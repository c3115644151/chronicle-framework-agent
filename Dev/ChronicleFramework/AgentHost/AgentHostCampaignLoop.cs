using System.Diagnostics;
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal static class AgentHostCampaignLoop
{
    private const int MaxRejectedDecisions = 2;
    private static readonly HashSet<string> CampaignActions = new(StringComparer.Ordinal)
    {
        "mapSettlementTargets", "move"
    };

    internal static IReadOnlyList<object> RunContractSelfTests()
    {
        var results = new List<object>();
        var initialActions = BuildActionCatalog(null, moving: false, goalVerified: false);
        var initialControls = BuildControlCatalog(moving: false, goalVerified: false);
        if (initialActions.Count != 1 || ReadString(initialActions[0] as JsonObject, "action") != "mapSettlementTargets" || initialControls.Count != 0)
            throw new AgentHostException("campaign-loop-self-test-catalog-failed", "The first Host decision must be a read-only map query.");
        results.Add(new { scenario = "campaign-loop-starts-with-read-only-map-observation", passed = true });

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

        var targetActions = BuildActionCatalog(safeTargets, moving: false, goalVerified: false);
        if (targetActions.Count != 2 || ReadString(targetActions[1] as JsonObject, "action") != "move")
            throw new AgentHostException("campaign-loop-self-test-move-catalog-failed", "Movement must be offered only after a safe observed target exists.");
        results.Add(new { scenario = "campaign-loop-move-requires-current-safe-observation", passed = true });

        var movingActions = BuildActionCatalog(safeTargets, moving: true, goalVerified: false);
        var movingControls = BuildControlCatalog(moving: true, goalVerified: false);
        if (movingActions.Count != 0 || movingControls.Count != 1 ||
            !string.Equals(movingControls[0]?.GetValue<string>(), "observeAgain", StringComparison.Ordinal))
            throw new AgentHostException("campaign-loop-self-test-natural-wait-failed", "During movement the Host may only passively re-observe; it must not offer a game clock action.");
        results.Add(new { scenario = "campaign-loop-movement-exposes-only-passive-observation", passed = true });

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

    internal static async Task<IReadOnlyList<object>> RunTransportSelfTestsAsync()
    {
        var requestJson = "{\"runId\":\"selftest-arrival\",\"goal\":\"Reach the observed safe settlement.\",\"parentProcessId\":321,\"maxDecisions\":8,\"maxElapsedSeconds\":10,\"allowedActionNames\":[\"mapSettlementTargets\",\"move\"]}";
        using var request = JsonDocument.Parse(requestJson);
        var results = new List<object>();

        var arrivalClient = new FakeCampaignNativeClient(timeoutOnMove: false);
        var arrivalProvider = new FakeCampaignDecisionProvider(timeoutOnMove: false);
        var arrival = await RunAsync(request.RootElement, arrivalClient, arrivalProvider, CancellationToken.None);
        if (ReadString(arrival, "status") != "completed" ||
            ReadInt(arrival, "decisions", 0) != 4 ||
            ReadInt(arrival, "actionsExecuted", 0) != 2 ||
            arrivalClient.MapQueryCount != 1 || arrivalClient.MoveCount != 1 || arrivalProvider.CallCount != 4 ||
            arrival["termination"] is not JsonObject arrivalTermination || ReadBoolean(arrivalTermination, "goalVerified") != true)
            throw new AgentHostException("campaign-loop-self-test-arrival-runtime-failed", "The injected Native/Provider loop did not observe, move once, passively re-observe, and verify arrival.");
        results.Add(new { scenario = "campaign-loop-runtime-observe-decide-act-observe-arrival", passed = true });

        var timeoutClient = new FakeCampaignNativeClient(timeoutOnMove: true);
        var timeoutProvider = new FakeCampaignDecisionProvider(timeoutOnMove: true);
        var timeout = await RunAsync(request.RootElement, timeoutClient, timeoutProvider, CancellationToken.None);
        if (ReadString(timeout, "status") != "failed" ||
            timeout["termination"] is not JsonObject timeoutTermination || ReadString(timeoutTermination, "reason") != "native-action-result-ambiguous" ||
            ReadInt(timeout, "actionsExecuted", 0) != 1 || timeoutClient.MapQueryCount != 1 || timeoutClient.MoveCount != 1 || timeoutProvider.CallCount != 2 ||
            timeout["trace"] is not JsonArray timeoutTrace || timeoutTrace.OfType<JsonObject>().Count(step => ReadString(step["actionReceipt"] as JsonObject, "status") == "timeout-ambiguous") != 1)
            throw new AgentHostException("campaign-loop-self-test-timeout-replay-failed", "An ambiguous Native move timeout was not surfaced safely or the action was replayed.");
        results.Add(new { scenario = "campaign-loop-runtime-native-timeout-is-not-replayed", passed = true });
        return results;
    }

    internal static async Task<JsonObject> RunAsync(
        JsonElement request,
        string protocolRoot,
        CancellationToken cancellationToken,
        Action<int>? onReady = null)
    {
        var nativeTimeoutSeconds = ReadIntEnvironment("CHRONICLE_LLM_TIMEOUT_SECONDS", 180, 5, 240);
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
        Action<int>? onReady = null)
    {
        var runId = ReadString(request, "runId") ?? Guid.NewGuid().ToString("N");
        var expectedParentProcessId = ReadInt(request, "parentProcessId", 0);
        var goal = ReadString(request, "goal");
        var maxDecisions = ReadInt(request, "maxDecisions", 30);
        var maxElapsedSeconds = ReadInt(request, "maxElapsedSeconds", 600);
        var requestedActions = request.TryGetProperty("allowedActionNames", out var actionNames) && actionNames.ValueKind == JsonValueKind.Array
            ? actionNames.EnumerateArray().Where(item => item.ValueKind == JsonValueKind.String).Select(item => item.GetString()!).ToHashSet(StringComparer.Ordinal)
            : new HashSet<string>(StringComparer.Ordinal);
        if (string.IsNullOrWhiteSpace(goal) || goal.Length > 1000 || maxDecisions is < 1 or > 30 || maxElapsedSeconds is < 1 or > 600 ||
            !requestedActions.SetEquals(CampaignActions))
            throw new AgentHostException("campaign-loop-request-invalid", "The Host requires a bounded Campaign-map goal and the two approved map-query/movement actions.");

        using (provider)
        {
        using var elapsed = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        elapsed.CancelAfter(TimeSpan.FromSeconds(maxElapsedSeconds));

        var trace = new JsonArray();
        var decisionCount = 0;
        var rejectedDecisionCount = 0;
        var prematureCompletionCount = 0;
        var actionsExecuted = 0;
        long promptTokens = 0;
        long completionTokens = 0;
        JsonObject? currentNative = null;
        JsonObject? previousReceipt = null;
        JsonObject? feedback = null;
        JsonArray? visibleTargets = null;
        string? moveTargetId = null;
        string? moveTargetName = null;
        var completedByProvider = false;
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

            for (var iteration = 1; iteration <= maxDecisions; iteration++)
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
                var actionCatalog = BuildActionCatalog(visibleTargets, movingToTarget, targetReached);
                var controls = BuildControlCatalog(movingToTarget, targetReached);
                if (actionCatalog.Count == 0 && controls.Count == 0)
                {
                    failure = "No safe map query, movement action or waiting control is available in the current Native state.";
                    terminationReason = "no-safe-action";
                    break;
                }

                var observation = BuildObservation(before, visibleTargets, moveTargetId, moveTargetName, targetReached);
                var modelRequest = BuildModelRequest(runId, iteration, goal!, observation, previousReceipt, feedback, actionCatalog, controls);
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
                        ["requiredNextStep"] = "Use exactly one action or control from the latest catalog; do not repeat the rejected response."
                    };
                    trace.Add(BuildRejectedDecisionStep(iteration, observation, previousReceipt, actionCatalog, controls, feedback, providerStartedUtc, providerCompletedUtc, providerStartedTicks));
                    continue;
                }

                var providerDoneUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                var decision = providerResult.Decision;
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
                if (nativeAction == "mapSettlementTargets") visibleTargets = BuildSafeVisibleTargets(nativeReceipt);
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
            ["promptTokens"] = promptTokens,
            ["completionTokens"] = completionTokens,
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
        catalog.Add(new JsonObject { ["action"] = "mapSettlementTargets", ["arguments"] = new JsonArray() });
        if (targets is { Count: > 0 }) catalog.Add(new JsonObject { ["action"] = "move", ["arguments"] = new JsonArray(JsonValue.Create("SettlementId")) });
        return catalog;
    }

    private static JsonArray BuildControlCatalog(bool moving, bool goalVerified)
    {
        var controls = new JsonArray();
        if (moving) controls.Add("observeAgain");
        if (goalVerified) controls.Add("done");
        return controls;
    }

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

    private static JsonObject BuildModelRequest(string runId, int iteration, string goal, JsonObject observation, JsonObject? previousReceipt, JsonObject? feedback, JsonArray actions, JsonArray controls) =>
        new()
        {
            ["schemaVersion"] = 1,
            ["runId"] = runId,
            ["iteration"] = iteration,
            ["goal"] = goal,
            ["observation"] = observation.DeepClone(),
            ["previousActionReceipt"] = previousReceipt?.DeepClone(),
            ["decisionFeedback"] = feedback?.DeepClone(),
            ["allowedActions"] = actions.DeepClone(),
            ["allowedControls"] = controls.DeepClone()
        };

    private static JsonArray BuildSafeVisibleTargets(JsonObject receipt)
    {
        if (ReadString(receipt, "status") != "completed" || receipt["data"] is not JsonObject data || data["mapSettlementTargets"] is not JsonArray targets)
            return new JsonArray();
        var candidates = targets.OfType<JsonObject>()
            .Where(target => HasExplicitBoolean(target, "hostile", expected: false) && HasExplicitBoolean(target, "underSiege", expected: false) &&
                             ReadDouble(target, "distance", double.MaxValue) > 1.0 &&
                             !string.IsNullOrWhiteSpace(ReadString(target, "id")) && !string.IsNullOrWhiteSpace(ReadString(target, "name")))
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
        "provider-response-invalid-json" or "provider-decision-invalid-json" or "provider-decision-ambiguous" or
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

    private sealed class FakeCampaignNativeClient(bool timeoutOnMove) : IAgentHostCampaignNativeClient
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

    private sealed class FakeCampaignDecisionProvider(bool timeoutOnMove) : IAgentHostDecisionProvider
    {
        internal int CallCount { get; private set; }
        public string ModelId => "deterministic-campaign-loop-self-test";
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
            var decision = CallCount switch
            {
                1 => new JsonObject { ["action"] = "mapSettlementTargets", ["arguments"] = new JsonObject(), ["rationale"] = "Read current safe destinations." },
                2 => new JsonObject { ["action"] = "move", ["arguments"] = new JsonObject { ["SettlementId"] = "safe" }, ["rationale"] = "Move to the observed safe destination." },
                3 when !timeoutOnMove => new JsonObject { ["observeAgain"] = true, ["waitSeconds"] = 1, ["reason"] = "Observe natural movement." },
                4 when !timeoutOnMove => new JsonObject { ["done"] = true, ["reason"] = "Fresh Native state confirms arrival." },
                _ => throw new AgentHostException("campaign-loop-self-test-provider-sequence-invalid", "The runtime test requested more decisions than its scripted sequence.")
            };
            return Task.FromResult(new ProviderDecisionResult("completed", ModelId, null, null, "stop", decision));
        }

        public void Dispose() { }
    }

    private sealed record CampaignTarget(string Id, string Name, string Type);
}
