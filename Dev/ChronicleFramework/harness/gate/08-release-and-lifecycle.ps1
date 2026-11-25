#Requires -Version 7.0

# Release and lifecycle: deterministic release archive, smoke dialog evidence, Host PID binding.
# Sources asserted here: Test-Module.ps1, New-ChronicleReleasePackage.ps1, Test-AgentHostReleasePackage.ps1, SubModule.cs, OllamaNativeProvider.cs, Program.cs, AgentHostCampaignLoop.cs, AgentHostSupplyLoop.cs, NativeMailboxClient.cs

$smokeModuleSource = Get-Content (Join-Path $stageRoot 'Test-Module.ps1') -Raw -Encoding UTF8
$releasePackageSource = Get-Content (Join-Path $stageRoot 'New-ChronicleReleasePackage.ps1') -Raw -Encoding UTF8
$releasePackageTestSource = Get-Content (Join-Path $stageRoot 'Test-AgentHostReleasePackage.ps1') -Raw -Encoding UTF8
if ($harnessScript -notmatch "'ReleasePackage' \{ @\('Preflight', 'AgentHostPackage', 'ReleasePackage'\) \}" -or
    $harnessScript -match "'All' \{[^\r\n]*'ReleasePackage'" -or
    $releasePackageSource -notmatch 'D:\\ChronicleFramework\\BuildCache\\ReleasePackages' -or
    $releasePackageSource -notmatch 'IO\.Compression\.ZipArchive' -or
    $releasePackageSource -notmatch 'sourceTreeClean' -or
    $releasePackageSource -notmatch 'ChronicleAgentHost\.exe' -or
    $releasePackageSource -notmatch 'release-manifest\.json' -or
    $releasePackageSource -notmatch 'SHA256' -or
    $releasePackageSource -notmatch 'LICENSE\.txt' -or
    $releasePackageTestSource -notmatch 'PackageReproducible' -or
    $releasePackageTestSource -notmatch 'ManifestValidated' -or
    $releasePackageTestSource -notmatch 'New-IsolatedGameRoot' -or
    $releasePackageTestSource -notmatch 'Test-Module\.ps1' -or
    $releasePackageTestSource -notmatch 'CHRONICLE_STEAM_ROOT' -or
    $smokeModuleSource -notmatch 'CHRONICLE_STEAM_ROOT' -or
    $releasePackageTestSource -notmatch 'FormalSaveHashesUnchanged' -or
    $releasePackageTestSource -notmatch 'UpdateRollbackCycleVerified' -or
    $releasePackageTestSource -notmatch 'SyntheticUpdateFixture' -or
    $releasePackageTestSource -notmatch 'manifest-only synthetic 0.1.0-to-0.1.1 fixture' -or
    $releasePackageTestSource -notmatch 'no hot-update path' -or
    $releasePackageTestSource -notmatch 'Assert-GameClosedForModuleFileChange' -or
    $releasePackageTestSource -notmatch 'RollbackPreservedUserData' -or
    $releasePackageTestSource -notmatch 'UninstallRemovedOnlyChronicleModule' -or
    $releasePackageTestSource -notmatch 'RequiredModulesRemainAfterUninstall' -or
    $releasePackageTestSource -notmatch 'UserMcmConfigurationUnchangedAfterUninstall' -or
    $releasePackageTestSource -notmatch 'FormalSavesUnchangedAfterUninstall' -or
    $releasePackageTestSource -notmatch 'NoGameProcessesDuringUninstall' -or
    $releasePackageTestSource -notmatch 'Get-DirectorySnapshotSha256' -or
    $releasePackageTestSource -notmatch 'UserMcmConfigurationUnchanged' -or
    $releasePackageTestSource -notmatch 'Remove-IsolatedTree' -or
    $smokeModuleSource -notmatch 'Bannerlord\.Harmony' -or $smokeModuleSource -notmatch 'Bannerlord\.MBOptionScreen' -or
    $smokeModuleSource -notmatch '\[switch\]\$SkipBuild') {
    throw 'W7-I must build a deterministic D: release archive, verify its inventory/checksum, install into a separate isolated game root and Smoke it without deploying into the user''s module directory.'
}
$subModuleSource = Get-Content (Join-Path $modRoot 'SubModule.cs') -Raw -Encoding UTF8
if ($harnessScript -notmatch "HarnessContractVersion\s*=\s*'$contractVersion'" -or
    $harnessScript -notmatch '\[int\]\$SmokeTimeoutSeconds\s*=\s*180' -or
    $smokeModuleSource -notmatch 'HarnessShaderCacheDialog\.ps1' -or $smokeModuleSource -notmatch 'Invoke-ChronicleShaderCacheDialogAcknowledgement' -or
    $smokeModuleSource -notmatch '\[int\]\$TimeoutSeconds\s*=\s*180' -or
    $smokeModuleSource -notmatch 'StartupDialogSnapshots' -or $smokeModuleSource -notmatch 'SmokeResult\.json' -or
    $smokeModuleSource -notmatch 'McmSettingsRegistered' -or $smokeModuleSource -notmatch 'requiredMcmButtonPropertyIds' -or
    $smokeModuleSource -notmatch 'StartupReadySeconds' -or $smokeModuleSource -notmatch 'stabilityCompleted' -or
    $smokeModuleSource -notmatch 'StartupTimeoutSeconds' -or $smokeModuleSource -notmatch 'ModuleIds = @\(\$modules\)' -or
    $smokeModuleSource -notmatch 'WindowLayoutApplied' -or $smokeModuleSource -notmatch 'candidateWindowLayout\.Applied' -or
    $smokeModuleSource -notmatch 'WindowLayoutNonActivating' -or $smokeModuleSource -notmatch 'candidateWindowLayout\.NonActivating' -or
    $smokeModuleSource -notmatch 'WindowNotForeground' -or $smokeModuleSource -notmatch 'candidateWindowLayout\.NotForeground' -or
    $smokeModuleSource -notmatch 'CursorUnrestrictedAcrossDesktop' -or $smokeModuleSource -notmatch '\$testWindowLayout\.CursorUnrestrictedAcrossDesktop' -or
    $smokeModuleSource -notmatch 'Get-ChronicleCursorClipSnapshot' -or $smokeModuleSource -notmatch '-CursorClipBaseline \$cursorClipBaseline' -or
    $smokeModuleSource -notmatch 'CursorClipRestorationAfterExit' -or $smokeModuleSource -notmatch 'cursorClipRestoration\.Restored' -or
    $smokeModuleSource -notmatch 'ForegroundProcessId = if \(\$testWindowLayout\)' -or
    $smokeModuleSource -notmatch 'HarnessInputLockObserved' -or $smokeModuleSource -notmatch 'CHRONICLE_HARNESS_AGENT_INPUT_LOCK' -or
    $smokeModuleSource -notmatch 'CampaignGoal' -or $smokeModuleSource -notmatch 'ViewAgentStatus' -or
    $subModuleSource -notmatch 'ProbeHarnessMcmSettingsRegistration' -or
    $subModuleSource -notmatch 'TrySkipHarnessStartupVideo' -or $subModuleSource -notmatch 'state\.CanUserSkip' -or
    $subModuleSource -notmatch 'player\.StopVideo\(\)' -or $subModuleSource -notmatch 'harness-mcm-settings-wait' -or
    $subModuleSource -notmatch 'BaseSettingsProvider\.Instance' -or $subModuleSource -notmatch 'ValidateLocalConfiguration' -or
    $subModuleSource -notmatch 'ChronicleAgentRuntimeController\.Tick\(\)' -or $subModuleSource -notmatch 'StopForSubModuleUnload' -or
    $subModuleSource -notmatch 'agent-host-lifecycle-test' -or
    $subModuleSource -notmatch 'harness-smoke-mode-active' -or
    $harnessScript -notmatch 'Smoke test failed with exit code \$smokeExitCode\. Evidence: \$smokeOutput') {
    throw 'Smoke startup checks must preserve dialog evidence and verify MCM registered Chronicle settings and the validation button.'
}
$agentHostProviderSource = Get-Content (Join-Path $agentHostRoot 'OllamaNativeProvider.cs') -Raw -Encoding UTF8
$agentHostProgramSource = Get-Content (Join-Path $agentHostRoot 'Program.cs') -Raw -Encoding UTF8
$agentHostCampaignLoopSource = Get-Content (Join-Path $agentHostRoot 'AgentHostCampaignLoop.cs') -Raw -Encoding UTF8
$agentHostSupplyLoopSource = Get-Content (Join-Path $agentHostRoot 'AgentHostSupplyLoop.cs') -Raw -Encoding UTF8
$agentHostMailboxSource = Get-Content (Join-Path $agentHostRoot 'NativeMailboxClient.cs') -Raw -Encoding UTF8
if ($agentHostProviderSource -notmatch 'CheckConfiguredModelAsync' -or $agentHostProviderSource -notmatch '/models' -or
    $agentHostProviderSource -notmatch 'FREELLMAPI_API_KEY' -or $agentHostProviderSource -notmatch 'X-Routed-Via' -or
    $agentHostProviderSource -notmatch '_supportsParallelToolCalls' -or
    $agentHostProviderSource -notmatch 'payload\["parallel_tool_calls"\] = false' -or
    $agentHostProviderSource -notmatch 'providerToolCallsDiscarded = toolCallCount - 1' -or
    $agentHostProviderSource -notmatch 'var toolCall = toolCalls\[0\]' -or
    $agentHostProviderContractSelfTestSource -notmatch 'required-tool-call-disables-parallel-calls-and-serializes-a-native-decision-batch-to-its-first-current-action' -or
    $agentHostProviderContractSelfTestSource -notmatch 'provider-serializes-only-the-first-tool-call-and-validates-it-against-the-current-native-catalog' -or
    $agentHostProviderSource -notmatch 'finishReason is "length" or "max_tokens"' -or
    $agentHostProviderContractSelfTestSource -notmatch 'required-tool-call-length-response-is-routed-to-one-bounded-truncation-retry' -or
    $agentHostProviderDecisionRecoverySource -notmatch 'provider-multiple-tool-calls' -or
    $agentHostProviderDecisionRecoverySource -notmatch 'rejectedDecisions < \(errorCode is "provider-multiple-tool-calls" or "provider-response-truncated" or "provider-tool-call-missing" \? 1 : MaxRejectedDecisions\)' -or
    $agentHostProviderDecisionRecoverySource -notmatch 'provider-decision-recovery-retries-multiple-tool-calls-once-without-native-actions' -or
    $agentHostProviderDecisionRecoverySource -notmatch 'provider-missing-tool-call-feedback-self-test-failed' -or
    $agentHostProviderContractSelfTestSource -notmatch 'generic-https-openai-compatible-provider-health-auth-and-structured-decision' -or
    $agentHostProviderContractSelfTestSource -notmatch 'canonical-observe-again-decision-is-recognized-by-native-subloops' -or
    $agentHostProviderSource -notmatch 'IsListedSingleArgumentValue' -or $agentHostProviderSource -notmatch 'IsStoryModeClanNameTextArgument' -or
    $agentHostProviderContractSelfTestSource -notmatch 'provider-repairs-only-exact-listed-single-enum-argument-shorthand' -or
    $agentHostProviderContractSelfTestSource -notmatch 'provider-repairs-single-storymode-clan-name-text-shorthand-for-native-validation' -or
    $agentHostProviderContractSelfTestSource -notmatch 'deepseek-run-cost-reservation-rejects-over-budget-before-http' -or
    $agentHostProviderContractSelfTestSource -notmatch 'required-tool-call-disables-parallel-calls-and-serializes-a-native-decision-batch-to-its-first-current-action' -or
    $agentHostHarnessProgressTraceSource -notmatch 'provider-progress-trace-records-request-size-cache-cost-and-goal-scope-without-request-content' -or
    $agentHostHarnessProgressTraceSource -notmatch 'observationFieldByteSizes' -or $agentHostHarnessProgressTraceSource -notmatch 'observationStateFieldByteSizes' -or
    $agentHostProviderSource -notmatch 'auto:reliable' -or
    $agentHostProviderSelfTestSource -notmatch 'freellmapi-health-accepts-documented-auto-reliable-strategy-not-listed-as-model' -or
    $agentHostProviderSelfTestSource -notmatch 'freellmapi-health-rejects-unknown-auto-profile-not-listed-as-model' -or
    $freeLlmApiProfileSource -notmatch 'auto:reliable' -or $freeLlmApiProfileSource -notmatch 'auto:fastest' -or
    $agentHostProviderSmokeSource -notmatch 'auto:reliable' -or $agentHostProviderSmokeSource -notmatch 'auto:typo-profile' -or
    $agentHostCampaignLoopSource -notmatch 'providerRouteHistory' -or $agentHostVillageToolsQuestLoopSource -notmatch 'providerRouteHistory' -or
    $agentHostProviderSmokeSource -notmatch 'Initialize-FreeLLMAPIProfile' -or $agentHostProviderSmokeSource -match '/api/tags' -or
    $agentHostCampaignLoopSource -notmatch 'provider\.CheckConfiguredModelAsync' -or $agentHostSupplyLoopSource -notmatch 'provider\.CheckConfiguredModelAsync' -or
    $agentHostProgramSource -notmatch 'WaitForStopSignalAsync' -or $agentHostProgramSource -notmatch 'ReadLineAsync\(cancellationToken\)' -or
    $agentHostProgramSource -notmatch 'control.*stop' -or $agentHostCampaignLoopSource -notmatch 'native-action-result-ambiguous' -or
    $agentHostCampaignLoopSource -notmatch 'host-stop-requested' -or
    $agentHostProgramSource -notmatch 'OpenBoundParentProcess' -or $agentHostProgramSource -notmatch 'WaitForParentExitAsync' -or
    $agentHostProgramSource -notmatch 'MarkParentExited' -or $agentHostCampaignLoopSource -notmatch 'native-parent-process-mismatch' -or
    $agentHostProviderSource -notmatch 'FromCampaignRequest' -or $agentHostProviderSource -notmatch 'mcm-start-request' -or
    $agentHostRuntimeControllerSource -notmatch 'providerConfiguration' -or
    $agentHostMailboxSource -notmatch 'native-response-session-mismatch' -or $agentHostMailboxSource -notmatch 'expectedNativeSessionId' -or
    $agentProtocolSource -notmatch 'native-session-mismatch' -or $subModuleSource -notmatch 'AgentRuntimeSessionId' -or
    $agentHostRuntimeControllerSource -notmatch 'ReferenceEquals.*_ownedCampaign' -or
    $agentHostCampaignLoopSource -notmatch 'onReady\?\.Invoke\(nativeProcessId\)') {
    throw 'Host lifecycle must bind to the launching Bannerlord PID/start time, handshake against the current Native PID before ready, monitor game exit, accept only explicit stop control, and fail safely without replay after an ambiguous action.'
}
