using System;
using System.Collections;
using System.Linq;
using System.Reflection;
using System.Text;
using SandBox.CampaignBehaviors;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.Actions;
using TaleWorlds.CampaignSystem.CharacterDevelopment;
using TaleWorlds.CampaignSystem.GameMenus;
using TaleWorlds.CampaignSystem.GameState;
using TaleWorlds.CampaignSystem.Party;
using TaleWorlds.CampaignSystem.Roster;
using TaleWorlds.CampaignSystem.Settlements;
using TaleWorlds.Core;
using TaleWorlds.Localization;

namespace ChronicleFramework;

internal static class HarnessAlleyLeaderFixture
{
    internal static string PrepareTownAlleyLeaderInquiry(string settlementId)
    {
        var mode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var root = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(mode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(root) || !System.IO.Directory.Exists(root))
            throw new InvalidOperationException("Alley leader fixtures are restricted to a visual Harness run with its temporary evidence directory.");
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("Alley leader fixture setup requires the Campaign Map, including a current Town menu.");
        var settlement = Settlement.Find(settlementId);
        if (settlement == null || !settlement.IsTown || !settlement.IsVisible || settlement.Party?.MapEvent != null || settlement.IsUnderSiege)
            throw new InvalidOperationException("Alley leader fixture requires a visible, non-besieged Town without an active battle.");
        var alley = settlement.Alleys?.FirstOrDefault(item => item != null && item.Owner == null);
        if (alley == null)
            throw new InvalidOperationException("No currently unowned Native Alley is available in this disposable Town.");

        var playerClan = Clan.PlayerClan;
        var existingBehavior = Campaign.Current.GetCampaignBehavior<AlleyCampaignBehavior>();
        if (existingBehavior == null) throw new InvalidOperationException("Native AlleyCampaignBehavior is not registered in the active Campaign.");
        var dataType = typeof(AlleyCampaignBehavior).GetNestedType("PlayerAlleyData", BindingFlags.Public | BindingFlags.NonPublic);
        var listField = typeof(AlleyCampaignBehavior).GetField("_playerOwnedCommonAreaData", BindingFlags.Instance | BindingFlags.NonPublic);
        var playerAlleyData = listField?.GetValue(existingBehavior) as IList;
        if (dataType == null || playerAlleyData == null) throw new MissingMemberException(typeof(AlleyCampaignBehavior).FullName, "PlayerAlleyData/_playerOwnedCommonAreaData");
        if (playerAlleyData.Cast<object>().Any(item => ReferenceEquals(ReadMember(item, "Alley"), alley)))
            throw new InvalidOperationException("Chosen Native Alley is already present in the PlayerAlleyData list.");

        var initialAssignedHero = CreateEligibleAlleyClanHero(settlement, playerClan);
        var availableExistingHero = playerClan.Heroes.FirstOrDefault(hero => hero != null && hero != Hero.MainHero && hero != initialAssignedHero && hero.IsAlive &&
            !hero.IsTraveling && !hero.IsPrisoner && !hero.IsPartyLeader && hero.GetSkillValue(DefaultSkills.Roguery) >= 30 && hero.GetTraitLevel(DefaultTraits.Mercy) <= 0);
        Hero candidate = availableExistingHero;
        var candidateCreatedForFixture = false;
        if (candidate == null)
        {
            candidate = CreateEligibleAlleyClanHero(settlement, playerClan);
            candidateCreatedForFixture = true;
        }
        if (candidate.Clan != playerClan)
            throw new InvalidOperationException("Native Clan-hero fixture did not join the candidate to the player's Clan (clan=" + candidate.Clan?.StringId + ", party=" + candidate.PartyBelongedTo?.StringId + ").");

        var availability = Campaign.Current.Models.AlleyModel.GetClanMembersAndAvailabilityDetailsForLeadingAnAlley(alley)
            .FirstOrDefault(item => item.Item1 == candidate);
        var availabilityName = availability.Item1 == candidate ? availability.Item2.ToString() : "NotReturned";
        if (availability.Item1 != candidate ||
            !string.Equals(availabilityName, "Available", StringComparison.Ordinal) &&
            !string.Equals(availabilityName, "AvailableWithDelay", StringComparison.Ordinal))
            throw new InvalidOperationException("Harness Clan Hero is not enabled by the Native AlleyModel: " + availabilityName);

        var roster = TroopRoster.CreateDummyTroopRoster();
        roster.AddToCounts(initialAssignedHero.CharacterObject, 1);
        var constructor = dataType.GetConstructor(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic, null, new[] { typeof(Alley), typeof(TroopRoster) }, null);
        if (constructor == null) throw new MissingMethodException(dataType.FullName, ".ctor(Alley, TroopRoster)");
        var nativePlayerAlleyData = constructor.Invoke(new object[] { alley, roster });
        alley.SetOwner(Hero.MainHero);
        playerAlleyData.Add(nativePlayerAlleyData);

        // Native ChangeTheLeaderOfAlleyInternal moves the old leader's existing
        // LocationCharacter to the tavern when that Hero is already in this
        // settlement. A bare PlayerAlleyData record is not a complete Native
        // fixture: initialize the alley roster through the behavior's own
        // lifecycle helper so the later Native menu callback has that object.
        var addCharacters = typeof(AlleyCampaignBehavior).GetMethod("AddPlayerAlleyCharacters", BindingFlags.Instance | BindingFlags.NonPublic);
        if (addCharacters == null) throw new MissingMethodException(typeof(AlleyCampaignBehavior).FullName, "AddPlayerAlleyCharacters(Alley)");
        addCharacters.Invoke(existingBehavior, new object[] { alley });
        if (initialAssignedHero.CurrentSettlement == settlement && settlement.LocationComplex.GetLocationCharacterOfHero(initialAssignedHero) == null)
            throw new InvalidOperationException("Native alley roster setup did not create a LocationCharacter for the current-settlement leader required by the Native confirmation callback.");

        var finalAvailability = Campaign.Current.Models.AlleyModel.GetClanMembersAndAvailabilityDetailsForLeadingAnAlley(alley)
            .FirstOrDefault(item => item.Item1 == candidate);
        var finalAvailabilityName = finalAvailability.Item1 == candidate ? finalAvailability.Item2.ToString() : "NotReturned";
        if (finalAvailability.Item1 != candidate ||
            !string.Equals(finalAvailabilityName, "Available", StringComparison.Ordinal) &&
            !string.Equals(finalAvailabilityName, "AvailableWithDelay", StringComparison.Ordinal))
            throw new InvalidOperationException("Native AlleyModel changed this candidate to '" + finalAvailabilityName + "' after the PlayerAlleyData fixture (active=" + candidate.IsActive + ",partyLeader=" + candidate.IsPartyLeader + ",isTraveling=" + candidate.IsTraveling + ",partyId=" + candidate.PartyBelongedTo?.StringId + ",mainPartyLeader=" + MobileParty.MainParty.LeaderHero?.StringId + ").");

        GameMenu.SwitchToMenu("manage_alley");
        var menu = Campaign.Current.CurrentMenuContext?.GameMenu;
        var option = menu?.MenuOptions.FirstOrDefault(item => string.Equals(item.IdString, "change_leader_of_alley", StringComparison.Ordinal));
        if (menu?.StringId != "manage_alley" || option == null || !option.IsEnabled || !option.GetConditionsHold(Game.Current, Campaign.Current.CurrentMenuContext))
            throw new InvalidOperationException("Native manage_alley did not present the currently enabled change_leader_of_alley option.");

        var json = new StringBuilder(768);
        json.Append('{');
        Property(json, "settlementId", settlement.StringId);
        Property(json, "settlementName", settlement.Name?.ToString(), true);
        Property(json, "alleyTag", alley.Tag, true);
        Property(json, "initialAssignedHeroId", initialAssignedHero.StringId, true);
        Property(json, "candidateHeroId", candidate.StringId, true);
        Property(json, "nativeAvailability", finalAvailabilityName, true);
        Property(json, "menuId", menu.StringId, true);
        Property(json, "optionId", option.IdString, true);
        json.Append(",\"candidateCreatedInMemory\":").Append(Bool(candidateCreatedForFixture));
        json.Append(",\"playerAlleyDataPreparedInMemory\":true}");
        return json.ToString();
    }

