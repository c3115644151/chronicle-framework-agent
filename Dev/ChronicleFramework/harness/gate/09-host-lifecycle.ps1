#Requires -Version 7.0

# Host lifecycle: bounded map Host goal classification and Establish Your Clan planner gating.
# Sources asserted here: Test-AgentHostLifecycleEvaluation.ps1, AgentHostRuntimeController.cs

$agentHostLifecycleHarness = Get-Content (Join-Path $stageRoot 'Test-AgentHostLifecycleEvaluation.ps1') -Raw -Encoding UTF8
$agentHostRuntimeControllerSource = Get-Content (Join-Path $modRoot 'AgentHostRuntimeController.cs') -Raw -Encoding UTF8
if ($agentHostLifecycleHarness -notmatch "'UnsupportedGoal'" -or
    $agentHostCampaignLoopSource -notmatch 'BuildGoalScopeClassificationControls' -or
    $agentHostCampaignLoopSource -notmatch 'native-campaign-goal-classification-v1' -or
    $agentHostCampaignLoopSource -notmatch 'No goal-specific game action has run yet' -or
    $agentHostCampaignLoopSource -notmatch 'campaign-goal-unsupported' -or
    $agentHostDecisionCycleSource -notmatch 'CampaignGoalClassificationPrompt' -or
    $agentHostDecisionCycleSource -notmatch 'The goal may be written in Chinese' -or
    $agentHostDecisionCycleSource -notmatch 'Classification tests supported goal type only' -or
    $agentHostDecisionCycleSource -notmatch 'VillageNeedsToolsIssue \(村庄工具委托\)' -or
    $agentHostDecisionCycleSource -notmatch 'Use unsupportedGoal for any requested final outcome' -or
    $agentHostProviderSelfTestSource -notmatch 'provider-goal-classification-scope-catalog-mismatch' -or
    $agentHostProviderSource -notmatch 'supportedMapArrivalGoal' -or
    $agentHostRuntimeControllerSource -notmatch 'campaign-goal-unsupported') {
    throw 'The bounded map Host must classify the complete user goal before offering Native actions and safely report unsupported objectives.'
}
if ($agentHostCampaignLoopSource -notmatch 'supportedEstablishYourClanGoal' -or
    $agentHostProviderSource -notmatch 'supportedEstablishYourClanGoal' -or
    $agentObserverSource -notmatch 'storyModeEstablishClanStatus' -or
    $agentObserverSource -notmatch 'JournalLogEntry' -or
    $agentObserverSource -notmatch 'bESRdcRo' -or
    $agentObserverSource -notmatch 'IsEndedUnsuccessfully' -or
    $storyModeLifecycleStatusSource -notmatch '"not-storymode"' -or
    $storyModeLifecycleStatusSource -notmatch '"storymode-not-activated"' -or
    $storyModeLifecycleStatusSource -notmatch '"completed"' -or
    $storyModeLifecycleStatusSource -notmatch '"failed"' -or
    $agentHostProviderSelfTestSource -notmatch 'StoryModeEstablishClanLifecycleStatus\.RunContractSelfTests' -or
    $agentHostEstablishClanPlannerSource -notmatch 'BuildObjectiveActionCatalog' -or
    $agentHostEstablishClanPlannerSource -notmatch 'questDetailsClient\.ReadQuestDetailsAsync' -or
    $agentHostEstablishClanPlannerSource -notmatch '\["observation"\] = new JsonObject' -or
    $agentHostDecisionCycleSource -notmatch 'IAgentHostQuestDetailsNativeClient' -or
    $agentHostCampaignLoopSource -notmatch 'IAgentHostQuestDetailsNativeClient' -or
    $agentHostMailboxSource -notmatch 'BuildQuestDetailsArguments' -or
    $agentHostEstablishClanPlannerSource -notmatch 'BuildObjectiveSnapshot' -or
    $agentHostEstablishClanPlannerSource -notmatch 'FindLiveMetricDifferences' -or
    $agentHostEstablishClanPlannerSource -notmatch 'liveMetricDifferences' -or
    $agentHostEstablishClanPlannerSource -notmatch 'selectEstablishYourClanObjective' -or
    $agentHostEstablishClanPlannerSource -notmatch 'resultKind.*objective-plan' -or
    $agentHostEstablishClanPlannerSource -notmatch 'providerConfigurationSource' -or
    $agentHostEstablishClanPlannerSource -notmatch 'goalVerified.*false' -or
    $agentHostDecisionCycleSource -notmatch 'BuildEstablishYourClanGoalPlannerPrompt' -or
    $agentHostDecisionCycleSource -notmatch 'JournalLog current/target values' -or
    $agentHostDecisionCycleSource -notmatch 'nativeProgressionContext.partySizeLimit' -or
    $agentHostDecisionCycleSource -notmatch 'If Journal target exceeds the limit and Renown is listed' -or
    $agentHostDecisionCycleSource -notmatch 'temporary over-limit troops can desert' -or
    $agentHostEstablishClanPlannerSource -notmatch 'establish-clan-planner-only-includes-current-objective-contracts' -or
    $agentHostEstablishClanPlannerSource -notmatch 'BuildNativeProgressionContext' -or
    $agentHostEstablishClanAutonomySource -notmatch 'observedNativeState: JsonNode.Parse\(current.RootElement.GetRawText\(\)\)' -or
    $agentHostProviderSource -notmatch 'supported-establish-your-clan') {
    throw 'The Establish Your Clan planner must be gated by the active original quest, use the four official JournalLog values as tracked progress, retain live metric differences diagnostically, allow only unmet Journal objectives, and never claim gameplay completion.'
}
if ($harnessScript -notmatch "'AgentHostLifecycleEvaluation' \{ @\('Preflight', 'Build', 'Smoke', 'AgentHostPackage', 'AgentHostLifecycleEvaluation'\) \}" -or
    $harnessScript -match "'All' \{[^\r\n]*'AgentHostLifecycleEvaluation'" -or
    $agentHostLifecycleHarness -notmatch 'agent-host-lifecycle-test' -or $agentHostLifecycleHarness -notmatch 'AgentBridgeLifecycle' -or
    $agentHostLifecycleHarness -notmatch 'NativeGoalActions' -or $agentHostLifecycleHarness -notmatch 'NativeHandshakeVerified' -or
    $agentHostLifecycleHarness -notmatch 'CHRONICLE_HARNESS_AGENT_NO_MODEL' -or $agentHostLifecycleHarness -notmatch 'CliSessionCleaned' -or
    $agentHostLifecycleHarness -notmatch 'NativeSessionGuardVerified' -or $agentCliSource -notmatch 'ExpectedNativeSessionId' -or
    $agentHostLifecycleHarness -notmatch 'StartupRejectionCases' -or $agentHostLifecycleHarness -notmatch 'DuplicateStartVerified' -or
    $agentHostRuntimeControllerSource -notmatch 'ProbeHarnessStartRejections' -or
    $agentHostProgramSource -notmatch 'IsAuthorizedLifecycleNoModelMode' -or $agentHostProgramSource -notmatch 'LifecycleIdleDecisionProvider' -or
    $agentHostRuntimeControllerSource -notmatch 'AgentHostReadyProtocol\.TryParse' -or
    $agentHostProgramSource -notmatch 'AgentHostReadyProtocol\.Format' -or
    $agentHostRuntimeControllerSource -notmatch 'ReadLineAsync\(\)\.ConfigureAwait\(false\)' -or
    $agentHostRuntimeControllerSource -notmatch '!_hostOutput\.IsCompleted' -or
    $subModuleSource -notmatch 'Instance\?\.StartAgent\?\.Invoke\(\)' -or
    $agentHostRuntimeControllerSource -notmatch 'Instance\?\.StopAgent' -or
    $agentHostRuntimeControllerSource -notmatch 'TryPrepareForAgentStart\(\)' -or
    $agentHostRuntimeControllerSource -notmatch 'ShouldOwnPlayerInput' -or
    $agentHostRuntimeControllerSource -notmatch 'agent-host-process-exit-observed' -or
    $agentPlayerInputOwnershipSource -notmatch 'ScreenManager\.AddGlobalLayer' -or
    $agentPlayerInputOwnershipSource -notmatch 'IsHarnessAgentInputLockRequested' -or
    $agentPlayerInputOwnershipSource -notmatch 'CHRONICLE_HARNESS_AGENT_INPUT_LOCK' -or
    $agentPlayerInputOwnershipSource -notmatch '"battle-fixture" or "solo-battle-fixture"' -or
    $agentPlayerInputOwnershipSource -notmatch 'harness-agent-input-lock\|locked=' -or
    $agentPlayerInputOwnershipSource -notmatch 'SetLocked\(shouldLock, notifyPlayer: !harnessOwnsInput\)' -or
    $agentPlayerInputOwnershipSource -notmatch 'InputUsageMask\.All' -or
    $agentPlayerInputOwnershipSource -notmatch 'MissionState\.Current\?\.CurrentMission' -or
    $agentPlayerInputOwnershipSource -notmatch 'MapViewsContainer' -or
    $agentPlayerInputOwnershipSource -notmatch 'TryRepairDefaultToggleBinding' -or
    $agentPlayerInputOwnershipSource -notmatch 'AdvanceOwnershipToggleHarnessProbe' -or
    $agentPlayerInputOwnershipSource -notmatch 'NativeInput.PressKey' -or
    $agentPlayerInputOwnershipSource -notmatch 'GameKeyContextType.Default' -or
    $agentPlayerInputOwnershipSource -notmatch 'GameKeyOptionCategoryVM' -or
    $agentPlayerInputOwnershipSource -notmatch 'optionsVisible=' -or
    $agentPlayerInputOwnershipSource -notmatch 'agent-input-toggle-harness-probe' -or
    $agentPlayerInputOwnershipSource -notmatch '_toggleKeyWasDown' -or
    $agentPlayerInputOwnershipSource -notmatch 'CHRONICLE_HARNESS_AGENT_INPUT_TOGGLE_TEST' -or
    $agentPlayerInputOwnershipSource -notmatch 'HotKeyManager\.MarkForSave' -or
    $agentPlayerInputOwnershipSource -notmatch 'AI已接管玩家控制' -or
    $agentPlayerInputOwnershipSource -notmatch 'AI已停止，玩家控制已恢复' -or
    $agentPlayerInputOwnershipSource -notmatch 'StopGameOnFocusLost = true' -or
    $agentPlayerInputOwnershipSource -notmatch 'ScreenManager\.OnGameWindowFocusChange\(focusGained: false\)' -or
    $agentPlayerInputOwnershipSource -notmatch 'TestFocusGuardPrefix' -or
    $agentPlayerInputOwnershipSource -notmatch 'DescribeFocusPermissionPatchOwners' -or
    $agentPlayerInputOwnershipSource -notmatch 'Input\.PressKey\(InputKey\.Escape\)' -or
    $agentPlayerInputOwnershipSource -notmatch 'ForceMouseDownForRoutingProbe' -or
    $agentPlayerInputOwnershipSource -notmatch 'harmony\.Unpatch\(target, HarmonyPatchType\.All' -or
    $agentPlayerInputOwnershipSource -notmatch 'BannerlordConfig\.StopGameOnFocusLost = priorStopOnFocusLoss' -or
    $agentPlayerInputOwnershipSource -match 'SendInput|keybd_event|SetCursorPos' -or
    $agentHostLifecycleHarness -notmatch 'InputOwnershipSafeHandoffVerified' -or
    $agentHostLifecycleHarness -notmatch 'InputOwnershipAutoReleasedAfterHostExit' -or
    $agentHostLifecycleHarness -notmatch 'InputTogglePlayerReturnVerified' -or
    $agentHostLifecycleHarness -notmatch 'CHRONICLE_HARNESS_AGENT_INPUT_TOGGLE_TEST' -or
    $agentHostLifecycleHarness -notmatch "'InputToggle'" -or
    $agentHostLifecycleHarness -notmatch 'FocusGuardOwnerPrefixVerified' -or
    $agentHostLifecycleHarness -notmatch 'FocusGuardPlayerPrefixPassthroughVerified' -or
    $agentHostLifecycleHarness -notmatch 'ScreenLayerCaptureConfigurationVerified' -or
    $agentHostLifecycleHarness -notmatch 'SyntheticScreenInputRoutingVerified' -or
    $agentHostLifecycleHarness -notmatch 'HostExitObservedEvents' -or
    $agentHostLifecycleHarness -notmatch 'agent-input-focus-guard-installed' -or
    $agentHostLifecycleHarness -notmatch 'FocusLossEscapeSuppressionVerified' -or
    $agentHostLifecycleHarness -notmatch 'CHRONICLE_HARNESS_AGENT_INPUT_FOCUS_TEST' -or
    $agentHostLifecycleHarness -notmatch 'diagnosticRunStartedUtc' -or
    $agentHostLifecycleHarness -notmatch '\[DateTimeOffset\]::Parse') {
    throw 'Agent Host lifecycle verification must remain opt-in, use a disposable Campaign, exercise the registered MCM action delegates, require a versioned Native-PID handshake before Running, stop safely, and preserve source fixture/process cleanup.'
}
if ($moduleManifestSource -notmatch '<XmlName id="GameText" path="global_strings"' -or
    $moduleStringsSource -notmatch 'str_key_category_name\.ChronicleAgentControl' -or
    $moduleStringsSource -notmatch 'str_key_name\.ChronicleAgentControl_Up' -or
    $moduleStringsSource -notmatch 'str_key_description\.ChronicleAgentControl_Up' -or
    $harnessScript -notmatch 'Join-Path \$modulePackageRoot ''ModuleData''' -or
    $harnessScript -notmatch 'Copy-Item -LiteralPath \$moduleDataEntry\.FullName -Destination \$runtimeModuleData -Recurse -Force' -or
    $smokeModuleSource -notmatch 'ModuleData\\global_strings\.xml' -or
    $smokeModuleSource -notmatch 'str_key_description\.ChronicleAgentControl_Up' -or
    $smokeModuleSource -notmatch 'InputControlKeyDisplayTextLoaded' -or
    $smokeModuleSource -notmatch 'InputControlKeyVisibleInNativeOptions' -or
    $smokeModuleSource -notmatch 'agent-input-key-display-text' -or
    $releasePackageSource -notmatch 'ModuleData' -or
    $releasePackageSource -notmatch 'moduleDataSource') {
    throw 'The native configurable AI/player toggle must ship its GameText category/name/description resources in the installed module and release package.'
}
if ($harnessScript -notmatch "'AgentHostLifecycleCompletionEvaluation' \{ @\('Preflight', 'Build', 'Smoke', 'AgentHostPackage', 'AgentHostLifecycleCompletionEvaluation'\) \}" -or
    $harnessScript -match "'All' \{[^\r\n]*'AgentHostLifecycleCompletionEvaluation'" -or
    $harnessScript -notmatch '\-Scenario Complete' -or $agentHostLifecycleHarness -notmatch 'NativeArrivalCompleted' -or
    $agentHostLifecycleHarness -notmatch 'AgentHostLifecycleHostReceipt\.json' -or
    $agentHostRuntimeControllerSource -notmatch 'AgentHostLifecycleReceipt\.CaptureForHarness\(output, errorOutput, exitCode\)' -or
    $agentHostLifecycleReceiptSource -notmatch 'fresh-campaign-renown' -or
    $agentHostLifecycleReceiptSource -notmatch 'TryDeserializeReceipt' -or
    $agentHostLifecycleReceiptSource -notmatch 'HostExitCode' -or
    $agentHostLifecycleReceiptSource -notmatch 'DataMember\(Name = "message"\)' -or
    $agentHostLifecycleReceiptSource -notmatch 'SanitizeDiagnostic\(receipt\.Message\)' -or
    $agentHostLifecycleReceiptSource -notmatch 'sk-\[A-Za-z0-9_-' -or
    $freshCampaignTest -notmatch 'storyModeHostReceipt\.error' -or
    $agentHostLifecycleReceiptSource -notmatch 'DecisionCountAlias' -or
    $agentHostLifecycleReceiptSource -notmatch 'DecisionCount = Math\.Max' -or
    $agentHostHarnessProgressTraceSource -notmatch 'RecordObjectiveSubflowResult' -or
    $agentHostHarnessProgressTraceSource -notmatch 'objective-subflow-result') {
    throw 'Real game-launched Host completion must remain opt-in, use the local model and Native arrival postcondition, and keep a sanitized lifecycle receipt without full model prompts or responses.'
}
