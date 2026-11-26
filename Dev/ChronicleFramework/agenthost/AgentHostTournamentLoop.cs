using System.Diagnostics;
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

/// <summary>
/// One bounded observation of a currently visible Native Arena tournament. This profile is
/// deliberately independent of the general Campaign loop: tournament handlers live inside an
/// Arena Mission, and a handler receipt never proves a player victory or a reward. The loop
/// reports Native winner/playerWon only after TournamentVM reports isOver with a resolved result.
/// </summary>
internal static class AgentHostTournamentLoop
{
    private const int MaxDecisionsDefault = 8;
    private const int MaxDecisionsCeiling = 32;

    internal static async Task<JsonObject> RunAsync(
        JsonElement request,
        IAgentHostCampaignNativeClient stateClient,
        IAgentHostTournamentNativeClient actionClient,
        IAgentHostDecisionProvider provider,
        DecisionRunLedger ledger,
        CancellationToken cancellationToken)
    {
        var runId = ReadString(request, "runId") ?? Guid.NewGuid().ToString("N");
        var maxDecisions = Math.Clamp(ReadInt(request, "maxDecisions", MaxDecisionsDefault), 1, MaxDecisionsCeiling);
        var maxElapsedSeconds = Math.Clamp(ReadInt(request, "maxElapsedSeconds", 900), 10, 86400);
        using var elapsed = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        elapsed.CancelAfter(TimeSpan.FromSeconds(maxElapsedSeconds));

        var actionCount = 0;
        var rejectedProviderDecisions = 0;
        JsonObject? decisionFeedback = null;
        JsonObject? finalReceipt = null;
        JsonObject? initialNative = null;
        JsonObject? currentNative = null;
        var campaignDayBefore = double.NaN;
        string? timeControlModeBefore = null;

        try
        {
            await provider.CheckConfiguredModelAsync(elapsed.Token);
            using (var initial = await stateClient.ReadStateAsync(elapsed.Token)) initialNative = ParseObject(initial.RootElement);
            currentNative = initialNative.DeepClone() as JsonObject ?? throw new AgentHostException("tournament-initial-state-invalid", "Native returned no initial state.");
            campaignDayBefore = ReadDouble(currentNative, "campaignDay", double.NaN);
            timeControlModeBefore = ReadString(currentNative, "timeControlMode");

            var initialState = currentNative["state"] as JsonObject ?? throw new AgentHostException("tournament-state-missing", "Native returned no state object.");
            var initialContext = initialState["context"] as JsonObject;
            if (ReadBoolean(initialContext?["captivity"] as JsonObject, "isCaptive") || ReadBoolean(initialContext, "inquiryOpen"))
                throw new AgentHostException("tournament-out-of-scope", "The tournament observation profile does not resolve captivity or Native inquiries.");
            if (ReadString(initialContext, "gameState") != "MissionState" || ReadBoolean(GetTournament(initialState), "available") != true)
                throw new AgentHostException("tournament-not-visible-in-current-mission", "The bounded tournament profile requires a currently visible Native tournament screen inside an Arena Mission.");

            for (var iteration = 1; ledger.Decisions < maxDecisions; iteration++)
            {
                elapsed.Token.ThrowIfCancellationRequested();
                var state = currentNative["state"] as JsonObject ?? throw new AgentHostException("tournament-state-missing", "Native returned no state object.");
                var tournament = GetTournament(state);

                if (TryReadSettledResult(tournament, out var settled))
                    return BuildSuccess(runId, provider, initialNative, currentNative, settled!, finalReceipt, ledger,
                        actionCount, campaignDayBefore, timeControlModeBefore);

                var actionCatalog = BuildActionCatalog(state);
                if (actionCatalog.Count == 0)
                    throw new AgentHostException("tournament-no-current-handler", "Native did not expose a safe current tournament handler or an already resolved result.");

                var observation = BuildObservation(currentNative, state, finalReceipt);
                var modelRequest = BuildDecisionRequest(runId, ReadString(request, "goal"), iteration + ledger.Decisions,
                    observation, finalReceipt, decisionFeedback, actionCatalog);
                var started = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                var startedTicks = Stopwatch.GetTimestamp();
                ProviderDecisionResult modelDecision;
                try
                {
                    modelDecision = await AgentHostDecisionCycle.DecideTournamentAsync(provider, modelRequest, elapsed.Token);
                }
                catch (AgentHostException exception) when (AgentHostProviderDecisionRecovery.CanRetry(exception.Code, rejectedProviderDecisions))
                {
                    ledger.RecordUnsentDecision();
                    rejectedProviderDecisions++;
                    decisionFeedback = AgentHostProviderDecisionRecovery.BuildFeedback(exception.Code, actionCatalog, new JsonArray());
                    ledger.Trace.Add(new JsonObject
                    {
                        ["iteration"] = ledger.Decisions,
                        ["stage"] = "decision-rejected-before-native",
                        ["rejectionCode"] = exception.Code,
                        ["nativeActionSent"] = false,
                        ["allowedActionNames"] = AgentHostProviderDecisionRecovery.CurrentActionNames(actionCatalog),
                        ["feedback"] = decisionFeedback.DeepClone()
                    });
                    continue;
                }
                ledger.RecordDecision(modelDecision);
                rejectedProviderDecisions = 0;
                decisionFeedback = null;

                if (!TryResolveAction(actionCatalog, modelDecision.Decision, out var action, out var arguments, out var rejection))
                    throw new AgentHostException("tournament-model-action-invalid", rejection ?? "The model did not choose a currently listed Native tournament handler.");

                using var actionResponse = await actionClient.ExecuteTournamentActionAsync(action!, arguments!, elapsed.Token);
                var receipt = ParseObject(actionResponse.RootElement);
                actionCount++;
                if (!VerifyActionReceipt(receipt, action!))
                    throw new AgentHostException("tournament-native-handler-unverified", "Native did not confirm the current " + action + " handler through its original TournamentVM.");

                finalReceipt = BuildReceipt(action!, receipt);
                using (var fresh = await stateClient.ReadStateAsync(elapsed.Token)) currentNative = ParseObject(fresh.RootElement);
                ledger.Trace.Add(BuildStep(ledger.Decisions, observation, modelDecision.Decision, finalReceipt, started, startedTicks,
                    BuildObservation(currentNative, currentNative["state"] as JsonObject ?? new JsonObject(), finalReceipt)));
            }

            if (ShouldSafelyLeave(currentNative))
            {
                using var leaveResponse = await actionClient.ExecuteTournamentActionAsync("tournamentLeave", new JsonObject(), elapsed.Token);
                var leaveReceipt = ParseObject(leaveResponse.RootElement);
                if (!VerifyActionReceipt(leaveReceipt, "tournamentLeave"))
                    throw new AgentHostException("tournament-budget-leave-unverified", "Native did not confirm the original Leave handler after the decision budget was exhausted.");
                actionCount++;
                finalReceipt = BuildReceipt("tournamentLeave", leaveReceipt);
                using (var fresh = await stateClient.ReadStateAsync(elapsed.Token)) currentNative = ParseObject(fresh.RootElement);
                ledger.Trace.Add(new JsonObject
                {
                    ["stage"] = "tournament-decision-budget-exhausted-left-native-screen",
                    ["nativeAction"] = "tournamentLeave",
                    ["nativeActionStatus"] = "completed",
                    ["modelDecisionCount"] = ledger.Decisions
                });
                return BuildFailure("tournament-budget-exhausted-left-native-screen",
                    "The decision limit was reached before Native resolved a tournament result; the original Leave handler was used without claiming a winner or reward.");
            }

            throw new AgentHostException("tournament-budget-exhausted", "The bounded tournament observation did not reach a Native resolved result.");
        }
        catch (OperationCanceledException)
        {
            return BuildFailure(cancellationToken.IsCancellationRequested ? "host-stop-requested" : "tournament-timeout",
                cancellationToken.IsCancellationRequested ? "The Host stop signal ended the observation without claiming a result." : "The bounded tournament objective exceeded its elapsed-time limit.");
        }
        catch (AgentHostException exception)
        {
            return BuildFailure(exception.Code, exception.Message);
        }
        catch (Exception exception)
        {
            return BuildFailure("tournament-unexpected-error", exception.GetType().Name);
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
                ["resultKind"] = "tournament-observation",
                ["runId"] = runId,
                ["providerModelId"] = provider.ModelId,
                ["providerConfigurationSource"] = provider.ConfigurationSource,
                ["decisions"] = ledger.Decisions,
                ["actionsExecuted"] = actionCount,
                ["promptTokens"] = ledger.PromptTokens,
                ["completionTokens"] = ledger.CompletionTokens,
                ["providerRouteHistory"] = ledger.Routes.DeepClone(),
                ["initialNativeState"] = initialNative?.DeepClone(),
                ["finalNativeState"] = currentNative?.DeepClone(),
                ["finalReceipt"] = finalReceipt?.DeepClone(),
                ["trace"] = ledger.Trace.DeepClone(),
                ["termination"] = new JsonObject { ["reason"] = code, ["completedByProvider"] = false, ["goalVerified"] = false },
                ["failure"] = message,
                ["failureCode"] = code
            };
        }
    }

    private static JsonObject? GetTournament(JsonObject state) => (state["context"] as JsonObject)?["tournament"] as JsonObject;

    private static bool TryReadSettledResult(JsonObject? tournament, out JsonObject? result)
    {
        result = null;
        if (tournament is null || ReadBoolean(tournament, "isOver") != true) return false;
        var candidate = tournament["result"] as JsonObject;
        if (candidate is null || ReadBoolean(candidate, "resolved") != true) return false;
        result = candidate.DeepClone() as JsonObject;
        return true;
    }

    private static JsonArray BuildActionCatalog(JsonObject state)
    {
        var context = state["context"] as JsonObject;
        if (ReadString(context, "gameState") != "MissionState" || ReadBoolean(context, "inquiryOpen") ||
            ReadBoolean(context, "escapeMenuOpen") || ReadBoolean(context?["captivity"] as JsonObject, "isCaptive"))
            return new JsonArray();
        var tournament = GetTournament(state);
        if (tournament is null || ReadBoolean(tournament, "available") != true || ReadBoolean(tournament, "isOver"))
            return new JsonArray();

        var catalog = new JsonArray();
        if (ReadBoolean(tournament, "canPlayerJoin"))
        {
            catalog.Add(new JsonObject { ["action"] = "tournamentJoin", ["arguments"] = new JsonArray() });
        }
        else
        {
            catalog.Add(new JsonObject { ["action"] = "tournamentSkipAllRounds", ["arguments"] = new JsonArray() });
            catalog.Add(new JsonObject { ["action"] = "tournamentSkipRound", ["arguments"] = new JsonArray() });
        }
        catalog.Add(new JsonObject { ["action"] = "tournamentLeave", ["arguments"] = new JsonArray() });
        return catalog;
    }

    private static bool ShouldSafelyLeave(JsonObject native)
    {
        var state = native["state"] as JsonObject;
        if (state is null || ReadString((state["context"] as JsonObject), "gameState") != "MissionState") return false;
        var tournament = GetTournament(state);
        return tournament is not null && ReadBoolean(tournament, "available") && !ReadBoolean(tournament, "isOver");
    }

    private static bool TryResolveAction(JsonArray catalog, JsonObject? decision, out string? action, out JsonObject? arguments, out string? rejection)
    {
        action = null;
        arguments = null;
        rejection = null;
        var candidate = ReadString(decision, "action");
        if (string.IsNullOrWhiteSpace(candidate))
        {
            rejection = "Choose exactly one currently listed tournament handler action.";
            return false;
        }
        if (!catalog.OfType<JsonObject>().Any(item => ReadString(item, "action") == candidate))
        {
            rejection = "The chosen handler is not currently listed for this tournament state.";
            return false;
        }
        if (decision?["arguments"] is JsonObject supplied && supplied.Count != 0)
        {
            rejection = "Tournament handlers take no arguments; send an empty arguments object.";
            return false;
        }
        action = candidate;
        arguments = new JsonObject();
        return true;
    }

    private static string? ExpectedNativeHandler(string action) => action switch
    {
        "tournamentJoin" => "ExecuteJoinTournament",
        "tournamentSkipRound" => "ExecuteSkipRound",
        "tournamentSkipAllRounds" => "ExecuteSkipAllRounds",
        "tournamentWatchRound" => "ExecuteWatchRound",
        "tournamentLeave" => "ExecuteLeave",
        _ => null
    };

    private static bool VerifyActionReceipt(JsonObject receipt, string action)
    {
        if (ReadString(receipt, "status") != "completed") return false;
        var data = receipt["data"] as JsonObject;
        if (data is null || ReadString(data, "nativeHandler") != ExpectedNativeHandler(action)) return false;
        return data["tournament"] is JsonObject;
    }

    private static JsonObject BuildObservation(JsonObject native, JsonObject state, JsonObject? finalReceipt) => new()
    {
        ["status"] = ReadString(native, "status"),
        ["timeControlMode"] = ReadString(native, "timeControlMode"),
        ["campaignDay"] = native["campaignDay"]?.DeepClone(),
        ["tournament"] = GetTournament(state)?.DeepClone(),
        ["finalReceipt"] = finalReceipt?["data"]?["tournament"]?.DeepClone(),
        ["state"] = state.DeepClone()
    };

    private static JsonObject BuildDecisionRequest(
        string runId,
        string? goal,
        int iteration,
        JsonObject observation,
        JsonObject? previousReceipt,
        JsonObject? feedback,
        JsonArray actionCatalog) => new()
    {
        ["runId"] = runId,
        ["goal"] = goal,
        ["goalKind"] = "bounded-tournament-observation",
        ["goalScopeClassificationRequired"] = false,
        ["previousActionReceipt"] = previousReceipt?.DeepClone(),
        ["decisionFeedback"] = feedback?.DeepClone(),
        ["observation"] = observation.DeepClone(),
        ["allowedActions"] = actionCatalog.DeepClone(),
        ["allowedControls"] = new JsonArray(),
        ["controlArguments"] = new JsonObject(),
        ["iteration"] = iteration
    };

    private static JsonObject BuildReceipt(string action, JsonObject receipt) => new()
    {
        ["action"] = action,
        ["status"] = ReadString(receipt, "status"),
        ["data"] = receipt["data"]?.DeepClone()
    };

    private static JsonObject BuildStep(
        int iteration,
        JsonObject observation,
        JsonObject decision,
        JsonObject receipt,
        string started,
        long startedTicks,
        JsonObject observationAfter) => new()
    {
        ["iteration"] = iteration,
        ["observationBefore"] = observation.DeepClone(),
        ["decision"] = decision.DeepClone(),
        ["actionReceipt"] = receipt.DeepClone(),
        ["actionAttempted"] = decision["action"] is not null,
        ["actionExecuted"] = ReadString(receipt, "status") == "completed",
        ["observationAfter"] = observationAfter.DeepClone(),
        ["timing"] = new JsonObject
        {
            ["providerStartedUtc"] = started,
            ["providerElapsedMilliseconds"] = Math.Round(Stopwatch.GetElapsedTime(startedTicks).TotalMilliseconds, 2),
            ["observationCompletedUtc"] = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture)
        }
    };

    private static JsonObject BuildSuccess(
        string runId,
        IAgentHostDecisionProvider provider,
        JsonObject initialNative,
        JsonObject finalNative,
        JsonObject result,
        JsonObject? finalReceipt,
        DecisionRunLedger ledger,
        int actionsExecuted,
        double campaignDayBefore,
        string? timeControlModeBefore)
    {
        var playerWon = ReadNullableBoolean(result, "playerWon");
        var winnerCharacterId = ReadString(result, "winnerCharacterId");
        var winnerName = ReadString(result, "winnerName");
        var winnerObserved = !string.IsNullOrWhiteSpace(winnerCharacterId) || !string.IsNullOrWhiteSpace(winnerName);
        return new JsonObject
        {
            ["status"] = "completed",
            ["resultKind"] = "tournament-observation",
            ["providerModelId"] = provider.ModelId,
            ["providerConfigurationSource"] = provider.ConfigurationSource,
            ["runId"] = runId,
            ["decisions"] = ledger.Decisions,
            ["actionsExecuted"] = actionsExecuted,
            ["promptTokens"] = ledger.PromptTokens,
            ["completionTokens"] = ledger.CompletionTokens,
            ["providerRouteHistory"] = ledger.Routes.DeepClone(),
            ["initialNativeState"] = initialNative.DeepClone(),
            ["finalNativeState"] = finalNative.DeepClone(),
            ["tournamentEnded"] = true,
            ["winnerObserved"] = winnerObserved,
            ["winnerCharacterId"] = winnerCharacterId,
            ["winnerName"] = winnerName,
            ["playerWonReported"] = playerWon is null ? null : JsonValue.Create(playerWon.Value),
            ["playerVictoryVerified"] = playerWon == true,
            ["rewardVerified"] = false,
            ["renownVerified"] = false,
            ["tournamentResult"] = result.DeepClone(),
            ["finalReceipt"] = finalReceipt?.DeepClone(),
            ["initialCampaignDay"] = double.IsFinite(campaignDayBefore) ? JsonValue.Create(campaignDayBefore) : null,
            ["finalCampaignDay"] = finalNative["campaignDay"]?.DeepClone(),
            ["initialTimeControlMode"] = timeControlModeBefore,
            ["finalTimeControlMode"] = ReadString(finalNative, "timeControlMode"),
            ["termination"] = new JsonObject
            {
                ["reason"] = "native-tournament-result-observed-without-player-victory-or-reward-claim",
                ["completedByProvider"] = false,
                ["goalVerified"] = true
            },
            ["trace"] = ledger.Trace.DeepClone()
        };
    }

    internal static IReadOnlyList<object> RunContractSelfTests()
    {
        var results = new List<object>();
        void Expect(bool condition, string code, string message)
        {
            if (!condition) throw new AgentHostException(code, message);
        }

        var stateWithJoin = new JsonObject
        {
            ["context"] = new JsonObject
            {
                ["gameState"] = "MissionState",
                ["tournament"] = new JsonObject
                {
                    ["available"] = true, ["canPlayerJoin"] = true, ["isOver"] = false,
                    ["isCurrentMatchActive"] = false, ["isTournamentIncomplete"] = true
                }
            }
        };
        var joinCatalog = BuildActionCatalog(stateWithJoin);
        Expect(joinCatalog.Count == 2 && joinCatalog.OfType<JsonObject>().Any(a => ReadString(a, "action") == "tournamentJoin") &&
            joinCatalog.OfType<JsonObject>().Any(a => ReadString(a, "action") == "tournamentLeave") &&
            !joinCatalog.OfType<JsonObject>().Any(a => ReadString(a, "action")?.StartsWith("tournamentSkip", StringComparison.Ordinal) == true),
            "tournament-self-test-join-catalog-wrong", "Before joining, only the original Join and Leave handlers are safe.");
        results.Add(new { scenario = "tournament-catalog-offers-join-or-leave-before-entry", passed = true });

        var stateInMatch = new JsonObject
        {
            ["context"] = new JsonObject
            {
                ["gameState"] = "MissionState",
                ["tournament"] = new JsonObject
                {
                    ["available"] = true, ["canPlayerJoin"] = false, ["isOver"] = false,
                    ["isCurrentMatchActive"] = true, ["isTournamentIncomplete"] = true
                }
            }
        };
        var matchCatalog = BuildActionCatalog(stateInMatch);
        Expect(matchCatalog.Count == 3 && matchCatalog.OfType<JsonObject>().Any(a => ReadString(a, "action") == "tournamentSkipAllRounds") &&
            matchCatalog.OfType<JsonObject>().Any(a => ReadString(a, "action") == "tournamentSkipRound") &&
            matchCatalog.OfType<JsonObject>().Any(a => ReadString(a, "action") == "tournamentLeave") &&
            !matchCatalog.OfType<JsonObject>().Any(a => ReadString(a, "action") == "tournamentJoin"),
            "tournament-self-test-match-catalog-wrong", "After joining, the bounded observation offers Native skip/leave handlers only.");
        results.Add(new { scenario = "tournament-catalog-offers-skip-and-leave-after-entry", passed = true });

        var stateOver = new JsonObject
        {
            ["context"] = new JsonObject
            {
                ["gameState"] = "MissionState",
                ["tournament"] = new JsonObject { ["available"] = true, ["canPlayerJoin"] = false, ["isOver"] = true, ["result"] = new JsonObject { ["resolved"] = true } }
            }
        };
        Expect(BuildActionCatalog(stateOver).Count == 0, "tournament-self-test-over-catalog-wrong", "A resolved tournament must not offer further handlers.");
        Expect(TryReadSettledResult(GetTournament(stateOver), out _), "tournament-self-test-settled-result-false", "Resolved isOver must be detected before any further decision.");
        results.Add(new { scenario = "tournament-settled-result-stops-catalog", passed = true });

        Expect(!TryResolveAction(matchCatalog, new JsonObject { ["action"] = "pause" }, out _, out _, out _),
            "tournament-self-test-accepts-out-of-scope-action", "Out-of-scope actions must be rejected before any Native command.");
        Expect(TryResolveAction(matchCatalog, new JsonObject { ["action"] = "tournamentSkipAllRounds", ["arguments"] = new JsonObject() }, out var resolvedAction, out var resolvedArguments, out _) &&
            resolvedAction == "tournamentSkipAllRounds" && resolvedArguments is not null && resolvedArguments.Count == 0,
            "tournament-self-test-rejects-valid-handler", "A currently listed zero-argument tournament handler must resolve.");
        results.Add(new { scenario = "tournament-action-resolution-is-handler-bounded", passed = true });

        var nullResultReceipt = new JsonObject
        {
            ["status"] = "completed",
            ["data"] = new JsonObject { ["nativeHandler"] = "ExecuteSkipAllRounds", ["tournament"] = new JsonObject { ["isOver"] = true } }
        };
        Expect(VerifyActionReceipt(nullResultReceipt, "tournamentSkipAllRounds"),
            "tournament-self-test-receipt-rejected", "A completed original handler receipt with tournament data must verify.");
        Expect(!VerifyActionReceipt(nullResultReceipt, "tournamentSkipRound"),
            "tournament-self-test-handler-mismatch-accepted", "A receipt for a different Native handler must be rejected.");
        results.Add(new { scenario = "tournament-receipt-binds-exact-native-handler", passed = true });

        var nonPlayerResult = new JsonObject
        {
            ["resolved"] = true,
            ["winnerCharacterId"] = "lord_1_3",
            ["winnerName"] = "曼忒俄斯",
            ["playerWon"] = false
        };
        var fakeProvider = new StaticTournamentProvider();
        var fakeLedger = new DecisionRunLedger(fakeProvider, "tournament-self-test");
        var success = BuildSuccess("self-test", fakeProvider, new JsonObject(), new JsonObject(), nonPlayerResult, null, fakeLedger, 2, double.NaN, "Stop");
        Expect(ReadBoolean(success, "winnerObserved") && !ReadBoolean(success, "playerVictoryVerified") &&
            !ReadBoolean(success, "rewardVerified") && !ReadBoolean(success, "renownVerified") &&
            ReadString(success["termination"] as JsonObject, "reason") == "native-tournament-result-observed-without-player-victory-or-reward-claim",
            "tournament-self-test-non-player-win-misreported", "An NPC winner must not be reported as player victory or reward.");
        results.Add(new { scenario = "tournament-result-never-claims-player-victory-or-reward", passed = true });

        var playerResult = new JsonObject { ["resolved"] = true, ["winnerName"] = "MainHero", ["playerWon"] = true };
        var playerSuccess = BuildSuccess("self-test", fakeProvider, new JsonObject(), new JsonObject(), playerResult, null, fakeLedger, 2, double.NaN, "Stop");
        Expect(ReadBoolean(playerSuccess, "playerVictoryVerified") && !ReadBoolean(playerSuccess, "rewardVerified"),
            "tournament-self-test-player-win-not-reported", "A Native playerWon=true must be reported without claiming unverified rewards.");
        results.Add(new { scenario = "tournament-result-reports-native-player-win-only", passed = true });

        var observation = BuildObservation(new JsonObject { ["campaignDay"] = 91097.3, ["timeControlMode"] = "Stop" }, stateInMatch, null);
        var request = BuildDecisionRequest("self-test", "Observe the current tournament.", 1, observation, null, null, matchCatalog);
        Expect(ReadString(request, "goalKind") == "bounded-tournament-observation" &&
            ReadBoolean(request, "goalScopeClassificationRequired") == false &&
            (request["allowedActions"] as JsonArray)?.Count == 3,
            "tournament-self-test-decision-request-wrong", "The decision request must bind the tournament goal and current handler catalog.");
        results.Add(new { scenario = "tournament-decision-request-binds-current-catalog", passed = true });

        return results;
    }

    private sealed class StaticTournamentProvider : IAgentHostDecisionProvider
    {
        public string ModelId => "tournament-self-test";
        public string ConfigurationSource => "self-test";
        public Task CheckConfiguredModelAsync(CancellationToken cancellationToken) => Task.CompletedTask;
        public Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken) =>
            Task.FromResult(new ProviderDecisionResult("completed", ModelId, 0, 0, "self-test", new JsonObject()));
        public void Dispose() { }
    }

    private static JsonObject ParseObject(JsonElement element) => JsonNode.Parse(element.GetRawText())?.AsObject()
        ?? throw new AgentHostException("native-response-invalid", "Native returned no object.");
    private static int ReadInt(JsonElement element, string key, int fallback) => element.ValueKind == JsonValueKind.Object && element.TryGetProperty(key, out var value) && value.TryGetInt32(out var number) ? number : fallback;
    private static int ReadInt(JsonObject? value, string key, int fallback) => value?[key] is JsonValue node && node.TryGetValue<int>(out var number) ? number : fallback;
    private static double ReadDouble(JsonObject? value, string key, double fallback) => value?[key] is JsonValue node && node.TryGetValue<double>(out var number) ? number : fallback;
    private static bool ReadBoolean(JsonObject? value, string key) => value?[key] is JsonValue node && node.TryGetValue<bool>(out var result) && result;
    private static bool? ReadNullableBoolean(JsonObject? value, string key) => value?[key] is JsonValue node && node.TryGetValue<bool>(out var result) ? result : null;
    private static string? ReadString(JsonObject? value, string key) => value?[key] is JsonValue node && node.TryGetValue<string>(out var text) ? text : null;
    private static string? ReadString(JsonElement value, string key) => value.ValueKind == JsonValueKind.Object && value.TryGetProperty(key, out var property) && property.ValueKind == JsonValueKind.String ? property.GetString() : null;
}
