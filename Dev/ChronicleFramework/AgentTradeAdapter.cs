using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Text;
using Helpers;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.GameState;
using TaleWorlds.CampaignSystem.Inventory;
using TaleWorlds.CampaignSystem.Party;
using TaleWorlds.CampaignSystem.Roster;
using TaleWorlds.CampaignSystem.Settlements;
using TaleWorlds.CampaignSystem.ViewModelCollection.Inventory;
using TaleWorlds.Core;
using TaleWorlds.Library;

namespace ChronicleFramework;

internal static class ChronicleAgentTradeAdapter
{
    private sealed class PendingTradeDraft
    {
        internal string Direction;
        internal string ItemViewModelId;
        internal string SettlementId;
        internal EquipmentElement Element;
        internal int Amount;
        internal int PlayerCountBefore;
        internal int MarketCountBefore;
        internal int PlayerGoldBefore;
        internal int MerchantGoldBefore;
        internal int TransactionAmount;
        internal string TimeControlModeBefore;
        internal double CampaignDayBefore;
    }

    private static PendingTradeDraft _pendingDraft;

    internal static string BuildTradeOptionsJson()
    {
        var inventoryState = RequireNativeTradeState(out var viewModel);
        var settlement = Settlement.CurrentSettlement;
        var items = GetTradeItems(viewModel).ToArray();
        var json = new StringBuilder(8192);
        json.Append('{').Append("\"schemaVersion\":1");
        ChroniclePartyUpgradeAdapter.Property(json, "settlementId", settlement.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "inventoryMode", inventoryState.InventoryMode.ToString());
        ChroniclePartyUpgradeAdapter.Property(json, "equipmentMode", Enum.GetName(typeof(SPInventoryVM.EquipmentModes), viewModel.EquipmentMode));
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlMode", Campaign.Current.TimeControlMode.ToString());
        json.Append(",\"campaignDay\":").Append(CampaignTime.Now.ToDays.ToString("F6", System.Globalization.CultureInfo.InvariantCulture));
        json.Append(",\"playerGold\":").Append(Hero.MainHero.Gold);
        json.Append(",\"merchantGold\":").Append(settlement.SettlementComponent.Gold);
        json.Append(",\"playerItemCount\":").Append(inventoryState.InventoryLogic.GetElementCountOnSide(InventoryLogic.InventorySide.PlayerInventory));
        json.Append(",\"marketItemCount\":").Append(inventoryState.InventoryLogic.GetElementCountOnSide(InventoryLogic.InventorySide.OtherInventory));
        json.Append(",\"isDoneDisabled\":").Append(ChroniclePartyUpgradeAdapter.Bool(viewModel.IsDoneDisabled));
        json.Append(",\"hasPendingChanges\":").Append(ChroniclePartyUpgradeAdapter.Bool(inventoryState.InventoryLogic.IsThereAnyChanges()));
        AppendOffers(json, "buyOffers", items.Where(item => item.InventorySide == InventoryLogic.InventorySide.OtherInventory), inventoryState.InventoryLogic, isBuying: true);
        AppendOffers(json, "sellOffers", items.Where(item => item.InventorySide == InventoryLogic.InventorySide.PlayerInventory), inventoryState.InventoryLogic, isBuying: false);
        return json.Append('}').ToString();
    }

    internal static string BuildFoodOptionsJson()
    {
        var inventoryState = RequireNativeTradeState(out var viewModel);
        var settlement = Settlement.CurrentSettlement;
        var offers = GetTradeItems(viewModel)
            .Where(item => item.InventorySide == InventoryLogic.InventorySide.OtherInventory && item.ItemRosterElement.EquipmentElement.Item.IsFood)
            .ToArray();
        var json = new StringBuilder(4096);
        json.Append('{').Append("\"schemaVersion\":1");
        ChroniclePartyUpgradeAdapter.Property(json, "settlementId", settlement.StringId);
        json.Append(",\"playerGold\":").Append(Hero.MainHero.Gold);
        json.Append(",\"partyFoodInventory\":").Append(MobileParty.MainParty.TotalFoodAtInventory);
        json.Append(",\"hasPendingChanges\":").Append(ChroniclePartyUpgradeAdapter.Bool(inventoryState.InventoryLogic.IsThereAnyChanges()));
        AppendOffers(json, "offers", offers, inventoryState.InventoryLogic, isBuying: true);
        return json.Append('}').ToString();
    }

