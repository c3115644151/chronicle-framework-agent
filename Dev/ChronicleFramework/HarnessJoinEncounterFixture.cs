using System;
using System.Globalization;
using System.Linq;
using System.Text;
using Helpers;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.Actions;
using TaleWorlds.CampaignSystem.Encounters;
using TaleWorlds.CampaignSystem.GameState;
using TaleWorlds.CampaignSystem.GameMenus;
using TaleWorlds.CampaignSystem.MapEvents;
using TaleWorlds.CampaignSystem.Party;
using TaleWorlds.CampaignSystem.Party.PartyComponents;
using TaleWorlds.CampaignSystem.Settlements;
using TaleWorlds.Core;
using TaleWorlds.Library;
using TaleWorlds.Localization;

namespace ChronicleFramework;

internal static class ChronicleHarnessJoinEncounterFixture
{
    private const string BanditPartyId = "chronicle_harness_join_encounter_looters";

    internal static string CreateNpcBattleForPlayerJoin(string playerRelationProfile = "HelpDefenders")
    {
        RequireVisualMapFixture();
        if (playerRelationProfile != "HelpDefenders" && playerRelationProfile != "HelpAttackers" && playerRelationProfile != "Neutral")
            throw new InvalidOperationException("JoinEncounter fixture relation profile must be HelpDefenders, HelpAttackers or Neutral.");
        var mainParty = MobileParty.MainParty;
        if (PlayerEncounter.IsActive || mainParty.MapEvent != null || PlayerCaptivity.IsCaptive || mainParty.IsCurrentlyAtSea)
            throw new InvalidOperationException("JoinEncounter fixture requires a free land Campaign Map without a current MapEvent.");
        if (MobileParty.All.Any(party => party != null && string.Equals(party.StringId, BanditPartyId, StringComparison.Ordinal)))
            throw new InvalidOperationException("JoinEncounter fixture bandit ID already exists in this disposable Campaign.");

        var joiningRadius = Campaign.Current.Models.EncounterModel.GetEncounterJoiningRadius;
        var defender = MobileParty.All
            .Where(party => party != null && party != mainParty && party.IsActive && party.IsLordParty && party.MapFaction != null)
            .Where(party => party.Army == null && party.AttachedTo == null && party.MapEvent == null && party.SiegeEvent == null && party.CurrentSettlement == null)
            .Where(party => !party.IsCurrentlyAtSea && !party.IsInRaftState && party.Position.Distance(mainParty.Position) <= joiningRadius * 1.5f)
            .OrderBy(party => party.Position.Distance(mainParty.Position))
            .FirstOrDefault();
        if (defender == null)
            throw new InvalidOperationException("No active independent LordParty is close enough for a controlled Native NPC battle join fixture.");

        var banditClan = Clan.BanditFactions.FirstOrDefault(clan => clan?.MapFaction != null && clan.DefaultPartyTemplate != null &&
            clan.MapFaction != defender.MapFaction && FactionManager.IsAtWarAgainstFaction(clan.MapFaction, defender.MapFaction));
        banditClan ??= Clan.BanditFactions.FirstOrDefault(clan => clan?.MapFaction != null && clan.DefaultPartyTemplate != null && clan.MapFaction != defender.MapFaction);
        var playerFaction = mainParty.MapFaction;
        var attackerClan = playerRelationProfile == "HelpDefenders"
            ? banditClan
            : Clan.All.Where(clan => clan != null && clan.MapFaction != null && clan.DefaultPartyTemplate != null && clan.Kingdom != null &&
                    clan.MapFaction != playerFaction && clan.MapFaction != defender.MapFaction && clan.Kingdom != Clan.PlayerClan.Kingdom &&
                    !clan.IsEliminated && !Campaign.Current.Models.DiplomacyModel.IsAtConstantWar(playerFaction, clan.MapFaction))
                .OrderBy(clan => clan.MapFaction.StringId, StringComparer.Ordinal)
                .FirstOrDefault();
        var partyTemplate = Game.Current?.ObjectManager?.GetObject<PartyTemplateObject>("looters_template");
        var looter = Game.Current?.ObjectManager?.GetObject<CharacterObject>("looter");
        var homeSettlement = Settlement.All
            .Where(settlement => settlement != null && settlement.IsActive && (settlement.IsTown || settlement.IsVillage))
            .OrderBy(settlement => defender.Position.Distance(settlement.Position))
            .FirstOrDefault();
        if (attackerClan == null || partyTemplate == null || looter == null || homeSettlement == null)
            throw new InvalidOperationException("A compatible Native attacker faction/template/troop or a nearby Town/Village is unavailable for the JoinEncounter fixture.");

        var attackerFaction = attackerClan.MapFaction;
        SetFactionWar(attackerFaction, defender.MapFaction, true);
        switch (playerRelationProfile)
        {
            case "HelpDefenders":
                SetFactionWar(playerFaction, attackerFaction, true);
                SetFactionWar(playerFaction, defender.MapFaction, false);
                break;
            case "HelpAttackers":
                SetFactionWar(playerFaction, attackerFaction, false);
                SetFactionWar(playerFaction, defender.MapFaction, true);
                break;
            case "Neutral":
                SetFactionWar(playerFaction, attackerFaction, false);
                SetFactionWar(playerFaction, defender.MapFaction, false);
                break;
        }

        var spawnPosition = FindNearbyNavigablePoint(new Vec2(defender.Position.X, defender.Position.Y));
        var attacker = playerRelationProfile == "HelpDefenders"
            ? BanditPartyComponent.CreateLooterParty(BanditPartyId, attackerClan, homeSettlement, isBossParty: false, partyTemplate,
                new CampaignVec2(spawnPosition, isOnLand: true))
            : CustomPartyComponent.CreateCustomPartyWithPartyTemplate(new CampaignVec2(spawnPosition, isOnLand: true), 0f, homeSettlement,
                new TextObject("{=!}Chronicle Harness Join Encounter Attacker"), attackerClan, partyTemplate, owner: null);
        if (attacker == null || !attacker.IsActive)
            throw new InvalidOperationException("Native NPC attacker party was not created.");
        attacker.MemberRoster.Clear();
        attacker.MemberRoster.AddToCounts(looter, 20, insertAtFront: false, woundedCount: 0, xpChange: 0, removeDepleted: true, index: -1);
        var initialAttackerStrength = attacker.Party.GetCustomStrength(BattleSideEnum.Attacker, MapEvent.PowerCalculationContext.PlainBattle);
        if (initialAttackerStrength <= 0f)
            throw new InvalidOperationException("Native NPC attacker party has no positive Campaign battle strength.");
        var defenderStrength = defender.Party.GetCustomStrength(BattleSideEnum.Defender, MapEvent.PowerCalculationContext.PlainBattle);
        var targetAttackerStrength = defenderStrength * 1.05f;
        var desiredAttackerCount = Math.Max(20, Math.Min(1000, (int)Math.Ceiling(20f * targetAttackerStrength / initialAttackerStrength)));
        attacker.MemberRoster.Clear();
        attacker.MemberRoster.AddToCounts(looter, desiredAttackerCount, insertAtFront: false, woundedCount: 0, xpChange: 0, removeDepleted: true, index: -1);
        var finalAttackerStrength = attacker.Party.GetCustomStrength(BattleSideEnum.Attacker, MapEvent.PowerCalculationContext.PlainBattle);

        var timeModeBefore = Campaign.Current.TimeControlMode;
        var campaignDayBefore = CampaignTime.Now.ToDays;
        StartBattleAction.Apply(attacker.Party, defender.Party);
        var mapEvent = defender.MapEvent;
        if (mapEvent == null || attacker.MapEvent != mapEvent || mapEvent.IsPlayerMapEvent || mapEvent.HasWinner)
            throw new InvalidOperationException("Native NPC-vs-NPC StartBattleAction did not produce a continuing non-player MapEvent.");
        mapEvent.RecalculateStrengthOfSides();
        if (mainParty.MapEvent != null || PlayerEncounter.IsActive)
            throw new InvalidOperationException("NPC battle fixture unexpectedly joined or started a PlayerEncounter before the player approached it.");

        var json = new StringBuilder(512);
        json.Append('{').Append("\"schemaVersion\":1,\"testOnly\":true,\"nativeNpcMapEventCreated\":true");
        ChroniclePartyUpgradeAdapter.Property(json, "playerRelationProfile", playerRelationProfile);
        ChroniclePartyUpgradeAdapter.Property(json, "eventId", mapEvent.Id.ToString());
        ChroniclePartyUpgradeAdapter.Property(json, "attackerPartyId", attacker.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "defenderPartyId", defender.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "playerFactionId", playerFaction.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "attackerFactionId", attackerFaction.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "defenderFactionId", defender.MapFaction.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "eventType", mapEvent.EventType.ToString());
        json.Append(",\"attackerStrength\":").Append(mapEvent.StrengthOfSide[(int)BattleSideEnum.Attacker].ToString("F3", CultureInfo.InvariantCulture));
        json.Append(",\"defenderStrength\":").Append(mapEvent.StrengthOfSide[(int)BattleSideEnum.Defender].ToString("F3", CultureInfo.InvariantCulture));
        json.Append(",\"attackerTroopCount\":").Append(attacker.MemberRoster.TotalManCount);
        json.Append(",\"targetAttackerStrength\":").Append(targetAttackerStrength.ToString("F3", CultureInfo.InvariantCulture));
        json.Append(",\"finalAttackerStrength\":").Append(finalAttackerStrength.ToString("F3", CultureInfo.InvariantCulture));
        json.Append(",\"attackerPartyCount\":").Append(mapEvent.AttackerSide.Parties.Count);
        json.Append(",\"defenderPartyCount\":").Append(mapEvent.DefenderSide.Parties.Count);
        json.Append(",\"mainPartyJoined\":false");
        json.Append(",\"playerAtWarWithAttacker\":").Append(ChroniclePartyUpgradeAdapter.Bool(FactionManager.IsAtWarAgainstFaction(playerFaction, attackerFaction)));
        json.Append(",\"playerAtWarWithDefender\":").Append(ChroniclePartyUpgradeAdapter.Bool(FactionManager.IsAtWarAgainstFaction(playerFaction, defender.MapFaction)));
        json.Append(",\"playerAtConstantWarWithAttacker\":").Append(ChroniclePartyUpgradeAdapter.Bool(Campaign.Current.Models.DiplomacyModel.IsAtConstantWar(playerFaction, attackerFaction)));
        json.Append(",\"playerAtConstantWarWithDefender\":").Append(ChroniclePartyUpgradeAdapter.Bool(Campaign.Current.Models.DiplomacyModel.IsAtConstantWar(playerFaction, defender.MapFaction)));
        json.Append(",\"mainPartyCanJoinAttacker\":").Append(ChroniclePartyUpgradeAdapter.Bool(mapEvent.CanPartyJoinBattle(mainParty.Party, BattleSideEnum.Attacker)));
        json.Append(",\"mainPartyCanJoinDefender\":").Append(ChroniclePartyUpgradeAdapter.Bool(mapEvent.CanPartyJoinBattle(mainParty.Party, BattleSideEnum.Defender)));
        json.Append(",\"battleHasWinner\":").Append(ChroniclePartyUpgradeAdapter.Bool(mapEvent.HasWinner));
        json.Append(",\"campaignDayBefore\":").Append(campaignDayBefore.ToString("F6", CultureInfo.InvariantCulture));
        json.Append(",\"campaignDayAfter\":").Append(CampaignTime.Now.ToDays.ToString("F6", CultureInfo.InvariantCulture));
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeBefore", timeModeBefore.ToString());
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeAfter", Campaign.Current.TimeControlMode.ToString());
        json.Append(",\"mainPartyPosition\":{\"x\":").Append(mainParty.Position.X.ToString("R", CultureInfo.InvariantCulture));
        json.Append(",\"y\":").Append(mainParty.Position.Y.ToString("R", CultureInfo.InvariantCulture)).Append('}');
        json.Append(",\"playerApproachPoint\":{\"x\":").Append(defender.Position.X.ToString("R", CultureInfo.InvariantCulture));
        json.Append(",\"y\":").Append(defender.Position.Y.ToString("R", CultureInfo.InvariantCulture)).Append('}');
        return json.Append('}').ToString();
    }

