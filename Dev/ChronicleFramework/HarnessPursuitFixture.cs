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

internal static class ChronicleHarnessPursuitFixture
{
    internal const string PartyId = "chronicle_harness_pursuit_looters";

    internal static string CreateWeakHostileLooterParty()
    {
        var mainParty = MobileParty.MainParty;
        if (mainParty == null || mainParty.MapEvent != null || PlayerEncounter.Current != null || mainParty.IsCurrentlyAtSea)
            throw new InvalidOperationException("Pursuit visibility fixture requires a land Campaign Map with no active encounter.");
        if (MobileParty.All.Any(party => party != null && string.Equals(party.StringId, PartyId, StringComparison.Ordinal)))
            throw new InvalidOperationException("Pursuit visibility fixture party ID already exists in this disposable Campaign.");

        var hostileClan = Clan.BanditFactions.FirstOrDefault(clan =>
            clan?.MapFaction != null &&
            clan.DefaultPartyTemplate != null &&
            FactionManager.IsAtWarAgainstFaction(mainParty.MapFaction, clan));
        var partyTemplate = Game.Current?.ObjectManager?.GetObject<PartyTemplateObject>("looters_template");
        var looter = Game.Current?.ObjectManager?.GetObject<CharacterObject>("looter");
        var mainHero = Hero.MainHero;
        var playerRecruit = mainHero?.Culture?.BasicTroop;
        var homeSettlement = Settlement.All
            .Where(settlement => settlement != null && settlement.IsActive && (settlement.IsTown || settlement.IsVillage))
            .OrderBy(settlement => mainParty.Position.Distance(settlement.Position))
            .FirstOrDefault();
        if (hostileClan == null || partyTemplate == null || looter == null || playerRecruit == null || homeSettlement == null)
            throw new InvalidOperationException("Native hostile bandit clan, looter/recruit troop, template, or nearby home settlement is unavailable.");

        var initialPlayerMembers = mainParty.MemberRoster.TotalManCount;
        var spawnPoint = FindNearbyNavigablePoint(new Vec2(mainParty.Position.X, mainParty.Position.Y));
        var enemyParty = BanditPartyComponent.CreateLooterParty(
            PartyId,
            hostileClan,
            homeSettlement,
            isBossParty: false,
            partyTemplate,
            new CampaignVec2(spawnPoint, isOnLand: true));
        if (enemyParty == null || !enemyParty.IsActive)
            throw new InvalidOperationException("Native looter party creation did not produce an active map party.");

        enemyParty.MemberRoster.Clear();
        enemyParty.MemberRoster.AddToCounts(looter, 5, insertAtFront: false, woundedCount: 0, xpChange: 0, removeDepleted: true, index: -1);
        mainParty.MemberRoster.AddToCounts(playerRecruit, 100, insertAtFront: false, woundedCount: 0, xpChange: 0, removeDepleted: true, index: -1);

        var distance = mainParty.Position.Distance(enemyParty.Position);
        var hostile = FactionManager.IsAtWarAgainstFaction(mainParty.MapFaction, enemyParty.MapFaction);
        if (!hostile || distance < 4f || distance > 10f)
            throw new InvalidOperationException("Pursuit fixture failed its hostile/fair-distance preconditions.");

        ChronicleDiagnostics.Write($"pursuit-visibility-fixture|created|party={enemyParty.StringId}|faction={enemyParty.MapFaction?.StringId}|hostile={hostile}|targetMembers={enemyParty.MemberRoster.TotalManCount}|playerMembersBefore={initialPlayerMembers}|playerMembersAfter={mainParty.MemberRoster.TotalManCount}|distance={distance:F3}|spawn={spawnPoint}|moveMode={enemyParty.DefaultBehavior}|campaignDay={CampaignTime.Now.ToDays.ToString("F6", CultureInfo.InvariantCulture)}");
        return "{\"schemaVersion\":1,\"partyId\":\"" + enemyParty.StringId + "\",\"factionId\":\"" + enemyParty.MapFaction?.StringId + "\",\"hostile\":" + (hostile ? "true" : "false") + ",\"targetMembers\":" + enemyParty.MemberRoster.TotalManCount.ToString(CultureInfo.InvariantCulture) + ",\"playerMembersBefore\":" + initialPlayerMembers.ToString(CultureInfo.InvariantCulture) + ",\"playerMembersAfter\":" + mainParty.MemberRoster.TotalManCount.ToString(CultureInfo.InvariantCulture) + ",\"distance\":" + distance.ToString("F3", CultureInfo.InvariantCulture) + ",\"spawnPoint\":{\"x\":" + spawnPoint.X.ToString("R", CultureInfo.InvariantCulture) + ",\"y\":" + spawnPoint.Y.ToString("R", CultureInfo.InvariantCulture) + "},\"moveMode\":\"" + enemyParty.DefaultBehavior + "\",\"campaignDay\":" + CampaignTime.Now.ToDays.ToString("F6", CultureInfo.InvariantCulture) + "}";
    }

    private static Vec2 FindNearbyNavigablePoint(Vec2 origin)
    {
        var distances = new[] { 6f, 7f, 8f, 5f, 9f };
        for (var distanceIndex = 0; distanceIndex < distances.Length; distanceIndex++)
        for (var directionIndex = 0; directionIndex < 32; directionIndex++)
        {
            var angle = directionIndex * Math.PI / 16.0;
            var distance = distances[distanceIndex];
            var candidate = new Vec2(origin.X + distance * (float)Math.Cos(angle), origin.Y + distance * (float)Math.Sin(angle));
            var campaignPoint = new CampaignVec2(candidate, isOnLand: true);
            if (campaignPoint.Face.IsValid() && Helpers.NavigationHelper.CanPlayerNavigateToPosition(campaignPoint, out _))
                return candidate;
        }
        throw new InvalidOperationException("Pursuit visibility fixture could not find a Native-navigable land spawn point at spotting range.");
    }
}
