using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Text;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.CharacterDevelopment;
using TaleWorlds.CampaignSystem.GameState;
using TaleWorlds.CampaignSystem.MapNotificationTypes;
using TaleWorlds.CampaignSystem.ViewModelCollection.Map;
using TaleWorlds.CampaignSystem.ViewModelCollection.Map.MapNotificationTypes;
using TaleWorlds.Core;
using TaleWorlds.Localization;

namespace ChronicleFramework;

internal static class ChronicleAgentMapNotifications
{
    private sealed class HarnessUnregisteredNoticeData : InformationData
    {
        internal HarnessUnregisteredNoticeData(string description) : base(new TextObject(description)) { }
        public override TextObject TitleText => new TextObject("Harness-only unregistered notification");
        public override string SoundEventPath => string.Empty;
    }

    private sealed class HarnessInvalidNoticeData : InformationData
    {
        internal HarnessInvalidNoticeData(string description) : base(new TextObject(description)) { }
        public override TextObject TitleText => new TextObject("Harness-only invalid notification");
        public override string SoundEventPath => string.Empty;
        public override bool IsValid() => false;
    }

    internal static string BuildJson()
    {
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("mapNotifications requires the Campaign Map state");
        var campaign = Campaign.Current ?? throw new InvalidOperationException("mapNotifications requires an active Campaign");
        var notices = ReadManagerNotices(campaign.CampaignInformationManager)
            .Where(notice => notice != null && notice.IsValid())
            .ToArray();
        var timeModeBefore = campaign.TimeControlMode.ToString();
        var campaignDayBefore = CampaignTime.Now.ToDays;
        var viewModel = new MapNotificationVM(null, _ => { });

        try
        {
            foreach (var notice in notices) viewModel.AddMapNotification(notice);

            var json = new StringBuilder(2048);
            json.Append('{').Append("\"schemaVersion\":1");
            ChroniclePartyUpgradeAdapter.Property(json, "gameState", "MapState");
            ChroniclePartyUpgradeAdapter.Property(json, "menuId", campaign.CurrentMenuContext?.GameMenu?.StringId);
            ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeBefore", timeModeBefore);
            json.Append(",\"campaignDayBefore\":").Append(campaignDayBefore.ToString("F6", System.Globalization.CultureInfo.InvariantCulture));
            json.Append(",\"notifications\":[");
            var items = viewModel.NotificationItems.ToArray();
            for (var index = 0; index < items.Length; index++)
            {
                if (index > 0) json.Append(',');
                var item = items[index];
                json.Append('{').Append("\"index\":").Append(index);
                ChroniclePartyUpgradeAdapter.Property(json, "dataType", item.Data.GetType().Name);
                ChroniclePartyUpgradeAdapter.Property(json, "viewModelType", item.GetType().Name);
                ChroniclePartyUpgradeAdapter.Property(json, "notificationIdentifier", item.NotificationIdentifier);
                ChroniclePartyUpgradeAdapter.Property(json, "titleText", item.TitleText);
                ChroniclePartyUpgradeAdapter.Property(json, "descriptionText", item.DescriptionText);
                json.Append(",\"forceInspection\":").Append(ChroniclePartyUpgradeAdapter.Bool(item.ForceInspection));
                json.Append('}');
            }
            json.Append(']');
            json.Append(",\"notificationCount\":").Append(items.Length);
            ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeAfter", campaign.TimeControlMode.ToString());
            json.Append(",\"campaignDayAfter\":").Append(CampaignTime.Now.ToDays.ToString("F6", System.Globalization.CultureInfo.InvariantCulture));
            return json.Append('}').ToString();
        }
        finally
        {
            foreach (var item in viewModel.NotificationItems.ToArray()) item.OnFinalize();
            viewModel.OnFinalize();
        }
    }

    internal static string SeedHarnessFixture()
    {
        RequireVisualHarnessFixture();
        if (Game.Current?.GameStateManager?.ActiveState is not MapState || Campaign.Current == null)
            throw new InvalidOperationException("harnessSeedMapNotificationFixture requires the Campaign Map state");

        const string description = "Chronicle Harness Map Notification fixture; this message exists only in the disposable Campaign.";
        const string unsupportedDescription = "Chronicle Harness unregistered notice; it must not be exposed.";
        const string invalidDescription = "Chronicle Harness invalid notice; it must not be exposed.";
        var information = new TraitChangedMapNotification(DefaultTraits.Mercy, true, 0, new TextObject(description));
        var manager = Campaign.Current.CampaignInformationManager;
        manager.NewMapNoticeAdded(information);
        manager.NewMapNoticeAdded(new HarnessUnregisteredNoticeData(unsupportedDescription));
        manager.NewMapNoticeAdded(new HarnessInvalidNoticeData(invalidDescription));
        return "{\"schemaVersion\":1,\"testOnly\":true,\"type\":\"" + Escape(information.GetType().Name) +
            "\",\"descriptionText\":\"" + Escape(description) + "\",\"unregisteredDescriptionText\":\"" + Escape(unsupportedDescription) +
            "\",\"invalidDescriptionText\":\"" + Escape(invalidDescription) + "\"}";
    }

    private static IEnumerable<InformationData> ReadManagerNotices(CampaignInformationManager manager)
    {
        if (manager == null) throw new InvalidOperationException("CampaignInformationManager is unavailable");
        var field = typeof(CampaignInformationManager).GetField("_mapNotices", BindingFlags.Instance | BindingFlags.NonPublic);
        if (field?.GetValue(manager) is not IEnumerable<InformationData> notices)
            throw new InvalidOperationException("Native CampaignInformationManager map notice list is unavailable");
        return notices.ToArray();
    }

    private static void RequireVisualHarnessFixture()
    {
        if (!string.Equals(Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE"), "visual-capture", StringComparison.Ordinal) ||
            string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP")))
            throw new InvalidOperationException("Map notification fixture is restricted to visual Harness runs");
    }

    private static string Escape(string value) => (value ?? string.Empty).Replace("\\", "\\\\").Replace("\"", "\\\"");
}
