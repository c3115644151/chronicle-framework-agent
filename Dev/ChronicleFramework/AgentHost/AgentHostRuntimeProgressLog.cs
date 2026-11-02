using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace ChronicleFramework.AgentHost;

/// <summary>
/// A bounded, secret-free per-run usage and decision log for the player-owned MCM Agent.
/// Harness evidence remains isolated under TestResults; this log is only for normal MCM runs.
/// </summary>
internal static class AgentHostRuntimeProgressLog
{
    internal const string UsageSignalPrefix = "CHRONICLE_AGENT_HOST_USAGE|";
    private const long MaximumRunLogBytes = 8L * 1024 * 1024;
    private const int MaximumRetainedRunLogs = 10;
    private const string OwnedRunIdPattern = "^(mcm-[a-f0-9]{32})(?:-[A-Za-z0-9_-]{1,64})?$";
    private static readonly object WriteGate = new();
    private static readonly HashSet<string> ActiveProductRunIds = new(StringComparer.Ordinal);

    internal static void RecordRunStarted(JsonElement request)
    {
        var runId = ReadString(request, "runId");
        if (!TryGetPath(runId, out var path) || !TryGetBaseRunId(runId, out var baseRunId)) return;
        try
        {
            lock (WriteGate) ActiveProductRunIds.Add(baseRunId);
            var configuration = request.TryGetProperty("providerConfiguration", out var node) && node.ValueKind == JsonValueKind.Object
                ? node
                : default;
            var baseUrl = ReadString(configuration, "ProviderBaseUrl") ?? ReadString(configuration, "OllamaBaseUrl");
            var host = Uri.TryCreate(baseUrl, UriKind.Absolute, out var endpoint) ? endpoint.Host : "unknown";
            AppendEvent(path, new JsonObject
            {
                ["event"] = "run-start",
                ["schemaVersion"] = 1,
                ["utc"] = UtcNow(),
                ["runId"] = ReadString(request, "runId"),
                ["providerHost"] = host,
                ["modelId"] = ReadString(configuration, "ModelId"),
                ["responseFormatMode"] = ReadString(configuration, "OutputMode"),
                ["deepSeekRunCostLimitCny"] = ReadString(configuration, "DeepSeekRunCostLimitCny"),
                ["promptsLogged"] = false,
                ["responseBodiesLogged"] = false,
                ["credentialsLogged"] = false
            });
            PrunePlayerRunLogs(Path.GetDirectoryName(path)!, path);
        }
        catch { }
    }

    internal static void RecordDecision(JsonElement request, ProviderDecisionResult result, double? configuredRunCostLimitCny)
    {
        var runId = ReadString(request, "runId");
        if (!IsActiveProductRun(runId) || !TryGetPath(runId, out var path)) return;
        try
        {
            AppendEvent(path, BuildDecisionEvent(request, result, configuredRunCostLimitCny));
        }
        catch { }
        if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE")))
            WriteUsageSignal(result, configuredRunCostLimitCny);
    }