    internal static Hero CreateEligibleAlleyClanHero(Settlement settlement, Clan playerClan)
    {
        var template = Campaign.Current.Models.HeroCreationModel.GetRandomTemplateByOccupation(Occupation.Wanderer, settlement) ??
            Hero.AllAliveHeroes.FirstOrDefault(hero => hero != null && hero.Occupation == Occupation.Wanderer && hero.Clan == null && hero.PartyBelongedTo == null)?.CharacterObject ??
            Hero.MainHero?.CharacterObject;
        if (template == null) throw new InvalidOperationException("Neither Native HeroCreationModel nor current Hero templates provide a testable Clan candidate.");
        var hero = HeroCreator.CreateSpecialHero(template, bornSettlement: null, faction: null, supporterOfClan: null, age: 28);
        hero.ChangeState(Hero.CharacterStates.Active);
        hero.HeroDeveloper.SetInitialSkillLevel(DefaultSkills.Roguery, 30);
        hero.SetTraitLevel(DefaultTraits.Mercy, 0);
        AddCompanionAction.Apply(playerClan, hero);
        return hero;
    }

    internal static object ReadMember(object instance, string propertyName)
    {
        if (instance == null) return null;
        return instance.GetType().GetProperty(propertyName, BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)?.GetValue(instance) ??
            instance.GetType().GetField(propertyName, BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)?.GetValue(instance);
    }

