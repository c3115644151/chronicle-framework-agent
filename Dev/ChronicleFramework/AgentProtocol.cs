using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using SandBox;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.Encounters;
using TaleWorlds.CampaignSystem.GameState;
using TaleWorlds.CampaignSystem.GameMenus;
using TaleWorlds.CampaignSystem.MapEvents;
using TaleWorlds.CampaignSystem.Party;
using TaleWorlds.CampaignSystem.Settlements;
using TaleWorlds.CampaignSystem.Settlements.Locations;
using TaleWorlds.CampaignSystem.ViewModelCollection.GameMenu.Recruitment;
using TaleWorlds.CampaignSystem.ViewModelCollection.GameMenu.Events;
using TaleWorlds.Core;
using TaleWorlds.MountAndBlade;
using TaleWorlds.MountAndBlade.View.MissionViews;
using EngineTime = TaleWorlds.Engine.Time;

namespace ChronicleFramework;

internal sealed class ChronicleAgentProtocol
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

    internal ChronicleAgentProtocol()
    {
        _activeInstance = this;
        AgentMissionInputPatch.Install();
        ChronicleAgentBarterViewCapture.Install();
        var documentsPath = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
        _root = Path.Combine(documentsPath, "Mount and Blade II Bannerlord", "AgentRuns", "ChronicleAgent");
        _responseRoot = Path.Combine(_root, "responses");
        Directory.CreateDirectory(_root);
        Directory.CreateDirectory(_responseRoot);
        if (Environment.GetEnvironmentVariable("CHRONICLE_FRESH_CAMPAIGN_SKIP_ISSUE_PROBE") == "1")
            ChronicleDiagnostics.Write($"fresh-progression-protocol-created|root={_root}");
    }

    internal void Poll(ChronicleCampaignBehavior behavior)
    {
        string currentCommandId = null;
        string currentAction = null;
        try
        {
            UpdateMissionNavigationLease();
            UpdateMissionInputLease();
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
            switch (action)
            {
                case "state":
                    WriteResponse(commandId, action, "completed", behavior);
                    break;
                case "mapSettlementTargets":
                    if (Game.Current?.GameStateManager?.ActiveState is not MapState)
                        throw new InvalidOperationException("mapSettlementTargets requires the Campaign Map state");
                    WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentObserver.BuildMapSettlementTargetsJson());
                    break;
                case "mapPartyTargets":
                    if (Game.Current?.GameStateManager?.ActiveState is not MapState)
                        throw new InvalidOperationException("mapPartyTargets requires the Campaign Map state");
                    WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentObserver.BuildMapPartyTargetsJson());
                    break;
                case "mapPartyComposition":
                    if (Game.Current?.GameStateManager?.ActiveState is not MapState)
                        throw new InvalidOperationException("mapPartyComposition requires the Campaign Map state");
                    var compositionPartyId = ReadString(command, "partyId");
                    if (string.IsNullOrWhiteSpace(compositionPartyId))
                        throw new InvalidOperationException("mapPartyComposition requires a partyId from the current visible map party list");
                    WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentObserver.BuildMapPartyCompositionJson(compositionPartyId));
                    break;
                case "mapPartyBehavior":
                    if (Game.Current?.GameStateManager?.ActiveState is not MapState)
                        throw new InvalidOperationException("mapPartyBehavior requires the Campaign Map state");
                    var behaviorPartyId = ReadString(command, "partyId");
                    if (string.IsNullOrWhiteSpace(behaviorPartyId))
                        throw new InvalidOperationException("mapPartyBehavior requires a partyId from the current visible map party list");
                    WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentObserver.BuildMapPartyBehaviorJson(behaviorPartyId));
                    break;
                case "characterDevelopment":
                    if (Game.Current?.GameStateManager?.ActiveState is not MapState)
                        throw new InvalidOperationException("characterDevelopment requires the Campaign Map state");
                    WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentObserver.BuildCharacterDevelopmentJson());
                    break;
                case "spendSkillFocus":
                    if (Game.Current?.GameStateManager?.ActiveState is not MapState)
                        throw new InvalidOperationException("spendSkillFocus requires the Campaign Map state");
                    WriteResponse(commandId, action, "completed", behavior, null, SpendMainHeroSkillFocus(command));
                    break;
                case "partyUpgradeOptions":
                    if (Game.Current?.GameStateManager?.ActiveState is not MapState)
                        throw new InvalidOperationException("partyUpgradeOptions requires the Campaign Map state");
                    WriteResponse(commandId, action, "completed", behavior, null, ChroniclePartyUpgradeAdapter.BuildOptionsJson());
                    break;
                case "upgradeTroop":
                    if (Game.Current?.GameStateManager?.ActiveState is not MapState)
                        throw new InvalidOperationException("upgradeTroop requires the Campaign Map state");
                    var upgradeTroopId = ReadString(command, "troopId");
                    var upgradeTargetIndex = ReadRequiredInteger(command, "upgradeTargetIndex");
                    WriteResponse(commandId, action, "completed", behavior, null, ChroniclePartyUpgradeAdapter.UpgradeOneTroopJson(upgradeTroopId, upgradeTargetIndex));
                    break;
                case "prisonerRecruitmentOptions":
                    if (Game.Current?.GameStateManager?.ActiveState is not MapState)
                        throw new InvalidOperationException("prisonerRecruitmentOptions requires the Campaign Map state");
                    WriteResponse(commandId, action, "completed", behavior, null, ChroniclePartyPrisonerRecruitmentAdapter.BuildOptionsJson());
                    break;
                case "recruitPrisoner":
                    if (Game.Current?.GameStateManager?.ActiveState is not MapState)
                        throw new InvalidOperationException("recruitPrisoner requires the Campaign Map state");
                    WriteResponse(commandId, action, "completed", behavior, null, ChroniclePartyPrisonerRecruitmentAdapter.RecruitOneJson(ReadString(command, "troopId"), ReadDouble(command, "confirmPartySizeWarning") > 0.5));
                    break;
                case "harnessSeedPartyUpgradeFixture":
                    var upgradeFixtureMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
                    var upgradeFixtureRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
                    if (!string.Equals(upgradeFixtureMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(upgradeFixtureRoot) || !Directory.Exists(upgradeFixtureRoot))
                        throw new InvalidOperationException("harnessSeedPartyUpgradeFixture is restricted to a visual Harness run with a Harness temp directory");
                    if (Game.Current?.GameStateManager?.ActiveState is not MapState)
                        throw new InvalidOperationException("harnessSeedPartyUpgradeFixture requires the Campaign Map state");
                    WriteResponse(commandId, action, "completed", behavior, null, SeedPartyUpgradeFixture());
                    break;
                case "harnessSeedPrisonerRecruitmentFixture":
                    var prisonerFixtureMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
                    var prisonerFixtureRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
                    if (!string.Equals(prisonerFixtureMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(prisonerFixtureRoot) || !Directory.Exists(prisonerFixtureRoot))
                        throw new InvalidOperationException("harnessSeedPrisonerRecruitmentFixture is restricted to a visual Harness run with a Harness temp directory");
                    if (Game.Current?.GameStateManager?.ActiveState is not MapState)
                        throw new InvalidOperationException("harnessSeedPrisonerRecruitmentFixture requires the Campaign Map state");
                    WriteResponse(commandId, action, "completed", behavior, null, SeedPrisonerRecruitmentFixture());
                    break;
                case "harnessPrepareCompanionHiringFixture":
                    var companionFixtureMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
                    var companionFixtureRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
                    if (!string.Equals(companionFixtureMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(companionFixtureRoot) || !Directory.Exists(companionFixtureRoot))
                        throw new InvalidOperationException("harnessPrepareCompanionHiringFixture is restricted to a visual Harness run with a Harness temp directory");
                    WriteResponse(commandId, action, "completed", behavior, null, PrepareCompanionHiringFixture(ReadString(command, "heroId"), ReadRequiredInteger(command, "goldOffset")));
                    break;
                case "harnessCompanionHiringDiagnostics":
                    var companionDiagnosticsMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
                    var companionDiagnosticsRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
                    if (!string.Equals(companionDiagnosticsMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(companionDiagnosticsRoot) || !Directory.Exists(companionDiagnosticsRoot))
                        throw new InvalidOperationException("harnessCompanionHiringDiagnostics is restricted to a visual Harness run with a Harness temp directory");
                    WriteResponse(commandId, action, "completed", behavior, null, BuildCompanionHiringDiagnosticsJson(ReadString(command, "heroId")));
                    break;
                case "harnessSeedPartyRoleFixture":
                    RequireRoleHarnessMode();
                    if (Game.Current?.GameStateManager?.ActiveState is not MapState)
                        throw new InvalidOperationException("harnessSeedPartyRoleFixture requires Campaign Map state");
                    WriteResponse(commandId, action, "completed", behavior, null, ChroniclePartyRoleAdapter.SeedDisposableRoleCompanion());
                    break;
                case "harnessPartyRoleDiagnostics":
                    RequireRoleHarnessMode();
                    WriteResponse(commandId, action, "completed", behavior, null, ChroniclePartyRoleAdapter.BuildHarnessDiagnosticsJson());
                    break;
                case "harnessSeedEquipmentModifierFixture":
                    RequireEquipmentModifierFixtureHarnessMode();
                    if (Game.Current?.GameStateManager?.ActiveState is not MapState)
                        throw new InvalidOperationException("harnessSeedEquipmentModifierFixture requires Campaign Map state");
                    WriteResponse(commandId, action, "completed", behavior, null, ChronicleHarnessEquipmentModifierFixture.SeedMasterworkSword());
                    break;
                case "harnessClearEquipmentModifierFixture":
                    RequireEquipmentModifierFixtureHarnessMode();
                    if (Game.Current?.GameStateManager?.ActiveState is not MapState)
                        throw new InvalidOperationException("harnessClearEquipmentModifierFixture requires Campaign Map state");
                    WriteResponse(commandId, action, "completed", behavior, null, ChronicleHarnessEquipmentModifierFixture.ClearMasterworkSword());
                    break;
                case "harnessOpenInventoryState":
                    WriteResponse(commandId, action, "completed", behavior, null, ChronicleInventoryStateAdapter.OpenThroughNativeMapNavigation(requireHarnessMode: true));
                    break;
                case "harnessCloseInventoryState":
                    WriteResponse(commandId, action, "completed", behavior, null, ChronicleInventoryStateAdapter.CloseAsNativeCancel(requireHarnessMode: true));
                    break;
                case "harnessInventoryStateDiagnostics":
                    WriteResponse(commandId, action, "completed", behavior, null, ChronicleInventoryStateAdapter.BuildHarnessDiagnosticsJson());
                    break;
                case "questDetails":
                    var questDetailsId = ReadString(command, "questId");
                    var observedQuest = FindObservedOngoingQuest(questDetailsId);
                    WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentObserver.BuildQuestDetailsJson(observedQuest));
                    break;
                case "partyRoster":
                    if (Game.Current?.GameStateManager?.ActiveState is not MapState)
                        throw new InvalidOperationException("partyRoster requires the Campaign Map state");
                    WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentObserver.BuildPartyRosterJson());
                    break;
                case "partyRoles":
                    WriteResponse(commandId, action, "completed", behavior, null, ChroniclePartyRoleAdapter.BuildMainPartyRolesJson());
                    break;
                case "inventoryOpen":
                    WriteResponse(commandId, action, "completed", behavior, null, ChronicleInventoryStateAdapter.OpenThroughNativeMapNavigation());
                    break;
                case "heroEquipmentOptions":
                    WriteResponse(commandId, action, "completed", behavior, null, ChronicleInventoryStateAdapter.BuildHeroEquipmentOptionsJson());
                    break;
                case "equipHeroItem":
                    WriteResponse(commandId, action, "completed", behavior, null, ChronicleInventoryStateAdapter.DraftEquipOneMainHeroItem(ReadString(command, "itemViewModelId"), ReadRequiredInteger(command, "equipmentIndex")));
                    break;
                case "unequipHeroItem":
                    WriteResponse(commandId, action, "completed", behavior, null, ChronicleInventoryStateAdapter.DraftUnequipMainHeroItem(ReadRequiredInteger(command, "equipmentIndex")));
                    break;
                case "inventoryConfirm":
                    WriteResponse(commandId, action, "completed", behavior, null, ChronicleInventoryStateAdapter.CommitCurrentNativeTransaction());
                    break;
                case "inventoryCancel":
                    WriteResponse(commandId, action, "completed", behavior, null, ChronicleInventoryStateAdapter.CancelCurrentNativeTransaction(confirmDiscardChanges: false));
                    break;
                case "inventoryCancelChanges":
                    WriteResponse(commandId, action, "completed", behavior, null, ChronicleInventoryStateAdapter.CancelCurrentNativeTransaction(confirmDiscardChanges: true));
                    break;
                case "setPartyRole":
                    WriteResponse(commandId, action, "completed", behavior, null, ChroniclePartyRoleAdapter.SetMainPartyRoleJson(ReadString(command, "roleId"), ReadString(command, "heroId"), removeAssignee: false));
                    break;
                case "unassignPartyRole":
                    WriteResponse(commandId, action, "completed", behavior, null, ChroniclePartyRoleAdapter.SetMainPartyRoleJson(ReadString(command, "roleId"), null, removeAssignee: true));
                    break;
                case "harnessMissionDiagnostics":
                    var missionDiagnosticsMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
                    var missionDiagnosticsRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
                    if (!string.Equals(missionDiagnosticsMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(missionDiagnosticsRoot) || !Directory.Exists(missionDiagnosticsRoot))
                        throw new InvalidOperationException("harnessMissionDiagnostics is restricted to a visual Harness run with a Harness temp directory");
                    var diagnosticMission = Mission.Current;
                    if (diagnosticMission == null || diagnosticMission.MissionEnded || !AgentMissionInputPatch.IsSupportedLocationMission(diagnosticMission))
                        throw new InvalidOperationException("harnessMissionDiagnostics requires an active Town or Tavern Location Mission");
                    WriteResponse(commandId, action, "completed", behavior, null, BuildHarnessMissionDiagnosticsJson(diagnosticMission));
                    break;
                case "harnessMapDiagnostics":
                    var mapDiagnosticsMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
                    var mapDiagnosticsRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
                    if (!string.Equals(mapDiagnosticsMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(mapDiagnosticsRoot) || !Directory.Exists(mapDiagnosticsRoot))
                        throw new InvalidOperationException("harnessMapDiagnostics is restricted to a visual Harness run with a Harness temp directory");
                    if (Game.Current?.GameStateManager?.ActiveState is not MapState)
                        throw new InvalidOperationException("harnessMapDiagnostics requires the Campaign Map state");
                    WriteResponse(commandId, action, "completed", behavior, null, BuildHarnessMapDiagnosticsJson());
                    break;
                case "harnessPlayerSkillsDiagnostics":
                    var skillsDiagnosticsMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
                    var skillsDiagnosticsRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
                    if (!string.Equals(skillsDiagnosticsMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(skillsDiagnosticsRoot) || !Directory.Exists(skillsDiagnosticsRoot))
                        throw new InvalidOperationException("harnessPlayerSkillsDiagnostics is restricted to a visual Harness run with a Harness temp directory");
                    if (Game.Current?.GameStateManager?.ActiveState is not MapState)
                        throw new InvalidOperationException("harnessPlayerSkillsDiagnostics requires the Campaign Map state");
                    WriteResponse(commandId, action, "completed", behavior, null, BuildHarnessPlayerSkillsDiagnosticsJson());
                    break;
                case "harnessCharacterDevelopmentDiagnostics":
                    var characterDevelopmentDiagnosticsMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
                    var characterDevelopmentDiagnosticsRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
                    if (!string.Equals(characterDevelopmentDiagnosticsMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(characterDevelopmentDiagnosticsRoot) || !Directory.Exists(characterDevelopmentDiagnosticsRoot))
                        throw new InvalidOperationException("harnessCharacterDevelopmentDiagnostics is restricted to a visual Harness run with a Harness temp directory");
                    if (Game.Current?.GameStateManager?.ActiveState is not MapState)
                        throw new InvalidOperationException("harnessCharacterDevelopmentDiagnostics requires the Campaign Map state");
                    WriteResponse(commandId, action, "completed", behavior, null, BuildHarnessCharacterDevelopmentDiagnosticsJson());
                    break;
                case "harnessQuestDetailsDiagnostics":
                    var questDetailsDiagnosticsMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
                    var questDetailsDiagnosticsRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
                    if (!string.Equals(questDetailsDiagnosticsMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(questDetailsDiagnosticsRoot) || !Directory.Exists(questDetailsDiagnosticsRoot))
                        throw new InvalidOperationException("harnessQuestDetailsDiagnostics is restricted to a visual Harness run with a Harness temp directory");
                    var diagnosticQuest = FindObservedOngoingQuest(ReadString(command, "questId"));
                    WriteResponse(commandId, action, "completed", behavior, null, BuildHarnessQuestDetailsDiagnosticsJson(diagnosticQuest));
                    break;
                case "harnessQuestDeadlinePrivacyDiagnostics":
                    var questDeadlineDiagnosticsMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
                    var questDeadlineDiagnosticsRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
                    if (!string.Equals(questDeadlineDiagnosticsMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(questDeadlineDiagnosticsRoot) || !Directory.Exists(questDeadlineDiagnosticsRoot))
                        throw new InvalidOperationException("harnessQuestDeadlinePrivacyDiagnostics is restricted to a visual Harness run with a Harness temp directory");
                    WriteResponse(commandId, action, "completed", behavior, null, BuildHarnessQuestDeadlinePrivacyDiagnosticsJson());
                    break;
                case "harnessPartyRosterDiagnostics":
                    var partyRosterDiagnosticsMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
                    var partyRosterDiagnosticsRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
                    if (!string.Equals(partyRosterDiagnosticsMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(partyRosterDiagnosticsRoot) || !Directory.Exists(partyRosterDiagnosticsRoot))
                        throw new InvalidOperationException("harnessPartyRosterDiagnostics is restricted to a visual Harness run with a Harness temp directory");
                    if (Game.Current?.GameStateManager?.ActiveState is not MapState)
                        throw new InvalidOperationException("harnessPartyRosterDiagnostics requires the Campaign Map state");
                    WriteResponse(commandId, action, "completed", behavior, null, BuildHarnessPartyRosterDiagnosticsJson());
                    break;
                case "harnessMapPartyDiagnostics":
                    var mapPartyDiagnosticsMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
                    var mapPartyDiagnosticsRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
                    if (!string.Equals(mapPartyDiagnosticsMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(mapPartyDiagnosticsRoot) || !Directory.Exists(mapPartyDiagnosticsRoot))
                        throw new InvalidOperationException("harnessMapPartyDiagnostics is restricted to a visual Harness run with a Harness temp directory");
                    if (Game.Current?.GameStateManager?.ActiveState is not MapState)
                        throw new InvalidOperationException("harnessMapPartyDiagnostics requires the Campaign Map state");
                    WriteResponse(commandId, action, "completed", behavior, null, BuildHarnessMapPartyDiagnosticsJson());
                    break;
                case "harnessMapPartyCompositionDiagnostics":
                    var mapPartyCompositionDiagnosticsMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
                    var mapPartyCompositionDiagnosticsRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
                    if (!string.Equals(mapPartyCompositionDiagnosticsMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(mapPartyCompositionDiagnosticsRoot) || !Directory.Exists(mapPartyCompositionDiagnosticsRoot))
                        throw new InvalidOperationException("harnessMapPartyCompositionDiagnostics is restricted to a visual Harness run with a Harness temp directory");
                    if (Game.Current?.GameStateManager?.ActiveState is not MapState)
                        throw new InvalidOperationException("harnessMapPartyCompositionDiagnostics requires the Campaign Map state");
                    var diagnosticPartyId = ReadString(command, "partyId");
                    if (string.IsNullOrWhiteSpace(diagnosticPartyId))
                        throw new InvalidOperationException("harnessMapPartyCompositionDiagnostics requires a partyId");
                    WriteResponse(commandId, action, "completed", behavior, null, BuildHarnessMapPartyCompositionDiagnosticsJson(diagnosticPartyId));
                    break;
                case "harnessCreateMapArmyFixture":
                    var createArmyFixtureMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
                    var createArmyFixtureRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
                    if (!string.Equals(createArmyFixtureMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(createArmyFixtureRoot) || !Directory.Exists(createArmyFixtureRoot))
                        throw new InvalidOperationException("harnessCreateMapArmyFixture is restricted to a visual Harness run with a Harness temp directory");
                    if (Game.Current?.GameStateManager?.ActiveState is not MapState)
                        throw new InvalidOperationException("harnessCreateMapArmyFixture requires the Campaign Map state");
                    WriteResponse(commandId, action, "completed", behavior, null, CreateMapArmyFixture(ReadString(command, "partyId"), ReadString(command, "attachedPartyId")));
                    break;
                case "harnessPrepareSafePassageFixture":
                    var safePassageFixtureMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
                    var safePassageFixtureRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
                    if (!string.Equals(safePassageFixtureMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(safePassageFixtureRoot) || !Directory.Exists(safePassageFixtureRoot))
                        throw new InvalidOperationException("harnessPrepareSafePassageFixture is restricted to a visual Harness run with a Harness temp directory");
                    if (Game.Current?.GameStateManager?.ActiveState is not MapState)
                        throw new InvalidOperationException("harnessPrepareSafePassageFixture requires the Campaign Map state");
                    WriteResponse(commandId, action, "completed", behavior, null, ChronicleHarnessSafePassageFixture.CreateAttackingBanditParty());
                    break;
                case "talkToSettlementHero":
                    var overlayMenuContext = TaleWorlds.CampaignSystem.Campaign.Current?.CurrentMenuContext;
                    var overlayGameMenu = overlayMenuContext?.GameMenu;
                    if (overlayGameMenu == null ||
                        (overlayGameMenu.OverlayType != GameMenu.MenuOverlayType.SettlementWithCharacters && overlayGameMenu.OverlayType != GameMenu.MenuOverlayType.SettlementWithBoth) ||
                        Settlement.CurrentSettlement == null)
                        throw new InvalidOperationException("talkToSettlementHero requires the native settlement menu with a visible Characters overlay");
                    var settlementHeroId = ReadString(command, "heroId");
                    if (string.IsNullOrWhiteSpace(settlementHeroId)) throw new InvalidOperationException("talkToSettlementHero requires a HeroId from the current settlement overlay observation");
                    var settlementOverlayLocationCharacters = TaleWorlds.CampaignSystem.Campaign.Current.GameMenuManager.MenuLocations
                        .Where(location => location != null)
                        .SelectMany(location => location.GetCharacterList())
                        .Where(locationCharacter => locationCharacter != null && locationCharacter.Character?.IsHero == true && TaleWorlds.CampaignSystem.Campaign.Current.Models.HeroAgentLocationModel.WillBeListedInOverlay(locationCharacter))
                        .ToArray();
                    var settlementTargetLocationCharacter = settlementOverlayLocationCharacters.FirstOrDefault(locationCharacter =>
                        locationCharacter.Character?.HeroObject != null &&
                        string.Equals(locationCharacter.Character.HeroObject.StringId, settlementHeroId, StringComparison.Ordinal));
                    var settlementTargetHero = settlementTargetLocationCharacter?.Character?.HeroObject;
                    if (settlementTargetHero == null || !settlementTargetHero.IsAlive || settlementTargetHero.IsPrisoner || settlementTargetHero.CurrentSettlement != Settlement.CurrentSettlement)
                        throw new InvalidOperationException("talkToSettlementHero target is no longer a living, non-prisoner character in the current native Settlement overlay");
                    var talkPermissionWasReported = false;
                    var talkPermissionAllowed = true;
                    string talkPermissionHint = null;
                    Game.Current.EventManager.TriggerEvent(new SettlementOverlayTalkPermissionEvent(settlementTargetHero, (isAllowed, hint) =>
                    {
                        talkPermissionWasReported = true;
                        talkPermissionAllowed = isAllowed;
                        talkPermissionHint = hint?.ToString();
                    }));
                    if (talkPermissionWasReported && !talkPermissionAllowed)
                        throw new InvalidOperationException(string.IsNullOrWhiteSpace(talkPermissionHint) ? "The native Settlement overlay does not currently allow talking to this Hero" : talkPermissionHint);
                    var targetLocation = LocationComplex.Current?.GetLocationOfCharacter(settlementTargetHero);
                    if (targetLocation == null) throw new InvalidOperationException("Native LocationComplex has no current Location for the selected Settlement overlay Hero");
                    if (string.Equals(targetLocation.StringId, "alley", StringComparison.Ordinal))
                        targetLocation = LocationComplex.Current.GetLocationWithId("center");
                    TaleWorlds.CampaignSystem.CampaignEventDispatcher.Instance.OnPlayerStartTalkFromMenu(settlementTargetHero);
                    PlayerEncounter.LocationEncounter.CreateAndOpenMissionController(targetLocation, null, settlementTargetHero.CharacterObject);
                    var talkData = "{\"heroId\":\"" + Escape(settlementTargetHero.StringId) + "\",\"heroName\":\"" + Escape(settlementTargetHero.Name?.ToString()) + "\",\"locationId\":\"" + Escape(targetLocation.StringId) + "\",\"hasIssue\":" + (settlementTargetHero.Issue != null ? "true" : "false") + ",\"issueType\":\"" + Escape(settlementTargetHero.Issue?.GetType().Name) + "\",\"talkPermissionWasReported\":" + (talkPermissionWasReported ? "true" : "false") + "}";
                    WriteResponse(commandId, action, "completed", behavior, null, talkData);
                    break;
                case "captureFrame":
                    var screenshotHarnessMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
                    if (!string.Equals(screenshotHarnessMode, "visual-capture", StringComparison.Ordinal) &&
                        !string.Equals(screenshotHarnessMode, "visual-battle-fixture", StringComparison.Ordinal))
                        throw new InvalidOperationException("captureFrame is restricted to visual Harness modes");
                    var captureRootValue = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
                    if (string.IsNullOrWhiteSpace(captureRootValue)) throw new InvalidOperationException("Harness capture directory is unavailable");
                    var captureRoot = Path.GetFullPath(captureRootValue).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
                    var captureFileName = ReadString(command, "fileName") ?? string.Empty;
                    if (!string.Equals(captureFileName, Path.GetFileName(captureFileName), StringComparison.Ordinal) || !string.Equals(Path.GetExtension(captureFileName), ".bmp", StringComparison.OrdinalIgnoreCase))
                        throw new InvalidOperationException("captureFrame requires a BMP file name without path components");
                    var capturePath = Path.GetFullPath(Path.Combine(captureRoot, captureFileName));
                    if (!capturePath.StartsWith(captureRoot, StringComparison.OrdinalIgnoreCase))
                        throw new InvalidOperationException("captureFrame output escaped the Harness temp directory");
                    Directory.CreateDirectory(Path.GetDirectoryName(capturePath));
                    TaleWorlds.Engine.Utilities.TakeScreenshot(capturePath);
                    WriteResponse(commandId, action, "completed", behavior);
                    break;
                case "inventoryTakeAll":
                    var lootInventoryState = Game.Current.GameStateManager.ActiveState as InventoryState;
                    if (lootInventoryState?.InventoryLogic == null || lootInventoryState.InventoryMode != Helpers.InventoryScreenHelper.InventoryMode.Loot)
                        throw new InvalidOperationException("inventoryTakeAll requires the native postbattle Loot InventoryState");
                    var inventoryHandler = lootInventoryState.Handler;
                    if (inventoryHandler == null || lootInventoryState.InventoryLogic.GetElementCountOnSide(TaleWorlds.CampaignSystem.Inventory.InventoryLogic.InventorySide.OtherInventory) <= 0)
                        throw new InvalidOperationException("native InventoryState has no loot items or UI handler");
                    inventoryHandler.ExecuteLootingScript();
                    WriteResponse(commandId, action, "completed", behavior);
                    break;
                case "inventoryDone":
                    var lootInventoryStateToClose = Game.Current.GameStateManager.ActiveState as InventoryState;
                    if (lootInventoryStateToClose?.InventoryLogic == null || lootInventoryStateToClose.InventoryMode != Helpers.InventoryScreenHelper.InventoryMode.Loot)
                        throw new InvalidOperationException("inventoryDone requires the native postbattle Loot InventoryState");
                    Helpers.InventoryScreenHelper.CloseScreen(fromCancel: false);
                    WriteResponse(commandId, action, "completed", behavior);
                    break;
                case "advance":
                    var days = ReadDouble(command, "days");
                    _advanceTargetDay = CampaignTime.Now.ToDays + Math.Max(0.01, days);
                    _advanceCommandId = commandId;
                    TaleWorlds.CampaignSystem.Campaign.Current.TimeControlMode = TaleWorlds.CampaignSystem.CampaignTimeControlMode.UnstoppableFastForward;
                    WriteResponse(commandId, action, "accepted", behavior);
                    break;
                case "rest":
                    var currentMenu = TaleWorlds.CampaignSystem.Campaign.Current.CurrentMenuContext?.GameMenu;
                    if (currentMenu == null || currentMenu.StringId != "town_wait_menus" || !currentMenu.IsWaitMenu || !Campaign.Current.IsMainPartyWaiting)
                        throw new InvalidOperationException("rest requires the native town settlement wait menu");
                    if (_restCommandId != null) throw new InvalidOperationException("another rest command is active");
                    var restDays = Math.Max(0.01, ReadDouble(command, "days"));
                    _restCommandId = commandId;
                    _restTargetDay = CampaignTime.Now.ToDays + restDays;
                    WriteResponse(commandId, action, "accepted", behavior);
                    break;
                case "pursue":
                    if (PlayerEncounter.IsActive || MobileParty.MainParty.CurrentSettlement != null || MobileParty.MainParty.MapEvent != null)
                        throw new InvalidOperationException("pursuit requires the campaign map with no active encounter");
                    var targetPartyId = ReadString(command, "partyId");
                    var targetParty = MobileParty.All.FirstOrDefault(party => party != null && string.Equals(party.StringId, targetPartyId, StringComparison.Ordinal));
                    if (targetParty == null || targetParty == MobileParty.MainParty || !targetParty.IsActive || !targetParty.IsVisible)
                        throw new InvalidOperationException("active visible target party not found");
                    if (targetParty.IsCurrentlyAtSea != MobileParty.MainParty.IsCurrentlyAtSea ||
                        !Helpers.NavigationHelper.CanPlayerNavigateToPosition(targetParty.Position, out var pursuitNavigationType))
                        throw new InvalidOperationException("target party is not currently navigable by the main party");
                    MobileParty.MainParty.SetMoveEngageParty(targetParty, pursuitNavigationType);
                    ApplyMapClickTimeChange(isDoubleClick: false);
                    WriteResponse(commandId, action, "completed", behavior);
                    break;
                case "follow":
                    if (PlayerEncounter.IsActive || MobileParty.MainParty.CurrentSettlement != null || MobileParty.MainParty.MapEvent != null)
                        throw new InvalidOperationException("escort requires the campaign map with no active encounter");
                    var escortPartyId = ReadString(command, "partyId");
                    var escortParty = MobileParty.All.FirstOrDefault(party => party != null && string.Equals(party.StringId, escortPartyId, StringComparison.Ordinal));
                    if (escortParty == null || escortParty == MobileParty.MainParty || !escortParty.IsActive || !escortParty.IsVisible)
                        throw new InvalidOperationException("active visible target party not found");
                    if (escortParty.IsCurrentlyAtSea != MobileParty.MainParty.IsCurrentlyAtSea ||
                        !Helpers.NavigationHelper.CanPlayerNavigateToPosition(escortParty.Position, out var escortNavigationType))
                        throw new InvalidOperationException("target party is not currently navigable by the main party");
                    MobileParty.MainParty.SetMoveEscortParty(escortParty, escortNavigationType, isTargetingPort: false);
                    ApplyMapClickTimeChange(isDoubleClick: false);
                    WriteResponse(commandId, action, "completed", behavior);
                    break;
                case "hold":
                    MobileParty.MainParty.SetMoveModeHold();
                    ApplyMapClickTimeChange(isDoubleClick: false);
                    WriteResponse(commandId, action, "completed", behavior);
                    break;
                case "pause":
                    TaleWorlds.CampaignSystem.Campaign.Current.TimeControlMode = TaleWorlds.CampaignSystem.CampaignTimeControlMode.Stop;
                    WriteResponse(commandId, action, "completed", behavior);
                    break;
                case "resume":
                    TaleWorlds.CampaignSystem.Campaign.Current.TimeControlMode = TaleWorlds.CampaignSystem.CampaignTimeControlMode.UnstoppablePlay;
                    WriteResponse(commandId, action, "completed", behavior);
                    break;
                case "move":
                    if (PlayerEncounter.IsActive || MobileParty.MainParty.CurrentSettlement != null || MobileParty.MainParty.MapEvent != null)
                        throw new InvalidOperationException("settlement movement requires the campaign map with no active encounter");
                    var settlementId = ReadString(command, "settlementId");
                    var settlement = string.IsNullOrWhiteSpace(settlementId) ? null : Settlement.Find(settlementId);
                    if (settlement == null || !settlement.IsActive || !settlement.IsVisible) throw new InvalidOperationException("settlement is not currently exposed as a visible Campaign map target");
                    if (settlement.MapFaction != null && FactionManager.IsAtWarAgainstFaction(MobileParty.MainParty.MapFaction, settlement.MapFaction))
                        throw new InvalidOperationException("hostile settlement rejected by safe movement policy");
                    Helpers.NavigationHelper.GetInteractionDataForMainParty(settlement, out var canNavigateToSettlement, out var navigationType, out var targetingPort);
                    if (!canNavigateToSettlement) throw new InvalidOperationException("settlement is not currently navigable by the main party");
                    MobileParty.MainParty.SetMoveGoToSettlement(settlement, navigationType, targetingPort);
                    ApplyMapClickTimeChange(isDoubleClick: false);
                    WriteResponse(commandId, action, "completed", behavior);
                    break;
                case "moveToPoint":
                    if (PlayerEncounter.IsActive || MobileParty.MainParty.CurrentSettlement != null || MobileParty.MainParty.MapEvent != null)
                        throw new InvalidOperationException("point movement requires the campaign map with no active encounter");
                    var mapStateForPointMove = Game.Current.GameStateManager.ActiveState as MapState;
                    if (mapStateForPointMove == null || mapStateForPointMove.AtMenu)
                        throw new InvalidOperationException("point movement requires the unblocked native campaign map state");
                    var targetX = ReadRequiredFiniteDouble(command, "x");
                    var targetY = ReadRequiredFiniteDouble(command, "y");
                    var surface = ReadString(command, "surface");
                    if (!string.Equals(surface, "land", StringComparison.Ordinal))
                        throw new InvalidOperationException("moveToPoint currently supports land destinations only; naval/sea transition belongs to a separately tested adapter");
                    if (!MobileParty.MainParty.Position.IsOnLand)
                        throw new InvalidOperationException("land point movement requires the main party to be on land");
                    if (targetX > float.MaxValue || targetX < -float.MaxValue || targetY > float.MaxValue || targetY < -float.MaxValue)
                        throw new InvalidOperationException("map destination is outside the Campaign coordinate range");
                    var requestedPoint = new CampaignVec2(new TaleWorlds.Library.Vec2((float)targetX, (float)targetY), isOnLand: true);
                    if (!requestedPoint.Face.IsValid())
                        throw new InvalidOperationException("map destination does not resolve to a valid navigation face");
                    if (!Helpers.NavigationHelper.CanPlayerNavigateToPosition(requestedPoint, out _))
                        throw new InvalidOperationException("map destination is not currently navigable by the main party");
                    var mainPartyForPointMove = MobileParty.MainParty;
                    mapStateForPointMove.ProcessTravel(requestedPoint);
                    if (mainPartyForPointMove.DefaultBehavior != AiBehavior.GoToPoint)
                        throw new InvalidOperationException("native MapState.ProcessTravel did not establish a GoToPoint order");
                    ApplyMapClickTimeChange(isDoubleClick: false);
                    var actualPoint = mainPartyForPointMove.TargetPosition;
                    var pointMoveData = "{\"requested\":{\"x\":" + targetX.ToString("R", CultureInfo.InvariantCulture) + ",\"y\":" + targetY.ToString("R", CultureInfo.InvariantCulture) + ",\"surface\":\"" + Escape(surface) + "\"},\"nativeTarget\":{\"x\":" + actualPoint.X.ToString("R", CultureInfo.InvariantCulture) + ",\"y\":" + actualPoint.Y.ToString("R", CultureInfo.InvariantCulture) + ",\"isOnLand\":" + actualPoint.IsOnLand.ToString().ToLowerInvariant() + "},\"nativeBehavior\":\"" + Escape(mainPartyForPointMove.DefaultBehavior.ToString()) + "\"}";
                    WriteResponse(commandId, action, "completed", behavior, null, pointMoveData);
                    break;
                case "missionInput":
                    var activeMission = Mission.Current;
                    var missionState = Game.Current.GameStateManager.ActiveState as MissionState;
                    if (activeMission == null || activeMission.MissionEnded || missionState == null || activeMission.MainAgent == null || !activeMission.MainAgent.IsActive() || !activeMission.MainAgent.IsPlayerControlled)
                        throw new InvalidOperationException("missionInput requires an active Location Mission with the live player MainAgent");
                    if (!AgentMissionInputPatch.IsSupportedLocationMission(activeMission))
                        throw new InvalidOperationException("missionInput requires a supported non-battle town or Tavern Location Mission");
                    if (Campaign.Current.TimeControlMode != TaleWorlds.CampaignSystem.CampaignTimeControlMode.Stop)
                        throw new InvalidOperationException("missionInput requires the Campaign clock to remain stopped");
                    var inputX = ReadRequiredFiniteDouble(command, "x");
                    var inputY = ReadRequiredFiniteDouble(command, "y");
                    var durationSeconds = ReadRequiredFiniteDouble(command, "durationSeconds");
                    if (inputX < -1.0 || inputX > 1.0 || inputY < -1.0 || inputY > 1.0)
                        throw new InvalidOperationException("missionInput axes must be within [-1,1]");
                    if (durationSeconds < 0.0 || durationSeconds > 0.5)
                        throw new InvalidOperationException("missionInput duration must be 0 to 0.5 seconds");
                    var inputMagnitude = Math.Sqrt(inputX * inputX + inputY * inputY);
                    if (inputMagnitude > 1.0)
                    {
                        inputX /= inputMagnitude;
                        inputY /= inputMagnitude;
                    }
                    ClearMissionNavigationLease("manual-input");
                    if (inputMagnitude == 0.0)
                    {
                        ClearMissionInputLease();
                        activeMission.MainAgent.MovementInputVector = TaleWorlds.Library.Vec2.Zero;
                    }
                    else
                    {
                        if (durationSeconds <= 0.0) throw new InvalidOperationException("nonzero missionInput axes require a positive duration");
                        _missionInputAgent = activeMission.MainAgent;
                        _missionInputVector = new TaleWorlds.Library.Vec2((float)inputX, (float)inputY);
                        _missionInputExpiresAt = EngineTime.ApplicationTime + (float)durationSeconds;
                        _missionInputAgent.MovementInputVector = _missionInputVector;
                    }
                    var missionInputData = "{\"x\":" + inputX.ToString("R", CultureInfo.InvariantCulture) + ",\"y\":" + inputY.ToString("R", CultureInfo.InvariantCulture) + ",\"durationSeconds\":" + durationSeconds.ToString("R", CultureInfo.InvariantCulture) + ",\"boundedLease\":true}";
                    WriteResponse(commandId, action, "completed", behavior, null, missionInputData);
                    break;
                case "missionNavigateToAgent":
                    var navigationMission = Mission.Current;
                    var navigationState = Game.Current.GameStateManager.ActiveState as MissionState;
                    if (navigationMission == null || navigationMission.MissionEnded || navigationState == null || navigationMission.MainAgent == null || !navigationMission.MainAgent.IsActive() || !navigationMission.MainAgent.IsPlayerControlled)
                        throw new InvalidOperationException("missionNavigateToAgent requires an active Location Mission with the live player MainAgent");
                    if (!AgentMissionInputPatch.IsSupportedLocationMission(navigationMission))
                        throw new InvalidOperationException("missionNavigateToAgent requires a supported non-battle town or Tavern Location Mission");
                    if (Campaign.Current.TimeControlMode != CampaignTimeControlMode.Stop)
                        throw new InvalidOperationException("missionNavigateToAgent requires the Campaign clock to remain stopped");
                    if (navigationMission.IsTeleportingAgents)
                        throw new InvalidOperationException("missionNavigateToAgent rejects Mission teleport mode");
                    var targetIndexValue = ReadRequiredFiniteDouble(command, "agentIndex");
                    if (targetIndexValue < 0 || targetIndexValue > int.MaxValue || targetIndexValue != Math.Floor(targetIndexValue))
                        throw new InvalidOperationException("agentIndex must be a nonnegative current-Mission integer index");
                    var navigationTargetAgentIndex = (int)targetIndexValue;
                    var navigationTargetAgent = navigationMission.Agents.FirstOrDefault(agent => agent != null && agent.IsActive() && agent.IsHuman && agent != navigationMission.MainAgent && agent.Index == navigationTargetAgentIndex);
                    if (navigationTargetAgent == null) throw new InvalidOperationException("missionNavigateToAgent requires a live human Agent from the current Mission observation");
                    if (navigationTargetAgent.IsEnemyOf(navigationMission.MainAgent)) throw new InvalidOperationException("hostile local Agent rejected by scripted navigation");
                    var navigationStart = navigationMission.MainAgent.Position;
                    var navigationDestination = navigationTargetAgent.Position;
                    var navigationDistance = Math.Sqrt(Math.Pow(navigationStart.X - navigationDestination.X, 2) + Math.Pow(navigationStart.Y - navigationDestination.Y, 2) + Math.Pow(navigationStart.Z - navigationDestination.Z, 2));
                    if (navigationDistance > 12.0) throw new InvalidOperationException("missionNavigateToAgent target is outside the current local Agent observation range");
                    var requestedNavigationSeconds = ReadDouble(command, "durationSeconds");
                    if (requestedNavigationSeconds == 0) requestedNavigationSeconds = 8.0;
                    if (requestedNavigationSeconds < 1.0 || requestedNavigationSeconds > 20.0)
                        throw new InvalidOperationException("missionNavigateToAgent durationSeconds must be between 1 and 20 seconds");
                    var startWorldPosition = new TaleWorlds.Engine.WorldPosition(navigationMission.Scene, navigationStart);
                    var targetWorldPosition = new TaleWorlds.Engine.WorldPosition(navigationMission.Scene, navigationDestination);
                    if (!navigationMission.Scene.DoesPathExistBetweenPositions(startWorldPosition, targetWorldPosition))
                        throw new InvalidOperationException("native Mission Scene reports no NavMesh path to the currently observed Agent");
                    var originalMainAgentController = navigationMission.MainAgent.Controller;
                    if (originalMainAgentController != AgentControllerType.Player) throw new InvalidOperationException("missionNavigateToAgent can only temporarily hand off the Player-controlled MainAgent");
                    ClearMissionNavigationLease("replaced");
                    ClearMissionInputLease();
                    var directionX = navigationDestination.X - navigationStart.X;
                    var directionY = navigationDestination.Y - navigationStart.Y;
                    var scriptedDirection = (float)Math.Atan2(directionY, directionX);
                    var newMissionNavigator = new SandBox.AgentNavigator(navigationMission.MainAgent);
                    try
                    {
                        navigationMission.MainAgent.Controller = AgentControllerType.AI;
                        newMissionNavigator.SetTargetFrame(targetWorldPosition, scriptedDirection, rangeThreshold: 1.5f, rotationThreshold: -10f, flags: (Agent.AIScriptedFrameFlags)0, disableClearTargetWhenTargetIsReached: false);
                    }
                    catch
                    {
                        try { newMissionNavigator.ClearTarget(); } catch { }
                        navigationMission.MainAgent.Controller = originalMainAgentController;
                        throw;
                    }
                    _missionNavigator = newMissionNavigator;
                    _missionNavigationOwner = navigationMission.MainAgent;
                    _missionNavigationTargetAgentIndex = navigationTargetAgentIndex;
                    _missionNavigationTargetPosition = navigationDestination;
                    _missionNavigationOriginalController = originalMainAgentController;
                    _missionNavigationMission = navigationMission;
                    _missionNavigationStartedAt = EngineTime.ApplicationTime;
                    _missionNavigationExpiresAt = EngineTime.ApplicationTime + (float)requestedNavigationSeconds;
                    _lastMissionNavigationTickAt = EngineTime.ApplicationTime;
                    _missionNavigationStatus = _missionNavigator._agentState.ToString();
                    var navigationData = "{\"targetAgentIndex\":" + navigationTargetAgentIndex.ToString(CultureInfo.InvariantCulture) + ",\"targetCharacterId\":\"" + Escape(navigationTargetAgent.Character?.StringId) + "\",\"targetHeroId\":" + ((navigationTargetAgent.Character as CharacterObject)?.HeroObject == null ? "null" : "\"" + Escape((navigationTargetAgent.Character as CharacterObject).HeroObject.StringId) + "\"") + ",\"navState\":\"" + _missionNavigator._agentState + "\",\"targetDistance\":" + navigationDistance.ToString("R", CultureInfo.InvariantCulture) + ",\"durationSeconds\":" + requestedNavigationSeconds.ToString("R", CultureInfo.InvariantCulture) + "}";
                    WriteResponse(commandId, action, "completed", behavior, null, navigationData);
                    break;
                case "missionInteract":
                    var missionInteractionIndex = ReadRequiredFiniteDouble(command, "agentIndex");
                    if (missionInteractionIndex < 0 || missionInteractionIndex > int.MaxValue || missionInteractionIndex != Math.Floor(missionInteractionIndex))
                        throw new InvalidOperationException("agentIndex must be a nonnegative integer from the current Mission observation");
                    WriteResponse(commandId, action, "completed", behavior, null, ChronicleMissionInteraction.InteractWithObservedAgent((int)missionInteractionIndex));
                    break;
                case "missionCancelNavigation":
                    if (_missionNavigator == null) throw new InvalidOperationException("no native Mission AgentNavigator route is active");
                    if (Mission.Current?.MainAgent != _missionNavigationOwner) throw new InvalidOperationException("active Mission MainAgent changed; navigation cannot be cancelled through this context");
                    ClearMissionNavigationLease("cancelled");
                    var navigationCancelData = "{\"targetAgentIndex\":" + _missionNavigationTargetAgentIndex.ToString(CultureInfo.InvariantCulture) + ",\"controllerRestored\":" + (_missionNavigationOwner?.Controller == AgentControllerType.Player ? "true" : "false") + "}";
                    WriteResponse(commandId, action, "completed", behavior, null, navigationCancelData);
                    break;
                case "missionAimAt":
                    var aimMission = Mission.Current;
                    var aimMissionState = Game.Current.GameStateManager.ActiveState as MissionState;
                    if (aimMission == null || aimMission.MissionEnded || aimMissionState == null || aimMission.MainAgent == null || !aimMission.MainAgent.IsActive() || !aimMission.MainAgent.IsPlayerControlled)
                        throw new InvalidOperationException("missionAimAt requires an active Location Mission with the live player MainAgent");
                    if (!AgentMissionInputPatch.IsSupportedLocationMission(aimMission))
                        throw new InvalidOperationException("missionAimAt requires a supported non-battle town or Tavern Location Mission");
                    if (Campaign.Current.TimeControlMode != TaleWorlds.CampaignSystem.CampaignTimeControlMode.Stop)
                        throw new InvalidOperationException("missionAimAt requires the Campaign clock to remain stopped");
                    var aimAgentIndex = (int)ReadRequiredFiniteDouble(command, "agentIndex");
                    var aimController = aimMission.MissionBehaviors.OfType<MissionMainAgentController>().FirstOrDefault();
                    if (aimController?.MissionScreen == null) throw new InvalidOperationException("native Mission camera controller is unavailable");
                    var aimTarget = aimMission.Agents.FirstOrDefault(agent => agent != null && agent.IsActive() && agent.IsHuman && agent != aimMission.MainAgent && agent.Index == aimAgentIndex);
                    if (aimTarget == null) throw new InvalidOperationException("missionAimAt requires a live human Agent from the current Mission observation");
                    if (aimTarget.IsEnemyOf(aimMission.MainAgent)) throw new InvalidOperationException("hostile HeroAgent cannot be selected by the Tavern interaction camera action");
                    var aimDeltaX = aimTarget.Position.X - aimMission.MainAgent.Position.X;
                    var aimDeltaY = aimTarget.Position.Y - aimMission.MainAgent.Position.Y;
                    var aimDeltaZ = aimTarget.Position.Z - aimMission.MainAgent.Position.Z;
                    var aimDistance = Math.Sqrt(aimDeltaX * aimDeltaX + aimDeltaY * aimDeltaY + aimDeltaZ * aimDeltaZ);
                    if (aimDistance > 12.0) throw new InvalidOperationException("missionAimAt target is outside the current local Agent observation range");
                    var horizontalAimDistance = Math.Sqrt(aimDeltaX * aimDeltaX + aimDeltaY * aimDeltaY);
                    if (horizontalAimDistance < 0.1) throw new InvalidOperationException("HeroAgent target is too close to establish a stable camera bearing");
                    var cameraBearing = Math.Atan2(-aimDeltaX, aimDeltaY);
                    cameraBearing = Math.Atan2(Math.Sin(cameraBearing), Math.Cos(cameraBearing));
                    var previousCameraBearing = aimController.MissionScreen.CameraBearing;
                    aimController.MissionScreen.CameraBearing = (float)cameraBearing;
                    var aimCharacter = aimTarget.Character as CharacterObject;
                    var aimHeroId = aimCharacter?.HeroObject?.StringId;
                    var cameraAimData = "{\"agentIndex\":" + aimTarget.Index.ToString(CultureInfo.InvariantCulture) + ",\"characterId\":\"" + Escape(aimCharacter?.StringId) + "\",\"heroId\":" + (aimHeroId == null ? "null" : "\"" + Escape(aimHeroId) + "\"") + ",\"cameraBearingBefore\":" + previousCameraBearing.ToString("R", CultureInfo.InvariantCulture) + ",\"cameraBearingAfter\":" + aimController.MissionScreen.CameraBearing.ToString("R", CultureInfo.InvariantCulture) + ",\"distance\":" + aimDistance.ToString("R", CultureInfo.InvariantCulture) + "}";
                    WriteResponse(commandId, action, "completed", behavior, null, cameraAimData);
                    break;
                case "menu":
                    if (TaleWorlds.CampaignSystem.Campaign.Current.CurrentMenuContext?.GameMenu == null)
                        throw new InvalidOperationException("no campaign menu is active");
                    WriteResponse(commandId, action, "completed", behavior);
                    break;
                case "recruitOptions":
                    _recruitmentViewModel = ChronicleAgentRecruitment.CreateOrRefresh(_recruitmentViewModel);
                    WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentRecruitment.BuildOptionsJson(_recruitmentViewModel));
                    break;
                case "recruit":
                    _recruitmentViewModel = ChronicleAgentRecruitment.CreateOrRefresh(_recruitmentViewModel);
                    var recruitOwnerId = ReadString(command, "ownerId");
                    var recruitTroopId = ReadString(command, "troopId");
                    var recruitSlot = (int)ReadDouble(command, "slot");
                    var recruitmentResult = ChronicleAgentRecruitment.Recruit(_recruitmentViewModel, recruitOwnerId, recruitTroopId, recruitSlot);
                    WriteResponse(commandId, action, "completed", behavior, null, recruitmentResult);
                    break;
                case "foodOptions":
                    WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentTradeAdapter.BuildFoodOptionsJson());
                    break;
                case "tradeOptions":
                    WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentTradeAdapter.BuildTradeOptionsJson());
                    break;
                case "trade":
                    var tradeDirection = ReadString(command, "direction");
                    var tradeItemViewModelId = ReadString(command, "itemViewModelId");
                    var tradeInventorySide = ReadString(command, "inventorySide");
                    var tradeAmount = (int)ReadDouble(command, "amount");
                    var tradeResult = ChronicleAgentTradeAdapter.DraftTradeItem(tradeDirection, tradeItemViewModelId, tradeInventorySide, tradeAmount);
                    WriteResponse(commandId, action, "completed", behavior, null, tradeResult);
                    break;
                case "provision":
                    var foodItemViewModelId = ReadString(command, "itemViewModelId");
                    var foodAmount = (int)ReadDouble(command, "amount");
                    var provisionResult = ChronicleAgentTradeAdapter.DraftTradeItem("buy", foodItemViewModelId, "OtherInventory", foodAmount, requireFood: true);
                    WriteResponse(commandId, action, "completed", behavior, null, provisionResult);
                    break;
                case "tradeConfirm":
                    WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentTradeAdapter.CommitCurrentNativeTradeTransaction());
                    break;
                case "tradeCancel":
                    WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentTradeAdapter.CancelCurrentNativeTradeTransaction(confirmDiscardChanges: false));
                    break;
                case "tradeCancelChanges":
                    WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentTradeAdapter.CancelCurrentNativeTradeTransaction(confirmDiscardChanges: true));
                    break;
                case "barterOptions":
                    WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentBarterAdapter.BuildOptionsJson());
                    break;
                case "barterEdit":
                    var barterCandidateId = ReadString(command, "barterCandidateId");
                    var barterOperation = ReadString(command, "barterOperation");
                    var barterAmount = (int)ReadDouble(command, "amount");
                    WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentBarterAdapter.EditProposal(barterCandidateId, barterOperation, barterAmount));
                    break;
                case "barterReset":
                    WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentBarterAdapter.ResetProposal());
                    break;
                case "barterAutoBalance":
                    WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentBarterAdapter.AutoBalanceProposal());
                    break;
                case "barterOffer":
                    WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentBarterAdapter.SubmitOffer());
                    break;
                case "barterCancel":
                    WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentBarterAdapter.CancelProposal());
                    break;
                case "menuSelect":
                    var menuContext = TaleWorlds.CampaignSystem.Campaign.Current.CurrentMenuContext;
                    var expectedMenuId = ReadString(command, "menuId");
                    var optionId = ReadString(command, "optionId");
                    if (menuContext?.GameMenu == null || !string.Equals(menuContext.GameMenu.StringId, expectedMenuId, StringComparison.Ordinal))
                        throw new InvalidOperationException("campaign menu changed before option selection");
                    var menuOptions = menuContext.GameMenu.MenuOptions.ToList();
                    if (menuContext.GameMenu.MenuRepeatObjects.Count > 0)
                        throw new InvalidOperationException("repeatable menu options are not supported by protocol v1");
                    var optionIndex = menuOptions.FindIndex(candidate => string.Equals(candidate.IdString, optionId, StringComparison.Ordinal));
                    if (optionIndex < 0) throw new InvalidOperationException("menu option not found");
                    var option = menuOptions[optionIndex];
                    if (!option.GetConditionsHold(TaleWorlds.Core.Game.Current, menuContext) || !option.IsEnabled)
                        throw new InvalidOperationException("menu option is unavailable or disabled");
                    menuContext.GameMenu.RunMenuOptionConsequence(menuContext, optionIndex);
                    WriteResponse(commandId, action, "completed", behavior);
                    break;
                case "dialogueSelect":
                    var conversationManager = Campaign.Current.ConversationManager;
                    var dialogueOptionId = ReadString(command, "optionId");
                    if (conversationManager == null || !conversationManager.IsConversationInProgress)
                        throw new InvalidOperationException("dialogueSelect requires an active native conversation");
                    var dialogueOption = conversationManager.CurOptions.FirstOrDefault(option => string.Equals(option.Id, dialogueOptionId, StringComparison.Ordinal));
                    if (string.IsNullOrWhiteSpace(dialogueOption.Id) || !dialogueOption.IsClickable)
                        throw new InvalidOperationException("conversation option is missing or not clickable");
                    conversationManager.DoOption(dialogueOptionId);
                    WriteResponse(commandId, action, "completed", behavior);
                    break;
                case "dialogueContinue":
                    var conversationToContinue = Campaign.Current.ConversationManager;
                    if (conversationToContinue == null || !conversationToContinue.IsConversationInProgress || conversationToContinue.CurOptions.Count != 0)
                        throw new InvalidOperationException("dialogueContinue requires an active conversation with no selectable options");
                    conversationToContinue.ContinueConversation();
                    WriteResponse(commandId, action, "completed", behavior);
                    break;
                case "battlePause":
                    var battleSimulationToPause = PlayerEncounter.CurrentBattleSimulation;
                    if (battleSimulationToPause == null) throw new InvalidOperationException("battlePause requires an active native battle simulation");
                    battleSimulationToPause.Pause();
                    WriteResponse(commandId, action, "completed", behavior);
                    break;
                case "battleSkip":
                    var battleSimulationToSkip = PlayerEncounter.CurrentBattleSimulation;
                    if (battleSimulationToSkip == null || battleSimulationToSkip.IsSimulationFinished)
                        throw new InvalidOperationException("battleSkip requires an unfinished native battle simulation");
                    battleSimulationToSkip.Skip();
                    WriteResponse(commandId, action, "completed", behavior);
                    break;
                case "seedVisualLoot":
                    if (!string.Equals(Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE"), "visual-battle-fixture", StringComparison.Ordinal))
                        throw new InvalidOperationException("seedVisualLoot is restricted to the visual battle Harness fixture");
                    var finishedLootSimulation = PlayerEncounter.CurrentBattleSimulation;
                    var activeLootEncounter = PlayerEncounter.Current;
                    if (finishedLootSimulation == null || !finishedLootSimulation.IsSimulationFinished || activeLootEncounter == null)
                        throw new InvalidOperationException("seedVisualLoot requires a finished native simulation before encounter aftermath");
                    var visualLootItem = Game.Current.ObjectManager.GetObject<ItemObject>("wool");
                    if (visualLootItem == null) throw new InvalidOperationException("visual loot fixture item 'wool' is unavailable");
                    activeLootEncounter.RosterToReceiveLootItems.AddToCounts(visualLootItem, 10);
                    ChronicleDiagnostics.Write("visual-loot-fixture-seeded|item=wool|count=10|naturalDrop=false");
                    WriteResponse(commandId, action, "completed", behavior, null, "{\"itemId\":\"wool\",\"count\":10,\"naturalDrop\":false}");
                    break;
                case "battleFinish":
                    var completedBattleSimulation = PlayerEncounter.CurrentBattleSimulation;
                    if (completedBattleSimulation == null || !completedBattleSimulation.IsSimulationFinished)
                        throw new InvalidOperationException("battleFinish requires a completed native battle simulation");
                    var activeMapState = Game.Current.GameStateManager.LastOrDefault<MapState>();
                    if (activeMapState != null && activeMapState.IsSimulationActive) activeMapState.EndBattleSimulation();
                    var captureRewardTelemetry = string.Equals(Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE"), "visual-battle-fixture", StringComparison.Ordinal);
                    var rewardMapEvent = captureRewardTelemetry ? completedBattleSimulation.MapEvent : null;
                    var rewardWinnerSide = rewardMapEvent?.Winner;
                    var rewardWinnerParties = rewardWinnerSide?.Parties.ToList() ?? new System.Collections.Generic.List<MapEventParty>();
                    var rewardLoserSide = rewardMapEvent == null || rewardMapEvent.DefeatedSide == BattleSideEnum.None ? null : rewardMapEvent.GetMapEventSide(rewardMapEvent.DefeatedSide);
                    var rewardLoserParties = rewardLoserSide?.Parties.ToList() ?? new System.Collections.Generic.List<MapEventParty>();
                    var rewardPlayerRenownBefore = Clan.PlayerClan?.Renown ?? 0f;
                    var rewardAttackerStrength = rewardMapEvent != null && rewardMapEvent.StrengthOfSide.Length > 1 ? rewardMapEvent.StrengthOfSide[1] : 0f;
                    var rewardDefenderStrength = rewardMapEvent != null && rewardMapEvent.StrengthOfSide.Length > 0 ? rewardMapEvent.StrengthOfSide[0] : 0f;
                    var rewardWinnerContributionTotal = rewardWinnerParties.Sum(entry => entry.ContributionToBattle);
                    var rewardPlayerEntry = rewardWinnerParties.FirstOrDefault(entry => entry.Party == PartyBase.MainParty);
                    completedBattleSimulation.OnFinished();
                    string rewardTelemetryJson = null;
                    if (captureRewardTelemetry && rewardMapEvent != null && rewardWinnerSide != null)
                    {
                        try
                        {
                            var rewardPlayerRenownAfter = Clan.PlayerClan?.Renown ?? 0f;
                            var loserStartingStrength = rewardMapEvent.StrengthOfSide[(int)rewardMapEvent.DefeatedSide];
                            var loserCurrentStrength = rewardLoserParties.Sum(entry => entry.Party.GetCustomStrength(entry.Party.Side, rewardMapEvent.SimulationContext));
                            var loserStrengthReductionFactor = loserStartingStrength > 0f ? (loserStartingStrength - loserCurrentStrength) / loserStartingStrength : 0f;
                            var partyAwards = string.Join(",", rewardWinnerParties.Select(entry => "{\"partyId\":\"" + Escape(entry.Party.MobileParty?.StringId ?? entry.Party.LeaderHero?.StringId ?? "party") + "\",\"contribution\":" + entry.ContributionToBattle + ",\"renown\":" + entry.GainedRenown.ToString("F3", CultureInfo.InvariantCulture) + "}"));
                            rewardTelemetryJson = "{\"eventType\":\"" + Escape(rewardMapEvent.EventType.ToString()) + "\",\"winnerSide\":\"" + Escape(rewardMapEvent.WinningSide.ToString()) + "\",\"attackerStartingStrength\":" + rewardAttackerStrength.ToString("F3", CultureInfo.InvariantCulture) + ",\"defenderStartingStrength\":" + rewardDefenderStrength.ToString("F3", CultureInfo.InvariantCulture) + ",\"winnerRenownValue\":" + rewardWinnerSide.RenownValue.ToString("F3", CultureInfo.InvariantCulture) + ",\"winnerStrengthRatio\":" + rewardWinnerSide.StrengthRatio.ToString("F3", CultureInfo.InvariantCulture) + ",\"winnerContributionTotal\":" + rewardWinnerContributionTotal + ",\"playerContribution\":" + (rewardPlayerEntry?.ContributionToBattle ?? 0) + ",\"loserStartingStrength\":" + loserStartingStrength.ToString("F3", CultureInfo.InvariantCulture) + ",\"loserCurrentStrengthAfterFinish\":" + loserCurrentStrength.ToString("F3", CultureInfo.InvariantCulture) + ",\"loserStrengthReductionFactorAfterFinish\":" + loserStrengthReductionFactor.ToString("F3", CultureInfo.InvariantCulture) + ",\"playerRenownBefore\":" + rewardPlayerRenownBefore.ToString("F3", CultureInfo.InvariantCulture) + ",\"playerRenownAfter\":" + rewardPlayerRenownAfter.ToString("F3", CultureInfo.InvariantCulture) + ",\"winnerPartyAwards\":[" + partyAwards + "]}";
                        }
                        catch (Exception telemetryException)
                        {
                            ChronicleDiagnostics.Write("postbattle-renown-telemetry-failed|detail=" + telemetryException.GetType().Name + ":" + telemetryException.Message);
                        }
                    }
                    WriteResponse(commandId, action, "completed", behavior, null, rewardTelemetryJson == null ? null : "{\"rewardTelemetry\":" + rewardTelemetryJson + "}");
                    break;
                case "battleRetreat":
                    var battleSimulationToRetreat = PlayerEncounter.CurrentBattleSimulation;
                    if (battleSimulationToRetreat == null) throw new InvalidOperationException("battleRetreat requires an active native battle simulation");
                    if (battleSimulationToRetreat.IsSimulationFinished) throw new InvalidOperationException("battleRetreat requires an unfinished battle simulation");
                    battleSimulationToRetreat.OnPlayerRetreat();
                    WriteResponse(commandId, action, "completed", behavior);
                    break;
                case "missionRetreat":
                    var missionToRetreat = Mission.Current;
                    if (missionToRetreat == null || missionToRetreat.MissionEnded) throw new InvalidOperationException("missionRetreat requires an active battle mission");
                    var battleEndLogic = missionToRetreat.GetMissionBehavior<BattleEndLogic>();
                    if (battleEndLogic == null) throw new InvalidOperationException("active mission does not expose native BattleEndLogic");
                    var exitResult = battleEndLogic.TryExit();
                    if (exitResult == BattleEndLogic.ExitResult.SurrenderSiege)
                        throw new InvalidOperationException("native TAB exit is surrender for a siege defender, not retreat");
                    if (exitResult == BattleEndLogic.ExitResult.True)
                        throw new InvalidOperationException("battle mission already ended; retreat is not applicable");
                    missionToRetreat.RetreatMission();
                    var retreatData = "{\"tryExit\":\"" + Escape(exitResult.ToString()) + "\",\"missionEnded\":" + (missionToRetreat.MissionEnded ? "true" : "false") + "}";
                    WriteResponse(commandId, action, "completed", behavior, null, retreatData);
                    break;
                case "partyTakeAll":
                    var activeLootPartyState = Game.Current.GameStateManager.ActiveState as PartyState;
                    var lootTypeName = ReadString(command, "troopType");
                    if (activeLootPartyState?.PartyScreenLogic == null || activeLootPartyState.PartyScreenMode.ToString() != "Loot")
                        throw new InvalidOperationException("partyTakeAll requires the native postbattle loot PartyState");
                    var lootTroopType = lootTypeName == "members"
                        ? PartyScreenLogic.TroopType.Member
                        : lootTypeName == "prisoners" ? PartyScreenLogic.TroopType.Prisoner : (PartyScreenLogic.TroopType?)null;
                    if (!lootTroopType.HasValue) throw new InvalidOperationException("troopType must be members or prisoners");
                    var lootRoster = activeLootPartyState.PartyScreenLogic.GetRoster(PartyScreenLogic.PartyRosterSide.Left, lootTroopType.Value);
                    if (lootRoster.Count == 0 || !lootRoster.GetTroopRoster().Any(element => element.Character != null && element.Number > 0 && activeLootPartyState.PartyScreenLogic.IsTroopTransferable(lootTroopType.Value, element.Character, (int)PartyScreenLogic.PartyRosterSide.Left)))
                        throw new InvalidOperationException("no transferable loot of the requested type is available");
                    var takeAllCommand = new PartyScreenLogic.PartyCommand();
                    takeAllCommand.FillForTransferAllTroops(PartyScreenLogic.PartyRosterSide.Left, lootTroopType.Value);
                    activeLootPartyState.PartyScreenLogic.AddCommand(takeAllCommand);
                    activeLootPartyState.PartyScreenLogic.RemoveZeroCounts();
                    WriteResponse(commandId, action, "completed", behavior);
                    break;
                case "partyScreenDone":
                    var lootPartyStateToClose = Game.Current.GameStateManager.ActiveState as PartyState;
                    if (lootPartyStateToClose?.PartyScreenLogic == null || lootPartyStateToClose.PartyScreenMode.ToString() != "Loot")
                        throw new InvalidOperationException("partyScreenDone requires the native postbattle loot PartyState");
                    if (!lootPartyStateToClose.PartyScreenLogic.IsDoneActive()) throw new InvalidOperationException("native loot PartyScreen Done is unavailable");
                    var partyScreenHandler = lootPartyStateToClose.Handler as IPartyScreenPrisonHandler;
                    if (partyScreenHandler == null) throw new InvalidOperationException("native PartyScreen Done handler is unavailable");
                    partyScreenHandler.ExecuteDoneScript();
                    WriteResponse(commandId, action, "completed", behavior);
                    break;
                case "save":
                    var saveName = ReadString(command, "name");
                    if (string.IsNullOrWhiteSpace(saveName)) throw new InvalidOperationException("save name is required");
                    _pendingSaveName = saveName;
                    _pendingSaveCommandId = commandId;
                    TaleWorlds.CampaignSystem.Campaign.Current.SaveHandler.SaveAs(saveName);
                    WriteResponse(commandId, action, "accepted", behavior);
                    break;
                case "stop":
                    ClearMissionNavigationLease("stopped");
                    ClearMissionInputLease();
                    TaleWorlds.CampaignSystem.Campaign.Current.TimeControlMode = TaleWorlds.CampaignSystem.CampaignTimeControlMode.Stop;
                    WriteResponse(commandId, action, "completed", behavior);
                    break;
                default:
                    WriteResponse(commandId, action, "rejected", behavior, "unknown action");
                    break;
            }
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

    private static void TryCaptureUnexpectedProtocolFailureFrame(string commandId, string action, Exception exception)
    {
        if (_unexpectedProtocolFailureFrameCaptured || exception is InvalidOperationException) return;
        var mode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var rootValue = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if ((mode != "visual-capture" && mode != "visual-battle-fixture") || string.IsNullOrWhiteSpace(rootValue) || !Directory.Exists(rootValue)) return;

        _unexpectedProtocolFailureFrameCaptured = true;
        try
        {
            var root = Path.GetFullPath(rootValue).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
            var imagePath = Path.GetFullPath(Path.Combine(root, "protocol-unexpected-failure-frame.bmp"));
            if (!imagePath.StartsWith(root, StringComparison.OrdinalIgnoreCase)) return;
            TaleWorlds.Engine.Utilities.TakeScreenshot(imagePath);

            var gameState = Game.Current?.GameStateManager?.ActiveState?.GetType().Name ?? string.Empty;
            var menuId = Campaign.Current?.CurrentMenuContext?.GameMenu?.StringId ?? string.Empty;
            var timeMode = Campaign.Current?.TimeControlMode.ToString() ?? string.Empty;
            var campaignDayJson = Campaign.Current != null ? CampaignTime.Now.ToDays.ToString("R", CultureInfo.InvariantCulture) : "null";
            var stack = (exception.StackTrace ?? string.Empty).Replace("\r", " ").Replace("\n", " | ");
            var message = (exception.Message ?? string.Empty).Replace("\r", " ").Replace("\n", " | ");
            var metadata = "{\"commandId\":\"" + Escape(commandId) + "\",\"action\":\"" + Escape(action) + "\",\"exceptionType\":\"" + Escape(exception.GetType().FullName) + "\",\"message\":\"" + Escape(message) + "\",\"stackTrace\":\"" + Escape(stack) + "\",\"gameState\":\"" + Escape(gameState) + "\",\"menuId\":\"" + Escape(menuId) + "\",\"timeControlMode\":\"" + Escape(timeMode) + "\",\"campaignDay\":" + campaignDayJson + "}";
            File.WriteAllText(Path.Combine(root, "protocol-unexpected-failure-frame.json"), metadata, Encoding.UTF8);
            ChronicleDiagnostics.Write("protocol-unexpected-failure-frame-captured|action=" + Escape(action) + "|path=" + imagePath);
        }
        catch (Exception captureException)
        {
            ChronicleDiagnostics.Write("protocol-unexpected-failure-frame-capture-failed|type=" + captureException.GetType().Name + "|message=" + captureException.Message);
        }
    }

    private static void RequireRoleHarnessMode()
    {
        var mode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var root = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(mode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(root) || !Directory.Exists(root))
            throw new InvalidOperationException("PartyRole fixture/diagnostics are restricted to visual Harness runs with a Harness temp directory");
    }

    private static void RequireEquipmentModifierFixtureHarnessMode()
    {
        var mode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var root = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(mode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(root) || !Directory.Exists(root))
            throw new InvalidOperationException("Equipment modifier fixture seeding/cleanup is restricted to visual Harness runs with a Harness temp directory");
    }

    private void UpdateMissionNavigationLease()
    {
        if (_missionNavigator == null) return;
        var mission = Mission.Current;
        var activeState = Game.Current?.GameStateManager?.ActiveState as MissionState;
        if (EngineTime.ApplicationTime >= _missionNavigationExpiresAt)
        {
            ClearMissionNavigationLease("timed-out");
            return;
        }
        if (mission == null || mission != _missionNavigationMission || mission.MissionEnded || activeState == null || mission.MainAgent != _missionNavigationOwner || !AgentMissionInputPatch.IsSupportedLocationMission(mission))
        {
            ClearMissionNavigationLease("scene-changed");
            return;
        }

        var currentMissionTime = mission.CurrentTime;
        var deltaTime = Math.Max(0f, Math.Min(0.25f, currentMissionTime - _lastMissionNavigationTickAt));
        _lastMissionNavigationTickAt = currentMissionTime;
        _missionNavigator.Tick(deltaTime);
        if (_missionNavigator._agentState == AgentNavigator.NavigationState.AtTargetPosition || _missionNavigator._agentState == AgentNavigator.NavigationState.NoTarget)
            ClearMissionNavigationLease("arrived");
    }

    private void ClearMissionNavigationLease(string status)
    {
        if (_missionNavigator != null)
        {
            try { _missionNavigator.ClearTarget(); }
            catch (Exception exception) { ChronicleDiagnostics.Write($"agent-mission-navigation-clear-failed|type={exception.GetType().Name}|message={exception.Message}"); }
        }
        if (_missionNavigationOwner != null && _missionNavigationOriginalController.HasValue && _missionNavigationOwner.IsActive())
        {
            try { _missionNavigationOwner.Controller = _missionNavigationOriginalController.Value; }
            catch (Exception exception) { ChronicleDiagnostics.Write($"agent-mission-controller-restore-failed|type={exception.GetType().Name}|message={exception.Message}"); }
        }
        _missionNavigator = null;
        _missionNavigationStatus = status;
        _missionNavigationOriginalController = null;
        _missionNavigationExpiresAt = 0f;
        _lastMissionNavigationTickAt = 0f;
    }

    internal static string BuildMissionNavigationObservationJson(Agent mainAgent)
    {
        var protocol = _activeInstance;
        if (protocol == null || mainAgent == null || protocol._missionNavigationMission == null || protocol._missionNavigationMission != Mission.Current || protocol._missionNavigationOwner != mainAgent || protocol._missionNavigationTargetAgentIndex < 0 || string.IsNullOrWhiteSpace(protocol._missionNavigationStatus))
            return "null";
        var x = mainAgent.Position.X - protocol._missionNavigationTargetPosition.X;
        var y = mainAgent.Position.Y - protocol._missionNavigationTargetPosition.Y;
        var z = mainAgent.Position.Z - protocol._missionNavigationTargetPosition.Z;
        var distance = Math.Sqrt(x * x + y * y + z * z);
        var remaining = protocol._missionNavigator == null ? 0.0 : Math.Max(0.0, protocol._missionNavigationExpiresAt - EngineTime.ApplicationTime);
        return "{\"status\":\"" + Escape(protocol._missionNavigationStatus) + "\",\"active\":" + (protocol._missionNavigator != null ? "true" : "false") + ",\"targetAgentIndex\":" + protocol._missionNavigationTargetAgentIndex.ToString(CultureInfo.InvariantCulture) + ",\"targetPosition\":{\"x\":" + protocol._missionNavigationTargetPosition.X.ToString("R", CultureInfo.InvariantCulture) + ",\"y\":" + protocol._missionNavigationTargetPosition.Y.ToString("R", CultureInfo.InvariantCulture) + ",\"z\":" + protocol._missionNavigationTargetPosition.Z.ToString("R", CultureInfo.InvariantCulture) + "},\"distance\":" + distance.ToString("R", CultureInfo.InvariantCulture) + ",\"secondsRemaining\":" + remaining.ToString("R", CultureInfo.InvariantCulture) + "}";
    }

    private static string BuildHarnessMissionDiagnosticsJson(Mission mission)
    {
        var mainAgent = mission?.MainAgent;
        var currentCampaignLocation = CampaignMission.Current?.Location;
        var missionAgents = mission == null ? Enumerable.Empty<Agent>() : mission.Agents.AsEnumerable();
        var notables = missionAgents
            .Where(agent => agent != null && agent.IsActive() && agent.IsHuman && agent != mainAgent)
            .Select(agent => new { Agent = agent, Character = agent.Character as CharacterObject, Hero = (agent.Character as CharacterObject)?.HeroObject })
            .Where(item => item.Hero != null && item.Hero.IsNotable)
            .Select(item => new
            {
                item.Agent,
                item.Character,
                item.Hero,
                Distance = mainAgent == null ? (double?)null : Math.Sqrt(
                    Math.Pow(mainAgent.Position.X - item.Agent.Position.X, 2) +
                    Math.Pow(mainAgent.Position.Y - item.Agent.Position.Y, 2) +
                    Math.Pow(mainAgent.Position.Z - item.Agent.Position.Z, 2))
            })
            .OrderBy(item => item.Distance ?? double.MaxValue)
            .ToArray();
        var locationIssueOwners = currentCampaignLocation == null
            ? Array.Empty<Hero>()
            : currentCampaignLocation.GetCharacterList()
                .Where(locationCharacter => locationCharacter?.Character?.HeroObject?.Issue != null)
                .Select(locationCharacter => locationCharacter.Character.HeroObject)
                .Distinct()
                .OrderBy(hero => hero.StringId, StringComparer.Ordinal)
                .ToArray();

        var json = new StringBuilder(1024);
        json.Append('{');
        json.Append("\"sceneName\":\"").Append(Escape(mission.SceneName)).Append('"');
        json.Append(",\"campaignLocationId\":\"").Append(Escape(currentCampaignLocation?.StringId)).Append('"');
        json.Append(",\"activeAgentCount\":").Append(mission.Agents.Count(agent => agent != null && agent.IsActive()));
        json.Append(",\"notableAgentCount\":").Append(notables.Length);
        json.Append(",\"issueNotableCount\":").Append(notables.Count(item => item.Hero.Issue != null));
        json.Append(",\"notableAgents\":[");
        for (var index = 0; index < notables.Length; index++)
        {
            if (index > 0) json.Append(',');
            var item = notables[index];
            json.Append('{');
            json.Append("\"agentIndex\":").Append(item.Agent.Index);
            json.Append(",\"characterId\":\"").Append(Escape(item.Character?.StringId)).Append('"');
            json.Append(",\"heroId\":\"").Append(Escape(item.Hero.StringId)).Append('"');
            json.Append(",\"name\":\"").Append(Escape(item.Hero.Name?.ToString())).Append('"');
            json.Append(",\"occupation\":\"").Append(Escape(item.Hero.Occupation.ToString())).Append('"');
            json.Append(",\"hasIssue\":").Append(item.Hero.Issue != null ? "true" : "false");
            json.Append(",\"issueType\":\"").Append(Escape(item.Hero.Issue?.GetType().Name)).Append('"');
            json.Append(",\"distance\":").Append(item.Distance.HasValue ? item.Distance.Value.ToString("R", CultureInfo.InvariantCulture) : "null");
            json.Append(",\"position\":{\"x\":").Append(item.Agent.Position.X.ToString("R", CultureInfo.InvariantCulture));
            json.Append(",\"y\":").Append(item.Agent.Position.Y.ToString("R", CultureInfo.InvariantCulture));
            json.Append(",\"z\":").Append(item.Agent.Position.Z.ToString("R", CultureInfo.InvariantCulture)).Append("}}");
        }
        json.Append(']');
        json.Append(",\"locationIssueOwnerCount\":").Append(locationIssueOwners.Length);
        json.Append(",\"locationIssueOwners\":[");
        for (var index = 0; index < locationIssueOwners.Length; index++)
        {
            if (index > 0) json.Append(',');
            var hero = locationIssueOwners[index];
            json.Append('{');
            json.Append("\"heroId\":\"").Append(Escape(hero.StringId)).Append('"');
            json.Append(",\"name\":\"").Append(Escape(hero.Name?.ToString())).Append('"');
            json.Append(",\"isNotable\":").Append(hero.IsNotable ? "true" : "false");
            json.Append(",\"issueType\":\"").Append(Escape(hero.Issue?.GetType().Name)).Append('"');
            json.Append('}');
        }
        json.Append("]}");
        return json.ToString();
    }

    private static string BuildHarnessMapDiagnosticsJson()
    {
        var settlements = Settlement.All
            .Where(settlement => settlement != null && settlement.IsActive)
            .OrderBy(settlement => settlement.StringId, StringComparer.Ordinal)
            .ToArray();
        var json = new StringBuilder(2048);
        json.Append('{');
        json.Append("\"activeSettlementCount\":").Append(settlements.Length);
        json.Append(",\"visibleSettlementCount\":").Append(settlements.Count(settlement => settlement.IsVisible));
        json.Append(",\"hiddenSettlementCount\":").Append(settlements.Count(settlement => !settlement.IsVisible));
        json.Append(",\"settlements\":[");
        for (var index = 0; index < settlements.Length; index++)
        {
            if (index > 0) json.Append(',');
            var settlement = settlements[index];
            json.Append('{');
            json.Append("\"id\":\"").Append(Escape(settlement.StringId)).Append('"');
            json.Append(",\"name\":\"").Append(Escape(settlement.Name?.ToString())).Append('"');
            var settlementType = settlement.IsTown ? "town" : settlement.IsCastle ? "castle" : settlement.IsVillage ? "village" : settlement.IsHideout ? "hideout" : "other";
            json.Append(",\"type\":\"").Append(settlementType).Append('"');
            json.Append(",\"isVisible\":").Append(settlement.IsVisible ? "true" : "false");
            json.Append(",\"isInspected\":").Append(settlement.IsInspected ? "true" : "false");
            json.Append('}');
        }
        json.Append("]}");
        return json.ToString();
    }

    private static string BuildHarnessPlayerSkillsDiagnosticsJson()
    {
        var hero = Hero.MainHero;
        var skills = TaleWorlds.CampaignSystem.Extensions.Skills.All
            .Where(skill => skill != null)
            .OrderBy(skill => skill.StringId, StringComparer.Ordinal)
            .ToArray();
        var json = new StringBuilder(1024);
        json.Append('{');
        json.Append("\"heroId\":\"").Append(Escape(hero?.StringId)).Append('"');
        json.Append(",\"skills\":[");
        for (var index = 0; index < skills.Length; index++)
        {
            if (index > 0) json.Append(',');
            var skill = skills[index];
            json.Append('{');
            json.Append("\"id\":\"").Append(Escape(skill.StringId)).Append('"');
            json.Append(",\"level\":").Append(hero.GetSkillValue(skill));
            json.Append('}');
        }
        json.Append("]}");
        return json.ToString();
    }

    private static string BuildHarnessCharacterDevelopmentDiagnosticsJson()
    {
        var hero = Hero.MainHero;
        if (hero == null) throw new InvalidOperationException("MainHero is unavailable");
        var viewModel = new TaleWorlds.CampaignSystem.ViewModelCollection.CharacterDeveloper.CharacterDeveloperHeroItemVM(hero, () => { });
        var json = new StringBuilder(4096);
        json.Append('{');
        json.Append("\"heroId\":\"").Append(Escape(hero.StringId)).Append('"');
        json.Append(",\"level\":").Append(hero.Level);
        json.Append(",\"currentTotalXp\":").Append(viewModel.CurrentTotalXp);
        json.Append(",\"xpRequiredForNextLevel\":").Append(viewModel.XpRequiredForNextLevel);
        json.Append(",\"unspentFocusPoints\":").Append(viewModel.UnspentCharacterPoints);
        json.Append(",\"unspentAttributePoints\":").Append(viewModel.UnspentAttributePoints);
        json.Append(",\"attributes\":[");
        for (var index = 0; index < viewModel.Attributes.Count; index++)
        {
            if (index > 0) json.Append(',');
            var attribute = viewModel.Attributes[index];
            json.Append('{');
            json.Append("\"id\":\"").Append(Escape(attribute.AttributeType.StringId)).Append('"');
            json.Append(",\"name\":\"").Append(Escape(attribute.Name)).Append('"');
            json.Append(",\"value\":").Append(attribute.AttributeValue).Append('}');
        }
        json.Append(']');
        json.Append(",\"skills\":[");
        for (var index = 0; index < viewModel.Skills.Count; index++)
        {
            if (index > 0) json.Append(',');
            var skill = viewModel.Skills[index];
            json.Append('{');
            json.Append("\"id\":\"").Append(Escape(skill.SkillId)).Append('"');
            json.Append(",\"name\":\"").Append(Escape(skill.NameText)).Append('"');
            json.Append(",\"level\":").Append(skill.Level);
            json.Append(",\"experienceProgress\":").Append(skill.CurrentSkillXP);
            json.Append(",\"experienceRequiredForNextLevel\":").Append(skill.XpRequiredForNextLevel);
            json.Append(",\"focus\":").Append(skill.CurrentFocusLevel);
            json.Append(",\"learningRate\":").Append(skill.LearningRate.ToString("R", CultureInfo.InvariantCulture));
            json.Append(",\"learningLimit\":").Append(skill.FullLearningRateLevel);
            json.Append(",\"canAddFocus\":").Append(skill.CanAddFocus ? "true" : "false");
            json.Append(",\"unopenedPerks\":").Append(skill.NumOfUnopenedPerks);
            json.Append(",\"perks\":[");
            for (var perkIndex = 0; perkIndex < skill.Perks.Count; perkIndex++)
            {
                if (perkIndex > 0) json.Append(',');
                var perk = skill.Perks[perkIndex];
                json.Append('{');
                json.Append("\"id\":\"").Append(Escape(perk.Perk.StringId)).Append('"');
                json.Append(",\"requiredSkillLevel\":").Append(perk.Level);
                json.Append(",\"alternativeId\":");
                if (perk.Perk.AlternativePerk == null) json.Append("null");
                else json.Append('"').Append(Escape(perk.Perk.AlternativePerk.StringId)).Append('"');
                json.Append(",\"state\":").Append(perk.PerkState);
                json.Append(",\"alternativeType\":").Append(perk.AlternativeType).Append('}');
            }
            json.Append("]}");
        }
        json.Append("]}");
        return json.ToString();
    }

    private static string BuildHarnessQuestDetailsDiagnosticsJson(QuestBase quest)
    {
        if (quest == null) throw new InvalidOperationException("Active observed Quest is unavailable");
        var viewModel = new TaleWorlds.CampaignSystem.ViewModelCollection.Quests.QuestItemVM(quest, _ => { });
        var json = new StringBuilder(2048);
        json.Append('{');
        json.Append("\"questId\":\"").Append(Escape(quest.StringId)).Append('"');
        json.Append(",\"title\":\"").Append(Escape(viewModel.Name)).Append('"');
        json.Append(",\"isSpecialQuest\":").Append(quest.IsSpecialQuest ? "true" : "false");
        json.Append(",\"isTracked\":").Append(viewModel.IsTracked ? "true" : "false");
        json.Append(",\"questGiverHidden\":").Append(viewModel.IsQuestGiverHeroHidden ? "true" : "false");
        json.Append(",\"questGiverId\":");
        if (quest.QuestGiver == null) json.Append("null");
        else json.Append('"').Append(Escape(quest.QuestGiver.StringId)).Append('"');
        json.Append(",\"questGiverName\":");
        if (quest.QuestGiver == null) json.Append("null");
        else json.Append('"').Append(Escape(quest.QuestGiver.Name?.ToString())).Append('"');
        json.Append(",\"isRemainingTimeHidden\":").Append(viewModel.IsRemainingDaysHidden ? "true" : "false");
        json.Append(",\"daysRemaining\":");
        if (viewModel.IsRemainingDaysHidden) json.Append("null");
        else json.Append(viewModel.RemainingDays);
        json.Append(",\"journalStages\":[");
        for (var index = 0; index < viewModel.Stages.Count; index++)
        {
            if (index > 0) json.Append(',');
            var stage = viewModel.Stages[index];
            json.Append('{');
            json.Append("\"logType\":\"").Append(Escape(stage.Log?.Type.ToString())).Append('"');
            json.Append(",\"dateText\":\"").Append(Escape(stage.DateText)).Append('"');
            json.Append(",\"description\":\"").Append(Escape(stage.DescriptionText)).Append('"');
            json.Append(",\"isLastStage\":").Append(stage.IsLastStage ? "true" : "false");
            json.Append(",\"hasTask\":").Append(stage.HasATask ? "true" : "false");
            if (stage.HasATask)
            {
                json.Append(",\"rawTaskName\":");
                if (stage.Log?.TaskName == null) json.Append("null");
                else json.Append('"').Append(Escape(stage.Log.TaskName.ToString())).Append('"');
                json.Append(",\"taskName\":\"").Append(Escape(stage.StageTask.TaskName)).Append('"');
                json.Append(",\"currentProgress\":").Append(stage.StageTask.CurrentProgress);
                json.Append(",\"targetProgress\":").Append(stage.StageTask.TargetProgress);
                json.Append(",\"progressType\":\"").Append(Escape(((LogType)stage.StageTask.ProgressType).ToString())).Append('"');
                json.Append(",\"isTaskCompleted\":").Append(stage.IsTaskCompleted ? "true" : "false");
            }
            json.Append('}');
        }
        json.Append("]}");
        return json.ToString();
    }

    private static string BuildHarnessQuestDeadlinePrivacyDiagnosticsJson()
    {
        var json = new StringBuilder(128);
        json.Append('{').Append("\"hidden\":{\"available\":true");
        ChronicleAgentObserver.AppendQuestDeadline(json, true, 14);
        json.Append("},\"visible\":{\"available\":true");
        ChronicleAgentObserver.AppendQuestDeadline(json, false, 14);
        json.Append("}}");
        return json.ToString();
    }

    private static string BuildHarnessPartyRosterDiagnosticsJson()
    {
        var party = MobileParty.MainParty;
        if (party == null) throw new InvalidOperationException("MainParty is unavailable");
        var members = party.MemberRoster.GetTroopRoster()
            .Where(element => element.Character != null && element.Number > 0)
            .OrderBy(element => element.Character.StringId, StringComparer.Ordinal)
            .ToArray();
        var prisoners = party.PrisonRoster.GetTroopRoster()
            .Where(element => element.Character != null && element.Number > 0)
            .OrderBy(element => element.Character.StringId, StringComparer.Ordinal)
            .ToArray();
        var json = new StringBuilder(4096);
        json.Append('{');
        json.Append("\"partyId\":\"").Append(Escape(party.StringId)).Append('"');
        json.Append(",\"members\":");
        AppendHarnessRosterDiagnostics(json, members);
        json.Append(",\"prisoners\":");
        AppendHarnessRosterDiagnostics(json, prisoners);
        json.Append(",\"memberTotals\":{");
        json.Append("\"totalCount\":").Append(party.MemberRoster.TotalManCount);
        json.Append(",\"healthyCount\":").Append(party.MemberRoster.TotalHealthyCount);
        json.Append(",\"woundedCount\":").Append(party.MemberRoster.TotalWounded);
        json.Append(",\"sizeLimit\":").Append(party.Party.PartySizeLimit).Append('}');
        json.Append(",\"prisonerTotals\":{");
        json.Append("\"totalCount\":").Append(party.PrisonRoster.TotalManCount);
        json.Append(",\"healthyCount\":").Append(party.PrisonRoster.TotalHealthyCount);
        json.Append(",\"woundedCount\":").Append(party.PrisonRoster.TotalWounded);
        json.Append(",\"sizeLimit\":").Append(party.Party.PrisonerSizeLimit).Append('}');
        json.Append('}');
        return json.ToString();
    }

    private static string SeedPartyUpgradeFixture()
    {
        var party = MobileParty.MainParty;
        var hero = Hero.MainHero;
        if (Campaign.Current == null || party == null || hero == null)
            throw new InvalidOperationException("Upgrade fixture requires an active MainParty and MainHero");

        TaleWorlds.CampaignSystem.CharacterObject chosenCharacter = null;
        TaleWorlds.CampaignSystem.CharacterObject chosenTarget = null;
        var chosenTargetIndex = -1;
        var chosenXpCost = 0;
        var chosenGoldCost = 0;
        foreach (var character in TaleWorlds.CampaignSystem.CharacterObject.All
            .Where(item => item != null && !item.IsHero && item.UpgradeTargets != null && item.UpgradeTargets.Length > 0 && party.MemberRoster.FindIndexOfTroop(item) < 0)
            .OrderBy(item => item.Tier).ThenBy(item => item.StringId, StringComparer.Ordinal))
        {
            for (var targetIndex = 0; targetIndex < character.UpgradeTargets.Length; targetIndex++)
            {
                var target = character.UpgradeTargets[targetIndex];
                if (target == null || target.UpgradeRequiresItemFromCategory != null) continue;
                if (!Campaign.Current.Models.PartyTroopUpgradeModel.DoesPartyHaveRequiredPerksForUpgrade(party.Party, character, target, out var _)) continue;
                var xpCost = character.GetUpgradeXpCost(party.Party, targetIndex);
                var goldCost = character.GetUpgradeGoldCost(party.Party, targetIndex);
                if (xpCost <= 0 || goldCost < 0 || goldCost > hero.Gold) continue;
                chosenCharacter = character;
                chosenTarget = target;
                chosenTargetIndex = targetIndex;
                chosenXpCost = xpCost;
                chosenGoldCost = goldCost;
                break;
            }
            if (chosenCharacter != null) break;
        }
        if (chosenCharacter == null)
            throw new InvalidOperationException("No disposable troop has an item-free, perk-eligible upgrade target affordable by MainHero");

        var membersBefore = party.MemberRoster.TotalManCount;
        var goldBefore = hero.Gold;
        party.MemberRoster.AddToCounts(chosenCharacter, 1);
        var rosterIndex = party.MemberRoster.FindIndexOfTroop(chosenCharacter);
        if (rosterIndex < 0) throw new InvalidOperationException("Harness could not seed the native MainParty troop roster");
        party.MemberRoster.SetElementXp(rosterIndex, chosenXpCost);

        var json = new StringBuilder(512);
        json.Append('{');
        json.Append("\"characterId\":\"").Append(Escape(chosenCharacter.StringId)).Append('"');
        json.Append(",\"characterName\":\"").Append(Escape(chosenCharacter.Name?.ToString())).Append('"');
        json.Append(",\"upgradeTargetIndex\":").Append(chosenTargetIndex);
        json.Append(",\"targetId\":\"").Append(Escape(chosenTarget.StringId)).Append('"');
        json.Append(",\"targetName\":\"").Append(Escape(chosenTarget.Name?.ToString())).Append('"');
        json.Append(",\"experienceCost\":").Append(chosenXpCost);
        json.Append(",\"goldCost\":").Append(chosenGoldCost);
        json.Append(",\"membersBefore\":").Append(membersBefore);
        json.Append(",\"membersAfter\":").Append(party.MemberRoster.TotalManCount);
        json.Append(",\"goldBefore\":").Append(goldBefore);
        json.Append(",\"goldAfter\":").Append(hero.Gold);
        json.Append('}');
        return json.ToString();
    }

    private static string SeedPrisonerRecruitmentFixture()
    {
        var party = MobileParty.MainParty;
        var hero = Hero.MainHero;
        if (Campaign.Current == null || party == null || hero == null)
            throw new InvalidOperationException("Prisoner recruitment fixture requires an active MainParty and MainHero");
        if (party.MemberRoster.TotalManCount > party.Party.PartySizeLimit)
            throw new InvalidOperationException("Prisoner recruitment fixture cannot establish a clean at-limit roster from an already over-limit party");

        TaleWorlds.CampaignSystem.CharacterObject chosenCharacter = null;
        var conformityCost = 0;
        var model = Campaign.Current.Models.PrisonerRecruitmentCalculationModel;
        var maxTier = Campaign.Current.Models.CharacterStatsModel.MaxCharacterTier;
        foreach (var character in TaleWorlds.CampaignSystem.CharacterObject.All
            .Where(item => item != null && !item.IsHero && item.IsRegular && item.Tier >= 2 && item.Tier <= maxTier && item.Culture != null && !item.Culture.IsBandit && item.Culture != hero.Culture && party.PrisonRoster.FindIndexOfTroop(item) < 0)
            .OrderBy(item => item.Tier).ThenBy(item => item.StringId, StringComparer.Ordinal))
        {
            var threshold = model.GetConformityNeededToRecruitPrisoner(character);
            if (threshold <= 1) continue;
            chosenCharacter = character;
            conformityCost = threshold;
            break;
        }
        if (chosenCharacter == null)
            throw new InvalidOperationException("No non-hero regular troop meets native Tier/Culture constraints for a disposable prisoner fixture");

        var filler = TaleWorlds.CampaignSystem.CharacterObject.All.FirstOrDefault(item => item != null && item != chosenCharacter && !item.IsHero && item.IsRegular && party.MemberRoster.FindIndexOfTroop(item) < 0);
        if (filler == null) throw new InvalidOperationException("No ordinary CharacterObject is available to seed the at-limit MainParty fixture");
        var membersBefore = party.MemberRoster.TotalManCount;
        var sizeLimit = party.Party.PartySizeLimit;
        var fillersAdded = Math.Max(0, sizeLimit - membersBefore);
        if (fillersAdded > 0) party.MemberRoster.AddToCounts(filler, fillersAdded);

        const int prisonerCount = 2;
        var seededConformityXp = conformityCost * prisonerCount - 1;
        party.PrisonRoster.AddToCounts(chosenCharacter, prisonerCount);
        var prisonerIndex = party.PrisonRoster.FindIndexOfTroop(chosenCharacter);
        if (prisonerIndex < 0) throw new InvalidOperationException("Harness could not seed the native MainParty prisoner roster");
        party.PrisonRoster.SetElementXp(prisonerIndex, seededConformityXp);

        var json = new StringBuilder(768);
        json.Append('{');
        json.Append("\"characterId\":\"").Append(Escape(chosenCharacter.StringId)).Append('"');
        json.Append(",\"characterName\":\"").Append(Escape(chosenCharacter.Name?.ToString())).Append('"');
        json.Append(",\"cultureId\":\"").Append(Escape(chosenCharacter.Culture.StringId)).Append('"');
        json.Append(",\"tier\":").Append(chosenCharacter.Tier);
        json.Append(",\"prisonerCount\":").Append(prisonerCount);
        json.Append(",\"conformityCostPerRecruit\":").Append(conformityCost);
        json.Append(",\"conformityXpSeeded\":").Append(seededConformityXp);
        json.Append(",\"availableCountExpected\":1");
        json.Append(",\"memberCountBefore\":").Append(membersBefore);
        json.Append(",\"memberCountAfter\":").Append(party.MemberRoster.TotalManCount);
        json.Append(",\"partySizeLimit\":").Append(sizeLimit);
        json.Append(",\"fillerTroopId\":\"").Append(Escape(filler.StringId)).Append('"');
        json.Append(",\"fillersAdded\":").Append(fillersAdded);
        json.Append('}');
        return json.ToString();
    }

    private static Hero FindCurrentObservedMissionHero(string heroId)
    {
        var mission = Mission.Current;
        var mainAgent = mission?.MainAgent;
        if (mission == null || mission.MissionEnded || mainAgent == null || !AgentMissionInputPatch.IsSupportedLocationMission(mission) || string.IsNullOrWhiteSpace(heroId))
            throw new InvalidOperationException("Companion hiring diagnostics require an observed HeroId in a live Town/Tavern Mission");
        var targetAgent = mission.Agents.FirstOrDefault(agent =>
        {
            var character = agent?.Character as TaleWorlds.CampaignSystem.CharacterObject;
            var hero = character?.HeroObject;
            if (agent == null || !agent.IsActive() || !agent.IsHuman || hero == null || !string.Equals(hero.StringId, heroId, StringComparison.Ordinal)) return false;
            var x = mainAgent.Position.X - agent.Position.X;
            var y = mainAgent.Position.Y - agent.Position.Y;
            var z = mainAgent.Position.Z - agent.Position.Z;
            return Math.Sqrt(x * x + y * y + z * z) <= 12.0;
        });
        var result = (targetAgent?.Character as TaleWorlds.CampaignSystem.CharacterObject)?.HeroObject;
        if (result == null) throw new InvalidOperationException("HeroId is not an active Hero in the current 12-unit local Mission observation");
        if (targetAgent.IsEnemyOf(mainAgent)) throw new InvalidOperationException("hostile local Hero rejected by companion hiring diagnostics");
        return result;
    }

    private static string PrepareCompanionHiringFixture(string heroId, int goldOffset)
    {
        var candidate = FindCurrentObservedMissionHero(heroId);
        var playerClan = Clan.PlayerClan;
        if (candidate.IsPlayerCompanion || candidate.PartyBelongedTo != null || candidate.Clan != null)
            throw new InvalidOperationException("Companion hiring fixture target must be an unowned, unparty Wanderer Hero");
        if (goldOffset < 0 || goldOffset > 1)
            throw new InvalidOperationException("Companion hiring Harness goldOffset must be exactly 0 (insufficient) or 1 (eligible)");
        var price = Campaign.Current.Models.CompanionHiringPriceCalculationModel.GetCompanionHiringPrice(candidate);
        var priceGold = Hero.MainHero.Gold;
        var desiredGold = price + goldOffset;
        var goldChange = desiredGold - priceGold;
        if (goldChange != 0) Hero.MainHero.ChangeHeroGold(goldChange);

        var json = new StringBuilder(768);
        json.Append('{');
        json.Append("\"heroId\":\"").Append(Escape(candidate.StringId)).Append('"');
        json.Append(",\"nativeHiringPrice\":").Append(price);
        json.Append(",\"goldBeforeSeed\":").Append(priceGold);
        json.Append(",\"goldChangeForDisposableHarnessFixture\":").Append(goldChange);
        json.Append(",\"playerGoldAfterSeed\":").Append(Hero.MainHero.Gold);
        json.Append(",\"goldStrictlyExceedsPrice\":").Append(Hero.MainHero.Gold > price ? "true" : "false");
        json.Append(",\"playerCompanionCount\":").Append(playerClan.Companions.Count);
        json.Append(",\"companionLimit\":").Append(playerClan.CompanionLimit);
        json.Append('}');
        return json.ToString();
    }

    private static string BuildCompanionHiringDiagnosticsJson(string heroId)
    {
        if (string.IsNullOrWhiteSpace(heroId)) throw new InvalidOperationException("Companion hiring diagnostics requires a HeroId");
        var candidate = Hero.AllAliveHeroes.FirstOrDefault(hero => hero != null && string.Equals(hero.StringId, heroId, StringComparison.Ordinal));
        if (candidate == null) throw new InvalidOperationException("Companion hiring diagnostics could not find the live Hero");
        var playerClan = Clan.PlayerClan;
        var memberIndex = MobileParty.MainParty?.MemberRoster?.FindIndexOfTroop(candidate.CharacterObject) ?? -1;
        var inMainParty = memberIndex >= 0;
        var json = new StringBuilder(768);
        json.Append('{');
        json.Append("\"heroId\":\"").Append(Escape(candidate.StringId)).Append('"');
        json.Append(",\"nativeHiringPrice\":").Append(Campaign.Current.Models.CompanionHiringPriceCalculationModel.GetCompanionHiringPrice(candidate));
        json.Append(",\"playerGold\":").Append(Hero.MainHero.Gold);
        json.Append(",\"playerCompanionCount\":").Append(playerClan.Companions.Count);
        json.Append(",\"companionLimit\":").Append(playerClan.CompanionLimit);
        json.Append(",\"isPlayerCompanion\":").Append(candidate.IsPlayerCompanion ? "true" : "false");
        json.Append(",\"isInPlayerClan\":").Append(candidate.Clan == playerClan ? "true" : "false");
        json.Append(",\"clanId\":\"").Append(Escape(candidate.Clan?.StringId)).Append('"');
        json.Append(",\"isInMainParty\":").Append(inMainParty ? "true" : "false");
        json.Append(",\"partyId\":\"").Append(Escape(candidate.PartyBelongedTo?.StringId)).Append('"');
        json.Append('}');
        return json.ToString();
    }

    private static string BuildHarnessMapPartyDiagnosticsJson()
    {
        var mainParty = MobileParty.MainParty;
        if (mainParty == null) throw new InvalidOperationException("MainParty is unavailable");
        var managerType = AppDomain.CurrentDomain.GetAssemblies()
            .Select(assembly => assembly.GetType("SandBox.View.Map.Managers.MobilePartyVisualManager", throwOnError: false))
            .FirstOrDefault(type => type != null);
        var manager = managerType?.GetProperty("Current", System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Static)?.GetValue(null);
        var getPartyVisual = managerType?.GetMethod("GetPartyVisual", System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance);
        if (manager == null || getPartyVisual == null) throw new InvalidOperationException("Native MobilePartyVisualManager is unavailable for map target diagnostics");
        var displayHelperType = AppDomain.CurrentDomain.GetAssemblies()
            .Select(assembly => assembly.GetType("SandBox.ViewModelCollection.SandBoxUIHelper", throwOnError: false))
            .FirstOrDefault(type => type != null);
        var healthyCountMethod = displayHelperType?.GetMethod("GetPartyHealthyCount", System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Static);
        var woundedCountMethod = displayHelperType?.GetMethod("GetAllWoundedMembersAmount", System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Static);
        var prisonerCountMethod = displayHelperType?.GetMethod("GetAllPrisonerMembersAmount", System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Static);
        if (healthyCountMethod == null || woundedCountMethod == null || prisonerCountMethod == null) throw new InvalidOperationException("Native PartyNameplate count helpers are unavailable for map target diagnostics");

        var candidates = MobileParty.All
            .Where(party => party != null && party != mainParty && party.IsActive && !party.IsGarrison && !party.IsMilitia)
            .OrderBy(party => party.StringId, StringComparer.Ordinal)
            .ToArray();
        var position = mainParty.GetPosition2D;
        var json = new StringBuilder(4096);
        json.Append('{');
        json.Append("\"activePartyEntityCount\":").Append(candidates.Length);
        json.Append(",\"mapPartyEntities\":[");
        for (var index = 0; index < candidates.Length; index++)
        {
            if (index > 0) json.Append(',');
            var party = candidates[index];
            var visual = getPartyVisual.Invoke(manager, new object[] { party.Party });
            var attachedTo = party.AttachedTo;
            var isNativeMarkerCandidate = party.Party.IsVisible && attachedTo == null;
            var visibleOrFading = (bool)(visual.GetType().GetMethod("IsVisibleOrFadingOut", System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance)?.Invoke(visual, null) ?? false);
            var healthy = (int)healthyCountMethod.Invoke(null, new object[] { party });
            var wounded = (int)woundedCountMethod.Invoke(null, new object[] { party });
            var prisoners = (int)prisonerCountMethod.Invoke(null, new object[] { party });
            var partyPosition = party.GetPosition2D;
            var distanceX = position.X - partyPosition.X;
            var distanceY = position.Y - partyPosition.Y;
            var distance = Math.Sqrt(distanceX * distanceX + distanceY * distanceY);
            json.Append('{');
            json.Append("\"id\":\"").Append(Escape(party.StringId)).Append('"');
            json.Append(",\"mapFactionId\":\"").Append(Escape(party.MapFaction?.StringId)).Append('"');
            var partyName = party.Army != null && party.Army.DoesLeaderPartyAndAttachedPartiesContain(party) ? party.ArmyName?.ToString() : party.LeaderHero?.Name?.ToString() ?? party.Name?.ToString();
            json.Append(",\"nameplateName\":\"").Append(Escape(partyName)).Append('"');
            json.Append(",\"type\":\"").Append(Escape(ChronicleAgentObserver.GetPartyTypeForObservation(party))).Append('"');
            json.Append(",\"isActive\":true");
            json.Append(",\"isGarrison\":false,\"isMilitia\":false");
            json.Append(",\"partyBaseIsVisible\":").Append(party.Party.IsVisible ? "true" : "false");
            json.Append(",\"mobilePartyIsVisible\":").Append(party.IsVisible ? "true" : "false");
            json.Append(",\"isInspected\":").Append(party.IsInspected ? "true" : "false");
            json.Append(",\"isInfoHidden\":").Append(party.IsInfoHidden ? "true" : "false");
            json.Append(",\"attachedToLeader\":").Append(attachedTo == null ? "null" : "\"" + Escape(attachedTo.StringId) + "\"");
            json.Append(",\"isNativeMarkerCandidate\":").Append(isNativeMarkerCandidate ? "true" : "false");
            json.Append(",\"nativeVisualVisibleOrFading\":").Append(visibleOrFading ? "true" : "false");
            json.Append(",\"distance\":").Append(distance.ToString("F3", CultureInfo.InvariantCulture));
            json.Append(",\"defaultBehavior\":\"").Append(Escape(party.DefaultBehavior.ToString())).Append('"');
            json.Append(",\"moveMode\":\"").Append(Escape(party.PartyMoveMode.ToString())).Append('"');
            json.Append(",\"doNotAttackMainPartyRemainingHours\":").Append((party.Ai?.DoNotAttackMainPartyUntil.RemainingHoursFromNow ?? 0f).ToString("F3", CultureInfo.InvariantCulture));
            json.Append(",\"nameplateHealthyCount\":").Append(healthy);
            json.Append(",\"nameplateWoundedCount\":").Append(wounded);
            json.Append(",\"nameplatePrisonerCount\":").Append(prisoners);
            json.Append('}');
        }
        json.Append("]}");
        return json.ToString();
    }

    private static string BuildHarnessMapPartyCompositionDiagnosticsJson(string partyId)
    {
        var mainParty = MobileParty.MainParty;
        var party = MobileParty.All.FirstOrDefault(item => item != null && string.Equals(item.StringId, partyId, StringComparison.Ordinal));
        if (mainParty == null || party == null || party == mainParty || !party.IsActive || party.IsGarrison || party.IsMilitia || party.AttachedTo != null || !party.Party.IsVisible)
            throw new InvalidOperationException("Harness Party composition diagnostic requires a current visible independent map party");

        var isArmyLeader = party.Army != null && party.Army.LeaderParty == party;
        var rosterParties = isArmyLeader ? new[] { party }.Concat(party.AttachedParties).ToArray() : new[] { party };
        var partyRows = new System.Collections.Generic.Dictionary<string, (TaleWorlds.CampaignSystem.CharacterObject Character, int Total, int Wounded)>(StringComparer.Ordinal);
        var prisonerRows = new System.Collections.Generic.Dictionary<string, (TaleWorlds.CampaignSystem.CharacterObject Character, int Total, int Wounded)>(StringComparer.Ordinal);
        foreach (var rosterParty in rosterParties)
        {
            AddDiagnosticRosterRows(partyRows, rosterParty.MemberRoster);
            AddDiagnosticRosterRows(prisonerRows, rosterParty.PrisonRoster);
        }

        var tooltipType = isArmyLeader ? typeof(Army) : typeof(MobileParty);
        var tooltipArguments = new object[] { isArmyLeader ? (object)party.Army : party, false, true };
        var tooltipVmType = AppDomain.CurrentDomain.GetAssemblies()
            .Select(assembly => assembly.GetType("TaleWorlds.Core.ViewModelCollection.Information.PropertyBasedTooltipVM", throwOnError: false))
            .FirstOrDefault(type => type != null);
        if (tooltipVmType == null) throw new InvalidOperationException("Native PropertyBasedTooltipVM is unavailable for expanded tooltip diagnostics");
        var nativeTooltip = Activator.CreateInstance(tooltipVmType, new object[] { tooltipType, tooltipArguments });
        tooltipVmType.GetProperty("IsExtended")?.SetValue(nativeTooltip, true);
        var properties = tooltipVmType.GetProperty("TooltipPropertyList")?.GetValue(nativeTooltip) as System.Collections.IEnumerable;
        if (properties == null) throw new InvalidOperationException("Native tooltip property list is unavailable for expanded tooltip diagnostics");

        var json = new StringBuilder(4096);
        json.Append('{');
        json.Append("\"partyId\":\"").Append(Escape(party.StringId)).Append('"');
        json.Append(",\"mapFactionId\":\"").Append(Escape(party.MapFaction?.StringId)).Append('"');
        json.Append(",\"isInspected\":").Append(party.IsInspected ? "true" : "false");
        json.Append(",\"isInfoHidden\":").Append(party.IsInfoHidden ? "true" : "false");
        json.Append(",\"isArmyLeader\":").Append(isArmyLeader ? "true" : "false");
        json.Append(",\"memberRoster\":");
        AppendHarnessPartyRosterRows(json, partyRows);
        json.Append(",\"prisonRoster\":");
        AppendHarnessPartyRosterRows(json, prisonerRows);
        json.Append(",\"nativeTooltipProperties\":[");
        var propertyIndex = 0;
        foreach (var property in properties)
        {
            if (propertyIndex++ > 0) json.Append(',');
            json.Append('{');
            var propertyType = property.GetType();
            json.Append("\"definition\":\"").Append(Escape(propertyType.GetProperty("DefinitionLabel")?.GetValue(property)?.ToString())).Append('"');
            json.Append(",\"value\":\"").Append(Escape(propertyType.GetProperty("ValueLabel")?.GetValue(property)?.ToString())).Append('"');
            json.Append('}');
        }
        json.Append("]}");
        return json.ToString();
    }

    private static void AddDiagnosticRosterRows(
        System.Collections.Generic.Dictionary<string, (TaleWorlds.CampaignSystem.CharacterObject Character, int Total, int Wounded)> rows,
        TaleWorlds.CampaignSystem.Roster.TroopRoster roster)
    {
        for (var index = 0; index < roster.Count; index++)
        {
            var element = roster.GetElementCopyAtIndex(index);
            if (element.Character == null || element.Number <= 0) continue;
            var id = element.Character.StringId;
            if (rows.TryGetValue(id, out var current))
                rows[id] = (current.Character, current.Total + element.Number, current.Wounded + element.WoundedNumber);
            else
                rows[id] = (element.Character, element.Number, element.WoundedNumber);
        }
    }

    private static void AppendHarnessPartyRosterRows(
        StringBuilder json,
        System.Collections.Generic.Dictionary<string, (TaleWorlds.CampaignSystem.CharacterObject Character, int Total, int Wounded)> rows)
    {
        json.Append('[');
        var first = true;
        foreach (var row in rows.OrderBy(item => item.Key, StringComparer.Ordinal))
        {
            if (!first) json.Append(',');
            first = false;
            json.Append('{');
            json.Append("\"characterId\":\"").Append(Escape(row.Key)).Append('"');
            json.Append(",\"name\":\"").Append(Escape(row.Value.Character.Name?.ToString())).Append('"');
            json.Append(",\"totalCount\":").Append(row.Value.Total);
            json.Append(",\"healthyCount\":").Append(Math.Max(row.Value.Total - row.Value.Wounded, 0));
            json.Append(",\"woundedCount\":").Append(row.Value.Wounded);
            json.Append(",\"isHero\":").Append(row.Value.Character.IsHero ? "true" : "false");
            json.Append('}');
        }
        json.Append(']');
    }

    private static string CreateMapArmyFixture(string leaderPartyId, string attachedPartyId)
    {
        var leaderParty = MobileParty.All.FirstOrDefault(item => item != null && string.Equals(item.StringId, leaderPartyId, StringComparison.Ordinal));
        var kingdom = leaderParty?.MapFaction as Kingdom;
        if (leaderParty == null || kingdom == null || leaderParty == MobileParty.MainParty || !leaderParty.IsActive || !leaderParty.IsVisible || !leaderParty.IsInspected || leaderParty.IsGarrison || leaderParty.IsMilitia || leaderParty.AttachedTo != null || leaderParty.Army != null || leaderParty.LeaderHero == null)
            throw new InvalidOperationException("A native Harness Army requires a current visible inspected independent Lord Party without an Army");
        var attachedParty = string.IsNullOrWhiteSpace(attachedPartyId) ? null : MobileParty.All.FirstOrDefault(item => item != null && string.Equals(item.StringId, attachedPartyId, StringComparison.Ordinal));
        if (attachedPartyId != null && (attachedParty == null || attachedParty == leaderParty || attachedParty == MobileParty.MainParty || attachedParty.MapFaction != kingdom || !attachedParty.IsActive || !attachedParty.IsVisible || !attachedParty.IsInspected || attachedParty.IsGarrison || attachedParty.IsMilitia || attachedParty.AttachedTo != null || attachedParty.Army != null))
            throw new InvalidOperationException("A native Harness Army attachment requires a second current visible inspected independent Party in the same Kingdom");
        var gatheringFocus = leaderParty.TargetSettlement ?? leaderParty.CurrentSettlement ?? kingdom.Settlements.FirstOrDefault(settlement => settlement.IsFortification && !settlement.IsUnderSiege) ?? kingdom.Settlements.FirstOrDefault();
        if (gatheringFocus == null) throw new InvalidOperationException("A native Harness Army requires an available focus settlement");

        var kingdomArmyCountBefore = kingdom.Armies.Count;
        var partiesToCall = attachedParty == null ? null : new TaleWorlds.Library.MBList<MobileParty> { attachedParty };
        kingdom.CreateArmy(leaderParty.LeaderHero, gatheringFocus, Army.ArmyTypes.Patrolling, partiesToCall);
        var army = leaderParty.Army;
        if (army == null || army.LeaderParty != leaderParty || !kingdom.Armies.Contains(army))
            throw new InvalidOperationException("Native Kingdom.CreateArmy did not create a registered Army for the selected Lord Party");
        if (attachedParty != null)
        {
            if (attachedParty.Army != army) throw new InvalidOperationException("Native Kingdom.CreateArmy did not enlist the selected secondary Party");
            army.AddPartyToMergedParties(attachedParty);
        }
        var json = new StringBuilder(512);
        json.Append('{');
        json.Append("\"leaderPartyId\":\"").Append(Escape(leaderParty.StringId)).Append('"');
        json.Append(",\"armyType\":\"").Append(Escape(army.ArmyType.ToString())).Append('"');
        json.Append(",\"armyRegisteredInKingdom\":true");
        json.Append(",\"armyCountBefore\":").Append(kingdomArmyCountBefore);
        json.Append(",\"armyCountAfter\":").Append(kingdom.Armies.Count);
        json.Append(",\"attachedPartyCount\":").Append(leaderParty.AttachedParties.Count);
        json.Append(",\"temporaryAttachedPartyEnlisted\":").Append(attachedParty != null && attachedParty.Army == army ? "true" : "false");
        json.Append('}');
        return json.ToString();
    }

    private static void AppendHarnessRosterDiagnostics(StringBuilder json, TaleWorlds.CampaignSystem.Roster.TroopRosterElement[] elements)
    {
        json.Append('[');
        for (var index = 0; index < elements.Length; index++)
        {
            if (index > 0) json.Append(',');
            var element = elements[index];
            var character = element.Character;
            json.Append('{');
            json.Append("\"characterId\":\"").Append(Escape(character.StringId)).Append('"');
            json.Append(",\"name\":\"").Append(Escape(character.Name?.ToString())).Append('"');
            json.Append(",\"tier\":").Append(character.Tier);
            json.Append(",\"count\":").Append(element.Number);
            json.Append(",\"woundedCount\":").Append(element.WoundedNumber);
            json.Append(",\"healthyCount\":").Append(Math.Max(element.Number - element.WoundedNumber, 0));
            json.Append(",\"isHero\":").Append(character.IsHero ? "true" : "false");
            json.Append(",\"isHeroWounded\":").Append(character.IsHero && character.HeroObject != null && character.HeroObject.IsWounded ? "true" : "false");
            json.Append('}');
        }
        json.Append(']');
    }

    private static QuestBase FindObservedOngoingQuest(string questId)
    {
        if (string.IsNullOrWhiteSpace(questId)) throw new InvalidOperationException("questId must come from the current state.quests observation");
        var campaign = Campaign.Current;
        if (campaign?.QuestManager == null) throw new InvalidOperationException("Campaign QuestManager is unavailable");
        var visibleQuests = campaign.QuestManager.Quests.Where(quest => quest != null && quest.IsOngoing).Take(12);
        var quest = visibleQuests.FirstOrDefault(item => string.Equals(item.StringId, questId, StringComparison.Ordinal));
        if (quest == null) throw new InvalidOperationException("questId is not among the currently observed ongoing Quest entries");
        return quest;
    }

    private static string SpendMainHeroSkillFocus(string command)
    {
        var skillId = ReadString(command, "skillId");
        if (string.IsNullOrWhiteSpace(skillId)) throw new InvalidOperationException("skillId must come from the current characterDevelopment observation");
        var count = ReadRequiredInteger(command, "count");
        if (count < 1 || count > 100) throw new InvalidOperationException("count must be between 1 and 100");

        var campaign = Campaign.Current;
        var hero = Hero.MainHero;
        if (campaign == null || hero?.HeroDeveloper == null) throw new InvalidOperationException("MainHero development is unavailable");
        var skillObject = TaleWorlds.CampaignSystem.Extensions.Skills.All
            .FirstOrDefault(skill => skill != null && string.Equals(skill.StringId, skillId, StringComparison.Ordinal));
        if (skillObject == null) throw new InvalidOperationException("skillId is not an active Campaign SkillObject");

        var viewModel = new TaleWorlds.CampaignSystem.ViewModelCollection.CharacterDeveloper.CharacterDeveloperHeroItemVM(hero, () => { });
        var skillViewModel = viewModel.Skills.FirstOrDefault(skill => string.Equals(skill.SkillId, skillId, StringComparison.Ordinal));
        if (skillViewModel == null) throw new InvalidOperationException("skillId is not present in MainHero's Character Developer view");

        var developer = hero.HeroDeveloper;
        var focusBefore = developer.GetFocus(skillObject);
        var pointsBefore = developer.UnspentFocusPoints;
        var maxFocus = campaign.Models.CharacterDevelopmentModel.MaxFocusPerSkill;
        if (count > maxFocus - focusBefore) throw new InvalidOperationException("requested count exceeds the native maximum Focus for this skill");
        var focusPointCost = developer.GetRequiredFocusPointsToAddFocus(skillObject);
        if ((long)count * focusPointCost > pointsBefore) throw new InvalidOperationException("requested count exceeds MainHero's unspent Focus points");

        var learningRateBefore = campaign.Models.CharacterDevelopmentModel.CalculateLearningRate(hero.CharacterAttributes, focusBefore, hero.GetSkillValue(skillObject), skillObject).ResultNumber;
        skillViewModel.ExecuteInspect();
        for (var index = 0; index < count; index++)
        {
            if (!skillViewModel.CanAddFocus)
            {
                viewModel.ResetChanges(isCancel: true);
                throw new InvalidOperationException("native Character Developer no longer permits the requested Focus allocation");
            }
            skillViewModel.ExecuteAddFocus();
        }
        if (skillViewModel.CurrentFocusLevel != focusBefore + count)
        {
            viewModel.ResetChanges(isCancel: true);
            throw new InvalidOperationException("native Character Developer did not stage the full requested Focus allocation");
        }

        skillViewModel.ApplyChanges();
        var focusAfter = developer.GetFocus(skillObject);
        var pointsAfter = developer.UnspentFocusPoints;
        if (focusAfter != focusBefore + count || pointsAfter != pointsBefore - count * focusPointCost)
            throw new InvalidOperationException("native HeroDeveloper result differs from the staged Character Developer transaction");
        var learningRateAfter = campaign.Models.CharacterDevelopmentModel.CalculateLearningRate(hero.CharacterAttributes, focusAfter, hero.GetSkillValue(skillObject), skillObject).ResultNumber;

        var json = new StringBuilder(256);
        json.Append('{');
        json.Append("\"skillId\":\"").Append(Escape(skillId)).Append('"');
        json.Append(",\"requestedCount\":").Append(count);
        json.Append(",\"committedCount\":").Append(focusAfter - focusBefore);
        json.Append(",\"focusBefore\":").Append(focusBefore);
        json.Append(",\"focusAfter\":").Append(focusAfter);
        json.Append(",\"focusPointsBefore\":").Append(pointsBefore);
        json.Append(",\"focusPointsAfter\":").Append(pointsAfter);
        json.Append(",\"focusPointCost\":").Append(focusPointCost);
        json.Append(",\"learningRateBefore\":").Append(learningRateBefore.ToString("R", CultureInfo.InvariantCulture));
        json.Append(",\"learningRateAfter\":").Append(learningRateAfter.ToString("R", CultureInfo.InvariantCulture));
        json.Append('}');
        return json.ToString();
    }

    private void UpdateMissionInputLease()
    {
        if (_missionInputAgent == null) return;
        var mission = Mission.Current;
        var activeState = Game.Current?.GameStateManager?.ActiveState as MissionState;
        if (EngineTime.ApplicationTime >= _missionInputExpiresAt || mission == null || mission.MissionEnded || activeState == null || mission.MainAgent != _missionInputAgent || !_missionInputAgent.IsActive())
        {
            ClearMissionInputLease();
            return;
        }
        _missionInputAgent.MovementInputVector = _missionInputVector;
    }


    internal static void ApplyMissionInputAfterNativeControl(Agent agent)
    {
        var protocol = _activeInstance;
        if (protocol == null || agent == null || protocol._missionInputAgent != agent || EngineTime.ApplicationTime >= protocol._missionInputExpiresAt)
            return;

        var mission = Mission.Current;
        if (mission == null || mission.MissionEnded || mission.MainAgent != agent || !agent.IsActive()) return;
        if (!AgentMissionInputPatch.IsSupportedLocationMission(mission))
            return;
        agent.MovementInputVector = protocol._missionInputVector;
    }

    private void ClearMissionInputLease()
    {
        if (_missionInputAgent != null && _missionInputAgent.IsActive())
            _missionInputAgent.MovementInputVector = TaleWorlds.Library.Vec2.Zero;
        _missionInputAgent = null;
        _missionInputVector = TaleWorlds.Library.Vec2.Zero;
        _missionInputExpiresAt = 0f;
    }

    private void CompleteRestIfReady(ChronicleCampaignBehavior behavior)
    {
        if (_restCommandId == null || !_restTargetDay.HasValue) return;
        var menu = TaleWorlds.CampaignSystem.Campaign.Current.CurrentMenuContext?.GameMenu;
        var commandId = _restCommandId;
        if (menu == null || menu.StringId != "town_wait_menus" || !menu.IsWaitMenu || !Campaign.Current.IsMainPartyWaiting)
        {
            WriteResponse(commandId, "rest", "failed", behavior, "settlement wait was interrupted before the requested time elapsed");
            _restCommandId = null;
            _restTargetDay = null;
            return;
        }
        if (CampaignTime.Now.ToDays >= _restTargetDay.Value)
        {
            WriteResponse(commandId, "rest", "completed", behavior);
            _restCommandId = null;
            _restTargetDay = null;
        }
    }

    private void ApplyMapClickTimeChange(bool isDoubleClick)
    {
        var mode = BannerlordConfig.MapDoubleClickBehavior;
        var campaign = Campaign.Current;
        switch (mode)
        {
            case 0:
                if (!isDoubleClick && campaign.TimeControlMode == CampaignTimeControlMode.StoppableFastForward)
                {
                    _waitForDoubleClickUntilTime = EngineTime.ApplicationTime + 0.3f;
                    campaign.TimeControlMode = CampaignTimeControlMode.StoppableFastForward;
                }
                else
                {
                    campaign.TimeControlMode = isDoubleClick ? CampaignTimeControlMode.StoppableFastForward : CampaignTimeControlMode.StoppablePlay;
                }
                break;
            case 1:
                if (isDoubleClick)
                    campaign.TimeControlMode = campaign.TimeControlMode == CampaignTimeControlMode.StoppableFastForward ? CampaignTimeControlMode.StoppablePlay : CampaignTimeControlMode.StoppableFastForward;
                else
                    campaign.TimeControlMode = campaign.TimeControlMode == CampaignTimeControlMode.StoppableFastForward ? CampaignTimeControlMode.StoppableFastForward : CampaignTimeControlMode.StoppablePlay;
                break;
            case 2:
                campaign.TimeControlMode = campaign.TimeControlMode == CampaignTimeControlMode.StoppableFastForward ? CampaignTimeControlMode.StoppableFastForward : CampaignTimeControlMode.StoppablePlay;
                break;
        }
    }

    private void CompleteDeferredMapClickTimeChange()
    {
        if (_waitForDoubleClickUntilTime <= 0f || _waitForDoubleClickUntilTime >= EngineTime.ApplicationTime) return;
        if (BannerlordConfig.MapDoubleClickBehavior == 0 && Campaign.Current.TimeControlMode == CampaignTimeControlMode.StoppableFastForward)
            Campaign.Current.TimeControlMode = CampaignTimeControlMode.StoppablePlay;
        _waitForDoubleClickUntilTime = 0f;
    }

    private void CompleteAdvanceIfReady(ChronicleCampaignBehavior behavior)
    {
        if (!_advanceTargetDay.HasValue) return;
        var interruptedByEncounter = PlayerEncounter.IsActive;
        if (!interruptedByEncounter && CampaignTime.Now.ToDays < _advanceTargetDay.Value) return;
        var commandId = _advanceCommandId;
        var completionReason = interruptedByEncounter ? "encounter" : "requestedDuration";
        _advanceTargetDay = null;
        _advanceCommandId = null;
        Campaign.Current.TimeControlMode = CampaignTimeControlMode.Stop;
        var dataJson = "{\"completedBy\":\"" + completionReason + "\"}";
        WriteResponse(commandId, "advance", "completed", behavior, null, dataJson);
    }

    internal void OnSaveOver(bool successful, string saveName, ChronicleCampaignBehavior behavior)
    {
        if (_pendingSaveName == null || !string.Equals(_pendingSaveName, saveName, StringComparison.Ordinal)) return;
        _pendingSaveName = null;
        WriteResponse(_pendingSaveCommandId, "save", successful ? "completed" : "rejected", behavior, successful ? null : "save failed");
        _pendingSaveCommandId = null;
    }

    private void WriteResponse(string commandId, string action, string status, ChronicleCampaignBehavior behavior, string error = null, string dataJson = null)
    {
        var response = "{\"protocolVersion\":1,\"commandId\":\"" + Escape(commandId) + "\",\"action\":\"" + Escape(action) + "\",\"status\":\"" + Escape(status) + "\",\"processId\":" + Process.GetCurrentProcess().Id + ",\"campaignDay\":" + CampaignTime.Now.ToDays.ToString("F3", CultureInfo.InvariantCulture) + ",\"dailyTickCount\":" + behavior.DailyTickCount + ",\"timeControlMode\":\"" + Escape(TaleWorlds.CampaignSystem.Campaign.Current.TimeControlMode.ToString()) + "\",\"state\":" + ChronicleAgentObserver.BuildSnapshotJson() + (dataJson == null ? "" : ",\"data\":" + dataJson) + (error == null ? "" : ",\"error\":\"" + Escape(error) + "\"") + "}";
        var safeCommandId = SanitizeFileName(commandId);
        var safeStatus = SanitizeFileName(status);
        var responsePath = Path.Combine(_responseRoot, safeCommandId + "." + safeStatus + ".json");
        var temporaryPath = Path.Combine(_responseRoot, safeCommandId + "." + safeStatus + "." + Guid.NewGuid().ToString("N") + ".tmp");
        File.WriteAllText(temporaryPath, response);
        for (var attempt = 0; attempt < 5; attempt++)
        {
            try
            {
                if (File.Exists(responsePath)) File.Delete(responsePath);
                File.Move(temporaryPath, responsePath);
                File.AppendAllText(Path.Combine(_root, "events.jsonl"), response + Environment.NewLine);
                return;
            }
            catch (IOException) when (attempt < 4)
            {
                System.Threading.Thread.Sleep(20);
            }
        }
    }

    private static string SanitizeFileName(string value)
    {
        var result = value ?? string.Empty;
        foreach (var invalidCharacter in Path.GetInvalidFileNameChars()) result = result.Replace(invalidCharacter, '_');
        return string.IsNullOrWhiteSpace(result) ? "unknown" : result;
    }

    private static string ReadString(string json, string key)
    {
        var marker = "\"" + key + "\":\"";
        var start = json.IndexOf(marker, StringComparison.Ordinal);
        if (start < 0) return null;
        start += marker.Length;
        var end = json.IndexOf('"', start);
        return end < 0 ? null : json.Substring(start, end - start);
    }

    private static double ReadDouble(string json, string key)
    {
        var marker = "\"" + key + "\":";
        var start = json.IndexOf(marker, StringComparison.Ordinal);
        if (start < 0) return 0;
        start += marker.Length;
        var end = json.IndexOfAny(new[] { ',', '}' }, start);
        var value = json.Substring(start, end < 0 ? json.Length - start : end - start);
        return double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out var parsed) ? parsed : 0;
    }

    private static double ReadRequiredFiniteDouble(string json, string key)
    {
        var marker = "\"" + key + "\":";
        var start = json.IndexOf(marker, StringComparison.Ordinal);
        if (start < 0) throw new InvalidOperationException("Missing required coordinate '" + key + "'");
        start += marker.Length;
        var end = json.IndexOfAny(new[] { ',', '}' }, start);
        var value = json.Substring(start, end < 0 ? json.Length - start : end - start);
        if (!double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out var parsed) || double.IsNaN(parsed) || double.IsInfinity(parsed))
            throw new InvalidOperationException("Coordinate '" + key + "' must be a finite number");
        if (parsed > float.MaxValue || parsed < -float.MaxValue)
            throw new InvalidOperationException("Coordinate '" + key + "' exceeds the Campaign map numeric range");
        return parsed;
    }

    private static int ReadRequiredInteger(string json, string key)
    {
        var parsed = ReadRequiredFiniteDouble(json, key);
        if (parsed < int.MinValue || parsed > int.MaxValue || parsed != Math.Truncate(parsed))
            throw new InvalidOperationException("value '" + key + "' must be an integer");
        return (int)parsed;
    }

    internal static string Escape(string value) => (value ?? string.Empty).Replace("\\", "\\\\").Replace("\"", "\\\"");
}
