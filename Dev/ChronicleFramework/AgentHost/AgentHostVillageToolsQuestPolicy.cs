using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal static class AgentHostVillageToolsQuestPolicy
{
    internal static JsonArray BuildActionCatalog(JsonObject native, JsonObject? previousReceipt, bool preDeliveryInventoryCaptured = false, bool questDetailsObserved = false)
    {
        var state = native["state"] as JsonObject;
        var context = state?["context"] as JsonObject;
        var location = state?["location"] as JsonObject;
        if (state is null || context is null) return new JsonArray();

        var menuId = ReadString(context, "menuId");
        var conversation = context["conversation"] as JsonObject;
        if (conversation is not null)
        {
            if (string.Equals(menuId, "encounter_meeting", StringComparison.Ordinal)) return new JsonArray();
            var catalog = new JsonArray();
            AddQuestDetailsAction(state, catalog, questDetailsObserved);
            var options = conversation["options"] as JsonArray ?? new JsonArray();
            if (options.OfType<JsonObject>().Any(option => ReadBoolean(option, "clickable")))
                catalog.Add(new JsonObject { ["action"] = "dialogueSelect", ["arguments"] = new JsonArray("OptionId") });
            else
                catalog.Add(new JsonObject { ["action"] = "dialogueContinue", ["arguments"] = new JsonArray() });
            return catalog;
        }

        var gameState = ReadString(context, "gameState");
        if (string.Equals(gameState, "InventoryState", StringComparison.Ordinal))
            return BuildInventoryActionCatalog(state, previousReceipt);
        if (!string.Equals(gameState, "MapState", StringComparison.Ordinal))
            return new JsonArray();

        var currentSettlementId = ReadString(location, "currentSettlementId");
        var targetSettlementId = ReadString(location, "targetSettlementId");
        var hasToolsQuest = HasActiveToolsQuest(state);
        var visibleToolsIssueGivers = GetAllowedToolsQuestGiverIds(state, previousReceipt);
        if (!hasToolsQuest && visibleToolsIssueGivers.Count == 0)
            return new JsonArray();
        var catalogWithQuestDetails = new JsonArray();
        AddQuestDetailsAction(state, catalogWithQuestDetails, questDetailsObserved);

        if (hasToolsQuest && !preDeliveryInventoryCaptured && context["conversation"] is not JsonObject && IsToolsTaskSatisfied(previousReceipt))
        {
            catalogWithQuestDetails.Add(new JsonObject { ["action"] = "inventoryOpen", ["arguments"] = new JsonArray() });
            return catalogWithQuestDetails;
        }

        if (!hasToolsQuest && context["conversation"] is not JsonObject &&
            (ReadString(previousReceipt, "action") is "dialogueSelect" or "dialogueContinue") && ReadString(previousReceipt, "status") == "completed")
            catalogWithQuestDetails.Add(new JsonObject { ["action"] = "inventoryOpen", ["arguments"] = new JsonArray() });

        if (!string.IsNullOrWhiteSpace(targetSettlementId) && !string.Equals(currentSettlementId, targetSettlementId, StringComparison.Ordinal))
            return new JsonArray();

        if (!string.IsNullOrWhiteSpace(menuId))
        {
            var markedGivers = GetAllowedToolsQuestGiverIds(state, previousReceipt);
            if (markedGivers.Count > 0)
            {
                catalogWithQuestDetails.Add(new JsonObject { ["action"] = "talkToSettlementHero", ["arguments"] = new JsonArray("HeroId") });
                return catalogWithQuestDetails;
            }

            var menuOptions = state["availableMenuOptions"] as JsonArray ?? new JsonArray();
            var tradeContextSupported = hasToolsQuest && string.Equals(GetCurrentSettlementType(state), "town", StringComparison.Ordinal);
            var townMarketAttemptFinished = ReadString(previousReceipt, "status") == "completed" &&
                ReadString(previousReceipt, "action") is "tradeCancel" or "tradeCancelChanges" or "tradeConfirm";
            var allowedMenuOptions = menuOptions.OfType<JsonObject>()
                .Where(option => IsTrue(option, "available") && IsTrue(option, "enabled") &&
                    (IsTrue(option, "isLeave")
                        ? (!tradeContextSupported || townMarketAttemptFinished)
                        : (tradeContextSupported && !townMarketAttemptFinished && IsTradeOption(option))))
                .ToArray();
            if (allowedMenuOptions.Length > 0)
            {
                var optionIds = new JsonArray();
                foreach (var option in allowedMenuOptions)
                {
                    var optionId = ReadString(option, "id");
                    if (!string.IsNullOrWhiteSpace(optionId)) optionIds.Add(optionId);
                }
                catalogWithQuestDetails.Add(new JsonObject
                {
                    ["action"] = "menuSelect",
                    ["arguments"] = new JsonArray("OptionId"),
                    ["argumentValues"] = new JsonObject { ["OptionId"] = optionIds }
                });
            }
            if (hasToolsQuest && !preDeliveryInventoryCaptured && IsToolsTaskSatisfied(previousReceipt))
                catalogWithQuestDetails.Add(new JsonObject { ["action"] = "inventoryOpen", ["arguments"] = new JsonArray() });
            return catalogWithQuestDetails;
        }

        if (hasToolsQuest && !preDeliveryInventoryCaptured && IsToolsTaskSatisfied(previousReceipt))
            catalogWithQuestDetails.Add(new JsonObject { ["action"] = "inventoryOpen", ["arguments"] = new JsonArray() });

        if (hasToolsQuest && string.IsNullOrWhiteSpace(currentSettlementId))
        {
            var observedTargets = GetTargetsFromReceipt(previousReceipt);
            if (observedTargets is null)
            {
                catalogWithQuestDetails.Add(new JsonObject { ["action"] = "mapSettlementTargets", ["arguments"] = new JsonArray() });
                return catalogWithQuestDetails;
            }

            var candidates = FilterSafeTargets(observedTargets, "town");
            if (candidates.Count > 0)
            {
                var settlementIds = new JsonArray();
                foreach (var candidate in candidates.OfType<JsonObject>())
                {
                    var settlementId = ReadString(candidate, "id");
                    if (!string.IsNullOrWhiteSpace(settlementId)) settlementIds.Add(settlementId);
                }
                catalogWithQuestDetails.Add(new JsonObject
                {
                    ["action"] = "move",
                    ["arguments"] = new JsonArray("SettlementId"),
                    ["argumentValues"] = new JsonObject { ["SettlementId"] = settlementIds }
                });
            }
            return catalogWithQuestDetails;
        }

        return catalogWithQuestDetails;
    }

    internal static JsonArray BuildControlCatalog(JsonObject native, bool questWasObservedActive = false, bool inventoryVerifiedAfterTurnIn = false)
    {
        var state = native["state"] as JsonObject;
        var context = state?["context"] as JsonObject;
        var location = state?["location"] as JsonObject;
        if (state is null || context is null)
            return new JsonArray();

        var controls = new JsonArray();
        if (!string.Equals(ReadString(context, "gameState"), "MapState", StringComparison.Ordinal) ||
            context["conversation"] is JsonObject || !string.IsNullOrWhiteSpace(ReadString(context, "menuId")))
            return controls;

        if (questWasObservedActive && !HasActiveToolsQuest(state) && inventoryVerifiedAfterTurnIn)
            controls.Add("done");

        var currentSettlementId = ReadString(location, "currentSettlementId");
        var targetSettlementId = ReadString(location, "targetSettlementId");
        if (!string.IsNullOrWhiteSpace(targetSettlementId) && !string.Equals(currentSettlementId, targetSettlementId, StringComparison.Ordinal))
            controls.Add("observeAgain");
        return controls;
    }

    internal static bool TryResolveAction(
        JsonObject native,
        JsonObject? previousReceipt,
        JsonObject decision,
        out string? action,
        out JsonObject? nativeArguments,
        out string rejection,
        bool preDeliveryInventoryCaptured = false)
    {
        action = ReadString(decision, "action");
        nativeArguments = null;
        var state = native["state"] as JsonObject;
        var context = state?["context"] as JsonObject;
        var location = state?["location"] as JsonObject;
        if (state is null || context is null || string.IsNullOrWhiteSpace(action))
        {
            rejection = "The current Native state or selected action is missing.";
            return false;
        }

        var arguments = decision["arguments"] as JsonObject ?? new JsonObject();
        var menuId = ReadString(context, "menuId");
        var conversation = context["conversation"] as JsonObject;
        var currentSettlementId = ReadString(location, "currentSettlementId");
        var targetSettlementId = ReadString(location, "targetSettlementId");
        var hasToolsQuest = HasActiveToolsQuest(state);

        if (ReadString(context, "gameState") == "InventoryState")
            return TryResolveInventoryAction(state, previousReceipt, action!, arguments, out nativeArguments, out rejection);

        switch (action)
        {
            case "mapSettlementTargets" when arguments.Count == 0 &&
                ReadString(context, "gameState") == "MapState" && string.IsNullOrWhiteSpace(menuId) &&
                string.IsNullOrWhiteSpace(currentSettlementId) && string.IsNullOrWhiteSpace(targetSettlementId) && hasToolsQuest:
                nativeArguments = new JsonObject();
                rejection = string.Empty;
                return true;

            case "questDetails" when arguments.Count == 1 && ReadString(context, "gameState") == "MapState":
            {
                var questId = ReadString(arguments, "QuestId");
                if (ActiveToolsQuestIds(state).Contains(questId, StringComparer.Ordinal))
                {
                    nativeArguments = new JsonObject { ["questId"] = questId };
                    rejection = string.Empty;
                    return true;
                }
                break;
            }

            case "inventoryOpen" when arguments.Count == 0 && ReadString(context, "gameState") == "MapState" &&
                ((hasToolsQuest && !preDeliveryInventoryCaptured && IsToolsTaskSatisfied(previousReceipt)) ||
                 (!hasToolsQuest && (ReadString(previousReceipt, "action") is "dialogueSelect" or "dialogueContinue") && ReadString(previousReceipt, "status") == "completed")):
                nativeArguments = new JsonObject();
                rejection = string.Empty;
                return true;

            case "move" when arguments.Count == 1 &&
                ReadString(context, "gameState") == "MapState" && string.IsNullOrWhiteSpace(menuId) &&
                string.IsNullOrWhiteSpace(currentSettlementId) && string.IsNullOrWhiteSpace(targetSettlementId):
            {
                var targetId = ReadString(arguments, "SettlementId");
                var targetReceipt = GetTargetsFromReceipt(previousReceipt);
                var selected = targetReceipt is null || !hasToolsQuest ? null : FilterSafeTargets(targetReceipt, "town")
                    .OfType<JsonObject>().FirstOrDefault(item => ReadString(item, "id") == targetId);
                if (selected is null)
                {
                    rejection = "move must select a safe settlement of the required type from the latest Native target query.";
                    return false;
                }
                nativeArguments = new JsonObject { ["settlementId"] = targetId };
                rejection = string.Empty;
                return true;
            }

            case "talkToSettlementHero" when arguments.Count == 1 &&
                ReadString(context, "gameState") == "MapState" && !string.IsNullOrWhiteSpace(menuId):
            {
                var heroId = ReadString(arguments, "HeroId");
                if (GetAllowedToolsQuestGiverIds(state, previousReceipt).Contains(heroId, StringComparer.Ordinal))
                {
                    nativeArguments = new JsonObject { ["heroId"] = heroId };
                    rejection = string.Empty;
                    return true;
                }
                break;
            }

            case "menuSelect" when arguments.Count == 1 &&
                ReadString(context, "gameState") == "MapState" && !string.IsNullOrWhiteSpace(menuId):
            {
                var optionId = ReadString(arguments, "OptionId");
                var option = (state["availableMenuOptions"] as JsonArray)?.OfType<JsonObject>()
                    .FirstOrDefault(item => ReadString(item, "id") == optionId && IsTrue(item, "available") && IsTrue(item, "enabled"));
                if (option is not null && (IsTrue(option, "isLeave") || (hasToolsQuest && IsTradeOption(option))))
                {
                    nativeArguments = new JsonObject { ["menuId"] = menuId, ["optionId"] = optionId };
                    rejection = string.Empty;
                    return true;
                }
                break;
            }

            case "dialogueSelect" when arguments.Count == 1 && conversation is not null && menuId != "encounter_meeting":
            {
                var optionId = ReadString(arguments, "OptionId");
                var option = (conversation["options"] as JsonArray)?.OfType<JsonObject>()
                    .FirstOrDefault(item => ReadString(item, "id") == optionId && IsTrue(item, "clickable"));
                if (option is not null)
                {
                    nativeArguments = new JsonObject { ["optionId"] = optionId };
                    rejection = string.Empty;
                    return true;
                }
                break;
            }

            case "dialogueContinue" when arguments.Count == 0 && conversation is not null && menuId != "encounter_meeting" &&
                (conversation["options"] as JsonArray)?.Count == 0:
                nativeArguments = new JsonObject();
                rejection = string.Empty;
                return true;
        }

        rejection = "The selected action is not allowed by the current observed Native village-quest context.";
        return false;
    }

    internal static IReadOnlyList<object> RunContractSelfTests()
    {
        var results = new List<object>();
        var map = State("MapState", null, null);
        var noQuestActions = BuildActionCatalog(map, null);
        if (noQuestActions.Count != 0)
            throw new AgentHostException("village-tools-policy-self-test-quest-search-overreach", "Without the current visible blue tools issue, the Host must not travel or mutate the Campaign.");

        var activeMap = State("MapState", null, null, quests: new JsonArray(new JsonObject { ["id"] = "quest-tools", ["title"] = "Village Needs Tools" }));
        var activeTargets = new JsonObject
        {
            ["action"] = "mapSettlementTargets",
            ["status"] = "completed",
            ["data"] = new JsonObject { ["mapSettlementTargets"] = new JsonArray
            {
                new JsonObject { ["id"] = "town-1", ["type"] = "town", ["hostile"] = false, ["underSiege"] = false, ["distance"] = 4.0 },
                new JsonObject { ["id"] = "town-danger", ["type"] = "town", ["hostile"] = true, ["underSiege"] = false, ["distance"] = 1.0 },
                new JsonObject { ["id"] = "town-1", ["type"] = "town", ["hostile"] = false, ["underSiege"] = false, ["distance"] = 5.0 }
            } }
        };
        var moveCatalog = BuildActionCatalog(activeMap, activeTargets);
        var moveAction = moveCatalog.OfType<JsonObject>().FirstOrDefault(item => ReadString(item, "action") == "move");
        var permittedTownIds = (moveAction?["argumentValues"]?["SettlementId"] as JsonArray)?.Select(item => item?.GetValue<string>()).ToArray() ?? Array.Empty<string?>();
        if (moveAction is null || !permittedTownIds.SequenceEqual(new string?[] { "town-1" }, StringComparer.Ordinal) ||
            !TryResolveAction(activeMap, activeTargets, new JsonObject { ["action"] = "move", ["arguments"] = new JsonObject { ["SettlementId"] = "town-1" } }, out _, out _, out _) ||
            TryResolveAction(activeMap, activeTargets, new JsonObject { ["action"] = "move", ["arguments"] = new JsonObject { ["SettlementId"] = "town-danger" } }, out _, out _, out _))
            throw new AgentHostException("village-tools-policy-self-test-map-target-gate-failed", "Only a safe town from the latest Native target query may be selected after the current tools Quest is active.");
        results.Add(new { scenario = "village-tools-policy-requires-current-safe-town-before-procuring-items", passed = true });

        var overlay = new JsonArray
        {
            new JsonObject { ["heroId"] = "hero-tools", ["questMarkers"] = new JsonArray(new JsonObject { ["type"] = "AvailableIssue", ["title"] = "Needs Tools" }) },
            new JsonObject { ["heroId"] = "hero-unrelated", ["questMarkers"] = new JsonArray(new JsonObject { ["type"] = "AvailableIssue", ["title"] = "Needs Help" }) }
        };
        var villageMenu = State("MapState", "village", "village-1", overlay: overlay);
        var giverCatalog = BuildActionCatalog(villageMenu, null);
        if (giverCatalog.Count != 1 || ReadString(giverCatalog[0] as JsonObject, "action") != "talkToSettlementHero" ||
            !TryResolveAction(villageMenu, null, new JsonObject { ["action"] = "talkToSettlementHero", ["arguments"] = new JsonObject { ["HeroId"] = "hero-tools" } }, out _, out _, out _) ||
            TryResolveAction(villageMenu, null, new JsonObject { ["action"] = "talkToSettlementHero", ["arguments"] = new JsonObject { ["HeroId"] = "hero-unrelated" } }, out _, out _, out _))
            throw new AgentHostException("village-tools-policy-self-test-visible-issue-marker-gate-failed", "The Host must only offer quick conversation for an observed available issue visibly matching the tools request.");
        results.Add(new { scenario = "village-tools-policy-talks-only-to-current-visible-tools-issue", passed = true });

        var acceptedVillageMenu = State("MapState", "village", "village-1", quests: new JsonArray(new JsonObject { ["id"] = "quest-tools", ["title"] = "Village Needs Tools" }));
        acceptedVillageMenu["state"]!["nearbySettlements"] = new JsonArray(new JsonObject { ["id"] = "village-1", ["type"] = "village" });
        acceptedVillageMenu["state"]!["availableMenuOptions"] = new JsonArray(
            new JsonObject { ["id"] = "village_center", ["available"] = true, ["enabled"] = true, ["isLeave"] = false },
            new JsonObject { ["id"] = "trade", ["text"] = "Trade", ["available"] = true, ["enabled"] = true, ["isLeave"] = false },
            new JsonObject { ["id"] = "leave", ["available"] = true, ["enabled"] = true, ["isLeave"] = true });
        var villageMenuCatalog = BuildActionCatalog(acceptedVillageMenu, null);
        var villageMenuSelect = villageMenuCatalog.OfType<JsonObject>().FirstOrDefault(item => ReadString(item, "action") == "menuSelect");
        var villageMenuIds = (villageMenuSelect?["argumentValues"]?["OptionId"] as JsonArray)?.Select(item => item?.GetValue<string>()).ToArray() ?? Array.Empty<string?>();
        if (villageMenuSelect is null || villageMenuIds.Contains("village_center", StringComparer.Ordinal) ||
            villageMenuIds.Contains("trade", StringComparer.Ordinal) || !villageMenuIds.Contains("leave", StringComparer.Ordinal))
            throw new AgentHostException("village-tools-policy-self-test-village-trade-gate-failed", "Village Trade is visible to the player but is not a supported Town merchant transaction.");
        var acceptedTownMenu = State("MapState", "town", "town-1", quests: new JsonArray(new JsonObject { ["id"] = "quest-tools", ["title"] = "Village Needs Tools" }));
        acceptedTownMenu["state"]!["nearbySettlements"] = new JsonArray(new JsonObject { ["id"] = "town-1", ["type"] = "town" });
        acceptedTownMenu["state"]!["availableMenuOptions"] = acceptedVillageMenu["state"]!["availableMenuOptions"]!.DeepClone();
        var townMenuCatalog = BuildActionCatalog(acceptedTownMenu, null);
        var townMenuSelect = townMenuCatalog.OfType<JsonObject>().FirstOrDefault(item => ReadString(item, "action") == "menuSelect");
        var townMenuIds = (townMenuSelect?["argumentValues"]?["OptionId"] as JsonArray)?.Select(item => item?.GetValue<string>()).ToArray() ?? Array.Empty<string?>();
        if (townMenuSelect is null || !townMenuIds.Contains("trade", StringComparer.Ordinal) || townMenuIds.Contains("leave", StringComparer.Ordinal))
            throw new AgentHostException("village-tools-policy-self-test-town-trade-gate-failed", "Before checking the Town merchant, the model must trade first rather than leave and revisit the same Town.");
        var noMarketReceipt = new JsonObject { ["action"] = "tradeCancel", ["status"] = "completed" };
        var afterEmptyMarket = BuildActionCatalog(acceptedTownMenu, noMarketReceipt);
        var afterEmptyMarketSelect = afterEmptyMarket.OfType<JsonObject>().FirstOrDefault(item => ReadString(item, "action") == "menuSelect");
        var afterEmptyMarketIds = (afterEmptyMarketSelect?["argumentValues"]?["OptionId"] as JsonArray)?.Select(item => item?.GetValue<string>()).ToArray() ?? Array.Empty<string?>();
        if (afterEmptyMarketSelect is null || afterEmptyMarketIds.Contains("trade", StringComparer.Ordinal) || !afterEmptyMarketIds.Contains("leave", StringComparer.Ordinal))
            throw new AgentHostException("village-tools-policy-self-test-empty-town-market-gate-failed", "After the current Town market has no tools, the model must leave and replan rather than reopen the same market.");
        results.Add(new { scenario = "village-tools-policy-gates-trade-to-town-native-merchant", passed = true });

        var emptyConversation = State("MapState", null, null, null, conversation: new JsonObject { ["options"] = new JsonArray() });
        if (ReadString(BuildActionCatalog(emptyConversation, null)[0] as JsonObject, "action") != "dialogueContinue" ||
            BuildActionCatalog(State("MapState", "encounter_meeting", null, null, conversation: new JsonObject { ["options"] = new JsonArray() }), null).Count != 0)
            throw new AgentHostException("village-tools-policy-self-test-dialogue-safety-failed", "Only an empty non-hostile Native conversation may expose dialogueContinue; encounters must stop safely.");
        results.Add(new { scenario = "village-tools-policy-rejects-hostile-encounter-dialogue", passed = true });

        var questState = State("MapState", "village", "village-1", quests: new JsonArray(new JsonObject { ["id"] = "quest-tools", ["title"] = "Village Needs Tools" }));
        var questCatalog = BuildActionCatalog(questState, null);
        if (!questCatalog.OfType<JsonObject>().Any(action => ReadString(action, "action") == "questDetails") ||
            !TryResolveAction(questState, null, new JsonObject { ["action"] = "questDetails", ["arguments"] = new JsonObject { ["QuestId"] = "quest-tools" } }, out _, out _, out _) ||
            TryResolveAction(questState, null, new JsonObject { ["action"] = "questDetails", ["arguments"] = new JsonObject { ["QuestId"] = "hidden-quest" } }, out _, out _, out _))
            throw new AgentHostException("village-tools-policy-self-test-quest-id-gate-failed", "Quest details may target only the currently observed supported quest ID.");
        results.Add(new { scenario = "village-tools-policy-quest-details-bind-current-visible-quest-id", passed = true });
        var afterJournalCatalog = BuildActionCatalog(questState, null, questDetailsObserved: true);
        if (afterJournalCatalog.OfType<JsonObject>().Any(action => ReadString(action, "action") == "questDetails") ||
            !afterJournalCatalog.OfType<JsonObject>().Any(action => ReadString(action, "action") == "menuSelect"))
            throw new AgentHostException("village-tools-policy-self-test-quest-details-once-failed", "After the active Quest journal has been observed, the model must not loop on the same query and should receive the current leave option.");
        results.Add(new { scenario = "village-tools-policy-removes-redundant-journal-query-after-observation", passed = true });

        var tradeState = State("InventoryState", null, "town-1", quests: new JsonArray(new JsonObject { ["id"] = "quest-tools", ["title"] = "Village Needs Tools" }));
        tradeState["state"]!["inventoryScreen"] = new JsonObject { ["mode"] = "Trade" };
        var tradeOptionsReceipt = new JsonObject
        {
            ["action"] = "tradeOptions", ["status"] = "completed", ["data"] = new JsonObject
            {
                ["buyOffers"] = new JsonArray
                {
                    new JsonObject { ["viewModelItemId"] = "tools-offer", ["itemId"] = "tools", ["name"] = "Tools", ["inventorySide"] = "OtherInventory", ["stock"] = 2, ["isTransferable"] = true },
                    new JsonObject { ["viewModelItemId"] = "grain-offer", ["itemId"] = "grain", ["name"] = "Grain", ["inventorySide"] = "OtherInventory", ["stock"] = 5, ["isTransferable"] = true }
                }
            }
        };
        var tradeCatalog = BuildActionCatalog(tradeState, tradeOptionsReceipt);
        if (!tradeCatalog.OfType<JsonObject>().Any(action => ReadString(action, "action") == "trade") ||
            !TryResolveAction(tradeState, tradeOptionsReceipt, new JsonObject { ["action"] = "trade", ["arguments"] = new JsonObject { ["Direction"] = "buy", ["ItemViewModelId"] = "tools-offer", ["InventorySide"] = "OtherInventory", ["Amount"] = 1 } }, out _, out _, out _) ||
            TryResolveAction(tradeState, tradeOptionsReceipt, new JsonObject { ["action"] = "trade", ["arguments"] = new JsonObject { ["Direction"] = "buy", ["ItemViewModelId"] = "grain-offer", ["InventorySide"] = "OtherInventory", ["Amount"] = 1 } }, out _, out _, out _))
            throw new AgentHostException("village-tools-policy-self-test-trade-offer-gate-failed", "Only a current transferable Tools offer may be drafted for the bounded quest.");
        results.Add(new { scenario = "village-tools-policy-trade-binds-current-tools-offer", passed = true });

        var noToolsMarket = new JsonObject { ["action"] = "tradeOptions", ["status"] = "completed", ["data"] = new JsonObject { ["buyOffers"] = new JsonArray() } };
        var noToolsCatalog = BuildActionCatalog(tradeState, noToolsMarket);
        if (ReadString(noToolsCatalog[0] as JsonObject, "action") != "tradeCancel" ||
            !TryResolveAction(tradeState, noToolsMarket, new JsonObject { ["action"] = "tradeCancel", ["arguments"] = new JsonObject() }, out _, out _, out _))
            throw new AgentHostException("village-tools-policy-self-test-empty-market-exit-failed", "An empty Native tools market must expose the original transaction cancel/exit action, not stall or repeat the market query.");
        results.Add(new { scenario = "village-tools-policy-leaves-native-market-without-tools", passed = true });

        var tradeDraft = new JsonObject { ["action"] = "trade", ["status"] = "completed", ["data"] = new JsonObject { ["nativeCanCompleteTransaction"] = true } };
        if (ReadString(BuildActionCatalog(tradeState, tradeDraft)[0] as JsonObject, "action") != "tradeConfirm" ||
            !TryResolveAction(tradeState, tradeDraft, new JsonObject { ["action"] = "tradeConfirm", ["arguments"] = new JsonObject() }, out _, out _, out _) ||
            TryResolveAction(tradeState, tradeDraft, new JsonObject { ["action"] = "inventoryConfirm", ["arguments"] = new JsonObject() }, out _, out _, out _))
            throw new AgentHostException("village-tools-policy-self-test-trade-commit-gate-failed", "Only a current completable Native Trade draft may be confirmed, through its Trade action.");
        results.Add(new { scenario = "village-tools-policy-confirms-only-current-native-trade-draft", passed = true });

        var inventoryState = State("InventoryState", null, "village-1");
        inventoryState["state"]!["inventoryScreen"] = new JsonObject { ["mode"] = "Default" };
        var inventoryOpen = new JsonObject { ["action"] = "inventoryOpen", ["status"] = "completed" };
        var inventoryOptions = new JsonObject { ["action"] = "heroEquipmentOptions", ["status"] = "completed" };
        if (ReadString(BuildActionCatalog(inventoryState, inventoryOpen)[0] as JsonObject, "action") != "heroEquipmentOptions" ||
            ReadString(BuildActionCatalog(inventoryState, inventoryOptions)[0] as JsonObject, "action") != "inventoryCancel" ||
            !TryResolveAction(inventoryState, inventoryOptions, new JsonObject { ["action"] = "inventoryCancel", ["arguments"] = new JsonObject() }, out _, out _, out _))
            throw new AgentHostException("village-tools-policy-self-test-inventory-verify-cycle-failed", "The Host must read MainHero inventory through the Native VM and return without a mutation.");
        results.Add(new { scenario = "village-tools-policy-native-inventory-verify-returns-without-commit", passed = true });

        var completedJournalReceipt = new JsonObject
        {
            ["action"] = "questDetails", ["status"] = "completed", ["data"] = new JsonObject
            {
                ["journalStages"] = new JsonArray(new JsonObject { ["hasTask"] = true, ["taskName"] = "tools", ["currentProgress"] = 1, ["targetProgress"] = 1 })
            }
        };
        var activeToolsQuest = State("MapState", "village", "village-1", overlay, quests: new JsonArray(new JsonObject { ["id"] = "quest-tools", ["title"] = "Village Needs Tools" }));
        var baselineCatalog = BuildActionCatalog(activeToolsQuest, completedJournalReceipt);
        if (baselineCatalog.Count != 2 || !baselineCatalog.OfType<JsonObject>().Any(item => ReadString(item, "action") == "inventoryOpen") ||
            baselineCatalog.OfType<JsonObject>().Any(item => ReadString(item, "action") == "talkToSettlementHero") ||
            !TryResolveAction(activeToolsQuest, completedJournalReceipt, new JsonObject { ["action"] = "inventoryOpen", ["arguments"] = new JsonObject() }, out _, out _, out _))
            throw new AgentHostException("village-tools-policy-self-test-pre-delivery-inventory-gate-failed", "Before delivery, the current completed Journal task must force a Native inventory baseline before reopening the giver conversation.");
        if (BuildControlCatalog(inventoryState, questWasObservedActive: true, inventoryVerifiedAfterTurnIn: true).Any(control => control?.GetValue<string>() == "done") ||
            !BuildControlCatalog(State("MapState", null, null), questWasObservedActive: true, inventoryVerifiedAfterTurnIn: true).Any(control => control?.GetValue<string>() == "done"))
            throw new AgentHostException("village-tools-policy-self-test-done-context-gate-failed", "The done control is available only on unobstructed Campaign Map after the Quest is absent and post-turn-in Inventory is verified.");
        results.Add(new { scenario = "village-tools-policy-captures-pre-delivery-inventory-and-gates-done-on-map", passed = true });
        return results;
    }

    private static JsonArray BuildInventoryActionCatalog(JsonObject state, JsonObject? previousReceipt)
    {
        var inventory = state["inventoryScreen"] as JsonObject;
        var mode = ReadString(inventory, "mode");
        var previousAction = ReadString(previousReceipt, "action");
        if (mode == "Trade")
        {
            if (previousAction == "tradeOptions" && ReadString(previousReceipt, "status") == "completed")
                return HasCurrentToolsBuyOffer(previousReceipt)
                    ? new JsonArray(new JsonObject { ["action"] = "trade", ["arguments"] = new JsonArray("Direction", "ItemViewModelId", "InventorySide", "Amount") })
                    : new JsonArray(new JsonObject { ["action"] = "tradeCancel", ["arguments"] = new JsonArray() });
            if (previousAction == "trade" && ReadString(previousReceipt, "status") == "completed")
                return ReadBoolean(previousReceipt?["data"] as JsonObject, "nativeCanCompleteTransaction")
                    ? new JsonArray(new JsonObject { ["action"] = "tradeConfirm", ["arguments"] = new JsonArray() })
                    : new JsonArray(new JsonObject { ["action"] = "tradeCancelChanges", ["arguments"] = new JsonArray() });
            return new JsonArray(new JsonObject { ["action"] = "tradeOptions", ["arguments"] = new JsonArray() });
        }

        if (mode == "Default")
        {
            if (previousAction == "inventoryOpen" && ReadString(previousReceipt, "status") == "completed")
                return new JsonArray(new JsonObject { ["action"] = "heroEquipmentOptions", ["arguments"] = new JsonArray() });
            if (previousAction == "heroEquipmentOptions" && ReadString(previousReceipt, "status") == "completed")
                return new JsonArray(new JsonObject { ["action"] = "inventoryCancel", ["arguments"] = new JsonArray() });
        }
        return new JsonArray();
    }

    private static bool TryResolveInventoryAction(JsonObject state, JsonObject? previousReceipt, string action, JsonObject arguments, out JsonObject? nativeArguments, out string rejection)
    {
        nativeArguments = null;
        var inventory = state["inventoryScreen"] as JsonObject;
        var mode = ReadString(inventory, "mode");
        if (mode == "Trade")
        {
            if (action == "tradeOptions" && arguments.Count == 0)
            {
                nativeArguments = new JsonObject();
                rejection = string.Empty;
                return true;
            }
            if (action == "trade" && arguments.Count == 4 && ReadString(previousReceipt, "action") == "tradeOptions" &&
                ReadString(previousReceipt, "status") == "completed")
            {
                var direction = ReadString(arguments, "Direction");
                var itemViewModelId = ReadString(arguments, "ItemViewModelId");
                var inventorySide = ReadString(arguments, "InventorySide");
                var amount = ReadInteger(arguments, "Amount");
                var offer = (previousReceipt?["data"]?["buyOffers"] as JsonArray)?.OfType<JsonObject>()
                    .FirstOrDefault(candidate => ReadString(candidate, "viewModelItemId") == itemViewModelId);
                if (direction == "buy" && inventorySide == "OtherInventory" && amount is > 0 && offer is not null &&
                    IsCurrentToolsOffer(offer) && IsTrue(offer, "isTransferable") && amount <= ReadInteger(offer, "stock"))
                {
                    nativeArguments = new JsonObject
                    {
                        ["direction"] = "buy",
                        ["itemViewModelId"] = itemViewModelId,
                        ["inventorySide"] = "OtherInventory",
                        ["amount"] = amount
                    };
                    rejection = string.Empty;
                    return true;
                }
            }
            if (action == "tradeConfirm" && arguments.Count == 0 && ReadString(previousReceipt, "action") == "trade" &&
                ReadString(previousReceipt, "status") == "completed" && ReadBoolean(previousReceipt?["data"] as JsonObject, "nativeCanCompleteTransaction"))
            {
                nativeArguments = new JsonObject();
                rejection = string.Empty;
                return true;
            }
            if (action == "tradeCancel" && arguments.Count == 0 && ReadString(previousReceipt, "action") == "tradeOptions" &&
                ReadString(previousReceipt, "status") == "completed" && !HasCurrentToolsBuyOffer(previousReceipt))
            {
                nativeArguments = new JsonObject();
                rejection = string.Empty;
                return true;
            }
            if (action == "tradeCancelChanges" && arguments.Count == 0 && ReadString(previousReceipt, "action") == "trade" &&
                ReadString(previousReceipt, "status") == "completed" && !ReadBoolean(previousReceipt?["data"] as JsonObject, "nativeCanCompleteTransaction"))
            {
                nativeArguments = new JsonObject();
                rejection = string.Empty;
                return true;
            }
        }
        else if (mode == "Default")
        {
            if (arguments.Count == 0 && action == "heroEquipmentOptions" && ReadString(previousReceipt, "action") == "inventoryOpen" && ReadString(previousReceipt, "status") == "completed")
            {
                nativeArguments = new JsonObject();
                rejection = string.Empty;
                return true;
            }
            if (arguments.Count == 0 && action == "inventoryCancel" && ReadString(previousReceipt, "action") == "heroEquipmentOptions" && ReadString(previousReceipt, "status") == "completed")
            {
                nativeArguments = new JsonObject();
                rejection = string.Empty;
                return true;
            }
        }
        rejection = "The selected inventory action is not authorized by the current Native inventory mode and receipt.";
        return false;
    }

    private static JsonObject State(string gameState, string? menuId, string? currentSettlementId, JsonArray? overlay = null, JsonObject? conversation = null, JsonArray? quests = null)
    {
        var state = new JsonObject
        {
            ["context"] = new JsonObject { ["gameState"] = gameState, ["menuId"] = menuId, ["conversation"] = conversation },
            ["location"] = new JsonObject { ["currentSettlementId"] = currentSettlementId, ["targetSettlementId"] = null },
            ["settlementOverlayCharacters"] = overlay?.DeepClone() as JsonArray ?? new JsonArray(),
            ["quests"] = quests?.DeepClone() as JsonArray ?? new JsonArray(),
            ["inventoryScreen"] = null,
            ["availableMenuOptions"] = new JsonArray(new JsonObject { ["id"] = "leave", ["text"] = "Leave", ["isLeave"] = true, ["available"] = true, ["enabled"] = true })
        };
        return new JsonObject { ["status"] = "completed", ["state"] = state };
    }

    private static IReadOnlyList<string> GetVisibleToolsQuestGiverIds(JsonObject state)
    {
        var characters = state["settlementOverlayCharacters"] as JsonArray ?? new JsonArray();
        return characters.OfType<JsonObject>()
            .Where(character => (character["questMarkers"] as JsonArray)?.OfType<JsonObject>().Any(marker =>
                ReadString(marker, "type") == "AvailableIssue" && IsToolsMarker(marker)) == true)
            .Select(character => ReadString(character, "heroId"))
            .Where(id => !string.IsNullOrWhiteSpace(id))
            .Cast<string>()
            .ToArray();
    }

    private static IReadOnlyList<string> GetAllowedToolsQuestGiverIds(JsonObject state, JsonObject? previousReceipt)
    {
        var ids = new HashSet<string>(GetVisibleToolsQuestGiverIds(state), StringComparer.Ordinal);
        if (HasActiveToolsQuest(state) && ReadString(previousReceipt, "action") == "questDetails" && ReadString(previousReceipt, "status") == "completed")
        {
            var giverId = ReadString(previousReceipt?["data"]?["questGiver"] as JsonObject, "id");
            if (!string.IsNullOrWhiteSpace(giverId) &&
                (state["settlementOverlayCharacters"] as JsonArray)?.OfType<JsonObject>().Any(character => ReadString(character, "heroId") == giverId) == true)
                ids.Add(giverId);
        }
        return ids.ToArray();
    }

    private static string? GetCurrentSettlementType(JsonObject state)
    {
        var currentSettlementId = ReadString(state["location"] as JsonObject, "currentSettlementId");
        if (string.IsNullOrWhiteSpace(currentSettlementId)) return null;
        return (state["nearbySettlements"] as JsonArray)?.OfType<JsonObject>()
            .FirstOrDefault(settlement => string.Equals(ReadString(settlement, "id"), currentSettlementId, StringComparison.Ordinal)) is JsonObject current
            ? ReadString(current, "type")
            : null;
    }

    private static bool IsToolsMarker(JsonObject marker)
    {
        var text = (ReadString(marker, "title") ?? string.Empty) + " " + (ReadString(marker, "hint") ?? string.Empty);
        return text.Contains("工具", StringComparison.Ordinal) || text.Contains("tool", StringComparison.OrdinalIgnoreCase);
    }

    private static JsonArray? GetTargetsFromReceipt(JsonObject? receipt) =>
        ReadString(receipt, "action") == "mapSettlementTargets" && ReadString(receipt, "status") == "completed"
            ? receipt?["data"]?["mapSettlementTargets"] as JsonArray
            : null;

    private static JsonArray FilterSafeTargets(JsonArray targets, string requiredType) => new(targets.OfType<JsonObject>()
        .Where(target => ReadString(target, "type") == requiredType && IsFalse(target, "hostile") && IsFalse(target, "underSiege") &&
            !string.IsNullOrWhiteSpace(ReadString(target, "id")) && ReadDouble(target, "distance", double.MaxValue) > 1.0)
        .GroupBy(target => ReadString(target, "id")!, StringComparer.Ordinal)
        .Select(group => group.First())
        .Select(target => (JsonNode?)target.DeepClone()).ToArray());

    private static bool IsTradeOption(JsonObject option)
    {
        var id = ReadString(option, "id") ?? string.Empty;
        var text = ReadString(option, "text") ?? string.Empty;
        return id.Contains("trade", StringComparison.OrdinalIgnoreCase) || text.Contains("交易", StringComparison.Ordinal) || text.Contains("trade", StringComparison.OrdinalIgnoreCase);
    }

    private static IReadOnlyList<string> ActiveToolsQuestIds(JsonObject state) =>
        (state["quests"] as JsonArray)?.OfType<JsonObject>()
            .Where(quest =>
            {
                var title = ReadString(quest, "title") ?? string.Empty;
                return title.Contains("工具", StringComparison.Ordinal) || title.Contains("tool", StringComparison.OrdinalIgnoreCase);
            })
            .Select(quest => ReadString(quest, "id"))
            .Where(id => !string.IsNullOrWhiteSpace(id))
            .Cast<string>()
            .ToArray() ?? Array.Empty<string>();

    private static void AddQuestDetailsAction(JsonObject state, JsonArray catalog, bool questDetailsObserved)
    {
        if (!questDetailsObserved && ActiveToolsQuestIds(state).Count > 0)
            catalog.Add(new JsonObject { ["action"] = "questDetails", ["arguments"] = new JsonArray("QuestId") });
    }

    private static bool HasCurrentToolsBuyOffer(JsonObject? receipt) =>
        (receipt?["data"]?["buyOffers"] as JsonArray)?.OfType<JsonObject>().Any(IsCurrentToolsOffer) == true;

    private static bool IsCurrentToolsOffer(JsonObject offer)
    {
        var itemId = ReadString(offer, "itemId") ?? string.Empty;
        var name = ReadString(offer, "name") ?? string.Empty;
        return (itemId == "tools" || name.Contains("工具", StringComparison.Ordinal) || name.Contains("tool", StringComparison.OrdinalIgnoreCase)) &&
            ReadString(offer, "inventorySide") == "OtherInventory";
    }

    private static bool IsToolsTaskSatisfied(JsonObject? receipt)
    {
        if (ReadString(receipt, "action") != "questDetails" || ReadString(receipt, "status") != "completed") return false;
        var task = (receipt?["data"]?["journalStages"] as JsonArray)?.OfType<JsonObject>()
            .FirstOrDefault(stage => ReadBoolean(stage, "hasTask"));
        var current = task?["currentProgress"] is JsonValue currentValue && currentValue.TryGetValue<int>(out var currentCount) ? currentCount : -1;
        var target = task?["targetProgress"] is JsonValue targetValue && targetValue.TryGetValue<int>(out var targetCount) ? targetCount : -1;
        var taskName = ReadString(task, "taskName") ?? string.Empty;
        return current >= 0 && target > 0 && current >= target &&
            (taskName.Contains("tool", StringComparison.OrdinalIgnoreCase) || taskName.Contains("工具", StringComparison.Ordinal));
    }

    private static string? ReadString(JsonObject? value, string name) => value?[name] is JsonValue node && node.TryGetValue<string>(out var result) ? result : null;
    private static bool ReadBoolean(JsonObject? value, string name) => value?[name] is JsonValue node && node.TryGetValue<bool>(out var result) && result;
    private static int? ReadInteger(JsonObject? value, string name) => value?[name] is JsonValue node && node.TryGetValue<int>(out var result) ? result : null;
    private static bool IsTrue(JsonObject value, string name) => ReadBoolean(value, name);
    private static bool IsFalse(JsonObject value, string name) => value[name] is JsonValue node && node.TryGetValue<bool>(out var result) && !result;
    private static double ReadDouble(JsonObject value, string name, double fallback) => value[name] is JsonValue node && node.TryGetValue<double>(out var result) ? result : fallback;

    private static bool HasActiveToolsQuest(JsonObject state) =>
        (state["quests"] as JsonArray)?.OfType<JsonObject>().Any(quest =>
        {
            var title = ReadString(quest, "title") ?? string.Empty;
            return title.Contains("工具", StringComparison.Ordinal) || title.Contains("tool", StringComparison.OrdinalIgnoreCase);
        }) == true;
}
