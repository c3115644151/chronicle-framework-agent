using System;
using System.Globalization;
using System.Linq;
using System.Text;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.Actions;
using TaleWorlds.CampaignSystem.Encounters;
using TaleWorlds.CampaignSystem.GameMenus;
using TaleWorlds.CampaignSystem.GameState;
using TaleWorlds.CampaignSystem.Party;
using TaleWorlds.CampaignSystem.Settlements;
using TaleWorlds.Core;

namespace ChronicleFramework;

internal static class ChronicleHarnessCaptivityObservationFixture
{
    internal static string BuildCaptivityDiagnostics(string captorPartyId = null)
    {
        var mode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var root = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(mode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(root) || !System.IO.Directory.Exists(root))
            throw new InvalidOperationException("Captivity diagnostics are restricted to a visual Harness run with a Harness temp directory.");
        if (Game.Current?.GameStateManager?.ActiveState is not MapState || Campaign.Current == null || Hero.MainHero == null || MobileParty.MainParty == null)
            throw new InvalidOperationException("Captivity diagnostics require a live Campaign Map and MainHero.");

        TaleWorlds.CampaignSystem.Party.PartyBase captorParty = null;
        if (!string.IsNullOrWhiteSpace(captorPartyId))
            captorParty = MobileParty.All.FirstOrDefault(party => party != null && string.Equals(party.StringId, captorPartyId, StringComparison.Ordinal))?.Party;
        if (captorParty == null && !string.IsNullOrWhiteSpace(captorPartyId))
            captorParty = Settlement.All.FirstOrDefault(settlement => settlement != null && string.Equals(settlement.StringId, captorPartyId, StringComparison.Ordinal))?.Party;
        if (captorParty == null && PlayerCaptivity.IsCaptive) captorParty = PlayerCaptivity.CaptorParty;
        var prisonerParty = Hero.MainHero.PartyBelongedToAsPrisoner;
        var menuId = Campaign.Current.CurrentMenuContext?.GameMenu?.StringId;
        var json = new StringBuilder(512);
        json.Append('{').Append("\"schemaVersion\":1");
        json.Append(",\"isCaptive\":").Append(ChroniclePartyUpgradeAdapter.Bool(PlayerCaptivity.IsCaptive));
        json.Append(",\"heroIsPrisoner\":").Append(ChroniclePartyUpgradeAdapter.Bool(Hero.MainHero.IsPrisoner));
        ChroniclePartyUpgradeAdapter.Property(json, "heroPrisonerPartyId", prisonerParty?.Id);
        ChroniclePartyUpgradeAdapter.Property(json, "captorPartyId", captorParty == null ? null : captorParty.Id.ToString());
        json.Append(",\"captorPartyFound\":").Append(ChroniclePartyUpgradeAdapter.Bool(captorParty != null));
        json.Append(",\"captorRosterContainsMainHero\":").Append(ChroniclePartyUpgradeAdapter.Bool(captorParty != null && captorParty.PrisonRoster.GetTroopCount(Hero.MainHero.CharacterObject) > 0));
        json.Append(",\"captorMainHeroPrisonerCount\":").Append(captorParty?.PrisonRoster.GetTroopCount(Hero.MainHero.CharacterObject) ?? 0);
        json.Append(",\"mainPartyIsActive\":").Append(ChroniclePartyUpgradeAdapter.Bool(MobileParty.MainParty.IsActive));
        json.Append(",\"mainPartyMemberCount\":").Append(MobileParty.MainParty.MemberRoster.TotalManCount);
        json.Append(",\"mainPartyContainsMainHero\":").Append(ChroniclePartyUpgradeAdapter.Bool(MobileParty.MainParty.MemberRoster.GetTroopCount(Hero.MainHero.CharacterObject) > 0));
        json.Append(",\"gold\":").Append(Hero.MainHero.Gold);
        json.Append(",\"campaignDay\":").Append(CampaignTime.Now.ToDays.ToString("F6", CultureInfo.InvariantCulture));
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlMode", Campaign.Current.TimeControlMode.ToString());
        ChroniclePartyUpgradeAdapter.Property(json, "menuId", menuId);
        json.Append('}');
        return json.ToString();
    }

    internal static string SwitchToNativeWildernessEscapeMenu()
    {
        var mode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var root = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(mode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(root) || !System.IO.Directory.Exists(root))
            throw new InvalidOperationException("Captivity menu transition fixture is restricted to a visual Harness run with a Harness temp directory.");
        if (Game.Current?.GameStateManager?.ActiveState is not MapState mapState || !PlayerCaptivity.IsCaptive)
            throw new InvalidOperationException("Captivity menu transition fixture requires an active Native MainHero captivity on the Campaign Map.");

        var previousMenuId = Campaign.Current.CurrentMenuContext?.GameMenu?.StringId;
        if (mapState.AtMenu) GameMenu.SwitchToMenu("menu_captivity_end_wilderness_escape");
        else GameMenu.ActivateGameMenu("menu_captivity_end_wilderness_escape");
        var currentMenuId = Campaign.Current.CurrentMenuContext?.GameMenu?.StringId;
        if (!string.Equals(currentMenuId, "menu_captivity_end_wilderness_escape", StringComparison.Ordinal))
            throw new InvalidOperationException("Native Captivity wilderness-escape GameMenu was not switched to as requested by the Harness fixture.");

        var json = new StringBuilder(256);
        json.Append('{').Append("\"schemaVersion\":1,\"testOnly\":true");
        ChroniclePartyUpgradeAdapter.Property(json, "previousMenuId", previousMenuId);
        ChroniclePartyUpgradeAdapter.Property(json, "currentMenuId", currentMenuId);
        json.Append(",\"isCaptive\":").Append(ChroniclePartyUpgradeAdapter.Bool(PlayerCaptivity.IsCaptive));
        return json.Append('}').ToString();
    }

