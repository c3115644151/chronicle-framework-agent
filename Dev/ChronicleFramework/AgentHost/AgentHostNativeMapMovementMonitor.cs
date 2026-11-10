using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal sealed record AgentHostNativeMapMovementWatchResult(
    JsonObject NativeReceipt,
    JsonObject NativeState,
    JsonArray VisibleHostileBanditTargets,
    JsonObject? PauseReceipt,
    int MapPartyTargetPollCount)
{
    internal bool InterruptedByVisibleHostileBandit => PauseReceipt is not null;
}

internal sealed record AgentHostNativePartyPursuitWatchResult(
    JsonObject NativeReceipt,
    int PollCount,
    int ElapsedSeconds,
    string StopReason)
{
    internal bool WindowExpired => StopReason == "window-expired";
}

/// <summary>
/// Passively watches a Native settlement move for brief, player-visible hostile Bandits.
/// World time still follows the game's move/wait state. When a current Bandit appears,
/// it issues a separately traced Native Pause so the EYC parent can route the fresh map
/// state through the existing BattleSimulation loop without another idle model call.
/// </summary>
internal static class AgentHostNativeMapMovementMonitor
{
    internal const string FailureCode = "native-visible-hostile-bandit-interrupted-settlement-move";
    internal const int MaximumWatchWindowSeconds = 10;

    internal static async Task<AgentHostNativePartyPursuitWatchResult> WaitForPartyPursuitAsync(
        IAgentHostCampaignNativeClient client,
        JsonObject initialNative,
        string targetPartyId,
        int waitSeconds,
        CancellationToken cancellationToken,
        TimeSpan? pollInterval = null)
    {
        if (waitSeconds is < 1 or > MaximumWatchWindowSeconds)
            throw new AgentHostException("native-party-pursuit-watch-interval-invalid", "Passive Native party pursuit observation requires a bounded 1-10 second wait.");
        if (string.IsNullOrWhiteSpace(targetPartyId))
            throw new AgentHostException("native-party-pursuit-target-missing", "Passive Native party pursuit observation requires the exact target ID selected by the model.");

        var latest = (JsonObject)initialNative.DeepClone();
        var stopReason = GetPartyPursuitStopReason(latest, targetPartyId);
        if (stopReason != "pursuit-active")
            return new AgentHostNativePartyPursuitWatchResult(latest, 0, 0, stopReason);

        var interval = pollInterval ?? TimeSpan.FromSeconds(1);
        var pollCount = 0;
        for (var elapsedSeconds = 1; elapsedSeconds <= waitSeconds; elapsedSeconds++)
        {
            await Task.Delay(interval, cancellationToken);
            using var stateResponse = await client.ReadStateAsync(cancellationToken);
            latest = CloneObject(stateResponse.RootElement);
            pollCount++;
            stopReason = GetPartyPursuitStopReason(latest, targetPartyId);
            if (stopReason != "pursuit-active")
                return new AgentHostNativePartyPursuitWatchResult(latest, pollCount, elapsedSeconds, stopReason);
        }

        return new AgentHostNativePartyPursuitWatchResult(latest, pollCount, waitSeconds, "window-expired");
    }

    internal static string GetPartyPursuitStopReason(JsonObject native, string targetPartyId)
    {
        var state = native["state"] as JsonObject ?? native;
        var context = state["context"] as JsonObject;
        var location = state["location"] as JsonObject;
        var party = state["party"] as JsonObject;
        var gameState = ReadString(context, "gameState");
        if (!string.Equals(gameState, "MapState", StringComparison.Ordinal)) return "game-state-changed";
        if (ReadBoolean(context, "encounterActive")) return "encounter-opened";
        if (context?["conversation"] is JsonObject) return "conversation-opened";
        if (ReadBoolean(context, "inquiryOpen") || ReadBoolean(context, "escapeMenuOpen") ||
            !string.IsNullOrWhiteSpace(ReadString(context, "menuId")) ||
            ReadBoolean(context, "isWaitMenu") || ReadBoolean(context, "isWaitActive") ||
            ReadBoolean(context? ["sceneNotification"] as JsonObject, "hasActiveNotification"))
            return "native-ui-interruption";
        if (ReadBoolean(context?["mapIncident"] as JsonObject, "active")) return "map-incident-opened";
        if (!string.Equals(ReadString(location, "targetPartyId"), targetPartyId, StringComparison.Ordinal)) return "target-lost-or-changed";
        if (!ReadBoolean(party, "isMoving")) return "native-pursuit-stopped";
        if (!IsCampaignTimeAdvancing(native)) return "campaign-time-stopped";
        return "pursuit-active";
    }

