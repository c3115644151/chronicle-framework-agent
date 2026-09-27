using System;
using System.Linq;
using System.Text;
using Helpers;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.GameState;
using TaleWorlds.CampaignSystem.Party;
using TaleWorlds.CampaignSystem.ViewModelCollection.Party;
using TaleWorlds.Core;

namespace ChronicleFramework;

internal static class ChroniclePartyUpgradeAdapter
{
    internal static string BuildOptionsJson()
    {
        var beforeMode = Campaign.Current.TimeControlMode.ToString();
        var beforeDay = CampaignTime.Now.ToDays;
        var viewModel = OpenMainPartyScreen();
        var duringMode = Campaign.Current.TimeControlMode.ToString();
        var json = new StringBuilder(4096);
        json.Append('{').Append("\"schemaVersion\":1");
        Property(json, "heroId", Hero.MainHero.StringId);
        json.Append(",\"heroGold\":").Append(Hero.MainHero.Gold);
        json.Append(",\"partyId\":\"").Append(Escape(MobileParty.MainParty.StringId)).Append('"');
        json.Append(",\"partyScreenMode\":\"Normal\"");
        json.Append(",\"timeControlModeBefore\":\"").Append(Escape(beforeMode)).Append('"');
        json.Append(",\"timeControlModeDuring\":\"").Append(Escape(duringMode)).Append('"');
        json.Append(",\"campaignDayBefore\":").Append(beforeDay.ToString("F3", System.Globalization.CultureInfo.InvariantCulture));
        json.Append(",\"options\":[");
        var firstTroop = true;
        try
        {
            var party = MobileParty.MainParty;
            foreach (var troop in viewModel.MainPartyTroops.Where(item => item != null && item.Side == PartyScreenLogic.PartyRosterSide.Right && item.Type == PartyScreenLogic.TroopType.Member && item.IsUpgradableTroop))
            {
                var character = troop.Character;
                var rosterIndex = character == null ? -1 : party.MemberRoster.FindIndexOfTroop(character);
                if (character == null || rosterIndex < 0) continue;
                if (!firstTroop) json.Append(',');
                firstTroop = false;
                json.Append('{');
                Property(json, "troopId", character.StringId, addComma: false);
                Property(json, "troopName", character.Name?.ToString(), true);
                json.Append(",\"currentCount\":").Append(party.MemberRoster.GetElementNumber(rosterIndex));
                json.Append(",\"woundedCount\":").Append(party.MemberRoster.GetElementWoundedNumber(rosterIndex));
                json.Append(",\"currentXp\":").Append(party.MemberRoster.GetElementXp(rosterIndex));
                json.Append(",\"upgradeTargets\":[");
                var firstTarget = true;
                for (var targetIndex = 0; targetIndex < troop.Upgrades.Count && targetIndex < character.UpgradeTargets.Length; targetIndex++)
                {
                    var targetVm = troop.Upgrades[targetIndex];
                    var target = character.UpgradeTargets[targetIndex];
                    if (!firstTarget) json.Append(',');
                    firstTarget = false;
                    json.Append('{').Append("\"targetIndex\":").Append(targetIndex);
                    Property(json, "targetId", target.StringId);
                    Property(json, "targetName", target.Name?.ToString(), true);
                    json.Append(",\"availableCount\":").Append(targetVm.AvailableUpgrades);
                    json.Append(",\"isAvailable\":").Append(Bool(targetVm.IsAvailable));
                    json.Append(",\"isInsufficient\":").Append(Bool(targetVm.IsInsufficient));
                    json.Append(",\"experienceCostPerUnit\":").Append(character.GetUpgradeXpCost(party.Party, targetIndex));
                    json.Append(",\"goldCostPerUnit\":").Append(character.GetUpgradeGoldCost(party.Party, targetIndex));
                    Property(json, "requiredItemCategoryId", target.UpgradeRequiresItemFromCategory?.StringId, true);
                    json.Append(",\"hasItemRequirement\":").Append(Bool(targetVm.Requirements.HasItemRequirement));
                    json.Append(",\"itemRequirementMet\":").Append(Bool(targetVm.Requirements.IsItemRequirementMet));
                    json.Append(",\"hasPerkRequirement\":").Append(Bool(targetVm.Requirements.HasPerkRequirement));
                    json.Append(",\"perkRequirementMet\":").Append(Bool(targetVm.Requirements.IsPerkRequirementMet));
                    json.Append('}');
                }
                json.Append("]}");
            }
        }
        finally
        {
            CancelOpenedPartyScreen(viewModel);
        }
        json.Append("],\"timeControlModeAfter\":\"").Append(Escape(Campaign.Current.TimeControlMode.ToString())).Append('"');
        json.Append(",\"campaignDayAfter\":").Append(CampaignTime.Now.ToDays.ToString("F3", System.Globalization.CultureInfo.InvariantCulture));
        json.Append(",\"returnedToMap\":").Append(Game.Current?.GameStateManager?.ActiveState is MapState ? "true" : "false");
        return json.Append('}').ToString();
    }

