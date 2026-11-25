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
    private void HandleHarnessMissionDiagnostics(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var missionDiagnosticsMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var missionDiagnosticsRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(missionDiagnosticsMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(missionDiagnosticsRoot) || !Directory.Exists(missionDiagnosticsRoot))
            throw new InvalidOperationException("harnessMissionDiagnostics is restricted to a visual Harness run with a Harness temp directory");
        var diagnosticMission = Mission.Current;
        if (diagnosticMission == null || diagnosticMission.MissionEnded || !AgentMissionInputPatch.IsSupportedLocationMission(diagnosticMission))
            throw new InvalidOperationException("harnessMissionDiagnostics requires an active Town or Tavern Location Mission");
        WriteResponse(commandId, action, "completed", behavior, null, BuildHarnessMissionDiagnosticsJson(diagnosticMission));
    }

    private void HandleHarnessSeedNpcBattleForPlayerJoin(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var joinEncounterFixtureMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var joinEncounterFixtureRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(joinEncounterFixtureMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(joinEncounterFixtureRoot) || !Directory.Exists(joinEncounterFixtureRoot))
            throw new InvalidOperationException("harnessSeedNpcBattleForPlayerJoin is restricted to a visual Harness run with a Harness temp directory");
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleHarnessJoinEncounterFixture.CreateNpcBattleForPlayerJoin(ReadString(command, "relationProfile") ?? "HelpDefenders"));
    }

    private void HandleHarnessCloseMissionOrderMenu(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var orderMenuProbeMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var orderMenuProbeRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(orderMenuProbeMode, "battle-fixture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(orderMenuProbeRoot) || !Directory.Exists(orderMenuProbeRoot))
            throw new InvalidOperationException("harnessCloseMissionOrderMenu is restricted to a disposable battle-fixture Harness run");
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentBattleMissionAdapter.CloseNativeMissionOrderViewFromHarness());
    }

    private void HandleHarnessPrepareCameraMotionBaseline(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var cameraBaselineMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var cameraBaselineRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(cameraBaselineMode, "battle-fixture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(cameraBaselineRoot) || !Directory.Exists(cameraBaselineRoot))
            throw new InvalidOperationException("harnessPrepareCameraMotionBaseline is restricted to a disposable battle-fixture Harness run");
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentBattleMissionAdapter.PrepareNativeThirdPersonCameraMotionBaseline());
    }

    private void HandleHarnessMainAgentAiControllerProbe(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentBattleMissionAdapter.BeginMainAgentAiControllerProbe(ReadDouble(command, "durationSeconds")));
    }

    private void HandleHarnessMainAgentNativeAiHandoffProbe(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentBattleMissionAdapter.BeginMainAgentAiControllerProbe(ReadDouble(command, "durationSeconds"), fullNativeHandoff: true));
    }

    private void HandleHarnessMainAgentAiSurrogateControllerProbe(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentBattleMissionAdapter.BeginMainAgentAiControllerProbe(ReadDouble(command, "durationSeconds"), handoffToFriendlySurrogate: true));
    }

    private void HandleHarnessRefreshMainAgentFormationAiProbe(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentBattleMissionAdapter.RefreshMainAgentFormationAiProbe());
    }

    private void HandleHarnessNotifyMainAgentAiMovementOrderProbe(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentBattleMissionAdapter.NotifyMainAgentAiMovementOrderProbe());
    }

    private void HandleHarnessMainAgentAiRtsCameraProbe(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentBattleMissionAdapter.ApplyMainAgentRtsCameraAiBehaviorProbe());
    }

    private void HandleHarnessRestoreMainAgentAiControllerProbe(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentBattleMissionAdapter.RestoreMainAgentAiControllerProbe());
    }

    private void HandleHarnessBattleMovementInputProbe(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var movementProbeMission = Mission.Current;
        var movementProbeMainAgent = movementProbeMission?.MainAgent;
        if (!AgentMissionInputPatch.IsSupportedCampaignFieldBattleInput(movementProbeMission, movementProbeMainAgent))
            throw new InvalidOperationException("harnessBattleMovementInputProbe requires the active stopped Campaign field Battle Mission and Player-controlled MainAgent");
        if (_missionInputAgent != null)
            throw new InvalidOperationException("harnessBattleMovementInputProbe refuses while another MovementInput lease is active");
        var probeInputX = ReadRequiredFiniteDouble(command, "x");
        var probeInputY = ReadRequiredFiniteDouble(command, "y");
        var probeDuration = ReadRequiredFiniteDouble(command, "durationSeconds");
        if (probeInputX < -1.0 || probeInputX > 1.0 || probeInputY < -1.0 || probeInputY > 1.0 || probeDuration <= 0.0 || probeDuration > 0.5)
            throw new InvalidOperationException("harnessBattleMovementInputProbe requires axes in [-1,1] and a duration in (0,0.5]");
        var probeMagnitude = Math.Sqrt(probeInputX * probeInputX + probeInputY * probeInputY);
        if (probeMagnitude <= 0.0)
            throw new InvalidOperationException("harnessBattleMovementInputProbe requires a nonzero movement vector");
        if (probeMagnitude > 1.0)
        {
            probeInputX /= probeMagnitude;
            probeInputY /= probeMagnitude;
        }
        var probeCampaignDayBefore = CampaignTime.Now.ToDays;
        var probeTimeModeBefore = Campaign.Current.TimeControlMode.ToString();
        var probePositionBefore = movementProbeMainAgent.Position;
        AgentMissionInputPatch.BeginBattleMovementProbe(movementProbeMission, movementProbeMainAgent);
        _missionInputAgent = movementProbeMainAgent;
        _missionInputVector = new TaleWorlds.Library.Vec2((float)probeInputX, (float)probeInputY);
        _missionInputExpiresAt = EngineTime.ApplicationTime + (float)probeDuration;
        _missionInputAgent.MovementInputVector = _missionInputVector;
        var battleMovementProbeData = new StringBuilder(384);
        battleMovementProbeData.Append("{\"schemaVersion\":1,\"scope\":\"harness-only\",\"nativeInput\":\"MainAgent.MovementInputVector after MissionMainAgentController.ControlTick\"")
            .Append(",\"x\":").Append(probeInputX.ToString("R", CultureInfo.InvariantCulture))
            .Append(",\"y\":").Append(probeInputY.ToString("R", CultureInfo.InvariantCulture))
            .Append(",\"durationSeconds\":").Append(probeDuration.ToString("R", CultureInfo.InvariantCulture))
            .Append(",\"mainAgentController\":\"").Append(Escape(movementProbeMainAgent.Controller.ToString())).Append('"');
        battleMovementProbeData.Append(",\"positionBefore\":{\"x\":").Append(probePositionBefore.X.ToString("R", CultureInfo.InvariantCulture))
            .Append(",\"y\":").Append(probePositionBefore.Y.ToString("R", CultureInfo.InvariantCulture))
            .Append(",\"z\":").Append(probePositionBefore.Z.ToString("R", CultureInfo.InvariantCulture)).Append('}')
            .Append(",\"campaignDayBefore\":").Append(probeCampaignDayBefore.ToString("R", CultureInfo.InvariantCulture))
            .Append(",\"campaignDayAfter\":").Append(CampaignTime.Now.ToDays.ToString("R", CultureInfo.InvariantCulture))
            .Append(",\"timeControlModeBefore\":\"").Append(Escape(probeTimeModeBefore)).Append('"')
            .Append(",\"timeControlModeAfter\":\"").Append(Escape(Campaign.Current.TimeControlMode.ToString())).Append('"');
        battleMovementProbeData.Append('}');
        WriteResponse(commandId, action, "completed", behavior, null, battleMovementProbeData.ToString());
    }

    private void HandleHarnessBattleAgentNavigatorProbe(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var navigatorMission = Mission.Current;
        var navigatorMainAgent = navigatorMission?.MainAgent;
        if (!AgentMissionInputPatch.IsSupportedCampaignFieldBattleInput(navigatorMission, navigatorMainAgent))
            throw new InvalidOperationException("harnessBattleAgentNavigatorProbe requires the active stopped Campaign field Battle Mission and Player-controlled MainAgent");
        if (_missionNavigator != null || _missionInputAgent != null)
            throw new InvalidOperationException("harnessBattleAgentNavigatorProbe refuses while another Native movement lease is active");
        var navigatorFormation = navigatorMainAgent.Formation;
        if (navigatorFormation == null || navigatorFormation.CountOfUnits != 1 || !navigatorFormation.IsAIControlled)
            throw new InvalidOperationException("harnessBattleAgentNavigatorProbe requires the isolated singleton MainAgent Formation to be AI-controlled");
        var navigatorDuration = ReadDouble(command, "durationSeconds");
        if (navigatorDuration == 0.0) navigatorDuration = 8.0;
        if (double.IsNaN(navigatorDuration) || double.IsInfinity(navigatorDuration) || navigatorDuration < 1.0 || navigatorDuration > 10.0)
            throw new InvalidOperationException("harnessBattleAgentNavigatorProbe durationSeconds must be between 1 and 10");
        var nearestEnemy = navigatorMission.Agents
            .Where(agent => agent != null && agent != navigatorMainAgent && agent.IsActive() && agent.IsHuman && agent.Team != null && navigatorMainAgent.IsEnemyOf(agent))
            .Select(agent => new
            {
                Agent = agent,
                Distance = Math.Sqrt(Math.Pow(navigatorMainAgent.Position.X - agent.Position.X, 2) + Math.Pow(navigatorMainAgent.Position.Y - agent.Position.Y, 2) + Math.Pow(navigatorMainAgent.Position.Z - agent.Position.Z, 2))
            })
            .OrderBy(item => item.Distance)
            .ThenBy(item => item.Agent.Index)
            .FirstOrDefault();
        if (nearestEnemy == null)
            throw new InvalidOperationException("harnessBattleAgentNavigatorProbe requires one active enemy human Agent in the current Mission");
        double awayX = navigatorMainAgent.Position.X - nearestEnemy.Agent.Position.X;
        double awayY = navigatorMainAgent.Position.Y - nearestEnemy.Agent.Position.Y;
        var awayLength = Math.Sqrt(awayX * awayX + awayY * awayY);
        if (awayLength < 0.1)
            throw new InvalidOperationException("harnessBattleAgentNavigatorProbe cannot resolve a horizontal retreat direction from the nearest enemy");
        awayX /= awayLength;
        awayY /= awayLength;
        var startPosition = navigatorMainAgent.Position;
        TaleWorlds.Engine.WorldPosition battleNavigatorTargetWorldPosition = default;
        var targetResolved = false;
        foreach (var distance in new[] { 8f, 12f, 16f })
        {
            var target = new TaleWorlds.Library.Vec3((float)(startPosition.X + awayX * distance), (float)(startPosition.Y + awayY * distance), startPosition.Z);
            var candidate = new TaleWorlds.Engine.WorldPosition(navigatorMission.Scene, target);
            var start = new TaleWorlds.Engine.WorldPosition(navigatorMission.Scene, startPosition);
            if (navigatorMission.Scene.DoesPathExistBetweenPositions(start, candidate))
            {
                battleNavigatorTargetWorldPosition = candidate;
                targetResolved = true;
                return;
            }
        }
        if (!targetResolved)
            throw new InvalidOperationException("harnessBattleAgentNavigatorProbe found no 8/12/16-unit NavMesh path away from the nearest enemy");
        var navigatorDirectionX = battleNavigatorTargetWorldPosition.AsVec2.X - startPosition.X;
        var navigatorDirectionY = battleNavigatorTargetWorldPosition.AsVec2.Y - startPosition.Y;
        var navigatorDirection = (float)Math.Atan2(navigatorDirectionY, navigatorDirectionX);
        var navigatorCampaignDayBefore = CampaignTime.Now.ToDays;
        var navigatorTimeModeBefore = Campaign.Current.TimeControlMode.ToString();
        var originalNavigatorController = navigatorMainAgent.Controller;
        var originalNavigatorFormationAi = navigatorFormation.IsAIControlled;
        var battleNavigator = new SandBox.AgentNavigator(navigatorMainAgent);
        try
        {
            navigatorFormation.SetControlledByAI(false);
            navigatorMainAgent.Controller = AgentControllerType.AI;
            battleNavigator.SetTargetFrame(battleNavigatorTargetWorldPosition, navigatorDirection, rangeThreshold:1.5f, rotationThreshold:-10f, flags:(Agent.AIScriptedFrameFlags)0, disableClearTargetWhenTargetIsReached:false);
        }
        catch
        {
            try { battleNavigator.ClearTarget(); } catch { }
            if (navigatorMainAgent.IsActive() && navigatorMainAgent.Controller != originalNavigatorController)
            {
                try { navigatorMainAgent.Controller = originalNavigatorController; }
                catch { }
            }
            if (navigatorFormation.IsAIControlled != originalNavigatorFormationAi)
            {
                try { navigatorFormation.SetControlledByAI(originalNavigatorFormationAi); }
                catch { }
            }
            throw;
        }
        _missionNavigator = battleNavigator;
        _missionNavigationMission = navigatorMission;
        _missionNavigationOwner = navigatorMainAgent;
        _missionNavigationTargetAgentIndex = -1;
        _missionNavigationTargetPosition = battleNavigatorTargetWorldPosition.GetGroundVec3();
        _missionNavigationOriginalController = originalNavigatorController;
        _missionNavigationBattleProbeFormation = navigatorFormation;
        _missionNavigationBattleProbeOriginalFormationAiControlled = originalNavigatorFormationAi;
        _missionNavigationStartedAt = EngineTime.ApplicationTime;
        _missionNavigationExpiresAt = EngineTime.ApplicationTime + (float)navigatorDuration;
        _lastMissionNavigationTickAt = navigatorMission.CurrentTime;
        _missionNavigationStatus = battleNavigator._agentState.ToString();
        _missionNavigationBattleProbe = true;
        var battleNavigatorData = new StringBuilder(448);
        battleNavigatorData.Append("{\"schemaVersion\":1,\"scope\":\"harness-only\",\"nativeNavigator\":\"SandBox.AgentNavigator.SetTargetFrame\",\"targetMode\":\"away-from-nearest-active-enemy\"")
            .Append(",\"enemyAgentIndex\":").Append(nearestEnemy.Agent.Index)
            .Append(",\"enemyDistanceBefore\":").Append(nearestEnemy.Distance.ToString("R", CultureInfo.InvariantCulture))
            .Append(",\"durationSeconds\":").Append(navigatorDuration.ToString("R", CultureInfo.InvariantCulture))
            .Append(",\"controllerBefore\":\"").Append(Escape(originalNavigatorController.ToString())).Append('"')
            .Append(",\"controllerAfter\":\"").Append(Escape(navigatorMainAgent.Controller.ToString())).Append('"')
            .Append(",\"formationAiControlledBefore\":").Append(originalNavigatorFormationAi ? "true" : "false")
            .Append(",\"formationAiControlledAfter\":").Append(navigatorFormation.IsAIControlled ? "true" : "false")
            .Append(",\"navState\":\"").Append(Escape(_missionNavigationStatus)).Append('"')
            .Append(",\"target\":{\"x\":").Append(battleNavigatorTargetWorldPosition.GetGroundVec3().X.ToString("R", CultureInfo.InvariantCulture))
            .Append(",\"y\":").Append(battleNavigatorTargetWorldPosition.GetGroundVec3().Y.ToString("R", CultureInfo.InvariantCulture))
            .Append(",\"z\":").Append(battleNavigatorTargetWorldPosition.GetGroundVec3().Z.ToString("R", CultureInfo.InvariantCulture)).Append('}')
            .Append(",\"campaignDayBefore\":").Append(navigatorCampaignDayBefore.ToString("R", CultureInfo.InvariantCulture))
            .Append(",\"campaignDayAfter\":").Append(CampaignTime.Now.ToDays.ToString("R", CultureInfo.InvariantCulture))
            .Append(",\"timeControlModeBefore\":\"").Append(Escape(navigatorTimeModeBefore)).Append('"')
            .Append(",\"timeControlModeAfter\":\"").Append(Escape(Campaign.Current.TimeControlMode.ToString())).Append('"').Append('}');
        WriteResponse(commandId, action, "completed", behavior, null, battleNavigatorData.ToString());
    }
}
