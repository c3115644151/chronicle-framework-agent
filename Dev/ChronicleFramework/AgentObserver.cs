using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using Helpers;
using SandBox.View.Map;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.GameMenus;
using TaleWorlds.CampaignSystem.GameState;
using TaleWorlds.CampaignSystem.Encounters;
using TaleWorlds.CampaignSystem.LogEntries;
using TaleWorlds.CampaignSystem.Party;
using TaleWorlds.CampaignSystem.Roster;
using TaleWorlds.CampaignSystem.Settlements;
using TaleWorlds.CampaignSystem.Settlements.Locations;
using TaleWorlds.CampaignSystem.ViewModelCollection;
using TaleWorlds.Core;
using TaleWorlds.MountAndBlade;
using TaleWorlds.MountAndBlade.View.MissionViews;

namespace ChronicleFramework;

internal static class ChronicleAgentObserver
{
    internal static string BuildSnapshotJson()
    {
        var campaign = Campaign.Current;
        var hero = Hero.MainHero;
        var clan = Clan.PlayerClan;
        var party = MobileParty.MainParty;
        if (campaign == null || hero == null || party == null) return "null";

        var position = party.GetPosition2D;
        var radius = Math.Max(12f, party.SeeingRange);
        var settlements = Settlement.All
            .Where(item => item != null && item.IsActive && item.IsVisible)
            .Select(item => new { Item = item, Distance = Distance(position.X, position.Y, item.GetPosition2D.X, item.GetPosition2D.Y) })
            .Where(item => item.Distance <= radius)
            .OrderBy(item => item.Distance)
            .Take(8)
            .ToArray();
        var parties = MobileParty.All
            .Where(item => item != null && item != party && item.IsActive && item.IsVisible)
            .Select(item => new { Item = item, Distance = Distance(position.X, position.Y, item.GetPosition2D.X, item.GetPosition2D.Y) })
            .Where(item => item.Distance <= radius)
            .OrderBy(item => item.Distance)
            .Take(12)
            .ToArray();
        var hostileParties = parties.Where(item => IsHostile(party.MapFaction, item.Item.MapFaction)).ToArray();
        var quests = campaign.QuestManager?.Quests.Where(item => item.IsOngoing).Take(12).ToArray() ?? Array.Empty<QuestBase>();
        var menu = campaign.CurrentMenuContext?.GameMenu;
        var encounteredParty = PlayerEncounter.IsActive ? PlayerEncounter.EncounteredParty : null;

        var json = new StringBuilder(4096);
        json.Append('{');
        json.Append("\"schemaVersion\":29");
        json.Append(",\"campaignDay\":").Append(Number(CampaignTime.Now.ToDays));
        json.Append(",\"identity\":{");
        Property(json, "heroId", hero.StringId); Property(json, "heroName", hero.Name?.ToString(), true);
        Property(json, "clanId", clan?.StringId, true); Property(json, "clanName", clan?.Name?.ToString(), true);
        json.Append(",\"clanTier\":").Append(clan?.Tier ?? 0);
        json.Append(",\"nextTierRequiredRenown\":");
        if (clan != null && clan.Tier < campaign.Models.ClanTierModel.MaxClanTier)
            json.Append(Number(clan.RenownRequirementForNextTier));
        else
            json.Append("null");
        json.Append(",\"mercenaryRequiredTier\":").Append(campaign.Models.ClanTierModel.MercenaryEligibleTier).Append('}');
        var mainHeroSkills = TaleWorlds.CampaignSystem.Extensions.Skills.All
            .Where(skill => skill != null)
            .OrderBy(skill => skill.StringId, StringComparer.Ordinal)
            .ToArray();
        json.Append(",\"mainHeroSkills\":[");
        for (var index = 0; index < mainHeroSkills.Length; index++)
        {
            if (index > 0) json.Append(',');
            var skill = mainHeroSkills[index];
            json.Append('{');
            Property(json, "id", skill.StringId);
            Property(json, "name", skill.Name?.ToString(), true);
            json.Append(",\"level\":").Append(hero.GetSkillValue(skill)).Append('}');
        }
        json.Append(']');
        json.Append(",\"economy\":{");
        json.Append("\"gold\":").Append(hero.Gold);
        json.Append(",\"influence\":").Append(Number(clan?.Influence ?? 0));
        json.Append(",\"renown\":").Append(Number(clan?.Renown ?? 0)).Append('}');
        json.Append(",\"party\":{");
        Property(json, "id", party.StringId); Property(json, "name", party.Name?.ToString(), true);
        json.Append(",\"members\":").Append(party.MemberRoster.TotalManCount);
        json.Append(",\"healthy\":").Append(party.MemberRoster.TotalHealthyCount);
        json.Append(",\"wounded\":").Append(party.MemberRoster.TotalWounded);
        json.Append(",\"prisoners\":").Append(party.PrisonRoster.TotalManCount);
        json.Append(",\"itemCount\":").Append(TotalItemCount(party.ItemRoster));
        json.Append(",\"sizeLimit\":").Append(party.Party.PartySizeLimit);
        json.Append(",\"speed\":").Append(Number(party.Speed));
        json.Append(",\"morale\":").Append(Number(party.Morale));
        json.Append(",\"moraleContext\":");
        if (party.Morale <= 0f)
        {
            json.Append('{');
            json.Append("\"recentEventsMorale\":").Append(Number(party.RecentEventsMorale));
            json.Append(",\"isStarving\":").Append(Bool(party.Party.IsStarving));
            json.Append(",\"unpaidWages\":").Append(Number(party.HasUnpaidWages));
            json.Append(",\"foodVariety\":").Append(party.ItemRoster.FoodVariety);
            json.Append(",\"effectiveMorale\":").Append(Number(party.MoraleExplained.ResultNumber));
            json.Append('}');
        }
        else
        {
            json.Append("null");
        }
        json.Append(",\"food\":").Append(Number(party.Food));
        json.Append(",\"foodInventory\":").Append(party.TotalFoodAtInventory);
        json.Append(",\"foodChange\":").Append(Number(party.FoodChange));
        json.Append(",\"dailyWage\":").Append(party.TotalWage);
        json.Append(",\"cargoWeight\":").Append(Number(party.TotalWeightCarried));
        json.Append(",\"cargoCapacity\":").Append(party.InventoryCapacity);
        json.Append(",\"isMoving\":").Append(Bool(party.IsMoving));
        Property(json, "moveMode", party.PartyMoveMode.ToString(), true);
        Property(json, "defaultBehavior", party.DefaultBehavior.ToString(), true);
        json.Append(",\"isAtSea\":").Append(Bool(party.IsCurrentlyAtSea)).Append('}');
        json.Append(",\"location\":{");
        json.Append("\"x\":").Append(Number(position.X)).Append(",\"y\":").Append(Number(position.Y));
        Property(json, "currentSettlementId", party.CurrentSettlement?.StringId, true);
        Property(json, "targetSettlementId", party.TargetSettlement?.StringId, true);
        Property(json, "targetPartyId", party.TargetParty?.StringId, true);
        json.Append(",\"targetPosition\":");
        if (party.DefaultBehavior == AiBehavior.GoToPoint)
        {
            var targetPosition = party.TargetPosition;
            json.Append("{\"x\":").Append(Number(targetPosition.X)).Append(",\"y\":").Append(Number(targetPosition.Y));
            json.Append(",\"isOnLand\":").Append(Bool(targetPosition.IsOnLand)).Append('}');
        }
        else
        {
            json.Append("null");
        }
        json.Append('}');
        json.Append(",\"context\":{");
        Property(json, "gameState", Game.Current?.GameStateManager?.ActiveState?.GetType().Name);
        Property(json, "timeControlMode", campaign.TimeControlMode.ToString(), true);
        json.Append(",\"timeControlModeLocked\":").Append(Bool(campaign.TimeControlModeLock));
        Property(json, "menuId", menu?.StringId, true);
        json.Append(",\"isWaitMenu\":").Append(Bool(menu?.IsWaitMenu == true));
        json.Append(",\"isWaitActive\":").Append(Bool(menu?.IsWaitActive == true));
        json.Append(",\"escapeMenuOpen\":").Append(Bool(Game.Current?.GameStateManager?.ActiveState is MapState && MapScreen.Instance?.IsEscapeMenuOpened == true));
        var activeGameState = Game.Current?.GameStateManager?.ActiveState;
        var nativeInquiryOpen = (activeGameState is MapState || activeGameState is MissionState || activeGameState is InventoryState || activeGameState is PartyState) && ChronicleInquiryAdapter.IsInquiryOpen;
        json.Append(",\"inquiryOpen\":").Append(Bool(nativeInquiryOpen));
        json.Append(",\"inquiry\":").Append(nativeInquiryOpen ? ChronicleInquiryAdapter.BuildMapInquiryJson() : "null");
        json.Append(",\"sceneNotification\":").Append(ChronicleAgentSceneNotification.BuildJson(includeClockAudit: false));
        json.Append(",\"mapIncident\":").Append(ChronicleAgentMapIncidentAdapter.BuildJson());
        json.Append(",\"bannerEditor\":").Append(ChronicleAgentBannerEditor.BuildJson());
        json.Append(",\"tournament\":").Append(ChronicleTournamentAdapter.BuildJson());
        json.Append(",\"encounterActive\":").Append(Bool(PlayerEncounter.IsActive));
        json.Append(",\"lootItemCount\":");
        if (PlayerEncounter.Current == null) json.Append("null");
        else json.Append(TotalItemCount(PlayerEncounter.Current.RosterToReceiveLootItems));
        Property(json, "encounteredPartyId", encounteredParty?.Id, true);
        Property(json, "encounteredPartyName", encounteredParty?.Name?.ToString(), true);
        json.Append(",\"isWaiting\":").Append(Bool(campaign.IsMainPartyWaiting));
        json.Append(",\"captivity\":");
        AppendPlayerCaptivityContext(json, campaign, menu?.StringId);
        var battleSimulation = PlayerEncounter.CurrentBattleSimulation;
        json.Append(",\"battleSimulation\":");
        if (battleSimulation == null)
        {
            json.Append("null");
        }
        else
        {
            json.Append('{');
            json.Append("\"finished\":").Append(Bool(battleSimulation.IsSimulationFinished));
            json.Append(",\"playerRetreated\":").Append(Bool(battleSimulation.IsPlayerRetreated));
            Property(json, "battleState", battleSimulation.MapEvent?.BattleState.ToString(), true);
            json.Append('}');
        }
        json.Append(",\"conversation\":");
        var conversationManager = campaign.ConversationManager;
        if (conversationManager == null || !conversationManager.IsConversationInProgress)
        {
            json.Append("null");
        }
        else
        {
            json.Append('{');
            Property(json, "characterId", conversationManager.OneToOneConversationCharacter?.StringId);
            Property(json, "characterName", conversationManager.OneToOneConversationCharacter?.Name?.ToString(), true);
            Property(json, "heroId", conversationManager.OneToOneConversationHero?.StringId, true);
            Property(json, "heroName", conversationManager.OneToOneConversationHero?.Name?.ToString(), true);
            Property(json, "sentenceText", conversationManager.CurrentSentenceText, true);
            json.Append(",\"options\":[");
            var conversationOptions = conversationManager.CurOptions;
            for (var index = 0; index < conversationOptions.Count; index++)
            {
                if (index > 0) json.Append(',');
                var option = conversationOptions[index];
                json.Append('{');
                Property(json, "id", option.Id);
                Property(json, "text", option.Text?.ToString(), true);
                Property(json, "textId", option.Text?.GetID(), true);
                json.Append(",\"clickable\":").Append(Bool(option.IsClickable));
                Property(json, "hint", option.HintText?.ToString(), true);
                json.Append('}');
            }
            json.Append(']');
            json.Append('}');
        }
        json.Append('}');
        var activePartyState = Game.Current.GameStateManager.ActiveState as PartyState;
        json.Append(",\"partyScreen\":");
        if (activePartyState?.PartyScreenLogic == null)
        {
            json.Append("null");
        }
        else
        {
            var screen = activePartyState.PartyScreenLogic;
            json.Append('{');
            Property(json, "mode", activePartyState.PartyScreenMode.ToString());
            json.Append(",\"canDone\":").Append(Bool(screen.IsDoneActive()));
            Property(json, "leftPartyId", screen.LeftOwnerParty?.Id, true);
            Property(json, "rightPartyId", screen.RightOwnerParty?.Id, true);
            AppendPartyRoster(json, "leftMembers", screen, PartyScreenLogic.PartyRosterSide.Left, PartyScreenLogic.TroopType.Member);
            AppendPartyRoster(json, "leftPrisoners", screen, PartyScreenLogic.PartyRosterSide.Left, PartyScreenLogic.TroopType.Prisoner);
            AppendPartyRoster(json, "rightMembers", screen, PartyScreenLogic.PartyRosterSide.Right, PartyScreenLogic.TroopType.Member);
            AppendPartyRoster(json, "rightPrisoners", screen, PartyScreenLogic.PartyRosterSide.Right, PartyScreenLogic.TroopType.Prisoner);
            if (ChronicleAlleyRosterAdapter.IsCurrentNativeAlleyPartyScreen())
            {
                var alleyModel = Campaign.Current.Models.AlleyModel;
                var currentAlleyTroops = screen.GetRoster(PartyScreenLogic.PartyRosterSide.Left, PartyScreenLogic.TroopType.Member).TotalRegulars;
                json.Append(",\"alleyRoster\":{\"minimumTroops\":").Append(alleyModel.MinimumTroopCountInPlayerOwnedAlley);
                json.Append(",\"maximumTroops\":").Append(alleyModel.MaximumTroopCountInPlayerOwnedAlley);
                json.Append(",\"currentTroops\":").Append(currentAlleyTroops);
                json.Append(",\"doneAvailable\":").Append(Bool(screen.IsDoneActive())).Append('}');
            }
            json.Append('}');
        }
        var activeInventoryState = Game.Current.GameStateManager.ActiveState as InventoryState;
        json.Append(",\"inventoryScreen\":");
        if (activeInventoryState?.InventoryLogic == null)
        {
            json.Append("null");
        }
        else
        {
            var inventoryLogic = activeInventoryState.InventoryLogic;
            json.Append('{');
            Property(json, "mode", activeInventoryState.InventoryMode.ToString());
            json.Append(",\"lootItemCount\":").Append(inventoryLogic.GetElementCountOnSide(TaleWorlds.CampaignSystem.Inventory.InventoryLogic.InventorySide.OtherInventory));
            json.Append(",\"playerItemCount\":").Append(inventoryLogic.GetElementCountOnSide(TaleWorlds.CampaignSystem.Inventory.InventoryLogic.InventorySide.PlayerInventory));
            json.Append(",\"hasHandler\":").Append(Bool(activeInventoryState.Handler != null));
            json.Append('}');
        }
        json.Append(",\"availableMenuOptions\":").Append(BuildMenuOptionsJson(campaign.CurrentMenuContext));
        json.Append(",\"settlementOverlayCharacters\":").Append(BuildSettlementOverlayCharactersJson(campaign.CurrentMenuContext));
        json.Append(",\"nearbySettlements\":[");
        for (var index = 0; index < settlements.Length; index++)
        {
            if (index > 0) json.Append(',');
            var item = settlements[index].Item;
            json.Append('{'); Property(json, "id", item.StringId); Property(json, "name", item.Name?.ToString(), true);
            Property(json, "type", item.IsTown ? "town" : item.IsCastle ? "castle" : item.IsVillage ? "village" : item.IsHideout ? "hideout" : "other", true);
            json.Append(",\"distance\":").Append(Number(settlements[index].Distance));
            json.Append(",\"hostile\":").Append(Bool(IsHostile(party.MapFaction, item.MapFaction)));
            json.Append(",\"underSiege\":").Append(Bool(item.IsUnderSiege)).Append('}');
        }
        json.Append(']');
        json.Append(",\"nearbyParties\":[");
        for (var index = 0; index < parties.Length; index++)
        {
            if (index > 0) json.Append(',');
            var item = parties[index].Item;
            json.Append('{'); Property(json, "id", item.StringId); Property(json, "name", item.Name?.ToString(), true);
            Property(json, "type", PartyType(item), true);
            json.Append(",\"distance\":").Append(Number(parties[index].Distance));
            json.Append(",\"hostile\":").Append(Bool(IsHostile(party.MapFaction, item.MapFaction)));
            json.Append(",\"isMoving\":").Append(Bool(item.IsMoving));
            Property(json, "currentSettlementId", item.CurrentSettlement?.StringId, true);
            json.Append(",\"members\":").Append(item.MemberRoster.TotalManCount);
            json.Append(",\"strength\":").Append(Number(item.Party.EstimatedStrength)).Append('}');
        }
        json.Append(']');
        json.Append(",\"quests\":[");
        for (var index = 0; index < quests.Length; index++)
        {
            if (index > 0) json.Append(',');
            json.Append('{'); Property(json, "id", quests[index].StringId); Property(json, "title", quests[index].Title?.ToString(), true);
            AppendQuestDeadline(json, quests[index].IsRemainingTimeHidden, (int)(quests[index].QuestDueTime - CampaignTime.Now).ToDays);
            json.Append('}');
        }
        json.Append(']');
        json.Append(",\"storyModeEstablishClanStatus\":").Append(BuildEstablishClanLifecycleStatusJson(campaign, quests));
        json.Append(",\"danger\":{");
        json.Append("\"hostilePartyCount\":").Append(hostileParties.Length);
        json.Append(",\"nearestHostileDistance\":").Append(hostileParties.Length == 0 ? "null" : Number(hostileParties[0].Distance));
        json.Append(",\"hostileStrength\":").Append(Number(hostileParties.Sum(item => item.Item.Party.EstimatedStrength))).Append('}');
        json.Append(",\"mission\":").Append(BuildMissionObservationJson());
        json.Append('}');
        return json.ToString();
    }

