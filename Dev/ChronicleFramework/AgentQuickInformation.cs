using System;
using System.Linq;
using System.Reflection;
using System.Text;
using TaleWorlds.CampaignSystem.GameState;
using TaleWorlds.Core;
using TaleWorlds.Core.ViewModelCollection.Information;
using TaleWorlds.Localization;

namespace ChronicleFramework;

internal static class ChronicleAgentQuickInformation
{
    private const string GauntletGameNotificationTypeName = "TaleWorlds.MountAndBlade.GauntletUI.GauntletGameNotification";

    internal static string BuildJson()
    {
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("quickInformation requires the Campaign Map state");

        var timeModeBefore = TaleWorlds.CampaignSystem.Campaign.Current?.TimeControlMode.ToString();
        var campaignDayBefore = TaleWorlds.CampaignSystem.Campaign.Current == null ? (double?)null : TaleWorlds.CampaignSystem.CampaignTime.Now.ToDays;
        if (!TryGetNativeGameNotificationViewModel(out var viewModel))
            return BuildUnavailableJson(timeModeBefore, campaignDayBefore);

        var item = viewModel.CurrentNotification;
        var uiLayerPaused = viewModel.IsPaused;
        var currentIsDialog = item?.IsDialog ?? false;
        var visibleQuickInfo = viewModel.GotNotification && !uiLayerPaused && !currentIsDialog && item != null && !string.IsNullOrEmpty(item.GameNotificationText);

        var json = new StringBuilder(1024);
        json.Append('{').Append("\"schemaVersion\":1,\"available\":true");
        json.Append(",\"hasVisibleQuickInfo\":").Append(ChroniclePartyUpgradeAdapter.Bool(visibleQuickInfo));
        json.Append(",\"uiLayerPaused\":").Append(ChroniclePartyUpgradeAdapter.Bool(uiLayerPaused));
        json.Append(",\"currentIsDialog\":").Append(ChroniclePartyUpgradeAdapter.Bool(currentIsDialog));
        if (visibleQuickInfo)
        {
            json.Append(",\"notificationId\":").Append(viewModel.NotificationId);
            ChroniclePartyUpgradeAdapter.Property(json, "notificationText", item.GameNotificationText);
            ChroniclePartyUpgradeAdapter.Property(json, "announcerName", item.CharacterNameText);
            json.Append(",\"extraTimeInMs\":").Append(item.ExtraTimeInMs);
            json.Append(",\"nativeDisplayDurationSeconds\":").Append(viewModel.CurrentNotificationDurationInSeconds.ToString("F3", System.Globalization.CultureInfo.InvariantCulture));
            json.Append(",\"isFadingOut\":").Append(ChroniclePartyUpgradeAdapter.Bool(viewModel.MustFadeOutCurrentNotification));
            json.Append(",\"fadeOutDelaySeconds\":").Append(viewModel.CurrentNotificationFadeOutDelayInSeconds.ToString("F3", System.Globalization.CultureInfo.InvariantCulture));
        }
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeBefore", timeModeBefore);
        if (campaignDayBefore.HasValue) json.Append(",\"campaignDayBefore\":").Append(campaignDayBefore.Value.ToString("F6", System.Globalization.CultureInfo.InvariantCulture));
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeAfter", TaleWorlds.CampaignSystem.Campaign.Current?.TimeControlMode.ToString());
        if (TaleWorlds.CampaignSystem.Campaign.Current != null)
            json.Append(",\"campaignDayAfter\":").Append(TaleWorlds.CampaignSystem.CampaignTime.Now.ToDays.ToString("F6", System.Globalization.CultureInfo.InvariantCulture));
        return json.Append('}').ToString();
    }

    internal static string SeedHarnessFixture()
    {
        RequireVisualHarnessFixture();
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("harnessSeedQuickInformationFixture requires the Campaign Map state");
        if (!TryGetNativeGameNotificationViewModel(out _))
            throw new InvalidOperationException("Native GauntletGameNotification UI layer is not loaded in this Campaign");

        const int extraTimeInMs = 30000;
        const string currentText = "Chronicle Harness current QuickInfo; this message is visible only in the disposable process.";
        const string queuedText = "Chronicle Harness queued QuickInfo; the agent must not report this before it is displayed.";
        MBInformationManager.ClearQuickInformations();
        MBInformationManager.AddQuickInformation(new TextObject(currentText), extraTimeInMs);
        MBInformationManager.AddQuickInformation(new TextObject(queuedText), extraTimeInMs);
        return "{\"schemaVersion\":1,\"testOnly\":true,\"currentText\":\"" + Escape(currentText) +
            "\",\"queuedText\":\"" + Escape(queuedText) + "\",\"extraTimeInMs\":" + extraTimeInMs + "}";
    }

    private static bool TryGetNativeGameNotificationViewModel(out GameNotificationVM viewModel)
    {
        viewModel = null;
        var viewType = AppDomain.CurrentDomain.GetAssemblies()
            .Select(assembly => assembly.GetType(GauntletGameNotificationTypeName, throwOnError: false))
            .FirstOrDefault(type => type != null);
        if (viewType == null) return false;

        var currentProperty = viewType.GetProperty("Current", BindingFlags.Static | BindingFlags.NonPublic | BindingFlags.Public | BindingFlags.FlattenHierarchy);
        var currentView = currentProperty?.GetValue(null, null);
        if (currentView == null) return false;

        var dataSourceField = viewType.GetField("_dataSource", BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.FlattenHierarchy);
        viewModel = dataSourceField?.GetValue(currentView) as GameNotificationVM;
        return viewModel != null;
    }

    private static string BuildUnavailableJson(string timeMode, double? campaignDay)
    {
        var json = new StringBuilder(256);
        json.Append('{').Append("\"schemaVersion\":1,\"available\":false,\"hasVisibleQuickInfo\":false");
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeBefore", timeMode);
        if (campaignDay.HasValue) json.Append(",\"campaignDayBefore\":").Append(campaignDay.Value.ToString("F6", System.Globalization.CultureInfo.InvariantCulture));
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeAfter", TaleWorlds.CampaignSystem.Campaign.Current?.TimeControlMode.ToString());
        if (TaleWorlds.CampaignSystem.Campaign.Current != null)
            json.Append(",\"campaignDayAfter\":").Append(TaleWorlds.CampaignSystem.CampaignTime.Now.ToDays.ToString("F6", System.Globalization.CultureInfo.InvariantCulture));
        return json.Append('}').ToString();
    }

    private static void RequireVisualHarnessFixture()
    {
        if (!string.Equals(Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE"), "visual-capture", StringComparison.Ordinal) ||
            string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP")))
            throw new InvalidOperationException("Quick information fixture is restricted to visual Harness runs");
    }

    private static string Escape(string value) => (value ?? string.Empty).Replace("\\", "\\\\").Replace("\"", "\\\"");
}
