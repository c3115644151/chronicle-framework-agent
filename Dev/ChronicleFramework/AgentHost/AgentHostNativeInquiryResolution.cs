using System.Text.Json;
using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal static class AgentHostNativeInquiryResolution
{
    internal static IReadOnlyList<object> RunContractSelfTests()
    {
        var results = new List<object>();
        var native = new FakeNativeInquiryClient();
        var provider = new FakeDecisionProvider("affirmative");
        var resolved = RunAsync(native, native, provider, CancellationToken.None, "inquiry-selftest").GetAwaiter().GetResult();
        if (ReadString(resolved, "status") != "resolved" || ReadBoolean(resolved, "inquiryStillOpen") ||
            ReadInt(resolved, "decisions", 0) != 1 || ReadInt(resolved, "actionsExecuted", 0) != 1 ||
            native.LastChoice != "affirmative" || native.LastToken != "inquiry-token-1" ||
            provider.LastRequest?["allowedChoices"] is not JsonArray choices || choices.Count != 1 || choices[0]?.GetValue<string>() != "affirmative" ||
            provider.LastRequest?["observation"]?["state"]?["context"]?["inquiry"]?["token"] is not null)
            throw new AgentHostException("native-inquiry-resolution-selftest-failed", "The resolver must show only current enabled Native choices, bind the token internally, and verify the modal closed after the model's choice.");
        results.Add(new { scenario = "native-map-inquiry-is-resolved-only-by-a-model-choice-from-current-visible-enabled-buttons", passed = true });

        var invalidNative = new FakeNativeInquiryClient();
        var invalidProvider = new FakeDecisionProvider("negative");
        var invalidChoice = RunAsync(invalidNative, invalidNative, invalidProvider, CancellationToken.None, "inquiry-selftest-invalid").GetAwaiter().GetResult();
        if (ReadString(invalidChoice, "status") != "failed" || ReadString(invalidChoice, "failureCode") != "native-inquiry-choice-not-currently-enabled" ||
            ReadInt(invalidChoice, "actionsExecuted", 0) != 0 || invalidNative.LastChoice is not null)
            throw new AgentHostException("native-inquiry-invalid-choice-selftest-failed", "The resolver must reject a model choice hidden or disabled by the currently displayed Native prompt before sending a command.");
        results.Add(new { scenario = "native-inquiry-resolver-rejects-a-choice-not-shown-or-enabled", passed = true });

        var unsupportedNative = new FakeNativeInquiryClient(supported: false);
        var unsupportedProvider = new FakeDecisionProvider("affirmative");
        var unsupported = RunAsync(unsupportedNative, unsupportedNative, unsupportedProvider, CancellationToken.None, "inquiry-selftest-unsupported").GetAwaiter().GetResult();
        if (ReadString(unsupported, "status") != "failed" || ReadString(unsupported, "failureCode") != "native-inquiry-kind-unsupported" ||
            unsupportedProvider.CallCount != 0 || unsupportedNative.LastChoice is not null)
            throw new AgentHostException("native-inquiry-unsupported-selftest-failed", "Unsupported Native modal types must fail closed without a model request or Native response.");
        results.Add(new { scenario = "native-inquiry-resolver-fails-closed-for-unsupported-modal-types", passed = true });
        return results;
    }

    internal static async Task<JsonObject> RunAsync(
        IAgentHostCampaignNativeClient stateClient,
        IAgentHostNativeInquiryClient inquiryClient,
        IAgentHostDecisionProvider provider,
        CancellationToken cancellationToken,
        string runId)
    {
        using var current = await stateClient.ReadStateAsync(cancellationToken);
        var currentRoot = JsonNode.Parse(current.RootElement.GetRawText()) as JsonObject;
        var state = currentRoot?["state"] as JsonObject;
        var context = state?["context"] as JsonObject;
        if (!ReadBoolean(context, "inquiryOpen"))
            return new JsonObject { ["status"] = "no-active-inquiry", ["decisions"] = 0, ["actionsExecuted"] = 0 };

        var inquiry = context?["inquiry"] as JsonObject;
        if (ReadString(context, "gameState") != "MapState" ||
            inquiry is null || !ReadBoolean(inquiry, "supported") || ReadString(inquiry, "kind") != "YesNoInquiry")
            return Failure("native-inquiry-kind-unsupported", "The current Native prompt is not a supported Campaign Map Yes/No Inquiry.");

        var token = ReadString(inquiry, "token");
        if (string.IsNullOrWhiteSpace(token))
            return Failure("native-inquiry-token-missing", "The active Native Inquiry has no current anti-stale token.");

        var allowedChoices = new JsonArray();
        foreach (var choice in new[] { "affirmative", "negative" })
        {
            if (IsChoiceEnabled(inquiry, choice)) allowedChoices.Add(choice);
        }
        if (allowedChoices.Count == 0)
            return Failure("native-inquiry-has-no-enabled-choice", "The current Native Inquiry exposes no shown and enabled response.");

        var visibleInquiry = inquiry.DeepClone() as JsonObject ?? new JsonObject();
        visibleInquiry.Remove("token");
        var request = new JsonObject
        {
            ["schemaVersion"] = 1,
            ["runId"] = runId,
            ["observation"] = new JsonObject
            {
                ["scope"] = "one-current-native-map-inquiry",
                ["state"] = new JsonObject
                {
                    ["context"] = new JsonObject
                    {
                        ["gameState"] = "MapState",
                        ["inquiryOpen"] = true,
                        ["inquiry"] = visibleInquiry
                    }
                }
            },
            ["allowedChoices"] = allowedChoices.DeepClone()
        };

        var decision = await AgentHostDecisionCycle.DecideNativeInquiryResponseAsync(provider, request, cancellationToken);
        using (var requestDocument = JsonDocument.Parse(request.ToJsonString()))
            AgentHostHarnessProgressTrace.RecordDecision(requestDocument.RootElement, decision);

        var selectedChoice = ReadString(decision.Decision, "choice");
        if (selectedChoice is not ("affirmative" or "negative") || !allowedChoices.Any(node => node?.GetValue<string>() == selectedChoice))
            return new JsonObject
            {
                ["status"] = "failed",
                ["failureCode"] = "native-inquiry-choice-not-currently-enabled",
                ["failure"] = "The model did not choose a response currently shown and enabled by the Native Inquiry.",
                ["decisions"] = 1,
                ["actionsExecuted"] = 0,
                ["promptTokens"] = decision.PromptTokens ?? 0,
                ["completionTokens"] = decision.CompletionTokens ?? 0,
                ["decision"] = decision.Decision.DeepClone(),
                ["providerRoute"] = BuildProviderRoute(decision)
            };

        using var nativeReceiptDocument = await inquiryClient.RespondNativeInquiryAsync(token, selectedChoice, cancellationToken);
        var nativeReceipt = JsonNode.Parse(nativeReceiptDocument.RootElement.GetRawText()) as JsonObject ?? new JsonObject();
        using var after = await stateClient.ReadStateAsync(cancellationToken);
        var afterState = after.RootElement.TryGetProperty("state", out var afterStateElement) && afterStateElement.ValueKind == JsonValueKind.Object
            ? JsonNode.Parse(afterStateElement.GetRawText()) as JsonObject
            : null;
        var afterContext = afterState?["context"] as JsonObject;
        var stillOpen = ReadBoolean(afterContext, "inquiryOpen");
        var nativeCompleted = ReadString(nativeReceipt, "status") == "completed";
        return new JsonObject
        {
            ["status"] = nativeCompleted && !stillOpen ? "resolved" : "failed",
            ["failureCode"] = nativeCompleted && !stillOpen ? null : "native-inquiry-transition-unverified",
            ["failure"] = nativeCompleted && !stillOpen ? null : "The selected Native Inquiry handler did not leave a verified unblocked MapState.",
            ["decisions"] = 1,
            ["actionsExecuted"] = nativeCompleted ? 1 : 0,
            ["promptTokens"] = decision.PromptTokens ?? 0,
            ["completionTokens"] = decision.CompletionTokens ?? 0,
            ["inquiryStillOpen"] = stillOpen,
            ["choice"] = selectedChoice,
            ["decision"] = decision.Decision.DeepClone(),
            ["providerRoute"] = BuildProviderRoute(decision),
            ["nativeReceipt"] = nativeReceipt,
            ["nativeStateAfter"] = AgentHostHarnessProgressTrace.BuildNativeStateSummary(JsonNode.Parse(after.RootElement.GetRawText()) as JsonObject)
        };
    }

    private static JsonObject Failure(string code, string message) => new()
    {
        ["status"] = "failed", ["failureCode"] = code, ["failure"] = message,
        ["decisions"] = 0, ["actionsExecuted"] = 0
    };

    private static bool IsChoiceEnabled(JsonObject inquiry, string choice)
    {
        var option = inquiry[choice] as JsonObject;
        return ReadBoolean(option, "visible") && ReadBoolean(option, "enabled");
    }

    private static JsonObject BuildProviderRoute(ProviderDecisionResult result) => new()
    {
        ["requestedModelId"] = result.ModelId,
        ["responseModelId"] = result.ModelId,
        ["routedVia"] = result.RoutedVia,
        ["responseFormatMode"] = result.ResponseFormatMode,
        ["promptTokens"] = result.PromptTokens,
        ["completionTokens"] = result.CompletionTokens
    };

    private static string? ReadString(JsonObject? value, string name) =>
        value?[name] is JsonValue node && node.TryGetValue<string>(out var result) ? result : null;

    private static bool ReadBoolean(JsonObject? value, string name) =>
        value?[name] is JsonValue node && node.TryGetValue<bool>(out var result) && result;

    private static int ReadInt(JsonObject? value, string name, int fallback) =>
        value?[name] is JsonValue node && node.TryGetValue<int>(out var result) ? result : fallback;

    private sealed class FakeNativeInquiryClient(bool supported = true) : IAgentHostCampaignNativeClient, IAgentHostNativeInquiryClient
    {
        private bool _open = true;
        internal string? LastToken { get; private set; }
        internal string? LastChoice { get; private set; }

        public Task<JsonDocument> ReadStateAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var context = new JsonObject
            {
                ["gameState"] = "MapState",
                ["inquiryOpen"] = _open,
                ["inquiry"] = _open ? new JsonObject
                {
                    ["supported"] = supported,
                    ["kind"] = supported ? "YesNoInquiry" : "TextInquiry",
                    ["token"] = "inquiry-token-1",
                    ["title"] = "通知",
                    ["text"] = "原版游戏内容",
                    ["affirmative"] = new JsonObject { ["visible"] = true, ["enabled"] = true, ["text"] = "好" },
                    ["negative"] = new JsonObject { ["visible"] = false, ["enabled"] = false, ["text"] = "" }
                } : null
            };
            return Task.FromResult(JsonDocument.Parse(new JsonObject { ["status"] = "completed", ["state"] = new JsonObject { ["context"] = context } }.ToJsonString()));
        }

        public Task<JsonDocument> ExecuteCampaignActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken) =>
            throw new AgentHostException("native-inquiry-selftest-unexpected-action", "The Native Inquiry resolver must not use ordinary Campaign actions.");

        public Task<JsonDocument> RespondNativeInquiryAsync(string token, string choice, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (!_open || token != "inquiry-token-1") throw new AgentHostException("native-inquiry-selftest-token-invalid", "The resolver did not bind the current active inquiry token.");
            LastToken = token;
            LastChoice = choice;
            _open = false;
            return Task.FromResult(JsonDocument.Parse("{\"status\":\"completed\",\"action\":\"respondInquiry\"}"));
        }
    }

    private sealed class FakeDecisionProvider(string choice) : IAgentHostDecisionProvider
    {
        internal int CallCount { get; private set; }
        internal JsonObject? LastRequest { get; private set; }
        public string ModelId => "native-inquiry-selftest-model";
        public string ConfigurationSource => "harness-fake-provider";
        public Task CheckConfiguredModelAsync(CancellationToken cancellationToken) => Task.CompletedTask;
        public Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            CallCount++;
            LastRequest = JsonNode.Parse(request.GetRawText()) as JsonObject;
            if (!systemPrompt.Contains("currently visible to the player", StringComparison.Ordinal))
                throw new AgentHostException("native-inquiry-selftest-prompt-invalid", "The resolver did not state that the prompt is the current player-visible Native inquiry.");
            return Task.FromResult(new ProviderDecisionResult("completed", ModelId, 12, 2, "self-test",
                new JsonObject { ["choice"] = choice, ["reason"] = "Current visible choice." }, "self-test", "json_schema"));
        }
        public void Dispose() { }
    }
}
