using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal static class AgentHostProviderDecisionRecovery
{
    internal const int MaxRejectedDecisions = 2;

    private static readonly HashSet<string> RecoverableErrorCodes = new(StringComparer.Ordinal)
    {
        "provider-action-unavailable", "provider-control-unavailable", "provider-control-arguments-invalid",
        "provider-arguments-missing", "provider-arguments-invalid-json", "provider-arguments-shape-invalid",
        "provider-argument-unavailable", "provider-decision-ambiguous", "provider-decision-field-unavailable"
    };

    internal static bool CanRetry(string errorCode, int rejectedDecisions) =>
        rejectedDecisions < MaxRejectedDecisions && RecoverableErrorCodes.Contains(errorCode);

    internal static JsonArray CurrentActionNames(JsonArray actions) => new(actions.OfType<JsonObject>()
        .Select(action => ReadString(action, "action"))
        .Where(name => !string.IsNullOrWhiteSpace(name))
        .Select(name => (JsonNode?)JsonValue.Create(name))
        .ToArray());

    internal static JsonObject BuildFeedback(string errorCode, JsonArray actions, JsonArray controls)
    {
        var actionNames = CurrentActionNames(actions).Select(node => node?.GetValue<string>()).Where(name => name is not null);
        var controlNames = controls.Select(node => node?.GetValue<string>()).Where(name => name is not null);
        var requiredNextStep = errorCode == "provider-arguments-invalid-json"
            ? "Return arguments as a JSON object matching the currently listed names and values. Do not quote or nest JSON; no Native action was sent."
            : $"The prior response was rejected before any Native action. Choose exactly one action from [{string.Join(", ", actionNames)}] or control from [{string.Join(", ", controlNames)}] in the current catalog; do not repeat the rejected response.";

        return new JsonObject
        {
            ["kind"] = "decision-rejected-before-native",
            ["code"] = errorCode,
            ["nativeActionSent"] = false,
            ["allowedActionNames"] = CurrentActionNames(actions),
            ["allowedControls"] = controls.DeepClone(),
            ["requiredNextStep"] = requiredNextStep
        };
    }

    internal static IReadOnlyList<object> RunContractSelfTests()
    {
        var actions = new JsonArray(new JsonObject { ["action"] = "move", ["arguments"] = new JsonArray("SettlementId") });
        var controls = new JsonArray("observeAgain");
        var feedback = BuildFeedback("provider-arguments-invalid-json", actions, controls);
        var retryCountBounded = CanRetry("provider-arguments-invalid-json", 0) &&
            CanRetry("provider-arguments-invalid-json", 1) &&
            !CanRetry("provider-arguments-invalid-json", 2) &&
            !CanRetry("provider-http-error", 0);
        if (!retryCountBounded ||
            ReadString(feedback, "kind") != "decision-rejected-before-native" ||
            ReadString(feedback, "code") != "provider-arguments-invalid-json" ||
            ReadBoolean(feedback, "nativeActionSent") ||
            feedback["allowedActionNames"] is not JsonArray names || names.Count != 1 || names[0]?.GetValue<string>() != "move" ||
            feedback["allowedControls"] is not JsonArray listedControls || listedControls.Count != 1 || listedControls[0]?.GetValue<string>() != "observeAgain" ||
            ReadString(feedback, "requiredNextStep")?.Contains("JSON object", StringComparison.Ordinal) != true)
            throw new AgentHostException("provider-decision-recovery-contract-self-test-failed", "Retry feedback must remain bounded, name only current catalogs, and explicitly state that no Native action was sent.");

        return [new { scenario = "provider-decision-recovery-is-bounded-and-preserves-the-current-native-catalog", passed = true }];
    }

    private static string? ReadString(JsonObject? value, string key) =>
        value?[key] is JsonValue node && node.TryGetValue<string>(out var result) ? result : null;

    private static bool ReadBoolean(JsonObject? value, string key) =>
        value?[key] is JsonValue node && node.TryGetValue<bool>(out var result) && result;
}
