#nullable enable
using System;
using System.Globalization;
using System.Linq;
using System.Reflection;
using System.Text;
using SandBox.View.Map;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.Encounters;
using TaleWorlds.Core;
using TaleWorlds.MountAndBlade;
using EngineTime = TaleWorlds.Engine.Time;

namespace ChronicleFramework;

internal static class ChronicleAgentBattleMissionAdapter
{
    private static Mission? _deploymentFinishSubmittedForMission;
    private static Mission? _mainAgentAiProbeMission;
    private static Agent? _mainAgentAiProbeOwner;
    private static AgentControllerType? _mainAgentAiProbeOriginalController;
    private static float _mainAgentAiProbeExpiresAt;
    private static string? _mainAgentAiProbeStatus;

    internal static string BuildStatusJson()
    {
        var mission = Mission.Current;
        var missionStateActive = Game.Current?.GameStateManager?.ActiveState?.GetType().Name == "MissionState";
        var isCampaignEncounterBattle = mission != null &&
            missionStateActive &&
            !mission.MissionEnded &&
            !mission.IsFriendlyMission &&
            mission.IsFieldBattle &&
            PlayerEncounter.IsActive &&
            PlayerEncounter.Battle != null;
        var mainAgent = mission?.MainAgent;
        var team = mission?.PlayerTeam;
        var orderController = team?.PlayerOrderController;
        var mainAgentFormation = mainAgent?.Formation;
        var formations = team?.FormationsIncludingEmpty
            .Where(formation => formation != null && formation.CountOfUnits > 0)
            .OrderBy(formation => formation.FormationIndex)
            .ToArray() ?? Array.Empty<Formation>();
        var selected = orderController?.SelectedFormations?.ToArray() ?? Array.Empty<Formation>();
        var json = new StringBuilder(768);
        json.Append("{\"schemaVersion\":1,");
        json.Append("\"supported\":").Append(isCampaignEncounterBattle ? "true" : "false").Append(',');
        AppendString(json, "reason", isCampaignEncounterBattle ? null : GetUnsupportedReason(mission, missionStateActive));
        AppendString(json, "sceneName", mission?.SceneName);
        AppendString(json, "missionMode", mission?.Mode.ToString());
        AppendString(json, "missionCurrentState", mission?.CurrentState.ToString());
        AppendString(json, "missionCombatType", mission?.CombatType.ToString());
        AppendString(json, "missionTeamAIType", mission?.MissionTeamAIType.ToString());
        json.Append("\"campaignTimeControlMode\":");
        AppendStringValue(json, Campaign.Current?.TimeControlMode.ToString());
        json.Append(",\"campaignDay\":");
        AppendNumber(json, Campaign.Current == null ? null : CampaignTime.Now.ToDays);
        json.Append(",\"mainAgent\":");
        if (mainAgent == null || !mainAgent.IsActive()) json.Append("null");
        else
        {
            json.Append('{');
            AppendString(json, "controller", mainAgent.Controller.ToString());
            json.Append("\"isPlayerControlled\":").Append(mainAgent.IsPlayerControlled ? "true" : "false").Append(',');
            json.Append("\"isAIControlled\":").Append(mainAgent.IsAIControlled ? "true" : "false").Append(',');
            json.Append("\"health\":").Append(Number(mainAgent.Health)).Append(',');
            json.Append("\"healthLimit\":").Append(Number(mainAgent.HealthLimit)).Append(',');
            json.Append("\"isActive\":true,");
            json.Append("\"isDetachedFromFormation\":").Append(mainAgent.IsDetachedFromFormation ? "true" : "false").Append(',');
            json.Append("\"formation\":");
            if (mainAgentFormation == null) json.Append("null");
            else
            {
                json.Append('{')
                    .Append("\"formationIndex\":").Append((int)mainAgentFormation.FormationIndex)
                    .Append(",\"unitCount\":").Append(mainAgentFormation.CountOfUnits)
                    .Append(",\"isAIControlled\":").Append(mainAgentFormation.IsAIControlled ? "true" : "false")
                    .Append(",\"isPlayerOwned\":").Append(mainAgentFormation.PlayerOwner == mainAgent ? "true" : "false")
                    .Append('}');
            }
            json.Append(',');
            json.Append("\"position\":{\"x\":").Append(Number(mainAgent.Position.X))
                .Append(",\"y\":").Append(Number(mainAgent.Position.Y))
                .Append(",\"z\":").Append(Number(mainAgent.Position.Z)).Append("}}");
        }
        json.Append(",\"playerTeam\":{\"formationCount\":").Append(formations.Length)
            .Append(",\"orderControllerAvailable\":").Append(orderController == null ? "false" : "true")
            .Append(",\"selectedFormationCount\":").Append(selected.Length)
            .Append(",\"formations\":[");
        for (var index = 0; index < formations.Length; index++)
        {
            if (index > 0) json.Append(',');
            var formation = formations[index];
            json.Append('{')
                .Append("\"formationIndex\":").Append((int)formation.FormationIndex)
                .Append(",\"unitCount\":").Append(formation.CountOfUnits)
                .Append(",\"isAIControlled\":").Append(formation.IsAIControlled ? "true" : "false")
                .Append(",\"isPlayerOwned\":").Append(mainAgent != null && formation.PlayerOwner == mainAgent ? "true" : "false")
                .Append(",\"isSelected\":").Append(selected.Any(item => item == formation) ? "true" : "false")
                .Append('}');
        }
        json.Append("]},\"mainAgentAiControllerProbe\":").Append(BuildMainAgentAiControllerProbeJson()).Append('}');
        return json.ToString();
    }

