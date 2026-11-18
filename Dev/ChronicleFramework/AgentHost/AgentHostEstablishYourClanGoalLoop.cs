using System.Text.Json;
using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal static class AgentHostEstablishYourClanGoalLoop
{
    private const string QuestId = "rebuild_player_clan_storymode_quest";
    internal static readonly string[] ObjectiveIds = ["gold", "partySize", "renown", "companions"];

    internal static JsonArray BuildObjectiveActionCatalog(JsonObject? snapshot, IReadOnlySet<string>? supportedObjectives = null)
    {
        var action = new JsonObject
        {
            ["action"] = "selectEstablishYourClanObjective",
            ["arguments"] = new JsonArray("ObjectiveId")
        };
        var unmet = new JsonArray();
        foreach (var objectiveId in ObjectiveIds)
        {
            if ((supportedObjectives is null || supportedObjectives.Contains(objectiveId)) &&
                ReadBoolean(snapshot?[objectiveId] as JsonObject, "met") == false)
                unmet.Add(objectiveId);
        }
        action["argumentValues"] = new JsonObject { ["ObjectiveId"] = unmet };
        return unmet.Count == 0 ? new JsonArray() : new JsonArray(action);
    }

    internal static async Task<IReadOnlyList<object>> RunContractSelfTestsAsync()
    {
        var plannerRequest = new JsonObject
        {
            ["allowedActions"] = new JsonArray(new JsonObject
            {
                ["action"] = "selectEstablishYourClanObjective",
                ["argumentValues"] = new JsonObject { ["ObjectiveId"] = new JsonArray("gold", "partySize", "renown", "companions") }
            })
        };
        var plannerSystemPrompt = AgentHostDecisionCycle.BuildEstablishYourClanGoalPlannerPrompt(plannerRequest);
        if (!plannerSystemPrompt.Contains("str_order_attack", StringComparison.Ordinal) ||
            !plannerSystemPrompt.Contains("real-time Mission", StringComparison.Ordinal) ||
            !plannerSystemPrompt.Contains("when companions remain unmet", StringComparison.Ordinal) ||
            !plannerSystemPrompt.Contains("actual Native action availability", StringComparison.Ordinal) ||
            !plannerSystemPrompt.Contains("nativeProgressionContext.partySizeLimit", StringComparison.Ordinal) ||
            !plannerSystemPrompt.Contains("Tier1", StringComparison.Ordinal) ||
            !plannerSystemPrompt.Contains("do not use temporary MainParty troop-size over-limit volunteer or prisoner recruitment as a substitute", StringComparison.Ordinal) ||
            !plannerSystemPrompt.Contains("choose another feasible objective and replan after the Native state changes", StringComparison.Ordinal) ||
            !plannerSystemPrompt.Contains("Gold objective tracks current carried balance, not cumulative earnings", StringComparison.Ordinal) ||
            !plannerSystemPrompt.Contains("Prefer completing Gold after other feasible objectives", StringComparison.Ordinal) ||
            plannerSystemPrompt.Length > 2200 ||
            plannerSystemPrompt.Contains("privateDiagnostic", StringComparison.Ordinal))
            throw new AgentHostException("establish-clan-planner-native-renown-prerequisite-prompt-missing", "The read-only objective planner must know the Native Renown route, the current party limit/Tier1 over-limit attrition dependency and the volatile current-balance Gold objective.");
        var companionOnlyPlannerPrompt = AgentHostDecisionCycle.BuildEstablishYourClanGoalPlannerPrompt(new JsonObject
        {
            ["allowedActions"] = new JsonArray(new JsonObject
            {
                ["action"] = "selectEstablishYourClanObjective",
                ["argumentValues"] = new JsonObject { ["ObjectiveId"] = new JsonArray("companions") }
            })
        });
        if (companionOnlyPlannerPrompt.Length >= plannerSystemPrompt.Length ||
            companionOnlyPlannerPrompt.Length > 1250 ||
            !companionOnlyPlannerPrompt.Contains("currently clickable Native acceptance", StringComparison.Ordinal) ||
            companionOnlyPlannerPrompt.Contains("str_order_attack", StringComparison.Ordinal) ||
            companionOnlyPlannerPrompt.Contains("nativeProgressionContext.partySizeLimit", StringComparison.Ordinal))
            throw new AgentHostException("establish-clan-planner-only-includes-current-objective-contracts", "The planner must include only rules relevant to currently listed unmet objectives, while retaining the applicable Native route and safety checks.");

        var snapshot = new JsonObject
        {
            ["gold"] = new JsonObject { ["current"] = 2000, ["target"] = 2000, ["met"] = true },
            ["partySize"] = new JsonObject { ["current"] = 8, ["target"] = 20, ["met"] = false },
            ["renown"] = new JsonObject { ["current"] = 50, ["target"] = 50, ["met"] = true },
            ["companions"] = new JsonObject { ["current"] = 0, ["target"] = 1, ["met"] = false }
        };
        var catalog = BuildObjectiveActionCatalog(snapshot);
        var allowedObjectives = catalog[0]?["argumentValues"]?["ObjectiveId"] as JsonArray;
        if (allowedObjectives is null || allowedObjectives.Count != 2 ||
            !allowedObjectives.Any(value => value?.GetValue<string>() == "partySize") ||
            !allowedObjectives.Any(value => value?.GetValue<string>() == "companions") ||
            allowedObjectives.Any(value => value?.GetValue<string>() is "gold" or "renown"))
            throw new AgentHostException("establish-clan-objective-catalog-failed", "The planner catalog must contain only objectives whose fresh Native met flag is false.");
        if (BuildObjectiveActionCatalog(new JsonObject
            {
                ["gold"] = new JsonObject { ["met"] = true }, ["partySize"] = new JsonObject { ["met"] = true },
                ["renown"] = new JsonObject { ["met"] = true }, ["companions"] = new JsonObject { ["met"] = true }
            }).Count != 0)
            throw new AgentHostException("establish-clan-all-goals-met-offered-for-selection", "The planner must not invent a next objective when all four current conditions are met.");
        var journalSnapshot = new JsonArray(
            new JsonObject { ["objectiveId"] = "gold", ["current"] = 2000, ["target"] = 2000 },
            new JsonObject { ["objectiveId"] = "partySize", ["current"] = 8, ["target"] = 20 },
            new JsonObject { ["objectiveId"] = "renown", ["current"] = 50, ["target"] = 50 },
            new JsonObject { ["objectiveId"] = "companions", ["current"] = 0, ["target"] = 1 });
        if (FindLiveMetricDifferences(snapshot, journalSnapshot).Count != 0)
            throw new AgentHostException("establish-clan-journal-consistency-self-test-failed", "Matching Journal and current objective snapshots must be accepted.");
        var authoritativeSnapshot = BuildObjectiveSnapshot(journalSnapshot);
        if (ReadNumber(authoritativeSnapshot["partySize"] as JsonObject, "current") != 8 ||
            ReadNumber(authoritativeSnapshot["partySize"] as JsonObject, "target") != 20 ||
            ReadBoolean(authoritativeSnapshot["partySize"] as JsonObject, "met") != false)
            throw new AgentHostException("establish-clan-journal-authority-self-test-failed", "Planner current/target/met values must come directly from the original Journal task log.");
        var stalePartyTargetSnapshot = (JsonObject)snapshot.DeepClone();
        stalePartyTargetSnapshot["partySize"]!["target"] = 21;
        if (FindLiveMetricDifferences(stalePartyTargetSnapshot, journalSnapshot).Count != 1)
            throw new AgentHostException("establish-clan-live-metric-difference-self-test-failed", "A stale recomputed live target must be preserved as a diagnostic difference from the official Journal target.");

        var native = new FakeNativeClient(snapshot);
        var provider = new FakeDecisionProvider("partySize");
        using var request = JsonDocument.Parse("""
            {"runId":"establish-clan-planner-selftest","goal":"Choose one unmet Establish Your Clan objective.","parentProcessId":321,"maxDecisions":8,"maxElapsedSeconds":10,"allowedActionNames":["questDetails"]}
            """);
        var result = await RunAsync(request.RootElement, native, native, provider, CancellationToken.None);
        var providerCatalog = provider.FirstRequest?["allowedActions"] as JsonArray;
        if (ReadString(result, "status") != "completed" || ReadString(result, "resultKind") != "objective-plan" || ReadString(result["selection"] as JsonObject, "objectiveId") != "partySize" ||
            ReadBoolean(result["termination"] as JsonObject, "goalVerified") == true || native.QuestDetailsReads != 1 || native.MutatingActionCount != 0 ||
            providerCatalog is null ||
            ReadString(provider.FirstRequest?["observation"] as JsonObject, "scope") != "read-only-active-storymode-quest-objective-planning" ||
            provider.FirstRequest?["observation"]?["state"]?["objectiveSnapshot"] is not JsonObject modelObjectiveSnapshot ||
            modelObjectiveSnapshot.Count != ObjectiveIds.Length ||
            provider.FirstRequest?["observation"]?["state"]?["nativeProgressionContext"] is not JsonObject nativeProgressionContext ||
            ReadInt(nativeProgressionContext, "partySizeLimit", -1) != 20 || ReadInt(nativeProgressionContext, "clanTier", -1) != 0 ||
            !providerCatalog[0]!["argumentValues"]!["ObjectiveId"]!.AsArray().Any(value => value?.GetValue<string>() == "partySize") ||
            providerCatalog[0]!["argumentValues"]!["ObjectiveId"]!.AsArray().Any(value => value?.GetValue<string>() is "gold" or "renown"))
            throw new AgentHostException("establish-clan-objective-planner-runtime-failed", "The read-only planner did not select an unmet objective from the exact current quest catalog.");

        var correctionNative = new FakeNativeClient(snapshot);
        var correctionProvider = new FakeObjectiveCorrectionProvider("companions", "partySize");
        var correctionSupported = new HashSet<string>(StringComparer.Ordinal) { "partySize" };
        var correctedPlan = await RunAsync(request.RootElement, correctionNative, correctionNative, correctionProvider, CancellationToken.None,
            supportedObjectives: correctionSupported);
        var correctedCatalog = correctionProvider.Requests.Count > 1 ? correctionProvider.Requests[1]["allowedActions"] as JsonArray : null;
        if (ReadString(correctedPlan, "status") != "completed" || ReadString(correctedPlan["selection"] as JsonObject, "objectiveId") != "partySize" ||
            ReadInt(correctedPlan, "decisions", 0) != 2 || correctionProvider.CallCount != 2 || correctionNative.MutatingActionCount != 0 ||
            correctedCatalog?[0]?["argumentValues"]?["ObjectiveId"]?.AsArray().Any(value => value?.GetValue<string>() == "companions") == true ||
            ReadString(correctionProvider.Requests[1]["decisionFeedback"] as JsonObject, "kind") != "objective-selection-rejected-before-native" ||
            ReadString(correctionProvider.Requests[1]["decisionFeedback"] as JsonObject, "requiredNextStep")?.Contains("partySize", StringComparison.Ordinal) != true ||
            ReadString(correctionProvider.Requests[1]["decisionFeedback"] as JsonObject, "requiredNextStep")?.Contains("companions", StringComparison.Ordinal) == true)
            throw new AgentHostException("establish-clan-objective-invalid-choice-correction-failed", "An excluded objective must be rejected before gameplay, then receive one bounded correction request constrained to current supported routes.");

        var truncatedNative = new FakeNativeClient(snapshot);
        var truncatedProvider = new FakeTruncatedObjectiveProvider("partySize");
        var truncatedPlan = await RunAsync(request.RootElement, truncatedNative, truncatedNative, truncatedProvider, CancellationToken.None);
        if (ReadString(truncatedPlan, "status") != "completed" || ReadString(truncatedPlan["selection"] as JsonObject, "objectiveId") != "partySize" ||
            ReadInt(truncatedPlan, "decisions", 0) != 2 || truncatedProvider.CallCount != 2 || truncatedNative.MutatingActionCount != 0 ||
            ReadString(truncatedProvider.Requests[1]["decisionFeedback"] as JsonObject, "kind") != "decision-rejected-before-native" ||
            ReadString(truncatedProvider.Requests[1]["decisionFeedback"] as JsonObject, "code") != "provider-response-truncated" ||
            ReadString(truncatedProvider.Requests[1]["decisionFeedback"] as JsonObject, "requiredNextStep")?.Contains("only one compact JSON object", StringComparison.Ordinal) != true)
            throw new AgentHostException("establish-clan-objective-truncated-provider-recovery-failed", "A truncated planning response must get one concise, no-action retry before it can terminate the parent objective loop.");

        var inconsistentSnapshot = (JsonObject)snapshot.DeepClone();
        inconsistentSnapshot["partySize"]!["current"] = 20;
        inconsistentSnapshot["partySize"]!["met"] = true;
        var inconsistentProvider = new FakeDecisionProvider("partySize");
        var inconsistentNative = new FakeNativeClient(inconsistentSnapshot);
        var inconsistentResult = await RunAsync(request.RootElement, inconsistentNative, inconsistentNative, inconsistentProvider, CancellationToken.None);
        var resultJournalSnapshot = inconsistentResult["objectiveSnapshot"]?["partySize"] as JsonObject;
        if (ReadString(inconsistentResult, "status") != "completed" || ReadString(inconsistentResult["selection"] as JsonObject, "objectiveId") != "partySize" ||
            ReadNumber(resultJournalSnapshot, "current") != 8 || ReadNumber(resultJournalSnapshot, "target") != 20 ||
            (inconsistentResult["liveMetricDifferences"] as JsonArray)?.Count != 1 || inconsistentProvider.CallCount != 1)
            throw new AgentHostException("establish-clan-live-metric-lag-blocked-planner", "When live MainParty data is newer than the original Journal cache, selection must still follow Journal and retain the difference diagnostically.");

        var inactiveNative = new FakeNativeClient(snapshot, activeQuest: false);
        var inactiveProvider = new FakeDecisionProvider("partySize");
        try
        {
            _ = await RunAsync(request.RootElement, inactiveNative, inactiveNative, inactiveProvider, CancellationToken.None);
            throw new AgentHostException("establish-clan-inactive-quest-planner-accepted", "The planner accepted a Campaign without the exact active StoryMode quest.");
        }
        catch (AgentHostException exception) when (exception.Code == "establish-clan-quest-no-longer-active")
        {
            if (inactiveNative.QuestDetailsReads != 0 || inactiveProvider.CallCount != 0)
                throw new AgentHostException("establish-clan-inactive-quest-work-leaked", "Inactive Quest rejection must happen before Journal reads or model calls.");
        }
        return [
            new { scenario = "establish-clan-objective-planner-knows-native-renown-simulation-and-party-growth-prerequisite", passed = true },
            new { scenario = "establish-clan-planner-projects-only-currently-listed-objective-guidance", allFourPromptCharacters = plannerSystemPrompt.Length, companionOnlyPromptCharacters = companionOnlyPlannerPrompt.Length, passed = true },
            new { scenario = "establish-clan-planner-observes-current-native-capacity-and-tier", passed = true },
            new { scenario = "establish-clan-planner-offers-only-currently-unmet-objectives", passed = true },
            new { scenario = "establish-clan-planner-reads-native-quest-and-never-mutates-campaign", passed = true },
            new { scenario = "establish-clan-planner-boundedly-retries-a-truncated-provider-response-before-native-actions", passed = true },
            new { scenario = "establish-clan-journal-progress-is-authoritative-when-live-metrics-lag", passed = true },
            new { scenario = "establish-clan-planner-stops-before-read-without-active-quest", passed = true }
        ];
    }

    internal static async Task<JsonObject> RunAsync(
        JsonElement request,
        IAgentHostCampaignNativeClient client,
        IAgentHostQuestDetailsNativeClient questDetailsClient,
        IAgentHostDecisionProvider provider,
        CancellationToken cancellationToken,
        int priorDecisions = 0,
        long priorPromptTokens = 0,
        long priorCompletionTokens = 0,
        JsonArray? priorTrace = null,
        JsonArray? priorProviderRouteHistory = null,
        IReadOnlySet<string>? supportedObjectives = null,
        JsonObject? observedQuestDetails = null,
        JsonObject? observedNativeState = null,
        bool activeQuestAlreadyVerified = false)
    {
        if (!activeQuestAlreadyVerified)
        {
            using var current = await client.ReadStateAsync(cancellationToken);
            observedNativeState ??= JsonNode.Parse(current.RootElement.GetRawText())?.AsObject();
            if (!HasActiveQuest(current.RootElement))
                throw new AgentHostException("establish-clan-quest-no-longer-active", "The exact StoryMode quest is no longer in the fresh Native active-quest list.");
        }

        JsonObject receipt;
        if (observedQuestDetails is not null)
            receipt = observedQuestDetails.DeepClone() as JsonObject
                ?? throw new AgentHostException("establish-clan-quest-details-invalid", "The supplied fresh Native Quest Journal could not be cloned.");
        else
        {
            using var questDetails = await questDetailsClient.ReadQuestDetailsAsync(QuestId, cancellationToken);
            receipt = JsonNode.Parse(questDetails.RootElement.GetRawText())?.AsObject()
                ?? throw new AgentHostException("establish-clan-quest-details-invalid", "Native returned no quest-details receipt.");
        }
        cancellationToken.ThrowIfCancellationRequested();
        if (ReadString(receipt, "status") != "completed" || receipt["data"] is not JsonObject data ||
            ReadString(data, "questId") != QuestId)
            throw new AgentHostException("establish-clan-progress-unavailable", "The current Native quest-details read did not expose the exact active StoryMode quest.");
        var journalObjectives = BuildJournalObjectives(data);
        var snapshot = BuildObjectiveSnapshot(journalObjectives);
        ValidateSnapshot(snapshot);
        var liveSnapshot = data["storyModeEstablishClan"] as JsonObject;
        var liveMetricDifferences = liveSnapshot is null ? new JsonArray() : FindLiveMetricDifferences(liveSnapshot, journalObjectives);
        var targetConsistency = new JsonObject { ["consistent"] = true, ["authoritativeSource"] = "original-journal-log-progress" };
        var actionCatalog = BuildObjectiveActionCatalog(snapshot, supportedObjectives);
        if (actionCatalog.Count == 0)
        {
            var allConditionsMet = ObjectiveIds.All(objectiveId => ReadBoolean(snapshot[objectiveId] as JsonObject, "met") == true);
            var unimplementedObjectives = new JsonArray(ObjectiveIds
                .Where(objectiveId => ReadBoolean(snapshot[objectiveId] as JsonObject, "met") == false &&
                                      supportedObjectives is not null && !supportedObjectives.Contains(objectiveId))
                .Select(objectiveId => (JsonNode?)JsonValue.Create(objectiveId))
                .ToArray());
            return new JsonObject
            {
                ["status"] = "completed",
                ["resultKind"] = allConditionsMet ? "no-incomplete-objective" : "no-implemented-objective-route",
                ["providerModelId"] = provider.ModelId,
                ["providerConfigurationSource"] = provider.ConfigurationSource,
                ["decisions"] = 0,
                ["actionsExecuted"] = 1,
                ["questDetails"] = receipt.DeepClone(),
                ["journalObjectiveSnapshot"] = journalObjectives,
                ["objectiveSnapshot"] = snapshot.DeepClone(),
                ["unimplementedObjectives"] = unimplementedObjectives,
                ["targetConsistency"] = targetConsistency.DeepClone(),
                ["liveMetricDifferences"] = liveMetricDifferences.DeepClone(),
                ["selection"] = null,
                ["termination"] = new JsonObject { ["reason"] = "no-currently-unmet-objective", ["completedByProvider"] = false, ["goalVerified"] = false },
                ["note"] = allConditionsMet
                    ? "No objective was selected because all four currently observed objective conditions are met; this does not claim Native Quest completion."
                    : "No objective was selected because each currently unmet condition lacks an integrated executor in this Host build. This does not claim Native Quest completion."
            };
        }

        var modelRequest = new JsonObject
        {
            ["runId"] = ReadString(request, "runId"),
            ["goal"] = ReadString(request, "goal"),
            ["goalKind"] = "active-storymode-establish-your-clan-objective-selection",
            ["nativeQuestId"] = QuestId,
            ["nativeQuestTitle"] = ReadString(data, "title"),
            ["observation"] = new JsonObject
            {
                ["scope"] = "read-only-active-storymode-quest-objective-planning",
                ["state"] = new JsonObject
                {
                    ["questId"] = QuestId,
                    ["title"] = ReadString(data, "title"),
                    ["objectiveSnapshot"] = snapshot.DeepClone(),
                    ["journalObjectiveSnapshot"] = journalObjectives.DeepClone(),
                    ["targetConsistency"] = targetConsistency.DeepClone(),
                    ["liveMetricDifferences"] = liveMetricDifferences.DeepClone(),
                    ["nativeProgressionContext"] = BuildNativeProgressionContext(observedNativeState)
                }
            },
            ["journalObjectiveSnapshot"] = journalObjectives.DeepClone(),
            ["objectiveSnapshot"] = snapshot.DeepClone(),
            ["targetConsistency"] = targetConsistency.DeepClone(),
            ["liveMetricDifferences"] = liveMetricDifferences.DeepClone(),
            ["allowedActions"] = actionCatalog,
            ["allowedControls"] = new JsonArray()
        };
        var routeHistory = priorProviderRouteHistory?.DeepClone() as JsonArray ?? new JsonArray();
        var trace = priorTrace?.DeepClone() as JsonArray ?? new JsonArray();
        ProviderDecisionResult decision = null!;
        string? selectedObjective = null;
        JsonObject? selectedGoal = null;
        var plannerDecisionCount = 0;
        long plannerPromptTokens = 0;
        long plannerCompletionTokens = 0;
        var validSelection = false;
        string? lastProviderFailureCode = null;
        for (var attempt = 0; attempt < 2; attempt++)
        {
            modelRequest["iteration"] = priorDecisions + plannerDecisionCount + 1;
            if (attempt == 1)
            {
                if (lastProviderFailureCode is not null)
                    modelRequest["decisionFeedback"] = AgentHostProviderDecisionRecovery.BuildFeedback(lastProviderFailureCode, actionCatalog, new JsonArray());
                else
                {
                    var allowedObjectiveIds = actionCatalog[0]!["argumentValues"]!["ObjectiveId"]!.AsArray()
                        .Select(value => value?.GetValue<string>())
                        .Where(value => !string.IsNullOrWhiteSpace(value))
                        .ToArray();
                    modelRequest["decisionFeedback"] = new JsonObject
                    {
                        ["kind"] = "objective-selection-rejected-before-native",
                        ["requiredNextStep"] = "The allowed ObjectiveId values are exactly [" + string.Join(", ", allowedObjectiveIds) + "]. Choose one listed value; do not repeat an omitted route. No Native action was taken."
                    };
                }
            }

            try
            {
                decision = await AgentHostDecisionCycle.DecideEstablishYourClanGoalAsync(provider, modelRequest, cancellationToken);
            }
            catch (AgentHostException exception) when (AgentHostProviderDecisionRecovery.CanRetry(exception.Code, attempt))
            {
                plannerDecisionCount++;
                lastProviderFailureCode = exception.Code;
                routeHistory.Add(new JsonObject
                {
                    ["decision"] = priorDecisions + plannerDecisionCount,
                    ["requestedModelId"] = provider.ModelId,
                    ["status"] = "provider-failure-before-decision",
                    ["failureCode"] = exception.Code,
                    ["nativeActionSent"] = false
                });
                trace.Add(new JsonObject
                {
                    ["iteration"] = priorDecisions + plannerDecisionCount,
                    ["stage"] = "objective-planner-provider-retry",
                    ["failureCode"] = exception.Code,
                    ["nativeActionSent"] = false,
                    ["retryAttempt"] = attempt + 1
                });
                continue;
            }
            plannerDecisionCount++;
            plannerPromptTokens += decision.PromptTokens ?? 0;
            plannerCompletionTokens += decision.CompletionTokens ?? 0;
            routeHistory.Add(new JsonObject
            {
                ["decision"] = priorDecisions + plannerDecisionCount,
                ["requestedModelId"] = provider.ModelId,
                ["responseModelId"] = decision.ModelId,
                ["routedVia"] = decision.RoutedVia,
                ["responseFormatMode"] = decision.ResponseFormatMode,
                ["promptTokens"] = decision.PromptTokens,
                ["completionTokens"] = decision.CompletionTokens
            });

            selectedObjective = ReadString(decision.Decision["arguments"] as JsonObject, "ObjectiveId");
            selectedGoal = selectedObjective is null ? null : snapshot[selectedObjective] as JsonObject;
            validSelection = ReadString(decision.Decision, "action") == "selectEstablishYourClanObjective" &&
                selectedGoal is not null && ReadBoolean(selectedGoal, "met") == false &&
                actionCatalog[0]!["argumentValues"]!["ObjectiveId"]!.AsArray().Any(value => value?.GetValue<string>() == selectedObjective);
            trace.Add(new JsonObject
            {
                ["iteration"] = priorDecisions + plannerDecisionCount,
                ["decision"] = decision.Decision.DeepClone(),
                ["planningOnly"] = true,
                ["nativeActionExecuted"] = false,
                ["nativeQuestDetailsRead"] = QuestId,
                ["selectedObjectiveId"] = selectedObjective,
                ["allowedObjectiveIds"] = actionCatalog[0]!["argumentValues"]!["ObjectiveId"]!.DeepClone(),
                ["selectionValid"] = validSelection,
                ["rejectionCode"] = validSelection ? null : "establish-clan-objective-selection-invalid"
            });
            if (validSelection) break;
        }

        if (!validSelection)
            return new JsonObject
            {
                ["status"] = "failed",
                ["resultKind"] = "objective-selection-invalid",
                ["providerModelId"] = provider.ModelId,
                ["providerConfigurationSource"] = provider.ConfigurationSource,
                ["decisions"] = priorDecisions + plannerDecisionCount,
                ["actionsExecuted"] = 1,
                ["promptTokens"] = priorPromptTokens + plannerPromptTokens,
                ["completionTokens"] = priorCompletionTokens + plannerCompletionTokens,
                ["providerRouteHistory"] = routeHistory,
                ["trace"] = trace,
                ["questDetails"] = receipt.DeepClone(),
                ["objectiveSnapshot"] = snapshot.DeepClone(),
                ["journalObjectiveSnapshot"] = journalObjectives.DeepClone(),
                ["targetConsistency"] = targetConsistency.DeepClone(),
                ["liveMetricDifferences"] = liveMetricDifferences.DeepClone(),
                ["selection"] = null,
                ["failureCode"] = lastProviderFailureCode ?? "establish-clan-objective-selection-invalid",
                ["failure"] = lastProviderFailureCode is null
                    ? "The model selected no current unmet objective after one bounded catalog correction."
                    : "The objective planner exhausted its single bounded retry after a provider response could not be parsed.",
                ["termination"] = new JsonObject { ["reason"] = "objective-selection-invalid-after-correction", ["completedByProvider"] = false, ["goalVerified"] = false }
            };

        return new JsonObject
        {
            ["status"] = "completed",
            ["resultKind"] = "objective-plan",
            ["providerModelId"] = provider.ModelId,
            ["providerConfigurationSource"] = provider.ConfigurationSource,
            ["decisions"] = priorDecisions + plannerDecisionCount,
            ["actionsExecuted"] = 1,
            ["promptTokens"] = priorPromptTokens + plannerPromptTokens,
            ["completionTokens"] = priorCompletionTokens + plannerCompletionTokens,
            ["providerRouteHistory"] = routeHistory,
            ["trace"] = trace,
            ["questDetails"] = receipt.DeepClone(),
            ["objectiveSnapshot"] = snapshot.DeepClone(),
            ["journalObjectiveSnapshot"] = journalObjectives.DeepClone(),
            ["targetConsistency"] = targetConsistency.DeepClone(),
            ["liveMetricDifferences"] = liveMetricDifferences,
            ["selection"] = new JsonObject
            {
                ["objectiveId"] = selectedObjective,
                ["current"] = selectedGoal!["current"]?.DeepClone(),
                ["target"] = selectedGoal["target"]?.DeepClone(),
                ["met"] = false,
                ["rationale"] = decision.Decision["rationale"]?.DeepClone(),
                ["providerModelId"] = decision.ModelId,
                ["routedVia"] = decision.RoutedVia,
                ["promptTokens"] = decision.PromptTokens,
                ["completionTokens"] = decision.CompletionTokens
            },
            ["termination"] = new JsonObject { ["reason"] = "unmet-objective-selected", ["completedByProvider"] = true, ["goalVerified"] = false },
            ["note"] = "This result selects a next objective only. It neither executes gameplay actions nor claims that the original StoryMode quest is complete."
        };
    }

    internal static bool HasActiveQuest(JsonElement native)
    {
        if (!native.TryGetProperty("state", out var state) || state.ValueKind != JsonValueKind.Object ||
            !state.TryGetProperty("quests", out var quests) || quests.ValueKind != JsonValueKind.Array) return false;
        return quests.EnumerateArray().Any(quest => ReadString(quest, "id") == QuestId);
    }

    private static void ValidateSnapshot(JsonObject snapshot)
    {
        foreach (var objectiveId in ObjectiveIds)
        {
            if (snapshot[objectiveId] is not JsonObject objective || objective["current"] is null || objective["target"] is null ||
                objective["met"] is not JsonValue metValue || !metValue.TryGetValue<bool>(out _))
                throw new AgentHostException("establish-clan-objective-snapshot-incomplete", "The Native objective snapshot must include current, target and met for all four StoryMode conditions.");
        }
    }

    internal static JsonArray BuildJournalObjectives(JsonObject questData)
    {
        if (questData["journalStages"] is not JsonArray stages)
            throw new AgentHostException("establish-clan-journal-objectives-missing", "The observed Quest Journal does not contain its objective list.");
        var taskStages = stages.OfType<JsonObject>().Where(stage => ReadBoolean(stage, "hasTask") == true).ToArray();
        if (taskStages.Length != ObjectiveIds.Length)
            throw new AgentHostException("establish-clan-journal-objectives-incomplete", "The observed StoryMode Journal must expose exactly four numeric objective stages.");
        var result = new JsonArray();
        for (var index = 0; index < ObjectiveIds.Length; index++)
        {
            var stage = taskStages[index];
            var current = ReadNumber(stage, "currentProgress");
            var target = ReadNumber(stage, "targetProgress");
            if (current is null || target is null)
                throw new AgentHostException("establish-clan-journal-objective-values-missing", "Each visible StoryMode objective stage must include numeric current and target progress.");
            result.Add(new JsonObject
            {
                ["objectiveId"] = ObjectiveIds[index],
                ["current"] = current.Value,
                ["target"] = target.Value,
                ["description"] = ReadString(stage, "description")
            });
        }
        return result;
    }

    private static JsonObject? BuildNativeProgressionContext(JsonObject? nativeReceipt)
    {
        var state = nativeReceipt?["state"] as JsonObject;
        if (state is null) return null;
        var context = state["context"] as JsonObject;
        var identity = state["identity"] as JsonObject;
        var party = state["party"] as JsonObject;
        var economy = state["economy"] as JsonObject;
        var location = state["location"] as JsonObject;
        var captivity = context?["captivity"] as JsonObject;
        return new JsonObject
        {
            ["gameState"] = context?["gameState"]?.DeepClone(),
            ["menuId"] = context?["menuId"]?.DeepClone(),
            ["currentSettlementId"] = location?["currentSettlementId"]?.DeepClone(),
            ["clanTier"] = identity?["clanTier"]?.DeepClone(),
            ["clanRenown"] = economy?["renown"]?.DeepClone(),
            ["gold"] = economy?["gold"]?.DeepClone(),
            ["partyMembers"] = party?["members"]?.DeepClone(),
            ["partySizeLimit"] = party?["sizeLimit"]?.DeepClone(),
            ["partyIsMoving"] = party?["isMoving"]?.DeepClone(),
            ["encounterActive"] = context?["encounterActive"]?.DeepClone(),
            ["isCaptive"] = captivity?["isCaptive"]?.DeepClone()
        };
    }

    internal static JsonObject BuildObjectiveSnapshot(JsonArray journalObjectives)
    {
        var result = new JsonObject();
        foreach (var objectiveId in ObjectiveIds)
        {
            var objective = journalObjectives.OfType<JsonObject>().FirstOrDefault(stage => ReadString(stage, "objectiveId") == objectiveId);
            var current = ReadNumber(objective, "current");
            var target = ReadNumber(objective, "target");
            if (current is null || target is null)
                throw new AgentHostException("establish-clan-journal-objective-values-missing", "The original StoryMode Journal did not provide current and target progress for every objective.");
            result[objectiveId] = new JsonObject
            {
                ["current"] = current.Value,
                ["target"] = target.Value,
                ["met"] = current.Value >= target.Value
            };
        }
        return result;
    }

    internal static JsonArray FindLiveMetricDifferences(JsonObject snapshot, JsonArray journalObjectives)
    {
        var differences = new JsonArray();
        foreach (var stage in journalObjectives.OfType<JsonObject>())
        {
            var objectiveId = ReadString(stage, "objectiveId");
            var native = objectiveId is null ? null : snapshot[objectiveId] as JsonObject;
            var journalCurrent = ReadNumber(stage, "current");
            var journalTarget = ReadNumber(stage, "target");
            var nativeCurrent = ReadNumber(native, "current");
            var nativeTarget = ReadNumber(native, "target");
            if (native is null || journalCurrent != nativeCurrent || journalTarget != nativeTarget)
                differences.Add(new JsonObject
                {
                    ["objectiveId"] = objectiveId,
                    ["journalCurrent"] = journalCurrent,
                    ["journalTarget"] = journalTarget,
                    ["nativeCurrent"] = nativeCurrent,
                    ["nativeTarget"] = nativeTarget
                });
        }
        return differences;
    }

    private static string? ReadString(JsonObject? value, string key) => value?[key] is JsonValue item && item.TryGetValue<string>(out var text) ? text : null;
    private static string? ReadString(JsonElement value, string key) => value.ValueKind == JsonValueKind.Object && value.TryGetProperty(key, out var property) && property.ValueKind == JsonValueKind.String ? property.GetString() : null;
    private static int ReadInt(JsonObject? value, string key, int fallback = 0) => value?[key] is JsonValue item && item.TryGetValue<int>(out var integer) ? integer : fallback;
    private static bool? ReadBoolean(JsonObject? value, string key) => value?[key] is JsonValue item && item.TryGetValue<bool>(out var result) ? result : null;
    private static double? ReadNumber(JsonObject? value, string key)
    {
        if (value?[key] is not JsonValue item) return null;
        if (item.TryGetValue<double>(out var number)) return number;
        if (item.TryGetValue<int>(out var integer)) return integer;
        if (item.TryGetValue<long>(out var longInteger)) return longInteger;
        return null;
    }

    private sealed class FakeNativeClient(JsonObject snapshot, bool activeQuest = true) : IAgentHostCampaignNativeClient, IAgentHostQuestDetailsNativeClient
    {
        internal int QuestDetailsReads { get; private set; }
        internal int MutatingActionCount { get; private set; }

        public Task<JsonDocument> ReadStateAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var quests = activeQuest
                ? new JsonArray(new JsonObject { ["id"] = QuestId, ["title"] = "Establish Your Clan" })
                : new JsonArray();
            var state = new JsonObject
            {
                ["status"] = "completed", ["processId"] = 321,
                ["state"] = new JsonObject
                {
                    ["quests"] = quests,
                    ["context"] = new JsonObject { ["gameState"] = "MapState", ["encounterActive"] = false },
                    ["identity"] = new JsonObject { ["clanTier"] = 0 },
                    ["party"] = new JsonObject { ["members"] = (int)(ReadNumber(snapshot["partySize"] as JsonObject, "current") ?? 0), ["sizeLimit"] = 20, ["isMoving"] = false },
                    ["economy"] = new JsonObject
                    {
                        ["gold"] = (int)(ReadNumber(snapshot["gold"] as JsonObject, "current") ?? 0),
                        ["renown"] = (int)(ReadNumber(snapshot["renown"] as JsonObject, "current") ?? 0)
                    }
                }
            };
            return Task.FromResult(JsonDocument.Parse(state.ToJsonString()));
        }

        public Task<JsonDocument> ExecuteCampaignActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            MutatingActionCount++;
            throw new AgentHostException("establish-clan-self-test-native-mutation", "The planner attempted to use the generic Campaign action interface for quest inspection.");
        }

        public Task<JsonDocument> ReadQuestDetailsAsync(string questId, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (questId != QuestId) throw new AgentHostException("establish-clan-self-test-wrong-quest-read", "The planner attempted to inspect any Quest other than its exact active StoryMode objective.");
            QuestDetailsReads++;
            var data = new JsonObject
            {
                ["questId"] = QuestId,
                ["title"] = "Establish Your Clan",
                ["journalStages"] = new JsonArray(
                    new JsonObject { ["hasTask"] = true, ["currentProgress"] = 2000, ["targetProgress"] = 2000, ["description"] = "Gain 1000 denars" },
                    new JsonObject { ["hasTask"] = true, ["currentProgress"] = 8, ["targetProgress"] = 20, ["description"] = "Raise a party" },
                    new JsonObject { ["hasTask"] = true, ["currentProgress"] = 50, ["targetProgress"] = 50, ["description"] = "Gain renown" },
                    new JsonObject { ["hasTask"] = true, ["currentProgress"] = 0, ["targetProgress"] = 1, ["description"] = "Find a companion" }),
                ["storyModeEstablishClan"] = snapshot.DeepClone()
            };
            return Task.FromResult(JsonDocument.Parse(new JsonObject { ["status"] = "completed", ["data"] = data }.ToJsonString()));
        }
    }

    private sealed class FakeObjectiveCorrectionProvider(params string[] selections) : IAgentHostDecisionProvider
    {
        internal int CallCount { get; private set; }
        internal List<JsonObject> Requests { get; } = new();
        public string ModelId => "deterministic-establish-clan-objective-correction-self-test";
        public string ConfigurationSource => "harness-fake-provider";
        public Task CheckConfiguredModelAsync(CancellationToken cancellationToken) => Task.CompletedTask;
        public Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (CallCount >= selections.Length) throw new AgentHostException("objective-correction-provider-exhausted", "The correction self-test received more decisions than configured.");
            Requests.Add(JsonNode.Parse(request.GetRawText())?.AsObject() ?? new JsonObject());
            var selectedObjective = selections[CallCount++];
            return Task.FromResult(new ProviderDecisionResult("completed", ModelId, 5, 1, "self-test",
                new JsonObject
                {
                    ["action"] = "selectEstablishYourClanObjective",
                    ["arguments"] = new JsonObject { ["ObjectiveId"] = selectedObjective },
                    ["rationale"] = "Choose one objective."
                }, "self-test", "json_schema"));
        }
        public void Dispose() { }
    }

    private sealed class FakeDecisionProvider(string selectedObjective) : IAgentHostDecisionProvider
    {
        internal JsonObject? FirstRequest { get; private set; }
        internal int CallCount { get; private set; }
        public string ModelId => "deterministic-establish-clan-planner-self-test";
        public string ConfigurationSource => "harness-fake-provider";
        public Task CheckConfiguredModelAsync(CancellationToken cancellationToken) => Task.CompletedTask;
        public Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            CallCount++;
            FirstRequest = JsonNode.Parse(request.GetRawText())?.AsObject();
            return Task.FromResult(new ProviderDecisionResult("completed", ModelId, null, null, "self-test", new JsonObject
            {
                ["action"] = "selectEstablishYourClanObjective",
                ["arguments"] = new JsonObject { ["ObjectiveId"] = selectedObjective },
                ["rationale"] = "Select a currently unmet objective."
            }));
        }
        public void Dispose() { }
    }

    private sealed class FakeTruncatedObjectiveProvider(string selectedObjective) : IAgentHostDecisionProvider
    {
        internal int CallCount { get; private set; }
        internal List<JsonObject> Requests { get; } = new();
        public string ModelId => "deterministic-establish-clan-truncated-provider-self-test";
        public string ConfigurationSource => "harness-fake-provider";
        public Task CheckConfiguredModelAsync(CancellationToken cancellationToken) => Task.CompletedTask;
        public Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Requests.Add(JsonNode.Parse(request.GetRawText())?.AsObject() ?? new JsonObject());
            if (CallCount++ == 0)
                throw new AgentHostException("provider-response-truncated", "The fake remote route returned a truncated structured response.");
            return Task.FromResult(new ProviderDecisionResult("completed", ModelId, 1, 1, "self-test", new JsonObject
            {
                ["action"] = "selectEstablishYourClanObjective",
                ["arguments"] = new JsonObject { ["ObjectiveId"] = selectedObjective },
                ["rationale"] = "Select the currently listed objective after bounded recovery."
            }));
        }
        public void Dispose() { }
    }
}
