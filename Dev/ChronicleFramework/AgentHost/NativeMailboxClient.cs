using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal sealed class NativeMailboxClient : IAgentHostCampaignNativeClient
{
    private static readonly HashSet<string> SupplySliceActions = new(StringComparer.Ordinal)
    {
        "state", "menuSelect", "foodOptions", "provision", "tradeConfirm", "tradeCancelChanges", "rest"
    };

    private readonly string _root;
    private readonly string _responseRoot;
    private readonly TimeSpan _timeout;

    internal NativeMailboxClient(string protocolRoot, TimeSpan timeout)
    {
        _root = Path.GetFullPath(protocolRoot);
        _responseRoot = Path.Combine(_root, "responses");
        _timeout = timeout;
        Directory.CreateDirectory(_root);
        Directory.CreateDirectory(_responseRoot);
    }

    internal static string GetDefaultProtocolRoot()
    {
        var documents = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
        if (string.IsNullOrWhiteSpace(documents))
            throw new AgentHostException("documents-path-unavailable", "The Windows Documents directory could not be resolved.");
        return Path.Combine(documents, "Mount and Blade II Bannerlord", "AgentRuns", "ChronicleAgent");
    }

    internal Task<JsonDocument> ReadStateAsync(CancellationToken cancellationToken) =>
        SendAsync("state", new JsonObject(), acceptedResponseExpected: false, cancellationToken);

    Task<JsonDocument> IAgentHostCampaignNativeClient.ReadStateAsync(CancellationToken cancellationToken) => ReadStateAsync(cancellationToken);

    internal Task<JsonDocument> ExecuteSupplyActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
    {
        if (!SupplySliceActions.Contains(action) || action == "state")
            throw new AgentHostException("native-action-not-in-supply-scope", "The Agent Host action is outside the approved Native supply slice.");
        return SendAsync(action, arguments, acceptedResponseExpected: action == "rest", cancellationToken);
    }

    internal Task<JsonDocument> ExecuteCampaignActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
    {
        switch (action)
        {
            case "mapSettlementTargets" when arguments.Count == 0:
                break;
            case "move" when arguments.Count == 1 &&
                              arguments.TryGetPropertyValue("settlementId", out var settlementIdNode) &&
                              settlementIdNode is JsonValue settlementIdValue &&
                              settlementIdValue.TryGetValue<string>(out var settlementId) &&
                              !string.IsNullOrWhiteSpace(settlementId):
                break;
            case "mapSettlementTargets":
                throw new AgentHostException("native-map-target-arguments-invalid", "mapSettlementTargets does not accept arguments.");
            case "move":
                throw new AgentHostException("native-move-arguments-invalid", "move requires only a non-empty observed settlementId.");
            default:
                throw new AgentHostException("native-action-not-in-campaign-loop-scope", "The Agent Host action is outside the current Campaign loop scope.");
        }

        return SendAsync(action, arguments, acceptedResponseExpected: false, cancellationToken);
    }

    Task<JsonDocument> IAgentHostCampaignNativeClient.ExecuteCampaignActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken) =>
        ExecuteCampaignActionAsync(action, arguments, cancellationToken);

    private async Task<JsonDocument> SendAsync(
        string action,
        JsonObject arguments,
        bool acceptedResponseExpected,
        CancellationToken cancellationToken)
    {
        var commandId = "host-" + Guid.NewGuid().ToString("N");
        var commandPath = Path.Combine(_root, "command.json");
        var temporaryPath = commandPath + "." + commandId + ".tmp";
        var command = new JsonObject { ["id"] = commandId, ["action"] = action };
        foreach (var property in arguments) command[property.Key] = property.Value?.DeepClone();
        var json = command.ToJsonString();

        await using (var stream = new FileStream(temporaryPath, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
        {
            var bytes = new UTF8Encoding(false).GetBytes(json);
            await stream.WriteAsync(bytes, cancellationToken);
            await stream.FlushAsync(cancellationToken);
            stream.Flush(flushToDisk: true);
        }

        try
        {
            try { File.Move(temporaryPath, commandPath, overwrite: false); }
            catch (IOException exception) when (File.Exists(commandPath))
            {
                throw new AgentHostException("native-mailbox-busy", "Another protocol owner has an unclaimed Native command.", exception);
            }

            var deadline = Stopwatch.GetTimestamp() + (long)(_timeout.TotalSeconds * Stopwatch.Frequency);
            var candidateStatuses = acceptedResponseExpected
                ? new[] { "accepted", "completed", "rejected", "failed" }
                : new[] { "completed", "rejected", "failed" };
            while (Stopwatch.GetTimestamp() < deadline)
            {
                cancellationToken.ThrowIfCancellationRequested();
                foreach (var status in candidateStatuses)
                {
                    var responsePath = Path.Combine(_responseRoot, commandId + "." + status + ".json");
                    if (!File.Exists(responsePath)) continue;
                    var response = await ReadJsonAsync(responsePath, cancellationToken);
                    ValidateResponse(response.RootElement, commandId, action, status);
                    return response;
                }
                await Task.Delay(TimeSpan.FromMilliseconds(100), cancellationToken);
            }

            throw new AgentHostException("native-command-timeout", $"The Native '{action}' command timed out.");
        }
        catch
        {
            RemoveOwnedUnclaimedCommand(commandPath, commandId);
            throw;
        }
        finally
        {
            try { if (File.Exists(temporaryPath)) File.Delete(temporaryPath); }
            catch (IOException) { }
        }
    }

    private static async Task<JsonDocument> ReadJsonAsync(string path, CancellationToken cancellationToken)
    {
        for (var attempt = 0; attempt < 5; attempt++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            try { return JsonDocument.Parse(await File.ReadAllTextAsync(path, cancellationToken)); }
            catch (IOException) when (attempt < 4) { await Task.Delay(TimeSpan.FromMilliseconds(20), cancellationToken); }
            catch (JsonException) when (attempt < 4) { await Task.Delay(TimeSpan.FromMilliseconds(20), cancellationToken); }
        }
        throw new AgentHostException("native-response-unreadable", "A Native mailbox response was not readable as complete JSON.");
    }

    private static void ValidateResponse(JsonElement response, string commandId, string action, string fileStatus)
    {
        if (!response.TryGetProperty("protocolVersion", out var version) || !version.TryGetInt32(out var protocolVersion) || protocolVersion != 1 ||
            !string.Equals(ReadString(response, "commandId"), commandId, StringComparison.Ordinal) ||
            !string.Equals(ReadString(response, "action"), action, StringComparison.Ordinal) ||
            !string.Equals(ReadString(response, "status"), fileStatus, StringComparison.Ordinal))
            throw new AgentHostException("native-response-correlation-invalid", "Native response did not match the Host command and protocol version.");
    }

    private static string? ReadString(JsonElement element, string name) =>
        element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;

    private static void RemoveOwnedUnclaimedCommand(string commandPath, string commandId)
    {
        try
        {
            if (!File.Exists(commandPath)) return;
            using var command = JsonDocument.Parse(File.ReadAllText(commandPath));
            if (string.Equals(ReadString(command.RootElement, "id"), commandId, StringComparison.Ordinal)) File.Delete(commandPath);
        }
        catch (IOException) { }
        catch (JsonException) { }
    }
}
