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
    private void CompleteRestIfReady(ChronicleCampaignBehavior behavior)
    {
        if (_restCommandId == null || !_restTargetDay.HasValue) return;
        var menu = TaleWorlds.CampaignSystem.Campaign.Current.CurrentMenuContext?.GameMenu;
        var commandId = _restCommandId;
        if (menu == null || menu.StringId != "town_wait_menus" || !menu.IsWaitMenu || !Campaign.Current.IsMainPartyWaiting)
        {
            Campaign.Current.TimeControlMode = CampaignTimeControlMode.Stop;
            var interruptedData = BuildRestTimingDataJson(CampaignTime.Now.ToDays);
            WriteResponse(commandId, "rest", "failed", behavior, "settlement wait was interrupted before the requested time elapsed", interruptedData);
            _restCommandId = null;
            _restStartDay = null;
            _restRequestedDays = null;
            _restTargetDay = null;
            return;
        }
        if (CampaignTime.Now.ToDays >= _restTargetDay.Value)
        {
            Campaign.Current.TimeControlMode = CampaignTimeControlMode.Stop;
            var completedData = BuildRestTimingDataJson(CampaignTime.Now.ToDays);
            WriteResponse(commandId, "rest", "completed", behavior, null, completedData);
            _restCommandId = null;
            _restStartDay = null;
            _restRequestedDays = null;
            _restTargetDay = null;
        }
    }

    private string BuildRestTimingDataJson(double actualCampaignDay)
    {
        var startDay = _restStartDay ?? actualCampaignDay;
        var targetDay = _restTargetDay ?? actualCampaignDay;
        var requestedDays = _restRequestedDays ?? Math.Max(0d, targetDay - startDay);
        var overshootDays = Math.Max(0d, actualCampaignDay - targetDay);
        return "{\"requestedDays\":" + requestedDays.ToString("R", CultureInfo.InvariantCulture) +
            ",\"startCampaignDay\":" + startDay.ToString("R", CultureInfo.InvariantCulture) +
            ",\"targetCampaignDay\":" + targetDay.ToString("R", CultureInfo.InvariantCulture) +
            ",\"actualCampaignDay\":" + actualCampaignDay.ToString("R", CultureInfo.InvariantCulture) +
            ",\"overshootDays\":" + overshootDays.ToString("R", CultureInfo.InvariantCulture) + "}";
    }

    private void ApplyMapClickTimeChange(bool isDoubleClick)
    {
        var mode = BannerlordConfig.MapDoubleClickBehavior;
        var campaign = Campaign.Current;
        switch (mode)
        {
            case 0:
                if (!isDoubleClick && campaign.TimeControlMode == CampaignTimeControlMode.StoppableFastForward)
                {
                    _waitForDoubleClickUntilTime = EngineTime.ApplicationTime + 0.3f;
                    campaign.TimeControlMode = CampaignTimeControlMode.StoppableFastForward;
                }
                else
                {
                    campaign.TimeControlMode = isDoubleClick ? CampaignTimeControlMode.StoppableFastForward : CampaignTimeControlMode.StoppablePlay;
                }
                break;
            case 1:
                if (isDoubleClick)
                    campaign.TimeControlMode = campaign.TimeControlMode == CampaignTimeControlMode.StoppableFastForward ? CampaignTimeControlMode.StoppablePlay : CampaignTimeControlMode.StoppableFastForward;
                else
                    campaign.TimeControlMode = campaign.TimeControlMode == CampaignTimeControlMode.StoppableFastForward ? CampaignTimeControlMode.StoppableFastForward : CampaignTimeControlMode.StoppablePlay;
                break;
            case 2:
                campaign.TimeControlMode = campaign.TimeControlMode == CampaignTimeControlMode.StoppableFastForward ? CampaignTimeControlMode.StoppableFastForward : CampaignTimeControlMode.StoppablePlay;
                break;
        }
    }

    private void CompleteDeferredMapClickTimeChange()
    {
        if (_waitForDoubleClickUntilTime <= 0f || _waitForDoubleClickUntilTime >= EngineTime.ApplicationTime) return;
        if (BannerlordConfig.MapDoubleClickBehavior == 0 && Campaign.Current.TimeControlMode == CampaignTimeControlMode.StoppableFastForward)
            Campaign.Current.TimeControlMode = CampaignTimeControlMode.StoppablePlay;
        _waitForDoubleClickUntilTime = 0f;
    }

    private void CompleteAdvanceIfReady(ChronicleCampaignBehavior behavior)
    {
        if (!_advanceTargetDay.HasValue) return;
        var interruptedByEncounter = PlayerEncounter.IsActive;
        if (!interruptedByEncounter && CampaignTime.Now.ToDays < _advanceTargetDay.Value) return;
        var commandId = _advanceCommandId;
        var completionReason = interruptedByEncounter ? "encounter" : "requestedDuration";
        _advanceTargetDay = null;
        _advanceCommandId = null;
        Campaign.Current.TimeControlMode = CampaignTimeControlMode.Stop;
        var dataJson = "{\"completedBy\":\"" + completionReason + "\"}";
        WriteResponse(commandId, "advance", "completed", behavior, null, dataJson);
    }

    internal void OnSaveOver(bool successful, string saveName, ChronicleCampaignBehavior behavior)
    {
        if (_pendingSaveName == null || !string.Equals(_pendingSaveName, saveName, StringComparison.Ordinal)) return;
        _pendingSaveName = null;
        WriteResponse(_pendingSaveCommandId, "save", successful ? "completed" : "rejected", behavior, successful ? null : "save failed");
        _pendingSaveCommandId = null;
    }

    private static string SetNativeTimeSpeed(int selectedTimeSpeed)
    {
        var campaign = TaleWorlds.CampaignSystem.Campaign.Current;
        if (campaign == null || Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("explicit time control requires the Campaign Map state");
        if (campaign.TimeControlModeLock)
            throw new InvalidOperationException("native Campaign time control is currently locked");
        var activeMenu = campaign.CurrentMenuContext?.GameMenu;
        if (campaign.CurrentMenuContext != null && (activeMenu == null || !activeMenu.IsWaitActive))
            throw new InvalidOperationException("native time controls are disabled in this Campaign menu");
        if (selectedTimeSpeed < 0 || selectedTimeSpeed > 2)
            throw new ArgumentOutOfRangeException(nameof(selectedTimeSpeed), "Native map time speed must be Stop(0), Play(1), or FastForward(2).");

        var modeBefore = campaign.TimeControlMode;
        var simplifiedBefore = campaign.GetSimplifiedTimeControlMode();
        var waitingBefore = campaign.IsMainPartyWaiting;
        var dayBefore = CampaignTime.Now.ToDays;
        campaign.SetTimeSpeed(selectedTimeSpeed);
        var modeAfter = campaign.TimeControlMode;
        var simplifiedAfter = campaign.GetSimplifiedTimeControlMode();
        var waitingAfter = campaign.IsMainPartyWaiting;
        var dayAfter = CampaignTime.Now.ToDays;
        var requestedMode = selectedTimeSpeed == 0 ? "pause" : selectedTimeSpeed == 1 ? "play" : "fastForward";
        return "{\"requestedMode\":\"" + requestedMode + "\",\"selectedTimeSpeed\":" + selectedTimeSpeed.ToString(CultureInfo.InvariantCulture) +
            ",\"rawModeBefore\":\"" + modeBefore + "\",\"rawModeAfter\":\"" + modeAfter + "\",\"effectiveModeBefore\":\"" + simplifiedBefore +
            "\",\"effectiveModeAfter\":\"" + simplifiedAfter + "\",\"isMainPartyWaitingBefore\":" + waitingBefore.ToString().ToLowerInvariant() +
            ",\"isMainPartyWaitingAfter\":" + waitingAfter.ToString().ToLowerInvariant() + ",\"campaignDayBefore\":" + dayBefore.ToString("F3", CultureInfo.InvariantCulture) +
            ",\"campaignDayAfter\":" + dayAfter.ToString("F3", CultureInfo.InvariantCulture) + "}";
    }
}
