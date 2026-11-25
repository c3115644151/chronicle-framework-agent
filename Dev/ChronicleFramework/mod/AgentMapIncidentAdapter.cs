#nullable enable
using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Reflection;
using System.Text;
using TaleWorlds.CampaignSystem.CampaignBehaviors;
using SandBox.View.Map;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.GameState;
using TaleWorlds.CampaignSystem.Incidents;
using TaleWorlds.Core;
using TaleWorlds.MountAndBlade;

namespace ChronicleFramework;

internal static class ChronicleAgentMapIncidentAdapter
{
    private const BindingFlags InstanceFlags = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;

    internal static string SeedHarnessFixture()
    {
        if (!string.Equals(Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE"), "visual-capture", StringComparison.Ordinal) ||
            string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP")))
            throw new InvalidOperationException("harnessSeedMapIncidentFixture is restricted to a disposable visual Harness run");
        if (Game.Current?.GameStateManager?.ActiveState is not MapState mapState || MapScreen.Instance == null)
            throw new InvalidOperationException("harnessSeedMapIncidentFixture requires the original Campaign Map and MapScreen");
        if (IsActive()) throw new InvalidOperationException("harnessSeedMapIncidentFixture requires no existing Native Map Incident");

        var incident = new Incident("chronicle_harness_modal_input_guard");
        incident.Initialize(
            "Chronicle Harness input guard",
            "This harmless disposable modal verifies that map movement cannot bypass the original Native Incident UI.",
            IncidentsCampaignBehaviour.IncidentTrigger.LeavingTown,
            IncidentsCampaignBehaviour.IncidentType.PlightOfCivilians,
            CampaignTime.Hours(1f),
            _ => true);
        incident.AddOption("Close harness incident (no campaign effects)", new List<IncidentEffect>());
        mapState.StartIncident(incident);

        var observation = BuildJson();
        if (!IsActive()) throw new InvalidOperationException("The original MapState did not activate the disposable Native Map Incident view");
        return "{\"schemaVersion\":1,\"testOnly\":true,\"type\":\"PlightOfCivilians\",\"observation\":" + observation + "}";
    }

    internal static bool IsActive()
    {
        if (Game.Current?.GameStateManager?.ActiveState is not MapState) return false;
        var mapScreen = MapScreen.Instance;
        return mapScreen != null && (mapScreen.IsMapIncidentActive || mapScreen.GetMapView<MapIncidentView>() != null);
    }

    internal static string BuildJson()
    {
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            return "{\"schemaVersion\":1,\"active\":false,\"supported\":false,\"reason\":\"not-map-state\"}";

        var mapScreen = MapScreen.Instance;
        if (mapScreen == null)
            return "{\"schemaVersion\":1,\"active\":false,\"supported\":false,\"reason\":\"map-screen-unavailable\"}";

        var view = mapScreen.GetMapView<MapIncidentView>();
        if (!mapScreen.IsMapIncidentActive && view == null)
            return "{\"schemaVersion\":1,\"active\":false,\"supported\":true}";
        if (view == null)
            return "{\"schemaVersion\":1,\"active\":true,\"supported\":false,\"reason\":\"incident-view-missing\"}";
        if (!TryGetViewModel(view, out var viewModel, out var failure))
            return "{\"schemaVersion\":1,\"active\":true,\"supported\":false,\"reason\":\"" + Escape(failure) + "\"}";

        var options = ReadOptions(viewModel);
        var json = new StringBuilder(512);
        json.Append("{\"schemaVersion\":1,\"active\":true,\"supported\":true");
        AppendString(json, "incidentType", ReadString(viewModel, "IncidentType"));
        AppendString(json, "title", ReadString(viewModel, "Title"));
        AppendString(json, "description", ReadString(viewModel, "Description"));
        AppendString(json, "confirmText", ReadString(viewModel, "ConfirmText"));
        json.Append(",\"canConfirm\":").Append(ReadBoolean(viewModel, "CanConfirm") ? "true" : "false");
        json.Append(",\"selectedOptionIndex\":").Append(ReadOptionIndex(ReadProperty(viewModel, "SelectedOption")));
        json.Append(",\"options\":[");
        for (var index = 0; index < options.Count; index++)
        {
            if (index > 0) json.Append(',');
            var option = options[index];
            json.Append("{\"index\":").Append(ReadIndex(option));
            AppendString(json, "text", ReadString(option, "Description"));
            AppendString(json, "hint", ReadString(option, "Hint"));
            json.Append(",\"selected\":").Append(ReadBoolean(option, "IsSelected") ? "true" : "false");
            json.Append(",\"focused\":").Append(ReadBoolean(option, "IsFocused") ? "true" : "false").Append('}');
        }
        json.Append("]}");
        return json.ToString();
    }

    internal static string SelectAndConfirm(int optionIndex)
    {
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("incidentSelect requires the Native Campaign Map state");

        var mapScreen = MapScreen.Instance;
        var view = mapScreen?.GetMapView<MapIncidentView>();
        if (mapScreen == null || !mapScreen.IsMapIncidentActive || view == null)
            throw new InvalidOperationException("incidentSelect requires the currently active Native Map Incident view");
        if (!TryGetViewModel(view, out var viewModel, out var failure))
            throw new InvalidOperationException("incidentSelect cannot access the current Native Incident VM: " + failure);

        var options = ReadOptions(viewModel);
        var selectedOption = options.Find(option => ReadIndex(option) == optionIndex);
        if (optionIndex < 0 || selectedOption == null)
            throw new InvalidOperationException("incidentSelect requires an option index from the current Native Incident VM");

        var title = ReadString(viewModel, "Title");
        var incidentType = ReadString(viewModel, "IncidentType");
        var optionText = ReadString(selectedOption, "Description");
        var dayBefore = CampaignTime.Now.ToDays;
        var timeModeBefore = Campaign.Current?.TimeControlMode.ToString() ?? "unknown";
        var timeLockBefore = Campaign.Current?.TimeControlModeLock ?? false;

        InvokeRequired(selectedOption, "ExecuteSelect");
        if (ReadOptionIndex(ReadProperty(viewModel, "SelectedOption")) != optionIndex || !ReadBoolean(viewModel, "CanConfirm"))
            throw new InvalidOperationException("The Native Incident VM did not accept the current option selection");

        InvokeRequired(viewModel, "ExecuteConfirm");

        var currentView = MapScreen.Instance?.GetMapView<MapIncidentView>();
        var sameIncidentViewRemains = ReferenceEquals(currentView, view);
        var dayAfter = CampaignTime.Now.ToDays;
        var timeModeAfter = Campaign.Current?.TimeControlMode.ToString() ?? "unknown";
        var timeLockAfter = Campaign.Current?.TimeControlModeLock ?? false;
        var json = new StringBuilder(384);
        json.Append("{\"schemaVersion\":1,\"submitted\":true,\"incidentType\":\"").Append(Escape(incidentType)).Append('\"');
        json.Append(",\"title\":\"").Append(Escape(title)).Append('\"');
        json.Append(",\"optionIndex\":").Append(optionIndex.ToString(CultureInfo.InvariantCulture));
        json.Append(",\"optionText\":\"").Append(Escape(optionText)).Append('\"');
        json.Append(",\"sameIncidentViewRemains\":").Append(sameIncidentViewRemains ? "true" : "false");
        json.Append(",\"campaignDayBefore\":").Append(dayBefore.ToString("F3", CultureInfo.InvariantCulture));
        json.Append(",\"campaignDayAfter\":").Append(dayAfter.ToString("F3", CultureInfo.InvariantCulture));
        json.Append(",\"timeControlModeBefore\":\"").Append(Escape(timeModeBefore)).Append('\"');
        json.Append(",\"timeControlModeAfter\":\"").Append(Escape(timeModeAfter)).Append('\"');
        json.Append(",\"timeControlModeLockBefore\":").Append(timeLockBefore ? "true" : "false");
        json.Append(",\"timeControlModeLockAfter\":").Append(timeLockAfter ? "true" : "false").Append('}');
        return json.ToString();
    }

    private static bool TryGetViewModel(MapIncidentView view, out object viewModel, out string failure)
    {
        Type? type = view.GetType();
        while (type != null)
        {
            var field = type.GetField("_dataSource", InstanceFlags);
            if (field?.GetValue(view) is object value)
            {
                if (!string.Equals(value.GetType().FullName, "SandBox.ViewModelCollection.Map.Incidents.MapIncidentVM", StringComparison.Ordinal))
                {
                    viewModel = null!;
                    failure = "unexpected-view-model-type";
                    return false;
                }
                viewModel = value;
                failure = string.Empty;
                return true;
            }
            type = type.BaseType;
        }
        viewModel = null!;
        failure = "native-incident-view-model-unavailable";
        return false;
    }

    private static List<object> ReadOptions(object viewModel)
    {
        var values = ReadProperty(viewModel, "Options") as IEnumerable;
        var options = new List<object>();
        if (values == null) return options;
        foreach (var option in values)
            if (option != null) options.Add(option);
        return options;
    }

    private static object? ReadProperty(object? target, string name) =>
        target?.GetType().GetProperty(name, InstanceFlags)?.GetValue(target);

    private static string? ReadString(object? target, string name) => ReadProperty(target, name)?.ToString();

    private static bool ReadBoolean(object? target, string name) => ReadProperty(target, name) is bool value && value;

    private static int ReadIndex(object target)
    {
        var value = target.GetType().GetField("Index", InstanceFlags)?.GetValue(target);
        return value is int index ? index : -1;
    }

    private static int ReadOptionIndex(object? option) => option == null ? -1 : ReadIndex(option);

    private static void InvokeRequired(object target, string methodName)
    {
        var method = target.GetType().GetMethod(methodName, InstanceFlags, null, Type.EmptyTypes, null);
        if (method == null) throw new InvalidOperationException("The Native Incident VM handler is unavailable: " + methodName);
        try { method.Invoke(target, null); }
        catch (TargetInvocationException exception) when (exception.InnerException != null)
        {
            throw new InvalidOperationException("The Native Incident VM handler failed: " + methodName, exception.InnerException);
        }
    }

    private static void AppendString(StringBuilder json, string name, string? value) =>
        json.Append(",\"").Append(name).Append("\":\"").Append(Escape(value)).Append('\"');

    private static string Escape(string? value)
    {
        var text = value ?? string.Empty;
        if (text.Length == 0) return string.Empty;
        var builder = new StringBuilder(text.Length + 8);
        foreach (var character in text)
        {
            switch (character)
            {
                case '\\': builder.Append("\\\\"); break;
                case '"': builder.Append("\\\""); break;
                case '\n': builder.Append("\\n"); break;
                case '\r': builder.Append("\\r"); break;
                case '\t': builder.Append("\\t"); break;
                default:
                    if (character < 0x20) builder.Append("\\u").Append(((int)character).ToString("X4", CultureInfo.InvariantCulture));
                    else builder.Append(character);
                    break;
            }
        }
        return builder.ToString();
    }
}
