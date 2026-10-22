using System;
using System.Globalization;
using System.IO;
using System.Linq;
using SandBox;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.CharacterCreationContent;
using TaleWorlds.CampaignSystem.Conversation;
using TaleWorlds.CampaignSystem.GameState;
using TaleWorlds.CampaignSystem.Party;
using TaleWorlds.CampaignSystem.Settlements;
using TaleWorlds.Core;
using TaleWorlds.MountAndBlade;

namespace ChronicleFramework;

internal static class FreshCampaignHarness
{
    internal const string Mode = "fresh-campaign-renown";
    private static bool _armed;
    private static bool _storyMode;
    private static bool _startAttempted;
    private static bool _creationFailed;
    private static bool _issueProbeAttempted;
    private static bool _trainingFieldConversationStarted;
    private static bool _trainingFieldConversationFrameCaptured;
    private static DateTime _trainingFieldConversationStartedUtc;
    private static bool _tutorialSkipSelected;
    private static bool _tutorialSkipOptionVisible;
    private static bool _tutorialSkipOptionFrameCaptured;
    private static DateTime _tutorialSkipOptionVisibleUtc;
    private static bool _tutorialSkipConfirmationVisible;
    private static bool _tutorialSkipConfirmationFrameCaptured;
    private static DateTime _tutorialSkipConfirmationVisibleUtc;
    private static bool _tutorialSkipConfirmed;
    private static bool _storyModeReadyLogged;
    private static bool _storyModeSettledFrameLogged;
    private static bool _storyModeFailureLogged;
    private static DateTime _storyModeReadyObservedUtc;
    private static int _storyModeTrainingFieldAgentWaitTicks;
    private static int _lastProcessedStage = -1;

    internal static void ArmIfRequested()
    {
        var mode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        _armed = mode == Mode;
        _storyMode = _armed && Environment.GetEnvironmentVariable("CHRONICLE_FRESH_CAMPAIGN_STORYMODE") == "1";
        if (_armed) ChronicleDiagnostics.Write("fresh-campaign-harness-armed|save=none|gameMode=" + (_storyMode ? "storymode" : "sandbox"));
    }

    internal static void TryStartCampaign()
    {
        if (!_armed || _startAttempted || GameStateManager.Current == null) return;
        if (_storyMode)
        {
            var initialState = GameStateManager.Current.ActiveState as InitialState;
            if (initialState == null) return;
            _startAttempted = true;
            try
            {
                var storyModeOption = Module.CurrentModule.GetInitialStateOptions()
                    .FirstOrDefault(option => string.Equals(option.Id, "StoryModeNewGame", StringComparison.Ordinal));
                if (storyModeOption == null || (storyModeOption.IsHidden?.Invoke() ?? false) || storyModeOption.IsDisabledAndReason().Item1)
                    throw new InvalidOperationException("The original StoryModeNewGame menu option is absent, hidden, or disabled.");
                ChronicleDiagnostics.Write("fresh-campaign-start-requested|save=none|gameMode=storymode|entry=StoryModeNewGame");
                initialState.OnExecutedInitialStateOption(storyModeOption);
                storyModeOption.DoAction();
            }
            catch (Exception exception)
            {
                WriteFailure("storymode-menu-entry", exception);
            }
            return;
        }

        if (GameStateManager.Current.ActiveState is CharacterCreationState) return;

        _startAttempted = true;
        ChronicleDiagnostics.Write("fresh-campaign-start-requested|save=none|gameMode=sandbox");
        try
        {
            MBGameManager.StartNewGame(new SandBoxGameManager(() => new Campaign((CampaignGameMode)1)));
        }
        catch (Exception exception)
        {
            WriteFailure("start", exception);
        }
    }

