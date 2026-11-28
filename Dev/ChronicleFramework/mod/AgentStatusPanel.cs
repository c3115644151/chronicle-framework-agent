using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using Newtonsoft.Json.Linq;
using TaleWorlds.Engine.GauntletUI;
using TaleWorlds.GauntletUI;
using TaleWorlds.InputSystem;
using TaleWorlds.Library;
using TaleWorlds.ScreenSystem;

namespace ChronicleFramework;

// One always-available, in-game view of what the agent is doing. It reads the Host live-status snapshot so the
// player never has to leave the game or open a separate page to understand the agent.
internal static class ChronicleAgentStatusPanel
{
    private const string MovieName = "ChronicleAgentStatus";
    private const float PollIntervalSeconds = 0.25f;
    private static readonly InputKey[] OpenKeys = { InputKey.F7 };
    private const string HarnessShowVariable = "CHRONICLE_HARNESS_SHOW_STATUS_PANEL";
    private const string HarnessDetailVariable = "CHRONICLE_HARNESS_STATUS_DETAIL";
    private const string HarnessSnapshotPathVariable = "CHRONICLE_HARNESS_STATUS_SNAPSHOT_PATH";
    private static readonly InputKey[] DetailKeys = { InputKey.F6 };
    private static ChronicleAgentStatusVM _viewModel;
    private static GauntletLayer _gauntletLayer;
    private static GlobalLayer _globalLayer;
    private static float _pollElapsed;
    private static bool _openPressed;
    private static bool _detailPressed;
    private static bool _initializationFailedLogged;
    private static bool _harnessAutoShown;

    internal static bool IsOpen => _viewModel?.IsPanelOpen == true;
    internal static bool IsDetailed => _viewModel?.IsDetailed == true;

    internal static void Tick(float dt)
    {
        TryInitialize();
        if (!_harnessAutoShown && _viewModel is not null &&
            (Environment.GetEnvironmentVariable(HarnessShowVariable) == "1" ||
             Environment.GetEnvironmentVariable(HarnessDetailVariable) == "1"))
        {
            _harnessAutoShown = true;
            if (Environment.GetEnvironmentVariable(HarnessDetailVariable) == "1") _viewModel.IsDetailed = true;
            Show();
            ChronicleDiagnostics.Write("agent-status-panel-auto-shown|detail=" + _viewModel.IsDetailed);
        }
        PollKeys();
        if (_viewModel is null) return;
        _pollElapsed += dt;
        if (_pollElapsed < PollIntervalSeconds) return;
        _pollElapsed = 0f;
        RefreshFromSnapshot();
    }

    internal static void Show()
    {
        TryInitialize();
        if (_viewModel is null) return;
        _viewModel.IsPanelOpen = true;
        RefreshFromSnapshot();
    }

    internal static void Hide()
    {
        if (_viewModel is null) return;
        _viewModel.IsPanelOpen = false;
    }

    internal static void Release()
    {
        try
        {
            if (_globalLayer is not null) ScreenManager.RemoveGlobalLayer(_globalLayer);
        }
        catch (Exception exception)
        {
            ChronicleDiagnostics.Write("agent-status-panel-release-failed|type=" + exception.GetType().Name);
        }
        finally
        {
            _globalLayer = null;
            _gauntletLayer = null;
            _viewModel = null;
        }
    }

    private static void TryInitialize()
    {
        if (_viewModel is not null) return;
        if (ScreenManager.TopScreen is null) return;
        try
        {
            _viewModel = new ChronicleAgentStatusVM();
            _gauntletLayer = new GauntletLayer("ChronicleAgentStatus", 4100);
            _gauntletLayer.LoadMovie(MovieName, _viewModel);
            _globalLayer = new ChronicleAgentStatusGlobalLayer(_gauntletLayer!);
            ScreenManager.AddGlobalLayer(_globalLayer, isFocusable: false);
            ChronicleDiagnostics.Write("agent-status-panel-ready");
        }
        catch (Exception exception)
        {
            _viewModel = null;
            _gauntletLayer = null;
            _globalLayer = null;
            if (_initializationFailedLogged) return;
            _initializationFailedLogged = true;
            ChronicleDiagnostics.Write("agent-status-panel-unavailable|type=" + exception.GetType().Name + "|message=" + exception.Message);
        }
    }

