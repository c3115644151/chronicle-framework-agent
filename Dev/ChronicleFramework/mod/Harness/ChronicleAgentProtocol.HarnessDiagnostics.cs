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
    private static string BuildHarnessMissionDiagnosticsJson(Mission mission)
    {
        var mainAgent = mission?.MainAgent;
        var currentCampaignLocation = CampaignMission.Current?.Location;
        var missionAgents = mission == null ? Enumerable.Empty<Agent>() : mission.Agents.AsEnumerable();
        var notables = missionAgents
            .Where(agent => agent != null && agent.IsActive() && agent.IsHuman && agent != mainAgent)
            .Select(agent => new { Agent = agent, Character = agent.Character as CharacterObject, Hero = (agent.Character as CharacterObject)?.HeroObject })
            .Where(item => item.Hero != null && item.Hero.IsNotable)
            .Select(item => new
            {
                item.Agent,
                item.Character,
                item.Hero,
                Distance = mainAgent == null ? (double?)null : Math.Sqrt(
                    Math.Pow(mainAgent.Position.X - item.Agent.Position.X, 2) +
                    Math.Pow(mainAgent.Position.Y - item.Agent.Position.Y, 2) +
                    Math.Pow(mainAgent.Position.Z - item.Agent.Position.Z, 2))
            })
            .OrderBy(item => item.Distance ?? double.MaxValue)
            .ToArray();
        var locationIssueOwners = currentCampaignLocation == null
            ? Array.Empty<Hero>()
            : currentCampaignLocation.GetCharacterList()
                .Where(locationCharacter => locationCharacter?.Character?.HeroObject?.Issue != null)
                .Select(locationCharacter => locationCharacter.Character.HeroObject)
                .Distinct()
                .OrderBy(hero => hero.StringId, StringComparer.Ordinal)
                .ToArray();
        var activeHeroAgents = missionAgents
            .Where(agent => agent != null && agent.IsActive() && agent.IsHuman)
            .Select(agent => new { Agent = agent, Character = agent.Character as CharacterObject, Hero = (agent.Character as CharacterObject)?.HeroObject })
            .Where(item => item.Hero != null)
            .Select(item => new
            {
                item.Agent,
                item.Character,
                item.Hero,
                Distance = mainAgent == null ? (double?)null : Math.Sqrt(
                    Math.Pow(mainAgent.Position.X - item.Agent.Position.X, 2) +
                    Math.Pow(mainAgent.Position.Y - item.Agent.Position.Y, 2) +
                    Math.Pow(mainAgent.Position.Z - item.Agent.Position.Z, 2)),
                LocationId = Settlement.CurrentSettlement?.LocationComplex?.GetLocationOfCharacter(item.Hero)?.StringId
            })
            .OrderBy(item => item.Distance ?? double.MaxValue)
            .ToArray();

        var json = new StringBuilder(1024);
        json.Append('{');
        json.Append("\"sceneName\":\"").Append(Escape(mission.SceneName)).Append('"');
        json.Append(",\"campaignLocationId\":\"").Append(Escape(currentCampaignLocation?.StringId)).Append('"');
        json.Append(",\"activeAgentCount\":").Append(mission.Agents.Count(agent => agent != null && agent.IsActive()));
        json.Append(",\"notableAgentCount\":").Append(notables.Length);
        json.Append(",\"issueNotableCount\":").Append(notables.Count(item => item.Hero.Issue != null));
        json.Append(",\"notableAgents\":[");
        for (var index = 0; index < notables.Length; index++)
        {
            if (index > 0) json.Append(',');
            var item = notables[index];
            json.Append('{');
            json.Append("\"agentIndex\":").Append(item.Agent.Index);
            json.Append(",\"characterId\":\"").Append(Escape(item.Character?.StringId)).Append('"');
            json.Append(",\"heroId\":\"").Append(Escape(item.Hero.StringId)).Append('"');
            json.Append(",\"name\":\"").Append(Escape(item.Hero.Name?.ToString())).Append('"');
            json.Append(",\"occupation\":\"").Append(Escape(item.Hero.Occupation.ToString())).Append('"');
            json.Append(",\"hasIssue\":").Append(item.Hero.Issue != null ? "true" : "false");
            json.Append(",\"issueType\":\"").Append(Escape(item.Hero.Issue?.GetType().Name)).Append('"');
            json.Append(",\"distance\":").Append(item.Distance.HasValue ? item.Distance.Value.ToString("R", CultureInfo.InvariantCulture) : "null");
            json.Append(",\"position\":{\"x\":").Append(item.Agent.Position.X.ToString("R", CultureInfo.InvariantCulture));
            json.Append(",\"y\":").Append(item.Agent.Position.Y.ToString("R", CultureInfo.InvariantCulture));
            json.Append(",\"z\":").Append(item.Agent.Position.Z.ToString("R", CultureInfo.InvariantCulture)).Append("}}");
        }
        json.Append(']');
        json.Append(",\"activeHeroAgents\":[");
        for (var index = 0; index < activeHeroAgents.Length; index++)
        {
            if (index > 0) json.Append(',');
            var item = activeHeroAgents[index];
            json.Append('{');
            json.Append("\"agentIndex\":").Append(item.Agent.Index);
            json.Append(",\"characterId\":\"").Append(Escape(item.Character?.StringId)).Append('"');
            json.Append(",\"heroId\":\"").Append(Escape(item.Hero.StringId)).Append('"');
            json.Append(",\"name\":\"").Append(Escape(item.Hero.Name?.ToString())).Append('"');
            json.Append(",\"isNotable\":").Append(item.Hero.IsNotable ? "true" : "false");
            json.Append(",\"locationId\":\"").Append(Escape(item.LocationId)).Append('"');
            json.Append(",\"distance\":").Append(item.Distance.HasValue ? item.Distance.Value.ToString("R", CultureInfo.InvariantCulture) : "null");
            json.Append('}');
        }
        json.Append(']');
        json.Append(",\"locationIssueOwnerCount\":").Append(locationIssueOwners.Length);
        json.Append(",\"locationIssueOwners\":[");
        for (var index = 0; index < locationIssueOwners.Length; index++)
        {
            if (index > 0) json.Append(',');
            var hero = locationIssueOwners[index];
            json.Append('{');
            json.Append("\"heroId\":\"").Append(Escape(hero.StringId)).Append('"');
            json.Append(",\"name\":\"").Append(Escape(hero.Name?.ToString())).Append('"');
            json.Append(",\"isNotable\":").Append(hero.IsNotable ? "true" : "false");
            json.Append(",\"issueType\":\"").Append(Escape(hero.Issue?.GetType().Name)).Append('"');
            json.Append('}');
        }
        json.Append(']');
        json.Append('}');
        return json.ToString();
    }

    private static string BuildHarnessMapDiagnosticsJson(string targetHeroId = null)
    {
        var activeMapState = Game.Current?.GameStateManager?.ActiveState as MapState;
        var escapeMenuOpen = MapScreen.Instance?.IsEscapeMenuOpened ?? false;
        var settlements = Settlement.All
            .Where(settlement => settlement != null && settlement.IsActive)
            .OrderBy(settlement => settlement.StringId, StringComparer.Ordinal)
            .ToArray();
        var json = new StringBuilder(2048);
        json.Append('{').Append("\"mapStateAtMenu\":").Append((activeMapState?.AtMenu ?? false).ToString().ToLowerInvariant());
        json.Append(",\"escapeMenuOpen\":").Append(escapeMenuOpen.ToString().ToLowerInvariant());
        json.Append(",\"harnessFocusLossEscapeMenuGuardInstalled\":").Append(SubModule.HarnessFocusLossEscapeMenuGuardInstalled.ToString().ToLowerInvariant());
        json.Append(",\"activeSettlementCount\":").Append(settlements.Length);
        json.Append(",\"visibleSettlementCount\":").Append(settlements.Count(settlement => settlement.IsVisible));
        json.Append(",\"hiddenSettlementCount\":").Append(settlements.Count(settlement => !settlement.IsVisible));
        json.Append(",\"settlements\":[");
        for (var index = 0; index < settlements.Length; index++)
        {
            if (index > 0) json.Append(',');
            var settlement = settlements[index];
            json.Append('{');
            json.Append("\"id\":\"").Append(Escape(settlement.StringId)).Append('"');
            json.Append(",\"name\":\"").Append(Escape(settlement.Name?.ToString())).Append('"');
            var settlementType = settlement.IsTown ? "town" : settlement.IsCastle ? "castle" : settlement.IsVillage ? "village" : settlement.IsHideout ? "hideout" : "other";
            json.Append(",\"type\":\"").Append(settlementType).Append('"');
            json.Append(",\"isVisible\":").Append(settlement.IsVisible ? "true" : "false");
            json.Append(",\"isInspected\":").Append(settlement.IsInspected ? "true" : "false");
            json.Append('}');
        }
        json.Append("],\"issueGateProbe\":");
        if (string.IsNullOrWhiteSpace(targetHeroId))
        {
            json.Append("null");
        }
        else
        {
            var targetHero = Hero.AllAliveHeroes.FirstOrDefault(hero => hero != null && string.Equals(hero.StringId, targetHeroId, StringComparison.Ordinal));
            var targetIssue = targetHero?.Issue;
            var sameTypeIssues = targetIssue == null
                ? Array.Empty<KeyValuePair<Hero, IssueBase>>()
                : Campaign.Current.IssueManager.Issues.Where(pair => pair.Value != null && pair.Value.GetType() == targetIssue.GetType()).OrderBy(pair => pair.Key?.StringId, StringComparer.Ordinal).ToArray();
            json.Append('{');
            json.Append("\"targetHeroId\":\"").Append(Escape(targetHeroId)).Append('"');
            json.Append(",\"targetHeroFound\":").Append(ChroniclePartyUpgradeAdapter.Bool(targetHero != null));
            json.Append(",\"targetHasIssue\":").Append(ChroniclePartyUpgradeAdapter.Bool(targetIssue != null));
            json.Append(",\"targetIssueType\":\"").Append(Escape(targetIssue?.GetType().FullName)).Append('"');
            json.Append(",\"targetIssueId\":\"").Append(Escape(targetIssue?.StringId)).Append('"');
            json.Append(",\"relationToPlayer\":").Append(targetHero == null ? "null" : targetHero.GetRelationWithPlayer().ToString("R", CultureInfo.InvariantCulture));
            json.Append(",\"atWarWithPlayerFaction\":").Append(ChroniclePartyUpgradeAdapter.Bool(targetHero?.MapFaction != null && targetHero.MapFaction.IsAtWarWith(Hero.MainHero.MapFaction)));
            json.Append(",\"sameTypeIssueCount\":").Append(sameTypeIssues.Length);
            json.Append(",\"sameTypeIssues\":[");
            for (var index = 0; index < sameTypeIssues.Length; index++)
            {
                if (index > 0) json.Append(',');
                var pair = sameTypeIssues[index];
                json.Append('{');
                json.Append("\"ownerHeroId\":\"").Append(Escape(pair.Key?.StringId)).Append('"');
                json.Append(",\"issueId\":\"").Append(Escape(pair.Value.StringId)).Append('"');
                json.Append(",\"isOngoingWithoutQuest\":").Append(ChroniclePartyUpgradeAdapter.Bool(pair.Value.IsOngoingWithoutQuest));
                json.Append(",\"isSolvingWithQuest\":").Append(ChroniclePartyUpgradeAdapter.Bool(pair.Value.IsSolvingWithQuest));
                json.Append(",\"isSolvingWithAlternative\":").Append(ChroniclePartyUpgradeAdapter.Bool(pair.Value.IsSolvingWithAlternative));
                json.Append(",\"isSolvingWithLord\":").Append(ChroniclePartyUpgradeAdapter.Bool(pair.Value.IsSolvingWithLordSolution));
                json.Append('}');
            }
            json.Append("]}");
        }
        json.Append('}');
        return json.ToString();
    }

    private static string BuildHarnessPlayerSkillsDiagnosticsJson()
    {
        var hero = Hero.MainHero;
        var skills = TaleWorlds.CampaignSystem.Extensions.Skills.All
            .Where(skill => skill != null)
            .OrderBy(skill => skill.StringId, StringComparer.Ordinal)
            .ToArray();
        var json = new StringBuilder(1024);
        json.Append('{');
        json.Append("\"heroId\":\"").Append(Escape(hero?.StringId)).Append('"');
        json.Append(",\"skills\":[");
        for (var index = 0; index < skills.Length; index++)
        {
            if (index > 0) json.Append(',');
            var skill = skills[index];
            json.Append('{');
            json.Append("\"id\":\"").Append(Escape(skill.StringId)).Append('"');
            json.Append(",\"level\":").Append(hero.GetSkillValue(skill));
            json.Append('}');
        }
        json.Append("]}");
        return json.ToString();
    }

    private static string BuildHarnessCharacterDevelopmentDiagnosticsJson()
    {
        var hero = Hero.MainHero;
        if (hero == null) throw new InvalidOperationException("MainHero is unavailable");
        var viewModel = new TaleWorlds.CampaignSystem.ViewModelCollection.CharacterDeveloper.CharacterDeveloperHeroItemVM(hero, () => { });
        var json = new StringBuilder(4096);
        json.Append('{');
        json.Append("\"heroId\":\"").Append(Escape(hero.StringId)).Append('"');
        json.Append(",\"level\":").Append(hero.Level);
        json.Append(",\"currentTotalXp\":").Append(viewModel.CurrentTotalXp);
        json.Append(",\"xpRequiredForNextLevel\":").Append(viewModel.XpRequiredForNextLevel);
        json.Append(",\"unspentFocusPoints\":").Append(viewModel.UnspentCharacterPoints);
        json.Append(",\"unspentAttributePoints\":").Append(viewModel.UnspentAttributePoints);
        json.Append(",\"attributes\":[");
        for (var index = 0; index < viewModel.Attributes.Count; index++)
        {
            if (index > 0) json.Append(',');
            var attribute = viewModel.Attributes[index];
            json.Append('{');
            json.Append("\"id\":\"").Append(Escape(attribute.AttributeType.StringId)).Append('"');
            json.Append(",\"name\":\"").Append(Escape(attribute.Name)).Append('"');
            json.Append(",\"value\":").Append(attribute.AttributeValue).Append('}');
        }
        json.Append(']');
        json.Append(",\"skills\":[");
        for (var index = 0; index < viewModel.Skills.Count; index++)
        {
            if (index > 0) json.Append(',');
            var skill = viewModel.Skills[index];
            json.Append('{');
            json.Append("\"id\":\"").Append(Escape(skill.SkillId)).Append('"');
            json.Append(",\"name\":\"").Append(Escape(skill.NameText)).Append('"');
            json.Append(",\"level\":").Append(skill.Level);
            json.Append(",\"experienceProgress\":").Append(skill.CurrentSkillXP);
            json.Append(",\"experienceRequiredForNextLevel\":").Append(skill.XpRequiredForNextLevel);
            json.Append(",\"focus\":").Append(skill.CurrentFocusLevel);
            json.Append(",\"learningRate\":").Append(skill.LearningRate.ToString("R", CultureInfo.InvariantCulture));
            json.Append(",\"learningLimit\":").Append(skill.FullLearningRateLevel);
            json.Append(",\"canAddFocus\":").Append(skill.CanAddFocus ? "true" : "false");
            json.Append(",\"unopenedPerks\":").Append(skill.NumOfUnopenedPerks);
            json.Append(",\"perks\":[");
            for (var perkIndex = 0; perkIndex < skill.Perks.Count; perkIndex++)
            {
                if (perkIndex > 0) json.Append(',');
                var perk = skill.Perks[perkIndex];
                json.Append('{');
                json.Append("\"id\":\"").Append(Escape(perk.Perk.StringId)).Append('"');
                json.Append(",\"requiredSkillLevel\":").Append(perk.Level);
                json.Append(",\"alternativeId\":");
                if (perk.Perk.AlternativePerk == null) json.Append("null");
                else json.Append('"').Append(Escape(perk.Perk.AlternativePerk.StringId)).Append('"');
                json.Append(",\"state\":").Append(perk.PerkState);
                json.Append(",\"alternativeType\":").Append(perk.AlternativeType).Append('}');
            }
            json.Append("]}");
        }
        json.Append("]}");
        return json.ToString();
    }

    private static string BuildHarnessQuestDetailsDiagnosticsJson(QuestBase quest)
    {
        if (quest == null) throw new InvalidOperationException("Active observed Quest is unavailable");
        var viewModel = new TaleWorlds.CampaignSystem.ViewModelCollection.Quests.QuestItemVM(quest, _ => { });
        var json = new StringBuilder(2048);
        json.Append('{');
        json.Append("\"questId\":\"").Append(Escape(quest.StringId)).Append('"');
        json.Append(",\"title\":\"").Append(Escape(viewModel.Name)).Append('"');
        json.Append(",\"isSpecialQuest\":").Append(quest.IsSpecialQuest ? "true" : "false");
        json.Append(",\"isTracked\":").Append(viewModel.IsTracked ? "true" : "false");
        json.Append(",\"questGiverHidden\":").Append(viewModel.IsQuestGiverHeroHidden ? "true" : "false");
        json.Append(",\"questGiverId\":");
        if (quest.QuestGiver == null) json.Append("null");
        else json.Append('"').Append(Escape(quest.QuestGiver.StringId)).Append('"');
        json.Append(",\"questGiverName\":");
        if (quest.QuestGiver == null) json.Append("null");
        else json.Append('"').Append(Escape(quest.QuestGiver.Name?.ToString())).Append('"');
        json.Append(",\"isRemainingTimeHidden\":").Append(viewModel.IsRemainingDaysHidden ? "true" : "false");
        json.Append(",\"daysRemaining\":");
        if (viewModel.IsRemainingDaysHidden) json.Append("null");
        else json.Append(viewModel.RemainingDays);
        json.Append(",\"journalStages\":[");
        for (var index = 0; index < viewModel.Stages.Count; index++)
        {
            if (index > 0) json.Append(',');
            var stage = viewModel.Stages[index];
            json.Append('{');
            json.Append("\"logType\":\"").Append(Escape(stage.Log?.Type.ToString())).Append('"');
            json.Append(",\"dateText\":\"").Append(Escape(stage.DateText)).Append('"');
            json.Append(",\"description\":\"").Append(Escape(stage.DescriptionText)).Append('"');
            json.Append(",\"isLastStage\":").Append(stage.IsLastStage ? "true" : "false");
            json.Append(",\"hasTask\":").Append(stage.HasATask ? "true" : "false");
            if (stage.HasATask)
            {
                json.Append(",\"rawTaskName\":");
                if (stage.Log?.TaskName == null) json.Append("null");
                else json.Append('"').Append(Escape(stage.Log.TaskName.ToString())).Append('"');
                json.Append(",\"taskName\":\"").Append(Escape(stage.StageTask.TaskName)).Append('"');
                json.Append(",\"currentProgress\":").Append(stage.StageTask.CurrentProgress);
                json.Append(",\"targetProgress\":").Append(stage.StageTask.TargetProgress);
                json.Append(",\"progressType\":\"").Append(Escape(((LogType)stage.StageTask.ProgressType).ToString())).Append('"');
                json.Append(",\"isTaskCompleted\":").Append(stage.IsTaskCompleted ? "true" : "false");
            }
            json.Append('}');
        }
        json.Append("]}");
        return json.ToString();
    }

    private static string BuildHarnessQuestDeadlinePrivacyDiagnosticsJson()
    {
        var json = new StringBuilder(128);
        json.Append('{').Append("\"hidden\":{\"available\":true");
        ChronicleAgentObserver.AppendQuestDeadline(json, true, 14);
        json.Append("},\"visible\":{\"available\":true");
        ChronicleAgentObserver.AppendQuestDeadline(json, false, 14);
        json.Append("}}");
        return json.ToString();
    }

    private static string BuildHarnessPartyRosterDiagnosticsJson()
    {
        var party = MobileParty.MainParty;
        if (party == null) throw new InvalidOperationException("MainParty is unavailable");
        var members = party.MemberRoster.GetTroopRoster()
            .Where(element => element.Character != null && element.Number > 0)
            .OrderBy(element => element.Character.StringId, StringComparer.Ordinal)
            .ToArray();
        var prisoners = party.PrisonRoster.GetTroopRoster()
            .Where(element => element.Character != null && element.Number > 0)
            .OrderBy(element => element.Character.StringId, StringComparer.Ordinal)
            .ToArray();
        var json = new StringBuilder(4096);
        json.Append('{');
        json.Append("\"partyId\":\"").Append(Escape(party.StringId)).Append('"');
        json.Append(",\"members\":");
        AppendHarnessRosterDiagnostics(json, members);
        json.Append(",\"prisoners\":");
        AppendHarnessRosterDiagnostics(json, prisoners);
        json.Append(",\"memberTotals\":{");
        json.Append("\"totalCount\":").Append(party.MemberRoster.TotalManCount);
        json.Append(",\"healthyCount\":").Append(party.MemberRoster.TotalHealthyCount);
        json.Append(",\"woundedCount\":").Append(party.MemberRoster.TotalWounded);
        json.Append(",\"sizeLimit\":").Append(party.Party.PartySizeLimit).Append('}');
        json.Append(",\"prisonerTotals\":{");
        json.Append("\"totalCount\":").Append(party.PrisonRoster.TotalManCount);
        json.Append(",\"healthyCount\":").Append(party.PrisonRoster.TotalHealthyCount);
        json.Append(",\"woundedCount\":").Append(party.PrisonRoster.TotalWounded);
        json.Append(",\"sizeLimit\":").Append(party.Party.PrisonerSizeLimit).Append('}');
        json.Append('}');
        return json.ToString();
    }

    private static string BuildCompanionHiringDiagnosticsJson(string heroId)
    {
        if (string.IsNullOrWhiteSpace(heroId)) throw new InvalidOperationException("Companion hiring diagnostics requires a HeroId");
        var candidate = Hero.AllAliveHeroes.FirstOrDefault(hero => hero != null && string.Equals(hero.StringId, heroId, StringComparison.Ordinal));
        if (candidate == null) throw new InvalidOperationException("Companion hiring diagnostics could not find the live Hero");
        var playerClan = Clan.PlayerClan;
        var memberIndex = MobileParty.MainParty?.MemberRoster?.FindIndexOfTroop(candidate.CharacterObject) ?? -1;
        var inMainParty = memberIndex >= 0;
        var json = new StringBuilder(768);
        json.Append('{');
        json.Append("\"heroId\":\"").Append(Escape(candidate.StringId)).Append('"');
        json.Append(",\"nativeHiringPrice\":").Append(Campaign.Current.Models.CompanionHiringPriceCalculationModel.GetCompanionHiringPrice(candidate));
        json.Append(",\"playerGold\":").Append(Hero.MainHero.Gold);
        json.Append(",\"playerCompanionCount\":").Append(playerClan.Companions.Count);
        json.Append(",\"companionLimit\":").Append(playerClan.CompanionLimit);
        json.Append(",\"isPlayerCompanion\":").Append(candidate.IsPlayerCompanion ? "true" : "false");
        json.Append(",\"isInPlayerClan\":").Append(candidate.Clan == playerClan ? "true" : "false");
        json.Append(",\"clanId\":\"").Append(Escape(candidate.Clan?.StringId)).Append('"');
        json.Append(",\"isInMainParty\":").Append(inMainParty ? "true" : "false");
        json.Append(",\"partyId\":\"").Append(Escape(candidate.PartyBelongedTo?.StringId)).Append('"');
        json.Append('}');
        return json.ToString();
    }

    private static void AddDiagnosticRosterRows(
        System.Collections.Generic.Dictionary<string, (TaleWorlds.CampaignSystem.CharacterObject Character, int Total, int Wounded)> rows,
        TaleWorlds.CampaignSystem.Roster.TroopRoster roster)
    {
        for (var index = 0; index < roster.Count; index++)
        {
            var element = roster.GetElementCopyAtIndex(index);
            if (element.Character == null || element.Number <= 0) continue;
            var id = element.Character.StringId;
            if (rows.TryGetValue(id, out var current))
                rows[id] = (current.Character, current.Total + element.Number, current.Wounded + element.WoundedNumber);
            else
                rows[id] = (element.Character, element.Number, element.WoundedNumber);
        }
    }

    private static void AppendHarnessPartyRosterRows(
        StringBuilder json,
        System.Collections.Generic.Dictionary<string, (TaleWorlds.CampaignSystem.CharacterObject Character, int Total, int Wounded)> rows)
    {
        json.Append('[');
        var first = true;
        foreach (var row in rows.OrderBy(item => item.Key, StringComparer.Ordinal))
        {
            if (!first) json.Append(',');
            first = false;
            json.Append('{');
            json.Append("\"characterId\":\"").Append(Escape(row.Key)).Append('"');
            json.Append(",\"name\":\"").Append(Escape(row.Value.Character.Name?.ToString())).Append('"');
            json.Append(",\"totalCount\":").Append(row.Value.Total);
            json.Append(",\"healthyCount\":").Append(Math.Max(row.Value.Total - row.Value.Wounded, 0));
            json.Append(",\"woundedCount\":").Append(row.Value.Wounded);
            json.Append(",\"isHero\":").Append(row.Value.Character.IsHero ? "true" : "false");
            json.Append('}');
        }
        json.Append(']');
    }

    private static void AppendHarnessRosterDiagnostics(StringBuilder json, TaleWorlds.CampaignSystem.Roster.TroopRosterElement[] elements)
    {
        json.Append('[');
        for (var index = 0; index < elements.Length; index++)
        {
            if (index > 0) json.Append(',');
            var element = elements[index];
            var character = element.Character;
            json.Append('{');
            json.Append("\"characterId\":\"").Append(Escape(character.StringId)).Append('"');
            json.Append(",\"name\":\"").Append(Escape(character.Name?.ToString())).Append('"');
            json.Append(",\"tier\":").Append(character.Tier);
            json.Append(",\"count\":").Append(element.Number);
            json.Append(",\"woundedCount\":").Append(element.WoundedNumber);
            json.Append(",\"healthyCount\":").Append(Math.Max(element.Number - element.WoundedNumber, 0));
            json.Append(",\"isHero\":").Append(character.IsHero ? "true" : "false");
            json.Append(",\"isHeroWounded\":").Append(character.IsHero && character.HeroObject != null && character.HeroObject.IsWounded ? "true" : "false");
            json.Append('}');
        }
        json.Append(']');
    }

    private static string BuildHarnessMapPartyDiagnosticsJson()
    {
        var mainParty = MobileParty.MainParty;
        if (mainParty == null) throw new InvalidOperationException("MainParty is unavailable");
        var managerType = AppDomain.CurrentDomain.GetAssemblies()
            .Select(assembly => assembly.GetType("SandBox.View.Map.Managers.MobilePartyVisualManager", throwOnError: false))
            .FirstOrDefault(type => type != null);
        var manager = managerType?.GetProperty("Current", System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Static)?.GetValue(null);
        var getPartyVisual = managerType?.GetMethod("GetPartyVisual", System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance);
        if (manager == null || getPartyVisual == null) throw new InvalidOperationException("Native MobilePartyVisualManager is unavailable for map target diagnostics");
        var displayHelperType = AppDomain.CurrentDomain.GetAssemblies()
            .Select(assembly => assembly.GetType("SandBox.ViewModelCollection.SandBoxUIHelper", throwOnError: false))
            .FirstOrDefault(type => type != null);
        var healthyCountMethod = displayHelperType?.GetMethod("GetPartyHealthyCount", System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Static);
        var woundedCountMethod = displayHelperType?.GetMethod("GetAllWoundedMembersAmount", System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Static);
        var prisonerCountMethod = displayHelperType?.GetMethod("GetAllPrisonerMembersAmount", System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Static);
        if (healthyCountMethod == null || woundedCountMethod == null || prisonerCountMethod == null) throw new InvalidOperationException("Native PartyNameplate count helpers are unavailable for map target diagnostics");

        var candidates = MobileParty.All
            .Where(party => party != null && party != mainParty && party.IsActive && !party.IsGarrison && !party.IsMilitia)
            .OrderBy(party => party.StringId, StringComparer.Ordinal)
            .ToArray();
        var position = mainParty.GetPosition2D;
        var json = new StringBuilder(4096);
        json.Append('{');
        json.Append("\"activePartyEntityCount\":").Append(candidates.Length);
        json.Append(",\"mapPartyEntities\":[");
        for (var index = 0; index < candidates.Length; index++)
        {
            if (index > 0) json.Append(',');
            var party = candidates[index];
            var visual = getPartyVisual.Invoke(manager, new object[] { party.Party });
            var attachedTo = party.AttachedTo;
            var isNativeMarkerCandidate = party.Party.IsVisible && attachedTo == null;
            var visibleOrFading = (bool)(visual.GetType().GetMethod("IsVisibleOrFadingOut", System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance)?.Invoke(visual, null) ?? false);
            var healthy = (int)healthyCountMethod.Invoke(null, new object[] { party });
            var wounded = (int)woundedCountMethod.Invoke(null, new object[] { party });
            var prisoners = (int)prisonerCountMethod.Invoke(null, new object[] { party });
            var partyPosition = party.GetPosition2D;
            var distanceX = position.X - partyPosition.X;
            var distanceY = position.Y - partyPosition.Y;
            var distance = Math.Sqrt(distanceX * distanceX + distanceY * distanceY);
            json.Append('{');
            json.Append("\"id\":\"").Append(Escape(party.StringId)).Append('"');
            json.Append(",\"mapFactionId\":\"").Append(Escape(party.MapFaction?.StringId)).Append('"');
            var partyName = party.Army != null && party.Army.DoesLeaderPartyAndAttachedPartiesContain(party) ? party.ArmyName?.ToString() : party.LeaderHero?.Name?.ToString() ?? party.Name?.ToString();
            json.Append(",\"nameplateName\":\"").Append(Escape(partyName)).Append('"');
            json.Append(",\"type\":\"").Append(Escape(ChronicleAgentObserver.GetPartyTypeForObservation(party))).Append('"');
            json.Append(",\"isActive\":true");
            json.Append(",\"isGarrison\":false,\"isMilitia\":false");
            json.Append(",\"partyBaseIsVisible\":").Append(party.Party.IsVisible ? "true" : "false");
            json.Append(",\"mobilePartyIsVisible\":").Append(party.IsVisible ? "true" : "false");
            json.Append(",\"isInspected\":").Append(party.IsInspected ? "true" : "false");
            json.Append(",\"isInfoHidden\":").Append(party.IsInfoHidden ? "true" : "false");
            json.Append(",\"attachedToLeader\":").Append(attachedTo == null ? "null" : "\"" + Escape(attachedTo.StringId) + "\"");
            json.Append(",\"isNativeMarkerCandidate\":").Append(isNativeMarkerCandidate ? "true" : "false");
            json.Append(",\"nativeVisualVisibleOrFading\":").Append(visibleOrFading ? "true" : "false");
            json.Append(",\"distance\":").Append(distance.ToString("F3", CultureInfo.InvariantCulture));
            json.Append(",\"defaultBehavior\":\"").Append(Escape(party.DefaultBehavior.ToString())).Append('"');
            json.Append(",\"moveMode\":\"").Append(Escape(party.PartyMoveMode.ToString())).Append('"');
            json.Append(",\"doNotAttackMainPartyRemainingHours\":").Append((party.Ai?.DoNotAttackMainPartyUntil.RemainingHoursFromNow ?? 0f).ToString("F3", CultureInfo.InvariantCulture));
            json.Append(",\"nameplateHealthyCount\":").Append(healthy);
            json.Append(",\"nameplateWoundedCount\":").Append(wounded);
            json.Append(",\"nameplatePrisonerCount\":").Append(prisoners);
            json.Append('}');
        }
        json.Append("]}");
        return json.ToString();
    }

    private static string BuildHarnessMapPartyCompositionDiagnosticsJson(string partyId)
    {
        var mainParty = MobileParty.MainParty;
        var party = MobileParty.All.FirstOrDefault(item => item != null && string.Equals(item.StringId, partyId, StringComparison.Ordinal));
        if (mainParty == null || party == null || party == mainParty || !party.IsActive || party.IsGarrison || party.IsMilitia || party.AttachedTo != null || !party.Party.IsVisible)
            throw new InvalidOperationException("Harness Party composition diagnostic requires a current visible independent map party");

        var isArmyLeader = party.Army != null && party.Army.LeaderParty == party;
        var rosterParties = isArmyLeader ? new[] { party }.Concat(party.AttachedParties).ToArray() : new[] { party };
        var partyRows = new System.Collections.Generic.Dictionary<string, (TaleWorlds.CampaignSystem.CharacterObject Character, int Total, int Wounded)>(StringComparer.Ordinal);
        var prisonerRows = new System.Collections.Generic.Dictionary<string, (TaleWorlds.CampaignSystem.CharacterObject Character, int Total, int Wounded)>(StringComparer.Ordinal);
        foreach (var rosterParty in rosterParties)
        {
            AddDiagnosticRosterRows(partyRows, rosterParty.MemberRoster);
            AddDiagnosticRosterRows(prisonerRows, rosterParty.PrisonRoster);
        }

        var tooltipType = isArmyLeader ? typeof(Army) : typeof(MobileParty);
        var tooltipArguments = new object[] { isArmyLeader ? (object)party.Army : party, false, true };
        var tooltipVmType = AppDomain.CurrentDomain.GetAssemblies()
            .Select(assembly => assembly.GetType("TaleWorlds.Core.ViewModelCollection.Information.PropertyBasedTooltipVM", throwOnError: false))
            .FirstOrDefault(type => type != null);
        if (tooltipVmType == null) throw new InvalidOperationException("Native PropertyBasedTooltipVM is unavailable for expanded tooltip diagnostics");
        var nativeTooltip = Activator.CreateInstance(tooltipVmType, new object[] { tooltipType, tooltipArguments });
        tooltipVmType.GetProperty("IsExtended")?.SetValue(nativeTooltip, true);
        var properties = tooltipVmType.GetProperty("TooltipPropertyList")?.GetValue(nativeTooltip) as System.Collections.IEnumerable;
        if (properties == null) throw new InvalidOperationException("Native tooltip property list is unavailable for expanded tooltip diagnostics");

        var json = new StringBuilder(4096);
        json.Append('{');
        json.Append("\"partyId\":\"").Append(Escape(party.StringId)).Append('"');
        json.Append(",\"mapFactionId\":\"").Append(Escape(party.MapFaction?.StringId)).Append('"');
        json.Append(",\"isInspected\":").Append(party.IsInspected ? "true" : "false");
        json.Append(",\"isInfoHidden\":").Append(party.IsInfoHidden ? "true" : "false");
        json.Append(",\"isArmyLeader\":").Append(isArmyLeader ? "true" : "false");
        json.Append(",\"memberRoster\":");
        AppendHarnessPartyRosterRows(json, partyRows);
        json.Append(",\"prisonRoster\":");
        AppendHarnessPartyRosterRows(json, prisonerRows);
        json.Append(",\"nativeTooltipProperties\":[");
        var propertyIndex = 0;
        foreach (var property in properties)
        {
            if (propertyIndex++ > 0) json.Append(',');
            json.Append('{');
            var propertyType = property.GetType();
            json.Append("\"definition\":\"").Append(Escape(propertyType.GetProperty("DefinitionLabel")?.GetValue(property)?.ToString())).Append('"');
            json.Append(",\"value\":\"").Append(Escape(propertyType.GetProperty("ValueLabel")?.GetValue(property)?.ToString())).Append('"');
            json.Append('}');
        }
        json.Append("]}");
        return json.ToString();
    }

    private static Hero FindCurrentObservedMissionHero(string heroId)
    {
        var mission = Mission.Current;
        var mainAgent = mission?.MainAgent;
        if (mission == null || mission.MissionEnded || mainAgent == null || !AgentMissionInputPatch.IsSupportedLocationMission(mission) || string.IsNullOrWhiteSpace(heroId))
            throw new InvalidOperationException("Companion hiring diagnostics require an observed HeroId in a live Town/Tavern Mission");
        var targetAgent = mission.Agents.FirstOrDefault(agent =>
        {
            var character = agent?.Character as TaleWorlds.CampaignSystem.CharacterObject;
            var hero = character?.HeroObject;
            if (agent == null || !agent.IsActive() || !agent.IsHuman || hero == null || !string.Equals(hero.StringId, heroId, StringComparison.Ordinal)) return false;
            var x = mainAgent.Position.X - agent.Position.X;
            var y = mainAgent.Position.Y - agent.Position.Y;
            var z = mainAgent.Position.Z - agent.Position.Z;
            return Math.Sqrt(x * x + y * y + z * z) <= 12.0;
        });
        var result = (targetAgent?.Character as TaleWorlds.CampaignSystem.CharacterObject)?.HeroObject;
        if (result == null) throw new InvalidOperationException("HeroId is not an active Hero in the current 12-unit local Mission observation");
        if (targetAgent.IsEnemyOf(mainAgent)) throw new InvalidOperationException("hostile local Hero rejected by companion hiring diagnostics");
        return result;
    }

    private static QuestBase FindObservedOngoingQuest(string questId)
    {
        if (string.IsNullOrWhiteSpace(questId)) throw new InvalidOperationException("questId must come from the current state.quests observation");
        var campaign = Campaign.Current;
        if (campaign?.QuestManager == null) throw new InvalidOperationException("Campaign QuestManager is unavailable");
        var visibleQuests = campaign.QuestManager.Quests.Where(quest => quest != null && quest.IsOngoing).Take(12);
        var quest = visibleQuests.FirstOrDefault(item => string.Equals(item.StringId, questId, StringComparison.Ordinal));
        if (quest == null) throw new InvalidOperationException("questId is not among the currently observed ongoing Quest entries");
        return quest;
    }

    private static string SpendMainHeroSkillFocus(string command)
    {
        var skillId = ReadString(command, "skillId");
        if (string.IsNullOrWhiteSpace(skillId)) throw new InvalidOperationException("skillId must come from the current characterDevelopment observation");
        var count = ReadRequiredInteger(command, "count");
        if (count < 1 || count > 100) throw new InvalidOperationException("count must be between 1 and 100");

        var campaign = Campaign.Current;
        var hero = Hero.MainHero;
        if (campaign == null || hero?.HeroDeveloper == null) throw new InvalidOperationException("MainHero development is unavailable");
        var skillObject = TaleWorlds.CampaignSystem.Extensions.Skills.All
            .FirstOrDefault(skill => skill != null && string.Equals(skill.StringId, skillId, StringComparison.Ordinal));
        if (skillObject == null) throw new InvalidOperationException("skillId is not an active Campaign SkillObject");

        var viewModel = new TaleWorlds.CampaignSystem.ViewModelCollection.CharacterDeveloper.CharacterDeveloperHeroItemVM(hero, () => { });
        var skillViewModel = viewModel.Skills.FirstOrDefault(skill => string.Equals(skill.SkillId, skillId, StringComparison.Ordinal));
        if (skillViewModel == null) throw new InvalidOperationException("skillId is not present in MainHero's Character Developer view");

        var developer = hero.HeroDeveloper;
        var focusBefore = developer.GetFocus(skillObject);
        var pointsBefore = developer.UnspentFocusPoints;
        var maxFocus = campaign.Models.CharacterDevelopmentModel.MaxFocusPerSkill;
        if (count > maxFocus - focusBefore) throw new InvalidOperationException("requested count exceeds the native maximum Focus for this skill");
        var focusPointCost = developer.GetRequiredFocusPointsToAddFocus(skillObject);
        if ((long)count * focusPointCost > pointsBefore) throw new InvalidOperationException("requested count exceeds MainHero's unspent Focus points");

        var learningRateBefore = campaign.Models.CharacterDevelopmentModel.CalculateLearningRate(hero.CharacterAttributes, focusBefore, hero.GetSkillValue(skillObject), skillObject).ResultNumber;
        skillViewModel.ExecuteInspect();
        for (var index = 0; index < count; index++)
        {
            if (!skillViewModel.CanAddFocus)
            {
                viewModel.ResetChanges(isCancel: true);
                throw new InvalidOperationException("native Character Developer no longer permits the requested Focus allocation");
            }
            skillViewModel.ExecuteAddFocus();
        }
        if (skillViewModel.CurrentFocusLevel != focusBefore + count)
        {
            viewModel.ResetChanges(isCancel: true);
            throw new InvalidOperationException("native Character Developer did not stage the full requested Focus allocation");
        }

        skillViewModel.ApplyChanges();
        var focusAfter = developer.GetFocus(skillObject);
        var pointsAfter = developer.UnspentFocusPoints;
        if (focusAfter != focusBefore + count || pointsAfter != pointsBefore - count * focusPointCost)
            throw new InvalidOperationException("native HeroDeveloper result differs from the staged Character Developer transaction");
        var learningRateAfter = campaign.Models.CharacterDevelopmentModel.CalculateLearningRate(hero.CharacterAttributes, focusAfter, hero.GetSkillValue(skillObject), skillObject).ResultNumber;

        var json = new StringBuilder(256);
        json.Append('{');
        json.Append("\"skillId\":\"").Append(Escape(skillId)).Append('"');
        json.Append(",\"requestedCount\":").Append(count);
        json.Append(",\"committedCount\":").Append(focusAfter - focusBefore);
        json.Append(",\"focusBefore\":").Append(focusBefore);
        json.Append(",\"focusAfter\":").Append(focusAfter);
        json.Append(",\"focusPointsBefore\":").Append(pointsBefore);
        json.Append(",\"focusPointsAfter\":").Append(pointsAfter);
        json.Append(",\"focusPointCost\":").Append(focusPointCost);
        json.Append(",\"learningRateBefore\":").Append(learningRateBefore.ToString("R", CultureInfo.InvariantCulture));
        json.Append(",\"learningRateAfter\":").Append(learningRateAfter.ToString("R", CultureInfo.InvariantCulture));
        json.Append('}');
        return json.ToString();
    }
}