    internal static string DelegateCurrentTroopFormations()
    {
        if (!TryGetSupportedBattleMission(out var mission, out var reason))
            throw new InvalidOperationException("missionDelegateTroops " + reason);

        var campaign = Campaign.Current ?? throw new InvalidOperationException("missionDelegateTroops requires an active Campaign");
        if (campaign.TimeControlMode != CampaignTimeControlMode.Stop)
            throw new InvalidOperationException("missionDelegateTroops requires the Campaign clock to remain stopped");

        var mainAgent = mission.MainAgent;
        if (mainAgent == null || !mainAgent.IsActive() || !mainAgent.IsPlayerControlled)
            throw new InvalidOperationException("missionDelegateTroops requires the active MainAgent to remain player-controlled");

        var team = mission.PlayerTeam;
        var orderController = team?.PlayerOrderController;
        if (orderController == null)
            throw new InvalidOperationException("missionDelegateTroops requires the Native player-team OrderController");

        if (orderController.SelectedFormations.Count == 0)
            orderController.SelectAllFormations(uiFeedback: false);

        var selected = orderController.SelectedFormations
            .Where(formation => formation != null && formation.CountOfUnits > 0 && formation.PlayerOwner == mainAgent)
            .OrderBy(formation => formation.FormationIndex)
            .ToArray();
        if (selected.Length == 0)
            throw new InvalidOperationException("missionDelegateTroops requires at least one selected player-owned Formation with units");

        var timeModeBefore = campaign.TimeControlMode.ToString();
        var dayBefore = CampaignTime.Now.ToDays;
        var mainControllerBefore = mainAgent.Controller.ToString();
        var selectedIndices = string.Join(",", selected.Select(formation => ((int)formation.FormationIndex).ToString(CultureInfo.InvariantCulture)));

        orderController.SetOrder(OrderType.AIControlOn);

        var delegated = selected.Where(formation => formation.IsAIControlled).ToArray();
        var timeModeAfter = campaign.TimeControlMode.ToString();
        var dayAfter = CampaignTime.Now.ToDays;
        var json = new StringBuilder(640);
        json.Append("{\"schemaVersion\":1,\"nativeOrder\":\"AIControlOn\"")
            .Append(",\"requestedFormationCount\":").Append(selected.Length)
            .Append(",\"delegatedFormationCount\":").Append(delegated.Length)
            .Append(",\"allRequestedFormationsDelegated\":").Append(delegated.Length == selected.Length ? "true" : "false")
            .Append(",\"selectedFormationIndices\":[").Append(selectedIndices).Append("]")
            .Append(",\"mainAgentControllerBefore\":"); AppendStringValue(json, mainControllerBefore);
        json.Append(",\"mainAgentControllerAfter\":"); AppendStringValue(json, mainAgent.Controller.ToString());
        json.Append(",\"mainAgentStillPlayerControlled\":").Append(mainAgent.IsPlayerControlled ? "true" : "false");
        json.Append(",\"campaignDayBefore\":").Append(Number(dayBefore))
            .Append(",\"campaignDayAfter\":").Append(Number(dayAfter));
        json.Append(",\"timeControlModeBefore\":"); AppendStringValue(json, timeModeBefore);
        json.Append(",\"timeControlModeAfter\":"); AppendStringValue(json, timeModeAfter);
        json.Append('}');
        return json.ToString();
    }

