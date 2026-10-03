using System;
using System.Linq;
using System.Text;
using TaleWorlds.Core;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.GameState;
using TaleWorlds.CampaignSystem.GameMenus;
using TaleWorlds.CampaignSystem.Party;
using TaleWorlds.CampaignSystem.Settlements;
using TaleWorlds.CampaignSystem.ViewModelCollection.GameMenu.Recruitment;
using TaleWorlds.InputSystem;
using TaleWorlds.Library;
using TaleWorlds.Localization;
using TaleWorlds.MountAndBlade;

namespace ChronicleFramework;

internal static class ChronicleAgentRecruitment
{
    internal static void EnsureNativeVolunteerRecruitmentEntryIsAvailable()
    {
        var campaign = Campaign.Current;
        var settlement = Settlement.CurrentSettlement;
        var menuContext = campaign?.CurrentMenuContext;
        var menu = menuContext?.GameMenu;
        if (campaign == null || settlement == null || Game.Current?.GameStateManager?.ActiveState is not MapState || menu == null)
            throw new InvalidOperationException("volunteer recruitment requires an active Settlement GameMenu on the Campaign Map");

        var menuId = menu.StringId;
        var menuMatchesSettlement =
            (settlement.IsTown && (menuId == "town" || menuId == "town_backstreet")) ||
            (settlement.IsVillage && menuId == "village");
        if (!menuMatchesSettlement)
            throw new InvalidOperationException("volunteer recruitment is not available from this Settlement menu");

        var option = menu.MenuOptions.FirstOrDefault(candidate => candidate.IdString == "recruit_volunteers");
        if (option == null || !option.IsEnabled || !option.GetConditionsHold(Game.Current, menuContext))
            throw new InvalidOperationException("the native recruit_volunteers menu option is not currently available");
    }

    internal static string BuildOptionsJson(RecruitmentVM viewModel)
    {
        var settlement = Settlement.CurrentSettlement;
        var options = viewModel.VolunteerList
            .SelectMany(owner => owner.Troops
                .Where(troop => troop.Character != null)
                .Select(troop => new { Owner = owner, Troop = troop }))
            .ToArray();

        var json = new StringBuilder(2048);
        json.Append('{');
        json.Append("\"settlementId\":\"").Append(Escape(settlement.StringId)).Append('\"');
        json.Append(",\"gold\":").Append(Hero.MainHero.Gold);
        json.Append(",\"partySize\":").Append(viewModel.CurrentPartySize);
        json.Append(",\"partyCapacity\":").Append(viewModel.PartyCapacity);
        var nextVolunteerWouldExceedLimit = viewModel.CurrentPartySize + 1 > viewModel.PartyCapacity;
        json.Append(",\"partySizeWarningForOne\":").Append(nextVolunteerWouldExceedLimit ? "true" : "false");
        if (nextVolunteerWouldExceedLimit)
        {
            Property(json, "nativeCapacityWarningTitle", new TextObject("{=uJro3Bua}Over Limit").ToString(), prependComma: true);
            Property(json, "nativeCapacityWarningText", GameTexts.FindText("str_party_over_limit_troops").ToString(), prependComma: true);
        }
        json.Append(",\"offers\":[");
        for (var index = 0; index < options.Length; index++)
        {
            if (index > 0) json.Append(',');
            var option = options[index];
            json.Append('{');
            Property(json, "ownerId", option.Owner.OwnerHero.StringId);
            Property(json, "ownerName", option.Owner.OwnerHero.Name?.ToString(), true);
            Property(json, "troopId", option.Troop.Character.StringId, true);
            Property(json, "troopName", option.Troop.Character.Name?.ToString(), true);
            json.Append(",\"slot\":").Append(option.Troop.Index);
            json.Append(",\"cost\":").Append(option.Troop.Cost);
            json.Append(",\"wage\":").Append(option.Troop.Wage);
            json.Append(",\"available\":").Append(option.Troop.CanBeRecruited ? "true" : "false");
            json.Append('}');
        }
        json.Append("]}");
        return json.ToString();
    }

    internal static RecruitmentVM CreateOrRefresh(RecruitmentVM current)
    {
        EnsureNativeVolunteerRecruitmentEntryIsAvailable();
        if (current == null) return CreateNativeRecruitmentViewModel();
        current.ExecuteReset();
        current.RefreshScreen();
        current.Enabled = true;
        return current;
    }

