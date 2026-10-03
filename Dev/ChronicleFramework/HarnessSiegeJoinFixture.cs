using System;
using System.Globalization;
using System.Linq;
using System.Text;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.Actions;
using TaleWorlds.CampaignSystem.Encounters;
using TaleWorlds.CampaignSystem.GameState;
using TaleWorlds.CampaignSystem.Party;
using TaleWorlds.CampaignSystem.Party.PartyComponents;
using TaleWorlds.CampaignSystem.Settlements;
using TaleWorlds.CampaignSystem.Siege;
using TaleWorlds.Core;
using TaleWorlds.Library;

namespace ChronicleFramework;

internal static class ChronicleHarnessSiegeJoinFixture
{
    internal static string PrepareNativeSiegeJoin(string settlementId)
    {
        RequireVisualMapFixture();
        if (PlayerEncounter.IsActive || MobileParty.MainParty.MapEvent != null || MobileParty.MainParty.Army != null ||
            MobileParty.MainParty.IsCurrentlyAtSea || PlayerCaptivity.IsCaptive)
            throw new InvalidOperationException("Siege join fixture requires a free land Campaign Map MainParty without Army, Event or Captivity.");
        if (string.IsNullOrWhiteSpace(settlementId))
            throw new InvalidOperationException("settlementId must come from the current Native mapSettlementTargets observation.");

        var settlement = Settlement.All.FirstOrDefault(item => item != null && string.Equals(item.StringId, settlementId, StringComparison.Ordinal));
        var defenderKingdom = settlement?.MapFaction as Kingdom;
        if (settlement == null || !settlement.IsActive || !settlement.IsVisible || (!settlement.IsTown && !settlement.IsCastle) ||
            settlement.SiegeEvent != null || settlement.Party?.MapEvent != null || defenderKingdom == null)
            throw new InvalidOperationException("settlementId must be a currently visible, unsieged Town/Castle owned by a Kingdom without an active MapEvent.");

        var besiegerSelection = Kingdom.All
            .Where(kingdom => kingdom != null && kingdom != defenderKingdom && kingdom != Clan.PlayerClan.Kingdom && !kingdom.IsEliminated)
            .SelectMany(kingdom => MobileParty.All
                .Where(party => party != null && party != MobileParty.MainParty && party.IsActive && party.IsLordParty && party.LeaderHero != null &&
                    party.MapFaction == kingdom && party.MapEvent == null && party.SiegeEvent == null && party.Army == null && party.AttachedTo == null &&
                    party.CurrentSettlement == null && !party.IsCurrentlyAtSea)
                .Select(party => new { Kingdom = kingdom, LeaderParty = party, Distance = party.Position.Distance(settlement.Position) }))
            .OrderBy(item => item.Distance)
            .FirstOrDefault();
        var besiegerKingdom = besiegerSelection?.Kingdom;
        var besiegerLeader = besiegerSelection?.LeaderParty;
        if (besiegerKingdom == null || besiegerLeader == null)
            throw new InvalidOperationException("No free Native Kingdom LordParty was available to establish the disposable siege fixture.");

        var playerKingdomBefore = Clan.PlayerClan.Kingdom;
        var playerFactionIdBefore = MobileParty.MainParty.MapFaction?.StringId;
        var playerInfluenceBefore = Clan.PlayerClan.Influence;
        var goldBefore = Hero.MainHero.Gold;
        var campaignDayBefore = CampaignTime.Now.ToDays;
        var timeModeBefore = Campaign.Current.TimeControlMode;
        if (Clan.PlayerClan.Kingdom != besiegerKingdom)
            ChangeKingdomAction.ApplyByJoinToKingdom(Clan.PlayerClan, besiegerKingdom, CampaignTime.Zero, showNotification: false);
        if (MobileParty.MainParty.MapFaction != besiegerKingdom)
            throw new InvalidOperationException("Native ChangeKingdomAction did not align MainParty to the Native besieger Kingdom.");
        SetFactionWar(besiegerKingdom, defenderKingdom, true);

        var auxiliaryParty = MobileParty.All
            .Where(party => party != null && party != MobileParty.MainParty && party != besiegerLeader && party.IsActive && party.IsLordParty && party.LeaderHero != null &&
                party.MapFaction == besiegerKingdom && party.MapEvent == null && party.SiegeEvent == null && party.Army == null && party.AttachedTo == null &&
                party.CurrentSettlement == null && !party.IsCurrentlyAtSea)
            .OrderBy(party => party.Position.Distance(besiegerLeader.Position))
            .FirstOrDefault();
        var armyFocus = besiegerKingdom.Settlements
            .Where(item => item != null && item.IsActive && item.IsFortification && !item.IsUnderSiege)
            .OrderByDescending(item => besiegerLeader.Position.Distance(item.Position))
            .FirstOrDefault() ?? besiegerKingdom.Settlements.FirstOrDefault(item => item != null && item.IsActive);
        if (armyFocus == null)
            throw new InvalidOperationException("Native besieger Kingdom has no available Army gathering focus.");

        var partiesToCall = auxiliaryParty == null ? null : new MBList<MobileParty> { auxiliaryParty };
        besiegerKingdom.CreateArmy(besiegerLeader.LeaderHero, armyFocus, Army.ArmyTypes.Besieger, partiesToCall);
        var army = besiegerLeader.Army;
        if (army == null || army.LeaderParty != besiegerLeader || !besiegerKingdom.Armies.Contains(army))
            throw new InvalidOperationException("Native Kingdom.CreateArmy did not create a registered Army for the siege fixture.");
        if (auxiliaryParty != null && auxiliaryParty.Army == army && !ReferenceEquals(auxiliaryParty.AttachedTo, besiegerLeader))
            army.AddPartyToMergedParties(auxiliaryParty);
        SetPartyAiAction.GetActionForBesiegingSettlement(besiegerLeader, settlement, MobileParty.NavigationType.Default, isFromPort: false);

        var siege = Campaign.Current.SiegeEventManager.StartSiegeEvent(settlement, besiegerLeader);
        besiegerLeader.BesiegerCamp = siege.BesiegerCamp;
        if (siege == null || settlement.SiegeEvent != siege || !siege.CanPartyJoinSide(PartyBase.MainParty, BattleSideEnum.Attacker) ||
            settlement.Party.MapEvent != null || besiegerLeader.MapEvent != null || settlement.SiegeEvent.IsBlockadeActive)
            throw new InvalidOperationException("Native SiegeEvent fixture did not establish a joinable, non-battle land SiegeEvent.");

        var json = new StringBuilder(1024);
        json.Append('{').Append("\"schemaVersion\":1,\"testOnly\":true,\"nativeSiegeJoinFixtureCreated\":true");
        ChroniclePartyUpgradeAdapter.Property(json, "settlementId", settlement.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "settlementName", settlement.Name?.ToString());
        ChroniclePartyUpgradeAdapter.Property(json, "defenderKingdomId", defenderKingdom.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "besiegerKingdomId", besiegerKingdom.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "besiegerLeaderPartyId", besiegerLeader.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "besiegerArmyLeaderPartyId", army.LeaderParty.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "besiegerBehavior", besiegerLeader.DefaultBehavior.ToString());
        ChroniclePartyUpgradeAdapter.Property(json, "siegeTargetSettlementId", army.AiBehaviorObject is Settlement armyTarget ? armyTarget.StringId : null);
        json.Append(",\"armyPartyCount\":").Append(army.Parties.Count);
        json.Append(",\"siegeEventActive\":").Append(ChroniclePartyUpgradeAdapter.Bool(settlement.SiegeEvent != null));
        json.Append(",\"besiegerLeaderInSiege\":").Append(ChroniclePartyUpgradeAdapter.Bool(siege.BesiegerCamp.HasInvolvedPartyForEventType(besiegerLeader.Party)));
        json.Append(",\"settlementMapEventActive\":").Append(ChroniclePartyUpgradeAdapter.Bool(settlement.Party.MapEvent != null));
        json.Append(",\"besiegerMapEventActive\":").Append(ChroniclePartyUpgradeAdapter.Bool(besiegerLeader.MapEvent != null));
        json.Append(",\"attackerJoinSideEnabled\":").Append(ChroniclePartyUpgradeAdapter.Bool(siege.CanPartyJoinSide(PartyBase.MainParty, BattleSideEnum.Attacker)));
        json.Append(",\"playerAtWarWithDefender\":").Append(ChroniclePartyUpgradeAdapter.Bool(FactionManager.IsAtWarAgainstFaction(MobileParty.MainParty.MapFaction, defenderKingdom)));
        json.Append(",\"playerAtWarWithBesieger\":").Append(ChroniclePartyUpgradeAdapter.Bool(FactionManager.IsAtWarAgainstFaction(MobileParty.MainParty.MapFaction, besiegerKingdom)));
        ChroniclePartyUpgradeAdapter.Property(json, "playerKingdomBefore", playerKingdomBefore?.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "playerFactionIdBefore", playerFactionIdBefore);
        ChroniclePartyUpgradeAdapter.Property(json, "playerKingdomAfter", Clan.PlayerClan.Kingdom?.StringId);
        json.Append(",\"playerInfluenceBefore\":").Append(playerInfluenceBefore.ToString("F3", CultureInfo.InvariantCulture));
        json.Append(",\"playerInfluenceAfter\":").Append(Clan.PlayerClan.Influence.ToString("F3", CultureInfo.InvariantCulture));
        json.Append(",\"goldBefore\":").Append(goldBefore);
        json.Append(",\"goldAfter\":").Append(Hero.MainHero.Gold);
        json.Append(",\"campaignDayBefore\":").Append(campaignDayBefore.ToString("F6", CultureInfo.InvariantCulture));
        json.Append(",\"campaignDayAfter\":").Append(CampaignTime.Now.ToDays.ToString("F6", CultureInfo.InvariantCulture));
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeBefore", timeModeBefore.ToString());
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeAfter", Campaign.Current.TimeControlMode.ToString());
        return json.Append('}').ToString();
    }