    internal static async Task<AgentHostNativeMapMovementWatchResult> WaitAsync(
        IAgentHostCampaignNativeClient client,
        IAgentHostBattleSimulationNativeClient? battleClient,
        JsonObject initialNative,
        string? targetSettlementId,
        int waitSeconds,
        bool monitorVisibleBandits,
        CancellationToken cancellationToken)
    {
        var latest = (JsonObject)initialNative.DeepClone();
        var pollCount = 0;
        if (waitSeconds is < 1 or > MaximumWatchWindowSeconds)
            throw new AgentHostException("native-map-movement-watch-interval-invalid", "Passive Native map observation requires a bounded 1-10 second wait.");

        // Do not spend a wall-clock wait while Native time is stopped and a settlement
        // move still appears active. Return this exact state to the caller so its parent
        // can recover the original Native Move; never turn this into an implicit clock action.
        if (IsStalledNativeSettlementMove(latest, targetSettlementId))
            return new AgentHostNativeMapMovementWatchResult(latest, CloneState(latest), new JsonArray(), null, pollCount);

        // Preserve the existing observe-again contract if this state is not a current
        // settlement move. CampaignLoop also uses observeAgain outside settlement travel.
        if (string.IsNullOrWhiteSpace(targetSettlementId) || !IsActiveMapMove(latest, targetSettlementId))
        {
            await Task.Delay(TimeSpan.FromSeconds(waitSeconds), cancellationToken);
            using var finalState = await client.ReadStateAsync(cancellationToken);
            latest = CloneObject(finalState.RootElement);
            return new AgentHostNativeMapMovementWatchResult(latest, CloneState(latest), new JsonArray(), null, pollCount);
        }

        var canMonitorBandits = monitorVisibleBandits && battleClient is not null && HasActiveEycQuest(latest);
        if (!canMonitorBandits)
        {
            await Task.Delay(TimeSpan.FromSeconds(waitSeconds), cancellationToken);
            using var finalState = await client.ReadStateAsync(cancellationToken);
            latest = CloneObject(finalState.RootElement);
            return new AgentHostNativeMapMovementWatchResult(latest, CloneState(latest), new JsonArray(), null, pollCount);
        }

        for (var elapsedSeconds = 0; elapsedSeconds < waitSeconds; elapsedSeconds++)
        {
            await Task.Delay(TimeSpan.FromSeconds(1), cancellationToken);

            if (canMonitorBandits)
            {
                using var targetsResponse = await battleClient!.ExecuteBattleSimulationActionAsync("mapPartyTargets", new JsonObject(), cancellationToken);
                latest = CloneObject(targetsResponse.RootElement);
                pollCount++;
                if (!IsActiveMapMove(latest, targetSettlementId))
                    return new AgentHostNativeMapMovementWatchResult(latest, CloneState(latest), new JsonArray(), null, pollCount);

                var visibleBandits = GetVisibleHostileBandits(latest);
                if (visibleBandits.Count > 0)
                {
                    using var pauseResponse = await battleClient.PauseForVisibleHostileDecisionAsync(cancellationToken);
                    var pauseReceipt = CloneObject(pauseResponse.RootElement);
                    if (ReadString(pauseReceipt, "status") == "completed")
                    {
                        using var pausedState = await client.ReadStateAsync(cancellationToken);
                        latest = CloneObject(pausedState.RootElement);
                        return new AgentHostNativeMapMovementWatchResult(latest, CloneState(latest), visibleBandits, pauseReceipt, pollCount);
                    }
                }
            }
            else
            {
                using var stateResponse = await client.ReadStateAsync(cancellationToken);
                latest = CloneObject(stateResponse.RootElement);
                if (!IsActiveMapMove(latest, targetSettlementId))
                    return new AgentHostNativeMapMovementWatchResult(latest, CloneState(latest), new JsonArray(), null, pollCount);
            }
        }

        return new AgentHostNativeMapMovementWatchResult(latest, CloneState(latest), new JsonArray(), null, pollCount);
    }