    private static RecruitmentVM CreateNativeRecruitmentViewModel()
    {
        var viewModel = new RecruitmentVM();
        var keyCategory = HotKeyManager.GetCategory("GenericPanelGameKeyCategory");
        viewModel.SetCancelInputKey(keyCategory.GetHotKey("Exit"));
        viewModel.SetDoneInputKey(keyCategory.GetHotKey("Confirm"));
        viewModel.SetResetInputKey(keyCategory.GetHotKey("Reset"));
        viewModel.SetRecruitAllInputKey(keyCategory.GetHotKey("TakeAll"));
        viewModel.SetGetKeyTextFromKeyIDFunc(keyId => GameKeyTextExtensions.GetHotKeyGameTextFromKeyID(Game.Current.GameTextManager, keyId));
        return viewModel;
    }

    internal static string Recruit(RecruitmentVM viewModel, string ownerId, string troopId, int slot, bool confirmPartySizeWarning)
    {
        var selected = viewModel.VolunteerList
            .Where(owner => string.Equals(owner.OwnerHero.StringId, ownerId, StringComparison.Ordinal))
            .SelectMany(owner => owner.Troops.Select(troop => new { Owner = owner, Troop = troop }))
            .FirstOrDefault(option =>
                option.Troop.Character != null &&
                string.Equals(option.Troop.Character.StringId, troopId, StringComparison.Ordinal) &&
                option.Troop.Index == slot);

        if (selected == null) throw new InvalidOperationException("recruit offer not found or no longer available");
        if (!selected.Troop.CanBeRecruited) throw new InvalidOperationException("recruit offer is unavailable");

        var beforeMembers = MobileParty.MainParty.MemberRoster.TotalManCount;
        var beforeGold = Hero.MainHero.Gold;
        var expectedCost = selected.Troop.Cost;
        selected.Troop.ExecuteRecruit();
        if (!selected.Troop.IsInCart) throw new InvalidOperationException("native recruitment view model did not accept the offer");
        if (!viewModel.IsDoneEnabled)
        {
            viewModel.ExecuteReset();
            throw new InvalidOperationException("insufficient gold for recruit");
        }

        var requiresCapacityConfirmation = viewModel.CurrentPartySize > viewModel.PartyCapacity;
        InquiryData nativeCapacityInquiry = null;
        if (requiresCapacityConfirmation)
        {
            nativeCapacityInquiry = ExecuteDoneAndConfirmNativeOverLimit(viewModel, confirmPartySizeWarning);
            if (nativeCapacityInquiry == null)
            {
                viewModel.ExecuteReset();
                throw new InvalidOperationException("native RecruitmentVM did not open its Over Limit confirmation inquiry");
            }
            if (!confirmPartySizeWarning)
            {
                viewModel.ExecuteReset();
                throw new InvalidOperationException("native RecruitmentVM requires explicit ConfirmPartySizeWarning=true: " + nativeCapacityInquiry.Text);
            }
        }
        else
        {
            viewModel.ExecuteDone();
        }

        var afterMembers = MobileParty.MainParty.MemberRoster.TotalManCount;
        var afterGold = Hero.MainHero.Gold;
        var completed = afterMembers == beforeMembers + 1 && afterGold == beforeGold - expectedCost;
        var json = new StringBuilder();
        json.Append('{');
        Property(json, "ownerId", ownerId);
        Property(json, "troopId", troopId, true);
        json.Append(",\"slot\":").Append(slot);
        json.Append(",\"cost\":").Append(expectedCost);
        json.Append(",\"beforeMembers\":").Append(beforeMembers);
        json.Append(",\"afterMembers\":").Append(afterMembers);
        json.Append(",\"partySizeLimit\":").Append(viewModel.PartyCapacity);
        json.Append(",\"nativeCapacityWarningRequired\":").Append(requiresCapacityConfirmation ? "true" : "false");
        json.Append(",\"nativeCapacityConfirmationAccepted\":").Append((requiresCapacityConfirmation && confirmPartySizeWarning && nativeCapacityInquiry != null) ? "true" : "false");
        Property(json, "nativeCapacityConfirmationTitle", nativeCapacityInquiry?.TitleText, prependComma: true);
        Property(json, "nativeCapacityConfirmationText", nativeCapacityInquiry?.Text, prependComma: true);
        json.Append(",\"beforeGold\":").Append(beforeGold);
        json.Append(",\"afterGold\":").Append(afterGold);
        json.Append(",\"verified\":").Append(completed ? "true" : "false");
        json.Append('}');
        return json.ToString();
    }

