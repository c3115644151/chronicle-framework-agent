using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal sealed class NativeMailboxClient : IAgentHostVillageToolsQuestNativeClient, IAgentHostBattleSimulationNativeClient, IAgentHostQuestDetailsNativeClient
{
    private static readonly HashSet<string> SupplySliceActions = new(StringComparer.Ordinal)
    {
        "state", "menuSelect", "foodOptions", "provision", "tradeConfirm", "tradeCancelChanges", "rest"
    };

    private static readonly HashSet<string> VillageToolsQuestActions = new(StringComparer.Ordinal)
    {
        "mapSettlementTargets", "move", "menuSelect", "talkToSettlementHero", "dialogueSelect",
        "dialogueContinue", "questDetails", "tradeOptions", "trade", "tradeConfirm", "tradeCancel", "tradeCancelChanges",
        "barterOptions", "barterAutoBalance", "barterOffer", "barterCancel",
        "inventoryOpen", "heroEquipmentOptions", "inventoryCancel"
    };
    private static readonly HashSet<string> BattleSimulationActions = new(StringComparer.Ordinal)
    {
        "mapPartyTargets", "pursue", "dialogueSelect", "dialogueContinue", "menuSelect", "battleSkip", "battleFinish", "partyTakeAll", "partyScreenDone", "inventoryTakeAll", "inventoryDone"
    };

    private readonly string _root;
    private readonly string _responseRoot;
    private readonly TimeSpan _timeout;
    private readonly int? _expectedProcessId;
    private readonly string? _expectedNativeSessionId;

    internal NativeMailboxClient(string protocolRoot, TimeSpan timeout, int? expectedProcessId = null, string? expectedNativeSessionId = null)
    {
        _root = Path.GetFullPath(protocolRoot);
        _responseRoot = Path.Combine(_root, "responses");
        _timeout = timeout;
        _expectedProcessId = expectedProcessId;
        _expectedNativeSessionId = expectedNativeSessionId;
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

    public Task<JsonDocument> ReadQuestDetailsAsync(string questId, CancellationToken cancellationToken)
    {
        return SendAsync("questDetails", BuildQuestDetailsArguments(questId), acceptedResponseExpected: false, cancellationToken);
    }

    internal static JsonObject BuildQuestDetailsArguments(string questId)
    {
        if (string.IsNullOrWhiteSpace(questId) || questId.Length > 160)
            throw new AgentHostException("native-quest-details-id-invalid", "The read-only Quest Journal query requires one bounded observed quest id.");
        return new JsonObject { ["questId"] = questId };
    }

    internal static IReadOnlyList<object> RunQuestDetailsReadActionContractSelfTests()
    {
        var arguments = BuildQuestDetailsArguments("rebuild_player_clan_storymode_quest");
        if (arguments.Count != 1 || arguments["questId"]?.GetValue<string>() != "rebuild_player_clan_storymode_quest")
            throw new AgentHostException("native-quest-details-read-contract-failed", "The read-only Quest Journal adapter must serialize only its single observed quest id.");
        foreach (var invalid in new[] { "", " ", new string('x', 161) })
        {
            try
            {
                _ = BuildQuestDetailsArguments(invalid);
                throw new AgentHostException("native-quest-details-invalid-id-accepted", "The read-only Quest Journal adapter accepted a blank or oversized id.");
            }
            catch (AgentHostException exception) when (exception.Code == "native-quest-details-id-invalid") { }
        }
        return [new { scenario = "native-quest-details-is-an-explicit-read-only-adapter-with-one-bounded-id", passed = true }];
    }

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

    public Task<JsonDocument> ExecuteVillageToolsQuestActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
    {
        // This is only the transport's closed action/argument boundary. The quest loop must still
        // construct its per-decision catalog from fresh Native observations and bind every ID to it.
        ValidateVillageToolsQuestAction(action, arguments);
        return SendAsync(action, arguments, acceptedResponseExpected: false, cancellationToken);
    }

    public Task<JsonDocument> ExecuteBattleSimulationActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
    {
        ValidateBattleSimulationAction(action, arguments);
        return SendAsync(action, arguments, acceptedResponseExpected: false, cancellationToken);
    }

    internal static void ValidateBattleSimulationAction(string action, JsonObject arguments)
    {
        if (!BattleSimulationActions.Contains(action))
            throw new AgentHostException("native-action-not-in-battle-simulation-scope", "The action is outside the bounded Native Campaign BattleSimulation scope.");

        static bool HasOnlyKeys(JsonObject value, params string[] keys) =>
            value.Count == keys.Length && keys.All(value.ContainsKey);
        static bool HasText(JsonObject value, string key) =>
            value[key] is JsonValue node && node.TryGetValue<string>(out var text) && !string.IsNullOrWhiteSpace(text);

        var valid = action switch
        {
            "mapPartyTargets" or "dialogueContinue" or "battleSkip" or "battleFinish" or "partyScreenDone" or "inventoryTakeAll" or "inventoryDone" => arguments.Count == 0,
            "pursue" => HasOnlyKeys(arguments, "partyId") && HasText(arguments, "partyId"),
            "dialogueSelect" => HasOnlyKeys(arguments, "optionId") && HasText(arguments, "optionId"),
            "menuSelect" => HasOnlyKeys(arguments, "menuId", "optionId") && HasText(arguments, "menuId") && HasText(arguments, "optionId"),
            "partyTakeAll" => HasOnlyKeys(arguments, "troopType") && arguments["troopType"] is JsonValue troopTypeNode && troopTypeNode.TryGetValue<string>(out var troopType) && troopType is "members" or "prisoners",
            _ => false
        };
        if (!valid)
            throw new AgentHostException("native-battle-simulation-arguments-invalid", $"The Native '{action}' arguments do not match the bounded BattleSimulation protocol contract.");
    }

    internal static void ValidateVillageToolsQuestAction(string action, JsonObject arguments)
    {
        if (!VillageToolsQuestActions.Contains(action))
            throw new AgentHostException("native-action-not-in-village-tools-scope", "The action is outside the bounded village-tools quest transport scope.");

        static bool HasOnlyKeys(JsonObject value, params string[] keys) =>
            value.Count == keys.Length && keys.All(value.ContainsKey);
        static bool HasText(JsonObject value, string key) =>
            value[key] is JsonValue node && node.TryGetValue<string>(out var text) && !string.IsNullOrWhiteSpace(text);

        var valid = action switch
        {
            "mapSettlementTargets" or "dialogueContinue" or "tradeOptions" or "tradeConfirm" or "tradeCancel" or "tradeCancelChanges" or
            "barterOptions" or "barterAutoBalance" or "barterCancel" or
                "inventoryOpen" or "heroEquipmentOptions" or "inventoryCancel" => arguments.Count == 0,
            "move" => HasOnlyKeys(arguments, "settlementId") && HasText(arguments, "settlementId"),
            "menuSelect" => HasOnlyKeys(arguments, "menuId", "optionId") && HasText(arguments, "menuId") && HasText(arguments, "optionId"),
            "talkToSettlementHero" => HasOnlyKeys(arguments, "heroId") && HasText(arguments, "heroId"),
            "dialogueSelect" => HasOnlyKeys(arguments, "optionId") && HasText(arguments, "optionId"),
            "questDetails" => HasOnlyKeys(arguments, "questId") && HasText(arguments, "questId"),
            "trade" => HasOnlyKeys(arguments, "direction", "itemViewModelId", "inventorySide", "amount") &&
                HasText(arguments, "direction") && HasText(arguments, "itemViewModelId") && HasText(arguments, "inventorySide") &&
                arguments["amount"] is JsonValue amountNode && amountNode.TryGetValue<int>(out var amount) && amount > 0 &&
                arguments["direction"]!.GetValue<string>() is "buy" or "sell",
            "barterOffer" => arguments.Count == 0 ||
                HasOnlyKeys(arguments, "expectedSessionId", "expectedProposalFingerprint") &&
                HasText(arguments, "expectedSessionId") && HasText(arguments, "expectedProposalFingerprint"),
            _ => false
        };

        if (!valid)
            throw new AgentHostException("native-village-tools-arguments-invalid", $"The Native '{action}' arguments do not match the bounded village-tools protocol contract.");
    }

    internal static IReadOnlyList<object> RunVillageToolsQuestActionContractSelfTests()
    {
        var validCases = new (string Action, string Json)[]
        {
            ("mapSettlementTargets", "{}"),
            ("move", "{\"settlementId\":\"village-1\"}"),
            ("menuSelect", "{\"menuId\":\"village\",\"optionId\":\"town_visit\"}"),
            ("talkToSettlementHero", "{\"heroId\":\"hero-1\"}"),
            ("dialogueSelect", "{\"optionId\":\"quest_accept\"}"),
            ("dialogueContinue", "{}"),
            ("questDetails", "{\"questId\":\"quest-1\"}"),
            ("tradeOptions", "{}"),
            ("trade", "{\"direction\":\"buy\",\"itemViewModelId\":\"tools\",\"inventorySide\":\"OtherInventory\",\"amount\":1}"),
            ("tradeConfirm", "{}"),
            ("tradeCancel", "{}"),
            ("tradeCancelChanges", "{}"),
            ("barterOptions", "{}"),
            ("barterAutoBalance", "{}"),
            ("barterOffer", "{}"),
            ("barterOffer", "{\"expectedSessionId\":\"session-1\",\"expectedProposalFingerprint\":\"fingerprint-1\"}"),
            ("barterCancel", "{}"),
            ("inventoryOpen", "{}"),
            ("heroEquipmentOptions", "{}"),
            ("inventoryCancel", "{}")
        };
        foreach (var item in validCases)
        {
            ValidateVillageToolsQuestAction(item.Action, JsonNode.Parse(item.Json)!.AsObject());
        }

        var invalidCases = new (string Action, string Json)[]
        {
            ("pause", "{}"),
            ("move", "{\"settlementId\":\"village-1\",\"pause\":true}"),
            ("talkToSettlementHero", "{\"heroId\":\"\"}"),
            ("trade", "{\"direction\":\"buy\",\"itemViewModelId\":\"tools\",\"inventorySide\":\"OtherInventory\",\"amount\":0}"),
            ("trade", "{\"direction\":\"delete\",\"itemViewModelId\":\"tools\",\"inventorySide\":\"OtherInventory\",\"amount\":1}"),
            ("tradeConfirm", "{\"questId\":\"quest-1\"}"),
            ("barterOffer", "{\"expectedSessionId\":\"session-1\"}"),
            ("inventoryCancelChanges", "{}")
        };
        foreach (var item in invalidCases)
        {
            var arguments = JsonNode.Parse(item.Json)!.AsObject();
            try
            {
                ValidateVillageToolsQuestAction(item.Action, arguments);
                throw new AgentHostException("native-village-tools-contract-self-test-invalid-accepted", "An invalid action, argument, transaction, or clock request passed validation.");
            }
            catch (AgentHostException exception) when (exception.Code is "native-action-not-in-village-tools-scope" or "native-village-tools-arguments-invalid") { }
        }

        return [new { scenario = "village-tools-mailbox-action-contract-allows-only-observed-native-action-shapes-and-no-clock-control", validCases = validCases.Length, invalidCases = invalidCases.Length, passed = true }];
    }

    internal static IReadOnlyList<object> RunBattleSimulationActionContractSelfTests()
    {
        var validCases = new (string Action, string Json)[]
        {
            ("mapPartyTargets", "{}"),
            ("pursue", "{\"partyId\":\"observed-bandit\"}"),
            ("menuSelect", "{\"menuId\":\"encounter\",\"optionId\":\"str_order_attack\"}"),
            ("battleSkip", "{}"),
            ("battleFinish", "{}"),
            ("partyTakeAll", "{\"troopType\":\"members\"}"),
            ("partyTakeAll", "{\"troopType\":\"prisoners\"}"),
            ("partyScreenDone", "{}"),
            ("inventoryTakeAll", "{}"),
            ("inventoryDone", "{}")
        };
        foreach (var item in validCases)
            ValidateBattleSimulationAction(item.Action, JsonNode.Parse(item.Json)!.AsObject());

        var invalidCases = new (string Action, string Json)[]
        {
            ("pause", "{}"),
            ("battleRetreat", "{}"),
            ("menuSelect", "{\"menuId\":\"encounter\"}"),
            ("pursue", "{\"partyId\":\"\"}"),
            ("partyTakeAll", "{\"troopType\":\"companions\"}"),
            ("inventoryDone", "{\"skipLoot\":true}")
        };
        foreach (var item in invalidCases)
        {
            try
            {
                ValidateBattleSimulationAction(item.Action, JsonNode.Parse(item.Json)!.AsObject());
                throw new AgentHostException("native-battle-simulation-contract-self-test-invalid-accepted", "An invalid action, argument, outcome, or clock request passed validation.");
            }
            catch (AgentHostException exception) when (exception.Code is "native-action-not-in-battle-simulation-scope" or "native-battle-simulation-arguments-invalid") { }
        }
        return [new { scenario = "battle-simulation-mailbox-allows-only-bounded-native-actions-and-no-clock-controls", validCases = validCases.Length, invalidCases = invalidCases.Length, passed = true }];
    }

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
        if (_expectedNativeSessionId != null) command["expectedNativeSessionId"] = _expectedNativeSessionId;
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
                    try { ValidateResponse(response.RootElement, commandId, action, status); }
                    catch { response.Dispose(); throw; }
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

    internal void ValidateResponse(JsonElement response, string commandId, string action, string fileStatus)
    {
        if (!response.TryGetProperty("protocolVersion", out var version) || !version.TryGetInt32(out var protocolVersion) || protocolVersion != 1 ||
            !string.Equals(ReadString(response, "commandId"), commandId, StringComparison.Ordinal) ||
            !string.Equals(ReadString(response, "action"), action, StringComparison.Ordinal) ||
            !string.Equals(ReadString(response, "status"), fileStatus, StringComparison.Ordinal))
            throw new AgentHostException("native-response-correlation-invalid", "Native response did not match the Host command and protocol version.");
        if (_expectedProcessId.HasValue && (!response.TryGetProperty("processId", out var processId) ||
            !processId.TryGetInt32(out var receivedProcessId) || receivedProcessId != _expectedProcessId.Value))
            throw new AgentHostException("native-response-process-mismatch", "Native response came from a different Bannerlord process.");
        if (_expectedNativeSessionId != null && !string.Equals(ReadString(response, "nativeSessionId"), _expectedNativeSessionId, StringComparison.Ordinal))
            throw new AgentHostException("native-response-session-mismatch", "Native response came from a different loaded Campaign session.");
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
