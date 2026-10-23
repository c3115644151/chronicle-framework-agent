using System;
using System.Linq;
using System.Reflection;
using System.Text;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.GameState;
using TaleWorlds.CampaignSystem.SceneInformationPopupTypes;
using TaleWorlds.Core;
using TaleWorlds.Core.ViewModelCollection.Information;
using TaleWorlds.Library;
using TaleWorlds.Localization;

namespace ChronicleFramework;

internal static class ChronicleAgentSceneNotification
{
    private const string GauntletSceneNotificationTypeName = "TaleWorlds.MountAndBlade.GauntletUI.SceneNotification.GauntletSceneNotification";
    private const string FirstBannerPieceNotificationTypeName = "FindingFirstBannerPieceSceneNotificationItem";

    internal static string BuildJson(bool includeClockAudit = true)
    {
        var timeModeBefore = Campaign.Current?.TimeControlMode.ToString();
        var campaignDayBefore = Campaign.Current == null ? (double?)null : CampaignTime.Now.ToDays;
        if (!TryGetNativeSceneNotification(out var available, out var isActive, out var viewModel))
            return BuildEmptyJson(available, isActive: false, null, timeModeBefore, campaignDayBefore, includeClockAudit);

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
            json.Append(",\"pauseActiveState\":").Append(ChroniclePartyUpgradeAdapter.Bool(data.PauseActiveState));
            json.Append(",\"canContinue\":").Append(ChroniclePartyUpgradeAdapter.Bool(CanContinueFirstBannerNotification(viewModel, data)));
            ChroniclePartyUpgradeAdapter.Property(json, "continuationKind", GetContinuationKind(data));
        }
        if (includeClockAudit)
        {
            ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeBefore", timeModeBefore);
            if (campaignDayBefore.HasValue) json.Append(",\"campaignDayBefore\":").Append(campaignDayBefore.Value.ToString("F6", System.Globalization.CultureInfo.InvariantCulture));
            ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeAfter", Campaign.Current?.TimeControlMode.ToString());
            if (Campaign.Current != null) json.Append(",\"campaignDayAfter\":").Append(CampaignTime.Now.ToDays.ToString("F6", System.Globalization.CultureInfo.InvariantCulture));
        }
        return json.Append('}').ToString();
    }

    internal static string ContinueFirstBannerNotification()
    {
        if (Game.Current?.GameStateManager?.ActiveState is not MapState || Campaign.Current == null)
            throw new InvalidOperationException("continueSceneNotification requires the Campaign Map state");
        if (!TryGetNativeSceneNotification(out _, out var isActive, out var viewModel) || !isActive || viewModel?.IsShown != true ||
            viewModel.ActiveData is not SceneNotificationData data || !CanContinueFirstBannerNotification(viewModel, data))
            throw new InvalidOperationException("continueSceneNotification requires the active, ready Native FindingFirstBannerPieceSceneNotificationItem with a verified no-op or StoryMode clan-name continuation");

        var timeModeBefore = Campaign.Current.TimeControlMode.ToString();
        var campaignDayBefore = CampaignTime.Now.ToDays;
        var title = viewModel.TitleText;
        viewModel.ExecuteClose();
        var stillActive = TryGetNativeSceneNotification(out _, out var afterIsActive, out var afterViewModel) &&
                          afterIsActive && afterViewModel?.IsShown == true && afterViewModel.ActiveData != null;

        var json = new StringBuilder(512);
        json.Append('{').Append("\"schemaVersion\":1");
        ChroniclePartyUpgradeAdapter.Property(json, "nativeHandler", "SceneNotificationVM.ExecuteClose");
        ChroniclePartyUpgradeAdapter.Property(json, "dataType", data.GetType().Name);
        ChroniclePartyUpgradeAdapter.Property(json, "titleText", title);
        json.Append(",\"notificationStillActive\":").Append(ChroniclePartyUpgradeAdapter.Bool(stillActive));
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeBefore", timeModeBefore);
        json.Append(",\"campaignDayBefore\":").Append(campaignDayBefore.ToString("F6", System.Globalization.CultureInfo.InvariantCulture));
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeAfter", Campaign.Current.TimeControlMode.ToString());
        json.Append(",\"campaignDayAfter\":").Append(CampaignTime.Now.ToDays.ToString("F6", System.Globalization.CultureInfo.InvariantCulture));
        if (InformationManager.IsAnyInquiryActive())
            json.Append(",\"followUpInquiry\":").Append(ChronicleInquiryAdapter.BuildMapInquiryJson());
        return json.Append('}').ToString();
    }

    private static bool CanContinueFirstBannerNotification(SceneNotificationVM viewModel, SceneNotificationData data)
    {
        if (Game.Current?.GameStateManager?.ActiveState is not MapState ||
            data.GetType().Name != FirstBannerPieceNotificationTypeName ||
            !viewModel.IsShown || !viewModel.IsReady || viewModel.IsButtonOkShown || viewModel.IsButtonCancelShown ||
            string.IsNullOrWhiteSpace(viewModel.ClickToContinueText)) return false;

        var callback = data.GetType().GetField("_onCloseAction", BindingFlags.Instance | BindingFlags.NonPublic)?.GetValue(data) as Action;
        return callback == null || IsStoryModeClanNameCallback(callback);
    }

    private static string GetContinuationKind(SceneNotificationData data)
    {
        var callback = data?.GetType().GetField("_onCloseAction", BindingFlags.Instance | BindingFlags.NonPublic)?.GetValue(data) as Action;
        return callback == null ? "none" : IsStoryModeClanNameCallback(callback) ? "storymode-clan-name-setup" : "unsupported";
    }

    internal static string SeedHarnessFixture()
    {
        RequireVisualHarnessFixture();
        if (Game.Current?.GameStateManager?.ActiveState is not MapState || Campaign.Current == null || Hero.MainHero == null)
            throw new InvalidOperationException("harnessSeedSceneNotificationFixture requires an active Campaign Map and MainHero");
        if (!TryGetNativeSceneNotification(out var available, out var isActive, out _))
            throw new InvalidOperationException("Native GauntletSceneNotification UI layer is unavailable");
        if (isActive) throw new InvalidOperationException("Harness scene notification fixture requires no active scene notification");

        var callback = GetStoryModeClanNameCallback();
        if (callback == null) throw new InvalidOperationException("The StoryMode FirstPhaseCampaignBehavior clan-name callback is unavailable in this Campaign");
        var data = new FindingFirstBannerPieceSceneNotificationItem(Hero.MainHero, callback);
        MBInformationManager.ShowSceneNotification(data);

        var json = new StringBuilder(512);
        json.Append('{').Append("\"schemaVersion\":1,\"testOnly\":true");
        ChroniclePartyUpgradeAdapter.Property(json, "type", data.GetType().Name);
        ChroniclePartyUpgradeAdapter.Property(json, "titleText", data.TitleText?.ToString());
        json.Append(",\"pauseActiveState\":").Append(ChroniclePartyUpgradeAdapter.Bool(data.PauseActiveState));
        json.Append(",\"closeCallbackIsStoryModeClanName\":true}");
        return json.ToString();
    }

    private static Action GetStoryModeClanNameCallback()
    {
        var behavior = GetStoryModeFirstPhaseBehavior();
        if (behavior == null) return null;
        var method = behavior.GetType().GetMethod("OnPieceFoundAction", BindingFlags.Instance | BindingFlags.NonPublic);
        return method == null ? null : Delegate.CreateDelegate(typeof(Action), behavior, method) as Action;
    }

    private static bool IsStoryModeClanNameCallback(Action callback)
    {
        if (callback?.Target == null || callback.Method.Name != "OnPieceFoundAction" ||
            callback.Target.GetType().FullName != "StoryMode.GameComponents.CampaignBehaviors.FirstPhaseCampaignBehavior") return false;
        return ReferenceEquals(callback.Target, GetStoryModeFirstPhaseBehavior());
    }

    private static object GetStoryModeFirstPhaseBehavior()
    {
        if (Campaign.Current == null) return null;
        var behaviorType = AppDomain.CurrentDomain.GetAssemblies()
            .Select(assembly => assembly.GetType("StoryMode.GameComponents.CampaignBehaviors.FirstPhaseCampaignBehavior", throwOnError: false))
            .FirstOrDefault(type => type != null);
        var manager = Campaign.Current.GetType().GetProperty("CampaignBehaviorManager", BindingFlags.Instance | BindingFlags.Public)?.GetValue(Campaign.Current);
        var getBehavior = manager?.GetType().GetMethods(BindingFlags.Instance | BindingFlags.Public)
            .FirstOrDefault(method => method.Name == "GetBehavior" && method.IsGenericMethodDefinition && method.GetParameters().Length == 0);
        return behaviorType == null || getBehavior == null ? null : getBehavior.MakeGenericMethod(behaviorType).Invoke(manager, null);
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

    private static string BuildEmptyJson(bool available, bool isActive, SceneNotificationVM viewModel, string timeMode, double? campaignDay, bool includeClockAudit)
    {
        var json = new StringBuilder(256);
        json.Append('{').Append("\"schemaVersion\":1");
        json.Append(",\"available\":").Append(ChroniclePartyUpgradeAdapter.Bool(available));
        json.Append(",\"hasActiveNotification\":false");
        json.Append(",\"isShown\":").Append(ChroniclePartyUpgradeAdapter.Bool(viewModel?.IsShown == true));
        json.Append(",\"isReady\":").Append(ChroniclePartyUpgradeAdapter.Bool(viewModel?.IsReady == true));
        if (includeClockAudit)
        {
            ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeBefore", timeMode);
            if (campaignDay.HasValue) json.Append(",\"campaignDayBefore\":").Append(campaignDay.Value.ToString("F6", System.Globalization.CultureInfo.InvariantCulture));
            ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeAfter", Campaign.Current?.TimeControlMode.ToString());
            if (Campaign.Current != null) json.Append(",\"campaignDayAfter\":").Append(CampaignTime.Now.ToDays.ToString("F6", System.Globalization.CultureInfo.InvariantCulture));
        }
        return json.Append('}').ToString();
    }

    private static void RequireVisualHarnessFixture()
    {
        if (!string.Equals(Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE"), "visual-capture", StringComparison.Ordinal) ||
            string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP")))
            throw new InvalidOperationException("Scene notification fixture is restricted to visual Harness runs");
    }
}
