using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal static class AgentHostStoryModeSetupLoop
{
    private const int MaxDecisions = 8;

    internal static async Task<IReadOnlyList<object>> RunContractSelfTestsAsync()
    {
        var native = new FakeStoryModeSetupNativeClient(delayNotificationReady: true);
        var provider = new FakeStoryModeSetupDecisionProvider();
        using var request = JsonDocument.Parse("{\"runId\":\"storymode-post-tutorial-setup-selftest\",\"goal\":\"Complete original family name and banner setup.\"}");
        var result = await RunAsync(request.RootElement, native, native, native, provider, new DecisionRunLedger(provider, null), CancellationToken.None);
        var expected = new[] { "respondInquiry", "continueSceneNotification", "submitStoryModeClanName", "bannerEditorDone", "respondInquiry" };
        if (ReadString(result, "status") != "completed" ||
            ReadString(result["termination"] as JsonObject, "reason") != "storymode-post-tutorial-setup-returned-to-map" ||
            ReadInt(result, "decisions", 0) != expected.Length || ReadInt(result, "actionsExecuted", 0) != expected.Length ||
            provider.CallCount != expected.Length || native.Actions.Count != expected.Length ||
            !native.Actions.SequenceEqual(expected, StringComparer.Ordinal) || native.SubmittedClanName != "Chronicle Wolves")
            throw new AgentHostException("storymode-setup-loop-selftest-failed", "The Native startup chain must continue the verified banner notification, use TextQueryPopUpVM for a model-selected family name, commit the current BannerEditor through Done, answer the resulting tutorial inquiry, and return to Map. status=" + ReadString(result, "status") + "; actions=" + string.Join(",", native.Actions) + "; decisions=" + provider.CallCount);
        var recoveringNative = new FakeStoryModeSetupNativeClient();
        var recoveringProvider = new FakeStoryModeSetupDecisionProvider(failOnCall: 2);
        var recoveredResult = await RunAsync(request.RootElement, recoveringNative, recoveringNative, recoveringNative, recoveringProvider, new DecisionRunLedger(recoveringProvider, null), CancellationToken.None);
        if (ReadString(recoveredResult, "status") != "completed" ||
            ReadString(recoveredResult["termination"] as JsonObject, "reason") != "storymode-post-tutorial-setup-returned-to-map" ||
            ReadInt(recoveredResult, "decisions", 0) != expected.Length + 1 || recoveringProvider.CallCount != expected.Length + 1 ||
            recoveringNative.Actions.Count != expected.Length || !recoveringNative.Actions.SequenceEqual(expected, StringComparer.Ordinal) ||
            (recoveredResult["trace"] as JsonArray)?.OfType<JsonObject>().All(step => ReadString(step, "stage") != "storymode-setup-provider-retry") == true)
            throw new AgentHostException("storymode-setup-provider-retry-selftest-failed", "One recoverable malformed provider response must be corrected with a bounded no-action retry, then the original Native setup chain must still complete exactly once.");
        return
        [
            new { scenario = "storymode-post-tutorial-native-notification-family-name-banner-editor-and-follow-up-inquiry-loop", decisions = provider.CallCount, nativeActions = native.Actions.ToArray(), passed = true },
            new { scenario = "storymode-setup-recovers-one-provider-format-error-without-replaying-native-actions", decisions = recoveringProvider.CallCount, nativeActions = recoveringNative.Actions.ToArray(), passed = true },
            new { scenario = "storymode-setup-waits-for-scene-notification-native-readiness-without-spending-model-call", readinessPolls = native.NotificationReadinessPolls, passed = native.NotificationReadinessPolls == 2 }
        ];
    }

    internal static async Task<JsonObject> RunAsync(
        JsonElement request,
        IAgentHostCampaignNativeClient stateClient,
        IAgentHostNativeInquiryClient inquiryClient,
        IAgentHostStoryModeBannerEditorNativeClient bannerEditorClient,
        IAgentHostDecisionProvider provider,
        DecisionRunLedger ledger,
        CancellationToken cancellationToken)
    {
        var runId = ReadString(request, "runId") ?? Guid.NewGuid().ToString("N");
        var actions = 0;
        var started = false;

        try
        {
            for (var step = 0; step < MaxDecisions; step++)
            {
                cancellationToken.ThrowIfCancellationRequested();
                using var current = await stateClient.ReadStateAsync(cancellationToken);
                var root = JsonNode.Parse(current.RootElement.GetRawText()) as JsonObject;
                var state = root?["state"] as JsonObject;
                var context = state?["context"] as JsonObject;
                if (state == null || context == null)
                    return Result(started ? "failed" : "not-needed", started ? "storymode-setup-state-unavailable" : "no-storymode-setup-ui", "Native state/context is unavailable for StoryMode setup.");

                var gameState = ReadString(context, "gameState");
                var scene = context["sceneNotification"] as JsonObject;
                if (ReadBoolean(scene, "hasActiveNotification"))
                {
                    if (ReadString(scene, "dataType") != "FindingFirstBannerPieceSceneNotificationItem" ||
                        ReadString(scene, "continuationKind") != "storymode-clan-name-setup")
                    {
                        if (!started) return Result("not-needed", "scene-notification-outside-storymode-setup", null);
                        return Result("failed", "storymode-setup-scene-notification-unsupported", "A different or unsafe Native scene notification interrupted StoryMode setup.");
                    }

                    started = true;
                    if (!ReadBoolean(scene, "isReady") || !ReadBoolean(scene, "canContinue"))
                    {
                        // Native loads/shows this Campaign callback-backed scene card
                        // asynchronously. A current exact StoryMode card that is not yet
                        // ready is a transition, not an unsupported modal or an LLM decision.
                        await Task.Delay(TimeSpan.FromMilliseconds(250), cancellationToken);
                        continue;
                    }

                    var observation = new JsonObject
                    {
                        ["scope"] = "original-storymode-post-tutorial-setup",
                        ["state"] = state.DeepClone(),
                        ["stage"] = "first-banner-notification"
                    };
                    var modelRequest = BuildActionRequest(runId, ledger.NextDecisionNumber,
                        "Complete the current Native StoryMode first-banner notification and continue the original setup.",
                        observation, new JsonObject { ["action"] = "continueSceneNotification", ["arguments"] = new JsonArray() });
                    var decision = await DecideWithRecoveryAsync(
                        token => AgentHostDecisionCycle.DecideStoryModeSceneNotificationAsync(provider, modelRequest, token), modelRequest);
                    ledger.RecordDecision(decision);
                    var chosen = ReadString(decision.Decision, "action");
                    if (chosen != "continueSceneNotification" || HasArguments(decision.Decision))
                        return Result("failed", "storymode-scene-notification-decision-invalid", "The model did not choose the current Native notification continuation action.", decision.Decision);

                    using var receiptDocument = await stateClient.ExecuteCampaignActionAsync("continueSceneNotification", new JsonObject(), cancellationToken);
                    var receipt = JsonNode.Parse(receiptDocument.RootElement.GetRawText()) as JsonObject ?? new JsonObject();
                    if (ReadString(receipt, "status") != "completed")
                        return Result("failed", "storymode-scene-notification-native-close-failed", "The Native SceneNotification close handler did not complete.", decision.Decision, receipt);
                    actions++;
                    AddTrace("scene-notification-continued", decision, receipt, observation);
                    continue;
                }

                if (ReadBoolean(context, "inquiryOpen"))
                {
                    var inquiry = context["inquiry"] as JsonObject;
                    var kind = ReadString(inquiry, "kind");
                    var relevantName = kind == "StoryModeClanNameTextInquiry";
                    var relevantStoryQuery = kind == "YesNoInquiry" && ReadString(inquiry, "storyModeStartupKind") is "tutorial-skip-notification" or "stealth-tutorial-start";
                    if (!relevantName && !relevantStoryQuery)
                    {
                        if (!started) return Result("not-needed", "inquiry-outside-storymode-setup", null);
                        return Result("failed", "storymode-setup-inquiry-unsupported", "An unrelated or unsupported Native Inquiry interrupted StoryMode setup.");
                    }

                    started = true;
                    var resolution = await AgentHostNativeInquiryResolution.RunAsync(stateClient, inquiryClient, provider,
            cancellationToken,
                        runId + "-setup-inquiry-" + ledger.NextDecisionNumber.ToString(CultureInfo.InvariantCulture));
                    ledger.RecordDelegated(resolution);
                    actions += ReadInt(resolution, "actionsExecuted", 0);
                    ledger.Trace.Add(new JsonObject
                    {
                        ["stage"] = "storymode-setup-inquiry",
                        ["inquiryKind"] = kind,
                        ["status"] = ReadString(resolution, "status"),
                        ["clanName"] = ReadString(resolution, "clanName"),
                        ["decision"] = resolution["decision"]?.DeepClone(),
                        ["nativeReceipt"] = resolution["nativeReceipt"]?.DeepClone()
                    });
                    if (ReadString(resolution, "status") != "resolved")
                        return Result("failed", ReadString(resolution, "failureCode") ?? "storymode-setup-inquiry-unresolved",
                            ReadString(resolution, "failure") ?? "The Native StoryMode inquiry did not resolve.", resolution["decision"] as JsonObject, resolution["nativeReceipt"] as JsonObject);
                    continue;
                }

                var bannerEditor = context["bannerEditor"] as JsonObject;
                if (gameState == "BannerEditorState")
                {
                    if (!ReadBoolean(bannerEditor, "active") || !ReadBoolean(bannerEditor, "supported"))
                        return Result("failed", "storymode-banner-editor-native-view-unavailable", "BannerEditorState is active but the verified Native player-clan BannerEditor view is unavailable.");
                    started = true;
                    var observation = new JsonObject
                    {
                        ["scope"] = "original-storymode-post-tutorial-setup",
                        ["state"] = state.DeepClone(),
                        ["stage"] = "main-hero-clan-banner-editor"
                    };
                    var modelRequest = BuildActionRequest(runId, ledger.NextDecisionNumber,
                        "Complete the current Native BannerEditor setup using its current banner unless a requested customization is supported.",
                        observation, new JsonObject { ["action"] = "bannerEditorDone", ["arguments"] = new JsonArray() });
                    var decision = await DecideWithRecoveryAsync(
                        token => AgentHostDecisionCycle.DecideStoryModeBannerEditorAsync(provider, modelRequest, token), modelRequest);
                    ledger.RecordDecision(decision);
                    if (ReadString(decision.Decision, "action") != "bannerEditorDone" || HasArguments(decision.Decision))
                        return Result("failed", "storymode-banner-editor-decision-invalid", "The model did not choose the current Native BannerEditor Done action.", decision.Decision);
                    using var receiptDocument = await bannerEditorClient.CompleteStoryModeBannerEditorAsync(cancellationToken);
                    var receipt = JsonNode.Parse(receiptDocument.RootElement.GetRawText()) as JsonObject ?? new JsonObject();
                    if (ReadString(receipt, "status") != "completed")
                        return Result("failed", "storymode-banner-editor-native-done-failed", "The Native BannerEditor VM did not complete its current Done choice.", decision.Decision, receipt);
                    actions++;
                    AddTrace("banner-editor-done", decision, receipt, observation);
                    continue;
                }

                if (gameState == "MapState" && started)
                    return Result("completed", "storymode-post-tutorial-setup-returned-to-map", null);
                return started
                    ? Result("failed", "storymode-setup-transition-unsupported", "StoryMode setup entered a state outside the verified Native prompt/editor chain.")
                    : Result("not-needed", "no-storymode-setup-ui", null);
            }

            return started
                ? Result("failed", "storymode-setup-decision-budget-exhausted", "The original StoryMode setup chain did not return to MapState within the bounded decision count.")
                : Result("not-needed", "no-storymode-setup-ui", null);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            return Result("failed", "storymode-setup-cancelled", "StoryMode setup was cancelled before returning to Campaign Map.");
        }
        catch (Exception exception)
        {
            return Result("failed", exception is AgentHostException host ? host.Code : "storymode-setup-failed", exception.Message);
        }

        async Task<ProviderDecisionResult> DecideWithRecoveryAsync(
            Func<CancellationToken, Task<ProviderDecisionResult>> decide,
            JsonObject request)
        {
            string? previousFailure = null;
            for (var attempt = 0; attempt < 2; attempt++)
            {
                if (attempt > 0 && previousFailure is not null)
                    request["decisionFeedback"] = AgentHostProviderDecisionRecovery.BuildFeedback(previousFailure,
                        request["allowedActions"] as JsonArray ?? new JsonArray(),
                        request["allowedControls"] as JsonArray ?? new JsonArray());
                try { return await decide(cancellationToken); }
                catch (AgentHostException exception) when (AgentHostProviderDecisionRecovery.CanRetry(exception.Code, attempt))
                {
                    previousFailure = exception.Code;
                    ledger.RecordProviderFailure(exception.Code);
                    ledger.Trace.Add(new JsonObject
                    {
                        ["stage"] = "storymode-setup-provider-retry",
                        ["failureCode"] = exception.Code,
                        ["nativeActionSent"] = false,
                        ["retryAttempt"] = attempt + 1
                    });
                }
            }
            throw new AgentHostException(previousFailure ?? "storymode-setup-provider-retry-exhausted", "The bounded StoryMode setup provider retry ended without a parsed decision.");
        }

        void AddTrace(string stage, ProviderDecisionResult decision, JsonObject receipt, JsonObject observation)
        {
            ledger.Trace.Add(new JsonObject
            {
                ["stage"] = stage,
                ["decision"] = decision.Decision.DeepClone(),
                ["nativeReceipt"] = receipt.DeepClone(),
                ["observation"] = observation.DeepClone()
            });
        }

        JsonObject Result(string status, string? termination, string? failure, JsonObject? decision = null, JsonObject? receipt = null)
        {
            var result = new JsonObject
            {
                ["status"] = status,
                ["decisions"] = ledger.Decisions,
                ["actionsExecuted"] = actions,
                ["promptTokens"] = ledger.PromptTokens,
                ["completionTokens"] = ledger.CompletionTokens,
                ["trace"] = ledger.Trace.DeepClone(),
                ["providerRouteHistory"] = ledger.Routes.DeepClone(),
                ["termination"] = new JsonObject { ["reason"] = termination }
            };
            if (failure != null) result["failure"] = failure;
            if (status == "failed") result["failureCode"] = termination;
            if (decision != null) result["lastDecision"] = decision.DeepClone();
            if (receipt != null) result["lastNativeReceipt"] = receipt.DeepClone();
            return result;
        }
    }

    private static JsonObject BuildActionRequest(string runId, int iteration, string goal, JsonObject observation, JsonObject action) => new()
    {
        ["schemaVersion"] = 1,
        ["runId"] = runId,
        ["goal"] = goal,
        ["goalKind"] = "storymode-post-tutorial-setup",
        ["iteration"] = iteration,
        ["observation"] = observation.DeepClone(),
        ["allowedActions"] = new JsonArray(action.DeepClone()),
        ["allowedControls"] = new JsonArray()
    };

    private static bool HasArguments(JsonObject? decision) => decision?["arguments"] is JsonObject arguments && arguments.Count != 0;
    private static JsonObject? ReadState(JsonDocument document) =>
        document.RootElement.TryGetProperty("state", out var state) && state.ValueKind == JsonValueKind.Object
            ? JsonNode.Parse(state.GetRawText()) as JsonObject
            : null;
    private static string? ReadString(JsonObject? value, string name) => value?[name] is JsonValue node && node.TryGetValue<string>(out var text) ? text : null;
    private static string? ReadString(JsonElement value, string name) => value.ValueKind == JsonValueKind.Object && value.TryGetProperty(name, out var node) && node.ValueKind == JsonValueKind.String ? node.GetString() : null;
    private static bool ReadBoolean(JsonObject? value, string name) => value?[name] is JsonValue node && node.TryGetValue<bool>(out var boolean) && boolean;
    private static int ReadInt(JsonObject? value, string name, int fallback = 0) => value?[name] is JsonValue node && node.TryGetValue<int>(out var integer) ? integer : fallback;
    private static long ReadLong(JsonObject? value, string name, long fallback = 0) => value?[name] is JsonValue node && node.TryGetValue<long>(out var integer) ? integer : fallback;

    private sealed class FakeStoryModeSetupNativeClient : IAgentHostCampaignNativeClient, IAgentHostNativeInquiryClient, IAgentHostStoryModeBannerEditorNativeClient
    {
        private int _stage;
        private readonly bool _delayNotificationReady;
        internal List<string> Actions { get; } = new();
        internal string? SubmittedClanName { get; private set; }
        internal int NotificationReadinessPolls { get; private set; }

        internal FakeStoryModeSetupNativeClient(bool delayNotificationReady = false) => _delayNotificationReady = delayNotificationReady;

        public Task<JsonDocument> ReadStateAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var context = new JsonObject { ["gameState"] = _stage == 3 ? "BannerEditorState" : "MapState" };
            if (_stage == 1)
            {
                var ready = !_delayNotificationReady || NotificationReadinessPolls > 0;
                NotificationReadinessPolls++;
                context["sceneNotification"] = new JsonObject
                {
                    ["hasActiveNotification"] = true, ["isReady"] = ready,
                    ["dataType"] = "FindingFirstBannerPieceSceneNotificationItem",
                    ["continuationKind"] = "storymode-clan-name-setup", ["canContinue"] = ready,
                    ["titleText"] = "You found the first banner piece.", ["clickToContinueText"] = "Click to continue"
                };
            }
            else
                context["sceneNotification"] = new JsonObject { ["available"] = true, ["hasActiveNotification"] = false };

            if (_stage is 0 or 2 or 4)
            {
                var isClanName = _stage == 2;
                context["inquiryOpen"] = true;
                context["inquiry"] = isClanName
                    ? new JsonObject
                    {
                        ["supported"] = true, ["kind"] = "StoryModeClanNameTextInquiry", ["token"] = "clan-name-token",
                        ["title"] = "Select your family name:", ["text"] = "", ["defaultInputText"] = "Clan",
                        ["inputText"] = "Clan", ["affirmativeText"] = "Done", ["affirmativeVisible"] = true,
                        ["affirmativeEnabled"] = true, ["negativeVisible"] = false, ["inputObfuscated"] = false
                    }
                    : new JsonObject
                    {
                        ["supported"] = true, ["kind"] = "YesNoInquiry", ["token"] = _stage == 0 ? "notification-token" : "stealth-token",
                        ["title"] = _stage == 0 ? "通知" : "Stealth Tutorial", ["text"] = _stage == 0 ? "A Native StoryMode setup notification." : "Continue the original StoryMode setup.",
                        ["storyModeStartupKind"] = _stage == 0 ? "tutorial-skip-notification" : "stealth-tutorial-start",
                        ["affirmative"] = new JsonObject { ["visible"] = true, ["enabled"] = true, ["text"] = "Continue" },
                        ["negative"] = new JsonObject { ["visible"] = false, ["enabled"] = false, ["text"] = "" }
                    };
            }
            else
            {
                context["inquiryOpen"] = false;
                context["inquiry"] = null;
            }
            if (_stage == 3) context["bannerEditor"] = new JsonObject { ["active"] = true, ["supported"] = true, ["doneText"] = "Done", ["bannerCode"] = "native-default-banner" };
            else context["bannerEditor"] = new JsonObject { ["active"] = false };

            return Task.FromResult(JsonDocument.Parse(new JsonObject { ["status"] = "completed", ["state"] = new JsonObject { ["context"] = context } }.ToJsonString()));
        }

        public Task<JsonDocument> ExecuteCampaignActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (_stage != 1 || action != "continueSceneNotification" || arguments.Count != 0)
                throw new AgentHostException("storymode-setup-selftest-scene-action-invalid", "The setup loop must choose only the current Native first-banner continuation.");
            Actions.Add(action);
            _stage = 2;
            return Receipt(action, new JsonObject { ["nativeHandler"] = "SceneNotificationVM.ExecuteClose", ["nextInquiry"] = "StoryModeClanNameTextInquiry" });
        }

        public Task<JsonDocument> RespondNativeInquiryAsync(string token, string choice, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (!((_stage == 0 && token == "notification-token") || (_stage == 4 && token == "stealth-token")) || choice != "affirmative")
                throw new AgentHostException("storymode-setup-selftest-yesno-invalid", "The setup loop must answer only the current visible tutorial continuation choice.");
            Actions.Add("respondInquiry");
            _stage = _stage == 0 ? 1 : 5;
            return Receipt("respondInquiry", new JsonObject { ["choice"] = choice });
        }

        public Task<JsonDocument> SubmitStoryModeClanNameAsync(string token, string clanName, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (_stage != 2 || token != "clan-name-token") throw new AgentHostException("storymode-setup-selftest-name-token-invalid", "The family-name text action must bind the active Native TextInquiry token.");
            SubmittedClanName = clanName;
            Actions.Add("submitStoryModeClanName");
            _stage = 3;
            return Receipt("submitStoryModeClanName", new JsonObject { ["inputText"] = clanName, ["nativeViewModelHandler"] = "TextQueryPopUpVM.ExecuteAffirmativeAction" });
        }

        public Task<JsonDocument> CompleteStoryModeBannerEditorAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (_stage != 3) throw new AgentHostException("storymode-setup-selftest-banner-editor-invalid", "BannerEditor Done must be selected only in its current Native state.");
            Actions.Add("bannerEditorDone");
            _stage = 4;
            return Receipt("bannerEditorDone", new JsonObject { ["nativeHandler"] = "BannerEditorVM.ExecuteDone", ["nextInquiry"] = "stealth-tutorial-start" });
        }

        private static Task<JsonDocument> Receipt(string action, JsonObject data) =>
            Task.FromResult(JsonDocument.Parse(new JsonObject { ["status"] = "completed", ["action"] = action, ["data"] = data }.ToJsonString()));
    }

    private sealed class FakeStoryModeSetupDecisionProvider(int failOnCall = 0) : IAgentHostDecisionProvider
    {
        internal int CallCount { get; private set; }
        public string ModelId => "storymode-setup-selftest-model";
        public string ConfigurationSource => "harness-fake-provider";
        public Task CheckConfiguredModelAsync(CancellationToken cancellationToken) => Task.CompletedTask;

        public Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            CallCount++;
            if (failOnCall > 0 && CallCount == failOnCall)
                throw new AgentHostException("provider-decision-field-unavailable", "The fake provider emitted one unsupported field before correction.");
            var actions = request.GetProperty("allowedActions").EnumerateArray().ToArray();
            var action = actions.Single().GetProperty("action").GetString();
            JsonObject decision = action switch
            {
                "continueSceneNotification" => new JsonObject { ["action"] = action, ["arguments"] = new JsonObject() },
                "submitStoryModeClanName" => new JsonObject { ["action"] = action, ["arguments"] = new JsonObject { ["text"] = "Chronicle Wolves" } },
                "bannerEditorDone" => new JsonObject { ["action"] = action, ["arguments"] = new JsonObject() },
                "respondInquiry" => new JsonObject { ["action"] = action, ["arguments"] = new JsonObject { ["choice"] = "affirmative" } },
                _ => throw new AgentHostException("storymode-setup-selftest-action-unknown", "The fake provider received an unexpected action catalog.")
            };
            return Task.FromResult(new ProviderDecisionResult("completed", ModelId, 7, 2, "self-test", decision, "self-test", "json_schema"));
        }

        public void Dispose() { }
    }
}