    private static string BuildEstablishClanLifecycleStatusJson(Campaign campaign, QuestBase[] activeQuests)
    {
        const string questId = "rebuild_player_clan_storymode_quest";
        const string questTitleStringId = "bESRdcRo";
        var isStoryMode = string.Equals(Game.Current?.GameType?.GetType().FullName, "StoryMode.CampaignStoryMode", StringComparison.Ordinal);
        var activeQuest = activeQuests.FirstOrDefault(quest => string.Equals(quest.StringId, questId, StringComparison.Ordinal) && quest.IsOngoing);
        if (activeQuest != null)
        {
            var status = StoryModeEstablishClanLifecycleStatus.Classify(isStoryMode: true, tutorialCompleted: true, firstPhaseStarted: true, questActive: true, historicalResultAvailable: false, historicalResultUnsuccessful: false);
            return "{\"status\":\"" + status + "\",\"questId\":\"rebuild_player_clan_storymode_quest\",\"title\":\"" + Escape(activeQuest.Title?.ToString()) + "\",\"source\":\"quest-manager\"}";
        }

        if (!isStoryMode)
        {
            var status = StoryModeEstablishClanLifecycleStatus.Classify(isStoryMode: false, tutorialCompleted: false, firstPhaseStarted: false, questActive: false, historicalResultAvailable: false, historicalResultUnsuccessful: false);
            return "{\"status\":\"" + status + "\",\"questId\":\"rebuild_player_clan_storymode_quest\",\"isStoryMode\":false,\"source\":\"current-game-type\"}";
        }

        try
        {
            var storyModeManagerType = Type.GetType("StoryMode.StoryModeManager, StoryMode", throwOnError: false);
            var storyModeManager = storyModeManagerType?.GetProperty("Current")?.GetValue(null);
            var mainStoryLine = storyModeManager?.GetType().GetProperty("MainStoryLine")?.GetValue(storyModeManager);
            var tutorialPhase = mainStoryLine?.GetType().GetProperty("TutorialPhase")?.GetValue(mainStoryLine);
            var tutorialCompletedValue = tutorialPhase?.GetType().GetProperty("IsCompleted")?.GetValue(tutorialPhase);
            var tutorialCompleted = tutorialCompletedValue is bool completed && completed;
            var firstPhase = mainStoryLine?.GetType().GetProperty("FirstPhase")?.GetValue(mainStoryLine);
            if (storyModeManager == null || tutorialPhase == null || tutorialCompletedValue is not bool)
                return "{\"status\":\"unknown\",\"questId\":\"rebuild_player_clan_storymode_quest\",\"source\":\"storymode-runtime-unavailable\"}";

            var historicalEntry = campaign.LogEntryHistory.GetGameActionLogs<JournalLogEntry>(entry =>
                    entry.IsSpecial && entry.IsEnded() && string.Equals(entry.Title?.GetID(), questTitleStringId, StringComparison.Ordinal))
                .LastOrDefault();
            if (historicalEntry != null)
            {
                var unsuccessful = historicalEntry.IsEndedUnsuccessfully();
                var status = StoryModeEstablishClanLifecycleStatus.Classify(isStoryMode: true, tutorialCompleted: tutorialCompleted, firstPhaseStarted: firstPhase != null, questActive: false, historicalResultAvailable: true, historicalResultUnsuccessful: unsuccessful);
                return "{\"status\":\"" + status + "\",\"questId\":\"rebuild_player_clan_storymode_quest\",\"title\":\"" + Escape(historicalEntry.Title?.ToString()) + "\",\"tutorialCompleted\":" + Bool(tutorialCompleted) + ",\"source\":\"native-old-quest-journal\"}";
            }

            var inactiveStatus = StoryModeEstablishClanLifecycleStatus.Classify(isStoryMode: true, tutorialCompleted: tutorialCompleted, firstPhaseStarted: firstPhase != null, questActive: false, historicalResultAvailable: false, historicalResultUnsuccessful: false);
            if (inactiveStatus == "storymode-not-activated")
                return "{\"status\":\"" + inactiveStatus + "\",\"questId\":\"rebuild_player_clan_storymode_quest\",\"tutorialCompleted\":" + Bool(tutorialCompleted) + ",\"firstPhaseStarted\":" + Bool(firstPhase != null) + ",\"source\":\"storymode-tutorial-phase\"}";

            return "{\"status\":\"" + inactiveStatus + "\",\"questId\":\"rebuild_player_clan_storymode_quest\",\"tutorialCompleted\":true,\"firstPhaseStarted\":true,\"source\":\"no-active-or-historical-quest-entry\"}";
        }
        catch (Exception exception)
        {
            return "{\"status\":\"unknown\",\"questId\":\"rebuild_player_clan_storymode_quest\",\"reason\":\"lifecycle-observation-failed\",\"errorType\":\"" + Escape(exception.GetType().Name) + "\"}";
        }
    }

