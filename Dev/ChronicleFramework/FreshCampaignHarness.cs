using System;
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
    private static bool _startAttempted;
    private static bool _creationFailed;
    private static bool _issueProbeAttempted;
    private static int _lastProcessedStage = -1;

    internal static void ArmIfRequested()
    {
        _armed = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE") == Mode;
        if (_armed) ChronicleDiagnostics.Write("fresh-campaign-harness-armed|save=none|gameMode=sandbox");
    }

    internal static void TryStartCampaign()
    {
        if (!_armed || _startAttempted || GameStateManager.Current == null) return;
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
        if (!_armed || _issueProbeAttempted || mapState == null) return;
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

    private static void WriteFailure(string stage, Exception exception)
    {
        var detail = exception.ToString().Replace('\r', ' ').Replace('\n', ' ');
        ChronicleDiagnostics.Write($"fresh-campaign-failed|stage={stage}|detail={detail}");
    }
}
