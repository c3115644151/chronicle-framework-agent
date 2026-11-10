using System.Diagnostics;
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal sealed record AgentHostBattleMissionLoopResult(
    bool Completed,
    string Termination,
    JsonObject FinalNative,
    bool DelegationIssued,
    int DelegatedFormationCount,
    double MainHeroHealthAtStart,
    double MainHeroHealthAtEnd,
    bool MainHeroStayedPlayerControlled,
    double CampaignDayAtStart,
    double CampaignDayAtEnd,
    string TimeControlModeAtStart,
    string TimeControlModeAtEnd,
    int PassivePollCount);

/// <summary>
/// Executes only the bounded Native Delegate Command while the original Campaign Battle Mission
/// runs. It never calls the decision provider and never changes Campaign time.
/// </summary>
internal static class AgentHostBattleMissionLoop
{
    private const int MissionEntryPollLimit = 20;
    private const int MissionCompletionPollLimit = 900;
    private const int EndScreenExitPollLimit = 20;

    internal static async Task<AgentHostBattleMissionLoopResult> RunAsync(
        IAgentHostBattleSimulationNativeClient stateClient,
        IAgentHostBattleMissionNativeClient missionClient,
        int expectedProcessId,
        CancellationToken cancellationToken,
        TimeSpan? pollInterval = null,
        int missionEntryPollLimit = MissionEntryPollLimit,
        int missionCompletionPollLimit = MissionCompletionPollLimit,
        int endScreenExitPollLimit = EndScreenExitPollLimit)
    {
        var delay = pollInterval ?? TimeSpan.FromSeconds(1);
        JsonObject? native = null;
        var processId = expectedProcessId;
        var entryPolls = 0;
        while (entryPolls++ < missionEntryPollLimit)
        {
            native = await ReadStateAsync(stateClient, processId, cancellationToken);
            var state = native["state"] as JsonObject ?? new JsonObject();
            var context = state["context"] as JsonObject ?? new JsonObject();
            var gameState = ReadString(context, "gameState");
            var mission = state["mission"] as JsonObject;
            if (string.Equals(gameState, "MissionState", StringComparison.Ordinal) &&
                (string.Equals(ReadString(mission, "mode"), "Battle", StringComparison.Ordinal) || ReadBoolean(mission, "missionEnded"))) break;
            if (entryPolls < missionEntryPollLimit) await Task.Delay(delay, cancellationToken);
        }

        if (native is null || !string.Equals(ReadString((native["state"]?["context"] as JsonObject), "gameState"), "MissionState", StringComparison.Ordinal))
            return Failure("battle-mission-entry-timeout", native ?? new JsonObject(), false, 0, double.NaN, double.NaN, false, double.NaN, double.NaN, null, null, entryPolls);

        var initialState = native["state"]!.AsObject();
        var initialMission = initialState["mission"] as JsonObject ?? new JsonObject();
        if (!string.Equals(ReadString(initialMission, "mode"), "Battle", StringComparison.Ordinal) ||
            ReadBoolean(initialMission, "missionEnded"))
            return Failure("battle-mission-not-active-battle", native, false, 0, ReadHeroHealth(initialMission), ReadHeroHealth(initialMission),
                ReadHeroIsPlayerControlled(initialMission), ReadDouble(native, "campaignDay"), ReadDouble(native, "campaignDay"),
                ReadString(native, "timeControlMode"), ReadString(native, "timeControlMode"), 0);

        var campaignDayStart = ReadDouble(native, "campaignDay");
        var timeModeStart = ReadString(native, "timeControlMode") ?? ReadString(initialState["context"] as JsonObject, "timeControlMode") ?? string.Empty;
        var heroHealthStart = ReadHeroHealth(initialMission);
        var heroControlStart = ReadHeroIsPlayerControlled(initialMission);
        var pollCount = 0;
        var delegatedFormationCount = 0;

        using (var statusResponse = await missionClient.ReadBattleMissionStatusAsync(cancellationToken))
        {
            var status = ParseRoot(statusResponse.RootElement);
            if (ReadInt(status, "processId", -1) != processId)
                return Failure("battle-mission-process-mismatch", native, false, 0, heroHealthStart, heroHealthStart, false,
                    campaignDayStart, campaignDayStart, timeModeStart, timeModeStart, pollCount);
            var data = status["data"] as JsonObject;
            if (!ReadBoolean(data, "supported") || !string.Equals(ReadString(data, "missionMode"), "Battle", StringComparison.Ordinal) ||
                !ReadBoolean(data?["mainAgent"] as JsonObject, "isPlayerControlled") ||
                ReadInt(data?["playerTeam"] as JsonObject, "formationCount", 0) <= 0)
                return Failure("battle-mission-native-delegation-precondition-failed", native, false, 0, heroHealthStart, heroHealthStart,
                    heroControlStart, campaignDayStart, campaignDayStart, timeModeStart, timeModeStart, pollCount);
        }

        using (var delegateResponse = await missionClient.DelegateBattleMissionTroopsAsync(cancellationToken))
        {
            var delegated = ParseRoot(delegateResponse.RootElement);
            if (ReadInt(delegated, "processId", -1) != processId || ReadString(delegated, "status") != "completed")
                return Failure("battle-mission-delegation-rejected", native, false, 0, heroHealthStart, heroHealthStart,
                    heroControlStart, campaignDayStart, campaignDayStart, timeModeStart, timeModeStart, pollCount);
            var receipt = delegated["data"] as JsonObject;
            delegatedFormationCount = ReadInt(receipt, "delegatedFormationCount", 0);
            if (!ReadBoolean(receipt, "allRequestedFormationsDelegated") || !ReadBoolean(receipt, "mainAgentStillPlayerControlled") ||
                ReadString(receipt, "timeControlModeBefore") != timeModeStart || ReadString(receipt, "timeControlModeAfter") != timeModeStart ||
                !NearlyEqual(ReadDouble(receipt, "campaignDayBefore"), campaignDayStart) ||
                !NearlyEqual(ReadDouble(receipt, "campaignDayAfter"), campaignDayStart))
                return Failure("battle-mission-delegation-postcondition-failed", native, true,
                    ReadInt(receipt, "delegatedFormationCount", 0), heroHealthStart, heroHealthStart, false,
                    campaignDayStart, campaignDayStart, timeModeStart, ReadString(receipt, "timeControlModeAfter") ?? string.Empty, pollCount);
        }

        var mainHeroStayedPlayerControlled = true;
        var heroHealthEnd = heroHealthStart;
        var missionEndedObserved = false;
        for (var poll = 0; poll < missionCompletionPollLimit; poll++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            await Task.Delay(delay, cancellationToken);
            native = await ReadStateAsync(stateClient, processId, cancellationToken);
            pollCount++;
            var state = native["state"] as JsonObject ?? new JsonObject();
            var context = state["context"] as JsonObject ?? new JsonObject();
            var gameState = ReadString(context, "gameState");
            var mission = state["mission"] as JsonObject;
            var missionIsEnded = ReadBoolean(mission, "missionEnded");
            if (mission is not null && mission["mainAgent"] is JsonObject mainAgent)
            {
                if (mainAgent["isPlayerControlled"] is JsonValue playerNode && playerNode.TryGetValue<bool>(out var isPlayer) && !isPlayer)
                    mainHeroStayedPlayerControlled = false;
                heroHealthEnd = ReadDouble(mainAgent, "health", heroHealthEnd);
            }
            if (!string.Equals(gameState, "MissionState", StringComparison.Ordinal))
                return BuildResult(true, "native-aftermath-reached", native, true,
                    delegatedFormationCount, heroHealthStart, heroHealthEnd,
                    mainHeroStayedPlayerControlled, campaignDayStart, ReadDouble(native, "campaignDay"), timeModeStart,
                    ReadString(native, "timeControlMode") ?? string.Empty, pollCount);
            if (missionIsEnded)
            {
                missionEndedObserved = true;
                break;
            }
        }

        if (!missionEndedObserved)
            return Failure("battle-mission-observation-timeout", native ?? new JsonObject(), true, 0, heroHealthStart, heroHealthEnd,
                mainHeroStayedPlayerControlled, campaignDayStart, ReadDouble(native, "campaignDay"), timeModeStart,
                ReadString(native, "timeControlMode") ?? string.Empty, pollCount);

        // This is the Native BattleEndLogic path used by the battle exit handling, after the Mission
        // has already ended. It is distinct from the friendly-location Leave Area hold wrapper.
        using (var exitResponse = await missionClient.ExitEndedBattleMissionAsync(cancellationToken))
        {
            var exit = ParseRoot(exitResponse.RootElement);
            if (ReadInt(exit, "processId", -1) != processId || ReadString(exit, "status") != "completed")
                return Failure("battle-mission-native-exit-rejected", native!, true, 0, heroHealthStart, heroHealthEnd,
                    mainHeroStayedPlayerControlled, campaignDayStart, ReadDouble(native, "campaignDay"), timeModeStart,
                    ReadString(native, "timeControlMode") ?? string.Empty, pollCount);
        }

        for (var poll = 0; poll < endScreenExitPollLimit; poll++)
        {
            native = await ReadStateAsync(stateClient, processId, cancellationToken);
            var gameState = ReadString(native["state"]?["context"] as JsonObject, "gameState");
            if (!string.Equals(gameState, "MissionState", StringComparison.Ordinal))
                return BuildResult(true, "native-aftermath-reached", native, true,
                    delegatedFormationCount, heroHealthStart, heroHealthEnd,
                    mainHeroStayedPlayerControlled, campaignDayStart, ReadDouble(native, "campaignDay"), timeModeStart,
                    ReadString(native, "timeControlMode") ?? string.Empty, pollCount);
            if (poll + 1 < endScreenExitPollLimit) await Task.Delay(delay, cancellationToken);
        }
        return Failure("battle-mission-aftermath-transition-timeout", native ?? new JsonObject(), true, 0, heroHealthStart, heroHealthEnd,
            mainHeroStayedPlayerControlled, campaignDayStart, ReadDouble(native, "campaignDay"), timeModeStart,
            ReadString(native, "timeControlMode") ?? string.Empty, pollCount);
    }

