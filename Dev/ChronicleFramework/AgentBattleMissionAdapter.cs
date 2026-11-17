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
    private const float NativeThirdPersonBattleCameraElevation = -0.2f;
    private const float NativeThirdPersonBattleCameraNearVerticalThreshold = -0.7f;
    private static Mission? _deploymentFinishSubmittedForMission;
    private static Mission? _deploymentAutoDeploySubmittedForMission;
    private static Type? _nativeMainAgentControllerType;
    private static Mission? _mainAgentAiProbeMission;
    private static Agent? _mainAgentAiProbeOwner;
    private static Agent? _mainAgentAiProbeSurrogate;
    private static AgentControllerType? _mainAgentAiProbeOriginalController;
    private static AgentControllerType? _mainAgentAiProbeSurrogateOriginalController;
    private static object? _mainAgentAiProbeOriginalWatchState;
    private static bool? _mainAgentAiProbeOriginalPlayerTroopInFormation;
    private static bool _mainAgentAiProbeFullNativeHandoff;
    private static AgentFlag? _mainAgentAiProbeOriginalAgentFlags;
    private static object? _mainAgentAiProbeOriginalAiStateFlags;
    private static bool? _mainAgentAiProbeOriginalAiPaused;
    private static object? _mainAgentAiProbeMissionController;
    private static bool? _mainAgentAiProbeOriginalMissionControllerActivated;
    private static object? _mainAgentAiProbeOriginalCustomLookDir;
    private static float _mainAgentAiProbeExpiresAt;
    private static string? _mainAgentAiProbeStatus;
    private static string? _mainAgentAiProbeScope;
    private static string? _mainAgentAiProbeLastOwnerController;
    private static int? _mainAgentAiProbeLastSurrogateAgentIndex;
    private static string? _mainAgentAiProbeLastSurrogateController;
    private static int? _mainAgentAiProbeLastMissionMainAgentIndex;

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
        var mainAgentFormationActiveBehavior = mainAgentFormation?.AI?.ActiveBehavior;
        var cameraController = mission == null ? null : GetNativeMainAgentController(mission);
        TaleWorlds.Library.Vec2? mainAgentFormationAiOrderTarget = null;
        if (mainAgentFormation != null && mainAgentFormationActiveBehavior != null)
            mainAgentFormationAiOrderTarget = mainAgentFormationActiveBehavior.CurrentOrder.GetPosition(mainAgentFormation);
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
        var deploymentUi = GetDeploymentUiStatus(mission);
        json.Append("\"deploymentUi\":{\"viewAvailable\":").Append(deploymentUi.ViewAvailable ? "true" : "false")
            .Append(",\"readyCallbackBound\":").Append(deploymentUi.ReadyCallbackBound ? "true" : "false")
            .Append(",\"canStartMission\":").Append(deploymentUi.CanStartMission ? "true" : "false")
            .Append(",\"deploymentFinished\":").Append(deploymentUi.DeploymentFinished ? "true" : "false").Append("},");
        json.Append("\"campaignTimeControlMode\":");
        AppendStringValue(json, Campaign.Current?.TimeControlMode.ToString());
        json.Append(",\"campaignDay\":");
        AppendNumber(json, Campaign.Current == null ? null : CampaignTime.Now.ToDays);
        json.Append(",\"mainAgent\":");
        if (mainAgent == null || !mainAgent.IsActive()) json.Append("null");
        else
        {
            json.Append('{');
            json.Append("\"agentIndex\":").Append(mainAgent.Index).Append(',');
            AppendString(json, "controller", mainAgent.Controller.ToString());
            AppendString(json, "currentWatchState", mainAgent.CurrentWatchState.ToString());
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
                    .Append(",\"hasPlayerControlledTroop\":").Append(mainAgentFormation.HasPlayerControlledTroop ? "true" : "false")
                    .Append(",\"isPlayerTroopInFormation\":").Append(mainAgentFormation.IsPlayerTroopInFormation ? "true" : "false")
                    .Append(",\"hasActiveAiBehavior\":").Append(mainAgentFormationActiveBehavior != null ? "true" : "false")
                    .Append(",\"activeAiBehaviorType\":"); AppendStringValue(json, mainAgentFormationActiveBehavior?.GetType().Name);
                json.Append(",\"activeAiOrderType\":"); AppendStringValue(json, mainAgentFormationActiveBehavior?.CurrentOrder.OrderEnum.ToString());
                json.Append(",\"activeAiOrderTarget\":");
                if (mainAgentFormationAiOrderTarget.HasValue)
                {
                    var orderTarget = mainAgentFormationAiOrderTarget.Value;
                    json.Append("{\"x\":").Append(Number(orderTarget.X)).Append(",\"y\":").Append(Number(orderTarget.Y)).Append('}');
                    var dx = mainAgent.Position.X - orderTarget.X;
                    var dy = mainAgent.Position.Y - orderTarget.Y;
                    json.Append(",\"distanceToActiveAiOrderTarget\":").Append(Number(Math.Sqrt(dx * dx + dy * dy)));
                }
                else json.Append("null,\"distanceToActiveAiOrderTarget\":null");
                json.Append('}');
            }
            json.Append(',');
            var nativeMainAgentController = cameraController;
            json.Append("\"missionMainAgentControllerActive\":");
            try { json.Append(nativeMainAgentController == null ? "null" : ReadControllerActivated(nativeMainAgentController) ? "true" : "false"); }
            catch { json.Append("null"); }
            json.Append(',');
            json.Append("\"position\":{\"x\":").Append(Number(mainAgent.Position.X))
                .Append(",\"y\":").Append(Number(mainAgent.Position.Y))
                .Append(",\"z\":").Append(Number(mainAgent.Position.Z)).Append("}}");
            json.Append(",\"agentNavigator\":").Append(ChronicleAgentProtocol.BuildMissionNavigationObservationJson(mainAgent));
        }
        json.Append(",\"camera\":").Append(BuildMissionCameraSnapshot(mission, cameraController));
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
        json.Append("]},\"mainAgentAiControlLease\":").Append(BuildMainAgentAiControllerProbeJson()).Append('}');
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
        var readyCallbackField = viewModelType.GetField("_onBeginMission", BindingFlags.Instance | BindingFlags.NonPublic);
        var readyCallbackBound = readyCallbackField?.GetValue(orderBattleViewModel) is Delegate readyCallback && readyCallback.GetInvocationList().Length > 0;
        if (!readyCallbackBound && !ReferenceEquals(_deploymentAutoDeploySubmittedForMission, mission))
            throw new InvalidOperationException("missionFinishDeployment requires an initialized Native Ready callback or this Host's Native Auto Deploy fallback");
        var executeReady = viewModelType.GetMethods(BindingFlags.Instance | BindingFlags.Public)
            .FirstOrDefault(method => method.Name == "ExecuteBeginMission" && method.GetParameters().Length == 0);
        if (executeReady == null)
            throw new InvalidOperationException("missionFinishDeployment could not resolve the original Native OrderOfBattle Ready command");
        var nativeReadyCallbackDispatchedByBridge = false;

        var modeBefore = mission.Mode.ToString();
        var campaignDayBefore = CampaignTime.Now.ToDays;
        var timeModeBefore = campaign.TimeControlMode.ToString();
        string? nativeReadyHandlerExceptionType = null;
        try
        {
            executeReady.Invoke(orderBattleViewModel, null);
        }
        catch (TargetInvocationException exception) when (exception.InnerException != null)
        {
            if (mission.Mode != MissionMode.Battle || !mission.IsDeploymentFinished || campaign.TimeControlMode.ToString() != timeModeBefore)
                throw new InvalidOperationException("missionFinishDeployment original Native Ready command failed", exception.InnerException);
            nativeReadyHandlerExceptionType = exception.InnerException.GetType().Name;
        }
        if (!readyCallbackBound)
        {
            var nativeReadyCallback = orderBattleView.GetType().GetMethod("OnBeginMission", BindingFlags.Instance | BindingFlags.NonPublic);
            if (nativeReadyCallback == null)
                throw new InvalidOperationException("missionFinishDeployment could not resolve the original Native OrderOfBattle OnBeginMission callback target");
            try { nativeReadyCallback.Invoke(orderBattleView, null); }
            catch (TargetInvocationException exception) when (exception.InnerException != null)
            {
                if (mission.Mode != MissionMode.Battle || !mission.IsDeploymentFinished || campaign.TimeControlMode.ToString() != timeModeBefore)
                    throw new InvalidOperationException("missionFinishDeployment original Native OrderOfBattle OnBeginMission callback failed", exception.InnerException);
                nativeReadyHandlerExceptionType = exception.InnerException.GetType().Name;
            }
            nativeReadyCallbackDispatchedByBridge = true;
        }
        _deploymentFinishSubmittedForMission = mission;
        var modeAfter = mission.Mode.ToString();
        var campaignDayAfter = CampaignTime.Now.ToDays;
        var timeModeAfter = campaign.TimeControlMode.ToString();

        var json = new StringBuilder(512);
        json.Append("{\"schemaVersion\":1,\"nativeHandler\":\"OrderOfBattleVM.ExecuteBeginMission\",\"nativeDeploymentHandler\":\"DeploymentHandler.FinishDeployment\",\"nativeUiView\":\"OrderOfBattle.xml\",\"canStartMission\":true")
            .Append(",\"readyCallbackBoundBefore\":").Append(readyCallbackBound ? "true" : "false")
            .Append(",\"nativeReadyCallbackDispatchedByBridge\":").Append(nativeReadyCallbackDispatchedByBridge ? "true" : "false")
            .Append(",\"modeBefore\":"); AppendStringValue(json, modeBefore);
        json.Append(",\"modeAfter\":"); AppendStringValue(json, modeAfter);
        json.Append(",\"nativeReadyHandlerExceptionType\":"); AppendStringValue(json, nativeReadyHandlerExceptionType);
        json.Append(",\"deploymentFinishedAfter\":").Append(mission.IsDeploymentFinished ? "true" : "false");
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

    internal static string AutoDeployCurrentBattleDeployment()
    {
        if (!TryGetActiveCampaignFieldBattle(out var mission, out var reason))
            throw new InvalidOperationException("missionAutoDeploy " + reason);
        var campaign = Campaign.Current ?? throw new InvalidOperationException("missionAutoDeploy requires an active Campaign");
        if (campaign.TimeControlMode != CampaignTimeControlMode.Stop)
            throw new InvalidOperationException("missionAutoDeploy requires the Campaign clock to remain stopped");
        if (mission.Mode != MissionMode.Deployment)
            throw new InvalidOperationException("missionAutoDeploy requires the current Native Mission to remain in Deployment mode");
        if (ChronicleInquiryAdapter.IsInquiryOpen)
            throw new InvalidOperationException("missionAutoDeploy refuses to bypass an active Native Inquiry");
        if (ReferenceEquals(_deploymentAutoDeploySubmittedForMission, mission))
            throw new InvalidOperationException("missionAutoDeploy was already submitted for this Native Mission");

        const string orderBattleHandlerTypeName = "TaleWorlds.MountAndBlade.GauntletUI.Mission.Singleplayer.MissionGauntletOrderOfBattleUIHandler";
        const string deploymentOrderHandlerTypeName = "TaleWorlds.MountAndBlade.GauntletUI.Mission.Singleplayer.MissionGauntletSingleplayerOrderUIHandler";
        var orderBattleHandler = mission.MissionBehaviors.FirstOrDefault(behavior => behavior?.GetType().FullName == orderBattleHandlerTypeName);
        var deploymentOrderHandler = mission.MissionBehaviors.FirstOrDefault(behavior => behavior?.GetType().FullName == deploymentOrderHandlerTypeName);
        if (orderBattleHandler == null || deploymentOrderHandler == null)
            throw new InvalidOperationException("missionAutoDeploy requires the active Native Order of Battle and deployment order views");
        var orderDataSource = orderBattleHandler.GetType().GetField("_dataSource", BindingFlags.Instance | BindingFlags.NonPublic)?.GetValue(orderBattleHandler);
        var canStartProperty = orderDataSource?.GetType().GetProperty("CanStartMission", BindingFlags.Instance | BindingFlags.Public);
        if (canStartProperty?.GetValue(orderDataSource) is not bool canStart || !canStart)
            throw new InvalidOperationException("missionAutoDeploy refuses while the Native Order of Battle does not allow starting");
        var autoDeployHandler = deploymentOrderHandler.GetType().GetMethods(BindingFlags.Instance | BindingFlags.Public)
            .FirstOrDefault(method => method.Name == "OnAutoDeploy" && method.GetParameters().Length == 0);
        if (autoDeployHandler == null)
            throw new InvalidOperationException("missionAutoDeploy could not resolve the original Native Auto Deploy UI handler");

        var campaignDayBefore = CampaignTime.Now.ToDays;
        var timeModeBefore = campaign.TimeControlMode.ToString();
        try { autoDeployHandler.Invoke(deploymentOrderHandler, null); }
        catch (TargetInvocationException exception) when (exception.InnerException != null)
        {
            throw new InvalidOperationException("missionAutoDeploy original Native Auto Deploy UI handler failed", exception.InnerException);
        }
        _deploymentAutoDeploySubmittedForMission = mission;
        var nativeDeploymentSideReadyHandlerInvoked = false;
        if (!GetDeploymentUiStatus(mission).ReadyCallbackBound)
        {
            var deploymentOrderDataSource = deploymentOrderHandler.GetType().GetField("_dataSource", BindingFlags.Instance | BindingFlags.NonPublic)?.GetValue(deploymentOrderHandler);
            var deploymentController = deploymentOrderDataSource?.GetType().GetProperty("DeploymentController", BindingFlags.Instance | BindingFlags.Public)?.GetValue(deploymentOrderDataSource);
            var deployPlayerSide = deploymentController?.GetType().GetMethods(BindingFlags.Instance | BindingFlags.Public)
                .FirstOrDefault(method => method.Name == "ExecuteDeployPlayerSide" && method.GetParameters().Length == 0);
            if (deployPlayerSide == null)
                throw new InvalidOperationException("missionAutoDeploy could not resolve the original Native Player Side Deployment Ready handler");
            try { deployPlayerSide.Invoke(deploymentController, null); }
            catch (TargetInvocationException exception) when (exception.InnerException != null)
            {
                throw new InvalidOperationException("missionAutoDeploy original Native Player Side Deployment Ready handler failed", exception.InnerException);
            }
            nativeDeploymentSideReadyHandlerInvoked = true;
        }
        var campaignDayAfter = CampaignTime.Now.ToDays;
        var timeModeAfter = campaign.TimeControlMode.ToString();
        var deploymentUiAfter = GetDeploymentUiStatus(mission);
        var json = new StringBuilder(512);
        json.Append("{\"schemaVersion\":1,\"nativeHandler\":\"MissionGauntletSingleplayerOrderUIHandler.OnAutoDeploy\",\"nativeAutoDeployHandler\":\"MissionOrderDeploymentControllerVM.ExecuteAutoDeploy\",\"nativeDeploymentHandler\":\"MissionOrderDeploymentControllerVM.ExecuteDeployPlayerSide\",\"nativeUiView\":\"OrderOfBattle.xml\",\"canStartMission\":true")
            .Append(",\"nativeDeploymentSideReadyHandlerInvoked\":").Append(nativeDeploymentSideReadyHandlerInvoked ? "true" : "false")
            .Append(",\"readyCallbackBoundAfter\":").Append(deploymentUiAfter.ReadyCallbackBound ? "true" : "false")
            .Append(",\"deploymentFinishedAfter\":").Append(mission.IsDeploymentFinished ? "true" : "false")
            .Append(",\"campaignDayBefore\":").Append(Number(campaignDayBefore))
            .Append(",\"campaignDayAfter\":").Append(Number(campaignDayAfter))
            .Append(",\"timeControlModeBefore\":"); AppendStringValue(json, timeModeBefore);
        json.Append(",\"timeControlModeAfter\":"); AppendStringValue(json, timeModeAfter);
        json.Append('}');
        return json.ToString();
    }

    private static (bool ViewAvailable, bool ReadyCallbackBound, bool CanStartMission, bool DeploymentFinished) GetDeploymentUiStatus(Mission? mission)
    {
        if (mission == null || mission.Mode != MissionMode.Deployment)
            return (false, false, false, mission?.IsDeploymentFinished ?? false);
        const string handlerTypeName = "TaleWorlds.MountAndBlade.GauntletUI.Mission.Singleplayer.MissionGauntletOrderOfBattleUIHandler";
        var handler = mission.MissionBehaviors.FirstOrDefault(behavior => behavior?.GetType().FullName == handlerTypeName);
        var viewModel = handler?.GetType().GetField("_dataSource", BindingFlags.Instance | BindingFlags.NonPublic)?.GetValue(handler);
        if (viewModel == null) return (false, false, false, mission.IsDeploymentFinished);
        var type = viewModel.GetType();
        var callback = type.GetField("_onBeginMission", BindingFlags.Instance | BindingFlags.NonPublic)?.GetValue(viewModel) as Delegate;
        var canStart = type.GetProperty("CanStartMission", BindingFlags.Instance | BindingFlags.Public)?.GetValue(viewModel) is bool value && value;
        return (true, callback != null && callback.GetInvocationList().Length > 0, canStart, mission.IsDeploymentFinished);
    }

    internal static string BeginMainAgentAiControllerProbe(double requestedDurationSeconds, bool handoffToFriendlySurrogate = false, bool fullNativeHandoff = false)
        => BeginMainAgentAiControlLease(requestedDurationSeconds, handoffToFriendlySurrogate, fullNativeHandoff, "harness-only");

    internal static string BeginMainAgentNativeAiAutopilotLease()
        => BeginMainAgentAiControlLease(900.0, handoffToFriendlySurrogate: false, fullNativeHandoff: true, scope: "agenthost-native-battle-autopilot");

    private static string BeginMainAgentAiControlLease(double requestedDurationSeconds, bool handoffToFriendlySurrogate, bool fullNativeHandoff, string scope)
    {
        if (!TryGetSupportedBattleMission(out var mission, out var reason))
            throw new InvalidOperationException("harnessMainAgentAiControllerProbe " + reason);
        var campaign = Campaign.Current ?? throw new InvalidOperationException("harnessMainAgentAiControllerProbe requires an active Campaign");
        if (campaign.TimeControlMode != CampaignTimeControlMode.Stop)
            throw new InvalidOperationException("harnessMainAgentAiControllerProbe requires the Campaign clock to remain stopped");
        if (_mainAgentAiProbeOwner != null)
            throw new InvalidOperationException("harnessMainAgentAiControllerProbe refuses while another MainAgent AI probe lease is active");
        var maximumProbeDurationSeconds = scope == "harness-only" ? (fullNativeHandoff ? 180.0 : 10.0) : 900.0;
        if (double.IsNaN(requestedDurationSeconds) || double.IsInfinity(requestedDurationSeconds) || requestedDurationSeconds < 1.0 || requestedDurationSeconds > maximumProbeDurationSeconds)
            throw new InvalidOperationException("harnessMainAgentAiControllerProbe durationSeconds exceeds the bounded Native probe duration");

        var mainAgent = mission.MainAgent;
        if (mainAgent == null || !mainAgent.IsActive() || mainAgent.Controller != AgentControllerType.Player)
            throw new InvalidOperationException("harnessMainAgentAiControllerProbe requires the active MainAgent to be Player-controlled");
        Agent? surrogate = null;
        if (handoffToFriendlySurrogate)
        {
            surrogate = mission.Agents
                .Where(agent => agent != null && agent != mainAgent && agent.IsActive() && agent.IsHuman && agent.Character != null &&
                    agent.Team == mission.PlayerTeam && agent.Controller == AgentControllerType.AI && agent.Formation != null)
                .OrderBy(agent => agent.Index)
                .FirstOrDefault();
            if (surrogate == null)
                throw new InvalidOperationException("harnessMainAgentAiSurrogateControllerProbe requires one active AI-controlled human Agent in the current player Team");
        }

        var campaignDayBefore = CampaignTime.Now.ToDays;
        var timeModeBefore = campaign.TimeControlMode.ToString();
        var controllerBefore = mainAgent.Controller.ToString();
        var missionMainAgentBeforeIndex = mission.MainAgent.Index;
        var surrogateControllerBefore = surrogate?.Controller.ToString();
        var positionBefore = mainAgent.Position;
        var healthBefore = mainAgent.Health;
        var nativeController = fullNativeHandoff ? GetNativeMainAgentController(mission, required: true) : null;
        var cameraBefore = BuildMissionCameraSnapshot(mission, nativeController);
        if (fullNativeHandoff && surrogate != null)
            throw new InvalidOperationException("harnessMainAgentNativeAiHandoffProbe does not combine with a surrogate MainAgent");
        if (fullNativeHandoff)
        {
            _mainAgentAiProbeFullNativeHandoff = true;
            _mainAgentAiProbeOriginalAgentFlags = mainAgent.GetAgentFlags();
            _mainAgentAiProbeOriginalAiStateFlags = ReadMemberValue(mainAgent, "AIStateFlags");
            _mainAgentAiProbeOriginalAiPaused = mainAgent.IsPaused;
            _mainAgentAiProbeMissionController = nativeController;
            _mainAgentAiProbeOriginalMissionControllerActivated = nativeController == null ? null : ReadControllerActivated(nativeController);
            _mainAgentAiProbeOriginalCustomLookDir = nativeController == null ? null : ReadControllerLookDirection(nativeController);
            _mainAgentAiProbeOriginalWatchState = mainAgent.CurrentWatchState;
        }
        try
        {
            if (fullNativeHandoff)
                InvokeControllerInteractionClearFocus(_mainAgentAiProbeMissionController);
            mainAgent.Controller = AgentControllerType.AI;
            if (fullNativeHandoff)
                ApplyNativeMainAgentAiHandoff(mainAgent, mission);
            if (surrogate != null) surrogate.Controller = AgentControllerType.Player;
        }
        catch
        {
            if (fullNativeHandoff)
            {
                try { RestoreNativeMainAgentAiHandoff(mainAgent, mission); }
                catch { }
            }
            if (surrogate != null && surrogate.IsActive() && surrogate.Controller == AgentControllerType.Player)
            {
                try { surrogate.Controller = AgentControllerType.AI; }
                catch { }
            }
            if (mainAgent.IsActive() && mainAgent.Controller != AgentControllerType.Player)
            {
                try { mainAgent.Controller = AgentControllerType.Player; }
                catch { }
            }
            throw;
        }

        var expectedMissionMainAgent = surrogate ?? mainAgent;
        if (mission.MainAgent != expectedMissionMainAgent)
        {
            if (surrogate != null && surrogate.IsActive()) { try { surrogate.Controller = AgentControllerType.AI; } catch { } }
            if (mainAgent.IsActive()) { try { mainAgent.Controller = AgentControllerType.Player; } catch { } }
            throw new InvalidOperationException("harnessMainAgentAiControllerProbe Native MainAgent handoff did not select the expected current agent");
        }

        _mainAgentAiProbeMission = mission;
        _mainAgentAiProbeOwner = mainAgent;
        _mainAgentAiProbeSurrogate = surrogate;
        _mainAgentAiProbeOriginalController = AgentControllerType.Player;
        _mainAgentAiProbeSurrogateOriginalController = surrogate == null ? null : AgentControllerType.AI;
        _mainAgentAiProbeExpiresAt = EngineTime.ApplicationTime + (float)requestedDurationSeconds;
        _mainAgentAiProbeStatus = "active";
        _mainAgentAiProbeScope = scope;

        var json = new StringBuilder(512);
        json.Append("{\"schemaVersion\":1,\"scope\":\"").Append(Escape(scope)).Append("\",\"nativeSetter\":\"Agent.Controller\",\"leaseClock\":\"EngineTime.ApplicationTime\"")
            .Append(",\"handoffMode\":\"").Append(fullNativeHandoff ? "rts-camera-native-ai-initialization" : "controller-only").Append('"')
            .Append(",\"durationSeconds\":").Append(Number(requestedDurationSeconds));
        json.Append(",\"controllerBefore\":"); AppendStringValue(json, controllerBefore);
        json.Append(",\"controllerAfter\":"); AppendStringValue(json, mainAgent.Controller.ToString());
        json.Append(",\"isPlayerControlledAfter\":").Append(mainAgent.IsPlayerControlled ? "true" : "false")
            .Append(",\"isAIControlledAfter\":").Append(mainAgent.IsAIControlled ? "true" : "false")
            .Append(",\"missionMainAgentControllerActiveAfter\":");
        try { json.Append(_mainAgentAiProbeMissionController == null ? "null" : ReadControllerActivated(_mainAgentAiProbeMissionController) ? "true" : "false"); }
        catch { json.Append("null"); }
        json.Append(",\"originalMainAgentIndex\":").Append(mainAgent.Index)
            .Append(",\"missionMainAgentIndexBefore\":").Append(missionMainAgentBeforeIndex)
            .Append(",\"missionMainAgentIndexAfter\":").Append(mission.MainAgent.Index);
        json.Append(",\"surrogateAgentIndex\":").Append(surrogate == null ? "null" : surrogate.Index.ToString(CultureInfo.InvariantCulture));
        json.Append(",\"surrogateControllerBefore\":"); AppendStringValue(json, surrogateControllerBefore);
        json.Append(",\"surrogateControllerAfter\":"); AppendStringValue(json, surrogate?.Controller.ToString());
        json.Append(",\"healthBefore\":").Append(Number(healthBefore))
            .Append(",\"healthAfter\":").Append(Number(mainAgent.Health));
        json.Append(",\"cameraBefore\":").Append(cameraBefore)
            .Append(",\"cameraAfter\":").Append(BuildMissionCameraSnapshot(mission, nativeController));
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

    private static void ApplyNativeMainAgentAiHandoff(Agent mainAgent, Mission mission)
    {
        if (mainAgent.Controller != AgentControllerType.AI)
            throw new InvalidOperationException("Native AI handoff setup requires the MainAgent controller to be AI");

        // Reproduce the non-camera MainAgent setup used by the installed
        // MissionSharedLibrary.Utilities.Utility.AIControlMainAgent path.
        var hasHorseEquipment = false;
        var character = mainAgent.Character;
        if (character != null)
        {
            try { hasHorseEquipment = character.Equipment[(EquipmentIndex)10].Item != null; }
            catch { }
        }
        if (hasHorseEquipment || (character?.IsMounted ?? false) || mainAgent.HasMount)
            mainAgent.SetAgentFlags(mainAgent.GetAgentFlags() | (AgentFlag)0x2000);
        else
            mainAgent.SetAgentFlags(mainAgent.GetAgentFlags() & ~(AgentFlag)0x2000);

        var commonAi = mainAgent.CommonAIComponent;
        if (commonAi != null) commonAi.Initialize();
        var humanAi = mainAgent.HumanAIComponent;
        if (humanAi != null) humanAi.Initialize();

        var formation = mainAgent.Formation;
        if (formation != null)
        {
            mainAgent.SetRidingOrder(formation.RidingOrder.OrderEnum);
            formation.OnUnitAddedOrRemoved();
        }
        if (!string.Equals(mainAgent.CurrentWatchState.ToString(), "Alarmed", StringComparison.Ordinal))
            SetMainAgentWatchState(mainAgent, "Alarmed");
        if (mainAgent.IsPaused)
            mainAgent.SetIsAIPaused(false);
        mainAgent.DisableScriptedMovement();
        if (formation != null)
        {
            var currentOrder = formation.GetReadonlyMovementOrderReference();
            currentOrder.OnUnitJoinOrLeave(formation, mainAgent, isJoining: true);
        }

        ResetNativeThirdPersonBattleCamera(mission, _mainAgentAiProbeMissionController);

        // RTS Camera disables the player input controller in free-camera AI
        // mode. This probe keeps the camera unchanged but prevents its input
        // controller from competing with the Native AI.
        var missionController = _mainAgentAiProbeMissionController ?? GetNativeMainAgentController(mission, required: true);
        if (missionController != null)
        {
            InvokeControllerInteractionClearFocus(missionController);
            InvokeControllerMethod(missionController, "Disable");
        }
    }

    private static void ResetNativeThirdPersonBattleCamera(Mission mission, object? missionController)
    {
        if (mission.CameraIsFirstPerson || missionController == null ||
            ReadMemberValue(missionController, "MissionScreen") is not object missionScreen)
            return;

        if (ReadMemberValue(missionScreen, "CameraElevation") is not float currentElevation ||
            (!float.IsNaN(currentElevation) && !float.IsInfinity(currentElevation) &&
             currentElevation >= NativeThirdPersonBattleCameraNearVerticalThreshold))
            return;

        // The Native MissionScreen starts from a shallow third-person angle
        // (-0.2 radians). Deployment/idle camera input can leave the value at
        // its near-vertical clamp before the AI lease begins; only then restore
        // that Native baseline, preserving other valid player camera angles.
        WriteMemberValue(missionScreen, "CameraElevation", NativeThirdPersonBattleCameraElevation);
        WriteMemberValue(missionScreen, "_cameraElevationDelta", 0f);
    }

    private static void RestoreNativeMainAgentAiHandoff(Agent owner, Mission mission)
    {
        if (!owner.IsActive()) return;
        if (_mainAgentAiProbeOriginalAgentFlags.HasValue)
            owner.SetAgentFlags(_mainAgentAiProbeOriginalAgentFlags.Value);
        if (_mainAgentAiProbeOriginalAiStateFlags != null)
            WriteMemberValue(owner, "AIStateFlags", _mainAgentAiProbeOriginalAiStateFlags);
        if (_mainAgentAiProbeOriginalWatchState != null)
        {
            var restoreWatchState = typeof(Agent).GetMethod("SetWatchState", BindingFlags.Instance | BindingFlags.Public);
            restoreWatchState?.Invoke(owner, new[] { _mainAgentAiProbeOriginalWatchState });
        }
        if (_mainAgentAiProbeOriginalAiPaused.HasValue && owner.IsPaused != _mainAgentAiProbeOriginalAiPaused.Value)
            owner.SetIsAIPaused(_mainAgentAiProbeOriginalAiPaused.Value);
        if (owner.Formation != null)
        {
            owner.Formation.OnUnitAddedOrRemoved();
            var currentOrder = owner.Formation.GetReadonlyMovementOrderReference();
            currentOrder.OnUnitJoinOrLeave(owner.Formation, owner, isJoining: true);
        }
        var nativeController = _mainAgentAiProbeMissionController ?? GetNativeMainAgentController(mission);
        if (nativeController != null)
        {
            if (_mainAgentAiProbeOriginalCustomLookDir != null)
                WriteControllerLookDirection(nativeController, _mainAgentAiProbeOriginalCustomLookDir);
            if (_mainAgentAiProbeOriginalMissionControllerActivated == true)
                InvokeControllerMethod(nativeController, "Enable");
            else
                InvokeControllerMethod(nativeController, "Disable");
        }
    }

    private static void SetMainAgentWatchState(Agent agent, string stateName)
    {
        var method = typeof(Agent).GetMethod("SetWatchState", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
        var parameterType = method?.GetParameters().FirstOrDefault()?.ParameterType;
        if (method == null || parameterType == null || !parameterType.IsEnum)
            throw new MissingMethodException(typeof(Agent).FullName, "SetWatchState(WatchState)");
        method.Invoke(agent, new[] { Enum.Parse(parameterType, stateName) });
    }

    private static object? GetNativeMainAgentController(Mission mission, bool required = false)
    {
        var controllerType = _nativeMainAgentControllerType ??= AppDomain.CurrentDomain.GetAssemblies()
            .Select(assembly => assembly.GetType("TaleWorlds.MountAndBlade.View.MissionViews.MissionMainAgentController", throwOnError: false))
            .FirstOrDefault(type => type != null);
        if (controllerType == null)
        {
            if (required) throw new TypeLoadException("Native MissionMainAgentController type is not loaded");
            return null;
        }
        var getter = typeof(Mission).GetMethods(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)
            .FirstOrDefault(method => method.Name == "GetMissionBehavior" && method.IsGenericMethodDefinition && method.GetParameters().Length == 0);
        if (getter == null) throw new MissingMethodException(typeof(Mission).FullName, "GetMissionBehavior<T>()");
        return getter.MakeGenericMethod(controllerType).Invoke(mission, null);
    }

    private static bool ReadControllerActivated(object controller)
    {
        var value = ReadMemberValue(controller, "_activated");
        if (value is bool active) return active;
        throw new MissingMemberException(controller.GetType().FullName, "_activated");
    }

    private static object? ReadControllerLookDirection(object controller)
    {
        var value = ReadMemberValue(controller, "CustomLookDir");
        if (value == null) throw new MissingMemberException(controller.GetType().FullName, "CustomLookDir");
        return value;
    }

    private static object? ReadMemberValue(object target, string name)
    {
        var type = target.GetType();
        var property = type.GetProperty(name, BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
        if (property != null) return property.GetValue(target);
        return type.GetField(name, BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)?.GetValue(target);
    }

    private static string BuildMissionCameraSnapshot(Mission? mission, object? controller)
    {
        if (mission == null || controller == null || ReadMemberValue(controller, "MissionScreen") is not object missionScreen) return "null";
        if (ReadMemberValue(missionScreen, "CameraBearing") is not float bearing ||
            ReadMemberValue(missionScreen, "CameraElevation") is not float elevation ||
            float.IsNaN(bearing) || float.IsInfinity(bearing) || float.IsNaN(elevation) || float.IsInfinity(elevation)) return "null";
        return "{\"bearing\":" + Number(bearing) + ",\"elevation\":" + Number(elevation) +
            ",\"firstPerson\":" + (mission.CameraIsFirstPerson ? "true" : "false") + "}";
    }

    private static void WriteMemberValue(object target, string name, object value)
    {
        var type = target.GetType();
        var property = type.GetProperty(name, BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
        if (property?.CanWrite == true) { property.SetValue(target, value); return; }
        var field = type.GetField(name, BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
        if (field != null) { field.SetValue(target, value); return; }
        throw new MissingMemberException(type.FullName, name);
    }

    private static void WriteControllerLookDirection(object controller, object value) => WriteMemberValue(controller, "CustomLookDir", value);

    private static void InvokeControllerInteractionClearFocus(object? controller)
    {
        if (controller == null) return;
        var interaction = ReadMemberValue(controller, "InteractionComponent");
        interaction?.GetType().GetMethod("ClearFocus", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)?.Invoke(interaction, null);
    }

    private static void InvokeControllerMethod(object controller, string name)
    {
        var method = controller.GetType().GetMethod(name, BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic, binder: null, Type.EmptyTypes, modifiers: null);
        if (method == null) throw new MissingMethodException(controller.GetType().FullName, name);
        method.Invoke(controller, null);
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
        var expectedMainAgent = _mainAgentAiProbeSurrogate ?? _mainAgentAiProbeOwner;
        if (mission == null || mission != _mainAgentAiProbeMission || mission.MissionEnded || !activeState || mission.MainAgent != expectedMainAgent)
            ClearMainAgentAiControllerProbeLease("mission-ended-or-changed");
    }

    internal static string RestoreMainAgentAiControllerProbe()
    {
        if (_mainAgentAiProbeOwner == null || !_mainAgentAiProbeOriginalController.HasValue)
        {
            var lastStatus = _mainAgentAiProbeStatus ?? "never-started";
            var restored = lastStatus != "never-started" && _mainAgentAiProbeLastOwnerController == AgentControllerType.Player.ToString() &&
                (_mainAgentAiProbeLastSurrogateAgentIndex == null || _mainAgentAiProbeLastSurrogateController == AgentControllerType.AI.ToString());
            return "{\"schemaVersion\":1,\"status\":\"" + Escape(lastStatus) + "\",\"restored\":" + (restored ? "true" : "false") +
                ",\"ownerControllerAfter\":" + (_mainAgentAiProbeLastOwnerController == null ? "null" : "\"" + Escape(_mainAgentAiProbeLastOwnerController) + "\"") +
                ",\"surrogateAgentIndex\":" + (_mainAgentAiProbeLastSurrogateAgentIndex?.ToString(CultureInfo.InvariantCulture) ?? "null") +
                ",\"surrogateControllerAfter\":" + (_mainAgentAiProbeLastSurrogateController == null ? "null" : "\"" + Escape(_mainAgentAiProbeLastSurrogateController) + "\"") +
                ",\"missionMainAgentIndexAfter\":" + (_mainAgentAiProbeLastMissionMainAgentIndex?.ToString(CultureInfo.InvariantCulture) ?? "null") + "}";
        }
        var owner = _mainAgentAiProbeOwner;
        var surrogate = _mainAgentAiProbeSurrogate;
        ClearMainAgentAiControllerProbeLease("explicitly-restored");
        var controller = owner.IsActive() ? owner.Controller.ToString() : null;
        var surrogateController = surrogate?.IsActive() == true ? surrogate.Controller.ToString() : null;
        var leaseRestored = owner.IsActive() && controller == AgentControllerType.Player.ToString() &&
            (surrogate == null || surrogateController == AgentControllerType.AI.ToString());
        return "{\"schemaVersion\":1,\"status\":\"" + Escape(_mainAgentAiProbeStatus ?? "restored") + "\",\"restored\":" + (leaseRestored ? "true" : "false") +
            ",\"ownerControllerAfter\":" + (controller == null ? "null" : "\"" + Escape(controller) + "\"") +
            ",\"surrogateAgentIndex\":" + (surrogate == null ? "null" : surrogate.Index.ToString(CultureInfo.InvariantCulture)) +
            ",\"surrogateControllerAfter\":" + (surrogateController == null ? "null" : "\"" + Escape(surrogateController) + "\"") +
            ",\"missionMainAgentIndexAfter\":" + (Mission.Current?.MainAgent?.Index.ToString(CultureInfo.InvariantCulture) ?? "null") + "}";
    }

    internal static string RefreshMainAgentFormationAiProbe()
    {
        if (_mainAgentAiProbeMission != Mission.Current || _mainAgentAiProbeOwner == null || !_mainAgentAiProbeOwner.IsActive() ||
            _mainAgentAiProbeSurrogate == null || !_mainAgentAiProbeSurrogate.IsActive() || Mission.Current?.MainAgent != _mainAgentAiProbeSurrogate)
            throw new InvalidOperationException("harnessRefreshMainAgentFormationAiProbe requires the active surrogate-controller probe lease");
        var mission = Mission.Current!;
        if (mission.MissionEnded || mission.Mode != MissionMode.Battle)
            throw new InvalidOperationException("harnessRefreshMainAgentFormationAiProbe requires the same active Battle Mission");
        var campaign = Campaign.Current ?? throw new InvalidOperationException("harnessRefreshMainAgentFormationAiProbe requires an active Campaign");
        if (campaign.TimeControlMode != CampaignTimeControlMode.Stop)
            throw new InvalidOperationException("harnessRefreshMainAgentFormationAiProbe requires the Campaign clock to remain stopped");
        var formation = _mainAgentAiProbeOwner.Formation;
        if (formation == null || formation.CountOfUnits <= 0 || !formation.IsAIControlled || formation.AI?.ActiveBehavior == null)
            throw new InvalidOperationException("harnessRefreshMainAgentFormationAiProbe requires the MainAgent's current populated AI Formation with an active behavior");

        var dayBefore = CampaignTime.Now.ToDays;
        var timeModeBefore = campaign.TimeControlMode.ToString();
        var aiControlledBefore = formation.IsAIControlled;
        var behaviorType = formation.AI.ActiveBehavior.GetType().Name;
        var orderBefore = formation.AI.ActiveBehavior.CurrentOrder;
        var targetBefore = orderBefore.GetPosition(formation);
        try
        {
            formation.SetControlledByAI(false);
            formation.SetControlledByAI(true);
        }
        catch
        {
            if (aiControlledBefore && !formation.IsAIControlled)
            {
                try { formation.SetControlledByAI(true); }
                catch { }
            }
            throw;
        }

        var activeBehaviorAfter = formation.AI?.ActiveBehavior;
        var dayAfter = CampaignTime.Now.ToDays;
        var timeModeAfter = campaign.TimeControlMode.ToString();
        var json = new StringBuilder(512);
        json.Append("{\"schemaVersion\":1,\"scope\":\"harness-only\",\"nativeOperation\":\"Formation.SetControlledByAI(false,true)\"")
            .Append(",\"mainHeroController\":"); AppendStringValue(json, _mainAgentAiProbeOwner.Controller.ToString());
        json.Append(",\"missionMainAgentIndex\":").Append(mission.MainAgent?.Index.ToString(CultureInfo.InvariantCulture) ?? "null")
            .Append(",\"formationIndex\":").Append((int)formation.FormationIndex)
            .Append(",\"formationCount\":").Append(formation.CountOfUnits)
            .Append(",\"isAIControlledBefore\":").Append(aiControlledBefore ? "true" : "false")
            .Append(",\"isAIControlledAfter\":").Append(formation.IsAIControlled ? "true" : "false");
        json.Append(",\"behaviorTypeBefore\":"); AppendStringValue(json, behaviorType);
        json.Append(",\"behaviorTypeAfter\":"); AppendStringValue(json, activeBehaviorAfter?.GetType().Name);
        json.Append(",\"orderTypeBefore\":"); AppendStringValue(json, orderBefore.OrderEnum.ToString());
        json.Append(",\"orderTypeAfter\":"); AppendStringValue(json, activeBehaviorAfter?.CurrentOrder.OrderEnum.ToString());
        json.Append(",\"orderTargetBefore\":{\"x\":").Append(Number(targetBefore.X)).Append(",\"y\":").Append(Number(targetBefore.Y)).Append('}');
        if (activeBehaviorAfter != null)
        {
            var targetAfter = activeBehaviorAfter.CurrentOrder.GetPosition(formation);
            json.Append(",\"orderTargetAfter\":{\"x\":").Append(Number(targetAfter.X)).Append(",\"y\":").Append(Number(targetAfter.Y)).Append('}');
        }
        else json.Append(",\"orderTargetAfter\":null");
        json.Append(",\"campaignDayBefore\":").Append(Number(dayBefore)).Append(",\"campaignDayAfter\":").Append(Number(dayAfter));
        json.Append(",\"timeControlModeBefore\":"); AppendStringValue(json, timeModeBefore);
        json.Append(",\"timeControlModeAfter\":"); AppendStringValue(json, timeModeAfter);
        json.Append('}');
        return json.ToString();
    }

    internal static string NotifyMainAgentAiMovementOrderProbe()
    {
        if (_mainAgentAiProbeMission != Mission.Current || _mainAgentAiProbeOwner == null || !_mainAgentAiProbeOwner.IsActive() ||
            _mainAgentAiProbeSurrogate == null || !_mainAgentAiProbeSurrogate.IsActive() || Mission.Current?.MainAgent != _mainAgentAiProbeSurrogate)
            throw new InvalidOperationException("harnessNotifyMainAgentAiMovementOrder requires the active surrogate-controller probe lease");
        var mission = Mission.Current!;
        var campaign = Campaign.Current ?? throw new InvalidOperationException("harnessNotifyMainAgentAiMovementOrder requires an active Campaign");
        if (mission.MissionEnded || mission.Mode != MissionMode.Battle || campaign.TimeControlMode != CampaignTimeControlMode.Stop)
            throw new InvalidOperationException("harnessNotifyMainAgentAiMovementOrder requires the same active Battle Mission and stopped Campaign clock");
        var hero = _mainAgentAiProbeOwner;
        var formation = hero.Formation;
        if (hero.Controller != AgentControllerType.AI || formation == null || !formation.IsAIControlled || formation.CountOfUnits <= 0 || formation.AI?.ActiveBehavior == null)
            throw new InvalidOperationException("harnessNotifyMainAgentAiMovementOrder requires the AI-controlled MainHero in a populated AI Formation with an active behavior");
        var currentOrder = formation.GetReadonlyMovementOrderReference();
        if (currentOrder.OrderEnum != MovementOrder.MovementOrderEnum.Move)
            throw new InvalidOperationException("harnessNotifyMainAgentAiMovementOrder only rebinds the current Native Move order");

        var campaignDayBefore = CampaignTime.Now.ToDays;
        var timeModeBefore = campaign.TimeControlMode.ToString();
        var positionBefore = hero.Position;
        var targetBefore = currentOrder.GetPosition(formation);
        currentOrder.OnUnitJoinOrLeave(formation, hero, isJoining: true);
        var currentOrderAfter = formation.GetReadonlyMovementOrderReference();
        var targetAfter = currentOrderAfter.GetPosition(formation);
        var json = new StringBuilder(448);
        json.Append("{\"schemaVersion\":1,\"scope\":\"harness-only\",\"nativeOperation\":\"MovementOrder.OnUnitJoinOrLeave\",\"isJoining\":true")
            .Append(",\"ownerAgentIndex\":").Append(hero.Index)
            .Append(",\"surrogateAgentIndex\":").Append(mission.MainAgent.Index)
            .Append(",\"controller\":"); AppendStringValue(json, hero.Controller.ToString());
        json.Append(",\"orderTypeBefore\":"); AppendStringValue(json, currentOrder.OrderEnum.ToString());
        json.Append(",\"orderTypeAfter\":"); AppendStringValue(json, currentOrderAfter.OrderEnum.ToString());
        json.Append(",\"positionBefore\":{\"x\":").Append(Number(positionBefore.X)).Append(",\"y\":").Append(Number(positionBefore.Y)).Append(",\"z\":").Append(Number(positionBefore.Z)).Append('}');
        json.Append(",\"targetBefore\":{\"x\":").Append(Number(targetBefore.X)).Append(",\"y\":").Append(Number(targetBefore.Y)).Append('}')
            .Append(",\"targetAfter\":{\"x\":").Append(Number(targetAfter.X)).Append(",\"y\":").Append(Number(targetAfter.Y)).Append('}');
        json.Append(",\"campaignDayBefore\":").Append(Number(campaignDayBefore)).Append(",\"campaignDayAfter\":").Append(Number(CampaignTime.Now.ToDays));
        json.Append(",\"timeControlModeBefore\":"); AppendStringValue(json, timeModeBefore);
        json.Append(",\"timeControlModeAfter\":"); AppendStringValue(json, campaign.TimeControlMode.ToString());
        json.Append('}');
        return json.ToString();
    }

    internal static string ApplyMainAgentRtsCameraAiBehaviorProbe()
    {
        if (_mainAgentAiProbeMission != Mission.Current || _mainAgentAiProbeOwner == null || !_mainAgentAiProbeOwner.IsActive() ||
            _mainAgentAiProbeSurrogate != null || Mission.Current?.MainAgent != _mainAgentAiProbeOwner || _mainAgentAiProbeOwner.Controller != AgentControllerType.AI)
            throw new InvalidOperationException("harnessMainAgentAiRtsCameraProbe requires the active AI-controlled MainAgent probe lease without a surrogate");
        var mission = Mission.Current!;
        var campaign = Campaign.Current ?? throw new InvalidOperationException("harnessMainAgentAiRtsCameraProbe requires an active Campaign");
        if (mission.MissionEnded || mission.Mode != MissionMode.Battle || campaign.TimeControlMode != CampaignTimeControlMode.Stop)
            throw new InvalidOperationException("harnessMainAgentAiRtsCameraProbe requires the same active Battle Mission and stopped Campaign clock");
        var hero = _mainAgentAiProbeOwner;
        var formation = hero.Formation;
        if (formation == null || !formation.IsAIControlled || formation.CountOfUnits <= 0)
            throw new InvalidOperationException("harnessMainAgentAiRtsCameraProbe requires MainHero's current populated AI Formation");
        var setPlayerTroopFlag = typeof(Formation).GetProperty("IsPlayerTroopInFormation", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)?.GetSetMethod(nonPublic: true);
        if (setPlayerTroopFlag == null)
            throw new InvalidOperationException("harnessMainAgentAiRtsCameraProbe cannot resolve the installed Native IsPlayerTroopInFormation setter");

        _mainAgentAiProbeOriginalWatchState ??= hero.CurrentWatchState;
        _mainAgentAiProbeOriginalPlayerTroopInFormation ??= formation.IsPlayerTroopInFormation;
        var campaignDayBefore = CampaignTime.Now.ToDays;
        var timeModeBefore = campaign.TimeControlMode.ToString();
        var positionBefore = hero.Position;
        var currentOrder = formation.GetReadonlyMovementOrderReference();
        var targetBefore = currentOrder.GetPosition(formation);
        try
        {
            var setWatchState = typeof(Agent).GetMethod("SetWatchState", BindingFlags.Instance | BindingFlags.Public);
            var watchStateParameter = setWatchState?.GetParameters().FirstOrDefault()?.ParameterType;
            if (setWatchState == null || watchStateParameter == null || !watchStateParameter.IsEnum)
                throw new MissingMethodException("Native Agent.SetWatchState(WatchState) not found");
            var alarmedWatchState = Enum.Parse(watchStateParameter, "Alarmed");
            setWatchState.Invoke(hero, new[] { alarmedWatchState });
            setPlayerTroopFlag.Invoke(formation, new object[] { false });
            currentOrder.OnUnitJoinOrLeave(formation, hero, isJoining: true);
        }
        catch
        {
            if (_mainAgentAiProbeOriginalPlayerTroopInFormation.HasValue)
            {
                try { setPlayerTroopFlag.Invoke(formation, new object[] { _mainAgentAiProbeOriginalPlayerTroopInFormation.Value }); }
                catch { }
            }
            if (_mainAgentAiProbeOriginalWatchState != null)
            {
                try
                {
                    var restoreWatchState = typeof(Agent).GetMethod("SetWatchState", BindingFlags.Instance | BindingFlags.Public);
                    restoreWatchState?.Invoke(hero, new[] { _mainAgentAiProbeOriginalWatchState });
                }
                catch { }
            }
            throw;
        }

        var dayAfter = CampaignTime.Now.ToDays;
        var timeModeAfter = campaign.TimeControlMode.ToString();
        var json = new StringBuilder(512);
        json.Append("{\"schemaVersion\":1,\"scope\":\"harness-only\",\"referencePattern\":\"RTSCamera AIControlMainAgent + MovementOrder membership notification\"")
            .Append(",\"nativeWatchStateBefore\":"); AppendStringValue(json, _mainAgentAiProbeOriginalWatchState.ToString());
        json.Append(",\"nativeWatchStateAfter\":"); AppendStringValue(json, hero.CurrentWatchState.ToString());
        json.Append(",\"isPlayerTroopInFormationBefore\":").Append(_mainAgentAiProbeOriginalPlayerTroopInFormation.Value ? "true" : "false")
            .Append(",\"isPlayerTroopInFormationAfter\":").Append(formation.IsPlayerTroopInFormation ? "true" : "false")
            .Append(",\"hasPlayerControlledTroopAfter\":").Append(formation.HasPlayerControlledTroop ? "true" : "false")
            .Append(",\"ownerController\":"); AppendStringValue(json, hero.Controller.ToString());
        json.Append(",\"orderType\":"); AppendStringValue(json, currentOrder.OrderEnum.ToString());
        json.Append(",\"positionBefore\":{\"x\":").Append(Number(positionBefore.X)).Append(",\"y\":").Append(Number(positionBefore.Y)).Append(",\"z\":").Append(Number(positionBefore.Z)).Append('}')
            .Append(",\"targetBefore\":{\"x\":").Append(Number(targetBefore.X)).Append(",\"y\":").Append(Number(targetBefore.Y)).Append('}')
            .Append(",\"campaignDayBefore\":").Append(Number(campaignDayBefore)).Append(",\"campaignDayAfter\":").Append(Number(dayAfter));
        json.Append(",\"timeControlModeBefore\":"); AppendStringValue(json, timeModeBefore);
        json.Append(",\"timeControlModeAfter\":"); AppendStringValue(json, timeModeAfter);
        json.Append('}');
        return json.ToString();
    }

    private static string BuildMainAgentAiControllerProbeJson()
    {
        var owner = _mainAgentAiProbeOwner;
        if (owner == null || _mainAgentAiProbeMission == null)
            return "{\"active\":false,\"status\":\"" + Escape(_mainAgentAiProbeStatus ?? "never-started") + "\"}";
        var remaining = Math.Max(0.0, _mainAgentAiProbeExpiresAt - EngineTime.ApplicationTime);
        var surrogate = _mainAgentAiProbeSurrogate;
        var formation = owner.Formation;
        var activeBehavior = formation?.AI?.ActiveBehavior;
        var activeOrderTarget = formation != null && activeBehavior != null ? activeBehavior.CurrentOrder.GetPosition(formation) : (TaleWorlds.Library.Vec2?)null;
        var json = new StringBuilder(640);
        json.Append("{\"active\":true,\"scope\":\"" + Escape(_mainAgentAiProbeScope ?? "harness-only") + "\",\"status\":\"" + Escape(_mainAgentAiProbeStatus ?? "active") + "\",\"secondsRemaining\":")
            .Append(Number(remaining))
            .Append(",\"handoffMode\":\"").Append(_mainAgentAiProbeFullNativeHandoff ? "rts-camera-native-ai-initialization" : "controller-only").Append('"')
            .Append(",\"ownerAgentIndex\":").Append(owner.Index)
            .Append(",\"ownerController\":"); AppendStringValue(json, owner.Controller.ToString());
        json.Append(",\"missionMainAgentIndex\":").Append(Mission.Current?.MainAgent?.Index.ToString(CultureInfo.InvariantCulture) ?? "null")
            .Append(",\"ownerHealth\":").Append(Number(owner.Health))
            .Append(",\"ownerPosition\":{\"x\":").Append(Number(owner.Position.X)).Append(",\"y\":").Append(Number(owner.Position.Y)).Append(",\"z\":").Append(Number(owner.Position.Z)).Append('}')
            .Append(",\"ownerFormationIndex\":").Append(formation == null ? "null" : ((int)formation.FormationIndex).ToString(CultureInfo.InvariantCulture))
            .Append(",\"ownerHasActiveAiBehavior\":").Append(activeBehavior == null ? "false" : "true")
            .Append(",\"ownerActiveAiBehaviorType\":"); AppendStringValue(json, activeBehavior?.GetType().Name);
        json.Append(",\"ownerActiveAiOrderType\":"); AppendStringValue(json, activeBehavior?.CurrentOrder.OrderEnum.ToString());
        json.Append(",\"ownerWatchState\":"); AppendStringValue(json, owner.CurrentWatchState.ToString());
        json.Append(",\"ownerAiStateFlags\":"); AppendStringValue(json, ReadMemberValue(owner, "AIStateFlags")?.ToString());
        json.Append(",\"missionMainAgentControllerActive\":");
        try { json.Append(_mainAgentAiProbeMissionController == null ? "null" : ReadControllerActivated(_mainAgentAiProbeMissionController) ? "true" : "false"); }
        catch { json.Append("null"); }
        json.Append(",\"ownerActiveAiOrderTarget\":");
        if (activeOrderTarget.HasValue)
        {
            var target = activeOrderTarget.Value;
            json.Append("{\"x\":").Append(Number(target.X)).Append(",\"y\":").Append(Number(target.Y)).Append('}');
            var dx = owner.Position.X - target.X;
            var dy = owner.Position.Y - target.Y;
            json.Append(",\"ownerDistanceToAiOrderTarget\":").Append(Number(Math.Sqrt(dx * dx + dy * dy)));
        }
        else json.Append("null,\"ownerDistanceToAiOrderTarget\":null");
        json.Append(",\"surrogateAgentIndex\":").Append(surrogate == null ? "null" : surrogate.Index.ToString(CultureInfo.InvariantCulture))
            .Append(",\"surrogateController\":"); AppendStringValue(json, surrogate?.Controller.ToString());
        json.Append('}');
        return json.ToString();
    }

    internal static string ClearMainAgentAiControllerProbeLease(string status)
    {
        var owner = _mainAgentAiProbeOwner;
        var surrogate = _mainAgentAiProbeSurrogate;
        var original = _mainAgentAiProbeOriginalController;
        var surrogateOriginal = _mainAgentAiProbeSurrogateOriginalController;
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
        if (surrogate != null && surrogateOriginal.HasValue && surrogate.IsActive())
        {
            if (surrogate.Controller == AgentControllerType.Player || surrogate.Controller == surrogateOriginal.Value)
            {
                try { surrogate.Controller = surrogateOriginal.Value; }
                catch (Exception exception)
                {
                    ChronicleDiagnostics.Write($"agent-main-controller-probe-surrogate-restore-failed|type={exception.GetType().Name}|message={exception.Message}");
                    status = "restore-failed";
                }
            }
            else status = "surrogate-controller-changed-externally";
        }
        if (owner != null && owner.IsActive() && _mainAgentAiProbeFullNativeHandoff)
        {
            try { RestoreNativeMainAgentAiHandoff(owner, mission ?? Mission.Current!); }
            catch (Exception exception)
            {
                ChronicleDiagnostics.Write($"agent-main-native-ai-handoff-restore-failed|type={exception.GetType().Name}|message={exception.Message}");
                status = "restore-failed";
            }
        }
        else if (owner != null && owner.IsActive() && _mainAgentAiProbeOriginalWatchState != null)
        {
            try
            {
                var restoreWatchState = typeof(Agent).GetMethod("SetWatchState", BindingFlags.Instance | BindingFlags.Public);
                restoreWatchState?.Invoke(owner, new[] { _mainAgentAiProbeOriginalWatchState });
            }
            catch (Exception exception)
            {
                ChronicleDiagnostics.Write($"agent-main-controller-probe-watch-state-restore-failed|type={exception.GetType().Name}|message={exception.Message}");
                status = "restore-failed";
            }
        }
        if (owner?.Formation != null && _mainAgentAiProbeOriginalPlayerTroopInFormation.HasValue)
        {
            var playerTroopFlagSetter = typeof(Formation).GetProperty("IsPlayerTroopInFormation", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)?.GetSetMethod(nonPublic: true);
            try
            {
                if (playerTroopFlagSetter == null) throw new MissingMethodException("Native Formation.IsPlayerTroopInFormation setter unavailable during probe cleanup");
                playerTroopFlagSetter.Invoke(owner.Formation, new object[] { _mainAgentAiProbeOriginalPlayerTroopInFormation.Value });
            }
            catch (Exception exception)
            {
                ChronicleDiagnostics.Write($"agent-main-controller-probe-formation-flag-restore-failed|type={exception.GetType().Name}|message={exception.Message}");
                status = "restore-failed";
            }
        }
        else if (mission != null && mission.MissionEnded) status = "mission-ended";

        _mainAgentAiProbeLastOwnerController = owner?.IsActive() == true ? owner.Controller.ToString() : null;
        _mainAgentAiProbeLastSurrogateAgentIndex = surrogate?.Index;
        _mainAgentAiProbeLastSurrogateController = surrogate?.IsActive() == true ? surrogate.Controller.ToString() : null;
        _mainAgentAiProbeLastMissionMainAgentIndex = mission?.MainAgent?.Index;

        _mainAgentAiProbeMission = null;
        _mainAgentAiProbeOwner = null;
        _mainAgentAiProbeSurrogate = null;
        _mainAgentAiProbeOriginalController = null;
        _mainAgentAiProbeSurrogateOriginalController = null;
        _mainAgentAiProbeOriginalWatchState = null;
        _mainAgentAiProbeOriginalPlayerTroopInFormation = null;
        _mainAgentAiProbeFullNativeHandoff = false;
        _mainAgentAiProbeOriginalAgentFlags = null;
        _mainAgentAiProbeOriginalAiStateFlags = null;
        _mainAgentAiProbeOriginalAiPaused = null;
        _mainAgentAiProbeMissionController = null;
        _mainAgentAiProbeOriginalMissionControllerActivated = null;
        _mainAgentAiProbeOriginalCustomLookDir = null;
        _mainAgentAiProbeExpiresAt = 0f;
        _mainAgentAiProbeStatus = status;
        _mainAgentAiProbeScope = null;
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

    private static string Number(double value) => double.IsNaN(value) || double.IsInfinity(value)
        ? "null"
        : value.ToString("R", CultureInfo.InvariantCulture);

    private static string Escape(string value) => value.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\r", "\\r").Replace("\n", "\\n");
}
