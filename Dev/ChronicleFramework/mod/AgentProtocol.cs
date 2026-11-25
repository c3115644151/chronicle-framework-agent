using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using SandBox;
using SandBox.View.Map;
using SandBox.View.Map.Managers;
using SandBox.View.Map.Visuals;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.Encounters;
using TaleWorlds.CampaignSystem.GameState;
using TaleWorlds.CampaignSystem.GameMenus;
using TaleWorlds.CampaignSystem.Issues;
using TaleWorlds.CampaignSystem.MapEvents;
using TaleWorlds.CampaignSystem.Party;
using TaleWorlds.CampaignSystem.Settlements;
using TaleWorlds.CampaignSystem.Settlements.Locations;
using TaleWorlds.CampaignSystem.ViewModelCollection.GameMenu.Recruitment;
using TaleWorlds.CampaignSystem.ViewModelCollection.GameMenu.Events;
using TaleWorlds.Core;
using TaleWorlds.InputSystem;
using TaleWorlds.MountAndBlade;
using TaleWorlds.MountAndBlade.View.MissionViews;
using EngineTime = TaleWorlds.Engine.Time;

namespace ChronicleFramework;

internal sealed partial class ChronicleAgentProtocol
{
    private static ChronicleAgentProtocol _activeInstance;
    private static bool _unexpectedProtocolFailureFrameCaptured;
    private readonly string _root;
    private readonly string _responseRoot;
    private string _lastCommandId;
    private double? _advanceTargetDay;
    private string _advanceCommandId;
    private string _pendingSaveName;
    private string _pendingSaveCommandId;
    private string _pendingClaimedCommandPath;
    private float _nextClaimedCommandReadTime;
    private float _nextClaimedCommandReadLogTime;
    private float _waitForDoubleClickUntilTime;
    private string _restCommandId;
    private double? _restTargetDay;
    private double? _restStartDay;
    private double? _restRequestedDays;
    private RecruitmentVM _recruitmentViewModel;
    private bool _freshProgressionPollLogged;
    private bool _freshProgressionCommandLogged;
    private Agent _missionInputAgent;
    private TaleWorlds.Library.Vec2 _missionInputVector;
    private float _missionInputExpiresAt;
    private AgentNavigator _missionNavigator;
    private Mission _missionNavigationMission;
    private Agent _missionNavigationOwner;
    private int _missionNavigationTargetAgentIndex = -1;
    private TaleWorlds.Library.Vec3 _missionNavigationTargetPosition;
    private TaleWorlds.Core.AgentControllerType? _missionNavigationOriginalController;
    private float _missionNavigationStartedAt;
    private float _missionNavigationExpiresAt;
    private float _lastMissionNavigationTickAt;
    private string _missionNavigationStatus;
    private bool _missionNavigationBattleProbe;
    private Formation _missionNavigationBattleProbeFormation;
    private bool? _missionNavigationBattleProbeOriginalFormationAiControlled;
    private Mission _missionSceneAgentsObservationMission;
    private Dictionary<int, Agent> _missionSceneAgentsObservation;
    private float _missionSceneAgentsObservationAt;
    private const float MissionSceneAgentsObservationLeaseSeconds = 60f;
    private const float LeaveAreaHoldSeconds = 2.5f;
    private const long MaxProtocolEventLogBytes = 16L * 1024 * 1024;
    private Mission _missionLeaveMission;
    private IInputContext _missionLeaveOriginalInputContext;
    private ChronicleMissionLeaveInputContext _missionLeaveInputContext;
    private float _missionLeaveStartedAt;
    private float _missionLeaveExpiresAt;
    private string _missionLeaveStatus;