    internal static IReadOnlyList<object> RunContractSelfTests()
    {
        var successClient = new FakeBattleMissionNativeClient();
        var result = RunAsync(successClient, successClient, 101, CancellationToken.None, TimeSpan.Zero,
            missionEntryPollLimit: 2, missionCompletionPollLimit: 6, endScreenExitPollLimit: 2).GetAwaiter().GetResult();
        if (!result.Completed || result.Termination != "native-aftermath-reached" || successClient.DelegationCalls != 1 ||
            successClient.ExitCalls != 1 || result.DelegatedFormationCount != 1 || !result.MainHeroStayedPlayerControlled ||
            result.MainHeroHealthAtStart != 100 || result.MainHeroHealthAtEnd != 100 ||
            result.CampaignDayAtStart != 42 || result.CampaignDayAtEnd != 42 ||
            result.TimeControlModeAtStart != "Stop" || result.TimeControlModeAtEnd != "Stop" ||
            ReadString(result.FinalNative["state"]?["context"] as JsonObject, "gameState") != "PartyState")
            throw new AgentHostException("battle-mission-loop-self-test-delegation-flow-failed", "The Mission controller must delegate once, preserve Hero control/time and return to Native aftermath without a model call.");

        var defeatClient = new FakeBattleMissionNativeClient(capturedAfterBattle: true);
        var defeat = RunAsync(defeatClient, defeatClient, 101, CancellationToken.None, TimeSpan.Zero,
            missionEntryPollLimit: 2, missionCompletionPollLimit: 6, endScreenExitPollLimit: 2).GetAwaiter().GetResult();
        if (!defeat.Completed || defeat.Termination != "native-aftermath-reached" || defeatClient.DelegationCalls != 1 ||
            !ReadBoolean(defeat.FinalNative["state"]?["context"]?["captivity"] as JsonObject, "isCaptive") ||
            ReadString(defeat.FinalNative["state"]?["context"] as JsonObject, "menuId") != "prisoner_wait")
            throw new AgentHostException("battle-mission-loop-self-test-native-defeat-aftermath-not-preserved", "A Native defeat/captivity aftermath must be returned as observed and not mislabeled as victory.");

        var riskClient = new FakeBattleMissionNativeClient(heroTakesDamage: true);
        var risk = RunAsync(riskClient, riskClient, 101, CancellationToken.None, TimeSpan.Zero,
            missionEntryPollLimit: 2, missionCompletionPollLimit: 6, endScreenExitPollLimit: 2).GetAwaiter().GetResult();
        if (!risk.Completed || riskClient.DelegationCalls != 1 || risk.MainHeroHealthAtStart != 100 ||
            risk.MainHeroHealthAtEnd >= risk.MainHeroHealthAtStart || !risk.MainHeroStayedPlayerControlled)
            throw new AgentHostException("battle-mission-loop-self-test-mainhero-risk-observation-failed", "The passive Mission controller must retain observed MainHero health loss and verify that the Native controller remains Player; it must not claim health stayed unchanged.");

        var rejectedClient = new FakeBattleMissionNativeClient(supported: false);
        var rejected = RunAsync(rejectedClient, rejectedClient, 101, CancellationToken.None, TimeSpan.Zero,
            missionEntryPollLimit: 2, missionCompletionPollLimit: 2, endScreenExitPollLimit: 2).GetAwaiter().GetResult();
        if (rejected.Completed || rejectedClient.DelegationCalls != 0 || rejectedClient.ExitCalls != 0 ||
            rejected.Termination != "battle-mission-native-delegation-precondition-failed")
            throw new AgentHostException("battle-mission-loop-self-test-unsupported-mission-not-rejected", "The loop must reject a Native unsupported Mission before issuing Delegate Command.");

        var timeoutClient = new FakeBattleMissionNativeClient(neverEnds: true);
        var timeout = RunAsync(timeoutClient, timeoutClient, 101, CancellationToken.None, TimeSpan.Zero,
            missionEntryPollLimit: 2, missionCompletionPollLimit: 3, endScreenExitPollLimit: 2).GetAwaiter().GetResult();
        if (timeout.Completed || timeoutClient.DelegationCalls != 1 || timeoutClient.ExitCalls != 0 ||
            timeout.Termination != "battle-mission-observation-timeout")
            throw new AgentHostException("battle-mission-loop-self-test-timeout-not-bounded", "An unfinished Mission must stop at its poll bound without repeated delegation or exit calls.");

        return [
            new { scenario = "battle-mission-delegates-once-observes-mainhero-and-campaign-clock-and-returns-to-native-aftermath", passed = true },
            new { scenario = "battle-mission-returns-native-defeat-aftermath-without-a-victory-claim", passed = true },
            new { scenario = "battle-mission-records-mainhero-health-risk-without-model-polling", passed = true },
            new { scenario = "battle-mission-rejects-unsupported-native-state-before-delegation", passed = true },
            new { scenario = "battle-mission-passive-observation-timeout-does-not-repeat-native-actions", passed = true }
        ];
    }

