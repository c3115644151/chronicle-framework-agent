using System.Text.Json;
using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal static class AgentHostEstablishYourClanGoalLoop
{
    private const string QuestId = "rebuild_player_clan_storymode_quest";
    private static readonly string[] ObjectiveIds = ["gold", "partySize", "renown", "companions"];

    internal static JsonArray BuildObjectiveActionCatalog(JsonObject? snapshot)
    {
        var action = new JsonObject
        {
            ["action"] = "selectEstablishYourClanObjective",
            ["arguments"] = new JsonArray("ObjectiveId")
        };
        var unmet = new JsonArray();
        foreach (var objectiveId in ObjectiveIds)
        {
            if (ReadBoolean(snapshot?[objectiveId] as JsonObject, "met") == false)
                unmet.Add(objectiveId);
        }
        action["argumentValues"] = new JsonObject { ["ObjectiveId"] = unmet };
        return unmet.Count == 0 ? new JsonArray() : new JsonArray(action);
    }

    internal static async Task<IReadOnlyList<object>> RunContractSelfTestsAsync()
    {
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
        if (FindJournalInconsistencies(snapshot, journalSnapshot).Count != 0)
            throw new AgentHostException("establish-clan-journal-consistency-self-test-failed", "Matching Journal and current objective snapshots must be accepted.");
        var stalePartyTargetSnapshot = (JsonObject)snapshot.DeepClone();
        stalePartyTargetSnapshot["partySize"]!["target"] = 21;
        if (FindJournalInconsistencies(stalePartyTargetSnapshot, journalSnapshot).Count != 1)
            throw new AgentHostException("establish-clan-stale-dynamic-target-self-test-failed", "A stale Journal hideout-size target must be preserved as a mismatch and fail closed.");

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
            !providerCatalog[0]!["argumentValues"]!["ObjectiveId"]!.AsArray().Any(value => value?.GetValue<string>() == "partySize") ||
            providerCatalog[0]!["argumentValues"]!["ObjectiveId"]!.AsArray().Any(value => value?.GetValue<string>() is "gold" or "renown"))
            throw new AgentHostException("establish-clan-objective-planner-runtime-failed", "The read-only planner did not select an unmet objective from the exact current quest catalog.");

        var inconsistentSnapshot = (JsonObject)snapshot.DeepClone();
        inconsistentSnapshot["partySize"]!["target"] = 21;
        var inconsistentProvider = new FakeDecisionProvider("partySize");
        var inconsistentNative = new FakeNativeClient(inconsistentSnapshot);
        var inconsistentResult = await RunAsync(request.RootElement, inconsistentNative, inconsistentNative, inconsistentProvider, CancellationToken.None);
        if (ReadString(inconsistentResult, "status") != "blocked" || inconsistentProvider.CallCount != 0 ||
            ReadString(inconsistentResult["termination"] as JsonObject, "reason") != "journal-native-target-mismatch")
            throw new AgentHostException("establish-clan-journal-mismatch-model-call-leaked", "A mismatched Journal/dynamic target must stop before calling the model.");

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
            new { scenario = "establish-clan-planner-offers-only-currently-unmet-objectives", passed = true },
            new { scenario = "establish-clan-planner-reads-native-quest-and-never-mutates-campaign", passed = true },
            new { scenario = "establish-clan-journal-dynamic-threshold-mismatch-fails-before-model-call", passed = true },
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
        JsonArray? priorProviderRouteHistory = null)
    {
        using var current = await client.ReadStateAsync(cancellationToken);
        if (!HasActiveQuest(current.RootElement))
            throw new AgentHostException("establish-clan-quest-no-longer-active", "The exact StoryMode quest is no longer in the fresh Native active-quest list.");

        using var questDetails = await questDetailsClient.ReadQuestDetailsAsync(QuestId, cancellationToken);
        var receipt = JsonNode.Parse(questDetails.RootElement.GetRawText())?.AsObject()
            ?? throw new AgentHostException("establish-clan-quest-details-invalid", "Native returned no quest-details receipt.");
        if (ReadString(receipt, "status") != "completed" || receipt["data"] is not JsonObject data ||
            ReadString(data, "questId") != QuestId || data["storyModeEstablishClan"] is not JsonObject snapshot)
            throw new AgentHostException("establish-clan-progress-unavailable", "The current Native quest-details read did not expose the active StoryMode objective snapshot.");

        ValidateSnapshot(snapshot);
        var journalObjectives = BuildJournalObjectives(data);
        var inconsistencies = FindJournalInconsistencies(snapshot, journalObjectives);
        if (inconsistencies.Count > 0)
            return new JsonObject
            {
                ["status"] = "blocked",
                ["decisions"] = 0,
                ["actionsExecuted"] = 1,
                ["questDetails"] = receipt.DeepClone(),
                ["journalObjectiveSnapshot"] = journalObjectives,
                ["objectiveSnapshot"] = snapshot.DeepClone(),
                ["targetConsistency"] = new JsonObject { ["consistent"] = false, ["differences"] = inconsistencies },
                ["selection"] = null,
                ["termination"] = new JsonObject { ["reason"] = "journal-native-target-mismatch", ["completedByProvider"] = false, ["goalVerified"] = false }
            };
        var actionCatalog = BuildObjectiveActionCatalog(snapshot);
        if (actionCatalog.Count == 0)
            return new JsonObject
            {
                ["status"] = "completed",
                ["resultKind"] = "no-incomplete-objective",
                ["decisions"] = 0,
                ["actionsExecuted"] = 1,
                ["questDetails"] = receipt.DeepClone(),
                ["journalObjectiveSnapshot"] = journalObjectives,
                ["targetConsistency"] = new JsonObject { ["consistent"] = true },
                ["selection"] = null,
                ["termination"] = new JsonObject { ["reason"] = "no-currently-unmet-objective", ["completedByProvider"] = false, ["goalVerified"] = false },
                ["note"] = "No objective was selected because all four currently observed objective conditions are met; this does not claim Native Quest completion."
            };

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
                    ["targetConsistency"] = new JsonObject { ["consistent"] = true }
                }
            },
            ["journalObjectiveSnapshot"] = journalObjectives.DeepClone(),
            ["objectiveSnapshot"] = snapshot.DeepClone(),
            ["targetConsistency"] = new JsonObject { ["consistent"] = true },
            ["allowedActions"] = actionCatalog,
            ["allowedControls"] = new JsonArray()
        };
        var decision = await AgentHostDecisionCycle.DecideEstablishYourClanGoalAsync(provider, modelRequest, cancellationToken);
        var selectedObjective = ReadString(decision.Decision["arguments"] as JsonObject, "ObjectiveId");
        var selectedGoal = selectedObjective is null ? null : snapshot[selectedObjective] as JsonObject;
        if (ReadString(decision.Decision, "action") != "selectEstablishYourClanObjective" ||
            selectedGoal is null || ReadBoolean(selectedGoal, "met") != false ||
            !actionCatalog[0]!["argumentValues"]!["ObjectiveId"]!.AsArray().Any(value => value?.GetValue<string>() == selectedObjective))
            throw new AgentHostException("establish-clan-objective-selection-invalid", "The model did not select exactly one currently unmet, catalog-listed objective.");

        var routeHistory = priorProviderRouteHistory?.DeepClone() as JsonArray ?? new JsonArray();
        routeHistory.Add(new JsonObject
        {
            ["decision"] = priorDecisions + 1,
            ["requestedModelId"] = provider.ModelId,
            ["responseModelId"] = decision.ModelId,
            ["routedVia"] = decision.RoutedVia,
            ["responseFormatMode"] = decision.ResponseFormatMode,
            ["promptTokens"] = decision.PromptTokens,
            ["completionTokens"] = decision.CompletionTokens
        });
        var trace = priorTrace?.DeepClone() as JsonArray ?? new JsonArray();
        trace.Add(new JsonObject
        {
            ["iteration"] = priorDecisions + 1,
            ["decision"] = decision.Decision.DeepClone(),
            ["planningOnly"] = true,
            ["nativeActionExecuted"] = false,
            ["nativeQuestDetailsRead"] = QuestId,
            ["selectedObjectiveId"] = selectedObjective
        });
        return new JsonObject
        {
            ["status"] = "completed",
            ["resultKind"] = "objective-plan",
            ["decisions"] = priorDecisions + 1,
            ["actionsExecuted"] = 1,
            ["promptTokens"] = priorPromptTokens + (decision.PromptTokens ?? 0),
            ["completionTokens"] = priorCompletionTokens + (decision.CompletionTokens ?? 0),
            ["providerRouteHistory"] = routeHistory,
            ["trace"] = trace,
            ["questDetails"] = receipt.DeepClone(),
            ["objectiveSnapshot"] = snapshot.DeepClone(),
            ["journalObjectiveSnapshot"] = journalObjectives.DeepClone(),
            ["targetConsistency"] = new JsonObject { ["consistent"] = true },
            ["selection"] = new JsonObject
            {
                ["objectiveId"] = selectedObjective,
                ["current"] = selectedGoal["current"]?.DeepClone(),
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

    private static bool HasActiveQuest(JsonElement native)
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

    private static JsonArray BuildJournalObjectives(JsonObject questData)
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

    private static JsonArray FindJournalInconsistencies(JsonObject snapshot, JsonArray journalObjectives)
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
            var state = new JsonObject { ["status"] = "completed", ["processId"] = 321, ["state"] = new JsonObject { ["quests"] = quests } };
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
}
