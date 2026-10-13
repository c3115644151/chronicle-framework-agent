using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Text;
using Helpers;
using SandBox.View.Map;
using SandBox.View.Map.Navigation;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.GameState;
using TaleWorlds.CampaignSystem.Inventory;
using TaleWorlds.CampaignSystem.Party;
using TaleWorlds.CampaignSystem.ViewModelCollection.Inventory;
using TaleWorlds.Core;
using TaleWorlds.Library;
using TaleWorlds.Localization;
using TaleWorlds.ScreenSystem;

namespace ChronicleFramework;

internal static class ChronicleInventoryStateAdapter
{
    private sealed class PendingEquipmentDraft
    {
        public string Operation;
        public int EquipmentIndex;
        public SPInventoryVM.EquipmentModes EquipmentMode;
        public EquipmentElement TargetElement;
        public EquipmentElement PreviousElement;
        public int TargetPartyCountBefore;
        public int PreviousPartyCountBefore;
    }

    private static PendingEquipmentDraft _pendingEquipmentDraft;

    internal static string OpenThroughNativeMapNavigation(bool requireHarnessMode = false)
    {
        if (requireHarnessMode) RequireHarnessMode();
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("Native Inventory navigation requires the Campaign Map state");
        var mapScreen = ScreenManager.TopScreen as MapScreen;
        var navigationHandler = mapScreen?.NavigationHandler as MapNavigationHandler;
        var navigationElement = navigationHandler?.GetElement("inventory");
        if (navigationElement == null) throw new InvalidOperationException("Native MapScreen Inventory navigation element is unavailable");

        var timeModeBefore = Campaign.Current.TimeControlMode.ToString();
        var dayBefore = CampaignTime.Now.ToDays;
        navigationElement.OpenView();
        var isInventoryActive = Game.Current?.GameStateManager?.ActiveState is InventoryState;
        var json = new StringBuilder(512);
        json.Append('{').Append("\"schemaVersion\":1");
        ChroniclePartyUpgradeAdapter.Property(json, "entryId", navigationElement.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeBefore", timeModeBefore);
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeAfter", Campaign.Current.TimeControlMode.ToString());
        json.Append(",\"campaignDayBefore\":").Append(dayBefore.ToString("F6", System.Globalization.CultureInfo.InvariantCulture));
        json.Append(",\"campaignDayAfter\":").Append(CampaignTime.Now.ToDays.ToString("F6", System.Globalization.CultureInfo.InvariantCulture));
        json.Append(",\"inventoryStateActive\":").Append(ChroniclePartyUpgradeAdapter.Bool(isInventoryActive));
        return json.Append('}').ToString();
    }

    internal static string CloseAsNativeCancel(bool requireHarnessMode = false)
    {
        if (requireHarnessMode) RequireHarnessMode();
        if (Game.Current?.GameStateManager?.ActiveState is not InventoryState)
            throw new InvalidOperationException("Inventory cancel requires an active InventoryState");
        var timeModeBefore = Campaign.Current.TimeControlMode.ToString();
        var dayBefore = CampaignTime.Now.ToDays;
        InventoryScreenHelper.CloseScreen(fromCancel: true);
        var json = new StringBuilder(512);
        json.Append('{').Append("\"schemaVersion\":1");
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeBefore", timeModeBefore);
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeAfter", Campaign.Current.TimeControlMode.ToString());
        json.Append(",\"campaignDayBefore\":").Append(dayBefore.ToString("F6", System.Globalization.CultureInfo.InvariantCulture));
        json.Append(",\"campaignDayAfter\":").Append(CampaignTime.Now.ToDays.ToString("F6", System.Globalization.CultureInfo.InvariantCulture));
        json.Append(",\"returnedToMap\":").Append(ChroniclePartyUpgradeAdapter.Bool(Game.Current?.GameStateManager?.ActiveState is MapState));
        return json.Append('}').ToString();
    }

    internal static string BuildHarnessDiagnosticsJson()
    {
        RequireHarnessMode();
        return BuildHeroEquipmentOptionsJson(requireMainHero: true);
    }

    internal static string BuildHeroEquipmentOptionsJson()
    {
        return BuildHeroEquipmentOptionsJson(requireMainHero: true);
    }

    private static string BuildHeroEquipmentOptionsJson(bool requireMainHero)
    {
        if (Game.Current?.GameStateManager?.ActiveState is not InventoryState inventoryState || inventoryState.InventoryLogic == null)
            throw new InvalidOperationException("heroEquipmentOptions requires an active InventoryState with InventoryLogic");
        var viewModel = GetNativeViewModel(inventoryState);
        return BuildHeroEquipmentOptionsJson(inventoryState, viewModel, requireMainHero);
    }

    private static string BuildHeroEquipmentOptionsJson(InventoryState inventoryState, SPInventoryVM viewModel, bool requireMainHero = true)
    {
        var currentCharacter = GetCurrentCharacter(viewModel);
        if (requireMainHero && currentCharacter?.HeroObject != Hero.MainHero)
            throw new InvalidOperationException("heroEquipmentOptions currently requires MainHero selected in the native Inventory VM");
        if (inventoryState.InventoryMode != InventoryScreenHelper.InventoryMode.Default || inventoryState.InventoryLogic.IsTrading)
            throw new InvalidOperationException("heroEquipmentOptions supports only the native Default player InventoryState, not Loot/Trade/Stash");
        var json = new StringBuilder(8192);
        json.Append('{').Append("\"schemaVersion\":1");
        ChroniclePartyUpgradeAdapter.Property(json, "handlerType", inventoryState.Handler?.GetType().FullName);
        ChroniclePartyUpgradeAdapter.Property(json, "mainHeroId", Hero.MainHero.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "currentCharacterId", currentCharacter?.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "currentCharacterName", viewModel.CurrentCharacterName);
        ChroniclePartyUpgradeAdapter.Property(json, "equipmentMode", Enum.GetName(typeof(SPInventoryVM.EquipmentModes), viewModel.EquipmentMode));
        json.Append(",\"equipmentModeValue\":").Append(viewModel.EquipmentMode);
        ChroniclePartyUpgradeAdapter.Property(json, "inventoryMode", inventoryState.InventoryMode.ToString());
        json.Append(",\"timeControlMode\":\"").Append(ChroniclePartyUpgradeAdapter.Escape(Campaign.Current.TimeControlMode.ToString())).Append('"');
        json.Append(",\"campaignDay\":").Append(CampaignTime.Now.ToDays.ToString("F6", System.Globalization.CultureInfo.InvariantCulture));
        json.Append(",\"isMainHeroSelected\":").Append(ChroniclePartyUpgradeAdapter.Bool(string.Equals(viewModel.CurrentCharacterName, CharacterObject.PlayerCharacter.Name.ToString(), StringComparison.Ordinal)));
        json.Append(",\"isDoneDisabled\":").Append(ChroniclePartyUpgradeAdapter.Bool(viewModel.IsDoneDisabled));
        json.Append(",\"playerItemCount\":").Append(inventoryState.InventoryLogic.GetElementCountOnSide(InventoryLogic.InventorySide.PlayerInventory));
        json.Append(",\"rightItems\":[");
        for (var index = 0; index < viewModel.RightItemListVM.Count; index++)
        {
            if (index > 0) json.Append(',');
            AppendItem(json, viewModel.RightItemListVM[index], index);
        }
        json.Append(']');
        json.Append(",\"equipmentSlots\":[");
        var slots = GetEquipmentSlotViewModels(viewModel);
        for (var index = 0; index < slots.Length; index++)
        {
            if (index > 0) json.Append(',');
            var item = slots[index].Item;
            json.Append('{');
            ChroniclePartyUpgradeAdapter.Property(json, "slotName", slots[index].Property.Name, addComma: false);
            json.Append(",\"equipmentIndex\":").Append((int)slots[index].EquipmentIndex);
            ChroniclePartyUpgradeAdapter.Property(json, "viewModelItemId", item?.StringId);
            ChroniclePartyUpgradeAdapter.Property(json, "itemId", item?.ItemRosterElement.EquipmentElement.Item?.StringId);
            ChroniclePartyUpgradeAdapter.Property(json, "modifierId", item?.ItemRosterElement.EquipmentElement.ItemModifier?.StringId);
            ChroniclePartyUpgradeAdapter.Property(json, "inventorySide", item?.InventorySide.ToString());
            json.Append('}');
        }
        json.Append("]}");
        return json.ToString();
    }

    internal static string DraftEquipOneMainHeroItem(string itemViewModelId, int equipmentIndex)
    {
        var inventoryState = RequireMainHeroDefaultInventoryState(out var viewModel);
        if (inventoryState.InventoryLogic.IsThereAnyChanges())
            throw new InvalidOperationException("Commit or cancel the current native Inventory draft before another equipment change");
        if (string.IsNullOrWhiteSpace(itemViewModelId)) throw new InvalidOperationException("itemViewModelId is required from the current heroEquipmentOptions result");
        var candidates = viewModel.RightItemListVM.Where(item => item != null && string.Equals(item.StringId, itemViewModelId, StringComparison.Ordinal)).ToArray();
        if (candidates.Length != 1) throw new InvalidOperationException("itemViewModelId is missing or ambiguous in the current native Inventory VM");
        var item = candidates[0];
        if (item.InventorySide != InventoryLogic.InventorySide.PlayerInventory || item.ItemCount < 1 || !item.IsTransferable)
            throw new InvalidOperationException("itemViewModelId is not a transferable PlayerInventory item in the current native VM");
        if (!item.CanCharacterUseItem) throw new InvalidOperationException("Native SPInventoryVM says MainHero cannot use this item");
        var targetSlot = GetEquipmentSlotViewModels(viewModel).FirstOrDefault(slot => (int)slot.EquipmentIndex == equipmentIndex);
        if (targetSlot.Item == null) throw new InvalidOperationException("equipmentIndex is not a current native MainHero equipment slot");

        var modeBefore = Campaign.Current.TimeControlMode.ToString();
        var dayBefore = CampaignTime.Now.ToDays;
        var before = BuildHeroEquipmentOptionsJson(inventoryState, viewModel);
        var equipmentElement = item.ItemRosterElement.EquipmentElement;
        var inventoryElementCountBefore = GetExactMainPartyItemCount(equipmentElement);
        var previousElement = targetSlot.Item.ItemRosterElement.EquipmentElement;
        var previousInventoryCountBefore = previousElement.IsEmpty ? 0 : GetExactMainPartyItemCount(previousElement);
        viewModel.ExecuteTransferWithParameters(item, 0, "Equipment_" + equipmentIndex.ToString(System.Globalization.CultureInfo.InvariantCulture));
        if (!inventoryState.InventoryLogic.IsThereAnyChanges())
            throw new InvalidOperationException("Native SPInventoryVM rejected the equipment transfer; no transaction draft was created");
        _pendingEquipmentDraft = new PendingEquipmentDraft
        {
            Operation = "equip",
            EquipmentIndex = equipmentIndex,
            EquipmentMode = (SPInventoryVM.EquipmentModes)viewModel.EquipmentMode,
            TargetElement = equipmentElement,
            PreviousElement = previousElement,
            TargetPartyCountBefore = inventoryElementCountBefore,
            PreviousPartyCountBefore = previousInventoryCountBefore
        };

        var json = new StringBuilder(8192);
        json.Append('{').Append("\"schemaVersion\":1");
        ChroniclePartyUpgradeAdapter.Property(json, "itemViewModelId", itemViewModelId);
        ChroniclePartyUpgradeAdapter.Property(json, "itemId", equipmentElement.Item?.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "modifierId", equipmentElement.ItemModifier?.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "slotName", targetSlot.Property.Name);
        json.Append(",\"equipmentIndex\":").Append(equipmentIndex);
        ChroniclePartyUpgradeAdapter.Property(json, "equipmentMode", Enum.GetName(typeof(SPInventoryVM.EquipmentModes), viewModel.EquipmentMode));
        json.Append(",\"inventoryElementCountBefore\":").Append(inventoryElementCountBefore);
        json.Append(",\"draftCreatedByNativeVM\":true");
        json.Append(",\"isDoneDisabled\":").Append(ChroniclePartyUpgradeAdapter.Bool(viewModel.IsDoneDisabled));
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeBefore", modeBefore);
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeAfter", Campaign.Current.TimeControlMode.ToString());
        json.Append(",\"campaignDayBefore\":").Append(dayBefore.ToString("F6", System.Globalization.CultureInfo.InvariantCulture));
        json.Append(",\"campaignDayAfter\":").Append(CampaignTime.Now.ToDays.ToString("F6", System.Globalization.CultureInfo.InvariantCulture));
        json.Append(",\"before\":").Append(before);
        json.Append(",\"draft\":").Append(BuildHeroEquipmentOptionsJson(inventoryState, viewModel));
        return json.Append('}').ToString();
    }

    internal static string DraftUnequipMainHeroItem(int equipmentIndex)
    {
        var inventoryState = RequireMainHeroDefaultInventoryState(out var viewModel);
        if (inventoryState.InventoryLogic.IsThereAnyChanges())
            throw new InvalidOperationException("Commit or cancel the current native Inventory draft before another equipment change");
        var targetSlot = GetEquipmentSlotViewModels(viewModel).FirstOrDefault(slot => (int)slot.EquipmentIndex == equipmentIndex);
        if (targetSlot.Item == null || string.IsNullOrEmpty(targetSlot.Item.StringId) || targetSlot.Item.ItemRosterElement.EquipmentElement.IsEmpty)
            throw new InvalidOperationException("equipmentIndex is not occupied in the current native MainHero Equipment mode");

        var modeBefore = Campaign.Current.TimeControlMode.ToString();
        var dayBefore = CampaignTime.Now.ToDays;
        var before = BuildHeroEquipmentOptionsJson(inventoryState, viewModel);
        var equipmentElement = targetSlot.Item.ItemRosterElement.EquipmentElement;
        var inventoryElementCountBefore = GetExactMainPartyItemCount(equipmentElement);
        viewModel.ExecuteTransferWithParameters(targetSlot.Item, 0, "PlayerInventory");
        if (!inventoryState.InventoryLogic.IsThereAnyChanges())
            throw new InvalidOperationException("Native SPInventoryVM rejected the unequip transfer; no transaction draft was created");
        _pendingEquipmentDraft = new PendingEquipmentDraft
        {
            Operation = "unequip",
            EquipmentIndex = equipmentIndex,
            EquipmentMode = (SPInventoryVM.EquipmentModes)viewModel.EquipmentMode,
            TargetElement = equipmentElement,
            PreviousElement = EquipmentElement.Invalid,
            TargetPartyCountBefore = inventoryElementCountBefore,
            PreviousPartyCountBefore = 0
        };

        var json = new StringBuilder(8192);
        json.Append('{').Append("\"schemaVersion\":1");
        ChroniclePartyUpgradeAdapter.Property(json, "itemId", equipmentElement.Item?.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "modifierId", equipmentElement.ItemModifier?.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "slotName", targetSlot.Property.Name);
        json.Append(",\"equipmentIndex\":").Append(equipmentIndex);
        ChroniclePartyUpgradeAdapter.Property(json, "equipmentMode", Enum.GetName(typeof(SPInventoryVM.EquipmentModes), viewModel.EquipmentMode));
        json.Append(",\"inventoryElementCountBefore\":").Append(inventoryElementCountBefore);
        json.Append(",\"draftCreatedByNativeVM\":true");
        json.Append(",\"isDoneDisabled\":").Append(ChroniclePartyUpgradeAdapter.Bool(viewModel.IsDoneDisabled));
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeBefore", modeBefore);
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeAfter", Campaign.Current.TimeControlMode.ToString());
        json.Append(",\"campaignDayBefore\":").Append(dayBefore.ToString("F6", System.Globalization.CultureInfo.InvariantCulture));
        json.Append(",\"campaignDayAfter\":").Append(CampaignTime.Now.ToDays.ToString("F6", System.Globalization.CultureInfo.InvariantCulture));
        json.Append(",\"before\":").Append(before);
        json.Append(",\"draft\":").Append(BuildHeroEquipmentOptionsJson(inventoryState, viewModel));
        return json.Append('}').ToString();
    }

    internal static string CommitCurrentNativeTransaction()
    {
        var inventoryState = RequireMainHeroDefaultInventoryState(out var viewModel);
        if (!inventoryState.InventoryLogic.IsThereAnyChanges()) throw new InvalidOperationException("There is no native Inventory transaction to confirm");
        if (viewModel.IsDoneDisabled) throw new InvalidOperationException("Native Inventory Done is disabled; draft was not committed");
        if (_pendingEquipmentDraft == null) throw new InvalidOperationException("No Chronicle H08 equipment draft is registered for this Inventory transaction");
        var handler = inventoryState.Handler;
        var confirm = handler.GetType().GetMethod("ExecuteConfirm", BindingFlags.Instance | BindingFlags.Public);
        if (confirm == null || confirm.GetParameters().Length != 0) throw new MissingMethodException(handler.GetType().FullName, "ExecuteConfirm()");
        var before = BuildHeroEquipmentOptionsJson(inventoryState, viewModel);
        var timeModeBefore = Campaign.Current.TimeControlMode.ToString();
        var dayBefore = CampaignTime.Now.ToDays;
        var pendingDraft = _pendingEquipmentDraft;
        confirm.Invoke(handler, null);
        var returnedToMap = Game.Current?.GameStateManager?.ActiveState is MapState;
        var remainsInventory = Game.Current?.GameStateManager?.ActiveState is InventoryState;
        var actualModeEquipment = GetEquipmentForMode(pendingDraft.EquipmentMode);
        var actualSlotElement = actualModeEquipment.GetEquipmentFromSlot((EquipmentIndex)pendingDraft.EquipmentIndex);
        var targetCountAfter = GetExactMainPartyItemCount(pendingDraft.TargetElement);
        var previousCountAfter = pendingDraft.PreviousElement.IsEmpty ? 0 : GetExactMainPartyItemCount(pendingDraft.PreviousElement);
        var postconditionPassed = pendingDraft.Operation == "equip"
            ? actualSlotElement.IsEqualTo(pendingDraft.TargetElement) && targetCountAfter == pendingDraft.TargetPartyCountBefore - 1 && (pendingDraft.PreviousElement.IsEmpty || previousCountAfter == pendingDraft.PreviousPartyCountBefore + 1)
            : actualSlotElement.IsEmpty && targetCountAfter == pendingDraft.TargetPartyCountBefore + 1;
        if (returnedToMap && postconditionPassed) _pendingEquipmentDraft = null;
        var json = new StringBuilder(8192);
        json.Append('{').Append("\"schemaVersion\":1");
        json.Append(",\"committed\":").Append(ChroniclePartyUpgradeAdapter.Bool(returnedToMap && postconditionPassed));
        json.Append(",\"nativeTransactionClosed\":").Append(ChroniclePartyUpgradeAdapter.Bool(returnedToMap));
        json.Append(",\"postconditionPassed\":").Append(ChroniclePartyUpgradeAdapter.Bool(postconditionPassed));
        json.Append(",\"operation\":\"").Append(ChroniclePartyUpgradeAdapter.Escape(pendingDraft.Operation)).Append('"');
        json.Append(",\"equipmentIndex\":").Append(pendingDraft.EquipmentIndex);
        ChroniclePartyUpgradeAdapter.Property(json, "equipmentMode", pendingDraft.EquipmentMode.ToString());
        json.Append(",\"targetPartyCountBefore\":").Append(pendingDraft.TargetPartyCountBefore);
        json.Append(",\"targetPartyCountAfter\":").Append(targetCountAfter);
        json.Append(",\"previousPartyCountBefore\":").Append(pendingDraft.PreviousPartyCountBefore);
        json.Append(",\"previousPartyCountAfter\":").Append(previousCountAfter);
        ChroniclePartyUpgradeAdapter.Property(json, "equippedItemAfter", actualSlotElement.Item?.StringId);
        json.Append(",\"inventoryStateStillActive\":").Append(ChroniclePartyUpgradeAdapter.Bool(remainsInventory));
        json.Append(",\"mainHeroId\":\"").Append(ChroniclePartyUpgradeAdapter.Escape(Hero.MainHero.StringId)).Append('"');
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeBefore", timeModeBefore);
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeAfter", Campaign.Current.TimeControlMode.ToString());
        json.Append(",\"campaignDayBefore\":").Append(dayBefore.ToString("F6", System.Globalization.CultureInfo.InvariantCulture));
        json.Append(",\"campaignDayAfter\":").Append(CampaignTime.Now.ToDays.ToString("F6", System.Globalization.CultureInfo.InvariantCulture));
        json.Append(",\"before\":").Append(before);
        json.Append(",\"partyItemCountAfter\":").Append(MobileParty.MainParty.ItemRoster.Sum(element => element.Amount));
        return json.Append('}').ToString();
    }

    internal static string CancelCurrentNativeTransaction(bool confirmDiscardChanges)
    {
        var inventoryState = RequireMainHeroDefaultInventoryState(out var viewModel);
        var hasPendingChanges = inventoryState.InventoryLogic.IsThereAnyChanges();
        if (hasPendingChanges && !confirmDiscardChanges)
            throw new InvalidOperationException("Native Inventory has pending changes; use inventoryCancelChanges only after the Agent chooses to discard them");
        if (!hasPendingChanges && confirmDiscardChanges)
            throw new InvalidOperationException("There are no pending Inventory changes to discard");
        var handler = inventoryState.Handler;
        var cancel = handler.GetType().GetMethod("ExecuteCancel", BindingFlags.Instance | BindingFlags.Public);
        if (cancel == null || cancel.GetParameters().Length != 0) throw new MissingMethodException(handler.GetType().FullName, "ExecuteCancel()");

        InquiryData confirmedInquiry = null;
        Action<InquiryData, bool, bool> inquiryHandler = (inquiry, pauseGameActiveState, prioritize) =>
        {
            var expectedText = GameTexts.FindText("str_cancelling_changes").ToString();
            if (!confirmDiscardChanges || confirmedInquiry != null || inquiry == null || inquiry.AffirmativeAction == null || !string.Equals(inquiry.Text, expectedText, StringComparison.Ordinal))
                return;
            confirmedInquiry = inquiry;
            InformationManager.HideInquiry();
            inquiry.AffirmativeAction.Invoke();
        };

        InformationManager.OnShowInquiry += inquiryHandler;
        try { cancel.Invoke(handler, null); }
        finally { InformationManager.OnShowInquiry -= inquiryHandler; }

        if (confirmDiscardChanges && confirmedInquiry == null)
            throw new InvalidOperationException("Native Inventory Cancel did not show the expected discard-changes inquiry; it was not auto-confirmed");
        if (Game.Current?.GameStateManager?.ActiveState is MapState) _pendingEquipmentDraft = null;
        return "{\"schemaVersion\":1,\"cancelRequested\":true,\"discardConfirmed\":" + ChroniclePartyUpgradeAdapter.Bool(confirmDiscardChanges) + ",\"returnedToMap\":" + ChroniclePartyUpgradeAdapter.Bool(Game.Current?.GameStateManager?.ActiveState is MapState) + ",\"inventoryStateStillActive\":" + ChroniclePartyUpgradeAdapter.Bool(Game.Current?.GameStateManager?.ActiveState is InventoryState) + "}";
    }

    internal static SPInventoryVM GetNativeViewModel(InventoryState inventoryState)
    {
        if (inventoryState?.Handler == null) throw new InvalidOperationException("Gauntlet Inventory handler is not initialized");
        var dataSourceField = inventoryState.Handler.GetType().GetField("_dataSource", BindingFlags.Instance | BindingFlags.NonPublic);
        if (dataSourceField == null || dataSourceField.FieldType != typeof(SPInventoryVM))
            throw new MissingFieldException(inventoryState.Handler.GetType().FullName, "_dataSource: SPInventoryVM");
        if (dataSourceField.GetValue(inventoryState.Handler) is not SPInventoryVM viewModel)
            throw new InvalidOperationException("Native Gauntlet Inventory SPInventoryVM is not ready");
        return viewModel;
    }

    private static InventoryState RequireMainHeroDefaultInventoryState(out SPInventoryVM viewModel)
    {
        if (Game.Current?.GameStateManager?.ActiveState is not InventoryState inventoryState || inventoryState.InventoryLogic == null)
            throw new InvalidOperationException("H08 equipment actions require the native InventoryState");
        if (inventoryState.InventoryMode != InventoryScreenHelper.InventoryMode.Default || inventoryState.InventoryLogic.IsTrading)
            throw new InvalidOperationException("H08 equipment actions support only the Default player InventoryState, not Loot/Trade/Stash");
        viewModel = GetNativeViewModel(inventoryState);
        var currentCharacter = GetCurrentCharacter(viewModel);
        if (currentCharacter == null || currentCharacter.HeroObject != Hero.MainHero)
            throw new InvalidOperationException("H08 currently supports only MainHero selected in the native Inventory VM");
        return inventoryState;
    }

    internal static CharacterObject GetCurrentCharacter(SPInventoryVM viewModel)
    {
        var field = typeof(SPInventoryVM).GetField("_currentCharacter", BindingFlags.Instance | BindingFlags.NonPublic);
        if (field == null || field.FieldType != typeof(CharacterObject)) throw new MissingFieldException(typeof(SPInventoryVM).FullName, "_currentCharacter");
        return field.GetValue(viewModel) as CharacterObject;
    }

    private static (PropertyInfo Property, SPItemVM Item, EquipmentIndex EquipmentIndex)[] GetEquipmentSlotViewModels(SPInventoryVM viewModel)
    {
        var slotLookup = viewModel.GetType().GetMethods(BindingFlags.Instance | BindingFlags.NonPublic)
            .FirstOrDefault(method => method.Name == "GetItemFromIndex" && method.GetParameters().Length == 1 && method.GetParameters()[0].ParameterType == typeof(EquipmentIndex));
        if (slotLookup == null) throw new MissingMethodException(viewModel.GetType().FullName, "GetItemFromIndex(EquipmentIndex)");
        var slotProperties = viewModel.GetType().GetProperties(BindingFlags.Instance | BindingFlags.Public)
            .Where(property => property.Name.StartsWith("Character", StringComparison.Ordinal) && property.Name.EndsWith("Slot", StringComparison.Ordinal) && property.PropertyType == typeof(SPItemVM))
            .ToArray();
        var slots = new List<(PropertyInfo Property, SPItemVM Item, EquipmentIndex EquipmentIndex)>();
        var seenIndices = new HashSet<int>();
        foreach (EquipmentIndex equipmentIndex in Enum.GetValues(typeof(EquipmentIndex)))
        {
            var equipmentIndexValue = (int)equipmentIndex;
            if (equipmentIndexValue < 0 || equipmentIndexValue >= (int)EquipmentIndex.NumEquipmentSetSlots || !seenIndices.Add(equipmentIndexValue)) continue;
            if (slotLookup.Invoke(viewModel, new object[] { equipmentIndex }) is not SPItemVM item) continue;
            var property = slotProperties.FirstOrDefault(candidate => ReferenceEquals(candidate.GetValue(viewModel, null), item));
            if (property != null) slots.Add((property, item, equipmentIndex));
        }
        return slots.OrderBy(slot => (int)slot.EquipmentIndex).ToArray();
    }

    private static int GetExactMainPartyItemCount(EquipmentElement element)
    {
        var roster = MobileParty.MainParty.ItemRoster;
        var index = roster.FindIndexOfElement(element);
        return index < 0 ? 0 : roster.GetElementNumber(index);
    }

    private static Equipment GetEquipmentForMode(SPInventoryVM.EquipmentModes equipmentMode)
    {
        return equipmentMode switch
        {
            SPInventoryVM.EquipmentModes.Battle => Hero.MainHero.BattleEquipment,
            SPInventoryVM.EquipmentModes.Civilian => Hero.MainHero.CivilianEquipment,
            SPInventoryVM.EquipmentModes.Stealth => Hero.MainHero.StealthEquipment,
            _ => throw new InvalidOperationException("Unsupported native MainHero EquipmentMode " + equipmentMode)
        };
    }

    private static void AppendItem(StringBuilder json, SPItemVM item, int listIndex)
    {
        json.Append('{');
        ChroniclePartyUpgradeAdapter.Property(json, "viewModelItemId", item.StringId, addComma: false);
        ChroniclePartyUpgradeAdapter.Property(json, "itemId", item.ItemRosterElement.EquipmentElement.Item?.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "modifierId", item.ItemRosterElement.EquipmentElement.ItemModifier?.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "name", item.ItemRosterElement.EquipmentElement.GetModifiedItemName().ToString());
        ChroniclePartyUpgradeAdapter.Property(json, "inventorySide", item.InventorySide.ToString());
        json.Append(",\"itemType\":").Append((int)item.ItemType);
        json.Append(",\"listIndex\":").Append(listIndex);
        json.Append(",\"itemCount\":").Append(item.ItemCount);
        json.Append(",\"isTransferable\":").Append(ChroniclePartyUpgradeAdapter.Bool(item.IsTransferable));
        json.Append(",\"canCharacterUseItem\":").Append(ChroniclePartyUpgradeAdapter.Bool(item.CanCharacterUseItem));
        json.Append('}');
    }

    private static void RequireHarnessMode()
    {
        var mode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var root = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(mode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(root) || !System.IO.Directory.Exists(root))
            throw new InvalidOperationException("Inventory State navigation/diagnostics are restricted to visual Harness runs with a Harness temp directory");
    }
}
