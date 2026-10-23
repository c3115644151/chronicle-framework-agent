using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal static class AgentHostStoryModeSetupLoop
{
    private const int MaxDecisions = 8;

    internal static async Task<IReadOnlyList<object>> RunContractSelfTestsAsync()
    {
        var native = new FakeStoryModeSetupNativeClient();
        var provider = new FakeStoryModeSetupDecisionProvider();
        using var request = JsonDocument.Parse("{\"runId\":\"storymode-post-tutorial-setup-selftest\",\"goal\":\"Complete original family name and banner setup.\"}");
        var result = await RunAsync(request.RootElement, native, native, native, provider, CancellationToken.None);
        var expected = new[] { "respondInquiry", "continueSceneNotification", "submitStoryModeClanName", "bannerEditorDone", "respondInquiry" };
        if (ReadString(result, "status") != "completed" ||
            ReadString(result["termination"] as JsonObject, "reason") != "storymode-post-tutorial-setup-returned-to-map" ||
            ReadInt(result, "decisions", 0) != expected.Length || ReadInt(result, "actionsExecuted", 0) != expected.Length ||
            provider.CallCount != expected.Length || native.Actions.Count != expected.Length ||
            !native.Actions.SequenceEqual(expected, StringComparer.Ordinal) || native.SubmittedClanName != "Chronicle Wolves")
            throw new AgentHostException("storymode-setup-loop-selftest-failed", "The Native startup chain must continue the verified banner notification, use TextQueryPopUpVM for a model-selected family name, commit the current BannerEditor through Done, answer the resulting tutorial inquiry, and return to Map. status=" + ReadString(result, "status") + "; actions=" + string.Join(",", native.Actions) + "; decisions=" + provider.CallCount);
        return [new { scenario = "storymode-post-tutorial-native-notification-family-name-banner-editor-and-follow-up-inquiry-loop", decisions = provider.CallCount, nativeActions = native.Actions.ToArray(), passed = true }];
    }

    internal static async Task<JsonObject> RunAsync(
        JsonElement request,
        IAgentHostCampaignNativeClient stateClient,
        IAgentHostNativeInquiryClient inquiryClient,
        IAgentHostStoryModeBannerEditorNativeClient bannerEditorClient,
        IAgentHostDecisionProvider provider,
        CancellationToken cancellationToken,
        int priorDecisions = 0,
        long priorPromptTokens = 0,
        long priorCompletionTokens = 0,
        JsonArray? priorTrace = null,
        JsonArray? priorProviderRouteHistory = null)
    {
        var runId = ReadString(request, "runId") ?? Guid.NewGuid().ToString("N");
        var decisions = priorDecisions;
        var actions = 0;
        long promptTokens = priorPromptTokens;
        long completionTokens = priorCompletionTokens;
        var trace = priorTrace?.DeepClone() as JsonArray ?? new JsonArray();
        var routes = priorProviderRouteHistory?.DeepClone() as JsonArray ?? new JsonArray();
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
                        ReadString(scene, "continuationKind") != "storymode-clan-name-setup" || !ReadBoolean(scene, "canContinue"))
                    {
                        if (!started) return Result("not-needed", "scene-notification-outside-storymode-setup", null);
                        return Result("failed", "storymode-setup-scene-notification-unsupported", "A different or unsafe Native scene notification interrupted StoryMode setup.");
                    }

                    started = true;
                    var observation = new JsonObject
                    {
                        ["scope"] = "original-storymode-post-tutorial-setup",
                        ["state"] = state.DeepClone(),
                        ["stage"] = "first-banner-notification"
                    };
                    var modelRequest = BuildActionRequest(runId, decisions + 1,
                        "Complete the current Native StoryMode first-banner notification and continue the original setup.",
                        observation, new JsonObject { ["action"] = "continueSceneNotification", ["arguments"] = new JsonArray() });
                    var decision = await AgentHostDecisionCycle.DecideStoryModeSceneNotificationAsync(provider, modelRequest, cancellationToken);
                    CountDecision(decision);
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
                    var resolution = await AgentHostNativeInquiryResolution.RunAsync(stateClient, inquiryClient, provider, cancellationToken,
                        runId + "-setup-inquiry-" + (decisions + 1).ToString(CultureInfo.InvariantCulture));
                    decisions += ReadInt(resolution, "decisions", 0);
                    actions += ReadInt(resolution, "actionsExecuted", 0);
                    promptTokens += ReadLong(resolution, "promptTokens", 0);
                    completionTokens += ReadLong(resolution, "completionTokens", 0);
                    if (resolution["providerRoute"] is JsonObject route) routes.Add(route.DeepClone());
                    trace.Add(new JsonObject
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
                    var modelRequest = BuildActionRequest(runId, decisions + 1,
                        "Complete the current Native BannerEditor setup using its current banner unless a requested customization is supported.",
                        observation, new JsonObject { ["action"] = "bannerEditorDone", ["arguments"] = new JsonArray() });
                    var decision = await AgentHostDecisionCycle.DecideStoryModeBannerEditorAsync(provider, modelRequest, cancellationToken);
                    CountDecision(decision);
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

        void CountDecision(ProviderDecisionResult decision)
        {
            decisions += 0; // The resolver already counted its own decisions; direct UI stages are counted here below.
            promptTokens += decision.PromptTokens ?? 0;
            completionTokens += decision.CompletionTokens ?? 0;
            routes.Add(new JsonObject
            {
                ["requestedModelId"] = decision.ModelId,
                ["responseModelId"] = decision.ModelId,
                ["routedVia"] = decision.RoutedVia,
                ["responseFormatMode"] = decision.ResponseFormatMode,
                ["promptTokens"] = decision.PromptTokens,
                ["completionTokens"] = decision.CompletionTokens
            });
            decisions++;
        }

        void AddTrace(string stage, ProviderDecisionResult decision, JsonObject receipt, JsonObject observation)
        {
            trace.Add(new JsonObject
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
                ["decisions"] = decisions,
                ["actionsExecuted"] = actions,
                ["promptTokens"] = promptTokens,
                ["completionTokens"] = completionTokens,
                ["trace"] = trace.DeepClone(),
                ["providerRouteHistory"] = routes.DeepClone(),
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
        internal List<string> Actions { get; } = new();
        internal string? SubmittedClanName { get; private set; }

        public Task<JsonDocument> ReadStateAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var context = new JsonObject { ["gameState"] = _stage == 3 ? "BannerEditorState" : "MapState" };
            if (_stage == 1)
                context["sceneNotification"] = new JsonObject
                {
                    ["hasActiveNotification"] = true, ["dataType"] = "FindingFirstBannerPieceSceneNotificationItem",
                    ["continuationKind"] = "storymode-clan-name-setup", ["canContinue"] = true,
                    ["titleText"] = "You found the first banner piece.", ["clickToContinueText"] = "Click to continue"
                };
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

    private sealed class FakeStoryModeSetupDecisionProvider : IAgentHostDecisionProvider
    {
        internal int CallCount { get; private set; }
        public string ModelId => "storymode-setup-selftest-model";
        public string ConfigurationSource => "harness-fake-provider";
        public Task CheckConfiguredModelAsync(CancellationToken cancellationToken) => Task.CompletedTask;

        public Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            CallCount++;
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
