using System.Diagnostics;
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal static class AgentHostEstablishClanCompanionLoop
{
    private const double MinimumCompanionNavigationProgressDistance = 0.1d;
    private const int MaxCompanionNavigationNoProgressAttempts = 2;
    private const int MaxTavernMissionStartupWaits = 20;
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
        var measuredApproach = EvaluateNavigationNoProgress(10d, 9.5d, 1, false);
        var nowInteractable = EvaluateNavigationNoProgress(1.39d, 1.39d, 1, true);
        if (stalledNavigationFirstAttempt.ExcludeTarget || stalledNavigationSecondAttempt.Attempts != 2 || !stalledNavigationSecondAttempt.ExcludeTarget ||
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
        return [
            new { scenario = "companion-navigation-stall-policy-excludes-only-after-two-no-progress-native-approaches", passed = true },
            new { scenario = "establish-clan-companion-targets-only-current-safe-unvisited-town-and-friendly-wanderer", passed = true },
            new { scenario = "establish-clan-companion-town-choice-window-pages-without-world-target-cap", passed = true, totalWorldTargets = 21, choiceWindow = SafeTownDecisionWindowSize },
            new { scenario = "establish-clan-companion-model-observation-compacts-raw-mission-agent-roster-and-preserves-current-wanderer-candidates", originalMissionBytes, projectedMissionBytes, missionBytesSaved = originalMissionBytes - projectedMissionBytes, fullPromptTokens = fullSceneTokenEstimate.TokenizerTokens, projectedPromptTokens = projectedSceneTokenEstimate.TokenizerTokens, estimatedPromptTokensSaved = fullSceneTokenEstimate.TokenizerTokens - projectedSceneTokenEstimate.TokenizerTokens, passed = true },
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
        if (ReadString(result, "status") != "completed" ||
            ReadString(result["termination"] as JsonObject, "reason") != "native-companion-journal-target-met" ||
            ReadInt(result, "actionsExecuted", 0) != expected.Length || provider.CallCount != expected.Length ||
            !client.Actions.SequenceEqual(expected, StringComparer.Ordinal) || client.Gold != 1340 || client.CompanionCount != 1 ||
            client.ActiveMissionNavigationStateReads < 2 || client.TavernMissionStartupStateReads < 2 || provider.SawActiveMissionNavigation || !provider.SawCompanionObservationProjection ||
            ReadBoolean((result["objectiveSnapshot"] as JsonObject)?["companions"] as JsonObject, "met") != true)
            throw new AgentHostException("establish-clan-companion-transport-self-test-failed", "The injected Native/Provider route did not passively settle the original Tavern Mission before decisions, preserve projected current Wanderer candidates without sending the raw scene roster or MainHero skill list, wait for Native navigation, hire one quoted Wanderer, and verify refreshed original Journal progress. status=" + ReadString(result, "status") + "; termination=" + ReadString(result["termination"] as JsonObject, "reason") + "; failureCode=" + ReadString(result, "failureCode") + "; failure=" + ReadString(result, "failure") + "; actions=" + string.Join(",", client.Actions) + "; calls=" + provider.CallCount + "; activeNavigationReads=" + client.ActiveMissionNavigationStateReads + "; startupReads=" + client.TavernMissionStartupStateReads + "; providerSawActiveNavigation=" + provider.SawActiveMissionNavigation + "; providerSawProjection=" + provider.SawCompanionObservationProjection + "; journalMet=" + ReadBoolean((result["objectiveSnapshot"] as JsonObject)?["companions"] as JsonObject, "met"));
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
            ReadInt(missionStopRecovered, "actionsExecuted", 0) != 3 || missionStopProvider.CallCount != 5 ||
            !missionStopClient.Actions.SequenceEqual(["missionSceneAgents", "missionLeave", "mapSettlementTargets"], StringComparer.Ordinal) ||
            !missionStopProvider.SawMissionStopRecovery)
            throw new AgentHostException("establish-clan-companion-mission-stop-did-not-recover-to-map", "A model stop inside a Tavern Mission must be corrected to a listed Native exit, return to Map, and only then allow safe parent replanning.");
        var movementWaitResult = await RunMapMovementWaitSelfTestAsync();
        return [
            new { scenario = "establish-clan-companion-passively-settles-friendly-tavern-mission-startup-before-decisions", startupReads = client.TavernMissionStartupStateReads, passed = true },
            new { scenario = "establish-clan-companion-passively-waits-for-native-mission-navigation-before-next-model-decision", activeNavigationReads = client.ActiveMissionNavigationStateReads, decisions = provider.CallCount, nativeActions = client.Actions.ToArray(), passed = true },
            new { scenario = "establish-clan-companion-listed-safe-stop-is-interrupted-with-zero-native-actions", decisions = stopProvider.CallCount, passed = true },
            new { scenario = "establish-clan-companion-mission-stop-is-corrected-to-native-leave-before-parent-replan", decisions = missionStopProvider.CallCount, nativeActions = missionStopClient.Actions.ToArray(), passed = true },
            await RunInvalidActionRecoverySelfTestAsync(request.RootElement),
            movementWaitResult
        ];
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
            provider.CallCount != 5 || !provider.SawBoundedRecoveryFeedback ||
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
        var visitedTowns = new HashSet<string>(StringComparer.Ordinal);
        var excludedHeroes = new HashSet<string>(StringComparer.Ordinal);
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

        try
        {
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
                    // Native map movement already selects its normal StoppablePlay mode.
                    // Watch Native visible Bandits during that natural travel. This is a
                    // bounded nearest-Town decision window: observe active Native movement
                    // During Native movement, do not spend a model decision or issue another move/time command.
                    var movementNative = JsonNode.Parse(nativeState.RootElement.GetRawText())?.AsObject()
                        ?? throw new AgentHostException("companion-movement-state-invalid", "The current Native Map observation could not be cloned for the hostile-party monitor.");
                    var movementWatch = await AgentHostNativeMapMovementMonitor.WaitAsync(
                        campaignClient,
                        campaignClient as IAgentHostBattleSimulationNativeClient,
                        movementNative,
                        moveTargetId,
                        1,
                        monitorVisibleBandits: AgentHostNativeMapMovementMonitor.HasActiveEycQuest(movementNative),
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
                            visitedTowns.Add(currentSettlementId);
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
                        if (!string.IsNullOrWhiteSpace(navigationProgressTargetHeroId) && navigationProgressStartDistance.HasValue)
                        {
                            var targetDistance = FindWandererDistance(sceneAgentsReceipt, navigationProgressTargetHeroId);
                            var targetInteractable = IsWandererInteractable(state, navigationProgressTargetHeroId);
                            if (targetDistance.HasValue && !targetInteractable)
                            {
                                var progress = EvaluateNavigationNoProgress(navigationProgressStartDistance, targetDistance,
                                    navigationNoProgressAttempts.GetValueOrDefault(navigationProgressTargetHeroId), targetInteractable);
                                var madeProgress = progress.Attempts == 0;
                                var attempts = progress.Attempts;
                                if (madeProgress) navigationNoProgressAttempts.Remove(navigationProgressTargetHeroId);
                                else navigationNoProgressAttempts[navigationProgressTargetHeroId] = attempts;
                                if (!madeProgress)
                                {
                                    selectedHeroId = null;
                                    interactTargetHeroId = null;
                                    var candidateBlocked = progress.ExcludeTarget;
                                    decisionFeedback = new JsonObject
                                    {
                                        ["kind"] = candidateBlocked ? "native-navigation-target-stalled" : "native-navigation-no-measured-approach",
                                        ["message"] = candidateBlocked
                                            ? "Two completed Native navigation attempts did not measurably reduce this Wanderer's distance. This candidate is temporarily excluded; choose another current candidate or a listed Native leave action."
                                            : "The last Native navigation ended without a measured approach. Do not repeat this target immediately; inspect the full current scene candidate catalog."
                                    };
                                    if (candidateBlocked)
                                    {
                                        excludedHeroes.Add(navigationProgressTargetHeroId);
                                        navigationNoProgressAttempts.Remove(navigationProgressTargetHeroId);
                                    }
                                }
                            }
                            else if (targetInteractable)
                            {
                                navigationNoProgressAttempts.Remove(navigationProgressTargetHeroId);
                            }
                            navigationProgressTargetHeroId = null;
                            navigationProgressStartDistance = null;
                        }
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
                        if (selectedDialogueOption == "player_companion_hire_response_2" || selectedDialogueOption == "player_companion_hire_response_1")
                            excludedHeroes.Add(selectedHeroId ?? string.Empty);
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
        private int _stage;
        private bool _navigated;
        private int _tavernMissionStartupReadsRemaining = 2;
        private int _missionNavigationActiveReadsRemaining;
        internal int ActiveMissionNavigationStateReads { get; private set; }
        internal int TavernMissionStartupStateReads { get; private set; }
        internal List<string> Actions { get; } = new();
        internal int Gold => _stage >= 8 ? 1340 : 2000;
        internal int CompanionCount => _stage >= 8 ? 1 : 0;

        public Task<JsonDocument> ReadStateAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            JsonObject state;
            if (_stage < 2)
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
                            ? new JsonArray(new JsonObject { ["agentIndex"] = 4, ["heroId"] = "wanderer-a", ["occupation"] = "Wanderer", ["isNotable"] = false, ["isEnemy"] = false, ["isInteractable"] = !navigationActive, ["distance"] = navigationActive ? 3.0 : 1.2 })
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
                        ["agents"] = new JsonArray(new JsonObject { ["agentIndex"] = 4, ["heroId"] = "wanderer-a", ["occupation"] = "Wanderer", ["isNotable"] = false, ["isEnemy"] = false, ["nativeConversationActionAvailable"] = true, ["distance"] = 6.0 })
                    };
                    return Receipt(action, data);
                case "missionNavigateToAgent": _stage = 4; _navigated = true; _missionNavigationActiveReadsRemaining = 3; data = new JsonObject { ["targetAgentIndex"] = 4, ["status"] = "navigating" }; return Receipt(action, data);
                case "missionInteract": _stage = 5; data = new JsonObject { ["targetHeroId"] = "wanderer-a", ["conversationStarted"] = true }; return Receipt(action, data);
                case "missionLeave": _stage = 9; data = new JsonObject { ["status"] = "holding-native-leave-area" }; return Receipt(action, data);
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
            ("missionSceneAgents", new JsonObject()),
            ("missionNavigateToAgent", new JsonObject { ["AgentIndex"] = 4, ["DurationSeconds"] = 8 }),
            ("missionSceneAgents", new JsonObject()),
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
            else if (CallCount == 3)
                decision = new JsonObject { ["action"] = "missionSceneAgents", ["arguments"] = new JsonObject() };
            else
            {
                if (catalog.ValueKind != JsonValueKind.Object)
                    throw new AgentHostException("companion-invalid-action-selftest-catalog-missing", "The rejected-response test requires the exact current Native navigation catalog.");
                var feedback = request.TryGetProperty("decisionFeedback", out var feedbackNode) && feedbackNode.ValueKind == JsonValueKind.Object
                    ? feedbackNode
                    : default;
                if (CallCount == 4)
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
                    ["encounterActive"] = false,
                    ["inquiryOpen"] = false,
                    ["captivity"] = new JsonObject { ["isCaptive"] = false }
                },
                ["location"] = new JsonObject { ["currentSettlementId"] = mission ? "town-a" : null },
                ["mission"] = mission ? new JsonObject
                {
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
            JsonObject decision;
            if (actions.Any(action => action.GetProperty("action").GetString() == "missionSceneAgents"))
                decision = new JsonObject { ["action"] = "missionSceneAgents", ["arguments"] = new JsonObject() };
            else if (CallCount == 2)
                decision = new JsonObject { ["stop"] = true, ["reason"] = "The model first tries to stop inside a Mission." };
            else if (CallCount == 3)
            {
                var feedback = request.TryGetProperty("decisionFeedback", out var feedbackElement) && feedbackElement.ValueKind == JsonValueKind.Object
                    ? JsonNode.Parse(feedbackElement.GetRawText())?.AsObject()
                    : null;
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
