using System.Diagnostics;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal static class Program
{
    private static readonly JsonSerializerOptions OutputJsonOptions = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };

    private static async Task<int> Main(string[] args)
    {
        try
        {
            if (args.Length > 0 && string.Equals(args[0], "--native-map-movement-monitor-probe", StringComparison.Ordinal))
            {
                if (args.Length != 2 || !int.TryParse(args[1], out var movementMonitorWaitSeconds) || movementMonitorWaitSeconds is < 1 or > 10)
                    throw new AgentHostException("native-map-movement-probe-arguments-invalid", "The Harness-only Native map movement probe requires one wait interval from 1 to 10 seconds.");
                return await RunNativeMapMovementMonitorProbeAsync(movementMonitorWaitSeconds);
            }

            if (args.Length > 0 && string.Equals(args[0], "--native-battle-mission-loop-harness", StringComparison.Ordinal))
            {
                if (args.Length != 2 || !int.TryParse(args[1], out var nativeBattleProcessId) || nativeBattleProcessId <= 0)
                    throw new AgentHostException("native-battle-mission-harness-arguments-invalid", "The Harness-only Native Battle Mission loop requires one positive Bannerlord process id.");
                if (Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE") is not ("battle-fixture" or "solo-battle-fixture") ||
                    string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP")))
                    throw new AgentHostException("native-battle-mission-harness-not-authorized", "The real-Native Battle Mission loop probe is restricted to its disposable battle Harness phase.");
                return await RunNativeBattleMissionLoopHarnessAsync(nativeBattleProcessId);
            }

            if (args.Length == 1 && string.Equals(args[0], "--parent-process-self-test-probe", StringComparison.Ordinal))
            {
                await Task.Delay(TimeSpan.FromSeconds(1));
                return 0;
            }

            if (args.Length == 1 && string.Equals(args[0], "--provider-self-test", StringComparison.Ordinal))
            {
                var providerTests = await ProviderContractSelfTest.RunAsync();
                Console.Out.WriteLine(JsonSerializer.Serialize(providerTests, OutputJsonOptions));
                return 0;
            }

            if (args.Length == 1 && string.Equals(args[0], "--provider-health-only", StringComparison.Ordinal))
            {
                var requestJson = await Console.In.ReadToEndAsync();
                using var request = JsonDocument.Parse(requestJson);
                using var provider = OllamaNativeProvider.FromCampaignRequest(request.RootElement);
                await provider.CheckConfiguredModelAsync(CancellationToken.None);
                Console.Out.WriteLine(JsonSerializer.Serialize(new
                {
                    status = "ready",
                    providerHost = provider.ProviderHost,
                    modelId = provider.ModelId,
                    availableModelCount = provider.AvailableModelCount,
                    structuredOutputStrategy = provider.StructuredOutputStrategy,
                    proxySelectionSource = provider.ProxySelectionSource,
                    modelCalls = 0,
                    nativeCommands = 0
                }, OutputJsonOptions));
                return 0;
            }

            if (args.Length == 1 && string.Equals(args[0], "--campaign-action-catalog", StringComparison.Ordinal))
            {
                Console.Out.WriteLine(JsonSerializer.Serialize(new
                {
                    actions = AgentHostCampaignLoop.AllSupportedActions.OrderBy(action => action, StringComparer.Ordinal).ToArray()
                }, OutputJsonOptions));
                return 0;
            }

            if (args.Length == 1 && string.Equals(args[0], "--version", StringComparison.Ordinal))
            {
                Console.Out.WriteLine(JsonSerializer.Serialize(GetPackageHealth(), OutputJsonOptions));
                return 0;
            }

            if (args.Length == 1 && string.Equals(args[0], "--package-health", StringComparison.Ordinal))
            {
                Console.Out.WriteLine(JsonSerializer.Serialize(GetPackageHealth(), OutputJsonOptions));
                return 0;
            }

            var options = HostOptions.Parse(args);
            if (options.DecisionOnce)
            {
                var requestJson = await Console.In.ReadToEndAsync();
                var request = JsonNode.Parse(requestJson) as JsonObject
                    ?? throw new AgentHostException("provider-decision-once-request-invalid", "The one-shot provider request must be a JSON object.");
                using var provider = OllamaNativeProvider.FromEnvironment();
                var decision = await AgentHostDecisionCycle.DecideCampaignAsync(provider, request, CancellationToken.None);
                Console.Out.WriteLine(JsonSerializer.Serialize(decision, OutputJsonOptions));
                return 0;
            }

            var protocolRoot = GetProtocolRoot(options.ProtocolRoot);
            Directory.CreateDirectory(protocolRoot);
            Directory.CreateDirectory(Path.Combine(protocolRoot, "responses"));

            using var mutex = new Mutex(initiallyOwned: true, GetMutexName(protocolRoot), out var createdNew);
            if (!createdNew)
                throw new AgentHostException("host-already-running", "A Chronicle Agent Host already owns this protocol root.");

            if (options.ProtocolRejectionTest)
            {
                if (Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE") != "agent-host-protocol-test" ||
                    string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP")))
                    throw new AgentHostException("protocol-test-not-authorized", "The invalid-option protocol probe is restricted to its disposable Harness phase.");
                var rejection = await RunProtocolRejectionTestAsync(protocolRoot, CancellationToken.None);
                Console.Out.WriteLine(JsonSerializer.Serialize(rejection, OutputJsonOptions));
                return rejection["passed"]?.GetValue<bool>() == true ? 0 : 1;
            }

            if (options.CampaignLoop)
            {
                var requestJson = await Console.In.ReadLineAsync();
                if (string.IsNullOrWhiteSpace(requestJson))
                    throw new AgentHostException("campaign-loop-request-missing", "Agent Host received no Campaign goal request.");
                using var requestDocument = JsonDocument.Parse(requestJson);
                AgentHostRuntimeProgressLog.RecordRunStarted(requestDocument.RootElement);
                using var parentProcess = OpenBoundParentProcess(requestDocument.RootElement);
                using var parentMonitorCancellation = new CancellationTokenSource();
                using var stopToken = new CancellationTokenSource();
                using var stopInputToken = new CancellationTokenSource();
                var parentExited = false;
                var loopTask = AgentHostCampaignLoop.RunAsync(
                    requestDocument.RootElement,
                    protocolRoot,
                    stopToken.Token,
                    nativeProcessId => EmitReady(requestDocument.RootElement, nativeProcessId));
                // Console.In is a synchronized TextReader and may perform an async
                // line read synchronously. Keep an open stdin pipe from blocking
                // the owner that observes loop completion and parent exit.
                var stopTask = Task.Run(() => WaitForStopSignalAsync(Console.In, stopInputToken.Token));
                var parentExitTask = WaitForParentExitAsync(parentProcess, parentMonitorCancellation.Token);
                var completedTask = await Task.WhenAny(loopTask, stopTask, parentExitTask);
                if (completedTask == stopTask)
                {
                    if (await stopTask) stopToken.Cancel();
                    else stopInputToken.Cancel();
                    completedTask = await Task.WhenAny(loopTask, parentExitTask);
                }
                if (completedTask == parentExitTask && await parentExitTask)
                {
                    parentExited = true;
                    stopToken.Cancel();
                }
                else
                {
                    stopInputToken.Cancel();
                    parentMonitorCancellation.Cancel();
                }
                var loopResult = await loopTask;
                if (parentExited) MarkParentExited(loopResult);
                AgentHostRuntimeProgressLog.RecordRunSummary(requestDocument.RootElement, loopResult);
                Console.Out.WriteLine(JsonSerializer.Serialize(BuildCampaignLoopTerminalReceipt(loopResult), OutputJsonOptions));
                var terminationReason = (loopResult["termination"] as JsonObject)?["reason"]?.GetValue<string>();
                return loopResult["status"]?.GetValue<string>() == "completed" || terminationReason == "host-stop-requested" ? 0 : 1;
            }

            if (options.SupplyLoop)
            {
                var requestJson = await Console.In.ReadToEndAsync();
                using var requestDocument = JsonDocument.Parse(requestJson);
                var loopResult = await AgentHostSupplyLoop.RunAsync(requestDocument.RootElement, protocolRoot, CancellationToken.None);
                Console.Out.WriteLine(JsonSerializer.Serialize(loopResult, OutputJsonOptions));
                return loopResult["status"]?.GetValue<string>() == "completed" ? 0 : 1;
            }

            var result = await RequestCurrentStateAsync(protocolRoot, options.Timeout, CancellationToken.None);
            Console.Out.WriteLine(JsonSerializer.Serialize(result, OutputJsonOptions));
            return 0;
        }
        catch (AgentHostException exception)
        {
            Console.Error.WriteLine(JsonSerializer.Serialize(new
            {
                status = "failed",
                error = exception.Code,
                message = exception.Message,
                provider = BuildSafeProviderFailureDetails(exception)
            }, OutputJsonOptions));
            return 2;
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine(JsonSerializer.Serialize(new
            {
                status = "failed",
                error = "host-unexpected-error",
                exceptionType = exception.GetType().Name,
                providerSelfTestDetail = args.Contains("--provider-self-test", StringComparer.Ordinal)
                    ? exception.Message[..Math.Min(exception.Message.Length, 240)]
                    : null,
                providerSelfTestStack = args.Contains("--provider-self-test", StringComparer.Ordinal) && exception.StackTrace is string stack
                    ? stack[..Math.Min(stack.Length, 900)]
                    : null,
                nativeBattleMissionHarnessDetail = args.Contains("--native-battle-mission-loop-harness", StringComparer.Ordinal)
                    ? exception.Message[..Math.Min(exception.Message.Length, 500)]
                    : null,
                nativeBattleMissionHarnessStack = args.Contains("--native-battle-mission-loop-harness", StringComparer.Ordinal) && exception.StackTrace is string nativeStack
                    ? nativeStack[..Math.Min(nativeStack.Length, 1500)]
                    : null
            }, OutputJsonOptions));
            return 3;
        }
    }

    internal static JsonObject? BuildSafeProviderFailureDetails(AgentHostException exception)
    {
        if (exception.ProviderHttpStatus is null) return null;
        return new JsonObject
        {
            ["httpStatus"] = JsonValue.Create(exception.ProviderHttpStatus.Value),
            ["route"] = JsonValue.Create(exception.ProviderRoute),
            ["outputFormat"] = JsonValue.Create(exception.ProviderOutputFormat),
            ["failureStage"] = JsonValue.Create(exception.ProviderFailureStage),
            ["proxySelectionSource"] = JsonValue.Create(exception.ProviderProxySelectionSource),
            ["proxyEndpointHostPort"] = JsonValue.Create(exception.ProviderProxyEndpointHostPort),
            ["requestBodyBytes"] = JsonValue.Create(exception.ProviderRequestBodyBytes),
            ["responseServer"] = JsonValue.Create(exception.ProviderResponseServer),
            ["responseVia"] = JsonValue.Create(exception.ProviderResponseVia),
            ["responseRequestId"] = JsonValue.Create(exception.ProviderResponseRequestId),
            ["retryAfter"] = JsonValue.Create(exception.ProviderRetryAfter),
            ["errorBodyKind"] = JsonValue.Create(exception.ProviderErrorBodyKind),
            ["errorContentType"] = JsonValue.Create(exception.ProviderErrorContentType),
            ["errorType"] = JsonValue.Create(exception.ProviderErrorType),
            ["errorCode"] = JsonValue.Create(exception.ProviderErrorCode),
            ["errorParam"] = JsonValue.Create(exception.ProviderErrorParam),
            ["toolCallsPresent"] = JsonValue.Create(exception.ProviderToolCallsPresent),
            ["toolCallCount"] = JsonValue.Create(exception.ProviderToolCallCount),
            ["responseContentKind"] = JsonValue.Create(exception.ProviderResponseContentKind),
            ["responseContentCharacters"] = JsonValue.Create(exception.ProviderResponseContentCharacters),
            ["finishReason"] = JsonValue.Create(exception.ProviderFinishReason),
            ["responseModel"] = JsonValue.Create(exception.ProviderResponseModel),
            ["promptTokens"] = JsonValue.Create(exception.ProviderResponsePromptTokens),
            ["completionTokens"] = JsonValue.Create(exception.ProviderResponseCompletionTokens),
            ["fallbackAttempts"] = JsonValue.Create(exception.ProviderFallbackAttempts),
            ["fallbackTrail"] = JsonValue.Create(exception.ProviderFallbackTrail)
        };
    }

    internal static JsonObject BuildCampaignLoopTerminalReceipt(JsonObject result)
    {
        var sourceTermination = result["termination"] as JsonObject;
        return new JsonObject
        {
            ["status"] = result["status"]?.DeepClone(),
            ["providerModelId"] = result["providerModelId"]?.DeepClone(),
            ["providerConfigurationSource"] = result["providerConfigurationSource"]?.DeepClone(),
            ["decisionCount"] = result["decisions"]?.DeepClone(),
            ["actionsExecuted"] = result["actionsExecuted"]?.DeepClone(),
            ["promptTokens"] = result["promptTokens"]?.DeepClone(),
            ["completionTokens"] = result["completionTokens"]?.DeepClone(),
            ["providerPromptCacheHitTokens"] = result["providerPromptCacheHitTokens"]?.DeepClone(),
            ["providerPromptCacheMissTokens"] = result["providerPromptCacheMissTokens"]?.DeepClone(),
            ["providerActualCostEstimateCny"] = result["providerActualCostEstimateCny"]?.DeepClone(),
            ["providerReservedCostUpperCny"] = result["providerReservedCostUpperCny"]?.DeepClone(),
            ["failureCode"] = result["failureCode"]?.DeepClone(),
            ["failureExceptionType"] = result["failureExceptionType"]?.DeepClone(),
            ["failureLocation"] = result["failureLocation"]?.DeepClone(),
            ["termination"] = sourceTermination is null ? null : new JsonObject
            {
                ["reason"] = sourceTermination["reason"]?.DeepClone(),
                ["goalVerified"] = sourceTermination["goalVerified"]?.DeepClone(),
                ["completedByProvider"] = sourceTermination["completedByProvider"]?.DeepClone()
            }
        };
    }

    private static async Task<int> RunNativeMapMovementMonitorProbeAsync(int waitSeconds)
    {
        var harnessTemp = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE") != "agent-host-native-map-movement-monitor-probe" ||
            string.IsNullOrWhiteSpace(harnessTemp) || !Directory.Exists(harnessTemp))
            throw new AgentHostException("native-map-movement-probe-not-authorized", "The live Native movement probe is restricted to its explicit disposable Harness phase and temp directory.");

        var protocolRoot = NativeMailboxClient.GetDefaultProtocolRoot();
        var client = new NativeMailboxClient(protocolRoot, TimeSpan.FromSeconds(15));
        using var initialResponse = await client.ReadStateAsync(CancellationToken.None);
        var initial = CloneObject(initialResponse.RootElement);
        var state = initial["state"] as JsonObject;
        var context = state?["context"] as JsonObject;
        var location = state?["location"] as JsonObject;
        var party = state?["party"] as JsonObject;
        var targetSettlementId = NodeString(location, "targetSettlementId");
        var currentSettlementId = NodeString(location, "currentSettlementId");
        var timeControlMode = ReadString(initialResponse.RootElement, "timeControlMode") ?? NodeString(context, "timeControlMode");
        var activeEycQuest = AgentHostNativeMapMovementMonitor.HasActiveEycQuest(initial);
        var validMovementPrecondition = ReadString(initialResponse.RootElement, "status") == "completed" && state is not null &&
            NodeString(context, "gameState") == "MapState" && activeEycQuest &&
            !string.IsNullOrWhiteSpace(targetSettlementId) && !string.Equals(targetSettlementId, currentSettlementId, StringComparison.Ordinal) &&
            timeControlMode is not null and not "Stop" && NodeBoolean(party, "isMoving") &&
            string.IsNullOrWhiteSpace(NodeString(context, "menuId")) && !NodeBoolean(context, "escapeMenuOpen") &&
            !NodeBoolean(context, "inquiryOpen") && !NodeBoolean(context, "encounterActive") &&
            !NodeBoolean(context, "isWaitMenu") && !NodeBoolean(context, "isWaitActive");
        if (!validMovementPrecondition)
            throw new AgentHostException("native-map-movement-probe-precondition-failed", "The disposable live probe requires a free moving EYC Map with live time; status=" +
                ReadString(initialResponse.RootElement, "status") + "; gameState=" + NodeString(context, "gameState") + "; menuId=" + NodeString(context, "menuId") +
                "; timeControlMode=" + timeControlMode + "; currentSettlementId=" + currentSettlementId + "; targetSettlementId=" + targetSettlementId +
                "; isMoving=" + NodeBoolean(party, "isMoving") + "; encounter=" + NodeBoolean(context, "encounterActive") + "; activeEycQuest=" + activeEycQuest + ".");

        double? ReadCampaignDay(JsonObject native) => native["campaignDay"] is JsonValue day && day.TryGetValue<double>(out var value) ? value : null;
        var movement = await AgentHostNativeMapMovementMonitor.WaitAsync(
            client,
            client,
            initial,
            targetSettlementId,
            waitSeconds,
            monitorVisibleBandits: true,
            CancellationToken.None);
        var result = new JsonObject
        {
            ["passed"] = movement.MapPartyTargetPollCount > 0,
            ["status"] = "completed",
            ["probe"] = "native-map-movement-monitor",
            ["waitSeconds"] = waitSeconds,
            ["targetSettlementId"] = targetSettlementId,
            ["campaignDayBefore"] = ReadCampaignDay(initial),
            ["campaignDayAfter"] = ReadCampaignDay(movement.NativeReceipt),
            ["timeControlModeBefore"] = timeControlMode,
            ["timeControlModeAfter"] = NodeString(movement.NativeReceipt, "timeControlMode"),
            ["mapPartyTargetPollCount"] = movement.MapPartyTargetPollCount,
            ["visibleHostileBanditTargets"] = movement.VisibleHostileBanditTargets.DeepClone(),
            ["nativePauseReceipt"] = movement.PauseReceipt?.DeepClone(),
            ["interruptedByVisibleHostileBandit"] = movement.InterruptedByVisibleHostileBandit,
            ["freshPausedMapStillShowsBandit"] = movement.PauseReceipt is not null && AgentHostNativeMapMovementMonitor.IsPausedVisibleBanditMove(movement.NativeReceipt),
            ["finalNativeState"] = AgentHostHarnessProgressTrace.BuildNativeStateSummary(movement.NativeReceipt),
            ["modelCalls"] = 0
        };
        Console.Out.WriteLine(JsonSerializer.Serialize(result, OutputJsonOptions));
        return result["passed"]?.GetValue<bool>() == true ? 0 : 1;

        static string? NodeString(JsonObject? value, string property) =>
            value?[property] is JsonValue node && node.TryGetValue<string>(out var text) ? text : null;
        static bool NodeBoolean(JsonObject? value, string property) =>
            value?[property] is JsonValue node && node.TryGetValue<bool>(out var flag) && flag;
    }

    private static async Task<int> RunNativeBattleMissionLoopHarnessAsync(int processId)
    {
        try
        {
            var protocolRoot = NativeMailboxClient.GetDefaultProtocolRoot();
            using var mutex = new Mutex(initiallyOwned: true, GetMutexName(protocolRoot), out var createdNew);
            if (!createdNew) throw new AgentHostException("host-already-running", "A Chronicle Agent Host already owns this protocol root.");
            var client = new NativeMailboxClient(protocolRoot, TimeSpan.FromSeconds(12), expectedProcessId: processId);
            var result = await AgentHostBattleMissionLoop.RunAsync(client, client, processId, CancellationToken.None,
                pollInterval: TimeSpan.FromSeconds(1), missionEntryPollLimit: 20, missionCompletionPollLimit: 900, endScreenExitPollLimit: 20);
            var completed = result.Completed && result.MainHeroNativeAiControlMaintained;
            Console.Out.WriteLine(JsonSerializer.Serialize(new
            {
                status = completed ? "completed" : "unresolved",
                nativeResult = new
                {
                    completed = result.Completed,
                    termination = result.Termination,
                    finalNative = result.FinalNative,
                    delegationIssued = result.DelegationIssued,
                    delegatedFormationCount = result.DelegatedFormationCount,
                    mainHeroHealthAtStart = double.IsFinite(result.MainHeroHealthAtStart) ? (double?)result.MainHeroHealthAtStart : null,
                    mainHeroHealthAtEnd = double.IsFinite(result.MainHeroHealthAtEnd) ? (double?)result.MainHeroHealthAtEnd : null,
                    mainHeroNativeAiControlMaintained = result.MainHeroNativeAiControlMaintained,
                    campaignDayAtStart = double.IsFinite(result.CampaignDayAtStart) ? (double?)result.CampaignDayAtStart : null,
                    campaignDayAtEnd = double.IsFinite(result.CampaignDayAtEnd) ? (double?)result.CampaignDayAtEnd : null,
                    timeControlModeAtStart = result.TimeControlModeAtStart,
                    timeControlModeAtEnd = result.TimeControlModeAtEnd,
                    passivePollCount = result.PassivePollCount,
                    nativeDeploymentFinishIssued = result.NativeDeploymentFinishIssued,
                    nativeDeploymentPreconditionDiagnostic = result.NativeDeploymentPreconditionDiagnostic?.DeepClone(),
                    nativeDeploymentCompletedByNative = result.NativeDeploymentCompletedByNative,
                    nativeDeploymentAutoDeployIssued = result.NativeDeploymentAutoDeployIssued,
                    nativeReadyCallbackDispatchedByBridge = result.NativeReadyCallbackDispatchedByBridge,
                    nativeReadyHandlerExceptionType = result.NativeReadyHandlerExceptionType,
                    deploymentTransitionPollCount = result.DeploymentTransitionPollCount,
                    missionModeAtEntry = result.MissionModeAtEntry,
                    mainAgentRemovedDuringMission = result.MainAgentRemovedDuringMission,
                    mainHeroAutopilotIssued = result.MainHeroAutopilotIssued,
                    nativeMissionExitIssued = result.NativeMissionExitIssued
                }
            }, OutputJsonOptions));
            return completed ? 0 : 1;
        }
        catch (AgentHostException) { throw; }
        catch (Exception exception)
        {
            throw new AgentHostException("native-battle-mission-loop-harness-failed", $"{exception.GetType().Name}: {exception.Message}");
        }
    }

    internal static async Task<bool> WaitForStopSignalAsync(TextReader input, CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            string? line;
            try { line = await input.ReadLineAsync(cancellationToken); }
            catch (OperationCanceledException) { return false; }
            if (line is null) return false;
            try
            {
                using var document = JsonDocument.Parse(line);
                if (ReadString(document.RootElement, "control") == "stop")
                {
                    if (IsAuthorizedLifecycleNoModelMode() && Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_AGENT_IGNORE_STOP") == "1") continue;
                    return true;
                }
            }
            catch (JsonException) { }
        }
        return false;
    }

    internal static Process OpenBoundParentProcess(JsonElement request)
    {
        var processId = ReadInt(request, "parentProcessId");
        var startTimeTicks = request.TryGetProperty("parentProcessStartTimeUtcTicks", out var startTimeValue) && startTimeValue.TryGetInt64(out var ticks)
            ? ticks
            : 0L;
        if (processId <= 0 || processId == Environment.ProcessId || startTimeTicks <= 0)
            throw new AgentHostException("campaign-parent-identity-invalid", "The Campaign Host requires the launching Bannerlord process ID and start time.");

        Process parent;
        try { parent = Process.GetProcessById(processId); }
        catch (ArgumentException exception) { throw new AgentHostException("campaign-parent-not-running", "The launching Bannerlord process is no longer running.", exception); }
        catch (InvalidOperationException exception) { throw new AgentHostException("campaign-parent-not-running", "The launching Bannerlord process is no longer running.", exception); }

        try
        {
            if (parent.HasExited || parent.StartTime.ToUniversalTime().Ticks != startTimeTicks)
                throw new AgentHostException("campaign-parent-identity-mismatch", "The Host could not verify the original Bannerlord process identity.");
            return parent;
        }
        catch (AgentHostException)
        {
            parent.Dispose();
            throw;
        }
        catch (Exception exception)
        {
            parent.Dispose();
            throw new AgentHostException("campaign-parent-not-running", "The original Bannerlord process identity could not be verified.", exception);
        }
    }

    internal static async Task<IReadOnlyList<object>> RunParentProcessContractSelfTestsAsync()
    {
        var results = new List<object>();
        var hostPath = Environment.ProcessPath;
        if (string.IsNullOrWhiteSpace(hostPath) || !string.Equals(Path.GetFileName(hostPath), "ChronicleAgentHost.exe", StringComparison.OrdinalIgnoreCase))
        {
            results.Add(new { scenario = "campaign-parent-process-identity-tests-require-packaged-windows-host", passed = true, skipped = true });
            return results;
        }

        Process? probe = null;
        try
        {
            var startInfo = new ProcessStartInfo(hostPath) { UseShellExecute = false, CreateNoWindow = true };
            startInfo.ArgumentList.Add("--parent-process-self-test-probe");
            probe = Process.Start(startInfo) ?? throw new AgentHostException("campaign-parent-self-test-start-failed", "Could not start the disposable parent process probe.");
            var parentStartTicks = probe.StartTime.ToUniversalTime().Ticks;
            var requestJson = JsonSerializer.Serialize(new { parentProcessId = probe.Id, parentProcessStartTimeUtcTicks = parentStartTicks });
            using var request = JsonDocument.Parse(requestJson);
            using var boundParent = OpenBoundParentProcess(request.RootElement);
            if (boundParent.Id != probe.Id)
                throw new AgentHostException("campaign-parent-self-test-binding-failed", "The Host guard returned a different parent process.");
            results.Add(new { scenario = "campaign-host-binds-parent-pid-and-start-time", passed = true });

            var mismatchedJson = JsonSerializer.Serialize(new { parentProcessId = probe.Id, parentProcessStartTimeUtcTicks = parentStartTicks + 1 });
            using var mismatchedRequest = JsonDocument.Parse(mismatchedJson);
            try
            {
                using var unexpectedParent = OpenBoundParentProcess(mismatchedRequest.RootElement);
                throw new AgentHostException("campaign-parent-self-test-reuse-accepted", "The Host accepted a mismatched parent process start time.");
            }
            catch (AgentHostException exception) when (exception.Code == "campaign-parent-identity-mismatch") { }
            results.Add(new { scenario = "campaign-host-rejects-parent-pid-reuse", passed = true });

            using (var cancelledMonitor = new CancellationTokenSource())
            {
                cancelledMonitor.CancelAfter(TimeSpan.FromMilliseconds(100));
                if (await WaitForParentExitAsync(boundParent, cancelledMonitor.Token))
                    throw new AgentHostException("campaign-parent-self-test-cancel-failed", "Cancelling parent monitoring falsely reported that the parent exited.");
            }

            await probe.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(5));
            if (!await WaitForParentExitAsync(boundParent, CancellationToken.None))
                throw new AgentHostException("campaign-parent-self-test-exit-missed", "The Host did not observe the bound parent process exit.");
            results.Add(new { scenario = "campaign-host-detects-parent-process-exit", passed = true });
        }
        finally
        {
            if (probe is { HasExited: false })
            {
                try { probe.Kill(entireProcessTree: true); await probe.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(3)); }
                catch { }
            }
            probe?.Dispose();
        }

        await VerifyOpenInputDoesNotBlockTerminalResultAsync(hostPath);
        results.Add(new { scenario = "campaign-host-open-stdin-does-not-block-terminal-error", passed = true });
        return results;
    }

    private static async Task VerifyOpenInputDoesNotBlockTerminalResultAsync(string hostPath)
    {
        var root = Path.Combine(Path.GetTempPath(), "ChronicleHostInputProbe-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        using var owner = Process.GetCurrentProcess();
        using var child = new Process
        {
            StartInfo = new ProcessStartInfo(hostPath)
            {
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            }
        };
        child.StartInfo.ArgumentList.Add("--campaign-loop");
        child.StartInfo.ArgumentList.Add("--protocol-root");
        child.StartInfo.ArgumentList.Add(root);
        var childStarted = false;
        try
        {
            childStarted = child.Start();
            if (!childStarted) throw new AgentHostException("open-input-probe-start-failed", "Could not start the open-input lifecycle probe.");
            var outputTask = child.StandardOutput.ReadToEndAsync();
            var errorTask = child.StandardError.ReadToEndAsync();
            var request = new
            {
                parentProcessId = owner.Id,
                parentProcessStartTimeUtcTicks = owner.StartTime.ToUniversalTime().Ticks,
                nativeSessionId = "no-native-command-probe",
                goal = "Reject the invalid action catalog before contacting any service.",
                allowedActionNames = Array.Empty<string>(),
                providerConfiguration = new { OllamaBaseUrl = "http://127.0.0.1:11434/v1", ModelId = "unused-local-probe" }
            };
            await child.StandardInput.WriteLineAsync(JsonSerializer.Serialize(request));
            await child.StandardInput.FlushAsync();
            // Deliberately leave stdin open, as the game does during ordinary play.
            await child.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(5));
            var error = await errorTask;
            await outputTask;
            if (child.ExitCode != 2 || !error.Contains("campaign-loop-request-invalid", StringComparison.Ordinal))
            {
                var safeError = error.Trim();
                if (safeError.Length > 500) safeError = safeError[..500] + "...[truncated]";
                throw new AgentHostException("open-input-probe-result-invalid", $"An open input pipe prevented the expected pre-action failure result (exit={child.ExitCode}; stderr={safeError}).");
            }
        }
        finally
        {
            if (childStarted && !child.HasExited)
            {
                child.Kill(entireProcessTree: true);
                await child.WaitForExitAsync();
            }
            Directory.Delete(root, recursive: true);
        }
    }

    internal static IAgentHostDecisionProvider CreateCampaignDecisionProvider(JsonElement request)
    {
        if (IsAuthorizedLifecycleNoModelMode())
        {
            if (request.TryGetProperty("providerConfiguration", out var configuration))
                AgentProviderProfile.Parse(configuration, "mcm-start-request");
            return new LifecycleIdleDecisionProvider();
        }
        return OllamaNativeProvider.FromCampaignRequest(request);
    }

    private static bool IsAuthorizedLifecycleNoModelMode()
    {
        if (Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE") != "agent-host-lifecycle-test" ||
            Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_AGENT_NO_MODEL") != "1")
            return false;

        var repositoryRoot = Environment.GetEnvironmentVariable("CHRONICLE_REPOSITORY_ROOT");
        var evidenceTemp = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (string.IsNullOrWhiteSpace(repositoryRoot) || string.IsNullOrWhiteSpace(evidenceTemp)) return false;

        try
        {
            var fullTemp = Path.GetFullPath(evidenceTemp).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
            var testResultsRoots = new[]
            {
                Path.Combine(Path.GetFullPath(repositoryRoot), "TestResults"),
                Path.Combine(Path.GetFullPath(repositoryRoot), "Dev", "ChronicleFramework", "TestResults")
            };
            return testResultsRoots.Any(root => fullTemp.StartsWith(
                Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar,
                StringComparison.OrdinalIgnoreCase));
        }
        catch { return false; }
    }

    internal static async Task<bool> WaitForParentExitAsync(Process parent, CancellationToken cancellationToken)
    {
        try
        {
            if (parent.HasExited) return true;
            await parent.WaitForExitAsync(cancellationToken);
            return true;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { return false; }
        catch { return true; }
    }

    private static void EmitReady(JsonElement request, int nativeProcessId)
    {
        var version = typeof(Program).Assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion
            ?? typeof(Program).Assembly.GetName().Version?.ToString(3)
            ?? "unknown";
        Console.Out.WriteLine(AgentHostReadyProtocol.Format(nativeProcessId, ReadString(request, "runId") ?? string.Empty, version));
        Console.Out.Flush();
    }

    private static void MarkParentExited(JsonObject result)
    {
        if (result["termination"] is not JsonObject termination) return;
        result["parentProcessExited"] = true;
        if (string.Equals(termination["reason"]?.GetValue<string>(), "native-action-result-ambiguous", StringComparison.Ordinal)) return;
        termination["reason"] = "parent-process-exited";
        result["status"] = "failed";
        result["failureCode"] = "campaign-parent-exited";
        result["failure"] = "The launching Bannerlord process exited; the Host stopped without replaying any Native action.";
    }

    private static object GetPackageHealth()
    {
        return new
        {
            status = "ready",
            product = "ChronicleAgentHost",
            version = typeof(Program).Assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion
                ?? typeof(Program).Assembly.GetName().Version?.ToString(3)
                ?? "unknown",
            protocolVersion = 1,
            processArchitecture = RuntimeInformation.ProcessArchitecture.ToString(),
            is64BitProcess = Environment.Is64BitProcess,
            runtime = RuntimeInformation.FrameworkDescription
        };
    }

    private static async Task<HostStateResult> RequestCurrentStateAsync(
        string protocolRoot,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        var commandId = "host-state-" + Guid.NewGuid().ToString("N");
        var commandPath = Path.Combine(protocolRoot, "command.json");
        var responseRoot = Path.Combine(protocolRoot, "responses");
        var temporaryPath = commandPath + "." + commandId + ".tmp";
        var payload = JsonSerializer.Serialize(new { id = commandId, action = "state" });

        await WriteAtomicallyAsync(temporaryPath, payload, cancellationToken);
        try
        {
            try
            {
                File.Move(temporaryPath, commandPath, overwrite: false);
            }
            catch (IOException exception) when (File.Exists(commandPath))
            {
                throw new AgentHostException("protocol-command-busy", "The Native protocol mailbox already has an owner.", exception);
            }

            var deadline = Stopwatch.GetTimestamp() + (long)(timeout.TotalSeconds * Stopwatch.Frequency);
            while (Stopwatch.GetTimestamp() < deadline)
            {
                cancellationToken.ThrowIfCancellationRequested();
                foreach (var status in new[] { "completed", "rejected", "failed" })
                {
                    var responsePath = Path.Combine(responseRoot, commandId + "." + status + ".json");
                    if (!File.Exists(responsePath))
                        continue;

                    using var response = await ReadJsonAsync(responsePath, cancellationToken);
                    ValidateResponse(response.RootElement, commandId, status);
                    return BuildResult(response.RootElement);
                }

                await Task.Delay(TimeSpan.FromMilliseconds(100), cancellationToken);
            }

            throw new AgentHostException("native-state-timeout", $"The current Bannerlord client did not answer the read-only state request within {timeout.TotalSeconds:0} seconds.");
        }
        catch
        {
            TryRemoveOwnedUnclaimedCommand(commandPath, commandId);
            throw;
        }
        finally
        {
            TryDelete(temporaryPath);
        }
    }

    private static HostStateResult BuildResult(JsonElement response)
    {
        var state = response.GetProperty("state");
        var identity = state.GetProperty("identity");
        var party = state.GetProperty("party");
        var context = state.GetProperty("context");

        return new HostStateResult(
            response.GetProperty("commandId").GetString() ?? string.Empty,
            response.GetProperty("processId").GetInt32(),
            response.GetProperty("campaignDay").GetDouble(),
            response.GetProperty("dailyTickCount").GetInt32(),
            response.GetProperty("timeControlMode").GetString() ?? string.Empty,
            identity.GetProperty("heroId").GetString() ?? string.Empty,
            identity.TryGetProperty("clanId", out var clanId) ? clanId.GetString() ?? string.Empty : string.Empty,
            party.GetProperty("id").GetString() ?? string.Empty,
            party.GetProperty("members").GetInt32(),
            context.GetProperty("gameState").GetString() ?? string.Empty);
    }

    private static void ValidateResponse(JsonElement response, string commandId, string responseStatus)
    {
        if (ReadInt(response, "protocolVersion") != 1)
                throw new AgentHostException("protocol-version-mismatch", "The Native bridge returned an unsupported protocol version.");
        if (!string.Equals(ReadString(response, "commandId"), commandId, StringComparison.Ordinal))
            throw new AgentHostException("protocol-correlation-mismatch", "The Native bridge response did not match this request.");
        if (!string.Equals(ReadString(response, "action"), "state", StringComparison.Ordinal))
            throw new AgentHostException("protocol-action-mismatch", "The Native bridge answered with a different action.");
        if (!string.Equals(ReadString(response, "status"), responseStatus, StringComparison.Ordinal))
            throw new AgentHostException("protocol-status-mismatch", "The Native bridge response status did not match its response file.");
        if (responseStatus != "completed")
        {
            var error = ReadString(response, "error");
            throw new AgentHostException("native-state-rejected", string.IsNullOrWhiteSpace(error) ? "The Native bridge rejected the state request." : "The Native bridge rejected the state request: " + error);
        }
        if (ReadInt(response, "processId") <= 0)
            throw new AgentHostException("native-process-id-invalid", "The Native bridge returned an invalid game process ID.");
        if (!response.TryGetProperty("state", out var state) || state.ValueKind != JsonValueKind.Object)
            throw new AgentHostException("native-state-missing", "The Native bridge response did not contain a state object.");
        if (!state.TryGetProperty("identity", out var identity) || identity.ValueKind != JsonValueKind.Object ||
            string.IsNullOrWhiteSpace(ReadString(identity, "heroId")))
            throw new AgentHostException("native-player-identity-missing", "The Native state did not identify the current MainHero.");
        if (!state.TryGetProperty("party", out var party) || party.ValueKind != JsonValueKind.Object ||
            string.IsNullOrWhiteSpace(ReadString(party, "id")))
            throw new AgentHostException("native-main-party-missing", "The Native state did not identify the current MainParty.");
        if (!state.TryGetProperty("context", out var context) || context.ValueKind != JsonValueKind.Object)
            throw new AgentHostException("native-game-context-missing", "The Native state did not contain the current game context.");
    }

    private static async Task<JsonDocument> ReadJsonAsync(string path, CancellationToken cancellationToken)
    {
        for (var attempt = 0; attempt < 5; attempt++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            try
            {
                var text = await File.ReadAllTextAsync(path, cancellationToken);
                return JsonDocument.Parse(text);
            }
            catch (IOException) when (attempt < 4)
            {
                await Task.Delay(TimeSpan.FromMilliseconds(20), cancellationToken);
            }
            catch (JsonException) when (attempt < 4)
            {
                await Task.Delay(TimeSpan.FromMilliseconds(20), cancellationToken);
            }
        }

        throw new AgentHostException("native-response-unreadable", "The Native bridge response could not be read as complete JSON.");
    }

    private static async Task WriteAtomicallyAsync(string path, string contents, CancellationToken cancellationToken)
    {
        await using var stream = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough);
        var bytes = new UTF8Encoding(encoderShouldEmitUTF8Identifier: false).GetBytes(contents);
        await stream.WriteAsync(bytes, cancellationToken);
        await stream.FlushAsync(cancellationToken);
        stream.Flush(flushToDisk: true);
    }

    private static void TryRemoveOwnedUnclaimedCommand(string commandPath, string commandId)
    {
        try
        {
            if (!File.Exists(commandPath))
                return;
            using var document = JsonDocument.Parse(File.ReadAllText(commandPath));
            if (string.Equals(ReadString(document.RootElement, "id"), commandId, StringComparison.Ordinal))
                File.Delete(commandPath);
        }
        catch (IOException)
        {
            // The game's tick loop may be claiming the file at the same moment.
        }
        catch (JsonException)
        {
            // Never remove a mailbox file that cannot be proven to belong to this request.
        }
    }

    private static string GetProtocolRoot(string? requestedRoot)
    {
        var root = requestedRoot ?? Environment.GetEnvironmentVariable("CHRONICLE_AGENT_PROTOCOL_ROOT");
        if (string.IsNullOrWhiteSpace(root))
        {
            var documents = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
            if (string.IsNullOrWhiteSpace(documents))
                throw new AgentHostException("documents-path-unavailable", "The Windows Documents directory could not be resolved.");
            root = Path.Combine(documents, "Mount and Blade II Bannerlord", "AgentRuns", "ChronicleAgent");
        }

        return Path.GetFullPath(root);
    }

    private static async Task<JsonObject> RunProtocolRejectionTestAsync(string protocolRoot, CancellationToken cancellationToken)
    {
        var client = new NativeMailboxClient(protocolRoot, TimeSpan.FromSeconds(15));
        using var before = await client.ReadStateAsync(cancellationToken);
        var beforeState = CloneObject(before.RootElement);
        var invalidArguments = new JsonObject
        {
            ["menuId"] = "__chronicle_invalid_menu__",
            ["optionId"] = "__chronicle_invalid_option__"
        };
        using var rejected = await client.ExecuteSupplyActionAsync("menuSelect", invalidArguments, cancellationToken);
        var rejection = CloneObject(rejected.RootElement);
        using var after = await client.ReadStateAsync(cancellationToken);
        var afterState = CloneObject(after.RootElement);
        var errorText = rejection["error"]?.GetValue<string>() ?? string.Empty;
        var beforeFingerprint = BuildProtocolTestFingerprint(beforeState);
        var afterFingerprint = BuildProtocolTestFingerprint(afterState);
        return new JsonObject
        {
            ["passed"] = rejection["status"]?.GetValue<string>() == "rejected" &&
                errorText.Contains('\n') &&
                (beforeState["processId"]?.GetValue<int>() ?? -1) == (rejection["processId"]?.GetValue<int>() ?? -2) &&
                (beforeState["processId"]?.GetValue<int>() ?? -1) == (afterState["processId"]?.GetValue<int>() ?? -2) &&
                beforeFingerprint.ToJsonString() == afterFingerprint.ToJsonString(),
            ["action"] = "menuSelect",
            ["status"] = rejection["status"]?.GetValue<string>(),
            ["errorType"] = errorText.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries).FirstOrDefault()?.Split(':')[0],
            ["escapedControlCharactersParse"] = errorText.Contains('\n'),
            ["campaignStateUnchanged"] = beforeFingerprint.ToJsonString() == afterFingerprint.ToJsonString(),
            ["gameProcessId"] = beforeState["processId"]?.GetValue<int>() ?? -1
        };
    }

    private static JsonObject BuildProtocolTestFingerprint(JsonObject response)
    {
        var state = response["state"]!.AsObject();
        var identity = state["identity"]!.AsObject();
        var party = state["party"]!.AsObject();
        var economy = state["economy"]!.AsObject();
        var location = state["location"]!.AsObject();
        var context = state["context"]!.AsObject();
        return new JsonObject
        {
            ["heroId"] = identity["heroId"]?.DeepClone(),
            ["clanId"] = identity["clanId"]?.DeepClone(),
            ["partyId"] = party["id"]?.DeepClone(),
            ["members"] = party["members"]?.DeepClone(),
            ["gold"] = economy["gold"]?.DeepClone(),
            ["food"] = party["food"]?.DeepClone(),
            ["foodInventory"] = party["foodInventory"]?.DeepClone(),
            ["settlementId"] = location["currentSettlementId"]?.DeepClone(),
            ["menuId"] = context["menuId"]?.DeepClone(),
            ["timeControlMode"] = context["timeControlMode"]?.DeepClone()
        };
    }

    private static JsonObject CloneObject(JsonElement value) => JsonNode.Parse(value.GetRawText())!.AsObject();

    private static string GetMutexName(string protocolRoot)
    {
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(protocolRoot.ToUpperInvariant())));
        return "Local\\ChronicleAgentHost_" + hash[..24];
    }

    private static string? ReadString(JsonElement element, string name) =>
        element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;

    private static int ReadInt(JsonElement element, string name) =>
        element.TryGetProperty(name, out var value) && value.TryGetInt32(out var result) ? result : 0;

    private static void TryDelete(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); }
        catch (IOException) { }
    }

    private sealed record HostStateResult(
        string CommandId,
        int BannerlordProcessId,
        double CampaignDay,
        int DailyTickCount,
        string TimeControlMode,
        string MainHeroId,
        string PlayerClanId,
        string MainPartyId,
        int MainPartyMembers,
        string GameState);

    private sealed class LifecycleIdleDecisionProvider : IAgentHostDecisionProvider
    {
        public string ModelId => "harness-lifecycle-idle-provider";
        public string ConfigurationSource => "harness-only-no-model-lifecycle-test";

        public Task CheckConfiguredModelAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            return Task.CompletedTask;
        }

        public async Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken)
        {
            await Task.Delay(Timeout.Infinite, cancellationToken);
            throw new OperationCanceledException(cancellationToken);
        }

        public void Dispose() { }
    }

    private sealed record HostOptions(string? ProtocolRoot, TimeSpan Timeout, bool DecisionOnce, bool CampaignLoop, bool SupplyLoop, bool ProtocolRejectionTest)
    {
        internal static HostOptions Parse(string[] args)
        {
            string? root = null;
            var timeoutSeconds = 15;
            var decisionOnce = false;
            var campaignLoop = false;
            var supplyLoop = false;
            var protocolRejectionTest = false;
            for (var index = 0; index < args.Length; index++)
            {
                switch (args[index])
                {
                    case "--protocol-root" when index + 1 < args.Length:
                        root = args[++index];
                        break;
                    case "--timeout-seconds" when index + 1 < args.Length && int.TryParse(args[index + 1], out var parsedTimeout):
                        timeoutSeconds = parsedTimeout;
                        index++;
                        break;
                    case "--state-once":
                        break;
                    case "--decision-once":
                        decisionOnce = true;
                        break;
                    case "--campaign-loop":
                        campaignLoop = true;
                        break;
                    case "--supply-loop":
                        supplyLoop = true;
                        break;
                    case "--protocol-rejection-test":
                        protocolRejectionTest = true;
                        break;
                    default:
                        throw new AgentHostException("host-arguments-invalid", "Agent Host arguments were not recognized.");
                }
            }

            if (timeoutSeconds is < 1 or > 300)
                throw new AgentHostException("host-timeout-invalid", "Host timeout must be from 1 to 300 seconds.");
            if ((decisionOnce ? 1 : 0) + (campaignLoop ? 1 : 0) + (supplyLoop ? 1 : 0) + (protocolRejectionTest ? 1 : 0) > 1)
                throw new AgentHostException("host-mode-conflict", "Select one Host execution mode.");
            return new HostOptions(root, TimeSpan.FromSeconds(timeoutSeconds), decisionOnce, campaignLoop, supplyLoop, protocolRejectionTest);
        }
    }
}
