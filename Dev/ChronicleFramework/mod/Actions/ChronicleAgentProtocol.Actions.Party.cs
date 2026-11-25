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
    private void HandleCharacterDevelopment(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("characterDevelopment requires the Campaign Map state");
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentObserver.BuildCharacterDevelopmentJson());
    }

    private void HandleSpendSkillFocus(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("spendSkillFocus requires the Campaign Map state");
        WriteResponse(commandId, action, "completed", behavior, null, SpendMainHeroSkillFocus(command));
    }

    private void HandlePartyUpgradeOptions(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("partyUpgradeOptions requires the Campaign Map state");
        WriteResponse(commandId, action, "completed", behavior, null, ChroniclePartyUpgradeAdapter.BuildOptionsJson());
    }

    private void HandleUpgradeTroop(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("upgradeTroop requires the Campaign Map state");
        var upgradeTroopId = ReadString(command, "troopId");
        var upgradeTargetIndex = ReadRequiredInteger(command, "upgradeTargetIndex");
        WriteResponse(commandId, action, "completed", behavior, null, ChroniclePartyUpgradeAdapter.UpgradeOneTroopJson(upgradeTroopId, upgradeTargetIndex));
    }

    private void HandlePrisonerRecruitmentOptions(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("prisonerRecruitmentOptions requires the Campaign Map state");
        WriteResponse(commandId, action, "completed", behavior, null, ChroniclePartyPrisonerRecruitmentAdapter.BuildOptionsJson());
    }

    private void HandleRecruitPrisoner(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("recruitPrisoner requires the Campaign Map state");
        WriteResponse(commandId, action, "completed", behavior, null, ChroniclePartyPrisonerRecruitmentAdapter.RecruitOneJson(
            ReadString(command, "troopId"),
            ReadDouble(command, "confirmPartySizeWarning") > 0.5,
            ReadDouble(command, "confirmPrisonerLimitWarning") > 0.5));
    }

    private void HandleQuestDetails(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var questDetailsId = ReadString(command, "questId");
        if (string.IsNullOrWhiteSpace(questDetailsId)) throw new InvalidOperationException("questId must come from a previously observed Quest entry");
        var activeQuestDetails = Campaign.Current?.QuestManager?.Quests
            .Where(quest => quest != null && quest.IsOngoing)
            .Take(12)
            .FirstOrDefault(quest => string.Equals(quest.StringId, questDetailsId, StringComparison.Ordinal));
        if (activeQuestDetails != null)
        {
            WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentObserver.BuildQuestDetailsJson(activeQuestDetails));
            return;
        }
        var terminalQuestDetails = behavior.FindQuestTerminalOutcomeJson(questDetailsId);
        if (string.IsNullOrWhiteSpace(terminalQuestDetails))
            throw new InvalidOperationException("questId is not active or a Native terminal outcome previously observed in this Campaign");
        WriteResponse(commandId, action, "completed", behavior, null, terminalQuestDetails);
    }

    private void HandlePartyRoster(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("partyRoster requires the Campaign Map state");
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentObserver.BuildPartyRosterJson());
    }

    private void HandlePartyRoles(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChroniclePartyRoleAdapter.BuildMainPartyRolesJson());
    }

    private void HandleInventoryOpen(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleInventoryStateAdapter.OpenThroughNativeMapNavigation());
    }

    private void HandleHeroEquipmentOptions(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleInventoryStateAdapter.BuildHeroEquipmentOptionsJson());
    }

    private void HandleEquipHeroItem(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleInventoryStateAdapter.DraftEquipOneMainHeroItem(ReadString(command, "itemViewModelId"), ReadRequiredInteger(command, "equipmentIndex")));
    }

    private void HandleUnequipHeroItem(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleInventoryStateAdapter.DraftUnequipMainHeroItem(ReadRequiredInteger(command, "equipmentIndex")));
    }

    private void HandleInventoryConfirm(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleInventoryStateAdapter.CommitCurrentNativeTransaction());
    }

    private void HandleInventoryCancel(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleInventoryStateAdapter.CancelCurrentNativeTransaction(confirmDiscardChanges: false));
    }

    private void HandleInventoryCancelChanges(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleInventoryStateAdapter.CancelCurrentNativeTransaction(confirmDiscardChanges: true));
    }

    private void HandleSetPartyRole(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChroniclePartyRoleAdapter.SetMainPartyRoleJson(ReadString(command, "roleId"), ReadString(command, "heroId"), removeAssignee: false));
    }

    private void HandleUnassignPartyRole(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChroniclePartyRoleAdapter.SetMainPartyRoleJson(ReadString(command, "roleId"), null, removeAssignee: true));
    }

    private void HandleInventoryTakeAll(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var lootInventoryState = Game.Current.GameStateManager.ActiveState as InventoryState;
        if (lootInventoryState?.InventoryLogic == null || lootInventoryState.InventoryMode != Helpers.InventoryScreenHelper.InventoryMode.Loot)
            throw new InvalidOperationException("inventoryTakeAll requires the native postbattle Loot InventoryState");
        var inventoryHandler = lootInventoryState.Handler;
        if (inventoryHandler == null || lootInventoryState.InventoryLogic.GetElementCountOnSide(TaleWorlds.CampaignSystem.Inventory.InventoryLogic.InventorySide.OtherInventory) <= 0)
            throw new InvalidOperationException("native InventoryState has no loot items or UI handler");
        inventoryHandler.ExecuteLootingScript();
        WriteResponse(commandId, action, "completed", behavior);
    }

    private void HandleInventoryDone(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var lootInventoryStateToClose = Game.Current.GameStateManager.ActiveState as InventoryState;
        if (lootInventoryStateToClose?.InventoryLogic == null || lootInventoryStateToClose.InventoryMode != Helpers.InventoryScreenHelper.InventoryMode.Loot)
            throw new InvalidOperationException("inventoryDone requires the native postbattle Loot InventoryState");
        if (lootInventoryStateToClose.InventoryLogic.GetElementCountOnSide(TaleWorlds.CampaignSystem.Inventory.InventoryLogic.InventorySide.OtherInventory) > 0)
            throw new InvalidOperationException("inventoryDone refuses to skip the Native 'leave loot behind' confirmation; take all remaining battle loot first");
        Helpers.InventoryScreenHelper.CloseScreen(fromCancel: false);
        WriteResponse(commandId, action, "completed", behavior);
    }

    private void HandleRecruitOptions(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        _recruitmentViewModel = ChronicleAgentRecruitment.CreateOrRefresh(_recruitmentViewModel);
        try
        {
            WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentRecruitment.BuildOptionsJson(_recruitmentViewModel));
        }
        finally
        {
            FinalizeVolunteerRecruitmentViewModel();
        }
    }

    private void HandleRecruit(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        _recruitmentViewModel = ChronicleAgentRecruitment.CreateOrRefresh(_recruitmentViewModel);
        var recruitOwnerId = ReadString(command, "ownerId");
        var recruitTroopId = ReadString(command, "troopId");
        var recruitSlot = (int)ReadDouble(command, "slot");
        var recruitConfirmCapacity = ReadDouble(command, "confirmPartySizeWarning") > 0.5;
        try
        {
            var recruitmentResult = ChronicleAgentRecruitment.Recruit(_recruitmentViewModel, recruitOwnerId, recruitTroopId, recruitSlot, recruitConfirmCapacity);
            WriteResponse(commandId, action, "completed", behavior, null, recruitmentResult);
        }
        finally
        {
            FinalizeVolunteerRecruitmentViewModel();
        }
    }

    private void HandleRecruitAll(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        _recruitmentViewModel = ChronicleAgentRecruitment.CreateOrRefresh(_recruitmentViewModel);
        try
        {
            var recruitAllResult = ChronicleAgentRecruitment.RecruitAll(
                _recruitmentViewModel,
                (int)ReadDouble(command, "expectedCount"),
                (int)ReadDouble(command, "expectedTotalCost"),
                (int)ReadDouble(command, "expectedPartySize"),
                (int)ReadDouble(command, "expectedPartyCapacity"),
                (int)ReadDouble(command, "expectedJournalTarget"),
                ReadString(command, "expectedOfferSetSha256"));
            WriteResponse(commandId, action, "completed", behavior, null, recruitAllResult);
        }
        finally
        {
            FinalizeVolunteerRecruitmentViewModel();
        }
    }

    private void HandlePartyTakeAll(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var activeLootPartyState = Game.Current.GameStateManager.ActiveState as PartyState;
        var lootTypeName = ReadString(command, "troopType");
        if (activeLootPartyState?.PartyScreenLogic == null || activeLootPartyState.PartyScreenMode.ToString() != "Loot")
            throw new InvalidOperationException("partyTakeAll requires the native postbattle loot PartyState");
        var lootTroopType = lootTypeName == "members"
            ? PartyScreenLogic.TroopType.Member
            : lootTypeName == "prisoners" ? PartyScreenLogic.TroopType.Prisoner : (PartyScreenLogic.TroopType?)null;
        if (!lootTroopType.HasValue) throw new InvalidOperationException("troopType must be members or prisoners");
        var lootRoster = activeLootPartyState.PartyScreenLogic.GetRoster(PartyScreenLogic.PartyRosterSide.Left, lootTroopType.Value);
        if (lootRoster.Count == 0 || !lootRoster.GetTroopRoster().Any(element => element.Character != null && element.Number > 0 && activeLootPartyState.PartyScreenLogic.IsTroopTransferable(lootTroopType.Value, element.Character, (int)PartyScreenLogic.PartyRosterSide.Left)))
            throw new InvalidOperationException("no transferable loot of the requested type is available");
        var takeAllCommand = new PartyScreenLogic.PartyCommand();
        takeAllCommand.FillForTransferAllTroops(PartyScreenLogic.PartyRosterSide.Left, lootTroopType.Value);
        activeLootPartyState.PartyScreenLogic.AddCommand(takeAllCommand);
        activeLootPartyState.PartyScreenLogic.RemoveZeroCounts();
        WriteResponse(commandId, action, "completed", behavior);
    }

    private void HandlePartyLootTransferOne(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null,
            ChronicleLootPartyTransferAdapter.TransferOne(ReadString(command, "troopId"), ReadString(command, "troopType")));
    }

    private void HandleSellPrisonerOne(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null,
            ChronicleRansomPrisonerSaleAdapter.TransferOne(ReadString(command, "troopId")));
    }

    private void HandlePartyScreenCancel(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var activeCancelPartyState = Game.Current.GameStateManager.ActiveState as PartyState;
        if (activeCancelPartyState?.PartyScreenMode.ToString() != "Ransom")
            throw new InvalidOperationException("partyScreenCancel requires the native prisoner-sale Ransom PartyState");
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleRansomPrisonerSaleAdapter.Cancel());
    }

    private void HandlePartyScreenDone(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        if (ChronicleAlleyRosterAdapter.IsCurrentNativeAlleyPartyScreen())
        {
            var alleyRosterDone = ChronicleAlleyRosterAdapter.Done();
            WriteResponse(commandId, action, "completed", behavior, null, alleyRosterDone);
            return;
        }
        var activeDonePartyState = Game.Current.GameStateManager.ActiveState as PartyState;
        if (activeDonePartyState?.PartyScreenMode.ToString() == "Ransom")
        {
            WriteResponse(commandId, action, "completed", behavior, null, ChronicleRansomPrisonerSaleAdapter.Done());
            return;
        }
        var lootPartyStateToClose = Game.Current.GameStateManager.ActiveState as PartyState;
        if (lootPartyStateToClose?.PartyScreenLogic == null || lootPartyStateToClose.PartyScreenMode.ToString() is not ("Loot" or "Ransom"))
            throw new InvalidOperationException("partyScreenDone requires the native postbattle Loot or prisoner-sale Ransom PartyState");
        if (!lootPartyStateToClose.PartyScreenLogic.IsDoneActive()) throw new InvalidOperationException("native PartyScreen Done is unavailable");
        var partyScreenHandler = lootPartyStateToClose.Handler as IPartyScreenPrisonHandler;
        if (partyScreenHandler == null) throw new InvalidOperationException("native PartyScreen Done handler is unavailable");
        partyScreenHandler.ExecuteDoneScript();
        WriteResponse(commandId, action, "completed", behavior);
    }

    private void HandleQuestTroopTransfer(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null,
            ChronicleQuestTroopScreenAdapter.TransferOne(ReadString(command, "troopId"), ReadString(command, "sourceSide")));
    }

    private void HandleQuestTroopScreenDone(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleQuestTroopScreenAdapter.Done());
    }

    private void HandleQuestTroopScreenCancel(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleQuestTroopScreenAdapter.Cancel());
    }

    private void HandleAlleyRosterTransfer(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null,
            ChronicleAlleyRosterAdapter.TransferOne(ReadString(command, "troopId"), ReadString(command, "sourceSide")));
    }

    private void HandleAlleyRosterCancel(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAlleyRosterAdapter.Cancel());
    }
}
