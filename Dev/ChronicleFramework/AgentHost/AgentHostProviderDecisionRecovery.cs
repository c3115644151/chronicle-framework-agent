using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal static class AgentHostProviderDecisionRecovery
{
    internal const int MaxRejectedDecisions = 2;

    private static readonly HashSet<string> RecoverableErrorCodes = new(StringComparer.Ordinal)
    {
        "provider-action-unavailable", "provider-control-unavailable", "provider-control-arguments-invalid",
        "provider-arguments-missing", "provider-arguments-invalid-json", "provider-arguments-shape-invalid",
        "provider-argument-unavailable", "provider-decision-ambiguous", "provider-decision-field-unavailable",
        "provider-response-truncated", "provider-multiple-tool-calls"
    };

    internal static bool CanRetry(string errorCode, int rejectedDecisions) =>
        RecoverableErrorCodes.Contains(errorCode) &&
        rejectedDecisions < (errorCode == "provider-multiple-tool-calls" ? 1 : MaxRejectedDecisions);

    internal static async Task<ProviderDecisionResult> DecideWithSingleRetryAsync(
        JsonObject request,
        Func<CancellationToken, Task<ProviderDecisionResult>> decide,
        Action<string> onRecoverableFailure,
        CancellationToken cancellationToken)
    {
        try { return await decide(cancellationToken); }
        catch (AgentHostException exception) when (CanRetry(exception.Code, rejectedDecisions: 0))
        {
            onRecoverableFailure(exception.Code);
            request["decisionFeedback"] = BuildFeedback(exception.Code,
                request["allowedActions"] as JsonArray ?? new JsonArray(),
                request["allowedControls"] as JsonArray ?? new JsonArray());
            return await decide(cancellationToken);
        }
    }

    internal static JsonArray CurrentActionNames(JsonArray actions) => new(actions.OfType<JsonObject>()
        .Select(action => ReadString(action, "action"))
        .Where(name => !string.IsNullOrWhiteSpace(name))
        .Select(name => (JsonNode?)JsonValue.Create(name))
        .ToArray());

    internal static JsonObject BuildFeedback(string errorCode, JsonArray actions, JsonArray controls)
    {
        var actionNames = CurrentActionNames(actions).Select(node => node?.GetValue<string>()).Where(name => name is not null);
        var controlNames = controls.Select(node => node?.GetValue<string>()).Where(name => name is not null);
        var requiredNextStep = errorCode == "provider-multiple-tool-calls"
            ? "The previous response contained multiple decision tool calls. Return exactly one tool call for one currently listed action/control; no Native action was sent."
            : errorCode == "provider-response-truncated"
            ? "The previous provider response was truncated before it could be parsed. Return only one compact JSON object matching the current schema and listed catalog; omit explanations and do not repeat the prior response. No Native action was sent."
            : errorCode == "provider-arguments-invalid-json"
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
            CanRetry("provider-response-truncated", 0) && !CanRetry("provider-response-truncated", 2) &&
            CanRetry("provider-multiple-tool-calls", 0) && !CanRetry("provider-multiple-tool-calls", 1) &&
            !CanRetry("provider-http-error", 0);
        if (!retryCountBounded ||
            ReadString(feedback, "kind") != "decision-rejected-before-native" ||
            ReadString(feedback, "code") != "provider-arguments-invalid-json" ||
            ReadBoolean(feedback, "nativeActionSent") ||
            feedback["allowedActionNames"] is not JsonArray names || names.Count != 1 || names[0]?.GetValue<string>() != "move" ||
            feedback["allowedControls"] is not JsonArray listedControls || listedControls.Count != 1 || listedControls[0]?.GetValue<string>() != "observeAgain" ||
            ReadString(feedback, "requiredNextStep")?.Contains("JSON object", StringComparison.Ordinal) != true)
            throw new AgentHostException("provider-decision-recovery-contract-self-test-failed", "Retry feedback must remain bounded, name only current catalogs, and explicitly state that no Native action was sent.");

        var truncatedFeedback = BuildFeedback("provider-response-truncated", actions, controls);
        if (ReadString(truncatedFeedback, "requiredNextStep")?.Contains("only one compact JSON object", StringComparison.Ordinal) != true ||
            ReadBoolean(truncatedFeedback, "nativeActionSent"))
            throw new AgentHostException("provider-truncated-response-feedback-self-test-failed", "A truncated model response may receive one bounded retry with a concise schema-only instruction; it must state no Native action was sent.");

        var multipleCallFeedback = BuildFeedback("provider-multiple-tool-calls", actions, controls);
        if (ReadString(multipleCallFeedback, "requiredNextStep")?.Contains("multiple decision tool calls", StringComparison.Ordinal) != true ||
            ReadString(multipleCallFeedback, "requiredNextStep")?.Contains("exactly one tool call", StringComparison.Ordinal) != true ||
            ReadBoolean(multipleCallFeedback, "nativeActionSent"))
            throw new AgentHostException("provider-multiple-tool-call-feedback-self-test-failed", "A duplicate tool-call response may receive one bounded correction, and the feedback must explicitly require one call with no Native action sent.");

        var retryRequest = new JsonObject
        {
            ["allowedActions"] = actions.DeepClone(),
            ["allowedControls"] = controls.DeepClone()
        };
        var retryCalls = 0;
        string? observedRetryFailure = null;
        var retriedDecision = DecideWithSingleRetryAsync(retryRequest, cancellationToken =>
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (retryCalls++ == 0) throw new AgentHostException("provider-response-truncated", "Synthetic truncated output.");
            return Task.FromResult(new ProviderDecisionResult("completed", "recovery-selftest", 1, 1, "self-test",
                new JsonObject { ["action"] = "move", ["arguments"] = new JsonObject { ["SettlementId"] = "town-a" } }));
        }, code => observedRetryFailure = code, CancellationToken.None).GetAwaiter().GetResult();
        if (retryCalls != 2 || observedRetryFailure != "provider-response-truncated" ||
            ReadString(retriedDecision.Decision, "action") != "move" ||
            ReadString(retryRequest["decisionFeedback"] as JsonObject, "code") != "provider-response-truncated" ||
            ReadBoolean(retryRequest["decisionFeedback"] as JsonObject, "nativeActionSent"))
            throw new AgentHostException("provider-decision-bounded-retry-selftest-failed", "A recoverable provider failure must trigger exactly one same-catalog retry and must explicitly preserve the no-Native-action boundary.");

        var multipleCallRetryRequest = new JsonObject { ["allowedActions"] = actions.DeepClone(), ["allowedControls"] = controls.DeepClone() };
        var multipleCallRetryCalls = 0;
        string? observedMultipleCallFailure = null;
        var recoveredMultipleCall = DecideWithSingleRetryAsync(multipleCallRetryRequest, cancellationToken =>
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (multipleCallRetryCalls++ == 0)
                throw new AgentHostException("provider-multiple-tool-calls", "Synthetic multiple calls.", providerToolCallCount: 2);
            return Task.FromResult(new ProviderDecisionResult("completed", "recovery-selftest", 1, 1, "self-test",
                new JsonObject { ["action"] = "move", ["arguments"] = new JsonObject { ["SettlementId"] = "town-a" } }));
        }, code => observedMultipleCallFailure = code, CancellationToken.None).GetAwaiter().GetResult();
        if (multipleCallRetryCalls != 2 || observedMultipleCallFailure != "provider-multiple-tool-calls" ||
            ReadString(recoveredMultipleCall.Decision, "action") != "move" ||
            ReadString(multipleCallRetryRequest["decisionFeedback"] as JsonObject, "code") != "provider-multiple-tool-calls" ||
            ReadBoolean(multipleCallRetryRequest["decisionFeedback"] as JsonObject, "nativeActionSent"))
            throw new AgentHostException("provider-multiple-tool-call-bounded-retry-self-test-failed", "A provider duplicate-call failure must get one same-catalog correction before Native execution and must preserve the no-action boundary.");

        return [
            new { scenario = "provider-decision-recovery-is-bounded-and-preserves-the-current-native-catalog", passed = true },
            new { scenario = "provider-decision-recovery-retries-one-truncated-response-without-native-actions", passed = true },
            new { scenario = "provider-decision-recovery-retries-multiple-tool-calls-once-without-native-actions", passed = true }
        ];
    }

    private static string? ReadString(JsonObject? value, string key) =>
        value?[key] is JsonValue node && node.TryGetValue<string>(out var result) ? result : null;

    private static bool ReadBoolean(JsonObject? value, string key) =>
        value?[key] is JsonValue node && node.TryGetValue<bool>(out var result) && result;
}