    internal static string UpgradeOneTroopJson(string troopId, int upgradeTargetIndex)
    {
        if (string.IsNullOrWhiteSpace(troopId) || upgradeTargetIndex < 0)
            throw new InvalidOperationException("upgradeTroop requires a current troopId and non-negative upgradeTargetIndex");
        var timeModeBefore = Campaign.Current.TimeControlMode.ToString();
        var campaignDayBefore = CampaignTime.Now.ToDays;
        var viewModel = OpenMainPartyScreen();
        try
        {
            var party = MobileParty.MainParty;
            var troop = viewModel.MainPartyTroops.FirstOrDefault(item => item != null && item.Side == PartyScreenLogic.PartyRosterSide.Right && item.Type == PartyScreenLogic.TroopType.Member && item.Character != null && string.Equals(item.Character.StringId, troopId, StringComparison.Ordinal));
            if (troop == null || !troop.IsUpgradableTroop || upgradeTargetIndex >= troop.Upgrades.Count || upgradeTargetIndex >= troop.Character.UpgradeTargets.Length)
                throw new InvalidOperationException("troopId/upgradeTargetIndex is not a current ordinary MainParty upgrade option");
            var upgradeVm = troop.Upgrades[upgradeTargetIndex];
            if (!upgradeVm.IsAvailable || upgradeVm.IsInsufficient || upgradeVm.AvailableUpgrades < 1 || !upgradeVm.Requirements.IsItemRequirementMet || !upgradeVm.Requirements.IsPerkRequirementMet)
                throw new InvalidOperationException("the selected native PartyScreen upgrade target is not currently available");
            if (!viewModel.PartyScreenLogic.IsDoneActive())
                throw new InvalidOperationException("the native PartyScreen Done action is not currently available");

            var sourceCharacter = troop.Character;
            var targetCharacter = sourceCharacter.UpgradeTargets[upgradeTargetIndex];
            var memberIndex = party.MemberRoster.FindIndexOfTroop(sourceCharacter);
            if (memberIndex < 0) throw new InvalidOperationException("the selected troop is no longer in MainParty.MemberRoster");
            var sourceCountBefore = party.MemberRoster.GetElementNumber(memberIndex);
            var sourceWoundedBefore = party.MemberRoster.GetElementWoundedNumber(memberIndex);
            var sourceXpBefore = party.MemberRoster.GetElementXp(memberIndex);
            var targetCountBefore = party.MemberRoster.GetTroopCount(targetCharacter);
            var goldBefore = Hero.MainHero.Gold;
            var xpCost = sourceCharacter.GetUpgradeXpCost(party.Party, upgradeTargetIndex);
            var goldCost = sourceCharacter.GetUpgradeGoldCost(party.Party, upgradeTargetIndex);

            viewModel.ExecuteUpgrade(troop, upgradeTargetIndex, 1);
            viewModel.ExecuteDone();
            if (Game.Current?.GameStateManager?.ActiveState is not MapState)
                throw new InvalidOperationException("PartyScreen did not complete its native Done/close transition");

            var sourceIndexAfter = party.MemberRoster.FindIndexOfTroop(sourceCharacter);
            var sourceCountAfter = sourceIndexAfter < 0 ? 0 : party.MemberRoster.GetElementNumber(sourceIndexAfter);
            var sourceWoundedAfter = sourceIndexAfter < 0 ? 0 : party.MemberRoster.GetElementWoundedNumber(sourceIndexAfter);
            var sourceXpAfter = sourceIndexAfter < 0 ? 0 : party.MemberRoster.GetElementXp(sourceIndexAfter);
            var targetCountAfter = party.MemberRoster.GetTroopCount(targetCharacter);
            var json = new StringBuilder(1024);
            json.Append('{').Append("\"schemaVersion\":1,\"committed\":true");
            Property(json, "troopId", sourceCharacter.StringId);
            Property(json, "targetId", targetCharacter.StringId);
            json.Append(",\"upgradedCount\":1");
            json.Append(",\"sourceCountBefore\":").Append(sourceCountBefore);
            json.Append(",\"sourceCountAfter\":").Append(sourceCountAfter);
            json.Append(",\"sourceWoundedBefore\":").Append(sourceWoundedBefore);
            json.Append(",\"sourceWoundedAfter\":").Append(sourceWoundedAfter);
            json.Append(",\"sourceXpBefore\":").Append(sourceXpBefore);
            json.Append(",\"sourceXpAfter\":").Append(sourceXpAfter);
            json.Append(",\"targetCountBefore\":").Append(targetCountBefore);
            json.Append(",\"targetCountAfter\":").Append(targetCountAfter);
            json.Append(",\"xpCost\":").Append(xpCost);
            json.Append(",\"goldBefore\":").Append(goldBefore);
            json.Append(",\"goldAfter\":").Append(Hero.MainHero.Gold);
            json.Append(",\"goldCost\":").Append(goldCost);
            json.Append(",\"timeControlModeBefore\":\"").Append(Escape(timeModeBefore)).Append('"');
            json.Append(",\"timeControlModeAfter\":\"").Append(Escape(Campaign.Current.TimeControlMode.ToString())).Append('"');
            json.Append(",\"campaignDayBefore\":").Append(campaignDayBefore.ToString("F3", System.Globalization.CultureInfo.InvariantCulture));
            json.Append(",\"campaignDayAfter\":").Append(CampaignTime.Now.ToDays.ToString("F3", System.Globalization.CultureInfo.InvariantCulture));
            return json.Append('}').ToString();
        }
        catch
        {
            CancelActiveNormalPartyScreen();
            throw;
        }
    }

