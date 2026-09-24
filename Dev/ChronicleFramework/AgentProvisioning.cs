using System;
using System.Linq;
using System.Text;
using Helpers;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.Inventory;
using TaleWorlds.CampaignSystem.Party;
using TaleWorlds.CampaignSystem.Roster;
using TaleWorlds.CampaignSystem.Settlements;
using TaleWorlds.Core;
using TaleWorlds.Localization;

namespace ChronicleFramework;

internal static class ChronicleAgentProvisioning
{
    internal static string GetFoodOptionsJson()
    {
        var settlement = GetCurrentTown();
        var logic = CreateTownTradeLogic(settlement, attachMerchantListener: false);
            var foodItems = logic.GetElementsInRoster(InventoryLogic.InventorySide.OtherInventory)
                .Where(item => item.EquipmentElement.Item != null && item.EquipmentElement.Item.IsFood && item.Amount > 0)
                .Select(item => new
                {
                    Element = item,
                    Price = logic.GetItemPrice(item.EquipmentElement, isBuying: true)
                })
                .OrderBy(item => item.Price)
                .ToArray();

            var json = new StringBuilder(2048);
            json.Append('{');
            Property(json, "settlementId", Settlement.CurrentSettlement.StringId);
            json.Append(",\"gold\":").Append(Hero.MainHero.Gold);
            json.Append(",\"partyFood\":").Append(Number(MobileParty.MainParty.Food));
            json.Append(",\"partyFoodInventory\":").Append(MobileParty.MainParty.TotalFoodAtInventory);
            json.Append(",\"offers\":[");
            for (var index = 0; index < foodItems.Length; index++)
            {
                if (index > 0) json.Append(',');
                var food = foodItems[index];
                json.Append('{');
                Property(json, "itemId", food.Element.EquipmentElement.Item.StringId);
                Property(json, "name", food.Element.EquipmentElement.Item.Name?.ToString(), true);
                json.Append(",\"stock\":").Append(food.Element.Amount);
                json.Append(",\"unitPrice\":").Append(food.Price);
                json.Append(",\"unitWeight\":").Append(Number(food.Element.EquipmentElement.Weight));
                json.Append('}');
            }
            json.Append("]}");
            return json.ToString();
    }

    internal static string GetTradeOptionsJson()
    {
        var settlement = GetCurrentTown();
        var logic = CreateTownTradeLogic(settlement, attachMerchantListener: false);
        var marketItems = logic.GetElementsInRoster(InventoryLogic.InventorySide.OtherInventory)
            .Where(item => item.EquipmentElement.Item != null && item.Amount > 0)
            .Select(item => new { Element = item, Price = logic.GetItemPrice(item.EquipmentElement, isBuying: true) })
            .OrderBy(item => item.Price)
            .ToArray();
        var partyItems = logic.GetElementsInRoster(InventoryLogic.InventorySide.PlayerInventory)
            .Where(item => item.EquipmentElement.Item != null && item.Amount > 0)
            .Select(item => new { Element = item, Price = logic.GetItemPrice(item.EquipmentElement, isBuying: false) })
            .OrderBy(item => item.Price)
            .ToArray();

        var json = new StringBuilder(4096);
        json.Append('{');
        Property(json, "settlementId", settlement.StringId);
        json.Append(",\"gold\":").Append(Hero.MainHero.Gold);
        AppendOffers(json, "buyOffers", marketItems, item => item.Element, item => item.Price);
        AppendOffers(json, "sellOffers", partyItems, item => item.Element, item => item.Price);
        json.Append('}');
        return json.ToString();
    }

    internal static string BuyFood(string itemId, int amount)
    {
        return TradeItem("buy", itemId, amount, requireFood: true);
    }

