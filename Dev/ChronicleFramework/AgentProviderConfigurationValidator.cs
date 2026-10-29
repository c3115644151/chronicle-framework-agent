#nullable enable
using System;
using System.Globalization;

namespace ChronicleFramework;

internal static class AgentProviderConfigurationValidator
{
    internal static (string? ApiKey, string? Source) SelectApiKey(
        string? baseUrl,
        string? genericProcessKey,
        string? genericUserKey,
        string? freeLlmApiProcessKey,
        string? freeLlmApiUserKey)
    {
        var isFreeLlmApi = Uri.TryCreate(baseUrl?.Trim(), UriKind.Absolute, out var uri) &&
            uri.IsLoopback && uri.Port == 31415 && string.Equals(uri.AbsolutePath.TrimEnd('/'), "/v1", StringComparison.Ordinal);
        var candidates = isFreeLlmApi
            ? new (string? Value, string Source)[]
            {
                (freeLlmApiProcessKey, "FREELLMAPI_API_KEY:Process"),
                (freeLlmApiUserKey, "FREELLMAPI_API_KEY:User"),
                (genericProcessKey, "CHRONICLE_LLM_API_KEY:Process"),
                (genericUserKey, "CHRONICLE_LLM_API_KEY:User")
            }
            : new (string? Value, string Source)[]
            {
                (genericProcessKey, "CHRONICLE_LLM_API_KEY:Process"),
                (genericUserKey, "CHRONICLE_LLM_API_KEY:User")
            };
        foreach (var candidate in candidates)
            if (!string.IsNullOrWhiteSpace(candidate.Value)) return (candidate.Value, candidate.Source);
        return (null, null);
    }

    internal static string? GetErrorCode(string? baseUrl, string? modelId, string? outputMode = null, string? deepSeekRunCostLimitCny = null)
    {
        if (string.IsNullOrWhiteSpace(baseUrl) || !Uri.TryCreate(baseUrl.Trim(), UriKind.Absolute, out var uri) ||
            uri.Scheme is not ("http" or "https") || (uri.Scheme == "http" && !uri.IsLoopback) || !string.IsNullOrEmpty(uri.UserInfo) ||
            !string.IsNullOrEmpty(uri.Query) || !string.IsNullOrEmpty(uri.Fragment))
            return "provider-profile-endpoint-invalid";
        if (string.IsNullOrWhiteSpace(modelId) || modelId.Trim().Length > 160)
            return "provider-profile-model-invalid";
        if (string.IsNullOrWhiteSpace(outputMode)) outputMode = "auto";
        if (outputMode is not ("auto" or "json_schema" or "json_object" or "required_tool_call"))
            return "provider-profile-output-mode-invalid";
        if (string.IsNullOrWhiteSpace(deepSeekRunCostLimitCny)) deepSeekRunCostLimitCny = "5";
        if (!double.TryParse(deepSeekRunCostLimitCny, NumberStyles.Float, CultureInfo.InvariantCulture, out var costLimit) || costLimit < 0.01d || costLimit > 1000d)
            return "provider-profile-run-cost-invalid";
        return null;
    }
}
