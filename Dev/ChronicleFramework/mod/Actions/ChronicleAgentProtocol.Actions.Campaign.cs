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
    private void HandleState(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior);
    }

    private void HandleAgentCheckpointGet(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        RequireCampaignMapState("agentCheckpointGet");
        WriteResponse(commandId, action, "completed", behavior, null, behavior.BuildAgentCheckpointDataJson());
    }

    private void HandleAgentCheckpointSet(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        RequireCampaignMapState("agentCheckpointSet");
        var encodedCheckpoint = ReadString(command, "checkpointBase64");
        if (string.IsNullOrWhiteSpace(encodedCheckpoint) || encodedCheckpoint.Length > 100000)
            throw new InvalidOperationException("Checkpoint base64 is missing or oversized");
        byte[] checkpointBytes;
        try { checkpointBytes = Convert.FromBase64String(encodedCheckpoint); }
        catch (FormatException) { throw new InvalidOperationException("Checkpoint payload is not valid base64"); }
        if (checkpointBytes.Length > 65536) throw new InvalidOperationException("Checkpoint payload exceeds the 65536-byte save-data limit");
        string checkpointJson;
        try { checkpointJson = new UTF8Encoding(false, true).GetString(checkpointBytes); }
        catch (DecoderFallbackException) { throw new InvalidOperationException("Checkpoint payload is not valid UTF-8"); }
        var checkpointSchemaVersion = ReadRequiredInteger(checkpointJson, "schemaVersion");
        if (checkpointSchemaVersion != 1 && checkpointSchemaVersion != 2)
            throw new InvalidOperationException("Unsupported Agent checkpoint schema version");
        var checkpointCampaignId = ReadString(checkpointJson, "campaignInstanceId");
        behavior.StoreAgentCheckpoint(checkpointCampaignId, checkpointJson);
        var checkpointWriteJson = "{\"campaignInstanceId\":\"" + Escape(behavior.AgentCampaignInstanceId) + "\",\"checkpointChars\":" + checkpointJson.Length + "}";
        WriteResponse(commandId, action, "completed", behavior, null, checkpointWriteJson);
    }

    private void HandleHarnessSeedAgentCheckpointFailure(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var checkpointFixtureMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var checkpointFixtureRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(checkpointFixtureMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(checkpointFixtureRoot) || !Directory.Exists(checkpointFixtureRoot))
            throw new InvalidOperationException("harnessSeedAgentCheckpointFailure is restricted to a visual Harness run with a Harness temp directory");
        RequireCampaignMapState("harnessSeedAgentCheckpointFailure");
        var checkpointFailureMode = ReadString(command, "mode");
        string invalidCheckpointJson;
        if (string.Equals(checkpointFailureMode, "corrupt-json", StringComparison.Ordinal))
        {
            invalidCheckpointJson = "{not-json}";
        }
        else if (string.Equals(checkpointFailureMode, "unsupported-schema", StringComparison.Ordinal))
        {
            invalidCheckpointJson = "{\"schemaVersion\":99,\"campaignInstanceId\":\"" + Escape(behavior.AgentCampaignInstanceId) + "\",\"taskId\":\"harness-invalid-schema\",\"goal\":\"must not run\",\"status\":\"active\"}";
        }
        else if (string.Equals(checkpointFailureMode, "wrong-campaign", StringComparison.Ordinal))
        {
            invalidCheckpointJson = "{\"schemaVersion\":1,\"campaignInstanceId\":\"chronicle_wrong_campaign\",\"taskId\":\"harness-wrong-campaign\",\"goal\":\"must not run\",\"status\":\"active\"}";
        }
        else
        {
            throw new InvalidOperationException("Harness checkpoint failure mode must be corrupt-json, unsupported-schema, or wrong-campaign");
        }
        behavior.StoreAgentCheckpoint(behavior.AgentCampaignInstanceId, invalidCheckpointJson);
        var checkpointFixtureResult = "{\"mode\":\"" + Escape(checkpointFailureMode) + "\",\"campaignInstanceId\":\"" + Escape(behavior.AgentCampaignInstanceId) + "\",\"payloadChars\":" + invalidCheckpointJson.Length + "}";
        WriteResponse(commandId, action, "completed", behavior, null, checkpointFixtureResult);
    }

    private void HandleCloseEscapeMenu(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        if (Game.Current?.GameStateManager?.ActiveState is not MapState mapStateForEscape || mapStateForEscape.AtMenu)
            throw new InvalidOperationException("closeEscapeMenu requires the unobstructed Campaign Map state");
        var mapScreenForEscape = MapScreen.Instance;
        if (mapScreenForEscape == null || !mapScreenForEscape.IsEscapeMenuOpened)
            throw new InvalidOperationException("closeEscapeMenu requires the Native Campaign Map Escape menu to be open");
        mapScreenForEscape.CloseEscapeMenu();
        if (mapScreenForEscape.IsEscapeMenuOpened)
            throw new InvalidOperationException("Native MapScreen did not close its Escape menu");
        WriteResponse(commandId, action, "completed", behavior);
    }

    private void HandleAdvance(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var days = ReadDouble(command, "days");
        _advanceTargetDay = CampaignTime.Now.ToDays + Math.Max(0.01, days);
        _advanceCommandId = commandId;
        TaleWorlds.CampaignSystem.Campaign.Current.TimeControlMode = TaleWorlds.CampaignSystem.CampaignTimeControlMode.UnstoppableFastForward;
        WriteResponse(commandId, action, "accepted", behavior);
    }

    private void HandleRest(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var currentMenuContext = TaleWorlds.CampaignSystem.Campaign.Current.CurrentMenuContext;
        var currentMenu = currentMenuContext?.GameMenu;
        var atTownMenu = currentMenu != null && currentMenu.StringId == "town" && !currentMenu.IsWaitMenu;
        var atWaitMenu = currentMenu != null && currentMenu.StringId == "town_wait_menus" && currentMenu.IsWaitMenu && Campaign.Current.IsMainPartyWaiting;
        if (!atTownMenu && !atWaitMenu)
            throw new InvalidOperationException("rest requires the current Native Town menu or an active native town_wait_menus screen");
        if (_restCommandId != null) throw new InvalidOperationException("another rest command is active");
        var requestedRestDays = ReadDouble(command, "days");
        if (double.IsNaN(requestedRestDays) || double.IsInfinity(requestedRestDays) || requestedRestDays <= 0d)
            throw new InvalidOperationException("rest requires a positive finite Native wait duration in Campaign days");
        var restDays = Math.Max(0.01, requestedRestDays);
        var restStartDay = CampaignTime.Now.ToDays;
        _restCommandId = commandId;
        _restStartDay = restStartDay;
        _restRequestedDays = restDays;
        _restTargetDay = restStartDay + restDays;
        if (atTownMenu)
        {
            var townWaitOptions = currentMenu.MenuOptions.ToList();
            var townWaitOptionIndex = townWaitOptions.FindIndex(option => string.Equals(option.IdString, "town_wait", StringComparison.Ordinal));
            if (townWaitOptionIndex < 0 ||
                !townWaitOptions[townWaitOptionIndex].GetConditionsHold(TaleWorlds.Core.Game.Current, currentMenuContext) ||
                !townWaitOptions[townWaitOptionIndex].IsEnabled)
            {
                Campaign.Current.TimeControlMode = CampaignTimeControlMode.Stop;
                _restCommandId = null;
                _restStartDay = null;
                _restRequestedDays = null;
                _restTargetDay = null;
                throw new InvalidOperationException("the current Native Town menu does not offer an enabled town_wait option");
            }

            try
            {
                currentMenu.RunMenuOptionConsequence(currentMenuContext, townWaitOptionIndex);
            }
            catch
            {
                Campaign.Current.TimeControlMode = CampaignTimeControlMode.Stop;
                _restCommandId = null;
                _restStartDay = null;
                _restRequestedDays = null;
                _restTargetDay = null;
                throw;
            }

            var waitMenuAfterStart = Campaign.Current.CurrentMenuContext?.GameMenu;
            if (waitMenuAfterStart == null || waitMenuAfterStart.StringId != "town_wait_menus" ||
                !waitMenuAfterStart.IsWaitMenu || !Campaign.Current.IsMainPartyWaiting)
            {
                Campaign.Current.TimeControlMode = CampaignTimeControlMode.Stop;
                _restCommandId = null;
                _restStartDay = null;
                _restRequestedDays = null;
                _restTargetDay = null;
                throw new InvalidOperationException("the original town_wait option did not enter its active Native Wait menu");
            }
        }
        else if (Campaign.Current.TimeControlMode is CampaignTimeControlMode.Stop or CampaignTimeControlMode.FastForwardStop)
        {
            Campaign.Current.TimeControlMode = CampaignTimeControlMode.UnstoppableFastForward;
        }

        var restAcceptedData = "{\"requestedDays\":" + restDays.ToString("R", CultureInfo.InvariantCulture) +
            ",\"startCampaignDay\":" + restStartDay.ToString("R", CultureInfo.InvariantCulture) +
            ",\"targetCampaignDay\":" + _restTargetDay.Value.ToString("R", CultureInfo.InvariantCulture) + "}";
        WriteResponse(commandId, action, "accepted", behavior, null, restAcceptedData);
    }

    private void HandlePause(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, SetNativeTimeSpeed(0));
    }

    private void HandleResume(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, SetNativeTimeSpeed(1));
    }

    private void HandleFastForward(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, SetNativeTimeSpeed(2));
    }

    private void HandleSave(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var saveName = ReadString(command, "name");
        if (string.IsNullOrWhiteSpace(saveName)) throw new InvalidOperationException("save name is required");
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("save requires the Native Campaign MapState; the current game state cannot complete the Harness SaveAs request");
        if (!string.IsNullOrWhiteSpace(_pendingSaveCommandId))
            throw new InvalidOperationException("another Native SaveAs request is still awaiting its SaveOver completion; no second save was queued");
        _pendingSaveName = saveName;
        _pendingSaveCommandId = commandId;
        TaleWorlds.CampaignSystem.Campaign.Current.SaveHandler.SaveAs(saveName);
        WriteResponse(commandId, action, "accepted", behavior);
    }

    private void HandleStop(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        ChronicleAgentBattleMissionAdapter.ClearMainAgentAiControllerProbeLease("protocol-stopped");
        ClearMissionNavigationLease("stopped");
        ClearMissionInputLease();
        TaleWorlds.CampaignSystem.Campaign.Current.TimeControlMode = TaleWorlds.CampaignSystem.CampaignTimeControlMode.Stop;
        WriteResponse(commandId, action, "completed", behavior);
    }
}