    internal static string DraftTradeItem(string direction, string itemViewModelId, string inventorySide, int amount, bool requireFood = false)
    {
        if (!string.Equals(direction, "buy", StringComparison.Ordinal) && !string.Equals(direction, "sell", StringComparison.Ordinal))
            throw new InvalidOperationException("trade direction must be buy or sell");
        if (string.IsNullOrWhiteSpace(itemViewModelId)) throw new InvalidOperationException("itemViewModelId must come from the current native tradeOptions result");
        if (amount <= 0) throw new InvalidOperationException("trade amount must be greater than zero");
        if (_pendingDraft != null) throw new InvalidOperationException("Commit or cancel the current Native Trade draft before another transaction");

        var inventoryState = RequireNativeTradeState(out var viewModel);
        var logic = inventoryState.InventoryLogic;
        if (logic.IsThereAnyChanges()) throw new InvalidOperationException("Native Trade Inventory contains an untracked draft; cancel or commit it before another action");
        var expectedSide = direction == "buy" ? InventoryLogic.InventorySide.OtherInventory : InventoryLogic.InventorySide.PlayerInventory;
        if (!string.Equals(inventorySide, expectedSide.ToString(), StringComparison.Ordinal))
            throw new InvalidOperationException("InventorySide does not match the current buy/sell direction");
        var candidates = GetTradeItems(viewModel).Where(item => item.InventorySide == expectedSide && string.Equals(item.StringId, itemViewModelId, StringComparison.Ordinal)).ToArray();
        if (candidates.Length != 1) throw new InvalidOperationException("itemViewModelId is stale, missing or ambiguous in the current Native Trade VM");
        var item = candidates[0];
        if (item.InventorySide != expectedSide) throw new InvalidOperationException("itemViewModelId is not on the Native Trade side selected by direction");
        if (item.ItemCount < 1 || amount > item.ItemCount || !item.IsTransferable)
            throw new InvalidOperationException("trade amount or item transferability is not valid for the current Native Trade candidate");
        var element = item.ItemRosterElement.EquipmentElement;
        if (element.Item == null) throw new InvalidOperationException("Native Trade candidate has no EquipmentElement item");
        if (requireFood && !element.Item.IsFood) throw new InvalidOperationException("provision accepts only a current Native Trade food candidate");

        var settlement = Settlement.CurrentSettlement;
        var playerCountBefore = CountExact(MobileParty.MainParty.ItemRoster, element);
        var marketCountBefore = CountExact(settlement.SettlementComponent.Owner.ItemRoster, element);
        var playerGoldBefore = Hero.MainHero.Gold;
        var merchantGoldBefore = settlement.SettlementComponent.Gold;
        var timeModeBefore = Campaign.Current.TimeControlMode.ToString();
        var dayBefore = CampaignTime.Now.ToDays;
        if (direction == "buy") item.ExecuteBuy(amount);
        else item.ExecuteSell(amount);
        if (!logic.IsThereAnyChanges()) throw new InvalidOperationException("Native SPItemVM did not create a Trade Inventory draft");

        var transactionAmount = logic.TotalAmount;
        var lacksGold = direction == "buy" && playerGoldBefore - transactionAmount < 0;
        if (lacksGold || viewModel.IsDoneDisabled || !logic.CanPlayerCompleteTransaction())
        {
            var reason = lacksGold ? "The Native Trade quote exceeds MainHero's current Gold" : "The Native Trade VM says this draft cannot be completed";
            var rollback = CancelCurrentNativeTradeTransaction(confirmDiscardChanges: true);
            if (Game.Current?.GameStateManager?.ActiveState is not MapState)
                throw new InvalidOperationException(reason + "; Native Cancel did not restore the Campaign Map");
            throw new InvalidOperationException(reason + "; the draft was discarded through the Native Trade Cancel inquiry");
        }

        _pendingDraft = new PendingTradeDraft
        {
            Direction = direction,
            ItemViewModelId = itemViewModelId,
            SettlementId = settlement.StringId,
            Element = element,
            Amount = amount,
            PlayerCountBefore = playerCountBefore,
            MarketCountBefore = marketCountBefore,
            PlayerGoldBefore = playerGoldBefore,
            MerchantGoldBefore = merchantGoldBefore,
            TransactionAmount = transactionAmount,
            TimeControlModeBefore = timeModeBefore,
            CampaignDayBefore = dayBefore
        };

        var json = new StringBuilder(1024);
        json.Append('{').Append("\"schemaVersion\":1");
        ChroniclePartyUpgradeAdapter.Property(json, "direction", direction);
        ChroniclePartyUpgradeAdapter.Property(json, "itemViewModelId", itemViewModelId);
        ChroniclePartyUpgradeAdapter.Property(json, "inventorySide", item.InventorySide.ToString());
        ChroniclePartyUpgradeAdapter.Property(json, "itemId", element.Item.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "modifierId", element.ItemModifier?.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "inventorySide", item.InventorySide.ToString());
        ChroniclePartyUpgradeAdapter.Property(json, "settlementId", settlement.StringId);
        json.Append(",\"amount\":").Append(amount);
        json.Append(",\"itemCountAvailable\":").Append(item.ItemCount);
        json.Append(",\"nativeItemCost\":").Append(item.ItemCost);
        json.Append(",\"nativeTransactionAmount\":").Append(transactionAmount);
        json.Append(",\"nativeCanCompleteTransaction\":").Append(ChroniclePartyUpgradeAdapter.Bool(logic.CanPlayerCompleteTransaction()));
        json.Append(",\"isDoneDisabled\":").Append(ChroniclePartyUpgradeAdapter.Bool(viewModel.IsDoneDisabled));
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeBefore", timeModeBefore);
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeAfter", Campaign.Current.TimeControlMode.ToString());
        json.Append(",\"campaignDayBefore\":").Append(dayBefore.ToString("F6", System.Globalization.CultureInfo.InvariantCulture));
        json.Append(",\"campaignDayAfter\":").Append(CampaignTime.Now.ToDays.ToString("F6", System.Globalization.CultureInfo.InvariantCulture));
        return json.Append('}').ToString();
    }

