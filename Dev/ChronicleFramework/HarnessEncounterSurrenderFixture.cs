using System;
using System.Globalization;
using System.Text;
using Helpers;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.Encounters;
using TaleWorlds.CampaignSystem.GameState;
using TaleWorlds.CampaignSystem.Party;
using TaleWorlds.Core;

namespace ChronicleFramework;

internal static class ChronicleHarnessEncounterSurrenderFixture
{
    internal static string PrepareNativeSurrenderCondition()
    {
        var mode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var root = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(mode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(root) || !System.IO.Directory.Exists(root))
            throw new InvalidOperationException("Encounter surrender condition fixture is restricted to a visual Harness run with a Harness temp directory.");
        if (Game.Current?.GameStateManager?.ActiveState is not MapState mapState || Campaign.Current == null || Hero.MainHero == null || MobileParty.MainParty == null)
            throw new InvalidOperationException("Encounter surrender condition fixture requires a live Campaign Map and MainHero.");
        if (!PlayerEncounter.IsActive || MobileParty.MainParty.MapEvent == null || PlayerCaptivity.IsCaptive || Hero.MainHero.IsPrisoner ||
            !string.Equals(Campaign.Current.CurrentMenuContext?.GameMenu?.StringId, "encounter", StringComparison.Ordinal) || !mapState.AtMenu)
            throw new InvalidOperationException("Encounter surrender condition fixture requires a free MainHero in the actual Native encounter menu and MapEvent.");

        var hitPointsBefore = Hero.MainHero.HitPoints;
        var woundLimit = Hero.MainHero.WoundedHealthLimit;
        var moraleBefore = MobileParty.MainParty.Morale;
        var moraleEventsBefore = MobileParty.MainParty.RecentEventsMorale;
        var dayBefore = CampaignTime.Now.ToDays;
        var timeModeBefore = Campaign.Current.TimeControlMode.ToString();
        Hero.MainHero.MakeWounded();
        MobileParty.MainParty.RecentEventsMorale = -100f;

        var isWounded = Hero.MainHero.IsWounded;
        var canPartyAttack = MobilePartyHelper.CanPartyAttackWithCurrentMorale(MobileParty.MainParty);
        var isValid = isWounded && !canPartyAttack;
        if (!isValid)
            throw new InvalidOperationException("Native encounter surrender menu condition could not be reached using the wounded-MainHero/zero-morale branch.");

        var json = new StringBuilder(384);
        json.Append('{').Append("\"schemaVersion\":1,\"testOnly\":true,\"usedNativeHeroWoundMethod\":true");
        json.Append(",\"heroHitPointsBefore\":").Append(hitPointsBefore);
        json.Append(",\"heroHitPointsAfter\":").Append(Hero.MainHero.HitPoints);
        json.Append(",\"heroWoundedHealthLimit\":").Append(woundLimit);
        json.Append(",\"heroIsWounded\":").Append(ChroniclePartyUpgradeAdapter.Bool(isWounded));
        json.Append(",\"partyMoraleBefore\":").Append(moraleBefore.ToString("F3", CultureInfo.InvariantCulture));
        json.Append(",\"partyMoraleAfter\":").Append(MobileParty.MainParty.Morale.ToString("F3", CultureInfo.InvariantCulture));
        json.Append(",\"partyMoraleEventsBefore\":").Append(moraleEventsBefore.ToString("F3", CultureInfo.InvariantCulture));
        json.Append(",\"partyMoraleEventsAfter\":").Append(MobileParty.MainParty.RecentEventsMorale.ToString("F3", CultureInfo.InvariantCulture));
        json.Append(",\"nativeCanPartyAttackAfter\":").Append(ChroniclePartyUpgradeAdapter.Bool(canPartyAttack));
        json.Append(",\"nativeSurrenderConditionSatisfied\":").Append(ChroniclePartyUpgradeAdapter.Bool(isValid));
        ChroniclePartyUpgradeAdapter.Property(json, "currentMenuId", Campaign.Current.CurrentMenuContext?.GameMenu?.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "encounteredPartyId", PlayerEncounter.EncounteredParty == null ? null : PlayerEncounter.EncounteredParty.Id.ToString());
        json.Append(",\"campaignDayBefore\":").Append(dayBefore.ToString("F6", CultureInfo.InvariantCulture));
        json.Append(",\"campaignDayAfter\":").Append(CampaignTime.Now.ToDays.ToString("F6", CultureInfo.InvariantCulture));
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeBefore", timeModeBefore);
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeAfter", Campaign.Current.TimeControlMode.ToString());
        return json.Append('}').ToString();
    }
}