    internal static void AdvanceCharacterCreation()
    {
        if (!_armed || _creationFailed) return;
        var activeState = GameStateManager.Current?.ActiveState;
        if (activeState is VideoPlaybackState intro && intro.CanUserSkip)
        {
            ChronicleDiagnostics.Write("fresh-campaign-intro-skipped|via=native-video-completion|mode=harness");
            intro.OnVideoFinished();
            return;
        }
        if (activeState is not CharacterCreationState state)
        {
            if (_storyMode)
            {
                TrySkipStoryModeTrainingField();
                LogStoryModeReadyIfVerified();
                return;
            }
            ProbeLocalIssueConversation();
            return;
        }

        var manager = state.CharacterCreationManager;
        var stageIndex = manager.GetIndexOfCurrentStage();
        if (stageIndex < 0 || stageIndex == _lastProcessedStage) return;
        _lastProcessedStage = stageIndex;

        try
        {
            var stage = manager.CurrentStage;
            ChronicleDiagnostics.Write($"fresh-campaign-stage|index={stageIndex}|type={stage?.GetType().Name ?? "null"}");

            if (stage is CharacterCreationCultureStage)
            {
                var vlandianCulture = Game.Current.ObjectManager.GetObject<CultureObject>("vlandia")
                    ?? throw new InvalidOperationException("Vlandian culture was not loaded.");
                manager.CharacterCreationContent.SetSelectedCulture(vlandianCulture, manager);
            }
            else if (stage is CharacterCreationNarrativeStage)
            {
                SelectNarrativeHistory(manager);
            }

            manager.NextStage();
        }
        catch (Exception exception)
        {
            _creationFailed = true;
            WriteFailure($"stage-{stageIndex}", exception);
        }
    }

    private static void SelectNarrativeHistory(CharacterCreationManager manager)
    {
        if (manager.CurrentMenu == null) manager.StartNarrativeStage();

        for (var menuCount = 0; menuCount <= manager.NarrativeMenus.Count; menuCount++)
        {
            var menu = manager.CurrentMenu
                ?? throw new InvalidOperationException("Narrative stage has no active menu.");
            var options = manager.GetSuitableNarrativeMenuOptions().ToArray();
            var selected = menu.StringId == "narrative_adulthood_menu"
                ? options.FirstOrDefault(option => option.StringId == "adulthood_defeated_enemy_option")
                : options.FirstOrDefault();

            if (selected == null)
                throw new InvalidOperationException($"No suitable native option for narrative menu '{menu.StringId}'.");

            manager.OnNarrativeMenuOptionSelected(selected);
            ChronicleDiagnostics.Write($"fresh-campaign-background-selected|menu={menu.StringId}|option={selected.StringId}");
            if (!manager.TrySwitchToNextMenu()) return;
        }

        throw new InvalidOperationException("Narrative menu chain exceeded its native menu count.");
    }