    private static void PollKeys()
    {
        if (_viewModel is null) return;
        var openDown = IsAnyDown(OpenKeys);
        if (openDown && !_openPressed)
        {
            _viewModel.IsPanelOpen = !_viewModel.IsPanelOpen;
            if (_viewModel.IsPanelOpen) RefreshFromSnapshot();
        }
        _openPressed = openDown;
        var detailDown = IsAnyDown(DetailKeys);
        if (detailDown && !_detailPressed && _viewModel.IsPanelOpen)
        {
            _viewModel.IsDetailed = !_viewModel.IsDetailed;
            RefreshFromSnapshot();
        }
        _detailPressed = detailDown;
    }

    private static bool IsAnyDown(InputKey[] keys)
    {
        for (var index = 0; index < keys.Length; index++)
        {
            if (Input.IsKeyDown(keys[index])) return true;
        }
        return false;
    }

    private static void RefreshFromSnapshot()
    {
        if (_viewModel is null) return;
        try
        {
            var path = ChronicleLiveStatusPath();
            if (!File.Exists(path)) { _viewModel.Title = "AI 待机"; _viewModel.Body = BuildMissingBody(); return; }
            var snapshot = JObject.Parse(File.ReadAllText(path));
            _viewModel.Title = _viewModel.IsDetailed ? BuildDetailedTitle(snapshot) : DescribeRunState(Text(snapshot, "status"));
            _viewModel.Body = _viewModel.IsDetailed ? BuildDetailedBody(snapshot) : BuildNormalBody(snapshot);
        }
        catch (Exception exception)
        {
            _viewModel.Body = "状态快照暂时不可读：" + exception.GetType().Name;
        }
    }

    internal static string ChronicleLiveStatusPath()
    {
        var overridePath = Environment.GetEnvironmentVariable(HarnessSnapshotPathVariable);
        return string.IsNullOrWhiteSpace(overridePath) ? ChronicleAgentControlChannel.LiveStatusPath() : overridePath;
    }

    internal static string BuildMissingBody() =>
        string.Join(Environment.NewLine,
            "当前没有运行中的 Agent。F10 用于 AI 接管 / 交还控制。",
            "F10 启动 AI 并接管控制 · F7 显示或隐藏本面板 · F6 切换详细 / 简洁");

    internal static string BuildNormalBody(JObject root)
    {
        var progress = Object(root, "progress");
        var lines = new[]
        {
            "正在做：" + Fallback(Text(root, "phase")),
            "思考：" + Trim(Text(root, "thinking"), 120),
            "进度：金币 " + Number(progress, "gold") + " · 声望 " + Number(progress, "renown") + " · 队伍 " + Number(progress, "members") + " 人",
            "位置：" + Fallback(Text(progress, "gameState")) + MenuLabel(Text(progress, "menuId")),
            "目标：" + Trim(Text(progress, "focus"), 90),
            "F7 隐藏 · F6 详细模式 · F10 接管 / 交还 · F9 结束 Agent"
        };
        return string.Join(Environment.NewLine, lines);
    }

    internal static string BuildDetailedBody(JObject root)
    {
        var progress = Object(root, "progress");
        var budget = Object(root, "budget");
        var debug = Object(root, "debug");
        var lines = new List<string>
        {
            "阶段：" + Fallback(Text(root, "phase")),
            "决策：" + Trim(debug?["decision"]?.ToString(Newtonsoft.Json.Formatting.None), 240),
            "目标：" + Fallback(Text(root, "objectiveId")),
            "模型：" + Fallback(Text(root, "modelId")) + " · token " + Raw(budget, "promptTokens") + "+" + Raw(budget, "completionTokens") + " · 缓存命中 " + Raw(budget, "promptCacheHitTokens") + " / 未命中 " + Raw(budget, "promptCacheMissTokens"),
            "目录：" + Raw(budget, "allowedActionCount") + " 个动作 / " + Raw(budget, "allowedControlCount") + " 个控制",
            "请求：" + Raw(debug, "requestBytes") + " 字节 · 观察 " + Raw(debug, "observationBytes") + " 字节 · 提示 " + Raw(debug, "systemPromptBytes") + " 字节",
            "原生：" + Fallback(Text(progress, "gameState")) + MenuLabel(Text(progress, "menuId")) + " · 战役日 " + Number(progress, "campaignDay"),
            "可用动作：" + DescribeActions(debug?["allowedActions"]),
            "状态：" + Fallback(Text(root, "status")) + " · 保持原因：" + Fallback(Text(root, "holdReason")),
            "失败码：" + (Text(root, "failureCode") ?? "无") + AttentionSuffix(Text(root, "attention")),
            "运行：" + Fallback(Text(root, "runId")) + " · " + Fallback(Text(root, "utc")),
            "F6 返回简洁模式 · F7 隐藏 · F10 接管 / 交还 · F9 结束 Agent"
        };
        return string.Join(Environment.NewLine, lines);
    }


