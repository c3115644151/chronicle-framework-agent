using System;
using System.Globalization;
using System.Linq;
using System.Text;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.Encounters;
using TaleWorlds.CampaignSystem.GameState;
using TaleWorlds.CampaignSystem.Party;
using TaleWorlds.Core;

namespace ChronicleFramework;

internal static class ChronicleHarnessEncounterEscapeFixture
{
    internal static string SeedMainPartyForNativeEscape()
    {
        RequireVisualMapFixture();
        if (PlayerEncounter.IsActive || MobileParty.MainParty.MapEvent != null || PlayerCaptivity.IsCaptive)
            throw new InvalidOperationException("Try-get-away roster fixture requires a free MainParty before an Encounter.");

        var party = MobileParty.MainParty;
        var culture = Hero.MainHero?.Culture;
        var basicTroop = culture?.BasicTroop;
        if (basicTroop == null) throw new InvalidOperationException("Try-get-away roster fixture requires the MainHero culture's BasicTroop.");

        const int additionalHealthyTroops = 12;
        const int fixtureGrain = 20;
        var membersBefore = party.MemberRoster.TotalManCount;
        var healthyNonHeroesBefore = party.Party.NumberOfHealthyMembers - party.MemberRoster.TotalHeroes;
        var grainBefore = party.ItemRoster.GetItemNumber(DefaultItems.Grain);
        var mainGoldBefore = Hero.MainHero.Gold;
        party.MemberRoster.AddToCounts(basicTroop, additionalHealthyTroops, insertAtFront: false, woundedCount: 0, xpChange: 0, removeDepleted: true, index: -1);
        party.ItemRoster.AddToCounts(DefaultItems.Grain, fixtureGrain);
        var membersAfter = party.MemberRoster.TotalManCount;
        var healthyNonHeroesAfter = party.Party.NumberOfHealthyMembers - party.MemberRoster.TotalHeroes;
        var grainAfter = party.ItemRoster.GetItemNumber(DefaultItems.Grain);
        if (healthyNonHeroesAfter < 9 || grainAfter < fixtureGrain)
            throw new InvalidOperationException("Native Try-to-get-away fixture failed to establish its minimum Party/item roster condition.");

        var json = new StringBuilder(384);
        json.Append('{').Append("\"schemaVersion\":1,\"testOnly\":true");
        ChroniclePartyUpgradeAdapter.Property(json, "troopId", basicTroop.StringId);
        json.Append(",\"membersBefore\":").Append(membersBefore);
        json.Append(",\"additionalHealthyTroops\":").Append(additionalHealthyTroops);
        json.Append(",\"membersAfter\":").Append(membersAfter);
        json.Append(",\"healthyNonHeroesBefore\":").Append(healthyNonHeroesBefore);
        json.Append(",\"healthyNonHeroesAfter\":").Append(healthyNonHeroesAfter);
        json.Append(",\"grainBefore\":").Append(grainBefore);
        json.Append(",\"grainAdded\":").Append(fixtureGrain);
        json.Append(",\"grainAfter\":").Append(grainAfter);
        json.Append(",\"mainHeroGoldBefore\":").Append(mainGoldBefore);
        ChroniclePartyUpgradeAdapter.Property(json, "fixtureWritePath", "Native MainParty MemberRoster/ItemRoster.AddToCounts in disposable campaign memory");
        return json.Append('}').ToString();
    }

