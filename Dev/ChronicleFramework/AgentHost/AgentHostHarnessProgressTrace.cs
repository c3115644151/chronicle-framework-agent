using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal static class AgentHostHarnessProgressTrace
{
    private const long MaximumBytes = 16L * 1024 * 1024;
    private static readonly object WriteGate = new();

    internal static void RecordDecision(JsonElement request, ProviderDecisionResult result)
    {
        var harnessMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        if (!string.Equals(harnessMode, "visual-capture", StringComparison.Ordinal) &&
            !string.Equals(harnessMode, "agent-host-lifecycle-test", StringComparison.Ordinal)) return;
        var directory = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (string.IsNullOrWhiteSpace(directory) || !Directory.Exists(directory)) return;

        try
        {
            var rootPath = Path.GetFullPath(directory).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
            var tracePath = Path.GetFullPath(Path.Combine(rootPath, "AgentHostProgress.jsonl"));
            if (!tracePath.StartsWith(rootPath, StringComparison.OrdinalIgnoreCase)) return;
            var requestNode = JsonNode.Parse(request.GetRawText()) as JsonObject;
            var observation = requestNode?["observation"] as JsonObject;
            var state = observation?["state"] as JsonObject ?? observation;
            var context = state?["context"] as JsonObject;
            var location = state?["location"] as JsonObject;
            var conversation = context?["conversation"] as JsonObject;
            var decision = result.Decision.DeepClone() as JsonObject ?? new JsonObject();
            decision.Remove("rationale");
            decision.Remove("reason");

            var options = new JsonArray();
            if (conversation?["options"] is JsonArray sourceOptions)
            {
                foreach (var source in sourceOptions.OfType<JsonObject>())
                {
                    options.Add(new JsonObject
                    {
                        ["id"] = Copy(source, "id"),
                        ["text"] = Copy(source, "text"),
                        ["clickable"] = Copy(source, "clickable")
                    });
                }
            }

            var quests = new JsonArray();
            if (state?["quests"] is JsonArray sourceQuests)
            {
                foreach (var source in sourceQuests.OfType<JsonObject>())
                    quests.Add(new JsonObject { ["id"] = Copy(source, "id"), ["title"] = Copy(source, "title") });
            }

            var markers = new JsonArray();
            if (state?["settlementOverlayCharacters"] is JsonArray sourceCharacters)
            {
                foreach (var source in sourceCharacters.OfType<JsonObject>())
                {
                    var issueMarkers = new JsonArray();
                    if (source["questMarkers"] is JsonArray sourceMarkers)
                    {
                        foreach (var marker in sourceMarkers.OfType<JsonObject>())
                            issueMarkers.Add(new JsonObject { ["type"] = Copy(marker, "type"), ["title"] = Copy(marker, "title") });
                    }
                    if (issueMarkers.Count > 0)
                        markers.Add(new JsonObject { ["heroId"] = Copy(source, "heroId"), ["markers"] = issueMarkers });
                }
            }

            var economy = state?["economy"] as JsonObject;
            var party = state?["party"] as JsonObject;
            var payload = new JsonObject
            {
                ["event"] = "provider-decision",
                ["utc"] = DateTime.UtcNow.ToString("O", System.Globalization.CultureInfo.InvariantCulture),
                ["runId"] = ReadString(request, "runId"),
                ["modelId"] = result.ModelId,
                ["routedVia"] = result.RoutedVia,
                ["responseFormatMode"] = result.ResponseFormatMode,
                ["promptTokens"] = result.PromptTokens,
                ["completionTokens"] = result.CompletionTokens,
                ["decision"] = decision,
                ["observation"] = new JsonObject
                {
                    ["campaignDay"] = Copy(state, "campaignDay"),
                    ["gameState"] = Copy(context, "gameState"),
                    ["menuId"] = Copy(context, "menuId"),
                    ["timeControlMode"] = Copy(context, "timeControlMode"),
                    ["isWaiting"] = Copy(context, "isWaiting"),
                    ["currentSettlementId"] = Copy(location, "currentSettlementId"),
                    ["targetSettlementId"] = Copy(location, "targetSettlementId"),
                    ["gold"] = Copy(economy, "gold"),
                    ["renown"] = Copy(economy, "renown"),
                    ["partyMembers"] = Copy(party, "members"),
                    ["questCount"] = quests.Count,
                    ["quests"] = quests,
                    ["issueMarkers"] = markers,
                    ["conversationText"] = Truncate(ReadString(conversation, "sentenceText"), 500),
                    ["clickableOptions"] = options
                }
            };
            var line = Encoding.UTF8.GetBytes(payload.ToJsonString() + Environment.NewLine);
            AppendLine(tracePath, line);
        }
        catch
        {
            // Diagnostics must never change or block a real model decision.
        }
    }

    internal static void RecordObjectiveSubflowResult(string objectiveId, JsonObject result)
    {
        var harnessMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        if (!string.Equals(harnessMode, "visual-capture", StringComparison.Ordinal) &&
            !string.Equals(harnessMode, "agent-host-lifecycle-test", StringComparison.Ordinal)) return;
        var directory = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (string.IsNullOrWhiteSpace(directory) || !Directory.Exists(directory)) return;

        try
        {
            var rootPath = Path.GetFullPath(directory).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
            var tracePath = Path.GetFullPath(Path.Combine(rootPath, "AgentHostProgress.jsonl"));
            if (!tracePath.StartsWith(rootPath, StringComparison.OrdinalIgnoreCase)) return;
            var termination = result["termination"] as JsonObject;
            var payload = new JsonObject
            {
                ["event"] = "objective-subflow-result",
                ["utc"] = DateTime.UtcNow.ToString("O", System.Globalization.CultureInfo.InvariantCulture),
                ["objectiveId"] = objectiveId,
                ["status"] = Copy(result, "status"),
                ["termination"] = Copy(termination, "reason") ?? Copy(result, "termination"),
                ["failureCode"] = Copy(result, "failureCode"),
                ["actionsExecuted"] = Copy(result, "actionsExecuted"),
                ["decisions"] = Copy(result, "decisions"),
                ["promptTokens"] = Copy(result, "promptTokens"),
                ["completionTokens"] = Copy(result, "completionTokens")
            };
            AppendLine(tracePath, Encoding.UTF8.GetBytes(payload.ToJsonString() + Environment.NewLine));
        }
        catch
        {
            // Diagnostics must never change or block an objective result.
        }
    }

    private static void AppendLine(string tracePath, byte[] line)
    {
        lock (WriteGate)
        {
            using var stream = new FileStream(tracePath, FileMode.Append, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete);
            if (stream.Length + line.Length > MaximumBytes) return;
            stream.Write(line);
            stream.Flush();
        }
    }

    internal static IReadOnlyList<object> RunContractSelfTests()
    {
        var previousMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var previousTemp = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        var temporaryDirectory = Path.Combine(Path.GetTempPath(), "ChronicleAgentHostProgress-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(temporaryDirectory);
        var path = Path.Combine(temporaryDirectory, "AgentHostProgress.jsonl");
        try
        {
            Environment.SetEnvironmentVariable("CHRONICLE_HARNESS_MODE", "visual-capture");
            Environment.SetEnvironmentVariable("CHRONICLE_HARNESS_TEMP", temporaryDirectory);
            using var request = JsonDocument.Parse("""
                {"runId":"trace-test","observation":{"state":{"campaignDay":12.5,"context":{"gameState":"MapState","menuId":"village","conversation":{"sentenceText":"Tools are needed.","options":[{"id":"issue_offer_player_accept_quest","text":"I can do it.","clickable":true}] }},"location":{"currentSettlementId":"village-1"},"economy":{"gold":920,"renown":20},"party":{"members":5},"quests":[],"settlementOverlayCharacters":[]}}}
                """);
            var decision = JsonNode.Parse("""{"action":"dialogueSelect","arguments":{"OptionId":"issue_offer_player_accept_quest"},"rationale":"Rationale is deliberately excluded."}""")!.AsObject();
            RecordDecision(request.RootElement, new ProviderDecisionResult("completed", "selftest-model", 123, 17, "stop", decision, "selftest/route"));
            var lines = File.ReadAllLines(path);
            if (lines.Length != 1) throw new AgentHostException("host-progress-trace-self-test-line-count", "Harness progress trace did not append exactly one decision.");
            var recorded = JsonNode.Parse(lines[0])!.AsObject();
            var recordedDecision = recorded["decision"] as JsonObject;
            if (ReadString(recorded, "routedVia") != "selftest/route" ||
                ReadString(recordedDecision, "action") != "dialogueSelect" ||
                ReadString(recordedDecision?["arguments"] as JsonObject, "OptionId") != "issue_offer_player_accept_quest" ||
                recordedDecision?.ContainsKey("rationale") == true ||
                ReadString(recorded?["observation"] as JsonObject, "menuId") != "village")
                throw new AgentHostException("host-progress-trace-self-test-content", "Harness trace must preserve route and chosen Native argument without rationale or prompt content.");

            Environment.SetEnvironmentVariable("CHRONICLE_HARNESS_MODE", "agent-host-lifecycle-test");
            RecordDecision(request.RootElement, new ProviderDecisionResult("completed", "selftest-model", 1, 1, "stop", decision, "lifecycle/selftest-route"));
            if (File.ReadAllLines(path).Length != 2)
                throw new AgentHostException("host-progress-trace-lifecycle-mode", "Lifecycle Harness model evaluation must retain the same bounded decision trace as visual-capture runs.");

            var objectiveResult = new JsonObject
            {
                ["status"] = "failed",
                ["termination"] = "recruitment-route-unavailable",
                ["failureCode"] = "recruitment-route-unavailable",
                ["actionsExecuted"] = 0,
                ["decisions"] = 2,
                ["promptTokens"] = 900,
                ["completionTokens"] = 60,
                ["failure"] = "Free text must not be copied into this bounded diagnostics line."
            };
            RecordObjectiveSubflowResult("partySize", objectiveResult);
            var objectiveLine = JsonNode.Parse(File.ReadAllLines(path)[2])!.AsObject();
            if (File.ReadAllLines(path).Length != 3 ||
                ReadString(objectiveLine, "event") != "objective-subflow-result" ||
                ReadString(objectiveLine, "objectiveId") != "partySize" ||
                ReadString(objectiveLine, "failureCode") != "recruitment-route-unavailable" ||
                objectiveLine.ContainsKey("failure"))
                throw new AgentHostException("host-progress-trace-objective-subflow", "Harness diagnostics must record bounded objective result codes without copying free-text failure details.");

            Environment.SetEnvironmentVariable("CHRONICLE_HARNESS_MODE", "normal");
            RecordDecision(request.RootElement, new ProviderDecisionResult("completed", "selftest-model", 1, 1, "stop", decision, "selftest/route"));
            if (File.ReadAllLines(path).Length != 3)
                throw new AgentHostException("host-progress-trace-self-test-mode-gate", "Progress tracing must be disabled outside Harness visual-capture/lifecycle modes.");
            return [
                new { scenario = "harness-progress-trace-persists-native-decision-and-route-without-free-text-in-visual-capture-and-lifecycle-modes", passed = true },
                new { scenario = "harness-progress-trace-records-objective-subflow-termination-codes-without-free-text", passed = true }
            ];
        }
        finally
        {
            Environment.SetEnvironmentVariable("CHRONICLE_HARNESS_MODE", previousMode);
            Environment.SetEnvironmentVariable("CHRONICLE_HARNESS_TEMP", previousTemp);
            if (Directory.Exists(temporaryDirectory)) Directory.Delete(temporaryDirectory, recursive: true);
        }
    }

    private static JsonNode? Copy(JsonObject? source, string name) => source?[name]?.DeepClone();

    private static string? ReadString(JsonElement source, string name) =>
        source.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;

    private static string? ReadString(JsonObject? source, string name) =>
        source?[name] is JsonValue value && value.TryGetValue<string>(out var text) ? text : null;

    private static string? Truncate(string? value, int max) =>
        string.IsNullOrEmpty(value) ? value : value.Length <= max ? value : value[..max];
}
