using System.Diagnostics;
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

/// <summary>
/// One bounded Native town-market purchase. This profile is deliberately independent of the
/// sell-only Gold slice: it buys one currently quoted OtherInventory Goods stack and verifies
/// the exact Gold inverse and item-count deltas before claiming completion.
/// </summary>
internal static class AgentHostTownTradeLoop
{
    private const int MinimumActiveMapTravelObserveSeconds = 5;
    private const int MaxPurchaseUnitsDefault = 20;
    private const int MaxPurchaseUnitsCeiling = 100;

    internal static async Task<JsonObject> RunAsync(
        JsonElement request,
        IAgentHostCampaignNativeClient stateClient,
        IAgentHostTownTradeNativeClient actionClient,
        IAgentHostDecisionProvider provider,
        DecisionRunLedger ledger,
        CancellationToken cancellationToken)
    {
        var runId = ReadString(request, "runId") ?? Guid.NewGuid().ToString("N");
        var maxDecisions = Math.Clamp(ReadInt(request, "maxDecisions", AgentHostCampaignLoop.MaxCumulativeDecisions), 1, AgentHostCampaignLoop.MaxCumulativeDecisions);
        var maxElapsedSeconds = Math.Clamp(ReadInt(request, "maxElapsedSeconds", 1800), 10, 86400);
        var maxPurchaseUnits = Math.Clamp(ReadInt(request, "maxPurchaseUnits", MaxPurchaseUnitsDefault), 1, MaxPurchaseUnitsCeiling);
        using var elapsed = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        elapsed.CancelAfter(TimeSpan.FromSeconds(maxElapsedSeconds));

        var actionCount = 0;
        var buyActionCount = 0;
        string? moveTargetId = null;
        var moveStartPending = false;
        var rejectedProviderDecisions = 0;
        JsonArray? safeTowns = null;
        var visitedTowns = new HashSet<string>(StringComparer.Ordinal);
        var allowMapAfterNativeTownLeave = false;
        JsonObject? previousReceipt = null;
        JsonObject? decisionFeedback = null;
        JsonObject? buyReceipt = null;
        JsonObject? initialNative = null;
        JsonObject? currentNative = null;
        var campaignDayBefore = double.NaN;
        string? timeControlModeBefore = null;

        try
        {
            // The Campaign Host owns the shared decision provider; this bounded objective borrows it.
            await provider.CheckConfiguredModelAsync(elapsed.Token);
            using (var initial = await stateClient.ReadStateAsync(elapsed.Token)) initialNative = ParseObject(initial.RootElement);
            currentNative = initialNative.DeepClone() as JsonObject ?? throw new AgentHostException("town-trade-initial-state-invalid", "Native returned no initial Campaign state.");
            campaignDayBefore = ReadDouble(currentNative, "campaignDay", double.NaN);
            timeControlModeBefore = ReadString(currentNative, "timeControlMode");

            var initialState = currentNative["state"] as JsonObject ?? new JsonObject();
            if (ReadBoolean((initialState["context"] as JsonObject)?["captivity"] as JsonObject, "isCaptive") ||
                IsActiveEncounter(initialState))
                throw new AgentHostException("town-trade-encounter-out-of-scope", "The town-trade buy profile requires a free Campaign Map; an encounter or captivity was present before any model decision.");
            if (!IsSupportedStartingState(initialState))
                throw new AgentHostException("town-trade-free-map-or-native-trade-required", "The town-trade buy profile starts on a free Campaign Map or in the current settlement's Native Trade screen.");

            moveTargetId = ReadExistingNativeSettlementMoveTarget(currentNative);
            if (moveTargetId is not null)
            {
                ledger.Trace.Add(new JsonObject
                {
                    ["stage"] = "town-trade-adopted-existing-native-settlement-move",
                    ["targetSettlementId"] = moveTargetId,
                    ["timeControlMode"] = ReadString(currentNative, "timeControlMode"),
                    ["partyIsMoving"] = true,
                    ["nativeMoveActionReplayed"] = false,
                    ["modelDecisionRequiredToWait"] = false
                });
            }

            for (var iteration = 1; ledger.Decisions < maxDecisions; iteration++)
            {
                elapsed.Token.ThrowIfCancellationRequested();
                var state = currentNative["state"] as JsonObject ?? throw new AgentHostException("town-trade-state-missing", "Native returned no Campaign state.");

                if (ReadBoolean((state["context"] as JsonObject), "inquiryOpen"))
                    throw new AgentHostException("town-trade-inquiry-out-of-scope", "The bounded buy profile does not resolve Native inquiries or capacity warnings; no unverified confirmation was sent.");
                if (IsActiveEncounter(state) || ReadBoolean((state["context"] as JsonObject)?["captivity"] as JsonObject, "isCaptive"))
                    throw new AgentHostException("town-trade-encounter-out-of-scope", "A new encounter or Captivity interrupted the bounded Native buy path; no battle or recovery was started.");

                if (IsInterruptedMapMove(state, moveTargetId, moveStartPending))
                {
                    moveTargetId = null;
                    safeTowns = null;
                }

                if (HasReachedMoveTargetMenu(state, moveTargetId))
                {
                    moveTargetId = null;
                    moveStartPending = false;
                }

                if (moveTargetId is not null &&
                    ReadString(state["location"] as JsonObject, "targetSettlementId") == moveTargetId &&
                    ReadString(state["location"] as JsonObject, "currentSettlementId") != moveTargetId &&
                    ReadString(state["location"] as JsonObject, "targetPartyId") is null &&
                    ReadBoolean(state["party"] as JsonObject, "isMoving") && !IsMapConversationActive(state))
                {
                    if (AgentHostNativeMapMovementMonitor.IsStalledNativeSettlementMove(currentNative, moveTargetId))
                    {
                        ledger.Trace.Add(new JsonObject
                        {
                            ["stage"] = "town-trade-stopped-native-move-handoff",
                            ["targetSettlementId"] = moveTargetId,
                            ["timeControlMode"] = ReadString(currentNative, "timeControlMode"),
                            ["nativeActionSent"] = false,
                            ["explicitClockAction"] = false
                        });
                        return BuildFailure("town-trade-paused-native-move-handoff",
                            "A selected Native settlement move remains active while Campaign time is Stop; return it to the parent without an implicit clock action.");
                    }

                    if (AgentHostNativeMapMovementMonitor.IsCampaignTimeAdvancing(currentNative))
                    {
                        const int passiveMoveWatchSeconds = AgentHostNativeMapMovementMonitor.MaximumWatchWindowSeconds;
                        var movementWatch = await AgentHostNativeMapMovementMonitor.WaitAsync(
                            stateClient,
                            stateClient as IAgentHostBattleSimulationNativeClient,
                            currentNative,
                            moveTargetId,
                            passiveMoveWatchSeconds,
                            monitorVisibleBandits: false,
                            elapsed.Token);
                        currentNative = movementWatch.NativeReceipt;
                        actionCount += movementWatch.MapPartyTargetPollCount + (movementWatch.PauseReceipt is null ? 0 : 1);
                        ledger.Trace.Add(new JsonObject
                        {
                            ["stage"] = "town-trade-passively-observed-existing-native-move",
                            ["targetSettlementId"] = moveTargetId,
                            ["waitSeconds"] = passiveMoveWatchSeconds,
                            ["nativeMapPartyTargetPollCount"] = movementWatch.MapPartyTargetPollCount,
                            ["interruptedByVisibleHostileBandit"] = movementWatch.InterruptedByVisibleHostileBandit,
                            ["nativePauseReceipt"] = movementWatch.PauseReceipt?.DeepClone(),
                            ["providerDecisionDuringWait"] = false,
                            ["explicitClockAction"] = false
                        });
                        if (movementWatch.InterruptedByVisibleHostileBandit)
                            return BuildFailure(AgentHostNativeMapMovementMonitor.FailureCode,
                                "A visible hostile Bandit interrupted the bounded market route; the parent must resolve the current encounter before replanning.");
                        continue;
                    }
                }

                var actionCatalog = BuildActionCatalog(state, previousReceipt, safeTowns, moveTargetId, maxPurchaseUnits, allowMapAfterNativeTownLeave);
                var controls = BuildControlCatalog(state, moveTargetId, moveStartPending);
                if (actionCatalog.Count == 0 && controls.Count == 0)
                {
                    var (code, message) = DescribeNoAction(state, previousReceipt, visitedTowns, safeTowns);
                    throw new AgentHostException(code, message);
                }

                var observation = BuildObservation(currentNative, state, buyReceipt);
                var providerPreviousReceipt = BuildProviderPreviousReceipt(previousReceipt, safeTowns);
                var modelRequest = BuildDecisionRequest(runId, ReadString(request, "goal"), iteration + ledger.Decisions,
                    observation, providerPreviousReceipt, decisionFeedback, actionCatalog, controls, moveStartPending);
                var started = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                var startedTicks = Stopwatch.GetTimestamp();
                ProviderDecisionResult modelDecision;
                try
                {
                    modelDecision = await AgentHostDecisionCycle.DecideTownTradeAsync(provider, modelRequest, elapsed.Token);
                }
                catch (AgentHostException exception) when (AgentHostProviderDecisionRecovery.CanRetry(exception.Code, rejectedProviderDecisions))
                {
                    ledger.RecordUnsentDecision();
                    rejectedProviderDecisions++;
                    decisionFeedback = AgentHostProviderDecisionRecovery.BuildFeedback(exception.Code, actionCatalog, controls);
                    ledger.Trace.Add(new JsonObject
                    {
                        ["iteration"] = ledger.Decisions,
                        ["stage"] = "decision-rejected-before-native",
                        ["rejectionCode"] = exception.Code,
                        ["nativeActionSent"] = false,
                        ["allowedActionNames"] = AgentHostProviderDecisionRecovery.CurrentActionNames(actionCatalog),
                        ["allowedControls"] = controls.DeepClone(),
                        ["feedback"] = decisionFeedback.DeepClone()
                    });
                    continue;
                }
                ledger.RecordDecision(modelDecision);
                rejectedProviderDecisions = 0;
                decisionFeedback = null;

                if (ReadBoolean(modelDecision.Decision, "observeAgain"))
                {
                    if (!controls.Any(control => control?.GetValue<string>() == "observeAgain"))
                        throw new AgentHostException("town-trade-observe-not-allowed", "The Host may wait only while Native confirms movement or arrival pending.");
                    var seconds = ReadInt(modelDecision.Decision, "waitSeconds", 0);
                    var minimumWait = GetMinimumObserveInterval(moveStartPending);
                    if (!IsSupportedObserveInterval(seconds, moveStartPending))
                        throw new AgentHostException("town-trade-observe-interval-invalid", $"observeAgain requires a {minimumWait}-10 second read-only Host poll in the current Native map-movement state.");
                    var movementWatch = await AgentHostNativeMapMovementMonitor.WaitAsync(
                        stateClient,
                        stateClient as IAgentHostBattleSimulationNativeClient,
                        currentNative,
                        moveTargetId,
                        seconds,
                        monitorVisibleBandits: false,
                        elapsed.Token);
                    currentNative = movementWatch.NativeReceipt;
                    actionCount += movementWatch.MapPartyTargetPollCount + (movementWatch.PauseReceipt is null ? 0 : 1);
                    if (moveStartPending) moveStartPending = false;
                    ledger.Trace.Add(BuildStep(ledger.Decisions, observation, modelDecision.Decision, null, started, startedTicks,
                        new JsonObject
                        {
                            ["kind"] = movementWatch.InterruptedByVisibleHostileBandit ? AgentHostNativeMapMovementMonitor.FailureCode : "bounded-host-observation",
                            ["waitSeconds"] = seconds,
                            ["nativeMapPartyTargetPollCount"] = movementWatch.MapPartyTargetPollCount,
                            ["visibleHostileBanditTargets"] = movementWatch.VisibleHostileBanditTargets.DeepClone(),
                            ["nativePauseReceipt"] = movementWatch.PauseReceipt?.DeepClone()
                        },
                        BuildObservation(currentNative, currentNative["state"] as JsonObject ?? new JsonObject(), buyReceipt)));
                    if (movementWatch.InterruptedByVisibleHostileBandit)
                        return BuildFailure(AgentHostNativeMapMovementMonitor.FailureCode,
                            "A visible hostile Bandit interrupted movement toward a market Town; the parent must resolve the current encounter before replanning.");
                    continue;
                }

                if (!TryResolveAction(state, previousReceipt, actionCatalog, modelDecision.Decision, safeTowns,
                        maxPurchaseUnits, out var action, out var arguments, out var rejection))
                    throw new AgentHostException("town-trade-model-action-invalid", rejection ?? "The model did not choose a current allowed Native buy action.");

                using var actionResponse = await actionClient.ExecuteTownTradeActionAsync(action!, arguments!, elapsed.Token);
                var receipt = ParseObject(actionResponse.RootElement);
                actionCount++;
                if (action == "tradeConfirm" && ReadString(receipt, "status") == "accepted")
                    throw new AgentHostException("town-trade-confirm-accepted-unsupported",
                        "Native returned accepted instead of completed for tradeConfirm; this buy profile does not resolve inquiries or treat an accepted receipt as a committed purchase.");
                if (ReadString(receipt, "status") != "completed")
                    throw new AgentHostException("town-trade-native-action-rejected", $"Native rejected the current {action} action; no replay was attempted.");

                if (action == "mapSettlementTargets") safeTowns = FilterSafeTowns(receipt, visitedTowns);
                if (action == "move")
                {
                    moveTargetId = ReadMoveTargetId(arguments);
                    moveStartPending = moveTargetId is not null;
                    allowMapAfterNativeTownLeave = false;
                }
                if (action == "menuSelect")
                {
                    var exitedSettlementId = ReadString(state["location"] as JsonObject, "currentSettlementId");
                    if (ReadString(arguments, "optionId") is string optionId && IsLeaveOption(state, optionId))
                    {
                        if (!string.IsNullOrWhiteSpace(exitedSettlementId)) visitedTowns.Add(exitedSettlementId);
                        moveTargetId = null;
                        moveStartPending = false;
                        safeTowns = null;
                        allowMapAfterNativeTownLeave = true;
                    }
                }
                if (action == "trade")
                {
                    var data = receipt["data"] as JsonObject ?? new JsonObject();
                    if (ReadBoolean(data, "nativeCanCompleteTransaction") != true ||
                        ReadString(data, "direction") is not string direction || direction == "sell" || direction != "buy" ||
                        ReadInt(data, "amount", 0) < 1 ||
                        ReadString(data, "inventorySide") is not string inventorySide || inventorySide == "PlayerInventory" || inventorySide != "OtherInventory")
                        throw new AgentHostException("town-trade-native-draft-invalid", "The Native Trade handler did not produce a completable positive OtherInventory buy draft.");
                }
                if (action == "tradeCancelChanges")
                {
                    var data = receipt["data"] as JsonObject ?? new JsonObject();
                    if (ReadBoolean(data, "discardConfirmed") != true || ReadBoolean(data, "returnedToMap") != true ||
                        ReadBoolean(data, "tradeStateStillActive"))
                        throw new AgentHostException("town-trade-draft-discard-unverified", "Native did not confirm that the invalid buy draft was discarded without committing a purchase.");
                }
                if (action == "tradeConfirm")
                {
                    var data = receipt["data"] as JsonObject ?? new JsonObject();
                    if (!VerifyBuyReceipt(data, ReadInt(arguments, "amount", 0)))
                        throw new AgentHostException("town-trade-native-commit-unverified", "Native Trade did not confirm one buy with exact Gold inverse, OtherInventory and market count changes and unchanged Campaign time.");
                    buyReceipt = data.DeepClone() as JsonObject;
                    buyActionCount++;
                }

                previousReceipt = BuildReceipt(action!, arguments!, receipt);
                using (var fresh = await stateClient.ReadStateAsync(elapsed.Token)) currentNative = ParseObject(fresh.RootElement);
                ledger.Trace.Add(BuildStep(ledger.Decisions, observation, modelDecision.Decision, previousReceipt, started, startedTicks, null,
                    BuildObservation(currentNative, currentNative["state"] as JsonObject ?? new JsonObject(), buyReceipt)));

                if (buyReceipt is not null)
                {
                    var finalState = currentNative["state"] as JsonObject ?? new JsonObject();
                    if (ReadBoolean((finalState["context"] as JsonObject)?["captivity"] as JsonObject, "isCaptive") ||
                        IsActiveEncounter(finalState) || ReadBoolean(finalState["context"] as JsonObject, "inquiryOpen"))
                        throw new AgentHostException("town-trade-final-state-invalid", "After the confirmed Native buy, the final state was not a usable free Campaign Map.");
                    return BuildSuccess(runId, provider, initialNative, currentNative, buyReceipt, previousReceipt, ledger,
                        actionCount, buyActionCount, campaignDayBefore, timeControlModeBefore, maxPurchaseUnits);
                }
            }

            if (CanSafelyCancelUntouchedNativeTrade(currentNative, buyActionCount, previousReceipt))
            {
                var beforeState = currentNative?["state"] as JsonObject ?? new JsonObject();
                var beforeEconomy = beforeState["economy"] as JsonObject;
                var goldBeforeBudgetExit = ReadInt(beforeEconomy, "gold", -1);
                var campaignDayBeforeBudgetExit = ReadDouble(currentNative, "campaignDay", double.NaN);
                var timeModeBeforeBudgetExit = ReadString(currentNative, "timeControlMode");
                using var cancelResponse = await actionClient.ExecuteTownTradeActionAsync("tradeCancel", new JsonObject(), elapsed.Token);
                var cancelReceipt = ParseObject(cancelResponse.RootElement);
                var cancelData = cancelReceipt["data"] as JsonObject;
                if (ReadString(cancelReceipt, "status") != "completed" || ReadBoolean(cancelData, "cancelRequested") != true ||
                    ReadBoolean(cancelData, "discardConfirmed") || ReadBoolean(cancelData, "returnedToMap") != true ||
                    ReadBoolean(cancelData, "tradeStateStillActive"))
                    throw new AgentHostException("town-trade-budget-safe-cancel-unverified", "Native did not confirm leaving the unchanged Trade screen through its original Cancel handler.");

                actionCount++;
                previousReceipt = BuildReceipt("tradeCancel", new JsonObject(), cancelReceipt);
                using (var fresh = await stateClient.ReadStateAsync(elapsed.Token)) currentNative = ParseObject(fresh.RootElement);
                var returnedState = currentNative["state"] as JsonObject ?? new JsonObject();
                var goldAfterBudgetExit = ReadInt(returnedState["economy"] as JsonObject, "gold", -1);
                if (!IsFreeCampaignMap(returnedState) || goldBeforeBudgetExit < 0 || goldAfterBudgetExit != goldBeforeBudgetExit ||
                    !double.IsFinite(campaignDayBeforeBudgetExit) || !double.IsFinite(ReadDouble(currentNative, "campaignDay", double.NaN)) ||
                    Math.Abs(campaignDayBeforeBudgetExit - ReadDouble(currentNative, "campaignDay", double.NaN)) > 0.000001 ||
                    timeModeBeforeBudgetExit != ReadString(currentNative, "timeControlMode"))
                    throw new AgentHostException("town-trade-budget-safe-cancel-postcondition-failed", "Native Cancel did not return to the free Campaign Map with unchanged Gold and Campaign time.");

                ledger.Trace.Add(new JsonObject
                {
                    ["stage"] = "native-trade-decision-budget-exhausted-cancelled-unchanged-screen",
                    ["nativeAction"] = "tradeCancel",
                    ["nativeActionStatus"] = "completed",
                    ["nativeMapReturned"] = true,
                    ["goldUnchanged"] = true,
                    ["campaignDayUnchanged"] = true,
                    ["timeControlModeUnchanged"] = true,
                    ["buyActionCount"] = buyActionCount,
                    ["modelDecisionCount"] = ledger.Decisions
                });
                return BuildFailure("town-trade-budget-exhausted-safe-map-recovered",
                    "The decision limit was reached in an unchanged Native Trade screen; original Native Cancel restored the free Map without a purchase or time change.");
            }

            throw new AgentHostException("town-trade-budget-exhausted", "The bounded Native town buy loop did not complete one verified purchase.");
        }
        catch (OperationCanceledException)
        {
            return BuildFailure(cancellationToken.IsCancellationRequested ? "host-stop-requested" : "town-trade-timeout",
                cancellationToken.IsCancellationRequested ? "The Host stop signal ended the buy objective without claiming a purchase." : "The bounded buy objective exceeded its elapsed-time limit.");
        }
        catch (AgentHostException exception)
        {
            return BuildFailure(exception.Code, exception.Message);
        }
        catch (Exception exception)
        {
            return BuildFailure("town-trade-unexpected-error", exception.GetType().Name);
        }

        JsonObject BuildFailure(string code, string message)
        {
            ledger.Routes.Add(new JsonObject
            {
                ["decision"] = ledger.NextDecisionNumber,
                ["requestedModelId"] = provider.ModelId,
                ["status"] = "failed-before-valid-decision",
                ["failureCode"] = code,
                ["failureSummary"] = message.Length > 240 ? message[..240] : message
            });
            return new JsonObject
            {
                ["status"] = "failed",
                ["resultKind"] = "town-trade-buy",
                ["runId"] = runId,
                ["providerModelId"] = provider.ModelId,
                ["providerConfigurationSource"] = provider.ConfigurationSource,
                ["decisions"] = ledger.Decisions,
                ["actionsExecuted"] = actionCount,
                ["buyActionsExecuted"] = buyActionCount,
                ["promptTokens"] = ledger.PromptTokens,
                ["completionTokens"] = ledger.CompletionTokens,
                ["providerRouteHistory"] = ledger.Routes.DeepClone(),
                ["initialNativeState"] = initialNative?.DeepClone(),
                ["finalNativeState"] = currentNative?.DeepClone(),
                ["buyReceipt"] = buyReceipt?.DeepClone(),
                ["trace"] = ledger.Trace.DeepClone(),
                ["termination"] = new JsonObject { ["reason"] = code, ["completedByProvider"] = false, ["goalVerified"] = false },
                ["failure"] = message,
                ["failureCode"] = code
            };
        }
    }