    internal static string BuildNativeEscapeDiagnostics()
    {
        RequireVisualMapFixture();
        if (!PlayerEncounter.IsActive || PlayerEncounter.Battle == null)
            throw new InvalidOperationException("Try-to-get-away diagnostics require an active Native Campaign Encounter and MapEvent.");

        var party = MobileParty.MainParty;
        var menuContext = Campaign.Current.CurrentMenuContext;
        var menuId = menuContext?.GameMenu?.StringId;
        var sacrificeCount = Campaign.Current.Models.TroopSacrificeModel.GetNumberOfTroopsSacrificedForTryingToGetAway(PlayerEncounter.Current.PlayerSide, PlayerEncounter.Battle);
        var canTry = Campaign.Current.Models.TroopSacrificeModel.CanPlayerGetAwayFromEncounter(out var explanation);
        var text = menuContext?.GameMenu?.GetText()?.ToString();
        var roster = party.MemberRoster.GetTroopRoster();
        var itemRoster = party.ItemRoster;
        var json = new StringBuilder(2048);
        json.Append('{').Append("\"schemaVersion\":1");
        ChroniclePartyUpgradeAdapter.Property(json, "menuId", menuId);
        ChroniclePartyUpgradeAdapter.Property(json, "menuText", text);
        json.Append(",\"encounterActive\":true");
        json.Append(",\"mapEventHasWinner\":").Append(ChroniclePartyUpgradeAdapter.Bool(PlayerEncounter.Battle.HasWinner));
        json.Append(",\"playerSide\":").Append((int)PlayerEncounter.Current.PlayerSide);
        json.Append(",\"isDefenderLeader\":").Append(ChroniclePartyUpgradeAdapter.Bool(PlayerEncounter.Battle.DefenderSide.LeaderParty == PartyBase.MainParty));
        json.Append(",\"partyIsRaft\":").Append(ChroniclePartyUpgradeAdapter.Bool(party.IsInRaftState));
        json.Append(",\"canTryToGetAway\":").Append(ChroniclePartyUpgradeAdapter.Bool(canTry));
        json.Append(",\"nativeTroopsSacrificedForTry\":").Append(sacrificeCount);
        ChroniclePartyUpgradeAdapter.Property(json, "nativeTryDisabledReason", explanation?.ToString());
        json.Append(",\"gold\":").Append(Hero.MainHero.Gold);
        json.Append(",\"memberCount\":").Append(party.MemberRoster.TotalManCount);
        json.Append(",\"healthyNonHeroCount\":").Append(party.Party.NumberOfHealthyMembers - party.MemberRoster.TotalHeroes);
        json.Append(",\"grainCount\":").Append(itemRoster.GetItemNumber(DefaultItems.Grain));
        json.Append(",\"campaignDay\":").Append(CampaignTime.Now.ToDays.ToString("F6", CultureInfo.InvariantCulture));
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlMode", Campaign.Current.TimeControlMode.ToString());
        json.Append(",\"memberRoster\":[");
        for (var index = 0; index < roster.Count; index++)
        {
            if (index > 0) json.Append(',');
            var entry = roster[index];
            json.Append('{');
            ChroniclePartyUpgradeAdapter.Property(json, "troopId", entry.Character?.StringId, addComma: false);
            json.Append(",\"count\":").Append(entry.Number);
            json.Append(",\"wounded\":").Append(entry.WoundedNumber);
            json.Append('}');
        }
        json.Append("],\"itemRoster\":[");
        for (var index = 0; index < itemRoster.Count; index++)
        {
            if (index > 0) json.Append(',');
            var entry = itemRoster[index];
            json.Append('{');
            ChroniclePartyUpgradeAdapter.Property(json, "itemId", entry.EquipmentElement.Item?.StringId, addComma: false);
            json.Append(",\"count\":").Append(entry.Amount);
            json.Append('}');
        }
        json.Append("]}");
        return json.ToString();
    }

    private static void RequireVisualMapFixture()
    {
        var mode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var root = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(mode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(root) || !System.IO.Directory.Exists(root))
            throw new InvalidOperationException("Encounter escape fixtures are restricted to a visual Harness run with a Harness temp directory.");
        if (Game.Current?.GameStateManager?.ActiveState is not MapState || Campaign.Current == null || Hero.MainHero == null || MobileParty.MainParty == null)
            throw new InvalidOperationException("Encounter escape fixtures require an active Campaign Map and MainHero.");
    }
}
