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

internal static class ChronicleQuestTroopScreenAdapter
{
    internal static bool IsCurrentNativeQuestTroopScreen()
    {
        var state = Game.Current?.GameStateManager?.ActiveState as PartyState;
        return state?.PartyScreenLogic != null &&
            state.PartyScreenMode == PartyScreenHelper.PartyScreenMode.QuestTroopManage &&
            state.PartyScreenLogic.RightOwnerParty?.MobileParty == MobileParty.MainParty;
    }

    internal static string TransferOne(string troopId, string sourceSideName)
    {
        if (!IsCurrentNativeQuestTroopScreen())
            throw new InvalidOperationException("questTroopTransfer requires the current Native QuestTroopManage PartyScreen for MainParty");
        if (ChronicleInquiryAdapter.IsInquiryOpen)
            throw new InvalidOperationException("questTroopTransfer is blocked by an active Native inquiry");
        if (string.IsNullOrWhiteSpace(troopId)) throw new InvalidOperationException("troopId is required");

        var fromQuest = string.Equals(sourceSideName, "quest", StringComparison.Ordinal);
        var fromMainParty = string.Equals(sourceSideName, "mainParty", StringComparison.Ordinal);
        if (!fromQuest && !fromMainParty) throw new InvalidOperationException("sourceSide must be quest or mainParty");

        var state = (PartyState)Game.Current.GameStateManager.ActiveState;
        var logic = state.PartyScreenLogic;
        var sourceSide = fromQuest ? PartyScreenLogic.PartyRosterSide.Left : PartyScreenLogic.PartyRosterSide.Right;
        var targetSide = fromQuest ? PartyScreenLogic.PartyRosterSide.Right : PartyScreenLogic.PartyRosterSide.Left;
        var sourceRoster = logic.GetRoster(sourceSide, PartyScreenLogic.TroopType.Member);
        var targetRoster = logic.GetRoster(targetSide, PartyScreenLogic.TroopType.Member);
        var sourceElement = sourceRoster.GetTroopRoster().FirstOrDefault(element => element.Character != null &&
            element.Number > 0 && !element.Character.IsHero &&
            string.Equals(element.Character.StringId, troopId, StringComparison.Ordinal));
        var sourceCharacter = sourceElement.Character;
        if (sourceCharacter == null)
            throw new InvalidOperationException("troopId is not a current ordinary member on the requested QuestTroopManage roster side");
        if (!logic.IsTroopTransferable(PartyScreenLogic.TroopType.Member, sourceCharacter, (int)sourceSide))
            throw new InvalidOperationException("The current Native QuestTroopManage PartyScreen does not allow this troop to transfer from that side");
        if (!fromQuest && targetRoster.TotalManCount >= logic.LeftPartyMembersSizeLimit)
            throw new InvalidOperationException("The Native quest roster already meets its current left-side troop limit");

        var viewModel = ChroniclePartyScreenAdapter.AttachToActivePartyScreen(state);
        try
        {
            var displayedRoster = fromQuest ? viewModel.OtherPartyTroops : viewModel.MainPartyTroops;
            var row = displayedRoster.FirstOrDefault(candidate => candidate != null &&
                candidate.Side == sourceSide && candidate.Type == PartyScreenLogic.TroopType.Member &&
                candidate.Character != null && string.Equals(candidate.Character.StringId, troopId, StringComparison.Ordinal));
            if (row == null || !row.IsTroopTransferrable || row.IsHero || row.Number < 1)
                throw new InvalidOperationException("troopId is not a currently visible, transferable ordinary troop row");

            var sourceBefore = sourceRoster.GetTroopCount(sourceCharacter);
            var targetBefore = targetRoster.GetTroopCount(sourceCharacter);
            var progressBefore = logic.GetCurrentQuestCurrentCount(includePrisoners: false, includeMembers: true);
            var required = logic.GetCurrentQuestRequiredCount();
            row.ExecuteTransferSingle();

            sourceRoster = logic.GetRoster(sourceSide, PartyScreenLogic.TroopType.Member);
            targetRoster = logic.GetRoster(targetSide, PartyScreenLogic.TroopType.Member);
            var sourceAfter = sourceRoster.GetTroopCount(sourceCharacter);
            var targetAfter = targetRoster.GetTroopCount(sourceCharacter);
            var progressAfter = logic.GetCurrentQuestCurrentCount(includePrisoners: false, includeMembers: true);
            if (sourceAfter != sourceBefore - 1 || targetAfter != targetBefore + 1 || progressAfter != progressBefore + (fromQuest ? -1 : 1))
                throw new InvalidOperationException("Native PartyCharacterVM.ExecuteTransferSingle did not move exactly one current quest troop");

            var receipt = new StringBuilder(512);
            receipt.Append("{\"schemaVersion\":1");
            Property(receipt, "action", "Native PartyCharacterVM.ExecuteTransferSingle");
            Property(receipt, "troopId", sourceCharacter.StringId);
            Property(receipt, "sourceSide", sourceSideName);
            receipt.Append(",\"transferredCount\":1")
                .Append(",\"sourceCountBefore\":").Append(sourceBefore)
                .Append(",\"sourceCountAfter\":").Append(sourceAfter)
                .Append(",\"targetCountBefore\":").Append(targetBefore)
                .Append(",\"targetCountAfter\":").Append(targetAfter)
                .Append(",\"questProgressBefore\":").Append(progressBefore)
                .Append(",\"questProgressAfter\":").Append(progressAfter)
                .Append(",\"questProgressRequired\":").Append(required)
                .Append(",\"doneAvailableAfter\":").Append(logic.IsDoneActive() ? "true" : "false");
            Property(receipt, "doneReasonAfter", logic.DoneReasonString);
            receipt.Append('}');
            return receipt.ToString();
        }
        finally
        {
            ChroniclePartyScreenAdapter.Finalize(viewModel);
        }
    }

