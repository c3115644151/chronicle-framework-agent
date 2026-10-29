using System;
using MCM.Abstractions.Attributes;
using MCM.Abstractions.Attributes.v2;
using MCM.Abstractions.Base.Global;
using TaleWorlds.Core;
using TaleWorlds.Localization;

namespace ChronicleFramework;

internal sealed class ChronicleAgentProviderSettings : AttributeGlobalSettings<ChronicleAgentProviderSettings>
{
    private string _ollamaBaseUrl = "https://api.deepseek.com/v1";
    private string _modelId = "deepseek-flash";
    private string _outputMode = "auto";
    private string _deepSeekRunCostLimitCny = "5";
    private string _campaignGoal = "前往一个当前可见且安全的聚落。";

    public override string Id => "ChronicleAgentSettings";
    public override string DisplayName => "Chronicle Framework Agent";
    public override string FolderName => "ChronicleFramework";
    public override string FormatType => "json";

    [SettingPropertyText("OpenAI 兼容服务地址", Order = 0, RequireRestart = false, HintText = "填写兼容 OpenAI Chat Completions 的服务根地址，例如 https://api.deepseek.com/v1 或本机 FreeLLMAPI 地址。远程地址必须使用 HTTPS。")]
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

    [SettingPropertyText("模型 ID", Order = 1, RequireRestart = false, HintText = "填写服务商提供的模型标识，例如 deepseek-flash；实际请求模型与用量会写入本地运行收据。")]
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

    [SettingPropertyText("结构化输出模式", Order = 2, RequireRestart = false, HintText = "auto 自动选择；json_schema、json_object、required_tool_call 可按服务商能力显式指定。模型输出最终仍由 Host 按当前原生动作目录校验。")]
    [SettingPropertyGroup("模型服务", GroupOrder = 0)]
    public string OutputMode
    {
        get => _outputMode;
        set
        {
            var next = value?.Trim() ?? string.Empty;
            if (string.Equals(_outputMode, next, StringComparison.Ordinal)) return;
            _outputMode = next;
            OnPropertyChanged();
        }
    }

    [SettingPropertyText("DeepSeek 单次运行预算（CNY）", Order = 3, RequireRestart = false, HintText = "仅 DeepSeek 使用；按官方BPE tokenizer估计聊天文本和结构化工具说明，加15%余量与256 token服务开销，按峰时缓存未命中费率并预留全部输出上限。默认5元。平台usage返回后记录实际费用；估算可能偏高或偏低，此值是请求前预留停止门槛，不是账单硬上限。达到门槛后，Host会在发送下一请求前停止。其他服务商费用规则不同，目前按请求/输出限制并记录usage。")]
    [SettingPropertyGroup("模型服务", GroupOrder = 0)]
    public string DeepSeekRunCostLimitCny
    {
        get => _deepSeekRunCostLimitCny;
        set
        {
            var next = value?.Trim() ?? string.Empty;
            if (string.Equals(_deepSeekRunCostLimitCny, next, StringComparison.Ordinal)) return;
            _deepSeekRunCostLimitCny = next;
            OnPropertyChanged();
        }
    }

    [SettingPropertyButton("检查模型配置", Order = 4, RequireRestart = false, HintText = "只检查服务地址、模型 ID、输出模式和预算；启动 AI 时会用只读 /models 检查模型是否可调用，不生成推理请求。", Content = "检查")]
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
        var errorCode = AgentProviderConfigurationValidator.GetErrorCode(OllamaBaseUrl, ModelId, OutputMode, DeepSeekRunCostLimitCny);
        if (errorCode is null && Uri.TryCreate(OllamaBaseUrl, UriKind.Absolute, out var configuredUri) &&
            !configuredUri.IsLoopback &&
            string.IsNullOrWhiteSpace(ResolveApiKey(OllamaBaseUrl)))
            errorCode = "provider-api-key-missing";
        var message = errorCode switch
        {
            null => "服务地址和模型 ID 格式有效；启动 AI 时会验证服务与模型，并检查当前模型输出格式。",
            "provider-profile-endpoint-invalid" => "地址无效：远程服务必须使用 HTTPS；地址不能包含账号密码、查询参数或片段。",
            "provider-profile-model-invalid" => "模型 ID 无效：请输入服务商提供的模型标识。",
            "provider-profile-output-mode-invalid" => "结构化输出模式无效：请输入 auto、json_schema、json_object 或 required_tool_call。",
            "provider-profile-run-cost-invalid" => "DeepSeek 预算无效：请输入 0.01 到 1000 之间的人民币金额。",
            "provider-api-key-missing" => "远程模型的 API 密钥未配置。请在启动 Bannerlord 前设置 CHRONICLE_LLM_API_KEY；密钥不会写入 Mod 设置文件或测试日志。",
            _ => "模型网关配置无效；请检查地址和模型名称。"
        };
        MBInformationManager.AddQuickInformation(new TextObject(message), 7000);
    }

    private static string? ResolveApiKey(string baseUrl)
    {
        var credential = AgentProviderConfigurationValidator.SelectApiKey(
            baseUrl,
            Environment.GetEnvironmentVariable("CHRONICLE_LLM_API_KEY"),
            Environment.GetEnvironmentVariable("CHRONICLE_LLM_API_KEY", EnvironmentVariableTarget.User),
            Environment.GetEnvironmentVariable("FREELLMAPI_API_KEY"),
            Environment.GetEnvironmentVariable("FREELLMAPI_API_KEY", EnvironmentVariableTarget.User));
        return credential.ApiKey;
    }
}