    internal static void ProbeLocalIssueConversation()
    {
        var mapState = GameStateManager.Current?.ActiveState as MapState;
        if (!_armed || _storyMode || _issueProbeAttempted || mapState == null) return;
        _issueProbeAttempted = true;

        try
        {
            var party = MobileParty.MainParty;
            var position = party.GetPosition2D;
            var radius = Math.Max(12f, party.SeeingRange);
            var candidate = Settlement.All
                .Where(settlement => settlement != null && settlement.IsActive && settlement.IsVisible)
                .SelectMany(settlement => settlement.Notables
                    .Where(hero => hero != null && hero.IsAlive && hero.IsNotable && hero.Issue != null && hero.Issue.IsOngoingWithoutQuest)
                    .Select(hero => new
                    {
                        Hero = hero,
                        Settlement = settlement,
                        Distance = Math.Sqrt(Math.Pow(position.X - settlement.GetPosition2D.X, 2) + Math.Pow(position.Y - settlement.GetPosition2D.Y, 2))
                    }))
                .Where(item => item.Distance <= radius)
                .OrderBy(item => item.Distance)
                .FirstOrDefault();

            if (candidate == null)
            {
                ChronicleDiagnostics.Write("fresh-campaign-issue-probe|status=skipped|reason=no-visible-local-issue");
                return;
            }

            var timeBefore = Campaign.Current.TimeControlMode.ToString();
            CampaignMapConversation.OpenConversation(
                new ConversationCharacterData(CharacterObject.PlayerCharacter, PartyBase.MainParty),
                new ConversationCharacterData(candidate.Hero.CharacterObject));

            var manager = Campaign.Current.ConversationManager;
            for (var continueCount = 0; manager.IsConversationInProgress && manager.CurOptions.Count == 0 && continueCount < 4; continueCount++)
                manager.ContinueConversation();

            var optionIds = manager.CurOptions.Select(option => option.Id).ToArray();
            if (optionIds.Contains("lord_meet_player_response1"))
            {
                manager.DoOption("lord_meet_player_response1");
                for (var continueCount = 0; manager.IsConversationInProgress && manager.CurOptions.Count == 0 && continueCount < 4; continueCount++)
                    manager.ContinueConversation();
                optionIds = manager.CurOptions.Select(option => option.Id).ToArray();
            }

            var issueOfferAvailable = optionIds.Contains("hero_give_issue");
            var issueBriefReached = false;
            var questAcceptanceAvailable = false;
            var issueOfferDenied = false;
            if (issueOfferAvailable)
            {
                manager.DoOption("hero_give_issue");
                for (var continueCount = 0; manager.IsConversationInProgress && manager.CurOptions.Count == 0 && continueCount < 4; continueCount++)
                    manager.ContinueConversation();
                var offerOptions = manager.CurOptions.Select(option => option.Id).ToArray();
                issueBriefReached = offerOptions.Contains("issue_explanation_player_response_pre_quest_solution") || offerOptions.Contains("issue_explanation_player_response_pre_lord_solution");
                questAcceptanceAvailable = offerOptions.Contains("issue_offer_player_accept_quest");
                issueOfferDenied = !issueBriefReached && offerOptions.Contains("hero_give_issue");
                optionIds = offerOptions;
            }

            ChronicleDiagnostics.Write($"fresh-campaign-issue-probe|status={(manager.IsConversationInProgress ? "opened" : "failed")}|settlement={candidate.Settlement.StringId}|heroId={candidate.Hero.StringId}|issueType={candidate.Hero.Issue.GetType().Name}|issueOfferOption={issueOfferAvailable}|issueBriefReached={issueBriefReached}|issueOfferDenied={issueOfferDenied}|questAcceptanceAvailable={questAcceptanceAvailable}|clockBefore={timeBefore}|clockAfter={Campaign.Current.TimeControlMode}|options={string.Join(",", optionIds)}");
        }
        catch (Exception exception)
        {
            WriteFailure("issue-conversation-probe", exception);
        }
    }

