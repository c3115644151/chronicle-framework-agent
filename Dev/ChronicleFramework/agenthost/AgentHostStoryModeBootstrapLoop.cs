using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal static class AgentHostStoryModeBootstrapLoop
{
    internal const string StoryQuestId = "rebuild_player_clan_storymode_quest";
    internal const string TrainingFieldMenuId = "training_field_menu";
    internal const string TrainingFieldSettlementId = "tutorial_training_field";
    internal const string TrainingFieldLeaveOptionId = "training_field_leave";

    internal static IReadOnlyList<object> RunContractSelfTests()
    {
        var activeQuest = CreateState("active", tutorialCompleted: true, includeQuest: true);
        var validBeforeActivation = CreateState("storymode-not-activated", tutorialCompleted: true, includeQuest: false);
        var validUnknown = CreateState("unknown", tutorialCompleted: true, includeQuest: false);
        var preTutorial = CreateState("storymode-not-activated", tutorialCompleted: false, includeQuest: false);
        var wrongMenu = CreateState("unknown", tutorialCompleted: true, includeQuest: false);
        wrongMenu["state"]!["context"]!["menuId"] = "town";

        if (!IsEligibleTrainingFieldBootstrapState(Parse(activeQuest).RootElement) ||
            !IsEligibleTrainingFieldBootstrapState(Parse(validBeforeActivation).RootElement) ||
            !IsEligibleTrainingFieldBootstrapState(Parse(validUnknown).RootElement) ||
            IsEligibleTrainingFieldBootstrapState(Parse(preTutorial).RootElement) ||
            IsEligibleTrainingFieldBootstrapState(Parse(wrongMenu).RootElement))
            throw new AgentHostException("storymode-bootstrap-self-test-lifecycle-gate-failed", "The Native training-field exit must run for the exact post-skip menu both before and after natural EYC activation, and reject other lifecycle/location states.");

        var noLeave = CreateState("unknown", tutorialCompleted: true, includeQuest: false);
        var options = noLeave["state"]!["availableMenuOptions"]!.AsArray();
        options.RemoveAt(1);
        if (BuildActionCatalog(Parse(noLeave).RootElement).Count != 0)
            throw new AgentHostException("storymode-bootstrap-self-test-invented-leave-failed", "The bootstrap must not invent a Native leave option absent from the current menu.");

        var catalog = BuildActionCatalog(Parse(validBeforeActivation).RootElement);
        var optionValues = catalog[0]?["argumentValues"]?["OptionId"] as JsonArray;
        if (catalog.Count != 1 || ReadString(catalog[0] as JsonObject, "action") != "menuSelect" ||
            optionValues is null || !optionValues.Any(value => ReadString(value) == TrainingFieldLeaveOptionId) ||
            !optionValues.Any(value => ReadString(value) == "training_field_enter"))
            throw new AgentHostException("storymode-bootstrap-self-test-native-catalog-failed", "The model must see all currently enabled training-field menu options while using exact Native IDs.");

        var fakeClient = new FakeBootstrapNativeClient();
        var fakeProvider = new FakeBootstrapProvider();
        using var request = JsonDocument.Parse("{\"runId\":\"storymode-bootstrap-selftest\",\"goal\":\"Autonomously complete the original Establish Your Clan quest.\",\"maxElapsedSeconds\":10}");
        var execution = RunAsync(request.RootElement, fakeClient, fakeClient, fakeProvider, CancellationToken.None).GetAwaiter().GetResult();
        if (ReadString(execution, "status") != "completed" ||
            ReadString(execution["termination"]?.AsObject(), "reason") != "native-establish-your-clan-activated-after-visible-menu-action" ||
            ReadInt(execution, "decisions", -1) != 1 || ReadInt(execution, "actionsExecuted", -1) != 1 ||
            fakeProvider.CallCount != 1 || fakeClient.MenuActionCount != 1 || !fakeClient.ActiveEyc)
            throw new AgentHostException("storymode-bootstrap-self-test-native-leave-activation-failed", "The model-selected current Native training-field leave option must activate the original quest and return fresh active-quest evidence.");

        var activeQuestClient = new FakeBootstrapNativeClient(activeQuestAtStart: true);
        var activeQuestProvider = new FakeBootstrapProvider();
        var activeQuestExecution = RunAsync(request.RootElement, activeQuestClient, activeQuestClient, activeQuestProvider, CancellationToken.None).GetAwaiter().GetResult();
        if (ReadString(activeQuestExecution, "status") != "completed" ||
            ReadString(activeQuestExecution["termination"]?.AsObject(), "reason") != "native-training-field-left-with-active-eyc" ||
            ReadInt(activeQuestExecution, "decisions", -1) != 1 || ReadInt(activeQuestExecution, "actionsExecuted", -1) != 1 ||
            activeQuestProvider.CallCount != 1 || activeQuestClient.MenuActionCount != 1 || !activeQuestClient.ActiveEyc)
            throw new AgentHostException("storymode-bootstrap-self-test-active-quest-leave-failed", "When EYC is already active on the first training-field MapState, the model must still leave via the Native option and verify it returned to usable MapState with EYC active.");

        return
        [
            new { scenario = "storymode-training-field-exit-runs-before-or-after-natural-eyc-activation", passed = true },
            new { scenario = "storymode-bootstrap-requires-current-native-leave-option", passed = true },
            new { scenario = "storymode-bootstrap-model-catalog-enumerates-current-visible-menu", passed = true },
            new { scenario = "storymode-bootstrap-model-selects-native-leave-and-requires-active-quest-postcondition", passed = true },
            new { scenario = "storymode-training-field-leave-works-when-eyc-is-already-active", passed = true }
        ];
    }

    internal static bool IsEligibleTrainingFieldBootstrapState(JsonElement native)
    {
        if (!TryReadState(native, out var state) || !TryReadObject(state, "context", out var context) ||
            !TryReadObject(state, "storyModeEstablishClanStatus", out var lifecycle) ||
            !TryReadObject(state, "location", out var location)) return false;

        var lifecycleStatus = ReadString(lifecycle, "status");
        var activeQuest = HasActiveQuest(native);
        var lifecycleMatches = lifecycleStatus switch
        {
            "storymode-not-activated" or "unknown" => !activeQuest && ReadBoolean(lifecycle, "tutorialCompleted"),
            "active" => activeQuest,
            _ => false
        };
        if (!lifecycleMatches ||
            ReadString(lifecycle, "questId") != StoryQuestId ||
            ReadString(context, "gameState") != "MapState" ||
            ReadString(context, "menuId") != TrainingFieldMenuId ||
            ReadString(location, "currentSettlementId") != TrainingFieldSettlementId ||
            (TryReadObject(context, "captivity", out var captivity) && ReadBoolean(captivity, "isCaptive")) ||
            (context.TryGetProperty("encounterActive", out var encounterActive) && encounterActive.ValueKind == JsonValueKind.True &&
             ReadString(context, "encounteredPartyId") != TrainingFieldSettlementId)) return false;

        return BuildActionCatalog(native).Count == 1;
    }

    internal static JsonArray BuildActionCatalog(JsonElement native)
    {
        if (!TryReadState(native, out var state) || !TryReadObject(state, "context", out var context) ||
            !TryReadObject(state, "location", out var location) ||
            ReadString(context, "gameState") != "MapState" ||
            ReadString(context, "menuId") != TrainingFieldMenuId ||
            ReadString(location, "currentSettlementId") != TrainingFieldSettlementId ||
            !native.TryGetProperty("state", out var stateNode) || !stateNode.TryGetProperty("availableMenuOptions", out var options) || options.ValueKind != JsonValueKind.Array)
            return new JsonArray();

        var enabledOptionIds = options.EnumerateArray()
            .Where(option => option.ValueKind == JsonValueKind.Object &&
                ReadBoolean(option, "available") && ReadBoolean(option, "enabled"))
            .Select(option => ReadString(option, "id"))
            .Where(id => id is "training_field_enter" or TrainingFieldLeaveOptionId)
            .Distinct(StringComparer.Ordinal)
            .ToArray();
        if (!enabledOptionIds.Contains(TrainingFieldLeaveOptionId, StringComparer.Ordinal)) return new JsonArray();

        return new JsonArray(new JsonObject
        {
            ["action"] = "menuSelect",
            ["arguments"] = new JsonArray("MenuId", "OptionId"),
            ["argumentValues"] = new JsonObject
            {
                ["MenuId"] = new JsonArray(TrainingFieldMenuId),
                ["OptionId"] = new JsonArray(enabledOptionIds.Select(id => (JsonNode?)JsonValue.Create(id)).ToArray())
            }
        });
    }

    internal static async Task<JsonObject> RunAsync(
        JsonElement request,
        IAgentHostCampaignNativeClient client,
        IAgentHostStoryModeBootstrapNativeClient bootstrapClient,
        IAgentHostDecisionProvider provider,
        CancellationToken cancellationToken,
        int priorDecisions = 0,
        long priorPromptTokens = 0,
        long priorCompletionTokens = 0,
        JsonArray? priorTrace = null,
        JsonArray? priorProviderRouteHistory = null)
    {
        var runId = ReadString(request, "runId") ?? Guid.NewGuid().ToString("N");
        var goal = ReadString(request, "goal") ?? "Complete the original StoryMode Establish Your Clan quest.";
        var decisions = priorDecisions;
        var nativeActions = 0;
        long promptTokens = priorPromptTokens;
        long completionTokens = priorCompletionTokens;
        var trace = priorTrace?.DeepClone() as JsonArray ?? new JsonArray();
        var routes = priorProviderRouteHistory?.DeepClone() as JsonArray ?? new JsonArray();
        var started = Stopwatch.GetTimestamp();

        try
        {
            using var observed = await client.ReadStateAsync(cancellationToken);
            if (!IsEligibleTrainingFieldBootstrapState(observed.RootElement))
                return BuildResult("failed", "storymode-bootstrap-state-unsupported", "The exact post-skip training-field map menu and current Native leave option were not observed.", "storymode-bootstrap-state-unsupported");
            var questWasActive = HasActiveQuest(observed.RootElement);

            var allowedActions = BuildActionCatalog(observed.RootElement);
            var modelRequest = new JsonObject
            {
                ["schemaVersion"] = 1,
                ["runId"] = runId,
                ["iteration"] = 1,
                ["goal"] = goal,
                ["goalScopeClassificationRequired"] = false,
                ["goalScopeContract"] = "native-storymode-bootstrap-v1",
                ["observation"] = new JsonObject
                {
                    ["status"] = "completed",
                    ["scope"] = "post-tutorial-skip-storymode-bootstrap",
                    ["message"] = questWasActive
                        ? "The original Establish Your Clan quest is already active, but the player is still in the tutorial training-field menu. Leave through its current Native menu option."
                        : "The first Campaign MapState is active but the original Establish Your Clan quest is not active yet. Use the currently visible Native training-field menu to continue the campaign.",
                    ["campaignDay"] = GetNativeNumber(observed.RootElement, "campaignDay"),
                    ["timeControlMode"] = GetNativeString(observed.RootElement, "timeControlMode"),
                    ["state"] = JsonNode.Parse(observed.RootElement.GetProperty("state").GetRawText())
                },
                ["previousActionReceipt"] = null,
                ["decisionFeedback"] = new JsonObject
                {
                    ["kind"] = questWasActive ? "storymode-active-quest-training-field-exit" : "storymode-quest-awaiting-map-transition",
                    ["requiredNextStep"] = "Choose the currently listed Native training_field_leave menu option; do not re-enter training, manipulate Campaign time, or claim quest completion."
                },
                ["allowedActions"] = allowedActions,
                ["allowedControls"] = new JsonArray(),
                ["controlArguments"] = new JsonObject()
            };

            var providerStartedUtc = DateTime.UtcNow.ToString("O", System.Globalization.CultureInfo.InvariantCulture);
            var providerStartedTicks = Stopwatch.GetTimestamp();
            var providerResult = await AgentHostDecisionCycle.DecideStoryModeBootstrapAsync(provider, modelRequest, cancellationToken);
            decisions++;
            if (providerResult.PromptTokens.HasValue) promptTokens += providerResult.PromptTokens.Value;
            if (providerResult.CompletionTokens.HasValue) completionTokens += providerResult.CompletionTokens.Value;
            routes.Add(new JsonObject
            {
                ["decision"] = decisions,
                ["requestedModelId"] = provider.ModelId,
                ["responseModelId"] = providerResult.ModelId,
                ["routedVia"] = providerResult.RoutedVia,
                ["responseFormatMode"] = providerResult.ResponseFormatMode,
                ["promptTokens"] = providerResult.PromptTokens,
                ["completionTokens"] = providerResult.CompletionTokens
            });

            var decision = providerResult.Decision;
            var action = ReadString(decision, "action");
            if (action != "menuSelect" || !TryReadObject(decision, "arguments", out var arguments))
                return BuildResult("failed", "storymode-bootstrap-native-action-invalid", "The model did not choose a listed Native menuSelect action.", "storymode-bootstrap-native-action-invalid");
            var menuId = ReadString(arguments, "MenuId") ?? ReadString(arguments, "menuId");
            var optionId = ReadString(arguments, "OptionId") ?? ReadString(arguments, "optionId");
            var allowedOptionIds = allowedActions[0]?["argumentValues"]?["OptionId"] as JsonArray;
            if (menuId != TrainingFieldMenuId || optionId is null ||
                allowedOptionIds?.Any(value => ReadString(value) == optionId) != true)
                return BuildResult("failed", "storymode-bootstrap-menu-choice-not-listed", "The model selected an option outside the current Native training-field menu.", "storymode-bootstrap-menu-choice-not-listed");

            var actionArguments = new JsonObject { ["menuId"] = menuId, ["optionId"] = optionId };
            JsonObject actionReceipt;
            using (var response = await bootstrapClient.ExecuteTrainingFieldMenuSelectAsync(menuId, optionId, cancellationToken))
                actionReceipt = CloneObject(response.RootElement);
            if (ReadString(actionReceipt, "status") != "completed")
                return BuildResult("failed", "storymode-bootstrap-native-menu-action-failed", "The original training-field menu handler did not report completion.", "storymode-bootstrap-native-menu-action-failed");
            nativeActions++;

            var traceStep = new JsonObject
            {
                ["stage"] = "storymode-pre-activation-menu-action",
                ["iteration"] = 1,
                ["goal"] = goal,
                ["observation"] = modelRequest["observation"]?.DeepClone(),
                ["allowedActions"] = allowedActions.DeepClone(),
                ["decision"] = decision.DeepClone(),
                ["providerRoute"] = providerResult.RoutedVia,
                ["responseFormatMode"] = providerResult.ResponseFormatMode,
                ["promptTokens"] = providerResult.PromptTokens,
                ["completionTokens"] = providerResult.CompletionTokens,
                ["actionReceipt"] = BuildSafeActionReceipt(actionReceipt, menuId, optionId),
                ["providerStartedUtc"] = providerStartedUtc,
                ["providerElapsedMilliseconds"] = Math.Round(Stopwatch.GetElapsedTime(providerStartedTicks).TotalMilliseconds, 3)
            };
            trace.Add(traceStep);

            for (var poll = 0; poll < 12; poll++)
            {
                cancellationToken.ThrowIfCancellationRequested();
                if (poll > 0) await Task.Delay(TimeSpan.FromMilliseconds(250), cancellationToken);
                using var fresh = await client.ReadStateAsync(cancellationToken);
                if (HasActiveQuest(fresh.RootElement) && HasLeftTrainingField(fresh.RootElement))
                    return BuildResult("completed", questWasActive ? "native-training-field-left-with-active-eyc" : "native-establish-your-clan-activated-after-visible-menu-action", null, null);
            }

            return BuildResult("failed", "storymode-bootstrap-postcondition-unverified", "The selected Native training-field menu action completed, but fresh state did not show both a usable map outside the training field and the original EYC quest active.", "storymode-bootstrap-postcondition-unverified");
        }
        catch (OperationCanceledException)
        {
            return BuildResult("failed", "storymode-bootstrap-cancelled", "The Host stopped while preparing the native StoryMode quest transition.", "storymode-bootstrap-cancelled");
        }
        catch (AgentHostException exception)
        {
            return BuildResult("failed", "storymode-bootstrap-failed", exception.Message, exception.Code);
        }
        catch (Exception exception)
        {
            return BuildResult("failed", "storymode-bootstrap-failed", exception.GetType().Name, "storymode-bootstrap-unexpected-error");
        }

        JsonObject BuildResult(string status, string reason, string? failure, string? failureCode) => new()
        {
            ["status"] = status,
            ["resultKind"] = "storymode-post-skip-native-bootstrap",
            ["runId"] = runId,
            ["providerModelId"] = provider.ModelId,
            ["decisions"] = decisions,
            ["actionsExecuted"] = nativeActions,
            ["promptTokens"] = promptTokens,
            ["completionTokens"] = completionTokens,
            ["elapsedSeconds"] = Math.Round(Stopwatch.GetElapsedTime(started).TotalSeconds, 3),
            ["providerRouteHistory"] = routes.DeepClone(),
            ["trace"] = trace.DeepClone(),
            ["termination"] = new JsonObject { ["reason"] = reason, ["completedByProvider"] = false, ["goalVerified"] = false },
            ["failure"] = failure,
            ["failureCode"] = failureCode
        };
    }

    private static JsonObject BuildSafeActionReceipt(JsonObject receipt, string menuId, string optionId) => new()
    {
        ["action"] = "menuSelect",
        ["menuId"] = menuId,
        ["optionId"] = optionId,
        ["status"] = ReadString(receipt, "status"),
        ["commandId"] = ReadString(receipt, "commandId")
    };

    private static bool HasActiveQuest(JsonElement native) =>
        native.TryGetProperty("state", out var state) && state.ValueKind == JsonValueKind.Object &&
        state.TryGetProperty("quests", out var quests) && quests.ValueKind == JsonValueKind.Array &&
        quests.EnumerateArray().Any(quest => quest.ValueKind == JsonValueKind.Object && ReadString(quest, "id") == StoryQuestId);

    internal static bool HasLeftTrainingField(JsonElement native)
    {
        if (!TryReadState(native, out var state) || !TryReadObject(state, "context", out var context) || !TryReadObject(state, "location", out var location)) return false;
        return ReadString(context, "gameState") == "MapState" &&
               ReadString(context, "menuId") != TrainingFieldMenuId &&
               ReadString(location, "currentSettlementId") != TrainingFieldSettlementId;
    }

    private static bool TryReadState(JsonElement native, out JsonElement state)
    {
        state = default;
        return native.ValueKind == JsonValueKind.Object && native.TryGetProperty("state", out state) && state.ValueKind == JsonValueKind.Object;
    }

    private static bool TryReadObject(JsonElement parent, string name, out JsonElement value)
    {
        value = default;
        return parent.ValueKind == JsonValueKind.Object && parent.TryGetProperty(name, out value) && value.ValueKind == JsonValueKind.Object;
    }

    private static string? ReadString(JsonObject? obj, string name) => obj?[name] is JsonValue value && value.TryGetValue<string>(out var result) ? result : null;
    private static string? ReadString(JsonElement element, string name) => element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;
    private static string? ReadString(JsonNode? node) => node is JsonValue value && value.TryGetValue<string>(out var result) ? result : null;
    private static int ReadInt(JsonObject? obj, string name, int fallback) => obj?[name] is JsonValue value && value.TryGetValue<int>(out var result) ? result : fallback;
    private static bool ReadBoolean(JsonObject? obj, string name) => obj?[name] is JsonValue value && value.TryGetValue<bool>(out var result) && result;
    private static bool ReadBoolean(JsonElement element, string name) => element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.True;
    private static string? GetNativeString(JsonElement native, string name) => ReadString(native, name);
    private static JsonNode? GetNativeNumber(JsonElement native, string name) => native.ValueKind == JsonValueKind.Object && native.TryGetProperty(name, out var value) ? JsonNode.Parse(value.GetRawText()) : null;
    private static bool TryReadObject(JsonObject? parent, string name, out JsonObject? value)
    {
        value = parent?[name] as JsonObject;
        return value is not null;
    }

    private static JsonObject CloneObject(JsonElement element) => JsonNode.Parse(element.GetRawText())?.AsObject()
        ?? throw new AgentHostException("storymode-bootstrap-native-response-invalid", "The Native StoryMode bootstrap response was not a JSON object.");

    private static JsonObject CreateState(string status, bool tutorialCompleted, bool includeQuest)
    {
        var quests = new JsonArray();
        if (includeQuest) quests.Add(new JsonObject { ["id"] = StoryQuestId });
        return new JsonObject
        {
            ["status"] = "completed",
            ["processId"] = 321,
            ["state"] = new JsonObject
            {
                ["storyModeEstablishClanStatus"] = new JsonObject
                {
                    ["status"] = status, ["questId"] = StoryQuestId, ["tutorialCompleted"] = tutorialCompleted
                },
                ["context"] = new JsonObject { ["gameState"] = "MapState", ["menuId"] = TrainingFieldMenuId, ["encounterActive"] = true, ["encounteredPartyId"] = TrainingFieldSettlementId },
                ["location"] = new JsonObject { ["currentSettlementId"] = TrainingFieldSettlementId },
                ["quests"] = quests,
                ["availableMenuOptions"] = new JsonArray(
                    new JsonObject { ["id"] = "training_field_enter", ["available"] = true, ["enabled"] = true },
                    new JsonObject { ["id"] = TrainingFieldLeaveOptionId, ["available"] = true, ["enabled"] = true })
            }
        };
    }

    private static JsonDocument Parse(JsonObject value) => JsonDocument.Parse(value.ToJsonString());

    private sealed class FakeBootstrapNativeClient : IAgentHostCampaignNativeClient, IAgentHostStoryModeBootstrapNativeClient
    {
        private readonly JsonObject _state;
        internal int MenuActionCount { get; private set; }
        internal bool ActiveEyc { get; private set; }

        internal FakeBootstrapNativeClient(bool activeQuestAtStart = false)
        {
            ActiveEyc = activeQuestAtStart;
            _state = activeQuestAtStart
                ? CreateState("active", tutorialCompleted: true, includeQuest: true)
                : CreateState("unknown", tutorialCompleted: true, includeQuest: false);
        }

        public Task<JsonDocument> ReadStateAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            return Task.FromResult(Parse((JsonObject)_state.DeepClone()));
        }

        public Task<JsonDocument> ExecuteCampaignActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken) =>
            throw new AgentHostException("storymode-bootstrap-self-test-unexpected-campaign-action", "The bootstrap must use only the separate Native menu action.");

        public Task<JsonDocument> ExecuteTrainingFieldMenuSelectAsync(string menuId, string optionId, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (menuId != TrainingFieldMenuId || optionId != TrainingFieldLeaveOptionId)
                throw new AgentHostException("storymode-bootstrap-self-test-wrong-menu-option", "The model did not select the currently listed original training-field Leave option.");
            MenuActionCount++;
            ActiveEyc = true;
            var state = _state["state"]!.AsObject();
            state["context"]!["menuId"] = null;
            state["location"]!["currentSettlementId"] = null;
            state["availableMenuOptions"] = new JsonArray();
            state["storyModeEstablishClanStatus"]!["status"] = "active";
            state["quests"]!.AsArray().Add(new JsonObject { ["id"] = StoryQuestId });
            return Task.FromResult(Parse(new JsonObject { ["status"] = "completed", ["commandId"] = "fake-storymode-leave" }));
        }
    }

    private sealed class FakeBootstrapProvider : IAgentHostDecisionProvider
    {
        internal int CallCount { get; private set; }
        internal JsonObject? LastRequest { get; private set; }
        public string ModelId => "fake-storymode-bootstrap";
        public string ConfigurationSource => "harness-fake-provider";

        public Task CheckConfiguredModelAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            return Task.CompletedTask;
        }

        public Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            CallCount++;
            LastRequest = JsonNode.Parse(request.GetRawText())?.AsObject();
            return Task.FromResult(new ProviderDecisionResult("completed", ModelId, 25, 5, "tool_calls",
                new JsonObject
                {
                    ["action"] = "menuSelect",
                    ["arguments"] = new JsonObject { ["MenuId"] = TrainingFieldMenuId, ["OptionId"] = TrainingFieldLeaveOptionId },
                    ["rationale"] = "Leave the tutorial training field."
                },
                "fake-remote-route", "required_tool_call"));
        }

        public void Dispose() { }
    }
}