    internal static JsonObject BuildDecisionEvent(JsonElement request, ProviderDecisionResult result, double? configuredRunCostLimitCny)
    {
        var runId = ReadString(request, "runId");
        var requestNode = JsonNode.Parse(request.GetRawText()) as JsonObject;
        var observation = requestNode?["observation"] as JsonObject;
        var state = observation?["state"] as JsonObject ?? observation;
        var context = state?["context"] as JsonObject;
        var location = state?["location"] as JsonObject;
        var party = state?["party"] as JsonObject;
        var economy = state?["economy"] as JsonObject;
        var conversation = context?["conversation"] as JsonObject;
        var actionArguments = result.Decision["arguments"] as JsonObject;
        var decisionAction = ReadString(result.Decision, "action");
        var decisionControl = ReadString(result.Decision, "control");
        if (string.IsNullOrWhiteSpace(decisionControl) && ReadBoolean(result.Decision, "observeAgain")) decisionControl = "observeAgain";
        if (string.IsNullOrWhiteSpace(decisionControl) && ReadBoolean(result.Decision, "stop")) decisionControl = "stop";
        var argumentNames = new JsonArray((actionArguments?.Select(pair => (JsonNode?)JsonValue.Create(pair.Key)) ?? Enumerable.Empty<JsonNode?>()).ToArray());
        var allowedActions = new JsonArray((requestNode?["allowedActions"] as JsonArray)?.OfType<JsonObject>()
            .Select(item => ReadString(item, "action"))
            .Where(name => !string.IsNullOrWhiteSpace(name))
            .Select(name => (JsonNode?)JsonValue.Create(name))
            .ToArray() ?? Array.Empty<JsonNode?>());
        var allowedControls = requestNode?["allowedControls"]?.DeepClone() as JsonArray ?? new JsonArray();
        var clickableOptionIds = new JsonArray((conversation?["options"] as JsonArray)?.OfType<JsonObject>()
            .Where(option => ReadBoolean(option, "clickable"))
            .Select(option => ReadString(option, "id"))
            .Where(id => !string.IsNullOrWhiteSpace(id))
            .Select(id => (JsonNode?)JsonValue.Create(id))
            .ToArray() ?? Array.Empty<JsonNode?>());

        return new JsonObject
        {
            ["event"] = "provider-decision",
            ["schemaVersion"] = 1,
            ["utc"] = UtcNow(),
            ["runId"] = runId,
            ["modelId"] = result.ModelId,
            ["routedVia"] = result.RoutedVia,
            ["responseFormatMode"] = result.ResponseFormatMode,
            ["promptTokens"] = result.PromptTokens,
            ["completionTokens"] = result.CompletionTokens,
            ["promptCacheHitTokens"] = result.PromptCacheHitTokens,
            ["promptCacheMissTokens"] = result.PromptCacheMissTokens,
            ["estimatedCostCny"] = result.EstimatedCostCny,
            ["reservedCostUpperBoundCny"] = result.ReservedCostUpperBoundCny,
            ["configuredRunCostLimitCny"] = configuredRunCostLimitCny,
            ["requestBodyBytes"] = result.RequestBodyBytes,
            ["systemPromptBytes"] = result.SystemPromptBytes,
            ["userPayloadBytes"] = result.UserPayloadBytes,
            ["observationBytes"] = result.ObservationBytes,
            ["decisionAction"] = decisionAction,
            ["goalClassification"] = ReadString(result.Decision, "goalClassification"),
            ["decisionControl"] = decisionControl,
            ["argumentNames"] = argumentNames,
            ["allowedActions"] = allowedActions,
            ["allowedControls"] = allowedControls,
            ["clickableOptionIds"] = clickableOptionIds,
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
            ["partyCapacity"] = Copy(party, "sizeLimit"),
            ["objectiveSnapshot"] = state?["objectiveSnapshot"]?.DeepClone(),
            ["promptsLogged"] = false,
            ["responseBodiesLogged"] = false,
            ["rationaleLogged"] = false,
            ["credentialsLogged"] = false
        };
    }

    internal static void RecordProviderFailure(JsonElement request, string failureCode)
    {
        var runId = ReadString(request, "runId");
        if (!IsActiveProductRun(runId) || !TryGetPath(runId, out var path)) return;
        try
        {
            AppendEvent(path, new JsonObject
            {
                ["event"] = "provider-failure",
                ["schemaVersion"] = 1,
                ["utc"] = UtcNow(),
                ["runId"] = ReadString(request, "runId"),
                ["failureCode"] = SanitizeCode(failureCode),
                ["nativeActionSent"] = false,
                ["responseBodiesLogged"] = false,
                ["credentialsLogged"] = false
            });
        }
        catch { }
    }

    internal static void RecordObjectiveSubflowResult(string objectiveId, JsonObject result)
    {
        var runId = ReadString(result, "runId");
        if (!IsActiveProductRun(runId) || !TryGetPath(runId, out var path)) return;
        try
        {
            AppendEvent(path, new JsonObject
            {
                ["event"] = "objective-subflow-result",
                ["schemaVersion"] = 1,
                ["utc"] = UtcNow(),
                ["runId"] = ReadString(result, "runId"),
                ["objectiveId"] = objectiveId,
                ["status"] = Copy(result, "status"),
                ["termination"] = Copy(result["termination"] as JsonObject, "reason") ?? Copy(result, "termination"),
                ["failureCode"] = Copy(result, "failureCode"),
                ["decisions"] = Copy(result, "decisions"),
                ["actionsExecuted"] = Copy(result, "actionsExecuted"),
                ["promptTokens"] = Copy(result, "promptTokens"),
                ["completionTokens"] = Copy(result, "completionTokens"),
                ["nativeStateBefore"] = AgentHostHarnessProgressTrace.BuildNativeStateSummary(result["initialNativeState"] as JsonObject),
                ["nativeStateAfter"] = AgentHostHarnessProgressTrace.BuildNativeStateSummary(result["finalNativeState"] as JsonObject ?? result["finalState"] as JsonObject),
                ["failureTextLogged"] = false
            });
        }
        catch { }
    }