    internal static string BuildSiegeJoinDiagnostics(string settlementId, string besiegerLeaderPartyId)
    {
        RequireVisualMapFixture();
        var settlement = Settlement.All.FirstOrDefault(item => item != null && string.Equals(item.StringId, settlementId, StringComparison.Ordinal));
        var besiegerLeader = MobileParty.All.FirstOrDefault(party => party != null && string.Equals(party.StringId, besiegerLeaderPartyId, StringComparison.Ordinal));
        var siege = settlement?.SiegeEvent;
        if (settlement == null || besiegerLeader == null || siege == null)
            throw new InvalidOperationException("Siege diagnostics could not resolve the current SiegeEvent, Settlement and besieger Army Leader.");

        var army = besiegerLeader.Army;
        var json = new StringBuilder(1024);
        json.Append('{').Append("\"schemaVersion\":1");
        ChroniclePartyUpgradeAdapter.Property(json, "menuId", Campaign.Current.CurrentMenuContext?.GameMenu?.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "settlementId", settlement.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "settlementName", settlement.Name?.ToString());
        ChroniclePartyUpgradeAdapter.Property(json, "besiegerLeaderPartyId", besiegerLeader.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "defenderFactionId", settlement.MapFaction?.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "besiegerFactionId", siege.BesiegerCamp?.MapFaction?.StringId);
        json.Append(",\"siegeEventActive\":").Append(ChroniclePartyUpgradeAdapter.Bool(settlement.SiegeEvent == siege));
        json.Append(",\"settlementUnderSiege\":").Append(ChroniclePartyUpgradeAdapter.Bool(settlement.IsUnderSiege));
        json.Append(",\"settlementMapEventActive\":").Append(ChroniclePartyUpgradeAdapter.Bool(settlement.Party.MapEvent != null));
        json.Append(",\"besiegerMapEventActive\":").Append(ChroniclePartyUpgradeAdapter.Bool(besiegerLeader.MapEvent != null));
        json.Append(",\"mainPartyInBesiegerCamp\":").Append(ChroniclePartyUpgradeAdapter.Bool(MobileParty.MainParty.BesiegerCamp == siege.BesiegerCamp));
        json.Append(",\"canJoinAttacker\":").Append(ChroniclePartyUpgradeAdapter.Bool(siege.CanPartyJoinSide(PartyBase.MainParty, BattleSideEnum.Attacker)));
        json.Append(",\"canJoinDefender\":").Append(ChroniclePartyUpgradeAdapter.Bool(siege.CanPartyJoinSide(PartyBase.MainParty, BattleSideEnum.Defender)));
        json.Append(",\"playerSiegeEventActive\":").Append(ChroniclePartyUpgradeAdapter.Bool(PlayerSiege.PlayerSiegeEvent == siege));
        ChroniclePartyUpgradeAdapter.Property(json, "playerSiegeSide", PlayerSiege.PlayerSide.ToString());
        json.Append(",\"playerEncounterActive\":").Append(ChroniclePartyUpgradeAdapter.Bool(PlayerEncounter.IsActive));
        json.Append(",\"mainPartyArmyMember\":").Append(ChroniclePartyUpgradeAdapter.Bool(army != null && army.Parties.Contains(MobileParty.MainParty)));
        json.Append(",\"armyPartyCount\":").Append(army?.Parties.Count ?? 0);
        json.Append(",\"besiegerCampPartyCount\":").Append(siege.BesiegerCamp.GetInvolvedPartiesForEventType().Count());
        json.Append(",\"gold\":").Append(Hero.MainHero.Gold);
        json.Append(",\"playerInfluence\":").Append(Clan.PlayerClan.Influence.ToString("F3", CultureInfo.InvariantCulture));
        json.Append(",\"campaignDay\":").Append(CampaignTime.Now.ToDays.ToString("F6", CultureInfo.InvariantCulture));
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlMode", Campaign.Current.TimeControlMode.ToString());
        return json.Append('}').ToString();
    }

    private static void SetFactionWar(IFaction first, IFaction second, bool shouldBeAtWar)
    {
        if (FactionManager.IsAtWarAgainstFaction(first, second) == shouldBeAtWar) return;
        if (shouldBeAtWar) DeclareWarAction.ApplyByDefault(first, second);
        else MakePeaceAction.Apply(first, second);
    }

    private static void RequireVisualMapFixture()
    {
        var mode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var root = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(mode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(root) || !System.IO.Directory.Exists(root))
            throw new InvalidOperationException("Siege join fixture/diagnostics are restricted to a visual Harness run with a Harness temp directory.");
        if (Game.Current?.GameStateManager?.ActiveState is not MapState || Campaign.Current == null || Hero.MainHero == null || MobileParty.MainParty == null)
            throw new InvalidOperationException("Siege join fixture/diagnostics require an active Campaign Map and MainHero.");
    }
}
