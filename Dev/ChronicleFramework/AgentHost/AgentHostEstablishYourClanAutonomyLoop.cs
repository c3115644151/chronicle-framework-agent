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
        if (!ShouldReconsiderUnavailableObjectives(journalProgressChanged: true) ||
            ShouldReconsiderUnavailableObjectives(journalProgressChanged: false))
            throw new AgentHostException("establish-clan-autonomy-child-retry-invalidation-failed", "A previously blocked objective route must reopen only after authoritative original Journal progress; a no-progress attempt remains temporarily unavailable.");
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
            new { scenario = "establish-clan-autonomy-never-selects-unimplemented-or-met-objectives", passed = true },
            new { scenario = "establish-clan-autonomy-child-native-actions-reopen-prior-route-blocks", passed = true }
        };
        var retryBefore = AgentHostEstablishYourClanGoalLoop.BuildObjectiveSnapshot(new JsonArray(
            new JsonObject { ["objectiveId"] = "gold", ["current"] = 920.0, ["target"] = 2000.0 },
            new JsonObject { ["objectiveId"] = "partySize", ["current"] = 1.0, ["target"] = 25.0 },
            new JsonObject { ["objectiveId"] = "renown", ["current"] = 20.0, ["target"] = 50.0 },
            new JsonObject { ["objectiveId"] = "companions", ["current"] = 0.0, ["target"] = 1.0 }));
        var retryAfter = (JsonObject)retryBefore.DeepClone();
        retryAfter["partySize"]!["current"] = 5.0;
        if (!HasObjectiveSnapshotProgressChanged(retryBefore, retryAfter) || HasObjectiveSnapshotProgressChanged(retryAfter, retryAfter))
            throw new AgentHostException("establish-clan-autonomy-child-journal-progress-detection-failed", "A child result whose official Journal snapshot progressed must be recognized even if that child safely stopped before its target.");
        using var routeStateBefore = JsonDocument.Parse("""{"campaignDay":1.0,"timeControlMode":"StoppablePlay","state":{"context":{"gameState":"MapState","menuId":null,"encounterActive":false,"captivity":{"isCaptive":false}},"location":{"currentSettlementId":null,"targetSettlementId":"town-a","targetPartyId":null},"party":{"members":11,"itemCount":1},"economy":{"gold":332,"renown":20},"nearbyParties":[]}}""");
        using var routeStateSame = JsonDocument.Parse(routeStateBefore.RootElement.GetRawText());
        using var routeStateTimeOnly = JsonDocument.Parse("""{"campaignDay":2.0,"timeControlMode":"UnstoppableFastForward","state":{"context":{"gameState":"MapState","menuId":null,"encounterActive":false,"captivity":{"isCaptive":false}},"location":{"currentSettlementId":null,"targetSettlementId":"town-a","targetPartyId":null},"party":{"members":11,"itemCount":1},"economy":{"gold":332,"renown":20},"nearbyParties":[]}}""");
        using var routeStateChanged = JsonDocument.Parse("""{"campaignDay":2.0,"timeControlMode":"StoppablePlay","state":{"context":{"gameState":"MapState","menuId":null,"encounterActive":false,"captivity":{"isCaptive":false}},"location":{"currentSettlementId":"town-a","targetSettlementId":"town-b","targetPartyId":null},"party":{"members":13,"itemCount":2},"economy":{"gold":432,"renown":20},"nearbyParties":[]}}""");
        if (BuildObjectiveRouteAvailabilityFingerprint(routeStateBefore.RootElement) != BuildObjectiveRouteAvailabilityFingerprint(routeStateSame.RootElement) ||
            BuildObjectiveRouteAvailabilityFingerprint(routeStateBefore.RootElement) != BuildObjectiveRouteAvailabilityFingerprint(routeStateTimeOnly.RootElement) ||
            BuildObjectiveRouteAvailabilityFingerprint(routeStateBefore.RootElement) == BuildObjectiveRouteAvailabilityFingerprint(routeStateChanged.RootElement))
            throw new AgentHostException("establish-clan-autonomy-route-state-fingerprint-failed", "Natural Campaign time and time-mode changes alone must not reopen a blocked route; meaningful Native location, Party or economy changes must.");
        results.Add(new { scenario = "establish-clan-autonomy-retries-partial-objective-after-child-journal-progress", passed = true });
        var noGoodsSaleOnFreeMap = new JsonObject
        {
            ["status"] = "failed",
            ["failureCode"] = "gold-sale-no-transferable-goods",
            ["finalNativeState"] = JsonNode.Parse("""{"status":"completed","state":{"context":{"gameState":"MapState","menuId":null,"encounterActive":false,"escapeMenuOpen":false,"inquiryOpen":false,"captivity":{"isCaptive":false}},"partyScreen":null,"inventoryScreen":null}}""")
        };
        var providerFailedSale = (JsonObject)noGoodsSaleOnFreeMap.DeepClone();
        providerFailedSale["failureCode"] = "provider-http-error";
        var noGoodsSaleInEncounter = (JsonObject)noGoodsSaleOnFreeMap.DeepClone();
        noGoodsSaleInEncounter["finalNativeState"]!["state"]!["context"]!["encounterActive"] = true;
        var noGoodsSaleInMission = (JsonObject)noGoodsSaleOnFreeMap.DeepClone();
        noGoodsSaleInMission["finalNativeState"]!["state"]!["context"]!["gameState"] = "MissionState";
        if (!ShouldUseBattleLootFallback(noGoodsSaleOnFreeMap) ||
            ShouldUseBattleLootFallback(providerFailedSale) ||
            ShouldUseBattleLootFallback(noGoodsSaleInEncounter) ||
            ShouldUseBattleLootFallback(noGoodsSaleInMission))
            throw new AgentHostException("establish-clan-autonomy-gold-loot-fallback-gate-failed", "The BattleSimulation fallback is allowed only after the exact no-transferable-goods result on a free Campaign Map; Provider failures, active encounters and Missions must not trigger it.");
        results.Add(new { scenario = "establish-clan-autonomy-gold-falls-back-to-battle-loot-only-after-verified-no-goods-on-free-map", passed = true });
        if (!IsRecoverableObjectiveProviderFailure("provider-http-error", "FreeLLMAPI returned HTTP 502. fallbackAttempts=2") ||
            !IsRecoverableObjectiveProviderFailure("provider-http-error", "FreeLLMAPI returned HTTP 503. fallbackAttempts=1") ||
            !IsRecoverableObjectiveProviderFailure("provider-http-error", "FreeLLMAPI returned HTTP 504. fallbackAttempts=1") ||
            IsRecoverableObjectiveProviderFailure("provider-http-error", "FreeLLMAPI returned HTTP 401. fallbackAttempts=0") ||
            IsRecoverableObjectiveProviderFailure("provider-http-error", "FreeLLMAPI returned HTTP 429. rateLimitRetryAttempts=3"))
            throw new AgentHostException("establish-clan-autonomy-transient-provider-http-recovery-classifier-failed", "Only exhausted transient gateway statuses 502/503/504 may replan from a separately verified safe Native state; auth errors and rate limits remain terminal.");
        results.Add(new { scenario = "establish-clan-autonomy-replans-only-exhausted-transient-gateway-errors", passed = true });
        if (!IsSafeObjectiveRouteUnavailable("companions", "companion-model-stopped", freeMap: true) ||
            IsSafeObjectiveRouteUnavailable("companions", "companion-model-stopped", freeMap: false) ||
            IsSafeObjectiveRouteUnavailable("gold", "companion-model-stopped", freeMap: true) ||
            !IsSafeObjectiveRouteUnavailable("gold", "gold-sale-no-transferable-goods", freeMap: true) ||
            !IsSafeObjectiveRouteUnavailable("gold", "gold-loot-no-current-visible-bandit", freeMap: true) ||
            !IsSafeObjectiveRouteUnavailable("gold", "training-issue-direct-offer-unavailable", freeMap: true) ||
            !IsSafeObjectiveRouteUnavailable("gold", "training-issue-direct-offer-rejected", freeMap: true) ||
            IsSafeObjectiveRouteUnavailable("gold", "gold-sale-no-transferable-goods", freeMap: false) ||
            IsSafeObjectiveRouteUnavailable("gold", "gold-loot-no-current-visible-bandit", freeMap: false) ||
            !IsSafeObjectiveRouteUnavailable("partySize", "recruitment-model-stopped", freeMap: true) ||
            IsSafeObjectiveRouteUnavailable("partySize", "recruitment-model-stopped", freeMap: false) ||
            !IsSafeObjectiveRouteUnavailable("partySize", "recruitment-model-stopped-with-safe-actions", freeMap: true) ||
            IsSafeObjectiveRouteUnavailable("partySize", "recruitment-model-stopped-with-safe-actions", freeMap: false) ||
            !IsSafeObjectiveRouteUnavailable("companions", "companion-provider-failure-returned-to-map", freeMap: true) ||
            IsSafeObjectiveRouteUnavailable("companions", "companion-provider-failure-returned-to-map", freeMap: false))
            throw new AgentHostException("establish-clan-autonomy-safe-stop-replan-policy-failed", "A Gold no-goods outcome, unavailable/rejected Native training offer, and safe Companion/PartySize stops may block only that route on a free Map; they must not hide unrelated failures or encounter/captive state.");
        results.Add(new { scenario = "establish-clan-autonomy-safe-no-goods-and-companion-recruitment-stops-mark-route-unavailable-and-allow-replan", passed = true });

        using var safeTavernMission = JsonDocument.Parse("""
            {"status":"completed","state":{"context":{"gameState":"MissionState","inquiryOpen":false,"escapeMenuOpen":false,"encounterActive":false,"captivity":{"isCaptive":false}},"mission":{"active":true,"missionEnded":false,"mode":"StartUp","sceneName":"town_ES3_tavern","conversation":null,"navigation":{"active":false},"leave":{"active":false}},"quests":[{"id":"rebuild_player_clan_storymode_quest"}]}}
            """);
        using var activeConversationMission = JsonDocument.Parse("""
            {"status":"completed","state":{"context":{"gameState":"MissionState","inquiryOpen":false,"escapeMenuOpen":false,"encounterActive":false,"captivity":{"isCaptive":false}},"mission":{"active":true,"missionEnded":false,"mode":"StartUp","sceneName":"town_ES3_tavern","navigation":{"active":false},"leave":{"active":false}},"conversation":{"heroId":"wanderer-a"},"quests":[{"id":"rebuild_player_clan_storymode_quest"}]}}
            """);
        if (!IsSafeTavernMissionForCompanionProviderRecovery(safeTavernMission.RootElement) ||
            IsSafeTavernMissionForCompanionProviderRecovery(activeConversationMission.RootElement))
            throw new AgentHostException("establish-clan-autonomy-companion-provider-mission-leave-policy-failed", "Provider failure may recover with Native Leave only from a friendly Town/Tavern Mission with no active conversation or modal.");
        results.Add(new { scenario = "establish-clan-autonomy-companion-provider-recovery-allows-safe-tavern-leave-but-not-active-conversation", passed = true });

        using var townLocationMenu = JsonDocument.Parse("""
            {"status":"completed","state":{"context":{"gameState":"MapState","menuId":"town","encounterActive":true,"encounteredPartyId":"town_ES3","captivity":{"isCaptive":false}},"location":{"currentSettlementId":"town_ES3"}}}
            """);
        using var hostileEncounter = JsonDocument.Parse("""
            {"status":"completed","state":{"context":{"gameState":"MapState","menuId":"encounter","encounterActive":true,"encounteredPartyId":"looter-party","captivity":{"isCaptive":false}},"location":{"currentSettlementId":null}}}
            """);
        if (!IsFreeMapForObjectiveReplan(townLocationMenu.RootElement) || IsFreeMapForObjectiveReplan(hostileEncounter.RootElement))
            throw new AgentHostException("establish-clan-autonomy-town-menu-free-map-classification-failed", "A Native Town location menu may report encounterActive=true but must remain a free Map for safe objective replanning; a real party encounter must still block it.");
        results.Add(new { scenario = "establish-clan-autonomy-native-town-menu-is-free-map-for-objective-replan-but-hostile-encounter-is-not", passed = true });

        using var hostileBanditInterruption = JsonDocument.Parse("""
            {"status":"completed","state":{"context":{"gameState":"MapState","menuId":"encounter_meeting","encounterActive":true,"encounteredPartyId":"mountain_bandits_221","captivity":{"isCaptive":false}},"nearbyParties":[{"id":"mountain_bandits_221","type":"bandit","hostile":true,"members":5}]}}
            """);
        using var nonHostileBanditInterruption = JsonDocument.Parse("""
            {"status":"completed","state":{"context":{"gameState":"MapState","menuId":"encounter_meeting","encounterActive":true,"encounteredPartyId":"mountain_bandits_221","captivity":{"isCaptive":false}},"nearbyParties":[{"id":"mountain_bandits_221","type":"bandit","hostile":false,"members":5}]}}
            """);
        using var hostileLordInterruption = JsonDocument.Parse("""
            {"status":"completed","state":{"context":{"gameState":"MapState","menuId":"encounter_meeting","encounterActive":true,"encounteredPartyId":"lord_party","captivity":{"isCaptive":false}},"nearbyParties":[{"id":"lord_party","type":"lord","hostile":true,"members":103}]}}
            """);
        if (!IsSupportedHostileBanditEncounter(hostileBanditInterruption.RootElement) ||
            IsSupportedHostileBanditEncounter(nonHostileBanditInterruption.RootElement) ||
            IsSupportedHostileBanditEncounter(hostileLordInterruption.RootElement))
            throw new AgentHostException("establish-clan-autonomy-incidental-battle-classification-failed", "Only a currently active, observed, hostile Bandit encounter may be handed to the existing Campaign BattleSimulation route; neutral and lord encounters must not be reclassified.");
        results.Add(new { scenario = "establish-clan-autonomy-resolves-only-current-observed-hostile-bandit-interruptions-through-battle-simulation", passed = true });

        using var safeObjectiveProviderMap = JsonDocument.Parse("""
            {"status":"completed","state":{"context":{"gameState":"MapState","inquiryOpen":false,"escapeMenuOpen":false,"isWaitMenu":false,"isWaitActive":false,"encounterActive":false,"captivity":{"isCaptive":false},"sceneNotification":{"hasActiveNotification":false}},"party":{"isMoving":false}}}
            """);
        using var movingObjectiveProviderMap = JsonDocument.Parse("""
            {"status":"completed","state":{"context":{"gameState":"MapState","inquiryOpen":false,"escapeMenuOpen":false,"isWaitMenu":false,"isWaitActive":false,"encounterActive":false,"captivity":{"isCaptive":false},"sceneNotification":{"hasActiveNotification":false}},"party":{"isMoving":true}}}
            """);
        if (!IsSafeMapForObjectiveProviderReplan(safeObjectiveProviderMap.RootElement) ||
            IsSafeMapForObjectiveProviderReplan(movingObjectiveProviderMap.RootElement))
            throw new AgentHostException("establish-clan-autonomy-provider-failure-map-safety-failed", "Provider failure may replan objectives only from a free, nonmoving, nonmodal Native Map state.");
        results.Add(new { scenario = "establish-clan-autonomy-provider-failure-replan-requires-safe-nonmoving-free-map", passed = true });

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

        var companionProviderFailureNative = new FakeNativeClient(activeQuest: true, lifecycle: "active", initialGold: 100, initialCompanions: 0);
        var companionProviderFailurePlanner = new FakeObjectiveProvider("companions", "gold", "companions");
        var companionProviderFailureChildCalls = 0;
        async Task<JsonObject> RecoverCompanionProviderFailure(string objectiveId, int priorDecisions, long priorPromptTokens, long priorCompletionTokens,
            JsonArray priorTrace, JsonArray priorRoutes, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            companionProviderFailureChildCalls++;
            if (objectiveId == "companions")
            {
                if (companionProviderFailureChildCalls == 1)
                {
                    companionProviderFailureNative.EnterTavernMission();
                    return new JsonObject
                    {
                        ["status"] = "failed", ["actionsExecuted"] = 4, ["decisions"] = priorDecisions,
                        ["promptTokens"] = priorPromptTokens, ["completionTokens"] = priorCompletionTokens,
                        ["trace"] = priorTrace.DeepClone(), ["providerRouteHistory"] = priorRoutes.DeepClone(),
                        ["termination"] = new JsonObject { ["reason"] = "companion-loop-failed" },
                        ["failureCode"] = "provider-http-error",
                        ["failure"] = "FreeLLMAPI returned HTTP 502. lastSuccessfulRoute=ovh; fallbackAttempts=2"
                    };
                }
                if (companionProviderFailureChildCalls != 3 || companionProviderFailureNative.IsInCompanionMission ||
                    !companionProviderFailureNative.CompanionNativeActions.SequenceEqual(["missionLeave"], StringComparer.Ordinal))
                    throw new AgentHostException("autonomy-selftest-companion-retry-state-invalid", "A failed Companion route may be attempted again only after one verified Native Leave changed the player from Tavern Mission to free Map; its prior actions must not be replayed.");
                companionProviderFailureNative.CompleteSuccessfully();
                return new JsonObject
                {
                    ["status"] = "completed", ["actionsExecuted"] = 1, ["decisions"] = priorDecisions,
                    ["promptTokens"] = priorPromptTokens, ["completionTokens"] = priorCompletionTokens,
                    ["trace"] = priorTrace.DeepClone(), ["providerRouteHistory"] = priorRoutes.DeepClone(),
                    ["termination"] = new JsonObject { ["reason"] = "native-companion-journal-target-met" }
                };
            }
            if (objectiveId != "gold" || companionProviderFailureNative.IsInCompanionMission ||
                !companionProviderFailureNative.CompanionNativeActions.SequenceEqual(["missionLeave"], StringComparer.Ordinal))
                throw new AgentHostException("autonomy-selftest-companion-provider-replan-state-invalid", "The next objective may run only after one verified Native missionLeave from the failed Tavern route; no Companion action may be replayed.");
            companionProviderFailureNative.CompleteGoldObjective();
            return new JsonObject
            {
                ["status"] = "completed", ["actionsExecuted"] = 1, ["decisions"] = priorDecisions,
                ["promptTokens"] = priorPromptTokens, ["completionTokens"] = priorCompletionTokens,
                ["trace"] = priorTrace.DeepClone(), ["providerRouteHistory"] = priorRoutes.DeepClone(),
                ["termination"] = new JsonObject { ["reason"] = "one-native-objective-subflow-completed" }
            };
        }
        var companionProviderRecovered = RunAsync(request.RootElement, companionProviderFailureNative, companionProviderFailureNative,
            companionProviderFailurePlanner, RecoverCompanionProviderFailure, CancellationToken.None).GetAwaiter().GetResult();
        var companionProviderAllowedObjectives = companionProviderFailurePlanner.AllowedObjectiveIds;
        if (ReadString(companionProviderRecovered, "status") != "completed" ||
            ReadBoolean(companionProviderRecovered["termination"] as JsonObject, "goalVerified") != true ||
            ReadInt(companionProviderRecovered, "actionsExecuted", 0) != 7 ||
            companionProviderFailurePlanner.CallCount != 3 || companionProviderFailureChildCalls != 3 ||
            companionProviderFailureNative.CompanionNativeActions.Count != 1 ||
            companionProviderAllowedObjectives.Count != 3 ||
            !companionProviderAllowedObjectives[0].Contains("companions", StringComparer.Ordinal) ||
            !companionProviderAllowedObjectives[1].Contains("gold", StringComparer.Ordinal) ||
            !companionProviderAllowedObjectives[1].Contains("companions", StringComparer.Ordinal) ||
            !companionProviderAllowedObjectives[2].SequenceEqual(["companions"], StringComparer.Ordinal) ||
            !((companionProviderRecovered["trace"] as JsonArray)?.OfType<JsonObject>().Any(step =>
                ReadString(step, "stage") == "objective-route-blocked-after-companion-provider-failure" &&
                ReadBoolean(step, "nativeLeaveVerified") && !ReadBoolean(step, "replayedChildActions")) ?? false))
            throw new AgentHostException("establish-clan-autonomy-companion-provider-failure-recovery-selftest-failed", "A provider error inside a supported Tavern Mission must return through Native Leave; the changed Native Map context can reopen Companion while another objective is considered, without replaying the failed child action. status=" + ReadString(companionProviderRecovered, "status") + "; termination=" + ReadString(companionProviderRecovered["termination"] as JsonObject, "reason") + "; goalVerified=" + ReadBoolean(companionProviderRecovered["termination"] as JsonObject, "goalVerified") + "; actions=" + ReadInt(companionProviderRecovered, "actionsExecuted", 0) + "; plannerCalls=" + companionProviderFailurePlanner.CallCount + "; childCalls=" + companionProviderFailureChildCalls + "; leaveActions=" + string.Join(",", companionProviderFailureNative.CompanionNativeActions) + "; allowed=" + string.Join("|", companionProviderAllowedObjectives.Select(ids => string.Join(",", ids))));
        results.Add(new { scenario = "establish-clan-autonomy-leaves-tavern-replans-and-retries-companion-after-native-map-return", modelDecisions = companionProviderFailurePlanner.CallCount, nativeActions = companionProviderRecovered["actionsExecuted"]?.GetValue<int>(), passed = true });
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
        var maxDecisions = Math.Clamp(ReadInt(request, "maxDecisions", AgentHostCampaignLoop.MaxCumulativeDecisions), 1, AgentHostCampaignLoop.MaxCumulativeDecisions);
        var maxElapsedSeconds = Math.Clamp(ReadInt(request, "maxElapsedSeconds", 7200), 1, 7200);
        var trace = priorTrace?.DeepClone() as JsonArray ?? new JsonArray();
        var routes = priorProviderRouteHistory?.DeepClone() as JsonArray ?? new JsonArray();
        var decisions = priorDecisions;
        var nativeActions = 0;
        long promptTokens = priorPromptTokens;
        long completionTokens = priorCompletionTokens;
        var unavailableObjectives = new HashSet<string>(StringComparer.Ordinal);
        var unavailableObjectiveFingerprints = new Dictionary<string, string>(StringComparer.Ordinal);
        var safeSettlementRefreshVisitedIds = new HashSet<string>(StringComparer.Ordinal);
        string? RememberCurrentSettlement(JsonElement nativeState)
        {
            var settlementId = ReadStateString(nativeState, "location", "currentSettlementId");
            if (!string.IsNullOrWhiteSpace(settlementId)) safeSettlementRefreshVisitedIds.Add(settlementId);
            return settlementId;
        }
        void MarkObjectiveUnavailable(string objectiveId, JsonElement native)
        {
            unavailableObjectives.Add(objectiveId);
            unavailableObjectiveFingerprints[objectiveId] = BuildObjectiveRouteAvailabilityFingerprint(native);
        }
        void ClearUnavailableObjectives()
        {
            unavailableObjectives.Clear();
            unavailableObjectiveFingerprints.Clear();
        }
        var objectiveRuns = new JsonArray();
        var start = Stopwatch.GetTimestamp();
        using var elapsed = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        elapsed.CancelAfter(TimeSpan.FromSeconds(maxElapsedSeconds));

        try
        {
            await provider.CheckConfiguredModelAsync(elapsed.Token);
            using (var initialState = await client.ReadStateAsync(elapsed.Token))
            {
                RememberCurrentSettlement(initialState.RootElement);
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
                RememberCurrentSettlement(current.RootElement);
                var currentRouteFingerprint = BuildObjectiveRouteAvailabilityFingerprint(current.RootElement);
                foreach (var previouslyBlocked in unavailableObjectiveFingerprints
                             .Where(entry => !string.Equals(entry.Value, currentRouteFingerprint, StringComparison.Ordinal))
                             .Select(entry => entry.Key).ToArray())
                {
                    unavailableObjectives.Remove(previouslyBlocked);
                    unavailableObjectiveFingerprints.Remove(previouslyBlocked);
                    trace.Add(new JsonObject
                    {
                        ["stage"] = "objective-route-reopened-after-native-state-change",
                        ["objectiveId"] = previouslyBlocked
                    });
                }
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
                    observedNativeState: JsonNode.Parse(current.RootElement.GetRawText())?.AsObject(),
                    activeQuestAlreadyVerified: true);
                decisions = ReadInt(planner, "decisions", decisions);
                promptTokens = ReadLong(planner, "promptTokens", promptTokens);
                completionTokens = ReadLong(planner, "completionTokens", completionTokens);
                trace = planner["trace"]?.DeepClone() as JsonArray ?? trace;
                routes = planner["providerRouteHistory"]?.DeepClone() as JsonArray ?? routes;

                if (ReadString(planner, "status") == "failed")
                    return BuildResult("failed", "objective-planner-failed", false,
                        ReadString(planner, "failure") ?? "The objective planner could not select from the current Native-supported routes after bounded correction.",
                        ReadString(planner, "failureCode") ?? "establish-clan-objective-selection-invalid",
                        journalObjectives, snapshot, differences);

                var resultKind = ReadString(planner, "resultKind");
                if (resultKind == "no-implemented-objective-route")
                {
                    var unmet = AgentHostEstablishYourClanGoalLoop.ObjectiveIds
                        .Where(id => ReadBoolean(snapshot[id] as JsonObject, "met") == false).ToArray();
                    var unimplemented = new JsonArray(unmet
                        .Where(id => !InitiallyIntegratedObjectives.Contains(id))
                        .Select(id => (JsonNode?)JsonValue.Create(id)).ToArray());
                    var allIntegratedRoutesBlocked = unimplemented.Count == 0 && unavailableObjectives.Count > 0;
                    if (allIntegratedRoutesBlocked && decisions < maxDecisions)
                    {
                        using var beforeRefresh = await client.ReadStateAsync(elapsed.Token);
                        var beforeRefreshState = beforeRefresh.RootElement.TryGetProperty("state", out var beforeStateElement) && beforeStateElement.ValueKind == JsonValueKind.Object
                            ? JsonNode.Parse(beforeStateElement.GetRawText())?.AsObject() ?? new JsonObject()
                            : new JsonObject();
                        var beforeRefreshLocation = beforeRefreshState["location"] as JsonObject;
                        var beforeRefreshSettlementId = ReadString(beforeRefreshLocation, "currentSettlementId");
                        if (!string.IsNullOrWhiteSpace(beforeRefreshSettlementId)) safeSettlementRefreshVisitedIds.Add(beforeRefreshSettlementId);
                        var remainingSeconds = Math.Max(1, maxElapsedSeconds - (int)Stopwatch.GetElapsedTime(start).TotalSeconds);
                        var refreshRequestNode = JsonNode.Parse(request.GetRawText())?.AsObject()
                            ?? throw new AgentHostException("establish-clan-opportunity-refresh-request-invalid", "The active Native EYC request could not be cloned for safe settlement re-navigation.");
                        refreshRequestNode["goal"] = "All currently integrated Establish Your Clan objective routes are temporarily unavailable at this free Campaign Map. Travel to one currently visible, safe settlement using the Native map target list. This refreshes the local recruitment, trade and encounter opportunities; do not claim EYC progress, and return control to the parent so it can re-read the original Journal.";
                        refreshRequestNode["scopeRestriction"] = "safe-settlement-arrival";
                        var excludedSettlementIdsForRefresh = new JsonArray(safeSettlementRefreshVisitedIds
                            .OrderBy(id => id, StringComparer.Ordinal)
                            .Select(id => (JsonNode?)JsonValue.Create(id)).ToArray());
                        refreshRequestNode["excludedSettlementIds"] = excludedSettlementIdsForRefresh.DeepClone();
                        refreshRequestNode["maxDecisions"] = maxDecisions;
                        refreshRequestNode["maxElapsedSeconds"] = remainingSeconds;
                        using var refreshRequest = JsonDocument.Parse(refreshRequestNode.ToJsonString());
                        trace.Add(new JsonObject
                        {
                            ["stage"] = "no-integrated-route-safe-settlement-refresh-started",
                            ["objectiveIdsBlocked"] = new JsonArray(unavailableObjectives.Select(id => (JsonNode?)JsonValue.Create(id)).ToArray()),
                            ["fromSettlementId"] = beforeRefreshSettlementId,
                            ["campaignDayBefore"] = ReadDouble(beforeRefresh.RootElement, "campaignDay", double.NaN),
                            ["timeControlModeBefore"] = ReadString(beforeRefresh.RootElement, "timeControlMode")
                        });
                        var refresh = await AgentHostCampaignLoop.RunAsync(
                            refreshRequest.RootElement, client, provider, elapsed.Token,
                            disposeProvider: false,
                            priorDecisions: decisions,
                            priorPromptTokens: promptTokens,
                            priorCompletionTokens: completionTokens,
                            priorTrace: trace,
                            priorProviderRouteHistory: routes);
                        decisions = ReadInt(refresh, "decisions", decisions);
                        nativeActions += ReadInt(refresh, "actionsExecuted", 0);
                        promptTokens = ReadLong(refresh, "promptTokens", promptTokens);
                        completionTokens = ReadLong(refresh, "completionTokens", completionTokens);
                        trace = refresh["trace"]?.DeepClone() as JsonArray ?? trace;
                        routes = refresh["providerRouteHistory"]?.DeepClone() as JsonArray ?? routes;
                        using var afterRefresh = await client.ReadStateAsync(elapsed.Token);
                        var afterRefreshState = afterRefresh.RootElement.TryGetProperty("state", out var afterStateElement) && afterStateElement.ValueKind == JsonValueKind.Object
                            ? JsonNode.Parse(afterStateElement.GetRawText())?.AsObject() ?? new JsonObject()
                            : new JsonObject();
                        var afterRefreshSettlementId = ReadString(afterRefreshState["location"] as JsonObject, "currentSettlementId");
                        var verifiedArrival = ReadString(refresh, "status") == "completed" &&
                            ReadString(refresh["termination"] as JsonObject, "reason") == "native-settlement-arrival-verified" &&
                            ReadBoolean(refresh["termination"] as JsonObject, "goalVerified") &&
                            !string.IsNullOrWhiteSpace(afterRefreshSettlementId) &&
                            !string.Equals(beforeRefreshSettlementId, afterRefreshSettlementId, StringComparison.Ordinal);
                        if (verifiedArrival) safeSettlementRefreshVisitedIds.Add(afterRefreshSettlementId!);

                        if (!verifiedArrival && decisions < maxDecisions &&
                            IsSupportedHostileBanditEncounter(afterRefresh.RootElement) &&
                            client is IAgentHostBattleSimulationNativeClient refreshBattleClient)
                        {
                            var interruptedBattle = await AgentHostBattleSimulationLoop.RunAsync(
                                request, refreshBattleClient, provider, elapsed.Token,
                                priorDecisions: decisions,
                                priorPromptTokens: promptTokens,
                                priorCompletionTokens: completionTokens,
                                priorTrace: trace,
                                priorProviderRouteHistory: routes,
                                recoverPlayerCaptivity: true);
                            AgentHostHarnessProgressTrace.RecordObjectiveSubflowResult("safeSettlementRefreshBanditInterruption", interruptedBattle);
                            decisions = ReadInt(interruptedBattle, "decisions", decisions);
                            promptTokens = ReadLong(interruptedBattle, "promptTokens", promptTokens);
                            completionTokens = ReadLong(interruptedBattle, "completionTokens", completionTokens);
                            nativeActions += ReadInt(interruptedBattle, "actionsExecuted", 0);
                            trace = interruptedBattle["trace"]?.DeepClone() as JsonArray ?? trace;
                            routes = interruptedBattle["providerRouteHistory"]?.DeepClone() as JsonArray ?? routes;
                            using var afterInterruptedBattle = await client.ReadStateAsync(elapsed.Token);
                            var canReplanAfterEncounter = IsSafeMapForObjectiveProviderReplan(afterInterruptedBattle.RootElement);
                            trace.Add(new JsonObject
                            {
                                ["stage"] = canReplanAfterEncounter ? "safe-settlement-refresh-bandit-resolved-or-left" : "safe-settlement-refresh-bandit-unresolved",
                                ["battleStatus"] = ReadString(interruptedBattle, "status"),
                                ["battleTermination"] = ReadString(interruptedBattle, "termination"),
                                ["playerOutcome"] = ReadString(interruptedBattle, "playerOutcome"),
                                ["freeMapReplanVerified"] = canReplanAfterEncounter
                            });
                            if (canReplanAfterEncounter) continue;
                        }

                        trace.Add(new JsonObject
                        {
                            ["stage"] = verifiedArrival ? "no-integrated-route-safe-settlement-refresh-arrived" : "no-integrated-route-safe-settlement-refresh-failed",
                            ["fromSettlementId"] = beforeRefreshSettlementId,
                            ["toSettlementId"] = afterRefreshSettlementId,
                            ["campaignDayBefore"] = ReadDouble(beforeRefresh.RootElement, "campaignDay", double.NaN),
                            ["campaignDayAfter"] = ReadDouble(afterRefresh.RootElement, "campaignDay", double.NaN),
                            ["timeControlModeBefore"] = ReadString(beforeRefresh.RootElement, "timeControlMode"),
                            ["timeControlModeAfter"] = ReadString(afterRefresh.RootElement, "timeControlMode"),
                            ["excludedSettlementIds"] = excludedSettlementIdsForRefresh.DeepClone(),
                            ["nativeMoveActions"] = ReadInt(refresh, "actionsExecuted", 0),
                            ["nativeArrivalVerified"] = verifiedArrival,
                            ["refreshFailureCode"] = ReadString(refresh, "failureCode")
                        });
                        objectiveRuns.Add(new JsonObject
                        {
                            ["objectiveId"] = "safeSettlementRefresh",
                            ["status"] = verifiedArrival ? "completed" : "failed",
                            ["termination"] = verifiedArrival ? "native-settlement-arrival-verified" : ReadString(refresh["termination"] as JsonObject, "reason"),
                            ["actionsExecuted"] = ReadInt(refresh, "actionsExecuted", 0),
                            ["decisions"] = decisions
                        });
                        if (verifiedArrival) continue;
                    }
                    return BuildResult("failed", allIntegratedRoutesBlocked ? "no-current-integrated-route-available" : "objective-route-not-yet-integrated", false,
                        allIntegratedRoutesBlocked
                            ? "Every integrated objective route remained blocked after one bounded Native safe-settlement refresh; the original Quest remains active."
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
                    var failedChildJournalProgress = HasObjectiveSnapshotProgressChanged(snapshot, child["objectiveSnapshot"] as JsonObject);
                    if (ShouldReconsiderUnavailableObjectives(journalProgressChanged: failedChildJournalProgress))
                    {
                        ClearUnavailableObjectives();
                        trace.Add(new JsonObject
                        {
                            ["stage"] = "failed-objective-native-actions-reopened-other-routes",
                            ["objectiveId"] = objectiveId,
                            ["journalProgressChanged"] = failedChildJournalProgress,
                            ["nativeActionsExecuted"] = ReadInt(child, "actionsExecuted", 0),
                            ["replayedActions"] = false
                        });
                    }
                    using var failedState = await client.ReadStateAsync(elapsed.Token);
                    var failedContext = failedState.RootElement.TryGetProperty("state", out var failedStateData) && failedStateData.ValueKind == JsonValueKind.Object &&
                                        failedStateData.TryGetProperty("context", out var contextData) && contextData.ValueKind == JsonValueKind.Object
                        ? contextData
                        : default;
                    var freeMap = IsFreeMapForObjectiveReplan(failedState.RootElement);
                    var childFailureCode = ReadString(child, "failureCode");

                    // A hostile Bandit can interrupt ordinary Campaign travel. The child
                    // objective must not reinterpret that encounter as a Companion/Gold
                    // failure or discard it; resolve it through the existing Native
                    // BattleSimulation contract, then resume planning from fresh Journal state.
                    if (IsSupportedHostileBanditEncounter(failedState.RootElement) &&
                        client is IAgentHostBattleSimulationNativeClient incidentBattleClient)
                    {
                        var incidentBattle = await AgentHostBattleSimulationLoop.RunAsync(
                            request, incidentBattleClient, provider, elapsed.Token,
                            priorDecisions: decisions,
                            priorPromptTokens: promptTokens,
                            priorCompletionTokens: completionTokens,
                            priorTrace: trace,
                            priorProviderRouteHistory: routes,
                            recoverPlayerCaptivity: true);
                        AgentHostHarnessProgressTrace.RecordObjectiveSubflowResult("incidentBattleSimulation", incidentBattle);
                        decisions = ReadInt(incidentBattle, "decisions", decisions);
                        promptTokens = ReadLong(incidentBattle, "promptTokens", promptTokens);
                        completionTokens = ReadLong(incidentBattle, "completionTokens", completionTokens);
                        nativeActions += ReadInt(incidentBattle, "actionsExecuted", 0);
                        trace = incidentBattle["trace"]?.DeepClone() as JsonArray ?? trace;
                        routes = incidentBattle["providerRouteHistory"]?.DeepClone() as JsonArray ?? routes;
                        objectiveRuns.Add(new JsonObject
                        {
                            ["objectiveId"] = "incidentBattleSimulation",
                            ["interruptedObjectiveId"] = objectiveId,
                            ["status"] = ReadString(incidentBattle, "status"),
                            ["termination"] = ReadString(incidentBattle, "termination"),
                            ["actionsExecuted"] = ReadInt(incidentBattle, "actionsExecuted", 0),
                            ["playerOutcome"] = ReadString(incidentBattle, "playerOutcome")
                        });

                        using var afterIncidentBattle = await client.ReadStateAsync(elapsed.Token);
                        if (IsPlayerCaptive(afterIncidentBattle.RootElement))
                        {
                            MarkObjectiveUnavailable(objectiveId, afterIncidentBattle.RootElement);
                            trace.Add(new JsonObject
                            {
                                ["stage"] = "incident-bandit-battle-returned-player-captive",
                                ["interruptedObjectiveId"] = objectiveId,
                                ["replayedChildActions"] = false,
                                ["nextStep"] = "native-captivity-recovery"
                            });
                            continue;
                        }
                        if (ReadString(incidentBattle, "termination") == "native-encounter-left-no-battle")
                        {
                            if (!IsSafeMapForObjectiveProviderReplan(afterIncidentBattle.RootElement) ||
                                !AgentHostEstablishYourClanGoalLoop.HasActiveQuest(afterIncidentBattle.RootElement))
                                return BuildResult("failed", "incident-bandit-leave-return-state-unverified", false,
                                    "The current Native Leave option was used because Send Troops was unavailable, but a safe Map and active EYC were not reverified.",
                                    "incident-bandit-leave-return-state-unverified", journalObjectives, snapshot, differences);
                            MarkObjectiveUnavailable(objectiveId, afterIncidentBattle.RootElement);
                            trace.Add(new JsonObject
                            {
                                ["stage"] = "incident-bandit-native-leave-without-simulation-replanned",
                                ["interruptedObjectiveId"] = objectiveId,
                                ["nativeBattleStarted"] = false,
                                ["renownProgressClaimed"] = false,
                                ["replayedChildActions"] = false
                            });
                            continue;
                        }
                        if (ReadString(incidentBattle, "status") != "completed")
                            return BuildResult("failed", "incident-bandit-battle-failed", false,
                                ReadString(incidentBattle, "failure") ?? "The interrupted hostile Bandit encounter did not reach a verified Native BattleSimulation return.",
                                ReadString(incidentBattle, "failureCode") ?? "incident-bandit-battle-failed",
                                journalObjectives, snapshot, differences);

                        if (!IsSafeMapForObjectiveProviderReplan(afterIncidentBattle.RootElement) ||
                            !AgentHostEstablishYourClanGoalLoop.HasActiveQuest(afterIncidentBattle.RootElement))
                            return BuildResult("failed", "incident-bandit-battle-return-state-unverified", false,
                                "The Native battle ended, but a safe nonmoving Campaign Map and the original EYC Journal were not both reverified.",
                                "incident-bandit-battle-return-state-unverified", journalObjectives, snapshot, differences);

                        using var afterIncidentDetails = await questDetailsClient.ReadQuestDetailsAsync(QuestId, elapsed.Token);
                        var afterIncidentData = ReadQuestDetailsData(afterIncidentDetails.RootElement);
                        var afterIncidentJournal = AgentHostEstablishYourClanGoalLoop.BuildJournalObjectives(afterIncidentData);
                        if (HasJournalProgressChanged(journalObjectives, afterIncidentJournal))
                            ClearUnavailableObjectives();
                        else
                            MarkObjectiveUnavailable(objectiveId, afterIncidentBattle.RootElement);
                        trace.Add(new JsonObject
                        {
                            ["stage"] = "hostile-bandit-interruption-resolved-and-parent-replanned",
                            ["interruptedObjectiveId"] = objectiveId,
                            ["journalProgressChanged"] = HasJournalProgressChanged(journalObjectives, afterIncidentJournal),
                            ["replayedChildActions"] = false,
                            ["nativeBattleResult"] = ReadString(incidentBattle, "battleResult"),
                            ["renownBefore"] = incidentBattle["renownBefore"]?.DeepClone(),
                            ["renownAfter"] = incidentBattle["renownAfter"]?.DeepClone()
                        });
                        continue;
                    }

                    if (IsPlayerCaptive(failedState.RootElement))
                    {
                        MarkObjectiveUnavailable(objectiveId, failedState.RootElement);
                        trace.Add(new JsonObject
                        {
                            ["stage"] = "objective-child-returned-mainhero-captive",
                            ["objectiveId"] = objectiveId,
                            ["replayedChildActions"] = false,
                            ["nextStep"] = "native-captivity-recovery"
                        });
                        continue;
                    }

                    // A recoverable provider failure (including an exhausted transient gateway
                    // status) after a Companion Native Mission action is
                    // not a reason to terminate the entire EYC Agent. Leave only from a verified
                    // friendly Town/Tavern Mission with no modal, conversation or active lease;
                    // then replan from fresh Map/Journal state without replaying any child action.
                    if (IsRecoverableObjectiveProviderFailure(childFailureCode, ReadString(child, "failure")))
                    {
                        if (InitiallyIntegratedObjectives.Contains(objectiveId) && freeMap && IsSafeMapForObjectiveProviderReplan(failedState.RootElement) &&
                            AgentHostEstablishYourClanGoalLoop.HasActiveQuest(failedState.RootElement))
                        {
                            MarkObjectiveUnavailable(objectiveId, failedState.RootElement);
                            trace.Add(new JsonObject
                            {
                                ["stage"] = "objective-provider-failure-route-blocked-on-free-map",
                                ["objectiveId"] = objectiveId,
                                ["failureCode"] = childFailureCode,
                                ["childActionsExecuted"] = ReadInt(child, "actionsExecuted", 0),
                                ["nativeLeaveSent"] = false,
                                ["replayedChildActions"] = false
                            });
                            continue;
                        }

                        if (objectiveId == "companions" && client is IAgentHostCompanionHiringNativeClient companionRecoveryClient &&
                            IsSafeTavernMissionForCompanionProviderRecovery(failedState.RootElement))
                        {
                            using var leaveResponse = await companionRecoveryClient.ExecuteCompanionHiringActionAsync("missionLeave", new JsonObject(), elapsed.Token);
                            var leaveReceipt = JsonNode.Parse(leaveResponse.RootElement.GetRawText())?.AsObject()
                                ?? throw new AgentHostException("companion-provider-failure-native-leave-receipt-invalid", "Native returned no recovery Leave receipt for the failed Tavern decision.");
                            if (ReadString(leaveReceipt, "status") != "completed")
                                return BuildResult("failed", "companion-provider-failure-native-leave-rejected", false,
                                    "The Companion provider failed in a Tavern Mission and Native Leave was not accepted; no parent replan was attempted.",
                                    "companion-provider-failure-native-leave-rejected", journalObjectives, snapshot, differences);

                            nativeActions++;
                            trace.Add(new JsonObject
                            {
                                ["stage"] = "companion-provider-failure-native-leave-started",
                                ["objectiveId"] = objectiveId,
                                ["failureCode"] = childFailureCode,
                                ["nativeAction"] = "missionLeave",
                                ["nativeActionStatus"] = "completed",
                                ["childActionsExecuted"] = ReadInt(child, "actionsExecuted", 0),
                                ["replayedChildActions"] = false
                            });

                            var returnedToMap = false;
                            for (var wait = 0; wait < 30; wait++)
                            {
                                await Task.Delay(TimeSpan.FromSeconds(1), elapsed.Token);
                                using var afterLeave = await client.ReadStateAsync(elapsed.Token);
                                if (!IsFreeMapForObjectiveReplan(afterLeave.RootElement) || !IsSafeMapForObjectiveProviderReplan(afterLeave.RootElement)) continue;
                                if (!AgentHostEstablishYourClanGoalLoop.HasActiveQuest(afterLeave.RootElement))
                                    return BuildResult("failed", "companion-provider-failure-quest-state-unverified", false,
                                        "Native Leave returned to Map after a Companion provider failure, but the original EYC Journal was no longer active.",
                                        "companion-provider-failure-quest-state-unverified", journalObjectives, snapshot, differences);
                                returnedToMap = true;
                                break;
                            }
                            if (!returnedToMap)
                                return BuildResult("failed", "companion-provider-failure-leave-unverified", false,
                                    "Native Leave was accepted after a Companion provider failure, but a safe free Map state was not verified within the bounded recovery window.",
                                    "companion-provider-failure-leave-unverified", journalObjectives, snapshot, differences);

                            MarkObjectiveUnavailable(objectiveId, failedState.RootElement);
                            trace.Add(new JsonObject
                            {
                                ["stage"] = "objective-route-blocked-after-companion-provider-failure",
                                ["objectiveId"] = objectiveId,
                                ["failureCode"] = childFailureCode,
                                ["nativeLeaveVerified"] = true,
                                ["childActionsExecuted"] = ReadInt(child, "actionsExecuted", 0),
                                ["replayedChildActions"] = false
                            });
                            continue;
                        }
                    }

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
                        if (resolution["providerRouteHistory"] is JsonArray inquiryRoutes)
                            foreach (var inquiryRoute in inquiryRoutes) routes.Add(inquiryRoute?.DeepClone());
                        else if (resolution["providerRoute"] is JsonObject inquiryRoute)
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
                        if (!failedChildJournalProgress) MarkObjectiveUnavailable(objectiveId, failedState.RootElement);
                        trace.Add(new JsonObject
                        {
                            ["stage"] = failedChildJournalProgress ? "objective-route-retry-after-partial-journal-progress" : "objective-route-blocked",
                            ["objectiveId"] = objectiveId,
                            ["termination"] = termination,
                            ["journalProgressChanged"] = failedChildJournalProgress,
                            ["failureCode"] = ReadString(child, "failureCode")
                        });
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
                if (HasJournalProgressChanged(journalObjectives, afterJournal))
                    ClearUnavailableObjectives();
                else
                    MarkObjectiveUnavailable(objectiveId, afterState.RootElement);
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
            // Preserve the exception message and stack in the Host receipt. The prior
            // type-only failure hid the exact boundary needed to diagnose live Campaign
            // failures and made repeat runs expensive without improving safety.
            return BuildResult("failed", "autonomy-loop-failed", false, exception.ToString(), "establish-clan-autonomy-unexpected-error");
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
                ["providerPromptCacheHitTokens"] = provider is OllamaNativeProvider cacheMeter ? cacheMeter.PromptCacheHitTokens : null,
                ["providerPromptCacheMissTokens"] = provider is OllamaNativeProvider missMeter ? missMeter.PromptCacheMissTokens : null,
                ["providerActualCostEstimateCny"] = provider is OllamaNativeProvider actualCostMeter ? actualCostMeter.ActualCostEstimateCny : null,
                ["providerReservedCostUpperCny"] = provider is OllamaNativeProvider costMeter ? costMeter.ReservedCostUpperBoundCny : null,
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

    internal static bool HasObjectiveSnapshotProgressChanged(JsonObject? before, JsonObject? after)
    {
        if (before is null || after is null) return false;
        foreach (var objectiveId in AgentHostEstablishYourClanGoalLoop.ObjectiveIds)
        {
            var oldObjective = before[objectiveId] as JsonObject;
            var newObjective = after[objectiveId] as JsonObject;
            if (ReadDouble(oldObjective, "current") != ReadDouble(newObjective, "current") ||
                ReadDouble(oldObjective, "target") != ReadDouble(newObjective, "target"))
                return true;
        }
        return false;
    }

    internal static string BuildObjectiveRouteAvailabilityFingerprint(JsonElement native)
    {
        var root = JsonNode.Parse(native.GetRawText())?.AsObject() ?? new JsonObject();
        var state = root["state"] as JsonObject ?? new JsonObject();
        var context = state["context"] as JsonObject;
        var location = state["location"] as JsonObject;
        var party = state["party"] as JsonObject;
        var economy = state["economy"] as JsonObject;
        var captivity = context?["captivity"] as JsonObject;
        var nearbyPartyFingerprint = string.Join(",", (state["nearbyParties"] as JsonArray ?? new JsonArray())
            .OfType<JsonObject>()
            .Select(item => string.Join(":", ReadString(item, "id"), ReadString(item, "type"), ReadBoolean(item, "hostile"), ReadInt(item, "members", -1)))
            .OrderBy(value => value, StringComparer.Ordinal));
        return string.Join("|",
            ReadString(context, "gameState"), ReadString(context, "menuId"), ReadBoolean(context, "encounterActive"),
            ReadString(location, "currentSettlementId"), ReadString(location, "targetSettlementId"), ReadString(location, "targetPartyId"),
            ReadInt(party, "members", -1), ReadInt(party, "itemCount", -1), ReadInt(economy, "gold", -1),
            ReadDouble(economy, "renown").ToString("R", CultureInfo.InvariantCulture), ReadBoolean(captivity, "isCaptive"),
            nearbyPartyFingerprint);
    }

    internal static bool ShouldReconsiderUnavailableObjectives(bool journalProgressChanged) => journalProgressChanged;

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
        if (objectiveId == "gold") return termination is "provider-failure-returned-to-map" or "gold-sale-no-transferable-goods" or
            "gold-loot-no-current-visible-bandit" or "training-issue-no-visible-direct-offer" or "training-issue-no-safe-settlement-visible" or
            "training-issue-no-current-native-action" or "training-issue-battle-subflow-failed" or "training-issue-action-rejection-limit" or
            "training-issue-direct-offer-unavailable" or "training-issue-direct-offer-rejected";
        if (objectiveId == "renown") return termination is "provider-failure-returned-to-map" or "no-safe-action" or "native-encounter-left-no-battle";
        if (objectiveId is "partySize" or "companions")
            return termination is "native-journal-refresh-pending" or "recruitment-route-unavailable" or "companion-route-unavailable" or "companion-model-stopped" or "recruitment-model-stopped" or "recruitment-model-stopped-with-safe-actions" or "provider-failure-returned-to-map" or "companion-provider-failure-returned-to-map";
        return false;
    }

    internal static bool ShouldUseBattleLootFallback(JsonObject saleResult)
    {
        if (ReadString(saleResult, "status") != "failed" || ReadString(saleResult, "failureCode") != "gold-sale-no-transferable-goods" ||
            saleResult["finalNativeState"] is not JsonObject native || native["state"] is not JsonObject state)
            return false;
        var context = state["context"] as JsonObject;
        var captivity = context?["captivity"] as JsonObject;
        return ReadString(context, "gameState") == "MapState" && ReadString(context, "menuId") is null &&
               !ReadBoolean(context, "encounterActive") && !ReadBoolean(context, "escapeMenuOpen") && !ReadBoolean(context, "inquiryOpen") &&
               !ReadBoolean(captivity, "isCaptive") && state["partyScreen"] is null && state["inventoryScreen"] is null;
    }

    private static bool IsRecoverableObjectiveProviderFailure(string? failureCode, string? failure = null) =>
        failureCode == "companion-action-recovery-exhausted" || AgentHostProviderDecisionRecovery.CanRetry(failureCode ?? string.Empty, rejectedDecisions: 0) ||
        failureCode == "provider-http-error" && IsTransientGatewayFailure(failure);

    private static bool IsTransientGatewayFailure(string? failure) =>
        failure?.Contains("returned HTTP 502", StringComparison.OrdinalIgnoreCase) == true ||
        failure?.Contains("returned HTTP 503", StringComparison.OrdinalIgnoreCase) == true ||
        failure?.Contains("returned HTTP 504", StringComparison.OrdinalIgnoreCase) == true;

    private static bool IsSupportedHostileBanditEncounter(JsonElement native)
    {
        if (native.ValueKind != JsonValueKind.Object || !native.TryGetProperty("state", out var stateElement) || stateElement.ValueKind != JsonValueKind.Object)
            return false;
        var state = JsonNode.Parse(stateElement.GetRawText())?.AsObject();
        var context = state?["context"] as JsonObject;
        var encounteredPartyId = ReadString(context, "encounteredPartyId");
        return state is not null && ReadString(context, "gameState") == "MapState" &&
               AgentHostCampaignStateFacts.IsActiveEncounter(state) && !IsPlayerCaptive(native) &&
               !string.IsNullOrWhiteSpace(encounteredPartyId) &&
               (state["nearbyParties"] as JsonArray)?.OfType<JsonObject>().Any(party =>
                   ReadString(party, "id") == encounteredPartyId && ReadString(party, "type") == "bandit" && ReadBoolean(party, "hostile")) == true;
    }

    private static bool IsSafeMapForObjectiveProviderReplan(JsonElement native)
    {
        if (native.ValueKind != JsonValueKind.Object || !native.TryGetProperty("state", out var stateElement) || stateElement.ValueKind != JsonValueKind.Object)
            return false;
        var state = JsonNode.Parse(stateElement.GetRawText())?.AsObject();
        var context = state?["context"] as JsonObject;
        var party = state?["party"] as JsonObject;
        return state is not null && ReadString(context, "gameState") == "MapState" &&
               !ReadBoolean(context, "inquiryOpen") && !ReadBoolean(context, "escapeMenuOpen") &&
               !ReadBoolean(context, "isWaitMenu") && !ReadBoolean(context, "isWaitActive") &&
               !ReadBoolean(context?["sceneNotification"] as JsonObject, "hasActiveNotification") &&
               party?["isMoving"] is JsonValue movingNode && movingNode.TryGetValue<bool>(out var isMoving) && !isMoving &&
               !AgentHostCampaignStateFacts.IsActiveEncounter(state) && !IsPlayerCaptive(native);
    }

    private static bool IsSafeTavernMissionForCompanionProviderRecovery(JsonElement native)
    {
        if (native.ValueKind != JsonValueKind.Object || !native.TryGetProperty("state", out var stateElement) || stateElement.ValueKind != JsonValueKind.Object)
            return false;
        var state = JsonNode.Parse(stateElement.GetRawText())?.AsObject();
        var context = state?["context"] as JsonObject;
        var mission = state?["mission"] as JsonObject;
        var sceneName = ReadString(mission, "sceneName");
        var supportedLocationScene = sceneName?.Contains("tavern", StringComparison.OrdinalIgnoreCase) == true ||
                                     sceneName?.Contains("_town_", StringComparison.OrdinalIgnoreCase) == true;
        return state is not null && ReadString(context, "gameState") == "MissionState" &&
               ReadString(mission, "mode") == "StartUp" && supportedLocationScene &&
               ReadBoolean(mission, "active") && !ReadBoolean(mission, "missionEnded") &&
               state["conversation"] is null &&
               !ReadBoolean(context, "inquiryOpen") && !ReadBoolean(context, "escapeMenuOpen") &&
               !ReadBoolean(context?["sceneNotification"] as JsonObject, "hasActiveNotification") &&
               !ReadBoolean(mission?["navigation"] as JsonObject, "active") &&
               !ReadBoolean(mission?["leave"] as JsonObject, "active") &&
               !AgentHostCampaignStateFacts.IsActiveEncounter(state) && !IsPlayerCaptive(native) &&
               AgentHostEstablishYourClanGoalLoop.HasActiveQuest(native);
    }

    internal static bool IsFreeMapForObjectiveReplan(JsonElement native)
    {
        if (native.ValueKind != JsonValueKind.Object || !native.TryGetProperty("state", out var stateElement) || stateElement.ValueKind != JsonValueKind.Object)
            return false;
        var state = JsonNode.Parse(stateElement.GetRawText())?.AsObject();
        if (state is null || ReadString(state["context"] as JsonObject, "gameState") != "MapState") return false;
        return !AgentHostCampaignStateFacts.IsActiveEncounter(state) && !IsPlayerCaptive(native);
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
    private static string? ReadStateString(JsonElement native, string objectName, string propertyName)
    {
        if (native.ValueKind != JsonValueKind.Object || !native.TryGetProperty("state", out var state) || state.ValueKind != JsonValueKind.Object ||
            !state.TryGetProperty(objectName, out var value)) return null;
        return ReadString(value, propertyName);
    }
    private static int ReadInt(JsonElement element, string name, int fallback) => element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var value) && value.TryGetInt32(out var result) ? result : fallback;
    private static double ReadDouble(JsonElement element, string name, double fallback) => element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var value) && value.TryGetDouble(out var result) ? result : fallback;
    private static int ReadInt(JsonObject? node, string name, int fallback) => node?[name] is JsonValue value && value.TryGetValue<int>(out var result) ? result : fallback;
    private static long ReadLong(JsonObject? node, string name, long fallback) => node?[name] is JsonValue value && value.TryGetValue<long>(out var result) ? result : fallback;
    private static double ReadDouble(JsonObject? node, string name) => node?[name] is JsonValue value && value.TryGetValue<double>(out var result) ? result : double.NaN;

    private sealed class FakeNativeClient(bool activeQuest, string lifecycle, int initialGold, bool initialCaptive = false, int initialCompanions = 1) : IAgentHostCompanionHiringNativeClient, IAgentHostNativeInquiryClient
    {
        private bool _activeQuest = activeQuest;
        private string _lifecycle = lifecycle;
        private int _gold = initialGold;
        private int _companions = initialCompanions;
        internal bool IsFree => !_captive;
        internal bool IsInCompanionMission => _companionMission;
        internal List<string> CompanionNativeActions { get; } = new();
        private bool _captive = initialCaptive;
        private bool _inquiryOpen;
        private bool _companionMission;
        private bool _missionLeaveRequested;
        private int _missionLeaveActiveReadsRemaining;
        internal bool InquiryOpen => _inquiryOpen;
        internal string? LastInquiryChoice { get; private set; }
        internal string? LastInquiryToken { get; private set; }
        internal int QuestDetailsReads { get; private set; }

        internal void CompleteSuccessfully()
        {
            _gold = 2000;
            _companions = 1;
            _activeQuest = false;
            _lifecycle = "completed";
        }

        internal void CompleteGoldObjective() => _gold = 2000;

        internal void LeaveCaptivity() => _captive = false;
        internal void OpenInquiry() => _inquiryOpen = true;
        internal void EnterTavernMission() => _companionMission = true;

        public Task<JsonDocument> ReadStateAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var missionLeaveActive = false;
            if (_companionMission && _missionLeaveRequested && _missionLeaveActiveReadsRemaining > 0)
            {
                missionLeaveActive = true;
                _missionLeaveActiveReadsRemaining--;
            }
            else if (_companionMission && _missionLeaveRequested)
            {
                _companionMission = false;
                _missionLeaveRequested = false;
            }
            var quests = new JsonArray();
            if (_activeQuest) quests.Add(new JsonObject { ["id"] = QuestId });
            var state = new JsonObject
            {
                ["context"] = new JsonObject
                {
                    ["gameState"] = _companionMission ? "MissionState" : "MapState", ["captivity"] = new JsonObject { ["isCaptive"] = _captive },
                    ["inquiryOpen"] = _inquiryOpen,
                    ["escapeMenuOpen"] = false,
                    ["encounterActive"] = false,
                    ["sceneNotification"] = new JsonObject { ["hasActiveNotification"] = false },
                    ["inquiry"] = _inquiryOpen ? new JsonObject
                    {
                        ["supported"] = true, ["kind"] = "YesNoInquiry", ["token"] = "inquiry-token",
                        ["title"] = "通知", ["text"] = "训练场结束通知",
                        ["affirmative"] = new JsonObject { ["visible"] = true, ["enabled"] = true, ["text"] = "好" },
                        ["negative"] = new JsonObject { ["visible"] = false, ["enabled"] = false, ["text"] = "" }
                    } : null
                },
                ["quests"] = quests,
                ["party"] = new JsonObject { ["isMoving"] = false },
                ["storyModeEstablishClanStatus"] = new JsonObject { ["status"] = _lifecycle }
            };
            if (_companionMission)
            {
                state["location"] = new JsonObject { ["currentSettlementId"] = "town_ES3" };
                state["conversation"] = null;
                state["mission"] = new JsonObject
                {
                    ["active"] = true,
                    ["missionEnded"] = false,
                    ["mode"] = "StartUp",
                    ["sceneName"] = "town_ES3_tavern",
                    ["navigation"] = new JsonObject { ["active"] = false },
                    ["leave"] = new JsonObject { ["active"] = missionLeaveActive }
                };
            }
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
                Objective("companions", _companions, 1));
            var live = new JsonObject
            {
                ["gold"] = new JsonObject { ["current"] = _gold, ["target"] = 2000, ["met"] = _gold >= 2000 },
                ["partySize"] = new JsonObject { ["current"] = 20, ["target"] = 20, ["met"] = true },
                ["renown"] = new JsonObject { ["current"] = 50, ["target"] = 50, ["met"] = true },
                ["companions"] = new JsonObject { ["current"] = _companions, ["target"] = 1, ["met"] = _companions >= 1 }
            };
            var data = new JsonObject { ["questId"] = QuestId, ["title"] = "Establish Your Clan", ["journalStages"] = journal, ["storyModeEstablishClan"] = live };
            return Task.FromResult(JsonDocument.Parse(new JsonObject { ["status"] = "completed", ["data"] = data }.ToJsonString()));
        }

        public Task<JsonDocument> ExecuteCampaignActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken) =>
            throw new AgentHostException("autonomy-selftest-unexpected-native-action", "The fake parent-loop test injects the objective executor and must not directly send Native actions.");

        public Task<JsonDocument> ExecuteCompanionHiringActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (action != "missionLeave" || arguments.Count != 0 || !_companionMission || _missionLeaveRequested)
                throw new AgentHostException("autonomy-selftest-companion-leave-invalid", "Only one original Native missionLeave may recover the safe Companion Tavern failure fixture.");
            CompanionNativeActions.Add(action);
            _missionLeaveRequested = true;
            _missionLeaveActiveReadsRemaining = 2;
            return Task.FromResult(JsonDocument.Parse("{\"status\":\"completed\",\"action\":\"missionLeave\"}"));
        }

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

    private sealed class FakeObjectiveProvider(params string[] selectedObjectives) : IAgentHostDecisionProvider
    {
        internal int CallCount { get; private set; }
        internal List<string[]> AllowedObjectiveIds { get; } = new();
        public string ModelId => "deterministic-establish-clan-autonomy-selftest";
        public string ConfigurationSource => "harness-fake-provider";
        public Task CheckConfiguredModelAsync(CancellationToken cancellationToken) => Task.CompletedTask;
        public Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var allowedAction = request.GetProperty("allowedActions").EnumerateArray()
                .FirstOrDefault(action => action.GetProperty("action").GetString() == "selectEstablishYourClanObjective");
            if (allowedAction.ValueKind != JsonValueKind.Object)
                throw new AgentHostException("autonomy-selftest-objective-catalog-missing", "The fake planner requires the current Native-backed ObjectiveId catalog.");
            var allowedIds = allowedAction.GetProperty("argumentValues").GetProperty("ObjectiveId")
                .EnumerateArray().Select(value => value.GetString() ?? string.Empty).ToArray();
            AllowedObjectiveIds.Add(allowedIds);
            var selectedObjective = selectedObjectives[Math.Min(CallCount, selectedObjectives.Length - 1)];
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