    private static AgentHostBattleMissionLoopResult Failure(string termination, JsonObject native, bool delegationIssued, int delegatedFormationCount,
        double heroHealthStart, double heroHealthEnd, bool heroStayedPlayerControlled, double campaignDayStart, double campaignDayEnd,
        string? timeModeStart, string? timeModeEnd, int pollCount) =>
        BuildResult(false, termination, native, delegationIssued, delegatedFormationCount, heroHealthStart, heroHealthEnd,
            heroStayedPlayerControlled, campaignDayStart, campaignDayEnd, timeModeStart ?? string.Empty, timeModeEnd ?? string.Empty, pollCount);

    private static AgentHostBattleMissionLoopResult BuildResult(bool completed, string termination, JsonObject native,
        bool delegationIssued, int delegatedFormationCount, double heroHealthStart, double heroHealthEnd,
        bool heroStayedPlayerControlled, double campaignDayStart, double campaignDayEnd, string timeModeStart,
        string timeModeEnd, int pollCount) =>
        new(completed, termination, native, delegationIssued, delegatedFormationCount, heroHealthStart, heroHealthEnd,
            heroStayedPlayerControlled, campaignDayStart, campaignDayEnd, timeModeStart, timeModeEnd, pollCount);

    private static async Task<JsonObject> ReadStateAsync(IAgentHostBattleSimulationNativeClient client, int processId, CancellationToken cancellationToken)
    {
        using var response = await client.ReadStateAsync(cancellationToken);
        var native = ParseRoot(response.RootElement);
        if (ReadInt(native, "processId", -1) != processId)
            throw new AgentHostException("native-process-changed", "Native observations switched Bannerlord processes during the Battle Mission loop.");
        return native;
    }

