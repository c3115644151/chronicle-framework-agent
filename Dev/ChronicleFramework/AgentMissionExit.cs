using System;
using System.Globalization;
using System.Linq;
using System.Text;
using SandBox.Objects;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.GameState;
using TaleWorlds.Core;
using TaleWorlds.Engine;
using TaleWorlds.Library;
using TaleWorlds.MountAndBlade;

namespace ChronicleFramework;

internal static class ChronicleAgentMissionExit
{
    internal sealed class ExitCandidate
    {
        internal MissionObject MissionObject;
        internal UsableMissionObject UsableObject;
        internal WorldFrame UserFrame;
        internal bool HasPath;
        internal double Distance;
        internal string ObjectId;
        internal string ActionText;
    }

    internal static string BuildTargetsJson(Mission mission, Agent mainAgent)
    {
        var candidates = GetCandidates(mission, mainAgent);
        var json = new StringBuilder(1024);
        json.Append('[');
        for (var index = 0; index < candidates.Length; index++)
        {
            if (index > 0) json.Append(',');
            var item = candidates[index];
            var position = item.UserFrame.Origin.GetNavMeshVec3();
            json.Append('{');
            ChroniclePartyUpgradeAdapter.Property(json, "missionObjectId", item.ObjectId, addComma: false);
            ChroniclePartyUpgradeAdapter.Property(json, "objectType", item.MissionObject.GetType().Name);
            ChroniclePartyUpgradeAdapter.Property(json, "name", item.MissionObject.GameEntity.Name);
            ChroniclePartyUpgradeAdapter.Property(json, "actionText", item.ActionText);
            json.Append(",\"isNativeExit\":true");
            json.Append(",\"isUsableNow\":").Append(ChroniclePartyUpgradeAdapter.Bool(item.UsableObject.IsUsableByAgent(mainAgent) && !item.MissionObject.IsDisabled));
            json.Append(",\"isDeactivated\":").Append(ChroniclePartyUpgradeAdapter.Bool(item.UsableObject.IsDeactivated));
            json.Append(",\"hasPath\":").Append(ChroniclePartyUpgradeAdapter.Bool(item.HasPath));
            json.Append(",\"distance\":").Append(item.Distance.ToString("R", CultureInfo.InvariantCulture));
            json.Append(",\"userPosition\":{\"x\":").Append(position.X.ToString("R", CultureInfo.InvariantCulture));
            json.Append(",\"y\":").Append(position.Y.ToString("R", CultureInfo.InvariantCulture));
            json.Append(",\"z\":").Append(position.Z.ToString("R", CultureInfo.InvariantCulture)).Append("}}");
        }
        return json.Append(']').ToString();
    }

    internal static ExitCandidate[] GetCandidates(Mission mission, Agent mainAgent)
    {
        if (mission == null || mission.MissionEnded || mainAgent == null || !mainAgent.IsActive()) return Array.Empty<ExitCandidate>();
        if (!AgentMissionInputPatch.IsSupportedLocationMission(mission)) return Array.Empty<ExitCandidate>();

        return mission.ActiveMissionObjects
            .Where(IsNativeMissionExit)
            .Select(missionObject => TryBuildCandidate(mission, mainAgent, missionObject))
            .Where(candidate => candidate != null)
            .OrderBy(candidate => candidate.Distance)
            .Take(12)
            .ToArray();
    }

    internal static ExitCandidate FindCandidate(Mission mission, Agent mainAgent, string missionObjectId)
    {
        if (string.IsNullOrWhiteSpace(missionObjectId) || !TryParseObjectId(missionObjectId, out var objectId)) return null;
        return GetCandidates(mission, mainAgent).FirstOrDefault(candidate => candidate.MissionObject.Id == objectId);
    }

    internal static string BuildUseReceipt(Agent mainAgent, ExitCandidate candidate, string timeModeBefore, double campaignDayBefore, bool missionEnded)
    {
        var json = new StringBuilder(512);
        json.Append('{').Append("\"schemaVersion\":1");
        ChroniclePartyUpgradeAdapter.Property(json, "missionObjectId", candidate.ObjectId);
        ChroniclePartyUpgradeAdapter.Property(json, "exitObjectType", candidate.MissionObject.GetType().Name);
        ChroniclePartyUpgradeAdapter.Property(json, "nativeHandler", "Agent.HandleStartUsingAction/UsableMissionObject.OnUse");
        json.Append(",\"nativeUseRequested\":true");
        json.Append(",\"missionEndedImmediately\":").Append(ChroniclePartyUpgradeAdapter.Bool(missionEnded));
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeBefore", timeModeBefore);
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeAfter", Campaign.Current.TimeControlMode.ToString());
        json.Append(",\"campaignDayBefore\":").Append(campaignDayBefore.ToString("F6", CultureInfo.InvariantCulture));
        json.Append(",\"campaignDayAfter\":").Append(CampaignTime.Now.ToDays.ToString("F6", CultureInfo.InvariantCulture));
        return json.Append('}').ToString();
    }

    private static string Escape(string value) => (value ?? string.Empty).Replace("\\", "\\\\").Replace("\"", "\\\"");

