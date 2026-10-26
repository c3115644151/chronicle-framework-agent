using System.Text.Json;
using System.Globalization;
using ChronicleFramework;

namespace ChronicleFramework.AgentHost;

internal sealed record AgentProviderProfile(string BaseUrl, string ModelId, string OutputMode, double DeepSeekRunCostLimitCny, string Source)
{
    private const int MaxProfileBytes = 32 * 1024;

    internal static string GetDefaultPath()
    {
        var documents = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
        if (string.IsNullOrWhiteSpace(documents))
            throw new AgentHostException("provider-profile-path-unavailable", "The Windows Documents directory could not be resolved for the global model profile.");
        return Path.Combine(documents, "Mount and Blade II Bannerlord", "Configs", "ModSettings", "Global", "ChronicleFramework", "ChronicleAgentSettings.json");
    }

    internal static AgentProviderProfile LoadDefault()
    {
        return Load(GetDefaultPath(), "mcm-global-profile");
    }

    internal static AgentProviderProfile Load(string path, string source)
    {
        if (!File.Exists(path))
            throw new AgentHostException("provider-profile-missing", "Open Chronicle Framework's global Mod Settings and configure an OpenAI-compatible provider URL and model identifier before starting the Agent.");

        var fileInfo = new FileInfo(path);
        if (fileInfo.Length is <= 0 or > MaxProfileBytes)
            throw new AgentHostException("provider-profile-size-invalid", "The global model profile is empty or exceeds the supported size.");

        try
        {
            using var document = JsonDocument.Parse(File.ReadAllText(path));
            return Parse(document.RootElement, source);
        }
        catch (JsonException exception)
        {
            throw new AgentHostException("provider-profile-invalid-json", "The global model profile could not be read; reopen Chronicle Framework Mod Settings and save valid values.", exception);
        }
        catch (IOException exception)
        {
            throw new AgentHostException("provider-profile-unreadable", "The global model profile could not be read.", exception);
        }
    }

    internal static AgentProviderProfile Parse(JsonElement root, string source = "test-profile")
    {
        if (root.ValueKind != JsonValueKind.Object)
            throw new AgentHostException("provider-profile-shape-invalid", "The global model profile must be a JSON object.");

        // `OllamaBaseUrl` is retained as a migration key for existing MCM profiles.
        var baseUrl = ReadString(root, "ProviderBaseUrl") ?? ReadString(root, "OllamaBaseUrl");
        var modelId = ReadString(root, "ModelId");
        var outputMode = ReadString(root, "OutputMode") ?? "auto";
        var deepSeekRunCostLimitCny = ReadString(root, "DeepSeekRunCostLimitCny") ?? "5";
        return ParseValues(baseUrl, modelId, outputMode, deepSeekRunCostLimitCny, source);
    }

    internal static string? GetSettingsValidationError(string? baseUrl, string? modelId, string? outputMode = null, string? deepSeekRunCostLimitCny = null)
    {
        return AgentProviderConfigurationValidator.GetErrorCode(baseUrl, modelId, outputMode, deepSeekRunCostLimitCny);
    }

    private static AgentProviderProfile ParseValues(string? baseUrl, string? modelId, string? outputMode, string? deepSeekRunCostLimitCny, string source)
    {
        var errorCode = AgentProviderConfigurationValidator.GetErrorCode(baseUrl, modelId, outputMode, deepSeekRunCostLimitCny);
        if (errorCode == "provider-profile-endpoint-invalid")
            throw new AgentHostException(errorCode, "The configured provider URL must use HTTPS (HTTP is allowed only on loopback) and must not include credentials, query, or fragment.");
        if (errorCode == "provider-profile-model-invalid")
            throw new AgentHostException(errorCode, "The configured model identifier is missing or too long.");
        if (errorCode == "provider-profile-output-mode-invalid")
            throw new AgentHostException(errorCode, "The structured output mode must be auto, json_schema, json_object, or required_tool_call.");
        if (errorCode == "provider-profile-run-cost-invalid")
            throw new AgentHostException(errorCode, "The DeepSeek per-run cost ceiling must be a number from 0.01 through 1000 CNY.");

        var uri = new Uri(baseUrl!.Trim(), UriKind.Absolute);

        return new AgentProviderProfile(uri.ToString().TrimEnd('/'), modelId!.Trim(), string.IsNullOrWhiteSpace(outputMode) ? "auto" : outputMode,
            double.Parse(string.IsNullOrWhiteSpace(deepSeekRunCostLimitCny) ? "5" : deepSeekRunCostLimitCny, CultureInfo.InvariantCulture), source);
    }

    private static string? ReadString(JsonElement root, string propertyName)
    {
        foreach (var property in root.EnumerateObject())
        {
            if (string.Equals(property.Name, propertyName, StringComparison.OrdinalIgnoreCase) && property.Value.ValueKind == JsonValueKind.String)
                return property.Value.GetString();
        }
        return null;
    }
}