    private static string BuildDetailedTitle(JObject root) =>
        "调试视图 · " + Fallback(Text(root, "scope") ?? Text(root, "status"));

    private static string DescribeRunState(string? status) => status switch
    {
        "held" => "AI 已暂停 · 等待玩家交还控制",
        "resuming" => "AI 已恢复 · 继续决策",
        "provider-failure" => "AI 运行中 · 等待重试",
        _ => "AI 运行中 · 观察与决策"
    };

    private static string AttentionSuffix(string? attention) =>
        string.IsNullOrWhiteSpace(attention) || attention == "none" ? string.Empty : "（" + attention + "）";

    private static string DescribeActions(JToken? actions)
    {
        if (actions is not JArray array) return "—";
        var names = new List<string>();
        foreach (var action in array)
        {
            var name = action?["action"]?.Value<string>();
            if (!string.IsNullOrWhiteSpace(name)) names.Add(name!);
            if (names.Count >= 8) break;
        }
        return names.Count == 0 ? "（无）" : string.Join(", ", names);
    }

    private static string MenuLabel(string? menuId) => string.IsNullOrWhiteSpace(menuId) ? string.Empty : " / 菜单 " + menuId;

    private static JObject? Object(JObject? root, string name) => root?[name] as JObject;

    private static string? Text(JObject? root, string name) => root?[name]?.Value<string?>();

    private static string Fallback(string? value) => string.IsNullOrWhiteSpace(value) ? "—" : value!;

    private static string Number(JObject? root, string name)
    {
        var token = root?[name];
        if (token is null || (token.Type != JTokenType.Float && token.Type != JTokenType.Integer)) return "—";
        return token.Value<double>().ToString("0.#", CultureInfo.InvariantCulture);
    }

    private static string Raw(JObject? root, string name)
    {
        var token = root?[name];
        if (token is null || token.Type == JTokenType.Null) return "—";
        return token.ToString(Newtonsoft.Json.Formatting.None);
    }

    private static string Trim(string? value, int limit)
    {
        if (string.IsNullOrWhiteSpace(value)) return "—";
        var trimmed = value.Trim();
        return trimmed.Length <= limit ? trimmed : trimmed.Substring(0, limit) + "…";
    }
}

// Wraps the Gauntlet layer so the panel lives above game screens without taking focus.
internal sealed class ChronicleAgentStatusGlobalLayer : GlobalLayer
{
    internal ChronicleAgentStatusGlobalLayer(ScreenLayer layer)
    {
        Layer = layer;
    }
}

// The panel never takes focus or blocks input: it is a read-only window into the agent.
internal sealed class ChronicleAgentStatusVM : ViewModel
{
    private string _title = "AI 待机";
    private string _body = ChronicleAgentStatusPanel.BuildMissingBody();
    private bool _isDetailed;
    private bool _isPanelOpen;

    [DataSourceProperty]
    public string Title
    {
        get => _title;
        set
        {
            if (_title == value) return;
            _title = value;
            OnPropertyChanged(nameof(Title));
        }
    }

    [DataSourceProperty]
    public string Body
    {
        get => _body;
        set
        {
            if (_body == value) return;
            _body = value;
            OnPropertyChanged(nameof(Body));
        }
    }

    public bool IsDetailed
    {
        get => _isDetailed;
        set
        {
            if (_isDetailed == value) return;
            _isDetailed = value;
            OnPropertyChanged(nameof(Body));
        }
    }

    public bool IsPanelOpen
    {
        get => _isPanelOpen;
        set
        {
            if (_isPanelOpen == value) return;
            _isPanelOpen = value;
            OnPropertyChanged(nameof(IsPanelOpen));
            OnPropertyChanged(nameof(IsVisible));
        }
    }

    [DataSourceProperty]
    public bool IsVisible => _isPanelOpen;
}