    private static PartyVM OpenMainPartyScreen()
    {
        if (Game.Current == null || Game.Current.CheatMode || Game.Current.GameStateManager?.ActiveState is not MapState || MobileParty.MainParty == null)
            throw new InvalidOperationException("Party upgrade options/actions require a non-cheat Campaign Map state with MainParty");
        PartyScreenHelper.OpenScreenAsNormal();
        var partyState = Game.Current.GameStateManager.ActiveState as PartyState;
        if (partyState == null || partyState.PartyScreenMode != PartyScreenHelper.PartyScreenMode.Normal || partyState.PartyScreenLogic?.RightOwnerParty?.MobileParty != MobileParty.MainParty)
        {
            CancelActiveNormalPartyScreen();
            throw new InvalidOperationException("Native PartyScreen did not open in normal MainParty mode");
        }
        try
        {
            return new PartyVM(partyState.PartyScreenLogic);
        }
        catch
        {
            CancelActiveNormalPartyScreen();
            throw;
        }
    }

    private static void CancelOpenedPartyScreen(PartyVM viewModel)
    {
        if (Game.Current?.GameStateManager?.ActiveState is PartyState partyState && partyState.PartyScreenMode == PartyScreenHelper.PartyScreenMode.Normal)
            PartyScreenHelper.CloseScreen(isForced: false, fromCancel: true);
    }

    private static void CancelActiveNormalPartyScreen()
    {
        if (Game.Current?.GameStateManager?.ActiveState is PartyState partyState && partyState.PartyScreenMode == PartyScreenHelper.PartyScreenMode.Normal)
            PartyScreenHelper.CloseScreen(isForced: false, fromCancel: true);
    }

    private static void Property(StringBuilder json, string key, string value, bool addComma = true)
    {
        if (addComma) json.Append(',');
        json.Append('"').Append(key).Append("\":\"").Append(Escape(value)).Append('"');
    }

    private static string Escape(string value) => (value ?? string.Empty).Replace("\\", "\\\\").Replace("\"", "\\\"");
    private static string Bool(bool value) => value ? "true" : "false";
}
