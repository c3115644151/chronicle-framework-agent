using System;
using System.Globalization;
using System.Linq;
using System.Text;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.GameMenus;
using TaleWorlds.CampaignSystem.GameState;
using TaleWorlds.CampaignSystem.Encounters;
using TaleWorlds.CampaignSystem.Party;
using TaleWorlds.CampaignSystem.Settlements;
using TaleWorlds.Core;

namespace ChronicleFramework;

internal static class ChronicleAgentObserver
{
    internal static string BuildSnapshotJson()
    {
        var campaign = Campaign.Current;
        var hero = Hero.MainHero;
        var clan = Clan.PlayerClan;
        var party = MobileParty.MainParty;
        if (campaign == null || hero == null || party == null) return "null";

        var position = party.GetPosition2D;
        var radius = Math.Max(12f, party.SeeingRange);
        var settlements = Settlement.All
            .Where(item => item != null && item.IsActive && item.IsVisible)
            .Select(item => new { Item = item, Distance = Distance(position.X, position.Y, item.GetPosition2D.X, item.GetPosition2D.Y) })
            .Where(item => item.Distance <= radius)
            .OrderBy(item => item.Distance)
            .Take(8)
            .ToArray();
        var parties = MobileParty.All
            .Where(item => item != null && item != party && item.IsActive && item.IsVisible)
            .Select(item => new { Item = item, Distance = Distance(position.X, position.Y, item.GetPosition2D.X, item.GetPosition2D.Y) })
            .Where(item => item.Distance <= radius)
            .OrderBy(item => item.Distance)
            .Take(12)
            .ToArray();
        var hostileParties = parties.Where(item => IsHostile(party.MapFaction, item.Item.MapFaction)).ToArray();
        var quests = campaign.QuestManager?.Quests.Where(item => item.IsOngoing).Take(12).ToArray() ?? Array.Empty<QuestBase>();
        var menu = campaign.CurrentMenuContext?.GameMenu;
        var encounteredParty = PlayerEncounter.IsActive ? PlayerEncounter.EncounteredParty : null;

        var json = new StringBuilder(4096);
        json.Append('{');
        json.Append("\"schemaVersion\":8");
        json.Append(",\"campaignDay\":").Append(Number(CampaignTime.Now.ToDays));
        json.Append(",\"identity\":{");
        Property(json, "heroId", hero.StringId); Property(json, "heroName", hero.Name?.ToString(), true);
        Property(json, "clanId", clan?.StringId, true); Property(json, "clanName", clan?.Name?.ToString(), true);
        json.Append(",\"clanTier\":").Append(clan?.Tier ?? 0);
        json.Append(",\"nextTierRequiredRenown\":");
        if (clan != null && clan.Tier < campaign.Models.ClanTierModel.MaxClanTier)
            json.Append(Number(clan.RenownRequirementForNextTier));
        else
            json.Append("null");
        json.Append(",\"mercenaryRequiredTier\":").Append(campaign.Models.ClanTierModel.MercenaryEligibleTier).Append('}');
        json.Append(",\"economy\":{");
        json.Append("\"gold\":").Append(hero.Gold);
        json.Append(",\"influence\":").Append(Number(clan?.Influence ?? 0));
        json.Append(",\"renown\":").Append(Number(clan?.Renown ?? 0)).Append('}');
        json.Append(",\"party\":{");
        Property(json, "id", party.StringId); Property(json, "name", party.Name?.ToString(), true);
        json.Append(",\"members\":").Append(party.MemberRoster.TotalManCount);
        json.Append(",\"healthy\":").Append(party.MemberRoster.TotalHealthyCount);
        json.Append(",\"wounded\":").Append(party.MemberRoster.TotalWounded);
        json.Append(",\"prisoners\":").Append(party.PrisonRoster.TotalManCount);
        json.Append(",\"itemCount\":").Append(TotalItemCount(party.ItemRoster));
        json.Append(",\"sizeLimit\":").Append(party.Party.PartySizeLimit);
        json.Append(",\"speed\":").Append(Number(party.Speed));
        json.Append(",\"morale\":").Append(Number(party.Morale));
        json.Append(",\"food\":").Append(Number(party.Food));
        json.Append(",\"foodInventory\":").Append(party.TotalFoodAtInventory);
        json.Append(",\"foodChange\":").Append(Number(party.FoodChange));
        json.Append(",\"dailyWage\":").Append(party.TotalWage);
        json.Append(",\"cargoWeight\":").Append(Number(party.TotalWeightCarried));
        json.Append(",\"cargoCapacity\":").Append(party.InventoryCapacity);
        json.Append(",\"isMoving\":").Append(Bool(party.IsMoving));
        Property(json, "moveMode", party.PartyMoveMode.ToString(), true);
        Property(json, "defaultBehavior", party.DefaultBehavior.ToString(), true);
        json.Append(",\"isAtSea\":").Append(Bool(party.IsCurrentlyAtSea)).Append('}');
        json.Append(",\"location\":{");
        json.Append("\"x\":").Append(Number(position.X)).Append(",\"y\":").Append(Number(position.Y));
        Property(json, "currentSettlementId", party.CurrentSettlement?.StringId, true);
        Property(json, "targetSettlementId", party.TargetSettlement?.StringId, true);
        Property(json, "targetPartyId", party.TargetParty?.StringId, true).Append('}');
        json.Append(",\"context\":{");
        Property(json, "gameState", Game.Current?.GameStateManager?.ActiveState?.GetType().Name);
        Property(json, "timeControlMode", campaign.TimeControlMode.ToString(), true);
        Property(json, "menuId", menu?.StringId, true);
        json.Append(",\"encounterActive\":").Append(Bool(PlayerEncounter.IsActive));
        json.Append(",\"lootItemCount\":");
        if (PlayerEncounter.Current == null) json.Append("null");
        else json.Append(TotalItemCount(PlayerEncounter.Current.RosterToReceiveLootItems));
        Property(json, "encounteredPartyId", encounteredParty?.Id, true);
        Property(json, "encounteredPartyName", encounteredParty?.Name?.ToString(), true);
        json.Append(",\"isWaiting\":").Append(Bool(campaign.IsMainPartyWaiting));
        var battleSimulation = PlayerEncounter.CurrentBattleSimulation;
        json.Append(",\"battleSimulation\":");
        if (battleSimulation == null)
        {
            json.Append("null");
        }
        else
        {
            json.Append('{');
            json.Append("\"finished\":").Append(Bool(battleSimulation.IsSimulationFinished));
            json.Append(",\"playerRetreated\":").Append(Bool(battleSimulation.IsPlayerRetreated));
            Property(json, "battleState", battleSimulation.MapEvent?.BattleState.ToString(), true);
            json.Append('}');
        }
        json.Append(",\"conversation\":");
        var conversationManager = campaign.ConversationManager;
        if (conversationManager == null || !conversationManager.IsConversationInProgress)
        {
            json.Append("null");
        }
        else
        {
            json.Append('{');
            Property(json, "sentenceText", conversationManager.CurrentSentenceText);
            json.Append(",\"options\":[");
            var conversationOptions = conversationManager.CurOptions;
            for (var index = 0; index < conversationOptions.Count; index++)
            {
                if (index > 0) json.Append(',');
                var option = conversationOptions[index];
                json.Append('{');
                Property(json, "id", option.Id);
                Property(json, "text", option.Text?.ToString(), true);
                json.Append(",\"clickable\":").Append(Bool(option.IsClickable));
                Property(json, "hint", option.HintText?.ToString(), true);
                json.Append('}');
            }
            json.Append("]}");
        }
        json.Append('}');
        var activePartyState = Game.Current.GameStateManager.ActiveState as PartyState;
        json.Append(",\"partyScreen\":");
        if (activePartyState?.PartyScreenLogic == null)
        {
            json.Append("null");
        }
        else
        {
            var screen = activePartyState.PartyScreenLogic;
            json.Append('{');
            Property(json, "mode", activePartyState.PartyScreenMode.ToString());
            json.Append(",\"canDone\":").Append(Bool(screen.IsDoneActive()));
            Property(json, "leftPartyId", screen.LeftOwnerParty?.Id, true);
            Property(json, "rightPartyId", screen.RightOwnerParty?.Id, true);
            AppendPartyRoster(json, "leftMembers", screen, PartyScreenLogic.PartyRosterSide.Left, PartyScreenLogic.TroopType.Member);
            AppendPartyRoster(json, "leftPrisoners", screen, PartyScreenLogic.PartyRosterSide.Left, PartyScreenLogic.TroopType.Prisoner);
            AppendPartyRoster(json, "rightMembers", screen, PartyScreenLogic.PartyRosterSide.Right, PartyScreenLogic.TroopType.Member);
            AppendPartyRoster(json, "rightPrisoners", screen, PartyScreenLogic.PartyRosterSide.Right, PartyScreenLogic.TroopType.Prisoner);
            json.Append('}');
        }
        var activeInventoryState = Game.Current.GameStateManager.ActiveState as InventoryState;
        json.Append(",\"inventoryScreen\":");
        if (activeInventoryState?.InventoryLogic == null)
        {
            json.Append("null");
        }
        else
        {
            var inventoryLogic = activeInventoryState.InventoryLogic;
            json.Append('{');
            Property(json, "mode", activeInventoryState.InventoryMode.ToString());
            json.Append(",\"lootItemCount\":").Append(inventoryLogic.GetElementCountOnSide(TaleWorlds.CampaignSystem.Inventory.InventoryLogic.InventorySide.OtherInventory));
            json.Append(",\"playerItemCount\":").Append(inventoryLogic.GetElementCountOnSide(TaleWorlds.CampaignSystem.Inventory.InventoryLogic.InventorySide.PlayerInventory));
            json.Append(",\"hasHandler\":").Append(Bool(activeInventoryState.Handler != null));
            json.Append('}');
        }
        json.Append(",\"availableMenuOptions\":").Append(BuildMenuOptionsJson(campaign.CurrentMenuContext));
        json.Append(",\"nearbySettlements\":[");
        for (var index = 0; index < settlements.Length; index++)
        {
            if (index > 0) json.Append(',');
            var item = settlements[index].Item;
            json.Append('{'); Property(json, "id", item.StringId); Property(json, "name", item.Name?.ToString(), true);
            Property(json, "type", item.IsTown ? "town" : item.IsCastle ? "castle" : item.IsVillage ? "village" : item.IsHideout ? "hideout" : "other", true);
            json.Append(",\"distance\":").Append(Number(settlements[index].Distance));
            json.Append(",\"hostile\":").Append(Bool(IsHostile(party.MapFaction, item.MapFaction)));
            json.Append(",\"underSiege\":").Append(Bool(item.IsUnderSiege)).Append('}');
        }
        json.Append(']');
        json.Append(",\"nearbyParties\":[");
        for (var index = 0; index < parties.Length; index++)
        {
            if (index > 0) json.Append(',');
            var item = parties[index].Item;
            json.Append('{'); Property(json, "id", item.StringId); Property(json, "name", item.Name?.ToString(), true);
            Property(json, "type", PartyType(item), true);
            json.Append(",\"distance\":").Append(Number(parties[index].Distance));
            json.Append(",\"hostile\":").Append(Bool(IsHostile(party.MapFaction, item.MapFaction)));
            json.Append(",\"isMoving\":").Append(Bool(item.IsMoving));
            Property(json, "currentSettlementId", item.CurrentSettlement?.StringId, true);
            json.Append(",\"members\":").Append(item.MemberRoster.TotalManCount);
            json.Append(",\"strength\":").Append(Number(item.Party.EstimatedStrength)).Append('}');
        }
        json.Append(']');
        json.Append(",\"quests\":[");
        for (var index = 0; index < quests.Length; index++)
        {
            if (index > 0) json.Append(',');
            json.Append('{'); Property(json, "id", quests[index].StringId); Property(json, "title", quests[index].Title?.ToString(), true);
            json.Append(",\"dueDay\":").Append(Number(quests[index].QuestDueTime.ToDays)).Append('}');
        }
        json.Append(']');
        json.Append(",\"danger\":{");
        json.Append("\"hostilePartyCount\":").Append(hostileParties.Length);
        json.Append(",\"nearestHostileDistance\":").Append(hostileParties.Length == 0 ? "null" : Number(hostileParties[0].Distance));
        json.Append(",\"hostileStrength\":").Append(Number(hostileParties.Sum(item => item.Item.Party.EstimatedStrength))).Append('}');
        json.Append('}');
        return json.ToString();
    }

