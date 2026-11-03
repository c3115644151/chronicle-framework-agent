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

    internal static void RecordBudgetReservationRejected(JsonElement request, string modelId, int estimatedInputTokens, int reservedInputTokens,
        int outputTokenCeiling, double reservedBeforeCny, double nextRequestUpperBoundCny, double runLimitCny)
    {
        var runId = ReadString(request, "runId");
        if (!IsActiveProductRun(runId) || !TryGetPath(runId, out var path)) return;
        try
        {
            var observation = request.ValueKind == JsonValueKind.Object && request.TryGetProperty("observation", out var observationValue) && observationValue.ValueKind == JsonValueKind.Object
                ? observationValue : default;
            AppendEvent(path, new JsonObject
            {
                ["event"] = "provider-budget-reservation-rejected",
                ["schemaVersion"] = 1,
                ["utc"] = UtcNow(),
                ["runId"] = runId,
                ["modelId"] = modelId,
                ["objectiveId"] = ReadString(request, "objectiveId") ?? ReadString(observation, "objectiveId"),
                ["scope"] = ReadString(request, "scopeRestriction") ?? ReadString(observation, "scope"),
                ["estimatedInputTokens"] = estimatedInputTokens,
                ["reservedInputTokens"] = reservedInputTokens,
                ["outputTokenCeiling"] = outputTokenCeiling,
                ["reservedBeforeCny"] = Math.Round(reservedBeforeCny, 8),
                ["nextRequestUpperBoundCny"] = Math.Round(nextRequestUpperBoundCny, 8),
                ["runLimitCny"] = Math.Round(runLimitCny, 8),
                ["projectedReservedAfterCny"] = Math.Round(reservedBeforeCny + nextRequestUpperBoundCny, 8),
                ["nativeActionSent"] = false,
                ["promptsLogged"] = false,
                ["credentialsLogged"] = false
            });
        }
        catch { }
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
        var inquiry = context?["inquiry"] as JsonObject;
        var partyScreen = state?["partyScreen"] as JsonObject;
        var objectiveId = ReadString(request, "objectiveId") ?? ReadString(observation, "objectiveId") ?? ReadString(state, "objectiveId");
        var scope = ReadString(request, "scopeRestriction") ?? ReadString(observation, "scope") ?? ReadString(state, "scope");
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
            ["proxySelectionSource"] = result.ProxySelectionSource,
            ["proxyEndpointHostPort"] = result.ProxyEndpointHostPort,
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
            ["objectiveId"] = objectiveId,
            ["scope"] = scope,
            ["argumentNames"] = argumentNames,
            ["allowedActions"] = allowedActions,
            ["allowedControls"] = allowedControls,
            ["clickableOptionIds"] = clickableOptionIds,
            ["campaignDay"] = Copy(state, "campaignDay"),
            ["gameState"] = Copy(context, "gameState"),
            ["menuId"] = Copy(context, "menuId"),
            ["timeControlMode"] = Copy(context, "timeControlMode"),
            ["isWaiting"] = Copy(context, "isWaiting"),
            ["inquiryOpen"] = Copy(context, "inquiryOpen"),
            ["inquiryKind"] = Copy(inquiry, "kind"),
            ["inquiryTitle"] = Truncate(ReadString(inquiry, "title"), 120),
            ["inquiryAffirmativeText"] = Truncate(ReadString(inquiry?["affirmative"] as JsonObject, "text"), 80),
            ["inquiryNegativeText"] = Truncate(ReadString(inquiry?["negative"] as JsonObject, "text"), 80),
            ["nativePartyScreen"] = AgentHostHarnessProgressTrace.BuildPartyScreenSummary(partyScreen),
            ["encounterActive"] = Copy(context, "encounterActive"),
            ["encounteredPartyId"] = Copy(context, "encounteredPartyId"),
            ["battleSimulationActive"] = context?["battleSimulation"] is JsonObject,
            ["currentSettlementId"] = Copy(location, "currentSettlementId"),
            ["targetSettlementId"] = Copy(location, "targetSettlementId"),
            ["targetPartyId"] = Copy(location, "targetPartyId"),
            ["gold"] = Copy(economy, "gold"),
            ["renown"] = Copy(economy, "renown"),
            ["partyMembers"] = Copy(party, "members"),
            ["partyCapacity"] = Copy(party, "sizeLimit"),
            ["partyHealthy"] = Copy(party, "healthy"),
            ["partyWounded"] = Copy(party, "wounded"),
            ["partyPrisoners"] = Copy(party, "prisoners"),
            ["partyMorale"] = Copy(party, "morale"),
            ["partyFood"] = Copy(party, "food"),
            ["partyFoodChange"] = Copy(party, "foodChange"),
            ["partyIsMoving"] = Copy(party, "isMoving"),
            ["partyMoveMode"] = Copy(party, "moveMode"),
            ["partyDefaultBehavior"] = Copy(party, "defaultBehavior"),
            ["objectiveSnapshot"] = state?["objectiveSnapshot"]?.DeepClone(),
            ["promptsLogged"] = false,
            ["responseBodiesLogged"] = false,
            ["rationaleLogged"] = false,
            ["credentialsLogged"] = false
        };
    }

    internal static void RecordProviderFailure(JsonElement request, string failureCode, int? providerHttpStatus = null,
        string? providerRoute = null, string? providerOutputFormat = null, int? providerRetryAttempts = null, long? providerRetryWaitMilliseconds = null,
        string? providerFailureStage = null, string? providerProxySelectionSource = null, int? providerTimeoutSeconds = null,
        int? providerRequestBodyBytes = null, string? providerTransportErrorType = null, string? providerProxyEndpointHostPort = null,
        string? providerResponseServer = null, string? providerResponseVia = null, string? providerResponseRequestId = null,
        string? providerRetryAfter = null, string? providerErrorBodyKind = null, string? providerErrorContentType = null,
        string? providerErrorType = null, string? providerErrorCode = null)
    {
        var runId = ReadString(request, "runId");
        if (!IsActiveProductRun(runId) || !TryGetPath(runId, out var path)) return;
        try
        {
            var observation = request.ValueKind == JsonValueKind.Object && request.TryGetProperty("observation", out var observationValue) && observationValue.ValueKind == JsonValueKind.Object
                ? observationValue : default;
            AppendEvent(path, new JsonObject
            {
                ["event"] = "provider-failure",
                ["schemaVersion"] = 1,
                ["utc"] = UtcNow(),
                ["runId"] = ReadString(request, "runId"),
                ["failureCode"] = SanitizeCode(failureCode),
                ["objectiveId"] = ReadString(request, "objectiveId") ?? ReadString(observation, "objectiveId"),
                ["scope"] = ReadString(request, "scopeRestriction") ?? ReadString(observation, "scope"),
                ["providerHttpStatus"] = providerHttpStatus,
                ["providerRoute"] = providerRoute,
                ["providerOutputFormat"] = providerOutputFormat,
                ["providerRetryAttempts"] = providerRetryAttempts,
                ["providerRetryWaitMilliseconds"] = providerRetryWaitMilliseconds,
                ["providerFailureStage"] = providerFailureStage,
                ["providerProxySelectionSource"] = providerProxySelectionSource,
                ["providerProxyEndpointHostPort"] = providerProxyEndpointHostPort,
                ["providerTimeoutSeconds"] = providerTimeoutSeconds,
                ["providerRequestBodyBytes"] = providerRequestBodyBytes,
                ["providerTransportErrorType"] = providerTransportErrorType,
                ["providerResponseServer"] = providerResponseServer,
                ["providerResponseVia"] = providerResponseVia,
                ["providerResponseRequestId"] = providerResponseRequestId,
                ["providerRetryAfter"] = providerRetryAfter,
                ["providerErrorBodyKind"] = providerErrorBodyKind,
                ["providerErrorContentType"] = providerErrorContentType,
                ["providerErrorType"] = providerErrorType,
                ["providerErrorCode"] = providerErrorCode,
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
            var loggedUsage = BuildLoggedUsageSummary(path, runId, result);
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
                ["loggedProviderUsage"] = loggedUsage,
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

    private static JsonObject BuildLoggedUsageSummary(string path, string? runId, JsonObject result)
    {
        var hasBaseRunId = TryGetBaseRunId(runId, out var baseRunId);
        var rows = new List<JsonObject>();
        var providerFailureEventsWithoutUsage = 0;
        var budgetReservationRejections = 0;
        try
        {
            foreach (var line in File.ReadLines(path))
            {
                JsonObject? item;
                try { item = JsonNode.Parse(line) as JsonObject; }
                catch { continue; }
                if (item is null) continue;
                var itemRunId = ReadString(item, "runId");
                if (hasBaseRunId && (!TryGetBaseRunId(itemRunId, out var itemBaseRunId) || itemBaseRunId != baseRunId)) continue;
                switch (ReadString(item, "event"))
                {
                    case "provider-decision": rows.Add(item); break;
                    case "provider-failure": providerFailureEventsWithoutUsage++; break;
                    case "provider-budget-reservation-rejected": budgetReservationRejections++; break;
                }
            }
        }
        catch { }

        long? Sum(string field) => rows.Count > 0 && rows.All(row => ReadLong(row, field).HasValue)
            ? rows.Sum(row => ReadLong(row, field)!.Value)
            : null;
        double? SumDouble(string field) => rows.Count > 0 && rows.All(row => ReadDouble(row, field).HasValue)
            ? Math.Round(rows.Sum(row => ReadDouble(row, field)!.Value), 8)
            : null;
        var reportedDecisions = ReadInt(result, "decisions");
        var terminalPromptTokens = ReadLong(result, "promptTokens");
        var terminalCompletionTokens = ReadLong(result, "completionTokens");
        var terminalEstimatedCost = ReadDouble(result, "providerActualCostEstimateCny");
        var loggedPromptTokens = Sum("promptTokens");
        var loggedCompletionTokens = Sum("completionTokens");
        var loggedEstimatedCost = SumDouble("estimatedCostCny");
        var cacheHitTokens = Sum("promptCacheHitTokens");
        var cacheMissTokens = Sum("promptCacheMissTokens");
        var cacheTotal = cacheHitTokens.HasValue && cacheMissTokens.HasValue ? cacheHitTokens.Value + cacheMissTokens.Value : 0;
        var missingUsageRows = rows.Count(row => !ReadLong(row, "promptTokens").HasValue ||
            !ReadLong(row, "completionTokens").HasValue || !ReadDouble(row, "estimatedCostCny").HasValue);
        return new JsonObject
        {
            ["accountingSource"] = "provider-decision-log-rows",
            ["providerResponseRows"] = rows.Count,
            ["rowsMissingTokenOrCostUsage"] = missingUsageRows,
            ["providerUsageRowsComplete"] = rows.Count > 0 && missingUsageRows == 0,
            ["costEstimateScope"] = "successfully parsed provider responses only; provider failures may have unreported usage",
            ["providerFailureEventsWithoutUsage"] = providerFailureEventsWithoutUsage,
            ["budgetReservationRejectionEvents"] = budgetReservationRejections,
            ["reportedLoopDecisionCount"] = reportedDecisions,
            ["reportedLoopDecisionCountMinusProviderRows"] = reportedDecisions.HasValue ? reportedDecisions.Value - rows.Count : null,
            ["promptTokensFromRows"] = loggedPromptTokens,
            ["completionTokensFromRows"] = loggedCompletionTokens,
            ["promptCacheHitTokensFromRows"] = cacheHitTokens,
            ["promptCacheMissTokensFromRows"] = cacheMissTokens,
            ["promptCacheHitRatioFromRows"] = cacheTotal > 0 ? Math.Round((double)cacheHitTokens!.Value / cacheTotal, 6) : null,
            ["estimatedCostCnyFromRows"] = loggedEstimatedCost,
            ["providerPromptTokensFromTerminal"] = terminalPromptTokens,
            ["providerCompletionTokensFromTerminal"] = terminalCompletionTokens,
            ["providerEstimatedCostCnyFromTerminal"] = terminalEstimatedCost,
            ["promptTokensRowsMinusTerminal"] = loggedPromptTokens.HasValue && terminalPromptTokens.HasValue ? loggedPromptTokens.Value - terminalPromptTokens.Value : null,
            ["completionTokensRowsMinusTerminal"] = loggedCompletionTokens.HasValue && terminalCompletionTokens.HasValue ? loggedCompletionTokens.Value - terminalCompletionTokens.Value : null,
            ["estimatedCostCnyRowsMinusTerminal"] = loggedEstimatedCost.HasValue && terminalEstimatedCost.HasValue ? Math.Round(loggedEstimatedCost.Value - terminalEstimatedCost.Value, 8) : null,
            ["lastBudgetReservationRejection"] = ReadLastBudgetRejection(path, baseRunId, hasBaseRunId)
        };
    }

    private static JsonObject? ReadLastBudgetRejection(string path, string baseRunId, bool hasBaseRunId)
    {
        try
        {
            foreach (var line in File.ReadLines(path).Reverse())
            {
                JsonObject? item;
                try { item = JsonNode.Parse(line) as JsonObject; }
                catch { continue; }
                if (item is null || ReadString(item, "event") != "provider-budget-reservation-rejected") continue;
                var itemRunId = ReadString(item, "runId");
                if (hasBaseRunId && (!TryGetBaseRunId(itemRunId, out var itemBaseRunId) || itemBaseRunId != baseRunId)) continue;
                return new JsonObject
                {
                    ["reservedBeforeCny"] = Copy(item, "reservedBeforeCny"),
                    ["nextRequestUpperBoundCny"] = Copy(item, "nextRequestUpperBoundCny"),
                    ["projectedReservedAfterCny"] = Copy(item, "projectedReservedAfterCny"),
                    ["runLimitCny"] = Copy(item, "runLimitCny"),
                    ["estimatedInputTokens"] = Copy(item, "estimatedInputTokens"),
                    ["reservedInputTokens"] = Copy(item, "reservedInputTokens"),
                    ["outputTokenCeiling"] = Copy(item, "outputTokenCeiling"),
                    ["nativeActionSent"] = Copy(item, "nativeActionSent")
                };
            }
        }
        catch { }
        return null;
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
            {"runId":"mcm-0123456789abcdef0123456789abcdef","goal":"PRIVATE_GOAL_TEXT","objectiveId":"gold","scopeRestriction":"safe-settlement-arrival","observation":{"state":{"campaignDay":42.5,"context":{"gameState":"PartyState","menuId":null,"timeControlMode":"Stop","encounterActive":false,"inquiryOpen":true,"inquiry":{"supported":true,"kind":"YesNoInquiry","token":"PRIVATE_INQUIRY_TOKEN","title":"Leaving troops behind","text":"PRIVATE_INQUIRY_BODY","affirmative":{"visible":true,"enabled":true,"text":"Yes"},"negative":{"visible":true,"enabled":true,"text":"No"}},"encounteredPartyId":null},"location":{"currentSettlementId":"village-1","targetPartyId":null},"economy":{"gold":100,"renown":20},"party":{"members":5,"sizeLimit":20,"healthy":3,"wounded":1,"prisoners":1,"morale":12.5,"food":0.5,"foodChange":-0.25,"isMoving":false,"moveMode":"Party","defaultBehavior":"Hold"},"partyScreen":{"mode":"Loot","canDone":true,"doneReason":"Leaving troops behind","rightMemberLimit":20,"leftMembers":[{"troopId":"hidden-native-id","count":5,"transferable":true}],"leftPrisoners":[],"rightMembers":[{"troopId":"looter","count":5,"transferable":false}],"rightPrisoners":[]},"objectiveSnapshot":{"gold":{"current":100,"target":2000,"met":false}}}},"allowedActions":[{"action":"respondInquiry","arguments":["choice"]},{"action":"partyScreenDone","arguments":[]}],"allowedControls":[]}
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
                PromptCacheHitTokens: 12, PromptCacheMissTokens: 34, EstimatedCostCny: 0.01, ReservedCostUpperBoundCny: 0.04,
                ProxySelectionSource: "local-listener", ProxyEndpointHostPort: "127.0.0.1:7890"),
            configuredRunCostLimitCny: 5);
        var loggedJson = loggedDecision.ToJsonString();
        if (ReadInt(loggedDecision, "promptTokens") != 321 || ReadInt(loggedDecision, "completionTokens") != 40 ||
            ReadInt(loggedDecision, "promptCacheHitTokens") != 12 || ReadInt(loggedDecision, "promptCacheMissTokens") != 34 ||
            Math.Abs((ReadDouble(loggedDecision, "estimatedCostCny") ?? -1) - 0.01) > 0.0000001 ||
            Math.Abs((ReadDouble(loggedDecision, "configuredRunCostLimitCny") ?? -1) - 5) > 0.0000001 ||
            ReadString(loggedDecision, "proxySelectionSource") != "local-listener" ||
            ReadString(loggedDecision, "proxyEndpointHostPort") != "127.0.0.1:7890" ||
            ReadString(loggedDecision, "objectiveId") != "gold" || ReadString(loggedDecision, "scope") != "safe-settlement-arrival" ||
            ReadBoolean(loggedDecision, "partyIsMoving") || ReadBoolean(loggedDecision, "encounterActive") ||
            ReadString(loggedDecision, "encounteredPartyId") is not null || ReadString(loggedDecision, "partyDefaultBehavior") != "Hold" ||
            ReadInt(loggedDecision, "partyWounded") != 1 || ReadInt(loggedDecision, "partyPrisoners") != 1 ||
            Math.Abs((ReadDouble(loggedDecision, "partyMorale") ?? -1) - 12.5) > 0.0000001 ||
            Math.Abs((ReadDouble(loggedDecision, "partyFood") ?? -1) - 0.5) > 0.0000001 ||
            Math.Abs((ReadDouble(loggedDecision, "partyFoodChange") ?? -1) + 0.25) > 0.0000001 ||
            loggedJson.Contains("PRIVATE_", StringComparison.Ordinal) || loggedJson.Contains("issue_offer_player_accept_quest", StringComparison.Ordinal) ||
            (loggedDecision["argumentNames"] as JsonArray)?.Count != 2)
            throw new AgentHostException("runtime-progress-log-privacy-or-usage-self-test-failed", "The player runtime log must retain token/cache/cost metadata and safe argument names while omitting goals, argument values, response text and rationales.");

        if (ReadBoolean(loggedDecision, "inquiryOpen") != true ||
            ReadString(loggedDecision, "inquiryKind") != "YesNoInquiry" ||
            ReadString(loggedDecision, "inquiryTitle") != "Leaving troops behind" ||
            ReadString(loggedDecision, "inquiryAffirmativeText") != "Yes" || ReadString(loggedDecision, "inquiryNegativeText") != "No" ||
            ReadString(loggedDecision["nativePartyScreen"] as JsonObject, "mode") != "Loot" ||
            ReadInt(loggedDecision["nativePartyScreen"]?["leftMembers"] as JsonObject, "count", -1) != 5 ||
            ReadInt(loggedDecision["nativePartyScreen"]?["leftMembers"] as JsonObject, "transferableCount", -1) != 5 ||
            loggedJson.Contains("PRIVATE_INQUIRY", StringComparison.Ordinal) || loggedJson.Contains("hidden-native-id", StringComparison.Ordinal))
            throw new AgentHostException("runtime-progress-log-native-party-ui-self-test-failed", "The player run log must record compact modal/PartyScreen context while omitting one-use tokens, inquiry body text and roster entity IDs.");

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
                RecordBudgetReservationRejected(childRequestDocument.RootElement, "deepseek-flash", 900, 990, 256, 4.9, 0.2, 5);
                RecordProviderFailure(request.RootElement, "provider-http-error", 429, "api.deepseek.com", "required_tool_call", 2, 1500,
                    "http-response-status", "local-listener", 360, 12000, "HttpRequestException",
                    "127.0.0.1:7890", "cloudflare", "1.1 proxy", "req-123", "30", "json-error", "application/json", "server_error", "overloaded");
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
            var budgetEvent = productLogLines.Length > 3 ? JsonNode.Parse(productLogLines[3]) as JsonObject : null;
            var summaryEvent = productLogLines.Length > 6 ? JsonNode.Parse(productLogLines[6]) as JsonObject : null;
            var summaryUsage = summaryEvent?["loggedProviderUsage"] as JsonObject;
            if (productLogLines.Length != 7 || productLogLines.Any(line => line.Contains("PRIVATE_", StringComparison.Ordinal) ||
                    line.Contains("PRIVATE_OPTION_VALUE", StringComparison.Ordinal)) ||
                ReadString(JsonNode.Parse(productLogLines[1]) as JsonObject, "event") != "provider-decision" ||
                ReadString(childDecision, "event") != "provider-decision" ||
                ReadString(childDecision, "runId") != validRun + "-battle-inquiry-1" ||
                ReadString(childDecision, "goalClassification") != "supported-map-arrival" ||
                ReadString(budgetEvent, "event") != "provider-budget-reservation-rejected" ||
                ReadString(JsonNode.Parse(productLogLines[4]) as JsonObject, "event") != "provider-failure" ||
                ReadInt(JsonNode.Parse(productLogLines[4]) as JsonObject, "providerHttpStatus") != 429 ||
                ReadString(JsonNode.Parse(productLogLines[4]) as JsonObject, "providerRoute") != "api.deepseek.com" ||
                ReadInt(JsonNode.Parse(productLogLines[4]) as JsonObject, "providerRetryAttempts") != 2 ||
                ReadString(JsonNode.Parse(productLogLines[4]) as JsonObject, "providerFailureStage") != "http-response-status" ||
                ReadString(JsonNode.Parse(productLogLines[4]) as JsonObject, "providerProxySelectionSource") != "local-listener" ||
                ReadString(JsonNode.Parse(productLogLines[4]) as JsonObject, "providerProxyEndpointHostPort") != "127.0.0.1:7890" ||
                ReadInt(JsonNode.Parse(productLogLines[4]) as JsonObject, "providerTimeoutSeconds") != 360 ||
                ReadInt(JsonNode.Parse(productLogLines[4]) as JsonObject, "providerRequestBodyBytes") != 12000 ||
                ReadString(JsonNode.Parse(productLogLines[4]) as JsonObject, "providerResponseServer") != "cloudflare" ||
                ReadString(JsonNode.Parse(productLogLines[4]) as JsonObject, "providerResponseVia") != "1.1 proxy" ||
                ReadString(JsonNode.Parse(productLogLines[4]) as JsonObject, "providerResponseRequestId") != "req-123" ||
                ReadString(JsonNode.Parse(productLogLines[4]) as JsonObject, "providerRetryAfter") != "30" ||
                ReadString(JsonNode.Parse(productLogLines[4]) as JsonObject, "providerErrorBodyKind") != "json-error" ||
                ReadString(JsonNode.Parse(productLogLines[4]) as JsonObject, "providerErrorContentType") != "application/json" ||
                ReadString(JsonNode.Parse(productLogLines[4]) as JsonObject, "providerErrorType") != "server_error" ||
                ReadString(JsonNode.Parse(productLogLines[4]) as JsonObject, "providerErrorCode") != "overloaded" ||
                ReadString(JsonNode.Parse(productLogLines[5]) as JsonObject, "objectiveId") != "gold" ||
                ReadString(summaryEvent, "event") != "run-summary" ||
                ReadInt(summaryUsage, "providerResponseRows", -1) != 2 ||
                ReadInt(summaryUsage, "providerFailureEventsWithoutUsage", -1) != 1 ||
                ReadInt(summaryUsage, "budgetReservationRejectionEvents", -1) != 1 ||
                ReadInt(summaryUsage, "reportedLoopDecisionCountMinusProviderRows", 0) != -1 ||
                ReadLong(summaryUsage, "promptTokensRowsMinusTerminal") != 99 ||
                Math.Abs((ReadDouble(summaryUsage, "estimatedCostCnyFromRows") ?? -1) - 0.012) > 0.0000001 ||
                Math.Abs((ReadDouble(summaryUsage, "estimatedCostCnyRowsMinusTerminal") ?? -1) - 0.002) > 0.0000001 ||
                Math.Abs((ReadDouble(summaryUsage, "promptCacheHitRatioFromRows") ?? -1) - (12d / 145d)) > 0.000001 ||
                Math.Abs((ReadDouble(budgetEvent, "projectedReservedAfterCny") ?? -1) - 5.1) > 0.0000001)
            {
                var loggedEvents = string.Join(",", productLogLines.Select(line => ReadString(JsonNode.Parse(line) as JsonObject, "event") ?? "unknown"));
                var privateMarkerFound = productLogLines.Any(line => line.Contains("PRIVATE_", StringComparison.Ordinal));
                throw new AgentHostException("runtime-progress-log-end-to-end-self-test-failed", $"A MCM run must persist per-decision cost data and reconcile the final summary while omitting secret markers and free-text payloads. lines={productLogLines.Length}; events={loggedEvents}; privateMarker={privateMarkerFound}; providerRows={ReadInt(summaryUsage, "providerResponseRows", -1)}; decisionDelta={ReadInt(summaryUsage, "reportedLoopDecisionCountMinusProviderRows", 0)}; promptDelta={ReadLong(summaryUsage, "promptTokensRowsMinusTerminal")}; rowCost={ReadDouble(summaryUsage, "estimatedCostCnyFromRows")}; costDelta={ReadDouble(summaryUsage, "estimatedCostCnyRowsMinusTerminal")}; projectedReserve={ReadDouble(budgetEvent, "projectedReservedAfterCny")}.");
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
    private static string? Truncate(string? value, int max) => string.IsNullOrEmpty(value) ? value : value.Length <= max ? value : value[..max];
    private static string? ReadString(JsonElement parent, string name) =>
        parent.ValueKind == JsonValueKind.Object && parent.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString() : null;
    private static int? ReadInt(JsonObject? parent, string name) =>
        parent?[name] is JsonValue node && node.TryGetValue<int>(out var value) ? value : null;
    private static int ReadInt(JsonObject? parent, string name, int fallback) => ReadInt(parent, name) ?? fallback;
    private static long? ReadLong(JsonObject? parent, string name)
    {
        if (parent?[name] is not JsonValue node) return null;
        if (node.TryGetValue<long>(out var value)) return value;
        if (node.TryGetValue<int>(out var intValue)) return intValue;
        if (node.TryGetValue<JsonElement>(out var element) && element.ValueKind == JsonValueKind.Number && element.TryGetInt64(out value)) return value;
        return null;
    }
    private static double? ReadDouble(JsonObject? parent, string name) =>
        parent?[name] is JsonValue node && node.TryGetValue<double>(out var value) ? value : null;
    private static string? ReadString(JsonObject? parent, string name) =>
        parent?[name] is JsonValue node && node.TryGetValue<string>(out var value) ? value : null;
    private static bool ReadBoolean(JsonObject? parent, string name) =>
        parent?[name] is JsonValue node && node.TryGetValue<bool>(out var value) && value;
    private static string SanitizeCode(string code) => Regex.Replace(code ?? string.Empty, "[^A-Za-z0-9._-]", "_")[..Math.Min(80, (code ?? string.Empty).Length)];
}
