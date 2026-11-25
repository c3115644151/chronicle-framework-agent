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
    private void UpdateMissionLeaveLease()
    {
        var mission = _missionLeaveMission;
        if (mission == null) return;
        if (mission.MissionEnded || Mission.Current != mission || Game.Current?.GameStateManager?.ActiveState is not MissionState)
        {
            ClearMissionLeaveLease("mission-ended-or-changed");
            return;
        }
        if (EngineTime.ApplicationTime >= _missionLeaveExpiresAt)
            ClearMissionLeaveLease("hold-timeout");
    }

    private void ClearMissionLeaveLease(string status)
    {
        var mission = _missionLeaveMission;
        if (mission != null && ReferenceEquals(mission.InputManager, _missionLeaveInputContext))
        {
            try { mission.InputManager = _missionLeaveOriginalInputContext; }
            catch (Exception exception) { ChronicleDiagnostics.Write($"agent-mission-leave-context-restore-failed|type={exception.GetType().Name}|message={exception.Message}"); }
        }
        _missionLeaveMission = null;
        _missionLeaveOriginalInputContext = null;
        _missionLeaveInputContext = null;
        _missionLeaveExpiresAt = 0f;
        _missionLeaveStartedAt = 0f;
        _missionLeaveStatus = status;
    }

    internal static string BuildMissionLeaveObservationJson(Mission mission)
    {
        var protocol = _activeInstance;
        if (protocol == null || mission == null || protocol._missionLeaveMission != mission || mission != Mission.Current)
            return "null";
        var remaining = Math.Max(0.0, protocol._missionLeaveExpiresAt - EngineTime.ApplicationTime);
        var nativeProgress = mission.GetMissionEndTimerValue();
        return "{\"status\":\"" + Escape(protocol._missionLeaveStatus) + "\",\"active\":true,\"secondsRemaining\":" + remaining.ToString("R", CultureInfo.InvariantCulture) + ",\"nativeLeaveProgressSeconds\":" + nativeProgress.ToString("R", CultureInfo.InvariantCulture) + ",\"nativeLeaveThresholdSeconds\":" + mission.GetMissionEndTimeInSeconds().ToString("R", CultureInfo.InvariantCulture) + "}";
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
        var isActiveBattleNavigatorProbe = _missionNavigationBattleProbe && mission != null && !mission.MissionEnded &&
            mission.Mode == MissionMode.Battle && mission.IsFieldBattle && !mission.IsFriendlyMission &&
            PlayerEncounter.IsActive && PlayerEncounter.Battle != null && Campaign.Current?.TimeControlMode == CampaignTimeControlMode.Stop &&
            _missionNavigationOwner?.Controller == AgentControllerType.AI;
        var supportedNavigationContext = AgentMissionInputPatch.IsSupportedLocationMission(mission) || isActiveBattleNavigatorProbe;
        if (mission == null || mission != _missionNavigationMission || mission.MissionEnded || activeState == null || mission.MainAgent != _missionNavigationOwner || !supportedNavigationContext)
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
        var battleProbeFormation = _missionNavigationBattleProbeFormation;
        var battleProbeFormationAiOriginal = _missionNavigationBattleProbeOriginalFormationAiControlled;
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
        if (battleProbeFormation != null && battleProbeFormationAiOriginal.HasValue && battleProbeFormation.IsAIControlled != battleProbeFormationAiOriginal.Value)
        {
            try { battleProbeFormation.SetControlledByAI(battleProbeFormationAiOriginal.Value); }
            catch (Exception exception) { ChronicleDiagnostics.Write($"agent-battle-navigator-formation-restore-failed|type={exception.GetType().Name}|message={exception.Message}"); }
        }
        _missionNavigator = null;
        _missionNavigationStatus = status;
        _missionNavigationBattleProbe = false;
        _missionNavigationBattleProbeFormation = null;
        _missionNavigationBattleProbeOriginalFormationAiControlled = null;
        _missionNavigationOriginalController = null;
        _missionNavigationExpiresAt = 0f;
        _lastMissionNavigationTickAt = 0f;
    }

    internal static string BuildMissionNavigationObservationJson(Agent mainAgent)
    {
        var protocol = _activeInstance;
        var isBattlePointProbe = protocol?._missionNavigationBattleProbe == true;
        if (protocol == null || mainAgent == null || protocol._missionNavigationMission == null || protocol._missionNavigationMission != Mission.Current || protocol._missionNavigationOwner != mainAgent || (protocol._missionNavigationTargetAgentIndex < 0 && !isBattlePointProbe) || string.IsNullOrWhiteSpace(protocol._missionNavigationStatus))
            return "null";
        var x = mainAgent.Position.X - protocol._missionNavigationTargetPosition.X;
        var y = mainAgent.Position.Y - protocol._missionNavigationTargetPosition.Y;
        var z = mainAgent.Position.Z - protocol._missionNavigationTargetPosition.Z;
        var distance = Math.Sqrt(x * x + y * y + z * z);
        var remaining = protocol._missionNavigator == null ? 0.0 : Math.Max(0.0, protocol._missionNavigationExpiresAt - EngineTime.ApplicationTime);
        var targetAgentJson = protocol._missionNavigationTargetAgentIndex < 0 ? "null" : protocol._missionNavigationTargetAgentIndex.ToString(CultureInfo.InvariantCulture);
        return "{\"scope\":\"" + (isBattlePointProbe ? "harness-battle-point" : "friendly-location-agent") + "\",\"status\":\"" + Escape(protocol._missionNavigationStatus) + "\",\"active\":" + (protocol._missionNavigator != null ? "true" : "false") + ",\"targetAgentIndex\":" + targetAgentJson + ",\"targetPosition\":{\"x\":" + protocol._missionNavigationTargetPosition.X.ToString("R", CultureInfo.InvariantCulture) + ",\"y\":" + protocol._missionNavigationTargetPosition.Y.ToString("R", CultureInfo.InvariantCulture) + ",\"z\":" + protocol._missionNavigationTargetPosition.Z.ToString("R", CultureInfo.InvariantCulture) + "},\"distance\":" + distance.ToString("R", CultureInfo.InvariantCulture) + ",\"secondsRemaining\":" + remaining.ToString("R", CultureInfo.InvariantCulture) + "}";
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
        if (!AgentMissionInputPatch.IsSupportedLocationMission(mission) && !AgentMissionInputPatch.IsActiveBattleMovementProbe(mission, agent))
            return;
        agent.MovementInputVector = protocol._missionInputVector;
    }

    private void ClearMissionInputLease()
    {
        AgentMissionInputPatch.ClearBattleMovementProbe();
        if (_missionInputAgent != null && _missionInputAgent.IsActive())
            _missionInputAgent.MovementInputVector = TaleWorlds.Library.Vec2.Zero;
        _missionInputAgent = null;
        _missionInputVector = TaleWorlds.Library.Vec2.Zero;
        _missionInputExpiresAt = 0f;
    }
}