    private static void TrySkipStoryModeTrainingField()
    {
        if (!_armed || !_storyMode ||
            GameStateManager.Current?.ActiveState?.GetType().Name != "MissionState" ||
            Settlement.CurrentSettlement?.StringId != "tutorial_training_field" || Mission.Current == null || Mission.Current.MissionEnded)
            return;

        try
        {
            var mission = Mission.Current;
            var manager = Campaign.Current?.ConversationManager;
            if (manager == null) return;
            if (!manager.IsConversationInProgress)
            {
                if (_trainingFieldConversationStarted) return;
                var brotherAgent = mission.Agents.FirstOrDefault(agent => agent?.Character?.StringId == "tutorial_npc_brother");
                var playerAgent = mission.MainAgent;
                if (brotherAgent == null || playerAgent == null)
                {
                    _storyModeTrainingFieldAgentWaitTicks++;
                    if (_storyModeTrainingFieldAgentWaitTicks == 90)
                        ChronicleDiagnostics.Write("fresh-storymode-tutorial-skip|status=training-field-agents-not-ready|brother=" + (brotherAgent != null) + "|player=" + (playerAgent != null));
                    return;
                }
                manager.SetupAndStartMissionConversation(brotherAgent, playerAgent, false);
                _trainingFieldConversationStarted = true;
                _trainingFieldConversationStartedUtc = DateTime.UtcNow;
                ChronicleDiagnostics.Write("fresh-storymode-tutorial-skip|status=original-brother-conversation-started");
                return;
            }

            // Native state/options can change before the game has presented the new UI frame.
            // Leave each original dialogue state open for a short visual settle interval before
            // recording it or moving to the next original option.
            if (!_trainingFieldConversationFrameCaptured)
            {
                if (DateTime.UtcNow - _trainingFieldConversationStartedUtc < TimeSpan.FromSeconds(8)) return;
                CaptureStoryModeFrame("brother-conversation-start", "MissionState", "training_field");
                _trainingFieldConversationFrameCaptured = true;
                return;
            }

            if (_tutorialSkipOptionVisible && !_tutorialSkipOptionFrameCaptured)
            {
                if (DateTime.UtcNow - _tutorialSkipOptionVisibleUtc < TimeSpan.FromSeconds(8)) return;
                CaptureStoryModeFrame("tutorial-skip-option-visible", "MissionState", "training_field");
                _tutorialSkipOptionFrameCaptured = true;
                return;
            }

            if (_tutorialSkipConfirmationVisible && !_tutorialSkipConfirmationFrameCaptured)
            {
                if (DateTime.UtcNow - _tutorialSkipConfirmationVisibleUtc < TimeSpan.FromSeconds(8)) return;
                CaptureStoryModeFrame("tutorial-skip-confirmation-visible", "MissionState", "training_field");
                _tutorialSkipConfirmationFrameCaptured = true;
                return;
            }

            if (_tutorialSkipConfirmed)
            {
                if (manager.CurOptions.Count == 0) manager.ContinueConversation();
                else WriteStoryModeFailure("unexpected-options-after-original-skip-confirmation");
                return;
            }

            if (manager.CurOptions.Count == 0)
            {
                manager.ContinueConversation();
                return;
            }

            var requiredOptionId = _tutorialSkipSelected ? "end_tutorial_yes" : "player_answer_skip_tutorial";
            var requiredOption = manager.CurOptions.FirstOrDefault(option =>
                string.Equals(option.Id, requiredOptionId, StringComparison.Ordinal) && option.IsClickable);
            if (requiredOption.Id == requiredOptionId)
            {
                if (!_tutorialSkipSelected && !_tutorialSkipOptionVisible)
                {
                    _tutorialSkipOptionVisible = true;
                    _tutorialSkipOptionVisibleUtc = DateTime.UtcNow;
                    ChronicleDiagnostics.Write("fresh-storymode-tutorial-skip|status=original-skip-option-visible|option=player_answer_skip_tutorial");
                    return;
                }
                if (_tutorialSkipSelected && !_tutorialSkipConfirmationVisible)
                {
                    _tutorialSkipConfirmationVisible = true;
                    _tutorialSkipConfirmationVisibleUtc = DateTime.UtcNow;
                    ChronicleDiagnostics.Write("fresh-storymode-tutorial-skip|status=original-confirmation-visible|option=end_tutorial_yes");
                    return;
                }

                manager.DoOption(requiredOptionId);
                if (_tutorialSkipSelected)
                {
                    _tutorialSkipConfirmed = true;
                    ChronicleDiagnostics.Write("fresh-storymode-tutorial-skip|status=original-confirmation-selected|option=end_tutorial_yes");
                }
                else
                {
                    _tutorialSkipSelected = true;
                    ChronicleDiagnostics.Write("fresh-storymode-tutorial-skip|status=original-skip-selected|option=player_answer_skip_tutorial");
                }
                return;
            }

            WriteStoryModeFailure("expected-original-skip-option-not-clickable-ids=" + string.Join(",", manager.CurOptions.Select(option => option.Id)));
        }
        catch (Exception exception)
        {
            WriteStoryModeFailure("original-skip-conversation-failed-" + exception.GetType().Name);
        }
    }