    internal static string PrepareArmyMemberForCurrentJoinEncounter()
    {
        RequireVisualMapFixture();
        if (!PlayerEncounter.IsActive || Campaign.Current.CurrentMenuContext?.GameMenu?.StringId != "join_encounter" || MobileParty.MainParty.Army != null)
            throw new InvalidOperationException("Army-member fixture requires the current Native join_encounter menu and a MainParty not already assigned to an Army.");
        var battle = PlayerEncounter.EncounteredBattle ?? MobileParty.MainParty.MapEvent;
        if (battle == null || battle.HasWinner || battle.IsPlayerMapEvent || battle.AttackerSide.Parties.Any(entry => entry.Party == PartyBase.MainParty) || battle.DefenderSide.Parties.Any(entry => entry.Party == PartyBase.MainParty))
            throw new InvalidOperationException("Army-member fixture requires the ongoing NPC-vs-NPC MapEvent before the player joins either side.");

        var eventParties = battle.AttackerSide.Parties.Concat(battle.DefenderSide.Parties).Select(entry => entry.Party.MobileParty).Where(party => party != null).ToArray();
        var armyLeaderParty = MobileParty.All
            .Where(party => party != null && party != MobileParty.MainParty && party.IsActive && party.IsVisible && party.IsLordParty && party.LeaderHero != null &&
                party.MapEvent == null && party.SiegeEvent == null && party.Army == null && party.AttachedTo == null && party.CurrentSettlement == null &&
                eventParties.All(eventParty => eventParty != party))
            .OrderByDescending(party => party.Position.Distance(MobileParty.MainParty.Position))
            .FirstOrDefault();
        var kingdom = armyLeaderParty?.MapFaction as Kingdom;
        var gatheringFocus = armyLeaderParty?.TargetSettlement ?? armyLeaderParty?.CurrentSettlement ??
            kingdom?.Settlements.FirstOrDefault(settlement => settlement.IsFortification && !settlement.IsUnderSiege) ?? kingdom?.Settlements.FirstOrDefault();
        if (kingdom == null || armyLeaderParty == null || gatheringFocus == null)
            throw new InvalidOperationException("A separate Native kingdom LordParty and gathering focus are required for the disposable Army-member fixture.");

        var eventIdBefore = battle.Id.ToString();
        var timeModeBefore = Campaign.Current.TimeControlMode;
        var campaignDayBefore = CampaignTime.Now.ToDays;
        var leaderInfluenceBefore = armyLeaderParty.LeaderHero.Clan.Influence;
        kingdom.CreateArmy(armyLeaderParty.LeaderHero, gatheringFocus, Army.ArmyTypes.Patrolling, new MBList<MobileParty> { MobileParty.MainParty });
        var army = MobileParty.MainParty.Army;
        if (army == null || army.LeaderParty != armyLeaderParty || !army.Parties.Contains(MobileParty.MainParty) || army.LeaderParty == MobileParty.MainParty)
            throw new InvalidOperationException("Native Kingdom.CreateArmy did not establish MainParty as a non-leader member of its registered Army.");
        GameMenu.SwitchToMenu("join_encounter");
        if (Campaign.Current.CurrentMenuContext?.GameMenu?.StringId != "join_encounter" || !PlayerEncounter.IsActive ||
            PlayerEncounter.EncounteredBattle?.Id.ToString() != eventIdBefore || armyLeaderParty.AttachedParties.Contains(MobileParty.MainParty))
            throw new InvalidOperationException("Native JoinEncounter was not safely refreshed after Army membership preparation.");

        var json = new StringBuilder(768);
        json.Append('{').Append("\"schemaVersion\":1,\"testOnly\":true,\"nativeArmyMembershipPrepared\":true");
        ChroniclePartyUpgradeAdapter.Property(json, "eventId", eventIdBefore);
        ChroniclePartyUpgradeAdapter.Property(json, "armyLeaderPartyId", armyLeaderParty.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "armyKingdomId", kingdom.StringId);
        json.Append(",\"armyPartyCount\":").Append(army.Parties.Count);
        json.Append(",\"armyContainsMainParty\":true");
        json.Append(",\"mainPartyAttachedToLeaderBeforeApproach\":false");
        json.Append(",\"leaderInfluenceBefore\":").Append(leaderInfluenceBefore.ToString("F3", CultureInfo.InvariantCulture));
        json.Append(",\"leaderInfluenceAfter\":").Append(armyLeaderParty.LeaderHero.Clan.Influence.ToString("F3", CultureInfo.InvariantCulture));
        json.Append(",\"campaignDayBefore\":").Append(campaignDayBefore.ToString("F6", CultureInfo.InvariantCulture));
        json.Append(",\"campaignDayAfter\":").Append(CampaignTime.Now.ToDays.ToString("F6", CultureInfo.InvariantCulture));
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeBefore", timeModeBefore.ToString());
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeAfter", Campaign.Current.TimeControlMode.ToString());
        return json.Append('}').ToString();
    }

