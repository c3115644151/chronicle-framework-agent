using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Net.Sockets;
using System.Text;
using System.Threading.Tasks;
using TaleWorlds.Core;
using TaleWorlds.Localization;

namespace ChronicleFramework;

internal static class ChronicleAgentRuntimeController
{
    private const string AgentHostUsageSignalPrefix = "CHRONICLE_AGENT_HOST_USAGE|";
    private static readonly object ProviderUsageLock = new();

    private enum RuntimeState
    {
        Stopped,
        Starting,
        Running,
        Stopping,
        Completed,
        Failed
    }

    private static RuntimeState _state;
    private static string _detail = string.Empty;
    private static string _hostExecutablePath = string.Empty;
    private static int _ownedProcessId;
    private static DateTime _ownedProcessStartTimeUtc;
    private static Process _process;
    private static StreamWriter _hostInput;
    private static Task<string> _hostOutput;
    private static Task<string> _hostError;
    private static readonly ConcurrentQueue<string> HostReadySignals = new();
    private static readonly Stopwatch StopWatch = new Stopwatch();
    private static bool _startRequested;
    private static bool _stopRequested;
    private static bool _stopSignalSent;
    private static bool _shutdownRequested;
    private static bool _hostExitObservedLogged;
    private static DateTime _hostReadyUtc;
    private static string _runId = string.Empty;
    private static string _lastRunId = string.Empty;
    private static string _forcedFailureDetail = string.Empty;
    private static int _providerDecisionCount;
    private static long _providerPromptTokens;
    private static long _providerCompletionTokens;
    private static long _providerCacheHitTokens;
    private static long _providerCacheMissTokens;
    private static double _providerEstimatedCostCny;
    private static double _providerReservedCostUpperCny;
    private static double? _providerRunCostLimitCny;
    private static bool _providerCostEstimateKnown = true;
    private static TaleWorlds.CampaignSystem.Campaign _ownedCampaign;
    private static bool _harnessStartProbeActive;
    private static bool _harnessDuplicateStartProbed;

