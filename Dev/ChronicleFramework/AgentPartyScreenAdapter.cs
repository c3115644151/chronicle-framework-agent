using System;
using System.Reflection;
using Helpers;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.GameState;
using TaleWorlds.CampaignSystem.Party;
using TaleWorlds.CampaignSystem.ViewModelCollection.Party;
using TaleWorlds.Core;
using TaleWorlds.Library;
using TaleWorlds.Localization;

namespace ChronicleFramework;

internal static class ChroniclePartyScreenAdapter
{
    internal static PartyVM OpenMainPartyNormal()
    {
        if (Game.Current == null || Game.Current.CheatMode || Game.Current.GameStateManager?.ActiveState is not MapState || MobileParty.MainParty == null)
            throw new InvalidOperationException("MainParty PartyScreen actions require a non-cheat Campaign Map state with MainParty");

        PartyScreenHelper.OpenScreenAsNormal();
        var partyState = Game.Current.GameStateManager.ActiveState as PartyState;
        if (partyState == null || partyState.PartyScreenMode != PartyScreenHelper.PartyScreenMode.Normal || partyState.PartyScreenLogic?.RightOwnerParty?.MobileParty != MobileParty.MainParty)
        {
            CancelActiveNormal();
            throw new InvalidOperationException("Native PartyScreen did not open in normal MainParty mode");
        }

        PartyVM viewModel = null;
        try
        {
            viewModel = new PartyVM(partyState.PartyScreenLogic);
            PrepareFinalization(viewModel);
            return viewModel;
        }
        catch
        {
            CancelActiveNormal();
            if (viewModel != null) Finalize(viewModel);
            throw;
        }
    }

    internal static PartyVM AttachToActivePartyScreen(PartyState partyState)
    {
        if (partyState?.PartyScreenLogic == null)
            throw new InvalidOperationException("A live Native PartyState/PartyScreenLogic is required");
        var viewModel = new PartyVM(partyState.PartyScreenLogic);
        try
        {
            PrepareFinalization(viewModel);
            return viewModel;
        }
        catch
        {
            Finalize(viewModel);
            throw;
        }
    }

    internal static void CancelAndFinalize(PartyVM viewModel)
    {
        try
        {
            CancelActiveNormal();
        }
        finally
        {
            Finalize(viewModel);
        }
    }

    internal static InquiryData ExecuteDoneAndConfirmNativeOverLimit(PartyVM viewModel, bool confirmPartySizeWarning, bool confirmPrisonerLimitWarning = false)
    {
        InquiryData confirmation = null;
        var expectedTitle = new TextObject("{=uJro3Bua}Over Limit").ToString();
        var mainTroopLimitWarning = viewModel.IsMainTroopsLimitWarningEnabled;
        var mainPrisonerLimitWarning = viewModel.IsMainPrisonersLimitWarningEnabled;
        Action<InquiryData, bool, bool> handler = (inquiry, pauseGameActiveState, prioritize) =>
        {
            var explicitlyConfirmed = mainTroopLimitWarning
                ? confirmPartySizeWarning
                : mainPrisonerLimitWarning && confirmPrisonerLimitWarning;
            if (!explicitlyConfirmed || confirmation != null || inquiry == null || !inquiry.IsAffirmativeOptionShown || inquiry.AffirmativeAction == null || !string.Equals(inquiry.TitleText, expectedTitle, StringComparison.Ordinal))
                return;
            confirmation = inquiry;
            InformationManager.HideInquiry();
            inquiry.AffirmativeAction.Invoke();
        };

        InformationManager.OnShowInquiry += handler;
        try
        {
            viewModel.ExecuteDone();
        }
        finally
        {
            InformationManager.OnShowInquiry -= handler;
        }
        return confirmation;
    }

    internal static void CancelActiveNormal()
    {
        if (Game.Current?.GameStateManager?.ActiveState is PartyState partyState && partyState.PartyScreenMode == PartyScreenHelper.PartyScreenMode.Normal)
            PartyScreenHelper.CloseScreen(isForced: false, fromCancel: true);
    }

    internal static void CancelDraftAndClose(PartyVM viewModel)
    {
        if (Game.Current?.GameStateManager?.ActiveState is PartyState partyState && partyState.PartyScreenMode == PartyScreenHelper.PartyScreenMode.Normal)
            viewModel.ExecuteCancelWithoutInquiry();
    }

    internal static void Finalize(PartyVM viewModel)
    {
        viewModel?.OnFinalize();
    }

    private static void PrepareFinalization(PartyVM viewModel)
    {
        viewModel.SetGetKeyTextFromKeyIDFunc(_ => TextObject.GetEmpty());
        foreach (var methodName in new[]
        {
            "SetCancelInputKey", "SetDoneInputKey", "SetResetInputKey", "SetTakeAllTroopsInputKey",
            "SetDismissAllTroopsInputKey", "SetTakeAllPrisonersInputKey", "SetDismissAllPrisonersInputKey",
            "SetOpenUpgradePanelInputKey", "SetOpenRecruitPanelInputKey"
        })
        {
            var setter = viewModel.GetType().GetMethod(methodName, BindingFlags.Instance | BindingFlags.Public);
            if (setter == null) throw new MissingMethodException(viewModel.GetType().FullName, methodName);
            setter.Invoke(viewModel, new object[] { null });
        }
    }
}
