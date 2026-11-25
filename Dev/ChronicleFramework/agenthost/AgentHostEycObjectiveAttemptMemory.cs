using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal static class AgentHostEycObjectiveAttemptMemory
{
    private const string PropertyName = "eycObjectiveAttemptMemoryV1";
    private static readonly HashSet<string> ObjectiveIds = new(AgentHostEstablishYourClanGoalLoop.ObjectiveIds, StringComparer.Ordinal);

    internal static JsonObject Empty() => new() { ["schemaVersion"] = 1, ["attempts"] = new JsonObject() };

    internal static JsonObject Read(JsonObject campaignCheckpoint)
    {
        if (campaignCheckpoint[PropertyName] is not JsonObject stored)
            return Empty();

        if (ReadInt(stored, "schemaVersion") != 1 || stored["attempts"] is not JsonObject attempts || attempts.Count > ObjectiveIds.Count)
            throw new AgentHostException("eyc-objective-attempt-memory-invalid", "The saved EYC objective-attempt memory has an unsupported shape or version.");

        var pendingCount = 0;
        foreach (var (objectiveId, value) in attempts)
        {
            if (!ObjectiveIds.Contains(objectiveId) || value is not JsonObject attempt ||
                ReadString(attempt, "status") is not ("pending" or "blocked") ||
                string.IsNullOrWhiteSpace(ReadString(attempt, "journalFingerprint")) ||
                string.IsNullOrWhiteSpace(ReadString(attempt, "nativeRouteFingerprint")) ||
                string.IsNullOrWhiteSpace(ReadString(attempt, "termination")) ||
                ReadString(attempt, "journalFingerprint")!.Length > 512 ||
                ReadString(attempt, "nativeRouteFingerprint")!.Length > 4096 ||
                ReadString(attempt, "termination")!.Length > 128 ||
                attempt["journalSnapshot"] is not JsonObject snapshot)
                throw new AgentHostException("eyc-objective-attempt-memory-invalid", "The saved EYC objective-attempt entry is malformed or contains an unsupported objective/status.");

            if (AgentHostEycCompanionSearchMemory.BuildJournalFingerprint(snapshot) != ReadString(attempt, "journalFingerprint"))
                throw new AgentHostException("eyc-objective-attempt-memory-invalid", "The saved EYC objective-attempt Journal snapshot does not match its fingerprint.");

            if (ReadString(attempt, "status") == "pending") pendingCount++;
        }
        if (pendingCount > 1)
            throw new AgentHostException("eyc-objective-attempt-memory-invalid", "Only one EYC objective may be pending at a time.");

        return stored.DeepClone() as JsonObject
            ?? throw new AgentHostException("eyc-objective-attempt-memory-invalid", "The saved EYC objective-attempt memory could not be cloned.");
    }

    internal static JsonObject Store(JsonObject campaignCheckpoint, JsonObject memory)
    {
        _ = Read(new JsonObject { [PropertyName] = memory.DeepClone() });
        var result = campaignCheckpoint.DeepClone() as JsonObject
            ?? throw new AgentHostException("campaign-checkpoint-shape-invalid", "The saved Agent checkpoint is not a JSON object.");
        result[PropertyName] = memory.DeepClone();
        return result;
    }

    internal static string? GetPendingObjective(JsonObject memory, JsonObject currentSnapshot)
    {
        var fingerprint = AgentHostEycCompanionSearchMemory.BuildJournalFingerprint(currentSnapshot);
        foreach (var (objectiveId, value) in (memory["attempts"] as JsonObject ?? new JsonObject()))
        {
            if (value is JsonObject attempt && ReadString(attempt, "status") == "pending" &&
                ReadString(attempt, "journalFingerprint") == fingerprint &&
                ReadBoolean(currentSnapshot[objectiveId] as JsonObject, "met") == false)
                return objectiveId;
        }
        return null;
    }

    internal static JsonObject Reconcile(JsonObject memory, JsonObject currentSnapshot, string currentNativeRouteFingerprint)
    {
        var result = Read(new JsonObject { [PropertyName] = memory.DeepClone() });
        var journalFingerprint = AgentHostEycCompanionSearchMemory.BuildJournalFingerprint(currentSnapshot);
        var attempts = result["attempts"] as JsonObject ?? new JsonObject();
        foreach (var (objectiveId, value) in attempts.ToArray())
        {
            if (value is not JsonObject attempt || ReadString(attempt, "journalFingerprint") != journalFingerprint ||
                (ReadString(attempt, "status") == "blocked" && ReadString(attempt, "nativeRouteFingerprint") != currentNativeRouteFingerprint))
                attempts.Remove(objectiveId);
        }
        result["attempts"] = attempts;
        return result;
    }

    internal static JsonObject ClearAll(JsonObject memory) => Empty();

    internal static int Count(JsonObject memory) => (memory["attempts"] as JsonObject)?.Count ?? 0;

    internal static HashSet<string> GetBlockedObjectives(JsonObject memory, JsonObject currentSnapshot, string currentNativeRouteFingerprint)
    {
        var result = new HashSet<string>(StringComparer.Ordinal);
        var journalFingerprint = AgentHostEycCompanionSearchMemory.BuildJournalFingerprint(currentSnapshot);
        foreach (var (objectiveId, value) in (memory["attempts"] as JsonObject ?? new JsonObject()))
        {
            if (value is JsonObject attempt && ReadString(attempt, "status") == "blocked" &&
                ReadString(attempt, "journalFingerprint") == journalFingerprint &&
                ReadString(attempt, "nativeRouteFingerprint") == currentNativeRouteFingerprint &&
                ReadBoolean(currentSnapshot[objectiveId] as JsonObject, "met") == false)
                result.Add(objectiveId);
        }
        return result;
    }

    internal static JsonObject SetPending(JsonObject memory, string objectiveId, JsonObject journalSnapshot, string nativeRouteFingerprint)
    {
        ValidateAttemptInput(objectiveId, journalSnapshot, nativeRouteFingerprint, "pending");
        var result = Read(new JsonObject { [PropertyName] = memory.DeepClone() });
        var attempts = result["attempts"] as JsonObject ?? new JsonObject();
        foreach (var key in attempts.Where(pair => ReadString(pair.Value as JsonObject, "status") == "pending").Select(pair => pair.Key).ToArray())
            attempts.Remove(key);
        attempts[objectiveId] = BuildAttempt("pending", "objective-selected", journalSnapshot, nativeRouteFingerprint);
        result["attempts"] = attempts;
        return result;
    }

    internal static JsonObject SetBlocked(JsonObject memory, string objectiveId, string termination, JsonObject journalSnapshot, string nativeRouteFingerprint)
    {
        ValidateAttemptInput(objectiveId, journalSnapshot, nativeRouteFingerprint, "blocked");
        if (string.IsNullOrWhiteSpace(termination) || termination.Length > 128)
            throw new AgentHostException("eyc-objective-attempt-termination-invalid", "The EYC route termination code must be a bounded non-empty identifier.");
        var result = Read(new JsonObject { [PropertyName] = memory.DeepClone() });
        var attempts = result["attempts"] as JsonObject ?? new JsonObject();
        attempts[objectiveId] = BuildAttempt("blocked", termination, journalSnapshot, nativeRouteFingerprint);
        result["attempts"] = attempts;
        return result;
    }

    internal static JsonObject Remove(JsonObject memory, string objectiveId)
    {
        var result = Read(new JsonObject { [PropertyName] = memory.DeepClone() });
        (result["attempts"] as JsonObject)?.Remove(objectiveId);
        return result;
    }

    internal static IReadOnlyList<object> RunContractSelfTests()
    {
        var snapshot = new JsonObject
        {
            ["gold"] = new JsonObject { ["current"] = 424, ["target"] = 2000, ["met"] = false },
            ["partySize"] = new JsonObject { ["current"] = 1, ["target"] = 25, ["met"] = false },
            ["renown"] = new JsonObject { ["current"] = 20, ["target"] = 50, ["met"] = false },
            ["companions"] = new JsonObject { ["current"] = 0, ["target"] = 1, ["met"] = false }
        };
        var original = new JsonObject { ["schemaVersion"] = 2, ["campaignInstanceId"] = "campaign-attempt-fixture", ["existing"] = "preserved" };
        var pending = SetPending(new JsonObject { ["schemaVersion"] = 1, ["attempts"] = new JsonObject() }, "partySize", snapshot, "town_EW3|party=1|encounter=false");
        var stored = Store(original, pending);
        var read = Read(stored);
        if (ReadString(read["attempts"]?["partySize"] as JsonObject, "status") != "pending" ||
            GetPendingObjective(read, snapshot) != "partySize" ||
            ReadString(stored, "existing") != "preserved")
            throw new AgentHostException("eyc-objective-attempt-memory-self-test-pending-roundtrip-failed", "A pending model-selected EYC objective must survive a same-Campaign checkpoint roundtrip without altering other fields.");

        var blocked = SetBlocked(read, "companions", "companion-route-unavailable", snapshot, "town_EW3|party=1|encounter=false");
        if (!GetBlockedObjectives(blocked, snapshot, "town_EW3|party=1|encounter=false").SetEquals(["companions"]) ||
            GetBlockedObjectives(blocked, snapshot, "town_EW6|party=1|encounter=false").Count != 0)
            throw new AgentHostException("eyc-objective-attempt-memory-self-test-block-fingerprint-failed", "A no-progress objective is blocked only while the original Journal and route fingerprint match.");

        if (Reconcile(blocked, snapshot, "town_EW6|party=1|encounter=false")["attempts"] is JsonObject reopened && reopened.ContainsKey("companions"))
            throw new AgentHostException("eyc-objective-attempt-memory-self-test-route-change-reconcile-failed", "A changed Native route fingerprint must remove a stale blocked route.");

        var progressed = (JsonObject)snapshot.DeepClone();
        progressed["partySize"]!["current"] = 2;
        if (GetPendingObjective(read, progressed) is not null || GetBlockedObjectives(blocked, progressed, "town_EW3|party=1|encounter=false").Count != 0)
            throw new AgentHostException("eyc-objective-attempt-memory-self-test-progress-clears-failure-failed", "Journal progress must make old pending/blocked attempt state stale.");

        var cleared = Remove(blocked, "companions");
        if ((cleared["attempts"] as JsonObject)?.ContainsKey("companions") == true || ReadInt(cleared, "schemaVersion") != 1)
            throw new AgentHostException("eyc-objective-attempt-memory-self-test-remove-failed", "Clearing one attempt must remove only its entry and retain the attempt memory schema.");

        ExpectReadReject(new JsonObject
        {
            ["schemaVersion"] = 1,
            ["attempts"] = new JsonObject
            {
                ["unlistedObjective"] = new JsonObject
                {
                    ["status"] = "blocked", ["termination"] = "route-unavailable",
                    ["journalFingerprint"] = AgentHostEycCompanionSearchMemory.BuildJournalFingerprint(snapshot),
                    ["journalSnapshot"] = snapshot.DeepClone(), ["nativeRouteFingerprint"] = "native-state"
                }
            }
        }, "eyc-objective-attempt-memory-invalid");
        ExpectReadReject(new JsonObject
        {
            ["schemaVersion"] = 1,
            ["attempts"] = new JsonObject
            {
                ["companions"] = new JsonObject
                {
                    ["status"] = "success", ["termination"] = "route-unavailable",
                    ["journalFingerprint"] = AgentHostEycCompanionSearchMemory.BuildJournalFingerprint(snapshot),
                    ["journalSnapshot"] = snapshot.DeepClone(), ["nativeRouteFingerprint"] = "native-state"
                }
            }
        }, "eyc-objective-attempt-memory-invalid");
        if (stored.ToJsonString().Contains("prompt", StringComparison.OrdinalIgnoreCase) ||
            stored.ToJsonString().Contains("credential", StringComparison.OrdinalIgnoreCase))
            throw new AgentHostException("eyc-objective-attempt-memory-self-test-raw-context-persisted", "Attempt memory may store only bounded route/Journals fields, never prompts or credentials.");

        return [new { scenario = "eyc-objective-attempt-memory-persists-pending-and-blocked-routes-and-reopens-only-after-journal-or-native-state-change", passed = true }];

        static void ExpectReadReject(JsonObject memory, string expectedCode)
        {
            try
            {
                _ = Read(new JsonObject { [PropertyName] = memory });
                throw new AgentHostException("eyc-objective-attempt-memory-self-test-invalid-read-accepted", "The objective-attempt codec accepted an unsupported attempt record.");
            }
            catch (AgentHostException exception) when (exception.Code == expectedCode) { }
        }
    }

    private static JsonObject BuildAttempt(string status, string termination, JsonObject journalSnapshot, string nativeRouteFingerprint) =>
        new()
        {
            ["status"] = status,
            ["termination"] = termination,
            ["journalFingerprint"] = AgentHostEycCompanionSearchMemory.BuildJournalFingerprint(journalSnapshot),
            ["journalSnapshot"] = journalSnapshot.DeepClone(),
            ["nativeRouteFingerprint"] = nativeRouteFingerprint
        };

    private static void ValidateAttemptInput(string objectiveId, JsonObject journalSnapshot, string nativeRouteFingerprint, string status)
    {
        if (!ObjectiveIds.Contains(objectiveId) || status is not ("pending" or "blocked") || string.IsNullOrWhiteSpace(nativeRouteFingerprint) || nativeRouteFingerprint.Length > 4096)
            throw new AgentHostException("eyc-objective-attempt-input-invalid", "The EYC attempt requires one current objective ID, a supported status, and a bounded Native route fingerprint.");
        _ = AgentHostEycCompanionSearchMemory.BuildJournalFingerprint(journalSnapshot);
    }

    private static string? ReadString(JsonObject? node, string name) =>
        node?[name] is JsonValue value && value.TryGetValue<string>(out var result) ? result : null;

    private static int ReadInt(JsonObject? node, string name) =>
        node?[name] is JsonValue value && value.TryGetValue<int>(out var result) ? result : 0;

    private static bool? ReadBoolean(JsonObject? node, string name) =>
        node?[name] is JsonValue value && value.TryGetValue<bool>(out var result) ? result : null;
}
