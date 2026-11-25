using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using SandBox;
using SandBox.View.Map;
using SandBox.View.Map.Managers;
using SandBox.View.Map.Visuals;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.Encounters;
using TaleWorlds.CampaignSystem.GameState;
using TaleWorlds.CampaignSystem.GameMenus;
using TaleWorlds.CampaignSystem.Issues;
using TaleWorlds.CampaignSystem.MapEvents;
using TaleWorlds.CampaignSystem.Party;
using TaleWorlds.CampaignSystem.Settlements;
using TaleWorlds.CampaignSystem.Settlements.Locations;
using TaleWorlds.CampaignSystem.ViewModelCollection.GameMenu.Recruitment;
using TaleWorlds.CampaignSystem.ViewModelCollection.GameMenu.Events;
using TaleWorlds.Core;
using TaleWorlds.InputSystem;
using TaleWorlds.MountAndBlade;
using TaleWorlds.MountAndBlade.View.MissionViews;
using EngineTime = TaleWorlds.Engine.Time;

namespace ChronicleFramework;

internal sealed partial class ChronicleAgentProtocol
{
    private static string ReadString(string json, string key)
    {
        var marker = "\"" + key + "\":\"";
        var start = json.IndexOf(marker, StringComparison.Ordinal);
        if (start < 0) return null;
        start += marker.Length;
        var end = json.IndexOf('"', start);
        return end < 0 ? null : json.Substring(start, end - start);
    }

    private static string[] ReadStringArray(string json, string key)
    {
        var marker = "\"" + key + "\":[";
        var start = json.IndexOf(marker, StringComparison.Ordinal);
        if (start < 0) return Array.Empty<string>();
        start += marker.Length;
        var end = json.IndexOf(']', start);
        if (end < 0) throw new InvalidOperationException("Array value '" + key + "' is not closed");
        var contents = json.Substring(start, end - start).Trim();
        if (contents.Length == 0) return Array.Empty<string>();
        var values = contents.Split(',');
        var result = new string[values.Length];
        for (var index = 0; index < values.Length; index++)
        {
            var value = values[index].Trim();
            if (value.Length < 2 || value[0] != '"' || value[value.Length - 1] != '"' || value.Substring(1, value.Length - 2).Contains('\\'))
                throw new InvalidOperationException("Array value '" + key + "' must contain plain string IDs without escape sequences");
            result[index] = value.Substring(1, value.Length - 2);
        }
        return result;
    }

    private static double ReadDouble(string json, string key)
    {
        var marker = "\"" + key + "\":";
        var start = json.IndexOf(marker, StringComparison.Ordinal);
        if (start < 0) return 0;
        start += marker.Length;
        var end = json.IndexOfAny(new[] { ',', '}' }, start);
        var value = json.Substring(start, end < 0 ? json.Length - start : end - start);
        return double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out var parsed) ? parsed : 0;
    }

    private static double ReadRequiredFiniteDouble(string json, string key)
    {
        var marker = "\"" + key + "\":";
        var start = json.IndexOf(marker, StringComparison.Ordinal);
        if (start < 0) throw new InvalidOperationException("Missing required coordinate '" + key + "'");
        start += marker.Length;
        var end = json.IndexOfAny(new[] { ',', '}' }, start);
        var value = json.Substring(start, end < 0 ? json.Length - start : end - start);
        if (!double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out var parsed) || double.IsNaN(parsed) || double.IsInfinity(parsed))
            throw new InvalidOperationException("Coordinate '" + key + "' must be a finite number");
        if (parsed > float.MaxValue || parsed < -float.MaxValue)
            throw new InvalidOperationException("Coordinate '" + key + "' exceeds the Campaign map numeric range");
        return parsed;
    }

    private static int ReadRequiredInteger(string json, string key)
    {
        var parsed = ReadRequiredFiniteDouble(json, key);
        if (parsed < int.MinValue || parsed > int.MaxValue || parsed != Math.Truncate(parsed))
            throw new InvalidOperationException("value '" + key + "' must be an integer");
        return (int)parsed;
    }

    internal static string Escape(string value)
    {
        if (string.IsNullOrEmpty(value)) return string.Empty;
        var builder = new StringBuilder(value.Length + 8);
        foreach (var character in value)
        {
            switch (character)
            {
                case '\\': builder.Append("\\\\"); break;
                case '"': builder.Append("\\\""); break;
                case '\b': builder.Append("\\b"); break;
                case '\f': builder.Append("\\f"); break;
                case '\n': builder.Append("\\n"); break;
                case '\r': builder.Append("\\r"); break;
                case '\t': builder.Append("\\t"); break;
                default:
                    if (character < 0x20) builder.Append("\\u").Append(((int)character).ToString("x4", CultureInfo.InvariantCulture));
                    else builder.Append(character);
                    break;
            }
        }
        return builder.ToString();
    }
}
