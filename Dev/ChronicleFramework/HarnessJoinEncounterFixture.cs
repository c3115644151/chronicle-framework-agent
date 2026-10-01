using System;
using System.Globalization;
using System.Linq;
using System.Text;
using Helpers;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.Actions;
using TaleWorlds.CampaignSystem.Encounters;
using TaleWorlds.CampaignSystem.GameState;
using TaleWorlds.CampaignSystem.MapEvents;
using TaleWorlds.CampaignSystem.Party;
using TaleWorlds.CampaignSystem.Party.PartyComponents;
using TaleWorlds.CampaignSystem.Settlements;
using TaleWorlds.Core;
using TaleWorlds.Library;

namespace ChronicleFramework;

internal static class ChronicleHarnessJoinEncounterFixture
{
    private const string BanditPartyId = "chronicle_harness_join_encounter_looters";

    internal static string CreateNpcBattleForPlayerJoin()
    {
        RequireVisualMapFixture();
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

        var hostileClan = Clan.BanditFactions.FirstOrDefault(clan => clan?.MapFaction != null && clan.DefaultPartyTemplate != null &&
            clan.MapFaction != defender.MapFaction && FactionManager.IsAtWarAgainstFaction(clan.MapFaction, defender.MapFaction));
        hostileClan ??= Clan.BanditFactions.FirstOrDefault(clan => clan?.MapFaction != null && clan.DefaultPartyTemplate != null && clan.MapFaction != defender.MapFaction);
        var partyTemplate = Game.Current?.ObjectManager?.GetObject<PartyTemplateObject>("looters_template");
        var looter = Game.Current?.ObjectManager?.GetObject<CharacterObject>("looter");
        var homeSettlement = Settlement.All
            .Where(settlement => settlement != null && settlement.IsActive && (settlement.IsTown || settlement.IsVillage))
            .OrderBy(settlement => defender.Position.Distance(settlement.Position))
            .FirstOrDefault();
        if (hostileClan == null || partyTemplate == null || looter == null || homeSettlement == null)
            throw new InvalidOperationException("Native Bandit faction/template/troop or a nearby Town/Village is unavailable for the JoinEncounter fixture.");

        var playerFaction = mainParty.MapFaction;
        var banditFaction = hostileClan.MapFaction;
        if (!FactionManager.IsAtWarAgainstFaction(banditFaction, defender.MapFaction))
            DeclareWarAction.ApplyByDefault(banditFaction, defender.MapFaction);
        if (!FactionManager.IsAtWarAgainstFaction(playerFaction, banditFaction))
            DeclareWarAction.ApplyByDefault(playerFaction, banditFaction);

        var spawnPosition = FindNearbyNavigablePoint(new Vec2(defender.Position.X, defender.Position.Y));
        var attacker = BanditPartyComponent.CreateLooterParty(
            BanditPartyId,
            hostileClan,
            homeSettlement,
            isBossParty: false,
            partyTemplate,
            new CampaignVec2(spawnPosition, isOnLand: true));
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
        ChroniclePartyUpgradeAdapter.Property(json, "eventId", mapEvent.Id.ToString());
        ChroniclePartyUpgradeAdapter.Property(json, "attackerPartyId", attacker.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "defenderPartyId", defender.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "eventType", mapEvent.EventType.ToString());
        json.Append(",\"attackerStrength\":").Append(mapEvent.StrengthOfSide[(int)BattleSideEnum.Attacker].ToString("F3", CultureInfo.InvariantCulture));
        json.Append(",\"defenderStrength\":").Append(mapEvent.StrengthOfSide[(int)BattleSideEnum.Defender].ToString("F3", CultureInfo.InvariantCulture));
        json.Append(",\"attackerTroopCount\":").Append(attacker.MemberRoster.TotalManCount);
        json.Append(",\"targetAttackerStrength\":").Append(targetAttackerStrength.ToString("F3", CultureInfo.InvariantCulture));
        json.Append(",\"finalAttackerStrength\":").Append(finalAttackerStrength.ToString("F3", CultureInfo.InvariantCulture));
        json.Append(",\"attackerPartyCount\":").Append(mapEvent.AttackerSide.Parties.Count);
        json.Append(",\"defenderPartyCount\":").Append(mapEvent.DefenderSide.Parties.Count);
        json.Append(",\"mainPartyJoined\":false");
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

    internal static string BuildJoinEncounterDiagnostics()
    {
        RequireVisualMapFixture();
        if (!PlayerEncounter.IsActive)
            throw new InvalidOperationException("JoinEncounter diagnostics require the player to be in an active Native Encounter/JoinEncounter state.");
        var battle = PlayerEncounter.EncounteredBattle ?? MobileParty.MainParty.MapEvent;
        if (battle == null)
            throw new InvalidOperationException("JoinEncounter diagnostics could not resolve the current Native MapEvent.");

        var menuId = Campaign.Current.CurrentMenuContext?.GameMenu?.StringId;
        var mainParty = PartyBase.MainParty;
        var playerSide = PlayerEncounter.Current.PlayerSide;
        var mainPartyOnAttackerSide = battle.AttackerSide.Parties.Any(entry => entry.Party == mainParty);
        var mainPartyOnDefenderSide = battle.DefenderSide.Parties.Any(entry => entry.Party == mainParty);
        var json = new StringBuilder(1024);
        json.Append('{').Append("\"schemaVersion\":1");
        ChroniclePartyUpgradeAdapter.Property(json, "menuId", menuId);
        ChroniclePartyUpgradeAdapter.Property(json, "eventId", battle.Id.ToString());
        ChroniclePartyUpgradeAdapter.Property(json, "eventType", battle.EventType.ToString());
        ChroniclePartyUpgradeAdapter.Property(json, "playerSide", playerSide.ToString());
        json.Append(",\"isJoinedBattle\":").Append(ChroniclePartyUpgradeAdapter.Bool(PlayerEncounter.Current.IsJoinedBattle));
        json.Append(",\"mainPartyOnAttackerSide\":").Append(ChroniclePartyUpgradeAdapter.Bool(mainPartyOnAttackerSide));
        json.Append(",\"mainPartyOnDefenderSide\":").Append(ChroniclePartyUpgradeAdapter.Bool(mainPartyOnDefenderSide));
        json.Append(",\"battleHasWinner\":").Append(ChroniclePartyUpgradeAdapter.Bool(battle.HasWinner));
        json.Append(",\"battleSimulationExists\":").Append(ChroniclePartyUpgradeAdapter.Bool(PlayerEncounter.Current.BattleSimulation != null));
        json.Append(",\"attackerPartyIds\":[").Append(string.Join(",", battle.AttackerSide.Parties.Select(entry => "\"" + ChroniclePartyUpgradeAdapter.Escape(entry.Party.Id.ToString()) + "\""))).Append(']');
        json.Append(",\"defenderPartyIds\":[").Append(string.Join(",", battle.DefenderSide.Parties.Select(entry => "\"" + ChroniclePartyUpgradeAdapter.Escape(entry.Party.Id.ToString()) + "\""))).Append(']');
        json.Append(",\"gold\":").Append(Hero.MainHero.Gold);
        json.Append(",\"mainPartyMemberCount\":").Append(MobileParty.MainParty.MemberRoster.TotalManCount);
        json.Append(",\"campaignDay\":").Append(CampaignTime.Now.ToDays.ToString("F6", CultureInfo.InvariantCulture));
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlMode", Campaign.Current.TimeControlMode.ToString());
        return json.Append('}').ToString();
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
