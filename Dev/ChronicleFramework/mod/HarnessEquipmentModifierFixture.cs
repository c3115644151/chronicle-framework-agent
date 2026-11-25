using System;
using System.Linq;
using TaleWorlds.CampaignSystem.Party;
using TaleWorlds.CampaignSystem.Roster;
using TaleWorlds.Core;

namespace ChronicleFramework;

internal static class ChronicleHarnessEquipmentModifierFixture
{
    internal static string SeedMasterworkSword()
    {
        var element = GetMasterworkSwordElement();
        var roster = MobileParty.MainParty.ItemRoster;
        var before = GetCount(roster, element);
        if (before != 0)
            throw new InvalidOperationException("The disposable equipment modifier fixture requires no pre-existing masterwork sword in MainParty inventory");
        roster.AddToCounts(element, 1);
        var after = GetCount(roster, element);
        if (after != 1)
            throw new InvalidOperationException("The masterwork sword fixture did not produce exactly one matching EquipmentElement");
        return "{\"schemaVersion\":1,\"itemId\":\"vlandia_sword_1_t2\",\"modifierId\":\"masterwork_sword\",\"countBefore\":" + before + ",\"countAfter\":" + after + "}";
    }

    internal static string ClearMasterworkSword()
    {
        var element = GetMasterworkSwordElement();
        var roster = MobileParty.MainParty.ItemRoster;
        var before = GetCount(roster, element);
        if (before != 1)
            throw new InvalidOperationException("The disposable equipment modifier fixture cannot be safely cleared because its exact remaining count is not one");
        roster.AddToCounts(element, -1);
        var after = GetCount(roster, element);
        if (after != 0)
            throw new InvalidOperationException("The masterwork sword fixture remained in MainParty inventory after cleanup");
        return "{\"schemaVersion\":1,\"itemId\":\"vlandia_sword_1_t2\",\"modifierId\":\"masterwork_sword\",\"countBefore\":" + before + ",\"countAfter\":" + after + "}";
    }

    private static EquipmentElement GetMasterworkSwordElement()
    {
        var item = Game.Current?.ObjectManager?.GetObject<ItemObject>("vlandia_sword_1_t2");
        var modifier = Game.Current?.ObjectManager?.GetObject<ItemModifier>("masterwork_sword");
        if (item?.WeaponComponent?.ItemModifierGroup == null || modifier == null || !item.WeaponComponent.ItemModifierGroup.ItemModifiers.Contains(modifier))
            throw new InvalidOperationException("The current game object set does not contain the expected compatible masterwork sword modifier fixture");
        return new EquipmentElement(item, modifier);
    }

    private static int GetCount(ItemRoster roster, EquipmentElement element)
    {
        var index = roster.FindIndexOfElement(element);
        return index < 0 ? 0 : roster.GetElementNumber(index);
    }
}