    internal static string BuildJoinEncounterDiagnostics(string mapEventPartyId = null, string armyLeaderPartyId = null)
    {
        RequireVisualMapFixture();
        MapEvent battle = null;
        if (PlayerEncounter.IsActive)
            battle = PlayerEncounter.EncounteredBattle ?? MobileParty.MainParty.MapEvent;
        else if (!string.IsNullOrWhiteSpace(mapEventPartyId))
            battle = MobileParty.All.FirstOrDefault(party => party != null && string.Equals(party.StringId, mapEventPartyId, StringComparison.Ordinal))?.MapEvent;
        if (battle == null)
            throw new InvalidOperationException("JoinEncounter diagnostics could not resolve the active Native MapEvent.");

        var menuId = Campaign.Current.CurrentMenuContext?.GameMenu?.StringId;
        var mainParty = PartyBase.MainParty;
        var playerSide = PlayerEncounter.IsActive ? PlayerEncounter.Current.PlayerSide.ToString() : "None";
        var playerArmy = MobileParty.MainParty.Army;
        if (playerArmy == null && !string.IsNullOrWhiteSpace(armyLeaderPartyId))
            playerArmy = MobileParty.All.FirstOrDefault(party => party != null && string.Equals(party.StringId, armyLeaderPartyId, StringComparison.Ordinal))?.Army;
        var mainPartyOnAttackerSide = battle.AttackerSide.Parties.Any(entry => entry.Party == mainParty);
        var mainPartyOnDefenderSide = battle.DefenderSide.Parties.Any(entry => entry.Party == mainParty);
        var json = new StringBuilder(1024);
        json.Append('{').Append("\"schemaVersion\":1");
        ChroniclePartyUpgradeAdapter.Property(json, "menuId", menuId);
        ChroniclePartyUpgradeAdapter.Property(json, "eventId", battle.Id.ToString());
        ChroniclePartyUpgradeAdapter.Property(json, "eventType", battle.EventType.ToString());
        ChroniclePartyUpgradeAdapter.Property(json, "playerSide", playerSide);
        json.Append(",\"playerEncounterActive\":").Append(ChroniclePartyUpgradeAdapter.Bool(PlayerEncounter.IsActive));
        json.Append(",\"isJoinedBattle\":").Append(ChroniclePartyUpgradeAdapter.Bool(PlayerEncounter.IsActive && PlayerEncounter.Current.IsJoinedBattle));
        json.Append(",\"mainPartyOnAttackerSide\":").Append(ChroniclePartyUpgradeAdapter.Bool(mainPartyOnAttackerSide));
        json.Append(",\"mainPartyOnDefenderSide\":").Append(ChroniclePartyUpgradeAdapter.Bool(mainPartyOnDefenderSide));
        json.Append(",\"battleHasWinner\":").Append(ChroniclePartyUpgradeAdapter.Bool(battle.HasWinner));
        json.Append(",\"battleSimulationExists\":").Append(ChroniclePartyUpgradeAdapter.Bool(PlayerEncounter.IsActive && PlayerEncounter.Current.BattleSimulation != null));
        json.Append(",\"mainPartyCanJoinAttacker\":").Append(ChroniclePartyUpgradeAdapter.Bool(battle.CanPartyJoinBattle(mainParty, BattleSideEnum.Attacker)));
        json.Append(",\"mainPartyCanJoinDefender\":").Append(ChroniclePartyUpgradeAdapter.Bool(battle.CanPartyJoinBattle(mainParty, BattleSideEnum.Defender)));
        json.Append(",\"playerAtWarWithAttacker\":").Append(ChroniclePartyUpgradeAdapter.Bool(FactionManager.IsAtWarAgainstFaction(battle.GetLeaderParty(BattleSideEnum.Attacker).MapFaction, MobileParty.MainParty.MapFaction)));
        json.Append(",\"playerAtWarWithDefender\":").Append(ChroniclePartyUpgradeAdapter.Bool(FactionManager.IsAtWarAgainstFaction(battle.GetLeaderParty(BattleSideEnum.Defender).MapFaction, MobileParty.MainParty.MapFaction)));
        json.Append(",\"mainPartyArmyMember\":").Append(ChroniclePartyUpgradeAdapter.Bool(MobileParty.MainParty.Army != null && MobileParty.MainParty.Army.LeaderParty != MobileParty.MainParty && MobileParty.MainParty.Army.Parties.Contains(MobileParty.MainParty)));
        json.Append(",\"mainPartyArmyContainsPlayer\":").Append(ChroniclePartyUpgradeAdapter.Bool(playerArmy != null && playerArmy.Parties.Contains(MobileParty.MainParty)));
        json.Append(",\"mainPartyArmyPartyCount\":").Append(playerArmy?.Parties.Count ?? 0);
        json.Append(",\"mainPartyArmyAttachedPartyCount\":").Append(playerArmy?.LeaderParty.AttachedParties.Count ?? 0);
        json.Append(",\"playerClanInfluence\":").Append(Clan.PlayerClan.Influence.ToString("F3", CultureInfo.InvariantCulture));
        json.Append(",\"armyLeaderClanInfluence\":").Append((playerArmy?.LeaderParty?.LeaderHero?.Clan?.Influence ?? 0f).ToString("F3", CultureInfo.InvariantCulture));
        ChroniclePartyUpgradeAdapter.Property(json, "playerArmyLeaderPartyId", playerArmy?.LeaderParty?.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "mainPartyAttachedToPartyId", MobileParty.MainParty.AttachedTo?.StringId);
        json.Append(",\"attackerPartyIds\":[").Append(string.Join(",", battle.AttackerSide.Parties.Select(entry => "\"" + ChroniclePartyUpgradeAdapter.Escape(entry.Party.Id.ToString()) + "\""))).Append(']');
        json.Append(",\"defenderPartyIds\":[").Append(string.Join(",", battle.DefenderSide.Parties.Select(entry => "\"" + ChroniclePartyUpgradeAdapter.Escape(entry.Party.Id.ToString()) + "\""))).Append(']');
        json.Append(",\"gold\":").Append(Hero.MainHero.Gold);
        json.Append(",\"mainPartyMemberCount\":").Append(MobileParty.MainParty.MemberRoster.TotalManCount);
        json.Append(",\"campaignDay\":").Append(CampaignTime.Now.ToDays.ToString("F6", CultureInfo.InvariantCulture));
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlMode", Campaign.Current.TimeControlMode.ToString());
        return json.Append('}').ToString();
    }

