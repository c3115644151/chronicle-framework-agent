using System;
using System.Linq;
using System.Text;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.GameState;
using TaleWorlds.CampaignSystem.Party;
using TaleWorlds.CampaignSystem.ViewModelCollection.ClanManagement;
using TaleWorlds.Core;
using TaleWorlds.Library;

namespace ChronicleFramework;

internal static class ChroniclePartyRoleAdapter
{
    private static readonly PartyRole[] SupportedRoles =
    {
        PartyRole.Quartermaster,
        PartyRole.Scout,
        PartyRole.Surgeon,
        PartyRole.Engineer
    };

    internal static string BuildMainPartyRolesJson()
    {
        RequireCampaignMap();
        var party = MobileParty.MainParty;
        if (party == null || party.LeaderHero == null) throw new InvalidOperationException("MainParty and its leader are required");
        var timeModeBefore = Campaign.Current.TimeControlMode.ToString();
        var campaignDayBefore = CampaignTime.Now.ToDays;
        var roles = BuildNativeRoleViewModels(party);
        try
        {
            var snapshot = BuildSnapshotJson(party, roles);
            return snapshot.Substring(0, snapshot.Length - 1) +
                ",\"timeControlModeBefore\":\"" + ChroniclePartyUpgradeAdapter.Escape(timeModeBefore) + "\"" +
                ",\"timeControlModeDuring\":\"" + ChroniclePartyUpgradeAdapter.Escape(Campaign.Current.TimeControlMode.ToString()) + "\"" +
                ",\"campaignDayBefore\":" + campaignDayBefore.ToString("F3", System.Globalization.CultureInfo.InvariantCulture) +
                ",\"timeControlModeAfter\":\"" + ChroniclePartyUpgradeAdapter.Escape(Campaign.Current.TimeControlMode.ToString()) + "\"" +
                ",\"campaignDayAfter\":" + CampaignTime.Now.ToDays.ToString("F3", System.Globalization.CultureInfo.InvariantCulture) + "}";
        }
        finally
        {
            Finalize(roles);
        }
    }

    internal static string SetMainPartyRoleJson(string roleId, string heroId, bool removeAssignee)
    {
        RequireCampaignMap();
        var hasHeroId = !string.IsNullOrWhiteSpace(heroId);
        if (removeAssignee == hasHeroId)
            throw new InvalidOperationException("Specify exactly one of heroId or removeAssignee=true");

        var party = MobileParty.MainParty;
        if (party == null || party.LeaderHero == null) throw new InvalidOperationException("MainParty and its leader are required");
        var requestedRole = ParseSupportedRole(roleId);
        if (!TaleWorlds.CampaignSystem.ViewModelCollection.CampaignUIHelper.GetMapScreenActionIsEnabledWithReason(out var disabledReason))
            throw new InvalidOperationException("Native Clan Party role actions are disabled: " + disabledReason);
        var before = BuildNativeRoleViewModels(party);
        try
        {
            var targetRole = before.FirstOrDefault(item => item.Role == requestedRole);
            if (targetRole == null) throw new InvalidOperationException("Role is not exposed by the current native ClanMemberPartyRoleModel");

            ClanRoleMemberItemVM targetMember;
            if (removeAssignee)
            {
                if (party.GetRoleHolder(requestedRole) == null) throw new InvalidOperationException("The selected role has no current assignee to remove");
                targetMember = targetRole.Members.FirstOrDefault(item => item != null && item.IsRemoveAssigneeOption);
                if (targetMember == null) throw new InvalidOperationException("Native role VM did not expose Remove assignee");
            }
            else
            {
                targetMember = targetRole.Members.FirstOrDefault(item => item?.Member?.HeroObject != null && string.Equals(item.Member.HeroObject.StringId, heroId, StringComparison.Ordinal));
                if (targetMember == null)
                    throw new InvalidOperationException("HeroId is not a currently eligible MainParty candidate in the native role VM");
            }

            var roleSnapshotBefore = BuildSnapshotJson(party, before);
            var timeModeBefore = Campaign.Current.TimeControlMode.ToString();
            var campaignDayBefore = CampaignTime.Now.ToDays;
            targetMember.ExecuteAssignHeroToRole();

            var after = BuildNativeRoleViewModels(party);
            try
            {
                var newHolder = party.GetRoleHolder(requestedRole);
                if (!removeAssignee && (newHolder == null || !string.Equals(newHolder.StringId, heroId, StringComparison.Ordinal)))
                    throw new InvalidOperationException("Native role handler returned without assigning the requested Hero");
                if (removeAssignee && newHolder != null)
                    throw new InvalidOperationException("Native role handler returned without removing the requested role assignee");

                var json = new StringBuilder(4096);
                json.Append('{').Append("\"schemaVersion\":1");
                ChroniclePartyUpgradeAdapter.Property(json, "partyId", party.StringId);
                ChroniclePartyUpgradeAdapter.Property(json, "roleId", requestedRole.ToString());
                ChroniclePartyUpgradeAdapter.Property(json, "requestedHeroId", removeAssignee ? null : heroId);
                json.Append(",\"removeAssignee\":").Append(ChroniclePartyUpgradeAdapter.Bool(removeAssignee));
                json.Append(",\"committed\":true");
                ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeBefore", timeModeBefore);
                json.Append(",\"timeControlModeAfter\":\"").Append(ChroniclePartyUpgradeAdapter.Escape(Campaign.Current.TimeControlMode.ToString())).Append('"');
                json.Append(",\"campaignDayBefore\":").Append(campaignDayBefore.ToString("F3", System.Globalization.CultureInfo.InvariantCulture));
                json.Append(",\"campaignDayAfter\":").Append(CampaignTime.Now.ToDays.ToString("F3", System.Globalization.CultureInfo.InvariantCulture));
                json.Append(",\"before\":").Append(roleSnapshotBefore);
                json.Append(",\"after\":").Append(BuildSnapshotJson(party, after));
                return json.Append('}').ToString();
            }
            finally
            {
                Finalize(after);
            }
        }
        finally
        {
            Finalize(before);
        }
    }

