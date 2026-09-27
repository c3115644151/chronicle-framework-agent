using System;
using System.Linq;
using System.Text;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.GameState;
using TaleWorlds.CampaignSystem.Party;
using TaleWorlds.CampaignSystem.ViewModelCollection.Party;
using TaleWorlds.Core;
using TaleWorlds.Localization;

namespace ChronicleFramework;

internal static class ChroniclePartyPrisonerRecruitmentAdapter
{
    internal static string BuildOptionsJson()
    {
        var beforeMode = Campaign.Current.TimeControlMode.ToString();
        var beforeDay = CampaignTime.Now.ToDays;
        var party = MobileParty.MainParty;
        var viewModel = ChroniclePartyScreenAdapter.OpenMainPartyNormal();
        try
        {
            var json = new StringBuilder(4096);
            json.Append('{').Append("\"schemaVersion\":1");
            ChroniclePartyUpgradeAdapter.Property(json, "heroId", Hero.MainHero.StringId);
            json.Append(",\"partyId\":\"").Append(ChroniclePartyUpgradeAdapter.Escape(party.StringId)).Append('"');
            json.Append(",\"partyScreenMode\":\"Normal\"");
            json.Append(",\"partySizeLimit\":").Append(party.Party.PartySizeLimit);
            json.Append(",\"memberCount\":").Append(party.MemberRoster.TotalManCount);
            var requiresDoneConfirmation = party.MemberRoster.TotalManCount + 1 > party.Party.PartySizeLimit;
            json.Append(",\"nativeDoneConfirmationRequiredForOne\":").Append(ChroniclePartyUpgradeAdapter.Bool(requiresDoneConfirmation));
            if (requiresDoneConfirmation)
            {
                ChroniclePartyUpgradeAdapter.Property(json, "nativeDoneConfirmationTitle", new TextObject("{=uJro3Bua}Over Limit").ToString());
                ChroniclePartyUpgradeAdapter.Property(json, "nativeDoneConfirmationText", GameTexts.FindText("str_party_over_limit_troops").ToString());
            }
            json.Append(",\"timeControlModeBefore\":\"").Append(ChroniclePartyUpgradeAdapter.Escape(beforeMode)).Append('"');
            json.Append(",\"timeControlModeDuring\":\"").Append(ChroniclePartyUpgradeAdapter.Escape(Campaign.Current.TimeControlMode.ToString())).Append('"');
            json.Append(",\"campaignDayBefore\":").Append(beforeDay.ToString("F3", System.Globalization.CultureInfo.InvariantCulture));
            json.Append(",\"options\":[");
            var first = true;
            foreach (var troop in viewModel.MainPartyPrisoners.Where(item => item != null && item.Side == PartyScreenLogic.PartyRosterSide.Right && item.Type == PartyScreenLogic.TroopType.Prisoner && item.Character != null && !item.Character.IsHero))
            {
                var rosterIndex = party.PrisonRoster.FindIndexOfTroop(troop.Character);
                if (rosterIndex < 0) continue;
                var character = troop.Character;
                var conformityNeeded = Campaign.Current.Models.PrisonerRecruitmentCalculationModel.GetConformityNeededToRecruitPrisoner(character);
                var availableCount = viewModel.PartyScreenLogic.GetTroopRecruitableAmount(character);
                var isAvailable = troop.IsTroopRecruitable && availableCount > 0;
                var reason = viewModel.PartyScreenLogic.GetRecruitableReasonString(character, troop.IsTroopRecruitable, party.PrisonRoster.GetElementNumber(rosterIndex), out var showStackModifier);
                var moraleEffect = Campaign.Current.Models.PrisonerRecruitmentCalculationModel.GetPrisonerRecruitmentMoraleEffect(party.Party, character, 1);
                if (!first) json.Append(',');
                first = false;
                json.Append('{');
                ChroniclePartyUpgradeAdapter.Property(json, "troopId", character.StringId, addComma: false);
                ChroniclePartyUpgradeAdapter.Property(json, "troopName", character.Name?.ToString());
                ChroniclePartyUpgradeAdapter.Property(json, "cultureId", character.Culture?.StringId);
                json.Append(",\"tier\":").Append(character.Tier);
                json.Append(",\"currentCount\":").Append(party.PrisonRoster.GetElementNumber(rosterIndex));
                json.Append(",\"currentConformityXp\":").Append(party.PrisonRoster.GetElementXp(rosterIndex));
                json.Append(",\"conformityXpPerRecruit\":").Append(conformityNeeded);
                json.Append(",\"availableCount\":").Append(availableCount);
                json.Append(",\"isAvailable\":").Append(ChroniclePartyUpgradeAdapter.Bool(isAvailable));
                json.Append(",\"partySizeWarning\":").Append(ChroniclePartyUpgradeAdapter.Bool(party.Party.PartySizeLimit <= party.MemberRoster.TotalManCount));
                json.Append(",\"showStackModifier\":").Append(ChroniclePartyUpgradeAdapter.Bool(showStackModifier));
                ChroniclePartyUpgradeAdapter.Property(json, "nativeRecruitReason", reason, true);
                json.Append(",\"moraleEffectPerRecruit\":").Append(moraleEffect);
                json.Append('}');
            }
            json.Append("],\"timeControlModeAfter\":\"").Append(ChroniclePartyUpgradeAdapter.Escape(Campaign.Current.TimeControlMode.ToString())).Append('"');
            json.Append(",\"campaignDayAfter\":").Append(CampaignTime.Now.ToDays.ToString("F3", System.Globalization.CultureInfo.InvariantCulture));
            json.Append(",\"returnedToMap\":").Append(Game.Current?.GameStateManager?.ActiveState is MapState ? "true" : "false");
            return json.Append('}').ToString();
        }
        finally
        {
            ChroniclePartyScreenAdapter.CancelAndFinalize(viewModel);
        }
    }