    internal static string BuildMapSettlementTargetsJson()
    {
        var campaign = Campaign.Current;
        var party = MobileParty.MainParty;
        if (campaign == null || party == null) return "null";
        var position = party.GetPosition2D;
        var mapSettlementTargets = Settlement.All
            .Where(item => item != null && item.IsActive && item.IsVisible)
            .Select(item => new { Item = item, Distance = Distance(position.X, position.Y, item.GetPosition2D.X, item.GetPosition2D.Y) })
            .OrderBy(item => item.Distance)
            .ThenBy(item => item.Item.StringId, StringComparer.Ordinal)
            .ToArray();
        var json = new StringBuilder(1024);
        json.Append('{').Append("\"schemaVersion\":1,\"mapSettlementTargets\":[");
        for (var index = 0; index < mapSettlementTargets.Length; index++)
        {
            if (index > 0) json.Append(',');
            var item = mapSettlementTargets[index].Item;
            json.Append('{'); Property(json, "id", item.StringId); Property(json, "name", item.Name?.ToString(), true);
            Property(json, "type", item.IsTown ? "town" : item.IsCastle ? "castle" : item.IsVillage ? "village" : item.IsHideout ? "hideout" : "other", true);
            json.Append(",\"distance\":").Append(Number(mapSettlementTargets[index].Distance));
            json.Append(",\"isInspected\":").Append(Bool(item.IsInspected));
            json.Append(",\"hostile\":").Append(Bool(IsHostile(party.MapFaction, item.MapFaction)));
            json.Append(",\"underSiege\":").Append(Bool(item.IsUnderSiege)).Append('}');
        }
        json.Append("]}");
        return json.ToString();
    }

    internal static string BuildMapPartyTargetsJson()
    {
        var party = MobileParty.MainParty;
        if (Campaign.Current == null || party == null) return "null";
        var position = party.GetPosition2D;
        var mapPartyTargets = MobileParty.All
            .Where(item => item != null && item != party && item.IsActive && !item.IsGarrison && !item.IsMilitia && item.AttachedTo == null && item.Party.IsVisible)
            .Select(item => new { Item = item, Distance = Distance(position.X, position.Y, item.GetPosition2D.X, item.GetPosition2D.Y) })
            .OrderBy(item => item.Distance)
            .ThenBy(item => item.Item.StringId, StringComparer.Ordinal)
            .ToArray();
        var json = new StringBuilder(2048);
        json.Append('{').Append("\"schemaVersion\":1,\"mapPartyTargets\":[");
        for (var index = 0; index < mapPartyTargets.Length; index++)
        {
            if (index > 0) json.Append(',');
            var target = mapPartyTargets[index];
            var item = target.Item;
            json.Append('{');
            Property(json, "id", item.StringId);
            Property(json, "name", PartyNameplateName(item), true);
            Property(json, "type", PartyType(item), true);
            json.Append(",\"distance\":").Append(Number(target.Distance));
            json.Append(",\"hostile\":").Append(Bool(IsHostile(party.MapFaction, item.MapFaction)));
            json.Append(",\"isInspected\":").Append(Bool(item.IsInspected));
            json.Append(",\"isArmyLeader\":").Append(Bool(item.Army != null && item.Army.LeaderParty == item));
            json.Append(",\"healthyMemberCount\":").Append(GetPartyNameplateHealthyCount(item));
            json.Append(",\"woundedCount\":").Append(GetPartyNameplateWoundedCount(item));
            json.Append(",\"prisonerCount\":").Append(GetPartyNameplatePrisonerCount(item));
            var questMarkers = GetMapPartyNameplateQuestMarkers(item);
            json.Append(",\"questMarkers\":");
            if (questMarkers == null)
            {
                json.Append("null");
            }
            else
            {
                json.Append('[');
                for (var markerIndex = 0; markerIndex < questMarkers.Count; markerIndex++)
                {
                    if (markerIndex > 0) json.Append(',');
                    json.Append('"').Append(questMarkers[markerIndex].ToString()).Append('"');
                }
                json.Append(']');
            }
            json.Append(",\"hasAvailableIssueMarker\":").Append(questMarkers == null ? "null" : Bool(questMarkers.Contains(CampaignUIHelper.IssueQuestFlags.AvailableIssue)));
            json.Append('}');
        }
        json.Append("]}");
        return json.ToString();
    }

