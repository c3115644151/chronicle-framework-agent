using System;
using System.Reflection;
using System.Text;
using System.Linq;
using TaleWorlds.CampaignSystem.GameState;
using TaleWorlds.Core;
using TaleWorlds.Library;

namespace ChronicleFramework;

internal static class ChronicleInquiryAdapter
{
    private const string QueryManagerTypeName = "TaleWorlds.MountAndBlade.GauntletUI.GauntletQueryManager";
    private const string QueryManagerAssemblyName = "TaleWorlds.MountAndBlade.GauntletUI";
    private const string SupportedInquiryVmTypeName = "TaleWorlds.MountAndBlade.ViewModelCollection.Inquiries.SingleQueryPopUpVM";
    private static readonly object Sync = new();
    private static bool _subscribed;
    private static long _eventGeneration;
    private static object _tokenData;
    private static long _tokenGeneration = -1;
    private static string _token;
    private static string _harnessFixtureChoice;

    internal static void EnsureLifecycleTracking()
    {
        lock (Sync)
        {
            if (_subscribed) return;
            InformationManager.OnShowInquiry += OnInquiryLifecycleChanged;
            InformationManager.OnShowTextInquiry += OnTextInquiryLifecycleChanged;
            InformationManager.OnHideInquiry += OnInquiryHidden;
            MBInformationManager.OnShowMultiSelectionInquiry += OnMultiInquiryLifecycleChanged;
            _subscribed = true;
        }
    }

    internal static bool IsInquiryOpen => InformationManager.IsAnyInquiryActive();

    internal static string BuildMapInquiryJson()
    {
        EnsureLifecycleTracking();
        if (!IsInquiryOpen) return "null";

        if (!TryReadNativeActiveQuery(out var queryData, out var dataSource, out var pauseGameActiveState, out var failure))
            return "{\"supported\":false,\"kind\":\"unavailable\",\"reason\":\"" + Escape(failure) + "\"}";

        var inquiryType = queryData?.GetType();
        var viewModelType = dataSource?.GetType();
        if (inquiryType != typeof(InquiryData) || viewModelType?.FullName != SupportedInquiryVmTypeName)
        {
            var unsupported = new StringBuilder(256);
            unsupported.Append("{\"supported\":false,\"kind\":\"").Append(Escape(inquiryType?.FullName ?? "unknown"));
            unsupported.Append("\",\"viewModel\":\"").Append(Escape(viewModelType?.FullName ?? "unknown")).Append("\"}");
            return unsupported.ToString();
        }

        var data = (InquiryData)queryData;
        var okVisible = ReadBool(dataSource, "IsButtonOkShown", data.IsAffirmativeOptionShown);
        var cancelVisible = ReadBool(dataSource, "IsButtonCancelShown", data.IsNegativeOptionShown);
        var okEnabled = ReadBool(dataSource, "IsButtonOkEnabled", IsOptionEnabled(data.GetIsAffirmativeOptionEnabled));
        var cancelEnabled = ReadBool(dataSource, "IsButtonCancelEnabled", IsOptionEnabled(data.GetIsNegativeOptionEnabled));
        lock (Sync)
        {
            if (!ReferenceEquals(_tokenData, data) || _tokenGeneration != _eventGeneration || string.IsNullOrEmpty(_token))
            {
                _tokenData = data;
                _tokenGeneration = _eventGeneration;
                _token = Guid.NewGuid().ToString("N");
            }
        }

        var json = new StringBuilder(512);
        json.Append("{\"supported\":true,\"kind\":\"YesNoInquiry\",\"token\":\"").Append(_token).Append('"');
        AppendProperty(json, "title", ReadString(dataSource, "TitleText") ?? data.TitleText);
        AppendProperty(json, "text", ReadString(dataSource, "PopUpLabel") ?? data.Text);
        json.Append(",\"affirmative\":{\"visible\":").Append(Bool(okVisible));
        json.Append(",\"enabled\":").Append(Bool(okVisible && okEnabled));
        AppendProperty(json, "text", ReadString(dataSource, "ButtonOkLabel") ?? data.AffirmativeText);
        json.Append('}');
        json.Append(",\"negative\":{\"visible\":").Append(Bool(cancelVisible));
        json.Append(",\"enabled\":").Append(Bool(cancelVisible && cancelEnabled));
        AppendProperty(json, "text", ReadString(dataSource, "ButtonCancelLabel") ?? data.NegativeText);
        json.Append('}');
        json.Append(",\"timerShown\":").Append(Bool(ReadBool(dataSource, "IsTimerShown", data.ExpireTime > 0f)));
        json.Append(",\"pauseGameActiveState\":").Append(Bool(pauseGameActiveState));
        json.Append('}');
        return json.ToString();
    }

