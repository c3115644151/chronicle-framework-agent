using System;
using System.Linq;
using System.Text;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.Party;
using TaleWorlds.CampaignSystem.Settlements;
using TaleWorlds.CampaignSystem.ViewModelCollection.GameMenu.Recruitment;

namespace ChronicleFramework;

internal static class ChronicleAgentRecruitment
{
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
        if (Settlement.CurrentSettlement == null) throw new InvalidOperationException("recruitment requires an active settlement");
        if (current == null) return new RecruitmentVM();
        current.ExecuteReset();
        current.RefreshScreen();
        current.Enabled = true;
        return current;
    }

    internal static string Recruit(RecruitmentVM viewModel, string ownerId, string troopId, int slot)
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
        if (viewModel.CurrentPartySize > viewModel.PartyCapacity)
        {
            viewModel.ExecuteReset();
            throw new InvalidOperationException("party capacity would be exceeded");
        }
        if (!viewModel.IsDoneEnabled)
        {
            viewModel.ExecuteReset();
            throw new InvalidOperationException("insufficient gold for recruit");
        }

        viewModel.ExecuteDone();

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
        json.Append(",\"beforeGold\":").Append(beforeGold);
        json.Append(",\"afterGold\":").Append(afterGold);
        json.Append(",\"verified\":").Append(completed ? "true" : "false");
        json.Append('}');
        return json.ToString();
    }

    private static StringBuilder Property(StringBuilder json, string key, string value, bool prependComma = false)
    {
        if (prependComma) json.Append(',');
        json.Append('"').Append(Escape(key)).Append("\":\"").Append(Escape(value)).Append('"');
        return json;
    }

    private static string Escape(string value) => (value ?? string.Empty).Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\r", "\\r").Replace("\n", "\\n");
}