    private static List<CampaignUIHelper.IssueQuestFlags> GetMapPartyNameplateQuestMarkers(MobileParty party)
    {
        if (party == null || !party.IsSpotted() || party.CurrentSettlement != null) return null;
        var markers = new HashSet<CampaignUIHelper.IssueQuestFlags>();
        if (party == null || party == MobileParty.MainParty) return new List<CampaignUIHelper.IssueQuestFlags>();

        var leader = party.LeaderHero;
        if (leader?.Issue != null) markers.Add(CampaignUIHelper.GetIssueType(leader.Issue));
        AddPartyQuestMarkers(markers, party, leader);

        if (party.Army != null && party.Army.LeaderParty == party)
        {
            foreach (var attachedParty in party.Army.LeaderParty.AttachedParties)
                AddArmyAggregateQuestMarkers(markers, attachedParty, party);
        }

        var result = new List<CampaignUIHelper.IssueQuestFlags>(markers);
        result.Sort((left, right) => ((int)left).CompareTo((int)right));
        return result;
    }

    private static void AddArmyAggregateQuestMarkers(HashSet<CampaignUIHelper.IssueQuestFlags> markers, MobileParty party, MobileParty nameplateParty)
    {
        if (party == null || party == MobileParty.MainParty || party == nameplateParty) return;

        var leader = party.LeaderHero;
        if (leader?.Issue != null && !markers.Contains(CampaignUIHelper.IssueQuestFlags.TrackedIssue) &&
            (!markers.Contains(CampaignUIHelper.IssueQuestFlags.AvailableIssue) || !markers.Contains(CampaignUIHelper.IssueQuestFlags.ActiveIssue)))
            markers.Add(CampaignUIHelper.GetIssueType(leader.Issue));

        if ((markers.Contains(CampaignUIHelper.IssueQuestFlags.TrackedStoryQuest) || markers.Contains(CampaignUIHelper.IssueQuestFlags.ActiveIssue)) &&
            markers.Contains(CampaignUIHelper.IssueQuestFlags.ActiveStoryQuest))
            return;

        AddPartyQuestMarkers(markers, party, leader);
    }

    private static void AddPartyQuestMarkers(HashSet<CampaignUIHelper.IssueQuestFlags> markers, MobileParty party, Hero leader)
    {
        foreach (var quest in CampaignUIHelper.GetQuestsRelatedToParty(party))
        {
            var isLeaderQuestGiver = leader != null && quest.QuestGiver == leader;
            var marker = isLeaderQuestGiver
                ? (quest.IsSpecialQuest ? CampaignUIHelper.IssueQuestFlags.ActiveStoryQuest : CampaignUIHelper.IssueQuestFlags.ActiveIssue)
                : (quest.IsSpecialQuest ? CampaignUIHelper.IssueQuestFlags.TrackedStoryQuest : CampaignUIHelper.IssueQuestFlags.TrackedIssue);
            markers.Add(marker);
        }
    }

    internal static string BuildMapPartyCompositionJson(string partyId)
    {
        var mainParty = MobileParty.MainParty;
        var target = MobileParty.All.FirstOrDefault(item => item != null && string.Equals(item.StringId, partyId, StringComparison.Ordinal));
        if (Campaign.Current == null || mainParty == null || target == null || target == mainParty || !target.IsActive || target.IsGarrison || target.IsMilitia || target.AttachedTo != null || !target.Party.IsVisible)
            throw new InvalidOperationException("party is not a current visible independent mapPartyTargets candidate");

        var isArmyLeader = target.Army != null && target.Army.LeaderParty == target;
        if (!target.IsInspected || target.IsInfoHidden)
            return BuildUnavailablePartyCompositionJson(target, isArmyLeader, target.IsInfoHidden ? "nativeTooltipSuppressesDetails" : "notInspected");

        var members = isArmyLeader ? MergeArmyRoster(target, prisoners: false) : target.MemberRoster;
        var prisoners = isArmyLeader ? MergeArmyRoster(target, prisoners: true) : target.PrisonRoster;
        var json = new StringBuilder(4096);
        json.Append('{').Append("\"schemaVersion\":1,\"available\":true");
        Property(json, "partyId", target.StringId, true);
        Property(json, "name", PartyNameplateName(target), true);
        Property(json, "type", PartyType(target), true);
        json.Append(",\"isArmyLeader\":").Append(Bool(isArmyLeader));
        json.Append(",\"members\":");
        AppendPartyCompositionRoster(json, members);
        json.Append(",\"prisoners\":");
        AppendPartyCompositionRoster(json, prisoners);
        json.Append('}');
        return json.ToString();
    }

    private static string BuildUnavailablePartyCompositionJson(MobileParty target, bool isArmyLeader, string reason)
    {
        var json = new StringBuilder(256);
        json.Append('{').Append("\"schemaVersion\":1,\"available\":false");
        Property(json, "partyId", target.StringId, true);
        json.Append(",\"isArmyLeader\":").Append(Bool(isArmyLeader));
        Property(json, "reason", reason, true);
        json.Append('}');
        return json.ToString();
    }

    internal static string BuildMapPartyBehaviorJson(string partyId)
    {
        var mainParty = MobileParty.MainParty;
        var target = MobileParty.All.FirstOrDefault(item => item != null && string.Equals(item.StringId, partyId, StringComparison.Ordinal));
        if (Campaign.Current == null || mainParty == null || target == null || target == mainParty || !target.IsActive || target.IsGarrison || target.IsMilitia || target.AttachedTo != null || !target.Party.IsVisible)
            throw new InvalidOperationException("party is not a current visible independent mapPartyTargets candidate");
        if (!target.IsInspected)
            return BuildUnavailablePartyBehaviorJson(target, "notInspected");

        var behaviorText = CampaignUIHelper.GetMobilePartyBehaviorText(target);
        if (string.IsNullOrWhiteSpace(behaviorText))
            return BuildUnavailablePartyBehaviorJson(target, "nativeTooltipHasNoBehaviorSummary");
        var json = new StringBuilder(512);
        json.Append('{').Append("\"schemaVersion\":1,\"available\":true");
        Property(json, "partyId", target.StringId, true);
        json.Append(",\"isArmyLeader\":").Append(Bool(target.Army != null && target.Army.LeaderParty == target));
        Property(json, "behaviorText", behaviorText, true);
        json.Append('}');
        return json.ToString();
    }

    private static string BuildUnavailablePartyBehaviorJson(MobileParty target, string reason)
    {
        var json = new StringBuilder(256);
        json.Append('{').Append("\"schemaVersion\":1,\"available\":false");
        Property(json, "partyId", target.StringId, true);
        Property(json, "reason", reason, true);
        json.Append('}');
        return json.ToString();
    }

    private static TroopRoster MergeArmyRoster(MobileParty leader, bool prisoners)
    {
        var merged = TroopRoster.CreateDummyTroopRoster();
        AddRoster(merged, prisoners ? leader.PrisonRoster : leader.MemberRoster);
        foreach (var attachedParty in leader.AttachedParties)
            AddRoster(merged, prisoners ? attachedParty.PrisonRoster : attachedParty.MemberRoster);
        return merged;
    }

    private static void AddRoster(TroopRoster target, TroopRoster source)
    {
        for (var index = 0; index < source.Count; index++)
        {
            var element = source.GetElementCopyAtIndex(index);
            if (element.Character != null && element.Number > 0)
                target.AddToCounts(element.Character, element.Number, insertAtFront: false, element.WoundedNumber);
        }
    }

