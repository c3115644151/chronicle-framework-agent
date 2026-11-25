#Requires -Version 7.0

# Command surface: stage index, protocol sources, input lockdown and the Campaign action catalog.
# Sources asserted here: Run-Harness.ps1, Test-AgentPersistentStoryModeCampaign.ps1, HarnessStartupEvidence.ps1, Prune-TestResults.ps1, Agent-Cli.ps1, Test-Campaign.ps1, Test-WindowLayout.ps1, HarnessShaderCacheDialog.ps1, AgentProtocol.cs, SubModule.cs, AgentObserver.cs, AgentMapIncidentAdapter.cs, Test-AgentMapIncidentInputGuard.ps1, AgentInquiryAdapter.cs, StoryModeEstablishClanLifecycleStatus.cs, Agent-DecisionLoop.ps1, Agent-ProviderBudget.ps1, Agent-DecisionLoopPolicy.ps1, Test-AgentLoopProvider.ps1, Test-AgentLoop.ps1, Agent-OpenAICompatibleProvider.ps1, Get-FreeLLMAPIProfile.ps1, Test-AgentOpenAICompatibleProvider.ps1, Test-AgentEvaluationLiveModelSupply.ps1, AgentHostCampaignLoop.cs, Program.cs, AgentHostRuntimeProgressLog.cs, Test-AgentLiveModelLoop.ps1, AgentHostEstablishClanRecruitmentLoop.cs, AgentHostEstablishClanTrainingIssueLoop.cs, AgentHostEstablishClanCompanionLoop.cs, AgentHostNativeMapMovementMonitor.cs, Test-AgentHostNativeMapMovementMonitorProbe.ps1, AgentHostSupplyLoop.cs, AgentHostDecisionCycle.cs, AgentHostEstablishYourClanGoalLoop.cs, AgentHostEstablishYourClanAutonomyLoop.cs, AgentHostMapIncidentLoop.cs, AgentHostStoryModeBootstrapLoop.cs, AgentHostHarnessProgressTrace.cs, ProviderContractSelfTest.cs, AgentHostProviderDecisionRecovery.cs, Test-AgentFreshCampaign.ps1, OllamaNativeProvider.cs, AgentHostRuntimeController.cs, AgentProviderSettings.cs, AgentHostLifecycleReceipt.cs

$harnessStageSourceFiles = @((Join-Path $stageRoot 'Run-Harness.ps1')) + @(Get-ChildItem -Path (Join-Path $stageRoot 'stages') -File -Filter '*.ps1' | Sort-Object FullName | ForEach-Object { $_.FullName })
$harnessScript = (@($harnessStageSourceFiles | ForEach-Object { Get-Content -LiteralPath $_ -Raw -Encoding UTF8 }) -join [Environment]::NewLine)

$layoutFailures = Test-HarnessLayout -Layout $layout
if ($layoutFailures.Count -gt 0) { throw ($layoutFailures -join '; ') }
$stageReferencePattern = 'Join-Path\s+\$stageRoot\s+''([^'']+\.ps1)'''
foreach ($stageReference in [regex]::Matches($harnessScript, $stageReferencePattern)) {
    $stageScriptName = $stageReference.Groups[1].Value
    if (-not (Test-Path -LiteralPath (Join-Path $stageRoot $stageScriptName) -PathType Leaf)) {
        throw "Run-Harness.ps1 references a stage script that is missing from the stage root: $stageScriptName (root: $stageRoot)"
    }
}

