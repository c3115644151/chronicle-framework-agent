using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal static class AgentHostEstablishClanCompanionLoop
{
    private const string QuestId = "rebuild_player_clan_storymode_quest";
    private const int MaxDecisions = 96;
    private static readonly TimeSpan MaxElapsed = TimeSpan.FromMinutes(45);
    private static readonly HashSet<string> HiringDialogueOptions = new(StringComparer.Ordinal)
    {
        "wanderer_meet_player_response2", "main_option_faction_hire",
        "player_companion_hire_response_1", "player_companion_hire_response_2"
    };

    internal static IReadOnlyList<object> RunContractSelfTests()
    {
        var candidates = FilterWandererCandidates(new JsonArray
        {
            new JsonObject { ["agentIndex"] = 4, ["heroId"] = "wanderer-a", ["occupation"] = "Wanderer", ["isNotable"] = false, ["isEnemy"] = false, ["distance"] = 6.0 },
            new JsonObject { ["agentIndex"] = 5, ["heroId"] = "notable-a", ["occupation"] = "Merchant", ["isNotable"] = true, ["isEnemy"] = false, ["distance"] = 2.0 },
            new JsonObject { ["agentIndex"] = 6, ["heroId"] = "hostile-wanderer", ["occupation"] = "Wanderer", ["isNotable"] = false, ["isEnemy"] = true, ["distance"] = 1.0 },
            new JsonObject { ["agentIndex"] = 7, ["heroId"] = null, ["occupation"] = "Wanderer", ["isNotable"] = false, ["isEnemy"] = false, ["distance"] = 3.0 }
        }, new HashSet<string>(StringComparer.Ordinal));
        if (candidates.Count != 1 || ReadString(candidates[0] as JsonObject, "heroId") != "wanderer-a")
            throw new AgentHostException("establish-clan-companion-candidate-filter-failed", "Only a current, unowned, friendly Wanderer Hero may enter the Companion objective candidate catalog.");

        var journey = new JsonObject
        {
            ["context"] = new JsonObject { ["gameState"] = "MissionState" },
            ["conversation"] = new JsonObject
            {
                ["heroId"] = "wanderer-a",
                ["options"] = new JsonArray(
                    new JsonObject { ["id"] = "main_option_faction_hire", ["clickable"] = true },
                    new JsonObject { ["id"] = "unrelated_option", ["clickable"] = true })
            }
        };
        var dialogue = BuildActionCatalog(journey, new JsonArray(), new JsonObject(), null, null, null, null, false,
            new HashSet<string>(StringComparer.Ordinal), new HashSet<string>(StringComparer.Ordinal));
        var listed = dialogue.OfType<JsonObject>().FirstOrDefault(action => ReadString(action, "action") == "dialogueSelect");
        var optionIds = listed?["argumentValues"]?["OptionId"] as JsonArray;
        if (optionIds is null || optionIds.Count != 1 || optionIds[0]?.GetValue<string>() != "main_option_faction_hire")
            throw new AgentHostException("establish-clan-companion-unrelated-dialogue-leaked", "The companion executor may expose only the source-verified hiring conversation options.");

        var safeMap = FilterSafeTowns(new JsonArray
        {
            new JsonObject { ["id"] = "town-a", ["type"] = "town", ["distance"] = 4.0, ["hostile"] = false, ["underSiege"] = false },
            new JsonObject { ["id"] = "village-a", ["type"] = "village", ["distance"] = 1.0, ["hostile"] = false, ["underSiege"] = false },
            new JsonObject { ["id"] = "town-visited", ["type"] = "town", ["distance"] = 2.0, ["hostile"] = false, ["underSiege"] = false },
            new JsonObject { ["id"] = "town-sieged", ["type"] = "town", ["distance"] = 3.0, ["hostile"] = false, ["underSiege"] = true }
        }, null, new HashSet<string>(["town-visited"], StringComparer.Ordinal));
        if (safeMap.Count != 1 || ReadString(safeMap[0] as JsonObject, "id") != "town-a")
            throw new AgentHostException("establish-clan-companion-safe-town-filter-failed", "The Companion executor must visit only newly observed safe Town targets.");

        var options = BuildActionCatalog(new JsonObject
        {
            ["context"] = new JsonObject { ["gameState"] = "MissionState" },
            ["mission"] = new JsonObject
            {
                ["nearbySceneAgents"] = new JsonArray(new JsonObject { ["agentIndex"] = 4, ["heroId"] = "wanderer-a", ["occupation"] = "Wanderer", ["isNotable"] = false, ["isEnemy"] = false, ["isInteractable"] = true, ["distance"] = 1.2 })
            }
        }, new JsonArray(), new JsonObject(), null,
            new JsonObject { ["data"] = new JsonObject { ["agents"] = new JsonArray(new JsonObject { ["agentIndex"] = 4, ["heroId"] = "wanderer-a", ["occupation"] = "Wanderer", ["isNotable"] = false, ["isEnemy"] = false, ["distance"] = 6.0 }) } },
            "wanderer-a", null, false, new HashSet<string>(StringComparer.Ordinal), new HashSet<string>(StringComparer.Ordinal));
        if (options.Count != 1 || ReadString(options[0] as JsonObject, "action") != "missionInteract")
            throw new AgentHostException("establish-clan-companion-native-interaction-route-failed", "An observed, interactable local Wanderer must use Native Agent interaction rather than an invented conversation action.");

        return [
            new { scenario = "establish-clan-companion-targets-only-current-safe-unvisited-town-and-friendly-wanderer", passed = true },
            new { scenario = "establish-clan-companion-dialogue-catalog-excludes-unrelated-native-options", passed = true },
            new { scenario = "establish-clan-companion-nearby-target-uses-native-interact", passed = true }
        ];
    }

    internal static async Task<IReadOnlyList<object>> RunTransportSelfTestsAsync()
    {
        var client = new FakeCompanionClient();
        var provider = new FakeCompanionProvider();
        using var request = JsonDocument.Parse("{\"runId\":\"establish-clan-companion-selftest\",\"goal\":\"Reach the original Journal companion target.\",\"maxDecisions\":24,\"maxElapsedSeconds\":60}");
        var result = await RunAsync(request.RootElement, client, client, provider, CancellationToken.None);
            var expected = new[] { "menuSelect", "menuSelect", "missionSceneAgents", "missionNavigateToAgent", "missionSceneAgents", "missionInteract", "dialogueSelect", "dialogueSelect", "dialogueSelect" };
        if (ReadString(result, "status") != "completed" ||
            ReadString(result["termination"] as JsonObject, "reason") != "native-companion-journal-target-met" ||
            ReadInt(result, "actionsExecuted", 0) != expected.Length || provider.CallCount != expected.Length ||
            !client.Actions.SequenceEqual(expected, StringComparer.Ordinal) || client.Gold != 1340 || client.CompanionCount != 1 ||
            ReadBoolean((result["objectiveSnapshot"] as JsonObject)?["companions"] as JsonObject, "met") != true)
            throw new AgentHostException("establish-clan-companion-transport-self-test-failed", "The injected Native/Provider route did not follow the observed Tavern path, hire one quoted Wanderer, and verify refreshed original Journal progress. status=" + ReadString(result, "status") + "; termination=" + ReadString(result["termination"] as JsonObject, "reason") + "; failureCode=" + ReadString(result, "failureCode") + "; failure=" + ReadString(result, "failure") + "; actions=" + string.Join(",", client.Actions) + "; calls=" + provider.CallCount + "; journalMet=" + ReadBoolean((result["objectiveSnapshot"] as JsonObject)?["companions"] as JsonObject, "met"));
        return [new { scenario = "establish-clan-companion-runtime-observe-travel-tavern-native-dialogue-hire-and-journal-verify", decisions = provider.CallCount, nativeActions = client.Actions.ToArray(), passed = true }];
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
        var maxSeconds = Math.Clamp(ReadInt(request, "maxElapsedSeconds", (int)MaxElapsed.TotalSeconds), 10, 3600);
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
        var visitedHeroes = new HashSet<string>(StringComparer.Ordinal);
        var start = Stopwatch.GetTimestamp();
        using var elapsed = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        elapsed.CancelAfter(TimeSpan.FromSeconds(maxSeconds));

        try
        {
            await provider.CheckConfiguredModelAsync(elapsed.Token);
            for (var iteration = 0; iteration < maxDecisions - decisions; iteration++)
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
                if (ReadBoolean(context?["captivity"] as JsonObject, "isCaptive") || ReadBoolean(context, "encounterActive"))
                    return BuildResult("interrupted", "campaign-interruption", "Captivity or an encounter interrupts the Tavern hiring route and must be handled by its own Native subflow.", "companion-campaign-interruption", state);

                var journal = await ReadJournalAsync(companionClient, elapsed.Token);
                var objective = AgentHostEstablishYourClanGoalLoop.BuildObjectiveSnapshot(journal);
                var companionObjective = objective["companions"] as JsonObject
                    ?? throw new AgentHostException("companion-objective-missing", "The original EYC Journal omitted its Companion target.");
                if (ReadBoolean(companionObjective, "met"))
                    return BuildResult("completed", "native-companion-journal-target-met", null, null, state, journal, objective);
                var liveCompanions = ReadDouble(state["storyModeEstablishClan"]?["companions"] as JsonObject, "current");
                var journalTarget = ReadDouble(companionObjective, "target");
                var liveGoalAhead = liveCompanions >= journalTarget && !double.IsNaN(journalTarget);

                var location = state["location"] as JsonObject;
                var currentSettlementId = ReadString(location, "currentSettlementId");
                var targetSettlementId = ReadString(location, "targetSettlementId");
                var menuId = ReadString(context, "menuId");
                if (liveGoalAhead && gameState == "MapState" && string.IsNullOrWhiteSpace(menuId))
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
                if (gameState == "MissionState" && state["conversation"] is JsonObject conversation && ReadString(conversation, "heroId") is string conversationHeroId)
                    selectedHeroId = conversationHeroId;
                if (missionTransitionPending && (gameState != "MissionState" || state["mission"]?["leave"] is JsonObject leaveState && !ReadBoolean(leaveState, "active")))
                    missionTransitionPending = false;

                var nativeMoveActive = !string.IsNullOrWhiteSpace(moveTargetId) &&
                    (ReadBoolean(state["party"] as JsonObject, "isMoving") || string.Equals(targetSettlementId, moveTargetId, StringComparison.Ordinal));
                if (nativeMoveActive) moveStartPending = false;
                var menuArrivalPending = gameState == "MapState" && !string.IsNullOrWhiteSpace(moveTargetId) &&
                    string.Equals(currentSettlementId, moveTargetId, StringComparison.Ordinal) && string.IsNullOrWhiteSpace(menuId);
                var mapMovementPending = gameState == "MapState" && !string.IsNullOrWhiteSpace(moveTargetId) &&
                    !string.Equals(currentSettlementId, moveTargetId, StringComparison.Ordinal) && (nativeMoveActive || moveStartPending);

                var missionNavigationActive = gameState == "MissionState" && ReadBoolean(state["mission"]?["navigation"] as JsonObject, "active");
                var missionLeaveActive = gameState == "MissionState" && ReadBoolean(state["mission"]?["leave"] as JsonObject, "active");
                var controls = BuildControlCatalog(mapMovementPending || menuArrivalPending, missionNavigationActive, missionLeaveActive || missionTransitionPending);
                var catalog = BuildActionCatalog(state, journal, objective, safeTowns, sceneAgentsReceipt, selectedHeroId,
                    moveTargetId, mapMovementPending || menuArrivalPending || missionNavigationActive || missionLeaveActive || missionTransitionPending, visitedTowns, visitedHeroes);
                if (liveGoalAhead)
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
                    ["previousActionReceipt"] = trace.LastOrDefault() is JsonObject lastTrace ? lastTrace["nativeReceipt"]?.DeepClone() : null
                };
                var decision = await AgentHostDecisionCycle.DecideEstablishClanCompanionAsync(provider, modelRequest, elapsed.Token);
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

                if (ReadString(decision.Decision, "control") == "stop")
                    return BuildResult("interrupted", "companion-route-unavailable", ReadString(decision.Decision, "reason") ?? "The model stopped because no safe current Native action remained.", "companion-model-stopped", state, journal, objective);

                if (ReadString(decision.Decision, "control") == "observeAgain")
                {
                    if (!controls.Any(control => control?.GetValue<string>() == "observeAgain"))
                        throw new AgentHostException("companion-observe-not-allowed", "Passive observation is allowed only while Native movement/navigation/leave transition is active.");
                    var waitSeconds = ReadInt(decision.Decision, "waitSeconds", 0);
                    if (waitSeconds is < 1 or > 10) throw new AgentHostException("companion-observe-interval-invalid", "observeAgain requires a bounded 1-10 second host-side wait.");
                    await Task.Delay(TimeSpan.FromSeconds(waitSeconds), elapsed.Token);
                    using var afterWait = await campaignClient.ReadStateAsync(elapsed.Token);
                    var waitedState = ReadState(afterWait.RootElement);
                    trace.Add(BuildStep(decisions, observation, decision.Decision, null, waitedState, "bounded-native-observation"));
                    continue;
                }

                if (!TryResolveAction(decision.Decision, catalog, state, sceneAgentsReceipt, selectedHeroId, moveTargetId,
                        mapMovementPending || menuArrivalPending || missionNavigationActive || missionLeaveActive || missionTransitionPending,
                        out var action, out var arguments, out var selectedSettlementId, out var targetHeroId, out var rejection))
                {
                    trace.Add(BuildStep(decisions, observation, decision.Decision, null, state, "rejected",
                        new JsonObject { ["kind"] = "decision-rejected-before-native", ["message"] = rejection }));
                    continue;
                }

                JsonDocument response;
                var actionStarted = DateTime.UtcNow.ToString("O");
                if (action is "mapSettlementTargets" or "move")
                    response = await campaignClient.ExecuteCampaignActionAsync(action, arguments, elapsed.Token);
                else
                    response = await companionClient.ExecuteCompanionHiringActionAsync(action, arguments, elapsed.Token);
                using (response)
                {
                    var receipt = JsonNode.Parse(response.RootElement.GetRawText())?.AsObject()
                        ?? throw new AgentHostException("companion-native-response-invalid", "Native returned no Companion action receipt.");
                    if (ReadString(receipt, "status") != "completed")
                    {
                        trace.Add(BuildStep(decisions, observation, decision.Decision, SafeReceipt(receipt, action, selectedSettlementId, targetHeroId), state, actionStarted));
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
                        moveTargetId = targetSettlementId;
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
                        sceneAgentsReceipt = receipt.DeepClone() as JsonObject;
                    else if (action == "missionNavigateToAgent")
                    {
                        selectedHeroId = targetHeroId;
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
                    else if (action == "dialogueSelect")
                    {
                        var selectedDialogueOption = ReadString(arguments, "optionId");
                        if (selectedDialogueOption == "player_companion_hire_response_2" || selectedDialogueOption == "player_companion_hire_response_1")
                            visitedHeroes.Add(selectedHeroId ?? string.Empty);
                        if (selectedDialogueOption == "player_companion_hire_response_2")
                        {
                            selectedHeroId = null;
                            interactTargetHeroId = null;
                            sceneAgentsReceipt = null;
                        }
                    }

                    using var refreshed = await campaignClient.ReadStateAsync(elapsed.Token);
                    var afterState = ReadState(refreshed.RootElement);
                    trace.Add(BuildStep(decisions, observation, decision.Decision, SafeReceipt(receipt, action, selectedSettlementId, targetHeroId), afterState, actionStarted));
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

    private static JsonArray BuildActionCatalog(JsonObject state, JsonArray journal, JsonObject objective, JsonArray? safeTowns,
        JsonObject? sceneAgentsReceipt, string? selectedHeroId, string? moveTargetId, bool pending,
        HashSet<string> visitedTowns, HashSet<string> visitedHeroes)
    {
        var catalog = new JsonArray();
        var context = state["context"] as JsonObject;
        var gameState = ReadString(context, "gameState");
        if (pending || ReadBoolean(context, "inquiryOpen") || ReadBoolean(context, "escapeMenuOpen") ||
            ReadBoolean(context, "encounterActive") || ReadBoolean(context?["captivity"] as JsonObject, "isCaptive")) return catalog;

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
                var action = new JsonObject { ["action"] = "move", ["arguments"] = new JsonArray("SettlementId") };
                action["argumentValues"] = new JsonObject { ["SettlementId"] = new JsonArray(safeTowns.OfType<JsonObject>()
                    .Select(town => (JsonNode?)JsonValue.Create(ReadString(town, "id"))).ToArray()) };
                catalog.Add(action);
            }
            return catalog;
        }

        if (gameState != "MissionState") return catalog;
        var conversation = state["conversation"] as JsonObject;
        if (conversation is not null)
        {
            var currentOptions = conversation["options"] as JsonArray ?? new JsonArray();
            var allowedOptions = currentOptions.OfType<JsonObject>()
                .Where(option => HiringDialogueOptions.Contains(ReadString(option, "id") ?? string.Empty) && ReadBoolean(option, "clickable"))
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

        var candidates = FilterWandererCandidates(sceneAgentsReceipt?["data"]?["agents"] as JsonArray, visitedHeroes);
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
        var nearbyInteractable = candidates.OfType<JsonObject>().Where(candidate => localAgents.OfType<JsonObject>().Any(local =>
            ReadString(local, "heroId") == ReadString(candidate, "heroId") && ReadBoolean(local, "isInteractable"))).ToArray();
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
            case "dialogueContinue" when supplied.Count == 0:
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
                var agentIndex = ReadInt(supplied, "AgentIndex", -1);
                if (agentIndex < 0 || !listed["argumentValues"]?["AgentIndex"]?.AsArray().Any(value => value?.GetValue<int>() == agentIndex) == true) return false;
                var candidate = (sceneAgentsReceipt?["data"]?["agents"] as JsonArray)?.OfType<JsonObject>().FirstOrDefault(item => ReadInt(item, "agentIndex", -1) == agentIndex &&
                    ReadString(item, "occupation") == "Wanderer" && !ReadBoolean(item, "isEnemy") && !ReadBoolean(item, "isNotable") && !string.IsNullOrWhiteSpace(ReadString(item, "heroId")));
                var currentConversationHero = ReadString(state["conversation"] as JsonObject, "heroId");
                if (candidate is null || (selectedHeroId is not null && ReadString(candidate, "heroId") != selectedHeroId) || currentConversationHero is not null) return false;
                targetHeroId = ReadString(candidate, "heroId");
                arguments["agentIndex"] = agentIndex;
                if (action == "missionNavigateToAgent")
                {
                    var duration = ReadInt(supplied, "DurationSeconds", -1);
                    if (!listed["argumentValues"]?["DurationSeconds"]?.AsArray().Any(value => value?.GetValue<int>() == duration) == true) return false;
                    arguments["durationSeconds"] = duration;
                }
                else if (!(state["mission"]?["nearbySceneAgents"] as JsonArray)?.OfType<JsonObject>().Any(local => ReadInt(local, "agentIndex", -1) == agentIndex && ReadBoolean(local, "isInteractable")) == true)
                    return false;
                return true;
            case "dialogueSelect":
                var currentOptions = state["conversation"]?["options"] as JsonArray;
                var selectedOption = ReadString(supplied, "OptionId");
                if (selectedOption is null || !HiringDialogueOptions.Contains(selectedOption) ||
                    !listed["argumentValues"]?["OptionId"]?.AsArray().Any(value => value?.GetValue<string>() == selectedOption) == true ||
                    !currentOptions?.OfType<JsonObject>().Any(option => ReadString(option, "id") == selectedOption && ReadBoolean(option, "clickable")) == true) return false;
                arguments["optionId"] = selectedOption;
                targetHeroId = ReadString(state["conversation"] as JsonObject, "heroId");
                return targetHeroId is not null;
            default:
                return false;
        }
    }

    private static JsonArray FilterWandererCandidates(JsonArray? agents, HashSet<string> visitedHeroes)
    {
        var result = new JsonArray();
        if (agents is null) return result;
        foreach (var agent in agents.OfType<JsonObject>())
        {
            var id = ReadString(agent, "heroId");
            if (string.IsNullOrWhiteSpace(id) || ReadString(agent, "occupation") != "Wanderer" || ReadBoolean(agent, "isNotable") || ReadBoolean(agent, "isEnemy") || visitedHeroes.Contains(id)) continue;
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

    private static JsonArray BuildControlCatalog(bool mapMovementPending, bool missionNavigationActive, bool missionLeaveActive) =>
        mapMovementPending || missionNavigationActive || missionLeaveActive ? new JsonArray("observeAgain") : new JsonArray();

    private static JsonObject BuildObservation(JsonObject state, JsonArray journal, JsonObject objective, JsonArray? safeTowns,
        JsonObject? sceneAgentsReceipt, string? selectedHeroId, string? interactTargetHeroId, int traceCount)
    {
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
            ["state"] = state.DeepClone(),
            ["journalObjectiveSnapshot"] = journal.DeepClone(),
            ["objectiveSnapshot"] = objective.DeepClone(),
            ["visibleSafeTownTargets"] = safeTowns?.DeepClone(),
            ["sceneObservationScope"] = ReadString(sceneAgentsReceipt?["data"] as JsonObject, "scope"),
            ["sceneAgentCount"] = ReadInt(sceneAgentsReceipt?["data"] as JsonObject, "activeAgentCount", 0),
            ["currentSceneWandererCandidates"] = compactCandidates,
            ["nearbyInteractableWanderers"] = nearbyCandidates,
            ["selectedWandererHeroId"] = selectedHeroId,
            ["lastInteractionHeroId"] = interactTargetHeroId,
            ["priorStepCount"] = traceCount
        };
    }

    private static JsonObject SafeReceipt(JsonObject receipt, string action, string? targetSettlementId, string? targetHeroId) => new()
    {
        ["action"] = action,
        ["status"] = ReadString(receipt, "status"),
        ["targetSettlementId"] = targetSettlementId,
        ["targetHeroId"] = targetHeroId,
        ["data"] = receipt["data"]?.DeepClone()
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

    private sealed class FakeCompanionClient : IAgentHostCampaignNativeClient, IAgentHostCompanionHiringNativeClient
    {
        private int _stage;
        private bool _navigated;
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
            else
            {
                state = BuildState("MissionState", null, new JsonArray());
                if (_stage == 5)
                    state["conversation"] = BuildConversation("wanderer-a", "Wanderer business offer", "wanderer_meet_player_response2");
                else if (_stage == 6)
                    state["conversation"] = BuildConversation("wanderer-a", "Company offer", "main_option_faction_hire");
                else if (_stage == 7)
                    state["conversation"] = BuildConversation("wanderer-a", "Wanderer asks for 660 denars", "player_companion_hire_response_1", "player_companion_hire_response_2");
                else if (_stage >= 4)
                    state["mission"] = new JsonObject
                    {
                        ["nearbySceneAgents"] = _navigated
                            ? new JsonArray(new JsonObject { ["agentIndex"] = 4, ["heroId"] = "wanderer-a", ["occupation"] = "Wanderer", ["isNotable"] = false, ["isEnemy"] = false, ["isInteractable"] = true, ["distance"] = 1.2 })
                            : new JsonArray(),
                        ["navigation"] = new JsonObject { ["active"] = false }, ["leave"] = null
                    };
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
                        ["agents"] = new JsonArray(new JsonObject { ["agentIndex"] = 4, ["heroId"] = "wanderer-a", ["occupation"] = "Wanderer", ["isNotable"] = false, ["isEnemy"] = false, ["distance"] = 6.0 })
                    };
                    return Receipt(action, data);
                case "missionNavigateToAgent": _stage = 4; _navigated = true; data = new JsonObject { ["targetAgentIndex"] = 4, ["status"] = "arrived" }; return Receipt(action, data);
                case "missionInteract": _stage = 5; data = new JsonObject { ["targetHeroId"] = "wanderer-a", ["conversationStarted"] = true }; return Receipt(action, data);
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
            return new JsonObject { ["context"] = context, ["availableMenuOptions"] = menuOptions, ["party"] = new JsonObject { ["isMoving"] = false } };
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
            ("dialogueSelect", new JsonObject { ["OptionId"] = "player_companion_hire_response_1" })
        ];
        internal int CallCount { get; private set; }
        public string ModelId => "deterministic-establish-clan-companion-selftest";
        public string ConfigurationSource => "harness-fake-provider";
        public Task CheckConfiguredModelAsync(CancellationToken cancellationToken) { cancellationToken.ThrowIfCancellationRequested(); return Task.CompletedTask; }
        public Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
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
}
