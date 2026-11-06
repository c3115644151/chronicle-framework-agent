using System.Diagnostics;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal static class AgentHostEstablishClanRecruitmentLoop
{
    private const int SettlementTargetPageSize = 12;
    private const string QuestId = "rebuild_player_clan_storymode_quest";
    private const string RecruitmentMenuOptionId = "recruit_volunteers";
    internal const string VillagersInNeedQuestId = "talk_to_villagers_in_village_quest";
    internal const string VillagersInNeedVillageId = "village_ES3_2";
    internal const string VillagersInNeedHeroId = "tutorial_npc_questgiver_villager";
    internal const string VillagersInNeedVillaMissionStartTextId = "glarczej";
    internal const string VillagersInNeedDeferTextId = "nhSLTzHk";
    internal const string GangLeaderRecruitsIssueTitleZh = "帮派需要招新";
    internal const string GangLeaderRecruitsDirectAcceptanceOptionId = "issue_offer_player_accept_quest";
    internal const string GangLeaderRecruitsAlternativeOptionId = "issue_offer_player_accept_alternative";
    internal const string GangLeaderRecruitsLordOptionId = "issue_offer_player_accept_lord";
    private const int MaxRejectedDecisions = 2;
    private const int MaxDecisions = AgentHostCampaignLoop.MaxCumulativeDecisions;
    internal const int MaxVillagersInNeedConversationStartupWaits = 10;
    private static readonly TimeSpan MaxElapsed = TimeSpan.FromHours(24);

    internal static async Task<IReadOnlyList<object>> RunContractSelfTestsAsync()
    {
        var recruitmentSystemPrompt = AgentHostDecisionCycle.EstablishClanRecruitmentSystemPrompt;
        if (!recruitmentSystemPrompt.Contains("use observeAgain waitSeconds=10 exactly", StringComparison.Ordinal) ||
            !recruitmentSystemPrompt.Contains("polls mapPartyTargets every second", StringComparison.Ordinal) ||
            !recruitmentSystemPrompt.Contains("no shorter interval is available in this subgoal", StringComparison.Ordinal) ||
            !recruitmentSystemPrompt.Contains("mapSettlementTargetsMore", StringComparison.Ordinal) ||
            !recruitmentSystemPrompt.Contains("Every target in the current safe Native result remains reachable through the pages", StringComparison.Ordinal) ||
            !recruitmentSystemPrompt.Contains("only then is the original talkToSettlementHero route offered", StringComparison.Ordinal) ||
            !recruitmentSystemPrompt.Contains("The Issue accepts ordinary Bandit members through its Native TroopsManage screen, not prisoners", StringComparison.Ordinal) ||
            !recruitmentSystemPrompt.Contains("asks for a dynamic number of ordinary Bandit members within 30 days", StringComparison.Ordinal) ||
            !recruitmentSystemPrompt.Contains("starts at 2000 Gold reward plus tier bonuses", StringComparison.Ordinal))
            throw new AgentHostException("establish-clan-recruitment-passive-wait-efficiency-contract-failed", "Safe PartySize movement must prefer one 10-second observation window and offer paginated access to the complete Native target result.");
        var targets = FilterRecruitmentTargets(new JsonArray
        {
            new JsonObject { ["id"] = "town-a", ["type"] = "town", ["distance"] = 4, ["hostile"] = false, ["underSiege"] = false },
            new JsonObject { ["id"] = "village-a", ["type"] = "village", ["distance"] = 3, ["hostile"] = false, ["underSiege"] = false },
            new JsonObject { ["id"] = "castle-a", ["type"] = "castle", ["distance"] = 2, ["hostile"] = false, ["underSiege"] = false },
            new JsonObject { ["id"] = "hostile-village", ["type"] = "village", ["distance"] = 2, ["hostile"] = true, ["underSiege"] = false },
            new JsonObject { ["id"] = "sieged-town", ["type"] = "town", ["distance"] = 2, ["hostile"] = false, ["underSiege"] = true },
            new JsonObject { ["id"] = "current-village", ["type"] = "village", ["distance"] = 0, ["hostile"] = false, ["underSiege"] = false }
        }, "current-village", new HashSet<string>(StringComparer.Ordinal))
            ?? throw new AgentHostException("establish-clan-recruitment-target-filter-unavailable", "A supplied Native target list must produce a filtered target list.");
        if (targets.Count != 2 || targets.Any(target => ReadString(target as JsonObject, "id") is not ("town-a" or "village-a")))
            throw new AgentHostException("establish-clan-recruitment-target-filter-failed", "Only newly observed, safe Town/Village targets may be offered for troop recruitment travel.");
        if (targets.OfType<JsonObject>().Any(target => target.ContainsKey("hostile") || target.ContainsKey("underSiege") || target.ContainsKey("isInspected")))
            throw new AgentHostException("establish-clan-recruitment-target-projection-retains-redundant-flags", "After filtering safe targets, the per-target observation must omit hostility/siege flags already proven false and inspection state unused by this subgoal.");
        var sameDayNoOfferTrace = new JsonArray(new JsonObject
        {
            ["stage"] = "recruitment-settlement-no-affordable-volunteer-offers",
            ["settlementId"] = "town-a",
            ["campaignDay"] = 91077.90,
            ["gold"] = 100
        });
        var sameDayNoOfferCooldown = BuildNoAffordableVolunteerSettlementCooldowns(sameDayNoOfferTrace, 91077.99, 100);
        var nextDayNoOfferCooldown = BuildNoAffordableVolunteerSettlementCooldowns(sameDayNoOfferTrace, 91078.01, 100);
        var fundedNoOfferCooldown = BuildNoAffordableVolunteerSettlementCooldowns(sameDayNoOfferTrace, 91077.99, 101);
        if (!sameDayNoOfferCooldown.Contains("town-a") || nextDayNoOfferCooldown.Contains("town-a") || fundedNoOfferCooldown.Contains("town-a") ||
            (FilterRecruitmentTargets(new JsonArray(new JsonObject { ["id"] = "town-a", ["type"] = "town", ["distance"] = 4 },
                new JsonObject { ["id"] = "village-b", ["type"] = "village", ["distance"] = 3 }), null, sameDayNoOfferCooldown)
                ?? new JsonArray()).OfType<JsonObject>().Any(target => ReadString(target, "id") == "town-a"))
            throw new AgentHostException("establish-clan-recruitment-no-offer-same-day-cooldown-failed", "A settlement with no currently affordable volunteer offers should be skipped only while the game day and Gold remain unchanged, then become eligible for a fresh Native query.");
        if (MaxDecisions != AgentHostCampaignLoop.MaxCumulativeDecisions || MaxElapsed != TimeSpan.FromHours(24))
            throw new AgentHostException("establish-clan-recruitment-budget-mismatch", "The PartySize executor must honor the autonomous parent's cumulative decision and 24-hour run budgets rather than terminating its child route early.");
        var manyTargets = FilterRecruitmentTargets(new JsonArray(Enumerable.Range(0, 32).Select(index => (JsonNode?)new JsonObject
        {
            ["id"] = $"settlement-{index:D2}", ["name"] = $"Settlement {index:D2}", ["type"] = index % 2 == 0 ? "town" : "village",
            ["distance"] = (double)index + 1, ["hostile"] = false, ["underSiege"] = false, ["isInspected"] = index % 2 == 0
        }).ToArray()), null, new HashSet<string>(StringComparer.Ordinal))
            ?? throw new AgentHostException("establish-clan-recruitment-target-list-unavailable", "A supplied Native target list must produce a filtered target list.");
        var manyTargetState = new JsonObject
        {
            ["context"] = new JsonObject { ["gameState"] = "MapState", ["menuId"] = "village", ["encounterActive"] = false },
            ["availableMenuOptions"] = new JsonArray()
        };
        var unknownTargetCache = FilterRecruitmentTargets(null, null, new HashSet<string>(StringComparer.Ordinal));
        var refreshTargetsCatalog = BuildActionCatalog(manyTargetState,
            new JsonObject { ["partySize"] = new JsonObject { ["target"] = 5 } }, unknownTargetCache, null, null, false);
        if (unknownTargetCache is not null || refreshTargetsCatalog.Count != 1 ||
            ReadString(refreshTargetsCatalog[0] as JsonObject, "action") != "mapSettlementTargets")
            throw new AgentHostException("establish-clan-recruitment-invalidated-target-cache-not-refreshed", "An invalidated or never-loaded target cache must remain unknown (null), allowing the model to request the current Native-visible Town/Village list after leaving a no-offer settlement.");
        var targetPage0 = GetRecruitmentSettlementTargetPage(manyTargets, 0);
        var targetPage1 = GetRecruitmentSettlementTargetPage(manyTargets, targetPage0.Count);
        var targetPage2 = GetRecruitmentSettlementTargetPage(manyTargets, targetPage0.Count + targetPage1.Count);
        var pagedTargetIds = targetPage0.Concat(targetPage1).Concat(targetPage2).OfType<JsonObject>()
            .Select(target => ReadString(target, "id")).ToArray();
        var manyTargetCatalog = BuildActionCatalog(manyTargetState, new JsonObject { ["partySize"] = new JsonObject { ["target"] = 5 } },
            targetPage0, null, null, false, moreSafeTargetsAvailable: true);
        var lastTargetPageCatalog = BuildActionCatalog(manyTargetState, new JsonObject { ["partySize"] = new JsonObject { ["target"] = 5 } },
            targetPage2, null, null, false, moreSafeTargetsAvailable: false);
        var pageMoreDecision = new JsonObject { ["action"] = "mapSettlementTargetsMore", ["arguments"] = new JsonObject() };
        if (manyTargets.Count != 32 || targetPage0.Count != SettlementTargetPageSize || targetPage1.Count != SettlementTargetPageSize || targetPage2.Count != 8 ||
            !pagedTargetIds.SequenceEqual(manyTargets.OfType<JsonObject>().Select(target => ReadString(target, "id"))) ||
            (manyTargetCatalog.First(action => ReadString(action as JsonObject, "action") == "move")?["argumentValues"]?["SettlementId"] as JsonArray)?.Count != SettlementTargetPageSize ||
            manyTargetCatalog.OfType<JsonObject>().Any(action => ReadString(action, "action") == "mapSettlementTargetsMore") != true ||
            lastTargetPageCatalog.OfType<JsonObject>().Any(action => ReadString(action, "action") == "mapSettlementTargetsMore") ||
            !TryResolveRecruitmentAction(pageMoreDecision, manyTargetState, targetPage0, null, null, false,
                out var pageMoreAction, out _, out _, out _, moreSafeTargetsAvailable: true) || pageMoreAction != "mapSettlementTargetsMore" ||
            TryResolveRecruitmentAction(pageMoreDecision, manyTargetState, targetPage2, null, null, false,
                out _, out _, out _, out _, moreSafeTargetsAvailable: false))
            throw new AgentHostException("establish-clan-recruitment-target-pagination-failed", "The Host must expose each safe Native target exactly once over all settlement pages, list More only while another page exists, and resolve that Host-only page action without hiding targets behind a hard cap.");
        var fullTargetObservationBytes = System.Text.Encoding.UTF8.GetByteCount(BuildObservation(manyTargetState, new JsonArray(), new JsonObject(), manyTargets, null, null, null).ToJsonString());
        var firstTargetPageObservation = BuildObservation(manyTargetState, new JsonArray(), new JsonObject(), targetPage0, null, null, null,
            targetPageIndex: 0, totalSafeTargetCount: manyTargets.Count, moreSafeTargetsAvailable: true);
        var firstTargetPageBytes = System.Text.Encoding.UTF8.GetByteCount(firstTargetPageObservation.ToJsonString());
        if (fullTargetObservationBytes <= firstTargetPageBytes ||
            ReadInt(firstTargetPageObservation["safeSettlementTargetPage"] as JsonObject, "totalSafeTargetCount", -1) != 32 ||
            !ReadBoolean(firstTargetPageObservation["safeSettlementTargetPage"] as JsonObject, "moreAvailable"))
            throw new AgentHostException("establish-clan-recruitment-target-page-observation-failed", "A paged map observation must reduce the current prompt payload while explicitly preserving the full remaining-target count and next-page availability.");
        var settlementTargetPageBytesSaved = fullTargetObservationBytes - firstTargetPageBytes;

        var prefixStateBefore = (JsonObject)manyTargetState.DeepClone();
        prefixStateBefore["location"] = new JsonObject { ["currentSettlementId"] = null, ["targetSettlementId"] = "settlement-00", ["mapPositionX"] = 100.0 };
        prefixStateBefore["party"] = new JsonObject { ["isMoving"] = true, ["speed"] = 4.2 };
        var prefixContext = prefixStateBefore["context"] as JsonObject;
        if (prefixContext is null)
        {
            prefixContext = new JsonObject();
            prefixStateBefore["context"] = prefixContext;
        }
        prefixContext["timeControlMode"] = "StoppablePlay";
        var prefixStateAfter = (JsonObject)prefixStateBefore.DeepClone();
        prefixStateAfter["location"]!["mapPositionX"] = 101.0;
        var prefixJournal = new JsonArray(new JsonObject { ["objectiveId"] = "partySize", ["current"] = 4, ["target"] = 25 });
        var prefixObjective = new JsonObject { ["partySize"] = new JsonObject { ["current"] = 4, ["target"] = 25, ["met"] = false } };
        var movementCatalog = BuildActionCatalog(prefixStateBefore, prefixObjective, targetPage0, null, "settlement-00", moving: true);
        var movementControls = BuildControlCatalog(prefixStateBefore, moving: true, movementCatalog.Count);
        var pausedMovementState = (JsonObject)prefixStateBefore.DeepClone();
        var pausedMovementContext = pausedMovementState["context"] as JsonObject;
        if (pausedMovementContext is null) throw new AgentHostException("establish-clan-recruitment-paused-move-fixture-invalid", "The movement regression fixture needs its Native context.");
        pausedMovementContext["timeControlMode"] = "Stop";
        var pausedMovementControls = BuildControlCatalog(pausedMovementState, moving: true, movementCatalog.Count);
        if (!movementControls.Any(control => control?.GetValue<string>() == "observeAgain") ||
            pausedMovementControls.Any(control => control?.GetValue<string>() == "observeAgain"))
            throw new AgentHostException("establish-clan-recruitment-paused-move-observe-gate-failed", "PartySize may request passive observation only while Campaign time naturally advances; a paused settlement move must return to the EYC parent for Native Move recovery.");
        JsonObject BuildLegacyPromptRequest(JsonObject state, int iteration)
        {
            var oldObservation = new JsonObject
            {
                ["scope"] = "native-storymode-party-size-recruitment",
                ["state"] = state.DeepClone(),
                ["journalObjectiveSnapshot"] = prefixJournal.DeepClone(),
                ["objectiveSnapshot"] = prefixObjective.DeepClone(),
                ["visibleSafeRecruitmentSettlements"] = targetPage0.DeepClone(),
                ["currentRecruitmentOffers"] = null,
                ["currentPrisonerRecruitmentOptions"] = null,
                ["decisionFeedback"] = null
            };
            return new JsonObject
            {
                ["runId"] = "cache-prefix-probe",
                ["goal"] = "Raise the active Journal PartySize target.",
                ["goalKind"] = "active-storymode-establish-clan-party-size",
                ["iteration"] = iteration,
                ["observation"] = oldObservation,
                ["previousActionReceipt"] = null,
                ["decisionFeedback"] = null,
                ["allowedActions"] = movementCatalog.DeepClone(),
                ["allowedControls"] = movementControls.DeepClone()
            };
        }
        JsonObject BuildCacheOrderedPromptRequest(JsonObject state, int iteration) => new()
        {
            ["runId"] = "cache-prefix-probe",
            ["goal"] = "Raise the active Journal PartySize target.",
            ["goalKind"] = "active-storymode-establish-clan-party-size",
            ["observation"] = BuildObservation(state, prefixJournal, prefixObjective, targetPage0, null, null, null,
                targetPageIndex: 0, totalSafeTargetCount: manyTargets.Count, moreSafeTargetsAvailable: true),
            ["previousActionReceipt"] = null,
            ["decisionFeedback"] = null,
            ["allowedActions"] = movementCatalog.DeepClone(),
            ["allowedControls"] = movementControls.DeepClone(),
            ["iteration"] = iteration
        };
        var legacyCommonPrefixTokens = DeepSeekPromptTokenEstimator.CountCommonPrefixTokens(recruitmentSystemPrompt,
            BuildLegacyPromptRequest(prefixStateBefore, 1).ToJsonString(), BuildLegacyPromptRequest(prefixStateAfter, 2).ToJsonString());
        var cacheOrderedCommonPrefixTokens = DeepSeekPromptTokenEstimator.CountCommonPrefixTokens(recruitmentSystemPrompt,
            BuildCacheOrderedPromptRequest(prefixStateBefore, 1).ToJsonString(), BuildCacheOrderedPromptRequest(prefixStateAfter, 2).ToJsonString());
        var cacheablePrefixTokenGain = cacheOrderedCommonPrefixTokens - legacyCommonPrefixTokens;
        if (cacheablePrefixTokenGain < 100)
            throw new AgentHostException("establish-clan-recruitment-cache-prefix-order-failed", "Stable Journal/objective/visible settlement context must precede the changing Native movement state and iteration field in the serialized PartySize request; exact tokenizer prefix gain was only " + cacheablePrefixTokenGain + " tokens.");

        var mapTargetsReceipt = new JsonObject
        {
            ["status"] = "completed",
            ["data"] = new JsonObject { ["mapSettlementTargets"] = targets.DeepClone() }
        };
        var compactMapTargetsReceipt = SafeReceipt(mapTargetsReceipt, "mapSettlementTargets", null);
        var mapTargetsObservation = BuildObservation(new JsonObject(), new JsonArray(), new JsonObject(), targets, null, compactMapTargetsReceipt, null);
        if (ReadInt(compactMapTargetsReceipt["data"] as JsonObject, "visibleTargetCount", -1) != 2 ||
            compactMapTargetsReceipt["data"] is JsonObject mapReceiptData && mapReceiptData.ContainsKey("mapSettlementTargets") ||
            (mapTargetsObservation["visibleSafeRecruitmentSettlements"] as JsonArray)?.Count != 2 ||
            mapTargetsObservation.ContainsKey("previousNativeReceipt"))
            throw new AgentHostException("establish-clan-recruitment-duplicate-map-target-payload", "The current safe map targets must remain available once in the observation while the previous query receipt carries only its target count.");

        var largePriorReceipt = new JsonObject { ["action"] = "menuSelect", ["data"] = new JsonObject { ["nativeDiagnostic"] = new string('x', 4096) } };
        var singleReceiptRequest = new JsonObject
        {
            ["observation"] = BuildObservation(new JsonObject(), new JsonArray(), new JsonObject(), null, null, largePriorReceipt, null),
            ["previousActionReceipt"] = largePriorReceipt.DeepClone()
        };
        var duplicatedReceiptRequest = (JsonObject)singleReceiptRequest.DeepClone();
        (duplicatedReceiptRequest["observation"] as JsonObject)!["previousNativeReceipt"] = largePriorReceipt.DeepClone();
        var duplicateReceiptBytesRemoved = System.Text.Encoding.UTF8.GetByteCount(duplicatedReceiptRequest.ToJsonString()) -
                                           System.Text.Encoding.UTF8.GetByteCount(singleReceiptRequest.ToJsonString());
        if (duplicateReceiptBytesRemoved < 4096)
            throw new AgentHostException("establish-clan-recruitment-previous-receipt-deduplication-failed", "The model request must include the previous Native receipt once at top level, not duplicate it in the observation.");

        var offers = new JsonObject
        {
            ["data"] = new JsonObject
            {
                ["gold"] = 25,
                ["offers"] = new JsonArray
                {
                    new JsonObject { ["ownerId"] = "notable-a", ["troopId"] = "vlandian_recruit", ["slot"] = 0, ["cost"] = 20, ["available"] = true },
                    new JsonObject { ["ownerId"] = "notable-b", ["troopId"] = "vlandian_recruit", ["slot"] = 1, ["cost"] = 30, ["available"] = true },
                    new JsonObject { ["ownerId"] = "notable-a", ["troopId"] = "stale-recruit", ["slot"] = 2, ["cost"] = 1, ["available"] = false }
                }
            }
        };
        var recruitCatalog = BuildRecruitmentActionCatalog(offers, new JsonObject { ["partySize"] = new JsonObject { ["target"] = 5 } });
        var ownerIds = recruitCatalog[0]?["argumentValues"]?["ownerId"] as JsonArray;
        var troopIds = recruitCatalog[0]? ["argumentValues"]?["troopId"] as JsonArray;
        var slots = recruitCatalog[0]? ["argumentValues"]?["slot"] as JsonArray;
        if (recruitCatalog.Count != 1 || ReadString(recruitCatalog[0] as JsonObject, "action") != "recruit" ||
            ownerIds is null || ownerIds.Count != 1 || ownerIds[0]?.GetValue<string>() != "notable-a" ||
            troopIds is null || troopIds.Count != 1 || troopIds[0]?.GetValue<string>() != "vlandian_recruit" ||
            slots is null || slots.Count != 1 || slots[0]?.GetValue<int>() != 0)
            throw new AgentHostException("establish-clan-recruitment-catalog-failed", "The recruitment catalog must bind an affordable offer to its exact current owner, troop and VM slot; unaffordable/stale offers stay hidden.");
        var underfundedOffers = (JsonObject)offers.DeepClone();
        underfundedOffers["data"]!["gold"] = 10;
        var settlementState = new JsonObject { ["location"] = new JsonObject { ["currentSettlementId"] = "town-a" } };
        var noAffordableEvent = BuildNoAffordableVolunteerOfferTraceStep(underfundedOffers,
            new JsonObject { ["partySize"] = new JsonObject { ["target"] = 5 } }, settlementState, 91077.9);
        var fundedEvent = BuildNoAffordableVolunteerOfferTraceStep(offers,
            new JsonObject { ["partySize"] = new JsonObject { ["target"] = 5 } }, settlementState, 91077.9);
        if (noAffordableEvent is null || ReadString(noAffordableEvent, "settlementId") != "town-a" ||
            ReadDouble(noAffordableEvent, "campaignDay") != 91077.9 || ReadDouble(noAffordableEvent, "gold") != 10 || fundedEvent is not null)
            throw new AgentHostException("establish-clan-recruitment-no-offer-trace-builder-failed", "Only an exact current settlement RecruitmentVM snapshot with zero affordable volunteer actions may create the same-day no-offer cooldown record.");

        using var noOfferCooldownRequest = JsonDocument.Parse("""
            {"runId":"same-day-no-offer-cooldown-selftest","goal":"Raise the active Journal PartySize target.","maxDecisions":12,"maxElapsedSeconds":10}
            """);
        var firstNoOfferClient = new FakeNoOfferCooldownNativeClient(startAtTown: true);
        var firstNoOfferProvider = new FakeNoOfferCooldownDecisionProvider(queryMapTargets: false);
        var firstNoOfferRun = await RunAsync(noOfferCooldownRequest.RootElement, firstNoOfferClient, firstNoOfferClient,
            firstNoOfferClient, firstNoOfferProvider, CancellationToken.None);
        var noOfferEvent = (firstNoOfferRun["trace"] as JsonArray)?.OfType<JsonObject>()
            .FirstOrDefault(step => ReadString(step, "stage") == "recruitment-settlement-no-affordable-volunteer-offers");
        var secondNoOfferClient = new FakeNoOfferCooldownNativeClient(startAtTown: false, targetCount: 32);
        var secondNoOfferProvider = new FakeNoOfferCooldownDecisionProvider(queryMapTargets: true, continueTargetPages: true);
        var secondNoOfferRun = await RunAsync(noOfferCooldownRequest.RootElement, secondNoOfferClient, secondNoOfferClient,
            secondNoOfferClient, secondNoOfferProvider, CancellationToken.None, priorTrace: firstNoOfferRun["trace"] as JsonArray);
        if (ReadString(firstNoOfferRun["termination"] as JsonObject, "reason") != "recruitment-model-stopped-with-safe-actions" ||
            noOfferEvent is null || ReadString(noOfferEvent, "settlementId") != "town-a" ||
            ReadString(secondNoOfferRun["termination"] as JsonObject, "reason") != "recruitment-model-stopped-with-safe-actions" ||
            !secondNoOfferProvider.MoveCatalogObserved || secondNoOfferProvider.ObservedMoveSettlementIds.Count != 31 ||
            secondNoOfferProvider.ObservedMoveSettlementIds.Contains("town-a") || !secondNoOfferProvider.ObservedMoveSettlementIds.Contains("settlement-01") ||
            secondNoOfferProvider.TargetPages.Select(page => page.PageStartIndex).SequenceEqual(new[] { 0, 12, 24 }) != true ||
            secondNoOfferProvider.TargetPages.Select(page => page.PageSize).SequenceEqual(new[] { 12, 12, 7 }) != true ||
            secondNoOfferProvider.PageMoreActionCount != 2 || !secondNoOfferClient.CampaignActions.SequenceEqual(["mapSettlementTargets"], StringComparer.Ordinal))
            throw new AgentHostException("establish-clan-recruitment-cross-subflow-no-offer-cooldown-failed", "A same-day Native no-affordable-offer trace must survive the PartySize child restart, omit only the exhausted settlement, and expose every other safe target over pages. first=" + ReadString(firstNoOfferRun["termination"] as JsonObject, "reason") + "; event=" + ReadString(noOfferEvent, "settlementId") + "; second=" + ReadString(secondNoOfferRun["termination"] as JsonObject, "reason") + "; targets=" + secondNoOfferProvider.ObservedMoveSettlementIds.Count + "; moreActions=" + secondNoOfferProvider.PageMoreActionCount + "; pages=" + string.Join(";", secondNoOfferProvider.TargetPages.Select(page => page.PageStartIndex + ":" + page.PageSize)) + "; campaignActions=" + string.Join(",", secondNoOfferClient.CampaignActions) + "; providerCalls=" + secondNoOfferProvider.CallCount + ".");
        var currentPrisonerOptions = new JsonObject
        {
            ["status"] = "completed",
            ["data"] = new JsonObject
            {
                ["memberCount"] = 11, ["partySizeLimit"] = 20, ["nativeDoneConfirmationRequiredForOne"] = false,
                ["mainPartyPrisonerCount"] = 15, ["mainPartyPrisonerLimit"] = 13,
                ["nativePrisonerLimitWarningAfterOneRecruit"] = true,
                ["nativePrisonerLimitConfirmationText"] = "The prisoner roster exceeds its limit; prisoners may escape.",
                ["options"] = new JsonArray(new JsonObject
                {
                    ["troopId"] = "looter", ["troopName"] = "Bandit", ["currentCount"] = 15,
                    ["currentConformityXp"] = 496, ["conformityXpPerRecruit"] = 134,
                    ["availableCount"] = 3, ["isAvailable"] = true, ["moraleEffectPerRecruit"] = -2
                })
            }
        };
        var prisonerMapState = new JsonObject
        {
            ["context"] = new JsonObject { ["gameState"] = "MapState", ["menuId"] = null, ["inquiryOpen"] = false, ["encounterActive"] = false },
            ["party"] = new JsonObject { ["members"] = 11, ["prisoners"] = 15, ["sizeLimit"] = 20, ["isMoving"] = false },
            ["availableMenuOptions"] = new JsonArray()
        };
        var currentPartyObjective = new JsonObject { ["partySize"] = new JsonObject { ["current"] = 11, ["target"] = 25, ["met"] = false } };
        var prisonerActionCatalog = BuildActionCatalog(prisonerMapState, currentPartyObjective, new JsonArray(), null, null, false, currentPrisonerOptions);
        var prisonerAction = prisonerActionCatalog.OfType<JsonObject>().FirstOrDefault(item => ReadString(item, "action") == "recruitPrisoner");
        var prisonerTroopValues = prisonerAction?["argumentValues"]?["TroopId"] as JsonArray;
        var prisonerWarningValues = prisonerAction?["argumentValues"]?["ConfirmPrisonerLimitWarning"] as JsonArray;
        var prisonerOptionsObservation = BuildObservation(prisonerMapState, new JsonArray(), currentPartyObjective, null, null, null, null, currentPrisonerOptions);
        var compactPrisonerReceipt = SafeReceipt(currentPrisonerOptions, "prisonerRecruitmentOptions", null);
        var prisonerDecision = new JsonObject
        {
            ["action"] = "recruitPrisoner",
            ["arguments"] = new JsonObject { ["TroopId"] = "looter", ["ConfirmPartySizeWarning"] = 0, ["ConfirmPrisonerLimitWarning"] = 1 }
        };
        if (prisonerAction is null || prisonerTroopValues?.Count != 1 || prisonerTroopValues[0]?.GetValue<string>() != "looter" ||
            prisonerWarningValues?.Count != 1 || prisonerWarningValues[0]?.GetValue<int>() != 1 ||
            ReadInt(prisonerOptionsObservation["currentPrisonerRecruitmentOptions"] as JsonObject, "mainPartyPrisonerCount", -1) != 15 ||
            (prisonerOptionsObservation["currentPrisonerRecruitmentOptions"]?["options"] as JsonArray)?.Count != 1 ||
            compactPrisonerReceipt["data"]?["options"] is not null || ReadInt(compactPrisonerReceipt["data"] as JsonObject, "availableOfferCount", -1) != 1 ||
            !TryResolveRecruitmentAction(prisonerDecision, prisonerMapState, new JsonArray(), null, null, false,
                out var prisonerActionName, out var prisonerArguments, out _, out _, currentPrisonerOptions) ||
            prisonerActionName != "recruitPrisoner" || ReadString(prisonerArguments, "troopId") != "looter" ||
            ReadInt(prisonerArguments, "confirmPrisonerLimitWarning", -1) != 1)
            throw new AgentHostException("establish-clan-recruitment-prisoner-limit-catalog-failed", "The EYC PartySize catalog must expose current recruitable prisoners and require an explicit, separate choice for the Native prisoner-limit warning.");
        var decliningPrisonerWarning = prisonerDecision.DeepClone().AsObject();
        decliningPrisonerWarning["arguments"]!["ConfirmPrisonerLimitWarning"] = 0;
        if (TryResolveRecruitmentAction(decliningPrisonerWarning, prisonerMapState, new JsonArray(), null, null, false,
                out _, out _, out _, out _, currentPrisonerOptions))
            throw new AgentHostException("establish-clan-recruitment-prisoner-limit-decline-accepted", "A prisoner-limit warning response not present in the current action catalog was accepted.");
        var compactOfferSummary = BuildRecruitmentOffersObservation(offers);
        var compactOfferReceipt = SafeReceipt(offers, "recruitOptions", null);
        var offerObservation = BuildObservation(new JsonObject(), new JsonArray(), new JsonObject(), null, offers, compactOfferReceipt, null);
        var currentActionOffers = recruitCatalog[0]?["currentOffers"] as JsonArray;
        if (ReadInt(compactOfferSummary, "affordableOfferCount", -1) != 1 ||
            offerObservation["currentRecruitmentOffers"] is not JsonObject offerSummary || offerSummary.ContainsKey("offers") ||
            compactOfferReceipt["data"] is not JsonObject offerReceiptSummary || offerReceiptSummary.ContainsKey("offers") ||
            currentActionOffers?.Count != 1 || ReadString(currentActionOffers[0] as JsonObject, "ownerId") != "notable-a")
            throw new AgentHostException("establish-clan-recruitment-duplicate-offer-payload", "The decision observation must provide aggregate RecruitmentVM counts while the listed recruit action alone retains exact current affordable offers.");

        var selection = new JsonObject
        {
            ["action"] = "recruit",
            ["arguments"] = new JsonObject { ["ownerId"] = "notable-a", ["troopId"] = "vlandian_recruit", ["slot"] = 0, ["confirmPartySizeWarning"] = 1 }
        };
        var recruitmentMenu = new JsonObject
        {
            ["context"] = new JsonObject { ["gameState"] = "MapState", ["menuId"] = "town" },
            ["availableMenuOptions"] = new JsonArray(new JsonObject { ["id"] = RecruitmentMenuOptionId, ["available"] = true, ["enabled"] = true })
        };
        if (!TryResolveRecruitmentAction(selection, recruitmentMenu, null, offers, null, false, out var action, out _, out _, out _) || action != "recruit")
            throw new AgentHostException("establish-clan-recruitment-current-offer-rejected", "The current affordable Native volunteer offer was not resolvable.");

        var safeBulkOffers = new JsonObject
        {
            ["data"] = new JsonObject
            {
                ["gold"] = 100, ["partySize"] = 1, ["partyCapacity"] = 20,
                ["offers"] = new JsonArray
                {
                    new JsonObject { ["ownerId"] = "notable-a", ["troopId"] = "vlandian_recruit", ["slot"] = 0, ["cost"] = 20, ["available"] = true },
                    new JsonObject { ["ownerId"] = "notable-b", ["troopId"] = "imperial_recruit", ["slot"] = 1, ["cost"] = 30, ["available"] = true }
                }
            }
        };
        var safeBulkObjective = new JsonObject { ["partySize"] = new JsonObject { ["current"] = 1, ["target"] = 5 } };
        var safeBulkCatalog = BuildRecruitmentActionCatalog(safeBulkOffers, safeBulkObjective);
        var safeBulkAction = safeBulkCatalog.OfType<JsonObject>().FirstOrDefault(item => ReadString(item, "action") == "recruitAll");
        var safeBulkValues = safeBulkAction?["argumentValues"] as JsonObject;
        var bulkArguments = safeBulkValues is null ? new JsonObject() : new JsonObject
        {
            ["expectedCount"] = safeBulkValues["expectedCount"]![0]!.DeepClone(),
            ["expectedTotalCost"] = safeBulkValues["expectedTotalCost"]![0]!.DeepClone(),
            ["expectedPartySize"] = safeBulkValues["expectedPartySize"]![0]!.DeepClone(),
            ["expectedPartyCapacity"] = safeBulkValues["expectedPartyCapacity"]![0]!.DeepClone(),
            ["expectedJournalTarget"] = safeBulkValues["expectedJournalTarget"]![0]!.DeepClone(),
            ["expectedOfferSetSha256"] = safeBulkValues["expectedOfferSetSha256"]![0]!.DeepClone()
        };
        if (safeBulkAction is null || ReadInt(bulkArguments, "expectedCount", -1) != 2 ||
            ReadInt(bulkArguments, "expectedTotalCost", -1) != 50 ||
            !TryResolveRecruitmentAction(new JsonObject { ["action"] = "recruitAll", ["arguments"] = bulkArguments },
                recruitmentMenu, null, safeBulkOffers, null, false, out var bulkActionName, out var canonicalBulkArguments, out _, out _,
                objective: safeBulkObjective) || bulkActionName != "recruitAll" ||
            ReadString(canonicalBulkArguments, "expectedOfferSetSha256") != ReadString(bulkArguments, "expectedOfferSetSha256"))
            throw new AgentHostException("establish-clan-recruitment-native-take-all-catalog-failed", "Native Take All may be listed only for the exact current offer set when all selected people fit the original Journal target, MainParty capacity and Gold.");
        var unsafeBulkObjectives = new JsonObject { ["partySize"] = new JsonObject { ["current"] = 1, ["target"] = 2 } };
        if (BuildRecruitmentActionCatalog(safeBulkOffers, unsafeBulkObjectives).OfType<JsonObject>().Any(item => ReadString(item, "action") == "recruitAll"))
            throw new AgentHostException("establish-clan-recruitment-native-take-all-exceeds-journal-target", "Native Take All must not be offered when its full current offer set would overshoot the EYC Journal target.");
        var tooLittleGold = (JsonObject)safeBulkOffers.DeepClone();
        tooLittleGold["data"]!["gold"] = 49;
        if (BuildRecruitmentActionCatalog(tooLittleGold, safeBulkObjective).OfType<JsonObject>().Any(item => ReadString(item, "action") == "recruitAll"))
            throw new AgentHostException("establish-clan-recruitment-native-take-all-exceeds-gold", "Native Take All must not be offered when its total Native RecruitmentVM cost exceeds current Gold.");
        var staleBulkDecision = new JsonObject { ["action"] = "recruitAll", ["arguments"] = (JsonObject)bulkArguments.DeepClone() };
        staleBulkDecision["arguments"]!["expectedOfferSetSha256"] = "stale";
        if (TryResolveRecruitmentAction(staleBulkDecision, recruitmentMenu, null, safeBulkOffers, null, false,
                out _, out _, out _, out _, objective: safeBulkObjective))
            throw new AgentHostException("establish-clan-recruitment-native-take-all-stale-offer-set-accepted", "A batch action with an offer-set fingerprint different from the exact current catalog must be rejected before the Native command.");
        var stringNumericSelection = selection.DeepClone().AsObject();
        stringNumericSelection["arguments"]!["slot"] = "0";
        stringNumericSelection["arguments"]!["confirmPartySizeWarning"] = "1";
        if (!TryResolveRecruitmentAction(stringNumericSelection, recruitmentMenu, null, offers, null, false, out var canonicalAction, out var canonicalArguments, out _, out _) ||
            canonicalAction != "recruit" || ReadInt(canonicalArguments, "slot", -1) != 0 || ReadInt(canonicalArguments, "confirmPartySizeWarning", -1) != 1)
            throw new AgentHostException("establish-clan-recruitment-string-integer-not-normalized", "Canonical decimal integer strings from the provider must normalize to the same in-range native offer values.");
        var nonCanonicalStringNumericSelection = selection.DeepClone().AsObject();
        nonCanonicalStringNumericSelection["arguments"]!["slot"] = "00";
        if (TryResolveRecruitmentAction(nonCanonicalStringNumericSelection, recruitmentMenu, null, offers, null, false, out _, out _, out _, out _))
            throw new AgentHostException("establish-clan-recruitment-noncanonical-integer-accepted", "Noncanonical numeric strings must not be normalized into a Native offer.");
        var stale = selection.DeepClone().AsObject();
        stale["arguments"]!["slot"] = 7;
        if (TryResolveRecruitmentAction(stale, recruitmentMenu, null, offers, null, false, out _, out _, out _, out _))
            throw new AgentHostException("establish-clan-recruitment-stale-offer-accepted", "A recruitment slot not present in the fresh Native RecruitmentVM receipt was accepted.");

        var unavailableOffers = new JsonObject
        {
            ["data"] = new JsonObject
            {
                ["gold"] = 1000,
                ["partySize"] = 1,
                ["partyCapacity"] = 20,
                ["offers"] = new JsonArray
                {
                    new JsonObject { ["ownerId"] = "notable-a", ["troopId"] = "imperial_recruit", ["slot"] = 0, ["cost"] = 20, ["available"] = false },
                    new JsonObject { ["ownerId"] = "notable-b", ["troopId"] = "imperial_recruit", ["slot"] = 1, ["cost"] = 20, ["available"] = false }
                }
            }
        };
        var townWithoutRecruitableOffers = new JsonObject
        {
            ["context"] = new JsonObject
            {
                ["gameState"] = "MapState", ["menuId"] = "town", ["encounterActive"] = true,
                ["encounteredPartyId"] = "town-a", ["captivity"] = new JsonObject { ["isCaptive"] = false }
            },
            ["location"] = new JsonObject { ["currentSettlementId"] = "town-a" },
            ["availableMenuOptions"] = new JsonArray(
                new JsonObject { ["id"] = RecruitmentMenuOptionId, ["available"] = true, ["enabled"] = true },
                new JsonObject { ["id"] = "town_leave", ["available"] = true, ["enabled"] = true, ["isLeave"] = true })
        };
        var noOfferCatalog = BuildActionCatalog(townWithoutRecruitableOffers,
            new JsonObject { ["partySize"] = new JsonObject { ["target"] = 20 } }, null, unavailableOffers, null, false);
        var noOfferLeaveOption = noOfferCatalog.Count == 0 ? null : (noOfferCatalog[0]?["argumentValues"]?["OptionId"] as JsonArray)?[0]?.GetValue<string>();
        if (noOfferCatalog.Count != 1 || ReadString(noOfferCatalog[0] as JsonObject, "action") != "menuSelect" || noOfferLeaveOption != "town_leave")
            throw new AgentHostException("establish-clan-recruitment-unavailable-offers-looped", "After the current Native RecruitmentVM returns no affordable/available volunteers, the subgoal must expose the current settlement's Native Leave action instead of querying the same unavailable offers again.");

        var recruitOptionsRecovery = BuildSafeStopRecoveryInstruction(new JsonArray(new JsonObject { ["action"] = "recruitOptions" }));
        if (!recruitOptionsRecovery.Contains("does not recruit anyone or spend Gold", StringComparison.Ordinal) ||
            !recruitOptionsRecovery.Contains("current original RecruitmentVM", StringComparison.Ordinal))
            throw new AgentHostException("establish-clan-recruitment-recruit-options-recovery-unclear", "When a model stops while only the Native offer query remains, recovery must explicitly explain that recruitOptions is read-only before asking the model to use it.");

        var trainingFieldMenu = new JsonObject
        {
            ["context"] = new JsonObject
            {
                ["gameState"] = "MapState", ["menuId"] = "training_field_menu", ["encounterActive"] = true,
                ["encounteredPartyId"] = "tutorial_training_field", ["captivity"] = new JsonObject { ["isCaptive"] = false }
            },
            ["location"] = new JsonObject { ["currentSettlementId"] = "tutorial_training_field" },
            ["availableMenuOptions"] = new JsonArray(new JsonObject { ["id"] = "training_field_leave", ["available"] = true, ["enabled"] = true, ["isLeave"] = true })
        };
        var trainingFieldCatalog = BuildActionCatalog(trainingFieldMenu, new JsonObject { ["partySize"] = new JsonObject { ["target"] = 5 } }, null, null, null, false);
        var trainingFieldLeaveOption = trainingFieldCatalog.Count == 0 ? null : (trainingFieldCatalog[0]?["argumentValues"]?["OptionId"] as JsonArray)?[0]?.GetValue<string>();
        if (trainingFieldCatalog.Count != 1 || ReadString(trainingFieldCatalog[0] as JsonObject, "action") != "menuSelect" || trainingFieldLeaveOption != "training_field_leave")
            throw new AgentHostException("establish-clan-recruitment-training-field-menu-not-exitable", "The original post-tutorial training-field location menu must remain leaveable before party recruitment begins.");

        var villagersInNeedTextState = VillagersInNeedConversationState(options: new JsonArray());
        var villagersContinueCatalog = BuildActionCatalog(villagersInNeedTextState,
            new JsonObject { ["partySize"] = new JsonObject { ["target"] = 5 } }, null, null, null, false);
        if (villagersContinueCatalog.Count != 1 || ReadString(villagersContinueCatalog[0] as JsonObject, "action") != "dialogueContinue" ||
            !TryResolveRecruitmentAction(new JsonObject { ["action"] = "dialogueContinue", ["arguments"] = new JsonObject() },
                villagersInNeedTextState, null, null, null, false, out var continueAction, out _, out _, out _) || continueAction != "dialogueContinue")
            throw new AgentHostException("establish-clan-villagers-in-need-continue-not-listed", "The exact Native VillagersInNeed conversation may advance only through dialogueContinue while it has no selectable option.");

        var villagersInNeedChoiceState = VillagersInNeedConversationState(new JsonArray(
            new JsonObject { ["id"] = "adg:131", ["textId"] = VillagersInNeedVillaMissionStartTextId, ["text"] = "Lead on.", ["clickable"] = true },
            new JsonObject { ["id"] = "adg:132", ["textId"] = VillagersInNeedDeferTextId, ["text"] = "I have to take care of something else, first.", ["clickable"] = true },
            new JsonObject { ["id"] = "villagers_hidden", ["text"] = "hidden", ["clickable"] = false }));
        var villagersChoiceCatalog = BuildActionCatalog(villagersInNeedChoiceState,
            new JsonObject { ["partySize"] = new JsonObject { ["target"] = 5 } }, null, null, null, false);
        var villagersOptionIds = villagersChoiceCatalog.Count == 1 ? villagersChoiceCatalog[0]? ["argumentValues"]? ["OptionId"] as JsonArray : null;
        if (villagersChoiceCatalog.Count != 1 || ReadString(villagersChoiceCatalog[0] as JsonObject, "action") != "dialogueSelect" ||
            villagersOptionIds?.Count != 1 || villagersOptionIds[0]?.GetValue<string>() != "adg:132" ||
            villagersOptionIds.Any(option => option?.GetValue<string>() == "villagers_hidden") ||
            !TryResolveRecruitmentAction(new JsonObject { ["action"] = "dialogueSelect", ["arguments"] = new JsonObject { ["OptionId"] = "adg:132" } },
                villagersInNeedChoiceState, null, null, null, false, out var selectAction, out _, out _, out _) || selectAction != "dialogueSelect" ||
            TryResolveRecruitmentAction(new JsonObject { ["action"] = "dialogueSelect", ["arguments"] = new JsonObject { ["OptionId"] = "adg:131" } },
                villagersInNeedChoiceState, null, null, null, false, out _, out _, out _, out _) ||
            TryResolveRecruitmentAction(new JsonObject { ["action"] = "dialogueSelect", ["arguments"] = new JsonObject { ["OptionId"] = "villagers_hidden" } },
                villagersInNeedChoiceState, null, null, null, false, out _, out _, out _, out _))
            throw new AgentHostException("establish-clan-villagers-in-need-options-not-current", "Only current clickable VillagersInNeed answers may be selected; the localized Native option that starts the excluded Villa Mission must be omitted and rejected.");

        var unrelatedMissionState = VillagersInNeedConversationState(new JsonArray(), "unrelated_character");
        if (BuildActionCatalog(unrelatedMissionState, new JsonObject { ["partySize"] = new JsonObject { ["target"] = 5 } }, null, null, null, false).Count != 0)
            throw new AgentHostException("establish-clan-recruitment-unrelated-mission-action-leaked", "A generic Village/Town Mission must not inherit this one StoryMode-specific conversation recovery route.");

        var mapConversationState = new JsonObject
        {
            ["context"] = new JsonObject
            {
                ["gameState"] = "MapState",
                ["menuId"] = null,
                ["conversation"] = new JsonObject
                {
                    ["characterId"] = "notable-a",
                    ["sentenceText"] = "A current Native map dialogue line.",
                    ["options"] = new JsonArray(
                        new JsonObject { ["id"] = "current-option", ["text"] = "A visible reply.", ["clickable"] = true },
                        new JsonObject { ["id"] = "hidden-option", ["text"] = "Unavailable reply.", ["clickable"] = false })
                }
            },
            ["location"] = new JsonObject { ["currentSettlementId"] = null, ["targetSettlementId"] = "village-a" },
            ["party"] = new JsonObject { ["isMoving"] = true }
        };
        var mapConversationTargets = new JsonArray(new JsonObject { ["id"] = "village-a", ["type"] = "village", ["distance"] = 1.0, ["hostile"] = false, ["underSiege"] = false });
        var mapConversationCatalog = BuildActionCatalog(mapConversationState,
            new JsonObject { ["partySize"] = new JsonObject { ["target"] = 5 } }, mapConversationTargets, null, "village-a", moving: true);
        var mapOptionIds = mapConversationCatalog.Count == 1 ? mapConversationCatalog[0]?["argumentValues"]?["OptionId"] as JsonArray : null;
        if (mapConversationCatalog.Count != 1 || ReadString(mapConversationCatalog[0] as JsonObject, "action") != "dialogueSelect" ||
            mapOptionIds?.Count != 1 || mapOptionIds[0]?.GetValue<string>() != "current-option" ||
            !TryResolveRecruitmentAction(new JsonObject { ["action"] = "dialogueSelect", ["arguments"] = new JsonObject { ["OptionId"] = "current-option" } },
                mapConversationState, mapConversationTargets, null, "village-a", moving: true, out var mapSelectAction, out _, out _, out _) ||
            mapSelectAction != "dialogueSelect" ||
            TryResolveRecruitmentAction(new JsonObject { ["action"] = "dialogueSelect", ["arguments"] = new JsonObject { ["OptionId"] = "hidden-option" } },
                mapConversationState, mapConversationTargets, null, "village-a", moving: true, out _, out _, out _, out _))
            throw new AgentHostException("establish-clan-recruitment-map-conversation-options-not-current", "A current MapState conversation must override movement waiting and expose only its clickable Native replies, rejecting hidden or stale choices.");

        var mapConversationTextOnly = (JsonObject)mapConversationState.DeepClone();
        ((mapConversationTextOnly["context"]?["conversation"] as JsonObject)!["options"] as JsonArray)!.Clear();
        var mapContinueCatalog = BuildActionCatalog(mapConversationTextOnly,
            new JsonObject { ["partySize"] = new JsonObject { ["target"] = 5 } }, mapConversationTargets, null, "village-a", moving: true);
        if (mapContinueCatalog.Count != 1 || ReadString(mapContinueCatalog[0] as JsonObject, "action") != "dialogueContinue" ||
            !TryResolveRecruitmentAction(new JsonObject { ["action"] = "dialogueContinue", ["arguments"] = new JsonObject() },
                mapConversationTextOnly, mapConversationTargets, null, "village-a", moving: true, out var mapContinueAction, out _, out _, out _) ||
            mapContinueAction != "dialogueContinue")
            throw new AgentHostException("establish-clan-recruitment-map-conversation-continue-not-current", "A Native MapState line with no current options must expose only its original dialogueContinue while moving.");

        var gangIssueTownState = new JsonObject
        {
            ["context"] = new JsonObject { ["gameState"] = "MapState", ["menuId"] = "town", ["encounterActive"] = false },
            ["location"] = new JsonObject { ["currentSettlementId"] = "town_V2" },
            ["party"] = new JsonObject { ["isMoving"] = false, ["prisoners"] = 0 },
            ["settlementOverlayCharacters"] = new JsonArray(
                new JsonObject
                {
                    ["heroId"] = "gang-leader", ["isNotable"] = true,
                    ["questMarkers"] = new JsonArray(new JsonObject { ["type"] = "AvailableIssue", ["title"] = GangLeaderRecruitsIssueTitleZh })
                },
                new JsonObject
                {
                    ["heroId"] = "headman", ["isNotable"] = true,
                    ["questMarkers"] = new JsonArray(new JsonObject { ["type"] = "AvailableIssue", ["title"] = "需要工具" })
                }),
            ["availableMenuOptions"] = new JsonArray(
                new JsonObject { ["id"] = "recruit_volunteers", ["available"] = true, ["enabled"] = true, ["isLeave"] = false },
                new JsonObject { ["id"] = "town_leave", ["available"] = true, ["enabled"] = true, ["isLeave"] = true })
        };
        var gangNoOfferReceipt = new JsonObject { ["action"] = "recruitOptions", ["status"] = "completed", ["data"] = new JsonObject { ["offers"] = new JsonArray(), ["gold"] = 0 } };
        var gangGivers = GetVisibleGangLeaderRecruitsIssueGivers(gangIssueTownState);
        var gangContacted = new HashSet<string>(StringComparer.Ordinal) { "gang-leader" };
        var availableGangCatalog = BuildActionCatalog(gangIssueTownState,
            new JsonObject { ["partySize"] = new JsonObject { ["current"] = 1, ["target"] = 25, ["met"] = false } },
            null, gangNoOfferReceipt, null, false, contactedGangLeaderIssueGivers: new HashSet<string>(StringComparer.Ordinal));
        var contactedAvailableGangCatalog = BuildActionCatalog(gangIssueTownState,
            new JsonObject { ["partySize"] = new JsonObject { ["current"] = 1, ["target"] = 25, ["met"] = false } },
            null, gangNoOfferReceipt, null, false, contactedGangLeaderIssueGivers: gangContacted);
        var activeGangIssueState = (JsonObject)gangIssueTownState.DeepClone();
        activeGangIssueState["settlementOverlayCharacters"]![0]!["questMarkers"]![0]!["type"] = "ActiveIssue";
        var activeGangCatalog = BuildActionCatalog(activeGangIssueState,
            new JsonObject { ["partySize"] = new JsonObject { ["current"] = 1, ["target"] = 25, ["met"] = false } },
            null, gangNoOfferReceipt, null, false, contactedGangLeaderIssueGivers: gangContacted);
        var talkAction = availableGangCatalog.OfType<JsonObject>().FirstOrDefault(action => ReadString(action, "action") == "talkToSettlementHero");
        if (gangGivers.Length != 1 || gangGivers[0] != "gang-leader" ||
            talkAction?["argumentValues"]?["HeroId"]?.AsArray().Count != 1 ||
            talkAction["argumentValues"]?["HeroId"]?[0]?.GetValue<string>() != "gang-leader" ||
            contactedAvailableGangCatalog.OfType<JsonObject>().Any(action => ReadString(action, "action") == "talkToSettlementHero") ||
            !activeGangCatalog.OfType<JsonObject>().Any(action => ReadString(action, "action") == "talkToSettlementHero") ||
            !TryResolveRecruitmentAction(new JsonObject { ["action"] = "talkToSettlementHero", ["arguments"] = new JsonObject { ["HeroId"] = "gang-leader" } },
                gangIssueTownState, null, gangNoOfferReceipt, null, false, out var talkGangAction, out var talkGangArgs, out _, out _,
                contactedGangLeaderIssueGivers: new HashSet<string>(StringComparer.Ordinal)) ||
            talkGangAction != "talkToSettlementHero" || ReadString(talkGangArgs, "heroId") != "gang-leader" ||
            TryResolveRecruitmentAction(new JsonObject { ["action"] = "talkToSettlementHero", ["arguments"] = new JsonObject { ["HeroId"] = "headman" } },
                gangIssueTownState, null, gangNoOfferReceipt, null, false, out _, out _, out _, out _,
                contactedGangLeaderIssueGivers: new HashSet<string>(StringComparer.Ordinal)))
            throw new AgentHostException("establish-clan-gang-leader-issue-current-overlay-contact-failed", "The EYC PartySize route must expose only a current visible Gang Leader Needs Recruits giver, avoid repeating a declined AvailableIssue, and permit a current ActiveIssue delivery contact.");

        var gangIssueConversationState = (JsonObject)gangIssueTownState.DeepClone();
        gangIssueConversationState["context"]!["menuId"] = null;
        gangIssueConversationState["context"]!["conversation"] = new JsonObject
        {
            ["heroId"] = "gang-leader", ["sentenceText"] = "I have recruited the people you asked for.",
            ["options"] = new JsonArray(
                new JsonObject { ["id"] = "issue_offer_player_accept_quest", ["text"] = "I brought the recruits.", ["clickable"] = true },
                new JsonObject { ["id"] = GangLeaderRecruitsAlternativeOptionId, ["text"] = "Send a companion.", ["clickable"] = true },
                new JsonObject { ["id"] = GangLeaderRecruitsLordOptionId, ["text"] = "Ask a lord.", ["clickable"] = true },
                new JsonObject { ["id"] = "player_is_leaving_neutral_or_friendly", ["text"] = "I must be going.", ["clickable"] = true })
        };
        var gangConversationCatalog = BuildActionCatalog(gangIssueConversationState,
            new JsonObject { ["partySize"] = new JsonObject { ["current"] = 1, ["target"] = 25, ["met"] = false } },
            null, null, null, false, contactedGangLeaderIssueGivers: gangContacted);
        var gangConversationIds = gangConversationCatalog.FirstOrDefault()? ["argumentValues"]? ["OptionId"] as JsonArray;
        var gangDirectOptionListed = gangConversationIds?.Any(option => option?.GetValue<string>() == GangLeaderRecruitsDirectAcceptanceOptionId) == true;
        var gangAlternativeOptionListed = gangConversationIds?.Any(option => option?.GetValue<string>() is GangLeaderRecruitsAlternativeOptionId or GangLeaderRecruitsLordOptionId) == true;
        var gangDirectResolved = TryResolveRecruitmentAction(new JsonObject { ["action"] = "dialogueSelect", ["arguments"] = new JsonObject { ["OptionId"] = GangLeaderRecruitsDirectAcceptanceOptionId } },
                gangIssueConversationState, null, null, null, false, out var gangDialogueAction, out var gangDialogueArgs, out _, out _,
                contactedGangLeaderIssueGivers: gangContacted);
        var gangAlternativeResolved = TryResolveRecruitmentAction(new JsonObject { ["action"] = "dialogueSelect", ["arguments"] = new JsonObject { ["OptionId"] = GangLeaderRecruitsAlternativeOptionId } },
                gangIssueConversationState, null, null, null, false, out _, out _, out _, out _,
                contactedGangLeaderIssueGivers: gangContacted);
        if (!gangDirectOptionListed || gangAlternativeOptionListed || !gangDirectResolved ||
            gangDialogueAction != "dialogueSelect" || ReadString(gangDialogueArgs, "optionId") != GangLeaderRecruitsDirectAcceptanceOptionId || gangAlternativeResolved)
            throw new AgentHostException("establish-clan-gang-leader-issue-direct-route-only-failed", $"The current Gang Leader conversation must allow its direct visible quest/handoff route and neutral exit while excluding the known companion and lord alternatives. listed={string.Join(",", gangConversationIds?.Select(option => option?.GetValue<string>()) ?? Array.Empty<string>())}; directResolved={gangDirectResolved}; directAction={gangDialogueAction}; directArgument={ReadString(gangDialogueArgs, "optionId")}; alternativeResolved={gangAlternativeResolved}");

        var results = new List<object>
        {
            new { scenario = "establish-clan-recruitment-orders-stable-context-before-changing-map-state-for-prefix-cache", legacyCommonPrefixTokens, cacheOrderedCommonPrefixTokens, cacheablePrefixTokenGain, passed = true },
            new { scenario = "establish-clan-recruitment-sends-previous-native-receipt-once", duplicateReceiptBytesRemoved, passed = true },
            new { scenario = "establish-clan-party-size-executor-matches-autonomous-parent-budget", maxDecisions = MaxDecisions, maxElapsedSeconds = (int)MaxElapsed.TotalSeconds, passed = true },
            new { scenario = "establish-clan-recruitment-travels-only-to-current-safe-town-village-targets", passed = true },
            new { scenario = "establish-clan-recruitment-offers-only-current-affordable-volunteers", passed = true },
            new { scenario = "native-recruit-all-is-cost-and-target-bounded-with-fresh-offer-set", offeredCount = 2, totalCost = 50, passed = true },
            new { scenario = "establish-clan-party-size-offers-current-prisoner-route-and-separate-native-prisoner-limit-confirmation", passed = true },
            new { scenario = "establish-clan-recruitment-rejects-stale-volunteer-identifiers", passed = true },
            new { scenario = "establish-clan-recruitment-leaves-town-after-current-vm-has-no-available-affordable-volunteers", passed = true },
            new { scenario = "establish-clan-recruitment-same-day-no-offer-memory-survives-party-size-subflow-restart", passed = true },
            new { scenario = "establish-clan-recruitment-pages-complete-safe-settlement-set", targetCount = manyTargets.Count,
                pageSize = SettlementTargetPageSize, pageCount = 3, fullObservationBytes = fullTargetObservationBytes,
                firstPageObservationBytes = firstTargetPageBytes, observationBytesSaved = settlementTargetPageBytesSaved, passed = true }
        };
        results.Add(new { scenario = "establish-clan-recruitment-resolves-current-map-conversation-before-resuming-movement", passed = true });
        results.Add(new { scenario = "establish-clan-recruitment-continues-only-no-choice-map-conversation", passed = true });
        results.Add(new { scenario = "establish-clan-party-size-exposes-only-current-gang-leader-issue-and-direct-dialogue-route", passed = true });

        var fakeClient = new FakeRecruitmentNativeClient();
        var fakeProvider = new FakeRecruitmentDecisionProvider();
        using var request = JsonDocument.Parse("{\"runId\":\"establish-clan-recruitment-selftest\",\"goal\":\"Raise the active Journal PartySize target.\",\"maxDecisions\":8,\"maxElapsedSeconds\":10}");
        var runtime = await RunAsync(request.RootElement, fakeClient, fakeClient, fakeClient, fakeProvider, CancellationToken.None);
        if (ReadString(runtime, "status") != "completed" ||
            ReadString(runtime["termination"] as JsonObject, "reason") != "native-party-size-journal-target-met" ||
            ReadInt(runtime, "actionsExecuted", 0) != 2 || fakeProvider.CallCount != 2 ||
            fakeClient.RecruitedMembers != 5 || fakeClient.Gold != 80 ||
            !fakeClient.Actions.SequenceEqual(["recruitOptions", "recruit"], StringComparer.Ordinal))
            throw new AgentHostException("establish-clan-recruitment-runtime-self-test-failed", "The recruitment subloop must query current offers, commit one affordable volunteer through the Native adapter and stop only after the Journal target refreshes.");
        results.Add(new { scenario = "establish-clan-recruitment-runtime-observe-decide-native-commit-journal-verify", passed = true });

        var bulkFakeClient = new FakeRecruitmentNativeClient(useRecruitAll: true);
        var bulkFakeProvider = new FakeRecruitmentDecisionProvider(useRecruitAll: true);
        var bulkRuntime = await RunAsync(request.RootElement, bulkFakeClient, bulkFakeClient, bulkFakeClient, bulkFakeProvider, CancellationToken.None);
        if (ReadString(bulkRuntime, "status") != "completed" ||
            ReadString(bulkRuntime["termination"] as JsonObject, "reason") != "native-party-size-journal-target-met" ||
            ReadInt(bulkRuntime, "actionsExecuted", 0) != 2 || bulkFakeProvider.CallCount != 2 ||
            bulkFakeClient.RecruitedMembers != 6 || bulkFakeClient.Gold != 50 ||
            !bulkFakeClient.Actions.SequenceEqual(["recruitOptions", "recruitAll"], StringComparer.Ordinal))
            throw new AgentHostException("establish-clan-recruitment-native-take-all-runtime-self-test-failed", "The real PartySize Host route must expose a safe exact Take All offer, submit it through its RecruitmentVM transport and stop after the refreshed Journal target is met.");
        results.Add(new { scenario = "establish-clan-recruitment-runtime-uses-native-take-all-and-journal-verifies-batch", passed = true, providerCalls = bulkFakeProvider.CallCount, nativeActions = bulkFakeClient.Actions.Count });

        var capacityBlockedClient = new FakeRecruitmentNativeClient(startAtNativeCapacity: true);
        var capacityBlockedProvider = new FakeRecruitmentDecisionProvider();
        var capacityBlockedRun = await RunAsync(request.RootElement, capacityBlockedClient, capacityBlockedClient, capacityBlockedClient,
            capacityBlockedProvider, CancellationToken.None);
        if (ReadString(capacityBlockedRun, "status") != "interrupted" ||
            ReadString(capacityBlockedRun["termination"] as JsonObject, "reason") != "party-capacity-blocked-until-renown" ||
            ReadInt(capacityBlockedRun, "actionsExecuted", -1) != 0 || capacityBlockedProvider.CallCount != 0 || capacityBlockedClient.Actions.Count != 0)
            throw new AgentHostException("establish-clan-recruitment-overlimit-renown-gate-failed", "At Native party capacity with PartySize still unmet and Renown below its Journal target, PartySize must return to the parent without querying or issuing an over-limit volunteer/prisoner action.");
        results.Add(new { scenario = "establish-clan-recruitment-defers-overlimit-recruitment-until-renown-target", passed = true, providerCalls = capacityBlockedProvider.CallCount, nativeActions = capacityBlockedClient.Actions.Count });

        var stopClient = new FakeRecruitmentNativeClient();
        var stopProvider = new FakeRecruitmentStopProvider();
        var stopResult = await RunAsync(request.RootElement, stopClient, stopClient, stopClient, stopProvider, CancellationToken.None);
        if (ReadString(stopResult, "status") != "interrupted" ||
            ReadString(stopResult["termination"] as JsonObject, "reason") != "recruitment-model-stopped-with-safe-actions" ||
            ReadInt(stopResult, "actionsExecuted", 0) != 0 || stopProvider.CallCount != 2 || stopClient.Actions.Count != 0)
            throw new AgentHostException("establish-clan-recruitment-premature-stop-self-test-failed", "Repeated model stop decisions while safe Native actions remain listed must stop after bounded feedback without sending or substituting a Native recruitment action.");
        results.Add(new { scenario = "establish-clan-recruitment-bounds-premature-stop-while-safe-native-actions-remain", passed = true });

        var unavailableClient = new FakeRecruitmentNativeClient(startOnMap: false);
        var unavailableProvider = new FakeRecruitmentDecisionProvider();
        var unavailable = await RunAsync(request.RootElement, unavailableClient, unavailableClient, unavailableClient, unavailableProvider, CancellationToken.None);
        if (ReadString(unavailable, "status") != "failed" ||
            ReadString(unavailable["termination"] as JsonObject, "reason") != "campaign-map-unavailable" ||
            ReadString(unavailable, "failureCode") != "recruitment-map-unavailable" ||
            string.IsNullOrWhiteSpace(ReadString(unavailable, "failure")) ||
            ReadString(unavailable["nativeStateAfter"] as JsonObject, "gameState") != "MenuState" ||
            ReadString(unavailable["nativeStateAfter"] as JsonObject, "menuId") != "town" ||
            ReadInt(unavailable, "actionsExecuted", -1) != 0 || unavailableProvider.CallCount != 0)
            throw new AgentHostException("establish-clan-recruitment-failure-receipt-failed", "A Native map precondition failure must preserve its code and sanitized final Native gameState/menu, without calling the Provider or executing an action.");
        results.Add(new { scenario = "establish-clan-recruitment-failure-receipt-preserves-safe-native-state-summary", passed = true });

        var trainingFieldClient = new FakeRecruitmentNativeClient(startAtTrainingField: true);
        var trainingFieldProvider = new FakeObservedRecruitmentDecisionProvider();
        var trainingFieldRun = await RunAsync(request.RootElement, trainingFieldClient, trainingFieldClient, trainingFieldClient, trainingFieldProvider, CancellationToken.None);
        if (ReadString(trainingFieldRun, "status") != "completed" ||
            ReadString(trainingFieldRun["termination"] as JsonObject, "reason") != "native-party-size-journal-target-met" ||
            ReadInt(trainingFieldRun, "actionsExecuted", 0) != 3 || trainingFieldProvider.CallCount != 3 ||
            !trainingFieldClient.Actions.SequenceEqual(["menuSelect", "recruitOptions", "recruit"], StringComparer.Ordinal))
            throw new AgentHostException("establish-clan-recruitment-training-field-runtime-self-test-failed", "The Native PartySize subflow must leave the original training-field location menu before querying a Town RecruitmentVM and verifying a volunteer in the Journal.");
        results.Add(new { scenario = "establish-clan-recruitment-native-training-field-leave-to-volunteer-to-journal-verification", passed = true });

        var stopRecoveryClient = new FakeRecruitmentNativeClient(startAtTrainingField: true);
        var stopRecoveryProvider = new FakeObservedRecruitmentDecisionProvider(returnStopCount: 1);
        var stopRecoveryRun = await RunAsync(request.RootElement, stopRecoveryClient, stopRecoveryClient, stopRecoveryClient, stopRecoveryProvider, CancellationToken.None);
        var stopRecoveryTrace = stopRecoveryRun["trace"] as JsonArray ?? new JsonArray();
        if (ReadString(stopRecoveryRun, "status") != "completed" ||
            ReadInt(stopRecoveryRun, "actionsExecuted", 0) != 3 || stopRecoveryProvider.CallCount != 4 ||
            !stopRecoveryClient.Actions.SequenceEqual(["menuSelect", "recruitOptions", "recruit"], StringComparer.Ordinal) ||
            !stopRecoveryTrace.OfType<JsonObject>().Any(step => ReadString(step["decisionFeedback"] as JsonObject, "kind") == "safe-stop-rejected-with-listed-actions"))
            throw new AgentHostException("establish-clan-recruitment-safe-stop-recovery-self-test-failed", "A model stop while a safe Native action is listed must be rejected without a Native command, then the model may continue from the current catalog and complete the original recruitment route. status=" + ReadString(stopRecoveryRun, "status") + "; termination=" + ReadString(stopRecoveryRun["termination"] as JsonObject, "reason") + "; actions=" + string.Join(",", stopRecoveryClient.Actions) + "; calls=" + stopRecoveryProvider.CallCount + "; feedbackSteps=" + stopRecoveryTrace.OfType<JsonObject>().Count(step => ReadString(step["decisionFeedback"] as JsonObject, "kind") == "safe-stop-rejected-with-listed-actions"));
        results.Add(new { scenario = "establish-clan-recruitment-rejects-premature-stop-and-replans-from-current-native-catalog", passed = true });

        var backstreetRecoveryClient = new FakeRecruitmentNativeClient(startAtBackstreet: true);
        var backstreetRecoveryProvider = new FakeObservedRecruitmentDecisionProvider(returnStopCount: 2);
        var backstreetRecoveryRun = await RunAsync(request.RootElement, backstreetRecoveryClient, backstreetRecoveryClient, backstreetRecoveryClient, backstreetRecoveryProvider, CancellationToken.None);
        var backstreetRecoveryTrace = backstreetRecoveryRun["trace"] as JsonArray ?? new JsonArray();
        if (ReadString(backstreetRecoveryRun, "status") != "completed" ||
            ReadInt(backstreetRecoveryRun, "actionsExecuted", 0) != 3 || backstreetRecoveryProvider.CallCount != 4 ||
            !backstreetRecoveryClient.Actions.SequenceEqual(["menuSelect", "recruitOptions", "recruit"], StringComparer.Ordinal) ||
            !backstreetRecoveryTrace.OfType<JsonObject>().Any(step => ReadString(step["decisionFeedback"] as JsonObject, "kind") == "host-safe-backstreet-exit-after-model-stop"))
            throw new AgentHostException("establish-clan-recruitment-backstreet-stop-recovery-self-test-failed", "After two model stop decisions in Backstreet, Host may use only the sole currently enabled original Back option, verify return to the same Town and active EYC, then resume model decisions; no recruit or other action may be substituted.");
        results.Add(new { scenario = "establish-clan-recruitment-native-backstreet-exit-recovery-resumes-on-town-menu", passed = true });

        var villagersInNeedClient = new FakeVillagersInNeedRecruitmentClient();
        var villagersInNeedProvider = new FakeVillagersInNeedDecisionProvider(stopWhileMovingOnce: true, returnInvalidWaitOnce: true, rejectUnavailableControlOnce: true);
        using var villagersInNeedRequest = JsonDocument.Parse("{\"runId\":\"establish-clan-villagers-in-need-selftest\",\"goal\":\"Raise the active Journal PartySize target.\",\"maxDecisions\":16,\"maxElapsedSeconds\":30}");
        var villagersInNeedRun = await RunAsync(villagersInNeedRequest.RootElement, villagersInNeedClient, villagersInNeedClient, villagersInNeedClient,
            villagersInNeedProvider, CancellationToken.None);
        var automaticVillagerContinueCount = (villagersInNeedRun["trace"] as JsonArray)?.OfType<JsonObject>()
            .Count(step => ReadString(step["decisionFeedback"] as JsonObject, "kind") == "host-native-no-choice-dialogue-continue") ?? 0;
        if (ReadString(villagersInNeedRun, "status") != "completed" ||
            ReadString(villagersInNeedRun["termination"] as JsonObject, "reason") != "native-party-size-journal-target-met" ||
            ReadInt(villagersInNeedRun, "actionsExecuted", 0) != 11 || villagersInNeedClient.MapPartyTargetPollCount != 2 || villagersInNeedClient.StealthMissionStarted ||
            !villagersInNeedProvider.PrematureMoveStopRecovered ||
            !villagersInNeedProvider.InvalidWaitRejected ||
            !villagersInNeedProvider.ProviderControlUnavailableRecovered ||
            !((villagersInNeedRun["trace"] as JsonArray)?.OfType<JsonObject>().Any(step =>
                ReadString(step["decisionFeedback"] as JsonObject, "kind") == "decision-rejected-before-native" &&
                ReadString(step["decisionFeedback"] as JsonObject, "code") == "provider-control-unavailable") ?? false) ||
            villagersInNeedProvider.DialogueContinueDecisions != 0 ||
            automaticVillagerContinueCount != 2 ||
            !villagersInNeedClient.Actions.SequenceEqual(["mapSettlementTargets", "move", "dialogueSelect", "dialogueContinue", "dialogueSelect", "dialogueContinue", "dialogueSelect", "recruitOptions", "recruit"], StringComparer.Ordinal))
            throw new AgentHostException("establish-clan-villagers-in-need-party-size-recovery-failed", $"The bounded PartySize subgoal must reject a premature stop and a nine-second wait while movement exposes observeAgain, return a current MapState conversation to the model before movement resumes, then host-advance only no-choice VillagersInNeed Mission text, defer its mission at the visible answer, return to the Village menu and recruit through the current VM offer. status={ReadString(villagersInNeedRun, "status")}; termination={ReadString(villagersInNeedRun["termination"] as JsonObject, "reason")}; failureCode={ReadString(villagersInNeedRun, "failureCode")}; failure={ReadString(villagersInNeedRun, "failure")}; actions={ReadInt(villagersInNeedRun, "actionsExecuted", -1)}; automaticContinues={automaticVillagerContinueCount}; modelContinueChoices={villagersInNeedProvider.DialogueContinueDecisions}; providerRecoveredMoveStop={villagersInNeedProvider.PrematureMoveStopRecovered}; invalidWaitRejected={villagersInNeedProvider.InvalidWaitRejected}; mapTargetPolls={villagersInNeedClient.MapPartyTargetPollCount}; nativeActions={string.Join(',', villagersInNeedClient.Actions)}.");
        results.Add(new { scenario = "establish-clan-recruitment-resumes-after-native-villagers-in-need-deferral", passed = true });
        results.Add(new { scenario = "establish-clan-recruitment-rejects-stop-while-native-move-exposes-observe-again", passed = true });
        results.Add(new { scenario = "establish-clan-recruitment-rejects-observe-again-outside-exact-ten-second-contract", passed = true });

        using var prisonerRouteRequest = JsonDocument.Parse("{\"runId\":\"establish-clan-prisoner-recruitment-selftest\",\"goal\":\"Raise the original EYC PartySize objective.\",\"maxDecisions\":12,\"maxElapsedSeconds\":30}");
        var prisonerRouteClient = new FakePrisonerRecruitmentNativeClient();
        var prisonerRouteProvider = new FakePrisonerRecruitmentDecisionProvider();
        var prisonerRoute = await RunAsync(prisonerRouteRequest.RootElement, prisonerRouteClient, prisonerRouteClient, prisonerRouteClient,
            prisonerRouteProvider, CancellationToken.None);
        if (ReadString(prisonerRoute, "status") != "completed" ||
            ReadString(prisonerRoute["termination"] as JsonObject, "reason") != "native-party-size-journal-target-met" ||
            ReadInt(prisonerRoute, "actionsExecuted", 0) != 2 || prisonerRouteProvider.CallCount != 2 ||
            !prisonerRouteClient.Actions.SequenceEqual(["prisonerRecruitmentOptions", "recruitPrisoner"], StringComparer.Ordinal) ||
            prisonerRouteClient.PartyMembers != 11 || prisonerRouteClient.Prisoners != 14 ||
            prisonerRouteClient.PrisonerLimitConfirmations != 1 ||
            !((prisonerRoute["trace"] as JsonArray)?.OfType<JsonObject>().Any(step =>
                ReadString(step["decision"] as JsonObject, "action") == "recruitPrisoner" &&
                ReadBoolean(step["observation"]?["currentPrisonerRecruitmentOptions"] as JsonObject, "nativePrisonerLimitWarningAfterOneRecruit")) ?? false))
            throw new AgentHostException("establish-clan-prisoner-route-not-composed", $"The PartySize model must see current Native prisoner/limit offers, decide the separate warning, recruit one exact prisoner through the original adapter and verify the dynamic Journal target. status={ReadString(prisonerRoute, "status")}; termination={ReadString(prisonerRoute["termination"] as JsonObject, "reason")}; failureCode={ReadString(prisonerRoute, "failureCode")}; failure={ReadString(prisonerRoute, "failure")}; decisions={ReadInt(prisonerRoute, "decisions", -1)}; actions={ReadInt(prisonerRoute, "actionsExecuted", -1)}; providerCalls={prisonerRouteProvider.CallCount}; nativeActions={string.Join(",", prisonerRouteClient.Actions)}; members={prisonerRouteClient.PartyMembers}; prisoners={prisonerRouteClient.Prisoners}; confirmations={prisonerRouteClient.PrisonerLimitConfirmations}.");
        results.Add(new { scenario = "establish-clan-party-size-model-selects-current-prisoner-offer-and-explicit-limit-warning", decisions = prisonerRouteProvider.CallCount, nativeActions = prisonerRouteClient.Actions.ToArray(), partyAfter = prisonerRouteClient.PartyMembers, prisonersAfter = prisonerRouteClient.Prisoners, passed = true });
        return results;
    }

    private static JsonObject VillagersInNeedConversationState(JsonArray options, string characterId = VillagersInNeedHeroId) => new()
    {
        ["context"] = new JsonObject
        {
            ["gameState"] = "MissionState", ["menuId"] = null, ["encounterActive"] = true,
            ["encounteredPartyId"] = VillagersInNeedVillageId,
            ["conversation"] = new JsonObject { ["characterId"] = characterId, ["sentenceText"] = "Native villager line", ["options"] = options.DeepClone() },
            ["captivity"] = new JsonObject { ["isCaptive"] = false }
        },
        ["location"] = new JsonObject { ["currentSettlementId"] = VillagersInNeedVillageId },
        ["quests"] = new JsonArray(new JsonObject { ["id"] = QuestId }, new JsonObject { ["id"] = VillagersInNeedQuestId }),
        ["availableMenuOptions"] = new JsonArray(new JsonObject { ["id"] = RecruitmentMenuOptionId, ["available"] = true, ["enabled"] = true })
    };


    internal static async Task<JsonObject> RunAsync(
        JsonElement request,
        IAgentHostCampaignNativeClient campaignClient,
        IAgentHostRecruitmentNativeClient recruitmentClient,
        IAgentHostQuestDetailsNativeClient questDetailsClient,
        IAgentHostDecisionProvider provider,
        CancellationToken cancellationToken,
        int priorDecisions = 0,
        long priorPromptTokens = 0,
        long priorCompletionTokens = 0,
        JsonArray? priorTrace = null,
        JsonArray? priorProviderRouteHistory = null)
    {
        return await RunCoreAsync(request, campaignClient, recruitmentClient, questDetailsClient, provider, cancellationToken,
            priorDecisions, priorPromptTokens, priorCompletionTokens, priorTrace, priorProviderRouteHistory);
    }

    private static async Task<JsonObject> RunCoreAsync(
        JsonElement request,
        IAgentHostCampaignNativeClient campaignClient,
        IAgentHostRecruitmentNativeClient recruitmentClient,
        IAgentHostQuestDetailsNativeClient questDetailsClient,
        IAgentHostDecisionProvider provider,
        CancellationToken cancellationToken,
        int priorDecisions,
        long priorPromptTokens,
        long priorCompletionTokens,
        JsonArray? priorTrace,
        JsonArray? priorProviderRouteHistory)
    {
        var runId = ReadString(request, "runId") ?? Guid.NewGuid().ToString("N");
        var maxDecisions = Math.Clamp(ReadInt(request, "maxDecisions", MaxDecisions), 1, MaxDecisions);
        var maxSeconds = Math.Clamp(ReadInt(request, "maxElapsedSeconds", (int)MaxElapsed.TotalSeconds), 10, (int)MaxElapsed.TotalSeconds);
        var trace = priorTrace?.DeepClone() as JsonArray ?? new JsonArray();
        var routes = priorProviderRouteHistory?.DeepClone() as JsonArray ?? new JsonArray();
        var decisions = priorDecisions;
        var actionsExecuted = 0;
        long promptTokens = priorPromptTokens;
        long completionTokens = priorCompletionTokens;
        var visitedSettlements = new HashSet<string>(StringComparer.Ordinal);
        var lastMapTargets = (JsonArray?)null;
        var settlementTargetPageStartIndex = 0;
        var currentRecruitOffers = (JsonObject?)null;
        var currentPrisonerRecruitOptions = (JsonObject?)null;
        string? moveTargetId = null;
        var moveStartPending = false;
        JsonObject? previousReceipt = null;
        JsonObject? feedback = null;
        JsonObject? initialNativeState = null;
        JsonObject? lastNativeState = null;
        double? initialCampaignDay = null;
        double? lastCampaignDay = null;
        var rejectedDecisions = 0;
        var rejectedPrematureStops = 0;
        var villagersInNeedConversationStartupWaits = 0;
        var noOfferSettlementEventKeys = BuildNoAffordableVolunteerSettlementEventKeys(priorTrace);
        var contactedGangLeaderIssueGivers = new HashSet<string>(StringComparer.Ordinal);
        var priorNoProgressRest = trace.OfType<JsonObject>().LastOrDefault(step =>
            ReadString(step, "stage") == "eyc-native-wounded-party-rest-recovery" && !ReadBoolean(step, "healthImproved"));
        var lastNoProgressRestFingerprint = ReadString(priorNoProgressRest, "fingerprint");
        var start = Stopwatch.GetTimestamp();
        using var elapsed = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        elapsed.CancelAfter(TimeSpan.FromSeconds(maxSeconds));

        try
        {
            await provider.CheckConfiguredModelAsync(elapsed.Token);
            while (decisions < maxDecisions)
            {
                elapsed.Token.ThrowIfCancellationRequested();
                using var nativeState = await campaignClient.ReadStateAsync(elapsed.Token);
                var nativeStateRoot = JsonNode.Parse(nativeState.RootElement.GetRawText())?.AsObject()
                    ?? throw new AgentHostException("recruitment-state-unavailable", "Native did not provide a cloneable current Campaign state.");
                var state = ReadState(nativeState.RootElement)
                    ?? throw new AgentHostException("recruitment-state-unavailable", "Native did not provide the current Campaign state.");
                var campaignDay = ReadDouble(nativeState.RootElement, "campaignDay");
                if (double.IsFinite(campaignDay))
                {
                    initialCampaignDay ??= campaignDay;
                    lastCampaignDay = campaignDay;
                }
                var currentGold = ReadNumber(state["economy"] as JsonObject, "gold") ?? double.NaN;
                foreach (var cooldownSettlementId in BuildNoAffordableVolunteerSettlementCooldowns(trace, campaignDay, currentGold))
                    visitedSettlements.Add(cooldownSettlementId);
                initialNativeState ??= state.DeepClone() as JsonObject;
                lastNativeState = state;
                var context = state["context"] as JsonObject;
                var villagersInNeedConversation = IsVillagersInNeedConversation(state);
                if (ReadBoolean(context, "inquiryOpen"))
                    return BuildResult("failed", "native-inquiry-out-of-scope", "A Native Inquiry interrupted the recruitment path; no answer was invented.", "recruitment-inquiry-out-of-scope", state, currentRecruitOffers);
                if (ReadBoolean(context?["captivity"] as JsonObject, "isCaptive"))
                    return BuildResult("interrupted", "captivity-recovery-required", "The MainHero is captive; the EYC supervisor must run the Native captivity recovery subflow before recruiting.", "recruitment-captive", state, currentRecruitOffers);
                if (IsPendingVillagersInNeedConversationTransition(state))
                {
                    if (villagersInNeedConversationStartupWaits >= MaxVillagersInNeedConversationStartupWaits)
                        return BuildResult("failed", "villagers-in-need-conversation-startup-timeout", "The original StoryMode village ConversationMission remained active but its Native ConversationManager did not expose the known villager after bounded passive settling; no gameplay action or clock command was issued.", "villagers-in-need-conversation-startup-timeout", state, currentRecruitOffers);

                    var beforeDay = ReadDouble(nativeState.RootElement, "campaignDay");
                    var beforeMode = ReadString(nativeState.RootElement, "timeControlMode");
                    villagersInNeedConversationStartupWaits++;
                    await Task.Delay(TimeSpan.FromMilliseconds(500), elapsed.Token);
                    using var settledNativeState = await campaignClient.ReadStateAsync(elapsed.Token);
                    var settledState = ReadState(settledNativeState.RootElement)
                        ?? throw new AgentHostException("recruitment-state-unavailable", "Native did not provide the Campaign state after waiting for the StoryMode villager conversation to open.");
                    var settledDay = ReadDouble(settledNativeState.RootElement, "campaignDay");
                    trace.Add(new JsonObject
                    {
                        ["kind"] = "native-villagers-in-need-conversation-startup-settle",
                        ["attempt"] = villagersInNeedConversationStartupWaits,
                        ["before"] = AgentHostHarnessProgressTrace.BuildNativeStateSummary(new JsonObject { ["state"] = state.DeepClone(), ["campaignDay"] = double.IsFinite(campaignDay) ? JsonValue.Create(campaignDay) : null }),
                        ["after"] = AgentHostHarnessProgressTrace.BuildNativeStateSummary(new JsonObject { ["state"] = settledState.DeepClone(), ["campaignDay"] = double.IsFinite(settledDay) ? JsonValue.Create(settledDay) : null }),
                        ["beforeTimeControlMode"] = beforeMode,
                        ["afterTimeControlMode"] = ReadString(settledNativeState.RootElement, "timeControlMode")
                    });
                    lastNativeState = settledState;
                    if (double.IsFinite(settledDay)) lastCampaignDay = settledDay;
                    continue;
                }
                if (ReadString(context, "gameState") != "MapState" && !villagersInNeedConversation)
                    return BuildResult("failed", "campaign-map-unavailable", "Recruitment can only proceed from the original Campaign MapState or the source-verified StoryMode villager conversation.", "recruitment-map-unavailable", state, currentRecruitOffers);
                if (AgentHostCampaignStateFacts.IsActiveEncounter(state) && !villagersInNeedConversation)
                    return BuildResult("interrupted", "encounter-resolution-required", "A Native encounter interrupted travel; the EYC supervisor must resolve or leave that encounter before recruiting.", "recruitment-encounter", state, currentRecruitOffers);
                if (AgentHostNativeMapMovementMonitor.IsStalledNativeSettlementMove(nativeStateRoot))
                    return BuildResult("interrupted", "native-stalled-move-returned-by-recruitment", "The Native settlement move remains active while Campaign time is stopped; return it to the EYC parent for the existing bounded original-Move recovery.", "native-stalled-move-returned-by-recruitment", state, currentRecruitOffers);

                var journal = await ReadJournalAsync(questDetailsClient, elapsed.Token);
                var objective = AgentHostEstablishYourClanGoalLoop.BuildObjectiveSnapshot(journal);
                if (ReadBoolean(objective["partySize"] as JsonObject, "met"))
                    return BuildResult("completed", "native-party-size-journal-target-met", "The original Journal reports the dynamic PartySize objective as met.", null, state, currentRecruitOffers, journal, objective);
                if (IsPartySizeBlockedAtNativeCapacityUntilRenown(state, objective))
                {
                    trace.Add(new JsonObject
                    {
                        ["stage"] = "party-size-native-capacity-blocked-until-renown",
                        ["partyMembers"] = ReadNumber(state["party"] as JsonObject, "members"),
                        ["nativePartyCapacity"] = ReadNumber(state["party"] as JsonObject, "sizeLimit"),
                        ["journalPartySize"] = (objective["partySize"] as JsonObject)?.DeepClone(),
                        ["journalRenown"] = (objective["renown"] as JsonObject)?.DeepClone(),
                        ["overLimitRecruitmentExposed"] = false
                    });
                    return BuildResult("interrupted", "party-capacity-blocked-until-renown",
                        "MainParty is at its current Native capacity while the original Journal still requires more members and Renown is unmet. No over-limit recruit is issued; the parent planner must pursue Renown or another objective.",
                        "party-capacity-blocked-until-renown", state, currentRecruitOffers, journal, objective);
                }

                var livePartySize = ReadDouble(state["storyModeEstablishClan"]?["partySize"] as JsonObject, "current");
                var livePartyTarget = ReadDouble(state["storyModeEstablishClan"]?["partySize"] as JsonObject, "target");
                if (livePartySize >= livePartyTarget && !double.IsNaN(livePartyTarget))
                    return BuildResult("interrupted", "native-journal-refresh-pending", "Live MainParty size reaches the dynamic target, but the authoritative Journal is still behind; the loop will not over-recruit.", "recruitment-journal-refresh-pending", state, currentRecruitOffers, journal, objective);

                var moving = ReadBoolean(state["party"] as JsonObject, "isMoving");
                var currentSettlementId = ReadString(state["location"] as JsonObject, "currentSettlementId");
                var targetSettlementId = ReadString(state["location"] as JsonObject, "targetSettlementId");
                var currentMenuId = ReadString(context, "menuId");
                if (!string.IsNullOrWhiteSpace(moveTargetId) && string.Equals(currentSettlementId, moveTargetId, StringComparison.Ordinal))
                {
                    visitedSettlements.Add(moveTargetId);
                    moveStartPending = false;
                    if (!string.IsNullOrWhiteSpace(currentMenuId))
                    {
                        moveTargetId = null;
                        lastMapTargets = FilterRecruitmentTargets(lastMapTargets, currentSettlementId, visitedSettlements);
                        settlementTargetPageStartIndex = 0;
                    }
                }
                var nativeMoveActive = !string.IsNullOrWhiteSpace(moveTargetId) &&
                                       (moving || string.Equals(targetSettlementId, moveTargetId, StringComparison.Ordinal));
                if (nativeMoveActive) moveStartPending = false;
                var mapStateActive = ReadString(context, "gameState") == "MapState";
                var movementPending = mapStateActive && !string.IsNullOrWhiteSpace(moveTargetId) && !string.Equals(currentSettlementId, moveTargetId, StringComparison.Ordinal) &&
                                      (nativeMoveActive || moveStartPending);
                var settlementMenuPending = mapStateActive && !string.IsNullOrWhiteSpace(moveTargetId) && string.Equals(currentSettlementId, moveTargetId, StringComparison.Ordinal) && string.IsNullOrWhiteSpace(currentMenuId);
                movementPending |= settlementMenuPending;
                if (!movementPending && !settlementMenuPending && !string.IsNullOrWhiteSpace(moveTargetId) && !string.Equals(currentSettlementId, moveTargetId, StringComparison.Ordinal))
                {
                    moveTargetId = null;
                    lastMapTargets = null;
                    settlementTargetPageStartIndex = 0;
                    moveStartPending = false;
                }

                var townRestFingerprint = AgentHostEstablishYourClanAutonomyLoop.BuildNoHealthyTownRestRecoveryFingerprint(nativeState.RootElement);
                if (townRestFingerprint is not null && !string.Equals(townRestFingerprint, lastNoProgressRestFingerprint, StringComparison.Ordinal))
                {
                    lastNoProgressRestFingerprint = townRestFingerprint;
                    if (campaignClient is not IAgentHostSupplyNativeClient restClient)
                        return BuildResult("failed", "recruitment-native-rest-client-unavailable",
                            "The current Town offers Native bounded rest for the completely wounded MainParty, but the Native transport cannot run the existing rest adapter.",
                            "recruitment-native-rest-client-unavailable", state, currentRecruitOffers, journal, objective);

                    var restRecovery = await AgentHostSupplyLoop.RunBoundedEycRestRecoveryAsync(restClient, elapsed.Token);
                    restRecovery["runId"] = runId;
                    AgentHostHarnessProgressTrace.RecordObjectiveSubflowResult("nativeRestRecovery", restRecovery);
                    var restActionsExecuted = ReadInt(restRecovery, "actionsExecuted", 0);
                    actionsExecuted += restActionsExecuted;
                    var restHealthImproved = ReadBoolean(restRecovery, "healthImproved");
                    if (restRecovery["monitorStep"] is JsonObject restMonitorStep) trace.Add(restMonitorStep.DeepClone());
                    if (restRecovery["leaveStep"] is JsonObject restLeaveStep) trace.Add(restLeaveStep.DeepClone());
                    trace.Add(new JsonObject
                    {
                        ["stage"] = "eyc-native-wounded-party-rest-recovery",
                        ["fingerprint"] = townRestFingerprint,
                        ["status"] = ReadString(restRecovery, "status"),
                        ["healthImproved"] = restHealthImproved,
                        ["healthyBefore"] = restRecovery["healthyBefore"]?.DeepClone(),
                        ["healthyAfter"] = restRecovery["healthyAfter"]?.DeepClone(),
                        ["woundedBefore"] = restRecovery["woundedBefore"]?.DeepClone(),
                        ["woundedAfter"] = restRecovery["woundedAfter"]?.DeepClone(),
                        ["campaignDayBefore"] = restRecovery["campaignDayBefore"]?.DeepClone(),
                        ["campaignDayAfter"] = restRecovery["campaignDayAfter"]?.DeepClone(),
                        ["explicitClockAction"] = false
                    });
                    lastMapTargets = null;
                    settlementTargetPageStartIndex = 0;
                    moveTargetId = null;
                    moveStartPending = false;
                    currentRecruitOffers = null;
                    currentPrisonerRecruitOptions = null;
                    previousReceipt = new JsonObject
                    {
                        ["action"] = "rest",
                        ["status"] = ReadString(restRecovery, "status"),
                        ["healthImproved"] = restHealthImproved
                    };
                    feedback = null;
                    continue;
                }

                var visibleRecruitmentTargets = lastMapTargets is null
                    ? null
                    : GetRecruitmentSettlementTargetPage(lastMapTargets, settlementTargetPageStartIndex);
                var moreSafeRecruitmentTargetsAvailable = lastMapTargets is not null &&
                    settlementTargetPageStartIndex + (visibleRecruitmentTargets?.Count ?? 0) < lastMapTargets.Count;
                var catalog = BuildActionCatalog(state, objective, visibleRecruitmentTargets, currentRecruitOffers, moveTargetId,
                    movementPending, currentPrisonerRecruitOptions, moreSafeRecruitmentTargetsAvailable, contactedGangLeaderIssueGivers);
                var controls = BuildControlCatalog(state, movementPending, catalog.Count);
                var observation = BuildObservation(state, journal, objective, visibleRecruitmentTargets, currentRecruitOffers, previousReceipt,
                    feedback, currentPrisonerRecruitOptions, settlementTargetPageStartIndex, lastMapTargets?.Count ?? 0,
                    moreSafeRecruitmentTargetsAvailable);
                if (villagersInNeedConversation && catalog.Count == 1 &&
                    ReadString(catalog[0] as JsonObject, "action") == "dialogueContinue" &&
                    TryResolveRecruitmentAction(new JsonObject { ["action"] = "dialogueContinue", ["arguments"] = new JsonObject() },
                        state, visibleRecruitmentTargets, currentRecruitOffers, moveTargetId, movementPending,
                        out var automaticContinueAction, out var automaticContinueArguments, out _, out _, currentPrisonerRecruitOptions,
                        moreSafeRecruitmentTargetsAvailable) &&
                    automaticContinueAction == "dialogueContinue")
                {
                    var beforeConversation = context?["conversation"] as JsonObject;
                    var beforeText = ReadString(beforeConversation, "sentenceText");
                    var continueStartedAt = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                    using var continueResponse = await recruitmentClient.ExecuteRecruitmentActionAsync(automaticContinueAction, automaticContinueArguments, elapsed.Token);
                    var continueReceipt = JsonNode.Parse(continueResponse.RootElement.GetRawText())?.AsObject()
                        ?? throw new AgentHostException("villagers-in-need-dialogue-continue-receipt-invalid", "Native returned no receipt for the currently listed no-choice dialogueContinue.");
                    if (ReadString(continueReceipt, "status") != "completed")
                        return BuildResult("failed", "villagers-in-need-dialogue-continue-rejected", "Native did not confirm the original no-choice dialogueContinue handler; the PartySize objective was not advanced by substitution.", "villagers-in-need-dialogue-continue-rejected", state, currentRecruitOffers, journal, objective);

                    actionsExecuted++;
                    using var afterContinue = await campaignClient.ReadStateAsync(elapsed.Token);
                    var afterContinueState = ReadState(afterContinue.RootElement)
                        ?? throw new AgentHostException("recruitment-state-unavailable", "Native did not provide fresh Campaign state after the original StoryMode dialogueContinue handler.");
                    var afterContinueContext = afterContinueState["context"] as JsonObject;
                    var afterConversation = afterContinueContext?["conversation"] as JsonObject;
                    if (!AgentHostEstablishYourClanGoalLoop.HasActiveQuest(afterContinue.RootElement) ||
                        (ReadString(afterContinueContext, "gameState") != "MapState" &&
                         !IsVillagersInNeedConversation(afterContinueState) &&
                         !IsPendingVillagersInNeedConversationTransition(afterContinueState)))
                        return BuildResult("failed", "villagers-in-need-dialogue-continue-postcondition-unverified", "The original no-choice Continue handler completed, but fresh Native state did not preserve the EYC quest and either return to MapState or remain in the known VillagersInNeed conversation.", "villagers-in-need-dialogue-continue-postcondition-unverified", afterContinueState, currentRecruitOffers, journal, objective);
                    if (IsVillagersInNeedConversation(afterContinueState) &&
                        ReadString(afterConversation, "sentenceText") == beforeText &&
                        ((afterConversation?["options"] as JsonArray)?.Count ?? 0) == 0)
                        return BuildResult("failed", "villagers-in-need-dialogue-continue-no-progress", "The Native Continue handler completed, but the known no-choice StoryMode conversation exposed the same line again; automatic continuation stopped without repeating it.", "villagers-in-need-dialogue-continue-no-progress", afterContinueState, currentRecruitOffers, journal, objective);

                    var safeContinueReceipt = SafeReceipt(continueReceipt, automaticContinueAction, null);
                    trace.Add(BuildStep(decisions, observation, null, safeContinueReceipt,
                        new JsonObject
                        {
                            ["kind"] = "host-native-no-choice-dialogue-continue",
                            ["reason"] = "The verified StoryMode VillagersInNeed conversation exposed only the original Native dialogueContinue action; no player answer was selectable.",
                            ["nativeAction"] = "dialogueContinue",
                            ["modelGameplayActionsCommitted"] = 0
                        }, afterContinueState, continueStartedAt,
                        new JsonObject
                        {
                            ["campaignDayBefore"] = campaignDay,
                            ["campaignDayAfter"] = ReadDouble(afterContinue.RootElement, "campaignDay"),
                            ["nativeTimeControlMode"] = ReadString(afterContinue.RootElement, "timeControlMode")
                        }));
                    previousReceipt = safeContinueReceipt;
                    feedback = null;
                    currentRecruitOffers = null;
                    currentPrisonerRecruitOptions = null;
                    if (double.IsFinite(ReadDouble(afterContinue.RootElement, "campaignDay")))
                        lastCampaignDay = ReadDouble(afterContinue.RootElement, "campaignDay");
                    lastNativeState = afterContinueState;
                    continue;
                }
                if (catalog.Count == 0 && controls.Count == 0)
                    return BuildResult("interrupted", "recruitment-route-unavailable", DescribeNoAction(state, currentRecruitOffers), "recruitment-route-unavailable", state, currentRecruitOffers, journal, objective);

                var modelRequest = new JsonObject
                {
                    ["runId"] = runId,
                    ["goal"] = ReadString(request, "goal"),
                    ["goalKind"] = "active-storymode-establish-clan-party-size",
                    ["observation"] = observation,
                    ["previousActionReceipt"] = previousReceipt?.DeepClone(),
                    ["decisionFeedback"] = feedback?.DeepClone(),
                    ["allowedActions"] = catalog.DeepClone(),
                    ["allowedControls"] = controls.DeepClone(),
                    ["controlArguments"] = controls.Any(control => control?.GetValue<string>() == "observeAgain")
                        ? new JsonObject { ["observeAgain"] = new JsonObject { ["waitSeconds"] = new JsonObject { ["type"] = "integer", ["minimum"] = 10, ["maximum"] = 10 } } }
                        : new JsonObject(),
                    ["iteration"] = decisions + 1
                };
                var providerStarted = Stopwatch.GetTimestamp();
                var decision = await AgentHostProviderDecisionRecovery.DecideWithSingleRetryAsync(
                    modelRequest,
                    token => AgentHostDecisionCycle.DecideEstablishClanRecruitmentAsync(provider, modelRequest, token),
                    errorCode =>
                    {
                        decisions++;
                        var recoveryFeedback = AgentHostProviderDecisionRecovery.BuildFeedback(errorCode, catalog, controls);
                        trace.Add(BuildStep(decisions, observation, null, null, recoveryFeedback, state,
                            DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture)));
                    },
                    elapsed.Token);
                decisions++;
                promptTokens += decision.PromptTokens ?? 0;
                completionTokens += decision.CompletionTokens ?? 0;
                routes.Add(new JsonObject
                {
                    ["decision"] = decisions,
                    ["requestedModelId"] = provider.ModelId,
                    ["responseModelId"] = decision.ModelId,
                    ["routedVia"] = decision.RoutedVia,
                    ["promptTokens"] = decision.PromptTokens,
                    ["completionTokens"] = decision.CompletionTokens
                });

                if (ReadBoolean(decision.Decision, "stop") && (catalog.Count > 0 || controls.Count > 0))
                {
                    if (rejectedPrematureStops >= 1)
                    {
                        if (TryResolveBackstreetLeave(state, catalog, lastMapTargets, currentRecruitOffers, moveTargetId, movementPending, out var leaveArguments))
                        {
                            var leaveStartedAt = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                            using var leaveResponse = await recruitmentClient.ExecuteRecruitmentActionAsync("menuSelect", leaveArguments, elapsed.Token);
                            var leaveReceipt = JsonNode.Parse(leaveResponse.RootElement.GetRawText())?.AsObject()
                                ?? throw new AgentHostException("recruitment-backstreet-leave-receipt-invalid", "Native returned no receipt for the exact enabled Backstreet Leave option.");
                            if (ReadString(leaveReceipt, "status") != "completed")
                                return BuildResult("failed", "recruitment-backstreet-leave-rejected", "The exact enabled Native Backstreet Leave option was submitted after repeated model stop, but Native did not confirm it.", "recruitment-backstreet-leave-rejected", state, currentRecruitOffers, journal, objective);

                            actionsExecuted++;
                            using var afterLeave = await campaignClient.ReadStateAsync(elapsed.Token);
                            var afterLeaveState = ReadState(afterLeave.RootElement);
                            var afterContext = afterLeaveState?["context"] as JsonObject;
                            var beforeSettlement = ReadString(state["location"] as JsonObject, "currentSettlementId");
                            var afterSettlement = ReadString(afterLeaveState?["location"] as JsonObject, "currentSettlementId");
                            if (ReadString(afterContext, "gameState") != "MapState" ||
                                ReadString(afterContext, "menuId") != "town" ||
                                string.IsNullOrWhiteSpace(beforeSettlement) || beforeSettlement != afterSettlement ||
                                ReadBoolean(afterContext, "inquiryOpen") || AgentHostCampaignStateFacts.IsActiveEncounter(afterLeaveState ?? state) ||
                                !AgentHostEstablishYourClanGoalLoop.HasActiveQuest(afterLeave.RootElement))
                                return BuildResult("failed", "recruitment-backstreet-leave-postcondition-unverified", "The Native Backstreet Leave receipt completed, but the fresh state did not verify return to the same Town menu with the original EYC still active and no modal or encounter.", "recruitment-backstreet-leave-postcondition-unverified", afterLeaveState ?? state, currentRecruitOffers, journal, objective);

                            trace.Add(BuildStep(decisions, observation, decision.Decision,
                                SafeReceipt(leaveReceipt, "menuSelect", null),
                                new JsonObject { ["kind"] = "host-safe-backstreet-exit-after-model-stop", ["nativeAction"] = "menuSelect", ["menuId"] = "town_backstreet", ["optionId"] = "town_backstreet_back", ["hostRecoveryKind"] = "single-enabled-location-leave", ["modelGameplayActionsCommitted"] = 0 },
                                afterLeaveState, leaveStartedAt,
                                new JsonObject { ["campaignDayBefore"] = ReadDouble(state, "campaignDay"), ["campaignDayAfter"] = ReadDouble(afterLeave.RootElement, "campaignDay"), ["nativeTimeControlMode"] = ReadString(afterLeave.RootElement, "timeControlMode") }));
                            previousReceipt = SafeReceipt(leaveReceipt, "menuSelect", null);
                            feedback = null;
                            rejectedPrematureStops = 0;
                            currentRecruitOffers = null;
                            continue;
                        }
                        return BuildResult("interrupted", "recruitment-model-stopped-with-safe-actions", "The model repeated stop after one recovery request while the current Native state still exposed safe actions; no gameplay action was substituted.", "recruitment-model-stopped-with-safe-actions", state, currentRecruitOffers, journal, objective);
                    }
                    rejectedPrematureStops++;
                    var availableActions = catalog.OfType<JsonObject>()
                        .Select(item => ReadString(item, "action"))
                        .Where(name => !string.IsNullOrWhiteSpace(name))
                        .Select(name => name!)
                        .Distinct(StringComparer.Ordinal)
                        .ToArray();
                    var observeAgainOnly = catalog.Count == 0 && controls.Any(control => control?.GetValue<string>() == "observeAgain");
                    feedback = new JsonObject
                    {
                        ["kind"] = observeAgainOnly ? "safe-stop-rejected-with-observe-again-control" : "safe-stop-rejected-with-listed-actions",
                        ["requiredNextStep"] = observeAgainOnly
                            ? "The currently issued Native map move is still active. Choose observeAgain with waitSeconds 10 exactly; the Native movement monitor polls each second and returns early on a hostile interruption or arrival; do not change the game clock."
                            : BuildSafeStopRecoveryInstruction(catalog, availableActions)
                    };
                    trace.Add(BuildStep(decisions, observation, decision.Decision, null, feedback.DeepClone() as JsonObject, state, null));
                    continue;
                }
                if (ReadBoolean(decision.Decision, "stop"))
                    return BuildResult("interrupted", "recruitment-model-stopped", ReadString(decision.Decision, "reason") ?? "The model safely stopped the PartySize subgoal before another Native action.", "recruitment-model-stopped", state, currentRecruitOffers, journal, objective);

                if (AgentHostDecisionCycle.IsObserveAgainDecision(decision.Decision))
                {
                    var waitSeconds = ReadInt(decision.Decision, "waitSeconds", 0);
                    if (!movementPending || waitSeconds != 10)
                        feedback = RejectedFeedback("control", "observeAgain is available only during the current Native move and requires waitSeconds=10 exactly; the Host monitors Native state every second.");
                    else
                    {
                        var waitStarted = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                        var waitNative = JsonNode.Parse(nativeState.RootElement.GetRawText())?.AsObject()
                            ?? throw new AgentHostException("recruitment-movement-state-invalid", "The current Native state could not be cloned for the movement monitor.");
                        var movementWatch = await AgentHostNativeMapMovementMonitor.WaitAsync(
                            campaignClient,
                            campaignClient as IAgentHostBattleSimulationNativeClient,
                            waitNative,
                            moveTargetId,
                            waitSeconds,
                            monitorVisibleBandits: AgentHostEstablishYourClanGoalLoop.HasActiveQuest(nativeState.RootElement),
                            elapsed.Token);
                        var waitedState = movementWatch.NativeState;
                        actionsExecuted += movementWatch.MapPartyTargetPollCount + (movementWatch.PauseReceipt is null ? 0 : 1);
                        moveStartPending = false;
                        var movementStep = BuildStep(decisions, observation, decision.Decision, null,
                            new JsonObject
                            {
                                ["kind"] = movementWatch.InterruptedByVisibleHostileBandit ? AgentHostNativeMapMovementMonitor.FailureCode : "bounded-observe-again",
                                ["waitSeconds"] = waitSeconds,
                                ["nativeMapPartyTargetPollCount"] = movementWatch.MapPartyTargetPollCount,
                                ["visibleHostileBanditTargets"] = movementWatch.VisibleHostileBanditTargets.DeepClone(),
                                ["nativePauseReceipt"] = movementWatch.PauseReceipt?.DeepClone()
                            }, waitedState, waitStarted);
                        trace.Add(movementStep);
                        previousReceipt = new JsonObject { ["control"] = "observeAgain", ["waitSeconds"] = waitSeconds, ["status"] = "completed" };
                        feedback = null;
                        currentRecruitOffers = null;
                        currentPrisonerRecruitOptions = null;
                        if (movementWatch.InterruptedByVisibleHostileBandit)
                            return BuildResult("interrupted", AgentHostNativeMapMovementMonitor.FailureCode,
                                "A Native visible hostile Bandit interrupted the PartySize settlement move. The EYC parent should resolve it through the existing BattleSimulation route before replanning.",
                                AgentHostNativeMapMovementMonitor.FailureCode, waitedState, currentRecruitOffers, journal, objective);
                    }
                    continue;
                }

                if (!TryResolveRecruitmentAction(decision.Decision, state, visibleRecruitmentTargets, currentRecruitOffers, moveTargetId, movementPending,
                        out var action, out var arguments, out var selectedSettlementId, out var rejection, currentPrisonerRecruitOptions,
                        moreSafeRecruitmentTargetsAvailable, objective, contactedGangLeaderIssueGivers))
                {
                    rejectedDecisions++;
                    feedback = RejectedFeedback("decision-rejected-before-native", rejection);
                    trace.Add(BuildStep(decisions, observation, decision.Decision, null, feedback.DeepClone() as JsonObject, state, null));
                    if (rejectedDecisions > MaxRejectedDecisions)
                        return BuildResult("failed", "model-rejection-limit", "The Native recruitment action boundary rejected repeated stale/unsupported decisions.", "recruitment-rejection-limit", state, currentRecruitOffers, journal, objective);
                    continue;
                }
                rejectedPrematureStops = 0;

                if (action == "mapSettlementTargetsMore")
                {
                    var currentPage = GetRecruitmentSettlementTargetPage(lastMapTargets, settlementTargetPageStartIndex);
                    var nextPageStart = settlementTargetPageStartIndex + currentPage.Count;
                    if (lastMapTargets is null || currentPage.Count == 0 || nextPageStart >= lastMapTargets.Count)
                        return BuildResult("failed", "recruitment-target-page-stale", "The Host-only next-page action no longer matches the current cached Native settlement target list.", "recruitment-target-page-stale", state, currentRecruitOffers, journal, objective);
                    trace.Add(new JsonObject
                    {
                        ["kind"] = "host-safe-settlement-target-page-advanced",
                        ["fromIndex"] = settlementTargetPageStartIndex,
                        ["toIndex"] = nextPageStart,
                        ["totalSafeTargetCount"] = lastMapTargets.Count,
                        ["nativeActionCommitted"] = false
                    });
                    settlementTargetPageStartIndex = nextPageStart;
                    previousReceipt = new JsonObject
                    {
                        ["action"] = "mapSettlementTargetsMore", ["status"] = "completed", ["nativeActionCommitted"] = false,
                        ["pageStartIndex"] = settlementTargetPageStartIndex, ["totalSafeTargetCount"] = lastMapTargets.Count
                    };
                    feedback = null;
                    continue;
                }

                var actionStarted = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                JsonDocument response;
                if (action is "mapSettlementTargets" or "move")
                    response = await campaignClient.ExecuteCampaignActionAsync(action, arguments, elapsed.Token);
                else
                    response = await recruitmentClient.ExecuteRecruitmentActionAsync(action, arguments, elapsed.Token);
                using (response)
                {
                    var receipt = JsonNode.Parse(response.RootElement.GetRawText())?.AsObject()
                        ?? throw new AgentHostException("recruitment-native-response-invalid", "Native returned no recruitment action receipt.");
                    var completed = ReadString(receipt, "status") == "completed";
                    if (completed) actionsExecuted++;
                    if (action == "mapSettlementTargets")
                    {
                        lastMapTargets = FilterRecruitmentTargets(receipt["data"]?["mapSettlementTargets"] as JsonArray, currentSettlementId, visitedSettlements);
                        settlementTargetPageStartIndex = 0;
                        currentRecruitOffers = null;
                    }
                    else if (action == "move" && completed)
                    {
                        moveTargetId = selectedSettlementId;
                        moveStartPending = true;
                        lastMapTargets = null;
                        settlementTargetPageStartIndex = 0;
                        currentRecruitOffers = null;
                        currentPrisonerRecruitOptions = null;
                    }
                    else if (action == "recruitOptions")
                    {
                        currentRecruitOffers = receipt.DeepClone() as JsonObject;
                        var noOfferStep = BuildNoAffordableVolunteerOfferTraceStep(receipt, objective, state, campaignDay);
                        if (noOfferStep is not null)
                        {
                            var settlementId = ReadString(noOfferStep, "settlementId")!;
                            var offerEventKey = BuildNoOfferSettlementEventKey(settlementId, campaignDay, currentGold);
                            visitedSettlements.Add(settlementId);
                            if (noOfferSettlementEventKeys.Add(offerEventKey))
                                trace.Add(noOfferStep);
                        }
                    }
                    else if (action == "prisonerRecruitmentOptions")
                        currentPrisonerRecruitOptions = receipt.DeepClone() as JsonObject;
                    else if (action is "recruit" or "recruitAll")
                    {
                        var recruitmentData = receipt["data"] as JsonObject;
                        var expectedBatchMatches = action != "recruitAll" ||
                            recruitmentData is not null &&
                            ReadInt(recruitmentData, "recruitedCount", -1) == ReadInt(arguments, "expectedCount", -2) &&
                            ReadInt(recruitmentData, "totalCost", -1) == ReadInt(arguments, "expectedTotalCost", -2) &&
                            ReadString(recruitmentData, "offerSetSha256") == ReadString(arguments, "expectedOfferSetSha256");
                        if (recruitmentData is not null && ReadBoolean(recruitmentData, "verified") && expectedBatchMatches)
                        {
                            currentRecruitOffers = null;
                            currentPrisonerRecruitOptions = null;
                        }
                        else
                            throw new AgentHostException("recruitment-native-outcome-unverified", "The Native recruitment transaction returned without the required member-count, Gold and exact batch-offer receipt.");
                    }
                    else if (action == "recruitPrisoner")
                    {
                        if (receipt["data"] is JsonObject prisonerData && ReadBoolean(prisonerData, "committed") && ReadInt(prisonerData, "recruitedCount", 0) == 1)
                        {
                            currentRecruitOffers = null;
                            currentPrisonerRecruitOptions = null;
                        }
                        else if (completed)
                            throw new AgentHostException("recruitment-native-prisoner-outcome-unverified", "The Native prisoner recruitment receipt did not prove exactly one current prisoner was recruited.");
                    }
                    else if (action == "menuSelect")
                    {
                        currentRecruitOffers = null;
                        currentPrisonerRecruitOptions = null;
                        var settlement = ReadString(state?["location"] as JsonObject, "currentSettlementId");
                        if (settlement != null)
                        {
                            visitedSettlements.Add(settlement);
                            lastMapTargets = FilterRecruitmentTargets(lastMapTargets, null, visitedSettlements);
                            settlementTargetPageStartIndex = 0;
                        }
                    }
                    else if (action == "talkToSettlementHero" && completed)
                    {
                        var heroId = ReadString(arguments, "heroId");
                        if (!string.IsNullOrWhiteSpace(heroId)) contactedGangLeaderIssueGivers.Add(heroId);
                        currentRecruitOffers = null;
                        currentPrisonerRecruitOptions = null;
                    }

                    using var after = await campaignClient.ReadStateAsync(elapsed.Token);
                    var afterState = ReadState(after.RootElement);
                    var afterDay = ReadDouble(after.RootElement, "campaignDay");
                    var beforeDay = ReadDouble(state, "campaignDay");
                    trace.Add(BuildStep(decisions, observation, decision.Decision, receipt, null, afterState, actionStarted,
                        new JsonObject { ["campaignDayBefore"] = beforeDay, ["campaignDayAfter"] = afterDay,
                            ["nativeTimeControlMode"] = ReadString(after.RootElement, "timeControlMode") }));
                    previousReceipt = SafeReceipt(receipt, action, selectedSettlementId);
                    feedback = completed ? null : new JsonObject { ["kind"] = "native-action-rejected", ["message"] = "Native rejected the recruitment step; re-read current state and do not repeat a stale offer." };
                    rejectedDecisions = completed ? 0 : rejectedDecisions + 1;
                    if (rejectedDecisions > MaxRejectedDecisions)
                        return BuildResult("failed", "native-rejection-limit", "Repeated Native recruitment rejection stopped this bounded subgoal.", "recruitment-native-rejection-limit", afterState, currentRecruitOffers, journal, objective);
                }
            }

            using var finalState = await campaignClient.ReadStateAsync(elapsed.Token);
            var current = ReadState(finalState.RootElement);
            var finalJournal = await ReadJournalAsync(questDetailsClient, elapsed.Token);
            var finalObjective = AgentHostEstablishYourClanGoalLoop.BuildObjectiveSnapshot(finalJournal);
            return BuildResult("failed", "decision-budget-exhausted", "The recruitment subgoal reached its bounded decision limit without Journal-confirmed PartySize completion.", "recruitment-decision-budget-exhausted", current, currentRecruitOffers, finalJournal, finalObjective);
        }
        catch (OperationCanceledException)
        {
            return BuildResult("failed", "host-stop-or-time-budget", cancellationToken.IsCancellationRequested ? "Host stop signal ended recruitment without claiming PartySize completion." : "The bounded recruitment subgoal exceeded its elapsed-time limit.",
                cancellationToken.IsCancellationRequested ? "host-stop-requested" : "recruitment-timeout", null, currentRecruitOffers);
        }
        catch (AgentHostException exception)
        {
            return BuildResult("failed", "recruitment-loop-failed", exception.Message, exception.Code, null, currentRecruitOffers);
        }

        JsonObject BuildResult(string status, string termination, string? failure, string? failureCode, JsonObject? finalState,
            JsonObject? offers, JsonArray? journal = null, JsonObject? objective = null)
        {
            var live = finalState?["storyModeEstablishClan"] as JsonObject;
            return new JsonObject
            {
                ["status"] = status,
                ["resultKind"] = "establish-clan-party-size-recruitment-subgoal",
                ["runId"] = runId,
                ["providerModelId"] = provider.ModelId,
                ["providerConfigurationSource"] = provider.ConfigurationSource,
                ["decisions"] = decisions,
                ["actionsExecuted"] = actionsExecuted,
                ["promptTokens"] = promptTokens,
                ["completionTokens"] = completionTokens,
                ["elapsedSeconds"] = Math.Round(Stopwatch.GetElapsedTime(start).TotalSeconds, 3),
                ["providerRouteHistory"] = routes.DeepClone(),
                ["trace"] = trace.DeepClone(),
                ["lastRecruitmentOffers"] = offers?.DeepClone(),
                ["livePartySize"] = live?["partySize"]?.DeepClone(),
                ["nativeStateBefore"] = SummarizeNativeState(initialNativeState, initialCampaignDay),
                ["nativeStateAfter"] = SummarizeNativeState(finalState ?? lastNativeState, lastCampaignDay),
                ["journalObjectiveSnapshot"] = journal?.DeepClone(),
                ["objectiveSnapshot"] = objective?.DeepClone(),
                ["failure"] = failure,
                ["failureCode"] = failureCode,
                ["termination"] = new JsonObject { ["reason"] = termination, ["goalVerified"] = ReadBoolean(objective?["partySize"] as JsonObject, "met") }
            };
        }

        static JsonObject? SummarizeNativeState(JsonObject? state, double? campaignDay)
        {
            if (state is null) return null;
            var native = new JsonObject { ["state"] = state.DeepClone() };
            if (campaignDay is double day && double.IsFinite(day)) native["campaignDay"] = day;
            return AgentHostHarnessProgressTrace.BuildNativeStateSummary(native);
        }
    }

    private static JsonArray BuildActionCatalog(JsonObject? state, JsonObject objective, JsonArray? safeTargets,
        JsonObject? recruitOptions, string? moveTargetId, bool moving, JsonObject? prisonerRecruitmentOptions = null,
        bool moreSafeTargetsAvailable = false, IReadOnlySet<string>? contactedGangLeaderIssueGivers = null)
    {
        var catalog = new JsonArray();
        var context = state?["context"] as JsonObject;
        var villagersInNeedConversation = IsVillagersInNeedConversation(state);
        if (ReadBoolean(context, "escapeMenuOpen") || ReadBoolean(context, "inquiryOpen") ||
            ReadBoolean(context?["captivity"] as JsonObject, "isCaptive")) return catalog;
        if (state is not null && AgentHostCampaignStateFacts.IsActiveEncounter(state) && !villagersInNeedConversation) return catalog;

        if (villagersInNeedConversation)
            return BuildVillagersInNeedConversationCatalog(state);

        if (IsMapStateConversation(state))
            return BuildMapConversationActionCatalog(state, contactedGangLeaderIssueGivers);

        if (moving) return catalog;

        if (ReadString(context, "gameState") != "MapState") return catalog;

        var menuId = ReadString(context, "menuId");
        var menuOptions = state?["availableMenuOptions"] as JsonArray ?? new JsonArray();
        var partySizeMet = ReadBoolean(objective["partySize"] as JsonObject, "met") == true;
        var prisonerCount = ReadInt(state?["party"] as JsonObject, "prisoners", 0);
        if (!partySizeMet && prisonerCount > 0 && menuId is null or "town" or "village")
        {
            if (prisonerRecruitmentOptions is null)
                catalog.Add(new JsonObject { ["action"] = "prisonerRecruitmentOptions", ["arguments"] = new JsonArray() });
            else
            {
                var prisonerActions = BuildPrisonerRecruitmentActionCatalog(prisonerRecruitmentOptions, objective);
                foreach (var prisonerAction in prisonerActions) catalog.Add(prisonerAction?.DeepClone());
            }
        }

        if (recruitOptions is not null)
        {
            var offers = BuildRecruitmentActionCatalog(recruitOptions, objective);
            if (offers.Count > 0)
            {
                foreach (var offerAction in offers) catalog.Add(offerAction?.DeepClone());
                AddGangLeaderIssueTalkAction(catalog, state, contactedGangLeaderIssueGivers);
                return catalog;
            }
            if (state is not null && AgentHostCampaignStateFacts.IsNativeLocationMenu(state))
            {
                AddGangLeaderIssueTalkAction(catalog, state, contactedGangLeaderIssueGivers);
                var leaveActions = BuildLocationLeaveActionCatalog(state, menuId);
                foreach (var leaveAction in leaveActions) catalog.Add(leaveAction?.DeepClone());
                return catalog;
            }
        }

        if (!IsRecruitmentMenu(menuId) && state is not null && AgentHostCampaignStateFacts.IsNativeLocationMenu(state))
        {
            AddGangLeaderIssueTalkAction(catalog, state, contactedGangLeaderIssueGivers);
            var leaveActions = BuildLocationLeaveActionCatalog(state, menuId);
            foreach (var leaveAction in leaveActions) catalog.Add(leaveAction?.DeepClone());
            return catalog;
        }
        if (IsRecruitmentMenu(menuId) && HasEnabledOption(menuOptions, RecruitmentMenuOptionId) && recruitOptions is null)
        {
            catalog.Add(new JsonObject { ["action"] = "recruitOptions", ["arguments"] = new JsonArray() });
            AddGangLeaderIssueTalkAction(catalog, state, contactedGangLeaderIssueGivers);
            return catalog;
        }

        if (IsRecruitmentMenu(menuId))
        {
            var leave = menuOptions.OfType<JsonObject>().Where(option => ReadBoolean(option, "available") && ReadBoolean(option, "enabled") && ReadBoolean(option, "isLeave"))
                .Select(option => ReadString(option, "id")).Where(id => !string.IsNullOrWhiteSpace(id)).Cast<string>().ToArray();
            if (leave.Length > 0)
            {
                var action = new JsonObject { ["action"] = "menuSelect", ["arguments"] = new JsonArray("OptionId") };
                action["argumentValues"] = new JsonObject { ["OptionId"] = new JsonArray(leave.Select(id => (JsonNode?)JsonValue.Create(id)).ToArray()) };
                action["arguments"] = new JsonArray("MenuId", "OptionId");
                var argumentValues = action["argumentValues"] as JsonObject ?? new JsonObject();
                argumentValues["MenuId"] = new JsonArray(JsonValue.Create(menuId));
                action["argumentValues"] = argumentValues;
                catalog.Add(action);
                AddGangLeaderIssueTalkAction(catalog, state, contactedGangLeaderIssueGivers);
                return catalog;
            }
        }

        if (safeTargets is null)
        {
            catalog.Add(new JsonObject { ["action"] = "mapSettlementTargets", ["arguments"] = new JsonArray() });
            return catalog;
        }
        if (safeTargets.Count > 0)
        {
            var action = new JsonObject { ["action"] = "move", ["arguments"] = new JsonArray("SettlementId") };
            action["argumentValues"] = new JsonObject { ["SettlementId"] = new JsonArray(safeTargets.OfType<JsonObject>()
                .Select(target => (JsonNode?)JsonValue.Create(ReadString(target, "id"))).ToArray()) };
            catalog.Add(action);
        }
        if (moreSafeTargetsAvailable)
            catalog.Add(new JsonObject { ["action"] = "mapSettlementTargetsMore", ["arguments"] = new JsonArray() });
        return catalog;
    }

    internal static bool IsVillagersInNeedConversation(JsonObject? state)
    {
        var context = state?["context"] as JsonObject;
        var location = state?["location"] as JsonObject;
        var conversation = context?["conversation"] as JsonObject;
        return ReadString(context, "gameState") == "MissionState" &&
               ReadString(location, "currentSettlementId") == VillagersInNeedVillageId &&
               ReadString(conversation, "characterId") == VillagersInNeedHeroId &&
               state?["quests"] is JsonArray quests &&
               quests.OfType<JsonObject>().Any(quest => ReadString(quest, "id") == VillagersInNeedQuestId);
    }

    internal static bool IsPendingVillagersInNeedConversationTransition(JsonObject? state)
    {
        var context = state?["context"] as JsonObject;
        var location = state?["location"] as JsonObject;
        var conversation = context?["conversation"] as JsonObject;
        return ReadString(context, "gameState") == "MissionState" &&
               ReadString(location, "currentSettlementId") == VillagersInNeedVillageId &&
               ReadBoolean(context, "encounterActive") &&
               string.IsNullOrWhiteSpace(ReadString(conversation, "characterId")) &&
               state?["quests"] is JsonArray quests &&
               quests.OfType<JsonObject>().Any(quest => ReadString(quest, "id") == VillagersInNeedQuestId);
    }

    internal static JsonArray BuildVillagersInNeedConversationCatalog(JsonObject? state)
    {
        var options = ((state?["context"] as JsonObject)?["conversation"] as JsonObject)?["options"] as JsonArray;
        if (options is null || options.Count == 0)
            return [new JsonObject { ["action"] = "dialogueContinue", ["arguments"] = new JsonArray() }];

        var optionIds = options.OfType<JsonObject>()
            .Where(option => ReadBoolean(option, "clickable"))
            .Where(option => !string.Equals(ReadString(option, "textId"), VillagersInNeedVillaMissionStartTextId, StringComparison.Ordinal))
            .Select(option => ReadString(option, "id"))
            .Where(id => !string.IsNullOrWhiteSpace(id))
            .Distinct(StringComparer.Ordinal)
            .Cast<string>()
            .ToArray();
        if (optionIds.Length == 0) return [];
        return
        [
            new JsonObject
            {
                ["action"] = "dialogueSelect",
                ["arguments"] = new JsonArray("OptionId"),
                ["argumentValues"] = new JsonObject { ["OptionId"] = new JsonArray(optionIds.Select(id => (JsonNode?)JsonValue.Create(id)).ToArray()) }
            }
        ];
    }

    internal static bool IsGangLeaderRecruitsIssueTitle(string? title) =>
        !string.IsNullOrWhiteSpace(title) &&
        (title.Contains(GangLeaderRecruitsIssueTitleZh, StringComparison.Ordinal) ||
         title.Contains("Gang Leader Needs Recruits", StringComparison.OrdinalIgnoreCase));

    internal static string[] GetVisibleGangLeaderRecruitsIssueGivers(JsonObject? state, IReadOnlySet<string>? contactedAvailableGivers = null) =>
        (state?["settlementOverlayCharacters"] as JsonArray)?.OfType<JsonObject>()
            .Where(hero => ReadBoolean(hero, "isNotable") &&
                (hero["questMarkers"] as JsonArray)?.OfType<JsonObject>().Any(marker =>
                    (ReadString(marker, "type") is "AvailableIssue" or "ActiveIssue") &&
                    IsGangLeaderRecruitsIssueTitle(string.Join(" ", ReadString(marker, "title"), ReadString(marker, "hint"))) &&
                    !(ReadString(marker, "type") == "AvailableIssue" &&
                      contactedAvailableGivers?.Contains(ReadString(hero, "heroId") ?? string.Empty) == true)) == true)
            .Select(hero => ReadString(hero, "heroId"))
            .Where(id => !string.IsNullOrWhiteSpace(id))
            .Cast<string>()
            .Distinct(StringComparer.Ordinal)
            .ToArray() ?? Array.Empty<string>();

    private static void AddGangLeaderIssueTalkAction(JsonArray catalog, JsonObject? state,
        IReadOnlySet<string>? contactedGangLeaderIssueGivers)
    {
        var context = state?["context"] as JsonObject;
        if (ReadString(context, "gameState") != "MapState" || ReadString(context, "menuId") != "town") return;
        var giverIds = GetVisibleGangLeaderRecruitsIssueGivers(state, contactedGangLeaderIssueGivers);
        if (giverIds.Length == 0) return;
        catalog.Add(new JsonObject
        {
            ["action"] = "talkToSettlementHero",
            ["arguments"] = new JsonArray("HeroId"),
            ["argumentValues"] = new JsonObject
            {
                ["HeroId"] = new JsonArray(giverIds.Select(id => (JsonNode?)JsonValue.Create(id)).ToArray())
            }
        });
    }

    private static bool IsCurrentGangLeaderRecruitsIssueConversation(JsonObject? state, IReadOnlySet<string>? contactedGivers)
    {
        var conversation = state?["context"]?["conversation"] as JsonObject;
        var heroId = ReadString(conversation, "heroId") ?? ReadString(conversation, "characterId");
        return !string.IsNullOrWhiteSpace(heroId) && contactedGivers?.Contains(heroId) == true;
    }

    private static bool IsMapStateConversation(JsonObject? state) =>
        ReadString(state?["context"] as JsonObject, "gameState") == "MapState" &&
        state?["context"]?["conversation"] is JsonObject;

    private static JsonArray BuildMapConversationActionCatalog(JsonObject? state, IReadOnlySet<string>? contactedGangLeaderIssueGivers = null)
    {
        var conversation = state?["context"]?["conversation"] as JsonObject;
        if (conversation is null) return new JsonArray();
        var options = conversation["options"] as JsonArray ?? new JsonArray();
        var gangLeaderIssueConversation = IsCurrentGangLeaderRecruitsIssueConversation(state, contactedGangLeaderIssueGivers);
        var clickableIds = options.OfType<JsonObject>()
            .Where(option => ReadBoolean(option, "clickable"))
            .Select(option => ReadString(option, "id"))
            .Where(id => !string.IsNullOrWhiteSpace(id) &&
                (!gangLeaderIssueConversation || id is not (GangLeaderRecruitsAlternativeOptionId or GangLeaderRecruitsLordOptionId)))
            .Distinct(StringComparer.Ordinal)
            .Cast<string>()
            .ToArray();
        if (clickableIds.Length > 0)
            return [new JsonObject
            {
                ["action"] = "dialogueSelect",
                ["arguments"] = new JsonArray("OptionId"),
                ["argumentValues"] = new JsonObject
                {
                    ["OptionId"] = new JsonArray(clickableIds.Select(id => (JsonNode?)JsonValue.Create(id)).ToArray())
                }
            }];
        if (options.Count == 0 && !string.IsNullOrWhiteSpace(ReadString(conversation, "sentenceText")))
            return [new JsonObject { ["action"] = "dialogueContinue", ["arguments"] = new JsonArray() }];
        return new JsonArray();
    }

    private static JsonArray BuildLocationLeaveActionCatalog(JsonObject state, string? menuId)
    {
        var catalog = new JsonArray();
        var leaveOptions = (state["availableMenuOptions"] as JsonArray ?? new JsonArray()).OfType<JsonObject>()
            .Where(option => ReadBoolean(option, "available") && ReadBoolean(option, "enabled") && ReadBoolean(option, "isLeave"))
            .Select(option => ReadString(option, "id"))
            .Where(id => !string.IsNullOrWhiteSpace(id)).Distinct(StringComparer.Ordinal).ToArray();
        if (leaveOptions.Length == 0) return catalog;
        var leaveAction = new JsonObject { ["action"] = "menuSelect", ["arguments"] = new JsonArray("MenuId", "OptionId") };
        leaveAction["argumentValues"] = new JsonObject
        {
            ["MenuId"] = new JsonArray(menuId),
            ["OptionId"] = new JsonArray(leaveOptions.Select(id => (JsonNode?)JsonValue.Create(id)).ToArray())
        };
        catalog.Add(leaveAction);
        return catalog;
    }

    private static JsonArray BuildRecruitmentActionCatalog(JsonObject optionsReceipt, JsonObject objective)
    {
        var data = optionsReceipt["data"] as JsonObject;
        var gold = ReadNumber(data, "gold") ?? 0;
        var journalTarget = ReadNumber(objective["partySize"] as JsonObject, "target") ?? 0;
        var partySize = ReadNumber(data, "partySize") ?? 0;
        var partyCapacity = ReadNumber(data, "partyCapacity") ?? 0;
        if (partySize >= journalTarget) return new JsonArray();
        var allEligibleOffers = (data?["offers"] as JsonArray)?.OfType<JsonObject>()
            .Where(offer => ReadBoolean(offer, "available"))
            .OrderBy(offer => ReadString(offer, "ownerId"), StringComparer.Ordinal)
            .ThenBy(offer => ReadNumber(offer, "slot") ?? double.MaxValue)
            .ThenBy(offer => ReadString(offer, "troopId"), StringComparer.Ordinal)
            .ToArray() ?? Array.Empty<JsonObject>();
        var offers = allEligibleOffers
            .Where(offer => (ReadNumber(offer, "cost") ?? double.MaxValue) <= gold)
            .ToArray();
        if (offers.Length == 0) return new JsonArray();
        var action = new JsonObject { ["action"] = "recruit", ["arguments"] = new JsonArray("ownerId", "troopId", "slot", "confirmPartySizeWarning") };
        action["argumentValues"] = new JsonObject
        {
            ["ownerId"] = new JsonArray(offers.Select(offer => (JsonNode?)JsonValue.Create(ReadString(offer, "ownerId"))).Distinct().ToArray()),
            ["troopId"] = new JsonArray(offers.Select(offer => (JsonNode?)JsonValue.Create(ReadString(offer, "troopId"))).Distinct().ToArray()),
            ["slot"] = new JsonArray(offers.Select(offer => (JsonNode?)JsonValue.Create((int)(ReadNumber(offer, "slot") ?? -1))).Distinct().ToArray()),
            ["confirmPartySizeWarning"] = partySize + 1 > partyCapacity ? new JsonArray(JsonValue.Create(0), JsonValue.Create(1)) : new JsonArray(JsonValue.Create(0))
        };
        action["currentOffers"] = new JsonArray(offers.Select(offer => offer.DeepClone()).ToArray());
        var catalog = new JsonArray(action);
        var bulkCost = allEligibleOffers.Sum(offer => ReadNumber(offer, "cost") ?? double.MaxValue);
        var remainingTarget = journalTarget - partySize;
        var remainingCapacity = partyCapacity - partySize;
        if (allEligibleOffers.Length > 1 && allEligibleOffers.Length <= remainingTarget &&
            allEligibleOffers.Length <= remainingCapacity && bulkCost <= gold &&
            IsIntegralInRange(partySize, 0, int.MaxValue) && IsIntegralInRange(partyCapacity, 0, int.MaxValue) &&
            IsIntegralInRange(journalTarget, 0, int.MaxValue) && IsIntegralInRange(bulkCost, 0, int.MaxValue))
        {
            var bulkAction = new JsonObject
            {
                ["action"] = "recruitAll",
                ["arguments"] = new JsonArray("expectedCount", "expectedTotalCost", "expectedPartySize", "expectedPartyCapacity", "expectedJournalTarget", "expectedOfferSetSha256")
            };
            bulkAction["argumentValues"] = new JsonObject
            {
                ["expectedCount"] = new JsonArray(JsonValue.Create(allEligibleOffers.Length)),
                ["expectedTotalCost"] = new JsonArray(JsonValue.Create((int)bulkCost)),
                ["expectedPartySize"] = new JsonArray(JsonValue.Create((int)partySize)),
                ["expectedPartyCapacity"] = new JsonArray(JsonValue.Create((int)partyCapacity)),
                ["expectedJournalTarget"] = new JsonArray(JsonValue.Create((int)journalTarget)),
                ["expectedOfferSetSha256"] = new JsonArray(JsonValue.Create(ComputeOfferSetSha256(allEligibleOffers)))
            };
            catalog.Add(bulkAction);
        }
        return catalog;
    }

    internal static bool IsPartySizeBlockedAtNativeCapacityUntilRenown(JsonObject? state, JsonObject? objective)
    {
        var party = state?["party"] as JsonObject;
        var partyObjective = objective?["partySize"] as JsonObject;
        var renownObjective = objective?["renown"] as JsonObject;
        var members = ReadNumber(party, "members");
        var capacity = ReadNumber(party, "sizeLimit");
        var partyTarget = ReadNumber(partyObjective, "target");
        var renownCurrent = ReadNumber(renownObjective, "current");
        var renownTarget = ReadNumber(renownObjective, "target");
        return members.HasValue && capacity.HasValue && partyTarget.HasValue && renownCurrent.HasValue && renownTarget.HasValue &&
               members.Value >= capacity.Value && members.Value < partyTarget.Value &&
               !ReadBoolean(renownObjective, "met") && renownCurrent.Value < renownTarget.Value;
    }

    private static bool IsIntegralInRange(double value, int minimum, int maximum) =>
        !double.IsNaN(value) && !double.IsInfinity(value) && value >= minimum && value <= maximum && Math.Truncate(value) == value;

    private static string ComputeOfferSetSha256(IEnumerable<JsonObject> offers)
    {
        var canonical = string.Join("\n", offers.Select(offer =>
            ReadString(offer, "ownerId") + "\t" + ReadString(offer, "troopId") + "\t" +
            ((int)(ReadNumber(offer, "slot") ?? -1)).ToString(CultureInfo.InvariantCulture) + "\t" +
            ((int)(ReadNumber(offer, "cost") ?? -1)).ToString(CultureInfo.InvariantCulture)));
        using var sha256 = SHA256.Create();
        return BitConverter.ToString(sha256.ComputeHash(Encoding.UTF8.GetBytes(canonical))).Replace("-", string.Empty).ToLowerInvariant();
    }

    internal static JsonObject? BuildNoAffordableVolunteerOfferTraceStep(JsonObject optionsReceipt, JsonObject objective,
        JsonObject? state, double campaignDay)
    {
        if (BuildRecruitmentActionCatalog(optionsReceipt, objective).Count != 0) return null;
        var settlementId = ReadString(state?["location"] as JsonObject, "currentSettlementId");
        if (string.IsNullOrWhiteSpace(settlementId)) return null;
        var data = optionsReceipt["data"] as JsonObject;
        return new JsonObject
        {
            ["stage"] = "recruitment-settlement-no-affordable-volunteer-offers",
            ["settlementId"] = settlementId,
            ["campaignDay"] = double.IsFinite(campaignDay) ? JsonValue.Create(campaignDay) : null,
            ["gold"] = ReadNumber(data, "gold") is double gold ? JsonValue.Create(gold) : null,
            ["affordableOfferActionCount"] = 0
        };
    }

    private static JsonArray BuildPrisonerRecruitmentActionCatalog(JsonObject optionsReceipt, JsonObject objective)
    {
        var data = optionsReceipt["data"] as JsonObject;
        var journalTarget = ReadNumber(objective["partySize"] as JsonObject, "target") ?? 0;
        var memberCount = ReadNumber(data, "memberCount") ?? 0;
        if (memberCount >= journalTarget) return new JsonArray();
        var offers = (data?["options"] as JsonArray)?.OfType<JsonObject>()
            .Where(option => ReadBoolean(option, "isAvailable") && (ReadNumber(option, "availableCount") ?? 0) > 0)
            .ToArray() ?? Array.Empty<JsonObject>();
        if (offers.Length == 0) return new JsonArray();

        var action = new JsonObject { ["action"] = "recruitPrisoner", ["arguments"] = new JsonArray("TroopId", "ConfirmPartySizeWarning", "ConfirmPrisonerLimitWarning") };
        action["argumentValues"] = new JsonObject
        {
            ["TroopId"] = new JsonArray(offers.Select(option => (JsonNode?)JsonValue.Create(ReadString(option, "troopId"))).Distinct().ToArray()),
            ["ConfirmPartySizeWarning"] = ReadBoolean(data, "nativeDoneConfirmationRequiredForOne")
                ? new JsonArray(JsonValue.Create(0), JsonValue.Create(1))
                : new JsonArray(JsonValue.Create(0)),
            ["ConfirmPrisonerLimitWarning"] = ReadBoolean(data, "nativePrisonerLimitWarningAfterOneRecruit")
                ? new JsonArray(JsonValue.Create(1))
                : new JsonArray(JsonValue.Create(0))
        };
        action["currentOffers"] = new JsonArray(offers.Select(option => option.DeepClone()).ToArray());
        action["prisonerLimitConfirmationText"] = data?["nativePrisonerLimitConfirmationText"]?.DeepClone();
        return [action];
    }

    internal static bool TryResolveRecruitmentAction(JsonObject? decision, JsonObject? state, JsonArray? safeTargets,
        JsonObject? optionsReceipt, string? moveTargetId, bool moving, out string action, out JsonObject arguments,
        out string? selectedSettlementId, out string rejection, JsonObject? prisonerOptionsReceipt = null,
        bool moreSafeTargetsAvailable = false, JsonObject? objective = null,
        IReadOnlySet<string>? contactedGangLeaderIssueGivers = null)
    {
        action = string.Empty;
        arguments = new JsonObject();
        selectedSettlementId = null;
        rejection = "The action must exactly match the current Native recruitment catalog.";
        var supplied = decision?["arguments"] as JsonObject;
        if (decision?["action"] is not JsonValue actionNode || !actionNode.TryGetValue<string>(out var parsedAction) || supplied is null) return false;
        action = parsedAction;
        var catalogObjective = objective ?? new JsonObject { ["partySize"] = new JsonObject { ["target"] = double.MaxValue } };
        var catalog = BuildActionCatalog(state, catalogObjective, safeTargets,
            optionsReceipt, moveTargetId, moving, prisonerOptionsReceipt, moreSafeTargetsAvailable, contactedGangLeaderIssueGivers);
        var resolvedAction = action;
        var allowed = catalog.OfType<JsonObject>().FirstOrDefault(candidate => ReadString(candidate, "action") == resolvedAction);
        if (allowed is null) return false;
        switch (action)
        {
            case "mapSettlementTargets" when supplied.Count == 0:
                return true;
            case "mapSettlementTargetsMore" when supplied.Count == 0 && moreSafeTargetsAvailable:
                return true;
            case "move":
                var settlementId = ReadString(supplied, "SettlementId") ?? ReadString(supplied, "settlementId");
                selectedSettlementId = settlementId;
                if (supplied.Count != 1 || string.IsNullOrWhiteSpace(settlementId) || safeTargets is null ||
                    !safeTargets.OfType<JsonObject>().Any(target => ReadString(target, "id") == settlementId)) return false;
                arguments["settlementId"] = settlementId;
                return true;
            case "recruitOptions" when supplied.Count == 0:
                return true;
            case "prisonerRecruitmentOptions" when supplied.Count == 0:
                return true;
            case "talkToSettlementHero":
                var heroId = ReadString(supplied, "HeroId") ?? ReadString(supplied, "heroId");
                var allowedHeroIds = allowed["argumentValues"]?["HeroId"] as JsonArray;
                if (supplied.Count != 1 || string.IsNullOrWhiteSpace(heroId) ||
                    allowedHeroIds?.Any(value => value?.GetValue<string>() == heroId) != true) return false;
                arguments["heroId"] = heroId;
                return true;
            case "dialogueContinue":
            {
                var continueConversation = state?["context"]?["conversation"] as JsonObject;
                var continueOptions = continueConversation?["options"] as JsonArray;
                if (supplied.Count != 0 || !(IsVillagersInNeedConversation(state) || IsMapStateConversation(state)) ||
                    continueOptions?.Count != 0 || string.IsNullOrWhiteSpace(ReadString(continueConversation, "sentenceText")))
                    return false;
                return true;
            }
            case "dialogueSelect":
            {
                var dialogueOptionId = ReadString(supplied, "OptionId") ?? ReadString(supplied, "optionId");
                var conversationOptions = state?["context"]?["conversation"]?["options"] as JsonArray;
                var allowedOptionIds = allowed["argumentValues"]?["OptionId"] as JsonArray;
                var isKnownMissionConversation = IsVillagersInNeedConversation(state);
                if (supplied.Count != 1 || !(isKnownMissionConversation || IsMapStateConversation(state)) || string.IsNullOrWhiteSpace(dialogueOptionId) ||
                    allowedOptionIds?.Any(value => value?.GetValue<string>() == dialogueOptionId) != true ||
                    conversationOptions?.OfType<JsonObject>().Any(option => ReadString(option, "id") == dialogueOptionId && ReadBoolean(option, "clickable") &&
                        (!isKnownMissionConversation || !string.Equals(ReadString(option, "textId"), VillagersInNeedVillaMissionStartTextId, StringComparison.Ordinal))) != true)
                    return false;
                arguments["optionId"] = dialogueOptionId;
                return true;
            }
            case "menuSelect":
                var menuId = ReadString(supplied, "MenuId") ?? ReadString(supplied, "menuId");
                var optionId = ReadString(supplied, "OptionId") ?? ReadString(supplied, "optionId");
                var availableOptions = state?["availableMenuOptions"] as JsonArray;
                if (supplied.Count != 2 || string.IsNullOrWhiteSpace(menuId) || ReadString(state?["context"] as JsonObject, "menuId") != menuId ||
                    string.IsNullOrWhiteSpace(optionId) || availableOptions is null || !availableOptions.OfType<JsonObject>().Any(option =>
                        ReadString(option, "id") == optionId && ReadBoolean(option, "available") && ReadBoolean(option, "enabled") && ReadBoolean(option, "isLeave"))) return false;
                arguments["menuId"] = menuId;
                arguments["optionId"] = optionId;
                return true;
            case "recruit":
                var ownerId = ReadString(supplied, "ownerId");
                var troopId = ReadString(supplied, "troopId");
                if (!TryReadCanonicalInteger(supplied, "slot", out var slot) ||
                    !TryReadCanonicalInteger(supplied, "confirmPartySizeWarning", out var confirm)) return false;
                var offer = optionsReceipt?["data"]?["offers"]?.AsArray().OfType<JsonObject>().FirstOrDefault(item =>
                    ReadString(item, "ownerId") == ownerId && ReadString(item, "troopId") == troopId && (int)(ReadNumber(item, "slot") ?? -2) == slot &&
                    ReadBoolean(item, "available") && (ReadNumber(item, "cost") ?? double.MaxValue) <= (ReadNumber(optionsReceipt["data"] as JsonObject, "gold") ?? 0));
                if (supplied.Count != 4 || ownerId is null || troopId is null || slot < 0 || confirm is not (0 or 1) || offer is null) return false;
                var partySize = (int)(ReadNumber(optionsReceipt?["data"] as JsonObject, "partySize") ?? 0);
                var partyCapacity = (int)(ReadNumber(optionsReceipt?["data"] as JsonObject, "partyCapacity") ?? 0);
                if (partySize + 1 > partyCapacity && confirm != 1) return false;
                if (partySize + 1 <= partyCapacity && confirm != 0) return false;
                arguments["ownerId"] = ownerId;
                arguments["troopId"] = troopId;
                arguments["slot"] = slot;
                arguments["confirmPartySizeWarning"] = confirm;
                return true;
            case "recruitAll":
                if (!TryReadCanonicalInteger(supplied, "expectedCount", out var expectedCount) ||
                    !TryReadCanonicalInteger(supplied, "expectedTotalCost", out var expectedTotalCost) ||
                    !TryReadCanonicalInteger(supplied, "expectedPartySize", out var expectedPartySize) ||
                    !TryReadCanonicalInteger(supplied, "expectedPartyCapacity", out var expectedPartyCapacity) ||
                    !TryReadCanonicalInteger(supplied, "expectedJournalTarget", out var expectedJournalTarget)) return false;
                var expectedOfferSetSha256 = ReadString(supplied, "expectedOfferSetSha256");
                var bulkCatalogValues = allowed["argumentValues"] as JsonObject;
                if (supplied.Count != 6 || expectedCount < 2 || expectedTotalCost < 0 || expectedPartySize < 0 ||
                    expectedPartyCapacity < expectedPartySize || expectedJournalTarget < expectedPartySize + expectedCount ||
                    !IsSha256Hex(expectedOfferSetSha256) ||
                    !ContainsInt(bulkCatalogValues?["expectedCount"] as JsonArray, expectedCount) ||
                    !ContainsInt(bulkCatalogValues?["expectedTotalCost"] as JsonArray, expectedTotalCost) ||
                    !ContainsInt(bulkCatalogValues?["expectedPartySize"] as JsonArray, expectedPartySize) ||
                    !ContainsInt(bulkCatalogValues?["expectedPartyCapacity"] as JsonArray, expectedPartyCapacity) ||
                    !ContainsInt(bulkCatalogValues?["expectedJournalTarget"] as JsonArray, expectedJournalTarget) ||
                    !ContainsString(bulkCatalogValues?["expectedOfferSetSha256"] as JsonArray, expectedOfferSetSha256!)) return false;
                arguments["expectedCount"] = expectedCount;
                arguments["expectedTotalCost"] = expectedTotalCost;
                arguments["expectedPartySize"] = expectedPartySize;
                arguments["expectedPartyCapacity"] = expectedPartyCapacity;
                arguments["expectedJournalTarget"] = expectedJournalTarget;
                arguments["expectedOfferSetSha256"] = expectedOfferSetSha256;
                return true;
            case "recruitPrisoner":
                var prisonerTroopId = ReadString(supplied, "TroopId") ?? ReadString(supplied, "troopId");
                if (!TryReadCanonicalInteger(supplied, "ConfirmPartySizeWarning", out var prisonerPartyConfirm) ||
                    !TryReadCanonicalInteger(supplied, "ConfirmPrisonerLimitWarning", out var prisonerLimitConfirm)) return false;
                var prisonerOffer = prisonerOptionsReceipt?["data"]?["options"]?.AsArray().OfType<JsonObject>().FirstOrDefault(option =>
                    ReadString(option, "troopId") == prisonerTroopId && ReadBoolean(option, "isAvailable") && (ReadNumber(option, "availableCount") ?? 0) > 0);
                var prisonerAction = BuildPrisonerRecruitmentActionCatalog(prisonerOptionsReceipt ?? new JsonObject(),
                    new JsonObject { ["partySize"] = new JsonObject { ["target"] = double.MaxValue } })
                    .OfType<JsonObject>().FirstOrDefault(item => ReadString(item, "action") == "recruitPrisoner");
                var prisonerArguments = prisonerAction?["argumentValues"] as JsonObject;
                var listedPrisonerTroopIds = prisonerArguments?["TroopId"] as JsonArray;
                if (supplied.Count != 3 || string.IsNullOrWhiteSpace(prisonerTroopId) || prisonerOffer is null ||
                    !ContainsInt(prisonerArguments?["ConfirmPartySizeWarning"] as JsonArray, prisonerPartyConfirm) ||
                    !ContainsInt(prisonerArguments?["ConfirmPrisonerLimitWarning"] as JsonArray, prisonerLimitConfirm) ||
                    listedPrisonerTroopIds?.Any(value => value?.GetValue<string>() == prisonerTroopId) != true)
                    return false;
                arguments["troopId"] = prisonerTroopId;
                arguments["confirmPartySizeWarning"] = prisonerPartyConfirm;
                arguments["confirmPrisonerLimitWarning"] = prisonerLimitConfirm;
                return true;
            default:
                return false;
        }
    }

    private static bool TryResolveBackstreetLeave(JsonObject state, JsonArray catalog, JsonArray? safeTargets,
        JsonObject? offers, string? moveTargetId, bool moving, out JsonObject arguments)
    {
        arguments = new JsonObject();
        var context = state["context"] as JsonObject;
        var options = state["availableMenuOptions"] as JsonArray;
        if (catalog.Count != 1 || ReadString(context, "gameState") != "MapState" || ReadString(context, "menuId") != "town_backstreet" ||
            ReadBoolean(context, "inquiryOpen") || AgentHostCampaignStateFacts.IsActiveEncounter(state) ||
            options?.OfType<JsonObject>().Any(option => ReadString(option, "id") == "town_backstreet_back" &&
                ReadBoolean(option, "available") && ReadBoolean(option, "enabled") && ReadBoolean(option, "isLeave")) != true)
            return false;

        var catalogAction = catalog[0] as JsonObject;
        if (ReadString(catalogAction, "action") != "menuSelect") return false;
        var values = catalogAction?["argumentValues"] as JsonObject;
        var menuIds = values?["MenuId"] as JsonArray;
        var optionIds = values?["OptionId"] as JsonArray;
        if (menuIds?.Count != 1 || optionIds?.Count != 1 ||
            menuIds[0]?.GetValue<string>() != "town_backstreet" || optionIds[0]?.GetValue<string>() != "town_backstreet_back")
            return false;

        var decision = new JsonObject
        {
            ["action"] = "menuSelect",
            ["arguments"] = new JsonObject { ["MenuId"] = "town_backstreet", ["OptionId"] = "town_backstreet_back" }
        };
        return TryResolveRecruitmentAction(decision, state, safeTargets, offers, moveTargetId, moving,
            out var action, out arguments, out _, out _) && action == "menuSelect";
    }

    private static JsonArray? FilterRecruitmentTargets(JsonArray? targets, string? currentSettlementId, HashSet<string> visited)
    {
        if (targets is null) return null;
        var result = new JsonArray();
        foreach (var target in targets.OfType<JsonObject>())
        {
            var id = ReadString(target, "id");
            var type = ReadString(target, "type");
            if (string.IsNullOrWhiteSpace(id) || type is not ("town" or "village") || id == currentSettlementId || visited.Contains(id) ||
                ReadBoolean(target, "hostile") || ReadBoolean(target, "underSiege")) continue;
            result.Add(new JsonObject
            {
                ["id"] = id,
                ["name"] = target["name"]?.DeepClone(),
                ["type"] = type,
                ["distance"] = target["distance"]?.DeepClone()
            });
        }
        return result;
    }

    internal static JsonArray GetRecruitmentSettlementTargetPage(JsonArray? allTargets, int startIndex)
    {
        var page = new JsonArray();
        if (allTargets is null || allTargets.Count == 0) return page;
        var start = Math.Clamp(startIndex, 0, allTargets.Count);
        foreach (var target in allTargets.Skip(start).Take(SettlementTargetPageSize))
            page.Add(target?.DeepClone());
        return page;
    }

    internal static HashSet<string> BuildNoAffordableVolunteerSettlementCooldowns(JsonArray? trace, double campaignDay, double gold)
    {
        var result = new HashSet<string>(StringComparer.Ordinal);
        if (!double.IsFinite(campaignDay) || !double.IsFinite(gold) || trace is null) return result;
        var currentGameDay = Math.Floor(campaignDay);
        foreach (var entry in trace.OfType<JsonObject>())
        {
            if (ReadString(entry, "stage") != "recruitment-settlement-no-affordable-volunteer-offers") continue;
            var settlementId = ReadString(entry, "settlementId");
            var observedDay = ReadDouble(entry, "campaignDay", double.NaN);
            var observedGold = ReadDouble(entry, "gold", double.NaN);
            if (string.IsNullOrWhiteSpace(settlementId) || !double.IsFinite(observedDay) || !double.IsFinite(observedGold)) continue;
            if (Math.Floor(observedDay) == currentGameDay && gold <= observedGold)
                result.Add(settlementId);
        }
        return result;
    }

    private static HashSet<string> BuildNoAffordableVolunteerSettlementEventKeys(JsonArray? trace) =>
        trace?.OfType<JsonObject>()
            .Where(entry => ReadString(entry, "stage") == "recruitment-settlement-no-affordable-volunteer-offers")
            .Select(entry => BuildNoOfferSettlementEventKey(ReadString(entry, "settlementId") ?? string.Empty,
                ReadDouble(entry, "campaignDay", double.NaN), ReadDouble(entry, "gold", double.NaN)))
            .ToHashSet(StringComparer.Ordinal) ?? new HashSet<string>(StringComparer.Ordinal);

    private static string BuildNoOfferSettlementEventKey(string settlementId, double campaignDay, double gold)
    {
        var dayKey = double.IsFinite(campaignDay) ? Math.Floor(campaignDay).ToString("0", CultureInfo.InvariantCulture) : "unknown-day";
        var goldKey = double.IsFinite(gold) ? gold.ToString("R", CultureInfo.InvariantCulture) : "unknown-gold";
        return settlementId + "|" + dayKey + "|" + goldKey;
    }

    private static bool IsRecruitmentMenu(string? menuId) => menuId is "town" or "town_backstreet" or "village";
    private static bool HasEnabledOption(JsonArray? options, string id) => options?.OfType<JsonObject>().Any(option => ReadString(option, "id") == id && ReadBoolean(option, "available") && ReadBoolean(option, "enabled")) == true;

    private static JsonObject BuildObservation(JsonObject state, JsonArray journal, JsonObject objective, JsonArray? safeTargets,
        JsonObject? offers, JsonObject? previousReceipt, JsonObject? feedback, JsonObject? prisonerOptions = null,
        int targetPageIndex = 0, int totalSafeTargetCount = -1, bool moreSafeTargetsAvailable = false)
    {
        var result = new JsonObject
        {
            ["scope"] = "native-storymode-party-size-recruitment",
            ["journalObjectiveSnapshot"] = journal.DeepClone(),
            ["objectiveSnapshot"] = objective.DeepClone(),
            ["visibleSafeRecruitmentSettlements"] = safeTargets?.DeepClone(),
            ["safeSettlementTargetPage"] = safeTargets is null ? null : new JsonObject
            {
                ["pageStartIndex"] = Math.Max(0, targetPageIndex),
                ["pageSize"] = safeTargets.Count,
                ["totalSafeTargetCount"] = totalSafeTargetCount >= 0 ? totalSafeTargetCount : safeTargets.Count,
                ["moreAvailable"] = moreSafeTargetsAvailable
            },
            ["currentRecruitmentOffers"] = BuildRecruitmentOffersObservation(offers),
            ["currentPrisonerRecruitmentOptions"] = BuildPrisonerRecruitmentOptionsObservation(prisonerOptions),
            ["decisionFeedback"] = feedback?.DeepClone(),
            ["state"] = state.DeepClone()
        };
        return result;
    }

    private static JsonObject? BuildPrisonerRecruitmentOptionsObservation(JsonObject? receipt)
    {
        if (receipt?["data"] is not JsonObject data) return null;
        var options = new JsonArray();
        foreach (var option in (data["options"] as JsonArray ?? new JsonArray()).OfType<JsonObject>())
        {
            options.Add(new JsonObject
            {
                ["troopId"] = option["troopId"]?.DeepClone(),
                ["troopName"] = option["troopName"]?.DeepClone(),
                ["cultureId"] = option["cultureId"]?.DeepClone(),
                ["tier"] = option["tier"]?.DeepClone(),
                ["currentCount"] = option["currentCount"]?.DeepClone(),
                ["currentConformityXp"] = option["currentConformityXp"]?.DeepClone(),
                ["conformityXpPerRecruit"] = option["conformityXpPerRecruit"]?.DeepClone(),
                ["availableCount"] = option["availableCount"]?.DeepClone(),
                ["isAvailable"] = option["isAvailable"]?.DeepClone(),
                ["nativeRecruitReason"] = option["nativeRecruitReason"]?.DeepClone(),
                ["moraleEffectPerRecruit"] = option["moraleEffectPerRecruit"]?.DeepClone()
            });
        }
        return new JsonObject
        {
            ["memberCount"] = data["memberCount"]?.DeepClone(),
            ["partySizeLimit"] = data["partySizeLimit"]?.DeepClone(),
            ["mainPartyPrisonerCount"] = data["mainPartyPrisonerCount"]?.DeepClone(),
            ["mainPartyPrisonerLimit"] = data["mainPartyPrisonerLimit"]?.DeepClone(),
            ["nativeDoneConfirmationRequiredForOne"] = data["nativeDoneConfirmationRequiredForOne"]?.DeepClone(),
            ["nativeDoneConfirmationText"] = data["nativeDoneConfirmationText"]?.DeepClone(),
            ["nativePrisonerLimitWarningAfterOneRecruit"] = data["nativePrisonerLimitWarningAfterOneRecruit"]?.DeepClone(),
            ["nativePrisonerLimitConfirmationTitle"] = data["nativePrisonerLimitConfirmationTitle"]?.DeepClone(),
            ["nativePrisonerLimitConfirmationText"] = data["nativePrisonerLimitConfirmationText"]?.DeepClone(),
            ["options"] = options
        };
    }

    private static JsonArray BuildControlCatalog(JsonObject? state, bool moving, int actionCount)
    {
        var controls = new JsonArray("stop");
        if (moving && actionCount == 0 && AgentHostNativeMapMovementMonitor.IsCampaignTimeAdvancing(state)) controls.Add("observeAgain");
        return controls;
    }

    private static JsonObject RejectedFeedback(string kind, string message) => new() { ["kind"] = kind, ["message"] = message };

    private static string BuildSafeStopRecoveryInstruction(JsonArray catalog, string[]? actionNames = null)
    {
        var names = actionNames ?? catalog.OfType<JsonObject>()
            .Select(item => ReadString(item, "action"))
            .Where(name => !string.IsNullOrWhiteSpace(name))
            .Select(name => name!)
            .Distinct(StringComparer.Ordinal)
            .ToArray();

        if (names.Length == 1)
        {
            var action = names[0];
            if (action == "recruitOptions")
                return "Choose the currently listed recruitOptions action now. It only reads the current original RecruitmentVM offers; it does not recruit anyone or spend Gold. Then choose only an exact offer from the fresh Native result, or leave if no affordable offer is listed.";
            if (action == "prisonerRecruitmentOptions")
                return "Choose the currently listed prisonerRecruitmentOptions action now. It only reads current MainParty prisoner eligibility, Conformity XP, morale effect and the Native prisoner-limit warning; it does not recruit, spend Gold, or advance time.";
            if (action == "recruitPrisoner")
                return "Choose one currently listed prisoner offer and the exact listed troop-size/prisoner-limit confirmation values. This uses the original PartyScreen Recruit and Done handlers for one prisoner; consider the current EYC objective and the warning's movement/escape consequences.";
            if (action == "menuSelect")
                return "Choose the currently listed Native menuSelect action and one exact enabled option from its current argumentValues. If it is the settlement Leave option, use it to return to the campaign map and search another visible safe Town/Village.";
            if (action == "mapSettlementTargets")
                return "Choose the currently listed mapSettlementTargets query. It only reads visible safe settlement targets and does not move the party or change world time.";
            if (action == "mapSettlementTargetsMore")
                return "Choose the currently listed mapSettlementTargetsMore action to inspect the next page of the already-read safe Native settlement list. This is Host-only view navigation; it sends no Native command and does not move the party or change world time.";
            if (action == "move")
                return "Choose one currently listed settlement ID for the original Native move action, then passively observe until that move ends.";
            if (action == "dialogueContinue")
                return "Choose the currently listed Native dialogueContinue action. It only advances the VillagersInNeed NPC text when no answer is selectable; it does not start the villa mission or change Campaign time.";
            if (action == "dialogueSelect")
                return "Choose among the current visible VillagersInNeed answers. If they describe the rescue approach, choose a non-starting approach and continue the conversation; if a choice would launch the Villa Mission, do not choose it, and use the visible postponement choice when it appears.";
            if (action == "recruit")
                return "Choose one currently listed affordable offer using its exact current ownerId, troopId, slot, and confirmation value; Native will revalidate those values before recruitment.";
        }

        return "A safe stop is not available while the current Native catalog lists " + string.Join(", ", names) + ". Choose one action from the current allowedActions catalog; it will be revalidated against fresh Native state before any game action is sent.";
    }

    private static JsonObject BuildStep(int iteration, JsonObject observation, JsonObject? decision, JsonObject? receipt,
        JsonObject? feedback, JsonObject? afterState, string? startedAt, JsonObject? timing = null)
    {
        var step = new JsonObject
        {
            ["iteration"] = iteration,
            ["observation"] = observation.DeepClone(),
            ["decision"] = decision?.DeepClone(),
            ["nativeReceipt"] = receipt?.DeepClone(),
            ["decisionFeedback"] = feedback?.DeepClone(),
            ["observationAfter"] = afterState?.DeepClone(),
            ["actionStartedUtc"] = startedAt,
            ["actionTiming"] = timing?.DeepClone()
        };
        return step;
    }

    private static JsonObject SafeReceipt(JsonObject receipt, string action, string? selectedSettlementId)
    {
        var safe = new JsonObject
        {
            ["action"] = action,
            ["status"] = ReadString(receipt, "status"),
            ["selectedSettlementId"] = selectedSettlementId
        };
        if (action == "mapSettlementTargets")
        {
            var count = (receipt["data"]?["mapSettlementTargets"] as JsonArray)?.Count ?? 0;
            safe["data"] = new JsonObject { ["visibleTargetCount"] = count };
        }
        else if (action == "recruitOptions")
        {
            safe["data"] = BuildRecruitmentOffersObservation(receipt);
        }
        else if (action == "prisonerRecruitmentOptions")
        {
            safe["data"] = BuildPrisonerRecruitmentSummary(receipt);
        }
        else
        {
            safe["data"] = receipt["data"]?.DeepClone();
        }
        return safe;
    }

    private static JsonObject? BuildPrisonerRecruitmentSummary(JsonObject? receipt)
    {
        var data = receipt?["data"] as JsonObject;
        if (data is null) return null;
        var options = data["options"] as JsonArray ?? new JsonArray();
        var available = options.OfType<JsonObject>().Where(option => ReadBoolean(option, "isAvailable") && (ReadNumber(option, "availableCount") ?? 0) > 0).ToArray();
        return new JsonObject
        {
            ["memberCount"] = data["memberCount"]?.DeepClone(),
            ["partySizeLimit"] = data["partySizeLimit"]?.DeepClone(),
            ["mainPartyPrisonerCount"] = data["mainPartyPrisonerCount"]?.DeepClone(),
            ["mainPartyPrisonerLimit"] = data["mainPartyPrisonerLimit"]?.DeepClone(),
            ["nativeDoneConfirmationRequiredForOne"] = data["nativeDoneConfirmationRequiredForOne"]?.DeepClone(),
            ["nativePrisonerLimitWarningAfterOneRecruit"] = data["nativePrisonerLimitWarningAfterOneRecruit"]?.DeepClone(),
            ["optionCount"] = options.Count,
            ["availableOfferCount"] = available.Length
        };
    }

    private static JsonObject? BuildRecruitmentOffersObservation(JsonObject? receipt)
    {
        var data = receipt?["data"] as JsonObject;
        if (data is null) return null;
        var offers = data["offers"] as JsonArray;
        var gold = ReadNumber(data, "gold") ?? 0;
        var available = offers?.OfType<JsonObject>().Where(offer => ReadBoolean(offer, "available")).ToArray() ?? Array.Empty<JsonObject>();
        var affordable = available.Where(offer => (ReadNumber(offer, "cost") ?? double.MaxValue) <= gold).ToArray();
        var lowest = affordable.Select(offer => ReadNumber(offer, "cost")).Where(cost => cost.HasValue).Select(cost => cost!.Value).DefaultIfEmpty(double.NaN).Min();
        return new JsonObject
        {
            ["gold"] = data["gold"]?.DeepClone(),
            ["partySize"] = data["partySize"]?.DeepClone(),
            ["partyCapacity"] = data["partyCapacity"]?.DeepClone(),
            ["offerCount"] = offers?.Count ?? 0,
            ["availableOfferCount"] = available.Length,
            ["affordableOfferCount"] = affordable.Length,
            ["lowestAffordableCost"] = double.IsFinite(lowest) ? JsonValue.Create(lowest) : null
        };
    }

    private static string DescribeNoAction(JsonObject state, JsonObject? options)
    {
        if (options is not null && (options["data"]?["offers"] as JsonArray)?.Count == 0)
            return "The current original RecruitmentVM has no volunteer offers. Leave this settlement and search another currently visible safe Town/Village.";
        return "No current safe Town/Village move, enabled recruit_volunteers entry or affordable Native volunteer offer is available.";
    }

    private static JsonObject? ReadState(JsonElement receipt)
    {
        if (ReadString(receipt, "status") != "completed" || !receipt.TryGetProperty("state", out var state) || state.ValueKind != JsonValueKind.Object) return null;
        return JsonNode.Parse(state.GetRawText())?.AsObject();
    }

    private static async Task<JsonArray> ReadJournalAsync(IAgentHostQuestDetailsNativeClient client, CancellationToken cancellationToken)
    {
        using var details = await client.ReadQuestDetailsAsync(QuestId, cancellationToken);
        var root = JsonNode.Parse(details.RootElement.GetRawText())?.AsObject();
        if (ReadString(root, "status") != "completed" || root?["data"] is not JsonObject data || ReadString(data, "questId") != QuestId)
            throw new AgentHostException("recruitment-quest-details-unavailable", "The Native Journal no longer contains the exact active EYC quest.");
        return AgentHostEstablishYourClanGoalLoop.BuildJournalObjectives(data);
    }

    private static double ReadDouble(JsonObject? node, string name, double fallback = double.NaN) => ReadNumber(node, name) ?? fallback;
    private static double ReadDouble(JsonElement element, string name, double fallback = double.NaN) =>
        element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var value) && value.TryGetDouble(out var result) ? result : fallback;

    private static double? ReadNumber(JsonObject? node, string name)
    {
        if (node?[name] is not JsonValue value) return null;
        if (value.TryGetValue<double>(out var doubleValue)) return doubleValue;
        if (value.TryGetValue<int>(out var intValue)) return intValue;
        if (value.TryGetValue<long>(out var longValue)) return longValue;
        return null;
    }

    private static string? ReadString(JsonObject? node, string name) => node?[name] is JsonValue value && value.TryGetValue<string>(out var result) ? result : null;
    private static bool ReadBoolean(JsonObject? node, string name) => node?[name] is JsonValue value && value.TryGetValue<bool>(out var result) && result;
    private static int ReadInt(JsonElement element, string name, int fallback) => element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var value) && value.TryGetInt32(out var result) ? result : fallback;
    private static int ReadInt(JsonObject? node, string name, int fallback) => node?[name] is JsonValue value && value.TryGetValue<int>(out var result) ? result : fallback;
    private static bool TryReadCanonicalInteger(JsonObject node, string name, out int result)
    {
        result = -1;
        if (node[name] is not JsonValue value) return false;
        if (value.TryGetValue<int>(out result)) return true;
        if (!value.TryGetValue<string>(out var text) || !int.TryParse(text, NumberStyles.None, CultureInfo.InvariantCulture, out result))
            return false;
        return string.Equals(text, result.ToString(CultureInfo.InvariantCulture), StringComparison.Ordinal);
    }
    private static bool ContainsInt(JsonArray? values, int expected) => values?.OfType<JsonValue>().Any(value => value.TryGetValue<int>(out var item) && item == expected) == true;
    private static bool ContainsString(JsonArray? values, string expected) => values?.OfType<JsonValue>().Any(value => value.TryGetValue<string>(out var item) && string.Equals(item, expected, StringComparison.Ordinal)) == true;
    private static bool IsSha256Hex(string? value) => value is { Length: 64 } && value.All(character => character is >= '0' and <= '9' or >= 'a' and <= 'f');
    private static string? ReadString(JsonElement element, string name) => element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;

    private sealed class FakeRecruitmentNativeClient : IAgentHostCampaignNativeClient, IAgentHostQuestDetailsNativeClient, IAgentHostRecruitmentNativeClient
    {
        private bool _recruited;
        private readonly bool _startOnMap;
        private readonly bool _startAtTrainingField;
        private readonly bool _startAtBackstreet;
        private readonly bool _useRecruitAll;
        private readonly bool _startAtNativeCapacity;
        private bool _trainingFieldLeft;
        private bool _backstreetLeft;
        internal FakeRecruitmentNativeClient(bool startOnMap = true, bool startAtTrainingField = false, bool startAtBackstreet = false,
            bool useRecruitAll = false, bool startAtNativeCapacity = false)
        {
            _startOnMap = startOnMap;
            _startAtTrainingField = startAtTrainingField;
            _startAtBackstreet = startAtBackstreet;
            _useRecruitAll = useRecruitAll;
            _startAtNativeCapacity = startAtNativeCapacity;
        }
        internal int RecruitedMembers => _startAtNativeCapacity ? 20 : (_recruited ? (_useRecruitAll ? 6 : 5) : 4);
        internal int JournalPartyTarget => _startAtNativeCapacity ? 25 : (_useRecruitAll ? 6 : 5);
        internal int Gold => _recruited ? (_useRecruitAll ? 50 : 80) : 100;
        internal List<string> Actions { get; } = new();

        public Task<JsonDocument> ReadStateAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var atTrainingField = _startAtTrainingField && !_trainingFieldLeft;
            var atBackstreet = _startAtBackstreet && !_backstreetLeft;
            var menuId = atTrainingField ? "training_field_menu" : atBackstreet ? "town_backstreet" : "town";
            var state = new JsonObject
            {
                ["campaignDay"] = 10.0,
                ["timeControlMode"] = "Stop",
                ["context"] = new JsonObject
                {
                    ["gameState"] = _startOnMap ? "MapState" : "MenuState",
                    ["menuId"] = menuId,
                    ["encounterActive"] = atTrainingField || atBackstreet,
                    ["encounteredPartyId"] = atTrainingField ? "tutorial_training_field" : (atBackstreet ? "town-a" : null),
                    ["inquiryOpen"] = false,
                    ["captivity"] = new JsonObject { ["isCaptive"] = false }
                },
                ["availableMenuOptions"] = atTrainingField
                    ? new JsonArray(new JsonObject { ["id"] = "training_field_leave", ["available"] = true, ["enabled"] = true, ["isLeave"] = true })
                    : atBackstreet
                        ? new JsonArray(
                            new JsonObject { ["id"] = "town_tavern", ["available"] = true, ["enabled"] = true },
                            new JsonObject { ["id"] = "recruit_mercenaries", ["available"] = true, ["enabled"] = false },
                            new JsonObject { ["id"] = "town_backstreet_back", ["available"] = true, ["enabled"] = true, ["isLeave"] = true })
                        : new JsonArray(new JsonObject { ["id"] = RecruitmentMenuOptionId, ["available"] = true, ["enabled"] = true }),
                ["location"] = new JsonObject { ["currentSettlementId"] = atTrainingField ? "tutorial_training_field" : "town-a", ["targetSettlementId"] = null },
                ["party"] = new JsonObject { ["members"] = RecruitedMembers, ["sizeLimit"] = 20, ["isMoving"] = false },
                ["quests"] = new JsonArray(new JsonObject { ["id"] = QuestId }),
                ["storyModeEstablishClan"] = new JsonObject { ["partySize"] = new JsonObject { ["current"] = RecruitedMembers, ["target"] = JournalPartyTarget } }
            };
            return Task.FromResult(JsonDocument.Parse(new JsonObject { ["status"] = "completed", ["state"] = state }.ToJsonString()));
        }

        public Task<JsonDocument> ReadQuestDetailsAsync(string questId, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (questId != QuestId) throw new AgentHostException("recruitment-selftest-wrong-quest", "The fake client received an unexpected Journal request.");
            var values = new (string Id, int Current, int Target)[]
            {
                ("gold", Gold, 2000), ("partySize", RecruitedMembers, JournalPartyTarget), ("renown", 0, 50), ("companions", 0, 1)
            };
            var stages = new JsonArray(values.Select(value => (JsonNode?)new JsonObject
            {
                ["hasTask"] = true,
                ["currentProgress"] = value.Current,
                ["targetProgress"] = value.Target,
                ["description"] = value.Id
            }).ToArray());
            var data = new JsonObject { ["questId"] = QuestId, ["journalStages"] = stages };
            return Task.FromResult(JsonDocument.Parse(new JsonObject { ["status"] = "completed", ["data"] = data }.ToJsonString()));
        }

        public Task<JsonDocument> ExecuteCampaignActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            throw new AgentHostException("recruitment-selftest-unexpected-campaign-action", "The already-arrived fake recruitment case must not travel or query the map.");
        }

        public Task<JsonDocument> ExecuteRecruitmentActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Actions.Add(action);
            if (action == "menuSelect" && _startAtTrainingField && !_trainingFieldLeft &&
                ReadString(arguments, "menuId") == "training_field_menu" && ReadString(arguments, "optionId") == "training_field_leave")
            {
                _trainingFieldLeft = true;
                return Task.FromResult(JsonDocument.Parse(new JsonObject { ["status"] = "completed", ["data"] = new JsonObject { ["menuId"] = "training_field_menu", ["optionId"] = "training_field_leave" } }.ToJsonString()));
            }
            if (action == "menuSelect" && _startAtBackstreet && !_backstreetLeft &&
                ReadString(arguments, "menuId") == "town_backstreet" && ReadString(arguments, "optionId") == "town_backstreet_back")
            {
                _backstreetLeft = true;
                return Task.FromResult(JsonDocument.Parse(new JsonObject { ["status"] = "completed", ["data"] = new JsonObject { ["menuId"] = "town_backstreet", ["optionId"] = "town_backstreet_back" } }.ToJsonString()));
            }
            if (action == "recruitOptions")
            {
                var offers = _useRecruitAll
                    ? new JsonArray(
                        new JsonObject { ["ownerId"] = "notable-a", ["troopId"] = "vlandian_recruit", ["slot"] = 0, ["cost"] = 20, ["available"] = true },
                        new JsonObject { ["ownerId"] = "notable-b", ["troopId"] = "imperial_recruit", ["slot"] = 1, ["cost"] = 30, ["available"] = true })
                    : new JsonArray(new JsonObject
                    {
                        ["ownerId"] = "notable-a", ["troopId"] = "vlandian_recruit", ["slot"] = 0, ["cost"] = 20, ["available"] = true
                    });
                var options = new JsonObject
                {
                    ["gold"] = Gold,
                    ["partySize"] = RecruitedMembers,
                    ["partyCapacity"] = 20,
                    ["offers"] = offers
                };
                return Task.FromResult(JsonDocument.Parse(new JsonObject { ["status"] = "completed", ["data"] = options }.ToJsonString()));
            }
            if (action == "recruitAll" && _useRecruitAll && !_recruited)
            {
                var expectedHash = ComputeOfferSetSha256(new[]
                {
                    new JsonObject { ["ownerId"] = "notable-a", ["troopId"] = "vlandian_recruit", ["slot"] = 0, ["cost"] = 20, ["available"] = true },
                    new JsonObject { ["ownerId"] = "notable-b", ["troopId"] = "imperial_recruit", ["slot"] = 1, ["cost"] = 30, ["available"] = true }
                });
                if (ReadInt(arguments, "expectedCount", -1) != 2 || ReadInt(arguments, "expectedTotalCost", -1) != 50 ||
                    ReadInt(arguments, "expectedPartySize", -1) != 4 || ReadInt(arguments, "expectedPartyCapacity", -1) != 20 ||
                    ReadInt(arguments, "expectedJournalTarget", -1) != JournalPartyTarget ||
                    ReadString(arguments, "expectedOfferSetSha256") != expectedHash)
                    throw new AgentHostException("recruitment-selftest-invalid-take-all", "The fake Native transport received a stale or malformed Take All transaction.");
                _recruited = true;
                var bulkReceipt = new JsonObject
                {
                    ["committed"] = true, ["verified"] = true, ["recruitedCount"] = 2, ["totalCost"] = 50,
                    ["beforeMembers"] = 4, ["afterMembers"] = 6, ["beforeGold"] = 100, ["afterGold"] = 50,
                    ["partyCapacity"] = 20, ["offerSetSha256"] = expectedHash
                };
                return Task.FromResult(JsonDocument.Parse(new JsonObject { ["status"] = "completed", ["data"] = bulkReceipt }.ToJsonString()));
            }
            if (action != "recruit" || _recruited || ReadString(arguments, "ownerId") != "notable-a" || ReadString(arguments, "troopId") != "vlandian_recruit" || ReadInt(arguments, "slot", -1) != 0 || ReadInt(arguments, "confirmPartySizeWarning", -1) != 0)
                throw new AgentHostException("recruitment-selftest-invalid-transaction", "The fake recruitment transport received a stale or malformed volunteer transaction.");
            _recruited = true;
            var receipt = new JsonObject { ["verified"] = true, ["beforeMembers"] = 4, ["afterMembers"] = 5, ["beforeGold"] = 100, ["afterGold"] = 80, ["cost"] = 20 };
            return Task.FromResult(JsonDocument.Parse(new JsonObject { ["status"] = "completed", ["data"] = receipt }.ToJsonString()));
        }
    }

    private sealed class FakeVillagersInNeedRecruitmentClient : IAgentHostCampaignNativeClient, IAgentHostQuestDetailsNativeClient, IAgentHostRecruitmentNativeClient, IAgentHostBattleSimulationNativeClient
    {
        private bool _moveIssued;
        private bool _arrived;
        private bool _mapConversationActive;
        private bool _mapConversationResolved;
        private int _dialogueStage = -1;
        private bool _talkedToVillagers;
        private bool _deferredVillaMission;
        private bool _stealthMissionStarted;
        private bool _recruited;
        internal List<string> Actions { get; } = new();
        internal int MapPartyTargetPollCount { get; private set; }
        internal bool StealthMissionStarted => _stealthMissionStarted;
        internal bool DeferredVillaMission => _deferredVillaMission;
        internal bool TalkedToVillagers => _talkedToVillagers;

        private int PartySize => _recruited ? 5 : 4;
        private int Gold => _recruited ? 80 : 100;

        public Task<JsonDocument> ReadStateAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var conversationStartupPending = _arrived && _dialogueStage == -2;
            var inVillagerConversation = _arrived && _dialogueStage is >= 0 and <= 3;
            var missionActive = conversationStartupPending || inVillagerConversation;
            var gameState = missionActive ? "MissionState" : "MapState";
            var menuId = missionActive ? "village" : (_arrived ? "village" : null);
            var conversationOptions = _dialogueStage switch
            {
                1 => new JsonArray(
                    new JsonObject { ["id"] = "villagers_wait_for_opening", ["text"] = "Wait until the bandits turn their backs.", ["clickable"] = true },
                    new JsonObject { ["id"] = "villagers_pass_unseen", ["text"] = "Pass through unseen.", ["clickable"] = true }),
                3 => new JsonArray(
                    new JsonObject { ["id"] = "adg:131", ["textId"] = VillagersInNeedVillaMissionStartTextId, ["text"] = "Lead on.", ["clickable"] = true },
                    new JsonObject { ["id"] = "adg:132", ["textId"] = VillagersInNeedDeferTextId, ["text"] = "I have to take care of something else, first.", ["clickable"] = true }),
                _ => new JsonArray()
            };
            var state = new JsonObject
            {
                ["campaignDay"] = _arrived ? 10.115 : (_moveIssued ? 10.002 : 10.0),
                ["timeControlMode"] = inVillagerConversation ? "Stop" : (_moveIssued && !_arrived ? "StoppablePlay" : "Stop"),
                ["context"] = new JsonObject
                {
                    ["gameState"] = gameState,
                    ["menuId"] = menuId,
                    ["encounterActive"] = missionActive,
                    ["encounteredPartyId"] = missionActive ? VillagersInNeedVillageId : null,
                    ["escapeMenuOpen"] = false,
                    ["inquiryOpen"] = false,
                    ["conversation"] = _mapConversationActive
                        ? new JsonObject
                        {
                            ["characterId"] = "notable-a",
                            ["sentenceText"] = "A Native MapState dialogue line.",
                            ["options"] = new JsonArray(new JsonObject { ["id"] = "map_current", ["text"] = "Continue the conversation.", ["clickable"] = true })
                        }
                        : inVillagerConversation ? new JsonObject
                        {
                            ["characterId"] = VillagersInNeedHeroId,
                            ["sentenceText"] = _dialogueStage is 1 or 3 ? "Native VillagersInNeed answer line" : "Native VillagersInNeed NPC line",
                            ["options"] = conversationOptions
                        } : null,
                    ["captivity"] = new JsonObject { ["isCaptive"] = false }
                },
                ["location"] = new JsonObject
                {
                    ["currentSettlementId"] = _arrived ? VillagersInNeedVillageId : null,
                    ["targetSettlementId"] = _moveIssued && !_arrived ? VillagersInNeedVillageId : null
                },
                ["party"] = new JsonObject { ["members"] = PartySize, ["sizeLimit"] = 20, ["isMoving"] = _moveIssued && !_arrived },
                ["economy"] = new JsonObject { ["gold"] = Gold, ["renown"] = 20 },
                ["quests"] = new JsonArray(new JsonObject { ["id"] = QuestId }, new JsonObject { ["id"] = VillagersInNeedQuestId }),
                ["availableMenuOptions"] = missionActive ? new JsonArray() : (_arrived
                    ? new JsonArray(new JsonObject { ["id"] = RecruitmentMenuOptionId, ["available"] = true, ["enabled"] = true })
                    : new JsonArray()),
                ["storyModeEstablishClan"] = new JsonObject
                {
                    ["status"] = "active",
                    ["partySize"] = new JsonObject { ["current"] = PartySize, ["target"] = 5 }
                }
            };
            if (conversationStartupPending) _dialogueStage = 0;
            return Task.FromResult(JsonDocument.Parse(new JsonObject
            {
                ["status"] = "completed",
                ["campaignDay"] = _arrived ? 10.115 : (_moveIssued ? 10.002 : 10.0),
                ["timeControlMode"] = inVillagerConversation ? "Stop" : (_moveIssued && !_arrived ? "StoppablePlay" : "Stop"),
                ["state"] = state
            }.ToJsonString()));
        }

        public Task<JsonDocument> ReadQuestDetailsAsync(string questId, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (questId != QuestId) throw new AgentHostException("villagers-in-need-selftest-wrong-quest", "The fake client received an unexpected Journal request.");
            var values = new (string Id, int Current, int Target)[]
            {
                ("gold", Gold, 2000), ("partySize", PartySize, 5), ("renown", 20, 50), ("companions", 0, 1)
            };
            var stages = new JsonArray(values.Select(value => (JsonNode?)new JsonObject
            {
                ["hasTask"] = true,
                ["currentProgress"] = value.Current,
                ["targetProgress"] = value.Target,
                ["description"] = value.Id
            }).ToArray());
            return Task.FromResult(JsonDocument.Parse(new JsonObject
            {
                ["status"] = "completed",
                ["data"] = new JsonObject { ["questId"] = QuestId, ["journalStages"] = stages }
            }.ToJsonString()));
        }

        public Task<JsonDocument> ExecuteCampaignActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Actions.Add(action);
            if (action == "mapSettlementTargets")
                return Task.FromResult(JsonDocument.Parse(new JsonObject
                {
                    ["status"] = "completed",
                    ["data"] = new JsonObject
                    {
                        ["mapSettlementTargets"] = new JsonArray(new JsonObject
                        {
                            ["id"] = VillagersInNeedVillageId, ["type"] = "village", ["distance"] = 1.2, ["hostile"] = false, ["underSiege"] = false
                        })
                    }
                }.ToJsonString()));
            if (action == "move" && ReadString(arguments, "settlementId") == VillagersInNeedVillageId)
            {
                _moveIssued = true;
                return Task.FromResult(JsonDocument.Parse("{\"status\":\"completed\",\"data\":{\"targetSettlementId\":\"village_ES3_2\"}}"));
            }
            throw new AgentHostException("villagers-in-need-selftest-unexpected-campaign-action", "The fake Native VillagersInNeed route received an unsupported or out-of-order action.");
        }

        public Task<JsonDocument> ExecuteBattleSimulationActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (action != "mapPartyTargets" || arguments.Count != 0)
                throw new AgentHostException("villagers-in-need-selftest-unexpected-map-poll", "The PartySize movement monitor may only query current Native map-party targets without arguments.");
            MapPartyTargetPollCount++;
            if (MapPartyTargetPollCount == 1 && _moveIssued)
            {
                _mapConversationActive = true;
            }
            else if (MapPartyTargetPollCount >= 2 && _mapConversationResolved)
            {
                _arrived = true;
                _dialogueStage = -2;
            }
            using var stateResponse = ReadStateAsync(cancellationToken).GetAwaiter().GetResult();
            var native = JsonNode.Parse(stateResponse.RootElement.GetRawText())?.AsObject()
                ?? throw new AgentHostException("villagers-in-need-selftest-map-poll-invalid", "The fake Native movement poll returned no current state.");
            native["data"] = new JsonObject { ["schemaVersion"] = 1, ["mapPartyTargets"] = new JsonArray() };
            return Task.FromResult(JsonDocument.Parse(native.ToJsonString()));
        }

        public Task<JsonDocument> PauseForVisibleHostileDecisionAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            throw new AgentHostException("villagers-in-need-selftest-unexpected-pause", "The VillagersInNeed movement fixture contains no hostile party and must not change the Native clock.");
        }

        public Task<JsonDocument> ExecuteRecruitmentActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Actions.Add(action);
            if (_mapConversationActive)
            {
                if (action != "dialogueSelect" || ReadString(arguments, "optionId") != "map_current")
                    throw new AgentHostException("villagers-in-need-selftest-map-conversation-invalid-action", "A map conversation during movement must accept only its current Native clickable option before travel resumes.");
                _mapConversationActive = false;
                _mapConversationResolved = true;
                return Task.FromResult(JsonDocument.Parse("{\"status\":\"completed\",\"data\":{\"conversationClosed\":true}}"));
            }
            if (!_arrived)
                throw new AgentHostException("villagers-in-need-selftest-recruited-before-deferral", "Recruitment must wait for the original conversation deferral and return to the Village menu.");
            if (action == "dialogueContinue" && _dialogueStage is 0 or 2)
            {
                _dialogueStage++;
                return Task.FromResult(JsonDocument.Parse("{\"status\":\"completed\"}"));
            }
            if (action == "dialogueSelect")
            {
                var optionId = ReadString(arguments, "optionId");
                if (_dialogueStage == 1 && optionId is "villagers_wait_for_opening" or "villagers_pass_unseen")
                {
                    _talkedToVillagers = true;
                    _dialogueStage = 2;
                    return Task.FromResult(JsonDocument.Parse("{\"status\":\"completed\"}"));
                }
                if (_dialogueStage == 3 && optionId == "adg:132")
                {
                    _deferredVillaMission = true;
                    _dialogueStage = 4;
                    return Task.FromResult(JsonDocument.Parse("{\"status\":\"completed\",\"data\":{\"villageMenuReturned\":true}}"));
                }
                if (_dialogueStage == 3 && optionId == "villagers_lead_on") _stealthMissionStarted = true;
            }
            if (_dialogueStage != 4)
                throw new AgentHostException("villagers-in-need-selftest-recruited-before-deferral", "Recruitment must wait for the original conversation deferral and return to the Village menu.");
            if (action == "recruitOptions")
                return Task.FromResult(JsonDocument.Parse(new JsonObject
                {
                    ["status"] = "completed",
                    ["data"] = new JsonObject
                    {
                        ["gold"] = Gold,
                        ["partySize"] = PartySize,
                        ["partyCapacity"] = 20,
                        ["offers"] = new JsonArray(new JsonObject
                        {
                            ["ownerId"] = "notable-a", ["troopId"] = "vlandian_recruit", ["slot"] = 0, ["cost"] = 20, ["available"] = true
                        })
                    }
                }.ToJsonString()));
            if (action == "recruit" && !_recruited && ReadString(arguments, "ownerId") == "notable-a" &&
                ReadString(arguments, "troopId") == "vlandian_recruit" && ReadInt(arguments, "slot", -1) == 0 &&
                ReadInt(arguments, "confirmPartySizeWarning", -1) == 0)
            {
                _recruited = true;
                return Task.FromResult(JsonDocument.Parse("{\"status\":\"completed\",\"data\":{\"verified\":true,\"beforeMembers\":4,\"afterMembers\":5,\"beforeGold\":100,\"afterGold\":80,\"cost\":20}}"));
            }
            throw new AgentHostException("villagers-in-need-selftest-invalid-recruitment", "The fake Native recruitment adapter received an unexpected transaction.");
        }
    }

    private sealed class FakeVillagersInNeedDecisionProvider : IAgentHostDecisionProvider
    {
        private bool _stopWhileMovingOnce;
        private bool _returnInvalidWaitOnce;
        private bool _rejectUnavailableControlOnce;
        private bool _unavailableControlRejected;
        internal int CallCount { get; private set; }
        internal bool PrematureMoveStopRecovered { get; private set; }
        internal bool InvalidWaitRejected { get; private set; }
        internal bool ProviderControlUnavailableRecovered { get; private set; }
        internal int DialogueContinueDecisions { get; private set; }
        internal FakeVillagersInNeedDecisionProvider(bool stopWhileMovingOnce = false, bool returnInvalidWaitOnce = false, bool rejectUnavailableControlOnce = false)
        {
            _stopWhileMovingOnce = stopWhileMovingOnce;
            _returnInvalidWaitOnce = returnInvalidWaitOnce;
            _rejectUnavailableControlOnce = rejectUnavailableControlOnce;
        }
        public string ModelId => "deterministic-villagers-in-need-recruitment-selftest";
        public string ConfigurationSource => "harness-fake-provider";
        public Task CheckConfiguredModelAsync(CancellationToken cancellationToken) { cancellationToken.ThrowIfCancellationRequested(); return Task.CompletedTask; }

        public Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            CallCount++;
            var controls = request.GetProperty("allowedControls");
            if (controls.EnumerateArray().Any(control => control.GetString() == "observeAgain"))
            {
                var waitBounds = request.GetProperty("controlArguments").GetProperty("observeAgain").GetProperty("waitSeconds");
                if (waitBounds.GetProperty("minimum").GetInt32() != 10 || waitBounds.GetProperty("maximum").GetInt32() != 10)
                    throw new AgentHostException("villagers-in-need-selftest-movement-wait-bounds-invalid", "The PartySize provider schema must require exactly one monitored 10-second observation window while movement remains active.");
                var feedback = request.TryGetProperty("decisionFeedback", out var feedbackNode) ? feedbackNode : default;
                if (_stopWhileMovingOnce)
                {
                    _stopWhileMovingOnce = false;
                    CallCount++;
                    return Task.FromResult(new ProviderDecisionResult("completed", ModelId, 1, 1, "villagers-in-need-selftest", new JsonObject
                    {
                        ["stop"] = true, ["reason"] = "Pause this subgoal while movement is still active."
                    }));
                }
                if (feedback.ValueKind == JsonValueKind.Object && ReadString(feedback, "kind") == "safe-stop-rejected-with-observe-again-control")
                {
                    var instruction = ReadString(feedback, "requiredNextStep");
                    if (instruction?.Contains("observeAgain", StringComparison.Ordinal) != true || instruction.Contains("change the game clock", StringComparison.Ordinal) != true)
                        throw new AgentHostException("villagers-in-need-observe-again-recovery-unclear", "The Host recovery instruction must name passive observeAgain and forbid clock changes.");
                    PrematureMoveStopRecovered = true;
                }
                if (_returnInvalidWaitOnce)
                {
                    _returnInvalidWaitOnce = false;
                    CallCount++;
                    return Task.FromResult(new ProviderDecisionResult("completed", ModelId, 1, 1, "villagers-in-need-selftest", new JsonObject
                    {
                        ["observeAgain"] = true, ["waitSeconds"] = 9
                    }));
                }
                if (feedback.ValueKind == JsonValueKind.Object && ReadString(feedback, "kind") == "control")
                {
                    var message = ReadString(feedback, "message");
                    if (message?.Contains("requires waitSeconds=10 exactly", StringComparison.Ordinal) != true)
                        throw new AgentHostException("villagers-in-need-invalid-wait-feedback-unclear", "The Host must explain the exact ten-second wait requirement after rejecting a model response outside the control schema.");
                    InvalidWaitRejected = true;
                }
                if (_rejectUnavailableControlOnce && !_unavailableControlRejected && InvalidWaitRejected)
                {
                    _unavailableControlRejected = true;
                    CallCount++;
                    throw new AgentHostException("provider-control-unavailable", "Synthetic response selected a control that is not listed while Native movement is active.");
                }
                if (feedback.ValueKind == JsonValueKind.Object && ReadString(feedback, "kind") == "decision-rejected-before-native")
                {
                    var allowedControls = request.GetProperty("decisionFeedback").GetProperty("allowedControls");
                    if (ReadString(feedback, "code") != "provider-control-unavailable" ||
                        !allowedControls.EnumerateArray().Any(control => control.GetString() == "observeAgain") ||
                        !systemPrompt.Contains("RECOVERY DIRECTIVE", StringComparison.Ordinal))
                        throw new AgentHostException("villagers-in-need-provider-control-recovery-unclear", "The retry must receive the exact unavailable-control error, the current observeAgain catalog, and recovery instructions before any Native action.");
                    ProviderControlUnavailableRecovered = true;
                }
                if (_returnInvalidWaitOnce || !PrematureMoveStopRecovered)
                    throw new AgentHostException("villagers-in-need-invalid-wait-selftest-sequence", "The fake provider must first observe Host rejection of both premature stop and an out-of-contract wait before accepting the ten-second wait.");
                CallCount++;
                return Task.FromResult(new ProviderDecisionResult("completed", ModelId, 1, 1, "villagers-in-need-selftest", new JsonObject
                {
                    ["observeAgain"] = true, ["waitSeconds"] = 10
                }));
            }

            var catalog = request.GetProperty("allowedActions");
            foreach (var item in catalog.EnumerateArray())
            {
                var action = item.GetProperty("action").GetString();
                var values = item.TryGetProperty("argumentValues", out var argumentValues) ? argumentValues : default;
                if (action == "dialogueContinue") DialogueContinueDecisions++;
                if (action == "mapSettlementTargets" || action == "dialogueContinue" || action == "recruitOptions")
                    return Task.FromResult(new ProviderDecisionResult("completed", ModelId, 1, 1, "villagers-in-need-selftest", new JsonObject
                    {
                        ["action"] = action,
                        ["arguments"] = new JsonObject()
                    }));
                if (action == "move")
                    return Task.FromResult(new ProviderDecisionResult("completed", ModelId, 1, 1, "villagers-in-need-selftest", new JsonObject
                    {
                        ["action"] = action,
                        ["arguments"] = new JsonObject { ["SettlementId"] = values.GetProperty("SettlementId")[0].GetString() }
                    }));
                if (action == "dialogueSelect")
                {
                    var optionIds = values.GetProperty("OptionId").EnumerateArray().Select(value => value.GetString()).ToArray();
                    var selected = optionIds.Contains("adg:132", StringComparer.Ordinal) ? "adg:132" : optionIds.FirstOrDefault();
                    if (selected is null) throw new AgentHostException("villagers-in-need-selftest-no-option", "The fake conversation exposed no current answer.");
                    return Task.FromResult(new ProviderDecisionResult("completed", ModelId, 1, 1, "villagers-in-need-selftest", new JsonObject
                    {
                        ["action"] = action,
                        ["arguments"] = new JsonObject { ["OptionId"] = selected }
                    }));
                }
                if (action == "recruit")
                    return Task.FromResult(new ProviderDecisionResult("completed", ModelId, 1, 1, "villagers-in-need-selftest", new JsonObject
                    {
                        ["action"] = action,
                        ["arguments"] = new JsonObject
                        {
                            ["ownerId"] = values.GetProperty("ownerId")[0].GetString(),
                            ["troopId"] = values.GetProperty("troopId")[0].GetString(),
                            ["slot"] = values.GetProperty("slot")[0].GetInt32(),
                            ["confirmPartySizeWarning"] = values.GetProperty("confirmPartySizeWarning")[0].GetInt32()
                        }
                    }));
            }
            throw new AgentHostException("villagers-in-need-selftest-empty-catalog", "The fake Native route produced no safe action or movement control.");
        }

        public void Dispose() { }
    }

    private sealed class FakePrisonerRecruitmentNativeClient : IAgentHostRecruitmentNativeClient, IAgentHostQuestDetailsNativeClient
    {
        private int _members = 10;
        private int _prisoners = 15;
        private int _conformityXp = 496;
        private double _morale = 30;
        internal int PartyMembers => _members;
        internal int Prisoners => _prisoners;
        internal int PrisonerLimitConfirmations { get; private set; }
        internal List<string> Actions { get; } = [];

        public Task<JsonDocument> ReadStateAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var partySize = new JsonObject { ["current"] = _members, ["target"] = 11, ["met"] = _members >= 11 };
            var state = new JsonObject
            {
                ["context"] = new JsonObject { ["gameState"] = "MapState", ["menuId"] = null, ["inquiryOpen"] = false, ["encounterActive"] = false, ["captivity"] = new JsonObject { ["isCaptive"] = false } },
                ["identity"] = new JsonObject { ["clanTier"] = 0 },
                ["economy"] = new JsonObject { ["gold"] = 300, ["renown"] = 21.136 },
                ["party"] = new JsonObject { ["members"] = _members, ["prisoners"] = _prisoners, ["sizeLimit"] = 20, ["morale"] = _morale, ["isMoving"] = false },
                ["location"] = new JsonObject { ["currentSettlementId"] = null, ["targetSettlementId"] = null, ["targetPartyId"] = null },
                ["quests"] = new JsonArray(new JsonObject { ["id"] = QuestId }),
                ["storyModeEstablishClanStatus"] = new JsonObject { ["status"] = "active" },
                ["storyModeEstablishClan"] = new JsonObject { ["gold"] = new JsonObject { ["current"] = 300, ["target"] = 2000 }, ["partySize"] = partySize, ["renown"] = new JsonObject { ["current"] = 21.136, ["target"] = 50 }, ["companions"] = new JsonObject { ["current"] = 1, ["target"] = 1 } },
                ["availableMenuOptions"] = new JsonArray()
            };
            return Task.FromResult(JsonDocument.Parse(new JsonObject
            {
                ["status"] = "completed", ["processId"] = 321, ["campaignDay"] = 10.0, ["timeControlMode"] = "Stop", ["state"] = state
            }.ToJsonString()));
        }

        public Task<JsonDocument> ReadQuestDetailsAsync(string questId, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (questId != QuestId) throw new AgentHostException("prisoner-recruitment-selftest-wrong-quest", "The fake Native client received an unexpected Journal request.");
            var stages = new JsonArray(
                new JsonObject { ["hasTask"] = true, ["currentProgress"] = 300, ["targetProgress"] = 2000, ["description"] = "Gain gold" },
                new JsonObject { ["hasTask"] = true, ["currentProgress"] = _members, ["targetProgress"] = 11, ["description"] = "Raise party size" },
                new JsonObject { ["hasTask"] = true, ["currentProgress"] = 21.136, ["targetProgress"] = 50, ["description"] = "Gain renown" },
                new JsonObject { ["hasTask"] = true, ["currentProgress"] = 1, ["targetProgress"] = 1, ["description"] = "Find a companion" });
            return Task.FromResult(JsonDocument.Parse(new JsonObject
            {
                ["status"] = "completed", ["data"] = new JsonObject { ["questId"] = QuestId, ["journalStages"] = stages }
            }.ToJsonString()));
        }

        public Task<JsonDocument> ExecuteCampaignActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken) =>
            throw new AgentHostException("prisoner-recruitment-selftest-unexpected-campaign-action", "The prisoner recruitment route should not need map movement in this fixture.");

        public Task<JsonDocument> ExecuteRecruitmentActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            NativeMailboxClient.ValidateRecruitmentAction(action, arguments);
            Actions.Add(action);
            if (action == "prisonerRecruitmentOptions")
            {
                var data = new JsonObject
                {
                    ["memberCount"] = _members, ["partySizeLimit"] = 20, ["nativeDoneConfirmationRequiredForOne"] = false,
                    ["mainPartyPrisonerCount"] = _prisoners, ["mainPartyPrisonerLimit"] = 13,
                    ["nativePrisonerLimitWarningAfterOneRecruit"] = 13 < _prisoners - 1,
                    ["nativePrisonerLimitConfirmationText"] = "The prisoner roster exceeds its limit; prisoners may escape.",
                    ["options"] = new JsonArray(new JsonObject { ["troopId"] = "looter", ["troopName"] = "Bandit", ["currentCount"] = _prisoners, ["currentConformityXp"] = _conformityXp, ["conformityXpPerRecruit"] = 134, ["availableCount"] = _conformityXp / 134, ["isAvailable"] = _conformityXp >= 134, ["moraleEffectPerRecruit"] = -2 })
                };
                return Task.FromResult(JsonDocument.Parse(new JsonObject { ["status"] = "completed", ["data"] = data }.ToJsonString()));
            }
            if (action == "recruitPrisoner")
            {
                if (ReadString(arguments, "troopId") != "looter" || ReadInt(arguments, "confirmPartySizeWarning", -1) != 0 ||
                    ReadInt(arguments, "confirmPrisonerLimitWarning", -1) != 1 || _conformityXp < 134 || _prisoners <= 0)
                    throw new AgentHostException("prisoner-recruitment-selftest-native-precondition-failed", "The Host did not choose the exact eligible prisoner with the visible over-limit confirmation.");
                var beforeMembers = _members;
                var beforePrisoners = _prisoners;
                var beforeXp = _conformityXp;
                _members++;
                _prisoners--;
                _conformityXp -= 134;
                _morale -= 2;
                PrisonerLimitConfirmations++;
                return Task.FromResult(JsonDocument.Parse(new JsonObject
                {
                    ["status"] = "completed",
                    ["data"] = new JsonObject { ["committed"] = true, ["troopId"] = "looter", ["recruitedCount"] = 1, ["memberTotalBefore"] = beforeMembers, ["memberTotalAfter"] = _members, ["prisonerCountBefore"] = beforePrisoners, ["prisonerCountAfter"] = _prisoners, ["prisonerConformityXpBefore"] = beforeXp, ["prisonerConformityXpAfter"] = _conformityXp, ["goldBefore"] = 300, ["goldAfter"] = 300 }
                }.ToJsonString()));
            }
            throw new AgentHostException("prisoner-recruitment-selftest-unexpected-action", "The Host issued a Native action outside this bounded prisoner route.");
        }
    }

    private sealed class FakePrisonerRecruitmentDecisionProvider : IAgentHostDecisionProvider
    {
        internal int CallCount { get; private set; }
        internal JsonObject? LastRecruitmentObservation { get; private set; }
        public string ModelId => "deterministic-prisoner-recruitment-selftest";
        public string ConfigurationSource => "harness-fake-provider";
        public Task CheckConfiguredModelAsync(CancellationToken cancellationToken) { cancellationToken.ThrowIfCancellationRequested(); return Task.CompletedTask; }
        public Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var index = CallCount++;
            if (index == 0)
                return Task.FromResult(new ProviderDecisionResult("completed", ModelId, 8, 2, "fake-prisoner-route", new JsonObject
                {
                    ["action"] = "prisonerRecruitmentOptions", ["arguments"] = new JsonObject(), ["rationale"] = "Inspect current recruitable prisoners for the unmet PartySize objective."
                }));
            var prisonerOptions = request.GetProperty("observation").GetProperty("currentPrisonerRecruitmentOptions");
            var warningFlag = prisonerOptions.GetProperty("nativePrisonerLimitWarningAfterOneRecruit").GetBoolean();
            var warningText = prisonerOptions.GetProperty("nativePrisonerLimitConfirmationText").GetString() ?? string.Empty;
            var confirmationRulePresent = systemPrompt.Contains("separate confirmPrisonerLimitWarning", StringComparison.Ordinal);
            if (!warningFlag || !warningText.Contains("escape", StringComparison.OrdinalIgnoreCase) || !confirmationRulePresent)
                throw new AgentHostException("prisoner-recruitment-selftest-warning-not-observed", $"The model request omitted the exact current prisoner-limit warning and its separate confirmation rule. flag={warningFlag}; text={warningText}; systemRule={confirmationRulePresent}; observation={prisonerOptions.GetRawText()}.");
            LastRecruitmentObservation = JsonNode.Parse(request.GetProperty("observation").GetRawText()) as JsonObject;
            return Task.FromResult(new ProviderDecisionResult("completed", ModelId, 11, 3, "fake-prisoner-route", new JsonObject
            {
                ["action"] = "recruitPrisoner",
                ["arguments"] = new JsonObject { ["TroopId"] = "looter", ["ConfirmPartySizeWarning"] = 0, ["ConfirmPrisonerLimitWarning"] = 1 },
                ["rationale"] = "One Native recruit moves the current PartySize objective closer to its target; accept the observed temporary prisoner-cap penalty."
            }));
        }
        public void Dispose() { }
    }

    private sealed class FakeRecruitmentDecisionProvider : IAgentHostDecisionProvider
    {
        private readonly bool _useRecruitAll;
        internal FakeRecruitmentDecisionProvider(bool useRecruitAll = false) => _useRecruitAll = useRecruitAll;
        internal int CallCount { get; private set; }
        public string ModelId => "deterministic-establish-clan-recruitment-selftest";
        public string ConfigurationSource => "harness-fake-provider";
        public Task CheckConfiguredModelAsync(CancellationToken cancellationToken) { cancellationToken.ThrowIfCancellationRequested(); return Task.CompletedTask; }
        public Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var action = CallCount++ == 0 ? "recruitOptions" : (_useRecruitAll ? "recruitAll" : "recruit");
            JsonObject arguments;
            if (action == "recruitOptions") arguments = new JsonObject();
            else if (action == "recruitAll")
            {
                var bulkAction = request.GetProperty("allowedActions").EnumerateArray()
                    .FirstOrDefault(candidate => candidate.GetProperty("action").GetString() == "recruitAll");
                if (bulkAction.ValueKind != JsonValueKind.Object)
                    throw new AgentHostException("recruitment-selftest-take-all-not-listed", "The fake model expected the exact safe Native Take All candidate to appear in allowedActions.");
                var values = bulkAction.GetProperty("argumentValues");
                arguments = new JsonObject
                {
                    ["expectedCount"] = JsonNode.Parse(values.GetProperty("expectedCount")[0].GetRawText()),
                    ["expectedTotalCost"] = JsonNode.Parse(values.GetProperty("expectedTotalCost")[0].GetRawText()),
                    ["expectedPartySize"] = JsonNode.Parse(values.GetProperty("expectedPartySize")[0].GetRawText()),
                    ["expectedPartyCapacity"] = JsonNode.Parse(values.GetProperty("expectedPartyCapacity")[0].GetRawText()),
                    ["expectedJournalTarget"] = JsonNode.Parse(values.GetProperty("expectedJournalTarget")[0].GetRawText()),
                    ["expectedOfferSetSha256"] = JsonNode.Parse(values.GetProperty("expectedOfferSetSha256")[0].GetRawText())
                };
            }
            else arguments = new JsonObject
            {
                ["ownerId"] = "notable-a", ["troopId"] = "vlandian_recruit", ["slot"] = 0, ["confirmPartySizeWarning"] = 0
            };
            return Task.FromResult(new ProviderDecisionResult("completed", ModelId, 1, 1, "fake-recruitment-selftest", new JsonObject
            {
                ["action"] = action,
                ["arguments"] = arguments,
                ["rationale"] = "Use the currently listed Native volunteer offer."
            }));
        }
        public void Dispose() { }
    }

    private sealed class FakeObservedRecruitmentDecisionProvider : IAgentHostDecisionProvider
    {
        private readonly int _returnStopCount;

        internal FakeObservedRecruitmentDecisionProvider(int returnStopCount = 0) => _returnStopCount = returnStopCount;

        internal int CallCount { get; private set; }
        public string ModelId => "deterministic-training-field-recruitment-selftest";
        public string ConfigurationSource => "harness-fake-provider";
        public Task CheckConfiguredModelAsync(CancellationToken cancellationToken) { cancellationToken.ThrowIfCancellationRequested(); return Task.CompletedTask; }
        public Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (CallCount < _returnStopCount)
            {
                CallCount++;
                return Task.FromResult(new ProviderDecisionResult("completed", ModelId, 1, 1, "fake-training-field-premature-stop", new JsonObject
                {
                    ["stop"] = true,
                    ["reason"] = "There is an action but stopping is simpler."
                }));
            }
            if (_returnStopCount > 0 && CallCount == 1 &&
                (systemPrompt.Contains("RECOVERY DIRECTIVE", StringComparison.Ordinal) != true ||
                 request.GetProperty("decisionFeedback").GetProperty("kind").GetString() != "safe-stop-rejected-with-listed-actions" ||
                 !request.GetProperty("decisionFeedback").GetProperty("requiredNextStep").GetString()!.Contains("menuSelect", StringComparison.Ordinal)))
                throw new AgentHostException("training-field-premature-stop-feedback-invalid", "The recovery decision must receive the current Native menu action and a concise instruction before any Native action is issued.");
            var allowed = request.GetProperty("allowedActions");
            if (allowed.GetArrayLength() == 0) throw new AgentHostException("training-field-selftest-action-catalog-empty", "The fake Native training-field route exposed no currently allowed action.");
            var selected = allowed[0];
            var action = selected.GetProperty("action").GetString() ?? throw new AgentHostException("training-field-selftest-action-missing", "The fake Native catalog action had no id.");
            var values = selected.TryGetProperty("argumentValues", out var argumentValues) ? argumentValues : default;
            JsonObject arguments = action switch
            {
                "menuSelect" => new JsonObject
                {
                    ["MenuId"] = values.GetProperty("MenuId")[0].GetString(),
                    ["OptionId"] = values.GetProperty("OptionId")[0].GetString()
                },
                "recruitOptions" => new JsonObject(),
                "recruit" => new JsonObject
                {
                    ["ownerId"] = values.GetProperty("ownerId")[0].GetString(),
                    ["troopId"] = values.GetProperty("troopId")[0].GetString(),
                    ["slot"] = values.GetProperty("slot")[0].GetInt32(),
                    ["confirmPartySizeWarning"] = values.GetProperty("confirmPartySizeWarning")[0].GetInt32()
                },
                _ => throw new AgentHostException("training-field-selftest-action-unsupported", "The fake Native training-field route received an unexpected action catalog entry.")
            };
            CallCount++;
            return Task.FromResult(new ProviderDecisionResult("completed", ModelId, 1, 1, "fake-training-field-recruitment", new JsonObject
            {
                ["action"] = action,
                ["arguments"] = arguments
            }));
        }
        public void Dispose() { }
    }

    private sealed class FakeRecruitmentStopProvider : IAgentHostDecisionProvider
    {
        internal int CallCount { get; private set; }
        public string ModelId => "deterministic-recruitment-stop-selftest";
        public string ConfigurationSource => "harness-fake-provider";
        public Task CheckConfiguredModelAsync(CancellationToken cancellationToken) { cancellationToken.ThrowIfCancellationRequested(); return Task.CompletedTask; }
        public Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            CallCount++;
            if (!request.GetProperty("allowedControls").EnumerateArray().Any(control => control.GetString() == "stop"))
                throw new AgentHostException("recruitment-stop-selftest-control-not-listed", "The recruitment system prompt supports a safe stop, so the current control catalog must expose it.");
            return Task.FromResult(new ProviderDecisionResult("completed", ModelId, 1, 1, "self-test",
                new JsonObject { ["stop"] = true, ["reason"] = "No safe volunteer route now." }, "self-test", "json_schema"));
        }
        public void Dispose() { }
    }

    private sealed class FakeNoOfferCooldownNativeClient : IAgentHostCampaignNativeClient, IAgentHostQuestDetailsNativeClient, IAgentHostRecruitmentNativeClient
    {
        private readonly bool _startAtTown;
        private readonly int _targetCount;
        private bool _leftTown;
        internal List<string> Actions { get; } = new();
        internal List<string> CampaignActions { get; } = new();

        internal FakeNoOfferCooldownNativeClient(bool startAtTown, int targetCount = 2)
        {
            _startAtTown = startAtTown;
            _targetCount = Math.Max(0, targetCount);
        }

        public Task<JsonDocument> ReadStateAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var atTown = _startAtTown && !_leftTown;
            var state = new JsonObject
            {
                ["context"] = new JsonObject
                {
                    ["gameState"] = "MapState", ["menuId"] = atTown ? "town" : null,
                    ["escapeMenuOpen"] = false, ["inquiryOpen"] = false, ["encounterActive"] = false,
                    ["isWaitMenu"] = false, ["isWaitActive"] = false,
                    ["captivity"] = new JsonObject { ["isCaptive"] = false }
                },
                ["location"] = new JsonObject { ["currentSettlementId"] = atTown ? "town-a" : null, ["targetSettlementId"] = null, ["targetPartyId"] = null },
                ["party"] = new JsonObject { ["members"] = 1, ["healthy"] = 1, ["wounded"] = 0, ["prisoners"] = 0, ["isMoving"] = false },
                ["economy"] = new JsonObject { ["gold"] = 100, ["renown"] = 0 },
                ["quests"] = new JsonArray(new JsonObject { ["id"] = QuestId }),
                ["storyModeEstablishClan"] = new JsonObject { ["partySize"] = new JsonObject { ["current"] = 1, ["target"] = 5 } },
                ["availableMenuOptions"] = atTown
                    ? new JsonArray(
                        new JsonObject { ["id"] = RecruitmentMenuOptionId, ["available"] = true, ["enabled"] = true },
                        new JsonObject { ["id"] = "town_leave", ["available"] = true, ["enabled"] = true, ["isLeave"] = true })
                    : new JsonArray()
            };
            return Task.FromResult(JsonDocument.Parse(new JsonObject
            {
                ["status"] = "completed", ["campaignDay"] = 10.25, ["timeControlMode"] = "Stop", ["state"] = state
            }.ToJsonString()));
        }

        public Task<JsonDocument> ReadQuestDetailsAsync(string questId, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (questId != QuestId) throw new AgentHostException("no-offer-selftest-wrong-quest", "The no-offer cooldown fake received an unexpected Journal request.");
            var stages = new JsonArray(
                new JsonObject { ["hasTask"] = true, ["currentProgress"] = 100, ["targetProgress"] = 2000, ["description"] = "gold" },
                new JsonObject { ["hasTask"] = true, ["currentProgress"] = 1, ["targetProgress"] = 5, ["description"] = "partySize" },
                new JsonObject { ["hasTask"] = true, ["currentProgress"] = 0, ["targetProgress"] = 50, ["description"] = "renown" },
                new JsonObject { ["hasTask"] = true, ["currentProgress"] = 0, ["targetProgress"] = 1, ["description"] = "companions" });
            return Task.FromResult(JsonDocument.Parse(new JsonObject
            {
                ["status"] = "completed", ["data"] = new JsonObject { ["questId"] = QuestId, ["journalStages"] = stages }
            }.ToJsonString()));
        }

        public Task<JsonDocument> ExecuteCampaignActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Actions.Add(action);
            CampaignActions.Add(action);
            if (action != "mapSettlementTargets")
                throw new AgentHostException("no-offer-selftest-unexpected-campaign-action", "The cross-subflow cooldown fake only needs to return current map targets.");
            var targets = new JsonArray();
            for (var index = 0; index < _targetCount; index++)
            {
                var id = index == 0 ? "town-a" : $"settlement-{index:D2}";
                targets.Add(new JsonObject
                {
                    ["id"] = id,
                    ["name"] = "Settlement " + id,
                    ["type"] = index % 2 == 0 ? "town" : "village",
                    ["distance"] = (double)index + 1,
                    ["hostile"] = false,
                    ["underSiege"] = false
                });
            }
            return Task.FromResult(JsonDocument.Parse(new JsonObject
            {
                ["status"] = "completed",
                ["data"] = new JsonObject { ["mapSettlementTargets"] = targets }
            }.ToJsonString()));
        }

        public Task<JsonDocument> ExecuteRecruitmentActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Actions.Add(action);
            if (action == "recruitOptions")
                return Task.FromResult(JsonDocument.Parse(new JsonObject
                {
                    ["status"] = "completed",
                    ["data"] = new JsonObject { ["gold"] = 100, ["partySize"] = 1, ["partyCapacity"] = 20, ["offers"] = new JsonArray() }
                }.ToJsonString()));
            if (action == "menuSelect" && ReadString(arguments, "menuId") == "town" && ReadString(arguments, "optionId") == "town_leave" && _startAtTown && !_leftTown)
            {
                _leftTown = true;
                return Task.FromResult(JsonDocument.Parse(new JsonObject
                {
                    ["status"] = "completed", ["data"] = new JsonObject { ["menuId"] = "town", ["optionId"] = "town_leave" }
                }.ToJsonString()));
            }
            throw new AgentHostException("no-offer-selftest-unexpected-recruitment-action", "The no-offer cooldown fake accepts only its current empty RecruitmentVM query and enabled Town Leave.");
        }
    }

    private sealed class FakeNoOfferCooldownDecisionProvider : IAgentHostDecisionProvider
    {
        private readonly bool _queryMapTargets;
        private readonly bool _continueTargetPages;
        internal int CallCount { get; private set; }
        internal bool MoveCatalogObserved { get; private set; }
        internal int PageMoreActionCount { get; private set; }
        internal HashSet<string> ObservedMoveSettlementIds { get; } = new(StringComparer.Ordinal);
        internal List<(int PageStartIndex, int PageSize)> TargetPages { get; } = new();
        public string ModelId => "deterministic-no-offer-cooldown-selftest";
        public string ConfigurationSource => "harness-fake-provider";

        internal FakeNoOfferCooldownDecisionProvider(bool queryMapTargets, bool continueTargetPages = false)
        {
            _queryMapTargets = queryMapTargets;
            _continueTargetPages = continueTargetPages;
        }
        public Task CheckConfiguredModelAsync(CancellationToken cancellationToken) { cancellationToken.ThrowIfCancellationRequested(); return Task.CompletedTask; }

        public Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            CallCount++;
            var actionCatalog = request.GetProperty("allowedActions");
            var actions = actionCatalog.EnumerateArray().ToArray();
            var move = actions.FirstOrDefault(candidate => candidate.GetProperty("action").GetString() == "move");
            if (move.ValueKind == JsonValueKind.Object)
            {
                var ids = move.GetProperty("argumentValues").GetProperty("SettlementId").EnumerateArray()
                    .Select(value => value.GetString() ?? string.Empty).ToArray();
                foreach (var id in ids) ObservedMoveSettlementIds.Add(id);
                MoveCatalogObserved = true;
                var page = request.GetProperty("observation").GetProperty("safeSettlementTargetPage");
                var pageInfo = (page.GetProperty("pageStartIndex").GetInt32(), page.GetProperty("pageSize").GetInt32());
                if (!TargetPages.Contains(pageInfo)) TargetPages.Add(pageInfo);
            }

            var moreAction = actions.FirstOrDefault(candidate => candidate.GetProperty("action").GetString() == "mapSettlementTargetsMore");
            if (_continueTargetPages && moreAction.ValueKind == JsonValueKind.Object)
            {
                PageMoreActionCount++;
                return Decision(new JsonObject { ["action"] = "mapSettlementTargetsMore", ["arguments"] = new JsonObject() });
            }

            var selected = actions.FirstOrDefault();
            var selectedAction = selected.ValueKind == JsonValueKind.Object ? selected.GetProperty("action").GetString() : null;
            if (selectedAction == "recruitOptions")
                return Decision(new JsonObject { ["action"] = "recruitOptions", ["arguments"] = new JsonObject() });
            if (selectedAction == "menuSelect")
            {
                var values = selected.GetProperty("argumentValues");
                return Decision(new JsonObject { ["action"] = "menuSelect", ["arguments"] = new JsonObject
                {
                    ["MenuId"] = values.GetProperty("MenuId")[0].GetString(),
                    ["OptionId"] = values.GetProperty("OptionId")[0].GetString()
                }});
            }
            if (selectedAction == "mapSettlementTargets" && _queryMapTargets)
                return Decision(new JsonObject { ["action"] = "mapSettlementTargets", ["arguments"] = new JsonObject() });
            if (selectedAction == "mapSettlementTargets" || request.GetProperty("allowedControls").EnumerateArray().Any(control => control.GetString() == "stop"))
                return Decision(new JsonObject { ["stop"] = true, ["reason"] = "No further fake action is required for this bounded route test." });
            throw new AgentHostException("no-offer-selftest-empty-action-catalog", "The fake no-offer route exposed neither an expected action nor a safe stop.");
        }

        private Task<ProviderDecisionResult> Decision(JsonObject decision) => Task.FromResult(new ProviderDecisionResult(
            "completed", ModelId, 1, 1, "fake-no-offer-cooldown", decision, "self-test", "json_schema"));
        public void Dispose() { }
    }
}