    private static void LogStoryModeReadyIfVerified()
    {
        if (!_armed || !_storyMode || !_tutorialSkipConfirmed ||
            GameStateManager.Current?.ActiveState is not MapState || Campaign.Current == null)
            return;
        var activeQuest = Campaign.Current.QuestManager?.Quests.FirstOrDefault(quest =>
            string.Equals(quest.StringId, "rebuild_player_clan_storymode_quest", StringComparison.Ordinal) && quest.IsOngoing);
        if (activeQuest == null) return;

        if (!_storyModeReadyLogged)
        {
            _storyModeReadyLogged = true;
            _storyModeReadyObservedUtc = DateTime.UtcNow;
            var renown = Clan.PlayerClan?.Renown;
            var json = ChronicleAgentObserver.BuildSnapshotJson();
            CaptureStoryModeFrame("eyc-map-active", "MapState", string.Empty);
            ChronicleDiagnostics.Write("fresh-storymode-e2e-ready|quest=rebuild_player_clan_storymode_quest|mapState=MapState|renown=" +
                (renown?.ToString("F3", CultureInfo.InvariantCulture) ?? "null") + "|campaignDay=" + CampaignTime.Now.ToDays.ToString("F6", CultureInfo.InvariantCulture));
            ChronicleDiagnostics.Write("fresh-storymode-e2e-snapshot|json=" + json);
            return;
        }

        // The native campaign state can advance while the startup/video layer is still presenting.
        // Hold the disposable fixture in the same MapState briefly so the final visual capture can
        // prove that the rendered UI caught up instead of accepting another copy of the splash frame.
        if (!_storyModeSettledFrameLogged && DateTime.UtcNow - _storyModeReadyObservedUtc >= TimeSpan.FromSeconds(8))
        {
            _storyModeSettledFrameLogged = true;
            CaptureStoryModeFrame("eyc-map-render-settled", "MapState", string.Empty);
            ChronicleDiagnostics.Write("fresh-storymode-render-settled|gameState=MapState|campaignClock=" + Campaign.Current.TimeControlMode);
            if (string.Equals(Environment.GetEnvironmentVariable("CHRONICLE_FRESH_CAMPAIGN_START_AGENT"), "1", StringComparison.Ordinal))
            {
                Environment.SetEnvironmentVariable("CHRONICLE_HARNESS_MODE", "agent-host-lifecycle-test");
                ChronicleDiagnostics.Write("fresh-storymode-agent-autostart-armed|entry=existing-MCM-start|gameState=MapState");
            }
        }
    }

    private static void WriteStoryModeFailure(string reason)
    {
        if (_storyModeFailureLogged) return;
        _storyModeFailureLogged = true;
        ChronicleDiagnostics.Write("fresh-storymode-e2e-failed|reason=" + reason);
    }

    private static void CaptureStoryModeFrame(string name, string gameState, string menuId)
    {
        try
        {
            var configuredTempRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
            if (!_storyMode || string.IsNullOrWhiteSpace(configuredTempRoot))
                throw new InvalidOperationException("StoryMode native frame capture requires a scoped Harness temp directory.");
            var captureRoot = Path.GetFullPath(configuredTempRoot).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
            var fileName = "FreshStoryMode-" + name + ".bmp";
            var capturePath = Path.GetFullPath(Path.Combine(captureRoot, fileName));
            if (!capturePath.StartsWith(captureRoot, StringComparison.OrdinalIgnoreCase) || File.Exists(capturePath))
                throw new InvalidOperationException("StoryMode native frame path is unsafe or already exists.");
            TaleWorlds.Engine.Utilities.TakeScreenshot(capturePath);
            ChronicleDiagnostics.Write("fresh-storymode-frame-captured|name=" + name + "|file=" + fileName + "|gameState=" + gameState + "|menuId=" + menuId);
        }
        catch (Exception exception)
        {
            WriteStoryModeFailure("native-frame-" + name + "-" + exception.GetType().Name);
        }
    }

    private static void WriteFailure(string stage, Exception exception)
    {
        var detail = exception.ToString().Replace('\r', ' ').Replace('\n', ' ');
        ChronicleDiagnostics.Write($"fresh-campaign-failed|stage={stage}|detail={detail}");
    }
}
