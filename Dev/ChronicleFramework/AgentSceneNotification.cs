using System;
using System.Linq;
using System.Reflection;
using System.Text;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.GameState;
using TaleWorlds.CampaignSystem.SceneInformationPopupTypes;
using TaleWorlds.Core;
using TaleWorlds.Core.ViewModelCollection.Information;
using TaleWorlds.Localization;

namespace ChronicleFramework;

internal static class ChronicleAgentSceneNotification
{
    private const string GauntletSceneNotificationTypeName = "TaleWorlds.MountAndBlade.GauntletUI.SceneNotification.GauntletSceneNotification";

    internal static string BuildJson()
    {
        var timeModeBefore = Campaign.Current?.TimeControlMode.ToString();
        var campaignDayBefore = Campaign.Current == null ? (double?)null : CampaignTime.Now.ToDays;
        if (!TryGetNativeSceneNotification(out var available, out var isActive, out var viewModel))
            return BuildEmptyJson(available, isActive: false, null, timeModeBefore, campaignDayBefore);

        var data = viewModel?.ActiveData;
        var isShown = viewModel?.IsShown == true;
        var hasActiveNotification = isActive && isShown && data != null;
        var json = new StringBuilder(1024);
        json.Append('{').Append("\"schemaVersion\":1");
        json.Append(",\"available\":true");
        json.Append(",\"hasActiveNotification\":").Append(ChroniclePartyUpgradeAdapter.Bool(hasActiveNotification));
        json.Append(",\"isShown\":").Append(ChroniclePartyUpgradeAdapter.Bool(isShown));
        json.Append(",\"isReady\":").Append(ChroniclePartyUpgradeAdapter.Bool(viewModel?.IsReady == true));
        if (hasActiveNotification)
        {
            ChroniclePartyUpgradeAdapter.Property(json, "dataType", data.GetType().Name);
            ChroniclePartyUpgradeAdapter.Property(json, "titleText", viewModel.TitleText);
            ChroniclePartyUpgradeAdapter.Property(json, "affirmativeTitleText", viewModel.AffirmativeTitleText);
            ChroniclePartyUpgradeAdapter.Property(json, "affirmativeDescription", viewModel.AffirmativeDescription);
            ChroniclePartyUpgradeAdapter.Property(json, "affirmativeButtonLabel", viewModel.ButtonOkLabel);
            json.Append(",\"affirmativeButtonShown\":").Append(ChroniclePartyUpgradeAdapter.Bool(viewModel.IsButtonOkShown));
            ChroniclePartyUpgradeAdapter.Property(json, "negativeTitleText", viewModel.NegativeTitleText);
            ChroniclePartyUpgradeAdapter.Property(json, "negativeDescription", viewModel.CancelDescription);
            ChroniclePartyUpgradeAdapter.Property(json, "negativeButtonLabel", viewModel.ButtonCancelLabel);
            json.Append(",\"negativeButtonShown\":").Append(ChroniclePartyUpgradeAdapter.Bool(viewModel.IsButtonCancelShown));
            ChroniclePartyUpgradeAdapter.Property(json, "clickToContinueText", viewModel.ClickToContinueText);
        }
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeBefore", timeModeBefore);
        if (campaignDayBefore.HasValue) json.Append(",\"campaignDayBefore\":").Append(campaignDayBefore.Value.ToString("F6", System.Globalization.CultureInfo.InvariantCulture));
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeAfter", Campaign.Current?.TimeControlMode.ToString());
        if (Campaign.Current != null) json.Append(",\"campaignDayAfter\":").Append(CampaignTime.Now.ToDays.ToString("F6", System.Globalization.CultureInfo.InvariantCulture));
        return json.Append('}').ToString();
    }