    internal static string SeedDisposableRoleCompanion()
    {
        RequireCampaignMap();
        var candidate = Hero.AllAliveHeroes.FirstOrDefault(hero => hero != null && hero.Occupation == Occupation.Wanderer && hero.CompanionOf == null && hero.Clan == null && hero.PartyBelongedTo == null && !hero.IsPrisoner);
        if (candidate == null) throw new InvalidOperationException("No unattached Wanderer Hero is available for the disposable PartyRole fixture");
        var goldBefore = Hero.MainHero.Gold;
        var campaignDayBefore = CampaignTime.Now.ToDays;
        var modeBefore = Campaign.Current.TimeControlMode.ToString();
        TaleWorlds.CampaignSystem.Actions.AddCompanionAction.Apply(Clan.PlayerClan, candidate);
        TaleWorlds.CampaignSystem.Actions.AddHeroToPartyAction.Apply(candidate, MobileParty.MainParty, showNotification: false);
        var json = new StringBuilder(768);
        json.Append('{').Append("\"schemaVersion\":1");
        ChroniclePartyUpgradeAdapter.Property(json, "heroId", candidate.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "heroName", candidate.Name?.ToString());
        json.Append(",\"isPlayerCompanion\":").Append(ChroniclePartyUpgradeAdapter.Bool(candidate.IsPlayerCompanion));
        json.Append(",\"inMainParty\":").Append(ChroniclePartyUpgradeAdapter.Bool(MobileParty.MainParty.MemberRoster.FindIndexOfTroop(candidate.CharacterObject) >= 0));
        json.Append(",\"goldBefore\":").Append(goldBefore).Append(",\"goldAfter\":").Append(Hero.MainHero.Gold);
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeBefore", modeBefore);
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeAfter", Campaign.Current.TimeControlMode.ToString());
        json.Append(",\"campaignDayBefore\":").Append(campaignDayBefore.ToString("F3", System.Globalization.CultureInfo.InvariantCulture));
        json.Append(",\"campaignDayAfter\":").Append(CampaignTime.Now.ToDays.ToString("F3", System.Globalization.CultureInfo.InvariantCulture));
        return json.Append('}').ToString();
    }

    internal static string BuildHarnessDiagnosticsJson()
    {
        RequireCampaignMap();
        var party = MobileParty.MainParty;
        var json = new StringBuilder(1800);
        json.Append('{').Append("\"schemaVersion\":1");
        ChroniclePartyUpgradeAdapter.Property(json, "partyId", party.StringId);
        json.Append(",\"maximumPartyRoleAssignmentCount\":").Append(Campaign.Current.Models.ClanMemberPartyRoleModel.MaximumPartyRoleAssignmentCount);
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlMode", Campaign.Current.TimeControlMode.ToString());
        json.Append(",\"campaignDay\":").Append(CampaignTime.Now.ToDays.ToString("F3", System.Globalization.CultureInfo.InvariantCulture));
        json.Append(",\"gold\":").Append(Hero.MainHero.Gold);
        json.Append(",\"memberCount\":").Append(party.MemberRoster.TotalManCount);
        json.Append(",\"roles\":[");
        var first = true;
        foreach (var role in Campaign.Current.Models.ClanMemberPartyRoleModel.GetAssignablePartyRoles())
        {
            if (!first) json.Append(',');
            first = false;
            var holder = party.GetRoleHolder(role);
            var effective = GetEffectiveHolder(party, role);
            json.Append('{');
            ChroniclePartyUpgradeAdapter.Property(json, "roleId", role.ToString(), addComma: false);
            ChroniclePartyUpgradeAdapter.Property(json, "assignedHeroId", holder?.StringId);
            ChroniclePartyUpgradeAdapter.Property(json, "effectiveHeroId", effective?.StringId);
            json.Append('}');
        }
        json.Append("]}");
        return json.ToString();
    }

