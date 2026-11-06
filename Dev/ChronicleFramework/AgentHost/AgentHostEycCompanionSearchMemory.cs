using System.Globalization;
using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal static class AgentHostEycCompanionSearchMemory
{
    private const string PropertyName = "eycCompanionSearchMemoryV1";
    private const int MaximumRememberedTowns = 256;

    internal static string BuildJournalFingerprint(JsonObject objectiveSnapshot)
    {
        var names = new[] { "gold", "partySize", "renown", "companions" };
        return string.Join("|", names.Select(name =>
        {
            var objective = objectiveSnapshot[name] as JsonObject;
            if (objective is null)
                throw new AgentHostException("eyc-companion-memory-journal-invalid", "The Native EYC Journal snapshot omitted a required objective value.");
            var current = ReadNumber(objective, "current");
            var target = ReadNumber(objective, "target");
            if (!double.IsFinite(current) || !double.IsFinite(target))
                throw new AgentHostException("eyc-companion-memory-journal-invalid", "The Native EYC Journal snapshot contained a non-finite objective value.");
            return name + ":" + current.ToString("R", CultureInfo.InvariantCulture) + "/" + target.ToString("R", CultureInfo.InvariantCulture) + ":" + ReadBoolean(objective, "met");
        }));
    }

    internal static string? ReadJournalFingerprint(JsonObject campaignCheckpoint) =>
        ReadString(campaignCheckpoint[PropertyName] as JsonObject, "journalFingerprint");

    internal static HashSet<string> ReadNoCandidateTownIds(JsonObject campaignCheckpoint)
    {
        var result = new HashSet<string>(StringComparer.Ordinal);
        if (campaignCheckpoint[PropertyName] is not JsonObject memory || memory["noCandidateTownIds"] is not JsonArray ids)
            return result;
        if (ids.Count > MaximumRememberedTowns)
            throw new AgentHostException("eyc-companion-memory-town-count-invalid", "The saved Companion search memory exceeds its supported settlement count.");
        foreach (var value in ids.OfType<JsonValue>())
        {
            if (!value.TryGetValue<string>(out var id) || string.IsNullOrWhiteSpace(id) || id.Length > 128)
                throw new AgentHostException("eyc-companion-memory-town-id-invalid", "The saved Companion search memory contains an invalid Native settlement identifier.");
            result.Add(id);
        }
        return result;
    }

    internal static JsonObject Store(JsonObject campaignCheckpoint, string journalFingerprint, IEnumerable<string> townIds)
    {
        if (string.IsNullOrWhiteSpace(journalFingerprint) || journalFingerprint.Length > 512)
            throw new AgentHostException("eyc-companion-memory-fingerprint-invalid", "The Companion search checkpoint requires a bounded current Journal fingerprint.");
        var ids = townIds.Where(id => !string.IsNullOrWhiteSpace(id) && id.Length <= 128)
            .Distinct(StringComparer.Ordinal).OrderBy(id => id, StringComparer.Ordinal).ToArray();
        if (ids.Length > MaximumRememberedTowns)
            throw new AgentHostException("eyc-companion-memory-town-count-invalid", "The Companion search memory exceeds its supported settlement count.");

        var result = campaignCheckpoint.DeepClone() as JsonObject
            ?? throw new AgentHostException("campaign-checkpoint-shape-invalid", "The saved Agent checkpoint is not a JSON object.");
        result[PropertyName] = new JsonObject
        {
            ["journalFingerprint"] = journalFingerprint,
            ["noCandidateTownIds"] = new JsonArray(ids.Select(id => (JsonNode?)JsonValue.Create(id)).ToArray())
        };
        return result;
    }

    internal static IReadOnlyList<object> RunContractSelfTests()
    {
        var objective = new JsonObject
        {
            ["gold"] = new JsonObject { ["current"] = 1000, ["target"] = 2000, ["met"] = false },
            ["partySize"] = new JsonObject { ["current"] = 1, ["target"] = 25, ["met"] = false },
            ["renown"] = new JsonObject { ["current"] = 20, ["target"] = 50, ["met"] = false },
            ["companions"] = new JsonObject { ["current"] = 0, ["target"] = 1, ["met"] = false }
        };
        var fingerprint = BuildJournalFingerprint(objective);
        var checkpoint = new JsonObject
        {
            ["schemaVersion"] = 2,
            ["campaignInstanceId"] = "campaign-memory-fixture",
            ["existingCheckpointField"] = "preserved"
        };
        var stored = Store(checkpoint, fingerprint, ["town-b", "town-a", "town-a"]);
        var retrieved = ReadNoCandidateTownIds(stored);
        if (retrieved.Count != 2 || !retrieved.Contains("town-a") || !retrieved.Contains("town-b") ||
            ReadJournalFingerprint(stored) != fingerprint || ReadString(stored, "existingCheckpointField") != "preserved")
            throw new AgentHostException("eyc-companion-memory-self-test-roundtrip-failed", "Campaign-scoped Companion memory must preserve existing checkpoint fields and deduplicate Native town IDs.");

        var progressed = (JsonObject)objective.DeepClone();
        progressed["gold"]!["current"] = 1200;
        if (string.Equals(BuildJournalFingerprint(progressed), fingerprint, StringComparison.Ordinal))
            throw new AgentHostException("eyc-companion-memory-self-test-journal-fingerprint-stale", "A fresh original Journal value change must invalidate the old Companion search fingerprint.");
        var changed = Store(stored, BuildJournalFingerprint(progressed), []);
        if (ReadNoCandidateTownIds(changed).Count != 0 || ReadString(changed, "existingCheckpointField") != "preserved")
            throw new AgentHostException("eyc-companion-memory-self-test-journal-refresh-failed", "An EYC Journal change must be able to clear only the stale Companion search memory.");
        return [new { scenario = "eyc-companion-search-memory-persists-only-native-no-candidate-towns-and-clears-on-journal-progress", passed = true }];
    }

    private static string? ReadString(JsonObject? node, string name) =>
        node?[name] is JsonValue value && value.TryGetValue<string>(out var result) ? result : null;

    private static double ReadNumber(JsonObject? node, string name)
    {
        if (node?[name] is not JsonValue value) return double.NaN;
        if (value.TryGetValue<double>(out var number)) return number;
        if (value.TryGetValue<int>(out var integer)) return integer;
        if (value.TryGetValue<long>(out var longInteger)) return longInteger;
        return double.NaN;
    }

    private static bool ReadBoolean(JsonObject? node, string name) =>
        node?[name] is JsonValue value && value.TryGetValue<bool>(out var result) && result;
}
