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
    bool MainHeroNativeAiControlMaintained,
    double CampaignDayAtStart,
    double CampaignDayAtEnd,
    string TimeControlModeAtStart,
    string TimeControlModeAtEnd,
    int PassivePollCount)
{
    public bool NativeDeploymentFinishIssued { get; init; }
    public bool NativeDeploymentAutoDeployIssued { get; init; }
    public bool NativeReadyCallbackDispatchedByBridge { get; init; }
    public int DeploymentTransitionPollCount { get; init; }
    public string MissionModeAtEntry { get; init; } = string.Empty;
    public bool MainAgentRemovedDuringMission { get; init; }
    public bool MainHeroAutopilotIssued { get; init; }
    public bool NativeMissionExitIssued { get; init; }
    public string NativeReadyHandlerExceptionType { get; init; } = string.Empty;
    public JsonObject? NativeDeploymentPreconditionDiagnostic { get; init; }
}

/// <summary>
/// Executes the bounded Native Delegate Command and MainHero AI handoff while the original Campaign Battle Mission
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
            var mode = ReadString(mission, "mode");
            if (string.Equals(gameState, "MissionState", StringComparison.Ordinal) &&
                (mode is "Deployment" or "Battle" || ReadBoolean(mission, "missionEnded"))) break;
            if (entryPolls < missionEntryPollLimit) await Task.Delay(delay, cancellationToken);
        }

        if (native is null || !string.Equals(ReadString((native["state"]?["context"] as JsonObject), "gameState"), "MissionState", StringComparison.Ordinal))
            return Failure("battle-mission-entry-timeout", native ?? new JsonObject(), false, 0, double.NaN, double.NaN, false, double.NaN, double.NaN, null, null, entryPolls);

        var initialState = native["state"]!.AsObject();
        var initialMission = initialState["mission"] as JsonObject ?? new JsonObject();
        var missionModeAtEntry = ReadString(initialMission, "mode") ?? string.Empty;
        if (missionModeAtEntry is not ("Deployment" or "Battle") ||
            ReadBoolean(initialMission, "missionEnded"))
            return Failure("battle-mission-not-active-battle", native, false, 0, ReadHeroHealth(initialMission), ReadHeroHealth(initialMission),
                false, ReadDouble(native, "campaignDay"), ReadDouble(native, "campaignDay"),
                ReadString(native, "timeControlMode"), ReadString(native, "timeControlMode"), 0);

        var campaignDayStart = ReadDouble(native, "campaignDay");
        var timeModeStart = ReadString(native, "timeControlMode") ?? ReadString(initialState["context"] as JsonObject, "timeControlMode") ?? string.Empty;
        if (timeModeStart != "Stop")
            return Failure("battle-mission-clock-not-stopped", native, false, 0, ReadHeroHealth(initialMission), ReadHeroHealth(initialMission),
                false, campaignDayStart, campaignDayStart, timeModeStart, timeModeStart, 0,
                missionModeAtEntry: missionModeAtEntry);
        var heroHealthStart = double.NaN;
        var pollCount = 0;
        var delegatedFormationCount = 0;
        var deploymentFinishIssued = false;
        var deploymentAutoDeployIssued = false;
        var nativeReadyCallbackDispatchedByBridge = false;
        var nativeReadyHandlerExceptionType = string.Empty;
        var deploymentTransitionPollCount = 0;

        if (missionModeAtEntry == "Deployment")
        {
            var context = initialState["context"] as JsonObject;
            if (ReadBoolean(context, "inquiryOpen"))
                return Failure("battle-mission-deployment-inquiry-open", native, false, 0, heroHealthStart, heroHealthStart,
                    false, campaignDayStart, campaignDayStart, timeModeStart, timeModeStart, pollCount,
                    deploymentFinishIssued: false, deploymentTransitionPollCount: deploymentTransitionPollCount, missionModeAtEntry: missionModeAtEntry);
            var deploymentUiReady = false;
            for (var deploymentPoll = 0; deploymentPoll < missionEntryPollLimit; deploymentPoll++)
            {
                cancellationToken.ThrowIfCancellationRequested();
                using var deploymentStatusResponse = await missionClient.ReadBattleMissionStatusAsync(cancellationToken);
                var deploymentStatus = ParseRoot(deploymentStatusResponse.RootElement);
                var deploymentData = deploymentStatus["data"] as JsonObject;
                var deploymentCampaignDay = ReadDouble(deploymentData, "campaignDay");
                var deploymentUi = deploymentData?["deploymentUi"] as JsonObject;
                var deploymentPreconditionFailures = new List<string>();
                if (ReadInt(deploymentStatus, "processId", -1) != processId) deploymentPreconditionFailures.Add("process-id");
                if (!ReadBoolean(deploymentData, "supported")) deploymentPreconditionFailures.Add("unsupported:" + (ReadString(deploymentData, "reason") ?? "unspecified"));
                if (ReadString(deploymentData, "missionMode") != "Deployment") deploymentPreconditionFailures.Add("mission-mode:" + (ReadString(deploymentData, "missionMode") ?? "missing"));
                if (!double.IsFinite(deploymentCampaignDay)) deploymentPreconditionFailures.Add("campaign-day-nonfinite");
                if (ReadString(deploymentData, "campaignTimeControlMode") != timeModeStart)
                    deploymentPreconditionFailures.Add("campaign-time-mode:" + (ReadString(deploymentData, "campaignTimeControlMode") ?? "missing"));
                if (deploymentPreconditionFailures.Count > 0)
                    return Failure("battle-mission-native-deployment-precondition-failed", native, false, 0, heroHealthStart, heroHealthStart,
                        false, campaignDayStart, campaignDayStart, timeModeStart, timeModeStart, pollCount,
                        deploymentFinishIssued: false, deploymentTransitionPollCount: deploymentTransitionPollCount, missionModeAtEntry: missionModeAtEntry,
                        nativeDeploymentPreconditionDiagnostic: BuildDeploymentPreconditionDiagnostic(deploymentStatus, deploymentPreconditionFailures));
                campaignDayStart = deploymentCampaignDay;
                if (ReadBoolean(deploymentUi, "viewAvailable") && ReadBoolean(deploymentUi, "readyCallbackBound") &&
                    ReadBoolean(deploymentUi, "canStartMission") && !ReadBoolean(deploymentUi, "deploymentFinished"))
                {
                    deploymentUiReady = true;
                    break;
                }
                if (deploymentAutoDeployIssued && ReadBoolean(deploymentUi, "viewAvailable") &&
                    ReadBoolean(deploymentUi, "canStartMission") && !ReadBoolean(deploymentUi, "deploymentFinished"))
                {
                    deploymentUiReady = true;
                    break;
                }
                if (!deploymentAutoDeployIssued && ReadBoolean(deploymentUi, "viewAvailable") &&
                    ReadBoolean(deploymentUi, "canStartMission") && !ReadBoolean(deploymentUi, "deploymentFinished"))
                {
                    using var autoDeployResponse = await missionClient.AutoDeployBattleMissionAsync(cancellationToken);
                    var autoDeploy = ParseRoot(autoDeployResponse.RootElement);
                    var autoDeployData = autoDeploy["data"] as JsonObject;
                    var autoDeployError = ReadString(autoDeploy, "error") ?? string.Empty;
                    if (ReadInt(autoDeploy, "processId", -1) == processId && ReadString(autoDeploy, "status") == "rejected")
                    {
                        var safeAutoDeployError = autoDeployError.Replace('\r', ' ').Replace('\n', ' ');
                        if (safeAutoDeployError.Length > 220) safeAutoDeployError = safeAutoDeployError[..220];
                        return Failure("battle-mission-native-auto-deploy-command-rejected:" + safeAutoDeployError, native, false, 0,
                            heroHealthStart, heroHealthStart, false, campaignDayStart, ReadDouble(autoDeploy, "campaignDay", campaignDayStart),
                            timeModeStart, ReadString(autoDeploy, "timeControlMode") ?? timeModeStart, pollCount,
                            deploymentFinishIssued: false, deploymentTransitionPollCount: deploymentTransitionPollCount,
                            missionModeAtEntry: missionModeAtEntry, nativeDeploymentAutoDeployIssued: true);
                    }
                    if (ReadInt(autoDeploy, "processId", -1) != processId || ReadString(autoDeploy, "status") != "completed" ||
                        ReadString(autoDeployData, "nativeHandler") != "MissionGauntletSingleplayerOrderUIHandler.OnAutoDeploy" ||
                        ReadString(autoDeployData, "nativeAutoDeployHandler") != "MissionOrderDeploymentControllerVM.ExecuteAutoDeploy" ||
                        ReadString(autoDeployData, "nativeDeploymentHandler") != "MissionOrderDeploymentControllerVM.ExecuteDeployPlayerSide" ||
                        !ReadBoolean(autoDeployData, "canStartMission") ||
                        !NearlyEqual(ReadDouble(autoDeployData, "campaignDayBefore"), campaignDayStart) ||
                        !NearlyEqual(ReadDouble(autoDeployData, "campaignDayAfter"), campaignDayStart) ||
                        ReadString(autoDeployData, "timeControlModeBefore") != timeModeStart ||
                        ReadString(autoDeployData, "timeControlModeAfter") != timeModeStart)
                        return Failure("battle-mission-native-auto-deploy-rejected", native, false, 0, heroHealthStart, heroHealthStart,
                            false, campaignDayStart, ReadDouble(autoDeploy, "campaignDay", campaignDayStart), timeModeStart,
                            ReadString(autoDeploy, "timeControlMode") ?? timeModeStart, pollCount,
                            deploymentFinishIssued: false, deploymentTransitionPollCount: deploymentTransitionPollCount,
                            missionModeAtEntry: missionModeAtEntry, nativeDeploymentAutoDeployIssued: true);
                    deploymentAutoDeployIssued = true;
                }
                if (deploymentPoll + 1 < missionEntryPollLimit) await Task.Delay(delay, cancellationToken);
            }
            if (!deploymentUiReady)
                return Failure("battle-mission-deployment-ui-not-ready", native, false, 0, heroHealthStart, heroHealthStart,
                    false, campaignDayStart, campaignDayStart, timeModeStart, timeModeStart, pollCount,
                    deploymentFinishIssued: false, deploymentTransitionPollCount: deploymentTransitionPollCount, missionModeAtEntry: missionModeAtEntry,
                    nativeDeploymentAutoDeployIssued: deploymentAutoDeployIssued);

            deploymentFinishIssued = true;
            JsonObject finishData;
            using (var finishResponse = await missionClient.FinishBattleMissionDeploymentAsync(cancellationToken))
            {
                var finish = ParseRoot(finishResponse.RootElement);
                finishData = finish["data"] as JsonObject ?? new JsonObject();
                nativeReadyCallbackDispatchedByBridge = ReadBoolean(finishData, "nativeReadyCallbackDispatchedByBridge");
                nativeReadyHandlerExceptionType = ReadString(finishData, "nativeReadyHandlerExceptionType") ?? string.Empty;
                var finishError = ReadString(finish, "error") ?? string.Empty;
                if (ReadInt(finish, "processId", -1) == processId && ReadString(finish, "status") == "rejected" &&
                    finishError.Contains("Ready callback is initialized", StringComparison.OrdinalIgnoreCase))
                    return Failure("battle-mission-native-ready-callback-not-bound", native, false, 0, heroHealthStart, heroHealthStart,
                        false, campaignDayStart, ReadDouble(finish, "campaignDay", campaignDayStart), timeModeStart,
                        ReadString(finish, "timeControlMode") ?? timeModeStart, pollCount,
                        deploymentFinishIssued: deploymentFinishIssued, deploymentTransitionPollCount: deploymentTransitionPollCount, missionModeAtEntry: missionModeAtEntry,
                        nativeDeploymentAutoDeployIssued: deploymentAutoDeployIssued);
                if (ReadInt(finish, "processId", -1) == processId && ReadString(finish, "status") == "rejected")
                {
                    var safeFinishError = finishError.Replace('\r', ' ').Replace('\n', ' ');
                    if (safeFinishError.Length > 220) safeFinishError = safeFinishError[..220];
                    return Failure("battle-mission-native-deployment-command-rejected:" + safeFinishError, native, false, 0,
                        heroHealthStart, heroHealthStart, false, campaignDayStart, ReadDouble(finish, "campaignDay", campaignDayStart),
                        timeModeStart, ReadString(finish, "timeControlMode") ?? timeModeStart, pollCount,
                        deploymentFinishIssued: deploymentFinishIssued, deploymentTransitionPollCount: deploymentTransitionPollCount,
                        missionModeAtEntry: missionModeAtEntry, nativeDeploymentAutoDeployIssued: deploymentAutoDeployIssued);
                }
                var finishValidationFailures = new List<string>();
                if (ReadInt(finish, "processId", -1) != processId) finishValidationFailures.Add("process-id");
                if (ReadString(finish, "status") != "completed") finishValidationFailures.Add("status-" + (ReadString(finish, "status") ?? "missing"));
                if (ReadString(finishData, "nativeHandler") != "OrderOfBattleVM.ExecuteBeginMission") finishValidationFailures.Add("native-handler");
                if (ReadString(finishData, "nativeDeploymentHandler") != "DeploymentHandler.FinishDeployment") finishValidationFailures.Add("native-deployment-handler");
                if (!ReadBoolean(finishData, "canStartMission")) finishValidationFailures.Add("ready-disabled");
                if (!ReadBoolean(finishData, "readyCallbackBoundBefore") && !ReadBoolean(finishData, "nativeReadyCallbackDispatchedByBridge")) finishValidationFailures.Add("ready-callback-not-dispatched");
                if (ReadString(finishData, "modeBefore") != "Deployment") finishValidationFailures.Add("mode-before");
                if (ReadString(finishData, "timeControlModeBefore") != timeModeStart) finishValidationFailures.Add("time-before");
                if (ReadString(finishData, "timeControlModeAfter") != timeModeStart) finishValidationFailures.Add("time-after");
                if (finishValidationFailures.Count > 0)
                    return Failure("battle-mission-native-deployment-finish-rejected:" + string.Join(",", finishValidationFailures), native, false, 0, heroHealthStart, heroHealthStart,
                        false, campaignDayStart, ReadDouble(finish, "campaignDay", campaignDayStart), timeModeStart,
                        ReadString(finish, "timeControlMode") ?? timeModeStart, pollCount,
                        deploymentFinishIssued: deploymentFinishIssued, deploymentTransitionPollCount: deploymentTransitionPollCount, missionModeAtEntry: missionModeAtEntry,
                        nativeDeploymentAutoDeployIssued: deploymentAutoDeployIssued);
                var deploymentFinishDayBefore = ReadDouble(finishData, "campaignDayBefore");
                var deploymentFinishDayAfter = ReadDouble(finishData, "campaignDayAfter");
                if (!NearlyEqual(deploymentFinishDayBefore, deploymentFinishDayAfter))
                    return Failure("battle-mission-native-deployment-action-campaign-day-changed:" +
                        deploymentFinishDayBefore.ToString("R", CultureInfo.InvariantCulture) + "->" +
                        deploymentFinishDayAfter.ToString("R", CultureInfo.InvariantCulture), native, false, 0,
                        heroHealthStart, heroHealthStart, false, campaignDayStart, deploymentFinishDayAfter, timeModeStart,
                        ReadString(finish, "timeControlMode") ?? timeModeStart, pollCount,
                        deploymentFinishIssued: deploymentFinishIssued, deploymentTransitionPollCount: deploymentTransitionPollCount, missionModeAtEntry: missionModeAtEntry,
                        nativeDeploymentAutoDeployIssued: deploymentAutoDeployIssued,
                        nativeReadyCallbackDispatchedByBridge: nativeReadyCallbackDispatchedByBridge);
                if (!ReadBoolean(finishData, "deploymentFinishedAfter"))
                    return Failure("battle-mission-native-ready-did-not-finish-deployment", native, false, 0, heroHealthStart, heroHealthStart,
                        false, campaignDayStart, ReadDouble(finish, "campaignDay", campaignDayStart), timeModeStart,
                        ReadString(finish, "timeControlMode") ?? timeModeStart, pollCount,
                        deploymentFinishIssued: deploymentFinishIssued, deploymentTransitionPollCount: deploymentTransitionPollCount, missionModeAtEntry: missionModeAtEntry,
                        nativeDeploymentAutoDeployIssued: deploymentAutoDeployIssued);
            }

            var battleModeObserved = false;
            for (var poll = 0; poll < missionEntryPollLimit; poll++)
            {
                cancellationToken.ThrowIfCancellationRequested();
                if (poll > 0) await Task.Delay(delay, cancellationToken);
                native = await ReadStateAsync(stateClient, processId, cancellationToken);
                deploymentTransitionPollCount++;
                var state = native["state"] as JsonObject ?? new JsonObject();
                var contextAfterFinish = state["context"] as JsonObject ?? new JsonObject();
                var missionAfterFinish = state["mission"] as JsonObject;
                if (!string.Equals(ReadString(contextAfterFinish, "gameState"), "MissionState", StringComparison.Ordinal) ||
                    ReadBoolean(missionAfterFinish, "missionEnded"))
                    return Failure("battle-mission-left-state-before-battle-mode", native, false, 0, heroHealthStart, heroHealthStart,
                        false, campaignDayStart, ReadDouble(native, "campaignDay"), timeModeStart,
                        ReadString(native, "timeControlMode") ?? string.Empty, pollCount,
                        deploymentFinishIssued: deploymentFinishIssued, deploymentTransitionPollCount: deploymentTransitionPollCount, missionModeAtEntry: missionModeAtEntry);
                if (ReadBoolean(contextAfterFinish, "inquiryOpen"))
                    return Failure("battle-mission-deployment-finish-opened-inquiry", native, false, 0, heroHealthStart, heroHealthStart,
                        false, campaignDayStart, ReadDouble(native, "campaignDay"), timeModeStart,
                        ReadString(native, "timeControlMode") ?? string.Empty, pollCount,
                        deploymentFinishIssued: deploymentFinishIssued, deploymentTransitionPollCount: deploymentTransitionPollCount, missionModeAtEntry: missionModeAtEntry);
                if (ReadString(missionAfterFinish, "mode") == "Battle")
                {
                    battleModeObserved = true;
                    break;
                }
                if (ReadString(missionAfterFinish, "mode") != "Deployment")
                    return Failure("battle-mission-deployment-finish-entered-unsupported-mode", native, false, 0, heroHealthStart, heroHealthStart,
                        false, campaignDayStart, ReadDouble(native, "campaignDay"), timeModeStart,
                        ReadString(native, "timeControlMode") ?? string.Empty, pollCount,
                        deploymentFinishIssued: deploymentFinishIssued, deploymentTransitionPollCount: deploymentTransitionPollCount, missionModeAtEntry: missionModeAtEntry);
            }
            if (!battleModeObserved)
                return Failure("battle-mission-deployment-transition-timeout", native ?? new JsonObject(), false, 0, heroHealthStart, heroHealthStart,
                    false, campaignDayStart, ReadDouble(native, "campaignDay"), timeModeStart,
                    ReadString(native, "timeControlMode") ?? string.Empty, pollCount,
                    deploymentFinishIssued: deploymentFinishIssued, deploymentTransitionPollCount: deploymentTransitionPollCount, missionModeAtEntry: missionModeAtEntry);

            initialState = native!["state"]!.AsObject();
            initialMission = initialState["mission"] as JsonObject ?? new JsonObject();
            heroHealthStart = ReadHeroHealth(initialMission);
        }

        var battleMainAgentReady = false;
        var preciseBattleCampaignDayEstablished = missionModeAtEntry == "Deployment";
        for (var readinessPoll = 0; readinessPoll < missionEntryPollLimit; readinessPoll++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            using var statusResponse = await missionClient.ReadBattleMissionStatusAsync(cancellationToken);
            var status = ParseRoot(statusResponse.RootElement);
            if (ReadInt(status, "processId", -1) != processId)
                return Failure("battle-mission-process-mismatch", native, false, 0, heroHealthStart, heroHealthStart, false,
                    campaignDayStart, campaignDayStart, timeModeStart, timeModeStart, pollCount);
            var data = status["data"] as JsonObject;
            var statusCampaignDay = ReadDouble(data, "campaignDay");
            if (!ReadBoolean(data, "supported") || !string.Equals(ReadString(data, "missionMode"), "Battle", StringComparison.Ordinal) ||
                ReadInt(data?["playerTeam"] as JsonObject, "formationCount", 0) <= 0 || !double.IsFinite(statusCampaignDay) ||
                ReadString(data, "campaignTimeControlMode") != timeModeStart)
                return Failure("battle-mission-native-delegation-precondition-failed", native, false, 0, heroHealthStart, heroHealthStart,
                    false, campaignDayStart, campaignDayStart, timeModeStart, timeModeStart, pollCount);
            if (!preciseBattleCampaignDayEstablished)
            {
                if (Math.Abs(statusCampaignDay - campaignDayStart) > 0.0005)
                    return Failure("battle-mission-clock-changed-before-mainagent-readiness", native, false, 0, heroHealthStart, heroHealthStart,
                        false, campaignDayStart, statusCampaignDay, timeModeStart, ReadString(data, "campaignTimeControlMode") ?? string.Empty, pollCount);
                campaignDayStart = statusCampaignDay;
                preciseBattleCampaignDayEstablished = true;
            }
            else if (!NearlyEqual(statusCampaignDay, campaignDayStart))
                return Failure("battle-mission-clock-changed-before-mainagent-readiness", native, false, 0, heroHealthStart, heroHealthStart,
                    false, campaignDayStart, statusCampaignDay, timeModeStart, ReadString(data, "campaignTimeControlMode") ?? string.Empty, pollCount);

            var mainAgent = data?["mainAgent"] as JsonObject;
            if (mainAgent != null && ReadBoolean(mainAgent, "isPlayerControlled") && ReadString(mainAgent, "controller") == "Player")
            {
                heroHealthStart = ReadDouble(mainAgent, "health");
                if (double.IsFinite(heroHealthStart)) { battleMainAgentReady = true; break; }
            }

            if (readinessPoll + 1 >= missionEntryPollLimit)
                return Failure("battle-mission-mainagent-readiness-timeout", native, false, 0, heroHealthStart, heroHealthStart,
                    false, campaignDayStart, campaignDayStart, timeModeStart, timeModeStart, pollCount);

            await Task.Delay(delay, cancellationToken);
            native = await ReadStateAsync(stateClient, processId, cancellationToken);
            var readinessState = native["state"] as JsonObject ?? new JsonObject();
            var readinessContext = readinessState["context"] as JsonObject ?? new JsonObject();
            var readinessMission = readinessState["mission"] as JsonObject;
            if (!string.Equals(ReadString(readinessContext, "gameState"), "MissionState", StringComparison.Ordinal) ||
                ReadBoolean(readinessMission, "missionEnded") || ReadBoolean(readinessContext, "inquiryOpen") ||
                !string.Equals(ReadString(readinessMission, "mode"), "Battle", StringComparison.Ordinal))
                return Failure("battle-mission-left-state-before-mainagent-readiness", native, false, 0, heroHealthStart, heroHealthStart,
                    false, campaignDayStart, ReadDouble(native, "campaignDay"), timeModeStart,
                    ReadString(native, "timeControlMode") ?? string.Empty, pollCount);
        }
        if (!battleMainAgentReady)
            return Failure("battle-mission-mainagent-readiness-timeout", native, false, 0, heroHealthStart, heroHealthStart,
                false, campaignDayStart, campaignDayStart, timeModeStart, timeModeStart, pollCount);

        using (var delegateResponse = await missionClient.DelegateBattleMissionTroopsAsync(cancellationToken))
        {
            var delegated = ParseRoot(delegateResponse.RootElement);
            if (ReadInt(delegated, "processId", -1) != processId || ReadString(delegated, "status") != "completed")
                return Failure("battle-mission-delegation-rejected", native, false, 0, heroHealthStart, heroHealthStart,
                    false, campaignDayStart, campaignDayStart, timeModeStart, timeModeStart, pollCount);
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

        var nativeAiHandoffVerified = false;
        var mainHeroAutopilotIssued = false;
        using (var autopilotResponse = await missionClient.AutopilotMainAgentBattleMissionAsync(cancellationToken))
        {
            mainHeroAutopilotIssued = true;
            var autopilot = ParseRoot(autopilotResponse.RootElement);
            var receipt = autopilot["data"] as JsonObject;
            if (ReadInt(autopilot, "processId", -1) != processId || ReadString(autopilot, "status") != "completed" ||
                ReadString(receipt, "scope") != "agenthost-native-battle-autopilot" ||
                ReadString(receipt, "handoffMode") != "rts-camera-native-ai-initialization" ||
                ReadString(receipt, "controllerBefore") != "Player" || ReadString(receipt, "controllerAfter") != "AI" ||
                ReadBoolean(receipt, "isPlayerControlledAfter") || !ReadBoolean(receipt, "isAIControlledAfter") ||
                ReadBoolean(receipt, "missionMainAgentControllerActiveAfter") ||
                ReadInt(receipt, "missionMainAgentIndexBefore", -1) != ReadInt(receipt, "missionMainAgentIndexAfter", -2) ||
                ReadString(receipt, "timeControlModeBefore") != timeModeStart || ReadString(receipt, "timeControlModeAfter") != timeModeStart ||
                !NearlyEqual(ReadDouble(receipt, "campaignDayBefore"), campaignDayStart) ||
                !NearlyEqual(ReadDouble(receipt, "campaignDayAfter"), campaignDayStart))
                return Failure("battle-mission-native-mainhero-autopilot-rejected", native, true,
                    delegatedFormationCount, heroHealthStart, heroHealthStart, false, campaignDayStart,
                    ReadDouble(autopilot, "campaignDay", campaignDayStart), timeModeStart,
                    ReadString(autopilot, "timeControlMode") ?? timeModeStart, pollCount,
                    mainHeroAutopilotIssued: mainHeroAutopilotIssued);
            nativeAiHandoffVerified = true;
        }

        var mainHeroNativeAiControlMaintained = nativeAiHandoffVerified;
        var mainAgentRemovedDuringMission = false;
        var nativeMissionExitIssued = false;
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
            if (!string.Equals(gameState, "MissionState", StringComparison.Ordinal))
                return BuildResult(true, "native-aftermath-reached", native, true,
                    delegatedFormationCount, heroHealthStart, heroHealthEnd,
                    mainHeroNativeAiControlMaintained, campaignDayStart, ReadDouble(native, "campaignDay"), timeModeStart,
                    ReadString(native, "timeControlMode") ?? string.Empty, pollCount, deploymentFinishIssued,
                    deploymentTransitionPollCount, missionModeAtEntry, mainAgentRemovedDuringMission,
                    mainHeroAutopilotIssued, nativeMissionExitIssued, deploymentAutoDeployIssued, nativeReadyCallbackDispatchedByBridge,
                    nativeReadyHandlerExceptionType);
            if (missionIsEnded)
            {
                missionEndedObserved = true;
                break;
            }

            using (var currentMissionStatusResponse = await missionClient.ReadBattleMissionStatusAsync(cancellationToken))
            {
                var currentMissionStatus = ParseRoot(currentMissionStatusResponse.RootElement);
                var data = currentMissionStatus["data"] as JsonObject;
                var mainAgent = data?["mainAgent"] as JsonObject;
                if (ReadInt(currentMissionStatus, "processId", -1) != processId || !ReadBoolean(data, "supported") ||
                    ReadString(data, "missionMode") != "Battle")
                    mainHeroNativeAiControlMaintained = false;
                else if (mainAgent == null)
                    mainAgentRemovedDuringMission = true;
                else
                {
                    heroHealthEnd = ReadDouble(mainAgent, "health", heroHealthEnd);
                    if (ReadString(mainAgent, "controller") != "AI" || !ReadBoolean(mainAgent, "isAIControlled") ||
                        !TryReadBoolean(mainAgent, "missionMainAgentControllerActive", out var inputControllerActive) || inputControllerActive)
                        mainHeroNativeAiControlMaintained = false;
                }
            }
        }

        if (!missionEndedObserved)
                return Failure("battle-mission-observation-timeout", native ?? new JsonObject(), true, 0, heroHealthStart, heroHealthEnd,
                mainHeroNativeAiControlMaintained, campaignDayStart, ReadDouble(native, "campaignDay"), timeModeStart,
                ReadString(native, "timeControlMode") ?? string.Empty, pollCount,
                mainHeroAutopilotIssued: mainHeroAutopilotIssued);

        // This is the Native BattleEndLogic path used by the battle exit handling, after the Mission
        // has already ended. It is distinct from the friendly-location Leave Area hold wrapper.
        using (var exitResponse = await missionClient.ExitEndedBattleMissionAsync(cancellationToken))
        {
            nativeMissionExitIssued = true;
            var exit = ParseRoot(exitResponse.RootElement);
            if (ReadInt(exit, "processId", -1) != processId || ReadString(exit, "status") != "completed")
                return Failure("battle-mission-native-exit-rejected", native!, true, 0, heroHealthStart, heroHealthEnd,
                    mainHeroNativeAiControlMaintained, campaignDayStart, ReadDouble(native, "campaignDay"), timeModeStart,
                    ReadString(native, "timeControlMode") ?? string.Empty, pollCount,
                    mainHeroAutopilotIssued: mainHeroAutopilotIssued, nativeMissionExitIssued: nativeMissionExitIssued);
        }

        for (var poll = 0; poll < endScreenExitPollLimit; poll++)
        {
            native = await ReadStateAsync(stateClient, processId, cancellationToken);
            var gameState = ReadString(native["state"]?["context"] as JsonObject, "gameState");
            if (!string.Equals(gameState, "MissionState", StringComparison.Ordinal))
                return BuildResult(true, "native-aftermath-reached", native, true,
                    delegatedFormationCount, heroHealthStart, heroHealthEnd,
                    mainHeroNativeAiControlMaintained, campaignDayStart, ReadDouble(native, "campaignDay"), timeModeStart,
                    ReadString(native, "timeControlMode") ?? string.Empty, pollCount, deploymentFinishIssued,
                    deploymentTransitionPollCount, missionModeAtEntry, mainAgentRemovedDuringMission,
                    mainHeroAutopilotIssued, nativeMissionExitIssued, deploymentAutoDeployIssued, nativeReadyCallbackDispatchedByBridge,
                    nativeReadyHandlerExceptionType);
            if (poll + 1 < endScreenExitPollLimit) await Task.Delay(delay, cancellationToken);
        }
        return Failure("battle-mission-aftermath-transition-timeout", native ?? new JsonObject(), true, 0, heroHealthStart, heroHealthEnd,
            mainHeroNativeAiControlMaintained, campaignDayStart, ReadDouble(native, "campaignDay"), timeModeStart,
            ReadString(native, "timeControlMode") ?? string.Empty, pollCount,
            mainHeroAutopilotIssued: mainHeroAutopilotIssued, nativeMissionExitIssued: nativeMissionExitIssued);
    }

    internal static IReadOnlyList<object> RunContractSelfTests()
    {
        var successClient = new FakeBattleMissionNativeClient();
        var result = RunAsync(successClient, successClient, 101, CancellationToken.None, TimeSpan.Zero,
            missionEntryPollLimit: 2, missionCompletionPollLimit: 6, endScreenExitPollLimit: 2).GetAwaiter().GetResult();
        if (!result.Completed || result.Termination != "native-aftermath-reached" || successClient.DelegationCalls != 1 ||
            successClient.AutopilotCalls != 1 || successClient.ExitCalls != 1 || result.DelegatedFormationCount != 1 || !result.MainHeroNativeAiControlMaintained ||
            result.MainHeroHealthAtStart != 100 || result.MainHeroHealthAtEnd != 100 ||
            result.CampaignDayAtStart != 42 || result.CampaignDayAtEnd != 42 ||
            result.TimeControlModeAtStart != "Stop" || result.TimeControlModeAtEnd != "Stop" ||
            ReadString(result.FinalNative["state"]?["context"] as JsonObject, "gameState") != "PartyState")
            throw new AgentHostException("battle-mission-loop-self-test-delegation-flow-failed", $"The Mission controller must delegate once, keep the Native MainHero AI lease through the Mission, and return to Native aftermath without a model call. completed={result.Completed}; termination={result.Termination}; delegationCalls={successClient.DelegationCalls}; autopilotCalls={successClient.AutopilotCalls}; exitCalls={successClient.ExitCalls}; formations={result.DelegatedFormationCount}; nativeAiMaintained={result.MainHeroNativeAiControlMaintained}; health={result.MainHeroHealthAtStart}->{result.MainHeroHealthAtEnd}; campaignDay={result.CampaignDayAtStart}->{result.CampaignDayAtEnd}; time={result.TimeControlModeAtStart}->{result.TimeControlModeAtEnd}; finalState={ReadString(result.FinalNative["state"]?["context"] as JsonObject, "gameState")}");

        var defeatClient = new FakeBattleMissionNativeClient(capturedAfterBattle: true);
        var defeat = RunAsync(defeatClient, defeatClient, 101, CancellationToken.None, TimeSpan.Zero,
            missionEntryPollLimit: 2, missionCompletionPollLimit: 6, endScreenExitPollLimit: 2).GetAwaiter().GetResult();
        if (!defeat.Completed || defeat.Termination != "native-aftermath-reached" || defeatClient.DelegationCalls != 1 || defeatClient.AutopilotCalls != 1 ||
            !ReadBoolean(defeat.FinalNative["state"]?["context"]?["captivity"] as JsonObject, "isCaptive") ||
            ReadString(defeat.FinalNative["state"]?["context"] as JsonObject, "menuId") != "prisoner_wait")
            throw new AgentHostException("battle-mission-loop-self-test-native-defeat-aftermath-not-preserved", "A Native defeat/captivity aftermath must be returned as observed and not mislabeled as victory.");

        var riskClient = new FakeBattleMissionNativeClient(heroTakesDamage: true);
        var risk = RunAsync(riskClient, riskClient, 101, CancellationToken.None, TimeSpan.Zero,
            missionEntryPollLimit: 2, missionCompletionPollLimit: 6, endScreenExitPollLimit: 2).GetAwaiter().GetResult();
        if (!risk.Completed || riskClient.DelegationCalls != 1 || riskClient.AutopilotCalls != 1 || risk.MainHeroHealthAtStart != 100 ||
            risk.MainHeroHealthAtEnd >= risk.MainHeroHealthAtStart || !risk.MainHeroNativeAiControlMaintained)
            throw new AgentHostException("battle-mission-loop-self-test-mainhero-risk-observation-failed", "The passive Mission controller must retain observed MainHero health loss and verify that Native AI control remains active; it must not claim health stayed unchanged.");

        var rejectedClient = new FakeBattleMissionNativeClient(supported: false);
        var rejected = RunAsync(rejectedClient, rejectedClient, 101, CancellationToken.None, TimeSpan.Zero,
            missionEntryPollLimit: 2, missionCompletionPollLimit: 2, endScreenExitPollLimit: 2).GetAwaiter().GetResult();
        if (rejected.Completed || rejectedClient.DelegationCalls != 0 || rejectedClient.AutopilotCalls != 0 || rejectedClient.ExitCalls != 0 ||
            rejected.Termination != "battle-mission-native-delegation-precondition-failed")
            throw new AgentHostException("battle-mission-loop-self-test-unsupported-mission-not-rejected", "The loop must reject a Native unsupported Mission before issuing Delegate Command.");

        var timeoutClient = new FakeBattleMissionNativeClient(neverEnds: true);
        var timeout = RunAsync(timeoutClient, timeoutClient, 101, CancellationToken.None, TimeSpan.Zero,
            missionEntryPollLimit: 2, missionCompletionPollLimit: 3, endScreenExitPollLimit: 2).GetAwaiter().GetResult();
        if (timeout.Completed || timeoutClient.DelegationCalls != 1 || timeoutClient.AutopilotCalls != 1 || timeoutClient.ExitCalls != 0 ||
            timeout.Termination != "battle-mission-observation-timeout")
            throw new AgentHostException("battle-mission-loop-self-test-timeout-not-bounded", "An unfinished Mission must stop at its poll bound without repeated delegation or exit calls.");

        var rejectedHandoffClient = new FakeBattleMissionNativeClient(autopilotRejected: true);
        var rejectedHandoff = RunAsync(rejectedHandoffClient, rejectedHandoffClient, 101, CancellationToken.None, TimeSpan.Zero,
            missionEntryPollLimit: 2, missionCompletionPollLimit: 6, endScreenExitPollLimit: 2).GetAwaiter().GetResult();
        if (rejectedHandoff.Completed || rejectedHandoffClient.DelegationCalls != 1 || rejectedHandoffClient.AutopilotCalls != 1 ||
            rejectedHandoffClient.ExitCalls != 0 || rejectedHandoff.Termination != "battle-mission-native-mainhero-autopilot-rejected")
            throw new AgentHostException("battle-mission-loop-self-test-native-ai-handoff-rejection-not-explicit", "A rejected Native MainHero handoff must stop with an explicit unresolved result and no repeated action or false battle result.");

        var controlLossClient = new FakeBattleMissionNativeClient(loseAutopilotControl: true);
        var controlLoss = RunAsync(controlLossClient, controlLossClient, 101, CancellationToken.None, TimeSpan.Zero,
            missionEntryPollLimit: 2, missionCompletionPollLimit: 6, endScreenExitPollLimit: 2).GetAwaiter().GetResult();
        if (!controlLoss.Completed || controlLoss.MainHeroNativeAiControlMaintained || controlLossClient.AutopilotCalls != 1 ||
            controlLossClient.ExitCalls != 1)
            throw new AgentHostException("battle-mission-loop-self-test-native-ai-control-loss-overclaimed", "A completed Native aftermath may be returned after control loss, but the Host must record that Native AI control did not persist.");

        return [
            new { scenario = "battle-mission-delegates-troops-and-native-ai-controls-mainhero-until-aftermath", passed = true },
            new { scenario = "battle-mission-returns-native-defeat-aftermath-without-a-victory-claim", passed = true },
            new { scenario = "battle-mission-records-mainhero-health-risk-without-model-polling", passed = true },
            new { scenario = "battle-mission-rejects-unsupported-native-state-before-delegation", passed = true },
            new { scenario = "battle-mission-passive-observation-timeout-does-not-repeat-native-actions", passed = true },
            new { scenario = "battle-mission-native-mainhero-autopilot-rejection-remains-unresolved", passed = true },
            new { scenario = "battle-mission-native-mainhero-control-loss-is-not-overclaimed", passed = true }
        ];
    }

    private static AgentHostBattleMissionLoopResult Failure(string termination, JsonObject native, bool delegationIssued, int delegatedFormationCount,
        double heroHealthStart, double heroHealthEnd, bool heroNativeAiControlMaintained, double campaignDayStart, double campaignDayEnd,
        string? timeModeStart, string? timeModeEnd, int pollCount, bool deploymentFinishIssued = false,
        int deploymentTransitionPollCount = 0, string missionModeAtEntry = "", bool mainHeroAutopilotIssued = false,
        bool nativeMissionExitIssued = false, bool nativeDeploymentAutoDeployIssued = false,
        bool nativeReadyCallbackDispatchedByBridge = false, string nativeReadyHandlerExceptionType = "",
        JsonObject? nativeDeploymentPreconditionDiagnostic = null) =>
        BuildResult(false, termination, native, delegationIssued, delegatedFormationCount, heroHealthStart, heroHealthEnd,
            heroNativeAiControlMaintained, campaignDayStart, campaignDayEnd, timeModeStart ?? string.Empty, timeModeEnd ?? string.Empty,
            pollCount, deploymentFinishIssued, deploymentTransitionPollCount, missionModeAtEntry,
            mainHeroAutopilotIssued: mainHeroAutopilotIssued, nativeMissionExitIssued: nativeMissionExitIssued,
            nativeDeploymentAutoDeployIssued: nativeDeploymentAutoDeployIssued,
            nativeReadyCallbackDispatchedByBridge: nativeReadyCallbackDispatchedByBridge,
            nativeReadyHandlerExceptionType: nativeReadyHandlerExceptionType,
            nativeDeploymentPreconditionDiagnostic: nativeDeploymentPreconditionDiagnostic);

    private static AgentHostBattleMissionLoopResult BuildResult(bool completed, string termination, JsonObject native,
        bool delegationIssued, int delegatedFormationCount, double heroHealthStart, double heroHealthEnd,
        bool heroNativeAiControlMaintained, double campaignDayStart, double campaignDayEnd, string timeModeStart,
        string timeModeEnd, int pollCount, bool deploymentFinishIssued = false, int deploymentTransitionPollCount = 0,
        string missionModeAtEntry = "", bool mainAgentRemovedDuringMission = false, bool mainHeroAutopilotIssued = false,
        bool nativeMissionExitIssued = false, bool nativeDeploymentAutoDeployIssued = false,
        bool nativeReadyCallbackDispatchedByBridge = false, string nativeReadyHandlerExceptionType = "",
        JsonObject? nativeDeploymentPreconditionDiagnostic = null) =>
        new(completed, termination, native, delegationIssued, delegatedFormationCount, heroHealthStart, heroHealthEnd,
            heroNativeAiControlMaintained, campaignDayStart, campaignDayEnd, timeModeStart, timeModeEnd, pollCount)
        {
            NativeDeploymentFinishIssued = deploymentFinishIssued,
            NativeDeploymentAutoDeployIssued = nativeDeploymentAutoDeployIssued,
            NativeReadyCallbackDispatchedByBridge = nativeReadyCallbackDispatchedByBridge,
            NativeReadyHandlerExceptionType = nativeReadyHandlerExceptionType,
            DeploymentTransitionPollCount = deploymentTransitionPollCount,
            MissionModeAtEntry = missionModeAtEntry,
            MainAgentRemovedDuringMission = mainAgentRemovedDuringMission,
            MainHeroAutopilotIssued = mainHeroAutopilotIssued,
            NativeMissionExitIssued = nativeMissionExitIssued,
            NativeDeploymentPreconditionDiagnostic = nativeDeploymentPreconditionDiagnostic?.DeepClone() as JsonObject
        };

    private static JsonObject BuildDeploymentPreconditionDiagnostic(JsonObject status, IReadOnlyCollection<string> failures)
    {
        var data = status["data"] as JsonObject;
        var campaignDay = ReadDouble(data, "campaignDay");
        return new JsonObject
        {
            ["failures"] = new JsonArray(failures.Select(failure => (JsonNode?)JsonValue.Create(failure)).ToArray()),
            ["processId"] = ReadInt(status, "processId", -1),
            ["status"] = ReadString(status, "status"),
            ["supported"] = ReadBoolean(data, "supported"),
            ["reason"] = ReadString(data, "reason"),
            ["missionMode"] = ReadString(data, "missionMode"),
            ["campaignDay"] = double.IsFinite(campaignDay) ? JsonValue.Create(campaignDay) : null,
            ["campaignTimeControlMode"] = ReadString(data, "campaignTimeControlMode"),
            ["deploymentUi"] = data?["deploymentUi"]?.DeepClone()
        };
    }

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
    private static bool TryReadBoolean(JsonObject? node, string name, out bool result)
    {
        if (node?[name] is JsonValue value && value.TryGetValue<bool>(out result)) return true;
        result = false;
        return false;
    }
    private static double ReadHeroHealth(JsonObject mission) => ReadDouble(mission["mainAgent"] as JsonObject, "health");
    private static bool NearlyEqual(double left, double right) => double.IsFinite(left) && double.IsFinite(right) && Math.Abs(left - right) < 0.000001;

    private sealed class FakeBattleMissionNativeClient(bool supported = true, bool neverEnds = false, bool heroTakesDamage = false,
        bool capturedAfterBattle = false, bool autopilotRejected = false, bool loseAutopilotControl = false) :
        IAgentHostBattleSimulationNativeClient, IAgentHostBattleMissionNativeClient
    {
        private int _reads;
        private bool _exitRequested;
        private bool _autopilotStarted;
        internal int DelegationCalls { get; private set; }
        internal int AutopilotCalls { get; private set; }
        internal int ExitCalls { get; private set; }

        public Task<JsonDocument> ReadStateAsync(CancellationToken cancellationToken)
        {
            _reads++;
            var ended = !neverEnds && _reads >= 5;
            var aftermathReached = _exitRequested && _reads >= 6;
            var gameState = aftermathReached ? (capturedAfterBattle ? "MapState" : "PartyState") : "MissionState";
            var nativeAiControlActive = _autopilotStarted && !(loseAutopilotControl && _reads >= 3);
            var mission = new JsonObject
            {
                ["active"] = !ended,
                ["missionEnded"] = ended,
                ["mode"] = "Battle",
                ["mainAgent"] = new JsonObject
                {
                    ["controller"] = nativeAiControlActive ? "AI" : "Player",
                    ["isPlayerControlled"] = !nativeAiControlActive,
                    ["isAIControlled"] = nativeAiControlActive,
                    ["missionMainAgentControllerActive"] = !nativeAiControlActive,
                    ["health"] = heroTakesDamage && _reads >= 3 ? 40 : 100
                }
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
                ["campaignDay"] = 42.0,
                ["campaignTimeControlMode"] = "Stop",
            ["mainAgent"] = new JsonObject
                {
                ["controller"] = _autopilotStarted && !(loseAutopilotControl && _reads >= 3) ? "AI" : "Player",
                ["isPlayerControlled"] = !(_autopilotStarted && !(loseAutopilotControl && _reads >= 3)),
                ["isAIControlled"] = _autopilotStarted && !(loseAutopilotControl && _reads >= 3),
                    ["missionMainAgentControllerActive"] = !(_autopilotStarted && !(loseAutopilotControl && _reads >= 3)),
                    ["health"] = heroTakesDamage && _reads >= 3 ? 40 : 100
                },
                ["mainAgentAiControlLease"] = _autopilotStarted
                    ? new JsonObject { ["active"] = true, ["scope"] = "agenthost-native-battle-autopilot", ["status"] = "active" }
                    : new JsonObject { ["active"] = false, ["scope"] = "none", ["status"] = "never-started" },
                ["playerTeam"] = new JsonObject { ["formationCount"] = 1 }
            }
        }.ToJsonString()));

        public Task<JsonDocument> AutoDeployBattleMissionAsync(CancellationToken cancellationToken) =>
            throw new AgentHostException("battle-mission-fake-unexpected-auto-deploy", "The fixture already starts in Battle mode; Native Deployment auto-deploy is not expected.");

        public Task<JsonDocument> FinishBattleMissionDeploymentAsync(CancellationToken cancellationToken) =>
            throw new AgentHostException("battle-mission-fake-unexpected-deployment-finish", "The fixture already starts in Battle mode; no deployment finish is expected.");

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

        public Task<JsonDocument> AutopilotMainAgentBattleMissionAsync(CancellationToken cancellationToken)
        {
            AutopilotCalls++;
            if (AutopilotCalls != 1 || DelegationCalls != 1)
                throw new AgentHostException("battle-mission-fake-autopilot-order-invalid", "Native MainHero AI handoff must occur once after Native troop delegation.");
            if (autopilotRejected)
                return Task.FromResult(JsonDocument.Parse("{\"processId\":101,\"status\":\"rejected\",\"campaignDay\":42.0,\"timeControlMode\":\"Stop\",\"data\":{\"scope\":\"agenthost-native-battle-autopilot\"}}"));
            _autopilotStarted = true;
            return Task.FromResult(JsonDocument.Parse(new JsonObject
            {
                ["processId"] = 101,
                ["status"] = "completed",
                ["campaignDay"] = 42.0,
                ["timeControlMode"] = "Stop",
                ["data"] = new JsonObject
                {
                    ["scope"] = "agenthost-native-battle-autopilot",
                    ["handoffMode"] = "rts-camera-native-ai-initialization",
                    ["controllerBefore"] = "Player",
                    ["controllerAfter"] = "AI",
                    ["isPlayerControlledAfter"] = false,
                    ["isAIControlledAfter"] = true,
                    ["missionMainAgentIndexBefore"] = 34,
                    ["missionMainAgentIndexAfter"] = 34,
                    ["missionMainAgentControllerActiveAfter"] = false,
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
