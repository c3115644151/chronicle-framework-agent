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
    private static void RequireCampaignMapState(string action)
    {
        if (TaleWorlds.CampaignSystem.Campaign.Current == null || Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException(action + " requires the active Campaign Map state");
    }

    private static void EnsureNoActiveMapIncident(string action)
    {
        if (ChronicleAgentMapIncidentAdapter.IsActive())
            throw new InvalidOperationException(action + " requires the unobstructed Campaign Map; a Native Map Incident is open and must be resolved first");
    }

    private void FinalizeVolunteerRecruitmentViewModel()
    {
        var viewModel = _recruitmentViewModel;
        _recruitmentViewModel = null;
        viewModel?.OnFinalize();
    }

    private static void RequireRoleHarnessMode()
    {
        var mode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var root = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(mode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(root) || !Directory.Exists(root))
            throw new InvalidOperationException("PartyRole fixture/diagnostics are restricted to visual Harness runs with a Harness temp directory");
    }

    private static void RequireEquipmentModifierFixtureHarnessMode()
    {
        var mode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var root = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(mode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(root) || !Directory.Exists(root))
            throw new InvalidOperationException("Equipment modifier fixture seeding/cleanup is restricted to visual Harness runs with a Harness temp directory");
    }
}
