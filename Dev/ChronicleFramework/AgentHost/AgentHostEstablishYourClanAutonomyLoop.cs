using System.Diagnostics;
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal static class AgentHostEstablishYourClanAutonomyLoop
{
    private const string QuestId = "rebuild_player_clan_storymode_quest";
    internal static readonly HashSet<string> InitiallyIntegratedObjectives = new(StringComparer.Ordinal) { "gold", "partySize", "renown" };

    internal delegate Task<JsonObject> ObjectiveExecutor(
        string objectiveId,
        int priorDecisions,
        long priorPromptTokens,
        long priorCompletionTokens,
        JsonArray priorTrace,
        JsonArray priorProviderRouteHistory,
        CancellationToken cancellationToken);

    internal static IReadOnlyList<object> RunContractSelfTests()
    {
        var snapshot = new JsonObject
        {
            ["gold"] = new JsonObject { ["current"] = 32, ["target"] = 2000, ["met"] = false },
            ["partySize"] = new JsonObject { ["current"] = 4, ["target"] = 20, ["met"] = false },
            ["renown"] = new JsonObject { ["current"] = 5, ["target"] = 50, ["met"] = false },
            ["companions"] = new JsonObject { ["current"] = 0, ["target"] = 1, ["met"] = false }
        };
        var catalog = AgentHostEstablishYourClanGoalLoop.BuildObjectiveActionCatalog(snapshot, InitiallyIntegratedObjectives);
        var selectable = catalog[0]?["argumentValues"]?["ObjectiveId"] as JsonArray;
        if (selectable is null || selectable.Count != 3 ||
            !selectable.Any(value => value?.GetValue<string>() == "gold") ||
            !selectable.Any(value => value?.GetValue<string>() == "partySize") ||
            !selectable.Any(value => value?.GetValue<string>() == "renown") ||
            selectable.Any(value => value?.GetValue<string>() == "companions"))
            throw new AgentHostException("establish-clan-autonomy-catalog-failed", "The integrated EYC scheduler must offer only objective routes that exist in the current Host build.");

        var allMet = (JsonObject)snapshot.DeepClone();
        foreach (var objective in AgentHostEstablishYourClanGoalLoop.ObjectiveIds)
            allMet[objective]!["met"] = true;
        if (AgentHostEstablishYourClanGoalLoop.BuildObjectiveActionCatalog(allMet, InitiallyIntegratedObjectives).Count != 0)
            throw new AgentHostException("establish-clan-autonomy-all-met-catalog-leaked", "The integrated EYC scheduler must not select an objective after all four authoritative Journal targets are met.");

        var unsupportedOnly = (JsonObject)snapshot.DeepClone();
        unsupportedOnly["gold"]!["met"] = true;
        unsupportedOnly["partySize"]!["met"] = true;
        unsupportedOnly["renown"]!["met"] = true;
        if (AgentHostEstablishYourClanGoalLoop.BuildObjectiveActionCatalog(unsupportedOnly, InitiallyIntegratedObjectives).Count != 0)
            throw new AgentHostException("establish-clan-autonomy-invented-route", "The scheduler must fail closed when only objectives without integrated Native executors remain.");

        var results = new List<object>
        {
            new { scenario = "establish-clan-autonomy-offers-only-integrated-unmet-objectives", passed = true },
            new { scenario = "establish-clan-autonomy-never-selects-unimplemented-or-met-objectives", passed = true }
        };

        var native = new FakeNativeClient(activeQuest: true, lifecycle: "active", initialGold: 100);
        var provider = new FakeObjectiveProvider("gold");
        var executorCalls = 0;
        var requestJson = """
            {"runId":"establish-clan-autonomy-selftest","goal":"Complete the active original Establish Your Clan quest.","parentProcessId":321,"maxDecisions":8,"maxElapsedSeconds":10,"allowedActionNames":[]}
            """;
        using var request = JsonDocument.Parse(requestJson);
        async Task<JsonObject> ExecuteObjective(string objectiveId, int priorDecisions, long priorPromptTokens, long priorCompletionTokens,
            JsonArray priorTrace, JsonArray priorRoutes, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            executorCalls++;
            if (objectiveId != "gold") throw new AgentHostException("autonomy-selftest-unexpected-objective", "The fake executor received an unexpected objective.");
            native.CompleteSuccessfully();
            return new JsonObject
            {
                ["status"] = "completed",
                ["decisions"] = priorDecisions,
                ["actionsExecuted"] = 1,
                ["promptTokens"] = priorPromptTokens,
                ["completionTokens"] = priorCompletionTokens,
                ["trace"] = priorTrace.DeepClone(),
                ["providerRouteHistory"] = priorRoutes.DeepClone(),
                ["termination"] = new JsonObject { ["reason"] = "one-native-objective-subflow-completed" }
            };
        }

        var completed = RunAsync(request.RootElement, native, native, provider, ExecuteObjective, CancellationToken.None).GetAwaiter().GetResult();
        if (ReadString(completed, "status") != "completed" ||
            ReadBoolean(completed["termination"] as JsonObject, "goalVerified") != true ||
            ReadInt(completed, "actionsExecuted", -1) != 1 || provider.CallCount != 1 || executorCalls != 1 || native.QuestDetailsReads != 1)
            throw new AgentHostException("establish-clan-autonomy-completion-selftest-failed", "The parent loop must re-read the Native Journal, execute the selected objective route, and only report completion after Native Quest history confirms success. result=" + completed.ToJsonString() + "; providerCalls=" + provider.CallCount + "; executorCalls=" + executorCalls + "; journalReads=" + native.QuestDetailsReads);
        results.Add(new { scenario = "establish-clan-autonomy-dispatches-selected-route-and-requires-native-quest-success", passed = true });

        var unverifiedNative = new FakeNativeClient(activeQuest: false, lifecycle: "unknown", initialGold: 100);
        var unverifiedProvider = new FakeObjectiveProvider("gold");
        var unverified = RunAsync(request.RootElement, unverifiedNative, unverifiedNative, unverifiedProvider, ExecuteObjective, CancellationToken.None).GetAwaiter().GetResult();
        if (ReadString(unverified, "status") != "failed" ||
            ReadString(unverified["termination"] as JsonObject, "reason") != "quest-no-longer-active-without-success-evidence" ||
            unverifiedProvider.CallCount != 0 || executorCalls != 1)
            throw new AgentHostException("establish-clan-autonomy-unverified-completion-accepted", "An inactive Quest without a successful Native history record must fail before model or objective execution.");
        results.Add(new { scenario = "establish-clan-autonomy-rejects-unverified-quest-termination", passed = true });
        return results;
    }

    internal static async Task<JsonObject> RunAsync(
        JsonElement request,
        IAgentHostCampaignNativeClient client,
        IAgentHostQuestDetailsNativeClient questDetailsClient,
        IAgentHostDecisionProvider provider,
        ObjectiveExecutor executeObjective,
        CancellationToken cancellationToken,
        int priorDecisions = 0,
        long priorPromptTokens = 0,
        long priorCompletionTokens = 0,
        JsonArray? priorTrace = null,
        JsonArray? priorProviderRouteHistory = null)
    {
        var runId = ReadString(request, "runId") ?? Guid.NewGuid().ToString("N");
        var maxDecisions = Math.Clamp(ReadInt(request, "maxDecisions", 160), 1, 160);
        var maxElapsedSeconds = Math.Clamp(ReadInt(request, "maxElapsedSeconds", 7200), 1, 7200);
        var trace = priorTrace?.DeepClone() as JsonArray ?? new JsonArray();
        var routes = priorProviderRouteHistory?.DeepClone() as JsonArray ?? new JsonArray();
        var decisions = priorDecisions;
        var nativeActions = 0;
        long promptTokens = priorPromptTokens;
        long completionTokens = priorCompletionTokens;
        var unavailableObjectives = new HashSet<string>(StringComparer.Ordinal);
        var objectiveRuns = new JsonArray();
        var start = Stopwatch.GetTimestamp();
        using var elapsed = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        elapsed.CancelAfter(TimeSpan.FromSeconds(maxElapsedSeconds));

        try
        {
            await provider.CheckConfiguredModelAsync(elapsed.Token);
            for (var cycle = 0; cycle < 20 && decisions < maxDecisions; cycle++)
            {
                elapsed.Token.ThrowIfCancellationRequested();
                using var current = await client.ReadStateAsync(elapsed.Token);
                var lifecycle = ReadLifecycleStatus(current.RootElement);
                if (!AgentHostEstablishYourClanGoalLoop.HasActiveQuest(current.RootElement))
                {
                    if (lifecycle == "completed")
                        return BuildResult("completed", "native-establish-your-clan-quest-success-verified", true, null, null,
                            completionEvidence: "Native lifecycle status storyModeEstablishClanStatus=completed");
                    return BuildResult("failed", "quest-no-longer-active-without-success-evidence", false,
                        "The original StoryMode quest is no longer active and Native history does not prove successful completion.", "establish-clan-native-success-unverified");
                }

                using var details = await questDetailsClient.ReadQuestDetailsAsync(QuestId, elapsed.Token);
                var detailsReceipt = JsonNode.Parse(details.RootElement.GetRawText())?.AsObject()
                    ?? throw new AgentHostException("establish-clan-autonomy-details-invalid", "The Native Quest Journal did not return a cloneable receipt.");
                var data = ReadQuestDetailsData(details.RootElement);
                var journalObjectives = AgentHostEstablishYourClanGoalLoop.BuildJournalObjectives(data);
                var snapshot = AgentHostEstablishYourClanGoalLoop.BuildObjectiveSnapshot(journalObjectives);
                var live = data["storyModeEstablishClan"] as JsonObject;
                var differences = live is null ? new JsonArray() : AgentHostEstablishYourClanGoalLoop.FindLiveMetricDifferences(live, journalObjectives);
                var allMet = AgentHostEstablishYourClanGoalLoop.ObjectiveIds.All(id => ReadBoolean(snapshot[id] as JsonObject, "met") == true);
                if (allMet)
                {
                    using var confirmState = await client.ReadStateAsync(elapsed.Token);
                    if (ReadLifecycleStatus(confirmState.RootElement) == "completed")
                        return BuildResult("completed", "native-establish-your-clan-quest-success-verified", true, null, null,
                            journalObjectives, snapshot, differences, completionEvidence: "Native lifecycle status storyModeEstablishClanStatus=completed");
                    return BuildResult("failed", "all-journal-targets-met-awaiting-native-quest-completion", false,
                        "All four Journal targets appear met, but fresh Native history has not yet proven original Quest completion.", "establish-clan-completion-unverified",
                        journalObjectives, snapshot, differences);
                }

                var selectableObjectives = new HashSet<string>(InitiallyIntegratedObjectives, StringComparer.Ordinal);
                selectableObjectives.ExceptWith(unavailableObjectives);
                var planner = await AgentHostEstablishYourClanGoalLoop.RunAsync(
                    request, client, questDetailsClient, provider, elapsed.Token,
                    priorDecisions: decisions,
                    priorPromptTokens: promptTokens,
                    priorCompletionTokens: completionTokens,
                    priorTrace: trace,
                    priorProviderRouteHistory: routes,
                    supportedObjectives: selectableObjectives,
                    observedQuestDetails: detailsReceipt,
                    activeQuestAlreadyVerified: true);
                decisions = ReadInt(planner, "decisions", decisions);
                promptTokens = ReadLong(planner, "promptTokens", promptTokens);
                completionTokens = ReadLong(planner, "completionTokens", completionTokens);
                trace = planner["trace"]?.DeepClone() as JsonArray ?? trace;
                routes = planner["providerRouteHistory"]?.DeepClone() as JsonArray ?? routes;

                var resultKind = ReadString(planner, "resultKind");
                if (resultKind == "no-implemented-objective-route")
                {
                    var unmet = AgentHostEstablishYourClanGoalLoop.ObjectiveIds
                        .Where(id => ReadBoolean(snapshot[id] as JsonObject, "met") == false).ToArray();
                    var unimplemented = new JsonArray(unmet
                        .Where(id => !InitiallyIntegratedObjectives.Contains(id))
                        .Select(id => (JsonNode?)JsonValue.Create(id)).ToArray());
                    var allIntegratedRoutesBlocked = unimplemented.Count == 0 && unavailableObjectives.Count > 0;
                    return BuildResult("failed", allIntegratedRoutesBlocked ? "no-current-integrated-route-available" : "objective-route-not-yet-integrated", false,
                        allIntegratedRoutesBlocked
                            ? "Every currently integrated objective route was rejected or unavailable in the fresh Native state; the quest remains active."
                            : "The current Host build has no integrated Native executor for every unmet objective; the quest remains active.",
                        allIntegratedRoutesBlocked ? "establish-clan-objective-routes-currently-unavailable" : "establish-clan-objective-route-unavailable",
                        journalObjectives, snapshot, differences, unimplemented);
                }

                if (ReadString(planner["selection"] as JsonObject, "objectiveId") is not string objectiveId ||
                    !selectableObjectives.Contains(objectiveId))
                    return BuildResult("failed", "objective-planner-did-not-select-supported-route", false,
                        "The objective planner did not choose one currently supported, unmet route.", "establish-clan-objective-selection-invalid",
                        journalObjectives, snapshot, differences);

                JsonObject child;
                child = await executeObjective(objectiveId, decisions, promptTokens, completionTokens, trace, routes, elapsed.Token);

                decisions = ReadInt(child, "decisions", decisions);
                promptTokens = ReadLong(child, "promptTokens", promptTokens);
                completionTokens = ReadLong(child, "completionTokens", completionTokens);
                nativeActions += ReadInt(child, "actionsExecuted", 0);
                trace = child["trace"]?.DeepClone() as JsonArray ?? trace;
                routes = child["providerRouteHistory"]?.DeepClone() as JsonArray ?? routes;
                objectiveRuns.Add(new JsonObject
                {
                    ["objectiveId"] = objectiveId,
                    ["status"] = ReadString(child, "status"),
                    ["termination"] = child["termination"]?.DeepClone(),
                    ["failureCode"] = child["failureCode"]?.DeepClone(),
                    ["actionsExecuted"] = ReadInt(child, "actionsExecuted", 0)
                });

                if (ReadString(child, "status") != "completed")
                {
                    var termination = ReadString(child, "termination") ?? ReadString(child["termination"] as JsonObject, "reason");
                    using var failedState = await client.ReadStateAsync(elapsed.Token);
                    var failedContext = failedState.RootElement.TryGetProperty("state", out var failedStateData) && failedStateData.ValueKind == JsonValueKind.Object &&
                                        failedStateData.TryGetProperty("context", out var contextData) && contextData.ValueKind == JsonValueKind.Object
                        ? contextData
                        : default;
                    var freeMap = failedContext.ValueKind == JsonValueKind.Object &&
                                  ReadString(failedContext, "gameState") == "MapState" &&
                                  !(failedContext.TryGetProperty("encounterActive", out var encounterActive) && encounterActive.ValueKind == JsonValueKind.True) &&
                                  !(failedContext.TryGetProperty("captivity", out var captivity) && captivity.ValueKind == JsonValueKind.Object &&
                                    captivity.TryGetProperty("isCaptive", out var captive) && captive.ValueKind == JsonValueKind.True);
                    if (objectiveId == "partySize" && freeMap && termination is ("native-journal-refresh-pending" or "recruitment-route-unavailable"))
                    {
                        unavailableObjectives.Add(objectiveId);
                        trace.Add(new JsonObject { ["stage"] = "objective-route-blocked", ["objectiveId"] = objectiveId, ["termination"] = termination, ["failureCode"] = ReadString(child, "failureCode") });
                        continue;
                    }
                    if (objectiveId == "renown" && termination == "no-safe-action" && freeMap)
                    {
                        unavailableObjectives.Add(objectiveId);
                        trace.Add(new JsonObject { ["stage"] = "objective-route-blocked", ["objectiveId"] = objectiveId, ["termination"] = termination, ["failureCode"] = ReadString(child, "failureCode") });
                        continue;
                    }
                    return BuildResult("failed", "objective-subflow-failed", false,
                        "A Native objective subflow failed; the parent did not claim progress or replay its actions.",
                        ReadString(child, "failureCode"), journalObjectives, snapshot, differences);
                }

                using var afterState = await client.ReadStateAsync(elapsed.Token);
                if (!AgentHostEstablishYourClanGoalLoop.HasActiveQuest(afterState.RootElement) && ReadLifecycleStatus(afterState.RootElement) == "completed")
                    return BuildResult("completed", "native-establish-your-clan-quest-success-verified", true, null, null,
                        completionEvidence: "Native lifecycle status storyModeEstablishClanStatus=completed; the previous objective snapshot is intentionally omitted as pre-action state");

                using var afterDetails = await questDetailsClient.ReadQuestDetailsAsync(QuestId, elapsed.Token);
                var afterData = ReadQuestDetailsData(afterDetails.RootElement);
                var afterJournal = AgentHostEstablishYourClanGoalLoop.BuildJournalObjectives(afterData);
                if (HasJournalProgressChanged(journalObjectives, afterJournal) || ReadInt(child, "actionsExecuted", 0) > 0)
                    unavailableObjectives.Clear();
                else
                    unavailableObjectives.Add(objectiveId);
            }

            var latestState = await client.ReadStateAsync(elapsed.Token);
            using (latestState)
            {
                using var latestDetails = await questDetailsClient.ReadQuestDetailsAsync(QuestId, elapsed.Token);
                var latestData = ReadQuestDetailsData(latestDetails.RootElement);
                var latestJournal = AgentHostEstablishYourClanGoalLoop.BuildJournalObjectives(latestData);
                return BuildResult("failed", "objective-or-decision-budget-exhausted", false,
                    "The bounded Host loop ended with the original StoryMode Quest still requiring Native objective progress.", "establish-clan-autonomy-budget-exhausted",
                    latestJournal, AgentHostEstablishYourClanGoalLoop.BuildObjectiveSnapshot(latestJournal), new JsonArray(),
                    UnimplementedObjectives(latestJournal));
            }
        }
        catch (OperationCanceledException)
        {
            return BuildResult("failed", "host-stop-or-time-budget", false,
                cancellationToken.IsCancellationRequested ? "The Host stop signal ended the loop; Native state was not reported as completed." : "The shared autonomous Campaign loop exceeded its elapsed-time budget.",
                cancellationToken.IsCancellationRequested ? "host-stop-requested" : "establish-clan-autonomy-timeout");
        }
        catch (AgentHostException exception)
        {
            return BuildResult("failed", "autonomy-loop-failed", false, exception.Message, exception.Code);
        }
        catch (Exception exception)
        {
            return BuildResult("failed", "autonomy-loop-failed", false, exception.GetType().Name, "establish-clan-autonomy-unexpected-error");
        }

        JsonObject BuildResult(string status, string reason, bool goalVerified, string? failure, string? failureCode,
            JsonArray? journal = null, JsonObject? snapshotResult = null, JsonArray? metricDifferences = null, JsonArray? unimplemented = null,
            string? completionEvidence = null)
        {
            var elapsedSeconds = Stopwatch.GetElapsedTime(start).TotalSeconds;
            return new JsonObject
            {
                ["status"] = status,
                ["resultKind"] = "storymode-establish-your-clan-autonomy-loop",
                ["runId"] = runId,
                ["providerModelId"] = provider.ModelId,
                ["providerConfigurationSource"] = provider.ConfigurationSource,
                ["decisions"] = decisions,
                ["actionsExecuted"] = nativeActions,
                ["promptTokens"] = promptTokens,
                ["completionTokens"] = completionTokens,
                ["elapsedSeconds"] = Math.Round(elapsedSeconds, 3),
                ["providerRouteHistory"] = routes.DeepClone(),
                ["trace"] = trace.DeepClone(),
                ["objectiveRuns"] = objectiveRuns.DeepClone(),
                ["unavailableObjectiveIds"] = new JsonArray(unavailableObjectives.Select(id => (JsonNode?)JsonValue.Create(id)).ToArray()),
                ["journalObjectiveSnapshot"] = journal?.DeepClone(),
                ["objectiveSnapshot"] = snapshotResult?.DeepClone(),
                ["liveMetricDifferences"] = metricDifferences?.DeepClone(),
                ["unimplementedObjectives"] = unimplemented?.DeepClone() ?? new JsonArray(),
                ["completionEvidence"] = completionEvidence,
                ["termination"] = new JsonObject { ["reason"] = reason, ["completedByProvider"] = false, ["goalVerified"] = goalVerified },
                ["failure"] = failure,
                ["failureCode"] = failureCode
            };
        }
    }

    private static bool HasJournalProgressChanged(JsonArray before, JsonArray after)
    {
        foreach (var objectiveId in AgentHostEstablishYourClanGoalLoop.ObjectiveIds)
        {
            var oldStage = before.OfType<JsonObject>().FirstOrDefault(stage => ReadString(stage, "objectiveId") == objectiveId);
            var newStage = after.OfType<JsonObject>().FirstOrDefault(stage => ReadString(stage, "objectiveId") == objectiveId);
            if (ReadDouble(newStage, "current") != ReadDouble(oldStage, "current") || ReadDouble(newStage, "target") != ReadDouble(oldStage, "target"))
                return true;
        }
        return false;
    }

    private static JsonObject ReadQuestDetailsData(JsonElement receipt)
    {
        var node = JsonNode.Parse(receipt.GetRawText())?.AsObject();
        if (ReadString(node, "status") != "completed" || node?["data"] is not JsonObject data || ReadString(data, "questId") != QuestId)
            throw new AgentHostException("establish-clan-progress-unavailable", "The fresh Native Quest Journal did not expose the exact active StoryMode quest.");
        return data;
    }

    private static string? ReadLifecycleStatus(JsonElement native)
    {
        if (!native.TryGetProperty("state", out var state) || state.ValueKind != JsonValueKind.Object ||
            !state.TryGetProperty("storyModeEstablishClanStatus", out var status) || status.ValueKind != JsonValueKind.Object ||
            !status.TryGetProperty("status", out var value) || value.ValueKind != JsonValueKind.String) return null;
        return value.GetString();
    }

    private static JsonArray UnimplementedObjectives(JsonArray journal)
    {
        var result = new JsonArray();
        foreach (var objective in journal.OfType<JsonObject>())
        {
            var id = ReadString(objective, "objectiveId");
            if (id is not null && !InitiallyIntegratedObjectives.Contains(id) && ReadDouble(objective, "current") < ReadDouble(objective, "target"))
                result.Add(JsonValue.Create(id));
        }
        return result;
    }

    private static bool ReadBoolean(JsonObject? node, string name) => node?[name] is JsonValue value && value.TryGetValue<bool>(out var result) && result;
    private static string? ReadString(JsonObject? node, string name) => node?[name] is JsonValue value && value.TryGetValue<string>(out var result) ? result : null;
    private static string? ReadString(JsonElement element, string name) => element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;
    private static int ReadInt(JsonElement element, string name, int fallback) => element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var value) && value.TryGetInt32(out var result) ? result : fallback;
    private static int ReadInt(JsonObject? node, string name, int fallback) => node?[name] is JsonValue value && value.TryGetValue<int>(out var result) ? result : fallback;
    private static long ReadLong(JsonObject? node, string name, long fallback) => node?[name] is JsonValue value && value.TryGetValue<long>(out var result) ? result : fallback;
    private static double ReadDouble(JsonObject? node, string name) => node?[name] is JsonValue value && value.TryGetValue<double>(out var result) ? result : double.NaN;

    private sealed class FakeNativeClient(bool activeQuest, string lifecycle, int initialGold) : IAgentHostCampaignNativeClient, IAgentHostQuestDetailsNativeClient
    {
        private bool _activeQuest = activeQuest;
        private string _lifecycle = lifecycle;
        private int _gold = initialGold;
        internal int QuestDetailsReads { get; private set; }

        internal void CompleteSuccessfully()
        {
            _gold = 2000;
            _activeQuest = false;
            _lifecycle = "completed";
        }

        public Task<JsonDocument> ReadStateAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var quests = new JsonArray();
            if (_activeQuest) quests.Add(new JsonObject { ["id"] = QuestId });
            var state = new JsonObject
            {
                ["context"] = new JsonObject { ["gameState"] = "MapState", ["captivity"] = new JsonObject { ["isCaptive"] = false } },
                ["quests"] = quests,
                ["storyModeEstablishClanStatus"] = new JsonObject { ["status"] = _lifecycle }
            };
            return Task.FromResult(JsonDocument.Parse(new JsonObject { ["status"] = "completed", ["state"] = state }.ToJsonString()));
        }

        public Task<JsonDocument> ReadQuestDetailsAsync(string questId, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            QuestDetailsReads++;
            if (questId != QuestId) throw new AgentHostException("autonomy-selftest-quest-id-invalid", "The fake Native client received a different Quest id.");
            var journal = new JsonArray(
                Objective("gold", _gold, 2000),
                Objective("partySize", 20, 20),
                Objective("renown", 50, 50),
                Objective("companions", 1, 1));
            var live = new JsonObject
            {
                ["gold"] = new JsonObject { ["current"] = _gold, ["target"] = 2000, ["met"] = _gold >= 2000 },
                ["partySize"] = new JsonObject { ["current"] = 20, ["target"] = 20, ["met"] = true },
                ["renown"] = new JsonObject { ["current"] = 50, ["target"] = 50, ["met"] = true },
                ["companions"] = new JsonObject { ["current"] = 1, ["target"] = 1, ["met"] = true }
            };
            var data = new JsonObject { ["questId"] = QuestId, ["title"] = "Establish Your Clan", ["journalStages"] = journal, ["storyModeEstablishClan"] = live };
            return Task.FromResult(JsonDocument.Parse(new JsonObject { ["status"] = "completed", ["data"] = data }.ToJsonString()));
        }

        public Task<JsonDocument> ExecuteCampaignActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken) =>
            throw new AgentHostException("autonomy-selftest-unexpected-native-action", "The fake parent-loop test injects the objective executor and must not directly send Native actions.");

        private static JsonObject Objective(string id, int current, int target) => new()
        {
            ["hasTask"] = true,
            ["currentProgress"] = current,
            ["targetProgress"] = target,
            ["description"] = id
        };
    }

    private sealed class FakeObjectiveProvider(string selectedObjective) : IAgentHostDecisionProvider
    {
        internal int CallCount { get; private set; }
        public string ModelId => "deterministic-establish-clan-autonomy-selftest";
        public string ConfigurationSource => "harness-fake-provider";
        public Task CheckConfiguredModelAsync(CancellationToken cancellationToken) => Task.CompletedTask;
        public Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            CallCount++;
            return Task.FromResult(new ProviderDecisionResult("completed", ModelId, null, null, "self-test", new JsonObject
            {
                ["action"] = "selectEstablishYourClanObjective",
                ["arguments"] = new JsonObject { ["ObjectiveId"] = selectedObjective },
                ["rationale"] = "Choose the currently unmet integrated objective."
            }));
        }
        public void Dispose() { }
    }
}