    internal static string CommitCurrentNativeTradeTransaction()
    {
        var inventoryState = RequireNativeTradeState(out var viewModel);
        if (_pendingDraft == null || !inventoryState.InventoryLogic.IsThereAnyChanges())
            throw new InvalidOperationException("There is no Chronicle native Trade draft to confirm");
        if (!string.Equals(Settlement.CurrentSettlement?.StringId, _pendingDraft.SettlementId, StringComparison.Ordinal))
            throw new InvalidOperationException("The Town changed while a native Trade draft was pending");
        if (viewModel.IsDoneDisabled || !inventoryState.InventoryLogic.CanPlayerCompleteTransaction())
            throw new InvalidOperationException("The Native Trade VM says this transaction cannot be completed; draft remains available for explicit cancel");

        var handler = inventoryState.Handler;
        var confirm = handler.GetType().GetMethod("ExecuteConfirm", BindingFlags.Instance | BindingFlags.Public);
        if (confirm == null || confirm.GetParameters().Length != 0) throw new MissingMethodException(handler.GetType().FullName, "ExecuteConfirm()");
        var pending = _pendingDraft;
        var timeModeBefore = Campaign.Current.TimeControlMode.ToString();
        var dayBefore = CampaignTime.Now.ToDays;
        confirm.Invoke(handler, null);
        var state = Game.Current?.GameStateManager?.ActiveState;
        var returnedToMapState = state is MapState;
        var tradeStillOpen = state is InventoryState remainingInventory && remainingInventory.InventoryMode == InventoryScreenHelper.InventoryMode.Trade;
        var currentSettlement = Settlement.CurrentSettlement;
        var playerCountAfter = CountExact(MobileParty.MainParty.ItemRoster, pending.Element);
        var marketCountAfter = CountExact(currentSettlement?.SettlementComponent?.Owner?.ItemRoster, pending.Element);
        var playerGoldAfter = Hero.MainHero.Gold;
        var merchantGoldAfter = currentSettlement?.SettlementComponent?.Gold ?? 0;
        var expectedPlayerCount = pending.Direction == "buy" ? pending.PlayerCountBefore + pending.Amount : pending.PlayerCountBefore - pending.Amount;
        var expectedMarketCount = pending.Direction == "buy" ? pending.MarketCountBefore - pending.Amount : pending.MarketCountBefore + pending.Amount;
        var expectedPlayerGold = pending.PlayerGoldBefore - pending.TransactionAmount;
        var expectedMerchantGold = pending.MerchantGoldBefore + pending.TransactionAmount;
        var postconditionPassed = returnedToMapState && !tradeStillOpen &&
            playerCountAfter == expectedPlayerCount && marketCountAfter == expectedMarketCount &&
            playerGoldAfter == expectedPlayerGold && merchantGoldAfter == expectedMerchantGold;
        if (returnedToMapState) _pendingDraft = null;

        var json = new StringBuilder(1024);
        json.Append('{').Append("\"schemaVersion\":1");
        json.Append(",\"committed\":").Append(ChroniclePartyUpgradeAdapter.Bool(postconditionPassed));
        json.Append(",\"nativeTransactionClosed\":").Append(ChroniclePartyUpgradeAdapter.Bool(returnedToMapState && !tradeStillOpen));
        json.Append(",\"postconditionPassed\":").Append(ChroniclePartyUpgradeAdapter.Bool(postconditionPassed));
        ChroniclePartyUpgradeAdapter.Property(json, "direction", pending.Direction);
        ChroniclePartyUpgradeAdapter.Property(json, "settlementId", pending.SettlementId);
        ChroniclePartyUpgradeAdapter.Property(json, "itemId", pending.Element.Item?.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "modifierId", pending.Element.ItemModifier?.StringId);
        json.Append(",\"amount\":").Append(pending.Amount);
        json.Append(",\"nativeTransactionAmount\":").Append(pending.TransactionAmount);
        json.Append(",\"playerCountBefore\":").Append(pending.PlayerCountBefore);
        json.Append(",\"playerCountAfter\":").Append(playerCountAfter);
        json.Append(",\"marketCountBefore\":").Append(pending.MarketCountBefore);
        json.Append(",\"marketCountAfter\":").Append(marketCountAfter);
        json.Append(",\"playerGoldBefore\":").Append(pending.PlayerGoldBefore);
        json.Append(",\"playerGoldAfter\":").Append(playerGoldAfter);
        json.Append(",\"merchantGoldBefore\":").Append(pending.MerchantGoldBefore);
        json.Append(",\"merchantGoldAfter\":").Append(merchantGoldAfter);
        json.Append(",\"campaignDayBefore\":").Append(pending.CampaignDayBefore.ToString("F6", System.Globalization.CultureInfo.InvariantCulture));
        json.Append(",\"campaignDayAfter\":").Append(CampaignTime.Now.ToDays.ToString("F6", System.Globalization.CultureInfo.InvariantCulture));
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeBefore", pending.TimeControlModeBefore);
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeAfter", timeModeBefore);
        json.Append(",\"campaignDayAtCommit\":").Append(dayBefore.ToString("F6", System.Globalization.CultureInfo.InvariantCulture));
        return json.Append('}').ToString();
    }

