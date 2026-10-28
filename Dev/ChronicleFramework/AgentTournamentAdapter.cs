using System;
using System.Reflection;
using System.Text;
using System.Linq;
using HarmonyLib;
using TaleWorlds.Core;
using TaleWorlds.MountAndBlade;

namespace ChronicleFramework;

/// <summary>
/// Reads and invokes the currently visible Native tournament screen's own ViewModel handlers.
/// Tournament actions are deliberately not translated into arbitrary screen clicks.
/// </summary>
internal static class ChronicleTournamentAdapter
{
    private const string ViewModelTypeName = "SandBox.ViewModelCollection.Tournament.TournamentVM";
    private const string BehaviorTypeName = "SandBox.Tournaments.MissionLogics.TournamentBehavior";
    private static object _currentViewModel;
    private static bool _installed;

    internal static void Install()
    {
        if (_installed) return;
        try
        {
            var viewModelType = AccessTools.TypeByName(ViewModelTypeName);
            var behaviorType = AccessTools.TypeByName(BehaviorTypeName);
            var constructor = viewModelType == null || behaviorType == null
                ? null
                : AccessTools.Constructor(viewModelType, new[] { typeof(Action), behaviorType });
            var created = AccessTools.Method(typeof(ChronicleTournamentAdapter), nameof(OnViewModelCreated));
            var finalized = viewModelType == null ? null : AccessTools.Method(viewModelType, "OnFinalize");
            var finalizedPostfix = AccessTools.Method(typeof(ChronicleTournamentAdapter), nameof(OnViewModelFinalized));
            if (constructor == null || created == null || finalized == null || finalizedPostfix == null)
            {
                ChronicleDiagnostics.Write("tournament-viewmodel-capture-unavailable|reason=native-member-not-found");
                return;
            }

            var harmony = new Harmony("ChronicleFramework.NativeTournamentActions");
            harmony.Patch(constructor, postfix: new HarmonyMethod(created));
            harmony.Patch(finalized, postfix: new HarmonyMethod(finalizedPostfix));
            _installed = true;
            ChronicleDiagnostics.Write("tournament-viewmodel-capture-installed|type=" + ViewModelTypeName);
        }
        catch (Exception exception)
        {
            ChronicleDiagnostics.Write("tournament-viewmodel-capture-failed|type=" + exception.GetType().Name + "|message=" + exception.Message);
        }
    }

    private static void OnViewModelCreated(object __instance) => _currentViewModel = __instance;

    private static void OnViewModelFinalized(object __instance)
    {
        if (ReferenceEquals(_currentViewModel, __instance)) _currentViewModel = null;
    }

    internal static string BuildJson()
    {
        if (!TryGetCurrentViewModel(out var viewModel, out var failure))
            return "{\"available\":false,\"reason\":\"" + Escape(failure) + "\"}";

        var tournament = ReadProperty(viewModel, "Tournament");
        var game = ReadProperty(tournament, "TournamentGame");
        var prize = ReadProperty(game, "Prize");
        var json = new StringBuilder(512);
        json.Append("{\"available\":true");
        AppendBoolean(json, "canPlayerJoin", ReadBoolean(viewModel, "CanPlayerJoin"));
        AppendBoolean(json, "isCurrentMatchActive", ReadBoolean(viewModel, "IsCurrentMatchActive"));
        AppendBoolean(json, "isTournamentIncomplete", ReadBoolean(viewModel, "IsTournamentIncomplete"));
        AppendBoolean(json, "isOver", ReadBoolean(viewModel, "IsOver"));
        AppendBoolean(json, "isBetButtonEnabled", ReadBoolean(viewModel, "IsBetButtonEnabled"));
        AppendInteger(json, "activeRoundIndex", ReadInteger(viewModel, "ActiveRoundIndex"));
        AppendInteger(json, "maximumBetValue", ReadInteger(viewModel, "MaximumBetValue"));
        AppendInteger(json, "wageredDenars", ReadInteger(viewModel, "WageredDenars"));
        AppendInteger(json, "expectedBetDenars", ReadInteger(viewModel, "ExpectedBetDenars"));
        AppendInteger(json, "bettedDenars", ReadInteger(tournament, "BettedDenars"));
        AppendInteger(json, "overallExpectedDenars", ReadInteger(tournament, "OverallExpectedDenars"));
        AppendString(json, "prizeItemId", ReadString(prize, "StringId"));
        AppendString(json, "prizeItemName", ReadProperty(prize, "Name")?.ToString());
        json.Append('}');
        return json.ToString();
    }

    internal static string Invoke(string action)
    {
        if (!TryGetCurrentViewModel(out var viewModel, out var failure))
            throw new InvalidOperationException("Native tournament action is unavailable: " + failure);

        var methodName = action switch
        {
            "tournamentJoin" => "ExecuteJoinTournament",
            "tournamentSkipRound" => "ExecuteSkipRound",
            "tournamentSkipAllRounds" => "ExecuteSkipAllRounds",
            "tournamentWatchRound" => "ExecuteWatchRound",
            "tournamentLeave" => "ExecuteLeave",
            _ => throw new InvalidOperationException("Unsupported Native tournament action: " + action)
        };

        var method = viewModel.GetType().GetMethod(methodName, BindingFlags.Instance | BindingFlags.Public, null, Type.EmptyTypes, null);
        if (method == null) throw new InvalidOperationException("Verified Native tournament handler is unavailable: " + methodName);
        method.Invoke(viewModel, null);
        return "{\"schemaVersion\":1,\"nativeHandler\":\"" + methodName + "\",\"tournament\":" + BuildJson() + "}";
    }

    private static bool TryGetCurrentViewModel(out object viewModel, out string failure)
    {
        viewModel = null;
        failure = null;
        var mission = Mission.Current;
        if (mission == null || mission.MissionEnded || Game.Current?.GameStateManager?.ActiveState is not MissionState)
        {
            failure = "No active Native MissionState";
            return false;
        }

        var candidate = _currentViewModel;
        if (candidate == null || !string.Equals(candidate.GetType().FullName, ViewModelTypeName, StringComparison.Ordinal))
        {
            failure = "The original Native Tournament screen is not active";
            return false;
        }

        var candidateTournament = ReadProperty(candidate, "Tournament");
        var currentBehavior = mission.MissionBehaviors.FirstOrDefault(item => string.Equals(item.GetType().FullName, BehaviorTypeName, StringComparison.Ordinal));
        if (candidateTournament == null || !ReferenceEquals(candidateTournament, currentBehavior))
        {
            failure = "The captured Native Tournament screen does not belong to the active Mission";
            return false;
        }

        viewModel = candidate;
        return true;
    }

    private static object ReadProperty(object source, string name) => source?.GetType().GetProperty(name, BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)?.GetValue(source);
    private static string ReadString(object source, string name) => ReadProperty(source, name)?.ToString();
    private static bool ReadBoolean(object source, string name) => ReadProperty(source, name) is bool value && value;
    private static int ReadInteger(object source, string name) => ReadProperty(source, name) is int value ? value : 0;
    private static void AppendBoolean(StringBuilder json, string name, bool value) => json.Append(",\"").Append(name).Append("\":").Append(value ? "true" : "false");
    private static void AppendInteger(StringBuilder json, string name, int value) => json.Append(",\"").Append(name).Append("\":").Append(value);
    private static void AppendString(StringBuilder json, string name, string value) => json.Append(",\"").Append(name).Append("\":\"").Append(Escape(value)).Append('"');
    private static string Escape(string value) => (value ?? string.Empty).Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\r", "\\r").Replace("\n", "\\n");
}
