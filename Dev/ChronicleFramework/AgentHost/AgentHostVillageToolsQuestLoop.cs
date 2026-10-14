using System.Diagnostics;
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal static class AgentHostVillageToolsQuestLoop
{
    internal static async Task<IReadOnlyList<object>> RunContractSelfTestsAsync()
    {
        using (var targetResponse = JsonDocument.Parse("""
        {"status":"completed","data":{"mapSettlementTargets":[
          {"id":"town-1","type":"town","hostile":false,"underSiege":false},
          {"id":"town-2","type":"town","hostile":false,"underSiege":false},
          {"id":"village-1","type":"village","hostile":false,"underSiege":false},
          {"id":"town-danger","type":"town","hostile":true,"underSiege":false}
        ]}}
        """))
        {
            var safeReceipt = BuildSafeReceipt("mapSettlementTargets", targetResponse.RootElement, new HashSet<string>(["town-1"], StringComparer.Ordinal));
            var targetIds = (safeReceipt["data"]?["mapSettlementTargets"] as JsonArray)?.OfType<JsonObject>().Select(item => ReadString(item, "id")).ToArray() ?? Array.Empty<string?>();
            if (!targetIds.SequenceEqual(new string?[] { "town-2" }, StringComparer.Ordinal))
                throw new AgentHostException("village-tools-loop-self-test-market-fallback-failed", "Map replanning must expose only fresh safe towns and exclude a town whose tools market was already checked empty.");
        }

        var questReceipt = new JsonObject
        {
            ["action"] = "questDetails", ["status"] = "completed", ["data"] = new JsonObject
            {
                ["journalStages"] = new JsonArray(
                    new JsonObject { ["hasTask"] = false, ["description"] = "卡利奥克的埃唐博尔请你带1单位工具给他。他会给你73单位亚麻作为报酬。" },
                    new JsonObject { ["hasTask"] = true, ["taskName"] = "tools", ["currentProgress"] = 1, ["targetProgress"] = 1, ["description"] = "交付工具" })
            }
        };
        if (!VerifyQuestInventoryDelta(questReceipt, InventoryReceipt(1, 0), InventoryReceipt(0, 73)) ||
            VerifyQuestInventoryDelta(questReceipt, InventoryReceipt(1, 0), InventoryReceipt(0, 72)) ||
            VerifyQuestInventoryDelta(questReceipt, InventoryReceipt(1, 0), InventoryReceipt(1, 73)))
            throw new AgentHostException("village-tools-loop-self-test-inventory-verifier-failed", "Native inventory verification did not require exact consumption and reward deltas from visible quest text.");

        var client = new FakeVillageQuestNativeClient();
        var provider = new FakeVillageQuestDecisionProvider();
        using var request = JsonDocument.Parse(JsonSerializer.Serialize(new
        {
            runId = "selftest-village-tools",
            goal = "完成当前可见的村庄工具委托",
            parentProcessId = 321,
            maxDecisions = 4,
            maxElapsedSeconds = 10,
            allowedActionNames = AgentHostCampaignLoop.ApprovedActions.ToArray()
        }));
        var result = await RunAsync(request.RootElement, client, provider, CancellationToken.None, priorDecisions: 1);
        if (ReadString(result, "status") != "failed" || ReadString(result["termination"] as JsonObject, "reason") != "decision-budget-exhausted" ||
            ReadBoolean(result, "questWasObservedActive") != true || client.Actions.Count != 3 || provider.Calls != 3 ||
            !client.Actions.SequenceEqual(new[] { "talkToSettlementHero", "dialogueSelect", "questDetails" }) || client.ClockActionCount != 0 || client.ProcessId != 321)
            throw new AgentHostException("village-tools-loop-self-test-observe-decide-act-failed", "Quest loop contract mismatch: status=" + ReadString(result, "status") + "; termination=" + ReadString(result["termination"] as JsonObject, "reason") + "; decisions=" + ReadInt(result, "decisions", -1) + "; actions=" + string.Join(",", client.Actions) + "; providerCalls=" + provider.Calls + "; clockActions=" + client.ClockActionCount + "; active=" + ReadBoolean(result, "questWasObservedActive") + ".");

        var recoveryClient = new FakeVillageQuestNativeClient();
        var recoveryProvider = new FakeVillageQuestRecoverableDecisionProvider();
        using var recoveryRequest = JsonDocument.Parse(JsonSerializer.Serialize(new
        {
            runId = "selftest-village-tools-dialogue-recovery",
            goal = "Complete the currently visible village tools quest.",
            parentProcessId = 321,
            maxDecisions = 6,
            maxElapsedSeconds = 10,
            allowedActionNames = AgentHostCampaignLoop.ApprovedActions.ToArray()
        }));
        var recoveryResult = await RunAsync(recoveryRequest.RootElement, recoveryClient, recoveryProvider, CancellationToken.None);
        var recoveryTrace = recoveryResult["trace"] as JsonArray ?? new JsonArray();
        var recoveryFeedback = recoveryProvider.FeedbackRequiredNextSteps;
        if (ReadString(recoveryResult, "status") != "failed" ||
            ReadString(recoveryResult["termination"] as JsonObject, "reason") != "decision-budget-exhausted" ||
            !recoveryClient.Actions.SequenceEqual(new[] { "talkToSettlementHero", "dialogueSelect", "questDetails" }) ||
            recoveryProvider.Calls != 6 || recoveryTrace.OfType<JsonObject>().Count(step => ReadString(step, "stage") == "decision-rejected-before-native") != 3 ||
            recoveryFeedback.Count != 3 || recoveryFeedback.Any(text => !text.Contains("Native conversation is open", StringComparison.Ordinal) ||
                !text.Contains("dialogueSelect", StringComparison.Ordinal) || !text.Contains("issue_64_quest_accept", StringComparison.Ordinal)))
            throw new AgentHostException("village-tools-loop-self-test-dialogue-provider-recovery-failed", "Repeated unavailable actions during an open conversation must receive precise feedback, remain Native-side-effect-free, and allow a later listed dialogue action.");

        var passageClient = new FakeSafePassageNativeClient();
        var passageProvider = new FakeSafePassageDecisionProvider();
        using var passageRequest = JsonDocument.Parse(JsonSerializer.Serialize(new
        {
            runId = "selftest-village-tools-safe-passage",
            goal = "Complete the currently visible village tools quest.",
            parentProcessId = 321,
            maxDecisions = 5,
            maxElapsedSeconds = 10,
            allowedActionNames = AgentHostCampaignLoop.ApprovedActions.ToArray()
        }));
        var passageResult = await RunAsync(passageRequest.RootElement, passageClient, passageProvider, CancellationToken.None);
        if (ReadString(passageResult, "status") != "failed" ||
            ReadString(passageResult["termination"] as JsonObject, "reason") != "decision-budget-exhausted" ||
            !passageClient.Actions.SequenceEqual(new[] { "dialogueSelect", "barterOptions", "barterAutoBalance", "barterOptions", "barterOffer" }) ||
            passageClient.Actions.Any(action => action is "advance" or "pause" or "resume" or "fastForward" or "battleFinish" or "battleRetreat") ||
            passageProvider.Calls != 5 || passageClient.FinalEncounterActive)
            throw new AgentHostException("village-tools-loop-self-test-safe-passage-transaction-failed", "Host did not complete the bounded Native non-fight Safe Passage action chain exactly once.");
        return [
            new { scenario = "village-tools-postcondition-requires-exact-visible-tool-consumption-and-reward-delta", passed = true },
            new { scenario = "village-tools-host-routes-classified-goal-through-native-observe-decide-act-loop", decisions = ReadInt(result, "decisions", 0), actions = client.Actions.ToArray(), clockActions = client.ClockActionCount, passed = true },
            new { scenario = "village-tools-host-recovers-from-bounded-invalid-actions-in-open-native-dialogue", decisions = recoveryProvider.Calls, rejectedDecisions = recoveryFeedback.Count, nativeActions = recoveryClient.Actions.ToArray(), passed = true },
            new { scenario = "village-tools-host-resolves-bandit-interruption-through-native-safe-passage-without-fight-or-clock-actions", decisions = ReadInt(passageResult, "decisions", 0), actions = passageClient.Actions.ToArray(), encounterCleared = !passageClient.FinalEncounterActive, passed = true }
        ];
    }

    private static JsonObject InventoryReceipt(int tools, int flax) => new()
    {
        ["action"] = "heroEquipmentOptions", ["status"] = "completed", ["data"] = new JsonObject
        {
            ["rightItems"] = new JsonArray(
                new JsonObject { ["itemId"] = "tools", ["name"] = "工具", ["itemCount"] = tools },
                new JsonObject { ["itemId"] = "flax", ["name"] = "亚麻", ["itemCount"] = flax })
        }
    };

    internal static async Task<JsonObject> RunAsync(
        JsonElement request,
        IAgentHostVillageToolsQuestNativeClient client,
        IAgentHostDecisionProvider provider,
        CancellationToken cancellationToken,
        int priorDecisions = 0,
        long priorPromptTokens = 0,
        long priorCompletionTokens = 0)
    {
        var runId = ReadString(request, "runId") ?? Guid.NewGuid().ToString("N");
        var goal = ReadString(request, "goal") ?? string.Empty;
        var maxDecisions = Math.Clamp(ReadInt(request, "maxDecisions", 100), 1, 100);
        var maxAdditionalDecisions = Math.Max(0, maxDecisions - priorDecisions);
        var maxElapsedSeconds = Math.Clamp(ReadInt(request, "maxElapsedSeconds", 1800), 1, 1800);
        var actions = request.TryGetProperty("allowedActionNames", out var names) && names.ValueKind == JsonValueKind.Array
            ? names.EnumerateArray().Where(item => item.ValueKind == JsonValueKind.String).Select(item => item.GetString()!).ToHashSet(StringComparer.Ordinal)
            : new HashSet<string>(StringComparer.Ordinal);
        if (string.IsNullOrWhiteSpace(goal) || !actions.SetEquals(AgentHostCampaignLoop.ApprovedActions))
            throw new AgentHostException("village-tools-loop-request-invalid", "The Host requires the exact bounded VillageNeedsTools Native action catalog.");

        using var elapsed = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        elapsed.CancelAfter(TimeSpan.FromSeconds(maxElapsedSeconds));
        var trace = new JsonArray();
        var decisions = priorDecisions;
        var actionsExecuted = 0;
        var rejected = 0;
        var promptTokens = priorPromptTokens;
        var completionTokens = priorCompletionTokens;
        var providerRouteHistory = new JsonArray();
        var questId = string.Empty;
        var sawQuestActive = false;
        var questDetailsObservedForActiveQuest = false;
        var marketsWithoutTools = new HashSet<string>(StringComparer.Ordinal);
        var preDeliveryInventoryCaptured = false;
        var inventoryVerifiedAfterTurnIn = false;
        JsonObject? questDetailsReceipt = null;
        JsonObject? preDeliveryInventoryReceipt = null;
        string? failure = null;
        string? failureCode = null;
        string? termination = null;
        JsonObject? previousReceipt = null;
        JsonObject? safePassageBalanceReceipt = null;
        string? safePassageEncounterPartyId = null;
        var safePassageContinueUsed = false;
        JsonObject? feedback = null;
        JsonObject? currentNative = null;
        int gameProcessId = -1;
        double startDay = double.NaN;
        var traceStartedUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);

        try
        {
            using (var firstState = await client.ReadStateAsync(elapsed.Token)) currentNative = JsonNode.Parse(firstState.RootElement.GetRawText())!.AsObject();
            gameProcessId = ReadInt(currentNative, "processId", -1);
            if (gameProcessId <= 0) throw new AgentHostException("native-process-id-invalid", "Native state did not identify its game process.");
            startDay = ReadDouble(currentNative, "campaignDay", double.NaN);

            for (var index = 1; index <= maxAdditionalDecisions; index++)
            {
                elapsed.Token.ThrowIfCancellationRequested();
                var state = currentNative?["state"] as JsonObject ?? throw new AgentHostException("native-state-missing", "The quest loop lost its latest Native state.");
                if (ReadInt(currentNative, "processId", -1) != gameProcessId)
                    throw new AgentHostException("native-process-changed", "Native observations switched Bannerlord process during the quest loop.");

                var currentContext = state["context"] as JsonObject;
                var currentBanditPartyId = ReadString(currentContext, "menuId") == "encounter_meeting" && ReadBoolean(currentContext, "encounterActive")
                    ? ReadString(currentContext, "encounteredPartyId")
                    : null;
                if (!string.Equals(currentBanditPartyId, safePassageEncounterPartyId, StringComparison.Ordinal))
                {
                    safePassageEncounterPartyId = currentBanditPartyId;
                    safePassageContinueUsed = false;
                    if (currentBanditPartyId is null) safePassageBalanceReceipt = null;
                }

                var quests = state["quests"] as JsonArray ?? new JsonArray();
                var activeQuest = quests.OfType<JsonObject>().FirstOrDefault(IsVillageToolsQuest);
                if (activeQuest is not null)
                {
                    sawQuestActive = true;
                    questId = ReadString(activeQuest, "id") ?? questId;
                }
                else if (sawQuestActive)
                {
                    var previousAction = ReadString(previousReceipt, "action");
                    if (previousAction == "heroEquipmentOptions" && ReadString(previousReceipt, "status") == "completed")
                        inventoryVerifiedAfterTurnIn = true;
                }

                var catalog = AgentHostVillageToolsQuestPolicy.BuildActionCatalog(currentNative!, previousReceipt, preDeliveryInventoryCaptured, questDetailsObservedForActiveQuest, marketsWithoutTools, safePassageBalanceReceipt, questDetailsReceipt, safePassageContinueUsed);
                var controls = AgentHostVillageToolsQuestPolicy.BuildControlCatalog(currentNative!, sawQuestActive, inventoryVerifiedAfterTurnIn);
                if (catalog.Count == 0 && controls.Count == 0)
                {
                    failure = activeQuest is null
                        ? "The supported Quest is not currently visible or has no safe recovery/verification action."
                        : "No safe Native action is available in the current Campaign context.";
                    termination = activeQuest is null ? "quest-not-observable-or-verification-incomplete" : "no-safe-action";
                    break;
                }

                var observation = BuildObservation(currentNative!, questId, sawQuestActive, inventoryVerifiedAfterTurnIn);
                var modelRequest = BuildDecisionRequest(runId, index, goal, observation, previousReceipt, feedback, catalog, controls);
                ProviderDecisionResult providerResult;
                var decisionStarted = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                try
                {
                    providerResult = await AgentHostDecisionCycle.DecideVillageToolsQuestAsync(provider, modelRequest, elapsed.Token);
                    decisions++;
                    if (providerResult.PromptTokens.HasValue) promptTokens += providerResult.PromptTokens.Value;
                    if (providerResult.CompletionTokens.HasValue) completionTokens += providerResult.CompletionTokens.Value;
                    providerRouteHistory.Add(new JsonObject
                    {
                        ["decision"] = decisions,
                        ["requestedModelId"] = provider.ModelId,
                        ["responseModelId"] = providerResult.ModelId,
                        ["routedVia"] = providerResult.RoutedVia,
                        ["responseFormatMode"] = providerResult.ResponseFormatMode,
                        ["promptTokens"] = providerResult.PromptTokens,
                        ["completionTokens"] = providerResult.CompletionTokens
                    });
                }
                catch (AgentHostException exception) when (IsRecoverableProviderError(exception.Code) && rejected < 3)
                {
                    decisions++;
                    rejected++;
                    var currentConversation = currentNative?["state"]?["context"]?["conversation"] as JsonObject;
                    var requiredNextStep = "Select exactly one action or control from the latest Native catalog and use the listed argument names and IDs.";
                    if (exception.Code == "provider-action-unavailable" && currentConversation is not null)
                    {
                        var clickableOptionIds = (currentConversation["options"] as JsonArray)?.OfType<JsonObject>()
                            .Where(option => ReadBoolean(option, "clickable"))
                            .Select(option => ReadString(option, "id"))
                            .Where(id => !string.IsNullOrWhiteSpace(id))
                            .Cast<string>()
                            .ToArray() ?? Array.Empty<string>();
                        if (catalog.OfType<JsonObject>().Any(action => ReadString(action, "action") == "dialogueSelect") && clickableOptionIds.Length > 0)
                            requiredNextStep = "A Native conversation is open. The only allowed Host action is dialogueSelect; put one exact clickable conversation option ID into arguments.OptionId. Clickable IDs: " + string.Join(", ", clickableOptionIds) + ".";
                        else if (catalog.OfType<JsonObject>().Any(action => ReadString(action, "action") == "dialogueContinue"))
                            requiredNextStep = "A Native conversation is open without a clickable option. Use the listed dialogueContinue action only.";
                    }
                    feedback = new JsonObject
                    {
                        ["kind"] = "decision-rejected-before-native",
                        ["code"] = exception.Code,
                        ["message"] = exception.Message,
                        ["nativeActionSent"] = false,
                        ["requiredNextStep"] = requiredNextStep
                    };
                    trace.Add(new JsonObject { ["iteration"] = index, ["stage"] = "decision-rejected-before-native", ["feedback"] = feedback.DeepClone() });
                    continue;
                }
                catch (Exception exception)
                {
                    failure = exception is AgentHostException hostException ? hostException.Code : exception.GetType().Name;
                    failureCode = exception is AgentHostException typed ? typed.Code : null;
                    termination = "provider-failed";
                    trace.Add(new JsonObject { ["iteration"] = index, ["stage"] = "provider-failed", ["failure"] = failure, ["detail"] = Truncate(exception.Message, 300) });
                    break;
                }

                var decision = providerResult.Decision;
                var decisionDone = ReadBoolean(decision, "done");
                if (decisionDone)
                {
                    if (!sawQuestActive || !inventoryVerifiedAfterTurnIn || activeQuest is not null)
                    {
                        rejected++;
                        feedback = new JsonObject
                        {
                            ["kind"] = "goal-not-satisfied",
                            ["questWasObservedActive"] = sawQuestActive,
                            ["questStillActive"] = activeQuest is not null,
                            ["nativeInventoryVerifiedAfterTurnIn"] = inventoryVerifiedAfterTurnIn,
                            ["requiredNextStep"] = activeQuest is null ? "Verify the current MainHero inventory through the listed native inventory options." : "Continue the current Native Quest using a listed action."
                        };
                        trace.Add(BuildDecisionStep(index, decisionStarted, modelRequest, decision, feedback, null, observationAfter: observation));
                        if (rejected > 2) { failure = "The model repeatedly proposed completion before Native Quest and inventory postconditions passed."; termination = "premature-done-rejected"; break; }
                        continue;
                    }
                    termination = "native-quest-and-inventory-observed";
                    trace.Add(BuildDecisionStep(index, decisionStarted, modelRequest, decision, null, null));
                    return BuildResult("completed", runId, provider, decisions, actionsExecuted, promptTokens, completionTokens,
                        termination, null, null, startDay, currentNative, trace, providerRouteHistory, questId, sawQuestActive, inventoryVerifiedAfterTurnIn);
                }

                if (ReadBoolean(decision, "observeAgain"))
                {
                    var waitSeconds = ReadInt(decision, "waitSeconds", 0);
                    var controlsAllowed = controls.Any(control => control?.GetValue<string>() == "observeAgain");
                    if (!controlsAllowed || waitSeconds is < 1 or > 10)
                    {
                        feedback = new JsonObject { ["kind"] = "control-rejected-before-wait", ["nativeActionSent"] = false };
                        trace.Add(BuildDecisionStep(index, decisionStarted, modelRequest, decision, feedback, null, observationAfter: observation));
                        continue;
                    }
                    await Task.Delay(TimeSpan.FromSeconds(waitSeconds), elapsed.Token);
                    using var afterWait = await client.ReadStateAsync(elapsed.Token);
                    currentNative = JsonNode.Parse(afterWait.RootElement.GetRawText())!.AsObject();
                    feedback = null;
                    trace.Add(BuildDecisionStep(index, decisionStarted, modelRequest, decision, null, null,
                        observationAfter: BuildObservation(currentNative!, questId, sawQuestActive, inventoryVerifiedAfterTurnIn),
                        control: new JsonObject { ["kind"] = "bounded-observe-again", ["waitSeconds"] = waitSeconds }));
                    continue;
                }

                if (!AgentHostVillageToolsQuestPolicy.TryResolveAction(currentNative!, previousReceipt, decision, out var action, out var arguments, out var rejection, preDeliveryInventoryCaptured, safePassageBalanceReceipt, questDetailsReceipt, safePassageContinueUsed))
                {
                    rejected++;
                    feedback = new JsonObject { ["kind"] = "decision-rejected-before-native", ["code"] = "native-precondition-not-met", ["message"] = rejection, ["nativeActionSent"] = false };
                    trace.Add(BuildDecisionStep(index, decisionStarted, modelRequest, decision, feedback, null, observationAfter: observation));
                    if (rejected > 2) { failure = "The model exceeded the bounded pre-Native rejection allowance."; termination = "rejection-limit"; break; }
                    continue;
                }

                JsonObject receipt;
                try
                {
                    using var actionResponse = await client.ExecuteVillageToolsQuestActionAsync(action!, arguments!, elapsed.Token);
                    if (ReadInt(actionResponse.RootElement, "processId", -1) != gameProcessId)
                        throw new AgentHostException("native-process-mismatch", "Native action receipt came from a different Bannerlord process.");
                    receipt = BuildSafeReceipt(action!, actionResponse.RootElement, marketsWithoutTools);
                }
                catch (AgentHostException exception) when (exception.Code == "native-command-timeout")
                {
                    failure = "Native action timed out with an ambiguous result; it was not replayed.";
                    failureCode = exception.Code;
                    termination = "native-action-result-ambiguous";
                    trace.Add(BuildDecisionStep(index, decisionStarted, modelRequest, decision, null,
                        new JsonObject { ["action"] = action, ["status"] = "timeout-ambiguous" }));
                    break;
                }

                if (ReadString(receipt, "status") == "completed") actionsExecuted++;
                if (action == "barterAutoBalance" && ReadString(receipt, "status") == "completed")
                    safePassageBalanceReceipt = receipt.DeepClone() as JsonObject;
                else if (action is "barterOffer" or "barterCancel")
                    safePassageBalanceReceipt = null;
                if (action == "dialogueContinue" && ReadString(receipt, "status") == "completed" &&
                    ReadString(currentNative?["state"]?["context"] as JsonObject, "menuId") == "encounter_meeting")
                    safePassageContinueUsed = true;
                if (action == "questDetails" && activeQuest is not null && ReadString(receipt, "status") == "completed")
                {
                    questDetailsReceipt = receipt.DeepClone() as JsonObject;
                    questDetailsObservedForActiveQuest = true;
                }
                if (action == "tradeConfirm" && ReadString(receipt, "status") == "completed")
                {
                    questDetailsReceipt = null;
                    questDetailsObservedForActiveQuest = false;
                }
                if (action == "tradeOptions" && ReadString(receipt, "status") == "completed" && !AgentHostVillageToolsQuestPolicy.HasCurrentToolsBuyOffer(receipt))
                {
                    var location = currentNative?["state"]?["location"] as JsonObject;
                    var currentTownId = ReadString(location, "currentSettlementId");
                    if (!string.IsNullOrWhiteSpace(currentTownId) &&
                        string.Equals(AgentHostVillageToolsQuestPolicy.GetCurrentSettlementType(currentNative!["state"]!.AsObject()), "town", StringComparison.Ordinal))
                        marketsWithoutTools.Add(currentTownId);
                }
                if (action == "heroEquipmentOptions" && ReadString(receipt, "status") == "completed")
                {
                    if (activeQuest is not null)
                    {
                        preDeliveryInventoryReceipt = receipt.DeepClone() as JsonObject;
                        preDeliveryInventoryCaptured = true;
                    }
                    else if (sawQuestActive && preDeliveryInventoryReceipt is not null)
                    {
                        inventoryVerifiedAfterTurnIn = VerifyQuestInventoryDelta(questDetailsReceipt, preDeliveryInventoryReceipt, receipt);
                    }
                }
                previousReceipt = receipt;
                using (var refreshed = await client.ReadStateAsync(elapsed.Token)) currentNative = JsonNode.Parse(refreshed.RootElement.GetRawText())!.AsObject();
                feedback = ReadString(receipt, "status") == "completed" ? null : new JsonObject { ["kind"] = "native-action-rejected", ["action"] = action, ["receipt"] = receipt.DeepClone() };
                trace.Add(BuildDecisionStep(index, decisionStarted, modelRequest, decision, feedback, receipt,
                    observationAfter: BuildObservation(currentNative!, questId, sawQuestActive, inventoryVerifiedAfterTurnIn),
                    actionExecuted: ReadString(receipt, "status") == "completed"));
                if (feedback is not null) rejected++; else rejected = 0;
                if (rejected > 2) { failure = "Native rejected more than the bounded action allowance."; termination = "native-rejection-limit"; break; }
            }

            if (termination is null)
            {
                failure = "The Host exhausted its bounded decision budget before Native Quest completion was verified.";
                termination = "decision-budget-exhausted";
            }
        }
        catch (OperationCanceledException)
        {
            failure = cancellationToken.IsCancellationRequested ? "Host stop was requested; no action was replayed." : "The bounded village quest loop exceeded its elapsed-time limit.";
            termination = cancellationToken.IsCancellationRequested ? "host-stop-requested" : "village-tools-loop-timeout";
        }
        catch (Exception exception)
        {
            failure = exception is AgentHostException hostException ? hostException.Message : exception.GetType().Name;
            failureCode = exception is AgentHostException typed ? typed.Code : null;
            termination = "village-tools-loop-failed";
            trace.Add(new JsonObject { ["stage"] = "loop-failed", ["failure"] = failure, ["detail"] = Truncate(exception.Message, 500) });
        }

        return BuildResult("failed", runId, provider, decisions, actionsExecuted, promptTokens, completionTokens,
            termination ?? "village-tools-loop-failed", failure, failureCode, startDay, currentNative, trace, providerRouteHistory, questId, sawQuestActive, inventoryVerifiedAfterTurnIn);
    }

    private static JsonObject BuildDecisionRequest(string runId, int iteration, string goal, JsonObject observation,
        JsonObject? previousReceipt, JsonObject? feedback, JsonArray actions, JsonArray controls) => new()
    {
        ["schemaVersion"] = 1,
        ["runId"] = runId,
        ["iteration"] = iteration,
        ["goal"] = goal,
        ["goalScopeClassificationRequired"] = false,
        ["goalScopeContract"] = "native-village-tools-quest-v1",
        ["observation"] = observation,
        ["previousActionReceipt"] = previousReceipt?.DeepClone(),
        ["decisionFeedback"] = feedback?.DeepClone(),
        ["allowedActions"] = actions.DeepClone(),
        ["allowedControls"] = controls.DeepClone()
    };

    private static JsonObject BuildObservation(JsonObject native, string questId, bool sawQuest, bool inventoryVerified) => new()
    {
        ["status"] = "completed",
        ["campaignDay"] = native["campaignDay"]?.DeepClone(),
        ["timeControlMode"] = native["timeControlMode"]?.DeepClone(),
        ["state"] = native["state"]?.DeepClone(),
        ["goalVerification"] = new JsonObject
        {
            ["contractId"] = "native-village-tools-quest-v1",
            ["questId"] = questId,
            ["questWasObservedActive"] = sawQuest,
            ["inventoryVerifiedAfterTurnIn"] = inventoryVerified
        }
    };

    internal static JsonObject BuildSafeReceipt(string action, JsonElement response, IReadOnlySet<string>? marketsWithoutTools = null)
    {
        var receipt = new JsonObject { ["action"] = action, ["status"] = ReadString(response, "status"), ["processId"] = ReadInt(response, "processId", -1) };
        if (ReadString(response, "error") is string error) receipt["error"] = error;
        if (response.TryGetProperty("data", out var data) && data.ValueKind == JsonValueKind.Object)
        {
            var parsed = JsonNode.Parse(data.GetRawText())!.AsObject();
            if (action == "mapSettlementTargets" && parsed["mapSettlementTargets"] is JsonArray targets)
                parsed["mapSettlementTargets"] = new JsonArray(targets.OfType<JsonObject>()
                    .Where(IsSafeVisibleTarget)
                    .Where(item => ReadString(item, "type") == "town")
                    .Where(item => marketsWithoutTools is null || !marketsWithoutTools.Contains(ReadString(item, "id") ?? string.Empty))
                    .Take(32)
                    .Select(item => (JsonNode?)item.DeepClone()).ToArray());
            if (action == "tradeOptions" && parsed["buyOffers"] is JsonArray offers)
                parsed["buyOffers"] = new JsonArray(offers.OfType<JsonObject>().Where(IsToolsOffer).Take(8).Select(item => (JsonNode?)item.DeepClone()).ToArray());
            if (action == "heroEquipmentOptions" && parsed["rightItems"] is JsonArray inventoryRows)
                parsed["rightItems"] = new JsonArray(inventoryRows.OfType<JsonObject>().Take(256).Select(item => (JsonNode?)item.DeepClone()).ToArray());
            receipt["data"] = parsed;
        }
        return receipt;
    }

    private static bool IsSafeVisibleTarget(JsonObject item) =>
        ReadString(item, "type") is "village" or "town" && ReadBoolean(item, "hostile") == false && ReadBoolean(item, "underSiege") == false;

    private static bool IsToolsOffer(JsonObject item)
    {
        var text = (ReadString(item, "itemId") ?? string.Empty) + " " + (ReadString(item, "name") ?? string.Empty) + " " + (ReadString(item, "taskName") ?? string.Empty);
        return text.Contains("tools", StringComparison.OrdinalIgnoreCase) || text.Contains("工具", StringComparison.Ordinal);
    }

    private static bool VerifyQuestInventoryDelta(JsonObject? questReceipt, JsonObject? beforeReceipt, JsonObject? afterReceipt)
    {
        if (ReadString(questReceipt, "action") != "questDetails" || ReadString(beforeReceipt, "action") != "heroEquipmentOptions" || ReadString(afterReceipt, "action") != "heroEquipmentOptions")
            return false;
        var data = questReceipt?["data"] as JsonObject;
        var task = (data?["journalStages"] as JsonArray)?.OfType<JsonObject>().FirstOrDefault(stage => ReadBoolean(stage, "hasTask"));
        var requestedCount = task?["targetProgress"] is JsonValue countValue && countValue.TryGetValue<int>(out var parsedCount) ? parsedCount : 0;
        if (requestedCount <= 0) return false;

        var descriptions = string.Join(" ", (data?["journalStages"] as JsonArray)?.OfType<JsonObject>().Select(stage => ReadString(stage, "description") ?? string.Empty) ?? Enumerable.Empty<string>());
        var reward = ParseReward(descriptions);
        if (reward is null) return false;

        var beforeItems = (beforeReceipt?["data"]?["rightItems"] as JsonArray)?.OfType<JsonObject>().ToArray() ?? Array.Empty<JsonObject>();
        var afterItems = (afterReceipt?["data"]?["rightItems"] as JsonArray)?.OfType<JsonObject>().ToArray() ?? Array.Empty<JsonObject>();
        var taskName = ReadString(task, "taskName") ?? "tools";
        var toolCandidate = beforeItems.FirstOrDefault(item => IsToolsOffer(item) || (ReadString(item, "itemId") == "tools"));
        if (toolCandidate is null) return false;
        var toolId = ReadString(toolCandidate, "itemId");
        if (string.IsNullOrWhiteSpace(toolId)) return false;
        var beforeTools = SumItemCount(beforeItems, toolId);
        var afterTools = SumItemCount(afterItems, toolId);
        if (beforeTools - afterTools != requestedCount) return false;

        var rewardCandidates = afterItems.Where(item => NameMatchesReward(item, reward.Value.Item)).ToArray();
        if (rewardCandidates.Length != 1) return false;
        var rewardId = ReadString(rewardCandidates[0], "itemId");
        if (string.IsNullOrWhiteSpace(rewardId)) return false;
        var rewardBefore = SumItemCount(beforeItems, rewardId);
        var rewardAfter = SumItemCount(afterItems, rewardId);
        return rewardAfter - rewardBefore == reward.Value.Count;
    }

    private static (string Item, int Count)? ParseReward(string text)
    {
        var cleaned = System.Text.RegularExpressions.Regex.Replace(text, "<[^>]+>", string.Empty);
        var chinese = System.Text.RegularExpressions.Regex.Match(cleaned, "(?<count>\\d+)\\s*单位\\s*(?<item>[^，。;；]+?)\\s*作为报酬", System.Text.RegularExpressions.RegexOptions.CultureInvariant);
        if (chinese.Success && int.TryParse(chinese.Groups["count"].Value, out var chineseCount))
            return (chinese.Groups["item"].Value.Trim(), chineseCount);
        var english = System.Text.RegularExpressions.Regex.Match(cleaned, "(?<count>\\d+)\\s+units?\\s+of\\s+(?<item>[^,.]+?)\\s+as\\s+(?:a\\s+)?reward", System.Text.RegularExpressions.RegexOptions.IgnoreCase | System.Text.RegularExpressions.RegexOptions.CultureInvariant);
        if (english.Success && int.TryParse(english.Groups["count"].Value, out var englishCount))
            return (english.Groups["item"].Value.Trim(), englishCount);
        return null;
    }

    private static bool NameMatchesReward(JsonObject item, string rewardName)
    {
        var name = ReadString(item, "name") ?? string.Empty;
        return name.Contains(rewardName, StringComparison.OrdinalIgnoreCase) || rewardName.Contains(name, StringComparison.OrdinalIgnoreCase);
    }

    private static int SumItemCount(IEnumerable<JsonObject> items, string itemId) =>
        items.Where(item => ReadString(item, "itemId") == itemId).Sum(item => item["itemCount"] is JsonValue value && value.TryGetValue<int>(out var count) ? count : 0);

    private static JsonObject BuildDecisionStep(int iteration, string startedUtc, JsonObject request, JsonObject decision, JsonObject? feedback, JsonObject? receipt,
        JsonObject? observationAfter = null, JsonObject? control = null, bool actionExecuted = false) => new()
    {
        ["iteration"] = iteration,
        ["decisionStartedUtc"] = startedUtc,
        ["goal"] = ReadString(request, "goal"),
        ["observationBefore"] = request["observation"]?.DeepClone(),
        ["observation"] = request["observation"]?.DeepClone(),
        ["observationAfter"] = observationAfter?.DeepClone(),
        ["allowedActions"] = request["allowedActions"]?.DeepClone(),
        ["allowedControls"] = request["allowedControls"]?.DeepClone(),
        ["decision"] = decision.DeepClone(),
        ["feedback"] = feedback?.DeepClone(),
        ["control"] = control?.DeepClone(),
        ["actionAttempted"] = receipt is not null,
        ["actionExecuted"] = actionExecuted,
        ["actionReceipt"] = receipt?.DeepClone(),
        ["timing"] = new JsonObject
        {
            ["providerStartedUtc"] = startedUtc,
            ["providerCompletedUtc"] = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture),
            ["actionCompletedUtc"] = receipt is null ? null : DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture),
            ["observationCompletedUtc"] = observationAfter is null ? null : DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture),
            ["schedulerWaitCompletedUtc"] = control is null ? null : DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture)
        }
    };

    private static JsonObject BuildResult(string status, string runId, IAgentHostDecisionProvider provider, int decisions, int actions,
        long promptTokens, long completionTokens, string termination, string? failure, string? failureCode, double startDay,
        JsonObject? native, JsonArray trace, JsonArray providerRouteHistory, string questId, bool sawQuest, bool inventoryVerified) => new()
    {
        ["status"] = status,
        ["runId"] = runId,
        ["contractId"] = "native-village-tools-quest-v1",
        ["providerModelId"] = provider.ModelId,
        ["providerConfigurationSource"] = provider.ConfigurationSource,
        ["decisions"] = decisions,
        ["actionsExecuted"] = actions,
        ["promptTokens"] = promptTokens,
        ["completionTokens"] = completionTokens,
        ["providerRouteHistory"] = providerRouteHistory.DeepClone(),
        ["startingCampaignDay"] = double.IsFinite(startDay) ? JsonValue.Create(startDay) : null,
        ["endingCampaignDay"] = native is null ? null : native["campaignDay"]?.DeepClone(),
        ["questId"] = questId,
        ["questWasObservedActive"] = sawQuest,
        ["inventoryVerifiedAfterTurnIn"] = inventoryVerified,
        ["termination"] = new JsonObject { ["reason"] = termination, ["goalVerified"] = status == "completed" },
        ["failure"] = failure,
        ["failureCode"] = failureCode,
        ["trace"] = trace,
        ["lastObservation"] = native is null ? null : BuildObservation(native, questId, sawQuest, inventoryVerified)
    };

    private static bool IsVillageToolsQuest(JsonObject quest)
    {
        var title = ReadString(quest, "title") ?? string.Empty;
        return title.Contains("工具", StringComparison.Ordinal) || title.Contains("tool", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsRecoverableProviderError(string code) => code is "provider-invalid-json" or "provider-invalid-decision-json" or
        "provider-response-truncated" or "provider-decision-field-unavailable" or "provider-control-unavailable" or
        "provider-action-unavailable" or "provider-argument-unavailable" or "provider-arguments-invalid-json" or "provider-arguments-missing" or
        "provider-arguments-shape-invalid" or "provider-menu-alias-arguments-invalid";

    private static string Truncate(string value, int length) => value.Length > length ? value[..length] : value;
    private static string? ReadString(JsonObject? value, string name) => value?[name] is JsonValue node && node.TryGetValue<string>(out var result) ? result : null;
    private static string? ReadString(JsonElement element, string name) => element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;
    private static bool ReadBoolean(JsonObject? value, string name) => value?[name] is JsonValue node && node.TryGetValue<bool>(out var result) && result;
    private static int ReadInt(JsonElement element, string name, int fallback) => element.TryGetProperty(name, out var value) && value.TryGetInt32(out var result) ? result : fallback;
    private static int ReadInt(JsonObject? element, string name, int fallback) => element?[name] is JsonValue value && value.TryGetValue<int>(out var result) ? result : fallback;
    private static double ReadDouble(JsonObject? value, string name, double fallback) => value?[name] is JsonValue node && node.TryGetValue<double>(out var result) ? result : fallback;

    private sealed class FakeVillageQuestNativeClient : IAgentHostVillageToolsQuestNativeClient
    {
        internal readonly List<string> Actions = [];
        internal int ClockActionCount { get; private set; }
        internal int ProcessId => 321;
        private string? _targetSettlementId;
        private string? _currentSettlementId = "village-1";
        private bool _atVillageMenu = true;
        private bool _inIssueConversation;
        private bool _questActive;

        public Task<JsonDocument> ReadStateAsync(CancellationToken cancellationToken) => Task.FromResult(ParseState());

        public Task<JsonDocument> ExecuteCampaignActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken) =>
            ExecuteVillageToolsQuestActionAsync(action, arguments, cancellationToken);

        public Task<JsonDocument> ExecuteVillageToolsQuestActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
        {
            Actions.Add(action);
            if (action is "pause" or "advance" or "fastForward") ClockActionCount++;
            var state = ParseState();
            using (state)
            {
                var response = JsonNode.Parse(state.RootElement.GetRawText())!.AsObject();
                response["commandId"] = "fake-" + Actions.Count;
                response["action"] = action;
                response["status"] = "completed";
                if (action == "move") { _targetSettlementId = null; _currentSettlementId = "village-1"; _atVillageMenu = true; }
                if (action == "talkToSettlementHero") _inIssueConversation = true;
                if (action == "dialogueSelect") { _inIssueConversation = false; _questActive = true; }
                response["data"] = action switch
                {
                    "questDetails" => new JsonObject { ["questId"] = "issue-1", ["title"] = "村庄需要工具", ["journalStages"] = new JsonArray(new JsonObject { ["taskName"] = "tools", ["currentProgress"] = 0, ["targetProgress"] = 1 }) },
                    "mapSettlementTargets" => new JsonObject { ["mapSettlementTargets"] = new JsonArray(new JsonObject { ["id"] = "village-1", ["name"] = "Test Village", ["type"] = "village", ["distance"] = 4.0, ["hostile"] = false, ["underSiege"] = false }) },
                    "move" => SetTarget(arguments),
                    "talkToSettlementHero" => new JsonObject { ["heroId"] = "hero-tools" },
                    _ => new JsonObject()
                };
                return Task.FromResult(JsonDocument.Parse(response.ToJsonString()));
            }
        }

        private JsonObject SetTarget(JsonObject arguments)
        {
            _targetSettlementId = ReadString(arguments, "settlementId");
            return new JsonObject { ["targetSettlementId"] = _targetSettlementId };
        }

        private JsonDocument ParseState()
        {
            var state = new JsonObject
            {
                ["processId"] = ProcessId,
                ["campaignDay"] = 4.0,
                ["timeControlMode"] = "Stop",
                ["state"] = new JsonObject
                {
                    ["context"] = new JsonObject
                    {
                        ["gameState"] = "MapState",
                        ["menuId"] = _atVillageMenu ? "village" : null,
                        ["conversation"] = _inIssueConversation ? new JsonObject { ["options"] = new JsonArray(new JsonObject { ["id"] = "issue_64_quest_accept", ["clickable"] = true, ["text"] = "接受委托" }) } : null
                    },
                    ["location"] = new JsonObject { ["currentSettlementId"] = _currentSettlementId, ["targetSettlementId"] = _targetSettlementId },
                    ["quests"] = _questActive ? new JsonArray(new JsonObject { ["id"] = "issue-1", ["title"] = "村庄需要工具" }) : new JsonArray(),
                    ["settlementOverlayCharacters"] = _atVillageMenu && !_questActive
                        ? new JsonArray(new JsonObject { ["heroId"] = "hero-tools", ["questMarkers"] = new JsonArray(new JsonObject { ["type"] = "AvailableIssue", ["title"] = "需要工具" }) })
                        : new JsonArray(),
                    ["availableMenuOptions"] = new JsonArray()
                }
            };
            return JsonDocument.Parse(state.ToJsonString());
        }
    }

    private sealed class FakeVillageQuestDecisionProvider : IAgentHostDecisionProvider
    {
        public string ModelId => "selftest-fake";
        public string ConfigurationSource => "selftest";
        internal int Calls { get; private set; }
        public void Dispose() { }
        public Task CheckConfiguredModelAsync(CancellationToken cancellationToken) => Task.CompletedTask;

        public Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken)
        {
            Calls++;
            var actionName = Calls switch { 1 => "talkToSettlementHero", 2 => "dialogueSelect", _ => "questDetails" };
            var decision = actionName switch
            {
                "talkToSettlementHero" => new JsonObject { ["action"] = actionName, ["arguments"] = new JsonObject { ["HeroId"] = "hero-tools" }, ["rationale"] = "Talk to the visible tools issue giver." },
                "dialogueSelect" => new JsonObject { ["action"] = actionName, ["arguments"] = new JsonObject { ["OptionId"] = "issue_64_quest_accept" }, ["rationale"] = "Accept the current visible issue." },
                "questDetails" => new JsonObject { ["action"] = actionName, ["arguments"] = new JsonObject { ["QuestId"] = "issue-1" }, ["rationale"] = "Read the active Native journal." },
                _ => new JsonObject { ["action"] = actionName, ["arguments"] = new JsonObject(), ["rationale"] = "Use only the current allowed Native action." }
            };
            var actions = request.GetProperty("allowedActions").EnumerateArray();
            if (!actions.Any(item => ReadString(JsonNode.Parse(item.GetRawText()) as JsonObject, "action") == actionName))
                throw new AgentHostException("village-tools-loop-self-test-provider-order-invalid", "The test model selected an action missing from the live policy catalog.");
            return Task.FromResult(new ProviderDecisionResult("completed", ModelId, 10, 5, "stop", decision));
        }
    }

    private sealed class FakeVillageQuestRecoverableDecisionProvider : IAgentHostDecisionProvider
    {
        public string ModelId => "selftest-dialogue-recovery";
        public string ConfigurationSource => "selftest";
        internal int Calls { get; private set; }
        internal List<string> FeedbackRequiredNextSteps { get; } = [];
        public void Dispose() { }
        public Task CheckConfiguredModelAsync(CancellationToken cancellationToken) => Task.CompletedTask;

        public Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken)
        {
            Calls++;
            if (request.TryGetProperty("decisionFeedback", out var feedback) && feedback.ValueKind == JsonValueKind.Object &&
                feedback.TryGetProperty("requiredNextStep", out var required) && required.ValueKind == JsonValueKind.String)
                FeedbackRequiredNextSteps.Add(required.GetString() ?? string.Empty);
            if (Calls is >= 2 and <= 4)
                throw new AgentHostException("provider-action-unavailable", "Action 'leave_settlement' is not in the current Native action catalog [dialogueSelect].");

            var decision = Calls switch
            {
                1 => new JsonObject { ["action"] = "talkToSettlementHero", ["arguments"] = new JsonObject { ["HeroId"] = "hero-tools" }, ["rationale"] = "Talk to the visible issue giver." },
                5 => new JsonObject { ["action"] = "dialogueSelect", ["arguments"] = new JsonObject { ["OptionId"] = "issue_64_quest_accept" }, ["rationale"] = "Select the current clickable option." },
                _ => new JsonObject { ["action"] = "questDetails", ["arguments"] = new JsonObject { ["QuestId"] = "issue-1" }, ["rationale"] = "Read the current Native journal." }
            };
            var action = ReadString(decision, "action");
            if (!request.GetProperty("allowedActions").EnumerateArray().Any(item =>
                    ReadString(JsonNode.Parse(item.GetRawText()) as JsonObject, "action") == action))
                throw new AgentHostException("village-tools-loop-self-test-provider-order-invalid", "The recovery test selected an action absent from the current catalog.");
            return Task.FromResult(new ProviderDecisionResult("completed", ModelId, 10, 5, "stop", decision));
        }
    }

    private sealed class FakeSafePassageNativeClient : IAgentHostVillageToolsQuestNativeClient
    {
        internal readonly List<string> Actions = [];
        internal int ProcessId => 321;
        internal bool FinalEncounterActive => _phase < 4;
        private int _phase;

        public Task<JsonDocument> ReadStateAsync(CancellationToken cancellationToken) => Task.FromResult(ParseState());
        public Task<JsonDocument> ExecuteCampaignActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken) =>
            ExecuteVillageToolsQuestActionAsync(action, arguments, cancellationToken);

        public Task<JsonDocument> ExecuteVillageToolsQuestActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
        {
            Actions.Add(action);
            JsonObject data = new();
            switch (action)
            {
                case "dialogueSelect": _phase = 1; break;
                case "barterOptions":
                    if (_phase == 1)
                    {
                        _phase = 2;
                        data = SafePassageOptions(isOfferDisabled: true, goldCost: 1, playerGold: 500, fingerprint: "proposal-before");
                    }
                    else
                        data = SafePassageOptions(isOfferDisabled: false, goldCost: 144, playerGold: 500, fingerprint: "proposal-balanced");
                    break;
                case "barterAutoBalance":
                    _phase = 3;
                    data = new JsonObject { ["autoBalanced"] = true, ["updatedOptions"] = SafePassageOptions(isOfferDisabled: false, goldCost: 144, playerGold: 500, fingerprint: "proposal-balanced") };
                    break;
                case "barterOffer":
                    if (ReadString(arguments, "expectedSessionId") != "session-1" || ReadString(arguments, "expectedProposalFingerprint") != "proposal-balanced")
                        throw new AgentHostException("village-tools-safe-passage-self-test-native-precondition-missing", "Host omitted the Native session/proposal precondition on Offer.");
                    _phase = 4;
                    break;
                default: throw new AgentHostException("village-tools-safe-passage-self-test-unexpected-action", "Unexpected action in the Safe Passage Host scenario: " + action);
            }
            var response = new JsonObject
            {
                ["status"] = "completed", ["processId"] = ProcessId, ["action"] = action, ["data"] = data
            };
            return Task.FromResult(JsonDocument.Parse(response.ToJsonString()));
        }

        private JsonDocument ParseState()
        {
            var encounterActive = _phase < 4;
            var options = _phase == 0
                ? new JsonArray(
                    new JsonObject { ["id"] = "bandit_start_defender_1", ["text"] = "Fight", ["clickable"] = true },
                    new JsonObject { ["id"] = "bandit_start_defender_2", ["text"] = "Find a compromise", ["clickable"] = true })
                : new JsonArray();
            var state = new JsonObject
            {
                ["context"] = new JsonObject
                {
                    ["gameState"] = "MapState", ["menuId"] = encounterActive ? "encounter_meeting" : null,
                    ["encounterActive"] = encounterActive, ["encounteredPartyId"] = encounterActive ? "looters_1" : null,
                    ["conversation"] = encounterActive ? new JsonObject { ["options"] = options } : null
                },
                ["location"] = new JsonObject { ["currentSettlementId"] = null, ["targetSettlementId"] = null },
                ["nearbyParties"] = encounterActive ? new JsonArray(new JsonObject { ["id"] = "looters_1", ["name"] = "Looter", ["type"] = "bandit", ["hostile"] = true }) : new JsonArray(),
                ["quests"] = new JsonArray(new JsonObject { ["id"] = "quest-tools", ["title"] = "Village Needs Tools" }),
                ["availableMenuOptions"] = new JsonArray()
            };
            return JsonDocument.Parse(new JsonObject { ["status"] = "completed", ["processId"] = ProcessId, ["campaignDay"] = 5.0, ["timeControlMode"] = "Stop", ["state"] = state }.ToJsonString());
        }

        private static JsonObject SafePassageOptions(bool isOfferDisabled, int goldCost, int playerGold, string fingerprint) => new()
        {
            ["sessionId"] = "session-1", ["proposalFingerprint"] = fingerprint,
            ["context"] = "contextual:safe_passage_barterable", ["contextInitializer"] = "InitializeSafePassageBarterContext",
            ["gameState"] = "MapState", ["isOfferDisabled"] = isOfferDisabled, ["playerGold"] = playerGold,
            ["candidates"] = new JsonArray(
                new JsonObject { ["nativeType"] = "safe_passage_barterable", ["list"] = "leftOffer", ["originalPartyId"] = "looters_1", ["isOffered"] = true },
                new JsonObject { ["nativeType"] = "gold_barterable", ["list"] = "rightGold", ["currentAmount"] = goldCost, ["isOffered"] = goldCost > 1 })
        };
    }

    private sealed class FakeSafePassageDecisionProvider : IAgentHostDecisionProvider
    {
        internal int Calls { get; private set; }
        public string ModelId => "selftest-safe-passage";
        public string ConfigurationSource => "selftest";
        public void Dispose() { }
        public Task CheckConfiguredModelAsync(CancellationToken cancellationToken) => Task.CompletedTask;

        public Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken)
        {
            Calls++;
            var allowed = request.GetProperty("allowedActions").EnumerateArray().FirstOrDefault();
            var action = allowed.ValueKind == JsonValueKind.Object ? allowed.GetProperty("action").GetString() : null;
            if (string.IsNullOrWhiteSpace(action)) throw new AgentHostException("village-tools-safe-passage-self-test-empty-catalog", "The fake provider received no Native actions.");
            var arguments = new JsonObject();
            if (action == "dialogueSelect") arguments["OptionId"] = "bandit_start_defender_2";
            var decision = new JsonObject { ["action"] = action, ["arguments"] = arguments, ["rationale"] = "Use the current safe Native option." };
            return Task.FromResult(new ProviderDecisionResult("completed", ModelId, 10, 5, "stop", decision));
        }
    }
}
