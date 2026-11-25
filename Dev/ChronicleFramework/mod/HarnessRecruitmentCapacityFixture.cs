using System;
using System.Text;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.Party;

namespace ChronicleFramework;

internal static class HarnessRecruitmentCapacityFixture
{
    internal static string SeedMainPartyToCapacity()
    {
        var mode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var root = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(mode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(root) || !System.IO.Directory.Exists(root))
            throw new InvalidOperationException("Recruitment capacity fixture seeding is restricted to a visual Harness run.");

        var party = MobileParty.MainParty;
        var hero = Hero.MainHero;
        if (Campaign.Current == null || party == null || hero?.Culture?.BasicTroop == null)
            throw new InvalidOperationException("Recruitment capacity fixture requires a current MainParty and a cultural BasicTroop.");

        var membersBefore = party.MemberRoster.TotalManCount;
        var limit = party.Party.PartySizeLimit;
        if (membersBefore > limit)
            throw new InvalidOperationException("Recruitment capacity fixture cannot seed an already over-limit MainParty.");

        var filler = hero.Culture.BasicTroop;
        var added = limit - membersBefore;
        if (added > 0)
            party.MemberRoster.AddToCounts(filler, added, insertAtFront: false, woundedCount: 0, xpChange: 0, removeDepleted: true, index: -1);

        var json = new StringBuilder(256);
        json.Append('{').Append("\"fillerTroopId\":\"").Append(Escape(filler.StringId)).Append('"');
        json.Append(",\"membersBefore\":").Append(membersBefore);
        json.Append(",\"fillerAdded\":").Append(added);
        json.Append(",\"partySizeLimit\":").Append(limit);
        json.Append(",\"membersAfter\":").Append(party.MemberRoster.TotalManCount);
        json.Append('}');
        return json.ToString();
    }

    private static string Escape(string value) => (value ?? string.Empty).Replace("\\", "\\\\").Replace("\"", "\\\"");
}
