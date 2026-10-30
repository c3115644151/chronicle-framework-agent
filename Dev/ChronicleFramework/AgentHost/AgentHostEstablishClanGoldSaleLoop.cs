using System.Diagnostics;
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal static class AgentHostEstablishClanGoldSaleLoop
{
    private const string QuestId = "rebuild_player_clan_storymode_quest";
    private const int MinimumActiveMapTravelObserveSeconds = 5;

    internal static IReadOnlyList<object> RunContractSelfTests()
    {
        var nativeTown = MapState("town", "sargot", new JsonArray(
            new JsonObject { ["id"] = "trade", ["available"] = true, ["enabled"] = true },
            new JsonObject { ["id"] = "leave", ["available"] = true, ["enabled"] = true }));
        var townCatalog = BuildActionCatalog(nativeTown, null, null, null);
        var townOptionIds = townCatalog.FirstOrDefault()?["argumentValues"]?["OptionId"] as JsonArray;
        if (townCatalog.Count != 1 || ReadString(townCatalog[0] as JsonObject, "action") != "menuSelect" ||
            townOptionIds?.Count != 1 || townOptionIds[0]?.GetValue<string>() != "trade")
            throw new AgentHostException("gold-sale-self-test-town-menu-scope-failed", "Only the currently enabled Native Town Trade entry may be offered from the safe Town menu.");

        var tradeOptions = new JsonObject
        {
            ["action"] = "tradeOptions",
            ["status"] = "completed",
            ["data"] = new JsonObject
            {
                ["sellOffers"] = new JsonArray
                {
                    new JsonObject { ["viewModelItemId"] = "goods-1", ["nativeTooltipType"] = "Goods", ["inventorySide"] = "PlayerInventory", ["stock"] = 2, ["inventoryLogicUnitPrice"] = 100, ["isTransferable"] = true },
                    new JsonObject { ["viewModelItemId"] = "goods-locked", ["nativeTooltipType"] = "Goods", ["inventorySide"] = "PlayerInventory", ["stock"] = 1, ["inventoryLogicUnitPrice"] = 500, ["isTransferable"] = false },
                    new JsonObject { ["viewModelItemId"] = "market-goods", ["nativeTooltipType"] = "Goods", ["inventorySide"] = "OtherInventory", ["stock"] = 99, ["inventoryLogicUnitPrice"] = 1, ["isTransferable"] = true },
                    new JsonObject { ["viewModelItemId"] = "equipped-sword", ["nativeTooltipType"] = "Weapon", ["inventorySide"] = "PlayerInventory", ["stock"] = 1, ["inventoryLogicUnitPrice"] = 300, ["isTransferable"] = true },
                    new JsonObject { ["viewModelItemId"] = "zero-value", ["nativeTooltipType"] = "Goods", ["inventorySide"] = "PlayerInventory", ["stock"] = 1, ["inventoryLogicUnitPrice"] = 0, ["isTransferable"] = true }
                }
            }
        };
        var tradeState = new JsonObject
        {
            ["context"] = new JsonObject { ["gameState"] = "InventoryState", ["menuId"] = null, ["captivity"] = null, ["encounterActive"] = true, ["encounteredPartyId"] = "sargot" },
            ["location"] = new JsonObject { ["currentSettlementId"] = "sargot" },
            ["inventoryScreen"] = new JsonObject { ["mode"] = "Trade", ["hasHandler"] = true, ["hasPendingChanges"] = false }
        };
        if (AgentHostCampaignStateFacts.IsActiveEncounter(tradeState) && IsActiveEncounter(tradeState))
            throw new AgentHostException("gold-sale-self-test-native-trade-misclassified-as-encounter", "The original settlement Trade InventoryState must not be treated as a hostile encounter when the Native encounter owner is the same current settlement.");
        var saleCatalog = BuildActionCatalog(tradeState, tradeOptions, null, null);
        var saleItemIds = saleCatalog[0]?["argumentValues"]?["ItemViewModelId"] as JsonArray;
        var saleAmountValues = saleCatalog[0]?["argumentValues"]?["Amount"] as JsonArray;
        if (saleCatalog.Count != 1 || ReadString(saleCatalog[0] as JsonObject, "action") != "trade" ||
            saleItemIds?.Count != 1 || saleItemIds[0]?.GetValue<string>() != "goods-1" ||
            saleAmountValues?.Count != 1 || saleAmountValues[0]?.GetValue<int>() != 1 ||
            saleCatalog[0]?["arguments"]?[1]?.GetValue<string>() != "ItemViewModelId")
            throw new AgentHostException("gold-sale-self-test-current-sell-offer-scope-failed", "The sale catalog must expose exactly one current transferable Goods offer at the quoted positive price and limit the slice to one unit.");
        var noGoodsQuote = tradeOptions.DeepClone() as JsonObject ?? throw new AgentHostException("gold-sale-self-test-no-goods-quote-invalid", "The no-goods quote fixture could not be cloned.");
        noGoodsQuote["data"]!["sellOffers"] = new JsonArray(
            new JsonObject { ["viewModelItemId"] = "bound-banner", ["nativeTooltipType"] = "Banner", ["inventorySide"] = "PlayerInventory", ["stock"] = 1, ["inventoryLogicUnitPrice"] = 1, ["isTransferable"] = false });
        var zeroPricedGoodsQuote = tradeOptions.DeepClone() as JsonObject ?? throw new AgentHostException("gold-sale-self-test-zero-price-quote-invalid", "The zero-priced quote fixture could not be cloned.");
        zeroPricedGoodsQuote["data"]!["sellOffers"] = new JsonArray(
            new JsonObject { ["viewModelItemId"] = "zero-price-goods", ["nativeTooltipType"] = "Goods", ["inventorySide"] = "PlayerInventory", ["stock"] = 1, ["inventoryLogicUnitPrice"] = 0, ["isTransferable"] = true });
        if (HasTransferableGoodsInventory(noGoodsQuote) || !HasTransferableGoodsInventory(zeroPricedGoodsQuote))
            throw new AgentHostException("gold-sale-self-test-transferable-inventory-classification-failed", "The route may stop early only when the complete Native PlayerInventory quote contains no transferable Goods at any price; bound quest items are not sale stock, while zero-priced Goods may be worth checking at another market.");

        var staleQuote = tradeOptions.DeepClone() as JsonObject ?? throw new AgentHostException("gold-sale-self-test-stale-quote-invalid", "The current quote fixture could not be cloned.");
        staleQuote["data"]!["sellOffers"]![0]!["viewModelItemId"] = "old-goods-id";
        if (TryResolveAction(tradeState, staleQuote, saleCatalog, new JsonObject
            {
                ["action"] = "trade",
                ["arguments"] = new JsonObject { ["Direction"] = "sell", ["ItemViewModelId"] = "goods-1", ["InventorySide"] = "PlayerInventory", ["Amount"] = 1 }
            }, null, null, out _, out _, out _))
            throw new AgentHostException("gold-sale-self-test-stale-trade-quote-accepted", "A sell item id from a prior Trade VM must not be accepted.");

        var moveTargetReceipt = new JsonObject
        {
            ["status"] = "completed",
            ["data"] = new JsonObject
            {
                ["mapSettlementTargets"] = new JsonArray
                {
                    new JsonObject { ["id"] = "safe-town", ["name"] = "Safe Town", ["type"] = "town", ["distance"] = 5.0, ["hostile"] = false, ["underSiege"] = false },
                    new JsonObject { ["id"] = "village", ["name"] = "Village", ["type"] = "village", ["distance"] = 2.0, ["hostile"] = false, ["underSiege"] = false },
                    new JsonObject { ["id"] = "hostile-town", ["name"] = "Hostile Town", ["type"] = "town", ["distance"] = 4.0, ["hostile"] = true, ["underSiege"] = false },
                    new JsonObject { ["id"] = "siege-town", ["name"] = "Sieged Town", ["type"] = "town", ["distance"] = 3.0, ["hostile"] = false, ["underSiege"] = true }
                }
            }
        };
        var noSettlement = MapState(null, null, []);
        var movementCatalog = BuildActionCatalog(noSettlement, moveTargetReceipt, FilterSafeTowns(moveTargetReceipt), null);
        var movementTargets = movementCatalog[0]?["argumentValues"]?["SettlementId"] as JsonArray;
        if (movementCatalog.Count != 1 || ReadString(movementCatalog[0] as JsonObject, "action") != "move" ||
            movementTargets?.Count != 1 || movementTargets[0]?.GetValue<string>() != "safe-town")
            throw new AgentHostException("gold-sale-self-test-safe-town-movement-failed", "The sale route must use only currently visible, non-hostile, non-sieged Towns.");
        if (FilterSafeTowns(moveTargetReceipt, new HashSet<string>(StringComparer.Ordinal) { "safe-town" }).Count != 0)
            throw new AgentHostException("gold-sale-self-test-visited-town-reoffered", "A Town already left during a no-goods market sweep must not be selected again from the next Native map-target observation.");
        if (!TryResolveAction(noSettlement, null, movementCatalog, new JsonObject
            {
                ["action"] = "move",
                ["arguments"] = new JsonObject { ["SettlementId"] = "safe-town" }
            }, FilterSafeTowns(moveTargetReceipt), null, out var resolvedMoveAction, out var resolvedMoveArguments, out _) ||
            resolvedMoveAction != "move" || ReadMoveTargetId(resolvedMoveArguments) != "safe-town")
            throw new AgentHostException("gold-sale-self-test-normalized-move-target-lost", "The Host must recover the destination from its normalized Native argument shape before the next observation cycle.");
        var moveStarting = MapState(null, null, []);
        moveStarting["location"]!["targetSettlementId"] = "safe-town";
        moveStarting["context"]!["timeControlMode"] = "StoppablePlay";
        moveStarting["context"]!["isWaiting"] = true;
        if (!BuildControlCatalog(moveStarting, ReadMoveTargetId(resolvedMoveArguments), moveStartPending: true).Any(control => control?.GetValue<string>() == "observeAgain") ||
            BuildControlCatalog(moveStarting, ReadMoveTargetId(resolvedMoveArguments), moveStartPending: false).Count != 0)
            throw new AgentHostException("gold-sale-self-test-native-move-start-transition-poll-failed", "After its own Native move sets the target but before isMoving updates, allow one bounded read-only poll and no replayed movement or clock action.");
        var movementWaitControls = new JsonArray("observeAgain");
        var startPollRequest = BuildDecisionRequest("gold-sale-self-test", "sale", 1, new JsonObject(), null, null,
            new JsonArray(), movementWaitControls, moveStartPending: true);
        var activeTravelRequest = BuildDecisionRequest("gold-sale-self-test", "sale", 1, new JsonObject(), null, null,
            new JsonArray(), movementWaitControls, moveStartPending: false);
        if (ReadInt(startPollRequest["controlArguments"]?["observeAgain"]?["waitSeconds"] as JsonObject, "minimum", 0) != 1 ||
            ReadInt(activeTravelRequest["controlArguments"]?["observeAgain"]?["waitSeconds"] as JsonObject, "minimum", 0) != MinimumActiveMapTravelObserveSeconds ||
            !IsSupportedObserveInterval(1, moveStartPending: true) || IsSupportedObserveInterval(1, moveStartPending: false) ||
            !IsSupportedObserveInterval(MinimumActiveMapTravelObserveSeconds, moveStartPending: false) || !IsSupportedObserveInterval(10, moveStartPending: false))
            throw new AgentHostException("gold-sale-self-test-active-map-observation-cadence-failed", "The one movement-start poll may be 1 second, while an active map journey must wait at least 5 seconds and at most 10 seconds.");
        var existingMove = MapState(null, null, []);
        existingMove["party"]!["isMoving"] = true;
        existingMove["location"]!["targetSettlementId"] = "user-existing-target";
        if (BuildActionCatalog(existingMove, null, null, null).Count != 0)
            throw new AgentHostException("gold-sale-self-test-existing-move-overwritten", "The Gold sale loop must not replace a Native movement order it did not issue.");

        var travelConversation = MapState(null, null, []);
        travelConversation["party"]!["isMoving"] = true;
        travelConversation["location"]!["targetSettlementId"] = "safe-town";
        travelConversation["context"]!["conversation"] = new JsonObject
        {
            ["sentenceText"] = "My lord, I have something to discuss.",
            ["options"] = new JsonArray(new JsonObject { ["id"] = "grievance_requested", ["text"] = "Continue, I am listening.", ["clickable"] = true })
        };
        var travelDialogueCatalog = BuildActionCatalog(travelConversation, null, null, "safe-town");
        var travelDialogueOptionIds = travelDialogueCatalog.FirstOrDefault()?["argumentValues"]?["OptionId"] as JsonArray;
        if (travelDialogueCatalog.Count != 1 || ReadString(travelDialogueCatalog[0] as JsonObject, "action") != "dialogueSelect" ||
            travelDialogueOptionIds?.Count != 1 || travelDialogueOptionIds[0]?.GetValue<string>() != "grievance_requested" ||
            BuildControlCatalog(travelConversation, "safe-town").Count != 0)
            throw new AgentHostException("gold-sale-self-test-map-dialogue-does-not-yield-to-wait", "An active Native MapState conversation must replace movement waits with only its currently clickable Native options.");
        if (!TryResolveAction(travelConversation, null, travelDialogueCatalog,
            new JsonObject { ["action"] = "dialogueSelect", ["arguments"] = new JsonObject { ["OptionId"] = "grievance_requested" } },
            null, "safe-town", out var travelDialogueAction, out var travelDialogueArguments, out _) ||
            travelDialogueAction != "dialogueSelect" || ReadString(travelDialogueArguments, "optionId") != "grievance_requested")
            throw new AgentHostException("gold-sale-self-test-map-dialogue-current-option-not-resolved", "MapState dialogue must resolve exactly the current visible clickable option through the existing Native action.");
        if (TryResolveAction(travelConversation, null, travelDialogueCatalog,
            new JsonObject { ["action"] = "dialogueSelect", ["arguments"] = new JsonObject { ["OptionId"] = "stale-option" } },
            null, "safe-town", out _, out _, out _))
            throw new AgentHostException("gold-sale-self-test-map-dialogue-stale-option-accepted", "A previous or unlisted conversation option must be rejected before Native dispatch.");
        var travelDialogueText = MapState(null, null, []);
        travelDialogueText["context"]!["conversation"] = new JsonObject { ["sentenceText"] = "The Native NPC continues speaking.", ["options"] = new JsonArray() };
        var travelDialogueContinueCatalog = BuildActionCatalog(travelDialogueText, null, null, null);
        if (travelDialogueContinueCatalog.Count != 1 || ReadString(travelDialogueContinueCatalog[0] as JsonObject, "action") != "dialogueContinue" ||
            !TryResolveAction(travelDialogueText, null, travelDialogueContinueCatalog,
                new JsonObject { ["action"] = "dialogueContinue", ["arguments"] = new JsonObject() }, null, null,
                out var continueAction, out var continueArguments, out _) || continueAction != "dialogueContinue" || continueArguments?.Count != 0)
            throw new AgentHostException("gold-sale-self-test-map-dialogue-continue-not-bounded", "Native Continue may be offered only for an active MapState conversation with no listed options.");
        var disabledDialogueOptions = MapState(null, null, []);
        disabledDialogueOptions["context"]!["conversation"] = new JsonObject
        {
            ["options"] = new JsonArray(new JsonObject { ["id"] = "disabled", ["clickable"] = false })
        };
        if (BuildActionCatalog(disabledDialogueOptions, null, null, null).Count != 0 || BuildControlCatalog(disabledDialogueOptions, "safe-town").Count != 0)
            throw new AgentHostException("gold-sale-self-test-disabled-map-dialogue-not-fail-closed", "A MapState conversation with no clickable Native option must not fall through to waiting or an unrelated action.");
        var dialogueEndedStoppedMove = MapState(null, null, []);
        if (!IsInterruptedMapMove(dialogueEndedStoppedMove, "safe-town", moveStartPending: false) ||
            IsInterruptedMapMove(moveStarting, "safe-town", moveStartPending: true))
            throw new AgentHostException("gold-sale-self-test-cleared-native-move-target-not-replanned", "If a map dialogue ends after Native clears the issued move, re-query current targets; do not clear a move that is still starting.");
        dialogueEndedStoppedMove["location"]!["targetSettlementId"] = "safe-town";
        if (!IsInterruptedMapMove(dialogueEndedStoppedMove, "safe-town", moveStartPending: false))
            throw new AgentHostException("gold-sale-self-test-stale-native-target-blocks-replanning", "A stale Native target ID without isMoving must not keep the sale route from re-querying map targets.");
        var dialogueEndedMoving = MapState(null, null, []);
        dialogueEndedMoving["party"]!["isMoving"] = true;
        dialogueEndedMoving["location"]!["targetSettlementId"] = "safe-town";
        if (IsInterruptedMapMove(dialogueEndedMoving, "safe-town", moveStartPending: false))
            throw new AgentHostException("gold-sale-self-test-resumed-native-move-cleared", "Keep passively observing when the original Native travel target remains active after the conversation.");
        var disabledTradeMenu = MapState("town", "sargot", new JsonArray(new JsonObject { ["id"] = "trade", ["available"] = true, ["enabled"] = false }));
        if (BuildActionCatalog(disabledTradeMenu, null, null, null).Count != 0)
            throw new AgentHostException("gold-sale-self-test-disabled-trade-menu-leaked", "A disabled Native Trade menu entry must not become an agent action.");

        var nativeTownEncounter = MapState("town", "town_ES3", new JsonArray(new JsonObject { ["id"] = "trade", ["available"] = true, ["enabled"] = true }));
        nativeTownEncounter["context"]!["encounterActive"] = true;
        nativeTownEncounter["context"]!["encounteredPartyId"] = "town_ES3";
        nativeTownEncounter["context"]!["encounteredPartyName"] = "Poros";
        var townTradeEntry = BuildActionCatalog(nativeTownEncounter, null, null, null);
        if (townTradeEntry.Count != 1 || ReadString(townTradeEntry[0] as JsonObject, "action") != "menuSelect")
            throw new AgentHostException("gold-sale-self-test-native-town-menu-misclassified-as-hostile-encounter", "An active native settlement menu where encounteredPartyId equals currentSettlementId is the expected market entry, not a hostile battle to abort.");
        var nativeTrainingFieldMenu = MapState("training_field_menu", "tutorial_training_field", new JsonArray(
            new JsonObject { ["id"] = "training_field_leave", ["available"] = true, ["enabled"] = true, ["isLeave"] = true }));
        nativeTrainingFieldMenu["context"]!["encounterActive"] = true;
        nativeTrainingFieldMenu["context"]!["encounteredPartyId"] = "tutorial_training_field";
        var trainingFieldExit = BuildActionCatalog(nativeTrainingFieldMenu, null, null, null);
        var trainingFieldExitOption = trainingFieldExit.Count == 0 ? null : (trainingFieldExit[0]?["argumentValues"]?["OptionId"] as JsonArray)?[0]?.GetValue<string>();
        if (trainingFieldExit.Count != 1 || ReadString(trainingFieldExit[0] as JsonObject, "action") != "menuSelect" ||
            trainingFieldExitOption != "training_field_leave" || !IsFreeCampaignMap(nativeTrainingFieldMenu))
            throw new AgentHostException("gold-sale-self-test-training-field-menu-not-exitable", "The original Tutorial skip can leave the training-field Native location menu even though its context marks the location as an encounter.");
        var townBackstreetMenu = MapState("town_backstreet", "town_ES3", new JsonArray(
            new JsonObject { ["id"] = "town_tavern", ["available"] = true, ["enabled"] = true },
            new JsonObject { ["id"] = "town_backstreet_back", ["available"] = true, ["enabled"] = true, ["isLeave"] = true }));
        townBackstreetMenu["context"]!["encounterActive"] = true;
        townBackstreetMenu["context"]!["encounteredPartyId"] = "town_ES3";
        townBackstreetMenu["location"]!["targetSettlementId"] = "town_ES3";
        var townBackstreetCatalog = BuildActionCatalog(townBackstreetMenu, null, null, null);
        var townBackstreetExitOption = townBackstreetCatalog.Count == 0 ? null : (townBackstreetCatalog[0]?["argumentValues"]?["OptionId"] as JsonArray)?[0]?.GetValue<string>();
        if (townBackstreetCatalog.Count != 1 || ReadString(townBackstreetCatalog[0] as JsonObject, "action") != "menuSelect" ||
            townBackstreetExitOption != "town_backstreet_back" || !IsFreeCampaignMap(townBackstreetMenu) ||
            !TryResolveAction(townBackstreetMenu, null, townBackstreetCatalog, new JsonObject
            {
                ["action"] = "menuSelect",
                ["arguments"] = new JsonObject { ["MenuId"] = "town_backstreet", ["OptionId"] = "town_backstreet_back" }
            }, null, null, out var backstreetAction, out var backstreetArguments, out _) ||
            backstreetAction != "menuSelect" || ReadString(backstreetArguments, "menuId") != "town_backstreet" ||
            ReadString(backstreetArguments, "optionId") != "town_backstreet_back")
            throw new AgentHostException("gold-sale-self-test-town-backstreet-not-returnable", "When a prior target id still equals the current settlement, the currently enabled Native Town Backstreet Leave option must remain available so the Gold route can return to the main Town menu and reach Native Trade.");
        var backstreetWithSale = townBackstreetMenu.DeepClone().AsObject();
        backstreetWithSale["availableMenuOptions"]!.AsArray().Insert(0, new JsonObject { ["id"] = "sell_some_prisoners", ["available"] = true, ["enabled"] = true });
        var backstreetSaleCatalog = BuildActionCatalog(backstreetWithSale, null, null, null);
        if (backstreetSaleCatalog.Count != 1 || ReadString(backstreetSaleCatalog[0] as JsonObject, "action") != "menuSelect" ||
            (backstreetSaleCatalog[0]?["argumentValues"]?["OptionId"] as JsonArray)?.Count != 2)
            throw new AgentHostException("gold-sale-self-test-backstreet-prisoner-option-missing", "Offer the currently enabled prisoner-selection entry alongside the Native Leave option, without exposing full-sale or invented menu choices.");
        var ransomCancelReceipt = new JsonObject { ["action"] = "partyScreenCancel", ["status"] = "completed" };
        var backstreetAfterCancelCatalog = BuildActionCatalog(backstreetWithSale, ransomCancelReceipt, null, null);
        if (backstreetAfterCancelCatalog.Count != 1 || ReadString(backstreetAfterCancelCatalog[0] as JsonObject, "action") != "menuSelect" ||
            (backstreetAfterCancelCatalog[0]?["argumentValues"]?["OptionId"] as JsonArray)?.Any(value => value?.GetValue<string>() == "sell_some_prisoners") == true)
            throw new AgentHostException("gold-sale-self-test-ransom-cancel-reopened-same-sale", "After Native Ransom Cancel, do not re-enter the identical sale immediately; only current Backstreet Leave options remain available.");

        var ransomState = new JsonObject
        {
            ["context"] = new JsonObject { ["gameState"] = "PartyState", ["menuId"] = null, ["inquiryOpen"] = false, ["captivity"] = null },
            ["partyScreen"] = new JsonObject
            {
                ["mode"] = "Ransom", ["canDone"] = true, ["cancelAvailable"] = true, ["rightPartyId"] = "player_party", ["ransomGoldChangeAmount"] = 0,
                ["leftPrisoners"] = new JsonArray(),
                ["rightPrisoners"] = new JsonArray
                {
                    new JsonObject { ["troopId"] = "mounted_ransacker", ["count"] = 2, ["transferable"] = true },
                    new JsonObject { ["troopId"] = "mounted_pillager", ["count"] = 5, ["transferable"] = true }
                }
            }
        };
        var ransomCatalog = BuildActionCatalog(ransomState, null, null, null);
        var ransomTroopIds = ransomCatalog.FirstOrDefault()?["argumentValues"]?["TroopId"] as JsonArray;
        if (ransomCatalog.Count != 2 || !ransomCatalog.OfType<JsonObject>().Any(item => ReadString(item, "action") == "sellPrisonerOne") ||
            !ransomCatalog.OfType<JsonObject>().Any(item => ReadString(item, "action") == "partyScreenCancel") ||
            ransomTroopIds?.Count != 2 || ransomTroopIds[0]?.GetValue<string>() != "mounted_ransacker" ||
            !TryResolveAction(ransomState, null, ransomCatalog, new JsonObject
            {
                ["action"] = "sellPrisonerOne", ["arguments"] = new JsonObject { ["TroopId"] = "mounted_ransacker" }
            }, null, null, out var ransomAction, out var ransomArguments, out _) ||
            ransomAction != "sellPrisonerOne" || ReadString(ransomArguments, "troopId") != "mounted_ransacker")
            throw new AgentHostException("gold-sale-self-test-ransom-roster-scope-failed", "A Native Ransom screen must expose individual transferable MainParty prisoners, never a bulk sale.");
        var selectedRansomState = ransomState.DeepClone().AsObject();
        selectedRansomState["partyScreen"]!["leftPrisoners"] = new JsonArray(new JsonObject { ["troopId"] = "mounted_ransacker", ["count"] = 1 });
        selectedRansomState["partyScreen"]!["ransomGoldChangeAmount"] = 47d;
        var selectedRansomCatalog = BuildActionCatalog(selectedRansomState, null, null, null);
        if (!selectedRansomCatalog.OfType<JsonObject>().Any(item => ReadString(item, "action") == "partyScreenDone") ||
            !selectedRansomCatalog.OfType<JsonObject>().Any(item => ReadString(item, "action") == "partyScreenCancel") ||
            !selectedRansomCatalog.OfType<JsonObject>().Any(item => ReadString(item, "action") == "sellPrisonerOne"))
            throw new AgentHostException("gold-sale-self-test-ransom-draft-choice-missing", "A current Ransom draft must let the model observe its quote and choose to add a current prisoner, commit, or cancel.");
        if (!TryResolveAction(selectedRansomState, null, selectedRansomCatalog, new JsonObject
            {
                ["action"] = "partyScreenCancel", ["arguments"] = new JsonObject()
            }, null, null, out var cancelAction, out var cancelArguments, out _) ||
            cancelAction != "partyScreenCancel" || cancelArguments?.Count != 0)
            throw new AgentHostException("gold-sale-self-test-ransom-cancel-resolution-failed", "The Native Ransom cancel command must resolve only from the current cancel-enabled PartyState without additional arguments.");
        var zeroValueRansomState = selectedRansomState.DeepClone().AsObject();
        zeroValueRansomState["partyScreen"]!["ransomGoldChangeAmount"] = 0;
        var zeroValueRansomCatalog = BuildActionCatalog(zeroValueRansomState, null, null, null);
        if (zeroValueRansomCatalog.OfType<JsonObject>().Any(item => ReadString(item, "action") == "partyScreenDone") ||
            !zeroValueRansomCatalog.OfType<JsonObject>().Any(item => ReadString(item, "action") == "partyScreenCancel") ||
            !zeroValueRansomCatalog.OfType<JsonObject>().Any(item => ReadString(item, "action") == "sellPrisonerOne") ||
            TryResolveAction(zeroValueRansomState, null, selectedRansomCatalog, new JsonObject
            {
                ["action"] = "partyScreenDone", ["arguments"] = new JsonObject()
            }, null, null, out _, out _, out _))
            throw new AgentHostException("gold-sale-self-test-ransom-zero-value-commit-accepted", "A zero-value draft cannot be submitted, but the original Native Cancel must remain available to discard it.");
        var negativeValueRansomState = selectedRansomState.DeepClone().AsObject();
        negativeValueRansomState["partyScreen"]!["ransomGoldChangeAmount"] = -47d;
        if (BuildActionCatalog(negativeValueRansomState, null, null, null).OfType<JsonObject>().Any(item => ReadString(item, "action") == "partyScreenDone") ||
            TryResolveAction(negativeValueRansomState, null, selectedRansomCatalog, new JsonObject
            {
                ["action"] = "partyScreenDone", ["arguments"] = new JsonObject()
            }, null, null, out _, out _, out _))
            throw new AgentHostException("gold-sale-self-test-negative-ransom-commit-accepted", "A prisoner-sale draft that would reduce MainHero Gold must not expose Native Done.");
        var disabledRansomCancel = selectedRansomState.DeepClone().AsObject();
        disabledRansomCancel["partyScreen"]!["cancelAvailable"] = false;
        if (BuildActionCatalog(disabledRansomCancel, null, null, null).OfType<JsonObject>().Any(item => ReadString(item, "action") == "partyScreenCancel") ||
            TryResolveAction(disabledRansomCancel, null, selectedRansomCatalog, new JsonObject
            {
                ["action"] = "partyScreenCancel", ["arguments"] = new JsonObject()
            }, null, null, out _, out _, out _))
            throw new AgentHostException("gold-sale-self-test-ransom-disabled-cancel-exposed", "Do not expose Native Ransom Cancel when the current PartyVM says it is unavailable.");
        var townReachedAfterMovement = MapState("town", "town-a", new JsonArray(new JsonObject { ["id"] = "trade", ["available"] = true, ["enabled"] = true }));
        townReachedAfterMovement["location"]!["targetSettlementId"] = "town-a";
        if (!HasReachedMoveTargetMenu(townReachedAfterMovement, "town-a") || HasReachedMoveTargetMenu(townReachedAfterMovement, "town-b"))
            throw new AgentHostException("gold-sale-self-test-arrival-does-not-clear-native-move-target", "A completed move target may be cleared only after fresh Native location state confirms arrival and presents the settlement menu.");
        var emptyTradeTown = MapState("town", "town-a", new JsonArray(
            new JsonObject { ["id"] = "trade", ["available"] = true, ["enabled"] = true },
            new JsonObject { ["id"] = "town_leave", ["available"] = true, ["enabled"] = true, ["isLeave"] = true }));
        emptyTradeTown["context"]!["encounterActive"] = true;
        emptyTradeTown["context"]!["encounteredPartyId"] = "town-a";
        emptyTradeTown["location"]!["targetSettlementId"] = "town-a";
        var cancelReceipt = new JsonObject { ["action"] = "tradeCancel", ["status"] = "completed" };
        var emptyTradeCatalog = BuildActionCatalog(emptyTradeTown, cancelReceipt, null, null);
        var emptyTradeLeaveOption = emptyTradeCatalog.Count == 0 ? null : (emptyTradeCatalog[0]?["argumentValues"]?["OptionId"] as JsonArray)?[0]?.GetValue<string>();
        if (emptyTradeCatalog.Count != 1 || ReadString(emptyTradeCatalog[0] as JsonObject, "action") != "menuSelect" || emptyTradeLeaveOption != "town_leave" ||
            !TryResolveAction(emptyTradeTown, cancelReceipt, emptyTradeCatalog,
                new JsonObject { ["action"] = "menuSelect", ["arguments"] = new JsonObject { ["MenuId"] = "town", ["OptionId"] = "town_leave" } },
                null, null, out var emptyMarketAction, out _, out _) || emptyMarketAction != "menuSelect")
            throw new AgentHostException("gold-sale-self-test-empty-market-not-exitable", "After Native Trade returns no transferable Goods, expose and accept only the current Town's Native Leave option so the route can inspect another market.");
        var mapAfterTownLeave = MapState(null, null, []);
        mapAfterTownLeave["location"]!["targetSettlementId"] = "town-a";
        if (BuildActionCatalog(mapAfterTownLeave, null, null, null).Count != 0 ||
            ReadString(BuildActionCatalog(mapAfterTownLeave, null, null, null, allowMapAfterNativeTownLeave: true)[0] as JsonObject, "action") != "mapSettlementTargets")
            throw new AgentHostException("gold-sale-self-test-native-town-leave-stale-target-blocked-map", "Only after a verified Native Town Leave may a stale targetSettlementId equal to the departed Town be ignored for a fresh map-target query.");
        var hostileEncounter = MapState("encounter", null, []);
        hostileEncounter["context"]!["encounterActive"] = true;
        hostileEncounter["context"]!["encounteredPartyId"] = "bandit_party";
        if (BuildActionCatalog(hostileEncounter, null, null, null).Count != 0)
            throw new AgentHostException("gold-sale-self-test-hostile-encounter-not-blocked", "An active non-settlement encounter must remain outside the bounded Gold trade subflow.");

        return [
            new { scenario = "gold-sale-offers-only-current-enabled-town-trade-entry", passed = true },
            new { scenario = "gold-sale-binds-one-current-native-goods-offer-and-positive-quote", passed = true },
            new { scenario = "gold-sale-native-move-start-transition-uses-one-bounded-observation", passed = true },
            new { scenario = "gold-sale-rejects-stale-offers-unsafe-targets-and-disabled-native-options", passed = true },
            new { scenario = "gold-sale-allows-native-town-menu-and-training-field-exit-but-rejects-hostile-party-encounter", passed = true },
            new { scenario = "gold-sale-returns-through-current-native-town-backstreet-leave-before-trading", passed = true }
        ];
    }

    internal static async Task<IReadOnlyList<object>> RunFailureTransportSelfTestsAsync()
    {
        var client = new FakeGoldSaleFailureNativeClient();
        var provider = new FakeGoldSaleFailureProvider();
        using var request = JsonDocument.Parse("{\"runId\":\"gold-sale-failure-receipt-selftest\",\"goal\":\"Raise Gold Journal progress with one Native sale.\",\"maxDecisions\":6,\"maxElapsedSeconds\":30}");
        var result = await RunAsync(request.RootElement, client, client, provider, CancellationToken.None);
        var trace = result["trace"] as JsonArray;
        var routeHistory = result["providerRouteHistory"] as JsonArray;
        var failedRoute = routeHistory?.OfType<JsonObject>().LastOrDefault();
        var firstAction = trace?.OfType<JsonObject>().Select(step => step["actionReceipt"] as JsonObject).FirstOrDefault(receipt => receipt is not null);
        var rejectedDecisionRecorded = trace?.OfType<JsonObject>().Any(step =>
            ReadString(step, "stage") == "decision-rejected-before-native" &&
            ReadString(step, "rejectionCode") == "provider-arguments-invalid-json" &&
            ReadBoolean(step, "nativeActionSent") == false &&
            step["allowedActionNames"] is JsonArray names && names.Count == 1 && names[0]?.GetValue<string>() == "mapSettlementTargets") == true;
        var compactTargetCandidates = provider.LastRequest?["previousActionReceipt"]?["data"]?["mapSettlementTargets"] as JsonArray;
        var compactTargetArgumentValues = provider.LastRequest?["allowedActions"]?[0]?["argumentValues"]?["SettlementId"] as JsonArray;
        var rawMapReceipt = trace?.OfType<JsonObject>()
            .Select(step => step["actionReceipt"] as JsonObject)
            .FirstOrDefault(receipt => ReadString(receipt, "action") == "mapSettlementTargets");
        var rawTargetCandidates = rawMapReceipt?["data"]?["mapSettlementTargets"] as JsonArray;
        if (ReadString(result, "status") != "failed" || ReadString(result, "failureCode") != "provider-http-error" ||
            ReadInt(result, "actionsExecuted", 0) != 1 || trace?.Count != 2 || ReadString(firstAction, "action") != "mapSettlementTargets" ||
            ReadString(failedRoute, "failureCode") != "provider-http-error" || client.MapTargetQueries != 1 ||
            provider.CallCount != 3 || provider.IsDisposed || !provider.FeedbackObserved || !rejectedDecisionRecorded ||
            compactTargetCandidates?.Count != 12 || compactTargetArgumentValues?.Count != 12 || rawTargetCandidates?.Count != 18 ||
            compactTargetCandidates.OfType<JsonObject>().Any(target => ReadString(target, "type") != "town" || ReadBoolean(target, "hostile") || ReadBoolean(target, "underSiege")))
            throw new AgentHostException("gold-sale-failure-receipt-selftest-failed", "The Host must correct malformed arguments before Native, preserve the full Native map receipt in trace, send only the current safe Town candidates to the model, preserve a later transport failure without replay, and leave the borrowed provider alive for its Campaign parent.");
        return [new { scenario = "gold-sale-compacts-safe-town-targets-and-does-not-dispose-the-borrowed-campaign-provider", passed = true }];
    }

    internal static async Task<JsonObject> RunAsync(
        JsonElement request,
        IAgentHostCampaignNativeClient stateClient,
        IAgentHostGoldSaleNativeClient actionClient,
        IAgentHostDecisionProvider provider,
        CancellationToken cancellationToken,
        int priorDecisions = 0,
        long priorPromptTokens = 0,
        long priorCompletionTokens = 0,
        JsonArray? priorTrace = null,
        JsonArray? priorProviderRouteHistory = null)
    {
        var runId = ReadString(request, "runId") ?? Guid.NewGuid().ToString("N");
        var maxDecisions = Math.Clamp(ReadInt(request, "maxDecisions", AgentHostCampaignLoop.MaxCumulativeDecisions), 1, AgentHostCampaignLoop.MaxCumulativeDecisions);
        var maxElapsedSeconds = Math.Clamp(ReadInt(request, "maxElapsedSeconds", 1800), 10, 7200);
        using var elapsed = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        elapsed.CancelAfter(TimeSpan.FromSeconds(maxElapsedSeconds));
        var trace = priorTrace?.DeepClone() as JsonArray ?? new JsonArray();
        var routeHistory = priorProviderRouteHistory?.DeepClone() as JsonArray ?? new JsonArray();
        var decisionCount = priorDecisions;
        var actionCount = 0;
        var saleActionCount = 0;
        var noTransferableGoodsInPlayerInventory = false;
        long promptTokens = priorPromptTokens;
        long completionTokens = priorCompletionTokens;
        string? moveTargetId = null;
        var moveStartPending = false;
        var rejectedProviderDecisions = 0;
        JsonArray? safeTowns = null;
        var visitedTowns = new HashSet<string>(StringComparer.Ordinal);
        var allowMapAfterNativeTownLeave = false;
        JsonObject? previousReceipt = null;
        JsonObject? decisionFeedback = null;
        JsonObject? saleReceipt = null;
        JsonObject? initialNative = null;
        JsonObject? currentNative = null;
        JsonObject? objectiveSnapshotBefore = null;
        JsonArray? liveMetricDifferencesBefore = null;
        JsonObject? objectiveSnapshotAfter = null;
        JsonArray? liveMetricDifferencesAfter = null;
        double campaignDayBefore = double.NaN;
        string? timeControlModeBefore = null;
        JsonObject? initialCaptivityRecovery = null;

        try
        {
            // The Campaign Host owns the shared decision provider. This objective
            // borrows it; disposing it here would break the parent's next plan call.
            await provider.CheckConfiguredModelAsync(elapsed.Token);
            using (var initial = await stateClient.ReadStateAsync(elapsed.Token)) initialNative = ParseObject(initial.RootElement);
            currentNative = initialNative.DeepClone() as JsonObject ?? throw new AgentHostException("gold-sale-initial-state-invalid", "Native returned no initial Campaign state.");
            campaignDayBefore = ReadDouble(currentNative, "campaignDay", double.NaN);
            timeControlModeBefore = ReadString(currentNative, "timeControlMode");

            var initialState = currentNative["state"] as JsonObject ?? new JsonObject();
            if (ReadString(initialState["storyModeEstablishClanStatus"] as JsonObject, "status") != "active" || !HasActiveQuest(initialState))
                throw new AgentHostException("gold-sale-active-storymode-quest-required", "W7-P requires the exact active original Establish Your Clan quest before any model decision or sale.");

            if (ReadBoolean((initialState["context"] as JsonObject)?["captivity"] as JsonObject, "isCaptive"))
            {
                initialCaptivityRecovery = await AgentHostCaptivityRecoveryLoop.RunAsync(
                    request, stateClient, actionClient, actionClient, provider, elapsed.Token,
                    priorDecisions: decisionCount,
                    priorPromptTokens: promptTokens,
                    priorCompletionTokens: completionTokens,
                    priorTrace: trace,
                    priorProviderRouteHistory: routeHistory);
                if (ReadString(initialCaptivityRecovery, "resultKind") != "captivity-recovered-objective-plan" ||
                    ReadBoolean(initialCaptivityRecovery, "captivityRecoveryVerified") != true)
                    throw new AgentHostException("gold-sale-captivity-prelude-failed", "The original W7-O recovery flow did not return a verified free Campaign Map; no sale action was attempted.");
                decisionCount = ReadInt(initialCaptivityRecovery, "decisions", decisionCount);
                promptTokens = ReadLong(initialCaptivityRecovery, "promptTokens", promptTokens);
                completionTokens = ReadLong(initialCaptivityRecovery, "completionTokens", completionTokens);
                routeHistory = initialCaptivityRecovery["providerRouteHistory"]?.DeepClone() as JsonArray ?? routeHistory;
                trace = initialCaptivityRecovery["trace"]?.DeepClone() as JsonArray ?? trace;
                currentNative = initialCaptivityRecovery["finalNativeState"]?.DeepClone() as JsonObject
                    ?? throw new AgentHostException("gold-sale-captivity-final-state-missing", "W7-O returned no fresh final Native state for the gold sale loop.");
                previousReceipt = new JsonObject { ["action"] = "captivityRecovery", ["status"] = "completed", ["resultKind"] = "captivity-recovered-objective-plan" };
            }

            var postRecoveryState = currentNative["state"] as JsonObject ?? new JsonObject();
            if (!IsFreeCampaignMap(postRecoveryState))
                throw new AgentHostException("gold-sale-free-map-required", "The Gold sale slice requires a free Campaign Map after any approved Captivity recovery.");
            if (!HasActiveQuest(postRecoveryState) || ReadString(postRecoveryState["storyModeEstablishClanStatus"] as JsonObject, "status") != "active")
                throw new AgentHostException("gold-sale-storymode-quest-no-longer-active", "The exact original StoryMode quest is no longer active after recovery.");

            using var beforeDetails = await actionClient.ReadQuestDetailsAsync(QuestId, elapsed.Token);
            (objectiveSnapshotBefore, liveMetricDifferencesBefore) = ReadGoldJournal(beforeDetails.RootElement);
            var goldBefore = objectiveSnapshotBefore["gold"] as JsonObject
                ?? throw new AgentHostException("gold-sale-journal-gold-objective-missing", "The current original Journal did not expose its Gold objective.");
            if (ReadBoolean(goldBefore, "met") == true)
                throw new AgentHostException("gold-sale-objective-already-met", "The official Journal Gold objective is already met; no sale was performed.");

            for (var iteration = 1; decisionCount < maxDecisions; iteration++)
            {
                elapsed.Token.ThrowIfCancellationRequested();
                var state = currentNative["state"] as JsonObject ?? throw new AgentHostException("gold-sale-state-missing", "Native returned no Campaign state.");
                if (IsActiveEncounter(state) || ReadBoolean((state["context"] as JsonObject)?["captivity"] as JsonObject, "isCaptive"))
                    throw new AgentHostException("gold-sale-encounter-out-of-scope", "A new encounter or Captivity interrupted the sale path; no battle or unverified recovery was started.");

                if (IsInterruptedMapMove(state, moveTargetId, moveStartPending))
                {
                    // A Native map conversation can interrupt and clear an issued move. Do not
                    // keep waiting on a stale target; re-query current safe Towns after it ends.
                    moveTargetId = null;
                    safeTowns = null;
                }

                if (HasReachedMoveTargetMenu(state, moveTargetId))
                {
                    moveTargetId = null;
                    moveStartPending = false;
                }

                var actionCatalog = BuildActionCatalog(state, previousReceipt, safeTowns, moveTargetId, allowMapAfterNativeTownLeave);
                var controls = BuildControlCatalog(state, moveTargetId, moveStartPending);
                if (actionCatalog.Count == 0 && controls.Count == 0)
                {
                    var currentSettlementId = ReadString(state["location"] as JsonObject, "currentSettlementId");
                    var noUnvisitedSafeMarket = visitedTowns.Count > 0 && safeTowns is { Count: 0 } && string.IsNullOrWhiteSpace(currentSettlementId);
                    throw new AgentHostException(noUnvisitedSafeMarket ? "gold-sale-no-transferable-goods" : "gold-sale-no-safe-native-action",
                        noUnvisitedSafeMarket
                            ? "The current visible safe Town candidates have been exhausted and no Native transferable Goods offer was found; Gold did not advance."
                            : DescribeNoAction(state, previousReceipt));
                }

                var observation = BuildObservation(currentNative, state, objectiveSnapshotBefore, liveMetricDifferencesBefore, saleReceipt);
                var providerPreviousReceipt = BuildProviderPreviousReceipt(previousReceipt, safeTowns);
                var modelRequest = BuildDecisionRequest(runId, ReadString(request, "goal"), iteration + decisionCount,
                    observation, providerPreviousReceipt, decisionFeedback, actionCatalog, controls, moveStartPending);
                var started = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                var startedTicks = Stopwatch.GetTimestamp();
                ProviderDecisionResult modelDecision;
                try
                {
                    modelDecision = await AgentHostDecisionCycle.DecideEstablishClanGoldSaleAsync(provider, modelRequest, elapsed.Token);
                }
                catch (AgentHostException exception) when (AgentHostProviderDecisionRecovery.CanRetry(exception.Code, rejectedProviderDecisions))
                {
                    decisionCount++;
                    rejectedProviderDecisions++;
                    decisionFeedback = AgentHostProviderDecisionRecovery.BuildFeedback(exception.Code, actionCatalog, controls);
                    trace.Add(new JsonObject
                    {
                        ["iteration"] = decisionCount,
                        ["stage"] = "decision-rejected-before-native",
                        ["rejectionCode"] = exception.Code,
                        ["nativeActionSent"] = false,
                        ["allowedActionNames"] = AgentHostProviderDecisionRecovery.CurrentActionNames(actionCatalog),
                        ["allowedControls"] = controls.DeepClone(),
                        ["feedback"] = decisionFeedback.DeepClone()
                    });
                    continue;
                }
                decisionCount++;
                rejectedProviderDecisions = 0;
                decisionFeedback = null;
                promptTokens += modelDecision.PromptTokens ?? 0;
                completionTokens += modelDecision.CompletionTokens ?? 0;
                routeHistory.Add(new JsonObject
                {
                    ["decision"] = decisionCount,
                    ["requestedModelId"] = provider.ModelId,
                    ["responseModelId"] = modelDecision.ModelId,
                    ["routedVia"] = modelDecision.RoutedVia,
                    ["responseFormatMode"] = modelDecision.ResponseFormatMode,
                    ["promptTokens"] = modelDecision.PromptTokens,
                    ["completionTokens"] = modelDecision.CompletionTokens
                });

                if (ReadBoolean(modelDecision.Decision, "observeAgain"))
                {
                    if (!controls.Any(control => control?.GetValue<string>() == "observeAgain"))
                        throw new AgentHostException("gold-sale-observe-not-allowed", "The Host cannot wait unless the current Native state confirms movement or settlement arrival pending.");
                    var seconds = ReadInt(modelDecision.Decision, "waitSeconds", 0);
                    var minimumWait = GetMinimumObserveInterval(moveStartPending);
                    if (!IsSupportedObserveInterval(seconds, moveStartPending))
                        throw new AgentHostException("gold-sale-observe-interval-invalid", $"observeAgain requires a {minimumWait}-10 second Host poll in the current Native map-movement state.");
                    await Task.Delay(TimeSpan.FromSeconds(seconds), elapsed.Token);
                    using var afterWait = await stateClient.ReadStateAsync(elapsed.Token);
                    currentNative = ParseObject(afterWait.RootElement);
                    if (moveStartPending) moveStartPending = false;
                    trace.Add(BuildStep(decisionCount, observation, modelDecision.Decision, null, started, startedTicks,
                        new JsonObject { ["kind"] = "bounded-host-observation", ["waitSeconds"] = seconds },
                        BuildObservation(currentNative, currentNative["state"] as JsonObject ?? new JsonObject(), objectiveSnapshotBefore, liveMetricDifferencesBefore, saleReceipt)));
                    continue;
                }

                if (!TryResolveAction(state, previousReceipt, actionCatalog, modelDecision.Decision, safeTowns, moveTargetId,
                    out var action, out var arguments, out var rejection))
                    throw new AgentHostException("gold-sale-model-action-invalid", rejection ?? "The model did not choose a current allowed Native sale action.");

                using var actionResponse = await actionClient.ExecuteGoldSaleActionAsync(action!, arguments!, elapsed.Token);
                var receipt = ParseObject(actionResponse.RootElement);
                actionCount++;
                if (ReadString(receipt, "status") != "completed")
                    throw new AgentHostException("gold-sale-native-action-rejected", $"Native rejected the current {action} action; no replay was attempted.");

                if (action == "mapSettlementTargets") safeTowns = FilterSafeTowns(receipt, visitedTowns);
                if (action == "move")
                {
                    moveTargetId = ReadMoveTargetId(arguments);
                    moveStartPending = moveTargetId is not null;
                    allowMapAfterNativeTownLeave = false;
                }
                if (action == "menuSelect" && ReadString(arguments, "menuId") == "town" && ReadString(arguments, "optionId") == "town_leave")
                {
                    var exitedSettlementId = ReadString(state["location"] as JsonObject, "currentSettlementId");
                    if (!string.IsNullOrWhiteSpace(exitedSettlementId)) visitedTowns.Add(exitedSettlementId);
                    moveTargetId = null;
                    moveStartPending = false;
                    safeTowns = null;
                    allowMapAfterNativeTownLeave = true;
                }
                if (action == "trade")
                {
                    var data = receipt["data"] as JsonObject ?? new JsonObject();
                    if (ReadBoolean(data, "nativeCanCompleteTransaction") != true ||
                        ReadString(data, "direction") != "sell" || ReadInt(data, "amount", 0) != 1 ||
                        ReadString(data, "inventorySide") != "PlayerInventory")
                        throw new AgentHostException("gold-sale-native-draft-invalid", "The Native Trade handler did not produce the expected one-unit sell draft.");
                }
                if (action == "tradeOptions")
                    noTransferableGoodsInPlayerInventory = !HasTransferableGoodsInventory(receipt);
                if (action == "tradeConfirm")
                {
                    var data = receipt["data"] as JsonObject ?? new JsonObject();
                    if (ReadBoolean(data, "postconditionPassed") != true || ReadString(data, "direction") != "sell" ||
                        ReadInt(data, "amount", 0) != 1 || ReadInt(data, "playerGoldAfter", 0) <= ReadInt(data, "playerGoldBefore", 0) ||
                        ReadInt(data, "playerCountAfter", -1) != ReadInt(data, "playerCountBefore", -1) - 1 ||
                        ReadString(data, "timeControlModeBefore") != ReadString(data, "timeControlModeAfter") ||
                        Math.Abs(ReadDouble(data, "campaignDayBefore", double.NaN) - ReadDouble(data, "campaignDayAfter", double.NaN)) > 0.000001 ||
                        ReadInt(data, "playerGoldAfter", 0) - ReadInt(data, "playerGoldBefore", 0) != Math.Abs(ReadInt(data, "nativeTransactionAmount", 0)))
                        throw new AgentHostException("gold-sale-native-commit-unverified", "Native Trade did not confirm a positive one-unit sale with matching Gold and inventory deltas.");
                    saleReceipt = data.DeepClone() as JsonObject;
                    saleActionCount++;
                }
                if (action == "sellPrisonerOne")
                {
                    var data = receipt["data"] as JsonObject ?? new JsonObject();
                    if (ReadInt(data, "transferredCount", 0) != 1 ||
                        ReadInt(data, "sourceCountAfter", -1) != ReadInt(data, "sourceCountBefore", -1) - 1 ||
                        ReadInt(data, "saleCountAfter", -1) != ReadInt(data, "saleCountBefore", -1) + 1)
                        throw new AgentHostException("gold-sale-ransom-native-draft-invalid", "Native did not move exactly one selected prisoner into the current Ransom draft.");
                }
                if (action == "partyScreenDone")
                {
                    var data = receipt["data"] as JsonObject ?? new JsonObject();
                    if (ReadBoolean(data, "postconditionPassed") != true || ReadInt(data, "playerGoldAfter", 0) <= ReadInt(data, "playerGoldBefore", 0) ||
                        ReadInt(data, "prisonerCountAfter", -1) != ReadInt(data, "prisonerCountBefore", -1) - ReadInt(data, "selectedCount", 0) ||
                        ReadString(data, "timeControlModeBefore") != ReadString(data, "timeControlModeAfter") ||
                        Math.Abs(ReadDouble(data, "campaignDayBefore", double.NaN) - ReadDouble(data, "campaignDayAfter", double.NaN)) > 0.000001)
                        throw new AgentHostException("gold-sale-ransom-native-commit-unverified", "Native Ransom Done did not prove a positive Gold gain, exact prisoner removal, and unchanged Campaign time state.");
                    saleReceipt = data.DeepClone() as JsonObject;
                    saleActionCount++;
                }
                if (action == "partyScreenCancel")
                {
                    var data = receipt["data"] as JsonObject ?? new JsonObject();
                    if (ReadBoolean(data, "postconditionPassed") != true ||
                        ReadInt(data, "playerGoldAfter", -1) != ReadInt(data, "playerGoldBefore", -2) ||
                        ReadInt(data, "prisonerCountAfter", -1) != ReadInt(data, "prisonerCountBefore", -2) ||
                        ReadBoolean(data, "partyScreenClosed") != true ||
                        ReadString(data, "timeControlModeBefore") != ReadString(data, "timeControlModeAfter") ||
                        Math.Abs(ReadDouble(data, "campaignDayBefore", double.NaN) - ReadDouble(data, "campaignDayAfter", double.NaN)) > 0.000001)
                        throw new AgentHostException("gold-sale-ransom-cancel-unverified", "Native Cancel did not prove it discarded the current Ransom draft without Gold, prisoner, time or page-close side effects.");
                }

                previousReceipt = BuildReceipt(action!, arguments!, receipt);
                using (var fresh = await stateClient.ReadStateAsync(elapsed.Token)) currentNative = ParseObject(fresh.RootElement);
                trace.Add(BuildStep(decisionCount, observation, modelDecision.Decision, previousReceipt, started, startedTicks, null,
                    BuildObservation(currentNative, currentNative["state"] as JsonObject ?? new JsonObject(), objectiveSnapshotBefore, liveMetricDifferencesBefore, saleReceipt)));

                if (action == "menuSelect" && ReadString(arguments, "menuId") == "town" && ReadString(arguments, "optionId") == "town_leave" &&
                    noTransferableGoodsInPlayerInventory)
                    throw new AgentHostException("gold-sale-no-transferable-goods", "The complete Native PlayerInventory quote contained no transferable Goods; changing Town cannot make a bound or quest item sellable, so the Gold route stopped after Native Town leave instead of visiting more markets.");

                if (saleReceipt is not null)
                {
                    var finalState = currentNative["state"] as JsonObject ?? new JsonObject();
                    if (!IsFreeCampaignMap(finalState) || !HasActiveQuest(finalState))
                        throw new AgentHostException("gold-sale-final-map-or-quest-invalid", "After the sale, Native did not return to a free Map with the original StoryMode quest still active.");
                    using var afterDetails = await actionClient.ReadQuestDetailsAsync(QuestId, elapsed.Token);
                    (objectiveSnapshotAfter, liveMetricDifferencesAfter) = ReadGoldJournal(afterDetails.RootElement);
                    var beforeGold = objectiveSnapshotBefore["gold"] as JsonObject;
                    var afterGold = objectiveSnapshotAfter["gold"] as JsonObject;
                    if (ReadDouble(afterGold, "current", double.MinValue) <= ReadDouble(beforeGold, "current", double.MaxValue))
                        throw new AgentHostException("gold-sale-journal-not-increased", "Native proved the transaction, but the original Quest Journal Gold progress did not advance; no further sale was attempted.");
                    return BuildSuccess(runId, provider, initialNative, currentNative, objectiveSnapshotBefore, objectiveSnapshotAfter,
                        liveMetricDifferencesBefore, liveMetricDifferencesAfter, saleReceipt, previousReceipt, trace, routeHistory,
                        decisionCount, actionCount, saleActionCount, promptTokens, completionTokens, campaignDayBefore,
                        timeControlModeBefore, initialCaptivityRecovery);
                }
            }
        throw new AgentHostException("gold-sale-budget-exhausted", "The bounded Native Gold sale loop did not complete one verified positive sale.");
        }
        catch (OperationCanceledException)
        {
            return BuildFailure(cancellationToken.IsCancellationRequested ? "host-stop-requested" : "gold-sale-timeout",
                cancellationToken.IsCancellationRequested ? "The Host stop signal ended the Gold sale objective without claiming progress." : "The bounded Gold sale objective exceeded its elapsed-time limit.");
        }
        catch (AgentHostException exception)
        {
            return BuildFailure(exception.Code, exception.Message);
        }
        catch (Exception exception)
        {
            return BuildFailure("gold-sale-unexpected-error", exception.GetType().Name);
        }

        JsonObject BuildFailure(string code, string message)
        {
            routeHistory.Add(new JsonObject
            {
                ["decision"] = decisionCount + 1,
                ["requestedModelId"] = provider.ModelId,
                ["status"] = "failed-before-valid-decision",
                ["failureCode"] = code,
                ["failureSummary"] = message.Length > 240 ? message[..240] : message
            });
            var recoveryActions = ReadInt(initialCaptivityRecovery, "actionsExecuted", 0);
            return new JsonObject
            {
                ["status"] = "failed",
                ["resultKind"] = "establish-clan-gold-sale",
                ["runId"] = runId,
                ["providerModelId"] = provider.ModelId,
                ["providerConfigurationSource"] = provider.ConfigurationSource,
                ["decisions"] = decisionCount,
                ["actionsExecuted"] = recoveryActions + actionCount,
                ["saleActionsExecuted"] = saleActionCount,
                ["promptTokens"] = promptTokens,
                ["completionTokens"] = completionTokens,
                ["providerRouteHistory"] = routeHistory.DeepClone(),
                ["initialNativeState"] = initialNative?.DeepClone(),
                ["finalNativeState"] = currentNative?.DeepClone(),
                ["initialCaptivityRecovery"] = initialCaptivityRecovery?.DeepClone(),
                ["objectiveSnapshotBefore"] = objectiveSnapshotBefore?.DeepClone(),
                ["objectiveSnapshotAfter"] = objectiveSnapshotAfter?.DeepClone(),
                ["saleReceipt"] = saleReceipt?.DeepClone(),
                ["trace"] = trace.DeepClone(),
                ["termination"] = new JsonObject { ["reason"] = code, ["completedByProvider"] = false, ["goalVerified"] = false },
                ["failure"] = message,
                ["failureCode"] = code
            };
        }
    }

    private static JsonArray BuildActionCatalog(JsonObject state, JsonObject? previousReceipt, JsonArray? safeTowns, string? moveTargetId,
        bool allowMapAfterNativeTownLeave = false)
    {
        var context = state["context"] as JsonObject;
        var gameState = ReadString(context, "gameState");
        var ransomSaleState = gameState == "PartyState" && ReadString(state["partyScreen"] as JsonObject, "mode") == "Ransom" &&
            ReadString(state["partyScreen"] as JsonObject, "rightPartyId") == "player_party";
        if (ReadBoolean(context?["captivity"] as JsonObject, "isCaptive") || (!ransomSaleState && IsActiveEncounter(state)) ||
            ReadBoolean(context, "escapeMenuOpen") || ReadBoolean(context, "inquiryOpen")) return new JsonArray();
        if (gameState == "InventoryState")
        {
            var inventory = state["inventoryScreen"] as JsonObject;
            if (ReadString(inventory, "mode") != "Trade") return new JsonArray();
            var previousAction = ReadString(previousReceipt, "action");
            if (previousAction == "trade" && ReadString(previousReceipt, "status") == "completed")
                return ReadBoolean(previousReceipt?["data"] as JsonObject, "nativeCanCompleteTransaction")
                    ? new JsonArray(new JsonObject { ["action"] = "tradeConfirm", ["arguments"] = new JsonArray() })
                    : new JsonArray(new JsonObject { ["action"] = "tradeCancelChanges", ["arguments"] = new JsonArray() });
            if (previousAction == "tradeOptions" && ReadString(previousReceipt, "status") == "completed")
            {
                var offers = GetSellableGoods(previousReceipt);
                if (offers.Length == 0) return new JsonArray(new JsonObject { ["action"] = "tradeCancel", ["arguments"] = new JsonArray() });
                var itemIds = new JsonArray(offers.Select(offer => (JsonNode?)JsonValue.Create(ReadString(offer, "viewModelItemId"))).ToArray());
                return new JsonArray(new JsonObject
                {
                    ["action"] = "trade",
                    ["arguments"] = new JsonArray("Direction", "ItemViewModelId", "InventorySide", "Amount"),
                    ["argumentValues"] = new JsonObject
                    {
                        ["Direction"] = new JsonArray("sell"),
                        ["ItemViewModelId"] = itemIds,
                        ["InventorySide"] = new JsonArray("PlayerInventory"),
                        ["Amount"] = new JsonArray(1)
                    }
                });
            }
            if (ReadBoolean(inventory, "hasPendingChanges")) return new JsonArray();
            return new JsonArray(new JsonObject { ["action"] = "tradeOptions", ["arguments"] = new JsonArray() });
        }
        if (gameState == "PartyState")
        {
            var screen = state["partyScreen"] as JsonObject;
            if (screen is null || ReadString(screen, "mode") != "Ransom" || ReadString(screen, "rightPartyId") != "player_party") return new JsonArray();
            var rightRows = screen["rightPrisoners"] as JsonArray;
            var leftRows = screen["leftPrisoners"] as JsonArray;
            var selected = CountRoster(leftRows);
            var goldDraft = ReadDouble(screen, "ransomGoldChangeAmount", 0);
            var ransomIds = rightRows?.OfType<JsonObject>().Where(row => ReadBoolean(row, "transferable") && ReadInt(row, "count", 0) > 0)
                .Select(row => ReadString(row, "troopId")).Where(id => !string.IsNullOrWhiteSpace(id)).Distinct(StringComparer.Ordinal).ToArray()
                ?? Array.Empty<string>();
            var actions = new JsonArray();
            if (ransomIds.Length > 0)
            {
                actions.Add(new JsonObject
                {
                    ["action"] = "sellPrisonerOne", ["arguments"] = new JsonArray("TroopId"),
                    ["argumentValues"] = new JsonObject { ["TroopId"] = new JsonArray(ransomIds.Select(id => (JsonNode?)JsonValue.Create(id)).ToArray()) }
                });
            }
            if (selected > 0 && goldDraft > 0 && ReadBoolean(screen, "canDone"))
                actions.Add(new JsonObject { ["action"] = "partyScreenDone", ["arguments"] = new JsonArray() });
            if (ReadBoolean(screen, "cancelAvailable"))
                actions.Add(new JsonObject { ["action"] = "partyScreenCancel", ["arguments"] = new JsonArray() });
            return actions;
        }
        if (gameState != "MapState") return new JsonArray();
        if (IsMapConversationActive(state)) return BuildMapConversationActionCatalog(state);
        if (moveTargetId is not null && !string.Equals(ReadString(state["location"] as JsonObject, "currentSettlementId"), moveTargetId, StringComparison.Ordinal))
            return new JsonArray();
        var location = state["location"] as JsonObject;
        var currentSettlementId = ReadString(location, "currentSettlementId");
        var targetSettlementId = ReadString(location, "targetSettlementId");
        if (moveTargetId is null &&
            (ReadBoolean(state["party"] as JsonObject, "isMoving") ||
             (!allowMapAfterNativeTownLeave && !string.Equals(targetSettlementId, currentSettlementId, StringComparison.Ordinal) &&
              !string.IsNullOrWhiteSpace(targetSettlementId)))) return new JsonArray();
        var menuId = ReadString(context, "menuId");
        if (!string.IsNullOrWhiteSpace(menuId))
        {
            if (menuId == "town" && ReadString(previousReceipt, "action") == "tradeCancel" && ReadString(previousReceipt, "status") == "completed")
            {
                var townLeaveOptions = GetEnabledOptions(state).OfType<JsonObject>()
                    .Where(option => ReadBoolean(option, "isLeave"))
                    .Select(option => ReadString(option, "id"))
                    .Where(id => !string.IsNullOrWhiteSpace(id)).Distinct(StringComparer.Ordinal).ToArray();
                if (townLeaveOptions.Length == 0) return new JsonArray();
                return new JsonArray(new JsonObject
                {
                    ["action"] = "menuSelect", ["arguments"] = new JsonArray("MenuId", "OptionId"),
                    ["argumentValues"] = new JsonObject { ["MenuId"] = new JsonArray("town"), ["OptionId"] = new JsonArray(townLeaveOptions.Select(id => (JsonNode?)JsonValue.Create(id)).ToArray()) }
                });
            }
            if (menuId != "town")
            {
                if (!AgentHostCampaignStateFacts.IsNativeLocationMenu(state)) return new JsonArray();
                if (menuId == "town_backstreet")
                {
                    var cancelJustReturned = ReadString(previousReceipt, "action") == "partyScreenCancel" && ReadString(previousReceipt, "status") == "completed";
                    var entries = GetEnabledOptions(state).OfType<JsonObject>()
                        .Where(option => (!cancelJustReturned && ReadString(option, "id") == "sell_some_prisoners") || ReadBoolean(option, "isLeave"))
                        .Select(option => ReadString(option, "id")).Where(id => !string.IsNullOrWhiteSpace(id))
                        .Distinct(StringComparer.Ordinal).ToArray();
                    if (entries.Contains("sell_some_prisoners", StringComparer.Ordinal))
                        return new JsonArray(new JsonObject
                        {
                            ["action"] = "menuSelect", ["arguments"] = new JsonArray("MenuId", "OptionId"),
                            ["argumentValues"] = new JsonObject { ["MenuId"] = new JsonArray("town_backstreet"), ["OptionId"] = new JsonArray(entries.Select(id => (JsonNode?)JsonValue.Create(id)).ToArray()) }
                        });
                }
                var leaveOptions = GetEnabledOptions(state).OfType<JsonObject>()
                    .Where(option => ReadBoolean(option, "isLeave"))
                    .Select(option => ReadString(option, "id"))
                    .Where(id => !string.IsNullOrWhiteSpace(id)).Distinct(StringComparer.Ordinal).ToArray();
                if (leaveOptions.Length == 0) return new JsonArray();
                return new JsonArray(new JsonObject
                {
                    ["action"] = "menuSelect", ["arguments"] = new JsonArray("MenuId", "OptionId"),
                    ["argumentValues"] = new JsonObject { ["MenuId"] = new JsonArray(menuId), ["OptionId"] = new JsonArray(leaveOptions.Select(id => (JsonNode?)JsonValue.Create(id)).ToArray()) }
                });
            }
            var tradeOptions = GetEnabledOptions(state).OfType<JsonObject>().Where(option => ReadString(option, "id") == "trade").ToArray();
            if (tradeOptions.Length == 0) return new JsonArray();
            return new JsonArray(new JsonObject
            {
                ["action"] = "menuSelect", ["arguments"] = new JsonArray("MenuId", "OptionId"),
                ["argumentValues"] = new JsonObject { ["MenuId"] = new JsonArray("town"), ["OptionId"] = new JsonArray("trade") }
            });
        }
        if (!string.IsNullOrWhiteSpace(currentSettlementId)) return new JsonArray();
        if (safeTowns is null) return new JsonArray(new JsonObject { ["action"] = "mapSettlementTargets", ["arguments"] = new JsonArray() });
        var ids = safeTowns.OfType<JsonObject>().Select(target => ReadString(target, "id"))
            .Where(id => !string.IsNullOrWhiteSpace(id)).Distinct(StringComparer.Ordinal).ToArray();
        if (ids.Length == 0) return new JsonArray();
        return new JsonArray(new JsonObject
        {
            ["action"] = "move", ["arguments"] = new JsonArray("SettlementId"),
            ["argumentValues"] = new JsonObject { ["SettlementId"] = new JsonArray(ids.Select(id => (JsonNode?)JsonValue.Create(id)).ToArray()) }
        });
    }

    private static JsonArray BuildControlCatalog(JsonObject state, string? moveTargetId, bool moveStartPending = false)
    {
        var context = state["context"] as JsonObject;
        if (IsMapConversationActive(state)) return new JsonArray();
        if (ReadString(context, "gameState") != "MapState" || moveTargetId is null) return new JsonArray();
        var location = state["location"] as JsonObject;
        var targetIsCurrent = ReadString(location, "targetSettlementId") == moveTargetId;
        var movementIsActive = ReadBoolean(state["party"] as JsonObject, "isMoving");
        if (targetIsCurrent && (movementIsActive || moveStartPending) && ReadString(location, "currentSettlementId") != moveTargetId)
            return new JsonArray("observeAgain");
        if (ReadString(location, "currentSettlementId") == moveTargetId && string.IsNullOrWhiteSpace(ReadString(context, "menuId")))
            return new JsonArray("observeAgain");
        return new JsonArray();
    }

    private static bool IsMapConversationActive(JsonObject state) =>
        ReadString(state["context"] as JsonObject, "gameState") == "MapState" &&
        state["context"]?["conversation"] is JsonObject;

    private static bool IsInterruptedMapMove(JsonObject state, string? moveTargetId, bool moveStartPending)
    {
        if (string.IsNullOrWhiteSpace(moveTargetId) || IsMapConversationActive(state)) return false;
        var context = state["context"] as JsonObject;
        var location = state["location"] as JsonObject;
        return ReadString(context, "gameState") == "MapState" &&
            ReadString(location, "currentSettlementId") != moveTargetId &&
            !ReadBoolean(state["party"] as JsonObject, "isMoving") &&
            !moveStartPending;
    }

    private static JsonArray BuildMapConversationActionCatalog(JsonObject state)
    {
        var conversation = state["context"]?["conversation"] as JsonObject;
        if (conversation is null) return new JsonArray();
        var options = conversation["options"] as JsonArray ?? new JsonArray();
        var clickable = options.OfType<JsonObject>()
            .Where(option => ReadBoolean(option, "clickable"))
            .Select(option => ReadString(option, "id"))
            .Where(id => !string.IsNullOrWhiteSpace(id))
            .Distinct(StringComparer.Ordinal)
            .ToArray();
        if (clickable.Length > 0)
        {
            return new JsonArray(new JsonObject
            {
                ["action"] = "dialogueSelect",
                ["arguments"] = new JsonArray("OptionId"),
                ["argumentValues"] = new JsonObject
                {
                    ["OptionId"] = new JsonArray(clickable.Select(id => (JsonNode?)JsonValue.Create(id)).ToArray())
                }
            });
        }
        if (options.Count == 0)
            return new JsonArray(new JsonObject { ["action"] = "dialogueContinue", ["arguments"] = new JsonArray() });
        return new JsonArray();
    }

    private static string? ReadMoveTargetId(JsonObject? arguments) => ReadString(arguments, "settlementId");

    private static bool HasReachedMoveTargetMenu(JsonObject state, string? moveTargetId)
    {
        if (string.IsNullOrWhiteSpace(moveTargetId)) return false;
        var location = state["location"] as JsonObject;
        var context = state["context"] as JsonObject;
        return string.Equals(ReadString(location, "currentSettlementId"), moveTargetId, StringComparison.Ordinal) &&
               !string.IsNullOrWhiteSpace(ReadString(context, "menuId"));
    }

    private static bool TryResolveAction(JsonObject state, JsonObject? previousReceipt, JsonArray catalog,
        JsonObject decision, JsonArray? safeTowns, string? moveTargetId,
        out string? action, out JsonObject? arguments, out string? rejection)
    {
        action = ReadString(decision, "action");
        arguments = null;
        rejection = null;
        var requestedAction = action;
        var listed = requestedAction is null ? null : catalog.OfType<JsonObject>().FirstOrDefault(item => ReadString(item, "action") == requestedAction);
        if (listed is null || decision["arguments"] is not JsonObject supplied)
        {
            rejection = "Choose one Native action from the current W7-P catalog.";
            return false;
        }
        var names = listed["arguments"] as JsonArray ?? new JsonArray();
        if (names.Count != supplied.Count || names.Any(name => name?.GetValue<string>() is not string key || !supplied.ContainsKey(key)))
        {
            rejection = "Native action arguments do not match the current Gold sale catalog.";
            return false;
        }
        if (action == "dialogueSelect")
        {
            var optionId = ReadString(supplied, "OptionId");
            var options = state["context"]?["conversation"]?["options"] as JsonArray;
            var currentOption = options?.OfType<JsonObject>().FirstOrDefault(option =>
                ReadString(option, "id") == optionId && ReadBoolean(option, "clickable"));
            var listedOptionIds = listed["argumentValues"]?["OptionId"] as JsonArray;
            if (!IsMapConversationActive(state) || string.IsNullOrWhiteSpace(optionId) || currentOption is null ||
                listedOptionIds?.Any(value => value?.GetValue<string>() == optionId) != true)
            {
                rejection = "Choose only a currently clickable Native option from the active MapState conversation.";
                return false;
            }
            arguments = new JsonObject { ["optionId"] = optionId };
            return true;
        }
        if (action == "dialogueContinue")
        {
            var options = state["context"]?["conversation"]?["options"] as JsonArray;
            if (supplied.Count != 0 || !IsMapConversationActive(state) || options is null || options.Count != 0)
            {
                rejection = "Native dialogueContinue is valid only when the active MapState conversation has no options.";
                return false;
            }
            arguments = new JsonObject();
            return true;
        }
        if (action == "move")
        {
            var targetId = ReadString(supplied, "SettlementId");
            if (safeTowns?.OfType<JsonObject>().Any(target => ReadString(target, "id") == targetId) != true ||
                !listed["argumentValues"]!["SettlementId"]!.AsArray().Any(value => value?.GetValue<string>() == targetId))
            {
                rejection = "Movement is limited to a current safe Native Town target.";
                return false;
            }
            arguments = new JsonObject { ["settlementId"] = targetId };
            return true;
        }
        if (action == "menuSelect")
        {
            var menuId = ReadString(supplied, "MenuId");
            var optionId = ReadString(supplied, "OptionId");
            var currentMenuId = ReadString(state["context"] as JsonObject, "menuId");
            var currentOption = GetEnabledOptions(state).OfType<JsonObject>().FirstOrDefault(option => ReadString(option, "id") == optionId);
            var isMainTownTrade = menuId == "town" && optionId == "trade";
            var isSelectPrisonersForSale = menuId == "town_backstreet" && optionId == "sell_some_prisoners";
            var isTownLeaveAfterEmptyTrade = menuId == "town" && ReadString(previousReceipt, "action") == "tradeCancel" && ReadBoolean(currentOption, "isLeave");
            var isNativeLocationLeave = AgentHostCampaignStateFacts.IsNativeLocationMenu(state) && ReadBoolean(currentOption, "isLeave") &&
                                        (menuId != "town" || isTownLeaveAfterEmptyTrade);
            if (menuId != currentMenuId || (!isMainTownTrade && !isSelectPrisonersForSale && !isNativeLocationLeave) || currentOption is null)
            {
                rejection = "Only the current Native Town Trade entry or a visible Native location-menu Leave option can be selected.";
                return false;
            }
            arguments = new JsonObject { ["menuId"] = menuId, ["optionId"] = optionId };
            return true;
        }
        if (action == "trade")
        {
            var direction = ReadString(supplied, "Direction");
            var itemId = ReadString(supplied, "ItemViewModelId");
            var side = ReadString(supplied, "InventorySide");
            var amount = ReadInt(supplied, "Amount", 0);
            var offer = GetSellableGoods(previousReceipt).FirstOrDefault(candidate => ReadString(candidate, "viewModelItemId") == itemId);
            if (ReadString(previousReceipt, "action") != "tradeOptions" || direction != "sell" || side != "PlayerInventory" || amount != 1 || offer is null ||
                !listed["argumentValues"]!["ItemViewModelId"]!.AsArray().Any(value => value?.GetValue<string>() == itemId))
            {
                rejection = "Sale must be exactly one unit from the current Native transferable Goods sell offer.";
                return false;
            }
            arguments = new JsonObject { ["direction"] = "sell", ["itemViewModelId"] = itemId, ["inventorySide"] = "PlayerInventory", ["amount"] = 1 };
            return true;
        }
        if (action == "sellPrisonerOne")
        {
            var troopId = ReadString(supplied, "TroopId");
            var rows = state["partyScreen"]?["rightPrisoners"] as JsonArray;
            var row = rows?.OfType<JsonObject>().FirstOrDefault(item => ReadString(item, "troopId") == troopId &&
                ReadBoolean(item, "transferable") && ReadInt(item, "count", 0) > 0);
            if (ReadString(state["context"] as JsonObject, "gameState") != "PartyState" ||
                ReadString(state["partyScreen"] as JsonObject, "mode") != "Ransom" ||
                ReadString(state["partyScreen"] as JsonObject, "rightPartyId") != "player_party" || row is null ||
                listed["argumentValues"]?["TroopId"]?.AsArray().Any(value => value?.GetValue<string>() == troopId) != true)
            {
                rejection = "Choose one currently observed transferable prisoner from MainParty in the Native Ransom screen.";
                return false;
            }
            arguments = new JsonObject { ["troopId"] = troopId };
            return true;
        }
        if (action == "partyScreenCancel")
        {
            var screen = state["partyScreen"] as JsonObject;
            if (ReadString(state["context"] as JsonObject, "gameState") != "PartyState" || ReadString(screen, "mode") != "Ransom" ||
                ReadString(screen, "rightPartyId") != "player_party" || !ReadBoolean(screen, "cancelAvailable") || supplied.Count != 0)
            {
                rejection = "Cancel only the current MainParty Ransom draft when the Native PartyVM says Cancel is available.";
                return false;
            }
            arguments = new JsonObject();
            return true;
        }
        if (action == "partyScreenDone")
        {
            var screen = state["partyScreen"] as JsonObject;
            if (ReadString(state["context"] as JsonObject, "gameState") != "PartyState" || ReadString(screen, "mode") != "Ransom" ||
                ReadString(screen, "rightPartyId") != "player_party" || !ReadBoolean(screen, "canDone") ||
                CountRoster(screen?["leftPrisoners"] as JsonArray) < 1 || ReadDouble(screen, "ransomGoldChangeAmount", 0) <= 0 || supplied.Count != 0)
            {
                rejection = "Commit only a current Native Ransom draft that adds Gold and shows the current Done button enabled.";
                return false;
            }
            arguments = new JsonObject();
            return true;
        }
        if ((action is "mapSettlementTargets" or "tradeOptions" or "tradeConfirm" or "tradeCancel" or "tradeCancelChanges") && supplied.Count == 0)
        {
            arguments = new JsonObject();
            return true;
        }
        rejection = "The action is not supported by the W7-P original Native sale slice.";
        return false;
    }

    private static JsonObject[] GetSellableGoods(JsonObject? receipt) =>
        (receipt?["data"]?["sellOffers"] as JsonArray)?.OfType<JsonObject>()
            .Where(offer => ReadString(offer, "nativeTooltipType") == "Goods" &&
                ReadString(offer, "inventorySide") == "PlayerInventory" &&
                ReadBoolean(offer, "isTransferable") && ReadInt(offer, "stock", 0) >= 1 &&
                ReadInt(offer, "inventoryLogicUnitPrice", 0) > 0 && !string.IsNullOrWhiteSpace(ReadString(offer, "viewModelItemId")))
            .Select(offer => (JsonObject)offer.DeepClone()).ToArray() ?? Array.Empty<JsonObject>();

    private static bool HasTransferableGoodsInventory(JsonObject? receipt) =>
        (receipt?["data"]?["sellOffers"] as JsonArray)?.OfType<JsonObject>().Any(offer =>
            ReadString(offer, "nativeTooltipType") == "Goods" &&
            ReadString(offer, "inventorySide") == "PlayerInventory" &&
            ReadBoolean(offer, "isTransferable") && ReadInt(offer, "stock", 0) >= 1) == true;

    private static JsonArray FilterSafeTowns(JsonObject receipt, HashSet<string>? visitedTowns = null)
    {
        if (ReadString(receipt, "status") != "completed" || receipt["data"]?["mapSettlementTargets"] is not JsonArray targets) return new JsonArray();
        var candidates = targets.OfType<JsonObject>()
            .Where(target => ReadString(target, "type") == "town" && !ReadBoolean(target, "hostile") && !ReadBoolean(target, "underSiege") &&
                (visitedTowns is null || !visitedTowns.Contains(ReadString(target, "id") ?? string.Empty)) &&
                ReadDouble(target, "distance", double.MaxValue) > 1.0 && !string.IsNullOrWhiteSpace(ReadString(target, "id")) && !string.IsNullOrWhiteSpace(ReadString(target, "name")))
            .OrderBy(target => ReadDouble(target, "distance", double.MaxValue))
            .ThenBy(target => ReadString(target, "id"), StringComparer.Ordinal)
            .Take(12)
            .Select(target => (JsonNode?)new JsonObject
            {
                ["id"] = ReadString(target, "id"), ["name"] = ReadString(target, "name"), ["type"] = "town",
                ["distance"] = ReadDouble(target, "distance", double.MaxValue), ["hostile"] = false, ["underSiege"] = false
            });
        return new JsonArray(candidates.ToArray());
    }

    private static JsonArray GetEnabledOptions(JsonObject state) =>
        (state["availableMenuOptions"] as JsonArray)?.OfType<JsonObject>()
            .Where(option => ReadBoolean(option, "available") && ReadBoolean(option, "enabled")).ToArray() is { } options
            ? new JsonArray(options.Select(option => (JsonNode?)option.DeepClone()).ToArray()) : new JsonArray();

    private static int CountRoster(JsonArray? rows) => rows?.OfType<JsonObject>().Sum(row => Math.Max(0, ReadInt(row, "count", 0))) ?? 0;

    private static JsonObject BuildObservation(JsonObject native, JsonObject state, JsonObject goldObjective,
        JsonArray liveDifferences, JsonObject? saleReceipt) => new()
    {
        ["status"] = ReadString(native, "status"),
        ["campaignDay"] = native["campaignDay"]?.DeepClone(),
        ["timeControlMode"] = ReadString(native, "timeControlMode"),
        ["state"] = state.DeepClone(),
        ["activeStoryModeQuest"] = QuestId,
        ["goldObjective"] = goldObjective.DeepClone(),
        ["liveMetricDifferences"] = liveDifferences.DeepClone(),
        ["saleReceipt"] = saleReceipt?.DeepClone()
    };

    private static JsonObject BuildDecisionRequest(string runId, string? goal, int iteration, JsonObject observation,
        JsonObject? previousReceipt, JsonObject? feedback, JsonArray actionCatalog, JsonArray controls, bool moveStartPending)
    {
        var request = new JsonObject
        {
            ["runId"] = runId,
            ["goal"] = goal,
            ["goalKind"] = "active-establish-clan-gold-sale",
            ["goalScopeClassificationRequired"] = false,
            ["iteration"] = iteration,
            ["observation"] = observation.DeepClone(),
            ["previousActionReceipt"] = previousReceipt?.DeepClone(),
            ["decisionFeedback"] = feedback?.DeepClone(),
            ["allowedActions"] = actionCatalog.DeepClone(),
            ["allowedControls"] = controls.DeepClone()
        };
        request["controlArguments"] = controls.Any(control => control?.GetValue<string>() == "observeAgain")
            ? new JsonObject
            {
                ["observeAgain"] = new JsonObject
                {
                    ["waitSeconds"] = new JsonObject
                    {
                        ["type"] = "integer",
                        ["minimum"] = GetMinimumObserveInterval(moveStartPending),
                        ["maximum"] = 10
                    }
                }
            }
            : new JsonObject();
        return request;
    }

    private static int GetMinimumObserveInterval(bool moveStartPending) => moveStartPending ? 1 : MinimumActiveMapTravelObserveSeconds;

    private static bool IsSupportedObserveInterval(int seconds, bool moveStartPending) =>
        seconds >= GetMinimumObserveInterval(moveStartPending) && seconds <= 10;

    private static JsonObject? BuildProviderPreviousReceipt(JsonObject? previousReceipt, JsonArray? safeTowns)
    {
        if (ReadString(previousReceipt, "action") != "mapSettlementTargets")
            return previousReceipt?.DeepClone() as JsonObject;
        var compact = previousReceipt?.DeepClone() as JsonObject;
        var data = compact?["data"] as JsonObject;
        if (data is null || data["mapSettlementTargets"] is not JsonArray)
            return compact;
        data["mapSettlementTargets"] = safeTowns?.DeepClone() as JsonArray ?? new JsonArray();
        data["candidateScope"] = "currently observed safe Town targets for the active Gold objective";
        data["candidateCount"] = safeTowns?.Count ?? 0;
        return compact;
    }

    private static JsonObject BuildReceipt(string action, JsonObject arguments, JsonObject receipt)
    {
        var result = new JsonObject { ["action"] = action, ["status"] = ReadString(receipt, "status"), ["data"] = receipt["data"]?.DeepClone() };
        if (action == "mapSettlementTargets") result["data"] = receipt["data"]?.DeepClone();
        if (action == "move") result["targetSettlementId"] = arguments["settlementId"]?.DeepClone();
        if (action == "trade")
        {
            result["itemViewModelId"] = arguments["itemViewModelId"]?.DeepClone();
            result["direction"] = "sell";
        }
        return result;
    }

    private static JsonObject BuildStep(int iteration, JsonObject observation, JsonObject decision, JsonObject? receipt,
        string started, long startedTicks, JsonObject? control, JsonObject? observationAfter)
    {
        return new JsonObject
        {
            ["iteration"] = iteration,
            ["observationBefore"] = observation.DeepClone(),
            ["decision"] = decision.DeepClone(),
            ["actionReceipt"] = receipt?.DeepClone(),
            ["actionAttempted"] = decision["action"] is not null,
            ["actionExecuted"] = receipt is JsonObject actionReceipt && ReadString(actionReceipt, "status") == "completed",
            ["observationAfter"] = observationAfter?.DeepClone(),
            ["control"] = control?.DeepClone(),
            ["timing"] = new JsonObject
            {
                ["providerStartedUtc"] = started,
                ["providerElapsedMilliseconds"] = Math.Round(Stopwatch.GetElapsedTime(startedTicks).TotalMilliseconds, 2),
                ["observationCompletedUtc"] = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture)
            }
        };
    }

    private static (JsonObject Snapshot, JsonArray LiveDifferences) ReadGoldJournal(JsonElement receiptElement)
    {
        var receipt = JsonNode.Parse(receiptElement.GetRawText())?.AsObject() ?? throw new AgentHostException("gold-sale-quest-details-invalid", "Native returned no quest details object.");
        if (ReadString(receipt, "status") != "completed" || receipt["data"] is not JsonObject data || ReadString(data, "questId") != QuestId)
            throw new AgentHostException("gold-sale-quest-details-invalid", "Native questDetails did not return the exact active StoryMode quest.");
        var journal = AgentHostEstablishYourClanGoalLoop.BuildJournalObjectives(data);
        var snapshot = AgentHostEstablishYourClanGoalLoop.BuildObjectiveSnapshot(journal);
        var live = data["storyModeEstablishClan"] as JsonObject;
        var differences = live is null ? new JsonArray() : AgentHostEstablishYourClanGoalLoop.FindLiveMetricDifferences(live, journal);
        return (snapshot, differences);
    }

    private static bool HasActiveQuest(JsonObject state) =>
        (state["quests"] as JsonArray)?.OfType<JsonObject>().Any(quest => ReadString(quest, "id") == QuestId) == true;

    private static bool IsFreeCampaignMap(JsonObject state)
    {
        var context = state["context"] as JsonObject;
        return ReadString(context, "gameState") == "MapState" &&
            !ReadBoolean(context?["captivity"] as JsonObject, "isCaptive") &&
            !AgentHostCampaignStateFacts.IsActiveEncounter(state) && context?["battleSimulation"] is null &&
            !ReadBoolean(context, "escapeMenuOpen") && !ReadBoolean(context, "inquiryOpen") &&
            state["inventoryScreen"] is null && state["partyScreen"] is null;
    }

    private static bool IsActiveEncounter(JsonObject state)
    {
        var context = state["context"] as JsonObject;
        var inventory = state["inventoryScreen"] as JsonObject;
        var currentSettlementId = ReadString(state["location"] as JsonObject, "currentSettlementId");
        var nativeSettlementTrade = ReadString(context, "gameState") == "InventoryState" &&
            ReadString(inventory, "mode") == "Trade" && ReadBoolean(inventory, "hasHandler") &&
            !string.IsNullOrWhiteSpace(currentSettlementId) &&
            string.Equals(ReadString(context, "encounteredPartyId"), currentSettlementId, StringComparison.Ordinal);
        return AgentHostCampaignStateFacts.IsActiveEncounter(state) && !nativeSettlementTrade;
    }

    private static JsonObject MapState(string? menuId, string? settlementId, JsonArray options) => new()
    {
        ["context"] = new JsonObject
        {
            ["gameState"] = "MapState", ["menuId"] = menuId, ["captivity"] = null,
            ["escapeMenuOpen"] = false, ["inquiryOpen"] = false, ["encounterActive"] = false,
            ["battleSimulation"] = null
        },
        ["location"] = new JsonObject { ["currentSettlementId"] = settlementId, ["targetSettlementId"] = null },
        ["party"] = new JsonObject { ["isMoving"] = false },
        ["availableMenuOptions"] = options.DeepClone()
    };

    private static JsonObject BuildSuccess(
        string runId,
        IAgentHostDecisionProvider provider,
        JsonObject initialNative,
        JsonObject finalNative,
        JsonObject objectiveSnapshotBefore,
        JsonObject objectiveSnapshotAfter,
        JsonArray liveMetricDifferencesBefore,
        JsonArray liveMetricDifferencesAfter,
        JsonObject saleReceipt,
        JsonObject? finalReceipt,
        JsonArray trace,
        JsonArray routeHistory,
        int decisions,
        int actionsExecuted,
        int saleActionsExecuted,
        long promptTokens,
        long completionTokens,
        double campaignDayBefore,
        string? timeControlModeBefore,
        JsonObject? captivityRecovery)
    {
        var goldBefore = objectiveSnapshotBefore["gold"] as JsonObject ?? new JsonObject();
        var goldAfter = objectiveSnapshotAfter["gold"] as JsonObject ?? new JsonObject();
        var finalState = finalNative["state"] as JsonObject ?? new JsonObject();
        var saleData = saleReceipt;
        var explicitTimeActions = captivityRecovery?["explicitTimeActions"]?.DeepClone() as JsonArray ?? new JsonArray();
        var recoveryGameplayActions = ReadInt(captivityRecovery, "gameplayActionsExecuted", 0);
        var recoveryActionCount = ReadInt(captivityRecovery, "actionsExecuted", 0);
        return new JsonObject
        {
            ["status"] = "completed",
            ["resultKind"] = "establish-clan-gold-sale",
            ["providerModelId"] = provider.ModelId,
            ["providerConfigurationSource"] = provider.ConfigurationSource,
            ["runId"] = runId,
            ["decisions"] = decisions,
            ["actionsExecuted"] = recoveryActionCount + actionsExecuted,
            ["saleActionsExecuted"] = saleActionsExecuted,
            ["gameplayActionsExecuted"] = recoveryGameplayActions + saleActionsExecuted,
            ["promptTokens"] = promptTokens,
            ["completionTokens"] = completionTokens,
            ["providerRouteHistory"] = routeHistory.DeepClone(),
            ["initialNativeState"] = initialNative.DeepClone(),
            ["finalNativeState"] = finalNative.DeepClone(),
            ["captivityRecoveryVerified"] = captivityRecovery is null ? null : JsonValue.Create(ReadBoolean(captivityRecovery, "captivityRecoveryVerified")),
            ["captivityRecoveryResultKind"] = ReadString(captivityRecovery, "resultKind"),
            ["captivityRecoveryObjectiveSelection"] = captivityRecovery?["objectiveSelection"]?.DeepClone(),
            ["captivityRecoveryPlannerVerification"] = captivityRecovery is null ? null : new JsonObject
            {
                ["initialStoryModeStatus"] = ReadString(captivityRecovery["initialStoryModeEstablishClanStatus"] as JsonObject, "status"),
                ["finalStoryModeStatus"] = ReadString(captivityRecovery["finalStoryModeEstablishClanStatus"] as JsonObject, "status"),
                ["finalCaptive"] = ReadBoolean((finalState["context"] as JsonObject)?["captivity"] as JsonObject, "isCaptive"),
                ["nativeActionSequence"] = JsonSerializer.SerializeToNode((captivityRecovery["trace"] as JsonArray)?.OfType<JsonObject>()
                    .Where(item => item["actionReceipt"] is JsonObject receipt && ReadString(receipt, "action") is string)
                    .Select(item => ReadString(item["actionReceipt"] as JsonObject, "action")) ?? Array.Empty<string>()),
                ["explicitClockActions"] = explicitTimeActions.DeepClone(),
                ["goalVerified"] = false
            },
            ["saleVerified"] = true,
            ["tradeTimeUnchanged"] = ReadString(saleReceipt, "timeControlModeBefore") == ReadString(saleReceipt, "timeControlModeAfter") &&
                Math.Abs(ReadDouble(saleReceipt, "campaignDayBefore", double.NaN) - ReadDouble(saleReceipt, "campaignDayAfter", double.NaN)) <= 0.000001,
            ["saleReceipt"] = saleData.DeepClone(),
            ["finalReceipt"] = finalReceipt?.DeepClone(),
            ["initialGoldJournal"] = goldBefore.DeepClone(),
            ["finalGoldJournal"] = goldAfter.DeepClone(),
            ["goldJournalDelta"] = ReadDouble(goldAfter, "current", 0) - ReadDouble(goldBefore, "current", 0),
            ["liveMetricDifferencesBeforeSale"] = liveMetricDifferencesBefore.DeepClone(),
            ["liveMetricDifferencesAfterSale"] = liveMetricDifferencesAfter.DeepClone(),
            ["initialCampaignDay"] = double.IsFinite(campaignDayBefore) ? JsonValue.Create(campaignDayBefore) : null,
            ["finalCampaignDay"] = finalNative["campaignDay"]?.DeepClone(),
            ["initialTimeControlMode"] = timeControlModeBefore,
            ["finalTimeControlMode"] = ReadString(finalNative, "timeControlMode"),
            ["explicitTimeActions"] = explicitTimeActions.DeepClone(),
            ["originalQuestStillActive"] = HasActiveQuest(finalState),
            ["originalQuestCompletionClaimed"] = false,
            ["termination"] = new JsonObject { ["reason"] = "one-native-sale-and-journal-gold-increase-verified", ["completedByProvider"] = false, ["goalVerified"] = true },
            ["trace"] = trace.DeepClone()
        };
    }

    private static string DescribeNoAction(JsonObject state, JsonObject? previousReceipt)
    {
        var context = state["context"] as JsonObject;
        var offers = (previousReceipt?["data"]?["sellOffers"] as JsonArray)?.Count ?? 0;
        return $"No safe Gold sale action is available: gameState={ReadString(context, "gameState") ?? "<none>"}; menuId={ReadString(context, "menuId") ?? "<none>"}; sellOfferCount={offers}.";
    }

    private static JsonObject ParseObject(JsonElement element) => JsonNode.Parse(element.GetRawText())?.AsObject()
        ?? throw new AgentHostException("native-response-invalid", "Native returned no object.");
    private static int ReadInt(JsonElement element, string key, int fallback) => element.ValueKind == JsonValueKind.Object && element.TryGetProperty(key, out var value) && value.TryGetInt32(out var number) ? number : fallback;
    private static int ReadInt(JsonObject? value, string key, int fallback) => value?[key] is JsonValue node && node.TryGetValue<int>(out var number) ? number : fallback;
    private static double ReadDouble(JsonObject? value, string key, double fallback) => value?[key] is JsonValue node && node.TryGetValue<double>(out var number) ? number : fallback;
    private static bool ReadBoolean(JsonObject? value, string key) => value?[key] is JsonValue node && node.TryGetValue<bool>(out var result) && result;
    private static string? ReadString(JsonObject? value, string key) => value?[key] is JsonValue node && node.TryGetValue<string>(out var text) ? text : null;
    private static string? ReadString(JsonElement value, string key) => value.ValueKind == JsonValueKind.Object && value.TryGetProperty(key, out var property) && property.ValueKind == JsonValueKind.String ? property.GetString() : null;
    private static long ReadLong(JsonObject? value, string key, long fallback) => value?[key] is JsonValue node && node.TryGetValue<long>(out var result) ? result : fallback;

    private sealed class FakeGoldSaleFailureNativeClient : IAgentHostGoldSaleNativeClient
    {
        internal int MapTargetQueries { get; private set; }

        public Task<JsonDocument> ReadStateAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var state = new JsonObject
            {
                ["context"] = new JsonObject
                {
                    ["gameState"] = "MapState", ["menuId"] = null, ["timeControlMode"] = "Stop",
                    ["captivity"] = new JsonObject { ["isCaptive"] = false }, ["encounterActive"] = false,
                    ["battleSimulation"] = null, ["escapeMenuOpen"] = false, ["inquiryOpen"] = false
                },
                ["quests"] = new JsonArray(new JsonObject { ["id"] = QuestId }),
                ["storyModeEstablishClanStatus"] = new JsonObject { ["status"] = "active", ["questId"] = QuestId },
                ["location"] = new JsonObject { ["currentSettlementId"] = null, ["targetSettlementId"] = null },
                ["party"] = new JsonObject { ["isMoving"] = false },
                ["economy"] = new JsonObject { ["gold"] = 32, ["renown"] = 5 }
            };
            var receipt = new JsonObject { ["status"] = "completed", ["campaignDay"] = 10.0, ["timeControlMode"] = "Stop", ["state"] = state };
            return Task.FromResult(JsonDocument.Parse(receipt.ToJsonString()));
        }

        public Task<JsonDocument> ReadQuestDetailsAsync(string questId, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (questId != QuestId) throw new AgentHostException("gold-sale-failure-selftest-quest-id-invalid", "The fake Native client received an unexpected Quest id.");
            var stages = new JsonArray(
                Stage("gold", 32, 2000), Stage("partySize", 4, 25), Stage("renown", 5, 50), Stage("companions", 1, 1));
            var live = new JsonObject
            {
                ["gold"] = Metric(32, 2000), ["partySize"] = Metric(4, 25), ["renown"] = Metric(5, 50), ["companions"] = Metric(1, 1)
            };
            var data = new JsonObject { ["questId"] = QuestId, ["journalStages"] = stages, ["storyModeEstablishClan"] = live };
            return Task.FromResult(JsonDocument.Parse(new JsonObject { ["status"] = "completed", ["data"] = data }.ToJsonString()));
        }

        public Task<JsonDocument> ExecuteCampaignActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken) =>
            throw new AgentHostException("gold-sale-failure-selftest-unexpected-map-action", "Gold sale did not use the reviewed Native sale adapter.");

        public Task<JsonDocument> ExecuteCaptivityRecoveryActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken) =>
            throw new AgentHostException("gold-sale-failure-selftest-unexpected-captivity-action", "The fake Native source is not captive.");

        public Task<JsonDocument> ExecuteGoldSaleActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (action != "mapSettlementTargets" || arguments.Count != 0) throw new AgentHostException("gold-sale-failure-selftest-unexpected-native-action", "Only the first current safe Town target query is expected before the provider failure.");
            MapTargetQueries++;
            var targets = new JsonArray();
            for (var index = 1; index <= 15; index++)
                targets.Add(new JsonObject { ["id"] = $"town-safe-{index}", ["name"] = $"Safe Town {index}", ["type"] = "town", ["distance"] = 10.0 + index, ["hostile"] = false, ["underSiege"] = false });
            targets.Add(new JsonObject { ["id"] = "town-hostile", ["name"] = "Hostile Town", ["type"] = "town", ["distance"] = 3.0, ["hostile"] = true, ["underSiege"] = false });
            targets.Add(new JsonObject { ["id"] = "town-sieged", ["name"] = "Sieged Town", ["type"] = "town", ["distance"] = 4.0, ["hostile"] = false, ["underSiege"] = true });
            targets.Add(new JsonObject { ["id"] = "village", ["name"] = "Village", ["type"] = "village", ["distance"] = 2.0, ["hostile"] = false, ["underSiege"] = false });
            var data = new JsonObject { ["mapSettlementTargets"] = targets };
            return Task.FromResult(JsonDocument.Parse(new JsonObject { ["status"] = "completed", ["action"] = action, ["data"] = data }.ToJsonString()));
        }

        private static JsonObject Stage(string id, int current, int target) => new()
        {
            ["hasTask"] = true, ["currentProgress"] = current, ["targetProgress"] = target, ["description"] = id
        };
        private static JsonObject Metric(int current, int target) => new() { ["current"] = current, ["target"] = target, ["met"] = current >= target };
    }

    private sealed class FakeGoldSaleFailureProvider : IAgentHostDecisionProvider
    {
        internal int CallCount { get; private set; }
        internal bool FeedbackObserved { get; private set; }
        internal bool IsDisposed { get; private set; }
        internal JsonObject? LastRequest { get; private set; }
        public string ModelId => "deterministic-gold-sale-failure-selftest";
        public string ConfigurationSource => "harness-fake-provider";
        public Task CheckConfiguredModelAsync(CancellationToken cancellationToken) { cancellationToken.ThrowIfCancellationRequested(); return Task.CompletedTask; }
        public Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            CallCount++;
            LastRequest = JsonNode.Parse(request.GetRawText())?.AsObject();
            if (request.TryGetProperty("decisionFeedback", out var feedbackValue) && feedbackValue.ValueKind == JsonValueKind.Object &&
                feedbackValue.TryGetProperty("kind", out var feedbackKind) && feedbackKind.ValueKind == JsonValueKind.String &&
                feedbackKind.GetString() == "decision-rejected-before-native") FeedbackObserved = true;
            if (CallCount == 1)
                throw new AgentHostException("provider-arguments-invalid-json", "The self-test model returned malformed action arguments before Native execution.");
            if (CallCount == 2)
                return Task.FromResult(new ProviderDecisionResult("completed", ModelId, 1, 1, "fake-gold-sale-failure-route", new JsonObject
                {
                    ["action"] = "mapSettlementTargets", ["arguments"] = new JsonObject(), ["rationale"] = "Read current safe Town targets."
                }));
            throw new AgentHostException("provider-http-error", "Fake external provider rate-limit summary; no Native command followed.");
        }
        public void Dispose() { IsDisposed = true; }
    }
}
