using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

// One small, atomically replaced snapshot of what the agent is doing right now. The in-game panel reads this
// file instead of the full progress log, so presentation never depends on harness-only artifacts.
internal static class AgentHostLiveStatus
{
    internal const string FileName = "agent-live-status.json";
    private const int MaximumDebugObservationBytes = 24 * 1024;
    private static readonly object WriteGate = new();

    internal static string DefaultStatusPath() =>
        Path.Combine(NativeMailboxClient.GetDefaultProtocolRoot(), FileName);

    internal static void RecordDecision(JsonElement request, ProviderDecisionResult result)
    {
        try { Write(BuildSnapshot(request, result)); }
        catch { }
    }

    internal static void RecordFailure(JsonElement request, string failureCode)
    {
        try
        {
            var snapshot = BuildSnapshot(request, null);
            snapshot["status"] = "provider-failure";
            snapshot["failureCode"] = failureCode;
            snapshot["attention"] = BuildAttention(failureCode);
            Write(snapshot);
        }
        catch { }
    }

    // A player takeover or an ESC pause parks the agent between Native actions. Keeping the previous progress
    // fields makes the panel show why the agent is idle instead of blanking the run.
    internal static void RecordHold(string reason, string? path = null)
    {
        try
        {
            var snapshot = ReadCurrentSnapshot(path);
            snapshot["status"] = "held";
            snapshot["holdReason"] = AgentHostControlHold.SanitizeReason(reason);
            snapshot["phase"] = "waiting for the player to hand control back";
            snapshot["thinking"] = string.Equals(snapshot["holdReason"]?.ToString(), AgentHostControlHold.EscapeMenuReason, StringComparison.Ordinal)
                ? "ESC 暂停中，关闭菜单后 Agent 自动继续。"
                : "玩家已接管，按 F10 交还控制后 Agent 继续。";
            Write(snapshot, path);
        }
        catch { }
    }

    internal static void RecordHoldReleased(string? path = null)
    {
        try
        {
            var snapshot = ReadCurrentSnapshot(path);
            snapshot["status"] = "resuming";
            snapshot["phase"] = "resuming after the player handed control back";
            snapshot.Remove("holdReason");
            Write(snapshot, path);
        }
        catch { }
    }

    internal static JsonObject ReadCurrentSnapshot(string? path = null)
    {
        try
        {
            path ??= DefaultStatusPath();
            if (!File.Exists(path)) return new JsonObject { ["schemaVersion"] = 1 };
            return JsonNode.Parse(File.ReadAllText(path)) as JsonObject ?? new JsonObject { ["schemaVersion"] = 1 };
        }
        catch
        {
            return new JsonObject { ["schemaVersion"] = 1 };
        }
    }

