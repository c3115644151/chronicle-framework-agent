using System.Diagnostics;
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal static class AgentHostSupplyLoop
{
    private const string SupplyContractId = "sargot-three-day-food-v1";
    private const int MaxRejectedDecisions = 2;
    private static readonly HashSet<string> SupportedActions = new(StringComparer.Ordinal)
    {
        "menuSelect", "foodOptions", "provision", "tradeConfirm", "rest"
    };

    internal static async Task<JsonObject> RunAsync(JsonElement request, string protocolRoot, CancellationToken cancellationToken)
    {
        var runId = ReadString(request, "runId") ?? Guid.NewGuid().ToString("N");
        var goal = ReadString(request, "goal");
        var targetSettlementId = ReadString(request, "targetSettlementId");
        var maxDecisions = ReadInt(request, "maxDecisions", 24);
        var maxElapsedSeconds = ReadInt(request, "maxElapsedSeconds", 300);
        var contract = request.TryGetProperty("completionContract", out var completionContract) ? completionContract.Clone() : default;
        if (string.IsNullOrWhiteSpace(goal) || string.IsNullOrWhiteSpace(targetSettlementId) ||
            maxDecisions is < 1 or > 24 || maxElapsedSeconds is < 1 or > 300 ||
            contract.ValueKind != JsonValueKind.Object || ReadString(contract, "contractId") != SupplyContractId)
            throw new AgentHostException("supply-loop-request-invalid", "The Host requires the frozen local supply goal, Native settlement, limits, and completion contract.");
        var requestedActions = request.TryGetProperty("allowedActionNames", out var actionNames) && actionNames.ValueKind == JsonValueKind.Array
            ? new HashSet<string>(actionNames.EnumerateArray().Where(item => item.ValueKind == JsonValueKind.String).Select(item => item.GetString()!), StringComparer.Ordinal)
            : new HashSet<string>(StringComparer.Ordinal);
        if (!requestedActions.SetEquals(SupportedActions))
            throw new AgentHostException("supply-loop-action-scope-invalid", "The Host supply loop only accepts the five previously verified Native actions.");
        var nativeTimeoutSeconds = ReadIntEnvironment("CHRONICLE_LLM_TIMEOUT_SECONDS", 180, 5, 240);
        var client = new NativeMailboxClient(protocolRoot, TimeSpan.FromSeconds(nativeTimeoutSeconds));
        using var provider = OllamaNativeProvider.FromEnvironment();
        using var elapsed = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        elapsed.CancelAfter(TimeSpan.FromSeconds(maxElapsedSeconds));

        var trace = new List<JsonObject>();
        var nativeActionsExecuted = 0;
        var decisionCount = 0;
        var rejectedCount = 0;
        long inputTokens = 0;
        long outputTokens = 0;
        JsonObject? previousReceipt = null;
        JsonObject? feedback = null;
        string lastProviderCompletedUtc = string.Empty;
        string? failure = null;
        string? failureExceptionType = null;
        string? failureDetail = null;
        string? failureStack = null;
        string? terminationReason = null;
        var completedByProvider = false;
        var goalVerified = false;
        JsonObject? currentNative = null;
        int startingDailyTick = 0;
        var acceptedFoodPurchase = false;
        var completedRequestedRest = false;
        var loopStage = "read-start-state";
        string? lastSelectedAction = null;

        try
        {
            using (var initial = await client.ReadStateAsync(elapsed.Token)) currentNative = CloneObject(initial.RootElement);
            var nativeGameProcessId = ReadInt(currentNative, "processId", -1);
            if (nativeGameProcessId <= 0) throw new AgentHostException("native-process-id-invalid", "The active Native response did not identify its game process.");
            var startingIdentity = CloneIdentity(currentNative);
            ValidatePreparedSupplyFixture(currentNative, targetSettlementId, out startingDailyTick);

            for (var iteration = 1; iteration <= maxDecisions; iteration++)
            {
                elapsed.Token.ThrowIfCancellationRequested();
                if (decisionCount >= maxDecisions) break;

                loopStage = "evaluate-completion-contract";
                var nativeObservation = currentNative ?? throw new AgentHostException("native-observation-missing", "The Host lost its current Native observation.");
                var contractResult = EvaluateCompletionContract(nativeObservation, contract);
                if (completedRequestedRest && !contractResult.Passed)
                {
                    failure = "The requested Native rest finished, but the frozen supply conditions were not met; Host stopped instead of repeating the food purchase.";
                    terminationReason = "rest-completed-contract-failed";
                    break;
                }
                loopStage = "build-action-catalog";
                var catalog = BuildActionCatalog(nativeObservation, previousReceipt, targetSettlementId, startingDailyTick, contractResult.Passed, acceptedFoodPurchase);
                loopStage = "build-control-catalog";
                var controls = BuildControlCatalog(contractResult.Passed);
                if (catalog.Count == 0 && controls.Count == 0)
                {
                    failure = "No safe action or scheduler control is available in the current Native context.";
                    terminationReason = "no-safe-action";
                    break;
                }

                loopStage = "build-model-request";
                var modelRequest = BuildModelRequest(runId, iteration, goal!, nativeObservation, previousReceipt, feedback, contract, catalog, controls, targetSettlementId!, startingDailyTick, acceptedFoodPurchase);
                var decisionStartedUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                var providerStarted = Stopwatch.GetTimestamp();
                ProviderDecisionResult providerResult;
                try
                {
                    loopStage = "provider-call";
                    using var decisionDocument = JsonDocument.Parse(modelRequest.ToJsonString());
                    providerResult = await provider.DecideAsync(decisionDocument.RootElement, elapsed.Token);
                    decisionCount++;
                    lastProviderCompletedUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                    if (providerResult.PromptTokens.HasValue) inputTokens += providerResult.PromptTokens.Value;
                    if (providerResult.CompletionTokens.HasValue) outputTokens += providerResult.CompletionTokens.Value;
                }
                catch (AgentHostException exception) when (IsRecoverableProviderDecisionError(exception.Code) && rejectedCount < MaxRejectedDecisions)
                {
                    decisionCount++;
                    rejectedCount++;
                    lastProviderCompletedUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                    feedback = new JsonObject
                    {
                        ["kind"] = "decision-rejected-before-native",
                        ["code"] = exception.Code,
                        ["reason"] = exception.Message,
                        ["nativeActionSent"] = false,
                        ["currentActionNames"] = new JsonArray(catalog.OfType<JsonObject>().Select(item => (JsonNode?)JsonValue.Create(ReadString(item, "action"))).ToArray()),
                        ["currentControlNames"] = new JsonArray(controls.Select(item => item?.DeepClone()).ToArray()),
                        ["requiredNextStep"] = GetRequiredNextStep(nativeObservation, previousReceipt, targetSettlementId!, startingDailyTick),
                        ["instruction"] = "Use the latest Native observation and current action/control catalogs; do not repeat the rejected shape."
                    };
                    trace.Add(BuildRejectedDecisionStep(iteration, decisionStartedUtc, lastProviderCompletedUtc, nativeObservation, feedback, Stopwatch.GetTimestamp() - providerStarted));
                    continue;
                }
                catch (Exception exception)
                {
                    failure = exception is AgentHostException hostException ? hostException.Code : exception.GetType().Name;
                    terminationReason = "provider-failed";
                    var providerFailureDetail = exception.Message.Length > 400 ? exception.Message[..400] : exception.Message;
                    trace.Add(BuildFailedProviderStep(iteration, decisionStartedUtc, DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture), nativeObservation, failure, providerFailureDetail, Stopwatch.GetTimestamp() - providerStarted));
                    break;
                }

                loopStage = "normalize-decision";
                var decision = JsonNode.Parse(providerResult.Decision.ToJsonString())!.AsObject();
                var providerCompletedUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                if (decision["done"]?.GetValue<bool>() == true)
                {
                    if (!contractResult.Passed)
                    {
                        rejectedCount++;
                        feedback = new JsonObject
                        {
                            ["kind"] = "goal-not-satisfied",
                            ["failedConditions"] = contractResult.FailedConditions.DeepClone(),
                            ["doneAllowed"] = false,
                            ["currentActionNames"] = new JsonArray(catalog.OfType<JsonObject>().Select(item => (JsonNode?)JsonValue.Create(ReadString(item, "action"))).ToArray()),
                            ["currentControlNames"] = new JsonArray(controls.Select(item => item?.DeepClone()).ToArray()),
                            ["requiredNextStep"] = GetRequiredNextStep(nativeObservation, previousReceipt, targetSettlementId, startingDailyTick),
                            ["instruction"] = "This stop proposal was not executed. Do not repeat done; follow requiredNextStep using only the listed current action/control."
                        };
                        trace.Add(BuildDecisionOnlyStep(iteration, decisionStartedUtc, providerCompletedUtc, nativeObservation, decision, feedback, Stopwatch.GetTimestamp() - providerStarted));
                        if (rejectedCount > MaxRejectedDecisions)
                        {
                            failure = "The provider repeated stop proposals while Native completion conditions were still unmet.";
                            terminationReason = "premature-stop-rejection-limit";
                            break;
                        }
                        continue;
                    }

                    completedByProvider = true;
                    goalVerified = true;
                    terminationReason = "native-completion-contract-passed";
                    trace.Add(BuildDecisionOnlyStep(iteration, decisionStartedUtc, providerCompletedUtc, nativeObservation, decision, null, Stopwatch.GetTimestamp() - providerStarted));
                    break;
                }

                if (decision["observeAgain"]?.GetValue<bool>() == true)
                {
                    failure = "The Host does not expose model-driven polling during an accepted Native rest; the Host owns that asynchronous action until it completes.";
                    terminationReason = "model-poll-during-native-rest-rejected";
                    trace.Add(BuildDecisionOnlyStep(iteration, decisionStartedUtc, providerCompletedUtc, nativeObservation, decision, new JsonObject { ["kind"] = "control-rejected-before-wait", ["nativeActionSent"] = false }, Stopwatch.GetTimestamp() - providerStarted));
                    break;
                }

                var actionName = ReadString(decision, "action");
                lastSelectedAction = actionName;
                JsonObject? nativeArguments = null;
                string? validationError = null;
                var actionValid = !string.IsNullOrWhiteSpace(actionName) &&
                    TryBuildNativeArguments(actionName!, decision["arguments"] as JsonObject, nativeObservation, previousReceipt, targetSettlementId!, startingDailyTick, contractResult.Passed, acceptedFoodPurchase, out nativeArguments, out validationError);
                if (!actionValid)
                {
                    rejectedCount++;
                    feedback = new JsonObject
                    {
                        ["kind"] = "decision-rejected-before-native",
                        ["code"] = "native-precondition-not-met",
                        ["reason"] = validationError ?? "The decision was not a listed Native action.",
                        ["nativeActionSent"] = false
                    };
                    trace.Add(BuildRejectedActionStep(iteration, decisionStartedUtc, providerCompletedUtc, nativeObservation, decision, feedback, Stopwatch.GetTimestamp() - providerStarted));
                    if (rejectedCount > MaxRejectedDecisions)
                    {
                        failure = "The decision exceeded the bounded pre-Native rejection allowance.";
                        terminationReason = "rejection-limit";
                        break;
                    }
                    continue;
                }

                var nativeActionStartedUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                loopStage = "native-action-dispatch:" + actionName;
                using var actionResponse = await client.ExecuteSupplyActionAsync(actionName!, nativeArguments!, elapsed.Token);
                loopStage = "native-action-response:" + actionName;
                var actionReceipt = CloneObject(actionResponse.RootElement);
                VerifySameNativeOwner(actionReceipt, nativeGameProcessId, startingIdentity);
                var actionStatus = ReadString(actionReceipt, "status") ?? string.Empty;
                var nativeActionCompletedUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                var actionExecuted = actionStatus is "completed" or "accepted";
                if (actionExecuted) nativeActionsExecuted++;
                if (actionReceipt["state"] is not JsonObject)
                    throw new AgentHostException("native-action-post-state-missing", "Native action receipt did not include its post-action state.");
                var afterAction = actionReceipt;
                trace.Add(BuildNativeActionStep(iteration, decisionStartedUtc, providerCompletedUtc, nativeActionStartedUtc, nativeActionCompletedUtc, nativeObservation, afterAction, decision, actionReceipt, actionExecuted, Stopwatch.GetTimestamp() - providerStarted));

                if (actionStatus is not ("completed" or "accepted"))
                {
                    rejectedCount++;
                    if (!RejectedActionPreservedCriticalState(nativeObservation, afterAction))
                    {
                        failure = "A Native rejected action changed a protected supply-slice state value.";
                        terminationReason = "rejected-action-mutated-state";
                        currentNative = afterAction;
                        break;
                    }
                    feedback = new JsonObject
                    {
                        ["kind"] = "native-action-rejected",
                        ["action"] = actionName,
                        ["status"] = actionStatus,
                        ["nativeActionSent"] = true,
                        ["reason"] = ReadString(actionReceipt, "error") ?? "Native rejected the action; use the fresh state."
                    };
                    if (rejectedCount > MaxRejectedDecisions)
                    {
                        failure = "The Native action rejection allowance was exhausted.";
                        terminationReason = "rejection-limit";
                        currentNative = afterAction;
                        break;
                    }
                }
                else
                {
                    feedback = null;
                    rejectedCount = 0;
                }

                previousReceipt = actionReceipt;
                currentNative = afterAction;

                if (actionName == "tradeConfirm" && actionStatus == "completed")
                    acceptedFoodPurchase = true;

                if (actionName == "rest" && actionStatus == "accepted")
                {
                    loopStage = "await-native-rest-completion";
                    var restCompletion = await AwaitNativeRestCompletionAsync(
                        client,
                        actionReceipt,
                        iteration,
                        startingDailyTick + 3,
                        nativeGameProcessId,
                        startingIdentity,
                        elapsed.Token);
                    trace.Add(restCompletion.MonitorStep);
                    currentNative = restCompletion.CurrentObservation;
                    previousReceipt = restCompletion.FinalReceipt;
                    if (restCompletion.LeaveReceipt is not null)
                    {
                        trace.Add(restCompletion.LeaveStep!);
                        nativeActionsExecuted++;
                    }
                    if (restCompletion.RequestedRestCompleted)
                    {
                        completedRequestedRest = true;
                        var afterRestContract = EvaluateCompletionContract(currentNative, contract);
                        if (!afterRestContract.Passed)
                        {
                            failure = "The requested Native rest finished, but the frozen supply conditions were not met; Host stopped instead of repeating the food purchase.";
                            terminationReason = "rest-completed-contract-failed";
                            break;
                        }
                    }
                    feedback = null;
                    rejectedCount = 0;
                }
            }

            if (!completedByProvider && failure is null)
            {
                failure = "The Agent Host decision or elapsed-time budget was exhausted before the Native goal was verified.";
                terminationReason = "decision-budget-exhausted";
            }
        }
        catch (OperationCanceledException)
        {
            failure = "The Agent Host total elapsed-time budget expired.";
            terminationReason = "elapsed-time-budget-exhausted";
        }
        catch (Exception exception)
        {
            var code = exception is AgentHostException hostException ? hostException.Code : exception.GetType().Name;
            failure = loopStage + ":" + code;
            failureExceptionType = exception.GetType().Name;
            failureDetail = exception.Message.Length > 500 ? exception.Message[..500] : exception.Message;
            failureStack = exception.StackTrace;
            terminationReason = "native-or-host-failure";
        }

        return new JsonObject
        {
            ["status"] = completedByProvider && goalVerified ? "completed" : "failed",
            ["runId"] = runId,
            ["failureStage"] = failure is null ? null : loopStage,
            ["failureExceptionType"] = failureExceptionType,
            ["failureDetail"] = failureDetail,
            ["failureStack"] = failureStack,
            ["lastSelectedAction"] = lastSelectedAction,
            ["trace"] = new JsonArray(trace.Select(step => (JsonNode?)step).ToArray()),
            ["lastObservation"] = currentNative?.DeepClone(),
            ["actionsExecuted"] = nativeActionsExecuted,
            ["decisions"] = decisionCount,
            ["providerBudget"] = new JsonObject { ["mode"] = "token-only-local", ["maxOutputTokensPerCall"] = ReadIntEnvironment("CHRONICLE_LLM_MAX_TOKENS", 256, 64, 4096), ["maxProviderCalls"] = maxDecisions },
            ["providerUsage"] = new JsonObject { ["promptTokens"] = inputTokens, ["completionTokens"] = outputTokens, ["cost"] = (JsonNode?)null },
            ["timing"] = new JsonObject { ["providerCompletedUtc"] = lastProviderCompletedUtc },
            ["termination"] = new JsonObject
            {
                ["completedByProvider"] = completedByProvider,
                ["goalVerified"] = goalVerified,
                ["reason"] = terminationReason ?? "unknown"
            },
            ["error"] = failure
        };
    }

    private static void ValidatePreparedSupplyFixture(JsonObject response, string targetSettlementId, out int startingDailyTick)
    {
        var state = response["state"] as JsonObject ?? throw new AgentHostException("supply-start-state-invalid", "Native Campaign state was missing.");
        var party = state["party"] as JsonObject ?? throw new AgentHostException("supply-start-party-invalid", "Native MainParty was missing.");
        var economy = state["economy"] as JsonObject ?? throw new AgentHostException("supply-start-economy-invalid", "Native MainHero economy was missing.");
        var location = state["location"] as JsonObject ?? throw new AgentHostException("supply-start-location-invalid", "Native settlement location was missing.");
        var context = state["context"] as JsonObject ?? throw new AgentHostException("supply-start-context-invalid", "Native Campaign context was missing.");
        startingDailyTick = ReadInt(response, "dailyTickCount", -1);
        if (ReadString(context, "gameState") != "MapState" || ReadString(context, "menuId") != "town" ||
            ReadString(location, "currentSettlementId") != targetSettlementId ||
            ReadInt(party, "members", -1) != 6 || ReadInt(economy, "gold", -1) != 900 ||
            Math.Abs(ReadDouble(party, "food", double.NaN) - 0.95d) > 0.01d || ReadInt(party, "foodInventory", -1) != 0 ||
            Math.Abs(ReadDouble(party, "foodChange", double.NaN) - (-0.3d)) > 0.01d || ReadInt(party, "dailyWage", -1) != 10 || startingDailyTick < 0)
            throw new AgentHostException("supply-start-fixture-mismatch", "The Native Campaign did not match the prepared W5 supply fixture; Host made no action.");
    }

    private sealed record NativeRestCompletion(
        JsonObject CurrentObservation,
        JsonObject FinalReceipt,
        JsonObject? LeaveReceipt,
        JsonObject MonitorStep,
        JsonObject? LeaveStep,
        bool RequestedRestCompleted);

    private sealed record NativeRestStop(JsonObject? BeforeObservation, JsonObject? Receipt);

    private static async Task<NativeRestCompletion> AwaitNativeRestCompletionAsync(
        NativeMailboxClient client,
        JsonObject acceptedRestReceipt,
        int iteration,
        int targetDailyTick,
        int nativeGameProcessId,
        JsonObject startingIdentity,
        CancellationToken cancellationToken)
    {
        const int pollIntervalMilliseconds = 500;
        var waitStartedUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
        var waitStartedTicks = Stopwatch.GetTimestamp();
        var tickSamples = new JsonArray();
        var current = (JsonObject)acceptedRestReceipt.DeepClone();
        var lastRecordedTick = int.MinValue;
        var pollCount = 0;
        RecordTickSample(current, tickSamples, ref lastRecordedTick, "accepted");

        try
        {
            while (true)
            {
                cancellationToken.ThrowIfCancellationRequested();
                var tick = ReadInt(current, "dailyTickCount", -1);
                var state = current["state"] as JsonObject ?? throw new AgentHostException("native-rest-state-missing", "The accepted Native rest receipt omitted Campaign state.");
                var context = state["context"] as JsonObject ?? throw new AgentHostException("native-rest-context-missing", "The accepted Native rest receipt omitted Campaign context.");
                var waitIsActive = ReadString(context, "gameState") == "MapState" &&
                    ReadString(context, "menuId") == "town_wait_menus" &&
                    ReadBool(context, "isWaiting");

                if (tick >= targetDailyTick && waitIsActive && IsEnabledMenuOption(state, "wait_leave"))
                {
                    var nativeArguments = new JsonObject
                    {
                        ["optionId"] = "wait_leave",
                        ["menuId"] = ReadString(context, "menuId")
                    };
                    var actionStartedUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                    using var leaveResponse = await client.ExecuteSupplyActionAsync("menuSelect", nativeArguments, cancellationToken);
                    var leaveReceipt = CloneObject(leaveResponse.RootElement);
                    VerifySameNativeOwner(leaveReceipt, nativeGameProcessId, startingIdentity);
                    var actionCompletedUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                    if (ReadString(leaveReceipt, "status") != "completed")
                        throw new AgentHostException("native-rest-leave-rejected", "The current Native wait_leave option was rejected after the requested daily ticks.");
                    var postState = leaveReceipt["state"] as JsonObject ?? throw new AgentHostException("native-rest-leave-state-missing", "Native wait_leave omitted its post-action state.");
                    var postContext = postState["context"] as JsonObject ?? throw new AgentHostException("native-rest-leave-context-missing", "Native wait_leave omitted its post-action Campaign context.");
                    if (ReadString(postContext, "gameState") != "MapState" || ReadString(postContext, "menuId") != "town" ||
                        ReadString(postContext, "timeControlMode") != "Stop")
                        throw new AgentHostException("native-rest-leave-postcondition-failed", "Native wait_leave did not return to the Town menu with time stopped.");

                    var monitorStep = BuildNativeRestMonitorStep(iteration, acceptedRestReceipt, leaveReceipt, waitStartedUtc, actionCompletedUtc, waitStartedTicks, pollCount, targetDailyTick, tickSamples, requestedRestCompleted: true, interrupted: false);
                    var leaveStep = BuildNativeRestLeaveStep(iteration, current, leaveReceipt, actionStartedUtc, actionCompletedUtc, requestedRestCompleted: true);
                    return new NativeRestCompletion(leaveReceipt, leaveReceipt, leaveReceipt, monitorStep, leaveStep, RequestedRestCompleted: true);
                }

                if (!waitIsActive)
                {
                    var completedUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                    var monitorStep = BuildNativeRestMonitorStep(iteration, acceptedRestReceipt, current, waitStartedUtc, completedUtc, waitStartedTicks, pollCount, targetDailyTick, tickSamples, requestedRestCompleted: false, interrupted: true);
                    return new NativeRestCompletion(current, acceptedRestReceipt, null, monitorStep, null, RequestedRestCompleted: false);
                }

                await Task.Delay(pollIntervalMilliseconds, cancellationToken);
                using var observationResponse = await client.ReadStateAsync(cancellationToken);
                current = CloneObject(observationResponse.RootElement);
                VerifySameNativeOwner(current, nativeGameProcessId, startingIdentity);
                pollCount++;
                RecordTickSample(current, tickSamples, ref lastRecordedTick, "native-state-poll");
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            var safeStop = await TryStopNativeTownWaitAsync(client, nativeGameProcessId, startingIdentity);
            if (safeStop.Receipt is not null && safeStop.BeforeObservation is not null)
            {
                var stoppedUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                var leaveStep = BuildNativeRestLeaveStep(iteration, safeStop.BeforeObservation, safeStop.Receipt, waitStartedUtc, stoppedUtc, requestedRestCompleted: false);
                var monitorStep = BuildNativeRestMonitorStep(iteration, acceptedRestReceipt, safeStop.Receipt, waitStartedUtc, stoppedUtc, waitStartedTicks, pollCount, targetDailyTick, tickSamples, requestedRestCompleted: false, interrupted: true);
                return new NativeRestCompletion(safeStop.Receipt, safeStop.Receipt, safeStop.Receipt, monitorStep, leaveStep, RequestedRestCompleted: false);
            }
            throw;
        }
    }

    private static async Task<NativeRestStop> TryStopNativeTownWaitAsync(NativeMailboxClient client, int nativeGameProcessId, JsonObject startingIdentity)
    {
        using var cleanupTimeout = new CancellationTokenSource(TimeSpan.FromSeconds(8));
        try
        {
            using var stateResponse = await client.ReadStateAsync(cleanupTimeout.Token);
            var state = CloneObject(stateResponse.RootElement);
            VerifySameNativeOwner(state, nativeGameProcessId, startingIdentity);
            var campaignState = state["state"] as JsonObject;
            var context = campaignState?["context"] as JsonObject;
            if (ReadString(context, "gameState") != "MapState" || ReadString(context, "menuId") != "town_wait_menus" ||
                !ReadBool(context, "isWaiting") || campaignState is null || !IsEnabledMenuOption(campaignState, "wait_leave"))
                return new NativeRestStop(state, null);

            var args = new JsonObject { ["menuId"] = "town_wait_menus", ["optionId"] = "wait_leave" };
            using var stopResponse = await client.ExecuteSupplyActionAsync("menuSelect", args, cleanupTimeout.Token);
            var receipt = CloneObject(stopResponse.RootElement);
            VerifySameNativeOwner(receipt, nativeGameProcessId, startingIdentity);
            return new NativeRestStop(state, ReadString(receipt, "status") == "completed" ? receipt : null);
        }
        catch
        {
            return new NativeRestStop(null, null);
        }
    }

    private static void RecordTickSample(JsonObject response, JsonArray samples, ref int lastRecordedTick, string source)
    {
        var tick = ReadInt(response, "dailyTickCount", -1);
        if (tick == lastRecordedTick) return;
        lastRecordedTick = tick;
        samples.Add(new JsonObject
        {
            ["utc"] = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture),
            ["source"] = source,
            ["dailyTickCount"] = tick,
            ["campaignDay"] = response["campaignDay"]?.DeepClone(),
            ["timeControlMode"] = response["timeControlMode"]?.DeepClone()
        });
    }

    private static JsonObject BuildNativeRestMonitorStep(
        int iteration,
        JsonObject acceptedRestReceipt,
        JsonObject finalObservation,
        string startedUtc,
        string completedUtc,
        long startedTicks,
        int pollCount,
        int targetDailyTick,
        JsonArray tickSamples,
        bool requestedRestCompleted,
        bool interrupted) =>
        new()
        {
            ["iteration"] = iteration,
            ["decision"] = new JsonObject { ["hostExecution"] = "await-native-rest", ["requestedDays"] = 3 },
            ["actionAttempted"] = false,
            ["actionExecuted"] = false,
            ["observationBefore"] = acceptedRestReceipt.DeepClone(),
            ["observationAfter"] = finalObservation.DeepClone(),
            ["control"] = new JsonObject
            {
                ["kind"] = "host-await-native-rest",
                ["pollIntervalMilliseconds"] = 500,
                ["pollCount"] = pollCount,
                ["targetDailyTick"] = targetDailyTick,
                ["tickSamples"] = tickSamples.DeepClone(),
                ["requestedRestCompleted"] = requestedRestCompleted,
                ["interrupted"] = interrupted,
                ["explicitClockActions"] = new JsonArray()
            },
            ["timing"] = new JsonObject
            {
                ["startedUtc"] = startedUtc,
                ["completedUtc"] = completedUtc,
                ["elapsedMilliseconds"] = ElapsedMilliseconds(startedTicks)
            }
        };

    private static JsonObject BuildNativeRestLeaveStep(int iteration, JsonObject before, JsonObject receipt, string startedUtc, string completedUtc, bool requestedRestCompleted) =>
        new()
        {
            ["iteration"] = iteration,
            ["decision"] = new JsonObject
            {
                ["hostExecution"] = "finish-accepted-native-rest",
                ["action"] = "menuSelect",
                ["arguments"] = new JsonObject { ["OptionId"] = "wait_leave" }
            },
            ["actionAttempted"] = true,
            ["actionExecuted"] = ReadString(receipt, "status") == "completed",
            ["observationBefore"] = before.DeepClone(),
            ["observationAfter"] = receipt.DeepClone(),
            ["actionReceipt"] = receipt.DeepClone(),
            ["control"] = new JsonObject { ["kind"] = requestedRestCompleted ? "host-rest-completed" : "host-rest-safely-stopped", ["requestedRestCompleted"] = requestedRestCompleted },
            ["timing"] = new JsonObject { ["actionStartedUtc"] = startedUtc, ["actionCompletedUtc"] = completedUtc }
        };

    private static JsonObject BuildModelRequest(
        string runId,
        int iteration,
        string goal,
        JsonObject nativeResponse,
        JsonObject? previousReceipt,
        JsonObject? feedback,
        JsonElement completionContract,
        JsonArray allowedActions,
        JsonArray allowedControls,
        string targetSettlementId,
        int startingDailyTick,
        bool foodPurchaseCommitted)
    {
        var state = nativeResponse["state"]!.AsObject();
        var context = state["context"]!.AsObject();
        var menuId = ReadString(context, "menuId") ?? string.Empty;
        var party = state["party"]!.AsObject();
        var hasPurchasedFood = foodPurchaseCommitted || ReadInt(party, "foodInventory", 0) > 0 || ReadString(previousReceipt, "action") == "tradeConfirm";
        var dailyTick = ReadInt(nativeResponse, "dailyTickCount", -1);
        var relevantMenuIds = menuId switch
        {
            "town" when hasPurchasedFood => new HashSet<string>(new[] { "town_wait" }, StringComparer.Ordinal),
            "town" => new HashSet<string>(new[] { "trade" }, StringComparer.Ordinal),
            "town_wait_menus" when dailyTick >= startingDailyTick + 3 => new HashSet<string>(new[] { "wait_leave" }, StringComparer.Ordinal),
            "town_wait_menus" => new HashSet<string>(StringComparer.Ordinal),
            _ => new HashSet<string>(StringComparer.Ordinal)
        };
        var available = new JsonArray();
        if (state["availableMenuOptions"] is JsonArray menuOptions)
        {
            foreach (var optionNode in menuOptions)
            {
                if (optionNode is not JsonObject option) continue;
                var id = ReadString(option, "id");
                if (id is null || !relevantMenuIds.Contains(id)) continue;
                available.Add(new JsonObject
                {
                    ["id"] = id,
                    ["text"] = option["text"]?.DeepClone(),
                    ["available"] = option["available"]?.DeepClone(),
                    ["enabled"] = option["enabled"]?.DeepClone()
                });
            }
        }
        var economy = state["economy"]!.AsObject();
        var location = state["location"]!.AsObject();
        var inventoryScreen = state["inventoryScreen"];
        var scopedState = new JsonObject
        {
            ["schemaVersion"] = state["schemaVersion"]?.DeepClone(),
            ["campaignDay"] = state["campaignDay"]?.DeepClone(),
            ["party"] = new JsonObject
            {
                ["members"] = party["members"]?.DeepClone(),
                ["sizeLimit"] = party["sizeLimit"]?.DeepClone(),
                ["food"] = party["food"]?.DeepClone(),
                ["foodInventory"] = party["foodInventory"]?.DeepClone(),
                ["foodChange"] = party["foodChange"]?.DeepClone(),
                ["dailyWage"] = party["dailyWage"]?.DeepClone(),
                ["morale"] = party["morale"]?.DeepClone()
            },
            ["economy"] = new JsonObject { ["gold"] = economy["gold"]?.DeepClone() },
            ["location"] = new JsonObject { ["currentSettlementId"] = location["currentSettlementId"]?.DeepClone() },
            ["context"] = new JsonObject
            {
                ["gameState"] = context["gameState"]?.DeepClone(),
                ["timeControlMode"] = context["timeControlMode"]?.DeepClone(),
                ["menuId"] = context["menuId"]?.DeepClone(),
                ["isWaiting"] = context["isWaiting"]?.DeepClone()
            },
            ["inventoryScreen"] = inventoryScreen is JsonObject inventory ? new JsonObject { ["mode"] = inventory["mode"]?.DeepClone() } : null,
            ["availableMenuOptions"] = available
        };
        var safeReceipt = previousReceipt is null ? null : BuildSafeReceipt(previousReceipt);
        var request = new JsonObject
        {
            ["schemaVersion"] = 1,
            ["runId"] = runId,
            ["iteration"] = iteration,
            ["goal"] = goal,
            ["completionContract"] = JsonNode.Parse(completionContract.GetRawText()),
            ["nativeStart"] = new JsonObject { ["targetSettlementId"] = targetSettlementId, ["startingDailyTick"] = startingDailyTick },
            ["observation"] = new JsonObject
            {
                ["scope"] = "campaign-multiday-supply",
                ["state"] = scopedState,
                ["campaignDay"] = nativeResponse["campaignDay"]?.DeepClone(),
                ["dailyTickCount"] = nativeResponse["dailyTickCount"]?.DeepClone(),
                ["timeControlMode"] = nativeResponse["timeControlMode"]?.DeepClone()
            },
            ["previousActionReceipt"] = safeReceipt,
            ["decisionFeedback"] = feedback?.DeepClone(),
            ["allowedActions"] = allowedActions,
            ["allowedControls"] = allowedControls
        };
        return request;
    }

    private static JsonArray BuildActionCatalog(JsonObject nativeResponse, JsonObject? previousReceipt, string targetSettlementId, int startingDailyTick, bool goalMet, bool foodPurchaseCommitted)
    {
        var catalog = new JsonArray();
        var state = nativeResponse["state"]!.AsObject();
        var context = state["context"]!.AsObject();
        var gameState = ReadString(context, "gameState");
        var menuId = ReadString(context, "menuId");
        var inventory = state["inventoryScreen"] as JsonObject;
        var tick = ReadInt(nativeResponse, "dailyTickCount", -1);
        if (gameState == "MapState" && menuId == "town")
        {
            var hasPurchased = foodPurchaseCommitted || ReadInt(state["party"]!.AsObject(), "foodInventory", 0) > 0 || ReadString(previousReceipt, "action") == "tradeConfirm";
            var targetOption = hasPurchased ? "town_wait" : "trade";
            if (IsEnabledMenuOption(state, targetOption)) catalog.Add(Action("menuSelect", "OptionId"));
        }
        else if (gameState == "InventoryState" && ReadString(inventory, "mode") == "Trade")
        {
            var previousAction = ReadString(previousReceipt, "action");
            var previousStatus = ReadString(previousReceipt, "status");
            if (previousAction == "foodOptions" && previousStatus == "completed" && HasUsableFoodOffer(previousReceipt, state))
                catalog.Add(Action("provision", "ItemViewModelId", "Amount"));
            else if (previousAction == "provision" && previousStatus == "completed")
                catalog.Add(Action("tradeConfirm"));
            else if (previousAction != "tradeConfirm")
                catalog.Add(Action("foodOptions"));
        }
        else if (gameState == "MapState" && menuId == "town_wait_menus" && ReadBool(context, "isWaiting"))
        {
            if (previousReceipt is null || ReadString(previousReceipt, "action") != "rest" || ReadString(previousReceipt, "status") is "rejected" or "failed")
            {
                if (tick < startingDailyTick + 3) catalog.Add(Action("rest", "Days"));
            }
            else if (tick >= startingDailyTick + 3 && IsEnabledMenuOption(state, "wait_leave"))
            {
                catalog.Add(Action("menuSelect", "OptionId"));
            }
        }
        if (goalMet) return new JsonArray();
        return catalog;
    }

    private static JsonArray BuildControlCatalog(bool goalMet)
    {
        var controls = new JsonArray();
        if (goalMet)
            controls.Add("done");
        return controls;
    }

    private static JsonObject BuildSafeReceipt(JsonObject receipt)
    {
        var safe = new JsonObject();
        foreach (var name in new[] { "protocolVersion", "commandId", "action", "status", "campaignDay", "dailyTickCount", "timeControlMode", "error" })
            if (receipt.TryGetPropertyValue(name, out var value)) safe[name] = value?.DeepClone();
        if (receipt["data"] is not JsonObject data) return safe;
        var action = ReadString(receipt, "action");
        if (action == "foodOptions")
        {
            var offers = new JsonArray();
            if (data["offers"] is JsonArray sourceOffers)
            {
                foreach (var node in sourceOffers)
                {
                    if (node is not JsonObject offer || !ReadBool(offer, "isFood") || !ReadBool(offer, "isTransferable") || ReadInt(offer, "stock", 0) < 1) continue;
                    var clone = new JsonObject();
                    foreach (var name in new[] { "viewModelItemId", "itemId", "modifierId", "name", "stock", "nativeItemCost", "inventoryLogicUnitPrice", "isFood", "isTransferable" })
                        if (offer.TryGetPropertyValue(name, out var value)) clone[name] = value?.DeepClone();
                    offers.Add(clone);
                }
            }
            safe["data"] = new JsonObject { ["hasPendingChanges"] = data["hasPendingChanges"]?.DeepClone(), ["offers"] = offers };
        }
        else if (action is "provision" or "tradeConfirm" or "rest")
        {
            var safeData = new JsonObject();
            foreach (var name in new[] { "verified", "committed", "postconditionPassed", "nativeTransactionAmount", "itemId", "amount", "days" })
                if (data.TryGetPropertyValue(name, out var value)) safeData[name] = value?.DeepClone();
            if (action == "provision") safeData["hasPendingChanges"] = ReadString(receipt, "status") == "completed";
            safe["data"] = safeData;
        }
        return safe;
    }

    private static bool TryBuildNativeArguments(
        string action,
        JsonObject? arguments,
        JsonObject nativeResponse,
        JsonObject? previousReceipt,
        string targetSettlementId,
        int startingDailyTick,
        bool goalMet,
        bool foodPurchaseCommitted,
        out JsonObject? nativeArguments,
        out string? error)
    {
        nativeArguments = new JsonObject();
        error = null;
        var state = nativeResponse["state"]!.AsObject();
        var context = state["context"]!.AsObject();
        var menuId = ReadString(context, "menuId");
        switch (action)
        {
            case "menuSelect":
                var optionId = ReadString(arguments, "OptionId");
                if (string.IsNullOrWhiteSpace(optionId) || !IsEnabledMenuOption(state, optionId)) { error = "OptionId is not an enabled current Native option."; return false; }
                if (foodPurchaseCommitted && menuId == "town" && optionId == "trade") { error = "The frozen supply slice permits one committed food purchase; Trade cannot be reopened."; return false; }
                if (menuId == "town" && optionId != (ReadInt(state["party"]!.AsObject(), "foodInventory", 0) > 0 ? "town_wait" : "trade")) { error = "Town option violates the prepared supply step order."; return false; }
                if (menuId == "town_wait_menus" && (optionId != "wait_leave" || ReadInt(nativeResponse, "dailyTickCount", -1) < startingDailyTick + 3)) { error = "Wait may be exited only after three Native daily ticks."; return false; }
                nativeArguments["optionId"] = optionId;
                nativeArguments["menuId"] = menuId;
                return true;
            case "foodOptions":
                if (ReadString(context, "gameState") != "InventoryState" || ReadString(state["inventoryScreen"] as JsonObject, "mode") != "Trade" || ReadString(previousReceipt, "action") is "foodOptions" or "provision") { error = "foodOptions is not enabled in this current TradeVM state."; return false; }
                return true;
            case "provision":
                if (ReadString(context, "gameState") != "InventoryState" || ReadString(state["inventoryScreen"] as JsonObject, "mode") != "Trade" || ReadString(previousReceipt, "action") != "foodOptions" || ReadString(previousReceipt, "status") != "completed") { error = "provision requires the current Native food offer receipt."; return false; }
                var itemViewModelId = ReadString(arguments, "ItemViewModelId");
                if (ReadInt(arguments, "Amount", 0) != 1) { error = "The frozen Native supply slice purchases exactly one unit."; return false; }
                var offers = previousReceipt?["data"]?["offers"] as JsonArray;
                var eligibleOffers = offers?.OfType<JsonObject>().Where(offer => ReadBool(offer, "isFood") && ReadBool(offer, "isTransferable") && ReadInt(offer, "stock", 0) > 0 && ReadDouble(offer, "inventoryLogicUnitPrice", double.MaxValue) <= ReadInt(state["economy"]!.AsObject(), "gold", 0)).OrderBy(offer => ReadDouble(offer, "inventoryLogicUnitPrice", double.MaxValue)).ToArray() ?? Array.Empty<JsonObject>();
                if (eligibleOffers.Length == 0 || itemViewModelId is null || !string.Equals(itemViewModelId, ReadString(eligibleOffers[0], "viewModelItemId"), StringComparison.Ordinal)) { error = "provision must select the cheapest currently available affordable Native food offer."; return false; }
                nativeArguments["itemViewModelId"] = itemViewModelId;
                nativeArguments["amount"] = 1;
                return true;
            case "tradeConfirm":
                if (ReadString(context, "gameState") != "InventoryState" || ReadString(state["inventoryScreen"] as JsonObject, "mode") != "Trade" || ReadString(previousReceipt, "action") != "provision" || ReadString(previousReceipt, "status") != "completed") { error = "tradeConfirm requires one current Native provision draft."; return false; }
                return true;
            case "rest":
                if (ReadString(context, "gameState") != "MapState" || menuId != "town_wait_menus" || !ReadBool(context, "isWaiting") ||
                    (ReadString(previousReceipt, "action") == "rest" && ReadString(previousReceipt, "status") is "accepted" or "completed")) { error = "rest requires the active Native Town Wait before a rest request has been accepted."; return false; }
                if (ReadInt(arguments, "Days", 0) != 3) { error = "The frozen Native supply slice requests exactly three days."; return false; }
                nativeArguments["days"] = 3;
                return true;
            default:
                nativeArguments = null;
                error = "The action is outside the local supply allowlist.";
                return false;
        }
    }

    private static bool IsEnabledMenuOption(JsonObject state, string id)
    {
        if (state["availableMenuOptions"] is not JsonArray options) return false;
        return options.OfType<JsonObject>().Any(option => ReadString(option, "id") == id && ReadBool(option, "available") && ReadBool(option, "enabled"));
    }

    private static bool HasUsableFoodOffer(JsonObject? receipt, JsonObject state)
    {
        var offers = receipt?["data"]?["offers"] as JsonArray;
        return offers?.OfType<JsonObject>().Any(offer => ReadBool(offer, "isFood") && ReadBool(offer, "isTransferable") && ReadInt(offer, "stock", 0) > 0 && ReadDouble(offer, "inventoryLogicUnitPrice", double.MaxValue) <= ReadInt(state["economy"]!.AsObject(), "gold", 0)) == true;
    }

    private static (bool Passed, JsonArray FailedConditions) EvaluateCompletionContract(JsonObject nativeResponse, JsonElement contract)
    {
        var failed = new JsonArray();
        if (!contract.TryGetProperty("conditions", out var conditions) || conditions.ValueKind != JsonValueKind.Array)
            return (false, new JsonArray("completion-contract-conditions-missing"));
        foreach (var condition in conditions.EnumerateArray())
        {
            var id = ReadString(condition, "id") ?? "unknown-condition";
            var path = ReadString(condition, "path") ?? string.Empty;
            var operation = ReadString(condition, "operator") ?? string.Empty;
            var hasActual = TryGetPath(nativeResponse, path, out var actual);
            var hasExpected = condition.TryGetProperty("expected", out var expected);
            if (!hasActual || !hasExpected || !Compare(actual, expected, operation))
            {
                failed.Add(new JsonObject
                {
                    ["id"] = id,
                    ["path"] = path,
                    ["operator"] = operation,
                    ["expected"] = hasExpected ? JsonNode.Parse(expected.GetRawText()) : null,
                    ["actual"] = actual?.DeepClone()
                });
            }
        }
        return (failed.Count == 0, failed);
    }

    private static string GetRequiredNextStep(JsonObject nativeResponse, JsonObject? previousReceipt, string settlementId, int startingDailyTick)
    {
        var state = nativeResponse["state"] as JsonObject;
        var context = state?["context"] as JsonObject;
        var menuId = ReadString(context, "menuId");
        var gameState = ReadString(context, "gameState");
        var tick = ReadInt(nativeResponse, "dailyTickCount", -1);
        if (gameState == "InventoryState" && ReadString(state?["inventoryScreen"] as JsonObject, "mode") == "Trade" && ReadString(previousReceipt, "action") == "provision")
            return "The provision receipt is only an uncommitted TradeVM draft; select the currently enabled tradeConfirm once before waiting.";
        if (gameState == "MapState" && menuId == "town" && ReadString(state?["location"] as JsonObject, "currentSettlementId") == settlementId && ReadInt(state?["party"] as JsonObject, "foodInventory", 0) > 0 && tick < startingDailyTick + 3)
            return "Select the currently enabled town_wait menu option, then schedule one Native rest of three days.";
        if (gameState == "MapState" && menuId == "town_wait_menus" && tick < startingDailyTick + 3 && ReadBool(context, "isWaiting") && ReadString(previousReceipt, "action") != "rest")
            return "Town Wait has begun but no Native rest request has been accepted; choose the listed rest action with Days=3.";
        if (gameState == "MapState" && menuId == "town_wait_menus" && tick < startingDailyTick + 3 && ReadString(previousReceipt, "action") == "rest" && ReadString(previousReceipt, "status") == "accepted")
            return "The Host is passively monitoring the accepted Native Town Wait and will return a fresh observation after the requested ticks; do not issue another wait or time-control action.";
        if (gameState == "MapState" && menuId == "town_wait_menus" && tick >= startingDailyTick + 3)
            return "Select the currently enabled wait_leave option once, then verify the Town menu and completion contract.";
        return "Use a currently listed Native action/control to satisfy the remaining exact completion conditions; do not stop early.";
    }

    private static bool TryGetPath(JsonObject root, string path, out JsonNode? value)
    {
        JsonNode? current = root;
        foreach (var segment in path.Split('.', StringSplitOptions.RemoveEmptyEntries))
        {
            if (current is not JsonObject objectValue || !objectValue.TryGetPropertyValue(segment, out current))
            {
                value = null;
                return false;
            }
        }
        value = current;
        return value is not null;
    }

    private static bool Compare(JsonNode? actual, JsonElement expected, string operation)
    {
        if (actual is null) return false;
        if (operation == "eq")
        {
            if (expected.ValueKind == JsonValueKind.String) return ReadNodeString(actual) == expected.GetString();
            if (expected.ValueKind is JsonValueKind.True or JsonValueKind.False) return ReadNodeBool(actual) == expected.GetBoolean();
            if (expected.ValueKind == JsonValueKind.Number) return Math.Abs(ReadDouble(actual, double.NaN) - expected.GetDouble()) < 0.0001d;
            return false;
        }
        return operation == "gte" && expected.ValueKind == JsonValueKind.Number && ReadDouble(actual, double.NaN) >= expected.GetDouble();
    }

    private static bool RejectedActionPreservedCriticalState(JsonObject beforeResponse, JsonObject afterResponse)
    {
        var before = beforeResponse["state"] as JsonObject;
        var after = afterResponse["state"] as JsonObject;
        if (before is null || after is null) return false;
        var fields = new[] { "gold", "food", "foodInventory", "members" };
        foreach (var field in fields)
        {
            var left = field is "gold" ? before["economy"]?[field] : before["party"]?[field == "members" ? "members" : field];
            var right = field is "gold" ? after["economy"]?[field] : after["party"]?[field == "members" ? "members" : field];
            if (left?.ToJsonString() != right?.ToJsonString()) return false;
        }
        return ReadString(before["location"] as JsonObject, "currentSettlementId") == ReadString(after["location"] as JsonObject, "currentSettlementId") &&
            ReadString(before["context"] as JsonObject, "menuId") == ReadString(after["context"] as JsonObject, "menuId");
    }

    private static JsonObject BuildRejectedDecisionStep(int iteration, string providerStarted, string providerCompleted, JsonObject observation, JsonObject feedback, long providerStartedTicks) =>
        new()
        {
            ["iteration"] = iteration,
            ["decision"] = new JsonObject { ["rejected"] = true },
            ["actionAttempted"] = false,
            ["actionExecuted"] = false,
            ["observationBefore"] = observation.DeepClone(),
            ["observationAfter"] = observation.DeepClone(),
            ["control"] = new JsonObject { ["kind"] = "decision-rejected-before-native", ["feedback"] = feedback.DeepClone() },
            ["timing"] = new JsonObject { ["providerStartedUtc"] = providerStarted, ["providerCompletedUtc"] = providerCompleted, ["providerElapsedMilliseconds"] = ElapsedMilliseconds(providerStartedTicks) }
        };

    private static JsonObject BuildFailedProviderStep(int iteration, string providerStarted, string providerCompleted, JsonObject observation, string failure, string failureDetail, long providerStartedTicks) =>
        new()
        {
            ["iteration"] = iteration,
            ["decision"] = new JsonObject { ["providerFailed"] = true },
            ["actionAttempted"] = false,
            ["actionExecuted"] = false,
            ["observationBefore"] = observation.DeepClone(),
            ["observationAfter"] = observation.DeepClone(),
            ["control"] = new JsonObject { ["kind"] = "provider-failed", ["code"] = failure, ["reason"] = failureDetail },
            ["timing"] = new JsonObject { ["providerStartedUtc"] = providerStarted, ["providerCompletedUtc"] = providerCompleted, ["providerElapsedMilliseconds"] = ElapsedMilliseconds(providerStartedTicks) }
        };

    private static JsonObject BuildDecisionOnlyStep(int iteration, string providerStarted, string providerCompleted, JsonObject observation, JsonObject decision, JsonObject? feedback, long providerStartedTicks) =>
        new()
        {
            ["iteration"] = iteration,
            ["decision"] = decision.DeepClone(),
            ["actionAttempted"] = false,
            ["actionExecuted"] = false,
            ["observationBefore"] = observation.DeepClone(),
            ["observationAfter"] = observation.DeepClone(),
            ["actionReceipt"] = null,
            ["control"] = feedback is null ? new JsonObject { ["kind"] = "provider-stop" } : new JsonObject { ["kind"] = "goal-not-satisfied", ["feedback"] = feedback.DeepClone() },
            ["timing"] = new JsonObject { ["providerStartedUtc"] = providerStarted, ["providerCompletedUtc"] = providerCompleted, ["providerElapsedMilliseconds"] = ElapsedMilliseconds(providerStartedTicks) }
        };

    private static JsonObject BuildRejectedActionStep(int iteration, string providerStarted, string providerCompleted, JsonObject observation, JsonObject decision, JsonObject feedback, long providerStartedTicks) =>
        new()
        {
            ["iteration"] = iteration,
            ["decision"] = decision.DeepClone(),
            ["actionAttempted"] = false,
            ["actionExecuted"] = false,
            ["observationBefore"] = observation.DeepClone(),
            ["observationAfter"] = observation.DeepClone(),
            ["actionReceipt"] = null,
            ["control"] = new JsonObject { ["kind"] = "decision-rejected-before-native", ["feedback"] = feedback.DeepClone() },
            ["timing"] = new JsonObject { ["providerStartedUtc"] = providerStarted, ["providerCompletedUtc"] = providerCompleted, ["providerElapsedMilliseconds"] = ElapsedMilliseconds(providerStartedTicks) }
        };

    private static JsonObject BuildNativeActionStep(int iteration, string providerStarted, string providerCompleted, string actionStarted, string actionCompleted, JsonObject before, JsonObject after, JsonObject decision, JsonObject receipt, bool executed, long providerStartedTicks) =>
        new()
        {
            ["iteration"] = iteration,
            ["decision"] = decision.DeepClone(),
            ["actionAttempted"] = true,
            ["actionExecuted"] = executed,
            ["observationBefore"] = before.DeepClone(),
            ["observationAfter"] = after.DeepClone(),
            ["actionReceipt"] = receipt.DeepClone(),
            ["control"] = executed ? null : new JsonObject { ["kind"] = "native-action-rejected-before-state-change" },
            ["timing"] = new JsonObject { ["providerStartedUtc"] = providerStarted, ["providerCompletedUtc"] = providerCompleted, ["providerElapsedMilliseconds"] = ElapsedMilliseconds(providerStartedTicks), ["actionStartedUtc"] = actionStarted, ["actionCompletedUtc"] = actionCompleted, ["observationCompletedUtc"] = actionCompleted }
        };

    private static double ElapsedMilliseconds(long startTicks) => Math.Round(Stopwatch.GetElapsedTime(startTicks).TotalMilliseconds, 2);

    private static JsonObject Action(string name, params string[] arguments) => new()
    {
        ["action"] = name,
        ["arguments"] = new JsonArray(arguments.Select(argument => (JsonNode?)JsonValue.Create(argument)).ToArray())
    };

    private static JsonNode? GetPath(JsonNode root, string path)
    {
        JsonNode? value = root;
        foreach (var segment in path.Split('.', StringSplitOptions.RemoveEmptyEntries))
        {
            if (value is not JsonObject obj || !obj.TryGetPropertyValue(segment, out value)) return null;
        }
        return value;
    }

    private static bool IsRecoverableProviderDecisionError(string code) =>
        code is "provider-action-unavailable" or "provider-argument-unavailable" or "provider-arguments-missing" or
            "provider-arguments-shape-invalid" or "provider-control-unavailable";

    private static JsonObject CloneObject(JsonElement value) => JsonNode.Parse(value.GetRawText())!.AsObject();
    private static JsonObject CloneIdentity(JsonObject response)
    {
        var state = response["state"] as JsonObject ?? throw new AgentHostException("native-state-missing", "The Native response omitted Campaign state.");
        var identity = state["identity"] as JsonObject ?? throw new AgentHostException("native-player-identity-missing", "The Native response omitted the active player identity.");
        var party = state["party"] as JsonObject ?? throw new AgentHostException("native-main-party-missing", "The Native response omitted MainParty identity.");
        return new JsonObject
        {
            ["heroId"] = identity["heroId"]?.DeepClone(),
            ["clanId"] = identity["clanId"]?.DeepClone(),
            ["partyId"] = party["id"]?.DeepClone()
        };
    }

    private static void VerifySameNativeOwner(JsonObject response, int processId, JsonObject startingIdentity)
    {
        var currentIdentity = CloneIdentity(response);
        if (ReadInt(response, "processId", -1) != processId ||
            ReadString(currentIdentity, "heroId") != ReadString(startingIdentity, "heroId") ||
            ReadString(currentIdentity, "clanId") != ReadString(startingIdentity, "clanId") ||
            ReadString(currentIdentity, "partyId") != ReadString(startingIdentity, "partyId"))
            throw new AgentHostException("native-session-owner-changed", "The Host stopped because Native game process or player identity changed; it did not retry the prior action.");
    }

    private static string? ReadString(JsonElement value, string name) => value.ValueKind == JsonValueKind.Object && value.TryGetProperty(name, out var prop) && prop.ValueKind == JsonValueKind.String ? prop.GetString() : null;
    private static string? ReadString(JsonObject? value, string name) => value?[name]?.GetValue<string>();
    private static bool ReadBool(JsonObject? value, string name) => value?[name]?.GetValue<bool>() == true;
    private static int ReadInt(JsonElement value, string name, int fallback) => value.ValueKind == JsonValueKind.Object && value.TryGetProperty(name, out var prop) && prop.TryGetInt32(out var parsed) ? parsed : fallback;
    private static int ReadInt(JsonObject? value, string name, int fallback) => value?[name]?.GetValue<int>() ?? fallback;
    private static double ReadDouble(JsonObject value, string name, double fallback) => value[name]?.GetValue<double>() ?? fallback;
    private static double ReadDouble(JsonNode value, double fallback) => double.TryParse(value.ToJsonString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var parsed) ? parsed : fallback;
    private static string? ReadNodeString(JsonNode value) => value is JsonValue jsonValue && jsonValue.TryGetValue<string>(out var result) ? result : null;
    private static bool ReadNodeBool(JsonNode value) => value is JsonValue jsonValue && jsonValue.TryGetValue<bool>(out var result) && result;
    private static int ReadIntEnvironment(string name, int fallback, int min, int max)
    {
        var raw = Environment.GetEnvironmentVariable(name);
        return int.TryParse(raw, NumberStyles.Integer, CultureInfo.InvariantCulture, out var parsed) && parsed >= min && parsed <= max ? parsed : fallback;
    }
}
