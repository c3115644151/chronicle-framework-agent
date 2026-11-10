#nullable enable
using System;
using System.Globalization;
using System.Linq;
using System.Text;
using SandBox.View.Map;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.Encounters;
using TaleWorlds.Core;
using TaleWorlds.MountAndBlade;

namespace ChronicleFramework;

internal static class ChronicleAgentBattleMissionAdapter
{
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
        json.Append("]}}");
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

    private static bool TryGetSupportedBattleMission(out Mission mission, out string reason)
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
        if (mission.Mode != MissionMode.Battle)
        {
            reason = "requires the Native Battle Mission to have started, not be in deployment/transition";
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