    internal static string RecruitOneJson(string troopId, bool confirmPartySizeWarning)
    {
        if (string.IsNullOrWhiteSpace(troopId))
            throw new InvalidOperationException("recruitPrisoner requires a current ordinary MainParty prisonerId");
        var timeModeBefore = Campaign.Current.TimeControlMode.ToString();
        var campaignDayBefore = CampaignTime.Now.ToDays;
        var party = MobileParty.MainParty;
        var viewModel = ChroniclePartyScreenAdapter.OpenMainPartyNormal();
        try
        {
            var prisoner = viewModel.MainPartyPrisoners.FirstOrDefault(item => item != null && item.Side == PartyScreenLogic.PartyRosterSide.Right && item.Type == PartyScreenLogic.TroopType.Prisoner && item.Character != null && !item.Character.IsHero && string.Equals(item.Character.StringId, troopId, StringComparison.Ordinal));
            if (prisoner == null || !prisoner.IsTroopRecruitable || prisoner.NumOfRecruitablePrisoners < 1)
                throw new InvalidOperationException("the selected ordinary MainParty prisoner is not currently recruitable by the native PartyScreen VM");
            if (!viewModel.PartyScreenLogic.IsDoneActive())
                throw new InvalidOperationException("the native PartyScreen Done action is not currently available");

            var character = prisoner.Character;
            var rosterIndexBefore = party.PrisonRoster.FindIndexOfTroop(character);
            if (rosterIndexBefore < 0) throw new InvalidOperationException("the selected prisoner is no longer in MainParty.PrisonRoster");
            var prisonerCountBefore = party.PrisonRoster.GetElementNumber(rosterIndexBefore);
            var prisonerXpBefore = party.PrisonRoster.GetElementXp(rosterIndexBefore);
            var memberCountBefore = party.MemberRoster.GetTroopCount(character);
            var memberTotalBefore = party.MemberRoster.TotalManCount;
            var goldBefore = Hero.MainHero.Gold;
            var moraleBefore = party.RecentEventsMorale;
            var conformityCost = Campaign.Current.Models.PrisonerRecruitmentCalculationModel.GetConformityNeededToRecruitPrisoner(character);
            var expectedMoraleEffect = Campaign.Current.Models.PrisonerRecruitmentCalculationModel.GetPrisonerRecruitmentMoraleEffect(party.Party, character, 1);

            prisoner.ExecuteRecruitTroop();
            var stagedHistory = viewModel.PartyScreenLogic.CurrentData.RecruitedPrisonersHistory.FirstOrDefault(entry => entry.Item1 == character);
            var stagedRecruitCount = stagedHistory == null ? 0 : stagedHistory.Item2;
            if (stagedRecruitCount != 1)
                throw new InvalidOperationException("the native PartyVM did not stage exactly one prisoner recruitment");
            if (viewModel.IsMainTroopsLimitWarningEnabled && !confirmPartySizeWarning)
                throw new InvalidOperationException("the native PartyScreen requires confirmation because recruiting this prisoner exceeds the MainParty size limit; observe nativeDoneConfirmationText and retry with confirmPartySizeWarning=true only if accepted");
            var moralePreview = viewModel.PartyScreenLogic.CurrentData.PartyMoraleChangeAmount;
            var nativeLimitConfirmation = ChroniclePartyScreenAdapter.ExecuteDoneAndConfirmNativeOverLimit(viewModel, confirmPartySizeWarning);
            if (Game.Current?.GameStateManager?.ActiveState is not MapState)
                throw new InvalidOperationException("PartyScreen did not complete its native Done/close transition");

            var prisonerIndexAfter = party.PrisonRoster.FindIndexOfTroop(character);
            var prisonerCountAfter = prisonerIndexAfter < 0 ? 0 : party.PrisonRoster.GetElementNumber(prisonerIndexAfter);
            var prisonerXpAfter = prisonerIndexAfter < 0 ? 0 : party.PrisonRoster.GetElementXp(prisonerIndexAfter);
            var json = new StringBuilder(1200);
            json.Append('{').Append("\"schemaVersion\":1,\"committed\":true");
            ChroniclePartyUpgradeAdapter.Property(json, "troopId", character.StringId);
            json.Append(",\"recruitedCount\":1");
            json.Append(",\"prisonerCountBefore\":").Append(prisonerCountBefore);
            json.Append(",\"prisonerCountAfter\":").Append(prisonerCountAfter);
            json.Append(",\"prisonerConformityXpBefore\":").Append(prisonerXpBefore);
            json.Append(",\"prisonerConformityXpAfter\":").Append(prisonerXpAfter);
            json.Append(",\"conformityXpCost\":").Append(conformityCost);
            json.Append(",\"memberCountBefore\":").Append(memberCountBefore);
            json.Append(",\"memberCountAfter\":").Append(party.MemberRoster.GetTroopCount(character));
            json.Append(",\"memberTotalBefore\":").Append(memberTotalBefore);
            json.Append(",\"memberTotalAfter\":").Append(party.MemberRoster.TotalManCount);
            json.Append(",\"partySizeLimit\":").Append(party.Party.PartySizeLimit);
            json.Append(",\"partySizeWarningBefore\":").Append(ChroniclePartyUpgradeAdapter.Bool(memberTotalBefore >= party.Party.PartySizeLimit));
            json.Append(",\"nativeLimitConfirmationAccepted\":").Append(ChroniclePartyUpgradeAdapter.Bool(nativeLimitConfirmation != null));
            ChroniclePartyUpgradeAdapter.Property(json, "nativeConfirmationTitle", nativeLimitConfirmation?.TitleText);
            ChroniclePartyUpgradeAdapter.Property(json, "nativeConfirmationText", nativeLimitConfirmation?.Text);
            json.Append(",\"nativeMoralePreviewDelta\":").Append(moralePreview);
            json.Append(",\"recentEventsMoraleBefore\":").Append(moraleBefore.ToString("R", System.Globalization.CultureInfo.InvariantCulture));
            json.Append(",\"recentEventsMoraleAfter\":").Append(party.RecentEventsMorale.ToString("R", System.Globalization.CultureInfo.InvariantCulture));
            json.Append(",\"expectedRecentEventsMoraleDelta\":").Append(expectedMoraleEffect);
            json.Append(",\"goldBefore\":").Append(goldBefore);
            json.Append(",\"goldAfter\":").Append(Hero.MainHero.Gold);
            json.Append(",\"timeControlModeBefore\":\"").Append(ChroniclePartyUpgradeAdapter.Escape(timeModeBefore)).Append('"');
            json.Append(",\"timeControlModeAfter\":\"").Append(ChroniclePartyUpgradeAdapter.Escape(Campaign.Current.TimeControlMode.ToString())).Append('"');
            json.Append(",\"campaignDayBefore\":").Append(campaignDayBefore.ToString("F3", System.Globalization.CultureInfo.InvariantCulture));
            json.Append(",\"campaignDayAfter\":").Append(CampaignTime.Now.ToDays.ToString("F3", System.Globalization.CultureInfo.InvariantCulture));
            return json.Append('}').ToString();
        }
        catch
        {
            ChroniclePartyScreenAdapter.CancelDraftAndClose(viewModel);
            throw;
        }
        finally
        {
            ChroniclePartyScreenAdapter.Finalize(viewModel);
        }
    }
}