    private static JsonObject ParseRoot(JsonElement root) => JsonNode.Parse(root.GetRawText()) as JsonObject ?? new JsonObject();
    private static string? ReadString(JsonObject? node, string name) => node?[name] is JsonValue value && value.TryGetValue<string>(out var text) ? text : null;
    private static int ReadInt(JsonObject? node, string name, int fallback = 0) => node?[name] is JsonValue value && value.TryGetValue<int>(out var number) ? number : fallback;
    private static double ReadDouble(JsonObject? node, string name, double fallback = double.NaN) => node?[name] is JsonValue value && value.TryGetValue<double>(out var number) && double.IsFinite(number) ? number : fallback;
    private static bool ReadBoolean(JsonObject? node, string name) => node?[name] is JsonValue value && value.TryGetValue<bool>(out var result) && result;
    private static double ReadHeroHealth(JsonObject mission) => ReadDouble(mission["mainAgent"] as JsonObject, "health");
    private static bool ReadHeroIsPlayerControlled(JsonObject mission) => ReadBoolean(mission["mainAgent"] as JsonObject, "isPlayerControlled");
    private static bool NearlyEqual(double left, double right) => double.IsFinite(left) && double.IsFinite(right) && Math.Abs(left - right) < 0.000001;

    private sealed class FakeBattleMissionNativeClient(bool supported = true, bool neverEnds = false, bool heroTakesDamage = false,
        bool capturedAfterBattle = false) :
        IAgentHostBattleSimulationNativeClient, IAgentHostBattleMissionNativeClient
    {
        private int _reads;
        private bool _exitRequested;
        internal int DelegationCalls { get; private set; }
        internal int ExitCalls { get; private set; }

        public Task<JsonDocument> ReadStateAsync(CancellationToken cancellationToken)
        {
            _reads++;
            var ended = !neverEnds && _reads >= 5;
            var aftermathReached = _exitRequested && _reads >= 6;
            var gameState = aftermathReached ? (capturedAfterBattle ? "MapState" : "PartyState") : "MissionState";
            var mission = new JsonObject
            {
                ["active"] = !ended,
                ["missionEnded"] = ended,
                ["mode"] = "Battle",
                ["mainAgent"] = new JsonObject { ["isPlayerControlled"] = true, ["health"] = heroTakesDamage && _reads >= 3 ? 40 : 100 }
            };
            return Task.FromResult(JsonDocument.Parse(new JsonObject
            {
                ["processId"] = 101,
                ["campaignDay"] = 42.0,
                ["timeControlMode"] = "Stop",
                ["state"] = new JsonObject
                {
                    ["context"] = new JsonObject
                    {
                        ["gameState"] = gameState,
                        ["menuId"] = aftermathReached && capturedAfterBattle ? "prisoner_wait" : null,
                        ["encounterActive"] = aftermathReached ? false : true,
                        ["captivity"] = aftermathReached && capturedAfterBattle ? new JsonObject { ["isCaptive"] = true } : null,
                        ["timeControlMode"] = "Stop"
                    },
                    ["mission"] = mission,
                    ["partyScreen"] = gameState == "PartyState" ? new JsonObject { ["mode"] = "Loot" } : null
                }
            }.ToJsonString()));
        }

        public Task<JsonDocument> ExecuteCampaignActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken) =>
            throw new AgentHostException("battle-mission-fake-unexpected-campaign-action", "No Campaign action is expected during a battle Mission.");