    internal static JsonArray GetVisibleHostileBandits(JsonObject native)
    {
        var rows = native["data"]?["mapPartyTargets"] as JsonArray;
        return new JsonArray((rows?.OfType<JsonObject>() ?? Enumerable.Empty<JsonObject>())
            .Where(row => ReadString(row, "type") == "bandit" && ReadBoolean(row, "hostile") && !string.IsNullOrWhiteSpace(ReadString(row, "id")))
            .Select(row => (JsonNode?)row.DeepClone())
            .ToArray());
    }

    internal static bool IsCampaignTimeAdvancing(JsonObject? nativeOrState)
    {
        if (nativeOrState is null) return false;
        var state = nativeOrState["state"] as JsonObject ?? nativeOrState;
        var context = state["context"] as JsonObject;
        var timeMode = ReadString(nativeOrState, "timeControlMode") ?? ReadString(context, "timeControlMode");
        return !string.IsNullOrWhiteSpace(timeMode) && !string.Equals(timeMode, "Stop", StringComparison.Ordinal);
    }

    internal static bool IsStalledNativeSettlementMove(JsonObject? native, string? expectedTargetSettlementId = null)
    {
        if (native is null) return false;
        var state = native["state"] as JsonObject ?? native;
        var context = state["context"] as JsonObject;
        var location = state["location"] as JsonObject;
        var party = state["party"] as JsonObject;
        var timeMode = ReadString(native, "timeControlMode") ?? ReadString(context, "timeControlMode");
        var targetSettlementId = ReadString(location, "targetSettlementId");
        return string.Equals(timeMode, "Stop", StringComparison.Ordinal) &&
               string.Equals(ReadString(context, "gameState"), "MapState", StringComparison.Ordinal) &&
               string.IsNullOrWhiteSpace(ReadString(context, "menuId")) &&
               !ReadBoolean(context, "escapeMenuOpen") && !ReadBoolean(context, "inquiryOpen") &&
               !ReadBoolean(context, "encounterActive") && !ReadBoolean(context, "isWaitMenu") && !ReadBoolean(context, "isWaitActive") &&
               context?["conversation"] is not JsonObject &&
               !ReadBoolean(context?["captivity"] as JsonObject, "isCaptive") &&
               !ReadBoolean(context?["sceneNotification"] as JsonObject, "hasActiveNotification") &&
               ReadBoolean(party, "isMoving") && !string.IsNullOrWhiteSpace(targetSettlementId) &&
               string.IsNullOrWhiteSpace(ReadString(location, "targetPartyId")) &&
               !string.Equals(ReadString(location, "currentSettlementId"), targetSettlementId, StringComparison.Ordinal) &&
               (string.IsNullOrWhiteSpace(expectedTargetSettlementId) ||
                string.Equals(expectedTargetSettlementId, targetSettlementId, StringComparison.Ordinal));
    }

    internal static bool IsPausedVisibleBanditMove(JsonObject native)
    {
        var state = native["state"] as JsonObject;
        var context = state?["context"] as JsonObject;
        var party = state?["party"] as JsonObject;
        var location = state?["location"] as JsonObject;
        return ReadString(context, "gameState") == "MapState" &&
               ReadString(native, "timeControlMode") == "Stop" &&
               string.IsNullOrWhiteSpace(ReadString(context, "menuId")) &&
               !ReadBoolean(context, "escapeMenuOpen") && !ReadBoolean(context, "inquiryOpen") &&
               !ReadBoolean(context, "encounterActive") && !ReadBoolean(context, "isWaitMenu") && !ReadBoolean(context, "isWaitActive") &&
               party is not null && ReadBoolean(party, "isMoving") &&
               !string.IsNullOrWhiteSpace(ReadString(location, "targetSettlementId")) &&
               string.IsNullOrWhiteSpace(ReadString(location, "targetPartyId")) &&
               HasActiveEycQuest(native) && HasVisibleHostileBanditState(state);
    }