    internal static string UseObservedExit(string missionObjectId)
    {
        var mission = Mission.Current;
        var missionState = Game.Current?.GameStateManager?.ActiveState as MissionState;
        var mainAgent = mission?.MainAgent;
        if (mission == null || mission.MissionEnded || missionState == null || mainAgent == null || !mainAgent.IsActive() || !mainAgent.IsPlayerControlled)
            throw new InvalidOperationException("missionUseExit requires an active Location Mission with the Player-controlled MainAgent");
        if (!AgentMissionInputPatch.IsSupportedLocationMission(mission))
            throw new InvalidOperationException("missionUseExit requires a supported non-battle Town, Tavern or Village Location Mission");
        if (Campaign.Current?.TimeControlMode != CampaignTimeControlMode.Stop)
            throw new InvalidOperationException("missionUseExit requires the Campaign clock to remain stopped");
        if (mission.IsTeleportingAgents)
            throw new InvalidOperationException("missionUseExit rejects Mission teleport mode");
        if (string.IsNullOrWhiteSpace(missionObjectId))
            throw new InvalidOperationException("missionObjectId must come from the current state.mission.exitTargets observation");

        var candidate = FindCandidate(mission, mainAgent, missionObjectId);
        if (candidate == null) throw new InvalidOperationException("missionObjectId is stale, hidden, inactive or is not a current Native Mission exit");
        if (candidate.Distance > 2.5)
            throw new InvalidOperationException("MainAgent must reach the current Native Mission exit before using it");
        if (candidate.MissionObject.IsDisabled || candidate.UsableObject.IsDisabledForAgent(mainAgent) || !candidate.UsableObject.IsUsableByAgent(mainAgent))
            throw new InvalidOperationException("The Native Mission exit is currently disabled for the MainAgent");
        if (mainAgent.CurrentlyUsedGameObject != null)
            throw new InvalidOperationException("MainAgent is already using a Native Mission object");

        var timeModeBefore = Campaign.Current.TimeControlMode.ToString();
        var campaignDayBefore = CampaignTime.Now.ToDays;
        mainAgent.HandleStartUsingAction(candidate.UsableObject, -1);
        var json = new StringBuilder(512);
        json.Append('{').Append("\"schemaVersion\":1");
        ChroniclePartyUpgradeAdapter.Property(json, "missionObjectId", candidate.ObjectId);
        ChroniclePartyUpgradeAdapter.Property(json, "exitObjectType", candidate.MissionObject.GetType().Name);
        ChroniclePartyUpgradeAdapter.Property(json, "nativeHandler", "Agent.HandleStartUsingAction/UsableMissionObject.OnUse");
        json.Append(",\"useStarted\":").Append(ChroniclePartyUpgradeAdapter.Bool(mainAgent.CurrentlyUsedGameObject == candidate.UsableObject));
        json.Append(",\"missionEnded\":").Append(ChroniclePartyUpgradeAdapter.Bool(mission.MissionEnded));
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeBefore", timeModeBefore);
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeAfter", Campaign.Current.TimeControlMode.ToString());
        json.Append(",\"campaignDayBefore\":").Append(campaignDayBefore.ToString("F6", CultureInfo.InvariantCulture));
        json.Append(",\"campaignDayAfter\":").Append(CampaignTime.Now.ToDays.ToString("F6", CultureInfo.InvariantCulture));
        return json.Append('}').ToString();
    }

    private static ExitCandidate TryBuildCandidate(Mission mission, Agent mainAgent, MissionObject missionObject)
    {
        if (missionObject == null || missionObject.IsDisabled || !missionObject.GameEntity.IsValid) return null;
        if (missionObject is not UsableMissionObject usableObject) return null;
        try
        {
            var frame = usableObject.GetUserFrameForAgent(mainAgent);
            var targetWorldPosition = frame.Origin;
            var target = targetWorldPosition.GetNavMeshVec3();
            var distance = Distance(mainAgent.Position, target);
            var startPosition = new WorldPosition(mission.Scene, mainAgent.Position);
            var hasPath = mission.Scene?.DoesPathExistBetweenPositions(startPosition, targetWorldPosition) == true;
            var actionText = missionObject is ExitDoor exitDoor
                ? exitDoor.GetActionTextForStandingPoint(usableObject)?.ToString() ?? string.Empty
                : usableObject.ActionMessage?.ToString() ?? string.Empty;
            return new ExitCandidate
            {
                MissionObject = missionObject,
                UsableObject = usableObject,
                UserFrame = frame,
                HasPath = hasPath,
                Distance = distance,
                ObjectId = FormatObjectId(missionObject.Id),
                ActionText = actionText
            };
        }
        catch
        {
            return null;
        }
    }

    private static bool IsNativeMissionExit(MissionObject missionObject)
    {
        if (missionObject is PassageUsePoint passageUsePoint) return passageUsePoint.IsMissionExit;
        return missionObject is ExitDoor;
    }

    private static string FormatObjectId(MissionObjectId id) => id.Id.ToString(CultureInfo.InvariantCulture) + ":" + (id.CreatedAtRuntime ? "1" : "0");

    private static bool TryParseObjectId(string value, out MissionObjectId id)
    {
        id = MissionObjectId.Invalid;
        var parts = value.Split(':');
        if (parts.Length != 2 || !int.TryParse(parts[0], NumberStyles.Integer, CultureInfo.InvariantCulture, out var nativeId) ||
            (parts[1] != "0" && parts[1] != "1")) return false;
        id = new MissionObjectId(nativeId, parts[1] == "1");
        return true;
    }

    internal static double Distance(Vec3 first, Vec3 second)
    {
        var x = first.X - second.X;
        var y = first.Y - second.Y;
        var z = first.Z - second.Z;
        return Math.Sqrt(x * x + y * y + z * z);
    }
}
