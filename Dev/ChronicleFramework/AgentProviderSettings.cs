using System;
using MCM.Abstractions.Attributes;
using MCM.Abstractions.Attributes.v2;
using MCM.Abstractions.Base.Global;
using TaleWorlds.Core;
using TaleWorlds.Localization;

namespace ChronicleFramework;

internal sealed class ChronicleAgentProviderSettings : AttributeGlobalSettings<ChronicleAgentProviderSettings>
{
    private string _ollamaBaseUrl = "http://127.0.0.1:11434/v1";
    private string _modelId = "qwen3.5:4b-q4_K_M";
    private string _campaignGoal = "前往一个当前可见且安全的聚落。";

    public override string Id => "ChronicleAgentSettings";
    public override string DisplayName => "Chronicle Framework Agent";
    public override string FolderName => "ChronicleFramework";
    public override string FormatType => "json";

    [SettingPropertyText("Ollama 服务地址", Order = 0, RequireRestart = false, HintText = "本地 Ollama 的 OpenAI-compatible API 地址；默认 http://127.0.0.1:11434/v1。")]
    [SettingPropertyGroup("本地模型", GroupOrder = 0)]
    public string OllamaBaseUrl
    {
        get => _ollamaBaseUrl;
        set
        {
            var next = value?.Trim() ?? string.Empty;
            if (string.Equals(_ollamaBaseUrl, next, StringComparison.Ordinal)) return;
            _ollamaBaseUrl = next;
            OnPropertyChanged();
        }
    }

    [SettingPropertyText("模型名称", Order = 1, RequireRestart = false, HintText = "填写 Ollama 中已安装的模型标识；当前开发基准是 qwen3.5:4b-q4_K_M。")]
    [SettingPropertyGroup("本地模型", GroupOrder = 0)]
    public string ModelId
    {
        get => _modelId;
        set
        {
            var next = value?.Trim() ?? string.Empty;
            if (string.Equals(_modelId, next, StringComparison.Ordinal)) return;
            _modelId = next;
            OnPropertyChanged();
        }
    }

    [SettingPropertyButton("检查本地配置", Order = 2, RequireRestart = false, HintText = "只检查地址格式与本机服务限制，不会发送网络请求；服务连通性将在启动 AI 时确认。", Content = "检查")]
    [SettingPropertyGroup("本地模型", GroupOrder = 0)]
    public Action ValidateLocalConfiguration
    {
        get => ShowConfigurationValidation;
        set { }
    }

    [SettingPropertyText("本次战役目标", Order = 0, RequireRestart = false, HintText = "用自然语言说明本次目标。Host只会提供已经接入并验证的动作；当前首个范围是地图安全移动。")]
    [SettingPropertyGroup("自主Agent", GroupOrder = 1)]
    public string CampaignGoal
    {
        get => _campaignGoal;
        set
        {
            var next = value?.Trim() ?? string.Empty;
            if (string.Equals(_campaignGoal, next, StringComparison.Ordinal)) return;
            _campaignGoal = next;
            OnPropertyChanged();
        }
    }

    [SettingPropertyButton("启动自主Agent", Order = 1, RequireRestart = false, HintText = "在当前Campaign地图启动本地Agent Host。", Content = "启动")]
    [SettingPropertyGroup("自主Agent", GroupOrder = 1)]
    public Action StartAgent
    {
        get => ChronicleAgentRuntimeController.RequestStart;
        set { }
    }

    [SettingPropertyButton("停止自主Agent", Order = 2, RequireRestart = false, HintText = "发送有界停止请求；不会结束Bannerlord或杀死其他程序。", Content = "停止")]
    [SettingPropertyGroup("自主Agent", GroupOrder = 1)]
    public Action StopAgent
    {
        get => ChronicleAgentRuntimeController.RequestStop;
        set { }
    }

    [SettingPropertyButton("查看Agent状态", Order = 3, RequireRestart = false, HintText = "查看自主Agent当前状态；状态变化时也会显示游戏内通知。", Content = "查看")]
    [SettingPropertyGroup("自主Agent", GroupOrder = 1)]
    public Action ViewAgentStatus
    {
        get => ChronicleAgentRuntimeController.RequestStatus;
        set { }
    }

    private void ShowConfigurationValidation()
    {
        var errorCode = AgentProviderConfigurationValidator.GetErrorCode(OllamaBaseUrl, ModelId);
        var message = errorCode switch
        {
            null => "本地模型配置格式有效。保存设置后，启动 AI 时会再检查 Ollama 服务是否可连接、模型是否可用。",
            "provider-profile-endpoint-invalid" => "地址无效：请输入不带账号密码、查询参数或片段的本机 HTTP(S) 服务地址。",
            "provider-profile-model-invalid" => "模型名称无效：请填写已安装模型的名称。",
            _ => "本地模型配置无效；请检查地址和模型名称。"
        };
        MBInformationManager.AddQuickInformation(new TextObject(message), 7000);
    }
}
