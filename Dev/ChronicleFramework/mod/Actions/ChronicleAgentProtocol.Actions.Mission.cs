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
    private void HandleBattleMissionStatus(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentBattleMissionAdapter.BuildStatusJson());
    }

    private void HandleMissionDelegateTroops(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentBattleMissionAdapter.DelegateCurrentTroopFormations());
    }

    private void HandleMissionAutopilotMainAgent(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentBattleMissionAdapter.BeginMainAgentNativeAiAutopilotLease());
    }

    private void HandleMissionFinishDeployment(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentBattleMissionAdapter.FinishCurrentBattleDeployment());
    }

    private void HandleMissionAutoDeploy(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentBattleMissionAdapter.AutoDeployCurrentBattleDeployment());
    }

    private void HandleMissionSceneAgents(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var sceneAgentsMission = Mission.Current;
        var sceneAgentsMissionState = Game.Current?.GameStateManager?.ActiveState as MissionState;
        if (sceneAgentsMissionState == null)
            throw new InvalidOperationException("missionSceneAgents requires the current Location MissionState");
        var sceneAgentsJson = ChronicleAgentObserver.BuildMissionSceneAgentsJson(sceneAgentsMission, out var observedSceneAgents);
        _missionSceneAgentsObservationMission = sceneAgentsMission;
        _missionSceneAgentsObservation = observedSceneAgents.ToDictionary(agent => agent.Index);
        _missionSceneAgentsObservationAt = EngineTime.ApplicationTime;
        WriteResponse(commandId, action, "completed", behavior, null, sceneAgentsJson);
    }

    private void HandleMissionInput(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
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
    }

    private void HandleMissionNavigateToAgent(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
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
        if (navigationDistance > 12.0)
        {
            var observationIsCurrent = _missionSceneAgentsObservationMission == navigationMission &&
                _missionSceneAgentsObservation != null &&
                EngineTime.ApplicationTime - _missionSceneAgentsObservationAt <= MissionSceneAgentsObservationLeaseSeconds &&
                _missionSceneAgentsObservation.TryGetValue(navigationTargetAgentIndex, out var observedNavigationTarget) &&
                ReferenceEquals(observedNavigationTarget, navigationTargetAgent);
            if (!observationIsCurrent)
                throw new InvalidOperationException("remote missionNavigateToAgent target requires a recent missionSceneAgents observation from this same Mission");
        }
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
    }

    private void HandleMissionLeave(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var leaveMission = Mission.Current;
        var leaveMissionState = Game.Current?.GameStateManager?.ActiveState as MissionState;
        var leaveMainAgent = leaveMission?.MainAgent;
        if (leaveMission == null || leaveMission.MissionEnded || leaveMissionState == null || leaveMainAgent == null || !leaveMainAgent.IsActive() || !leaveMainAgent.IsPlayerControlled)
            throw new InvalidOperationException("missionLeave requires an active Location Mission with the Player-controlled MainAgent");
        if (!AgentMissionInputPatch.IsSupportedLocationLeaveMission(leaveMission) || !leaveMission.IsFriendlyMission)
            throw new InvalidOperationException("missionLeave requires a supported friendly Town, Tavern or Village Mission, including its active native Conversation mode");
        if (Campaign.Current?.TimeControlMode != CampaignTimeControlMode.Stop)
            throw new InvalidOperationException("missionLeave requires the Campaign clock to remain stopped");
        if (leaveMission.IsTeleportingAgents) throw new InvalidOperationException("missionLeave rejects Mission teleport mode");
        if (_missionLeaveMission != null) throw new InvalidOperationException("a native Leave Area hold lease is already active");
        if (leaveMission.InputManager == null) throw new InvalidOperationException("Native Mission input context is unavailable");
        _missionLeaveMission = leaveMission;
        _missionLeaveOriginalInputContext = leaveMission.InputManager;
        _missionLeaveInputContext = new ChronicleMissionLeaveInputContext(_missionLeaveOriginalInputContext, ChronicleMissionLeaveInputContext.LeaveAreaGameKeyId);
        leaveMission.InputManager = _missionLeaveInputContext;
        _missionLeaveStartedAt = EngineTime.ApplicationTime;
        _missionLeaveExpiresAt = _missionLeaveStartedAt + LeaveAreaHoldSeconds;
        _missionLeaveStatus = "holding-native-leave-area";
        var leaveReceipt = "{\"schemaVersion\":1,\"nativeInputContext\":\"Mission.InputManager.IsGameKeyDown(LeaveArea)\",\"holdSeconds\":" + LeaveAreaHoldSeconds.ToString("R", CultureInfo.InvariantCulture) + ",\"missionEndTimeInSeconds\":" + leaveMission.GetMissionEndTimeInSeconds().ToString("R", CultureInfo.InvariantCulture) + ",\"campaignDay\":" + CampaignTime.Now.ToDays.ToString("F6", CultureInfo.InvariantCulture) + ",\"timeControlMode\":\"" + Campaign.Current.TimeControlMode + "\"}";
        WriteResponse(commandId, action, "completed", behavior, null, leaveReceipt);
    }

    private void HandleTournament(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleTournamentAdapter.Invoke(action));
    }

    private void HandleMissionInteract(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var missionInteractionIndex = ReadRequiredFiniteDouble(command, "agentIndex");
        if (missionInteractionIndex < 0 || missionInteractionIndex > int.MaxValue || missionInteractionIndex != Math.Floor(missionInteractionIndex))
            throw new InvalidOperationException("agentIndex must be a nonnegative integer from the current Mission observation");
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleMissionInteraction.InteractWithObservedAgent((int)missionInteractionIndex));
    }

    private void HandleMissionCancelNavigation(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        if (_missionNavigator == null) throw new InvalidOperationException("no native Mission AgentNavigator route is active");
        if (Mission.Current?.MainAgent != _missionNavigationOwner) throw new InvalidOperationException("active Mission MainAgent changed; navigation cannot be cancelled through this context");
        ClearMissionNavigationLease("cancelled");
        var navigationCancelData = "{\"targetAgentIndex\":" + _missionNavigationTargetAgentIndex.ToString(CultureInfo.InvariantCulture) + ",\"controllerRestored\":" + (_missionNavigationOwner?.Controller == AgentControllerType.Player ? "true" : "false") + "}";
        WriteResponse(commandId, action, "completed", behavior, null, navigationCancelData);
    }

    private void HandleMissionAimAt(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
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
    }

    private void HandleBattlePause(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var battleSimulationToPause = PlayerEncounter.CurrentBattleSimulation;
        if (battleSimulationToPause == null) throw new InvalidOperationException("battlePause requires an active native battle simulation");
        battleSimulationToPause.Pause();
        WriteResponse(commandId, action, "completed", behavior);
    }

    private void HandleBattleSkip(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var battleSimulationToSkip = PlayerEncounter.CurrentBattleSimulation;
        if (battleSimulationToSkip == null || battleSimulationToSkip.IsSimulationFinished)
            throw new InvalidOperationException("battleSkip requires an unfinished native battle simulation");
        battleSimulationToSkip.Skip();
        WriteResponse(commandId, action, "completed", behavior);
    }

    private void HandleSeedVisualLoot(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
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
    }

    private void HandleBattleFinish(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
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
    }

    private void HandleBattleRetreat(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var battleSimulationToRetreat = PlayerEncounter.CurrentBattleSimulation;
        if (battleSimulationToRetreat == null) throw new InvalidOperationException("battleRetreat requires an active native battle simulation");
        if (battleSimulationToRetreat.IsSimulationFinished) throw new InvalidOperationException("battleRetreat requires an unfinished battle simulation");
        battleSimulationToRetreat.OnPlayerRetreat();
        WriteResponse(commandId, action, "completed", behavior);
    }

    private void HandleMissionRetreat(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var missionRetreatGameState = Game.Current?.GameStateManager?.ActiveState;
        var missionRetreatCurrentMission = missionRetreatGameState?.GetType().GetProperty("CurrentMission")?.GetValue(missionRetreatGameState) as Mission;
        var missionToRetreat = Mission.Current ?? missionRetreatCurrentMission;
        if (missionToRetreat == null || !string.Equals(missionRetreatGameState?.GetType().Name, "MissionState", StringComparison.Ordinal))
            throw new InvalidOperationException("missionRetreat requires an active Native MissionState with a current Mission, including its postbattle results phase");
        var battleEndLogic = missionToRetreat.GetMissionBehavior<BattleEndLogic>();
        if (battleEndLogic == null) throw new InvalidOperationException("active mission does not expose native BattleEndLogic");
        var exitResult = battleEndLogic.TryExit();
        if (exitResult == BattleEndLogic.ExitResult.SurrenderSiege)
            throw new InvalidOperationException("native TAB exit is surrender for a siege defender, not retreat");
        if (exitResult != BattleEndLogic.ExitResult.True)
            missionToRetreat.OnEndMissionRequest();
        var retreatData = "{\"nativeRequest\":\"Mission.OnEndMissionRequest\",\"tryExit\":\"" + Escape(exitResult.ToString()) + "\",\"inquiryOpen\":" + (ChronicleInquiryAdapter.IsInquiryOpen ? "true" : "false") + ",\"missionEnded\":" + (missionToRetreat.MissionEnded ? "true" : "false") + "}";
        WriteResponse(commandId, action, "completed", behavior, null, retreatData);
    }
}
