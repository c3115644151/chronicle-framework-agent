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
    private void DispatchCommand(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        switch (action)
        {
            case "state":
                HandleState(behavior, commandId, action, command);
                break;
            case "agentCheckpointGet":
                HandleAgentCheckpointGet(behavior, commandId, action, command);
                break;
            case "agentCheckpointSet":
                HandleAgentCheckpointSet(behavior, commandId, action, command);
                break;
            case "harnessSeedAgentCheckpointFailure":
                HandleHarnessSeedAgentCheckpointFailure(behavior, commandId, action, command);
                break;
            case "closeEscapeMenu":
                HandleCloseEscapeMenu(behavior, commandId, action, command);
                break;
            case "respondInquiry":
                HandleRespondInquiry(behavior, commandId, action, command);
                break;
            case "respondMultiSelectionInquiry":
                HandleRespondMultiSelectionInquiry(behavior, commandId, action, command);
                break;
            case "mapSettlementTargets":
                HandleMapSettlementTargets(behavior, commandId, action, command);
                break;
            case "mapNotifications":
                HandleMapNotifications(behavior, commandId, action, command);
                break;
            case "quickInformation":
                HandleQuickInformation(behavior, commandId, action, command);
                break;
            case "sceneNotification":
                HandleSceneNotification(behavior, commandId, action, command);
                break;
            case "continueSceneNotification":
                HandleContinueSceneNotification(behavior, commandId, action, command);
                break;
            case "incidentSelect":
                HandleIncidentSelect(behavior, commandId, action, command);
                break;
            case "harnessSeedMapIncidentFixture":
                HandleHarnessSeedMapIncidentFixture(behavior, commandId, action, command);
                break;
            case "submitStoryModeClanName":
                HandleSubmitStoryModeClanName(behavior, commandId, action, command);
                break;
            case "bannerEditorDone":
                HandleBannerEditorDone(behavior, commandId, action, command);
                break;
            case "harnessSeedMapNotificationFixture":
                HandleHarnessSeedMapNotificationFixture(behavior, commandId, action, command);
                break;
            case "harnessSeedQuickInformationFixture":
                HandleHarnessSeedQuickInformationFixture(behavior, commandId, action, command);
                break;
            case "harnessSeedSceneNotificationFixture":
                HandleHarnessSeedSceneNotificationFixture(behavior, commandId, action, command);
                break;
            case "mapPartyTargets":
                HandleMapPartyTargets(behavior, commandId, action, command);
                break;
            case "mapPartyComposition":
                HandleMapPartyComposition(behavior, commandId, action, command);
                break;
            case "mapPartyBehavior":
                HandleMapPartyBehavior(behavior, commandId, action, command);
                break;
            case "characterDevelopment":
                HandleCharacterDevelopment(behavior, commandId, action, command);
                break;
            case "spendSkillFocus":
                HandleSpendSkillFocus(behavior, commandId, action, command);
                break;
            case "partyUpgradeOptions":
                HandlePartyUpgradeOptions(behavior, commandId, action, command);
                break;
            case "upgradeTroop":
                HandleUpgradeTroop(behavior, commandId, action, command);
                break;
            case "prisonerRecruitmentOptions":
                HandlePrisonerRecruitmentOptions(behavior, commandId, action, command);
                break;
            case "recruitPrisoner":
                HandleRecruitPrisoner(behavior, commandId, action, command);
                break;
            case "harnessSeedPartyUpgradeFixture":
                HandleHarnessSeedPartyUpgradeFixture(behavior, commandId, action, command);
                break;
            case "harnessSeedPrisonerRecruitmentFixture":
                HandleHarnessSeedPrisonerRecruitmentFixture(behavior, commandId, action, command);
                break;
            case "harnessSeedRecruitmentCapacityFixture":
                HandleHarnessSeedRecruitmentCapacityFixture(behavior, commandId, action, command);
                break;
            case "harnessPrepareCompanionHiringFixture":
                HandleHarnessPrepareCompanionHiringFixture(behavior, commandId, action, command);
                break;
            case "harnessCompanionHiringDiagnostics":
                HandleHarnessCompanionHiringDiagnostics(behavior, commandId, action, command);
                break;
            case "harnessSeedPartyRoleFixture":
                HandleHarnessSeedPartyRoleFixture(behavior, commandId, action, command);
                break;
            case "harnessPartyRoleDiagnostics":
                HandleHarnessPartyRoleDiagnostics(behavior, commandId, action, command);
                break;
            case "harnessSeedEquipmentModifierFixture":
                HandleHarnessSeedEquipmentModifierFixture(behavior, commandId, action, command);
                break;
            case "harnessClearEquipmentModifierFixture":
                HandleHarnessClearEquipmentModifierFixture(behavior, commandId, action, command);
                break;
            case "harnessOpenInventoryState":
                HandleHarnessOpenInventoryState(behavior, commandId, action, command);
                break;
            case "harnessCloseInventoryState":
                HandleHarnessCloseInventoryState(behavior, commandId, action, command);
                break;
            case "harnessInventoryStateDiagnostics":
                HandleHarnessInventoryStateDiagnostics(behavior, commandId, action, command);
                break;
            case "questDetails":
                HandleQuestDetails(behavior, commandId, action, command);
                break;
            case "partyRoster":
                HandlePartyRoster(behavior, commandId, action, command);
                break;
            case "partyRoles":
                HandlePartyRoles(behavior, commandId, action, command);
                break;
            case "inventoryOpen":
                HandleInventoryOpen(behavior, commandId, action, command);
                break;
            case "heroEquipmentOptions":
                HandleHeroEquipmentOptions(behavior, commandId, action, command);
                break;
            case "equipHeroItem":
                HandleEquipHeroItem(behavior, commandId, action, command);
                break;
            case "unequipHeroItem":
                HandleUnequipHeroItem(behavior, commandId, action, command);
                break;
            case "inventoryConfirm":
                HandleInventoryConfirm(behavior, commandId, action, command);
                break;
            case "inventoryCancel":
                HandleInventoryCancel(behavior, commandId, action, command);
                break;
            case "inventoryCancelChanges":
                HandleInventoryCancelChanges(behavior, commandId, action, command);
                break;
            case "setPartyRole":
                HandleSetPartyRole(behavior, commandId, action, command);
                break;
            case "unassignPartyRole":
                HandleUnassignPartyRole(behavior, commandId, action, command);
                break;
            case "harnessMissionDiagnostics":
                HandleHarnessMissionDiagnostics(behavior, commandId, action, command);
                break;
            case "harnessMapDiagnostics":
                HandleHarnessMapDiagnostics(behavior, commandId, action, command);
                break;
            case "harnessOpenMapEscapeMenu":
                HandleHarnessOpenMapEscapeMenu(behavior, commandId, action, command);
                break;
            case "harnessOpenNativeInquiry":
                HandleHarnessOpenNativeInquiry(behavior, commandId, action, command);
                break;
            case "harnessOpenRecruitmentInquiry":
                HandleHarnessOpenRecruitmentInquiry(behavior, commandId, action, command);
                break;
            case "harnessNativeInquiryDiagnostics":
                HandleHarnessNativeInquiryDiagnostics(behavior, commandId, action, command);
                break;
            case "harnessPrepareAlleyLeaderFixture":
                HandleHarnessPrepareAlleyLeaderFixture(behavior, commandId, action, command);
                break;
            case "harnessAlleyLeaderDiagnostics":
                HandleHarnessAlleyLeaderDiagnostics(behavior, commandId, action, command);
                break;
            case "harnessPrepareAlleyRosterFixture":
                HandleHarnessPrepareAlleyRosterFixture(behavior, commandId, action, command);
                break;
            case "harnessSeedAlleyAttackFixture":
                HandleHarnessSeedAlleyAttackFixture(behavior, commandId, action, command);
                break;
            case "harnessSeedPersuasionFixture":
                HandleHarnessSeedPersuasionFixture(behavior, commandId, action, command);
                break;
            case "harnessCurrentConversationAnswers":
                HandleHarnessCurrentConversationAnswers(behavior, commandId, action, command);
                break;
            case "harnessAlleyRosterDiagnostics":
                HandleHarnessAlleyRosterDiagnostics(behavior, commandId, action, command);
                break;
            case "harnessPlayerSkillsDiagnostics":
                HandleHarnessPlayerSkillsDiagnostics(behavior, commandId, action, command);
                break;
            case "harnessCharacterDevelopmentDiagnostics":
                HandleHarnessCharacterDevelopmentDiagnostics(behavior, commandId, action, command);
                break;
            case "harnessQuestDetailsDiagnostics":
                HandleHarnessQuestDetailsDiagnostics(behavior, commandId, action, command);
                break;
            case "harnessQuestDeadlinePrivacyDiagnostics":
                HandleHarnessQuestDeadlinePrivacyDiagnostics(behavior, commandId, action, command);
                break;
            case "harnessPartyRosterDiagnostics":
                HandleHarnessPartyRosterDiagnostics(behavior, commandId, action, command);
                break;
            case "harnessMapPartyDiagnostics":
                HandleHarnessMapPartyDiagnostics(behavior, commandId, action, command);
                break;
            case "harnessMapPartyCompositionDiagnostics":
                HandleHarnessMapPartyCompositionDiagnostics(behavior, commandId, action, command);
                break;
            case "harnessCreateMapArmyFixture":
                HandleHarnessCreateMapArmyFixture(behavior, commandId, action, command);
                break;
            case "harnessPrepareMovingArmyEncounter":
                HandleHarnessPrepareMovingArmyEncounter(behavior, commandId, action, command);
                break;
            case "harnessArmyEncounterDiagnostics":
                HandleHarnessArmyEncounterDiagnostics(behavior, commandId, action, command);
                break;
            case "harnessPrepareSiegeJoinFixture":
                HandleHarnessPrepareSiegeJoinFixture(behavior, commandId, action, command);
                break;
            case "harnessSiegeJoinDiagnostics":
                HandleHarnessSiegeJoinDiagnostics(behavior, commandId, action, command);
                break;
            case "harnessSeedMapPartyIssueMarker":
                HandleHarnessSeedMapPartyIssueMarker(behavior, commandId, action, command);
                break;
            case "harnessPrepareSafePassageFixture":
                HandleHarnessPrepareSafePassageFixture(behavior, commandId, action, command);
                break;
            case "harnessSeedCaptivityObservationFixture":
                HandleHarnessSeedCaptivityObservationFixture(behavior, commandId, action, command);
                break;
            case "harnessSeedPrisonCaptivityFixture":
                HandleHarnessSeedPrisonCaptivityFixture(behavior, commandId, action, command);
                break;
            case "harnessPrepareSurrenderCondition":
                HandleHarnessPrepareSurrenderCondition(behavior, commandId, action, command);
                break;
            case "harnessSeedTryGetAwayFixture":
                HandleHarnessSeedTryGetAwayFixture(behavior, commandId, action, command);
                break;
            case "harnessTryGetAwayDiagnostics":
                HandleHarnessTryGetAwayDiagnostics(behavior, commandId, action, command);
                break;
            case "harnessSeedNpcBattleForPlayerJoin":
                HandleHarnessSeedNpcBattleForPlayerJoin(behavior, commandId, action, command);
                break;
            case "harnessPrepareArmyMemberForCurrentJoinEncounter":
                HandleHarnessPrepareArmyMemberForCurrentJoinEncounter(behavior, commandId, action, command);
                break;
            case "harnessJoinEncounterDiagnostics":
                HandleHarnessJoinEncounterDiagnostics(behavior, commandId, action, command);
                break;
            case "harnessSwitchCaptivityObservationMenu":
                HandleHarnessSwitchCaptivityObservationMenu(behavior, commandId, action, command);
                break;
            case "harnessCaptivityDiagnostics":
                HandleHarnessCaptivityDiagnostics(behavior, commandId, action, command);
                break;
            case "harnessPreparePursuitVisibilityFixture":
                HandleHarnessPreparePursuitVisibilityFixture(behavior, commandId, action, command);
                break;
            case "talkToSettlementHero":
                HandleTalkToSettlementHero(behavior, commandId, action, command);
                break;
            case "visitSettlementHero":
                HandleVisitSettlementHero(behavior, commandId, action, command);
                break;
            case "captureFrame":
                HandleCaptureFrame(behavior, commandId, action, command);
                break;
            case "inventoryTakeAll":
                HandleInventoryTakeAll(behavior, commandId, action, command);
                break;
            case "inventoryDone":
                HandleInventoryDone(behavior, commandId, action, command);
                break;
            case "advance":
                HandleAdvance(behavior, commandId, action, command);
                break;
            case "rest":
                HandleRest(behavior, commandId, action, command);
                break;
            case "pursue":
                HandlePursue(behavior, commandId, action, command);
                break;
            case "follow":
                HandleFollow(behavior, commandId, action, command);
                break;
            case "hold":
                HandleHold(behavior, commandId, action, command);
                break;
            case "pause":
                HandlePause(behavior, commandId, action, command);
                break;
            case "resume":
                HandleResume(behavior, commandId, action, command);
                break;
            case "fastForward":
                HandleFastForward(behavior, commandId, action, command);
                break;
            case "move":
                HandleMove(behavior, commandId, action, command);
                break;
            case "moveToPoint":
                HandleMoveToPoint(behavior, commandId, action, command);
                break;
            case "battleMissionStatus":
                HandleBattleMissionStatus(behavior, commandId, action, command);
                break;
            case "harnessCloseMissionOrderMenu":
                HandleHarnessCloseMissionOrderMenu(behavior, commandId, action, command);
                break;
            case "harnessPrepareCameraMotionBaseline":
                HandleHarnessPrepareCameraMotionBaseline(behavior, commandId, action, command);
                break;
            case "missionDelegateTroops":
                HandleMissionDelegateTroops(behavior, commandId, action, command);
                break;
            case "missionAutopilotMainAgent":
                HandleMissionAutopilotMainAgent(behavior, commandId, action, command);
                break;
            case "missionFinishDeployment":
                HandleMissionFinishDeployment(behavior, commandId, action, command);
                break;
            case "missionAutoDeploy":
                HandleMissionAutoDeploy(behavior, commandId, action, command);
                break;
            case "harnessMainAgentAiControllerProbe":
                HandleHarnessMainAgentAiControllerProbe(behavior, commandId, action, command);
                break;
            case "harnessMainAgentNativeAiHandoffProbe":
                HandleHarnessMainAgentNativeAiHandoffProbe(behavior, commandId, action, command);
                break;
            case "harnessMainAgentAiSurrogateControllerProbe":
                HandleHarnessMainAgentAiSurrogateControllerProbe(behavior, commandId, action, command);
                break;
            case "harnessRefreshMainAgentFormationAiProbe":
                HandleHarnessRefreshMainAgentFormationAiProbe(behavior, commandId, action, command);
                break;
            case "harnessNotifyMainAgentAiMovementOrderProbe":
                HandleHarnessNotifyMainAgentAiMovementOrderProbe(behavior, commandId, action, command);
                break;
            case "harnessMainAgentAiRtsCameraProbe":
                HandleHarnessMainAgentAiRtsCameraProbe(behavior, commandId, action, command);
                break;
            case "harnessRestoreMainAgentAiControllerProbe":
                HandleHarnessRestoreMainAgentAiControllerProbe(behavior, commandId, action, command);
                break;
            case "missionSceneAgents":
                HandleMissionSceneAgents(behavior, commandId, action, command);
                break;
            case "missionInput":
                HandleMissionInput(behavior, commandId, action, command);
                break;
            case "harnessBattleMovementInputProbe":
                HandleHarnessBattleMovementInputProbe(behavior, commandId, action, command);
                break;
            case "harnessBattleAgentNavigatorProbe":
                HandleHarnessBattleAgentNavigatorProbe(behavior, commandId, action, command);
                break;
            case "missionNavigateToAgent":
                HandleMissionNavigateToAgent(behavior, commandId, action, command);
                break;
            case "missionLeave":
                HandleMissionLeave(behavior, commandId, action, command);
                break;
            case "tournamentJoin":
            case "tournamentSkipRound":
            case "tournamentSkipAllRounds":
            case "tournamentWatchRound":
            case "tournamentLeave":
                HandleTournament(behavior, commandId, action, command);
                break;
            case "missionInteract":
                HandleMissionInteract(behavior, commandId, action, command);
                break;
            case "missionCancelNavigation":
                HandleMissionCancelNavigation(behavior, commandId, action, command);
                break;
            case "missionAimAt":
                HandleMissionAimAt(behavior, commandId, action, command);
                break;
            case "menu":
                HandleMenu(behavior, commandId, action, command);
                break;
            case "recruitOptions":
                HandleRecruitOptions(behavior, commandId, action, command);
                break;
            case "recruit":
                HandleRecruit(behavior, commandId, action, command);
                break;
            case "recruitAll":
                HandleRecruitAll(behavior, commandId, action, command);
                break;
            case "foodOptions":
                HandleFoodOptions(behavior, commandId, action, command);
                break;
            case "tradeOptions":
                HandleTradeOptions(behavior, commandId, action, command);
                break;
            case "tradeRumors":
                HandleTradeRumors(behavior, commandId, action, command);
                break;
            case "harnessSeedTradeRumorFixture":
                HandleHarnessSeedTradeRumorFixture(behavior, commandId, action, command);
                break;
            case "harnessTradeRumorTooltipDiagnostics":
                HandleHarnessTradeRumorTooltipDiagnostics(behavior, commandId, action, command);
                break;
            case "trade":
                HandleTrade(behavior, commandId, action, command);
                break;
            case "provision":
                HandleProvision(behavior, commandId, action, command);
                break;
            case "tradeConfirm":
                HandleTradeConfirm(behavior, commandId, action, command);
                break;
            case "tradeCancel":
                HandleTradeCancel(behavior, commandId, action, command);
                break;
            case "tradeCancelChanges":
                HandleTradeCancelChanges(behavior, commandId, action, command);
                break;
            case "barterOptions":
                HandleBarterOptions(behavior, commandId, action, command);
                break;
            case "barterEdit":
                HandleBarterEdit(behavior, commandId, action, command);
                break;
            case "barterReset":
                HandleBarterReset(behavior, commandId, action, command);
                break;
            case "barterAutoBalance":
                HandleBarterAutoBalance(behavior, commandId, action, command);
                break;
            case "barterOffer":
                HandleBarterOffer(behavior, commandId, action, command);
                break;
            case "barterCancel":
                HandleBarterCancel(behavior, commandId, action, command);
                break;
            case "menuSelect":
                HandleMenuSelect(behavior, commandId, action, command);
                break;
            case "dialogueSelect":
                HandleDialogueSelect(behavior, commandId, action, command);
                break;
            case "persuasionDetails":
                HandlePersuasionDetails(behavior, commandId, action, command);
                break;
            case "dialogueContinue":
                HandleDialogueContinue(behavior, commandId, action, command);
                break;
            case "battlePause":
                HandleBattlePause(behavior, commandId, action, command);
                break;
            case "battleSkip":
                HandleBattleSkip(behavior, commandId, action, command);
                break;
            case "seedVisualLoot":
                HandleSeedVisualLoot(behavior, commandId, action, command);
                break;
            case "battleFinish":
                HandleBattleFinish(behavior, commandId, action, command);
                break;
            case "battleRetreat":
                HandleBattleRetreat(behavior, commandId, action, command);
                break;
            case "missionRetreat":
                HandleMissionRetreat(behavior, commandId, action, command);
                break;
            case "partyTakeAll":
                HandlePartyTakeAll(behavior, commandId, action, command);
                break;
            case "partyLootTransferOne":
                HandlePartyLootTransferOne(behavior, commandId, action, command);
                break;
            case "sellPrisonerOne":
                HandleSellPrisonerOne(behavior, commandId, action, command);
                break;
            case "partyScreenCancel":
                HandlePartyScreenCancel(behavior, commandId, action, command);
                break;
            case "partyScreenDone":
                HandlePartyScreenDone(behavior, commandId, action, command);
                break;
            case "questTroopTransfer":
                HandleQuestTroopTransfer(behavior, commandId, action, command);
                break;
            case "questTroopScreenDone":
                HandleQuestTroopScreenDone(behavior, commandId, action, command);
                break;
            case "questTroopScreenCancel":
                HandleQuestTroopScreenCancel(behavior, commandId, action, command);
                break;
            case "alleyRosterTransfer":
                HandleAlleyRosterTransfer(behavior, commandId, action, command);
                break;
            case "alleyRosterCancel":
                HandleAlleyRosterCancel(behavior, commandId, action, command);
                break;
            case "save":
                HandleSave(behavior, commandId, action, command);
                break;
            case "stop":
                HandleStop(behavior, commandId, action, command);
                break;
            default:
                WriteResponse(commandId, action, "rejected", behavior, "unknown action");
                break;
        }
    }
}
