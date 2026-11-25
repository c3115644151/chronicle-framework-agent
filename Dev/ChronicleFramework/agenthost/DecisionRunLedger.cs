using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

/// <summary>
/// The accounts of one bounded decision run: decision count, provider token totals, the trace array, the
/// provider route history, and the last decision/receipt. Each scenario loop used to keep those as parallel
/// locals and add to all of them by hand. The receipt shape and what counts as an executed action stay with
/// the scenario, because both differ per scenario.
/// </summary>
internal sealed class DecisionRunLedger
{
    private readonly IAgentHostDecisionProvider _provider;

    internal DecisionRunLedger(
        IAgentHostDecisionProvider provider,
        string? runId,
        int priorDecisions = 0,
        long priorPromptTokens = 0,
        long priorCompletionTokens = 0,
        JsonArray? priorTrace = null,
        JsonArray? priorProviderRouteHistory = null)
    {
        _provider = provider;
        RunId = runId ?? Guid.NewGuid().ToString("N");
        Decisions = priorDecisions;
        PromptTokens = priorPromptTokens;
        CompletionTokens = priorCompletionTokens;
        Trace = priorTrace?.DeepClone() as JsonArray ?? new JsonArray();
        Routes = priorProviderRouteHistory?.DeepClone() as JsonArray ?? new JsonArray();
    }

    internal string RunId { get; }

    internal int Decisions { get; private set; }

    internal long PromptTokens { get; private set; }

    internal long CompletionTokens { get; private set; }

    internal JsonArray Trace { get; }

    internal JsonArray Routes { get; }

    internal JsonObject? LastDecision { get; private set; }

    internal JsonObject? LastNativeReceipt { get; private set; }

    /// <summary>The decision number the next model request is asking for, counting prior decisions from the caller.</summary>
    internal int NextDecisionNumber => Decisions + 1;

    internal void RecordProviderFailure(string errorCode)
    {
        Decisions++;
        Routes.Add(new JsonObject
        {
            ["decision"] = Decisions,
            ["requestedModelId"] = _provider.ModelId,
            ["status"] = "provider-failure-before-decision",
            ["failureCode"] = errorCode,
            ["nativeActionSent"] = false
        });
    }

    internal void RecordDecision(ProviderDecisionResult result)
    {
        Decisions++;
        PromptTokens += result.PromptTokens ?? 0;
        CompletionTokens += result.CompletionTokens ?? 0;
        Routes.Add(new JsonObject
        {
            ["decision"] = Decisions,
            ["requestedModelId"] = _provider.ModelId,
            ["responseModelId"] = result.ModelId,
            ["routedVia"] = result.RoutedVia,
            ["responseFormatMode"] = result.ResponseFormatMode,
            ["promptTokens"] = result.PromptTokens,
            ["completionTokens"] = result.CompletionTokens
        });
    }

    /// <summary>Records the decision the scenario refused to send to Native, so the receipt still names it.</summary>
    internal void RecordDecisionRejection(JsonObject decision)
    {
        LastDecision = decision.DeepClone() as JsonObject;
    }

    /// <summary>Records the decision that produced a Native receipt, together with that receipt.</summary>
    internal void RecordNativeReceipt(JsonObject decision, JsonObject receipt)
    {
        LastDecision = decision.DeepClone() as JsonObject;
        LastNativeReceipt = receipt.DeepClone() as JsonObject;
    }

    /// <summary>
    /// Records an action whose outcome is unknown (a Native timeout). The receipt keeps the ambiguity instead
    /// of claiming completion, because the Host must not replay it.
    /// </summary>
    internal void RecordAmbiguousNativeAction(JsonObject decision, string action, string errorCode)
    {
        LastDecision = decision.DeepClone() as JsonObject;
        LastNativeReceipt = new JsonObject
        {
            ["action"] = action,
            ["status"] = "timeout-ambiguous",
            ["error"] = errorCode
        };
    }
}