    internal static bool IsPausedVisibleBanditMove(JsonElement native)
    {
        if (native.ValueKind != JsonValueKind.Object) return false;
        var parsed = JsonNode.Parse(native.GetRawText()) as JsonObject;
        return parsed is not null && IsPausedVisibleBanditMove(parsed);
    }

    internal static IReadOnlyList<object> RunContractSelfTests()
    {
        var visible = new FakeVisibleBanditMoveClient(visibleHostileBandit: true);
        var interrupted = WaitAsync(visible, visible, visible.CurrentNative, "safe-town", 2, monitorVisibleBandits: true, CancellationToken.None)
            .GetAwaiter().GetResult();
        if (!interrupted.InterruptedByVisibleHostileBandit || visible.MapPartyTargetPollCount != 1 || visible.PauseCount != 1 ||
            interrupted.VisibleHostileBanditTargets.Count != 1 || !IsPausedVisibleBanditMove(interrupted.NativeReceipt))
            throw new AgentHostException("campaign-map-movement-hostile-interrupt-self-test-failed", "A current hostile Bandit exposed during Native settlement travel must trigger a separately recorded Native Pause and return a fresh paused EYC Map state without another model decision.");

        var neutral = new FakeVisibleBanditMoveClient(visibleHostileBandit: false);
        var noInterruption = WaitAsync(neutral, neutral, neutral.CurrentNative, "safe-town", 1, monitorVisibleBandits: true, CancellationToken.None)
            .GetAwaiter().GetResult();
        if (noInterruption.InterruptedByVisibleHostileBandit || neutral.PauseCount != 0)
            throw new AgentHostException("campaign-map-movement-neutral-interrupt-self-test-failed", "A neutral party during Native settlement movement must not receive an automatic time pause.");

        var mapConversation = new FakeVisibleBanditMoveClient(visibleHostileBandit: false, openConversationAfterFirstPoll: true);
        var conversationWatch = WaitAsync(mapConversation, mapConversation, mapConversation.CurrentNative, "safe-town", 4, monitorVisibleBandits: true, CancellationToken.None)
            .GetAwaiter().GetResult();
        if (mapConversation.MapPartyTargetPollCount != 1 || mapConversation.PauseCount != 0 ||
            conversationWatch.NativeState["context"]?["conversation"] is not JsonObject conversation ||
            string.IsNullOrWhiteSpace(ReadString(conversation, "sentenceText")))
            throw new AgentHostException("campaign-map-movement-conversation-interrupt-self-test-failed", "Passive movement monitoring must return immediately when a current Native MapState conversation appears, leaving its visible text/options for the Agent decision loop without changing the clock.");

        var pausedMove = new FakeVisibleBanditMoveClient(visibleHostileBandit: false, initiallyPaused: true);
        var pausedStarted = Stopwatch.GetTimestamp();
        var pausedWatch = WaitAsync(pausedMove, pausedMove, pausedMove.CurrentNative, "safe-town", 4, monitorVisibleBandits: true, CancellationToken.None)
            .GetAwaiter().GetResult();
        if (Stopwatch.GetElapsedTime(pausedStarted) > TimeSpan.FromSeconds(1) || pausedMove.MapPartyTargetPollCount != 0 ||
            pausedMove.PauseCount != 0 || !IsStalledNativeSettlementMove(pausedWatch.NativeReceipt, "safe-town") ||
            IsCampaignTimeAdvancing(pausedWatch.NativeReceipt))
            throw new AgentHostException("campaign-map-movement-stopped-clock-wait-return-failed", "A settlement move order left active while Native Campaign time is stopped must return immediately to its caller, without ten seconds of model-paid waiting or a clock action.");

        var pursuitEncounter = new FakePartyPursuitClient(stopAfterPoll: "encounter-opened");
        var pursuitEncounterWatch = WaitForPartyPursuitAsync(pursuitEncounter, pursuitEncounter.CurrentNative, "bandit-1", 5, CancellationToken.None, TimeSpan.FromMilliseconds(1))
            .GetAwaiter().GetResult();
        if (pursuitEncounterWatch.StopReason != "encounter-opened" || pursuitEncounterWatch.PollCount != 1 ||
            pursuitEncounter.ClockActions.Count != 0 || pursuitEncounter.GameplayActions.Count != 0)
            throw new AgentHostException("campaign-party-pursuit-encounter-interrupt-self-test-failed", "Passive pursuit monitoring must return the fresh Native encounter immediately without a model wait or clock/gameplay action.");

        var pursuitConversation = new FakePartyPursuitClient(stopAfterPoll: "conversation-opened");
        var pursuitConversationWatch = WaitForPartyPursuitAsync(pursuitConversation, pursuitConversation.CurrentNative, "bandit-1", 5, CancellationToken.None, TimeSpan.FromMilliseconds(1))
            .GetAwaiter().GetResult();
        var pursuitIncident = new FakePartyPursuitClient(stopAfterPoll: "map-incident-opened");
        var pursuitIncidentWatch = WaitForPartyPursuitAsync(pursuitIncident, pursuitIncident.CurrentNative, "bandit-1", 5, CancellationToken.None, TimeSpan.FromMilliseconds(1))
            .GetAwaiter().GetResult();
        if (pursuitConversationWatch.StopReason != "conversation-opened" || pursuitIncidentWatch.StopReason != "map-incident-opened" ||
            pursuitConversationWatch.PollCount != 1 || pursuitIncidentWatch.PollCount != 1)
            throw new AgentHostException("campaign-party-pursuit-native-interruptions-self-test-failed", "Native map conversation and incident UI must interrupt passive pursuit observation on the first fresh read.");

        var pursuitStoppedClock = new FakePartyPursuitClient(stopAfterPoll: "campaign-time-stopped");
        var pursuitStoppedClockWatch = WaitForPartyPursuitAsync(pursuitStoppedClock, pursuitStoppedClock.CurrentNative, "bandit-1", 5, CancellationToken.None, TimeSpan.FromMilliseconds(1))
            .GetAwaiter().GetResult();
        if (pursuitStoppedClockWatch.StopReason != "campaign-time-stopped" || pursuitStoppedClockWatch.PollCount != 1 ||
            pursuitStoppedClock.ClockActions.Count != 0 || pursuitStoppedClock.GameplayActions.Count != 0)
            throw new AgentHostException("campaign-party-pursuit-stopped-clock-self-test-failed", "A Native stopped-clock observation must immediately return without a compensating clock action.");

        var pursuitTargetLoss = new FakePartyPursuitClient(stopAfterPoll: "target-lost-or-changed");
        var pursuitTargetLossWatch = WaitForPartyPursuitAsync(pursuitTargetLoss, pursuitTargetLoss.CurrentNative, "bandit-1", 5, CancellationToken.None, TimeSpan.FromMilliseconds(1))
            .GetAwaiter().GetResult();
        if (pursuitTargetLossWatch.StopReason != "target-lost-or-changed" || pursuitTargetLossWatch.PollCount != 1 ||
            pursuitTargetLoss.ClockActions.Count != 0 || pursuitTargetLoss.GameplayActions.Count != 0)
            throw new AgentHostException("campaign-party-pursuit-target-loss-self-test-failed", "A Native target-loss/hold state must return immediately for fresh model replanning, without changing the stopped Campaign clock.");

        var pursuitStillActive = new FakePartyPursuitClient();
        var pursuitWindow = WaitForPartyPursuitAsync(pursuitStillActive, pursuitStillActive.CurrentNative, "bandit-1", 3, CancellationToken.None, TimeSpan.FromMilliseconds(1))
            .GetAwaiter().GetResult();
        if (!pursuitWindow.WindowExpired || pursuitWindow.PollCount != 3 || pursuitStillActive.ClockActions.Count != 0 ||
            pursuitStillActive.GameplayActions.Count != 0 || pursuitWindow.NativeReceipt["campaignDay"]?.GetValue<double>() != 3.0)
            throw new AgentHostException("campaign-party-pursuit-bounded-window-self-test-failed", "An unchanged Native pursuit must return fresh state at the bound without issuing clock or gameplay actions.");

        using var canceledWatch = new CancellationTokenSource();
        canceledWatch.Cancel();
        var cancellationClient = new FakePartyPursuitClient();
        var cancellationPropagated = false;
        try
        {
            _ = WaitForPartyPursuitAsync(cancellationClient, cancellationClient.CurrentNative, "bandit-1", 5, canceledWatch.Token, TimeSpan.FromMilliseconds(1))
                .GetAwaiter().GetResult();
        }
        catch (OperationCanceledException) { cancellationPropagated = true; }
        if (!cancellationPropagated || cancellationClient.PollCount != 0 || cancellationClient.ClockActions.Count != 0 || cancellationClient.GameplayActions.Count != 0)
            throw new AgentHostException("campaign-party-pursuit-cancellation-self-test-failed", "Host cancellation must stop passive pursuit observation before another read or any Native action.");

        return [
            new { scenario = "campaign-map-movement-passively-polls-visible-hostile-bandits-and-pauses-as-a-separate-native-control", partyTargetPolls = visible.MapPartyTargetPollCount, pauseCount = visible.PauseCount, extraModelDecisions = 0, passed = true },
            new { scenario = "campaign-map-movement-does-not-pause-for-neutral-party-observations", partyTargetPolls = neutral.MapPartyTargetPollCount, pauseCount = neutral.PauseCount, passed = true },
            new { scenario = "campaign-map-movement-returns-current-map-conversation-before-wait-window-ends", partyTargetPolls = mapConversation.MapPartyTargetPollCount, pauseCount = mapConversation.PauseCount, clockChanged = false, passed = true },
            new { scenario = "campaign-map-movement-returns-paused-native-move-without-wall-clock-delay-or-clock-action", partyTargetPolls = pausedMove.MapPartyTargetPollCount, pauseCount = pausedMove.PauseCount, passed = true },
            new { scenario = "campaign-party-pursuit-passive-monitor-returns-on-native-encounter-without-model-or-clock-action", polls = pursuitEncounterWatch.PollCount, stopReason = pursuitEncounterWatch.StopReason, clockActions = pursuitEncounter.ClockActions.Count, gameplayActions = pursuitEncounter.GameplayActions.Count, passed = true },
            new { scenario = "campaign-party-pursuit-passive-monitor-returns-on-map-conversation-and-incident", conversationStopReason = pursuitConversationWatch.StopReason, incidentStopReason = pursuitIncidentWatch.StopReason, passed = true },
            new { scenario = "campaign-party-pursuit-passive-monitor-returns-on-stopped-clock-without-clock-action", stopReason = pursuitStoppedClockWatch.StopReason, passed = true },
            new { scenario = "campaign-party-pursuit-passive-monitor-returns-on-target-loss-without-clock-action", polls = pursuitTargetLossWatch.PollCount, stopReason = pursuitTargetLossWatch.StopReason, clockActions = pursuitTargetLoss.ClockActions.Count, passed = true },
            new { scenario = "campaign-party-pursuit-passive-monitor-bounds-unchanged-native-observation", polls = pursuitWindow.PollCount, elapsedSeconds = pursuitWindow.ElapsedSeconds, stopReason = pursuitWindow.StopReason, clockActions = pursuitStillActive.ClockActions.Count, passed = true },
            new { scenario = "campaign-party-pursuit-passive-monitor-honors-host-cancellation", polls = cancellationClient.PollCount, cancellationPropagated, passed = true }
        ];
    }

