using System;
using System.Linq;
using System.Text;
using Helpers;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.Actions;
using TaleWorlds.CampaignSystem.GameState;
using TaleWorlds.CampaignSystem.Party;
using TaleWorlds.CampaignSystem.ViewModelCollection.Party;
using TaleWorlds.Core;

namespace ChronicleFramework;

internal static class ChronicleRansomPrisonerSaleAdapter
{
    internal static string TransferOne(string troopId)
    {
        var state = Game.Current?.GameStateManager?.ActiveState as PartyState;
        if (state?.PartyScreenLogic == null || state.PartyScreenMode != PartyScreenHelper.PartyScreenMode.Ransom ||
            state.PartyScreenLogic.RightOwnerParty?.MobileParty != MobileParty.MainParty)
            throw new InvalidOperationException("sellPrisonerOne requires the current Native Ransom PartyState for MainParty");
        if (ChronicleInquiryAdapter.IsInquiryOpen)
            throw new InvalidOperationException("sellPrisonerOne is blocked by an active Native inquiry");
        if (string.IsNullOrWhiteSpace(troopId)) throw new InvalidOperationException("troopId is required");

        var logic = state.PartyScreenLogic;
        const PartyScreenLogic.TroopType troopType = PartyScreenLogic.TroopType.Prisoner;
        var sourceSide = PartyScreenLogic.PartyRosterSide.Right;
        var targetSide = PartyScreenLogic.PartyRosterSide.Left;
        var sourceRoster = logic.GetRoster(sourceSide, troopType);
        var targetRoster = logic.GetRoster(targetSide, troopType);
        var sourceElement = sourceRoster.GetTroopRoster().FirstOrDefault(element => element.Character != null &&
            element.Number > 0 && string.Equals(element.Character.StringId, troopId, StringComparison.Ordinal));
        var sourceCharacter = sourceElement.Character;
        if (sourceCharacter == null)
            throw new InvalidOperationException("troopId is not a current Native MainParty prisoner row in the Ransom screen");
        if (!logic.IsTroopTransferable(troopType, sourceCharacter, (int)sourceSide))
            throw new InvalidOperationException("The current Native Ransom screen does not allow this prisoner to be sold");

        var viewModel = ChroniclePartyScreenAdapter.AttachToActivePartyScreen(state);
        try
        {
            var row = viewModel.MainPartyPrisoners?.FirstOrDefault(candidate => candidate != null &&
                candidate.Side == sourceSide && candidate.Type == troopType && candidate.Character != null &&
                string.Equals(candidate.Character.StringId, troopId, StringComparison.Ordinal));
            if (row == null || !row.IsTroopTransferrable || row.Number < 1)
                throw new InvalidOperationException("troopId is not a currently visible, transferable Native MainParty prisoner row");

            var sourceBefore = sourceRoster.GetTroopCount(sourceCharacter);
            var saleBefore = targetRoster.GetTroopCount(sourceCharacter);
            var goldBefore = Hero.MainHero?.Gold ?? 0;
            var goldChangeBefore = logic.CurrentData.PartyGoldChangeAmount;
            row.ExecuteTransferSingle();

            sourceRoster = logic.GetRoster(sourceSide, troopType);
            targetRoster = logic.GetRoster(targetSide, troopType);
            var sourceAfter = sourceRoster.GetTroopCount(sourceCharacter);
            var saleAfter = targetRoster.GetTroopCount(sourceCharacter);
            var goldChangeAfter = logic.CurrentData.PartyGoldChangeAmount;
            if (sourceAfter != sourceBefore - 1 || saleAfter != saleBefore + 1)
                throw new InvalidOperationException("Native PartyCharacterVM.ExecuteTransferSingle did not move exactly one prisoner into the sale roster");

            var receipt = new StringBuilder(512);
            receipt.Append("{\"schemaVersion\":1,\"transferredCount\":1");
            Property(receipt, "troopId", sourceCharacter.StringId);
            Property(receipt, "nativeHandler", "PartyCharacterVM.ExecuteTransferSingle");
            receipt.Append(",\"sourceCountBefore\":").Append(sourceBefore)
                .Append(",\"sourceCountAfter\":").Append(sourceAfter)
                .Append(",\"saleCountBefore\":").Append(saleBefore)
                .Append(",\"saleCountAfter\":").Append(saleAfter)
                .Append(",\"goldBefore\":").Append(goldBefore)
                .Append(",\"nativeGoldChangeBefore\":").Append(goldChangeBefore)
                .Append(",\"nativeGoldChangeAfter\":").Append(goldChangeAfter)
                .Append(",\"doneAvailableAfter\":").Append(logic.IsDoneActive() ? "true" : "false")
                .Append('}');
            return receipt.ToString();
        }
        finally
        {
            ChroniclePartyScreenAdapter.Finalize(viewModel);
        }
    }