    internal static string FinishCurrentBattleDeployment()
    {
        if (!TryGetActiveCampaignFieldBattle(out var mission, out var reason))
            throw new InvalidOperationException("missionFinishDeployment " + reason);
        var campaign = Campaign.Current ?? throw new InvalidOperationException("missionFinishDeployment requires an active Campaign");
        if (campaign.TimeControlMode != CampaignTimeControlMode.Stop)
            throw new InvalidOperationException("missionFinishDeployment requires the Campaign clock to remain stopped");
        if (mission.Mode != MissionMode.Deployment)
            throw new InvalidOperationException("missionFinishDeployment requires the current Native Mission to be in Deployment mode");
        var mainAgentBefore = mission.MainAgent;
        if (mainAgentBefore != null && (!mainAgentBefore.IsActive() || !mainAgentBefore.IsPlayerControlled))
            throw new InvalidOperationException("missionFinishDeployment rejects an active non-Player MainAgent");
        if (ChronicleInquiryAdapter.IsInquiryOpen)
            throw new InvalidOperationException("missionFinishDeployment refuses to bypass an active Native Inquiry");
        if (ReferenceEquals(_deploymentFinishSubmittedForMission, mission))
            throw new InvalidOperationException("missionFinishDeployment was already submitted for this Native Mission");

        const string orderBattleViewTypeName = "TaleWorlds.MountAndBlade.GauntletUI.Mission.Singleplayer.MissionGauntletOrderOfBattleUIHandler";
        var orderBattleView = mission.MissionBehaviors.FirstOrDefault(behavior => behavior?.GetType().FullName == orderBattleViewTypeName);
        if (orderBattleView == null)
            throw new InvalidOperationException("missionFinishDeployment requires the active Native OrderOfBattle Ready view");
        var viewModelField = orderBattleView.GetType().GetField("_dataSource", BindingFlags.Instance | BindingFlags.NonPublic);
        var orderBattleViewModel = viewModelField?.GetValue(orderBattleView);
        if (orderBattleViewModel == null)
            throw new InvalidOperationException("missionFinishDeployment could not resolve the active Native OrderOfBattle view-model");
        var viewModelType = orderBattleViewModel.GetType();
        var canStartProperty = viewModelType.GetProperty("CanStartMission", BindingFlags.Instance | BindingFlags.Public);
        if (canStartProperty?.GetValue(orderBattleViewModel) is not bool canStart || !canStart)
            throw new InvalidOperationException("missionFinishDeployment refuses while the original Native Ready button is disabled");
        var executeReady = viewModelType.GetMethods(BindingFlags.Instance | BindingFlags.Public)
            .FirstOrDefault(method => method.Name == "ExecuteBeginMission" && method.GetParameters().Length == 0);
        if (executeReady == null)
            throw new InvalidOperationException("missionFinishDeployment could not resolve the original Native OrderOfBattle Ready command");

        var modeBefore = mission.Mode.ToString();
        var campaignDayBefore = CampaignTime.Now.ToDays;
        var timeModeBefore = campaign.TimeControlMode.ToString();
        try
        {
            executeReady.Invoke(orderBattleViewModel, null);
        }
        catch (TargetInvocationException exception) when (exception.InnerException != null)
        {
            throw new InvalidOperationException("missionFinishDeployment original Native Ready command failed", exception.InnerException);
        }
        _deploymentFinishSubmittedForMission = mission;
        var modeAfter = mission.Mode.ToString();
        var campaignDayAfter = CampaignTime.Now.ToDays;
        var timeModeAfter = campaign.TimeControlMode.ToString();

        var json = new StringBuilder(512);
        json.Append("{\"schemaVersion\":1,\"nativeHandler\":\"OrderOfBattleVM.ExecuteBeginMission\",\"nativeDeploymentHandler\":\"DeploymentHandler.FinishDeployment\",\"nativeUiView\":\"OrderOfBattle.xml\",\"canStartMission\":true")
            .Append(",\"modeBefore\":"); AppendStringValue(json, modeBefore);
        json.Append(",\"modeAfter\":"); AppendStringValue(json, modeAfter);
        json.Append(",\"campaignDayBefore\":").Append(Number(campaignDayBefore))
            .Append(",\"campaignDayAfter\":").Append(Number(campaignDayAfter));
        json.Append(",\"timeControlModeBefore\":"); AppendStringValue(json, timeModeBefore);
        json.Append(",\"timeControlModeAfter\":"); AppendStringValue(json, timeModeAfter);
        json.Append(",\"mainAgentPresentBefore\":").Append(mainAgentBefore != null && mainAgentBefore.IsActive() ? "true" : "false");
        json.Append(",\"mainAgentControllerBefore\":"); AppendStringValue(json, mainAgentBefore?.Controller.ToString());
        var mainAgentAfter = mission.MainAgent;
        json.Append(",\"mainAgentPresentAfter\":").Append(mainAgentAfter != null && mainAgentAfter.IsActive() ? "true" : "false");
        json.Append(",\"mainAgentControllerAfter\":"); AppendStringValue(json, mainAgentAfter?.Controller.ToString());
        json.Append('}');
        return json.ToString();
    }

