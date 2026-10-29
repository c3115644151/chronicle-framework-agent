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

internal static class ChronicleLootPartyTransferAdapter
{
    internal static string TransferOne(string troopId, string troopTypeName)
    {
        var state = Game.Current?.GameStateManager?.ActiveState as PartyState;
        if (state?.PartyScreenLogic == null || state.PartyScreenMode != PartyScreenHelper.PartyScreenMode.Loot ||
            state.PartyScreenLogic.RightOwnerParty?.MobileParty != MobileParty.MainParty)
            throw new InvalidOperationException("partyLootTransferOne requires the current Native postbattle Loot PartyState for MainParty");
        if (ChronicleInquiryAdapter.IsInquiryOpen)
            throw new InvalidOperationException("partyLootTransferOne is blocked by an active Native inquiry");
        if (string.IsNullOrWhiteSpace(troopId)) throw new InvalidOperationException("troopId is required");

        var troopType = troopTypeName switch
        {
            "members" => PartyScreenLogic.TroopType.Member,
            "prisoners" => PartyScreenLogic.TroopType.Prisoner,
            _ => throw new InvalidOperationException("troopType must be members or prisoners")
        };
        var logic = state.PartyScreenLogic;
        var sourceSide = PartyScreenLogic.PartyRosterSide.Left;
        var targetSide = PartyScreenLogic.PartyRosterSide.Right;
        var sourceRoster = logic.GetRoster(sourceSide, troopType);
        var targetRoster = logic.GetRoster(targetSide, troopType);
        var sourceElement = sourceRoster.GetTroopRoster().FirstOrDefault(element => element.Character != null &&
            element.Number > 0 && string.Equals(element.Character.StringId, troopId, StringComparison.Ordinal));
        var sourceCharacter = sourceElement.Character;
        if (sourceCharacter == null)
            throw new InvalidOperationException("troopId is not a current transferable Native loot row on the left side");
        if (!logic.IsTroopTransferable(troopType, sourceCharacter, (int)sourceSide))
            throw new InvalidOperationException("The current Native Loot PartyScreen does not allow this troop to transfer");

        var receiveLimit = troopType == PartyScreenLogic.TroopType.Prisoner
            ? logic.RightPartyPrisonersSizeLimit
            : logic.RightPartyMembersSizeLimit;
        if (targetRoster.TotalManCount >= receiveLimit)
            throw new InvalidOperationException("The MainParty Native Loot roster is already at its current receive limit");

        var viewModel = ChroniclePartyScreenAdapter.AttachToActivePartyScreen(state);
        try
        {
            var displayedRoster = troopType == PartyScreenLogic.TroopType.Prisoner
                ? viewModel.OtherPartyPrisoners
                : viewModel.OtherPartyTroops;
            var row = displayedRoster?.FirstOrDefault(candidate => candidate != null &&
                candidate.Side == sourceSide && candidate.Type == troopType && candidate.Character != null &&
                string.Equals(candidate.Character.StringId, troopId, StringComparison.Ordinal));
            if (row == null || !row.IsTroopTransferrable || row.Number < 1)
                throw new InvalidOperationException("troopId is not a currently visible, transferable Native Loot row");

            var sourceBefore = sourceRoster.GetTroopCount(sourceCharacter);
            var targetBefore = targetRoster.GetTroopCount(sourceCharacter);
            row.ExecuteTransferSingle();

            sourceRoster = logic.GetRoster(sourceSide, troopType);
            targetRoster = logic.GetRoster(targetSide, troopType);
            var sourceAfter = sourceRoster.GetTroopCount(sourceCharacter);
            var targetAfter = targetRoster.GetTroopCount(sourceCharacter);
            if (sourceAfter != sourceBefore - 1 || targetAfter != targetBefore + 1)
                throw new InvalidOperationException("Native PartyCharacterVM.ExecuteTransferSingle did not move exactly one loot troop");

            var receipt = new StringBuilder(512);
            receipt.Append("{\"schemaVersion\":1,\"transferredCount\":1");
            Property(receipt, "troopId", sourceCharacter.StringId);
            Property(receipt, "troopType", troopTypeName);
            Property(receipt, "nativeHandler", "PartyCharacterVM.ExecuteTransferSingle");
            receipt.Append(",\"sourceCountBefore\":").Append(sourceBefore)
                .Append(",\"sourceCountAfter\":").Append(sourceAfter)
                .Append(",\"targetCountBefore\":").Append(targetBefore)
                .Append(",\"targetCountAfter\":").Append(targetAfter)
                .Append(",\"targetCountLimit\":").Append(receiveLimit)
                .Append(",\"doneAvailableAfter\":").Append(logic.IsDoneActive() ? "true" : "false")
                .Append('}');
            return receipt.ToString();
        }
        finally
        {
            ChroniclePartyScreenAdapter.Finalize(viewModel);
        }
    }

    private static void Property(StringBuilder builder, string name, string value)
    {
        builder.Append(",\"").Append(name).Append("\":\"").Append((value ?? string.Empty)
            .Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\r", "\\r").Replace("\n", "\\n")).Append('"');
    }
}