    internal static string Done()
    {
        var state = Game.Current?.GameStateManager?.ActiveState as PartyState;
        if (state?.PartyScreenLogic == null || state.PartyScreenMode != PartyScreenHelper.PartyScreenMode.Ransom ||
            state.PartyScreenLogic.RightOwnerParty?.MobileParty != MobileParty.MainParty)
            throw new InvalidOperationException("Ransom Done requires the current Native Ransom PartyState for MainParty");
        if (ChronicleInquiryAdapter.IsInquiryOpen)
            throw new InvalidOperationException("Ransom Done is blocked by an active Native inquiry");
        var logic = state.PartyScreenLogic;
        if (!logic.IsDoneActive()) throw new InvalidOperationException("Native Ransom PartyScreen Done is unavailable");
        var handler = state.Handler as IPartyScreenPrisonHandler;
        if (handler == null) throw new InvalidOperationException("Native Ransom PartyScreen Done handler is unavailable");

        var goldBefore = Hero.MainHero?.Gold ?? 0;
        var prisonerCountBefore = MobileParty.MainParty.PrisonRoster.TotalManCount;
        var dayBefore = CampaignTime.Now.ToDays;
        var modeBefore = Campaign.Current?.TimeControlMode.ToString() ?? string.Empty;
        var selectedCount = logic.GetRoster(PartyScreenLogic.PartyRosterSide.Left, PartyScreenLogic.TroopType.Prisoner).TotalManCount;
        var draftGoldChange = logic.CurrentData.PartyGoldChangeAmount;
        if (selectedCount <= 0 || draftGoldChange == 0)
            throw new InvalidOperationException("Ransom Done requires at least one currently selected prisoner and a non-zero Native price draft");

        handler.ExecuteDoneScript();

        var goldAfter = Hero.MainHero?.Gold ?? 0;
        var prisonerCountAfter = MobileParty.MainParty.PrisonRoster.TotalManCount;
        var dayAfter = CampaignTime.Now.ToDays;
        var modeAfter = Campaign.Current?.TimeControlMode.ToString() ?? string.Empty;
        var stateAfter = Game.Current?.GameStateManager?.ActiveState;
        var nativeTransaction = goldAfter - goldBefore;
        var nativeSoldCount = prisonerCountBefore - prisonerCountAfter;
        var passed = nativeTransaction > 0 && nativeSoldCount == selectedCount &&
            Math.Abs(dayAfter - dayBefore) <= 0.000001 && modeBefore == modeAfter && stateAfter != state;

        return "{\"schemaVersion\":1,\"postconditionPassed\":" + (passed ? "true" : "false") +
            ",\"nativeHandler\":\"IPartyScreenPrisonHandler.ExecuteDoneScript\"" +
            ",\"selectedCount\":" + selectedCount +
            ",\"playerGoldBefore\":" + goldBefore +
            ",\"playerGoldAfter\":" + goldAfter +
            ",\"nativeTransactionAmount\":" + nativeTransaction +
            ",\"prisonerCountBefore\":" + prisonerCountBefore +
            ",\"prisonerCountAfter\":" + prisonerCountAfter +
            ",\"timeControlModeBefore\":\"" + modeBefore + "\",\"timeControlModeAfter\":\"" + modeAfter + "\"" +
            ",\"campaignDayBefore\":" + dayBefore.ToString("R", System.Globalization.CultureInfo.InvariantCulture) +
            ",\"campaignDayAfter\":" + dayAfter.ToString("R", System.Globalization.CultureInfo.InvariantCulture) +
            ",\"partyScreenClosed\":" + (stateAfter != state ? "true" : "false") + "}";
    }