    internal static string BeginMainAgentAiControllerProbe(double requestedDurationSeconds)
    {
        if (!TryGetSupportedBattleMission(out var mission, out var reason))
            throw new InvalidOperationException("harnessMainAgentAiControllerProbe " + reason);
        var campaign = Campaign.Current ?? throw new InvalidOperationException("harnessMainAgentAiControllerProbe requires an active Campaign");
        if (campaign.TimeControlMode != CampaignTimeControlMode.Stop)
            throw new InvalidOperationException("harnessMainAgentAiControllerProbe requires the Campaign clock to remain stopped");
        if (_mainAgentAiProbeOwner != null)
            throw new InvalidOperationException("harnessMainAgentAiControllerProbe refuses while another MainAgent AI probe lease is active");
        if (double.IsNaN(requestedDurationSeconds) || double.IsInfinity(requestedDurationSeconds) || requestedDurationSeconds < 1.0 || requestedDurationSeconds > 10.0)
            throw new InvalidOperationException("harnessMainAgentAiControllerProbe durationSeconds must be between 1 and 10");

        var mainAgent = mission.MainAgent;
        if (mainAgent == null || !mainAgent.IsActive() || mainAgent.Controller != AgentControllerType.Player)
            throw new InvalidOperationException("harnessMainAgentAiControllerProbe requires the active MainAgent to be Player-controlled");

        var campaignDayBefore = CampaignTime.Now.ToDays;
        var timeModeBefore = campaign.TimeControlMode.ToString();
        var controllerBefore = mainAgent.Controller.ToString();
        var positionBefore = mainAgent.Position;
        var healthBefore = mainAgent.Health;
        try
        {
            mainAgent.Controller = AgentControllerType.AI;
        }
        catch
        {
            if (mainAgent.IsActive() && mainAgent.Controller != AgentControllerType.Player)
            {
                try { mainAgent.Controller = AgentControllerType.Player; }
                catch { }
            }
            throw;
        }

        _mainAgentAiProbeMission = mission;
        _mainAgentAiProbeOwner = mainAgent;
        _mainAgentAiProbeOriginalController = AgentControllerType.Player;
        _mainAgentAiProbeExpiresAt = EngineTime.ApplicationTime + (float)requestedDurationSeconds;
        _mainAgentAiProbeStatus = "active";

        var json = new StringBuilder(512);
        json.Append("{\"schemaVersion\":1,\"scope\":\"harness-only\",\"nativeSetter\":\"Agent.Controller\",\"leaseClock\":\"EngineTime.ApplicationTime\"")
            .Append(",\"durationSeconds\":").Append(Number(requestedDurationSeconds));
        json.Append(",\"controllerBefore\":"); AppendStringValue(json, controllerBefore);
        json.Append(",\"controllerAfter\":"); AppendStringValue(json, mainAgent.Controller.ToString());
        json.Append(",\"isPlayerControlledAfter\":").Append(mainAgent.IsPlayerControlled ? "true" : "false");
        json.Append(",\"healthBefore\":").Append(Number(healthBefore))
            .Append(",\"healthAfter\":").Append(Number(mainAgent.Health));
        json.Append(",\"positionBefore\":{\"x\":").Append(Number(positionBefore.X))
            .Append(",\"y\":").Append(Number(positionBefore.Y))
            .Append(",\"z\":").Append(Number(positionBefore.Z)).Append('}');
        json.Append(",\"campaignDayBefore\":").Append(Number(campaignDayBefore))
            .Append(",\"campaignDayAfter\":").Append(Number(CampaignTime.Now.ToDays));
        json.Append(",\"timeControlModeBefore\":"); AppendStringValue(json, timeModeBefore);
        json.Append(",\"timeControlModeAfter\":"); AppendStringValue(json, campaign.TimeControlMode.ToString());
        json.Append('}');
        return json.ToString();
    }

