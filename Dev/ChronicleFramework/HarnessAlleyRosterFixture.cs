using System;
using System.Collections;
using System.Linq;
using System.Reflection;
using System.Text;
using SandBox.CampaignBehaviors;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.GameMenus;
using TaleWorlds.CampaignSystem.GameState;
using TaleWorlds.CampaignSystem.Party;
using TaleWorlds.CampaignSystem.Roster;
using TaleWorlds.CampaignSystem.Settlements;
using TaleWorlds.Core;

namespace ChronicleFramework;

internal static class HarnessAlleyRosterFixture
{
    internal static string PrepareTownAlleyRoster(string settlementId)
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
        var alley = settlement.Alleys?.FirstOrDefault(item => item != null && item.Owner == null);
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
        var alleyRoster = TroopRoster.CreateDummyTroopRoster();
        alleyRoster.AddToCounts(assignedHero.CharacterObject, 1);
        alleyRoster.AddToCounts(baseTroop, minimum + 1);
        var constructor = dataType.GetConstructor(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic, null, new[] { typeof(Alley), typeof(TroopRoster) }, null);
        if (constructor == null) throw new MissingMethodException(dataType.FullName, ".ctor(Alley, TroopRoster)");
        var nativeData = constructor.Invoke(new object[] { alley, alleyRoster });
        alley.SetOwner(Hero.MainHero);
        playerAlleyData.Add(nativeData);

        var addCharacters = typeof(AlleyCampaignBehavior).GetMethod("AddPlayerAlleyCharacters", BindingFlags.Instance | BindingFlags.NonPublic);
        if (addCharacters == null) throw new MissingMethodException(typeof(AlleyCampaignBehavior).FullName, "AddPlayerAlleyCharacters(Alley)");
        addCharacters.Invoke(behavior, new object[] { alley });
        GameMenu.SwitchToMenu("manage_alley");
        var option = Campaign.Current.CurrentMenuContext?.GameMenu?.MenuOptions.FirstOrDefault(item => item.IdString == "manage_alley_troops");
        if (Campaign.Current.CurrentMenuContext?.GameMenu?.StringId != "manage_alley" || option == null || !option.IsEnabled || !option.GetConditionsHold(Game.Current, Campaign.Current.CurrentMenuContext))
            throw new InvalidOperationException("Native manage_alley_troops is not available after preparing the in-memory player Alley.");

        var json = new StringBuilder(768);
        json.Append('{');
        Property(json, "settlementId", settlement.StringId);
        Property(json, "alleyTag", alley.Tag, true);
        Property(json, "assignedHeroId", assignedHero.StringId, true);
        Property(json, "troopId", baseTroop.StringId, true);
        json.Append(",\"initialAlleyCount\":").Append(minimum + 1);
        json.Append(",\"minimumTroops\":").Append(minimum);
        json.Append(",\"maximumTroops\":").Append(maximum);
        json.Append(",\"initialMainPartyCount\":").Append(MobileParty.MainParty.MemberRoster.GetTroopCount(baseTroop));
        Property(json, "optionId", option.IdString, true);
        json.Append(",\"playerAlleyDataPreparedInMemory\":true}");
        return json.ToString();
    }

    internal static string BuildDiagnostics(string settlementId, string alleyTag = null)
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
        var roster = HarnessAlleyLeaderFixture.ReadMember(data, "TroopRoster") as TroopRoster;
        if (alley == null)
            throw new InvalidOperationException("Could not read the Native PlayerAlleyData for the test Town.");
        roster ??= TroopRoster.CreateDummyTroopRoster();
        var json = new StringBuilder(1024);
        json.Append('{');
        Property(json, "settlementId", settlement.StringId);
        Property(json, "alleyOwnerId", alley.Owner?.StringId, true);
        Property(json, "assignedHeroId", assigned?.StringId, true);
        json.Append(",\"playerAlleyDataPresent\":").Append(data == null ? "false" : "true");
        json.Append(",\"underAttack\":").Append(HarnessAlleyLeaderFixture.ReadMember(data, "IsUnderAttack") is bool underAttack && underAttack ? "true" : "false");
        json.Append(",\"alleyRoster\":");
        AppendRoster(json, roster);
        json.Append(",\"mainPartyRoster\":");
        AppendRoster(json, MobileParty.MainParty.MemberRoster);
        json.Append(",\"gold\":").Append(Hero.MainHero.Gold);
        json.Append(",\"influence\":").Append(Clan.PlayerClan.Influence.ToString("R", System.Globalization.CultureInfo.InvariantCulture));
        json.Append(",\"campaignDay\":").Append(CampaignTime.Now.ToDays.ToString("R", System.Globalization.CultureInfo.InvariantCulture));
        Property(json, "timeControlMode", Campaign.Current.TimeControlMode.ToString(), true);
        json.Append(",\"isWaiting\":").Append(Campaign.Current.IsMainPartyWaiting ? "true" : "false");
        json.Append('}');
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
