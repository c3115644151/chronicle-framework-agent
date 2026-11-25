using System.Diagnostics;
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal static class AgentHostMapIncidentLoop
{
    private const int MaxDecisions = 2;

    internal static bool IsActive(JsonElement native) =>
        native.ValueKind == JsonValueKind.Object && native.TryGetProperty("state", out var state) &&
        state.ValueKind == JsonValueKind.Object && state.TryGetProperty("context", out var context) &&
        context.ValueKind == JsonValueKind.Object && context.TryGetProperty("mapIncident", out var incident) &&
        incident.ValueKind == JsonValueKind.Object && incident.TryGetProperty("active", out var active) &&
        active.ValueKind == JsonValueKind.True;

    internal static async Task<IReadOnlyList<object>> RunContractSelfTestsAsync()
    {
        var request = JsonDocument.Parse("""{"runId":"map-incident-selftest","goal":"Complete the original StoryMode Establish Your Clan campaign."}""");
        using (request)
        {
            var native = new FakeIncidentNativeClient();
            var provider = new FakeIncidentDecisionProvider(optionIndex: 1);
            var result = await RunAsync(request.RootElement, native, null, provider, CancellationToken.None);
            if (ReadString(result, "status") != "completed" || ReadInt(result, "decisions") != 1 ||
                ReadInt(result, "actionsExecuted") != 1 || provider.CallCount != 1 ||
                native.SubmittedOptionIndex != 1 || native.ClockActions != 0 || native.IncidentActive)
                throw new AgentHostException("map-incident-selftest-native-resolution-failed", "A current Native incident must offer only observed option indices, submit one selected option, and verify the original view closed without any clock action.");
            var builtCatalog = BuildActionCatalog(CreateIncidentState(new[] { 2, 5 }));
            var values = (builtCatalog[0] as JsonObject)?["argumentValues"]?["OptionIndex"] as JsonArray;
            if (values?.Count != 2 || values[0]?.GetValue<int>() != 2 || values[1]?.GetValue<int>() != 5)
                throw new AgentHostException("map-incident-selftest-catalog-filter-failed", "The incident action catalog must carry only exact current Native option indices.");
            if (TryResolveIncidentDecision(new JsonObject { ["action"] = "incidentSelect", ["arguments"] = new JsonObject { ["OptionIndex"] = 0 } }, builtCatalog[0] as JsonObject, values!, out _, out _) ||
                TryResolveIncidentDecision(new JsonObject { ["action"] = "incidentSelect", ["arguments"] = new JsonObject { ["OptionIndex"] = 1 } }, builtCatalog[0] as JsonObject, values!, out _, out _))
                throw new AgentHostException("map-incident-selftest-unobserved-option-accepted", "An option index absent from the current Native VM must be rejected before execution.");
            return
            [
                new { scenario = "map-incident-current-native-options-confirm-and-clock-lock-cleanup", decisions = 1, nativeActions = 1, passed = true },
                new { scenario = "map-incident-catalog-exposes-only-current-native-option-indices", optionIndices = new[] { 2, 5 }, passed = true }
            ];
        }
    }

    internal static async Task<JsonObject> RunAsync(
        JsonElement request,
        IAgentHostCampaignNativeClient client,
        IAgentHostQuestDetailsNativeClient? questDetailsClient,
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
        var actionsExecuted = 0;
        var promptTokens = priorPromptTokens;
        var completionTokens = priorCompletionTokens;
        var trace = priorTrace?.DeepClone() as JsonArray ?? new JsonArray();
        var routes = priorProviderRouteHistory?.DeepClone() as JsonArray ?? new JsonArray();
        JsonObject? lastDecision = null;
        JsonObject? lastReceipt = null;

        async Task<JsonObject> ResultAsync(string status, string reason, string? failureCode = null, string? failure = null)
        {
            double? actualCost = provider is OllamaNativeProvider costMeter ? costMeter.ActualCostEstimateCny : null;
            double? reservedCost = provider is OllamaNativeProvider reserveMeter ? reserveMeter.ReservedCostUpperBoundCny : null;
            var result = new JsonObject
            {
                ["status"] = status,
                ["runId"] = runId,
                ["decisions"] = decisions,
                ["actionsExecuted"] = actionsExecuted,
                ["promptTokens"] = promptTokens,
                ["completionTokens"] = completionTokens,
                ["providerActualCostEstimateCny"] = actualCost,
                ["providerReservedCostUpperCny"] = reservedCost,
                ["providerRouteHistory"] = routes.DeepClone(),
                ["trace"] = trace.DeepClone(),
                ["termination"] = new JsonObject { ["reason"] = reason, ["goalVerified"] = status == "completed" },
                ["failureCode"] = failureCode,
                ["failure"] = failure
            };
            if (lastDecision != null) result["lastDecision"] = lastDecision.DeepClone();
            if (lastReceipt != null) result["lastNativeReceipt"] = lastReceipt.DeepClone();
            await Task.CompletedTask;
            return result;
        }

        try
        {
            using var beforeDocument = await client.ReadStateAsync(cancellationToken);
            var before = CloneObject(beforeDocument.RootElement);
            if (!IsActive(beforeDocument.RootElement)) return await ResultAsync("not-needed", "no-active-native-map-incident");
            var incident = ReadMapIncident(before);
            if (!ReadBoolean(incident, "supported"))
                return await ResultAsync("failed", "active-native-incident-unsupported", "native-map-incident-view-unavailable",
                    "A Native map incident is active but its current visible ViewModel could not be read.");
            var catalog = BuildActionCatalog(incident);
            if (catalog.Count != 1)
                return await ResultAsync("failed", "active-native-incident-has-no-selectable-options", "native-map-incident-options-unavailable",
                    "The active Native incident did not expose a non-empty current option list.");

            JsonObject? journal = null;
            if (questDetailsClient != null && HasActiveEycQuest(before))
            {
                using var journalDocument = await questDetailsClient.ReadQuestDetailsAsync("rebuild_player_clan_storymode_quest", cancellationToken);
                var journalRoot = JsonNode.Parse(journalDocument.RootElement.GetRawText()) as JsonObject;
                journal = journalRoot?["data"]?["storyModeEstablishClan"]?.DeepClone() as JsonObject;
            }

            JsonObject? feedback = null;
            JsonObject? selectedDecision = null;
            for (var attempt = 0; attempt < MaxDecisions; attempt++)
            {
                var observation = new JsonObject
                {
                    ["status"] = "completed",
                    ["campaignDay"] = before["campaignDay"]?.DeepClone(),
                    ["timeControlMode"] = before["timeControlMode"]?.DeepClone(),
                    ["state"] = before["state"]?.DeepClone(),
                    ["incidentJournalObjectives"] = journal?.DeepClone()
                };
                var modelRequest = BuildModelRequest(runId, decisions + 1, request, observation, feedback, catalog);
                var startedUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                var startedTicks = Stopwatch.GetTimestamp();
                ProviderDecisionResult providerResult;
                try
                {
                    providerResult = await AgentHostDecisionCycle.DecideMapIncidentAsync(provider, modelRequest, cancellationToken);
                }
                catch (AgentHostException exception) when (AgentHostProviderDecisionRecovery.CanRetry(exception.Code, attempt) && attempt + 1 < MaxDecisions)
                {
                    decisions++;
                    routes.Add(new JsonObject
                    {
                        ["decision"] = decisions,
                        ["requestedModelId"] = provider.ModelId,
                        ["status"] = "provider-failure-before-decision",
                        ["failureCode"] = exception.Code,
                        ["nativeActionSent"] = false
                    });
                    trace.Add(new JsonObject { ["stage"] = "map-incident-provider-retry", ["failureCode"] = exception.Code, ["nativeActionSent"] = false });
                    feedback = new JsonObject { ["kind"] = "decision-rejected-before-native", ["code"] = exception.Code, ["requiredNextStep"] = "Choose exactly one OptionIndex from the current incident action catalog." };
                    continue;
                }

                decisions++;
                promptTokens += providerResult.PromptTokens ?? 0;
                completionTokens += providerResult.CompletionTokens ?? 0;
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
                selectedDecision = providerResult.Decision;
                var allowedIncidentIndices = (catalog[0] as JsonObject)?["argumentValues"]?["OptionIndex"] as JsonArray ?? new JsonArray();
                if (!TryResolveIncidentDecision(selectedDecision, catalog[0] as JsonObject, allowedIncidentIndices, out var optionIndex, out var rejection))
                {
                    if (attempt + 1 >= MaxDecisions)
                    {
                        lastDecision = selectedDecision.DeepClone() as JsonObject;
                        trace.Add(new JsonObject
                        {
                            ["stage"] = "map-incident-decision-rejected-before-native",
                            ["decision"] = selectedDecision.DeepClone(),
                            ["rejection"] = rejection,
                            ["nativeActionSent"] = false
                        });
                        return await ResultAsync("failed", "incident-decision-unavailable", "map-incident-decision-invalid", rejection);
                    }
                    feedback = new JsonObject { ["kind"] = "decision-rejected-before-native", ["message"] = rejection, ["requiredNextStep"] = "Choose exactly one current Native incident option index from allowedActions." };
                    trace.Add(new JsonObject { ["stage"] = "map-incident-decision-rejected-before-native", ["decision"] = selectedDecision.DeepClone(), ["rejection"] = rejection, ["nativeActionSent"] = false });
                    continue;
                }

                var actionStartedUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                JsonObject nativeReceipt;
                try
                {
                    using var response = await client.ExecuteCampaignActionAsync("incidentSelect", new JsonObject { ["optionIndex"] = optionIndex }, cancellationToken);
                    nativeReceipt = CloneObject(response.RootElement);
                }
                catch (AgentHostException exception) when (exception.Code == "native-command-timeout")
                {
                    lastDecision = selectedDecision.DeepClone() as JsonObject;
                    lastReceipt = new JsonObject { ["action"] = "incidentSelect", ["status"] = "timeout-ambiguous", ["error"] = exception.Code };
                    trace.Add(new JsonObject
                    {
                        ["stage"] = "map-incident-action-timeout-ambiguous",
                        ["decision"] = selectedDecision.DeepClone(),
                        ["nativeReceipt"] = lastReceipt.DeepClone(),
                        ["nativeActionReplayed"] = false
                    });
                    return await ResultAsync("failed", "incident-action-result-ambiguous", "native-command-timeout",
                        "The incident outcome may already have been submitted; the Host did not repeat it.");
                }

                lastDecision = selectedDecision.DeepClone() as JsonObject;
                lastReceipt = nativeReceipt.DeepClone() as JsonObject;
                var actionCompletedUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                var actionCompleted = string.Equals(ReadString(nativeReceipt, "status"), "completed", StringComparison.Ordinal) &&
                                      ReadBoolean(nativeReceipt["data"] as JsonObject, "submitted") &&
                                      !ReadBoolean(nativeReceipt["data"] as JsonObject, "sameIncidentViewRemains");
                actionsExecuted += actionCompleted ? 1 : 0;
                using var afterDocument = await client.ReadStateAsync(cancellationToken);
                var after = CloneObject(afterDocument.RootElement);
                var nextIncidentActive = IsActive(afterDocument.RootElement);
                var sameIncidentViewRemains = ReadBoolean(nativeReceipt["data"] as JsonObject, "sameIncidentViewRemains");
                var lockStillHeldWithoutNextIncident = !nextIncidentActive && ReadBoolean(ReadContext(after), "timeControlModeLocked");
                trace.Add(new JsonObject
                {
                    ["stage"] = "map-incident-option-submitted",
                    ["decision"] = selectedDecision.DeepClone(),
                    ["nativeReceipt"] = nativeReceipt.DeepClone(),
                    ["before"] = observation.DeepClone(),
                    ["after"] = JsonNode.Parse(afterDocument.RootElement.GetRawText()),
                    ["nativeActionCompleted"] = actionCompleted,
                    ["nativeActionReplayed"] = false,
                    ["providerStartedUtc"] = startedUtc,
                    ["providerElapsedMs"] = Stopwatch.GetElapsedTime(startedTicks).TotalMilliseconds,
                    ["nativeActionStartedUtc"] = actionStartedUtc,
                    ["nativeActionCompletedUtc"] = actionCompletedUtc
                });
                if (!actionCompleted)
                    return await ResultAsync("failed", "native-incident-submit-unverified", "native-map-incident-submit-unverified",
                        "The current incident option was not confirmed and the original Native view did not close.");
                if (sameIncidentViewRemains)
                    return await ResultAsync("failed", "native-incident-view-remains-open", "native-map-incident-view-remains-open",
                        "The Native confirmation submitted but the same incident view remains active; the Host did not repeat the choice.");
                if (lockStillHeldWithoutNextIncident)
                    return await ResultAsync("failed", "native-incident-closed-but-map-still-blocked", "native-map-incident-followup-blocked",
                        "The incident view closed but the Native time-control lock remains; the Host did not continue moving.");
                return await ResultAsync("completed", "native-map-incident-resolved");
            }

            return await ResultAsync("failed", "map-incident-decision-budget-exhausted", "map-incident-decision-limit",
                "The Host did not obtain one valid current incident option decision within the bounded retry count.");
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            return await ResultAsync("failed", "map-incident-cancelled", "map-incident-cancelled", "The Host was cancelled during Native incident resolution.");
        }
        catch (Exception exception)
        {
            return await ResultAsync("failed", "map-incident-resolution-failed", exception is AgentHostException host ? host.Code : "map-incident-resolution-failed", exception.Message);
        }
    }

    internal static JsonArray BuildActionCatalog(JsonObject? incident)
    {
        var options = incident?["options"] as JsonArray;
        var indices = options?.OfType<JsonObject>()
            .Select(option => ReadInt(option, "index", -1))
            .Where(index => index >= 0)
            .Distinct()
            .ToArray() ?? Array.Empty<int>();
        if (!ReadBoolean(incident, "active") || !ReadBoolean(incident, "supported") || indices.Length == 0)
            return new JsonArray();
        return new JsonArray(new JsonObject
        {
            ["action"] = "incidentSelect",
            ["arguments"] = new JsonArray("OptionIndex"),
            ["argumentValues"] = new JsonObject { ["OptionIndex"] = new JsonArray(indices.Select(index => (JsonNode?)JsonValue.Create(index)).ToArray()) }
        });
    }

    internal static bool TryResolveIncidentDecision(JsonObject? decision, JsonObject? actionTemplate, JsonArray allowedIndices, out int optionIndex, out string rejection)
    {
        optionIndex = -1;
        var parsedOptionIndex = -1;
        if (!string.Equals(ReadString(decision, "action"), "incidentSelect", StringComparison.Ordinal) ||
            decision?["arguments"] is not JsonObject arguments || arguments.Count != 1 ||
            !arguments.TryGetPropertyValue("OptionIndex", out var value) || value is not JsonValue jsonValue ||
            !jsonValue.TryGetValue<int>(out parsedOptionIndex) ||
            !allowedIndices.Any(item => item is JsonValue allowed && allowed.TryGetValue<int>(out var index) && index == parsedOptionIndex))
        {
            rejection = "Select only one OptionIndex listed in the current Native incident action catalog.";
            return false;
        }
        if (actionTemplate == null || ReadString(actionTemplate, "action") != "incidentSelect")
        {
            optionIndex = -1;
            rejection = "The current Native action catalog does not contain incidentSelect.";
            return false;
        }
        optionIndex = parsedOptionIndex;
        rejection = string.Empty;
        return true;
    }

    private static JsonObject BuildModelRequest(string runId, int iteration, JsonElement originalRequest, JsonObject observation, JsonObject? feedback, JsonArray actions) => new()
    {
        ["schemaVersion"] = 1,
        ["runId"] = runId,
        ["iteration"] = iteration,
        ["goal"] = ReadString(originalRequest, "goal") ?? "Resolve the current original Native map incident and continue the Campaign.",
        ["goalKind"] = "native-map-incident-resolution",
        ["observation"] = observation.DeepClone(),
        ["previousActionReceipt"] = null,
        ["decisionFeedback"] = feedback?.DeepClone(),
        ["allowedActions"] = actions.DeepClone(),
        ["allowedControls"] = new JsonArray()
    };

    private static JsonObject CloneObject(JsonElement element) => JsonNode.Parse(element.GetRawText())?.AsObject() ?? new JsonObject();
    private static JsonObject? ReadMapIncident(JsonObject native) => (native["state"] as JsonObject)?["context"]?["mapIncident"] as JsonObject;
    private static JsonObject? ReadContext(JsonObject native) => (native["state"] as JsonObject)?["context"] as JsonObject;
    private static bool HasActiveEycQuest(JsonObject native) => (native["state"]?["quests"] as JsonArray)?.OfType<JsonObject>().Any(quest => ReadString(quest, "id") == "rebuild_player_clan_storymode_quest") == true;
    private static bool ReadBoolean(JsonObject? value, string name) => value?[name] is JsonValue node && node.TryGetValue<bool>(out var result) && result;
    private static int ReadInt(JsonObject? value, string name, int fallback = 0) => value?[name] is JsonValue node && node.TryGetValue<int>(out var result) ? result : fallback;
    private static string? ReadString(JsonObject? value, string name) => value?[name] is JsonValue node && node.TryGetValue<string>(out var result) ? result : null;
    private static string? ReadString(JsonElement value, string name) => value.ValueKind == JsonValueKind.Object && value.TryGetProperty(name, out var node) && node.ValueKind == JsonValueKind.String ? node.GetString() : null;

    private static JsonObject CreateIncidentState(int[] indices) => new()
    {
        ["active"] = true,
        ["supported"] = true,
        ["options"] = new JsonArray(indices.Select(index => (JsonNode?)new JsonObject { ["index"] = index, ["text"] = "Option " + index }).ToArray())
    };

    private sealed class FakeIncidentNativeClient : IAgentHostCampaignNativeClient
    {
        internal bool IncidentActive { get; private set; } = true;
        internal int SubmittedOptionIndex { get; private set; } = -1;
        internal int ClockActions { get; private set; }

        public Task<JsonDocument> ReadStateAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var result = new JsonObject
            {
                ["status"] = "completed",
                ["campaignDay"] = 10.0,
                ["timeControlMode"] = IncidentActive ? "Stop" : "StoppablePlay",
                ["state"] = new JsonObject
                {
                    ["quests"] = new JsonArray(new JsonObject { ["id"] = "rebuild_player_clan_storymode_quest" }),
                    ["economy"] = new JsonObject { ["gold"] = 500 },
                    ["party"] = new JsonObject { ["members"] = 7 },
                    ["context"] = new JsonObject
                    {
                        ["gameState"] = "MapState",
                        ["timeControlModeLocked"] = IncidentActive,
                        ["mapIncident"] = IncidentActive ? new JsonObject
                        {
                            ["schemaVersion"] = 1, ["active"] = true, ["supported"] = true,
                            ["incidentType"] = "Plight", ["title"] = "A harvest is threatened", ["description"] = "Choose a response.",
                            ["canConfirm"] = false, ["selectedOptionIndex"] = -1,
                            ["options"] = new JsonArray(
                                new JsonObject { ["index"] = 0, ["text"] = "Spend 100 denars", ["hint"] = "Lose Gold.", ["selected"] = false },
                                new JsonObject { ["index"] = 1, ["text"] = "Risk the crops", ["hint"] = "Preserve Gold.", ["selected"] = false })
                        } : new JsonObject { ["schemaVersion"] = 1, ["active"] = false, ["supported"] = true }
                    }
                }
            };
            return Task.FromResult(JsonDocument.Parse(result.ToJsonString()));
        }

        public Task<JsonDocument> ExecuteCampaignActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (action != "incidentSelect" || arguments.Count != 1 || !arguments.TryGetPropertyValue("optionIndex", out var value) || value is not JsonValue node || !node.TryGetValue<int>(out var index))
                throw new AgentHostException("fake-native-action-invalid", "The map incident self-test received an unexpected Native action.");
            SubmittedOptionIndex = index;
            IncidentActive = false;
            return Task.FromResult(JsonDocument.Parse(new JsonObject
            {
                ["status"] = "completed",
                ["action"] = action,
                ["data"] = new JsonObject { ["submitted"] = true, ["sameIncidentViewRemains"] = false, ["selectedOptionIndex"] = index }
            }.ToJsonString()));
        }
    }

    private sealed class FakeIncidentDecisionProvider(int optionIndex) : IAgentHostDecisionProvider
    {
        internal int CallCount { get; private set; }
        public string ModelId => "self-test";
        public string ConfigurationSource => "self-test";
        public Task CheckConfiguredModelAsync(CancellationToken cancellationToken) => Task.CompletedTask;
        public Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            CallCount++;
            return Task.FromResult(new ProviderDecisionResult("completed", ModelId, 8, 3, "self-test", new JsonObject
            {
                ["action"] = "incidentSelect", ["arguments"] = new JsonObject { ["OptionIndex"] = optionIndex }
            }, "self-test", "json_schema"));
        }
        public void Dispose() { }
    }
}