    internal static string TradeItem(string direction, string itemId, int amount, bool requireFood = false)
    {
        if (direction != "buy" && direction != "sell") throw new InvalidOperationException("trade direction must be buy or sell");
        if (amount <= 0) throw new InvalidOperationException("trade amount must be greater than zero");
        var settlement = GetCurrentTown();
        var logic = CreateTownTradeLogic(settlement, attachMerchantListener: true);
        var committed = false;
        try
        {
            var isBuying = direction == "buy";
            var sourceSide = isBuying ? InventoryLogic.InventorySide.OtherInventory : InventoryLogic.InventorySide.PlayerInventory;
            var destinationSide = isBuying ? InventoryLogic.InventorySide.PlayerInventory : InventoryLogic.InventorySide.OtherInventory;
            var sourceRoster = logic.GetElementsInRoster(sourceSide);
            var element = sourceRoster.FirstOrDefault(item => item.EquipmentElement.Item != null && string.Equals(item.EquipmentElement.Item.StringId, itemId, StringComparison.Ordinal));
            if (element.EquipmentElement.Item == null || (requireFood && !element.EquipmentElement.Item.IsFood))
                throw new InvalidOperationException(isBuying ? "item not found in this settlement market" : "item not found in player inventory");
            if (element.Amount < amount) throw new InvalidOperationException(isBuying ? "market stock is lower than requested amount" : "player stock is lower than requested amount");

            var beforeGold = Hero.MainHero.Gold;
            var beforeFood = MobileParty.MainParty.TotalFoodAtInventory;
            var beforePartyCount = Count(logic.GetElementsInRoster(InventoryLogic.InventorySide.PlayerInventory), itemId);
            var beforeMarketCount = Count(logic.GetElementsInRoster(InventoryLogic.InventorySide.OtherInventory), itemId);
            var command = TransferCommand.Transfer(
                amount,
                sourceSide,
                destinationSide,
                new ItemRosterElement(element.EquipmentElement, amount),
                EquipmentIndex.None,
                EquipmentIndex.None,
                CharacterObject.PlayerCharacter);
            logic.AddTransferCommand(command);
            var totalAmount = logic.TotalAmount;
            if (!logic.CanPlayerCompleteTransaction())
            {
                logic.Reset(fromCancel: true);
                throw new InvalidOperationException("purchase exceeds available gold or inventory capacity");
            }
            if (!logic.DoneLogic())
            {
                logic.Reset(fromCancel: true);
                throw new InvalidOperationException("native inventory transaction was not accepted");
            }
            committed = true;

            var afterGold = Hero.MainHero.Gold;
            var afterFood = MobileParty.MainParty.TotalFoodAtInventory;
            var afterPartyCount = Count(MobileParty.MainParty.ItemRoster, itemId);
            var afterMarketCount = Count(settlement.ItemRoster, itemId);
            var expectedPartyDelta = isBuying ? amount : -amount;
            var expectedMarketDelta = -expectedPartyDelta;
            var verified = afterPartyCount - beforePartyCount == expectedPartyDelta && afterMarketCount - beforeMarketCount == expectedMarketDelta && beforeGold - afterGold == totalAmount && (!requireFood || (isBuying ? afterFood > beforeFood : afterFood < beforeFood));
            var json = new StringBuilder();
            json.Append('{');
            Property(json, "direction", direction);
            Property(json, "itemId", itemId, true);
            json.Append(",\"amount\":").Append(amount);
            json.Append(",\"transactionAmount\":").Append(totalAmount);
            json.Append(",\"beforeGold\":").Append(beforeGold);
            json.Append(",\"afterGold\":").Append(afterGold);
            json.Append(",\"beforeFoodInventory\":").Append(beforeFood);
            json.Append(",\"afterFoodInventory\":").Append(afterFood);
            json.Append(",\"verified\":").Append(verified ? "true" : "false");
            json.Append('}');
            return json.ToString();
        }
        finally
        {
            if (!committed && logic.IsThereAnyChanges()) logic.Reset(fromCancel: true);
        }
    }

    private static int Count(System.Collections.Generic.IEnumerable<ItemRosterElement> roster, string itemId) => roster.Where(item => item.EquipmentElement.Item != null && string.Equals(item.EquipmentElement.Item.StringId, itemId, StringComparison.Ordinal)).Sum(item => item.Amount);
    private static int Count(ItemRoster roster, string itemId) => Count(roster.ToList(), itemId);

    private static void AppendOffers<T>(StringBuilder json, string key, T[] offers, Func<T, ItemRosterElement> getElement, Func<T, int> getPrice)
    {
        json.Append(",\"").Append(key).Append("\":[");
        var index = 0;
        foreach (var offer in offers)
        {
            if (index++ > 0) json.Append(',');
            var element = getElement(offer);
            json.Append('{');
            Property(json, "itemId", element.EquipmentElement.Item.StringId);
            Property(json, "name", element.EquipmentElement.Item.Name?.ToString(), true);
            json.Append(",\"stock\":").Append(element.Amount);
            json.Append(",\"unitPrice\":").Append(getPrice(offer));
            json.Append(",\"unitWeight\":").Append(Number(element.EquipmentElement.Weight));
            json.Append(",\"isFood\":").Append(element.EquipmentElement.Item.IsFood ? "true" : "false");
            json.Append('}');
        }
        json.Append(']');
    }

    private static Settlement GetCurrentTown()
    {
        var settlement = Settlement.CurrentSettlement;
        if (settlement == null || !settlement.IsTown || settlement.Town == null)
            throw new InvalidOperationException("food market access requires the main party to be in a town");
        return settlement;
    }

    private static InventoryLogic CreateTownTradeLogic(Settlement settlement, bool attachMerchantListener)
    {
        var logic = new InventoryLogic(settlement.SettlementComponent.Owner);
        logic.Initialize(
            settlement.ItemRoster,
            MobileParty.MainParty.ItemRoster,
            MobileParty.MainParty.MemberRoster,
            isTrading: true,
            isSpecialActionsPermitted: true,
            CharacterObject.PlayerCharacter,
            InventoryScreenHelper.InventoryCategoryType.None,
            settlement.Town.MarketData,
            useBasePrices: false,
            InventoryScreenHelper.InventoryMode.Trade);
        logic.TotalAmountChange = _ => { };
        logic.DonationXpChange = () => { };
        if (attachMerchantListener) logic.SetInventoryListener(new ChronicleMerchantInventoryListener(settlement.SettlementComponent));
        return logic;
    }

    private sealed class ChronicleMerchantInventoryListener : InventoryListener
    {
        private readonly SettlementComponent _settlementComponent;
        internal ChronicleMerchantInventoryListener(SettlementComponent settlementComponent) => _settlementComponent = settlementComponent;
        public override int GetGold() => _settlementComponent.Gold;
        public override TextObject GetTraderName() => _settlementComponent.Owner.Name;
        public override void SetGold(int gold) => _settlementComponent.ChangeGold(gold - _settlementComponent.Gold);
        public override PartyBase GetOppositeParty() => _settlementComponent.Owner;
        public override void OnTransaction() => throw new NotImplementedException();
    }

    private static StringBuilder Property(StringBuilder json, string key, string value, bool prependComma = false)
    {
        if (prependComma) json.Append(',');
        json.Append('\"').Append(Escape(key)).Append("\":\"").Append(Escape(value)).Append('\"');
        return json;
    }

    private static string Number(double value) => value.ToString("0.###", System.Globalization.CultureInfo.InvariantCulture);
    private static string Escape(string value) => (value ?? string.Empty).Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\r", "\\r").Replace("\n", "\\n");
}
