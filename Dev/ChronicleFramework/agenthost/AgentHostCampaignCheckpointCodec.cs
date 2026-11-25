using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal static class AgentHostCampaignCheckpointCodec
{
    private const int MaximumPayloadBytes = 65_536;
    private const int MaximumBase64Characters = 100_000;

    internal static JsonObject ReadFromNativeReceipt(JsonElement receipt)
    {
        if (ReadString(receipt, "status") != "completed" ||
            !receipt.TryGetProperty("data", out var data) || data.ValueKind != JsonValueKind.Object)
            throw new AgentHostException("campaign-checkpoint-native-receipt-invalid", "The Native Campaign checkpoint read did not return a completed data object.");

        var campaignInstanceId = ReadString(data, "campaignInstanceId");
        var encoded = ReadString(data, "checkpointBase64");
        if (string.IsNullOrWhiteSpace(campaignInstanceId) || campaignInstanceId.Length > 128 || encoded is null || encoded.Length > MaximumBase64Characters)
            throw new AgentHostException("campaign-checkpoint-native-receipt-invalid", "The Native Campaign checkpoint identity or encoded payload is missing or oversized.");

        if (encoded.Length == 0)
            return new JsonObject
            {
                ["schemaVersion"] = 2,
                ["campaignInstanceId"] = campaignInstanceId,
                ["taskId"] = "chronicle-campaign",
                ["status"] = "active"
            };

        byte[] bytes;
        try { bytes = Convert.FromBase64String(encoded); }
        catch (FormatException exception)
        {
            throw new AgentHostException("campaign-checkpoint-invalid-base64", "The saved Agent checkpoint is not valid Base64.", exception);
        }
        if (bytes.Length is 0 or > MaximumPayloadBytes)
            throw new AgentHostException("campaign-checkpoint-payload-size-invalid", "The saved Agent checkpoint is empty or exceeds the Native save-data limit.");

        try
        {
            using var document = JsonDocument.Parse(new UTF8Encoding(false, true).GetString(bytes));
            var root = document.RootElement;
            var schemaVersion = ReadInt(root, "schemaVersion");
            var savedCampaignId = ReadString(root, "campaignInstanceId");
            if (root.ValueKind != JsonValueKind.Object || schemaVersion is not (1 or 2) ||
                !string.Equals(savedCampaignId, campaignInstanceId, StringComparison.Ordinal))
                throw new AgentHostException("campaign-checkpoint-identity-invalid", "The saved Agent checkpoint schema or Campaign identity does not match the current Native Campaign.");
            return JsonNode.Parse(root.GetRawText())?.AsObject()
                ?? throw new AgentHostException("campaign-checkpoint-shape-invalid", "The saved Agent checkpoint is not a JSON object.");
        }
        catch (JsonException exception)
        {
            throw new AgentHostException("campaign-checkpoint-invalid-json", "The saved Agent checkpoint is not valid JSON.", exception);
        }
        catch (DecoderFallbackException exception)
        {
            throw new AgentHostException("campaign-checkpoint-invalid-utf8", "The saved Agent checkpoint is not valid UTF-8.", exception);
        }
    }

    internal static string EncodeForNative(string checkpointJson)
    {
        if (string.IsNullOrWhiteSpace(checkpointJson))
            throw new AgentHostException("campaign-checkpoint-payload-empty", "The Agent checkpoint cannot be empty.");
        byte[] bytes;
        try { bytes = new UTF8Encoding(false, true).GetBytes(checkpointJson); }
        catch (EncoderFallbackException exception)
        {
            throw new AgentHostException("campaign-checkpoint-invalid-utf8", "The Agent checkpoint cannot be encoded as valid UTF-8.", exception);
        }
        if (bytes.Length > MaximumPayloadBytes)
            throw new AgentHostException("campaign-checkpoint-payload-size-invalid", "The Agent checkpoint exceeds the Native save-data limit.");

        try
        {
            using var document = JsonDocument.Parse(bytes);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object || ReadInt(root, "schemaVersion") is not (1 or 2) ||
                string.IsNullOrWhiteSpace(ReadString(root, "campaignInstanceId")))
                throw new AgentHostException("campaign-checkpoint-shape-invalid", "The Agent checkpoint must be a JSON object with supported schemaVersion and Campaign identity.");
        }
        catch (JsonException exception)
        {
            throw new AgentHostException("campaign-checkpoint-invalid-json", "The Agent checkpoint is not valid JSON.", exception);
        }
        return Convert.ToBase64String(bytes);
    }

    internal static IReadOnlyList<object> RunContractSelfTests()
    {
        const string campaignId = "campaign-memory-fixture";
        using var emptyReceipt = JsonDocument.Parse("{\"status\":\"completed\",\"data\":{\"campaignInstanceId\":\"campaign-memory-fixture\",\"checkpointBase64\":\"\"}}");
        var empty = ReadFromNativeReceipt(emptyReceipt.RootElement);
        if (ReadInt(empty, "schemaVersion") != 2 || ReadString(empty, "campaignInstanceId") != campaignId)
            throw new AgentHostException("campaign-checkpoint-self-test-empty-read-failed", "An empty Native checkpoint must initialize version 2 against the current Campaign identity.");

        empty["eycCompanionSearch"] = new JsonObject { ["noCandidateTownIds"] = new JsonArray("town-a") };
        var encoded = EncodeForNative(empty.ToJsonString());
        using var roundTripReceipt = JsonDocument.Parse(new JsonObject
        {
            ["status"] = "completed",
            ["data"] = new JsonObject { ["campaignInstanceId"] = campaignId, ["checkpointBase64"] = encoded }
        }.ToJsonString());
        var roundTrip = ReadFromNativeReceipt(roundTripReceipt.RootElement);
        if (roundTrip["eycCompanionSearch"]?["noCandidateTownIds"]?[0]?.GetValue<string>() != "town-a")
            throw new AgentHostException("campaign-checkpoint-self-test-roundtrip-failed", "The Native checkpoint codec must preserve Chronicle-owned campaign memory while retaining the save identity.");

        RejectRead("{\"status\":\"completed\",\"data\":{\"campaignInstanceId\":\"campaign-memory-fixture\",\"checkpointBase64\":\"e30=\"}}", "campaign-checkpoint-identity-invalid");
        RejectWrite("{\"schemaVersion\":3,\"campaignInstanceId\":\"campaign-memory-fixture\"}", "campaign-checkpoint-shape-invalid");
        RejectWrite("{\"schemaVersion\":2,\"campaignInstanceId\":\"campaign-memory-fixture\",\"padding\":\"" + new string('x', MaximumPayloadBytes) + "\"}", "campaign-checkpoint-payload-size-invalid");
        return [new { scenario = "native-campaign-checkpoint-codec-binds-memory-to-save-identity-preserves-existing-json-and-enforces-size-and-schema", passed = true }];

        static void RejectRead(string receipt, string expectedCode)
        {
            try
            {
                using var document = JsonDocument.Parse(receipt);
                _ = ReadFromNativeReceipt(document.RootElement);
                throw new AgentHostException("campaign-checkpoint-self-test-invalid-read-accepted", "The checkpoint codec accepted an invalid saved Campaign checkpoint.");
            }
            catch (AgentHostException exception) when (exception.Code == expectedCode) { }
        }

        static void RejectWrite(string checkpoint, string expectedCode)
        {
            try
            {
                _ = EncodeForNative(checkpoint);
                throw new AgentHostException("campaign-checkpoint-self-test-invalid-write-accepted", "The checkpoint codec accepted an invalid write payload.");
            }
            catch (AgentHostException exception) when (exception.Code == expectedCode) { }
        }
    }

    private static string? ReadString(JsonElement element, string name) =>
        element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString()
            : null;

    private static string? ReadString(JsonObject? node, string name) =>
        node?[name] is JsonValue value && value.TryGetValue<string>(out var result) ? result : null;

    private static int ReadInt(JsonElement element, string name) =>
        element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var value) && value.TryGetInt32(out var result) ? result : 0;

    private static int ReadInt(JsonObject? node, string name) =>
        node?[name] is JsonValue value && value.TryGetValue<int>(out var result) ? result : 0;
}
