using System;
using System.IO;
using System.Text;
using Newtonsoft.Json.Linq;

namespace ChronicleFramework;

// The mod side of the agent control channel. The Host honours this file before every Native action, so handing
// control to the player is a pause that the agent respects instead of an in-flight order that races the player.
internal static class ChronicleAgentControlChannel
{
    internal const string ControlFileName = "agent-control.json";
    internal const string LiveStatusFileName = "agent-live-status.json";
    internal const string PlayerTakeoverReason = "player-takeover";
    internal const string EscapeMenuReason = "escape-menu";
    private static bool _holdWritten;
    private static string _holdReason = string.Empty;

    internal static string ProtocolRoot() =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "Mount and Blade II Bannerlord", "AgentRuns", "ChronicleAgent");

    internal static string ControlPath() => Path.Combine(ProtocolRoot(), ControlFileName);

    internal static string LiveStatusPath() => Path.Combine(ProtocolRoot(), LiveStatusFileName);

    // Returns true when the requested state was already in place, so callers can stay off the disk every tick.
    internal static bool SetHold(bool hold, string reason)
    {
        var normalized = string.IsNullOrWhiteSpace(reason) ? PlayerTakeoverReason : reason;
        if (_holdWritten && _holdReason == normalized) return true;
        try
        {
            var path = ControlPath();
            var directory = Path.GetDirectoryName(path);
            if (!string.IsNullOrWhiteSpace(directory)) Directory.CreateDirectory(directory);
            var document = new JObject
            {
                ["hold"] = hold,
                ["reason"] = normalized,
                ["utc"] = DateTime.UtcNow.ToString("O")
            };
            var temporary = path + ".tmp";
            File.WriteAllText(temporary, document.ToString(Newtonsoft.Json.Formatting.None), new UTF8Encoding(false));
            File.Copy(temporary, path, overwrite: true);
            File.Delete(temporary);
            _holdWritten = true;
            _holdReason = normalized;
            ChronicleDiagnostics.Write("agent-control-hold|hold=" + hold + "|reason=" + normalized);
            return true;
        }
        catch (Exception exception)
        {
            ChronicleDiagnostics.Write("agent-control-hold-failed|type=" + exception.GetType().Name);
            return false;
        }
    }

    internal static void ClearHold()
    {
        SetHold(false, PlayerTakeoverReason);
    }

    internal static string DescribeHoldBody(string status) =>
        status == "held" ? "AI 已暂停 · 等待玩家交还控制" : "AI 已暂停";
}
