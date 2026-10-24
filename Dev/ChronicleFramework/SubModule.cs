using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text;
using HarmonyLib;
using MCM.Abstractions;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.Party;
using TaleWorlds.CampaignSystem.Party.PartyComponents;
using TaleWorlds.CampaignSystem.Settlements;
using TaleWorlds.Core;
using TaleWorlds.Library;
using TaleWorlds.MountAndBlade;

namespace ChronicleFramework;

public sealed class SubModule : MBSubModuleBase
{
    private ChronicleCampaignBehavior _campaignBehavior;
    private bool _freshCampaignMusicWaitLogged;
    private bool _freshCampaignMusicReadyLogged;
    private bool _harnessMcmSettingsProbeCompleted;
    private float _harnessMcmSettingsProbeElapsed;
    private bool _harnessMcmSettingsWaitLogged;
    private object _harnessLastStartupVideoScreen;
    private bool _harnessAgentLifecycleStartRequested;
    private float _harnessAgentLifecycleStartDelay;
    private static bool _harnessFocusLossEscapeMenuGuardInstalled;
    private static bool _harnessFocusLossEscapeMenuGuardWaitLogged;

    protected override void OnSubModuleLoad()
    {
        base.OnSubModuleLoad();
        ChronicleDiagnostics.Write("submodule-load");
        if (Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE") == "smoke") ChronicleDiagnostics.Write("harness-smoke-mode-active");
        InstallCrashExceptionCaptureIfRequested();
        TryInstallHarnessFocusLossEscapeMenuGuard();
    }

    private static void InstallCrashExceptionCaptureIfRequested()
    {
        if (Environment.GetEnvironmentVariable("CHRONICLE_CAPTURE_CRASH_EXCEPTION") != "1") return;
        try
        {
            var reporterType = AccessTools.TypeByName("Bannerlord.ButterLib.ExceptionHandler.ExceptionReporter");
            var reportMethod = reporterType == null ? null : AccessTools.Method(reporterType, "Show", new[] { typeof(Exception) });
            if (reportMethod == null)
            {
                ChronicleDiagnostics.Write("crash-report-exception-capture-unavailable|reason=butterlib-show-not-found");
                return;
            }

            var capturePrefix = AccessTools.Method(typeof(SubModule), nameof(CaptureCrashExceptionBeforeReport));
            new Harmony("ChronicleFramework.HarnessCrashExceptionCapture").Patch(reportMethod, prefix: new HarmonyMethod(capturePrefix));
            ChronicleDiagnostics.Write("crash-report-exception-capture-installed");
        }
        catch (Exception exception)
        {
            ChronicleDiagnostics.Write($"crash-report-exception-capture-install-failed|type={exception.GetType().FullName}|message={exception.Message}");
        }
    }

    private static void TryInstallHarnessFocusLossEscapeMenuGuard()
    {
        if (_harnessFocusLossEscapeMenuGuardInstalled || !IsHarnessFocusLossEscapeMenuGuardMode()) return;
        var harnessTemp = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (string.IsNullOrWhiteSpace(harnessTemp) || !Directory.Exists(harnessTemp)) return;
        try
        {
            var managerType = AccessTools.TypeByName("SandBox.View.Map.MapViewsContainer");
            var nativeMethod = managerType == null ? null : AccessTools.Method(managerType, "IsOpeningEscapeMenuOnFocusChangeAllowedForAll", Type.EmptyTypes);
            if (nativeMethod == null)
            {
                if (!_harnessFocusLossEscapeMenuGuardWaitLogged)
                {
                    _harnessFocusLossEscapeMenuGuardWaitLogged = true;
                    ChronicleDiagnostics.Write("harness-focus-loss-escape-guard-wait|reason=native-map-views-container-not-loaded");
                }
                return;
            }

            var prefix = AccessTools.Method(typeof(SubModule), nameof(KeepNativeEscapeMenuClosedWhenHarnessLosesFocus));
            new Harmony("ChronicleFramework.HarnessFocusLossEscapeMenuGuard").Patch(nativeMethod, prefix: new HarmonyMethod(prefix));
            _harnessFocusLossEscapeMenuGuardInstalled = true;
            ChronicleDiagnostics.Write("harness-focus-loss-escape-guard-installed|scope=" + Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE"));
        }
        catch (Exception exception)
        {
            ChronicleDiagnostics.Write($"harness-focus-loss-escape-guard-install-failed|type={exception.GetType().FullName}|message={exception.Message}");
        }
    }

    private static bool KeepNativeEscapeMenuClosedWhenHarnessLosesFocus(ref bool __result)
    {
        if (!IsHarnessFocusLossEscapeMenuGuardMode()) return true;
        var harnessTemp = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (string.IsNullOrWhiteSpace(harnessTemp) || !Directory.Exists(harnessTemp)) return true;
        __result = false;
        return false;
    }

    private static bool IsHarnessFocusLossEscapeMenuGuardMode()
    {
        var mode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        return mode == "visual-capture" || mode == "agent-host-lifecycle-test" || mode == "fresh-campaign-renown";
    }

    internal static bool HarnessFocusLossEscapeMenuGuardInstalled => _harnessFocusLossEscapeMenuGuardInstalled;

    private static void CaptureCrashExceptionBeforeReport(Exception exception)
    {
        try
        {
            var outputDirectory = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
            if (string.IsNullOrWhiteSpace(outputDirectory)) return;
            Directory.CreateDirectory(outputDirectory);
            var outputPath = Path.Combine(outputDirectory, $"CrashException-{Process.GetCurrentProcess().Id}.txt");
            var exceptionText = exception?.ToString() ?? "<null exception>";
            var contents = $"CapturedUtc: {DateTime.UtcNow:O}{Environment.NewLine}Type: {exception?.GetType().FullName ?? "null"}{Environment.NewLine}{exceptionText}{Environment.NewLine}CampaignMusicContext: {DescribeCampaignMusicContext()}";
            File.WriteAllText(outputPath, contents, new System.Text.UTF8Encoding(false));
            ChronicleDiagnostics.Write($"crash-report-exception-captured|path={outputPath}|type={exception?.GetType().FullName ?? "null"}");
        }
        catch (Exception captureException)
        {
            ChronicleDiagnostics.Write($"crash-report-exception-capture-failed|type={captureException.GetType().FullName}|message={captureException.Message}");
        }
    }

    private static string DescribeCampaignMusicContext()
    {
        try
        {
            var managerType = typeof(MBMusicManager);
            var manager = MBMusicManager.Current;
            if (manager == null) return "manager=null";
            var initialized = managerType.GetField("_initialized", BindingFlags.Static | BindingFlags.NonPublic)?.GetValue(null);
            var campaignMode = managerType.GetField("_campaignMode", BindingFlags.Instance | BindingFlags.NonPublic)?.GetValue(manager);
            var handler = managerType.GetField("_campaignMusicHandler", BindingFlags.Instance | BindingFlags.NonPublic)?.GetValue(manager);
            var activeHandler = managerType.GetField("_activeMusicHandler", BindingFlags.Instance | BindingFlags.NonPublic)?.GetValue(manager);
            var culture = "handler-unavailable";
            if (handler != null)
            {
                var getNearbyCulture = handler.GetType().GetMethod("GetNearbyCulture", BindingFlags.Instance | BindingFlags.NonPublic);
                var nearbyCulture = getNearbyCulture?.Invoke(handler, null) as TaleWorlds.Core.BasicCultureObject;
                culture = nearbyCulture?.StringId ?? "null";
            }
            var playerCulture = TaleWorlds.CampaignSystem.Clan.PlayerClan?.Culture?.StringId ?? "null";
            var settlementCount = TaleWorlds.CampaignSystem.Campaign.Current?.Settlements?.Count ?? -1;
            return $"manager=present|initialized={initialized}|campaignMode={(campaignMode != null)}|campaignHandler={(handler != null)}|activeHandler={(activeHandler != null)}|nearbyCulture={culture}|playerCulture={playerCulture}|settlements={settlementCount}";
        }
        catch (Exception exception)
        {
            return $"context-capture-failed:{exception.GetType().FullName}:{exception.Message}";
        }
    }

    protected override void OnBeforeInitialModuleScreenSetAsRoot()
    {
        base.OnBeforeInitialModuleScreenSetAsRoot();
        FreshCampaignHarness.ArmIfRequested();
        if (Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE") == "smoke")
        {
            _harnessMcmSettingsProbeElapsed = 15f;
            ProbeHarnessMcmSettingsRegistration(0f);
        }
    }

    protected override void OnGameStart(Game game, IGameStarter gameStarterObject)
    {
        base.OnGameStart(game, gameStarterObject);
        ChronicleDiagnostics.Write("game-start");
        if (gameStarterObject is CampaignGameStarter campaignGameStarter)
        {
            _campaignBehavior = new ChronicleCampaignBehavior();
            campaignGameStarter.AddBehavior(_campaignBehavior);
            ChronicleDiagnostics.Write("campaign-behavior-registered");
        }
    }

    protected override void OnApplicationTick(float dt)
    {
        base.OnApplicationTick(dt);
        TrySkipHarnessStartupVideo();
        ChronicleAgentRuntimeController.Tick();
        if (AgentHostCampaignTransitionHarness.Tick()) return;
        var harnessStartState = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_AGENT_START_STATE") == "InventoryState" ? "InventoryState" : "MapState";
        if (!_harnessAgentLifecycleStartRequested &&
            Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE") == "agent-host-lifecycle-test" &&
            Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_AGENT_AUTO_START") == "1" &&
            Campaign.Current != null && Game.Current?.GameStateManager?.ActiveState?.GetType().Name == harnessStartState)
        {
            _harnessAgentLifecycleStartDelay += dt;
            if (_harnessAgentLifecycleStartDelay >= 2.5f)
            {
                _harnessAgentLifecycleStartRequested = true;
                ChronicleDiagnostics.Write("harness-agent-lifecycle-auto-start");
                  if (harnessStartState != "MapState" || ChronicleAgentRuntimeController.ProbeHarnessStartRejections())
                      ChronicleAgentProviderSettings.Instance?.StartAgent?.Invoke();
            }
        }
        ProbeHarnessMcmSettingsRegistration(dt);
        TryInstallHarnessFocusLossEscapeMenuGuard();
        if (Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE") == FreshCampaignHarness.Mode && !IsNativeCampaignMusicInitialized())
        {
            if (!_freshCampaignMusicWaitLogged)
            {
                _freshCampaignMusicWaitLogged = true;
                ChronicleDiagnostics.Write("fresh-campaign-start-wait|reason=native-campaign-music-not-initialized");
            }
            return;
        }
        if (Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE") == FreshCampaignHarness.Mode && !_freshCampaignMusicReadyLogged)
        {
            _freshCampaignMusicReadyLogged = true;
            ChronicleDiagnostics.Write("fresh-campaign-start-ready|nativeCampaignMusicInitialized=True");
        }
        FreshCampaignHarness.TryStartCampaign();
        var skipProgressionIssueProbe = Environment.GetEnvironmentVariable("CHRONICLE_FRESH_CAMPAIGN_SKIP_ISSUE_PROBE") == "1" &&
            Game.Current?.GameStateManager?.ActiveState?.GetType().Name == "MapState";
        if (!skipProgressionIssueProbe) FreshCampaignHarness.AdvanceCharacterCreation();
        var activeCampaignBehavior = Campaign.Current?.CampaignBehaviorManager?.GetBehavior<ChronicleCampaignBehavior>();
        if (activeCampaignBehavior != null && !ReferenceEquals(activeCampaignBehavior, _campaignBehavior))
        {
            _campaignBehavior = activeCampaignBehavior;
            ChronicleDiagnostics.Write("campaign-agent-behavior-rebound|reason=current-campaign");
        }
        _campaignBehavior?.PollAgentProtocol();
    }

    private static bool IsNativeCampaignMusicInitialized()
    {
        try
        {
            if (!MBMusicManager.IsCreationCompleted() || MBMusicManager.Current == null) return false;
            var initializedField = typeof(MBMusicManager).GetField("_initialized", BindingFlags.Static | BindingFlags.NonPublic);
            return initializedField != null && initializedField.GetValue(null) is bool initialized && initialized;
        }
        catch
        {
            return false;
        }
    }

    private void ProbeHarnessMcmSettingsRegistration(float dt)
    {
        if (_harnessMcmSettingsProbeCompleted || Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE") != "smoke") return;
        _harnessMcmSettingsProbeElapsed += dt;
        try
        {
            var settingsProvider = BaseSettingsProvider.Instance;
            var settings = settingsProvider?.GetSettings("ChronicleAgentSettings") as ChronicleAgentProviderSettings;
            var definition = settingsProvider?.SettingsDefinitions.FirstOrDefault(item => item.SettingsId == "ChronicleAgentSettings");
            if (settings == null || definition == null)
            {
                if (!_harnessMcmSettingsWaitLogged && _harnessMcmSettingsProbeElapsed >= 30f)
                {
                    _harnessMcmSettingsWaitLogged = true;
                    ChronicleDiagnostics.Write("harness-mcm-settings-wait|reason=registration-not-ready");
                }
                return;
            }

            var propertyIds = definition?.SettingPropertyGroups
                .SelectMany(group => group.SettingProperties)
                .Select(property => property.Id)
                .OrderBy(id => id, StringComparer.Ordinal)
                .ToArray() ?? Array.Empty<string>();
            var validationButtonType = definition?.SettingPropertyGroups
                .SelectMany(group => group.SettingProperties)
                .FirstOrDefault(property => property.Id == "ValidateLocalConfiguration")?.SettingType.ToString() ?? "missing";
            var buttonPropertyIds = definition?.SettingPropertyGroups
                .SelectMany(group => group.SettingProperties)
                .Where(property => property.SettingType.ToString() == "Button")
                .Select(property => property.Id)
                .OrderBy(id => id, StringComparer.Ordinal)
                .ToArray() ?? Array.Empty<string>();
            ChronicleDiagnostics.Write($"harness-mcm-settings|loaded={(settings != null)}|definition={(definition != null)}|propertyIds={string.Join(",", propertyIds)}|buttonPropertyIds={string.Join(",", buttonPropertyIds)}|validationButtonType={validationButtonType}");
            _harnessMcmSettingsProbeCompleted = true;
        }
        catch (Exception exception)
        {
            ChronicleDiagnostics.Write($"harness-mcm-settings-probe-failed|type={exception.GetType().FullName}|message={exception.Message}");
            _harnessMcmSettingsProbeCompleted = true;
        }
    }

    private void TrySkipHarnessStartupVideo()
    {
        var mode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        if ((mode != "smoke" && mode != "agent-host-lifecycle-test") || Campaign.Current != null) return;
        var screen = TaleWorlds.ScreenSystem.ScreenManager.TopScreen;
        if (screen == null || ReferenceEquals(screen, _harnessLastStartupVideoScreen) ||
            screen.GetType().FullName != "TaleWorlds.MountAndBlade.GauntletUI.GauntletVideoPlaybackScreen") return;
        try
        {
            var screenType = typeof(TaleWorlds.MountAndBlade.View.Screens.VideoPlaybackScreen);
            var state = screenType.GetField("_videoPlaybackState", BindingFlags.NonPublic | BindingFlags.Instance)?.GetValue(screen) as VideoPlaybackState;
            var player = screenType.GetField("_videoPlayerView", BindingFlags.NonPublic | BindingFlags.Instance)?.GetValue(screen) as TaleWorlds.Engine.VideoPlayerView;
            if (state == null || !state.CanUserSkip || player == null) return;
            player.StopVideo();
            _harnessLastStartupVideoScreen = screen;
            ChronicleDiagnostics.Write("harness-startup-video-skipped|entry=Native CanUserSkip StopVideo|video=" + Path.GetFileName(state.VideoPath));
        }
        catch (Exception exception)
        {
            _harnessLastStartupVideoScreen = screen;
            ChronicleDiagnostics.Write("harness-startup-video-skip-failed|type=" + exception.GetType().Name);
        }
    }

    protected override void OnSubModuleUnloaded()
    {
        ChronicleDiagnostics.Write("submodule-unload");
        ChronicleAgentRuntimeController.StopForSubModuleUnload();
        base.OnSubModuleUnloaded();
    }
}

internal sealed class ChronicleCampaignBehavior : CampaignBehaviorBase
{
    private const string HarnessModeVariable = "CHRONICLE_HARNESS_MODE";
    private const string HarnessSaveNameVariable = "CHRONICLE_HARNESS_SAVE_NAME";
    private int _stateVersion = 1;
    private int _dailyTickCount;
    private double _lastDailyTickDay;
    private string _agentCampaignInstanceId = string.Empty;
    private readonly string _agentRuntimeSessionId = Guid.NewGuid().ToString("N");
    private string _agentCheckpointJson = string.Empty;
    private bool _harnessSaveRequested;
    private bool _harnessTimeControlApplied;
    private bool _campaignActorThinkTraceCaptured;
    private float _campaignActorThinkTraceScanElapsed;
    private bool _freshProgressionSavePending;
    private bool _freshProgressionCampaignPollLogged;
    private ChronicleAgentProtocol _agentProtocol;

    internal int DailyTickCount => _dailyTickCount;
    internal string AgentRuntimeSessionId => _agentRuntimeSessionId;
    internal bool AgentProtocolReady => _agentProtocol != null;
    internal void PollAgentProtocol() => _agentProtocol?.Poll(this);
    internal string AgentCampaignInstanceId
    {
        get
        {
            if (string.IsNullOrWhiteSpace(_agentCampaignInstanceId)) _agentCampaignInstanceId = Guid.NewGuid().ToString("N");
            return _agentCampaignInstanceId;
        }
    }
    internal string AgentCheckpointJson => _agentCheckpointJson ?? string.Empty;

    internal string BuildAgentCheckpointDataJson()
    {
        var checkpointBase64 = Convert.ToBase64String(Encoding.UTF8.GetBytes(AgentCheckpointJson));
        return "{\"campaignInstanceId\":\"" + EscapeJsonString(AgentCampaignInstanceId) + "\",\"checkpointBase64\":\"" + checkpointBase64 + "\"}";
    }

    internal void StoreAgentCheckpoint(string campaignInstanceId, string checkpointJson)
    {
        if (string.IsNullOrWhiteSpace(campaignInstanceId) || !string.Equals(campaignInstanceId, AgentCampaignInstanceId, StringComparison.Ordinal))
            throw new InvalidOperationException("Checkpoint Campaign identity does not match the active Campaign save.");
        if (string.IsNullOrWhiteSpace(checkpointJson) || checkpointJson.Length > 65536 || checkpointJson[0] != '{' || checkpointJson[checkpointJson.Length - 1] != '}')
            throw new InvalidOperationException("Checkpoint payload is empty, oversized, or not a JSON object.");
        _agentCheckpointJson = checkpointJson;
    }

    private static string EscapeJsonString(string value)
    {
        return (value ?? string.Empty).Replace("\\", "\\\\").Replace("\"", "\\\"");
    }

    public override void RegisterEvents()
    {
        _agentProtocol = new ChronicleAgentProtocol();
        CampaignEvents.DailyTickEvent.AddNonSerializedListener(this, OnDailyTick);
        CampaignEvents.TickEvent.AddNonSerializedListener(this, OnCampaignTick);
        CampaignEvents.OnGameLoadedEvent.AddNonSerializedListener(this, OnGameLoaded);
        CampaignEvents.OnSaveOverEvent.AddNonSerializedListener(this, OnSaveOver);
        if (Environment.GetEnvironmentVariable(HarnessModeVariable) == FreshCampaignHarness.Mode)
            CampaignEvents.OnCharacterCreationIsOverEvent.AddNonSerializedListener(this, OnFreshCharacterCreationFinished);
    }

    private void CaptureCampaignActorThink(MobileParty party, PartyThinkParams thinkParams)
    {
        if (_campaignActorThinkTraceCaptured || party == null || thinkParams == null) return;

        var hero = party.LeaderHero;
        if (hero == null || hero == Hero.MainHero || hero.Clan == null || !hero.IsAlive || hero.IsPrisoner ||
            !party.IsActive || !party.IsLordParty || hero.PartyBelongedTo != party) return;

        var requestedHeroId = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_ACTOR_HERO_ID");
        if (!string.IsNullOrWhiteSpace(requestedHeroId) && !string.Equals(hero.StringId, requestedHeroId, StringComparison.Ordinal)) return;

        var candidateCount = thinkParams.AIBehaviorScores.Count;
        if (candidateCount == 0) return;
        _campaignActorThinkTraceCaptured = true;
        var candidates = string.Join(",", thinkParams.AIBehaviorScores.Select(item =>
        {
            var data = item.Item1;
            var target = data.Party is MobileParty targetParty
                ? "party:" + targetParty.StringId
                : data.Party is Settlement targetSettlement
                    ? "settlement:" + targetSettlement.StringId
                    : data.Party != null
                        ? "mapPoint:" + data.Party.GetType().Name + ":" + (data.Party.Name?.ToString() ?? "unnamed")
                        : "position:" + data.Position.X.ToString("F3", CultureInfo.InvariantCulture) + "," + data.Position.Y.ToString("F3", CultureInfo.InvariantCulture) + ",onLand=" + data.Position.IsOnLand;
            return data.AiBehavior + ":" + target + ":score=" + item.Item2.ToString("F3", CultureInfo.InvariantCulture) +
                ":gatherArmy=" + data.WillGatherArmy + ":navigation=" + data.NavigationType + ":fromPort=" + data.IsFromPort + ":toPort=" + data.IsTargetingPort;
        }));
        var campaign = Campaign.Current;
        var state = Game.Current?.GameStateManager?.ActiveState?.GetType().Name ?? "null";
        var currentPosition = party.GetPosition2D;
        var currentTarget = party.TargetSettlement != null
            ? "settlement:" + party.TargetSettlement.StringId
            : party.TargetParty != null
                ? "party:" + party.TargetParty.StringId
                : "none";
        ChronicleDiagnostics.Write(
            $"campaign-actor-think-trace|trace={Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_ACTOR_TRACE_ID") ?? "unscoped"}|source=MobileParty.ThinkParamsCache|actorHeroId={hero.StringId}|partyId={party.StringId}|clanId={hero.Clan.StringId}|mainHeroId={Hero.MainHero?.StringId ?? "null"}|heroAlive={hero.IsAlive}|heroPrisoner={hero.IsPrisoner}|partyActive={party.IsActive}|partyIsLord={party.IsLordParty}|partyLeaderMatchesHero={hero.PartyBelongedTo == party}|thinkPartyMatches={thinkParams.MobilePartyOf == party}|partyBehavior={party.DefaultBehavior}|currentTarget={currentTarget}|currentPosition={currentPosition.X.ToString("F3", CultureInfo.InvariantCulture)},{currentPosition.Y.ToString("F3", CultureInfo.InvariantCulture)}|aiDisabled={party.Ai.IsDisabled}|aiDoNotMakeNewDecisions={party.Ai.DoNotMakeNewDecisions}|doNotChangeBehavior={thinkParams.DoNotChangeBehavior}|currentObjective={thinkParams.CurrentObjectiveValue.ToString("F3", CultureInfo.InvariantCulture)}|candidateCount={candidateCount}|candidates={candidates}|campaignDay={CampaignTime.Now.ToDays.ToString("F6", CultureInfo.InvariantCulture)}|timeControl={campaign?.TimeControlMode.ToString() ?? "null"}|gameState={state}|writeMode=read-only");
    }

    private void OnFreshCharacterCreationFinished()
    {
        var renown = Clan.PlayerClan?.Renown;
        var renownText = renown?.ToString("F3", CultureInfo.InvariantCulture) ?? "null";
        var tierText = Clan.PlayerClan?.Tier.ToString() ?? "null";
        var clockText = Campaign.Current?.TimeControlMode.ToString() ?? "null";
        var stateText = Game.Current?.GameStateManager?.ActiveState?.GetType().Name ?? "null";
        ChronicleDiagnostics.Write($"fresh-campaign-character-creation-complete|renown={renownText}|tier={tierText}|clock={clockText}|mapState={stateText}");
        ChronicleDiagnostics.Write($"fresh-campaign-snapshot|json={ChronicleAgentObserver.BuildSnapshotJson()}");
        try
        {
            var party = MobileParty.MainParty;
            var position = party.GetPosition2D;
            var radius = Math.Max(12f, party.SeeingRange);
            var visibleIssueCounts = Settlement.All
                .Where(settlement => settlement != null && settlement.IsActive && settlement.IsVisible)
                .Select(settlement => new
                {
                    Settlement = settlement,
                    Distance = Math.Sqrt(Math.Pow(position.X - settlement.GetPosition2D.X, 2) + Math.Pow(position.Y - settlement.GetPosition2D.Y, 2))
                })
                .Where(item => item.Distance <= radius)
                .OrderBy(item => item.Distance)
                .Take(8)
                .Select(item =>
                {
                    var issueTypes = item.Settlement.Notables
                        .Where(hero => hero != null && hero.Issue != null && hero.Issue.IsOngoingWithoutQuest)
                        .Select(hero => hero.Issue.GetType().Name);
                    return item.Settlement.StringId + ":" + string.Join("+", issueTypes);
                });
            ChronicleDiagnostics.Write("fresh-campaign-visible-issues|settlements=" + string.Join(",", visibleIssueCounts));
            if (Environment.GetEnvironmentVariable("CHRONICLE_FRESH_CAMPAIGN_SKIP_ISSUE_PROBE") == "1")
                ChronicleDiagnostics.Write("fresh-campaign-issue-probe|status=skipped|reason=progression-test-mode");
            else
                FreshCampaignHarness.ProbeLocalIssueConversation();
        }
        catch (Exception exception)
        {
            var detail = exception.ToString().Replace('\r', ' ').Replace('\n', ' ');
            ChronicleDiagnostics.Write("fresh-campaign-issue-probe-failed|detail=" + detail);
        }

        var disposableSaveName = Environment.GetEnvironmentVariable("CHRONICLE_FRESH_CAMPAIGN_SAVE_NAME");
        if (Environment.GetEnvironmentVariable(HarnessModeVariable) == FreshCampaignHarness.Mode && !string.IsNullOrWhiteSpace(disposableSaveName))
        {
            try
            {
                _freshProgressionSavePending = true;
                ChronicleDiagnostics.Write($"fresh-campaign-disposable-save-scheduled|name={disposableSaveName}|via=CampaignTick");
            }
            catch (Exception exception)
            {
                var detail = exception.ToString().Replace('\r', ' ').Replace('\n', ' ');
                ChronicleDiagnostics.Write($"fresh-campaign-failed|stage=disposable-save|detail={detail}");
            }
        }
    }

    public override void SyncData(IDataStore dataStore)
    {
        dataStore.SyncData("chronicle_state_version", ref _stateVersion);
        dataStore.SyncData("chronicle_daily_tick_count", ref _dailyTickCount);
        dataStore.SyncData("chronicle_last_daily_tick_day", ref _lastDailyTickDay);
        dataStore.SyncData("chronicle_agent_campaign_instance_v1", ref _agentCampaignInstanceId);
        dataStore.SyncData("chronicle_agent_checkpoint_json_v1", ref _agentCheckpointJson);
        var mode = dataStore.IsSaving ? "save" : dataStore.IsLoading ? "load" : "unknown";
        ChronicleDiagnostics.Write($"campaign-sync|mode={mode}|version={_stateVersion}|count={_dailyTickCount}|day={_lastDailyTickDay:F3}|agentCampaignIdPresent={!string.IsNullOrWhiteSpace(_agentCampaignInstanceId)}|agentCheckpointChars={(_agentCheckpointJson ?? string.Empty).Length}");
    }

    private void OnDailyTick()
    {
        _dailyTickCount++;
        _lastDailyTickDay = CampaignTime.Now.ToDays;
        ChronicleDiagnostics.Write($"campaign-daily-tick|version={_stateVersion}|count={_dailyTickCount}|day={_lastDailyTickDay:F3}");

        if (Environment.GetEnvironmentVariable(HarnessModeVariable) == "advance-save" && !_harnessSaveRequested)
        {
            var saveName = Environment.GetEnvironmentVariable(HarnessSaveNameVariable);
            if (!string.IsNullOrWhiteSpace(saveName))
            {
                _harnessSaveRequested = true;
                Campaign.Current.SaveHandler.SaveAs(saveName);
                Campaign.Current.TimeControlMode = CampaignTimeControlMode.Stop;
                ChronicleDiagnostics.Write($"campaign-save-requested|name={saveName}|count={_dailyTickCount}|day={_lastDailyTickDay:F3}");
            }
        }
    }

    private void OnGameLoaded(CampaignGameStarter campaignGameStarter)
    {
        var harnessMode = Environment.GetEnvironmentVariable(HarnessModeVariable);
        ChronicleDiagnostics.Write($"campaign-loaded|mode={harnessMode ?? "normal"}|version={_stateVersion}|count={_dailyTickCount}|day={_lastDailyTickDay:F3}");
        if (harnessMode == "battle-fixture" || harnessMode == "visual-battle-fixture")
            CreateDisposableBattleFixture(harnessMode == "visual-battle-fixture");
    }

    private static void CreateDisposableBattleFixture(bool seedItemLoot)
    {
        try
        {
            var mainParty = MobileParty.MainParty;
            if (mainParty == null || mainParty.MapEvent != null) throw new InvalidOperationException("Main party is unavailable or already in a map event.");
            if (MobileParty.All.Any(party => party != null && party.StringId == "chronicle_harness_looters"))
                throw new InvalidOperationException("Disposable battle fixture party ID already exists.");

            // Test-fixture isolation only: begin from a stopped disposable world; runtime Agent actions do not do this.
            Campaign.Current.TimeControlMode = CampaignTimeControlMode.Stop;

            var hostileClan = Clan.BanditFactions.FirstOrDefault(clan => FactionManager.IsAtWarAgainstFaction(mainParty.MapFaction, clan));
            var partyTemplate = Game.Current.ObjectManager.GetObject<PartyTemplateObject>("looters_template");
            var looterCharacter = Game.Current.ObjectManager.GetObject<CharacterObject>("looter");
            var testRecruit = Game.Current.ObjectManager.GetObject<CharacterObject>("vlandian_recruit");
            var testLootItem = seedItemLoot ? Game.Current.ObjectManager.GetObject<ItemObject>("wool") : null;
            var homeSettlement = Settlement.All.Where(settlement => settlement != null && settlement.IsActive)
                .OrderBy(settlement => mainParty.Position.Distance(settlement.Position)).FirstOrDefault();
            if (hostileClan == null || partyTemplate == null || looterCharacter == null || testRecruit == null || homeSettlement == null || (seedItemLoot && testLootItem == null))
                throw new InvalidOperationException("Native hostile clan, looter template or home settlement is unavailable.");

            mainParty.MemberRoster.AddToCounts(testRecruit, 19, insertAtFront: false, woundedCount: 0, xpChange: 0, removeDepleted: true, index: -1);

            var enemyParty = BanditPartyComponent.CreateLooterParty(
                "chronicle_harness_looters", hostileClan, homeSettlement, false, partyTemplate, mainParty.Position + new Vec2(0.5f, 0f));
            enemyParty.MemberRoster.Clear();
            enemyParty.MemberRoster.AddToCounts(looterCharacter, 19, insertAtFront: false, woundedCount: 0, xpChange: 0, removeDepleted: true, index: -1);
            enemyParty.SetMoveEngageParty(mainParty, MobileParty.NavigationType.Default);
            ChronicleDiagnostics.Write($"battle-fixture-ready|party={enemyParty.StringId}|hostile={FactionManager.IsAtWarAgainstFaction(mainParty.MapFaction, enemyParty.MapFaction)}|enemyCount={enemyParty.MemberRoster.TotalManCount}|playerCount={mainParty.MemberRoster.TotalManCount}|lootFixtureEnabled={seedItemLoot}|lootFixtureItemId={testLootItem?.StringId}|playerMode={mainParty.DefaultBehavior}|clock={Campaign.Current.TimeControlMode}");
        }
        catch (Exception exception)
        {
            var detail = exception.ToString().Replace('\r', ' ').Replace('\n', ' ');
            ChronicleDiagnostics.Write($"battle-fixture-failed|{detail}");
        }
    }

    private void OnCampaignTick(float deltaTime)
    {
        if (Environment.GetEnvironmentVariable(HarnessModeVariable) == "campaign-actor-think-trace" && !_campaignActorThinkTraceCaptured)
        {
            _campaignActorThinkTraceScanElapsed += deltaTime;
            if (_campaignActorThinkTraceScanElapsed >= 1f)
            {
                _campaignActorThinkTraceScanElapsed = 0f;
                foreach (var candidate in MobileParty.All)
                {
                    var thinkParams = candidate?.ThinkParamsCache;
                    if (candidate == null || candidate == MobileParty.MainParty || !candidate.IsActive || !candidate.IsLordParty ||
                        candidate.LeaderHero == null || thinkParams == null || thinkParams.MobilePartyOf != candidate || thinkParams.AIBehaviorScores.Count == 0) continue;
                    CaptureCampaignActorThink(candidate, thinkParams);
                    if (_campaignActorThinkTraceCaptured) break;
                }
            }
        }

        if (Environment.GetEnvironmentVariable(HarnessModeVariable) == FreshCampaignHarness.Mode && _freshProgressionSavePending)
        {
            var freshSaveName = Environment.GetEnvironmentVariable("CHRONICLE_FRESH_CAMPAIGN_SAVE_NAME");
            if (!string.IsNullOrWhiteSpace(freshSaveName))
            {
                try
                {
                    _freshProgressionSavePending = false;
                    Campaign.Current.SaveHandler.SaveAs(freshSaveName);
                    ChronicleDiagnostics.Write($"fresh-campaign-disposable-save-requested|name={freshSaveName}|via=CampaignTick");
                }
                catch (Exception exception)
                {
                    var detail = exception.ToString().Replace('\r', ' ').Replace('\n', ' ');
                    ChronicleDiagnostics.Write($"fresh-campaign-failed|stage=campaign-tick-save|detail={detail}");
                }
            }
        }
        if (Environment.GetEnvironmentVariable(HarnessModeVariable) == FreshCampaignHarness.Mode &&
            !string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("CHRONICLE_FRESH_CAMPAIGN_SAVE_NAME")))
        {
            if (!_freshProgressionCampaignPollLogged)
            {
                _freshProgressionCampaignPollLogged = true;
                ChronicleDiagnostics.Write($"fresh-campaign-progression-campaign-tick|mode={Campaign.Current.TimeControlMode}");
            }
            _agentProtocol?.Poll(this);
        }
        if (Environment.GetEnvironmentVariable(HarnessModeVariable) == "advance-save" && !_harnessSaveRequested)
        {
            Campaign.Current.TimeControlMode = CampaignTimeControlMode.UnstoppableFastForward;
            if (!_harnessTimeControlApplied)
            {
                _harnessTimeControlApplied = true;
                ChronicleDiagnostics.Write("campaign-time-control|mode=unstoppable-fast-forward");
            }
        }
    }

    private void OnSaveOver(bool successful, string saveName)
    {
        var disposableSaveName = Environment.GetEnvironmentVariable("CHRONICLE_FRESH_CAMPAIGN_SAVE_NAME");
        if (Environment.GetEnvironmentVariable(HarnessModeVariable) == FreshCampaignHarness.Mode && !string.IsNullOrWhiteSpace(disposableSaveName) &&
            string.Equals(Path.GetFileNameWithoutExtension(saveName), Path.GetFileNameWithoutExtension(disposableSaveName), StringComparison.Ordinal))
            ChronicleDiagnostics.Write($"fresh-campaign-disposable-save-complete|name={disposableSaveName}|successful={successful}");
        _agentProtocol?.OnSaveOver(successful, saveName, this);
    }
}

internal static class ChronicleDiagnostics
{
    private static readonly object WriteLock = new object();

    internal static void Write(string lifecyclePoint)
    {
        try
        {
            var documentsPath = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
            var logDirectory = Path.Combine(documentsPath, "Mount and Blade II Bannerlord", "Configs", "ModLogs");
            Directory.CreateDirectory(logDirectory);
            var message = $"{DateTime.UtcNow:O}|pid={Process.GetCurrentProcess().Id}|{lifecyclePoint}{Environment.NewLine}";

            lock (WriteLock)
            {
                File.AppendAllText(Path.Combine(logDirectory, "chronicle-framework.log"), message);
            }
        }
        catch
        {
        }
    }
}