    internal static string StartWithNativeWildernessRansomOffer(string captorPartyId)
    {
        var mode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var root = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(mode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(root) || !System.IO.Directory.Exists(root))
            throw new InvalidOperationException("Captivity observation fixture is restricted to a visual Harness run with a Harness temp directory.");
        if (Game.Current?.GameStateManager?.ActiveState is not MapState || Campaign.Current == null || Hero.MainHero == null || MobileParty.MainParty == null)
            throw new InvalidOperationException("Captivity observation fixture requires a live Campaign Map and MainHero.");
        if (PlayerCaptivity.IsCaptive || PlayerEncounter.IsActive || MobileParty.MainParty.IsCurrentlyAtSea)
            throw new InvalidOperationException("Captivity observation fixture requires a free MainHero on land with no active encounter.");
        if (Hero.MainHero.IsPrisoner || Hero.MainHero.PartyBelongedToAsPrisoner != null)
            throw new InvalidOperationException("MainHero already belongs to a prisoner roster.");

        var captor = MobileParty.All.FirstOrDefault(party => party != null && party.IsActive && string.Equals(party.StringId, captorPartyId, StringComparison.Ordinal));
        if (captor == null || captor == MobileParty.MainParty)
            throw new InvalidOperationException("Captivity observation fixture requires an active Native captor party ID from the current Campaign.");

        var dayBefore = CampaignTime.Now.ToDays;
        var goldBefore = Hero.MainHero.Gold;
        var partyMembersBefore = MobileParty.MainParty.MemberRoster.TotalManCount;
        var previousTimeMode = Campaign.Current.TimeControlMode.ToString();
        TakePrisonerAction.Apply(captor.Party, Hero.MainHero);
        PlayerCaptivity.CaptorParty = captor.Party;
        Campaign.Current.PlayerCaptivity.SetRansomAmount();
        var ransomAmount = Campaign.Current.PlayerCaptivity.CurrentRansomAmount;
        if (ransomAmount <= 0) throw new InvalidOperationException("Native PlayerCaptivity produced no positive ransom quote for the observation fixture.");

        var previousMenuId = Campaign.Current.CurrentMenuContext?.GameMenu?.StringId;
        if (!string.Equals(previousMenuId, "prisoner_wait", StringComparison.Ordinal))
            throw new InvalidOperationException("Native MainHero captivity did not enter the expected wilderness prisoner_wait menu.");
        GameMenu.SwitchToMenu("menu_captivity_end_propose_ransom_wilderness");
        var actualMenuId = Campaign.Current.CurrentMenuContext?.GameMenu?.StringId;
        if (!string.Equals(actualMenuId, "menu_captivity_end_propose_ransom_wilderness", StringComparison.Ordinal))
            throw new InvalidOperationException("Native captivity ransom GameMenu was not activated as requested by the Harness fixture.");

        var json = new StringBuilder(512);
        json.Append('{').Append("\"schemaVersion\":1,\"testOnly\":true,\"mainHeroCapturedByNativeAction\":true");
        ChroniclePartyUpgradeAdapter.Property(json, "captorPartyId", captor.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "previousMenuId", previousMenuId);
        ChroniclePartyUpgradeAdapter.Property(json, "menuId", actualMenuId);
        json.Append(",\"nativeRansomAmount\":").Append(ransomAmount);
        json.Append(",\"goldBeforeCapture\":").Append(goldBefore);
        json.Append(",\"goldAfterCapture\":").Append(Hero.MainHero.Gold);
        json.Append(",\"partyMembersBeforeCapture\":").Append(partyMembersBefore);
        json.Append(",\"partyMembersAfterCapture\":").Append(MobileParty.MainParty.MemberRoster.TotalManCount);
        json.Append(",\"campaignDayBeforeCapture\":").Append(dayBefore.ToString("F6", CultureInfo.InvariantCulture));
        json.Append(",\"campaignDayAfterCapture\":").Append(CampaignTime.Now.ToDays.ToString("F6", CultureInfo.InvariantCulture));
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeBefore", previousTimeMode);
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeAfter", Campaign.Current.TimeControlMode.ToString());
        return json.Append('}').ToString();
    }