    private static bool IsActiveMapMove(JsonObject native, string targetSettlementId)
    {
        var state = native["state"] as JsonObject;
        var context = state?["context"] as JsonObject;
        var location = state?["location"] as JsonObject;
        var party = state?["party"] as JsonObject;
        var current = ReadString(location, "currentSettlementId");
        var conversationActive = context?["conversation"] is JsonObject;
        return ReadString(native, "status") == "completed" && ReadString(context, "gameState") == "MapState" &&
               IsCampaignTimeAdvancing(native) && string.IsNullOrWhiteSpace(ReadString(context, "menuId")) &&
               !conversationActive &&
               !ReadBoolean(context, "escapeMenuOpen") && !ReadBoolean(context, "inquiryOpen") &&
               !ReadBoolean(context, "encounterActive") && !ReadBoolean(context, "isWaitMenu") && !ReadBoolean(context, "isWaitActive") &&
               !ReadBoolean(context?["sceneNotification"] as JsonObject, "hasActiveNotification") &&
               string.Equals(ReadString(location, "targetSettlementId"), targetSettlementId, StringComparison.Ordinal) &&
               !string.Equals(current, targetSettlementId, StringComparison.Ordinal) && ReadBoolean(party, "isMoving");
    }

    internal static bool HasActiveEycQuest(JsonObject native) =>
        (native["state"]?["quests"] as JsonArray)?.OfType<JsonObject>()
            .Any(quest => ReadString(quest, "id") == "rebuild_player_clan_storymode_quest") == true;