    internal static string BuildDiagnostics(string settlementId)
    {
        var settlement = Settlement.Find(settlementId);
        var behavior = Campaign.Current?.GetCampaignBehavior<AlleyCampaignBehavior>();
        var listField = typeof(AlleyCampaignBehavior).GetField("_playerOwnedCommonAreaData", BindingFlags.Instance | BindingFlags.NonPublic);
        var playerAlleyData = listField?.GetValue(behavior) as IList;
        var data = playerAlleyData?.Cast<object>().FirstOrDefault(item => (ReadMember(item, "Alley") as Alley)?.Settlement == settlement);
        var alley = ReadMember(data, "Alley") as Alley;
        var assignedHero = ReadMember(data, "AssignedClanMember") as Hero;
        var roster = ReadMember(data, "TroopRoster") as TroopRoster;
        if (data == null || alley == null || assignedHero == null || roster == null)
            throw new InvalidOperationException("Harness could not find the Native PlayerAlleyData record for diagnostics.");

        var json = new StringBuilder(512);
        json.Append('{');
        Property(json, "settlementId", settlement.StringId);
        Property(json, "alleyTag", alley.Tag, true);
        Property(json, "alleyOwnerId", alley.Owner?.StringId, true);
        Property(json, "assignedHeroId", assignedHero.StringId, true);
        json.Append(",\"roster\":[");
        for (var index = 0; index < roster.Count; index++)
        {
            if (index > 0) json.Append(',');
            var element = roster.GetElementCopyAtIndex(index);
            json.Append("{\"troopId\":\"").Append(Escape(element.Character?.StringId)).Append('"');
            Property(json, "heroId", element.Character?.HeroObject?.StringId, comma: true);
            json.Append(",\"count\":").Append(element.Number).Append('}');
        }
        json.Append("]}");
        return json.ToString();
    }

    private static void Property(StringBuilder json, string key, string value, bool comma = false)
    {
        if (comma) json.Append(',');
        else if (json.Length > 1) json.Append(',');
        json.Append('"').Append(key).Append("\":\"").Append(Escape(value)).Append('"');
    }

    private static string Bool(bool value) => value ? "true" : "false";
    private static string Escape(string value) => (value ?? string.Empty).Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\r", "\\r").Replace("\n", "\\n");
}