    internal static string BeginHarnessNativeCapacityInquiry(RecruitmentVM current, string ownerId, string troopId, int slot, out RecruitmentVM preparedViewModel)
    {
        var mode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var root = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(mode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(root) || !System.IO.Directory.Exists(root))
            throw new InvalidOperationException("Native Recruitment Inquiry fixture is restricted to a visual Harness run.");
        EnsureNativeVolunteerRecruitmentEntryIsAvailable();
        var viewModel = CreateOrRefresh(current);
        var selected = viewModel.VolunteerList
            .Where(owner => string.Equals(owner.OwnerHero.StringId, ownerId, StringComparison.Ordinal))
            .SelectMany(owner => owner.Troops.Select(troop => new { Owner = owner, Troop = troop }))
            .FirstOrDefault(option => option.Troop.Character != null && string.Equals(option.Troop.Character.StringId, troopId, StringComparison.Ordinal) && option.Troop.Index == slot);
        if (selected == null || !selected.Troop.CanBeRecruited)
            throw new InvalidOperationException("Harness Native Recruitment Inquiry requires a currently available Native volunteer offer.");

        var membersBefore = MobileParty.MainParty.MemberRoster.TotalManCount;
        var goldBefore = Hero.MainHero.Gold;
        selected.Troop.ExecuteRecruit();
        if (!selected.Troop.IsInCart || !viewModel.IsDoneEnabled)
        {
            viewModel.ExecuteReset();
            throw new InvalidOperationException("Native RecruitmentVM could not prepare an affordable volunteer transaction.");
        }
        if (viewModel.CurrentPartySize <= viewModel.PartyCapacity)
        {
            viewModel.ExecuteReset();
            throw new InvalidOperationException("Native RecruitmentVM did not exceed capacity; the Native confirmation would be an invalid fixture.");
        }

        viewModel.ExecuteDone();
        if (!InformationManager.IsAnyInquiryActive())
        {
            viewModel.ExecuteReset();
            throw new InvalidOperationException("Native RecruitmentVM.ExecuteDone did not display its party capacity Inquiry.");
        }
        preparedViewModel = viewModel;
        var json = new StringBuilder(384);
        var warningTitle = new TextObject("{=uJro3Bua}Over Limit").ToString();
        json.Append('{');
        Property(json, "source", "Native RecruitmentVM.ExecuteDone");
        Property(json, "warningTitle", warningTitle, true);
        Property(json, "ownerId", ownerId, true);
        Property(json, "troopId", troopId, true);
        json.Append(",\"slot\":").Append(slot);
        json.Append(",\"membersBefore\":").Append(membersBefore);
        json.Append(",\"membersWithUncommittedOffer\":").Append(viewModel.CurrentPartySize);
        json.Append(",\"partyCapacity\":").Append(viewModel.PartyCapacity);
        json.Append(",\"goldBefore\":").Append(goldBefore);
        json.Append(",\"goldStillBeforeResponse\":").Append(Hero.MainHero.Gold);
        json.Append('}');
        return json.ToString();
    }

    private static InquiryData ExecuteDoneAndConfirmNativeOverLimit(RecruitmentVM viewModel, bool confirmPartySizeWarning)
    {
        InquiryData confirmation = null;
        var expectedTitle = new TextObject("{=uJro3Bua}Over Limit").ToString();
        Action<InquiryData, bool, bool> handler = (inquiry, pauseGameActiveState, prioritize) =>
        {
            if (inquiry == null || confirmation != null || !inquiry.IsAffirmativeOptionShown || inquiry.AffirmativeAction == null || !string.Equals(inquiry.TitleText, expectedTitle, StringComparison.Ordinal))
                return;
            confirmation = inquiry;
            InformationManager.HideInquiry();
            if (confirmPartySizeWarning) inquiry.AffirmativeAction.Invoke();
        };

        InformationManager.OnShowInquiry += handler;
        try { viewModel.ExecuteDone(); }
        finally { InformationManager.OnShowInquiry -= handler; }
        return confirmation;
    }

    private static StringBuilder Property(StringBuilder json, string key, string value, bool prependComma = false)
    {
        if (prependComma) json.Append(',');
        json.Append('"').Append(Escape(key)).Append("\":\"").Append(Escape(value)).Append('"');
        return json;
    }

    private static string Escape(string value) => (value ?? string.Empty).Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\r", "\\r").Replace("\n", "\\n");
}