    internal static void RecordRunSummary(JsonElement request, JsonObject result)
    {
        var runId = ReadString(request, "runId");
        if (!IsActiveProductRun(runId) || !TryGetPath(runId, out var path)) return;
        try
        {
            AppendEvent(path, new JsonObject
            {
                ["event"] = "run-summary",
                ["schemaVersion"] = 1,
                ["utc"] = UtcNow(),
                ["runId"] = runId,
                ["modelId"] = Copy(result, "providerModelId"),
                ["status"] = Copy(result, "status"),
                ["termination"] = Copy(result["termination"] as JsonObject, "reason"),
                ["failureCode"] = Copy(result, "failureCode"),
                ["decisions"] = Copy(result, "decisions"),
                ["actionsExecuted"] = Copy(result, "actionsExecuted"),
                ["promptTokens"] = Copy(result, "promptTokens"),
                ["completionTokens"] = Copy(result, "completionTokens"),
                ["promptCacheHitTokens"] = Copy(result, "providerPromptCacheHitTokens"),
                ["promptCacheMissTokens"] = Copy(result, "providerPromptCacheMissTokens"),
                ["estimatedCostCny"] = Copy(result, "providerActualCostEstimateCny"),
                ["reservedCostUpperBoundCny"] = Copy(result, "providerReservedCostUpperCny"),
                ["goalVerified"] = Copy(result["termination"] as JsonObject, "goalVerified"),
                ["failureTextLogged"] = false,
                ["credentialsLogged"] = false
            });
        }
        catch { }
        finally
        {
            if (TryGetBaseRunId(runId, out var baseRunId))
                lock (WriteGate) ActiveProductRunIds.Remove(baseRunId);
        }
    }

    internal static string? ResolvePlayerRunLogPath(string documentsDirectory, string runId)
    {
        if (string.IsNullOrWhiteSpace(documentsDirectory) || !TryGetBaseRunId(runId, out var baseRunId))
            return null;
        var root = Path.GetFullPath(Path.Combine(documentsDirectory, "Mount and Blade II Bannerlord", "Configs", "ModLogs", "AgentRuns"));
        var rootPrefix = root.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
        var path = Path.GetFullPath(Path.Combine(root, baseRunId + ".jsonl"));
        return path.StartsWith(rootPrefix, StringComparison.OrdinalIgnoreCase) ? path : null;
    }

    internal static void PrunePlayerRunLogs(string logRoot, string currentPath, int retainCount = MaximumRetainedRunLogs)
    {
        if (retainCount < 1) throw new ArgumentOutOfRangeException(nameof(retainCount));
        Directory.CreateDirectory(logRoot);
        var rootPrefix = Path.GetFullPath(logRoot).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
        var current = Path.GetFullPath(currentPath);
        if (!current.StartsWith(rootPrefix, StringComparison.OrdinalIgnoreCase)) return;
        var owned = Directory.EnumerateFiles(logRoot, "mcm-*.jsonl", SearchOption.TopDirectoryOnly)
            .Where(file => Regex.IsMatch(Path.GetFileName(file), "^mcm-[a-f0-9]{32}\\.jsonl$", RegexOptions.CultureInvariant))
            .OrderByDescending(File.GetLastWriteTimeUtc)
            .ToArray();
        var retained = new HashSet<string>(owned.Where(file => string.Equals(Path.GetFullPath(file), current, StringComparison.OrdinalIgnoreCase))
            .Concat(owned.Where(file => !string.Equals(Path.GetFullPath(file), current, StringComparison.OrdinalIgnoreCase))
                .Take(Math.Max(0, retainCount - 1)).Select(Path.GetFullPath)), StringComparer.OrdinalIgnoreCase);
        foreach (var stale in owned.Where(file => !retained.Contains(Path.GetFullPath(file))))
        {
            if (!Path.GetFullPath(stale).StartsWith(rootPrefix, StringComparison.OrdinalIgnoreCase)) continue;
            File.Delete(stale);
        }
    }