        public Task<JsonDocument> ExecuteBattleSimulationActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken) =>
            throw new AgentHostException("battle-mission-fake-unexpected-simulation-action", "The delegated Mission loop must not invoke BattleSimulation actions.");

        public Task<JsonDocument> PauseForVisibleHostileDecisionAsync(CancellationToken cancellationToken) =>
            throw new AgentHostException("battle-mission-fake-unexpected-pause", "The delegated Mission loop must not change Campaign clock controls.");

        public Task<JsonDocument> ReadBattleMissionStatusAsync(CancellationToken cancellationToken) => Task.FromResult(JsonDocument.Parse(new JsonObject
        {
            ["processId"] = 101,
            ["data"] = new JsonObject
            {
                ["supported"] = supported,
                ["missionMode"] = "Battle",
                ["mainAgent"] = new JsonObject { ["isPlayerControlled"] = true },
                ["playerTeam"] = new JsonObject { ["formationCount"] = 1 }
            }
        }.ToJsonString()));

        public Task<JsonDocument> DelegateBattleMissionTroopsAsync(CancellationToken cancellationToken)
        {
            DelegationCalls++;
            return Task.FromResult(JsonDocument.Parse(new JsonObject
            {
                ["processId"] = 101,
                ["status"] = "completed",
                ["data"] = new JsonObject
                {
                    ["allRequestedFormationsDelegated"] = true,
                    ["delegatedFormationCount"] = 1,
                    ["mainAgentStillPlayerControlled"] = true,
                    ["campaignDayBefore"] = 42.0,
                    ["campaignDayAfter"] = 42.0,
                    ["timeControlModeBefore"] = "Stop",
                    ["timeControlModeAfter"] = "Stop"
                }
            }.ToJsonString()));
        }

        public Task<JsonDocument> ExitEndedBattleMissionAsync(CancellationToken cancellationToken)
        {
            ExitCalls++;
            _exitRequested = true;
            return Task.FromResult(JsonDocument.Parse("{\"processId\":101,\"status\":\"completed\"}"));
        }
    }
}
