using System.Diagnostics;
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal static class AgentHostEstablishClanGoldSaleLoop
{
    private const string QuestId = "rebuild_player_clan_storymode_quest";

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
            ["context"] = new JsonObject { ["gameState"] = "InventoryState", ["menuId"] = null, ["captivity"] = null },
            ["inventoryScreen"] = new JsonObject { ["mode"] = "Trade", ["hasPendingChanges"] = false }
        };
        var saleCatalog = BuildActionCatalog(tradeState, tradeOptions, null, null);
        var saleItemIds = saleCatalog[0]?["argumentValues"]?["ItemViewModelId"] as JsonArray;
        var saleAmountValues = saleCatalog[0]?["argumentValues"]?["Amount"] as JsonArray;
        if (saleCatalog.Count != 1 || ReadString(saleCatalog[0] as JsonObject, "action") != "trade" ||
            saleItemIds?.Count != 1 || saleItemIds[0]?.GetValue<string>() != "goods-1" ||
            saleAmountValues?.Count != 1 || saleAmountValues[0]?.GetValue<int>() != 1 ||
            saleCatalog[0]?["arguments"]?[1]?.GetValue<string>() != "ItemViewModelId")
            throw new AgentHostException("gold-sale-self-test-current-sell-offer-scope-failed", "The sale catalog must expose exactly one current transferable Goods offer at the quoted positive price and limit the slice to one unit.");

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
        var moveStarting = MapState(null, null, []);
        moveStarting["location"]!["targetSettlementId"] = "safe-town";
        moveStarting["context"]!["timeControlMode"] = "StoppablePlay";
        moveStarting["context"]!["isWaiting"] = true;
        if (!BuildControlCatalog(moveStarting, "safe-town", moveStartPending: true).Any(control => control?.GetValue<string>() == "observeAgain") ||
            BuildControlCatalog(moveStarting, "safe-town", moveStartPending: false).Count != 0)
            throw new AgentHostException("gold-sale-self-test-native-move-start-transition-poll-failed", "After its own Native move sets the target but before isMoving updates, allow one bounded read-only poll and no replayed movement or clock action.");
        var existingMove = MapState(null, null, []);
        existingMove["party"]!["isMoving"] = true;
        existingMove["location"]!["targetSettlementId"] = "user-existing-target";
        if (BuildActionCatalog(existingMove, null, null, null).Count != 0)
            throw new AgentHostException("gold-sale-self-test-existing-move-overwritten", "The Gold sale loop must not replace a Native movement order it did not issue.");
        var disabledTradeMenu = MapState("town", "sargot", new JsonArray(new JsonObject { ["id"] = "trade", ["available"] = true, ["enabled"] = false }));
        if (BuildActionCatalog(disabledTradeMenu, null, null, null).Count != 0)
            throw new AgentHostException("gold-sale-self-test-disabled-trade-menu-leaked", "A disabled Native Trade menu entry must not become an agent action.");

        return [
            new { scenario = "gold-sale-offers-only-current-enabled-town-trade-entry", passed = true },
            new { scenario = "gold-sale-binds-one-current-native-goods-offer-and-positive-quote", passed = true },
            new { scenario = "gold-sale-native-move-start-transition-uses-one-bounded-observation", passed = true },
            new { scenario = "gold-sale-rejects-stale-offers-unsafe-targets-and-disabled-native-options", passed = true }
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
        if (ReadString(result, "status") != "failed" || ReadString(result, "failureCode") != "provider-http-error" ||
            ReadInt(result, "actionsExecuted", 0) != 1 || trace?.Count != 2 || ReadString(firstAction, "action") != "mapSettlementTargets" ||
            ReadString(failedRoute, "failureCode") != "provider-http-error" || client.MapTargetQueries != 1 ||
            provider.CallCount != 3 || !provider.FeedbackObserved || !rejectedDecisionRecorded)
            throw new AgentHostException("gold-sale-failure-receipt-selftest-failed", "One malformed provider decision must be corrected before Native action; a later provider outage must still preserve the query trace and must not replay it.");
        return [new { scenario = "gold-sale-recovers-malformed-provider-arguments-and-preserves-later-provider-failure-evidence", passed = true }];
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
        var maxDecisions = Math.Clamp(ReadInt(request, "maxDecisions", 48), 1, 160);
        var maxElapsedSeconds = Math.Clamp(ReadInt(request, "maxElapsedSeconds", 1800), 10, 7200);
        using var elapsed = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        elapsed.CancelAfter(TimeSpan.FromSeconds(maxElapsedSeconds));
        var trace = priorTrace?.DeepClone() as JsonArray ?? new JsonArray();
        var routeHistory = priorProviderRouteHistory?.DeepClone() as JsonArray ?? new JsonArray();
        var decisionCount = priorDecisions;
        var actionCount = 0;
        var saleActionCount = 0;
        long promptTokens = priorPromptTokens;
        long completionTokens = priorCompletionTokens;
        string? moveTargetId = null;
        var moveStartPending = false;
        var rejectedProviderDecisions = 0;
        JsonArray? safeTowns = null;
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
        using (provider)
        {
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

            for (var iteration = 1; decisionCount - priorDecisions < maxDecisions; iteration++)
            {
                elapsed.Token.ThrowIfCancellationRequested();
                var state = currentNative["state"] as JsonObject ?? throw new AgentHostException("gold-sale-state-missing", "Native returned no Campaign state.");
                if (IsActiveEncounter(state) || ReadBoolean((state["context"] as JsonObject)?["captivity"] as JsonObject, "isCaptive"))
                    throw new AgentHostException("gold-sale-encounter-out-of-scope", "A new encounter or Captivity interrupted the sale path; no battle or unverified recovery was started.");

                var actionCatalog = BuildActionCatalog(state, previousReceipt, safeTowns, moveTargetId);
                var controls = BuildControlCatalog(state, moveTargetId, moveStartPending);
                if (actionCatalog.Count == 0 && controls.Count == 0)
                    throw new AgentHostException("gold-sale-no-safe-native-action", DescribeNoAction(state, previousReceipt));

                var observation = BuildObservation(currentNative, state, objectiveSnapshotBefore, liveMetricDifferencesBefore, saleReceipt);
                var modelRequest = BuildDecisionRequest(runId, ReadString(request, "goal"), iteration + decisionCount,
                    observation, previousReceipt, decisionFeedback, actionCatalog, controls);
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
                    if (seconds is < 1 or > 10) throw new AgentHostException("gold-sale-observe-interval-invalid", "observeAgain must request a bounded 1-10 second Host poll.");
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

                if (action == "mapSettlementTargets") safeTowns = FilterSafeTowns(receipt);
                if (action == "move")
                {
                    moveTargetId = ReadString(arguments, "SettlementId");
                    moveStartPending = moveTargetId is not null;
                }
                if (action == "trade")
                {
                    var data = receipt["data"] as JsonObject ?? new JsonObject();
                    if (ReadBoolean(data, "nativeCanCompleteTransaction") != true ||
                        ReadString(data, "direction") != "sell" || ReadInt(data, "amount", 0) != 1 ||
                        ReadString(data, "inventorySide") != "PlayerInventory")
                        throw new AgentHostException("gold-sale-native-draft-invalid", "The Native Trade handler did not produce the expected one-unit sell draft.");
                }
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

                previousReceipt = BuildReceipt(action!, arguments!, receipt);
                using (var fresh = await stateClient.ReadStateAsync(elapsed.Token)) currentNative = ParseObject(fresh.RootElement);
                trace.Add(BuildStep(decisionCount, observation, modelDecision.Decision, previousReceipt, started, startedTicks, null,
                    BuildObservation(currentNative, currentNative["state"] as JsonObject ?? new JsonObject(), objectiveSnapshotBefore, liveMetricDifferencesBefore, saleReceipt)));

                if (action == "tradeCancel")
                    throw new AgentHostException("gold-sale-no-transferable-goods", "The current Native Town has no allowed transferable Goods sell offer; the unmodified Trade screen was closed and the Gold goal remains unmet.");

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

    private static JsonArray BuildActionCatalog(JsonObject state, JsonObject? previousReceipt, JsonArray? safeTowns, string? moveTargetId)
    {
        var context = state["context"] as JsonObject;
        var gameState = ReadString(context, "gameState");
        if (ReadBoolean(context?["captivity"] as JsonObject, "isCaptive") || IsActiveEncounter(state) ||
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
        if (gameState != "MapState") return new JsonArray();
        if (moveTargetId is not null && !string.Equals(ReadString(state["location"] as JsonObject, "currentSettlementId"), moveTargetId, StringComparison.Ordinal))
            return new JsonArray();
        if (moveTargetId is null && (ReadBoolean(state["party"] as JsonObject, "isMoving") ||
            !string.IsNullOrWhiteSpace(ReadString(state["location"] as JsonObject, "targetSettlementId")))) return new JsonArray();
        var menuId = ReadString(context, "menuId");
        if (!string.IsNullOrWhiteSpace(menuId))
        {
            if (menuId != "town") return new JsonArray();
            var tradeOptions = GetEnabledOptions(state).OfType<JsonObject>().Where(option => ReadString(option, "id") == "trade").ToArray();
            if (tradeOptions.Length == 0) return new JsonArray();
            return new JsonArray(new JsonObject
            {
                ["action"] = "menuSelect", ["arguments"] = new JsonArray("MenuId", "OptionId"),
                ["argumentValues"] = new JsonObject { ["MenuId"] = new JsonArray("town"), ["OptionId"] = new JsonArray("trade") }
            });
        }
        var location = state["location"] as JsonObject;
        var currentSettlementId = ReadString(location, "currentSettlementId");
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
            if (menuId != ReadString(state["context"] as JsonObject, "menuId") || menuId != "town" || optionId != "trade" ||
                !GetEnabledOptions(state).OfType<JsonObject>().Any(option => ReadString(option, "id") == optionId))
            {
                rejection = "Only the current enabled Trade entry in the Native Town menu can be selected.";
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

    private static JsonArray FilterSafeTowns(JsonObject receipt)
    {
        if (ReadString(receipt, "status") != "completed" || receipt["data"]?["mapSettlementTargets"] is not JsonArray targets) return new JsonArray();
        var candidates = targets.OfType<JsonObject>()
            .Where(target => ReadString(target, "type") == "town" && !ReadBoolean(target, "hostile") && !ReadBoolean(target, "underSiege") &&
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
        JsonObject? previousReceipt, JsonObject? feedback, JsonArray actionCatalog, JsonArray controls) => new()
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
            !ReadBoolean(context, "encounterActive") && context?["battleSimulation"] is null &&
            !ReadBoolean(context, "escapeMenuOpen") && !ReadBoolean(context, "inquiryOpen") &&
            state["inventoryScreen"] is null && state["partyScreen"] is null;
    }

    private static bool IsActiveEncounter(JsonObject state)
    {
        var context = state["context"] as JsonObject;
        return ReadBoolean(context, "encounterActive") || context?["battleSimulation"] is not null ||
            !string.IsNullOrWhiteSpace(ReadString(context, "encounteredPartyId")) || ReadString(context, "menuId") == "encounter";
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
            var targets = new JsonArray(new JsonObject { ["id"] = "town-safe", ["name"] = "Safe Town", ["type"] = "town", ["distance"] = 10.0, ["hostile"] = false, ["underSiege"] = false });
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
        public string ModelId => "deterministic-gold-sale-failure-selftest";
        public string ConfigurationSource => "harness-fake-provider";
        public Task CheckConfiguredModelAsync(CancellationToken cancellationToken) { cancellationToken.ThrowIfCancellationRequested(); return Task.CompletedTask; }
        public Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            CallCount++;
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
        public void Dispose() { }
    }
}