    internal static bool ProbeHarnessStartRejections()
    {
        if (!IsLifecycleHarnessMode() || Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_AGENT_NO_MODEL") != "1") return true;
        var priorHostPath = Environment.GetEnvironmentVariable("CHRONICLE_AGENT_HOST_TEST_PATH");
        var cases = new[]
        {
            new KeyValuePair<string, Action<ChronicleAgentProviderSettings>>("empty-goal", settings => settings.CampaignGoal = string.Empty),
            new KeyValuePair<string, Action<ChronicleAgentProviderSettings>>("oversized-goal", settings => settings.CampaignGoal = new string('x', 1001)),
            new KeyValuePair<string, Action<ChronicleAgentProviderSettings>>("insecure-remote-endpoint", settings => settings.OllamaBaseUrl = "http://example.com/v1"),
            new KeyValuePair<string, Action<ChronicleAgentProviderSettings>>("empty-model", settings => settings.ModelId = string.Empty),
            new KeyValuePair<string, Action<ChronicleAgentProviderSettings>>("missing-host", settings => { })
        };
        _harnessStartProbeActive = true;
        try
        {
            foreach (var testCase in cases)
            {
                var settings = new ChronicleAgentProviderSettings
                {
                    OllamaBaseUrl = "http://127.0.0.1:11434/v1",
                    ModelId = "harness-lifecycle-no-model",
                    CampaignGoal = "Harness rejection fixture"
                };
                testCase.Value(settings);
                Environment.SetEnvironmentVariable("CHRONICLE_AGENT_HOST_TEST_PATH", testCase.Key == "missing-host"
                    ? "D:\\ChronicleFramework\\BuildCache\\Packages\\__missing_" + Guid.NewGuid().ToString("N") + "\\ChronicleAgentHost.exe"
                    : priorHostPath);
                SetState(RuntimeState.Starting, "Harness startup rejection probe");
                StartOwnedHost(settings);
                if (_state != RuntimeState.Failed || _process != null)
                {
                    if (_process != null) RequestStop();
                    ChronicleDiagnostics.Write("harness-agent-start-rejection-failed|case=" + testCase.Key);
                    return false;
                }
                ChronicleDiagnostics.Write("harness-agent-start-rejection|case=" + testCase.Key + "|state=Failed|hostCreated=False");
            }
            SetState(RuntimeState.Stopped, string.Empty);
            return true;
        }
        catch (Exception exception)
        {
            ChronicleDiagnostics.Write("harness-agent-start-rejection-failed|type=" + exception.GetType().Name);
            return false;
        }
        finally
        {
            Environment.SetEnvironmentVariable("CHRONICLE_AGENT_HOST_TEST_PATH", priorHostPath);
            _harnessStartProbeActive = false;
        }
    }

    internal static string StatusText => _state switch
    {
        RuntimeState.Stopped => "未启动",
        RuntimeState.Starting => "正在启动",
        RuntimeState.Running => "运行中",
        RuntimeState.Stopping => "正在停止",
        RuntimeState.Completed => "目标已完成",
        RuntimeState.Failed => "失败",
        _ => "状态未知"
    };

    internal static string StatusMessage
    {
        get
        {
            var message = string.IsNullOrWhiteSpace(_detail) ? StatusText : StatusText + "：" + _detail;
            var usage = BuildProviderUsageSummary();
            return string.IsNullOrWhiteSpace(usage) ? message : message + " | " + usage;
        }
    }
    internal static bool IsHostRunning => _state == RuntimeState.Running && _process != null && !_process.HasExited;
    internal static bool OwnsHost => _process != null;
    internal static bool ShouldOwnPlayerInput => _startRequested ||
        (_process != null && !_process.HasExited && _state is RuntimeState.Starting or RuntimeState.Running or RuntimeState.Stopping);

    internal static void RequestStatus()
    {
        var runId = string.IsNullOrWhiteSpace(_runId) ? _lastRunId : _runId;
        var message = StatusMessage;
        if (_providerDecisionCount > 0 && !string.IsNullOrWhiteSpace(runId))
        {
            message = StatusText + " | " + BuildProviderUsageSummary() + " | 日志: AgentRuns\\" + runId + ".jsonl";
        }
        ShowMessage(Shorten(message, 180));
    }

    internal static void RequestStart()
    {
        if (_state is RuntimeState.Starting or RuntimeState.Running or RuntimeState.Stopping)
        {
            ShowMessage("自主Agent已在" + StatusText + "，不会重复启动进程。");
            return;
        }

        if (!ChroniclePlayerInputOwnership.TryPrepareForAgentStart())
        {
            SetState(RuntimeState.Failed, "游戏内输入保护未就绪；Host未启动");
            return;
        }

        _startRequested = true;
        _stopRequested = false;
        _stopSignalSent = false;
        _hostExitObservedLogged = false;
        ResetProviderUsage();
        SetState(RuntimeState.Starting, "等待Campaign与Host初始化");
    }

    internal static void RequestStop()
    {
        if (_process == null || _process.HasExited)
        {
            _startRequested = false;
            _stopRequested = false;
            if (_state is RuntimeState.Stopped or RuntimeState.Completed or RuntimeState.Failed)
                ShowMessage("自主Agent当前没有运行中的Host。");
            else
                SetState(RuntimeState.Stopped, string.Empty);
            return;
        }

        _startRequested = false;
        _stopRequested = true;
        SetState(RuntimeState.Stopping, "正在等待Host安全退出");
    }

    internal static void Tick()
    {
        if (_shutdownRequested) return;
        if (_startRequested)
        {
            _startRequested = false;
            StartOwnedHost();
        }

        DrainHostReadySignals();
        if (_process == null) return;
        if (_process.HasExited)
        {
            RecordHostProcessExitObserved("process-exit-detected");
            CompleteExitedHost();
            return;
        }

        if (!_stopRequested && !ReferenceEquals(TaleWorlds.CampaignSystem.Campaign.Current, _ownedCampaign))
        {
            _forcedFailureDetail = "战役已关闭或切换；旧Host已请求停止，不会在新战役重放行动";
            RequestStop();
        }

        if (!_stopRequested && _state == RuntimeState.Running && IsLifecycleHarnessMode() &&
            int.TryParse(Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_AGENT_AUTO_STOP_AFTER_MS"), out var autoStopMilliseconds) &&
            autoStopMilliseconds >= 250 && autoStopMilliseconds <= 86400000 &&
            DateTime.UtcNow - _hostReadyUtc >= TimeSpan.FromMilliseconds(autoStopMilliseconds))
        {
            var stopButton = ChronicleAgentProviderSettings.Instance?.StopAgent;
            if (stopButton != null) stopButton();
            else RequestStop();
        }

        if (_stopRequested && !_stopSignalSent)
        {
            try
            {
                _hostInput.WriteLine("{\"control\":\"stop\"}");
                _hostInput.Flush();
                _stopSignalSent = true;
                StopWatch.Restart();
            }
            catch (Exception exception)
            {
                SetState(RuntimeState.Failed, "无法发送停止请求（" + exception.GetType().Name + "）");
                TerminateOwnedHostAfterTimeout();
                return;
            }
        }

        if (_stopSignalSent && StopWatch.Elapsed >= TimeSpan.FromSeconds(5))
            TerminateOwnedHostAfterTimeout();
    }

    internal static void StopForSubModuleUnload()
    {
        _shutdownRequested = true;
        _startRequested = false;
        if (_process == null) return;
        try
        {
            if (!_process.HasExited && !_stopSignalSent)
            {
                _hostInput.WriteLine("{\"control\":\"stop\"}");
                _hostInput.Flush();
                _stopSignalSent = true;
            }
            if (!_process.HasExited && !_process.WaitForExit(2000)) TerminateOwnedHostAfterTimeout();
        }
        catch
        {
            TerminateOwnedHostAfterTimeout();
        }
        finally
        {
            DisposeProcessHandles();
        }
    }

    // A failure anywhere in Host startup must surface in the panel and diagnostics. An escaping exception used to
    // leave the state at Starting with no Host and no explanation.
    private static void StartOwnedHost(ChronicleAgentProviderSettings harnessSettings = null)
    {
        try
        {
            StartOwnedHostCore(harnessSettings);
        }
        catch (Exception exception)
        {
            ChronicleDiagnostics.Write("agent-host-start-exception|type=" + exception.GetType().Name + "|message=" + Shorten(exception.Message, 160));
            FailStart("Host启动异常（" + exception.GetType().Name + "）");
        }
    }

    private static void StartOwnedHostCore(ChronicleAgentProviderSettings harnessSettings)
    {
        NormalizeCaseDuplicateEnvironmentNames();
        if (_process != null && !_process.HasExited)
        {
            SetState(RuntimeState.Running, "Host进程仍在运行；不会重复启动");
            return;
        }

        var settings = IsLifecycleHarnessMode() && harnessSettings != null ? harnessSettings : ChronicleAgentProviderSettings.Instance;
        if (settings == null)
        {
            FailStart("无法读取MCM配置");
            return;
        }
        var harnessProviderModel = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_AGENT_MODEL");
        if (string.IsNullOrWhiteSpace(harnessProviderModel)) harnessProviderModel = Environment.GetEnvironmentVariable("CHRONICLE_LLM_MODEL");
        var harnessProviderBaseUrl = Environment.GetEnvironmentVariable("CHRONICLE_LLM_BASE_URL");
        var harnessProviderOutputMode = Environment.GetEnvironmentVariable("CHRONICLE_LLM_OUTPUT_MODE");
        var harnessProviderRunCost = Environment.GetEnvironmentVariable("CHRONICLE_LLM_MAX_RUN_COST_CNY");
        var useHarnessProviderEnvironment = harnessSettings == null && IsLifecycleHarnessMode() &&
            (!string.IsNullOrWhiteSpace(harnessProviderModel) || !string.IsNullOrWhiteSpace(harnessProviderBaseUrl) ||
             !string.IsNullOrWhiteSpace(harnessProviderOutputMode) || !string.IsNullOrWhiteSpace(harnessProviderRunCost));
        if (useHarnessProviderEnvironment)
        {
            settings = new ChronicleAgentProviderSettings
            {
                OllamaBaseUrl = string.IsNullOrWhiteSpace(harnessProviderBaseUrl) ? settings.OllamaBaseUrl : harnessProviderBaseUrl.Trim(),
                ModelId = string.IsNullOrWhiteSpace(harnessProviderModel) ? settings.ModelId : harnessProviderModel.Trim(),
                OutputMode = string.IsNullOrWhiteSpace(harnessProviderOutputMode) ? settings.OutputMode : harnessProviderOutputMode.Trim(),
                DeepSeekRunCostLimitCny = string.IsNullOrWhiteSpace(harnessProviderRunCost) ? settings.DeepSeekRunCostLimitCny : harnessProviderRunCost.Trim(),
                CampaignGoal = settings.CampaignGoal
            };
        }
        if (harnessSettings == null && IsLifecycleHarnessMode())
        {
            var failureFixture = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_AGENT_FAILURE_CASE");
            if (failureFixture == "MissingModel" || failureFixture == "ServiceUnavailable")
            {
                // Disposable settings instance: never alter or save the registered MCM singleton.
                settings = new ChronicleAgentProviderSettings
                {
                    OllamaBaseUrl = failureFixture == "ServiceUnavailable" ? "http://127.0.0.1:11433/v1" : settings.OllamaBaseUrl,
                    ModelId = failureFixture == "MissingModel" ? "chronicle-harness-model-not-installed" : settings.ModelId,
                    CampaignGoal = settings.CampaignGoal
                };
                ChronicleDiagnostics.Write("harness-agent-provider-failure-case|case=" + failureFixture);
            }
        }
        var goal = settings.CampaignGoal;
        var harnessGoal = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_AGENT_GOAL");
        if (harnessSettings == null && IsLifecycleHarnessMode() && !string.IsNullOrWhiteSpace(harnessGoal)) goal = harnessGoal;
        if (string.IsNullOrWhiteSpace(goal) || goal.Trim().Length > 1000)
        {
            FailStart("请填写不超过1000字的本次战役目标");
            return;
        }
        var configError = AgentProviderConfigurationValidator.GetErrorCode(settings.OllamaBaseUrl, settings.ModelId);
        if (configError != null)
        {
            FailStart(configError == "provider-profile-endpoint-invalid" ? "模型网关地址无效" : "模型名称无效");
            return;
        }
        var noModelLifecycleProbe = IsLifecycleHarnessMode() && Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_AGENT_NO_MODEL") == "1";
        var providerIsRemote = Uri.TryCreate(settings.OllamaBaseUrl, UriKind.Absolute, out var providerUri) && !providerUri.IsLoopback;
        var configuredApiKey = ResolveApiKey(settings.OllamaBaseUrl);
        if (providerIsRemote && string.IsNullOrWhiteSpace(configuredApiKey) && !noModelLifecycleProbe)
        {
            FailStart("远程模型API密钥未配置；请设置CHRONICLE_LLM_API_KEY后重启游戏启动器");
            return;
        }
        if (TaleWorlds.CampaignSystem.Campaign.Current == null ||
            Game.Current?.GameStateManager?.ActiveState?.GetType().Name != "MapState")
        {
            FailStart("请先进入Campaign地图，再启动自主Agent");
            return;
        }

        string hostPath;
        try { hostPath = ResolveHostExecutablePath(); }
        catch (Exception exception)
        {
            FailStart("无法定位随包Host（" + exception.GetType().Name + "）");
            return;
        }
        if (!File.Exists(hostPath))
        {
            FailStart("随包Agent Host未找到；请确认发行包已安装完整");
            return;
        }

        var moduleRoot = ResolveModuleRoot();
        var campaignBehavior = TaleWorlds.CampaignSystem.Campaign.Current.GetCampaignBehavior<ChronicleCampaignBehavior>();
        if (campaignBehavior == null || !campaignBehavior.AgentProtocolReady)
        {
            FailStart("当前战役的Agent桥接尚未就绪");
            return;
        }
        var nativeSessionId = campaignBehavior.AgentRuntimeSessionId;
        using var gameProcess = Process.GetCurrentProcess();
        var gameProcessId = gameProcess.Id;
        var gameProcessStartTimeTicks = gameProcess.StartTime.ToUniversalTime().Ticks;
        _runId = "mcm-" + Guid.NewGuid().ToString("N");
        _lastRunId = _runId;
        var startInfo = new ProcessStartInfo
        {
            FileName = hostPath,
            Arguments = "--campaign-loop",
            WorkingDirectory = moduleRoot,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };
        ConfigureProviderProxyEnvironment(startInfo, providerUri);
        if (!string.IsNullOrWhiteSpace(configuredApiKey))
            SetChildEnvironment(startInfo, "CHRONICLE_LLM_API_KEY", configuredApiKey);
        foreach (var name in new[]
        {
            "CHRONICLE_LLM_MAX_TOKENS", "CHRONICLE_LLM_MAX_TOKEN_PARAMETER", "CHRONICLE_LLM_THINKING_MODE",
            "CHRONICLE_LLM_REASONING_EFFORT", "CHRONICLE_LLM_TIMEOUT_SECONDS", "CHRONICLE_LLM_MAX_RUN_COST_CNY"
        })
        {
            var value = Environment.GetEnvironmentVariable(name);
            if (string.IsNullOrWhiteSpace(value)) value = Environment.GetEnvironmentVariable(name, EnvironmentVariableTarget.User);
            if (!string.IsNullOrWhiteSpace(value)) SetChildEnvironment(startInfo, name, value);
        }

        try
        {
            var process = new Process { StartInfo = startInfo, EnableRaisingEvents = false };
            if (!process.Start())
            {
                process.Dispose();
                FailStart("Windows未能启动随包Host");
                return;
            }

            _process = process;
            _ownedProcessId = process.Id;
            _ownedCampaign = TaleWorlds.CampaignSystem.Campaign.Current;
            _ownedProcessStartTimeUtc = process.StartTime.ToUniversalTime();
            _hostReadyUtc = DateTime.MinValue;
            _hostExecutablePath = Path.GetFullPath(hostPath);
            _hostInput = process.StandardInput;
            while (HostReadySignals.TryDequeue(out _)) { }
            _hostOutput = PumpHostOutputAsync(process.StandardOutput);
            _hostError = process.StandardError.ReadToEndAsync();
            var useDisposableBattleFixtureProfile = string.Equals(Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE"), "visual-battle-fixture", StringComparison.Ordinal) &&
                !string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("CHRONICLE_AGENT_PROFILE_PATH"));
            var providerConfigurationSource = useHarnessProviderEnvironment ? "harness-environment-override" : "mcm-start-request";
            var providerConfiguration = useDisposableBattleFixtureProfile
                ? string.Empty
                : ",\"providerConfiguration\":{\"OllamaBaseUrl\":\"" + EscapeJson(settings.OllamaBaseUrl) +
                  "\",\"ModelId\":\"" + EscapeJson(settings.ModelId) + "\",\"OutputMode\":\"" + EscapeJson(settings.OutputMode) +
                  "\",\"DeepSeekRunCostLimitCny\":\"" + EscapeJson(settings.DeepSeekRunCostLimitCny) + "\"},\"providerConfigurationSource\":\"" +
                  EscapeJson(providerConfigurationSource) + "\"";
            var requestJson = "{\"runId\":\"" + _runId + "\",\"parentProcessId\":" + gameProcessId.ToString(CultureInfo.InvariantCulture) +
                              ",\"parentProcessStartTimeUtcTicks\":" + gameProcessStartTimeTicks.ToString(CultureInfo.InvariantCulture) +
                              ",\"nativeSessionId\":\"" + EscapeJson(nativeSessionId) + "\"" + providerConfiguration +
                              ",\"goal\":\"" + EscapeJson(goal.Trim()) +
                              "\",\"maxDecisions\":2048,\"maxElapsedSeconds\":86400,\"allowedActionNames\":[\"mapSettlementTargets\",\"move\",\"menuSelect\",\"talkToSettlementHero\",\"dialogueSelect\",\"dialogueContinue\",\"questDetails\",\"tradeOptions\",\"trade\",\"tradeConfirm\",\"tradeCancel\",\"tradeCancelChanges\",\"barterOptions\",\"barterAutoBalance\",\"barterOffer\",\"barterCancel\",\"inventoryOpen\",\"heroEquipmentOptions\",\"inventoryCancel\",\"incidentSelect\",\"partyUpgradeOptions\",\"upgradeTroop\",\"mapPartyTargets\",\"pursue\",\"battleSkip\",\"battleFinish\",\"partyTakeAll\",\"partyLootTransferOne\",\"sellPrisonerOne\",\"partyScreenCancel\",\"partyScreenDone\",\"inventoryTakeAll\",\"inventoryDone\",\"recruitOptions\",\"recruit\",\"recruitAll\",\"prisonerRecruitmentOptions\",\"recruitPrisoner\",\"missionSceneAgents\",\"missionNavigateToAgent\",\"missionInteract\",\"missionLeave\"]}";
            // The Harness owns the per-slice action set. Without an override the mod would send its
            // own full list, the Host would classify the request as the wider route, and a bounded
            // slice (town trade) could never be selected (contract 7.761).
            var allowedActionsOverride = Environment.GetEnvironmentVariable("CHRONICLE_AGENT_ALLOWED_ACTIONS");
            ChronicleDiagnostics.Write("agent-host-allowed-actions-override|present=" + (!string.IsNullOrWhiteSpace(allowedActionsOverride) ? "true" : "false") + "|length=" + (allowedActionsOverride?.Length ?? 0) + "|harnessMode=" + (Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE") ?? "none"));

            if (!string.IsNullOrWhiteSpace(allowedActionsOverride))
            {
                var setStart = requestJson.IndexOf("\"allowedActionNames\":[", StringComparison.Ordinal);
                var setEnd = setStart < 0 ? -1 : requestJson.IndexOf(']', setStart);
                var overrideNames = Array.FindAll(allowedActionsOverride.Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries), name => name.Trim().Length > 0);
                if (setStart >= 0 && setEnd > setStart && overrideNames.Length > 0)
                {
                    var overrideJson = string.Join(",", Array.ConvertAll(overrideNames, name => "\"" + name.Trim() + "\""));
                    requestJson = requestJson.Substring(0, setStart) + "\"allowedActionNames\":[" + overrideJson + requestJson.Substring(setEnd);
                }
            }
            _hostInput.WriteLine(requestJson);
            _hostInput.Flush();
            _stopSignalSent = false;
            _stopRequested = false;
            _forcedFailureDetail = string.Empty;
            SetState(RuntimeState.Starting, "Host进程已启动，正在核对版本与当前Campaign连接");
            ChronicleDiagnostics.Write("agent-host-process-started|pid=" + _ownedProcessId + "|path=" + _hostExecutablePath);
            ShowMessage("自主Agent正在连接当前Campaign；目标：" + Shorten(goal.Trim(), 90));
        }
        catch (Exception exception)
        {
            if (_process != null) TerminateOwnedHostAfterTimeout();
            FailStart("Host启动失败（" + exception.GetType().Name + "）");
        }
    }

    // Windows environment blocks are case-insensitive: adding "NO_PROXY" beside an inherited "no_proxy" throws when
    // .NET merges the child block. Keep exactly one entry per name by inheriting the parent value when it exists.
    // Windows treats environment names case-insensitively but ProcessStartInfo.EnvironmentVariables does not, so a
    // parent block holding both "NO_PROXY" and "no_proxy" makes every child start throw. Collapse the duplicates once.
    private static void NormalizeCaseDuplicateEnvironmentNames()
    {
        var kept = new System.Collections.Generic.Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var removed = new System.Collections.Generic.List<string>();
        foreach (System.Collections.DictionaryEntry entry in Environment.GetEnvironmentVariables())
        {
            if (entry.Key is not string key) continue;
            if (kept.TryGetValue(key, out var existing))
            {
                if (!string.Equals(existing, key, StringComparison.Ordinal))
                {
                    Environment.SetEnvironmentVariable(key, null);
                    removed.Add(key);
                }
                continue;
            }
            kept[key] = key;
        }
        if (removed.Count > 0)
            ChronicleDiagnostics.Write("agent-host-env-duplicates-collapsed|keys=" + string.Join(",", removed));
    }

    private static void SetChildEnvironment(ProcessStartInfo startInfo, string name, string value)
    {
        foreach (System.Collections.DictionaryEntry entry in Environment.GetEnvironmentVariables())
            if (entry.Key is string key && string.Equals(key, name, StringComparison.OrdinalIgnoreCase)) return;
        startInfo.EnvironmentVariables[name] = value;
    }

    private static void ConfigureProviderProxyEnvironment(ProcessStartInfo startInfo, Uri providerUri)
    {
        if (providerUri == null || providerUri.IsLoopback) return;
        var httpsProxy = ReadProxyEnvironment("HTTPS_PROXY");
        var httpProxy = ReadProxyEnvironment("HTTP_PROXY");
        var allProxy = ReadProxyEnvironment("ALL_PROXY");
        var noProxy = ReadProxyEnvironment("NO_PROXY");
        var localProxyAvailable = string.IsNullOrWhiteSpace(httpsProxy) && string.IsNullOrWhiteSpace(httpProxy) &&
                                 string.IsNullOrWhiteSpace(allProxy) && !ProviderProxySelection.IsNoProxyMatch(providerUri.Host, noProxy) &&
                                 IsLocalProxyListenerAvailable();
        var selectedProxy = ProviderProxySelection.SelectProxyUrl(providerUri, httpsProxy, httpProxy, allProxy, localProxyAvailable, noProxy);

        foreach (var name in new[] { "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY" })
        {
            var value = ReadProxyEnvironment(name);
            if (!string.IsNullOrWhiteSpace(value)) SetChildEnvironment(startInfo, name, value);
        }
        if (string.IsNullOrWhiteSpace(selectedProxy))
        {
            SetChildEnvironment(startInfo, "CHRONICLE_LLM_PROXY_SELECTION_SOURCE",
                ProviderProxySelection.IsNoProxyMatch(providerUri.Host, noProxy) ? "no-proxy-bypass" : "system-default");
            return;
        }

        // The Host is a separate process. Pass a user-configured proxy through,
        // or use the already-running local proxy as a process-only fallback.
        SetChildEnvironment(startInfo, "HTTPS_PROXY", selectedProxy);
        if (string.IsNullOrWhiteSpace(httpProxy)) SetChildEnvironment(startInfo, "HTTP_PROXY", selectedProxy);

        var source = !string.IsNullOrWhiteSpace(httpsProxy) ? "https-proxy-environment" :
            !string.IsNullOrWhiteSpace(httpProxy) ? "http-proxy-environment" :
            !string.IsNullOrWhiteSpace(allProxy) ? "all-proxy-environment" : "local-listener";
        startInfo.EnvironmentVariables["CHRONICLE_LLM_PROXY_SELECTION_SOURCE"] = source;
        if (Uri.TryCreate(selectedProxy, UriKind.Absolute, out var proxyUri))
            ChronicleDiagnostics.Write("agent-provider-proxy-selected|source=" + source + "|host=" + proxyUri.Host + "|port=" + proxyUri.Port.ToString(CultureInfo.InvariantCulture));
        else
            ChronicleDiagnostics.Write("agent-provider-proxy-selected|source=" + source + "|host=unparsed");
    }

    private static string ReadProxyEnvironment(string name)
    {
        var value = Environment.GetEnvironmentVariable(name);
        if (string.IsNullOrWhiteSpace(value)) value = Environment.GetEnvironmentVariable(name, EnvironmentVariableTarget.User);
        return value?.Trim() ?? string.Empty;
    }

    private static bool IsLocalProxyListenerAvailable()
    {
        using (var client = new TcpClient())
        {
            try
            {
                var connect = client.ConnectAsync("127.0.0.1", 7890);
                return connect.Wait(600) && client.Connected;
            }
            catch
            {
                return false;
            }
        }
    }

    private static string ResolveApiKey(string baseUrl)
    {
        var credential = AgentProviderConfigurationValidator.SelectApiKey(
            baseUrl,
            Environment.GetEnvironmentVariable("CHRONICLE_LLM_API_KEY"),
            Environment.GetEnvironmentVariable("CHRONICLE_LLM_API_KEY", EnvironmentVariableTarget.User),
            Environment.GetEnvironmentVariable("FREELLMAPI_API_KEY"),
            Environment.GetEnvironmentVariable("FREELLMAPI_API_KEY", EnvironmentVariableTarget.User));
        return credential.ApiKey?.Trim() ?? string.Empty;
    }

    private static string ResolveHostExecutablePath()
    {
        var harnessMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var harnessTemp = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (string.Equals(harnessMode, "agent-host-lifecycle-test", StringComparison.Ordinal) && !string.IsNullOrWhiteSpace(harnessTemp))
        {
            var testPath = Environment.GetEnvironmentVariable("CHRONICLE_AGENT_HOST_TEST_PATH");
            const string packageCacheRoot = "D:\\ChronicleFramework\\BuildCache\\Packages\\";
            if (!string.IsNullOrWhiteSpace(testPath))
            {
                var fullTestPath = Path.GetFullPath(testPath);
                if (!fullTestPath.StartsWith(packageCacheRoot, StringComparison.OrdinalIgnoreCase))
                    throw new InvalidOperationException("Lifecycle Harness Host path is outside the D: package cache.");
                return fullTestPath;
            }
            return Path.Combine(Path.GetFullPath(harnessTemp), "AgentHostPackage", "ChronicleAgentHost.exe");
        }
        return Path.Combine(ResolveModuleRoot(), "AgentHost", "ChronicleAgentHost.exe");
    }

    private static bool IsLifecycleHarnessMode() =>
        string.Equals(Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE"), "agent-host-lifecycle-test", StringComparison.Ordinal) &&
        !string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP"));

    private static string ResolveModuleRoot()
    {
        var assemblyPath = typeof(SubModule).Assembly.Location;
        var assemblyDirectory = Path.GetDirectoryName(assemblyPath);
        var binDirectory = string.IsNullOrWhiteSpace(assemblyDirectory) ? null : Directory.GetParent(assemblyDirectory);
        var moduleDirectory = binDirectory?.Parent;
        if (moduleDirectory == null || !File.Exists(Path.Combine(moduleDirectory.FullName, "SubModule.xml")))
            throw new DirectoryNotFoundException("Chronicle module root could not be resolved from the loaded assembly.");
        return Path.GetFullPath(moduleDirectory.FullName);
    }

    private static void CompleteExitedHost()
    {
        if ((_hostOutput != null && !_hostOutput.IsCompleted) || (_hostError != null && !_hostError.IsCompleted))
            return;
        var exitedProcessId = _ownedProcessId;
        var exitCode = -1;
        string output = string.Empty;
        string errorOutput = string.Empty;
        try
        {
            exitCode = _process.ExitCode;
            if (_hostOutput != null) output = _hostOutput.GetAwaiter().GetResult();
            if (_hostError != null) errorOutput = _hostError.GetAwaiter().GetResult();
        }
        catch { }
        var hostReceipt = AgentHostLifecycleReceipt.CaptureForHarness(output, errorOutput, exitCode);
        if (!string.IsNullOrWhiteSpace(_forcedFailureDetail))
            SetState(RuntimeState.Failed, _forcedFailureDetail);
        else if (output.IndexOf("\"reason\":\"native-action-result-ambiguous\"", StringComparison.Ordinal) >= 0)
            SetState(RuntimeState.Failed, "停止时原生动作结果不确定；未重放，请检查当前Campaign状态");
        else if (output.IndexOf("\"reason\":\"host-stop-requested\"", StringComparison.Ordinal) >= 0)
            SetState(RuntimeState.Stopped, "Host已按停止请求退出");
        else if (output.IndexOf("\"status\":\"completed\"", StringComparison.Ordinal) >= 0 && exitCode == 0)
            SetState(RuntimeState.Completed, "当前目标已由Native状态核实完成");
        else if (ContainsAny(output, errorOutput, "provider-api-key-missing"))
            SetState(RuntimeState.Failed, "远程模型API密钥未配置；请检查CHRONICLE_LLM_API_KEY环境变量");
        else if (ContainsAny(output, errorOutput, "provider-model-unavailable", "not listed by the local model service"))
            SetState(RuntimeState.Failed, "模型服务没有列出配置的模型ID");
        else if (ContainsAny(output, errorOutput, "provider-unavailable", "could not be reached"))
            SetState(RuntimeState.Failed, "模型服务不可连接；请检查服务地址和网络");
        else if (ContainsAny(output, errorOutput, "provider-timeout"))
            SetState(RuntimeState.Failed, "模型服务未按时回复；Host已停止");
        else if (ContainsAny(output, errorOutput, "provider-http-error", "provider-unreachable"))
            SetState(RuntimeState.Failed, "模型请求失败；请检查服务商额度、限流和上游状态");
        else if (ContainsAny(output, errorOutput, "provider-budget-exhausted"))
            SetState(RuntimeState.Failed, "本轮DeepSeek费用预留将超过单次预算；Host已停止发送模型请求");
        else if (ContainsAny(output, errorOutput, "campaign-goal-unsupported"))
            SetState(RuntimeState.Failed, "当前目标超出Agent已接入范围；未执行战役行动");
        else if (ContainsAny(output, errorOutput, "provider-profile-missing", "profile-missing"))
            SetState(RuntimeState.Failed, "未找到已保存的MCM模型网关设置");
        else if (ContainsAny(output, errorOutput, "campaign-parent-exited", "campaign-parent-not-running", "campaign-parent-identity-mismatch", "native-parent-process-mismatch"))
            SetState(RuntimeState.Failed, "原Bannerlord战役进程已关闭或连接不匹配；Host已停止，未重放任何行动");
        else if (ContainsAny(output, errorOutput, "native-state-timeout", "native-command-timeout"))
            SetState(RuntimeState.Failed, "游戏内连接未能及时回应；行动结果可能不确定，未重放，请检查当前战役状态");
        else if (ContainsAny(output, errorOutput, "native-response-session-mismatch", "native-response-process-mismatch", "native-session-mismatch"))
            SetState(RuntimeState.Failed, "战役会话已变化；Host已停止，未重放行动");
        else if (ContainsAny(output, errorOutput, "host-already-running"))
            SetState(RuntimeState.Failed, "已有Host占用当前协议会话");
        else if (hostReceipt != null && (!string.IsNullOrWhiteSpace(hostReceipt.FailureCode) || !string.IsNullOrWhiteSpace(hostReceipt.ErrorCode)))
        {
            var code = AgentHostLifecycleReceipt.SanitizeDiagnostic(
                !string.IsNullOrWhiteSpace(hostReceipt.FailureCode) ? hostReceipt.FailureCode : hostReceipt.ErrorCode);
            SetState(RuntimeState.Failed, "Host失败（" + code + "，退出码 " + exitCode + "）");
        }
        else if (_stopRequested && exitCode == 0)
            SetState(RuntimeState.Stopped, "Host已停止");
        else
            SetState(RuntimeState.Failed, "Host未能完成目标（退出码 " + exitCode + "）");
        try { ChronicleDiagnostics.Write("agent-host-process-exit|pid=" + exitedProcessId + "|exitCode=" + exitCode + "|state=" + _state); }
        catch { }
        DisposeProcessHandles();
    }

    private static void DrainHostReadySignals()
    {
        while (HostReadySignals.TryDequeue(out var signal))
        {
            if (_state != RuntimeState.Starting) continue;
            var validSignal = AgentHostReadyProtocol.TryParse(signal, out var nativeProcessId, out var runId, out var version);
            using var gameProcess = Process.GetCurrentProcess();
            if (!validSignal || nativeProcessId != gameProcess.Id ||
                !string.Equals(runId, _runId, StringComparison.Ordinal))
            {
                _forcedFailureDetail = "Agent Host版本、运行编号或Native战役进程握手不匹配；已请求安全停止";
                _stopRequested = true;
                SetState(RuntimeState.Failed, _forcedFailureDetail);
                continue;
            }

            SetState(RuntimeState.Running, "Host版本 " + Shorten(version, 32) + " 已确认并连接当前战役");
            _hostReadyUtc = DateTime.UtcNow;
            ShowMessage("自主Agent已连接当前Campaign并开始执行目标");
            ChronicleDiagnostics.Write("agent-host-ready|hostPid=" + _ownedProcessId + "|protocol=1|version=" + Shorten(version, 64));
            if (IsLifecycleHarnessMode() && !_harnessDuplicateStartProbed)
            {
                _harnessDuplicateStartProbed = true;
                var priorPid = _ownedProcessId;
                ChronicleAgentProviderSettings.Instance?.StartAgent?.Invoke();
                var unchanged = _ownedProcessId == priorPid && _state == RuntimeState.Running && !_startRequested;
                ChronicleDiagnostics.Write("harness-agent-duplicate-start|hostPid=" + priorPid + "|unchanged=" + unchanged);
                if (!unchanged)
                {
                    _forcedFailureDetail = "重复启动测试改变了Host身份；已请求停止";
                    RequestStop();
                }
            }
        }
    }

    private static async Task<string> PumpHostOutputAsync(StreamReader output)
    {
        var result = new StringBuilder();
        string line;
        while ((line = await output.ReadLineAsync().ConfigureAwait(false)) != null)
        {
            if (line.StartsWith(AgentHostUsageSignalPrefix, StringComparison.Ordinal))
            {
                UpdateProviderUsage(line);
                continue;
            }
            if (line.StartsWith(AgentHostReadyProtocol.Prefix, StringComparison.Ordinal))
            {
                HostReadySignals.Enqueue(line);
                continue;
            }
            result.AppendLine(line);
        }
        return result.ToString();
    }

    private static void ResetProviderUsage()
    {
        lock (ProviderUsageLock)
        {
            _providerDecisionCount = 0;
            _providerPromptTokens = 0;
            _providerCompletionTokens = 0;
            _providerCacheHitTokens = 0;
            _providerCacheMissTokens = 0;
            _providerEstimatedCostCny = 0;
            _providerReservedCostUpperCny = 0;
            _providerRunCostLimitCny = null;
            _providerCostEstimateKnown = true;
        }
    }

    private static void UpdateProviderUsage(string line)
    {
        try
        {
            var values = new Dictionary<string, string>(StringComparer.Ordinal);
            foreach (var field in line.Substring(AgentHostUsageSignalPrefix.Length).Split('|'))
            {
                var separator = field.IndexOf('=');
                if (separator <= 0) continue;
                values[field.Substring(0, separator)] = field.Substring(separator + 1);
            }
            lock (ProviderUsageLock)
            {
                _providerDecisionCount++;
                _providerPromptTokens += ReadUsageLong(values, "promptTokens");
                _providerCompletionTokens += ReadUsageLong(values, "completionTokens");
                _providerCacheHitTokens += ReadUsageLong(values, "cacheHitTokens");
                _providerCacheMissTokens += ReadUsageLong(values, "cacheMissTokens");
                if (TryReadUsageDouble(values, "estimatedCostCny", out var estimatedCost)) _providerEstimatedCostCny += estimatedCost;
                else _providerCostEstimateKnown = false;
                if (TryReadUsageDouble(values, "reservedCostUpperBoundCny", out var reserved)) _providerReservedCostUpperCny = reserved;
                if (TryReadUsageDouble(values, "runCostLimitCny", out var limit)) _providerRunCostLimitCny = limit;
            }
        }
        catch { }
    }

    private static long ReadUsageLong(IReadOnlyDictionary<string, string> values, string name) =>
        long.TryParse(values.TryGetValue(name, out var raw) ? raw : null, NumberStyles.Integer, CultureInfo.InvariantCulture, out var parsed) ? parsed : 0;

    private static bool TryReadUsageDouble(IReadOnlyDictionary<string, string> values, string name, out double value) =>
        double.TryParse(values.TryGetValue(name, out var raw) ? raw : null, NumberStyles.Float, CultureInfo.InvariantCulture, out value);

    private static string BuildProviderUsageSummary()
    {
        lock (ProviderUsageLock)
        {
            if (_providerDecisionCount == 0) return string.Empty;
            var cost = _providerCostEstimateKnown ? "估算¥" + _providerEstimatedCostCny.ToString("0.####", CultureInfo.InvariantCulture) : "费用估算未知";
            var reservation = _providerRunCostLimitCny.HasValue
                ? "/预留¥" + _providerReservedCostUpperCny.ToString("0.####", CultureInfo.InvariantCulture) + "（上限¥" + _providerRunCostLimitCny.Value.ToString("0.####", CultureInfo.InvariantCulture) + ")"
                : string.Empty;
            return "模型" + _providerDecisionCount.ToString(CultureInfo.InvariantCulture) + "次，Token " +
                   _providerPromptTokens.ToString("N0", CultureInfo.InvariantCulture) + "/" + _providerCompletionTokens.ToString("N0", CultureInfo.InvariantCulture) +
                   "，缓存命中/未命中 " + _providerCacheHitTokens.ToString("N0", CultureInfo.InvariantCulture) + "/" + _providerCacheMissTokens.ToString("N0", CultureInfo.InvariantCulture) +
                   "，" + cost + reservation;
        }
    }

    private static void TerminateOwnedHostAfterTimeout()
    {
        try
        {
            if (!IsOwnedLiveProcess())
            {
                if (_process != null && _process.HasExited) RecordHostProcessExitObserved("already-exited-at-stop-timeout");
                return;
            }
            _process.Kill();
            _process.WaitForExit(1000);
            if (_process.HasExited) RecordHostProcessExitObserved("terminated-after-stop-timeout");
            SetState(RuntimeState.Failed, "Host未在停止时限内退出；进程已结束，动作结果可能不确定且不会重放");
        }
        catch (Exception exception)
        {
            SetState(RuntimeState.Failed, "无法安全结束Host（" + exception.GetType().Name + "）");
        }
        finally
        {
            DisposeProcessHandles();
        }
    }

    private static void RecordHostProcessExitObserved(string reason)
    {
        if (_hostExitObservedLogged) return;
        _hostExitObservedLogged = true;
        var exitCode = -1;
        try { if (_process != null && _process.HasExited) exitCode = _process.ExitCode; }
        catch { }
        try { ChronicleDiagnostics.Write("agent-host-process-exit-observed|pid=" + _ownedProcessId + "|exitCode=" + exitCode + "|reason=" + reason); }
        catch { }
    }

    private static bool IsOwnedLiveProcess()
    {
        try
        {
            return _process != null && !_process.HasExited && _process.Id == _ownedProcessId &&
                   _process.StartTime.ToUniversalTime() == _ownedProcessStartTimeUtc &&
                   string.Equals(Path.GetFullPath(_process.StartInfo.FileName), _hostExecutablePath, StringComparison.OrdinalIgnoreCase);
        }
        catch { return false; }
    }

    private static void FailStart(string message)
    {
        _startRequested = false;
        SetState(RuntimeState.Failed, message);
    }

    private static void SetState(RuntimeState state, string detail)
    {
        if (_state == state && string.Equals(_detail, detail, StringComparison.Ordinal)) return;
        _state = state;
        _detail = detail ?? string.Empty;
        if (_harnessStartProbeActive) return;
        try { ChronicleDiagnostics.Write("agent-host-state|state=" + state + "|detail=" + Shorten(_detail, 180)); }
        catch { }
        try { ShowMessage(StatusMessage); }
        catch { }
    }

    private static void ShowMessage(string message)
    {
        if (_harnessStartProbeActive) return;
        if (Game.Current == null) return;
        MBInformationManager.AddQuickInformation(new TextObject(Shorten(message, 180)), 6000);
    }

    private static bool ContainsAny(string first, string second, params string[] values)
    {
        foreach (var value in values)
        {
            if ((!string.IsNullOrEmpty(first) && first.IndexOf(value, StringComparison.OrdinalIgnoreCase) >= 0) ||
                (!string.IsNullOrEmpty(second) && second.IndexOf(value, StringComparison.OrdinalIgnoreCase) >= 0)) return true;
        }
        return false;
    }

    private static string Shorten(string value, int maximumLength) =>
        string.IsNullOrWhiteSpace(value) || value.Length <= maximumLength ? value ?? string.Empty : value.Substring(0, maximumLength) + "…";

    private static string EscapeJson(string value)
    {
        var builder = new StringBuilder(value?.Length ?? 0);
        foreach (var character in value ?? string.Empty)
        {
            switch (character)
            {
                case '"': builder.Append("\\\""); break;
                case '\\': builder.Append("\\\\"); break;
                case '\b': builder.Append("\\b"); break;
                case '\f': builder.Append("\\f"); break;
                case '\n': builder.Append("\\n"); break;
                case '\r': builder.Append("\\r"); break;
                case '\t': builder.Append("\\t"); break;
                default:
                    if (character < 0x20) builder.Append("\\u").Append(((int)character).ToString("x4"));
                    else builder.Append(character);
                    break;
            }
        }
        return builder.ToString();
    }

    private static void DisposeProcessHandles()
    {
        try { _hostInput?.Dispose(); } catch { }
        try { _process?.Dispose(); } catch { }
        _hostInput = null;
        _process = null;
        _hostOutput = null;
        _hostError = null;
        _runId = string.Empty;
        _ownedCampaign = null;
        _hostReadyUtc = DateTime.MinValue;
        _ownedProcessId = 0;
        _ownedProcessStartTimeUtc = default;
        _hostExecutablePath = string.Empty;
        _stopSignalSent = false;
        StopWatch.Reset();
    }
}