    private static JsonArray BuildActionCatalog(
        JsonObject state,
        JsonObject? previousReceipt,
        JsonArray? safeMarkets,
        string? moveTargetId,
        int maxPurchaseUnits,
        bool allowMapAfterNativeTownLeave = false)
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
                var offers = GetBuyableGoods(previousReceipt);
                if (offers.Length == 0) return new JsonArray(new JsonObject { ["action"] = "tradeCancel", ["arguments"] = new JsonArray() });
                var itemIds = new JsonArray(offers.Select(offer => (JsonNode?)JsonValue.Create(ReadString(offer, "viewModelItemId"))).ToArray());
                var amounts = BuildAmountCandidates(offers, ReadInt(state["economy"] as JsonObject, "gold", -1), maxPurchaseUnits);
                if (amounts.Count == 0) return new JsonArray();
                return new JsonArray(new JsonObject
                {
                    ["action"] = "trade",
                    ["arguments"] = new JsonArray("Direction", "ItemViewModelId", "InventorySide", "Amount"),
                    ["argumentValues"] = new JsonObject
                    {
                        ["Direction"] = new JsonArray("buy"),
                        ["ItemViewModelId"] = itemIds,
                        ["InventorySide"] = new JsonArray("OtherInventory"),
                        ["Amount"] = amounts
                    }
                });
            }
            if (previousAction == "tradeCancel" && ReadString(previousReceipt, "status") == "completed" &&
                (ReadBoolean(previousReceipt?["data"] as JsonObject, "returnedToMap") ||
                 ReadBoolean(previousReceipt?["data"] as JsonObject, "tradeStateStillActive") == false))
                return new JsonArray();
            if (ReadBoolean(inventory, "hasPendingChanges")) return new JsonArray();
            return new JsonArray(new JsonObject { ["action"] = "tradeOptions", ["arguments"] = new JsonArray() });
        }

        if (gameState != "MapState") return new JsonArray();
        if (IsMapConversationActive(state)) return BuildMapConversationActionCatalog(state);
        if (moveTargetId is not null &&
            !string.Equals(ReadString(state["location"] as JsonObject, "currentSettlementId"), moveTargetId, StringComparison.Ordinal))
            return new JsonArray();

        var location = state["location"] as JsonObject;
        var currentSettlementId = ReadString(location, "currentSettlementId");
        var targetSettlementId = ReadString(location, "targetSettlementId");
        if (moveTargetId is null &&
            (ReadBoolean(state["party"] as JsonObject, "isMoving") ||
             (!allowMapAfterNativeTownLeave && !string.Equals(targetSettlementId, currentSettlementId, StringComparison.Ordinal) &&
              !string.IsNullOrWhiteSpace(targetSettlementId)))) return new JsonArray();

        var menuId = ReadString(context, "menuId");
        if (!string.IsNullOrWhiteSpace(menuId))
        {
            var justCancelledTrade = ReadString(previousReceipt, "action") == "tradeCancel" && ReadString(previousReceipt, "status") == "completed";
            if (IsMarketMenu(menuId) && justCancelledTrade)
                return BuildLeaveMenuCatalog(state, menuId);
            if (!IsMarketMenu(menuId))
            {
                if (!AgentHostCampaignStateFacts.IsNativeLocationMenu(state)) return new JsonArray();
                return BuildLeaveMenuCatalog(state, menuId);
            }
            var tradeOptions = GetEnabledOptions(state).OfType<JsonObject>().Where(option => ReadString(option, "id") == "trade").ToArray();
            if (tradeOptions.Length == 0) return new JsonArray();
            return new JsonArray(new JsonObject
            {
                ["action"] = "menuSelect", ["arguments"] = new JsonArray("MenuId", "OptionId"),
                ["argumentValues"] = new JsonObject { ["MenuId"] = new JsonArray(menuId), ["OptionId"] = new JsonArray("trade") }
            });
        }
        if (!string.IsNullOrWhiteSpace(currentSettlementId)) return new JsonArray();
        if (safeMarkets is null) return new JsonArray(new JsonObject { ["action"] = "mapSettlementTargets", ["arguments"] = new JsonArray() });
        var ids = safeMarkets.OfType<JsonObject>().Select(target => ReadString(target, "id"))
            .Where(id => !string.IsNullOrWhiteSpace(id)).Distinct(StringComparer.Ordinal).ToArray();
        if (ids.Length == 0) return new JsonArray();
        return new JsonArray(new JsonObject
        {
            ["action"] = "move", ["arguments"] = new JsonArray("SettlementId"),
            ["argumentValues"] = new JsonObject { ["SettlementId"] = new JsonArray(ids.Select(id => (JsonNode?)JsonValue.Create(id)).ToArray()) }
        });
    }

    private static JsonArray BuildLeaveMenuCatalog(JsonObject state, string menuId)
    {
        var leaveOptions = GetEnabledOptions(state).OfType<JsonObject>()
            .Where(option => ReadBoolean(option, "isLeave"))
            .Select(option => ReadString(option, "id"))
            .Where(id => !string.IsNullOrWhiteSpace(id)).Distinct(StringComparer.Ordinal).ToArray();
        if (leaveOptions.Length == 0) return new JsonArray();
        return new JsonArray(new JsonObject
        {
            ["action"] = "menuSelect", ["arguments"] = new JsonArray("MenuId", "OptionId"),
            ["argumentValues"] = new JsonObject
            {
                ["MenuId"] = new JsonArray(menuId),
                ["OptionId"] = new JsonArray(leaveOptions.Select(id => (JsonNode?)JsonValue.Create(id)).ToArray())
            }
        });
    }

    private static JsonArray BuildControlCatalog(JsonObject state, string? moveTargetId, bool moveStartPending = false)
    {
        var context = state["context"] as JsonObject;
        if (IsMapConversationActive(state)) return new JsonArray();
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

    private static JsonArray BuildAmountCandidates(JsonObject[] offers, int playerGold, int maxPurchaseUnits)
    {
        if (playerGold < 0) return new JsonArray();
        var largestCap = offers.Select(offer => PurchaseCap(offer, playerGold, maxPurchaseUnits))
            .Where(cap => cap > 0).Distinct().OrderByDescending(cap => cap).FirstOrDefault();
        if (largestCap < 1) return new JsonArray();
        var values = new List<int> { 1 };
        if (largestCap != 1) values.Add(largestCap);
        return new JsonArray(values.Select(value => (JsonNode?)JsonValue.Create(value)).ToArray());
    }

    private static int PurchaseCap(JsonObject? offer, int playerGold, int maxPurchaseUnits)
    {
        if (offer is null || playerGold < 0) return 0;
        var stock = ReadInt(offer, "stock", 0);
        var unitPrice = ReadInt(offer, "inventoryLogicUnitPrice", 0);
        if (stock < 1 || unitPrice <= 0) return 0;
        var affordable = playerGold / unitPrice;
        var cap = Math.Min(stock, Math.Min(affordable, Math.Clamp(maxPurchaseUnits, 1, MaxPurchaseUnitsCeiling)));
        return cap < 1 ? 0 : cap;
    }

    private static JsonObject[] GetBuyableGoods(JsonObject? receipt) =>
        (receipt?["data"]?["buyOffers"] as JsonArray)?.OfType<JsonObject>()
            .Where(offer => ReadString(offer, "nativeTooltipType") == "Goods" &&
                ReadString(offer, "inventorySide") == "OtherInventory" &&
                ReadInt(offer, "stock", 0) >= 1 && ReadInt(offer, "inventoryLogicUnitPrice", 0) > 0 &&
                !string.IsNullOrWhiteSpace(ReadString(offer, "viewModelItemId")))
            .Select(offer => (JsonObject)offer.DeepClone()).ToArray() ?? Array.Empty<JsonObject>();

    private static bool IsMarketMenu(string? menuId) => menuId is "town" or "village";

    private static JsonArray FilterSafeTowns(JsonObject receipt, HashSet<string>? visitedTowns = null)
    {
        if (ReadString(receipt, "status") != "completed" || receipt["data"]?["mapSettlementTargets"] is not JsonArray targets) return new JsonArray();
        var candidates = targets.OfType<JsonObject>()
            .Where(target => ReadString(target, "type") == "town" && !ReadBoolean(target, "hostile") && !ReadBoolean(target, "underSiege") &&
                (visitedTowns is null || !visitedTowns.Contains(ReadString(target, "id") ?? string.Empty)) &&
                ReadDouble(target, "distance", double.MaxValue) > 1.0 &&
                !string.IsNullOrWhiteSpace(ReadString(target, "id")) && !string.IsNullOrWhiteSpace(ReadString(target, "name")))
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

    private static bool IsLeaveOption(JsonObject state, string optionId) =>
        GetEnabledOptions(state).OfType<JsonObject>().Any(option => ReadString(option, "id") == optionId && ReadBoolean(option, "isLeave"));

    private static bool IsMapConversationActive(JsonObject state) =>
        ReadString(state["context"] as JsonObject, "gameState") == "MapState" &&
        state["context"]?["conversation"] is JsonObject;

    private static JsonArray BuildMapConversationActionCatalog(JsonObject state)
    {
        var conversation = state["context"]?["conversation"] as JsonObject;
        if (conversation is null) return new JsonArray();
        var options = conversation["options"] as JsonArray ?? new JsonArray();
        var clickable = options.OfType<JsonObject>()
            .Where(option => ReadBoolean(option, "clickable"))
            .Select(option => ReadString(option, "id"))
            .Where(id => !string.IsNullOrWhiteSpace(id)).Distinct(StringComparer.Ordinal).ToArray();
        if (clickable.Length > 0)
        {
            return new JsonArray(new JsonObject
            {
                ["action"] = "dialogueSelect", ["arguments"] = new JsonArray("OptionId"),
                ["argumentValues"] = new JsonObject
                {
                    ["OptionId"] = new JsonArray(clickable.Select(id => (JsonNode?)JsonValue.Create(id)).ToArray())
                }
            });
        }
        return options.Count == 0
            ? new JsonArray(new JsonObject { ["action"] = "dialogueContinue", ["arguments"] = new JsonArray() })
            : new JsonArray();
    }

    private static string? ReadExistingNativeSettlementMoveTarget(JsonObject? native)
    {
        if (native is null) return null;
        var state = native["state"] as JsonObject ?? native;
        var context = state["context"] as JsonObject;
        var location = state["location"] as JsonObject;
        var party = state["party"] as JsonObject;
        var targetSettlementId = ReadString(location, "targetSettlementId");
        if (ReadString(context, "gameState") != "MapState" || !string.IsNullOrWhiteSpace(ReadString(context, "menuId")) ||
            ReadBoolean(context, "escapeMenuOpen") || ReadBoolean(context, "inquiryOpen") || ReadBoolean(context, "encounterActive") ||
            ReadBoolean(context, "isWaitMenu") || ReadBoolean(context, "isWaitActive") ||
            ReadBoolean(context?["sceneNotification"] as JsonObject, "hasActiveNotification") ||
            context?["conversation"] is JsonObject || !ReadBoolean(party, "isMoving") ||
            string.IsNullOrWhiteSpace(targetSettlementId) || !string.IsNullOrWhiteSpace(ReadString(location, "targetPartyId")) ||
            string.Equals(ReadString(location, "currentSettlementId"), targetSettlementId, StringComparison.Ordinal))
            return null;
        return targetSettlementId;
    }

    private static bool IsInterruptedMapMove(JsonObject state, string? moveTargetId, bool moveStartPending)
    {
        if (string.IsNullOrWhiteSpace(moveTargetId) || IsMapConversationActive(state)) return false;
        var context = state["context"] as JsonObject;
        var location = state["location"] as JsonObject;
        return ReadString(context, "gameState") == "MapState" &&
            ReadString(location, "currentSettlementId") != moveTargetId &&
            !ReadBoolean(state["party"] as JsonObject, "isMoving") && !moveStartPending;
    }

    private static string? ReadMoveTargetId(JsonObject? arguments) => ReadString(arguments, "settlementId");

    private static bool HasReachedMoveTargetMenu(JsonObject state, string? moveTargetId)
    {
        if (string.IsNullOrWhiteSpace(moveTargetId)) return false;
        var location = state["location"] as JsonObject;
        var context = state["context"] as JsonObject;
        return string.Equals(ReadString(location, "currentSettlementId"), moveTargetId, StringComparison.Ordinal) &&
            !string.IsNullOrWhiteSpace(ReadString(context, "menuId"));
    }

    private static bool TryResolveAction(
        JsonObject state,
        JsonObject? previousReceipt,
        JsonArray catalog,
        JsonObject decision,
        JsonArray? safeMarkets,
        int maxPurchaseUnits,
        out string? action,
        out JsonObject? arguments,
        out string? rejection)
    {
        action = ReadString(decision, "action");
        arguments = null;
        rejection = null;
        var requestedAction = action;
        var listed = requestedAction is null ? null : catalog.OfType<JsonObject>().FirstOrDefault(item => ReadString(item, "action") == requestedAction);
        if (listed is null || decision["arguments"] is not JsonObject supplied)
        {
            rejection = "Choose one action from the current town-trade catalog.";
            return false;
        }
        var names = listed["arguments"] as JsonArray ?? new JsonArray();
        if (names.Count != supplied.Count || names.Any(name => name?.GetValue<string>() is not string key || !supplied.ContainsKey(key)))
        {
            rejection = "Native action arguments must exactly match the current town-trade catalog.";
            return false;
        }

        if (action == "dialogueSelect")
        {
            var optionId = ReadString(supplied, "OptionId");
            var options = state["context"]?["conversation"]?["options"] as JsonArray;
            var currentOption = options?.OfType<JsonObject>().FirstOrDefault(option =>
                ReadString(option, "id") == optionId && ReadBoolean(option, "clickable"));
            var listedOptionIds = listed["argumentValues"]?["OptionId"] as JsonArray;
            if (!IsMapConversationActive(state) || string.IsNullOrWhiteSpace(optionId) || currentOption is null ||
                listedOptionIds?.Any(value => value?.GetValue<string>() == optionId) != true)
            {
                rejection = "Choose only a currently clickable option from the active MapState conversation.";
                return false;
            }
            arguments = new JsonObject { ["optionId"] = optionId };
            return true;
        }
        if (action == "dialogueContinue")
        {
            var options = state["context"]?["conversation"]?["options"] as JsonArray;
            if (supplied.Count != 0 || !IsMapConversationActive(state) || options is null || options.Count != 0)
            {
                rejection = "dialogueContinue is valid only when the active conversation has no clickable options.";
                return false;
            }
            arguments = new JsonObject();
            return true;
        }
        if (action == "move")
        {
            var targetId = ReadString(supplied, "SettlementId");
            if (safeMarkets?.OfType<JsonObject>().Any(target => ReadString(target, "id") == targetId && ReadString(target, "type") == "town") != true ||
                !listed["argumentValues"]!["SettlementId"]!.AsArray().Any(value => value?.GetValue<string>() == targetId))
            {
                rejection = "Movement is limited to a currently observed safe Town target.";
                return false;
            }
            arguments = new JsonObject { ["settlementId"] = targetId };
            return true;
        }
        if (action == "menuSelect")
        {
            var menuId = ReadString(supplied, "MenuId");
            var optionId = ReadString(supplied, "OptionId");
            var currentMenuId = ReadString(state["context"] as JsonObject, "menuId");
            var currentOption = GetEnabledOptions(state).OfType<JsonObject>().FirstOrDefault(option => ReadString(option, "id") == optionId);
            var listedMenuIds = listed["argumentValues"]?["MenuId"] as JsonArray;
            var listedOptionIds = listed["argumentValues"]?["OptionId"] as JsonArray;
            var isListedMenuChoice = listedMenuIds?.Any(value => value?.GetValue<string>() == menuId) == true &&
                listedOptionIds?.Any(value => value?.GetValue<string>() == optionId) == true;
            var isMarketTrade = IsMarketMenu(menuId) && optionId == "trade" &&
                !(ReadString(previousReceipt, "action") == "tradeCancel" && ReadString(previousReceipt, "status") == "completed");
            var isLeave = ReadBoolean(currentOption, "isLeave") && AgentHostCampaignStateFacts.IsNativeLocationMenu(state) &&
                (!IsMarketMenu(menuId) || (ReadString(previousReceipt, "action") == "tradeCancel" && ReadString(previousReceipt, "status") == "completed"));
            if (!isListedMenuChoice || menuId != currentMenuId || (!isMarketTrade && !isLeave) || currentOption is null)
            {
                rejection = "Select only the current Native market Trade entry or a currently enabled Native location Leave option.";
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
            var offer = GetBuyableGoods(previousReceipt).FirstOrDefault(candidate => ReadString(candidate, "viewModelItemId") == itemId);
            var cap = PurchaseCap(offer, ReadInt(state["economy"] as JsonObject, "gold", -1), maxPurchaseUnits);
            var isLowerIdentifier = !string.IsNullOrWhiteSpace(itemId) && itemId!.All(character => character is >= 'a' and <= 'z' or >= '0' and <= '9' or '_' or '-');
            if (ReadString(previousReceipt, "action") != "tradeOptions" || ReadString(previousReceipt, "status") != "completed" ||
                direction != "buy" || side != "OtherInventory" || offer is null || !isLowerIdentifier || amount < 1 || amount > cap ||
                listed["argumentValues"]?["ItemViewModelId"]?.AsArray().Any(value => value?.GetValue<string>() == itemId) != true ||
                listed["argumentValues"]?["Amount"]?.AsArray().Any(value => value?.GetValue<int>() == amount) != true)
            {
                rejection = offer is null
                    ? "The buy item must come from the current Native Trade quote."
                    : $"Buy must move between one and {cap} units of the current OtherInventory Goods offer with the listed exact item id.";
                return false;
            }
            arguments = new JsonObject
            {
                ["direction"] = "buy", ["itemViewModelId"] = itemId, ["inventorySide"] = "OtherInventory", ["amount"] = amount
            };
            return true;
        }
        if (action is "mapSettlementTargets" or "tradeOptions" or "tradeConfirm" or "tradeCancel" or "tradeCancelChanges" or "inventoryDone" && supplied.Count == 0)
        {
            arguments = new JsonObject();
            return true;
        }
        rejection = "The action is not supported by the bounded town-trade buy profile.";
        return false;
    }

    private static bool VerifyBuyReceipt(JsonObject data, int expectedAmount)
    {
        var amount = ReadInt(data, "amount", 0);
        if (ReadBoolean(data, "postconditionPassed") != true || ReadString(data, "direction") != "buy" ||
            amount < 1 || amount != expectedAmount || ReadString(data, "inventorySide") != "OtherInventory")
            return false;
        var goldBefore = ReadInt(data, "playerGoldBefore", -1);
        var goldAfter = ReadInt(data, "playerGoldAfter", -2);
        var playerBefore = ReadInt(data, "playerCountBefore", -1);
        var playerAfter = ReadInt(data, "playerCountAfter", -2);
        var marketBefore = ReadInt(data, "marketCountBefore", -1);
        var marketAfter = ReadInt(data, "marketCountAfter", -2);
        var dayBefore = ReadDouble(data, "campaignDayBefore", double.NaN);
        var dayAfter = ReadDouble(data, "campaignDayAfter", double.NaN);
        return goldBefore >= 0 && goldAfter < goldBefore &&
            playerAfter == playerBefore + amount && marketAfter == marketBefore - amount &&
            ReadString(data, "timeControlModeBefore") == ReadString(data, "timeControlModeAfter") &&
            double.IsFinite(dayBefore) && double.IsFinite(dayAfter) && Math.Abs(dayBefore - dayAfter) <= 0.000001 &&
            goldBefore - goldAfter == Math.Abs(ReadInt(data, "nativeTransactionAmount", 0));
    }

    private static JsonObject BuildObservation(JsonObject native, JsonObject state, JsonObject? buyReceipt) => new()
    {
        ["status"] = ReadString(native, "status"),
        ["timeControlMode"] = ReadString(native, "timeControlMode"),
        ["campaignDay"] = native["campaignDay"]?.DeepClone(),
        ["buyReceipt"] = buyReceipt?.DeepClone(),
        ["state"] = state.DeepClone()
    };

    private static JsonObject BuildDecisionRequest(
        string runId,
        string? goal,
        int iteration,
        JsonObject observation,
        JsonObject? previousReceipt,
        JsonObject? feedback,
        JsonArray actionCatalog,
        JsonArray controls,
        bool moveStartPending)
    {
        var request = new JsonObject
        {
            ["runId"] = runId,
            ["goal"] = goal,
            ["goalKind"] = "bounded-town-trade-buy",
            ["goalScopeClassificationRequired"] = false,
            ["previousActionReceipt"] = previousReceipt?.DeepClone(),
            ["decisionFeedback"] = feedback?.DeepClone(),
            ["observation"] = observation.DeepClone(),
            ["allowedActions"] = actionCatalog.DeepClone(),
            ["allowedControls"] = controls.DeepClone()
        };
        request["controlArguments"] = controls.Any(control => control?.GetValue<string>() == "observeAgain")
            ? new JsonObject
            {
                ["observeAgain"] = new JsonObject
                {
                    ["waitSeconds"] = new JsonObject
                    {
                        ["type"] = "integer",
                        ["minimum"] = GetMinimumObserveInterval(moveStartPending),
                        ["maximum"] = 10
                    }
                }
            }
            : new JsonObject();
        request["iteration"] = iteration;
        return request;
    }

    private static int GetMinimumObserveInterval(bool moveStartPending) => moveStartPending ? 1 : MinimumActiveMapTravelObserveSeconds;

    private static bool IsSupportedObserveInterval(int seconds, bool moveStartPending) =>
        seconds >= GetMinimumObserveInterval(moveStartPending) && seconds <= 10;

    private static JsonObject? BuildProviderPreviousReceipt(JsonObject? previousReceipt, JsonArray? safeTowns)
    {
        var action = ReadString(previousReceipt, "action");
        if (action == "tradeOptions")
        {
            var compactTrade = previousReceipt?.DeepClone() as JsonObject;
            if (compactTrade is null) return null;
            var tradeData = compactTrade["data"] as JsonObject;
            if (tradeData is null || tradeData["buyOffers"] is not JsonArray) return compactTrade;
            var buyableGoods = GetBuyableGoods(previousReceipt);
            compactTrade["data"] = new JsonObject
            {
                ["buyOffers"] = new JsonArray(buyableGoods.Select(offer => (JsonNode?)offer.DeepClone()).ToArray()),
                ["candidateScope"] = "currently buyable OtherInventory Goods",
                ["candidateCount"] = buyableGoods.Length
            };
            return compactTrade;
        }
        if (action != "mapSettlementTargets") return previousReceipt?.DeepClone() as JsonObject;
        var compact = previousReceipt?.DeepClone() as JsonObject;
        var data = compact?["data"] as JsonObject;
        if (data is null || data["mapSettlementTargets"] is not JsonArray) return compact;
        data["mapSettlementTargets"] = safeTowns?.DeepClone() as JsonArray ?? new JsonArray();
        data["candidateScope"] = "currently observed safe Town targets for the bounded buy profile";
        data["candidateCount"] = safeTowns?.Count ?? 0;
        return compact;
    }

    private static JsonObject BuildReceipt(string action, JsonObject arguments, JsonObject receipt)
    {
        var result = new JsonObject { ["action"] = action, ["status"] = ReadString(receipt, "status"), ["data"] = receipt["data"]?.DeepClone() };
        if (action == "menuSelect")
        {
            result["menuId"] = arguments["menuId"]?.DeepClone();
            result["optionId"] = arguments["optionId"]?.DeepClone();
        }
        if (action == "move") result["targetSettlementId"] = arguments["settlementId"]?.DeepClone();
        if (action == "trade")
        {
            result["itemViewModelId"] = arguments["itemViewModelId"]?.DeepClone();
            result["direction"] = "buy";
            result["amount"] = arguments["amount"]?.DeepClone();
        }
        return result;
    }

    private static JsonObject BuildStep(
        int iteration,
        JsonObject observation,
        JsonObject decision,
        JsonObject? receipt,
        string started,
        long startedTicks,
        JsonObject? control,
        JsonObject? observationAfter) => new()
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

    private static bool IsSupportedStartingState(JsonObject state)
    {
        if (IsFreeCampaignMap(state)) return true;
        var context = state["context"] as JsonObject;
        var inventory = state["inventoryScreen"] as JsonObject;
        var currentSettlementId = ReadString(state["location"] as JsonObject, "currentSettlementId");
        return ReadString(context, "gameState") == "InventoryState" && ReadString(inventory, "mode") == "Trade" &&
            ReadBoolean(inventory, "hasHandler") && !string.IsNullOrWhiteSpace(currentSettlementId) &&
            string.Equals(ReadString(context, "encounteredPartyId"), currentSettlementId, StringComparison.Ordinal) &&
            !ReadBoolean(context, "inquiryOpen") && !ReadBoolean(context, "escapeMenuOpen") &&
            !ReadBoolean(context?["captivity"] as JsonObject, "isCaptive");
    }

    private static bool IsFreeCampaignMap(JsonObject state)
    {
        var context = state["context"] as JsonObject;
        return ReadString(context, "gameState") == "MapState" &&
            !ReadBoolean(context?["captivity"] as JsonObject, "isCaptive") &&
            !IsActiveEncounter(state) && context?["battleSimulation"] is null &&
            !ReadBoolean(context, "escapeMenuOpen") && !ReadBoolean(context, "inquiryOpen") &&
            state["inventoryScreen"] is null && state["partyScreen"] is null;
    }

    private static bool IsActiveEncounter(JsonObject state)
    {
        var context = state["context"] as JsonObject;
        var inventory = state["inventoryScreen"] as JsonObject;
        var currentSettlementId = ReadString(state["location"] as JsonObject, "currentSettlementId");
        var nativeSettlementTrade = ReadString(context, "gameState") == "InventoryState" &&
            ReadString(inventory, "mode") == "Trade" && ReadBoolean(inventory, "hasHandler") &&
            !string.IsNullOrWhiteSpace(currentSettlementId) &&
            string.Equals(ReadString(context, "encounteredPartyId"), currentSettlementId, StringComparison.Ordinal);
        return AgentHostCampaignStateFacts.IsActiveEncounter(state) && !nativeSettlementTrade;
    }

    private static (string Code, string Message) DescribeNoAction(
        JsonObject state,
        JsonObject? previousReceipt,
        HashSet<string> visitedTowns,
        JsonArray? safeTowns)
    {
        var context = state["context"] as JsonObject;
        var buyOffers = (previousReceipt?["data"]?["buyOffers"] as JsonArray)?.Count ?? 0;
        var noBuyableGoods = ReadString(context, "gameState") == "InventoryState" &&
            ReadString(state["inventoryScreen"] as JsonObject, "mode") == "Trade" &&
            ReadString(previousReceipt, "action") == "tradeOptions" && GetBuyableGoods(previousReceipt).Length == 0;
        if (noBuyableGoods || (visitedTowns.Count > 0 && safeTowns is { Count: 0 } &&
            string.IsNullOrWhiteSpace(ReadString(state["location"] as JsonObject, "currentSettlementId"))))
            return ("town-trade-no-buyable-otherinventory-goods",
                "The visible safe Town markets have no currently buyable OtherInventory Goods; the bounded purchase stopped without changing Gold, items or Campaign time.");
        return ("town-trade-no-safe-native-action",
            $"No safe town-trade action is available: gameState={ReadString(context, "gameState") ?? "<none>"}; menuId={ReadString(context, "menuId") ?? "<none>"}; buyOfferCount={buyOffers}.");
    }

    private static bool CanSafelyCancelUntouchedNativeTrade(JsonObject? native, int buyActionCount, JsonObject? previousReceipt)
    {
        if (native is null || buyActionCount != 0 || native["state"] is not JsonObject state) return false;
        var context = state["context"] as JsonObject;
        var captivity = context?["captivity"] as JsonObject;
        var inventory = state["inventoryScreen"] as JsonObject;
        if (ReadString(context, "gameState") != "InventoryState" || ReadString(inventory, "mode") != "Trade" ||
            ReadBoolean(context, "inquiryOpen") || ReadBoolean(context, "escapeMenuOpen") ||
            ReadBoolean(captivity, "isCaptive") || IsActiveEncounter(state)) return false;
        if (inventory?["hasPendingChanges"] is JsonValue pendingValue && pendingValue.TryGetValue<bool>(out var hasPendingChanges))
            return !hasPendingChanges;
        return ReadString(previousReceipt, "action") == "menuSelect" && IsMarketMenu(ReadString(previousReceipt, "menuId")) &&
            ReadString(previousReceipt, "optionId") == "trade";
    }

    private static JsonObject BuildSuccess(
        string runId,
        IAgentHostDecisionProvider provider,
        JsonObject initialNative,
        JsonObject finalNative,
        JsonObject buyReceipt,
        JsonObject? finalReceipt,
        DecisionRunLedger ledger,
        int actionsExecuted,
        int buyActionsExecuted,
        double campaignDayBefore,
        string? timeControlModeBefore,
        int maxPurchaseUnits)
    {
        var amount = ReadInt(buyReceipt, "amount", 0);
        return new JsonObject
        {
            ["status"] = "completed",
            ["resultKind"] = "town-trade-buy",
            ["providerModelId"] = provider.ModelId,
            ["providerConfigurationSource"] = provider.ConfigurationSource,
            ["runId"] = runId,
            ["decisions"] = ledger.Decisions,
            ["actionsExecuted"] = actionsExecuted,
            ["buyActionsExecuted"] = buyActionsExecuted,
            ["promptTokens"] = ledger.PromptTokens,
            ["completionTokens"] = ledger.CompletionTokens,
            ["providerRouteHistory"] = ledger.Routes.DeepClone(),
            ["initialNativeState"] = initialNative.DeepClone(),
            ["finalNativeState"] = finalNative.DeepClone(),
            ["buyVerified"] = true,
            ["tradeTimeUnchanged"] = ReadString(buyReceipt, "timeControlModeBefore") == ReadString(buyReceipt, "timeControlModeAfter") &&
                Math.Abs(ReadDouble(buyReceipt, "campaignDayBefore", double.NaN) - ReadDouble(buyReceipt, "campaignDayAfter", double.NaN)) <= 0.000001,
            ["buyReceipt"] = buyReceipt.DeepClone(),
            ["finalReceipt"] = finalReceipt?.DeepClone(),
            ["purchasedAmount"] = amount,
            ["goldSpent"] = Math.Abs(ReadInt(buyReceipt, "nativeTransactionAmount", 0)),
            ["maxPurchaseUnits"] = maxPurchaseUnits,
            ["initialCampaignDay"] = double.IsFinite(campaignDayBefore) ? JsonValue.Create(campaignDayBefore) : null,
            ["finalCampaignDay"] = finalNative["campaignDay"]?.DeepClone(),
            ["initialTimeControlMode"] = timeControlModeBefore,
            ["finalTimeControlMode"] = ReadString(finalNative, "timeControlMode"),
            ["explicitTimeActions"] = new JsonArray(),
            ["termination"] = new JsonObject
            {
                ["reason"] = "one-native-buy-otherinventory-goods-and-gold-inverse-verified",
                ["completedByProvider"] = false,
                ["goalVerified"] = true
            },
            ["trace"] = ledger.Trace.DeepClone()
        };
    }

    internal static IReadOnlyList<object> RunContractSelfTests()
    {
        if (!AgentHostDecisionCycle.TownTradeSystemPrompt.Contains("Buy one current buyable OtherInventory Goods", StringComparison.Ordinal) ||
            !AgentHostDecisionCycle.TownTradeSystemPrompt.Contains("never sell", StringComparison.Ordinal) ||
            !AgentHostDecisionCycle.BuildTownTradeSystemPrompt(new JsonObject
            {
                ["allowedActions"] = new JsonArray(new JsonObject
                {
                    ["action"] = "menuSelect",
                    ["argumentValues"] = new JsonObject
                    {
                        ["MenuId"] = new JsonArray("town"),
                        ["OptionId"] = new JsonArray("town_leave")
                    }
                }),
                ["observation"] = new JsonObject
                {
                    ["state"] = new JsonObject { ["context"] = new JsonObject { ["menuId"] = "town" } }
                },
                ["previousActionReceipt"] = new JsonObject { ["action"] = "tradeCancel" }
            }).Contains("no currently buyable OtherInventory Goods", StringComparison.Ordinal))
            throw new AgentHostException("town-trade-self-test-buy-prompt-missing", "The bound provider prompt must name one current OtherInventory Goods buy, forbid selling, and explain the no-buyable cancel-to-leave path.");

        var quote = new JsonObject
        {
            ["status"] = "completed",
            ["action"] = "tradeOptions",
            ["data"] = new JsonObject
            {
                ["buyOffers"] = new JsonArray(
                    new JsonObject
                    {
                        ["nativeTooltipType"] = "Goods", ["inventorySide"] = "OtherInventory", ["viewModelItemId"] = "grain",
                        ["stock"] = 5, ["inventoryLogicUnitPrice"] = 20, ["isTransferable"] = false
                    },
                    new JsonObject
                    {
                        ["nativeTooltipType"] = "Goods", ["inventorySide"] = "PlayerInventory", ["viewModelItemId"] = "sell-only",
                        ["stock"] = 9, ["inventoryLogicUnitPrice"] = 10, ["isTransferable"] = true
                    })
            }
        };
        var tradeState = InventoryTradeState(120, hasPendingChanges: false);
        var buyCatalog = BuildActionCatalog(tradeState["state"] as JsonObject ?? tradeState, quote, null, null, MaxPurchaseUnitsDefault);
        var buyEntry = buyCatalog.Count == 1 ? buyCatalog[0] as JsonObject : null;
        var buyAmounts = buyEntry?["argumentValues"]?["Amount"] as JsonArray;
        var buyDirection = buyEntry?["argumentValues"]?["Direction"] as JsonArray;
        var buyInventorySide = buyEntry?["argumentValues"]?["InventorySide"] as JsonArray;
        var buyItemId = buyEntry?["argumentValues"]?["ItemViewModelId"] as JsonArray;
        if (ReadString(buyEntry, "action") != "trade" || buyDirection is null || ReadString(buyDirection, 0) != "buy" ||
            buyInventorySide is null || ReadString(buyInventorySide, 0) != "OtherInventory" ||
            buyAmounts?.Count != 2 || buyAmounts[0]?.GetValue<int>() != 1 || buyAmounts[1]?.GetValue<int>() != 5 ||
            buyItemId is null || ReadString(buyItemId, 0) != "grain")
            throw new AgentHostException("town-trade-self-test-buy-catalog-wrong", "The catalog must quote buy-side OtherInventory Goods from buyOffers with one-unit and capped amount candidates, never sellOffers.");
        if (!TryResolveAction(tradeState["state"] as JsonObject ?? tradeState, quote, buyCatalog,
                new JsonObject { ["action"] = "trade", ["arguments"] = new JsonObject { ["Direction"] = "buy", ["ItemViewModelId"] = "grain", ["InventorySide"] = "OtherInventory", ["Amount"] = 5 } },
                null, MaxPurchaseUnitsDefault, out var resolvedAction, out _, out _) ||
            resolvedAction != "trade" || ResolveSellAttemptRejected(tradeState, quote, buyCatalog))
            throw new AgentHostException("town-trade-self-test-sell-not-rejected", "A sell direction, PlayerInventory side, wrong amount or extra argument must be rejected before Native.");

        var cappedCatalog = BuildActionCatalog(InventoryTradeState(41, false)["state"] as JsonObject ?? throw new AgentHostException("town-trade-self-test-state-missing", "The capped Gold fixture must carry a state object."), quote, null, null, 2);
        var cappedAmounts = (cappedCatalog[0]?["argumentValues"]?["Amount"] as JsonArray);
        if (cappedAmounts?.Count != 2 || cappedAmounts[0]?.GetValue<int>() != 1 || cappedAmounts[1]?.GetValue<int>() != 2)
            throw new AgentHostException("town-trade-self-test-amount-cap-wrong", "A purchase must be capped by stock, affordable Gold and the bounded maxPurchaseUnits setting.");

        var tradeTargets = new JsonObject
        {
            ["status"] = "completed",
            ["data"] = new JsonObject
            {
                ["mapSettlementTargets"] = new JsonArray(
                    new JsonObject { ["id"] = "town-near", ["name"] = "Near Town", ["type"] = "town", ["distance"] = 3, ["hostile"] = false, ["underSiege"] = false },
                    new JsonObject { ["id"] = "village-near", ["name"] = "Near Village", ["type"] = "village", ["distance"] = 2, ["hostile"] = false, ["underSiege"] = false },
                    new JsonObject { ["id"] = "town-hostile", ["name"] = "Hostile Town", ["type"] = "town", ["distance"] = 4, ["hostile"] = true, ["underSiege"] = false },
                    new JsonObject { ["id"] = "town-far", ["name"] = "Far Town", ["type"] = "town", ["distance"] = 9, ["hostile"] = false, ["underSiege"] = true })
            }
        };
        var safeTowns = FilterSafeTowns(tradeTargets);
        if (safeTowns.Count != 1 || ReadString(safeTowns[0] as JsonObject, "id") != "town-near")
            throw new AgentHostException("town-trade-self-test-safe-towns-wrong", "Only a non-hostile, unbesieged Town may become a buy-route movement target.");
        var mapState = MapState(null, null, []);
        var moveCatalog = BuildActionCatalog(mapState["state"] as JsonObject ?? throw new AgentHostException("town-trade-self-test-state-missing", "The map fixture must carry a state object."), null, safeTowns, null, MaxPurchaseUnitsDefault);
        if (ReadString(moveCatalog[0] as JsonObject, "action") != "move" ||
            (moveCatalog[0]?["argumentValues"]?["SettlementId"] as JsonArray)?[0]?.GetValue<string>() != "town-near")
            throw new AgentHostException("town-trade-self-test-move-catalog-invalid", "The safe Town catalog must expose only a move action.");

        var nativeTrade = InventoryTradeState(80, false);
        var nativeTradeState = nativeTrade["state"] as JsonObject ?? throw new AgentHostException("town-trade-self-test-state-missing", "The Native Trade fixture must carry a state object.");
        (nativeTradeState["context"] as JsonObject)!["encounterActive"] = true;
        (nativeTradeState["context"] as JsonObject)!["encounteredPartyId"] = "town-a";
        (nativeTradeState["location"] as JsonObject)!["currentSettlementId"] = "town-a";
        (nativeTradeState["inventoryScreen"] as JsonObject)!["hasHandler"] = true;
        if (!IsSupportedStartingState(nativeTradeState) ||
            ReadString(BuildActionCatalog(nativeTradeState, null, null, null, MaxPurchaseUnitsDefault)[0] as JsonObject, "action") != "tradeOptions")
            throw new AgentHostException("town-trade-self-test-native-trade-encounter", "A settlement's Native Trade screen must not be mistaken for a hostile encounter.");

        var emptyMarket = MapState("town", "town-a",
            new JsonArray(new JsonObject { ["id"] = "town_leave", ["available"] = true, ["enabled"] = true, ["isLeave"] = true }));
        var emptyMarketState = emptyMarket["state"] as JsonObject ?? throw new AgentHostException("town-trade-self-test-state-missing", "The empty market fixture must carry a state object.");
        (emptyMarketState["context"] as JsonObject)!["encounterActive"] = true;
        (emptyMarketState["context"] as JsonObject)!["encounteredPartyId"] = "town-a";
        var cancelReceipt = new JsonObject { ["action"] = "tradeCancel", ["status"] = "completed" };
        var leaveCatalog = BuildActionCatalog(emptyMarketState, cancelReceipt, null, null, MaxPurchaseUnitsDefault);
        if (leaveCatalog.Count != 1 || ReadString(leaveCatalog[0] as JsonObject, "action") != "menuSelect" ||
            (leaveCatalog[0]?["argumentValues"]?["OptionId"] as JsonArray)?[0]?.GetValue<string>() != "town_leave" ||
            !TryResolveAction(emptyMarketState, cancelReceipt, leaveCatalog,
                new JsonObject { ["action"] = "menuSelect", ["arguments"] = new JsonObject { ["MenuId"] = "town", ["OptionId"] = "town_leave" } },
                null, MaxPurchaseUnitsDefault, out var leaveAction, out _, out _) || leaveAction != "menuSelect")
            throw new AgentHostException("town-trade-self-test-empty-market-leave", "An exhausted market must expose and accept only the current Town leave option.");

        var validCommit = new JsonObject
        {
            ["postconditionPassed"] = true, ["direction"] = "buy", ["inventorySide"] = "OtherInventory", ["amount"] = 3,
            ["playerGoldBefore"] = 100, ["playerGoldAfter"] = 40, ["playerCountBefore"] = 2, ["playerCountAfter"] = 5,
            ["marketCountBefore"] = 8, ["marketCountAfter"] = 5, ["timeControlModeBefore"] = "Stop", ["timeControlModeAfter"] = "Stop",
            ["campaignDayBefore"] = 12.5, ["campaignDayAfter"] = 12.5, ["nativeTransactionAmount"] = -60
        };
        var invalidCommit = validCommit.DeepClone().AsObject();
        invalidCommit["playerGoldAfter"] = 39;
        if (!VerifyBuyReceipt(validCommit, 3) || VerifyBuyReceipt(invalidCommit, 3))
            throw new AgentHostException("town-trade-self-test-commit-verification", "One buy must verify exact Gold inverse, player/market count deltas and unchanged Campaign time.");

        return
        [
            new { scenario = "town-trade-prompt-bound-to-one-current-otherinventory-buy-and-never-sell", passed = true },
            new { scenario = "town-trade-catalog-quotes-buy-offers-with-bounded-amount-candidates", passed = true },
            new { scenario = "town-trade-moves-only-to-safe-towns", passed = true },
            new { scenario = "town-trade-rejects-sell-playerinventory-stale-and-malformed-arguments", passed = true },
            new { scenario = "town-trade-native-settlement-trade-is-not-a-hostile-encounter", passed = true },
            new { scenario = "town-trade-empty-market-exits-through-current-town-leave", passed = true },
            new { scenario = "town-trade-confirm-verifies-gold-inverse-and-item-count-deltas", passed = true }
        ];

        static bool ResolveSellAttemptRejected(JsonObject tradeState, JsonObject quote, JsonArray catalog)
        {
            var wrongDirection = new JsonObject { ["action"] = "trade", ["arguments"] = new JsonObject { ["Direction"] = "sell", ["ItemViewModelId"] = "grain", ["InventorySide"] = "OtherInventory", ["Amount"] = 1 } };
            var wrongSide = new JsonObject { ["action"] = "trade", ["arguments"] = new JsonObject { ["Direction"] = "buy", ["ItemViewModelId"] = "grain", ["InventorySide"] = "PlayerInventory", ["Amount"] = 1 } };
            var wrongAmount = new JsonObject { ["action"] = "trade", ["arguments"] = new JsonObject { ["Direction"] = "buy", ["ItemViewModelId"] = "grain", ["InventorySide"] = "OtherInventory", ["Amount"] = 6 } };
            var extraArgument = new JsonObject { ["action"] = "trade", ["arguments"] = new JsonObject { ["Direction"] = "buy", ["ItemViewModelId"] = "grain", ["InventorySide"] = "OtherInventory", ["Amount"] = 1, ["Extra"] = 1 } };
            return TryResolveAction(tradeState["state"] as JsonObject ?? tradeState, quote, catalog, wrongDirection, null, MaxPurchaseUnitsDefault, out _, out _, out _) ||
                TryResolveAction(tradeState["state"] as JsonObject ?? tradeState, quote, catalog, wrongSide, null, MaxPurchaseUnitsDefault, out _, out _, out _) ||
                TryResolveAction(tradeState["state"] as JsonObject ?? tradeState, quote, catalog, wrongAmount, null, MaxPurchaseUnitsDefault, out _, out _, out _) ||
                TryResolveAction(tradeState["state"] as JsonObject ?? tradeState, quote, catalog, extraArgument, null, MaxPurchaseUnitsDefault, out _, out _, out _);
        }

        static JsonObject InventoryTradeState(int gold, bool hasPendingChanges) => new()
        {
            ["economy"] = new JsonObject { ["gold"] = gold },
            ["state"] = new JsonObject
            {
                ["economy"] = new JsonObject { ["gold"] = gold },
                ["context"] = new JsonObject
                {
                    ["gameState"] = "InventoryState", ["menuId"] = null, ["escapeMenuOpen"] = false, ["inquiryOpen"] = false,
                    ["encounterActive"] = false, ["encounteredPartyId"] = "town-a", ["captivity"] = null, ["battleSimulation"] = null
                },
                ["location"] = new JsonObject { ["currentSettlementId"] = "town-a", ["targetSettlementId"] = null },
                ["party"] = new JsonObject { ["isMoving"] = false },
                ["inventoryScreen"] = new JsonObject { ["mode"] = "Trade", ["hasHandler"] = true, ["hasPendingChanges"] = hasPendingChanges },
                ["availableMenuOptions"] = new JsonArray()
            }
        };

        static JsonObject MapState(string? menuId, string? settlementId, JsonArray options) => new()
        {
            ["economy"] = new JsonObject { ["gold"] = 100 },
            ["state"] = new JsonObject
            {
                ["economy"] = new JsonObject { ["gold"] = 100 },
                ["context"] = new JsonObject
                {
                    ["gameState"] = "MapState", ["menuId"] = menuId, ["escapeMenuOpen"] = false, ["inquiryOpen"] = false,
                    ["encounterActive"] = false, ["encounteredPartyId"] = null, ["captivity"] = null, ["battleSimulation"] = null
                },
                ["location"] = new JsonObject { ["currentSettlementId"] = settlementId, ["targetSettlementId"] = null },
                ["party"] = new JsonObject { ["isMoving"] = false },
                ["availableMenuOptions"] = options.DeepClone()
            }
        };
    }

    private static string? ReadString(JsonArray array, int index) => array[index] is JsonValue node && node.TryGetValue<string>(out var text) ? text : null;

    private static JsonObject ParseObject(JsonElement element) => JsonNode.Parse(element.GetRawText())?.AsObject()
        ?? throw new AgentHostException("native-response-invalid", "Native returned no object.");
    private static int ReadInt(JsonElement element, string key, int fallback) => element.ValueKind == JsonValueKind.Object && element.TryGetProperty(key, out var value) && value.TryGetInt32(out var number) ? number : fallback;
    private static int ReadInt(JsonObject? value, string key, int fallback) => value?[key] is JsonValue node && node.TryGetValue<int>(out var number) ? number : fallback;
    private static double ReadDouble(JsonObject? value, string key, double fallback) => value?[key] is JsonValue node && node.TryGetValue<double>(out var number) ? number : fallback;
    private static bool ReadBoolean(JsonObject? value, string key) => value?[key] is JsonValue node && node.TryGetValue<bool>(out var result) && result;
    private static string? ReadString(JsonObject? value, string key) => value?[key] is JsonValue node && node.TryGetValue<string>(out var text) ? text : null;
    private static string? ReadString(JsonElement value, string key) => value.ValueKind == JsonValueKind.Object && value.TryGetProperty(key, out var property) && property.ValueKind == JsonValueKind.String ? property.GetString() : null;
    private static long ReadLong(JsonObject? value, string key, long fallback) => value?[key] is JsonValue node && node.TryGetValue<long>(out var result) ? result : fallback;
}
