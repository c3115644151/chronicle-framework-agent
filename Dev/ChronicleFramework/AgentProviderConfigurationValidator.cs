#nullable enable
using System;

namespace ChronicleFramework;

internal static class AgentProviderConfigurationValidator
{
    internal static string? GetErrorCode(string? baseUrl, string? modelId)
    {
        if (string.IsNullOrWhiteSpace(baseUrl) || !Uri.TryCreate(baseUrl.Trim(), UriKind.Absolute, out var uri) ||
            uri.Scheme is not ("http" or "https") || !uri.IsLoopback || !string.IsNullOrEmpty(uri.UserInfo) ||
            !string.IsNullOrEmpty(uri.Query) || !string.IsNullOrEmpty(uri.Fragment))
            return "provider-profile-endpoint-invalid";
        if (string.IsNullOrWhiteSpace(modelId) || modelId.Trim().Length > 160)
            return "provider-profile-model-invalid";
        return null;
    }
}