    private static void AppendPartyCompositionRoster(StringBuilder json, TroopRoster roster)
    {
        json.Append('[');
        var first = true;
        for (var index = 0; index < roster.Count; index++)
        {
            var element = roster.GetElementCopyAtIndex(index);
            if (element.Character == null || element.Number <= 0) continue;
            if (!first) json.Append(',');
            first = false;
            json.Append('{');
            Property(json, "characterId", element.Character.StringId);
            Property(json, "name", element.Character.Name?.ToString(), true);
            json.Append(",\"totalCount\":").Append(element.Number);
            json.Append(",\"healthyCount\":").Append(Math.Max(element.Number - element.WoundedNumber, 0));
            json.Append(",\"woundedCount\":").Append(element.WoundedNumber);
            json.Append(",\"isHero\":").Append(Bool(element.Character.IsHero));
            json.Append('}');
        }
        json.Append(']');
    }

    private static string PartyNameplateName(MobileParty party)
    {
        if (party.Army != null && party.Army.DoesLeaderPartyAndAttachedPartiesContain(party)) return party.ArmyName?.ToString();
        return party.LeaderHero?.Name?.ToString() ?? party.Name?.ToString();
    }

    private static int GetPartyNameplateHealthyCount(MobileParty party)
    {
        var count = party.Party.NumberOfHealthyMembers;
        if (party.Army != null && party.Army.LeaderParty == party)
            foreach (var attachedParty in party.Army.LeaderParty.AttachedParties)
                count += attachedParty.Party.NumberOfHealthyMembers;
        return count;
    }

    private static int GetPartyNameplateWoundedCount(MobileParty party)
    {
        var count = party.Party.NumberOfWoundedTotalMembers;
        if (party.Army != null && party.Army.LeaderParty == party)
            foreach (var attachedParty in party.Army.LeaderParty.AttachedParties)
                count += attachedParty.Party.NumberOfWoundedTotalMembers;
        return count;
    }

    private static int GetPartyNameplatePrisonerCount(MobileParty party)
    {
        var count = party.Party.NumberOfPrisoners;
        if (party.Army != null && party.Army.LeaderParty == party)
            foreach (var attachedParty in party.Army.LeaderParty.AttachedParties)
                count += attachedParty.Party.NumberOfPrisoners;
        return count;
    }

    internal static string BuildCharacterDevelopmentJson()
    {
        var campaign = Campaign.Current;
        var hero = Hero.MainHero;
        var developer = hero?.HeroDeveloper;
        if (campaign == null || hero == null || developer == null) return "null";

        var skills = TaleWorlds.CampaignSystem.Extensions.Skills.All
            .Where(skill => skill != null)
            .OrderBy(skill => skill.StringId, StringComparer.Ordinal)
            .ToArray();
        var attributes = TaleWorlds.CampaignSystem.Extensions.Attributes.All
            .Where(attribute => attribute != null)
            .OrderBy(attribute => attribute.StringId, StringComparer.Ordinal)
            .ToArray();
        var allPerks = TaleWorlds.CampaignSystem.CharacterDevelopment.PerkObject.All
            .Where(perk => perk != null)
            .ToArray();

        var json = new StringBuilder(4096);
        json.Append('{').Append("\"schemaVersion\":1");
        Property(json, "heroId", hero.StringId, true);
        json.Append(",\"level\":").Append(hero.Level);
        json.Append(",\"totalExperience\":").Append(developer.TotalXp);
        json.Append(",\"experienceForNextLevel\":").Append(campaign.Models.CharacterDevelopmentModel.SkillsRequiredForLevel(hero.Level + 1));
        json.Append(",\"unspentFocusPoints\":").Append(developer.UnspentFocusPoints);
        json.Append(",\"unspentAttributePoints\":").Append(developer.UnspentAttributePoints);

        json.Append(",\"attributes\":[");
        for (var index = 0; index < attributes.Length; index++)
        {
            if (index > 0) json.Append(',');
            var attribute = attributes[index];
            json.Append('{');
            Property(json, "id", attribute.StringId);
            Property(json, "name", attribute.Name?.ToString(), true);
            json.Append(",\"value\":").Append(hero.GetAttributeValue(attribute)).Append('}');
        }
        json.Append(']');

        json.Append(",\"skills\":[");
        for (var index = 0; index < skills.Length; index++)
        {
            if (index > 0) json.Append(',');
            var skill = skills[index];
            var level = hero.GetSkillValue(skill);
            var focus = developer.GetFocus(skill);
            var model = campaign.Models.CharacterDevelopmentModel;
            json.Append('{');
            Property(json, "id", skill.StringId);
            Property(json, "name", skill.Name?.ToString(), true);
            json.Append(",\"level\":").Append(level);
            json.Append(",\"experienceProgress\":").Append(developer.GetSkillXpProgress(skill));
            json.Append(",\"experienceRequiredForNextLevel\":").Append(model.GetXpRequiredForSkillLevel(level + 1) - model.GetXpRequiredForSkillLevel(level));
            json.Append(",\"focus\":").Append(focus);
            json.Append(",\"learningRate\":").Append(Number(model.CalculateLearningRate(hero.CharacterAttributes, focus, level, skill).ResultNumber));
            json.Append(",\"learningLimit\":").Append(TaleWorlds.Library.MathF.Round(model.CalculateLearningLimit(hero.CharacterAttributes, focus, skill).ResultNumber));
            json.Append(",\"canAddFocus\":").Append(Bool(developer.CanAddFocusToSkill(skill)));

            var availablePerks = allPerks.Where(perk => perk.Skill == skill && (float)level >= perk.RequiredSkillValue).ToArray();
            var visiblePerks = availablePerks.OrderBy(perk => perk.RequiredSkillValue).ThenBy(perk => perk.StringId, StringComparer.Ordinal).ToArray();
            json.Append(",\"perks\":[");
            for (var perkIndex = 0; perkIndex < visiblePerks.Length; perkIndex++)
            {
                if (perkIndex > 0) json.Append(',');
                var perk = visiblePerks[perkIndex];
                var previous = allPerks
                    .Where(candidate => candidate.Skill == perk.Skill && candidate.RequiredSkillValue < perk.RequiredSkillValue)
                    .OrderByDescending(candidate => candidate.RequiredSkillValue)
                    .ThenBy(candidate => candidate.StringId, StringComparer.Ordinal)
                    .FirstOrDefault();
                var previousOwned = previous == null || hero.GetPerkValue(previous) || (previous.AlternativePerk != null && hero.GetPerkValue(previous.AlternativePerk));
                var alternativeOwned = perk.AlternativePerk != null && hero.GetPerkValue(perk.AlternativePerk);
                var owned = hero.GetPerkValue(perk);
                var choiceState = owned ? "owned" : alternativeOwned ? "alternativeSelected" : previousOwned ? "selectable" : "blockedByPrevious";
                json.Append('{');
                Property(json, "id", perk.StringId);
                Property(json, "name", perk.Name?.ToString(), true);
                json.Append(",\"requiredSkillLevel\":").Append(Number(perk.RequiredSkillValue));
                Property(json, "alternativeId", perk.AlternativePerk?.StringId, true);
                json.Append(",\"owned\":").Append(Bool(owned));
                json.Append(",\"alternativeOwned\":").Append(Bool(alternativeOwned));
                json.Append(",\"previousPerkOwned\":").Append(Bool(previousOwned));
                Property(json, "choiceState", choiceState, true);
                json.Append('}');
            }
            json.Append("]}");
        }
        json.Append(']');
        json.Append("}");
        return json.ToString();
    }

    internal static string BuildQuestDetailsJson(QuestBase quest)
    {
        if (quest == null || !quest.IsOngoing) return "null";
        var hiddenTime = quest.IsRemainingTimeHidden;
        var journalEntries = quest.JournalEntries;
        var json = new StringBuilder(2048);
        json.Append('{').Append("\"schemaVersion\":1");
        Property(json, "questId", quest.StringId, true);
        Property(json, "title", quest.Title?.ToString(), true);
        json.Append(",\"isSpecialQuest\":").Append(Bool(quest.IsSpecialQuest));
        json.Append(",\"isTracked\":").Append(Bool(quest.IsTrackEnabled));
        json.Append(",\"questGiverHidden\":").Append(Bool(quest.QuestGiver == null));
        json.Append(",\"questGiver\":");
        if (quest.QuestGiver == null) json.Append("null");
        else
        {
            json.Append('{');
            Property(json, "id", quest.QuestGiver.StringId);
            Property(json, "name", quest.QuestGiver.Name?.ToString(), true);
            json.Append('}');
        }
        AppendQuestDeadline(json, hiddenTime, (int)(quest.QuestDueTime - CampaignTime.Now).ToDays);
        json.Append(",\"journalStages\":[");
        for (var index = 0; index < journalEntries.Count; index++)
        {
            if (index > 0) json.Append(',');
            var log = journalEntries[index];
            var hasTask = log.Type != LogType.Text && log.Type != LogType.None;
            var currentProgress = log.Type == LogType.TwoWayContinuous ? log.CurrentProgress : Math.Max(log.CurrentProgress, 0);
            var targetProgress = Math.Max(log.Range, 0);
            json.Append('{');
            Property(json, "logType", log.Type.ToString());
            Property(json, "dateText", log.GetTimeText().ToString(), true);
            Property(json, "description", log.LogText?.ToString(), true);
            json.Append(",\"isLastStage\":").Append(Bool(index == journalEntries.Count - 1));
            json.Append(",\"hasTask\":").Append(Bool(hasTask));
            if (hasTask)
            {
                Property(json, "taskName", log.TaskName?.ToString(), true);
                json.Append(",\"currentProgress\":").Append(currentProgress);
                json.Append(",\"targetProgress\":").Append(targetProgress);
                Property(json, "progressType", log.Type.ToString(), true);
                json.Append(",\"isTaskCompleted\":").Append(Bool(currentProgress == targetProgress));
            }
            json.Append('}');
        }
        json.Append(']');
        if (string.Equals(quest.GetType().FullName, "StoryMode.Quests.PlayerClanQuests.RebuildPlayerClanQuest", StringComparison.Ordinal))
            AppendEstablishClanProgress(json);
        json.Append('}');
        return json.ToString();
    }

