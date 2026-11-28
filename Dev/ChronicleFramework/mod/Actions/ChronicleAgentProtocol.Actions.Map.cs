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
    private void HandleMapSettlementTargets(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("mapSettlementTargets requires the Campaign Map state");
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentObserver.BuildMapSettlementTargetsJson());
    }

    private void HandleMapNotifications(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentMapNotifications.BuildJson());
    }

    private void HandleQuickInformation(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentQuickInformation.BuildJson());
    }

    private void HandleSceneNotification(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentSceneNotification.BuildJson());
    }

    private void HandleContinueSceneNotification(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentSceneNotification.ContinueFirstBannerNotification());
    }

    private void HandleIncidentSelect(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null,
            ChronicleAgentMapIncidentAdapter.SelectAndConfirm(ReadRequiredInteger(command, "optionIndex")));
    }

    private void HandleSubmitStoryModeClanName(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null,
            ChronicleInquiryAdapter.RespondStoryModeClanName(ReadString(command, "token"), ReadString(command, "text")));
    }

    private void HandleBannerEditorDone(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentBannerEditor.CompleteCurrentEditor());
    }

    private void HandleMapPartyTargets(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("mapPartyTargets requires the Campaign Map state");
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentObserver.BuildMapPartyTargetsJson());
    }

    private void HandleMapPartyComposition(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("mapPartyComposition requires the Campaign Map state");
        var compositionPartyId = ReadString(command, "partyId");
        if (string.IsNullOrWhiteSpace(compositionPartyId))
            throw new InvalidOperationException("mapPartyComposition requires a partyId from the current visible map party list");
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentObserver.BuildMapPartyCompositionJson(compositionPartyId));
    }

    private void HandleMapPartyBehavior(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("mapPartyBehavior requires the Campaign Map state");
        var behaviorPartyId = ReadString(command, "partyId");
        if (string.IsNullOrWhiteSpace(behaviorPartyId))
            throw new InvalidOperationException("mapPartyBehavior requires a partyId from the current visible map party list");
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentObserver.BuildMapPartyBehaviorJson(behaviorPartyId));
    }

    private void HandleCaptureFrame(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        if (!HarnessScreenModes.IsCurrent())
            throw new InvalidOperationException("captureFrame is restricted to visual Harness modes");
        var captureRootValue = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (string.IsNullOrWhiteSpace(captureRootValue)) throw new InvalidOperationException("Harness capture directory is unavailable");
        var captureRoot = Path.GetFullPath(captureRootValue).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
        var captureFileName = ReadString(command, "fileName") ?? string.Empty;
        if (!string.Equals(captureFileName, Path.GetFileName(captureFileName), StringComparison.Ordinal) || !string.Equals(Path.GetExtension(captureFileName), ".bmp", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("captureFrame requires a BMP file name without path components");
        var capturePath = Path.GetFullPath(Path.Combine(captureRoot, captureFileName));
        if (!capturePath.StartsWith(captureRoot, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("captureFrame output escaped the Harness temp directory");
        Directory.CreateDirectory(Path.GetDirectoryName(capturePath));
        TaleWorlds.Engine.Utilities.TakeScreenshot(capturePath);
        WriteResponse(commandId, action, "completed", behavior);
    }

    private void HandlePursue(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        EnsureNoActiveMapIncident("pursuit");
        var mapStateForPursuit = Game.Current?.GameStateManager?.ActiveState as MapState;
        if (mapStateForPursuit == null || mapStateForPursuit.AtMenu || MapScreen.Instance?.IsEscapeMenuOpened == true || ChronicleInquiryAdapter.IsInquiryOpen)
            throw new InvalidOperationException("pursuit requires the unobstructed Campaign Map; a native Map menu, Escape menu, or Inquiry is open");
        if (PlayerEncounter.IsActive || MobileParty.MainParty.CurrentSettlement != null || MobileParty.MainParty.MapEvent != null)
            throw new InvalidOperationException("pursuit requires the campaign map with no active encounter");
        var targetPartyId = ReadString(command, "partyId");
        var targetParty = MobileParty.All.FirstOrDefault(party => party != null && string.Equals(party.StringId, targetPartyId, StringComparison.Ordinal));
        if (targetParty == null || targetParty == MobileParty.MainParty || !targetParty.IsActive || !targetParty.IsVisible)
            throw new InvalidOperationException("active visible target party not found");
        if (targetParty.IsCurrentlyAtSea != MobileParty.MainParty.IsCurrentlyAtSea ||
            !Helpers.NavigationHelper.CanPlayerNavigateToPosition(targetParty.Position, out var pursuitNavigationType))
            throw new InvalidOperationException("target party is not currently navigable by the main party");
        MobileParty.MainParty.SetMoveEngageParty(targetParty, pursuitNavigationType);
        ApplyMapClickTimeChange(isDoubleClick: false);
        WriteResponse(commandId, action, "completed", behavior);
    }

    private void HandleFollow(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        EnsureNoActiveMapIncident("escort");
        if (PlayerEncounter.IsActive || MobileParty.MainParty.CurrentSettlement != null || MobileParty.MainParty.MapEvent != null)
            throw new InvalidOperationException("escort requires the campaign map with no active encounter");
        var escortPartyId = ReadString(command, "partyId");
        var escortParty = MobileParty.All.FirstOrDefault(party => party != null && string.Equals(party.StringId, escortPartyId, StringComparison.Ordinal));
        if (escortParty == null || escortParty == MobileParty.MainParty || !escortParty.IsActive || !escortParty.IsVisible)
            throw new InvalidOperationException("active visible target party not found");
        if (escortParty.IsCurrentlyAtSea != MobileParty.MainParty.IsCurrentlyAtSea ||
            !Helpers.NavigationHelper.CanPlayerNavigateToPosition(escortParty.Position, out var escortNavigationType))
            throw new InvalidOperationException("target party is not currently navigable by the main party");
        MobileParty.MainParty.SetMoveEscortParty(escortParty, escortNavigationType, isTargetingPort: false);
        ApplyMapClickTimeChange(isDoubleClick: false);
        WriteResponse(commandId, action, "completed", behavior);
    }

    private void HandleHold(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        EnsureNoActiveMapIncident("hold");
        MobileParty.MainParty.SetMoveModeHold();
        ApplyMapClickTimeChange(isDoubleClick: false);
        WriteResponse(commandId, action, "completed", behavior);
    }

    private void HandleMove(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        EnsureNoActiveMapIncident("settlement movement");
        if (ChronicleInquiryAdapter.IsInquiryOpen || MapScreen.Instance?.IsEscapeMenuOpened == true || PlayerEncounter.IsActive || MobileParty.MainParty.CurrentSettlement != null || MobileParty.MainParty.MapEvent != null)
            throw new InvalidOperationException("settlement movement requires the unobstructed Campaign Map with no Native menu, Escape menu, Inquiry, or active Encounter"
                + " | inquiryOpen=" + ChronicleInquiryAdapter.IsInquiryOpen
                + " | escapeMenuOpen=" + (MapScreen.Instance?.IsEscapeMenuOpened == true)
                + " | playerEncounterActive=" + PlayerEncounter.IsActive
                + " | currentSettlement=" + (MobileParty.MainParty?.CurrentSettlement?.StringId ?? "<none>")
                + " | atMenu=" + ((Game.Current?.GameStateManager?.ActiveState as MapState)?.AtMenu ?? false)
                + " | cameraInput=" + (MapScreen.Instance?.MapCameraView?.ProcessCameraInput == true)
                + " | menuId=" + (Campaign.Current?.CurrentMenuContext?.GameMenu?.StringId ?? "<none>"));
        var mapStateForSettlementMove = Game.Current?.GameStateManager?.ActiveState as MapState;
        if (mapStateForSettlementMove == null || mapStateForSettlementMove.AtMenu)
            throw new InvalidOperationException("settlement movement requires the unobstructed native Campaign Map");
        if (MapScreen.Instance?.MapCameraView?.ProcessCameraInput != true)
            throw new InvalidOperationException("Native MapScreen is not currently accepting map camera clicks");
        var settlementId = ReadString(command, "settlementId");
        var settlement = string.IsNullOrWhiteSpace(settlementId) ? null : Settlement.Find(settlementId);
        if (settlement == null || !settlement.IsActive || !settlement.IsVisible) throw new InvalidOperationException("settlement is not currently exposed as a visible Campaign map target");
        var canJoinExistingSiegeAsAttacker = settlement.SiegeEvent != null &&
            !settlement.SiegeEvent.IsBlockadeActive && settlement.Party?.MapEvent == null &&
            MobileParty.MainParty.SiegeEvent == null && MobileParty.MainParty.BesiegerCamp == null &&
            settlement.SiegeEvent.CanPartyJoinSide(PartyBase.MainParty, BattleSideEnum.Attacker);
        if (settlement.MapFaction != null && FactionManager.IsAtWarAgainstFaction(MobileParty.MainParty.MapFaction, settlement.MapFaction) && !canJoinExistingSiegeAsAttacker)
            throw new InvalidOperationException("hostile settlement rejected by safe movement policy");
        Helpers.NavigationHelper.GetInteractionDataForMainParty(settlement, out var canNavigateToSettlement, out _, out _);
        if (!canNavigateToSettlement) throw new InvalidOperationException("settlement is not currently navigable by the main party");
        var settlementVisual = settlement.Party == null
            ? null
            : SettlementVisualManager.Current?.GetVisualOfEntity(settlement.Party) as SettlementVisual;
        if (settlementVisual == null)
            throw new InvalidOperationException("Native SettlementVisual is not currently visible for this settlement target");
        var targetInteractionFace = settlementVisual.InteractionPositionForPlayer.Face;
        var currentNavigationFace = MobileParty.MainParty.CurrentNavigationFace;
        var nativeMapScene = MapScreen.Instance.MapScene;
        if (nativeMapScene == null || targetInteractionFace.FaceIndex < 0 || currentNavigationFace.FaceIndex < 0 ||
            !nativeMapScene.DoesPathExistBetweenFaces(targetInteractionFace.FaceIndex, currentNavigationFace.FaceIndex, false))
            throw new InvalidOperationException("Native MapScreen would reject this settlement click because no path exists between the current party face and the settlement marker face");
        if (!settlementVisual.OnMapClick(followModifierUsed: false))
            throw new InvalidOperationException("Native SettlementVisual.OnMapClick declined this settlement target");
        ApplyMapClickTimeChange(isDoubleClick: false);
        WriteResponse(commandId, action, "completed", behavior);
    }

    private void HandleMoveToPoint(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        EnsureNoActiveMapIncident("point movement");
        if (ChronicleInquiryAdapter.IsInquiryOpen || MapScreen.Instance?.IsEscapeMenuOpened == true || PlayerEncounter.IsActive || MobileParty.MainParty.CurrentSettlement != null || MobileParty.MainParty.MapEvent != null)
            throw new InvalidOperationException("point movement requires the unobstructed Campaign Map with no Native menu, Escape menu, Inquiry, or active Encounter");
        var mapStateForPointMove = Game.Current.GameStateManager.ActiveState as MapState;
        if (mapStateForPointMove == null || mapStateForPointMove.AtMenu)
            throw new InvalidOperationException("point movement requires the unblocked native campaign map state");
        var targetX = ReadRequiredFiniteDouble(command, "x");
        var targetY = ReadRequiredFiniteDouble(command, "y");
        var surface = ReadString(command, "surface");
        if (!string.Equals(surface, "land", StringComparison.Ordinal))
            throw new InvalidOperationException("moveToPoint currently supports land destinations only; naval/sea transition belongs to a separately tested adapter");
        if (!MobileParty.MainParty.Position.IsOnLand)
            throw new InvalidOperationException("land point movement requires the main party to be on land");
        if (targetX > float.MaxValue || targetX < -float.MaxValue || targetY > float.MaxValue || targetY < -float.MaxValue)
            throw new InvalidOperationException("map destination is outside the Campaign coordinate range");
        var requestedPoint = new CampaignVec2(new TaleWorlds.Library.Vec2((float)targetX, (float)targetY), isOnLand: true);
        if (!requestedPoint.Face.IsValid())
            throw new InvalidOperationException("map destination does not resolve to a valid navigation face");
        if (!Helpers.NavigationHelper.CanPlayerNavigateToPosition(requestedPoint, out _))
            throw new InvalidOperationException("map destination is not currently navigable by the main party");
        var mainPartyForPointMove = MobileParty.MainParty;
        mapStateForPointMove.ProcessTravel(requestedPoint);
        if (mainPartyForPointMove.DefaultBehavior != AiBehavior.GoToPoint)
            throw new InvalidOperationException("native MapState.ProcessTravel did not establish a GoToPoint order");
        ApplyMapClickTimeChange(isDoubleClick: false);
        var actualPoint = mainPartyForPointMove.TargetPosition;
        var pointMoveData = "{\"requested\":{\"x\":" + targetX.ToString("R", CultureInfo.InvariantCulture) + ",\"y\":" + targetY.ToString("R", CultureInfo.InvariantCulture) + ",\"surface\":\"" + Escape(surface) + "\"},\"nativeTarget\":{\"x\":" + actualPoint.X.ToString("R", CultureInfo.InvariantCulture) + ",\"y\":" + actualPoint.Y.ToString("R", CultureInfo.InvariantCulture) + ",\"isOnLand\":" + actualPoint.IsOnLand.ToString().ToLowerInvariant() + "},\"nativeBehavior\":\"" + Escape(mainPartyForPointMove.DefaultBehavior.ToString()) + "\"}";
        WriteResponse(commandId, action, "completed", behavior, null, pointMoveData);
    }

    private void HandleMenu(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        if (TaleWorlds.CampaignSystem.Campaign.Current.CurrentMenuContext?.GameMenu == null)
            throw new InvalidOperationException("no campaign menu is active");
        WriteResponse(commandId, action, "completed", behavior);
    }

    private void HandleMenuSelect(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        if (!AgentMissionInputPatch.IsNativeMenuVisible())
            throw new InvalidOperationException("menuSelect requires a visible Native Campaign menu; do not use a stale parent menu while a 3D Mission or active dialogue is on screen");
        var menuContext = TaleWorlds.CampaignSystem.Campaign.Current.CurrentMenuContext;
        var expectedMenuId = ReadString(command, "menuId");
        var optionId = ReadString(command, "optionId");
        if (menuContext?.GameMenu == null && !string.IsNullOrWhiteSpace(expectedMenuId))
        {
            // Arriving at a settlement leaves the party on the Map with no current menu until the player
            // clicks it. When the Agent asks for a settlement menu it is standing in, activate that exact
            // menu instead of failing: the request still has to match the Native menu id afterwards.
            var standingSettlement = TaleWorlds.CampaignSystem.Hero.MainHero?.CurrentSettlement;
            if (standingSettlement != null)
            {
                TaleWorlds.CampaignSystem.GameMenus.GameMenu.ActivateGameMenu(expectedMenuId);
                menuContext = TaleWorlds.CampaignSystem.Campaign.Current.CurrentMenuContext;
            }
        }
        if (menuContext?.GameMenu == null || !string.Equals(menuContext.GameMenu.StringId, expectedMenuId, StringComparison.Ordinal))
            throw new InvalidOperationException("campaign menu changed before option selection");
        var menuOptions = menuContext.GameMenu.MenuOptions.ToList();
        if (menuContext.GameMenu.MenuRepeatObjects.Count > 0)
            throw new InvalidOperationException("repeatable menu options are not supported by protocol v1");
        var optionIndex = menuOptions.FindIndex(candidate => string.Equals(candidate.IdString, optionId, StringComparison.Ordinal));
        if (optionIndex < 0) throw new InvalidOperationException("menu option not found");
        var option = menuOptions[optionIndex];
        if (!option.GetConditionsHold(TaleWorlds.Core.Game.Current, menuContext) || !option.IsEnabled)
            throw new InvalidOperationException("menu option is unavailable or disabled");
        menuContext.GameMenu.RunMenuOptionConsequence(menuContext, optionIndex);
        WriteResponse(commandId, action, "completed", behavior);
    }
}
