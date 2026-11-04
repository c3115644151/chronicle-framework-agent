using System.Text.Json;
using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal static class AgentHostEstablishClanTrainingIssueLoop
{
    private const string EycQuestId = "rebuild_player_clan_storymode_quest";
    private const string DirectTrainingResponseTextId = "QxEPwLyp";
    private const string BorrowedTroopId = "borrowed_troop";
    private const string VeteranBorrowedTroopId = "veteran_borrowed_troop";
    private const int MaxRejectedDecisions = 2;
    internal const int MaximumTrainingIssueDiscoveryDecisions = 32;
    internal static IReadOnlyList<object> RunContractSelfTests()
    {
        var discoveryMap = NativeState(null, null, new JsonArray());
        var discoveryBelowLimit = !ShouldStopUnproductiveTrainingIssueSearch(discoveryMap, MaximumTrainingIssueDiscoveryDecisions - 1, 0,
            activeTrainingIssue: false, directOfferAccepted: false);
        var discoveryAtLimit = ShouldStopUnproductiveTrainingIssueSearch(discoveryMap, MaximumTrainingIssueDiscoveryDecisions, 0,
            activeTrainingIssue: false, directOfferAccepted: false);
        var activeIssueExempt = !ShouldStopUnproductiveTrainingIssueSearch(discoveryMap, MaximumTrainingIssueDiscoveryDecisions * 4, 0,
            activeTrainingIssue: true, directOfferAccepted: false);
        var acceptedOfferExempt = !ShouldStopUnproductiveTrainingIssueSearch(discoveryMap, MaximumTrainingIssueDiscoveryDecisions * 4, 0,
            activeTrainingIssue: false, directOfferAccepted: true);
        var movingMap = NativeState(null, null, new JsonArray(), moving: true);
        var movingNotCutOff = !ShouldStopUnproductiveTrainingIssueSearch(movingMap, MaximumTrainingIssueDiscoveryDecisions, 0,
            activeTrainingIssue: false, directOfferAccepted: false);
        if (!discoveryBelowLimit || !discoveryAtLimit || !activeIssueExempt || !acceptedOfferExempt || !movingNotCutOff)
            throw new AgentHostException("training-issue-self-test-discovery-budget-not-bounded", "Only an unproductive free-map search is capped after 32 local decisions; an accepted or active Native training Issue and an already-moving MainParty remain eligible to finish safely.");
        var discoveryLimitScenario = new { scenario = "training-issue-search-returns-to-parent-after-32-unproductive-decisions-but-does-not-cut-off-an-active-issue", maximumDiscoveryDecisions = MaximumTrainingIssueDiscoveryDecisions, passed = true };

        var villageMenu = NativeState("village", "village-a", new JsonArray(
            new JsonObject { ["id"] = "leave", ["available"] = true, ["enabled"] = true, ["isLeave"] = true }),
            new JsonArray(new JsonObject
            {
                ["heroId"] = "hero-training",
                ["questMarkers"] = new JsonArray(new JsonObject { ["type"] = "AvailableIssue", ["title"] = "为领主训练士兵" })
            }));
        var visibleCatalog = BuildActionCatalog(villageMenu, null, null, null, talkedToIssueGiver: false);
        if (!visibleCatalog.OfType<JsonObject>().Any(action => ReadString(action, "action") == "talkToSettlementHero" &&
                action["argumentValues"]?["HeroId"]?[0]?.GetValue<string>() == "hero-training") ||
            !visibleCatalog.OfType<JsonObject>().Any(action => ReadString(action, "action") == "menuSelect"))
            throw new AgentHostException("training-issue-self-test-visible-marker-catalog-failed", "The route must expose only the currently visible AvailableIssue giver and current Leave option from a settlement menu.");

        var hiddenGiver = NativeState("village", "village-a", new JsonArray(
            new JsonObject { ["id"] = "leave", ["available"] = true, ["enabled"] = true, ["isLeave"] = true }), new JsonArray());
        if (BuildActionCatalog(hiddenGiver, null, null, null, talkedToIssueGiver: false).OfType<JsonObject>()
            .Any(action => ReadString(action, "action") == "talkToSettlementHero"))
            throw new AgentHostException("training-issue-self-test-hidden-giver-leaked", "An Issue giver outside the current Native settlement overlay must not be contactable.");

        var unrelatedIssue = NativeState("town", "town-a", new JsonArray(
            new JsonObject { ["id"] = "leave", ["available"] = true, ["enabled"] = true, ["isLeave"] = true }), new JsonArray(
            new JsonObject
            {
                ["heroId"] = "hero-gang-issue",
                ["questMarkers"] = new JsonArray(new JsonObject { ["type"] = "AvailableIssue", ["title"] = "敌对帮派入侵波罗斯" })
            }));
        var unrelatedCatalog = BuildActionCatalog(unrelatedIssue, null, null, null, talkedToIssueGiver: false);
        if (unrelatedCatalog.OfType<JsonObject>().Any(action => ReadString(action, "action") == "talkToSettlementHero"))
            throw new AgentHostException("training-issue-self-test-unrelated-issue-giver-leaked", "The Gold retainer-training subgoal must not enter unrelated Issue conversations such as hostile-gang quests.");

        var mixedIssues = NativeState("town", "town-a", new JsonArray(
            new JsonObject { ["id"] = "leave", ["available"] = true, ["enabled"] = true, ["isLeave"] = true }), new JsonArray(
            new JsonObject
            {
                ["heroId"] = "hero-gang-issue",
                ["questMarkers"] = new JsonArray(new JsonObject { ["type"] = "AvailableIssue", ["title"] = "敌对帮派入侵波罗斯" })
            },
            new JsonObject
            {
                ["heroId"] = "hero-training",
                ["questMarkers"] = new JsonArray(new JsonObject { ["type"] = "AvailableIssue", ["title"] = "为卡诺洛斯的宇忒洛斯训练士兵" })
            }));
        var mixedCatalog = BuildActionCatalog(mixedIssues, null, null, null, talkedToIssueGiver: false);
        var mixedGivers = mixedCatalog.OfType<JsonObject>().FirstOrDefault(action => ReadString(action, "action") == "talkToSettlementHero")?
            ["argumentValues"]?["HeroId"] as JsonArray;
        if (mixedGivers?.Count != 1 || mixedGivers[0]?.GetValue<string>() != "hero-training")
            throw new AgentHostException("training-issue-self-test-mixed-issue-filter-failed", "Only a visible AvailableIssue marker whose Native title identifies retainer training may be contacted for the Gold training route.");

        var unavailableOfferConversation = new JsonObject
        {
            ["options"] = new JsonArray(
                new JsonObject { ["id"] = "issue_offer_player_accept_quest", ["textId"] = DirectTrainingResponseTextId, ["text"] = "I'll take your men.", ["clickable"] = false },
                new JsonObject { ["id"] = "issue_offer_player_accept_alternative", ["text"] = "Send a companion.", ["clickable"] = false },
                new JsonObject { ["id"] = "issue_offer_player_response_reject", ["text"] = "Sorry, not now.", ["clickable"] = true })
        };
        if (!IsFinalTrainingOfferWithoutDirectAcceptance(unavailableOfferConversation))
            throw new AgentHostException("training-issue-self-test-disabled-direct-offer-not-detected", "A visible final training offer with a disabled direct option must be recognized as currently infeasible, not retried indefinitely.");
        var returnFromUnavailableOffer = new JsonObject
        {
            ["options"] = new JsonArray(
                new JsonObject { ["id"] = "hero_give_issue", ["text"] = "I heard you have a problem.", ["clickable"] = true },
                new JsonObject { ["id"] = "player_is_leaving_neutral_or_friendly", ["text"] = "I must be going.", ["clickable"] = true })
        };
        var exitCatalog = BuildConversationCatalog(returnFromUnavailableOffer, talkedToIssueGiver: true,
            activeTrainingIssue: false, offerRefusalPendingExit: true, currentTrainingIssueGiverConversation: true);
        var exitOptionIds = exitCatalog.OfType<JsonObject>().FirstOrDefault(action => ReadString(action, "action") == "dialogueSelect")?
            ["argumentValues"]?["OptionId"] as JsonArray;
        if (exitOptionIds?.Count != 1 || exitOptionIds[0]?.GetValue<string>() != "player_is_leaving_neutral_or_friendly")
            throw new AgentHostException("training-issue-self-test-unavailable-offer-reopens-issue", "After rejecting a disabled direct offer, the Host must expose only the Native conversation exit and must not reopen the same issue.");

        var rawMapReceipt = new JsonObject
        {
            ["action"] = "mapSettlementTargets", ["status"] = "completed",
            ["data"] = new JsonObject
            {
                ["mapSettlementTargets"] = new JsonArray(
                    new JsonObject { ["id"] = "visited-village", ["name"] = "Visited" },
                    new JsonObject { ["id"] = "current-safe-town", ["name"] = "Current Safe Town" })
            }
        };
        var availableMapTargets = new JsonArray(new JsonObject { ["id"] = "current-safe-town", ["name"] = "Current Safe Town" });
        var filteredReceipt = BuildSafeModelPreviousReceipt(rawMapReceipt, availableMapTargets);
        var mapStateWithVisitedTarget = MapState(null);
        mapStateWithVisitedTarget["state"]!["nearbySettlements"] = new JsonArray(
            new JsonObject { ["id"] = "visited-village", ["name"] = "Visited", ["distance"] = 0 },
            new JsonObject { ["id"] = "current-safe-town", ["name"] = "Current Safe Town", ["distance"] = 3 });
        var filteredMapState = BuildModelState(mapStateWithVisitedTarget, availableMapTargets);
        if (filteredReceipt?["data"]?["mapSettlementTargets"]?.AsArray().Count != 1 ||
            filteredReceipt["data"]!["mapSettlementTargets"]![0]! ["id"]?.GetValue<string>() != "current-safe-town" ||
            rawMapReceipt["data"]!["mapSettlementTargets"]!.AsArray().Count != 2 ||
            filteredMapState["nearbySettlements"]?.AsArray().Count != 1 ||
            filteredMapState["nearbySettlements"]![0]!["id"]?.GetValue<string>() != "current-safe-town")
            throw new AgentHostException("training-issue-self-test-stale-settlement-target-leaked", "When selecting a move, the model must not receive visited settlement IDs that the current Native action catalog rejects.");

        var directAndAlternative = new JsonObject
        {
            ["state"] = new JsonObject
            {
                ["context"] = new JsonObject
                {
                    ["gameState"] = "MapState", ["menuId"] = "village",
                    ["conversation"] = new JsonObject
                    {
                        ["sentenceText"] = "Take the men and train them.",
                        ["options"] = new JsonArray(
                            new JsonObject { ["id"] = "issue_offer_player_accept_quest", ["textId"] = DirectTrainingResponseTextId, ["text"] = "I'll take your men into my party.", ["clickable"] = true },
                            new JsonObject { ["id"] = "issue_offer_player_accept_alternative", ["text"] = "Send a companion.", ["clickable"] = true },
                            new JsonObject { ["id"] = "issue_offer_player_accept_lord", ["text"] = "Use a lord solution.", ["clickable"] = true })
                    }
                }
            }
        };
        var contactedTrainingGiver = new HashSet<string>(StringComparer.Ordinal) { "hero-training" };
        directAndAlternative["state"]!["context"]!["conversation"]!["heroId"] = "hero-training";
        var offerCatalog = BuildActionCatalog(directAndAlternative, null, null, null, talkedToIssueGiver: true,
            contactedIssueGivers: contactedTrainingGiver);
        var offerIds = offerCatalog.OfType<JsonObject>().FirstOrDefault(action => ReadString(action, "action") == "dialogueSelect")?
            ["argumentValues"]?["OptionId"] as JsonArray;
        if (offerIds?.Count != 1 || offerIds[0]?.GetValue<string>() != "issue_offer_player_accept_quest")
            throw new AgentHostException("training-issue-self-test-alternative-outcome-leaked", "Only the current source-identified direct training Quest option may be selected; companion/lord alternatives are excluded.");

        var localizedDirectOption = (JsonObject)directAndAlternative.DeepClone();
        localizedDirectOption["state"]!["context"]!["conversation"]!["options"]![0]!["textId"] = "!";
        var localizedDirectState = localizedDirectOption["state"] as JsonObject
            ?? throw new AgentHostException("training-issue-self-test-localized-state-missing", "The current marked giver fixture must include its Native state.");
        var localizedDirectCatalog = BuildActionCatalog(localizedDirectOption, null, null, null, talkedToIssueGiver: true,
            contactedIssueGivers: contactedTrainingGiver);
        var localizedDirectDecision = new JsonObject
        {
            ["action"] = "dialogueSelect",
            ["arguments"] = new JsonObject { ["OptionId"] = "issue_offer_player_accept_quest" }
        };
        if (!localizedDirectCatalog.OfType<JsonObject>().Any(action =>
                (action["argumentValues"]?["OptionId"] as JsonArray)?.Any(id => id?.GetValue<string>() == "issue_offer_player_accept_quest") == true) ||
            !TryResolveDecision(localizedDirectDecision, localizedDirectCatalog, localizedDirectState, null, null,
                talkedToIssueGiver: true, activeTrainingIssue: false, out var localizedDirectAction, out _, out _, contactedTrainingGiver) ||
            localizedDirectAction != "dialogueSelect")
            throw new AgentHostException("training-issue-self-test-localized-direct-offer-hidden", "The stable current issue-offer option ID and known marked training giver must remain actionable when Native's localized TextObject has no stable ID string.");

        var upgradeReceipt = new JsonObject
        {
            ["status"] = "completed", ["action"] = "partyUpgradeOptions",
            ["data"] = new JsonObject
            {
                ["options"] = new JsonArray(
                    new JsonObject
                    {
                        ["troopId"] = BorrowedTroopId, ["troopName"] = "Borrowed Troop", ["currentCount"] = 3,
                        ["upgradeTargets"] = new JsonArray(new JsonObject
                        {
                            ["targetIndex"] = 0, ["targetId"] = VeteranBorrowedTroopId, ["targetName"] = "Veteran Borrowed Troop",
                            ["availableCount"] = 1, ["isAvailable"] = true, ["isInsufficient"] = false,
                            ["experienceCostPerUnit"] = 20, ["goldCostPerUnit"] = 0,
                            ["hasItemRequirement"] = false, ["itemRequirementMet"] = true,
                            ["hasPerkRequirement"] = false, ["isPerkRequirementMet"] = true
                        })
                    },
                    new JsonObject
                    {
                        ["troopId"] = "imperial_recruit", ["troopName"] = "Imperial Recruit", ["currentCount"] = 2,
                        ["upgradeTargets"] = new JsonArray(new JsonObject
                        {
                            ["targetIndex"] = 0, ["targetId"] = "imperial_vigla_recruit", ["targetName"] = "Imperial Vigla Recruit",
                            ["availableCount"] = 2, ["isAvailable"] = true, ["isInsufficient"] = false,
                            ["experienceCostPerUnit"] = 20, ["goldCostPerUnit"] = 5,
                            ["hasItemRequirement"] = false, ["itemRequirementMet"] = true,
                            ["hasPerkRequirement"] = false, ["isPerkRequirementMet"] = true
                        })
                    })
            }
        };
        var upgradeCatalog = BuildActionCatalog(MapState(null), upgradeReceipt, upgradeReceipt, null, talkedToIssueGiver: true, activeTrainingIssue: true);
        var upgradeAction = upgradeCatalog.OfType<JsonObject>().FirstOrDefault(action => ReadString(action, "action") == "upgradeTroop");
        if (upgradeAction is null || upgradeAction["argumentValues"]?["TroopId"]?[0]?.GetValue<string>() != BorrowedTroopId ||
            upgradeAction["argumentValues"]?["UpgradeTargetIndex"]?[0]?.GetValue<int>() != 0 ||
            upgradeCatalog.OfType<JsonObject>().Any(action => ReadString(action, "action") == "partyUpgradeOptions"))
            throw new AgentHostException("training-issue-self-test-upgrade-scope-failed", "Only the currently observed borrowed issue troop may be upgraded toward its current veteran target; ordinary player troops must not enter this task-specific catalog.");

        var noUpgradeReceipt = new JsonObject
        {
            ["status"] = "completed", ["action"] = "partyUpgradeOptions",
            ["data"] = new JsonObject { ["options"] = new JsonArray(new JsonObject { ["troopId"] = BorrowedTroopId, ["upgradeTargets"] = new JsonArray() }) }
        };
        var mapTargetsReceipt = new JsonObject { ["status"] = "completed", ["action"] = "mapSettlementTargets" };
        var cachedNoUpgrade = UpdateUpgradeOptionsReceipt(null, "partyUpgradeOptions", noUpgradeReceipt, nativeCompleted: true, activeTrainingIssue: true);
        var retainedNoUpgrade = UpdateUpgradeOptionsReceipt(cachedNoUpgrade, "mapSettlementTargets", mapTargetsReceipt, nativeCompleted: true, activeTrainingIssue: true);
        var safeTargets = new JsonArray(new JsonObject { ["id"] = "safe-town", ["name"] = "Safe Town" });
        var afterMapQueryCatalog = BuildActionCatalog(MapState(null), noUpgradeReceipt, cachedNoUpgrade, visibleSafeTargets: null,
            talkedToIssueGiver: true, activeTrainingIssue: true);
        var afterMapQueryAndCachedOptionsCatalog = BuildActionCatalog(MapState(null), mapTargetsReceipt, retainedNoUpgrade, safeTargets,
            talkedToIssueGiver: true, activeTrainingIssue: true);
        var afterMoveCache = UpdateUpgradeOptionsReceipt(retainedNoUpgrade, "move", new JsonObject { ["status"] = "completed" }, nativeCompleted: true, activeTrainingIssue: true);
        if (ReadString(afterMapQueryCatalog.FirstOrDefault() as JsonObject, "action") != "mapSettlementTargets" ||
            ReadString(afterMapQueryAndCachedOptionsCatalog.FirstOrDefault() as JsonObject, "action") != "move" ||
            afterMapQueryAndCachedOptionsCatalog.OfType<JsonObject>().Any(action => ReadString(action, "action") == "partyUpgradeOptions") ||
            retainedNoUpgrade is null || afterMoveCache is not null)
            throw new AgentHostException("training-issue-self-test-no-upgrade-query-loop", "A completed no-upgrade roster read must remain cached through target lookup, allow a current safe move, and refresh only after movement or troop-upgrade change.");
        var noTimeControls = BuildControlCatalog(MapState(null, moving: true), activeTrainingIssue: false);
        var mapDialogueNative = MapState(null, moving: true);
        var mapDialogueState = mapDialogueNative["state"] as JsonObject ?? new JsonObject();
        mapDialogueState["context"]!["conversation"] = new JsonObject
        {
            ["characterId"] = "notable-other",
            ["sentenceText"] = "A different current Native map conversation.",
            ["options"] = new JsonArray(
                new JsonObject { ["id"] = "map-safe-reply", ["text"] = "A visible reply.", ["clickable"] = true },
                new JsonObject { ["id"] = "map-hidden-reply", ["text"] = "Unavailable reply.", ["clickable"] = false },
                new JsonObject { ["id"] = "issue_offer_player_accept_quest", ["textId"] = DirectTrainingResponseTextId, ["text"] = "Accept this unrelated issue.", ["clickable"] = true })
        };
        var mapDialogueCatalog = BuildActionCatalog(mapDialogueNative, null, null, null, talkedToIssueGiver: false);
        var mapDialogueIds = mapDialogueCatalog.OfType<JsonObject>().SingleOrDefault(action => ReadString(action, "action") == "dialogueSelect")?
            ["argumentValues"]?["OptionId"] as JsonArray;
        if (mapDialogueCatalog.Count != 1 || mapDialogueIds?.Count != 1 || mapDialogueIds[0]?.GetValue<string>() != "map-safe-reply" ||
            BuildControlCatalog(mapDialogueNative, activeTrainingIssue: false).OfType<JsonValue>().Any(control => control.GetValue<string>() == "observeAgain") ||
            !TryResolveDecision(new JsonObject { ["action"] = "dialogueSelect", ["arguments"] = new JsonObject { ["OptionId"] = "map-safe-reply" } },
                mapDialogueCatalog, mapDialogueState, null, null, false, false, out var mapDialogueAction, out var mapDialogueArguments, out _, new HashSet<string>(StringComparer.Ordinal)) ||
            mapDialogueAction != "dialogueSelect" || mapDialogueArguments?["optionId"]?.GetValue<string>() != "map-safe-reply" ||
            TryResolveDecision(new JsonObject { ["action"] = "dialogueSelect", ["arguments"] = new JsonObject { ["OptionId"] = "issue_offer_player_accept_quest" } },
                mapDialogueCatalog, mapDialogueState, null, null, false, false, out _, out _, out _, new HashSet<string>(StringComparer.Ordinal)))
            throw new AgentHostException("training-issue-self-test-map-dialogue-scope-failed", "A non-issue MapState conversation during movement must expose only current safe clickable options, hide direct quest acceptance, reject stale options, and suppress observeAgain.");
        var contactedGiverInterrupt = MapState(null, moving: true);
        contactedGiverInterrupt["state"]!["context"]!["conversation"] = new JsonObject
        {
            ["characterId"] = "notable-other", ["sentenceText"] = "A different conversation after talking to the issue giver.",
            ["options"] = new JsonArray(new JsonObject { ["id"] = "other-safe-reply", ["text"] = "A visible reply.", ["clickable"] = true })
        };
        var contactedGiverCatalog = BuildActionCatalog(contactedGiverInterrupt, null, null, null, talkedToIssueGiver: true,
            contactedIssueGivers: contactedTrainingGiver);
        var contactedGiverOptions = contactedGiverCatalog.OfType<JsonObject>().SingleOrDefault(action => ReadString(action, "action") == "dialogueSelect")?
            ["argumentValues"]?["OptionId"] as JsonArray;
        if (contactedGiverCatalog.Count != 1 || contactedGiverOptions?.Count != 1 ||
            contactedGiverOptions[0]?.GetValue<string>() != "other-safe-reply")
            throw new AgentHostException("training-issue-self-test-unrelated-map-conversation-not-isolated", "After speaking with an Issue giver, a different current MapState conversation must not inherit the Issue acceptance catalog.");
        var mapDialogueNoChoiceNative = MapState(null, moving: true);
        var mapDialogueNoChoiceState = mapDialogueNoChoiceNative["state"] as JsonObject ?? new JsonObject();
        mapDialogueNoChoiceState["context"]!["conversation"] = new JsonObject
        {
            ["characterId"] = "notable-other", ["sentenceText"] = "A no-choice map text line.", ["options"] = new JsonArray()
        };
        var mapDialogueContinueCatalog = BuildActionCatalog(mapDialogueNoChoiceNative, null, null, null, talkedToIssueGiver: false);
        if (mapDialogueContinueCatalog.Count != 1 || ReadString(mapDialogueContinueCatalog[0] as JsonObject, "action") != "dialogueContinue" ||
            !TryResolveDecision(new JsonObject { ["action"] = "dialogueContinue", ["arguments"] = new JsonObject() },
                mapDialogueContinueCatalog, mapDialogueNoChoiceState, null, null, false, false, out var mapDialogueContinueAction, out _, out _, new HashSet<string>(StringComparer.Ordinal)) ||
            mapDialogueContinueAction != "dialogueContinue")
            throw new AgentHostException("training-issue-self-test-map-dialogue-continue-scope-failed", "A no-choice map conversation must expose only the current Native Continue action before the training route resumes.");
        var visibleBanditMap = MapState(null);
        visibleBanditMap["state"]!["nearbyParties"] = new JsonArray(new JsonObject { ["id"] = "bandit-a", ["type"] = "bandit", ["hostile"] = true });
        var trainingBattleControl = BuildControlCatalog(visibleBanditMap, activeTrainingIssue: true, upgradeOptionsKnown: true, currentlyUpgradable: false);
        var blockedBattleControl = BuildControlCatalog(visibleBanditMap, activeTrainingIssue: true, upgradeOptionsKnown: true, currentlyUpgradable: true);
        var nonTrainingBattleControl = BuildControlCatalog(visibleBanditMap, activeTrainingIssue: false, upgradeOptionsKnown: true, currentlyUpgradable: false);
        if (noTimeControls.Any(control => control?.GetValue<string>() is "timeControl" or "setTime" or "advanceTime") ||
            !trainingBattleControl.OfType<JsonValue>().Any(control => control.GetValue<string>() == "resolveVisibleBandit") ||
            blockedBattleControl.OfType<JsonValue>().Any(control => control.GetValue<string>() == "resolveVisibleBandit") ||
            nonTrainingBattleControl.OfType<JsonValue>().Any(control => control.GetValue<string>() == "resolveVisibleBandit"))
            throw new AgentHostException("training-issue-self-test-hidden-clock-control", "Ordinary map movement and bounded Host observations must not introduce an implicit or unrelated clock command.");

        var returnInquiry = new JsonObject
        {
            ["supported"] = true, ["kind"] = "YesNoInquiry",
            ["text"] = "你部队中的借调士兵均已经验丰富。你可以将他们调回给领主。",
            ["affirmative"] = new JsonObject { ["visible"] = true, ["enabled"] = true, ["text"] = "将士兵调回" },
            ["negative"] = new JsonObject { ["visible"] = true, ["enabled"] = true, ["text"] = "扣留他们" }
        };
        var unrelatedInquiry = new JsonObject
        {
            ["supported"] = true, ["kind"] = "YesNoInquiry", ["text"] = "A different native campaign prompt.",
            ["affirmative"] = new JsonObject { ["visible"] = true, ["enabled"] = true, ["text"] = "Yes" },
            ["negative"] = new JsonObject { ["visible"] = true, ["enabled"] = true, ["text"] = "No" }
        };
        if (!IsTrainingReturnInquiry(returnInquiry) || IsTrainingReturnInquiry(unrelatedInquiry))
            throw new AgentHostException("training-issue-self-test-inquiry-scope-failed", "Only the visible Native return-borrowed-troops prompt may enter the training Issue completion response path.");

        return [
            discoveryLimitScenario,
            new { scenario = "training-issue-targets-only-current-visible-available-issue-givers", passed = true },
            new { scenario = "training-issue-movement-observation-hides-settlement-targets-rejected-by-current-catalog", passed = true },
            new { scenario = "training-issue-accepts-only-the-source-identified-direct-quest-option", passed = true },
            new { scenario = "training-direct-offer-uses-current-giver-and-clickable-option-id-with-unassigned-local-text", passed = true },
            new { scenario = "training-issue-upgrade-catalog-is-limited-to-current-borrowed-retainers", passed = true },
            new { scenario = "training-issue-caches-no-upgrade-query-across-map-target-read-and-refreshes-after-move", passed = true },
            new { scenario = "training-issue-resolves-unrelated-current-map-conversation-without-quest-acceptance-or-waiting", passed = true },
            new { scenario = "training-issue-movement-observation-does-not-add-clock-controls", passed = true }
        ];
    }

    internal static async Task<IReadOnlyList<object>> RunMapDialogueTransportSelfTestsAsync()
    {
        var client = new FakeMapDialogueNativeClient();
        var provider = new FakeMapDialogueDecisionProvider();
        using var request = JsonDocument.Parse(JsonSerializer.Serialize(new
        {
            runId = "training-issue-map-dialogue-self-test",
            goal = "Earn original EYC Gold through the Native retainer-training Issue.",
            maxDecisions = 4,
            maxElapsedSeconds = 10,
            allowedActionNames = AgentHostCampaignLoop.AllSupportedActions.ToArray()
        }));
        var result = await RunAsync(request.RootElement, client, client, provider, CancellationToken.None);
        if (ReadString(result, "status") != "failed" ||
            ReadString(result, "termination") != "training-issue-interrupted-by-encounter" ||
            ReadInt(result, "decisions") != 1 || ReadInt(result, "actionsExecuted") != 1 ||
            ReadInt(result, "explicitClockActionCount") != 0 || provider.Calls != 1 || !provider.ReceivedOnlyCurrentSafeMapReply ||
            client.Actions.Count != 1 || client.Actions[0].Action != "dialogueSelect" || client.Actions[0].OptionId != "map-safe-reply")
            throw new AgentHostException("training-issue-loop-map-dialogue-transport-failed",
                "The complete Native training-issue loop must send exactly one current safe map reply, suppress the unrelated quest acceptance and observeAgain, then yield an encounter to the parent without clock actions.");

        return [new { scenario = "training-issue-map-dialogue-loop-selects-only-current-safe-reply-then-yields-encounter", passed = true }];
    }


    internal static async Task<JsonObject> RunAsync(
        JsonElement request,
        IAgentHostEstablishClanTrainingIssueNativeClient client,
        IAgentHostBattleSimulationNativeClient battleClient,
        IAgentHostDecisionProvider provider,
        CancellationToken cancellationToken,
        int priorDecisions = 0,
        long priorPromptTokens = 0,
        long priorCompletionTokens = 0,
        JsonArray? priorTrace = null,
        JsonArray? priorProviderRouteHistory = null)
    {
        var runId = ReadString(request, "runId") ?? Guid.NewGuid().ToString("N");
        var goal = ReadString(request, "goal") ?? "Earn original EYC Gold through the visible Native retainer-training Issue.";
        var maxDecisions = Math.Clamp(ReadInt(request, "maxDecisions", AgentHostCampaignLoop.MaxCumulativeDecisions), 1, AgentHostCampaignLoop.MaxCumulativeDecisions);
        var maxElapsedSeconds = Math.Clamp(ReadInt(request, "maxElapsedSeconds", 86400), 1, 86400);
        var allowedNames = request.TryGetProperty("allowedActionNames", out var names) && names.ValueKind == JsonValueKind.Array
            ? names.EnumerateArray().Where(value => value.ValueKind == JsonValueKind.String).Select(value => value.GetString()!).ToHashSet(StringComparer.Ordinal)
            : new HashSet<string>(StringComparer.Ordinal);
        if (!allowedNames.SetEquals(AgentHostCampaignLoop.AllSupportedActions))
            throw new AgentHostException("training-issue-request-action-set-invalid", "The training Issue route requires the exact reviewed EYC Native action superset.");

        using var elapsed = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        elapsed.CancelAfter(TimeSpan.FromSeconds(maxElapsedSeconds));
        var trace = priorTrace?.DeepClone() as JsonArray ?? new JsonArray();
        var routes = priorProviderRouteHistory?.DeepClone() as JsonArray ?? new JsonArray();
        var decisions = priorDecisions;
        var promptTokens = priorPromptTokens;
        var completionTokens = priorCompletionTokens;
        var actionsExecuted = 0;
        var rejected = 0;
        var processId = -1;
        JsonObject? initialNative = null;
        JsonObject? currentNative = null;
        JsonObject? previousReceipt = null;
        JsonObject? feedback = null;
        JsonObject? upgradeOptionsReceipt = null;
        JsonArray? visibleSafeTargets = null;
        var visitedSettlements = new HashSet<string>(StringComparer.Ordinal);
        var contactedIssueGivers = new HashSet<string>(StringComparer.Ordinal);
        var initialIssueIds = new HashSet<string>(StringComparer.Ordinal);
        string? trackedIssueQuestId = null;
        string? issueGiverSettlementId = null;
        var talkedToIssueGiver = false;
        var directOfferAccepted = false;
        var offerRefusalPendingExit = false;
        string? directOfferExitFailureCode = null;
        JsonObject? issueDetails = null;
        JsonObject? eycJournalBefore = null;
        JsonObject? eycJournalAfter = null;
        var goldDelta = double.NaN;
        var explicitClockActions = 0;
        string? failure = null;
        string? failureCode = null;
        string? termination = null;

        try
        {
            await provider.CheckConfiguredModelAsync(elapsed.Token);
            using (var initial = await client.ReadStateAsync(elapsed.Token)) initialNative = ParseObject(initial.RootElement);
            currentNative = initialNative.DeepClone() as JsonObject ?? throw new AgentHostException("training-issue-initial-state-invalid", "Native returned no initial Campaign state.");
            processId = ReadInt(currentNative, "processId", -1);
            if (processId <= 0) throw new AgentHostException("training-issue-process-id-invalid", "Native did not identify the current Bannerlord process.");
            if (!HasActiveEycQuest(currentNative))
                throw new AgentHostException("training-issue-active-eyc-required", "The training Issue income route requires the exact active original Establish Your Clan quest.");
            eycJournalBefore = await ReadEycJournalAsync(client, elapsed.Token);
            eycJournalAfter = (JsonObject)eycJournalBefore.DeepClone();
            if (IsGoldObjectiveMet(eycJournalBefore)) return BuildResult("completed", "eyc-gold-journal-already-met", null, null);
            var initialState = currentNative["state"] as JsonObject ?? new JsonObject();
            foreach (var quest in (initialState["quests"] as JsonArray)?.OfType<JsonObject>() ?? Enumerable.Empty<JsonObject>())
            {
                var id = ReadString(quest, "id");
                if (!string.IsNullOrWhiteSpace(id) && id.StartsWith("issue_", StringComparison.Ordinal)) initialIssueIds.Add(id);
            }
            trackedIssueQuestId = FindTrainingIssueQuestId(initialState);

            for (var localIndex = 1; decisions < maxDecisions; localIndex++)
            {
                elapsed.Token.ThrowIfCancellationRequested();
                if (localIndex > 1)
                {
                    using var refreshed = await client.ReadStateAsync(elapsed.Token);
                    currentNative = ParseObject(refreshed.RootElement);
                }
                if (ReadInt(currentNative, "processId", -1) != processId)
                    throw new AgentHostException("training-issue-native-process-changed", "The training Issue route received state from a different Bannerlord process.");
                var state = currentNative?["state"] as JsonObject ?? throw new AgentHostException("training-issue-native-state-missing", "Native returned no Campaign state.");
                if (!HasActiveEycQuest(currentNative!))
                {
                    failure = "The original Establish Your Clan quest is no longer active; this route cannot claim its Journal progress.";
                    failureCode = "training-issue-eyc-not-active";
                    termination = failureCode;
                    break;
                }

                eycJournalAfter = await ReadEycJournalAsync(client, elapsed.Token);
                if (GoldCurrent(eycJournalAfter) > GoldCurrent(eycJournalBefore) || IsGoldObjectiveMet(eycJournalAfter))
                {
                    termination = IsGoldObjectiveMet(eycJournalAfter) ? "eyc-gold-journal-target-met" : "native-training-issue-increased-eyc-gold-journal";
                    return BuildResult("completed", termination, null, null);
                }

                var activeIssueIds = (state["quests"] as JsonArray)?.OfType<JsonObject>()
                    .Where(quest => (ReadString(quest, "id") ?? string.Empty).StartsWith("issue_", StringComparison.Ordinal))
                    .Select(quest => ReadString(quest, "id")!).ToHashSet(StringComparer.Ordinal) ?? new HashSet<string>(StringComparer.Ordinal);
                trackedIssueQuestId = FindTrainingIssueQuestId(state) ??
                    (directOfferAccepted ? activeIssueIds.Except(initialIssueIds, StringComparer.Ordinal).FirstOrDefault() : trackedIssueQuestId);
                var activeTrainingIssue = !string.IsNullOrWhiteSpace(trackedIssueQuestId) && activeIssueIds.Contains(trackedIssueQuestId);
                if (activeTrainingIssue)
                {
                    using var issueReceipt = await client.ReadQuestDetailsAsync(trackedIssueQuestId!, elapsed.Token);
                    issueDetails = ParseObject(issueReceipt.RootElement);
                    if (ReadString(issueDetails, "status") != "completed" || issueDetails["data"] is not JsonObject issueData ||
                        ReadString(issueData, "questId") != trackedIssueQuestId)
                        throw new AgentHostException("training-issue-details-unavailable", "The active Native training Issue did not return its current visible Journal details.");
                    var title = ReadString(issueData, "title") ?? string.Empty;
                    if (!IsTrainingIssueTitle(title) && !directOfferAccepted)
                    {
                        failure = "The currently active Issue does not match the Native training task this route supports.";
                        failureCode = "training-issue-active-issue-unsupported";
                        termination = failureCode;
                        break;
                    }
                }
                else if (directOfferAccepted)
                {
                    failure = "The direct training Issue offer was accepted, but the Native active Issue did not appear in the current Journal.";
                    failureCode = "training-issue-acceptance-not-observed";
                    termination = failureCode;
                    break;
                }
                else
                {
                    trackedIssueQuestId = null;
                    issueDetails = null;
                }

                if (ShouldStopUnproductiveTrainingIssueSearch(currentNative!, decisions, priorDecisions, activeTrainingIssue, directOfferAccepted))
                {
                    failure = $"No visible retainer-training Issue became active within the bounded {MaximumTrainingIssueDiscoveryDecisions}-decision discovery budget; returning free Map control to the Gold objective parent.";
                    failureCode = "training-issue-search-budget-exhausted";
                    termination = failureCode;
                    trace.Add(new JsonObject
                    {
                        ["stage"] = "native-training-issue-discovery-budget-exhausted",
                        ["maxLocalDecisions"] = MaximumTrainingIssueDiscoveryDecisions,
                        ["localDecisionsUsed"] = decisions - priorDecisions,
                        ["settlementSearchCount"] = visitedSettlements.Count,
                        ["currentSettlementId"] = ReadString(state["location"] as JsonObject, "currentSettlementId"),
                        ["activeTrainingIssue"] = activeTrainingIssue,
                        ["nativeStateSummary"] = AgentHostHarnessProgressTrace.BuildNativeStateSummary(state)
                    });
                    break;
                }

                var context = state["context"] as JsonObject;
                var currentConversation = context?["conversation"] as JsonObject;
                if (offerRefusalPendingExit && currentConversation is null && !activeTrainingIssue)
                {
                    failureCode = directOfferExitFailureCode ?? "training-issue-direct-offer-unavailable";
                    failure = failureCode == "training-issue-direct-offer-rejected"
                        ? "The real model declined the current direct Native training offer; the Host closed the dialogue and will not reopen the same giver."
                        : "The direct Native training offer was not currently clickable; the Host closed the dialogue and will not retry the same giver.";
                    termination = failureCode;
                    break;
                }
                if (AgentHostCampaignStateFacts.IsActiveEncounter(state) && !AgentHostCampaignStateFacts.IsNativeLocationMenu(state))
                {
                    failure = "A Native encounter interrupted the training Issue; the parent Campaign loop must resolve the currently observed encounter before the Issue route resumes.";
                    failureCode = "training-issue-interrupted-by-encounter";
                    termination = failureCode;
                    break;
                }
                if (ReadBoolean(context, "inquiryOpen"))
                {
                    var currentInquiry = context?["inquiry"] as JsonObject;
                    if (!activeTrainingIssue || !IsTrainingReturnInquiry(currentInquiry))
                    {
                        failure = "A Native inquiry was not the visible return-borrowed-troops prompt for the active training Issue; no response was guessed.";
                        failureCode = "training-issue-unowned-inquiry";
                        termination = failureCode;
                        break;
                    }
                    var inquiryResult = await AgentHostNativeInquiryResolution.RunAsync(client, client, provider, elapsed.Token,
                        runId + "-training-return", "Return the currently trained borrowed troops to the Issue giver to finish the active Native training quest and claim its reward.");
                    decisions += ReadInt(inquiryResult, "decisions", 0);
                    promptTokens += ReadLong(inquiryResult, "promptTokens", 0);
                    completionTokens += ReadLong(inquiryResult, "completionTokens", 0);
                    actionsExecuted += ReadInt(inquiryResult, "actionsExecuted", 0);
                    AppendRoutes(routes, inquiryResult["providerRouteHistory"] as JsonArray);
                    trace.Add(new JsonObject { ["stage"] = "native-training-return-inquiry", ["result"] = inquiryResult.DeepClone() });
                    if (ReadString(inquiryResult, "status") != "resolved")
                    {
                        failure = ReadString(inquiryResult, "failure") ?? "The current Native training return inquiry did not resolve.";
                        failureCode = ReadString(inquiryResult, "failureCode") ?? "training-issue-return-inquiry-failed";
                        termination = "training-issue-return-inquiry-failed";
                        break;
                    }
                    using (var afterInquiry = await client.ReadStateAsync(elapsed.Token)) currentNative = ParseObject(afterInquiry.RootElement);
                    eycJournalAfter = await ReadEycJournalAsync(client, elapsed.Token);
                    if (GoldCurrent(eycJournalAfter) > GoldCurrent(eycJournalBefore))
                    {
                        termination = "native-training-issue-returned-borrowed-troops-and-increased-eyc-gold";
                        return BuildResult("completed", termination, null, null);
                    }
                    failure = "The Native return inquiry resolved, but the original EYC Gold Journal did not increase.";
                    failureCode = "training-issue-gold-journal-did-not-increase";
                    termination = failureCode;
                    break;
                }

                if (!activeTrainingIssue && !talkedToIssueGiver && issueGiverSettlementId is null &&
                    string.Equals(ReadString(context, "menuId"), "encounter", StringComparison.Ordinal))
                {
                    failure = "A hostile encounter interrupted training-issue discovery; the parent Campaign loop must resolve it before this route resumes.";
                    failureCode = "training-issue-interrupted-by-encounter";
                    termination = failureCode;
                    break;
                }

                var catalog = BuildActionCatalog(currentNative!, previousReceipt, upgradeOptionsReceipt, visibleSafeTargets,
                    talkedToIssueGiver, activeTrainingIssue, contactedIssueGivers, offerRefusalPendingExit);
                var upgradeOptionsKnown = ReadString(previousReceipt, "action") == "partyUpgradeOptions" && ReadString(previousReceipt, "status") == "completed";
                var currentlyUpgradable = upgradeOptionsKnown && HasAvailableBorrowedUpgrade(upgradeOptionsReceipt ?? previousReceipt);
                var controls = BuildControlCatalog(currentNative!, activeTrainingIssue, upgradeOptionsKnown, currentlyUpgradable);
                if (catalog.Count == 0 && controls.Count == 0)
                {
                    failure = activeTrainingIssue
                        ? "The current Native training Issue has no supported action in this state; no roster, clock or quest value was modified by the Host."
                        : "No currently visible settlement Issue giver or safe recovery action is available.";
                    failureCode = activeTrainingIssue ? "training-issue-no-current-native-action" : "training-issue-no-visible-direct-offer";
                    termination = failureCode;
                    break;
                }

                var modelPreviousReceipt = BuildSafeModelPreviousReceipt(previousReceipt, visibleSafeTargets);
                var observation = BuildObservation(currentNative!, eycJournalAfter, issueDetails, trackedIssueQuestId,
                    upgradeOptionsReceipt, modelPreviousReceipt, feedback, visibleSafeTargets);
                var decisionIndex = decisions + 1;
                var modelRequest = BuildDecisionRequest(runId, decisionIndex, goal, observation, modelPreviousReceipt, feedback, catalog, controls);
                ProviderDecisionResult providerResult;
                try
                {
                    providerResult = await AgentHostDecisionCycle.DecideEstablishClanTrainingIssueAsync(provider, modelRequest, elapsed.Token);
                    decisions++;
                    AddProviderRoute(routes, provider, providerResult, decisions, ref promptTokens, ref completionTokens);
                }
                catch (Exception exception)
                {
                    failure = exception is AgentHostException hostException ? hostException.Message : exception.GetType().Name;
                    failureCode = exception is AgentHostException typed ? typed.Code : null;
                    termination = "training-issue-provider-failed";
                    trace.Add(BuildDecisionStep(decisionIndex, modelRequest, null, feedback, null, false));
                    break;
                }

                var decision = JsonNode.Parse(providerResult.Decision.ToJsonString())?.AsObject() ?? new JsonObject();
                if (ReadBoolean(decision, "observeAgain"))
                {
                    var waitSeconds = ReadInt(decision, "waitSeconds", 0);
                    if (!controls.OfType<JsonValue>().Any(value => value.GetValue<string>() == "observeAgain") || waitSeconds is < 1 or > 10)
                    {
                        feedback = new JsonObject { ["kind"] = "control-rejected-before-wait", ["nativeActionSent"] = false };
                        trace.Add(BuildDecisionStep(decisionIndex, modelRequest, decision, feedback, null, false));
                        continue;
                    }
                    await Task.Delay(TimeSpan.FromSeconds(waitSeconds), elapsed.Token);
                    trace.Add(BuildDecisionStep(decisionIndex, modelRequest, decision, null,
                        new JsonObject { ["kind"] = "bounded-host-observe-again", ["waitSeconds"] = waitSeconds }, false));
                    feedback = null;
                    continue;
                }

                if (!TryResolveDecision(decision, catalog, state, visibleSafeTargets, upgradeOptionsReceipt,
                    talkedToIssueGiver, activeTrainingIssue, out var action, out var arguments, out var rejection, contactedIssueGivers))
                {
                    rejected++;
                    feedback = new JsonObject { ["kind"] = "decision-rejected-before-native", ["message"] = rejection, ["nativeActionSent"] = false };
                    trace.Add(BuildDecisionStep(decisionIndex, modelRequest, decision, feedback, null, false));
                    if (rejected > MaxRejectedDecisions)
                    {
                        failure = "The model repeatedly selected a Native Issue action outside the current visible catalog.";
                        failureCode = "training-issue-action-rejection-limit";
                        termination = failureCode;
                        break;
                    }
                    continue;
                }
                rejected = 0;

                if (action == "battleSimulation")
                {
                    var battleRequestNode = JsonNode.Parse(request.GetRawText())?.AsObject() ?? new JsonObject();
                    battleRequestNode["goal"] = "Train the current borrowed retainers for the active Native Landlord Training Issue. Resolve one currently visible weak hostile Bandit through Native BattleSimulation to earn experience, then return to the current Issue Journal; do not enter a realtime Mission or alter the clock.";
                    using var battleRequest = JsonDocument.Parse(battleRequestNode.ToJsonString());
                    var battle = await AgentHostBattleSimulationLoop.RunAsync(battleRequest.RootElement, battleClient, provider, elapsed.Token,
                        priorDecisions: decisions, priorPromptTokens: promptTokens, priorCompletionTokens: completionTokens,
                        priorTrace: trace, priorProviderRouteHistory: routes, recoverPlayerCaptivity: true);
                    AgentHostHarnessProgressTrace.RecordObjectiveSubflowResult("trainingIssueBattleSimulation", battle);
                    decisions = ReadInt(battle, "decisions", decisions);
                    promptTokens = ReadLong(battle, "promptTokens", promptTokens);
                    completionTokens = ReadLong(battle, "completionTokens", completionTokens);
                    actionsExecuted += ReadInt(battle, "actionsExecuted", 0);
                    trace = battle["trace"]?.DeepClone() as JsonArray ?? trace;
                    routes = battle["providerRouteHistory"]?.DeepClone() as JsonArray ?? routes;
                    if (ReadString(battle, "status") != "completed")
                    {
                        failure = ReadString(battle, "failure") ?? "The Native BattleSimulation did not return to a verified Campaign Map.";
                        failureCode = ReadString(battle, "failureCode") ?? "training-issue-battle-subflow-failed";
                        termination = "training-issue-battle-subflow-failed";
                        break;
                    }
                    using (var afterBattle = await client.ReadStateAsync(elapsed.Token)) currentNative = ParseObject(afterBattle.RootElement);
                    previousReceipt = new JsonObject { ["action"] = "battleSimulation", ["status"] = "completed", ["playerOutcome"] = ReadString(battle, "playerOutcome") };
                    upgradeOptionsReceipt = null;
                    feedback = null;
                    continue;
                }

                var nativeArguments = ToNativeArguments(action!, arguments!);
                JsonObject nativeReceipt;
                try
                {
                    using var response = await client.ExecuteTrainingIssueActionAsync(action!, nativeArguments, elapsed.Token);
                    nativeReceipt = ParseObject(response.RootElement);
                }
                catch (AgentHostException exception)
                {
                    feedback = new JsonObject { ["kind"] = "native-action-rejected-before-state-change", ["failureCode"] = exception.Code, ["message"] = exception.Message };
                    trace.Add(BuildDecisionStep(decisionIndex, modelRequest, decision, feedback, null, false));
                    if (++rejected > MaxRejectedDecisions)
                    {
                        failure = exception.Message;
                        failureCode = exception.Code;
                        termination = "training-issue-native-rejection-limit";
                        break;
                    }
                    continue;
                }
                if (ReadInt(nativeReceipt, "processId", processId) != processId)
                    throw new AgentHostException("training-issue-native-process-mismatch", "The Native Issue action receipt came from a different Bannerlord process.");
                var nativeCompleted = ReadString(nativeReceipt, "status") == "completed";
                if (nativeCompleted) actionsExecuted++;
                var currentOptionId = ReadString(arguments, "optionId");
                var directOfferWasClickable = IsTrainingDirectOfferClickable(state["context"]?["conversation"] as JsonObject);
                if (action == "talkToSettlementHero" && nativeCompleted)
                {
                    talkedToIssueGiver = true;
                    if (ReadString(arguments, "heroId") is string heroId && !string.IsNullOrWhiteSpace(heroId)) contactedIssueGivers.Add(heroId);
                    issueGiverSettlementId = ReadString(state["location"] as JsonObject, "currentSettlementId");
                }
                if (action == "dialogueSelect" && nativeCompleted && currentOptionId == "issue_offer_player_accept_quest") directOfferAccepted = true;
                if (action == "dialogueSelect" && nativeCompleted && currentOptionId == "issue_offer_player_response_reject" &&
                    ((state["context"]?["conversation"] as JsonObject) is JsonObject finalOffer &&
                     IsFinalTrainingOffer(finalOffer)))
                {
                    offerRefusalPendingExit = true;
                    directOfferExitFailureCode = directOfferWasClickable
                        ? "training-issue-direct-offer-rejected"
                        : "training-issue-direct-offer-unavailable";
                }
                if (action == "menuSelect" && nativeCompleted) talkedToIssueGiver = false;
                if (action == "mapSettlementTargets" && nativeCompleted)
                    visibleSafeTargets = AgentHostCampaignLoop.BuildSafeVisibleTargets(nativeReceipt, visitedSettlements, settlementsOnly: true);
                if (action == "move" && nativeCompleted)
                {
                    if (ReadString(arguments, "settlementId") is string moved && !string.IsNullOrWhiteSpace(moved)) visitedSettlements.Add(moved);
                    visibleSafeTargets = null;
                }
                upgradeOptionsReceipt = UpdateUpgradeOptionsReceipt(upgradeOptionsReceipt, action, nativeReceipt, nativeCompleted, activeTrainingIssue);
                previousReceipt = new JsonObject { ["action"] = action, ["status"] = ReadString(nativeReceipt, "status"), ["data"] = nativeReceipt["data"]?.DeepClone() };
                feedback = nativeCompleted ? null : new JsonObject { ["kind"] = "native-action-not-completed", ["message"] = ReadString(nativeReceipt, "error") };
                using (var afterAction = await client.ReadStateAsync(elapsed.Token)) currentNative = ParseObject(afterAction.RootElement);
                var afterActionConversation = (currentNative["state"]?["context"] as JsonObject)?["conversation"] as JsonObject;
                if (afterActionConversation is null && !activeTrainingIssue && (action is "dialogueSelect" or "dialogueContinue"))
                    talkedToIssueGiver = false;
                trace.Add(BuildDecisionStep(decisionIndex, modelRequest, decision, feedback, previousReceipt, nativeCompleted));
                if (action == "mapSettlementTargets" && visibleSafeTargets?.Count == 0)
                {
                    failure = "No currently visible safe settlement target was returned; no move was invented.";
                    failureCode = "training-issue-no-safe-settlement-visible";
                    termination = failureCode;
                    break;
                }
            }

            if (termination is null)
            {
                failure = "The Native training Issue route exhausted the shared EYC decision budget before original Gold Journal progress.";
                failureCode = "training-issue-budget-exhausted";
                termination = failureCode;
            }
        }
        catch (OperationCanceledException)
        {
            failure = cancellationToken.IsCancellationRequested ? "Host stop was requested; no action was replayed." : "The bounded training Issue route exceeded its elapsed-time limit.";
            failureCode = cancellationToken.IsCancellationRequested ? "host-stop-requested" : "training-issue-timeout";
            termination = failureCode;
        }
        catch (Exception exception)
        {
            failure = exception is AgentHostException hostException ? hostException.Message : exception.GetType().Name;
            failureCode = exception is AgentHostException typed ? typed.Code : null;
            termination = "training-issue-loop-failed";
            trace.Add(new JsonObject { ["stage"] = "training-issue-loop-failed", ["failure"] = failure, ["detail"] = exception.Message.Length > 500 ? exception.Message[..500] : exception.Message });
        }

        try { if (currentNative is not null) eycJournalAfter = await ReadEycJournalAsync(client, CancellationToken.None); }
        catch { }
        var goldBefore = GoldCurrent(eycJournalBefore);
        var goldAfter = GoldCurrent(eycJournalAfter);
        goldDelta = double.IsFinite(goldBefore) && double.IsFinite(goldAfter) ? goldAfter - goldBefore : double.NaN;
        var resultStatus = double.IsFinite(goldDelta) && goldDelta > 0 ? "completed" : "failed";
        if (resultStatus == "completed")
        {
            failure = null;
            failureCode = null;
            termination = "native-training-issue-increased-original-eyc-gold-journal";
        }
        return BuildResult(resultStatus, termination ?? "training-issue-loop-failed", failure, failureCode);

        JsonObject BuildResult(string status, string resultTermination, string? resultFailure, string? resultFailureCode) => new()
        {
            ["status"] = status, ["resultKind"] = "establish-clan-training-issue", ["runId"] = runId,
            ["providerModelId"] = provider.ModelId, ["providerConfigurationSource"] = provider.ConfigurationSource,
            ["decisions"] = decisions, ["actionsExecuted"] = actionsExecuted, ["promptTokens"] = promptTokens,
            ["completionTokens"] = completionTokens, ["failure"] = resultFailure, ["failureCode"] = resultFailureCode,
            ["termination"] = resultTermination, ["trainingIssueQuestId"] = trackedIssueQuestId,
            ["issueGiverSettlementId"] = issueGiverSettlementId, ["directOfferAccepted"] = directOfferAccepted,
            ["issueJournal"] = issueDetails?.DeepClone(), ["eycGoldJournalBefore"] = eycJournalBefore?.DeepClone(),
            ["eycGoldJournalAfter"] = eycJournalAfter?.DeepClone(), ["eycGoldJournalDelta"] = double.IsFinite(goldDelta) ? JsonValue.Create(goldDelta) : null,
            ["goldObjectiveVerified"] = IsGoldObjectiveMet(eycJournalAfter) || (double.IsFinite(goldDelta) && goldDelta > 0), ["explicitClockActionCount"] = explicitClockActions,
            ["initialNativeState"] = initialNative?.DeepClone(), ["finalNativeState"] = currentNative?.DeepClone(),
            ["providerRouteHistory"] = routes.DeepClone(), ["trace"] = trace.DeepClone()
        };
    }

    internal static JsonArray BuildActionCatalog(JsonObject native, JsonObject? previousReceipt, JsonObject? upgradeOptionsReceipt,
        JsonArray? visibleSafeTargets, bool talkedToIssueGiver, bool activeTrainingIssue = false, IReadOnlySet<string>? contactedIssueGivers = null,
        bool offerRefusalPendingExit = false)
    {
        var state = native["state"] as JsonObject;
        var context = state?["context"] as JsonObject;
        if (state is null || context is null) return new JsonArray();
        var conversation = context["conversation"] as JsonObject;
        if (conversation is not null)
        {
            var currentTrainingIssueGiverConversation = IsCurrentTrainingIssueMapConversation(state, talkedToIssueGiver, activeTrainingIssue, contactedIssueGivers);
            if (IsMapStateConversation(state) && !currentTrainingIssueGiverConversation)
                return BuildGenericMapConversationCatalog(conversation);
            return BuildConversationCatalog(conversation, talkedToIssueGiver, activeTrainingIssue, offerRefusalPendingExit,
                currentTrainingIssueGiverConversation);
        }

        var menuId = ReadString(context, "menuId");
        if (!string.IsNullOrWhiteSpace(menuId))
        {
            var catalog = new JsonArray();
            var menuOptions = (state["availableMenuOptions"] as JsonArray)?.OfType<JsonObject>() ?? Enumerable.Empty<JsonObject>();
            var leaveIds = menuOptions.Where(option => ReadBoolean(option, "available") && ReadBoolean(option, "enabled") && ReadBoolean(option, "isLeave"))
                .Select(option => ReadString(option, "id")).Where(id => !string.IsNullOrWhiteSpace(id)).Cast<string>().ToArray();
            var settlementId = ReadString(state["location"] as JsonObject, "currentSettlementId");
            var isSettlementMenu = menuId is "village" or "town" or "castle" && !string.IsNullOrWhiteSpace(settlementId) &&
                (!ReadBoolean(context, "encounterActive") || string.Equals(settlementId, ReadString(context, "encounteredPartyId"), StringComparison.Ordinal));
            if (isSettlementMenu && !activeTrainingIssue)
            {
                var giverIds = GetVisibleAvailableTrainingIssueGivers(state, contactedIssueGivers);
                if (giverIds.Length > 0)
                    catalog.Add(new JsonObject
                    {
                        ["action"] = "talkToSettlementHero",
                        ["arguments"] = new JsonArray("HeroId"),
                        ["argumentValues"] = new JsonObject { ["HeroId"] = new JsonArray(giverIds.Select(id => (JsonNode?)JsonValue.Create(id)).ToArray()) }
                    });
            }
            if (leaveIds.Length > 0)
                catalog.Add(new JsonObject
                {
                    ["action"] = "menuSelect", ["arguments"] = new JsonArray("MenuId", "OptionId"),
                    ["argumentValues"] = new JsonObject
                    {
                        ["MenuId"] = new JsonArray(menuId),
                        ["OptionId"] = new JsonArray(leaveIds.Select(id => (JsonNode?)JsonValue.Create(id)).ToArray())
                    }
                });
            return catalog;
        }

        if (string.Equals(ReadString(context, "gameState"), "MapState", StringComparison.Ordinal) &&
            !ReadBoolean(context, "encounterActive") && !ReadBoolean(context, "escapeMenuOpen") && !ReadBoolean(context, "inquiryOpen") &&
            state["partyScreen"] is null && state["inventoryScreen"] is null)
        {
            if (ReadBoolean(state["party"] as JsonObject, "isMoving")) return new JsonArray();
            if (activeTrainingIssue)
            {
                var upgradeOptionsAreCurrent = ReadString(upgradeOptionsReceipt, "action") == "partyUpgradeOptions" &&
                    ReadString(upgradeOptionsReceipt, "status") == "completed";
                if (!upgradeOptionsAreCurrent)
                    return new JsonArray(new JsonObject { ["action"] = "partyUpgradeOptions", ["arguments"] = new JsonArray() });
                var actions = new JsonArray();
                AddBorrowedTroopUpgradeAction(actions, upgradeOptionsReceipt);
                if (actions.OfType<JsonObject>().Any(action => ReadString(action, "action") == "upgradeTroop")) return actions;
                AddSafeMovementActions(actions, previousReceipt, visibleSafeTargets);
                return actions;
            }
            var mapActions = new JsonArray();
            AddSafeMovementActions(mapActions, previousReceipt, visibleSafeTargets);
            return mapActions;
        }
        return new JsonArray();
    }

    internal static JsonObject? UpdateUpgradeOptionsReceipt(JsonObject? currentReceipt, string? action, JsonObject nativeReceipt,
        bool nativeCompleted, bool activeTrainingIssue)
    {
        if (!activeTrainingIssue) return null;
        if (action == "partyUpgradeOptions")
            return nativeCompleted && ReadString(nativeReceipt, "status") == "completed"
                ? nativeReceipt.DeepClone() as JsonObject
                : null;
        if (action is "move" or "upgradeTroop") return null;
        return currentReceipt;
    }

    internal static JsonArray BuildConversationCatalog(JsonObject conversation, bool talkedToIssueGiver, bool activeTrainingIssue,
        bool offerRefusalPendingExit, bool currentTrainingIssueGiverConversation = false)
    {
        var options = (conversation["options"] as JsonArray)?.OfType<JsonObject>().ToArray() ?? Array.Empty<JsonObject>();
        if (offerRefusalPendingExit)
        {
            var leave = options.Where(option => ReadBoolean(option, "clickable") && ReadString(option, "id") == "player_is_leaving_neutral_or_friendly").ToArray();
            return DialogueCatalog(leave);
        }
        if (!talkedToIssueGiver && !activeTrainingIssue) return new JsonArray();
        var directOfferUnavailable = !activeTrainingIssue && IsFinalTrainingOfferWithoutDirectAcceptance(conversation);
        var clickable = options.Where(option => ReadBoolean(option, "clickable") && !IsOutOfScopeIssueAcceptance(option) &&
                (!IsTrainingDirectOffer(option) || (talkedToIssueGiver && !activeTrainingIssue && currentTrainingIssueGiverConversation)))
            .Where(option => !directOfferUnavailable || ReadString(option, "id") == "issue_offer_player_response_reject")
            .Select(option => (JsonObject)option.DeepClone()).ToArray();
        if (clickable.Length > 0) return DialogueCatalog(clickable);
        if (!HasClickableConversationOptions(conversation))
            return new JsonArray(new JsonObject { ["action"] = "dialogueContinue", ["arguments"] = new JsonArray() });
        return new JsonArray();

        static JsonArray DialogueCatalog(JsonObject[] choices) => choices.Length == 0
            ? new JsonArray()
            : new JsonArray(new JsonObject
            {
                ["action"] = "dialogueSelect", ["arguments"] = new JsonArray("OptionId"),
                ["argumentValues"] = new JsonObject { ["OptionId"] = new JsonArray(choices.Select(option => (JsonNode?)JsonValue.Create(ReadString(option, "id"))).ToArray()) }
            });
    }

    private static bool IsMapStateConversation(JsonObject? state) =>
        ReadString(state?["context"] as JsonObject, "gameState") == "MapState" &&
        state?["context"]?["conversation"] is JsonObject && !AgentHostCampaignStateFacts.IsActiveEncounter(state!);

    private static bool IsCurrentTrainingIssueMapConversation(JsonObject? state, bool talkedToIssueGiver, bool activeTrainingIssue,
        IReadOnlySet<string>? contactedIssueGivers)
    {
        if (!talkedToIssueGiver && !activeTrainingIssue || contactedIssueGivers is null || contactedIssueGivers.Count == 0) return false;
        var conversation = state?["context"]?["conversation"] as JsonObject;
        var conversationIds = new[] { ReadString(conversation, "heroId"), ReadString(conversation, "characterId") }
            .Where(id => !string.IsNullOrWhiteSpace(id));
        return conversationIds.Any(id => contactedIssueGivers.Contains(id!));
    }

    private static JsonArray BuildGenericMapConversationCatalog(JsonObject conversation)
    {
        var options = (conversation["options"] as JsonArray)?.OfType<JsonObject>().ToArray() ?? Array.Empty<JsonObject>();
        var clickableIds = options.Where(option => ReadBoolean(option, "clickable") &&
                !IsOutOfScopeIssueAcceptance(option) && !IsTrainingDirectOffer(option))
            .Select(option => ReadString(option, "id"))
            .Where(id => !string.IsNullOrWhiteSpace(id)).Distinct(StringComparer.Ordinal).Cast<string>().ToArray();
        if (clickableIds.Length > 0)
            return new JsonArray(new JsonObject
            {
                ["action"] = "dialogueSelect", ["arguments"] = new JsonArray("OptionId"),
                ["argumentValues"] = new JsonObject { ["OptionId"] = new JsonArray(clickableIds.Select(id => (JsonNode?)JsonValue.Create(id)).ToArray()) }
            });
        if (options.Length == 0 && !string.IsNullOrWhiteSpace(ReadString(conversation, "sentenceText")))
            return new JsonArray(new JsonObject { ["action"] = "dialogueContinue", ["arguments"] = new JsonArray() });
        return new JsonArray();
    }

    internal static bool IsFinalTrainingOfferWithoutDirectAcceptance(JsonObject? conversation)
    {
        var options = (conversation?["options"] as JsonArray)?.OfType<JsonObject>().ToArray() ?? Array.Empty<JsonObject>();
        var reject = options.Any(option => ReadString(option, "id") == "issue_offer_player_response_reject" && ReadBoolean(option, "clickable"));
        return reject && !IsTrainingDirectOfferClickable(conversation);
    }

    private static bool IsFinalTrainingOffer(JsonObject conversation) =>
        (conversation["options"] as JsonArray)?.OfType<JsonObject>().Any(option =>
            ReadString(option, "id") == "issue_offer_player_response_reject" && ReadBoolean(option, "clickable")) == true;

    private static bool IsTrainingDirectOfferClickable(JsonObject? conversation) =>
        (conversation?["options"] as JsonArray)?.OfType<JsonObject>().Any(option =>
            ReadString(option, "id") == "issue_offer_player_accept_quest" && ReadBoolean(option, "clickable")) == true;

    internal static JsonArray BuildControlCatalog(JsonObject native, bool activeTrainingIssue, bool upgradeOptionsKnown = false, bool currentlyUpgradable = false)
    {
        var state = native["state"] as JsonObject;
        var context = state?["context"] as JsonObject;
        var party = state?["party"] as JsonObject;
        if (activeTrainingIssue && upgradeOptionsKnown && !currentlyUpgradable && ReadString(context, "gameState") == "MapState" && ReadString(context, "menuId") is null &&
            !ReadBoolean(context, "encounterActive") && !ReadBoolean(context, "escapeMenuOpen") && !ReadBoolean(context, "inquiryOpen") &&
            !ReadBoolean(party, "isMoving") && (state?["nearbyParties"] as JsonArray)?.OfType<JsonObject>()
                .Any(item => ReadString(item, "type") == "bandit" && ReadBoolean(item, "hostile")) == true)
            return new JsonArray("resolveVisibleBandit");
        if (ReadString(context, "gameState") == "MapState" && ReadString(context, "menuId") is null && ReadBoolean(party, "isMoving") &&
            !ReadBoolean(context, "escapeMenuOpen") && !ReadBoolean(context, "inquiryOpen") && !ReadBoolean(context, "encounterActive") &&
            context?["conversation"] is not JsonObject)
            return new JsonArray("observeAgain");
        return new JsonArray();
    }

    internal static bool ShouldStopUnproductiveTrainingIssueSearch(JsonObject native, int decisions, int startingDecisions,
        bool activeTrainingIssue, bool directOfferAccepted)
    {
        if (activeTrainingIssue || directOfferAccepted || decisions - startingDecisions < MaximumTrainingIssueDiscoveryDecisions) return false;
        var state = native["state"] as JsonObject;
        if (state is null) return false;
        var context = state["context"] as JsonObject;
        var captivity = context?["captivity"] as JsonObject;
        return ReadString(context, "gameState") == "MapState" && ReadString(context, "menuId") is null &&
               !ReadBoolean(context, "encounterActive") && !ReadBoolean(context, "escapeMenuOpen") && !ReadBoolean(context, "inquiryOpen") &&
               !ReadBoolean(captivity, "isCaptive") && state["partyScreen"] is null && state["inventoryScreen"] is null &&
               !ReadBoolean(state["party"] as JsonObject, "isMoving") && GetVisibleAvailableTrainingIssueGivers(state).Length == 0;
    }

    internal static bool IsOutOfScopeIssueAcceptance(JsonObject option) =>
        ReadString(option, "id") is "issue_offer_player_accept_alternative" or "issue_offer_player_accept_lord";

    internal static bool IsTrainingDirectOffer(JsonObject option) => ReadString(option, "id") == "issue_offer_player_accept_quest";

    private static void AddBorrowedTroopUpgradeAction(JsonArray catalog, JsonObject? receipt)
    {
        var options = receipt?["data"]?["options"] as JsonArray;
        var borrowed = options?.OfType<JsonObject>().FirstOrDefault(item => ReadString(item, "troopId") == BorrowedTroopId);
        var target = (borrowed?["upgradeTargets"] as JsonArray)?.OfType<JsonObject>().FirstOrDefault(item =>
            ReadString(item, "targetId") == VeteranBorrowedTroopId && ReadBoolean(item, "isAvailable") &&
            !ReadBoolean(item, "isInsufficient") && ReadInt(item, "availableCount") > 0 &&
            (!ReadBoolean(item, "hasItemRequirement") || ReadBoolean(item, "itemRequirementMet")) &&
            (!ReadBoolean(item, "hasPerkRequirement") || ReadBoolean(item, "isPerkRequirementMet")));
        if (borrowed is null || target is null) return;
        var targetIndex = ReadInt(target, "targetIndex", -1);
        if (targetIndex < 0) return;
        catalog.Add(new JsonObject
        {
            ["action"] = "upgradeTroop", ["arguments"] = new JsonArray("TroopId", "UpgradeTargetIndex"),
            ["argumentValues"] = new JsonObject
            {
                ["TroopId"] = new JsonArray(BorrowedTroopId), ["UpgradeTargetIndex"] = new JsonArray(targetIndex)
            }
        });
    }

    private static bool HasAvailableBorrowedUpgrade(JsonObject? receipt)
    {
        var options = receipt?["data"]?["options"] as JsonArray;
        var borrowed = options?.OfType<JsonObject>().FirstOrDefault(item => ReadString(item, "troopId") == BorrowedTroopId);
        return (borrowed?["upgradeTargets"] as JsonArray)?.OfType<JsonObject>().Any(target =>
            ReadString(target, "targetId") == VeteranBorrowedTroopId && ReadBoolean(target, "isAvailable") &&
            !ReadBoolean(target, "isInsufficient") && ReadInt(target, "availableCount") > 0 &&
            (!ReadBoolean(target, "hasItemRequirement") || ReadBoolean(target, "itemRequirementMet")) &&
            (!ReadBoolean(target, "hasPerkRequirement") || ReadBoolean(target, "isPerkRequirementMet"))) == true;
    }

    private static void AddSafeMovementActions(JsonArray catalog, JsonObject? previousReceipt, JsonArray? visibleSafeTargets)
    {
        if (ReadString(previousReceipt, "action") != "mapSettlementTargets" || ReadString(previousReceipt, "status") != "completed")
        {
            catalog.Add(new JsonObject { ["action"] = "mapSettlementTargets", ["arguments"] = new JsonArray() });
            return;
        }
        if (visibleSafeTargets is null || visibleSafeTargets.Count == 0) return;
        catalog.Add(new JsonObject
        {
            ["action"] = "move", ["arguments"] = new JsonArray("SettlementId"),
            ["argumentValues"] = new JsonObject
            {
                ["SettlementId"] = new JsonArray(visibleSafeTargets.OfType<JsonObject>().Select(target => ReadString(target, "id"))
                    .Where(id => !string.IsNullOrWhiteSpace(id)).Select(id => (JsonNode?)JsonValue.Create(id)).ToArray())
            }
        });
    }

    private static string[] GetVisibleAvailableTrainingIssueGivers(JsonObject state, IReadOnlySet<string>? excludedHeroIds = null) =>
        (state["settlementOverlayCharacters"] as JsonArray)?.OfType<JsonObject>()
            .Where(hero => (hero["questMarkers"] as JsonArray)?.OfType<JsonObject>().Any(marker =>
                ReadString(marker, "type") == "AvailableIssue" &&
                IsTrainingIssueTitle(string.Join(" ", ReadString(marker, "title"), ReadString(marker, "hint")))) == true)
            .Select(hero => ReadString(hero, "heroId"))
            .Where(id => !string.IsNullOrWhiteSpace(id) && (excludedHeroIds is null || !excludedHeroIds.Contains(id)))
            .Cast<string>().Distinct(StringComparer.Ordinal).ToArray() ?? Array.Empty<string>();

    internal static JsonObject NativeState(string? menuId, string? settlementId, JsonArray options, JsonArray? overlay = null, bool moving = false) => new()
    {
        ["status"] = "completed", ["processId"] = 321, ["campaignDay"] = 10.0, ["timeControlMode"] = "Stop",
        ["state"] = new JsonObject
        {
            ["context"] = new JsonObject
            {
                ["gameState"] = "MapState", ["menuId"] = menuId,
                ["encounterActive"] = menuId is "village" or "town" or "castle",
                ["encounteredPartyId"] = menuId is "village" or "town" or "castle" ? settlementId : null
            },
            ["location"] = new JsonObject { ["currentSettlementId"] = settlementId },
            ["availableMenuOptions"] = options.DeepClone(), ["settlementOverlayCharacters"] = overlay?.DeepClone() ?? new JsonArray(),
            ["party"] = new JsonObject { ["isMoving"] = moving }
        }
    };

    private static bool HasClickableConversationOptions(JsonObject conversation) =>
        (conversation["options"] as JsonArray)?.OfType<JsonObject>().Any(option => ReadBoolean(option, "clickable")) == true;

    private static async Task<JsonObject> ReadEycJournalAsync(IAgentHostQuestDetailsNativeClient client, CancellationToken cancellationToken)
    {
        using var receipt = await client.ReadQuestDetailsAsync(EycQuestId, cancellationToken);
        var node = ParseObject(receipt.RootElement);
        if (ReadString(node, "status") != "completed" || node["data"] is not JsonObject data || ReadString(data, "questId") != EycQuestId)
            throw new AgentHostException("training-issue-eyc-journal-unavailable", "The current original Establish Your Clan Journal could not be read to verify Gold progress.");
        return AgentHostEstablishYourClanGoalLoop.BuildObjectiveSnapshot(AgentHostEstablishYourClanGoalLoop.BuildJournalObjectives(data));
    }

    private static double GoldCurrent(JsonObject? snapshot) => ReadDouble(snapshot?["gold"] as JsonObject, "current", double.NaN);
    private static double GoldTarget(JsonObject? snapshot) => ReadDouble(snapshot?["gold"] as JsonObject, "target", double.NaN);
    private static bool IsGoldObjectiveMet(JsonObject? snapshot) => ReadBoolean(snapshot?["gold"] as JsonObject, "met") ||
        double.IsFinite(GoldCurrent(snapshot)) && double.IsFinite(GoldTarget(snapshot)) && GoldCurrent(snapshot) >= GoldTarget(snapshot);

    private static bool HasActiveEycQuest(JsonObject? native) =>
        (native?["state"]?["quests"] as JsonArray)?.OfType<JsonObject>().Any(quest => ReadString(quest, "id") == EycQuestId) == true;

    private static string? FindTrainingIssueQuestId(JsonObject? state) =>
        (state?["quests"] as JsonArray)?.OfType<JsonObject>()
            .FirstOrDefault(quest => (ReadString(quest, "id") ?? string.Empty).StartsWith("issue_", StringComparison.Ordinal) &&
                                     IsTrainingIssueTitle(ReadString(quest, "title") ?? string.Empty)) is JsonObject found
            ? ReadString(found, "id")
            : null;

    private static bool IsTrainingIssueTitle(string title) =>
        title.Contains("训练士兵", StringComparison.Ordinal) || title.Contains("训练部队", StringComparison.Ordinal) ||
        title.Contains("Train Troops", StringComparison.OrdinalIgnoreCase) || title.Contains("Retainers", StringComparison.OrdinalIgnoreCase);

    internal static bool IsTrainingReturnInquiry(JsonObject? inquiry)
    {
        if (ReadString(inquiry, "kind") != "YesNoInquiry" || !ReadBoolean(inquiry, "supported")) return false;
        var text = ReadString(inquiry, "text") ?? string.Empty;
        var affirmative = ReadString(inquiry?["affirmative"] as JsonObject, "text") ?? string.Empty;
        return (text.Contains("借调士兵", StringComparison.Ordinal) && text.Contains("调回", StringComparison.Ordinal) && affirmative.Contains("调回", StringComparison.Ordinal)) ||
               (text.Contains("borrowed troops", StringComparison.OrdinalIgnoreCase) && text.Contains("send them back", StringComparison.OrdinalIgnoreCase) &&
                affirmative.Contains("send the troops back", StringComparison.OrdinalIgnoreCase));
    }

    internal static JsonObject? BuildSafeModelPreviousReceipt(JsonObject? receipt, JsonArray? visibleSafeTargets)
    {
        if (receipt is null) return null;
        var copy = (JsonObject)receipt.DeepClone();
        if (ReadString(copy, "action") == "mapSettlementTargets" && visibleSafeTargets is not null &&
            copy["data"] is JsonObject data && data["mapSettlementTargets"] is JsonArray)
        {
            data["mapSettlementTargets"] = visibleSafeTargets.DeepClone();
            copy["dataSummary"] = new JsonObject
            {
                ["visibleTargetCount"] = visibleSafeTargets.Count,
                ["safeCandidateCount"] = visibleSafeTargets.Count
            };
        }
        return copy;
    }

    internal static JsonObject BuildModelState(JsonObject nativeState, JsonArray? visibleSafeTargets)
    {
        var modelState = (JsonObject)(nativeState["state"]?.DeepClone() ?? new JsonObject());
        if (visibleSafeTargets is not null)
            modelState["nearbySettlements"] = visibleSafeTargets.DeepClone();
        return modelState;
    }

    private static JsonObject BuildObservation(JsonObject native, JsonObject? eycGoldSnapshot, JsonObject? issueDetails,
        string? issueQuestId, JsonObject? upgradeOptionsReceipt, JsonObject? previousReceipt, JsonObject? feedback,
        JsonArray? visibleSafeTargets) => new()
    {
        ["scope"] = "native-storymode-training-issue-gold",
        ["status"] = "completed",
        ["campaignDay"] = native["campaignDay"]?.DeepClone(),
        ["timeControlMode"] = native["timeControlMode"]?.DeepClone(),
        ["state"] = BuildModelState(native, visibleSafeTargets),
        ["currentEycGoldObjective"] = eycGoldSnapshot?["gold"]?.DeepClone(),
        ["activeTrainingIssueQuestId"] = issueQuestId,
        ["activeTrainingIssueJournal"] = issueDetails?["data"]?.DeepClone(),
        ["currentPartyUpgradeOptions"] = upgradeOptionsReceipt?["data"]?.DeepClone(),
        ["previousActionReceipt"] = previousReceipt?.DeepClone(),
        ["decisionFeedback"] = feedback?.DeepClone()
    };

    private static JsonObject BuildDecisionRequest(string runId, int iteration, string goal, JsonObject observation,
        JsonObject? previousReceipt, JsonObject? feedback, JsonArray actions, JsonArray controls) => new()
    {
        ["schemaVersion"] = 1,
        ["runId"] = runId,
        ["iteration"] = iteration,
        ["goal"] = goal,
        ["goalScopeContract"] = "native-establish-clan-training-issue-gold-v1",
        ["goalScopeClassificationRequired"] = false,
        ["observation"] = observation,
        ["previousActionReceipt"] = previousReceipt?.DeepClone(),
        ["decisionFeedback"] = feedback?.DeepClone(),
        ["allowedActions"] = actions.DeepClone(),
        ["allowedControls"] = controls.DeepClone()
    };

    private static bool TryResolveDecision(JsonObject decision, JsonArray catalog, JsonObject state, JsonArray? visibleSafeTargets,
        JsonObject? upgradeOptionsReceipt, bool talkedToIssueGiver, bool activeTrainingIssue,
        out string? action, out JsonObject? nativeArguments, out string rejection, IReadOnlySet<string>? contactedIssueGivers = null)
    {
        action = ReadString(decision, "action");
        nativeArguments = null;
        rejection = "The model must select one currently listed Native action with exact current arguments.";
        if (string.IsNullOrWhiteSpace(action)) return false;
        var selectedAction = action;
        var entry = catalog.OfType<JsonObject>().FirstOrDefault(item => ReadString(item, "action") == selectedAction);
        if (entry is null) return false;
        var schema = entry["arguments"] as JsonArray ?? new JsonArray();
        var supplied = decision["arguments"] as JsonObject ?? new JsonObject();
        if (supplied.Count != schema.Count) return false;
        foreach (var rawName in schema.OfType<JsonValue>())
        {
            if (!rawName.TryGetValue<string>(out var name)) return false;
            if (!supplied.TryGetPropertyValue(name, out var suppliedValue)) return false;
            if (entry["argumentValues"]?[name] is JsonArray values &&
                !values.Any(allowed => allowed is not null && JsonNode.DeepEquals(allowed, suppliedValue))) return false;
        }
        if (selectedAction == "talkToSettlementHero")
        {
            var heroId = ReadString(supplied, "HeroId");
            if (heroId is null || !GetVisibleAvailableTrainingIssueGivers(state).Contains(heroId, StringComparer.Ordinal))
            { rejection = "talkToSettlementHero requires a HeroId whose current visible AvailableIssue marker identifies the Landlord Training for Retainers route."; return false; }
        }
        if (selectedAction == "dialogueContinue")
        {
            var conversation = (state["context"] as JsonObject)?["conversation"] as JsonObject;
            if (conversation is null || HasClickableConversationOptions(conversation) ||
                IsMapStateConversation(state) && string.IsNullOrWhiteSpace(ReadString(conversation, "sentenceText")))
            { rejection = "dialogueContinue is valid only for a current Native conversation with no clickable choice."; return false; }
        }
        if (selectedAction == "dialogueSelect")
        {
            var mapConversation = IsMapStateConversation(state);
            var currentIssueGiverConversation = IsCurrentTrainingIssueMapConversation(state, talkedToIssueGiver, activeTrainingIssue, contactedIssueGivers);
            if (!mapConversation && !talkedToIssueGiver && !activeTrainingIssue)
            { rejection = "The Native Issue conversation was not opened from a current AvailableIssue marker."; return false; }
            var optionId = ReadString(supplied, "OptionId");
            var conversation = (state["context"] as JsonObject)?["conversation"] as JsonObject;
            var option = (conversation?["options"] as JsonArray)?.OfType<JsonObject>().FirstOrDefault(item => ReadString(item, "id") == optionId && ReadBoolean(item, "clickable"));
            if (option is null || IsOutOfScopeIssueAcceptance(option) || IsTrainingDirectOffer(option) &&
                (!currentIssueGiverConversation || activeTrainingIssue))
            { rejection = "Only current clickable issue dialogue options are allowed, and direct acceptance must match the Native training response."; return false; }
        }
        if (selectedAction == "move")
        {
            var settlementId = ReadString(supplied, "SettlementId");
            if (settlementId is null || visibleSafeTargets?.OfType<JsonObject>().Any(target => ReadString(target, "id") == settlementId) != true)
            { rejection = "move must select a settlement from the current safe, visible Native target receipt."; return false; }
        }
        if (selectedAction == "upgradeTroop")
        {
            if (!activeTrainingIssue || ReadString(supplied, "TroopId") != BorrowedTroopId ||
                upgradeOptionsReceipt is null || !IsCurrentBorrowedUpgrade(upgradeOptionsReceipt, ReadInt(supplied, "UpgradeTargetIndex", -1)))
            { rejection = "upgradeTroop is limited to the current Native offer for borrowed retainers and the exact veteran target."; return false; }
        }
        nativeArguments = ToNativeArguments(selectedAction, supplied);
        return true;
    }

    private static bool IsCurrentBorrowedUpgrade(JsonObject? receipt, int targetIndex)
    {
        var source = (receipt?["data"]?["options"] as JsonArray)?.OfType<JsonObject>().FirstOrDefault(item => ReadString(item, "troopId") == BorrowedTroopId);
        return (source?["upgradeTargets"] as JsonArray)?.OfType<JsonObject>().Any(target =>
            ReadInt(target, "targetIndex", -1) == targetIndex && ReadString(target, "targetId") == VeteranBorrowedTroopId &&
            ReadBoolean(target, "isAvailable") && !ReadBoolean(target, "isInsufficient") && ReadInt(target, "availableCount") > 0 &&
            (!ReadBoolean(target, "hasItemRequirement") || ReadBoolean(target, "itemRequirementMet")) &&
            (!ReadBoolean(target, "hasPerkRequirement") || ReadBoolean(target, "isPerkRequirementMet"))) == true;
    }

    private static JsonObject ToNativeArguments(string action, JsonObject supplied)
    {
        var result = new JsonObject();
        foreach (var property in supplied)
        {
            var nativeName = property.Key switch
            {
                "HeroId" => "heroId", "OptionId" => "optionId", "MenuId" => "menuId", "SettlementId" => "settlementId",
                "TroopId" => "troopId", "UpgradeTargetIndex" => "upgradeTargetIndex", _ => property.Key
            };
            result[nativeName] = property.Value?.DeepClone();
        }
        if (action is "mapSettlementTargets" or "partyUpgradeOptions" or "dialogueContinue" or "battleSimulation") return new JsonObject();
        return result;
    }

    private static JsonObject BuildDecisionStep(int iteration, JsonObject request, JsonObject? decision, JsonObject? feedback,
        JsonObject? receipt, bool actionExecuted) => new()
    {
        ["iteration"] = iteration,
        ["goal"] = ReadString(request, "goal"),
        ["observation"] = request["observation"]?.DeepClone(),
        ["allowedActions"] = request["allowedActions"]?.DeepClone(),
        ["allowedControls"] = request["allowedControls"]?.DeepClone(),
        ["decision"] = decision?.DeepClone(),
        ["feedback"] = feedback?.DeepClone(),
        ["actionReceipt"] = receipt?.DeepClone(),
        ["actionExecuted"] = actionExecuted,
        ["explicitClockAction"] = false
    };

    private static void AddProviderRoute(JsonArray routes, IAgentHostDecisionProvider provider, ProviderDecisionResult result,
        int decision, ref long promptTokens, ref long completionTokens)
    {
        if (result.PromptTokens.HasValue) promptTokens += result.PromptTokens.Value;
        if (result.CompletionTokens.HasValue) completionTokens += result.CompletionTokens.Value;
        routes.Add(new JsonObject
        {
            ["decision"] = decision, ["requestedModelId"] = provider.ModelId, ["responseModelId"] = result.ModelId,
            ["routedVia"] = result.RoutedVia, ["responseFormatMode"] = result.ResponseFormatMode,
            ["promptTokens"] = result.PromptTokens, ["completionTokens"] = result.CompletionTokens
        });
    }

    private static void AppendRoutes(JsonArray destination, JsonArray? source)
    {
        if (source is null) return;
        foreach (var item in source) destination.Add(item?.DeepClone());
    }

    private static JsonObject MapState(string? menuId, bool moving = false) =>
        NativeState(menuId, menuId is "village" or "town" or "castle" ? "settlement-a" : null, new JsonArray(), moving: moving);

    private static bool IsObservedHostileBandit(JsonObject state) =>
        (state["nearbyParties"] as JsonArray)?.OfType<JsonObject>()
            .Any(item => ReadString(item, "type") == "bandit" && ReadBoolean(item, "hostile")) == true;

    private sealed class FakeMapDialogueNativeClient : IAgentHostEstablishClanTrainingIssueNativeClient, IAgentHostBattleSimulationNativeClient
    {
        private bool _encounterActive;
        internal List<(string Action, string? OptionId)> Actions { get; } = [];

        public Task<JsonDocument> ReadStateAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            return Task.FromResult(JsonDocument.Parse(BuildState().ToJsonString()));
        }

        public Task<JsonDocument> ExecuteCampaignActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken) =>
            throw new AgentHostException("training-issue-map-dialogue-unexpected-campaign-action", "The map-dialogue transport test must use the task-scoped Native adapter.");

        public Task<JsonDocument> ExecuteTrainingIssueActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var optionId = ReadString(arguments, "optionId");
            Actions.Add((action, optionId));
            if (action != "dialogueSelect" || optionId != "map-safe-reply")
                throw new AgentHostException("training-issue-map-dialogue-invalid-native-action", "Only the current safe map-conversation response is accepted by this fake Native route.");
            _encounterActive = true;
            return Task.FromResult(JsonDocument.Parse(new JsonObject
            {
                ["status"] = "completed", ["processId"] = 321, ["action"] = action,
                ["data"] = new JsonObject { ["optionId"] = optionId }
            }.ToJsonString()));
        }

        public Task<JsonDocument> ReadQuestDetailsAsync(string questId, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (questId != EycQuestId)
                throw new AgentHostException("training-issue-map-dialogue-unexpected-quest", "Only the active original EYC Journal may be read in this test.");
            var stages = new JsonArray(
                JournalStage(0, 2000), JournalStage(0, 25), JournalStage(0, 50), JournalStage(0, 1));
            return Task.FromResult(JsonDocument.Parse(new JsonObject
            {
                ["status"] = "completed",
                ["data"] = new JsonObject { ["questId"] = EycQuestId, ["journalStages"] = stages }
            }.ToJsonString()));
        }

        public Task<JsonDocument> RespondNativeInquiryAsync(string token, string choice, CancellationToken cancellationToken) =>
            throw new AgentHostException("training-issue-map-dialogue-unexpected-inquiry", "No inquiry is part of the map-dialogue transport case.");

        public Task<JsonDocument> SubmitStoryModeClanNameAsync(string token, string clanName, CancellationToken cancellationToken) =>
            throw new AgentHostException("training-issue-map-dialogue-unexpected-clan-name", "No StoryMode setup action is part of the map-dialogue transport case.");

        public Task<JsonDocument> ExecuteBattleSimulationActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken) =>
            throw new AgentHostException("training-issue-map-dialogue-unexpected-battle-action", "A map-dialogue interruption must yield an encounter to the parent without starting a battle subflow.");

        public Task<JsonDocument> PauseForVisibleHostileDecisionAsync(CancellationToken cancellationToken) =>
            throw new AgentHostException("training-issue-map-dialogue-unexpected-pause", "This test must not issue a clock action.");

        private JsonObject BuildState()
        {
            var conversation = _encounterActive ? null : new JsonObject
            {
                ["characterId"] = "unrelated-map-notable",
                ["sentenceText"] = "A different current Native map conversation.",
                ["options"] = new JsonArray(
                    new JsonObject { ["id"] = "map-safe-reply", ["text"] = "A visible reply.", ["clickable"] = true },
                    new JsonObject { ["id"] = "issue_offer_player_accept_quest", ["textId"] = DirectTrainingResponseTextId, ["text"] = "Accept another issue.", ["clickable"] = true })
            };
            return new JsonObject
            {
                ["status"] = "completed", ["processId"] = 321, ["campaignDay"] = 10.0, ["timeControlMode"] = "StoppablePlay",
                ["state"] = new JsonObject
                {
                    ["context"] = new JsonObject
                    {
                        ["gameState"] = "MapState", ["menuId"] = _encounterActive ? "encounter" : null,
                        ["conversation"] = conversation, ["encounterActive"] = _encounterActive,
                        ["encounteredPartyId"] = _encounterActive ? "looter-party" : null,
                        ["escapeMenuOpen"] = false, ["inquiryOpen"] = false, ["battleSimulation"] = null
                    },
                    ["quests"] = new JsonArray(new JsonObject { ["id"] = EycQuestId, ["title"] = "Establish Your Clan" }),
                    ["location"] = new JsonObject { ["currentSettlementId"] = null, ["targetSettlementId"] = "settlement-target" },
                    ["party"] = new JsonObject { ["isMoving"] = !_encounterActive },
                    ["nearbyParties"] = new JsonArray()
                }
            };
        }

        private static JsonObject JournalStage(double current, double target) => new()
        {
            ["hasTask"] = true, ["currentProgress"] = current, ["targetProgress"] = target
        };
    }

    private sealed class FakeMapDialogueDecisionProvider : IAgentHostDecisionProvider
    {
        public string ModelId => "training-issue-map-dialogue-self-test";
        public string ConfigurationSource => "harness-fake-provider";
        internal int Calls { get; private set; }
        internal bool ReceivedOnlyCurrentSafeMapReply { get; private set; }
        public void Dispose() { }
        public Task CheckConfiguredModelAsync(CancellationToken cancellationToken) => Task.CompletedTask;

        public Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Calls++;
            var actions = request.GetProperty("allowedActions").EnumerateArray().ToArray();
            var controls = request.GetProperty("allowedControls").EnumerateArray().Select(item => item.GetString()).ToArray();
            var optionIds = actions.SingleOrDefault(item => item.GetProperty("action").GetString() == "dialogueSelect")
                .GetProperty("argumentValues").GetProperty("OptionId").EnumerateArray().Select(item => item.GetString()).ToArray();
            ReceivedOnlyCurrentSafeMapReply = Calls == 1 && actions.Length == 1 &&
                optionIds.SequenceEqual(new[] { "map-safe-reply" }, StringComparer.Ordinal) &&
                !controls.Contains("observeAgain", StringComparer.Ordinal) &&
                systemPrompt.Contains("MAP DIALOGUE INTERRUPTION", StringComparison.Ordinal);
            if (!ReceivedOnlyCurrentSafeMapReply)
                throw new AgentHostException("training-issue-map-dialogue-provider-catalog-invalid", "The fake model did not receive exactly the current safe reply with no movement wait or issue acceptance.");
            return Task.FromResult(new ProviderDecisionResult("completed", ModelId, 10, 3, "stop",
                new JsonObject { ["action"] = "dialogueSelect", ["arguments"] = new JsonObject { ["OptionId"] = "map-safe-reply" } }));
        }
    }

    private static JsonObject ParseObject(JsonElement value) => JsonNode.Parse(value.GetRawText())?.AsObject()
        ?? throw new AgentHostException("training-issue-native-response-invalid", "The Native training-issue route received no JSON object.");

    private static string? ReadString(JsonObject? node, string key) => node?[key] is JsonValue value && value.TryGetValue<string>(out var text) ? text : null;
    private static string? ReadString(JsonElement node, string key) => node.ValueKind == JsonValueKind.Object && node.TryGetProperty(key, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;
    private static int ReadInt(JsonObject? node, string key, int fallback = 0) => node?[key] is JsonValue value && value.TryGetValue<int>(out var number) ? number : fallback;
    private static int ReadInt(JsonElement node, string key, int fallback = 0) => node.ValueKind == JsonValueKind.Object && node.TryGetProperty(key, out var value) && value.TryGetInt32(out var number) ? number : fallback;
    private static long ReadLong(JsonObject? node, string key, long fallback = 0) => node?[key] is JsonValue value && value.TryGetValue<long>(out var number) ? number : fallback;
    private static double ReadDouble(JsonObject? node, string key, double fallback = double.NaN)
    {
        if (node?[key] is not JsonValue value) return fallback;
        if (value.TryGetValue<double>(out var number)) return number;
        if (value.TryGetValue<int>(out var integer)) return integer;
        if (value.TryGetValue<long>(out var longInteger)) return longInteger;
        return fallback;
    }
    private static bool ReadBoolean(JsonObject? node, string key) => node?[key] is JsonValue value && value.TryGetValue<bool>(out var flag) && flag;
}