    private static void AppendEstablishClanProgress(StringBuilder json)
    {
        var hero = Hero.MainHero;
        var clan = Clan.PlayerClan;
        var party = MobileParty.MainParty;
        var campaign = Campaign.Current;
        if (hero == null || clan == null || party == null || campaign?.Models?.BanditDensityModel == null) return;

        const int goldTarget = 2000;
        const int renownTarget = 50;
        const int companionTarget = 1;
        var partyTarget = campaign.Models.BanditDensityModel.GetMinimumTroopCountForHideoutMission(party, false);
        var gold = hero.Gold;
        var partyMembers = party.MemberRoster.TotalManCount;
        var renown = clan.Renown;
        var companions = clan.Companions.Count;
        json.Append(",\"storyModeEstablishClan\":{");
        Property(json, "questId", "rebuild_player_clan_storymode_quest");
        json.Append(",\"gold\":{\"current\":").Append(gold).Append(",\"target\":").Append(goldTarget).Append(",\"met\":").Append(Bool(gold >= goldTarget)).Append('}');
        json.Append(",\"partySize\":{\"current\":").Append(partyMembers).Append(",\"target\":").Append(partyTarget).Append(",\"met\":").Append(Bool(partyMembers >= partyTarget)).Append('}');
        json.Append(",\"renown\":{\"current\":").Append(Number(renown)).Append(",\"target\":").Append(renownTarget).Append(",\"met\":").Append(Bool(renown >= renownTarget)).Append('}');
        json.Append(",\"companions\":{\"current\":").Append(companions).Append(",\"target\":").Append(companionTarget).Append(",\"met\":").Append(Bool(companions >= companionTarget)).Append('}');
        json.Append('}');
    }

    internal static string BuildPartyRosterJson()
    {
        var party = MobileParty.MainParty;
        if (Campaign.Current == null || party == null) return "null";
        var memberRoster = party.MemberRoster;
        var prisonerRoster = party.PrisonRoster;
        var json = new StringBuilder(4096);
        json.Append('{').Append("\"schemaVersion\":1");
        Property(json, "partyId", party.StringId, true);
        json.Append(",\"members\":");
        AppendRosterDetails(json, memberRoster);
        json.Append(",\"prisoners\":");
        AppendRosterDetails(json, prisonerRoster);
        json.Append(",\"memberTotals\":{");
        json.Append("\"totalCount\":").Append(memberRoster.TotalManCount);
        json.Append(",\"healthyCount\":").Append(memberRoster.TotalHealthyCount);
        json.Append(",\"woundedCount\":").Append(memberRoster.TotalWounded);
        json.Append(",\"sizeLimit\":").Append(party.Party.PartySizeLimit).Append('}');
        json.Append(",\"prisonerTotals\":{");
        json.Append("\"totalCount\":").Append(prisonerRoster.TotalManCount);
        json.Append(",\"healthyCount\":").Append(prisonerRoster.TotalHealthyCount);
        json.Append(",\"woundedCount\":").Append(prisonerRoster.TotalWounded);
        json.Append(",\"sizeLimit\":").Append(party.Party.PrisonerSizeLimit).Append('}');
        json.Append('}');
        return json.ToString();
    }

    private static void AppendRosterDetails(StringBuilder json, TaleWorlds.CampaignSystem.Roster.TroopRoster roster)
    {
        var elements = Enumerable.Range(0, roster.Count)
            .Select(roster.GetElementCopyAtIndex)
            .Where(element => element.Character != null && element.Number > 0)
            .OrderBy(element => element.Character.StringId, StringComparer.Ordinal)
            .ToArray();
        json.Append('[');
        for (var index = 0; index < elements.Length; index++)
        {
            if (index > 0) json.Append(',');
            var element = elements[index];
            var character = element.Character;
            var isHero = character.IsHero;
            json.Append('{');
            Property(json, "characterId", character.StringId);
            Property(json, "name", character.Name?.ToString(), true);
            json.Append(",\"tier\":").Append(character.Tier);
            json.Append(",\"count\":").Append(element.Number);
            json.Append(",\"woundedCount\":").Append(element.WoundedNumber);
            json.Append(",\"healthyCount\":").Append(Math.Max(element.Number - element.WoundedNumber, 0));
            json.Append(",\"isHero\":").Append(Bool(isHero));
            json.Append(",\"isHeroWounded\":").Append(Bool(isHero && character.HeroObject != null && character.HeroObject.IsWounded));
            json.Append('}');
        }
        json.Append(']');
    }

    internal static void AppendQuestDeadline(StringBuilder json, bool isHidden, int daysRemaining)
    {
        json.Append(",\"isRemainingTimeHidden\":").Append(Bool(isHidden));
        json.Append(",\"daysRemaining\":");
        if (isHidden) json.Append("null");
        else json.Append(daysRemaining);
    }

