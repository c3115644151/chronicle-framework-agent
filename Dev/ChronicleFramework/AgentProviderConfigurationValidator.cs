#nullable enable
using System;
using System.Globalization;
using System.Net.Sockets;

namespace ChronicleFramework;

internal static class AgentProviderConfigurationValidator
{
    internal static (string? ApiKey, string? Source) SelectApiKey(
        string? baseUrl,
        string? genericProcessKey,
        string? genericUserKey,
        string? freeLlmApiProcessKey,
        string? freeLlmApiUserKey,
        string? dshWorkBuddyProcessKey = null,
        string? dshWorkBuddyUserKey = null)
    {
        var isDshWorkBuddy = Uri.TryCreate(baseUrl?.Trim(), UriKind.Absolute, out var dshUri) &&
            dshUri.IsLoopback && dshUri.Port == 8328 && string.Equals(dshUri.AbsolutePath.TrimEnd('/'), "/v1", StringComparison.Ordinal);
        if (isDshWorkBuddy)
        {
            foreach (var candidate in new (string? Value, string Source)[]
            {
                (dshWorkBuddyProcessKey, "CHRONICLE_DSH_XDPOOL_API_KEY:Process"),
                (dshWorkBuddyUserKey, "CHRONICLE_DSH_XDPOOL_API_KEY:User")
            })
                if (!string.IsNullOrWhiteSpace(candidate.Value)) return (candidate.Value, candidate.Source);
            // This is a provider-specific loopback gateway. A DeepSeek or
            // FreeLLMAPI key is not its credential and must not be forwarded.
            return (null, null);
        }

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

internal static class ProviderProxySelection
{
    internal const string LocalFallbackProxyUrl = "http://127.0.0.1:7890";

    internal static string? SelectProxyUrl(Uri providerEndpoint, string? httpsProxy, string? httpProxy, string? allProxy,
        bool localProxyListenerAvailable, string? noProxy = null)
    {
        if (providerEndpoint == null || providerEndpoint.IsLoopback) return null;
        if (IsNoProxyMatch(providerEndpoint.Host, noProxy)) return null;
        if (!string.IsNullOrWhiteSpace(httpsProxy)) return httpsProxy.Trim();
        if (!string.IsNullOrWhiteSpace(httpProxy)) return httpProxy.Trim();
        if (!string.IsNullOrWhiteSpace(allProxy)) return allProxy.Trim();
        return localProxyListenerAvailable ? LocalFallbackProxyUrl : null;
    }

    internal static bool IsNoProxyMatch(string host, string? noProxy)
    {
        if (string.IsNullOrWhiteSpace(noProxy)) return false;
        foreach (var rawEntry in noProxy.Split(new[] { ',', ';' }, StringSplitOptions.RemoveEmptyEntries))
        {
            var entry = rawEntry.Trim();
            if (entry == "*") return true;
            if (entry.Contains("/")) continue;
            if (entry.StartsWith("*.", StringComparison.Ordinal)) entry = entry.Substring(2);
            else entry = entry.TrimStart('.');
            var colon = entry.LastIndexOf(':');
            if (colon > 0 && entry.IndexOf(']') < colon) entry = entry.Substring(0, colon);
            if (string.Equals(host, entry, StringComparison.OrdinalIgnoreCase) || host.EndsWith("." + entry, StringComparison.OrdinalIgnoreCase))
                return true;
        }
        return false;
    }

    internal static bool IsLocalProxyListenerAvailable(int timeoutMilliseconds = 600)
    {
        using (var client = new TcpClient())
        {
            try
            {
                var connection = client.ConnectAsync("127.0.0.1", 7890);
                return connection.Wait(timeoutMilliseconds) && client.Connected;
            }
            catch { return false; }
        }
    }
}