$persistentStoryModeCampaignScript = Get-Content (Join-Path $stageRoot 'Test-AgentPersistentStoryModeCampaign.ps1') -Raw -Encoding UTF8
$harnessStartupEvidenceSource = Get-Content (Join-Path $stageRoot 'HarnessStartupEvidence.ps1') -Raw -Encoding UTF8
$testResultsRetentionScript = Join-Path $stageRoot 'Prune-TestResults.ps1'
$agentCliSource = Get-Content (Join-Path $stageRoot 'Agent-Cli.ps1') -Raw -Encoding UTF8
$testCampaignSource = Get-Content (Join-Path $stageRoot 'Test-Campaign.ps1') -Raw -Encoding UTF8
$testWindowLayoutSource = Get-Content (Join-Path $stageRoot 'Test-WindowLayout.ps1') -Raw -Encoding UTF8
$shaderDialogSource = Get-Content (Join-Path $stageRoot 'HarnessShaderCacheDialog.ps1') -Raw -Encoding UTF8
$agentProtocolSourceFiles = @((Join-Path $modRoot 'AgentProtocol.cs')) + @(Get-ChildItem -Path $modRoot -Recurse -File -Filter 'ChronicleAgentProtocol*.cs' | Sort-Object FullName | ForEach-Object { $_.FullName })
$agentProtocolSource = (@($agentProtocolSourceFiles | ForEach-Object { Get-Content -LiteralPath $_ -Raw -Encoding UTF8 }) -join [Environment]::NewLine)
$subModuleSource = Get-Content (Join-Path $modRoot 'SubModule.cs') -Raw -Encoding UTF8
$agentObserverSource = Get-Content (Join-Path $modRoot 'AgentObserver.cs') -Raw -Encoding UTF8
$agentMapIncidentAdapterSource = Get-Content (Join-Path $modRoot 'AgentMapIncidentAdapter.cs') -Raw -Encoding UTF8
$mapIncidentInputGuardTestSource = Get-Content (Join-Path $stageRoot 'Test-AgentMapIncidentInputGuard.ps1') -Raw -Encoding UTF8
$agentInquiryAdapterSource = Get-Content (Join-Path $modRoot 'AgentInquiryAdapter.cs') -Raw -Encoding UTF8
$agentInquiryAdapterSource = Get-Content (Join-Path $modRoot 'AgentInquiryAdapter.cs') -Raw -Encoding UTF8
if ([regex]::Matches($agentObserverSource, 'isWaitMenu').Count -ne 1 -or [regex]::Matches($agentObserverSource, 'isWaitActive').Count -ne 1) { throw 'The Native observer must emit each Wait-menu fact exactly once; duplicate JSON keys can make the Host fail before any model decision.' }
$storyModeLifecycleStatusSource = Get-Content (Join-Path $modRoot 'StoryModeEstablishClanLifecycleStatus.cs') -Raw -Encoding UTF8
$agentDecisionLoopSource = Get-Content (Join-Path $stageRoot 'Agent-DecisionLoop.ps1') -Raw -Encoding UTF8
$agentProviderBudgetSource = Get-Content (Join-Path $stageRoot 'Agent-ProviderBudget.ps1') -Raw -Encoding UTF8
$agentDecisionLoopPolicySource = Get-Content (Join-Path $stageRoot 'Agent-DecisionLoopPolicy.ps1') -Raw -Encoding UTF8
$nativeRejectedActionBranch = [regex]::Match($agentDecisionLoopSource, 'if \(\$actionResult.status -notin @\(''completed'',''accepted''\)\)(?<branch>[\s\S]*?)(?=\$stepTiming.observationStartedUtc)').Groups['branch'].Value
$agentDecisionTestProviderSource = Get-Content (Join-Path $stageRoot 'Test-AgentLoopProvider.ps1') -Raw -Encoding UTF8
$agentDecisionLoopTestSource = Get-Content (Join-Path $stageRoot 'Test-AgentLoop.ps1') -Raw -Encoding UTF8
$agentOpenAiProviderSource = Get-Content (Join-Path $stageRoot 'Agent-OpenAICompatibleProvider.ps1') -Raw -Encoding UTF8
$freeLlmApiProfileSource = Get-Content (Join-Path $stageRoot 'Get-FreeLLMAPIProfile.ps1') -Raw -Encoding UTF8
$agentOpenAiProviderTestSource = Get-Content (Join-Path $stageRoot 'Test-AgentOpenAICompatibleProvider.ps1') -Raw -Encoding UTF8
$agentEvaluationLiveModelSupplySource = Get-Content (Join-Path $stageRoot 'Test-AgentEvaluationLiveModelSupply.ps1') -Raw -Encoding UTF8
$agentHostCampaignLoopSource = Get-Content (Join-Path $agentHostRoot 'AgentHostCampaignLoop.cs') -Raw -Encoding UTF8
$agentHostProgramSource = Get-Content (Join-Path $agentHostRoot 'Program.cs') -Raw -Encoding UTF8
$agentHostRuntimeProgressLogSource = Get-Content (Join-Path $agentHostRoot 'AgentHostRuntimeProgressLog.cs') -Raw -Encoding UTF8
$agentLiveModelLoopSource = Get-Content (Join-Path $stageRoot 'Test-AgentLiveModelLoop.ps1') -Raw -Encoding UTF8
$harnessInputLockArmIndex = $agentLiveModelLoopSource.IndexOf('$env:CHRONICLE_HARNESS_AGENT_INPUT_LOCK = ''1''', [StringComparison]::Ordinal)
$harnessInputLockLoadIndex = $agentLiveModelLoopSource.IndexOf("Invoke-AgentCli 'load'", [StringComparison]::Ordinal)
if ($agentLiveModelLoopSource -notmatch 'Harness game input lock was not confirmed' -or
    $agentLiveModelLoopSource -notmatch 'HarnessInputOwnershipConfirmed = \$harnessInputLockConfirmed' -or
    $harnessInputLockArmIndex -lt 0 -or $harnessInputLockLoadIndex -lt 0 -or $harnessInputLockArmIndex -gt $harnessInputLockLoadIndex) {
    throw 'Live-model Harness must arm and verify test-owned game input lockdown before loading a scene or sending provider requests.'
}
$agentHostRecruitmentLoopSource = Get-Content (Join-Path $agentHostRoot 'AgentHostEstablishClanRecruitmentLoop.cs') -Raw -Encoding UTF8
$agentHostTrainingIssueLoopSource = Get-Content (Join-Path $agentHostRoot 'AgentHostEstablishClanTrainingIssueLoop.cs') -Raw -Encoding UTF8
$agentHostCompanionLoopSource = Get-Content (Join-Path $agentHostRoot 'AgentHostEstablishClanCompanionLoop.cs') -Raw -Encoding UTF8
$agentHostNativeMapMovementMonitorSource = Get-Content (Join-Path $agentHostRoot 'AgentHostNativeMapMovementMonitor.cs') -Raw -Encoding UTF8
$agentHostNativeMapMovementProbeSource = Get-Content (Join-Path $stageRoot 'Test-AgentHostNativeMapMovementMonitorProbe.ps1') -Raw -Encoding UTF8
$agentHostSupplyLoopSource = Get-Content (Join-Path $agentHostRoot 'AgentHostSupplyLoop.cs') -Raw -Encoding UTF8
$agentHostDecisionCycleSource = Get-Content (Join-Path $agentHostRoot 'AgentHostDecisionCycle.cs') -Raw -Encoding UTF8
$agentHostEstablishClanPlannerSource = Get-Content (Join-Path $agentHostRoot 'AgentHostEstablishYourClanGoalLoop.cs') -Raw -Encoding UTF8
$agentHostEstablishClanAutonomySource = Get-Content (Join-Path $agentHostRoot 'AgentHostEstablishYourClanAutonomyLoop.cs') -Raw -Encoding UTF8
$agentHostMapIncidentLoopSource = Get-Content (Join-Path $agentHostRoot 'AgentHostMapIncidentLoop.cs') -Raw -Encoding UTF8
$agentHostStoryModeBootstrapLoopSource = Get-Content (Join-Path $agentHostRoot 'AgentHostStoryModeBootstrapLoop.cs') -Raw -Encoding UTF8
$agentHostHarnessProgressTraceSource = Get-Content (Join-Path $agentHostRoot 'AgentHostHarnessProgressTrace.cs') -Raw -Encoding UTF8
$agentHostProviderContractSelfTestSource = Get-Content (Join-Path $agentHostRoot 'ProviderContractSelfTest.cs') -Raw -Encoding UTF8
$agentHostProviderDecisionRecoverySource = Get-Content (Join-Path $agentHostRoot 'AgentHostProviderDecisionRecovery.cs') -Raw -Encoding UTF8
$freshCampaignTestSource = Get-Content (Join-Path $stageRoot 'Test-AgentFreshCampaign.ps1') -Raw -Encoding UTF8
$agentHostProviderSource = Get-Content (Join-Path $agentHostRoot 'OllamaNativeProvider.cs') -Raw -Encoding UTF8
$agentHostRuntimeControllerSource = Get-Content (Join-Path $modRoot 'AgentHostRuntimeController.cs') -Raw -Encoding UTF8
$providerSettingsSource = Get-Content (Join-Path $modRoot 'AgentProviderSettings.cs') -Raw -Encoding UTF8
$agentHostLifecycleReceiptSource = Get-Content (Join-Path $modRoot 'AgentHostLifecycleReceipt.cs') -Raw -Encoding UTF8
$agentHostActionProfileNames = @('ApprovedActions','BattleSimulationActions','GoldSaleActions','RecruitmentActions','CompanionHiringActions','TrainingIssueActions')
$agentHostSupportedActions = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($profileName in $agentHostActionProfileNames) {
    $profilePattern = [regex]::Escape($profileName) + '\s*=\s*new\(StringComparer\.Ordinal\)\s*\{(?<actions>[\s\S]*?)\};'
    $profileMatch = [regex]::Match($agentHostCampaignLoopSource, $profilePattern)
    if (-not $profileMatch.Success) { throw "AgentHost action profile $profileName could not be read for the MCM request-contract check." }
    foreach ($actionMatch in [regex]::Matches($profileMatch.Groups['actions'].Value, '"(?<action>[A-Za-z][A-Za-z0-9]*)"')) {
        [void]$agentHostSupportedActions.Add($actionMatch.Groups['action'].Value)
    }
}
$startRequestLine = @([regex]::Split($agentHostRuntimeControllerSource, '\r?\n') | Where-Object { $_.Contains('allowedActionNames') } | Select-Object -First 1)
if ($startRequestLine.Count -ne 1) { throw 'AgentHostRuntimeController must emit one canonical Campaign action request catalog.' }
$startActionCatalogLine = [string]$startRequestLine[0]
$startActionMarkerIndex = $startActionCatalogLine.IndexOf('allowedActionNames', [StringComparison]::Ordinal)
$startActionArrayOpen = $startActionCatalogLine.IndexOf('[', $startActionMarkerIndex)
$startActionArrayClose = $startActionCatalogLine.IndexOf(']', $startActionArrayOpen + 1)
if ($startActionArrayOpen -lt 0 -or $startActionArrayClose -lt 0) { throw 'AgentHostRuntimeController Campaign action request catalog is not a bounded JSON array.' }
$startActions = @($startActionCatalogLine.Substring($startActionArrayOpen + 1, $startActionArrayClose - $startActionArrayOpen - 1).Split(',') | ForEach-Object { $_ -replace '[^A-Za-z0-9]', '' } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$missingMcmActions = @($agentHostSupportedActions | Where-Object { $_ -notin $startActions })
$unexpectedMcmActions = @($startActions | Where-Object { $_ -notin $agentHostSupportedActions })
if ($missingMcmActions.Count -gt 0 -or $unexpectedMcmActions.Count -gt 0 -or $startActions.Count -ne $agentHostSupportedActions.Count) {
    throw "AgentHostRuntimeController start catalog must exactly match AgentHostCampaignLoop.AllSupportedActions (missing=$($missingMcmActions -join ','); unexpected=$($unexpectedMcmActions -join ','))."
}
if ($agentHostProgramSource -notmatch '--campaign-action-catalog' -or
    $agentLiveModelLoopSource -notmatch '--campaign-action-catalog' -or
    $agentLiveModelLoopSource -notmatch 'catalogActions = @\(\$catalog\.actions' -or
    $agentLiveModelLoopSource -notmatch '\$allowedActions = \[string\]::Join\(') {
    throw 'The full EYC live-model Harness request must take its action allowlist from the compiled AgentHost catalog so product and campaign integration contracts cannot drift.'
}
if ($agentHostRecruitmentLoopSource -notmatch 'AgentHostProviderDecisionRecovery\.DecideWithSingleRetryAsync' -or
    $agentHostRecruitmentLoopSource -notmatch 'decision-rejected-before-native' -or
    $agentHostDecisionCycleSource -notmatch 'The previous model response selected an unavailable action or control' -or
    $agentHostRecruitmentLoopSource -notmatch 'provider-control-unavailable') {
    throw 'The EYC PartySize route must give one bounded current-catalog recovery when the model selects an unavailable action/control, and verify that no Native action was sent.'
}
if ($agentHostProviderSource -notmatch 'InferEnumeratedJsonSchemaType' -or
    $agentHostProviderContractSelfTestSource -notmatch 'provider-map-incident-option-index-is-integer-enum-not-string' -or
    $agentHostProviderContractSelfTestSource -notmatch 'provider-prisoner-recruitment-confirmations-follow-native-integer-enums' -or
    $agentHostProgramSource -notmatch 'BuildCampaignLoopTerminalReceipt' -or
    $agentHostProgramSource -notmatch 'failureExceptionType' -or
    $agentHostProgramSource -notmatch 'failureLocation' -or
    $agentHostProviderContractSelfTestSource -notmatch 'NullReferenceException' -or
    $agentHostProviderContractSelfTestSource -notmatch 'AgentHostEstablishYourClanAutonomyLoop.RunAsync' -or
    $freshCampaignTestSource -notmatch 'StoryModeAgentFailureExceptionType' -or
    $freshCampaignTestSource -notmatch 'StoryModeAgentFailureLocation' -or
    $agentHostProviderContractSelfTestSource -notmatch 'campaign-loop-emits-compact-cost-and-failure-receipt-without-trace-or-free-text') {
    throw 'The model schema must infer current Native argument types, and the Campaign Host must emit a tested compact terminal receipt instead of discarding error/cost evidence in a large trace.'
}
if ($agentHostProviderSource -notmatch 'toolCallsPresent=' -or
    $agentHostProviderSource -notmatch 'contentCharacters=' -or
    $agentHostProviderSource -notmatch 'promptTokens=' -or
    $agentHostProviderSource -notmatch 'routedVia=' -or
    $agentHostProviderContractSelfTestSource -notmatch 'provider-required-tool-call-missing-response-logs-safe-route-shape-and-usage' -or
    $agentHostProviderContractSelfTestSource -notmatch 'PRIVATE_FREE_LLM_API_RESPONSE_MUST_NOT_BE_LOGGED') {
    throw 'Missing required tool-call failures must retain only response-shape, route and token-use diagnostics; a self-test must prove response text is not copied into the failure message.'
}
if ($agentHostProviderSource -notmatch 'reasoningEffortIsExplicitlySupportedByFreeLlmApi' -or
    $agentHostProviderSource -notmatch '_supportsReasoningEffort' -or
    $agentHostProviderSource -notmatch 'SupportsThinkingParameter' -or
    $agentHostProviderSource -notmatch 'IsOpenRouterReasoningRoute' -or
    $agentHostProviderSource -notmatch 'payload\["reasoning"\]' -or
    $agentHostProviderSource -notmatch 'ReadString\(error, "param"\)' -or
    $agentHostProviderSource -notmatch 'ProviderErrorParam' -or
    $agentHostProviderSource -notmatch 'providerErrorParam: errorMetadata.ErrorParam' -or
    $agentHostProviderSource -notmatch 'ReasoningEffortApplied' -or
    $agentHostProviderContractSelfTestSource -notmatch 'provider-neutral-loopback-gateway-tool-call-omits-nonstandard-thinking-extension' -or
    $agentHostProviderContractSelfTestSource -notmatch 'openrouter-reasoning-disabled-uses-standard-reasoning-object' -or
    $agentHostProviderContractSelfTestSource -notmatch 'openrouter-empty-choices-preserves-safe-response-shape-and-usage' -or
    $agentHostProviderContractSelfTestSource -notmatch 'provider-http-failure-cli-output-preserves-safe-error-fields-without-body' -or
    $agentHostProviderContractSelfTestSource -notmatch 'tools_0_.function.parameters' -or
    $agentHostProgramSource -notmatch 'BuildSafeProviderFailureDetails' -or
    $agentHostProgramSource -notmatch '\["errorParam"\]' -or
    $agentHostProgramSource -notmatch '\["dshUpstreamCode"\]' -or
    $agentHostRuntimeProgressLogSource -notmatch '\["providerErrorParam"\]' -or
    $agentHostRuntimeProgressLogSource -notmatch '\["providerDshUpstreamCode"\]' -or
    $agentHostHarnessProgressTraceSource -notmatch '\["providerErrorParam"\]' -or
    $agentHostHarnessProgressTraceSource -notmatch '\["providerDshUpstreamCode"\]' -or
    $agentHostProviderContractSelfTestSource -notmatch 'freellmapi-advertised-reasoning-effort-low-is-applied-with-thinking-disabled' -or
    $agentHostProviderContractSelfTestSource -notmatch 'freellmapi-unadvertised-reasoning-effort-is-omitted' -or
    $agentHostRuntimeProgressLogSource -notmatch 'reasoningEffortApplied' -or
    $agentHostHarnessProgressTraceSource -notmatch 'reasoningEffortApplied' -or
    $agentHostHarnessProgressTraceSource -notmatch 'ProviderToolCallsDiscarded: 2' -or
    $agentHostRuntimeProgressLogSource -notmatch 'providerToolCallsDiscarded' -or
    $agentHostHarnessProgressTraceSource -notmatch 'providerToolCallsDiscarded') {
    throw 'FreeLLMAPI reasoning effort must be sent only when the selected model advertises the capability, even with thinking disabled, and the applied setting must be auditable.'
}
if ($agentHostDecisionCycleSource -notmatch 'BuildBattleAndCaptivityDecisionPrompt' -or
    $agentHostDecisionCycleSource -notmatch 'battle-and-captivity-prompt-scopes-visible-pursuit-to-current-target-action' -or
    $agentHostDecisionCycleSource -notmatch 'battle-and-captivity-prompt-scopes-encounter-risk-without-postbattle-sections' -or
    $agentHostDecisionCycleSource -notmatch 'battle-and-captivity-prompt-scopes-release-page-to-native-mno-continue') {
    throw 'Battle/captivity prompts must be scoped to the latest Native state/action catalog and regression-test the current pursuit, encounter and captivity-release steps.'
}
if ($agentHostProviderSource -notmatch '_supportsReasoningEffort' -or
    $agentHostProviderSource -notmatch 'reasoningEffortIsExplicitlySupportedByFreeLlmApi' -or
    $agentHostProviderSource -notmatch 'ReasoningEffortApplied' -or
    $agentHostProviderContractSelfTestSource -notmatch 'freellmapi-advertised-reasoning-effort-low-is-applied-with-thinking-disabled' -or
    $agentHostProviderContractSelfTestSource -notmatch 'freellmapi-unadvertised-reasoning-effort-is-omitted') {
    throw 'FreeLLMAPI reasoning effort must be sent only when the selected model advertises the capability, even when the separate thinking switch is disabled, and the applied setting must be auditable.'
}
if ($agentHostTrainingIssueLoopSource -notmatch 'training-issue-self-test-localized-direct-offer-hidden' -or
    $agentHostTrainingIssueLoopSource -notmatch 'training-issue-self-test-discovery-budget-not-bounded' -or
    $agentHostTrainingIssueLoopSource -notmatch 'training-issue-self-test-truncated-response-recovery-missing' -or
    $agentHostTrainingIssueLoopSource -notmatch 'AgentHostProviderDecisionRecovery.CanRetry' -or
    $agentHostTrainingIssueLoopSource -notmatch 'training-issue-self-test-no-upgrade-query-loop' -or
    $agentHostTrainingIssueLoopSource -notmatch 'UpdateUpgradeOptionsReceipt' -or
    $agentHostTrainingIssueLoopSource -notmatch 'native-storymode-training-issue-gold' -or
    $agentHostTrainingIssueLoopSource -notmatch 'training-issue-search-budget-exhausted' -or
    $agentHostTrainingIssueLoopSource -notmatch 'MaximumTrainingIssueDiscoveryDecisions = 32' -or
    $agentHostTrainingIssueLoopSource -notmatch 'AgentHostNativeMapMovementMonitor\.WaitAsync' -or
    $agentHostTrainingIssueLoopSource -notmatch 'waitSeconds != AgentHostNativeMapMovementMonitor\.MaximumWatchWindowSeconds' -or
    $agentHostTrainingIssueLoopSource -notmatch 'training-issue-movement-wait-uses-shared-native-monitor-with-one-model-decision' -or
    $agentHostTrainingIssueLoopSource -notmatch 'IsPendingVillagersInNeedConversationTransition' -or
    $agentHostTrainingIssueLoopSource -notmatch 'BuildVillagersInNeedConversationCatalog' -or
    $agentHostTrainingIssueLoopSource -notmatch 'training-issue-villagers-in-need-cross-route-failed' -or
    $agentHostTrainingIssueLoopSource -notmatch 'native-stalled-move-returned-by-training-issue' -or
    $agentHostTrainingIssueLoopSource -notmatch 'IsCampaignTimeAdvancing\(native\)' -or
    $agentHostEstablishClanAutonomySource -notmatch 'ShouldReturnPausedNativeMoveToParent' -or
    $agentHostEstablishClanAutonomySource -notmatch 'objective-child-returned-paused-native-move-to-parent' -or
    $agentHostDecisionCycleSource -notmatch 'waitSeconds=10 exactly' -or
    $agentHostCampaignLoopSource -notmatch 'training-issue-search-budget-exhausted' -or
    $agentHostTrainingIssueLoopSource -notmatch 'localizedDirectOption' -or
    $agentHostTrainingIssueLoopSource -notmatch 'currentTrainingIssueGiverConversation') {
    throw 'The retainer-training route must use current Native offers, identify its decision scope, avoid repeating a no-upgrade query, and use the shared per-second movement monitor instead of repeated model waits.'
}
if ($agentHostHarnessProgressTraceSource -notmatch 'AgentHostRuntimeProgressLog\.RecordDecision' -or
    $agentHostHarnessProgressTraceSource -notmatch 'AgentHostRuntimeProgressLog\.RecordObjectiveSubflowResult' -or
    $agentHostHarnessProgressTraceSource -notmatch '\["objectiveId"\] = ReadString\(requestNode, "objectiveId"\)' -or
    $agentHostHarnessProgressTraceSource -notmatch '\["scope"\] = ReadString\(observation, "scope"\)' -or
    $agentHostProgramSource -notmatch 'AgentHostRuntimeProgressLog\.RecordRunStarted' -or
    $agentHostProgramSource -notmatch 'AgentHostRuntimeProgressLog\.RecordRunSummary' -or
    $agentHostRuntimeProgressLogSource -notmatch 'MaximumRunLogBytes' -or
    $agentHostRuntimeProgressLogSource -notmatch 'MaximumRetainedRunLogs' -or
    $agentHostRuntimeProgressLogSource -notmatch 'WriteUsageSignal\(result, configuredRunCostLimitCny\)' -or
    $agentHostRuntimeProgressLogSource -notmatch 'BuildLoggedUsageSummary' -or
    $agentHostRuntimeProgressLogSource -notmatch 'providerResponseRows' -or
    $agentHostRuntimeProgressLogSource -notmatch 'BuildLoggedUsageByScope' -or
    $agentHostRuntimeProgressLogSource -notmatch 'providerUsageByScope' -or
    $agentHostHarnessProgressTraceSource -notmatch 'campaign-agent-loop' -or
    $agentHostRuntimeProgressLogSource -notmatch 'providerHttpStatus' -or
    $agentHostRuntimeProgressLogSource -notmatch 'providerFailureStage' -or
    $agentHostRuntimeProgressLogSource -notmatch 'providerProxySelectionSource' -or
    $agentHostRuntimeProgressLogSource -notmatch 'providerProxyEndpointHostPort' -or
    $agentHostRuntimeProgressLogSource -notmatch 'providerResponseServer' -or
    $agentHostRuntimeProgressLogSource -notmatch 'providerResponseVia' -or
    $agentHostRuntimeProgressLogSource -notmatch 'providerResponseRequestId' -or
    $agentHostRuntimeProgressLogSource -notmatch 'providerRetryAfter' -or
    $agentHostRuntimeProgressLogSource -notmatch 'providerErrorBodyKind' -or
    $agentHostRuntimeProgressLogSource -notmatch 'providerErrorCode' -or
    $agentHostRuntimeProgressLogSource -notmatch 'providerFallbackAttempts' -or
    $agentHostRuntimeProgressLogSource -notmatch 'providerFallbackTrail' -or
    $agentHostRuntimeProgressLogSource -notmatch 'providerToolCallsPresent' -or
    $agentHostRuntimeProgressLogSource -notmatch 'providerResponseContentKind' -or
    $agentHostRuntimeProgressLogSource -notmatch 'providerFinishReason' -or
    $agentHostRuntimeProgressLogSource -notmatch 'providerResponseModel' -or
    $agentHostRuntimeProgressLogSource -notmatch 'providerResponsePromptTokens' -or
    $agentHostRuntimeProgressLogSource -notmatch 'providerResponseContentCharacters' -or
    $agentHostProviderSource -notmatch 'ReadSafeProviderErrorMetadataAsync' -or
    $agentHostProviderSource -notmatch 'providerToolCallsPresent: hasToolCalls' -or
    $agentHostRuntimeProgressLogSource -notmatch 'providerRequestBodyBytes' -or
    $agentHostRuntimeProgressLogSource -notmatch 'providerFailureEventsWithoutUsage' -or
    $agentHostRuntimeProgressLogSource -notmatch 'providerFailureEventsWithUsage' -or
    $agentHostRuntimeProgressLogSource -notmatch 'providerFailurePromptTokens' -or
    $agentHostRuntimeProgressLogSource -notmatch 'totalObservedPromptTokens' -or
    $agentHostRuntimeProgressLogSource -notmatch 'overallTokenUsageComplete' -or
    $agentHostRuntimeProgressLogSource -notmatch 'overallCostEstimateComplete' -or
    $agentHostRuntimeProgressLogSource -notmatch 'promptCacheHitRatioFromRows' -or
    $agentHostRuntimeProgressLogSource -notmatch 'provider-decision-and-failure-log-rows' -or
    $agentHostRuntimeProgressLogSource -notmatch 'RecordBudgetReservationRejected' -or
    $agentHostHarnessProgressTraceSource -notmatch 'provider-budget-reservation-rejected' -or
    $agentHostHarnessProgressTraceSource -notmatch 'providerResponseRequestId' -or
    $agentHostHarnessProgressTraceSource -notmatch 'providerFallbackAttempts' -or
    $agentHostHarnessProgressTraceSource -notmatch 'providerFallbackTrail' -or
    $agentHostHarnessProgressTraceSource -notmatch 'host-progress-trace-provider-tool-shape' -or
    $agentHostHarnessProgressTraceSource -notmatch 'BuildProviderFailureRequestDiagnostics' -or
    $agentHostHarnessProgressTraceSource -notmatch 'provider-progress-trace-records-request-prompt-size-and-listed-action-names-without-content' -or
    $agentHostRuntimeProgressLogSource -notmatch 'systemPromptBytes' -or
    $agentHostRuntimeProgressLogSource -notmatch 'allowedActionNames' -or
    $agentHostHarnessProgressTraceSource -notmatch 'providerResponseCompletionTokens' -or
    $agentHostHarnessProgressTraceSource -notmatch 'providerDecisionFieldShape' -or
    $agentHostRuntimeProgressLogSource -notmatch 'providerDecisionFieldShape' -or
    $agentHostProviderContractSelfTestSource -notmatch 'provider-decision-ambiguity-retains-safe-field-shape' -or
    $agentHostProviderContractSelfTestSource -notmatch 'provider-goal-control-accepts-only-empty-uniform-arguments-envelope' -or
    $agentHostProviderContractSelfTestSource -notmatch 'provider-self-test-listed-tool-alias-action-failed' -or
    $agentHostProviderContractSelfTestSource -notmatch 'provider-self-test-listed-tool-alias-control-failed' -or
    $agentHostProviderContractSelfTestSource -notmatch 'provider-self-test-unlisted-tool-alias-accepted' -or
    $agentHostEstablishClanAutonomySource -notmatch 'establish-clan-autonomy-replans-stalled-move-when-target-is-not-in-current-safe-map-list' -or
    $agentHostEstablishClanAutonomySource -notmatch 'stalledMoveTargetsMissingFromVisibleMapDays' -or
    $agentHostEstablishClanAutonomySource -notmatch 'safeSettlementRefreshQueued' -or
    $agentHostCampaignLoopSource -notmatch 'campaign-loop-safe-settlement-refresh-can-reselect-from-current-map-when-stalled-target-is-unavailable' -or
    $agentHostCampaignLoopSource -notmatch 'safeSettlementArrivalOnly\)' -or
    $agentHostHarnessProgressTraceSource -notmatch 'providerProxyEndpointHostPort' -or
    $agentHostHarnessProgressTraceSource -notmatch 'host-progress-trace-provider-failure' -or
    $agentHostRuntimeControllerSource -notmatch 'CHRONICLE_LLM_PROXY_SELECTION_SOURCE' -or
    $agentHostRuntimeControllerSource -notmatch 'ProviderProxySelection\.IsNoProxyMatch' -or
    $agentHostProviderSource -notmatch 'ReadProxySelectionSourceOverride' -or
    $agentHostProviderSource -notmatch 'proxyUri\.Host \+ ":"' -or
    $agentHostRuntimeProgressLogSource -notmatch 'RunContractSelfTests' -or
    $agentHostRuntimeProgressLogSource -notmatch 'promptsLogged.*false' -or
    $agentHostRuntimeProgressLogSource -notmatch 'credentialsLogged.*false' -or
    $agentHostRuntimeProgressLogSource -notmatch '\["partyFoodChange"\]' -or
    $agentHostRuntimeProgressLogSource -notmatch '\["encounteredPartyId"\]' -or
    $agentHostRuntimeProgressLogSource -notmatch '\["inquiryTitle"\]' -or
    $agentHostRuntimeProgressLogSource -notmatch 'BuildPartyScreenSummary' -or
    $agentHostHarnessProgressTraceSource -notmatch 'host-progress-trace-party-state-self-test' -or
    $agentHostHarnessProgressTraceSource -notmatch 'host-progress-trace-party-screen-context-self-test' -or
    $agentHostHarnessProgressTraceSource -notmatch 'SummarizeAllowedActionNames' -or
    $agentHostHarnessProgressTraceSource -notmatch '\["partyDefaultBehavior"\]' -or
    $agentHostRuntimeControllerSource -notmatch 'AgentHostUsageSignalPrefix' -or
    $agentHostRuntimeControllerSource -notmatch 'BuildProviderUsageSummary' -or
    $agentHostRuntimeControllerSource -notmatch 'UpdateProviderUsage' -or
    $providerSettingsSource -notmatch 'AgentRuns' -or
    $agentHostRuntimeProgressLogSource -notmatch 'runtime-progress-log-preserves-cost-usage-without-prompts-responses-or-argument-values-including-numbered-subflows') {
    throw 'Normal MCM runs must record bounded per-decision token/cache/cost diagnostics without prompts or credentials, expose current usage to ViewAgentStatus, and retain an owned rotating local log.'
}
if ($agentHostCampaignLoopSource -notmatch 'goalValid=' -or
    $agentHostCampaignLoopSource -notmatch 'missingApproved=\[' -or
    $agentHostLifecycleReceiptSource -notmatch 'bool\? FirstDecisionRequiresGoalClassification' -or
    $agentHostLifecycleReceiptSource -notmatch 'long\? PromptTokens') {
    throw 'Rejected Campaign request receipts must preserve safe validation details even when the Host has not produced decision metrics.'
}
if ($agentHostRuntimeControllerSource -notmatch 'CHRONICLE_LLM_BASE_URL' -or
    $agentHostRuntimeControllerSource -notmatch 'useHarnessProviderEnvironment' -or
    $agentHostRuntimeControllerSource -notmatch 'harness-environment-override' -or
    $agentHostRuntimeControllerSource -notmatch 'CHRONICLE_LLM_OUTPUT_MODE' -or
    $agentHostRuntimeControllerSource -notmatch 'CHRONICLE_LLM_MAX_RUN_COST_CNY' -or
    $agentHostProviderSource -notmatch 'providerConfigurationSource' -or
    $agentHostCampaignLoopSource -notmatch 'missingApproved=\[' -or
    $agentHostLifecycleReceiptSource -notmatch 'bool\? FirstDecisionRequiresGoalClassification') {
    throw 'An explicit lifecycle Harness provider override must be forwarded into the Host request without changing the saved MCM provider profile.'
}
if ($agentHostProviderSource -notmatch 'choiceCount=' -or
    $agentHostProviderSource -notmatch 'hasToolCalls=' -or
    $agentHostProviderSource -notmatch 'contentKind=' -or
    $agentHostProviderSource -notmatch 'finishReason=') {
    throw 'A malformed OpenAI-compatible response must report only its structural envelope, never prompt or response body, to separate provider-format failures from Host decision failures.'
}