    internal static string SeedHarnessFixture()
    {
        RequireVisualHarnessFixture();
        if (Game.Current?.GameStateManager?.ActiveState is not MapState || Campaign.Current == null || Hero.MainHero == null)
            throw new InvalidOperationException("harnessSeedSceneNotificationFixture requires an active Campaign Map and MainHero");
        if (!TryGetNativeSceneNotification(out var available, out var isActive, out _))
            throw new InvalidOperationException("Native GauntletSceneNotification UI layer is unavailable");
        if (isActive) throw new InvalidOperationException("Harness scene notification fixture requires no active scene notification");

        var target = Hero.AllAliveHeroes.FirstOrDefault(hero => hero != Hero.MainHero);
        if (target == null) throw new InvalidOperationException("No other living Hero is available for the informative native notification fixture");
        var data = HeroExecutionSceneNotificationData.CreateForInformingPlayer(
            Hero.MainHero,
            target,
            SceneNotificationData.RelevantContextType.Map,
            onClose: null);
        MBInformationManager.ShowSceneNotification(data);

        var json = new StringBuilder(512);
        json.Append('{').Append("\"schemaVersion\":1,\"testOnly\":true");
        ChroniclePartyUpgradeAdapter.Property(json, "type", data.GetType().Name);
        ChroniclePartyUpgradeAdapter.Property(json, "titleText", data.TitleText?.ToString());
        ChroniclePartyUpgradeAdapter.Property(json, "affirmativeTitleText", data.AffirmativeTitleText?.ToString());
        ChroniclePartyUpgradeAdapter.Property(json, "affirmativeDescription", data.AffirmativeDescriptionText?.ToString());
        ChroniclePartyUpgradeAdapter.Property(json, "affirmativeButtonLabel", data.AffirmativeText?.ToString());
        json.Append(",\"affirmativeButtonShown\":").Append(ChroniclePartyUpgradeAdapter.Bool(data.IsAffirmativeOptionShown));
        ChroniclePartyUpgradeAdapter.Property(json, "negativeTitleText", data.NegativeTitleText?.ToString());
        ChroniclePartyUpgradeAdapter.Property(json, "negativeDescription", data.NegativeDescriptionText?.ToString());
        ChroniclePartyUpgradeAdapter.Property(json, "negativeButtonLabel", data.NegativeText?.ToString());
        json.Append(",\"negativeButtonShown\":").Append(ChroniclePartyUpgradeAdapter.Bool(data.IsNegativeOptionShown));
        ChroniclePartyUpgradeAdapter.Property(json, "testTargetHeroId", target.StringId);
        json.Append(",\"callbackWasExecuted\":false}");
        return json.ToString();
    }

    private static bool TryGetNativeSceneNotification(out bool available, out bool isActive, out SceneNotificationVM viewModel)
    {
        available = false;
        isActive = false;
        viewModel = null;
        var viewType = AppDomain.CurrentDomain.GetAssemblies()
            .Select(assembly => assembly.GetType(GauntletSceneNotificationTypeName, throwOnError: false))
            .FirstOrDefault(type => type != null);
        if (viewType == null) return false;
        available = true;

        var currentProperty = viewType.GetProperty("Current", BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.FlattenHierarchy);
        var current = currentProperty?.GetValue(null, null);
        if (current == null) return false;
        var activeProperty = viewType.GetProperty("IsActive", BindingFlags.Instance | BindingFlags.Public);
        isActive = activeProperty?.GetValue(current, null) is bool active && active;
        var dataField = viewType.GetField("_dataSource", BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.FlattenHierarchy);
        viewModel = dataField?.GetValue(current) as SceneNotificationVM;
        return viewModel != null;
    }

    private static string BuildEmptyJson(bool available, bool isActive, SceneNotificationVM viewModel, string timeMode, double? campaignDay)
    {
        var json = new StringBuilder(256);
        json.Append('{').Append("\"schemaVersion\":1");
        json.Append(",\"available\":").Append(ChroniclePartyUpgradeAdapter.Bool(available));
        json.Append(",\"hasActiveNotification\":false");
        json.Append(",\"isShown\":").Append(ChroniclePartyUpgradeAdapter.Bool(viewModel?.IsShown == true));
        json.Append(",\"isReady\":").Append(ChroniclePartyUpgradeAdapter.Bool(viewModel?.IsReady == true));
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeBefore", timeMode);
        if (campaignDay.HasValue) json.Append(",\"campaignDayBefore\":").Append(campaignDay.Value.ToString("F6", System.Globalization.CultureInfo.InvariantCulture));
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeAfter", Campaign.Current?.TimeControlMode.ToString());
        if (Campaign.Current != null) json.Append(",\"campaignDayAfter\":").Append(CampaignTime.Now.ToDays.ToString("F6", System.Globalization.CultureInfo.InvariantCulture));
        return json.Append('}').ToString();
    }

    private static void RequireVisualHarnessFixture()
    {
        if (!string.Equals(Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE"), "visual-capture", StringComparison.Ordinal) ||
            string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP")))
            throw new InvalidOperationException("Scene notification fixture is restricted to visual Harness runs");
    }
}
