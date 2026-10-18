using System.Diagnostics;
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal static class AgentHostCaptivityRecoveryLoop
{
    private const string StoryQuestId = "rebuild_player_clan_storymode_quest";
    private const string PrisonerWaitMenu = "prisoner_wait";
    private const string WildernessRansomMenu = "menu_captivity_end_propose_ransom_wilderness";
    private const string PrisonRansomMenu = "menu_captivity_end_propose_ransom_in_prison";
    private const string ReleasedByNoMoreEnemiesMenu = "menu_captivity_end_no_more_enemies";
    private const string CaptivityContinueOption = "mno_continue";
    private static readonly HashSet<string> RansomMenus = new(StringComparer.Ordinal)
    {
        WildernessRansomMenu, PrisonRansomMenu
    };
    private static readonly HashSet<string> CaptivityContinueMenus = new(StringComparer.Ordinal)
    {
        "menu_captivity_end_no_more_enemies", "menu_captivity_end_by_ally_party_saved",
        "menu_captivity_end_by_party_removed", "menu_captivity_end_wilderness_escape",
        "menu_escape_captivity_during_battle", "menu_released_after_battle",
        "menu_captivity_transfer_to_town", "menu_captivity_end_exchanged_with_prisoner",
        "menu_captivity_castle_remain", "menu_captivity_end_prison_escape"
    };

    internal static JsonArray BuildActionCatalog(JsonObject state)
    {
        var catalog = new JsonArray();
        var context = state["context"] as JsonObject;
        var menuId = ReadString(context, "menuId");
        var isCaptive = ReadBoolean(context?["captivity"] as JsonObject, "isCaptive");
        if (!isCaptive && !CaptivityContinueMenus.Contains(menuId ?? string.Empty)) return catalog;

        if (string.Equals(menuId, PrisonerWaitMenu, StringComparison.Ordinal))
        {
            if (GetEnabledOptions(state).Count > 0) return catalog;
            if (string.Equals(ReadString(context, "timeControlMode"), "Stop", StringComparison.Ordinal) &&
                ReadBoolean(context, "isWaitMenu") && ReadBoolean(context, "isWaitActive"))
                catalog.Add(new JsonObject { ["action"] = "resume", ["arguments"] = new JsonArray() });
            return catalog;
        }

        if (RansomMenus.Contains(menuId ?? string.Empty))
        {
            var enabled = GetEnabledOptions(state).Where(option => IsKnownRansomOption(ReadString(option, "id"))).ToArray();
            if (enabled.Length > 0)
            {
                var optionIds = new JsonArray();
                foreach (var option in enabled) optionIds.Add(ReadString(option, "id"));
                catalog.Add(new JsonObject
                {
                    ["action"] = "menuSelect",
                    ["arguments"] = new JsonArray("MenuId", "OptionId"),
                    ["argumentValues"] = new JsonObject { ["MenuId"] = new JsonArray(menuId), ["OptionId"] = optionIds }
                });
            }
        }
        else if (CaptivityContinueMenus.Contains(menuId ?? string.Empty) &&
            GetEnabledOptions(state).Any(option => ReadString(option, "id") == CaptivityContinueOption))
        {
            catalog.Add(new JsonObject
            {
                ["action"] = "menuSelect",
                ["arguments"] = new JsonArray("MenuId", "OptionId"),
                ["argumentValues"] = new JsonObject
                {
                    ["MenuId"] = new JsonArray(menuId),
                    ["OptionId"] = new JsonArray(CaptivityContinueOption)
                }
            });
        }
        return catalog;
    }

    internal static JsonArray BuildControlCatalog(JsonObject state) => IsUsableFreeMap(state) ? new JsonArray("done") : new JsonArray();

    internal static bool ShouldPassivelyWait(JsonObject state)
    {
        var context = state["context"] as JsonObject;
        return ReadBoolean(context?["captivity"] as JsonObject, "isCaptive") &&
            string.Equals(ReadString(context, "menuId"), PrisonerWaitMenu, StringComparison.Ordinal) &&
            GetEnabledOptions(state).Count == 0 &&
            !string.Equals(ReadString(context, "timeControlMode"), "Stop", StringComparison.Ordinal);
    }

    internal static bool IsUsableFreeMap(JsonObject state)
    {
        var context = state["context"] as JsonObject;
        return string.Equals(ReadString(context, "gameState"), "MapState", StringComparison.Ordinal) &&
            ReadBoolean(context?["captivity"] as JsonObject, "isCaptive") != true &&
            string.IsNullOrWhiteSpace(ReadString(context, "menuId")) &&
            !ReadBoolean(context, "escapeMenuOpen") && !ReadBoolean(context, "inquiryOpen") &&
            !ReadBoolean(context, "encounterActive") && context?["battleSimulation"] is null &&
            state["partyScreen"] is null && state["inventoryScreen"] is null;
    }

    internal static IReadOnlyList<object> RunContractSelfTests()
    {
        var stoppedWait = CaptiveState(PrisonerWaitMenu, "Stop", true, true, []);
        var resumeCatalog = BuildActionCatalog(stoppedWait);
        if (resumeCatalog.Count != 1 || ReadString(resumeCatalog[0] as JsonObject, "action") != "resume" || ShouldPassivelyWait(stoppedWait))
            throw new AgentHostException("captivity-recovery-self-test-resume-gate-failed", "A stopped no-option Native wait menu must expose only an explicit resume when its native wait is active.");

        var lockedWait = CaptiveState(PrisonerWaitMenu, "Stop", true, false, []);
        if (BuildActionCatalog(lockedWait).Count != 0 || ShouldPassivelyWait(lockedWait))
            throw new AgentHostException("captivity-recovery-self-test-locked-stop-progress-leaked", "The Host must fail closed when time is stopped and Native does not allow wait controls.");

        var naturalWait = CaptiveState(PrisonerWaitMenu, "UnstoppablePlay", true, true, []);
        if (BuildActionCatalog(naturalWait).Count != 0 || !ShouldPassivelyWait(naturalWait))
            throw new AgentHostException("captivity-recovery-self-test-natural-wait-catalog-failed", "When Native time is already flowing, the Host must observe passively without another clock action.");

        var ransomOptions = new JsonArray
        {
            new JsonObject { ["id"] = "mno_captivity_end_ransom_accept", ["available"] = true, ["enabled"] = true },
            new JsonObject { ["id"] = "captivity_end_ransom_deny", ["available"] = true, ["enabled"] = true },
            new JsonObject { ["id"] = "unrelated", ["available"] = true, ["enabled"] = true },
            new JsonObject { ["id"] = "mno_captivity_end_ransom_accept", ["available"] = true, ["enabled"] = false }
        };
        var ransomCatalog = BuildActionCatalog(CaptiveState(WildernessRansomMenu, "Stop", false, false, ransomOptions));
        var allowedOptions = ransomCatalog[0]?["argumentValues"]?["OptionId"] as JsonArray;
        if (ransomCatalog.Count != 1 || allowedOptions is null || allowedOptions.Count != 2 ||
            !allowedOptions.Any(option => option?.GetValue<string>() == "mno_captivity_end_ransom_accept") ||
            !allowedOptions.Any(option => option?.GetValue<string>() == "captivity_end_ransom_deny") ||
            allowedOptions.Any(option => option?.GetValue<string>() == "unrelated") || !IsUsableFreeMap(FreeMapState()))
            throw new AgentHostException("captivity-recovery-self-test-ransom-catalog-failed", "The Host must offer only current enabled Native wilderness ransom choices and accept a free MapState terminal with zero soldiers.");

        var releaseOptions = new JsonArray
        {
            new JsonObject { ["id"] = CaptivityContinueOption, ["available"] = true, ["enabled"] = true },
            new JsonObject { ["id"] = "unrelated", ["available"] = true, ["enabled"] = true },
            new JsonObject { ["id"] = CaptivityContinueOption, ["available"] = true, ["enabled"] = false }
        };
        var releaseMenuIds = new[]
        {
            "menu_captivity_end_no_more_enemies", "menu_captivity_end_by_ally_party_saved",
            "menu_captivity_end_by_party_removed", "menu_captivity_end_wilderness_escape",
            "menu_escape_captivity_during_battle", "menu_released_after_battle",
            "menu_captivity_transfer_to_town", "menu_captivity_end_exchanged_with_prisoner",
            "menu_captivity_castle_remain", "menu_captivity_end_prison_escape"
        };
        foreach (var releaseMenuId in releaseMenuIds)
        {
            var releaseCatalog = BuildActionCatalog(CaptiveState(releaseMenuId, "Stop", false, false, releaseOptions,
                isCaptive: releaseMenuId != "menu_released_after_battle"));
            var releaseOptionsAllowed = releaseCatalog.Count > 0 ? releaseCatalog[0]?["argumentValues"]?["OptionId"] as JsonArray : null;
            if (releaseCatalog.Count != 1 || releaseOptionsAllowed?.Count != 1 || releaseOptionsAllowed[0]?.GetValue<string>() != CaptivityContinueOption)
                throw new AgentHostException("captivity-recovery-self-test-release-menu-catalog-failed", $"The Host must expose only the source-verified Native Continue option in recognized menu '{releaseMenuId}'.");
        }
        var unrecognizedReleaseCatalog = BuildActionCatalog(CaptiveState("unrecognized_captivity_page", "Stop", false, false, releaseOptions, isCaptive: false));
        if (unrecognizedReleaseCatalog.Count != 0)
            throw new AgentHostException("captivity-recovery-self-test-release-menu-overbroad", "A generic Continue option on an unrecognized page must not become a captivity action.");
        if (!AgentHostDecisionCycle.CaptivityRecoverySystemPrompt.Contains("currently enabled original mno_continue", StringComparison.Ordinal) ||
            !AgentHostDecisionCycle.CaptivityRecoverySystemPrompt.Contains("return to a captive wait menu", StringComparison.Ordinal))
            throw new AgentHostException("captivity-recovery-self-test-release-prompt-failed", "The model prompt must explain the source-verified Native captivity continuation menus in this recovery slice.");

        return [
            new { scenario = "captivity-recovery-explicit-native-resume-is-separated-from-passive-wait", passed = true },
            new { scenario = "captivity-recovery-only-current-ransom-or-native-release-continuation-and-usable-free-map-terminal", passed = true }
        ];
    }

    internal static async Task<IReadOnlyList<object>> RunTransportSelfTestsAsync()
    {
        var native = new FakeNativeClient();
        var provider = new FakeProvider();
        using var request = JsonDocument.Parse("""
            {"runId":"captivity-recovery-selftest","goal":"Recover the currently captive MainHero, then plan one unmet Establish Your Clan objective.","maxDecisions":12,"maxElapsedSeconds":20}
            """);
        var result = await RunAsync(request.RootElement, native, native, native, provider, CancellationToken.None);
        var selected = result["objectiveSelection"] as JsonObject;
        var verification = result["captivityRecoveryVerified"]?.GetValue<bool>() == true;
        var explicitTimeActions = result["explicitTimeActions"] as JsonArray;
        var routes = result["providerRouteHistory"] as JsonArray;
        if (ReadString(result, "status") != "completed" ||
            ReadString(result, "resultKind") != "captivity-recovered-objective-plan" ||
            !verification || ReadBoolean((result["termination"] as JsonObject), "goalVerified") ||
            ReadString(selected, "objectiveId") != "gold" || native.ResumeCount != 1 || native.RansomChoiceCount != 1 || native.ReleaseContinueCount != 1 ||
            native.QuestDetailsCount != 1 || provider.CallCount != 5 || routes?.Count != 5 ||
            result["gameplayActionsExecuted"]?.GetValue<int>() != 3 || explicitTimeActions?.Count != 1 ||
            explicitTimeActions[0]?.GetValue<string>() != "resume" ||
            !native.RecoveryActionOrder.SequenceEqual(new[] { "resume", "captivity_end_ransom_deny", CaptivityContinueOption }, StringComparer.Ordinal))
            throw new AgentHostException("captivity-recovery-runtime-self-test-failed", "The Host failed to use explicit resume, current Native ransom and release-menu choices, verified free MapState, and original Quest replanning without a battle.");
        return [
            new { scenario = "captivity-recovery-host-resumes-explicitly-then-passively-observes-and-selects-current-ransom-or-release-menu", passed = true },
            new { scenario = "captivity-recovery-replans-active-establish-clan-without-claiming-quest-completion", passed = true }
        ];
    }

    internal static async Task<JsonObject> RunAsync(
        JsonElement request,
        IAgentHostCampaignNativeClient stateClient,
        IAgentHostCaptivityRecoveryNativeClient actionClient,
        IAgentHostQuestDetailsNativeClient questDetailsClient,
        IAgentHostDecisionProvider provider,
        CancellationToken cancellationToken,
        int priorDecisions = 0,
        long priorPromptTokens = 0,
        long priorCompletionTokens = 0,
        JsonArray? priorTrace = null,
        JsonArray? priorProviderRouteHistory = null)
    {
        var runId = ReadString(request, "runId") ?? Guid.NewGuid().ToString("N");
        var maxDecisions = Math.Clamp(ReadInt(request, "maxDecisions", 80), 1, 160);
        var maxElapsedSeconds = Math.Clamp(ReadInt(request, "maxElapsedSeconds", 7200), 5, 7200);
        using var elapsed = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        elapsed.CancelAfter(TimeSpan.FromSeconds(maxElapsedSeconds));

        var trace = priorTrace?.DeepClone() as JsonArray ?? new JsonArray();
        var routes = priorProviderRouteHistory?.DeepClone() as JsonArray ?? new JsonArray();
        var decisions = priorDecisions;
        var actionCount = 0;
        var passiveWaitCount = 0;
        string? captivityChoiceOptionId = null;
        JsonObject? previousReceipt = null;
        var explicitTimeActions = new JsonArray();
        using var initialDocument = await stateClient.ReadStateAsync(elapsed.Token);
        var initialNative = ParseObject(initialDocument.RootElement);
        var initialState = initialNative["state"] as JsonObject ?? new JsonObject();
        if (ReadString(initialState["storyModeEstablishClanStatus"] as JsonObject, "status") != "active" ||
            ReadBoolean((initialState["context"] as JsonObject)?["captivity"] as JsonObject, "isCaptive") != true)
            throw new AgentHostException("captivity-recovery-storymode-precondition-missing", "W7-O requires the exact active StoryMode Establish Your Clan quest and an already captive MainHero before any model decision.");
        var initialDay = ReadDouble(initialNative, "campaignDay", double.NaN);
        var initialMode = ReadString(initialState["context"] as JsonObject, "timeControlMode");
        var current = initialNative.DeepClone() as JsonObject ?? throw new AgentHostException("captivity-recovery-observation-invalid", "The initial Native state could not be cloned.");

        for (var loopIndex = 1; decisions - priorDecisions < maxDecisions; loopIndex++)
        {
            elapsed.Token.ThrowIfCancellationRequested();
            var state = current["state"] as JsonObject ?? throw new AgentHostException("captivity-recovery-state-missing", "Native returned no current Campaign state.");
            if (IsUsableFreeMap(state))
            {
                var terminalObservation = BuildObservation(current, state);
                var terminalRequest = BuildRequest(runId, ReadString(request, "goal"), terminalObservation, previousReceipt,
                    new JsonArray(), new JsonArray("done"), decisions + 1);
                var terminalDecision = await AgentHostDecisionCycle.DecideCaptivityRecoveryAsync(provider, terminalRequest, elapsed.Token);
                decisions++;
                AddRoute(routes, provider, terminalDecision, decisions, ref priorPromptTokens, ref priorCompletionTokens);
                if (ReadBoolean(terminalDecision.Decision, "done") != true)
                    throw new AgentHostException("captivity-recovery-completion-not-confirmed", "Only Native-verified free Campaign Map state may offer done for captivity recovery.");
                trace.Add(BuildTrace(decisions, terminalObservation, terminalDecision.Decision, null, new JsonArray("done")));

                var objectivePlan = await AgentHostEstablishYourClanGoalLoop.RunAsync(
                    request, stateClient, questDetailsClient, provider, elapsed.Token,
                    priorDecisions: decisions,
                    priorPromptTokens: priorPromptTokens,
                    priorCompletionTokens: priorCompletionTokens,
                    priorTrace: trace,
                    priorProviderRouteHistory: routes);
                return new JsonObject
                {
                    ["status"] = ReadString(objectivePlan, "status"),
                    ["resultKind"] = "captivity-recovered-objective-plan",
                    ["providerModelId"] = provider.ModelId,
                    ["providerConfigurationSource"] = provider.ConfigurationSource,
                    ["decisions"] = ReadInt(objectivePlan, "decisions", decisions),
                    ["actionsExecuted"] = actionCount + ReadInt(objectivePlan, "actionsExecuted", 0),
                    ["gameplayActionsExecuted"] = actionCount,
                    ["explicitTimeActions"] = explicitTimeActions.DeepClone(),
                    ["promptTokens"] = ReadLong(objectivePlan, "promptTokens", priorPromptTokens),
                    ["completionTokens"] = ReadLong(objectivePlan, "completionTokens", priorCompletionTokens),
                    ["providerRouteHistory"] = objectivePlan["providerRouteHistory"]?.DeepClone() ?? routes.DeepClone(),
                    ["captivityRecoveryVerified"] = true,
                    ["captivityChoiceOptionId"] = captivityChoiceOptionId,
                    ["passiveCaptivityPollCount"] = passiveWaitCount,
                    ["initialTimeControlMode"] = initialMode,
                    ["finalTimeControlMode"] = ReadString(state["context"] as JsonObject, "timeControlMode"),
                    ["campaignDayStart"] = double.IsFinite(initialDay) ? JsonValue.Create(initialDay) : null,
                    ["campaignDayEnd"] = current["campaignDay"]?.DeepClone(),
                    ["initialNativeState"] = initialNative.DeepClone(),
                    ["finalNativeState"] = current.DeepClone(),
                    ["initialStoryModeEstablishClanStatus"] = initialState["storyModeEstablishClanStatus"]?.DeepClone(),
                    ["objectiveSelection"] = objectivePlan["selection"]?.DeepClone(),
                    ["objectiveSnapshot"] = objectivePlan["objectiveSnapshot"]?.DeepClone(),
                    ["journalObjectiveSnapshot"] = objectivePlan["journalObjectiveSnapshot"]?.DeepClone(),
                    ["targetConsistency"] = objectivePlan["targetConsistency"]?.DeepClone(),
                    ["liveMetricDifferences"] = objectivePlan["liveMetricDifferences"]?.DeepClone(),
                    ["termination"] = new JsonObject { ["reason"] = "captivity-recovered-and-objective-replanned", ["completedByProvider"] = true, ["goalVerified"] = false },
                    ["trace"] = objectivePlan["trace"]?.DeepClone()
                };
            }

            if (ShouldPassivelyWait(state))
            {
                var beforeDay = ReadDouble(current, "campaignDay", double.NaN);
                var beforeContext = state["context"] as JsonObject;
                await Task.Delay(TimeSpan.FromSeconds(2), elapsed.Token);
                using var nextDocument = await stateClient.ReadStateAsync(elapsed.Token);
                current = ParseObject(nextDocument.RootElement);
                passiveWaitCount++;
                trace.Add(new JsonObject
                {
                    ["iteration"] = decisions,
                    ["passiveCaptivityWait"] = true,
                    ["waitSeconds"] = 2,
                    ["menuBefore"] = ReadString(beforeContext, "menuId"),
                    ["menuAfter"] = ReadString(current["state"]?["context"] as JsonObject, "menuId"),
                    ["timeControlModeBefore"] = ReadString(beforeContext, "timeControlMode"),
                    ["timeControlModeAfter"] = ReadString(current["state"]?["context"] as JsonObject, "timeControlMode"),
                    ["campaignDayBefore"] = double.IsFinite(beforeDay) ? JsonValue.Create(beforeDay) : null,
                    ["campaignDayAfter"] = current["campaignDay"]?.DeepClone(),
                    ["isCaptiveAfter"] = ReadBoolean((current["state"]?["context"]?["captivity"] as JsonObject), "isCaptive")
                });
                continue;
            }

            var actionCatalog = BuildActionCatalog(state);
            var controls = BuildControlCatalog(state);
            if (actionCatalog.Count == 0 && controls.Count == 0)
            {
                var context = state["context"] as JsonObject;
                var optionIds = string.Join(",", GetEnabledOptions(state).Select(option => ReadString(option, "id") ?? "<missing-id>"));
                throw new AgentHostException("captivity-recovery-current-menu-unsupported",
                    $"No supported Native captivity action is available: menuId={ReadString(context, "menuId") ?? "<none>"}; captivityMenuId={ReadString(context?["captivity"] as JsonObject, "currentMenuId") ?? "<none>"}; time={ReadString(context, "timeControlMode") ?? "<none>"}; isWaitMenu={ReadBoolean(context, "isWaitMenu")}; isWaitActive={ReadBoolean(context, "isWaitActive")}; enabledOptionIds=[{optionIds}].");
            }
            var observation = BuildObservation(current, state);
            var modelRequest = BuildRequest(runId, ReadString(request, "goal"), observation, previousReceipt, actionCatalog, controls, decisions + 1);
            var result = await AgentHostDecisionCycle.DecideCaptivityRecoveryAsync(provider, modelRequest, elapsed.Token);
            decisions++;
            AddRoute(routes, provider, result, decisions, ref priorPromptTokens, ref priorCompletionTokens);
            if (!TryResolveAction(result.Decision, actionCatalog, state, out var action, out var arguments, out var rejection))
                throw new AgentHostException("captivity-recovery-decision-invalid", rejection ?? "The model did not choose a currently allowed Native captivity action.");

            var beforeReceipt = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
            using var actionDocument = await actionClient.ExecuteCaptivityRecoveryActionAsync(action!, arguments!, elapsed.Token);
            var receipt = JsonNode.Parse(actionDocument.RootElement.GetRawText())?.AsObject()
                ?? throw new AgentHostException("captivity-recovery-native-receipt-invalid", "Native returned no recovery action receipt.");
            actionCount++;
            if (action == "resume") explicitTimeActions.Add("resume");
            if (action == "menuSelect") captivityChoiceOptionId = ReadString(arguments, "optionId");
            using var afterDocument = await stateClient.ReadStateAsync(elapsed.Token);
            current = ParseObject(afterDocument.RootElement);
            var receiptWithTiming = new JsonObject
            {
                ["action"] = action,
                ["status"] = ReadString(receipt, "status"),
                ["campaignDay"] = receipt["campaignDay"]?.DeepClone(),
                ["timeControlMode"] = receipt["timeControlMode"]?.DeepClone(),
                ["timing"] = new JsonObject { ["actionStartedUtc"] = beforeReceipt, ["actionCompletedUtc"] = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture) }
            };
            previousReceipt = receiptWithTiming.DeepClone() as JsonObject;
            trace.Add(BuildTrace(decisions, observation, result.Decision, receiptWithTiming, actionCatalog));
        }

        throw new AgentHostException("captivity-recovery-budget-exhausted", "The bounded Native Captivity loop did not regain a usable Campaign Map before the elapsed/decision budget.");
    }

    private static bool TryResolveAction(JsonObject decision, JsonArray catalog, JsonObject state,
        out string? action, out JsonObject? arguments, out string? rejection)
    {
        action = ReadString(decision, "action");
        arguments = null;
        rejection = null;
        var requestedAction = action;
        var allowed = requestedAction == null ? null : catalog.OfType<JsonObject>().FirstOrDefault(candidate => ReadString(candidate, "action") == requestedAction);
        if (allowed == null || decision["arguments"] is not JsonObject supplied)
        {
            rejection = "Decision must use one action and exact arguments from the current Native captivity catalog.";
            return false;
        }
        var names = (allowed["arguments"] as JsonArray)?.Select(item => item?.GetValue<string>()).Where(name => name != null).Select(name => name!).ToArray() ?? Array.Empty<string>();
        if (names.Length != supplied.Count || names.Any(name => !supplied.ContainsKey(name)))
        {
            rejection = "The action arguments do not match the current Native captivity catalog.";
            return false;
        }
        if (action == "resume")
        {
            var context = state["context"] as JsonObject;
            if (ReadBoolean((context?["captivity"] as JsonObject), "isCaptive") != true ||
                ReadString(context, "menuId") != PrisonerWaitMenu || ReadString(context, "timeControlMode") != "Stop" ||
                !ReadBoolean(context, "isWaitMenu") || !ReadBoolean(context, "isWaitActive") || GetEnabledOptions(state).Count != 0)
            {
                rejection = "resume is allowed only for a stopped no-option prisoner_wait whose Native Wait menu is active.";
                return false;
            }
            arguments = new JsonObject();
            return true;
        }
        if (action == "menuSelect")
        {
            var context = state["context"] as JsonObject;
            var menuId = ReadString(supplied, "MenuId");
            var optionId = ReadString(supplied, "OptionId");
            var menuValues = allowed["argumentValues"]?["MenuId"] as JsonArray;
            var optionValues = allowed["argumentValues"]?["OptionId"] as JsonArray;
            var captivity = context?["captivity"] as JsonObject;
            var currentMenuId = ReadString(captivity, "currentMenuId") ?? ReadString(context, "menuId");
            var isRansomChoice = ReadBoolean(captivity, "isCaptive") && RansomMenus.Contains(currentMenuId ?? string.Empty) && IsKnownRansomOption(optionId);
            var isVerifiedContinue = CaptivityContinueMenus.Contains(currentMenuId ?? string.Empty) && optionId == CaptivityContinueOption;
            if ((!isRansomChoice && !isVerifiedContinue) ||
                menuId != ReadString(context, "menuId") || menuValues?.Any(value => value?.GetValue<string>() == menuId) != true ||
                optionValues?.Any(value => value?.GetValue<string>() == optionId) != true ||
                !GetEnabledOptions(state).Any(option => ReadString(option, "id") == optionId))
            {
                rejection = "Only a currently enabled Native ransom choice or source-verified captivity-release continuation may be selected from its current menu.";
                return false;
            }
            arguments = new JsonObject { ["menuId"] = menuId, ["optionId"] = optionId };
            return true;
        }
        rejection = "The requested action is unsupported in this Captivity slice.";
        return false;
    }

    private static JsonObject BuildObservation(JsonObject native, JsonObject state) => new()
    {
        ["status"] = ReadString(native, "status"),
        ["campaignDay"] = native["campaignDay"]?.DeepClone(),
        ["dailyTickCount"] = native["dailyTickCount"]?.DeepClone(),
        ["timeControlMode"] = native["timeControlMode"]?.DeepClone(),
        ["state"] = state.DeepClone()
    };

    private static JsonObject BuildRequest(string runId, string? goal, JsonObject observation, JsonObject? previousReceipt,
        JsonArray actions, JsonArray controls, int iteration) => new()
    {
        ["runId"] = runId,
        ["goal"] = goal,
        ["goalScopeContract"] = "native-current-captivity-recovery-v1",
        ["goalScopeClassificationRequired"] = false,
        ["iteration"] = iteration,
        ["observation"] = observation.DeepClone(),
        ["previousActionReceipt"] = previousReceipt?.DeepClone(),
        ["decisionFeedback"] = null,
        ["allowedActions"] = actions.DeepClone(),
        ["allowedControls"] = controls.DeepClone()
    };

    private static JsonObject BuildTrace(int iteration, JsonObject observation, JsonObject decision, JsonObject? receipt, JsonArray catalog) => new()
    {
        ["iteration"] = iteration,
        ["observationBefore"] = observation.DeepClone(),
        ["decision"] = decision.DeepClone(),
        ["actionCatalog"] = catalog.DeepClone(),
        ["actionAttempted"] = receipt != null,
        ["actionExecuted"] = receipt != null && ReadString(receipt, "status") is "accepted" or "completed",
        ["actionReceipt"] = receipt?.DeepClone()
    };

    private static void AddRoute(JsonArray routes, IAgentHostDecisionProvider provider, ProviderDecisionResult result, int decision,
        ref long promptTokens, ref long completionTokens)
    {
        if (result.PromptTokens.HasValue) promptTokens += result.PromptTokens.Value;
        if (result.CompletionTokens.HasValue) completionTokens += result.CompletionTokens.Value;
        routes.Add(new JsonObject
        {
            ["decision"] = decision,
            ["requestedModelId"] = provider.ModelId,
            ["responseModelId"] = result.ModelId,
            ["routedVia"] = result.RoutedVia,
            ["responseFormatMode"] = result.ResponseFormatMode,
            ["promptTokens"] = result.PromptTokens,
            ["completionTokens"] = result.CompletionTokens
        });
    }

    private static IReadOnlyList<JsonObject> GetEnabledOptions(JsonObject state) =>
        (state["availableMenuOptions"] as JsonArray)?.OfType<JsonObject>()
            .Where(option => ReadBoolean(option, "available") && ReadBoolean(option, "enabled")).ToArray() ?? Array.Empty<JsonObject>();

    private static bool IsKnownRansomOption(string? optionId) => optionId is "mno_captivity_end_ransom_accept" or "captivity_end_ransom_deny";

    private static JsonObject ParseObject(JsonElement element) => JsonNode.Parse(element.GetRawText())?.AsObject()
        ?? throw new AgentHostException("native-response-invalid", "Native returned no Campaign state object.");

    private static JsonObject CaptiveState(string menuId, string timeMode, bool isWaitMenu, bool isWaitActive, JsonArray options, bool isCaptive = true) => new()
    {
        ["context"] = new JsonObject
        {
            ["gameState"] = "MapState", ["menuId"] = menuId, ["timeControlMode"] = timeMode,
            ["isWaitMenu"] = isWaitMenu, ["isWaitActive"] = isWaitActive,
            ["captivity"] = isCaptive ? new JsonObject { ["isCaptive"] = true, ["currentMenuId"] = menuId, ["ransomOfferVisible"] = RansomMenus.Contains(menuId), ["currentVisibleRansomAmount"] = RansomMenus.Contains(menuId) ? 100 : null } : null
        },
        ["availableMenuOptions"] = options.DeepClone()
    };

    private static JsonObject FreeMapState() => new()
    {
        ["context"] = new JsonObject { ["gameState"] = "MapState", ["menuId"] = null, ["captivity"] = null, ["encounterActive"] = false, ["escapeMenuOpen"] = false, ["inquiryOpen"] = false, ["battleSimulation"] = null },
        ["party"] = new JsonObject { ["members"] = 0 }, ["partyScreen"] = null, ["inventoryScreen"] = null
    };

    private static JsonObject StoryQuestState(JsonObject context) => new()
    {
        ["storyModeEstablishClanStatus"] = new JsonObject { ["status"] = "active" },
        ["context"] = context,
        ["party"] = new JsonObject { ["members"] = 0 },
        ["economy"] = new JsonObject { ["gold"] = 32, ["renown"] = 5 },
        ["quests"] = new JsonArray(new JsonObject { ["id"] = StoryQuestId, ["title"] = "Establish Your Clan" }),
        ["partyScreen"] = null, ["inventoryScreen"] = null
    };

    private static JsonObject BuildFakeNative(string menuId, string timeMode, bool captive, bool waitActive,
        JsonArray? options = null, bool isStoryQuestActive = true)
    {
        var state = StoryQuestState(new JsonObject
        {
            ["gameState"] = "MapState", ["menuId"] = menuId, ["timeControlMode"] = timeMode,
            ["isWaitMenu"] = menuId == PrisonerWaitMenu, ["isWaitActive"] = waitActive,
            ["captivity"] = captive ? new JsonObject { ["isCaptive"] = true, ["currentMenuId"] = menuId, ["ransomOfferVisible"] = menuId == WildernessRansomMenu, ["currentVisibleRansomAmount"] = menuId == WildernessRansomMenu ? 20 : null } : null,
            ["encounterActive"] = false, ["escapeMenuOpen"] = false, ["inquiryOpen"] = false, ["battleSimulation"] = null
        });
        if (options is not null) state["availableMenuOptions"] = options.DeepClone();
        if (!isStoryQuestActive)
        {
            state["storyModeEstablishClanStatus"]!["status"] = "storymode-not-activated";
            state["quests"] = new JsonArray();
        }
        return new JsonObject
        {
            ["status"] = "completed", ["processId"] = 321, ["nativeSessionId"] = "captivity-selftest-session",
            ["campaignDay"] = 91080.216, ["dailyTickCount"] = 100, ["timeControlMode"] = timeMode, ["state"] = state
        };
    }

    private static JsonDocument ToDocument(JsonObject value) => JsonDocument.Parse(value.ToJsonString());
    private static string? ReadString(JsonElement value, string key) => value.ValueKind == JsonValueKind.Object && value.TryGetProperty(key, out var property) && property.ValueKind == JsonValueKind.String ? property.GetString() : null;
    private static string? ReadString(JsonObject? value, string key) => value?[key] is JsonValue node && node.TryGetValue<string>(out var result) ? result : null;
    private static int ReadInt(JsonElement element, string key, int fallback) => element.ValueKind == JsonValueKind.Object && element.TryGetProperty(key, out var value) && value.TryGetInt32(out var number) ? number : fallback;
    private static int ReadInt(JsonObject? value, string key, int fallback) => value?[key] is JsonValue node && node.TryGetValue<int>(out var number) ? number : fallback;
    private static long ReadLong(JsonObject value, string key, long fallback) => value[key] is JsonValue node && node.TryGetValue<long>(out var number) ? number : fallback;
    private static double ReadDouble(JsonObject? value, string key, double fallback) => value?[key] is JsonValue node && node.TryGetValue<double>(out var result) ? result : fallback;
    private static bool ReadBoolean(JsonObject? value, string key) => value?[key] is JsonValue node && node.TryGetValue<bool>(out var result) && result;

    private sealed class FakeNativeClient : IAgentHostCampaignNativeClient, IAgentHostCaptivityRecoveryNativeClient, IAgentHostQuestDetailsNativeClient
    {
        private readonly Queue<JsonObject> _states = new(new[]
        {
            BuildFakeNative(PrisonerWaitMenu, "Stop", captive: true, waitActive: true),
            BuildFakeNative(PrisonerWaitMenu, "UnstoppablePlay", captive: true, waitActive: true),
            BuildFakeNative(WildernessRansomMenu, "Stop", captive: true, waitActive: false, new JsonArray(
                new JsonObject { ["id"] = "mno_captivity_end_ransom_accept", ["available"] = true, ["enabled"] = true },
                new JsonObject { ["id"] = "captivity_end_ransom_deny", ["available"] = true, ["enabled"] = true })),
            BuildFakeNative("menu_released_after_battle", "Stop", captive: false, waitActive: false, new JsonArray(
                new JsonObject { ["id"] = CaptivityContinueOption, ["available"] = true, ["enabled"] = true })),
            BuildFakeNative(string.Empty, "Stop", captive: false, waitActive: false),
            BuildFakeNative(string.Empty, "Stop", captive: false, waitActive: false)
        });

        internal int ResumeCount { get; private set; }
        internal int RansomChoiceCount { get; private set; }
        internal int ReleaseContinueCount { get; private set; }
        internal int QuestDetailsCount { get; private set; }
        internal List<string> RecoveryActionOrder { get; } = new();

        public Task<JsonDocument> ReadStateAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var state = _states.Count > 1 ? _states.Dequeue() : _states.Peek();
            return Task.FromResult(ToDocument(state));
        }

        public Task<JsonDocument> ExecuteCampaignActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken) =>
            throw new AgentHostException("captivity-selftest-generic-campaign-action", "Captivity recovery must not use the generic Campaign action transport.");

        public Task<JsonDocument> ExecuteCaptivityRecoveryActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (action == "resume" && arguments.Count == 0)
            {
                ResumeCount++;
                RecoveryActionOrder.Add(action);
                return Task.FromResult(ToDocument(new JsonObject { ["status"] = "completed", ["action"] = action, ["campaignDay"] = 91080.216, ["timeControlMode"] = "UnstoppablePlay" }));
            }
            if (action == "menuSelect" && ReadString(arguments, "menuId") == WildernessRansomMenu && ReadString(arguments, "optionId") == "captivity_end_ransom_deny")
            {
                RansomChoiceCount++;
                RecoveryActionOrder.Add(ReadString(arguments, "optionId")!);
                return Task.FromResult(ToDocument(new JsonObject { ["status"] = "completed", ["action"] = action, ["campaignDay"] = 91080.220, ["timeControlMode"] = "UnstoppableFastForward" }));
            }
            if (action == "menuSelect" && CaptivityContinueMenus.Contains(ReadString(arguments, "menuId") ?? string.Empty) && ReadString(arguments, "optionId") == CaptivityContinueOption)
            {
                ReleaseContinueCount++;
                RecoveryActionOrder.Add(CaptivityContinueOption);
                return Task.FromResult(ToDocument(new JsonObject { ["status"] = "completed", ["action"] = action, ["campaignDay"] = 91080.221, ["timeControlMode"] = "Stop" }));
            }
            throw new AgentHostException("captivity-selftest-unlisted-action", "The fake Native boundary saw an unlisted Captivity action.");
        }

        public Task<JsonDocument> ReadQuestDetailsAsync(string questId, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (questId != StoryQuestId) throw new AgentHostException("captivity-selftest-wrong-quest-details", "The planner requested the wrong quest journal.");
            QuestDetailsCount++;
            var snapshot = new JsonObject
            {
                ["questId"] = StoryQuestId,
                ["gold"] = new JsonObject { ["current"] = 32, ["target"] = 2000, ["met"] = false },
                ["partySize"] = new JsonObject { ["current"] = 0, ["target"] = 25, ["met"] = false },
                ["renown"] = new JsonObject { ["current"] = 5, ["target"] = 50, ["met"] = false },
                ["companions"] = new JsonObject { ["current"] = 1, ["target"] = 1, ["met"] = true }
            };
            var stages = new JsonArray(
                new JsonObject { ["hasTask"] = true, ["currentProgress"] = 32, ["targetProgress"] = 2000, ["description"] = "Increase denars" },
                new JsonObject { ["hasTask"] = true, ["currentProgress"] = 0, ["targetProgress"] = 25, ["description"] = "Grow your party" },
                new JsonObject { ["hasTask"] = true, ["currentProgress"] = 5, ["targetProgress"] = 50, ["description"] = "Reach Clan Tier 1" },
                new JsonObject { ["hasTask"] = true, ["currentProgress"] = 1, ["targetProgress"] = 1, ["description"] = "Hire a companion" });
            var data = new JsonObject { ["questId"] = StoryQuestId, ["title"] = "Establish Your Clan", ["journalStages"] = stages, ["storyModeEstablishClan"] = snapshot };
            return Task.FromResult(ToDocument(new JsonObject { ["status"] = "completed", ["data"] = data }));
        }
    }

    private sealed class FakeProvider : IAgentHostDecisionProvider
    {
        internal int CallCount { get; private set; }
        public string ModelId => "deterministic-captivity-selftest";
        public string ConfigurationSource => "harness-fake-provider";
        public Task CheckConfiguredModelAsync(CancellationToken cancellationToken) => Task.CompletedTask;
        public Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            CallCount++;
            var allowed = request.GetProperty("allowedActions").EnumerateArray().Select(item => item.GetProperty("action").GetString()).ToArray();
            var requestNode = JsonNode.Parse(request.GetRawText())?.AsObject();
            var currentMenuId = ReadString(requestNode?["observation"]?["state"]?["context"] as JsonObject, "menuId");
            JsonObject decision = allowed.Contains("resume", StringComparer.Ordinal)
                ? new JsonObject { ["action"] = "resume", ["arguments"] = new JsonObject(), ["rationale"] = "Use current native wait control." }
                : allowed.Contains("menuSelect", StringComparer.Ordinal)
                    ? new JsonObject { ["action"] = "menuSelect", ["arguments"] = new JsonObject { ["MenuId"] = currentMenuId, ["OptionId"] = CaptivityContinueMenus.Contains(currentMenuId ?? string.Empty) ? CaptivityContinueOption : "captivity_end_ransom_deny" }, ["rationale"] = "Choose the currently enabled Native captivity option." }
                    : request.GetProperty("allowedControls").EnumerateArray().Any(item => item.GetString() == "done")
                        ? new JsonObject { ["done"] = true, ["reason"] = "Native confirms the hero is free." }
                        : ReadString(JsonNode.Parse(request.GetRawText())?.AsObject(), "goalKind") == "active-storymode-establish-your-clan-objective-selection"
                            ? new JsonObject { ["action"] = "selectEstablishYourClanObjective", ["arguments"] = new JsonObject { ["ObjectiveId"] = "gold" }, ["rationale"] = "Select a currently unmet objective." }
                            : throw new AgentHostException("captivity-selftest-provider-sequence-invalid", "The planner requested an unexpected Native action catalog.");
            return Task.FromResult(new ProviderDecisionResult("completed", ModelId, 1, 1, "selftest", decision));
        }
        public void Dispose() { }
    }
}
