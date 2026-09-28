using System;
using System.Globalization;
using System.Linq;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.Encounters;
using TaleWorlds.CampaignSystem.Party;
using TaleWorlds.CampaignSystem.Party.PartyComponents;
using TaleWorlds.CampaignSystem.Settlements;
using TaleWorlds.Core;
using TaleWorlds.Library;

namespace ChronicleFramework;

internal static class ChronicleHarnessSafePassageFixture
{
    internal const string PartyId = "chronicle_harness_safe_passage_looters";

    internal static string CreateAttackingBanditParty()
    {
        var mainParty = MobileParty.MainParty;
        if (mainParty == null || mainParty.MapEvent != null || PlayerEncounter.Current != null)
            throw new InvalidOperationException("Safe Passage fixture requires the player Campaign Map without an active encounter.");
        if (mainParty.IsCurrentlyAtSea)
            throw new InvalidOperationException("Safe Passage fixture currently verifies the land-bandit branch only.");
        if (MobileParty.All.Any(party => party != null && string.Equals(party.StringId, PartyId, StringComparison.Ordinal)))
            throw new InvalidOperationException("Safe Passage fixture party ID already exists in this disposable Campaign.");

        var hostileClan = Clan.BanditFactions.FirstOrDefault(clan =>
            clan?.MapFaction != null &&
            clan.DefaultPartyTemplate != null &&
            FactionManager.IsAtWarAgainstFaction(mainParty.MapFaction, clan));
        var partyTemplate = Game.Current?.ObjectManager?.GetObject<PartyTemplateObject>("looters_template");
        var looter = Game.Current?.ObjectManager?.GetObject<CharacterObject>("looter");
        var homeSettlement = Settlement.All
            .Where(settlement => settlement != null && settlement.IsActive && (settlement.IsTown || settlement.IsVillage))
            .OrderBy(settlement => mainParty.Position.Distance(settlement.Position))
            .FirstOrDefault();
        if (hostileClan == null || partyTemplate == null || looter == null || homeSettlement == null)
            throw new InvalidOperationException("Native hostile bandit clan, looter template, troop, or nearby home settlement is unavailable.");

        var enemyParty = BanditPartyComponent.CreateLooterParty(
            PartyId,
            hostileClan,
            homeSettlement,
            isBossParty: false,
            partyTemplate,
            mainParty.Position + new Vec2(0.5f, 0f));
        enemyParty.MemberRoster.Clear();
        enemyParty.MemberRoster.AddToCounts(looter, 1, insertAtFront: false, woundedCount: 0, xpChange: 0, removeDepleted: true, index: -1);
        var timeModeBeforeEncounter = Campaign.Current.TimeControlMode;
        EncounterManager.StartPartyEncounter(enemyParty.Party, mainParty.Party);
        if (PlayerEncounter.Current == null || PlayerEncounter.EncounteredMobileParty != enemyParty || PlayerEncounter.Current.PlayerSide != BattleSideEnum.Defender)
            throw new InvalidOperationException("Native EncounterManager did not create the expected Bandit-attacker/MainParty-defender encounter.");

        ChronicleDiagnostics.Write($"safe-passage-fixture-ready|party={enemyParty.StringId}|faction={enemyParty.MapFaction?.StringId}|hostile={FactionManager.IsAtWarAgainstFaction(mainParty.MapFaction, enemyParty.MapFaction)}|memberCount={enemyParty.MemberRoster.TotalManCount}|distance={mainParty.Position.Distance(enemyParty.Position):F3}|playerSide={PlayerEncounter.Current.PlayerSide}|clockBefore={timeModeBeforeEncounter}|clockAfter={Campaign.Current.TimeControlMode}");
        return "{\"schemaVersion\":1,\"partyId\":\"" + enemyParty.StringId + "\",\"factionId\":\"" + enemyParty.MapFaction?.StringId + "\",\"hostile\":" + (FactionManager.IsAtWarAgainstFaction(mainParty.MapFaction, enemyParty.MapFaction) ? "true" : "false") + ",\"memberCount\":" + enemyParty.MemberRoster.TotalManCount.ToString(CultureInfo.InvariantCulture) + ",\"distance\":" + mainParty.Position.Distance(enemyParty.Position).ToString("F3", CultureInfo.InvariantCulture) + ",\"playerSide\":\"" + PlayerEncounter.Current.PlayerSide + "\",\"encounterActive\":" + (PlayerEncounter.Current != null ? "true" : "false") + ",\"timeControlModeBefore\":\"" + timeModeBeforeEncounter + "\",\"timeControlModeAfter\":\"" + Campaign.Current.TimeControlMode + "\",\"campaignDay\":" + CampaignTime.Now.ToDays.ToString("F6", CultureInfo.InvariantCulture) + "}";
    }
}