    internal static void UpdateMainAgentAiControllerProbeLease()
    {
        if (_mainAgentAiProbeOwner == null) return;
        var mission = Mission.Current;
        var activeState = Game.Current?.GameStateManager?.ActiveState?.GetType().Name == "MissionState";
        if (EngineTime.ApplicationTime >= _mainAgentAiProbeExpiresAt)
        {
            ClearMainAgentAiControllerProbeLease("timed-out");
            return;
        }
        if (mission == null || mission != _mainAgentAiProbeMission || mission.MissionEnded || !activeState || mission.MainAgent != _mainAgentAiProbeOwner)
            ClearMainAgentAiControllerProbeLease("mission-ended-or-changed");
    }

    internal static string RestoreMainAgentAiControllerProbe()
    {
        if (_mainAgentAiProbeOwner == null || !_mainAgentAiProbeOriginalController.HasValue)
        {
            var lastStatus = _mainAgentAiProbeStatus ?? "never-started";
            var currentMainAgent = Mission.Current?.MainAgent;
            var isCurrentlyRestored = currentMainAgent == null || !currentMainAgent.IsActive() || currentMainAgent.Controller == AgentControllerType.Player;
            return "{\"schemaVersion\":1,\"status\":\"" + Escape(lastStatus) + "\",\"restored\":" + (isCurrentlyRestored ? "true" : "false") + ",\"controllerAfter\":" + (currentMainAgent == null || !currentMainAgent.IsActive() ? "null" : "\"" + Escape(currentMainAgent.Controller.ToString()) + "\"") + "}";
        }
        var owner = _mainAgentAiProbeOwner;
        ClearMainAgentAiControllerProbeLease("explicitly-restored");
        var controller = owner.IsActive() ? owner.Controller.ToString() : null;
        var restored = owner.IsActive() && controller == AgentControllerType.Player.ToString();
        return "{\"schemaVersion\":1,\"status\":\"" + Escape(_mainAgentAiProbeStatus ?? "restored") + "\",\"restored\":" + (restored ? "true" : "false") + ",\"controllerAfter\":" + (controller == null ? "null" : "\"" + Escape(controller) + "\"") + "}";
    }

