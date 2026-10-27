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
            ReadString(provider.LastRequest, "goal") is null ||
            provider.LastRequest?["allowedActions"] is not JsonArray allowedActions || allowedActions.Count != 1 ||
            ReadString(allowedActions[0] as JsonObject, "action") != "respondInquiry" ||
            provider.LastRequest?["observation"]?["state"]?["context"]?["inquiry"]?["token"] is not null)
            throw new AgentHostException("native-inquiry-resolution-selftest-failed", "The resolver must show only current enabled Native choices, bind the token internally, and verify the modal closed after the model's choice.");
        results.Add(new { scenario = "native-map-inquiry-is-resolved-only-by-a-model-choice-from-current-visible-enabled-buttons", passed = true });
        var trainingReturnRequest = BuildDecisionRequest("training-inquiry-selftest",
            new JsonObject { ["supported"] = true, ["kind"] = "YesNoInquiry", ["title"] = "", ["text"] = "Return the trained borrowed troops?" },
            new JsonArray("affirmative", "negative"),
            "Return the trained borrowed troops to the quest giver to finish the current Native training Issue.");
        if (ReadString(trainingReturnRequest, "goal") != "Return the trained borrowed troops to the quest giver to finish the current Native training Issue.")
            throw new AgentHostException("native-inquiry-contextual-goal-selftest-failed", "A subgoal-specific Native Yes/No inquiry must preserve the parent objective context while still offering only current Native choices.");
        results.Add(new { scenario = "native-inquiry-can-inherit-current-training-issue-goal", passed = true });

        var recoveringNative = new FakeNativeInquiryClient();
        var recoveringProvider = new FakeDecisionProvider("affirmative", failFirstCall: true);
        var recoveredInquiry = RunAsync(recoveringNative, recoveringNative, recoveringProvider, CancellationToken.None, "inquiry-selftest-provider-retry").GetAwaiter().GetResult();
        if (ReadString(recoveredInquiry, "status") != "resolved" || ReadInt(recoveredInquiry, "decisions", 0) != 2 ||
            ReadInt(recoveredInquiry, "actionsExecuted", 0) != 1 || recoveringProvider.CallCount != 2 ||
            recoveringNative.LastChoice != "affirmative" || recoveringNative.ResponsesReceived != 1 ||
            recoveredInquiry["providerRouteHistory"] is not JsonArray retryRoutes || retryRoutes.Count != 2)
            throw new AgentHostException("native-inquiry-provider-retry-selftest-failed", "A recoverable provider-format error must retry one visible Inquiry choice without submitting more than one Native response.");
        results.Add(new { scenario = "native-inquiry-retries-one-recoverable-provider-error-without-duplicating-native-response", passed = true });

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

        var clanNameNative = new FakeStoryModeClanNameInquiryClient();
        var clanNameProvider = new FakeStoryModeClanNameProvider();
        var clanName = RunAsync(clanNameNative, clanNameNative, clanNameProvider, CancellationToken.None, "storymode-name-selftest").GetAwaiter().GetResult();
        if (ReadString(clanName, "status") != "resolved" || ReadBoolean(clanName, "bannerEditorEntered") != true ||
            ReadInt(clanName, "decisions", 0) != 1 || ReadInt(clanName, "actionsExecuted", 0) != 1 ||
            clanNameNative.SubmittedName != "Chronicle Wolves" || clanNameProvider.LastRequest?[
                "observation"]?["state"]?["context"]?["inquiry"]?["token"] is not null ||
            ReadString(clanNameProvider.LastRequest, "goal") is null ||
            ReadString((clanNameProvider.LastRequest?["allowedActions"] as JsonArray)?[0] as JsonObject, "action") != "submitStoryModeClanName")
            throw new AgentHostException("storymode-clan-name-resolution-selftest-failed", "The family-name TextInquiry resolver must use the normal model decision envelope, keep the Native token hidden, submit text through the Native handler and verify BannerEditorState.");
        results.Add(new { scenario = "storymode-family-name-text-inquiry-uses-model-text-and-native-handler-before-banner-editor", passed = true });

        var recoveringClanNameNative = new FakeStoryModeClanNameInquiryClient();
        var recoveringClanNameProvider = new FakeStoryModeClanNameProvider(failFirstCall: true);
        var recoveredClanName = RunAsync(recoveringClanNameNative, recoveringClanNameNative, recoveringClanNameProvider, CancellationToken.None, "storymode-name-provider-retry-selftest").GetAwaiter().GetResult();
        if (ReadString(recoveredClanName, "status") != "resolved" || ReadInt(recoveredClanName, "decisions", 0) != 2 ||
            ReadInt(recoveredClanName, "actionsExecuted", 0) != 1 || recoveringClanNameProvider.CallCount != 2 ||
            recoveringClanNameNative.SubmittedName != "Chronicle Wolves" ||
            recoveredClanName["providerRouteHistory"] is not JsonArray clanNameRetryRoutes || clanNameRetryRoutes.Count != 2)
            throw new AgentHostException("storymode-clan-name-provider-retry-selftest-failed", "A recoverable provider-format error must retry the current family-name prompt and invoke the Native text handler only once.");
        results.Add(new { scenario = "storymode-family-name-inquiry-retries-one-recoverable-provider-error-before-native-submit", passed = true });
        return results;
    }

    internal static async Task<JsonObject> RunAsync(
        IAgentHostCampaignNativeClient stateClient,
        IAgentHostNativeInquiryClient inquiryClient,
        IAgentHostDecisionProvider provider,
        CancellationToken cancellationToken,
        string runId,
        string? goal = null)
    {
        using var current = await stateClient.ReadStateAsync(cancellationToken);
        var currentRoot = JsonNode.Parse(current.RootElement.GetRawText()) as JsonObject;
        var state = currentRoot?["state"] as JsonObject;
        var context = state?["context"] as JsonObject;
        if (!ReadBoolean(context, "inquiryOpen"))
            return new JsonObject { ["status"] = "no-active-inquiry", ["decisions"] = 0, ["actionsExecuted"] = 0 };

        var inquiry = context?["inquiry"] as JsonObject;
        var gameState = ReadString(context, "gameState");
        if (gameState != "MapState" || inquiry is null || !ReadBoolean(inquiry, "supported"))
            return Failure("native-inquiry-kind-unsupported", "The current Native prompt is not a supported Campaign Map Yes/No Inquiry.");

        if (ReadString(inquiry, "kind") == "StoryModeClanNameTextInquiry")
            return await RunStoryModeClanNameAsync(stateClient, inquiryClient, provider, runId, inquiry, cancellationToken);
        if (ReadString(inquiry, "kind") != "YesNoInquiry")
            return Failure("native-inquiry-kind-unsupported", "The current Native prompt is not a supported Campaign Map Yes/No Inquiry or StoryMode family-name TextInquiry.");

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
        var request = BuildDecisionRequest(runId, visibleInquiry, allowedChoices, goal);
        var providerRoutes = new JsonArray();
        var decision = await AgentHostProviderDecisionRecovery.DecideWithSingleRetryAsync(request,
            token => AgentHostDecisionCycle.DecideNativeInquiryResponseAsync(provider, request, token),
            code => providerRoutes.Add(new JsonObject
            {
                ["requestedModelId"] = provider.ModelId,
                ["status"] = "provider-failure-before-decision",
                ["failureCode"] = code,
                ["nativeActionSent"] = false,
                ["tokenUsageAvailable"] = false
            }), cancellationToken);
        providerRoutes.Add(BuildProviderRoute(decision));
        using (var requestDocument = JsonDocument.Parse(request.ToJsonString()))
            AgentHostHarnessProgressTrace.RecordDecision(requestDocument.RootElement, decision);

        var actionName = ReadString(decision.Decision, "action");
        var decisionArguments = decision.Decision["arguments"] as JsonObject;
        var selectedChoice = ReadString(decisionArguments, "choice");
        if (actionName != "respondInquiry" || selectedChoice is not ("affirmative" or "negative") ||
            !allowedChoices.Any(node => node?.GetValue<string>() == selectedChoice))
            return new JsonObject
            {
                ["status"] = "failed",
                ["failureCode"] = "native-inquiry-choice-not-currently-enabled",
                ["failure"] = "The model did not choose the current respondInquiry action and a response shown and enabled by the Native Inquiry.",
                ["decisions"] = providerRoutes.Count,
                ["actionsExecuted"] = 0,
                ["promptTokens"] = decision.PromptTokens ?? 0,
                ["completionTokens"] = decision.CompletionTokens ?? 0,
                ["decision"] = decision.Decision.DeepClone(),
                ["providerRoute"] = BuildProviderRoute(decision),
                ["providerRouteHistory"] = providerRoutes
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
            ["decisions"] = providerRoutes.Count,
            ["actionsExecuted"] = nativeCompleted ? 1 : 0,
            ["promptTokens"] = decision.PromptTokens ?? 0,
            ["completionTokens"] = decision.CompletionTokens ?? 0,
            ["inquiryStillOpen"] = stillOpen,
            ["choice"] = selectedChoice,
            ["decision"] = decision.Decision.DeepClone(),
            ["providerRoute"] = BuildProviderRoute(decision),
            ["providerRouteHistory"] = providerRoutes,
            ["nativeReceipt"] = nativeReceipt,
            ["nativeStateAfter"] = AgentHostHarnessProgressTrace.BuildNativeStateSummary(JsonNode.Parse(after.RootElement.GetRawText()) as JsonObject)
        };
    }

    private static async Task<JsonObject> RunStoryModeClanNameAsync(
        IAgentHostCampaignNativeClient stateClient,
        IAgentHostNativeInquiryClient inquiryClient,
        IAgentHostDecisionProvider provider,
        string runId,
        JsonObject inquiry,
        CancellationToken cancellationToken)
    {
        var token = ReadString(inquiry, "token");
        if (string.IsNullOrWhiteSpace(token))
            return Failure("storymode-clan-name-token-missing", "The active Native family-name prompt has no current anti-stale token.");
        var visibleInquiry = inquiry.DeepClone() as JsonObject ?? new JsonObject();
        visibleInquiry.Remove("token");
        var request = BuildStoryModeClanNameDecisionRequest(runId, visibleInquiry);
        var providerRoutes = new JsonArray();
        var decision = await AgentHostProviderDecisionRecovery.DecideWithSingleRetryAsync(request,
            token => AgentHostDecisionCycle.DecideStoryModeClanNameAsync(provider, request, token),
            code => providerRoutes.Add(new JsonObject
            {
                ["requestedModelId"] = provider.ModelId,
                ["status"] = "provider-failure-before-decision",
                ["failureCode"] = code,
                ["nativeActionSent"] = false,
                ["tokenUsageAvailable"] = false
            }), cancellationToken);
        providerRoutes.Add(BuildProviderRoute(decision));
        using (var requestDocument = JsonDocument.Parse(request.ToJsonString()))
            AgentHostHarnessProgressTrace.RecordDecision(requestDocument.RootElement, decision);

        var arguments = decision.Decision["arguments"] as JsonObject;
        var clanName = ReadString(arguments, "text");
        if (ReadString(decision.Decision, "action") != "submitStoryModeClanName" || string.IsNullOrWhiteSpace(clanName) || clanName.Length > 64)
            return new JsonObject
            {
                ["status"] = "failed", ["failureCode"] = "storymode-clan-name-decision-invalid",
                ["failure"] = "The model did not return one nonblank, bounded current clan-name submission.",
                ["decisions"] = providerRoutes.Count, ["actionsExecuted"] = 0,
                ["promptTokens"] = decision.PromptTokens ?? 0, ["completionTokens"] = decision.CompletionTokens ?? 0,
                ["decision"] = decision.Decision.DeepClone(), ["providerRoute"] = BuildProviderRoute(decision),
                ["providerRouteHistory"] = providerRoutes
            };

        using var receiptDocument = await inquiryClient.SubmitStoryModeClanNameAsync(token, clanName, cancellationToken);
        var receipt = JsonNode.Parse(receiptDocument.RootElement.GetRawText()) as JsonObject ?? new JsonObject();
        using var after = await stateClient.ReadStateAsync(cancellationToken);
        var afterRoot = JsonNode.Parse(after.RootElement.GetRawText()) as JsonObject;
        var afterState = afterRoot?["state"] as JsonObject;
        var afterContext = afterState?["context"] as JsonObject;
        var enteredBannerEditor = ReadString(afterContext, "gameState") == "BannerEditorState" &&
                                  !ReadBoolean(afterContext, "inquiryOpen") &&
                                  ReadBoolean(afterContext?["bannerEditor"] as JsonObject, "supported");
        var completed = ReadString(receipt, "status") == "completed" && enteredBannerEditor;
        return new JsonObject
        {
            ["status"] = completed ? "resolved" : "failed",
            ["failureCode"] = completed ? null : "storymode-clan-name-transition-unverified",
            ["failure"] = completed ? null : "The Native family-name handler did not transition to the verified player BannerEditorState.",
            ["decisions"] = providerRoutes.Count, ["actionsExecuted"] = ReadString(receipt, "status") == "completed" ? 1 : 0,
            ["promptTokens"] = decision.PromptTokens ?? 0, ["completionTokens"] = decision.CompletionTokens ?? 0,
            ["storyModeSetupStage"] = "family-name",
            ["clanName"] = clanName,
            ["bannerEditorEntered"] = enteredBannerEditor,
            ["decision"] = decision.Decision.DeepClone(),
            ["providerRoute"] = BuildProviderRoute(decision),
            ["providerRouteHistory"] = providerRoutes,
            ["nativeReceipt"] = receipt,
            ["nativeStateAfter"] = AgentHostHarnessProgressTrace.BuildNativeStateSummary(afterRoot)
        };
    }

    internal static JsonObject BuildStoryModeClanNameDecisionRequest(string runId, JsonObject visibleInquiry) => new()
    {
        ["schemaVersion"] = 1,
        ["runId"] = runId,
        ["goal"] = "Choose and submit a valid Native family name to continue the current StoryMode setup.",
        ["observation"] = new JsonObject
        {
            ["scope"] = "storymode-player-clan-name-setup",
            ["state"] = new JsonObject
            {
                ["context"] = new JsonObject
                {
                    ["gameState"] = "MapState",
                    ["inquiryOpen"] = true,
                    ["inquiry"] = visibleInquiry.DeepClone()
                }
            }
        },
        ["allowedActions"] = new JsonArray
        {
            new JsonObject
            {
                ["action"] = "submitStoryModeClanName",
                ["arguments"] = new JsonArray("text"),
                ["textConstraints"] = new JsonObject { ["minLength"] = 1, ["maxLength"] = 64, ["nativeValidation"] = true }
            }
        },
        ["allowedControls"] = new JsonArray("done")
    };

    private sealed class FakeStoryModeClanNameInquiryClient : IAgentHostCampaignNativeClient, IAgentHostNativeInquiryClient
    {
        private bool _inquiryOpen = true;
        private bool _bannerEditor;
        internal string? SubmittedName { get; private set; }

        public Task<JsonDocument> ReadStateAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var context = new JsonObject
            {
                ["gameState"] = _bannerEditor ? "BannerEditorState" : "MapState",
                ["inquiryOpen"] = _inquiryOpen,
                ["inquiry"] = _inquiryOpen ? new JsonObject
                {
                    ["supported"] = true, ["kind"] = "StoryModeClanNameTextInquiry", ["token"] = "clan-name-token",
                    ["title"] = "Select your family name:", ["text"] = "", ["defaultInputText"] = "Clan",
                    ["inputText"] = "Clan", ["affirmativeText"] = "Done", ["affirmativeVisible"] = true,
                    ["affirmativeEnabled"] = true, ["negativeVisible"] = false, ["inputObfuscated"] = false
                } : null,
                ["bannerEditor"] = _bannerEditor ? new JsonObject { ["active"] = true, ["supported"] = true } : new JsonObject { ["active"] = false }
            };
            return Task.FromResult(JsonDocument.Parse(new JsonObject { ["status"] = "completed", ["state"] = new JsonObject { ["context"] = context } }.ToJsonString()));
        }

        public Task<JsonDocument> ExecuteCampaignActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken) =>
            throw new AgentHostException("storymode-name-selftest-unexpected-campaign-action", "The clan-name resolver must not use a generic Campaign action.");

        public Task<JsonDocument> RespondNativeInquiryAsync(string token, string choice, CancellationToken cancellationToken) =>
            throw new AgentHostException("storymode-name-selftest-unexpected-choice", "The clan-name resolver must not treat a text input as a Yes/No choice.");

        public Task<JsonDocument> SubmitStoryModeClanNameAsync(string token, string clanName, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (!_inquiryOpen || token != "clan-name-token" || string.IsNullOrWhiteSpace(clanName))
                throw new AgentHostException("storymode-name-selftest-token-invalid", "The Native clan-name submission did not bind the current TextInquiry and text.");
            SubmittedName = clanName;
            _inquiryOpen = false;
            _bannerEditor = true;
            return Task.FromResult(JsonDocument.Parse("{\"status\":\"completed\",\"nativeViewModelHandler\":\"TextQueryPopUpVM.ExecuteAffirmativeAction\"}"));
        }
    }

    private sealed class FakeStoryModeClanNameProvider(bool failFirstCall = false) : IAgentHostDecisionProvider
    {
        internal JsonObject? LastRequest { get; private set; }
        internal int CallCount { get; private set; }
        public string ModelId => "storymode-clan-name-selftest-model";
        public string ConfigurationSource => "harness-fake-provider";
        public Task CheckConfiguredModelAsync(CancellationToken cancellationToken) => Task.CompletedTask;

        public Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            CallCount++;
            LastRequest = JsonNode.Parse(request.GetRawText()) as JsonObject;
            if (!systemPrompt.Contains("family name", StringComparison.Ordinal))
                throw new AgentHostException("storymode-name-selftest-prompt-invalid", "The name-specific Native text prompt was not used.");
            if (failFirstCall && CallCount == 1)
                throw new AgentHostException("provider-decision-field-unavailable", "The fake provider emitted one unsupported name field before correction.");
            return Task.FromResult(new ProviderDecisionResult("completed", ModelId, 15, 3, "self-test",
                new JsonObject { ["action"] = "submitStoryModeClanName", ["arguments"] = new JsonObject { ["text"] = "Chronicle Wolves" }, ["rationale"] = "A concise in-world family name." }, "self-test", "json_schema"));
        }

        public void Dispose() { }
    }

    internal static JsonObject BuildDecisionRequest(string runId, JsonObject visibleInquiry, JsonArray allowedChoices, string? goal = null)
    {
        return new JsonObject
        {
            ["schemaVersion"] = 1,
            ["runId"] = runId,
            ["goal"] = string.IsNullOrWhiteSpace(goal)
                ? "Respond to the one current Native Bannerlord Map inquiry using only a currently visible and enabled choice."
                : goal,
            ["observation"] = new JsonObject
            {
                ["scope"] = "one-current-native-map-inquiry",
                ["state"] = new JsonObject
                {
                    ["context"] = new JsonObject
                    {
                        ["gameState"] = "MapState",
                        ["inquiryOpen"] = true,
                        ["inquiry"] = visibleInquiry.DeepClone()
                    }
                }
            },
            ["allowedActions"] = new JsonArray
            {
                new JsonObject
                {
                    ["action"] = "respondInquiry",
                    ["arguments"] = new JsonArray("choice"),
                    ["argumentValues"] = new JsonObject { ["choice"] = allowedChoices.DeepClone() }
                }
            },
            ["allowedControls"] = new JsonArray("done"),
            ["allowedChoices"] = allowedChoices.DeepClone()
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
        internal int ResponsesReceived { get; private set; }

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
            ResponsesReceived++;
            _open = false;
            return Task.FromResult(JsonDocument.Parse("{\"status\":\"completed\",\"action\":\"respondInquiry\"}"));
        }

        public Task<JsonDocument> SubmitStoryModeClanNameAsync(string token, string clanName, CancellationToken cancellationToken) =>
            throw new AgentHostException("native-inquiry-selftest-unexpected-clan-name", "The yes/no inquiry fixture does not accept a clan-name submission.");
    }

    private sealed class FakeDecisionProvider(string choice, bool failFirstCall = false) : IAgentHostDecisionProvider
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
            if (failFirstCall && CallCount == 1)
                throw new AgentHostException("provider-response-truncated", "The fake provider returned one truncated Native Inquiry decision.");
            return Task.FromResult(new ProviderDecisionResult("completed", ModelId, 12, 2, "self-test",
                new JsonObject { ["action"] = "respondInquiry", ["arguments"] = new JsonObject { ["choice"] = choice }, ["rationale"] = "Current visible choice." }, "self-test", "json_schema"));
        }
        public void Dispose() { }
    }
}
