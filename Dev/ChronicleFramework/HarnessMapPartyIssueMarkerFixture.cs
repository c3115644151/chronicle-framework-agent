using System;
using System.Linq;
using System.Text;
using Helpers;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.Issues;
using TaleWorlds.CampaignSystem.Party;
using TaleWorlds.CampaignSystem.ViewModelCollection;
using TaleWorlds.Core;

namespace ChronicleFramework;

internal static class ChronicleHarnessMapPartyIssueMarkerFixture
{
    internal static string PrepareNativeAvailableIssueMarker(string partyId)
    {
        RequireVisualMapFixture();
        var party = FindObservedParty(partyId);
        if (!party.IsSpotted() || party.CurrentSettlement != null)
            throw new InvalidOperationException("party must have a Native map Nameplate candidate (spotted and outside a settlement)");
        var leader = party.LeaderHero;
        if (leader == null || leader == Hero.MainHero)
            throw new InvalidOperationException("party must have a non-player Hero leader to create an Issue marker fixture");
        var issueManager = Campaign.Current.IssueManager;
        if (leader.Issue != null || issueManager.Issues.ContainsKey(leader))
            throw new InvalidOperationException("party leader already owns an Issue; choose a currently observed leader without an Issue");

        var candidates = issueManager.CheckForIssues(leader);
        var candidate = candidates.FirstOrDefault(item => item.IsValid);
        if (!candidate.IsValid)
            throw new InvalidOperationException("Native IssueManager found no currently eligible Issue candidate for this observed leader");
        if (!issueManager.CreateNewIssue(in candidate, leader))
            throw new InvalidOperationException("Native IssueManager.CreateNewIssue did not accept its own eligible candidate");
        if (!issueManager.Issues.TryGetValue(leader, out var createdIssue) || createdIssue == null || leader.Issue != createdIssue)
            throw new InvalidOperationException("Native IssueManager did not attach the created Issue to its selected Hero");

        var json = new StringBuilder(768);
        json.Append('{').Append("\"schemaVersion\":1,\"testOnly\":true,\"nativeIssueFixtureCreated\":true");
        ChroniclePartyUpgradeAdapter.Property(json, "partyId", party.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "leaderHeroId", leader.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "issueType", createdIssue.GetType().FullName);
        ChroniclePartyUpgradeAdapter.Property(json, "issueId", createdIssue.StringId);
        json.Append(",\"nativeCandidateCount\":").Append(candidates.Count);
        json.Append(",\"partySpotted\":").Append(ChroniclePartyUpgradeAdapter.Bool(party.IsSpotted()));
        json.Append(",\"partyHasNoSettlement\":").Append(ChroniclePartyUpgradeAdapter.Bool(party.CurrentSettlement == null));
        json.Append(",\"heroIssueAttached\":").Append(ChroniclePartyUpgradeAdapter.Bool(leader.Issue == createdIssue));
        json.Append(",\"nativeHeroQuestMarkerFlags\":[");
        var firstMarker = true;
        foreach (var marker in CampaignUIHelper.GetQuestStateOfHero(leader).Select(item => item.Item1).Distinct().OrderBy(item => (int)item))
        {
            if (!firstMarker) json.Append(',');
            firstMarker = false;
            json.Append('"').Append(marker.ToString()).Append('"');
        }
        json.Append(']');
        return json.Append('}').ToString();
    }

    internal static string BuildNativeIssueMarkerDiagnostics(string partyId)
    {
        RequireVisualMapFixture();
        var party = FindObservedParty(partyId);
        var leader = party.LeaderHero;
        var json = new StringBuilder(1024);
        json.Append('{').Append("\"schemaVersion\":1");
        ChroniclePartyUpgradeAdapter.Property(json, "partyId", party.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "leaderHeroId", leader?.StringId);
        json.Append(",\"nativeNameplateCandidate\":").Append(ChroniclePartyUpgradeAdapter.Bool(party.IsSpotted() && party.CurrentSettlement == null));
        json.Append(",\"partySpotted\":").Append(ChroniclePartyUpgradeAdapter.Bool(party.IsSpotted()));
        json.Append(",\"partyInSettlement\":").Append(ChroniclePartyUpgradeAdapter.Bool(party.CurrentSettlement != null));
        json.Append(",\"leaderHasIssue\":").Append(ChroniclePartyUpgradeAdapter.Bool(leader?.Issue != null));
        json.Append(",\"nativeHeroQuestMarkerFlags\":[");
        var first = true;
        if (leader != null)
        {
            foreach (var marker in CampaignUIHelper.GetQuestStateOfHero(leader).Select(item => item.Item1).Distinct().OrderBy(item => (int)item))
            {
                if (!first) json.Append(',');
                first = false;
                json.Append('"').Append(marker.ToString()).Append('"');
            }
        }
        json.Append("]}");
        return json.ToString();
    }

    private static MobileParty FindObservedParty(string partyId)
    {
        if (string.IsNullOrWhiteSpace(partyId))
            throw new InvalidOperationException("partyId must come from the current mapPartyTargets observation");
        var mainParty = MobileParty.MainParty;
        var target = MobileParty.All.FirstOrDefault(item => item != null && string.Equals(item.StringId, partyId, StringComparison.Ordinal));
        if (mainParty == null || target == null || target == mainParty || !target.IsActive || target.IsGarrison || target.IsMilitia || target.AttachedTo != null || !target.Party.IsVisible)
            throw new InvalidOperationException("party is not a current independent visible mapPartyTargets candidate");
        return target;
    }

    private static void RequireVisualMapFixture()
    {
        var mode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var root = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(mode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(root) || !System.IO.Directory.Exists(root))
            throw new InvalidOperationException("map Party Issue marker fixture/diagnostics are restricted to a visual Harness run with a Harness temp directory");
        if (Game.Current?.GameStateManager?.ActiveState is not TaleWorlds.CampaignSystem.GameState.MapState || Campaign.Current == null || Hero.MainHero == null || MobileParty.MainParty == null)
            throw new InvalidOperationException("map Party Issue marker fixture/diagnostics require an active Campaign Map and MainHero");
    }
}