    internal static IReadOnlyList<object> RunContractSelfTests()
    {
        var documents = Path.Combine(Path.GetTempPath(), "ChronicleRuntimeLogContract");
        var validRun = "mcm-0123456789abcdef0123456789abcdef";
        var path = ResolvePlayerRunLogPath(documents, validRun);
        var escaped = ResolvePlayerRunLogPath(documents, "mcm-..\\..\\outside");
        var expectedRoot = Path.GetFullPath(Path.Combine(documents, "Mount and Blade II Bannerlord", "Configs", "ModLogs", "AgentRuns")) + Path.DirectorySeparatorChar;
        if (path is null || !path.StartsWith(expectedRoot, StringComparison.OrdinalIgnoreCase) || escaped is not null)
            throw new AgentHostException("runtime-progress-log-path-self-test-failed", "Player progress logs must stay in the owned ModLogs\\AgentRuns folder and reject untrusted run IDs.");

        using var request = JsonDocument.Parse("""
            {"runId":"mcm-0123456789abcdef0123456789abcdef","goal":"PRIVATE_GOAL_TEXT","observation":{"state":{"campaignDay":42.5,"context":{"gameState":"MapState","menuId":"village","timeControlMode":"Stop"},"location":{"currentSettlementId":"village-1"},"economy":{"gold":100,"renown":20},"party":{"members":5,"sizeLimit":20},"objectiveSnapshot":{"gold":{"current":100,"target":2000,"met":false}}}},"allowedActions":[{"action":"dialogueSelect","arguments":["OptionId"]}],"allowedControls":[]}
            """);
        var decision = new JsonObject
        {
            ["action"] = "dialogueSelect",
            ["goalClassification"] = "supported-map-arrival",
            ["arguments"] = new JsonObject { ["OptionId"] = "issue_offer_player_accept_quest", ["PrivateValue"] = "PRIVATE_ACTION_VALUE" },
            ["rationale"] = "PRIVATE_RATIONALE"
        };
        var loggedDecision = BuildDecisionEvent(request.RootElement,
            new ProviderDecisionResult("completed", "deepseek-flash", 321, 40, "required_tool_call", decision, "deepseek-flash",
                PromptCacheHitTokens: 12, PromptCacheMissTokens: 34, EstimatedCostCny: 0.01, ReservedCostUpperBoundCny: 0.04),
            configuredRunCostLimitCny: 5);
        var loggedJson = loggedDecision.ToJsonString();
        if (ReadInt(loggedDecision, "promptTokens") != 321 || ReadInt(loggedDecision, "completionTokens") != 40 ||
            ReadInt(loggedDecision, "promptCacheHitTokens") != 12 || ReadInt(loggedDecision, "promptCacheMissTokens") != 34 ||
            Math.Abs((ReadDouble(loggedDecision, "estimatedCostCny") ?? -1) - 0.01) > 0.0000001 ||
            Math.Abs((ReadDouble(loggedDecision, "configuredRunCostLimitCny") ?? -1) - 5) > 0.0000001 ||
            loggedJson.Contains("PRIVATE_", StringComparison.Ordinal) || loggedJson.Contains("issue_offer_player_accept_quest", StringComparison.Ordinal) ||
            (loggedDecision["argumentNames"] as JsonArray)?.Count != 2)
            throw new AgentHostException("runtime-progress-log-privacy-or-usage-self-test-failed", "The player runtime log must retain token/cache/cost metadata and safe argument names while omitting goals, argument values, response text and rationales.");

        var tempRoot = Path.Combine(Path.GetTempPath(), "ChronicleRuntimeLogRetention-" + Guid.NewGuid().ToString("N"));
        try
        {
            Directory.CreateDirectory(tempRoot);
            var oldHarnessMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
            var oldHarnessTemp = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
            try
            {
                Environment.SetEnvironmentVariable("CHRONICLE_HARNESS_MODE", "agent-host-package");
                Environment.SetEnvironmentVariable("CHRONICLE_HARNESS_TEMP", tempRoot);
                RecordDecision(request.RootElement, new ProviderDecisionResult("completed", "deepseek-flash", 321, 40,
                    "required_tool_call", decision, "deepseek-flash", PromptCacheHitTokens: 12, PromptCacheMissTokens: 34,
                    EstimatedCostCny: 0.01, ReservedCostUpperBoundCny: 0.04), configuredRunCostLimitCny: 5);
                var unstartedLogPath = Path.Combine(tempRoot, "AgentHostRuntimeProgressLog", validRun + ".jsonl");
                if (File.Exists(unstartedLogPath))
                    throw new AgentHostException("runtime-progress-log-unowned-decision-recorded", "A provider one-shot with an MCM-shaped ID must not create a player run log unless the Campaign run was registered first.");
                RecordRunStarted(request.RootElement);
                RecordDecision(request.RootElement, new ProviderDecisionResult("completed", "deepseek-flash", 321, 40,
                    "required_tool_call", decision, "deepseek-flash", PromptCacheHitTokens: 12, PromptCacheMissTokens: 34,
                    EstimatedCostCny: 0.01, ReservedCostUpperBoundCny: 0.04), configuredRunCostLimitCny: 5);
                var childRequest = JsonNode.Parse(request.RootElement.GetRawText()) as JsonObject
                    ?? throw new AgentHostException("runtime-progress-child-request-self-test-failed", "The child subflow request fixture must be an object.");
                childRequest["runId"] = validRun + "-battle-inquiry-1";
                using var childRequestDocument = JsonDocument.Parse(childRequest.ToJsonString());
                RecordDecision(childRequestDocument.RootElement, new ProviderDecisionResult("completed", "deepseek-flash", 99, 12,
                    "required_tool_call", decision, "deepseek-flash", PromptCacheHitTokens: 0, PromptCacheMissTokens: 99,
                    EstimatedCostCny: 0.002, ReservedCostUpperBoundCny: 0.005), configuredRunCostLimitCny: 5);
                RecordObjectiveSubflowResult("gold", new JsonObject { ["runId"] = validRun, ["status"] = "failed", ["termination"] = "self-test" });
                RecordRunSummary(request.RootElement, new JsonObject
                {
                    ["providerModelId"] = "deepseek-flash", ["status"] = "completed", ["decisions"] = 1,
                    ["promptTokens"] = 321, ["completionTokens"] = 40, ["providerActualCostEstimateCny"] = 0.01,
                    ["providerReservedCostUpperCny"] = 0.04, ["termination"] = new JsonObject { ["reason"] = "self-test", ["goalVerified"] = false }
                });
            }
            finally
            {
                Environment.SetEnvironmentVariable("CHRONICLE_HARNESS_MODE", oldHarnessMode);
                Environment.SetEnvironmentVariable("CHRONICLE_HARNESS_TEMP", oldHarnessTemp);
            }
            var productLog = Path.Combine(tempRoot, "AgentHostRuntimeProgressLog", validRun + ".jsonl");
            var productLogLines = File.ReadAllLines(productLog);
            var childDecision = productLogLines.Length > 2 ? JsonNode.Parse(productLogLines[2]) as JsonObject : null;
            if (productLogLines.Length != 5 || productLogLines.Any(line => line.Contains("PRIVATE_", StringComparison.Ordinal) ||
                    line.Contains("PRIVATE_OPTION_VALUE", StringComparison.Ordinal)) ||
                ReadString(JsonNode.Parse(productLogLines[1]) as JsonObject, "event") != "provider-decision" ||
                ReadString(childDecision, "event") != "provider-decision" ||
                ReadString(childDecision, "runId") != validRun + "-battle-inquiry-1" ||
                ReadString(childDecision, "goalClassification") != "supported-map-arrival" ||
                ReadString(JsonNode.Parse(productLogLines[3]) as JsonObject, "objectiveId") != "gold" ||
                ReadString(JsonNode.Parse(productLogLines[4]) as JsonObject, "event") != "run-summary")
            {
                var loggedEvents = string.Join(",", productLogLines.Select(line => ReadString(JsonNode.Parse(line) as JsonObject, "event") ?? "unknown"));
                var privateMarkerFound = productLogLines.Any(line => line.Contains("PRIVATE_", StringComparison.Ordinal));
                throw new AgentHostException("runtime-progress-log-end-to-end-self-test-failed", $"A MCM run must persist per-decision cost data and a final summary while omitting secret markers and free-text payloads. lines={productLogLines.Length}; events={loggedEvents}; privateMarker={privateMarkerFound}.");
            }

            var currentPath = Path.Combine(tempRoot, validRun + ".jsonl");
            File.WriteAllText(currentPath, "current");
            for (var index = 0; index < 4; index++)
                File.WriteAllText(Path.Combine(tempRoot, "mcm-" + index.ToString("x32", CultureInfo.InvariantCulture) + ".jsonl"), "owned log");
            PrunePlayerRunLogs(tempRoot, currentPath, retainCount: 2);
            if (Directory.GetFiles(tempRoot, "mcm-*.jsonl").Length != 2 || !File.Exists(currentPath))
                throw new AgentHostException("runtime-progress-log-retention-self-test-failed", "Runtime log rotation must retain the current run and enforce its bounded file count.");
            File.WriteAllText(Path.Combine(tempRoot, "keep-me.txt"), "unowned");
            PrunePlayerRunLogs(tempRoot, currentPath, retainCount: 2);
            if (!File.Exists(Path.Combine(tempRoot, "keep-me.txt")))
                throw new AgentHostException("runtime-progress-log-retention-deleted-unowned-file", "Runtime log rotation must never delete non-owned files in its log directory.");
        }
        finally
        {
            try { if (Directory.Exists(tempRoot)) Directory.Delete(tempRoot, recursive: true); } catch { }
        }

        var previousConsoleOut = Console.Out;
        string usageSignal;
        try
        {
            using var signalWriter = new StringWriter(CultureInfo.InvariantCulture);
            Console.SetOut(signalWriter);
            WriteUsageSignal(new ProviderDecisionResult("completed", "deepseek-flash", 321, 40, "required_tool_call",
                new JsonObject { ["goalClassification"] = "supported-map-arrival" },
                PromptCacheHitTokens: 12, PromptCacheMissTokens: 34, EstimatedCostCny: 0.01, ReservedCostUpperBoundCny: 0.04), 5);
            usageSignal = signalWriter.ToString();
        }
        finally { Console.SetOut(previousConsoleOut); }
        if (!usageSignal.StartsWith(UsageSignalPrefix, StringComparison.Ordinal) ||
            !usageSignal.Contains("promptTokens=321", StringComparison.Ordinal) ||
            !usageSignal.Contains("cacheHitTokens=12", StringComparison.Ordinal) ||
            !usageSignal.Contains("estimatedCostCny=0.01", StringComparison.Ordinal) ||
            !usageSignal.Contains("reservedCostUpperBoundCny=0.04", StringComparison.Ordinal) ||
            !usageSignal.Contains("runCostLimitCny=5", StringComparison.Ordinal))
            throw new AgentHostException("runtime-progress-usage-signal-self-test-failed", "The game-process usage signal must carry token, cache, estimate, reservation and cap fields in the documented machine-readable format.");

        return new object[]
        {
            new { scenario = "runtime-progress-log-preserves-cost-usage-without-prompts-responses-or-argument-values-including-numbered-subflows", passed = true },
            new { scenario = "runtime-progress-log-path-is-run-scoped-and-rejects-path-traversal", passed = true },
            new { scenario = "runtime-progress-log-retention-is-bounded-and-only-removes-owned-jsonl", passed = true },
            new { scenario = "runtime-progress-usage-signal-is-machine-readable-for-live-status", passed = true }
        };
    }

