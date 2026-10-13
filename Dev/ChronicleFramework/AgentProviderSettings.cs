using System;
using MCM.Abstractions.Attributes;
using MCM.Abstractions.Attributes.v2;
using MCM.Abstractions.Base.Global;
using TaleWorlds.Core;
using TaleWorlds.Localization;

namespace ChronicleFramework;

internal sealed class ChronicleAgentProviderSettings : AttributeGlobalSettings<ChronicleAgentProviderSettings>
{
    private string _ollamaBaseUrl = "http://127.0.0.1:31415/v1";
    private string _modelId = "auto";
    private string _campaignGoal = "前往一个当前可见且安全的聚落。";

    public override string Id => "ChronicleAgentSettings";
    public override string DisplayName => "Chronicle Framework Agent";
    public override string FolderName => "ChronicleFramework";
    public override string FormatType => "json";

    [SettingPropertyText("FreeLLMAPI 网关地址", Order = 0, RequireRestart = false, HintText = "本机 FreeLLMAPI 的 OpenAI-compatible API 地址；默认 http://127.0.0.1:31415/v1。推理由已启用的免费外部服务商完成，不调用本地模型。")]
    [SettingPropertyGroup("模型服务", GroupOrder = 0)]
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

    [SettingPropertyText("模型名称/路由链", Order = 1, RequireRestart = false, HintText = "填写 FreeLLMAPI 模型 ID；auto 使用当前默认免费回退链。实际命中的服务商和模型写入测试收据。")]
    [SettingPropertyGroup("模型服务", GroupOrder = 0)]
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

    [SettingPropertyButton("检查网关配置", Order = 2, RequireRestart = false, HintText = "只检查地址和模型名称；启动 AI 时会用只读 /v1/models 检查模型是否可调用，不生成推理请求。", Content = "检查")]
    [SettingPropertyGroup("模型服务", GroupOrder = 0)]
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
        if (errorCode is null && (!Uri.TryCreate(OllamaBaseUrl, UriKind.Absolute, out var configuredUri) ||
            !configuredUri.IsLoopback || configuredUri.Port != 31415 || configuredUri.AbsolutePath.TrimEnd('/') != "/v1"))
            errorCode = "provider-freellmapi-endpoint-required";
        if (errorCode is null && Uri.TryCreate(OllamaBaseUrl, UriKind.Absolute, out configuredUri) &&
            string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("FREELLMAPI_API_KEY")) &&
            string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("CHRONICLE_LLM_API_KEY")))
            errorCode = "provider-api-key-missing";
        var message = errorCode switch
        {
            null => "FreeLLMAPI 网关配置格式有效。启动 AI 时会再检查可用模型目录。",
            "provider-profile-endpoint-invalid" => "地址无效：请输入不带账号密码、查询参数或片段的本机 HTTP(S) 服务地址。",
            "provider-freellmapi-endpoint-required" => "本项目实时模型测试仅允许本机 FreeLLMAPI 网关地址 http://127.0.0.1:31415/v1，不允许本地Ollama推理。",
            "provider-profile-model-invalid" => "模型名称无效：请填写 FreeLLMAPI 目录里的模型ID或路由链名称。",
            "provider-api-key-missing" => "FreeLLMAPI 客户端密钥未配置。请在启动 Bannerlord 前设置 FREELLMAPI_API_KEY 环境变量；密钥不会写入 Mod 设置文件或测试日志。",
            _ => "模型网关配置无效；请检查地址和模型名称。"
        };
        MBInformationManager.AddQuickInformation(new TextObject(message), 7000);
    }
}
