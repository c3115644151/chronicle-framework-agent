using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal static class AgentHostHarnessProgressTrace
{
    private const long MaximumBytes = 16L * 1024 * 1024;
    private static readonly object WriteGate = new();

    internal static void RecordDecision(JsonElement request, ProviderDecisionResult result, double? configuredRunCostLimitCny = null)
    {
        AgentHostRuntimeProgressLog.RecordDecision(request, result, configuredRunCostLimitCny);
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
            var observationFieldByteSizes = new JsonArray();
            if (observation is not null)
            {
                foreach (var property in observation.Select(property => new
                {
                    Name = property.Key,
                    Bytes = Encoding.UTF8.GetByteCount(property.Value?.ToJsonString() ?? "null")
                }).OrderByDescending(property => property.Bytes).ThenBy(property => property.Name, StringComparer.Ordinal).Take(12))
                {
                    observationFieldByteSizes.Add(new JsonObject { ["field"] = property.Name, ["bytes"] = property.Bytes });
                }
            }
            var stateFieldByteSizes = new JsonArray();
            if (state is not null)
            {
                foreach (var property in state.Select(property => new
                {
                    Name = property.Key,
                    Bytes = Encoding.UTF8.GetByteCount(property.Value?.ToJsonString() ?? "null")
                }).OrderByDescending(property => property.Bytes).ThenBy(property => property.Name, StringComparer.Ordinal).Take(12))
                {
                    stateFieldByteSizes.Add(new JsonObject { ["field"] = property.Name, ["bytes"] = property.Bytes });
                }
            }
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
                ["objectiveId"] = ReadString(requestNode, "objectiveId"),
                ["scope"] = ReadString(observation, "scope") ?? "campaign-agent-loop",
                ["scopeRestriction"] = ReadString(requestNode, "scopeRestriction"),
                ["modelId"] = result.ModelId,
                ["routedVia"] = result.RoutedVia,
                ["fallbackAttempts"] = result.FallbackAttempts,
                ["fallbackTrail"] = result.FallbackTrail,
                ["proxySelectionSource"] = result.ProxySelectionSource,
                ["proxyEndpointHostPort"] = result.ProxyEndpointHostPort,
                ["responseFormatMode"] = result.ResponseFormatMode,
                ["promptTokens"] = result.PromptTokens,
                ["completionTokens"] = result.CompletionTokens,
                ["promptCacheHitTokens"] = result.PromptCacheHitTokens,
                ["promptCacheMissTokens"] = result.PromptCacheMissTokens,
                ["deepSeekEstimatedInputTokens"] = result.DeepSeekEstimatedInputTokens,
                ["deepSeekRawRequestTokens"] = result.DeepSeekRawRequestTokens,
                ["deepSeekReservedInputTokens"] = result.DeepSeekReservedInputTokens,
                ["deepSeekInputTokenEstimator"] = result.DeepSeekInputTokenEstimator,
                ["requestBodyBytes"] = result.RequestBodyBytes,
                ["systemPromptBytes"] = result.SystemPromptBytes,
                ["userPayloadBytes"] = result.UserPayloadBytes,
                ["observationBytes"] = result.ObservationBytes,
                ["observationFieldByteSizes"] = observationFieldByteSizes,
                ["observationStateFieldByteSizes"] = stateFieldByteSizes,
                ["estimatedCostCny"] = result.EstimatedCostCny,
                ["reservedCostUpperBoundCny"] = result.ReservedCostUpperBoundCny,
                ["decision"] = decision,
                ["allowedActions"] = SummarizeAllowedActionNames(requestNode?["allowedActions"] as JsonArray),
                ["allowedControls"] = requestNode?["allowedControls"]?.DeepClone(),
                ["decisionFeedbackKind"] = Copy((observation?["decisionFeedback"] as JsonObject), "kind"),
                ["observation"] = new JsonObject
                {
                    ["campaignDay"] = Copy(state, "campaignDay"),
                    ["gameState"] = Copy(context, "gameState"),
                    ["menuId"] = Copy(context, "menuId"),
                    ["inquiryOpen"] = Copy(context, "inquiryOpen"),
                    ["inquiry"] = BuildInquirySummary(context?["inquiry"] as JsonObject),
                    ["partyScreen"] = BuildPartyScreenSummary(state?["partyScreen"] as JsonObject),
                    ["timeControlMode"] = Copy(context, "timeControlMode"),
                    ["isWaiting"] = Copy(context, "isWaiting"),
                    ["encounterActive"] = Copy(context, "encounterActive"),
                    ["encounteredPartyId"] = Copy(context, "encounteredPartyId"),
                    ["battleSimulationActive"] = context?["battleSimulation"] is JsonObject,
                    ["currentSettlementId"] = Copy(location, "currentSettlementId"),
                    ["targetSettlementId"] = Copy(location, "targetSettlementId"),
                    ["targetPartyId"] = Copy(location, "targetPartyId"),
                    ["gold"] = Copy(economy, "gold"),
                    ["renown"] = Copy(economy, "renown"),
                    ["partyMembers"] = Copy(party, "members"),
                    ["partyHealthy"] = Copy(party, "healthy"),
                    ["partyWounded"] = Copy(party, "wounded"),
                    ["partyPrisoners"] = Copy(party, "prisoners"),
                    ["partyMorale"] = Copy(party, "morale"),
                    ["partyFood"] = Copy(party, "food"),
                    ["partyFoodChange"] = Copy(party, "foodChange"),
                    ["partyIsMoving"] = Copy(party, "isMoving"),
                    ["partyMoveMode"] = Copy(party, "moveMode"),
                    ["partyDefaultBehavior"] = Copy(party, "defaultBehavior"),
                    ["objectiveSnapshot"] = BuildObjectiveSnapshotSummary(state?["objectiveSnapshot"] as JsonObject),
                    ["nativeProgressionContext"] = BuildNativeProgressionContextSummary(state?["nativeProgressionContext"] as JsonObject),
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

    internal static void RecordPassiveObservation(string eventName, JsonObject observation)
    {
        if (string.IsNullOrWhiteSpace(eventName) || eventName.Length > 80 ||
            eventName.Any(character => !(char.IsAsciiLetterOrDigit(character) || character is '-' or '_'))) return;
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
            var payload = new JsonObject
            {
                ["event"] = eventName,
                ["utc"] = DateTime.UtcNow.ToString("O", System.Globalization.CultureInfo.InvariantCulture)
            };
            foreach (var property in observation)
                payload[property.Key] = property.Value?.DeepClone();
            AppendLine(tracePath, Encoding.UTF8.GetBytes(payload.ToJsonString() + Environment.NewLine));
        }
        catch
        {
            // Diagnostics must never change or block a Native action or provider decision.
        }
    }

    internal static void RecordObjectiveSubflowResult(string objectiveId, JsonObject result)
    {
        AgentHostRuntimeProgressLog.RecordObjectiveSubflowResult(objectiveId, result);
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
                ["objectiveSnapshot"] = BuildObjectiveSnapshotSummary(result["objectiveSnapshot"] as JsonObject),
                ["recruitmentOfferSummary"] = BuildRecruitmentOfferSummary(result["lastRecruitmentOffers"] as JsonObject),
                ["companionNavigationSummary"] = BuildCompanionNavigationSummary(result["trace"] as JsonArray),
                ["tavernEntryTransitionSummary"] = result["tavernEntryTransitionSummary"]?.DeepClone(),
                ["companionSearchMemory"] = BuildCompanionSearchMemorySummary(result["companionSearchMemory"] as JsonObject),
                ["villagersInNeedStartupSummary"] = BuildVillagersInNeedStartupSummary(result["trace"] as JsonArray),
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

    internal static void RecordProviderFailure(JsonElement request, AgentHostException exception) =>
        RecordProviderFailure(request, exception.Code, exception.ProviderHttpStatus, exception.ProviderRoute,
            exception.ProviderOutputFormat, exception.ProviderRetryAttempts, exception.ProviderRetryWaitMilliseconds, exception.ProviderFailureStage,
            exception.ProviderProxySelectionSource, exception.ProviderTimeoutSeconds, exception.ProviderRequestBodyBytes, exception.ProviderTransportErrorType,
            exception.ProviderProxyEndpointHostPort, exception.ProviderResponseServer, exception.ProviderResponseVia, exception.ProviderResponseRequestId,
            exception.ProviderRetryAfter, exception.ProviderErrorBodyKind, exception.ProviderErrorContentType, exception.ProviderErrorType, exception.ProviderErrorCode,
            exception.ProviderFallbackAttempts, exception.ProviderFallbackTrail);

    internal static void RecordProviderFailure(JsonElement request, string failureCode, int? providerHttpStatus = null,
        string? providerRoute = null, string? providerOutputFormat = null, int? providerRetryAttempts = null, long? providerRetryWaitMilliseconds = null,
        string? providerFailureStage = null, string? providerProxySelectionSource = null, int? providerTimeoutSeconds = null,
        int? providerRequestBodyBytes = null, string? providerTransportErrorType = null, string? providerProxyEndpointHostPort = null,
        string? providerResponseServer = null, string? providerResponseVia = null, string? providerResponseRequestId = null, string? providerRetryAfter = null,
        string? providerErrorBodyKind = null, string? providerErrorContentType = null, string? providerErrorType = null, string? providerErrorCode = null,
        int? providerFallbackAttempts = null, string? providerFallbackTrail = null)
    {
        AgentHostRuntimeProgressLog.RecordProviderFailure(request, failureCode, providerHttpStatus, providerRoute,
            providerOutputFormat, providerRetryAttempts, providerRetryWaitMilliseconds, providerFailureStage,
            providerProxySelectionSource, providerTimeoutSeconds, providerRequestBodyBytes, providerTransportErrorType,
            providerProxyEndpointHostPort, providerResponseServer, providerResponseVia, providerResponseRequestId, providerRetryAfter,
            providerErrorBodyKind, providerErrorContentType, providerErrorType, providerErrorCode, providerFallbackAttempts, providerFallbackTrail);
        var harnessMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        if (harnessMode is not ("visual-capture" or "agent-host-lifecycle-test")) return;
        var directory = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (string.IsNullOrWhiteSpace(directory) || !Directory.Exists(directory)) return;
        try
        {
            var rootPath = Path.GetFullPath(directory).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
            var tracePath = Path.GetFullPath(Path.Combine(rootPath, "AgentHostProgress.jsonl"));
            if (!tracePath.StartsWith(rootPath, StringComparison.OrdinalIgnoreCase)) return;
            var requestNode = JsonNode.Parse(request.GetRawText()) as JsonObject;
            var observation = requestNode?["observation"] as JsonObject;
            var payload = new JsonObject
            {
                ["event"] = "provider-failure",
                ["utc"] = DateTime.UtcNow.ToString("O", System.Globalization.CultureInfo.InvariantCulture),
                ["runId"] = ReadString(request, "runId"),
                ["failureCode"] = failureCode,
                ["objectiveId"] = ReadString(requestNode, "objectiveId") ?? ReadString(observation, "objectiveId"),
                ["scope"] = ReadString(requestNode, "scopeRestriction") ?? ReadString(observation, "scope") ?? "campaign-agent-loop",
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
                ["providerFallbackAttempts"] = providerFallbackAttempts,
                ["providerFallbackTrail"] = providerFallbackTrail,
                ["nativeActionSent"] = false,
                ["responseBodiesLogged"] = false,
                ["credentialsLogged"] = false
            };
            AppendLine(tracePath, Encoding.UTF8.GetBytes(payload.ToJsonString() + Environment.NewLine));
        }
        catch
        {
            // Provider diagnostics must never replace the original failure or emit payload contents.
        }
    }

    internal static void RecordBudgetReservationRejected(JsonElement request, string modelId, int estimatedInputTokens, int reservedInputTokens,
        int outputTokenCeiling, double reservedBeforeCny, double nextRequestUpperBoundCny, double runLimitCny)
    {
        AgentHostRuntimeProgressLog.RecordBudgetReservationRejected(request, modelId, estimatedInputTokens, reservedInputTokens,
            outputTokenCeiling, reservedBeforeCny, nextRequestUpperBoundCny, runLimitCny);
        var harnessMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        if (harnessMode is not ("visual-capture" or "agent-host-lifecycle-test")) return;
        var directory = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (string.IsNullOrWhiteSpace(directory) || !Directory.Exists(directory)) return;
        try
        {
            var rootPath = Path.GetFullPath(directory).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
            var tracePath = Path.GetFullPath(Path.Combine(rootPath, "AgentHostProgress.jsonl"));
            if (!tracePath.StartsWith(rootPath, StringComparison.OrdinalIgnoreCase)) return;
            var requestNode = JsonNode.Parse(request.GetRawText()) as JsonObject;
            var observation = requestNode?["observation"] as JsonObject;
            var payload = new JsonObject
            {
                ["event"] = "provider-budget-reservation-rejected",
                ["utc"] = DateTime.UtcNow.ToString("O", System.Globalization.CultureInfo.InvariantCulture),
                ["runId"] = ReadString(request, "runId"),
                ["modelId"] = modelId,
                ["objectiveId"] = ReadString(requestNode, "objectiveId") ?? ReadString(observation, "objectiveId"),
                ["scope"] = ReadString(requestNode, "scopeRestriction") ?? ReadString(observation, "scope") ?? "campaign-agent-loop",
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
            };
            AppendLine(tracePath, Encoding.UTF8.GetBytes(payload.ToJsonString() + Environment.NewLine));
        }
        catch
        {
            // Budget diagnostics must never alter provider behavior or the safety cap.
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
        var conversation = context?["conversation"] as JsonObject;
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
        var conversationOptions = new JsonArray();
        if (conversation?["options"] is JsonArray sourceConversationOptions)
        {
            foreach (var option in sourceConversationOptions.OfType<JsonObject>())
                conversationOptions.Add(new JsonObject
                {
                    ["id"] = Copy(option, "id"),
                    ["textId"] = Copy(option, "textId"),
                    ["clickable"] = Copy(option, "clickable")
                });
        }
        return new JsonObject
        {
            ["campaignDay"] = Copy(native, "campaignDay"),
            ["gameState"] = Copy(context, "gameState"),
            ["menuId"] = Copy(context, "menuId"),
            ["currentSettlementId"] = Copy(location, "currentSettlementId"),
            ["targetSettlementId"] = Copy(location, "targetSettlementId"),
            ["targetPartyId"] = Copy(location, "targetPartyId"),
            ["conversationCharacterId"] = Copy(conversation, "characterId"),
            ["conversationHeroId"] = Copy(conversation, "heroId"),
            ["conversationOptions"] = conversationOptions,
            ["encounteredPartyId"] = Copy(context, "encounteredPartyId"),
            ["encounterActive"] = Copy(context, "encounterActive"),
            ["escapeMenuOpen"] = Copy(context, "escapeMenuOpen"),
            ["inquiryOpen"] = Copy(context, "inquiryOpen"),
            ["inquiry"] = BuildInquirySummary(context?["inquiry"] as JsonObject),
            ["partyScreenOpen"] = state["partyScreen"] is JsonObject,
            ["partyScreen"] = BuildPartyScreenSummary(state["partyScreen"] as JsonObject),
            ["inventoryScreenOpen"] = state["inventoryScreen"] is JsonObject,
            ["battleSimulationActive"] = context?["battleSimulation"] is JsonObject,
            ["isCaptive"] = Copy(captivity, "isCaptive"),
            ["storyModeStatus"] = Copy(storyMode, "status"),
            ["tutorialCompleted"] = Copy(storyMode, "tutorialCompleted"),
            ["gold"] = Copy(economy, "gold"),
            ["renown"] = Copy(economy, "renown"),
            ["partyMembers"] = Copy(party, "members"),
            ["partySizeLimit"] = Copy(party, "sizeLimit"),
            ["partyHealthy"] = Copy(party, "healthy"),
            ["partyWounded"] = Copy(party, "wounded"),
            ["partyPrisoners"] = Copy(party, "prisoners"),
            ["partyMorale"] = Copy(party, "morale"),
            ["partyFood"] = Copy(party, "food"),
            ["partyFoodChange"] = Copy(party, "foodChange"),
            ["partyIsMoving"] = Copy(party, "isMoving"),
            ["partyMoveMode"] = Copy(party, "moveMode"),
            ["partyDefaultBehavior"] = Copy(party, "defaultBehavior"),
            ["questIds"] = questIds,
            ["availableMenuOptions"] = menuOptions
        };
    }

    private static JsonObject? BuildCompanionSearchMemorySummary(JsonObject? memory)
    {
        if (memory is null) return null;
        return new JsonObject
        {
            ["checkpointReadAttempted"] = Copy(memory, "checkpointReadAttempted"),
            ["noCandidateTownCount"] = Copy(memory, "noCandidateTownCount"),
            ["memoryMatchedCurrentJournal"] = Copy(memory, "memoryMatchedCurrentJournal"),
            ["memoryInvalidatedByJournalProgress"] = Copy(memory, "memoryInvalidatedByJournalProgress"),
            ["memoryReusedAfterJournalDecrease"] = Copy(memory, "memoryReusedAfterJournalDecrease"),
            ["checkpointWriteCount"] = Copy(memory, "checkpointWriteCount"),
            ["lastCheckpointWriteStatus"] = Copy(memory, "lastCheckpointWriteStatus")
        };
    }

    internal static JsonObject? BuildInquirySummary(JsonObject? inquiry)
    {
        if (inquiry is null) return null;
        return new JsonObject
        {
            ["supported"] = Copy(inquiry, "supported"),
            ["kind"] = Copy(inquiry, "kind"),
            ["title"] = Copy(inquiry, "title"),
            ["text"] = Truncate(ReadString(inquiry, "text"), 400),
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

    internal static JsonArray SummarizeAllowedActionNames(JsonArray? actions) => new((actions?.OfType<JsonObject>() ?? Enumerable.Empty<JsonObject>())
        .Select(item => ReadString(item, "action"))
        .Where(name => !string.IsNullOrWhiteSpace(name))
        .Distinct(StringComparer.Ordinal)
        .Select(name => (JsonNode?)JsonValue.Create(name))
        .ToArray());

    internal static JsonObject? BuildPartyScreenSummary(JsonObject? screen)
    {
        if (screen is null) return null;
        return new JsonObject
        {
            ["mode"] = Copy(screen, "mode"),
            ["canDone"] = Copy(screen, "canDone"),
            ["doneReason"] = Truncate(ReadString(screen, "doneReason"), 300),
            ["rightMemberLimit"] = Copy(screen, "rightMemberLimit"),
            ["rightPrisonerLimit"] = Copy(screen, "rightPrisonerLimit"),
            ["leftMembers"] = BuildRosterSummary(screen["leftMembers"] as JsonArray),
            ["leftPrisoners"] = BuildRosterSummary(screen["leftPrisoners"] as JsonArray),
            ["rightMembers"] = BuildRosterSummary(screen["rightMembers"] as JsonArray),
            ["rightPrisoners"] = BuildRosterSummary(screen["rightPrisoners"] as JsonArray)
        };
    }

    private static JsonObject BuildRosterSummary(JsonArray? rows)
    {
        var sourceRows = rows?.OfType<JsonObject>().ToArray() ?? Array.Empty<JsonObject>();
        var count = sourceRows.Sum(row => Math.Max(0, ReadInt(row, "count", 0)));
        var transferableCount = sourceRows.Where(row => ReadBoolean(row, "transferable"))
            .Sum(row => Math.Max(0, ReadInt(row, "count", 0)));
        return new JsonObject
        {
            ["rowCount"] = sourceRows.Length,
            ["count"] = count,
            ["transferableCount"] = transferableCount
        };
    }

    internal static IReadOnlyList<object> RunContractSelfTests()
    {
        var modalSummary = BuildNativeStateSummary(new JsonObject
        {
            ["state"] = new JsonObject
            {
                ["context"] = new JsonObject
                {
                    ["gameState"] = "MapState", ["escapeMenuOpen"] = false, ["inquiryOpen"] = true,
                    ["conversation"] = new JsonObject
                    {
                        ["characterId"] = "tutorial_npc_questgiver_villager",
                        ["options"] = new JsonArray(new JsonObject { ["id"] = "adg:131", ["textId"] = "glarczej", ["clickable"] = true })
                    },
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
        var summarizedConversationOption = (modalSummary?["conversationOptions"] as JsonArray)?[0] as JsonObject;
        if (ReadBoolean(modalSummary, "inquiryOpen") != true || ReadString(summarizedInquiry, "kind") != "YesNoInquiry" ||
            ReadString(summarizedInquiry, "text") != "Native alert body" ||
            ReadString(modalSummary, "conversationCharacterId") != "tutorial_npc_questgiver_villager" ||
            ReadString(summarizedConversationOption, "id") != "adg:131" || ReadString(summarizedConversationOption, "textId") != "glarczej" ||
            ReadBoolean(summarizedConversationOption, "clickable") != true ||
            ReadString(summarizedInquiry?["affirmative"] as JsonObject, "text") != "好" ||
            summarizedInquiry?.ContainsKey("token") == true || ReadBoolean(modalSummary, "partyScreenOpen") || ReadBoolean(modalSummary, "inventoryScreenOpen"))
            throw new AgentHostException("host-progress-trace-native-modal-self-test", "The bounded progress trace must identify current modal blockers and visible button labels without leaking one-use tokens or claiming unrelated screens.");
        var conversationStartupSummary = BuildVillagersInNeedStartupSummary(new JsonArray(new JsonObject
        {
            ["kind"] = "native-villagers-in-need-conversation-startup-settle",
            ["before"] = new JsonObject { ["gameState"] = "MissionState", ["conversationCharacterId"] = null },
            ["after"] = new JsonObject { ["gameState"] = "MissionState", ["conversationCharacterId"] = "tutorial_npc_questgiver_villager" },
            ["beforeTimeControlMode"] = "Stop", ["afterTimeControlMode"] = "Stop"
        }));
        if (ReadInt(conversationStartupSummary, "waitCount") != 1 ||
            ReadString(conversationStartupSummary?["firstBefore"] as JsonObject, "conversationCharacterId") is not null ||
            ReadString(conversationStartupSummary?["lastAfter"] as JsonObject, "conversationCharacterId") != "tutorial_npc_questgiver_villager" ||
            ReadString(conversationStartupSummary, "lastAfterTimeControlMode") != "Stop")
            throw new AgentHostException("host-progress-trace-villagers-conversation-startup-self-test", "The bounded Host result must distinguish a pending native conversation load from the resolved Character identity without storing raw dialogue text.");
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
                {"runId":"trace-test","objectiveId":"partySize","observation":{"scope":"native-storymode-party-size-recruitment","state":{"campaignDay":12.5,"context":{"gameState":"MapState","menuId":"village","encounterActive":true,"encounteredPartyId":"bandit-a","conversation":{"sentenceText":"Tools are needed.","options":[{"id":"issue_offer_player_accept_quest","text":"I can do it.","clickable":true}] }},"location":{"currentSettlementId":"village-1","targetPartyId":"bandit-a"},"economy":{"gold":920,"renown":20},"party":{"members":5,"healthy":3,"wounded":1,"prisoners":1,"morale":12.5,"food":0.5,"foodChange":-0.25,"isMoving":true,"moveMode":"Party","defaultBehavior":"EngageParty"},"objectiveSnapshot":{"gold":{"current":920,"target":2000,"met":false},"partySize":{"current":5,"target":25,"met":false},"renown":{"current":20,"target":50,"met":false},"companions":{"current":0,"target":1,"met":false}},"nativeProgressionContext":{"clanTier":0,"partySizeLimit":20,"partyMembers":5,"partyIsMoving":false,"privateDiagnostic":"must-not-appear"},"quests":[],"settlementOverlayCharacters":[]}}}
                """);
            var decision = JsonNode.Parse("""{"action":"dialogueSelect","arguments":{"OptionId":"issue_offer_player_accept_quest"},"rationale":"Rationale is deliberately excluded."}""")!.AsObject();
            RecordDecision(request.RootElement, new ProviderDecisionResult("completed", "selftest-model", 123, 17, "stop", decision, "selftest/route",
                RequestBodyBytes: 40000, SystemPromptBytes: 1000, UserPayloadBytes: 30000, ObservationBytes: 5000,
                PromptCacheHitTokens: 50, PromptCacheMissTokens: 73, EstimatedCostCny: 0.0005, ReservedCostUpperBoundCny: 0.001,
                DeepSeekEstimatedInputTokens: 35000, DeepSeekRawRequestTokens: 41000, DeepSeekReservedInputTokens: 42000,
                DeepSeekInputTokenEstimator: "deepseek-v4-chat-template-plus-structured-metadata",
                ProxySelectionSource: "local-listener", ProxyEndpointHostPort: "127.0.0.1:7890",
                FallbackAttempts: 2, FallbackTrail: "ovh/model=rate_limited; nvidia/model=upstream_502"));
            var lines = File.ReadAllLines(path);
            if (lines.Length != 1) throw new AgentHostException("host-progress-trace-self-test-line-count", "Harness progress trace did not append exactly one decision.");
            var recorded = JsonNode.Parse(lines[0]) as JsonObject ?? throw new AgentHostException("host-progress-trace-self-test-json", "Harness progress trace did not contain one JSON object.");
            var recordedDecision = recorded["decision"] as JsonObject;
            if (ReadString(recorded, "routedVia") != "selftest/route" ||
                ReadInt(recorded, "fallbackAttempts") != 2 ||
                ReadString(recorded, "fallbackTrail") != "ovh/model=rate_limited; nvidia/model=upstream_502" ||
                ReadString(recorded, "proxySelectionSource") != "local-listener" ||
                ReadString(recorded, "proxyEndpointHostPort") != "127.0.0.1:7890" ||
                ReadString(recorded, "scope") != "native-storymode-party-size-recruitment" ||
                ReadString(recorded, "objectiveId") != "partySize" ||
                ReadString(recordedDecision, "action") != "dialogueSelect" ||
                ReadString(recordedDecision?["arguments"] as JsonObject, "OptionId") != "issue_offer_player_accept_quest" ||
                recordedDecision?.ContainsKey("rationale") == true ||
                ReadString(recorded?["observation"] as JsonObject, "menuId") != "village" ||
                (ReadInt(recorded, "requestBodyBytes") ?? 0) != 40000 || (ReadInt(recorded, "systemPromptBytes") ?? 0) != 1000 ||
                (ReadInt(recorded, "deepSeekEstimatedInputTokens") ?? 0) != 35000 ||
                (ReadInt(recorded, "deepSeekRawRequestTokens") ?? 0) != 41000 ||
                (ReadInt(recorded, "deepSeekReservedInputTokens") ?? 0) != 42000 ||
                ReadString(recorded, "deepSeekInputTokenEstimator") != "deepseek-v4-chat-template-plus-structured-metadata" ||
                (ReadInt(recorded, "userPayloadBytes") ?? 0) != 30000 || (ReadInt(recorded, "observationBytes") ?? 0) != 5000 ||
                (ReadInt(recorded, "promptCacheHitTokens") ?? 0) != 50 || (ReadInt(recorded, "promptCacheMissTokens") ?? 0) != 73 ||
                Math.Abs((ReadDouble(recorded, "estimatedCostCny") ?? -1) - 0.0005) > 0.0000001 ||
                Math.Abs((ReadDouble(recorded, "reservedCostUpperBoundCny") ?? -1) - 0.001) > 0.0000001 ||
                recorded!.ContainsKey("systemPrompt") || recorded.ContainsKey("userPayload") || recorded.ContainsKey("requestBody"))
                throw new AgentHostException("host-progress-trace-self-test-content", "Harness trace must preserve route, Native choice, request/cache/cost diagnostics and state-field sizes while excluding prompt or body text.");
            var traceObservation = recorded["observation"] as JsonObject;
            if (ReadBoolean(traceObservation, "encounterActive") != true ||
                ReadString(traceObservation, "encounteredPartyId") != "bandit-a" ||
                ReadString(traceObservation, "targetPartyId") != "bandit-a" ||
                ReadBoolean(traceObservation, "partyIsMoving") != true ||
                ReadString(traceObservation, "partyDefaultBehavior") != "EngageParty" ||
                ReadInt(traceObservation, "partyHealthy") != 3 || ReadInt(traceObservation, "partyWounded") != 1 ||
                ReadInt(traceObservation, "partyPrisoners") != 1 ||
                Math.Abs((ReadDouble(traceObservation, "partyMorale") ?? -1) - 12.5) > 0.0000001 ||
                Math.Abs((ReadDouble(traceObservation, "partyFood") ?? -1) - 0.5) > 0.0000001 ||
                Math.Abs((ReadDouble(traceObservation, "partyFoodChange") ?? -1) + 0.25) > 0.0000001)
                throw new AgentHostException("host-progress-trace-party-state-self-test", "The bounded model-decision trace must retain encounter and Native party context needed to diagnose movement, pursuit and survival decisions.");
            var traceProgression = traceObservation?["nativeProgressionContext"] as JsonObject;
            var traceObjectives = traceObservation?["objectiveSnapshot"] as JsonObject;
            if (ReadInt(traceProgression, "partySizeLimit") != 20 || ReadInt(traceProgression, "clanTier") != 0 ||
                traceProgression?.ContainsKey("privateDiagnostic") == true ||
                ReadDouble(traceObjectives?["partySize"] as JsonObject, "target") != 25 ||
                ReadBoolean(traceObjectives?["partySize"] as JsonObject, "met"))
                throw new AgentHostException("host-progress-trace-progression-context-self-test", "The bounded model-decision trace must retain only allowlisted Native capacity context and the four Journal objective metrics needed to audit the planner's decision.");
            var stateFieldSizes = recorded["observationStateFieldByteSizes"] as JsonArray;
            if (stateFieldSizes?.OfType<JsonObject>().Any(item => ReadString(item, "field") == "economy" && (ReadInt(item, "bytes") ?? 0) > 0) != true)
                throw new AgentHostException("host-progress-trace-state-field-size-self-test", "Harness trace must identify oversized observation fields by name and byte count without persisting their values.");
            var observationFieldSizes = recorded["observationFieldByteSizes"] as JsonArray;
            if (observationFieldSizes?.OfType<JsonObject>().Any(item => ReadString(item, "field") == "state" && (ReadInt(item, "bytes") ?? 0) > 0) != true)
                throw new AgentHostException("host-progress-trace-observation-field-size-self-test", "Harness trace must identify which bounded observation section contributes request size without persisting its contents.");

            using var partyRequest = JsonDocument.Parse("""
                {"runId":"trace-test","observation":{"scope":"native-postbattle-party-screen","state":{"context":{"gameState":"PartyState","inquiryOpen":true,"inquiry":{"supported":true,"kind":"YesNoInquiry","token":"PRIVATE_INQUIRY_TOKEN","title":"Leaving troops behind","text":"PRIVATE_INQUIRY_BODY","affirmative":{"visible":true,"enabled":true,"text":"Yes"},"negative":{"visible":true,"enabled":true,"text":"No"}}},"party":{"members":5,"sizeLimit":20},"partyScreen":{"mode":"Loot","canDone":true,"doneReason":"Leaving troops behind","rightMemberLimit":20,"rightPrisonerLimit":18,"leftMembers":[{"troopId":"hidden-native-id","count":5,"transferable":true}],"leftPrisoners":[],"rightMembers":[{"troopId":"hidden-player-id","count":5,"transferable":false}],"rightPrisoners":[]}}},"allowedActions":[{"action":"partyTakeAll","arguments":["TroopType"]},{"action":"partyScreenDone","arguments":[]}],"allowedControls":[]}
                """);
            var partyDecision = JsonNode.Parse("""{"action":"respondInquiry","arguments":{"choice":"negative"},"rationale":"Private model rationale."}""")!.AsObject();
            RecordDecision(partyRequest.RootElement, new ProviderDecisionResult("completed", "selftest-model", 51, 12, "required_tool_call", partyDecision, "selftest/party-inquiry"));
            var partyLines = File.ReadAllLines(path);
            if (partyLines.Length != 2)
                throw new AgentHostException("host-progress-trace-party-screen-event-count", "PartyState progress trace did not append the expected second decision event.");
            var partyEvent = JsonNode.Parse(partyLines[1]) as JsonObject ?? throw new AgentHostException("host-progress-trace-party-screen-event-json", "PartyState progress trace did not contain a JSON event.");
            var partyObservation = partyEvent["observation"] as JsonObject;
            var inquirySummary = partyObservation?["inquiry"] as JsonObject;
            var partyScreenSummary = partyObservation?["partyScreen"] as JsonObject;
            var loggedAllowedActions = partyEvent["allowedActions"] as JsonArray;
            var partyEventJson = partyEvent.ToJsonString();
            if (ReadString(partyObservation, "gameState") != "PartyState" ||
                ReadString(inquirySummary, "kind") != "YesNoInquiry" || ReadString(inquirySummary, "title") != "Leaving troops behind" ||
                ReadString(inquirySummary?["affirmative"] as JsonObject, "text") != "Yes" ||
                ReadString(inquirySummary?["negative"] as JsonObject, "text") != "No" ||
                ReadString(partyScreenSummary, "mode") != "Loot" || ReadBoolean(partyScreenSummary, "canDone") != true ||
                ReadInt(partyScreenSummary?["leftMembers"] as JsonObject, "count", -1) != 5 ||
                ReadInt(partyScreenSummary?["leftMembers"] as JsonObject, "transferableCount", -1) != 5 ||
                loggedAllowedActions?.Any(action => action?.GetValue<string>() == "partyTakeAll") != true ||
                loggedAllowedActions.Any(action => action?.GetValue<string>() == "partyScreenDone") != true ||
                !partyEventJson.Contains("PRIVATE_INQUIRY_BODY", StringComparison.Ordinal) ||
                partyEventJson.Contains("PRIVATE_INQUIRY_TOKEN", StringComparison.Ordinal) || partyEventJson.Contains("hidden-native-id", StringComparison.Ordinal) ||
                partyEventJson.Contains("Private model rationale", StringComparison.Ordinal))
                throw new AgentHostException("host-progress-trace-party-screen-context-self-test", "PartyState traces must retain current Inquiry labels, available action names and compact roster counts without tokens, free body/rationale text or troop IDs.");

            Environment.SetEnvironmentVariable("CHRONICLE_HARNESS_MODE", "agent-host-lifecycle-test");
            RecordDecision(request.RootElement, new ProviderDecisionResult("completed", "selftest-model", 1, 1, "stop", decision, "lifecycle/selftest-route"));
            if (File.ReadAllLines(path).Length != 3)
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
                ["objectiveSnapshot"] = new JsonObject
                {
                    ["gold"] = new JsonObject { ["current"] = 1000, ["target"] = 2000, ["met"] = false },
                    ["partySize"] = new JsonObject { ["current"] = 3, ["target"] = 5, ["met"] = false },
                    ["renown"] = new JsonObject { ["current"] = 20, ["target"] = 50, ["met"] = false },
                    ["companions"] = new JsonObject { ["current"] = 0, ["target"] = 1, ["met"] = false }
                },
                ["tavernEntryTransitionSummary"] = new JsonObject { ["waitCount"] = 3, ["confirmedCount"] = 1, ["pending"] = false, ["visitedTownMarked"] = true },
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
                ["trace"] = new JsonArray(
                    new JsonObject
                    {
                        ["selectedDecision"] = new JsonObject { ["action"] = "missionNavigateToAgent" },
                        ["nativeReceipt"] = new JsonObject
                        {
                            ["action"] = "missionNavigateToAgent",
                            ["targetHeroId"] = "never-copy-wanderer-id",
                            ["data"] = new JsonObject { ["targetDistance"] = 10.0, ["navState"] = "Moving" }
                        },
                        ["observation"] = new JsonObject
                        {
                            ["selectedWandererHeroId"] = "never-copy-wanderer-id",
                            ["currentSceneWandererCandidates"] = new JsonArray(new JsonObject { ["heroId"] = "never-copy-wanderer-id", ["name"] = "never-copy-wanderer-name", ["distance"] = 8.0 }),
                            ["nearbyInteractableWanderers"] = new JsonArray()
                        }
                    },
                    new JsonObject
                    {
                        ["selectedDecision"] = new JsonObject { ["action"] = "missionSceneAgents" },
                        ["nativeReceipt"] = new JsonObject { ["action"] = "missionSceneAgents" },
                        ["observation"] = new JsonObject
                        {
                            ["selectedWandererHeroId"] = "never-copy-wanderer-id",
                            ["currentSceneWandererCandidates"] = new JsonArray(new JsonObject { ["heroId"] = "never-copy-wanderer-id", ["name"] = "never-copy-wanderer-name", ["distance"] = 6.0 }),
                            ["nearbyInteractableWanderers"] = new JsonArray(new JsonObject { ["heroId"] = "never-copy-wanderer-id", ["name"] = "never-copy-wanderer-name", ["distance"] = 6.0, ["isInteractable"] = true })
                        }
                    },
                    new JsonObject
                    {
                        ["selectedDecision"] = new JsonObject { ["action"] = "missionInteract" },
                        ["nativeReceipt"] = new JsonObject
                        {
                            ["action"] = "missionInteract",
                            ["data"] = new JsonObject { ["targetHeroId"] = "never-copy-wanderer-id", ["conversationStarted"] = true }
                        },
                        ["observation"] = new JsonObject()
                    }),
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
            var objectiveLine = JsonNode.Parse(File.ReadAllLines(path)[3])!.AsObject();
            if (File.ReadAllLines(path).Length != 4 ||
                ReadString(objectiveLine, "event") != "objective-subflow-result" ||
                ReadString(objectiveLine, "objectiveId") != "partySize" ||
                ReadString(objectiveLine, "failureCode") != "provider-http-error" ||
                ReadInt(objectiveLine, "providerHttpStatus") != 502 ||
                ReadInt(objectiveLine["objectiveSnapshot"]?["partySize"] as JsonObject, "current") != 3 ||
                ReadInt(objectiveLine["objectiveSnapshot"]?["partySize"] as JsonObject, "target") != 5 ||
                ReadBoolean(objectiveLine["objectiveSnapshot"]?["partySize"] as JsonObject, "met") ||
                ReadInt(objectiveLine["recruitmentOfferSummary"] as JsonObject, "offerCount") != 3 ||
                ReadInt(objectiveLine["recruitmentOfferSummary"] as JsonObject, "availableOfferCount") != 2 ||
                ReadInt(objectiveLine["recruitmentOfferSummary"] as JsonObject, "affordableAvailableOfferCount") != 1 ||
                ReadInt(objectiveLine["recruitmentOfferSummary"] as JsonObject, "lowestAffordableCost") != 25 ||
                ReadInt(objectiveLine["companionNavigationSummary"] as JsonObject, "navigationAttemptCount") != 1 ||
                ReadDouble(objectiveLine["companionNavigationSummary"] as JsonObject, "navigationStartDistanceMin") != 10.0 ||
                ReadDouble(objectiveLine["companionNavigationSummary"] as JsonObject, "selectedTargetObservedDistanceMin") != 6.0 ||
                ReadInt(objectiveLine["companionNavigationSummary"] as JsonObject, "nearbyInteractableObservationCount") != 1 ||
                ReadInt(objectiveLine["companionNavigationSummary"] as JsonObject, "successfulConversationStartCount") != 1 ||
                ReadInt(objectiveLine["tavernEntryTransitionSummary"] as JsonObject, "waitCount", -1) != 3 ||
                ReadInt(objectiveLine["tavernEntryTransitionSummary"] as JsonObject, "confirmedCount", -1) != 1 ||
                ReadBoolean(objectiveLine["tavernEntryTransitionSummary"] as JsonObject, "pending") ||
                ReadString(objectiveLine["nativeStateBefore"] as JsonObject, "menuId") != "training_field_menu" ||
                ReadString(objectiveLine["nativeStateAfter"] as JsonObject, "menuId") is not null ||
                objectiveLine.ToJsonString().Contains("do not copy", StringComparison.Ordinal) ||
                objectiveLine.ToJsonString().Contains("never-copy", StringComparison.Ordinal) ||
                objectiveLine.ContainsKey("failure"))
                throw new AgentHostException("host-progress-trace-objective-subflow", "Harness diagnostics must record bounded failure codes and aggregate offer/navigation outcomes without copying free text or Native Hero/Troop IDs and names.");

            RecordBudgetReservationRejected(request.RootElement, "deepseek-flash", 900, 990, 256, 4.9, 0.2, 5);
            var budgetLine = JsonNode.Parse(File.ReadAllLines(path).Last()) as JsonObject;
            if (ReadString(budgetLine, "event") != "provider-budget-reservation-rejected" ||
                ReadInt(budgetLine, "estimatedInputTokens") != 900 ||
                Math.Abs((ReadDouble(budgetLine, "projectedReservedAfterCny") ?? -1) - 5.1) > 0.0000001 ||
                ReadBoolean(budgetLine, "nativeActionSent") || budgetLine?.ContainsKey("prompt") == true || budgetLine?.ContainsKey("apiKey") == true)
                throw new AgentHostException("host-progress-trace-budget-rejection", "Budget diagnostics must record the preflight cost arithmetic without logging prompt contents, credentials, or a Native action.");

            RecordProviderFailure(request.RootElement, "provider-http-error", 429, "api.deepseek.com", "required_tool_call", 2, 1500,
                "http-response-status", "local-listener", 360, 12000, "HttpRequestException",
                "127.0.0.1:7890", "cloudflare", "1.1 proxy", "req-123", "30", "json-error", "application/json", "server_error", "overloaded",
                providerFallbackAttempts: 2, providerFallbackTrail: "ovh/model=rate_limited; nvidia/model=upstream_502");
            var providerFailureLine = JsonNode.Parse(File.ReadAllLines(path).Last()) as JsonObject;
            if (ReadString(providerFailureLine, "event") != "provider-failure" ||
                ReadString(providerFailureLine, "failureCode") != "provider-http-error" ||
                ReadInt(providerFailureLine, "providerHttpStatus") != 429 ||
                ReadString(providerFailureLine, "providerRoute") != "api.deepseek.com" ||
                ReadInt(providerFailureLine, "providerRetryAttempts") != 2 ||
                ReadInt(providerFailureLine, "providerRetryWaitMilliseconds") != 1500 ||
                ReadString(providerFailureLine, "providerFailureStage") != "http-response-status" ||
                ReadString(providerFailureLine, "providerProxySelectionSource") != "local-listener" ||
                ReadString(providerFailureLine, "providerProxyEndpointHostPort") != "127.0.0.1:7890" ||
                ReadInt(providerFailureLine, "providerTimeoutSeconds") != 360 ||
                ReadInt(providerFailureLine, "providerRequestBodyBytes") != 12000 ||
                ReadString(providerFailureLine, "providerResponseServer") != "cloudflare" ||
                ReadString(providerFailureLine, "providerResponseVia") != "1.1 proxy" ||
                ReadString(providerFailureLine, "providerResponseRequestId") != "req-123" ||
                ReadString(providerFailureLine, "providerRetryAfter") != "30" ||
                ReadString(providerFailureLine, "providerErrorBodyKind") != "json-error" ||
                ReadString(providerFailureLine, "providerErrorContentType") != "application/json" ||
                ReadString(providerFailureLine, "providerErrorType") != "server_error" ||
                ReadString(providerFailureLine, "providerErrorCode") != "overloaded" ||
                ReadInt(providerFailureLine, "providerFallbackAttempts") != 2 ||
                ReadString(providerFailureLine, "providerFallbackTrail") != "ovh/model=rate_limited; nvidia/model=upstream_502" ||
                providerFailureLine?.ContainsKey("responseBody") == true || providerFailureLine?.ContainsKey("apiKey") == true)
                throw new AgentHostException("host-progress-trace-provider-failure", "Harness diagnostics must persist bounded HTTP status/retry metadata without response bodies or credentials.");

            RecordPassiveObservation("native-party-pursuit-passive-window", new JsonObject
            {
                ["targetPartyId"] = "bandit-test",
                ["pollCount"] = 4,
                ["elapsedSeconds"] = 3,
                ["stopReason"] = "encounter-opened",
                ["modelDecisionsDuringWindow"] = 0,
                ["clockActionsDuringWindow"] = 0,
                ["campaignDayBefore"] = 100.0,
                ["campaignDayAfter"] = 100.2,
                ["timeControlModeBefore"] = "StoppablePlay",
                ["timeControlModeAfter"] = "Stop"
            });
            var passiveObservationLine = JsonNode.Parse(File.ReadAllLines(path).Last()) as JsonObject;
            if (ReadString(passiveObservationLine, "event") != "native-party-pursuit-passive-window" ||
                ReadString(passiveObservationLine, "stopReason") != "encounter-opened" ||
                ReadString(passiveObservationLine, "targetPartyId") != "bandit-test" ||
                ReadInt(passiveObservationLine, "pollCount") != 4 ||
                ReadInt(passiveObservationLine, "modelDecisionsDuringWindow") != 0 ||
                ReadInt(passiveObservationLine, "clockActionsDuringWindow") != 0 ||
                passiveObservationLine?.ContainsKey("prompt") == true || passiveObservationLine?.ContainsKey("responseBody") == true)
                throw new AgentHostException("host-progress-trace-passive-observation", "Harness diagnostics must record bounded passive observation boundaries and counts without prompt or response-body content.");

            Environment.SetEnvironmentVariable("CHRONICLE_HARNESS_MODE", "normal");
            RecordDecision(request.RootElement, new ProviderDecisionResult("completed", "selftest-model", 1, 1, "stop", decision, "selftest/route"));
            if (File.ReadAllLines(path).Length != 7)
                throw new AgentHostException("host-progress-trace-self-test-mode-gate", "Progress tracing must be disabled outside Harness visual-capture/lifecycle modes.");
            return [
                new { scenario = "harness-progress-trace-records-current-modal-and-visible-buttons-without-one-use-token", passed = true },
                new { scenario = "harness-progress-trace-persists-native-decision-and-route-without-free-text-in-visual-capture-and-lifecycle-modes", passed = true },
                new { scenario = "provider-progress-trace-records-request-size-cache-cost-and-goal-scope-without-request-content", passed = true },
                new { scenario = "harness-progress-trace-reports-only-aggregate-affordable-recruitment-offer-counts", passed = true },
                new { scenario = "harness-progress-trace-reports-only-aggregate-companion-navigation-progress", passed = true },
                new { scenario = "harness-progress-trace-records-bounded-native-tavern-entry-transition-summary", passed = true },
                new { scenario = "harness-progress-trace-records-objective-subflow-termination-and-safe-native-state-summaries", passed = true },
                new { scenario = "harness-progress-trace-records-dynamic-journal-current-target-met-summary", passed = true },
                new { scenario = "harness-progress-trace-records-token-budget-rejection-arithmetic-without-prompt-or-key-material", passed = true },
                new { scenario = "harness-progress-trace-records-provider-http-status-and-retry-without-response-body-or-key", passed = true },
                new { scenario = "harness-progress-trace-records-native-passive-observation-boundaries-without-prompt-content", passed = true }
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

    private static JsonObject? BuildCompanionNavigationSummary(JsonArray? trace)
    {
        if (trace is null) return null;

        var navigationAttempts = 0;
        var sceneAgentReadCount = 0;
        var interactionAttemptCount = 0;
        var successfulConversationStartCount = 0;
        var sameTargetNavigationRepeatCount = 0;
        var nearbyInteractableObservationCount = 0;
        double? navigationStartDistanceMin = null;
        double? navigationStartDistanceMax = null;
        double? selectedTargetObservedDistanceMin = null;
        double? selectedTargetObservedDistanceMax = null;
        var priorNavigationHeroId = (string?)null;

        foreach (var step in trace.OfType<JsonObject>())
        {
            var receipt = step["nativeReceipt"] as JsonObject;
            var receiptAction = ReadString(receipt, "action");
            var observation = step["observation"] as JsonObject;
            var selectedHeroId = ReadString(observation, "selectedWandererHeroId");
            if (receiptAction == "missionSceneAgents") sceneAgentReadCount++;
            if (receiptAction == "missionNavigateToAgent")
            {
                navigationAttempts++;
                var targetHeroId = ReadString(receipt, "targetHeroId");
                if (targetHeroId is not null && targetHeroId == priorNavigationHeroId) sameTargetNavigationRepeatCount++;
                if (targetHeroId is not null) priorNavigationHeroId = targetHeroId;
                var startDistance = ReadDouble(receipt?["data"] as JsonObject, "targetDistance");
                if (startDistance is double observedStartDistance && double.IsFinite(observedStartDistance))
                {
                    navigationStartDistanceMin = navigationStartDistanceMin is null ? observedStartDistance : Math.Min(navigationStartDistanceMin.Value, observedStartDistance);
                    navigationStartDistanceMax = navigationStartDistanceMax is null ? observedStartDistance : Math.Max(navigationStartDistanceMax.Value, observedStartDistance);
                }
            }
            if (receiptAction == "missionInteract")
            {
                interactionAttemptCount++;
                if (ReadBoolean(receipt?["data"] as JsonObject, "conversationStarted")) successfulConversationStartCount++;
            }

            if (selectedHeroId is null) continue;
            if (observation?["currentSceneWandererCandidates"] is JsonArray candidates)
            {
                var target = candidates.OfType<JsonObject>().FirstOrDefault(candidate => ReadString(candidate, "heroId") == selectedHeroId);
                var distance = ReadDouble(target, "distance");
                if (distance is double observedDistance && double.IsFinite(observedDistance))
                {
                    selectedTargetObservedDistanceMin = selectedTargetObservedDistanceMin is null ? observedDistance : Math.Min(selectedTargetObservedDistanceMin.Value, observedDistance);
                    selectedTargetObservedDistanceMax = selectedTargetObservedDistanceMax is null ? observedDistance : Math.Max(selectedTargetObservedDistanceMax.Value, observedDistance);
                }
            }
            if (observation?["nearbyInteractableWanderers"] is JsonArray nearby &&
                nearby.OfType<JsonObject>().Any(agent => ReadString(agent, "heroId") == selectedHeroId && ReadBoolean(agent, "isInteractable")))
                nearbyInteractableObservationCount++;
        }

        if (navigationAttempts == 0 && sceneAgentReadCount == 0 && interactionAttemptCount == 0) return null;
        return new JsonObject
        {
            ["sceneAgentReadCount"] = sceneAgentReadCount,
            ["navigationAttemptCount"] = navigationAttempts,
            ["sameTargetNavigationRepeatCount"] = sameTargetNavigationRepeatCount,
            ["navigationStartDistanceMin"] = navigationStartDistanceMin,
            ["navigationStartDistanceMax"] = navigationStartDistanceMax,
            ["selectedTargetObservedDistanceMin"] = selectedTargetObservedDistanceMin,
            ["selectedTargetObservedDistanceMax"] = selectedTargetObservedDistanceMax,
            ["nearbyInteractableObservationCount"] = nearbyInteractableObservationCount,
            ["interactionAttemptCount"] = interactionAttemptCount,
            ["successfulConversationStartCount"] = successfulConversationStartCount
        };
    }

    private static JsonObject? BuildVillagersInNeedStartupSummary(JsonArray? trace)
    {
        var transitions = trace?.OfType<JsonObject>()
            .Where(step => ReadString(step, "kind") == "native-villagers-in-need-conversation-startup-settle")
            .ToArray() ?? Array.Empty<JsonObject>();
        if (transitions.Length == 0) return null;
        return new JsonObject
        {
            ["waitCount"] = transitions.Length,
            ["firstBefore"] = transitions[0]["before"]?.DeepClone(),
            ["lastAfter"] = transitions[^1]["after"]?.DeepClone(),
            ["lastBeforeTimeControlMode"] = Copy(transitions[^1], "beforeTimeControlMode"),
            ["lastAfterTimeControlMode"] = Copy(transitions[^1], "afterTimeControlMode")
        };
    }

    private static JsonObject? BuildObjectiveSnapshotSummary(JsonObject? objective)
    {
        if (objective is null) return null;
        var summary = new JsonObject();
        foreach (var name in new[] { "gold", "partySize", "renown", "companions" })
        {
            var value = objective[name] as JsonObject;
            if (value is null) continue;
            summary[name] = new JsonObject
            {
                ["current"] = Copy(value, "current"),
                ["target"] = Copy(value, "target"),
                ["met"] = Copy(value, "met")
            };
        }
        return summary;
    }

    private static JsonObject? BuildNativeProgressionContextSummary(JsonObject? context)
    {
        if (context is null) return null;
        var summary = new JsonObject();
        foreach (var name in new[] { "gameState", "menuId", "currentSettlementId", "clanTier", "clanRenown", "gold", "partyMembers", "partySizeLimit", "partyIsMoving", "encounterActive", "isCaptive" })
        {
            if (context.ContainsKey(name)) summary[name] = context[name]?.DeepClone();
        }
        return summary;
    }

    private static bool ReadBoolean(JsonObject? source, string name) =>
        source?[name] is JsonValue value && value.TryGetValue<bool>(out var result) && result;

    private static int? ReadInt(JsonObject? source, string name) =>
        source?[name] is JsonValue value && value.TryGetValue<int>(out var result) ? result : null;

    private static int ReadInt(JsonObject? source, string name, int fallback) => ReadInt(source, name) ?? fallback;

    private static double? ReadDouble(JsonObject? source, string name)
    {
        if (source?[name] is not JsonValue value) return null;
        if (value.TryGetValue<double>(out var doubleValue)) return doubleValue;
        if (value.TryGetValue<int>(out var intValue)) return intValue;
        if (value.TryGetValue<long>(out var longValue)) return longValue;
        return null;
    }

    private static string? ReadString(JsonElement source, string name) =>
        source.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;

    private static string? ReadString(JsonObject? source, string name) =>
        source?[name] is JsonValue value && value.TryGetValue<string>(out var text) ? text : null;

    private static string? Truncate(string? value, int max) =>
        string.IsNullOrEmpty(value) ? value : value.Length <= max ? value : value[..max];
}