    private static bool TryGetPath(string? runId, out string path)
    {
        path = string.Empty;
        var harnessMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        if (string.Equals(harnessMode, "agent-host-package", StringComparison.Ordinal))
        {
            var harnessTemp = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
            if (string.IsNullOrWhiteSpace(harnessTemp) || !TryGetBaseRunId(runId, out var baseRunId)) return false;
            var testRoot = Path.GetFullPath(Path.Combine(harnessTemp, "AgentHostRuntimeProgressLog"));
            var rootPrefix = testRoot.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
            var testPath = Path.GetFullPath(Path.Combine(testRoot, baseRunId + ".jsonl"));
            if (!testPath.StartsWith(rootPrefix, StringComparison.OrdinalIgnoreCase)) return false;
            path = testPath;
            return true;
        }
        if (!string.IsNullOrWhiteSpace(harnessMode)) return false;
        var documents = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
        var resolved = ResolvePlayerRunLogPath(documents, runId ?? string.Empty);
        if (resolved is null) return false;
        path = resolved;
        return true;
    }

    private static bool IsActiveProductRun(string? runId)
    {
        if (!TryGetBaseRunId(runId, out var baseRunId)) return false;
        lock (WriteGate) return ActiveProductRunIds.Contains(baseRunId);
    }

    private static bool TryGetBaseRunId(string? runId, out string baseRunId)
    {
        baseRunId = string.Empty;
        if (string.IsNullOrWhiteSpace(runId)) return false;
        var match = Regex.Match(runId, OwnedRunIdPattern, RegexOptions.CultureInvariant);
        if (!match.Success) return false;
        baseRunId = match.Groups[1].Value;
        return true;
    }