    private static string BuildMissionObservationJson()
    {
        var activeGameState = Game.Current?.GameStateManager?.ActiveState;
        var currentMissionProperty = activeGameState?.GetType().GetProperty("CurrentMission");
        var stateMission = currentMissionProperty?.GetValue(activeGameState) as Mission;
        var mission = Mission.Current ?? stateMission;
        if (mission == null)
        {
            if (activeGameState?.GetType().Name != "MissionState") return "null";
            var missionless = new StringBuilder(256);
            missionless.Append("{\"active\":false,\"missionEnded\":true,\"currentMissionPresent\":false");
            Property(missionless, "activeGameStateType", activeGameState.GetType().FullName, true);
            missionless.Append(",\"missionStateCurrentMissionPropertyPresent\":").Append(Bool(currentMissionProperty != null));
            missionless.Append(",\"missionCurrentStaticPresent\":").Append(Bool(Mission.Current != null));
            missionless.Append('}');
            return missionless.ToString();
        }

        var missionStateActive = string.Equals(activeGameState?.GetType().Name, "MissionState", StringComparison.Ordinal);
        var missionSource = Mission.Current != null ? "Mission.Current" : "MissionState.CurrentMission";

        var mainAgent = mission.MainAgent;
        var mainAgentController = mission.MissionBehaviors.OfType<MissionMainAgentController>().FirstOrDefault();
        var focusedObject = mainAgentController?.InteractionComponent?.CurrentFocusedObject;
        var focusedAgent = focusedObject as Agent;
        var missionAgents = mission.Agents.Where(agent => agent != null && agent != mainAgent && agent.IsActive()).ToArray();
        var nearbyHeroAgents = mainAgent == null
            ? Array.Empty<(Agent Agent, CharacterObject Character, Hero Hero, double Distance)>()
            : missionAgents
                .Select(agent => (Agent: agent, Character: agent.Character as CharacterObject, Hero: (agent.Character as CharacterObject)?.HeroObject))
                .Where(item => item.Hero != null)
                .Select(item => (item.Agent, item.Character, item.Hero, Distance: Distance3D(mainAgent.Position, item.Agent.Position)))
                .Where(item => item.Distance <= 12.0)
                .OrderBy(item => item.Distance)
                .Take(32)
                .ToArray();
        var nearbySceneAgents = mainAgent == null
            ? Array.Empty<(Agent Agent, CharacterObject Character, Hero Hero, double Distance)>()
            : missionAgents
                .Where(agent => agent.IsHuman && agent.Character != null)
                .Select(agent => (Agent: agent, Character: agent.Character as CharacterObject, Hero: (agent.Character as CharacterObject)?.HeroObject, Distance: Distance3D(mainAgent.Position, agent.Position)))
                .Where(item => item.Distance <= 12.0)
                .OrderBy(item => item.Distance)
                .Take(32)
                .ToArray();

        var json = new StringBuilder(2048);
        json.Append('{');
        json.Append("\"active\":").Append(Bool(!mission.MissionEnded));
        json.Append(",\"missionEnded\":").Append(Bool(mission.MissionEnded));
        json.Append(",\"nativeMissionStateActive\":").Append(Bool(missionStateActive));
        Property(json, "activeGameStateType", activeGameState?.GetType().FullName, true);
        Property(json, "missionObservationSource", missionSource, true);
        Property(json, "nativeMissionCurrentState", mission.CurrentState.ToString(), true);
        Property(json, "sceneName", mission.SceneName, true);
        Property(json, "mode", mission.Mode.ToString(), true);
        Property(json, "combatType", mission.CombatType.ToString(), true);
        json.Append(",\"activeAgentCount\":").Append(missionAgents.Length);
        json.Append(",\"camera\":");
        if (mainAgentController?.MissionScreen == null)
        {
            json.Append("null");
        }
        else
        {
            json.Append('{');
            json.Append("\"bearing\":").Append(Number(mainAgentController.MissionScreen.CameraBearing));
            json.Append(",\"elevation\":").Append(Number(mainAgentController.MissionScreen.CameraElevation)).Append('}');
        }
        json.Append(",\"mainAgent\":");
        if (mainAgent == null || !mainAgent.IsActive())
        {
            json.Append("null");
        }
        else
        {
            var mainCharacter = mainAgent.Character as CharacterObject;
            json.Append('{');
            Property(json, "characterId", mainCharacter?.StringId);
            Property(json, "heroId", mainCharacter?.HeroObject?.StringId, true);
            Property(json, "name", mainAgent.Name, true);
            Property(json, "controller", mainAgent.Controller.ToString(), true);
            json.Append(",\"isPlayerControlled\":").Append(Bool(mainAgent.IsPlayerControlled));
            json.Append(",\"isAIControlled\":").Append(Bool(mainAgent.IsAIControlled));
            json.Append(",\"position\":{\"x\":").Append(Number(mainAgent.Position.X));
            json.Append(",\"y\":").Append(Number(mainAgent.Position.Y)).Append(",\"z\":").Append(Number(mainAgent.Position.Z)).Append('}');
            json.Append(",\"lookDirection\":{\"x\":").Append(Number(mainAgent.LookDirection.X));
            json.Append(",\"y\":").Append(Number(mainAgent.LookDirection.Y)).Append(",\"z\":").Append(Number(mainAgent.LookDirection.Z)).Append('}');
        json.Append(",\"movementInput\":{\"x\":").Append(Number(mainAgent.MovementInputVector.X));
            json.Append(",\"y\":").Append(Number(mainAgent.MovementInputVector.Y)).Append("}}");
        }
        json.Append(",\"nativeFocus\":");
        if (mainAgentController == null)
        {
            json.Append("null");
        }
        else
        {
            json.Append('{');
            json.Append("\"controllerFound\":true");
            Property(json, "objectType", focusedObject?.GetType().Name, true);
            json.Append(",\"isAgent\":").Append(Bool(focusedAgent != null));
            json.Append(",\"agent\":");
            if (focusedAgent == null)
            {
                json.Append("null");
            }
            else
            {
                var focusedCharacter = focusedAgent.Character as CharacterObject;
                var focusedHero = focusedCharacter?.HeroObject;
                json.Append('{');
                json.Append("\"agentIndex\":").Append(focusedAgent.Index).Append(',');
                Property(json, "characterId", focusedCharacter?.StringId);
                Property(json, "heroId", focusedHero?.StringId, true);
                Property(json, "name", focusedHero?.Name?.ToString() ?? focusedAgent.Name, true);
                json.Append(",\"isNotable\":").Append(Bool(focusedHero?.IsNotable ?? false));
                json.Append(",\"isEnemy\":").Append(Bool(focusedAgent.IsEnemyOf(mainAgent)));
                var isInteractable = mainAgent != null && mainAgentController?.MissionScreen != null && mainAgent.CanInteractWithAgent(focusedAgent, mainAgentController.MissionScreen.CameraElevation);
                json.Append(",\"isInteractable\":").Append(Bool(isInteractable));
                json.Append(",\"distance\":").Append(Number(Distance3D(mainAgent.Position, focusedAgent.Position))).Append('}');
            }
            json.Append('}');
        }
        json.Append(",\"nearbyHeroAgents\":[");
        for (var index = 0; index < nearbyHeroAgents.Length; index++)
        {
            if (index > 0) json.Append(',');
            var item = nearbyHeroAgents[index];
            json.Append('{');
            Property(json, "heroId", item.Hero.StringId);
            Property(json, "characterId", item.Character.StringId, true);
            Property(json, "name", item.Hero.Name?.ToString(), true);
            Property(json, "occupation", item.Hero.Occupation.ToString(), true);
            json.Append(",\"isNotable\":").Append(Bool(item.Hero.IsNotable));
            json.Append(",\"isEnemy\":").Append(Bool(item.Agent.IsEnemyOf(mainAgent)));
            json.Append(",\"distance\":").Append(Number(item.Distance));
            json.Append(",\"position\":{\"x\":").Append(Number(item.Agent.Position.X));
            json.Append(",\"y\":").Append(Number(item.Agent.Position.Y)).Append(",\"z\":").Append(Number(item.Agent.Position.Z)).Append("}}");
        }
        json.Append(']');
        json.Append(",\"nearbySceneAgents\":[");
        for (var index = 0; index < nearbySceneAgents.Length; index++)
        {
            if (index > 0) json.Append(',');
            var item = nearbySceneAgents[index];
            json.Append('{');
            json.Append("\"agentIndex\":").Append(item.Agent.Index);
            Property(json, "characterId", item.Character?.StringId, true);
            Property(json, "heroId", item.Hero?.StringId, true);
            Property(json, "name", item.Hero?.Name?.ToString() ?? item.Character?.Name?.ToString() ?? item.Agent.Name, true);
            Property(json, "occupation", item.Hero?.Occupation.ToString() ?? item.Character?.Occupation.ToString(), true);
            json.Append(",\"isNotable\":").Append(Bool(item.Hero?.IsNotable ?? false));
            json.Append(",\"isEnemy\":").Append(Bool(item.Agent.IsEnemyOf(mainAgent)));
            json.Append(",\"distance\":").Append(Number(item.Distance));
            var isInteractable = mainAgentController?.MissionScreen != null && mainAgent.CanInteractWithAgent(item.Agent, mainAgentController.MissionScreen.CameraElevation);
            json.Append(",\"isInteractable\":").Append(Bool(isInteractable));
            json.Append(",\"position\":{\"x\":").Append(Number(item.Agent.Position.X));
            json.Append(",\"y\":").Append(Number(item.Agent.Position.Y)).Append(",\"z\":").Append(Number(item.Agent.Position.Z)).Append("}}");
        }
        json.Append(']');
        json.Append(",\"navigation\":").Append(ChronicleAgentProtocol.BuildMissionNavigationObservationJson(mainAgent));
        json.Append(",\"leave\":").Append(ChronicleAgentProtocol.BuildMissionLeaveObservationJson(mission));
        json.Append('}');
        return json.ToString();
    }

    internal static string BuildMissionSceneAgentsJson(Mission mission, out Agent[] observedAgents)
    {
        if (mission == null || mission.MissionEnded || mission.MainAgent == null || !mission.MainAgent.IsActive())
            throw new InvalidOperationException("missionSceneAgents requires an active Mission with the live player MainAgent");
        if (!AgentMissionInputPatch.IsSupportedLocationMission(mission) || !mission.IsFriendlyMission)
            throw new InvalidOperationException("missionSceneAgents supports friendly Town, Tavern, or Village Location Missions only");
        if (Campaign.Current?.TimeControlMode != TaleWorlds.CampaignSystem.CampaignTimeControlMode.Stop)
            throw new InvalidOperationException("missionSceneAgents requires the Campaign clock to remain stopped");

        var mainAgent = mission.MainAgent;
        observedAgents = mission.Agents
            .Where(agent => agent != null && agent != mainAgent && agent.IsActive() && agent.IsHuman && agent.Character != null)
            .OrderBy(agent => Distance3D(mainAgent.Position, agent.Position))
            .ThenBy(agent => agent.Index)
            .ToArray();

        var json = new StringBuilder(Math.Max(512, observedAgents.Length * 192));
        json.Append("{\"schemaVersion\":1,\"scope\":\"active human Agents instantiated in the current friendly Location Mission; not a Campaign/global list or camera-visibility claim\"");
        Property(json, "sceneName", mission.SceneName, true);
        json.Append(",\"activeAgentCount\":").Append(observedAgents.Length);
        json.Append(",\"agents\":[");
        for (var index = 0; index < observedAgents.Length; index++)
        {
            if (index > 0) json.Append(',');
            var agent = observedAgents[index];
            var character = agent.Character as CharacterObject;
            var hero = character?.HeroObject;
            json.Append('{');
            json.Append("\"agentIndex\":").Append(agent.Index);
            Property(json, "characterId", character?.StringId, true);
            Property(json, "heroId", hero?.StringId, true);
            Property(json, "name", hero?.Name?.ToString() ?? character?.Name?.ToString() ?? agent.Name, true);
            Property(json, "occupation", hero?.Occupation.ToString() ?? character?.Occupation.ToString(), true);
            json.Append(",\"isNotable\":").Append(Bool(hero?.IsNotable ?? false));
            json.Append(",\"isEnemy\":").Append(Bool(agent.IsEnemyOf(mainAgent)));
            json.Append(",\"distance\":").Append(Number(Distance3D(mainAgent.Position, agent.Position)));
            json.Append(",\"position\":{\"x\":").Append(Number(agent.Position.X));
            json.Append(",\"y\":").Append(Number(agent.Position.Y)).Append(",\"z\":").Append(Number(agent.Position.Z)).Append("}}");
        }
        json.Append("]}");
        return json.ToString();
    }