    internal static string Respond(string token, string choice)
    {
        EnsureLifecycleTracking();
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("respondInquiry supports Native Campaign Map inquiries only");
        if (!IsInquiryOpen) throw new InvalidOperationException("respondInquiry requires a currently active Native Inquiry");
        if (!TryReadNativeActiveQuery(out var queryData, out var dataSource, out _, out var failure))
            throw new InvalidOperationException("Current Native Inquiry is unavailable: " + failure);
        if (queryData is not InquiryData inquiry || dataSource?.GetType().FullName != SupportedInquiryVmTypeName)
            throw new InvalidOperationException("respondInquiry supports only the currently displayed Native Yes/No Inquiry");

        string currentToken;
        lock (Sync)
        {
            if (!ReferenceEquals(_tokenData, inquiry) || _tokenGeneration != _eventGeneration || string.IsNullOrEmpty(_token))
            {
                _tokenData = inquiry;
                _tokenGeneration = _eventGeneration;
                _token = Guid.NewGuid().ToString("N");
            }
            currentToken = _token;
        }
        if (string.IsNullOrWhiteSpace(token) || !string.Equals(token, currentToken, StringComparison.Ordinal))
            throw new InvalidOperationException("Inquiry token is stale; observe the current Native Inquiry again before choosing");

        var methodName = choice switch
        {
            "affirmative" when ReadBool(dataSource, "IsButtonOkShown", inquiry.IsAffirmativeOptionShown) && ReadBool(dataSource, "IsButtonOkEnabled", IsOptionEnabled(inquiry.GetIsAffirmativeOptionEnabled)) => "ExecuteAffirmativeAction",
            "negative" when ReadBool(dataSource, "IsButtonCancelShown", inquiry.IsNegativeOptionShown) && ReadBool(dataSource, "IsButtonCancelEnabled", IsOptionEnabled(inquiry.GetIsNegativeOptionEnabled)) => "ExecuteNegativeAction",
            "affirmative" or "negative" => throw new InvalidOperationException("Requested Native Inquiry choice is not currently shown and enabled"),
            _ => throw new InvalidOperationException("InquiryChoice must be affirmative or negative")
        };
        var method = dataSource.GetType().GetMethod(methodName, BindingFlags.Instance | BindingFlags.Public, null, Type.EmptyTypes, null);
        if (method == null) throw new MissingMethodException(dataSource.GetType().FullName, methodName + "()" );
        method.Invoke(dataSource, null);
        if (IsInquiryOpen && ReferenceEquals(ReadActiveDataField(), inquiry))
            throw new InvalidOperationException("Native Inquiry ViewModel did not transition after its selected action");
        return "{\"schemaVersion\":1,\"choice\":\"" + choice + "\",\"nativeViewModelHandler\":\"" + methodName + "\"}";
    }

    internal static string BeginHarnessInquiryFixture()
    {
        EnsureLifecycleTracking();
        if (Game.Current?.GameStateManager?.ActiveState is not MapState || IsInquiryOpen)
            throw new InvalidOperationException("Harness Inquiry fixture requires a Campaign Map without another active Inquiry");
        _harnessFixtureChoice = null;
        var inquiry = new InquiryData(
            "Chronicle Harness Confirmation",
            "Choose one button to verify the Native active Inquiry loop.",
            isAffirmativeOptionShown: true,
            isNegativeOptionShown: true,
            affirmativeText: "Accept test choice",
            negativeText: "Decline test choice",
            affirmativeAction: () => _harnessFixtureChoice = "affirmative",
            negativeAction: () => _harnessFixtureChoice = "negative");
        InformationManager.ShowInquiry(inquiry, pauseGameActiveState: false, prioritize: true);
        return "{\"fixtureCreated\":" + Bool(IsInquiryOpen) + ",\"callbackCount\":0}";
    }