    private static MBBindingList<ClanRoleItemVM> BuildNativeRoleViewModels(MobileParty party)
    {
        var members = new MBBindingList<ClanPartyMemberItemVM>();
        foreach (var element in party.MemberRoster.GetTroopRoster())
        {
            var hero = element.Character?.HeroObject;
            if (hero == null || hero.Clan != Clan.PlayerClan || hero.GovernorOf != null) continue;
            members.Add(new ClanPartyMemberItemVM(hero, party));
        }

        var roles = new MBBindingList<ClanRoleItemVM>();
        Action refreshAll = () => roles.ApplyActionOnAllItems(item => item.Refresh());
        foreach (var role in Campaign.Current.Models.ClanMemberPartyRoleModel.GetAssignablePartyRoles())
            roles.Add(new ClanRoleItemVM(party, role, members, _ => { }, refreshAll));
        return roles;
    }

    private static string BuildSnapshotJson(MobileParty party, MBBindingList<ClanRoleItemVM> roles)
    {
        var json = new StringBuilder(3072);
        json.Append('{').Append("\"schemaVersion\":1");
        ChroniclePartyUpgradeAdapter.Property(json, "partyId", party.StringId);
        json.Append(",\"maximumPartyRoleAssignmentCount\":").Append(Campaign.Current.Models.ClanMemberPartyRoleModel.MaximumPartyRoleAssignmentCount);
        json.Append(",\"roles\":[");
        var firstRole = true;
        foreach (var role in roles)
        {
            if (!firstRole) json.Append(',');
            firstRole = false;
            var effectiveHero = role.EffectiveOwner?.Member?.HeroObject;
            json.Append('{');
            ChroniclePartyUpgradeAdapter.Property(json, "roleId", role.Role.ToString(), addComma: false);
            ChroniclePartyUpgradeAdapter.Property(json, "roleName", role.Name);
            json.Append(",\"isAssigned\":").Append(ChroniclePartyUpgradeAdapter.Bool(!role.IsNotAssigned));
            ChroniclePartyUpgradeAdapter.Property(json, "assignedHeroId", party.GetRoleHolder(role.Role)?.StringId);
            ChroniclePartyUpgradeAdapter.Property(json, "effectiveHeroId", effectiveHero?.StringId);
            ChroniclePartyUpgradeAdapter.Property(json, "effectsText", role.AssignedMemberEffects);
            json.Append(",\"candidates\":[");
            var firstCandidate = true;
            foreach (var candidate in role.Members.Where(item => item?.Member?.HeroObject != null))
            {
                if (!firstCandidate) json.Append(',');
                firstCandidate = false;
                var hero = candidate.Member.HeroObject;
                json.Append('{');
                ChroniclePartyUpgradeAdapter.Property(json, "heroId", hero.StringId, addComma: false);
                ChroniclePartyUpgradeAdapter.Property(json, "name", hero.Name?.ToString());
                ChroniclePartyUpgradeAdapter.Property(json, "relevantSkillId", candidate.RelevantSkill?.StringId);
                json.Append(",\"relevantSkillValue\":").Append(candidate.RelevantSkillValue);
                json.Append('}');
            }
            json.Append("]}");
        }
        return json.Append("]}").ToString();
    }

    private static PartyRole ParseSupportedRole(string roleId)
    {
        if (string.IsNullOrWhiteSpace(roleId)) throw new InvalidOperationException("roleId is required");
        var parsed = SupportedRoles.FirstOrDefault(role => string.Equals(role.ToString(), roleId, StringComparison.OrdinalIgnoreCase));
        if (!SupportedRoles.Contains(parsed) || !Campaign.Current.Models.ClanMemberPartyRoleModel.GetAssignablePartyRoles().Contains(parsed))
            throw new InvalidOperationException("Role is not available in the current native ClanMemberPartyRoleModel");
        return parsed;
    }

    private static Hero GetEffectiveHolder(MobileParty party, PartyRole role)
    {
        return role switch
        {
            PartyRole.Quartermaster => party.EffectiveQuartermaster,
            PartyRole.Scout => party.EffectiveScout,
            PartyRole.Surgeon => party.EffectiveSurgeon,
            PartyRole.Engineer => party.EffectiveEngineer,
            _ => null
        };
    }

    private static void RequireCampaignMap()
    {
        if (Game.Current?.GameStateManager?.ActiveState is not MapState || Campaign.Current == null || Clan.PlayerClan == null || MobileParty.MainParty == null)
            throw new InvalidOperationException("Party role actions require Campaign Map, PlayerClan and MainParty");
    }

    private static void Finalize(MBBindingList<ClanRoleItemVM> roles)
    {
        roles?.ApplyActionOnAllItems(item => item.OnFinalize());
    }
}
