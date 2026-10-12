using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Text;
using System.Threading.Tasks;
using TaleWorlds.Core;
using TaleWorlds.Localization;

namespace ChronicleFramework;

internal static class ChronicleAgentRuntimeController
{
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
    private static DateTime _hostReadyUtc;
    private static string _runId = string.Empty;
    private static string _forcedFailureDetail = string.Empty;
    private static TaleWorlds.CampaignSystem.Campaign _ownedCampaign;

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

    internal static string StatusMessage => string.IsNullOrWhiteSpace(_detail) ? StatusText : StatusText + "：" + _detail;

    internal static void RequestStatus() => ShowMessage(StatusMessage);

    internal static void RequestStart()
    {
        if (_state is RuntimeState.Starting or RuntimeState.Running or RuntimeState.Stopping)
        {
            ShowMessage("自主Agent已在" + StatusText + "，不会重复启动进程。");
            return;
        }

        _startRequested = true;
        _stopRequested = false;
        _stopSignalSent = false;
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
            autoStopMilliseconds >= 250 && autoStopMilliseconds <= 30000 &&
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

    private static void StartOwnedHost()
    {
        if (_process != null && !_process.HasExited)
        {
            SetState(RuntimeState.Running, "Host进程仍在运行；不会重复启动");
            return;
        }

        var settings = ChronicleAgentProviderSettings.Instance;
        if (settings == null)
        {
            FailStart("无法读取MCM配置");
            return;
        }
        var goal = settings.CampaignGoal;
        var harnessGoal = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_AGENT_GOAL");
        if (IsLifecycleHarnessMode() && !string.IsNullOrWhiteSpace(harnessGoal)) goal = harnessGoal;
        if (string.IsNullOrWhiteSpace(goal) || goal.Trim().Length > 1000)
        {
            FailStart("请填写不超过1000字的本次战役目标");
            return;
        }
        var configError = AgentProviderConfigurationValidator.GetErrorCode(settings.OllamaBaseUrl, settings.ModelId);
        if (configError != null)
        {
            FailStart(configError == "provider-profile-endpoint-invalid" ? "本地服务地址无效" : "模型名称无效");
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
            var requestJson = "{\"runId\":\"" + _runId + "\",\"parentProcessId\":" + gameProcessId.ToString(CultureInfo.InvariantCulture) +
                              ",\"parentProcessStartTimeUtcTicks\":" + gameProcessStartTimeTicks.ToString(CultureInfo.InvariantCulture) +
                              ",\"nativeSessionId\":\"" + EscapeJson(nativeSessionId) + "\"" +
                              ",\"providerConfiguration\":{\"OllamaBaseUrl\":\"" + EscapeJson(settings.OllamaBaseUrl) +
                              "\",\"ModelId\":\"" + EscapeJson(settings.ModelId) + "\"}" +
                              ",\"goal\":\"" + EscapeJson(goal.Trim()) +
                              "\",\"maxDecisions\":30,\"maxElapsedSeconds\":600,\"allowedActionNames\":[\"mapSettlementTargets\",\"move\"]}";
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
        if (!string.IsNullOrWhiteSpace(_forcedFailureDetail))
            SetState(RuntimeState.Failed, _forcedFailureDetail);
        else if (output.IndexOf("\"reason\":\"native-action-result-ambiguous\"", StringComparison.Ordinal) >= 0)
            SetState(RuntimeState.Failed, "停止时原生动作结果不确定；未重放，请检查当前Campaign状态");
        else if (output.IndexOf("\"reason\":\"host-stop-requested\"", StringComparison.Ordinal) >= 0)
            SetState(RuntimeState.Stopped, "Host已按停止请求退出");
        else if (output.IndexOf("\"status\":\"completed\"", StringComparison.Ordinal) >= 0 && exitCode == 0)
            SetState(RuntimeState.Completed, "当前目标已由Native状态核实完成");
        else if (ContainsAny(output, errorOutput, "provider-model-unavailable", "not listed by the local model service"))
            SetState(RuntimeState.Failed, "本地服务中没有配置的模型");
        else if (ContainsAny(output, errorOutput, "provider-unavailable", "could not be reached"))
            SetState(RuntimeState.Failed, "本地模型服务不可连接");
        else if (ContainsAny(output, errorOutput, "provider-profile-missing", "profile-missing"))
            SetState(RuntimeState.Failed, "未找到已保存的MCM本地模型设置");
        else if (ContainsAny(output, errorOutput, "campaign-parent-exited", "campaign-parent-not-running", "campaign-parent-identity-mismatch", "native-parent-process-mismatch"))
            SetState(RuntimeState.Failed, "原Bannerlord战役进程已关闭或连接不匹配；Host已停止，未重放任何行动");
        else if (ContainsAny(output, errorOutput, "native-state-timeout", "native-command-timeout"))
            SetState(RuntimeState.Failed, "游戏内连接未能及时回应；行动结果可能不确定，未重放，请检查当前战役状态");
        else if (ContainsAny(output, errorOutput, "native-response-session-mismatch", "native-response-process-mismatch", "native-session-mismatch"))
            SetState(RuntimeState.Failed, "战役会话已变化；Host已停止，未重放行动");
        else if (ContainsAny(output, errorOutput, "host-already-running"))
            SetState(RuntimeState.Failed, "已有Host占用当前协议会话");
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
        }
    }

    private static async Task<string> PumpHostOutputAsync(StreamReader output)
    {
        var result = new StringBuilder();
        string line;
        while ((line = await output.ReadLineAsync().ConfigureAwait(false)) != null)
        {
            if (line.StartsWith(AgentHostReadyProtocol.Prefix, StringComparison.Ordinal))
            {
                HostReadySignals.Enqueue(line);
                continue;
            }
            result.AppendLine(line);
        }
        return result.ToString();
    }

    private static void TerminateOwnedHostAfterTimeout()
    {
        try
        {
            if (!IsOwnedLiveProcess()) return;
            _process.Kill();
            _process.WaitForExit(1000);
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
        try { ChronicleDiagnostics.Write("agent-host-state|state=" + state + "|detail=" + Shorten(_detail, 180)); }
        catch { }
        try { ShowMessage(StatusMessage); }
        catch { }
    }

    private static void ShowMessage(string message)
    {
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
