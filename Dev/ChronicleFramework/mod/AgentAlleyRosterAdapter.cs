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

internal static class ChronicleAlleyRosterAdapter
{
    internal static bool IsCurrentNativeAlleyPartyScreen()
    {
        var partyState = Game.Current?.GameStateManager?.ActiveState as PartyState;
        return partyState?.PartyScreenLogic != null &&
            partyState.PartyScreenMode == PartyScreenHelper.PartyScreenMode.TroopsManage &&
            Campaign.Current?.CurrentMenuContext?.GameMenu?.StringId == "manage_alley" &&
            MobileParty.MainParty != null &&
            partyState.PartyScreenLogic.RightOwnerParty?.MobileParty == MobileParty.MainParty;
    }

    internal static string TransferOne(string troopId, string sourceSideName)
    {
        if (!IsCurrentNativeAlleyPartyScreen())
            throw new InvalidOperationException("alleyRosterTransfer requires the Native manage_alley TroopsManage PartyScreen");
        if (ChronicleInquiryAdapter.IsInquiryOpen)
            throw new InvalidOperationException("alleyRosterTransfer is blocked by an active Native inquiry");
        if (string.IsNullOrWhiteSpace(troopId)) throw new InvalidOperationException("troopId is required");

        var fromAlley = string.Equals(sourceSideName, "alley", StringComparison.Ordinal);
        var fromMainParty = string.Equals(sourceSideName, "mainParty", StringComparison.Ordinal);
        if (!fromAlley && !fromMainParty) throw new InvalidOperationException("sourceSide must be alley or mainParty");

        var state = (PartyState)Game.Current.GameStateManager.ActiveState;
        var logic = state.PartyScreenLogic;
        var side = fromAlley ? PartyScreenLogic.PartyRosterSide.Left : PartyScreenLogic.PartyRosterSide.Right;
        var sourceRoster = logic.GetRoster(side, PartyScreenLogic.TroopType.Member);
        var targetRoster = logic.GetRoster(fromAlley ? PartyScreenLogic.PartyRosterSide.Right : PartyScreenLogic.PartyRosterSide.Left, PartyScreenLogic.TroopType.Member);
        var sourceElement = sourceRoster.GetTroopRoster().FirstOrDefault(element => element.Character != null &&
            !element.Character.IsHero && element.Number > 0 && string.Equals(element.Character.StringId, troopId, StringComparison.Ordinal));
        var sourceCharacter = sourceElement.Character;
        if (sourceCharacter == null) throw new InvalidOperationException("troopId is not a current ordinary member on the requested PartyScreen side");
        if (!logic.IsTroopTransferable(PartyScreenLogic.TroopType.Member, sourceCharacter, (int)side))
            throw new InvalidOperationException("The current Native PartyScreen does not allow this troop to transfer from that side");

        var viewModel = ChroniclePartyScreenAdapter.AttachToActivePartyScreen(state);
        try
        {
            var displayedRoster = fromAlley ? viewModel.OtherPartyTroops : viewModel.MainPartyTroops;
            var row = displayedRoster.FirstOrDefault(candidate => candidate != null &&
                candidate.Side == side && candidate.Type == PartyScreenLogic.TroopType.Member &&
                candidate.Character != null && string.Equals(candidate.Character.StringId, troopId, StringComparison.Ordinal));
            if (row == null || !row.IsTroopTransferrable || row.IsHero || row.Number < 1)
                throw new InvalidOperationException("troopId is not a currently visible, transferable ordinary troop row");

            var sourceBefore = sourceRoster.GetTroopCount(sourceCharacter);
            var targetBefore = targetRoster.GetTroopCount(sourceCharacter);
            row.ExecuteTransferSingle();
            var sourceAfter = logic.GetRoster(side, PartyScreenLogic.TroopType.Member).GetTroopCount(sourceCharacter);
            var targetSide = fromAlley ? PartyScreenLogic.PartyRosterSide.Right : PartyScreenLogic.PartyRosterSide.Left;
            var targetAfter = logic.GetRoster(targetSide, PartyScreenLogic.TroopType.Member).GetTroopCount(sourceCharacter);
            if (sourceAfter != sourceBefore - 1 || targetAfter != targetBefore + 1)
                throw new InvalidOperationException("Native PartyCharacterVM transfer button did not move exactly one troop");

            var json = new StringBuilder(512);
            json.Append("{\"schemaVersion\":1,\"transferredCount\":1");
            Property(json, "troopId", sourceCharacter.StringId);
            Property(json, "sourceSide", sourceSideName);
            json.Append(",\"sourceBefore\":").Append(sourceBefore);
            json.Append(",\"sourceAfter\":").Append(sourceAfter);
            json.Append(",\"targetBefore\":").Append(targetBefore);
            json.Append(",\"targetAfter\":").Append(targetAfter);
            json.Append(",\"nativeHandler\":\"PartyCharacterVM.ExecuteTransferSingle\"}");
            return json.ToString();
        }
        finally
        {
            ChroniclePartyScreenAdapter.Finalize(viewModel);
        }
    }

    internal static string Done()
    {
        if (!IsCurrentNativeAlleyPartyScreen())
            throw new InvalidOperationException("partyScreenDone requires the Native manage_alley TroopsManage PartyScreen");
        var state = (PartyState)Game.Current.GameStateManager.ActiveState;
        if (!state.PartyScreenLogic.IsDoneActive())
            throw new InvalidOperationException("the Native Alley PartyScreen Done action is unavailable under current roster/model conditions");
        var viewModel = ChroniclePartyScreenAdapter.AttachToActivePartyScreen(state);
        try
        {
            viewModel.ExecuteDone();
            if (ReferenceEquals(Game.Current?.GameStateManager?.ActiveState, state))
                throw new InvalidOperationException("The Native Alley PartyScreen Done handler did not close the current screen");
            return "{\"schemaVersion\":1,\"choice\":\"done\",\"nativeHandler\":\"PartyVM.ExecuteDone\"}";
        }
        finally
        {
            ChroniclePartyScreenAdapter.Finalize(viewModel);
        }
    }

    internal static string Cancel()
    {
        if (!IsCurrentNativeAlleyPartyScreen())
            throw new InvalidOperationException("alleyRosterCancel requires the Native manage_alley TroopsManage PartyScreen");
        var state = (PartyState)Game.Current.GameStateManager.ActiveState;
        var viewModel = ChroniclePartyScreenAdapter.AttachToActivePartyScreen(state);
        try
        {
            viewModel.ExecuteCancelWithoutInquiry();
            if (ReferenceEquals(Game.Current?.GameStateManager?.ActiveState, state))
                throw new InvalidOperationException("The Native Alley PartyScreen Cancel handler did not close the current screen");
            return "{\"schemaVersion\":1,\"choice\":\"cancel\",\"nativeHandler\":\"PartyVM.ExecuteCancelWithoutInquiry\"}";
        }
        finally
        {
            ChroniclePartyScreenAdapter.Finalize(viewModel);
        }
    }

    private static void Property(StringBuilder json, string name, string value)
    {
        json.Append(",\"").Append(name).Append("\":\"").Append(Escape(value)).Append('"');
    }

    private static string Escape(string value) => (value ?? string.Empty).Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\r", "\\r").Replace("\n", "\\n");
}