    internal static string Cancel()
    {
        var state = Game.Current?.GameStateManager?.ActiveState as PartyState;
        if (state?.PartyScreenLogic == null || state.PartyScreenMode != PartyScreenHelper.PartyScreenMode.Ransom ||
            state.PartyScreenLogic.RightOwnerParty?.MobileParty != MobileParty.MainParty)
            throw new InvalidOperationException("Ransom Cancel requires the current Native Ransom PartyState for MainParty");
        if (ChronicleInquiryAdapter.IsInquiryOpen)
            throw new InvalidOperationException("Ransom Cancel is blocked by an active Native inquiry");
        var logic = state.PartyScreenLogic;
        if (!logic.IsCancelActive()) throw new InvalidOperationException("Native Ransom PartyScreen Cancel is unavailable");

        var goldBefore = Hero.MainHero?.Gold ?? 0;
        var prisonerCountBefore = MobileParty.MainParty.PrisonRoster.TotalManCount;
        var selectedCount = logic.GetRoster(PartyScreenLogic.PartyRosterSide.Left, PartyScreenLogic.TroopType.Prisoner).TotalManCount;
        var draftGoldChange = logic.CurrentData.PartyGoldChangeAmount;
        var dayBefore = CampaignTime.Now.ToDays;
        var modeBefore = Campaign.Current?.TimeControlMode.ToString() ?? string.Empty;
        var viewModel = ChroniclePartyScreenAdapter.AttachToActivePartyScreen(state);
        try
        {
            // Native party screens use this same VM command for their visible Cancel control.
            // In Ransom mode ExecuteCancel(false) resets the draft and closes without a query.
            viewModel.ExecuteCancelWithoutInquiry();
        }
        finally
        {
            ChroniclePartyScreenAdapter.Finalize(viewModel);
        }

        var goldAfter = Hero.MainHero?.Gold ?? 0;
        var prisonerCountAfter = MobileParty.MainParty.PrisonRoster.TotalManCount;
        var dayAfter = CampaignTime.Now.ToDays;
        var modeAfter = Campaign.Current?.TimeControlMode.ToString() ?? string.Empty;
        var stateAfter = Game.Current?.GameStateManager?.ActiveState;
        var closed = stateAfter != state;
        var passed = closed && goldAfter == goldBefore && prisonerCountAfter == prisonerCountBefore &&
            Math.Abs(dayAfter - dayBefore) <= 0.000001 && modeBefore == modeAfter;

        return "{\"schemaVersion\":1,\"postconditionPassed\":" + (passed ? "true" : "false") +
            ",\"nativeHandler\":\"PartyVM.ExecuteCancelWithoutInquiry->ExecuteCancel(false)\"" +
            ",\"selectedCountDiscarded\":" + selectedCount +
            ",\"nativeGoldChangeDiscarded\":" + draftGoldChange.ToString(System.Globalization.CultureInfo.InvariantCulture) +
            ",\"playerGoldBefore\":" + goldBefore + ",\"playerGoldAfter\":" + goldAfter +
            ",\"prisonerCountBefore\":" + prisonerCountBefore + ",\"prisonerCountAfter\":" + prisonerCountAfter +
            ",\"timeControlModeBefore\":\"" + modeBefore + "\",\"timeControlModeAfter\":\"" + modeAfter + "\"" +
            ",\"campaignDayBefore\":" + dayBefore.ToString("R", System.Globalization.CultureInfo.InvariantCulture) +
            ",\"campaignDayAfter\":" + dayAfter.ToString("R", System.Globalization.CultureInfo.InvariantCulture) +
            ",\"partyScreenClosed\":" + (closed ? "true" : "false") + "}";
    }

    private static void Property(StringBuilder builder, string name, string value)
    {
        builder.Append(",\"").Append(name).Append("\":\"").Append((value ?? string.Empty)
            .Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\r", "\\r").Replace("\n", "\\n")).Append('"');
    }
}
