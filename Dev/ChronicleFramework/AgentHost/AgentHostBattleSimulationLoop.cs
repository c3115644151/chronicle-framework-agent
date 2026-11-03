using System.Diagnostics;
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal static class AgentHostBattleSimulationLoop
{
    private const int MaxRejectedDecisions = 2;
    private const string ContractId = "native-campaign-battle-simulation-v1";
    private const string WeakPartySurrenderResponseTextId = "LLEffOga";

    internal static async Task<JsonObject> RunAsync(
        JsonElement request,
        IAgentHostBattleSimulationNativeClient client,
        IAgentHostDecisionProvider provider,
        CancellationToken cancellationToken,
        int priorDecisions = 0,
        long priorPromptTokens = 0,
        long priorCompletionTokens = 0,
        JsonArray? priorTrace = null,
        JsonArray? priorProviderRouteHistory = null,
        bool recoverPlayerCaptivity = false,
        int passiveCaptivityPollSeconds = 15,
        IAgentHostNativeInquiryClient? inquiryClient = null)
    {
        var runId = ReadString(request, "runId") ?? Guid.NewGuid().ToString("N");
        var goal = ReadString(request, "goal") ?? string.Empty;
        var maxDecisions = Math.Clamp(ReadInt(request, "maxDecisions", AgentHostCampaignLoop.MaxCumulativeDecisions), 1, AgentHostCampaignLoop.MaxCumulativeDecisions);
        var maxElapsedSeconds = Math.Clamp(ReadInt(request, "maxElapsedSeconds", 7200), 1, 7200);
        var parentEycObjectives = request.TryGetProperty("parentEycObjectives", out var parentEycObjectivesElement) && parentEycObjectivesElement.ValueKind == JsonValueKind.Object
            ? JsonNode.Parse(parentEycObjectivesElement.GetRawText()) as JsonObject
            : null;
        var parentPartySizeObjective = parentEycObjectives?["partySize"] as JsonObject;
        var parentPartySizeObjectiveUnmet = parentPartySizeObjective is not null && !ReadBoolean(parentPartySizeObjective, "met");
        var allowedActionNames = request.TryGetProperty("allowedActionNames", out var names) && names.ValueKind == JsonValueKind.Array
            ? names.EnumerateArray().Where(x => x.ValueKind == JsonValueKind.String).Select(x => x.GetString()!).ToHashSet(StringComparer.Ordinal)
            : new HashSet<string>(StringComparer.Ordinal);
        if (string.IsNullOrWhiteSpace(goal) ||
            (!allowedActionNames.SetEquals(AgentHostCampaignLoop.BattleSimulationActions) && !allowedActionNames.SetEquals(AgentHostCampaignLoop.AllSupportedActions)))
            throw new AgentHostException("battle-simulation-loop-request-invalid", "The Host requires the bounded BattleSimulation action set or its approved Campaign superset.");

        using var elapsed = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        elapsed.CancelAfter(TimeSpan.FromSeconds(maxElapsedSeconds));
        var trace = priorTrace?.DeepClone() as JsonArray ?? new JsonArray();
        var routes = priorProviderRouteHistory?.DeepClone() as JsonArray ?? new JsonArray();
        var decisions = priorDecisions;
        var actionsExecuted = 0;
        var rejected = 0;
        var promptTokens = priorPromptTokens;
        var completionTokens = priorCompletionTokens;
        var startDay = double.NaN;
        var renownBefore = double.NaN;
        JsonObject? initialNative = null;
        var battleResult = "unknown";
        var playerRetreated = false;
        var requestedTargetId = (string?)null;
        var observedTargets = new JsonArray();
        var mapPartyTargetsQueried = false;
        var mapConversationContinuationCount = 0;
        var battleWasStarted = false;
        var nativeEncounterLeaveIssued = false;
        string? nativeEncounterLeaveOptionId = null;
        var nativeEscapeAccepted = false;
        var nativeEscapeCompleted = false;
        var captivityObserved = false;
        string? captivityChoiceOptionId = null;
        string? blockedPartyScreenDoneFingerprint = null;
        var repeatedPartyScreenNegativeInquiryCount = 0;
        var partyScreenDoneAwaitingInquiry = false;
        JsonObject? previousReceipt = null;
        JsonObject? battleFinishReceipt = null;
        JsonObject? feedback = null;
        JsonObject? currentNative = null;
        string? failure = null;
        string? failureCode = null;
        string? termination = null;
        int processId = -1;
        var runStarted = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);

        try
        {
            await provider.CheckConfiguredModelAsync(elapsed.Token);
            using (var initial = await client.ReadStateAsync(elapsed.Token)) currentNative = ParseObject(initial.RootElement);
            processId = ReadInt(currentNative, "processId", -1);
            if (processId <= 0) throw new AgentHostException("native-process-id-invalid", "Native state did not identify its Bannerlord process.");
            initialNative = currentNative.DeepClone() as JsonObject;
            startDay = ReadDouble(currentNative, "campaignDay", double.NaN);
            renownBefore = ReadRenown(currentNative["state"] as JsonObject);

            for (var localIndex = 1; decisions < maxDecisions; localIndex++)
            {
                elapsed.Token.ThrowIfCancellationRequested();
                var iteration = priorDecisions + localIndex;
                var native = currentNative ?? throw new AgentHostException("native-observation-missing", "The Host lost its current Native observation.");
                if (ReadInt(native, "processId", -1) != processId)
                    throw new AgentHostException("native-process-changed", "Native observations switched Bannerlord processes during the BattleSimulation loop.");

                var state = native["state"] as JsonObject ?? throw new AgentHostException("native-state-missing", "The latest Native response contained no Campaign state.");
                var context = state["context"] as JsonObject ?? new JsonObject();
                var gameState = ReadString(context, "gameState");
                var menuId = ReadString(context, "menuId");
                var currentPartyScreenFingerprint = BuildPartyScreenFingerprint(state);
                if (blockedPartyScreenDoneFingerprint is not null && !string.Equals(blockedPartyScreenDoneFingerprint, currentPartyScreenFingerprint, StringComparison.Ordinal))
                {
                    blockedPartyScreenDoneFingerprint = null;
                    repeatedPartyScreenNegativeInquiryCount = 0;
                    if (ReadString(feedback, "kind") == "postbattle-party-screen-negative-needs-roster-change") feedback = null;
                }
                var isCaptive = IsPlayerCaptive(state);
                captivityObserved |= isCaptive;
                var simulation = context["battleSimulation"] as JsonObject;
                var partyScreen = state["partyScreen"] as JsonObject;
                var inventoryScreen = state["inventoryScreen"] as JsonObject;

                if (nativeEscapeCompleted)
                {
                    if (!IsVerifiedMapTerminalAfterNativeEscape(state))
                    {
                        failure = "Native Try-to-get-away Continue did not return MainHero to a free Campaign Map with an active MainParty.";
                        failureCode = "native-try-to-get-away-return-unverified";
                        termination = "native-try-to-get-away-return-unverified";
                        break;
                    }
                    var escapeRenownAfter = ReadRenown(state);
                    if (!double.IsFinite(renownBefore) || !double.IsFinite(escapeRenownAfter))
                    {
                        failure = "The Native escape returned to Map, but Renown was not readable before and after the attempt.";
                        failureCode = "battle-renown-unobservable";
                        termination = "outcome-verification-incomplete";
                        break;
                    }
                    trace.Add(new JsonObject
                    {
                        ["stage"] = "native-try-to-get-away-return-verified",
                        ["battleSimulationStarted"] = false,
                        ["playerOutcome"] = "escaped-with-sacrifice",
                        ["nativeRiskContext"] = state["context"]?["encounterEscape"]?.DeepClone(),
                        ["renownBefore"] = renownBefore,
                        ["renownAfter"] = escapeRenownAfter
                    });
                    return BuildResult(runId, provider, "completed", decisions, actionsExecuted, promptTokens, completionTokens,
                        "native-try-to-get-away-completed", null, null, startDay, initialNative, native, trace, routes,
                        renownBefore, escapeRenownAfter, "native-try-to-get-away", playerRetreated: true,
                        targetId: requestedTargetId, battleStarted: false, battleFinishReceipt: null,
                        captivityRecoveryRequested: recoverPlayerCaptivity, captivityObserved: captivityObserved,
                        captivityChoiceOptionId: captivityChoiceOptionId, nativeEscapeCompleted: true);
                }

                if (recoverPlayerCaptivity && captivityObserved && !isCaptive && !battleWasStarted &&
                    IsVerifiedMapTerminalAfterNativeEscape(state))
                {
                    var recoveryRenownAfter = ReadRenown(state);
                    if (!double.IsFinite(renownBefore) || !double.IsFinite(recoveryRenownAfter))
                    {
                        failure = "Native captivity recovery returned to a free Map without readable Renown before and after recovery.";
                        failureCode = "battle-renown-unobservable";
                        termination = "outcome-verification-incomplete";
                        break;
                    }
                    trace.Add(new JsonObject
                    {
                        ["stage"] = "native-captivity-recovered-without-battle",
                        ["battleSimulationStarted"] = false,
                        ["playerOutcome"] = "captured-then-recovered",
                        ["captivityChoiceOptionId"] = captivityChoiceOptionId,
                        ["renownBefore"] = renownBefore,
                        ["renownAfter"] = recoveryRenownAfter
                    });
                    return BuildResult(runId, provider, "completed", decisions, actionsExecuted, promptTokens, completionTokens,
                        "native-captivity-recovered-without-battle", null, null, startDay, initialNative, native, trace, routes,
                        renownBefore, recoveryRenownAfter, "native-captivity-recovery", playerRetreated: false,
                        targetId: requestedTargetId, battleStarted: false, battleFinishReceipt: null,
                        captivityRecoveryRequested: true, captivityObserved: true,
                        captivityChoiceOptionId: captivityChoiceOptionId, nativeCaptivityRecoveryWithoutBattle: true);
                }

                if (IsActiveMapIncident(native))
                {
                    failure = "A Native Map Incident opened before the battle decision; the parent EYC loop must resolve its current visible choices before resuming.";
                    failureCode = "native-map-incident-interrupted-battle-planning";
                    termination = "native-map-incident-interrupted-battle-planning";
                    trace.Add(new JsonObject
                    {
                        ["stage"] = "battle-planning-interrupted-by-native-map-incident",
                        ["iteration"] = iteration,
                        ["modelDecisionMade"] = false,
                        ["nativeActionMade"] = false,
                        ["mapIncident"] = (context["mapIncident"] as JsonObject)?.DeepClone()
                    });
                    break;
                }

                var mapConversation = context["conversation"] as JsonObject;
                var mapConversationOptions = mapConversation?["options"] as JsonArray;
                if (gameState == "MapState" && mapConversation is not null &&
                    !AgentHostCampaignStateFacts.IsActiveEncounter(state) &&
                    mapConversationOptions?.Count == 0 &&
                    !string.IsNullOrWhiteSpace(ReadString(mapConversation, "sentenceText")))
                {
                    if (mapConversationContinuationCount >= 32)
                    {
                        failure = "The active Native map conversation exceeded the bounded no-choice Continue sequence; no quest choice or clock action was invented.";
                        failureCode = "native-map-conversation-continue-limit";
                        termination = "native-map-conversation-continue-limit";
                        break;
                    }
                    var conversationCharacterId = ReadString(mapConversation, "characterId");
                    var conversationTextBefore = ReadString(mapConversation, "sentenceText");
                    var continueStartedUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                    using var continueResponse = await client.ExecuteBattleSimulationActionAsync("dialogueContinue", new JsonObject(), elapsed.Token);
                    var continueReceipt = SafeReceipt("dialogueContinue", continueResponse.RootElement);
                    if (ReadString(continueReceipt, "status") != "completed")
                    {
                        failure = "Native did not confirm its original dialogueContinue handler for the active no-choice Map conversation.";
                        failureCode = "native-map-conversation-continue-rejected";
                        termination = "native-map-conversation-continue-rejected";
                        break;
                    }
                    actionsExecuted++;
                    mapConversationContinuationCount++;
                    using var afterContinue = await client.ReadStateAsync(elapsed.Token);
                    var afterContinueNative = ParseObject(afterContinue.RootElement);
                    var afterContinueState = afterContinueNative["state"] as JsonObject;
                    var afterContinueContext = afterContinueState?["context"] as JsonObject;
                    var afterConversation = afterContinueContext?["conversation"] as JsonObject;
                    var afterOptions = afterConversation?["options"] as JsonArray;
                    if (ReadString(afterContinueContext, "gameState") != "MapState")
                    {
                        currentNative = afterContinueNative;
                        failure = "The original map dialogueContinue left MapState; this Renown subflow will not begin an unverified scene or quest route.";
                        failureCode = "native-map-conversation-left-map";
                        termination = "native-map-conversation-left-map";
                        break;
                    }
                    if (afterConversation is not null && afterOptions?.Count == 0 &&
                        ReadString(afterConversation, "characterId") == conversationCharacterId &&
                        ReadString(afterConversation, "sentenceText") == conversationTextBefore)
                    {
                        currentNative = afterContinueNative;
                        failure = "Native accepted dialogueContinue but returned the same no-choice map sentence; Host stopped without repeating it.";
                        failureCode = "native-map-conversation-continue-no-progress";
                        termination = "native-map-conversation-continue-no-progress";
                        break;
                    }
                    if (afterConversation is null || afterOptions?.Any(option => ReadBoolean(option as JsonObject, "clickable")) == true ||
                        ReadString(afterConversation, "characterId") != conversationCharacterId)
                        mapConversationContinuationCount = 0;
                    var continueCampaignDayBefore = ReadDouble(native, "campaignDay", double.NaN);
                    var continueCampaignDayAfter = ReadDouble(afterContinueNative, "campaignDay", double.NaN);
                    trace.Add(new JsonObject
                    {
                        ["stage"] = "native-map-conversation-no-choice-continued",
                        ["iteration"] = iteration,
                        ["nativeAction"] = "dialogueContinue",
                        ["nativeActionReceipt"] = continueReceipt.DeepClone(),
                        ["characterId"] = conversationCharacterId,
                        ["lineAdvancedOrConversationClosed"] = true,
                        ["campaignDayBefore"] = double.IsFinite(continueCampaignDayBefore) ? JsonValue.Create(continueCampaignDayBefore) : null,
                        ["campaignDayAfter"] = double.IsFinite(continueCampaignDayAfter) ? JsonValue.Create(continueCampaignDayAfter) : null,
                        ["timeControlModeBefore"] = ReadString(native, "timeControlMode"),
                        ["timeControlModeAfter"] = ReadString(afterContinueNative, "timeControlMode"),
                        ["modelDecisionMade"] = false
                    });
                    currentNative = afterContinueNative;
                    feedback = null;
                    previousReceipt = new JsonObject { ["action"] = "dialogueContinue", ["status"] = "completed", ["nativeChoiceRequired"] = false };
                    continue;
                }

                // Preserve the current player-visible hostile target while the model decides
                // whether to pursue it. This is a distinct Native Pause command, never folded
                // into Move/Pursue, and it is skipped while that exact target is already being
                // pursued so ordinary Native chase behavior can continue.
                if (ShouldPauseForVisibleHostileDecision(native))
                {
                    var modeBeforePause = ReadString(native, "timeControlMode");
                    var dayBeforePause = ReadDouble(native, "campaignDay", double.NaN);
                    var pauseStartedUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                    using var pauseResponse = await client.PauseForVisibleHostileDecisionAsync(elapsed.Token);
                    var pauseReceipt = SafeReceipt("pause", pauseResponse.RootElement);
                    var pauseCompletedUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                    if (ReadString(pauseReceipt, "status") == "completed") actionsExecuted++;
                    using var stateAfterPause = await client.ReadStateAsync(elapsed.Token);
                    currentNative = ParseObject(stateAfterPause.RootElement);
                    var modeAfterPause = ReadString(currentNative, "timeControlMode");
                    var dayAfterPause = ReadDouble(currentNative, "campaignDay", double.NaN);
                    trace.Add(new JsonObject
                    {
                        ["stage"] = "visible-hostile-decision-paused-before-model",
                        ["iteration"] = iteration,
                        ["nativeAction"] = "pause",
                        ["nativeActionReceipt"] = pauseReceipt.DeepClone(),
                        ["timeControlModeBefore"] = modeBeforePause,
                        ["timeControlModeAfter"] = modeAfterPause,
                        ["campaignDayBefore"] = double.IsFinite(dayBeforePause) ? JsonValue.Create(dayBeforePause) : null,
                        ["campaignDayAfter"] = double.IsFinite(dayAfterPause) ? JsonValue.Create(dayAfterPause) : null,
                        ["actionStartedUtc"] = pauseStartedUtc,
                        ["actionCompletedUtc"] = pauseCompletedUtc,
                        ["modelDecisionMade"] = false
                    });
                    if (ReadString(pauseReceipt, "status") != "completed" || modeAfterPause != "Stop")
                    {
                        failure = "A visible hostile party needs a stable decision window, but the Native Campaign Pause did not verify stopped time.";
                        failureCode = "visible-hostile-native-pause-unverified";
                        termination = "visible-hostile-native-pause-unverified";
                        break;
                    }
                    continue;
                }

                if (simulation is not null)
                {
                    battleResult = ReadString(simulation, "battleState") ?? battleResult;
                    playerRetreated = ReadBoolean(simulation, "playerRetreated");
                }

                if (ReadBoolean(context, "inquiryOpen"))
                {
                    var activeInquiryClient = inquiryClient ?? client as IAgentHostNativeInquiryClient;
                    if (activeInquiryClient == null)
                    {
                        failure = "The active Native Yes/No Inquiry interrupted BattleSimulation, but the Native Inquiry client is unavailable.";
                        failureCode = "native-inquiry-client-unavailable";
                        termination = "native-inquiry-client-unavailable";
                        break;
                    }
                    var inquiryGoal = ReadString(request, "parentGoal") ?? goal;
                    if (string.Equals(gameState, "PartyState", StringComparison.Ordinal))
                    {
                        var objectiveSnapshot = request.TryGetProperty("parentEycObjectives", out var objectiveElement) && objectiveElement.ValueKind == JsonValueKind.Object
                            ? JsonNode.Parse(objectiveElement.GetRawText())?.ToJsonString() ?? "unavailable"
                            : "unavailable";
                        inquiryGoal = "Overall user goal: " + inquiryGoal + ". Current Battle subgoal: " + goal + ". Current original EYC Journal objectives: " + objectiveSnapshot + ". Resolve the current post-battle Native confirmation according to those goals and the exact current PartyState roster; do not assume friendly or neutral survivors are bandit prisoners. The model must choose the current visible affirmative/negative option, or return to the Native PartyScreen only if its current buttons make that appropriate.";
                        if (partyScreenDoneAwaitingInquiry)
                            inquiryGoal += " A Native partyScreenDone just opened this prompt. If you choose negative, the same PartyScreen draft returns. Do not create a negative/Done cycle: after declining, transfer a currently listed roster row that advances an unmet Journal objective before trying Done again. If no useful transfer is available, decide from the current objective whether to accept leaving the remaining troops or stop safely.";
                    }
                    var inquiry = await AgentHostNativeInquiryResolution.RunAsync(
                        client, activeInquiryClient, provider, elapsed.Token,
                        runId + "-battle-inquiry-" + (decisions + 1).ToString(CultureInfo.InvariantCulture), inquiryGoal);
                    decisions += ReadInt(inquiry, "decisions", 0);
                    actionsExecuted += ReadInt(inquiry, "actionsExecuted", 0);
                    promptTokens += ReadLong(inquiry, "promptTokens", 0);
                    completionTokens += ReadLong(inquiry, "completionTokens", 0);
                    if (inquiry["providerRouteHistory"] is JsonArray inquiryRoutes)
                        foreach (var route in inquiryRoutes) routes.Add(route?.DeepClone());
                    trace.Add(new JsonObject
                    {
                        ["stage"] = "postbattle-native-inquiry",
                        ["gameState"] = gameState,
                        ["status"] = ReadString(inquiry, "status"),
                        ["choice"] = ReadString(inquiry, "choice"),
                        ["decision"] = inquiry["decision"]?.DeepClone(),
                        ["nativeReceipt"] = inquiry["nativeReceipt"]?.DeepClone(),
                        ["nativeStateAfter"] = inquiry["nativeStateAfter"]?.DeepClone()
                    });
                    if (ReadString(inquiry, "status") != "resolved")
                    {
                        failure = ReadString(inquiry, "failure") ?? "The post-battle Native Inquiry did not close successfully.";
                        failureCode = ReadString(inquiry, "failureCode") ?? "postbattle-native-inquiry-unresolved";
                        termination = "postbattle-native-inquiry-unresolved";
                        break;
                    }
                    using var afterInquiry = await client.ReadStateAsync(elapsed.Token);
                    currentNative = ParseObject(afterInquiry.RootElement);
                    var selectedInquiryChoice = ReadString(inquiry, "choice");
                    var afterInquiryState = currentNative["state"] as JsonObject;
                    var afterInquiryContext = afterInquiryState?["context"] as JsonObject;
                    if (afterInquiryState is not null && partyScreenDoneAwaitingInquiry && parentPartySizeObjectiveUnmet && gameState == "PartyState" && selectedInquiryChoice == "negative" &&
                        ReadString(afterInquiryContext, "gameState") == "PartyState")
                    {
                        var afterFingerprint = BuildPartyScreenFingerprint(afterInquiryState);
                        if (afterFingerprint is not null)
                        {
                            repeatedPartyScreenNegativeInquiryCount = string.Equals(blockedPartyScreenDoneFingerprint, afterFingerprint, StringComparison.Ordinal)
                                ? repeatedPartyScreenNegativeInquiryCount + 1
                                : 1;
                            blockedPartyScreenDoneFingerprint = afterFingerprint;
                            feedback = new JsonObject
                            {
                                ["kind"] = "postbattle-party-screen-negative-needs-roster-change",
                                ["requiredNextStep"] = "The current negative response returned to the unchanged Native PartyScreen. Choose a listed partyTakeAll or partyLootTransferOne that advances an unmet Journal objective before selecting Done again; do not repeat the same negative/Done sequence."
                            };
                            var currentPartyCatalog = BuildActionCatalog(afterInquiryState, observedTargets, requestedTargetId, battleWasStarted,
                                mapPartyTargetsQueried, recoverPlayerCaptivity);
                            var hasRosterTransfer = HasPartyScreenTransferAction(currentPartyCatalog);
                            if (!hasRosterTransfer && repeatedPartyScreenNegativeInquiryCount >= 2)
                            {
                                failure = "The same Native PartyScreen Inquiry was declined twice without a transferable roster action or state change; the loop stopped without replaying another Done or Inquiry.";
                                failureCode = "party-screen-inquiry-negative-no-progress";
                                termination = "party-screen-inquiry-no-progress";
                                break;
                            }
                        }
                    }
                    partyScreenDoneAwaitingInquiry = false;
                    continue;
                }

                if (nativeEncounterLeaveIssued)
                {
                    if (IsVerifiedMapTerminalAfterNativeEncounterLeave(state))
                    {
                        var renownAfterLeave = ReadRenown(state);
                        var leaveTraceStep = BuildDeferredPartyTargetTraceStep(
                            requestedTargetId ?? ReadString(state["context"] as JsonObject, "encounteredPartyId"), observedTargets, state);
                        leaveTraceStep["nativeAction"] = "menuSelect";
                        leaveTraceStep["optionId"] = nativeEncounterLeaveOptionId;
                        leaveTraceStep["battleSimulationStarted"] = false;
                        leaveTraceStep["campaignDayAfter"] = native["campaignDay"]?.DeepClone();
                        leaveTraceStep["timeControlModeAfter"] = native["timeControlMode"]?.DeepClone();
                        leaveTraceStep["renownBefore"] = double.IsFinite(renownBefore) ? JsonValue.Create(renownBefore) : null;
                        leaveTraceStep["renownAfter"] = double.IsFinite(renownAfterLeave) ? JsonValue.Create(renownAfterLeave) : null;
                        leaveTraceStep["playerCaptiveAfter"] = IsPlayerCaptive(state);
                        trace.Add(leaveTraceStep);
                        return BuildResult(runId, provider, "interrupted", decisions, actionsExecuted, promptTokens, completionTokens,
                            "native-encounter-left-no-battle", "Native Leave closed the encounter without BattleSimulation; no victory or Renown gain is claimed.",
                            "native-encounter-left-no-battle", startDay, initialNative, native, trace, routes, renownBefore, renownAfterLeave,
                            battleResult, playerRetreated, requestedTargetId, battleWasStarted, battleFinishReceipt,
                            recoverPlayerCaptivity, captivityObserved, captivityChoiceOptionId, nativeEncounterLeft: true);
                    }
                    failure = "The current Native Leave action completed, but its fresh state did not verify an encounter-free Campaign Map or a prisoner wait menu.";
                    failureCode = "native-encounter-leave-return-unverified";
                    termination = "native-encounter-leave-return-unverified";
                    break;
                }

                if (ShouldPassivelyWaitForCaptivity(state, recoverPlayerCaptivity))
                {
                    var boundedCaptivityPollSeconds = Math.Clamp(passiveCaptivityPollSeconds, 1, 15);
                    var campaignDayBeforeWait = ReadDouble(native, "campaignDay", double.NaN);
                    await Task.Delay(TimeSpan.FromSeconds(boundedCaptivityPollSeconds), elapsed.Token);
                    using var captivityWaitState = await client.ReadStateAsync(elapsed.Token);
                    currentNative = ParseObject(captivityWaitState.RootElement);
                    var afterWaitState = currentNative["state"] as JsonObject;
                    var afterWaitContext = afterWaitState?["context"] as JsonObject;
                    captivityObserved |= IsPlayerCaptive(afterWaitState);
                    trace.Add(new JsonObject
                    {
                        ["stage"] = "captivity-passive-wait",
                        ["iteration"] = priorDecisions + localIndex,
                        ["waitSeconds"] = boundedCaptivityPollSeconds,
                        ["menuBefore"] = menuId,
                        ["menuAfter"] = ReadString(afterWaitContext, "menuId"),
                        ["campaignDayBefore"] = double.IsFinite(campaignDayBeforeWait) ? JsonValue.Create(campaignDayBeforeWait) : null,
                        ["campaignDayAfter"] = currentNative["campaignDay"]?.DeepClone(),
                        ["isCaptiveAfter"] = IsPlayerCaptive(afterWaitState)
                    });
                    feedback = null;
                    continue;
                }

                if (IsVerifiedMapTerminalAfterBattle(state, battleWasStarted) && !(recoverPlayerCaptivity && isCaptive))
                {
                    var renownAfterFinal = ReadRenown(state);
                    if (!double.IsFinite(renownBefore) || !double.IsFinite(renownAfterFinal))
                    {
                        failure = "The resolved encounter returned to Map, but Native Renown was not readable before and after the battle.";
                        failureCode = "battle-renown-unobservable";
                        termination = "outcome-verification-incomplete";
                        break;
                    }
                    var observation = BuildObservation(native, observedTargets, requestedTargetId, battleWasStarted, battleResult, playerRetreated, renownBefore, renownAfterFinal);
                    var doneControls = new JsonArray("done");
                    var modelRequest = BuildDecisionRequest(runId, iteration, goal, observation, previousReceipt, feedback, new JsonArray(), doneControls);
                    var decisionStart = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                    var decisionTicks = Stopwatch.GetTimestamp();
                    var providerResult = recoverPlayerCaptivity
                        ? await AgentHostDecisionCycle.DecideBattleAndCaptivityAsync(provider, modelRequest, elapsed.Token)
                        : await AgentHostDecisionCycle.DecideBattleSimulationAsync(provider, modelRequest, elapsed.Token);
                    var doneProviderCompletedUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                    decisions++;
                    AddRoute(routes, provider, providerResult, decisions, ref promptTokens, ref completionTokens);
                    var doneDecision = providerResult.Decision;
                    if (ReadBoolean(doneDecision, "done"))
                    {
                        termination = recoverPlayerCaptivity ? "battle-and-captivity-resolved-and-verified" : "battle-resolved-and-verified";
                        trace.Add(BuildTraceStep(iteration, decisionStart, modelRequest, doneDecision, null, previousReceipt, null, providerCompletedUtc: doneProviderCompletedUtc));
                        return BuildResult(runId, provider, "completed", decisions, actionsExecuted, promptTokens, completionTokens,
                            termination, null, null, startDay, initialNative, native, trace, routes, renownBefore, renownAfterFinal, battleResult, playerRetreated, requestedTargetId, battleWasStarted, battleFinishReceipt,
                            recoverPlayerCaptivity, captivityObserved, captivityChoiceOptionId);
                    }
                    failure = "The model did not accept the Native result verification even though only done was listed.";
                    failureCode = "battle-done-not-accepted";
                    termination = "outcome-verification-incomplete";
                    trace.Add(BuildTraceStep(iteration, decisionStart, modelRequest, doneDecision, null, previousReceipt, null, providerCompletedUtc: doneProviderCompletedUtc));
                    break;
                }

                var deferredPartyTargetIds = BuildDeferredPartyTargetIds(trace, state, observedTargets);
                var catalog = BuildActionCatalog(state, observedTargets, requestedTargetId, battleWasStarted, mapPartyTargetsQueried,
                    recoverPlayerCaptivity, deferredPartyTargetIds);
                var partyScreenDoneSuppressed = false;
                if (parentPartySizeObjectiveUnmet && blockedPartyScreenDoneFingerprint is not null &&
                    string.Equals(blockedPartyScreenDoneFingerprint, currentPartyScreenFingerprint, StringComparison.Ordinal) &&
                    HasPartyScreenTransferAction(catalog))
                {
                    var doneIndex = catalog.IndexOf(catalog.OfType<JsonObject>().FirstOrDefault(action => ReadString(action, "action") == "partyScreenDone"));
                    if (doneIndex >= 0)
                    {
                        catalog.RemoveAt(doneIndex);
                        partyScreenDoneSuppressed = true;
                        feedback = new JsonObject
                        {
                            ["kind"] = "postbattle-party-screen-negative-needs-roster-change",
                            ["requiredNextStep"] = "Done is temporarily unavailable because the previous negative Inquiry returned the unchanged roster. Choose a currently listed partyTakeAll or partyLootTransferOne that advances an unmet Journal objective."
                        };
                    }
                }
                var controls = BuildControlCatalog(state, requestedTargetId, battleWasStarted, recoverPlayerCaptivity);
                if (catalog.Count == 0 && controls.Count == 0)
                {
                    failure = recoverPlayerCaptivity && isCaptive
                        ? "The Native captivity menu has no currently enabled action supported by this bounded recovery loop; no choice or clock change was made."
                        : ExplainNoAction(state, battleWasStarted, observedTargets);
                    termination = "no-safe-action";
                    break;
                }

                var renownNow = ReadRenown(state);
                var observationNow = BuildObservation(native, observedTargets, requestedTargetId, battleWasStarted, battleResult, playerRetreated, renownBefore, renownNow);
                var requestNow = BuildDecisionRequest(runId, iteration, goal, observationNow, previousReceipt, feedback, catalog, controls);
                var providerStarted = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                var providerTicks = Stopwatch.GetTimestamp();
                ProviderDecisionResult result;
                string providerCompletedUtc;
                try
                {
                    result = recoverPlayerCaptivity
                        ? await AgentHostDecisionCycle.DecideBattleAndCaptivityAsync(provider, requestNow, elapsed.Token)
                        : await AgentHostDecisionCycle.DecideBattleSimulationAsync(provider, requestNow, elapsed.Token);
                    providerCompletedUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                    decisions++;
                    AddRoute(routes, provider, result, decisions, ref promptTokens, ref completionTokens);
                }
                catch (AgentHostException exception) when (IsRecoverableProviderError(exception.Code) && rejected < MaxRejectedDecisions)
                {
                    decisions++;
                    rejected++;
                    feedback = new JsonObject
                    {
                        ["kind"] = "decision-rejected-before-native",
                        ["code"] = exception.Code,
                        ["message"] = exception.Message,
                        ["requiredNextStep"] = exception.Code == "provider-arguments-invalid-json"
                            ? "Return arguments as a JSON object using exactly the listed names and latest observed IDs."
                            : "Choose exactly one action or control from the latest catalog; do not repeat the rejected response."
                    };
                    var providerErrorCompletedUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                    trace.Add(BuildTraceStep(iteration, providerStarted, requestNow, null, feedback, previousReceipt, null, providerCompletedUtc: providerErrorCompletedUtc));
                    continue;
                }

                var decision = result.Decision;
                if (!TryResolveDecision(decision, catalog, controls, state, observedTargets, requestedTargetId,
                        out var action, out var arguments, out var waitSeconds, out var rejection, recoverPlayerCaptivity))
                {
                    if (partyScreenDoneSuppressed && action == "partyScreenDone")
                        rejection = "The current PartyScreen roster is unchanged after a negative Inquiry. Choose a listed roster transfer before Done; do not repeat the same negative/Done sequence.";
                    rejected++;
                    feedback = new JsonObject
                    {
                        ["kind"] = "decision-rejected-before-native",
                        ["code"] = "battle-decision-not-listed",
                        ["message"] = rejection,
                        ["nativeActionSent"] = false,
                        ["requiredNextStep"] = rejection
                    };
                    trace.Add(BuildTraceStep(iteration, providerStarted, requestNow, decision, feedback, previousReceipt, null, providerCompletedUtc: DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture)));
                    if (rejected > MaxRejectedDecisions)
                    {
                        failure = "The model exceeded the bounded Native precondition rejection allowance.";
                        failureCode = "battle-rejection-limit";
                        termination = "rejection-limit";
                        break;
                    }
                    continue;
                }

                if (action is null)
                {
                    if (waitSeconds is null)
                    {
                        failure = "No executable action or bounded re-observation control was selected.";
                        termination = "invalid-decision";
                        break;
                    }
                    await Task.Delay(TimeSpan.FromSeconds(waitSeconds.Value), elapsed.Token);
                    rejected = 0;
                    var schedulerWaitCompletedUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                    using var waited = await client.ReadStateAsync(elapsed.Token);
                    currentNative = ParseObject(waited.RootElement);
                    feedback = null;
                    var observationCompletedUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                    trace.Add(BuildTraceStep(iteration, providerStarted, requestNow, decision, null, previousReceipt, currentNative,
                        BuildObserveControl(waitSeconds.Value), actionExecuted: false,
                        providerCompletedUtc: providerCompletedUtc, observationCompletedUtc: observationCompletedUtc,
                        schedulerWaitCompletedUtc: schedulerWaitCompletedUtc));
                    continue;
                }

                JsonObject receipt;
                var actionStartedUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                partyScreenDoneAwaitingInquiry = false;
                try
                {
                    using var actionResponse = await client.ExecuteBattleSimulationActionAsync(action, arguments!, elapsed.Token);
                    if (ReadInt(actionResponse.RootElement, "processId", -1) != processId)
                        throw new AgentHostException("native-process-mismatch", "Native action response came from a different Bannerlord process.");
                    receipt = SafeReceipt(action, actionResponse.RootElement);
                }
                catch (AgentHostException exception) when (exception.Code == "native-command-timeout")
                {
                    failure = "Native action timed out with an ambiguous result; the non-idempotent action was not replayed.";
                    failureCode = exception.Code;
                    termination = "native-action-result-ambiguous";
                    var actionTimeoutUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                    trace.Add(BuildTraceStep(iteration, providerStarted, requestNow, decision, null,
                        new JsonObject { ["action"] = action, ["status"] = "timeout-ambiguous" }, null,
                        providerCompletedUtc: providerCompletedUtc, actionStartedUtc: actionStartedUtc, actionCompletedUtc: actionTimeoutUtc));
                    break;
                }

                var nativeActionStatus = ReadString(receipt, "status");
                var completed = nativeActionStatus == "completed";
                var accepted = nativeActionStatus == "accepted";
                if (completed || accepted) actionsExecuted++;
                if (action == "mapPartyTargets")
                {
                    observedTargets = CloneArray(receipt["data"]?["mapPartyTargets"] as JsonArray);
                    mapPartyTargetsQueried = true;
                    if (AgentHostCampaignStateFacts.IsActiveEncounter(state))
                    {
                        var encounteredId = ReadString(state["context"] as JsonObject, "encounteredPartyId");
                        if (observedTargets.OfType<JsonObject>().Any(x => ReadString(x, "id") == encounteredId && ReadString(x, "type") == "bandit" && ReadBoolean(x, "hostile")))
                            requestedTargetId = encounteredId;
                    }
                    else requestedTargetId = null;
                }
                else if (action == "pursue")
                {
                    requestedTargetId = ReadString(arguments, "partyId");
                    observedTargets = new JsonArray();
                    mapPartyTargetsQueried = false;
                }
                else if (completed && action == "menuSelect" && string.Equals(ReadString(arguments, "optionId"), "str_order_attack", StringComparison.Ordinal))
                {
                    battleWasStarted = true;
                }
                else if (completed && action == "menuSelect" && !battleWasStarted &&
                         IsNativeEncounterLeaveSelection(state, arguments!))
                {
                    nativeEncounterLeaveIssued = true;
                    nativeEncounterLeaveOptionId = ReadString(arguments, "optionId");
                }
                else if (completed && action == "menuSelect" &&
                         string.Equals(ReadString((state["context"] as JsonObject), "menuId"), "try_to_get_away", StringComparison.Ordinal))
                {
                    var selectedOptionId = ReadString(arguments, "optionId");
                    nativeEscapeAccepted = selectedOptionId == "try_to_get_away_accept";
                    if (selectedOptionId == "try_to_get_away_reject")
                        playerRetreated = false;
                }
                else if (completed && action == "menuSelect" &&
                         string.Equals(ReadString((state["context"] as JsonObject), "menuId"), "try_to_get_away_debrief", StringComparison.Ordinal) &&
                         string.Equals(ReadString(arguments, "optionId"), "try_to_get_away_continue", StringComparison.Ordinal) &&
                         nativeEscapeAccepted)
                {
                    nativeEscapeCompleted = true;
                    playerRetreated = true;
                    battleResult = "native-try-to-get-away";
                }
                else if (completed && action == "battleSkip")
                {
                    battleWasStarted = true;
                    var contextAfterSkip = state["context"] as JsonObject;
                    var simAfterSkip = contextAfterSkip?["battleSimulation"] as JsonObject;
                    battleResult = ReadString(simAfterSkip, "battleState") ?? "simulation-skipped";
                    playerRetreated = ReadBoolean(simAfterSkip, "playerRetreated");
                }
                else if (completed && action == "battleFinish")
                {
                    battleWasStarted = true;
                    battleFinishReceipt = receipt.DeepClone() as JsonObject;
                    var simBeforeFinish = (state["context"] as JsonObject)?["battleSimulation"] as JsonObject;
                    battleResult = ReadString(simBeforeFinish, "battleState") ?? battleResult;
                    playerRetreated = ReadBoolean(simBeforeFinish, "playerRetreated");
                }
                else if (completed && action == "menuSelect" && recoverPlayerCaptivity && IsPlayerCaptive(state))
                {
                    captivityChoiceOptionId = ReadString(arguments, "optionId");
                }

                var actionCompletedUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                previousReceipt = receipt;
                using (var refreshed = await client.ReadStateAsync(elapsed.Token)) currentNative = ParseObject(refreshed.RootElement);
                if (action == "partyScreenDone")
                {
                    var refreshedContext = (currentNative["state"] as JsonObject)?["context"] as JsonObject;
                    partyScreenDoneAwaitingInquiry = accepted && ReadString(refreshedContext, "gameState") == "PartyState" && ReadBoolean(refreshedContext, "inquiryOpen");
                }
                else if (action is "partyTakeAll" or "partyLootTransferOne")
                {
                    var refreshedScreen = BuildPartyScreenFingerprint(currentNative["state"] as JsonObject);
                    if (!string.Equals(blockedPartyScreenDoneFingerprint, refreshedScreen, StringComparison.Ordinal))
                    {
                        blockedPartyScreenDoneFingerprint = null;
                        repeatedPartyScreenNegativeInquiryCount = 0;
                    }
                }
                var observationCompleted = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                feedback = completed ? null : new JsonObject { ["kind"] = "native-action-rejected", ["action"] = action, ["receipt"] = receipt.DeepClone() };
                trace.Add(BuildTraceStep(iteration, providerStarted, requestNow, decision, feedback, receipt, currentNative,
                    actionExecuted: completed, providerCompletedUtc: providerCompletedUtc, actionStartedUtc: actionStartedUtc,
                    actionCompletedUtc: actionCompletedUtc, observationCompletedUtc: observationCompleted));
                if (completed || accepted) rejected = 0;
                else if (++rejected > MaxRejectedDecisions)
                {
                    failure = "Native rejected more than the bounded action allowance.";
                    failureCode = "native-rejection-limit";
                    termination = "native-rejection-limit";
                    break;
                }
            }

            if (termination is null)
            {
                failure = "The Host exhausted its bounded decision budget before a Native BattleSimulation aftermath and return to Map were verified.";
                termination = "decision-budget-exhausted";
            }
        }
        catch (OperationCanceledException)
        {
            failure = cancellationToken.IsCancellationRequested ? "Host stop was requested; no action was replayed." : "The bounded BattleSimulation loop exceeded its elapsed-time limit.";
            termination = cancellationToken.IsCancellationRequested ? "host-stop-requested" : "battle-simulation-loop-timeout";
        }
        catch (Exception exception)
        {
            failure = exception is AgentHostException host ? host.Message : exception.GetType().Name;
            failureCode = exception is AgentHostException typed ? typed.Code : null;
            termination = "battle-simulation-loop-failed";
            trace.Add(new JsonObject { ["stage"] = "loop-failed", ["failure"] = failure, ["detail"] = Truncate(exception.Message, 500) });
        }

        var renownAfter = currentNative is null ? double.NaN : ReadRenown(currentNative["state"] as JsonObject);
        return BuildResult(runId, provider, "failed", decisions, actionsExecuted, promptTokens, completionTokens,
            termination ?? "battle-simulation-loop-failed", failure, failureCode, startDay, initialNative, currentNative, trace, routes,
            renownBefore, renownAfter, battleResult, playerRetreated, requestedTargetId, battleWasStarted, battleFinishReceipt,
            recoverPlayerCaptivity, captivityObserved, captivityChoiceOptionId);
    }

    internal static HashSet<string> BuildDeferredPartyTargetIds(JsonArray priorTrace, JsonObject state, JsonArray observedTargets)
    {
        var currentPlayerFingerprint = BuildPartyStrengthFingerprint(state);
        if (currentPlayerFingerprint is null) return new HashSet<string>(StringComparer.Ordinal);

        var currentTargetMembers = observedTargets.OfType<JsonObject>()
            .Where(target => ReadString(target, "type") == "bandit" && ReadBoolean(target, "hostile"))
            .Where(target => !string.IsNullOrWhiteSpace(ReadString(target, "id")))
            .ToDictionary(target => ReadString(target, "id")!, target => ReadInt(target, "members", -1), StringComparer.Ordinal);

        var deferred = new HashSet<string>(StringComparer.Ordinal);
        foreach (var attempt in priorTrace.OfType<JsonObject>())
        {
            if (ReadString(attempt, "stage") != "native-encounter-left-without-battlesimulation") continue;
            var targetId = ReadString(attempt, "targetPartyId");
            if (string.IsNullOrWhiteSpace(targetId) || !currentTargetMembers.TryGetValue(targetId, out var currentTargetCount)) continue;
            if (!string.Equals(ReadString(attempt, "playerPartyFingerprint"), currentPlayerFingerprint, StringComparison.Ordinal)) continue;

            var previousTargetCount = ReadInt(attempt, "targetPartyMembers", -1);
            if (previousTargetCount < 0 || currentTargetCount < 0 || previousTargetCount == currentTargetCount)
                deferred.Add(targetId);
        }
        return deferred;
    }

    internal static JsonObject BuildDeferredPartyTargetTraceStep(string? targetPartyId, JsonArray observedTargets, JsonObject state)
    {
        return new JsonObject
        {
            ["stage"] = "native-encounter-left-without-battlesimulation",
            ["targetPartyId"] = targetPartyId,
            ["targetPartyMembers"] = ReadObservedTargetMembers(observedTargets, targetPartyId),
            ["playerPartyFingerprint"] = BuildPartyStrengthFingerprint(state)
        };
    }

    private static int? ReadObservedTargetMembers(JsonArray observedTargets, string? targetId)
    {
        if (string.IsNullOrWhiteSpace(targetId)) return null;
        var target = observedTargets.OfType<JsonObject>().FirstOrDefault(item => ReadString(item, "id") == targetId);
        if (target is null) return null;
        var members = ReadInt(target, "members", -1);
        return members >= 0 ? members : null;
    }

    private static string? BuildPartyStrengthFingerprint(JsonObject state)
    {
        var party = state["party"] as JsonObject;
        if (party is null) return null;
        var members = ReadInt(party, "members", -1);
        var healthy = ReadInt(party, "healthy", -1);
        var wounded = ReadInt(party, "wounded", -1);
        var prisoners = ReadInt(party, "prisoners", -1);
        if (members < 0 && healthy < 0 && wounded < 0 && prisoners < 0) return null;
        return string.Join("|", members.ToString(CultureInfo.InvariantCulture), healthy.ToString(CultureInfo.InvariantCulture),
            wounded.ToString(CultureInfo.InvariantCulture), prisoners.ToString(CultureInfo.InvariantCulture));
    }

    internal static JsonArray BuildActionCatalog(JsonObject state, JsonArray observedTargets, string? targetId, bool battleWasStarted,
        bool mapPartyTargetsQueried, bool recoverPlayerCaptivity = false, ISet<string>? deferredPartyTargetIds = null)
    {
        var catalog = new JsonArray();
        var context = state["context"] as JsonObject ?? new JsonObject();
        var gameState = ReadString(context, "gameState");
        var simulation = context["battleSimulation"] as JsonObject;
        var partyScreen = state["partyScreen"] as JsonObject;
        var inventoryScreen = state["inventoryScreen"] as JsonObject;

        if (string.Equals(gameState, "MapState", StringComparison.Ordinal))
        {
            if (recoverPlayerCaptivity && IsPlayerCaptive(state))
            {
                if (IsSupportedCaptivityRansomMenu(ReadString(context, "menuId")) &&
                    HasEnabledCaptivityRansomOption(state))
                    Add(catalog, "menuSelect", "MenuId", "OptionId");
                return catalog;
            }
            if (simulation is not null)
            {
                if (!battleWasStarted && !IsObservedEncounterBandit(state, observedTargets))
                {
                    if (!mapPartyTargetsQueried) Add(catalog, "mapPartyTargets");
                    return catalog;
                }
                if (ReadBoolean(simulation, "finished")) Add(catalog, "battleFinish");
                else Add(catalog, "battleSkip");
                return catalog;
            }
            if (AgentHostCampaignStateFacts.IsNativeLocationMenu(state))
            {
                var menuId = ReadString(context, "menuId");
                var leaveOptionIds = (state["availableMenuOptions"] as JsonArray)?.OfType<JsonObject>()
                    .FirstOrDefault(option => ReadBoolean(option, "available") && ReadBoolean(option, "enabled") && ReadBoolean(option, "isLeave"));
                if (menuId is not null && leaveOptionIds is not null)
                {
                    var enabledLeaveIds = (state["availableMenuOptions"] as JsonArray)?.OfType<JsonObject>()
                        .Where(option => ReadBoolean(option, "available") && ReadBoolean(option, "enabled") && ReadBoolean(option, "isLeave"))
                        .Select(option => ReadString(option, "id"))
                        .Where(id => !string.IsNullOrWhiteSpace(id)).Distinct(StringComparer.Ordinal).ToArray() ?? Array.Empty<string>();
                    catalog.Add(new JsonObject
                    {
                        ["action"] = "menuSelect",
                        ["arguments"] = new JsonArray("MenuId", "OptionId"),
                        ["argumentValues"] = new JsonObject
                        {
                            ["MenuId"] = new JsonArray(menuId),
                            ["OptionId"] = new JsonArray(enabledLeaveIds.Select(id => (JsonNode?)JsonValue.Create(id)).ToArray())
                        }
                    });
                }
                return catalog;
            }
            if (AgentHostCampaignStateFacts.IsActiveEncounter(state))
            {
                var encounterMenuId = ReadString(context, "menuId");
                if (encounterMenuId == "try_to_get_away")
                {
                    AddNativeMenuSelectAction(catalog, encounterMenuId,
                        new[] { "try_to_get_away_accept", "try_to_get_away_reject" }
                            .Where(optionId => CurrentEnabledMenuOption(state, optionId)));
                    return catalog;
                }
                if (encounterMenuId == "try_to_get_away_debrief")
                {
                    AddNativeMenuSelectAction(catalog, encounterMenuId,
                        new[] { "try_to_get_away_continue" }
                            .Where(optionId => CurrentEnabledMenuOption(state, optionId)));
                    return catalog;
                }
                var encounteredId = ReadString(context, "encounteredPartyId");
                var validBandit = observedTargets.OfType<JsonObject>().Any(x =>
                    ReadString(x, "id") == encounteredId && ReadString(x, "type") == "bandit" && ReadBoolean(x, "hostile"));
                if (!validBandit)
                {
                    if (!mapPartyTargetsQueried) Add(catalog, "mapPartyTargets");
                    return catalog;
                }
                if (encounterMenuId == "join_encounter")
                {
                    var joinEncounterOptionIds = new[]
                    {
                        "join_encounter_help_attackers", "join_encounter_help_defenders",
                        "join_encounter_abandon", "join_encounter_leave"
                    }.Where(optionId => CurrentEnabledMenuOption(state, optionId));
                    AddNativeMenuSelectAction(catalog, encounterMenuId, joinEncounterOptionIds);
                    return catalog;
                }
                var conversation = context["conversation"] as JsonObject;
                if (conversation is not null)
                {
                    var clickable = (conversation["options"] as JsonArray)?.OfType<JsonObject>().Where(x => ReadBoolean(x, "clickable")).ToArray() ?? Array.Empty<JsonObject>();
                    var hasFightResponse = clickable.Any(option => ReadString(option, "id") == "bandit_start_defender_1");
                    var canUseWeakPartySurrender = recoverPlayerCaptivity && !hasFightResponse && clickable.Any(option =>
                        ReadString(option, "id") == "bandit_start_defender_3" && ReadString(option, "textId") == WeakPartySurrenderResponseTextId);
                    var allowedEncounterOptions = clickable
                        .Select(x => ReadString(x, "id"))
                        .Where(id => id is "bandit_start_defender_1" or "common_encounter_ultimatum" or "common_bandit_surrender_declined" ||
                                     canUseWeakPartySurrender && id == "bandit_start_defender_3")
                        .Distinct(StringComparer.Ordinal)
                        .ToArray();
                    if (allowedEncounterOptions.Length > 0)
                    {
                        catalog.Add(new JsonObject
                        {
                            ["action"] = "dialogueSelect",
                            ["arguments"] = new JsonArray("OptionId"),
                            ["argumentValues"] = new JsonObject
                            {
                                ["OptionId"] = new JsonArray(allowedEncounterOptions.Select(id => (JsonNode?)JsonValue.Create(id)).ToArray())
                            }
                        });
                    }
                    else if (clickable.Length == 0 && !string.IsNullOrWhiteSpace(ReadString(conversation, "sentenceText")))
                        Add(catalog, "dialogueContinue");
                    return catalog;
                }
                if (validBandit && string.Equals(ReadString(context, "menuId"), "encounter", StringComparison.Ordinal))
                {
                    if (battleWasStarted) return catalog;
                    var encounterOptions = new[] { "str_order_attack", "leave_soldiers_behind", "leave" }
                        .Where(optionId => CurrentEnabledMenuOption(state, optionId)).ToArray();
                    if (encounterOptions.Length > 0)
                        AddNativeMenuSelectAction(catalog, "encounter", encounterOptions);
                    else if (recoverPlayerCaptivity && CurrentEnabledMenuOption(state, "surrender"))
                        AddNativeMenuSelectAction(catalog, "encounter", ["surrender"]);
                }
                return catalog;
            }

            var mapConversation = context["conversation"] as JsonObject;
            if (mapConversation is not null)
            {
                var clickableMapOptions = (mapConversation["options"] as JsonArray)?.OfType<JsonObject>()
                    .Where(option => ReadBoolean(option, "clickable"))
                    .Select(option => ReadString(option, "id"))
                    .Where(id => !string.IsNullOrWhiteSpace(id))
                    .Distinct(StringComparer.Ordinal)
                    .ToArray() ?? Array.Empty<string>();
                if (clickableMapOptions.Length > 0)
                {
                    catalog.Add(new JsonObject
                    {
                        ["action"] = "dialogueSelect",
                        ["arguments"] = new JsonArray("OptionId"),
                        ["argumentValues"] = new JsonObject
                        {
                            ["OptionId"] = new JsonArray(clickableMapOptions.Select(id => (JsonNode?)JsonValue.Create(id)).ToArray())
                        }
                    });
                }
                else if (!string.IsNullOrWhiteSpace(ReadString(mapConversation, "sentenceText")))
                    Add(catalog, "dialogueContinue");
                return catalog;
            }

            if (!string.IsNullOrWhiteSpace(ReadString(context, "menuId")) || ReadBoolean(context, "escapeMenuOpen") || ReadBoolean(context, "inquiryOpen") ||
                !string.IsNullOrWhiteSpace(ReadString(state["location"] as JsonObject, "currentSettlementId")))
                return catalog;

            var location = state["location"] as JsonObject;
            var activeTarget = ReadString(location, "targetPartyId");
            if (!string.IsNullOrWhiteSpace(targetId) && string.Equals(targetId, activeTarget, StringComparison.Ordinal))
                return catalog;
            if (!string.IsNullOrWhiteSpace(activeTarget)) return catalog;
            var visibleBandits = observedTargets.OfType<JsonObject>().Any(x => ReadString(x, "type") == "bandit" && ReadBoolean(x, "hostile") &&
                !string.IsNullOrWhiteSpace(ReadString(x, "id")) && deferredPartyTargetIds?.Contains(ReadString(x, "id")!) != true);
            if (visibleBandits)
                Add(catalog, "pursue", "PartyId");
            else if (!mapPartyTargetsQueried)
                Add(catalog, "mapPartyTargets");
            return catalog;
        }

        if (battleWasStarted && string.Equals(gameState, "PartyState", StringComparison.Ordinal) && partyScreen is not null && ReadString(partyScreen, "mode") == "Loot")
        {
            var transferPairs = BuildLootTransferPairs(partyScreen);
            if (transferPairs.Count > 0)
                catalog.Add(new JsonObject
                {
                    ["action"] = "partyLootTransferOne",
                    ["arguments"] = new JsonArray("TroopId", "TroopType"),
                    ["argumentPairs"] = transferPairs
                });

            var lootTypes = new JsonArray();
            if (CanTakeWholeRoster(partyScreen, "members")) lootTypes.Add("members");
            if (CanTakeWholeRoster(partyScreen, "prisoners")) lootTypes.Add("prisoners");
            if (lootTypes.Count > 0)
                catalog.Add(new JsonObject
                {
                    ["action"] = "partyTakeAll",
                    ["arguments"] = new JsonArray("TroopType"),
                    ["argumentValues"] = new JsonObject { ["TroopType"] = lootTypes }
                });
            if (ReadBoolean(partyScreen, "canDone")) Add(catalog, "partyScreenDone");
            return catalog;
        }

        if (battleWasStarted && string.Equals(gameState, "InventoryState", StringComparison.Ordinal) && inventoryScreen is not null && ReadString(inventoryScreen, "mode") == "Loot")
        {
            if (ReadInt(inventoryScreen, "lootItemCount", 0) > 0) Add(catalog, "inventoryTakeAll");
            else Add(catalog, "inventoryDone");
        }
        return catalog;
    }

    private static bool HasPartyScreenTransferAction(JsonArray? catalog) => catalog?.OfType<JsonObject>().Any(action =>
        ReadString(action, "action") is "partyTakeAll" or "partyLootTransferOne") == true;

    private static string? BuildPartyScreenFingerprint(JsonObject? state) =>
        state?["partyScreen"] is JsonObject partyScreen ? partyScreen.ToJsonString() : null;

    internal static JsonArray BuildControlCatalog(JsonObject state, string? targetId, bool battleWasStarted, bool recoverPlayerCaptivity = false)
    {
        var controls = new JsonArray();
        var context = state["context"] as JsonObject;
        var gameState = ReadString(context, "gameState");
        var completedMap = IsVerifiedMapTerminalAfterBattle(state, battleWasStarted);
        var mapMovementWait = string.Equals(ReadString(context, "gameState"), "MapState", StringComparison.Ordinal) &&
                              string.IsNullOrWhiteSpace(ReadString(context, "menuId")) && !ReadBoolean(context, "escapeMenuOpen") && !ReadBoolean(context, "inquiryOpen") &&
                              !ReadBoolean(context, "encounterActive") && context?["battleSimulation"] is null &&
                              state["partyScreen"] is null && state["inventoryScreen"] is null;
        if (completedMap && !(recoverPlayerCaptivity && IsPlayerCaptive(state))) controls.Add("done");
        else if (mapMovementWait && !string.IsNullOrWhiteSpace(targetId) &&
                 string.Equals(ReadString(state["location"] as JsonObject, "targetPartyId"), targetId, StringComparison.Ordinal))
            controls.Add("observeAgain");
        return controls;
    }

    internal static bool TryResolveDecision(JsonObject decision, JsonArray catalog, JsonArray controls, JsonObject state,
        JsonArray observedTargets, string? targetId, out string? action, out JsonObject? arguments, out int? waitSeconds, out string rejection,
        bool recoverPlayerCaptivity = false)
    {
        action = ReadString(decision, "action");
        arguments = null;
        waitSeconds = null;
        rejection = "Choose one action or control in the latest Native catalog.";
        if (action is not null)
        {
            var requestedAction = action;
            var template = catalog.OfType<JsonObject>().FirstOrDefault(x => string.Equals(ReadString(x, "action"), requestedAction, StringComparison.Ordinal));
            if (template is null) { rejection = $"Action '{action}' is not in the current Native catalog."; return false; }
            if (decision["arguments"] is not JsonObject given) { rejection = "Action arguments must be one JSON object."; return false; }
            var required = (template["arguments"] as JsonArray)?.Select(x => x?.GetValue<string>() ?? string.Empty).ToArray() ?? Array.Empty<string>();
            if (given.Count != required.Length || required.Any(name => !given.Any(pair => string.Equals(pair.Key, name, StringComparison.OrdinalIgnoreCase))))
            { rejection = "Arguments must contain exactly the names listed for this action."; return false; }
            arguments = new JsonObject();
            foreach (var key in required)
            {
                var nativeKey = char.ToLowerInvariant(key[0]) + key[1..];
                var supplied = given.First(pair => string.Equals(pair.Key, key, StringComparison.OrdinalIgnoreCase));
                arguments[nativeKey] = supplied.Value?.DeepClone();
            }
            if (action == "pursue")
            {
                var partyId = ReadString(arguments, "partyId");
                if (string.IsNullOrWhiteSpace(partyId) || !observedTargets.OfType<JsonObject>().Any(x =>
                        ReadString(x, "id") == partyId && ReadString(x, "type") == "bandit" && ReadBoolean(x, "hostile")))
                { rejection = "Pursuit target must be a currently observed hostile bandit party."; return false; }
            }
            if (action == "menuSelect")
            {
                var context = state["context"] as JsonObject;
                var currentMenuId = ReadString(context, "menuId");
                if (AgentHostCampaignStateFacts.IsNativeLocationMenu(state))
                {
                    var optionId = ReadString(arguments, "optionId");
                    if (currentMenuId != ReadString(arguments, "menuId") ||
                        string.IsNullOrWhiteSpace(optionId) ||
                        !(state["availableMenuOptions"] as JsonArray)?.OfType<JsonObject>().Any(option =>
                            ReadString(option, "id") == optionId && ReadBoolean(option, "available") &&
                            ReadBoolean(option, "enabled") && ReadBoolean(option, "isLeave")) == true)
                    { rejection = "A Native location menu may only select its currently enabled Leave option before this battle subflow proceeds."; return false; }
                }
                else if (currentMenuId == "try_to_get_away")
                {
                    var optionId = ReadString(arguments, "optionId");
                    var selectedCurrentWarningChoice = optionId is "try_to_get_away_accept" or "try_to_get_away_reject" &&
                        CurrentEnabledMenuOption(state, optionId!);
                    var hasNativeRiskEvidence = context?["encounterEscape"] is JsonObject escapeContext &&
                        ReadBoolean(escapeContext, "canTryToGetAway") == true &&
                        !string.IsNullOrWhiteSpace(ReadString(escapeContext, "menuText")) &&
                        ReadInt(escapeContext, "nativeTroopsSacrificedForTry", -1) >= 0;
                    if (currentMenuId != ReadString(arguments, "menuId") || !selectedCurrentWarningChoice ||
                        optionId == "try_to_get_away_accept" && !hasNativeRiskEvidence)
                    { rejection = "A Try-to-get-away warning may select only its current Native Accept/Reject option; Accept also requires the original visible loss estimate."; return false; }
                }
                else if (currentMenuId == "try_to_get_away_debrief")
                {
                    var optionId = ReadString(arguments, "optionId");
                    if (currentMenuId != ReadString(arguments, "menuId") || optionId != "try_to_get_away_continue" ||
                        !CurrentEnabledMenuOption(state, optionId))
                    { rejection = "Only the currently enabled Native debrief Continue option may close an accepted Try-to-get-away flow."; return false; }
                }
                else if (recoverPlayerCaptivity && IsPlayerCaptive(state))
                {
                    var optionId = ReadString(arguments, "optionId");
                    if (!IsSupportedCaptivityRansomMenu(currentMenuId) ||
                        currentMenuId != ReadString(arguments, "menuId") ||
                        !IsSupportedCaptivityRansomOption(optionId) || !CurrentEnabledMenuOption(state, optionId!))
                    { rejection = "Only a currently enabled Native Accept/Reject option in an observed MainHero ransom offer may be selected."; return false; }
                }
                else if (currentMenuId == "join_encounter")
                {
                    var selectedOptionId = ReadString(arguments, "optionId");
                    var allowedJoinOption = selectedOptionId is "join_encounter_help_attackers" or "join_encounter_help_defenders" or
                        "join_encounter_abandon" or "join_encounter_leave";
                    if (currentMenuId != ReadString(arguments, "menuId") || !allowedJoinOption ||
                        !CurrentEnabledMenuOption(state, selectedOptionId!))
                    { rejection = "A Native join-encounter choice must match a currently enabled Help, Abandon, or Leave menu option."; return false; }
                    var encounteredId = ReadString(state["context"] as JsonObject, "encounteredPartyId");
                    if (!observedTargets.OfType<JsonObject>().Any(x => ReadString(x, "id") == encounteredId && ReadString(x, "type") == "bandit" && ReadBoolean(x, "hostile")))
                    { rejection = "The join-encounter choice must belong to a currently observed hostile bandit interruption."; return false; }
                }
                else
                {
                    var selectedOptionId = ReadString(arguments, "optionId");
                    if (currentMenuId != "encounter" || currentMenuId != ReadString(arguments, "menuId"))
                    { rejection = "Battle menu choices are restricted to the current Native Encounter or the specifically observed Try-to-get-away warning/debrief."; return false; }
                    var sendTroopsEnabled = CurrentEnabledMenuOption(state, "str_order_attack");
                    var allowedSendTroops = selectedOptionId == "str_order_attack" && sendTroopsEnabled;
                    var escapeOptionEnabled = CurrentEnabledMenuOption(state, "leave_soldiers_behind");
                    var allowedLeave = selectedOptionId == "leave" && CurrentEnabledMenuOption(state, "leave");
                    var allowedTryToGetAway = selectedOptionId == "leave_soldiers_behind" && escapeOptionEnabled;
                    var allowedSurrenderFallback = recoverPlayerCaptivity && !sendTroopsEnabled && !CurrentEnabledMenuOption(state, "leave") && !escapeOptionEnabled &&
                        selectedOptionId == "surrender" && CurrentEnabledMenuOption(state, "surrender");
                    if (!(allowedSendTroops || allowedLeave || allowedTryToGetAway || allowedSurrenderFallback))
                    { rejection = "Select only a current enabled Native Send Troops, Leave, or Try-to-get-away option; surrender is recovery-only when those choices are unavailable. Real-time attack Missions are outside this loop."; return false; }
                    var encounteredId = ReadString(state["context"] as JsonObject, "encounteredPartyId");
                    if (!observedTargets.OfType<JsonObject>().Any(x => ReadString(x, "id") == encounteredId && ReadString(x, "type") == "bandit" && ReadBoolean(x, "hostile")))
                    { rejection = "The active encounter party must match a currently observed hostile bandit target."; return false; }
                }
            }
            if (action == "dialogueSelect")
            {
                var context = state["context"] as JsonObject;
                var conversation = context?["conversation"] as JsonObject;
                var optionId = ReadString(arguments, "optionId");
                var encounteredId = ReadString(state["context"] as JsonObject, "encounteredPartyId");
                var currentOptions = (conversation?["options"] as JsonArray)?.OfType<JsonObject>().ToArray() ?? Array.Empty<JsonObject>();
                if (ReadString(context, "gameState") == "MapState" && conversation is not null && !AgentHostCampaignStateFacts.IsActiveEncounter(state))
                {
                    if (currentOptions.Any(option => ReadString(option, "id") == optionId && ReadBoolean(option, "clickable")))
                        return true;
                    rejection = "Map conversation choices must exactly match a current clickable Native option.";
                    return false;
                }
                var hasFightResponse = currentOptions.Any(x =>
                    ReadString(x, "id") == "bandit_start_defender_1" && ReadBoolean(x, "clickable"));
                var allowedWeakPartySurrender = recoverPlayerCaptivity && !hasFightResponse && optionId == "bandit_start_defender_3" &&
                    currentOptions.Any(x => ReadString(x, "id") == optionId && ReadString(x, "textId") == WeakPartySurrenderResponseTextId && ReadBoolean(x, "clickable"));
                var allowedKnownFightResponse = optionId is "bandit_start_defender_1" or "common_encounter_ultimatum" or "common_bandit_surrender_declined";
                if (!(allowedKnownFightResponse || allowedWeakPartySurrender) || conversation is null ||
                    !currentOptions.Any(x => ReadString(x, "id") == optionId && ReadBoolean(x, "clickable")) ||
                    !observedTargets.OfType<JsonObject>().Any(x => ReadString(x, "id") == encounteredId && ReadString(x, "type") == "bandit" && ReadBoolean(x, "hostile")))
                { rejection = "Only a current clickable Native fight/ultimatum response is allowed; the exact weak-party surrender line is allowed only in captivity-recovery mode when no Fight response is available."; return false; }
            }
            if (action == "dialogueContinue")
            {
                var conversation = (state["context"] as JsonObject)?["conversation"] as JsonObject;
                var clickableCount = (conversation?["options"] as JsonArray)?.OfType<JsonObject>().Count(x => ReadBoolean(x, "clickable")) ?? 0;
                if (conversation is null || clickableCount != 0 || string.IsNullOrWhiteSpace(ReadString(conversation, "sentenceText")))
                { rejection = "Dialogue Continue is only allowed for the current Native response line when no choice is clickable."; return false; }
            }
            if (action == "partyTakeAll")
            {
                var troopType = ReadString(arguments, "troopType");
                var listedTroopTypes = template["argumentValues"]?["TroopType"] as JsonArray;
                if (troopType is null || listedTroopTypes?.OfType<JsonValue>().Any(value => value.TryGetValue<string>(out var listedType) && listedType == troopType) != true)
                { rejection = "TroopType must exactly match a currently listed transferable Native loot roster: members or prisoners."; return false; }
                var rosterName = troopType == "members" ? "leftMembers" : "leftPrisoners";
                if (!HasTransferableRoster((state["partyScreen"] as JsonObject)?[rosterName] as JsonArray))
                { rejection = "Take-all troop type must have a currently observed transferable Native roster."; return false; }
            }
            if (action == "partyLootTransferOne")
            {
                var troopId = ReadString(arguments, "troopId");
                var troopType = ReadString(arguments, "troopType");
                var allowedPairs = template["argumentPairs"] as JsonArray;
                var pairIsCurrent = allowedPairs?.OfType<JsonObject>().Any(pair =>
                    ReadString(pair, "TroopId") == troopId && ReadString(pair, "TroopType") == troopType) == true;
                var rosterName = troopType == "members" ? "leftMembers" : troopType == "prisoners" ? "leftPrisoners" : string.Empty;
                var visibleRowIsCurrent = !string.IsNullOrWhiteSpace(rosterName) &&
                    (state["partyScreen"] as JsonObject)?[rosterName] is JsonArray rows &&
                    rows.OfType<JsonObject>().Any(row => ReadString(row, "troopId") == troopId && ReadBoolean(row, "transferable") && ReadInt(row, "count", 0) > 0);
                if (!pairIsCurrent || !visibleRowIsCurrent)
                { rejection = "Loot transfer must match one currently visible transferable Native left-roster row and its exact current members/prisoners type."; return false; }
            }
            return true;
        }

        var control = ReadBoolean(decision, "done") ? "done" : ReadBoolean(decision, "observeAgain") ? "observeAgain" : ReadString(decision, "control");
        var listedControl = controls.Any(x => x is JsonValue node && node.TryGetValue<string>(out var name) && string.Equals(name, control, StringComparison.Ordinal));
        if (!listedControl) { rejection = "Control is not listed for the current Native state."; return false; }
        if (control == "observeAgain")
        {
            var wait = ReadInt(decision, "waitSeconds", -1);
            if (wait is < 1 or > 10) { rejection = "observeAgain waitSeconds must be an integer from 1 through 10."; return false; }
            waitSeconds = wait;
            return true;
        }
        if (control == "done") return true;
        rejection = "Unsupported control.";
        return false;
    }

    internal static IReadOnlyList<object> RunContractSelfTests()
    {
        var results = new List<object>();
        if (!AgentHostDecisionCycle.BattleAndCaptivitySystemPrompt.Contains("surrender only as an emergency survival fallback", StringComparison.Ordinal) ||
            AgentHostDecisionCycle.BattleSimulationSystemPrompt.Contains("surrender only as a survival fallback", StringComparison.Ordinal) ||
            !AgentHostDecisionCycle.BattleSimulationSystemPrompt.Contains("nearby hostile parties may join the same battle", StringComparison.Ordinal) ||
            !AgentHostDecisionCycle.BattleSimulationSystemPrompt.Contains("context.encounterEscape.menuText", StringComparison.Ordinal) ||
            !AgentHostDecisionCycle.BattleSimulationSystemPrompt.Contains("try_to_get_away_reject", StringComparison.Ordinal) ||
            !AgentHostDecisionCycle.BattleSimulationSystemPrompt.Contains("do not repeat a negative/Done cycle", StringComparison.Ordinal))
            throw new AgentHostException("battle-loop-self-test-risk-aware-retreat-prompt-scope-failed", "BattleSimulation must assess nearby same-faction hostile force and the current Native Try-to-get-away loss warning, while surrender remains recovery-only.");
        var visibleBanditNeedsDecisionPause = ParseObject(JsonDocument.Parse("""
            {"timeControlMode":"StoppablePlay","state":{"context":{"gameState":"MapState","menuId":null,"encounterActive":false,"inquiryOpen":false,"escapeMenuOpen":false,"isWaitMenu":false,"isWaitActive":false,"mapIncident":{"active":false},"sceneNotification":{"hasActiveNotification":false},"captivity":{"isCaptive":false}},"location":{"targetPartyId":null},"party":{"isMoving":true},"nearbyParties":[{"id":"bandit-a","type":"bandit","hostile":true}]}}
            """).RootElement);
        var alreadyPursuingVisibleBandit = (JsonObject)visibleBanditNeedsDecisionPause.DeepClone();
        alreadyPursuingVisibleBandit["state"]!["location"]!["targetPartyId"] = "bandit-a";
        var activePursuitWithSecondBandit = (JsonObject)visibleBanditNeedsDecisionPause.DeepClone();
        activePursuitWithSecondBandit["state"]!["location"]!["targetPartyId"] = "bandit-a";
        activePursuitWithSecondBandit["state"]!["party"]!["defaultBehavior"] = "EngageParty";
        activePursuitWithSecondBandit["state"]!["party"]!["isMoving"] = false;
        (activePursuitWithSecondBandit["state"]!["nearbyParties"] as JsonArray)!.Add(new JsonObject { ["id"] = "bandit-b", ["type"] = "bandit", ["hostile"] = true });
        var stoppedVisibleBandit = (JsonObject)visibleBanditNeedsDecisionPause.DeepClone();
        stoppedVisibleBandit["timeControlMode"] = "Stop";
        var visibleNeutralParty = (JsonObject)visibleBanditNeedsDecisionPause.DeepClone();
        visibleNeutralParty["state"]!["nearbyParties"]![0]!["hostile"] = false;
        var visibleHostileLord = (JsonObject)visibleBanditNeedsDecisionPause.DeepClone();
        visibleHostileLord["state"]!["nearbyParties"]![0]!["type"] = "lord";
        var visibleBanditUnderNativeMenu = (JsonObject)visibleBanditNeedsDecisionPause.DeepClone();
        visibleBanditUnderNativeMenu["state"]!["context"]!["menuId"] = "town";
        var visibleBanditDuringEncounter = (JsonObject)visibleBanditNeedsDecisionPause.DeepClone();
        visibleBanditDuringEncounter["state"]!["context"]!["encounterActive"] = true;
        if (!ShouldPauseForVisibleHostileDecision(visibleBanditNeedsDecisionPause) ||
            ShouldPauseForVisibleHostileDecision(alreadyPursuingVisibleBandit) ||
            ShouldPauseForVisibleHostileDecision(activePursuitWithSecondBandit) ||
            ShouldPauseForVisibleHostileDecision(stoppedVisibleBandit) ||
            ShouldPauseForVisibleHostileDecision(visibleNeutralParty) ||
            ShouldPauseForVisibleHostileDecision(visibleHostileLord) ||
            ShouldPauseForVisibleHostileDecision(visibleBanditUnderNativeMenu) ||
            ShouldPauseForVisibleHostileDecision(visibleBanditDuringEncounter))
            throw new AgentHostException("battle-loop-visible-threat-pause-classification-failed", "Only a visible hostile bandit on an active free map, with no Native pursuit already active, may trigger the separately recorded Native Pause; another visible bandit must not interrupt an existing pursuit.");
        results.Add(new { scenario = "battle-loop-pauses-before-a-new-hostile-decision-but-never-interrupts-an-existing-native-bandit-pursuit", passed = true });
        var map = ParseState("MapState", menuId: null, encounterActive: false, partyTarget: null, battle: null);
        var candidates = new JsonArray(new JsonObject { ["id"] = "bandit-1", ["type"] = "bandit", ["hostile"] = true });
        var mapState = map["state"]!.AsObject();
        var query = BuildActionCatalog(mapState, new JsonArray(), null, false, false);
        if (query.Count != 1 || ReadString(query[0] as JsonObject, "action") != "mapPartyTargets")
            throw new AgentHostException("battle-loop-self-test-map-query-missing", "The initial battle loop must query currently visible Native party targets.");
        if (BuildActionCatalog(mapState, new JsonArray(), null, false, true).Count != 0)
            throw new AgentHostException("battle-loop-self-test-empty-party-query-repeated", "After an empty visible-party query, the Host must safely stop rather than requery the same world state indefinitely.");
        var noChoiceMapConversation = ParseState("MapState", menuId: null, encounterActive: false, partyTarget: null, battle: null)["state"]!.AsObject();
        noChoiceMapConversation["context"]!["conversation"] = new JsonObject
        {
            ["characterId"] = "notable-a", ["sentenceText"] = "We part ways.", ["options"] = new JsonArray()
        };
        var mapContinueCatalog = BuildActionCatalog(noChoiceMapConversation, new JsonArray(), null, false, true);
        if (mapContinueCatalog.Count != 1 || ReadString(mapContinueCatalog[0] as JsonObject, "action") != "dialogueContinue" ||
            !TryResolveDecision(new JsonObject { ["action"] = "dialogueContinue", ["arguments"] = new JsonObject() }, mapContinueCatalog,
                new JsonArray(), noChoiceMapConversation, new JsonArray(), null, out var mapContinueAction, out _, out _, out _) || mapContinueAction != "dialogueContinue")
            throw new AgentHostException("battle-loop-map-no-choice-conversation-continue-not-listed", "An active Native MapState conversation with no selectable answers must expose only its original dialogueContinue handler before any passive pursuit wait.");
        var choiceMapConversation = (JsonObject)noChoiceMapConversation.DeepClone();
        choiceMapConversation["context"]!["conversation"]!["options"] = new JsonArray(
            new JsonObject { ["id"] = "notable_decline", ["clickable"] = true },
            new JsonObject { ["id"] = "notable_hidden", ["clickable"] = false });
        var mapChoiceCatalog = BuildActionCatalog(choiceMapConversation, new JsonArray(), null, false, true);
        var mapOptionIds = mapChoiceCatalog.OfType<JsonObject>().SingleOrDefault(action => ReadString(action, "action") == "dialogueSelect")? ["argumentValues"]? ["OptionId"] as JsonArray;
        if (mapChoiceCatalog.Count != 1 || mapOptionIds?.Count != 1 || mapOptionIds[0]?.GetValue<string>() != "notable_decline" ||
            !TryResolveDecision(new JsonObject { ["action"] = "dialogueSelect", ["arguments"] = new JsonObject { ["OptionId"] = "notable_decline" } },
                mapChoiceCatalog, new JsonArray(), choiceMapConversation, new JsonArray(), null, out var mapSelectAction, out _, out _, out _) || mapSelectAction != "dialogueSelect" ||
            TryResolveDecision(new JsonObject { ["action"] = "dialogueSelect", ["arguments"] = new JsonObject { ["OptionId"] = "unlisted" } },
                mapChoiceCatalog, new JsonArray(), choiceMapConversation, new JsonArray(), null, out _, out _, out _, out _))
            throw new AgentHostException("battle-loop-map-conversation-choice-catalog-invalid", "An active Native Map conversation must expose only its current clickable answer IDs and reject all other selections.");
        results.Add(new { scenario = "battle-loop-resolves-active-map-conversation-before-pursuit-wait-and-uses-only-current-options", passed = true });
        var trainingFieldMenu = ParseState("MapState", "training_field_menu", true, null, null)["state"]!.AsObject();
        trainingFieldMenu["context"]!["encounteredPartyId"] = "tutorial_training_field";
        trainingFieldMenu["location"]!["currentSettlementId"] = "tutorial_training_field";
        trainingFieldMenu["availableMenuOptions"] = new JsonArray(new JsonObject { ["id"] = "training_field_leave", ["available"] = true, ["enabled"] = true, ["isLeave"] = true });
        var trainingFieldLeave = BuildActionCatalog(trainingFieldMenu, new JsonArray(), null, false, false);
        var trainingFieldLeaveDecision = new JsonObject { ["action"] = "menuSelect", ["arguments"] = new JsonObject { ["MenuId"] = "training_field_menu", ["OptionId"] = "training_field_leave" } };
        if (trainingFieldLeave.Count != 1 || ReadString(trainingFieldLeave[0] as JsonObject, "action") != "menuSelect" ||
            (trainingFieldLeave[0]?["argumentValues"]?["MenuId"] as JsonArray)?[0]?.GetValue<string>() != "training_field_menu" ||
            !((trainingFieldLeave[0]?["argumentValues"]?["OptionId"] as JsonArray)?.Any(option => option?.GetValue<string>() == "training_field_leave") ?? false) ||
            !TryResolveDecision(trainingFieldLeaveDecision, trainingFieldLeave, new JsonArray(), trainingFieldMenu, new JsonArray(), null, out _, out _, out _, out _))
            throw new AgentHostException("battle-loop-self-test-training-field-menu-not-exitable", "A Native location menu with an encounter-like location ID must expose only its current enabled Leave option before battle target scanning.");
        results.Add(new { scenario = "battle-loop-can-leave-native-training-field-location-menu-without-treating-it-as-hostile", passed = true });
        var pursue = BuildActionCatalog(mapState, candidates, null, false, true);
        if (pursue.Count != 1 || ReadString(pursue[0] as JsonObject, "action") != "pursue")
            throw new AgentHostException("battle-loop-self-test-pursue-missing", "Pursuit must only be available after a Native bandit target observation.");
        var deferredMapState = (JsonObject)mapState.DeepClone();
        deferredMapState["party"] = new JsonObject { ["members"] = 4, ["healthy"] = 4, ["wounded"] = 0, ["prisoners"] = 0 };
        var deferredCandidate = new JsonArray(new JsonObject { ["id"] = "bandit-1", ["type"] = "bandit", ["hostile"] = true, ["members"] = 9 });
        var deferredTrace = new JsonArray(BuildDeferredPartyTargetTraceStep("bandit-1", deferredCandidate, deferredMapState));
        var deferredIds = BuildDeferredPartyTargetIds(deferredTrace, deferredMapState, deferredCandidate);
        var deferredCatalog = BuildActionCatalog(deferredMapState, deferredCandidate, null, false, true, deferredPartyTargetIds: deferredIds);
        var strongerPlayer = (JsonObject)deferredMapState.DeepClone();
        strongerPlayer["party"]!["members"] = 5;
        strongerPlayer["party"]!["healthy"] = 5;
        var strongerPlayerIds = BuildDeferredPartyTargetIds(deferredTrace, strongerPlayer, deferredCandidate);
        var changedEnemy = new JsonArray(new JsonObject { ["id"] = "bandit-1", ["type"] = "bandit", ["hostile"] = true, ["members"] = 10 });
        var changedEnemyIds = BuildDeferredPartyTargetIds(deferredTrace, deferredMapState, changedEnemy);
        if (!deferredIds.Contains("bandit-1") || deferredCatalog.Count != 0 || strongerPlayerIds.Contains("bandit-1") || changedEnemyIds.Contains("bandit-1"))
            throw new AgentHostException("battle-loop-self-test-no-progress-bandit-target-cooldown-failed", "After Native Leave without a battle, the same party must be deferred while both sides retain the observed strength; a changed MainParty roster or changed bandit size must reopen it.");
        var deferredEncounter = ParseState("MapState", "encounter", true, null, null)["state"]!.AsObject();
        deferredEncounter["context"]!["encounteredPartyId"] = "bandit-1";
        deferredEncounter["availableMenuOptions"] = new JsonArray(new JsonObject { ["id"] = "str_order_attack", ["enabled"] = true, ["available"] = true });
        var deferredEncounterCatalog = BuildActionCatalog(deferredEncounter, deferredCandidate, "bandit-1", false, true,
            recoverPlayerCaptivity: true, deferredPartyTargetIds: deferredIds);
        if (deferredEncounterCatalog.Count != 1 || ReadString(deferredEncounterCatalog[0] as JsonObject, "action") != "menuSelect")
            throw new AgentHostException("battle-loop-self-test-deferred-target-blocked-current-native-encounter", "A prior no-battle cooldown must block only a new pursuit and must still let the Host resolve a current Native encounter.");
        results.Add(new { scenario = "battle-loop-defers-repeated-no-battle-bandit-pursuit-until-either-side-strength-changes", passed = true });
        var unverified = new JsonObject { ["action"] = "pursue", ["arguments"] = new JsonObject { ["PartyId"] = "other-party" } };
        if (TryResolveDecision(unverified, pursue, new JsonArray(), mapState, candidates, null, out _, out _, out _, out _))
            throw new AgentHostException("battle-loop-self-test-hidden-party-accepted", "The Host accepted a party absent from the current visible hostile bandit observation.");
        results.Add(new { scenario = "battle-loop-requires-current-visible-hostile-bandit-for-pursuit", passed = true });

        var nativePursuitLostTarget = ParseState("MapState", menuId: null, encounterActive: false, partyTarget: null, battle: null)["state"]!.AsObject();
        nativePursuitLostTarget["context"]!["timeControlMode"] = "StoppablePlay";
        nativePursuitLostTarget["context"]!["isWaiting"] = true;
        nativePursuitLostTarget["location"]!["targetPartyId"] = null;
        nativePursuitLostTarget["party"] = new JsonObject { ["moveMode"] = "Hold", ["defaultBehavior"] = "Hold", ["isMoving"] = false };
        nativePursuitLostTarget["nearbyParties"] = new JsonArray();
        var lostPursuitCatalog = BuildActionCatalog(nativePursuitLostTarget, new JsonArray(), "bandit-1", false, false);
        var lostPursuitControls = BuildControlCatalog(nativePursuitLostTarget, "bandit-1", false);
        var lostPursuitRescan = new JsonObject { ["action"] = "mapPartyTargets", ["arguments"] = new JsonObject() };
        if (lostPursuitCatalog.Count != 1 || ReadString(lostPursuitCatalog[0] as JsonObject, "action") != "mapPartyTargets" ||
            lostPursuitControls.Count != 0 ||
            !TryResolveDecision(lostPursuitRescan, lostPursuitCatalog, lostPursuitControls, nativePursuitLostTarget, new JsonArray(), "bandit-1", out var rescanAction, out _, out _, out _) ||
            rescanAction != "mapPartyTargets")
            throw new AgentHostException("battle-loop-self-test-native-pursuit-loss-does-not-rescan", "When Native EngageParty loses visibility and settles into waiting Hold, the Host must rescan current visible targets instead of offering an idle observeAgain control.");
        results.Add(new { scenario = "battle-loop-native-pursuit-loss-rescans-visible-targets-without-idle-wait", passed = true });

        var joinEncounter = ParseState("MapState", "join_encounter", true, null, null);
        joinEncounter["state"]!["context"]!["encounteredPartyId"] = "bandit-1";
        joinEncounter["state"]!["availableMenuOptions"] = new JsonArray(
            new JsonObject { ["id"] = "join_encounter_help_attackers", ["enabled"] = true, ["available"] = true },
            new JsonObject { ["id"] = "join_encounter_help_defenders", ["enabled"] = false, ["available"] = false },
            new JsonObject { ["id"] = "join_encounter_abandon", ["enabled"] = false, ["available"] = false },
            new JsonObject { ["id"] = "join_encounter_leave", ["enabled"] = true, ["available"] = true });
        var joinEncounterCatalog = BuildActionCatalog(joinEncounter["state"]!.AsObject(), candidates, "bandit-1", false, true);
        var joinEncounterOptionIds = joinEncounterCatalog.SingleOrDefault()? ["argumentValues"]? ["OptionId"] as JsonArray;
        var helpBanditSide = new JsonObject { ["action"] = "menuSelect", ["arguments"] = new JsonObject { ["MenuId"] = "join_encounter", ["OptionId"] = "join_encounter_help_attackers" } };
        var leaveJoinEncounter = new JsonObject { ["action"] = "menuSelect", ["arguments"] = new JsonObject { ["MenuId"] = "join_encounter", ["OptionId"] = "join_encounter_leave" } };
        var disabledJoinEncounterOption = new JsonObject { ["action"] = "menuSelect", ["arguments"] = new JsonObject { ["MenuId"] = "join_encounter", ["OptionId"] = "join_encounter_help_defenders" } };
        var joinHelpResolves = TryResolveDecision(helpBanditSide, joinEncounterCatalog, new JsonArray(), joinEncounter["state"]!.AsObject(), candidates, "bandit-1", out _, out _, out _, out _);
        var joinLeaveResolves = TryResolveDecision(leaveJoinEncounter, joinEncounterCatalog, new JsonArray(), joinEncounter["state"]!.AsObject(), candidates, "bandit-1", out _, out _, out _, out _);
        var disabledJoinOptionResolves = TryResolveDecision(disabledJoinEncounterOption, joinEncounterCatalog, new JsonArray(), joinEncounter["state"]!.AsObject(), candidates, "bandit-1", out _, out _, out _, out _);
        var leaveSelectionRecognized = IsNativeEncounterLeaveSelection(joinEncounter["state"]!.AsObject(), new JsonObject { ["menuId"] = "join_encounter", ["optionId"] = "join_encounter_leave" });
        var helpSelectionMisrecognizedAsLeave = IsNativeEncounterLeaveSelection(joinEncounter["state"]!.AsObject(), new JsonObject { ["menuId"] = "join_encounter", ["optionId"] = "join_encounter_help_attackers" });
        if (joinEncounterCatalog.Count != 1 || joinEncounterOptionIds?.Count != 2 || !joinHelpResolves || !joinLeaveResolves ||
            disabledJoinOptionResolves || !leaveSelectionRecognized || helpSelectionMisrecognizedAsLeave)
            throw new AgentHostException("battle-loop-self-test-join-encounter-native-options-not-bounded", $"For an observed hostile Bandit interrupt, list only current enabled Native join/leave options and recognize the Native join_encounter_leave option for no-battle return verification. catalog={joinEncounterCatalog.ToJsonString()}; help={joinHelpResolves}; leave={joinLeaveResolves}; disabled={disabledJoinOptionResolves}; leaveRecognized={leaveSelectionRecognized}; helpAsLeave={helpSelectionMisrecognizedAsLeave}.");
        results.Add(new { scenario = "battle-loop-observed-bandit-join-encounter-exposes-current-native-help-or-leave-and-verifies-leave-choice", passed = true });

        var encounter = ParseState("MapState", "encounter", true, null, null);
        encounter["state"]!["context"]!["encounteredPartyId"] = "bandit-1";
        encounter["state"]!["availableMenuOptions"] = new JsonArray(new JsonObject { ["id"] = "str_order_attack", ["enabled"] = true, ["available"] = true });
        var fight = BuildActionCatalog(encounter["state"]!.AsObject(), candidates, "bandit-1", false, true);
        if (fight.Count != 1 || ReadString(fight[0] as JsonObject, "action") != "menuSelect")
            throw new AgentHostException("battle-loop-self-test-native-attack-not-listed", "The live encounter exposes only the enabled Native attack option when party identity matches.");
        var wrongMenu = new JsonObject { ["action"] = "menuSelect", ["arguments"] = new JsonObject { ["MenuId"] = "encounter", ["OptionId"] = "str_order_retreat" } };
        if (TryResolveDecision(wrongMenu, fight, new JsonArray(), encounter["state"]!.AsObject(), candidates, "bandit-1", out _, out _, out _, out _))
            throw new AgentHostException("battle-loop-self-test-non-attack-choice-accepted", "The bounded loop must not expose retreat, ransom, toll or unsupported encounter choices.");

        var escapeChoiceEncounter = ParseState("MapState", "encounter", true, null, null);
        escapeChoiceEncounter["state"]!["context"]!["encounteredPartyId"] = "bandit-1";
        escapeChoiceEncounter["state"]!["availableMenuOptions"] = new JsonArray(
            new JsonObject { ["id"] = "str_order_attack", ["enabled"] = true, ["available"] = true },
            new JsonObject { ["id"] = "leave_soldiers_behind", ["enabled"] = true, ["available"] = true },
            new JsonObject { ["id"] = "leave", ["enabled"] = false, ["available"] = false });
        var escapeChoiceCatalog = BuildActionCatalog(escapeChoiceEncounter["state"]!.AsObject(), candidates, "bandit-1", false, true);
        var encounterOptionIds = escapeChoiceCatalog.Single()? ["argumentValues"]? ["OptionId"] as JsonArray;
        var tryToGetAwayDecision = new JsonObject { ["action"] = "menuSelect", ["arguments"] = new JsonObject { ["MenuId"] = "encounter", ["OptionId"] = "leave_soldiers_behind" } };
        if (escapeChoiceCatalog.Count != 1 || encounterOptionIds?.Count != 2 ||
            !encounterOptionIds.Any(option => option?.GetValue<string>() == "str_order_attack") ||
            !encounterOptionIds.Any(option => option?.GetValue<string>() == "leave_soldiers_behind") ||
            !TryResolveDecision(tryToGetAwayDecision, escapeChoiceCatalog, new JsonArray(), escapeChoiceEncounter["state"]!.AsObject(), candidates, "bandit-1", out _, out _, out _, out _))
            throw new AgentHostException("battle-loop-self-test-native-try-to-get-away-not-offered", "When the Native encounter enables both Send Troops and Try-to-get-away, the model must receive both exact current options so it can weigh battle risk.");

        var escapeWarning = ParseState("MapState", "try_to_get_away", true, null, null);
        escapeWarning["state"]!["context"]!["encounteredPartyId"] = "bandit-1";
        escapeWarning["state"]!["context"]!["encounterEscape"] = new JsonObject
        {
            ["schemaVersion"] = 1, ["menuId"] = "try_to_get_away", ["menuText"] = "You may lose 7 troops and some cargo.",
            ["canTryToGetAway"] = true, ["nativeTroopsSacrificedForTry"] = 7, ["healthyNonHeroMembers"] = 12
        };
        escapeWarning["state"]!["availableMenuOptions"] = new JsonArray(
            new JsonObject { ["id"] = "try_to_get_away_accept", ["enabled"] = true, ["available"] = true },
            new JsonObject { ["id"] = "try_to_get_away_reject", ["enabled"] = true, ["available"] = true });
        var escapeWarningCatalog = BuildActionCatalog(escapeWarning["state"]!.AsObject(), candidates, "bandit-1", false, true);
        var acceptEscape = new JsonObject { ["action"] = "menuSelect", ["arguments"] = new JsonObject { ["MenuId"] = "try_to_get_away", ["OptionId"] = "try_to_get_away_accept" } };
        var rejectEscape = new JsonObject { ["action"] = "menuSelect", ["arguments"] = new JsonObject { ["MenuId"] = "try_to_get_away", ["OptionId"] = "try_to_get_away_reject" } };
        if (escapeWarningCatalog.Count != 1 ||
            !(escapeWarningCatalog[0]? ["argumentValues"]? ["OptionId"] as JsonArray)?.Any(option => option?.GetValue<string>() == "try_to_get_away_accept") == true ||
            !TryResolveDecision(acceptEscape, escapeWarningCatalog, new JsonArray(), escapeWarning["state"]!.AsObject(), candidates, "bandit-1", out _, out _, out _, out _) ||
            !TryResolveDecision(rejectEscape, escapeWarningCatalog, new JsonArray(), escapeWarning["state"]!.AsObject(), candidates, "bandit-1", out _, out _, out _, out _))
            throw new AgentHostException("battle-loop-self-test-native-escape-warning-not-bounded", "The Native Try-to-get-away warning may expose only its current Accept/Reject choices, and Accept must require the visible Native troop-loss warning.");
        var escapeWarningWithoutRisk = (JsonObject)escapeWarning["state"]!.AsObject().DeepClone();
        escapeWarningWithoutRisk["context"]!["encounterEscape"] = null;
        if (TryResolveDecision(acceptEscape, escapeWarningCatalog, new JsonArray(), escapeWarningWithoutRisk, candidates, "bandit-1", out _, out _, out _, out _) ||
            !TryResolveDecision(rejectEscape, escapeWarningCatalog, new JsonArray(), escapeWarningWithoutRisk, candidates, "bandit-1", out _, out _, out _, out _))
            throw new AgentHostException("battle-loop-self-test-native-escape-accept-without-risk-evidence", "The Host must fail closed on Native escape Accept when its exact loss estimate is not observed, while preserving the zero-cost Reject.");
        var escapeDebrief = ParseState("MapState", "try_to_get_away_debrief", true, null, null)["state"]!.AsObject();
        escapeDebrief["context"]!["encounteredPartyId"] = "bandit-1";
        escapeDebrief["availableMenuOptions"] = new JsonArray(new JsonObject { ["id"] = "try_to_get_away_continue", ["enabled"] = true, ["available"] = true });
        var escapeContinueCatalog = BuildActionCatalog(escapeDebrief, candidates, "bandit-1", false, true);
        if (escapeContinueCatalog.Count != 1 ||
            !TryResolveDecision(new JsonObject { ["action"] = "menuSelect", ["arguments"] = new JsonObject { ["MenuId"] = "try_to_get_away_debrief", ["OptionId"] = "try_to_get_away_continue" } }, escapeContinueCatalog, new JsonArray(), escapeDebrief, candidates, "bandit-1", out _, out _, out _, out _) ||
            TryResolveDecision(new JsonObject { ["action"] = "menuSelect", ["arguments"] = new JsonObject { ["MenuId"] = "try_to_get_away_debrief", ["OptionId"] = "surrender" } }, escapeContinueCatalog, new JsonArray(), escapeDebrief, candidates, "bandit-1", out _, out _, out _, out _))
            throw new AgentHostException("battle-loop-self-test-native-escape-debrief-not-bounded", "After an accepted Native escape, the Host may submit only the current Continue option in the original debrief.");
        var playerFacingAttackMenu = ParseState("MapState", "encounter", true, null, null);
        playerFacingAttackMenu["state"]!["context"]!["encounteredPartyId"] = "bandit-1";
        playerFacingAttackMenu["state"]!["availableMenuOptions"] = new JsonArray(
            new JsonObject { ["id"] = "attack", ["enabled"] = true, ["available"] = true },
            new JsonObject { ["id"] = "str_order_attack", ["enabled"] = false, ["available"] = false });
        var playerFacingAttackCatalog = BuildActionCatalog(playerFacingAttackMenu["state"]!.AsObject(), candidates, "bandit-1", false, true);
        var playerFacingAttackDecision = new JsonObject { ["action"] = "menuSelect", ["arguments"] = new JsonObject { ["MenuId"] = "encounter", ["OptionId"] = "attack" } };
        if (playerFacingAttackCatalog.Count != 0 ||
            TryResolveDecision(playerFacingAttackDecision, playerFacingAttackCatalog, new JsonArray(), playerFacingAttackMenu["state"]!.AsObject(), candidates, "bandit-1", out _, out _, out _, out _))
            throw new AgentHostException("battle-loop-realtime-attack-mission-not-exposed-as-simulation", "An enabled Native attack option that would enter a real-time Mission must remain unavailable when str_order_attack is disabled.");
        results.Add(new { scenario = "battle-loop-requires-native-send-troops-option-and-rejects-realtime-attack-mission", passed = true });

        var noSendTroopsMenu = ParseState("MapState", "encounter", true, null, null);
        noSendTroopsMenu["state"]!["context"]!["encounteredPartyId"] = "bandit-1";
        noSendTroopsMenu["state"]!["availableMenuOptions"] = new JsonArray(
            new JsonObject { ["id"] = "attack", ["enabled"] = true, ["available"] = true },
            new JsonObject { ["id"] = "str_order_attack", ["enabled"] = false, ["available"] = false },
            new JsonObject { ["id"] = "leave", ["enabled"] = true, ["available"] = true });
        var noSendTroopsState = noSendTroopsMenu["state"]!.AsObject();
        var nativeLeaveCatalog = BuildActionCatalog(noSendTroopsState, candidates, "bandit-1", false, true);
        var nativeLeaveDecision = new JsonObject { ["action"] = "menuSelect", ["arguments"] = new JsonObject { ["MenuId"] = "encounter", ["OptionId"] = "leave" } };
        var liveAttackDecision = new JsonObject { ["action"] = "menuSelect", ["arguments"] = new JsonObject { ["MenuId"] = "encounter", ["OptionId"] = "attack" } };
        var disabledSendTroopsDecision = new JsonObject { ["action"] = "menuSelect", ["arguments"] = new JsonObject { ["MenuId"] = "encounter", ["OptionId"] = "str_order_attack" } };
        var listedLeaveOptions = nativeLeaveCatalog.FirstOrDefault()?["argumentValues"]?["OptionId"] as JsonArray;
        if (nativeLeaveCatalog.Count != 1 || ReadString(nativeLeaveCatalog[0] as JsonObject, "action") != "menuSelect" ||
            listedLeaveOptions?.Count != 1 || listedLeaveOptions[0]?.GetValue<string>() != "leave" ||
            !TryResolveDecision(nativeLeaveDecision, nativeLeaveCatalog, new JsonArray(), noSendTroopsState, candidates, "bandit-1", out _, out _, out _, out _) ||
            TryResolveDecision(liveAttackDecision, nativeLeaveCatalog, new JsonArray(), noSendTroopsState, candidates, "bandit-1", out _, out _, out _, out _) ||
            TryResolveDecision(disabledSendTroopsDecision, nativeLeaveCatalog, new JsonArray(), noSendTroopsState, candidates, "bandit-1", out _, out _, out _, out _))
            throw new AgentHostException("battle-loop-self-test-native-leave-not-bounded", "When Native Send Troops is disabled, expose only the current enabled Native Leave option and reject both real-time Attack and disabled Send Troops.");
        noSendTroopsState["availableMenuOptions"]![2]!["enabled"] = false;
        noSendTroopsState["availableMenuOptions"]![2]!["available"] = false;
        if (BuildActionCatalog(noSendTroopsState, candidates, "bandit-1", false, true).Count != 0)
            throw new AgentHostException("battle-loop-self-test-disabled-native-leave-listed", "Native Leave must not be listed after the encounter menu reports it disabled.");
        noSendTroopsState["availableMenuOptions"]!.AsArray().Add(new JsonObject { ["id"] = "surrender", ["enabled"] = true, ["available"] = true });
        var ordinarySurrenderCatalog = BuildActionCatalog(noSendTroopsState, candidates, "bandit-1", false, true, recoverPlayerCaptivity: false);
        var captivitySurrenderCatalog = BuildActionCatalog(noSendTroopsState, candidates, "bandit-1", false, true, recoverPlayerCaptivity: true);
        var surrenderFallbackDecision = new JsonObject { ["action"] = "menuSelect", ["arguments"] = new JsonObject { ["MenuId"] = "encounter", ["OptionId"] = "surrender" } };
        if (ordinarySurrenderCatalog.Count != 0 || captivitySurrenderCatalog.Count != 1 ||
            ReadString(captivitySurrenderCatalog[0] as JsonObject, "action") != "menuSelect" ||
            (captivitySurrenderCatalog[0]?["argumentValues"]?["OptionId"] as JsonArray)?.Any(value => value?.GetValue<string>() == "surrender") != true ||
            !TryResolveDecision(surrenderFallbackDecision, captivitySurrenderCatalog, new JsonArray(), noSendTroopsState, candidates, "bandit-1",
                out var surrenderFallbackAction, out var surrenderFallbackArguments, out _, out _, recoverPlayerCaptivity: true) ||
            surrenderFallbackAction != "menuSelect" || ReadString(surrenderFallbackArguments, "optionId") != "surrender" ||
            TryResolveDecision(surrenderFallbackDecision, captivitySurrenderCatalog, new JsonArray(), noSendTroopsState, candidates, "bandit-1",
                out _, out _, out _, out _, recoverPlayerCaptivity: false))
            throw new AgentHostException("battle-loop-self-test-native-surrender-captivity-fallback-failed", "Only explicit captivity-recovery mode may surrender when Native disables Send Troops and Leave; ordinary Renown BattleSimulation must keep it closed.");
        var noEnabledSurrender = (JsonObject)noSendTroopsState.DeepClone();
        noEnabledSurrender["availableMenuOptions"]![3]!["enabled"] = false;
        noEnabledSurrender["availableMenuOptions"]![3]!["available"] = false;
        if (BuildActionCatalog(noEnabledSurrender, candidates, "bandit-1", false, true, recoverPlayerCaptivity: true).Count != 0)
            throw new AgentHostException("battle-loop-self-test-disabled-surrender-fallback-listed", "Captivity recovery may expose surrender only when the current Native encounter menu marks it available and enabled.");
        var leavePreferredState = (JsonObject)noSendTroopsState.DeepClone();
        leavePreferredState["availableMenuOptions"]![2]!["enabled"] = true;
        leavePreferredState["availableMenuOptions"]![2]!["available"] = true;
        var leavePreferredCatalog = BuildActionCatalog(leavePreferredState, candidates, "bandit-1", false, true, recoverPlayerCaptivity: true);
        var leavePreferredIds = leavePreferredCatalog.FirstOrDefault()?["argumentValues"]?["OptionId"] as JsonArray;
        if (leavePreferredIds?.Count != 1 || leavePreferredIds[0]?.GetValue<string>() != "leave")
            throw new AgentHostException("battle-loop-self-test-leave-prioritized-over-surrender", "When Native Leave is enabled, it remains the no-capture fallback and surrender must not be offered.");
        results.Add(new { scenario = "battle-loop-surrenders-only-as-last-resort-in-explicit-captivity-recovery-mode", passed = true });
        var encounterLeftMap = new JsonObject
        {
            ["context"] = new JsonObject { ["gameState"] = "MapState", ["menuId"] = null, ["escapeMenuOpen"] = false, ["inquiryOpen"] = false,
                ["encounterActive"] = false, ["battleSimulation"] = null, ["captivity"] = new JsonObject { ["isCaptive"] = false } },
            ["partyScreen"] = null, ["inventoryScreen"] = null
        };
        if (!IsVerifiedMapTerminalAfterNativeEncounterLeave(encounterLeftMap) ||
            IsVerifiedMapTerminalAfterNativeEncounterLeave(noSendTroopsState))
            throw new AgentHostException("battle-loop-self-test-native-leave-postcondition-not-verified", "Native Leave completion requires a fresh encounter-free Campaign Map; an active encounter is not a terminal state.");
        var leaveOutcome = BuildResult("native-leave-self-test", new FakeBattleSimulationDecisionProvider(), "interrupted", 1, 1, 0, 0,
            "native-encounter-left-no-battle", "Native Leave ended the encounter without BattleSimulation.", "native-encounter-left-no-battle",
            5.0, null, new JsonObject { ["campaignDay"] = 5.1, ["timeControlMode"] = "Stop", ["state"] = encounterLeftMap },
            new JsonArray(), new JsonArray(), 10, 10, "unknown", false, "bandit-1", false, null, false, false, null, nativeEncounterLeft: true);
        var capturedAfterLeave = new JsonObject
        {
            ["context"] = new JsonObject { ["gameState"] = "MapState", ["menuId"] = "prisoner_wait", ["escapeMenuOpen"] = false, ["inquiryOpen"] = false,
                ["encounterActive"] = false, ["battleSimulation"] = null, ["captivity"] = new JsonObject { ["isCaptive"] = true, ["currentMenuId"] = "prisoner_wait", ["ransomOfferVisible"] = false } },
            ["availableMenuOptions"] = new JsonArray(), ["partyScreen"] = null, ["inventoryScreen"] = null
        };
        var captiveLeaveOutcome = BuildResult("native-leave-capture-self-test", new FakeBattleSimulationDecisionProvider(), "interrupted", 1, 1, 0, 0,
            "native-encounter-left-no-battle", "Native Leave ended the encounter and Native reports captivity.", "native-encounter-left-no-battle",
            5.0, null, new JsonObject { ["campaignDay"] = 5.1, ["timeControlMode"] = "Stop", ["state"] = capturedAfterLeave },
            new JsonArray(), new JsonArray(), 10, 10, "unknown", false, "bandit-1", false, null, false, false, null, nativeEncounterLeft: true);
        if (ReadString(leaveOutcome, "status") != "interrupted" || ReadString(leaveOutcome, "playerOutcome") != "left-encounter-without-battle" ||
            !ReadBoolean(leaveOutcome, "nativeReturnToMapVerified") || ReadBoolean(leaveOutcome, "battleStarted") ||
            ReadDouble(leaveOutcome, "renownDelta", double.NaN) != 0 || ReadString(captiveLeaveOutcome, "playerOutcome") != "captured" ||
            !ReadBoolean(captiveLeaveOutcome, "playerCaptiveAtMapReturn"))
            throw new AgentHostException("battle-loop-self-test-native-leave-outcome-misreported", "Native Leave must be reported as an interrupted non-battle exit with observed Renown, or as captured if its verified return is prisoner_wait.");
        results.Add(new { scenario = "battle-loop-native-leave-is-only-exposed-when-send-troops-is-disabled-and-postcondition-is-reverified", passed = true });

        var banditMeeting = ParseState("MapState", "encounter_meeting", true, null, null);
        banditMeeting["state"]!["context"]!["encounteredPartyId"] = "bandit-1";
        banditMeeting["state"]!["context"]!["conversation"] = new JsonObject
        {
            ["sentenceText"] = "Well well, look at this!",
            ["options"] = new JsonArray(new JsonObject { ["id"] = "bandit_start_defender_1", ["clickable"] = true }, new JsonObject { ["id"] = "bandit_toll", ["clickable"] = true })
        };
        var meetingActions = BuildActionCatalog(banditMeeting["state"]!.AsObject(), candidates, "bandit-1", false, true);
        if (meetingActions.Count != 1 || ReadString(meetingActions[0] as JsonObject, "action") != "dialogueSelect")
            throw new AgentHostException("battle-loop-self-test-bandit-fight-dialogue-not-listed", "The Native Bandit meeting must expose only its current Fight response, not toll dialogue.");
        var meetingOptionValues = meetingActions[0]?["argumentValues"]?["OptionId"] as JsonArray;
        if (meetingOptionValues?.Count != 1 || meetingOptionValues[0]?.GetValue<string>() != "bandit_start_defender_1")
            throw new AgentHostException("battle-loop-self-test-bandit-option-catalog-not-exact", "The Bandit dialogue action must list only the current allowed Native fight option.");
        var toll = new JsonObject { ["action"] = "dialogueSelect", ["arguments"] = new JsonObject { ["OptionId"] = "bandit_toll" } };
        if (TryResolveDecision(toll, meetingActions, new JsonArray(), banditMeeting["state"]!.AsObject(), candidates, "bandit-1", out _, out _, out _, out _))
            throw new AgentHostException("battle-loop-self-test-bandit-toll-choice-accepted", "A bandit toll option must not be mistaken for the requested BattleSimulation path.");

        banditMeeting["state"]!["context"]!["conversation"] = new JsonObject
        {
            ["sentenceText"] = "If you surrender, I'll let you go; otherwise prepare for battle!",
            ["options"] = new JsonArray(
                new JsonObject { ["id"] = "common_encounter_ultimatum", ["clickable"] = true },
                new JsonObject { ["id"] = "common_encounter_fight", ["clickable"] = true },
                new JsonObject { ["id"] = "bandit_start_barter", ["clickable"] = true })
        };
        var banditThreatActions = BuildActionCatalog(banditMeeting["state"]!.AsObject(), candidates, "bandit-1", false, true);
        var threatOptionValues = banditThreatActions[0]?["argumentValues"]?["OptionId"] as JsonArray;
        var issueUltimatum = new JsonObject { ["action"] = "dialogueSelect", ["arguments"] = new JsonObject { ["OptionId"] = "common_encounter_ultimatum" } };
        if (threatOptionValues?.Count != 1 || threatOptionValues[0]?.GetValue<string>() != "common_encounter_ultimatum" ||
            !TryResolveDecision(issueUltimatum, banditThreatActions, new JsonArray(), banditMeeting["state"]!.AsObject(), candidates, "bandit-1", out _, out _, out _, out _))
            throw new AgentHostException("battle-loop-self-test-bandit-threat-path-not-listed", "A Native player-threat response must be allowed when the observed hostile Bandit meeting exposes it.");
        foreach (var disallowedBanditResponse in new[] { "common_encounter_fight", "bandit_start_barter" })
        {
            var disallowed = new JsonObject { ["action"] = "dialogueSelect", ["arguments"] = new JsonObject { ["OptionId"] = disallowedBanditResponse } };
            if (TryResolveDecision(disallowed, banditThreatActions, new JsonArray(), banditMeeting["state"]!.AsObject(), candidates, "bandit-1", out _, out _, out _, out _))
                throw new AgentHostException("battle-loop-self-test-bandit-release-or-barter-accepted", "The Native let-the-bandits-go and Barter options must stay unavailable in the battle-growth slice.");
        }

        banditMeeting["state"]!["context"]!["conversation"] = new JsonObject
        {
            ["sentenceText"] = "We're in no shape to fight. We're at your mercy.",
            ["options"] = new JsonArray(
                new JsonObject { ["id"] = "bandit_start_defender_3", ["textId"] = WeakPartySurrenderResponseTextId, ["clickable"] = true },
                new JsonObject { ["id"] = "bandit_start_defender_2", ["textId"] = "aQYMefHU", ["clickable"] = true })
        };
        var ordinaryWeakPartyOptions = BuildActionCatalog(banditMeeting["state"]!.AsObject(), candidates, "bandit-1", false, true,
            recoverPlayerCaptivity: false);
        var recoveryWeakPartyOptions = BuildActionCatalog(banditMeeting["state"]!.AsObject(), candidates, "bandit-1", false, true,
            recoverPlayerCaptivity: true);
        var weakPartySurrenderDecision = new JsonObject { ["action"] = "dialogueSelect", ["arguments"] = new JsonObject { ["OptionId"] = "bandit_start_defender_3" } };
        var weakPartyNegotiationDecision = new JsonObject { ["action"] = "dialogueSelect", ["arguments"] = new JsonObject { ["OptionId"] = "bandit_start_defender_2" } };
        var recoveryOptionIds = recoveryWeakPartyOptions.OfType<JsonObject>().FirstOrDefault(action => ReadString(action, "action") == "dialogueSelect")?
            ["argumentValues"]?["OptionId"] as JsonArray;
        if (ordinaryWeakPartyOptions.Count != 0 || recoveryOptionIds?.Count != 1 || recoveryOptionIds[0]?.GetValue<string>() != "bandit_start_defender_3" ||
            !TryResolveDecision(weakPartySurrenderDecision, recoveryWeakPartyOptions, new JsonArray(), banditMeeting["state"]!.AsObject(), candidates, "bandit-1",
                out _, out _, out _, out _, recoverPlayerCaptivity: true) ||
            TryResolveDecision(weakPartySurrenderDecision, recoveryWeakPartyOptions, new JsonArray(), banditMeeting["state"]!.AsObject(), candidates, "bandit-1",
                out _, out _, out _, out _, recoverPlayerCaptivity: false) ||
            TryResolveDecision(weakPartyNegotiationDecision, recoveryWeakPartyOptions, new JsonArray(), banditMeeting["state"]!.AsObject(), candidates, "bandit-1",
                out _, out _, out _, out _, recoverPlayerCaptivity: true))
            throw new AgentHostException("battle-loop-self-test-weak-party-surrender-fallback-scope-failed", "Only a recovery-enabled Host may use the current Native weak-party surrender response when Fight is absent; safe-passage/barter stays outside this battle route.");
        results.Add(new { scenario = "battle-and-captivity-recovery-allows-native-weak-party-surrender-only-when-no-fight-choice-exists", passed = true });
        banditMeeting["state"]!["context"]!["conversation"] = new JsonObject
        {
            ["sentenceText"] = "You have no choice but to surrender!",
            ["options"] = new JsonArray(
                new JsonObject { ["id"] = "common_bandit_surrender_accept", ["clickable"] = true },
                new JsonObject { ["id"] = "common_bandit_surrender_declined", ["clickable"] = true })
        };
        var declineSurrenderActions = BuildActionCatalog(banditMeeting["state"]!.AsObject(), candidates, "bandit-1", false, true);
        var declineOptionValues = declineSurrenderActions[0]?["argumentValues"]?["OptionId"] as JsonArray;
        var declineSurrender = new JsonObject { ["action"] = "dialogueSelect", ["arguments"] = new JsonObject { ["OptionId"] = "common_bandit_surrender_declined" } };
        var acceptSurrender = new JsonObject { ["action"] = "dialogueSelect", ["arguments"] = new JsonObject { ["OptionId"] = "common_bandit_surrender_accept" } };
        if (declineOptionValues?.Count != 1 || declineOptionValues[0]?.GetValue<string>() != "common_bandit_surrender_declined" ||
            !TryResolveDecision(declineSurrender, declineSurrenderActions, new JsonArray(), banditMeeting["state"]!.AsObject(), candidates, "bandit-1", out _, out _, out _, out _) ||
            TryResolveDecision(acceptSurrender, declineSurrenderActions, new JsonArray(), banditMeeting["state"]!.AsObject(), candidates, "bandit-1", out _, out _, out _, out _))
            throw new AgentHostException("battle-loop-self-test-bandit-surrender-decision-not-bounded", "A Native surrender roll must permit only the current decline response, never accepting surrender.");
        results.Add(new { scenario = "battle-loop-supports-bandit-initiated-threat-and-decline-surrender", passed = true });

        banditMeeting["state"]!["context"]!["conversation"] = new JsonObject { ["sentenceText"] = "Prepare yourself.", ["options"] = new JsonArray() };
        var responseActions = BuildActionCatalog(banditMeeting["state"]!.AsObject(), candidates, "bandit-1", false, true);
        if (responseActions.Count != 1 || ReadString(responseActions[0] as JsonObject, "action") != "dialogueContinue")
            throw new AgentHostException("battle-loop-self-test-native-fight-response-not-continued", "A no-choice Native fight response line must expose only dialogueContinue.");
        banditMeeting["state"]!["context"]!["conversation"] = new JsonObject
        {
            ["sentenceText"] = "Pay the toll.",
            ["options"] = new JsonArray(new JsonObject { ["id"] = "bandit_toll", ["clickable"] = true })
        };
        if (BuildActionCatalog(banditMeeting["state"]!.AsObject(), candidates, "bandit-1", false, true).Count != 0)
            throw new AgentHostException("battle-loop-self-test-toll-only-meeting-not-stopped", "A toll-only meeting must not expose a toll payment action or invent a Fight option.");
        results.Add(new { scenario = "battle-loop-uses-native-bandit-fight-dialogue-and-rejects-toll", passed = true });

        var unfinished = ParseState("MapState", null, true, null, new JsonObject { ["finished"] = false, ["battleState"] = "AttackerVictory" });
        var finished = BuildActionCatalog(unfinished["state"]!.AsObject(), new JsonArray(), "bandit-1", true, true);
        if (finished.Count != 1 || ReadString(finished[0] as JsonObject, "action") != "battleSkip")
            throw new AgentHostException("battle-loop-self-test-skip-not-listed", "An unfinished Native BattleSimulation must expose only battleSkip.");
        unfinished["state"]!["context"]!["battleSimulation"]!["finished"] = true;
        var finish = BuildActionCatalog(unfinished["state"]!.AsObject(), new JsonArray(), "bandit-1", true, true);
        if (finish.Count != 1 || ReadString(finish[0] as JsonObject, "action") != "battleFinish")
            throw new AgentHostException("battle-loop-self-test-finish-not-listed", "A finished Native BattleSimulation must expose only battleFinish.");
        results.Add(new { scenario = "battle-loop-preserves-native-simulation-state-machine", passed = true });

        var party = new JsonObject { ["context"] = new JsonObject { ["gameState"] = "PartyState" }, ["partyScreen"] = new JsonObject
        {
            ["mode"] = "Loot", ["canDone"] = true,
            ["leftMembers"] = new JsonArray(new JsonObject { ["troopId"] = "caravan_guard_empire", ["count"] = 1, ["transferable"] = true }),
            ["leftPrisoners"] = new JsonArray(new JsonObject { ["troopId"] = "mounted_ransacker", ["count"] = 5, ["transferable"] = true }),
            ["rightMembers"] = new JsonArray(new JsonObject { ["troopId"] = "main_hero", ["count"] = 1, ["transferable"] = false }),
            ["rightPrisoners"] = new JsonArray(new JsonObject { ["troopId"] = "looter", ["count"] = 16, ["transferable"] = true }),
            ["rightMemberLimit"] = 20,
            ["rightPrisonerLimit"] = 18
        } };
        var partyActions = BuildActionCatalog(party, new JsonArray(), null, true, true);
        var takeAllAction = partyActions.OfType<JsonObject>().FirstOrDefault(action => ReadString(action, "action") == "partyTakeAll");
        var takeAllTypes = takeAllAction?["argumentValues"]?["TroopType"] as JsonArray;
        if (takeAllTypes?.Count != 1 || !takeAllTypes.OfType<JsonValue>().Any(value => value.GetValue<string>() == "members") ||
            takeAllTypes.OfType<JsonValue>().Any(value => value.GetValue<string>() == "prisoners") || !CatalogContains(partyActions, "partyScreenDone"))
            throw new AgentHostException("battle-loop-self-test-party-aftermath-not-listed", "Native take-all may be listed only when the whole currently transferable roster fits the current receive limit; single-row prisoner transfers remain available.");
        var singleTransfer = partyActions.OfType<JsonObject>().FirstOrDefault(action => ReadString(action, "action") == "partyLootTransferOne");
        var transferPairs = singleTransfer?["argumentPairs"] as JsonArray;
        if (transferPairs?.Count != 2 || !transferPairs.OfType<JsonObject>().Any(pair => ReadString(pair, "TroopId") == "caravan_guard_empire" && ReadString(pair, "TroopType") == "members") ||
            !transferPairs.OfType<JsonObject>().Any(pair => ReadString(pair, "TroopId") == "mounted_ransacker" && ReadString(pair, "TroopType") == "prisoners"))
            throw new AgentHostException("battle-loop-self-test-loot-single-transfer-pairs-missing", "Loot single transfers must bind exact currently visible member/prisoner ids to their Native roster types.");
        var validSingleTransfer = new JsonObject { ["action"] = "partyLootTransferOne", ["arguments"] = new JsonObject { ["TroopId"] = "mounted_ransacker", ["TroopType"] = "prisoners" } };
        if (!TryResolveDecision(validSingleTransfer, partyActions, new JsonArray(), party, new JsonArray(), null, out var singleAction, out var singleArguments, out _, out _, recoverPlayerCaptivity: false) ||
            singleAction != "partyLootTransferOne" || ReadString(singleArguments, "troopId") != "mounted_ransacker" || ReadString(singleArguments, "troopType") != "prisoners")
            throw new AgentHostException("battle-loop-self-test-loot-single-transfer-current-pair-not-resolvable", "The Host must resolve one exact current Native Loot prisoner row.");
        var staleSingleTransfer = new JsonObject { ["action"] = "partyLootTransferOne", ["arguments"] = new JsonObject { ["TroopId"] = "unobserved", ["TroopType"] = "prisoners" } };
        if (TryResolveDecision(staleSingleTransfer, partyActions, new JsonArray(), party, new JsonArray(), null, out _, out _, out _, out _, recoverPlayerCaptivity: false))
            throw new AgentHostException("battle-loop-self-test-loot-single-transfer-stale-row-accepted", "The Host must reject stale or hidden Loot rows before any Native transfer.");
        results.Add(new { scenario = "battle-loop-binds-single-loot-transfer-to-current-visible-row-and-roster-type", passed = true });
        var invalidLootType = new JsonObject { ["action"] = "partyTakeAll", ["arguments"] = new JsonObject { ["TroopType"] = "looter" } };
        if (TryResolveDecision(invalidLootType, partyActions, new JsonArray(), party, new JsonArray(), null, out _, out _, out _, out var invalidLootRejection, recoverPlayerCaptivity: false) ||
            !invalidLootRejection.Contains("members or prisoners", StringComparison.Ordinal))
            throw new AgentHostException("battle-loop-self-test-loot-type-alias-not-rejected", "The displayed troop class 'looter' must not be mistaken for the current Native PartyScreen roster type.");
        foreach (var validLootType in new[] { "members" })
        {
            var validLoot = new JsonObject { ["action"] = "partyTakeAll", ["arguments"] = new JsonObject { ["TroopType"] = validLootType } };
            if (!TryResolveDecision(validLoot, partyActions, new JsonArray(), party, new JsonArray(), null, out var resolvedLootAction, out var resolvedLootArguments, out _, out _, recoverPlayerCaptivity: false) ||
                resolvedLootAction != "partyTakeAll" || ReadString(resolvedLootArguments, "troopType") != validLootType)
                throw new AgentHostException("battle-loop-self-test-native-loot-type-not-resolvable", "Each currently observed transferable Native roster type must normalize to the exact PartyScreen handler value.");
        }
        var overLimitPrisonerTakeAll = new JsonObject { ["action"] = "partyTakeAll", ["arguments"] = new JsonObject { ["TroopType"] = "prisoners" } };
        if (TryResolveDecision(overLimitPrisonerTakeAll, partyActions, new JsonArray(), party, new JsonArray(), null, out _, out _, out _, out _, recoverPlayerCaptivity: false))
            throw new AgentHostException("battle-loop-self-test-over-limit-prisoner-take-all-accepted", "Take-all prisoners must be omitted and rejected when the full current left stack exceeds Native capacity; single transfers remain available.");
        results.Add(new { scenario = "battle-loop-suppresses-whole-prisoner-take-when-native-capacity-would-be-exceeded", passed = true });
        var inventory = new JsonObject { ["context"] = new JsonObject { ["gameState"] = "InventoryState" }, ["inventoryScreen"] = new JsonObject { ["mode"] = "Loot", ["lootItemCount"] = 2 } };
        var inventoryActions = BuildActionCatalog(inventory, new JsonArray(), null, true, true);
        if (inventoryActions.Count != 1 || ReadString(inventoryActions[0] as JsonObject, "action") != "inventoryTakeAll")
            throw new AgentHostException("battle-loop-self-test-inventory-done-skips-loot", "Inventory Done must remain unavailable while Native battle loot remains.");
        inventory["state"] = new JsonObject { ["context"] = new JsonObject { ["gameState"] = "InventoryState" }, ["inventoryScreen"] = new JsonObject { ["mode"] = "Loot", ["lootItemCount"] = 0 } };
        var emptyInventoryActions = BuildActionCatalog(inventory["state"]!.AsObject(), new JsonArray(), null, true, true);
        if (emptyInventoryActions.Count != 1 || ReadString(emptyInventoryActions[0] as JsonObject, "action") != "inventoryDone")
            throw new AgentHostException("battle-loop-self-test-inventory-done-not-listed", "Native Inventory Done may only be listed after the observed Loot roster is empty.");
        var capturedWait = new JsonObject
        {
            ["context"] = new JsonObject { ["gameState"] = "MapState", ["menuId"] = "prisoner_wait", ["encounterActive"] = false, ["battleSimulation"] = null,
                ["captivity"] = new JsonObject { ["isCaptive"] = true, ["currentMenuId"] = "prisoner_wait", ["ransomOfferVisible"] = false } },
            ["availableMenuOptions"] = new JsonArray(), ["partyScreen"] = null, ["inventoryScreen"] = null
        };
        if (!IsVerifiedMapTerminalAfterBattle(capturedWait, battleStarted: true) || BuildControlCatalog(capturedWait, null, battleWasStarted: true).Count != 1)
            throw new AgentHostException("battle-loop-self-test-captive-map-terminal-missing", "A completed Native battle ending in no-option prisoner_wait must be reported as captured, not misreported as a Host dead end.");
        if (BuildControlCatalog(capturedWait, null, battleWasStarted: true, recoverPlayerCaptivity: true).Count != 0 ||
            !ShouldPassivelyWaitForCaptivity(capturedWait, recoverPlayerCaptivity: true))
            throw new AgentHostException("battle-loop-self-test-captive-wait-was-completed", "When captivity recovery is in scope, a no-option prisoner_wait must passively re-observe and must not expose done.");
        capturedWait["availableMenuOptions"] = new JsonArray(new JsonObject { ["id"] = "captivity_ransom", ["available"] = true, ["enabled"] = true });
        if (IsVerifiedMapTerminalAfterBattle(capturedWait, battleStarted: true))
            throw new AgentHostException("battle-loop-self-test-captive-choice-ignored", "A visible Native captivity choice must not be silently ignored as a completed terminal state.");
        var ransomOffer = ParseState("MapState", "menu_captivity_end_propose_ransom_wilderness", false, null, null);
        ransomOffer["state"]!["context"]!["captivity"] = new JsonObject
        {
            ["isCaptive"] = true,
            ["currentMenuId"] = "menu_captivity_end_propose_ransom_wilderness",
            ["ransomOfferVisible"] = true,
            ["currentVisibleRansomAmount"] = 331
        };
        ransomOffer["state"]!["availableMenuOptions"] = new JsonArray(
            new JsonObject { ["id"] = "mno_captivity_end_ransom_accept", ["available"] = true, ["enabled"] = true },
            new JsonObject { ["id"] = "captivity_end_ransom_deny", ["available"] = true, ["enabled"] = true });
        var ransomActions = BuildActionCatalog(ransomOffer["state"]!.AsObject(), new JsonArray(), null, true, true, recoverPlayerCaptivity: true);
        var acceptRansom = new JsonObject { ["action"] = "menuSelect", ["arguments"] = new JsonObject { ["MenuId"] = "menu_captivity_end_propose_ransom_wilderness", ["OptionId"] = "mno_captivity_end_ransom_accept" } };
        if (ransomActions.Count != 1 || ReadString(ransomActions[0] as JsonObject, "action") != "menuSelect" ||
            !TryResolveDecision(acceptRansom, ransomActions, new JsonArray(), ransomOffer["state"]!.AsObject(), new JsonArray(), null,
                out var captivityAction, out _, out _, out _, recoverPlayerCaptivity: true) || captivityAction != "menuSelect")
            throw new AgentHostException("battle-loop-self-test-native-ransom-choice-not-listed", "The Host must expose the current Native ransom menu through its original enabled menuSelect option.");
        var inventedRansom = new JsonObject { ["action"] = "menuSelect", ["arguments"] = new JsonObject { ["MenuId"] = "menu_captivity_end_propose_ransom_wilderness", ["OptionId"] = "str_order_attack" } };
        if (TryResolveDecision(inventedRansom, ransomActions, new JsonArray(), ransomOffer["state"]!.AsObject(), new JsonArray(), null,
                out _, out _, out _, out _, recoverPlayerCaptivity: true))
            throw new AgentHostException("battle-loop-self-test-invented-captivity-option-accepted", "A Battle menu option must never be accepted as a Native captivity choice.");
        results.Add(new { scenario = "battle-loop-captivity-waits-for-native-and-binds-ransom-choice", passed = true });
        results.Add(new { scenario = "battle-loop-processes-observed-party-and-inventory-aftermath", passed = true });
        return results;
    }

    internal static async Task<IReadOnlyList<object>> RunTransportSelfTestsAsync()
    {
        const string actionNames = "[\"mapPartyTargets\",\"pursue\",\"dialogueSelect\",\"dialogueContinue\",\"menuSelect\",\"battleSkip\",\"battleFinish\",\"partyTakeAll\",\"partyLootTransferOne\",\"partyScreenDone\",\"inventoryTakeAll\",\"inventoryDone\"]";
        using var request = JsonDocument.Parse("{\"runId\":\"selftest-battle\",\"goal\":\"Resolve one visible bandit battle with Send Troops and verify outcomes.\",\"parentProcessId\":321,\"maxDecisions\":30,\"maxElapsedSeconds\":20,\"allowedActionNames\":" + actionNames + "}");
        var client = new FakeBattleSimulationNativeClient();
        var provider = new FakeBattleSimulationDecisionProvider();
        var priorTrace = new JsonArray(new JsonObject { ["stage"] = "goal-classifier", ["decision"] = new JsonObject { ["goalClassification"] = "supported-battle-simulation" } });
        var priorRoutes = new JsonArray(new JsonObject { ["decision"] = 1, ["requestedModelId"] = provider.ModelId, ["routedVia"] = "fake-test" });
        var result = await RunAsync(request.RootElement, client, provider, CancellationToken.None, priorDecisions: 1,
            priorPromptTokens: 11, priorCompletionTokens: 3, priorTrace: priorTrace, priorProviderRouteHistory: priorRoutes);
        if (ReadString(result, "status") != "completed" || ReadString(result, "termination") != "battle-resolved-and-verified" ||
            ReadInt(result, "decisions", 0) != 15 || ReadInt(result, "actionsExecuted", 0) != 12 || provider.CallCount != 14 ||
            ReadString(result, "targetPartyId") != "bandit-1" || ReadDouble(result, "renownBefore", double.NaN) != 10 ||
            ReadDouble(result, "renownAfter", double.NaN) != 10 || ReadInt(result, "explicitClockActionCount", -1) != 0 ||
            ReadString(result, "providerConfigurationSource") != provider.ConfigurationSource || ReadString(result, "playerOutcome") != "resolved-native-battle" ||
            !ReadBoolean(result, "nativeReturnToMapVerified") || client.Actions.Contains("pause") || client.Actions.Contains("advance") ||
            result["trace"] is not JsonArray trace || trace.Count != 15 || result["providerRouteHistory"] is not JsonArray routes || routes.Count != 15)
        {
            var traceSummary = string.Join(" | ", (result["trace"] as JsonArray ?? new JsonArray()).OfType<JsonObject>().Select(x =>
                $"{ReadInt(x, "iteration", 0)}:{ReadString(x["decision"] as JsonObject, "action") ?? ReadString(x["decision"] as JsonObject, "control") ?? (ReadBoolean(x["decision"] as JsonObject, "done") ? "done" : "")}:" +
                $"{ReadString(x["actionReceipt"] as JsonObject, "action") ?? "-"}:{ReadString(x["decisionFeedback"] as JsonObject, "message") ?? "-"}"));
            throw new AgentHostException("battle-loop-self-test-native-cycle-failed", $"Fake Native cycle mismatch: status={ReadString(result, "status")}, termination={ReadString(result, "termination")}, failure={ReadString(result, "failure")}, decisions={ReadInt(result, "decisions", -1)}, actions={ReadInt(result, "actionsExecuted", -1)}, calls={provider.CallCount}, target={ReadString(result, "targetPartyId")}, returnMap={ReadBoolean(result, "nativeReturnToMapVerified")}, path={traceSummary}.");
        }
        if (!client.Actions.SequenceEqual(new[] { "mapPartyTargets", "pursue", "mapPartyTargets", "dialogueSelect", "dialogueContinue", "menuSelect", "battleSkip", "battleFinish", "partyTakeAll", "partyScreenDone", "inventoryTakeAll", "inventoryDone" }))
            throw new AgentHostException("battle-loop-self-test-native-order-failed", "The battle loop emitted an unexpected Native action order.");

        var escapeClient = new FakeBattleSimulationNativeClient(simulateNativeEscape: true);
        var escapeProvider = new FakeTryToGetAwayDecisionProvider();
        var escapeResult = await RunAsync(request.RootElement, escapeClient, escapeProvider, CancellationToken.None);
        if (ReadString(escapeResult, "status") != "completed" ||
            ReadString(escapeResult, "termination") != "native-try-to-get-away-completed" ||
            ReadString(escapeResult, "playerOutcome") != "escaped-with-sacrifice" ||
            ReadBoolean(escapeResult, "battleStarted") || ReadBoolean(escapeResult, "nativeEscapeCompleted") != true ||
            ReadBoolean(escapeResult, "nativeReturnToMapVerified") != true ||
            ReadDouble(escapeResult, "renownBefore", double.NaN) != 10 || ReadDouble(escapeResult, "renownAfter", double.NaN) != 10 ||
            escapeProvider.CallCount != 9 || escapeProvider.WarningRequest? ["observation"]? ["state"]? ["context"]? ["encounterEscape"]? ["nativeTroopsSacrificedForTry"]?.GetValue<int>() != 7 ||
            escapeClient.Actions.SequenceEqual(new[] { "mapPartyTargets", "pursue", "mapPartyTargets", "dialogueSelect", "dialogueContinue", "menuSelect", "menuSelect", "menuSelect" }) != true ||
            escapeClient.Actions.Contains("battleSkip") || escapeClient.Actions.Contains("battleFinish"))
            throw new AgentHostException("battle-loop-native-escape-not-integrated", $"The model must be able to inspect the original risk warning, choose Try-to-get-away, accept its observed cost, continue its debrief, and return without claiming BattleSimulation/Renown. status={ReadString(escapeResult, "status")}, termination={ReadString(escapeResult, "termination")}, outcome={ReadString(escapeResult, "playerOutcome")}, actions={string.Join(",", escapeClient.Actions)}.");
        var visibleThreatClient = new FakeBattleSimulationNativeClient(visibleHostileAtStart: true);
        var visibleThreatProvider = new FakeBattleSimulationDecisionProvider();
        var visibleThreatResult = await RunAsync(request.RootElement, visibleThreatClient, visibleThreatProvider, CancellationToken.None);
        var visibleThreatTrace = visibleThreatResult["trace"] as JsonArray;
        if (ReadString(visibleThreatResult, "status") != "completed" ||
            !visibleThreatClient.ClockActions.SequenceEqual(["pause"]) ||
            ReadInt(visibleThreatResult, "explicitClockActionCount", -1) != 1 ||
            ReadInt(visibleThreatResult, "actionsExecuted", -1) != 13 ||
            visibleThreatTrace?.FirstOrDefault() is not JsonObject pauseStep ||
            ReadString(pauseStep, "stage") != "visible-hostile-decision-paused-before-model" ||
            ReadString(visibleThreatProvider.FirstRequest?["observation"]?["state"]?["context"] as JsonObject, "timeControlMode") != "Stop" ||
            (visibleThreatProvider.FirstRequest?["observation"]?["state"]?["nearbyParties"] as JsonArray)?.Count != 1 ||
            !visibleThreatTrace.OfType<JsonObject>().Any(step => ReadString(step["decision"] as JsonObject, "action") == "pursue"))
            throw new AgentHostException("battle-loop-visible-threat-pause-before-model-failed", "A visible, unpursued bandit must trigger a distinct audited Native Pause before the first model decision; the model must then decide using the still-visible party. Already-active pursuits and all ordinary movement remain on Native clock behavior.");

        var incidentClient = new FakeBattleSimulationNativeClient(mapIncidentAtStart: true);
        var incidentProvider = new FakeBattleSimulationDecisionProvider();
        var incidentInterruptedBattle = await RunAsync(request.RootElement, incidentClient, incidentProvider, CancellationToken.None);
        if (ReadString(incidentInterruptedBattle, "status") != "failed" ||
            ReadString(incidentInterruptedBattle, "termination") != "native-map-incident-interrupted-battle-planning" ||
            incidentProvider.CallCount != 0 || incidentClient.Actions.Count != 0 || incidentClient.ClockActions.Count != 0 ||
            incidentInterruptedBattle["trace"] is not JsonArray incidentTrace ||
            !incidentTrace.OfType<JsonObject>().Any(step => ReadString(step, "stage") == "battle-planning-interrupted-by-native-map-incident" &&
                ReadBoolean(step, "modelDecisionMade") == false && ReadBoolean(step, "nativeActionMade") == false))
            throw new AgentHostException("battle-loop-map-incident-was-not-left-to-parent", "A Native map incident must interrupt the battle child before any model or movement action so the parent can resolve the current incident and replan.");
        var mapConversationClient = new FakeBattleSimulationNativeClient(mapConversationAtStart: true);
        var mapConversationProvider = new FakeBattleSimulationDecisionProvider();
        var mapConversationResult = await RunAsync(request.RootElement, mapConversationClient, mapConversationProvider, CancellationToken.None);
        if (ReadString(mapConversationResult, "status") != "completed" ||
            ReadInt(mapConversationResult, "actionsExecuted", 0) != 13 || mapConversationProvider.CallCount != 14 ||
            mapConversationClient.Actions.Count != 13 || mapConversationClient.Actions[0] != "dialogueContinue" ||
            !((mapConversationResult["trace"] as JsonArray)?.OfType<JsonObject>().Any(step => ReadString(step, "stage") == "native-map-conversation-no-choice-continued" &&
                ReadBoolean(step, "modelDecisionMade") == false) ?? false) ||
            ReadString(mapConversationProvider.FirstRequest?["observation"]?["state"]?["context"] as JsonObject, "gameState") != "MapState" ||
            mapConversationProvider.FirstRequest?["observation"]?["state"]?["context"]?["conversation"] is not null)
            throw new AgentHostException("battle-loop-map-conversation-native-continue-failed", "The Host must advance only the active no-choice Native Map conversation before requesting the Renown decision, then resume from the fresh Map state. status=" + ReadString(mapConversationResult, "status") + "; termination=" + ReadString(mapConversationResult, "termination") + "; actions=" + ReadInt(mapConversationResult, "actionsExecuted", -1) + "; providerCalls=" + mapConversationProvider.CallCount + "; nativeActions=" + string.Join(",", mapConversationClient.Actions) + "; firstRequestConversation=" + (mapConversationProvider.FirstRequest?["observation"]?["state"]?["context"]?["conversation"] is not null) + "; traceStages=" + string.Join(",", (mapConversationResult["trace"] as JsonArray)?.OfType<JsonObject>().Select(step => ReadString(step, "stage") ?? ReadString(step["decision"] as JsonObject, "action") ?? "step") ?? Array.Empty<string>()));
        var inquiryClient = new FakeBattleSimulationNativeClient(simulatePartyInquiry: true);
        var inquiryProvider = new FakeBattleSimulationDecisionProvider(simulatePartyInquiry: true);
        var inquiryRequestNode = JsonNode.Parse(request.RootElement.GetRawText())!.AsObject();
        inquiryRequestNode["parentGoal"] = "Complete the original StoryMode Establish Your Clan objective set.";
        inquiryRequestNode["parentEycObjectives"] = new JsonObject
        {
            ["partySize"] = new JsonObject { ["current"] = 11, ["target"] = 25 },
            ["renown"] = new JsonObject { ["current"] = 21.378, ["target"] = 50 }
        };
        using var inquiryRequest = JsonDocument.Parse(inquiryRequestNode.ToJsonString());
        var partyInquiryResult = await RunAsync(inquiryRequest.RootElement, inquiryClient, inquiryProvider, CancellationToken.None,
            inquiryClient: inquiryClient);
        if (ReadString(partyInquiryResult, "status") != "completed" || ReadString(partyInquiryResult, "termination") != "battle-resolved-and-verified" ||
            ReadString(partyInquiryResult, "playerOutcome") != "resolved-native-battle" || inquiryClient.LastInquiryChoice != "negative" ||
            !inquiryClient.Actions.SequenceEqual(new[] { "mapPartyTargets", "pursue", "mapPartyTargets", "dialogueSelect", "dialogueContinue", "menuSelect", "battleSkip", "battleFinish", "partyTakeAll", "partyScreenDone", "partyTakeAll", "partyScreenDone", "inventoryTakeAll", "inventoryDone" }) ||
            inquiryProvider.LastInquiryRequest?[
                "observation"]?["state"]?["partyScreen"]?["leftMembers"]?[0]?["count"]?.GetValue<int>() != 5 ||
            ReadString(inquiryProvider.LastInquiryRequest?["observation"]?["state"]?["context"] as JsonObject, "gameState") != "PartyState" ||
            !ReadString(inquiryProvider.LastInquiryRequest, "goal")!.Contains("11", StringComparison.Ordinal) ||
            ReadInt(partyInquiryResult, "explicitClockActionCount", -1) != 0 ||
            partyInquiryResult["trace"] is not JsonArray inquiryTrace || !inquiryTrace.OfType<JsonObject>().Any(line => ReadString(line, "stage") == "postbattle-native-inquiry"))
            throw new AgentHostException("battle-loop-self-test-party-inquiry-goal-recovery-failed", $"The battle loop did not resolve a current PartyState Inquiry from EYC/roster context and resume Native loot: status={ReadString(partyInquiryResult, "status")}, termination={ReadString(partyInquiryResult, "termination")}, choice={inquiryClient.LastInquiryChoice}, actions={string.Join(",", inquiryClient.Actions)}.");

        if (ReadInt(partyInquiryResult, "actionsExecuted", 0) != 15)
            throw new AgentHostException("battle-loop-self-test-accepted-done-action-not-counted", "Native PartyScreen Done returns accepted while its leftover Inquiry is open; both the Done action and the subsequent model-chosen inquiry response must count as executed Native actions.");

        var repeatedDoneClient = new FakeBattleSimulationNativeClient(simulatePartyInquiry: true);
        var repeatedDoneProvider = new FakeBattleSimulationDecisionProvider(simulatePartyInquiry: true, repeatPartyScreenDoneAfterDecline: true);
        var repeatedDoneResult = await RunAsync(inquiryRequest.RootElement, repeatedDoneClient, repeatedDoneProvider, CancellationToken.None,
            inquiryClient: repeatedDoneClient);
        var repeatedDoneTrace = repeatedDoneResult["trace"] as JsonArray;
        if (ReadString(repeatedDoneResult, "status") != "completed" || repeatedDoneProvider.CallCount != 18 ||
            !repeatedDoneClient.Actions.SequenceEqual(new[] { "mapPartyTargets", "pursue", "mapPartyTargets", "dialogueSelect", "dialogueContinue", "menuSelect", "battleSkip", "battleFinish", "partyTakeAll", "partyScreenDone", "partyTakeAll", "partyScreenDone", "inventoryTakeAll", "inventoryDone" }) ||
            repeatedDoneTrace?.OfType<JsonObject>().Any(step => ReadString(step["decision"] as JsonObject, "action") == "partyScreenDone" &&
                ReadString(step["decisionFeedback"] as JsonObject, "kind") == "decision-rejected-before-native" &&
                (ReadString(step["decisionFeedback"] as JsonObject, "requiredNextStep") ?? string.Empty).Contains("roster transfer", StringComparison.Ordinal)) != true)
            throw new AgentHostException("battle-loop-self-test-negative-party-inquiry-prevents-done-loop", $"The same party roster must not re-open Done after a negative Inquiry when transfers are available; status={ReadString(repeatedDoneResult, "status")}, providerCalls={repeatedDoneProvider.CallCount}, nativeActions={string.Join(",", repeatedDoneClient.Actions)}.");

        using var cumulativeRequest = JsonDocument.Parse("{\"runId\":\"selftest-battle-after-objective-budget\",\"goal\":\"Resolve one active incident battle after prior objective decisions.\",\"parentProcessId\":321,\"maxDecisions\":320,\"maxElapsedSeconds\":20,\"allowedActionNames\":" + actionNames + "}");
        var cumulativeClient = new FakeBattleSimulationNativeClient();
        var cumulativeProvider = new FakeBattleSimulationDecisionProvider();
        var priorCampaignTrace = new JsonArray();
        var priorCampaignRoutes = new JsonArray();
        for (var prior = 0; prior < 201; prior++)
        {
            priorCampaignTrace.Add(new JsonObject { ["iteration"] = prior + 1, ["stage"] = "prior-objective-decision" });
            priorCampaignRoutes.Add(new JsonObject { ["decision"] = prior + 1, ["requestedModelId"] = cumulativeProvider.ModelId, ["routedVia"] = "prior-objective" });
        }
        var cumulativeBattle = await RunAsync(cumulativeRequest.RootElement, cumulativeClient, cumulativeProvider, CancellationToken.None,
            priorDecisions: 201, priorTrace: priorCampaignTrace, priorProviderRouteHistory: priorCampaignRoutes);
        if (ReadString(cumulativeBattle, "status") != "completed" || ReadInt(cumulativeBattle, "decisions", 0) != 215 ||
            cumulativeProvider.CallCount != 14 || ReadInt(cumulativeBattle, "actionsExecuted", 0) != 12 ||
            (cumulativeBattle["trace"] as JsonArray)?.Count != 215 ||
            (cumulativeBattle["providerRouteHistory"] as JsonArray)?.Count != 215)
            throw new AgentHostException("battle-loop-self-test-cumulative-budget-interruption-failed", "A real-time incident BattleSimulation must retain enough shared decision budget after earlier objective planning/actions and preserve global trace numbering.");
        var recoveryClient = new FakeBattleSimulationNativeClient(simulateCaptivity: true);
        var recoveryProvider = new FakeBattleCaptivityDecisionProvider();
        var recovery = await RunAsync(request.RootElement, recoveryClient, recoveryProvider, CancellationToken.None,
            priorDecisions: 1, priorTrace: priorTrace, priorProviderRouteHistory: priorRoutes,
            recoverPlayerCaptivity: true, passiveCaptivityPollSeconds: 1);
        if (ReadString(recovery, "status") != "completed" || ReadString(recovery, "playerOutcome") != "captured-then-recovered" ||
            !ReadBoolean(recovery, "captivityObserved") || !ReadBoolean(recovery, "captivityRecoveryVerified") ||
            ReadString(recovery, "captivityChoiceOptionId") != "mno_captivity_end_ransom_accept" ||
            ReadInt(recovery, "mainPartyMembersAtReturn", 0) != 1 || !ReadBoolean(recovery, "nativeReturnToMapVerified") ||
            ReadInt(recovery, "explicitClockActionCount", -1) != 0 || recoveryClient.Actions.Contains("pause") || recoveryClient.Actions.Contains("advance") ||
            !recoveryClient.Actions.SequenceEqual(new[] { "mapPartyTargets", "pursue", "mapPartyTargets", "dialogueSelect", "dialogueContinue", "menuSelect", "battleSkip", "battleFinish", "menuSelect" }))
            throw new AgentHostException("battle-loop-self-test-captivity-recovery-failed", $"A fake Native battle-capture-ransom cycle failed: status={ReadString(recovery, "status")}, outcome={ReadString(recovery, "playerOutcome")}, captivity={ReadBoolean(recovery, "captivityObserved")}, recovery={ReadBoolean(recovery, "captivityRecoveryVerified")}, action={ReadString(recovery, "captivityChoiceOptionId")}, actions={string.Join(",", recoveryClient.Actions)}.");
        var surrenderRecoveryClient = new FakeBattleSimulationNativeClient(simulateSurrenderWithoutBattle: true);
        var surrenderRecoveryProvider = new FakeSurrenderRecoveryDecisionProvider();
        var surrenderRecovery = await RunAsync(request.RootElement, surrenderRecoveryClient, surrenderRecoveryProvider, CancellationToken.None,
            recoverPlayerCaptivity: true, passiveCaptivityPollSeconds: 1);
        if (ReadString(surrenderRecovery, "status") != "completed" ||
            ReadString(surrenderRecovery, "termination") != "native-captivity-recovered-without-battle" ||
            ReadString(surrenderRecovery, "playerOutcome") != "captured-then-recovered" ||
            !ReadBoolean(surrenderRecovery, "captivityObserved") || !ReadBoolean(surrenderRecovery, "captivityRecoveryVerified") ||
            ReadBoolean(surrenderRecovery, "battleStarted") || ReadString(surrenderRecovery, "captivityChoiceOptionId") != "mno_captivity_end_ransom_accept" ||
            ReadInt(surrenderRecovery, "mainPartyMembersAtReturn", 0) != 1 || !ReadBoolean(surrenderRecovery, "nativeReturnToMapVerified") ||
            ReadInt(surrenderRecovery, "explicitClockActionCount", -1) != 0 || surrenderRecoveryClient.ClockActions.Count != 0 ||
            !surrenderRecoveryClient.Actions.SequenceEqual(new[] { "mapPartyTargets", "pursue", "mapPartyTargets", "dialogueSelect", "dialogueContinue", "menuSelect", "menuSelect" }))
            throw new AgentHostException("battle-loop-self-test-surrender-without-battle-recovers-before-replanning", $"Native surrender without Send Troops must wait through captivity, verify the original ransom release to free Map, and return to the parent planner without claiming battle/Renown. termination={ReadString(surrenderRecovery, "termination")}; outcome={ReadString(surrenderRecovery, "playerOutcome")}; battleStarted={ReadBoolean(surrenderRecovery, "battleStarted")}; actions={string.Join(",", surrenderRecoveryClient.Actions)}.");
        return [
            new { scenario = "battle-loop-native-observe-pursue-send-troops-aftermath-return-and-verify", decisions = ReadInt(result, "decisions", 0), nativeActions = client.Actions.ToArray(), renownBefore = ReadDouble(result, "renownBefore", double.NaN), renownAfter = ReadDouble(result, "renownAfter", double.NaN), explicitClockActions = ReadInt(result, "explicitClockActionCount", -1), passed = true },
            new { scenario = "battle-loop-model-chooses-observed-native-try-to-get-away-cost-and-returns-without-claiming-renown", nativeActions = escapeClient.Actions.ToArray(), playerOutcome = ReadString(escapeResult, "playerOutcome"), nativeEscapeCompleted = ReadBoolean(escapeResult, "nativeEscapeCompleted"), passed = true },
            new { scenario = "battle-loop-auto-continues-active-no-choice-map-dialogue-before-renown-planning", nativeActions = mapConversationClient.Actions.ToArray(), passed = true },
            new { scenario = "battle-loop-map-incident-interrupts-before-model-or-native-actions", passed = true },
            new { scenario = "battle-loop-resolves-party-loot-inquiry-from-current-eyc-goal-and-roster-then-resumes-native-aftermath", decisions = ReadInt(partyInquiryResult, "decisions", 0), nativeActions = inquiryClient.Actions.ToArray(), inquiryChoice = inquiryClient.LastInquiryChoice, passed = true },
            new { scenario = "battle-loop-blocks-repeating-done-after-negative-inquiry-until-native-roster-changes", providerCalls = repeatedDoneProvider.CallCount, nativeActions = repeatedDoneClient.Actions.ToArray(), passed = true },
            new { scenario = "battle-loop-incident-after-201-parent-decisions-retains-global-budget", decisions = ReadInt(cumulativeBattle, "decisions", 0), passed = true },
            new { scenario = "battle-loop-native-capture-passive-wait-ransom-release-and-map-return", decisions = ReadInt(recovery, "decisions", 0), nativeActions = recoveryClient.Actions.ToArray(), captivityChoiceOptionId = ReadString(recovery, "captivityChoiceOptionId"), mainPartyMembersAtReturn = ReadInt(recovery, "mainPartyMembersAtReturn", 0), explicitClockActions = ReadInt(recovery, "explicitClockActionCount", -1), passed = true },
            new { scenario = "battle-loop-native-surrender-without-battle-recovery-replans-after-free-map", decisions = ReadInt(surrenderRecovery, "decisions", 0), nativeActions = surrenderRecoveryClient.Actions.ToArray(), captivityChoiceOptionId = ReadString(surrenderRecovery, "captivityChoiceOptionId"), mainPartyMembersAtReturn = ReadInt(surrenderRecovery, "mainPartyMembersAtReturn", 0), explicitClockActions = ReadInt(surrenderRecovery, "explicitClockActionCount", -1), passed = true }
        ];
    }

    private static JsonObject BuildDecisionRequest(string runId, int iteration, string goal, JsonObject observation,
        JsonObject? previousReceipt, JsonObject? feedback, JsonArray actions, JsonArray controls) => new()
    {
        ["schemaVersion"] = 1,
        ["runId"] = runId,
        ["iteration"] = iteration,
        ["goal"] = goal,
        ["goalScopeClassificationRequired"] = false,
        ["goalScopeContract"] = ContractId,
        ["observation"] = observation,
        ["previousActionReceipt"] = previousReceipt?.DeepClone(),
        ["decisionFeedback"] = feedback?.DeepClone(),
        ["allowedActions"] = actions.DeepClone(),
        ["allowedControls"] = controls.DeepClone()
    };

    private static JsonObject BuildObservation(JsonObject native, JsonArray targets, string? targetId, bool battleStarted,
        string battleResult, bool retreated, double renownBefore, double renownNow) => new()
    {
        ["status"] = "completed",
        ["campaignDay"] = native["campaignDay"]?.DeepClone(),
        ["timeControlMode"] = native["timeControlMode"]?.DeepClone(),
        ["state"] = native["state"]?.DeepClone(),
        ["currentlyObservedHostileBanditTargets"] = targets.DeepClone(),
        ["goalVerification"] = new JsonObject
        {
            ["contractId"] = ContractId,
            ["targetPartyId"] = targetId,
            ["nativeBattleStarted"] = battleStarted,
            ["battleStateObserved"] = battleResult,
            ["playerRetreated"] = retreated,
            ["renownBefore"] = double.IsFinite(renownBefore) ? JsonValue.Create(renownBefore) : null,
            ["renownCurrent"] = double.IsFinite(renownNow) ? JsonValue.Create(renownNow) : null
        }
    };

    private static JsonObject BuildResult(string runId, IAgentHostDecisionProvider provider, string status, int decisions,
        int actionsExecuted, long promptTokens, long completionTokens, string termination, string? failure, string? failureCode,
        double startDay, JsonObject? initialNative, JsonObject? finalNative, JsonArray trace, JsonArray routes, double renownBefore, double renownAfter,
        string battleResult, bool playerRetreated, string? targetId, bool battleStarted, JsonObject? battleFinishReceipt,
        bool captivityRecoveryRequested, bool captivityObserved, string? captivityChoiceOptionId, bool nativeEncounterLeft = false,
        bool nativeEscapeCompleted = false, bool nativeCaptivityRecoveryWithoutBattle = false)
    {
        var state = finalNative?["state"] as JsonObject;
        var verifiedReturn = state is not null &&
            (nativeEscapeCompleted ? IsVerifiedMapTerminalAfterNativeEscape(state) :
                nativeEncounterLeft ? IsVerifiedMapTerminalAfterNativeEncounterLeave(state) :
                nativeCaptivityRecoveryWithoutBattle ? IsVerifiedMapTerminalAfterNativeEscape(state) :
                IsVerifiedMapTerminalAfterBattle(state, battleStarted));
        var finalContext = state?["context"] as JsonObject;
        var finalCaptivity = finalContext?["captivity"] as JsonObject;
        var captiveAtReturn = verifiedReturn && ReadBoolean(finalCaptivity, "isCaptive");
        var finalMenuId = ReadString(finalContext, "menuId");
        var nativeFreeMapReturned = verifiedReturn && string.IsNullOrWhiteSpace(finalMenuId);
        var finalParty = state?["party"] as JsonObject;
        var finalPartyMembers = ReadInt(finalParty, "members", 0);
        var captivityRecoveryVerified = captivityRecoveryRequested && captivityObserved && verifiedReturn && !captiveAtReturn && nativeFreeMapReturned && finalPartyMembers > 0;
        var finalPlayerOutcome = nativeEscapeCompleted ? "escaped-with-sacrifice" : captiveAtReturn ? "captured" :
            nativeEncounterLeft ? "left-encounter-without-battle" :
            playerRetreated ? "retreated" : captivityRecoveryVerified ? "captured-then-recovered" :
            string.IsNullOrWhiteSpace(battleResult) || battleResult == "unknown" ? "unknown" : "resolved-native-battle";
        return new JsonObject
        {
            ["schemaVersion"] = 1,
            ["runId"] = runId,
            ["goalScope"] = ContractId,
            ["status"] = status,
            ["modelId"] = provider.ModelId,
            ["providerConfigurationSource"] = provider.ConfigurationSource,
            ["decisions"] = decisions,
            ["actionsExecuted"] = actionsExecuted,
            ["promptTokens"] = promptTokens,
            ["completionTokens"] = completionTokens,
            ["termination"] = termination,
            ["failure"] = failure,
            ["failureCode"] = failureCode,
            ["campaignDayStart"] = double.IsFinite(startDay) ? JsonValue.Create(startDay) : null,
            ["campaignDayEnd"] = finalNative?["campaignDay"]?.DeepClone(),
            ["timeControlModeStart"] = ReadString(initialNative?["timeControlMode"] as JsonObject, "mode") ?? ReadString(initialNative, "timeControlMode"),
            ["timeControlModeEnd"] = ReadString(finalNative?["timeControlMode"] as JsonObject, "mode") ?? ReadString(finalNative, "timeControlMode"),
            ["explicitClockActionCount"] = trace.OfType<JsonObject>().Count(step =>
                ReadString(step, "stage") == "visible-hostile-decision-paused-before-model" &&
                ReadString(step["nativeActionReceipt"] as JsonObject, "status") == "completed"),
            ["targetPartyId"] = targetId,
            ["battleStarted"] = battleStarted,
            ["nativeEscapeCompleted"] = nativeEscapeCompleted,
            ["nativeCaptivityRecoveryWithoutBattle"] = nativeCaptivityRecoveryWithoutBattle,
            ["battleState"] = battleResult,
            ["battleFinishReceipt"] = battleFinishReceipt?.DeepClone(),
            ["playerRetreated"] = playerRetreated,
            ["playerOutcome"] = finalPlayerOutcome,
            ["playerCaptiveAtMapReturn"] = captiveAtReturn,
            ["nativeMapReturnMenuId"] = finalMenuId,
            ["freeMapReturned"] = nativeFreeMapReturned,
            ["captivityRecoveryRequested"] = captivityRecoveryRequested,
            ["captivityObserved"] = captivityObserved,
            ["captivityChoiceOptionId"] = captivityChoiceOptionId,
            ["captivityRecoveryVerified"] = captivityRecoveryVerified,
            ["mainPartyMembersAtReturn"] = finalPartyMembers,
            ["renownBefore"] = double.IsFinite(renownBefore) ? JsonValue.Create(renownBefore) : null,
            ["renownAfter"] = double.IsFinite(renownAfter) ? JsonValue.Create(renownAfter) : null,
            ["renownDelta"] = double.IsFinite(renownBefore) && double.IsFinite(renownAfter) ? JsonValue.Create(renownAfter - renownBefore) : null,
            ["nativeReturnToMapVerified"] = verifiedReturn,
            ["outcomeBefore"] = BuildOutcomeSummary(initialNative),
            ["outcomeAfter"] = BuildOutcomeSummary(finalNative),
            ["finalNativeState"] = finalNative?.DeepClone(),
            ["providerRouteHistory"] = routes.DeepClone(),
            ["trace"] = trace.DeepClone()
        };
    }

    private static JsonObject? BuildOutcomeSummary(JsonObject? native)
    {
        var state = native?["state"] as JsonObject;
        if (state is null) return null;
        var economy = state["economy"] as JsonObject;
        var party = state["party"] as JsonObject;
        return new JsonObject
        {
            ["renown"] = economy?["renown"]?.DeepClone(),
            ["influence"] = economy?["influence"]?.DeepClone(),
            ["gold"] = economy?["gold"]?.DeepClone(),
            ["members"] = party?["members"]?.DeepClone(),
            ["healthy"] = party?["healthy"]?.DeepClone(),
            ["wounded"] = party?["wounded"]?.DeepClone(),
            ["prisoners"] = party?["prisoners"]?.DeepClone(),
            ["itemCount"] = party?["itemCount"]?.DeepClone(),
            ["lootItemCount"] = state["lootItemCount"]?.DeepClone(),
            ["partyScreen"] = state["partyScreen"]?.DeepClone(),
            ["inventoryScreen"] = state["inventoryScreen"]?.DeepClone()
        };
    }

    private static bool IsVerifiedMapTerminalAfterBattle(JsonObject state, bool battleStarted)
    {
        return battleStarted && IsVerifiedMapTerminalState(state);
    }

    private static bool IsVerifiedMapTerminalAfterNativeEscape(JsonObject state) =>
        IsVerifiedMapTerminalState(state) && !IsPlayerCaptive(state) && ReadInt(state["party"] as JsonObject, "members", 0) > 0;

    private static bool IsVerifiedMapTerminalAfterNativeEncounterLeave(JsonObject state) => IsVerifiedMapTerminalState(state);

    private static bool IsNativeEncounterLeaveSelection(JsonObject state, JsonObject arguments)
    {
        var menuId = ReadString(state["context"] as JsonObject, "menuId");
        var expectedOptionId = menuId switch
        {
            "encounter" => "leave",
            "join_encounter" => "join_encounter_leave",
            _ => null
        };
        return expectedOptionId is not null &&
               string.Equals(ReadString(arguments, "menuId"), menuId, StringComparison.Ordinal) &&
               string.Equals(ReadString(arguments, "optionId"), expectedOptionId, StringComparison.Ordinal);
    }

    private static bool IsVerifiedMapTerminalState(JsonObject state)
    {
        var context = state["context"] as JsonObject;
        if (!string.Equals(ReadString(context, "gameState"), "MapState", StringComparison.Ordinal) ||
            ReadBoolean(context, "escapeMenuOpen") || ReadBoolean(context, "inquiryOpen") ||
            ReadBoolean(context, "encounterActive") || context?["battleSimulation"] is not null ||
            state["partyScreen"] is not null || state["inventoryScreen"] is not null)
            return false;
        var menuId = ReadString(context, "menuId");
        if (string.IsNullOrWhiteSpace(menuId)) return true;
        var captivity = context?["captivity"] as JsonObject;
        var noOptionPrisonerWait = ReadBoolean(captivity, "isCaptive") &&
            string.Equals(menuId, "prisoner_wait", StringComparison.Ordinal) &&
            string.Equals(ReadString(captivity, "currentMenuId"), "prisoner_wait", StringComparison.Ordinal) &&
            !ReadBoolean(captivity, "ransomOfferVisible") &&
            (state["availableMenuOptions"] as JsonArray)?.OfType<JsonObject>().Any(x => ReadBoolean(x, "available") && ReadBoolean(x, "enabled")) != true;
        return noOptionPrisonerWait;
    }

    private static bool IsPlayerCaptive(JsonObject? state) =>
        ReadBoolean((state?["context"] as JsonObject)?["captivity"] as JsonObject, "isCaptive");

    private static bool IsActiveMapIncident(JsonObject native) =>
        ReadBoolean(((native["state"] as JsonObject)?["context"] as JsonObject)?["mapIncident"] as JsonObject, "active");

    internal static bool ShouldPauseForVisibleHostileDecision(JsonObject native)
    {
        var state = native["state"] as JsonObject;
        var context = state?["context"] as JsonObject;
        var timeMode = ReadString(native, "timeControlMode") ?? ReadString(context, "timeControlMode");
        if (state is null || context is null || timeMode is null or "Stop" ||
            ReadString(context, "gameState") != "MapState" || !string.IsNullOrWhiteSpace(ReadString(context, "menuId")) ||
            ReadBoolean(context, "encounterActive") || ReadBoolean(context, "escapeMenuOpen") || ReadBoolean(context, "inquiryOpen") ||
            ReadBoolean(context, "isWaitMenu") || ReadBoolean(context, "isWaitActive") ||
            ReadBoolean(context?["sceneNotification"] as JsonObject, "hasActiveNotification") ||
            ReadBoolean(context?["mapIncident"] as JsonObject, "active") ||
            ReadBoolean(context?["bannerEditor"] as JsonObject, "active") || IsPlayerCaptive(state) ||
            state["partyScreen"] is not null || state["inventoryScreen"] is not null ||
            AgentHostCampaignStateFacts.IsActiveEncounter(state))
            return false;

        var pursuingPartyId = ReadString(state["location"] as JsonObject, "targetPartyId");
        IEnumerable<JsonObject> partyRows = state["nearbyParties"] switch
        {
            JsonArray parties => parties.OfType<JsonObject>(),
            JsonObject party => [party],
            _ => Array.Empty<JsonObject>()
        };
        var mainParty = state["party"] as JsonObject;
        var activeNativeBanditPursuit = !string.IsNullOrWhiteSpace(pursuingPartyId) &&
            ReadString(mainParty, "defaultBehavior") == "EngageParty" &&
            partyRows.Any(party => ReadString(party, "type") == "bandit" && ReadBoolean(party, "hostile") &&
                string.Equals(ReadString(party, "id"), pursuingPartyId, StringComparison.Ordinal));
        if (activeNativeBanditPursuit) return false;
        return partyRows.Any(party => ReadString(party, "type") == "bandit" &&
            ReadBoolean(party, "hostile") && !string.IsNullOrWhiteSpace(ReadString(party, "id")) &&
            !string.Equals(ReadString(party, "id"), pursuingPartyId, StringComparison.Ordinal));
    }

    internal static bool ShouldPassivelyWaitForCaptivity(JsonObject state, bool recoverPlayerCaptivity) =>
        recoverPlayerCaptivity && IsPlayerCaptive(state) &&
        string.Equals(ReadString(state["context"] as JsonObject, "menuId"), "prisoner_wait", StringComparison.Ordinal) &&
        !HasEnabledCaptivityOption(state);

    private static bool HasEnabledCaptivityOption(JsonObject state) =>
        (state["availableMenuOptions"] as JsonArray)?.OfType<JsonObject>()
            .Any(option => ReadBoolean(option, "available") && ReadBoolean(option, "enabled")) == true;

    private static bool IsSupportedCaptivityRansomMenu(string? menuId) =>
        menuId is "menu_captivity_end_propose_ransom_wilderness";

    private static bool IsSupportedCaptivityRansomOption(string? optionId) =>
        optionId is "mno_captivity_end_ransom_accept" or "captivity_end_ransom_deny";

    private static bool HasEnabledCaptivityRansomOption(JsonObject state) =>
        (state["availableMenuOptions"] as JsonArray)?.OfType<JsonObject>().Any(option =>
            ReadBoolean(option, "available") && ReadBoolean(option, "enabled") &&
            IsSupportedCaptivityRansomOption(ReadString(option, "id"))) == true;

    private static JsonObject BuildObserveControl(int waitSeconds) => new()
    {
        ["kind"] = "bounded-observe-again",
        ["requestedWaitSeconds"] = waitSeconds
    };

    private static JsonObject BuildTraceStep(int iteration, string startedUtc, JsonObject request, JsonObject? decision,
        JsonObject? feedback, JsonObject? receipt, JsonObject? observationAfter, JsonObject? control = null,
        bool actionExecuted = false, string? providerCompletedUtc = null, string? actionStartedUtc = null,
        string? actionCompletedUtc = null, string? observationCompletedUtc = null, string? schedulerWaitCompletedUtc = null) => new()
    {
        ["iteration"] = iteration,
        ["decisionStartedUtc"] = startedUtc,
        ["goal"] = ReadString(request, "goal"),
        ["observationBefore"] = request["observation"]?.DeepClone(),
        ["observation"] = request["observation"]?.DeepClone(),
        ["observationAfter"] = observationAfter?.DeepClone(),
        ["allowedActions"] = request["allowedActions"]?.DeepClone(),
        ["allowedControls"] = request["allowedControls"]?.DeepClone(),
        ["decision"] = decision?.DeepClone() ?? new JsonObject(),
        ["decisionFeedback"] = feedback?.DeepClone(),
        ["feedback"] = feedback?.DeepClone(),
        ["control"] = control?.DeepClone() ?? BuildTraceControl(feedback),
        ["actionAttempted"] = receipt is not null,
        ["actionExecuted"] = actionExecuted,
        ["actionReceipt"] = receipt?.DeepClone(),
        ["timing"] = new JsonObject
        {
            ["providerStartedUtc"] = startedUtc,
            ["providerCompletedUtc"] = providerCompletedUtc ?? DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture),
            ["actionStartedUtc"] = actionStartedUtc,
            ["actionCompletedUtc"] = actionCompletedUtc ?? (receipt is null ? null : DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture)),
            ["observationCompletedUtc"] = observationCompletedUtc ?? (observationAfter is null ? null : DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture)),
            ["schedulerWaitCompletedUtc"] = schedulerWaitCompletedUtc
        }
    };

    private static JsonObject? BuildTraceControl(JsonObject? feedback)
    {
        var kind = ReadString(feedback, "kind");
        if (kind == "decision-rejected-before-native")
            return new JsonObject { ["kind"] = kind, ["requiredNextStep"] = ReadString(feedback, "requiredNextStep") };
        if (kind == "native-action-rejected")
            return new JsonObject { ["kind"] = "native-action-rejected-before-state-change", ["message"] = ReadString(feedback, "action") };
        return null;
    }

    private static void AddRoute(JsonArray routes, IAgentHostDecisionProvider provider, ProviderDecisionResult result,
        int decision, ref long promptTokens, ref long completionTokens)
    {
        if (result.PromptTokens.HasValue) promptTokens += result.PromptTokens.Value;
        if (result.CompletionTokens.HasValue) completionTokens += result.CompletionTokens.Value;
        routes.Add(new JsonObject
        {
            ["decision"] = decision,
            ["requestedModelId"] = provider.ModelId,
            ["responseModelId"] = result.ModelId,
            ["routedVia"] = result.RoutedVia,
            ["responseFormatMode"] = result.ResponseFormatMode,
            ["promptTokens"] = result.PromptTokens,
            ["completionTokens"] = result.CompletionTokens
        });
    }

    private static JsonObject SafeReceipt(string action, JsonElement response) => new()
    {
        ["action"] = action,
        ["status"] = ReadString(response, "status"),
        ["commandId"] = ReadString(response, "commandId"),
        ["nativeSessionId"] = ReadString(response, "nativeSessionId"),
        ["error"] = ReadString(response, "error"),
        ["data"] = response.TryGetProperty("data", out var data) ? JsonNode.Parse(data.GetRawText()) : null
    };

    private static bool CurrentEnabledMenuOption(JsonObject state, string optionId) =>
        (state["availableMenuOptions"] as JsonArray)?.OfType<JsonObject>().Any(x =>
            string.Equals(ReadString(x, "id"), optionId, StringComparison.Ordinal) && ReadBoolean(x, "available") && ReadBoolean(x, "enabled")) == true;

    private static bool IsObservedEncounterBandit(JsonObject state, JsonArray observedTargets)
    {
        var encounteredId = ReadString(state["context"] as JsonObject, "encounteredPartyId");
        return !string.IsNullOrWhiteSpace(encounteredId) && observedTargets.OfType<JsonObject>().Any(x =>
            ReadString(x, "id") == encounteredId && ReadString(x, "type") == "bandit" && ReadBoolean(x, "hostile"));
    }

    private static bool HasTransferableRoster(JsonArray? roster) =>
        roster?.OfType<JsonObject>().Any(x => ReadInt(x, "count", 0) > 0 && ReadBoolean(x, "transferable")) == true;

    private static JsonArray BuildLootTransferPairs(JsonObject partyScreen)
    {
        var pairs = new JsonArray();
        AddRows(partyScreen["leftMembers"] as JsonArray, "rightMembers", "members", ReadInt(partyScreen, "rightMemberLimit", -1));
        AddRows(partyScreen["leftPrisoners"] as JsonArray, "rightPrisoners", "prisoners", ReadInt(partyScreen, "rightPrisonerLimit", -1));
        return pairs;

        void AddRows(JsonArray? rows, string targetRosterName, string troopType, int targetLimit)
        {
            if (rows is null || targetLimit < 0 || CountRoster(partyScreen[targetRosterName] as JsonArray) >= targetLimit) return;
            foreach (var row in rows.OfType<JsonObject>())
            {
                var troopId = ReadString(row, "troopId");
                if (string.IsNullOrWhiteSpace(troopId) || ReadBoolean(row, "transferable") != true || ReadInt(row, "count", 0) < 1)
                    continue;
                pairs.Add(new JsonObject { ["TroopId"] = troopId, ["TroopType"] = troopType });
            }
        }
    }

    private static bool CanTakeWholeRoster(JsonObject partyScreen, string troopType)
    {
        var isMembers = troopType == "members";
        var leftName = isMembers ? "leftMembers" : "leftPrisoners";
        var rightName = isMembers ? "rightMembers" : "rightPrisoners";
        var limit = ReadInt(partyScreen, isMembers ? "rightMemberLimit" : "rightPrisonerLimit", -1);
        if (limit < 0 || !HasTransferableRoster(partyScreen[leftName] as JsonArray)) return false;
        return CountRoster(partyScreen[rightName] as JsonArray) + CountTransferableRoster(partyScreen[leftName] as JsonArray) <= limit;
    }

    private static int CountRoster(JsonArray? roster) => roster?.OfType<JsonObject>().Sum(row => ReadInt(row, "count", 0)) ?? 0;

    private static int CountTransferableRoster(JsonArray? roster) =>
        roster?.OfType<JsonObject>().Where(row => ReadBoolean(row, "transferable")).Sum(row => ReadInt(row, "count", 0)) ?? 0;

    private static bool CatalogContains(JsonArray catalog, string action) =>
        catalog.OfType<JsonObject>().Any(x => string.Equals(ReadString(x, "action"), action, StringComparison.Ordinal));

    private static void Add(JsonArray catalog, string action, params string[] argumentNames)
    {
        var arguments = new JsonArray();
        foreach (var argumentName in argumentNames) arguments.Add(argumentName);
        catalog.Add(new JsonObject
        {
            ["action"] = action,
            ["arguments"] = arguments
        });
    }

    private static void AddNativeMenuSelectAction(JsonArray catalog, string menuId, IEnumerable<string> optionIds)
    {
        var options = optionIds.Where(id => !string.IsNullOrWhiteSpace(id)).Distinct(StringComparer.Ordinal).ToArray();
        if (options.Length == 0) return;
        catalog.Add(new JsonObject
        {
            ["action"] = "menuSelect",
            ["arguments"] = new JsonArray("MenuId", "OptionId"),
            ["argumentValues"] = new JsonObject
            {
                ["MenuId"] = new JsonArray(menuId),
                ["OptionId"] = new JsonArray(options.Select(id => (JsonNode?)JsonValue.Create(id)).ToArray())
            }
        });
    }

    private static string ExplainNoAction(JsonObject state, bool battleWasStarted, JsonArray observedTargets)
    {
        var context = state["context"] as JsonObject;
        var menuId = ReadString(context, "menuId");
        if (ReadBoolean(context, "encounterActive") && menuId == "encounter_meeting")
            return "The Native encounter is in a dialogue meeting, not a verified Send Troops menu; no toll, surrender, or invented dialogue option was chosen.";
        if (!ReadBoolean(context, "encounterActive") && observedTargets.Count == 0 && !battleWasStarted)
            return "No currently Native-visible hostile bandit party was observed; the Host stopped without using a hidden target or fabricating an encounter.";
        return "Current Native context has no bounded BattleSimulation action; the Host stopped without changing the game clock or entering a Mission.";
    }

    private static JsonObject ParseObject(JsonElement element) => JsonNode.Parse(element.GetRawText())?.AsObject() ?? new JsonObject();
    private static JsonArray CloneArray(JsonArray? source) => source?.DeepClone() as JsonArray ?? new JsonArray();
    private static JsonObject ParseState(string gameState, string? menuId, bool encounterActive, string? partyTarget, JsonObject? battle)
    {
        var context = new JsonObject { ["gameState"] = gameState, ["menuId"] = menuId, ["encounterActive"] = encounterActive, ["battleSimulation"] = battle?.DeepClone() };
        return new JsonObject
        {
            ["processId"] = 321,
            ["campaignDay"] = 5.0,
            ["timeControlMode"] = "Stop",
            ["state"] = new JsonObject
            {
                ["context"] = context,
                ["economy"] = new JsonObject { ["renown"] = 10.0 },
                ["location"] = new JsonObject { ["targetPartyId"] = partyTarget },
                ["availableMenuOptions"] = new JsonArray()
            }
        };
    }

    private static bool IsRecoverableProviderError(string code) => code is
        "provider-decision-invalid" or "provider-action-unavailable" or "provider-control-unavailable" or
        "provider-arguments-invalid-json" or "provider-arguments-invalid" or "provider-decision-timeout";

    private static double ReadRenown(JsonObject? state) => ReadDouble(state?["economy"] as JsonObject, "renown", double.NaN);
    private static string? ReadString(JsonObject? value, string name) => value?[name] is JsonValue node && node.TryGetValue<string>(out var result) ? result : null;
    private static bool ReadBoolean(JsonObject? value, string name) => value?[name] is JsonValue node && node.TryGetValue<bool>(out var result) && result;
    private static int ReadInt(JsonObject? value, string name, int fallback) => value?[name] is JsonValue node && node.TryGetValue<int>(out var result) ? result : fallback;
    private static long ReadLong(JsonObject? value, string name, long fallback) => value?[name] is JsonValue node && node.TryGetValue<long>(out var result) ? result : fallback;
    private static double ReadDouble(JsonObject? value, string name, double fallback) => value?[name] is JsonValue node && node.TryGetValue<double>(out var result) ? result : fallback;
    private static string? ReadString(JsonElement value, string name) => value.TryGetProperty(name, out var node) && node.ValueKind == JsonValueKind.String ? node.GetString() : null;
    private static int ReadInt(JsonElement value, string name, int fallback) => value.TryGetProperty(name, out var node) && node.TryGetInt32(out var result) ? result : fallback;
    private static JsonObject? ParseObjectOrNull(JsonElement value, string name) => value.TryGetProperty(name, out var node) && node.ValueKind == JsonValueKind.Object ? JsonNode.Parse(node.GetRawText())?.AsObject() : null;
    private static JsonObject CloneObject(JsonElement value) => JsonNode.Parse(value.GetRawText())?.AsObject() ?? new JsonObject();
    private static JsonArray CloneArray(JsonElement value) => value.ValueKind == JsonValueKind.Array ? JsonNode.Parse(value.GetRawText())?.AsArray() ?? new JsonArray() : new JsonArray();
    private static string Truncate(string value, int max) => value.Length <= max ? value : value[..max];

    private sealed class FakeBattleSimulationNativeClient : IAgentHostBattleSimulationNativeClient, IAgentHostNativeInquiryClient
    {
        private readonly bool _simulateCaptivity;
        private readonly bool _simulatePartyInquiry;
        private readonly bool _visibleHostileAtStart;
        private readonly bool _mapIncidentAtStart;
        private readonly bool _mapConversationAtStart;
        private readonly bool _simulateNativeEscape;
        private readonly bool _simulateSurrenderWithoutBattle;
        private int _stage;
        private int _movingReads;
        private int _captivityPolls;
        private bool _mapConversationContinued;
        private bool _memberLootTaken;
        private bool _prisonerLootTaken;
        private int _inventoryLootCount = 2;
        private string _timeControlMode = "Stop";
        internal List<string> Actions { get; } = [];
        internal List<string> ClockActions { get; } = [];
        internal string? LastInquiryChoice { get; private set; }

        internal FakeBattleSimulationNativeClient(bool simulateCaptivity = false, bool simulatePartyInquiry = false, bool visibleHostileAtStart = false, bool mapIncidentAtStart = false, bool mapConversationAtStart = false, bool simulateNativeEscape = false, bool simulateSurrenderWithoutBattle = false)
        {
            _simulateCaptivity = simulateCaptivity || simulateSurrenderWithoutBattle;
            _simulatePartyInquiry = simulatePartyInquiry;
            _visibleHostileAtStart = visibleHostileAtStart;
            _mapIncidentAtStart = mapIncidentAtStart;
            _mapConversationAtStart = mapConversationAtStart;
            _simulateNativeEscape = simulateNativeEscape;
            _simulateSurrenderWithoutBattle = simulateSurrenderWithoutBattle;
            if (visibleHostileAtStart) _timeControlMode = "StoppablePlay";
        }

        public Task<JsonDocument> ReadStateAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (_stage == 1 && ++_movingReads >= 2) _stage = 2;
            if (_simulateCaptivity && _stage == 10 && ++_captivityPolls >= 2) _stage = 11;
            return Task.FromResult(JsonDocument.Parse(BuildState().ToJsonString()));
        }

        public Task<JsonDocument> ExecuteCampaignActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken) =>
            throw new AgentHostException("battle-self-test-unexpected-campaign-action", "Campaign arrival actions are outside this fake battle transport.");

        public Task<JsonDocument> PauseForVisibleHostileDecisionAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (!_visibleHostileAtStart || _stage != 0 || _timeControlMode == "Stop")
                throw new AgentHostException("battle-self-test-unexpected-visible-hostile-pause", "Only the visible, not-yet-pursued moving-bandit fixture may receive the explicit Host Pause.");
            ClockActions.Add("pause");
            _timeControlMode = "Stop";
            return Task.FromResult(JsonDocument.Parse("{\"processId\":321,\"status\":\"completed\",\"action\":\"pause\",\"commandId\":\"fake-visible-threat-pause\"}"));
        }

        public Task<JsonDocument> ExecuteBattleSimulationActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            NativeMailboxClient.ValidateBattleSimulationAction(action, arguments);
            Actions.Add(action);
            switch (action)
            {
                case "pursue": _stage = 1; _movingReads = 0; _timeControlMode = "StoppablePlay"; break;
                case "dialogueSelect": _stage = 3; break;
                case "dialogueContinue":
                    if (_mapConversationAtStart && !_mapConversationContinued && _stage == 0) _mapConversationContinued = true;
                    else _stage = 4;
                    break;
                case "menuSelect":
                    if (_simulateSurrenderWithoutBattle && _stage == 4 && ReadString(arguments, "optionId") == "surrender") _stage = 10;
                    else if (_simulateNativeEscape && _stage == 4 && ReadString(arguments, "optionId") == "leave_soldiers_behind") _stage = 14;
                    else if (_simulateNativeEscape && _stage == 14 && ReadString(arguments, "optionId") == "try_to_get_away_accept") _stage = 15;
                    else if (_simulateNativeEscape && _stage == 14 && ReadString(arguments, "optionId") == "try_to_get_away_reject") _stage = 4;
                    else if (_simulateNativeEscape && _stage == 15 && ReadString(arguments, "optionId") == "try_to_get_away_continue") _stage = 16;
                    else if (_stage == 4) _stage = 5;
                    else if (_simulateCaptivity && _stage == 11 && ReadString(arguments, "optionId") == "mno_captivity_end_ransom_accept") _stage = 12;
                    else throw new AgentHostException("battle-self-test-menu-choice-invalid", "The fake Native menu did not have the selected enabled option.");
                    break;
                case "battleSkip": _stage = 6; break;
                case "battleFinish": _stage = _simulateCaptivity ? 10 : 7; break;
                case "partyTakeAll":
                    if (ReadString(arguments, "troopType") == "prisoners") _prisonerLootTaken = true;
                    else _memberLootTaken = true;
                    break;
                case "partyScreenDone": _stage = _simulatePartyInquiry && !_memberLootTaken ? 13 : 8; break;
                case "inventoryTakeAll": _inventoryLootCount = 0; break;
                case "inventoryDone": _stage = 9; break;
            }
            var response = new JsonObject
            {
                ["processId"] = 321,
                ["status"] = action == "partyScreenDone" && _simulatePartyInquiry && !_memberLootTaken ? "accepted" : "completed",
                ["commandId"] = "fake-" + action,
                ["nativeSessionId"] = "fake-session"
            };
            if (action == "mapPartyTargets")
                response["data"] = new JsonObject { ["mapPartyTargets"] = new JsonArray(new JsonObject { ["id"] = "bandit-1", ["name"] = "Bandit Party", ["type"] = "bandit", ["distance"] = 2.0, ["hostile"] = true }) };
            return Task.FromResult(JsonDocument.Parse(response.ToJsonString()));
        }

        public Task<JsonDocument> RespondNativeInquiryAsync(string token, string choice, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (!_simulatePartyInquiry || _stage != 13 || token != "party-loot-inquiry-token")
                throw new AgentHostException("battle-self-test-party-inquiry-token-invalid", "The battle loop did not respond to the exact current PartyState Inquiry.");
            LastInquiryChoice = choice;
            _stage = choice == "negative" ? 7 : 8;
            return Task.FromResult(JsonDocument.Parse("{\"status\":\"completed\",\"action\":\"respondInquiry\"}"));
        }

        public Task<JsonDocument> SubmitStoryModeClanNameAsync(string token, string clanName, CancellationToken cancellationToken) =>
            throw new AgentHostException("battle-self-test-unexpected-clan-name", "The battle aftermath fixture does not accept a family-name submission.");

        private JsonObject BuildState()
        {
            var stateName = _stage switch { 7 or 13 => "PartyState", 8 => "InventoryState", _ => "MapState" };
            var menuId = _stage is 2 or 3 ? "encounter_meeting" : _stage is 4 or 5 or 6 ? "encounter" : _stage == 10 ? "prisoner_wait" : _stage == 11 ? "menu_captivity_end_propose_ransom_wilderness" : _stage == 14 ? "try_to_get_away" : _stage == 15 ? "try_to_get_away_debrief" : null;
            var encounterActive = _stage is 2 or 3 or 4 or 5 or 6 or 14 or 15;
            JsonObject? simulation = null;
            if (_stage is 5 or 6)
                simulation = new JsonObject { ["finished"] = _stage == 6, ["playerRetreated"] = false, ["battleState"] = "AttackerVictory" };
                var state = new JsonObject
            {
                ["context"] = new JsonObject { ["gameState"] = stateName, ["menuId"] = menuId, ["encounterActive"] = encounterActive, ["battleSimulation"] = simulation, ["encounteredPartyId"] = encounterActive ? "bandit-1" : null, ["timeControlMode"] = _timeControlMode },
                ["economy"] = new JsonObject { ["renown"] = 10.0, ["influence"] = 0.0, ["gold"] = _stage == 12 ? 169 : 500 },
                ["party"] = new JsonObject { ["members"] = _stage is 10 or 11 ? 0 : _stage == 12 ? 1 : _memberLootTaken ? 41 : 40, ["healthy"] = 39, ["wounded"] = 1, ["prisoners"] = 0, ["itemCount"] = 12 },
                ["location"] = new JsonObject { ["targetPartyId"] = _stage == 1 ? "bandit-1" : null },
                    ["availableMenuOptions"] = _stage == 4 && _simulateSurrenderWithoutBattle
                        ? new JsonArray(
                            new JsonObject { ["id"] = "str_order_attack", ["available"] = false, ["enabled"] = false },
                            new JsonObject { ["id"] = "leave", ["available"] = false, ["enabled"] = false },
                            new JsonObject { ["id"] = "leave_soldiers_behind", ["available"] = false, ["enabled"] = false },
                            new JsonObject { ["id"] = "surrender", ["available"] = true, ["enabled"] = true })
                    : _stage == 4
                    ? _simulateNativeEscape
                        ? new JsonArray(
                            new JsonObject { ["id"] = "str_order_attack", ["available"] = true, ["enabled"] = true },
                            new JsonObject { ["id"] = "leave_soldiers_behind", ["available"] = true, ["enabled"] = true })
                        : new JsonArray(new JsonObject { ["id"] = "str_order_attack", ["available"] = true, ["enabled"] = true })
                    : _stage == 11
                        ? new JsonArray(
                            new JsonObject { ["id"] = "mno_captivity_end_ransom_accept", ["available"] = true, ["enabled"] = true },
                            new JsonObject { ["id"] = "captivity_end_ransom_deny", ["available"] = true, ["enabled"] = true })
                    : _stage == 14
                        ? new JsonArray(
                            new JsonObject { ["id"] = "try_to_get_away_accept", ["available"] = true, ["enabled"] = true },
                            new JsonObject { ["id"] = "try_to_get_away_reject", ["available"] = true, ["enabled"] = true })
                    : _stage == 15
                        ? new JsonArray(new JsonObject { ["id"] = "try_to_get_away_continue", ["available"] = true, ["enabled"] = true })
                        : new JsonArray()
            };
            if (_stage == 14)
                state["context"]!["encounterEscape"] = new JsonObject
                {
                    ["schemaVersion"] = 1,
                    ["menuId"] = "try_to_get_away",
                    ["menuText"] = "You may lose 7 troops and some cargo.",
                    ["canTryToGetAway"] = true,
                    ["nativeTroopsSacrificedForTry"] = 7,
                    ["healthyNonHeroMembers"] = 39,
                    ["gold"] = 500,
                    ["grain"] = 20,
                    ["itemCount"] = 12
                };
            if (_visibleHostileAtStart && _stage == 0)
                state["nearbyParties"] = new JsonArray(new JsonObject { ["id"] = "bandit-1", ["name"] = "Bandit Party", ["type"] = "bandit", ["distance"] = 2.0, ["hostile"] = true });
            if (_mapConversationAtStart && !_mapConversationContinued && _stage == 0)
                state["context"]!["conversation"] = new JsonObject
                {
                    ["characterId"] = "notable-a", ["sentenceText"] = "We part ways.", ["options"] = new JsonArray()
                };
            if (_mapIncidentAtStart && _stage == 0)
                state["context"]!["mapIncident"] = new JsonObject { ["schemaVersion"] = 1, ["active"] = true, ["supported"] = true, ["incidentType"] = "PlightOfCivilians" };
            if (_stage is 10 or 11)
                state["context"]!["captivity"] = new JsonObject
                {
                    ["isCaptive"] = true,
                    ["currentMenuId"] = menuId,
                    ["ransomOfferVisible"] = _stage == 11,
                    ["currentVisibleRansomAmount"] = _stage == 11 ? 331 : null
                };
            if (_stage == 2)
                state["context"]!["conversation"] = _simulateSurrenderWithoutBattle
                    ? new JsonObject
                    {
                        ["sentenceText"] = "Well well, look at this!",
                        ["options"] = new JsonArray(new JsonObject { ["id"] = "bandit_start_defender_3", ["textId"] = WeakPartySurrenderResponseTextId, ["clickable"] = true })
                    }
                    : new JsonObject
                    {
                        ["sentenceText"] = "Well well, look at this!",
                        ["options"] = new JsonArray(new JsonObject { ["id"] = "bandit_start_defender_1", ["clickable"] = true }, new JsonObject { ["id"] = "bandit_toll", ["clickable"] = true })
                    };
            if (_stage == 3)
                state["context"]!["conversation"] = new JsonObject { ["sentenceText"] = "Prepare yourself.", ["options"] = new JsonArray() };
            if (_stage is 7 or 13)
                state["partyScreen"] = new JsonObject
                {
                    ["mode"] = "Loot", ["canDone"] = true,
                    ["leftMembers"] = _memberLootTaken ? new JsonArray() : new JsonArray(new JsonObject { ["troopId"] = "villager_empire", ["name"] = "帝国农民", ["count"] = 5, ["transferable"] = true }),
                    ["leftPrisoners"] = _prisonerLootTaken ? new JsonArray() : new JsonArray(new JsonObject { ["troopId"] = "looter", ["name"] = "劫匪", ["count"] = 4, ["transferable"] = true }),
                    ["rightMembers"] = new JsonArray(), ["rightPrisoners"] = _prisonerLootTaken ? new JsonArray(new JsonObject { ["troopId"] = "looter", ["name"] = "劫匪", ["count"] = 4, ["transferable"] = true }) : new JsonArray(),
                    ["rightMemberLimit"] = 25, ["rightPrisonerLimit"] = 18
                };
            if (_stage == 13)
            {
                state["context"]!["inquiryOpen"] = true;
                state["context"]!["inquiry"] = new JsonObject
                {
                    ["supported"] = true, ["kind"] = "YesNoInquiry", ["token"] = "party-loot-inquiry-token",
                    ["title"] = "Leaving troops behind", ["text"] = "Five Imperial peasants remain. Leave them behind?",
                    ["affirmative"] = new JsonObject { ["visible"] = true, ["enabled"] = true, ["text"] = "是" },
                    ["negative"] = new JsonObject { ["visible"] = true, ["enabled"] = true, ["text"] = "否" }
                };
            }
            if (_stage == 8)
                state["inventoryScreen"] = new JsonObject { ["mode"] = "Loot", ["lootItemCount"] = _inventoryLootCount, ["playerItemCount"] = 12 };
            var timeControlMode = _stage == 10 ? "UnstoppableFastForward" : _timeControlMode;
            return new JsonObject { ["processId"] = 321, ["campaignDay"] = _stage is 1 or 2 ? 5.1 : _stage == 10 ? 5.2 : 5.0, ["timeControlMode"] = timeControlMode, ["state"] = state };
        }
    }

    private sealed class FakeTryToGetAwayDecisionProvider : IAgentHostDecisionProvider
    {
        private static readonly string[] ExpectedSteps =
        ["mapPartyTargets", "pursue", "observeAgain", "mapPartyTargets", "dialogueSelect", "dialogueContinue", "escape-start", "escape-accept", "escape-continue"];

        internal int CallCount { get; private set; }
        internal JsonObject? WarningRequest { get; private set; }
        public string ModelId => "deterministic-native-escape-self-test";
        public string ConfigurationSource => "harness-fake-provider";

        public Task CheckConfiguredModelAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            return Task.CompletedTask;
        }

        public Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (CallCount >= ExpectedSteps.Length)
                throw new AgentHostException("battle-loop-native-escape-self-test-provider-exhausted", "The fake provider exceeded the bounded Native Try-to-get-away route.");
            var step = ExpectedSteps[CallCount++];
            if (step == "escape-accept") WarningRequest = ParseObject(request);
            JsonObject decision = step switch
            {
                "observeAgain" => new JsonObject { ["control"] = "observeAgain", ["waitSeconds"] = 1, ["reason"] = "Wait for the Native pursuit transition." },
                "pursue" => new JsonObject { ["action"] = "pursue", ["arguments"] = new JsonObject { ["PartyId"] = "bandit-1" }, ["rationale"] = "Pursue the current visible hostile." },
                "dialogueSelect" => new JsonObject { ["action"] = "dialogueSelect", ["arguments"] = new JsonObject { ["OptionId"] = "bandit_start_defender_1" }, ["rationale"] = "Follow the visible Native fight choice." },
                "dialogueContinue" => new JsonObject { ["action"] = "dialogueContinue", ["arguments"] = new JsonObject(), ["rationale"] = "Advance the current no-choice Native line." },
                "escape-start" => new JsonObject { ["action"] = "menuSelect", ["arguments"] = new JsonObject { ["MenuId"] = "encounter", ["OptionId"] = "leave_soldiers_behind" }, ["rationale"] = "Open the current Native retreat risk warning." },
                "escape-accept" => new JsonObject { ["action"] = "menuSelect", ["arguments"] = new JsonObject { ["MenuId"] = "try_to_get_away", ["OptionId"] = "try_to_get_away_accept" }, ["rationale"] = "Accept the currently observed loss estimate." },
                "escape-continue" => new JsonObject { ["action"] = "menuSelect", ["arguments"] = new JsonObject { ["MenuId"] = "try_to_get_away_debrief", ["OptionId"] = "try_to_get_away_continue" }, ["rationale"] = "Complete the current Native debrief." },
                _ => new JsonObject { ["action"] = step, ["arguments"] = new JsonObject(), ["rationale"] = "Use the current Native action." }
            };
            return Task.FromResult(new ProviderDecisionResult("completed", ModelId, 1, 1, "fake-test-route", decision));
        }

        public void Dispose() { }
    }

    private sealed class FakeBattleSimulationDecisionProvider : IAgentHostDecisionProvider
    {
        private static readonly string[] ExpectedActions = ["mapPartyTargets", "pursue", "observeAgain", "mapPartyTargets", "dialogueSelect", "dialogueContinue", "menuSelect", "battleSkip", "battleFinish", "partyTakeAll", "partyScreenDone", "inventoryTakeAll", "inventoryDone", "done"];
        private static readonly string[] ExpectedInquiryActions = ["mapPartyTargets", "pursue", "observeAgain", "mapPartyTargets", "dialogueSelect", "dialogueContinue", "menuSelect", "battleSkip", "battleFinish", "partyTakeAll", "partyScreenDone", "respondInquiry", "partyTakeAll", "partyScreenDone", "inventoryTakeAll", "inventoryDone", "done"];
        private static readonly string[] ExpectedInquiryDoneRepeatActions = ["mapPartyTargets", "pursue", "observeAgain", "mapPartyTargets", "dialogueSelect", "dialogueContinue", "menuSelect", "battleSkip", "battleFinish", "partyTakeAll", "partyScreenDone", "respondInquiry", "partyScreenDone", "partyTakeAll", "partyScreenDone", "inventoryTakeAll", "inventoryDone", "done"];
        private readonly bool _simulatePartyInquiry;
        private readonly bool _repeatPartyScreenDoneAfterDecline;
        internal int CallCount { get; private set; }
        internal JsonObject? FirstRequest { get; private set; }
        internal JsonObject? LastInquiryRequest { get; private set; }
        public string ModelId => "deterministic-battle-loop-self-test";
        public string ConfigurationSource => "harness-fake-provider";
        internal FakeBattleSimulationDecisionProvider(bool simulatePartyInquiry = false, bool repeatPartyScreenDoneAfterDecline = false)
        {
            _simulatePartyInquiry = simulatePartyInquiry;
            _repeatPartyScreenDoneAfterDecline = repeatPartyScreenDoneAfterDecline;
        }
        public Task CheckConfiguredModelAsync(CancellationToken cancellationToken) { cancellationToken.ThrowIfCancellationRequested(); return Task.CompletedTask; }

        public Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (CallCount == 0) FirstRequest = ParseObject(request);
            var index = CallCount++;
            var expectedActions = !_simulatePartyInquiry ? ExpectedActions :
                _repeatPartyScreenDoneAfterDecline ? ExpectedInquiryDoneRepeatActions : ExpectedInquiryActions;
            if (index >= expectedActions.Length) throw new AgentHostException("battle-loop-self-test-provider-exhausted", "The fake provider received more decisions than the Native battle protocol requires.");
            var expected = expectedActions[index];
            if (expected == "respondInquiry") LastInquiryRequest = JsonNode.Parse(request.GetRawText()) as JsonObject;
            JsonObject decision;
            if (expected == "respondInquiry") decision = new JsonObject { ["action"] = "respondInquiry", ["arguments"] = new JsonObject { ["choice"] = "negative" }, ["rationale"] = "Keep reviewing the five villagers because the active party-size objective is 11 of 25." };
            else if (expected == "done") decision = new JsonObject { ["done"] = true, ["reason"] = "Native battle and return verified." };
            else if (expected == "observeAgain") decision = new JsonObject { ["control"] = "observeAgain", ["waitSeconds"] = 1, ["reason"] = "Observe current pursuit." };
            else decision = new JsonObject
            {
                ["action"] = expected,
                ["arguments"] = expected switch
                {
                    "pursue" => new JsonObject { ["PartyId"] = "bandit-1" },
                    "dialogueSelect" => new JsonObject { ["OptionId"] = "bandit_start_defender_1" },
                    "partyTakeAll" when _simulatePartyInquiry && index == 9 => new JsonObject { ["TroopType"] = "prisoners" },
                    "partyTakeAll" when _simulatePartyInquiry && index == (_repeatPartyScreenDoneAfterDecline ? 13 : 12) => new JsonObject { ["TroopType"] = "members" },
                    "menuSelect" => new JsonObject { ["MenuId"] = "encounter", ["OptionId"] = "str_order_attack" },
                    "partyTakeAll" => new JsonObject { ["TroopType"] = "members" },
                    _ => new JsonObject()
                },
                ["rationale"] = "Use the current Native action."
            };
            return Task.FromResult(new ProviderDecisionResult("completed", ModelId, 1, 1, "fake-test-route", decision));
        }
        public void Dispose() { }
    }

    private sealed class FakeBattleCaptivityDecisionProvider : IAgentHostDecisionProvider
    {
        private static readonly string[] ExpectedActions = ["mapPartyTargets", "pursue", "observeAgain", "mapPartyTargets", "dialogueSelect", "dialogueContinue", "menuSelect", "battleSkip", "battleFinish", "menuSelect", "done"];
        internal int CallCount { get; private set; }
        public string ModelId => "deterministic-battle-captivity-self-test";
        public string ConfigurationSource => "harness-fake-provider";
        public Task CheckConfiguredModelAsync(CancellationToken cancellationToken) { cancellationToken.ThrowIfCancellationRequested(); return Task.CompletedTask; }

        public Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var index = CallCount++;
            if (index >= ExpectedActions.Length) throw new AgentHostException("battle-captivity-self-test-provider-exhausted", "The fake provider received more decisions than the battle/captivity contract requires.");
            var expected = ExpectedActions[index];
            JsonObject decision;
            if (expected == "done") decision = new JsonObject { ["done"] = true, ["reason"] = "Native confirms captivity ended and MainParty is active." };
            else if (expected == "observeAgain") decision = new JsonObject { ["observeAgain"] = true, ["waitSeconds"] = 1, ["reason"] = "Observe natural movement." };
            else decision = new JsonObject
            {
                ["action"] = expected,
                ["arguments"] = expected switch
                {
                    "pursue" => new JsonObject { ["PartyId"] = "bandit-1" },
                    "dialogueSelect" => new JsonObject { ["OptionId"] = "bandit_start_defender_1" },
                    "menuSelect" when index == 6 => new JsonObject { ["MenuId"] = "encounter", ["OptionId"] = "str_order_attack" },
                    "menuSelect" => new JsonObject { ["MenuId"] = "menu_captivity_end_propose_ransom_wilderness", ["OptionId"] = "mno_captivity_end_ransom_accept" },
                    _ => new JsonObject()
                },
                ["rationale"] = "Use the current Native action."
            };
            return Task.FromResult(new ProviderDecisionResult("completed", ModelId, 1, 1, "fake-test-route", decision));
        }
        public void Dispose() { }
    }

    private sealed class FakeSurrenderRecoveryDecisionProvider : IAgentHostDecisionProvider
    {
        private static readonly string[] ExpectedActions = ["mapPartyTargets", "pursue", "observeAgain", "mapPartyTargets", "dialogueSelect", "dialogueContinue", "menuSelect", "menuSelect"];
        internal int CallCount { get; private set; }
        public string ModelId => "deterministic-surrender-recovery-self-test";
        public string ConfigurationSource => "harness-fake-provider";
        public Task CheckConfiguredModelAsync(CancellationToken cancellationToken) { cancellationToken.ThrowIfCancellationRequested(); return Task.CompletedTask; }

        public Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var index = CallCount++;
            if (index >= ExpectedActions.Length) throw new AgentHostException("surrender-recovery-self-test-provider-exhausted", "The fake provider exceeded the no-battle surrender/recovery route.");
            var expected = ExpectedActions[index];
            var arguments = expected switch
            {
                "pursue" => new JsonObject { ["PartyId"] = "bandit-1" },
                "dialogueSelect" => new JsonObject { ["OptionId"] = "bandit_start_defender_3" },
                "menuSelect" when index == 6 => new JsonObject { ["MenuId"] = "encounter", ["OptionId"] = "surrender" },
                "menuSelect" => new JsonObject { ["MenuId"] = "menu_captivity_end_propose_ransom_wilderness", ["OptionId"] = "mno_captivity_end_ransom_accept" },
                _ => new JsonObject()
            };
            var decision = expected switch
            {
                "observeAgain" => new JsonObject { ["observeAgain"] = true, ["waitSeconds"] = 1, ["reason"] = "Wait for the current Native pursuit transition." },
                _ => new JsonObject { ["action"] = expected, ["arguments"] = arguments, ["rationale"] = "Use the current Native action and recover through Native captivity." }
            };
            return Task.FromResult(new ProviderDecisionResult("completed", ModelId, 1, 1, "fake-test-route", decision));
        }

        public void Dispose() { }
    }
}
