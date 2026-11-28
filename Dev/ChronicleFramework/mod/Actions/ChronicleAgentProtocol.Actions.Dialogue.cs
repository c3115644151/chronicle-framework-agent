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
    private void HandleRespondInquiry(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var inquiryChoice = ReadString(command, "choice");
        var inquiryToken = ReadString(command, "token");
        var inquiryResponse = ChronicleInquiryAdapter.Respond(inquiryToken, inquiryChoice);
        var tradeInquiryResolution = ChronicleAgentTradeAdapter.ResolvePendingConfirmationInquiry(inquiryToken, inquiryChoice);
        var inquiryResponseData = tradeInquiryResolution == null
            ? inquiryResponse
            : "{\"nativeInquiryResponse\":" + inquiryResponse + ",\"tradeResolution\":" + tradeInquiryResolution + "}";
        WriteResponse(commandId, action, "completed", behavior, null, inquiryResponseData);
    }

    private void HandleRespondMultiSelectionInquiry(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var multiInquiryChoice = ReadString(command, "choice");
        var multiInquiryToken = ReadString(command, "token");
        var multiInquirySelectedIds = ReadStringArray(command, "selectedIds");
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleInquiryAdapter.RespondAlleyMultiSelection(multiInquiryToken, multiInquiryChoice, multiInquirySelectedIds));
    }

    private void HandleTalkToSettlementHero(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var quickOverlayMenuContext = TaleWorlds.CampaignSystem.Campaign.Current?.CurrentMenuContext;
        var quickOverlayGameMenu = quickOverlayMenuContext?.GameMenu;
        if (quickOverlayGameMenu == null ||
            (quickOverlayGameMenu.OverlayType != GameMenu.MenuOverlayType.SettlementWithCharacters && quickOverlayGameMenu.OverlayType != GameMenu.MenuOverlayType.SettlementWithBoth) ||
            Settlement.CurrentSettlement == null)
            throw new InvalidOperationException("talkToSettlementHero requires the native settlement menu with a visible Characters overlay");
        var quickSettlementHeroId = ReadString(command, "heroId");
        if (string.IsNullOrWhiteSpace(quickSettlementHeroId)) throw new InvalidOperationException("talkToSettlementHero requires a HeroId from the current settlement overlay observation");
        var quickOverlayLocationCharacters = TaleWorlds.CampaignSystem.Campaign.Current.GameMenuManager.MenuLocations
            .Where(location => location != null)
            .SelectMany(location => location.GetCharacterList())
            .Where(locationCharacter => locationCharacter != null && locationCharacter.Character?.IsHero == true && TaleWorlds.CampaignSystem.Campaign.Current.Models.HeroAgentLocationModel.WillBeListedInOverlay(locationCharacter))
            .ToArray();
        var quickSettlementTargetCharacter = quickOverlayLocationCharacters.FirstOrDefault(locationCharacter =>
            locationCharacter.Character?.HeroObject != null &&
            string.Equals(locationCharacter.Character.HeroObject.StringId, quickSettlementHeroId, StringComparison.Ordinal));
        var quickSettlementTargetHero = quickSettlementTargetCharacter?.Character?.HeroObject;
        if (quickSettlementTargetHero == null || !quickSettlementTargetHero.IsAlive || quickSettlementTargetHero.IsPrisoner || quickSettlementTargetHero.CurrentSettlement != Settlement.CurrentSettlement)
            throw new InvalidOperationException("talkToSettlementHero target is no longer a living, non-prisoner character in the current native Settlement overlay");
        var quickTalkPermissionWasReported = false;
        var quickTalkPermissionAllowed = true;
        string quickTalkPermissionHint = null;
        Game.Current.EventManager.TriggerEvent(new SettlementOverylayQuickTalkPermissionEvent(quickSettlementTargetHero, (isAllowed, hint) =>
        {
            quickTalkPermissionWasReported = true;
            quickTalkPermissionAllowed = isAllowed;
            quickTalkPermissionHint = hint?.ToString();
        }));
        if (quickTalkPermissionWasReported && !quickTalkPermissionAllowed)
            throw new InvalidOperationException(string.IsNullOrWhiteSpace(quickTalkPermissionHint) ? "The native Settlement overlay does not currently allow quick talking to this Hero" : quickTalkPermissionHint);
        TaleWorlds.CampaignSystem.Conversation.CampaignMapConversation.OpenConversation(
            new TaleWorlds.CampaignSystem.Conversation.ConversationCharacterData(CharacterObject.PlayerCharacter, null, noHorse: false, noWeapon: false, spawnAfterFight: false, isCivilianEquipmentRequiredForLeader: true),
            new TaleWorlds.CampaignSystem.Conversation.ConversationCharacterData(quickSettlementTargetCharacter.Character, null, noHorse: false, noWeapon: false, spawnAfterFight: false, isCivilianEquipmentRequiredForLeader: true));
        var quickTalkData = "{\"heroId\":\"" + Escape(quickSettlementTargetHero.StringId) + "\",\"heroName\":\"" + Escape(quickSettlementTargetHero.Name?.ToString()) + "\"}";
        WriteResponse(commandId, action, "completed", behavior, null, quickTalkData);
    }

    private void HandleVisitSettlementHero(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var visitOverlayMenuContext = TaleWorlds.CampaignSystem.Campaign.Current?.CurrentMenuContext;
        var visitOverlayGameMenu = visitOverlayMenuContext?.GameMenu;
        if (visitOverlayGameMenu == null ||
            (visitOverlayGameMenu.OverlayType != GameMenu.MenuOverlayType.SettlementWithCharacters && visitOverlayGameMenu.OverlayType != GameMenu.MenuOverlayType.SettlementWithBoth) ||
            Settlement.CurrentSettlement == null)
            throw new InvalidOperationException("visitSettlementHero requires the native settlement menu with a visible Characters overlay");
        var visitSettlementHeroId = ReadString(command, "heroId");
        if (string.IsNullOrWhiteSpace(visitSettlementHeroId)) throw new InvalidOperationException("visitSettlementHero requires a HeroId from the current settlement overlay observation");
        var visitOverlayLocationCharacters = TaleWorlds.CampaignSystem.Campaign.Current.GameMenuManager.MenuLocations
            .Where(location => location != null)
            .SelectMany(location => location.GetCharacterList())
            .Where(locationCharacter => locationCharacter != null && locationCharacter.Character?.IsHero == true && TaleWorlds.CampaignSystem.Campaign.Current.Models.HeroAgentLocationModel.WillBeListedInOverlay(locationCharacter))
            .ToArray();
        var visitSettlementTargetCharacter = visitOverlayLocationCharacters.FirstOrDefault(locationCharacter =>
            locationCharacter.Character?.HeroObject != null &&
            string.Equals(locationCharacter.Character.HeroObject.StringId, visitSettlementHeroId, StringComparison.Ordinal));
        var visitSettlementTargetHero = visitSettlementTargetCharacter?.Character?.HeroObject;
        if (visitSettlementTargetHero == null || !visitSettlementTargetHero.IsAlive || visitSettlementTargetHero.IsPrisoner || visitSettlementTargetHero.CurrentSettlement != Settlement.CurrentSettlement)
            throw new InvalidOperationException("visitSettlementHero target is no longer a living, non-prisoner character in the current native Settlement overlay");
        var visitPermissionWasReported = false;
        var visitPermissionAllowed = true;
        string visitPermissionHint = null;
        Game.Current.EventManager.TriggerEvent(new SettlementOverlayTalkPermissionEvent(visitSettlementTargetHero, (isAllowed, hint) =>
        {
            visitPermissionWasReported = true;
            visitPermissionAllowed = isAllowed;
            visitPermissionHint = hint?.ToString();
        }));
        if (visitPermissionWasReported && !visitPermissionAllowed)
            throw new InvalidOperationException(string.IsNullOrWhiteSpace(visitPermissionHint) ? "The native Settlement overlay does not currently allow visiting this Hero" : visitPermissionHint);
        var visitTargetLocation = LocationComplex.Current?.GetLocationOfCharacter(visitSettlementTargetHero);
        if (visitTargetLocation == null) throw new InvalidOperationException("Native LocationComplex has no current Location for the selected Settlement overlay Hero");
        if (string.Equals(visitTargetLocation.StringId, "alley", StringComparison.Ordinal))
            visitTargetLocation = LocationComplex.Current.GetLocationWithId("center");
        TaleWorlds.CampaignSystem.CampaignEventDispatcher.Instance.OnPlayerStartTalkFromMenu(visitSettlementTargetHero);
        PlayerEncounter.LocationEncounter.CreateAndOpenMissionController(visitTargetLocation, null, visitSettlementTargetHero.CharacterObject);
        var visitData = "{\"heroId\":\"" + Escape(visitSettlementTargetHero.StringId) + "\",\"heroName\":\"" + Escape(visitSettlementTargetHero.Name?.ToString()) + "\"}";
        WriteResponse(commandId, action, "completed", behavior, null, visitData);
    }

    private void HandleDialogueSelect(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var conversationManager = Campaign.Current.ConversationManager;
        var dialogueOptionId = ReadString(command, "optionId");
        if (conversationManager == null || !conversationManager.IsConversationInProgress)
            throw new InvalidOperationException("dialogueSelect requires an active native conversation");
        var dialogueOption = conversationManager.CurOptions.FirstOrDefault(option => string.Equals(option.Id, dialogueOptionId, StringComparison.Ordinal));
        if (string.IsNullOrWhiteSpace(dialogueOption.Id) || !dialogueOption.IsClickable)
            throw new InvalidOperationException("conversation option is missing or not clickable");
        if (dialogueOption.HasPersuasion && !ChroniclePersuasionAdapter.IsVisiblePersuasionOption(dialogueOptionId))
            throw new InvalidOperationException("Persuasion argument is not present in the active Native conversation answer list");
        conversationManager.DoOption(dialogueOptionId);
        WriteResponse(commandId, action, "completed", behavior);
    }

    // Mission encounter conversations use MissionConversationLogic.ConversationManager, which is the same class
    // as Campaign.Current.ConversationManager but a different instance. These handlers act on the mission one,
    // so the Host can use the game's own listed options instead of inventing dialogue.
    private void HandleMissionConversationSelect(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var optionId = ReadString(command, "optionId");
        var manager = CurrentMissionConversationManager();
        if (manager == null || !manager.IsConversationInProgress)
            throw new InvalidOperationException("missionConversationSelect requires an active Mission conversation");
        var option = manager.CurOptions.FirstOrDefault(candidate => string.Equals(candidate.Id, optionId, StringComparison.Ordinal));
        if (string.IsNullOrWhiteSpace(option.Id) || !option.IsClickable)
            throw new InvalidOperationException("mission conversation option is missing or not clickable");
        manager.DoOption(optionId);
        WriteResponse(commandId, action, "completed", behavior);
    }

    private void HandleMissionConversationContinue(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var manager = CurrentMissionConversationManager();
        if (manager == null || !manager.IsConversationInProgress || manager.CurOptions.Count != 0)
            throw new InvalidOperationException("missionConversationContinue requires an active Mission conversation with no selectable options");
        manager.ContinueConversation();
        WriteResponse(commandId, action, "completed", behavior);
    }

    private static TaleWorlds.CampaignSystem.Conversation.ConversationManager CurrentMissionConversationManager()
    {
        var mission = TaleWorlds.MountAndBlade.Mission.Current;
        if (mission == null) return null;
        var logic = mission.MissionBehaviors.OfType<SandBox.Conversation.MissionLogics.MissionConversationLogic>().FirstOrDefault();
        return logic?.ConversationManager;
    }
    private void HandlePersuasionDetails(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChroniclePersuasionAdapter.ReadCurrentPersuasion());
    }

    private void HandleDialogueContinue(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var conversationToContinue = Campaign.Current.ConversationManager;
        if (conversationToContinue == null || !conversationToContinue.IsConversationInProgress || conversationToContinue.CurOptions.Count != 0)
            throw new InvalidOperationException("dialogueContinue requires an active conversation with no selectable options");
        conversationToContinue.ContinueConversation();
        WriteResponse(commandId, action, "completed", behavior);
    }
}
