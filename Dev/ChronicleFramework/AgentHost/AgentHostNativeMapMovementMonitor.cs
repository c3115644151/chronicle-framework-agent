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

        return [
            new { scenario = "campaign-map-movement-passively-polls-visible-hostile-bandits-and-pauses-as-a-separate-native-control", partyTargetPolls = visible.MapPartyTargetPollCount, pauseCount = visible.PauseCount, extraModelDecisions = 0, passed = true },
            new { scenario = "campaign-map-movement-does-not-pause-for-neutral-party-observations", partyTargetPolls = neutral.MapPartyTargetPollCount, pauseCount = neutral.PauseCount, passed = true },
            new { scenario = "campaign-map-movement-returns-current-map-conversation-before-wait-window-ends", partyTargetPolls = mapConversation.MapPartyTargetPollCount, pauseCount = mapConversation.PauseCount, clockChanged = false, passed = true }
        ];
    }

    private static bool IsActiveMapMove(JsonObject native, string targetSettlementId)
    {
        var state = native["state"] as JsonObject;
        var context = state?["context"] as JsonObject;
        var location = state?["location"] as JsonObject;
        var party = state?["party"] as JsonObject;
        var current = ReadString(location, "currentSettlementId");
        var timeMode = ReadString(native, "timeControlMode") ?? ReadString(context, "timeControlMode");
        var conversationActive = context?["conversation"] is JsonObject;
        return ReadString(native, "status") == "completed" && ReadString(context, "gameState") == "MapState" &&
               timeMode is not null and not "Stop" && string.IsNullOrWhiteSpace(ReadString(context, "menuId")) &&
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

    private sealed class FakeVisibleBanditMoveClient(bool visibleHostileBandit, bool openConversationAfterFirstPoll = false) : IAgentHostBattleSimulationNativeClient
    {
        private bool _paused;
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
