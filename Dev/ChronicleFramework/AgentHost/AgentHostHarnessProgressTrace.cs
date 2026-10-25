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
                ["providerHttpStatus"] = ReadProviderHttpStatus(result),
                ["actionsExecuted"] = Copy(result, "actionsExecuted"),
                ["decisions"] = Copy(result, "decisions"),
                ["promptTokens"] = Copy(result, "promptTokens"),
                ["completionTokens"] = Copy(result, "completionTokens"),
                ["recruitmentOfferSummary"] = BuildRecruitmentOfferSummary(result["lastRecruitmentOffers"] as JsonObject),
                ["nativeStateBefore"] = result["nativeStateBefore"]?.DeepClone() ?? BuildNativeStateSummary(result["initialNativeState"] as JsonObject),
                ["nativeStateAfter"] = result["nativeStateAfter"]?.DeepClone() ?? BuildNativeStateSummary(result["finalNativeState"] as JsonObject ?? result["finalState"] as JsonObject)
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

    internal static JsonObject? BuildNativeStateSummary(JsonObject? native)
    {
        var state = native?["state"] as JsonObject;
        if (state is null) return null;
        var context = state["context"] as JsonObject;
        var location = state["location"] as JsonObject;
        var economy = state["economy"] as JsonObject;
        var party = state["party"] as JsonObject;
        var captivity = context?["captivity"] as JsonObject;
        var storyMode = state["storyModeEstablishClanStatus"] as JsonObject;
        var menuOptions = new JsonArray();
        if (state["availableMenuOptions"] is JsonArray options)
        {
            foreach (var option in options.OfType<JsonObject>())
                menuOptions.Add(new JsonObject
                {
                    ["id"] = Copy(option, "id"),
                    ["available"] = Copy(option, "available"),
                    ["enabled"] = Copy(option, "enabled"),
                    ["isLeave"] = Copy(option, "isLeave")
                });
        }
        var questIds = new JsonArray();
        if (state["quests"] is JsonArray quests)
        {
            foreach (var quest in quests.OfType<JsonObject>())
                questIds.Add(Copy(quest, "id"));
        }
        return new JsonObject
        {
            ["campaignDay"] = Copy(native, "campaignDay"),
            ["gameState"] = Copy(context, "gameState"),
            ["menuId"] = Copy(context, "menuId"),
            ["currentSettlementId"] = Copy(location, "currentSettlementId"),
            ["targetSettlementId"] = Copy(location, "targetSettlementId"),
            ["targetPartyId"] = Copy(location, "targetPartyId"),
            ["encounteredPartyId"] = Copy(context, "encounteredPartyId"),
            ["encounterActive"] = Copy(context, "encounterActive"),
            ["escapeMenuOpen"] = Copy(context, "escapeMenuOpen"),
            ["inquiryOpen"] = Copy(context, "inquiryOpen"),
            ["inquiry"] = BuildInquirySummary(context?["inquiry"] as JsonObject),
            ["partyScreenOpen"] = state["partyScreen"] is JsonObject,
            ["inventoryScreenOpen"] = state["inventoryScreen"] is JsonObject,
            ["battleSimulationActive"] = context?["battleSimulation"] is JsonObject,
            ["isCaptive"] = Copy(captivity, "isCaptive"),
            ["storyModeStatus"] = Copy(storyMode, "status"),
            ["tutorialCompleted"] = Copy(storyMode, "tutorialCompleted"),
            ["gold"] = Copy(economy, "gold"),
            ["renown"] = Copy(economy, "renown"),
            ["partyMembers"] = Copy(party, "members"),
            ["partySizeLimit"] = Copy(party, "sizeLimit"),
            ["questIds"] = questIds,
            ["availableMenuOptions"] = menuOptions
        };
    }

    private static JsonObject? BuildInquirySummary(JsonObject? inquiry)
    {
        if (inquiry is null) return null;
        return new JsonObject
        {
            ["supported"] = Copy(inquiry, "supported"),
            ["kind"] = Copy(inquiry, "kind"),
            ["title"] = Copy(inquiry, "title"),
            ["text"] = Truncate(ReadString(inquiry, "text"), 800),
            ["affirmative"] = BuildInquiryOption(inquiry["affirmative"] as JsonObject),
            ["negative"] = BuildInquiryOption(inquiry["negative"] as JsonObject),
            ["pauseGameActiveState"] = Copy(inquiry, "pauseGameActiveState")
        };
    }

    private static JsonObject? BuildInquiryOption(JsonObject? option) => option is null ? null : new JsonObject
    {
        ["visible"] = Copy(option, "visible"),
        ["enabled"] = Copy(option, "enabled"),
        ["text"] = Copy(option, "text")
    };

    internal static IReadOnlyList<object> RunContractSelfTests()
    {
        var modalSummary = BuildNativeStateSummary(new JsonObject
        {
            ["state"] = new JsonObject
            {
                ["context"] = new JsonObject
                {
                    ["gameState"] = "MapState", ["escapeMenuOpen"] = false, ["inquiryOpen"] = true,
                    ["inquiry"] = new JsonObject
                    {
                        ["supported"] = true, ["kind"] = "YesNoInquiry", ["token"] = "never-copy-this-token",
                        ["title"] = "通知", ["text"] = "Native alert body",
                        ["affirmative"] = new JsonObject { ["visible"] = true, ["enabled"] = true, ["text"] = "好" },
                        ["negative"] = new JsonObject { ["visible"] = false, ["enabled"] = false, ["text"] = "" },
                        ["pauseGameActiveState"] = true
                    }
                }
            }
        });
        var summarizedInquiry = modalSummary?["inquiry"] as JsonObject;
        if (ReadBoolean(modalSummary, "inquiryOpen") != true || ReadString(summarizedInquiry, "kind") != "YesNoInquiry" ||
            ReadString(summarizedInquiry, "text") != "Native alert body" ||
            ReadString(summarizedInquiry?["affirmative"] as JsonObject, "text") != "好" ||
            summarizedInquiry?.ContainsKey("token") == true || ReadBoolean(modalSummary, "partyScreenOpen") || ReadBoolean(modalSummary, "inventoryScreenOpen"))
            throw new AgentHostException("host-progress-trace-native-modal-self-test", "The bounded progress trace must identify current modal blockers and visible button labels without leaking one-use tokens or claiming unrelated screens.");
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
                ["failureCode"] = "provider-http-error",
                ["actionsExecuted"] = 0,
                ["decisions"] = 2,
                ["promptTokens"] = 900,
                ["completionTokens"] = 60,
                ["failure"] = "FreeLLMAPI returned HTTP 502. do not copy this free-text diagnostic.",
                ["lastRecruitmentOffers"] = new JsonObject
                {
                    ["data"] = new JsonObject
                    {
                        ["gold"] = 100,
                        ["partySize"] = 3,
                        ["partyCapacity"] = 20,
                        ["offers"] = new JsonArray(
                            new JsonObject { ["ownerId"] = "never-copy-notable-id", ["troopId"] = "never-copy-troop-id", ["cost"] = 25, ["available"] = true },
                            new JsonObject { ["ownerId"] = "never-copy-notable-id-2", ["troopId"] = "never-copy-troop-id-2", ["cost"] = 150, ["available"] = true },
                            new JsonObject { ["ownerId"] = "never-copy-notable-id-3", ["troopId"] = "never-copy-troop-id-3", ["cost"] = 10, ["available"] = false })
                    }
                },
                ["initialNativeState"] = new JsonObject
                {
                    ["campaignDay"] = 1,
                    ["state"] = new JsonObject
                    {
                        ["context"] = new JsonObject { ["gameState"] = "MapState", ["menuId"] = "training_field_menu", ["encounterActive"] = true, ["encounteredPartyId"] = "tutorial_training_field" },
                        ["location"] = new JsonObject { ["currentSettlementId"] = "tutorial_training_field" },
                        ["economy"] = new JsonObject { ["gold"] = 1000, ["renown"] = 20 },
                        ["party"] = new JsonObject { ["members"] = 1, ["sizeLimit"] = 20 },
                        ["storyModeEstablishClanStatus"] = new JsonObject { ["status"] = "active" },
                        ["quests"] = new JsonArray(new JsonObject { ["id"] = "rebuild_player_clan_storymode_quest", ["title"] = "do not copy arbitrary title" }),
                        ["availableMenuOptions"] = new JsonArray(new JsonObject { ["id"] = "training_field_leave", ["text"] = "do not copy localized menu text", ["available"] = true, ["enabled"] = true, ["isLeave"] = true })
                    }
                },
                ["finalNativeState"] = new JsonObject
                {
                    ["campaignDay"] = 1,
                    ["state"] = new JsonObject
                    {
                        ["context"] = new JsonObject { ["gameState"] = "MapState", ["menuId"] = null, ["encounterActive"] = false, ["encounteredPartyId"] = null },
                        ["location"] = new JsonObject { ["currentSettlementId"] = null },
                        ["availableMenuOptions"] = new JsonArray()
                    }
                }
            };
            RecordObjectiveSubflowResult("partySize", objectiveResult);
            var objectiveLine = JsonNode.Parse(File.ReadAllLines(path)[2])!.AsObject();
            if (File.ReadAllLines(path).Length != 3 ||
                ReadString(objectiveLine, "event") != "objective-subflow-result" ||
                ReadString(objectiveLine, "objectiveId") != "partySize" ||
                ReadString(objectiveLine, "failureCode") != "provider-http-error" ||
                ReadInt(objectiveLine, "providerHttpStatus") != 502 ||
                ReadInt(objectiveLine["recruitmentOfferSummary"] as JsonObject, "offerCount") != 3 ||
                ReadInt(objectiveLine["recruitmentOfferSummary"] as JsonObject, "availableOfferCount") != 2 ||
                ReadInt(objectiveLine["recruitmentOfferSummary"] as JsonObject, "affordableAvailableOfferCount") != 1 ||
                ReadInt(objectiveLine["recruitmentOfferSummary"] as JsonObject, "lowestAffordableCost") != 25 ||
                ReadString(objectiveLine["nativeStateBefore"] as JsonObject, "menuId") != "training_field_menu" ||
                ReadString(objectiveLine["nativeStateAfter"] as JsonObject, "menuId") is not null ||
                objectiveLine.ToJsonString().Contains("do not copy", StringComparison.Ordinal) ||
                objectiveLine.ToJsonString().Contains("never-copy", StringComparison.Ordinal) ||
                objectiveLine.ContainsKey("failure"))
                throw new AgentHostException("host-progress-trace-objective-subflow", "Harness diagnostics must record bounded failure codes, safe before/after Native state and aggregate recruitment offer counts without copying free-text failures or Native Hero/Troop IDs.");

            Environment.SetEnvironmentVariable("CHRONICLE_HARNESS_MODE", "normal");
            RecordDecision(request.RootElement, new ProviderDecisionResult("completed", "selftest-model", 1, 1, "stop", decision, "selftest/route"));
            if (File.ReadAllLines(path).Length != 3)
                throw new AgentHostException("host-progress-trace-self-test-mode-gate", "Progress tracing must be disabled outside Harness visual-capture/lifecycle modes.");
            return [
                new { scenario = "harness-progress-trace-records-current-modal-and-visible-buttons-without-one-use-token", passed = true },
                new { scenario = "harness-progress-trace-persists-native-decision-and-route-without-free-text-in-visual-capture-and-lifecycle-modes", passed = true },
                new { scenario = "harness-progress-trace-reports-only-aggregate-affordable-recruitment-offer-counts", passed = true },
                new { scenario = "harness-progress-trace-records-objective-subflow-termination-and-safe-native-state-summaries", passed = true }
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

    private static JsonNode? ReadProviderHttpStatus(JsonObject result)
    {
        if (ReadString(result, "failureCode") != "provider-http-error" || ReadString(result, "failure") is not string failure)
            return null;
        var marker = failure.IndexOf("HTTP ", StringComparison.OrdinalIgnoreCase);
        if (marker < 0 || marker + 8 > failure.Length) return null;
        var digits = failure.Substring(marker + 5, 3);
        return int.TryParse(digits, out var status) && status is >= 100 and <= 599 ? JsonValue.Create(status) : null;
    }

    private static JsonObject? BuildRecruitmentOfferSummary(JsonObject? receipt)
    {
        if (receipt?["data"] is not JsonObject data || data["offers"] is not JsonArray offers ||
            ReadInt(data, "gold") is not int gold || ReadInt(data, "partySize") is not int partySize ||
            ReadInt(data, "partyCapacity") is not int partyCapacity) return null;

        var entries = offers.OfType<JsonObject>().ToArray();
        var availableCount = entries.Count(offer => ReadBoolean(offer, "available"));
        var affordableCosts = entries
            .Where(offer => ReadBoolean(offer, "available") && ReadInt(offer, "cost") is int cost && cost <= gold)
            .Select(offer => ReadInt(offer, "cost")!.Value)
            .ToArray();
        return new JsonObject
        {
            ["gold"] = gold,
            ["partySize"] = partySize,
            ["partyCapacity"] = partyCapacity,
            ["offerCount"] = entries.Length,
            ["availableOfferCount"] = availableCount,
            ["affordableAvailableOfferCount"] = affordableCosts.Length,
            ["lowestAffordableCost"] = affordableCosts.Length > 0 ? affordableCosts.Min() : null
        };
    }

    private static bool ReadBoolean(JsonObject? source, string name) =>
        source?[name] is JsonValue value && value.TryGetValue<bool>(out var result) && result;

    private static int? ReadInt(JsonObject? source, string name) =>
        source?[name] is JsonValue value && value.TryGetValue<int>(out var result) ? result : null;

    private static string? ReadString(JsonElement source, string name) =>
        source.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;

    private static string? ReadString(JsonObject? source, string name) =>
        source?[name] is JsonValue value && value.TryGetValue<string>(out var text) ? text : null;

    private static string? Truncate(string? value, int max) =>
        string.IsNullOrEmpty(value) ? value : value.Length <= max ? value : value[..max];
}
