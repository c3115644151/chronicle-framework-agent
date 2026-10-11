using System.Text.Json;

namespace ChronicleFramework.AgentHost;

internal sealed record AgentProviderProfile(string BaseUrl, string ModelId, string Source)
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
            throw new AgentHostException("provider-profile-missing", "Open Chronicle Framework's global Mod Settings and configure a local Ollama URL and model before starting the Agent.");

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

        var baseUrl = ReadString(root, "OllamaBaseUrl");
        var modelId = ReadString(root, "ModelId");
        if (string.IsNullOrWhiteSpace(baseUrl) || !Uri.TryCreate(baseUrl.Trim(), UriKind.Absolute, out var uri) ||
            uri.Scheme is not ("http" or "https") || !uri.IsLoopback || !string.IsNullOrEmpty(uri.UserInfo))
            throw new AgentHostException("provider-profile-endpoint-invalid", "The configured local Ollama URL must be a loopback HTTP(S) address without credentials.");
        if (string.IsNullOrWhiteSpace(modelId) || modelId.Trim().Length > 160)
            throw new AgentHostException("provider-profile-model-invalid", "The configured Ollama model identifier is missing or too long.");

        return new AgentProviderProfile(uri.ToString().TrimEnd('/'), modelId.Trim(), source);
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
