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

    internal static JsonObject? ReadJournalSnapshot(JsonObject campaignCheckpoint) =>
        (campaignCheckpoint[PropertyName]?["journalSnapshot"] as JsonObject)?.DeepClone() as JsonObject ??
        ReadLegacyJournalSnapshot(ReadString(campaignCheckpoint[PropertyName] as JsonObject, "journalFingerprint"));

    private static JsonObject? ReadLegacyJournalSnapshot(string? fingerprint)
    {
        if (string.IsNullOrWhiteSpace(fingerprint) || fingerprint.Length > 512)
            return null;

        var names = new[] { "gold", "partySize", "renown", "companions" };
        var segments = fingerprint.Split('|');
        if (segments.Length != names.Length)
            return null;

        var result = new JsonObject();
        foreach (var segment in segments)
        {
            var colon = segment.IndexOf(':');
            var slash = segment.IndexOf('/', colon + 1);
            var statusColon = segment.LastIndexOf(':');
            if (colon <= 0 || slash <= colon + 1 || statusColon <= slash + 1 || statusColon == segment.Length - 1)
                return null;

            var name = segment[..colon];
            if (!names.Contains(name, StringComparer.Ordinal) || result.ContainsKey(name) ||
                !double.TryParse(segment[(colon + 1)..slash], NumberStyles.Float, CultureInfo.InvariantCulture, out var current) ||
                !double.TryParse(segment[(slash + 1)..statusColon], NumberStyles.Float, CultureInfo.InvariantCulture, out var target) ||
                !double.IsFinite(current) || !double.IsFinite(target) ||
                !bool.TryParse(segment[(statusColon + 1)..], out var met))
                return null;

            result[name] = new JsonObject
            {
                ["current"] = current,
                ["target"] = target,
                ["met"] = met
            };
        }

        return names.All(result.ContainsKey) ? result : null;
    }

    internal static bool HasForwardProgressOrTargetChange(JsonObject? previousSnapshot, JsonObject currentSnapshot)
    {
        if (previousSnapshot is null) return true;
        foreach (var name in new[] { "gold", "partySize", "renown", "companions" })
        {
            var previous = previousSnapshot[name] as JsonObject;
            var current = currentSnapshot[name] as JsonObject;
            if (previous is null || current is null) return true;
            var previousTarget = ReadNumber(previous, "target");
            var currentTarget = ReadNumber(current, "target");
            var previousValue = ReadNumber(previous, "current");
            var currentValue = ReadNumber(current, "current");
            if (!double.IsFinite(previousTarget) || !double.IsFinite(currentTarget) || !double.IsFinite(previousValue) || !double.IsFinite(currentValue) ||
                previousTarget != currentTarget || currentValue > previousValue)
                return true;
        }
        return false;
    }

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

    internal static JsonObject Store(JsonObject campaignCheckpoint, JsonObject objectiveSnapshot, IEnumerable<string> townIds)
    {
        var journalFingerprint = BuildJournalFingerprint(objectiveSnapshot);
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
            ["journalSnapshot"] = objectiveSnapshot.DeepClone(),
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
        var stored = Store(checkpoint, objective, ["town-b", "town-a", "town-a"]);
        var retrieved = ReadNoCandidateTownIds(stored);
        if (retrieved.Count != 2 || !retrieved.Contains("town-a") || !retrieved.Contains("town-b") ||
            ReadJournalFingerprint(stored) != fingerprint || ReadString(stored, "existingCheckpointField") != "preserved")
            throw new AgentHostException("eyc-companion-memory-self-test-roundtrip-failed", "Campaign-scoped Companion memory must preserve existing checkpoint fields and deduplicate Native town IDs.");

        var legacyCheckpoint = new JsonObject
        {
            ["eycCompanionSearchMemoryV1"] = new JsonObject
            {
                ["journalFingerprint"] = fingerprint,
                ["noCandidateTownIds"] = new JsonArray("town-a", "town-b")
            }
        };
        var legacySnapshot = ReadJournalSnapshot(legacyCheckpoint);
        if (legacySnapshot is null || HasForwardProgressOrTargetChange(legacySnapshot, (JsonObject)objective.DeepClone()))
            throw new AgentHostException("eyc-companion-memory-self-test-legacy-fingerprint-read-failed", "A legacy checkpoint fingerprint must recover its previous EYC objective values before reconciliation.");

        var decreased = (JsonObject)objective.DeepClone();
        decreased["gold"]!["current"] = 670;
        if (HasForwardProgressOrTargetChange(objective, decreased))
            throw new AgentHostException("eyc-companion-memory-self-test-resource-loss-invalidated", "A loss of Gold must not erase verified no-candidate Tavern observations.");
        var refreshedAfterLoss = Store(stored, decreased, retrieved);
        if (ReadNoCandidateTownIds(refreshedAfterLoss).Count != 2 || ReadJournalFingerprint(refreshedAfterLoss) == fingerprint)
            throw new AgentHostException("eyc-companion-memory-self-test-resource-loss-refresh-failed", "A downward Native Journal value must refresh the memory baseline while preserving the verified towns.");

        var refreshedLegacyAfterLoss = Store(legacyCheckpoint, decreased, ReadNoCandidateTownIds(legacyCheckpoint));
        if (ReadNoCandidateTownIds(refreshedLegacyAfterLoss).Count != 2 || ReadJournalFingerprint(refreshedLegacyAfterLoss) == fingerprint)
            throw new AgentHostException("eyc-companion-memory-self-test-legacy-resource-loss-failed", "A resource decrease must preserve and upgrade legacy no-candidate checkpoint memory.");

        var increased = (JsonObject)decreased.DeepClone();
        increased["gold"]!["current"] = 800;
        if (!HasForwardProgressOrTargetChange(decreased, increased))
            throw new AgentHostException("eyc-companion-memory-self-test-forward-progress-not-detected", "A positive Journal objective change must invalidate old no-candidate observations.");
        var cleared = Store(refreshedAfterLoss, increased, []);
        if (ReadNoCandidateTownIds(cleared).Count != 0 || ReadString(cleared, "existingCheckpointField") != "preserved")
            throw new AgentHostException("eyc-companion-memory-self-test-journal-refresh-failed", "Positive EYC Journal progress must clear only the stale Companion search memory.");
        return [new { scenario = "eyc-companion-search-memory-persists-across-restarts-upgrades-legacy-fingerprints-and-invalidates-only-on-forward-journal-progress", passed = true }];
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