    internal ChronicleAgentProtocol()
    {
        _activeInstance = this;
        AgentMissionInputPatch.Install();
        ChronicleAgentBarterViewCapture.Install();
        ChronicleTournamentAdapter.Install();
        var documentsPath = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
        _root = Path.Combine(documentsPath, "Mount and Blade II Bannerlord", "AgentRuns", "ChronicleAgent");
        _responseRoot = Path.Combine(_root, "responses");
        Directory.CreateDirectory(_root);
        Directory.CreateDirectory(_responseRoot);
        var eventLogPath = Path.Combine(_root, "events.jsonl");
        if (File.Exists(eventLogPath) && new FileInfo(eventLogPath).Length > MaxProtocolEventLogBytes)
            File.WriteAllText(eventLogPath, string.Empty, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
        if (Environment.GetEnvironmentVariable("CHRONICLE_FRESH_CAMPAIGN_SKIP_ISSUE_PROBE") == "1")
            ChronicleDiagnostics.Write($"fresh-progression-protocol-created|root={_root}");
    }

    internal void Poll(ChronicleCampaignBehavior behavior)
    {
        string currentCommandId = null;
        string currentAction = null;
        try
        {
            ChronicleAgentBattleMissionAdapter.UpdateMainAgentAiControllerProbeLease();
            UpdateMissionNavigationLease();
            UpdateMissionInputLease();
            UpdateMissionLeaveLease();
            CompleteRestIfReady(behavior);
            CompleteAdvanceIfReady(behavior);
            CompleteDeferredMapClickTimeChange();
            var commandPath = Path.Combine(_root, "command.json");
            if (!_freshProgressionPollLogged && Environment.GetEnvironmentVariable("CHRONICLE_FRESH_CAMPAIGN_SKIP_ISSUE_PROBE") == "1")
            {
                _freshProgressionPollLogged = true;
                ChronicleDiagnostics.Write($"fresh-progression-protocol-polled|root={_root}|commandExists={File.Exists(commandPath)}");
            }
            if (!_freshProgressionCommandLogged && Environment.GetEnvironmentVariable("CHRONICLE_FRESH_CAMPAIGN_SKIP_ISSUE_PROBE") == "1" && File.Exists(commandPath))
            {
                _freshProgressionCommandLogged = true;
                ChronicleDiagnostics.Write("fresh-progression-protocol-command-visible");
            }
            if (_pendingClaimedCommandPath == null)
            {
                if (!File.Exists(commandPath)) return;
                _pendingClaimedCommandPath = Path.Combine(_root, "command-" + Guid.NewGuid().ToString("N") + ".processing");
                try { File.Move(commandPath, _pendingClaimedCommandPath); }
                catch (IOException) { _pendingClaimedCommandPath = null; return; }
            }
            if (EngineTime.ApplicationTime < _nextClaimedCommandReadTime) return;
            string command;
            try
            {
                using (var commandStream = new FileStream(_pendingClaimedCommandPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                using (var commandReader = new StreamReader(commandStream, new System.Text.UTF8Encoding(false), true))
                    command = commandReader.ReadToEnd();
            }
            catch (IOException exception)
            {
                var applicationTime = EngineTime.ApplicationTime;
                _nextClaimedCommandReadTime = applicationTime + 0.1f;
                if (applicationTime >= _nextClaimedCommandReadLogTime)
                {
                    ChronicleDiagnostics.Write($"agent-command-read-retry|message={exception.Message}");
                    _nextClaimedCommandReadLogTime = applicationTime + 2f;
                }
                return;
            }
            var completedClaimedPath = _pendingClaimedCommandPath;
            _pendingClaimedCommandPath = null;
            _nextClaimedCommandReadTime = 0f;
            try { File.Delete(completedClaimedPath); }
            catch (IOException exception) { ChronicleDiagnostics.Write($"agent-command-file-cleanup|message={exception.Message}"); }
            var commandId = ReadString(command, "id") ?? Guid.NewGuid().ToString("N");
            currentCommandId = commandId;
            if (commandId == _lastCommandId) return;
            _lastCommandId = commandId;

            var action = ReadString(command, "action") ?? "unknown";
            currentAction = action;
            var expectedNativeSessionId = ReadString(command, "expectedNativeSessionId");
            if (expectedNativeSessionId != null && !string.Equals(expectedNativeSessionId, behavior.AgentRuntimeSessionId, StringComparison.Ordinal))
            {
                WriteResponse(commandId, action, "rejected", behavior, "native-session-mismatch");
                return;
            }
            DispatchCommand(behavior, commandId, action, command);
        }
        catch (Exception exception)
        {
            TryCaptureUnexpectedProtocolFailureFrame(currentCommandId, currentAction, exception);
            ChronicleDiagnostics.Write($"agent-protocol-error|type={exception.GetType().Name}|message={exception.Message}");
            if (!string.IsNullOrWhiteSpace(currentCommandId))
            {
                try { WriteResponse(currentCommandId, currentAction ?? "unknown", "rejected", behavior, exception.ToString()); }
                catch { }
            }
        }
    }
}
