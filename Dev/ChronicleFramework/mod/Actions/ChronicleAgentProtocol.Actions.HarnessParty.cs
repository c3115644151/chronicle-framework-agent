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
    private void HandleHarnessSeedPartyUpgradeFixture(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var upgradeFixtureMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var upgradeFixtureRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(upgradeFixtureMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(upgradeFixtureRoot) || !Directory.Exists(upgradeFixtureRoot))
            throw new InvalidOperationException("harnessSeedPartyUpgradeFixture is restricted to a visual Harness run with a Harness temp directory");
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("harnessSeedPartyUpgradeFixture requires the Campaign Map state");
        WriteResponse(commandId, action, "completed", behavior, null, SeedPartyUpgradeFixture());
    }

    private void HandleHarnessSeedPrisonerRecruitmentFixture(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var prisonerFixtureMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var prisonerFixtureRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(prisonerFixtureMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(prisonerFixtureRoot) || !Directory.Exists(prisonerFixtureRoot))
            throw new InvalidOperationException("harnessSeedPrisonerRecruitmentFixture is restricted to a visual Harness run with a Harness temp directory");
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("harnessSeedPrisonerRecruitmentFixture requires the Campaign Map state");
        WriteResponse(commandId, action, "completed", behavior, null, SeedPrisonerRecruitmentFixture());
    }

    private void HandleHarnessSeedRecruitmentCapacityFixture(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("harnessSeedRecruitmentCapacityFixture requires the Campaign Map state");
        WriteResponse(commandId, action, "completed", behavior, null, HarnessRecruitmentCapacityFixture.SeedMainPartyToCapacity());
    }

    private void HandleHarnessPrepareCompanionHiringFixture(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var companionFixtureMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var companionFixtureRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(companionFixtureMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(companionFixtureRoot) || !Directory.Exists(companionFixtureRoot))
            throw new InvalidOperationException("harnessPrepareCompanionHiringFixture is restricted to a visual Harness run with a Harness temp directory");
        WriteResponse(commandId, action, "completed", behavior, null, PrepareCompanionHiringFixture(ReadString(command, "heroId"), ReadRequiredInteger(command, "goldOffset")));
    }

    private void HandleHarnessCompanionHiringDiagnostics(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var companionDiagnosticsMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var companionDiagnosticsRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(companionDiagnosticsMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(companionDiagnosticsRoot) || !Directory.Exists(companionDiagnosticsRoot))
            throw new InvalidOperationException("harnessCompanionHiringDiagnostics is restricted to a visual Harness run with a Harness temp directory");
        WriteResponse(commandId, action, "completed", behavior, null, BuildCompanionHiringDiagnosticsJson(ReadString(command, "heroId")));
    }

    private void HandleHarnessSeedPartyRoleFixture(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        RequireRoleHarnessMode();
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("harnessSeedPartyRoleFixture requires Campaign Map state");
        WriteResponse(commandId, action, "completed", behavior, null, ChroniclePartyRoleAdapter.SeedDisposableRoleCompanion());
    }

    private void HandleHarnessPartyRoleDiagnostics(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        RequireRoleHarnessMode();
        WriteResponse(commandId, action, "completed", behavior, null, ChroniclePartyRoleAdapter.BuildHarnessDiagnosticsJson());
    }

    private void HandleHarnessSeedEquipmentModifierFixture(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        RequireEquipmentModifierFixtureHarnessMode();
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("harnessSeedEquipmentModifierFixture requires Campaign Map state");
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleHarnessEquipmentModifierFixture.SeedMasterworkSword());
    }

    private void HandleHarnessClearEquipmentModifierFixture(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        RequireEquipmentModifierFixtureHarnessMode();
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("harnessClearEquipmentModifierFixture requires Campaign Map state");
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleHarnessEquipmentModifierFixture.ClearMasterworkSword());
    }

    private void HandleHarnessOpenInventoryState(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleInventoryStateAdapter.OpenThroughNativeMapNavigation(requireHarnessMode: true));
    }

    private void HandleHarnessCloseInventoryState(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleInventoryStateAdapter.CloseAsNativeCancel(requireHarnessMode: true));
    }

    private void HandleHarnessInventoryStateDiagnostics(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleInventoryStateAdapter.BuildHarnessDiagnosticsJson());
    }

    private void HandleHarnessPlayerSkillsDiagnostics(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var skillsDiagnosticsMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var skillsDiagnosticsRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(skillsDiagnosticsMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(skillsDiagnosticsRoot) || !Directory.Exists(skillsDiagnosticsRoot))
            throw new InvalidOperationException("harnessPlayerSkillsDiagnostics is restricted to a visual Harness run with a Harness temp directory");
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("harnessPlayerSkillsDiagnostics requires the Campaign Map state");
        WriteResponse(commandId, action, "completed", behavior, null, BuildHarnessPlayerSkillsDiagnosticsJson());
    }

    private void HandleHarnessCharacterDevelopmentDiagnostics(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var characterDevelopmentDiagnosticsMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var characterDevelopmentDiagnosticsRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(characterDevelopmentDiagnosticsMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(characterDevelopmentDiagnosticsRoot) || !Directory.Exists(characterDevelopmentDiagnosticsRoot))
            throw new InvalidOperationException("harnessCharacterDevelopmentDiagnostics is restricted to a visual Harness run with a Harness temp directory");
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("harnessCharacterDevelopmentDiagnostics requires the Campaign Map state");
        WriteResponse(commandId, action, "completed", behavior, null, BuildHarnessCharacterDevelopmentDiagnosticsJson());
    }

    private void HandleHarnessQuestDetailsDiagnostics(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var questDetailsDiagnosticsMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var questDetailsDiagnosticsRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(questDetailsDiagnosticsMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(questDetailsDiagnosticsRoot) || !Directory.Exists(questDetailsDiagnosticsRoot))
            throw new InvalidOperationException("harnessQuestDetailsDiagnostics is restricted to a visual Harness run with a Harness temp directory");
        var diagnosticQuest = FindObservedOngoingQuest(ReadString(command, "questId"));
        WriteResponse(commandId, action, "completed", behavior, null, BuildHarnessQuestDetailsDiagnosticsJson(diagnosticQuest));
    }

    private void HandleHarnessQuestDeadlinePrivacyDiagnostics(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var questDeadlineDiagnosticsMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var questDeadlineDiagnosticsRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(questDeadlineDiagnosticsMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(questDeadlineDiagnosticsRoot) || !Directory.Exists(questDeadlineDiagnosticsRoot))
            throw new InvalidOperationException("harnessQuestDeadlinePrivacyDiagnostics is restricted to a visual Harness run with a Harness temp directory");
        WriteResponse(commandId, action, "completed", behavior, null, BuildHarnessQuestDeadlinePrivacyDiagnosticsJson());
    }

    private void HandleHarnessPartyRosterDiagnostics(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var partyRosterDiagnosticsMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var partyRosterDiagnosticsRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(partyRosterDiagnosticsMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(partyRosterDiagnosticsRoot) || !Directory.Exists(partyRosterDiagnosticsRoot))
            throw new InvalidOperationException("harnessPartyRosterDiagnostics is restricted to a visual Harness run with a Harness temp directory");
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("harnessPartyRosterDiagnostics requires the Campaign Map state");
        WriteResponse(commandId, action, "completed", behavior, null, BuildHarnessPartyRosterDiagnosticsJson());
    }

    private void HandleHarnessPrepareMovingArmyEncounter(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var movingArmyFixtureMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var movingArmyFixtureRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(movingArmyFixtureMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(movingArmyFixtureRoot) || !Directory.Exists(movingArmyFixtureRoot))
            throw new InvalidOperationException("harnessPrepareMovingArmyEncounter is restricted to a visual Harness run with a Harness temp directory");
        if (Game.Current?.GameStateManager?.ActiveState is not MapState || Campaign.Current == null)
            throw new InvalidOperationException("harnessPrepareMovingArmyEncounter requires the Campaign Map state");
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleHarnessJoinEncounterFixture.PrepareMovingArmyEncounter(ReadString(command, "partyId")));
    }

    private void HandleHarnessArmyEncounterDiagnostics(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var armyEncounterDiagnosticsMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var armyEncounterDiagnosticsRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(armyEncounterDiagnosticsMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(armyEncounterDiagnosticsRoot) || !Directory.Exists(armyEncounterDiagnosticsRoot))
            throw new InvalidOperationException("harnessArmyEncounterDiagnostics is restricted to a visual Harness run with a Harness temp directory");
        if (Game.Current?.GameStateManager?.ActiveState is not MapState || Campaign.Current == null)
            throw new InvalidOperationException("harnessArmyEncounterDiagnostics requires the Campaign Map state");
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleHarnessJoinEncounterFixture.BuildMovingArmyEncounterDiagnostics(ReadString(command, "partyId")));
    }

    private void HandleHarnessPrepareSiegeJoinFixture(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var siegeJoinFixtureMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var siegeJoinFixtureRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(siegeJoinFixtureMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(siegeJoinFixtureRoot) || !Directory.Exists(siegeJoinFixtureRoot))
            throw new InvalidOperationException("harnessPrepareSiegeJoinFixture is restricted to a visual Harness run with a Harness temp directory");
        if (Game.Current?.GameStateManager?.ActiveState is not MapState || Campaign.Current == null)
            throw new InvalidOperationException("harnessPrepareSiegeJoinFixture requires the Campaign Map state");
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleHarnessSiegeJoinFixture.PrepareNativeSiegeJoin(ReadString(command, "settlementId")));
    }

    private void HandleHarnessSiegeJoinDiagnostics(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var siegeJoinDiagnosticsMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var siegeJoinDiagnosticsRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(siegeJoinDiagnosticsMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(siegeJoinDiagnosticsRoot) || !Directory.Exists(siegeJoinDiagnosticsRoot))
            throw new InvalidOperationException("harnessSiegeJoinDiagnostics is restricted to a visual Harness run with a Harness temp directory");
        if (Game.Current?.GameStateManager?.ActiveState is not MapState || Campaign.Current == null)
            throw new InvalidOperationException("harnessSiegeJoinDiagnostics requires the Campaign Map state");
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleHarnessSiegeJoinFixture.BuildSiegeJoinDiagnostics(ReadString(command, "settlementId"), ReadString(command, "armyLeaderPartyId")));
    }

    private void HandleHarnessPrepareSafePassageFixture(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var safePassageFixtureMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var safePassageFixtureRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(safePassageFixtureMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(safePassageFixtureRoot) || !Directory.Exists(safePassageFixtureRoot))
            throw new InvalidOperationException("harnessPrepareSafePassageFixture is restricted to a visual Harness run with a Harness temp directory");
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("harnessPrepareSafePassageFixture requires the Campaign Map state");
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleHarnessSafePassageFixture.CreateAttackingBanditParty());
    }

    private void HandleHarnessSeedCaptivityObservationFixture(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var captivityFixtureMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var captivityFixtureRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(captivityFixtureMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(captivityFixtureRoot) || !Directory.Exists(captivityFixtureRoot))
            throw new InvalidOperationException("harnessSeedCaptivityObservationFixture is restricted to a visual Harness run with a Harness temp directory");
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("harnessSeedCaptivityObservationFixture requires the Campaign Map state");
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleHarnessCaptivityObservationFixture.StartWithNativeWildernessRansomOffer(ReadString(command, "partyId")));
    }

    private void HandleHarnessSeedPrisonCaptivityFixture(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var prisonCaptivityFixtureMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var prisonCaptivityFixtureRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(prisonCaptivityFixtureMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(prisonCaptivityFixtureRoot) || !Directory.Exists(prisonCaptivityFixtureRoot))
            throw new InvalidOperationException("harnessSeedPrisonCaptivityFixture is restricted to a visual Harness run with a Harness temp directory");
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("harnessSeedPrisonCaptivityFixture requires the Campaign Map state");
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleHarnessCaptivityObservationFixture.StartWithNativePrisonRansomOffer(ReadString(command, "settlementId")));
    }

    private void HandleHarnessPrepareSurrenderCondition(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var surrenderFixtureMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var surrenderFixtureRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(surrenderFixtureMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(surrenderFixtureRoot) || !Directory.Exists(surrenderFixtureRoot))
            throw new InvalidOperationException("harnessPrepareSurrenderCondition is restricted to a visual Harness run with a Harness temp directory");
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("harnessPrepareSurrenderCondition requires the Campaign Map state");
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleHarnessEncounterSurrenderFixture.PrepareNativeSurrenderCondition());
    }

    private void HandleHarnessSeedTryGetAwayFixture(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var tryGetAwayFixtureMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var tryGetAwayFixtureRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(tryGetAwayFixtureMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(tryGetAwayFixtureRoot) || !Directory.Exists(tryGetAwayFixtureRoot))
            throw new InvalidOperationException("harnessSeedTryGetAwayFixture is restricted to a visual Harness run with a Harness temp directory");
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleHarnessEncounterEscapeFixture.SeedMainPartyForNativeEscape());
    }

    private void HandleHarnessTryGetAwayDiagnostics(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleHarnessEncounterEscapeFixture.BuildNativeEscapeDiagnostics());
    }

    private void HandleHarnessPrepareArmyMemberForCurrentJoinEncounter(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var joinArmyFixtureMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var joinArmyFixtureRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(joinArmyFixtureMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(joinArmyFixtureRoot) || !Directory.Exists(joinArmyFixtureRoot))
            throw new InvalidOperationException("harnessPrepareArmyMemberForCurrentJoinEncounter is restricted to a visual Harness run with a Harness temp directory");
        if (Game.Current?.GameStateManager?.ActiveState is not MapState || !PlayerEncounter.IsActive || Campaign.Current.CurrentMenuContext?.GameMenu?.StringId != "join_encounter")
            throw new InvalidOperationException("harnessPrepareArmyMemberForCurrentJoinEncounter requires the current Native join_encounter menu in MapState");
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleHarnessJoinEncounterFixture.PrepareArmyMemberForCurrentJoinEncounter());
    }

    private void HandleHarnessJoinEncounterDiagnostics(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleHarnessJoinEncounterFixture.BuildJoinEncounterDiagnostics(
            ReadString(command, "partyId"), ReadString(command, "armyLeaderPartyId")));
    }

    private void HandleHarnessSwitchCaptivityObservationMenu(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var captivityMenuFixtureMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var captivityMenuFixtureRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(captivityMenuFixtureMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(captivityMenuFixtureRoot) || !Directory.Exists(captivityMenuFixtureRoot))
            throw new InvalidOperationException("harnessSwitchCaptivityObservationMenu is restricted to a visual Harness run with a Harness temp directory");
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("harnessSwitchCaptivityObservationMenu requires the Campaign Map state");
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleHarnessCaptivityObservationFixture.SwitchToNativeWildernessEscapeMenu());
    }

    private void HandleHarnessCaptivityDiagnostics(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleHarnessCaptivityObservationFixture.BuildCaptivityDiagnostics(ReadString(command, "partyId")));
    }
}