    internal static JsonObject BuildSnapshot(JsonElement request, ProviderDecisionResult? result)
    {
        var observation = request.ValueKind == JsonValueKind.Object && request.TryGetProperty("observation", out var observationNode) &&
                          observationNode.ValueKind == JsonValueKind.Object ? observationNode : default;
        var state = observation.ValueKind == JsonValueKind.Object && observation.TryGetProperty("state", out var stateNode) && stateNode.ValueKind == JsonValueKind.Object
            ? stateNode
            : observation;
        var context = ReadObject(state, "context");
        var economy = ReadObject(state, "economy");
        var party = ReadObject(state, "party");
        var allowedActions = request.ValueKind == JsonValueKind.Object && request.TryGetProperty("allowedActions", out var actionsNode) &&
                             actionsNode.ValueKind == JsonValueKind.Array ? actionsNode : default;
        var allowedControls = request.ValueKind == JsonValueKind.Object && request.TryGetProperty("allowedControls", out var controlsNode) &&
                              controlsNode.ValueKind == JsonValueKind.Array ? controlsNode : default;
        var decision = result?.Decision ?? new JsonObject();
        var snapshot = new JsonObject
        {
            ["schemaVersion"] = 1,
            ["utc"] = DateTime.UtcNow.ToString("O", System.Globalization.CultureInfo.InvariantCulture),
            ["status"] = "deciding",
            ["runId"] = ReadString(request, "runId"),
            ["scope"] = ReadString(request, "scope"),
            ["objectiveId"] = ReadString(request, "objectiveId"),
            ["modelId"] = result?.ModelId,
            ["phase"] = DescribePhase(result, decision),
            ["thinking"] = DescribeThinking(decision),
            ["progress"] = new JsonObject
            {
                ["gameState"] = ReadString(context, "gameState"),
                ["menuId"] = ReadString(context, "menuId"),
                ["campaignDay"] = ReadNumber(state, "campaignDay") ?? ReadNumber(request, "observation", "campaignDay"),
                ["gold"] = ReadNumber(economy, "gold"),
                ["renown"] = ReadNumber(economy, "renown"),
                ["members"] = ReadNumber(party, "members"),
                ["wounded"] = ReadNumber(party, "wounded"),
                ["focus"] = DescribeFocus(request)
            },
            ["budget"] = new JsonObject
            {
                ["promptTokens"] = result?.PromptTokens,
                ["completionTokens"] = result?.CompletionTokens,
                ["promptCacheHitTokens"] = result?.PromptCacheHitTokens,
                ["promptCacheMissTokens"] = result?.PromptCacheMissTokens,
                ["allowedActionCount"] = allowedActions.ValueKind == JsonValueKind.Array ? allowedActions.GetArrayLength() : 0,
                ["allowedControlCount"] = allowedControls.ValueKind == JsonValueKind.Array ? allowedControls.GetArrayLength() : 0
            },
            ["debug"] = new JsonObject
            {
                ["requestBytes"] = result?.RequestBodyBytes,
                ["observationBytes"] = result?.ObservationBytes,
                ["systemPromptBytes"] = result?.SystemPromptBytes,
                ["responseFormatMode"] = result?.ResponseFormatMode,
                ["finishReason"] = result?.FinishReason,
                ["allowedActions"] = allowedActions.ValueKind == JsonValueKind.Array ? JsonNode.Parse(allowedActions.GetRawText()) : null,
                ["allowedControls"] = allowedControls.ValueKind == JsonValueKind.Array ? JsonNode.Parse(allowedControls.GetRawText()) : null,
                ["decision"] = decision.DeepClone(),
                ["observation"] = BuildCappedObservation(observation)
            }
        };
        return snapshot;
    }

    internal static string BuildAttention(string? failureCode) => failureCode switch
    {
        null or "" => "none",
        "provider-argument-unavailable" or "provider-arguments-missing" or "provider-decision-ambiguous" => "the model answered outside the current action catalog",
        "provider-http-error" or "provider-timeout" => "the provider did not answer reliably",
        var code when code.Contains("route", StringComparison.Ordinal) => "no current Native route is available",
        var code => code
    };

    private static string DescribePhase(ProviderDecisionResult? result, JsonObject decision)
    {
        if (decision.ContainsKey("control"))
        {
            var control = ReadString(decision, "control");
            return control == "stop" ? "stopping" : "handling a bounded control";
        }
        if (decision.ContainsKey("action")) return "issuing one Native action";
        return result is null ? "waiting on the provider" : "produced an unclassified decision";
    }

    private static string DescribeThinking(JsonObject decision)
    {
        var rationale = ReadString(decision, "rationale") ?? ReadString(decision, "reason");
        var action = ReadString(decision, "action");
        var control = ReadString(decision, "control");
        var intent = action is not null ? "Native action: " + action : control is not null ? "control: " + control : "no decision field";
        return string.IsNullOrWhiteSpace(rationale) ? intent : intent + " — " + rationale;
    }

    private static string? DescribeFocus(JsonElement request)
    {
        var goal = ReadString(request, "goal");
        if (string.IsNullOrWhiteSpace(goal)) return null;
        var trimmed = goal.Trim();
        return trimmed.Length <= 160 ? trimmed : trimmed.Substring(0, 160) + "…";
    }