    private static void AppendEvent(string path, JsonObject payload)
    {
        var bytes = Encoding.UTF8.GetBytes(payload.ToJsonString() + Environment.NewLine);
        var directory = Path.GetDirectoryName(path);
        if (string.IsNullOrWhiteSpace(directory)) return;
        Directory.CreateDirectory(directory);
        lock (WriteGate)
        {
            using var stream = new FileStream(path, FileMode.Append, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete);
            if (stream.Length + bytes.Length > MaximumRunLogBytes) return;
            stream.Write(bytes);
            stream.Flush();
        }
    }

    private static void WriteUsageSignal(ProviderDecisionResult result, double? configuredRunCostLimitCny)
    {
        try
        {
            var estimated = result.EstimatedCostCny?.ToString("R", CultureInfo.InvariantCulture) ?? "unknown";
            var reserved = result.ReservedCostUpperBoundCny?.ToString("R", CultureInfo.InvariantCulture) ?? "unknown";
            var limit = configuredRunCostLimitCny?.ToString("R", CultureInfo.InvariantCulture) ?? "unknown";
            Console.Out.WriteLine(UsageSignalPrefix + string.Join("|", new[]
            {
                "promptTokens=" + (result.PromptTokens ?? 0).ToString(CultureInfo.InvariantCulture),
                "completionTokens=" + (result.CompletionTokens ?? 0).ToString(CultureInfo.InvariantCulture),
                "cacheHitTokens=" + (result.PromptCacheHitTokens ?? 0).ToString(CultureInfo.InvariantCulture),
                "cacheMissTokens=" + (result.PromptCacheMissTokens ?? 0).ToString(CultureInfo.InvariantCulture),
                "estimatedCostCny=" + estimated,
                "reservedCostUpperBoundCny=" + reserved,
                "runCostLimitCny=" + limit
            }));
        }
        catch { }
    }

    private static string UtcNow() => DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
    private static JsonNode? Copy(JsonObject? source, string name) => source?[name]?.DeepClone();
    private static string? ReadString(JsonElement parent, string name) =>
        parent.ValueKind == JsonValueKind.Object && parent.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString() : null;
    private static int? ReadInt(JsonObject? parent, string name) =>
        parent?[name] is JsonValue node && node.TryGetValue<int>(out var value) ? value : null;
    private static double? ReadDouble(JsonObject? parent, string name) =>
        parent?[name] is JsonValue node && node.TryGetValue<double>(out var value) ? value : null;
    private static string? ReadString(JsonObject? parent, string name) =>
        parent?[name] is JsonValue node && node.TryGetValue<string>(out var value) ? value : null;
    private static bool ReadBoolean(JsonObject? parent, string name) =>
        parent?[name] is JsonValue node && node.TryGetValue<bool>(out var value) && value;
    private static string SanitizeCode(string code) => Regex.Replace(code ?? string.Empty, "[^A-Za-z0-9._-]", "_")[..Math.Min(80, (code ?? string.Empty).Length)];
}
