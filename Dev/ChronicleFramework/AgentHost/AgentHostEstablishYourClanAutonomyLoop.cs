using System.Diagnostics;
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal static class AgentHostEstablishYourClanAutonomyLoop
{
    private const string QuestId = "rebuild_player_clan_storymode_quest";
    internal static readonly HashSet<string> InitiallyIntegratedObjectives = new(StringComparer.Ordinal) { "gold", "partySize", "renown", "companions" };

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
        if (selectable is null || selectable.Count != 4 ||
            !selectable.Any(value => value?.GetValue<string>() == "gold") ||
            !selectable.Any(value => value?.GetValue<string>() == "partySize") ||
            !selectable.Any(value => value?.GetValue<string>() == "renown") ||
            !selectable.Any(value => value?.GetValue<string>() == "companions"))
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
        unsupportedOnly["companions"]!["met"] = true;
        if (AgentHostEstablishYourClanGoalLoop.BuildObjectiveActionCatalog(unsupportedOnly, InitiallyIntegratedObjectives).Count != 0)
            throw new AgentHostException("establish-clan-autonomy-invented-route", "The scheduler must fail closed when only objectives without integrated Native executors remain.");

        var results = new List<object>
        {
            new { scenario = "establish-clan-autonomy-offers-only-integrated-unmet-objectives", passed = true },
            new { scenario = "establish-clan-autonomy-never-selects-unimplemented-or-met-objectives", passed = true }
        };
        if (!IsSafeObjectiveRouteUnavailable("companions", "companion-model-stopped", freeMap: true) ||
            IsSafeObjectiveRouteUnavailable("companions", "companion-model-stopped", freeMap: false) ||
            IsSafeObjectiveRouteUnavailable("gold", "companion-model-stopped", freeMap: true))
            throw new AgentHostException("establish-clan-autonomy-safe-stop-replan-policy-failed", "A safe Companion stop may mark only that route unavailable on a free Map; it must not hide an unrelated failure or encounter/captive state.");
        results.Add(new { scenario = "establish-clan-autonomy-safe-companion-stop-marks-route-unavailable-and-allows-replan", passed = true });

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

        var captiveNative = new FakeNativeClient(activeQuest: true, lifecycle: "active", initialGold: 100, initialCaptive: true);
        var captiveProvider = new FakeObjectiveProvider("gold");
        var captiveObjectiveOrder = new List<string>();
        async Task<JsonObject> RecoverBeforeObjective(string objectiveId, int priorDecisions, long priorPromptTokens, long priorCompletionTokens,
            JsonArray priorTrace, JsonArray priorRoutes, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            captiveObjectiveOrder.Add(objectiveId);
            if (objectiveId == "captivityRecovery")
            {
                if (captiveProvider.CallCount != 0) throw new AgentHostException("autonomy-selftest-objective-ran-before-captivity-recovery", "The parent must route current Native captivity before planning a StoryMode objective.");
                captiveNative.LeaveCaptivity();
                return new JsonObject
                {
                    ["status"] = "completed", ["captivityRecoveryVerified"] = true,
                    ["decisions"] = priorDecisions, ["actionsExecuted"] = 1,
                    ["promptTokens"] = priorPromptTokens, ["completionTokens"] = priorCompletionTokens,
                    ["trace"] = priorTrace.DeepClone(), ["providerRouteHistory"] = priorRoutes.DeepClone(),
                    ["termination"] = new JsonObject { ["reason"] = "captivity-recovered-return-to-parent" }
                };
            }
            if (objectiveId != "gold" || !captiveNative.IsFree)
                throw new AgentHostException("autonomy-selftest-objective-after-recovery-invalid", "The objective executor must run only after the fresh Native state shows the Hero free.");
            captiveNative.CompleteSuccessfully();
            return new JsonObject
            {
                ["status"] = "completed", ["decisions"] = priorDecisions, ["actionsExecuted"] = 1,
                ["promptTokens"] = priorPromptTokens, ["completionTokens"] = priorCompletionTokens,
                ["trace"] = priorTrace.DeepClone(), ["providerRouteHistory"] = priorRoutes.DeepClone(),
                ["termination"] = new JsonObject { ["reason"] = "one-native-objective-subflow-completed" }
            };
        }
        var recovered = RunAsync(request.RootElement, captiveNative, captiveNative, captiveProvider, RecoverBeforeObjective, CancellationToken.None).GetAwaiter().GetResult();
        if (ReadString(recovered, "status") != "completed" || ReadInt(recovered, "actionsExecuted", -1) != 2 ||
            captiveProvider.CallCount != 1 || !captiveObjectiveOrder.SequenceEqual(new[] { "captivityRecovery", "gold" }, StringComparer.Ordinal))
            throw new AgentHostException("establish-clan-autonomy-captivity-dispatch-selftest-failed", "An already-captive MainHero must recover through the current Native captivity subflow before the parent plans or executes an unmet objective.");
        results.Add(new { scenario = "establish-clan-autonomy-recovers-current-captivity-before-replanning-objectives", passed = true });

        var unverifiedNative = new FakeNativeClient(activeQuest: false, lifecycle: "unknown", initialGold: 100);
        var unverifiedProvider = new FakeObjectiveProvider("gold");
        var unverified = RunAsync(request.RootElement, unverifiedNative, unverifiedNative, unverifiedProvider, ExecuteObjective, CancellationToken.None).GetAwaiter().GetResult();
        if (ReadString(unverified, "status") != "failed" ||
            ReadString(unverified["termination"] as JsonObject, "reason") != "quest-no-longer-active-without-success-evidence" ||
            unverifiedProvider.CallCount != 0 || executorCalls != 1)
            throw new AgentHostException("establish-clan-autonomy-unverified-completion-accepted", "An inactive Quest without a successful Native history record must fail before model or objective execution.");
        results.Add(new { scenario = "establish-clan-autonomy-rejects-unverified-quest-termination", passed = true });

        var modalNative = new FakeNativeClient(activeQuest: true, lifecycle: "active", initialGold: 100);
        var modalProvider = new FakeInquiryRecoveryProvider();
        var interruptedObjectiveCalls = 0;
        async Task<JsonObject> RecoverInterruptedObjective(string objectiveId, int priorDecisions, long priorPromptTokens, long priorCompletionTokens,
            JsonArray priorTrace, JsonArray priorRoutes, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (objectiveId != "gold") throw new AgentHostException("autonomy-selftest-modal-objective-invalid", "The modal-recovery fixture must remain on the current Gold objective.");
            interruptedObjectiveCalls++;
            if (interruptedObjectiveCalls == 1)
            {
                modalNative.OpenInquiry();
                return new JsonObject
                {
                    ["status"] = "failed", ["actionsExecuted"] = 1, ["decisions"] = priorDecisions,
                    ["promptTokens"] = priorPromptTokens, ["completionTokens"] = priorCompletionTokens,
                    ["trace"] = priorTrace.DeepClone(), ["providerRouteHistory"] = priorRoutes.DeepClone(),
                    ["termination"] = new JsonObject { ["reason"] = "no-safe-action" },
                    ["failureCode"] = "gold-sale-free-map-required"
                };
            }
            if (interruptedObjectiveCalls != 2 || modalNative.InquiryOpen || modalProvider.CallCount != 3)
                throw new AgentHostException("autonomy-selftest-modal-replayed-before-fresh-plan", "After an interrupted child has already acted, the Host must resolve the current Native modal and obtain a fresh parent-model plan before invoking any objective executor again.");
            modalNative.CompleteSuccessfully();
            return new JsonObject
            {
                ["status"] = "completed", ["actionsExecuted"] = 1, ["decisions"] = priorDecisions,
                ["promptTokens"] = priorPromptTokens, ["completionTokens"] = priorCompletionTokens,
                ["trace"] = priorTrace.DeepClone(), ["providerRouteHistory"] = priorRoutes.DeepClone(),
                ["termination"] = new JsonObject { ["reason"] = "one-native-objective-subflow-completed" }
            };
        }
        var modalRecovered = RunAsync(request.RootElement, modalNative, modalNative, modalProvider, RecoverInterruptedObjective, CancellationToken.None).GetAwaiter().GetResult();
        if (ReadString(modalRecovered, "status") != "completed" || ReadInt(modalRecovered, "actionsExecuted", 0) != 3 ||
            modalProvider.CallCount != 3 || interruptedObjectiveCalls != 2 || modalNative.LastInquiryChoice != "affirmative" ||
            modalNative.LastInquiryToken != "inquiry-token" ||
            !((modalRecovered["trace"] as JsonArray)?.OfType<JsonObject>().Any(step =>
                ReadString(step, "stage") == "objective-replanned-after-native-inquiry" &&
                ReadInt(step, "childActionsExecuted", -1) == 1 &&
                !ReadBoolean(step, "replayedChildActions")) ?? false))
            throw new AgentHostException("establish-clan-autonomy-native-inquiry-recovery-selftest-failed", "A failed objective that already sent a Native action may resolve the current inquiry, but only a fresh parent-model decision may choose the next objective action; no child action is silently resumed.");
        results.Add(new { scenario = "establish-clan-autonomy-model-resolves-native-modal-after-prior-action-then-replans-from-fresh-state", passed = true });
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
            using (var initialState = await client.ReadStateAsync(elapsed.Token))
            {
                var initialQuestActive = AgentHostEstablishYourClanGoalLoop.HasActiveQuest(initialState.RootElement);
                var initialLifecycle = ReadLifecycleStatus(initialState.RootElement);
                if (!initialQuestActive && initialLifecycle == "completed")
                    return BuildResult("completed", "native-establish-your-clan-quest-success-verified", true, null, null,
                        completionEvidence: "Native lifecycle status storyModeEstablishClanStatus=completed before objective execution");

                // The tutorial-skip branch can naturally activate EYC before the first
                // settled MapState, while the player still remains in training_field_menu.
                // Run the same Native Leave action for both pre-activation and active-EYC
                // states; do not let a subgoal-specific model prompt infer this bootstrap.
                if (AgentHostStoryModeBootstrapLoop.IsEligibleTrainingFieldBootstrapState(initialState.RootElement))
                {
                    if (client is not IAgentHostStoryModeBootstrapNativeClient bootstrapClient)
                        return BuildResult("failed", "storymode-bootstrap-native-client-unavailable", false,
                            "The Native transport cannot submit the visible original training-field menu option.", "storymode-bootstrap-native-client-unavailable");

                    var bootstrap = await AgentHostStoryModeBootstrapLoop.RunAsync(request, client, bootstrapClient, provider, elapsed.Token,
                        priorDecisions: decisions, priorPromptTokens: promptTokens, priorCompletionTokens: completionTokens,
                        priorTrace: trace, priorProviderRouteHistory: routes);
                    decisions = ReadInt(bootstrap, "decisions", decisions);
                    promptTokens = ReadLong(bootstrap, "promptTokens", promptTokens);
                    completionTokens = ReadLong(bootstrap, "completionTokens", completionTokens);
                    nativeActions += ReadInt(bootstrap, "actionsExecuted", 0);
                    trace = bootstrap["trace"]?.DeepClone() as JsonArray ?? trace;
                    routes = bootstrap["providerRouteHistory"]?.DeepClone() as JsonArray ?? routes;

                    if (ReadString(bootstrap, "status") != "completed")
                        return BuildResult("failed", "storymode-bootstrap-failed", false,
                            ReadString(bootstrap, "failure") ?? "The Native StoryMode training-field exit did not verify a usable map and active EYC quest.",
                            ReadString(bootstrap, "failureCode") ?? "storymode-bootstrap-failed");

                    using var afterBootstrap = await client.ReadStateAsync(elapsed.Token);
                    if (!AgentHostEstablishYourClanGoalLoop.HasActiveQuest(afterBootstrap.RootElement) ||
                        !AgentHostStoryModeBootstrapLoop.HasLeftTrainingField(afterBootstrap.RootElement))
                        return BuildResult("failed", "storymode-bootstrap-postcondition-unverified", false,
                            "The bootstrap reported completion but fresh Native state does not show the player outside the training-field menu with the original EYC quest active.",
                            "storymode-bootstrap-active-quest-unverified");
                }
                else if (!initialQuestActive)
                    return BuildResult("failed", "quest-no-longer-active-without-success-evidence", false,
                        "The original StoryMode quest is no longer active and Native history does not prove successful completion.",
                        "establish-clan-native-success-unverified");
            }

            if (client is IAgentHostNativeInquiryClient startupInquiryClient && client is IAgentHostStoryModeBannerEditorNativeClient startupBannerEditorClient)
            {
                var setup = await AgentHostStoryModeSetupLoop.RunAsync(request, client, startupInquiryClient, startupBannerEditorClient, provider, elapsed.Token,
                    decisions, promptTokens, completionTokens, trace, routes);
                decisions = ReadInt(setup, "decisions", decisions);
                promptTokens = ReadLong(setup, "promptTokens", promptTokens);
                completionTokens = ReadLong(setup, "completionTokens", completionTokens);
                nativeActions += ReadInt(setup, "actionsExecuted", 0);
                trace = setup["trace"]?.DeepClone() as JsonArray ?? trace;
                routes = setup["providerRouteHistory"]?.DeepClone() as JsonArray ?? routes;
                if (ReadString(setup, "status") == "failed")
                    return BuildResult("failed", "storymode-initial-setup-failed", false,
                        ReadString(setup, "failure") ?? "The original StoryMode family-name/BannerEditor setup could not be completed.",
                        ReadString(setup, "failureCode"));
                if (ReadString(setup, "status") == "completed")
                    trace.Add(new JsonObject { ["stage"] = "storymode-initial-setup-completed", ["termination"] = setup["termination"]?.DeepClone() });
            }

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

                if (IsPlayerCaptive(current.RootElement))
                {
                    var recovery = await executeObjective("captivityRecovery", decisions, promptTokens, completionTokens, trace, routes, elapsed.Token);
                    decisions = ReadInt(recovery, "decisions", decisions);
                    promptTokens = ReadLong(recovery, "promptTokens", promptTokens);
                    completionTokens = ReadLong(recovery, "completionTokens", completionTokens);
                    nativeActions += ReadInt(recovery, "actionsExecuted", 0);
                    trace = recovery["trace"]?.DeepClone() as JsonArray ?? trace;
                    routes = recovery["providerRouteHistory"]?.DeepClone() as JsonArray ?? routes;
                    objectiveRuns.Add(new JsonObject
                    {
                        ["objectiveId"] = "captivityRecovery",
                        ["status"] = ReadString(recovery, "status"),
                        ["termination"] = recovery["termination"]?.DeepClone(),
                        ["captivityRecoveryVerified"] = ReadBoolean(recovery, "captivityRecoveryVerified"),
                        ["actionsExecuted"] = ReadInt(recovery, "actionsExecuted", 0)
                    });
                    if (ReadString(recovery, "status") != "completed" || !ReadBoolean(recovery, "captivityRecoveryVerified"))
                        return BuildResult("failed", "captivity-recovery-subflow-failed", false,
                            "The MainHero is captive; the Host did not resume objective planning because Native captivity recovery was not verified.",
                            ReadString(recovery, "failureCode"));
                    using var recoveredState = await client.ReadStateAsync(elapsed.Token);
                    if (IsPlayerCaptive(recoveredState.RootElement))
                        return BuildResult("failed", "captivity-recovery-native-state-still-captive", false,
                            "The recovery subflow returned but the fresh Native state still marks MainHero captive; no ordinary objective action was attempted.",
                            "captivity-recovery-native-state-still-captive");
                    continue;
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
                AgentHostHarnessProgressTrace.RecordObjectiveSubflowResult(objectiveId, child);

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

                    // A child objective can stop when a Native modal appears, either before or
                    // after other Native actions. Resolve only the current supported prompt;
                    // then let the parent read the current Journal/state and ask the model to
                    // replan. The failed child is never resumed automatically.
                    var interruptedChildActions = ReadInt(child, "actionsExecuted", 0);
                    var storySetupVisible = failedContext.ValueKind == JsonValueKind.Object &&
                        ((failedContext.TryGetProperty("gameState", out var setupGameState) && setupGameState.ValueKind == JsonValueKind.String && setupGameState.GetString() == "BannerEditorState") ||
                         (failedContext.TryGetProperty("sceneNotification", out var setupScene) && setupScene.ValueKind == JsonValueKind.Object &&
                          setupScene.TryGetProperty("hasActiveNotification", out var setupSceneActive) && setupSceneActive.ValueKind == JsonValueKind.True) ||
                         (failedContext.TryGetProperty("inquiry", out var setupInquiry) && setupInquiry.ValueKind == JsonValueKind.Object &&
                          ((setupInquiry.TryGetProperty("kind", out var setupInquiryKind) && setupInquiryKind.ValueKind == JsonValueKind.String && setupInquiryKind.GetString() == "StoryModeClanNameTextInquiry") ||
                           (setupInquiry.TryGetProperty("storyModeStartupKind", out var startupKind) && startupKind.ValueKind == JsonValueKind.String))));
                    if (storySetupVisible && client is IAgentHostNativeInquiryClient storySetupInquiryClient &&
                        client is IAgentHostStoryModeBannerEditorNativeClient storySetupBannerClient)
                    {
                        var setup = await AgentHostStoryModeSetupLoop.RunAsync(request, client, storySetupInquiryClient, storySetupBannerClient, provider, elapsed.Token,
                            decisions, promptTokens, completionTokens, trace, routes);
                        decisions = ReadInt(setup, "decisions", decisions);
                        promptTokens = ReadLong(setup, "promptTokens", promptTokens);
                        completionTokens = ReadLong(setup, "completionTokens", completionTokens);
                        nativeActions += ReadInt(setup, "actionsExecuted", 0);
                        trace = setup["trace"]?.DeepClone() as JsonArray ?? trace;
                        routes = setup["providerRouteHistory"]?.DeepClone() as JsonArray ?? routes;
                        if (ReadString(setup, "status") == "failed")
                            return BuildResult("failed", "storymode-setup-interrupted-objective", false,
                                ReadString(setup, "failure") ?? "The original StoryMode name/banner setup could not be completed after the current objective interruption.",
                                ReadString(setup, "failureCode"));
                        if (ReadString(setup, "status") == "completed")
                        {
                            using var resumedAfterStorySetup = await client.ReadStateAsync(elapsed.Token);
                            if (AgentHostEstablishYourClanGoalLoop.HasActiveQuest(resumedAfterStorySetup.RootElement) &&
                                !IsPlayerCaptive(resumedAfterStorySetup.RootElement))
                            {
                                trace.Add(new JsonObject
                                {
                                    ["stage"] = "objective-replanned-after-storymode-setup",
                                    ["objectiveId"] = objectiveId,
                                    ["childActionsExecuted"] = interruptedChildActions,
                                    ["replayedChildActions"] = false
                                });
                                continue;
                            }
                            return BuildResult("failed", "storymode-setup-return-state-unverified", false,
                                "The StoryMode setup callback completed but fresh Native state did not show the active EYC Campaign outside captivity.",
                                "storymode-setup-return-state-unverified");
                        }
                    }
                    if (failedContext.ValueKind == JsonValueKind.Object &&
                        failedContext.TryGetProperty("inquiryOpen", out var inquiryOpen) && inquiryOpen.ValueKind == JsonValueKind.True)
                    {
                        if (client is not IAgentHostNativeInquiryClient inquiryClient)
                            return BuildResult("failed", "native-inquiry-client-unavailable", false,
                                "A Native inquiry blocks the Campaign map and this Host transport cannot answer it.", "native-inquiry-client-unavailable",
                                journalObjectives, snapshot, differences);

                        var resolution = await AgentHostNativeInquiryResolution.RunAsync(
                            client, inquiryClient, provider, elapsed.Token,
                            runId + "-inquiry-" + (decisions + 1).ToString(CultureInfo.InvariantCulture));
                        decisions += ReadInt(resolution, "decisions", 0);
                        promptTokens += ReadLong(resolution, "promptTokens", 0);
                        completionTokens += ReadLong(resolution, "completionTokens", 0);
                        nativeActions += ReadInt(resolution, "actionsExecuted", 0);
                        if (resolution["providerRoute"] is JsonObject inquiryRoute)
                            routes.Add(inquiryRoute.DeepClone());
                        trace.Add(new JsonObject
                        {
                            ["stage"] = "native-inquiry-resolution",
                            ["objectiveId"] = objectiveId,
                            ["status"] = ReadString(resolution, "status"),
                            ["choice"] = ReadString(resolution, "choice"),
                            ["failureCode"] = ReadString(resolution, "failureCode"),
                            ["decision"] = resolution["decision"]?.DeepClone(),
                            ["nativeReceipt"] = resolution["nativeReceipt"]?.DeepClone(),
                            ["nativeStateAfter"] = resolution["nativeStateAfter"]?.DeepClone()
                        });

                        if (ReadString(resolution, "status") == "resolved")
                        {
                            using var afterInquiry = await client.ReadStateAsync(elapsed.Token);
                            var afterContext = afterInquiry.RootElement.TryGetProperty("state", out var inquiryAfterStateNode) && inquiryAfterStateNode.ValueKind == JsonValueKind.Object &&
                                               inquiryAfterStateNode.TryGetProperty("context", out var afterContextValue) && afterContextValue.ValueKind == JsonValueKind.Object
                                ? afterContextValue
                                : default;
                            var inquiryClosedOnFreeMap = afterContext.ValueKind == JsonValueKind.Object &&
                                ReadString(afterContext, "gameState") == "MapState" &&
                                !(afterContext.TryGetProperty("inquiryOpen", out var stillOpen) && stillOpen.ValueKind == JsonValueKind.True) &&
                                !(afterContext.TryGetProperty("encounterActive", out var nextEncounter) && nextEncounter.ValueKind == JsonValueKind.True) &&
                                !IsPlayerCaptive(afterInquiry.RootElement) &&
                                AgentHostEstablishYourClanGoalLoop.HasActiveQuest(afterInquiry.RootElement);
                            if (inquiryClosedOnFreeMap)
                            {
                                trace.Add(new JsonObject
                                {
                                    ["stage"] = "objective-replanned-after-native-inquiry",
                                    ["objectiveId"] = objectiveId,
                                    ["childActionsExecuted"] = interruptedChildActions,
                                    ["replayedChildActions"] = false
                                });
                                continue;
                            }
                        }

                        return BuildResult("failed", "native-inquiry-resolution-failed", false,
                            ReadString(resolution, "failure") ?? "The current Native inquiry was not safely resolved to a free Campaign Map.",
                            ReadString(resolution, "failureCode") ?? "native-inquiry-resolution-failed",
                            journalObjectives, snapshot, differences);
                    }

                    if (IsSafeObjectiveRouteUnavailable(objectiveId, termination, freeMap))
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

    internal static bool IsSafeObjectiveRouteUnavailable(string objectiveId, string? termination, bool freeMap)
    {
        if (!freeMap) return false;
        if (objectiveId is "partySize" or "companions")
            return termination is "native-journal-refresh-pending" or "recruitment-route-unavailable" or "companion-route-unavailable" or "companion-model-stopped";
        return objectiveId == "renown" && termination == "no-safe-action";
    }

    private static bool IsPlayerCaptive(JsonElement native) => native.ValueKind == JsonValueKind.Object &&
        native.TryGetProperty("state", out var state) && state.ValueKind == JsonValueKind.Object &&
        state.TryGetProperty("context", out var context) && context.ValueKind == JsonValueKind.Object &&
        context.TryGetProperty("captivity", out var captivity) && captivity.ValueKind == JsonValueKind.Object &&
        captivity.TryGetProperty("isCaptive", out var isCaptive) && isCaptive.ValueKind == JsonValueKind.True;

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

    private sealed class FakeNativeClient(bool activeQuest, string lifecycle, int initialGold, bool initialCaptive = false) : IAgentHostCampaignNativeClient, IAgentHostQuestDetailsNativeClient, IAgentHostNativeInquiryClient
    {
        private bool _activeQuest = activeQuest;
        private string _lifecycle = lifecycle;
        private int _gold = initialGold;
        internal bool IsFree => !_captive;
        private bool _captive = initialCaptive;
        private bool _inquiryOpen;
        internal bool InquiryOpen => _inquiryOpen;
        internal string? LastInquiryChoice { get; private set; }
        internal string? LastInquiryToken { get; private set; }
        internal int QuestDetailsReads { get; private set; }

        internal void CompleteSuccessfully()
        {
            _gold = 2000;
            _activeQuest = false;
            _lifecycle = "completed";
        }

        internal void LeaveCaptivity() => _captive = false;
        internal void OpenInquiry() => _inquiryOpen = true;

        public Task<JsonDocument> ReadStateAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var quests = new JsonArray();
            if (_activeQuest) quests.Add(new JsonObject { ["id"] = QuestId });
            var state = new JsonObject
            {
                ["context"] = new JsonObject
                {
                    ["gameState"] = "MapState", ["captivity"] = new JsonObject { ["isCaptive"] = _captive },
                    ["inquiryOpen"] = _inquiryOpen,
                    ["inquiry"] = _inquiryOpen ? new JsonObject
                    {
                        ["supported"] = true, ["kind"] = "YesNoInquiry", ["token"] = "inquiry-token",
                        ["title"] = "通知", ["text"] = "训练场结束通知",
                        ["affirmative"] = new JsonObject { ["visible"] = true, ["enabled"] = true, ["text"] = "好" },
                        ["negative"] = new JsonObject { ["visible"] = false, ["enabled"] = false, ["text"] = "" }
                    } : null
                },
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

        public Task<JsonDocument> RespondNativeInquiryAsync(string token, string choice, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (!_inquiryOpen || token != "inquiry-token" || choice is not ("affirmative" or "negative"))
                throw new AgentHostException("autonomy-selftest-native-inquiry-invalid", "The parent sent a stale prompt token or a choice outside the Native Yes/No contract.");
            LastInquiryToken = token;
            LastInquiryChoice = choice;
            _inquiryOpen = false;
            return Task.FromResult(JsonDocument.Parse("{\"status\":\"completed\",\"action\":\"respondInquiry\"}"));
        }

        public Task<JsonDocument> SubmitStoryModeClanNameAsync(string token, string clanName, CancellationToken cancellationToken) =>
            throw new AgentHostException("autonomy-selftest-unexpected-clan-name", "The autonomy parent fake does not expect a StoryMode clan-name TextInquiry.");

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

    private sealed class FakeInquiryRecoveryProvider : IAgentHostDecisionProvider
    {
        internal int CallCount { get; private set; }
        public string ModelId => "deterministic-native-inquiry-recovery-selftest";
        public string ConfigurationSource => "harness-fake-provider";
        public Task CheckConfiguredModelAsync(CancellationToken cancellationToken) => Task.CompletedTask;
        public Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            CallCount++;
            var isInquiry = systemPrompt.Contains("currently visible to the player", StringComparison.Ordinal);
            var decision = isInquiry
                ? new JsonObject { ["action"] = "respondInquiry", ["arguments"] = new JsonObject { ["choice"] = "affirmative" }, ["rationale"] = "Only visible response." }
                : new JsonObject
                {
                    ["action"] = "selectEstablishYourClanObjective",
                    ["arguments"] = new JsonObject { ["ObjectiveId"] = "gold" },
                    ["rationale"] = "Choose the currently unmet objective."
                };
            return Task.FromResult(new ProviderDecisionResult("completed", ModelId, 9, 2, "self-test", decision, "self-test", "json_schema"));
        }
        public void Dispose() { }
    }
}