    private static JsonNode? BuildCappedObservation(JsonElement observation)
    {
        if (observation.ValueKind != JsonValueKind.Object) return null;
        var raw = observation.GetRawText();
        if (Encoding.UTF8.GetByteCount(raw) <= MaximumDebugObservationBytes) return JsonNode.Parse(raw);
        return new JsonObject
        {
            ["truncated"] = true,
            ["bytes"] = Encoding.UTF8.GetByteCount(raw),
            ["state"] = observation.TryGetProperty("state", out var stateNode) && stateNode.ValueKind == JsonValueKind.Object
                ? JsonNode.Parse(stateNode.GetRawText())
                : null
        };
    }

    private static void Write(JsonObject snapshot, string? path = null)
    {
        var target = path ?? DefaultStatusPath();
        lock (WriteGate)
        {
            var directory = Path.GetDirectoryName(target);
            if (!string.IsNullOrWhiteSpace(directory)) Directory.CreateDirectory(directory);
            var temporary = target + ".tmp";
            File.WriteAllText(temporary, snapshot.ToJsonString());
            File.Move(temporary, target, overwrite: true);
        }
    }

    internal static IReadOnlyList<object> RunContractSelfTests()
    {
        using var request = JsonDocument.Parse("""
            {"runId":"selftest-live-status","scope":"campaign-agent-loop","objectiveId":"gold",
             "goal":"Complete the original StoryMode quest.","observation":{"state":{"campaignDay":12.5,
             "context":{"gameState":"MapState","menuId":"town"},"economy":{"gold":1200,"renown":48},"party":{"members":22,"wounded":1}}},
             "allowedActions":[{"action":"move","arguments":["SettlementId"]}],"allowedControls":["observeAgain"]}
            """);
        var decision = new JsonObject { ["action"] = "move", ["arguments"] = new JsonObject { ["SettlementId"] = "town_ES6" }, ["rationale"] = "nearest safe town" };
        var result = new ProviderDecisionResult("completed", "selftest-model", 11, 7, "stop", decision, PromptCacheHitTokens: 9, PromptCacheMissTokens: 2, RequestBodyBytes: 4096, ObservationBytes: 2048);
        var snapshot = BuildSnapshot(request.RootElement, result);
        var progress = snapshot["progress"] as JsonObject;
        if (ReadString(snapshot, "status") != "deciding" ||
            ReadString(progress, "gameState") != "MapState" ||
            ReadString(progress, "menuId") != "town" ||
            ReadNumber(progress, "gold") != 1200 ||
            ReadNumber(progress, "members") != 22 ||
            ReadNumber(progress, "campaignDay") != 12.5 ||
            ReadString(snapshot, "thinking")?.Contains("nearest safe town", StringComparison.Ordinal) != true ||
            ReadString(snapshot, "phase") != "issuing one Native action" ||
            ReadNumber(snapshot["budget"] as JsonObject, "allowedActionCount") != 1)
            throw new AgentHostException("live-status-decision-snapshot-incomplete", "The in-game status snapshot must carry the current Native state, the chosen action and its rationale, and the current catalog size.");

        var oversized = JsonNode.Parse(request.RootElement.GetRawText())!.AsObject();
        ((JsonObject)oversized["observation"]!)["padding"] = new string('x', MaximumDebugObservationBytes + 512);
        using var oversizedDocument = JsonDocument.Parse(oversized.ToJsonString());
        var capped = BuildSnapshot(oversizedDocument.RootElement, result);
        var cappedObservation = capped["debug"]?["observation"] as JsonObject;
        if (cappedObservation?["truncated"]?.GetValue<bool>() != true || cappedObservation["state"] is not JsonObject)
            throw new AgentHostException("live-status-debug-observation-not-capped", "A large observation must be truncated for the panel instead of being written whole.");

        var failure = BuildSnapshot(request.RootElement, null);
        failure["status"] = "provider-failure";
        failure["failureCode"] = "provider-argument-unavailable";
        failure["attention"] = BuildAttention("provider-argument-unavailable");
        if (ReadString(failure, "attention") != "the model answered outside the current action catalog" || ReadString(failure, "phase") != "waiting on the provider")
            throw new AgentHostException("live-status-failure-snapshot-unclear", "A provider failure must explain what the player is looking at instead of leaking a raw failure code only.");

        var holdDirectory = Path.Combine(Path.GetTempPath(), "ChronicleStatusHold-" + Guid.NewGuid().ToString("N"));
        try
        {
            Directory.CreateDirectory(holdDirectory);
            var holdPath = Path.Combine(holdDirectory, FileName);
            Write(snapshot, holdPath);
            RecordHold(AgentHostControlHold.EscapeMenuReason, holdPath);
            var held = JsonNode.Parse(File.ReadAllText(holdPath)) as JsonObject;
            if (ReadString(held, "status") != "held" ||
                ReadString(held, "holdReason") != AgentHostControlHold.EscapeMenuReason ||
                ReadNumber(held?["progress"] as JsonObject, "gold") is null ||
                ReadString(held, "thinking")?.Contains("ESC", StringComparison.Ordinal) != true)
                throw new AgentHostException("live-status-hold-snapshot-unclear", "A hold must keep the previous progress visible and explain the pause instead of blanking the run.");
            RecordHoldReleased(holdPath);
            var released = JsonNode.Parse(File.ReadAllText(holdPath)) as JsonObject;
            if (ReadString(released, "status") != "resuming" || released?.ContainsKey("holdReason") != false)
                throw new AgentHostException("live-status-hold-release-unclear", "Handing control back must clear the hold reason and show that the agent is resuming.");
        }
        finally
        {
            try { Directory.Delete(holdDirectory, recursive: true); } catch { }
        }

        var directory = Path.Combine(Path.GetTempPath(), "ChronicleLiveStatus-" + Guid.NewGuid().ToString("N"));
        try
        {
            Directory.CreateDirectory(directory);
            var path = Path.Combine(directory, FileName);
            Write(snapshot, path);
            Write(snapshot, path);
            var parsed = JsonNode.Parse(File.ReadAllText(path)) as JsonObject;
            if (parsed is null || ReadString(parsed, "runId") != "selftest-live-status" || Directory.GetFiles(directory).Length != 1)
                throw new AgentHostException("live-status-atomic-replace-failed", "Writing the status twice must leave exactly one complete snapshot file.");
        }
        finally
        {
            try { Directory.Delete(directory, recursive: true); } catch { }
        }

        return [
            new { scenario = "live-status-snapshot-is-small-atomic-and-capped", passed = true },
            new { scenario = "live-status-hands-control-back-while-keeping-progress-visible", passed = true }
        ];
    }