    internal static string CancelCurrentNativeTradeTransaction(bool confirmDiscardChanges)
    {
        var inventoryState = RequireNativeTradeState(out _);
        var hasPendingChanges = inventoryState.InventoryLogic.IsThereAnyChanges();
        if (hasPendingChanges && !confirmDiscardChanges)
            throw new InvalidOperationException("Native Trade Inventory has pending changes; use tradeCancelChanges only after the Agent chooses to discard them");
        if (!hasPendingChanges && confirmDiscardChanges)
            throw new InvalidOperationException("There are no pending Trade Inventory changes to discard");
        var handler = inventoryState.Handler;
        var cancel = handler.GetType().GetMethod("ExecuteCancel", BindingFlags.Instance | BindingFlags.Public);
        if (cancel == null || cancel.GetParameters().Length != 0) throw new MissingMethodException(handler.GetType().FullName, "ExecuteCancel()");
        InquiryData confirmedInquiry = null;
        Action<InquiryData, bool, bool> inquiryHandler = (inquiry, pauseGameActiveState, prioritize) =>
        {
            var expectedText = GameTexts.FindText("str_cancelling_changes").ToString();
            if (!confirmDiscardChanges || confirmedInquiry != null || inquiry?.AffirmativeAction == null || !string.Equals(inquiry.Text, expectedText, StringComparison.Ordinal)) return;
            confirmedInquiry = inquiry;
            InformationManager.HideInquiry();
            inquiry.AffirmativeAction.Invoke();
        };
        InformationManager.OnShowInquiry += inquiryHandler;
        try { cancel.Invoke(handler, null); }
        finally { InformationManager.OnShowInquiry -= inquiryHandler; }
        if (confirmDiscardChanges && confirmedInquiry == null)
            throw new InvalidOperationException("Native Trade Cancel did not show the expected discard-changes inquiry; it was not auto-confirmed");
        var returnedToMap = Game.Current?.GameStateManager?.ActiveState is MapState;
        if (returnedToMap) _pendingDraft = null;
        return "{\"schemaVersion\":1,\"cancelRequested\":true,\"discardConfirmed\":" + ChroniclePartyUpgradeAdapter.Bool(confirmDiscardChanges) + ",\"returnedToMap\":" + ChroniclePartyUpgradeAdapter.Bool(returnedToMap) + ",\"tradeStateStillActive\":" + ChroniclePartyUpgradeAdapter.Bool(Game.Current?.GameStateManager?.ActiveState is InventoryState active && active.InventoryMode == InventoryScreenHelper.InventoryMode.Trade) + "}";
    }