    private static void AppendPartyRoster(StringBuilder json, string propertyName, PartyScreenLogic logic, PartyScreenLogic.PartyRosterSide side, PartyScreenLogic.TroopType type)
    {
        json.Append(",\"").Append(propertyName).Append("\":[");
        var roster = logic.GetRoster(side, type);
        var outputIndex = 0;
        for (var index = 0; index < roster.Count; index++)
        {
            var element = roster.GetElementCopyAtIndex(index);
            if (element.Character == null || element.Number <= 0) continue;
            if (outputIndex++ > 0) json.Append(',');
            json.Append('{');
            Property(json, "troopId", element.Character.StringId);
            Property(json, "name", element.Character.Name?.ToString(), true);
            json.Append(",\"count\":").Append(element.Number);
            json.Append(",\"wounded\":").Append(element.WoundedNumber);
            json.Append(",\"transferable\":").Append(Bool(logic.IsTroopTransferable(type, element.Character, (int)side)));
            json.Append('}');
        }
        json.Append(']');
    }

    private static int TotalItemCount(TaleWorlds.CampaignSystem.Roster.ItemRoster roster)
    {
        var total = 0;
        for (var index = 0; index < roster.Count; index++) total += roster.GetElementNumber(index);
        return total;
    }

    internal static string BuildMenuOptionsJson(MenuContext menuContext)
    {
        if (menuContext?.GameMenu == null) return "[]";
        var options = menuContext.GameMenu.MenuOptions.ToArray();
        var json = new StringBuilder();
        json.Append('[');
        for (var index = 0; index < options.Length; index++)
        {
            if (index > 0) json.Append(',');
            var option = options[index];
            var available = option.GetConditionsHold(Game.Current, menuContext);
            json.Append('{');
            Property(json, "id", option.IdString);
            Property(json, "text", option.Text?.ToString(), true);
            Property(json, "tooltip", option.Tooltip?.ToString(), true);
            json.Append(",\"questMarkerFlags\":").Append((int)option.OptionQuestData);
            Property(json, "questMarkerNames", option.OptionQuestData.ToString(), true);
            json.Append(",\"available\":").Append(Bool(available));
            json.Append(",\"enabled\":").Append(Bool(option.IsEnabled));
            json.Append(",\"isLeave\":").Append(Bool(option.IsLeave));
            json.Append('}');
        }
        json.Append(']');
        return json.ToString();
    }

    private static string BuildSettlementOverlayCharactersJson(MenuContext menuContext)
    {
        var gameMenu = menuContext?.GameMenu;
        if (gameMenu == null ||
            (gameMenu.OverlayType != GameMenu.MenuOverlayType.SettlementWithCharacters && gameMenu.OverlayType != GameMenu.MenuOverlayType.SettlementWithBoth) ||
            Campaign.Current?.GameMenuManager == null)
            return "[]";

        var characters = Campaign.Current.GameMenuManager.MenuLocations
            .Where(location => location != null)
            .SelectMany(location => location.GetCharacterList())
            .Where(locationCharacter => locationCharacter != null && locationCharacter.Character?.IsHero == true && Campaign.Current.Models.HeroAgentLocationModel.WillBeListedInOverlay(locationCharacter))
            .Select(locationCharacter => new { Hero = locationCharacter.Character.HeroObject, Character = locationCharacter.Character })
            .Where(item => item.Hero != null)
            .GroupBy(item => item.Hero)
            .Select(group => group.First())
            .OrderBy(item => item.Hero.Name?.ToString() ?? item.Hero.StringId, StringComparer.OrdinalIgnoreCase)
            .ToArray();

        var json = new StringBuilder();
        json.Append('[');
        for (var index = 0; index < characters.Length; index++)
        {
            if (index > 0) json.Append(',');
            var item = characters[index];
            var questMarkers = CampaignUIHelper.GetQuestStateOfHero(item.Hero);
            json.Append('{');
            Property(json, "heroId", item.Hero.StringId);
            Property(json, "characterId", item.Character.StringId, true);
            Property(json, "name", item.Hero.Name?.ToString(), true);
            Property(json, "occupation", item.Hero.Occupation.ToString(), true);
            json.Append(",\"isNotable\":").Append(Bool(item.Hero.IsNotable));
            json.Append(",\"isPrisoner\":").Append(Bool(item.Hero.IsPrisoner));
            Property(json, "locationId", LocationComplex.Current?.GetLocationOfCharacter(item.Hero)?.StringId, true);
            json.Append(",\"questMarkers\":[");
            for (var markerIndex = 0; markerIndex < questMarkers.Count; markerIndex++)
            {
                if (markerIndex > 0) json.Append(',');
                var marker = questMarkers[markerIndex];
                json.Append('{');
                Property(json, "type", marker.Item1.ToString());
                Property(json, "title", marker.Item2?.ToString(), true);
                Property(json, "hint", marker.Item3?.ToString(), true);
                json.Append('}');
            }
            json.Append("]}");
        }
        json.Append(']');
        return json.ToString();
    }

    private static StringBuilder Property(StringBuilder json, string key, string value, bool prependComma = false)
    {
        if (prependComma) json.Append(',');
        json.Append('"').Append(Escape(key)).Append("\":");
        return value == null ? json.Append("null") : json.Append('"').Append(Escape(value)).Append('"');
    }

    private static string PartyType(MobileParty party) => party.IsLordParty ? "lord" : party.IsBandit ? "bandit" : party.IsCaravan ? "caravan" : party.IsVillager ? "villager" : party.IsPatrolParty ? "patrol" : party.IsGarrison ? "garrison" : "other";
    private static void AppendPlayerCaptivityContext(StringBuilder json, Campaign campaign, string menuId)
    {
        var playerCaptivity = campaign?.PlayerCaptivity;
        if (playerCaptivity == null || !PlayerCaptivity.IsCaptive)
        {
            json.Append("null");
            return;
        }

        var ransomOfferVisible = string.Equals(menuId, "menu_captivity_end_propose_ransom_wilderness", StringComparison.Ordinal) ||
            string.Equals(menuId, "menu_captivity_end_propose_ransom_in_prison", StringComparison.Ordinal);
        json.Append('{').Append("\"isCaptive\":true");
        Property(json, "currentMenuId", menuId, true);
        json.Append(",\"ransomOfferVisible\":").Append(Bool(ransomOfferVisible));
        json.Append(",\"currentVisibleRansomAmount\":");
        if (ransomOfferVisible) json.Append(playerCaptivity.CurrentRansomAmount);
        else json.Append("null");
        json.Append('}');
    }

    internal static string GetPartyTypeForObservation(MobileParty party) => PartyType(party);
    private static bool IsHostile(IFaction first, IFaction second) => first != null && second != null && FactionManager.IsAtWarAgainstFaction(first, second);
    private static double Distance(float x1, float y1, float x2, float y2) { var x = x1 - x2; var y = y1 - y2; return Math.Sqrt(x * x + y * y); }
    private static double Distance3D(TaleWorlds.Library.Vec3 first, TaleWorlds.Library.Vec3 second) { var x = first.X - second.X; var y = first.Y - second.Y; var z = first.Z - second.Z; return Math.Sqrt(x * x + y * y + z * z); }
    private static string Number(double value) => value.ToString("0.###", CultureInfo.InvariantCulture);
    private static string Bool(bool value) => value ? "true" : "false";
    private static string Escape(string value) => (value ?? string.Empty).Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\r", "\\r").Replace("\n", "\\n");
}
