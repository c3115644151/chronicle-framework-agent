#nullable enable
using System;
using System.Globalization;

namespace ChronicleFramework;

internal static class AgentProviderConfigurationValidator
{
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
