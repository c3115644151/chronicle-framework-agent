using System;
using System.Globalization;
using System.Linq;
using SandBox.Conversation.MissionLogics;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.GameState;
using TaleWorlds.Core;
using TaleWorlds.MountAndBlade;
using TaleWorlds.MountAndBlade.View.MissionViews;

namespace ChronicleFramework;

internal static class ChronicleMissionInteraction
{
    internal static string InteractWithObservedAgent(int agentIndex)
    {
        var mission = Mission.Current;
        var missionState = Game.Current?.GameStateManager?.ActiveState as MissionState;
        var mainAgent = mission?.MainAgent;
        if (mission == null || mission.MissionEnded || missionState == null || mainAgent == null || !mainAgent.IsActive() || !mainAgent.IsPlayerControlled)
            throw new InvalidOperationException("missionInteract requires an active Location Mission with the live player MainAgent");
        var supportedLocationMission = AgentMissionInputPatch.IsSupportedLocationMission(mission);
        var supportedArenaMission = AgentMissionInputPatch.IsSupportedTownArenaLeaveMission(mission);
        if (!supportedLocationMission && !supportedArenaMission)
            throw new InvalidOperationException("missionInteract requires a supported friendly Town, Tavern, Village or Arena Master Mission context");
        if (Campaign.Current.TimeControlMode != CampaignTimeControlMode.Stop)
            throw new InvalidOperationException("missionInteract requires the Campaign clock to remain stopped");
        if (mission.IsTeleportingAgents)
            throw new InvalidOperationException("missionInteract rejects Mission teleport mode");
        if (agentIndex < 0)
            throw new InvalidOperationException("missionInteract requires an AgentIndex from the current local Mission observation");
        var conversationManager = Campaign.Current.ConversationManager;
        if (conversationManager?.IsConversationInProgress == true)
            throw new InvalidOperationException("missionInteract rejects while another conversation is already active");

        var observedLocalAgents = mission.Agents
            .Where(agent => agent != null && agent != mainAgent && agent.IsActive())
            .Where(agent => agent.IsHuman && agent.Character != null)
            .Select(agent => new { Agent = agent, Distance = Math.Sqrt(Math.Pow(mainAgent.Position.X - agent.Position.X, 2) + Math.Pow(mainAgent.Position.Y - agent.Position.Y, 2) + Math.Pow(mainAgent.Position.Z - agent.Position.Z, 2)) })
            .Where(item => item.Distance <= 12.0)
            .OrderBy(item => item.Distance)
            .Take(32)
            .Select(item => item.Agent)
            .ToArray();
        var target = observedLocalAgents.FirstOrDefault(agent => agent.Index == agentIndex);
        if (target == null)
            throw new InvalidOperationException("missionInteract requires an active human AgentIndex from nearbySceneAgents in the current Mission observation");
        if (supportedArenaMission && !string.Equals((target.Character as CharacterObject)?.StringId, "tournament_master_empire", StringComparison.Ordinal))
            throw new InvalidOperationException("Arena Mission interaction is restricted to the currently observed Native Arena Master");
        if (target.IsEnemyOf(mainAgent))
            throw new InvalidOperationException("missionInteract rejects hostile local Agents");
        var distance = target.GetDistanceTo(mainAgent);

        var conversationLogic = mission.MissionBehaviors.OfType<MissionConversationLogic>().FirstOrDefault();
        if (conversationLogic == null || !conversationLogic.IsThereAgentAction(mainAgent, target))
            throw new InvalidOperationException("the current Native MissionConversationLogic reports no conversation action for this Agent");
        var mainAgentController = mission.MissionBehaviors.OfType<MissionMainAgentController>().FirstOrDefault();
        if (mainAgentController?.MissionScreen == null || !mainAgent.CanInteractWithAgent(target, mainAgentController.MissionScreen.CameraElevation))
            throw new InvalidOperationException("Native Agent interaction range/action eligibility is not currently satisfied");

        var targetCharacter = target.Character as CharacterObject;
        var targetHero = targetCharacter?.HeroObject;
        var beforeMode = Campaign.Current.TimeControlMode.ToString();
        var beforeDay = CampaignTime.Now.ToDays;
        target.OnUse(mainAgent, -1);

        conversationManager = Campaign.Current.ConversationManager;
        var started = conversationManager != null && conversationManager.IsConversationInProgress;
        var activeTarget = conversationManager?.OneToOneConversationHero;
        if (!started)
            throw new InvalidOperationException("Native Agent.OnUse completed, but no Mission conversation became active");
        if (targetHero != null && activeTarget != targetHero)
            throw new InvalidOperationException("Native conversation started with a different Hero than the observed target");

        return "{\"schemaVersion\":1,\"nativeEntry\":\"Agent.OnUse\",\"missionBehavior\":\"MissionConversationLogic\",\"conversationStarted\":true,\"targetAgentIndex\":" + agentIndex.ToString(CultureInfo.InvariantCulture) + ",\"targetCharacterId\":\"" + ChronicleAgentProtocol.Escape(targetCharacter?.StringId) + "\",\"targetHeroId\":" + (targetHero == null ? "null" : "\"" + ChronicleAgentProtocol.Escape(targetHero.StringId) + "\"") + ",\"conversationHeroId\":" + (activeTarget == null ? "null" : "\"" + ChronicleAgentProtocol.Escape(activeTarget.StringId) + "\"") + ",\"distance\":" + distance.ToString("R", CultureInfo.InvariantCulture) + ",\"timeControlModeBefore\":\"" + ChronicleAgentProtocol.Escape(beforeMode) + "\",\"timeControlModeAfter\":\"" + ChronicleAgentProtocol.Escape(Campaign.Current.TimeControlMode.ToString()) + "\",\"campaignDayBefore\":" + beforeDay.ToString("F3", CultureInfo.InvariantCulture) + ",\"campaignDayAfter\":" + CampaignTime.Now.ToDays.ToString("F3", CultureInfo.InvariantCulture) + "}";
    }
}
