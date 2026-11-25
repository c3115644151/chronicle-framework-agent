using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal static class AgentHostCampaignStateFacts
{
    internal static bool IsNativeLocationMenu(JsonObject state)
    {
        var context = state["context"] as JsonObject;
        var menuId = ReadString(context, "menuId");
        var currentSettlementId = ReadString(state["location"] as JsonObject, "currentSettlementId");
        var encounteredPartyId = ReadString(context, "encounteredPartyId");
        return !string.IsNullOrWhiteSpace(menuId) && !string.IsNullOrWhiteSpace(currentSettlementId) &&
               string.Equals(currentSettlementId, encounteredPartyId, StringComparison.Ordinal);
    }

    internal static bool IsActiveEncounter(JsonObject state)
    {
        var context = state["context"] as JsonObject;
        var menuId = ReadString(context, "menuId");
        return context?["battleSimulation"] is not null || menuId == "encounter" ||
               (!IsNativeLocationMenu(state) &&
                (ReadBoolean(context, "encounterActive") || !string.IsNullOrWhiteSpace(ReadString(context, "encounteredPartyId"))));
    }

    internal static IReadOnlyList<object> RunContractSelfTests()
    {
        var trainingField = new JsonObject
        {
            ["context"] = new JsonObject
            {
                ["gameState"] = "MapState", ["menuId"] = "training_field_menu", ["encounterActive"] = true,
                ["encounteredPartyId"] = "tutorial_training_field", ["battleSimulation"] = null
            },
            ["location"] = new JsonObject { ["currentSettlementId"] = "tutorial_training_field" }
        };
        if (!IsNativeLocationMenu(trainingField) || IsActiveEncounter(trainingField))
            throw new AgentHostException("campaign-state-facts-training-field-menu-misclassified", "The original post-tutorial training-field menu must not be confused with a hostile party encounter.");

        var banditEncounter = new JsonObject
        {
            ["context"] = new JsonObject
            {
                ["gameState"] = "MapState", ["menuId"] = "encounter", ["encounterActive"] = true,
                ["encounteredPartyId"] = "looter-party"
            },
            ["location"] = new JsonObject { ["currentSettlementId"] = null }
        };
        if (IsNativeLocationMenu(banditEncounter) || !IsActiveEncounter(banditEncounter))
            throw new AgentHostException("campaign-state-facts-hostile-encounter-misclassified", "A genuine party encounter must remain an active encounter.");

        return [
            new { scenario = "native-training-field-menu-is-not-party-encounter", passed = true },
            new { scenario = "native-hostile-party-encounter-remains-active", passed = true }
        ];
    }

    private static string? ReadString(JsonObject? source, string key) =>
        source?[key] is JsonValue value && value.TryGetValue<string>(out var text) ? text : null;

    private static bool ReadBoolean(JsonObject? source, string key) =>
        source?[key] is JsonValue value && value.TryGetValue<bool>(out var result) && result;
}
