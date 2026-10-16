using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal static class AgentHostVillageToolsQuestPolicy
{
    internal static JsonArray BuildActionCatalog(JsonObject native, JsonObject? previousReceipt, bool preDeliveryInventoryCaptured = false, bool questDetailsObserved = false, IReadOnlySet<string>? marketsWithoutTools = null, JsonObject? safePassageBalanceReceipt = null, JsonObject? questDetailsReceipt = null, bool safePassageContinueUsed = false)
    {
        var state = native["state"] as JsonObject;
        var context = state?["context"] as JsonObject;
        var location = state?["location"] as JsonObject;
        if (state is null || context is null) return new JsonArray();

        var menuId = ReadString(context, "menuId");
        var conversation = context["conversation"] as JsonObject;
        if (conversation is not null)
        {
            if (string.Equals(menuId, "encounter_meeting", StringComparison.Ordinal))
                return BuildBanditSafePassageCatalog(state, context, conversation, previousReceipt, safePassageBalanceReceipt, safePassageContinueUsed);
            var catalog = new JsonArray();
            AddQuestDetailsAction(state, catalog, questDetailsObserved);
            var clickableOptions = GetAllowedDialogueOptions(state, conversation, previousReceipt, questDetailsReceipt);
            if (clickableOptions.Count > 0)
            {
                var optionIds = new JsonArray(clickableOptions.Select(option => (JsonNode?)JsonValue.Create(ReadString(option, "id"))).ToArray());
                catalog.Add(new JsonObject
                {
                    ["action"] = "dialogueSelect",
                    ["arguments"] = new JsonArray("OptionId"),
                    ["argumentValues"] = new JsonObject { ["OptionId"] = optionIds }
                });
            }
            else if (!HasClickableConversationOptions(conversation))
                catalog.Add(new JsonObject { ["action"] = "dialogueContinue", ["arguments"] = new JsonArray() });
            return catalog;
        }

        var gameState = ReadString(context, "gameState");
        if (string.Equals(gameState, "InventoryState", StringComparison.Ordinal))
            return BuildInventoryActionCatalog(state, previousReceipt, questDetailsReceipt);
        if (!string.Equals(gameState, "MapState", StringComparison.Ordinal))
            return new JsonArray();

        var currentSettlementId = ReadString(location, "currentSettlementId");
        var targetSettlementId = ReadString(location, "targetSettlementId");
        var hasToolsQuest = HasActiveToolsQuest(state);
        var visibleToolsIssueGivers = GetAllowedToolsQuestGiverIds(state, previousReceipt, questDetailsReceipt);
        if (!hasToolsQuest && visibleToolsIssueGivers.Count == 0)
            return new JsonArray();
        var catalogWithQuestDetails = new JsonArray();
        AddQuestDetailsAction(state, catalogWithQuestDetails, questDetailsObserved);

        if (hasToolsQuest && !preDeliveryInventoryCaptured && context["conversation"] is not JsonObject && IsToolsTaskSatisfied(questDetailsReceipt ?? previousReceipt))
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
            var markedGivers = GetAllowedToolsQuestGiverIds(state, previousReceipt, questDetailsReceipt);
            if (markedGivers.Count > 0 && (!hasToolsQuest || IsToolsTaskSatisfied(questDetailsReceipt ?? previousReceipt)))
            {
                catalogWithQuestDetails.Add(new JsonObject { ["action"] = "talkToSettlementHero", ["arguments"] = new JsonArray("HeroId") });
                return catalogWithQuestDetails;
            }

            var menuOptions = state["availableMenuOptions"] as JsonArray ?? new JsonArray();
            var tradeContextSupported = hasToolsQuest && string.Equals(GetCurrentSettlementType(state), "town", StringComparison.Ordinal);
            var townMarketAttemptFinished = IsToolsTaskSatisfied(questDetailsReceipt ?? previousReceipt) ||
                (ReadString(previousReceipt, "status") == "completed" && ReadString(previousReceipt, "action") is "tradeCancel" or "tradeCancelChanges" or "tradeConfirm");
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
            if (hasToolsQuest && !preDeliveryInventoryCaptured && IsToolsTaskSatisfied(questDetailsReceipt ?? previousReceipt))
                catalogWithQuestDetails.Add(new JsonObject { ["action"] = "inventoryOpen", ["arguments"] = new JsonArray() });
            return catalogWithQuestDetails;
        }

        if (hasToolsQuest && !preDeliveryInventoryCaptured && IsToolsTaskSatisfied(questDetailsReceipt ?? previousReceipt))
            catalogWithQuestDetails.Add(new JsonObject { ["action"] = "inventoryOpen", ["arguments"] = new JsonArray() });

        if (hasToolsQuest && string.IsNullOrWhiteSpace(currentSettlementId))
        {
            var observedTargets = GetTargetsFromReceipt(previousReceipt);
            if (observedTargets is null)
            {
                catalogWithQuestDetails.Add(new JsonObject { ["action"] = "mapSettlementTargets", ["arguments"] = new JsonArray() });
                return catalogWithQuestDetails;
            }

            var candidates = FilterSafeTargets(observedTargets, "town")
                .OfType<JsonObject>()
                .Where(candidate => marketsWithoutTools is null || !marketsWithoutTools.Contains(ReadString(candidate, "id") ?? string.Empty))
                .Select(candidate => (JsonObject)candidate.DeepClone())
                .ToArray();
            if (candidates.Length > 0)
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
        bool preDeliveryInventoryCaptured = false,
        JsonObject? safePassageBalanceReceipt = null,
        JsonObject? questDetailsReceipt = null,
        bool safePassageContinueUsed = false)
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
            return TryResolveInventoryAction(state, previousReceipt, questDetailsReceipt, action!, arguments, out nativeArguments, out rejection);

        if (string.Equals(menuId, "encounter_meeting", StringComparison.Ordinal))
            return TryResolveBanditSafePassageAction(state, context, conversation, previousReceipt, safePassageBalanceReceipt, safePassageContinueUsed, action!, arguments, out nativeArguments, out rejection);

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
                ((hasToolsQuest && !preDeliveryInventoryCaptured && IsToolsTaskSatisfied(questDetailsReceipt ?? previousReceipt)) ||
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
                var canContactGiver = !hasToolsQuest || IsToolsTaskSatisfied(questDetailsReceipt ?? previousReceipt);
                if (canContactGiver && GetAllowedToolsQuestGiverIds(state, previousReceipt, questDetailsReceipt).Contains(heroId, StringComparer.Ordinal))
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
                var option = GetAllowedDialogueOptions(state, conversation, previousReceipt, questDetailsReceipt)
                    .FirstOrDefault(item => ReadString(item, "id") == optionId);
                if (option is not null)
                {
                    nativeArguments = new JsonObject { ["optionId"] = optionId };
                    rejection = string.Empty;
                    return true;
                }
                break;
            }

            case "dialogueContinue" when arguments.Count == 0 && conversation is not null && menuId != "encounter_meeting" &&
                !HasClickableConversationOptions(conversation):
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
        var excludingCheckedMarketCatalog = BuildActionCatalog(activeMap, activeTargets, marketsWithoutTools: new HashSet<string>(["town-1"], StringComparer.Ordinal));
        if (excludingCheckedMarketCatalog.OfType<JsonObject>().Any(item => ReadString(item, "action") == "move"))
            throw new AgentHostException("village-tools-policy-self-test-market-exclusion-failed", "The route policy must not target a Town already observed to have no tools.");
        results.Add(new { scenario = "village-tools-policy-excludes-empty-market-from-route-catalog", passed = true });

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

        var initialIssueConversation = State("MapState", "village", "village-1", overlay: overlay, conversation: new JsonObject
        {
            ["options"] = new JsonArray(
                new JsonObject { ["id"] = "issue_explanation_player_response_pre_quest_solution", ["text"] = "Tell me the details.", ["clickable"] = true },
                new JsonObject { ["id"] = "issue_alternative_solution_player_response", ["text"] = "Can my men handle it?", ["clickable"] = true })
        });
        var initialIssueConversationCatalog = BuildActionCatalog(initialIssueConversation, null);
        var initialIssueDialogueSelect = initialIssueConversationCatalog.OfType<JsonObject>().FirstOrDefault(item => ReadString(item, "action") == "dialogueSelect");
        var initialIssueOptionIds = (initialIssueDialogueSelect?["argumentValues"]?["OptionId"] as JsonArray)?.Select(item => item?.GetValue<string>()).ToArray() ?? Array.Empty<string?>();
        if (!initialIssueOptionIds.Contains("issue_explanation_player_response_pre_quest_solution", StringComparer.Ordinal) ||
            !initialIssueOptionIds.Contains("issue_alternative_solution_player_response", StringComparer.Ordinal) ||
            !TryResolveAction(initialIssueConversation, null, new JsonObject { ["action"] = "dialogueSelect", ["arguments"] = new JsonObject { ["OptionId"] = "issue_explanation_player_response_pre_quest_solution" } }, out _, out _, out _) ||
            !TryResolveAction(initialIssueConversation, null, new JsonObject { ["action"] = "dialogueSelect", ["arguments"] = new JsonObject { ["OptionId"] = "issue_alternative_solution_player_response" } }, out _, out _, out _))
            throw new AgentHostException("village-tools-policy-self-test-alternative-explanation-navigation-blocked", "The Native response that opens the Alternative Solution explanation must remain navigable; it does not itself accept or dispatch that outcome.");
        results.Add(new { scenario = "village-tools-policy-allows-native-alternative-explanation-navigation", passed = true });

        var finalIssueOfferConversation = State("MapState", "village", "village-1", overlay: overlay, conversation: new JsonObject
        {
            ["options"] = new JsonArray(
                new JsonObject { ["id"] = "issue_offer_player_accept_quest", ["text"] = "I can handle this myself.", ["clickable"] = true },
                new JsonObject { ["id"] = "issue_offer_player_accept_alternative", ["text"] = "My men will deliver it.", ["clickable"] = true },
                new JsonObject { ["id"] = "issue_offer_player_response_reject", ["text"] = "Sorry, not now.", ["clickable"] = true })
        });
        var finalIssueOfferCatalog = BuildActionCatalog(finalIssueOfferConversation, null);
        var finalIssueOfferSelect = finalIssueOfferCatalog.OfType<JsonObject>().FirstOrDefault(item => ReadString(item, "action") == "dialogueSelect");
        var finalIssueOfferIds = (finalIssueOfferSelect?["argumentValues"]?["OptionId"] as JsonArray)?.Select(item => item?.GetValue<string>()).ToArray() ?? Array.Empty<string?>();
        if (!finalIssueOfferIds.Contains("issue_offer_player_accept_quest", StringComparer.Ordinal) ||
            !finalIssueOfferIds.Contains("issue_offer_player_response_reject", StringComparer.Ordinal) ||
            finalIssueOfferIds.Contains("issue_offer_player_accept_alternative", StringComparer.Ordinal) ||
            TryResolveAction(finalIssueOfferConversation, null, new JsonObject { ["action"] = "dialogueSelect", ["arguments"] = new JsonObject { ["OptionId"] = "issue_offer_player_accept_alternative" } }, out _, out _, out _))
            throw new AgentHostException("village-tools-policy-self-test-final-alternative-outcome-not-blocked", "At the final Native Issue offer, the standard Quest and rejection options may be used, but the companion/men Alternative acceptance must remain unavailable.");
        results.Add(new { scenario = "village-tools-policy-allows-direct-quest-and-reject-but-blocks-alternative-acceptance", passed = true });

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
        if (ReadString(BuildActionCatalog(emptyConversation, null)[0] as JsonObject, "action") != "dialogueContinue")
            throw new AgentHostException("village-tools-policy-self-test-dialogue-safety-failed", "An empty non-hostile Native conversation may expose its native continue action.");
        var banditQuest = new JsonArray(new JsonObject { ["id"] = "quest-tools", ["title"] = "Village Needs Tools" });
        var banditConversation = new JsonObject { ["options"] = new JsonArray(
            new JsonObject { ["id"] = "bandit_start_defender_1", ["text"] = "Fight", ["clickable"] = true },
            new JsonObject { ["id"] = "bandit_start_defender_2", ["text"] = "Talk", ["clickable"] = true }) };
        var banditEncounter = State("MapState", "encounter_meeting", null, conversation: banditConversation, quests: banditQuest);
        var banditContext = banditEncounter["state"]!["context"]!.AsObject();
        banditContext["encounterActive"] = true;
        banditContext["encounteredPartyId"] = "looters_1";
        banditEncounter["state"]!["nearbyParties"] = new JsonArray(new JsonObject { ["id"] = "looters_1", ["type"] = "bandit", ["hostile"] = true });
        var banditTalkCatalog = BuildActionCatalog(banditEncounter, null);
        var talkChoice = banditTalkCatalog.OfType<JsonObject>().FirstOrDefault(item => ReadString(item, "action") == "dialogueSelect");
        var talkOptionIds = (talkChoice?["argumentValues"]?["OptionId"] as JsonArray)?.Select(item => item?.GetValue<string>()).ToArray() ?? Array.Empty<string?>();
        if (talkChoice is null || !talkOptionIds.SequenceEqual(new string?[] { "bandit_start_defender_2" }, StringComparer.Ordinal) ||
            TryResolveAction(banditEncounter, null, new JsonObject { ["action"] = "dialogueSelect", ["arguments"] = new JsonObject { ["OptionId"] = "bandit_start_defender_1" } }, out _, out _, out _) ||
            !TryResolveAction(banditEncounter, null, new JsonObject { ["action"] = "dialogueSelect", ["arguments"] = new JsonObject { ["OptionId"] = "bandit_start_defender_2" } }, out _, out _, out _))
            throw new AgentHostException("village-tools-policy-self-test-bandit-option-gate-failed", "Only the current observed Native non-fight compromise option may be selected during a hostile Bandit encounter.");

        var noOptionBandit = State("MapState", "encounter_meeting", null, conversation: new JsonObject { ["options"] = new JsonArray() }, quests: banditQuest);
        var noOptionContext = noOptionBandit["state"]!["context"]!.AsObject();
        noOptionContext["encounterActive"] = true;
        noOptionContext["encounteredPartyId"] = "looters_1";
        noOptionBandit["state"]!["nearbyParties"] = new JsonArray(new JsonObject { ["id"] = "looters_1", ["type"] = "bandit", ["hostile"] = true });
        if (ReadString(BuildActionCatalog(noOptionBandit, null)[0] as JsonObject, "action") != "barterOptions" ||
            ReadString(BuildActionCatalog(noOptionBandit, new JsonObject { ["action"] = "barterOptions", ["status"] = "rejected" })[0] as JsonObject, "action") != "dialogueContinue" ||
            ReadString(BuildActionCatalog(noOptionBandit, new JsonObject { ["action"] = "dialogueContinue", ["status"] = "completed" })[0] as JsonObject, "action") != "barterOptions" ||
            BuildActionCatalog(noOptionBandit, new JsonObject { ["action"] = "barterOptions", ["status"] = "rejected" }, safePassageContinueUsed: true).Count != 0)
            throw new AgentHostException("village-tools-policy-self-test-bandit-probe-gate-failed", "A no-option Bandit transition must probe Barter, Continue only once when the probe is rejected, then re-probe once before stopping.");

        var initialPassageQuote = SafePassageReceipt("barterOptions", SafePassageOptions("session-1", "proposal-before", 500, 1, isOfferDisabled: true));
        if (ReadString(BuildActionCatalog(banditEncounter, initialPassageQuote)[0] as JsonObject, "action") != "barterAutoBalance" ||
            !TryResolveAction(banditEncounter, initialPassageQuote, new JsonObject { ["action"] = "barterAutoBalance", ["arguments"] = new JsonObject() }, out _, out _, out _))
            throw new AgentHostException("village-tools-policy-self-test-bandit-autobalance-gate-failed", "Only the current Native Safe Passage quote may be auto-balanced.");

        var balancedOptions = SafePassageOptions("session-1", "proposal-balanced", 500, 144, isOfferDisabled: false);
        var balancedPassageQuote = SafePassageReceipt("barterAutoBalance", balancedOptions, wrapAutoBalance: true);
        var currentPassageQuote = SafePassageReceipt("barterOptions", balancedOptions);
        var balancedPassageCatalog = BuildActionCatalog(banditEncounter, currentPassageQuote, safePassageBalanceReceipt: balancedPassageQuote);
        var balancedQuoteIsSafe = TryGetSafePassageQuote(balancedPassageQuote, out var parsedBalancedQuote);
        var balancedQuoteIsAffordable = balancedQuoteIsSafe && IsAffordableSafePassageQuote(parsedBalancedQuote);
        var validSafePassageOffer = TryResolveAction(banditEncounter, currentPassageQuote,
            new JsonObject { ["action"] = "barterOffer", ["arguments"] = new JsonObject() }, out _, out var nativeOfferArguments, out _, safePassageBalanceReceipt: balancedPassageQuote);
        var mismatchedPartyOptions = SafePassageOptions("session-1", "proposal-balanced", 500, 144, isOfferDisabled: false);
        mismatchedPartyOptions["candidates"]![0]!["originalPartyId"] = "looters_2";
        var mismatchedPartyReceipt = SafePassageReceipt("barterOptions", mismatchedPartyOptions);
        var mismatchedSessionReceipt = SafePassageReceipt("barterOptions", SafePassageOptions("session-replaced", "proposal-balanced", 500, 144, isOfferDisabled: false));
        var mismatchedFingerprintReceipt = SafePassageReceipt("barterOptions", SafePassageOptions("session-1", "proposal-replaced", 500, 144, isOfferDisabled: false));
        var exhaustedGoldReceipt = SafePassageReceipt("barterOptions", SafePassageOptions("session-1", "proposal-balanced", 144, 144, isOfferDisabled: false));
        var playerGoodsOptions = SafePassageOptions("session-1", "proposal-balanced", 500, 144, isOfferDisabled: false);
        playerGoodsOptions["candidates"]!.AsArray().Add(new JsonObject { ["nativeType"] = "weapon_barterable", ["list"] = "rightItem", ["currentAmount"] = 1, ["isOffered"] = true });
        var playerGoodsReceipt = SafePassageReceipt("barterOptions", playerGoodsOptions);
        bool CanOffer(JsonObject currentQuote) => TryResolveAction(banditEncounter, currentQuote,
            new JsonObject { ["action"] = "barterOffer", ["arguments"] = new JsonObject() }, out _, out _, out _, safePassageBalanceReceipt: balancedPassageQuote);
        if (!balancedPassageCatalog.OfType<JsonObject>().Any(item => ReadString(item, "action") == "barterOffer") ||
            !balancedPassageCatalog.OfType<JsonObject>().Any(item => ReadString(item, "action") == "barterCancel") ||
            !validSafePassageOffer || CanOffer(mismatchedPartyReceipt) || CanOffer(mismatchedSessionReceipt) || CanOffer(mismatchedFingerprintReceipt) ||
            CanOffer(exhaustedGoldReceipt) || CanOffer(playerGoodsReceipt) ||
            ReadString(nativeOfferArguments, "expectedSessionId") != "session-1" || ReadString(nativeOfferArguments, "expectedProposalFingerprint") != "proposal-balanced")
            throw new AgentHostException("village-tools-policy-self-test-safe-passage-quote-gate-failed", "Safe Passage offer authorization must match the current safe party, session, proposal fingerprint, and positive-Gold quote.");
        results.Add(new { scenario = "village-tools-policy-recovers-bandit-travel-only-through-current-safe-passage", passed = true });

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
        var toolsTaskReceipt = new JsonObject
        {
            ["action"] = "questDetails", ["status"] = "completed", ["data"] = new JsonObject
            {
                ["journalStages"] = new JsonArray(new JsonObject { ["hasTask"] = true, ["taskName"] = "tools", ["currentProgress"] = 0, ["targetProgress"] = 1 })
            }
        };
        var activeQuestGiverOverlay = new JsonArray(new JsonObject
        {
            ["heroId"] = "hero-tools",
            ["questMarkers"] = new JsonArray(new JsonObject { ["type"] = "ActiveIssue", ["title"] = "Needs Tools" })
        });
        var activeQuestDetails = toolsTaskReceipt.DeepClone().AsObject();
        activeQuestDetails["data"]!["questGiver"] = new JsonObject { ["id"] = "hero-tools" };
        var activeQuestConversation = State("MapState", "village", "village-1", overlay: activeQuestGiverOverlay,
            conversation: new JsonObject
            {
                ["options"] = new JsonArray(
                    new JsonObject { ["id"] = "hero_task_given", ["text"] = "About the task", ["clickable"] = true },
                    new JsonObject { ["id"] = "player_is_leaving_neutral_or_friendly", ["text"] = "I must leave now", ["clickable"] = true })
            },
            quests: new JsonArray(new JsonObject { ["id"] = "quest-tools", ["title"] = "Village Needs Tools" }));
        var activeQuestConversationCatalog = BuildActionCatalog(activeQuestConversation, null, questDetailsObserved: true, questDetailsReceipt: activeQuestDetails);
        var activeQuestConversationSelect = activeQuestConversationCatalog.OfType<JsonObject>().FirstOrDefault(item => ReadString(item, "action") == "dialogueSelect");
        var allowedActiveQuestDialogueIds = (activeQuestConversationSelect?["argumentValues"]?["OptionId"] as JsonArray)?.Select(item => item?.GetValue<string>()).ToArray() ?? Array.Empty<string?>();
        if (activeQuestConversationSelect is null || !allowedActiveQuestDialogueIds.SequenceEqual(new string?[] { "player_is_leaving_neutral_or_friendly" }, StringComparer.Ordinal) ||
            TryResolveAction(activeQuestConversation, null, new JsonObject { ["action"] = "dialogueSelect", ["arguments"] = new JsonObject { ["OptionId"] = "hero_task_given" } }, out _, out _, out _, questDetailsReceipt: activeQuestDetails) ||
            !TryResolveAction(activeQuestConversation, null, new JsonObject { ["action"] = "dialogueSelect", ["arguments"] = new JsonObject { ["OptionId"] = "player_is_leaving_neutral_or_friendly" } }, out _, out _, out _, questDetailsReceipt: activeQuestDetails))
            throw new AgentHostException("village-tools-policy-self-test-active-quest-dialogue-exit-gate-failed", "Once the tools Quest is active but the item count is still short, the current conversation must allow only the native leave option, not more task chatter.");
        results.Add(new { scenario = "village-tools-active-quest-dialogue-allows-leave-only-before-tools-obtained", passed = true });

        var activeQuestVillageMenu = State("MapState", "village", "village-1", overlay: activeQuestGiverOverlay,
            quests: new JsonArray(new JsonObject { ["id"] = "quest-tools", ["title"] = "Village Needs Tools" }));
        var activeQuestVillageCatalog = BuildActionCatalog(activeQuestVillageMenu, null, questDetailsObserved: true, questDetailsReceipt: activeQuestDetails);
        var activeQuestMenuSelect = activeQuestVillageCatalog.OfType<JsonObject>().FirstOrDefault(item => ReadString(item, "action") == "menuSelect");
        if (activeQuestVillageCatalog.OfType<JsonObject>().Any(item => ReadString(item, "action") == "talkToSettlementHero") ||
            (activeQuestMenuSelect?["argumentValues"]?["OptionId"] as JsonArray)?.Any(item => item?.GetValue<string>() == "leave") != true)
            throw new AgentHostException("village-tools-policy-self-test-active-quest-village-exit-gate-failed", "With an active unsatisfied Quest at its giver's Village menu, the Host must expose leaving for market travel instead of reopening dialogue.");
        var satisfiedTaskReceipt = activeQuestDetails.DeepClone().AsObject();
        satisfiedTaskReceipt["data"]!["journalStages"]![0]!["currentProgress"] = 1;
        var deliveryVillageCatalog = BuildActionCatalog(activeQuestVillageMenu, null, preDeliveryInventoryCaptured: true, questDetailsObserved: true, questDetailsReceipt: satisfiedTaskReceipt);
        if (!deliveryVillageCatalog.OfType<JsonObject>().Any(item => ReadString(item, "action") == "talkToSettlementHero") ||
            !TryResolveAction(activeQuestVillageMenu, null, new JsonObject { ["action"] = "talkToSettlementHero", ["arguments"] = new JsonObject { ["HeroId"] = "hero-tools" } }, out _, out _, out _, preDeliveryInventoryCaptured: true, questDetailsReceipt: satisfiedTaskReceipt))
            throw new AgentHostException("village-tools-policy-self-test-delivery-giver-gate-failed", "After the requested tools are present and a pre-delivery inventory baseline is captured, the Native giver conversation must reopen for turn-in.");
        results.Add(new { scenario = "village-tools-active-quest-giver-reopens-only-after-tools-and-inventory-baseline", passed = true });
        var tradeOptionsReceipt = new JsonObject
        {
            ["action"] = "tradeOptions", ["status"] = "completed", ["data"] = new JsonObject
            {
                ["playerGold"] = 100,
                ["buyOffers"] = new JsonArray
                {
                    new JsonObject { ["viewModelItemId"] = "tools-offer", ["itemId"] = "tools", ["name"] = "Tools", ["inventorySide"] = "OtherInventory", ["stock"] = 2, ["nativeItemCost"] = 20, ["inventoryLogicUnitPrice"] = 20, ["isTransferable"] = true },
                    new JsonObject { ["viewModelItemId"] = "grain-offer", ["itemId"] = "grain", ["name"] = "Grain", ["inventorySide"] = "OtherInventory", ["stock"] = 5, ["isTransferable"] = true }
                }
            }
        };
        var tradeCatalog = BuildActionCatalog(tradeState, tradeOptionsReceipt, questDetailsReceipt: toolsTaskReceipt);
        var allowedTrade = tradeCatalog.OfType<JsonObject>().FirstOrDefault(action => ReadString(action, "action") == "trade");
        var tradeValues = allowedTrade?["argumentValues"] as JsonObject;
        if (allowedTrade is null ||
            (tradeValues?["Direction"] as JsonArray)?.Any(value => value?.GetValue<string>() == "buy") != true ||
            (tradeValues?["ItemViewModelId"] as JsonArray)?.Any(value => value?.GetValue<string>() == "tools-offer") != true ||
            (tradeValues?["InventorySide"] as JsonArray)?.Any(value => value?.GetValue<string>() == "OtherInventory") != true ||
            (tradeValues?["Amount"] as JsonArray)?.Any(value => value?.GetValue<int>() == 1) != true ||
            !TryResolveAction(tradeState, tradeOptionsReceipt, new JsonObject { ["action"] = "trade", ["arguments"] = new JsonObject { ["Direction"] = "buy", ["ItemViewModelId"] = "tools-offer", ["InventorySide"] = "OtherInventory", ["Amount"] = 1 } }, out _, out _, out _, questDetailsReceipt: toolsTaskReceipt) ||
            TryResolveAction(tradeState, tradeOptionsReceipt, new JsonObject { ["action"] = "trade", ["arguments"] = new JsonObject { ["Direction"] = "Buy", ["ItemViewModelId"] = "tools-offer", ["InventorySide"] = "OtherInventory", ["Amount"] = 1 } }, out _, out _, out _, questDetailsReceipt: toolsTaskReceipt) ||
            TryResolveAction(tradeState, tradeOptionsReceipt, new JsonObject { ["action"] = "trade", ["arguments"] = new JsonObject { ["Direction"] = "buy", ["ItemViewModelId"] = "tools-offer", ["InventorySide"] = "OtherInventory", ["Amount"] = 2 } }, out _, out _, out _, questDetailsReceipt: toolsTaskReceipt) ||
            TryResolveAction(tradeState, tradeOptionsReceipt, new JsonObject { ["action"] = "trade", ["arguments"] = new JsonObject { ["Direction"] = "buy", ["ItemViewModelId"] = "grain-offer", ["InventorySide"] = "OtherInventory", ["Amount"] = 1 } }, out _, out _, out _, questDetailsReceipt: toolsTaskReceipt))
            throw new AgentHostException("village-tools-policy-self-test-trade-offer-gate-failed", "Trade must expose exact Native string enums and the currently needed quantity, and reject wrong case, overbuying, or unrelated goods.");
        results.Add(new { scenario = "village-tools-policy-trade-binds-current-tools-offer-and-exact-journal-quantity", passed = true });

        var noToolsMarket = new JsonObject { ["action"] = "tradeOptions", ["status"] = "completed", ["data"] = new JsonObject { ["buyOffers"] = new JsonArray() } };
        var noToolsCatalog = BuildActionCatalog(tradeState, noToolsMarket, questDetailsReceipt: toolsTaskReceipt);
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

    private static JsonArray BuildBanditSafePassageCatalog(JsonObject state, JsonObject context, JsonObject conversation, JsonObject? previousReceipt, JsonObject? safePassageBalanceReceipt, bool safePassageContinueUsed)
    {
        if (!IsObservedBanditEncounter(state, context)) return new JsonArray();

        var previousAction = ReadString(previousReceipt, "action");
        var previousStatus = ReadString(previousReceipt, "status");
        var options = conversation["options"] as JsonArray ?? new JsonArray();
        if (previousAction is "barterOffer" or "barterCancel") return new JsonArray();

        if (previousAction == "barterOptions")
        {
            if (previousStatus == "completed")
            {
                if (!TryGetSafePassageQuote(previousReceipt, out var observedQuote) || !IsQuoteForObservedParty(observedQuote, context))
                    return new JsonArray();
                if (safePassageBalanceReceipt is not null)
                    return QuoteMatchesBalancedDraft(previousReceipt, safePassageBalanceReceipt, context)
                        ? new JsonArray(
                            new JsonObject { ["action"] = "barterOffer", ["arguments"] = new JsonArray() },
                            new JsonObject { ["action"] = "barterCancel", ["arguments"] = new JsonArray() })
                        : new JsonArray();
                return new JsonArray(new JsonObject { ["action"] = "barterAutoBalance", ["arguments"] = new JsonArray() });
            }
            if (!options.OfType<JsonObject>().Any(option => IsTrue(option, "clickable")))
                return safePassageBalanceReceipt is null && !safePassageContinueUsed
                    ? new JsonArray(new JsonObject { ["action"] = "dialogueContinue", ["arguments"] = new JsonArray() })
                    : new JsonArray();
        }

        if (previousAction == "barterAutoBalance")
        {
            if (previousStatus != "completed") return new JsonArray();
            return TryGetSafePassageQuote(previousReceipt, out var balancedQuote) && IsQuoteForObservedParty(balancedQuote, context) && IsAffordableSafePassageQuote(balancedQuote)
                ? new JsonArray(new JsonObject { ["action"] = "barterOptions", ["arguments"] = new JsonArray() })
                : new JsonArray(new JsonObject { ["action"] = "barterCancel", ["arguments"] = new JsonArray() });
        }

        if (previousAction == "dialogueSelect" && previousStatus == "completed")
            return new JsonArray(new JsonObject { ["action"] = "barterOptions", ["arguments"] = new JsonArray() });

        if (previousAction == "dialogueContinue")
            return previousStatus == "completed" && safePassageBalanceReceipt is null
                ? new JsonArray(new JsonObject { ["action"] = "barterOptions", ["arguments"] = new JsonArray() })
                : new JsonArray();

        var safePassageOption = options.OfType<JsonObject>().FirstOrDefault(option =>
            ReadString(option, "id") == "bandit_start_defender_2" && IsTrue(option, "clickable"));
        if (safePassageOption is not null)
            return new JsonArray(new JsonObject
            {
                ["action"] = "dialogueSelect",
                ["arguments"] = new JsonArray("OptionId"),
                ["argumentValues"] = new JsonObject { ["OptionId"] = new JsonArray("bandit_start_defender_2") }
            });

        if (options.OfType<JsonObject>().Any(option => IsTrue(option, "clickable"))) return new JsonArray();
        return new JsonArray(new JsonObject { ["action"] = "barterOptions", ["arguments"] = new JsonArray() });
    }

    private static bool TryResolveBanditSafePassageAction(JsonObject state, JsonObject context, JsonObject? conversation,
        JsonObject? previousReceipt, JsonObject? safePassageBalanceReceipt, bool safePassageContinueUsed, string action, JsonObject arguments, out JsonObject? nativeArguments, out string rejection)
    {
        nativeArguments = null;
        var catalog = conversation is null ? new JsonArray() : BuildBanditSafePassageCatalog(state, context, conversation, previousReceipt, safePassageBalanceReceipt, safePassageContinueUsed);
        var offeredAction = catalog.OfType<JsonObject>().FirstOrDefault(item => ReadString(item, "action") == action);
        if (!IsObservedBanditEncounter(state, context) || offeredAction is null)
        {
            rejection = "Only the current Native Bandit encounter may use its explicitly listed non-fight Safe Passage action.";
            return false;
        }

        var actionArguments = offeredAction["arguments"] as JsonArray ?? new JsonArray();
        if (actionArguments.Count == 1 && action == "dialogueSelect")
        {
            var optionId = ReadString(arguments, "OptionId");
            var allowedIds = offeredAction["argumentValues"]?["OptionId"] as JsonArray;
            if (arguments.Count != 1 || string.IsNullOrWhiteSpace(optionId) ||
                allowedIds?.Any(item => item?.GetValue<string>() == optionId) != true)
            {
                rejection = "Only the observed Native non-fight Bandit compromise option may be selected.";
                return false;
            }
            nativeArguments = new JsonObject { ["optionId"] = optionId };
            rejection = string.Empty;
            return true;
        }

        if (actionArguments.Count == 0 && arguments.Count == 0 &&
            (action is "barterOptions" or "barterAutoBalance" or "barterOffer" or "barterCancel" or "dialogueContinue"))
        {
            if (action == "barterOffer")
            {
                if (!TryGetSafePassageQuote(previousReceipt, out var quote) || !QuoteMatchesBalancedDraft(previousReceipt, safePassageBalanceReceipt, context) || !IsAffordableSafePassageQuote(quote))
                {
                    rejection = "A Safe Passage offer requires the current quote to match the balanced Native session/proposal and leave positive Gold.";
                    return false;
                }
                nativeArguments = new JsonObject
                {
                    ["expectedSessionId"] = ReadString(quote, "sessionId"),
                    ["expectedProposalFingerprint"] = ReadString(quote, "proposalFingerprint")
                };
                rejection = string.Empty;
                return true;
            }
            nativeArguments = new JsonObject();
            rejection = string.Empty;
            return true;
        }

        rejection = "The selected Safe Passage action does not match the current Native context.";
        return false;
    }

    private static bool IsObservedBanditEncounter(JsonObject state, JsonObject context)
    {
        if (!HasActiveToolsQuest(state) || ReadString(context, "gameState") != "MapState" || ReadString(context, "menuId") != "encounter_meeting" ||
            !ReadBoolean(context, "encounterActive")) return false;
        var encounteredPartyId = ReadString(context, "encounteredPartyId");
        if (string.IsNullOrWhiteSpace(encounteredPartyId)) return false;
        return (state["nearbyParties"] as JsonArray)?.OfType<JsonObject>().Any(party =>
            ReadString(party, "id") == encounteredPartyId && ReadString(party, "type") == "bandit" && IsTrue(party, "hostile")) == true;
    }

    private static bool TryGetSafePassageQuote(JsonObject? receipt, out JsonObject quote)
    {
        quote = receipt?["data"] as JsonObject ?? new JsonObject();
        if (ReadString(receipt, "action") == "barterAutoBalance") quote = quote["updatedOptions"] as JsonObject ?? new JsonObject();
        if (ReadString(receipt, "status") != "completed" ||
            ReadString(quote, "context") != "contextual:safe_passage_barterable" ||
            ReadString(quote, "contextInitializer") != "InitializeSafePassageBarterContext" ||
            string.IsNullOrWhiteSpace(ReadString(quote, "sessionId")) ||
            string.IsNullOrWhiteSpace(ReadString(quote, "proposalFingerprint"))) return false;
        var candidates = quote["candidates"] as JsonArray;
        return candidates?.OfType<JsonObject>().Any(candidate =>
                ReadString(candidate, "nativeType") == "safe_passage_barterable" && ReadString(candidate, "list") == "leftOffer" && IsTrue(candidate, "isOffered")) == true &&
            candidates.OfType<JsonObject>().All(candidate => ReadString(candidate, "nativeType") is "safe_passage_barterable" or "gold_barterable") &&
            candidates.OfType<JsonObject>().Any(candidate => ReadString(candidate, "nativeType") == "gold_barterable" && ReadString(candidate, "list") == "rightGold");
    }

    private static bool IsAffordableSafePassageQuote(JsonObject quote)
    {
        if (IsTrue(quote, "isOfferDisabled") || !ReadInteger(quote, "playerGold").HasValue) return false;
        var candidates = quote["candidates"] as JsonArray;
        if (candidates is null) return false;
        var offered = candidates.OfType<JsonObject>().Where(candidate => IsTrue(candidate, "isOffered")).ToArray();
        if (offered.Any(candidate => ReadString(candidate, "nativeType") is not ("safe_passage_barterable" or "gold_barterable"))) return false;
        var gold = offered.Where(candidate => ReadString(candidate, "nativeType") == "gold_barterable" && ReadString(candidate, "list") == "rightGold").ToArray();
        if (offered.Count(candidate => ReadString(candidate, "nativeType") == "gold_barterable") != gold.Length || gold.Length > 1) return false;
        var cost = gold.Length == 0 ? 0 : ReadInteger(gold[0], "currentAmount") ?? int.MaxValue;
        return cost >= 0 && ReadInteger(quote, "playerGold")!.Value - cost > 0;
    }

    private static bool IsQuoteForObservedParty(JsonObject quote, JsonObject context)
    {
        var partyId = ReadString(context, "encounteredPartyId");
        return !string.IsNullOrWhiteSpace(partyId) &&
            (quote["candidates"] as JsonArray)?.OfType<JsonObject>().Any(candidate =>
                ReadString(candidate, "nativeType") == "safe_passage_barterable" &&
                ReadString(candidate, "originalPartyId") == partyId) == true;
    }

    private static bool QuoteMatchesBalancedDraft(JsonObject? currentOptionsReceipt, JsonObject? balanceReceipt, JsonObject context)
    {
        if (!TryGetSafePassageQuote(currentOptionsReceipt, out var currentQuote) ||
            !TryGetSafePassageQuote(balanceReceipt, out var balancedQuote) ||
            !IsQuoteForObservedParty(currentQuote, context) || !IsQuoteForObservedParty(balancedQuote, context) ||
            !IsAffordableSafePassageQuote(currentQuote)) return false;
        return string.Equals(ReadString(currentQuote, "sessionId"), ReadString(balancedQuote, "sessionId"), StringComparison.Ordinal) &&
            string.Equals(ReadString(currentQuote, "proposalFingerprint"), ReadString(balancedQuote, "proposalFingerprint"), StringComparison.Ordinal);
    }

    private static JsonArray BuildInventoryActionCatalog(JsonObject state, JsonObject? previousReceipt, JsonObject? questDetailsReceipt)
    {
        var inventory = state["inventoryScreen"] as JsonObject;
        var mode = ReadString(inventory, "mode");
        var previousAction = ReadString(previousReceipt, "action");
        if (mode == "Trade")
        {
            if (previousAction == "tradeOptions" && ReadString(previousReceipt, "status") == "completed")
            {
                var remainingTools = GetToolsTaskRemainingCount(questDetailsReceipt) ?? 0;
                var playerGold = ReadInteger(previousReceipt?["data"] as JsonObject, "playerGold") ?? 0;
                var toolOffers = (previousReceipt?["data"]?["buyOffers"] as JsonArray)?.OfType<JsonObject>()
                    .Where(offer => IsCurrentToolsOffer(offer) && IsTrue(offer, "isTransferable") &&
                        (ReadInteger(offer, "stock") ?? 0) >= remainingTools &&
                        (ReadInteger(offer, "inventoryLogicUnitPrice") ?? ReadInteger(offer, "nativeItemCost") ?? int.MaxValue) > 0 &&
                        (long)(ReadInteger(offer, "inventoryLogicUnitPrice") ?? ReadInteger(offer, "nativeItemCost") ?? int.MaxValue) * remainingTools <= playerGold)
                    .Select(offer => ReadString(offer, "viewModelItemId"))
                    .Where(id => !string.IsNullOrWhiteSpace(id)).Cast<string>().Distinct(StringComparer.Ordinal).ToArray() ?? Array.Empty<string>();
                if (remainingTools <= 0 || toolOffers.Length == 0)
                    return new JsonArray(new JsonObject { ["action"] = "tradeCancel", ["arguments"] = new JsonArray() });
                var amountValues = new JsonArray();
                amountValues.Add(remainingTools);
                return new JsonArray(new JsonObject
                {
                    ["action"] = "trade",
                    ["arguments"] = new JsonArray("Direction", "ItemViewModelId", "InventorySide", "Amount"),
                    ["argumentValues"] = new JsonObject
                    {
                        ["Direction"] = new JsonArray("buy"),
                        ["ItemViewModelId"] = new JsonArray(toolOffers.Select(id => (JsonNode?)JsonValue.Create(id)).ToArray()),
                        ["InventorySide"] = new JsonArray("OtherInventory"),
                        ["Amount"] = amountValues
                    }
                });
            }
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

    private static bool TryResolveInventoryAction(JsonObject state, JsonObject? previousReceipt, JsonObject? questDetailsReceipt, string action, JsonObject arguments, out JsonObject? nativeArguments, out string rejection)
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
                var remainingTools = GetToolsTaskRemainingCount(questDetailsReceipt) ?? 0;
                var playerGold = ReadInteger(previousReceipt?["data"] as JsonObject, "playerGold") ?? 0;
                var offer = (previousReceipt?["data"]?["buyOffers"] as JsonArray)?.OfType<JsonObject>()
                    .FirstOrDefault(candidate => ReadString(candidate, "viewModelItemId") == itemViewModelId);
                var unitPrice = offer is null ? null : ReadInteger(offer, "inventoryLogicUnitPrice") ?? ReadInteger(offer, "nativeItemCost");
                var stock = offer is null ? null : ReadInteger(offer, "stock");
                if (direction == "buy" && inventorySide == "OtherInventory" && remainingTools > 0 && amount == remainingTools && offer is not null &&
                    IsCurrentToolsOffer(offer) && IsTrue(offer, "isTransferable") && amount.HasValue && stock.HasValue && amount.Value <= stock.Value &&
                    unitPrice is > 0 && (long)unitPrice.Value * amount.Value <= playerGold)
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

    private static JsonObject SafePassageOptions(string sessionId, string fingerprint, int playerGold, int goldCost, bool isOfferDisabled)
    {
        return new JsonObject
        {
            ["sessionId"] = sessionId, ["proposalFingerprint"] = fingerprint,
            ["context"] = "contextual:safe_passage_barterable", ["contextInitializer"] = "InitializeSafePassageBarterContext",
            ["isOfferDisabled"] = isOfferDisabled, ["playerGold"] = playerGold,
            ["candidates"] = new JsonArray(
                new JsonObject { ["nativeType"] = "safe_passage_barterable", ["list"] = "leftOffer", ["originalPartyId"] = "looters_1", ["isOffered"] = true },
                new JsonObject { ["nativeType"] = "gold_barterable", ["list"] = "rightGold", ["currentAmount"] = goldCost, ["isOffered"] = goldCost > 1 })
        };
    }

    private static JsonObject SafePassageReceipt(string action, JsonObject options, bool wrapAutoBalance = false) => new()
    {
        ["action"] = action,
        ["status"] = "completed",
        ["data"] = wrapAutoBalance ? new JsonObject { ["updatedOptions"] = options.DeepClone() } : options.DeepClone()
    };

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

    private static IReadOnlyList<string> GetAllowedToolsQuestGiverIds(JsonObject state, JsonObject? previousReceipt, JsonObject? questDetailsReceipt)
    {
        var ids = new HashSet<string>(GetVisibleToolsQuestGiverIds(state), StringComparer.Ordinal);
        if (HasActiveToolsQuest(state) && ReadString(questDetailsReceipt, "action") == "questDetails" && ReadString(questDetailsReceipt, "status") == "completed")
        {
            var giverId = ReadString(questDetailsReceipt?["data"]?["questGiver"] as JsonObject, "id");
            if (!string.IsNullOrWhiteSpace(giverId) &&
                (state["settlementOverlayCharacters"] as JsonArray)?.OfType<JsonObject>().Any(character => ReadString(character, "heroId") == giverId) == true)
                ids.Add(giverId);
        }
        return ids.ToArray();
    }

    internal static string? GetCurrentSettlementType(JsonObject state)
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

    internal static bool HasCurrentToolsBuyOffer(JsonObject? receipt) =>
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

    private static IReadOnlyList<JsonObject> GetAllowedDialogueOptions(JsonObject state, JsonObject conversation, JsonObject? previousReceipt, JsonObject? questDetailsReceipt)
    {
        var options = (conversation["options"] as JsonArray)?.OfType<JsonObject>()
            .Where(option => IsTrue(option, "clickable"))
            .Where(option => !IsOutOfScopeIssueOutcomeOption(option))
            .ToArray() ?? Array.Empty<JsonObject>();
        if (!HasActiveToolsQuest(state) || IsToolsTaskSatisfied(questDetailsReceipt ?? previousReceipt)) return options;
        return options.Where(IsConversationLeaveOption).ToArray();
    }

    internal static bool HasOnlyOutOfScopeIssueOutcomeOptions(JsonObject? conversation)
    {
        var clickableOptions = (conversation?["options"] as JsonArray)?.OfType<JsonObject>()
            .Where(option => IsTrue(option, "clickable")).ToArray() ?? Array.Empty<JsonObject>();
        return clickableOptions.Length > 0 && clickableOptions.All(IsOutOfScopeIssueOutcomeOption);
    }

    private static bool IsOutOfScopeIssueOutcomeOption(JsonObject option) =>
        ReadString(option, "id") is "issue_offer_player_accept_alternative" or "issue_offer_player_accept_lord";

    private static bool HasClickableConversationOptions(JsonObject conversation) =>
        (conversation["options"] as JsonArray)?.OfType<JsonObject>().Any(option => IsTrue(option, "clickable")) == true;

    private static bool IsConversationLeaveOption(JsonObject option) =>
        ReadString(option, "id")?.StartsWith("player_is_leaving_", StringComparison.Ordinal) == true;

    internal static int? GetToolsTaskRemainingCount(JsonObject? receipt)
    {
        if (ReadString(receipt, "action") != "questDetails" || ReadString(receipt, "status") != "completed") return null;
        var task = (receipt?["data"]?["journalStages"] as JsonArray)?.OfType<JsonObject>()
            .FirstOrDefault(stage => ReadBoolean(stage, "hasTask"));
        var current = ReadInteger(task, "currentProgress");
        var target = ReadInteger(task, "targetProgress");
        var taskName = ReadString(task, "taskName") ?? string.Empty;
        if (!current.HasValue || !target.HasValue || target.Value <= 0 ||
            !(taskName.Contains("tool", StringComparison.OrdinalIgnoreCase) || taskName.Contains("工具", StringComparison.Ordinal)))
            return null;
        return Math.Max(0, target.Value - current.Value);
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
