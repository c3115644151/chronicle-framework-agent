using System;
using System.IO;
using System.Linq;
using TaleWorlds.CampaignSystem;
using TaleWorlds.Core;
using TaleWorlds.MountAndBlade;

namespace ChronicleFramework;

// Native lifecycle fixture only; no Agent action or ordinary-player entry.
internal static class AgentHostCampaignTransitionHarness
{
    private static int _stage;
    private static string _oldSession;
    private static bool _stageOneStateLogged;
    private static bool _saveStateListenerRegistered;

    internal static bool Tick()
    {
        if (Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE") != "agent-host-lifecycle-test" ||
            Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_AGENT_ROUNDTRIP") != "1" ||
            Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_AGENT_NO_MODEL") != "1") return false;
        var temp = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        var repository = Environment.GetEnvironmentVariable("CHRONICLE_REPOSITORY_ROOT");
        if (string.IsNullOrWhiteSpace(temp) || string.IsNullOrWhiteSpace(repository)) return false;
        var allowed = Path.GetFullPath(Path.Combine(repository, "Dev", "ChronicleFramework", "TestResults")) + Path.DirectorySeparatorChar;
        if (!(Path.GetFullPath(temp) + Path.DirectorySeparatorChar).StartsWith(allowed, StringComparison.OrdinalIgnoreCase)) return false;
        try
        {
            if (_stage == 0 && ChronicleAgentRuntimeController.IsHostRunning &&
                File.Exists(Path.Combine(temp, "CampaignRoundtrip.proceed")))
            {
                var map = SandBox.View.Map.MapScreen.Instance;
                var behavior = Campaign.Current?.GetCampaignBehavior<ChronicleCampaignBehavior>();
                if (map == null || behavior == null || Game.Current?.GameStateManager?.ActiveState?.GetType().Name != "MapState") return false;
                _oldSession = behavior.AgentRuntimeSessionId;
                _stage = 1;
                ChronicleDiagnostics.Write("harness-agent-campaign-end-request|entry=Native MapScreen.OnExit|oldSession=" + _oldSession);
                map.OnExit();
                return true;
            }
            if (_stage == 1 && Campaign.Current == null && !ChronicleAgentRuntimeController.OwnsHost)
            {
                var activeState = GameStateManager.Current?.ActiveState?.GetType().Name ?? "null";
                if (!_stageOneStateLogged)
                {
                    _stageOneStateLogged = true;
                    ChronicleDiagnostics.Write("harness-agent-campaign-end-state|gameCurrent=" + (Game.Current != null) + "|activeState=" + activeState);
                }
                if (activeState != "InitialState") return false;
                var roundtripSaveId = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_AGENT_ROUNDTRIP_SAVE_ID");
                var fixture = Guid.TryParseExact(roundtripSaveId, "N", out var parsedId) && parsedId != Guid.Empty
                    ? "ChronicleRT-" + parsedId.ToString("N")
                    : "AgentBridgeLifecycle";
                var save = MBSaveLoad.GetSaveFileWithName(fixture);
                if (save == null || SandBox.SandBoxSaveHelper.GetIsDisabledWithReason(save, out var reason))
                    throw new InvalidOperationException("The fixed lifecycle fixture is unavailable or disabled by Native save validation.");
                var moduleMismatches = SandBox.SandBoxSaveHelper.CheckMetaDataCompatibilityErrors(save.MetaData);
                if (moduleMismatches.Count > 0)
                {
                    var summary = string.Join(",", moduleMismatches.Select(item => item.ModuleId + ":" + item.Type));
                    Fail("fixture-module-compatibility-mismatch:" + summary);
                    return false;
                }
                SandBox.SandBoxSaveHelper.OnStateChange += OnNativeSaveStateChanged;
                _saveStateListenerRegistered = true;
                _stage = 2;
                ChronicleDiagnostics.Write("harness-agent-campaign-reload-request|entry=Native SandBoxSaveHelper.TryLoadSave|save=" + fixture);
                if (Game.Current != null)
                {
                    GameStateManager.Current.CleanStates(0);
                    GameStateManager.Current = Module.CurrentModule.GlobalGameStateManager;
                }
                SandBox.SandBoxSaveHelper.TryLoadSave(save, result =>
                {
                    MBSaveLoad.OnStartGame(result);
                    MBGameManager.StartNewGame(new SandBox.SandBoxGameManager(result));
                }, () => Fail("native-save-load-cancelled"));
                return true;
            }
            if (_stage == 2 && Campaign.Current != null && Game.Current?.GameStateManager?.ActiveState?.GetType().Name == "MapState")
            {
                var session = Campaign.Current.GetCampaignBehavior<ChronicleCampaignBehavior>()?.AgentRuntimeSessionId;
                if (string.IsNullOrWhiteSpace(session) || session == _oldSession) return false;
                _stage = 3;
                if (_saveStateListenerRegistered)
                {
                    SandBox.SandBoxSaveHelper.OnStateChange -= OnNativeSaveStateChanged;
                    _saveStateListenerRegistered = false;
                }
                ChronicleDiagnostics.Write("harness-agent-campaign-roundtrip-complete|oldSession=" + _oldSession + "|newSession=" + session);
            }
        }
        catch (Exception exception) { Fail(exception.GetType().Name); }
        return false;
    }

    private static void OnNativeSaveStateChanged(SandBox.SandBoxSaveHelper.SaveHelperState state)
    {
        ChronicleDiagnostics.Write("harness-agent-campaign-load-state|state=" + state);
        if (state == SandBox.SandBoxSaveHelper.SaveHelperState.Inquiry)
            Fail("native-save-helper-inquiry");
    }

    private static void Fail(string error)
    {
        _stage = 4;
        if (_saveStateListenerRegistered)
        {
            SandBox.SandBoxSaveHelper.OnStateChange -= OnNativeSaveStateChanged;
            _saveStateListenerRegistered = false;
        }
        ChronicleDiagnostics.Write("harness-agent-campaign-roundtrip-failed|error=" + error);
    }
}