    private static bool HasVisibleHostileBanditState(JsonObject? state) =>
        (state?["nearbyParties"] as JsonArray)?.OfType<JsonObject>()
            .Any(party => ReadString(party, "type") == "bandit" && ReadBoolean(party, "hostile")) == true;

    private static JsonObject CloneObject(JsonElement value) =>
        JsonNode.Parse(value.GetRawText())?.AsObject() ?? new JsonObject();

    private static JsonObject CloneState(JsonObject native) =>
        native["state"] is JsonObject state ? (JsonObject)state.DeepClone() : new JsonObject();

    private static string? ReadString(JsonObject? value, string name) =>
        value?[name] is JsonValue node && node.TryGetValue<string>(out var text) ? text : null;

    private static bool ReadBoolean(JsonObject? value, string name) =>
        value?[name] is JsonValue node && node.TryGetValue<bool>(out var result) && result;

    private sealed class FakePartyPursuitClient(string? stopAfterPoll = null) : IAgentHostCampaignNativeClient
    {
        internal int PollCount { get; private set; }
        internal List<string> ClockActions { get; } = [];
        internal List<string> GameplayActions { get; } = [];
        internal JsonObject CurrentNative => BuildNative();

        public Task<JsonDocument> ReadStateAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            PollCount++;
            return Task.FromResult(JsonDocument.Parse(BuildNative().ToJsonString()));
        }

