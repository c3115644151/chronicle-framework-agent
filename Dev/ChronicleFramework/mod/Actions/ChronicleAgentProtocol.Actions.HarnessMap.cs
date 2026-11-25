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
    private void HandleHarnessSeedMapIncidentFixture(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentMapIncidentAdapter.SeedHarnessFixture());
    }

    private void HandleHarnessSeedMapNotificationFixture(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentMapNotifications.SeedHarnessFixture());
    }

    private void HandleHarnessSeedQuickInformationFixture(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentQuickInformation.SeedHarnessFixture());
    }

    private void HandleHarnessSeedSceneNotificationFixture(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentSceneNotification.SeedHarnessFixture());
    }

    private void HandleHarnessMapDiagnostics(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var mapDiagnosticsMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var mapDiagnosticsRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(mapDiagnosticsMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(mapDiagnosticsRoot) || !Directory.Exists(mapDiagnosticsRoot))
            throw new InvalidOperationException("harnessMapDiagnostics is restricted to a visual Harness run with a Harness temp directory");
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("harnessMapDiagnostics requires the Campaign Map state");
        WriteResponse(commandId, action, "completed", behavior, null, BuildHarnessMapDiagnosticsJson(ReadString(command, "heroId")));
    }

    private void HandleHarnessOpenMapEscapeMenu(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var escapeFixtureMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var escapeFixtureRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(escapeFixtureMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(escapeFixtureRoot) || !Directory.Exists(escapeFixtureRoot))
            throw new InvalidOperationException("harnessOpenMapEscapeMenu is restricted to a visual Harness run with a Harness temp directory");
        if (Game.Current?.GameStateManager?.ActiveState is not MapState mapStateForEscapeFixture || mapStateForEscapeFixture.AtMenu)
            throw new InvalidOperationException("harnessOpenMapEscapeMenu requires an unobstructed Campaign Map");
        if (MapScreen.Instance == null || MapScreen.Instance.IsEscapeMenuOpened)
            throw new InvalidOperationException("harnessOpenMapEscapeMenu requires a closed Native MapScreen Escape menu");
        MapScreen.Instance.OpenEscapeMenu();
        if (!MapScreen.Instance.IsEscapeMenuOpened)
            throw new InvalidOperationException("Native MapScreen did not open its Escape menu");
        WriteResponse(commandId, action, "completed", behavior, null, BuildHarnessMapDiagnosticsJson());
    }

    private void HandleHarnessOpenNativeInquiry(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var inquiryFixtureMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var inquiryFixtureRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(inquiryFixtureMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(inquiryFixtureRoot) || !Directory.Exists(inquiryFixtureRoot))
            throw new InvalidOperationException("harnessOpenNativeInquiry is restricted to a visual Harness run with a Harness temp directory");
        if (Game.Current?.GameStateManager?.ActiveState is not MapState inquiryFixtureMap || inquiryFixtureMap.AtMenu || MapScreen.Instance?.IsEscapeMenuOpened == true)
            throw new InvalidOperationException("harnessOpenNativeInquiry requires an unobstructed Campaign Map without an Escape menu");
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleInquiryAdapter.BeginHarnessInquiryFixture());
    }

    private void HandleHarnessOpenRecruitmentInquiry(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var recruitmentInquiryMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var recruitmentInquiryRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(recruitmentInquiryMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(recruitmentInquiryRoot) || !Directory.Exists(recruitmentInquiryRoot))
            throw new InvalidOperationException("harnessOpenRecruitmentInquiry is restricted to a visual Harness run with a Harness temp directory");
        if (Game.Current?.GameStateManager?.ActiveState is not MapState || ChronicleInquiryAdapter.IsInquiryOpen || MapScreen.Instance?.IsEscapeMenuOpened == true)
            throw new InvalidOperationException("harnessOpenRecruitmentInquiry requires a clear Campaign Map without another modal");
        var recruitmentInquiryData = ChronicleAgentRecruitment.BeginHarnessNativeCapacityInquiry(_recruitmentViewModel, ReadString(command, "ownerId"), ReadString(command, "troopId"), ReadRequiredInteger(command, "slot"), out var recruitmentInquiryViewModel);
        _recruitmentViewModel = recruitmentInquiryViewModel;
        WriteResponse(commandId, action, "completed", behavior, null, recruitmentInquiryData);
    }

    private void HandleHarnessNativeInquiryDiagnostics(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var inquiryDiagnosticsMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var inquiryDiagnosticsRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (inquiryDiagnosticsMode is not ("visual-capture" or "fresh-campaign-renown") || string.IsNullOrWhiteSpace(inquiryDiagnosticsRoot) || !Directory.Exists(inquiryDiagnosticsRoot))
            throw new InvalidOperationException("harnessNativeInquiryDiagnostics is restricted to a visual/fresh-campaign Harness run with a Harness temp directory");
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleInquiryAdapter.BuildHarnessInquiryDiagnosticsJson());
    }

    private void HandleHarnessPrepareAlleyLeaderFixture(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var alleyFixtureMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var alleyFixtureRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(alleyFixtureMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(alleyFixtureRoot) || !Directory.Exists(alleyFixtureRoot))
            throw new InvalidOperationException("harnessPrepareAlleyLeaderFixture is restricted to a visual Harness run with a Harness temp directory");
        WriteResponse(commandId, action, "completed", behavior, null, HarnessAlleyLeaderFixture.PrepareTownAlleyLeaderInquiry(ReadString(command, "settlementId")));
    }

    private void HandleHarnessAlleyLeaderDiagnostics(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var alleyDiagnosticsMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var alleyDiagnosticsRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(alleyDiagnosticsMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(alleyDiagnosticsRoot) || !Directory.Exists(alleyDiagnosticsRoot))
            throw new InvalidOperationException("harnessAlleyLeaderDiagnostics is restricted to a visual Harness run with a Harness temp directory");
        WriteResponse(commandId, action, "completed", behavior, null, HarnessAlleyLeaderFixture.BuildDiagnostics(ReadString(command, "settlementId")));
    }

    private void HandleHarnessPrepareAlleyRosterFixture(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var alleyRosterFixtureMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var alleyRosterFixtureRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(alleyRosterFixtureMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(alleyRosterFixtureRoot) || !Directory.Exists(alleyRosterFixtureRoot))
            throw new InvalidOperationException("harnessPrepareAlleyRosterFixture is restricted to a visual Harness run with a Harness temp directory");
        WriteResponse(commandId, action, "completed", behavior, null, HarnessAlleyRosterFixture.PrepareTownAlleyRoster(ReadString(command, "settlementId"), ReadString(command, "menuId") ?? "manage_alley", ReadString(command, "volunteerScenario") ?? "natural"));
    }

    private void HandleHarnessSeedAlleyAttackFixture(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var alleyAttackFixtureMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var alleyAttackFixtureRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(alleyAttackFixtureMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(alleyAttackFixtureRoot) || !Directory.Exists(alleyAttackFixtureRoot))
            throw new InvalidOperationException("harnessSeedAlleyAttackFixture is restricted to a visual Harness run with a Harness temp directory");
        WriteResponse(commandId, action, "completed", behavior, null, HarnessAlleyRosterFixture.SeedAlleyAttack(ReadString(command, "settlementId"), ReadString(command, "alleyTag")));
    }

    private void HandleHarnessSeedPersuasionFixture(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var persuasionFixtureMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var persuasionFixtureRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(persuasionFixtureMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(persuasionFixtureRoot) || !Directory.Exists(persuasionFixtureRoot))
            throw new InvalidOperationException("harnessSeedPersuasionFixture is restricted to a visual Harness run with a Harness temp directory");
        WriteResponse(commandId, action, "completed", behavior, null, HarnessPersuasionFixture.SeedPersuasionForCurrentNativeOption(ReadString(command, "optionId")));
    }

    private void HandleHarnessCurrentConversationAnswers(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var persuasionIntroMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var persuasionIntroRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(persuasionIntroMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(persuasionIntroRoot) || !Directory.Exists(persuasionIntroRoot))
            throw new InvalidOperationException("harnessCurrentConversationAnswers is restricted to a visual Harness run with a Harness temp directory");
        WriteResponse(commandId, action, "completed", behavior, null, HarnessPersuasionFixture.ReadCurrentNativeAnswerList());
    }

    private void HandleHarnessAlleyRosterDiagnostics(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var alleyRosterDiagnosticsMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var alleyRosterDiagnosticsRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(alleyRosterDiagnosticsMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(alleyRosterDiagnosticsRoot) || !Directory.Exists(alleyRosterDiagnosticsRoot))
            throw new InvalidOperationException("harnessAlleyRosterDiagnostics is restricted to a visual Harness run with a Harness temp directory");
        WriteResponse(commandId, action, "completed", behavior, null, HarnessAlleyRosterFixture.BuildDiagnostics(ReadString(command, "settlementId"), ReadString(command, "alleyTag"), ReadString(command, "referenceHeroId")));
    }

    private void HandleHarnessMapPartyDiagnostics(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var mapPartyDiagnosticsMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var mapPartyDiagnosticsRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(mapPartyDiagnosticsMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(mapPartyDiagnosticsRoot) || !Directory.Exists(mapPartyDiagnosticsRoot))
            throw new InvalidOperationException("harnessMapPartyDiagnostics is restricted to a visual Harness run with a Harness temp directory");
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("harnessMapPartyDiagnostics requires the Campaign Map state");
        WriteResponse(commandId, action, "completed", behavior, null, BuildHarnessMapPartyDiagnosticsJson());
    }

    private void HandleHarnessMapPartyCompositionDiagnostics(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var mapPartyCompositionDiagnosticsMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var mapPartyCompositionDiagnosticsRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(mapPartyCompositionDiagnosticsMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(mapPartyCompositionDiagnosticsRoot) || !Directory.Exists(mapPartyCompositionDiagnosticsRoot))
            throw new InvalidOperationException("harnessMapPartyCompositionDiagnostics is restricted to a visual Harness run with a Harness temp directory");
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("harnessMapPartyCompositionDiagnostics requires the Campaign Map state");
        var diagnosticPartyId = ReadString(command, "partyId");
        if (string.IsNullOrWhiteSpace(diagnosticPartyId))
            throw new InvalidOperationException("harnessMapPartyCompositionDiagnostics requires a partyId");
        WriteResponse(commandId, action, "completed", behavior, null, BuildHarnessMapPartyCompositionDiagnosticsJson(diagnosticPartyId));
    }

    private void HandleHarnessCreateMapArmyFixture(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var createArmyFixtureMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var createArmyFixtureRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(createArmyFixtureMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(createArmyFixtureRoot) || !Directory.Exists(createArmyFixtureRoot))
            throw new InvalidOperationException("harnessCreateMapArmyFixture is restricted to a visual Harness run with a Harness temp directory");
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("harnessCreateMapArmyFixture requires the Campaign Map state");
        WriteResponse(commandId, action, "completed", behavior, null, CreateMapArmyFixture(ReadString(command, "partyId"), ReadString(command, "attachedPartyId")));
    }

    private void HandleHarnessSeedMapPartyIssueMarker(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var mapPartyIssueMarkerMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var mapPartyIssueMarkerRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(mapPartyIssueMarkerMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(mapPartyIssueMarkerRoot) || !Directory.Exists(mapPartyIssueMarkerRoot))
            throw new InvalidOperationException("harnessSeedMapPartyIssueMarker is restricted to a visual Harness run with a Harness temp directory");
        if (Game.Current?.GameStateManager?.ActiveState is not MapState || Campaign.Current == null)
            throw new InvalidOperationException("harnessSeedMapPartyIssueMarker requires the Campaign Map state");
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleHarnessMapPartyIssueMarkerFixture.PrepareNativeAvailableIssueMarker(ReadString(command, "partyId")));
    }

    private void HandleHarnessPreparePursuitVisibilityFixture(ChronicleCampaignBehavior behavior, string commandId, string action, string command)
    {
        var pursuitFixtureMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var pursuitFixtureRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(pursuitFixtureMode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(pursuitFixtureRoot) || !Directory.Exists(pursuitFixtureRoot))
            throw new InvalidOperationException("Pursuit visibility fixture is restricted to a visual Harness run with a Harness temp directory");
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("Pursuit visibility fixture requires the Campaign Map state");
        WriteResponse(commandId, action, "completed", behavior, null, ChronicleHarnessPursuitFixture.CreateWeakHostileLooterParty());
    }
}
