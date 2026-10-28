using System;
using TaleWorlds.CampaignSystem;
using HarmonyLib;
using TaleWorlds.MountAndBlade;
using TaleWorlds.MountAndBlade.View.MissionViews;

namespace ChronicleFramework;

internal static class AgentMissionInputPatch
{
    private const string HarmonyId = "ChronicleFramework.TavernMissionInput";

    internal static bool IsInstalled { get; private set; }

    internal static bool IsSupportedLocationMission(Mission mission)
    {
        return mission != null && string.Equals(mission.Mode.ToString(), "StartUp", StringComparison.Ordinal) && IsSupportedLocationScene(mission);
    }

    internal static bool IsSupportedLocationLeaveMission(Mission mission)
    {
        if (mission == null || mission.MissionEnded) return false;
        var mode = mission.Mode.ToString();
        if (string.Equals(mode, "Conversation", StringComparison.Ordinal)) return IsSupportedLocationScene(mission);
        if (!string.Equals(mode, "StartUp", StringComparison.Ordinal)) return false;
        return IsSupportedLocationScene(mission) || IsSupportedTownArenaLeaveMission(mission);
    }

    private static bool IsSupportedTownArenaLeaveMission(Mission mission)
    {
        return mission != null && !mission.MissionEnded &&
            string.Equals(Campaign.Current?.CurrentMenuContext?.GameMenu?.StringId, "town_arena", StringComparison.Ordinal) &&
            mission.IsFriendlyMission;
    }

    private static bool IsSupportedLocationScene(Mission mission)
    {
        if (mission == null || string.IsNullOrWhiteSpace(mission.SceneName)) return false;
        return mission.SceneName.IndexOf("tavern", StringComparison.OrdinalIgnoreCase) >= 0 ||
            mission.SceneName.IndexOf("_town_", StringComparison.OrdinalIgnoreCase) >= 0 ||
            (mission.SceneName.IndexOf("village", StringComparison.OrdinalIgnoreCase) >= 0 && mission.SceneName.IndexOf("hideout", StringComparison.OrdinalIgnoreCase) < 0);
    }

    internal static void Install()
    {
        if (IsInstalled) return;
        try
        {
            var controlTick = AccessTools.Method(typeof(MissionMainAgentController), "ControlTick");
            var postfix = AccessTools.Method(typeof(AgentMissionInputPatch), nameof(AfterNativeControlTick));
            if (controlTick == null || postfix == null)
            {
                ChronicleDiagnostics.Write("agent-mission-input-patch-unavailable|reason=native-control-tick-not-found");
                return;
            }

            new Harmony(HarmonyId).Patch(controlTick, postfix: new HarmonyMethod(postfix));
            IsInstalled = true;
            ChronicleDiagnostics.Write("agent-mission-input-patch-installed|target=MissionMainAgentController.ControlTick");
        }
        catch (Exception exception)
        {
            ChronicleDiagnostics.Write($"agent-mission-input-patch-install-failed|type={exception.GetType().Name}|message={exception.Message}");
        }
    }

    private static void AfterNativeControlTick(MissionMainAgentController __instance)
    {
        ChronicleAgentProtocol.ApplyMissionInputAfterNativeControl(__instance?.Mission?.MainAgent);
    }
}
