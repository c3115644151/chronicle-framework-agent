using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using SandBox;
using SandBox.View.Map;
using SandBox.View.Map.Managers;
using SandBox.View.Map.Visuals;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.Encounters;
using TaleWorlds.CampaignSystem.GameState;
using TaleWorlds.CampaignSystem.GameMenus;
using TaleWorlds.CampaignSystem.Issues;
using TaleWorlds.CampaignSystem.MapEvents;
using TaleWorlds.CampaignSystem.Party;
using TaleWorlds.CampaignSystem.Settlements;
using TaleWorlds.CampaignSystem.Settlements.Locations;
using TaleWorlds.CampaignSystem.ViewModelCollection.GameMenu.Recruitment;
using TaleWorlds.CampaignSystem.ViewModelCollection.GameMenu.Events;
using TaleWorlds.Core;
using TaleWorlds.InputSystem;
using TaleWorlds.MountAndBlade;
using TaleWorlds.MountAndBlade.View.MissionViews;
using EngineTime = TaleWorlds.Engine.Time;

namespace ChronicleFramework;

internal sealed partial class ChronicleAgentProtocol
{
    private void HandleFoodOptions(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentTradeAdapter.BuildFoodOptionsJson());
    }

    private void HandleTradeOptions(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentTradeAdapter.BuildTradeOptionsJson());
    }

    private void HandleTradeRumors(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var tradeRumorItemViewModelId = ReadString(command, "itemViewModelId");
        var tradeRumorInventorySide = ReadString(command, "inventorySide");
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentTradeAdapter.BuildTradeRumorOptionsJson(tradeRumorItemViewModelId, tradeRumorInventorySide));
    }

    private void HandleHarnessSeedTradeRumorFixture(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentTradeAdapter.SeedHarnessTradeRumorFixture(ReadString(command, "itemViewModelId"), ReadString(command, "inventorySide")));
    }

    private void HandleHarnessTradeRumorTooltipDiagnostics(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentTradeAdapter.ReadHarnessNativeTradeRumorTooltip(ReadString(command, "itemViewModelId"), ReadString(command, "inventorySide")));
    }

    private void HandleTrade(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var tradeDirection = ReadString(command, "direction");
        var tradeItemViewModelId = ReadString(command, "itemViewModelId");
        var tradeInventorySide = ReadString(command, "inventorySide");
        var tradeAmount = (int)ReadDouble(command, "amount");
        var tradeResult = ChronicleAgentTradeAdapter.DraftTradeItem(tradeDirection, tradeItemViewModelId, tradeInventorySide, tradeAmount);
        WriteResponse(commandId, action, "completed", behavior, null, tradeResult);
    }

    private void HandleProvision(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var foodItemViewModelId = ReadString(command, "itemViewModelId");
        var foodAmount = (int)ReadDouble(command, "amount");
        var provisionResult = ChronicleAgentTradeAdapter.DraftTradeItem("buy", foodItemViewModelId, "OtherInventory", foodAmount, requireFood: true);
        WriteResponse(commandId, action, "completed", behavior, null, provisionResult);
    }

    private void HandleTradeConfirm(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var tradeCommitReceipt = ChronicleAgentTradeAdapter.CommitCurrentNativeTradeTransaction();
        if (tradeCommitReceipt.IndexOf("\"postconditionPassed\":true", StringComparison.Ordinal) >= 0)
        {
            WriteResponse(commandId, action, "completed", behavior, null, tradeCommitReceipt);
        }
        else if (ChronicleInquiryAdapter.IsInquiryOpen)
        {
            WriteResponse(commandId, action, "accepted", behavior, null, tradeCommitReceipt);
        }
        else
        {
            throw new InvalidOperationException("Native Trade Done did not commit and no Native confirmation inquiry is open");
        }
    }

    private void HandleTradeCancel(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentTradeAdapter.CancelCurrentNativeTradeTransaction(confirmDiscardChanges: false));
    }

    private void HandleTradeCancelChanges(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentTradeAdapter.CancelCurrentNativeTradeTransaction(confirmDiscardChanges: true));
    }

    private void HandleBarterOptions(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentBarterAdapter.BuildOptionsJson());
    }

    private void HandleBarterEdit(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var barterCandidateId = ReadString(command, "barterCandidateId");
        var barterOperation = ReadString(command, "barterOperation");
        var barterAmount = (int)ReadDouble(command, "amount");
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentBarterAdapter.EditProposal(barterCandidateId, barterOperation, barterAmount));
    }

    private void HandleBarterReset(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentBarterAdapter.ResetProposal());
    }

    private void HandleBarterAutoBalance(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentBarterAdapter.AutoBalanceProposal());
    }

    private void HandleBarterOffer(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var expectedBarterSessionId = ReadString(command, "expectedSessionId");
        var expectedBarterProposalFingerprint = ReadString(command, "expectedProposalFingerprint");
        if (string.IsNullOrWhiteSpace(expectedBarterSessionId) != string.IsNullOrWhiteSpace(expectedBarterProposalFingerprint))
            throw new InvalidOperationException("expected BarterVM session and proposal fingerprint must be supplied together");
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentBarterAdapter.SubmitOffer(expectedBarterSessionId, expectedBarterProposalFingerprint));
    }

    private void HandleBarterCancel(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentBarterAdapter.CancelProposal());
    }
}