    private static InventoryState RequireNativeTradeState(out SPInventoryVM viewModel)
    {
        if (Game.Current?.GameStateManager?.ActiveState is not InventoryState inventoryState || inventoryState.InventoryLogic == null)
            throw new InvalidOperationException("Trade actions require an active Native Trade InventoryState");
        if (inventoryState.InventoryMode != InventoryScreenHelper.InventoryMode.Trade || !inventoryState.InventoryLogic.IsTrading)
            throw new InvalidOperationException("Trade actions require the current native Trade Inventory mode");
        viewModel = ChronicleInventoryStateAdapter.GetNativeViewModel(inventoryState);
        if (ChronicleInventoryStateAdapter.GetCurrentCharacter(viewModel)?.HeroObject != Hero.MainHero)
            throw new InvalidOperationException("Trade actions currently require the Native Trade VM to show MainHero");
        if (Settlement.CurrentSettlement?.IsTown != true || Settlement.CurrentSettlement.SettlementComponent == null)
            throw new InvalidOperationException("Trade actions require the main party in a Town with an active merchant");
        return inventoryState;
    }

    private static IEnumerable<SPItemVM> GetTradeItems(SPInventoryVM viewModel)
    {
        return viewModel.LeftItemListVM.Cast<SPItemVM>().Concat(viewModel.RightItemListVM.Cast<SPItemVM>())
            .Where(item => item != null && item.ItemRosterElement.EquipmentElement.Item != null && item.ItemCount > 0);
    }

    private static void AppendOffers(StringBuilder json, string key, IEnumerable<SPItemVM> items, InventoryLogic logic, bool isBuying)
    {
        json.Append(",\"").Append(key).Append("\":[");
        var first = true;
        foreach (var item in items)
        {
            if (!first) json.Append(',');
            first = false;
            var element = item.ItemRosterElement.EquipmentElement;
            json.Append('{');
            ChroniclePartyUpgradeAdapter.Property(json, "viewModelItemId", item.StringId, addComma: false);
            ChroniclePartyUpgradeAdapter.Property(json, "itemId", element.Item.StringId);
            ChroniclePartyUpgradeAdapter.Property(json, "modifierId", element.ItemModifier?.StringId);
            ChroniclePartyUpgradeAdapter.Property(json, "name", element.GetModifiedItemName().ToString());
            ChroniclePartyUpgradeAdapter.Property(json, "inventorySide", item.InventorySide.ToString());
            json.Append(",\"stock\":").Append(item.ItemCount);
            json.Append(",\"nativeItemCost\":").Append(item.ItemCost);
            json.Append(",\"inventoryLogicUnitPrice\":").Append(logic.GetItemPrice(element, isBuying));
            json.Append(",\"unitWeight\":").Append(Number(element.Weight));
            json.Append(",\"isFood\":").Append(ChroniclePartyUpgradeAdapter.Bool(element.Item.IsFood));
            json.Append(",\"isTransferable\":").Append(ChroniclePartyUpgradeAdapter.Bool(item.IsTransferable));
            json.Append('}');
        }
        json.Append(']');
    }

    private static int CountExact(ItemRoster roster, EquipmentElement element)
    {
        var index = roster.FindIndexOfElement(element);
        return index < 0 ? 0 : roster.GetElementNumber(index);
    }

    private static float Number(float value) => float.IsNaN(value) || float.IsInfinity(value) ? 0f : value;
}
