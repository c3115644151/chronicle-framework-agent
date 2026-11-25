using System;
using System.Globalization;
using System.Linq;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.Encounters;
using TaleWorlds.CampaignSystem.MapEvents;
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
        ChronicleDiagnostics.Write("safe-passage-fixture-stage|validate-start");
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

        var playerFaction = mainParty.MapFaction;
        var banditFaction = hostileClan.MapFaction;
        var banditSpawnPoint = FindNearbyNavigablePoint(new Vec2(mainParty.Position.X, mainParty.Position.Y));
        var joiningRadius = Campaign.Current.Models.EncounterModel.GetEncounterJoiningRadius;
        var potentialPlayerJoiners = MobileParty.All
            .Where(party => party != null && party != mainParty && party.IsActive && party.MapFaction != null)
            .Where(party => party.AttachedTo == null && party.MapEvent == null && party.SiegeEvent == null && party.CurrentSettlement == null)
            .Where(party => !party.IsInRaftState && !party.IsCurrentlyAtSea && party.Position.Distance(mainParty.Position) <= joiningRadius)
            .Where(party => party.IsLordParty || party.IsBandit || party.IsPatrolParty || party.ShouldJoinPlayerBattles)
            .Where(party => !party.MapFaction.IsAtWarWith(playerFaction) && party.MapFaction.IsAtWarWith(banditFaction))
            .ToList();
        var playerSideStrength = mainParty.Party.GetCustomStrength(BattleSideEnum.Defender, MapEvent.PowerCalculationContext.PlainBattle) +
                                 potentialPlayerJoiners.Sum(party => party.Party.GetCustomStrength(BattleSideEnum.Defender, MapEvent.PowerCalculationContext.PlainBattle));
        var playerSideMemberCount = mainParty.MemberRoster.TotalHealthyCount + potentialPlayerJoiners.Sum(party => party.MemberRoster.TotalHealthyCount);
        ChronicleDiagnostics.Write($"safe-passage-fixture-stage|selected|clan={hostileClan.StringId}|leader={hostileClan.Leader?.StringId}|template={partyTemplate.StringId}|settlement={homeSettlement.StringId}|joiningRadius={joiningRadius:F3}|playerSidePartyCount={potentialPlayerJoiners.Count + 1}|playerSideMemberCount={playerSideMemberCount}|playerSideStrength={playerSideStrength:F3}");

        var enemyParty = BanditPartyComponent.CreateLooterParty(
            PartyId,
            hostileClan,
            homeSettlement,
            isBossParty: false,
            partyTemplate,
            new CampaignVec2(banditSpawnPoint, isOnLand: true));
        ChronicleDiagnostics.Write($"safe-passage-fixture-stage|created|party={enemyParty?.StringId}");
        enemyParty.MemberRoster.Clear();
        enemyParty.MemberRoster.AddToCounts(looter, 1, insertAtFront: false, woundedCount: 0, xpChange: 0, removeDepleted: true, index: -1);
        var singleLooterStrength = enemyParty.Party.GetCustomStrength(BattleSideEnum.Attacker, MapEvent.PowerCalculationContext.PlainBattle);
        if (singleLooterStrength <= 0f || float.IsNaN(singleLooterStrength) || float.IsInfinity(singleLooterStrength))
            throw new InvalidOperationException("Native calculation produced no finite strength for the looter fixture troop.");
        var requiredBanditStrength = playerSideStrength * 1.56f;
        var banditMemberCount = Math.Min(10000, Math.Max(10, (int)Math.Ceiling(requiredBanditStrength / singleLooterStrength)));
        var banditStrength = 0f;
        for (var attempt = 0; attempt < 8; attempt++)
        {
            enemyParty.MemberRoster.Clear();
            enemyParty.MemberRoster.AddToCounts(looter, banditMemberCount, insertAtFront: false, woundedCount: 0, xpChange: 0, removeDepleted: true, index: -1);
            banditStrength = enemyParty.Party.GetCustomStrength(BattleSideEnum.Attacker, MapEvent.PowerCalculationContext.PlainBattle);
            if (banditStrength >= requiredBanditStrength) break;
            if (banditMemberCount == 10000) break;
            banditMemberCount = Math.Min(10000, banditMemberCount * 2);
        }
        if (banditStrength < requiredBanditStrength)
            throw new InvalidOperationException("Safe Passage fixture could not reach 1.56x the local joined player-side strength without exceeding the 10,000-troop safety cap.");
        ChronicleDiagnostics.Write($"safe-passage-fixture-stage|members|count={enemyParty.MemberRoster.TotalManCount}|banditStrength={banditStrength:F3}|requiredBanditStrength={requiredBanditStrength:F3}|playerSideStrength={playerSideStrength:F3}");
        enemyParty.SetMoveEngageParty(mainParty, MobileParty.NavigationType.Default);
        var playerApproachPoint = FindApproachPointToward(
            new Vec2(mainParty.Position.X, mainParty.Position.Y),
            new Vec2(enemyParty.Position.X, enemyParty.Position.Y));
        var nearestBanditSettlement = Helpers.SettlementHelper.FindNearestSettlementToMobileParty(
            enemyParty,
            MobileParty.NavigationType.All,
            settlement => settlement.IsTown || settlement.IsVillage);
        if (nearestBanditSettlement == null)
            throw new InvalidOperationException("Native Safe Passage dialogue requires the encountered bandit party to resolve a nearest Town/Village; none is reachable from the fixture's navigation-valid spawn point.");
        var timeModeBeforeEngage = Campaign.Current.TimeControlMode;
        ChronicleDiagnostics.Write($"safe-passage-fixture-ready|party={enemyParty.StringId}|faction={enemyParty.MapFaction?.StringId}|hostile={FactionManager.IsAtWarAgainstFaction(mainParty.MapFaction, enemyParty.MapFaction)}|memberCount={enemyParty.MemberRoster.TotalManCount}|banditStrength={banditStrength:F3}|requiredBanditStrength={requiredBanditStrength:F3}|playerSidePartyCount={potentialPlayerJoiners.Count + 1}|playerSideMemberCount={playerSideMemberCount}|playerSideStrength={playerSideStrength:F3}|distance={mainParty.Position.Distance(enemyParty.Position):F3}|targetParty={enemyParty.TargetParty?.StringId}|banditSpawnPoint={banditSpawnPoint}|nearestSettlement={nearestBanditSettlement.StringId}|playerApproachPoint={playerApproachPoint}|clockBeforeEngage={timeModeBeforeEngage}");
        var joiningPartyIds = string.Join(",", potentialPlayerJoiners.Select(party => party.StringId));
        return "{\"schemaVersion\":1,\"partyId\":\"" + enemyParty.StringId + "\",\"factionId\":\"" + enemyParty.MapFaction?.StringId + "\",\"hostile\":" + (FactionManager.IsAtWarAgainstFaction(mainParty.MapFaction, enemyParty.MapFaction) ? "true" : "false") + ",\"memberCount\":" + enemyParty.MemberRoster.TotalManCount.ToString(CultureInfo.InvariantCulture) + ",\"banditStrength\":" + banditStrength.ToString("F3", CultureInfo.InvariantCulture) + ",\"requiredBanditStrength\":" + requiredBanditStrength.ToString("F3", CultureInfo.InvariantCulture) + ",\"playerSidePartyCount\":" + (potentialPlayerJoiners.Count + 1).ToString(CultureInfo.InvariantCulture) + ",\"playerSideMemberCount\":" + playerSideMemberCount.ToString(CultureInfo.InvariantCulture) + ",\"playerSideStrength\":" + playerSideStrength.ToString("F3", CultureInfo.InvariantCulture) + ",\"joiningPartyIds\":\"" + joiningPartyIds + "\",\"distance\":" + mainParty.Position.Distance(enemyParty.Position).ToString("F3", CultureInfo.InvariantCulture) + ",\"partyPosition\":{\"x\":" + enemyParty.Position.X.ToString("R", CultureInfo.InvariantCulture) + ",\"y\":" + enemyParty.Position.Y.ToString("R", CultureInfo.InvariantCulture) + "},\"banditSpawnPoint\":{\"x\":" + enemyParty.Position.X.ToString("R", CultureInfo.InvariantCulture) + ",\"y\":" + enemyParty.Position.Y.ToString("R", CultureInfo.InvariantCulture) + "},\"nearestSettlementId\":\"" + nearestBanditSettlement.StringId + "\",\"playerApproachPoint\":{\"x\":" + playerApproachPoint.X.ToString("R", CultureInfo.InvariantCulture) + ",\"y\":" + playerApproachPoint.Y.ToString("R", CultureInfo.InvariantCulture) + "},\"targetPartyId\":\"" + (enemyParty.TargetParty?.StringId ?? string.Empty) + "\",\"encounterActive\":false,\"timeControlModeBeforeEngage\":\"" + timeModeBeforeEngage + "\",\"campaignDay\":" + CampaignTime.Now.ToDays.ToString("F6", CultureInfo.InvariantCulture) + "}";
    }

    private static Vec2 FindNearbyNavigablePoint(Vec2 origin)
    {
        var distances = new[] { 0.25f, 0.5f, 0.75f, 1.0f, 1.25f, 1.5f, 2.0f };
        for (var distanceIndex = 0; distanceIndex < distances.Length; distanceIndex++)
        for (var directionIndex = 0; directionIndex < 32; directionIndex++)
        {
            var angle = directionIndex * Math.PI / 16.0;
            var distance = distances[distanceIndex];
            var candidate = new Vec2(origin.X + distance * (float)Math.Cos(angle), origin.Y + distance * (float)Math.Sin(angle));
            var campaignPoint = new CampaignVec2(candidate, isOnLand: true);
            if (campaignPoint.Face.IsValid() && Helpers.NavigationHelper.CanPlayerNavigateToPosition(campaignPoint, out _)) return candidate;
        }
        throw new InvalidOperationException("Safe Passage fixture could not find a nearby Native-navigable land point for the Bandit party.");
    }

    private static Vec2 FindApproachPointToward(Vec2 mainPosition, Vec2 banditPosition)
    {
        var delta = banditPosition - mainPosition;
        var length = delta.Length;
        if (length <= 0f) throw new InvalidOperationException("Safe Passage fixture bandit overlaps the player; no approach vector can be calculated.");
        var baseAngle = Math.Atan2(delta.Y, delta.X);
        var offsets = new[] { 0f, -15f, 15f, -30f, 30f, -45f, 45f, -60f, 60f, -75f, 75f, -90f, 90f };
        var distances = new[] { 1.0f, 1.5f, 2.0f, 3.0f };
        foreach (var distance in distances)
        foreach (var offset in offsets)
        {
            var angle = baseAngle + offset * Math.PI / 180.0;
            var candidate = new Vec2(mainPosition.X + distance * (float)Math.Cos(angle), mainPosition.Y + distance * (float)Math.Sin(angle));
            var campaignPoint = new CampaignVec2(candidate, isOnLand: true);
            if (campaignPoint.Face.IsValid() && Helpers.NavigationHelper.CanPlayerNavigateToPosition(campaignPoint, out _)) return candidate;
        }
        throw new InvalidOperationException("Safe Passage fixture could not find a nearby Native-navigable Campaign point in the direction of the actively engaging Bandit party.");
    }
}
