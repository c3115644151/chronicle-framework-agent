using System;
using System.Collections;
using System.Linq;
using System.Reflection;
using System.Text;
using SandBox.CampaignBehaviors;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.Actions;
using TaleWorlds.CampaignSystem.GameMenus;
using TaleWorlds.CampaignSystem.GameState;
using TaleWorlds.CampaignSystem.Party;
using TaleWorlds.CampaignSystem.Roster;
using TaleWorlds.CampaignSystem.Settlements;
using TaleWorlds.Core;

namespace ChronicleFramework;

internal static class HarnessAlleyRosterFixture
{
    internal static string PrepareTownAlleyRoster(string settlementId, string destinationMenuId = "manage_alley", string volunteerScenario = "natural")
    {
        var mode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var root = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(mode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(root) || !System.IO.Directory.Exists(root))
            throw new InvalidOperationException("Alley roster fixtures are restricted to a visual Harness run with its temporary evidence directory.");
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("Alley roster fixture setup requires the Campaign Map and Town menu.");
        var settlement = Settlement.Find(settlementId);
        if (settlement == null || !settlement.IsTown || !settlement.IsVisible || settlement.Party?.MapEvent != null || settlement.IsUnderSiege)
            throw new InvalidOperationException("Alley roster fixture requires a visible, non-besieged Town without an active battle.");
        if (destinationMenuId != "manage_alley" && destinationMenuId != "town")
            throw new InvalidOperationException("Alley fixture destination must be the Native Town or manage_alley menu.");
        if (volunteerScenario != "natural" && volunteerScenario != "noVolunteers" && volunteerScenario != "availableVolunteers")
            throw new InvalidOperationException("Alley volunteer fixture scenario must be natural, noVolunteers, or availableVolunteers.");
        var unownedAlleys = settlement.Alleys?.Where(item => item != null && item.Owner == null).ToArray() ?? Array.Empty<Alley>();
        var alley = volunteerScenario == "availableVolunteers"
            ? unownedAlleys.FirstOrDefault(item => MBRandom.RandomFloatWithSeed((uint)CampaignTime.Now.ToWeeks, unchecked((uint)item.Tag.GetHashCode())) < 0.5f)
            : unownedAlleys.FirstOrDefault();
        if (alley == null) throw new InvalidOperationException("No unowned Native Alley is available in this disposable Town.");

        var behavior = Campaign.Current.GetCampaignBehavior<AlleyCampaignBehavior>();
        var dataType = typeof(AlleyCampaignBehavior).GetNestedType("PlayerAlleyData", BindingFlags.Public | BindingFlags.NonPublic);
        var listField = typeof(AlleyCampaignBehavior).GetField("_playerOwnedCommonAreaData", BindingFlags.Instance | BindingFlags.NonPublic);
        var playerAlleyData = listField?.GetValue(behavior) as IList;
        if (behavior == null || dataType == null || playerAlleyData == null)
            throw new MissingMemberException(typeof(AlleyCampaignBehavior).FullName, "PlayerAlleyData/_playerOwnedCommonAreaData");
        if (playerAlleyData.Cast<object>().Any(item => ReferenceEquals(HarnessAlleyLeaderFixture.ReadMember(item, "Alley"), alley)))
            throw new InvalidOperationException("Selected Alley already has Native PlayerAlleyData in this Campaign.");

        var assignedHero = HarnessAlleyLeaderFixture.CreateEligibleAlleyClanHero(settlement, Clan.PlayerClan);
        var baseTroop = MobileParty.MainParty.MemberRoster.GetTroopRoster()
            .FirstOrDefault(element => element.Character != null && !element.Character.IsHero && element.Number > 0).Character ?? settlement.Culture.BasicTroop;
        if (baseTroop == null) throw new InvalidOperationException("MainParty has no ordinary soldier to seed a disposable Alley roster.");
        var minimum = Campaign.Current.Models.AlleyModel.MinimumTroopCountInPlayerOwnedAlley;
        var maximum = Campaign.Current.Models.AlleyModel.MaximumTroopCountInPlayerOwnedAlley;
        if (minimum < 1 || maximum <= minimum) throw new InvalidOperationException("Native Alley troop limits are not suitable for boundary testing.");

        // Test-only seed: make the current MainParty troop type available on both sides and
        // provide a legal Left roster that can cross the Native minimum by one transfer.
        MobileParty.MainParty.MemberRoster.AddToCounts(baseTroop, minimum + 2);
        var partySizeLimit = MobileParty.MainParty.Party.PartySizeLimit;
        var membersBeforeCapacityFill = MobileParty.MainParty.MemberRoster.TotalManCount;
        var capacityFillerAdded = 0;
        if (volunteerScenario == "availableVolunteers")
        {
            var targetMembers = partySizeLimit - 1;
            if (membersBeforeCapacityFill > targetMembers)
                throw new InvalidOperationException("Available-volunteer fixture cannot demonstrate the native over-capacity result because the disposable MainParty already exceeds the limit-minus-one target.");
            capacityFillerAdded = targetMembers - membersBeforeCapacityFill;
            if (capacityFillerAdded > 0)
                MobileParty.MainParty.MemberRoster.AddToCounts(baseTroop, capacityFillerAdded, insertAtFront: false, woundedCount: 0, xpChange: 0, removeDepleted: true, index: -1);
        }
        var alleyRoster = TroopRoster.CreateDummyTroopRoster();
        alleyRoster.AddToCounts(assignedHero.CharacterObject, 1);
        alleyRoster.AddToCounts(baseTroop, minimum + 1);
        var constructor = dataType.GetConstructor(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic, null, new[] { typeof(Alley), typeof(TroopRoster) }, null);
        if (constructor == null) throw new MissingMethodException(dataType.FullName, ".ctor(Alley, TroopRoster)");
        var nativeData = constructor.Invoke(new object[] { alley, alleyRoster });
        var lastRecruitTimeField = dataType.GetField("LastRecruitTime", BindingFlags.Instance | BindingFlags.NonPublic);
        if (lastRecruitTimeField == null) throw new MissingFieldException(dataType.FullName, "LastRecruitTime");
        if (volunteerScenario == "noVolunteers") lastRecruitTimeField.SetValue(nativeData, CampaignTime.Now);
        var weeklyRandomProperty = dataType.GetProperty("RandomFloatWeekly", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
        if (weeklyRandomProperty?.GetValue(nativeData) is not float weeklyRandom) throw new MissingMemberException(dataType.FullName, "RandomFloatWeekly");
        if (volunteerScenario == "noVolunteers" && weeklyRandom != 2f) throw new InvalidOperationException("Harness no-volunteer branch did not resolve to the Native within-week sentinel.");
        if (volunteerScenario == "availableVolunteers" && weeklyRandom >= 0.5f) throw new InvalidOperationException("Harness available-volunteer Alley seed did not produce a non-empty Native roster branch.");
        alley.SetOwner(Hero.MainHero);
        playerAlleyData.Add(nativeData);

        var addCharacters = typeof(AlleyCampaignBehavior).GetMethod("AddPlayerAlleyCharacters", BindingFlags.Instance | BindingFlags.NonPublic);
        if (addCharacters == null) throw new MissingMethodException(typeof(AlleyCampaignBehavior).FullName, "AddPlayerAlleyCharacters(Alley)");
        addCharacters.Invoke(behavior, new object[] { alley });
        GameMenu.SwitchToMenu(destinationMenuId);
        var expectedOptionId = destinationMenuId == "manage_alley" ? "manage_alley_troops" : "manage_alley";
        var option = Campaign.Current.CurrentMenuContext?.GameMenu?.MenuOptions.FirstOrDefault(item => item.IdString == expectedOptionId);
        if (Campaign.Current.CurrentMenuContext?.GameMenu?.StringId != destinationMenuId || option == null || !option.IsEnabled || !option.GetConditionsHold(Game.Current, Campaign.Current.CurrentMenuContext))
            throw new InvalidOperationException("Expected Native Alley option is not available after preparing the in-memory player Alley.");

        var json = new StringBuilder(768);
        json.Append('{');
        Property(json, "settlementId", settlement.StringId);
        Property(json, "alleyTag", alley.Tag, true);
        Property(json, "assignedHeroId", assignedHero.StringId, true);
        Property(json, "troopId", baseTroop.StringId, true);
        Property(json, "destinationMenuId", destinationMenuId, true);
        Property(json, "volunteerScenario", volunteerScenario, true);
        json.Append(",\"weeklyRandomForFixture\":").Append(weeklyRandom.ToString("R", System.Globalization.CultureInfo.InvariantCulture));
        Property(json, "volunteerScenario", volunteerScenario, true);
        json.Append(",\"initialAlleyCount\":").Append(minimum + 1);
        json.Append(",\"minimumTroops\":").Append(minimum);
        json.Append(",\"maximumTroops\":").Append(maximum);
        json.Append(",\"partySizeLimit\":").Append(partySizeLimit);
        json.Append(",\"membersBeforeCapacityFill\":").Append(membersBeforeCapacityFill);
        json.Append(",\"capacityFillerAdded\":").Append(capacityFillerAdded);
        json.Append(",\"membersAfterCapacityFill\":").Append(MobileParty.MainParty.MemberRoster.TotalManCount);
        json.Append(",\"initialMainPartyCount\":").Append(MobileParty.MainParty.MemberRoster.GetTroopCount(baseTroop));
        Property(json, "optionId", option.IdString, true);
        json.Append(",\"playerAlleyDataPreparedInMemory\":true}");
        return json.ToString();
    }

    internal static string BuildDiagnostics(string settlementId, string alleyTag = null, string referenceHeroId = null)
    {
        var settlement = Settlement.Find(settlementId);
        var behavior = Campaign.Current?.GetCampaignBehavior<AlleyCampaignBehavior>();
        var listField = typeof(AlleyCampaignBehavior).GetField("_playerOwnedCommonAreaData", BindingFlags.Instance | BindingFlags.NonPublic);
        var rows = listField?.GetValue(behavior) as IList;
        var data = rows?.Cast<object>().FirstOrDefault(item =>
        {
            var itemAlley = HarnessAlleyLeaderFixture.ReadMember(item, "Alley") as Alley;
            return itemAlley?.Settlement == settlement && (string.IsNullOrWhiteSpace(alleyTag) || string.Equals(itemAlley.Tag, alleyTag, StringComparison.Ordinal));
        });
        var alley = (HarnessAlleyLeaderFixture.ReadMember(data, "Alley") as Alley) ??
            settlement?.Alleys?.FirstOrDefault(item => item != null &&
                (string.IsNullOrWhiteSpace(alleyTag) ? item.Owner == Hero.MainHero : string.Equals(item.Tag, alleyTag, StringComparison.Ordinal)));
        var assigned = HarnessAlleyLeaderFixture.ReadMember(data, "AssignedClanMember") as Hero;
        var attackedBy = HarnessAlleyLeaderFixture.ReadMember(data, "UnderAttackBy") as Alley;
        var referenceHero = string.IsNullOrWhiteSpace(referenceHeroId) ? null : Hero.AllAliveHeroes.FirstOrDefault(hero => string.Equals(hero.StringId, referenceHeroId, StringComparison.Ordinal));
        var roster = HarnessAlleyLeaderFixture.ReadMember(data, "TroopRoster") as TroopRoster;
        if (alley == null)
            throw new InvalidOperationException("Could not read the Native PlayerAlleyData for the test Town.");
        roster ??= TroopRoster.CreateDummyTroopRoster();
        var json = new StringBuilder(1024);
        json.Append('{');
        Property(json, "settlementId", settlement.StringId);
        Property(json, "alleyOwnerId", alley.Owner?.StringId, true);
        Property(json, "assignedHeroId", assigned?.StringId, true);
        Property(json, "attackingAlleyTag", attackedBy?.Tag, true);
        Property(json, "attackingOwnerId", attackedBy?.Owner?.StringId, true);
        Property(json, "referenceHeroId", referenceHero?.StringId, true);
        json.Append(",\"mainHeroRelationToReferenceHero\":").Append(referenceHero == null ? "null" : Hero.MainHero.GetRelation(referenceHero).ToString(System.Globalization.CultureInfo.InvariantCulture));
        json.Append(",\"playerAlleyDataPresent\":").Append(data == null ? "false" : "true");
        json.Append(",\"underAttack\":").Append(HarnessAlleyLeaderFixture.ReadMember(data, "IsUnderAttack") is bool underAttack && underAttack ? "true" : "false");
        json.Append(",\"alleyRoster\":");
        AppendRoster(json, roster);
        json.Append(",\"mainPartyRoster\":");
        AppendRoster(json, MobileParty.MainParty.MemberRoster);
        json.Append(",\"gold\":").Append(Hero.MainHero.Gold);
        json.Append(",\"influence\":").Append(Clan.PlayerClan.Influence.ToString("R", System.Globalization.CultureInfo.InvariantCulture));
        json.Append(",\"lastRecruitDay\":");
        if (HarnessAlleyLeaderFixture.ReadMember(data, "LastRecruitTime") is CampaignTime lastRecruitTime)
            json.Append(lastRecruitTime.ToDays.ToString("R", System.Globalization.CultureInfo.InvariantCulture));
        else
            json.Append("null");
        json.Append(",\"randomFloatWeekly\":");
        var weeklyRandomProperty = data?.GetType().GetProperty("RandomFloatWeekly", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
        if (weeklyRandomProperty?.GetValue(data) is float randomFloatWeekly)
            json.Append(randomFloatWeekly.ToString("R", System.Globalization.CultureInfo.InvariantCulture));
        else
            json.Append("null");
        json.Append(",\"campaignDay\":").Append(CampaignTime.Now.ToDays.ToString("R", System.Globalization.CultureInfo.InvariantCulture));
        Property(json, "timeControlMode", Campaign.Current.TimeControlMode.ToString(), true);
        json.Append(",\"isWaiting\":").Append(Campaign.Current.IsMainPartyWaiting ? "true" : "false");
        json.Append('}');
        return json.ToString();
    }

    internal static string SeedAlleyAttack(string settlementId, string alleyTag)
    {
        var mode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var root = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(mode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(root) || !System.IO.Directory.Exists(root))
            throw new InvalidOperationException("Alley attack fixtures are restricted to a visual Harness run with its temporary evidence directory.");
        if (Game.Current?.GameStateManager?.ActiveState is not MapState || Campaign.Current?.CurrentMenuContext?.GameMenu?.StringId != "town")
            throw new InvalidOperationException("Alley attack fixture setup requires a Native Town Map menu.");

        var settlement = Settlement.Find(settlementId);
        var behavior = Campaign.Current?.GetCampaignBehavior<AlleyCampaignBehavior>();
        if (settlement == null || !settlement.IsTown || behavior == null)
            throw new InvalidOperationException("Alley attack fixture requires a current Town and Native AlleyCampaignBehavior.");
        var dataType = typeof(AlleyCampaignBehavior).GetNestedType("PlayerAlleyData", BindingFlags.Public | BindingFlags.NonPublic);
        var listField = typeof(AlleyCampaignBehavior).GetField("_playerOwnedCommonAreaData", BindingFlags.Instance | BindingFlags.NonPublic);
        var rows = listField?.GetValue(behavior) as IList;
        var data = rows?.Cast<object>().FirstOrDefault(item =>
        {
            var playerAlley = HarnessAlleyLeaderFixture.ReadMember(item, "Alley") as Alley;
            return playerAlley?.Settlement == settlement && string.Equals(playerAlley.Tag, alleyTag, StringComparison.Ordinal);
        });
        var playerAlleyData = HarnessAlleyLeaderFixture.ReadMember(data, "Alley") as Alley;
        var playerRoster = HarnessAlleyLeaderFixture.ReadMember(data, "TroopRoster") as TroopRoster;
        if (data == null || playerAlleyData == null || playerRoster == null || playerAlleyData.Owner != Hero.MainHero)
            throw new InvalidOperationException("Alley attack fixture requires the specified Native PlayerAlleyData.");
        if (HarnessAlleyLeaderFixture.ReadMember(data, "UnderAttackBy") is Alley)
            throw new InvalidOperationException("Selected PlayerAlleyData is already under attack.");

        var hostileLeader = settlement.Notables.FirstOrDefault(hero => hero != null && hero.IsGangLeader && !hero.IsDead && hero != Hero.MainHero);
        if (hostileLeader == null) throw new InvalidOperationException("Town has no living Native gang leader to use as the attacking Alley owner.");
        var attackingAlley = settlement.Alleys?.FirstOrDefault(item => item != null && item != playerAlleyData && item.Owner != Hero.MainHero);
        if (attackingAlley == null) throw new InvalidOperationException("Town has no second Native Alley for the attacking GangLeader fixture.");
        if (attackingAlley.Owner != hostileLeader) attackingAlley.SetOwner(hostileLeader);

        var underAttackField = dataType?.GetField("UnderAttackBy", BindingFlags.Instance | BindingFlags.NonPublic);
        var dueDateField = dataType?.GetField("AttackResponseDueDate", BindingFlags.Instance | BindingFlags.NonPublic);
        if (underAttackField == null || dueDateField == null)
            throw new MissingMemberException(dataType?.FullName, "UnderAttackBy/AttackResponseDueDate");
        var responseDays = Campaign.Current.Models.AlleyModel.GetAlleyAttackResponseTimeInDays(playerRoster);
        underAttackField.SetValue(data, attackingAlley);
        dueDateField.SetValue(data, CampaignTime.DaysFromNow(responseDays));
        ChangeRelationAction.ApplyPlayerRelation(hostileLeader, -5, true, true);

        if (HarnessAlleyLeaderFixture.ReadMember(data, "IsUnderAttack") is not bool isUnderAttack || !isUnderAttack)
            throw new InvalidOperationException("Native PlayerAlleyData did not enter its under-attack state.");
        var json = new StringBuilder(512);
        json.Append('{');
        Property(json, "settlementId", settlement.StringId);
        Property(json, "playerAlleyTag", playerAlleyData.Tag, true);
        Property(json, "attackingAlleyTag", attackingAlley.Tag, true);
        Property(json, "attackingHeroId", hostileLeader.StringId, true);
        Property(json, "attackingHeroName", hostileLeader.Name?.ToString(), true);
        json.Append(",\"responseDueDay\":").Append(CampaignTime.DaysFromNow(responseDays).ToDays.ToString("R", System.Globalization.CultureInfo.InvariantCulture));
        json.Append(",\"responseDays\":").Append(responseDays.ToString("R", System.Globalization.CultureInfo.InvariantCulture));
        json.Append(",\"relationAfterNativeAttackFixture\":").Append(Hero.MainHero.GetRelation(hostileLeader));
        json.Append(",\"playerAlleyUnderAttack\":true}");
        return json.ToString();
    }

    private static void AppendRoster(StringBuilder json, TroopRoster roster)
    {
        json.Append('[');
        var outputIndex = 0;
        foreach (var element in roster.GetTroopRoster())
        {
            if (element.Character == null || element.Number <= 0) continue;
            if (outputIndex++ > 0) json.Append(',');
            json.Append("{\"troopId\":\"").Append(Escape(element.Character.StringId)).Append('"');
            json.Append(",\"count\":").Append(element.Number);
            json.Append(",\"wounded\":").Append(element.WoundedNumber);
            json.Append('}');
        }
        json.Append(']');
    }

    private static void Property(StringBuilder json, string name, string value, bool comma = false)
    {
        if (comma) json.Append(',');
        else if (json.Length > 1) json.Append(',');
        json.Append('"').Append(name).Append("\":\"").Append(Escape(value)).Append('"');
    }

    private static string Escape(string value) => (value ?? string.Empty).Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\r", "\\r").Replace("\n", "\\n");
}