    private static void AppendPartyRoster(StringBuilder json, string propertyName, PartyScreenLogic logic, PartyScreenLogic.PartyRosterSide side, PartyScreenLogic.TroopType type)
    {
        json.Append(",\"").Append(propertyName).Append("\":[");
        var roster = logic.GetRoster(side, type);
        var outputIndex = 0;
        for (var index = 0; index < roster.Count; index++)
        {
            var element = roster.GetElementCopyAtIndex(index);
            if (element.Character == null || element.Number <= 0) continue;
            if (outputIndex++ > 0) json.Append(',');
            json.Append('{');
            Property(json, "troopId", element.Character.StringId);
            Property(json, "name", element.Character.Name?.ToString(), true);
            json.Append(",\"count\":").Append(element.Number);
            json.Append(",\"wounded\":").Append(element.WoundedNumber);
            json.Append(",\"transferable\":").Append(Bool(logic.IsTroopTransferable(type, element.Character, (int)side)));
            json.Append('}');
        }
        json.Append(']');
    }

    private static int TotalItemCount(TaleWorlds.CampaignSystem.Roster.ItemRoster roster)
    {
        var total = 0;
        for (var index = 0; index < roster.Count; index++) total += roster.GetElementNumber(index);
        return total;
    }

    internal static string BuildMenuOptionsJson(MenuContext menuContext)
    {
        if (menuContext?.GameMenu == null) return "[]";
        var options = menuContext.GameMenu.MenuOptions.ToArray();
        var json = new StringBuilder();
        json.Append('[');
        for (var index = 0; index < options.Length; index++)
        {
            if (index > 0) json.Append(',');
            var option = options[index];
            var available = option.GetConditionsHold(Game.Current, menuContext);
            json.Append('{');
            Property(json, "id", option.IdString);
            Property(json, "text", option.Text?.ToString(), true);
            json.Append(",\"available\":").Append(Bool(available));
            json.Append(",\"enabled\":").Append(Bool(option.IsEnabled));
            json.Append(",\"isLeave\":").Append(Bool(option.IsLeave));
            json.Append('}');
        }
        json.Append(']');
        return json.ToString();
    }

    private static StringBuilder Property(StringBuilder json, string key, string value, bool prependComma = false)
    {
        if (prependComma) json.Append(',');
        json.Append('"').Append(Escape(key)).Append("\":");
        return value == null ? json.Append("null") : json.Append('"').Append(Escape(value)).Append('"');
    }

    private static string PartyType(MobileParty party) => party.IsLordParty ? "lord" : party.IsBandit ? "bandit" : party.IsCaravan ? "caravan" : party.IsVillager ? "villager" : party.IsPatrolParty ? "patrol" : party.IsGarrison ? "garrison" : "other";
    private static bool IsHostile(IFaction first, IFaction second) => first != null && second != null && FactionManager.IsAtWarAgainstFaction(first, second);
    private static double Distance(float x1, float y1, float x2, float y2) { var x = x1 - x2; var y = y1 - y2; return Math.Sqrt(x * x + y * y); }
    private static string Number(double value) => value.ToString("0.###", CultureInfo.InvariantCulture);
    private static string Bool(bool value) => value ? "true" : "false";
    private static string Escape(string value) => (value ?? string.Empty).Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\r", "\\r").Replace("\n", "\\n");
}