    private static void SetFactionWar(IFaction first, IFaction second, bool shouldBeAtWar)
    {
        var currentlyAtWar = FactionManager.IsAtWarAgainstFaction(first, second);
        if (shouldBeAtWar && !currentlyAtWar)
            DeclareWarAction.ApplyByDefault(first, second);
        else if (!shouldBeAtWar && currentlyAtWar)
            MakePeaceAction.Apply(first, second);
    }

    private static Vec2 FindNearbyNavigablePoint(Vec2 origin)
    {
        var distances = new[] { 0.25f, 0.5f, 0.75f, 1f, 1.25f, 1.5f };
        for (var distanceIndex = 0; distanceIndex < distances.Length; distanceIndex++)
        for (var directionIndex = 0; directionIndex < 32; directionIndex++)
        {
            var angle = directionIndex * Math.PI / 16.0;
            var distance = distances[distanceIndex];
            var candidate = new Vec2(origin.X + distance * (float)Math.Cos(angle), origin.Y + distance * (float)Math.Sin(angle));
            var campaignPoint = new CampaignVec2(candidate, isOnLand: true);
            if (campaignPoint.Face.IsValid() && NavigationHelper.CanPlayerNavigateToPosition(campaignPoint, out _)) return candidate;
        }
        throw new InvalidOperationException("Could not find a Native-navigable attacker spawn near the chosen LordParty.");
    }

    private static void RequireVisualMapFixture()
    {
        var mode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var root = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(mode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(root) || !System.IO.Directory.Exists(root))
            throw new InvalidOperationException("JoinEncounter fixtures/diagnostics are restricted to a visual Harness run with a Harness temp directory.");
        if (Game.Current?.GameStateManager?.ActiveState is not MapState || Campaign.Current == null || Hero.MainHero == null || MobileParty.MainParty == null)
            throw new InvalidOperationException("JoinEncounter fixtures/diagnostics require an active Campaign Map and MainHero.");
    }
}
