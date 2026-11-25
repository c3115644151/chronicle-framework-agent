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
    private static string SeedPartyUpgradeFixture()
    {
        var party = MobileParty.MainParty;
        var hero = Hero.MainHero;
        if (Campaign.Current == null || party == null || hero == null)
            throw new InvalidOperationException("Upgrade fixture requires an active MainParty and MainHero");

        TaleWorlds.CampaignSystem.CharacterObject chosenCharacter = null;
        TaleWorlds.CampaignSystem.CharacterObject chosenTarget = null;
        var chosenTargetIndex = -1;
        var chosenXpCost = 0;
        var chosenGoldCost = 0;
        foreach (var character in TaleWorlds.CampaignSystem.CharacterObject.All
            .Where(item => item != null && !item.IsHero && item.UpgradeTargets != null && item.UpgradeTargets.Length > 0 && party.MemberRoster.FindIndexOfTroop(item) < 0)
            .OrderBy(item => item.Tier).ThenBy(item => item.StringId, StringComparer.Ordinal))
        {
            for (var targetIndex = 0; targetIndex < character.UpgradeTargets.Length; targetIndex++)
            {
                var target = character.UpgradeTargets[targetIndex];
                if (target == null || target.UpgradeRequiresItemFromCategory != null) continue;
                if (!Campaign.Current.Models.PartyTroopUpgradeModel.DoesPartyHaveRequiredPerksForUpgrade(party.Party, character, target, out var _)) continue;
                var xpCost = character.GetUpgradeXpCost(party.Party, targetIndex);
                var goldCost = character.GetUpgradeGoldCost(party.Party, targetIndex);
                if (xpCost <= 0 || goldCost < 0 || goldCost > hero.Gold) continue;
                chosenCharacter = character;
                chosenTarget = target;
                chosenTargetIndex = targetIndex;
                chosenXpCost = xpCost;
                chosenGoldCost = goldCost;
                break;
            }
            if (chosenCharacter != null) break;
        }
        if (chosenCharacter == null)
            throw new InvalidOperationException("No disposable troop has an item-free, perk-eligible upgrade target affordable by MainHero");

        var membersBefore = party.MemberRoster.TotalManCount;
        var goldBefore = hero.Gold;
        party.MemberRoster.AddToCounts(chosenCharacter, 1);
        var rosterIndex = party.MemberRoster.FindIndexOfTroop(chosenCharacter);
        if (rosterIndex < 0) throw new InvalidOperationException("Harness could not seed the native MainParty troop roster");
        party.MemberRoster.SetElementXp(rosterIndex, chosenXpCost);

        var json = new StringBuilder(512);
        json.Append('{');
        json.Append("\"characterId\":\"").Append(Escape(chosenCharacter.StringId)).Append('"');
        json.Append(",\"characterName\":\"").Append(Escape(chosenCharacter.Name?.ToString())).Append('"');
        json.Append(",\"upgradeTargetIndex\":").Append(chosenTargetIndex);
        json.Append(",\"targetId\":\"").Append(Escape(chosenTarget.StringId)).Append('"');
        json.Append(",\"targetName\":\"").Append(Escape(chosenTarget.Name?.ToString())).Append('"');
        json.Append(",\"experienceCost\":").Append(chosenXpCost);
        json.Append(",\"goldCost\":").Append(chosenGoldCost);
        json.Append(",\"membersBefore\":").Append(membersBefore);
        json.Append(",\"membersAfter\":").Append(party.MemberRoster.TotalManCount);
        json.Append(",\"goldBefore\":").Append(goldBefore);
        json.Append(",\"goldAfter\":").Append(hero.Gold);
        json.Append('}');
        return json.ToString();
    }

    private static string SeedPrisonerRecruitmentFixture()
    {
        var party = MobileParty.MainParty;
        var hero = Hero.MainHero;
        if (Campaign.Current == null || party == null || hero == null)
            throw new InvalidOperationException("Prisoner recruitment fixture requires an active MainParty and MainHero");
        if (party.MemberRoster.TotalManCount > party.Party.PartySizeLimit)
            throw new InvalidOperationException("Prisoner recruitment fixture cannot establish a clean at-limit roster from an already over-limit party");

        TaleWorlds.CampaignSystem.CharacterObject chosenCharacter = null;
        var conformityCost = 0;
        var model = Campaign.Current.Models.PrisonerRecruitmentCalculationModel;
        var maxTier = Campaign.Current.Models.CharacterStatsModel.MaxCharacterTier;
        foreach (var character in TaleWorlds.CampaignSystem.CharacterObject.All
            .Where(item => item != null && !item.IsHero && item.IsRegular && item.Tier >= 2 && item.Tier <= maxTier && item.Culture != null && !item.Culture.IsBandit && item.Culture != hero.Culture && party.PrisonRoster.FindIndexOfTroop(item) < 0)
            .OrderBy(item => item.Tier).ThenBy(item => item.StringId, StringComparer.Ordinal))
        {
            var threshold = model.GetConformityNeededToRecruitPrisoner(character);
            if (threshold <= 1) continue;
            chosenCharacter = character;
            conformityCost = threshold;
            break;
        }
        if (chosenCharacter == null)
            throw new InvalidOperationException("No non-hero regular troop meets native Tier/Culture constraints for a disposable prisoner fixture");

        var filler = TaleWorlds.CampaignSystem.CharacterObject.All.FirstOrDefault(item => item != null && item != chosenCharacter && !item.IsHero && item.IsRegular && party.MemberRoster.FindIndexOfTroop(item) < 0);
        if (filler == null) throw new InvalidOperationException("No ordinary CharacterObject is available to seed the at-limit MainParty fixture");
        var membersBefore = party.MemberRoster.TotalManCount;
        var sizeLimit = party.Party.PartySizeLimit;
        var fillersAdded = Math.Max(0, sizeLimit - membersBefore);
        if (fillersAdded > 0) party.MemberRoster.AddToCounts(filler, fillersAdded);

        const int prisonerCount = 2;
        var seededConformityXp = conformityCost * prisonerCount - 1;
        party.PrisonRoster.AddToCounts(chosenCharacter, prisonerCount);
        var prisonerIndex = party.PrisonRoster.FindIndexOfTroop(chosenCharacter);
        if (prisonerIndex < 0) throw new InvalidOperationException("Harness could not seed the native MainParty prisoner roster");
        party.PrisonRoster.SetElementXp(prisonerIndex, seededConformityXp);

        var json = new StringBuilder(768);
        json.Append('{');
        json.Append("\"characterId\":\"").Append(Escape(chosenCharacter.StringId)).Append('"');
        json.Append(",\"characterName\":\"").Append(Escape(chosenCharacter.Name?.ToString())).Append('"');
        json.Append(",\"cultureId\":\"").Append(Escape(chosenCharacter.Culture.StringId)).Append('"');
        json.Append(",\"tier\":").Append(chosenCharacter.Tier);
        json.Append(",\"prisonerCount\":").Append(prisonerCount);
        json.Append(",\"conformityCostPerRecruit\":").Append(conformityCost);
        json.Append(",\"conformityXpSeeded\":").Append(seededConformityXp);
        json.Append(",\"availableCountExpected\":1");
        json.Append(",\"memberCountBefore\":").Append(membersBefore);
        json.Append(",\"memberCountAfter\":").Append(party.MemberRoster.TotalManCount);
        json.Append(",\"partySizeLimit\":").Append(sizeLimit);
        json.Append(",\"fillerTroopId\":\"").Append(Escape(filler.StringId)).Append('"');
        json.Append(",\"fillersAdded\":").Append(fillersAdded);
        json.Append('}');
        return json.ToString();
    }

    private static string PrepareCompanionHiringFixture(string heroId, int goldOffset)
    {
        var candidate = FindCurrentObservedMissionHero(heroId);
        var playerClan = Clan.PlayerClan;
        if (candidate.IsPlayerCompanion || candidate.PartyBelongedTo != null || candidate.Clan != null)
            throw new InvalidOperationException("Companion hiring fixture target must be an unowned, unparty Wanderer Hero");
        if (goldOffset is not (-63 or 0 or 1))
            throw new InvalidOperationException("Companion hiring Harness goldOffset must be exactly -63 (below quote), 0 (equal quote), or 1 (above quote)");
        var price = Campaign.Current.Models.CompanionHiringPriceCalculationModel.GetCompanionHiringPrice(candidate);
        var priceGold = Hero.MainHero.Gold;
        var desiredGold = price + goldOffset;
        var goldChange = desiredGold - priceGold;
        if (goldChange != 0) Hero.MainHero.ChangeHeroGold(goldChange);

        var json = new StringBuilder(768);
        json.Append('{');
        json.Append("\"heroId\":\"").Append(Escape(candidate.StringId)).Append('"');
        json.Append(",\"nativeHiringPrice\":").Append(price);
        json.Append(",\"goldBeforeSeed\":").Append(priceGold);
        json.Append(",\"goldChangeForDisposableHarnessFixture\":").Append(goldChange);
        json.Append(",\"playerGoldAfterSeed\":").Append(Hero.MainHero.Gold);
        json.Append(",\"goldStrictlyExceedsPrice\":").Append(Hero.MainHero.Gold > price ? "true" : "false");
        json.Append(",\"playerCompanionCount\":").Append(playerClan.Companions.Count);
        json.Append(",\"companionLimit\":").Append(playerClan.CompanionLimit);
        json.Append('}');
        return json.ToString();
    }

    private static string CreateMapArmyFixture(string leaderPartyId, string attachedPartyId)
    {
        var leaderParty = MobileParty.All.FirstOrDefault(item => item != null && string.Equals(item.StringId, leaderPartyId, StringComparison.Ordinal));
        var kingdom = leaderParty?.MapFaction as Kingdom;
        if (leaderParty == null || kingdom == null || leaderParty == MobileParty.MainParty || !leaderParty.IsActive || !leaderParty.IsVisible || !leaderParty.IsInspected || leaderParty.IsGarrison || leaderParty.IsMilitia || leaderParty.AttachedTo != null || leaderParty.Army != null || leaderParty.LeaderHero == null)
            throw new InvalidOperationException("A native Harness Army requires a current visible inspected independent Lord Party without an Army");
        var attachedParty = string.IsNullOrWhiteSpace(attachedPartyId) ? null : MobileParty.All.FirstOrDefault(item => item != null && string.Equals(item.StringId, attachedPartyId, StringComparison.Ordinal));
        if (attachedPartyId != null && (attachedParty == null || attachedParty == leaderParty || attachedParty == MobileParty.MainParty || attachedParty.MapFaction != kingdom || !attachedParty.IsActive || !attachedParty.IsVisible || !attachedParty.IsInspected || attachedParty.IsGarrison || attachedParty.IsMilitia || attachedParty.AttachedTo != null || attachedParty.Army != null))
            throw new InvalidOperationException("A native Harness Army attachment requires a second current visible inspected independent Party in the same Kingdom");
        var gatheringFocus = leaderParty.TargetSettlement ?? leaderParty.CurrentSettlement ?? kingdom.Settlements.FirstOrDefault(settlement => settlement.IsFortification && !settlement.IsUnderSiege) ?? kingdom.Settlements.FirstOrDefault();
        if (gatheringFocus == null) throw new InvalidOperationException("A native Harness Army requires an available focus settlement");

        var kingdomArmyCountBefore = kingdom.Armies.Count;
        var partiesToCall = attachedParty == null ? null : new TaleWorlds.Library.MBList<MobileParty> { attachedParty };
        kingdom.CreateArmy(leaderParty.LeaderHero, gatheringFocus, Army.ArmyTypes.Patrolling, partiesToCall);
        var army = leaderParty.Army;
        if (army == null || army.LeaderParty != leaderParty || !kingdom.Armies.Contains(army))
            throw new InvalidOperationException("Native Kingdom.CreateArmy did not create a registered Army for the selected Lord Party");
        if (attachedParty != null)
        {
            if (attachedParty.Army != army) throw new InvalidOperationException("Native Kingdom.CreateArmy did not enlist the selected secondary Party");
            army.AddPartyToMergedParties(attachedParty);
        }
        var json = new StringBuilder(512);
        json.Append('{');
        json.Append("\"leaderPartyId\":\"").Append(Escape(leaderParty.StringId)).Append('"');
        json.Append(",\"armyType\":\"").Append(Escape(army.ArmyType.ToString())).Append('"');
        json.Append(",\"armyRegisteredInKingdom\":true");
        json.Append(",\"armyCountBefore\":").Append(kingdomArmyCountBefore);
        json.Append(",\"armyCountAfter\":").Append(kingdom.Armies.Count);
        json.Append(",\"attachedPartyCount\":").Append(leaderParty.AttachedParties.Count);
        json.Append(",\"temporaryAttachedPartyEnlisted\":").Append(attachedParty != null && attachedParty.Army == army ? "true" : "false");
        json.Append('}');
        return json.ToString();
    }
}
