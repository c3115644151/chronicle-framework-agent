using System;
using System.Globalization;

namespace ChronicleFramework;

internal static class AgentHostReadyProtocol
{
    internal const string Prefix = "CHRONICLE_AGENT_HOST_READY|";

    internal static string Format(int nativeProcessId, string runId, string version)
    {
        if (nativeProcessId <= 0 || !IsToken(runId) || !IsToken(version))
            throw new ArgumentException("Host ready identity is incomplete or contains protocol separators.");
        return Prefix + "1|" + nativeProcessId.ToString(CultureInfo.InvariantCulture) + "|" + runId + "|" + version;
    }

    internal static bool TryParse(string line, out int nativeProcessId, out string runId, out string version)
    {
        nativeProcessId = 0;
        runId = string.Empty;
        version = string.Empty;
        if (line == null || !line.StartsWith(Prefix, StringComparison.Ordinal)) return false;
        var fields = line.Substring(Prefix.Length).Split('|');
        if (fields.Length != 4 || fields[0] != "1" ||
            !int.TryParse(fields[1], NumberStyles.None, CultureInfo.InvariantCulture, out var parsedId) || parsedId <= 0 ||
            !IsToken(fields[2]) || !IsToken(fields[3])) return false;
        nativeProcessId = parsedId;
        runId = fields[2];
        version = fields[3];
        return true;
    }

    private static bool IsToken(string value) => !string.IsNullOrWhiteSpace(value) && value.Length <= 128 &&
        value.IndexOfAny(new[] { '|', '\r', '\n' }) < 0;
}