    private static string BuildMainAgentAiControllerProbeJson()
    {
        var owner = _mainAgentAiProbeOwner;
        if (owner == null || _mainAgentAiProbeMission == null)
            return "{\"active\":false,\"status\":\"" + Escape(_mainAgentAiProbeStatus ?? "never-started") + "\"}";
        var remaining = Math.Max(0.0, _mainAgentAiProbeExpiresAt - EngineTime.ApplicationTime);
        return "{\"active\":true,\"status\":\"" + Escape(_mainAgentAiProbeStatus ?? "active") + "\",\"secondsRemaining\":" + Number(remaining) + ",\"controller\":\"" + Escape(owner.Controller.ToString()) + "\"}";
    }

    internal static string ClearMainAgentAiControllerProbeLease(string status)
    {
        var owner = _mainAgentAiProbeOwner;
        var original = _mainAgentAiProbeOriginalController;
        var mission = _mainAgentAiProbeMission;
        if (owner != null && original.HasValue && owner.IsActive())
        {
            if (owner.Controller == AgentControllerType.AI || owner.Controller == original.Value)
            {
                try { owner.Controller = original.Value; }
                catch (Exception exception)
                {
                    ChronicleDiagnostics.Write($"agent-main-controller-probe-restore-failed|type={exception.GetType().Name}|message={exception.Message}");
                    status = "restore-failed";
                }
            }
            else status = "controller-changed-externally";
        }
        else if (mission != null && mission.MissionEnded) status = "mission-ended";

        _mainAgentAiProbeMission = null;
        _mainAgentAiProbeOwner = null;
        _mainAgentAiProbeOriginalController = null;
        _mainAgentAiProbeExpiresAt = 0f;
        _mainAgentAiProbeStatus = status;
        return status;
    }

    private static bool TryGetSupportedBattleMission(out Mission mission, out string reason)
    {
        if (!TryGetActiveCampaignFieldBattle(out mission, out reason)) return false;
        if (mission.Mode != MissionMode.Battle)
        {
            reason = "battle mission has not left Native Deployment mode";
            return false;
        }
        reason = string.Empty;
        return true;
    }

    private static bool TryGetActiveCampaignFieldBattle(out Mission mission, out string reason)
    {
        mission = Mission.Current!;
        if (Game.Current?.GameStateManager?.ActiveState?.GetType().Name != "MissionState" || mission == null || mission.MissionEnded)
        {
            reason = "requires an active Native MissionState";
            return false;
        }
        if (mission.IsFriendlyMission || !mission.IsFieldBattle || !PlayerEncounter.IsActive || PlayerEncounter.Battle == null)
        {
            reason = "requires a Campaign field Battle Mission started from an active Native Encounter";
            return false;
        }
        reason = string.Empty;
        return true;
    }

    private static string? GetUnsupportedReason(Mission? mission, bool missionStateActive)
    {
        if (!missionStateActive) return "not in MissionState";
        if (mission == null) return "mission unavailable";
        if (mission.MissionEnded) return "mission ended";
        if (mission.IsFriendlyMission) return "friendly Mission";
        if (!mission.IsFieldBattle) return "not a field Battle Mission";
        if (!PlayerEncounter.IsActive || PlayerEncounter.Battle == null) return "no active Campaign Encounter battle";
        if (mission.Mode != MissionMode.Battle) return "battle not yet started";
        return null;
    }

    private static void AppendString(StringBuilder json, string name, string? value)
    {
        json.Append('"').Append(name).Append("\":");
        AppendStringValue(json, value);
        json.Append(',');
    }

    private static void AppendStringValue(StringBuilder json, string? value)
    {
        if (value == null) json.Append("null");
        else json.Append('"').Append(Escape(value)).Append('"');
    }

    private static void AppendNumber(StringBuilder json, double? value)
    {
        if (value == null || double.IsNaN(value.Value) || double.IsInfinity(value.Value)) json.Append("null");
        else json.Append(Number(value.Value));
    }

    private static string Number(double value) => value.ToString("R", CultureInfo.InvariantCulture);

    private static string Escape(string value) => value.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\r", "\\r").Replace("\n", "\\n");
}
