using System.Diagnostics;
using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal static class AgentHostEstablishClanCompanionLoop
{
    private const double MinimumCompanionNavigationProgressDistance = 0.1d;
    private const int MaxCompanionNavigationNoProgressAttempts = 2;
    private const int MaxTavernMissionStartupWaits = 20;
    private const int MaxTavernEntryTransitionWaits = 10;
    private const string QuestId = "rebuild_player_clan_storymode_quest";
    private const int MaxDecisions = AgentHostCampaignLoop.MaxCumulativeDecisions;
    // This is a per-decision choice window, not a world-entity cap. After a
    // selected Town is visited, the Native target query is refreshed against
    // visitedTowns and exposes the next nearest unvisited candidates.
    private const int SafeTownDecisionWindowSize = 12;
    private static readonly TimeSpan MaxElapsed = TimeSpan.FromHours(24);
    private static readonly HashSet<string> HiringDialogueOptions = new(StringComparer.Ordinal)
    {
        "wanderer_meet_player_response2", "main_option_faction_hire",
        "player_companion_hire_response_1", "player_companion_hire_response_2", "player_is_leaving_neutral_or_friendly"
    };

    internal static IReadOnlyList<object> RunContractSelfTests()
    {
        if (MaxElapsed != TimeSpan.FromHours(24))
            throw new AgentHostException("establish-clan-companion-runtime-budget-contract-failed", "The Companion subgoal must share the autonomous EYC 24-hour elapsed-time envelope rather than terminating before the parent Campaign budget.");
        var stalledNavigationFirstAttempt = EvaluateNavigationNoProgress(1.39d, 1.65d, 0, false);
        var stalledNavigationSecondAttempt = EvaluateNavigationNoProgress(1.39d, 1.65d, stalledNavigationFirstAttempt.Attempts, false);
        var nativeNavigatorApproach = EvaluateNavigationNoProgress(10.201d, 1.365d, 0, false);
        var nativeNavigatorStallFirst = EvaluateNavigationNoProgress(1.365d, 1.364d, nativeNavigatorApproach.Attempts, false);
        var nativeNavigatorStallSecond = EvaluateNavigationNoProgress(1.364d, 1.364d, nativeNavigatorStallFirst.Attempts, false);
        var measuredApproach = EvaluateNavigationNoProgress(10d, 9.5d, 1, false);
        var nowInteractable = EvaluateNavigationNoProgress(1.39d, 1.39d, 1, true);
        if (stalledNavigationFirstAttempt.ExcludeTarget || stalledNavigationSecondAttempt.Attempts != 2 || !stalledNavigationSecondAttempt.ExcludeTarget ||
            nativeNavigatorApproach.Attempts != 0 || nativeNavigatorApproach.ExcludeTarget || nativeNavigatorStallFirst.Attempts != 1 || nativeNavigatorStallFirst.ExcludeTarget ||
            nativeNavigatorStallSecond.Attempts != 2 || !nativeNavigatorStallSecond.ExcludeTarget ||
            measuredApproach.Attempts != 0 || measuredApproach.ExcludeTarget || nowInteractable.Attempts != 0 || nowInteractable.ExcludeTarget)
            throw new AgentHostException("companion-navigation-stall-policy-self-test-failed", "Only repeated completed Native navigation with less than 0.1 distance improvement and no interactable observation may temporarily exclude a target.");
        var candidates = FilterWandererCandidates(new JsonArray
        {
            new JsonObject { ["agentIndex"] = 4, ["heroId"] = "wanderer-a", ["occupation"] = "Wanderer", ["isNotable"] = false, ["isEnemy"] = false, ["nativeConversationActionAvailable"] = true, ["distance"] = 6.0 },
            new JsonObject { ["agentIndex"] = 5, ["heroId"] = "notable-a", ["occupation"] = "Merchant", ["isNotable"] = true, ["isEnemy"] = false, ["distance"] = 2.0 },
            new JsonObject { ["agentIndex"] = 6, ["heroId"] = "hostile-wanderer", ["occupation"] = "Wanderer", ["isNotable"] = false, ["isEnemy"] = true, ["distance"] = 1.0 },
            new JsonObject { ["agentIndex"] = 7, ["heroId"] = null, ["occupation"] = "Wanderer", ["isNotable"] = false, ["isEnemy"] = false, ["distance"] = 3.0 },
            new JsonObject { ["agentIndex"] = 8, ["heroId"] = "wanderer-no-dialogue", ["occupation"] = "Wanderer", ["isNotable"] = false, ["isEnemy"] = false, ["nativeConversationActionAvailable"] = false, ["distance"] = 2.5 }
        }, new HashSet<string>(StringComparer.Ordinal));
        if (candidates.Count != 2 || !candidates.Any(candidate => ReadString(candidate as JsonObject, "heroId") == "wanderer-a") ||
            !candidates.Any(candidate => ReadString(candidate as JsonObject, "heroId") == "wanderer-no-dialogue"))
            throw new AgentHostException("establish-clan-companion-candidate-filter-failed", "A current, unowned, friendly Wanderer remains a navigation candidate even when the Native conversation action is not available from the current distance/pose.");

        var nativeTrainingFieldMenu = new JsonObject
        {
            ["context"] = new JsonObject
            {
                ["gameState"] = "MapState", ["menuId"] = "training_field_menu", ["encounterActive"] = true,
                ["encounteredPartyId"] = "tutorial_training_field", ["battleSimulation"] = null,
                ["captivity"] = new JsonObject { ["isCaptive"] = false }
            },
            ["location"] = new JsonObject { ["currentSettlementId"] = "tutorial_training_field" },
            ["availableMenuOptions"] = new JsonArray
            {
                new JsonObject { ["id"] = "training_field_enter", ["available"] = true, ["enabled"] = true, ["isLeave"] = false },
                new JsonObject { ["id"] = "training_field_leave", ["available"] = true, ["enabled"] = true, ["isLeave"] = true }
            }
        };
        var trainingFieldActions = BuildActionCatalog(nativeTrainingFieldMenu, new JsonArray(), new JsonObject(), null, null, null, null, false,
            new HashSet<string>(StringComparer.Ordinal), new HashSet<string>(StringComparer.Ordinal));
        var trainingFieldLeave = trainingFieldActions.OfType<JsonObject>().SingleOrDefault(action => ReadString(action, "action") == "menuSelect");
        if (((trainingFieldLeave?["argumentValues"]?["OptionId"] as JsonArray)?[0]?.GetValue<string>()) != "training_field_leave" ||
            AgentHostCampaignStateFacts.IsActiveEncounter(nativeTrainingFieldMenu))
            throw new AgentHostException("establish-clan-companion-training-field-menu-misclassified", "The original post-tutorial training-field menu is a Native location menu with a Leave option, not a hostile encounter that should abort the Companion objective.");
        var hostileEncounter = new JsonObject
        {
            ["context"] = new JsonObject { ["gameState"] = "MapState", ["encounterActive"] = true, ["encounteredPartyId"] = "looter-party", ["captivity"] = new JsonObject { ["isCaptive"] = false } },
            ["location"] = new JsonObject { ["currentSettlementId"] = null }
        };
        if (!AgentHostCampaignStateFacts.IsActiveEncounter(hostileEncounter) || BuildActionCatalog(hostileEncounter, new JsonArray(), new JsonObject(), null, null, null, null, false,
                new HashSet<string>(StringComparer.Ordinal), new HashSet<string>(StringComparer.Ordinal)).Count != 0)
            throw new AgentHostException("establish-clan-companion-hostile-encounter-not-blocked", "A true map-party encounter must continue to block Tavern hiring actions.");

        var journey = new JsonObject
        {
            ["context"] = new JsonObject
            {
                ["gameState"] = "MissionState",
                ["conversation"] = new JsonObject
                {
                    ["heroId"] = "wanderer-a",
                    ["options"] = new JsonArray(
                        new JsonObject { ["id"] = "main_option_faction_hire", ["clickable"] = true },
                        new JsonObject { ["id"] = "unrelated_option", ["clickable"] = true })
                }
            }
        };
        var dialogue = BuildActionCatalog(journey, new JsonArray(), new JsonObject(), null, null, null, null, false,
            new HashSet<string>(StringComparer.Ordinal), new HashSet<string>(StringComparer.Ordinal));
        var listed = dialogue.OfType<JsonObject>().FirstOrDefault(action => ReadString(action, "action") == "dialogueSelect");
        var optionIds = listed?["argumentValues"]?["OptionId"] as JsonArray;
        if (dialogue.Count != 1 || ReadString(dialogue[0] as JsonObject, "action") != "dialogueSelect" || optionIds is null || optionIds.Count != 1 || optionIds[0]?.GetValue<string>() != "main_option_faction_hire")
            throw new AgentHostException("establish-clan-companion-native-conversation-shape-failed", "The original Native context.conversation must take precedence over Tavern scene queries and expose only its current source-verified hiring option.");

        var declinedConversation = new JsonObject
        {
            ["context"] = new JsonObject
            {
                ["gameState"] = "MissionState",
                ["conversation"] = new JsonObject
                {
                    ["heroId"] = "wanderer-a",
                    ["options"] = new JsonArray(
                        new JsonObject { ["id"] = "main_option_faction_hire", ["clickable"] = true },
                        new JsonObject { ["id"] = "player_is_leaving_neutral_or_friendly", ["clickable"] = true })
                }
            }
        };
        var declinedCatalog = BuildActionCatalog(declinedConversation, new JsonArray(), new JsonObject(), null, null, null, null, false,
            new HashSet<string>(StringComparer.Ordinal), new HashSet<string>(["wanderer-a"], StringComparer.Ordinal));
        var declinedOptionIds = declinedCatalog.OfType<JsonObject>().SingleOrDefault(action => ReadString(action, "action") == "dialogueSelect")?["argumentValues"]?["OptionId"] as JsonArray;
        if (declinedCatalog.Count != 1 || declinedOptionIds?.Count != 1 || declinedOptionIds[0]?.GetValue<string>() != "player_is_leaving_neutral_or_friendly")
            throw new AgentHostException("establish-clan-companion-declined-wanderer-exit-not-gated", "After declining a Wanderer's quote, the current Native follow-up must allow its leave response and must not reopen the same hire offer.");

        var mapTravelConversation = new JsonObject
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
                        new JsonObject { ["id"] = "map-current", ["text"] = "A visible answer.", ["clickable"] = true },
                        new JsonObject { ["id"] = "map-hidden", ["text"] = "Unavailable answer.", ["clickable"] = false })
                }
            },
            ["location"] = new JsonObject { ["currentSettlementId"] = null, ["targetSettlementId"] = "town-a" },
            ["party"] = new JsonObject { ["isMoving"] = true }
        };
        var mapTravelCatalog = BuildActionCatalog(mapTravelConversation, new JsonArray(), new JsonObject(), null, null, null, "town-a", false,
            new HashSet<string>(StringComparer.Ordinal), new HashSet<string>(StringComparer.Ordinal));
        var mapTravelOptionIds = mapTravelCatalog.OfType<JsonObject>().SingleOrDefault(action => ReadString(action, "action") == "dialogueSelect")?[
            "argumentValues"]?["OptionId"] as JsonArray;
        if (mapTravelCatalog.Count != 1 || mapTravelOptionIds?.Count != 1 || mapTravelOptionIds[0]?.GetValue<string>() != "map-current" ||
            !TryResolveAction(new JsonObject { ["action"] = "dialogueSelect", ["arguments"] = new JsonObject { ["OptionId"] = "map-current" } },
                mapTravelCatalog, mapTravelConversation, null, null, "town-a", false, out var mapDialogueAction, out var mapDialogueArguments, out _, out var mapDialogueHero, out _) ||
            mapDialogueAction != "dialogueSelect" || mapDialogueArguments["optionId"]?.GetValue<string>() != "map-current" || mapDialogueHero is not null ||
            TryResolveAction(new JsonObject { ["action"] = "dialogueSelect", ["arguments"] = new JsonObject { ["OptionId"] = "map-hidden" } },
                mapTravelCatalog, mapTravelConversation, null, null, "town-a", false, out _, out _, out _, out _, out _))
            throw new AgentHostException("establish-clan-companion-map-conversation-options-not-current", "A MapState conversation during Companion travel must expose only current clickable Native options and must not be treated as a Wanderer hire conversation.");

        var mapTravelNoChoice = (JsonObject)mapTravelConversation.DeepClone();
        ((mapTravelNoChoice["context"]?["conversation"] as JsonObject)!["options"] as JsonArray)!.Clear();
        var mapContinueCatalog = BuildActionCatalog(mapTravelNoChoice, new JsonArray(), new JsonObject(), null, null, null, "town-a", false,
            new HashSet<string>(StringComparer.Ordinal), new HashSet<string>(StringComparer.Ordinal));
        if (mapContinueCatalog.Count != 1 || ReadString(mapContinueCatalog[0] as JsonObject, "action") != "dialogueContinue" ||
            !TryResolveAction(new JsonObject { ["action"] = "dialogueContinue", ["arguments"] = new JsonObject() },
                mapContinueCatalog, mapTravelNoChoice, null, null, "town-a", false, out var mapContinueAction, out _, out _, out _, out _) ||
            mapContinueAction != "dialogueContinue")
            throw new AgentHostException("establish-clan-companion-map-conversation-continue-not-current", "A no-choice MapState conversation must expose only the original Native dialogueContinue before a Companion route resumes.");

        var missionCandidateState = new JsonObject
        {
            ["context"] = new JsonObject { ["gameState"] = "MissionState", ["encounterActive"] = false },
            ["mission"] = new JsonObject { ["nearbySceneAgents"] = new JsonArray() }
        };
        var missionCandidateReceipt = new JsonObject
        {
            ["data"] = new JsonObject
            {
                ["agents"] = new JsonArray(new JsonObject
                {
                    ["agentIndex"] = 4, ["heroId"] = "wanderer-a", ["occupation"] = "Wanderer",
                    ["isNotable"] = false, ["isEnemy"] = false, ["nativeConversationActionAvailable"] = false, ["distance"] = 6.0
                })
            }
        };
        var missionCandidateCatalog = BuildActionCatalog(missionCandidateState, new JsonArray(), new JsonObject(), null,
            missionCandidateReceipt, null, null, false, new HashSet<string>(StringComparer.Ordinal), new HashSet<string>(StringComparer.Ordinal));
        if (!missionCandidateCatalog.OfType<JsonObject>().Any(action => ReadString(action, "action") == "missionNavigateToAgent") ||
            !missionCandidateCatalog.OfType<JsonObject>().Any(action => ReadString(action, "action") == "missionLeave"))
            throw new AgentHostException("establish-clan-companion-mission-exit-not-listed", "A nearby Wanderer without a current conversation action must remain navigable, while the Native exit remains available.");

        var wrappedIndexDecision = new JsonObject
        {
            ["action"] = "missionNavigateToAgent",
            ["arguments"] = new JsonObject { ["AgentIndex"] = "[4]", ["DurationSeconds"] = "**8**" }
        };
        if (!TryResolveAction(wrappedIndexDecision, missionCandidateCatalog, missionCandidateState, missionCandidateReceipt,
                selectedHeroId: null, moveTargetId: null, pending: false, out var normalizedNavigationAction, out var normalizedNavigationArguments,
                out _, out var normalizedTargetHeroId, out _) ||
            normalizedNavigationAction != "missionNavigateToAgent" || normalizedTargetHeroId != "wanderer-a" ||
            ReadInt(normalizedNavigationArguments, "agentIndex", -1) != 4 || ReadInt(normalizedNavigationArguments, "durationSeconds", -1) != 8)
            throw new AgentHostException("establish-clan-companion-current-catalog-integer-normalization-failed", "Bracket/Markdown formatting may be removed from numeric Native candidate arguments only when the canonical integer exactly matches the fresh current catalog.");
        var outOfCatalogWrappedIndex = wrappedIndexDecision.DeepClone().AsObject();
        outOfCatalogWrappedIndex["arguments"]!["AgentIndex"] = "[5]";
        if (TryResolveAction(outOfCatalogWrappedIndex, missionCandidateCatalog, missionCandidateState, missionCandidateReceipt,
                selectedHeroId: null, moveTargetId: null, pending: false, out _, out _, out _, out _, out _))
            throw new AgentHostException("establish-clan-companion-out-of-catalog-formatted-index-accepted", "Removing output formatting must never bypass the current Native AgentIndex list.");
        var unlistedDurationDecision = new JsonObject
        {
            ["action"] = "missionNavigateToAgent",
            ["arguments"] = new JsonObject { ["AgentIndex"] = 4, ["DurationSeconds"] = 12 }
        };
        if (TryResolveAction(unlistedDurationDecision, missionCandidateCatalog, missionCandidateState, missionCandidateReceipt,
                selectedHeroId: null, moveTargetId: null, pending: false, out _, out _, out _, out _, out var durationRejection) ||
            !durationRejection.Contains("AgentIndex [4]", StringComparison.Ordinal) ||
            !durationRejection.Contains("DurationSeconds [8, 20]", StringComparison.Ordinal) ||
            !durationRejection.Contains("no Native action was sent", StringComparison.Ordinal))
            throw new AgentHostException("establish-clan-companion-unlisted-navigation-duration-feedback-failed", "An unlisted navigation lease must be rejected before Native execution and identify only the current exact agent/duration values.");
        if (BuildControlCatalog(false, false, false, false, false).Any(control => control?.GetValue<string>() == "stop") ||
            !BuildControlCatalog(true, false, false, false, false).Any(control => control?.GetValue<string>() == "stop") ||
            BuildControlCatalog(true, true, false, false, false).Any(control => control?.GetValue<string>() == "observeAgain") ||
            !BuildControlCatalog(true, true, false, false, true).Any(control => control?.GetValue<string>() == "observeAgain"))
            throw new AgentHostException("establish-clan-companion-stop-scope-invalid", "A subgoal may stop for parent replan only from a free Native Map, never from inside a Mission.");

        var safeMap = FilterSafeTowns(new JsonArray
        {
            new JsonObject { ["id"] = "town-a", ["type"] = "town", ["distance"] = 4.0, ["hostile"] = false, ["underSiege"] = false },
            new JsonObject { ["id"] = "village-a", ["type"] = "village", ["distance"] = 1.0, ["hostile"] = false, ["underSiege"] = false },
            new JsonObject { ["id"] = "town-visited", ["type"] = "town", ["distance"] = 2.0, ["hostile"] = false, ["underSiege"] = false },
            new JsonObject { ["id"] = "town-sieged", ["type"] = "town", ["distance"] = 3.0, ["hostile"] = false, ["underSiege"] = true }
        }, null, new HashSet<string>(["town-visited"], StringComparer.Ordinal));
        if (safeMap.Count != 1 || ReadString(safeMap[0] as JsonObject, "id") != "town-a")
            throw new AgentHostException("establish-clan-companion-safe-town-filter-failed", "The Companion executor must visit only newly observed safe Town targets.");

        var manySafeTowns = new JsonArray(Enumerable.Range(0, 21).Select(index => (JsonNode?)new JsonObject
        {
            ["id"] = "town-" + index.ToString("D2", CultureInfo.InvariantCulture),
            ["name"] = "Town " + index.ToString("D2", CultureInfo.InvariantCulture),
            ["type"] = "town",
            ["distance"] = index + 1,
            ["hostile"] = false,
            ["underSiege"] = false,
            ["isInspected"] = false
        }).ToArray());
        var firstTownPage = FilterSafeTowns(manySafeTowns, null, new HashSet<string>(StringComparer.Ordinal));
        var firstTownWindow = BuildSafeTownDecisionWindow(firstTownPage);
        var mapTargetCatalog = BuildActionCatalog(new JsonObject { ["context"] = new JsonObject { ["gameState"] = "MapState", ["menuId"] = "" } },
            new JsonArray(), new JsonObject(), firstTownPage, null, null, null, false,
            new HashSet<string>(StringComparer.Ordinal), new HashSet<string>(StringComparer.Ordinal));
        var moveChoices = mapTargetCatalog.OfType<JsonObject>().FirstOrDefault(action => ReadString(action, "action") == "move")?[
            "argumentValues"]?["SettlementId"] as JsonArray;
        var visitedFirstWindow = new HashSet<string>(firstTownWindow.OfType<JsonObject>().Select(town => ReadString(town, "id")!), StringComparer.Ordinal);
        var nextTownWindow = BuildSafeTownDecisionWindow(FilterSafeTowns(manySafeTowns, null, visitedFirstWindow));
        if (firstTownPage.Count != 21 || firstTownWindow.Count != SafeTownDecisionWindowSize ||
            ReadString(firstTownWindow[0] as JsonObject, "id") != "town-00" || moveChoices?.Count != SafeTownDecisionWindowSize ||
            nextTownWindow.Count != 9 || ReadString(nextTownWindow[0] as JsonObject, "id") != "town-12")
            throw new AgentHostException("establish-clan-companion-town-window-paging-failed", "Map target context must bound each model choice window while retaining all world targets across the visited-Town refresh cycle.");

        var tavernStartupState = new JsonObject
        {
            ["context"] = new JsonObject { ["gameState"] = "MissionState", ["menuId"] = null, ["encounterActive"] = true, ["encounteredPartyId"] = "town-a" },
            ["location"] = new JsonObject { ["currentSettlementId"] = "town-a" },
            ["mission"] = new JsonObject { ["active"] = true, ["sceneName"] = "empire_house_c_tavern_a", ["mode"] = "StartUp", ["nativeMissionCurrentState"] = "Initializing", ["nativeConversationReady"] = false }
        };
        var tavernStartupCatalog = BuildActionCatalog(tavernStartupState, new JsonArray(), new JsonObject(), null, null, null, null, false,
            new HashSet<string>(StringComparer.Ordinal), new HashSet<string>(StringComparer.Ordinal));
        if (!IsNativeTavernMissionState(tavernStartupState) || !AgentHostCampaignStateFacts.IsActiveEncounter(tavernStartupState) ||
            tavernStartupCatalog.Count != 1 || ReadString(tavernStartupCatalog[0] as JsonObject, "action") != "missionSceneAgents")
            throw new AgentHostException("establish-clan-companion-tavern-mission-not-distinguished-from-encounter", "A MissionState at its own friendly settlement in a Native tavern scene must be distinguishable from a hostile/party encounter while preserving the current scene-agent query route.");

        var nonActionableTargetState = new JsonObject
        {
            ["context"] = new JsonObject { ["gameState"] = "MissionState" },
            ["mission"] = new JsonObject
            {
                ["nearbySceneAgents"] = new JsonArray(new JsonObject { ["agentIndex"] = 4, ["heroId"] = "wanderer-a", ["occupation"] = "Wanderer", ["isNotable"] = false, ["isEnemy"] = false, ["isInteractable"] = true, ["distance"] = 1.2 })
            }
        };
        var options = BuildActionCatalog(nonActionableTargetState, new JsonArray(), new JsonObject(), null,
            new JsonObject { ["data"] = new JsonObject { ["agents"] = new JsonArray(new JsonObject { ["agentIndex"] = 4, ["heroId"] = "wanderer-a", ["occupation"] = "Wanderer", ["isNotable"] = false, ["isEnemy"] = false, ["nativeConversationActionAvailable"] = false, ["distance"] = 1.2 }) } },
            "wanderer-a", null, false, new HashSet<string>(StringComparer.Ordinal), new HashSet<string>(StringComparer.Ordinal));
        if (!options.OfType<JsonObject>().Any(action => ReadString(action, "action") == "missionNavigateToAgent") ||
            options.OfType<JsonObject>().Any(action => ReadString(action, "action") == "missionInteract"))
            throw new AgentHostException("establish-clan-companion-native-interaction-route-failed", "The Host must not invoke Agent.OnUse until the current Native MissionConversationLogic action is available, even if a nearby-state heuristic says interactable.");
        var actionableTargetCatalog = new JsonObject { ["data"] = new JsonObject { ["agents"] = new JsonArray(new JsonObject
        {
            ["agentIndex"] = 4, ["heroId"] = "wanderer-a", ["occupation"] = "Wanderer", ["isNotable"] = false, ["isEnemy"] = false,
            ["nativeConversationActionAvailable"] = true, ["distance"] = 1.2
        }) } };
        var actionableOptions = BuildActionCatalog(nonActionableTargetState, new JsonArray(), new JsonObject(), null, actionableTargetCatalog,
            "wanderer-a", null, false, new HashSet<string>(StringComparer.Ordinal), new HashSet<string>(StringComparer.Ordinal));
        if (!actionableOptions.OfType<JsonObject>().Any(action => ReadString(action, "action") == "missionInteract") ||
            !actionableOptions.OfType<JsonObject>().Any(action => ReadString(action, "action") == "missionLeave"))
            throw new AgentHostException("establish-clan-companion-native-interaction-route-failed", "Once Native MissionConversationLogic reports a current action and the local Agent is interactable, use Native Agent interaction while retaining the Native exit.");

        var affordabilitySnapshot = new JsonObject
        {
            ["gold"] = new JsonObject { ["current"] = 64, ["target"] = 2000, ["met"] = false },
            ["partySize"] = new JsonObject { ["current"] = 19, ["target"] = 25, ["met"] = false },
            ["renown"] = new JsonObject { ["current"] = 20, ["target"] = 50, ["met"] = false },
            ["companions"] = new JsonObject { ["current"] = 0, ["target"] = 1, ["met"] = false }
        };
        var affordabilityCheckpoint = new JsonObject { ["schemaVersion"] = 2, ["campaignInstanceId"] = "campaign-affordability-fixture" };
        var affordabilityMemory = new Dictionary<string, int>(StringComparer.Ordinal);
        var noPayConversation = new JsonObject
        {
            ["context"] = new JsonObject
            {
                ["gameState"] = "MissionState",
                ["conversation"] = new JsonObject { ["heroId"] = "wanderer-a", ["options"] = new JsonArray() }
            },
            ["economy"] = new JsonObject { ["gold"] = 64 }
        };
        if (!RecordUnaffordableNativeResponse(affordabilityMemory, new HashSet<string>(StringComparer.Ordinal), noPayConversation,
                "dialogueSelect", "player_companion_hire_response_2"))
            throw new AgentHostException("establish-clan-companion-unaffordable-response-memory-failed", "The exact Native no-pay response must create one current Hero/Gold observation.");
        affordabilityCheckpoint = AgentHostEycCompanionSearchMemory.Store(affordabilityCheckpoint, affordabilitySnapshot, [], affordabilityMemory);
        var encodedAffordabilityCheckpoint = AgentHostCampaignCheckpointCodec.EncodeForNative(affordabilityCheckpoint.ToJsonString());
        using var checkpointRoundTripReceipt = JsonDocument.Parse(new JsonObject
        {
            ["status"] = "completed",
            ["data"] = new JsonObject
            {
                ["campaignInstanceId"] = "campaign-affordability-fixture",
                ["checkpointBase64"] = encodedAffordabilityCheckpoint
            }
        }.ToJsonString());
        var restartedCheckpoint = AgentHostCampaignCheckpointCodec.ReadFromNativeReceipt(checkpointRoundTripReceipt.RootElement);
        var restartedUnaffordableMemory = AgentHostEycCompanionSearchMemory.ReadUnaffordableHeroGold(restartedCheckpoint);
        var restartedExcludedHeroes = AgentHostEycCompanionSearchMemory.GetCurrentlyUnaffordableHeroIds(restartedUnaffordableMemory, 64);
        var twoCurrentCandidates = new JsonArray(
            new JsonObject { ["heroId"] = "wanderer-a", ["occupation"] = "Wanderer", ["isEnemy"] = false, ["isNotable"] = false },
            new JsonObject { ["heroId"] = "wanderer-b", ["occupation"] = "Wanderer", ["isEnemy"] = false, ["isNotable"] = false });
        var currentCandidatesAfterRestart = FilterWandererCandidates(twoCurrentCandidates, restartedExcludedHeroes);
        if (ReadString(restartedCheckpoint, "campaignInstanceId") != "campaign-affordability-fixture" ||
            currentCandidatesAfterRestart.Count != 1 || ReadString(currentCandidatesAfterRestart[0] as JsonObject, "heroId") != "wanderer-b" ||
            AgentHostEycCompanionSearchMemory.GetCurrentlyUnaffordableHeroIds(restartedUnaffordableMemory, 65).Count != 0)
            throw new AgentHostException("establish-clan-companion-unaffordable-checkpoint-resume-failed", "A saved Native no-pay observation must survive Host restart and leave other Wanderers eligible, then reopen after Gold rises.");

        var noisyNearbyAgents = new JsonArray(Enumerable.Range(0, 40).Select(index => (JsonNode?)new JsonObject
        {
            ["agentIndex"] = index,
            ["heroId"] = "scene-agent-" + index.ToString(CultureInfo.InvariantCulture),
            ["name"] = "Observed Tavern character " + index.ToString(CultureInfo.InvariantCulture),
            ["occupation"] = index == 0 ? "Wanderer" : "Other",
            ["isNotable"] = false,
            ["isEnemy"] = false,
            ["isInteractable"] = index == 0,
            ["distance"] = 1.2 + index
        }).ToArray());
        var noisyTavernState = new JsonObject
        {
            ["context"] = new JsonObject { ["gameState"] = "MissionState", ["menuId"] = null, ["encounterActive"] = true },
            ["location"] = new JsonObject { ["currentSettlementId"] = "town-a" },
            ["economy"] = new JsonObject { ["gold"] = 597 },
            ["mainHeroSkills"] = new JsonObject
            {
                ["skills"] = new JsonArray(Enumerable.Range(0, 12).Select(index => (JsonNode?)new JsonObject
                {
                    ["id"] = "skill_" + index.ToString(CultureInfo.InvariantCulture),
                    ["displayName"] = "Skill " + index.ToString(CultureInfo.InvariantCulture),
                    ["level"] = 100 + index,
                    ["focus"] = 5
                }).ToArray())
            },
            ["mission"] = new JsonObject
            {
                ["active"] = true,
                ["sceneName"] = "empire_house_c_tavern_a",
                ["navigation"] = new JsonObject { ["active"] = false },
                ["leave"] = new JsonObject { ["active"] = false },
                ["nearbySceneAgents"] = noisyNearbyAgents.DeepClone()
            }
        };
        var noisySceneReceipt = new JsonObject
        {
            ["data"] = new JsonObject
            {
                ["scope"] = "active-location-scene",
                ["activeAgentCount"] = 40,
                ["agents"] = new JsonArray(new JsonObject
                {
                    ["agentIndex"] = 0, ["heroId"] = "scene-agent-0", ["name"] = "Observed Tavern character 0",
                    ["occupation"] = "Wanderer", ["isNotable"] = false, ["isEnemy"] = false,
                    ["nativeConversationActionAvailable"] = true, ["distance"] = 1.2
                })
            }
        };
        var projectedCompanionObservation = BuildObservation(noisyTavernState, new JsonArray(), new JsonObject(), null,
            noisySceneReceipt, "scene-agent-0", "scene-agent-0", 0);
        var originalMissionBytes = System.Text.Encoding.UTF8.GetByteCount(noisyTavernState["mission"]!.ToJsonString());
        var projectedMission = projectedCompanionObservation["state"]?["mission"] as JsonObject;
        var projectedMissionBytes = projectedMission is null ? int.MaxValue : System.Text.Encoding.UTF8.GetByteCount(projectedMission.ToJsonString());
        var originalStateBytes = System.Text.Encoding.UTF8.GetByteCount(noisyTavernState.ToJsonString());
        var projectedState = projectedCompanionObservation["state"] as JsonObject;
        var projectedStateBytes = projectedState is null ? int.MaxValue : System.Text.Encoding.UTF8.GetByteCount(projectedState.ToJsonString());
        var projectedCandidates = projectedCompanionObservation["currentSceneWandererCandidates"] as JsonArray;
        var projectedNearby = projectedCompanionObservation["nearbyInteractableWanderers"] as JsonArray;
        var fullSceneObservation = projectedCompanionObservation.DeepClone().AsObject();
        fullSceneObservation["state"]!["mission"]!["nearbySceneAgents"] = noisyNearbyAgents.DeepClone();
        fullSceneObservation["state"]!["mainHeroSkills"] = noisyTavernState["mainHeroSkills"]!.DeepClone();
        const string cacheCostEstimationSystemPrompt = "Stable EYC cost-estimation prefix. Choose only current listed Native actions.";
        var fullSceneContent = fullSceneObservation.ToJsonString();
        var projectedSceneContent = projectedCompanionObservation.ToJsonString();
        var fullSceneTokenEstimate = DeepSeekPromptTokenEstimator.EstimateRequest(fullSceneContent, cacheCostEstimationSystemPrompt,
            fullSceneContent, new Dictionary<string, object?>());
        var projectedSceneTokenEstimate = DeepSeekPromptTokenEstimator.EstimateRequest(projectedSceneContent, cacheCostEstimationSystemPrompt,
            projectedSceneContent, new Dictionary<string, object?>());
        if (projectedMission is null || projectedMission.ContainsKey("nearbySceneAgents") ||
            ReadString(projectedMission, "sceneName") != "empire_house_c_tavern_a" ||
            projectedState is null || projectedState.ContainsKey("mainHeroSkills") ||
            ReadInt(projectedState["economy"] as JsonObject, "gold", -1) != 597 ||
            projectedCandidates?.Count != 1 || ReadString(projectedCandidates[0] as JsonObject, "heroId") != "scene-agent-0" ||
            projectedNearby?.Count != 1 || originalMissionBytes - projectedMissionBytes < 2000 || originalStateBytes - projectedStateBytes < 2500 ||
            fullSceneTokenEstimate.Method != "deepseek-v4-chat-template-plus-structured-metadata" ||
            projectedSceneTokenEstimate.Method != fullSceneTokenEstimate.Method ||
            fullSceneTokenEstimate.TokenizerTokens <= projectedSceneTokenEstimate.TokenizerTokens)
            throw new AgentHostException("establish-clan-companion-observation-projection-failed", "The model payload must omit the raw Tavern agent roster and irrelevant MainHero skill list while preserving Native scene identity, current Wanderer summaries, and current Gold; byte/token savings must be measurable. originalMissionBytes=" + originalMissionBytes + "; projectedMissionBytes=" + projectedMissionBytes + "; originalStateBytes=" + originalStateBytes + "; projectedStateBytes=" + projectedStateBytes + "; candidates=" + projectedCandidates?.Count + "; nearby=" + projectedNearby?.Count + "; fullPromptTokens=" + fullSceneTokenEstimate.TokenizerTokens + "; projectedPromptTokens=" + projectedSceneTokenEstimate.TokenizerTokens);
        var mapPromptRequest = new JsonObject
        {
            ["goal"] = "PRIVATE_GOAL_TEXT",
            ["observation"] = new JsonObject
            {
                ["state"] = new JsonObject { ["context"] = new JsonObject { ["gameState"] = "MapState", ["menuId"] = null } },
                ["visibleSafeTownTargets"] = new JsonArray(new JsonObject { ["id"] = "town-visible" })
            },
            ["allowedActions"] = new JsonArray(new JsonObject { ["action"] = "move" }),
            ["allowedControls"] = new JsonArray("observeAgain")
        };
        var mapPrompt = AgentHostDecisionCycle.BuildEstablishClanCompanionSystemPrompt(mapPromptRequest);
        var menuPromptRequest = new JsonObject
        {
            ["observation"] = new JsonObject { ["state"] = new JsonObject { ["context"] = new JsonObject { ["gameState"] = "MapState", ["menuId"] = "town" } } },
            ["allowedActions"] = new JsonArray(new JsonObject { ["action"] = "menuSelect" }),
            ["allowedControls"] = new JsonArray()
        };
        var menuPrompt = AgentHostDecisionCycle.BuildEstablishClanCompanionSystemPrompt(menuPromptRequest);
        var missionPromptRequest = new JsonObject
        {
            ["observation"] = new JsonObject { ["state"] = new JsonObject { ["context"] = new JsonObject { ["gameState"] = "MissionState", ["menuId"] = "town_tavern" } } },
            ["allowedActions"] = new JsonArray(new JsonObject { ["action"] = "missionNavigateToAgent" }, new JsonObject { ["action"] = "missionLeave" }),
            ["allowedControls"] = new JsonArray()
        };
        var missionPrompt = AgentHostDecisionCycle.BuildEstablishClanCompanionSystemPrompt(missionPromptRequest);
        var dialoguePromptRequest = new JsonObject
        {
            ["observation"] = new JsonObject { ["state"] = new JsonObject { ["context"] = new JsonObject { ["gameState"] = "MissionState", ["conversation"] = new JsonObject { ["heroId"] = "wanderer-visible" } } } },
            ["allowedActions"] = new JsonArray(new JsonObject { ["action"] = "dialogueSelect" }),
            ["allowedControls"] = new JsonArray()
        };
        var dialoguePrompt = AgentHostDecisionCycle.BuildEstablishClanCompanionSystemPrompt(dialoguePromptRequest);
        if (mapPrompt.Length > 950 || menuPrompt.Length > 950 || missionPrompt.Length > 950 || dialoguePrompt.Length > 950 ||
            !mapPrompt.Contains("visibleSafeTownTargets", StringComparison.Ordinal) || !mapPrompt.Contains("observeAgain", StringComparison.Ordinal) ||
            mapPrompt.Contains("player_companion_hire_response_1", StringComparison.Ordinal) || mapPrompt.Contains("FindingFirstBannerPieceSceneNotificationItem", StringComparison.Ordinal) ||
            !menuPrompt.Contains("currently listed enabled menuSelect", StringComparison.Ordinal) || menuPrompt.Contains("missionNavigateToAgent", StringComparison.Ordinal) ||
            !missionPrompt.Contains("current-location", StringComparison.Ordinal) || !missionPrompt.Contains("missionLeave", StringComparison.Ordinal) || missionPrompt.Contains("visibleSafeTownTargets", StringComparison.Ordinal) ||
            !dialoguePrompt.Contains("player_companion_hire_response_1", StringComparison.Ordinal) || !dialoguePrompt.Contains("clickable listed response", StringComparison.Ordinal) ||
            new[] { mapPrompt, menuPrompt, missionPrompt, dialoguePrompt }.Any(prompt => prompt.Contains("PRIVATE_GOAL_TEXT", StringComparison.Ordinal) ||
                !prompt.Contains("reason <= 8 words", StringComparison.Ordinal) || !prompt.Contains("required decision-tool call only", StringComparison.Ordinal)))
            throw new AgentHostException("establish-clan-companion-prompt-stage-projection-failed", "Companion prompts must reveal only the current Native phase, retain the current-action and Journal contract, and omit setup/dialogue rules that cannot apply at that phase.");
        return [
            new { scenario = "companion-navigation-stall-policy-excludes-only-after-two-no-progress-native-approaches", passed = true },
            new { scenario = "establish-clan-companion-targets-only-current-safe-unvisited-town-and-friendly-wanderer", passed = true },
            new { scenario = "establish-clan-companion-town-choice-window-pages-without-world-target-cap", passed = true, totalWorldTargets = 21, choiceWindow = SafeTownDecisionWindowSize },
            new { scenario = "establish-clan-companion-model-observation-compacts-raw-mission-agent-roster-and-preserves-current-wanderer-candidates", originalMissionBytes, projectedMissionBytes, missionBytesSaved = originalMissionBytes - projectedMissionBytes, fullPromptTokens = fullSceneTokenEstimate.TokenizerTokens, projectedPromptTokens = projectedSceneTokenEstimate.TokenizerTokens, estimatedPromptTokensSaved = fullSceneTokenEstimate.TokenizerTokens - projectedSceneTokenEstimate.TokenizerTokens, passed = true },
            new { scenario = "establish-clan-companion-prompt-is-projected-to-the-current-native-map-menu-mission-or-dialogue-stage", mapPromptCharacters = mapPrompt.Length, menuPromptCharacters = menuPrompt.Length, missionPromptCharacters = missionPrompt.Length, dialoguePromptCharacters = dialoguePrompt.Length, passed = true },
            new { scenario = "establish-clan-companion-dialogue-catalog-excludes-unrelated-native-options", passed = true },
            new { scenario = "establish-clan-companion-resolves-current-map-dialogue-before-resuming-travel", passed = true },
            new { scenario = "establish-clan-companion-continues-only-no-choice-map-dialogue", passed = true },
            new { scenario = "establish-clan-companion-nearby-target-uses-native-interact", passed = true },
            new { scenario = "establish-clan-companion-rejects-unlisted-navigation-duration-with-current-catalog-values", passed = true },
            new { scenario = "establish-clan-companion-normalizes-only-formatted-numbers-present-in-current-native-catalog", passed = true }
        ];
    }

    internal static async Task<IReadOnlyList<object>> RunTransportSelfTestsAsync()
    {
        var client = new FakeCompanionClient();
        var provider = new FakeCompanionProvider();
        using var request = JsonDocument.Parse("{\"runId\":\"establish-clan-companion-selftest\",\"goal\":\"Reach the original Journal companion target.\",\"maxDecisions\":24,\"maxElapsedSeconds\":60}");
        var result = await RunAsync(request.RootElement, client, client, provider, CancellationToken.None);
        var expected = new[] { "menuSelect", "menuSelect", "missionSceneAgents", "missionNavigateToAgent", "missionSceneAgents", "missionInteract", "dialogueSelect", "dialogueSelect", "dialogueSelect", "missionLeave" };
        var automaticSceneObservations = result["trace"] is JsonArray transportTrace
            ? transportTrace.OfType<JsonObject>().Count(step => ReadString(step, "stepKind") == "native-tavern-scene-observation")
            : 0;
        if (ReadString(result, "status") != "completed" ||
            ReadString(result["termination"] as JsonObject, "reason") != "native-companion-journal-target-met" ||
            ReadInt(result, "actionsExecuted", 0) != expected.Length || provider.CallCount != expected.Length - 2 || automaticSceneObservations != 2 ||
            !client.Actions.SequenceEqual(expected, StringComparer.Ordinal) || client.Gold != 1340 || client.CompanionCount != 1 ||
            client.ActiveMissionNavigationStateReads < 2 || client.TavernMissionStartupStateReads < 2 || provider.SawActiveMissionNavigation || !provider.SawCompanionObservationProjection ||
            ReadBoolean((result["objectiveSnapshot"] as JsonObject)?["companions"] as JsonObject, "met") != true)
            throw new AgentHostException("establish-clan-companion-transport-self-test-failed", "The injected Native/Provider route did not passively settle the original Tavern Mission, gather current scene candidates without a model call, preserve projected Wanderer candidates without the raw scene roster or MainHero skill list, wait for Native navigation, hire one quoted Wanderer, and verify refreshed original Journal progress. status=" + ReadString(result, "status") + "; termination=" + ReadString(result["termination"] as JsonObject, "reason") + "; failureCode=" + ReadString(result, "failureCode") + "; failure=" + ReadString(result, "failure") + "; actions=" + string.Join(",", client.Actions) + "; calls=" + provider.CallCount + "; automaticSceneObservations=" + automaticSceneObservations + "; activeNavigationReads=" + client.ActiveMissionNavigationStateReads + "; startupReads=" + client.TavernMissionStartupStateReads + "; providerSawActiveNavigation=" + provider.SawActiveMissionNavigation + "; providerSawProjection=" + provider.SawCompanionObservationProjection + "; journalMet=" + ReadBoolean((result["objectiveSnapshot"] as JsonObject)?["companions"] as JsonObject, "met"));

        var delayedTavernClient = new FakeCompanionClient(tavernEntryTransitionDelayReads: 3);
        var delayedTavernProvider = new FakeCompanionProvider();
        var delayedTavernResult = await RunAsync(request.RootElement, delayedTavernClient, delayedTavernClient, delayedTavernProvider, CancellationToken.None);
        var delayedTavernWaitRows = (delayedTavernResult["trace"] as JsonArray)?.OfType<JsonObject>()
            .Where(step => ReadString(step, "stage") == "native-tavern-entry-transition-wait").ToArray() ?? Array.Empty<JsonObject>();
        var delayedTavernSummary = delayedTavernResult["tavernEntryTransitionSummary"] as JsonObject;
        if (ReadString(delayedTavernResult, "status") != "completed" ||
            ReadString(delayedTavernResult["termination"] as JsonObject, "reason") != "native-companion-journal-target-met" ||
            delayedTavernClient.TavernEntryTransitionMapReads != 3 || delayedTavernWaitRows.Length != 2 ||
            delayedTavernWaitRows.Any(step => ReadBoolean(step, "modelDecisionSent") || ReadBoolean(step, "nativeActionSent")) ||
            ReadInt(delayedTavernSummary, "confirmedCount", -1) != 1 || ReadInt(delayedTavernSummary, "waitCount", -1) != 2 ||
            delayedTavernProvider.CallCount != provider.CallCount ||
            !delayedTavernClient.Actions.SequenceEqual(client.Actions, StringComparer.Ordinal))
            throw new AgentHostException("establish-clan-companion-delayed-tavern-entry-not-settled", "After Native town_tavern returns the old Map menu, Host must passively poll without another provider/action until the same settlement's Tavern Mission is observed; then continue the existing companion route.");

        var missingTavernMissionClient = new FakeCompanionClient(neverEnterTavernMission: true);
        var missingTavernMissionProvider = new FakeCompanionProvider();
        var missingTavernMission = await RunAsync(request.RootElement, missingTavernMissionClient, missingTavernMissionClient, missingTavernMissionProvider, CancellationToken.None);
        var missingMissionTrace = missingTavernMission["trace"] as JsonArray;
        if (ReadString(missingTavernMission, "status") != "interrupted" ||
            ReadString(missingTavernMission["termination"] as JsonObject, "reason") != "native-tavern-entry-transition-not-observed" ||
            missingTavernMissionProvider.CallCount != 2 ||
            !missingTavernMissionClient.Actions.SequenceEqual(new[] { "menuSelect", "menuSelect" }, StringComparer.Ordinal) ||
            missingTavernMissionClient.Actions.Contains("missionSceneAgents", StringComparer.Ordinal) ||
            missingMissionTrace?.OfType<JsonObject>().LastOrDefault(step => ReadString(step, "stage") == "native-tavern-entry-transition-not-observed") is not JsonObject missingMissionStep ||
            ReadBoolean(missingMissionStep, "visitedTownMarked") || ReadBoolean(missingMissionStep, "modelDecisionSent") || ReadBoolean(missingMissionStep, "nativeActionSent") ||
            ReadInt(missingTavernMission["tavernEntryTransitionSummary"] as JsonObject, "confirmedCount", -1) != 0)
            throw new AgentHostException("establish-clan-companion-missing-tavern-mission-marked-visited", "If the original menu action never reaches a Tavern Mission within the bound, Host must return without another model/menu action and must not mark the Town visited.");

        using var tavernTransitionCancellation = new CancellationTokenSource();
        var canceledTavernEntryClient = new FakeCompanionClient(tavernEntryTransitionDelayReads: 1, cancelAfterTavernEntryMapRead: tavernTransitionCancellation);
        var canceledTavernEntryProvider = new FakeCompanionProvider();
        var canceledTavernEntry = await RunAsync(request.RootElement, canceledTavernEntryClient, canceledTavernEntryClient,
            canceledTavernEntryProvider, tavernTransitionCancellation.Token);
        if (ReadString(canceledTavernEntry, "status") != "failed" ||
            ReadString(canceledTavernEntry["termination"] as JsonObject, "reason") != "host-stop-or-time-budget" ||
            canceledTavernEntryProvider.CallCount != 2 ||
            !canceledTavernEntryClient.Actions.SequenceEqual(new[] { "menuSelect", "menuSelect" }, StringComparer.Ordinal) ||
            canceledTavernEntryClient.Actions.Contains("missionSceneAgents", StringComparer.Ordinal) ||
            ReadInt(canceledTavernEntry["tavernEntryTransitionSummary"] as JsonObject, "confirmedCount", -1) != 0)
            throw new AgentHostException("establish-clan-companion-tavern-entry-cancellation-sent-extra-action", $"Host cancellation during the passive Tavern transition must exit without another provider decision, Native action, scene query or visited-town mark. status={ReadString(canceledTavernEntry, "status")}; termination={ReadString(canceledTavernEntry["termination"] as JsonObject, "reason")}; providers={canceledTavernEntryProvider.CallCount}; actions={string.Join(",", canceledTavernEntryClient.Actions)}; summary={canceledTavernEntry["tavernEntryTransitionSummary"]?.ToJsonString()};");

        var stalledClient = new FakeCompanionClient(simulateStalledNavigation: true);
        var stalledProvider = new FakeCompanionStallProvider();
        var stalled = await RunAsync(request.RootElement, stalledClient, stalledClient, stalledProvider, CancellationToken.None);
        if (ReadString(stalled["termination"] as JsonObject, "reason") != "companion-model-stopped" ||
            stalledClient.NavigationAttemptCount != 3 || stalledClient.MissionLeaveCount != 1 ||
            stalledProvider.NavigationDecisionCount != 3 || !stalledProvider.StoppedOnFreeMap ||
            !stalledClient.Actions.Contains("missionLeave", StringComparer.Ordinal))
            throw new AgentHostException("establish-clan-companion-automatic-observation-stall-recovery-failed", "The automatic scene scan after Native navigation must apply the two-attempt no-progress guard, leave the stalled target, and reach a safe Map without a fourth same-target navigation. status=" + ReadString(stalled, "status") + "; termination=" + ReadString(stalled["termination"] as JsonObject, "reason") + "; navigationAttempts=" + stalledClient.NavigationAttemptCount + "; missionLeaves=" + stalledClient.MissionLeaveCount + "; providerNavigationDecisions=" + stalledProvider.NavigationDecisionCount);

        var stopClient = new FakeCompanionClient();
        var stopProvider = new FakeCompanionStopProvider();
        using var stopRequest = JsonDocument.Parse("{\"runId\":\"establish-clan-companion-safe-stop-selftest\",\"goal\":\"Hire one Companion.\",\"maxDecisions\":1,\"maxElapsedSeconds\":10}");
        var stopped = await RunAsync(stopRequest.RootElement, stopClient, stopClient, stopProvider, CancellationToken.None);
        if (ReadString(stopped, "status") != "interrupted" ||
            ReadString(stopped["termination"] as JsonObject, "reason") != "companion-model-stopped" ||
            ReadInt(stopped, "actionsExecuted", 0) != 0 || stopProvider.CallCount != 1 || stopClient.Actions.Count != 0)
            throw new AgentHostException("establish-clan-companion-safe-stop-self-test-failed", "A listed stop control must stop the Companion subgoal explicitly without being rejected as an unavailable control or sending a Native action.");
        var missionStopClient = new FakeMissionStopRecoveryClient();
        var missionStopProvider = new FakeMissionStopRecoveryProvider();
        var missionStopRecovered = await RunAsync(request.RootElement, missionStopClient, missionStopClient, missionStopProvider, CancellationToken.None);
        if (ReadString(missionStopRecovered, "status") != "interrupted" ||
            ReadString(missionStopRecovered["termination"] as JsonObject, "reason") != "companion-model-stopped" ||
            ReadInt(missionStopRecovered, "actionsExecuted", 0) != 3 || missionStopProvider.CallCount != 4 ||
            !missionStopClient.Actions.SequenceEqual(["missionSceneAgents", "missionLeave", "mapSettlementTargets"], StringComparer.Ordinal) ||
            !missionStopProvider.SawMissionStopRecovery)
            throw new AgentHostException("establish-clan-companion-mission-stop-did-not-recover-to-map", "A model stop inside a Tavern Mission must be corrected to a listed Native exit, return to Map, and only then allow safe parent replanning. status=" + ReadString(missionStopRecovered, "status") + "; termination=" + ReadString(missionStopRecovered["termination"] as JsonObject, "reason") + "; actionsExecuted=" + ReadInt(missionStopRecovered, "actionsExecuted", 0) + "; providerCalls=" + missionStopProvider.CallCount + "; nativeActions=" + string.Join(",", missionStopClient.Actions) + "; recoveryFeedback=" + missionStopProvider.SawMissionStopRecovery);
        var movementWaitResult = await RunMapMovementWaitSelfTestAsync();
        var inheritedMoveResult = await RunInheritedNativeMoveSelfTestAsync();
        var persistentCompanionMemory = await RunPersistentNoCandidateTownMemorySelfTestAsync();
        return [
            new { scenario = "establish-clan-companion-passively-settles-friendly-tavern-mission-startup-before-decisions", startupReads = client.TavernMissionStartupStateReads, passed = true },
            new { scenario = "establish-clan-companion-waits-out-stale-backstreet-map-state-before-model-can-select-back", transitionMapReads = delayedTavernClient.TavernEntryTransitionMapReads, providerDecisions = delayedTavernProvider.CallCount, waitCount = ReadInt(delayedTavernSummary, "waitCount", -1), passed = true },
            new { scenario = "establish-clan-companion-tavern-transition-timeout-does-not-mark-town-visited-or-reissue-entry", transitionMapReads = missingTavernMissionClient.TavernEntryTransitionMapReads, providerDecisions = missingTavernMissionProvider.CallCount, passed = true },
            new { scenario = "establish-clan-companion-tavern-transition-honors-host-cancellation-without-followup-decision-or-action", providerDecisions = canceledTavernEntryProvider.CallCount, nativeActions = canceledTavernEntryClient.Actions.ToArray(), passed = true },
            new { scenario = "establish-clan-companion-passively-waits-for-native-mission-navigation-before-next-model-decision", activeNavigationReads = client.ActiveMissionNavigationStateReads, modelDecisions = provider.CallCount, nativeActions = client.Actions.ToArray(), passed = true },
            new { scenario = "establish-clan-companion-reads-current-tavern-agents-without-spending-a-model-decision", automaticSceneObservations, modelDecisionsSaved = 2, passed = true },
            new { scenario = "establish-clan-companion-automatic-scene-observation-excludes-stalled-wanderer-after-two-native-no-progress-retries", navigationAttempts = stalledClient.NavigationAttemptCount, providerNavigationDecisions = stalledProvider.NavigationDecisionCount, missionLeaves = stalledClient.MissionLeaveCount, passed = true },
            new { scenario = "establish-clan-companion-listed-safe-stop-is-interrupted-with-zero-native-actions", decisions = stopProvider.CallCount, passed = true },
            new { scenario = "establish-clan-companion-mission-stop-is-corrected-to-native-leave-before-parent-replan", decisions = missionStopProvider.CallCount, nativeActions = missionStopClient.Actions.ToArray(), passed = true },
            await RunInvalidActionRecoverySelfTestAsync(request.RootElement),
            persistentCompanionMemory,
            inheritedMoveResult,
            movementWaitResult
        ];
    }

    private static async Task<object> RunPersistentNoCandidateTownMemorySelfTestAsync()
    {
        var firstClient = new FakePersistentNoCandidateCompanionClient();
        var firstProvider = new FakeNoCandidateCompanionProvider(firstRun: true);
        using var request = JsonDocument.Parse("{\"runId\":\"establish-clan-companion-memory-write-selftest\",\"goal\":\"Hire one companion.\",\"maxDecisions\":12,\"maxElapsedSeconds\":60}");
        var first = await RunAsync(request.RootElement, firstClient, firstClient, firstProvider, CancellationToken.None);
        using var storedCheckpointReceipt = firstClient.ReadStoredCheckpointReceipt();
        var checkpoint = AgentHostCampaignCheckpointCodec.ReadFromNativeReceipt(storedCheckpointReceipt.RootElement);
        var storedTownIds = AgentHostEycCompanionSearchMemory.ReadNoCandidateTownIds(checkpoint);
        var journalData = new JsonObject { ["journalStages"] = firstClient.ReadJournal() };
        var expectedFingerprint = AgentHostEycCompanionSearchMemory.BuildJournalFingerprint(AgentHostEstablishYourClanGoalLoop.BuildObjectiveSnapshot(
            AgentHostEstablishYourClanGoalLoop.BuildJournalObjectives(journalData)));
        if (!storedTownIds.SetEquals(["town_a"]) ||
            AgentHostEycCompanionSearchMemory.ReadJournalFingerprint(checkpoint) != expectedFingerprint ||
            firstClient.CheckpointWrites != 1 || firstProvider.CallCount != 6 || ReadString(first["termination"] as JsonObject, "reason") != "companion-model-stopped")
            throw new AgentHostException("eyc-companion-memory-write-self-test-failed", "A Native Tavern with no eligible Wanderer must be remembered in the current Campaign save only after the original Mission returns to Map. writes=" + firstClient.CheckpointWrites + "; decisions=" + firstProvider.CallCount + "; nativeActions=" + string.Join(",", firstClient.Actions) + "; rememberedTownCount=" + storedTownIds.Count + "; termination=" + ReadString(first["termination"] as JsonObject, "reason") + "; failureCode=" + ReadString(first, "failureCode") + "; failure=" + ReadString(first, "failure"));

        var resumedClient = new FakePersistentNoCandidateCompanionClient(firstClient.StoredCheckpointJson, startAtFreeMap: true);
        var resumedProvider = new FakeNoCandidateCompanionProvider(firstRun: false);
        using var resumeRequest = JsonDocument.Parse("{\"runId\":\"establish-clan-companion-memory-resume-selftest\",\"goal\":\"Hire one companion.\",\"maxDecisions\":4,\"maxElapsedSeconds\":60}");
        var resumed = await RunAsync(resumeRequest.RootElement, resumedClient, resumedClient, resumedProvider, CancellationToken.None);
        if (ReadString(resumed["termination"] as JsonObject, "reason") != "companion-model-stopped" ||
            !resumedProvider.SawOnlyTownBAfterResume || resumedClient.CheckpointWrites != 0)
            throw new AgentHostException("eyc-companion-memory-resume-self-test-failed", "A new Host on the same saved Campaign must skip the previously verified no-candidate Town without rewriting or losing the checkpoint.");

        return new { scenario = "eyc-companion-no-candidate-town-survives-host-restart-in-same-native-save-and-does-not-exclude-other-towns", firstRunProviderCalls = firstProvider.CallCount, resumedRunProviderCalls = resumedProvider.CallCount, checkpointWrites = firstClient.CheckpointWrites, passed = true };
    }

    private static async Task<object> RunInvalidActionRecoverySelfTestAsync(JsonElement request)
    {
        var client = new FakeCompanionClient();
        var provider = new FakeInvalidCompanionActionProvider();
        var result = await RunAsync(request, client, client, provider, CancellationToken.None);
        var expectedActions = new[] { "menuSelect", "menuSelect", "missionSceneAgents" };
        if (ReadString(result, "status") != "failed" ||
            ReadString(result["termination"] as JsonObject, "reason") != "companion-action-recovery-exhausted" ||
            ReadInt(result, "actionsExecuted", 0) != expectedActions.Length ||
            provider.CallCount != 4 || !provider.SawBoundedRecoveryFeedback ||
            !client.Actions.SequenceEqual(expectedActions, StringComparer.Ordinal))
            throw new AgentHostException("establish-clan-companion-invalid-action-recovery-self-test-failed", "Two invalid Companion decisions must receive only bounded catalog feedback and terminate before any unlisted Native action is sent.");
        return new { scenario = "establish-clan-companion-bounds-unlisted-action-retries-before-native", decisions = provider.CallCount, nativeActions = client.Actions.ToArray(), passed = true };
    }

    private static async Task<object> RunMapMovementWaitSelfTestAsync()
    {
        var client = new FakeMovementCompanionClient();
        var provider = new FakeMovementDecisionProvider();
        using var request = JsonDocument.Parse("{\"runId\":\"establish-clan-companion-map-movement-selftest\",\"goal\":\"Reach a friendly Town Tavern to hire one Companion.\",\"maxDecisions\":4,\"maxElapsedSeconds\":30}");
        var result = await RunAsync(request.RootElement, client, client, provider, CancellationToken.None);
        var expectedActions = new[] { "mapSettlementTargets", "move", "continueSceneNotification", "menuSelect" };
        if (provider.CallCount != 4 || client.Actions.Count != expectedActions.Length ||
            !client.Actions.SequenceEqual(expectedActions, StringComparer.Ordinal) || client.ActiveMovementStateReads < 2 ||
            client.ExplicitClockActions != 0 || client.SceneNotificationContinueCount != 1 || !provider.SawSceneNotification ||
            ReadInt(result, "actionsExecuted", 0) != expectedActions.Length)
            throw new AgentHostException("establish-clan-companion-map-movement-wait-selftest-failed", "A safe Native scene notification must interrupt passive travel waiting, be visible to the model as the only action, close through its Native handler, then resume passive movement without time controls or repeated decisions. status=" + ReadString(result, "status") + "; termination=" + ReadString(result["termination"] as JsonObject, "reason") + "; actions=" + string.Join(",", client.Actions) + "; decisions=" + provider.CallCount + "; passiveReads=" + client.ActiveMovementStateReads + "; sceneCloses=" + client.SceneNotificationContinueCount + "; modelSawModal=" + provider.SawSceneNotification + "; clockActions=" + client.ExplicitClockActions + "; actionCount=" + ReadInt(result, "actionsExecuted", 0));
        return new { scenario = "establish-clan-companion-native-map-scene-notification-closes-then-movement-resumes", decisions = provider.CallCount, nativeActions = client.Actions.ToArray(), passiveMovementStateReads = client.ActiveMovementStateReads, sceneNotificationContinueCount = client.SceneNotificationContinueCount, explicitClockActions = client.ExplicitClockActions, passed = true };
    }

    private static async Task<object> RunInheritedNativeMoveSelfTestAsync()
    {
        var client = new FakeInheritedNativeMoveCompanionClient();
        var provider = new FakeInheritedNativeMoveProvider();
        using var request = JsonDocument.Parse("{\"runId\":\"establish-clan-companion-inherited-native-move-selftest\",\"goal\":\"Hire one Companion.\",\"maxDecisions\":1,\"maxElapsedSeconds\":10}");
        var result = await RunAsync(request.RootElement, client, client, provider, CancellationToken.None);
        var inheritedTrace = result["trace"] is JsonArray trace
            ? trace.OfType<JsonObject>().Any(step => ReadString(step, "stage") == "native-settlement-move-inherited-by-companion-route")
            : false;
        if (ReadString(result["termination"] as JsonObject, "reason") != "companion-model-stopped" ||
            ReadInt(result, "actionsExecuted", 0) != 0 || provider.CallCount != 1 || client.Actions.Count != 0 || !provider.SawNoDuplicateMoveAction || !inheritedTrace)
            throw new AgentHostException("establish-clan-companion-inherited-native-move-self-test-failed", "When Native already moves MainParty toward a Settlement, the Companion route must passively inherit that target and never query/reissue the same move. termination=" + ReadString(result["termination"] as JsonObject, "reason") + "; calls=" + provider.CallCount + "; actions=" + string.Join(",", client.Actions) + "; noDuplicateMove=" + provider.SawNoDuplicateMoveAction + "; inheritedTrace=" + inheritedTrace + "; providerObservation=" + provider.DebugState);
        return new { scenario = "establish-clan-companion-inherits-current-native-settlement-move-without-reissuing-it", decisions = provider.CallCount, nativeActions = client.Actions.ToArray(), passed = true };
    }

    internal static async Task<JsonObject> RunAsync(
        JsonElement request,
        IAgentHostCampaignNativeClient campaignClient,
        IAgentHostCompanionHiringNativeClient companionClient,
        IAgentHostDecisionProvider provider,
        CancellationToken cancellationToken,
        int priorDecisions = 0,
        long priorPromptTokens = 0,
        long priorCompletionTokens = 0,
        JsonArray? priorTrace = null,
        JsonArray? priorProviderRouteHistory = null)
    {
        var runId = ReadString(request, "runId") ?? Guid.NewGuid().ToString("N");
        var maxDecisions = Math.Clamp(ReadInt(request, "maxDecisions", MaxDecisions), 1, MaxDecisions);
        var maxSeconds = Math.Clamp(ReadInt(request, "maxElapsedSeconds", (int)MaxElapsed.TotalSeconds), 10, (int)MaxElapsed.TotalSeconds);
        var decisions = priorDecisions;
        var actionsExecuted = 0;
        long promptTokens = priorPromptTokens;
        long completionTokens = priorCompletionTokens;
        var trace = priorTrace?.DeepClone() as JsonArray ?? new JsonArray();
        var routes = priorProviderRouteHistory?.DeepClone() as JsonArray ?? new JsonArray();
        var safeTowns = (JsonArray?)null;
        var sceneAgentsReceipt = (JsonObject?)null;
        string? moveTargetId = null;
        string? selectedHeroId = null;
        string? interactTargetHeroId = null;
        var moveStartPending = false;
        var missionTransitionPending = false;
        var tavernEntryTransitionPending = false;
        string? pendingTavernEntrySettlementId = null;
        var tavernEntryTransitionWaits = 0;
        var totalTavernEntryTransitionWaits = 0;
        var tavernEntryTransitionConfirmedCount = 0;
        var visitedTowns = new HashSet<string>(StringComparer.Ordinal);
        var noCandidateTownIds = new HashSet<string>(StringComparer.Ordinal);
        var excludedHeroes = new HashSet<string>(StringComparer.Ordinal);
        var unaffordableHeroGold = new Dictionary<string, int>(StringComparer.Ordinal);
        var unaffordableCheckpointDirty = false;
        var checkpointClient = campaignClient as IAgentHostCampaignCheckpointNativeClient;
        JsonObject? campaignCheckpoint = null;
        string? storedCompanionJournalFingerprint = null;
        JsonObject? storedCompanionJournalSnapshot = null;
        string? currentCompanionJournalFingerprint = null;
        JsonObject? currentCompanionJournalSnapshot = null;
        string? pendingNoCandidateTownId = null;
        var companionSearchMemoryReconciled = false;
        var checkpointWriteCount = 0;
        var memoryMatchedCurrentJournal = false;
        var memoryInvalidatedByJournalProgress = false;
        var memoryReusedAfterJournalDecrease = false;
        string? lastCheckpointWriteStatus = null;
        var navigationNoProgressAttempts = new Dictionary<string, int>(StringComparer.Ordinal);
        string? navigationProgressTargetHeroId = null;
        double? navigationProgressStartDistance = null;
        var rejectedProviderDecisions = 0;
        var rejectedActionDecisions = 0;
        var missionWaitPending = false;
        var tavernMissionStartupWaits = 0;
        JsonObject? decisionFeedback = null;
        var start = Stopwatch.GetTimestamp();
        using var elapsed = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        elapsed.CancelAfter(TimeSpan.FromSeconds(maxSeconds));

        void ReconcileNavigationProgress(JsonObject stateAfterNavigation, JsonObject? sceneObservation)
        {
            if (string.IsNullOrWhiteSpace(navigationProgressTargetHeroId) || !navigationProgressStartDistance.HasValue) return;
            var targetHeroId = navigationProgressTargetHeroId;
            var targetDistance = FindWandererDistance(sceneObservation, targetHeroId);
            var targetInteractable = IsWandererInteractable(stateAfterNavigation, targetHeroId);
            if (targetDistance.HasValue && !targetInteractable)
            {
                var progress = EvaluateNavigationNoProgress(navigationProgressStartDistance, targetDistance,
                    navigationNoProgressAttempts.GetValueOrDefault(targetHeroId), isInteractable: false);
                var madeProgress = progress.Attempts == 0;
                if (madeProgress) navigationNoProgressAttempts.Remove(targetHeroId);
                else navigationNoProgressAttempts[targetHeroId] = progress.Attempts;
                if (!madeProgress)
                {
                    selectedHeroId = null;
                    interactTargetHeroId = null;
                    decisionFeedback = new JsonObject
                    {
                        ["kind"] = progress.ExcludeTarget ? "native-navigation-target-stalled" : "native-navigation-no-measured-approach",
                        ["message"] = progress.ExcludeTarget
                            ? "Two completed Native navigation attempts did not measurably reduce this Wanderer's distance. This candidate is temporarily excluded; choose another current candidate or a listed Native leave action."
                            : "The last Native navigation ended without a measured approach. Do not repeat this target immediately; inspect the full current scene candidate catalog."
                    };
                    if (progress.ExcludeTarget)
                    {
                        excludedHeroes.Add(targetHeroId);
                        navigationNoProgressAttempts.Remove(targetHeroId);
                    }
                }
            }
            else if (targetInteractable)
            {
                navigationNoProgressAttempts.Remove(targetHeroId);
            }
            navigationProgressTargetHeroId = null;
            navigationProgressStartDistance = null;
        }

        try
        {
            if (checkpointClient is not null)
            {
                using var checkpointReceipt = await checkpointClient.ReadCampaignCheckpointAsync(elapsed.Token);
                campaignCheckpoint = AgentHostCampaignCheckpointCodec.ReadFromNativeReceipt(checkpointReceipt.RootElement);
                storedCompanionJournalFingerprint = AgentHostEycCompanionSearchMemory.ReadJournalFingerprint(campaignCheckpoint);
                storedCompanionJournalSnapshot = AgentHostEycCompanionSearchMemory.ReadJournalSnapshot(campaignCheckpoint);
                noCandidateTownIds.UnionWith(AgentHostEycCompanionSearchMemory.ReadNoCandidateTownIds(campaignCheckpoint));
                unaffordableHeroGold = AgentHostEycCompanionSearchMemory.ReadUnaffordableHeroGold(campaignCheckpoint);
            }
            await provider.CheckConfiguredModelAsync(elapsed.Token);
            while (decisions < maxDecisions)
            {
                elapsed.Token.ThrowIfCancellationRequested();
                using var nativeState = await campaignClient.ReadStateAsync(elapsed.Token);
                var state = ReadState(nativeState.RootElement)
                    ?? throw new AgentHostException("companion-state-unavailable", "Native did not provide a current Campaign or Tavern Mission state.");
                var context = state["context"] as JsonObject;
                var gameState = ReadString(context, "gameState");
                if (gameState is not ("MapState" or "MissionState"))
                    return BuildResult("interrupted", "native-state-out-of-scope", "The current Native state is outside Campaign Map/Town Tavern Companion handling; no new game action was attempted.", "companion-state-out-of-scope", state);
                if (ReadBoolean(context, "inquiryOpen") || ReadBoolean(context, "escapeMenuOpen"))
                    return BuildResult("interrupted", "native-modal-out-of-scope", "A Native modal interrupted the Companion route; the executor did not guess a response.", "companion-native-modal", state);
                if (ReadBoolean(context?["captivity"] as JsonObject, "isCaptive") ||
                    (AgentHostCampaignStateFacts.IsActiveEncounter(state) && !IsNativeTavernMissionState(state)))
                    return BuildResult("interrupted", "campaign-interruption", "Captivity or an encounter interrupts the Tavern hiring route and must be handled by its own Native subflow.", "companion-campaign-interruption", state);
                var sceneNotification = context?["sceneNotification"] as JsonObject;
                var sceneNotificationActive = ReadBoolean(sceneNotification, "hasActiveNotification");
                var sceneNotificationCanContinue = ReadBoolean(sceneNotification, "canContinue");
                if (sceneNotificationActive && !sceneNotificationCanContinue)
                    return BuildResult("interrupted", "native-scene-notification-out-of-scope", "A Native scene notification is visible, but its current type or close behavior is not in the verified no-choice allowlist.", "companion-scene-notification-out-of-scope", state);

                if (tavernEntryTransitionPending)
                {
                    var currentEntrySettlementId = ReadString(state["location"] as JsonObject, "currentSettlementId");
                    if (IsNativeTavernMissionState(state) &&
                        !string.IsNullOrWhiteSpace(pendingTavernEntrySettlementId) &&
                        string.Equals(currentEntrySettlementId, pendingTavernEntrySettlementId, StringComparison.Ordinal))
                    {
                        tavernEntryTransitionPending = false;
                        visitedTowns.Add(pendingTavernEntrySettlementId);
                        tavernEntryTransitionConfirmedCount++;
                        trace.Add(new JsonObject
                        {
                            ["stage"] = "native-tavern-entry-transition-confirmed",
                            ["settlementId"] = pendingTavernEntrySettlementId,
                            ["sceneName"] = ReadString(state["mission"] as JsonObject, "sceneName"),
                            ["waitCount"] = tavernEntryTransitionWaits,
                            ["visitedTownMarked"] = true,
                            ["modelDecisionSent"] = false,
                            ["nativeActionSent"] = false
                        });
                        pendingTavernEntrySettlementId = null;
                        tavernEntryTransitionWaits = 0;
                    }
                    else
                    {
                        tavernEntryTransitionWaits++;
                        totalTavernEntryTransitionWaits++;
                        var settlementChanged = !string.IsNullOrWhiteSpace(pendingTavernEntrySettlementId) &&
                            !string.IsNullOrWhiteSpace(currentEntrySettlementId) &&
                            !string.Equals(currentEntrySettlementId, pendingTavernEntrySettlementId, StringComparison.Ordinal);
                        if (settlementChanged || tavernEntryTransitionWaits >= MaxTavernEntryTransitionWaits)
                        {
                            trace.Add(new JsonObject
                            {
                                ["stage"] = "native-tavern-entry-transition-not-observed",
                                ["expectedSettlementId"] = pendingTavernEntrySettlementId,
                                ["observedSettlementId"] = currentEntrySettlementId,
                                ["gameState"] = gameState,
                                ["menuId"] = ReadString(context, "menuId"),
                                ["waitCount"] = tavernEntryTransitionWaits,
                                ["visitedTownMarked"] = false,
                                ["modelDecisionSent"] = false,
                                ["nativeActionSent"] = false
                            });
                            return BuildResult("interrupted", "native-tavern-entry-transition-not-observed",
                                "The original Town Tavern menu action did not produce a Native Tavern Mission before its bounded observation ended; the town was not marked visited and no entry action was replayed.",
                                "native-tavern-entry-transition-not-observed", state);
                        }

                        trace.Add(new JsonObject
                        {
                            ["stage"] = "native-tavern-entry-transition-wait",
                            ["expectedSettlementId"] = pendingTavernEntrySettlementId,
                            ["observedGameState"] = gameState,
                            ["observedMenuId"] = ReadString(context, "menuId"),
                            ["waitCount"] = tavernEntryTransitionWaits,
                            ["visitedTownMarked"] = false,
                            ["modelDecisionSent"] = false,
                            ["nativeActionSent"] = false
                        });
                        await Task.Delay(TimeSpan.FromSeconds(1), elapsed.Token);
                        continue;
                    }
                }

                var nativeTavernMission = state["mission"] as JsonObject;
                if (IsNativeTavernMissionState(state) &&
                    (ReadString(nativeTavernMission, "nativeMissionCurrentState") == "Initializing" ||
                     !ReadBoolean(nativeTavernMission, "nativeConversationReady")))
                {
                    if (tavernMissionStartupWaits >= MaxTavernMissionStartupWaits)
                        return BuildResult("failed", "native-tavern-mission-startup-timeout", "The exact friendly Town Tavern Mission remained in Native initialization after bounded passive reads; no model decision or game action was sent.", "native-tavern-mission-startup-timeout", state);

                    var startupCampaignDayBefore = ReadDouble(state, "campaignDay");
                    tavernMissionStartupWaits++;
                    await Task.Delay(TimeSpan.FromMilliseconds(500), elapsed.Token);
                    using var settledMissionState = await campaignClient.ReadStateAsync(elapsed.Token);
                    var settledState = ReadState(settledMissionState.RootElement)
                        ?? throw new AgentHostException("companion-state-unavailable", "Native did not provide a state after passive Tavern Mission startup settling.");
                    if (!AgentHostEstablishYourClanGoalLoop.HasActiveQuest(settledMissionState.RootElement))
                        return BuildResult("failed", "native-tavern-mission-startup-lost-eyc", "The exact Tavern Mission startup wait did not preserve the original active EYC Quest.", "native-tavern-mission-startup-lost-eyc", settledState);
                    var startupCampaignDayAfter = ReadDouble(settledState, "campaignDay");
                    trace.Add(new JsonObject
                    {
                        ["stage"] = "native-tavern-mission-startup-settle",
                        ["attempt"] = tavernMissionStartupWaits,
                        ["before"] = AgentHostHarnessProgressTrace.BuildNativeStateSummary(new JsonObject { ["state"] = state.DeepClone(), ["campaignDay"] = double.IsFinite(startupCampaignDayBefore) ? JsonValue.Create(startupCampaignDayBefore) : null }),
                        ["after"] = AgentHostHarnessProgressTrace.BuildNativeStateSummary(new JsonObject { ["state"] = settledState.DeepClone(), ["campaignDay"] = double.IsFinite(startupCampaignDayAfter) ? JsonValue.Create(startupCampaignDayAfter) : null }),
                        ["beforeNativeMissionCurrentState"] = ReadString(state["mission"] as JsonObject, "nativeMissionCurrentState"),
                        ["afterNativeMissionCurrentState"] = ReadString(settledState["mission"] as JsonObject, "nativeMissionCurrentState"),
                        ["nativeActionSent"] = false,
                        ["modelDecisionSent"] = false
                    });
                    continue;
                }

                var journal = await ReadJournalAsync(companionClient, elapsed.Token);
                var objective = AgentHostEstablishYourClanGoalLoop.BuildObjectiveSnapshot(journal);
                var objectiveFingerprint = AgentHostEycCompanionSearchMemory.BuildJournalFingerprint(objective);
                var currentGold = ReadInt(state["economy"] as JsonObject, "gold", -1);
                var newlyAffordableHeroIds = currentGold < 0
                    ? Array.Empty<string>()
                    : unaffordableHeroGold.Where(pair => currentGold > pair.Value).Select(pair => pair.Key).ToArray();
                if (AgentHostEycCompanionSearchMemory.ReconcileUnaffordableHeroGold(unaffordableHeroGold, currentGold))
                {
                    unaffordableCheckpointDirty = true;
                    foreach (var heroId in newlyAffordableHeroIds) excludedHeroes.Remove(heroId);
                }
                if (currentGold >= 0)
                    excludedHeroes.UnionWith(AgentHostEycCompanionSearchMemory.GetCurrentlyUnaffordableHeroIds(unaffordableHeroGold, currentGold));
                var companionCheckpointDirty = unaffordableCheckpointDirty;
                if (!companionSearchMemoryReconciled)
                {
                    companionSearchMemoryReconciled = true;
                    if (string.Equals(storedCompanionJournalFingerprint, objectiveFingerprint, StringComparison.Ordinal))
                    {
                        memoryMatchedCurrentJournal = true;
                        visitedTowns.UnionWith(noCandidateTownIds);
                    }
                    else if (AgentHostEycCompanionSearchMemory.HasForwardProgressOrTargetChange(storedCompanionJournalSnapshot, objective))
                    {
                        memoryInvalidatedByJournalProgress = !string.IsNullOrWhiteSpace(storedCompanionJournalFingerprint) || noCandidateTownIds.Count > 0;
                        noCandidateTownIds.Clear();
                        visitedTowns.Clear();
                        companionCheckpointDirty = campaignCheckpoint?["eycCompanionSearchMemoryV1"] is JsonObject;
                    }
                    else
                    {
                        memoryReusedAfterJournalDecrease = true;
                        visitedTowns.UnionWith(noCandidateTownIds);
                        companionCheckpointDirty = campaignCheckpoint?["eycCompanionSearchMemoryV1"] is JsonObject;
                    }
                    currentCompanionJournalFingerprint = objectiveFingerprint;
                    currentCompanionJournalSnapshot = objective.DeepClone() as JsonObject;
                }
                else if (!string.Equals(currentCompanionJournalFingerprint, objectiveFingerprint, StringComparison.Ordinal))
                {
                    if (AgentHostEycCompanionSearchMemory.HasForwardProgressOrTargetChange(currentCompanionJournalSnapshot, objective))
                    {
                        noCandidateTownIds.Clear();
                        visitedTowns.Clear();
                        memoryInvalidatedByJournalProgress = true;
                    }
                    else
                    {
                        memoryReusedAfterJournalDecrease = true;
                    }
                    pendingNoCandidateTownId = null;
                    currentCompanionJournalFingerprint = objectiveFingerprint;
                    currentCompanionJournalSnapshot = objective.DeepClone() as JsonObject;
                    companionCheckpointDirty = campaignCheckpoint?["eycCompanionSearchMemoryV1"] is JsonObject;
                }

                if (gameState == "MapState" && (pendingNoCandidateTownId is not null || companionCheckpointDirty) &&
                    !ReadBoolean(state["context"] as JsonObject, "inquiryOpen") && !ReadBoolean(state["context"] as JsonObject, "escapeMenuOpen") &&
                    !AgentHostCampaignStateFacts.IsActiveEncounter(state) && !ReadBoolean(state, "partyScreenOpen") && !ReadBoolean(state, "inventoryScreenOpen"))
                {
                    if (pendingNoCandidateTownId is not null)
                    {
                        noCandidateTownIds.Add(pendingNoCandidateTownId);
                        visitedTowns.Add(pendingNoCandidateTownId);
                    }
                    if (checkpointClient is not null && campaignCheckpoint is not null)
                    {
                        var updatedCheckpoint = AgentHostEycCompanionSearchMemory.Store(campaignCheckpoint, objective, noCandidateTownIds, unaffordableHeroGold);
                        using var checkpointWrite = await checkpointClient.WriteCampaignCheckpointAsync(updatedCheckpoint.ToJsonString(), elapsed.Token);
                        if (ReadString(checkpointWrite.RootElement, "status") != "completed")
                            return BuildResult("failed", "companion-search-checkpoint-write-failed", "Native did not confirm saving the Companion no-candidate town memory; the Host will not rely on an unpersisted exclusion.", "companion-search-checkpoint-write-failed", state, journal, objective);
                        campaignCheckpoint = updatedCheckpoint;
                        checkpointWriteCount++;
                        if (unaffordableCheckpointDirty)
                        {
                            trace.Add(new JsonObject
                            {
                                ["stepKind"] = "unaffordable-wanderer-memory-checkpoint-write",
                                ["status"] = "completed",
                                ["rememberedHeroCount"] = unaffordableHeroGold.Count,
                                ["campaignCheckpointWriteCount"] = checkpointWriteCount,
                                ["nativeGold"] = currentGold,
                                ["campaignInstanceMatched"] = true
                            });
                        }
                        unaffordableCheckpointDirty = false;
                        lastCheckpointWriteStatus = "completed";
                    }
                    trace.Add(new JsonObject
                    {
                        ["stage"] = "native-campaign-companion-search-memory-saved",
                        ["campaignMemoryCount"] = noCandidateTownIds.Count,
                        ["pendingTownRecorded"] = pendingNoCandidateTownId is not null,
                        ["nativeCommandSent"] = checkpointClient is not null,
                        ["nativeStatus"] = checkpointClient is null ? "unsupported" : "completed"
                    });
                    pendingNoCandidateTownId = null;
                }

                var companionObjective = objective["companions"] as JsonObject
                    ?? throw new AgentHostException("companion-objective-missing", "The original EYC Journal omitted its Companion target.");
                var journalTargetMet = ReadBoolean(companionObjective, "met");
                if (journalTargetMet && gameState != "MissionState")
                    return BuildResult("completed", "native-companion-journal-target-met", null, null, state, journal, objective);
                var liveCompanions = ReadDouble(state["storyModeEstablishClan"]?["companions"] as JsonObject, "current");
                var journalTarget = ReadDouble(companionObjective, "target");
                var liveGoalAhead = (liveCompanions >= journalTarget && !double.IsNaN(journalTarget)) || (journalTargetMet && gameState == "MissionState");

                var location = state["location"] as JsonObject;
                var currentSettlementId = ReadString(location, "currentSettlementId");
                var targetSettlementId = ReadString(location, "targetSettlementId");
                var menuId = ReadString(context, "menuId");
                if (!journalTargetMet && liveGoalAhead && gameState == "MapState" && string.IsNullOrWhiteSpace(menuId))
                    return BuildResult("interrupted", "native-journal-refresh-pending", "The live Clan companion count has reached the Journal target, but the authoritative Journal has not refreshed; no second hire was attempted.", "companion-journal-refresh-pending", state, journal, objective);
                if (gameState == "MapState" && string.IsNullOrWhiteSpace(moveTargetId) &&
                    !string.IsNullOrWhiteSpace(targetSettlementId) && targetSettlementId != currentSettlementId &&
                    string.IsNullOrWhiteSpace(ReadString(location, "targetPartyId")) &&
                    ReadString(state["party"] as JsonObject, "defaultBehavior") == "GoToSettlement")
                {
                    moveTargetId = targetSettlementId;
                    moveStartPending = false;
                    trace.Add(new JsonObject
                    {
                        ["stage"] = "native-settlement-move-inherited-by-companion-route",
                        ["targetSettlementId"] = moveTargetId,
                        ["nativeActionSent"] = false,
                        ["modelDecisionSent"] = false
                    });
                }
                if (gameState == "MapState" && !string.IsNullOrWhiteSpace(moveTargetId) && string.Equals(currentSettlementId, moveTargetId, StringComparison.Ordinal))
                {
                    moveStartPending = false;
                    if (!string.IsNullOrWhiteSpace(menuId))
                    {
                        moveTargetId = null;
                        safeTowns = null;
                        sceneAgentsReceipt = null;
                        selectedHeroId = null;
                    }
                }
                if (gameState == "MissionState" && ReadConversation(state) is JsonObject conversation && ReadString(conversation, "heroId") is string conversationHeroId)
                    selectedHeroId = conversationHeroId;
                if (missionTransitionPending && (gameState != "MissionState" || state["mission"]?["leave"] is JsonObject leaveState && !ReadBoolean(leaveState, "active")))
                    missionTransitionPending = false;

                var nativeMoveActive = !string.IsNullOrWhiteSpace(moveTargetId) &&
                    (ReadBoolean(state["party"] as JsonObject, "isMoving") || string.Equals(targetSettlementId, moveTargetId, StringComparison.Ordinal));
                if (nativeMoveActive) moveStartPending = false;
                var mapConversationActive = IsMapStateConversation(state);
                var menuArrivalPending = !mapConversationActive && gameState == "MapState" && !string.IsNullOrWhiteSpace(moveTargetId) &&
                    string.Equals(currentSettlementId, moveTargetId, StringComparison.Ordinal) && string.IsNullOrWhiteSpace(menuId);
                var mapMovementPending = !mapConversationActive && gameState == "MapState" && !string.IsNullOrWhiteSpace(moveTargetId) &&
                    !string.Equals(currentSettlementId, moveTargetId, StringComparison.Ordinal) && (nativeMoveActive || moveStartPending);

                var movementNativeState = JsonNode.Parse(nativeState.RootElement.GetRawText())?.AsObject()
                    ?? throw new AgentHostException("companion-movement-state-invalid", "The current Native state could not be cloned for the stopped-move recovery check.");
                if (!sceneNotificationActive && AgentHostNativeMapMovementMonitor.IsStalledNativeSettlementMove(movementNativeState, moveTargetId))
                    return BuildResult("interrupted", "native-stalled-move-returned-by-companion", "The Native settlement move remains active while Campaign time is stopped; return it to the EYC parent for the existing bounded original-Move recovery.", "native-stalled-move-returned-by-companion", state, journal, objective);

                if (!sceneNotificationActive && mapMovementPending)
                {
                    // Native map movement normally selects StoppablePlay, but it may
                    // return Stop while the order still appears active. Yield that
                    // stalled state to the parent instead of spinning this poll loop.
                    // Watch Native visible Bandits during that natural travel. This is a
                    // bounded nearest-Town decision window: observe active Native movement
                    // During Native movement, do not spend a model decision or issue another move/time command.
                    var movementWatch = await AgentHostNativeMapMovementMonitor.WaitAsync(
                        campaignClient,
                        campaignClient as IAgentHostBattleSimulationNativeClient,
                        movementNativeState,
                        moveTargetId,
                        1,
                        monitorVisibleBandits: AgentHostNativeMapMovementMonitor.HasActiveEycQuest(movementNativeState),
                        elapsed.Token);
                    state = movementWatch.NativeState;
                    actionsExecuted += movementWatch.MapPartyTargetPollCount + (movementWatch.PauseReceipt is null ? 0 : 1);
                    trace.Add(new JsonObject
                    {
                        ["stage"] = movementWatch.InterruptedByVisibleHostileBandit ? AgentHostNativeMapMovementMonitor.FailureCode : "native-map-move-passive-observation",
                        ["targetSettlementId"] = moveTargetId,
                        ["mapPartyTargetPollCount"] = movementWatch.MapPartyTargetPollCount,
                        ["visibleHostileBanditTargets"] = movementWatch.VisibleHostileBanditTargets.DeepClone(),
                        ["nativePauseReceipt"] = movementWatch.PauseReceipt?.DeepClone(),
                        ["stateAfter"] = AgentHostHarnessProgressTrace.BuildNativeStateSummary(movementWatch.NativeReceipt)
                    });
                    if (movementWatch.InterruptedByVisibleHostileBandit)
                        return BuildResult("interrupted", AgentHostNativeMapMovementMonitor.FailureCode,
                            "A Native visible hostile Bandit interrupted Companion travel. The EYC parent must resolve the current map target before resuming the Companion route.",
                            AgentHostNativeMapMovementMonitor.FailureCode, state, journal, objective);
                    continue;
                }

                if (!sceneNotificationActive && menuArrivalPending)
                {
                    // Arrival and menu construction are Native transitions; wait for
                    // the original Town/Village menu without querying or steering it.
                    await Task.Delay(TimeSpan.FromSeconds(1), elapsed.Token);
                    continue;
                }

                var missionNavigationActive = gameState == "MissionState" && ReadBoolean(state["mission"]?["navigation"] as JsonObject, "active");
                var missionLeaveActive = gameState == "MissionState" && ReadBoolean(state["mission"]?["leave"] as JsonObject, "active");
                if (!sceneNotificationActive && (missionNavigationActive || missionLeaveActive || missionTransitionPending))
                {
                    // Native Mission navigation/Leave already owns the MainAgent or input context.
                    // Poll Native state passively; do not spend a remote model decision on observeAgain.
                    await Task.Delay(TimeSpan.FromSeconds(1), elapsed.Token);
                    missionWaitPending = true;
                    continue;
                }
                if (missionWaitPending)
                {
                    trace.Add(new JsonObject
                    {
                        ["stage"] = "native-mission-activity-ended",
                        ["gameState"] = gameState,
                        ["menuId"] = ReadString(context, "menuId"),
                        ["navigationActive"] = missionNavigationActive,
                        ["leaveActive"] = missionLeaveActive,
                        ["nativeActionSent"] = false
                    });
                    missionWaitPending = false;
                }
                var actionPending = !sceneNotificationActive && (mapMovementPending || menuArrivalPending || missionNavigationActive || missionLeaveActive || missionTransitionPending);
                var controls = BuildControlCatalog(gameState == "MapState", !sceneNotificationActive && (mapMovementPending || menuArrivalPending), missionNavigationActive, missionLeaveActive || missionTransitionPending,
                    AgentHostNativeMapMovementMonitor.IsCampaignTimeAdvancing(state));
                if (!liveGoalAhead && gameState == "MissionState" && IsNativeTavernMissionState(state) && ReadConversation(state) is null && sceneAgentsReceipt is null)
                {
                    using var sceneObservationResponse = await companionClient.ExecuteCompanionHiringActionAsync("missionSceneAgents", new JsonObject(), elapsed.Token);
                    var sceneObservationReceipt = JsonNode.Parse(sceneObservationResponse.RootElement.GetRawText())?.AsObject()
                        ?? throw new AgentHostException("companion-scene-observation-invalid", "Native returned no current Tavern scene roster receipt.");
                    if (ReadString(sceneObservationReceipt, "status") != "completed")
                        return BuildResult("failed", "companion-scene-observation-failed", "Native could not enumerate the current Tavern scene candidates; the Host did not ask the model to act on missing observation data.", "companion-scene-observation-failed", state, journal, objective);
                    sceneAgentsReceipt = sceneObservationReceipt.DeepClone() as JsonObject
                        ?? throw new AgentHostException("companion-scene-observation-invalid", "The current Tavern scene roster could not be retained for the next observation.");
                    ReconcileNavigationProgress(state, sceneAgentsReceipt);
                    var currentSceneCandidates = FilterWandererCandidates(sceneAgentsReceipt["data"]?["agents"] as JsonArray, excludedHeroes);
                    if (currentSceneCandidates.Count == 0 && !string.IsNullOrWhiteSpace(currentSettlementId))
                        pendingNoCandidateTownId = currentSettlementId;
                    else if (currentSceneCandidates.Count > 0 && !string.IsNullOrWhiteSpace(currentSettlementId) && noCandidateTownIds.Remove(currentSettlementId))
                    {
                        visitedTowns.Remove(currentSettlementId);
                        companionCheckpointDirty = true;
                    }
                    actionsExecuted++;
                    var sceneObservation = BuildObservation(state, journal, objective, safeTowns, sceneAgentsReceipt, selectedHeroId, interactTargetHeroId, trace.Count);
                    trace.Add(new JsonObject
                    {
                        ["decision"] = decisions,
                        ["observation"] = sceneObservation,
                        ["selectedDecision"] = null,
                        ["nativeReceipt"] = SafeReceipt(sceneObservationReceipt, "missionSceneAgents", null, null, safeTowns),
                        ["afterState"] = state.DeepClone(),
                        ["stepKind"] = "native-tavern-scene-observation",
                        ["modelDecisionSent"] = false,
                        ["worldChangingInputSent"] = false
                    });
                    if (currentSceneCandidates.Count == 0)
                    {
                        using var emptyTavernLeaveResponse = await companionClient.ExecuteCompanionHiringActionAsync("missionLeave", new JsonObject(), elapsed.Token);
                        var emptyTavernLeaveReceipt = JsonNode.Parse(emptyTavernLeaveResponse.RootElement.GetRawText())?.AsObject()
                            ?? throw new AgentHostException("companion-empty-tavern-leave-invalid", "Native returned no receipt for the only available action in an empty Tavern scene.");
                        if (ReadString(emptyTavernLeaveReceipt, "status") != "completed")
                            return BuildResult("failed", "companion-empty-tavern-leave-failed", "The current Native Tavern had no eligible Wanderer and its sole Native leave action was rejected.", "companion-empty-tavern-leave-failed", state, journal, objective);
                        actionsExecuted++;
                        missionTransitionPending = true;
                        selectedHeroId = null;
                        interactTargetHeroId = null;
                        sceneAgentsReceipt = null;
                        trace.Add(new JsonObject
                        {
                            ["decision"] = decisions,
                            ["observation"] = sceneObservation.DeepClone(),
                            ["selectedDecision"] = null,
                            ["nativeReceipt"] = SafeReceipt(emptyTavernLeaveReceipt, "missionLeave", null, null, safeTowns),
                            ["afterState"] = state.DeepClone(),
                            ["stepKind"] = "native-empty-tavern-leave",
                            ["modelDecisionSent"] = false,
                            ["worldChangingInputSent"] = true,
                            ["reason"] = "No eligible current Wanderer existed and missionLeave was the only Native action in the allowlisted catalog."
                        });
                    }
                    continue;
                }

                var catalog = BuildActionCatalog(state, journal, objective, safeTowns, sceneAgentsReceipt, selectedHeroId,
                    moveTargetId, actionPending, visitedTowns, excludedHeroes);
                if (liveGoalAhead && !sceneNotificationActive)
                {
                    catalog = gameState == "MissionState"
                        ? new JsonArray(new JsonObject { ["action"] = "missionLeave", ["arguments"] = new JsonArray() })
                        : BuildEnabledSettlementLeaveCatalog(state);
                }
                if (catalog.Count == 0 && controls.Count == 0)
                    return BuildResult("interrupted", "companion-route-unavailable", DescribeNoAction(state, safeTowns, sceneAgentsReceipt, journal), "companion-route-unavailable", state, journal, objective);

                var observation = BuildObservation(state, journal, objective, safeTowns, sceneAgentsReceipt, selectedHeroId, interactTargetHeroId, trace.Count);
                var modelRequest = new JsonObject
                {
                    ["runId"] = runId,
                    ["goal"] = ReadString(request, "goal"),
                    ["goalKind"] = "active-storymode-establish-clan-companion",
                    ["iteration"] = decisions + 1,
                    ["observation"] = observation,
                    ["allowedActions"] = catalog.DeepClone(),
                    ["allowedControls"] = controls.DeepClone(),
                    ["previousActionReceipt"] = trace.LastOrDefault() is JsonObject lastTrace ? lastTrace["nativeReceipt"]?.DeepClone() : null,
                    ["decisionFeedback"] = decisionFeedback?.DeepClone()
                };
                ProviderDecisionResult decision;
                try
                {
                    decision = await AgentHostDecisionCycle.DecideEstablishClanCompanionAsync(provider, modelRequest, elapsed.Token);
                }
                catch (AgentHostException exception) when (AgentHostProviderDecisionRecovery.CanRetry(exception.Code, rejectedProviderDecisions))
                {
                    decisions++;
                    rejectedProviderDecisions++;
                    decisionFeedback = AgentHostProviderDecisionRecovery.BuildFeedback(exception.Code, catalog, controls);
                    trace.Add(new JsonObject
                    {
                        ["iteration"] = decisions,
                        ["stage"] = "decision-rejected-before-native",
                        ["rejectionCode"] = exception.Code,
                        ["nativeActionSent"] = false,
                        ["allowedActionNames"] = AgentHostProviderDecisionRecovery.CurrentActionNames(catalog),
                        ["allowedControls"] = controls.DeepClone(),
                        ["feedback"] = decisionFeedback.DeepClone()
                    });
                    continue;
                }
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

                if (ReadBoolean(decision.Decision, "stop") && !controls.Any(control => control?.GetValue<string>() == "stop"))
                {
                    if (!AgentHostProviderDecisionRecovery.CanRetry("provider-control-unavailable", rejectedProviderDecisions))
                        return BuildResult("failed", "companion-stop-recovery-exhausted", "The model kept requesting a stop while still inside a Native Mission; no map replan was claimed.", "companion-stop-recovery-exhausted", state, journal, objective);
                    rejectedProviderDecisions++;
                    decisionFeedback = AgentHostProviderDecisionRecovery.BuildFeedback("provider-control-unavailable", catalog, controls);
                    trace.Add(BuildStep(decisions, observation, decision.Decision, null, state, "rejected",
                        new JsonObject { ["kind"] = "decision-rejected-before-native", ["message"] = decisionFeedback["requiredNextStep"]?.DeepClone() }));
                    continue;
                }
                rejectedProviderDecisions = 0;
                decisionFeedback = null;

                if (ReadBoolean(decision.Decision, "stop"))
                    return BuildResult("interrupted", "companion-model-stopped", ReadString(decision.Decision, "reason") ?? "The model safely stopped this Companion subgoal before another Native action.", "companion-model-stopped", state, journal, objective);

                if (AgentHostDecisionCycle.IsObserveAgainDecision(decision.Decision))
                {
                    if (!controls.Any(control => control?.GetValue<string>() == "observeAgain"))
                        throw new AgentHostException("companion-observe-not-allowed", "Passive observation is allowed only while Native movement/navigation/leave transition is active.");
                    var waitSeconds = ReadInt(decision.Decision, "waitSeconds", 0);
                    if (waitSeconds is < 1 or > 10) throw new AgentHostException("companion-observe-interval-invalid", "observeAgain requires a bounded 1-10 second host-side wait.");
                    rejectedActionDecisions = 0;
                    if (gameState == "MapState" && !string.IsNullOrWhiteSpace(moveTargetId))
                    {
                        var moveNative = JsonNode.Parse(nativeState.RootElement.GetRawText())?.AsObject()
                            ?? throw new AgentHostException("companion-movement-state-invalid", "The current Native Map observation could not be cloned for the hostile-party monitor.");
                        var movementWatch = await AgentHostNativeMapMovementMonitor.WaitAsync(
                            campaignClient,
                            campaignClient as IAgentHostBattleSimulationNativeClient,
                            moveNative,
                            moveTargetId,
                            waitSeconds,
                            monitorVisibleBandits: AgentHostNativeMapMovementMonitor.HasActiveEycQuest(moveNative),
                            elapsed.Token);
                        var waitedState = movementWatch.NativeState;
                        actionsExecuted += movementWatch.MapPartyTargetPollCount + (movementWatch.PauseReceipt is null ? 0 : 1);
                        var waitStep = BuildStep(decisions, observation, decision.Decision, null, waitedState,
                            movementWatch.InterruptedByVisibleHostileBandit ? AgentHostNativeMapMovementMonitor.FailureCode : "bounded-native-observation");
                        waitStep["movementMonitor"] = new JsonObject
                        {
                            ["mapPartyTargetPollCount"] = movementWatch.MapPartyTargetPollCount,
                            ["visibleHostileBanditTargets"] = movementWatch.VisibleHostileBanditTargets.DeepClone(),
                            ["nativePauseReceipt"] = movementWatch.PauseReceipt?.DeepClone()
                        };
                        trace.Add(waitStep);
                        if (movementWatch.InterruptedByVisibleHostileBandit)
                            return BuildResult("interrupted", AgentHostNativeMapMovementMonitor.FailureCode,
                                "A Native visible hostile Bandit interrupted Companion travel. The EYC parent must resolve the current map target before resuming the Companion route.",
                                AgentHostNativeMapMovementMonitor.FailureCode, waitedState, journal, objective);
                    }
                    else
                    {
                        await Task.Delay(TimeSpan.FromSeconds(waitSeconds), elapsed.Token);
                        using var afterWait = await campaignClient.ReadStateAsync(elapsed.Token);
                        var waitedState = ReadState(afterWait.RootElement);
                        trace.Add(BuildStep(decisions, observation, decision.Decision, null, waitedState, "bounded-native-observation"));
                    }
                    continue;
                }

                if (!TryResolveAction(decision.Decision, catalog, state, sceneAgentsReceipt, selectedHeroId, moveTargetId,
                        actionPending,
                        out var action, out var arguments, out var selectedSettlementId, out var targetHeroId, out var rejection))
                {
                    rejectedActionDecisions++;
                    decisionFeedback = AgentHostProviderDecisionRecovery.BuildFeedback("provider-action-unavailable", catalog, controls);
                    if (ReadString(decision.Decision, "action") == "missionNavigateToAgent" &&
                        rejection.StartsWith("Native navigation requires current listed AgentIndex and DurationSeconds values:", StringComparison.Ordinal))
                        decisionFeedback["requiredNextStep"] = rejection;
                    trace.Add(BuildStep(decisions, observation, decision.Decision, null, state, "rejected",
                        new JsonObject
                        {
                            ["kind"] = "decision-rejected-before-native",
                            ["message"] = rejection,
                            ["nativeActionSent"] = false,
                            ["recovery"] = decisionFeedback.DeepClone()
                        }));
                    if (!AgentHostProviderDecisionRecovery.CanRetry("provider-action-unavailable", rejectedActionDecisions))
                        return BuildResult("failed", "companion-action-recovery-exhausted", "The model repeatedly selected a Companion action that did not match the current Native catalog; no Native action was sent.", "companion-action-recovery-exhausted", state, journal, objective);
                    continue;
                }
                rejectedActionDecisions = 0;

                JsonDocument response;
                var actionStarted = DateTime.UtcNow.ToString("O");
                if (action is "mapSettlementTargets" or "move" or "continueSceneNotification")
                    response = await campaignClient.ExecuteCampaignActionAsync(action, arguments, elapsed.Token);
                else
                    response = await companionClient.ExecuteCompanionHiringActionAsync(action, arguments, elapsed.Token);
                using (response)
                {
                    var receipt = JsonNode.Parse(response.RootElement.GetRawText())?.AsObject()
                        ?? throw new AgentHostException("companion-native-response-invalid", "Native returned no Companion action receipt.");
                    if (ReadString(receipt, "status") != "completed")
                    {
                        trace.Add(BuildStep(decisions, observation, decision.Decision, SafeReceipt(receipt, action, selectedSettlementId, targetHeroId, safeTowns), state, actionStarted));
                        continue;
                    }
                    actionsExecuted++;
                    if (action == "mapSettlementTargets")
                    {
                        safeTowns = FilterSafeTowns(receipt["data"]?["mapSettlementTargets"] as JsonArray, currentSettlementId, visitedTowns);
                        sceneAgentsReceipt = null;
                    }
                    else if (action == "move")
                    {
                        // Keep the newly selected Native target. targetSettlementId is the
                        // target from the pre-action observation and may still be null here.
                        moveTargetId = selectedSettlementId;
                        moveStartPending = true;
                        safeTowns = null;
                        sceneAgentsReceipt = null;
                    }
                    else if (action == "menuSelect")
                    {
                        var selectedOption = ReadString(arguments, "optionId");
                        if (selectedOption == "town_tavern" && currentSettlementId is not null)
                        {
                            tavernEntryTransitionPending = true;
                            pendingTavernEntrySettlementId = currentSettlementId;
                            tavernEntryTransitionWaits = 0;
                            selectedHeroId = null;
                            sceneAgentsReceipt = null;
                        }
                        else if (currentSettlementId is not null && (ReadString(context, "menuId") is "town" or "town_backstreet") &&
                                 state["availableMenuOptions"] is JsonArray currentOptions && currentOptions.OfType<JsonObject>().Any(option =>
                                     ReadString(option, "id") == selectedOption && ReadBoolean(option, "isLeave")))
                            visitedTowns.Add(currentSettlementId);
                    }
                    else if (action == "missionSceneAgents")
                    {
                        sceneAgentsReceipt = receipt.DeepClone() as JsonObject;
                        ReconcileNavigationProgress(state, sceneAgentsReceipt);
                    }
                    else if (action == "missionNavigateToAgent")
                    {
                        selectedHeroId = targetHeroId;
                        navigationProgressTargetHeroId = targetHeroId;
                        navigationProgressStartDistance = FindWandererDistance(sceneAgentsReceipt, targetHeroId);
                        sceneAgentsReceipt = null;
                    }
                    else if (action == "missionInteract")
                    {
                        selectedHeroId = targetHeroId;
                        interactTargetHeroId = targetHeroId;
                        sceneAgentsReceipt = null;
                    }
                    else if (action == "missionLeave")
                    {
                        missionTransitionPending = true;
                        selectedHeroId = null;
                        interactTargetHeroId = null;
                        sceneAgentsReceipt = null;
                    }
                    else if (action == "dialogueSelect" && !IsMapStateConversation(state))
                    {
                        var selectedDialogueOption = ReadString(arguments, "optionId");
                        var currentConversationHeroId = ReadString(ReadConversation(state), "heroId") ?? selectedHeroId;
                        if (selectedDialogueOption == "player_companion_hire_response_2" || selectedDialogueOption == "player_companion_hire_response_1")
                        {
                            if (!string.IsNullOrWhiteSpace(currentConversationHeroId)) excludedHeroes.Add(currentConversationHeroId);
                        }
                        if (RecordUnaffordableNativeResponse(unaffordableHeroGold, excludedHeroes, state, action, selectedDialogueOption ?? string.Empty))
                        {
                            unaffordableCheckpointDirty = true;
                        }
                        if (selectedDialogueOption is "player_companion_hire_response_2" or "player_is_leaving_neutral_or_friendly")
                        {
                            selectedHeroId = null;
                            interactTargetHeroId = null;
                            sceneAgentsReceipt = null;
                        }
                    }

                    using var refreshed = await campaignClient.ReadStateAsync(elapsed.Token);
                    var afterState = ReadState(refreshed.RootElement);
                    trace.Add(BuildStep(decisions, observation, decision.Decision, SafeReceipt(receipt, action, selectedSettlementId, targetHeroId, safeTowns), afterState, actionStarted));
                }
            }

            using var lastState = await campaignClient.ReadStateAsync(elapsed.Token);
            var currentState = ReadState(lastState.RootElement);
            var finalJournal = await ReadJournalAsync(companionClient, elapsed.Token);
            var finalSnapshot = AgentHostEstablishYourClanGoalLoop.BuildObjectiveSnapshot(finalJournal);
            return BuildResult("failed", "decision-budget-exhausted", "The bounded Native Companion route did not refresh the Journal target before its decision budget ended.", "companion-decision-budget-exhausted", currentState, finalJournal, finalSnapshot);
        }
        catch (OperationCanceledException)
        {
            return BuildResult("failed", "host-stop-or-time-budget", cancellationToken.IsCancellationRequested ? "Host stop signal ended Companion hiring without claiming Journal completion." : "The bounded Companion objective exceeded its elapsed-time limit.",
                cancellationToken.IsCancellationRequested ? "host-stop-requested" : "companion-timeout", null);
        }
        catch (AgentHostException exception)
        {
            return BuildResult("failed", "companion-loop-failed", exception.Message, exception.Code, null);
        }
        catch (Exception exception)
        {
            return BuildResult("failed", "companion-loop-failed", exception.GetType().Name, "companion-unexpected-error", null);
        }

        JsonObject BuildResult(string status, string reason, string? failure, string? failureCode, JsonObject? finalState,
            JsonArray? journal = null, JsonObject? objective = null)
        {
            return new JsonObject
            {
                ["status"] = status,
                ["resultKind"] = "establish-clan-companion-hiring-subgoal",
                ["runId"] = runId,
                ["providerModelId"] = provider.ModelId,
                ["providerConfigurationSource"] = provider.ConfigurationSource,
                ["tavernEntryTransitionSummary"] = new JsonObject
                {
                    ["waitCount"] = totalTavernEntryTransitionWaits,
                    ["confirmedCount"] = tavernEntryTransitionConfirmedCount,
                    ["pending"] = tavernEntryTransitionPending,
                    ["visitedTownMarked"] = pendingTavernEntrySettlementId is null && tavernEntryTransitionConfirmedCount > 0
                },
                ["companionSearchMemory"] = new JsonObject
                {
                    ["checkpointReadAttempted"] = checkpointClient is not null,
                    ["noCandidateTownCount"] = noCandidateTownIds.Count,
                    ["memoryMatchedCurrentJournal"] = memoryMatchedCurrentJournal,
                    ["memoryInvalidatedByJournalProgress"] = memoryInvalidatedByJournalProgress,
                    ["memoryReusedAfterJournalDecrease"] = memoryReusedAfterJournalDecrease,
                    ["unaffordableHeroCount"] = unaffordableHeroGold.Count,
                    ["checkpointWriteCount"] = checkpointWriteCount,
                    ["lastCheckpointWriteStatus"] = lastCheckpointWriteStatus
                },
                ["decisions"] = decisions,
                ["actionsExecuted"] = actionsExecuted,
                ["promptTokens"] = promptTokens,
                ["completionTokens"] = completionTokens,
                ["elapsedSeconds"] = Math.Round(Stopwatch.GetElapsedTime(start).TotalSeconds, 3),
                ["providerRouteHistory"] = routes.DeepClone(),
                ["trace"] = trace.DeepClone(),
                ["currentCompanionCount"] = finalState?["storyModeEstablishClan"]?["companions"]?["current"]?.DeepClone(),
                ["journalObjectiveSnapshot"] = journal?.DeepClone(),
                ["objectiveSnapshot"] = objective?.DeepClone(),
                ["termination"] = new JsonObject
                {
                    ["reason"] = reason,
                    ["goalVerified"] = ReadBoolean(objective?["companions"] as JsonObject, "met"),
                    ["completedByProvider"] = false
                },
                ["failure"] = failure,
                ["failureCode"] = failureCode
            };
        }
    }

    private static bool IsNativeTavernMissionState(JsonObject state)
    {
        var context = state["context"] as JsonObject;
        var mission = state["mission"] as JsonObject;
        var location = state["location"] as JsonObject;
        var currentSettlementId = ReadString(location, "currentSettlementId");
        return ReadString(context, "gameState") == "MissionState" &&
               ReadBoolean(mission, "active") &&
               !string.IsNullOrWhiteSpace(ReadString(mission, "sceneName")) &&
               ReadString(mission, "sceneName")!.Contains("tavern", StringComparison.OrdinalIgnoreCase) &&
               !string.IsNullOrWhiteSpace(currentSettlementId) &&
               string.Equals(ReadString(context, "encounteredPartyId"), currentSettlementId, StringComparison.Ordinal);
    }

    private static JsonArray BuildActionCatalog(JsonObject state, JsonArray journal, JsonObject objective, JsonArray? safeTowns,
        JsonObject? sceneAgentsReceipt, string? selectedHeroId, string? moveTargetId, bool pending,
        HashSet<string> visitedTowns, HashSet<string> excludedHeroes)
    {
        var catalog = new JsonArray();
        var context = state["context"] as JsonObject;
        var gameState = ReadString(context, "gameState");
        var sceneNotification = context?["sceneNotification"] as JsonObject;
        if (ReadBoolean(sceneNotification, "hasActiveNotification"))
        {
            if (!pending && gameState == "MapState" && ReadBoolean(sceneNotification, "canContinue"))
                catalog.Add(new JsonObject { ["action"] = "continueSceneNotification", ["arguments"] = new JsonArray() });
            return catalog;
        }
        var mapConversationActive = IsMapStateConversation(state);
        if ((pending && !mapConversationActive) || ReadBoolean(context, "inquiryOpen") || ReadBoolean(context, "escapeMenuOpen") ||
            (AgentHostCampaignStateFacts.IsActiveEncounter(state) && !IsNativeTavernMissionState(state)) ||
            ReadBoolean(context?["captivity"] as JsonObject, "isCaptive")) return catalog;

        if (mapConversationActive)
            return BuildMapConversationActionCatalog(state);

        if (gameState == "MapState")
        {
            var menuId = ReadString(context, "menuId");
            var options = state["availableMenuOptions"] as JsonArray ?? new JsonArray();
            if (!string.IsNullOrWhiteSpace(menuId))
            {
                var currentTown = ReadString(state["location"] as JsonObject, "currentSettlementId");
                string? desiredOption = null;
                if (menuId == "town" && currentTown is not null && !visitedTowns.Contains(currentTown)) desiredOption = "town_backstreet";
                else if (menuId == "town_backstreet" && currentTown is not null && !visitedTowns.Contains(currentTown)) desiredOption = "town_tavern";
                if (desiredOption is not null && options.OfType<JsonObject>().Any(option => ReadString(option, "id") == desiredOption && ReadBoolean(option, "available") && ReadBoolean(option, "enabled")))
                    catalog.Add(MenuAction(menuId, desiredOption));
                else AddEnabledLeaveAction(catalog, menuId, options);
                return catalog;
            }
            if (string.IsNullOrWhiteSpace(moveTargetId) && safeTowns is null)
                catalog.Add(new JsonObject { ["action"] = "mapSettlementTargets", ["arguments"] = new JsonArray() });
            else if (string.IsNullOrWhiteSpace(moveTargetId) && safeTowns?.Count > 0)
            {
                var visibleTowns = BuildSafeTownDecisionWindow(safeTowns);
                var action = new JsonObject { ["action"] = "move", ["arguments"] = new JsonArray("SettlementId") };
                action["argumentValues"] = new JsonObject { ["SettlementId"] = new JsonArray(visibleTowns.OfType<JsonObject>()
                    .Select(town => (JsonNode?)JsonValue.Create(ReadString(town, "id"))).ToArray()) };
                catalog.Add(action);
            }
            return catalog;
        }

        if (gameState != "MissionState") return catalog;
        var conversation = ReadConversation(state);
        if (conversation is not null)
        {
            var currentOptions = conversation["options"] as JsonArray ?? new JsonArray();
            var currentConversationHeroId = ReadString(conversation, "heroId");
            var currentConversationHeroDeclined = currentConversationHeroId is not null && excludedHeroes.Contains(currentConversationHeroId);
            var allowedOptions = currentOptions.OfType<JsonObject>()
                .Where(option => HiringDialogueOptions.Contains(ReadString(option, "id") ?? string.Empty) && ReadBoolean(option, "clickable") &&
                    (!currentConversationHeroDeclined || ReadString(option, "id") == "player_is_leaving_neutral_or_friendly"))
                .Select(option => ReadString(option, "id"))
                .Where(id => !string.IsNullOrWhiteSpace(id)).Distinct(StringComparer.Ordinal).ToArray();
            if (allowedOptions.Length > 0)
            {
                catalog.Add(new JsonObject
                {
                    ["action"] = "dialogueSelect",
                    ["arguments"] = new JsonArray("OptionId"),
                    ["argumentValues"] = new JsonObject { ["OptionId"] = new JsonArray(allowedOptions.Select(id => (JsonNode?)JsonValue.Create(id)).ToArray()) }
                });
            }
            else if (!currentOptions.OfType<JsonObject>().Any(option => ReadBoolean(option, "clickable")))
                catalog.Add(new JsonObject { ["action"] = "dialogueContinue", ["arguments"] = new JsonArray() });
            else catalog.Add(new JsonObject { ["action"] = "missionLeave", ["arguments"] = new JsonArray() });
            return catalog;
        }

        var candidates = FilterWandererCandidates(sceneAgentsReceipt?["data"]?["agents"] as JsonArray, excludedHeroes);
        if (!string.IsNullOrWhiteSpace(selectedHeroId))
        {
            var selected = candidates.OfType<JsonObject>().Where(candidate => ReadString(candidate, "heroId") == selectedHeroId).ToArray();
            if (selected.Length > 0) candidates = new JsonArray(selected.Select(candidate => (JsonNode?)candidate.DeepClone()).ToArray());
            else selectedHeroId = null;
        }
        if (sceneAgentsReceipt is null)
        {
            catalog.Add(new JsonObject { ["action"] = "missionSceneAgents", ["arguments"] = new JsonArray() });
            return catalog;
        }
        if (candidates.Count == 0)
        {
            catalog.Add(new JsonObject { ["action"] = "missionLeave", ["arguments"] = new JsonArray() });
            return catalog;
        }

        var localAgents = state["mission"]?["nearbySceneAgents"] as JsonArray ?? new JsonArray();
        var nearbyInteractable = candidates.OfType<JsonObject>().Where(candidate => ReadBoolean(candidate, "nativeConversationActionAvailable") &&
            localAgents.OfType<JsonObject>().Any(local => ReadString(local, "heroId") == ReadString(candidate, "heroId") && ReadBoolean(local, "isInteractable"))).ToArray();
        if (nearbyInteractable.Length > 0)
        {
            var indexes = nearbyInteractable.Select(candidate => (JsonNode?)JsonValue.Create(ReadInt(candidate, "agentIndex", -1))).Where(node => node is not null).ToArray();
            catalog.Add(new JsonObject
            {
                ["action"] = "missionInteract",
                ["arguments"] = new JsonArray("AgentIndex"),
                ["argumentValues"] = new JsonObject { ["AgentIndex"] = new JsonArray(indexes) },
                ["candidateHeroes"] = new JsonArray(nearbyInteractable.Select(candidate => (JsonNode?)new JsonObject { ["heroId"] = ReadString(candidate, "heroId"), ["name"] = ReadString(candidate, "name"), ["agentIndex"] = ReadInt(candidate, "agentIndex", -1), ["distance"] = ReadDouble(candidate, "distance") }).ToArray())
            });
            catalog.Add(new JsonObject { ["action"] = "missionLeave", ["arguments"] = new JsonArray() });
            return catalog;
        }

        var targets = candidates.OfType<JsonObject>().ToArray();
        catalog.Add(new JsonObject
        {
            ["action"] = "missionNavigateToAgent",
            ["arguments"] = new JsonArray("AgentIndex", "DurationSeconds"),
            ["argumentValues"] = new JsonObject
            {
                ["AgentIndex"] = new JsonArray(targets.Select(candidate => (JsonNode?)JsonValue.Create(ReadInt(candidate, "agentIndex", -1))).ToArray()),
                ["DurationSeconds"] = new JsonArray(8, 20)
            },
            ["candidateHeroes"] = new JsonArray(targets.Select(candidate => (JsonNode?)new JsonObject { ["heroId"] = ReadString(candidate, "heroId"), ["name"] = ReadString(candidate, "name"), ["agentIndex"] = ReadInt(candidate, "agentIndex", -1), ["distance"] = ReadDouble(candidate, "distance") }).ToArray())
        });
        catalog.Add(new JsonObject { ["action"] = "missionLeave", ["arguments"] = new JsonArray() });
        return catalog;
    }

    private static bool TryResolveAction(JsonObject? decision, JsonArray catalog, JsonObject state, JsonObject? sceneAgentsReceipt,
        string? selectedHeroId, string? moveTargetId, bool pending, out string action, out JsonObject arguments,
        out string? targetSettlementId, out string? targetHeroId, out string rejection)
    {
        action = string.Empty;
        arguments = new JsonObject();
        targetSettlementId = null;
        targetHeroId = null;
        rejection = "Choose one action from the current Native Companion catalog with its exact listed arguments.";
        var requestedAction = ReadString(decision, "action");
        var supplied = decision?["arguments"] as JsonObject;
        var listed = requestedAction is null ? null : catalog.OfType<JsonObject>().FirstOrDefault(item => ReadString(item, "action") == requestedAction);
        if (listed is null || requestedAction is null || supplied is null || pending) return false;
        var argumentNames = listed["arguments"] as JsonArray ?? new JsonArray();
        if (argumentNames.Count != supplied.Count || argumentNames.Any(name => name?.GetValue<string>() is not string key || !supplied.ContainsKey(key)))
            return false;
        action = requestedAction;
        switch (action)
        {
            case "mapSettlementTargets" when supplied.Count == 0:
            case "missionSceneAgents" when supplied.Count == 0:
            case "missionLeave" when supplied.Count == 0:
                return true;
            case "dialogueContinue":
            {
                var conversation = ReadConversation(state);
                var options = conversation?["options"] as JsonArray;
                if (supplied.Count != 0 || conversation is null || options?.OfType<JsonObject>().Any(option => ReadBoolean(option, "clickable")) == true)
                    return false;
                if (IsMapStateConversation(state) && string.IsNullOrWhiteSpace(ReadString(conversation, "sentenceText"))) return false;
                if (ReadString(state["context"] as JsonObject, "gameState") is not ("MapState" or "MissionState")) return false;
                return true;
            }
            case "continueSceneNotification" when supplied.Count == 0 &&
                                                   ReadBoolean(state["context"]?["sceneNotification"] as JsonObject, "hasActiveNotification") &&
                                                   ReadBoolean(state["context"]?["sceneNotification"] as JsonObject, "canContinue"):
                return true;
            case "move":
                var requestedSettlementId = ReadString(supplied, "SettlementId");
                targetSettlementId = requestedSettlementId;
                if (requestedSettlementId is null || listed["argumentValues"]?["SettlementId"]?.AsArray().Any(value => value?.GetValue<string>() == requestedSettlementId) != true ||
                    ReadString(state["location"] as JsonObject, "currentSettlementId") == requestedSettlementId) return false;
                arguments["settlementId"] = requestedSettlementId;
                return true;
            case "menuSelect":
                var menuId = ReadString(supplied, "MenuId");
                var optionId = ReadString(supplied, "OptionId");
                if (menuId != ReadString(state["context"] as JsonObject, "menuId") || optionId is null ||
                    !listed["argumentValues"]?["OptionId"]?.AsArray().Any(value => value?.GetValue<string>() == optionId) == true ||
                    !listed["argumentValues"]?["MenuId"]?.AsArray().Any(value => value?.GetValue<string>() == menuId) == true) return false;
                arguments["menuId"] = menuId;
                arguments["optionId"] = optionId;
                return true;
            case "missionNavigateToAgent":
            case "missionInteract":
                if (!TryReadListedInteger(supplied["AgentIndex"], listed["argumentValues"]?["AgentIndex"] as JsonArray, out var agentIndex)) return false;
                var candidate = (sceneAgentsReceipt?["data"]?["agents"] as JsonArray)?.OfType<JsonObject>().FirstOrDefault(item => ReadInt(item, "agentIndex", -1) == agentIndex &&
                    ReadString(item, "occupation") == "Wanderer" && !ReadBoolean(item, "isEnemy") && !ReadBoolean(item, "isNotable") && !string.IsNullOrWhiteSpace(ReadString(item, "heroId")));
                var currentConversationHero = ReadString(ReadConversation(state), "heroId");
                if (candidate is null || (selectedHeroId is not null && ReadString(candidate, "heroId") != selectedHeroId) || currentConversationHero is not null) return false;
                targetHeroId = ReadString(candidate, "heroId");
                arguments["agentIndex"] = agentIndex;
                if (action == "missionNavigateToAgent")
                {
                    var allowedDurations = listed["argumentValues"]?["DurationSeconds"] as JsonArray;
                    if (!TryReadListedInteger(supplied["DurationSeconds"], allowedDurations, out var duration))
                    {
                        var allowedIndexes = string.Join(", ", ((listed["argumentValues"]?["AgentIndex"] as JsonArray)?.OfType<JsonValue>() ?? Enumerable.Empty<JsonValue>())
                            .Select(value => value.TryGetValue<int>(out var index) ? index.ToString(CultureInfo.InvariantCulture) : null).Where(value => value is not null));
                        var allowedDurationValues = string.Join(", ", (allowedDurations?.OfType<JsonValue>() ?? Enumerable.Empty<JsonValue>())
                            .Select(value => value.TryGetValue<int>(out var seconds) ? seconds.ToString(CultureInfo.InvariantCulture) : null).Where(value => value is not null));
                        rejection = $"Native navigation requires current listed AgentIndex and DurationSeconds values: AgentIndex [{allowedIndexes}], DurationSeconds [{allowedDurationValues}]. Use one exact listed pair; no Native action was sent.";
                        return false;
                    }
                    arguments["durationSeconds"] = duration;
                }
                else if (!(state["mission"]?["nearbySceneAgents"] as JsonArray)?.OfType<JsonObject>().Any(local => ReadInt(local, "agentIndex", -1) == agentIndex && ReadBoolean(local, "isInteractable")) == true)
                    return false;
                return true;
            case "dialogueSelect":
            {
                var currentOptions = ReadConversation(state)?["options"] as JsonArray;
                var selectedOption = ReadString(supplied, "OptionId");
                var isMapConversation = IsMapStateConversation(state);
                if (selectedOption is null || (!isMapConversation && !HiringDialogueOptions.Contains(selectedOption)) ||
                    !listed["argumentValues"]?["OptionId"]?.AsArray().Any(value => value?.GetValue<string>() == selectedOption) == true ||
                    !currentOptions?.OfType<JsonObject>().Any(option => ReadString(option, "id") == selectedOption && ReadBoolean(option, "clickable")) == true) return false;
                arguments["optionId"] = selectedOption;
                if (isMapConversation) return true;
                targetHeroId = ReadString(ReadConversation(state), "heroId");
                return targetHeroId is not null;
            }
            default:
                return false;
        }
    }

    private static bool TryReadListedInteger(JsonNode? supplied, JsonArray? allowedValues, out int result)
    {
        result = -1;
        if (supplied is not JsonValue suppliedValue) return false;
        if (!suppliedValue.TryGetValue<int>(out result))
        {
            if (!suppliedValue.TryGetValue<string>(out var text) || string.IsNullOrWhiteSpace(text)) return false;
            text = text.Trim();
            if (text.Length >= 2 && text.StartsWith("[", StringComparison.Ordinal) && text.EndsWith("]", StringComparison.Ordinal))
                text = text[1..^1].Trim();
            else if (text.Length >= 4 && text.StartsWith("**", StringComparison.Ordinal) && text.EndsWith("**", StringComparison.Ordinal))
                text = text[2..^2].Trim();
            else if (text.Length >= 2 && text.StartsWith("`", StringComparison.Ordinal) && text.EndsWith("`", StringComparison.Ordinal))
                text = text[1..^1].Trim();

            if (!int.TryParse(text, NumberStyles.None, CultureInfo.InvariantCulture, out result)) return false;
        }

        var parsedValue = result;
        return allowedValues?.OfType<JsonValue>().Any(value => value.TryGetValue<int>(out var allowed) && allowed == parsedValue) == true;
    }

    private static double? FindWandererDistance(JsonObject? receipt, string? heroId)
    {
        if (string.IsNullOrWhiteSpace(heroId) || receipt?["data"]?["agents"] is not JsonArray agents) return null;
        var candidate = agents.OfType<JsonObject>().FirstOrDefault(agent => ReadString(agent, "heroId") == heroId);
        return candidate is null ? null : ReadDouble(candidate, "distance");
    }

    private static JsonObject? ReadConversation(JsonObject? state) => state?["context"]?["conversation"] as JsonObject;

    private static bool IsMapStateConversation(JsonObject? state) =>
        ReadString(state?["context"] as JsonObject, "gameState") == "MapState" && ReadConversation(state) is not null;

    private static JsonArray BuildMapConversationActionCatalog(JsonObject state)
    {
        var conversation = ReadConversation(state);
        if (conversation is null) return new JsonArray();
        var options = conversation["options"] as JsonArray ?? new JsonArray();
        var clickableIds = options.OfType<JsonObject>()
            .Where(option => ReadBoolean(option, "clickable"))
            .Select(option => ReadString(option, "id"))
            .Where(id => !string.IsNullOrWhiteSpace(id))
            .Distinct(StringComparer.Ordinal)
            .Cast<string>()
            .ToArray();
        if (clickableIds.Length > 0)
            return [new JsonObject
            {
                ["action"] = "dialogueSelect",
                ["arguments"] = new JsonArray("OptionId"),
                ["argumentValues"] = new JsonObject { ["OptionId"] = new JsonArray(clickableIds.Select(id => (JsonNode?)JsonValue.Create(id)).ToArray()) }
            }];
        if (options.Count == 0 && !string.IsNullOrWhiteSpace(ReadString(conversation, "sentenceText")))
            return [new JsonObject { ["action"] = "dialogueContinue", ["arguments"] = new JsonArray() }];
        return new JsonArray();
    }

    private static bool IsWandererInteractable(JsonObject? state, string? heroId) =>
        !string.IsNullOrWhiteSpace(heroId) &&
        (state?["mission"]?["nearbySceneAgents"] as JsonArray)?.OfType<JsonObject>().Any(agent =>
            ReadString(agent, "heroId") == heroId && ReadBoolean(agent, "isInteractable")) == true;

    internal static (int Attempts, bool ExcludeTarget) EvaluateNavigationNoProgress(double? startDistance, double? observedDistance,
        int previousAttempts, bool isInteractable)
    {
        if (isInteractable || !startDistance.HasValue || !observedDistance.HasValue ||
            observedDistance.Value <= startDistance.Value - MinimumCompanionNavigationProgressDistance)
            return (0, false);
        var attempts = Math.Max(0, previousAttempts) + 1;
        return (attempts, attempts >= MaxCompanionNavigationNoProgressAttempts);
    }

    private static JsonArray FilterWandererCandidates(JsonArray? agents, HashSet<string> excludedHeroes)
    {
        var result = new JsonArray();
        if (agents is null) return result;
        foreach (var agent in agents.OfType<JsonObject>())
        {
            var id = ReadString(agent, "heroId");
            if (string.IsNullOrWhiteSpace(id) || ReadString(agent, "occupation") != "Wanderer" || ReadBoolean(agent, "isNotable") ||
                ReadBoolean(agent, "isEnemy") || excludedHeroes.Contains(id)) continue;
            result.Add(agent.DeepClone());
        }
        return result;
    }

    internal static bool RecordUnaffordableNativeResponse(Dictionary<string, int> unaffordableHeroGold,
        HashSet<string> excludedHeroes, JsonObject? currentState, string action, string optionId)
    {
        var conversationHeroId = ReadString(ReadConversation(currentState), "heroId");
        var goldAtRefusal = ReadInt(currentState?["economy"] as JsonObject, "gold", -1);
        if (!AgentHostEycCompanionSearchMemory.RecordUnaffordableHeroGold(
                unaffordableHeroGold, action, optionId, conversationHeroId, goldAtRefusal))
            return false;
        excludedHeroes.Add(conversationHeroId!);
        return true;
    }

    private static JsonArray FilterSafeTowns(JsonArray? targets, string? currentSettlementId, HashSet<string> visited)
    {
        var result = new JsonArray();
        if (targets is null) return result;
        foreach (var target in targets.OfType<JsonObject>())
        {
            var id = ReadString(target, "id");
            if (string.IsNullOrWhiteSpace(id) || ReadString(target, "type") != "town" || id == currentSettlementId || visited.Contains(id) ||
                ReadBoolean(target, "hostile") || ReadBoolean(target, "underSiege")) continue;
            result.Add(target.DeepClone());
        }
        return result;
    }

    private static JsonObject MenuAction(string menuId, string optionId) => new()
    {
        ["action"] = "menuSelect",
        ["arguments"] = new JsonArray("MenuId", "OptionId"),
        ["argumentValues"] = new JsonObject { ["MenuId"] = new JsonArray(menuId), ["OptionId"] = new JsonArray(optionId) }
    };

    private static void AddEnabledLeaveAction(JsonArray catalog, string menuId, JsonArray options)
    {
        var leaveIds = options.OfType<JsonObject>().Where(option => ReadBoolean(option, "available") && ReadBoolean(option, "enabled") && ReadBoolean(option, "isLeave"))
            .Select(option => ReadString(option, "id")).Where(id => !string.IsNullOrWhiteSpace(id)).Cast<string>().ToArray();
        if (leaveIds.Length == 0) return;
        catalog.Add(new JsonObject
        {
            ["action"] = "menuSelect",
            ["arguments"] = new JsonArray("MenuId", "OptionId"),
            ["argumentValues"] = new JsonObject { ["MenuId"] = new JsonArray(menuId), ["OptionId"] = new JsonArray(leaveIds.Select(id => (JsonNode?)JsonValue.Create(id)).ToArray()) }
        });
    }

    private static JsonArray BuildEnabledSettlementLeaveCatalog(JsonObject state)
    {
        var menuId = ReadString(state["context"] as JsonObject, "menuId");
        var options = state["availableMenuOptions"] as JsonArray ?? new JsonArray();
        var catalog = new JsonArray();
        if (string.IsNullOrWhiteSpace(menuId)) return catalog;
        AddEnabledLeaveAction(catalog, menuId, options);
        return catalog;
    }

    private static JsonArray BuildControlCatalog(bool allowStop, bool mapMovementPending, bool missionNavigationActive, bool missionLeaveActive, bool mapMovementTimeAdvancing)
    {
        var controls = new JsonArray();
        if (allowStop) controls.Add("stop");
        if (mapMovementPending && mapMovementTimeAdvancing || missionNavigationActive || missionLeaveActive) controls.Add("observeAgain");
        return controls;
    }

    private static JsonObject BuildObservation(JsonObject state, JsonArray journal, JsonObject objective, JsonArray? safeTowns,
        JsonObject? sceneAgentsReceipt, string? selectedHeroId, string? interactTargetHeroId, int traceCount)
    {
        var projectedState = state.DeepClone() as JsonObject ?? new JsonObject();
        projectedState.Remove("mainHeroSkills");
        if (projectedState["mission"] is JsonObject projectedMission)
            projectedMission.Remove("nearbySceneAgents");
        var sceneCandidates = FilterWandererCandidates(sceneAgentsReceipt?["data"]?["agents"] as JsonArray, new HashSet<string>(StringComparer.Ordinal));
        var compactCandidates = new JsonArray(sceneCandidates.OfType<JsonObject>().Select(candidate => (JsonNode?)new JsonObject
        {
            ["agentIndex"] = ReadInt(candidate, "agentIndex", -1),
            ["heroId"] = ReadString(candidate, "heroId"),
            ["name"] = ReadString(candidate, "name"),
            ["occupation"] = ReadString(candidate, "occupation"),
            ["distance"] = ReadDouble(candidate, "distance")
        }).ToArray());
        var nearby = state["mission"]?["nearbySceneAgents"] as JsonArray ?? new JsonArray();
        var nearbyCandidates = new JsonArray(nearby.OfType<JsonObject>()
            .Where(agent => ReadString(agent, "occupation") == "Wanderer" && ReadBoolean(agent, "isNotable") == false && !ReadBoolean(agent, "isEnemy"))
            .Select(agent => (JsonNode?)new JsonObject
            {
                ["agentIndex"] = ReadInt(agent, "agentIndex", -1),
                ["heroId"] = ReadString(agent, "heroId"),
                ["name"] = ReadString(agent, "name"),
                ["distance"] = ReadDouble(agent, "distance"),
                ["isInteractable"] = ReadBoolean(agent, "isInteractable")
            }).ToArray());
        return new JsonObject
        {
            ["scope"] = "native-storymode-companion-hiring",
            ["state"] = projectedState,
            ["journalObjectiveSnapshot"] = journal.DeepClone(),
            ["objectiveSnapshot"] = objective.DeepClone(),
            ["visibleSafeTownTargets"] = BuildSafeTownDecisionWindow(safeTowns),
            ["safeTownTargetCount"] = safeTowns?.Count ?? 0,
            ["additionalSafeTownTargetsAvailable"] = safeTowns is not null && safeTowns.Count > SafeTownDecisionWindowSize,
            ["sceneObservationScope"] = ReadString(sceneAgentsReceipt?["data"] as JsonObject, "scope"),
            ["sceneAgentCount"] = ReadInt(sceneAgentsReceipt?["data"] as JsonObject, "activeAgentCount", 0),
            ["currentSceneWandererCandidates"] = compactCandidates,
            ["nearbyInteractableWanderers"] = nearbyCandidates,
            ["selectedWandererHeroId"] = selectedHeroId,
            ["lastInteractionHeroId"] = interactTargetHeroId,
            ["priorStepCount"] = traceCount
        };
    }

    private static JsonArray BuildSafeTownDecisionWindow(JsonArray? safeTowns) => new(
        (safeTowns?.OfType<JsonObject>() ?? Enumerable.Empty<JsonObject>())
        .OrderBy(town => ReadDouble(town, "distance"))
        .ThenBy(town => ReadString(town, "id"), StringComparer.Ordinal)
        .Take(SafeTownDecisionWindowSize)
        .Select(town => (JsonNode?)new JsonObject
        {
            ["id"] = ReadString(town, "id"),
            ["name"] = ReadString(town, "name"),
            ["distance"] = ReadDouble(town, "distance")
        }).ToArray());

    private static JsonObject SafeReceipt(JsonObject receipt, string action, string? targetSettlementId, string? targetHeroId, JsonArray? safeTowns) => new()
    {
        ["action"] = action,
        ["status"] = ReadString(receipt, "status"),
        ["targetSettlementId"] = targetSettlementId,
        ["targetHeroId"] = targetHeroId,
        ["data"] = action == "mapSettlementTargets"
            ? new JsonObject
            {
                ["safeTownTargetCount"] = safeTowns?.Count ?? 0,
                ["decisionWindowCount"] = BuildSafeTownDecisionWindow(safeTowns).Count,
                ["additionalSafeTownTargetsAvailable"] = safeTowns is not null && safeTowns.Count > SafeTownDecisionWindowSize
            }
            : receipt["data"]?.DeepClone()
    };

    private static JsonObject BuildStep(int decision, JsonObject observation, JsonObject? selectedDecision, JsonObject? receipt,
        JsonObject? afterState, string? kind, JsonObject? feedback = null) => new()
    {
        ["decision"] = decision,
        ["observation"] = observation.DeepClone(),
        ["selectedDecision"] = selectedDecision?.DeepClone(),
        ["nativeReceipt"] = receipt?.DeepClone(),
        ["decisionFeedback"] = feedback?.DeepClone(),
        ["afterState"] = afterState?.DeepClone(),
        ["stepKind"] = kind
    };

    private static string DescribeNoAction(JsonObject state, JsonArray? safeTowns, JsonObject? sceneAgentsReceipt, JsonArray journal)
    {
        var gameState = ReadString(state["context"] as JsonObject, "gameState");
        if (gameState == "MapState" && safeTowns is { Count: 0 }) return "No newly observed safe Town remains for a Tavern visit in this subgoal.";
        if (gameState == "MissionState" && sceneAgentsReceipt is not null && FilterWandererCandidates(sceneAgentsReceipt["data"]?["agents"] as JsonArray, new HashSet<string>(StringComparer.Ordinal)).Count == 0)
            return "The current Native Tavern Mission contains no eligible Wanderer Hero candidate.";
        return "No safe current Native menu, movement, scene observation, Wanderer interaction or hiring dialogue action is available.";
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
            throw new AgentHostException("companion-quest-details-unavailable", "The Native Journal no longer contains the exact original EYC quest.");
        return AgentHostEstablishYourClanGoalLoop.BuildJournalObjectives(data);
    }

    private static int ReadInt(JsonObject? node, string name, int fallback = 0) => node?[name] is JsonValue value && value.TryGetValue<int>(out var result) ? result : fallback;
    private static double ReadDouble(JsonObject? node, string name, double fallback = double.NaN) => ReadNumber(node, name) ?? fallback;
    private static double? ReadNumber(JsonObject? node, string name)
    {
        if (node?[name] is not JsonValue value) return null;
        if (value.TryGetValue<double>(out var doubleValue)) return doubleValue;
        if (value.TryGetValue<int>(out var intValue)) return intValue;
        if (value.TryGetValue<long>(out var longValue)) return longValue;
        return null;
    }
    private static string? ReadString(JsonObject? node, string name) => node?[name] is JsonValue value && value.TryGetValue<string>(out var result) ? result : null;
    private static string? ReadString(JsonElement element, string name) => element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;
    private static bool ReadBoolean(JsonObject? node, string name) => node?[name] is JsonValue value && value.TryGetValue<bool>(out var result) && result;
    private static int ReadInt(JsonElement element, string name, int fallback = 0) => element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var value) && value.TryGetInt32(out var result) ? result : fallback;
    private static bool ReadBoolean(JsonElement element, string name) => element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.True;

    private sealed class FakeMovementCompanionClient : IAgentHostCampaignNativeClient, IAgentHostCompanionHiringNativeClient
    {
        private bool _moveIssued;
        private bool _arrived;
        private bool _townMenuAdvanced;
        private bool _sceneNotificationActive;
        private bool _sceneNotificationWasContinued;
        private int _postMoveReads;
        internal List<string> Actions { get; } = new();
        internal int ActiveMovementStateReads { get; private set; }
        internal int ExplicitClockActions { get; private set; }
        internal int SceneNotificationContinueCount { get; private set; }
        internal double CampaignDay { get; } = 91077.375;

        public Task<JsonDocument> ReadStateAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (_moveIssued && !_arrived && !_sceneNotificationActive)
            {
                _postMoveReads++;
                if (_postMoveReads == 1 && !_sceneNotificationWasContinued) _sceneNotificationActive = true;
                else if (_postMoveReads >= 4) _arrived = true;
                else ActiveMovementStateReads++;
            }
            var menuId = !_arrived ? null : (_townMenuAdvanced ? "town_backstreet" : "town");
            var options = !_arrived ? new JsonArray() : new JsonArray(new JsonObject
            {
                ["id"] = _townMenuAdvanced ? "town_tavern" : "town_backstreet",
                ["available"] = true,
                ["enabled"] = true,
                ["isLeave"] = false
            });
            var state = new JsonObject
            {
                ["context"] = new JsonObject
                {
                    ["gameState"] = "MapState", ["menuId"] = menuId, ["encounterActive"] = false,
                    ["inquiryOpen"] = false, ["escapeMenuOpen"] = false,
                    ["timeControlMode"] = _moveIssued ? "StoppablePlay" : "Stop",
                    ["campaignDay"] = CampaignDay,
                    ["sceneNotification"] = _sceneNotificationActive ? new JsonObject
                    {
                        ["available"] = true, ["hasActiveNotification"] = true, ["isShown"] = true, ["isReady"] = true,
                        ["dataType"] = "FindingFirstBannerPieceSceneNotificationItem", ["titleText"] = "A Native map scene notification",
                        ["clickToContinueText"] = "Click to continue", ["affirmativeButtonShown"] = false,
                        ["negativeButtonShown"] = false, ["pauseActiveState"] = true, ["canContinue"] = true
                    } : new JsonObject { ["available"] = true, ["hasActiveNotification"] = false },
                    ["captivity"] = new JsonObject { ["isCaptive"] = false }
                },
                ["availableMenuOptions"] = options,
                ["location"] = new JsonObject
                {
                    ["currentSettlementId"] = _arrived ? "town-a" : null,
                    ["targetSettlementId"] = _moveIssued ? "town-a" : null
                },
                ["party"] = new JsonObject { ["members"] = 1, ["isMoving"] = _moveIssued && !_arrived },
                ["economy"] = new JsonObject { ["gold"] = 1000 },
                ["storyModeEstablishClan"] = new JsonObject { ["companions"] = new JsonObject { ["current"] = 0, ["target"] = 1 } }
            };
            return Task.FromResult(JsonDocument.Parse(new JsonObject { ["status"] = "completed", ["state"] = state }.ToJsonString()));
        }

        public Task<JsonDocument> ReadQuestDetailsAsync(string questId, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (questId != QuestId) throw new AgentHostException("companion-movement-selftest-wrong-quest", "Movement waiting read an unexpected Journal.");
            var stages = new JsonArray(
                new JsonObject { ["hasTask"] = true, ["currentProgress"] = 1000, ["targetProgress"] = 2000, ["description"] = "gold" },
                new JsonObject { ["hasTask"] = true, ["currentProgress"] = 1, ["targetProgress"] = 25, ["description"] = "partySize" },
                new JsonObject { ["hasTask"] = true, ["currentProgress"] = 20, ["targetProgress"] = 50, ["description"] = "renown" },
                new JsonObject { ["hasTask"] = true, ["currentProgress"] = 0, ["targetProgress"] = 1, ["description"] = "companions" });
            return Task.FromResult(JsonDocument.Parse(new JsonObject { ["status"] = "completed", ["data"] = new JsonObject { ["questId"] = QuestId, ["journalStages"] = stages } }.ToJsonString()));
        }

        public Task<JsonDocument> ExecuteCampaignActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Actions.Add(action);
            if (action == "mapSettlementTargets")
                return Receipt(action, new JsonObject { ["mapSettlementTargets"] = new JsonArray(new JsonObject { ["id"] = "town-a", ["name"] = "Town A", ["type"] = "town", ["distance"] = 1.0, ["hostile"] = false, ["underSiege"] = false }) });
            if (action == "move" && ReadString(arguments, "settlementId") == "town-a")
            {
                _moveIssued = true;
                return Receipt(action, new JsonObject { ["targetSettlementId"] = "town-a", ["timeControlMode"] = "StoppablePlay" });
            }
            if (action == "continueSceneNotification" && arguments.Count == 0 && _sceneNotificationActive)
            {
                _sceneNotificationActive = false;
                _sceneNotificationWasContinued = true;
                SceneNotificationContinueCount++;
                return Receipt(action, new JsonObject { ["nativeHandler"] = "SceneNotificationVM.ExecuteClose", ["notificationStillActive"] = false, ["campaignDayBefore"] = CampaignDay, ["campaignDayAfter"] = CampaignDay });
            }
            if (action is "pause" or "resume" or "fastForward") ExplicitClockActions++;
            throw new AgentHostException("companion-movement-selftest-unexpected-map-action", "Movement waiting issued an unexpected Native map command.");
        }

        public Task<JsonDocument> ExecuteCompanionHiringActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Actions.Add(action);
            if (action == "menuSelect" && ReadString(arguments, "menuId") == "town" && ReadString(arguments, "optionId") == "town_backstreet")
            {
                _townMenuAdvanced = true;
                return Receipt(action, new JsonObject { ["menuId"] = "town", ["optionId"] = "town_backstreet" });
            }
            throw new AgentHostException("companion-movement-selftest-unexpected-town-action", "The companion loop resumed at an unexpected Town menu option.");
        }

        private static Task<JsonDocument> Receipt(string action, JsonObject data) =>
            Task.FromResult(JsonDocument.Parse(new JsonObject { ["status"] = "completed", ["action"] = action, ["data"] = data }.ToJsonString()));
    }

    private sealed class FakeMovementDecisionProvider : IAgentHostDecisionProvider
    {
        internal int CallCount { get; private set; }
        internal bool SawSceneNotification { get; private set; }
        public string ModelId => "deterministic-companion-map-movement-selftest";
        public string ConfigurationSource => "harness-fake-provider";
        public Task CheckConfiguredModelAsync(CancellationToken cancellationToken) { cancellationToken.ThrowIfCancellationRequested(); return Task.CompletedTask; }

        public Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            CallCount++;
            var observedState = request.GetProperty("observation").GetProperty("state");
            if (observedState.GetProperty("context").TryGetProperty("sceneNotification", out var sceneNotification) &&
                sceneNotification.TryGetProperty("hasActiveNotification", out var hasActive) && hasActive.GetBoolean() &&
                sceneNotification.TryGetProperty("canContinue", out var canContinue) && canContinue.GetBoolean()) SawSceneNotification = true;
            var actions = request.GetProperty("allowedActions").EnumerateArray().ToArray();
            JsonObject decision;
            var mapTargets = actions.FirstOrDefault(action => action.GetProperty("action").GetString() == "mapSettlementTargets");
            var move = actions.FirstOrDefault(action => action.GetProperty("action").GetString() == "move");
            var menu = actions.FirstOrDefault(action => action.GetProperty("action").GetString() == "menuSelect");
            var notificationContinue = actions.FirstOrDefault(action => action.GetProperty("action").GetString() == "continueSceneNotification");
            if (mapTargets.ValueKind == JsonValueKind.Object)
                decision = new JsonObject { ["action"] = "mapSettlementTargets", ["arguments"] = new JsonObject() };
            else if (move.ValueKind == JsonValueKind.Object)
                decision = new JsonObject { ["action"] = "move", ["arguments"] = new JsonObject { ["SettlementId"] = move.GetProperty("argumentValues").GetProperty("SettlementId")[0].GetString() } };
            else if (menu.ValueKind == JsonValueKind.Object)
                decision = new JsonObject { ["action"] = "menuSelect", ["arguments"] = new JsonObject
                {
                    ["MenuId"] = menu.GetProperty("argumentValues").GetProperty("MenuId")[0].GetString(),
                    ["OptionId"] = menu.GetProperty("argumentValues").GetProperty("OptionId")[0].GetString()
                } };
            else if (notificationContinue.ValueKind == JsonValueKind.Object)
                decision = new JsonObject { ["action"] = "continueSceneNotification", ["arguments"] = new JsonObject() };
            else if (request.GetProperty("allowedControls").EnumerateArray().Any(control => control.GetString() == "observeAgain"))
                decision = new JsonObject { ["control"] = "observeAgain", ["waitSeconds"] = 1, ["reason"] = "Current Native movement is active." };
            else
                throw new AgentHostException("companion-movement-selftest-no-action", "No current Native movement test action/control was listed.");
            return Task.FromResult(new ProviderDecisionResult("completed", ModelId, 1, 1, "self-test", decision, "self-test", "json_schema"));
        }

        public void Dispose() { }
    }

    private sealed class FakeCompanionClient : IAgentHostCampaignNativeClient, IAgentHostCompanionHiringNativeClient
    {
        private readonly bool _simulateStalledNavigation;
        private readonly bool _neverEnterTavernMission;
        private readonly CancellationTokenSource? _cancelAfterTavernEntryMapRead;
        private int _tavernEntryTransitionDelayReadsRemaining;
        private int _stage;
        private bool _navigated;
        private int _tavernMissionStartupReadsRemaining = 2;
        private int _missionNavigationActiveReadsRemaining;
        private double _wandererDistance = 10.201;
        internal int ActiveMissionNavigationStateReads { get; private set; }
        internal int TavernMissionStartupStateReads { get; private set; }
        internal int TavernEntryTransitionMapReads { get; private set; }
        internal int NavigationAttemptCount { get; private set; }
        internal int MissionLeaveCount { get; private set; }
        internal List<string> Actions { get; } = new();
        internal int Gold => !_simulateStalledNavigation && _stage >= 8 ? 1340 : 2000;
        internal int CompanionCount => !_simulateStalledNavigation && _stage >= 8 ? 1 : 0;

        internal FakeCompanionClient(bool simulateStalledNavigation = false, int tavernEntryTransitionDelayReads = 0,
            bool neverEnterTavernMission = false, CancellationTokenSource? cancelAfterTavernEntryMapRead = null)
        {
            _simulateStalledNavigation = simulateStalledNavigation;
            _tavernEntryTransitionDelayReadsRemaining = Math.Max(0, tavernEntryTransitionDelayReads);
            _neverEnterTavernMission = neverEnterTavernMission;
            _cancelAfterTavernEntryMapRead = cancelAfterTavernEntryMapRead;
        }

        public Task<JsonDocument> ReadStateAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            JsonObject state;
            if (_stage == 2 && (_neverEnterTavernMission || _tavernEntryTransitionDelayReadsRemaining > 0))
            {
                if (!_neverEnterTavernMission) _tavernEntryTransitionDelayReadsRemaining--;
                TavernEntryTransitionMapReads++;
                state = BuildState("MapState", "town_backstreet", new JsonArray(
                    new JsonObject { ["id"] = "town_tavern", ["available"] = true, ["enabled"] = true, ["isLeave"] = false },
                    new JsonObject { ["id"] = "town_backstreet_back", ["available"] = true, ["enabled"] = true, ["isLeave"] = true }));
                if (TavernEntryTransitionMapReads == 1) _cancelAfterTavernEntryMapRead?.Cancel();
            }
            else if (_stage < 2)
            {
                var menuId = _stage == 0 ? "town" : "town_backstreet";
                var optionId = _stage == 0 ? "town_backstreet" : "town_tavern";
                state = BuildState("MapState", menuId, new JsonArray(new JsonObject { ["id"] = optionId, ["available"] = true, ["enabled"] = true, ["isLeave"] = false }));
            }
            else if (_stage >= 9)
            {
                state = BuildState("MapState", null, new JsonArray());
            }
            else
            {
                state = BuildState("MissionState", null, new JsonArray());
                var navigationActive = _missionNavigationActiveReadsRemaining > 0;
                if (navigationActive)
                {
                    _missionNavigationActiveReadsRemaining--;
                    ActiveMissionNavigationStateReads++;
                }
                if (_stage == 5)
                    state["context"]!["conversation"] = BuildConversation("wanderer-a", "Wanderer business offer", "wanderer_meet_player_response2");
                else if (_stage == 6)
                    state["context"]!["conversation"] = BuildConversation("wanderer-a", "Company offer", "main_option_faction_hire");
                else if (_stage == 7)
                    state["context"]!["conversation"] = BuildConversation("wanderer-a", "Wanderer asks for 660 denars", "player_companion_hire_response_1", "player_companion_hire_response_2");
                else if (_stage >= 4)
                    state["mission"] = new JsonObject
                    {
                        ["nearbySceneAgents"] = _navigated
                            ? new JsonArray(new JsonObject { ["agentIndex"] = 4, ["heroId"] = "wanderer-a", ["occupation"] = "Wanderer", ["isNotable"] = false, ["isEnemy"] = false, ["isInteractable"] = !_simulateStalledNavigation && !navigationActive, ["distance"] = _simulateStalledNavigation ? _wandererDistance : navigationActive ? 3.0 : 1.2 })
                            : new JsonArray(),
                        ["navigation"] = new JsonObject { ["active"] = navigationActive, ["targetAgentIndex"] = _navigated ? 4 : null }, ["leave"] = null
                    };
                state["mission"] ??= new JsonObject();
                state["location"] ??= new JsonObject();
                state["context"]!["encounterActive"] = true;
                state["context"]!["encounteredPartyId"] = "town-a";
                state["mission"]!["active"] = true;
                state["mission"]!["sceneName"] = "empire_house_c_tavern_a";
                state["location"]!["currentSettlementId"] = "town-a";
                if (_stage == 2 && _tavernMissionStartupReadsRemaining > 0)
                {
                    _tavernMissionStartupReadsRemaining--;
                    TavernMissionStartupStateReads++;
                    state["mission"]!["mode"] = "StartUp";
                    state["mission"]!["nativeMissionCurrentState"] = "Initializing";
                    state["mission"]!["nativeConversationReady"] = false;
                    state["mission"]!["activeAgentCount"] = 0;
                }
                else
                {
                    state["mission"]!["nativeMissionCurrentState"] = "Continuing";
                    state["mission"]!["nativeConversationReady"] = true;
                    state["mission"]!["activeAgentCount"] = 25;
                }
            }
            state["campaignDay"] = 10.0;
            state["economy"] = new JsonObject { ["gold"] = Gold };
            state["storyModeEstablishClan"] = new JsonObject { ["companions"] = new JsonObject { ["current"] = CompanionCount, ["target"] = 1 } };
            state["location"] = new JsonObject { ["currentSettlementId"] = "town-a", ["targetSettlementId"] = null };
            state["party"] = new JsonObject { ["members"] = 4, ["isMoving"] = false };
            return Task.FromResult(JsonDocument.Parse(new JsonObject { ["status"] = "completed", ["state"] = state }.ToJsonString()));
        }

        public Task<JsonDocument> ReadQuestDetailsAsync(string questId, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (questId != QuestId) throw new AgentHostException("companion-selftest-wrong-quest", "The fake client received an unexpected Journal request.");
            var values = new (string Id, int Current, int Target)[]
            {
                ("gold", Gold, 2000), ("partySize", 4, 25), ("renown", 0, 50), ("companions", CompanionCount, 1)
            };
            var stages = new JsonArray(values.Select(value => (JsonNode?)new JsonObject { ["hasTask"] = true, ["currentProgress"] = value.Current, ["targetProgress"] = value.Target, ["description"] = value.Id }).ToArray());
            var data = new JsonObject { ["questId"] = QuestId, ["journalStages"] = stages };
            return Task.FromResult(JsonDocument.Parse(new JsonObject { ["status"] = "completed", ["data"] = data }.ToJsonString()));
        }

        public Task<JsonDocument> ExecuteCampaignActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Actions.Add(action);
            if (action == "mapSettlementTargets")
                return Receipt(action, new JsonObject { ["mapSettlementTargets"] = new JsonArray() });
            if (action != "menuSelect") throw new AgentHostException("companion-selftest-unexpected-map-action", "The fake companion route did not request an expected settlement menu action.");
            _stage++;
            return Receipt(action, new JsonObject { ["menuId"] = ReadString(arguments, "menuId"), ["optionId"] = ReadString(arguments, "optionId") });
        }

        public Task<JsonDocument> ExecuteCompanionHiringActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Actions.Add(action);
            JsonObject data;
            switch (action)
            {
                case "menuSelect":
                    _stage++;
                    data = new JsonObject { ["menuId"] = ReadString(arguments, "menuId"), ["optionId"] = ReadString(arguments, "optionId") };
                    return Receipt(action, data);
                case "missionSceneAgents":
                    _stage = 4;
                    data = new JsonObject
                    {
                        ["scope"] = "current-location-mission",
                        ["agents"] = new JsonArray(new JsonObject { ["agentIndex"] = 4, ["heroId"] = "wanderer-a", ["occupation"] = "Wanderer", ["isNotable"] = false, ["isEnemy"] = false, ["nativeConversationActionAvailable"] = !_simulateStalledNavigation, ["distance"] = _simulateStalledNavigation ? _wandererDistance : 6.0 })
                    };
                    return Receipt(action, data);
                case "missionNavigateToAgent":
                    _stage = 4;
                    _navigated = true;
                    NavigationAttemptCount++;
                    if (_simulateStalledNavigation) _wandererDistance = Math.Min(_wandererDistance, 1.365);
                    else _missionNavigationActiveReadsRemaining = 3;
                    data = new JsonObject { ["targetAgentIndex"] = 4, ["status"] = "navigating" };
                    return Receipt(action, data);
                case "missionInteract": _stage = 5; data = new JsonObject { ["targetHeroId"] = "wanderer-a", ["conversationStarted"] = true }; return Receipt(action, data);
                case "missionLeave": _stage = 9; MissionLeaveCount++; data = new JsonObject { ["status"] = "holding-native-leave-area" }; return Receipt(action, data);
                case "dialogueSelect":
                    var optionId = ReadString(arguments, "optionId");
                    _stage = optionId switch
                    {
                        "wanderer_meet_player_response2" => 6,
                        "main_option_faction_hire" => 7,
                        "player_companion_hire_response_1" => 8,
                        _ => throw new AgentHostException("companion-selftest-unexpected-dialogue", "The fake route received an unrelated Native dialogue choice.")
                    };
                    data = new JsonObject { ["optionId"] = optionId, ["status"] = "completed" };
                    return Receipt(action, data);
                default: throw new AgentHostException("companion-selftest-unexpected-native-action", "The fake companion client received an unexpected action.");
            }
        }

        private static JsonObject BuildState(string gameState, string? menuId, JsonArray menuOptions)
        {
            var context = new JsonObject { ["gameState"] = gameState, ["menuId"] = menuId, ["encounterActive"] = false, ["inquiryOpen"] = false, ["captivity"] = new JsonObject { ["isCaptive"] = false } };
            return new JsonObject
            {
                ["context"] = context,
                ["availableMenuOptions"] = menuOptions,
                ["mainHeroSkills"] = new JsonObject { ["skills"] = new JsonArray(new JsonObject { ["id"] = "leadership", ["level"] = 10 }) },
                ["quests"] = new JsonArray(new JsonObject { ["id"] = QuestId }),
                ["party"] = new JsonObject { ["isMoving"] = false }
            };
        }

        private static JsonObject BuildConversation(string heroId, string text, params string[] options) => new()
        {
            ["heroId"] = heroId,
            ["sentenceText"] = text,
            ["options"] = new JsonArray(options.Select(id => (JsonNode?)new JsonObject { ["id"] = id, ["clickable"] = true }).ToArray())
        };

        private static Task<JsonDocument> Receipt(string action, JsonObject data) =>
            Task.FromResult(JsonDocument.Parse(new JsonObject { ["status"] = "completed", ["action"] = action, ["data"] = data }.ToJsonString()));
    }

    private sealed class FakeCompanionProvider : IAgentHostDecisionProvider
    {
        private static readonly (string Action, JsonObject Arguments)[] Decisions =
        [
            ("menuSelect", new JsonObject { ["MenuId"] = "town", ["OptionId"] = "town_backstreet" }),
            ("menuSelect", new JsonObject { ["MenuId"] = "town_backstreet", ["OptionId"] = "town_tavern" }),
            ("missionNavigateToAgent", new JsonObject { ["AgentIndex"] = 4, ["DurationSeconds"] = 8 }),
            ("missionInteract", new JsonObject { ["AgentIndex"] = 4 }),
            ("dialogueSelect", new JsonObject { ["OptionId"] = "wanderer_meet_player_response2" }),
            ("dialogueSelect", new JsonObject { ["OptionId"] = "main_option_faction_hire" }),
            ("dialogueSelect", new JsonObject { ["OptionId"] = "player_companion_hire_response_1" }),
            ("missionLeave", new JsonObject())
        ];
        internal int CallCount { get; private set; }
        internal bool SawActiveMissionNavigation { get; private set; }
        internal bool SawCompanionObservationProjection { get; private set; }
        public string ModelId => "deterministic-establish-clan-companion-selftest";
        public string ConfigurationSource => "harness-fake-provider";
        public Task CheckConfiguredModelAsync(CancellationToken cancellationToken) { cancellationToken.ThrowIfCancellationRequested(); return Task.CompletedTask; }
        public Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var observation = request.GetProperty("observation");
            var state = observation.GetProperty("state");
            if (!state.TryGetProperty("mainHeroSkills", out _) &&
                state.TryGetProperty("mission", out var companionMission) && companionMission.ValueKind == JsonValueKind.Object &&
                !companionMission.TryGetProperty("nearbySceneAgents", out _) &&
                observation.TryGetProperty("currentSceneWandererCandidates", out var currentCandidates) && currentCandidates.ValueKind == JsonValueKind.Array &&
                currentCandidates.EnumerateArray().Any(candidate => ReadString(candidate, "heroId") == "wanderer-a") &&
                observation.TryGetProperty("nearbyInteractableWanderers", out var nearbyCandidates) && nearbyCandidates.ValueKind == JsonValueKind.Array &&
                nearbyCandidates.EnumerateArray().Any(candidate => ReadString(candidate, "heroId") == "wanderer-a"))
                SawCompanionObservationProjection = true;
            if (state.TryGetProperty("mission", out var mission) && mission.ValueKind == JsonValueKind.Object &&
                mission.TryGetProperty("navigation", out var navigation) && navigation.ValueKind == JsonValueKind.Object &&
                navigation.TryGetProperty("active", out var active) && active.ValueKind == JsonValueKind.True)
                SawActiveMissionNavigation = true;
            if (CallCount >= Decisions.Length) throw new AgentHostException("companion-selftest-provider-exhausted", "The fake provider received too many Tavern decisions.");
            var selected = Decisions[CallCount++];
            return Task.FromResult(new ProviderDecisionResult("completed", ModelId, 1, 1, "fake-companion-selftest", new JsonObject
            {
                ["action"] = selected.Action,
                ["arguments"] = selected.Arguments.DeepClone(),
                ["rationale"] = "Choose the current Native option for the bounded hiring task."
            }));
        }
        public void Dispose() { }
    }

    private sealed class FakeCompanionStallProvider : IAgentHostDecisionProvider
    {
        internal int CallCount { get; private set; }
        internal int NavigationDecisionCount { get; private set; }
        internal bool StoppedOnFreeMap { get; private set; }
        public string ModelId => "deterministic-companion-navigation-stall-selftest";
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
            var actions = request.GetProperty("allowedActions").EnumerateArray().ToArray();
            var controls = request.GetProperty("allowedControls").EnumerateArray().Select(item => item.GetString()).ToArray();
            var state = request.GetProperty("observation").GetProperty("state");
            JsonObject decision;
            if (controls.Contains("stop", StringComparer.Ordinal) &&
                state.TryGetProperty("context", out var context) && context.ValueKind == JsonValueKind.Object &&
                ReadString(context, "gameState") == "MapState" && ReadString(context, "menuId") is null)
            {
                StoppedOnFreeMap = true;
                decision = new JsonObject { ["stop"] = true, ["reason"] = "Automatic Native scan excluded the stalled Tavern target." };
            }
            else if (actions.FirstOrDefault(item => ReadString(item, "action") == "menuSelect") is var menuAction && menuAction.ValueKind == JsonValueKind.Object)
            {
                var values = menuAction.GetProperty("argumentValues");
                decision = new JsonObject
                {
                    ["action"] = "menuSelect",
                    ["arguments"] = new JsonObject
                    {
                        ["MenuId"] = values.GetProperty("MenuId")[0].GetString(),
                        ["OptionId"] = values.GetProperty("OptionId")[0].GetString()
                    }
                };
            }
            else if (actions.FirstOrDefault(item => ReadString(item, "action") == "missionNavigateToAgent") is var navigateAction && navigateAction.ValueKind == JsonValueKind.Object)
            {
                NavigationDecisionCount++;
                var values = navigateAction.GetProperty("argumentValues");
                decision = new JsonObject
                {
                    ["action"] = "missionNavigateToAgent",
                    ["arguments"] = new JsonObject
                    {
                        ["AgentIndex"] = values.GetProperty("AgentIndex")[0].GetInt32(),
                        ["DurationSeconds"] = values.GetProperty("DurationSeconds")[0].GetInt32()
                    }
                };
            }
            else if (actions.FirstOrDefault(item => ReadString(item, "action") == "mapSettlementTargets") is var targetAction && targetAction.ValueKind == JsonValueKind.Object)
            {
                decision = new JsonObject { ["action"] = "mapSettlementTargets", ["arguments"] = new JsonObject() };
            }
            else
            {
                throw new AgentHostException("companion-stall-selftest-no-current-action", "The stall fixture exposed neither a Native menu/navigation action nor a safe Map stop control.");
            }

            return Task.FromResult(new ProviderDecisionResult("completed", ModelId, 0, 0, "self-test", decision, "self-test", "json_schema"));
        }

        public void Dispose() { }
    }

    private sealed class FakePersistentNoCandidateCompanionClient : IAgentHostCampaignNativeClient,
        IAgentHostCompanionHiringNativeClient, IAgentHostQuestDetailsNativeClient, IAgentHostCampaignCheckpointNativeClient
    {
        private enum NativeStage { Town, Backstreet, Tavern, FreeMap }
        private readonly bool _startAtFreeMap;
        private NativeStage _stage;
        private string? _checkpointJson;
        internal List<string> Actions { get; } = new();
        internal int CheckpointWrites { get; private set; }
        internal string? StoredCheckpointJson => _checkpointJson;

        internal FakePersistentNoCandidateCompanionClient(string? checkpointJson = null, bool startAtFreeMap = false)
        {
            _checkpointJson = checkpointJson;
            _startAtFreeMap = startAtFreeMap;
            _stage = startAtFreeMap ? NativeStage.FreeMap : NativeStage.Town;
        }

        public Task<JsonDocument> ReadStateAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var mission = _stage == NativeStage.Tavern;
            var menuId = _stage switch
            {
                NativeStage.Town => "town",
                NativeStage.Backstreet => "town_backstreet",
                _ => null
            };
            var options = menuId switch
            {
                "town" => new JsonArray(
                    MenuOption("town_backstreet", leave: false),
                    MenuOption("town_leave", leave: true)),
                "town_backstreet" => new JsonArray(
                    MenuOption("town_tavern", leave: false),
                    MenuOption("town_backstreet_back", leave: true)),
                _ => new JsonArray()
            };
            var state = new JsonObject
            {
                ["context"] = new JsonObject
                {
                    ["gameState"] = mission ? "MissionState" : "MapState",
                    ["menuId"] = menuId,
                    ["encounteredPartyId"] = mission ? "town_a" : null,
                    ["encounterActive"] = false,
                    ["inquiryOpen"] = false,
                    ["escapeMenuOpen"] = false,
                    ["captivity"] = new JsonObject { ["isCaptive"] = false }
                },
                ["location"] = new JsonObject { ["currentSettlementId"] = _stage == NativeStage.FreeMap ? null : "town_a", ["targetSettlementId"] = null },
                ["availableMenuOptions"] = options,
                ["nearbySettlements"] = new JsonArray(
                    Settlement("town_a", "Town A", 1),
                    Settlement("town_b", "Town B", 2)),
                ["party"] = new JsonObject { ["members"] = 1, ["isMoving"] = false, ["food"] = 1, ["morale"] = 50 },
                ["economy"] = new JsonObject { ["gold"] = 1000, ["renown"] = 20 },
                ["storyModeEstablishClan"] = new JsonObject { ["companions"] = new JsonObject { ["current"] = 0, ["target"] = 1 } },
                ["quests"] = new JsonArray(new JsonObject { ["id"] = QuestId }),
                ["mission"] = mission ? new JsonObject
                {
                    ["active"] = true,
                    ["sceneName"] = "town_a_tavern",
                    ["nativeMissionCurrentState"] = "Running",
                    ["nativeConversationReady"] = true,
                    ["navigation"] = new JsonObject { ["active"] = false },
                    ["leave"] = new JsonObject { ["active"] = false },
                    ["nearbySceneAgents"] = new JsonArray()
                } : null
            };
            return Task.FromResult(JsonDocument.Parse(new JsonObject
            {
                ["status"] = "completed",
                ["campaignDay"] = 10.0,
                ["timeControlMode"] = "Stop",
                ["state"] = state
            }.ToJsonString()));
        }

        public Task<JsonDocument> ReadQuestDetailsAsync(string questId, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (questId != QuestId) throw new AgentHostException("eyc-companion-memory-self-test-wrong-quest", "The persistent Companion memory test queried an unexpected Quest.");
            return Task.FromResult(JsonDocument.Parse(new JsonObject
            {
                ["status"] = "completed",
                ["data"] = new JsonObject { ["questId"] = QuestId, ["journalStages"] = BuildJournal() }
            }.ToJsonString()));
        }

        internal JsonArray ReadJournal() => BuildJournal();

        public Task<JsonDocument> ReadCampaignCheckpointAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var base64 = _checkpointJson is null ? string.Empty : Convert.ToBase64String(Encoding.UTF8.GetBytes(_checkpointJson));
            return Task.FromResult(JsonDocument.Parse(new JsonObject
            {
                ["status"] = "completed",
                ["data"] = new JsonObject { ["campaignInstanceId"] = "campaign-companion-memory-selftest", ["checkpointBase64"] = base64 }
            }.ToJsonString()));
        }

        internal JsonDocument ReadStoredCheckpointReceipt()
        {
            var base64 = _checkpointJson is null ? string.Empty : Convert.ToBase64String(Encoding.UTF8.GetBytes(_checkpointJson));
            return JsonDocument.Parse(new JsonObject
            {
                ["status"] = "completed",
                ["data"] = new JsonObject { ["campaignInstanceId"] = "campaign-companion-memory-selftest", ["checkpointBase64"] = base64 }
            }.ToJsonString());
        }

        public Task<JsonDocument> WriteCampaignCheckpointAsync(string checkpointJson, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var base64 = AgentHostCampaignCheckpointCodec.EncodeForNative(checkpointJson);
            using var saved = JsonDocument.Parse(new UTF8Encoding(false, true).GetString(Convert.FromBase64String(base64)));
            if (ReadString(saved.RootElement, "campaignInstanceId") != "campaign-companion-memory-selftest")
                throw new AgentHostException("eyc-companion-memory-self-test-checkpoint-campaign-mismatch", "The checkpoint writer attempted to change Campaign identity.");
            _checkpointJson = checkpointJson;
            CheckpointWrites++;
            return Task.FromResult(JsonDocument.Parse("{\"status\":\"completed\",\"action\":\"agentCheckpointSet\"}"));
        }

        public Task<JsonDocument> ExecuteCampaignActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Actions.Add(action);
            if (action == "mapSettlementTargets")
                return Task.FromResult(JsonDocument.Parse(new JsonObject
                {
                    ["status"] = "completed", ["action"] = action,
                    ["data"] = new JsonObject { ["mapSettlementTargets"] = new JsonArray(Settlement("town_a", "Town A", 1), Settlement("town_b", "Town B", 2)) }
                }.ToJsonString()));
            if (action != "move") throw new AgentHostException("eyc-companion-memory-self-test-unexpected-campaign-action", "The checkpoint-memory test issued an unexpected Campaign action.");
            return Task.FromResult(JsonDocument.Parse(new JsonObject { ["status"] = "completed", ["action"] = action, ["data"] = new JsonObject() }.ToJsonString()));
        }

        public Task<JsonDocument> ExecuteCompanionHiringActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Actions.Add(action);
            if (action == "missionSceneAgents")
                return Task.FromResult(JsonDocument.Parse(new JsonObject
                {
                    ["status"] = "completed", ["action"] = action,
                    ["data"] = new JsonObject { ["scope"] = "current-location-mission", ["activeAgentCount"] = 3, ["agents"] = new JsonArray() }
                }.ToJsonString()));
            if (action == "missionLeave" && _stage == NativeStage.Tavern)
            {
                _stage = NativeStage.Backstreet;
                return Task.FromResult(JsonDocument.Parse("{\"status\":\"completed\",\"action\":\"missionLeave\",\"data\":{\"nativeHandler\":\"LeaveMission\"}}"));
            }
            if (action == "menuSelect")
            {
                var option = ReadString(arguments, "optionId");
                _stage = option switch
                {
                    "town_backstreet" when _stage == NativeStage.Town => NativeStage.Backstreet,
                    "town_tavern" when _stage == NativeStage.Backstreet => NativeStage.Tavern,
                    "town_backstreet_back" when _stage == NativeStage.Backstreet => NativeStage.Town,
                    "town_leave" when _stage == NativeStage.Town => NativeStage.FreeMap,
                    _ => throw new AgentHostException("eyc-companion-memory-self-test-menu-invalid", "The model selected an unavailable Native Town menu option.")
                };
                return Task.FromResult(JsonDocument.Parse(new JsonObject { ["status"] = "completed", ["action"] = action, ["data"] = new JsonObject { ["optionId"] = option } }.ToJsonString()));
            }
            throw new AgentHostException("eyc-companion-memory-self-test-unexpected-companion-action", "The checkpoint-memory test issued an unexpected Tavern action.");
        }

        private static JsonArray BuildJournal() => new(
            Objective("gold", 1000, 2000), Objective("partySize", 1, 25),
            Objective("renown", 20, 50), Objective("companions", 0, 1));

        private static JsonObject Objective(string description, int current, int target) => new()
        {
            ["hasTask"] = true, ["currentProgress"] = current, ["targetProgress"] = target, ["description"] = description
        };

        private static JsonObject MenuOption(string id, bool leave) => new()
        {
            ["id"] = id, ["available"] = true, ["enabled"] = true, ["isLeave"] = leave
        };

        private static JsonObject Settlement(string id, string name, double distance) => new()
        {
            ["id"] = id, ["name"] = name, ["type"] = "town", ["distance"] = distance, ["hostile"] = false, ["underSiege"] = false
        };
    }

    private sealed class FakeNoCandidateCompanionProvider(bool firstRun) : IAgentHostDecisionProvider
    {
        internal int CallCount { get; private set; }
        internal bool SawOnlyTownBAfterResume { get; private set; }
        public string ModelId => "deterministic-companion-no-candidate-memory-selftest";
        public string ConfigurationSource => "harness-fake-provider";
        public Task CheckConfiguredModelAsync(CancellationToken cancellationToken) { cancellationToken.ThrowIfCancellationRequested(); return Task.CompletedTask; }
        public Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            CallCount++;
            JsonObject decision;
            if (firstRun)
            {
                decision = CallCount switch
                {
                    1 => NativeDecision("menuSelect", new JsonObject { ["MenuId"] = "town", ["OptionId"] = "town_backstreet" }),
                    2 => NativeDecision("menuSelect", new JsonObject { ["MenuId"] = "town_backstreet", ["OptionId"] = "town_tavern" }),
                    3 => NativeDecision("menuSelect", new JsonObject { ["MenuId"] = "town_backstreet", ["OptionId"] = "town_backstreet_back" }),
                    4 => NativeDecision("menuSelect", new JsonObject { ["MenuId"] = "town", ["OptionId"] = "town_leave" }),
                    5 => NativeDecision("mapSettlementTargets", new JsonObject()),
                    6 => ReadMoveCatalogAndStop(request, requireTownBOnly: true, this, out decision),
                    _ => throw new AgentHostException("eyc-companion-memory-self-test-provider-exhausted", "The first bounded Companion memory run requested too many model decisions.")
                };
            }
            else if (CallCount == 1)
                decision = NativeDecision("mapSettlementTargets", new JsonObject());
            else if (CallCount == 2)
                decision = ReadMoveCatalogAndStop(request, requireTownBOnly: true, this, out decision);
            else throw new AgentHostException("eyc-companion-memory-self-test-provider-exhausted", "The resumed Companion memory run requested too many model decisions.");

            return Task.FromResult(new ProviderDecisionResult("completed", ModelId, 0, 0, "selftest", decision, "selftest", "json_schema"));
        }

        private static JsonObject ReadMoveCatalogAndStop(JsonElement request, bool requireTownBOnly, FakeNoCandidateCompanionProvider provider, out JsonObject decision)
        {
            var observation = request.GetProperty("observation");
            var visible = observation.GetProperty("visibleSafeTownTargets").EnumerateArray().Select(item => item.GetProperty("id").GetString()).ToArray();
            var move = request.GetProperty("allowedActions").EnumerateArray().FirstOrDefault(item => item.GetProperty("action").GetString() == "move");
            var ids = move.ValueKind == JsonValueKind.Object
                ? move.GetProperty("argumentValues").GetProperty("SettlementId").EnumerateArray().Select(item => item.GetString()).ToArray()
                : Array.Empty<string?>();
            provider.SawOnlyTownBAfterResume = visible.SequenceEqual(["town_b"], StringComparer.Ordinal) && ids.SequenceEqual(["town_b"], StringComparer.Ordinal);
            if (requireTownBOnly && !provider.SawOnlyTownBAfterResume)
                throw new AgentHostException("eyc-companion-memory-self-test-town-not-filtered", "A previously empty Tavern must be omitted after resuming the same Native Campaign checkpoint.");
            decision = new JsonObject { ["stop"] = true, ["reason"] = "The Native candidate observation was verified." };
            return decision;
        }

        private static JsonObject NativeDecision(string action, JsonObject arguments) => new()
        {
            ["action"] = action, ["arguments"] = arguments
        };

        public void Dispose() { }
    }

    private sealed class FakeInheritedNativeMoveCompanionClient : IAgentHostCampaignNativeClient,
        IAgentHostCompanionHiringNativeClient, IAgentHostQuestDetailsNativeClient
    {
        internal List<string> Actions { get; } = new();
        private int _stateReads;

        public Task<JsonDocument> ReadStateAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            _stateReads++;
            var arrived = _stateReads >= 2;
            var atTownMenu = _stateReads >= 3;
            var state = new JsonObject
            {
                ["context"] = new JsonObject
                {
                    ["gameState"] = "MapState", ["menuId"] = atTownMenu ? "town" : null, ["encounterActive"] = false,
                    ["inquiryOpen"] = false, ["escapeMenuOpen"] = false,
                    ["timeControlMode"] = "StoppablePlay", ["captivity"] = new JsonObject { ["isCaptive"] = false }
                },
                ["location"] = new JsonObject { ["currentSettlementId"] = arrived ? "town_EW2" : null, ["targetSettlementId"] = "town_EW2", ["targetPartyId"] = null },
                ["availableMenuOptions"] = atTownMenu ? new JsonArray(
                    new JsonObject { ["id"] = "town_backstreet", ["available"] = true, ["enabled"] = true },
                    new JsonObject { ["id"] = "town_leave", ["available"] = true, ["enabled"] = true, ["isLeave"] = true }) : new JsonArray(),
                ["party"] = new JsonObject { ["members"] = 1, ["isMoving"] = !arrived, ["defaultBehavior"] = arrived ? "Hold" : "GoToSettlement", ["moveMode"] = "Point" },
                ["economy"] = new JsonObject { ["gold"] = 1000, ["renown"] = 20 },
                ["storyModeEstablishClan"] = new JsonObject { ["companions"] = new JsonObject { ["current"] = 0, ["target"] = 1 } },
                ["quests"] = new JsonArray(new JsonObject { ["id"] = QuestId }),
                ["nearbySettlements"] = new JsonArray(Settlement("town_EW2", "Town EW2", 2))
            };
            return Task.FromResult(JsonDocument.Parse(new JsonObject
            {
                ["status"] = "completed", ["campaignDay"] = 10.0, ["timeControlMode"] = "StoppablePlay", ["state"] = state
            }.ToJsonString()));
        }

        public Task<JsonDocument> ReadQuestDetailsAsync(string questId, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (questId != QuestId) throw new AgentHostException("eyc-companion-inherited-move-wrong-quest", "The inherited movement test queried an unexpected Quest.");
            return Task.FromResult(JsonDocument.Parse(new JsonObject
            {
                ["status"] = "completed", ["data"] = new JsonObject { ["questId"] = QuestId, ["journalStages"] = new JsonArray(
                    Objective("gold", 1000, 2000), Objective("partySize", 1, 25), Objective("renown", 20, 50), Objective("companions", 0, 1)) }
            }.ToJsonString()));
        }

        public Task<JsonDocument> ExecuteCampaignActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
        {
            Actions.Add(action);
            throw new AgentHostException("eyc-companion-inherited-move-unexpected-campaign-action", "The existing Native settlement move must be observed, not replaced with another map action.");
        }

        public Task<JsonDocument> ExecuteCompanionHiringActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
        {
            Actions.Add(action);
            throw new AgentHostException("eyc-companion-inherited-move-unexpected-hiring-action", "An already moving MainParty must not enter a Tavern or send a duplicate Native move action.");
        }

        private static JsonObject Objective(string description, int current, int target) => new()
        {
            ["hasTask"] = true, ["currentProgress"] = current, ["targetProgress"] = target, ["description"] = description
        };

        private static JsonObject Settlement(string id, string name, double distance) => new()
        {
            ["id"] = id, ["name"] = name, ["type"] = "town", ["distance"] = distance, ["hostile"] = false, ["underSiege"] = false
        };
    }

    private sealed class FakeInheritedNativeMoveProvider : IAgentHostDecisionProvider
    {
        internal int CallCount { get; private set; }
        internal bool SawNoDuplicateMoveAction { get; private set; }
        internal string DebugState { get; private set; } = string.Empty;
        public string ModelId => "deterministic-companion-inherited-native-move-selftest";
        public string ConfigurationSource => "harness-fake-provider";
        public Task CheckConfiguredModelAsync(CancellationToken cancellationToken) { cancellationToken.ThrowIfCancellationRequested(); return Task.CompletedTask; }

        public Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            CallCount++;
            var actions = request.GetProperty("allowedActions").EnumerateArray().ToArray();
            var controls = request.GetProperty("allowedControls").EnumerateArray().Select(control => control.GetString()).ToArray();
            var observation = request.GetProperty("observation");
            var actionNames = actions.Select(action => action.GetProperty("action").GetString()).ToArray();
            var state = observation.TryGetProperty("state", out var stateNode) && stateNode.ValueKind == JsonValueKind.Object ? stateNode : default;
            var location = state.ValueKind == JsonValueKind.Object && state.TryGetProperty("location", out var locationNode) && locationNode.ValueKind == JsonValueKind.Object ? locationNode : default;
            var party = state.ValueKind == JsonValueKind.Object && state.TryGetProperty("party", out var partyNode) && partyNode.ValueKind == JsonValueKind.Object ? partyNode : default;
            var currentSettlement = location.ValueKind == JsonValueKind.Object && location.TryGetProperty("currentSettlementId", out var currentNode) && currentNode.ValueKind == JsonValueKind.String ? currentNode.GetString() : null;
            var targetSettlement = location.ValueKind == JsonValueKind.Object && location.TryGetProperty("targetSettlementId", out var targetNode) && targetNode.ValueKind == JsonValueKind.String ? targetNode.GetString() : null;
            var partyMoving = party.ValueKind == JsonValueKind.Object && party.TryGetProperty("isMoving", out var movingNode) && movingNode.ValueKind == JsonValueKind.True;
            DebugState = "actions=" + string.Join(",", actionNames) + "; controls=" + string.Join(",", controls) + "; current=" + currentSettlement + "; target=" + targetSettlement + "; moving=" + partyMoving;
            SawNoDuplicateMoveAction = actionNames.Contains("menuSelect", StringComparer.Ordinal) &&
                !actionNames.Contains("move", StringComparer.Ordinal) && !actionNames.Contains("mapSettlementTargets", StringComparer.Ordinal) &&
                controls.Contains("stop", StringComparer.Ordinal) &&
                currentSettlement == "town_EW2";
            if (!SawNoDuplicateMoveAction)
                throw new AgentHostException("eyc-companion-inherited-move-self-test-catalog-failed", "After arrival at the already targeted Town, the model must receive the current Town menu without a duplicate move or map-target query. " + DebugState);
            return Task.FromResult(new ProviderDecisionResult("completed", ModelId, 0, 0, "selftest",
                new JsonObject { ["stop"] = true, ["reason"] = "The original Native move reached its existing target." }, "selftest", "json_schema"));
        }

        public void Dispose() { }
    }

    private sealed class FakeCompanionStopProvider : IAgentHostDecisionProvider
    {
        internal int CallCount { get; private set; }
        public string ModelId => "deterministic-establish-clan-companion-stop-selftest";
        public string ConfigurationSource => "harness-fake-provider";
        public Task CheckConfiguredModelAsync(CancellationToken cancellationToken) { cancellationToken.ThrowIfCancellationRequested(); return Task.CompletedTask; }
        public Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            CallCount++;
            if (!request.GetProperty("allowedControls").EnumerateArray().Any(control => control.GetString() == "stop"))
                throw new AgentHostException("companion-stop-selftest-control-not-listed", "The model prompt allows a safe stop, so the action catalog must list that control.");
            return Task.FromResult(new ProviderDecisionResult("completed", ModelId, 1, 1, "self-test",
                new JsonObject { ["stop"] = true, ["reason"] = "No safe action now." }, "self-test", "json_schema"));
        }
        public void Dispose() { }
    }

    private sealed class FakeInvalidCompanionActionProvider : IAgentHostDecisionProvider
    {
        internal int CallCount { get; private set; }
        internal bool SawBoundedRecoveryFeedback { get; private set; }
        public string ModelId => "deterministic-establish-clan-companion-invalid-action-selftest";
        public string ConfigurationSource => "harness-fake-provider";
        public Task CheckConfiguredModelAsync(CancellationToken cancellationToken) { cancellationToken.ThrowIfCancellationRequested(); return Task.CompletedTask; }

        public Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            CallCount++;
            var catalog = request.GetProperty("allowedActions").EnumerateArray()
                .FirstOrDefault(action => action.GetProperty("action").GetString() == "missionNavigateToAgent");
            JsonObject decision;
            if (CallCount == 1)
                decision = new JsonObject { ["action"] = "menuSelect", ["arguments"] = new JsonObject { ["MenuId"] = "town", ["OptionId"] = "town_backstreet" } };
            else if (CallCount == 2)
                decision = new JsonObject { ["action"] = "menuSelect", ["arguments"] = new JsonObject { ["MenuId"] = "town_backstreet", ["OptionId"] = "town_tavern" } };
            else
            {
                if (catalog.ValueKind != JsonValueKind.Object)
                    throw new AgentHostException("companion-invalid-action-selftest-catalog-missing", "The rejected-response test requires the exact current Native navigation catalog.");
                var feedback = request.TryGetProperty("decisionFeedback", out var feedbackNode) && feedbackNode.ValueKind == JsonValueKind.Object
                    ? feedbackNode
                    : default;
                if (CallCount == 3)
                {
                    if (feedback.ValueKind != JsonValueKind.Undefined)
                        throw new AgentHostException("companion-invalid-action-selftest-feedback-too-early", "The first bounded decision must receive the original action catalog without recovery feedback.");
                }
                else
                {
                    var allowedNames = feedback.ValueKind == JsonValueKind.Object && feedback.TryGetProperty("allowedActionNames", out var allowed) && allowed.ValueKind == JsonValueKind.Array
                        ? allowed.EnumerateArray().Select(item => item.GetString()).ToArray()
                        : Array.Empty<string?>();
                    if (!feedback.TryGetProperty("nativeActionSent", out var sent) || sent.ValueKind != JsonValueKind.False ||
                        !allowedNames.Contains("missionNavigateToAgent", StringComparer.Ordinal) ||
                        !feedback.TryGetProperty("requiredNextStep", out var nextStep) || nextStep.ValueKind != JsonValueKind.String)
                        throw new AgentHostException("companion-invalid-action-selftest-recovery-feedback-invalid", "The recovery request must state no Native action was sent and list only the current Native action catalog.");
                    SawBoundedRecoveryFeedback = true;
                }
                decision = new JsonObject { ["action"] = "missionNavigateToAgent", ["arguments"] = new JsonObject { ["AgentIndex"] = 999, ["DurationSeconds"] = 8 } };
            }
            return Task.FromResult(new ProviderDecisionResult("completed", ModelId, 1, 1, "self-test", decision, "self-test", "json_schema"));
        }

        public void Dispose() { }
    }

    private sealed class FakeMissionStopRecoveryClient : IAgentHostCampaignNativeClient, IAgentHostCompanionHiringNativeClient, IAgentHostQuestDetailsNativeClient
    {
        private bool _leftMission;
        internal List<string> Actions { get; } = new();

        public Task<JsonDocument> ReadStateAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var mission = !_leftMission;
            var state = new JsonObject
            {
                ["context"] = new JsonObject
                {
                    ["gameState"] = mission ? "MissionState" : "MapState",
                    ["menuId"] = mission ? "town_backstreet" : "",
                    ["encounteredPartyId"] = mission ? "town-a" : null,
                    ["encounterActive"] = false,
                    ["inquiryOpen"] = false,
                    ["captivity"] = new JsonObject { ["isCaptive"] = false }
                },
                ["location"] = new JsonObject { ["currentSettlementId"] = mission ? "town-a" : null },
                ["mission"] = mission ? new JsonObject
                {
                    ["active"] = true,
                    ["sceneName"] = "town_a_tavern",
                    ["nativeMissionCurrentState"] = "Running",
                    ["nativeConversationReady"] = true,
                    ["navigation"] = new JsonObject { ["active"] = false },
                    ["leave"] = new JsonObject { ["active"] = false },
                    ["nearbySceneAgents"] = new JsonArray()
                } : null,
                ["party"] = new JsonObject { ["members"] = 1, ["isMoving"] = false },
                ["economy"] = new JsonObject { ["gold"] = 1000 },
                ["storyModeEstablishClan"] = new JsonObject { ["companions"] = new JsonObject { ["current"] = 0, ["target"] = 1 } }
            };
            return Task.FromResult(JsonDocument.Parse(new JsonObject { ["status"] = "completed", ["state"] = state }.ToJsonString()));
        }

        public Task<JsonDocument> ReadQuestDetailsAsync(string questId, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (questId != QuestId) throw new AgentHostException("companion-mission-stop-selftest-wrong-quest", "The companion Mission stop recovery read an unexpected Journal.");
            var stages = new JsonArray(
                new JsonObject { ["hasTask"] = true, ["currentProgress"] = 1000, ["targetProgress"] = 2000, ["description"] = "gold" },
                new JsonObject { ["hasTask"] = true, ["currentProgress"] = 1, ["targetProgress"] = 25, ["description"] = "partySize" },
                new JsonObject { ["hasTask"] = true, ["currentProgress"] = 20, ["targetProgress"] = 50, ["description"] = "renown" },
                new JsonObject { ["hasTask"] = true, ["currentProgress"] = 0, ["targetProgress"] = 1, ["description"] = "companions" });
            return Task.FromResult(JsonDocument.Parse(new JsonObject { ["status"] = "completed", ["data"] = new JsonObject { ["questId"] = QuestId, ["journalStages"] = stages } }.ToJsonString()));
        }

        public Task<JsonDocument> ExecuteCampaignActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Actions.Add(action);
            if (action == "mapSettlementTargets")
                return Task.FromResult(JsonDocument.Parse(new JsonObject { ["status"] = "completed", ["action"] = action, ["data"] = new JsonObject { ["mapSettlementTargets"] = new JsonArray() } }.ToJsonString()));
            throw new AgentHostException("companion-mission-stop-selftest-unexpected-campaign-action", "The model issued an unexpected Campaign action while recovering from a Mission stop.");
        }

        public Task<JsonDocument> ExecuteCompanionHiringActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Actions.Add(action);
            if (action == "missionSceneAgents")
            {
                var agent = new JsonObject
                {
                    ["agentIndex"] = 4, ["heroId"] = "wanderer-a", ["occupation"] = "Wanderer",
                    ["isNotable"] = false, ["isEnemy"] = false, ["distance"] = 6.0
                };
                return Task.FromResult(JsonDocument.Parse(new JsonObject
                {
                    ["status"] = "completed", ["action"] = action,
                    ["data"] = new JsonObject { ["scope"] = "current-location-mission", ["activeAgentCount"] = 1, ["agents"] = new JsonArray(agent) }
                }.ToJsonString()));
            }
            if (action == "missionLeave")
            {
                _leftMission = true;
                return Task.FromResult(JsonDocument.Parse(new JsonObject { ["status"] = "completed", ["action"] = action, ["data"] = new JsonObject { ["nativeHandler"] = "LeaveMission" } }.ToJsonString()));
            }
            throw new AgentHostException("companion-mission-stop-selftest-unexpected-native-action", "The Mission stop recovery must choose the listed Native Leave action.");
        }
    }

    private sealed class FakeMissionStopRecoveryProvider : IAgentHostDecisionProvider
    {
        internal int CallCount { get; private set; }
        internal bool SawMissionStopRecovery { get; private set; }
        public string ModelId => "deterministic-companion-mission-stop-recovery-selftest";
        public string ConfigurationSource => "harness-fake-provider";
        public Task CheckConfiguredModelAsync(CancellationToken cancellationToken) { cancellationToken.ThrowIfCancellationRequested(); return Task.CompletedTask; }
        public Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            CallCount++;
            var actions = request.GetProperty("allowedActions").EnumerateArray().ToArray();
            var controls = request.GetProperty("allowedControls").EnumerateArray().Select(control => control.GetString()).ToArray();
            var feedback = request.TryGetProperty("decisionFeedback", out var feedbackElement) && feedbackElement.ValueKind == JsonValueKind.Object
                ? JsonNode.Parse(feedbackElement.GetRawText())?.AsObject()
                : null;
            JsonObject decision;
            if (CallCount == 1 && actions.Any(action => action.GetProperty("action").GetString() == "missionNavigateToAgent"))
                decision = new JsonObject { ["stop"] = true, ["reason"] = "The model first tries to stop inside a Mission." };
            else if (feedback is not null)
            {
                var missionLeaveListed = actions.Any(action => action.GetProperty("action").GetString() == "missionLeave");
                SawMissionStopRecovery = feedback is not null && ReadString(feedback, "kind") == "decision-rejected-before-native" &&
                    ReadString(feedback, "requiredNextStep")?.Contains("missionLeave", StringComparison.Ordinal) == true &&
                    !controls.Contains("stop") && missionLeaveListed;
                if (!SawMissionStopRecovery)
                    throw new AgentHostException("companion-mission-stop-selftest-feedback-invalid", "The recovery request must remove stop, list the current Native Leave action, and explain the rejected control.");
                decision = new JsonObject { ["action"] = "missionLeave", ["arguments"] = new JsonObject() };
            }
            else if (actions.Any(action => action.GetProperty("action").GetString() == "mapSettlementTargets"))
                decision = new JsonObject { ["action"] = "mapSettlementTargets", ["arguments"] = new JsonObject() };
            else if (controls.Contains("stop"))
                decision = new JsonObject { ["stop"] = true, ["reason"] = "The route can now be safely replanned on Map." };
            else throw new AgentHostException("companion-mission-stop-selftest-no-current-action", "The fake provider did not receive a supported current action or control.");

            return Task.FromResult(new ProviderDecisionResult("completed", ModelId, 1, 1, "self-test", decision, "self-test", "json_schema"));
        }
        public void Dispose() { }
    }
}