    internal static string BuildHarnessInquiryDiagnosticsJson() => "{\"lastChoice\":\"" + Escape(_harnessFixtureChoice) + "\"}";

    private static void OnInquiryLifecycleChanged(InquiryData data, bool pauseGameActiveState, bool prioritize) => InvalidateToken();
    private static void OnTextInquiryLifecycleChanged(TextInquiryData data, bool pauseGameActiveState, bool prioritize) => InvalidateToken();
    private static void OnMultiInquiryLifecycleChanged(MultiSelectionInquiryData data, bool pauseGameActiveState, bool prioritize) => InvalidateToken();
    private static void OnInquiryHidden() => InvalidateToken();

    private static void InvalidateToken()
    {
        lock (Sync) _eventGeneration++;
    }

    private static bool TryReadNativeActiveQuery(out object queryData, out object dataSource, out bool pauseGameActiveState, out string failure)
    {
        queryData = null;
        dataSource = null;
        pauseGameActiveState = false;
        failure = null;
        var assemblies = AppDomain.CurrentDomain.GetAssemblies();
        var assembly = assemblies.FirstOrDefault(item => string.Equals(item.GetName().Name, QueryManagerAssemblyName, StringComparison.Ordinal));
        var managerType = assembly?.GetType(QueryManagerTypeName, throwOnError: false);
        if (managerType == null)
        {
            failure = "Native GauntletQueryManager type is unavailable";
            return false;
        }
        var dataField = managerType.GetField("_activeQueryData", BindingFlags.Static | BindingFlags.NonPublic);
        var sourceField = managerType.GetField("_activeDataSource", BindingFlags.Static | BindingFlags.NonPublic);
        var pauseField = managerType.GetField("_isLastActiveGameStatePaused", BindingFlags.Instance | BindingFlags.NonPublic);
        if (dataField == null || sourceField == null || pauseField == null)
        {
            failure = "Native active Inquiry fields do not match the verified 1.4.8 contract";
            return false;
        }
        queryData = dataField.GetValue(null);
        dataSource = sourceField.GetValue(null);
        var moduleType = Type.GetType("TaleWorlds.MountAndBlade.GauntletUI.GauntletUISubModule, " + QueryManagerAssemblyName, throwOnError: false);
        var moduleSingleton = moduleType?.GetProperty("Instance", BindingFlags.Static | BindingFlags.Public)?.GetValue(null);
        var queryManagerInstanceField = moduleType?.GetField("_queryManager", BindingFlags.Instance | BindingFlags.NonPublic);
        var managerInstance = moduleSingleton != null ? queryManagerInstanceField?.GetValue(moduleSingleton) : null;
        pauseGameActiveState = managerInstance != null && pauseField.GetValue(managerInstance) is bool paused && paused;
        if (queryData == null || dataSource == null)
        {
            failure = "Native Inquiry is queued or its active ViewModel is not ready";
            return false;
        }
        return true;
    }

    private static object ReadActiveDataField() => TryReadNativeActiveQuery(out var data, out _, out _, out _) ? data : null;
    private static bool IsOptionEnabled(Func<(bool, string)> predicate) => predicate == null || predicate().Item1;

    private static bool ReadBool(object instance, string propertyName, bool fallback)
    {
        var value = instance?.GetType().GetProperty(propertyName, BindingFlags.Instance | BindingFlags.Public)?.GetValue(instance);
        return value is bool boolean ? boolean : fallback;
    }

    private static string ReadString(object instance, string propertyName) => instance?.GetType().GetProperty(propertyName, BindingFlags.Instance | BindingFlags.Public)?.GetValue(instance) as string;
    private static string Bool(bool value) => value ? "true" : "false";
    private static void AppendProperty(StringBuilder json, string key, string value) => json.Append(",\"").Append(key).Append("\":\"").Append(Escape(value)).Append('"');
    private static string Escape(string value) => (value ?? string.Empty).Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\r", "\\r").Replace("\n", "\\n");
}
