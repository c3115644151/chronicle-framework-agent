using System.Diagnostics;
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal static class AgentHostCampaignLoop
{
    internal const int MaxCumulativeDecisions = 320;
    private const int MaxRejectedDecisions = 2;
    private const int MaxUnsupportedEycScopeReconsiderations = 1;
    internal static readonly HashSet<string> ApprovedActions = new(StringComparer.Ordinal)
    {
        "mapSettlementTargets", "move", "menuSelect", "talkToSettlementHero", "dialogueSelect", "dialogueContinue",
        "questDetails", "tradeOptions", "trade", "tradeConfirm", "tradeCancel", "tradeCancelChanges", "barterOptions", "barterAutoBalance", "barterOffer", "barterCancel", "inventoryOpen", "heroEquipmentOptions", "inventoryCancel", "incidentSelect"
    };
    internal static readonly HashSet<string> BattleSimulationActions = new(StringComparer.Ordinal)
    {
        "mapPartyTargets", "pursue", "dialogueSelect", "dialogueContinue", "menuSelect", "battleSkip", "battleFinish", "partyTakeAll", "partyLootTransferOne", "partyScreenDone", "inventoryTakeAll", "inventoryDone"
    };
    internal static readonly HashSet<string> CaptivityRecoveryActions = new(StringComparer.Ordinal) { "resume", "menuSelect" };
    internal static readonly HashSet<string> GoldSaleActions = new(StringComparer.Ordinal)
    {
        "mapSettlementTargets", "move", "menuSelect", "tradeOptions", "trade", "tradeConfirm", "tradeCancel", "tradeCancelChanges"
    };
    internal static readonly HashSet<string> RecruitmentActions = new(StringComparer.Ordinal) { "recruitOptions", "recruit", "prisonerRecruitmentOptions", "recruitPrisoner" };
    internal static readonly HashSet<string> CompanionHiringActions = new(StringComparer.Ordinal) { "missionSceneAgents", "missionNavigateToAgent", "missionInteract", "missionLeave" };
    internal static readonly HashSet<string> TrainingIssueActions = new(StringComparer.Ordinal) { "partyUpgradeOptions", "upgradeTroop" };
    internal static readonly HashSet<string> AllSupportedActions = new(ApprovedActions.Concat(BattleSimulationActions).Concat(GoldSaleActions).Concat(RecruitmentActions).Concat(CompanionHiringActions).Concat(TrainingIssueActions), StringComparer.Ordinal);

    internal static IReadOnlyList<object> RunContractSelfTests()
    {
        var results = new List<object>();
        results.AddRange(AgentHostMapIncidentLoop.RunContractSelfTestsAsync().GetAwaiter().GetResult());
        results.AddRange(AgentHostStoryModeBootstrapLoop.RunContractSelfTests());
        if (new[] { 0, 30, 80, 159, 319 }.Any(prior => prior >= GetCumulativeDecisionLimit(MaxCumulativeDecisions)) ||
            GetCumulativeDecisionLimit(8) != 8 || GetCumulativeDecisionLimit(0) != 1 || GetCumulativeDecisionLimit(1000) != MaxCumulativeDecisions)
            throw new AgentHostException("campaign-loop-self-test-child-decision-limit-shrank", "Nested objective loops must keep the parent's cumulative decision ceiling and carry prior decisions separately.");
        results.Add(new { scenario = "campaign-loop-nested-objectives-share-cumulative-decision-ceiling", passed = true });
        var initialActions = new JsonArray();
        var initialControls = BuildGoalScopeClassificationControls();
        if (initialActions.Count != 0 || initialControls.Count != 5 ||
            !initialControls.Any(control => control?.GetValue<string>() == "supportedMapArrivalGoal") ||
            !initialControls.Any(control => control?.GetValue<string>() == "supportedVillageToolsQuestGoal") ||
            !initialControls.Any(control => control?.GetValue<string>() == "supportedBattleSimulationGoal") ||
            !initialControls.Any(control => control?.GetValue<string>() == "supportedBattleAndCaptivityGoal") ||
            !initialControls.Any(control => control?.GetValue<string>() == "unsupportedGoal"))
            throw new AgentHostException("campaign-loop-self-test-goal-scope-gate-failed", "The first decision must classify the complete user goal before any Native action is available.");
        results.Add(new { scenario = "campaign-loop-requires-goal-scope-classification-before-native-actions", passed = true });
        var storyQuestControls = BuildGoalScopeClassificationControls(new JsonObject
        {
            ["quests"] = new JsonArray(new JsonObject { ["id"] = "rebuild_player_clan_storymode_quest" })
        });
        var unrelatedQuestControls = BuildGoalScopeClassificationControls(new JsonObject
        {
            ["quests"] = new JsonArray(new JsonObject { ["id"] = "issue_64_quest" })
        });
        var captiveControls = BuildGoalScopeClassificationControls(new JsonObject
        {
            ["context"] = new JsonObject { ["captivity"] = new JsonObject { ["isCaptive"] = true } },
            ["quests"] = new JsonArray(new JsonObject { ["id"] = "rebuild_player_clan_storymode_quest" })
        });
        if (storyQuestControls.Count != 7 || !storyQuestControls.Any(control => control?.GetValue<string>() == "supportedEstablishYourClanGoal") ||
            !storyQuestControls.Any(control => control?.GetValue<string>() == "supportedEstablishClanGoldSaleGoal") ||
            unrelatedQuestControls.Count != 5 || unrelatedQuestControls.Any(control => control?.GetValue<string>() == "supportedEstablishYourClanGoal") ||
            unrelatedQuestControls.Any(control => control?.GetValue<string>() == "supportedEstablishClanGoldSaleGoal") ||
            captiveControls.Count != 8 || !captiveControls.Any(control => control?.GetValue<string>() == "supportedCaptivityRecoveryGoal") ||
            !captiveControls.Any(control => control?.GetValue<string>() == "supportedEstablishClanGoldSaleGoal"))
            throw new AgentHostException("campaign-loop-self-test-establish-clan-gate-leaked", "The StoryMode planner classification must be listed only when the exact original Quest is currently observed.");
        results.Add(new { scenario = "campaign-loop-offers-storymode-planner-and-captivity-recovery-only-for-observed-prerequisites", passed = true });

        var postTutorialTrainingField = new JsonObject
        {
            ["context"] = new JsonObject { ["gameState"] = "MapState", ["menuId"] = "training_field_menu" },
            ["location"] = new JsonObject { ["currentSettlementId"] = "tutorial_training_field" },
            ["storyModeEstablishClanStatus"] = new JsonObject
            {
                ["status"] = "unknown", ["questId"] = "rebuild_player_clan_storymode_quest", ["tutorialCompleted"] = true
            }
        };
        var postTutorialControls = BuildGoalScopeClassificationControls(postTutorialTrainingField);
        var preTutorialTrainingField = (JsonObject)postTutorialTrainingField.DeepClone();
        preTutorialTrainingField["storyModeEstablishClanStatus"]!["status"] = "storymode-not-activated";
        preTutorialTrainingField["storyModeEstablishClanStatus"]!["tutorialCompleted"] = false;
        var preTutorialControls = BuildGoalScopeClassificationControls(preTutorialTrainingField);
        var wrongMenuTrainingField = (JsonObject)postTutorialTrainingField.DeepClone();
        wrongMenuTrainingField["context"]!["menuId"] = "town";
        var wrongMenuControls = BuildGoalScopeClassificationControls(wrongMenuTrainingField);
        if (postTutorialControls.Count != 6 || !postTutorialControls.Any(control => control?.GetValue<string>() == "supportedEstablishYourClanGoal") ||
            postTutorialControls.Any(control => control?.GetValue<string>() == "supportedEstablishClanGoldSaleGoal") ||
            preTutorialControls.Any(control => control?.GetValue<string>() == "supportedEstablishYourClanGoal") ||
            wrongMenuControls.Any(control => control?.GetValue<string>() == "supportedEstablishYourClanGoal"))
            throw new AgentHostException("campaign-loop-self-test-post-skip-bootstrap-scope-failed", "The EYC goal may bootstrap only after Tutorial completion at the original training-field MapState; Gold objective planning still requires the active quest.");
        results.Add(new { scenario = "campaign-loop-offers-eyc-bootstrap-only-after-tutorial-at-training-field-map", passed = true });
        var allScopeClassifierPrompt = AgentHostDecisionCycle.BuildCampaignGoalClassificationPrompt(new JsonObject
        {
            ["allowedControls"] = new JsonArray("supportedMapArrivalGoal", "supportedVillageToolsQuestGoal", "supportedBattleSimulationGoal",
                "supportedBattleAndCaptivityGoal", "supportedEstablishYourClanGoal", "supportedCaptivityRecoveryGoal",
                "supportedEstablishClanGoldSaleGoal", "unsupportedGoal")
        });
        if (!AgentHostDecisionCycle.CampaignGoalClassificationPrompt.Contains("intermediate steps", StringComparison.Ordinal) ||
            !AgentHostDecisionCycle.CampaignGoalClassificationPrompt.Contains("not currently visible", StringComparison.Ordinal) ||
            !allScopeClassifierPrompt.Contains("BattleSimulation", StringComparison.Ordinal) ||
            !allScopeClassifierPrompt.Contains("rebuild_player_clan_storymode_quest", StringComparison.Ordinal) ||
            !allScopeClassifierPrompt.Contains("currently sellable Goods item", StringComparison.Ordinal))
            throw new AgentHostException("campaign-loop-self-test-classifier-confuses-scope-with-availability", "Goal scope classification must treat supported actions as intermediate steps and not depend on target availability.");
        results.Add(new { scenario = "campaign-loop-classification-is-independent-of-target-availability", passed = true });
        var activeEycGoal = "Autonomously complete the exact currently active original StoryMode Establish Your Clan quest.";
        var activeEycControls = BuildGoalScopeClassificationControls(new JsonObject
        {
            ["quests"] = new JsonArray(new JsonObject { ["id"] = "rebuild_player_clan_storymode_quest" })
        });
        var mapRefreshOnlyControls = BuildGoalScopeClassificationControls(new JsonObject
        {
            ["quests"] = new JsonArray(new JsonObject { ["id"] = "rebuild_player_clan_storymode_quest" })
        }, safeSettlementArrivalOnly: true);
        if (mapRefreshOnlyControls.Count != 2 ||
            !mapRefreshOnlyControls.Any(control => control?.GetValue<string>() == "supportedMapArrivalGoal") ||
            !mapRefreshOnlyControls.Any(control => control?.GetValue<string>() == "unsupportedGoal") ||
            mapRefreshOnlyControls.Any(control => control?.GetValue<string>() == "supportedEstablishYourClanGoal"))
            throw new AgentHostException("campaign-loop-self-test-settlement-refresh-scope-leaked", "A safe-settlement refresh may classify only bounded map arrival; it cannot recursively select an already blocked EYC route.");
        results.Add(new { scenario = "campaign-loop-settlement-refresh-only-classifies-native-map-arrival", passed = true });
        if (!ShouldReconsiderUnsupportedEycScope(activeEycGoal, activeEycControls, false, 0) ||
            ShouldReconsiderUnsupportedEycScope("Sell a sword to a nearby merchant.", activeEycControls, false, 0) ||
            ShouldReconsiderUnsupportedEycScope(activeEycGoal, BuildGoalScopeClassificationControls(), false, 0) ||
            ShouldReconsiderUnsupportedEycScope(activeEycGoal, activeEycControls, false, MaxUnsupportedEycScopeReconsiderations))
            throw new AgentHostException("campaign-loop-self-test-eyc-scope-reconsideration-gate-failed", "Only an explicit Establish Your Clan request with its exact Native quest scope currently listed may receive one bounded unsupported-classification retry.");
        var eycClassifierRequest = new JsonObject { ["goal"] = activeEycGoal, ["allowedControls"] = activeEycControls.DeepClone() };
        var eycClassifierPrompt = AgentHostDecisionCycle.BuildCampaignGoalClassificationPrompt(eycClassifierRequest);
        if (!eycClassifierPrompt.Contains("Multi-step execution within this exact quest is not a reason to choose unsupportedGoal", StringComparison.Ordinal))
            throw new AgentHostException("campaign-loop-self-test-eyc-multistep-classification-guidance-missing", "The classifier must explicitly recognize the exact active multi-objective StoryMode quest as one supported high-level goal.");
        results.Add(new { scenario = "campaign-loop-allows-one-bounded-reconsideration-for-explicit-active-eyc-multistep-scope", passed = true });
        var postClassificationActions = BuildActionCatalog(null, moving: false, goalVerified: false);
        var postClassificationControls = BuildControlCatalog(moving: false, goalVerified: false);
        if (postClassificationActions.Count != 1 || ReadString(postClassificationActions[0] as JsonObject, "action") != "mapSettlementTargets" || postClassificationControls.Count != 0 ||
            !AgentHostDecisionCycle.CampaignSystemPrompt.Contains("MUST choose that action before any other action or completion proposal", StringComparison.Ordinal))
            throw new AgentHostException("campaign-loop-self-test-target-query-not-required", "After supported scope, the Native target query must precede all other actions and completion proposals.");
        results.Add(new { scenario = "campaign-loop-target-query-precedes-move-and-completion", passed = true });

        var safeTargets = BuildSafeVisibleTargets(new JsonObject
        {
            ["status"] = "completed",
            ["data"] = new JsonObject
            {
                ["mapSettlementTargets"] = new JsonArray
                {
                    new JsonObject { ["id"] = "safe", ["name"] = "Safe Town", ["type"] = "town", ["distance"] = 4.0, ["hostile"] = false, ["underSiege"] = false },
                    new JsonObject { ["id"] = "hostile", ["name"] = "Hostile Town", ["distance"] = 5.0, ["hostile"] = true, ["underSiege"] = false },
                    new JsonObject { ["id"] = "siege", ["name"] = "Besieged Town", ["distance"] = 6.0, ["hostile"] = false, ["underSiege"] = true },
                    new JsonObject { ["id"] = "unknown-risk", ["name"] = "Unknown Risk Town", ["distance"] = 7.0 },
                    new JsonObject { ["id"] = "current", ["name"] = "Current Town", ["distance"] = 0.5, ["hostile"] = false, ["underSiege"] = false }
                }
            }
        });
        if (safeTargets.Count != 1 || ReadString(safeTargets[0] as JsonObject, "id") != "safe")
            throw new AgentHostException("campaign-loop-self-test-target-filter-failed", "Only non-hostile, non-besieged, non-current visible settlements may be offered.");
        results.Add(new { scenario = "campaign-loop-filters-unsafe-current-and-unknown-risk-targets", passed = true });
        var settlementOnlyTargets = BuildSafeVisibleTargets(new JsonObject
        {
            ["status"] = "completed",
            ["data"] = new JsonObject
            {
                ["mapSettlementTargets"] = new JsonArray
                {
                    new JsonObject { ["id"] = "training-field", ["name"] = "Training Field", ["type"] = "other", ["distance"] = 2.0, ["hostile"] = false, ["underSiege"] = false },
                    new JsonObject { ["id"] = "safe-village", ["name"] = "Safe Village", ["type"] = "village", ["distance"] = 4.0, ["hostile"] = false, ["underSiege"] = false }
                }
            }
        }, settlementsOnly: true);
        if (settlementOnlyTargets.Count != 1 || ReadString(settlementOnlyTargets[0] as JsonObject, "id") != "safe-village")
            throw new AgentHostException("campaign-loop-self-test-settlement-only-target-filter-failed", "A goal that searches settlement menus must not travel to a non-settlement map target such as the tutorial training field.");
        results.Add(new { scenario = "campaign-loop-settlement-refresh-excludes-non-settlement-targets", passed = true });
        var excludedSafeTargets = BuildSafeVisibleTargets(new JsonObject
        {
            ["status"] = "completed",
            ["data"] = new JsonObject
            {
                ["mapSettlementTargets"] = new JsonArray
                {
                    new JsonObject { ["id"] = "safe", ["name"] = "Safe Town", ["type"] = "town", ["distance"] = 4.0, ["hostile"] = false, ["underSiege"] = false },
                    new JsonObject { ["id"] = "previously-visited", ["name"] = "Previously Visited Town", ["type"] = "town", ["distance"] = 2.0, ["hostile"] = false, ["underSiege"] = false }
                }
            }
        }, new HashSet<string>(["previously-visited"], StringComparer.Ordinal));
        if (excludedSafeTargets.Count != 1 || ReadString(excludedSafeTargets[0] as JsonObject, "id") != "safe")
            throw new AgentHostException("campaign-loop-self-test-safe-refresh-exclusion-failed", "A safe-settlement refresh must honor previously visited destinations and retain a different visible safe target.");
        results.Add(new { scenario = "campaign-loop-safe-arrival-excludes-recently-visited-settlements", passed = true });

        var targetActions = BuildActionCatalog(safeTargets, moving: false, goalVerified: false);
        if (targetActions.Count != 1 || ReadString(targetActions[0] as JsonObject, "action") != "move")
            throw new AgentHostException("campaign-loop-self-test-move-catalog-failed", "Once safe targets are observed, movement must be offered without repeating the map query.");
        results.Add(new { scenario = "campaign-loop-move-requires-current-safe-observation", passed = true });
        if (BuildActionCatalog(new JsonArray(), moving: false, goalVerified: false).Count != 0)
            throw new AgentHostException("campaign-loop-self-test-empty-target-requery-accepted", "An empty safe-target result must stop rather than repeat the same read-only query indefinitely.");
        results.Add(new { scenario = "campaign-loop-does-not-repeat-map-query-after-empty-result", passed = true });

        var movingActions = BuildActionCatalog(safeTargets, moving: true, goalVerified: false);
        var movingControls = BuildControlCatalog(moving: true, goalVerified: false);
        if (movingActions.Count != 0 || movingControls.Count != 1 ||
            !string.Equals(movingControls[0]?.GetValue<string>(), "observeAgain", StringComparison.Ordinal))
            throw new AgentHostException("campaign-loop-self-test-natural-wait-failed", "During movement the Host may only passively re-observe; it must not offer a game clock action.");
        results.Add(new { scenario = "campaign-loop-movement-exposes-only-passive-observation", passed = true });

        var movementInterruptedByBanditMeeting = new JsonObject
        {
            ["context"] = new JsonObject { ["gameState"] = "MapState", ["menuId"] = "encounter_meeting", ["encounterActive"] = true, ["encounteredPartyId"] = "looters-1" },
            ["party"] = new JsonObject { ["isMoving"] = true },
            ["location"] = new JsonObject { ["targetSettlementId"] = "safe", ["targetPartyId"] = "looters-1" }
        };
        if (BuildControlCatalog(moving: true, goalVerified: false, movementInterruptedByBanditMeeting).Count != 0)
            throw new AgentHostException("campaign-loop-self-test-hostile-meeting-does-not-wait", "A map EncounterMeeting interrupts a settlement move; passive observeAgain must not be listed until the existing BattleSimulation recovery handles it.");
        results.Add(new { scenario = "campaign-loop-hostile-encounter-meeting-interrupts-passive-movement-wait", passed = true });

        var doneControls = BuildControlCatalog(moving: false, goalVerified: true);
        if (doneControls.Count != 1 || !string.Equals(doneControls[0]?.GetValue<string>(), "done", StringComparison.Ordinal))
            throw new AgentHostException("campaign-loop-self-test-completion-gate-failed", "The done control must appear only after Native arrival is verified.");
        results.Add(new { scenario = "campaign-loop-done-requires-native-arrival", passed = true });

        if (!TryResolveCampaignAction(new JsonObject { ["action"] = "move", ["arguments"] = new JsonObject { ["SettlementId"] = "safe" } }, safeTargets, out var action, out var arguments, out var selected, out _) ||
            action != "move" || arguments?["settlementId"]?.GetValue<string>() != "safe" || selected?.Id != "safe")
            throw new AgentHostException("campaign-loop-self-test-target-binding-failed", "A move must bind to the exact ID from the latest safe Native map query.");
        if (TryResolveCampaignAction(new JsonObject { ["action"] = "move", ["arguments"] = new JsonObject { ["SettlementId"] = "unobserved" } }, safeTargets, out _, out _, out _, out _))
            throw new AgentHostException("campaign-loop-self-test-unobserved-target-accepted", "The Host accepted a settlement not present in the latest observed safe target list.");
        if (TryResolveCampaignAction(new JsonObject { ["action"] = "pause", ["arguments"] = new JsonObject() }, safeTargets, out _, out _, out _, out _))
            throw new AgentHostException("campaign-loop-self-test-clock-action-accepted", "The map-arrival Host accepted an explicit time-control action.");
        results.Add(new { scenario = "campaign-loop-rejects-unobserved-targets-and-clock-actions", passed = true });
        return results;
    }

    internal static int GetCumulativeDecisionLimit(int parentMaximum) => Math.Clamp(parentMaximum, 1, MaxCumulativeDecisions);

    internal static async Task<IReadOnlyList<object>> RunTransportSelfTestsAsync()
    {
        var requestJson = "{\"runId\":\"selftest-arrival\",\"goal\":\"Reach the observed safe settlement.\",\"parentProcessId\":321,\"maxDecisions\":8,\"maxElapsedSeconds\":10,\"allowedActionNames\":[\"mapSettlementTargets\",\"move\",\"menuSelect\",\"talkToSettlementHero\",\"dialogueSelect\",\"dialogueContinue\",\"questDetails\",\"tradeOptions\",\"trade\",\"tradeConfirm\",\"tradeCancel\",\"tradeCancelChanges\",\"barterOptions\",\"barterAutoBalance\",\"barterOffer\",\"barterCancel\",\"inventoryOpen\",\"heroEquipmentOptions\",\"inventoryCancel\",\"incidentSelect\"]}";
        using var request = JsonDocument.Parse(requestJson);
        var results = new List<object>();

        var arrivalClient = new FakeCampaignNativeClient(timeoutOnMove: false);
        var arrivalProvider = new FakeCampaignDecisionProvider(timeoutOnMove: false);
        var arrival = await RunAsync(request.RootElement, arrivalClient, arrivalProvider, CancellationToken.None);
        if (ReadString(arrival, "status") != "completed" ||
            ReadInt(arrival, "decisions", 0) != 5 ||
            ReadInt(arrival, "actionsExecuted", 0) != 2 ||
            arrivalClient.MapQueryCount != 1 || arrivalClient.MoveCount != 1 || arrivalProvider.CallCount != 5 ||
            arrivalProvider.FirstRequest?["goalScopeClassificationRequired"]?.GetValue<bool>() != true ||
            arrivalProvider.FirstRequest?["observation"]?["scope"]?.GetValue<string>() != "goal-classification-only" ||
            arrivalProvider.FirstRequest?["observation"]?["state"] is not null ||
            arrivalProvider.FirstRequest?["allowedActions"] is not JsonArray firstAllowedActions || firstAllowedActions.Count != 0 ||
            arrivalProvider.FirstRequest?["allowedControls"] is not JsonArray firstAllowedControls || firstAllowedControls.Count != 5 ||
            !firstAllowedControls.Any(control => control?.GetValue<string>() == "supportedMapArrivalGoal") ||
            !firstAllowedControls.Any(control => control?.GetValue<string>() == "supportedVillageToolsQuestGoal") ||
            !firstAllowedControls.Any(control => control?.GetValue<string>() == "supportedBattleSimulationGoal") ||
            !firstAllowedControls.Any(control => control?.GetValue<string>() == "supportedBattleAndCaptivityGoal") ||
            !firstAllowedControls.Any(control => control?.GetValue<string>() == "unsupportedGoal") ||
            arrival["termination"] is not JsonObject arrivalTermination || ReadBoolean(arrivalTermination, "goalVerified") != true)
            throw new AgentHostException("campaign-loop-self-test-arrival-runtime-failed", "The injected Native/Provider loop did not observe, move once, passively re-observe, and verify arrival.");
        results.Add(new { scenario = "campaign-loop-runtime-observe-decide-act-observe-arrival", passed = true });

        var refreshRequestNode = JsonNode.Parse(request.RootElement.GetRawText())?.AsObject() ?? throw new AgentHostException("campaign-loop-self-test-refresh-request-invalid", "The settlement refresh request could not be cloned.");
        refreshRequestNode["scopeRestriction"] = "safe-settlement-arrival";
        using var refreshRequest = JsonDocument.Parse(refreshRequestNode.ToJsonString());
        var sharedProvider = new FakeCampaignDecisionProvider(timeoutOnMove: false);
        var sharedArrivalClient = new FakeCampaignNativeClient(timeoutOnMove: false, includeActiveEycQuest: true);
        var sharedArrival = await RunAsync(refreshRequest.RootElement, sharedArrivalClient, sharedProvider, CancellationToken.None,
            disposeProvider: false, priorDecisions: 3, priorPromptTokens: 20, priorCompletionTokens: 2,
            priorTrace: new JsonArray(new JsonObject { ["stage"] = "prior-objective-trace" }),
            priorProviderRouteHistory: new JsonArray(new JsonObject { ["decision"] = 3, ["responseModelId"] = sharedProvider.ModelId }));
        if (ReadString(sharedArrival, "status") != "completed" || ReadInt(sharedArrival, "decisions", 0) != 8 ||
            sharedArrival["promptTokens"]?.GetValue<long>() != 20 || sharedArrival["completionTokens"]?.GetValue<long>() != 2 ||
            ReadInt(sharedArrival, "actionsExecuted", 0) != 2 || sharedArrivalClient.MoveCount != 1 || sharedProvider.CallCount != 5 ||
            sharedProvider.DisposeCount != 0 || sharedProvider.FirstRequest?["allowedControls"] is not JsonArray refreshControls || refreshControls.Count != 2 ||
            refreshControls.Any(control => control?.GetValue<string>() == "supportedEstablishYourClanGoal") ||
            sharedArrival["trace"] is not JsonArray sharedTrace || sharedTrace.Count <= 5 ||
            sharedArrival["providerRouteHistory"] is not JsonArray sharedRoutes || sharedRoutes.Count <= 5)
            throw new AgentHostException("campaign-loop-self-test-shared-provider-arrival-budget-failed", "A nested safe-map refresh must preserve the shared provider lifetime, cumulative decisions/token counters, prior trace and map-arrival-only scope.");
        sharedProvider.Dispose();
        results.Add(new { scenario = "campaign-loop-nested-map-arrival-shares-provider-budget-and-trace", passed = true });

        var timeoutClient = new FakeCampaignNativeClient(timeoutOnMove: true);
        var timeoutProvider = new FakeCampaignDecisionProvider(timeoutOnMove: true);
        var timeout = await RunAsync(request.RootElement, timeoutClient, timeoutProvider, CancellationToken.None);
        if (ReadString(timeout, "status") != "failed" ||
            timeout["termination"] is not JsonObject timeoutTermination || ReadString(timeoutTermination, "reason") != "native-action-result-ambiguous" ||
            ReadInt(timeout, "actionsExecuted", 0) != 1 || timeoutClient.MapQueryCount != 1 || timeoutClient.MoveCount != 1 || timeoutProvider.CallCount != 3 ||
            timeout["trace"] is not JsonArray timeoutTrace || timeoutTrace.OfType<JsonObject>().Count(step => ReadString(step["actionReceipt"] as JsonObject, "status") == "timeout-ambiguous") != 1)
            throw new AgentHostException("campaign-loop-self-test-timeout-replay-failed", "An ambiguous Native move timeout was not surfaced safely or the action was replayed.");
        results.Add(new { scenario = "campaign-loop-runtime-native-timeout-is-not-replayed", passed = true });

        var unsupportedClient = new FakeCampaignNativeClient(timeoutOnMove: false);
        var unsupportedProvider = new FakeCampaignDecisionProvider(timeoutOnMove: false, unsupportedGoal: true);
        var unsupported = await RunAsync(request.RootElement, unsupportedClient, unsupportedProvider, CancellationToken.None);
        if (ReadString(unsupported, "status") != "failed" ||
            ReadString(unsupported, "failureCode") != "campaign-goal-unsupported" ||
            ReadInt(unsupported, "actionsExecuted", 0) != 0 || unsupportedClient.MapQueryCount != 0 ||
            unsupportedClient.MoveCount != 0 || unsupportedProvider.CallCount != 1)
            throw new AgentHostException("campaign-loop-self-test-unsupported-goal-action-leaked", "An unsupported task must terminate after classification and before any Native game action.");
        results.Add(new { scenario = "campaign-loop-unsupported-goal-stops-before-native-actions", passed = true });

        var eycScopeRequest = new JsonObject
        {
            ["runId"] = "selftest-eyc-unsupported-reconsideration",
            ["goal"] = "Autonomously complete the exact currently active original StoryMode Establish Your Clan quest.",
            ["parentProcessId"] = 321,
            ["maxDecisions"] = 8,
            ["maxElapsedSeconds"] = 10,
            ["allowedActionNames"] = new JsonArray(AllSupportedActions.OrderBy(action => action, StringComparer.Ordinal).Select(action => (JsonNode?)JsonValue.Create(action)).ToArray())
        };
        using var eycScopeDocument = JsonDocument.Parse(eycScopeRequest.ToJsonString());
        var eycScopeClient = new FakeCampaignNativeClient(timeoutOnMove: false, includeActiveEycQuest: true);
        var eycScopeProvider = new FakeCampaignDecisionProvider(timeoutOnMove: false, reconsiderEycScope: true);
        var reconsideredEycScope = await RunAsync(eycScopeDocument.RootElement, eycScopeClient, eycScopeProvider, CancellationToken.None);
        var reconsiderationTrace = reconsideredEycScope["trace"] as JsonArray;
        if (ReadString(reconsideredEycScope, "status") != "failed" ||
            ReadString(reconsideredEycScope, "failureCode") != "establish-clan-autonomy-native-client-unavailable" ||
            ReadInt(reconsideredEycScope, "decisions", 0) != 2 || ReadInt(reconsideredEycScope, "actionsExecuted", 0) != 0 ||
            eycScopeClient.MapQueryCount != 0 || eycScopeClient.MoveCount != 0 || eycScopeProvider.CallCount != 2 ||
            eycScopeProvider.SecondRequest?["decisionFeedback"]?["kind"]?.GetValue<string>() != "supported-establish-clan-scope-reconsideration" ||
            !((eycScopeProvider.SecondSystemPrompt ?? string.Empty).Contains("Multi-step execution within this exact quest is not a reason to choose unsupportedGoal", StringComparison.Ordinal)) ||
            !reconsiderationTrace!.OfType<JsonObject>().Any(step =>
                ReadString(step["decisionFeedback"] as JsonObject, "kind") == "supported-establish-clan-scope-reconsideration" &&
                ReadBoolean(step["actionReceipt"] as JsonObject, "noNativeActionSent")))
            throw new AgentHostException("campaign-loop-self-test-eyc-unsupported-reconsideration-failed", "A single explicit active EYC multi-step classification error must be reconsidered once before any Native action, then route only to the listed EYC executor.");
        results.Add(new { scenario = "campaign-loop-reconsiders-one-explicit-active-eyc-unsupported-classification-before-native", passed = true });
        return results;
    }

    internal static async Task<JsonObject> RunAsync(
        JsonElement request,
        string protocolRoot,
        CancellationToken cancellationToken,
        Action<int>? onReady = null)
    {
        var nativeTimeoutSeconds = ReadIntEnvironment("CHRONICLE_NATIVE_MAILBOX_TIMEOUT_SECONDS", 180, 5, 240);
        var expectedProcessId = ReadInt(request, "parentProcessId", 0);
        var nativeSessionId = ReadString(request, "nativeSessionId");
        if (expectedProcessId <= 0 || string.IsNullOrWhiteSpace(nativeSessionId))
            throw new AgentHostException("campaign-native-session-missing", "The Campaign Host requires the launching game process and loaded Native session identity.");
        var client = new NativeMailboxClient(protocolRoot, TimeSpan.FromSeconds(nativeTimeoutSeconds), expectedProcessId, nativeSessionId);
        var provider = Program.CreateCampaignDecisionProvider(request);
        return await RunAsync(request, client, provider, cancellationToken, onReady);
    }

    internal static async Task<JsonObject> RunAsync(
        JsonElement request,
        IAgentHostCampaignNativeClient client,
        IAgentHostDecisionProvider provider,
        CancellationToken cancellationToken,
        Action<int>? onReady = null,
        bool disposeProvider = true,
        int priorDecisions = 0,
        long priorPromptTokens = 0,
        long priorCompletionTokens = 0,
        JsonArray? priorTrace = null,
        JsonArray? priorProviderRouteHistory = null)
    {
        var runId = ReadString(request, "runId") ?? Guid.NewGuid().ToString("N");
        var expectedParentProcessId = ReadInt(request, "parentProcessId", 0);
        var goal = ReadString(request, "goal");
        var maxDecisions = ReadInt(request, "maxDecisions", 30);
        var maxElapsedSeconds = ReadInt(request, "maxElapsedSeconds", 600);
        var requestedActions = request.TryGetProperty("allowedActionNames", out var actionNames) && actionNames.ValueKind == JsonValueKind.Array
            ? actionNames.EnumerateArray().Where(item => item.ValueKind == JsonValueKind.String).Select(item => item.GetString()!).ToHashSet(StringComparer.Ordinal)
            : new HashSet<string>(StringComparer.Ordinal);
        if (string.IsNullOrWhiteSpace(goal) || goal.Length > 1000 || maxDecisions is < 1 or > MaxCumulativeDecisions || maxElapsedSeconds is < 1 or > 7200 ||
            !IsSupportedRequestedActionSet(requestedActions))
            throw new AgentHostException("campaign-loop-request-invalid", "The Host requires a bounded goal and one exact approved Campaign action set.");

        using (disposeProvider ? provider : null)
        {
        using var elapsed = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        elapsed.CancelAfter(TimeSpan.FromSeconds(maxElapsedSeconds));

        var trace = priorTrace?.DeepClone() as JsonArray ?? new JsonArray();
        var providerRouteHistory = priorProviderRouteHistory?.DeepClone() as JsonArray ?? new JsonArray();
        var safeSettlementArrivalOnly = string.Equals(ReadString(request, "scopeRestriction"), "safe-settlement-arrival", StringComparison.Ordinal);
        var excludedSettlementIds = new HashSet<string>(StringComparer.Ordinal);
        if (safeSettlementArrivalOnly && request.TryGetProperty("excludedSettlementIds", out var excludedSettlementArray) && excludedSettlementArray.ValueKind == JsonValueKind.Array)
        {
            foreach (var excludedSettlement in excludedSettlementArray.EnumerateArray())
            {
                if (excludedSettlement.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(excludedSettlement.GetString()))
                    excludedSettlementIds.Add(excludedSettlement.GetString()!);
            }
        }
        var decisionCount = priorDecisions;
        var rejectedDecisionCount = 0;
        var prematureCompletionCount = 0;
        var actionsExecuted = 0;
        long promptTokens = priorPromptTokens;
        long completionTokens = priorCompletionTokens;
        JsonObject? currentNative = null;
        JsonObject? previousReceipt = null;
        JsonObject? feedback = null;
        JsonArray? visibleTargets = null;
        string? moveTargetId = null;
        string? moveTargetName = null;
        var completedByProvider = false;
        var goalScopeClassified = false;
        var unsupportedEycScopeReconsiderations = 0;
        bool? firstDecisionRequiresGoalClassification = null;
        bool? firstDecisionListsSupportedGoalClassification = null;
        bool? firstDecisionListsUnsupportedGoalClassification = null;
        string? terminationReason = null;
        string? failure = null;
        string? failureCode = null;
        string? failureExceptionType = null;
        string? hostFailureStack = null;
        string? nativeActionInFlight = null;
        var loopStartedTicks = Stopwatch.GetTimestamp();

        try
        {
            await provider.CheckConfiguredModelAsync(elapsed.Token);
            using (var initial = await client.ReadStateAsync(elapsed.Token)) currentNative = CloneObject(initial.RootElement);
            var nativeProcessId = ReadInt(currentNative, "processId", -1);
            if (nativeProcessId <= 0)
                throw new AgentHostException("native-process-id-invalid", "The active Native state did not identify its Bannerlord process.");
            if (expectedParentProcessId > 0 && nativeProcessId != expectedParentProcessId)
                throw new AgentHostException("native-parent-process-mismatch", "The Native mailbox answered from a different Bannerlord process than the Host owner.");
            onReady?.Invoke(nativeProcessId);

            for (var iteration = decisionCount + 1; iteration <= maxDecisions; iteration++)
            {
                elapsed.Token.ThrowIfCancellationRequested();
                var before = currentNative ?? throw new AgentHostException("native-observation-missing", "The Host lost its current Native observation.");
                var targetReached = moveTargetId != null && string.Equals(ReadStateString(before, "location", "currentSettlementId"), moveTargetId, StringComparison.Ordinal);
                var isMapState = string.Equals(ReadStateString(before, "context", "gameState"), "MapState", StringComparison.Ordinal);
                if (!isMapState)
                {
                    failure = "The Native Campaign is no longer on the map; Host stopped without selecting an out-of-scope action.";
                    terminationReason = "campaign-map-unavailable";
                    break;
                }

                var nativeTargetId = ReadStateString(before, "location", "targetSettlementId");
                var movingToTarget = moveTargetId != null && !targetReached && string.Equals(nativeTargetId, moveTargetId, StringComparison.Ordinal);
                if (moveTargetId != null && !targetReached && !movingToTarget)
                {
                    feedback = new JsonObject
                    {
                        ["kind"] = "native-move-no-longer-active",
                        ["message"] = "The fresh Native state no longer shows the selected move order. Query current visible settlements and replan; do not replay the old move."
                    };
                    moveTargetId = null;
                    moveTargetName = null;
                    visibleTargets = null;
                }

                targetReached = moveTargetId != null && string.Equals(ReadStateString(before, "location", "currentSettlementId"), moveTargetId, StringComparison.Ordinal);
                var actionCatalog = goalScopeClassified
                    ? BuildActionCatalog(visibleTargets, movingToTarget, targetReached)
                    : new JsonArray();
                var controls = goalScopeClassified
                    ? BuildControlCatalog(movingToTarget, targetReached, before["state"] as JsonObject)
                    : BuildGoalScopeClassificationControls(before["state"] as JsonObject,
                        safeSettlementArrivalOnly: ReadString(request, "scopeRestriction") == "safe-settlement-arrival");
                if (actionCatalog.Count == 0 && controls.Count == 0)
                {
                    failure = "No safe map query, movement action or waiting control is available in the current Native state.";
                    terminationReason = "no-safe-action";
                    break;
                }

                var observation = BuildObservation(before, visibleTargets, moveTargetId, moveTargetName, targetReached);
                var modelRequest = BuildModelRequest(runId, iteration, goal!, observation, previousReceipt, feedback, actionCatalog, controls);
                if (firstDecisionRequiresGoalClassification is null)
                {
                    firstDecisionRequiresGoalClassification = modelRequest["goalScopeClassificationRequired"]?.GetValue<bool>() ?? false;
                    firstDecisionListsSupportedGoalClassification = modelRequest["allowedControls"] is JsonArray firstControls &&
                        firstControls.Any(control => control?.GetValue<string>() == "supportedMapArrivalGoal");
                    firstDecisionListsUnsupportedGoalClassification = modelRequest["allowedControls"] is JsonArray firstControlsForUnsupported &&
                        firstControlsForUnsupported.Any(control => control?.GetValue<string>() == "unsupportedGoal");
                }
                var providerStartedUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                var providerStartedTicks = Stopwatch.GetTimestamp();
                ProviderDecisionResult providerResult;
                try
                {
                    providerResult = await AgentHostDecisionCycle.DecideCampaignAsync(provider, modelRequest, elapsed.Token);
                    decisionCount++;
                    rejectedDecisionCount = 0;
                    if (providerResult.PromptTokens.HasValue) promptTokens += providerResult.PromptTokens.Value;
                    if (providerResult.CompletionTokens.HasValue) completionTokens += providerResult.CompletionTokens.Value;
                    providerRouteHistory.Add(new JsonObject
                    {
                        ["decision"] = decisionCount,
                        ["requestedModelId"] = provider.ModelId,
                        ["responseModelId"] = providerResult.ModelId,
                        ["routedVia"] = providerResult.RoutedVia,
                        ["responseFormatMode"] = providerResult.ResponseFormatMode,
                        ["promptTokens"] = providerResult.PromptTokens,
                        ["completionTokens"] = providerResult.CompletionTokens
                    });
                }
                catch (AgentHostException exception) when (IsRecoverableProviderDecisionError(exception.Code) && rejectedDecisionCount < MaxRejectedDecisions)
                {
                    decisionCount++;
                    rejectedDecisionCount++;
                    var providerCompletedUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                    feedback = new JsonObject
                    {
                        ["kind"] = "decision-rejected-before-native",
                        ["code"] = exception.Code,
                        ["message"] = exception.Message,
                        ["requiredNextStep"] = exception.Code switch
                        {
                            "provider-goal-classification-unavailable" when goalScopeClassified => "Goal scope was already classified. Do not classify again; choose the currently listed mapSettlementTargets action.",
                            "provider-action-unavailable" when movingToTarget => "Native move is already active. Do not repeat move; choose the listed observeAgain control to obtain fresh state without changing the game clock.",
                            "provider-arguments-invalid-json" => "Return arguments as a JSON object, not a string; use exactly the listed names and current observed IDs.",
                            _ => "Use exactly one action or control from the latest catalog; do not repeat the rejected response."
                        }
                    };
                    trace.Add(BuildRejectedDecisionStep(iteration, observation, previousReceipt, actionCatalog, controls, feedback, providerStartedUtc, providerCompletedUtc, providerStartedTicks));
                    continue;
                }

                var providerDoneUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                var decision = providerResult.Decision;
                var goalClassification = ReadNodeString(decision["goalClassification"]);
                if (goalClassification == "unsupported")
                {
                    if (ShouldReconsiderUnsupportedEycScope(goal!, controls, goalScopeClassified, unsupportedEycScopeReconsiderations))
                    {
                        unsupportedEycScopeReconsiderations++;
                        feedback = new JsonObject
                        {
                            ["kind"] = "supported-establish-clan-scope-reconsideration",
                            ["requiredNextStep"] = "The exact active original Establish Your Clan quest is explicitly listed as a supported high-level scope. It is one goal with multi-step Native subgoals; reconsider that supported scope before declaring unrelated unsupported work."
                        };
                        trace.Add(BuildDecisionOnlyStep(iteration, observation, previousReceipt, actionCatalog, controls, decision,
                            providerStartedUtc, providerDoneUtc, providerStartedTicks, feedback.DeepClone() as JsonObject));
                        continue;
                    }
                    failure = "The configured goal is outside the implemented Native Campaign scopes; no game action was issued.";
                    failureCode = "campaign-goal-unsupported";
                    terminationReason = "campaign-goal-unsupported";
                    trace.Add(BuildDecisionOnlyStep(iteration, observation, previousReceipt, actionCatalog, controls, decision,
                        providerStartedUtc, providerDoneUtc, providerStartedTicks, new JsonObject { ["kind"] = "goal-out-of-scope" }));
                    break;
                }
                if (goalClassification == "supported-map-arrival")
                {
                    if (goalScopeClassified)
                    {
                        failure = "The Host received a repeated goal-scope declaration after classification.";
                        failureCode = "campaign-goal-classification-repeated";
                        terminationReason = "campaign-loop-failed";
                        break;
                    }
                    goalScopeClassified = true;
                    feedback = new JsonObject
                    {
                        ["kind"] = "goal-scope-accepted",
                        ["contractId"] = "native-map-arrival-v1",
                        ["message"] = "This goal is handled only as arrival at any one currently visible safe settlement. The Native arrival verifier checks that limited outcome."
                    };
                    trace.Add(BuildDecisionOnlyStep(iteration, observation, previousReceipt, actionCatalog, controls, decision,
                        providerStartedUtc, providerDoneUtc, providerStartedTicks, null));
                    continue;
                }
                if (goalClassification == "supported-village-tools-quest")
                {
                    trace.Add(BuildDecisionOnlyStep(iteration, observation, previousReceipt, actionCatalog, controls, decision,
                        providerStartedUtc, providerDoneUtc, providerStartedTicks, null));
                    if (client is not IAgentHostVillageToolsQuestNativeClient questClient)
                        throw new AgentHostException("village-tools-native-client-unavailable", "The Native transport does not implement the bounded VillageNeedsTools quest protocol.");
                    return await AgentHostVillageToolsQuestLoop.RunAsync(
                        request, questClient, provider, elapsed.Token,
                        priorDecisions: decisionCount,
                        priorPromptTokens: promptTokens,
                        priorCompletionTokens: completionTokens,
                        priorTrace: trace,
                        priorProviderRouteHistory: providerRouteHistory);
                }
                if (goalClassification == "supported-battle-simulation")
                {
                    trace.Add(BuildDecisionOnlyStep(iteration, observation, previousReceipt, actionCatalog, controls, decision,
                        providerStartedUtc, providerDoneUtc, providerStartedTicks, null));
                    if (!requestedActions.SetEquals(BattleSimulationActions) && !requestedActions.SetEquals(AllSupportedActions))
                        throw new AgentHostException("battle-simulation-action-set-unavailable", "The Campaign request does not include the exact bounded Native BattleSimulation action set.");
                    if (client is not IAgentHostBattleSimulationNativeClient battleClient)
                        throw new AgentHostException("battle-simulation-native-client-unavailable", "The Native transport does not implement the bounded Campaign BattleSimulation protocol.");
                    return await AgentHostBattleSimulationLoop.RunAsync(
                        request, battleClient, provider, elapsed.Token,
                        priorDecisions: decisionCount,
                        priorPromptTokens: promptTokens,
                        priorCompletionTokens: completionTokens,
                        priorTrace: trace,
                        priorProviderRouteHistory: providerRouteHistory);
                }
                if (goalClassification == "supported-battle-and-captivity")
                {
                    trace.Add(BuildDecisionOnlyStep(iteration, observation, previousReceipt, actionCatalog, controls, decision,
                        providerStartedUtc, providerDoneUtc, providerStartedTicks, null));
                    if (!requestedActions.SetEquals(BattleSimulationActions) && !requestedActions.SetEquals(AllSupportedActions))
                        throw new AgentHostException("battle-captivity-action-set-unavailable", "The Campaign request does not include the exact bounded Native BattleSimulation action set.");
                    if (client is not IAgentHostBattleSimulationNativeClient battleClient)
                        throw new AgentHostException("battle-captivity-native-client-unavailable", "The Native transport does not implement the bounded Campaign BattleSimulation/captivity protocol.");
                    return await AgentHostBattleSimulationLoop.RunAsync(
                        request, battleClient, provider, elapsed.Token,
                        priorDecisions: decisionCount,
                        priorPromptTokens: promptTokens,
                        priorCompletionTokens: completionTokens,
                        priorTrace: trace,
                        priorProviderRouteHistory: providerRouteHistory,
                        recoverPlayerCaptivity: true);
                }
                if (goalClassification == "supported-establish-your-clan")
                {
                    trace.Add(BuildDecisionOnlyStep(iteration, observation, previousReceipt, actionCatalog, controls, decision,
                        providerStartedUtc, providerDoneUtc, providerStartedTicks, null));
                    if (ReadBoolean(request, "establishClanPlannerOnly"))
                    {
                        if (!requestedActions.SetEquals(ApprovedActions))
                            throw new AgentHostException("establish-clan-planner-action-set-unavailable", "The read-only StoryMode objective planner accepts only its exact previously reviewed Native action set.");
                        if (client is not IAgentHostQuestDetailsNativeClient plannerDetailsClient)
                            throw new AgentHostException("establish-clan-quest-details-client-unavailable", "The Native transport does not implement the read-only Quest Journal query required by the StoryMode planner.");
                        return await AgentHostEstablishYourClanGoalLoop.RunAsync(
                            request, client, plannerDetailsClient, provider, elapsed.Token,
                            priorDecisions: decisionCount,
                            priorPromptTokens: promptTokens,
                            priorCompletionTokens: completionTokens,
                            priorTrace: trace,
                            priorProviderRouteHistory: providerRouteHistory);
                    }
                    if (!requestedActions.SetEquals(AllSupportedActions))
                        throw new AgentHostException("establish-clan-autonomy-action-set-unavailable", "The StoryMode autonomy loop requires the exact reviewed Native superset for its currently integrated Gold, PartySize, Renown and Companion subgoals.");
                    if (client is not IAgentHostQuestDetailsNativeClient questDetailsClient ||
                        client is not IAgentHostGoldSaleNativeClient goldSaleClient ||
                        client is not IAgentHostBattleSimulationNativeClient battleClient ||
                        client is not IAgentHostEstablishClanTrainingIssueNativeClient trainingIssueClient ||
                        client is not IAgentHostRecruitmentNativeClient recruitmentClient ||
                        client is not IAgentHostCompanionHiringNativeClient companionClient)
                        throw new AgentHostException("establish-clan-autonomy-native-client-unavailable", "The Native transport does not implement the reviewed Quest Journal, Trade-sale, recruitment, Tavern Mission and BattleSimulation subgoal contracts.");

                    async Task<JsonObject> ExecuteObjectiveAsync(string objectiveId, int priorSubDecisions, long priorSubPromptTokens,
                        long priorSubCompletionTokens, JsonArray priorSubTrace, JsonArray priorSubRoutes, CancellationToken subToken)
                    {
                        var childRequestNode = JsonNode.Parse(request.GetRawText())?.AsObject()
                            ?? throw new AgentHostException("establish-clan-subgoal-request-invalid", "The active StoryMode request could not be cloned for a bounded objective subgoal.");
                        var remainingSeconds = Math.Max(1, maxElapsedSeconds - (int)Stopwatch.GetElapsedTime(loopStartedTicks).TotalSeconds);
                        childRequestNode["maxDecisions"] = GetCumulativeDecisionLimit(maxDecisions);
                        childRequestNode["maxElapsedSeconds"] = remainingSeconds;
                        childRequestNode["goal"] = objectiveId switch
                        {
                            "gold" => "Raise the current original Establish Your Clan Journal Gold progress with one positive Native Goods sale; then return to the StoryMode objective loop.",
                            "partySize" => "Raise the current original Establish Your Clan Journal PartySize progress by recruiting current affordable volunteers through the original RecruitmentVM, stopping at the dynamic target and rechecking the Journal.",
                            "companions" => "Find one currently observed unowned Wanderer through a Native Town Tavern Mission, follow the current original hire dialogue and quote, and recheck the original Journal after the actual Native Clan/Party result.",
                            "renown" => "Raise the current original Establish Your Clan Journal Renown progress by resolving one currently visible hostile Bandit through Native Campaign BattleSimulation, verifying actual aftermath, then return to the StoryMode objective loop.",
                            "captivityRecovery" => "Recover MainHero from the currently observed Native captivity menus without starting another battle, verify a usable free Campaign Map, then return control to the Establish Your Clan objective loop.",
                            _ => throw new AgentHostException("establish-clan-objective-route-unavailable", "No integrated Native objective executor is registered for this StoryMode target.")
                        };
                        childRequestNode["parentGoal"] = ReadString(request, "goal");
                        childRequestNode["parentObjectiveId"] = objectiveId;
                        if (objectiveId is "gold" or "renown")
                        {
                            using var parentDetails = await questDetailsClient.ReadQuestDetailsAsync("rebuild_player_clan_storymode_quest", subToken);
                            var parentRoot = JsonNode.Parse(parentDetails.RootElement.GetRawText()) as JsonObject;
                            var parentData = parentRoot?["data"] as JsonObject
                                ?? throw new AgentHostException("establish-clan-parent-objectives-unavailable", "The current Native EYC Journal details did not include structured objective progress for the battle aftermath decision.");
                            var parentObjectives = AgentHostEstablishYourClanGoalLoop.BuildJournalObjectives(parentData);
                            childRequestNode["parentEycObjectives"] = AgentHostEstablishYourClanGoalLoop.BuildObjectiveSnapshot(parentObjectives);
                        }
                        using var childRequest = JsonDocument.Parse(childRequestNode.ToJsonString());
                        async Task<JsonObject> ExecuteGoldObjectiveAsync()
                        {
                            var sale = await AgentHostEstablishClanGoldSaleLoop.RunAsync(childRequest.RootElement, client, goldSaleClient, provider, subToken,
                                priorDecisions: priorSubDecisions, priorPromptTokens: priorSubPromptTokens, priorCompletionTokens: priorSubCompletionTokens,
                                priorTrace: priorSubTrace, priorProviderRouteHistory: priorSubRoutes);
                            if (!AgentHostEstablishYourClanAutonomyLoop.ShouldUseBattleLootFallback(sale)) return sale;

                            var trainingRequestNode = JsonNode.Parse(childRequest.RootElement.GetRawText())?.AsObject()
                                ?? throw new AgentHostException("establish-clan-training-issue-request-invalid", "The active Gold objective could not be cloned for a current visible Native training Issue.");
                            trainingRequestNode["goal"] = "Raise the current original Establish Your Clan Gold Journal by completing a currently visible direct Native Train Troops for Retainers Issue, upgrading its borrowed troops through PartyVM and returning them to the giver through the visible Native inquiry. Re-read the EYC Journal after the real payout.";
                            using var trainingRequest = JsonDocument.Parse(trainingRequestNode.ToJsonString());
                            var training = await AgentHostEstablishClanTrainingIssueLoop.RunAsync(trainingRequest.RootElement, trainingIssueClient, battleClient, provider, subToken,
                                priorDecisions: ReadInt(sale, "decisions", priorSubDecisions),
                                priorPromptTokens: ReadLong(sale, "promptTokens", priorSubPromptTokens),
                                priorCompletionTokens: ReadLong(sale, "completionTokens", priorSubCompletionTokens),
                                priorTrace: sale["trace"] as JsonArray ?? priorSubTrace,
                                priorProviderRouteHistory: sale["providerRouteHistory"] as JsonArray ?? priorSubRoutes);
                            AgentHostHarnessProgressTrace.RecordObjectiveSubflowResult("goldTrainingIssueIncome", training);
                            training["resultKind"] = "establish-clan-gold-sale-with-training-issue-route";
                            training["actionsExecuted"] = ReadInt(sale, "actionsExecuted", 0) + ReadInt(training, "actionsExecuted", 0);
                            training["saleActionsExecuted"] = ReadInt(sale, "saleActionsExecuted", 0);
                            training["goldSaleFailureCode"] = ReadString(sale, "failureCode");
                            training["goldObjectiveVerified"] = training["eycGoldJournalDelta"] is JsonValue trainingDeltaNode &&
                                trainingDeltaNode.TryGetValue<double>(out var trainingGoldDelta) && trainingGoldDelta > 0;
                            if (ReadString(training, "status") == "completed" || ReadBoolean(training, "directOfferAccepted")) return training;

                            var retryableIssueSearch = ReadString(training, "failureCode") is "training-issue-no-visible-direct-offer" or
                                "training-issue-no-safe-settlement-visible" or "training-issue-direct-offer-unavailable";
                            var trainingFinalContext = (training["finalNativeState"]?["state"]?["context"] as JsonObject);
                            var trainingEndedOnFreeMap = ReadString(trainingFinalContext, "gameState") == "MapState" &&
                                ReadString(trainingFinalContext, "menuId") is null && !ReadBoolean(trainingFinalContext, "encounterActive") &&
                                !ReadBoolean(trainingFinalContext, "escapeMenuOpen") && !ReadBoolean(trainingFinalContext, "inquiryOpen") &&
                                !ReadBoolean((trainingFinalContext?["captivity"] as JsonObject), "isCaptive");
                            if (!retryableIssueSearch || !trainingEndedOnFreeMap) return training;

                            var battleRequestNode = JsonNode.Parse(trainingRequest.RootElement.GetRawText())?.AsObject()
                                ?? throw new AgentHostException("establish-clan-gold-loot-request-invalid", "The Native no-goods sale result could not be cloned for its bounded battle-loot fallback.");
                            battleRequestNode["goal"] = "The original Establish Your Clan Gold Journal objective is unmet and the current Native PlayerInventory has no transferable Goods. Resolve one currently visible hostile Bandit through the original Campaign BattleSimulation, take only currently offered Native loot, and return to the EYC planner. This may produce saleable goods but does not prove Gold progress; do not enter a real-time Mission or control the Campaign clock.";
                            using var battleRequest = JsonDocument.Parse(battleRequestNode.ToJsonString());
                            var battle = await AgentHostBattleSimulationLoop.RunAsync(battleRequest.RootElement, battleClient, provider, subToken,
                                priorDecisions: ReadInt(training, "decisions", priorSubDecisions),
                                priorPromptTokens: ReadLong(training, "promptTokens", priorSubPromptTokens),
                                priorCompletionTokens: ReadLong(training, "completionTokens", priorSubCompletionTokens),
                                priorTrace: training["trace"] as JsonArray ?? priorSubTrace,
                                priorProviderRouteHistory: training["providerRouteHistory"] as JsonArray ?? priorSubRoutes,
                                recoverPlayerCaptivity: true);
                            AgentHostHarnessProgressTrace.RecordObjectiveSubflowResult("goldLootBattleFallback", battle);
                            battle["resultKind"] = "establish-clan-gold-sale-with-battle-loot-fallback";
                            battle["actionsExecuted"] = ReadInt(sale, "actionsExecuted", 0) + ReadInt(training, "actionsExecuted", 0) + ReadInt(battle, "actionsExecuted", 0);
                            battle["saleActionsExecuted"] = ReadInt(sale, "saleActionsExecuted", 0);
                            battle["trainingIssueAttempt"] = new JsonObject
                            {
                                ["failureCode"] = ReadString(training, "failureCode"),
                                ["termination"] = ReadString(training, "termination"),
                                ["directOfferAccepted"] = ReadBoolean(training, "directOfferAccepted"),
                                ["issueQuestId"] = ReadString(training, "trainingIssueQuestId")
                            };
                            battle["goldSaleFailureCode"] = ReadString(sale, "failureCode");
                            battle["goldSaleTermination"] = ReadString(sale["termination"] as JsonObject, "reason");
                            battle["goldObjectiveVerified"] = false;
                            var battleFinalContext = (battle["finalNativeState"]?["state"]?["context"] as JsonObject);
                            var battleEndedOnFreeMap = ReadString(battleFinalContext, "gameState") == "MapState" &&
                                ReadString(battleFinalContext, "menuId") is null &&
                                !ReadBoolean(battleFinalContext, "encounterActive") &&
                                !ReadBoolean(battleFinalContext, "escapeMenuOpen") &&
                                !ReadBoolean(battleFinalContext, "inquiryOpen") &&
                                !ReadBoolean((battleFinalContext?["captivity"] as JsonObject), "isCaptive");
                            if (ReadString(battle, "status") == "failed" &&
                                ReadString(battle, "termination") == "no-safe-action" &&
                                ReadBoolean(battle, "battleStarted") != true && battleEndedOnFreeMap)
                            {
                                battle["failureCode"] = "gold-loot-no-current-visible-bandit";
                                battle["termination"] = "gold-loot-no-current-visible-bandit";
                            }
                            return battle;
                        }
                        return objectiveId switch
                        {
                            "gold" => await ExecuteGoldObjectiveAsync(),
                            "partySize" => await AgentHostEstablishClanRecruitmentLoop.RunAsync(childRequest.RootElement, client, recruitmentClient, questDetailsClient, provider, subToken,
                                priorDecisions: priorSubDecisions, priorPromptTokens: priorSubPromptTokens, priorCompletionTokens: priorSubCompletionTokens,
                                priorTrace: priorSubTrace, priorProviderRouteHistory: priorSubRoutes),
                            "companions" => await AgentHostEstablishClanCompanionLoop.RunAsync(childRequest.RootElement, client, companionClient, provider, subToken,
                                priorDecisions: priorSubDecisions, priorPromptTokens: priorSubPromptTokens, priorCompletionTokens: priorSubCompletionTokens,
                                priorTrace: priorSubTrace, priorProviderRouteHistory: priorSubRoutes),
                            "renown" => await AgentHostBattleSimulationLoop.RunAsync(childRequest.RootElement, battleClient, provider, subToken,
                                priorDecisions: priorSubDecisions, priorPromptTokens: priorSubPromptTokens, priorCompletionTokens: priorSubCompletionTokens,
                                priorTrace: priorSubTrace, priorProviderRouteHistory: priorSubRoutes),
                            "captivityRecovery" => client is IAgentHostCaptivityRecoveryNativeClient captivityRecoveryClient
                                ? await AgentHostCaptivityRecoveryLoop.RunAsync(childRequest.RootElement, client, captivityRecoveryClient, questDetailsClient, provider, subToken,
                                    priorDecisions: priorSubDecisions, priorPromptTokens: priorSubPromptTokens, priorCompletionTokens: priorSubCompletionTokens,
                                    priorTrace: priorSubTrace, priorProviderRouteHistory: priorSubRoutes, planObjectiveAfterRecovery: false)
                                : throw new AgentHostException("establish-clan-captivity-recovery-client-unavailable", "The Native transport does not implement the current captivity recovery action contract required by the EYC parent loop."),
                            _ => throw new AgentHostException("establish-clan-objective-route-unavailable", "No integrated Native objective executor is registered for this StoryMode target.")
                        };
                    }

                    return await AgentHostEstablishYourClanAutonomyLoop.RunAsync(
                        request, client, questDetailsClient, provider, ExecuteObjectiveAsync, elapsed.Token,
                        priorDecisions: decisionCount,
                        priorPromptTokens: promptTokens,
                        priorCompletionTokens: completionTokens,
                        priorTrace: trace,
                        priorProviderRouteHistory: providerRouteHistory);
                }
                if (goalClassification == "supported-captivity-recovery")
                {
                    trace.Add(BuildDecisionOnlyStep(iteration, observation, previousReceipt, actionCatalog, controls, decision,
                        providerStartedUtc, providerDoneUtc, providerStartedTicks, null));
                    if (!requestedActions.SetEquals(CaptivityRecoveryActions) && !requestedActions.SetEquals(AllSupportedActions))
                        throw new AgentHostException("captivity-recovery-action-set-unavailable", "The Campaign request does not include the exact approved Native captivity recovery action set.");
                    if (client is not IAgentHostCaptivityRecoveryNativeClient captivityClient ||
                        client is not IAgentHostQuestDetailsNativeClient questDetailsClient)
                        throw new AgentHostException("captivity-recovery-native-client-unavailable", "The Native transport does not implement read-only Quest details and explicit Captivity recovery actions.");
                    return await AgentHostCaptivityRecoveryLoop.RunAsync(
                        request, client, captivityClient, questDetailsClient, provider, elapsed.Token,
                        priorDecisions: decisionCount,
                        priorPromptTokens: promptTokens,
                        priorCompletionTokens: completionTokens,
                        priorTrace: trace,
                        priorProviderRouteHistory: providerRouteHistory);
                }
                if (goalClassification == "supported-establish-clan-gold-sale")
                {
                    trace.Add(BuildDecisionOnlyStep(iteration, observation, previousReceipt, actionCatalog, controls, decision,
                        providerStartedUtc, providerDoneUtc, providerStartedTicks, null));
                    if (!requestedActions.SetEquals(GoldSaleActions) && !requestedActions.SetEquals(AllSupportedActions))
                        throw new AgentHostException("establish-clan-gold-sale-action-set-unavailable", "The Campaign request does not include the exact bounded Gold sale action set.");
                    if (client is not IAgentHostGoldSaleNativeClient goldSaleClient)
                        throw new AgentHostException("establish-clan-gold-sale-native-client-unavailable", "The Native transport does not implement the original Trade sale and active StoryMode Journal protocol.");
                    return await AgentHostEstablishClanGoldSaleLoop.RunAsync(
                        request, client, goldSaleClient, provider, elapsed.Token,
                        priorDecisions: decisionCount,
                        priorPromptTokens: promptTokens,
                        priorCompletionTokens: completionTokens,
                        priorTrace: trace,
                        priorProviderRouteHistory: providerRouteHistory);
                }
                if (!goalScopeClassified)
                {
                    failure = "The model did not classify the configured goal before the Native action gate.";
                    failureCode = "campaign-goal-classification-missing";
                    terminationReason = "campaign-goal-classification-missing";
                    break;
                }
                var decisionAction = ReadNodeString(decision["action"]);
                var decisionDone = ReadNodeBoolean(decision["done"]);
                var observeAgain = ReadNodeBoolean(decision["observeAgain"]);
                if (decisionDone)
                {
                    if (!targetReached)
                    {
                        feedback = new JsonObject
                        {
                            ["kind"] = "goal-not-satisfied",
                            ["message"] = "Fresh Native currentSettlementId does not match the selected destination.",
                            ["expectedTargetSettlementId"] = moveTargetId,
                            ["actualCurrentSettlementId"] = ReadStateString(before, "location", "currentSettlementId"),
                            ["requiredNextStep"] = movingToTarget ? "Use the currently listed observeAgain control while Native movement is active." : "Query fresh visible settlements and select a current safe destination; do not claim completion."
                        };
                        prematureCompletionCount++;
                        trace.Add(BuildDecisionOnlyStep(iteration, observation, previousReceipt, actionCatalog, controls, decision, providerStartedUtc, providerDoneUtc, providerStartedTicks, feedback));
                        if (prematureCompletionCount >= MaxRejectedDecisions)
                        {
                            failure = "The model proposed completion before fresh Native state verified arrival after the bounded correction opportunity.";
                            terminationReason = "goal-not-verified";
                            break;
                        }
                        continue;
                    }
                    completedByProvider = true;
                    terminationReason = "native-settlement-arrival-verified";
                    trace.Add(BuildDecisionOnlyStep(iteration, observation, previousReceipt, actionCatalog, controls, decision, providerStartedUtc, providerDoneUtc, providerStartedTicks, null));
                    break;
                }

                if (observeAgain)
                {
                    var waitSeconds = ReadNodeInt(decision["waitSeconds"], 1);
                    if (!movingToTarget || waitSeconds is < 1 or > 10)
                    {
                        feedback = new JsonObject { ["kind"] = "control-rejected-before-wait", ["message"] = "observeAgain is available only while the Native move order to the selected target remains active." };
                        trace.Add(BuildDecisionOnlyStep(iteration, observation, previousReceipt, actionCatalog, controls, decision, providerStartedUtc, providerDoneUtc, providerStartedTicks, feedback));
                        continue;
                    }
                    await Task.Delay(TimeSpan.FromSeconds(waitSeconds), elapsed.Token);
                    using var waitedState = await client.ReadStateAsync(elapsed.Token);
                    currentNative = CloneObject(waitedState.RootElement);
                    var arrivalAfterWait = moveTargetId != null && string.Equals(ReadStateString(currentNative, "location", "currentSettlementId"), moveTargetId, StringComparison.Ordinal);
                    var afterWait = BuildObservation(currentNative, visibleTargets, moveTargetId, moveTargetName, arrivalAfterWait);
                    var waitStep = BuildDecisionOnlyStep(iteration, observation, previousReceipt, actionCatalog, controls, decision, providerStartedUtc, providerDoneUtc, providerStartedTicks, null);
                    waitStep["observationAfter"] = afterWait;
                    waitStep["control"] = new JsonObject { ["kind"] = "bounded-observe-again", ["waitSeconds"] = waitSeconds };
                    trace.Add(waitStep);
                    feedback = null;
                    continue;
                }

                if (!TryResolveCampaignAction(decision, visibleTargets, out var nativeAction, out var nativeArguments, out var selectedTarget, out var rejection))
                {
                    feedback = new JsonObject
                    {
                        ["kind"] = "decision-rejected-before-native",
                        ["code"] = "host-action-validation-failed",
                        ["message"] = rejection,
                        ["requiredNextStep"] = "Use the latest mapSettlementTargets receipt and select only one of its safe visible settlement IDs."
                    };
                    trace.Add(BuildRejectedDecisionStep(iteration, observation, previousReceipt, actionCatalog, controls, feedback, providerStartedUtc, providerDoneUtc, providerStartedTicks, decision));
                    continue;
                }

                var priorReceiptForStep = previousReceipt?.DeepClone() as JsonObject;
                var actionStartedUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                JsonObject nativeReceipt;
                nativeActionInFlight = nativeAction;
                try
                {
                    using var response = await client.ExecuteCampaignActionAsync(nativeAction!, nativeArguments!, elapsed.Token);
                    nativeReceipt = CloneObject(response.RootElement);
                }
                catch (AgentHostException exception) when (exception.Code == "native-command-timeout")
                {
                    nativeActionInFlight = null;
                    failure = "The Native action result timed out and may be ambiguous; Host stopped without resubmitting it.";
                    terminationReason = "native-action-result-ambiguous";
                    nativeReceipt = new JsonObject { ["action"] = nativeAction, ["status"] = "timeout-ambiguous", ["error"] = exception.Code };
                    trace.Add(BuildNativeActionStep(iteration, observation, priorReceiptForStep, actionCatalog, controls, decision, nativeReceipt, observation, providerStartedUtc, providerDoneUtc, actionStartedUtc, DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture), providerStartedTicks, actionExecuted: false));
                    break;
                }

                nativeActionInFlight = null;
                var actionDoneUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                var actionCompleted = string.Equals(ReadString(nativeReceipt, "status"), "completed", StringComparison.Ordinal);
                actionsExecuted += actionCompleted ? 1 : 0;
                previousReceipt = BuildSafeReceipt(nativeReceipt, nativeAction!, selectedTarget);
                if (nativeAction == "mapSettlementTargets") visibleTargets = BuildSafeVisibleTargets(nativeReceipt,
                    safeSettlementArrivalOnly ? excludedSettlementIds : null, settlementsOnly: safeSettlementArrivalOnly);
                else if (nativeAction == "move" && actionCompleted)
                {
                    moveTargetId = selectedTarget?.Id;
                    moveTargetName = selectedTarget?.Name;
                    visibleTargets = null;
                }

                using (var refreshedState = await client.ReadStateAsync(elapsed.Token)) currentNative = CloneObject(refreshedState.RootElement);
                var arrivedAfterAction = moveTargetId != null && string.Equals(ReadStateString(currentNative, "location", "currentSettlementId"), moveTargetId, StringComparison.Ordinal);
                var observationAfterAction = BuildObservation(currentNative, visibleTargets, moveTargetId, moveTargetName, arrivedAfterAction);
                trace.Add(BuildNativeActionStep(iteration, observation, priorReceiptForStep, actionCatalog, controls, decision, nativeReceipt, observationAfterAction, providerStartedUtc, providerDoneUtc, actionStartedUtc, actionDoneUtc, providerStartedTicks, actionCompleted));
                feedback = actionCompleted ? null : new JsonObject { ["kind"] = "native-action-rejected", ["message"] = "The Native action was rejected; use the new state and current action catalog without repeating stale inputs." };
            }

            if (!completedByProvider && terminationReason is null)
            {
                terminationReason = decisionCount >= maxDecisions ? "decision-limit-reached" : "host-stopped-before-goal";
                failure = "The Host stopped before Native arrival was verified.";
            }
        }
        catch (OperationCanceledException)
        {
            var stopRequested = cancellationToken.IsCancellationRequested;
            var actionResultIsAmbiguous = stopRequested && nativeActionInFlight != null;
            failure = actionResultIsAmbiguous
                ? "Stop arrived while a Native action was in flight; its result is uncertain and Host will not replay it."
                : stopRequested ? "Host stop was requested; no further Native action will be issued." : "The bounded Campaign loop exceeded its time limit.";
            terminationReason = actionResultIsAmbiguous ? "native-action-result-ambiguous" : stopRequested ? "host-stop-requested" : "campaign-loop-timeout";
            failureExceptionType = nameof(OperationCanceledException);
        }
        catch (Exception exception)
        {
            failure = exception.Message;
            failureCode = exception is AgentHostException hostException ? hostException.Code : null;
            terminationReason = "campaign-loop-failed";
            failureExceptionType = exception.GetType().Name;
            hostFailureStack = exception.StackTrace;
        }

        var goalVerified = moveTargetId != null && currentNative != null && string.Equals(ReadStateString(currentNative, "location", "currentSettlementId"), moveTargetId, StringComparison.Ordinal);
        return new JsonObject
        {
            ["status"] = completedByProvider && goalVerified ? "completed" : "failed",
            ["runId"] = runId,
            ["contractId"] = "native-map-arrival-v1",
            ["providerModelId"] = provider.ModelId,
            ["providerConfigurationSource"] = provider.ConfigurationSource,
            ["decisions"] = decisionCount,
            ["decisionCount"] = decisionCount,
            ["actionsExecuted"] = actionsExecuted,
            ["firstDecisionRequiresGoalClassification"] = firstDecisionRequiresGoalClassification,
            ["firstDecisionListsSupportedGoalClassification"] = firstDecisionListsSupportedGoalClassification,
            ["firstDecisionListsUnsupportedGoalClassification"] = firstDecisionListsUnsupportedGoalClassification,
            ["promptTokens"] = promptTokens,
            ["completionTokens"] = completionTokens,
            ["providerPromptCacheHitTokens"] = provider is OllamaNativeProvider cacheMeter ? cacheMeter.PromptCacheHitTokens : null,
            ["providerPromptCacheMissTokens"] = provider is OllamaNativeProvider missMeter ? missMeter.PromptCacheMissTokens : null,
            ["providerActualCostEstimateCny"] = provider is OllamaNativeProvider actualCostMeter ? actualCostMeter.ActualCostEstimateCny : null,
            ["providerReservedCostUpperCny"] = provider is OllamaNativeProvider costMeter ? costMeter.ReservedCostUpperBoundCny : null,
            ["providerRouteHistory"] = providerRouteHistory,
            ["termination"] = new JsonObject { ["reason"] = terminationReason, ["completedByProvider"] = completedByProvider, ["goalVerified"] = goalVerified },
            ["failure"] = failure,
            ["failureCode"] = failureCode,
            ["failureExceptionType"] = failureExceptionType,
            ["hostFailureStack"] = hostFailureStack,
            ["trace"] = trace
        };
        }
    }

    private static JsonArray BuildActionCatalog(JsonArray? targets, bool moving, bool goalVerified)
    {
        var catalog = new JsonArray();
        if (moving || goalVerified) return catalog;
        if (targets is null)
            catalog.Add(new JsonObject { ["action"] = "mapSettlementTargets", ["arguments"] = new JsonArray() });
        else if (targets.Count > 0)
            catalog.Add(new JsonObject { ["action"] = "move", ["arguments"] = new JsonArray(JsonValue.Create("SettlementId")) });
        return catalog;
    }

    private static JsonArray BuildControlCatalog(bool moving, bool goalVerified, JsonObject? state = null)
    {
        var controls = new JsonArray();
        var context = state?["context"] as JsonObject;
        if (state is not null &&
            ((AgentHostCampaignStateFacts.IsActiveEncounter(state) && !AgentHostCampaignStateFacts.IsNativeLocationMenu(state)) ||
             ReadBoolean(context, "escapeMenuOpen") || ReadBoolean(context, "inquiryOpen") || context?["conversation"] is JsonObject))
            return controls;
        if (moving) controls.Add("observeAgain");
        if (goalVerified) controls.Add("done");
        return controls;
    }

    internal static JsonArray BuildGoalScopeClassificationControls(JsonObject? currentState = null, bool safeSettlementArrivalOnly = false)
    {
        if (safeSettlementArrivalOnly) return new JsonArray("supportedMapArrivalGoal", "unsupportedGoal");
        var controls = new JsonArray("supportedMapArrivalGoal", "supportedVillageToolsQuestGoal", "supportedBattleSimulationGoal", "supportedBattleAndCaptivityGoal");
        var activeEycQuest = HasObservedEstablishYourClanQuest(currentState);
        if (activeEycQuest || HasPostTutorialTrainingFieldMap(currentState))
            controls.Add("supportedEstablishYourClanGoal");
        if (activeEycQuest)
        {
            controls.Add("supportedEstablishClanGoldSaleGoal");
        }
        if (HasObservedPlayerCaptivity(currentState)) controls.Add("supportedCaptivityRecoveryGoal");
        controls.Add("unsupportedGoal");
        return controls;
    }

    internal static bool ShouldReconsiderUnsupportedEycScope(string goal, JsonArray controls, bool goalScopeClassified, int reconsiderations) =>
        !goalScopeClassified && reconsiderations < MaxUnsupportedEycScopeReconsiderations &&
        AgentHostDecisionCycle.IsExplicitEstablishYourClanGoal(goal) &&
        controls.Any(control => control?.GetValue<string>() == "supportedEstablishYourClanGoal");

    private static bool HasObservedEstablishYourClanQuest(JsonObject? state) =>
        (state?["quests"] as JsonArray)?.OfType<JsonObject>().Any(quest =>
            string.Equals(ReadString(quest, "id"), "rebuild_player_clan_storymode_quest", StringComparison.Ordinal)) == true;

    internal static bool HasPostTutorialTrainingFieldMap(JsonObject? state)
    {
        var context = state?["context"] as JsonObject;
        var location = state?["location"] as JsonObject;
        var lifecycle = state?["storyModeEstablishClanStatus"] as JsonObject;
        return ReadString(lifecycle, "questId") == AgentHostStoryModeBootstrapLoop.StoryQuestId &&
               ReadBoolean(lifecycle, "tutorialCompleted") &&
               (ReadString(lifecycle, "status") is "storymode-not-activated" or "unknown") &&
               ReadString(context, "gameState") == "MapState" &&
               ReadString(context, "menuId") == AgentHostStoryModeBootstrapLoop.TrainingFieldMenuId &&
               ReadString(location, "currentSettlementId") == AgentHostStoryModeBootstrapLoop.TrainingFieldSettlementId;
    }

    private static bool HasObservedPlayerCaptivity(JsonObject? state) =>
        ReadBoolean(((state?["context"] as JsonObject)?["captivity"] as JsonObject), "isCaptive");

    internal static bool IsSupportedRequestedActionSet(HashSet<string> requestedActions) =>
        requestedActions.SetEquals(ApprovedActions) || requestedActions.SetEquals(BattleSimulationActions) ||
        requestedActions.SetEquals(CaptivityRecoveryActions) || requestedActions.SetEquals(GoldSaleActions) ||
        requestedActions.SetEquals(AllSupportedActions);

    private static JsonObject BuildObservation(JsonObject native, JsonArray? targets, string? targetId, string? targetName, bool goalVerified)
    {
        var state = native["state"]?.DeepClone() as JsonObject ?? new JsonObject();
        state["nearbySettlements"] = targets?.DeepClone() ?? new JsonArray();
        return new JsonObject
        {
            ["status"] = "completed",
            ["campaignDay"] = native["campaignDay"]?.DeepClone(),
            ["dailyTickCount"] = native["dailyTickCount"]?.DeepClone(),
            ["timeControlMode"] = native["timeControlMode"]?.DeepClone(),
            ["state"] = state,
            ["goalVerification"] = new JsonObject
            {
                ["contractId"] = "native-map-arrival-v1",
                ["targetSettlementId"] = targetId,
                ["targetSettlementName"] = targetName,
                ["passed"] = goalVerified,
                ["evidence"] = "fresh Native currentSettlementId"
            }
        };
    }

    private static JsonObject BuildModelRequest(string runId, int iteration, string goal, JsonObject observation, JsonObject? previousReceipt, JsonObject? feedback, JsonArray actions, JsonArray controls)
    {
        var classificationRequired = actions.Count == 0 && controls.Any(control =>
            control?.GetValue<string>() is "supportedMapArrivalGoal" or "unsupportedGoal");
        var modelObservation = classificationRequired
            ? new JsonObject
            {
                ["scope"] = "goal-classification-only",
                ["message"] = "No goal-specific game action has run yet. Classify the complete requested outcome against the listed supported goals; only the selected goal executor will become available after this gate."
            }
            : observation.DeepClone();
        return new JsonObject
        {
            ["schemaVersion"] = 1,
            ["runId"] = runId,
            ["iteration"] = iteration,
            ["goal"] = goal,
            ["goalScopeClassificationRequired"] = classificationRequired,
            ["goalScopeContract"] = "native-campaign-goal-classification-v1",
            ["observation"] = modelObservation,
            ["previousActionReceipt"] = previousReceipt?.DeepClone(),
            ["decisionFeedback"] = feedback?.DeepClone(),
            ["allowedActions"] = actions.DeepClone(),
            ["allowedControls"] = controls.DeepClone(),
            ["controlArguments"] = controls.Any(control => control?.GetValue<string>() == "observeAgain")
                ? new JsonObject { ["observeAgain"] = new JsonObject { ["waitSeconds"] = new JsonObject { ["type"] = "integer", ["minimum"] = 1, ["maximum"] = 10 } } }
                : new JsonObject()
        };
    }

    internal static JsonArray BuildSafeVisibleTargets(JsonObject receipt, HashSet<string>? excludedSettlementIds = null, bool settlementsOnly = false)
    {
        if (ReadString(receipt, "status") != "completed" || receipt["data"] is not JsonObject data || data["mapSettlementTargets"] is not JsonArray targets)
            return new JsonArray();
        var candidates = targets.OfType<JsonObject>()
            .Where(target => HasExplicitBoolean(target, "hostile", expected: false) && HasExplicitBoolean(target, "underSiege", expected: false) &&
                             ReadDouble(target, "distance", double.MaxValue) > 1.0 &&
                             !string.IsNullOrWhiteSpace(ReadString(target, "id")) && !string.IsNullOrWhiteSpace(ReadString(target, "name")) &&
                             (!settlementsOnly || ReadString(target, "type") is "town" or "village" or "castle") &&
                             (excludedSettlementIds == null || !excludedSettlementIds.Contains(ReadString(target, "id")!)))
            .OrderBy(target => ReadDouble(target, "distance", double.MaxValue))
            .ThenBy(target => ReadString(target, "id"), StringComparer.Ordinal)
            .Take(12)
            .Select(target => new JsonObject
            {
                ["id"] = ReadString(target, "id"),
                ["name"] = ReadString(target, "name"),
                ["type"] = ReadString(target, "type"),
                ["distance"] = ReadDouble(target, "distance", double.MaxValue),
                ["hostile"] = false,
                ["underSiege"] = false,
                ["isInspected"] = ReadBoolean(target, "isInspected")
            });
        return new JsonArray(candidates.Cast<JsonNode?>().ToArray());
    }

    private static bool TryResolveCampaignAction(JsonObject decision, JsonArray? visibleTargets, out string? action, out JsonObject? arguments, out CampaignTarget? selectedTarget, out string rejection)
    {
        action = ReadNodeString(decision["action"]);
        arguments = null;
        selectedTarget = null;
        if (action == "mapSettlementTargets" && decision["arguments"] is JsonObject queryArguments && queryArguments.Count == 0)
        {
            arguments = new JsonObject();
            rejection = string.Empty;
            return true;
        }
        if (action != "move" || decision["arguments"] is not JsonObject decisionArguments || decisionArguments.Count != 1)
        {
            rejection = "The selected action is not in the current Native map catalog.";
            return false;
        }
        var targetId = ReadString(decisionArguments, "SettlementId");
        selectedTarget = visibleTargets?.OfType<JsonObject>()
            .Where(target => string.Equals(ReadString(target, "id"), targetId, StringComparison.Ordinal))
            .Select(target => new CampaignTarget(targetId ?? string.Empty, ReadString(target, "name") ?? string.Empty, ReadString(target, "type") ?? string.Empty))
            .FirstOrDefault();
        if (selectedTarget is null)
        {
            rejection = "move must select an ID from the latest safe, visible mapSettlementTargets result.";
            return false;
        }
        arguments = new JsonObject { ["settlementId"] = selectedTarget.Id };
        rejection = string.Empty;
        return true;
    }

    private static JsonObject BuildSafeReceipt(JsonObject response, string action, CampaignTarget? target = null)
    {
        var receipt = new JsonObject
        {
            ["action"] = action,
            ["status"] = ReadString(response, "status"),
            ["commandId"] = ReadString(response, "commandId"),
            ["targetSettlementId"] = target?.Id,
            ["targetSettlementName"] = target?.Name
        };
        if (action == "mapSettlementTargets" && response["data"] is JsonObject data && data["mapSettlementTargets"] is JsonArray targets)
        {
            receipt["dataSummary"] = new JsonObject
            {
                ["visibleTargetCount"] = targets.Count,
                ["safeCandidateCount"] = targets.OfType<JsonObject>().Count(item => !ReadBoolean(item, "hostile") && !ReadBoolean(item, "underSiege"))
            };
        }
        return receipt;
    }

    private static JsonObject BuildRejectedDecisionStep(int iteration, JsonObject observation, JsonObject? previousReceipt, JsonArray actions, JsonArray controls, JsonObject feedback, string startedUtc, string completedUtc, long providerStartedTicks, JsonObject? decision = null) =>
        new()
        {
            ["iteration"] = iteration,
            ["observationBefore"] = observation.DeepClone(),
            ["previousActionReceipt"] = previousReceipt?.DeepClone(),
            ["allowedActions"] = actions.DeepClone(),
            ["allowedControls"] = controls.DeepClone(),
            ["decisionFeedback"] = feedback.DeepClone(),
            ["decision"] = decision?.DeepClone(),
            ["timing"] = BuildTiming(startedUtc, completedUtc, null, null, providerStartedTicks),
            ["actionReceipt"] = new JsonObject { ["status"] = "decision-rejected-before-native", ["noNativeActionSent"] = true },
            ["observationAfter"] = observation.DeepClone(),
            ["actionAttempted"] = false,
            ["actionExecuted"] = false,
            ["control"] = new JsonObject { ["kind"] = "decision-rejected-before-native" }
        };

    private static JsonObject BuildDecisionOnlyStep(int iteration, JsonObject observation, JsonObject? previousReceipt, JsonArray actions, JsonArray controls, JsonObject decision, string startedUtc, string completedUtc, long providerStartedTicks, JsonObject? feedback) =>
        new()
        {
            ["iteration"] = iteration,
            ["observationBefore"] = observation.DeepClone(),
            ["previousActionReceipt"] = previousReceipt?.DeepClone(),
            ["allowedActions"] = actions.DeepClone(),
            ["allowedControls"] = controls.DeepClone(),
            ["decisionFeedback"] = feedback?.DeepClone(),
            ["decision"] = decision.DeepClone(),
            ["timing"] = BuildTiming(startedUtc, completedUtc, null, null, providerStartedTicks),
            ["actionReceipt"] = new JsonObject { ["status"] = "no-native-action", ["noNativeActionSent"] = true },
            ["observationAfter"] = observation.DeepClone(),
            ["actionAttempted"] = false,
            ["actionExecuted"] = false,
            ["control"] = null
        };

    private static JsonObject BuildNativeActionStep(int iteration, JsonObject observation, JsonObject? previousReceipt, JsonArray actions, JsonArray controls, JsonObject decision, JsonObject receipt, JsonObject observationAfter, string startedUtc, string providerCompletedUtc, string actionStartedUtc, string actionCompletedUtc, long providerStartedTicks, bool actionExecuted) =>
        new()
        {
            ["iteration"] = iteration,
            ["observationBefore"] = observation.DeepClone(),
            ["previousActionReceipt"] = previousReceipt?.DeepClone(),
            ["allowedActions"] = actions.DeepClone(),
            ["allowedControls"] = controls.DeepClone(),
            ["decisionFeedback"] = null,
            ["decision"] = decision.DeepClone(),
            ["timing"] = BuildTiming(startedUtc, providerCompletedUtc, actionStartedUtc, actionCompletedUtc, providerStartedTicks),
            ["actionReceipt"] = receipt.DeepClone(),
            ["observationAfter"] = observationAfter.DeepClone(),
            ["actionAttempted"] = true,
            ["actionExecuted"] = actionExecuted,
            ["control"] = actionExecuted ? null : new JsonObject { ["kind"] = "native-action-rejected-before-state-change" }
        };

    private static JsonObject BuildTiming(string startedUtc, string providerCompletedUtc, string? actionStartedUtc, string? actionCompletedUtc, long providerStartedTicks) =>
        new()
        {
            ["providerStartedUtc"] = startedUtc,
            ["providerCompletedUtc"] = providerCompletedUtc,
            ["providerElapsedMilliseconds"] = Math.Round(Stopwatch.GetElapsedTime(providerStartedTicks).TotalMilliseconds, 2),
            ["actionStartedUtc"] = actionStartedUtc,
            ["actionCompletedUtc"] = actionCompletedUtc,
            ["schedulerWaitCompletedUtc"] = null,
            ["observationCompletedUtc"] = actionCompletedUtc ?? providerCompletedUtc
        };

    private static bool IsRecoverableProviderDecisionError(string code) => code is
        "provider-response-invalid-json" or "provider-decision-invalid-json" or "provider-arguments-invalid-json" or "provider-decision-ambiguous" or "provider-goal-classification-unavailable" or
        "provider-action-unavailable" or "provider-arguments-missing" or "provider-argument-unavailable" or
        "provider-arguments-shape-invalid" or "provider-control-unavailable" or "provider-control-arguments-invalid" or
        "provider-stop-arguments-invalid" or "provider-reason-missing" or "provider-reason-too-long" or
        "provider-decision-field-unavailable";

    private static JsonObject CloneObject(JsonElement element) => JsonNode.Parse(element.GetRawText())?.AsObject() ?? new JsonObject();
    private static string? ReadString(JsonObject? value, string key) => value?[key] is JsonValue jsonValue && jsonValue.TryGetValue<string>(out var result) ? result : null;
    private static string? ReadNodeString(JsonNode? value) => value is JsonValue jsonValue && jsonValue.TryGetValue<string>(out var result) ? result : null;
    private static bool ReadBoolean(JsonObject? value, string key) => value?[key] is JsonValue jsonValue && jsonValue.TryGetValue<bool>(out var result) && result;
    private static bool HasExplicitBoolean(JsonObject? value, string key, bool expected) => value?[key] is JsonValue jsonValue && jsonValue.TryGetValue<bool>(out var result) && result == expected;
    private static bool ReadNodeBoolean(JsonNode? value) => value is JsonValue jsonValue && jsonValue.TryGetValue<bool>(out var result) && result;
    private static int ReadNodeInt(JsonNode? value, int fallback) => value is JsonValue jsonValue && jsonValue.TryGetValue<int>(out var result) ? result : fallback;
    private static int ReadInt(JsonObject? value, string key, int fallback) => value?[key] is JsonValue jsonValue && jsonValue.TryGetValue<int>(out var result) ? result : fallback;
    private static long ReadLong(JsonObject? value, string key, long fallback) => value?[key] is JsonValue jsonValue && jsonValue.TryGetValue<long>(out var result) ? result : fallback;
    private static double ReadDouble(JsonObject? value, string key, double fallback) => value?[key] is JsonValue jsonValue && jsonValue.TryGetValue<double>(out var result) ? result : fallback;
    private static string? ReadStateString(JsonObject native, string section, string key) => native["state"] is JsonObject state && state[section] is JsonObject nested ? ReadString(nested, key) : null;
    private static bool ReadStateBoolean(JsonObject native, string section, string key) => native["state"] is JsonObject state && state[section] is JsonObject nested && ReadBoolean(nested, key);
    private static int ReadInt(JsonElement value, string name, int fallback) => value.TryGetProperty(name, out var property) && property.TryGetInt32(out var result) ? result : fallback;
    private static string? ReadString(JsonElement value, string name) => value.TryGetProperty(name, out var property) && property.ValueKind == JsonValueKind.String ? property.GetString() : null;
    private static bool ReadBoolean(JsonElement value, string name) => value.TryGetProperty(name, out var property) && property.ValueKind == JsonValueKind.True;

    private static int ReadIntEnvironment(string name, int fallback, int minimum, int maximum)
    {
        var value = Environment.GetEnvironmentVariable(name);
        if (string.IsNullOrWhiteSpace(value)) return fallback;
        if (!int.TryParse(value, NumberStyles.Integer, CultureInfo.InvariantCulture, out var parsed) || parsed < minimum || parsed > maximum)
            throw new AgentHostException("campaign-loop-configuration-invalid", "The configured Host timeout is outside its supported range.");
        return parsed;
    }

    private sealed class FakeCampaignNativeClient(bool timeoutOnMove, bool includeActiveEycQuest = false) : IAgentHostCampaignNativeClient
    {
        private int _readCount;
        internal int MapQueryCount { get; private set; }
        internal int MoveCount { get; private set; }

        public Task<JsonDocument> ReadStateAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            _readCount++;
            var arrived = _readCount >= 4;
            var moving = _readCount == 3 && !timeoutOnMove;
            var response = new JsonObject
            {
                ["processId"] = 321,
                ["campaignDay"] = arrived ? 1.1 : 1.0,
                ["dailyTickCount"] = 1,
                ["timeControlMode"] = "StoppablePlay",
                ["state"] = new JsonObject
                {
                    ["context"] = new JsonObject { ["gameState"] = "MapState", ["menuId"] = "", ["timeControlMode"] = "StoppablePlay" },
                    ["quests"] = includeActiveEycQuest ? new JsonArray(new JsonObject { ["id"] = "rebuild_player_clan_storymode_quest" }) : new JsonArray(),
                    ["location"] = new JsonObject
                    {
                        ["currentSettlementId"] = arrived ? "safe" : "origin",
                        ["targetSettlementId"] = moving ? "safe" : null
                    },
                    ["party"] = new JsonObject { ["isMoving"] = moving }
                }
            };
            return Task.FromResult(Parse(response));
        }

        public Task<JsonDocument> ExecuteCampaignActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (action == "mapSettlementTargets")
            {
                MapQueryCount++;
                return Task.FromResult(Parse(new JsonObject
                {
                    ["status"] = "completed",
                    ["commandId"] = "fake-map",
                    ["data"] = new JsonObject
                    {
                        ["mapSettlementTargets"] = new JsonArray(new JsonObject
                        {
                            ["id"] = "safe", ["name"] = "Safe Town", ["type"] = "town", ["distance"] = 4.0,
                            ["hostile"] = false, ["underSiege"] = false, ["isInspected"] = true
                        })
                    }
                }));
            }
            if (action == "move")
            {
                MoveCount++;
                if (timeoutOnMove) throw new AgentHostException("native-command-timeout", "Injected ambiguous Native timeout.");
                return Task.FromResult(Parse(new JsonObject { ["status"] = "completed", ["commandId"] = "fake-move" }));
            }
            throw new AgentHostException("native-action-not-in-campaign-loop-scope", "The fake Native client received an out-of-scope action.");
        }

        private static JsonDocument Parse(JsonObject value) => JsonDocument.Parse(value.ToJsonString());
    }

    private sealed class FakeCampaignDecisionProvider : IAgentHostDecisionProvider
    {
        private readonly bool _timeoutOnMove;
        private readonly bool _unsupportedGoal;
        private readonly bool _reconsiderEycScope;

        internal int CallCount { get; private set; }
        internal int DisposeCount { get; private set; }
        internal JsonObject? FirstRequest { get; private set; }
        internal JsonObject? SecondRequest { get; private set; }
        internal string? SecondSystemPrompt { get; private set; }
        public string ModelId => "deterministic-campaign-loop-self-test";
        public string ConfigurationSource => "harness-fake-provider";

        internal FakeCampaignDecisionProvider(bool timeoutOnMove, bool unsupportedGoal = false, bool reconsiderEycScope = false)
        {
            _timeoutOnMove = timeoutOnMove;
            _unsupportedGoal = unsupportedGoal;
            _reconsiderEycScope = reconsiderEycScope;
        }

        public Task CheckConfiguredModelAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            return Task.CompletedTask;
        }

        public Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            CallCount++;
            if (CallCount == 1) FirstRequest = JsonNode.Parse(request.GetRawText())?.AsObject();
            if (CallCount == 2)
            {
                SecondRequest = JsonNode.Parse(request.GetRawText())?.AsObject();
                SecondSystemPrompt = systemPrompt;
            }
            if (CallCount == 1)
                return Task.FromResult(new ProviderDecisionResult("completed", ModelId, null, null, "stop",
                    new JsonObject { ["goalClassification"] = _unsupportedGoal || _reconsiderEycScope ? "unsupported" : "supported-map-arrival" }));
            if (_reconsiderEycScope && CallCount == 2)
                return Task.FromResult(new ProviderDecisionResult("completed", ModelId, null, null, "stop",
                    new JsonObject { ["goalClassification"] = "supported-establish-your-clan" }));
            var decision = (CallCount - 1) switch
            {
                1 => new JsonObject { ["action"] = "mapSettlementTargets", ["arguments"] = new JsonObject(), ["rationale"] = "Read current safe destinations." },
                2 => new JsonObject { ["action"] = "move", ["arguments"] = new JsonObject { ["SettlementId"] = "safe" }, ["rationale"] = "Move to the observed safe destination." },
                3 when !_timeoutOnMove => new JsonObject { ["observeAgain"] = true, ["waitSeconds"] = 1, ["reason"] = "Observe natural movement." },
                4 when !_timeoutOnMove => new JsonObject { ["done"] = true, ["reason"] = "Fresh Native state confirms arrival." },
                _ => throw new AgentHostException("campaign-loop-self-test-provider-sequence-invalid", "The runtime test requested more decisions than its scripted sequence.")
            };
            return Task.FromResult(new ProviderDecisionResult("completed", ModelId, null, null, "stop", decision));
        }

        public void Dispose() => DisposeCount++;
    }

    private sealed record CampaignTarget(string Id, string Name, string Type);
}
