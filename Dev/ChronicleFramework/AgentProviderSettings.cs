using System;
using MCM.Abstractions.Attributes;
using MCM.Abstractions.Attributes.v2;
using MCM.Abstractions.Base.Global;

namespace ChronicleFramework;

internal sealed class ChronicleAgentProviderSettings : AttributeGlobalSettings<ChronicleAgentProviderSettings>
{
    private string _ollamaBaseUrl = "http://127.0.0.1:11434/v1";
    private string _modelId = "qwen3.5:4b-q4_K_M";

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
}
