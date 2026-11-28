using System.Text.Json;
using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

// The player can take the reins at any moment. This channel is how the mod tells the Host to hold still before
// its next Native action, so a takeover never races an in-flight order.
internal static class AgentHostControlHold
{
    internal const string ControlFileName = "agent-control.json";
    internal const int PollMilliseconds = 250;
    internal const int MaximumReasonLength = 96;
    internal const string PlayerTakeoverReason = "player-takeover";
    internal const string EscapeMenuReason = "escape-menu";

    internal static string GetControlPath(string protocolRoot) => Path.Combine(protocolRoot, ControlFileName);

    internal static bool TryReadHold(string protocolRoot, out string reason)
    {
        reason = string.Empty;
        try
        {
            var path = GetControlPath(protocolRoot);
            if (!File.Exists(path)) return false;
            var text = File.ReadAllText(path);
            if (string.IsNullOrWhiteSpace(text)) return false;
            if (JsonNode.Parse(text) is not JsonObject document) return false;
            if (document["hold"] is not JsonValue value || !value.TryGetValue<bool>(out var hold) || !hold) return false;
            reason = SanitizeReason(document["reason"]?.ToString());
            return true;
        }
        catch
        {
            return false;
        }
    }

    internal static string SanitizeReason(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return PlayerTakeoverReason;
        var trimmed = raw.Trim();
        return trimmed.Length <= MaximumReasonLength ? trimmed : trimmed.Substring(0, MaximumReasonLength);
    }

    // Observation reads stay live while the agent is held so the panel keeps showing the current Native state.
    internal static bool AppliesToAction(string action) =>
        !string.Equals(action, "state", StringComparison.Ordinal);

    internal static async Task WaitWhileHeldAsync(string protocolRoot, CancellationToken cancellationToken)
    {
        var announced = false;
        while (TryReadHold(protocolRoot, out var reason))
        {
            if (!announced)
            {
                announced = true;
                AgentHostLiveStatus.RecordHold(reason);
            }
            await Task.Delay(PollMilliseconds, cancellationToken).ConfigureAwait(false);
        }
        if (announced) AgentHostLiveStatus.RecordHoldReleased();
    }

    internal static IReadOnlyList<object> RunContractSelfTests()
    {
        var directory = Path.Combine(Path.GetTempPath(), "ChronicleControlHold-" + Guid.NewGuid().ToString("N"));
        try
        {
            Directory.CreateDirectory(directory);
            if (TryReadHold(directory, out _))
                throw new AgentHostException("control-hold-missing-file", "A missing control file must never hold the agent.");

            var path = GetControlPath(directory);
            File.WriteAllText(path, new JsonObject { ["hold"] = false, ["reason"] = PlayerTakeoverReason }.ToJsonString());
            if (TryReadHold(directory, out _))
                throw new AgentHostException("control-hold-released-file", "hold=false must release the agent instead of stalling it.");

            File.WriteAllText(path, new JsonObject { ["hold"] = true, ["reason"] = EscapeMenuReason }.ToJsonString());
            if (!TryReadHold(directory, out var reason) || reason != EscapeMenuReason)
                throw new AgentHostException("control-hold-active-file", "An active hold must be reported with its reason so the panel can explain the pause.");

            File.WriteAllText(path, "{ not json");
            if (TryReadHold(directory, out _))
                throw new AgentHostException("control-hold-unparsable-file", "A damaged control file must fail safe by letting the agent continue.");

            if (SanitizeReason(new string('x', MaximumReasonLength + 40)).Length != MaximumReasonLength)
                throw new AgentHostException("control-hold-reason-length", "Hold reasons must be bounded before they reach the live status snapshot.");
            if (!AppliesToAction("move") || AppliesToAction("state"))
                throw new AgentHostException("control-hold-action-scope", "Holding must gate Native actions while leaving observation reads live.");
        }
        finally
        {
            try { Directory.Delete(directory, recursive: true); } catch { }
        }

        return [new { scenario = "control-hold-fails-safe-and-leaves-observation-live", passed = true }];
    }
}
