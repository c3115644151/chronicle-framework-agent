using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal static class AgentHostQuestTroopScreenLoop
{
    internal static IReadOnlyList<object> RunContractSelfTests()
    {
        var assignment = new JsonObject { ["currentCount"] = 1, ["requiredCount"] = 3, ["doneAvailable"] = false, ["cancelAvailable"] = true };
        var screen = new JsonObject
        {
            ["rightMembers"] = new JsonArray(
                new JsonObject { ["troopId"] = "main_hero", ["count"] = 1, ["transferable"] = false },
                new JsonObject { ["troopId"] = "imperial_recruit", ["count"] = 9, ["transferable"] = true },
                new JsonObject { ["troopId"] = "CharacterObject_1643", ["count"] = 1, ["transferable"] = false })
        };
        var transferCatalog = BuildActionCatalog(screen, assignment);
        var transferOptions = transferCatalog.OfType<JsonObject>().Where(action => ReadString(action, "action") == "questTroopTransfer").ToArray();
        if (transferOptions.Length != 1 || transferOptions[0]["arguments"]?["TroopId"]?.GetValue<string>() != "imperial_recruit" ||
            transferOptions[0]["arguments"]?["QuestTroopSourceSide"]?.GetValue<string>() != "mainParty" ||
            transferCatalog.OfType<JsonObject>().Any(action => ReadString(action, "action") == "questTroopScreenDone"))
            throw new AgentHostException("quest-troop-screen-self-test-transfer-catalog-failed", "The current QuestTroopManage catalog must offer only visible transferable ordinary troops and must not expose Done before the Native requirement is met.");

        var doneCatalog = BuildActionCatalog(screen, new JsonObject { ["currentCount"] = 3, ["requiredCount"] = 3, ["doneAvailable"] = true, ["cancelAvailable"] = true });
        if (doneCatalog.OfType<JsonObject>().Count() != 2 ||
            !doneCatalog.OfType<JsonObject>().Any(action => ReadString(action, "action") == "questTroopScreenDone") ||
            doneCatalog.OfType<JsonObject>().Any(action => ReadString(action, "action") == "questTroopTransfer"))
            throw new AgentHostException("quest-troop-screen-self-test-done-catalog-failed", "The current Native Done action must be exposed only when the PartyScreen says Done is enabled and progress is complete.");

        if (!TryResolveDecision(new JsonObject { ["action"] = "questTroopTransfer", ["arguments"] = new JsonObject { ["TroopId"] = "imperial_recruit", ["QuestTroopSourceSide"] = "mainParty" } }, transferCatalog, out var action, out _) ||
            action != "questTroopTransfer" ||
            TryResolveDecision(new JsonObject { ["action"] = "questTroopTransfer", ["arguments"] = new JsonObject { ["TroopId"] = "unobserved", ["QuestTroopSourceSide"] = "mainParty" } }, transferCatalog, out _, out _))
            throw new AgentHostException("quest-troop-screen-self-test-current-target-binding-failed", "The Host must bind each troop transfer to an exact current row and source side.");

        var gangIssueScreen = new JsonObject
        {
            ["mode"] = "TroopsManage",
            ["issueTroopAssignment"] = new JsonObject
            {
                ["kind"] = "gangLeaderRecruitHandoff", ["questId"] = "issue_123_quest", ["questGiverHeroId"] = "gang-leader",
                ["assignedCount"] = 2, ["assignmentLimit"] = 12, ["doneAvailable"] = true, ["cancelAvailable"] = true
            },
            ["rightMembers"] = new JsonArray(
                new JsonObject { ["troopId"] = "looter", ["count"] = 7, ["transferable"] = true, ["isHero"] = false },
                new JsonObject { ["troopId"] = "imperial_recruit", ["count"] = 4, ["transferable"] = false, ["isHero"] = false },
                new JsonObject { ["troopId"] = "companion", ["count"] = 1, ["transferable"] = false, ["isHero"] = true })
        };
        var gangProgress = BuildAssignmentProgress(gangIssueScreen);
        var gangCatalog = BuildActionCatalog(gangIssueScreen, gangProgress);
        using var gangRoot = JsonDocument.Parse(new JsonObject
        {
            ["state"] = new JsonObject
            {
                ["context"] = new JsonObject { ["gameState"] = "PartyState" },
                ["partyScreen"] = gangIssueScreen.DeepClone()
            }
        }.ToJsonString());
        var gangTransfers = gangCatalog.OfType<JsonObject>().Where(action => ReadString(action, "action") == "questTroopTransfer").ToArray();
        if (!IsActive(gangRoot.RootElement) || gangTransfers.Length != 1 ||
            ReadString(gangTransfers[0]["arguments"] as JsonObject, "TroopId") != "looter" ||
            !gangCatalog.OfType<JsonObject>().Any(action => ReadString(action, "action") == "questTroopScreenDone") ||
            !gangCatalog.OfType<JsonObject>().Any(action => ReadString(action, "action") == "questTroopScreenCancel"))
            throw new AgentHostException("quest-troop-screen-self-test-gang-leader-partial-handoff-catalog-failed", "The original Gang Leader TroopsManage screen must expose only Native-transferable Bandit member rows while allowing Native-enabled partial Done and Cancel.");
        if (!TryResolveDecision(new JsonObject { ["action"] = "questTroopTransfer", ["arguments"] = new JsonObject { ["TroopId"] = "looter", ["QuestTroopSourceSide"] = "mainParty" } }, gangCatalog, out var gangAction, out _) ||
            gangAction != "questTroopTransfer" ||
            TryResolveDecision(new JsonObject { ["action"] = "questTroopTransfer", ["arguments"] = new JsonObject { ["TroopId"] = "imperial_recruit", ["QuestTroopSourceSide"] = "mainParty" } }, gangCatalog, out _, out _))
            throw new AgentHostException("quest-troop-screen-self-test-gang-leader-current-bandit-binding-failed", "The Gang Leader hand-in must bind the model to a current Native-transferable ordinary Bandit row and reject unrelated members.");

        return [
            new { scenario = "quest-troop-screen-native-catalog-tracks-current-progress-and-excludes-heroes-and-stale-troops", passed = true },
            new { scenario = "gang-leader-troop-handoff-uses-native-transferability-and-native-partial-done", passed = true }
        ];
    }

    internal static bool IsActive(JsonElement root)
    {
        var state = ReadObject(root, "state");
        var context = ReadObject(state, "context");
        var screen = ReadObject(state, "partyScreen");
        var issueAssignment = ReadObject(screen, "issueTroopAssignment");
        return ReadString(context, "gameState") == "PartyState" &&
            (ReadString(screen, "mode") == "QuestTroopManage" ||
             ReadString(screen, "mode") == "TroopsManage" && ReadString(issueAssignment, "kind") == "gangLeaderRecruitHandoff");
    }

    internal static async Task<JsonObject> RunAsync(
        JsonObject runRequest,
        IAgentHostCampaignNativeClient client,
        IAgentHostQuestTroopScreenNativeClient nativeClient,
        IAgentHostDecisionProvider provider,
        CancellationToken cancellationToken,
        int priorDecisions = 0,
        long priorPromptTokens = 0,
        long priorCompletionTokens = 0,
        JsonArray? priorTrace = null,
        JsonArray? priorProviderRouteHistory = null)
    {
        var ledger = new DecisionRunLedger(
            provider,
            ReadString(runRequest, "runId") ?? "establish-your-clan",
            priorDecisions, priorPromptTokens, priorCompletionTokens, priorTrace, priorProviderRouteHistory);
        var actionsExecuted = 0;
        JsonObject? previousReceipt = null;

        JsonObject BuildResult(string status, string reason, string? message)
        {
            var result = new JsonObject
            {
                ["status"] = status,
                ["decisions"] = ledger.Decisions,
                ["actionsExecuted"] = actionsExecuted,
                ["promptTokens"] = ledger.PromptTokens,
                ["completionTokens"] = ledger.CompletionTokens,
                ["trace"] = ledger.Trace.DeepClone(),
                ["providerRouteHistory"] = ledger.Routes.DeepClone(),
                ["termination"] = new JsonObject { ["reason"] = reason }
            };
            if (!string.IsNullOrWhiteSpace(message)) result["failure"] = message;
            return result;
        }

        var decisionLimit = Math.Max(ledger.Decisions,
            Math.Clamp(ReadInt(runRequest, "maxDecisions", AgentHostCampaignLoop.MaxCumulativeDecisions), 1, AgentHostCampaignLoop.MaxCumulativeDecisions));
        for (var step = 0; step < decisionLimit && ledger.Decisions < decisionLimit; step++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            using var current = await client.ReadStateAsync(cancellationToken);
            if (!IsActive(current.RootElement))
            {
                return BuildResult("completed", "native-issue-troop-party-screen-closed",
                    "The original Native Issue troop-assignment screen is no longer active; no Issue completion was inferred.");
            }

            var root = JsonNode.Parse(current.RootElement.GetRawText())?.AsObject()
                ?? throw new AgentHostException("quest-troop-screen-state-invalid", "Native returned no current state document.");
            var state = root["state"] as JsonObject ?? new JsonObject();
            var partyScreen = state["partyScreen"] as JsonObject ?? new JsonObject();
            var assignment = BuildAssignmentProgress(partyScreen);
            var catalog = BuildActionCatalog(partyScreen, assignment);
            if (catalog.Count == 0)
            {
                ledger.Trace.Add(new JsonObject
                {
                    ["stage"] = "quest-troop-screen-no-safe-native-action",
                    ["partyScreen"] = partyScreen.DeepClone()
                });
                return BuildResult("failed", "quest-troop-screen-no-safe-action",
                    "The Native Issue troop-assignment screen is active but offers no currently enabled safe transfer, Done, or Cancel action.");
            }

            var modelRequest = new JsonObject
            {
                ["runId"] = ledger.RunId,
                ["goal"] = ReadString(runRequest, "goal") ?? "Complete the original StoryMode Establish Your Clan quest.",
                ["decisionNumber"] = ledger.NextDecisionNumber,
                ["observation"] = new JsonObject
                {
                    ["context"] = (state["context"] as JsonObject)?.DeepClone(),
                    ["party"] = (state["party"] as JsonObject)?.DeepClone(),
                    ["storyModeEstablishClan"] = (state["storyModeEstablishClan"] as JsonObject)?.DeepClone(),
                    ["partyScreen"] = partyScreen.DeepClone()
                },
                ["previousActionReceipt"] = previousReceipt?.DeepClone(),
                ["allowedActions"] = catalog.DeepClone()
            };

            var providerStarted = Stopwatch.GetTimestamp();
            var decision = await AgentHostDecisionCycle.DecideQuestTroopScreenAsync(provider, modelRequest, cancellationToken);
            ledger.RecordDecision(decision);

            if (!TryResolveDecision(decision.Decision, catalog, out var action, out var arguments))
            {
                ledger.Trace.Add(new JsonObject
                {
                    ["stage"] = "quest-troop-screen-decision-rejected-before-native",
                    ["decision"] = decision.Decision.DeepClone(),
                    ["allowedActions"] = catalog.DeepClone(),
                    ["providerElapsedMs"] = Stopwatch.GetElapsedTime(providerStarted).TotalMilliseconds
                });
                return BuildResult("failed", "quest-troop-screen-invalid-native-action",
                    "The model did not choose one exact action and argument set from the current Native Issue troop-assignment screen.");
            }

            using var response = await nativeClient.ExecuteQuestTroopScreenActionAsync(action, arguments, cancellationToken);
            var receipt = JsonNode.Parse(response.RootElement.GetRawText())?.AsObject()
                ?? throw new AgentHostException("quest-troop-screen-native-receipt-invalid", "Native returned no receipt for the current Issue troop-assignment action.");
            previousReceipt = receipt.DeepClone() as JsonObject;
            actionsExecuted++;
            ledger.Trace.Add(new JsonObject
            {
                ["stage"] = "quest-troop-screen-native-action",
                ["action"] = action,
                ["arguments"] = arguments.DeepClone(),
                ["receipt"] = receipt.DeepClone(),
                ["providerElapsedMs"] = Stopwatch.GetElapsedTime(providerStarted).TotalMilliseconds
            });

            if (ReadString(receipt, "status") != "completed")
                return BuildResult("failed", "quest-troop-screen-native-action-rejected",
                    "The selected native PartyVM action was rejected; no follow-up action was attempted from stale screen state.");

            if (action is "questTroopScreenDone" or "questTroopScreenCancel")
            {
                using var after = await client.ReadStateAsync(cancellationToken);
                if (IsActive(after.RootElement))
                    return BuildResult("failed", "quest-troop-screen-close-unverified",
                        "Native accepted the PartyVM control, but a fresh observation still reports the Issue assignment screen active.");
                var result = BuildResult(action == "questTroopScreenDone" ? "completed" : "interrupted",
                    action == "questTroopScreenDone" ? "native-quest-alternative-party-assignment-submitted" : "native-quest-alternative-party-assignment-cancelled",
                    action == "questTroopScreenDone"
                        ? "The original PartyVM Done handler closed the assignment screen; Issue outcome remains unverified until the Native Issue/Journal is observed again."
                        : "The original PartyVM cancel handler closed the assignment screen; no Issue success was claimed.");
                result["postActionState"] = JsonNode.Parse(after.RootElement.GetRawText())?.AsObject();
                return result;
            }
        }

        return BuildResult("failed", "quest-troop-screen-decision-limit",
            "The Native Issue troop-assignment screen remained open at the shared Campaign decision limit; no clock action or direct roster edit was used.");
    }

    private static JsonObject BuildAssignmentProgress(JsonObject partyScreen)
    {
        if (partyScreen["questTroopAssignment"] is JsonObject questAssignment)
            return questAssignment.DeepClone() as JsonObject ?? new JsonObject();

        var issueAssignment = partyScreen["issueTroopAssignment"] as JsonObject;
        if (issueAssignment is null || ReadString(issueAssignment, "kind") != "gangLeaderRecruitHandoff") return new JsonObject();
        return new JsonObject
        {
            ["currentCount"] = issueAssignment["assignedCount"]?.DeepClone(),
            ["requiredCount"] = issueAssignment["assignmentLimit"]?.DeepClone(),
            ["doneAvailable"] = issueAssignment["doneAvailable"]?.DeepClone(),
            ["cancelAvailable"] = issueAssignment["cancelAvailable"]?.DeepClone(),
            ["assignmentKind"] = "gangLeaderRecruitHandoff"
        };
    }

    internal static JsonArray BuildActionCatalog(JsonObject partyScreen, JsonObject assignment)
    {
        var result = new JsonArray();
        var progress = ReadInt(assignment, "currentCount", -1);
        var required = ReadInt(assignment, "requiredCount", -1);
        var doneAvailable = ReadBoolean(assignment, "doneAvailable");
        if (progress >= 0 && required >= 0 && progress < required)
        {
            if (partyScreen["rightMembers"] is JsonArray rows)
            {
                foreach (var row in rows.OfType<JsonObject>())
                {
                    var troopId = ReadString(row, "troopId");
                    if (string.IsNullOrWhiteSpace(troopId) || ReadBoolean(row, "transferable") != true || ReadBoolean(row, "isHero") == true || ReadInt(row, "count", 0) <= 0)
                        continue;
                    result.Add(new JsonObject
                    {
                        ["action"] = "questTroopTransfer",
                        ["arguments"] = new JsonObject { ["TroopId"] = troopId, ["QuestTroopSourceSide"] = "mainParty" }
                    });
                }
            }
        }
        if (doneAvailable)
            result.Add(new JsonObject { ["action"] = "questTroopScreenDone", ["arguments"] = new JsonObject() });
        if (ReadBoolean(assignment, "cancelAvailable"))
            result.Add(new JsonObject { ["action"] = "questTroopScreenCancel", ["arguments"] = new JsonObject() });
        return result;
    }

    private static bool TryResolveDecision(JsonObject decision, JsonArray catalog, out string action, out JsonObject arguments)
    {
        var selectedAction = ReadString(decision, "action") ?? string.Empty;
        action = selectedAction;
        arguments = new JsonObject();
        if (string.IsNullOrWhiteSpace(selectedAction) || decision["arguments"] is not JsonObject supplied) return false;
        var allowed = catalog.OfType<JsonObject>().FirstOrDefault(item => ReadString(item, "action") == selectedAction);
        if (allowed? ["arguments"] is not JsonObject allowedArguments) return false;
        if (selectedAction == "questTroopTransfer")
        {
            var troopId = ReadString(supplied, "TroopId") ?? ReadString(supplied, "troopId");
            var side = ReadString(supplied, "QuestTroopSourceSide") ?? ReadString(supplied, "sourceSide");
            if (supplied.Count != 2 || ReadString(allowedArguments, "TroopId") != troopId || ReadString(allowedArguments, "QuestTroopSourceSide") != side || side != "mainParty") return false;
            arguments["troopId"] = troopId;
            arguments["sourceSide"] = side;
            return true;
        }
        return supplied.Count == 0 && allowedArguments.Count == 0 && selectedAction is "questTroopScreenDone" or "questTroopScreenCancel";
    }

    private static JsonObject? ReadObject(JsonElement parent, string property) =>
        parent.TryGetProperty(property, out var value) && value.ValueKind == JsonValueKind.Object
            ? JsonNode.Parse(value.GetRawText()) as JsonObject
            : null;
    private static JsonObject? ReadObject(JsonObject? parent, string property) => parent?[property] as JsonObject;

    private static string? ReadString(JsonObject? value, string property) => value?[property]?.GetValue<string>();
    private static string? ReadString(JsonElement parent, string property) =>
        parent.TryGetProperty(property, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;
    private static int ReadInt(JsonObject? value, string property, int fallback) => value?[property] is JsonValue node && node.TryGetValue<int>(out var result) ? result : fallback;
    private static bool ReadBoolean(JsonObject? value, string property) => value?[property] is JsonValue node && node.TryGetValue<bool>(out var result) && result;
}