    internal static string StartWithNativePrisonRansomOffer(string captorSettlementId)
    {
        var mode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var root = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(mode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(root) || !System.IO.Directory.Exists(root))
            throw new InvalidOperationException("Prison captivity fixture is restricted to a visual Harness run with a Harness temp directory.");
        if (Game.Current?.GameStateManager?.ActiveState is not MapState mapState || Campaign.Current == null || Hero.MainHero == null || MobileParty.MainParty == null)
            throw new InvalidOperationException("Prison captivity fixture requires a live Campaign Map and MainHero.");
        if (PlayerCaptivity.IsCaptive || PlayerEncounter.IsActive || MobileParty.MainParty.IsCurrentlyAtSea)
            throw new InvalidOperationException("Prison captivity fixture requires a free MainHero on land with no active encounter.");
        if (Hero.MainHero.IsPrisoner || Hero.MainHero.PartyBelongedToAsPrisoner != null)
            throw new InvalidOperationException("MainHero already belongs to a prisoner roster.");

        var captorSettlement = Settlement.All.FirstOrDefault(settlement => settlement != null && settlement.IsActive &&
            (settlement.IsTown || settlement.IsCastle) && string.Equals(settlement.StringId, captorSettlementId, StringComparison.Ordinal));
        if (captorSettlement?.Party == null)
            throw new InvalidOperationException("Prison captivity fixture requires an active Town or Castle settlement ID from the current Campaign.");

        var dayBefore = CampaignTime.Now.ToDays;
        var goldBeforeFixture = Hero.MainHero.Gold;
        var wasAtWarBeforeFixture = FactionManager.IsAtWarAgainstFaction(captorSettlement.MapFaction, Hero.MainHero.MapFaction);
        if (!wasAtWarBeforeFixture)
            DeclareWarAction.ApplyByDefault(captorSettlement.MapFaction, Hero.MainHero.MapFaction);
        const int fixtureGoldFloor = 10000;
        if (Hero.MainHero.Gold < fixtureGoldFloor)
            GiveGoldAction.ApplyBetweenCharacters(null, Hero.MainHero, fixtureGoldFloor - Hero.MainHero.Gold);

        TakePrisonerAction.Apply(captorSettlement.Party, Hero.MainHero);
        PlayerCaptivity.CaptorParty = captorSettlement.Party;
        if (!mapState.AtMenu || !string.Equals(Campaign.Current.CurrentMenuContext?.GameMenu?.StringId, "settlement_wait", StringComparison.Ordinal))
            throw new InvalidOperationException("Native MainHero captivity did not enter the settlement_wait menu for the settlement-captor fixture.");
        Campaign.Current.PlayerCaptivity.SetRansomAmount();
        var ransomAmount = Campaign.Current.PlayerCaptivity.CurrentRansomAmount;
        if (ransomAmount <= 0 || ransomAmount > Hero.MainHero.Gold)
            throw new InvalidOperationException("Native PlayerCaptivity produced an unusable ransom quote for the prison fixture.");

        GameMenu.SwitchToMenu("menu_captivity_end_propose_ransom_in_prison");
        var actualMenuId = Campaign.Current.CurrentMenuContext?.GameMenu?.StringId;
        if (!string.Equals(actualMenuId, "menu_captivity_end_propose_ransom_in_prison", StringComparison.Ordinal))
            throw new InvalidOperationException("Native captivity prison ransom GameMenu was not activated as requested by the Harness fixture.");

        var json = new StringBuilder(512);
        json.Append('{').Append("\"schemaVersion\":1,\"testOnly\":true,\"mainHeroCapturedByNativeAction\":true,\"captorIsSettlement\":true");
        ChroniclePartyUpgradeAdapter.Property(json, "captorSettlementId", captorSettlement.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "captorSettlementType", captorSettlement.IsTown ? "town" : "castle");
        json.Append(",\"captorAtWarWithPlayerBeforeFixture\":").Append(ChroniclePartyUpgradeAdapter.Bool(wasAtWarBeforeFixture));
        json.Append(",\"captorAtWarWithPlayerAtRansomMenu\":").Append(ChroniclePartyUpgradeAdapter.Bool(FactionManager.IsAtWarAgainstFaction(captorSettlement.MapFaction, Hero.MainHero.MapFaction)));
        ChroniclePartyUpgradeAdapter.Property(json, "previousMenuId", "settlement_wait");
        ChroniclePartyUpgradeAdapter.Property(json, "menuId", actualMenuId);
        json.Append(",\"goldBeforeFixture\":").Append(goldBeforeFixture);
        json.Append(",\"goldAtRansomMenu\":").Append(Hero.MainHero.Gold);
        json.Append(",\"nativeRansomAmount\":").Append(ransomAmount);
        json.Append(",\"campaignDayBeforeCapture\":").Append(dayBefore.ToString("F6", CultureInfo.InvariantCulture));
        json.Append(",\"campaignDayAtRansomMenu\":").Append(CampaignTime.Now.ToDays.ToString("F6", CultureInfo.InvariantCulture));
        return json.Append('}').ToString();
    }
}