    internal static string Done()
    {
        if (!IsCurrentNativeQuestTroopScreen())
            throw new InvalidOperationException("questTroopScreenDone requires the current Native QuestTroopManage PartyScreen");
        var state = (PartyState)Game.Current.GameStateManager.ActiveState;
        var logic = state.PartyScreenLogic;
        var progress = logic.GetCurrentQuestCurrentCount(includePrisoners: false, includeMembers: true);
        var required = logic.GetCurrentQuestRequiredCount();
        if (!logic.IsDoneActive())
            throw new InvalidOperationException("Native QuestTroopManage Done is disabled: progress=" + progress + "/" + required + "; reason=" + (logic.DoneReasonString ?? string.Empty));

        var viewModel = ChroniclePartyScreenAdapter.AttachToActivePartyScreen(state);
        try
        {
            viewModel.ExecuteDone();
            var stillActive = ReferenceEquals(Game.Current?.GameStateManager?.ActiveState, state);
            if (stillActive)
                throw new InvalidOperationException("Native QuestTroopManage PartyVM.ExecuteDone did not leave the assignment screen");
            return "{\"schemaVersion\":1,\"action\":\"Native PartyVM.ExecuteDone\",\"questProgress\":" + progress +
                ",\"questProgressRequired\":" + required + ",\"screenClosed\":true}";
        }
        finally
        {
            ChroniclePartyScreenAdapter.Finalize(viewModel);
        }
    }

    internal static string Cancel()
    {
        if (!IsCurrentNativeQuestTroopScreen())
            throw new InvalidOperationException("questTroopScreenCancel requires the current Native QuestTroopManage PartyScreen");
        var state = (PartyState)Game.Current.GameStateManager.ActiveState;
        var logic = state.PartyScreenLogic;
        if (!logic.IsCancelActive())
            throw new InvalidOperationException("Native QuestTroopManage Cancel is disabled by the current PartyScreen state");

        var viewModel = ChroniclePartyScreenAdapter.AttachToActivePartyScreen(state);
        try
        {
            viewModel.ExecuteCancelWithoutInquiry();
            var stillActive = ReferenceEquals(Game.Current?.GameStateManager?.ActiveState, state);
            if (stillActive)
                throw new InvalidOperationException("Native QuestTroopManage PartyVM cancel handler did not leave the assignment screen");
            return "{\"schemaVersion\":1,\"action\":\"Native PartyVM.ExecuteCancelWithoutInquiry\",\"screenClosed\":true}";
        }
        finally
        {
            ChroniclePartyScreenAdapter.Finalize(viewModel);
        }
    }

    private static void Property(StringBuilder builder, string name, string value)
    {
        builder.Append(",\"").Append(Escape(name)).Append("\":\"").Append(Escape(value ?? string.Empty)).Append('"');
    }

    private static string Escape(string value) => (value ?? string.Empty)
        .Replace("\\", "\\\\")
        .Replace("\"", "\\\"")
        .Replace("\r", "\\r")
        .Replace("\n", "\\n");
}