    private static JsonObject? ReadObject(JsonElement source, string name) =>
        source.ValueKind == JsonValueKind.Object && source.TryGetProperty(name, out var node) && node.ValueKind == JsonValueKind.Object
            ? JsonNode.Parse(node.GetRawText()) as JsonObject
            : null;

    private static string? ReadString(JsonElement source, string name) =>
        source.ValueKind == JsonValueKind.Object && source.TryGetProperty(name, out var node) && node.ValueKind == JsonValueKind.String
            ? node.GetString()
            : null;

    private static string? ReadString(JsonObject? source, string name) =>
        source?[name] is JsonValue value && value.TryGetValue<string>(out var text) ? text : null;

    private static double? ReadNumber(JsonElement source, string name) =>
        source.ValueKind == JsonValueKind.Object && source.TryGetProperty(name, out var node) && node.ValueKind == JsonValueKind.Number && node.TryGetDouble(out var number)
            ? number
            : null;

    private static double? ReadNumber(JsonElement source, string parent, string name) =>
        source.ValueKind == JsonValueKind.Object && source.TryGetProperty(parent, out var node) ? ReadNumber(node, name) : null;

    private static double? ReadNumber(JsonObject? source, string name)
    {
        if (source?[name] is not JsonValue value) return null;
        if (value.TryGetValue<double>(out var number)) return number;
        if (value.TryGetValue<int>(out var smallInteger)) return smallInteger;
        if (value.TryGetValue<long>(out var integer)) return integer;
        return null;
    }
}