        public Task<JsonDocument> ExecuteCampaignActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            GameplayActions.Add(action);
            throw new AgentHostException("party-pursuit-monitor-self-test-unexpected-gameplay-action", "Passive pursuit observation must not issue gameplay actions.");
        }

        public Task<JsonDocument> ExecuteBattleSimulationActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            GameplayActions.Add(action);
            throw new AgentHostException("party-pursuit-monitor-self-test-unexpected-battle-action", "Passive pursuit observation must not query targets through a gameplay-action endpoint.");
        }

        public Task<JsonDocument> PauseForVisibleHostileDecisionAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            ClockActions.Add("pause");
            throw new AgentHostException("party-pursuit-monitor-self-test-unexpected-clock-action", "Passive pursuit observation must not issue a Native clock action.");
        }

        private JsonObject BuildNative()
        {
            var interrupted = stopAfterPoll is not null && PollCount >= 1;
            var context = new JsonObject
            {
                ["gameState"] = "MapState", ["menuId"] = null, ["encounterActive"] = false,
                ["inquiryOpen"] = false, ["escapeMenuOpen"] = false, ["isWaitMenu"] = false,
                ["isWaitActive"] = false, ["mapIncident"] = new JsonObject { ["active"] = false },
                ["sceneNotification"] = new JsonObject { ["hasActiveNotification"] = false }
            };
            var location = new JsonObject { ["targetPartyId"] = "bandit-1" };
            var party = new JsonObject { ["isMoving"] = true };
            switch (interrupted ? stopAfterPoll : null)
            {
                case "encounter-opened": context["encounterActive"] = true; context["menuId"] = "encounter"; break;
                case "conversation-opened": context["conversation"] = new JsonObject { ["sentenceText"] = "Threat" }; break;
                case "map-incident-opened": context["mapIncident"] = new JsonObject { ["active"] = true }; break;
                case "target-lost-or-changed": location["targetPartyId"] = null; party["isMoving"] = false; context["isWaiting"] = true; break;
            }
            return new JsonObject
            {
                ["status"] = "completed", ["processId"] = 321, ["campaignDay"] = 3.0,
                ["timeControlMode"] = interrupted && stopAfterPoll == "campaign-time-stopped" ? "Stop" : "StoppablePlay",
                ["state"] = new JsonObject { ["context"] = context, ["location"] = location, ["party"] = party }
            };
        }
    }

    private sealed class FakeVisibleBanditMoveClient(bool visibleHostileBandit, bool openConversationAfterFirstPoll = false, bool initiallyPaused = false) : IAgentHostBattleSimulationNativeClient
    {
        private bool _paused = initiallyPaused;
        private bool _mapConversationActive;
        internal int MapPartyTargetPollCount { get; private set; }
        internal int PauseCount { get; private set; }
        internal JsonObject CurrentNative => BuildNative(_paused);

        public Task<JsonDocument> ReadStateAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            return Task.FromResult(Parse(BuildNative(_paused)));
        }

        public Task<JsonDocument> ExecuteCampaignActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken) =>
            throw new AgentHostException("movement-monitor-self-test-unexpected-campaign-action", "Passive movement observation must not replace the current Native move order.");

        public Task<JsonDocument> ExecuteBattleSimulationActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (action != "mapPartyTargets" || arguments.Count != 0)
                throw new AgentHostException("movement-monitor-self-test-unexpected-battle-action", "Only the current Native mapPartyTargets observation is allowed during passive movement monitoring.");
            MapPartyTargetPollCount++;
            if (openConversationAfterFirstPoll && MapPartyTargetPollCount == 1) _mapConversationActive = true;
            var native = BuildNative(_paused, _mapConversationActive);
            native["data"] = new JsonObject
            {
                ["mapPartyTargets"] = visibleHostileBandit
                    ? new JsonArray(new JsonObject { ["id"] = "looters-visible", ["type"] = "bandit", ["hostile"] = true, ["distance"] = 8.4 })
                    : new JsonArray(new JsonObject { ["id"] = "patrol-visible", ["type"] = "patrol", ["hostile"] = false, ["distance"] = 5.0 })
            };
            return Task.FromResult(Parse(native));
        }

        public Task<JsonDocument> PauseForVisibleHostileDecisionAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            PauseCount++;
            _paused = true;
            return Task.FromResult(Parse(new JsonObject { ["status"] = "completed", ["action"] = "pause", ["timeControlMode"] = "Stop" }));
        }

        private static JsonObject BuildNative(bool paused, bool mapConversationActive = false)
        {
            var state = new JsonObject
            {
                ["context"] = new JsonObject
                {
                    ["gameState"] = "MapState", ["menuId"] = null, ["escapeMenuOpen"] = false,
                    ["inquiryOpen"] = false, ["encounterActive"] = false, ["isWaitMenu"] = false, ["isWaitActive"] = false,
                    ["conversation"] = mapConversationActive ? new JsonObject { ["characterId"] = "notable-a", ["sentenceText"] = "We part ways.", ["options"] = new JsonArray() } : null,
                    ["sceneNotification"] = new JsonObject { ["hasActiveNotification"] = false },
                    ["captivity"] = new JsonObject { ["isCaptive"] = false }
                },
                ["quests"] = new JsonArray(new JsonObject { ["id"] = "rebuild_player_clan_storymode_quest" }),
                ["location"] = new JsonObject { ["currentSettlementId"] = null, ["targetSettlementId"] = "safe-town", ["targetPartyId"] = null },
                ["party"] = new JsonObject { ["isMoving"] = true, ["defaultBehavior"] = "GoToSettlement" },
                ["nearbyParties"] = paused ? new JsonArray(new JsonObject { ["id"] = "looters-visible", ["type"] = "bandit", ["hostile"] = true, ["members"] = 9 }) : new JsonArray()
            };
            return new JsonObject { ["status"] = "completed", ["processId"] = 321, ["campaignDay"] = 1.0, ["timeControlMode"] = paused ? "Stop" : "StoppablePlay", ["state"] = state };
        }

        private static JsonDocument Parse(JsonObject value) => JsonDocument.Parse(value.ToJsonString());
    }
}
