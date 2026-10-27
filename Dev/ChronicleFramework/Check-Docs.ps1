[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$harnessRoot = $PSScriptRoot
$localSettingsPath = Join-Path $harnessRoot 'harness.local.json'
$localSettings = if (Test-Path -LiteralPath $localSettingsPath) { Get-Content -LiteralPath $localSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
$projectRoot = if ($localSettings -and $localSettings.repositoryRoot) { [IO.Path]::GetFullPath([string]$localSettings.repositoryRoot) } else { Split-Path -Parent (Split-Path -Parent $harnessRoot) }
$contractVersion = '7.401'
$contextState = Get-Content (Join-Path $harnessRoot 'ContextState.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$taskTrackerUrl = [string]$contextState.taskTracker.projectUrl
$requiredRootPaths = @('DEVELOPMENT.md', 'DESIGN.md', 'SYSTEM_INVENTORY.md')
$routedPaths = @(
    $requiredRootPaths
    @($contextState.defaultRead | ForEach-Object { [string]$_ })
    @([string]$contextState.current.path)
    @($contextState.references | ForEach-Object { [string]$_.path })
    @($contextState.archives | ForEach-Object { [string]$_ })
) | ForEach-Object { ([string]$_).Replace('/', '\') } | Sort-Object -Unique

# AGENTS.md is an injected work-rules file, not a content document routed through ContextState.
$actualFiles = @(Get-ChildItem -Path $harnessRoot -Recurse -File -Filter '*.md' | Where-Object {
    $_.FullName -notmatch '[\\/](TestResults|obj|bin)[\\/]' -and
    $_.FullName -ne (Join-Path $harnessRoot 'AGENTS.md')
})
$actualRelativePaths = @($actualFiles | ForEach-Object { $_.FullName.Substring($harnessRoot.Length + 1).Replace('/', '\') })
$unexpected = @($actualRelativePaths | Where-Object { $_ -notin $routedPaths })
$missing = @($routedPaths | Where-Object { $_ -notin $actualRelativePaths })
if ($unexpected.Count -gt 0) { throw "Unrouted Markdown files found; add each to ContextState and SYSTEM_INVENTORY routing: $($unexpected -join ', ')" }
if ($missing.Count -gt 0) { throw "Routed Markdown files are missing: $($missing -join ', ')" }
$researchFiles = @($actualRelativePaths | Where-Object { $_ -match '^Research\\[^\\]+\\.+\.md$' })
$researchCategories = @($researchFiles | ForEach-Object { [regex]::Match($_, '^Research\\([^\\]+)\\').Groups[1].Value } | Group-Object)
foreach ($category in $researchCategories) {
    if ($category.Count -gt 1) { throw "Research category '$($category.Name)' has multiple Markdown sources; consolidate unless the user approved a deliberate split." }
}
${activeFiles} = @($actualFiles | Where-Object { $_.FullName -notlike '*\Archive\*' })
$totalBytes = ($actualFiles | Measure-Object Length -Sum).Sum
$defaultReadPaths = @($contextState.defaultRead | ForEach-Object { ([string]$_).Replace('/', '\') })
$defaultReadBytes = ($actualFiles | Where-Object { $_.FullName.Substring($harnessRoot.Length + 1).Replace('/', '\') -in $defaultReadPaths } | Measure-Object Length -Sum).Sum
$harnessPowerShellFiles = @(Get-ChildItem -Path $harnessRoot -Recurse -File -Filter '*.ps1' | Where-Object { $_.FullName -notlike '*\TestResults\*' })
foreach ($scriptFile in $harnessPowerShellFiles) {
    $scriptBytes = [IO.File]::ReadAllBytes($scriptFile.FullName)
    $hasUtf8Bom = $scriptBytes.Length -ge 3 -and $scriptBytes[0] -eq 0xEF -and $scriptBytes[1] -eq 0xBB -and $scriptBytes[2] -eq 0xBF
    $hasNonAscii = @($scriptBytes | Where-Object { $_ -ge 0x80 }).Count -gt 0
    if ($hasNonAscii -and -not $hasUtf8Bom) { throw "PowerShell 5.1 source has non-ASCII text without a UTF-8 BOM: $($scriptFile.Name). Keep script literals ASCII or add a BOM." }
}

$harnessScript = Get-Content (Join-Path $harnessRoot 'Run-Harness.ps1') -Raw -Encoding UTF8
$harnessStartupEvidenceSource = Get-Content (Join-Path $harnessRoot 'HarnessStartupEvidence.ps1') -Raw -Encoding UTF8
$testResultsRetentionScript = Join-Path $harnessRoot 'Prune-TestResults.ps1'
$agentCliSource = Get-Content (Join-Path $harnessRoot 'Agent-Cli.ps1') -Raw -Encoding UTF8
$testCampaignSource = Get-Content (Join-Path $harnessRoot 'Test-Campaign.ps1') -Raw -Encoding UTF8
$testWindowLayoutSource = Get-Content (Join-Path $harnessRoot 'Test-WindowLayout.ps1') -Raw -Encoding UTF8
$shaderDialogSource = Get-Content (Join-Path $harnessRoot 'HarnessShaderCacheDialog.ps1') -Raw -Encoding UTF8
$agentProtocolSource = Get-Content (Join-Path $harnessRoot 'AgentProtocol.cs') -Raw -Encoding UTF8
$subModuleSource = Get-Content (Join-Path $harnessRoot 'SubModule.cs') -Raw -Encoding UTF8
$agentObserverSource = Get-Content (Join-Path $harnessRoot 'AgentObserver.cs') -Raw -Encoding UTF8
if ([regex]::Matches($agentObserverSource, 'isWaitMenu').Count -ne 1 -or [regex]::Matches($agentObserverSource, 'isWaitActive').Count -ne 1) { throw 'The Native observer must emit each Wait-menu fact exactly once; duplicate JSON keys can make the Host fail before any model decision.' }
$storyModeLifecycleStatusSource = Get-Content (Join-Path $harnessRoot 'StoryModeEstablishClanLifecycleStatus.cs') -Raw -Encoding UTF8
$agentDecisionLoopSource = Get-Content (Join-Path $harnessRoot 'Agent-DecisionLoop.ps1') -Raw -Encoding UTF8
$agentProviderBudgetSource = Get-Content (Join-Path $harnessRoot 'Agent-ProviderBudget.ps1') -Raw -Encoding UTF8
$agentDecisionLoopPolicySource = Get-Content (Join-Path $harnessRoot 'Agent-DecisionLoopPolicy.ps1') -Raw -Encoding UTF8
$nativeRejectedActionBranch = [regex]::Match($agentDecisionLoopSource, 'if \(\$actionResult.status -notin @\(''completed'',''accepted''\)\)(?<branch>[\s\S]*?)(?=\$stepTiming.observationStartedUtc)').Groups['branch'].Value
$agentDecisionTestProviderSource = Get-Content (Join-Path $harnessRoot 'Test-AgentLoopProvider.ps1') -Raw -Encoding UTF8
$agentDecisionLoopTestSource = Get-Content (Join-Path $harnessRoot 'Test-AgentLoop.ps1') -Raw -Encoding UTF8
$agentOpenAiProviderSource = Get-Content (Join-Path $harnessRoot 'Agent-OpenAICompatibleProvider.ps1') -Raw -Encoding UTF8
$freeLlmApiProfileSource = Get-Content (Join-Path $harnessRoot 'Get-FreeLLMAPIProfile.ps1') -Raw -Encoding UTF8
$agentOpenAiProviderTestSource = Get-Content (Join-Path $harnessRoot 'Test-AgentOpenAICompatibleProvider.ps1') -Raw -Encoding UTF8
$agentEvaluationLiveModelSupplySource = Get-Content (Join-Path $harnessRoot 'Test-AgentEvaluationLiveModelSupply.ps1') -Raw -Encoding UTF8
$agentHostCampaignLoopSource = Get-Content (Join-Path $harnessRoot 'AgentHost\AgentHostCampaignLoop.cs') -Raw -Encoding UTF8
$agentHostSupplyLoopSource = Get-Content (Join-Path $harnessRoot 'AgentHost\AgentHostSupplyLoop.cs') -Raw -Encoding UTF8
$agentHostDecisionCycleSource = Get-Content (Join-Path $harnessRoot 'AgentHost\AgentHostDecisionCycle.cs') -Raw -Encoding UTF8
$agentHostEstablishClanPlannerSource = Get-Content (Join-Path $harnessRoot 'AgentHost\AgentHostEstablishYourClanGoalLoop.cs') -Raw -Encoding UTF8
$agentHostEstablishClanAutonomySource = Get-Content (Join-Path $harnessRoot 'AgentHost\AgentHostEstablishYourClanAutonomyLoop.cs') -Raw -Encoding UTF8
$agentHostStoryModeBootstrapLoopSource = Get-Content (Join-Path $harnessRoot 'AgentHost\AgentHostStoryModeBootstrapLoop.cs') -Raw -Encoding UTF8
$agentHostHarnessProgressTraceSource = Get-Content (Join-Path $harnessRoot 'AgentHost\AgentHostHarnessProgressTrace.cs') -Raw -Encoding UTF8
$agentHostProviderContractSelfTestSource = Get-Content (Join-Path $harnessRoot 'AgentHost\ProviderContractSelfTest.cs') -Raw -Encoding UTF8
$agentHostProviderSource = Get-Content (Join-Path $harnessRoot 'AgentHost\OllamaNativeProvider.cs') -Raw -Encoding UTF8
$agentHostRuntimeControllerSource = Get-Content (Join-Path $harnessRoot 'AgentHostRuntimeController.cs') -Raw -Encoding UTF8
$agentPlayerInputOwnershipSource = Get-Content (Join-Path $harnessRoot 'AgentPlayerInputOwnership.cs') -Raw -Encoding UTF8
$agentHostLifecycleReceiptSource = Get-Content (Join-Path $harnessRoot 'AgentHostLifecycleReceipt.cs') -Raw -Encoding UTF8
$agentHostLifecycleEvaluationSource = Get-Content (Join-Path $harnessRoot 'Test-AgentHostLifecycleEvaluation.ps1') -Raw -Encoding UTF8
$freshCampaignTest = Get-Content (Join-Path $harnessRoot 'Test-AgentFreshCampaign.ps1') -Raw -Encoding UTF8
$deepSeekTokenEstimatorSource = Get-Content (Join-Path $harnessRoot 'AgentHost\DeepSeekPromptTokenEstimator.cs') -Raw -Encoding UTF8
$deepSeekTokenizerAsset = Join-Path $harnessRoot 'AgentHost\Resources\deepseek_v4_tokenizer.zip'
$deepSeekTokenizerLicense = Join-Path $harnessRoot 'AgentHost\Resources\DeepSeekV4Tokenizer-LICENSE.txt'
$agentHostDecisionCycleSource = Get-Content (Join-Path $harnessRoot 'AgentHost\AgentHostDecisionCycle.cs') -Raw -Encoding UTF8
$agentHostCampaignLoopEvaluationSource = Get-Content (Join-Path $harnessRoot 'Test-AgentHostCampaignLoopEvaluation.ps1') -Raw -Encoding UTF8
$agentHostLiveModelLoopSource = Get-Content (Join-Path $harnessRoot 'Test-AgentLiveModelLoop.ps1') -Raw -Encoding UTF8
$agentHostBattleSimulationLoopSource = Get-Content (Join-Path $harnessRoot 'AgentHost\AgentHostBattleSimulationLoop.cs') -Raw -Encoding UTF8
$agentHostCampaignStateFactsSource = Get-Content (Join-Path $harnessRoot 'AgentHost\AgentHostCampaignStateFacts.cs') -Raw -Encoding UTF8
$agentHostCompanionLoopSource = Get-Content (Join-Path $harnessRoot 'AgentHost\AgentHostEstablishClanCompanionLoop.cs') -Raw -Encoding UTF8
$agentHostRecruitmentLoopSource = Get-Content (Join-Path $harnessRoot 'AgentHost\AgentHostEstablishClanRecruitmentLoop.cs') -Raw -Encoding UTF8
if ($agentHostRecruitmentLoopSource -notmatch 'MaxDecisions = AgentHostCampaignLoop\.MaxCumulativeDecisions' -or $agentHostRecruitmentLoopSource -notmatch 'TimeSpan\.FromHours\(2\)' -or $agentHostRecruitmentLoopSource -notmatch 'establish-clan-recruitment-budget-mismatch') { throw 'PartySize execution must share the autonomous EYC parent cumulative-decision budget and 2-hour limit so a child loop cannot terminate early.' }
$agentHostCaptivityRecoveryLoopSource = Get-Content (Join-Path $harnessRoot 'AgentHost\AgentHostCaptivityRecoveryLoop.cs') -Raw -Encoding UTF8
$agentHostGoldSaleLoopSource = Get-Content (Join-Path $harnessRoot 'AgentHost\AgentHostEstablishClanGoldSaleLoop.cs') -Raw -Encoding UTF8
$agentHostMailboxSource = Get-Content (Join-Path $harnessRoot 'AgentHost\NativeMailboxClient.cs') -Raw -Encoding UTF8
$agentHostInquiryResolutionSource = Get-Content (Join-Path $harnessRoot 'AgentHost\AgentHostNativeInquiryResolution.cs') -Raw -Encoding UTF8
$agentHostVillageToolsQuestLoopSource = Get-Content (Join-Path $harnessRoot 'AgentHost\AgentHostVillageToolsQuestLoop.cs') -Raw -Encoding UTF8
$agentHostVillageToolsQuestPolicySource = Get-Content (Join-Path $harnessRoot 'AgentHost\AgentHostVillageToolsQuestPolicy.cs') -Raw -Encoding UTF8
$agentHostVillageToolsFixturePreparationSource = Get-Content (Join-Path $harnessRoot 'Test-AgentVillageToolsQuestFixturePreparation.ps1') -Raw -Encoding UTF8
$agentHostPackageSource = Get-Content (Join-Path $harnessRoot 'Test-AgentHostPackage.ps1') -Raw -Encoding UTF8
if ($agentHostPackageSource -notmatch "SelectNodes\('//PackageReference'\)" -or
    $agentHostPackageSource -notmatch "Microsoft.ML.Tokenizers" -or
    $agentHostPackageSource -notmatch "Version -ne '\[2.0.1\]'" -or
    $agentHostPackageSource -notmatch 'packages.lock.json' -or
    $agentHostPackageSource -notmatch 'RestoreLockedMode=true' -or
    $agentHostPackageSource -notmatch "-match 'NU1900'") { throw 'NuGet audit fallback must reject every Host dependency except the single pinned Microsoft.ML.Tokenizers 2.0.1 package.' }
$agentHostProviderSelfTestSource = Get-Content (Join-Path $harnessRoot 'AgentHost\ProviderContractSelfTest.cs') -Raw -Encoding UTF8
$agentHostProviderSmokeSource = Get-Content (Join-Path $harnessRoot 'Test-AgentHostProvider.ps1') -Raw -Encoding UTF8
if ($agentOpenAiProviderSource -notmatch "reason = 'invalid-action-arguments'" -or $agentOpenAiProviderSource -notmatch 'unsupportedArguments' -or $agentDecisionLoopSource -notmatch 'invalid-action-arguments' -or $agentDecisionLoopSource -notmatch 'noNativeActionSent' -or $agentOpenAiProviderTestSource -notmatch 'UnsupportedActionArgumentReturnsRecoverableRejection' -or $agentDecisionLoopTestSource -notmatch 'InvalidActionArgumentsRecoverWithoutNativeMutation' -or $agentDecisionTestProviderSource -notmatch 'invalidArgumentRecovery') { throw 'Unsupported model argument names must be rejected before Native, passed back with a fresh state, and covered in the provider and loop regressions.' }
if ($agentOpenAiProviderSource -notmatch '\$argumentShapeDepth' -or $agentOpenAiProviderSource -notmatch 'allowedArguments.Count -eq 1' -or $agentOpenAiProviderSource -notmatch 'ConvertFrom-Json -ErrorAction Stop' -or $agentOpenAiProviderTestSource -notmatch 'StringEncodedObjectArgumentsNormalized' -or $agentOpenAiProviderTestSource -notmatch 'SingleStringArrayArgumentsNormalized' -or $agentOpenAiProviderTestSource -notmatch 'NestedStringArrayArgumentsNormalized' -or $agentOpenAiProviderTestSource -notmatch 'SingleScalarArgumentsNormalized') { throw 'The local OpenAI-compatible provider must normalize bounded nested JSON wrappers and unambiguous one-field scalars through the same field allowlist and regression tests.' }
if ($agentOpenAiProviderSource -notmatch 'schemaVersion -ne 3' -or $agentOpenAiProviderSource -notmatch 'recentDecisionHistory = \$request\.recentDecisionHistory' -or $agentOpenAiProviderSource -notmatch 'completionContract = \$request\.completionContract' -or $agentOpenAiProviderSource -notmatch 'exact Native completion contract' -or $agentOpenAiProviderSource -notmatch 'bounded recentDecisionHistory' -or $agentOpenAiProviderSource -notmatch 'attempt=\$attempt/\$maxAttempts' -or $agentOpenAiProviderSource -notmatch 'CHRONICLE_LLM_PROTOCOL' -or $agentOpenAiProviderSource -notmatch 'ollama-native' -or $agentOpenAiProviderSource -notmatch '/api/chat' -or $agentOpenAiProviderSource -notmatch 'CHRONICLE_HARNESS_PROVIDER_MODE' -or $agentOpenAiProviderSource -notmatch 'FREELLMAPI_API_KEY' -or $agentOpenAiProviderSource -notmatch '31415' -or $agentOpenAiProviderSource -notmatch 'CHRONICLE_LLM_THINKING_MODE' -or $agentOpenAiProviderSource -notmatch 'payload\.thinking' -or $agentOpenAiProviderSource -notmatch "scope = 'trade-transaction'" -or $agentOpenAiProviderSource -notmatch 'observationScope = \$observationScope' -or $agentOpenAiProviderSource -notmatch "modelView -ceq 'campaign-multiday-supply'" -or $agentOpenAiProviderSource -notmatch "decision.action -ceq 'done'" -or $agentOpenAiProviderSource -notmatch 'A stop proposal cannot include action arguments' -or $agentOpenAiProviderTestSource -notmatch 'ActionDoneAliasNormalizesToStopProposal' -or $agentOpenAiProviderTestSource -notmatch 'TradeObservationCompactionWithinBudget' -or $agentOpenAiProviderTestSource -notmatch 'MultiDaySupplyProfileFitsRequestBudget' -or $agentOpenAiProviderTestSource -notmatch 'OllamaNativeProtocolNormalizesUsage' -or $agentOpenAiProviderTestSource -notmatch 'RecentDecisionHistoryForwarded' -or $agentOpenAiProviderTestSource -notmatch 'PreResponseConnectionFailureRetriesOnceAndClassifies' -or $agentOpenAiProviderTestSource -notmatch 'RequestFormatCorrect' -or $agentOpenAiProviderTestSource -notmatch "CHRONICLE_HARNESS_PROVIDER_MODE = 'protocol-stub'") { throw 'The PowerShell provider must restrict live calls to FreeLLMAPI, permit alternate loopback endpoints only inside the explicit protocol-stub harness, and preserve the structured-decision contract.' }
if ($agentDecisionLoopPolicySource -notmatch 'function Get-BarterActionGate' -or $agentDecisionLoopSource -notmatch 'BalancedBarterSessionId' -or $agentDecisionLoopSource -notmatch 'Get-BarterActionGate' -or $agentDecisionLoopTestSource -notmatch 'BarterActionCatalogStagesCurrentNativeQuote') { throw 'A current native barter session must expose a staged quote workflow and prevent repeated auto-balance/read loops.' }
if ($agentDecisionLoopPolicySource -notmatch 'function Get-TradeActionGate' -or $agentDecisionLoopPolicySource -notmatch 'function Get-CurrentMenuSelectionContext' -or $agentDecisionLoopPolicySource -notmatch 'function Get-NativeRestActionGate' -or $agentDecisionLoopSource -notmatch 'Get-TradeActionGate' -or $agentDecisionLoopSource -notmatch 'Get-CurrentMenuSelectionContext' -or $agentDecisionLoopSource -notmatch 'Get-NativeRestActionGate' -or $agentDecisionLoopSource -notmatch "menuSelect = @\('OptionId'\)" -or $agentDecisionLoopSource -notmatch 'ReturnWhenAccepted' -or $agentDecisionLoopSource -notmatch "validated.Action -ceq 'rest'" -or $agentDecisionLoopTestSource -notmatch 'MenuAndTradeActionCatalogFollowsCurrentNativeContext' -or $agentDecisionLoopTestSource -notmatch 'ObserveAgainDuringUncommittedTradeIsRecoverable' -or $agentDecisionLoopTestSource -notmatch 'NativeRestRequestIsSingleUsePerWait') { throw 'Campaign menu selection must bind an observed enabled OptionId to the current Native menu; Trade actions must be staged by current Native context; uncommitted Trade must reject ObserveAgain safely; and rest must be a single asynchronous accepted request per Town Wait.' }
if ($agentOpenAiProviderSource -notmatch 'For `menuSelect`, set `arguments\.OptionId` to the exact `id` value' -or $agentOpenAiProviderSource -notmatch 'For `provision`, set `arguments\.ItemViewModelId` to the exact `viewModelItemId`' -or $agentOpenAiProviderSource -notmatch '`provision` only drafts a TradeVM transaction' -or $agentOpenAiProviderTestSource -notmatch 'nativeArgumentPromptBindingsPresent' -or $agentDecisionLoopSource -notmatch 'decision-validation-failed-before-native' -or $agentDecisionLoopSource -notmatch 'control-validation-failed-before-wait' -or $agentDecisionLoopSource -notmatch 'noNativeActionSent = \$true') { throw 'The model prompt must bind Native menu/trade fields to observed values and transaction phases, and failed pre-Native action/control validation must retain the decision and no-dispatch evidence.' }
if ($agentDecisionLoopPolicySource -notmatch 'function Convert-SupplyObservationForDecision' -or $agentDecisionLoopPolicySource -notmatch 'function Convert-SupplyReceiptForDecision' -or $agentDecisionLoopPolicySource -notmatch 'inventoryLogicUnitPrice' -or $agentDecisionLoopPolicySource -notmatch 'isTransferable' -or $agentDecisionLoopSource -notmatch 'campaign-multiday-supply' -or $agentDecisionLoopTestSource -notmatch 'SupplyObservationProfileCompactsAndKeepsNativeContext' -or $agentOpenAiProviderSource -notmatch 'multi-day supply task' -or $agentOpenAiProviderTestSource -notmatch 'MultiDaySupplyProfileFitsRequestBudget' -or $agentOpenAiProviderTestSource -notmatch 'NativeFoodQuoteFieldsRetained') { throw 'The scoped supply prompt and quote receipt must fit the request budget while retaining exact Native IDs, stock, quoted prices, food/transferability, and transaction context.' }
if ($agentDecisionLoopPolicySource -notmatch 'function Get-NativeRestMonitorTarget' -or $agentDecisionLoopPolicySource -notmatch 'function Test-NativeRestMonitorNeeded' -or $agentDecisionLoopSource -notmatch 'native-rest-monitor-\$index' -or $agentDecisionLoopSource -notmatch 'nativeClockControlSent = \$false' -or $agentDecisionLoopTestSource -notmatch 'NativeRestMonitorCoalescesWaitPolling') { throw 'After an accepted Native rest action, the loop must monitor its requested daily-tick target with read-only observations, preserve a wall-clock bound, and record that it sent no native clock or game action.' }
if ($agentDecisionLoopPolicySource -notmatch 'function Test-AgentGoalCompletion' -or $agentDecisionLoopPolicySource -notmatch 'dailyTickCount' -or $agentDecisionLoopSource -notmatch 'CompletionContractBase64' -or $agentDecisionLoopSource -notmatch 'goal-verification-rejected' -or $agentDecisionLoopSource -notmatch 'verified-complete' -or $agentDecisionLoopSource -notmatch 'goalVerified' -or $agentOpenAiProviderSource -notmatch 'goal-verification-unknown' -or $agentOpenAiProviderSource -notmatch 'Never claim completion while the contract is unmet or unknown' -or $agentDecisionTestProviderSource -notmatch 'goalVerifierRejectedDone' -or $agentDecisionTestProviderSource -notmatch 'goalVerifierResume' -or $agentDecisionLoopTestSource -notmatch 'GoalVerifierEarlyDoneRecoveryVerified' -or $agentDecisionLoopTestSource -notmatch 'GoalCheckpointRoundtripResumeVerified') { throw 'A bounded Native goal contract must reject premature provider stop, return exact unmet/unknown evidence for another decision, persist across a Native save/load, and remain deterministically regression-tested.' }
if ($agentProviderBudgetSource -notmatch 'function New-AgentProviderBudget' -or $agentProviderBudgetSource -notmatch 'function Get-AgentProviderBudgetFingerprint' -or $agentProviderBudgetSource -notmatch 'function New-AgentProviderBudgetState' -or $agentProviderBudgetSource -notmatch 'function Test-AgentProviderBudgetState' -or $agentProviderBudgetSource -notmatch 'deepseek-v4\.1-flash-peak-cny-upper-bound-2026-10' -or $agentProviderBudgetSource -notmatch 'priceVerifiedOn = ''2026-10-10''' -or $agentProviderBudgetSource -notmatch 'inputTokenFramingReserveTokens = 128' -or $agentProviderBudgetSource -notmatch 'maxTotalInputTokens' -or $agentProviderBudgetSource -notmatch 'function Get-AgentProviderActualCostBreakdown' -or $agentProviderBudgetSource -notmatch 'No verified price profile exists' -or $agentDecisionLoopSource -notmatch 'provider-budget-exhausted-before-request' -or $agentDecisionLoopSource -notmatch 'maxInputTokensPerRequest = \[int\]\$script:AgentProviderBudget\.maxInputTokensPerRequest' -or $agentDecisionLoopSource -notmatch 'providerBudgetFingerprint' -or $agentDecisionLoopSource -notmatch 'pendingProviderCall' -or $agentDecisionLoopSource -notmatch 'reservedCostUpperBoundCny' -or $agentDecisionLoopSource -notmatch 'estimatedInputCacheHitCostCny' -or $agentDecisionLoopSource -notmatch 'estimatedInputCacheMissCostCny' -or $agentDecisionLoopSource -notmatch 'estimatedOutputCostCny' -or $agentDecisionLoopSource -notmatch 'provider-reported-usage-exceeded-budget' -or $agentOpenAiProviderSource -notmatch 'totalTokensConsistent' -or $agentOpenAiProviderSource -notmatch 'requestBodyBytes' -or $agentOpenAiProviderSource -notmatch 'promptCacheHitTokens' -or $agentOpenAiProviderSource -notmatch 'maxAttempts = if \(\$requestBudget -and \$requestBudget\.mode -eq ''priced-provider''\)' -or $agentOpenAiProviderTestSource -notmatch 'PaidProviderBudgetDisablesRetry' -or $agentOpenAiProviderTestSource -notmatch 'ProviderBudgetMathAndUnknownPriceFailClosed' -or $agentOpenAiProviderTestSource -notmatch 'ProviderReportedUsageCostBreakdown' -or $agentOpenAiProviderTestSource -notmatch 'UsageReceiptAccurate' -or $agentOpenAiProviderTestSource -notmatch 'MissingUsageNotTreatedAsZero' -or $agentDecisionLoopTestSource -notmatch 'ProviderBudgetStopsBeforeUnaffordableRequest' -or $agentDecisionLoopTestSource -notmatch 'ProviderReportedUsageOverrunStopsBeforeNativeAction' -or $agentDecisionLoopTestSource -notmatch 'checkpointBudgetRoundtripVerified' -or $agentDecisionTestProviderSource -notmatch 'reportedUsageOverBudget' -or $agentEvaluationLiveModelSupplySource -notmatch 'providerUsageAuditComplete' -or $agentEvaluationLiveModelSupplySource -notmatch 'usageUnavailableCalls -eq 0') { throw 'Provider usage must be auditable, missing usage cannot become zero, unpriced remote models fail closed, paid calls cannot retry outside their reservation, actual usage must be itemized and rechecked, budget profiles must persist across checkpoint resume, and per-run input/output/cost/request budgets must stop before any unaffordable model call.' }
if ($agentProviderBudgetSource -notmatch 'function Get-AgentProviderBudgetLedgerPath' -or $agentProviderBudgetSource -notmatch 'function Read-AgentProviderBudgetLedger' -or $agentProviderBudgetSource -notmatch 'function Merge-AgentProviderBudgetStates' -or $agentProviderBudgetSource -notmatch 'function Write-AgentProviderBudgetLedger' -or $agentDecisionLoopSource -notmatch 'CHRONICLE_PROVIDER_BUDGET_LEDGER_ROOT' -or $agentDecisionLoopSource -notmatch 'Sync-AgentProviderBudgetLedger' -or $agentOpenAiProviderTestSource -notmatch 'DurableBudgetLedgerPersistsPendingSpend') { throw 'Every billable task must have a durable host-side metadata-only budget ledger, merge newer ledger reservations over restored saves, and verify that pending charges cannot be refunded by task resume.' }
if ($agentProviderBudgetSource -notmatch 'File\]::Replace' -or $agentDecisionLoopSource -notmatch 'Get-SafeProviderErrorSummary' -or $agentDecisionLoopSource -notmatch 'response body omitted' -or $agentDecisionLoopSource -notmatch 'requestAttemptsUnavailableCalls' -or $agentDecisionLoopSource -notmatch 'requestAttemptsStatus = ''unknown''' -or $agentDecisionLoopSource -notmatch 'Write-AgentProviderBudgetLedger' -or $agentDecisionLoopSource -notmatch 'Initialize-AgentProviderBudgetLedger' -or $agentDecisionLoopSource -notmatch 'checkpoint-recovered-uncertain-provider-call' -or $agentDecisionLoopTestSource -notmatch 'checkpointBudgetRoundtripVerified' -or $agentDecisionLoopTestSource -notmatch 'ProviderBudgetCheckpointLedgerRoundtripVerified' -or $agentDecisionLoopTestSource -notmatch 'ProviderBudgetExhaustedAcrossCheckpointResume' -or $agentDecisionLoopTestSource -notmatch 'goalResumeTrace\.providerBudget\.reservedProviderCalls') { throw 'Budget reservations must be durable and resumable; unknown HTTP attempts cannot become zero, and error summaries must omit provider response bodies.' }
$agentLiveModelLoopSource = Get-Content (Join-Path $harnessRoot 'Test-AgentLiveModelLoop.ps1') -Raw -Encoding UTF8
$persistentEycCampaignSource = Get-Content (Join-Path $harnessRoot 'Test-AgentPersistentStoryModeCampaign.ps1') -Raw -Encoding UTF8
$agentHostCampaignLoopEvaluationSource = Get-Content (Join-Path $harnessRoot 'Test-AgentHostCampaignLoopEvaluation.ps1') -Raw -Encoding UTF8
if ($agentLiveModelLoopSource -notmatch 'ProviderProtocol' -or $agentLiveModelLoopSource -notmatch 'CHRONICLE_LLM_PROTOCOL' -or $agentLiveModelLoopSource -notmatch 'isFreeLlmApi' -or $agentLiveModelLoopSource -notmatch 'FREELLMAPI_API_KEY' -or $agentLiveModelLoopSource -notmatch 'available=true' -or $agentLiveModelLoopSource -notmatch 'configured provider model-list preflight' -or $agentLiveModelLoopSource -notmatch 'remote OpenAI-compatible provider requires an environment API key' -or $agentLiveModelLoopSource -notmatch 'no inference request was sent' -or $agentLiveModelLoopSource -notmatch 'ProviderRouteHistory' -or $agentLiveModelLoopSource -notmatch 'sargot-three-day-food-v1' -or $agentLiveModelLoopSource -notmatch 'CompletionContractBase64' -or $agentLiveModelLoopSource -notmatch 'termination.goalVerified') { throw 'Live Campaign evaluation must health-check the configured OpenAI-compatible provider, require a key for remote HTTPS endpoints, retain FreeLLMAPI execution-status validation for its route, record actual routing, and preserve Native goal verification.' }
if ($freeLlmApiProfileSource -notmatch 'Initialize-FreeLLMAPIProfile' -or $freeLlmApiProfileSource -notmatch 'FREELLMAPI_API_KEY' -or $freeLlmApiProfileSource -notmatch 'CHRONICLE_LLM_API_KEY' -or $freeLlmApiProfileSource -notmatch '31415' -or $freeLlmApiProfileSource -notmatch 'available=true' -or $freeLlmApiProfileSource -notmatch 'api/ping' -or $freeLlmApiProfileSource -notmatch 'Start-Process -FilePath \$ExecutablePath -WindowStyle Hidden' -or $freeLlmApiProfileSource -notmatch 'listenerDeadline' -or $freeLlmApiProfileSource -notmatch 'never read from UI or printed' -or $freeLlmApiProfileSource -notmatch 'Start-FreeLLMAPIWithInheritedProxy' -or $freeLlmApiProfileSource -notmatch 'Test-ChronicleLocalProxyListener' -or $freeLlmApiProfileSource -notmatch '127\.0\.0\.1.*7890' -or $freeLlmApiProfileSource -notmatch 'LocalProxyBootstrapApplied' -or $freeLlmApiProfileSource -notmatch 'originalValues') { throw 'Shared FreeLLMAPI preflight must reject local inference, start the installed desktop gateway hidden if stopped, pass persisted proxy configuration or the confirmed local 7890 proxy to that child only, wait for its local ping, retrieve credentials only from process/user environment, restore the parent environment, and never expose the key.' }
$freeLlmApiProfileTokens = $null
$freeLlmApiProfileParseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $harnessRoot 'Get-FreeLLMAPIProfile.ps1'), [ref]$freeLlmApiProfileTokens, [ref]$freeLlmApiProfileParseErrors) | Out-Null
if (@($freeLlmApiProfileParseErrors).Count -gt 0) { throw 'Get-FreeLLMAPIProfile.ps1 must parse before Harness can start or query the FreeLLMAPI service.' }
$agentCheckpointPersistenceSource = Get-Content (Join-Path $harnessRoot 'Test-AgentCheckpointPersistence.ps1') -Raw -Encoding UTF8
$agentCheckpointValidationSource = Get-Content (Join-Path $harnessRoot 'Test-AgentCheckpointValidation.ps1') -Raw -Encoding UTF8
$agentEvaluationRecruitmentBaselineSource = Get-Content (Join-Path $harnessRoot 'Test-AgentEvaluationRecruitmentBaseline.ps1') -Raw -Encoding UTF8
$multiDaySupplyBaselineSource = Get-Content (Join-Path $harnessRoot 'Test-AgentMultiDaySupplyBaseline.ps1') -Raw -Encoding UTF8
$agentEvaluationRecruitmentBaselineProviderSource = Get-Content (Join-Path $harnessRoot 'Test-AgentEvaluationBaselineProvider.ps1') -Raw -Encoding UTF8
$agentEvaluationLiveModelRecruitmentSource = Get-Content (Join-Path $harnessRoot 'Test-AgentEvaluationLiveModelRecruitment.ps1') -Raw -Encoding UTF8
$freshCampaignSource = Get-Content (Join-Path $harnessRoot 'Test-AgentFreshCampaign.ps1') -Raw -Encoding UTF8
$campaignTestSource = Get-Content (Join-Path $harnessRoot 'Test-Campaign.ps1') -Raw -Encoding UTF8
$freshCampaignBaselineMatrixSource = Get-Content (Join-Path $harnessRoot 'Test-AgentEvaluationFreshCampaignBaseline.ps1') -Raw -Encoding UTF8
$freshCampaignLiveModelEvaluationSource = Get-Content (Join-Path $harnessRoot 'Test-AgentEvaluationFreshCampaignLiveModel.ps1') -Raw -Encoding UTF8
$freshCampaignSupplyBaselineSource = Get-Content (Join-Path $harnessRoot 'Test-AgentEvaluationFreshCampaignSupplyBaseline.ps1') -Raw -Encoding UTF8
$freshCampaignRecruitmentFallbackSource = Get-Content (Join-Path $harnessRoot 'Test-AgentEvaluationFreshCampaignRecruitmentFallback.ps1') -Raw -Encoding UTF8
$agentActionLoopSource = Get-Content (Join-Path $harnessRoot 'Agent-DecisionLoop.ps1') -Raw -Encoding UTF8
$agentOpenAiProviderSource = Get-Content (Join-Path $harnessRoot 'Agent-OpenAICompatibleProvider.ps1') -Raw -Encoding UTF8
$agentLiveModelResumeSource = Get-Content (Join-Path $harnessRoot 'Test-AgentLiveModelResume.ps1') -Raw -Encoding UTF8
$harnessVideoCaptureSource = Get-Content (Join-Path $harnessRoot 'HarnessVideoCapture.ps1') -Raw -Encoding UTF8
$townCenterMissionSource = Get-Content (Join-Path $harnessRoot 'Test-AgentTownCenterMission.ps1') -Raw -Encoding UTF8
$inventoryNavigationSource = Get-Content (Join-Path $harnessRoot 'Test-AgentInventoryNavigation.ps1') -Raw -Encoding UTF8
$equipmentTransactionsSource = Get-Content (Join-Path $harnessRoot 'Test-AgentEquipmentTransactions.ps1') -Raw -Encoding UTF8
$tradeTransactionsSource = Get-Content (Join-Path $harnessRoot 'Test-AgentTradeTransactions.ps1') -Raw -Encoding UTF8
$tradeAdapterSource = Get-Content (Join-Path $harnessRoot 'AgentTradeAdapter.cs') -Raw -Encoding UTF8
$recruitmentTestSource = Get-Content (Join-Path $harnessRoot 'Test-AgentRecruitment.ps1') -Raw -Encoding UTF8
$recruitmentAdapterSource = Get-Content (Join-Path $harnessRoot 'AgentRecruitment.cs') -Raw -Encoding UTF8
$recruitmentCapacityFixtureSource = Get-Content (Join-Path $harnessRoot 'HarnessRecruitmentCapacityFixture.cs') -Raw -Encoding UTF8
$barterTransactionsSource = Get-Content (Join-Path $harnessRoot 'Test-AgentBarterTransactions.ps1') -Raw -Encoding UTF8
$barterContextsSource = Get-Content (Join-Path $harnessRoot 'Test-AgentSafePassageBarterContext.ps1') -Raw -Encoding UTF8
$barterAdapterSource = Get-Content (Join-Path $harnessRoot 'AgentBarterAdapter.cs') -Raw -Encoding UTF8
$barterCaptureSource = Get-Content (Join-Path $harnessRoot 'AgentBarterViewCapture.cs') -Raw -Encoding UTF8
$safePassageFixtureSource = Get-Content (Join-Path $harnessRoot 'HarnessSafePassageFixture.cs') -Raw -Encoding UTF8
$testAgentSupportSource = Get-Content (Join-Path $harnessRoot 'Test-AgentSupport.ps1') -Raw -Encoding UTF8
. (Join-Path $harnessRoot 'HarnessShaderCacheDialog.ps1')
$confirmLabel = [string][char]0x786E + [char]0x5B9A
$shaderDialogTestCases = @(
    (Test-ChronicleShaderCacheDialogCandidate -WindowTitle 'Mod change detected' -DialogText 'A change in your active mods was detected. Deleting the runtime shader cache to avoid rendering issues.' -ActionNames @($confirmLabel)),
    (Test-ChronicleShaderCacheDialogCandidate -WindowTitle 'Mod change detected' -DialogText 'A change in your active mods was detected. Deleting the runtime shader cache to avoid rendering issues.' -ActionNames @('OK','Cancel')),
    (Test-ChronicleShaderCacheDialogCandidate -WindowTitle 'Mod change detected' -DialogText 'Save compatibility warning.' -ActionNames @('OK')),
    (Test-ChronicleShaderCacheDialogCandidate -WindowTitle 'Crash Report' -DialogText 'A change in your active mods was detected. Deleting the runtime shader cache to avoid rendering issues.' -ActionNames @('OK'))
)
if (-not $shaderDialogTestCases[0] -or $shaderDialogTestCases[1] -or $shaderDialogTestCases[2] -or $shaderDialogTestCases[3]) { throw 'Shader-cache dialog classifier must accept only the exact known title, cache text, and a unique affirmative action.' }
if ($agentCliSource -notmatch 'Invoke-ChronicleShaderCacheDialogAcknowledgement' -or $shaderDialogSource -notmatch 'InvokePattern' -or $shaderDialogSource -notmatch 'LegacyIAccessiblePattern' -or $shaderDialogSource -notmatch 'Current\.ProcessId -ne \$ProcessId' -or $shaderDialogSource -notmatch 'GetWindowThreadProcessId' -or $shaderDialogSource -notmatch '0x00F5' -or $shaderDialogSource -notmatch '\$maxAcknowledgements\s*=\s*3' -or $shaderDialogSource -notmatch 'AcknowledgementAttempts' -or $shaderDialogSource -match 'SendInput|mouse_event|keybd_event|SetForegroundWindow|SetFocus' -or $inventoryNavigationSource -notmatch 'StartupDialogReceipts') { throw 'The shader-cache prompt must use a verified process-owned UIA/native-button action, bounded same-dialog retries, preserve its receipt, and never use global input or foreground activation.' }
if ($agentCliSource -notmatch "'moveToPoint'" -or $agentCliSource -notmatch "'missionInput'" -or $agentCliSource -notmatch "ValidateSet\('land'\)" -or $agentProtocolSource -notmatch 'case "moveToPoint"' -or $agentProtocolSource -notmatch 'case "missionInput"' -or $agentProtocolSource -notmatch 'boundedLease' -or $agentProtocolSource -notmatch 'UpdateMissionInputLease' -or $agentProtocolSource -notmatch 'ReadRequiredFiniteDouble' -or $agentProtocolSource -notmatch 'ProcessTravel\(requestedPoint\)' -or $agentProtocolSource -notmatch 'naval/sea transition belongs to a separately tested adapter' -or $agentDecisionLoopSource -notmatch "moveToPoint = @\('X','Y','Surface'\)" -or $agentDecisionLoopSource -notmatch "missionInput = @\('X','Y','DurationSeconds'\)" -or $agentObserverSource -notmatch 'schemaVersion\\":28' -or $agentObserverSource -notmatch 'characterId' -or $agentObserverSource -notmatch 'OneToOneConversationCharacter' -or $agentObserverSource -notmatch 'textId' -or $agentObserverSource -notmatch 'GetID\(\)' -or $agentObserverSource -notmatch 'bannerEditor' -or $agentObserverSource -notmatch 'isWaitMenu' -or $agentObserverSource -notmatch 'isWaitActive' -or $agentObserverSource -notmatch 'storyModeEstablishClanStatus' -or $agentObserverSource -notmatch 'questMarkerFlags' -or $agentObserverSource -notmatch 'OptionQuestData' -or $agentObserverSource -notmatch 'CanInteractWithAgent' -or $agentObserverSource -notmatch 'isInteractable' -or $agentObserverSource -notmatch 'targetPosition' -or $agentObserverSource -notmatch 'BuildMissionObservationJson' -or $agentObserverSource -notmatch 'combatType' -or $agentObserverSource -notmatch 'movementInput' -or $agentObserverSource -notmatch 'CameraBearing' -or $agentObserverSource -notmatch 'CameraElevation' -or $agentObserverSource -notmatch 'nativeFocus' -or $agentObserverSource -notmatch 'nearbySceneAgents' -or $agentObserverSource -notmatch 'BuildMissionNavigationObservationJson' -or $agentObserverSource -notmatch 'isPlayerControlled' -or $agentObserverSource -notmatch 'isAIControlled' -or $agentObserverSource -notmatch 'settlementOverlayCharacters' -or $agentProtocolSource -notmatch 'case "talkToSettlementHero"' -or $agentProtocolSource -notmatch 'case "visitSettlementHero"' -or $agentDecisionLoopSource -notmatch "talkToSettlementHero = @\('HeroId'\)" -or $agentDecisionLoopSource -notmatch "visitSettlementHero = @\('HeroId'\)") { throw 'W2-B land-point observation and W2-D native menu quest-marker and Mission camera/focus/input observations must coexist under the current schema.' }
if ($agentObserverSource -notmatch 'mainAgent\.CanInteractWithAgent\(item\.Agent, mainAgentController\.MissionScreen\.CameraElevation\)' -or
    $agentObserverSource -notmatch 'isInteractable') { throw 'Current local Mission agents must carry Native CanInteractWithAgent eligibility so the Companion route can distinguish a reachable conversation target from a merely nearby Hero.' }
if ($agentObserverSource -notmatch 'Property\(json, "characterName", conversationManager\.OneToOneConversationCharacter\?\.Name\?\.ToString\(\), true\)' -or
    $agentObserverSource -notmatch 'Property\(json, "heroId", conversationManager\.OneToOneConversationHero\?\.StringId, true\)' -or
    $agentObserverSource -notmatch 'Property\(json, "sentenceText", conversationManager\.CurrentSentenceText, true\)') {
    throw 'Native active conversation fields must serialize as comma-delimited JSON properties for both Hero and non-Hero CharacterObject speakers.'
}
if ($agentObserverSource -notmatch 'mapSettlementTargets' -or $agentObserverSource -notmatch 'item.IsActive && item.IsVisible' -or $agentProtocolSource -notmatch 'settlement.IsVisible' -or $agentProtocolSource -notmatch 'GetInteractionDataForMainParty') { throw 'W2-F must expose only native visible Settlement map targets and keep the move adapter constrained to visible, natively navigable targets.' }
if ($agentObserverSource -notmatch 'mainHeroSkills' -or $agentObserverSource -notmatch 'Skills.All' -or $agentObserverSource -notmatch 'hero.GetSkillValue\(skill\)') { throw 'MainHero skills must come from Campaign skill objects and the native Hero.GetSkillValue calculation.' }
if ($agentObserverSource -notmatch 'BuildMapSettlementTargetsJson' -or $agentProtocolSource -notmatch 'case "mapSettlementTargets"' -or $agentDecisionLoopSource -notmatch 'mapSettlementTargets = @\(\)' -or $agentProtocolSource -notmatch 'mapSettlementTargets requires the Campaign Map state') { throw 'Map targets must be exposed as an on-demand read-only Campaign Map observation tool, not repeated in every state snapshot.' }
if ($agentDecisionLoopSource -notmatch 'schemaVersion = 3' -or $agentDecisionLoopSource -notmatch 'goal = \$Goal' -or $agentDecisionLoopSource -notmatch 'recentDecisionHistory = @\(Get-RecentDecisionHistory -Trace \$trace\)' -or $agentDecisionLoopSource -notmatch 'allowedActions = @\(\$actionCatalog' -or $agentDecisionLoopSource -notmatch '\$allowed = \$ActionCatalog' -or $agentDecisionLoopSource -notmatch 'AllowedActionNames' -or $agentDecisionLoopSource -notmatch 'providerStartedUtc' -or $agentDecisionLoopSource -notmatch 'actionCompletedUtc' -or $agentDecisionLoopSource -notmatch 'observationCompletedUtc' -or $agentDecisionTestProviderSource -notmatch 'schemaVersion -ne 3' -or $agentDecisionTestProviderSource -notmatch 'recentDecisionHistory' -or $agentDecisionTestProviderSource -notmatch 'decisionContext' -or $agentDecisionTestProviderSource -notmatch 'exact requested map-action scope' -or $agentDecisionLoopTestSource -notmatch 'AllowedActionNames' -or $agentDecisionLoopTestSource -notmatch 'GoalAndActionCatalogForwarded' -or $agentDecisionLoopTestSource -notmatch 'ScopedActionRejected' -or $agentDecisionLoopTestSource -notmatch 'DynamicActionCatalogRecoveryVerified' -or $agentDecisionLoopTestSource -notmatch 'DecisionTimingCaptured') { throw 'Agent decision request schema v3 must include a bounded recent action/outcome history alongside the current Native observation, goal, prior receipt, action catalog and timings; the bounded executor still validates every current action.' }
if (-not (Test-Path (Join-Path $harnessRoot 'Agent-OpenAICompatibleProvider.ps1')) -or -not (Test-Path (Join-Path $harnessRoot 'Test-AgentOpenAICompatibleProvider.ps1')) -or $harnessScript -notmatch 'agentModelProviderScript = Join-Path \$harnessRoot ''Test-AgentOpenAICompatibleProvider\.ps1''' -or $harnessScript -notmatch 'OpenAI-compatible provider protocol test failed' -or $agentOpenAiProviderSource -notmatch 'CHRONICLE_LLM_BASE_URL' -or $agentOpenAiProviderSource -notmatch 'CHRONICLE_LLM_MODEL' -or $agentOpenAiProviderSource -notmatch 'CHRONICLE_LLM_API_KEY' -or $agentOpenAiProviderSource -notmatch 'response_format' -or $agentOpenAiProviderSource -notmatch 'allowedActions' -or $agentOpenAiProviderSource -match 'Write-Host' -or $agentOpenAiProviderTestSource -notmatch 'RequestGoalForwarded' -or $agentOpenAiProviderTestSource -notmatch 'AuthorizationHeaderSent' -or $agentOpenAiProviderTestSource -notmatch 'ProviderOutputCredentialFree') { throw 'The real-model provider prototype must remain outside the game process, use local-only credentials/config, validate structured decisions, and have a local HTTP protocol test that never substitutes for a live-model run.' }
if ($agentOpenAiProviderSource -notmatch 'max_completion_tokens' -or $agentOpenAiProviderSource -notmatch 'max_tokens' -or $agentOpenAiProviderSource -notmatch 'store = \$false' -or $agentOpenAiProviderSource -notmatch 'endpointBuilder\.Path' -or $agentOpenAiProviderTestSource -notmatch 'BaseUrlResolvedToChatCompletionsPath' -or $agentOpenAiProviderTestSource -notmatch 'TimeoutFailsClosedWithoutCredentialLeak' -or $agentOpenAiProviderTestSource -notmatch 'HttpErrorFailsClosedWithoutCredentialLeak') { throw 'The Provider contract must resolve a configured base URL to the Chat Completions path, use the current completion-token field by default, allow explicit compatibility override, request no model-output storage, and test HTTP error/timeout fail-closed behavior.' }
if ($agentOpenAiProviderTestSource -notmatch 'LocalCompatibleMaxTokensWithoutAuthorization' -or $agentOpenAiProviderTestSource -notmatch 'LocalReasoningEffortForwarded' -or $agentOpenAiProviderTestSource -notmatch 'LocalTemperatureForwarded' -or $agentOpenAiProviderTestSource -notmatch 'LocalReceiptCompacted' -or $agentOpenAiProviderSource -notmatch 'Ordered goal steps are hard preconditions' -or $agentOpenAiProviderSource -notmatch 'mapSettlementTargetsSummary' -or $agentOpenAiProviderSource -notmatch 'recruitOptionsSummary' -or $agentOpenAiProviderSource -notmatch 'stateSummary' -or $agentOpenAiProviderSource -notmatch 'observeAgain' -or $agentOpenAiProviderSource -notmatch '\[System\.Text\.Encoding\]::UTF8\.GetBytes\(\$body\)' -or $agentOpenAiProviderSource -notmatch 'rationaleSource = ''provider-fallback''' -or $agentOpenAiProviderTestSource -notmatch 'UnicodeObservationForwarded' -or $agentOpenAiProviderTestSource -notmatch 'ExactPositionalArgumentsNormalized' -or $agentOpenAiProviderTestSource -notmatch 'BoundedObserveAgainControlValidated' -or $agentOpenAiProviderTestSource -notmatch 'DisallowedActionFailsClosed' -or $agentOpenAiProviderTestSource -notmatch 'HttpErrorFailsClosedWithoutCredentialLeak' -or $agentOpenAiProviderTestSource -notmatch 'TimeoutFailsClosedWithoutCredentialLeak' -or $agentOpenAiProviderTestSource -notmatch 'local HTTP stub; not a real model call') { throw 'Provider contract must test UTF-8 transport, compact map/recruitment receipts, exact argument-tuple normalization, rationale fallback labeling, bounded observeAgain, local no-key operation, and fail-closed errors without claiming live-model coverage.' }
if ($harnessScript -notmatch "'LiveModel' \{ @\('Preflight', 'Build', 'LiveModel'\) \}" -or $harnessScript -notmatch "'LiveModel' \{" -or $harnessScript -match "'All' \{[^\r\n]*'LiveModel'") { throw 'Real model verification must be an explicit, cost-bearing opt-in Harness phase and remain outside All.' }
if ($harnessScript -notmatch "'LiveModelArrival' \{ @\('Preflight', 'Build', 'LiveModelArrival'\) \}" -or $harnessScript -notmatch "'LiveModelArrival' \{" -or $harnessScript -match "'All' \{[^\r\n]*'LiveModelArrival'") { throw 'Native arrival verification must be a separate opt-in real-model Harness phase and remain outside All.' }
if ($harnessScript -notmatch "'LiveModelRecruitment' \{ @\('Preflight', 'Build', 'LiveModelRecruitment'\) \}" -or $harnessScript -notmatch "'LiveModelRecruitment' \{" -or $harnessScript -match "'All' \{[^\r\n]*'LiveModelRecruitment'") { throw 'Native live-model recruitment verification must be a separate opt-in Harness phase and remain outside All.' }
if ($harnessScript -notmatch "'LiveModelSafePassageRecruitment' \{ @\('Preflight', 'Build', 'LiveModelSafePassageRecruitment'\) \}" -or $harnessScript -match "'All' \{[^\r\n]*'LiveModelSafePassageRecruitment'") { throw 'Roadside Safe Passage integration must be a dedicated opt-in real-model Harness phase outside All.' }
if ($agentLiveModelLoopSource -notmatch 'RoadsideBanditNegotiationLoop' -or $agentLiveModelLoopSource -notmatch 'barterAutoBalance' -or $agentLiveModelLoopSource -notmatch 'SafePassageRoute' -or $agentDecisionLoopSource -notmatch 'HarnessPrepareSafePassageAfterMove' -or $agentDecisionLoopSource -notmatch 'visual Harness run whose decision allowlist includes Native move' -or $agentDecisionLoopSource -notmatch 'native-safe-passage-conversation-observed') { throw 'The real-model Safe Passage scenario must use the current Native dialogue/Barter flow and keep its world-interruption fixture isolated to visual Harness runs.' }
if ($agentLiveModelLoopSource -notmatch 'Get-Process -Name Bannerlord\*' -or $agentLiveModelLoopSource -notmatch 'CHRONICLE_LLM_BASE_URL' -or $agentLiveModelLoopSource -notmatch 'CHRONICLE_LLM_MODEL' -or $agentLiveModelLoopSource -notmatch '\$allowedActions = ''mapSettlementTargets,move''' -or $agentLiveModelLoopSource -notmatch 'Start-ChronicleWindowVideoCapture' -or $agentLiveModelLoopSource -notmatch 'Write-LiveModelCaptureEvent' -or $agentLiveModelLoopSource -notmatch 'LiveModelEngine-before' -or $agentLiveModelLoopSource -notmatch 'LiveModelEngine-after' -or $agentLiveModelLoopSource -notmatch 'LiveModelEngine-failure' -or $agentLiveModelLoopSource -notmatch 'FailureEngineFrameCaptured' -or $agentLiveModelLoopSource -notmatch 'FixtureUnchanged' -or $agentLiveModelLoopSource -notmatch 'QueryThenNativeMoveVerified' -or $agentLiveModelLoopSource -notmatch 'ProcessStopped') { throw 'The opt-in LiveModel phase must refuse an already-running game, require local provider configuration, restrict the model to visible map query/movement, capture the real Bannerlord HWND and engine frames with aligned model/action events, retain failure visuals, verify the Native target receipt, and preserve fixture/process cleanup.' }
if ($agentDecisionLoopSource -notmatch 'Convert-ObservationForDecision' -or $agentDecisionLoopSource -notmatch 'campaign-map-travel' -or $agentDecisionLoopSource -notmatch 'campaign-settlement-recruitment' -or $agentDecisionLoopSource -notmatch 'MaxElapsedSeconds' -or $agentDecisionLoopSource -notmatch 'schedulerWaitElapsedMilliseconds' -or $agentDecisionLoopSource -notmatch 'Get-ObserveAgainPolicy' -or $agentDecisionLoopPolicySource -notmatch 'StoppablePlay' -or $agentDecisionLoopPolicySource -notmatch 'encounterActive' -or $agentDecisionLoopSource -notmatch 'control-unavailable' -or $agentLiveModelLoopSource -notmatch 'ArrivalLoop' -or $agentLiveModelLoopSource -notmatch 'ArrivalConfirmed' -or $agentLiveModelLoopSource -notmatch 'BoundedReobservations' -or $agentLiveModelLoopSource -notmatch 'NativeTravelReobservations' -or $agentLiveModelLoopSource -notmatch 'CampaignDayAdvancedDuringTravel') { throw 'Map travel and settlement recruitment model views must wait only while Native movement and Campaign time are active; stopped encounters must return feedback, and travel acceptance must use fresh Native arrival/time evidence.' }
if ($agentDecisionLoopPolicySource -notmatch 'function Test-UnobstructedCampaignMap' -or $agentDecisionLoopSource -notmatch 'Test-UnobstructedCampaignMap' -or $agentDecisionLoopSource -notmatch 'During a hostile encounter, expose the active conversation/barter route' -or $agentDecisionLoopSource -notmatch 'clickableDialogueOptions' -or $agentDecisionLoopSource -notmatch 'Get-BarterActionGate' -or $agentDecisionLoopSource -notmatch 'banditWaitingForBarterProbe' -or $agentDecisionLoopSource -notmatch 'nativeBarterProbeWasRejected' -or $agentDecisionLoopSource -notmatch 'nativeSafePassageOfferAccepted' -or $agentDecisionLoopSource -notmatch 'priorFeedback' -or $agentDecisionLoopSource -notmatch 'barterOptions' -or $agentDecisionLoopSource -notmatch 'dialogueContinue' -or $agentDecisionLoopTestSource -notmatch 'UnavailableDialogueRejectedWithoutNativeAction' -or $agentDecisionLoopTestSource -notmatch 'MapMovementCatalogRequiresUnobstructedCampaignMap' -or $agentDecisionTestProviderSource -notmatch 'unavailableDialogueRecovery') { throw 'Map movement must be hidden under Native menus/encounters, hostile encounter options must steer through current conversation/Barter, and the guards must retain prior feedback and have deterministic recovery coverage.' }
if ($agentDecisionLoopPolicySource -notmatch 'function Get-EffectiveControlCatalog' -or $agentDecisionLoopSource -notmatch 'Get-EffectiveControlCatalog' -or $agentDecisionLoopSource -notmatch 'allowedControls = \$controlCatalog' -or $agentDecisionLoopTestSource -notmatch 'ObserveAgainControlIsExposedOnlyWhenSafe' -or $agentOpenAiProviderSource -notmatch 'use only controls in `allowedControls`') { throw 'The Agent must expose scheduler controls only when currently safe, instruct the model to follow that catalog, and keep a deterministic regression for encounter/stopped-time states.' }
if ($agentLiveModelLoopSource -notmatch 'RecruitmentLoop' -or $agentLiveModelLoopSource -notmatch 'NativeRecruitmentVerified' -or $agentLiveModelLoopSource -notmatch 'recruit_volunteers' -or $agentLiveModelLoopSource -notmatch 'ConfirmPartySizeWarning' -or $agentLiveModelLoopSource -notmatch 'ArrivalConfirmed' -or $agentLiveModelLoopSource -notmatch 'RoadsideBanditNegotiationLoop' -or $agentLiveModelLoopSource -notmatch 'SafePassageRoute' -or $agentLiveModelLoopSource -notmatch 'barterAutoBalance' -or $agentDecisionLoopSource -notmatch 'HarnessPrepareSafePassageAfterMove') { throw 'Live-model recruitment must prove Native recruitment, while the separate Safe Passage scenario exercises current dialogue/barter recovery using a Harness-only interruption.' }
if ($agentLiveModelLoopSource -notmatch 'nativeReadObservationsAfterMove' -or $agentLiveModelLoopSource -notmatch 'travelReobserved' -or $agentLiveModelLoopSource -notmatch 'currentSettlementId.*chosenId') { throw 'A current Native observation after movement must count when it records either advancing travel or arrival at the target, without requiring a redundant scheduler wait.' }
if ($agentLiveModelLoopSource -notmatch 'ModelId = \[string\]\$env:CHRONICLE_LLM_MODEL' -or $agentLiveModelLoopSource -notmatch 'ModelThinkingMode' -or $agentLiveModelLoopSource -notmatch 'ModelReasoningEffort' -or $agentLiveModelLoopSource -notmatch 'SourceCommit = \$sourceCommit' -or $agentLiveModelLoopSource -notmatch 'SourceTrackedTreeClean' -or $agentLiveModelLoopSource -notmatch 'CampaignDayStart' -or $agentLiveModelLoopSource -notmatch 'CampaignDayEnd') { throw 'A real-model acceptance receipt must identify model, reasoning mode, source commit, tracked-tree state, and Campaign day interval without recording credentials.' }
if ($harnessScript -notmatch "'MultiDaySupplyBaseline' \{ @\('Preflight', 'Build', 'MultiDaySupplyBaseline'\) \}" -or $harnessScript -match "'All' \{[^\r\n]*'MultiDaySupplyBaseline'" -or $harnessScript -notmatch 'SupplyBaselineProvisionAmount = 4' -or $harnessScript -notmatch '-ProvisionAmount \$SupplyBaselineProvisionAmount' -or $multiDaySupplyBaselineSource -notmatch 'deterministic Native-action baseline' -or $multiDaySupplyBaselineSource -notmatch 'foodInventory' -or $multiDaySupplyBaselineSource -notmatch 'dailyWage' -or $multiDaySupplyBaselineSource -notmatch 'dailyTickCount' -or $multiDaySupplyBaselineSource -notmatch 'FixtureHashBefore' -or $multiDaySupplyBaselineSource -notmatch 'NoHarnessClockActionsUsed' -or $multiDaySupplyBaselineSource -match "Invoke-AgentCli '(advance|pause|resume|fastForward)'" -or $multiDaySupplyBaselineSource -notmatch "Invoke-AgentCli 'rest'" -or $multiDaySupplyBaselineSource -notmatch "Invoke-AgentCli 'provision'") { throw 'The multi-day supply Native baseline must remain opt-in, use only Native rest/trade/movement, measure resource/time postconditions, and preserve fixture cleanup.' }
if ($subModuleSource -notmatch 'chronicle_agent_campaign_instance_v1' -or $subModuleSource -notmatch 'chronicle_agent_checkpoint_json_v1' -or $subModuleSource -notmatch 'SyncData\(IDataStore dataStore\)' -or $subModuleSource -notmatch 'Checkpoint Campaign identity does not match' -or $agentProtocolSource -notmatch 'case "agentCheckpointGet"' -or $agentProtocolSource -notmatch 'case "agentCheckpointSet"' -or $agentCliSource -notmatch 'agentCheckpointGet' -or $agentCliSource -notmatch 'agentCheckpointSet' -or $agentDecisionLoopSource -notmatch 'ResumeCheckpoint' -or $agentDecisionLoopSource -notmatch 'PersistCheckpoint' -or $agentDecisionLoopSource -notmatch 'provider-stopped' -or $agentCheckpointPersistenceSource -notmatch 'CampaignInstanceStableAcrossNativeSaveLoad' -or $agentCheckpointPersistenceSource -notmatch 'LastMoveReceiptRestored' -or $agentLiveModelResumeSource -notmatch 'ResumeCheckpoint' -or $agentLiveModelResumeSource -notmatch 'GoalRestored' -or $agentLiveModelResumeSource -notmatch 'MoveNotRepeated' -or $agentLiveModelResumeSource -notmatch 'RecruitmentVerified') { throw 'W4 checkpoint recovery must persist a schema-versioned goal/confirmed receipt with Campaign save identity, re-observe after Native load, and verify a real-model resume without repeating the completed move.' }
if ($harnessScript -notmatch "'CheckpointPersistence' \{ @\('Preflight', 'Build', 'CheckpointPersistence'\) \}" -or $harnessScript -notmatch "'LiveModelResume' \{ @\('Preflight', 'Build', 'LiveModelResume'\) \}" -or $harnessScript -match "'All' \{[^\r\n]*'LiveModelResume'") { throw 'Checkpoint round-trip and real-model resume must be separate opt-in Harness phases; real LLM resume must remain outside All.' }
if ($harnessScript -notmatch "'LiveModelRuntimeResume' \{ @\('Preflight', 'Build', 'LiveModelRuntimeResume'\) \}" -or $harnessScript -notmatch "-RuntimeOnlyResume" -or $harnessScript -match "'All' \{[^\r\n]*'LiveModelRuntimeResume'") { throw 'Agent-only restart with a still-running Campaign must be a separate opt-in real-model phase outside All.' }
if ($agentLiveModelResumeSource -notmatch 'RuntimeOnlyResume' -or $agentLiveModelResumeSource -notmatch 'BannerlordProcessUnchangedAcrossResume' -or $agentLiveModelResumeSource -notmatch 'RuntimeRunIdChanged') { throw 'LiveModelRuntimeResume must keep the same Bannerlord process while starting a distinct resumed Agent loop.' }
if ($harnessScript -notmatch "'LiveModelActionRecovery' \{ @\('Preflight', 'Build', 'LiveModelActionRecovery'\) \}" -or $harnessScript -match "'All' \{[^\r\n]*'LiveModelActionRecovery'") { throw 'Native action reconciliation after an Agent-only fault must be an explicit opt-in phase outside All.' }
if ($agentDecisionLoopSource -notmatch 'HarnessCrashAfterAction' -or $agentDecisionLoopSource -notmatch 'expectedGoldAfter' -or $agentDecisionLoopSource -notmatch 'expectedMembersAfter' -or $agentDecisionLoopSource -notmatch 'recoveredAfterRuntimeInterruption' -or $agentDecisionLoopSource -notmatch 'Environment\]::Exit\(93\)' -or $agentLiveModelResumeSource -notmatch 'CrashAfterNativeRecruitVerified' -or $agentLiveModelResumeSource -notmatch 'sameSlotStillAvailable' -or $agentLiveModelResumeSource -notmatch '-HarnessCrashAfterAction recruit') { throw 'The post-recruit fault path must verify Native effects from pending intent plus fresh state and refuse a duplicate transaction.' }
if ($agentDecisionLoopSource -notmatch 'HarnessCrashAfterAction' -or $agentDecisionLoopSource -notmatch 'visual-capture' -or $agentDecisionLoopSource -notmatch 'pendingAction' -or $agentDecisionLoopSource -notmatch 'expectedGoldAfter' -or $agentDecisionLoopSource -notmatch 'recoveredAfterRuntimeInterruption' -or $agentDecisionLoopSource -notmatch 'Environment\]::Exit\(93\)' -or $agentLiveModelResumeSource -notmatch 'CrashAfterRecruit' -or $agentLiveModelResumeSource -notmatch 'CrashAfterNativeRecruitVerified') { throw 'The fault path must be Harness-gated, persist a pending Native recruit intent before execution, kill only the decision Runtime after real success, and verify reconciliation without repeating recruit.' }
if ($harnessScript -notmatch "'CheckpointValidation' \{ @\('Preflight', 'Build', 'CheckpointValidation'\) \}" -or $harnessScript -match "'All' \{[^\r\n]*'CheckpointValidation'") { throw 'Invalid-checkpoint validation must be an opt-in failure-safety stage outside All.' }
if ($agentProtocolSource -notmatch 'checkpointSchemaVersion != 1 && checkpointSchemaVersion != 2' -or $agentCliSource -notmatch 'Checkpoint schemaVersion 1 or 2' -or $agentProtocolSource -notmatch 'case "harnessSeedAgentCheckpointFailure"' -or $agentProtocolSource -notmatch 'restricted to a visual Harness run' -or $agentDecisionLoopSource -notmatch 'checkpoint is corrupt or unreadable' -or $agentDecisionLoopSource -notmatch 'schema version.*unsupported' -or $agentDecisionLoopSource -notmatch 'different Campaign instance' -or $agentDecisionTestProviderSource -notmatch 'checkpointMustNotCall' -or $agentCheckpointValidationSource -notmatch 'corrupt-json' -or $agentCheckpointValidationSource -notmatch 'unsupported-schema' -or $agentCheckpointValidationSource -notmatch 'wrong-campaign' -or $agentCheckpointValidationSource -notmatch 'ProviderWasNotCalled' -or $agentCheckpointValidationSource -notmatch 'WorldStateUnchanged') { throw 'Invalid/cross-Campaign checkpoint scenarios must stop before the model Provider or any Native write action; only checkpoint schemas 1 and 2 are accepted.' }
if ($harnessScript -notmatch "'RecruitmentBaseline' \{ @\('Preflight', 'Build', 'RecruitmentBaseline'\) \}" -or $harnessScript -match "'All' \{[^\r\n]*'RecruitmentBaseline'") { throw 'Repeated recruitment baseline must remain an explicit opt-in evaluation phase outside All.' }
if ($agentEvaluationRecruitmentBaselineSource -notmatch '\$Runs = 5' -or $agentEvaluationRecruitmentBaselineSource -notmatch 'DistinctCampaignSeeds = 1' -or $agentEvaluationRecruitmentBaselineSource -notmatch 'sourceHash' -or $agentEvaluationRecruitmentBaselineSource -notmatch 'WallClockSeconds' -or $agentEvaluationRecruitmentBaselineProviderSource -notmatch 'deterministic' -or $agentEvaluationRecruitmentBaselineProviderSource -notmatch 'recruit_volunteers' -or $agentEvaluationRecruitmentBaselineProviderSource -notmatch "action = 'recruit'") { throw 'W5 baseline must explicitly report five same-seed native runs, deterministic provider semantics, and real recruitment postconditions without claiming cross-seed/model results.' }
if ($harnessScript -notmatch "'LiveModelRecruitmentEvaluation' \{ @\('Preflight', 'Build', 'LiveModelRecruitmentEvaluation'\) \}" -or $harnessScript -match "'All' \{[^\r\n]*'LiveModelRecruitmentEvaluation'") { throw 'Repeated real-model candidate evaluation must be a separate opt-in phase outside All.' }
if ($agentEvaluationLiveModelRecruitmentSource -notmatch '\$Runs = 5' -or $agentEvaluationLiveModelRecruitmentSource -notmatch 'WallClockLimitSeconds = 180' -or $agentEvaluationLiveModelRecruitmentSource -notmatch 'CampaignDayLimit = 0\.1' -or $agentEvaluationLiveModelRecruitmentSource -notmatch 'SuccessfulRuns' -or $agentEvaluationLiveModelRecruitmentSource -notmatch 'DistinctCampaignSeeds = 1' -or $agentEvaluationLiveModelRecruitmentSource -notmatch 'RecruitmentVerified' -or $agentEvaluationLiveModelRecruitmentSource -notmatch 'VideoRemovedAfterEvidence') { throw 'The W5 same-save real-model candidate stage must enforce the predeclared five-of-five thresholds and keep cross-seed/generalization limits explicit.' }
if ($harnessScript -notmatch "'LiveModelSupplyEvaluation' \{ @\('Preflight', 'Build', 'LiveModelSupplyEvaluation'\) \}" -or $harnessScript -match "'All' \{[^\r\n]*'LiveModelSupplyEvaluation'") { throw 'Multi-day real-model supply evaluation must be a separate opt-in phase outside All.' }
if ($agentLiveModelLoopSource -notmatch 'SupplyManagementLoop' -or
    $agentLiveModelLoopSource -notmatch '\$allowedActions = ''menuSelect,foodOptions,provision,tradeConfirm,rest''' -or
    $agentLiveModelLoopSource -notmatch "CHRONICLE_LLM_MAX_TOKENS = '256'" -or
    $agentLiveModelLoopSource -notmatch 'dailyTickCount -ne 2' -or
    $agentLiveModelLoopSource -notmatch 'Host passively polls Native state' -or
    $agentLiveModelLoopSource -notmatch 'HostRestPollCount' -or
    $agentLiveModelLoopSource -notmatch 'HostWaitLeaveActionCompleted' -or
    $agentLiveModelLoopSource -notmatch 'naturalTicksElapsed -eq 3' -or
    $agentLiveModelLoopSource -notmatch 'Amount -eq 1' -or
    $agentLiveModelLoopSource -notmatch 'tradeEntrySteps.Count -eq 1' -or
    $agentLiveModelLoopSource -notmatch 'tradeCommitSteps.Count -eq 1' -or
    $agentLiveModelLoopSource -notmatch 'Gold -ge 861' -or
    $agentLiveModelLoopSource -notmatch 'DailyTicksElapsed' -or
    $agentLiveModelLoopSource -notmatch 'SupplyVerified' -or
    $agentLiveModelLoopSource -notmatch 'supply-fixture-prepared' -or
    $agentEvaluationLiveModelSupplySource -notmatch '\$Runs = 3' -or
    $agentEvaluationLiveModelSupplySource -notmatch 'WallClockLimitSeconds = 300' -or
    $agentEvaluationLiveModelSupplySource -notmatch 'maxDecisionsPerRun = 24' -or
    $agentEvaluationLiveModelSupplySource -notmatch 'budgetMaxInputTokensPerCall = 10128' -or
    $agentEvaluationLiveModelSupplySource -notmatch 'budgetTotalMaxInputTokens = 202560' -or
    $agentEvaluationLiveModelSupplySource -notmatch 'maxFoodTransactionsPerRun = 1' -or
    $agentEvaluationLiveModelSupplySource -notmatch 'maxFoodUnitsPerRun = 1' -or
    $agentEvaluationLiveModelSupplySource -notmatch 'maxNativeRestRequestsPerRun = 1' -or
    $agentEvaluationLiveModelSupplySource -notmatch 'requiredDailyTicks = 3' -or
    $agentEvaluationLiveModelSupplySource -notmatch 'minFinalFood = 1\.0' -or
    $agentEvaluationLiveModelSupplySource -notmatch 'minFinalGold = 861' -or
    $agentEvaluationLiveModelSupplySource -notmatch 'VideoRemovedAfterEvidence' -or
    $agentLiveModelLoopSource -match "Invoke-AgentCli '((advance)|(pause)|(resume)|(fastForward))'") {
    throw 'The multi-day supply candidate must use a one-unit Native purchase, exactly three natural ticks, passive Host waiting with one current wait_leave action, current Native postconditions, fixed budgets, and no explicit time-control action.'
}
if ($harnessScript -notmatch "'AgentHostCampaignLoopEvaluation' \{ @\('Preflight', 'Build', 'AgentHostCampaignLoopEvaluation'\) \}" -or
    $harnessScript -match "'All' \{[^\r\n]*'AgentHostCampaignLoopEvaluation'" -or
    $harnessScript -notmatch 'Test-AgentHostCampaignLoopEvaluation\.ps1' -or
    $agentHostDecisionCycleSource -notmatch 'CampaignSystemPrompt' -or
    $agentHostDecisionCycleSource -notmatch 'DecideCampaignAsync' -or
    $agentHostCampaignLoopSource -notmatch 'mapSettlementTargets' -or
    $agentHostCampaignLoopSource -notmatch 'ExecuteCampaignActionAsync' -or
    $agentHostCampaignLoopSource -notmatch 'BuildControlCatalog\(movingToTarget, targetReached, before\["state"\] as JsonObject\)' -or
    $agentHostCampaignLoopSource -notmatch 'campaign-loop-requires-goal-scope-classification-before-native-actions' -or
    $agentHostCampaignLoopSource -notmatch 'campaign-loop-unsupported-goal-stops-before-native-actions' -or
    $agentHostCampaignLoopSource -notmatch 'campaign-loop-target-query-precedes-move-and-completion' -or
    $agentHostCampaignLoopSource -notmatch 'campaign-loop-does-not-repeat-map-query-after-empty-result' -or
    $agentHostCampaignLoopSource -notmatch 'campaign-loop-self-test-hostile-meeting-does-not-wait' -or
    $agentHostCampaignLoopSource -notmatch 'provider-goal-classification-unavailable' -or
    $agentHostCampaignLoopSource -notmatch 'provider-arguments-invalid-json' -or
    $agentHostCampaignLoopSource -notmatch 'Native move is already active' -or
    $agentHostDecisionCycleSource -notmatch 'When the fresh Native state confirms the move to that selected target is active and observeAgain is listed' -or
    $agentHostDecisionCycleSource -notmatch 'After the Host accepts classification, never emit either classification control again' -or
    $agentHostCampaignLoopSource -notmatch 'campaign-loop-rejects-unobserved-targets-and-clock-actions' -or
    $agentHostCampaignLoopSource -notmatch 'RunTransportSelfTestsAsync' -or
    $agentHostCampaignLoopSource -notmatch 'campaign-loop-runtime-observe-decide-act-observe-arrival' -or
    $agentHostCampaignLoopSource -notmatch 'campaign-loop-runtime-native-timeout-is-not-replayed' -or
    $agentHostCampaignLoopEvaluationSource -notmatch '\-ArrivalLoop' -or
    $agentHostCampaignLoopEvaluationSource -notmatch '\-AgentHostRuntime' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'CampaignDayAdvancedDuringTravel' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'VideoRemovedAfterEvidence' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'SourceTrackedTreeClean' -or
    $agentLiveModelLoopSource -notmatch 'parentProcessStartTimeUtcTicks' -or $agentLiveModelLoopSource -notmatch 'nativeSessionId' -or
    $agentLiveModelLoopSource -notmatch 'HostReadyMessages' -or
    $agentHostPackageSource -notmatch '--provider-self-test' -or
    $agentHostPackageSource -notmatch 'CampaignLoopSelfTestScenarioCount' -or
    $agentHostPackageSource -notmatch 'BattleSimulationLoopSelfTestScenarioCount' -or
    $agentHostPackageSource -notmatch 'SharedDecisionCycleScenarioCount' -or
    $agentHostPackageSource -notmatch 'SelfTestNativeCommands' -or
    $agentHostProviderSelfTestSource -notmatch 'VerifySharedDecisionCycleAsync\(settings, "mapSettlementTargets", "CampaignSystemPrompt"' -or
    $agentHostProviderSelfTestSource -notmatch 'VerifySharedDecisionCycleAsync\(settings, "foodOptions", "SupplySystemPrompt"') {
    throw 'The Host campaign loop must remain opt-in and prove its bounded Native map-arrival contract, natural time progression, real local-model path, visual evidence and cleanup.'
}
if ($harnessScript -notmatch "'AgentHostVillageToolsQuestEvaluation' \{ @\('Preflight', 'Build', 'Smoke', 'AgentHostPackage', 'AgentHostVillageToolsQuestEvaluation'\) \}" -or
    -not $harnessScript.Contains("effectiveSmokeTimeoutSeconds = if (`$Phase -in @('FreshStoryModeModelEvaluation','PersistentEycCampaign','FreshStoryModeNativeInquiryResponseEvaluation','AgentHostVillageToolsQuestEvaluation','AgentHostEstablishClanGoalPlannerEvaluation','AgentHostEstablishClanAutonomyEvaluation','AgentHostCaptivityRecoveryEvaluation','AgentHostEstablishClanGoldSaleEvaluation','AgentHostBattleSimulationEvaluation','AgentHostBattleAndCaptivityEvaluation')) { [Math]::Max(`$SmokeTimeoutSeconds, 240) }") -or
    $harnessScript -match "'All' \{[^\r\n]*'AgentHostVillageToolsQuestEvaluation'" -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'VerifyQuestInventoryDelta' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'village-tools-direct-quest-option-unavailable' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'village-tools-loop-self-test-alternative-only-stop-failed' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'village-tools-policy-allows-native-alternative-explanation-navigation' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'village-tools-policy-allows-direct-quest-and-reject-but-blocks-alternative-acceptance' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'HasOnlyOutOfScopeIssueOutcomeOptions' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'IsOutOfScopeIssueOutcomeOption' -or
    $agentHostDecisionCycleSource -notmatch 'only opens the Alternative explanation' -or $agentHostDecisionCycleSource -notmatch 'never select issue_offer_player_accept_alternative' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'inventoryVerifiedAfterTurnIn' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'native-quest-and-inventory-observed' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'village-tools-policy-self-test-quest-search-overreach' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'tradeCancel' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'village-tools-policy-self-test-active-quest-dialogue-exit-gate-failed' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'village-tools-policy-self-test-active-quest-village-exit-gate-failed' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'village-tools-policy-self-test-delivery-giver-gate-failed' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'village-tools-policy-self-test-return-to-observed-giver-village-failed' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'village-tools-policy-self-test-requires-fresh-journal-after-purchase' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'village-tools-policy-self-test-inventory-verification-survives-marker-disappearance' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'village-tools-policy-gates-done-on-verified-map-including-settlement-menu' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'GetToolsQuestMapTargetType' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'village-tools-loop-self-test-giver-village-receipt-failed' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'village-tools-loop-self-test-unknown-origin-fails-closed' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'GetAllowedDialogueOptions' -or $agentHostVillageToolsQuestPolicySource -notmatch 'IsConversationLeaveOption' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'village-tools-host-routes-classified-goal-through-native-observe-decide-act-loop' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'village-tools-host-recovers-from-bounded-invalid-actions-in-open-native-dialogue' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'village-tools-host-recovers-invalid-village-target-with-current-safe-town-ids' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'sameActionRetryAllowed' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'BuildActionPreconditionFeedback' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'The only allowed Host action is dialogueSelect' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'The Native screen shows gold' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'village-tools-host-maps-visible-click-to-continue-screen-to-dialogueContinue' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'clickableOptionIds' -or
    $agentHostVillageToolsFixturePreparationSource -notmatch 'Get-ToolsIssueMarker' -or
    $agentHostVillageToolsFixturePreparationSource -notmatch "Invoke-NativeCli 'save'" -or
    $agentHostVillageToolsFixturePreparationSource -notmatch 'SourceFixtureUnchanged' -or
    $agentHostVillageToolsFixturePreparationSource -notmatch 'No Quest was injected' -or
    $agentHostDecisionCycleSource -notmatch 'supportedVillageToolsQuestGoal' -or
    $agentHostDecisionCycleSource -notmatch 'Conversation option IDs are argument values, never action names' -or
    $agentHostDecisionCycleSource -notmatch 'BuildVillageToolsQuestSystemPrompt' -or
    $agentHostDecisionCycleSource -notmatch 'RECOVERY DIRECTIVE' -or
    $agentHostDecisionCycleSource -notmatch 'sameActionRetryAllowed explicitly permits correcting its arguments' -or
    $agentHostDecisionCycleSource -notmatch 'You may repeat that action only with corrected arguments from the current catalog' -or
    $agentHostDecisionCycleSource -notmatch '点击继续' -or $agentHostDecisionCycleSource -notmatch 'does not leave the settlement' -or
    $agentHostDecisionCycleSource -notmatch 'intermediate steps' -or
    $agentHostDecisionCycleSource -notmatch 'steps toward that one outcome' -or
    $agentLiveModelLoopSource -notmatch '\[switch\]\$VillageToolsQuestLoop' -or
    $agentLiveModelLoopSource -notmatch 'tradeCancelChanges,barterOptions,barterAutoBalance,barterOffer,barterCancel,inventoryOpen' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'VillageToolsQuest' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'Test-AgentVillageToolsQuestFixturePreparation' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'VillageToolsQuestInventoryDeltaVerified') {
    throw 'The Host village-tools quest path must remain opt-in and verify the current visible quest, native actions and exact pre/post inventory deltas before allowing completion.'
}
if ($harnessScript -notmatch "'AgentHostEstablishClanGoalPlannerEvaluation' \{ @\('Preflight', 'Build', 'Smoke', 'AgentHostPackage', 'AgentHostEstablishClanGoalPlannerEvaluation'\) \}" -or
    $harnessScript -match "'All' \{[^\r\n]*'AgentHostEstablishClanGoalPlannerEvaluation'" -or
    $agentHostCampaignLoopEvaluationSource -notmatch '\-EstablishYourClanGoalPlanner' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'ChronicleW7N-' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'SourceSha256Before' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'plannerSourceHashAfter' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'RuntimeLoadModuleAugment' -or
    $harnessScript -notmatch 'StoryModePlannerSourceSaveName' -or
    $agentHostLiveModelLoopSource -notmatch '\[switch\]\$EstablishYourClanGoalPlanner' -or
    $agentHostLiveModelLoopSource -notmatch '-IncludeChronicleFramework' -or
    $agentCliSource -notmatch '\[switch\]\$IncludeChronicleFramework' -or
    $agentCliSource -notmatch 'observedStartupProcessIds' -or
    $agentCliSource -notmatch 'Stop-ChronicleStartupProcessTree' -or
    $agentCliSource -notmatch 'ActiveModules = \$modules' -or
    $agentCliSource -notmatch 'startup-crash-\$\(\$crashCandidate\.Id\)\.json' -or
    $agentCliSource -notmatch 'Unhandled startup exception' -or
    $agentHostLiveModelLoopSource -notmatch 'rebuild_player_clan_storymode_quest' -or
    $agentHostLiveModelLoopSource -notmatch 'timeControlMode -cne ''Stop''' -or
    $agentHostLiveModelLoopSource -notmatch 'EstablishYourClanPlannerVerified' -or
    $agentHostLiveModelLoopSource -notmatch 'storyModeEstablishClanStatus\.status' -or
    $agentHostLiveModelLoopSource -notmatch 'NativeClockActions = @\(\$steps' -or
    $agentHostLiveModelLoopSource -notmatch 'objectiveId' -or
    $agentHostLiveModelLoopSource -notmatch 'FixtureUnchanged = \$fixtureUnchanged') {
    throw 'W7-N must remain opt-in, use a disposable original StoryMode save with the exact naturally active quest, make real FreeLLMAPI decisions only, verify four objectives against Journal/native values without gameplay writes, and preserve source/time/world evidence.'
}
if ($harnessScript -notmatch "'AgentHostCaptivityRecoveryEvaluation' \{ @\('Preflight', 'Build', 'Smoke', 'AgentHostPackage', 'AgentHostCaptivityRecoveryEvaluation'\) \}" -or
    $harnessScript -match "'All' \{[^\r\n]*'AgentHostCaptivityRecoveryEvaluation'" -or
    $harnessScript -notmatch 'CaptivityRecoveryFromExisting' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'ChronicleW7O-' -or
    $agentHostLiveModelLoopSource -notmatch '\[switch\]\$CaptivityRecoveryLoop' -or
    $agentHostLiveModelLoopSource -notmatch 'isWaitActive' -or
    $agentHostLiveModelLoopSource -notmatch 'CaptivityRecoveryVerified' -or
    $agentHostLiveModelLoopSource -notmatch 'CaptivityRecoveryTargetConsistency' -or
    $agentHostCampaignLoopSource -notmatch 'supportedCaptivityRecoveryGoal' -or
    $agentHostCaptivityRecoveryLoopSource -notmatch 'ShouldPassivelyWait' -or
    $agentHostCaptivityRecoveryLoopSource -notmatch 'captivity-recovery-current-menu-unsupported' -or
    $agentHostCaptivityRecoveryLoopSource -notmatch 'menu_captivity_end_no_more_enemies' -or
    $agentHostCaptivityRecoveryLoopSource -notmatch 'menu_captivity_end_wilderness_escape' -or
    $agentHostCaptivityRecoveryLoopSource -notmatch 'menu_captivity_end_propose_ransom_in_prison' -or
    $agentHostCaptivityRecoveryLoopSource -notmatch 'mno_continue' -or
    $agentHostCaptivityRecoveryLoopSource -notmatch 'CaptivityRecoveryNativeClient' -or
    $agentHostCaptivityRecoveryLoopSource -notmatch 'postPlanDocument' -or
    $agentHostCaptivityRecoveryLoopSource -notmatch 'finalStoryModeEstablishClanStatus' -or
    $agentHostDecisionCycleSource -notmatch 'CaptivityRecoverySystemPrompt' -or
    $agentHostMailboxSource -notmatch 'ExecuteCaptivityRecoveryActionAsync') {
    throw 'W7-O must remain opt-in, resume from an already captive active StoryMode source without starting a battle, separate explicit Play from passive waiting, use only current enabled source-verified captivity menu choices, replan after free-map verification, and clean its disposable copy.'
}
if ($harnessScript -notmatch "'AgentHostEstablishClanGoldSaleEvaluation' \{ @\('Preflight', 'Build', 'Smoke', 'AgentHostPackage', 'AgentHostEstablishClanGoldSaleEvaluation'\) \}" -or
    $harnessScript -match "'All' \{[^\r\n]*'AgentHostEstablishClanGoldSaleEvaluation'" -or
    $agentHostCampaignLoopEvaluationSource -notmatch '\[switch\]\$EstablishClanGoldSaleFromStoryMode' -or
    $agentHostLiveModelLoopSource -notmatch '\[switch\]\$EstablishClanGoldSaleLoop' -or
    $agentHostLiveModelLoopSource -notmatch 'EstablishClanGoldSaleVerified' -or
    $agentHostCampaignLoopSource -notmatch 'supportedEstablishClanGoldSaleGoal' -or
    $agentHostGoldSaleLoopSource -notmatch 'nativeTooltipType"\) == "Goods"' -or
    $agentHostGoldSaleLoopSource -notmatch 'gold-sale-native-commit-unverified' -or
    $agentHostGoldSaleLoopSource -notmatch 'gold-sale-self-test-native-move-start-transition-poll-failed' -or
    $agentHostGoldSaleLoopSource -notmatch 'MinimumActiveMapTravelObserveSeconds' -or
    $agentHostGoldSaleLoopSource -notmatch 'gold-sale-self-test-active-map-observation-cadence-failed' -or
    $agentHostProviderSource -notmatch 'GetObserveAgainWaitBounds' -or
    $agentHostProviderSelfTestSource -notmatch 'provider-structured-output-enforces-context-specific-active-travel-observe-interval' -or
    $agentHostDecisionCycleSource -notmatch '5-10 second Host-side wait' -or
    $agentHostGoldSaleLoopSource -notmatch 'moveStartPending' -or
    $agentHostDecisionCycleSource -notmatch 'Immediately after your own move, Native may briefly show the selected target before isMoving becomes true' -or
    $agentHostMailboxSource -notmatch 'ValidateGoldSaleAction' -or
    $agentHostMailboxSource -notmatch 'PlayerInventory' -or
    $harnessScript -notmatch 'StoryModePlannerSourceSaveName = ''save002''' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'StartsWith\(''ChronicleW7P-''' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'storyModeGoldSaleSourceHashBefore' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'objectiveJournalBefore\.JournalGoldCurrent' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'objectiveJournalAfter\.current' -or
    $agentHostCampaignLoopEvaluationSource -match '\$saleVerification\.journalGoldAfter|\$saleVerification\.journalGoldBefore|\$saleVerification\.journalGoldTarget' -or
    $agentHostLiveModelLoopSource -notmatch 'JournalGoldCurrent' -or
    $agentHostLiveModelLoopSource -notmatch 'EstablishClanGoldSaleVerification') {
    throw 'W7-P must remain opt-in, use one current Native Goods sale with a real transaction receipt, isolate its campaign goal scope, and preserve source/visual/cleanup evidence.'
}
if ($harnessScript -notmatch "'AgentHostBattleSimulationEvaluation' \{ @\('Preflight', 'Build', 'Smoke', 'AgentHostPackage', 'AgentHostBattleSimulationEvaluation'\) \}" -or
    $harnessScript -match "'All' \{[^\r\n]*'AgentHostBattleSimulationEvaluation'" -or
    $agentHostCampaignLoopEvaluationSource -notmatch '\-BattleSimulationLoop' -or
    $harnessScript -notmatch 'BattleSimulationSourceSaveName' -or
    $agentHostCampaignLoopEvaluationSource -notmatch '\$BattleSourceSaveName' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'Get-AgentSaveModuleIds' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'ChronicleW7L-' -or
    $agentHostCampaignLoopEvaluationSource -notmatch '\[IO\.File\]::Copy\(\$battleSourceSavePath, \$battleFixtureSavePath, \$false\)' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'IsByteForByteCopy' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'SourceSha256Before' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'battleSourceHashAfter' -or
    $agentHostLiveModelLoopSource -notmatch '\[switch\]\$BattleSimulationLoop' -or
    $agentHostLiveModelLoopSource -notmatch 'visual-battle-fixture' -or
    $agentHostRuntimeControllerSource -notmatch 'useDisposableBattleFixtureProfile' -or
    $agentHostRuntimeControllerSource -notmatch 'CHRONICLE_AGENT_PROFILE_PATH' -or
    $agentHostRuntimeControllerSource -notmatch 'providerConfiguration = useDisposableBattleFixtureProfile' -or
    $subModuleSource -notmatch 'CreateDisposableBattleFixture' -or
    $agentHostLiveModelLoopSource -notmatch 'BattleTargetPreflight\.json' -or
    $agentHostLiveModelLoopSource -notmatch 'ModelInferenceStarted = \$false' -or
    $agentHostRuntimeControllerSource -notmatch 'battleSkip' -or
    $agentHostRuntimeControllerSource -notmatch 'dialogueSelect' -or
    $agentHostBattleSimulationLoopSource -notmatch 'bandit_start_defender_1' -or
    $agentHostBattleSimulationLoopSource -notmatch 'common_encounter_ultimatum' -or
    $agentHostBattleSimulationLoopSource -notmatch 'common_bandit_surrender_declined' -or
    $agentHostBattleSimulationLoopSource -notmatch 'common_encounter_fight' -or
    $agentHostDecisionCycleSource -notmatch 'common_encounter_ultimatum' -or
    $agentHostDecisionCycleSource -notmatch 'common_bandit_surrender_declined' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'everyDialogueChoiceMustMatchCurrentCatalogAndClickableOption' -or
    $agentHostBattleSimulationLoopSource -notmatch 'str_order_attack' -or
    $agentHostBattleSimulationLoopSource -notmatch 'battleSimulation' -or
    $agentHostBattleSimulationLoopSource -notmatch 'nativeReturnToMapVerified' -or
    $agentHostBattleSimulationLoopSource -notmatch 'prisoner_wait' -or
    $agentHostBattleSimulationLoopSource -notmatch 'partyTakeAll' -or
    $agentHostBattleSimulationLoopSource -notmatch 'argumentValues' -or
    $agentHostBattleSimulationLoopSource -notmatch 'members or prisoners' -or
    $agentHostBattleSimulationLoopSource -notmatch 'battle-loop-self-test-loot-type-alias-not-rejected' -or
    $agentHostBattleSimulationLoopSource -notmatch 'battle-loop-self-test-native-leave-not-bounded' -or
    $agentHostBattleSimulationLoopSource -notmatch 'battle-loop-self-test-native-leave-postcondition-not-verified' -or
    $agentHostBattleSimulationLoopSource -notmatch 'IsVerifiedMapTerminalAfterNativeEncounterLeave' -or
    $agentHostBattleSimulationLoopSource -notmatch 'native-encounter-left-no-battle' -or
    $agentHostBattleSimulationLoopSource -notmatch 'nativeEncounterLeft: true' -or
    $agentHostDecisionCycleSource -notmatch 'current Native leave option is enabled' -or
    $agentHostBattleSimulationLoopSource -notmatch 'playerOutcome' -or
    $agentHostBattleSimulationLoopSource -notmatch '\["providerConfigurationSource"\] = provider\.ConfigurationSource' -or
    $agentHostBattleSimulationLoopSource -notmatch 'ReadString\(result, "providerConfigurationSource"\)' -or
    $agentHostLiveModelLoopSource -notmatch 'PlayerOutcome = \[string\]\$loopTrace\.playerOutcome' -or
    $agentHostLiveModelLoopSource -notmatch 'PlayerCaptiveAtMapReturn = \[bool\]\$loopTrace\.playerCaptiveAtMapReturn' -or
    $agentHostLiveModelLoopSource -notmatch 'NativeMapReturnMenuId = \[string\]\$loopTrace\.nativeMapReturnMenuId' -or
    $agentHostBattleSimulationLoopSource -notmatch 'battle-loop-native-observe-pursue-send-troops-aftermath-return-and-verify' -or
    $agentHostBattleSimulationLoopSource -notmatch 'mapPartyTargetsQueried') {
    throw 'W7-L must remain opt-in, use the current Native Bandit Fight/Send Troops path, process aftermath, verify outcomes and stop safely when no visible target exists.'
}
if ($harnessScript -notmatch "'AgentHostBattleAndCaptivityEvaluation' \{ @\('Preflight', 'Build', 'Smoke', 'AgentHostPackage', 'AgentHostBattleAndCaptivityEvaluation'\) \}" -or
    $harnessScript -match "'All' \{[^\r\n]*'AgentHostBattleAndCaptivityEvaluation'" -or
    $agentHostCampaignLoopSource -notmatch 'supportedBattleAndCaptivityGoal' -or
    $agentHostDecisionCycleSource -notmatch 'BattleAndCaptivitySystemPrompt' -or
    $agentHostDecisionCycleSource -notmatch 'current Native wilderness ransom menu is visible' -or
    $agentHostCampaignLoopEvaluationSource -notmatch '\-BattleAndCaptivityLoop' -or
    $agentHostLiveModelLoopSource -notmatch '\[switch\]\$BattleAndCaptivityLoop' -or
    $agentHostBattleSimulationLoopSource -notmatch 'ShouldPassivelyWaitForCaptivity' -or
    $agentHostBattleSimulationLoopSource -notmatch 'captivityRecoveryVerified' -or
    $agentHostBattleSimulationLoopSource -notmatch 'menu_captivity_end_propose_ransom_wilderness' -or
    $agentHostBattleSimulationLoopSource -notmatch 'captivity_end_ransom_deny' -or
    $agentHostBattleSimulationLoopSource -notmatch 'battle-loop-captivity-waits-for-native-and-binds-ransom-choice') {
    throw 'W7-M must remain an opt-in real-model continuation from an actual Native battle capture, passively wait without clock actions, and restrict ransom decisions to current enabled Native options.'
}
if ($agentHostCampaignLoopEvaluationSource -notmatch '\[string\]\$CleanupPreparedSaveName' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'StartsWith\(''ChronicleW7K-''' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'StartsWith\(''ChronicleW7L-''' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'StartsWith\(''ChronicleW7N-''' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'StartsWith\(''ChronicleW7O-''' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'StartsWith\(''ChronicleW7P-''' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'Bannerlord process is running' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'Agent CLI session is active' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'escaped the Harness-owned ChronicleW7K/W7L/W7N/W7O/W7P Game Saves boundary' -or
    $agentHostCampaignLoopEvaluationSource -notmatch '\$staleSession\.saveName' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'Get-Process -Id \$stalePid' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'AgentCliStopOutput' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'AgentHostStaleFixtureRecovery\.json') {
    throw 'Recovery cleanup may delete only a ChronicleW7K disposable fixture after both Bannerlord and its CLI session are absent, and must stay inside Game Saves.'
}
if ($agentHostDecisionCycleSource -notmatch 'AgentHostHarnessProgressTrace\.RecordDecision' -or
    $agentHostHarnessProgressTraceSource -notmatch 'CHRONICLE_HARNESS_MODE' -or
    $agentHostHarnessProgressTraceSource -notmatch 'visual-capture' -or
    $agentHostHarnessProgressTraceSource -notmatch 'agent-host-lifecycle-test' -or
    $agentHostHarnessProgressTraceSource -notmatch 'lifecycle/selftest-route' -or
    $agentHostHarnessProgressTraceSource -notmatch 'AgentHostProgress\.jsonl' -or
    $agentHostHarnessProgressTraceSource -notmatch 'MaximumBytes' -or
    $agentHostHarnessProgressTraceSource -notmatch 'Rationale is deliberately excluded' -or
    $agentHostHarnessProgressTraceSource -notmatch 'BuildNativeStateSummary' -or
    $agentHostHarnessProgressTraceSource -notmatch 'nativeStateBefore' -or
    $agentHostHarnessProgressTraceSource -notmatch 'nativeStateAfter' -or
    $agentHostHarnessProgressTraceSource -notmatch 'conversationCharacterId' -or
    $agentHostHarnessProgressTraceSource -notmatch 'conversationOptions' -or
    $agentHostHarnessProgressTraceSource -notmatch 'BuildVillagersInNeedStartupSummary' -or
    $agentHostHarnessProgressTraceSource -notmatch 'host-progress-trace-villagers-conversation-startup-self-test' -or
    $agentHostHarnessProgressTraceSource -notmatch 'BuildObjectiveSnapshotSummary' -or
    $agentHostHarnessProgressTraceSource -notmatch 'BuildNativeProgressionContextSummary' -or
    $agentHostHarnessProgressTraceSource -notmatch 'nativeProgressionContext' -or
    $agentHostHarnessProgressTraceSource -notmatch 'host-progress-trace-progression-context-self-test' -or
    $agentHostHarnessProgressTraceSource -notmatch 'harness-progress-trace-records-dynamic-journal-current-target-met-summary' -or
    $agentHostRecruitmentLoopSource -notmatch 'safe-stop-rejected-with-observe-again-control' -or
    $agentHostRecruitmentLoopSource -notmatch 'The currently issued Native map move is still active' -or
    $agentHostRecruitmentLoopSource -notmatch 'BuildRecruitmentOffersObservation' -or
    $agentHostRecruitmentLoopSource -notmatch 'visibleTargetCount' -or
    $agentHostRecruitmentLoopSource -notmatch 'establish-clan-recruitment-duplicate-map-target-payload' -or
    $agentHostRecruitmentLoopSource -notmatch 'establish-clan-recruitment-duplicate-offer-payload' -or
    $agentHostRecruitmentLoopSource -notmatch 'establish-clan-recruitment-target-projection-retains-redundant-flags' -or
    $agentHostRecruitmentLoopSource -notmatch 'establish-clan-recruitment-target-projection-capped-dynamic-map-set' -or
    $agentHostHarnessProgressTraceSource -notmatch 'providerHttpStatus' -or
    $agentHostHarnessProgressTraceSource -notmatch 'BuildRecruitmentOfferSummary' -or
    $agentHostHarnessProgressTraceSource -notmatch 'harness-progress-trace-reports-only-aggregate-affordable-recruitment-offer-counts' -or
    $agentHostHarnessProgressTraceSource -notmatch 'BuildCompanionNavigationSummary' -or
    $agentHostHarnessProgressTraceSource -notmatch 'harness-progress-trace-reports-only-aggregate-companion-navigation-progress' -or
    $agentHostProviderContractSelfTestSource -notmatch 'AgentHostHarnessProgressTrace\.RunContractSelfTests') {
    throw 'Real Host decisions must be incrementally persisted only in bounded Harness visual-capture/lifecycle modes, including the selected Native argument and route but excluding rationale/raw prompt content.'
}
if (-not (Test-Path -LiteralPath (Join-Path $harnessRoot 'AgentHost\AgentHostCampaignStateFacts.cs')) -or
    $agentHostCampaignStateFactsSource -notmatch 'IsNativeLocationMenu' -or
    $agentHostCampaignStateFactsSource -notmatch 'IsActiveEncounter' -or
    $agentHostCampaignStateFactsSource -notmatch 'campaign-state-facts-training-field-menu-misclassified' -or
    $agentHostCampaignStateFactsSource -notmatch 'campaign-state-facts-hostile-encounter-misclassified' -or
    $agentHostCompanionLoopSource -notmatch 'establish-clan-companion-training-field-menu-misclassified' -or
    $agentHostCompanionLoopSource -notmatch 'companion-navigation-stall-policy-excludes-only-after-two-no-progress-native-approaches' -or
    $agentHostCompanionLoopSource -notmatch 'MinimumCompanionNavigationProgressDistance = 0.1d' -or
    $agentHostRecruitmentLoopSource -notmatch 'establish-clan-recruitment-training-field-menu-not-exitable' -or
    $agentHostRecruitmentLoopSource -notmatch 'establish-clan-recruitment-failure-receipt-preserves-safe-native-state-summary' -or
    $agentHostRecruitmentLoopSource -notmatch 'establish-clan-recruitment-native-training-field-leave-to-volunteer-to-journal-verification' -or
    $agentHostRecruitmentLoopSource -notmatch '\["failureCode"\] = failureCode' -or
    $agentHostGoldSaleLoopSource -notmatch 'gold-sale-self-test-training-field-menu-not-exitable' -or
    $agentHostBattleSimulationLoopSource -notmatch 'battle-loop-self-test-training-field-menu-not-exitable' -or
    $agentHostBattleSimulationLoopSource -notmatch 'trainingFieldLeave\[0\].*argumentValues' -or
    $agentHostBattleSimulationLoopSource -notmatch 'enabledLeaveIds\.Select' -or
    $agentHostProviderContractSelfTestSource -notmatch 'AgentHostCampaignStateFacts.RunContractSelfTests') {
    throw 'EYC objective subflows must distinguish the verified Native training-field Leave menu from a hostile Party encounter and keep the same leave path out of hostile encounter handling.'
}
if ($agentLiveModelLoopSource -notmatch 'elseif \(\$VillageToolsQuestLoop\)[\s\S]{0,900}Set-LiveModelProviderTimeout 360' -or
    $agentLiveModelLoopSource -notmatch 'elseif \(\$VillageToolsQuestLoop\)[\s\S]{0,900}\$env:CHRONICLE_LLM_MAX_TOKENS = ''1024''') {
    throw 'The real-model Village quest slice must retain the bounded 360-second FreeLLMAPI retry deadline and the empirically increased 1024-token output ceiling required after a 512-token structured response was truncated.'
}
if ($agentLiveModelLoopSource -notmatch 'elseif \(\$VillageToolsQuestLoop\)[\s\S]{0,400}\$maxElapsedSeconds = 7200' -or
    $agentLiveModelLoopSource -notmatch '\$maxDecisions = 160' -or
    $agentHostRuntimeControllerSource -notmatch 'maxDecisions\\":320,\\"maxElapsedSeconds\\":7200' -or
    $agentHostCampaignLoopSource -notmatch 'maxDecisions is < 1 or > MaxCumulativeDecisions' -or
    $agentHostCampaignLoopSource -notmatch 'MaxCumulativeDecisions = 320' -or
    $agentHostEstablishClanAutonomySource -notmatch 'ReadInt\(request, "maxDecisions", AgentHostCampaignLoop\.MaxCumulativeDecisions\)' -or
    $agentHostBattleSimulationLoopSource -notmatch 'ReadInt\(request, "maxDecisions", AgentHostCampaignLoop\.MaxCumulativeDecisions\)' -or
    $agentHostRecruitmentLoopSource -notmatch 'MaxDecisions = AgentHostCampaignLoop\.MaxCumulativeDecisions' -or
    $agentHostCompanionLoopSource -notmatch 'MaxDecisions = AgentHostCampaignLoop\.MaxCumulativeDecisions' -or
    $agentHostGoldSaleLoopSource -notmatch 'for \(var iteration = 1; decisionCount < maxDecisions; iteration\+\+\)' -or
    $agentHostCaptivityRecoveryLoopSource -notmatch 'for \(var loopIndex = 1; decisions < maxDecisions; loopIndex\+\+\)' -or
    $agentHostCampaignLoopSource -notmatch 'GetCumulativeDecisionLimit\(maxDecisions\)' -or
    $agentHostCampaignLoopSource -notmatch 'campaign-loop-self-test-child-decision-limit-shrank' -or
    $agentHostCampaignLoopSource -notmatch 'maxElapsedSeconds is < 1 or > 7200' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'Math\.Clamp\(ReadInt\(request, "maxElapsedSeconds", 7200\), 1, 7200\)' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'Math\.Clamp\(ReadInt\(request, "maxDecisions", 160\), 1, 160\)') {
    throw 'The EYC Host request and all nested objective loops must share the 7200-second/320-decision cumulative ceiling; separate loops must not restart the full decision allowance when prior decisions are carried forward.'
}
if ($agentHostEstablishClanAutonomySource -notmatch 'priorProviderRouteHistory: routes,[\s\S]{0,100}recoverPlayerCaptivity: true' -or
    $agentHostBattleSimulationLoopSource -notmatch 'allowedSurrenderFallback = recoverPlayerCaptivity && !sendTroopsEnabled' -or
    $agentHostBattleSimulationLoopSource -notmatch 'surrender only as a survival fallback' -or
    $agentHostDecisionCycleSource -notmatch 'Never choose surrender in the ordinary Renown BattleSimulation route') {
    throw 'Only an approved incidental encounter in Captivity-recovery mode may use current Native surrender after Send Troops and Leave are disabled; ordinary Renown Simulation must remain separate.'
}
if ($agentHostEstablishClanAutonomySource -notmatch 'failed-objective-native-actions-reopened-other-routes' -or
    $agentHostEstablishClanAutonomySource -notmatch 'HasObjectiveSnapshotProgressChanged\(snapshot, child\["objectiveSnapshot"\] as JsonObject\)' -or
    $agentHostEstablishClanAutonomySource -notmatch 'BuildObjectiveRouteAvailabilityFingerprint' -or
    $agentHostEstablishClanAutonomySource -notmatch 'objective-route-reopened-after-native-state-change' -or
    $agentHostEstablishClanAutonomySource -notmatch 'objective-route-retry-after-partial-journal-progress') {
    throw 'A failed EYC subgoal with authoritative Journal progress must remain eligible for another attempt; route blocks must not survive real partial progress.'
}
if ($agentLiveModelLoopSource -notmatch 'Get-FreeLLMAPIModelExecutionStatus -ModelRows @\(\$availableModelsResponse\.data\)' -or
    $agentLiveModelLoopSource -notmatch 'if \(\$modelExecutionStatus -eq ''not-listed''\)' -or
    $agentLiveModelLoopSource -match '\[string\]\$env:CHRONICLE_LLM_MODEL -notin \$availableModelIds') {
    throw 'Live-model preflight must use FreeLLMAPI router-aware execution status so documented auto strategy routes are not rejected for being absent from the model rows, while unknown profiles still fail before inference.'
}
if ($agentActionLoopSource -notmatch 'function Get-EffectiveActionCatalog' -or $agentActionLoopSource -notmatch 'recruit_volunteers' -or $agentActionLoopSource -notmatch 'rejected-before-native' -or $agentActionLoopSource -notmatch 'control-unavailable' -or $agentActionLoopSource -notmatch 'control-rejected-before-native' -or $nativeRejectedActionBranch -match '\$previousActionReceipt\s*=\s*\$actionResult' -or $nativeRejectedActionBranch -notmatch 'Keep the last completed Native receipt available' -or $agentDecisionLoopPolicySource -notmatch 'StoppablePlay' -or $agentDecisionLoopPolicySource -notmatch 'encounterActive' -or $agentDecisionLoopPolicySource -notmatch 'town_wait_menus' -or $agentDecisionLoopSource -notmatch 'Convert-ReceiptForDecision' -or $agentDecisionLoopSource -notmatch 'consecutiveDecisionRejections' -or $agentDecisionLoopSource -notmatch 'decisionRejected' -or $agentOpenAiProviderSource -notmatch 'decisionRejected' -or $agentOpenAiProviderSource -notmatch 'decisionFeedback' -or $agentOpenAiProviderTestSource -notmatch 'invalidActionDecision\.decisionRejected' -or $agentEvaluationRecruitmentBaselineProviderSource -notmatch 'recruitment actions leaked' -or $agentDecisionTestProviderSource -notmatch 'staleOfferRecovery' -or $agentDecisionTestProviderSource -notmatch 'unlistedResumeRecovery' -or $agentDecisionLoopTestSource -notmatch 'ObserveAgainPolicySeparatesNaturalTimeFromStoppedEncounter' -or $agentDecisionLoopTestSource -notmatch 'ObserveAgainCanMonitorAcceptedNativeTownWait' -or $agentDecisionLoopTestSource -notmatch 'StaleOfferRecoveryVerified' -or $agentDecisionLoopTestSource -notmatch 'StaleOfferBlockedWithoutNativeMutation' -or $agentDecisionLoopTestSource -notmatch 'UnlistedResumeRejectedWithoutNativeAction' -or $agentDecisionLoopTestSource -notmatch 'StaleObserveAgainRejectedWithoutNativeAction') { throw 'The Agent decision catalog must respect current Native entries, keep the last successful receipt after rejection, permit bounded observation of accepted Native Town Wait, reject waits while time is stopped/encountered, and bound recovery without Native mutation.' }
if ($agentHostVillageToolsQuestPolicySource -notmatch 'QuoteMatchesBalancedDraft' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'proposalFingerprint' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'GetToolsTaskRemainingCount' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'inventoryLogicUnitPrice' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'argumentValues' -or
    $agentHostDecisionCycleSource -notmatch 'never repeat Continue' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'safePassageBalanceReceipt' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'village-tools-host-resolves-bandit-interruption-through-native-safe-passage-and-click-to-continue-without-fight-or-clock-actions' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'safe-passage-self-test-unexpected-continue' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'questDetailsObservedForActiveQuest = false' -or
    $agentHostProviderSelfTestSource -notmatch 'decision-schema-constrains-current-native-string-and-integer-values' -or
    $agentHostProviderSelfTestSource -notmatch 'provider-decision-schema-uses-strict-compatible-root-wrapper' -or
    $barterAdapterSource -notmatch 'BuildProposalFingerprint' -or
    $barterAdapterSource -notmatch 'expectedSessionId' -or
    $agentProtocolSource -notmatch 'expectedProposalFingerprint' -or
    $agentCliSource -notmatch 'ExpectedProposalFingerprint' -or
    $barterContextsSource -notmatch 'NativeOfferRejectsStaleSessionAndProposalWithoutWorldChange') {
    throw 'W7-K Safe Passage Offer must bind the final Native transaction to the same observed BarterVM session and proposal, with stale-session/fingerprint runtime coverage.'
}
if (-not $agentHostRuntimeControllerSource.Contains('\"barterOptions\"') -or
    -not $agentHostRuntimeControllerSource.Contains('\"barterAutoBalance\"') -or
    -not $agentHostRuntimeControllerSource.Contains('\"barterOffer\"') -or
    -not $agentHostRuntimeControllerSource.Contains('\"barterCancel\"')) {
    throw 'The in-game Host start request must pass the same bounded action set that the campaign loop validates.'
}
if ($agentObserverSource -notmatch 'mainHeroSkills' -or $agentObserverSource -notmatch 'Skills.All' -or $agentObserverSource -notmatch 'hero.GetSkillValue\(skill\)') { throw 'MainHero skill observation must use the current Campaign SkillObject collection and native Hero.GetSkillValue without mutating development data.' }
if ($agentProtocolSource -notmatch 'case "harnessPlayerSkillsDiagnostics"' -or $agentProtocolSource -notmatch 'harnessPlayerSkillsDiagnostics is restricted to a visual Harness run' -or $agentDecisionLoopSource -match 'harnessPlayerSkillsDiagnostics') { throw 'Native skill cross-check diagnostics must remain Harness-only and never enter the Agent action allowlist.' }
if ($agentObserverSource -notmatch 'BuildCharacterDevelopmentJson' -or $agentProtocolSource -notmatch 'case "characterDevelopment"' -or $agentCliSource -notmatch "'characterDevelopment'" -or $agentDecisionLoopSource -notmatch 'characterDevelopment = @\(\)' -or $agentProtocolSource -notmatch 'harnessCharacterDevelopmentDiagnostics is restricted to a visual Harness run' -or $agentDecisionLoopSource -match 'harnessCharacterDevelopmentDiagnostics') { throw 'Character development must be an on-demand read-only tool; its native view-model diagnostics must remain Harness-only.' }
if ($agentProtocolSource -notmatch 'case "spendSkillFocus"' -or $agentProtocolSource -notmatch 'SpendMainHeroSkillFocus' -or $agentProtocolSource -notmatch 'exceeds the native maximum Focus' -or $agentProtocolSource -notmatch 'exceeds MainHero''s unspent Focus points' -or $agentCliSource -notmatch "'spendSkillFocus'" -or $agentDecisionLoopSource -notmatch "spendSkillFocus = @\('SkillId','Count'\)") { throw 'Skill Focus investment must validate the whole native Character Developer transaction and remain a bounded Agent action.' }
if ($agentObserverSource -notmatch 'BuildQuestDetailsJson' -or $agentObserverSource -notmatch 'IsRemainingTimeHidden' -or $agentObserverSource -notmatch 'JournalEntries' -or $agentProtocolSource -notmatch 'case "questDetails"' -or $agentProtocolSource -notmatch 'FindObservedOngoingQuest' -or $agentCliSource -notmatch "'questDetails'" -or $agentDecisionLoopSource -notmatch "questDetails = @\('QuestId'\)" -or $agentProtocolSource -notmatch 'harnessQuestDetailsDiagnostics is restricted to a visual Harness run' -or $agentProtocolSource -notmatch 'harnessQuestDeadlinePrivacyDiagnostics is restricted to a visual Harness run' -or $agentDecisionLoopSource -match 'harnessQuestDetailsDiagnostics|harnessQuestDeadlinePrivacyDiagnostics') { throw 'Quest Journal details must be an on-demand read of observed ongoing quests, respect hidden deadlines, and keep QA diagnostics Harness-only.' }
if ($agentObserverSource -notmatch 'BuildPartyRosterJson' -or $agentObserverSource -notmatch 'MemberRoster' -or $agentObserverSource -notmatch 'PrisonRoster' -or $agentProtocolSource -notmatch 'case "partyRoster"' -or $agentProtocolSource -notmatch 'harnessPartyRosterDiagnostics is restricted to a visual Harness run' -or $agentCliSource -notmatch "'partyRoster'" -or $agentDecisionLoopSource -notmatch 'partyRoster = @\(\)' -or $agentDecisionLoopSource -match 'harnessPartyRosterDiagnostics') { throw 'MainParty rosters must be an on-demand read-only query with isolated Harness comparison only.' }
if ($agentCliSource -notmatch "'mapSettlementTargets'" -or $agentDecisionLoopSource -notmatch 'mapSettlementTargets = @\(\)' -or $agentProtocolSource -notmatch 'settlement.IsVisible') { throw 'The on-demand map target query must be callable by the agent and the movement adapter must reject hidden settlement IDs.' }
$missionInputPatchSource = Get-Content (Join-Path $harnessRoot 'AgentMissionInputPatch.cs') -Raw -Encoding UTF8
if ($missionInputPatchSource -notmatch 'MissionMainAgentController' -or $missionInputPatchSource -notmatch 'ControlTick' -or $missionInputPatchSource -notmatch 'AfterNativeControlTick') { throw 'Mission movement input must be applied after the native player-axis handler, not by a one-shot setter that the handler immediately overwrites.' }
if ($agentCliSource -notmatch "'missionSceneAgents'" -or $agentProtocolSource -notmatch 'case "missionSceneAgents"' -or $agentObserverSource -notmatch 'BuildMissionSceneAgentsJson' -or $agentDecisionLoopSource -notmatch 'missionSceneAgents = @\(\)' -or $agentCliSource -notmatch "'missionNavigateToAgent'" -or $agentProtocolSource -notmatch 'case "missionNavigateToAgent"' -or $agentProtocolSource -notmatch 'SandBox.AgentNavigator' -or $agentProtocolSource -notmatch 'SetTargetFrame' -or $agentProtocolSource -notmatch 'DoesPathExistBetweenPositions' -or $agentProtocolSource -notmatch 'UpdateMissionNavigationLease' -or $agentProtocolSource -notmatch 'MissionSceneAgentsObservationLeaseSeconds' -or $agentProtocolSource -notmatch 'ReferenceEquals\(observedNavigationTarget, navigationTargetAgent\)' -or $agentProtocolSource -notmatch 'requestedNavigationSeconds' -or $agentDecisionLoopSource -notmatch "missionNavigateToAgent = @\('AgentIndex','DurationSeconds'\)" -or $agentObserverSource -notmatch 'missionNavigationObservationJson') { throw 'Mission scene roster must be explicitly queried for the current friendly Location Mission; remote approach must use a fresh same-Mission observation and native bounded NavMesh navigation, not hidden diagnostics or teleport.' }
if ($agentObserverSource -notmatch 'CurrentFocusedObject' -or $agentObserverSource -notmatch 'nativeFocus') { throw 'Tavern Mission observations must read the active native MainAgent focus rather than guess which scene character is available to interact with.' }
if ($agentCliSource -notmatch "'harnessMissionDiagnostics'" -or $agentCliSource -notmatch "Invoke-ProtocolCommand 'harnessMissionDiagnostics'" -or $agentProtocolSource -notmatch 'case "harnessMissionDiagnostics"' -or $agentProtocolSource -notmatch 'restricted to a visual Harness run' -or $agentProtocolSource -notmatch 'issueNotableCount' -or $agentProtocolSource -notmatch 'locationIssueOwnerCount' -or $agentProtocolSource -notmatch 'CampaignMission.Current' -or $agentProtocolSource -notmatch 'notableAgents' -or $agentDecisionLoopSource -match 'harnessMissionDiagnostics' -or $townCenterMissionSource -notmatch 'diagnostics-only-classified-entry' -or $townCenterMissionSource -notmatch 'outside the Agent local observation radius') { throw 'Full Mission/Location Issue-owner diagnostics must be Harness-only, preserve the roster-vs-spawn distinction, and avoid blind walking when the issue owner is outside local observation.' }
if (-not $agentCliSource.Contains('heroId = $HeroId') -or $agentProtocolSource -notmatch 'case "harnessMapDiagnostics"' -or $agentProtocolSource -notmatch 'restricted to a visual Harness run' -or $agentProtocolSource -notmatch 'sameTypeIssues' -or $agentProtocolSource -notmatch 'isSolvingWithQuest' -or $agentProtocolSource -notmatch 'atWarWithPlayerFaction' -or $agentDecisionLoopSource -match 'harnessMapDiagnostics') { throw 'Settlement diagnostics must expose the targeted Native Issue gate facts only through the visual Harness path, never the model action catalog.' }
if ($agentCliSource -notmatch "'mapSettlementTargets'" -or $agentProtocolSource -notmatch 'case "mapSettlementTargets"' -or $agentObserverSource -notmatch 'BuildMapSettlementTargetsJson' -or $agentDecisionLoopSource -notmatch 'mapSettlementTargets = @\(\)') { throw 'The full visible map-target list must be a separate on-demand observation query, not repeated in every state snapshot.' }
if ($agentObserverSource -notmatch 'settlementOverlayCharacters' -or $agentObserverSource -notmatch 'WillBeListedInOverlay' -or $agentObserverSource -notmatch 'GetQuestStateOfHero' -or $agentObserverSource -notmatch 'OneToOneConversationHero' -or $agentCliSource -notmatch "'talkToSettlementHero'" -or $agentDecisionLoopSource -notmatch "talkToSettlementHero = @\('HeroId'\)" -or $agentProtocolSource -notmatch 'SettlementOverlayTalkPermissionEvent' -or $agentProtocolSource -notmatch 'SettlementOverylayQuickTalkPermissionEvent' -or $agentProtocolSource -notmatch 'OnPlayerStartTalkFromMenu' -or $agentProtocolSource -notmatch 'CampaignMapConversation.OpenConversation' -or $agentProtocolSource -notmatch 'talkToSettlementHero' -or $agentProtocolSource -notmatch 'visitSettlementHero') { throw 'The settlement overlay route must expose only its native visible character list and reproduce the separate QuickConversation and Conversation paths.' }
if ($agentCliSource -notmatch "'missionNavigateToAgent'" -or $agentCliSource -notmatch "'missionCancelNavigation'" -or $agentProtocolSource -notmatch 'case "missionNavigateToAgent"' -or $agentProtocolSource -notmatch 'case "missionCancelNavigation"' -or $agentProtocolSource -notmatch 'requestedNavigationSeconds' -or $agentProtocolSource -notmatch 'Controller = AgentControllerType.AI' -or $agentProtocolSource -notmatch 'AgentControllerType.Player' -or $agentProtocolSource -notmatch 'SetTargetFrame' -or $agentProtocolSource -notmatch 'ClearTarget\(\)' -or $agentDecisionLoopSource -notmatch "missionNavigateToAgent = @\('AgentIndex','DurationSeconds'\)" -or $agentDecisionLoopSource -notmatch 'missionCancelNavigation' -or $agentProtocolSource -notmatch 'remote missionNavigateToAgent target requires a recent missionSceneAgents observation') { throw 'Native AgentNavigator handoff must use a bounded duration, target an observed current-Mission Agent, require a fresh same-Mission scene query for remote targets, and restore Player control.' }
if ($agentCliSource -notmatch "'missionAimAt'" -or $agentProtocolSource -notmatch 'case "missionAimAt"' -or $agentDecisionLoopSource -notmatch "missionAimAt = @\('AgentIndex'\)" -or $agentObserverSource -notmatch 'CameraBearing' -or $agentObserverSource -notmatch 'CameraElevation' -or $agentObserverSource -notmatch 'nearbySceneAgents') { throw 'Location Mission camera aiming must use a locally observed live Agent index and reobserve native focus rather than inject a target.' }
if ($agentProtocolSource -match 'var (quickTalkData|visitData) = [^\r\n]*(hasIssue|issueType|RequestedItem|numberOfRequested|locationId)' -or $agentProtocolSource -notmatch 'var quickTalkData = .*heroName' -or $agentProtocolSource -notmatch 'var visitData = .*heroName') { throw 'QuickTalk and Visit receipts may echo only the observed target identity; private Quest/Issue subtype data must not leak to the AI.' }
$villageToolsProviderSource = Get-Content (Join-Path $harnessRoot 'Test-AgentVillageToolsProvider.ps1') -Raw -Encoding UTF8
$villageToolsTestSource = Get-Content (Join-Path $harnessRoot 'Test-AgentVillageToolsDelivery.ps1') -Raw -Encoding UTF8
$villageToolsContractFailures = [System.Collections.Generic.List[string]]::new()
if ($harnessScript -notmatch "'VillageToolsDelivery' \{ @\('Preflight', 'Build', 'VillageToolsDelivery'\) \}") { $villageToolsContractFailures.Add('phase-map') }
if ($harnessScript -notmatch "Invoke-Stage -Name 'VillageToolsDelivery'") { $villageToolsContractFailures.Add('stage') }
if ($villageToolsProviderSource -notmatch 'settlementOverlayCharacters' -or $villageToolsProviderSource -notmatch 'AvailableIssue') { $villageToolsContractFailures.Add('visible-issue-marker') }
if ($villageToolsProviderSource -notmatch 'talkToSettlementHero' -or $villageToolsProviderSource -notmatch 'tradeOptions' -or $villageToolsProviderSource -notmatch 'questDetails') { $villageToolsContractFailures.Add('quick-talk-and-native-primitives') }
if ($villageToolsProviderSource -match 'VillageNeedsToolsIssueQuest|FinishQuestSuccess1|CompleteQuestWithSuccess') { $villageToolsContractFailures.Add('private-quest-helper-leak') }
if ($villageToolsTestSource -notmatch 'Agent-DecisionLoop.ps1' -or $villageToolsTestSource -notmatch 'SourceFixtureUnchanged' -or $villageToolsTestSource -notmatch 'ProcessStopped') { $villageToolsContractFailures.Add('loop-or-cleanup') }
if ($villageToolsContractFailures.Count -gt 0) { throw "Village Tools delivery contract failed: $($villageToolsContractFailures -join ', ')." }
$saveModuleMetadataSource = Get-Content (Join-Path $harnessRoot 'Agent-SaveMetadata.ps1') -Raw -Encoding UTF8
$saveModuleMetadataTest = Get-Content (Join-Path $harnessRoot 'Test-AgentSaveMetadata.ps1') -Raw -Encoding UTF8
if ($agentCliSource -notmatch 'Get-AgentSaveModuleIds -SavePath \$savePath' -or $saveModuleMetadataSource -notmatch 'Save metadata header length is invalid' -or $saveModuleMetadataTest -notmatch 'TruncatedHeaderRejected') { throw 'Save load must honor a validated, fixture-specific module set instead of guessing a default.' }
$startupEvidenceScript = Join-Path $harnessRoot 'HarnessStartupEvidence.ps1'
$contextFocusScript = Join-Path $harnessRoot 'Set-ContextFocus.ps1'
$researchReadinessScript = Join-Path $harnessRoot 'HarnessResearchReadiness.ps1'
$researchReadinessSource = Get-Content $researchReadinessScript -Raw -Encoding UTF8
. $researchReadinessScript
$contextFocusSource = Get-Content $contextFocusScript -Raw -Encoding UTF8
. $researchReadinessScript
$projectFile = Get-Content (Join-Path $harnessRoot 'ChronicleFramework.csproj') -Raw -Encoding UTF8
$developmentDoc = Get-Content (Join-Path $harnessRoot 'DEVELOPMENT.md') -Raw -Encoding UTF8
if ($developmentDoc -notmatch '不使用 Windows Computer Use 向游戏窗口发送鼠标或键盘输入' -or $developmentDoc -notmatch '会自动激活目标窗口' -or $developmentDoc -notmatch '后台窗口输入不会激活窗口') { throw 'Game UI automation must remain disabled until non-activating isolated input is evidenced.' }
$designDoc = Get-Content (Join-Path $harnessRoot 'DESIGN.md') -Raw -Encoding UTF8
$inventoryDoc = Get-Content (Join-Path $harnessRoot 'SYSTEM_INVENTORY.md') -Raw -Encoding UTF8
$rootAgents = Get-Content (Join-Path $projectRoot 'AGENTS.md') -Raw -Encoding UTF8
$runtimeGameRoot = if ($localSettings -and $localSettings.gameRoot) { [IO.Path]::GetFullPath([string]$localSettings.gameRoot) } else { $null }
$gitIgnore = Get-Content (Join-Path $projectRoot '.gitignore') -Raw -Encoding UTF8
$sourceManifestPath = Join-Path $projectRoot 'Modules\ChronicleFramework\SubModule.xml'
$moduleStringsSourcePath = Join-Path $projectRoot 'Modules\ChronicleFramework\ModuleData\global_strings.xml'
$moduleStringsSource = Get-Content $moduleStringsSourcePath -Raw -Encoding UTF8
$moduleManifestSource = Get-Content $sourceManifestPath -Raw -Encoding UTF8
$mainlinePath = Join-Path $harnessRoot ([string]$contextState.current.path)
$mainlineDoc = Get-Content $mainlinePath -Raw -Encoding UTF8
if (-not (Test-Path (Join-Path $harnessRoot 'ContextState.json'))) { throw 'ContextState.json is missing.' }
if ($runtimeGameRoot) {
    $runtimeAgentsPath = Join-Path $runtimeGameRoot 'AGENTS.md'
    if (Test-Path -LiteralPath $runtimeAgentsPath) {
        $trackedAgentsHash = (Get-FileHash -LiteralPath (Join-Path $projectRoot 'AGENTS.md') -Algorithm SHA256).Hash
        $runtimeAgentsHash = (Get-FileHash -LiteralPath $runtimeAgentsPath -Algorithm SHA256).Hash
        if ($trackedAgentsHash -ne $runtimeAgentsHash) { throw 'Repository AGENTS.md and game-workspace AGENTS.md copies have diverged.' }
    }
}
if ($projectFile -notmatch [regex]::Escape('<Compile Remove="TestResults/**/*.cs" />')) { throw 'ChronicleFramework.csproj must exclude generated/evidence C# sources under TestResults.' }

if ($harnessScript -notmatch "HarnessContractVersion\s*=\s*'$contractVersion'") {
    throw "Run-Harness.ps1 does not declare contract version $contractVersion."
}
$autonomyStages = [regex]::Match($harnessScript, "'AgentHostEstablishClanAutonomyEvaluation'\s*\{\s*@\(([^)]*)\)")
$autonomyStageList = if ($autonomyStages.Success) { $autonomyStages.Groups[1].Value } else { '' }
if (-not $autonomyStages.Success -or
    $autonomyStageList.IndexOf('AgentHostPackage', [StringComparison]::Ordinal) -lt 0 -or
    $autonomyStageList.IndexOf('Smoke', [StringComparison]::Ordinal) -lt 0 -or
    $autonomyStageList.IndexOf('AgentHostPackage', [StringComparison]::Ordinal) -gt $autonomyStageList.IndexOf('Smoke', [StringComparison]::Ordinal) -or
    $autonomyStageList.IndexOf('Smoke', [StringComparison]::Ordinal) -gt $autonomyStageList.IndexOf('AgentHostEstablishClanAutonomyEvaluation', [StringComparison]::Ordinal) -or
    $autonomyStageList.IndexOf('AgentHostProvider', [StringComparison]::Ordinal) -ge 0) {
    throw 'Live StoryMode autonomy evaluation must run package/Native startup checks, then use the exact real-model EYC classification as its first model request; do not spend an extra model call in AgentHostProvider.'
}
if ($agentHostLiveModelLoopSource -notmatch 'Set-LiveModelProviderTimeout' -or
    $agentHostLiveModelLoopSource -notmatch 'Resolve-LiveModelProviderTimeout' -or
    $agentHostLiveModelLoopSource -notmatch 'timeoutOverrideContract' -or
    $agentHostLiveModelLoopSource -match '\$env:CHRONICLE_LLM_TIMEOUT_SECONDS\s*=\s*''(180|360)''') {
    throw 'Live-model scenario defaults must honor a bounded explicit CHRONICLE_LLM_TIMEOUT_SECONDS override instead of resetting it.'
}
if ($harnessScript -notmatch 'GitCommit' -or $harnessScript -notmatch 'SourceControl' -or $harnessScript -notmatch 'status --porcelain' -or $harnessScript -match 'TaskBoard|CensusDomainDoneCount|gh project|gh api|githubProjectNumber') { throw 'Harness receipts must record Git provenance and remain independent of GitHub task tracking.' }
if ($projectFile -notmatch 'ChronicleGameRoot' -or $harnessScript -notmatch 'ChronicleGameRoot=\$gameRoot' -or -not (Test-Path -LiteralPath (Join-Path $harnessRoot 'Initialize-ChronicleWorkspace.ps1'))) { throw 'Cloned repositories must accept a local game path and provide a repeatable workspace initializer.' }
if ($projectFile -notmatch '<Content Remove="TestResults/\*\*/\*"' -or $projectFile -notmatch '<None Remove="TestResults/\*\*/\*"' -or
    $projectFile -notmatch '<Content Remove="AgentHost/\*\*/\*"' -or $projectFile -notmatch '<None Remove="AgentHost/\*\*/\*"') {
    throw 'Harness TestResults and AgentHost runtime outputs must be excluded from Mod project candidate assembly search paths so packaged runtimes cannot shadow game references.'
}
if ($projectFile -notmatch 'Reference Include="SandBox\.View"' -or $projectFile -notmatch 'Modules\\SandBox\\bin\\Win64_Shipping_Client\\SandBox\.View\.dll' -or $projectFile -notmatch 'Reference Include="TaleWorlds\.Core\.ViewModelCollection"' -or $projectFile -notmatch 'TaleWorlds\.Core\.ViewModelCollection\.dll' -or $projectFile -notmatch 'Reference Include="TaleWorlds\.InputSystem"' -or $projectFile -notmatch 'TaleWorlds\.InputSystem\.dll') { throw 'Native map inventory/menu and RecruitmentVM lifecycle support must bind to the installed 1.4.8 View, ViewModel, and InputSystem assemblies.' }
$providerSettingsSource = Get-Content (Join-Path $harnessRoot 'AgentProviderSettings.cs') -Raw -Encoding UTF8
$providerValidatorSource = Get-Content (Join-Path $harnessRoot 'AgentProviderConfigurationValidator.cs') -Raw -Encoding UTF8
$agentHostProjectSource = Get-Content (Join-Path $harnessRoot 'AgentHost\ChronicleAgentHost.csproj') -Raw -Encoding UTF8
if ($agentHostProjectSource -notmatch '<PackageReference Include="Microsoft\.ML\.Tokenizers" Version="\[2\.0\.1\]"' -or
    $agentHostProjectSource -notmatch '<RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>' -or
    $agentHostProjectSource -notmatch '<RuntimeIdentifiers>win-x64</RuntimeIdentifiers>' -or
    $agentHostProjectSource -notmatch 'CopyToPublishDirectory="PreserveNewest"' -or
    $agentHostProjectSource -notmatch 'deepseek_v4_tokenizer\.zip' -or
    $agentHostProjectSource -notmatch 'DeepSeekV4Tokenizer-LICENSE\.txt' -or
    $agentHostProjectSource -notmatch 'Resources\\\*\.txt') {
    throw 'The Agent Host must ship the pinned, MIT-noticed DeepSeek tokenizer data and its matching Microsoft tokenizer package.'
}
$tokenizerLockPath = Join-Path $harnessRoot 'AgentHost\packages.lock.json'
if (-not (Test-Path -LiteralPath $tokenizerLockPath -PathType Leaf)) { throw 'The Agent Host tokenizer package lock file is missing.' }
$tokenizerLock = Get-Content -LiteralPath $tokenizerLockPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$tokenizerLock.dependencies.'net8.0'.'Microsoft.ML.Tokenizers'.resolved -ne '2.0.1' -or
    [string]$tokenizerLock.dependencies.'net8.0'.'Google.Protobuf'.resolved -ne '3.30.2' -or
    $null -eq $tokenizerLock.dependencies.'net8.0/win-x64') {
    throw 'The Agent Host package lock must pin Microsoft.ML.Tokenizers 2.0.1 and its reviewed Google.Protobuf transitive dependency.'
}
$providerProfileSource = Get-Content (Join-Path $harnessRoot 'AgentHost\AgentProviderProfile.cs') -Raw -Encoding UTF8
$providerProfileTestSource = Get-Content (Join-Path $harnessRoot 'AgentHost\ProviderContractSelfTest.cs') -Raw -Encoding UTF8
$providerHostSource = Get-Content (Join-Path $harnessRoot 'AgentHost\OllamaNativeProvider.cs') -Raw -Encoding UTF8
$providerProgramSource = Get-Content (Join-Path $harnessRoot 'AgentHost\Program.cs') -Raw -Encoding UTF8
$providerSmokeSource = Get-Content (Join-Path $harnessRoot 'Test-AgentHostProvider.ps1') -Raw -Encoding UTF8
$supplyHostSource = Get-Content (Join-Path $harnessRoot 'AgentHost\AgentHostSupplyLoop.cs') -Raw -Encoding UTF8
$sourceModuleManifest = Get-Content $sourceManifestPath -Raw -Encoding UTF8
if ($projectFile -notmatch 'Reference Include="MCMv5"' -or $projectFile -notmatch 'Reference Include="0Harmony"' -or
    $sourceModuleManifest -notmatch 'DependedModule Id="Bannerlord\.Harmony" DependentVersion="[^"]+" Optional="false"' -or
    $sourceModuleManifest -notmatch 'DependedModule Id="Bannerlord\.ButterLib" DependentVersion="[^"]+" Optional="false"' -or
    $sourceModuleManifest -notmatch 'DependedModule Id="Bannerlord\.UIExtenderEx" DependentVersion="[^"]+" Optional="false"' -or
    $sourceModuleManifest -notmatch 'DependedModule Id="Bannerlord\.MBOptionScreen" DependentVersion="[^"]+" Optional="false"' -or
    $sourceModuleManifest -notmatch 'DependedModule Id="Native" DependentVersion="[^"]+" Optional="false"' -or
    $sourceModuleManifest -notmatch 'DependedModule Id="SandBoxCore" DependentVersion="[^"]+" Optional="false"' -or
    $sourceModuleManifest -notmatch 'DependedModule Id="SandBox" DependentVersion="[^"]+" Optional="false"' -or
    $providerSettingsSource -notmatch 'AttributeGlobalSettings<ChronicleAgentProviderSettings>' -or $providerSettingsSource -notmatch 'FormatType => "json"' -or
    $providerSettingsSource -notmatch 'OllamaBaseUrl' -or $providerSettingsSource -notmatch 'ModelId' -or
    $providerSettingsSource -notmatch 'api.deepseek.com/v1' -or $providerSettingsSource -notmatch 'deepseek-flash' -or
    $providerSettingsSource -notmatch 'OpenAI 兼容服务地址' -or $providerSettingsSource -notmatch 'CHRONICLE_LLM_API_KEY' -or
    $providerSettingsSource -notmatch 'EnvironmentVariableTarget.User' -or $providerSettingsSource -notmatch 'OutputMode' -or $providerSettingsSource -notmatch 'DeepSeekRunCostLimitCny' -or
    $providerSettingsSource -notmatch 'SettingPropertyButton' -or $providerSettingsSource -notmatch 'AgentProviderConfigurationValidator\.GetErrorCode' -or
    $providerSettingsSource -notmatch 'MBInformationManager\.AddQuickInformation' -or
    $providerSettingsSource -notmatch '(?s)public Action ValidateLocalConfiguration\s*\{\s*get => ShowConfigurationValidation;\s*set \{\s*\}\s*\}' -or
    $providerSettingsSource -notmatch 'CampaignGoal' -or $providerSettingsSource -notmatch 'StartAgent' -or $providerSettingsSource -notmatch 'StopAgent' -or $providerSettingsSource -notmatch 'ViewAgentStatus' -or
    $agentHostRuntimeControllerSource -notmatch 'ChronicleAgentHost\.exe' -or $agentHostRuntimeControllerSource -notmatch 'ResolveModuleRoot' -or
    $agentHostRuntimeControllerSource -notmatch 'RequestStart' -or $agentHostRuntimeControllerSource -notmatch 'RequestStop' -or $agentHostRuntimeControllerSource -notmatch 'host-stop-requested' -or
    $agentHostRuntimeControllerSource -notmatch 'Kill\(\)' -or $agentHostRuntimeControllerSource -notmatch 'IsOwnedLiveProcess' -or
    $agentHostRuntimeControllerSource -notmatch 'CHRONICLE_HARNESS_AGENT_AUTO_STOP_AFTER_MS' -or
    $agentHostRuntimeControllerSource -notmatch 'providerIsRemote' -or $agentHostRuntimeControllerSource -notmatch 'EnvironmentVariableTarget.User' -or
    $agentHostRuntimeControllerSource -notmatch 'settings.OutputMode' -or $agentHostRuntimeControllerSource -notmatch 'settings.DeepSeekRunCostLimitCny' -or
    $agentHostLifecycleEvaluationSource -notmatch 'AgentHostPackage\.log' -or $agentHostLifecycleEvaluationSource -notmatch 'agent-host-process-started' -or
    $agentHostLifecycleEvaluationSource -notmatch 'agent-host-process-exit' -or $agentHostLifecycleEvaluationSource -notmatch 'FixtureUnchanged' -or
    $providerValidatorSource -notmatch 'uri.Scheme == "http" && !uri.IsLoopback' -or $agentHostProjectSource -notmatch 'AgentProviderConfigurationValidator\.cs' -or
    $providerProfileSource -notmatch 'AgentProviderConfigurationValidator\.GetErrorCode' -or
    $providerProfileTestSource -notmatch 'mcm-profile-accepts-generic-https-openai-compatible-provider' -or
    $providerProfileTestSource -notmatch 'deepseek-auto-profile-selects-bounded-non-thinking-strict-tool-calls' -or
    $providerProfileTestSource -notmatch 'mcm-profile-rejects-insecure-remote-http' -or
    $providerProfileTestSource -notmatch 'mcm-profile-rejects-nonpositive-deepseek-run-budget' -or
    $providerProfileTestSource -notmatch 'deepseek-auto-profile-selects-bounded-non-thinking-strict-tool-calls' -or
    $providerProfileTestSource -notmatch 'mcm-global-profile-tolerates-legacy-and-unknown-fields' -or
    $providerProfileTestSource -notmatch 'provider-profile-reads-without-migrating-user-file' -or
    $providerProfileTestSource -notmatch 'provider-profile-error-path-mutated-file' -or
    $providerProfileTestSource -notmatch 'freellmapi-bearer-auth-available-model-preflight-and-routed-model-evidence' -or
    $providerProfileTestSource -notmatch 'freellmapi-profile-uses-bounded-512-token-live-model-budget' -or
    $providerProfileTestSource -notmatch 'provider-action-rationale-is-optional-and-native-catalog-still-gates' -or
    $providerHostSource -notmatch '\["anyOf"\]' -or $providerHostSource -match '\["oneOf"\]' -or
    $providerProfileTestSource -notmatch 'village-tools-prompt-uses-exact-native-action-id' -or
    $providerProfileTestSource -notmatch 'conversation is already open: never talk to that hero again' -or
    $providerProfileTestSource -notmatch 'only before a conversation is open, and only if talkToSettlementHero is currently listed' -or
    $providerProfileTestSource -notmatch 'Once the Journal confirms the Quest is active and tools are still owed, leave the Village and travel to a Town' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'village-tools-active-quest-dialogue-allows-leave-only-before-tools-obtained' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'village-tools-active-quest-giver-reopens-only-after-tools-and-inventory-baseline' -or
    $providerProfileTestSource -notmatch 'freellmapi-http-error-keeps-safe-route-fallback-headers-without-response-body' -or
    $providerProfileTestSource -notmatch 'freellmapi-json-schema-provider-rejection-falls-back-to-validated-json-object' -or
    $providerProfileTestSource -notmatch 'freellmapi-json-object-fallback-recognizes-schema-rejection-or-format-ignored-502-only' -or
    $providerProfileTestSource -notmatch 'freellmapi-format-ignored-502-falls-back-once-to-locally-normalized-native-action' -or
    $agentHostProviderSource -notmatch 'format_ignored' -or
    $providerProfileTestSource -notmatch 'freellmapi-transient-upstream-502-retried-once-before-native-action' -or
    $providerProfileTestSource -notmatch 'freellmapi-429-honors-bounded-retry-after-before-native-action' -or
    $providerProfileTestSource -notmatch 'freellmapi-exhaustion-body-eta-allows-one-bounded-retry' -or
    $providerProfileTestSource -notmatch 'freellmapi-exhaustion-body-beyond-deadline-fails-fast-with-safe-diagnostic' -or
    $providerProfileTestSource -notmatch 'freellmapi-429-allows-three-explicit-waits-then-fails-closed' -or
    $providerProfileTestSource -notmatch 'freellmapi-changing-retry-after-honors-later-in-deadline-window' -or
    $providerProfileTestSource -notmatch 'freellmapi-reclassifies-429-after-transient-upstream-retry' -or
    $providerProfileTestSource -notmatch 'freellmapi-429-reports-over-bound-retry-as-ineligible' -or
    $providerProfileTestSource -notmatch 'freellmapi-retry-after-delay-respects-overall-provider-timeout' -or
    $providerSmokeSource -notmatch 'function Resolve-ProviderSmokeTimeoutSeconds' -or
    $providerSmokeSource -notmatch 'Resolve-ProviderSmokeTimeoutSeconds \$null\) -ne 360' -or
    $providerSmokeSource -notmatch "CHRONICLE_LLM_MAX_TOKENS = '128'" -or
    $providerSmokeSource -notmatch 'EffectiveMaxOutputTokens = \[int\]\$env:CHRONICLE_LLM_MAX_TOKENS' -or
    $providerSmokeSource -match '\[ref\]\$effectiveTimeout' -or
    $providerProfileTestSource -notmatch 'freellmapi-429-accepts-observed-315-second-retry-and-fails-closed-outside-bounds' -or
    $providerProfileTestSource -notmatch 'freellmapi-two-transient-upstream-retries-bounded-before-native-action' -or
    $providerProfileTestSource -notmatch 'freellmapi-schema-fallback-then-transient-upstream-retry-is-bounded' -or
    $providerProfileTestSource -notmatch 'observedTokenParameters' -or
    $providerProfileTestSource -notmatch 'freellmapi-mistral-uses-validated-json-object-compatibility-mode' -or
    $providerProfileTestSource -notmatch 'freellmapi-ovh-model-rate-window-is-route-specific' -or
    $providerProfileTestSource -notmatch 'max_tokens' -or
    $providerProfileTestSource -notmatch 'mistralRequestShapeValid' -or
    $providerHostSource -notmatch 'IsMistralSmall32' -or $providerHostSource -notmatch 'GetMinimumRequestInterval' -or $providerHostSource -notmatch 'WaitForProviderRateWindowAsync' -or $providerHostSource -notmatch 'ShouldRetryTransientFreeLlmApiFailure' -or $providerHostSource -notmatch 'GetBoundedRateLimitRetryAfter' -or $providerHostSource -notmatch 'transientProviderRetriesUsed' -or $providerHostSource -notmatch 'retryDelaySeconds = transientProviderRetriesUsed == 0 \? 5 : 15' -or $providerHostSource -notmatch 'retryAfter=' -or $providerHostSource -notmatch 'failedRoute.Contains\("ovh/Mistral-Small"' -or $providerHostSource -notmatch 'payload.Remove\("max_completion_tokens"\)' -or $providerHostSource -notmatch 'ReadIntegerEnvironment\("CHRONICLE_LLM_MAX_TOKENS", 256, 64, 4096\)' -or
    $providerProfileTestSource -notmatch 'freellmapi-missing-key-fails-before-network-request' -or
    $providerSmokeSource -notmatch 'goalScopeClassificationRequired = \$true' -or
    $providerSmokeSource -notmatch 'goalScopeContract = ''native-campaign-goal-classification-v1''' -or
    $providerSmokeSource -notmatch 'No goal-specific game action has run yet' -or
    $providerSmokeSource -notmatch 'supportedVillageToolsQuestGoal' -or
    $providerSmokeSource -notmatch 'NativeCommands = 0' -or
    $providerSmokeSource -notmatch 'GatewayStartedByHarness = if \(\$freeLlmApiProfile\)' -or
    $providerSmokeSource -notmatch 'LocalProxyBootstrapApplied = if \(\$freeLlmApiProfile\)' -or
    $providerSmokeSource -notmatch 'DecisionClassification = \[string\]\$result.decision.goalClassification' -or
    $providerProgramSource -notmatch 'AgentHostDecisionCycle.DecideCampaignAsync' -or
    $providerSmokeSource -notmatch 'ResponseFormatMode = \[string\]\$result\.responseFormatMode' -or
    $providerHostSource -notmatch 'FREELLMAPI_API_KEY' -or $providerHostSource -notmatch 'CHRONICLE_LLM_API_KEY' -or
    $providerHostSource -notmatch 'X-Routed-Via' -or
    $providerProfileTestSource -notmatch 'mcm-global-profile-tolerates-legacy-and-unknown-fields' -or
    $providerProfileTestSource -notmatch 'provider-profile-reads-without-migrating-user-file' -or
    $providerProfileTestSource -notmatch 'provider-profile-error-path-mutated-file' -or
    $providerProfileTestSource -notmatch 'host-loads-authorized-harness-mcm-profile' -or
    $providerProfileTestSource -notmatch 'host-rejects-profile-outside-harness-root' -or
    $providerProfileSource -notmatch 'Configs.*ModSettings.*Global.*ChronicleFramework.*ChronicleAgentSettings\.json' -or
    $providerHostSource -notmatch 'FromConfiguredProfile' -or
    $supplyHostSource -notmatch 'OllamaNativeProvider\.FromConfiguredProfile') {
    throw 'Player model settings must expose an OpenAI-compatible endpoint with HTTPS-only remote transport, process/user-scoped secret lookup, and a matching Agent Host profile outside Harness overrides.'
}
if ($providerHostSource -notmatch 'defaultTimeoutSeconds = nativeOllama \? 60 : 360' -or
    $providerHostSource -notmatch 'maximumTimeoutSeconds = nativeOllama \? 240 : 360' -or
    $providerHostSource -notmatch 'ReadIntegerEnvironment\("CHRONICLE_LLM_TIMEOUT_SECONDS", defaultTimeoutSeconds, 5, maximumTimeoutSeconds\)' -or
    $providerHostSource -notmatch 'ReadIntegerEnvironment\("CHRONICLE_LLM_TIMEOUT_SECONDS", 360, 5, 360\)' -or
    $providerHostSource -notmatch 'maximumRateLimitRetries = retryHint.Source == "body-exhaustion" \? 1 : 3' -or
    $providerHostSource -notmatch 'ReadRateLimitRetryHintAsync' -or
    $providerHostSource -notmatch 'MaxRateLimitErrorBytes = 16 \* 1024' -or
    $providerHostSource -notmatch 'MinimumRateLimitRetryRequestBudget = TimeSpan.FromSeconds\(5\)' -or
    $providerHostSource -notmatch 'TimeSpan.FromSeconds\(360\)' -or
    $providerProfileTestSource -notmatch '315' -or
    $providerProfileTestSource -notmatch '361') {
    throw 'FreeLLMAPI recovery must permit the observed 315-second Retry-After inside a 360-second Host request deadline and reject waits above the bound.'
}
if ($agentHostCampaignLoopSource -notmatch 'ReadIntEnvironment\("CHRONICLE_NATIVE_MAILBOX_TIMEOUT_SECONDS", 180, 5, 240\)' -or
    $agentHostSupplyLoopSource -notmatch 'ReadIntEnvironment\("CHRONICLE_NATIVE_MAILBOX_TIMEOUT_SECONDS", 180, 5, 240\)') {
    throw 'Campaign and Supply Native mailbox waits must stay independently bounded and must not inherit the longer FreeLLMAPI model retry deadline.'
}
$smokeModuleSource = Get-Content (Join-Path $harnessRoot 'Test-Module.ps1') -Raw -Encoding UTF8
$releasePackageSource = Get-Content (Join-Path $harnessRoot 'New-ChronicleReleasePackage.ps1') -Raw -Encoding UTF8
$releasePackageTestSource = Get-Content (Join-Path $harnessRoot 'Test-AgentHostReleasePackage.ps1') -Raw -Encoding UTF8
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
$subModuleSource = Get-Content (Join-Path $harnessRoot 'SubModule.cs') -Raw -Encoding UTF8
if ($harnessScript -notmatch "HarnessContractVersion\s*=\s*'$contractVersion'" -or
    $smokeModuleSource -notmatch 'HarnessShaderCacheDialog\.ps1' -or $smokeModuleSource -notmatch 'Invoke-ChronicleShaderCacheDialogAcknowledgement' -or
    $smokeModuleSource -notmatch 'StartupDialogSnapshots' -or $smokeModuleSource -notmatch 'SmokeResult\.json' -or
    $smokeModuleSource -notmatch 'McmSettingsRegistered' -or $smokeModuleSource -notmatch 'requiredMcmButtonPropertyIds' -or
    $smokeModuleSource -notmatch 'StartupReadySeconds' -or $smokeModuleSource -notmatch 'stabilityCompleted' -or
    $smokeModuleSource -notmatch 'StartupTimeoutSeconds' -or $smokeModuleSource -notmatch 'ModuleIds = @\(\$modules\)' -or
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
$agentHostProviderSource = Get-Content (Join-Path $harnessRoot 'AgentHost\OllamaNativeProvider.cs') -Raw -Encoding UTF8
$agentHostProgramSource = Get-Content (Join-Path $harnessRoot 'AgentHost\Program.cs') -Raw -Encoding UTF8
$agentHostCampaignLoopSource = Get-Content (Join-Path $harnessRoot 'AgentHost\AgentHostCampaignLoop.cs') -Raw -Encoding UTF8
$agentHostSupplyLoopSource = Get-Content (Join-Path $harnessRoot 'AgentHost\AgentHostSupplyLoop.cs') -Raw -Encoding UTF8
$agentHostMailboxSource = Get-Content (Join-Path $harnessRoot 'AgentHost\NativeMailboxClient.cs') -Raw -Encoding UTF8
if ($agentHostProviderSource -notmatch 'CheckConfiguredModelAsync' -or $agentHostProviderSource -notmatch '/models' -or
    $agentHostProviderSource -notmatch 'FREELLMAPI_API_KEY' -or $agentHostProviderSource -notmatch 'X-Routed-Via' -or
    $agentHostProviderContractSelfTestSource -notmatch 'generic-https-openai-compatible-provider-health-auth-and-structured-decision' -or
    $agentHostProviderContractSelfTestSource -notmatch 'canonical-observe-again-decision-is-recognized-by-native-subloops' -or
    $agentHostProviderSource -notmatch 'IsListedSingleArgumentValue' -or $agentHostProviderSource -notmatch 'IsStoryModeClanNameTextArgument' -or
    $agentHostProviderContractSelfTestSource -notmatch 'provider-repairs-only-exact-listed-single-enum-argument-shorthand' -or
    $agentHostProviderContractSelfTestSource -notmatch 'provider-repairs-single-storymode-clan-name-text-shorthand-for-native-validation' -or
    $agentHostProviderContractSelfTestSource -notmatch 'deepseek-run-cost-reservation-rejects-over-budget-before-http' -or
    $agentHostHarnessProgressTraceSource -notmatch 'provider-progress-trace-records-request-size-cache-and-cost-without-request-content' -or
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
$agentHostLifecycleHarness = Get-Content (Join-Path $harnessRoot 'Test-AgentHostLifecycleEvaluation.ps1') -Raw -Encoding UTF8
$agentHostRuntimeControllerSource = Get-Content (Join-Path $harnessRoot 'AgentHostRuntimeController.cs') -Raw -Encoding UTF8
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
    $agentHostDecisionCycleSource -notmatch 'EstablishYourClanGoalPlannerPrompt' -or
    $agentHostDecisionCycleSource -notmatch 'JournalLog current/target values' -or
    $agentHostDecisionCycleSource -notmatch 'nativeProgressionContext.partySizeLimit' -or
    $agentHostDecisionCycleSource -notmatch 'DefaultPartySizeLimitModel' -or
    $agentHostDecisionCycleSource -notmatch 'confirmPartySizeWarning=1' -or
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
    $harnessScript -notmatch 'Join-Path \$repositoryRoot ''Modules\\ChronicleFramework\\ModuleData''' -or
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
    $agentHostRuntimeControllerSource -notmatch 'AgentHostLifecycleReceipt\.CaptureForHarness' -or
    $agentHostLifecycleReceiptSource -notmatch 'fresh-campaign-renown' -or
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
$agentHostCampaignTransitionSource = Get-Content (Join-Path $harnessRoot 'AgentHostCampaignTransitionHarness.cs') -Raw -Encoding UTF8
if ($agentHostLifecycleHarness -notmatch "'CampaignRoundtrip'" -or
    $agentCliSource -notmatch "'save'" -or $agentCliSource -notmatch "Invoke-ProtocolCommand 'save'" -or
    $agentCliSource -notmatch '\-ReturnWhenAccepted' -or
    $agentCliSource -notmatch 'Invoke-ProtocolCommand ''save''.*-ReturnWhenAccepted:\$ReturnWhenAccepted' -or
    $agentHostCampaignTransitionSource -notmatch 'MapScreen\.Instance' -or
    $agentHostCampaignTransitionSource -notmatch 'MapScreen\.OnExit' -or
    $agentHostCampaignTransitionSource -notmatch 'SandBoxSaveHelper\.TryLoadSave' -or
    $agentHostCampaignTransitionSource -notmatch 'CheckMetaDataCompatibilityErrors' -or
    $agentHostCampaignTransitionSource -notmatch 'native-save-helper-inquiry' -or
    $agentHostCampaignTransitionSource -notmatch 'CheckMetaDataCompatibilityErrors' -or
    $agentHostCampaignTransitionSource -notmatch 'OnNativeSaveStateChanged' -or
    $agentHostCampaignTransitionSource -notmatch 'native-save-helper-inquiry' -or
    $agentHostCampaignTransitionSource -notmatch 'AgentBridgeLifecycle' -or
    $agentHostCampaignTransitionSource -notmatch 'CampaignRoundtrip\.proceed' -or
    $agentHostCampaignTransitionSource -notmatch 'agent-host-lifecycle-test' -or
    $agentHostCampaignTransitionSource -notmatch 'CHRONICLE_HARNESS_AGENT_NO_MODEL' -or
    $agentHostCampaignTransitionSource -notmatch 'CHRONICLE_REPOSITORY_ROOT') {
    throw 'The same-process Campaign roundtrip must use the installed Native exit/load path, the fixed disposable fixture, and strict lifecycle/no-model/TestResults gates.'
}
$agentHostPackageSource = Get-Content (Join-Path $harnessRoot 'Test-AgentHostPackage.ps1') -Raw -Encoding UTF8
$agentHostProgramSource = Get-Content (Join-Path $harnessRoot 'AgentHost\Program.cs') -Raw -Encoding UTF8
if ($agentHostPackageSource -notmatch 'NU1900' -or $agentHostPackageSource -notmatch 'NuGetAudit=false' -or
    $agentHostPackageSource -notmatch 'PackageReference' -or
    $agentHostPackageSource -notmatch 'Microsoft.ML.Tokenizers' -or
    $agentHostPackageSource -notmatch '2.0.1' -or
    $agentHostPackageSource -notmatch 'Google.Protobuf' -or
    $agentHostPackageSource -notmatch 'THIRD-PARTY-NOTICES.txt') {
    throw 'NuGet audit fallback must be limited to a failed NU1900 vulnerability feed and the reviewed, pinned tokenizer dependency.'
}
if (-not (Test-Path -LiteralPath $deepSeekTokenizerAsset -PathType Leaf) -or
    -not (Test-Path -LiteralPath $deepSeekTokenizerLicense -PathType Leaf) -or
    -not (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $deepSeekTokenizerAsset) 'Microsoft.ML.Tokenizers-LICENSE.txt') -PathType Leaf) -or
    -not (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $deepSeekTokenizerAsset) 'Microsoft.ML.Tokenizers-THIRD-PARTY-NOTICES.txt') -PathType Leaf) -or
    -not (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $deepSeekTokenizerAsset) 'Google.Protobuf-LICENSE.txt') -PathType Leaf) -or
    -not (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $deepSeekTokenizerAsset) 'THIRD-PARTY-NOTICES.txt') -PathType Leaf) -or
    (Get-FileHash -LiteralPath $deepSeekTokenizerAsset -Algorithm SHA256).Hash -ne 'E7310D1DAFE0A86D8A5629FE78A7C763760F651DB9B8682718A1781DCD6FE495' -or
    $deepSeekTokenEstimatorSource -notmatch 'BpeOptions' -or
    $deepSeekTokenEstimatorSource -notmatch 'ByteLevel = true' -or
    $deepSeekTokenEstimatorSource -notmatch 'ReservationMargin' -or
    $deepSeekTokenEstimatorSource -notmatch 'utf8-byte-fallback' -or
    $deepSeekTokenEstimatorSource -notmatch 'OfficialTokenizerAssetSha256' -or
    $providerHostSource -notmatch 'DeepSeekPromptTokenEstimator\.EstimateRequest\(' -or
    $providerProfileTestSource -notmatch 'DeepSeekPromptTokenEstimator\.RunContractSelfTests' -or
    $agentHostHarnessProgressTraceSource -notmatch 'deepSeekEstimatedInputTokens' -or
    $agentHostHarnessProgressTraceSource -notmatch 'deepSeekRawRequestTokens' -or
    $agentHostHarnessProgressTraceSource -notmatch 'deepSeekReservedInputTokens') {
    throw 'DeepSeek token-cost estimation must use the hash-pinned official tokenizer asset, byte-level BPE, a conservative margin, and its safe byte-bound fallback.'
}
if ($harnessScript -notmatch "'AgentHostPackage'\s*\{ @\('Preflight', 'Build', 'AgentHostPackage'\) \}" -or
    $harnessScript -match "'All'\s*\{[^\r\n]*'AgentHostPackage'" -or
    $agentHostPackageSource -notmatch 'win-x64' -or $agentHostPackageSource -notmatch "'--self-contained',\s*'true'" -or
    $agentHostPackageSource -notmatch 'NUGET_PACKAGES' -or $agentHostPackageSource -notmatch '127\.0\.0\.1:7890' -or
    $agentHostPackageSource -notmatch 'function Test-BoundedTcpPort' -or $agentHostPackageSource -notmatch 'TimeoutMilliseconds = 500' -or $agentHostPackageSource -match 'Test-NetConnection' -or
    $agentHostPackageSource -notmatch 'D:\\ChronicleFramework\\BuildCache\\Packages' -or $agentHostPackageSource -notmatch 'package staging must be outside the source repository' -or
    $agentHostPackageSource -notmatch 'BaseOutputPath' -or
    $agentHostPackageSource -notmatch 'ChronicleAgentHost\.exe' -or $agentHostPackageSource -notmatch 'AgentHostPackageManifest\.json' -or
    $agentHostPackageSource -notmatch '\[switch\]\$RetainRuntimePackage' -or
    $agentHostPackageSource -notmatch '\[string\]\$CleanupPackageRoot' -or
    $agentHostPackageSource -notmatch 'Cleanup-only mode refuses while a Bannerlord or Agent Host process may still use the package' -or
    $agentHostPackageSource -notmatch 'PackageArtifactsRetained = \[bool\]\$RetainRuntimePackage' -or
    $agentHostPackageSource -notmatch 'AgentHostRuntimePackage\.json' -or
    $agentHostPackageSource -notmatch 'RuntimeExecutablePath' -or
    $agentHostPackageSource -notmatch 'Invoke-StaleAgentHostPackageCleanup' -or
    $agentHostPackageSource -notmatch 'OlderThanHours = 24' -or
    $agentHostPackageSource -notmatch 'CreationTimeUtc -lt \$cutoffUtc' -or
    $agentHostPackageSource -notmatch 'StalePackageCleanup = \$stalePackageCleanup' -or
    $agentHostPackageSource -notmatch 'Remove-Item -LiteralPath \$resolvedPackageRoot -Recurse -Force' -or
    $agentHostPackageSource -notmatch 'Refusing to remove package staging outside the exact unique Chronicle Agent Host cache directory' -or
    $agentHostPackageSource -notmatch 'Invoke-PackagedHostUnboundParentProbe' -or $agentHostPackageSource -notmatch 'UnboundParentRejected' -or
    $agentHostProviderSelfTestSource -notmatch 'RunParentProcessContractSelfTestsAsync' -or
    $agentHostProviderSelfTestSource -notmatch 'mcm-start-request-rejects-invalid-snapshot-without-profile-fallback' -or
    $agentHostProgramSource -notmatch 'campaign-parent-not-running' -or
    $agentHostProgramSource -notmatch '--package-health' -or $agentHostProgramSource -notmatch '--version') {
    throw 'Agent Host packaging must be an opt-in win-x64 self-contained publish, use D: NuGet cache/proxy port 7890, and directly verify the packaged Host without the .NET CLI.'
}
$initializerSource = Get-Content (Join-Path $harnessRoot 'Initialize-ChronicleWorkspace.ps1') -Raw -Encoding UTF8
if ($initializerSource -notmatch 'git -C \$PSScriptRoot rev-parse --show-toplevel' -or $initializerSource -notmatch 'not a Chronicle Framework source repository') { throw 'Workspace initialization must resolve and validate the Git root, including when invoked through an install-directory junction.' }
foreach ($ignoredPath in @('TestResults', 'obj', 'bin', 'harness.local.json')) { if ($gitIgnore -notmatch [regex]::Escape($ignoredPath)) { throw "Repository .gitignore must exclude generated/local data '$ignoredPath'." } }
if ($developmentDoc -notmatch 'GitHub Project 是工作项' -or $developmentDoc -notmatch '源码仓库位于 Bannerlord 安装目录之外' -or $developmentDoc -notmatch 'Harness不调用GitHub API/CLI') { throw 'Development policy must define decoupled task/source/runtime responsibilities.' }
if ($localSettings) {
    $forbiddenSettings = @($localSettings.PSObject.Properties.Name | Where-Object { $_ -match '^github' })
    if ($forbiddenSettings.Count -gt 0) { throw "Local Harness settings must not contain GitHub project state or credentials: $($forbiddenSettings -join ', ')." }
}
if (-not (Test-Path -LiteralPath $sourceManifestPath)) { throw 'The version-controlled Chronicle module manifest is missing.' }
[xml]$sourceModuleManifest = Get-Content -LiteralPath $sourceManifestPath -Encoding UTF8
if ([string]$sourceModuleManifest.Module.Id.value -ne 'ChronicleFramework') { throw 'The version-controlled manifest must declare ChronicleFramework.' }
if ($PSCommandPath -and ((Get-Content -LiteralPath $PSCommandPath -Raw -Encoding UTF8) -match '(?m)^\s*\$markdownBudget\s*=|^\s*\$byteBudget\s*=')) { throw 'Documentation byte/count ceilings must not force compression; use routing and informational size reporting.' }
if ($developmentDoc -notmatch '文档管理优先保证可读性' -or $developmentDoc -notmatch '不以总字数或文件总数强迫压缩' -or $rootAgents -notmatch '每个 `Research/<类别>/` 只维护一份权威文档') { throw 'Documentation policy must preserve readable documents and the one-authority-file-per-research-category rule.' }
if ($harnessScript -notmatch "VisualCapture'\s*\{\s*@\('Preflight', 'Build', 'VisualCapture'\)") { throw 'VisualCapture phase must run Preflight and Build before its capture test.' }
if ($harnessScript -notmatch "'JoinEncounterEligibility'\s*\{\s*@\('Preflight', 'Build', 'JoinEncounterEligibility'\)" -or $harnessScript -notmatch "Invoke-Stage -Name 'JoinEncounterEligibility'" -or $harnessScript -notmatch 'Test-AgentJoinEncounterEligibility\.ps1' -or $agentCliSource -notmatch "'HelpAttackers','Neutral'" -or $agentCliSource -notmatch 'relationProfile\s*=\s*if \(\$RelationProfile\)' -or $agentCliSource -notmatch 'harnessJoinEncounterDiagnostics.*\$PartyId') { throw 'JoinEncounterEligibility must be a standalone visual Harness phase and isolate reverse-side/neutral profiles from ordinary Agent actions.' }
if ($harnessScript -notmatch "'JoinEncounterAbandonArmy'\s*\{\s*@\('Preflight', 'Build', 'JoinEncounterAbandonArmy'\)" -or $harnessScript -notmatch "Invoke-Stage -Name 'JoinEncounterAbandonArmy'" -or $harnessScript -notmatch 'Test-AgentJoinEncounterAbandonArmy\.ps1' -or $agentCliSource -notmatch "'harnessPrepareArmyMemberForCurrentJoinEncounter'" -or $agentProtocolSource -notmatch 'case "harnessPrepareArmyMemberForCurrentJoinEncounter"' -or $agentProtocolSource -notmatch 'PrepareArmyMemberForCurrentJoinEncounter' -or $agentProtocolSource -notmatch 'CreateNpcBattleForPlayerJoin' -or $agentProtocolSource -notmatch 'BuildJoinEncounterDiagnostics') { throw 'JoinEncounterAbandonArmy must use a disposable Native Army-member fixture, a separate opt-in Harness phase and the native menu callback only.' }
$joinEncounterFixtureSource = Get-Content (Join-Path $harnessRoot 'HarnessJoinEncounterFixture.cs') -Raw -Encoding UTF8
if ($harnessScript -notmatch "'MovingArmyJoin'\s*\{\s*@\('Preflight', 'Build', 'MovingArmyJoin'\)" -or $harnessScript -notmatch "Invoke-Stage -Name 'MovingArmyJoin'" -or $harnessScript -notmatch 'Test-AgentMovingArmyJoin\.ps1' -or $agentCliSource -notmatch "'harnessPrepareMovingArmyEncounter'" -or $agentCliSource -notmatch "'harnessArmyEncounterDiagnostics'" -or $agentProtocolSource -notmatch 'case "harnessPrepareMovingArmyEncounter"' -or $agentProtocolSource -notmatch 'case "harnessArmyEncounterDiagnostics"' -or $joinEncounterFixtureSource -notmatch 'ChangeKingdomAction.ApplyByJoinToKingdom' -or $joinEncounterFixtureSource -notmatch 'BuildMovingArmyEncounterDiagnostics') { throw 'MovingArmyJoin must verify the nonengaged map-Army branch via the Army Encounter UI, isolated from active Battle assistance and Siege entry.' }
if ($harnessScript -notmatch "'JoinSiegeEvent'\s*\{\s*@\('Preflight', 'Build', 'JoinSiegeEvent'\)" -or $harnessScript -notmatch "Invoke-Stage -Name 'JoinSiegeEvent'" -or $harnessScript -notmatch 'Test-AgentJoinSiegeEvent\.ps1' -or $agentCliSource -notmatch "'harnessPrepareSiegeJoinFixture'" -or $agentCliSource -notmatch "'harnessSiegeJoinDiagnostics'" -or $agentProtocolSource -notmatch 'case "harnessPrepareSiegeJoinFixture"' -or $agentProtocolSource -notmatch 'case "harnessSiegeJoinDiagnostics"' -or $agentProtocolSource -notmatch 'PrepareNativeSiegeJoin' -or $agentProtocolSource -notmatch 'BuildSiegeJoinDiagnostics') { throw 'JoinSiegeEvent must be a separate native SiegeEvent menu phase, isolated from Army membership and Battle assistance.' }
if ($harnessScript -notmatch "TavernMission'\s*\{\s*@\('Preflight', 'Build', 'TavernMission'\)") { throw 'TavernMission phase must run Preflight and Build before its native entry test.' }
if ($harnessScript -notmatch "TownCenterMission'\s*\{\s*@\('Preflight', 'Build', 'TownCenterMission'\)") { throw 'TownCenterMission phase must run Preflight and Build before its native Town-center vertical-slice test.' }
if ($harnessScript -notmatch "SettlementOverlayConversation'\s*\{\s*@\('Preflight', 'Build', 'SettlementOverlayConversation'\)") { throw 'SettlementOverlayConversation phase must run Preflight and Build before its native target-Conversation validation.' }
if ($harnessScript -notmatch "SettlementOverlayQuickTalk'\s*\{\s*@\('Preflight', 'Build', 'SettlementOverlayQuickTalk'\)") { throw 'SettlementOverlayQuickTalk phase must run Preflight and Build before its native quick-talk return validation.' }
if ($harnessScript -notmatch "'All'\s*\{[^}]*'SettlementOverlayQuickTalk'") { throw 'The verified Native QuickConversation return route must remain covered by the full Harness regression.' }
if ($harnessScript -notmatch "SettlementOverlayQuestAcceptance'\s*\{\s*@\('Preflight', 'Build', 'SettlementOverlayQuestAcceptance'\)") { throw 'SettlementOverlayQuestAcceptance phase must run Preflight and Build before the native Issue Quest-acceptance validation.' }
if ($harnessScript -notmatch "SettlementOverlayQuestGate'\s*\{\s*@\('Preflight', 'Build', 'SettlementOverlayQuestGate'\)") { throw 'SettlementOverlayQuestGate phase must run Preflight and Build before its expected-native-refusal validation.' }
if ($harnessScript -notmatch "MapSettlementTargets'\s*\{\s*@\('Preflight', 'Build', 'MapSettlementTargets'\)") { throw 'MapSettlementTargets phase must run Preflight and Build before its visible/hidden target regression.' }
if ($harnessScript -notmatch "MainHeroSkills'\s*\{\s*@\('Preflight', 'Build', 'MainHeroSkills'\)") { throw 'MainHeroSkills phase must run Preflight and Build before its state-read regression.' }
if ($harnessScript -notmatch "CharacterDevelopment'\s*\{\s*@\('Preflight', 'Build', 'CharacterDevelopment'\)") { throw 'CharacterDevelopment phase must run Preflight and Build before its native VM comparison.' }
if ($harnessScript -notmatch "SpendSkillFocus'\s*\{\s*@\('Preflight', 'Build', 'SpendSkillFocus'\)") { throw 'SpendSkillFocus phase must run Preflight and Build before its native commit/rejection regression.' }
if ($harnessScript -notmatch "QuestJournal'\s*\{\s*@\('Preflight', 'Build', 'QuestJournal'\)") { throw 'QuestJournal phase must run Preflight and Build before accepting a native Quest and comparing journal details.' }
if ($harnessScript -notmatch "PartyRoster'\s*\{\s*@\('Preflight', 'Build', 'PartyRoster'\)") { throw 'PartyRoster phase must run Preflight and Build before comparing MainParty members and prisoners.' }
if ($harnessScript -notmatch "MapPartyTargets'\s*\{\s*@\('Preflight', 'Build', 'MapPartyTargets'\)") { throw 'MapPartyTargets phase must run Preflight and Build before comparing visible Party targets.' }
if ($harnessScript -notmatch "MapPartyComposition'\s*\{\s*@\('Preflight', 'Build', 'MapPartyComposition'\)") { throw 'MapPartyComposition phase must run Preflight and Build before comparing expanded native party tooltips.' }
if ($harnessScript -notmatch "MapArmyComposition'\s*\{\s*@\('Preflight', 'Build', 'MapArmyComposition'\)") { throw 'MapArmyComposition phase must run Preflight and Build before comparing native Army tooltip data.' }
if ($harnessScript -notmatch "MapPartyBehavior'\s*\{\s*@\('Preflight', 'Build', 'MapPartyBehavior'\)") { throw 'MapPartyBehavior phase must run Preflight and Build before comparing inspected behavior tooltip text.' }
if ($harnessScript -notmatch "PartyUpgrade'\s*\{\s*@\('Preflight', 'Build', 'PartyUpgrade'\)") { throw 'PartyUpgrade phase must run Preflight and Build before the native transaction regression.' }
if ($harnessScript -notmatch "PartyPrisonerRecruitment'\s*\{\s*@\('Preflight', 'Build', 'PartyPrisonerRecruitment'\)") { throw 'PartyPrisonerRecruitment phase must run Preflight and Build before the native prisoner recruitment regression.' }
if ($harnessScript -notmatch "MissionInteraction'\s*\{\s*@\('Preflight', 'Build', 'MissionInteraction'\)") { throw 'MissionInteraction phase must run Preflight and Build before the native Agent Use/conversation regression.' }
if ($harnessScript -notmatch "CompanionHiring'\s*\{\s*@\('Preflight', 'Build', 'CompanionHiring'\)") { throw 'CompanionHiring phase must run Preflight and Build before the Native Wanderer-hiring vertical slice.' }
if ($harnessScript -notmatch "PartyRoles'\s*\{\s*@\('Preflight', 'Build', 'PartyRoles'\)") { throw 'PartyRoles phase must run Preflight and Build before the native clan-role assignment/removal regression.' }
if ($harnessScript -notmatch "InventoryNavigation'\s*\{\s*@\('Preflight', 'Build', 'InventoryNavigation'\)") { throw 'InventoryNavigation phase must run Preflight and Build before testing native Inventory entry/time semantics.' }
if ($harnessScript -notmatch "EquipmentTransactions'\s*\{\s*@\('Preflight', 'Build', 'EquipmentTransactions'\)") { throw 'EquipmentTransactions phase must run Preflight and Build before native MainHero Equipment transaction validation.' }
$tavernMissionTest = Get-Content (Join-Path $harnessRoot 'Test-AgentTavernMission.ps1') -Raw -Encoding UTF8
$townCenterMissionTest = Get-Content (Join-Path $harnessRoot 'Test-AgentTownCenterMission.ps1') -Raw -Encoding UTF8
if ($tavernMissionTest -notmatch 'town_backstreet' -or $tavernMissionTest -notmatch 'town_tavern' -or $tavernMissionTest -notmatch "gameState -ne 'MissionState'" -or $tavernMissionTest -notmatch "timeControlMode -ne 'Stop'" -or $tavernMissionTest -notmatch 'state\.mission\.mainAgent' -or $tavernMissionTest -notmatch 'state\.mission\.combatType' -or $tavernMissionTest -notmatch 'missionInput' -or $tavernMissionTest -notmatch 'inputClearedAutomatically' -or $tavernMissionTest -notmatch 'settledDrift' -or $tavernMissionTest -notmatch 'captureFrame' -or $tavernMissionTest -notmatch 'TavernMissionResult\.json' -or $tavernMissionTest -notmatch 'FixtureUnchanged' -or $tavernMissionTest -notmatch 'ProcessStopped') { throw 'TavernMission must verify the native Town-to-Tavern MainAgent path, bounded movement/automatic release, scene combat/time context, engine screenshot, machine-readable result, fixture safety, and process cleanup.' }
$tavernDecisionProvider = Get-Content (Join-Path $harnessRoot 'Test-AgentLoopProvider.ps1') -Raw -Encoding UTF8
if ($tavernMissionTest -notmatch 'Agent-DecisionLoop\.ps1' -or $tavernMissionTest -notmatch "CHRONICLE_TEST_PROVIDER_MODE = 'tavernApproach'" -or $tavernMissionTest -notmatch 'TargetDistanceImproved' -or $tavernDecisionProvider -notmatch "CHRONICLE_TEST_PROVIDER_MODE -eq 'tavernApproach'" -or $tavernDecisionProvider -notmatch 'nearbyHeroAgents' -or $tavernDecisionProvider -notmatch 'lookDirection' -or $tavernDecisionProvider -notmatch "action = 'missionInput'") { throw 'TavernMission must verify the reproducible bounded movement/input-clear regression on its local Wanderer path.' }
if ($tavernMissionTest -notmatch 'state\.mission\.nativeFocus' -or $tavernMissionTest -notmatch 'state\.mission\.camera') { throw 'TavernMission must retain native focus and camera orientation evidence alongside candidate information.' }
if ($tavernMissionTest -notmatch 'missionNavigateToAgent' -or $tavernMissionTest -notmatch 'NativeNavigation' -or $tavernMissionTest -notmatch 'ControllerDuring' -or $tavernMissionTest -notmatch 'PlayerControllerRestored') { throw 'TavernMission must safely exercise native scripted navigation and prove the MainAgent Player controller is restored.' }
if ($townCenterMissionTest -notmatch "OptionId', 'town_streets'" -or $townCenterMissionTest -notmatch 'townExplore' -or $townCenterMissionTest -notmatch 'nearbySceneAgents' -or $townCenterMissionTest -notmatch 'missionNavigateToAgent' -or $townCenterMissionTest -notmatch 'NavigationMovementDistance' -or $townCenterMissionTest -notmatch 'NativeNavigation' -or $townCenterMissionTest -notmatch 'ControllerDuring' -or $townCenterMissionTest -notmatch 'PlayerControllerRestored' -or $townCenterMissionTest -notmatch 'missionAimAt' -or $townCenterMissionTest -notmatch 'FocusMatchesTarget' -or $townCenterMissionTest -notmatch 'TownCenterMissionResult\.json' -or $townCenterMissionTest -notmatch 'FixtureUnchanged' -or $townCenterMissionTest -notmatch 'ProcessStopped') { throw 'TownCenterMission must verify the native town_streets entry, bounded exploration, native NavMesh route/controller handoff and restoration, local-agent camera Focus probe, and cleanup evidence.' }
$settlementOverlayConversationTest = Get-Content (Join-Path $harnessRoot 'Test-AgentSettlementOverlayConversation.ps1') -Raw -Encoding UTF8
if ($settlementOverlayConversationTest -notmatch 'InteractionMode' -or $settlementOverlayConversationTest -notmatch 'QuickTalk' -or $settlementOverlayConversationTest -notmatch 'QuickTalkReturnedToSettlementMenu' -or $settlementOverlayConversationTest -notmatch 'TargetSettlementId' -or $settlementOverlayConversationTest -notmatch 'ApproachSettlementId' -or $settlementOverlayConversationTest -notmatch 'mapSettlementTargets' -or $settlementOverlayConversationTest -notmatch 'leaveApproachAndReobserve' -or $settlementOverlayConversationTest -notmatch 'settlementOverlayCharacters' -or $settlementOverlayConversationTest -notmatch 'questMarkers' -or $settlementOverlayConversationTest -notmatch 'visitSettlementHero' -or $settlementOverlayConversationTest -notmatch 'talkToSettlementHero' -or $settlementOverlayConversationTest -notmatch 'conversation.heroId' -or $settlementOverlayConversationTest -notmatch 'FixtureUnchanged' -or $settlementOverlayConversationTest -notmatch 'ProcessStopped' -or $settlementOverlayConversationTest -notmatch 'catch' -or $settlementOverlayConversationTest -notmatch 'Failure.json' -or $settlementOverlayConversationTest -notmatch 'AvailableMenuOptions' -or $settlementOverlayConversationTest -notmatch 'captureFrame' -or $settlementOverlayConversationTest -notmatch 'EngineMapFrame') { throw 'Settlement overlay tests must preserve separate QuickTalk and Visit routes, observe and close QuickConversation in MapState, verify visible Issue markers, preserve the fixture, clean the process, and retain structured failure evidence.' }
if ($settlementOverlayConversationTest -notmatch 'ExpectedOutcome' -or $settlementOverlayConversationTest -notmatch 'QuestAccepted' -or $settlementOverlayConversationTest -notmatch 'NativePreconditionBlocked' -or $settlementOverlayConversationTest -notmatch 'IssueGateProbe' -or $settlementOverlayConversationTest -notmatch 'NativeIssueGateDiagnostics' -or $settlementOverlayConversationTest -notmatch 'harnessMapDiagnostics' -or $settlementOverlayConversationTest -notmatch 'ExpectedOutcomeMet' -or $settlementOverlayConversationTest -notmatch 'issue_offer_player_accept_quest' -or $settlementOverlayConversationTest -notmatch 'issue_explanation_player_response_pre_quest_solution' -or $settlementOverlayConversationTest -notmatch 'IssueTopicRequested' -or $settlementOverlayConversationTest -notmatch 'QuestBlockedReason' -or $settlementOverlayConversationTest -notmatch 'NativeRefusalSentence' -or $settlementOverlayConversationTest -notmatch 'dialogueSelect') { throw 'W2-E must keep Quest acceptance and native-precondition rejection as separate explicit outcomes; a rejection cannot satisfy successful Quest acceptance.' }
if ($harnessScript -notmatch "'SettlementOverlayQuickTalkIssueGateProbe' \{ @\('Preflight', 'Build', 'SettlementOverlayQuickTalkIssueGateProbe'\) \}" -or $harnessScript -notmatch 'ExpectedOutcome IssueGateProbe' -or $settlementOverlayConversationTest -notmatch 'issue_offer_player_accept_quest' -or $settlementOverlayConversationTest -notmatch 'NativeIssueGateDiagnostics') { throw 'The no-model QuickTalk Issue gate probe must inspect same-type issue/relationship/war gates, follow only the explanatory screen, and stop at the direct Quest offer without accepting it or selecting the Alternative outcome.' }
if ($settlementOverlayConversationTest -notmatch 'issue_alternative_solution_player_response' -or $settlementOverlayConversationTest -notmatch 'AlternativeExplanationRequested' -or $agentHostVillageToolsQuestPolicySource -notmatch 'issue_offer_player_accept_alternative' -or $agentHostVillageToolsQuestPolicySource -notmatch 'issue_offer_player_accept_lord') { throw 'The Native Alternative explanation entry may be followed to expose the final offer, but final Alternative/Lord acceptance must remain outside the Quest loop.' }
if ($harnessScript -notmatch "FreshCampaign'\s*\{\s*@\('Preflight', 'Build', 'FreshCampaign'\)") { throw 'FreshCampaign phase must run Preflight and Build before its test.' }
if ($harnessScript -notmatch "FreshCampaignProgression'\s*\{\s*@\('Preflight', 'Build', 'FreshCampaignProgression'\)") { throw 'FreshCampaignProgression phase must run Preflight and Build before its test.' }
if ($harnessScript -notmatch "FreshCampaignBaselineMatrix'\s*\{\s*@\('Preflight', 'Build', 'FreshCampaignBaselineMatrix'\)" -or $harnessScript -match "'All'\s*\{[^\r\n]*'FreshCampaignBaselineMatrix'") { throw 'FreshCampaignBaselineMatrix must remain a selective five-instance evaluation phase outside All.' }
if ($harnessScript -notmatch "FreshCampaignSupplyBaseline'\s*\{\s*@\('Preflight', 'Build', 'FreshCampaignSupplyBaseline'\)" -or $harnessScript -match "'All'\s*\{[^\r\n]*'FreshCampaignSupplyBaseline'") { throw 'FreshCampaignSupplyBaseline must remain an opt-in selective evaluation phase, outside All.' }
if ($harnessScript -notmatch "FreshCampaignRecruitmentFallback'\s*\{\s*@\('Preflight', 'Build', 'FreshCampaignRecruitmentFallback'\)" -or $harnessScript -match "'All'\s*\{[^\r\n]*'FreshCampaignRecruitmentFallback'") { throw 'FreshCampaignRecruitmentFallback must remain an opt-in selective evaluation phase, outside All.' }
if ($harnessScript -notmatch "FreshCampaignLiveModelEvaluation'\s*\{\s*@\('Preflight', 'Build', 'FreshCampaignLiveModelEvaluation'\)" -or $harnessScript -match "'All'\s*\{[^\r\n]*'FreshCampaignLiveModelEvaluation'") { throw 'FreshCampaignLiveModelEvaluation must remain a selective opt-in candidate phase outside All.' }
if ($freshCampaignBaselineMatrixSource -notmatch '\$Runs = 5' -or $freshCampaignBaselineMatrixSource -notmatch 'ChronicleCampaignInstanceId' -or $freshCampaignBaselineMatrixSource -notmatch 'CampaignSeed = ''unknown; instance ID is not the Native RNG seed''' -or $freshCampaignBaselineMatrixSource -notmatch 'SourceSaveFilesUnchanged' -or $freshCampaignBaselineMatrixSource -notmatch 'RecruitmentProgression') { throw 'Fresh-campaign matrix must repeat five independently created Campaigns, record each opportunity/outcome and cleanup, and never present the Chronicle instance ID as an RNG seed.' }
if ($freshCampaignSource -notmatch 'RetainDisposableSave' -or $freshCampaignSource -notmatch 'DisposableSaveRetained' -or $freshCampaignSource -notmatch 'Get-SaveManifestDigest -ExcludeSaveName' -or $freshCampaignSupplyBaselineSource -notmatch 'RetainDisposableSave' -or $freshCampaignSupplyBaselineSource -notmatch 'Test-AgentMultiDaySupplyBaseline\.ps1' -or $freshCampaignSupplyBaselineSource -notmatch 'CampaignInstanceId' -or $freshCampaignSupplyBaselineSource -notmatch 'CaptureVisualEvidence' -or $freshCampaignSupplyBaselineSource -notmatch 'DisposableSaveRemoved' -or $freshCampaignSupplyBaselineSource -notmatch 'CampaignSeed = ''unknown; Chronicle Campaign instance identity is not represented as the Native RNG seed''') { throw 'Fresh-Campaign paired supply baselines must use an owned native-created disposable save, match both Native branches to its Campaign identity, record visual evidence, and clean the save.' }
if ($freshCampaignRecruitmentFallbackSource -notmatch 'leave-prepared-town' -or $freshCampaignRecruitmentFallbackSource -notmatch "state.context.gameState -ne 'MapState'" -or $freshCampaignRecruitmentFallbackSource -notmatch '\$preparedMarketTownId' -or
    $multiDaySupplyBaselineSource -notmatch 'elseif \(\$StartAtCurrentTown\)' -or $multiDaySupplyBaselineSource -notmatch 'prepared-map-towns' -or
    $freshCampaignRecruitmentFallbackSource -notmatch '\$MaxAttempts = 10' -or $freshCampaignRecruitmentFallbackSource -notmatch "'mapSettlementTargets'" -or $freshCampaignRecruitmentFallbackSource -notmatch 'Get-SafeVisibleSettlementTargets' -or $freshCampaignRecruitmentFallbackSource -notmatch 'RecruitmentVM' -or $freshCampaignRecruitmentFallbackSource -notmatch '\.available' -or $freshCampaignRecruitmentFallbackSource -notmatch 'FirstSettlementRecruitmentShortageObserved' -or $freshCampaignRecruitmentFallbackSource -notmatch 'fallback-reached-six-and-market-town' -or $freshCampaignRecruitmentFallbackSource -notmatch 'StartAtCurrentTown' -or $freshCampaignRecruitmentFallbackSource -notmatch 'VideoRemovedAfterEvidence') { throw 'Recruitment fallback evaluation must use only current Native-visible safe targets and offers, bound campaign attempts, save the paired fixture from MapState, preserve the verified Town id, and retain cleanup/video evidence.' }
if ($multiDaySupplyBaselineSource -notmatch 'CampaignInstanceMatched' -or $multiDaySupplyBaselineSource -notmatch 'Start-ChronicleWindowVideoCapture' -or $multiDaySupplyBaselineSource -notmatch 'VideoRemovedAfterEvidence' -or $multiDaySupplyBaselineSource -notmatch "'advance','pause','resume','fastForward'") { throw 'Paired Native supply branches must record runtime Campaign identities, capture actual UI transitions, remove successful clips after timeline extraction, and prove no Harness clock action was used.' }
if ($freshCampaignSource -notmatch "'agentCheckpointGet'" -or $freshCampaignSource -notmatch 'ChronicleCampaignInstanceId') { throw 'FreshCampaign progression must capture the Chronicle Campaign instance identity through the read-only Native checkpoint endpoint.' }
if ($freshCampaignSource -notmatch 'HarnessShaderCacheDialog\.ps1' -or $freshCampaignSource -notmatch 'Invoke-ChronicleShaderCacheDialogAcknowledgement' -or $freshCampaignSource -notmatch 'StartupDialogReceipts' -or $freshCampaignBaselineMatrixSource -notmatch 'FreshCampaignChildResult\.json' -or $freshCampaignBaselineMatrixSource -notmatch 'StartupDialogReceipts') { throw 'FreshCampaign tests must use the exact process-owned shader-cache dialog handler, retain its receipt, and preserve per-instance child evidence.' }
if ($freshCampaignSource -notmatch 'RealModelRecruitment' -or $freshCampaignSource -notmatch 'Test-AgentLiveModelLoop\.ps1' -or $freshCampaignSource -notmatch 'PreNativeRejectedDecisions' -or $freshCampaignLiveModelEvaluationSource -notmatch '\$Runs = 5' -or $freshCampaignLiveModelEvaluationSource -notmatch 'WallClockLimitSeconds = 180' -or $freshCampaignLiveModelEvaluationSource -notmatch 'CampaignDayLimit = 0\.1' -or $freshCampaignLiveModelEvaluationSource -notmatch 'ModelCatalogSha256' -or $freshCampaignLiveModelEvaluationSource -notmatch 'Initialize-FreeLLMAPIProfile' -or $freshCampaignLiveModelEvaluationSource -notmatch 'ModelGateway = ''FreeLLMAPI''' -or $freshCampaignLiveModelEvaluationSource -notmatch 'DistinctCampaignInstances' -or $freshCampaignLiveModelEvaluationSource -notmatch 'VideoRemovedAfterEvidence' -or $freshCampaignLiveModelEvaluationSource -notmatch 'Get-HarnessSourceManifestHash' -or $freshCampaignLiveModelEvaluationSource -notmatch 'SourceChangedDuringEvaluation' -or $freshCampaignLiveModelEvaluationSource -notmatch 'HarnessSourceIntegrityPassed') { throw 'FreshCampaign live-model evaluation must start from new Native Campaign state, preflight the FreeLLMAPI catalog, record its fingerprint/model route and retain fixed thresholds without mixing source versions.' }
if ($harnessScript -notmatch 'FreshCampaignProgressionAttempt\$attempt' -or $harnessScript -notmatch '\$attempt -le 2' -or $harnessScript -notmatch 'Get-ChronicleStartupAssessment' -or $harnessScript -notmatch 'startupClassification' -or $harnessScript -notmatch 'progressionFailureDetail' -or $harnessScript -notmatch 'characterCreationCompleted' -or $harnessScript -notmatch 'Get-Content -LiteralPath \$testResult\.RglLog -Tail 8' -or $harnessScript -notmatch 'ConvertTo-ChronicleLogTail -Lines \$rglLogLines' -or -not (Test-Path -LiteralPath $startupEvidenceScript)) { throw 'FreshCampaignProgression must retain stage/failure detail and normalize its short RGL tail.' }
if ($harnessScript -notmatch 'recruitmentProgression = \$testResult\.RecruitmentProgression' -or $harnessScript -notmatch 'progressionSaveCycleVerified' -or $harnessScript -notmatch 'freshClanRenown = \$testResult\.ClanRenown') { throw 'FreshCampaignProgression must preserve the measurable baseline, save cycle, and recruit receipt summary.' }
. $startupEvidenceScript
if (-not (Test-ChronicleStartupAssessment)) { throw 'Startup evidence regression checks failed.' }
$startupEvidenceSource = Get-Content -LiteralPath $startupEvidenceScript -Raw -Encoding UTF8
if (-not (Test-ChronicleSteamClientReadiness)) { throw 'Steam API readiness regression checks failed.' }
if ($startupEvidenceSource -notmatch 'function Ensure-ChronicleSteamClientReady' -or
    $startupEvidenceSource -notmatch "ArgumentList '-silent'.*-WindowStyle Hidden" -or
    $startupEvidenceSource -notmatch 'function Start-ChronicleSteamGame' -or
    $startupEvidenceSource -notmatch 'function Disable-ChronicleHarnessGameSound' -or
    $startupEvidenceSource -notmatch 'function Restore-ChronicleHarnessGameSound' -or
    $startupEvidenceSource -notmatch 'disable_sound\\s\*=\\s\*' -or
    $harnessScript -notmatch 'BannerlordSoundRecoveryOnHarnessStart' -or
    $startupEvidenceSource -notmatch "steam_appid\.txt" -or
    $startupEvidenceSource -notmatch "SetEnvironmentVariable\('SteamAppId'" -or
    $startupEvidenceSource -notmatch "SetEnvironmentVariable\('SteamGameId'" -or
    $agentCliSource -notmatch 'Ensure-ChronicleSteamClientReady' -or
    $agentCliSource -notmatch 'Start-ChronicleSteamGame -FilePath \$launcher' -or
    $agentCliSource -notmatch 'Disable-ChronicleHarnessGameSound' -or
    $agentCliSource -notmatch 'Restore-ChronicleHarnessGameSound' -or
    $freshCampaignSource -notmatch 'Start-ChronicleSteamGame -FilePath \$launcher' -or
    $freshCampaignSource -notmatch 'Disable-ChronicleHarnessGameSound' -or
    $freshCampaignSource -notmatch 'Restore-ChronicleHarnessGameSound' -or
    $freshCampaignSource -notmatch 'BannerlordSoundMutedForHarness' -or
    $campaignTestSource -notmatch 'Start-ChronicleSteamGame -FilePath \$launcher' -or
    $campaignTestSource -notmatch 'Disable-ChronicleHarnessGameSound' -or
    $campaignTestSource -notmatch 'Restore-ChronicleHarnessGameSound' -or
    $campaignTestSource -notmatch 'Ensure-ChronicleSteamClientReady' -or
    $smokeModuleSource -notmatch 'Ensure-ChronicleSteamClientReady' -or
    $smokeModuleSource -notmatch 'Start-ChronicleSteamGame -FilePath \$gameExe' -or
    $smokeModuleSource -notmatch 'Disable-ChronicleHarnessGameSound' -or
    $smokeModuleSource -notmatch 'Restore-ChronicleHarnessGameSound' -or
    $smokeModuleSource -notmatch 'BannerlordSoundMutedForHarness' -or
    $smokeModuleSource -notmatch 'BannerlordSoundRestored' -or
    $smokeModuleSource -notmatch 'SteamClient = \[ordered\]@\{' -or
    $smokeModuleSource -notmatch 'startedByHarness = \[bool\]\$steamStatus\.startedByHarness' -or
    $smokeModuleSource -notmatch 'SteamProcessCount = \[int\]\$steamStatus\.readiness\.SteamProcessCount' -or
    $smokeModuleSource -notmatch 'WebHelperStableSeconds = \[double\]\$steamStatus\.readiness\.WebHelperStableSeconds' -or
    $smokeModuleSource.IndexOf('Ensure-ChronicleSteamClientReady', [StringComparison]::Ordinal) -gt $smokeModuleSource.IndexOf('Start-ChronicleSteamGame -FilePath $gameExe', [StringComparison]::Ordinal)) {
    throw 'Every Harness-owned Bannerlord launch must use the shared Steam readiness gate and reversible game-only sound guard; Smoke must record readiness and sound restoration.'
}
if (-not (Test-ChronicleStartupDialogEvidenceSerialization)) { throw 'Startup dialog evidence retained a live UI Automation object instead of a serializable snapshot.' }
if (-not (Test-ChronicleReceiptSerialization)) { throw 'Receipt normalization changed primitive/list data or retained PowerShell object metadata.' }
$retentionSelfTestOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $testResultsRetentionScript -SelfTest 2>&1 | Out-String
if ($LASTEXITCODE -ne 0 -or -not ($retentionSelfTestOutput | ConvertFrom-Json).Passed) { throw "TestResults retention safety regression failed: $retentionSelfTestOutput" }
$retentionSource = Get-Content -LiteralPath $testResultsRetentionScript -Raw -Encoding UTF8
$expectedTimestampFolderPattern = '$_.Name -match ''^\d{8}-\d{6}$'''
$retentionSelfTest = $retentionSelfTestOutput | ConvertFrom-Json
if ($harnessScript -notmatch 'Prune-TestResults\.ps1' -or $harnessScript -notmatch '-CurrentRunId \$runId -Apply' -or -not $retentionSource.Contains($expectedTimestampFolderPattern) -or $retentionSource -notmatch 'ProtectedDocumentRunCount' -or $retentionSource -notmatch 'PreservedIncompleteCaptureRuns' -or $retentionSource -notmatch 'KeepMostRecentRuns' -or $retentionSource -notmatch 'knownUndecodable' -or $retentionSource -notmatch 'removedAfterEvidence' -or -not $retentionSelfTest.ContactSheetOnlyCapturePruned -or -not $retentionSelfTest.CitedAndIndexedMediaPreserved -or -not $retentionSelfTest.HistoricalContextFramesCompacted -or -not $retentionSelfTest.RedundantHistoricalMediaCompacted -or $harnessScript -notmatch 'DeletedUndecodableVideoBytes' -or $harnessScript -notmatch 'CompactedMediaBytes' -or $retentionSource -notmatch 'historical-event-frames-only' -or $retentionSource -notmatch 'Complete = \$skippedRuns\.Count -eq 0') { throw 'TestResults retention must protect active, documented and recent receipts plus incomplete captures, retain historical event frames, compact redundant adjacent frames only after index updates, and preserve explicitly cited images.' }
if (-not (Test-ChronicleLogTailNormalization -Path $startupEvidenceScript)) { throw 'Get-Content log-tail normalization regression checks failed.' }
$protocolSource = Get-Content (Join-Path (Split-Path -Parent $harnessRoot) 'ChronicleFramework\AgentProtocol.cs') -Raw -Encoding UTF8
if ($protocolSource -notmatch 'postbattle-renown-telemetry-failed' -or $protocolSource -notmatch 'visual-battle-fixture' -or $protocolSource -notmatch 'winnerRenownValue' -or $protocolSource -notmatch 'loserStrengthReductionFactorAfterFinish') { throw 'PostBattle renown telemetry must remain fixture-only and report model inputs/results without changing battle rules.' }
if ($protocolSource -notmatch 'captureFrame is restricted to visual Harness modes' -or $protocolSource -notmatch 'Utilities\.TakeScreenshot\(capturePath\)') { throw 'Harness-only engine screenshot contract is missing.' }
if ($protocolSource -notmatch '_pendingClaimedCommandPath' -or $protocolSource -notmatch 'agent-command-read-retry' -or $protocolSource -notmatch 'FileShare\.ReadWrite \| FileShare\.Delete') { throw 'Transiently locked commands must remain claimed and retry instead of being deleted/lost.' }
$videoCaptureSource = Get-Content (Join-Path $harnessRoot 'HarnessVideoCapture.ps1') -Raw -Encoding UTF8
$agentBattleFixtureSource = Get-Content (Join-Path $harnessRoot 'Test-AgentBattleFixture.ps1') -Raw -Encoding UTF8
$agentVisualCaptureSource = Get-Content (Join-Path $harnessRoot 'Test-AgentVisualCapture.ps1') -Raw -Encoding UTF8
if ($videoCaptureSource -notmatch 'gfxcapture=hwnd=') { throw 'Continuous capture must bind only to an explicit Bannerlord HWND.' }
if ($videoCaptureSource -notmatch 'FrameCoverageRatio' -or $videoCaptureSource -notmatch 'TimelineIndexPath' -or $videoCaptureSource -notmatch '\$contactFrameBudget = 64\.0' -or $videoCaptureSource -notmatch 'Remove-Item -LiteralPath \$Capture\.OutputPath' -or $videoCaptureSource -notmatch 'Explicit Bannerlord HWND') { throw 'Continuous capture must validate coverage, cap the contact sheet, create the event timeline, and remove a complete source clip after indexing.' }
if ($agentLiveModelLoopSource -match 'Stop-ChronicleWindowVideoCapture[^\r\n]*-KeepVideo' -or $agentLiveModelResumeSource -match 'Stop-ChronicleWindowVideoCapture[^\r\n]*-KeepVideo' -or $agentBattleFixtureSource -match 'Stop-ChronicleWindowVideoCapture[^\r\n]*-KeepVideo' -or $agentVisualCaptureSource -match 'Stop-ChronicleWindowVideoCapture[^\r\n]*-KeepVideo' -or $agentLiveModelLoopSource -notmatch 'SourceVideoRemovedAfterKeyframes') { throw 'No Harness path may retain a fully postprocessed MP4 merely because gameplay/model assertions failed; only postprocessing failures retain a clip.' }
if ($agentProtocolSource -notmatch 'MaxProtocolEventLogBytes = 16L \* 1024 \* 1024' -or $agentProtocolSource -notmatch 'AppendBoundedProtocolEventLog' -or -not $agentProtocolSource.Contains('currentBytes + incomingBytes > MaxProtocolEventLogBytes')) { throw 'The persistent Native protocol event log must enforce its 16 MiB bound.' }
if ($videoCaptureSource -notmatch "'mapSettlementTargets'.*'move'.*'recruitOptions'.*'recruit'.*'provision'.*'tradeConfirm'.*'rest'.*'providerDone'.*'modelLoopFailure'") { throw 'Contact-sheet/event timeline must preserve aligned map, trade, wait and failure transitions.' }
if ($videoCaptureSource -notmatch 'function Test-ChronicleFragmentedCaptureResilience' -or $videoCaptureSource -notmatch 'testsrc2=size=320x180:rate=5' -or $videoCaptureSource -notmatch 'Get-Command ffprobe\.exe' -or $videoCaptureSource -notmatch 'count_frames -select_streams v:0' -or $videoCaptureSource -notmatch 'TemporaryArtifactsRemoved' -or $agentLiveModelLoopSource -notmatch 'Test-ChronicleFragmentedCaptureResilience' -or $agentLiveModelLoopSource -notmatch 'CaptureRecoveryProof') { throw 'Live capture must prove that an abruptly interrupted fragmented MP4 remains decodable before starting a long Campaign run and retain a compact recovery receipt.' }
$battleFixtureSource = Get-Content (Join-Path $harnessRoot 'Test-AgentBattleFixture.ps1') -Raw -Encoding UTF8
if ($videoCaptureSource -notmatch 'keyframeInterval = \[Math\]::Max\(1, \$FrameRate \* 2\)' -or $videoCaptureSource -notmatch 'movflags \+frag_keyframe\+empty_moov\+default_base_moof' -or $videoCaptureSource -notmatch '\$contactFrameBudget = 64\.0' -or $videoCaptureSource -notmatch '\[Math\]::Min\(0\.25, \$contactFrameBudget / \[Math\]::Max\(1\.0, \$duration\)\)' -or $videoCaptureSource -notmatch 'frameExtractionFailures') { throw 'Continuous Bannerlord capture must preserve decodable interrupted clips, cap contact-sheet dimensions, record partial keyframe extraction failures, and still remove the raw clip when review evidence exists.' }
if ($battleFixtureSource -notmatch 'BattleRewardTelemetry = if \(\$simulationFinish -and \$simulationFinish\.data\)') { throw 'PostBattle evidence must preserve the returned renown telemetry object.' }
if ($protocolSource -notmatch 'inventoryDone refuses to skip the Native' -or $protocolSource -notmatch 'GetElementCountOnSide\(TaleWorlds\.CampaignSystem\.Inventory\.InventoryLogic\.InventorySide\.OtherInventory\) > 0' -or $battleFixtureSource -notmatch 'prematureInventoryDoneRejected' -or $battleFixtureSource -notmatch 'prematureInventoryDonePreservedLoot' -or $battleFixtureSource -notmatch 'CampaignDayAtBattleSimulationStart' -or $battleFixtureSource -notmatch 'TimeControlModeAtPostBattleMapReturn') { throw 'Loot Done must not bypass the Native remaining-loot inquiry: guard unclaimed loot, test no-mutation refusal, then verify Take All/Done and record campaign clock around BattleSimulation.' }
if ($battleFixtureSource -notmatch 'Start-ChronicleWindowVideoCapture' -or $battleFixtureSource -notmatch 'BattleToLoot-events\.jsonl' -or $battleFixtureSource -notmatch 'videoCapturePassed') { throw 'PostBattle must collect continuous HWND video, aligned action/state events, and enforce capture coverage.' }
if ($battleFixtureSource -notmatch 'RenownProgressionPassed' -or $battleFixtureSource -notmatch 'ClanRenownDelta -gt 0' -or $battleFixtureSource -notmatch 'BattleRewardTelemetryPassed' -or $battleFixtureSource -notmatch 'playerContribution' -or $battleFixtureSource -notmatch 'winnerPartyAwards') { throw 'PostBattle must require both a positive renown delta and complete player reward telemetry for the P5 battle progression check.' }
if ($battleFixtureSource -notmatch 'IO\.File\]::Open\(\$script:VideoCaptureEventsPath' -or $battleFixtureSource -notmatch 'FileShare\]::ReadWrite' -or $battleFixtureSource -notmatch 'for \(\$attempt = 0; \$attempt -lt 6; \$attempt\+\+\)') { throw 'Battle event trace appends must tolerate transient readers/locks with bounded retry and shared access.' }
if ($developmentDoc -notmatch "Contract version:\s*$([regex]::Escape($contractVersion))") {
    throw "DEVELOPMENT.md is not synchronized with contract version $contractVersion."
}
foreach ($requiredText in @('DEVELOPMENT.md', 'DESIGN.md', 'SYSTEM_INVENTORY.md', 'TestResults/latest.json')) {
    if ($rootAgents -notmatch [regex]::Escape($requiredText)) {
        throw "Root AGENTS.md does not reference '$requiredText'."
    }
}
foreach ($forbiddenText in @('ChronicleFramework/README.md', 'ChronicleFramework/HARNESS.md', 'ChronicleFramework/TOOLCHAIN.md')) {
    if ($rootAgents -match [regex]::Escape($forbiddenText)) {
        throw "Root AGENTS.md still references removed document '$forbiddenText'."
    }
}
foreach ($requiredText in @('TestResults/latest.json', 'Computer Use', 'ContextState.json', 'Focus/MAINLINE.md', 'Original Mechanic Assumption Gate')) {
    if ($developmentDoc -notmatch [regex]::Escape($requiredText)) {
        throw "DEVELOPMENT.md is missing contract element '$requiredText'."
    }
}
foreach ($requiredScript in @('Agent-DecisionLoop.ps1', 'Agent-ProviderBudget.ps1', 'Agent-SaveMetadata.ps1', 'Test-AgentSaveMetadata.ps1', 'Test-AgentLoop.ps1', 'Test-AgentLoopProvider.ps1', 'Test-AgentOpenAICompatibleProvider.ps1', 'Get-FreeLLMAPIProfile.ps1', 'Test-AgentLiveModelLoop.ps1', 'Test-AgentCheckpointPersistence.ps1', 'Test-AgentLiveModelResume.ps1', 'Test-AgentVillageToolsProvider.ps1', 'Test-AgentVillageToolsDelivery.ps1', 'Test-AgentBattleFixture.ps1', 'Test-AgentVisualCapture.ps1', 'AgentMissionInputPatch.cs', 'Test-AgentTavernMission.ps1', 'Test-AgentTownCenterMission.ps1', 'Test-AgentMissionInteraction.ps1', 'AgentMissionInteraction.cs', 'Test-AgentCompanionHiring.ps1', 'AgentPartyRoleAdapter.cs', 'Test-AgentPartyRoles.ps1', 'AgentInventoryStateAdapter.cs', 'AgentTradeAdapter.cs', 'HarnessEquipmentModifierFixture.cs', 'Test-AgentInventoryNavigation.ps1', 'Test-AgentEquipmentTransactions.ps1', 'Test-AgentTradeTransactions.ps1', 'Test-AgentSettlementOverlayConversation.ps1', 'Test-AgentFreshCampaign.ps1', 'Test-AgentSupport.ps1', 'Test-AgentMoveToPoint.ps1', 'Test-AgentCharacterDevelopment.ps1', 'Test-AgentSpendSkillFocus.ps1', 'Test-AgentPartyRoster.ps1', 'AgentPartyScreenAdapter.cs', 'AgentPartyUpgradeAdapter.cs', 'Test-AgentPartyUpgrade.ps1', 'AgentPartyPrisonerRecruitmentAdapter.cs', 'Test-AgentPartyPrisonerRecruitment.ps1', 'Test-AgentJoinEncounterEligibility.ps1', 'Test-AgentJoinEncounterAbandonArmy.ps1', 'Test-AgentMovingArmyJoin.ps1', 'Test-AgentJoinSiegeEvent.ps1', 'HarnessSiegeJoinFixture.cs', 'HarnessVideoCapture.ps1', 'Prune-TestResults.ps1', 'Set-ContextFocus.ps1')) {
    if (-not (Test-Path (Join-Path $harnessRoot $requiredScript))) { throw "Agent loop harness script is missing: $requiredScript" }
}
if (-not (Test-Path (Join-Path $harnessRoot 'Test-AgentMapSettlementTargets.ps1'))) { throw 'MapSettlementTargets regression script is missing.' }
foreach ($barterPath in @('AgentBarterAdapter.cs', 'AgentBarterViewCapture.cs', 'Test-AgentBarterTransactions.ps1')) {
    if (-not (Test-Path (Join-Path $harnessRoot $barterPath))) { throw "Native Barter implementation/test file is missing: $barterPath" }
}
foreach ($barterContextPath in @('Test-AgentSafePassageBarterContext.ps1', 'HarnessSafePassageFixture.cs')) {
    if (-not (Test-Path (Join-Path $harnessRoot $barterContextPath))) { throw "Safe Passage context test/fixture file is missing: $barterContextPath" }
}
if (-not (Test-Path (Join-Path $harnessRoot 'Test-AgentMapPartyTargets.ps1'))) { throw 'MapPartyTargets regression script is missing.' }
if (-not (Test-Path (Join-Path $harnessRoot 'Test-AgentMapPartyComposition.ps1'))) { throw 'MapPartyComposition regression script is missing.' }
if (-not (Test-Path (Join-Path $harnessRoot 'HarnessMapPartyIssueMarkerFixture.cs')) -or -not (Test-Path (Join-Path $harnessRoot 'Test-AgentMapPartyQuestMarkers.ps1'))) { throw 'MapPartyQuestMarkers requires its Native Issue fixture and visual-capture regression script.' }
if (-not (Test-Path (Join-Path $harnessRoot 'Test-AgentMapPartyQuestAcceptance.ps1'))) { throw 'MapPartyQuestAcceptance requires its standalone map-party Issue-to-Quest regression script.' }
if (-not (Test-Path (Join-Path $harnessRoot 'Test-AgentMapEscapeMenu.ps1'))) { throw 'MapEscapeMenu requires its standalone Native overlay observe/close regression script.' }
if (-not (Test-Path (Join-Path $harnessRoot 'Test-AgentMapInquiry.ps1'))) { throw 'MapInquiry requires its standalone Native active-Inquiry observe/respond regression script.' }
if ($harnessScript -notmatch "'MapPartyQuestMarkers'\s*\{\s*@\('Preflight', 'Build', 'MapPartyQuestMarkers'\)" -or $harnessScript -notmatch "Invoke-Stage -Name 'MapPartyQuestMarkers'" -or $harnessScript -notmatch 'Test-AgentMapPartyQuestMarkers\.ps1') { throw 'MapPartyQuestMarkers must remain a separate opt-in Native observation phase with Preflight and Build.' }
$mapPartyQuestMarkerTest = Get-Content (Join-Path $harnessRoot 'Test-AgentMapPartyQuestMarkers.ps1') -Raw -Encoding UTF8
$mapPartyQuestMarkerFixture = Get-Content (Join-Path $harnessRoot 'HarnessMapPartyIssueMarkerFixture.cs') -Raw -Encoding UTF8
$mapPartyQuestAcceptanceTest = Get-Content (Join-Path $harnessRoot 'Test-AgentMapPartyQuestAcceptance.ps1') -Raw -Encoding UTF8
if ($mapPartyQuestMarkerTest -notmatch 'harnessSeedMapPartyIssueMarker' -or $mapPartyQuestMarkerTest -notmatch 'AvailableIssueMarkerExposed' -or $mapPartyQuestMarkerTest -notmatch 'NoMarkerPartyRemainsEmpty' -or $mapPartyQuestMarkerTest -notmatch 'ObservationRepeatStable' -or $mapPartyQuestMarkerTest -notmatch 'QuestTextNotLeaked' -or $mapPartyQuestMarkerTest -notmatch 'SourceFixtureUnchanged' -or $mapPartyQuestMarkerTest -notmatch 'ProcessStopped' -or $mapPartyQuestMarkerTest -notmatch 'EngineFrames') { throw 'MapPartyQuestMarkers must test a Native available Issue, a no-marker target, information scope, repeat stability, screenshots, fixture/hash, and process cleanup.' }
if ($mapPartyQuestMarkerFixture -notmatch 'issueManager\.CheckForIssues' -or $mapPartyQuestMarkerFixture -notmatch 'issueManager\.CreateNewIssue' -or $mapPartyQuestMarkerFixture -match 'leader\.Issue\s*=(?!=)' -or $agentObserverSource -notmatch 'GetMapPartyNameplateQuestMarkers' -or $agentObserverSource -notmatch 'hasAvailableIssueMarker' -or $agentObserverSource -notmatch 'IsSpotted\(\)' -or $agentObserverSource -notmatch 'CurrentSettlement != null' -or $agentCliSource -notmatch "'harnessSeedMapPartyIssueMarker'" -or $agentProtocolSource -notmatch 'case "harnessSeedMapPartyIssueMarker"') { throw 'Map Party Issue marker observation must use Native marker-state rules, distinguish ineligible targets, and keep Issue fixture creation Harness-only.' }
if ($harnessScript -notmatch "'MapPartyQuestAcceptance'\s*\{\s*@\('Preflight', 'Build', 'MapPartyQuestAcceptance'\)" -or $harnessScript -notmatch "Invoke-Stage -Name 'MapPartyQuestAcceptance'" -or $harnessScript -notmatch 'Test-AgentMapPartyQuestAcceptance\.ps1' -or $mapPartyQuestAcceptanceTest -notmatch 'harnessSeedMapPartyIssueMarker' -or $mapPartyQuestAcceptanceTest -notmatch 'pursue' -or $mapPartyQuestAcceptanceTest -notmatch 'hero_give_issue' -or $mapPartyQuestAcceptanceTest -notmatch 'issue_offer_player_accept_quest' -or $mapPartyQuestAcceptanceTest -notmatch 'QuestAcceptedFromMapParty' -or $mapPartyQuestAcceptanceTest -notmatch 'QuestMarkerAdvancedToActive' -or $mapPartyQuestAcceptanceTest -notmatch 'ActiveIssue' -or $mapPartyQuestAcceptanceTest -notmatch 'SourceFixtureUnchanged' -or $mapPartyQuestAcceptanceTest -notmatch 'ProcessStopped') { throw 'MapPartyQuestAcceptance must follow a current Native map Party marker through real map approach, conversation options, Quest start, marker transition, and fixture/process cleanup.' }
$mapEscapeMenuTest = Get-Content (Join-Path $harnessRoot 'Test-AgentMapEscapeMenu.ps1') -Raw -Encoding UTF8
if ($harnessScript -notmatch "'MapEscapeMenu'\s*\{\s*@\('Preflight', 'Build', 'MapEscapeMenu'\)" -or $harnessScript -notmatch "Invoke-Stage -Name 'MapEscapeMenu'" -or $harnessScript -notmatch 'Test-AgentMapEscapeMenu\.ps1' -or $agentObserverSource -notmatch 'escapeMenuOpen' -or $agentProtocolSource -notmatch 'case "closeEscapeMenu"' -or $agentProtocolSource -notmatch 'CloseEscapeMenu\(\)' -or $agentCliSource -notmatch "'closeEscapeMenu'" -or $agentDecisionLoopSource -notmatch 'closeEscapeMenu = @\(\)' -or $mapEscapeMenuTest -notmatch 'harnessOpenMapEscapeMenu' -or $mapEscapeMenuTest -notmatch 'ClosedMenuActionRejected' -or $mapEscapeMenuTest -notmatch 'PursueRejectedWithoutChangingMenu' -or $mapEscapeMenuTest -notmatch 'OverlayTransitionOnly' -or $mapEscapeMenuTest -notmatch 'SourceFixtureUnchanged' -or $mapEscapeMenuTest -notmatch 'EngineFrames') { throw 'Map Escape recovery must expose the Native map overlay, limit the close action to MapScreen, reject blocked pursuit, prove overlay-only postconditions, and retain screenshots/cleanup evidence.' }
$mapInquiryTest = Get-Content (Join-Path $harnessRoot 'Test-AgentMapInquiry.ps1') -Raw -Encoding UTF8
$alleyLeaderInquiryTest = Get-Content (Join-Path $harnessRoot 'Test-AgentAlleyLeaderInquiry.ps1') -Raw -Encoding UTF8
$inquiryAdapterSource = Get-Content (Join-Path $harnessRoot 'AgentInquiryAdapter.cs') -Raw -Encoding UTF8
if ($harnessScript -notmatch "'MapInquiry'\s*\{\s*@\('Preflight', 'Build', 'MapInquiry'\)" -or $harnessScript -notmatch "Invoke-Stage -Name 'MapInquiry'" -or $harnessScript -notmatch 'Test-AgentMapInquiry\.ps1' -or $agentObserverSource -notmatch 'inquiryOpen' -or $agentObserverSource -notmatch 'ChronicleInquiryAdapter.BuildMapInquiryJson' -or $agentProtocolSource -notmatch 'case "respondInquiry"' -or $agentProtocolSource -notmatch 'case "harnessOpenNativeInquiry"' -or $agentProtocolSource -notmatch 'ChronicleInquiryAdapter.Respond' -or $agentCliSource -notmatch "'respondInquiry'" -or $agentDecisionLoopSource -notmatch "respondInquiry = @\('InquiryToken','InquiryChoice'\)" -or $inquiryAdapterSource -notmatch '_activeQueryData' -or $inquiryAdapterSource -notmatch '_activeDataSource' -or $inquiryAdapterSource -notmatch 'IsAnyInquiryActive' -or $inquiryAdapterSource -notmatch 'ExecuteAffirmativeAction' -or $inquiryAdapterSource -notmatch 'ExecuteNegativeAction' -or $inquiryAdapterSource -notmatch 'pauseGameActiveState' -or $mapInquiryTest -notmatch 'harnessOpenNativeInquiry' -or $mapInquiryTest -notmatch 'StaleTokenRejectedBeforeAndAfter' -or $mapInquiryTest -notmatch 'MapActionRejectedWithoutClosingInquiry' -or $mapInquiryTest -notmatch 'EngineFrames' -or $mapInquiryTest -notmatch 'SourceFixtureUnchanged') { throw 'Map Inquiry support must read the active Native popup VM, call its affirmative/negative handlers with fresh tokens, reject blocked map actions, expose pause semantics, and test screenshots/cleanup.' }
if ($agentHostDecisionCycleSource -notmatch 'DecideNativeInquiryResponseAsync' -or $agentHostDecisionCycleSource -notmatch 'respondInquiry' -or $agentHostMailboxSource -notmatch 'RespondNativeInquiryAsync' -or $agentHostEstablishClanAutonomySource -notmatch 'replayedChildActions' -or $agentHostEstablishClanAutonomySource -notmatch 'establish-clan-autonomy-model-resolves-native-modal-after-prior-action-then-replans-from-fresh-state' -or $agentHostInquiryResolutionSource -notmatch 'YesNoInquiry' -or $agentHostInquiryResolutionSource -notmatch 'allowedChoices' -or $agentHostInquiryResolutionSource -notmatch 'BuildDecisionRequest' -or $agentHostInquiryResolutionSource -notmatch 'allowedActions' -or $agentHostInquiryResolutionSource -notmatch 'respondInquiry' -or $agentHostInquiryResolutionSource -notmatch 'inquiryOpen' -or $agentHostInquiryResolutionSource -notmatch 'native-inquiry-choice-not-currently-enabled' -or $agentHostProviderContractSelfTestSource -notmatch 'native-inquiry-uses-standard-action-control-envelope-through-provider' -or $agentHostHarnessProgressTraceSource -notmatch 'BuildInquirySummary' -or $agentHostHarnessProgressTraceSource -notmatch 'harness-progress-trace-records-current-modal-and-visible-buttons-without-one-use-token') { throw 'The EYC Host must let the model choose only a currently visible/enabled supported Native Map inquiry response through the standard provider decision envelope, verify the modal transition, then obtain a fresh parent decision without replaying a failed child, and preserve a token-free modal state trace.' }
if ($agentProtocolSource -notmatch 'case "harnessOpenRecruitmentInquiry"' -or $agentProtocolSource -notmatch 'BeginHarnessNativeCapacityInquiry' -or $agentCliSource -notmatch "'harnessOpenRecruitmentInquiry'" -or $mapInquiryTest -notmatch 'NativeRecruitmentInquiry' -or $mapInquiryTest -notmatch 'declineNoMutation' -or $mapInquiryTest -notmatch 'nativeCapacityCommit' -or $mapInquiryTest -notmatch 'nativeInquiryTimeStable') { throw 'MapInquiry must exercise a real Native RecruitmentVM capacity confirmation in addition to the generic Native UI fixture, and verify clock stability.' }
if (-not (Test-Path (Join-Path $harnessRoot 'Test-AgentAlleyLeaderInquiry.ps1')) -or $harnessScript -notmatch "'AlleyLeaderInquiry'\s*\{\s*@\('Preflight', 'Build', 'AlleyLeaderInquiry'\)" -or $harnessScript -notmatch "Invoke-Stage -Name 'AlleyLeaderInquiry'" -or $harnessScript -notmatch 'Test-AgentAlleyLeaderInquiry\.ps1' -or $inquiryAdapterSource -notmatch 'RespondAlleyMultiSelection' -or $inquiryAdapterSource -notmatch 'BuildAlleyMultiSelectionJson' -or $inquiryAdapterSource -notmatch 'ChangeAssignedClanMemberOfAlley' -or $inquiryAdapterSource -notmatch 'MultiSelectionQueryPopUpVM' -or $agentProtocolSource -notmatch 'case "respondMultiSelectionInquiry"' -or $agentDecisionLoopSource -notmatch "respondMultiSelectionInquiry = @\('InquiryToken','InquiryChoice','SelectedIds'\)" -or $agentProtocolSource -notmatch 'harnessPrepareAlleyLeaderFixture' -or $agentProtocolSource -notmatch 'harnessAlleyLeaderDiagnostics' -or $alleyLeaderInquiryTest -notmatch 'change_leader_of_alley' -or $alleyLeaderInquiryTest -notmatch 'pauseGameActiveState' -or $alleyLeaderInquiryTest -notmatch 'cancelNoMutation' -or $alleyLeaderInquiryTest -notmatch 'positiveCommitted' -or $alleyLeaderInquiryTest -notmatch 'SourceFixtureUnchanged') { throw 'Alley MultiSelection must be gated to its active Native VM/Town action, preserve pause/selection semantics, and test positive/negative callbacks and cleanup.' }
$alleyLeaderFixture = Get-Content (Join-Path $harnessRoot 'HarnessAlleyLeaderFixture.cs') -Raw -Encoding UTF8
if ($alleyLeaderFixture -notmatch 'AddPlayerAlleyCharacters' -or $alleyLeaderFixture -notmatch 'GetLocationCharacterOfHero\(initialAssignedHero\)' -or $alleyLeaderInquiryTest -notmatch 'NativeWorldStableAcrossConfirmation' -or $alleyLeaderInquiryTest -notmatch 'NativeLeaderAndRosterChanged' -or $alleyLeaderInquiryTest -notmatch "Get-Process -Name 'Bannerlord\*'") { throw 'Alley leader integration must construct the Native LocationCharacter expected by the callback, assert gameplay/economy/clock postconditions, and detect the actual Bannerlord process family.' }
$alleyRosterTest = Get-Content (Join-Path $harnessRoot 'Test-AgentAlleyRosterManagement.ps1') -Raw -Encoding UTF8
$alleyRosterAdapter = Get-Content (Join-Path $harnessRoot 'AgentAlleyRosterAdapter.cs') -Raw -Encoding UTF8
$alleyRosterFixture = Get-Content (Join-Path $harnessRoot 'HarnessAlleyRosterFixture.cs') -Raw -Encoding UTF8
if (-not (Test-Path (Join-Path $harnessRoot 'Test-AgentAlleyRosterManagement.ps1')) -or $harnessScript -notmatch "'AlleyRosterManagement'\s*\{\s*@\('Preflight', 'Build', 'AlleyRosterManagement'\)" -or $harnessScript -notmatch "Invoke-Stage -Name 'AlleyRosterManagement'" -or $harnessScript -notmatch 'Test-AgentAlleyRosterManagement\.ps1' -or $agentProtocolSource -notmatch 'case "alleyRosterTransfer"' -or $agentProtocolSource -notmatch 'case "alleyRosterCancel"' -or $agentProtocolSource -notmatch 'ChronicleAlleyRosterAdapter.Done' -or $agentObserverSource -notmatch 'minimumTroops' -or $agentObserverSource -notmatch 'MaximumTroopCountInPlayerOwnedAlley' -or $alleyRosterAdapter -notmatch 'PartyCharacterVM\.ExecuteTransferSingle' -or $alleyRosterAdapter -notmatch 'viewModel\.ExecuteDone\(\)' -or $alleyRosterAdapter -notmatch 'viewModel\.ExecuteCancelWithoutInquiry\(\)' -or $alleyRosterAdapter -match 'AddToCounts\(' -or $alleyRosterFixture -notmatch 'manage_alley_troops' -or $alleyRosterTest -notmatch 'CancelNoMutation' -or $alleyRosterTest -notmatch 'MinimumBoundary' -or $alleyRosterTest -notmatch 'MaximumBoundary' -or $alleyRosterTest -notmatch 'NativeClockStable' -or $alleyRosterTest -notmatch 'SourceFixtureUnchanged' -or $alleyRosterTest -notmatch "Get-Process -Name 'Bannerlord\*'") { throw 'Alley roster work must use the real Native PartyScreen, enforce visible eligibility and both AlleyModel boundaries, verify cancel/commit/clock/save/cleanup, and retain a standalone Harness phase.' }
$alleyAbandonmentTest = Get-Content (Join-Path $harnessRoot 'Test-AgentAlleyAbandonment.ps1') -Raw -Encoding UTF8
if (-not (Test-Path (Join-Path $harnessRoot 'Test-AgentAlleyAbandonment.ps1')) -or $harnessScript -notmatch "'AlleyAbandonment'\s*\{\s*@\('Preflight', 'Build', 'AlleyAbandonment'\)" -or $harnessScript -notmatch "Invoke-Stage -Name 'AlleyAbandonment'" -or $harnessScript -notmatch 'Test-AgentAlleyAbandonment\.ps1' -or $alleyAbandonmentTest -notmatch 'manage_alley_abandon_are_you_sure' -or $alleyAbandonmentTest -notmatch 'abandon_alley_no' -or $alleyAbandonmentTest -notmatch 'abandon_alley_yes' -or $alleyAbandonmentTest -notmatch 'playerAlleyDataPresent' -or $alleyAbandonmentTest -notmatch 'SourceFixtureHashBefore' -or $alleyAbandonmentTest -notmatch 'ConfirmBranch' -or $alleyAbandonmentTest -notmatch 'CancelBranch') { throw 'Alley abandonment must use the Native Town confirmation branches in isolated disposable runs, verify reversible/irreversible postconditions, and preserve source fixture evidence.' }
$alleyEntryMenuTest = Get-Content (Join-Path $harnessRoot 'Test-AgentAlleyEntryMenu.ps1') -Raw -Encoding UTF8
if (-not (Test-Path (Join-Path $harnessRoot 'Test-AgentAlleyEntryMenu.ps1')) -or $harnessScript -notmatch "'AlleyEntryMenu'\s*\{\s*@\('Preflight', 'Build', 'AlleyEntryMenu'\)" -or $harnessScript -notmatch "Invoke-Stage -Name 'AlleyEntryMenu'" -or $harnessScript -notmatch 'Test-AgentAlleyEntryMenu\.ps1' -or $agentProtocolSource -notmatch 'case "menuSelect"' -or $alleyEntryMenuTest -notmatch 'manage_alley' -or $alleyEntryMenuTest -notmatch 'BusinessStateUnchanged' -or $alleyEntryMenuTest -notmatch 'ClockStable' -or $alleyEntryMenuTest -notmatch 'SourceFixtureUnchanged') { throw 'Native Alley entry coverage must exercise the Town GameMenu option and Alley back option through the current menu observer/selection path, retaining state and screenshot evidence.' }
$alleyLeaderSceneEntryTest = Get-Content (Join-Path $harnessRoot 'Test-AgentAlleyLeaderSceneEntry.ps1') -Raw -Encoding UTF8
if (-not (Test-Path (Join-Path $harnessRoot 'Test-AgentAlleyLeaderSceneEntry.ps1')) -or $harnessScript -notmatch "'MissionSceneNavigation'\s*\{\s*@\('Preflight', 'Build', 'MissionSceneNavigation'\)" -or $harnessScript -notmatch "Invoke-Stage -Name 'MissionSceneNavigation'" -or $harnessScript -notmatch 'Test-AgentAlleyLeaderSceneEntry\.ps1' -or $alleyLeaderSceneEntryTest -notmatch 'town_streets' -or $alleyLeaderSceneEntryTest -notmatch 'assignedHeroId' -or $alleyLeaderSceneEntryTest -notmatch 'missionSceneAgents' -or $alleyLeaderSceneEntryTest -notmatch 'missionNavigateToAgent' -or $alleyLeaderSceneEntryTest -notmatch 'missionInteract' -or $alleyLeaderSceneEntryTest -notmatch 'conversationPathSucceeded' -or $alleyLeaderSceneEntryTest -notmatch 'SourceFixtureUnchanged') { throw 'Mission scene navigation coverage must query the current Mission actor set, use native bounded NavMesh leases and start only the target Native conversation without choosing dialogue options.' }
if ($agentProtocolSource -notmatch 'activeHeroAgents' -or $alleyLeaderSceneEntryTest -notmatch 'harnessMissionDiagnostics' -or $alleyLeaderSceneEntryTest -notmatch 'AssignedLeaderInMissionScene' -or $agentDecisionLoopSource -match 'harnessMissionDiagnostics') { throw 'Harness-only Alley diagnostics may verify NPC generation but must never provide navigation target data to the Agent loop.' }
$alleyRosterFixtureSource = Get-Content (Join-Path $harnessRoot 'HarnessAlleyRosterFixture.cs') -Raw -Encoding UTF8
if ($harnessScript -notmatch "'AlleyVolunteerBranches'\s*\{\s*@\('Preflight', 'Build', 'AlleyVolunteerBranches'\)" -or $harnessScript -notmatch "Invoke-Stage -Name 'AlleyVolunteerBranches'" -or $alleyLeaderSceneEntryTest -notmatch 'VolunteerScenario' -or $alleyLeaderSceneEntryTest -notmatch 'noVolunteers' -or $alleyLeaderSceneEntryTest -notmatch 'availableVolunteers' -or $alleyLeaderSceneEntryTest -notmatch 'alley_talk_start_player_owned_alley_manager_volunteers_3' -or $alleyLeaderSceneEntryTest -notmatch 'alley_talk_start_player_owned_alley_manager_volunteers_5' -or $alleyLeaderSceneEntryTest -notmatch 'lastRecruitTimeUpdated' -or $alleyLeaderSceneEntryTest -notmatch 'OverCapacityWithoutInquiry' -or $alleyRosterFixtureSource -notmatch 'MBRandom.RandomFloatWithSeed' -or $alleyRosterFixtureSource -notmatch 'LastRecruitTime' -or $agentDecisionLoopSource -match 'harnessAlleyRosterDiagnostics|weeklyRandomForFixture') { throw 'Alley branch tests must use isolated Harness-only Native random fixtures, observe current dialogue options, verify roster/timer/capacity results, and keep hidden setup values out of product Agent decisions.' }
$alleyAttackYieldTest = Get-Content (Join-Path $harnessRoot 'Test-AgentAlleyAttackYield.ps1') -Raw -Encoding UTF8
if ($agentProtocolSource -notmatch 'harnessSeedAlleyAttackFixture is restricted to a visual Harness run' -or $alleyRosterFixtureSource -notmatch 'attackingAlley' -or $alleyRosterFixtureSource -notmatch 'AttackResponseDueDate' -or $alleyAttackYieldTest -notmatch 'noAttack' -or $alleyAttackYieldTest -notmatch 'peacefulYield' -or $agentDecisionLoopSource -match 'harnessSeedAlleyAttackFixture') { throw 'Attacked-Alley test conditions and enemy state must remain Harness-only; the product test must exercise both real no-attack and current peaceful-yield branches.' }
if ($harnessScript -notmatch "'AlleyAttackYield'\s*\{\s*@\('Preflight', 'Build', 'AlleyAttackYield'\)" -or $harnessScript -notmatch "Invoke-Stage -Name 'AlleyAttackYield'" -or $agentCliSource -notmatch "'harnessSeedAlleyAttackFixture'" -or $agentProtocolSource -notmatch 'case "harnessSeedAlleyAttackFixture"' -or $alleyRosterFixtureSource -notmatch 'SeedAlleyAttack' -or $alleyAttackYieldTest -notmatch 'confront_hostile_alley_leader' -or $alleyAttackYieldTest -notmatch 'alley_talk_start_normal_4' -or $alleyAttackYieldTest -notmatch 'PlayerAlleyDataRemovedAndOwnerTransferred' -or $alleyAttackYieldTest -notmatch 'SourceFixtureUnchanged' -or $agentDecisionLoopSource -match 'harnessSeedAlleyAttackFixture') { throw 'Alley attack peace-path tests must prepare a temporary Native under-attack context, use the current menu/dialogue branch, verify owner/roster/relationship effects, and keep attack seeding out of product decisions.' }
$alleyAttackFightTest = Get-Content (Join-Path $harnessRoot 'Test-AgentAlleyAttackFightMission.ps1') -Raw -Encoding UTF8
if (-not (Test-Path (Join-Path $harnessRoot 'Test-AgentAlleyAttackFightMission.ps1')) -or $harnessScript -notmatch "'AlleyAttackFightMission'\s*\{\s*@\('Preflight', 'Build', 'AlleyAttackFightMission'\)" -or $harnessScript -notmatch "Invoke-Stage -Name 'AlleyAttackFightMission'" -or $alleyAttackFightTest -notmatch 'alley_talk_start_normal_3' -or $alleyAttackFightTest -notmatch 'Wait-ForMissionState' -or $alleyAttackFightTest -notmatch 'activeAgentCount' -or $alleyAttackFightTest -notmatch 'mainAgent.isPlayerControlled' -or $alleyAttackFightTest -notmatch 'missionRetreat' -or $alleyAttackFightTest -notmatch 'MissionEntryVerified' -or $alleyAttackFightTest -notmatch 'AlleyLostAfterRetreat' -or $alleyAttackFightTest -notmatch 'SourceFixtureUnchanged' -or $alleyRosterFixtureSource -notmatch 'mainHeroHitPoints') { throw 'Alley Fight Mission validation must wait through Native Mission startup until the controlled MainAgent is live, use its Native retreat path, verify the actual loss result and player health, and preserve fixture/process cleanup.' }
if ($agentObserverSource -notmatch 'activeGameState is MapState || activeGameState is MissionState' -or $inquiryAdapterSource -notmatch 'activeState is not MissionState' -or $agentProtocolSource -notmatch 'missionToRetreat.OnEndMissionRequest\(\)' -or $agentProtocolSource -match 'missionToRetreat.RetreatMission\(\)' -or $alleyAttackFightTest -notmatch 'respondInquiry' -or $alleyAttackFightTest -notmatch 'MissionExitInquiryVisible' -or $alleyAttackFightTest -notmatch 'NativeCancelPreservedMission') { throw 'Combat Mission exit must surface a current Native Inquiry, support its callback only after explicit Agent choice, and never bypass confirmation with direct Mission.RetreatMission.' }
if ($agentProtocolSource -notmatch 'RunMenuOptionConsequence\(menuContext, optionIndex\)') { throw 'menuSelect must continue through the current Native GameMenuOption consequence rather than a Harness-only Alley shortcut.' }
$persuasionAdapterSource = Get-Content (Join-Path $harnessRoot 'AgentPersuasionAdapter.cs') -Raw -Encoding UTF8
$persuasionFixtureSource = Get-Content (Join-Path $harnessRoot 'HarnessPersuasionFixture.cs') -Raw -Encoding UTF8
$persuasionDetailsTest = Get-Content (Join-Path $harnessRoot 'Test-AgentPersuasionDetails.ps1') -Raw -Encoding UTF8
if (-not (Test-Path (Join-Path $harnessRoot 'AgentPersuasionAdapter.cs')) -or -not (Test-Path (Join-Path $harnessRoot 'HarnessPersuasionFixture.cs')) -or -not (Test-Path (Join-Path $harnessRoot 'Test-AgentPersuasionDetails.ps1')) -or $harnessScript -notmatch "'PersuasionDetails'\s*\{\s*@\('Preflight', 'Build', 'PersuasionDetails'\)" -or $harnessScript -notmatch "Invoke-Stage -Name 'PersuasionDetails'" -or $agentCliSource -notmatch "'persuasionDetails'" -or $agentCliSource -notmatch "'harnessCurrentConversationAnswers'" -or $agentProtocolSource -notmatch 'case "persuasionDetails"' -or $agentProtocolSource -notmatch 'ChroniclePersuasionAdapter.ReadCurrentPersuasion' -or $agentProtocolSource -notmatch 'ChroniclePersuasionAdapter.IsVisiblePersuasionOption' -or $agentProtocolSource -notmatch 'case "harnessCurrentConversationAnswers"' -or $agentProtocolSource -notmatch 'ReadCurrentNativeAnswerList' -or $agentDecisionLoopSource -notmatch "\['persuasionDetails'\]\s*=\s*@\(\)" -or $persuasionAdapterSource -notmatch 'MapConversationVM' -or $persuasionAdapterSource -notmatch 'AnswerList' -or $persuasionAdapterSource -notmatch 'PersuasionItem' -or $persuasionAdapterSource -notmatch 'SuccessChance' -or $persuasionAdapterSource -match 'StartPersuasion|CommitProgress|DoOption\(' -or $persuasionFixtureSource -notmatch 'visual-capture' -or $persuasionFixtureSource -notmatch 'currently rendered, enabled Native AnswerList' -or $persuasionDetailsTest -notmatch 'VisibleCurrentPersuasionOptionAccepted' -or $persuasionDetailsTest -notmatch 'harnessCurrentConversationAnswers' -or $persuasionDetailsTest -notmatch 'answerCount' -or $persuasionDetailsTest -notmatch 'FixtureUnchanged' -or $persuasionDetailsTest -notmatch 'ProcessStopped') { throw 'PersuasionDetails must wait for the Native answer list, bind Persuasion data only to its visible options, submit through dialogueSelect, and prove fixture/process safety.' }
if ($subModuleSource -notmatch 'TryInstallHarnessFocusLossEscapeMenuGuard' -or $subModuleSource -notmatch 'IsOpeningEscapeMenuOnFocusChangeAllowedForAll' -or $subModuleSource -notmatch 'IsHarnessFocusLossEscapeMenuGuardMode' -or $subModuleSource -notmatch 'mode == "agent-host-lifecycle-test"' -or $subModuleSource -notmatch 'CHRONICLE_HARNESS_AGENT_INPUT_FOCUS_TEST' -or $subModuleSource -notmatch 'mode == "fresh-campaign-renown"' -or $subModuleSource -notmatch 'visual-capture' -or $subModuleSource -notmatch 'KeepNativeEscapeMenuClosedWhenHarnessLosesFocus' -or $agentProtocolSource -notmatch 'MapScreen.Instance\?\.IsEscapeMenuOpened == true' -or $agentProtocolSource -notmatch 'mapStateForPursuit.AtMenu' -or $agentProtocolSource -notmatch 'harnessFocusLossEscapeMenuGuardInstalled' -or $mapPartyQuestAcceptanceTest -notmatch 'harnessMapDiagnostics' -or $mapPartyQuestAcceptanceTest -notmatch 'mapStateAtMenu' -or $mapPartyQuestAcceptanceTest -notmatch 'escapeMenuOpen' -or $mapPartyQuestAcceptanceTest -notmatch 'harnessFocusLossEscapeMenuGuardInstalled') { throw 'Background visual, lifecycle, and fresh-campaign Harness runs must suppress only automatic focus-loss Escape overlays, while the dedicated input-ownership probe bypasses that Harness guard to test the product guard; map actions continue to reject a genuinely open Escape menu.' }
$mainHeroSkillsTest = Get-Content (Join-Path $harnessRoot 'Test-AgentMainHeroSkills.ps1') -Raw -Encoding UTF8
if ($mainHeroSkillsTest -notmatch 'mainHeroSkills' -or $mainHeroSkillsTest -notmatch 'harnessPlayerSkillsDiagnostics' -or $mainHeroSkillsTest -notmatch 'LevelsMatchNative' -or $mainHeroSkillsTest -notmatch 'SnapshotUnchanged' -or $mainHeroSkillsTest -notmatch 'FixtureUnchanged' -or $mainHeroSkillsTest -notmatch 'ProcessStopped') { throw 'MainHeroSkills must compare the read-only state snapshot to native Hero.GetSkillValue values and prove state/fixture/process safety.' }
$characterDevelopmentTest = Get-Content (Join-Path $harnessRoot 'Test-AgentCharacterDevelopment.ps1') -Raw -Encoding UTF8
if ($characterDevelopmentTest -notmatch 'harnessCharacterDevelopmentDiagnostics' -or $characterDevelopmentTest -notmatch 'SkillProgressFocusRateAndPerksMatchNativeVM' -or $characterDevelopmentTest -notmatch 'AttributeValuesMatchNativeVM' -or $characterDevelopmentTest -notmatch 'StableAcrossRepeatedReads' -or $characterDevelopmentTest -notmatch 'FixtureUnchanged' -or $characterDevelopmentTest -notmatch 'ProcessStopped') { throw 'CharacterDevelopment must compare its read-only data to the native Character Developer VM and prove stability, fixture safety, and process cleanup.' }
$spendSkillFocusTest = Get-Content (Join-Path $harnessRoot 'Test-AgentSpendSkillFocus.ps1') -Raw -Encoding UTF8
if ($spendSkillFocusTest -notmatch 'spendSkillFocus' -or $spendSkillFocusTest -notmatch 'SuccessfulSinglePointSpend' -or $spendSkillFocusTest -notmatch 'OverBudgetRequestRejectedAtomically' -or $spendSkillFocusTest -notmatch 'OverCapRequestRejectedAtomically' -or $spendSkillFocusTest -notmatch 'QuestListUnchanged' -or $spendSkillFocusTest -notmatch 'SkillLevelsUnchanged' -or $spendSkillFocusTest -notmatch 'FixtureUnchanged' -or $spendSkillFocusTest -notmatch 'ProcessStopped') { throw 'SpendSkillFocus must verify a committed Focus point, atomic rejection without Quest/skill effects, save preservation, and process cleanup.' }
$questDetailsTest = Get-Content (Join-Path $harnessRoot 'Test-AgentSettlementOverlayConversation.ps1') -Raw -Encoding UTF8
if ($questDetailsTest -notmatch 'ValidateQuestDetails' -or $questDetailsTest -notmatch 'questDetails' -or $questDetailsTest -notmatch 'harnessQuestDetailsDiagnostics' -or $questDetailsTest -notmatch 'harnessQuestDeadlinePrivacyDiagnostics' -or $questDetailsTest -notmatch 'QuestDetailsValidated' -or $questDetailsTest -notmatch 'dueVisibilityMatches' -or $questDetailsTest -notmatch 'deadlinePrivacyGateCorrect' -or $questDetailsTest -notmatch 'unobservedQuestRejected' -or $questDetailsTest -notmatch 'journalReadOnly') { throw 'QuestJournal phase must verify a newly accepted Quest against the native QuestItemVM, deadline privacy branches, unobserved-ID rejection, and unchanged state.' }
$partyRosterTest = Get-Content (Join-Path $harnessRoot 'Test-AgentPartyRoster.ps1') -Raw -Encoding UTF8
if ($partyRosterTest -notmatch 'partyRoster' -or $partyRosterTest -notmatch 'harnessPartyRosterDiagnostics' -or $partyRosterTest -notmatch 'MemberRowsMatchNativeRoster' -or $partyRosterTest -notmatch 'PrisonerRowsMatchNativeRoster' -or $partyRosterTest -notmatch 'SnapshotUnchanged' -or $partyRosterTest -notmatch 'FixtureUnchanged' -or $partyRosterTest -notmatch 'ProcessStopped') { throw 'PartyRoster must compare both native MainParty rosters and prove read-only state, fixture and process safety.' }
$mapPartyTargetsTest = Get-Content (Join-Path $harnessRoot 'Test-AgentMapPartyTargets.ps1') -Raw -Encoding UTF8
if ($mapPartyTargetsTest -notmatch 'mapPartyTargets' -or $mapPartyTargetsTest -notmatch 'harnessMapPartyDiagnostics' -or $mapPartyTargetsTest -notmatch 'TargetSetMatchesNativeVisibleMarkerCandidates' -or $mapPartyTargetsTest -notmatch 'TargetFieldsMatchNativeNameplateData' -or $mapPartyTargetsTest -notmatch 'SnapshotUnchanged' -or $mapPartyTargetsTest -notmatch 'FixtureUnchanged' -or $mapPartyTargetsTest -notmatch 'ProcessStopped') { throw 'MapPartyTargets must compare visible map targets and nameplate facts with native diagnostics and prove read-only state, fixture and process safety.' }
if ($agentObserverSource -notmatch 'BuildMapPartyTargetsJson\(\)(?<mapPartyTargetsBody>[\s\S]*?)BuildMapPartyCompositionJson' -or $Matches.mapPartyTargetsBody -match 'IsInfoHidden' -or $agentProtocolSource -notmatch 'harnessMapPartyDiagnostics is restricted to a visual Harness run') { throw 'IsInfoHidden must not filter the vanilla map target census; detailed native diagnostics remain Harness-only.' }
$mapPartyCompositionTest = Get-Content (Join-Path $harnessRoot 'Test-AgentMapPartyComposition.ps1') -Raw -Encoding UTF8
if ($mapPartyCompositionTest -notmatch 'mapPartyComposition' -or $mapPartyCompositionTest -notmatch 'harnessMapPartyCompositionDiagnostics' -or $mapPartyCompositionTest -notmatch 'MemberRowsMatchNativeRoster' -or $mapPartyCompositionTest -notmatch 'NativeExtendedTooltipDisplaysMemberNames' -or $mapPartyCompositionTest -notmatch 'NonTargetPartyRejected' -or $mapPartyCompositionTest -notmatch 'SnapshotUnchanged' -or $mapPartyCompositionTest -notmatch 'FixtureUnchanged' -or $mapPartyCompositionTest -notmatch 'ProcessStopped') { throw 'MapPartyComposition must compare the on-demand roster to native roster and expanded tooltip evidence, reject non-target IDs and prove read-only state, fixture and process safety.' }
if ($agentObserverSource -notmatch 'BuildMapPartyCompositionJson' -or $agentObserverSource -notmatch 'MergeArmyRoster\(target, prisoners: false\)' -or $agentProtocolSource -notmatch 'harnessMapPartyCompositionDiagnostics is restricted to a visual Harness run' -or $agentCliSource -notmatch "'mapPartyComposition'") { throw 'MapPartyComposition must be read-only and explicitly callable by the Agent, while matching native Army leader-plus-attached roster aggregation; diagnostics remain Harness-only.' }
if (-not (Test-Path -LiteralPath (Join-Path $harnessRoot 'Test-AgentMapPartyBehavior.ps1'))) { throw 'MapPartyBehavior regression script is missing.' }
$mapPartyBehaviorTest = Get-Content (Join-Path $harnessRoot 'Test-AgentMapPartyBehavior.ps1') -Raw -Encoding UTF8
if ($mapPartyBehaviorTest -notmatch 'mapPartyBehavior' -or $mapPartyBehaviorTest -notmatch 'harnessMapPartyCompositionDiagnostics' -or $mapPartyBehaviorTest -notmatch 'OrdinaryBehaviorTextMatchesNativeTooltip' -or $mapPartyBehaviorTest -notmatch 'ArmyBehaviorTextMatchesNativeTooltipWhenRequested' -or $mapPartyBehaviorTest -notmatch 'InvalidPartyRejected' -or $mapPartyBehaviorTest -notmatch 'SnapshotUnchanged' -or $mapPartyBehaviorTest -notmatch 'FixtureUnchanged' -or $mapPartyBehaviorTest -notmatch 'ProcessStopped') { throw 'MapPartyBehavior must compare exact native tooltip summary strings for ordinary and Army targets and prove scope/read-only/fixture/process safety.' }
if ($harnessScript -notmatch 'mapPartyBehaviorScript -ValidateArmyTooltip' -or $mapPartyBehaviorTest -notmatch 'ArmyBehaviorTextMatchesNativeTooltipWhenRequested') { throw 'MapPartyBehavior must compare both ordinary MobileParty and native Army tooltip text when the Harness fixture can create an Army.' }
if ($agentObserverSource -notmatch 'BuildMapPartyBehaviorJson' -or $agentProtocolSource -notmatch 'case "mapPartyBehavior"' -or $agentCliSource -notmatch "'mapPartyBehavior'" -or $agentDecisionLoopSource -notmatch "mapPartyBehavior = @\('PartyId'\)") { throw 'MapPartyBehavior must be an explicit, read-only Agent observation bound to a current PartyId.' }
if ($agentProtocolSource -notmatch 'harnessCreateMapArmyFixture is restricted to a visual Harness run' -or $agentDecisionLoopSource -match 'harnessCreateMapArmyFixture|harnessMapPartyCompositionDiagnostics') { throw 'Army fixture creation and native tooltip diagnostics must stay outside the Agent action allowlist and be restricted to Harness mode.' }
$partyUpgradeTest = Get-Content (Join-Path $harnessRoot 'Test-AgentPartyUpgrade.ps1') -Raw -Encoding UTF8
$partyUpgradeAdapter = Get-Content (Join-Path $harnessRoot 'AgentPartyUpgradeAdapter.cs') -Raw -Encoding UTF8
if ($partyUpgradeTest -notmatch 'partyUpgradeOptions' -or $partyUpgradeTest -notmatch 'upgradeTroop' -or $partyUpgradeTest -notmatch 'HarnessSeedMatchesNativePartyVMOptions' -or $partyUpgradeTest -notmatch 'NativePartyScreenTransactionUpgradesOneUnit' -or $partyUpgradeTest -notmatch 'InvalidUpgradeRejectedWithoutMutation' -or $partyUpgradeTest -notmatch 'InsufficientExperienceRejectedWithoutMutation' -or $partyUpgradeTest -notmatch 'ActiveTimeModeSurvivesPartyScreenOpenClose' -or $partyUpgradeTest -notmatch 'FixtureUnchanged' -or $partyUpgradeTest -notmatch 'ProcessStopped' -or $partyUpgradeAdapter -notmatch 'ChroniclePartyScreenAdapter\.OpenMainPartyNormal' -or $partyUpgradeAdapter -notmatch 'ExecuteUpgrade' -or $partyUpgradeAdapter -notmatch 'ExecuteDone' -or $partyUpgradeAdapter -notmatch 'ChroniclePartyScreenAdapter\.CancelAndFinalize' -or $partyUpgradeAdapter -notmatch 'IsDoneActive' -or $agentProtocolSource -notmatch 'harnessSeedPartyUpgradeFixture is restricted to a visual Harness run' -or $agentDecisionLoopSource -match 'harnessSeedPartyUpgradeFixture') { throw 'PartyUpgrade must use the original PartyScreen VM transaction, clean up VM lifecycle hooks, keep fixture seeding Harness-only, test success/rejection/time, and clean the disposable fixture.' }
$partyScreenAdapter = Get-Content (Join-Path $harnessRoot 'AgentPartyScreenAdapter.cs') -Raw -Encoding UTF8
if ($partyScreenAdapter -notmatch 'PartyScreenHelper\.OpenScreenAsNormal' -or $partyScreenAdapter -notmatch 'new PartyVM\(partyState.PartyScreenLogic\)' -or $partyScreenAdapter -notmatch 'PrepareFinalization' -or $partyScreenAdapter -notmatch 'viewModel\?\.OnFinalize\(\)' -or $partyScreenAdapter -notmatch 'SetCancelInputKey' -or $partyScreenAdapter -notmatch 'SetDismissAllPrisonersInputKey' -or $partyScreenAdapter -notmatch 'ExecuteDoneAndConfirmNativeOverLimit' -or $partyScreenAdapter -notmatch 'InformationManager\.HideInquiry\(\)') { throw 'Shared PartyScreen adapter must open Normal MainParty state, safely finalize detached VM hooks, and support exact native Done confirmation callbacks.' }
$partyPrisonerTest = Get-Content (Join-Path $harnessRoot 'Test-AgentPartyPrisonerRecruitment.ps1') -Raw -Encoding UTF8
$partyPrisonerAdapter = Get-Content (Join-Path $harnessRoot 'AgentPartyPrisonerRecruitmentAdapter.cs') -Raw -Encoding UTF8
if ($partyPrisonerTest -notmatch 'prisonerRecruitmentOptions' -or $partyPrisonerTest -notmatch 'recruitPrisoner' -or $partyPrisonerTest -notmatch 'NativePartyVMRecruitsExactlyOneAtCapacity' -or $partyPrisonerTest -notmatch 'InsufficientConformityRejectedWithoutMutation' -or $partyPrisonerTest -notmatch 'NativeOverLimitWarningRequiresExplicitConfirmation' -or $partyPrisonerTest -notmatch 'RecruitableCountAndMoraleMatchNativeModel' -or $partyPrisonerTest -notmatch 'FixtureUnchanged' -or $partyPrisonerTest -notmatch 'ProcessStopped' -or $partyPrisonerAdapter -notmatch 'MainPartyPrisoners' -or $partyPrisonerAdapter -notmatch 'ExecuteRecruitTroop' -or $partyPrisonerAdapter -notmatch 'ExecuteDoneAndConfirmNativeOverLimit' -or $partyPrisonerAdapter -notmatch 'GetTroopRecruitableAmount' -or $partyPrisonerAdapter -notmatch 'RecentEventsMorale' -or $agentProtocolSource -notmatch 'harnessSeedPrisonerRecruitmentFixture is restricted to a visual Harness run' -or $agentDecisionLoopSource -match 'harnessSeedPrisonerRecruitmentFixture') { throw 'Party prisoner recruitment must use native PartyVM/Done, require explicit over-limit confirmation, test one recruit at capacity and insufficient conformity, verify morale/costs, and keep fixture seeding Harness-only.' }
if ($agentProtocolSource -notmatch 'case "prisonerRecruitmentOptions"' -or $agentProtocolSource -notmatch 'case "recruitPrisoner"' -or $agentCliSource -notmatch "'prisonerRecruitmentOptions'" -or $agentCliSource -notmatch "'recruitPrisoner'" -or $agentDecisionLoopSource -notmatch "prisonerRecruitmentOptions = @\(\)" -or $agentDecisionLoopSource -notmatch "recruitPrisoner = @\('TroopId','ConfirmPartySizeWarning'\)") { throw 'Party prisoner recruitment query/action must be explicitly exposed through protocol, CLI, and decision allowlist, with the native capacity confirmation flag.' }
if ($agentProtocolSource -notmatch 'case "recruitOptions"' -or $agentProtocolSource -notmatch 'case "recruit"' -or $agentProtocolSource -notmatch 'confirmPartySizeWarning' -or $agentProtocolSource -notmatch 'case "harnessSeedRecruitmentCapacityFixture"' -or $agentCliSource -notmatch "'recruitOptions'" -or $agentCliSource -notmatch "'recruit'" -or $agentCliSource -notmatch "'harnessSeedRecruitmentCapacityFixture'" -or $agentDecisionLoopSource -notmatch "recruitOptions = @\(\)" -or $agentDecisionLoopSource -notmatch "recruit = @\('OwnerId','TroopId','VolunteerSlot','ConfirmPartySizeWarning'\)" -or $recruitmentAdapterSource -notmatch 'EnsureNativeVolunteerRecruitmentEntryIsAvailable' -or $recruitmentAdapterSource -notmatch 'recruit_volunteers' -or $recruitmentAdapterSource -notmatch 'GetConditionsHold\(Game\.Current, menuContext\)' -or $recruitmentAdapterSource -notmatch 'ExecuteDoneAndConfirmNativeOverLimit' -or $recruitmentAdapterSource -notmatch 'InformationManager.OnShowInquiry' -or $recruitmentCapacityFixtureSource -notmatch 'visual Harness run' -or $recruitmentTestSource -notmatch 'CHRONICLE_HARNESS_MODE = ''visual-capture''' -or $recruitmentTestSource -notmatch 'RecruitmentMenuContextValid' -or $recruitmentTestSource -notmatch 'OffMenuRecruitmentRejectedWithoutMutation' -or $recruitmentTestSource -notmatch 'CapacityWarningConfirmed' -or $recruitmentTestSource -notmatch 'recruitmentRawClockModePreserved' -or $recruitmentTestSource -notmatch 'capacityRawClockModePreserved' -or $agentDecisionLoopSource -match 'harnessSeedRecruitmentCapacityFixture') { throw 'MainParty volunteer recruitment must gate on the Native Settlement menu, preserve native over-limit confirmation, record time state, and prove off-menu rejection/temporary capacity-fixture cleanup.' }
if ($agentProtocolSource -notmatch 'FinalizeVolunteerRecruitmentViewModel' -or $agentProtocolSource -notmatch 'viewModel\?\.OnFinalize\(\)' -or $recruitmentAdapterSource -notmatch 'CreateNativeRecruitmentViewModel' -or $recruitmentAdapterSource -notmatch 'SetCancelInputKey' -or $recruitmentAdapterSource -notmatch 'SetDoneInputKey' -or $recruitmentAdapterSource -notmatch 'SetResetInputKey' -or $recruitmentAdapterSource -notmatch 'SetRecruitAllInputKey' -or $recruitmentAdapterSource -notmatch 'SetGetKeyTextFromKeyIDFunc') { throw 'Detached RecruitmentVM instances must receive the Native screen lifecycle bindings and be finalized after each query/transaction to avoid NRE/leaked event subscriptions.' }
if ($recruitmentAdapterSource -notmatch 'partySizeWarningForOne' -or $recruitmentAdapterSource -notmatch 'nativeCapacityWarningRequired' -or $recruitmentAdapterSource -notmatch 'nativeCapacityConfirmationAccepted' -or $recruitmentTestSource -notmatch 'UnconfirmedCapacityRejectedWithoutMutation' -or $recruitmentTestSource -notmatch 'CapacityFixture') { throw 'Volunteer recruitment must surface Native capacity warnings, require explicit acceptance, and use only a disposable capacity fixture for over-limit confirmation tests.' }
if ($recruitmentAdapterSource -notmatch 'EnsureNativeVolunteerRecruitmentEntryIsAvailable' -or $recruitmentAdapterSource -notmatch 'CurrentMenuContext' -or $recruitmentAdapterSource -notmatch 'recruit_volunteers' -or $recruitmentAdapterSource -notmatch 'GetConditionsHold\(Game\.Current, menuContext\)' -or $recruitmentTestSource -notmatch 'RecruitmentMenuContextValid' -or $recruitmentTestSource -notmatch 'OffMenuRecruitmentRejectedWithoutMutation') { throw 'Volunteer recruitment must respect the currently available Native Settlement menu entry and prove unsupported contexts do not change roster or Gold.' }
$missionInteractionTest = Get-Content (Join-Path $harnessRoot 'Test-AgentMissionInteraction.ps1') -Raw -Encoding UTF8
$missionInteractionAdapter = Get-Content (Join-Path $harnessRoot 'AgentMissionInteraction.cs') -Raw -Encoding UTF8
if ($missionInteractionTest -notmatch 'missionInteract' -or $missionInteractionTest -notmatch 'NativeOnUseStartsObservedTargetConversation' -or $missionInteractionTest -notmatch 'InvalidAgentRejectedWithoutConversation' -or $missionInteractionTest -notmatch 'ConversationTargetMatches' -or $missionInteractionTest -notmatch 'FixtureUnchanged' -or $missionInteractionTest -notmatch 'ProcessStopped' -or $missionInteractionAdapter -notmatch 'target\.OnUse\(mainAgent, -1\)' -or $missionInteractionAdapter -notmatch 'MissionConversationLogic' -or $missionInteractionAdapter -notmatch 'IsThereAgentAction' -or $missionInteractionAdapter -notmatch 'CanInteractWithAgent' -or $missionInteractionAdapter -match 'SetupAndStartMissionConversation' -or $agentProtocolSource -notmatch 'case "missionInteract"' -or $agentCliSource -notmatch "'missionInteract'" -or $agentDecisionLoopSource -notmatch "missionInteract = @\('AgentIndex'\)") { throw 'MissionInteraction must use the local Native Agent.OnUse pipeline, prevalidate native conversation/interaction rules, verify the actual target conversation, and reject invalid targets without direct ConversationManager starts.' }
$companionHiringTest = Get-Content (Join-Path $harnessRoot 'Test-AgentCompanionHiring.ps1') -Raw -Encoding UTF8
if ($companionHiringTest -notmatch 'missionNavigateToAgent' -or $companionHiringTest -notmatch 'missionInteract' -or $companionHiringTest -notmatch 'dialogueSelect' -or $companionHiringTest -notmatch 'main_option_faction_hire' -or $companionHiringTest -notmatch 'player_companion_hire_response_1' -or $companionHiringTest -notmatch 'HireCommitted' -or $companionHiringTest -notmatch 'StrictGoldEqualityRejected' -or $companionHiringTest -notmatch 'harnessPrepareCompanionHiringFixture' -or $companionHiringTest -notmatch 'harnessCompanionHiringDiagnostics' -or $companionHiringTest -notmatch 'FixtureUnchanged' -or $companionHiringTest -notmatch 'ProcessStopped' -or $agentProtocolSource -notmatch 'harnessPrepareCompanionHiringFixture is restricted to a visual Harness run' -or $agentProtocolSource -notmatch 'harnessCompanionHiringDiagnostics is restricted to a visual Harness run' -or $agentDecisionLoopSource -match 'harnessPrepareCompanionHiringFixture|harnessCompanionHiringDiagnostics') { throw 'CompanionHiring must traverse observed Tavern Mission dialogue, verify the native price and Clan/Party result plus strict-gold refusal, and keep Gold injection/diagnostics Harness-only.' }
if ($agentHostCompanionLoopSource -notmatch 'BuildControlCatalog\(gameState == "MapState"' -or
    $agentHostCompanionLoopSource -notmatch 'missionStopProvider' -or
    $agentHostCompanionLoopSource -notmatch 'mission-stop-did-not-recover-to-map' -or
    $agentHostCompanionLoopSource -notmatch 'BuildControlCatalog\(bool allowStop' -or
    $agentHostCompanionLoopSource -notmatch 'decisionFeedback = AgentHostProviderDecisionRecovery\.BuildFeedback' -or
    $agentHostCompanionLoopSource -notmatch 'missionNavigationActive \|\| missionLeaveActive \|\| missionTransitionPending' -or
    $agentHostCompanionLoopSource -notmatch 'do not spend a remote model decision on observeAgain' -or
    $agentHostCompanionLoopSource -notmatch 'companion-action-recovery-exhausted' -or
    $agentHostCompanionLoopSource -notmatch 'establish-clan-companion-passively-waits-for-native-mission-navigation-before-next-model-decision' -or
    $agentHostCompanionLoopSource -notmatch 'establish-clan-companion-bounds-unlisted-action-retries-before-native' -or
    $agentHostCompanionLoopSource -notmatch 'SawActiveMissionNavigation' -or
    $agentHostCompanionLoopSource -notmatch 'missionLeave' -or
    $agentHostDecisionCycleSource -notmatch 'var prompt = EstablishClanCompanionSystemPrompt' -or
    $agentHostDecisionCycleSource -notmatch 'RECOVERY DIRECTIVE') { throw 'Companion Mission stops must be rejected before action, provide a bounded recovery from the exact Native catalog, and keep a Native missionLeave option beside Wanderer navigation/interact.' }
if ($agentHostEstablishClanAutonomySource -notmatch 'IsFreeMapForObjectiveReplan\(failedState\.RootElement\)' -or
    $agentHostEstablishClanAutonomySource -notmatch 'AgentHostCampaignStateFacts\.IsActiveEncounter\(state\)' -or
    $agentHostEstablishClanAutonomySource -notmatch 'town-menu-is-free-map-for-objective-replan-but-hostile-encounter-is-not') { throw 'Parent EYC replan safety must use the shared Native location-menu classifier so a Town menu is not mistaken for a hostile Party encounter, while real encounters remain blocked.' }
if ($agentHostEstablishClanAutonomySource -notmatch 'IsRecoverableObjectiveProviderFailure' -or
    $agentHostEstablishClanAutonomySource -notmatch 'IsSafeMapForObjectiveProviderReplan' -or
    $agentHostEstablishClanAutonomySource -notmatch 'IsSafeTavernMissionForCompanionProviderRecovery' -or
    $agentHostEstablishClanAutonomySource -notmatch 'companion-provider-failure-native-leave-started' -or
    $agentHostEstablishClanAutonomySource -notmatch 'companion-provider-failure-leave-unverified' -or
    $agentHostEstablishClanAutonomySource -notmatch 'objective-provider-failure-route-blocked-on-free-map' -or
    $agentHostEstablishClanAutonomySource -notmatch 'establish-clan-autonomy-leaves-tavern-replans-and-retries-companion-after-native-map-return' -or
    $agentHostEstablishClanAutonomySource -notmatch 'replayedChildActions') { throw 'Companion provider failure may replan only after a supported, modal-free Tavern Native Leave has returned to a free Map; the failed subflow is never replayed and route availability may refresh after verified Native state changes.' }
if ($agentHostEstablishClanAutonomySource -notmatch 'IsFreeMapForObjectiveReplan\(failedState\.RootElement\)' -or
    $agentHostEstablishClanAutonomySource -notmatch 'AgentHostCampaignStateFacts\.IsActiveEncounter\(state\)' -or
    $agentHostEstablishClanAutonomySource -notmatch 'town-menu-is-free-map-for-objective-replan-but-hostile-encounter-is-not') { throw 'Parent EYC replan safety must use the shared Native location-menu classifier so a Town menu is not mistaken for a hostile Party encounter, while true encounters remain blocked.' }
if ($agentHostCompanionLoopSource -notmatch 'SafeTownDecisionWindowSize' -or $agentHostCompanionLoopSource -notmatch 'BuildSafeTownDecisionWindow' -or $agentHostCompanionLoopSource -notmatch 'additionalSafeTownTargetsAvailable' -or $agentHostCompanionLoopSource -notmatch 'establish-clan-companion-town-choice-window-pages-without-world-target-cap' -or $agentHostCompanionLoopSource -notmatch 'while \(decisions < maxDecisions\)' -or $agentHostCompanionLoopSource -notmatch 'do not spend a model decision or issue another move/time command' -or $agentHostDecisionCycleSource -notmatch 'nearest unvisited decision window') { throw 'Companion map travel must use a bounded nearest-Town decision window that preserves access to the remaining world, and must observe active Native movement without repeated model calls or hidden clock actions.' }
if (-not (Test-Path (Join-Path $harnessRoot 'AgentHost\AgentHostCampaignStateFacts.cs')) -or
    $agentHostCampaignStateFactsSource -notmatch 'IsNativeLocationMenu' -or
    $agentHostCampaignStateFactsSource -notmatch 'IsActiveEncounter' -or
    $agentHostCampaignStateFactsSource -notmatch 'campaign-state-facts-training-field-menu-misclassified' -or
    $agentHostCampaignStateFactsSource -notmatch 'campaign-state-facts-hostile-encounter-misclassified' -or
    $agentHostCompanionLoopSource -notmatch 'establish-clan-companion-training-field-menu-misclassified' -or
    $agentHostRecruitmentLoopSource -notmatch 'establish-clan-recruitment-training-field-menu-not-exitable' -or
    $agentHostRecruitmentLoopSource -notmatch 'while \(decisions < maxDecisions\)' -or
    $agentHostRecruitmentLoopSource -notmatch 'decision.Decision, "stop"\) && \(catalog.Count > 0 \|\| controls.Count > 0\)' -or
    $agentHostRecruitmentLoopSource -notmatch 'safe-stop-rejected-with-listed-actions' -or
    $agentHostRecruitmentLoopSource -notmatch 'Choose the currently listed recruitOptions action now' -or
    $agentHostRecruitmentLoopSource -notmatch 'does not recruit anyone or spend Gold' -or
    $agentHostRecruitmentLoopSource -notmatch 'establish-clan-recruitment-recruit-options-recovery-unclear' -or
    $agentHostRecruitmentLoopSource -notmatch 'establish-clan-recruitment-bounds-premature-stop-while-safe-native-actions-remain' -or
    $agentHostRecruitmentLoopSource -notmatch 'establish-clan-recruitment-rejects-premature-stop-and-replans-from-current-native-catalog' -or
    $agentHostRecruitmentLoopSource -notmatch 'TryResolveBackstreetLeave' -or
    $agentHostRecruitmentLoopSource -notmatch 'host-safe-backstreet-exit-after-model-stop' -or
    $agentHostRecruitmentLoopSource -notmatch 'establish-clan-recruitment-native-backstreet-exit-recovery-resumes-on-town-menu' -or
    $agentHostRecruitmentLoopSource -notmatch 'establish-clan-recruitment-resumes-after-native-villagers-in-need-deferral' -or
    $agentHostRecruitmentLoopSource -notmatch 'VillagersInNeedConversation' -or
    $agentHostRecruitmentLoopSource -notmatch 'AgentHostDecisionCycle.IsObserveAgainDecision' -or
    $agentHostRecruitmentLoopSource -notmatch 'action is "mapSettlementTargets" or "move"' -or
    $agentHostMailboxSource -notmatch '"dialogueContinue" => arguments.Count == 0' -or
    $agentHostMailboxSource -notmatch '"dialogueSelect" => arguments.Count == 1 && HasText\(arguments, "optionId"\)' -or
    $agentHostProviderContractSelfTestSource -notmatch 'canonical-observe-again-decision-is-recognized-by-native-subloops' -or
    $agentHostDecisionCycleSource -notmatch 'RECOVERY DIRECTIVE: The previous stop was rejected before any Native action' -or
    $agentHostEstablishClanAutonomySource -notmatch 'recruitment-model-stopped' -or
    $agentHostEstablishClanAutonomySource -notmatch 'recruitment-model-stopped-with-safe-actions' -or
    $agentHostEstablishClanAutonomySource -notmatch 'unavailableObjectives.Add\(objectiveId\)' -or
    $agentHostEstablishClanAutonomySource -notmatch 'establish-clan-autonomy-safe-stop-replan-policy-failed' -or
    $agentHostGoldSaleLoopSource -notmatch 'gold-sale-self-test-training-field-menu-not-exitable' -or
    $agentHostBattleSimulationLoopSource -notmatch 'battle-loop-self-test-training-field-menu-not-exitable' -or
    $agentHostProviderContractSelfTestSource -notmatch 'AgentHostCampaignStateFacts.RunContractSelfTests' -or
    $agentHostMailboxSource -notmatch 'native-recruitment-mailbox-allows-quest-scoped-dialogue-and-current-offer-actions') { throw 'EYC objective subflows must distinguish the verified Native training-field Leave menu from a hostile Party encounter and keep the same leave path out of hostile encounter handling; PartySize VillagersInNeed dialogue must use its bounded recruitment Native transport.' }
$partyRoleAdapterSource = Get-Content (Join-Path $harnessRoot 'AgentPartyRoleAdapter.cs') -Raw -Encoding UTF8
$partyRoleTest = Get-Content (Join-Path $harnessRoot 'Test-AgentPartyRoles.ps1') -Raw -Encoding UTF8
if ($agentProtocolSource -notmatch 'case "partyRoles"' -or $agentProtocolSource -notmatch 'case "setPartyRole"' -or $agentProtocolSource -notmatch 'case "unassignPartyRole"' -or $agentCliSource -notmatch "'partyRoles'" -or $agentCliSource -notmatch "'setPartyRole'" -or $agentCliSource -notmatch "'unassignPartyRole'" -or $agentDecisionLoopSource -notmatch 'partyRoles = @\(\)' -or $agentDecisionLoopSource -notmatch "setPartyRole = @\('RoleId','HeroId'\)" -or $agentDecisionLoopSource -notmatch "unassignPartyRole = @\('RoleId'\)" -or $partyRoleAdapterSource -notmatch 'GetAssignablePartyRoles' -or $partyRoleAdapterSource -notmatch 'ExecuteAssignHeroToRole' -or $partyRoleAdapterSource -notmatch 'GetMapScreenActionIsEnabledWithReason' -or $partyRoleAdapterSource -match 'SetPartyQuartermaster|SetPartyScout|SetPartySurgeon|SetPartyEngineer' -or $agentProtocolSource -notmatch 'PartyRole fixture/diagnostics are restricted to visual Harness runs' -or $agentDecisionLoopSource -match 'harnessSeedPartyRoleFixture|harnessPartyRoleDiagnostics') { throw 'PartyRoles must query native role VM candidates, apply native Campaign action gating and call its native handler; fixture seeding/diagnostics stay Harness-only and bypassing role setters is forbidden.' }
$inventoryNavigationTest = Get-Content (Join-Path $harnessRoot 'Test-AgentInventoryNavigation.ps1') -Raw -Encoding UTF8
$inventoryStateAdapterSource = Get-Content (Join-Path $harnessRoot 'AgentInventoryStateAdapter.cs') -Raw -Encoding UTF8
$equipmentModifierFixtureSource = Get-Content (Join-Path $harnessRoot 'HarnessEquipmentModifierFixture.cs') -Raw -Encoding UTF8
if ($agentProtocolSource -notmatch 'case "harnessInventoryStateDiagnostics"' -or $inventoryStateAdapterSource -notmatch 'OpenThroughNativeMapNavigation' -or $inventoryStateAdapterSource -notmatch 'GetNativeViewModel' -or $inventoryStateAdapterSource -notmatch 'ExecuteTransferWithParameters' -and $inventoryStateAdapterSource -notmatch 'BuildHarnessDiagnosticsJson' -or $inventoryStateAdapterSource -notmatch 'visual Harness runs' -or $inventoryNavigationTest -notmatch 'NativeSPInventoryVMTargetsMainHero' -or $agentDecisionLoopSource -match 'harnessInventoryStateDiagnostics') { throw 'Inventory native VM diagnostics must inspect the currently active SPInventoryVM read-only and remain isolated to Harness mode.' }
if ($agentProtocolSource -notmatch 'case "inventoryOpen"' -or $agentProtocolSource -notmatch 'case "heroEquipmentOptions"' -or $agentProtocolSource -notmatch 'case "equipHeroItem"' -or $agentProtocolSource -notmatch 'case "unequipHeroItem"' -or $agentProtocolSource -notmatch 'case "inventoryConfirm"' -or $agentProtocolSource -notmatch 'case "inventoryCancelChanges"' -or $agentCliSource -notmatch "'equipHeroItem'" -or $agentCliSource -notmatch "'unequipHeroItem'" -or $agentDecisionLoopSource -notmatch "equipHeroItem = @\('ItemViewModelId','EquipmentIndex'\)" -or $agentDecisionLoopSource -notmatch "unequipHeroItem = @\('EquipmentIndex'\)" -or $inventoryStateAdapterSource -notmatch 'ExecuteTransferWithParameters' -or $inventoryStateAdapterSource -notmatch 'ExecuteConfirm' -or $inventoryStateAdapterSource -notmatch 'ExecuteCancel' -or $inventoryStateAdapterSource -notmatch 'GetItemFromIndex' -or $inventoryStateAdapterSource -notmatch 'slot\.EquipmentIndex' -or $inventoryStateAdapterSource -notmatch 'ItemModifier\?\.StringId' -or $inventoryStateAdapterSource -match '\.BattleEquipment\s*=|\.CivilianEquipment\s*=|ItemRoster\.AddToCounts' -or $equipmentTransactionsSource -notmatch 'NativeOccupiedSlotExchangeMatchesVM' -or $equipmentTransactionsSource -notmatch 'StaleNativeItemCandidateRejectedWithoutMutation' -or $equipmentTransactionsSource -notmatch 'PartyStateUnchanged' -or $equipmentTransactionsSource -notmatch 'GoldInfluenceRenownLocationAndTimeUnchanged' -or $equipmentTransactionsSource -notmatch 'NonEmptyModifierSurvivesEquipDoneUnequipDone' -or $equipmentTransactionsSource -notmatch 'harnessSeedEquipmentModifierFixture' -or $equipmentTransactionsSource -notmatch 'harnessClearEquipmentModifierFixture' -or $agentProtocolSource -notmatch 'case "harnessSeedEquipmentModifierFixture"' -or $agentProtocolSource -notmatch 'case "harnessClearEquipmentModifierFixture"' -or $agentProtocolSource -notmatch 'Equipment modifier fixture seeding/cleanup is restricted to visual Harness runs' -or $equipmentModifierFixtureSource -notmatch 'SeedMasterworkSword' -or $equipmentModifierFixtureSource -notmatch 'ClearMasterworkSword' -or $equipmentModifierFixtureSource -notmatch 'ItemModifierGroup.ItemModifiers.Contains' -or $equipmentModifierFixtureSource -notmatch 'AddToCounts' -or $agentDecisionLoopSource -match 'harnessSeedEquipmentModifierFixture|harnessClearEquipmentModifierFixture') { throw 'H08 must verify Native slot/modifier identity, exchange, stale-candidate rejection, world-state invariants and non-empty modifier round-trip; modifier fixture mutation must remain Harness-only.' }
$equipmentTransactionsTest = Get-Content (Join-Path $harnessRoot 'Test-AgentEquipmentTransactions.ps1') -Raw -Encoding UTF8
if ($equipmentTransactionsTest -notmatch 'NativeUnequipTransferDraftMatchesState' -or $equipmentTransactionsTest -notmatch 'NativeDoneCommittedUnequip' -or $equipmentTransactionsTest -notmatch 'NativeEquipTransferDraftMatchesState' -or $equipmentTransactionsTest -notmatch 'NativeDoneCommittedEquip' -or $equipmentTransactionsTest -notmatch 'NativeOccupiedSlotExchangeMatchesVM' -or $equipmentTransactionsTest -notmatch 'SameBaseItemVariantsHaveDistinctCurrentVMIds' -or $equipmentTransactionsTest -notmatch 'StaleNativeItemCandidateRejectedWithoutMutation' -or $equipmentTransactionsTest -notmatch 'IncompatibleNativeItemSlotRejectedWithoutMutation' -or $equipmentTransactionsTest -notmatch 'NonEmptyModifierSurvivesEquipDoneUnequipDone' -or $equipmentTransactionsTest -notmatch 'NativeCancelConfirmationDiscardedDraft' -or $equipmentTransactionsTest -notmatch 'InvalidItemRejectedWithoutMutation' -or $equipmentTransactionsTest -notmatch 'GoldInfluenceRenownLocationAndTimeUnchanged' -or $equipmentTransactionsTest -notmatch 'FixtureHashBefore' -or $equipmentTransactionsTest -notmatch 'ProcessStopped') { throw 'EquipmentTransactions must verify Native item/slot/modifier transfers, modifier-variant identities, exchange, stale/incompatible/invalid rejection, Cancel, unchanged Campaign data and fixture/process cleanup.' }
if ($agentProtocolSource -notmatch 'case "tradeOptions"' -or $agentProtocolSource -notmatch 'case "tradeConfirm"' -or $agentProtocolSource -notmatch 'case "tradeCancelChanges"' -or $agentProtocolSource -match 'ChronicleAgentProvisioning' -or $agentCliSource -notmatch "'tradeConfirm'" -or $agentDecisionLoopSource -notmatch "trade = @\('Direction','ItemViewModelId','InventorySide','Amount'\)" -or $agentDecisionLoopSource -notmatch "provision = @\('ItemViewModelId','Amount'\)" -or $tradeAdapterSource -notmatch 'InventoryMode.Trade' -or $tradeAdapterSource -notmatch 'ExecuteBuy\(amount\)' -or $tradeAdapterSource -notmatch 'ExecuteSell\(amount\)' -or $tradeAdapterSource -notmatch 'inventorySide, expectedSide' -or $tradeAdapterSource -notmatch 'ExecuteConfirm' -or $tradeAdapterSource -notmatch 'ExecuteCancel' -or $tradeAdapterSource -notmatch 'lacksGold' -or $tradeAdapterSource -notmatch 'Native Trade Cancel inquiry' -or $tradeTransactionsSource -notmatch 'NativeTradeQuoteMatchesInventoryLogic' -or $tradeTransactionsSource -notmatch 'NativeTradeOfferPreservesNonEmptyModifier' -or $tradeTransactionsSource -notmatch 'NativeBuyTransferAndDoneVerified' -or $tradeTransactionsSource -notmatch 'NativeSellTransferAndDoneVerified' -or $tradeTransactionsSource -notmatch 'NativeCancelInquiryDiscardsUncommittedBuy' -or $tradeTransactionsSource -notmatch 'NativeTownTradeBuySellPreserveArrivalClockMode' -or $tradeTransactionsSource -notmatch 'OverMarketStockRejectedWithoutGoldOrMarketMutation' -or $tradeTransactionsSource -notmatch 'WrongInventorySideRejectedWithoutDraft' -or $tradeTransactionsSource -notmatch 'InsufficientGoldRejectedAndNativeDraftRolledBack' -or $tradeTransactionsSource -notmatch 'NativeCapacityRuleObservedWithoutPersistentMutation' -or $tradeTransactionsSource -notmatch 'TradeRequiresActiveNativeTradeState' -or $tradeTransactionsSource -notmatch 'FixtureUnchanged' -or $recruitmentTestSource -notmatch 'Open-NativeTownTrade' -or (Test-Path (Join-Path $harnessRoot 'AgentProvisioning.cs'))) { throw 'Town trade/provision actions must use the active native Trade Inventory VM and explicit candidate sides, preserve modifier identity, affordability rollback and native buy/sell/Done/Cancel semantics, and keep coverage on a disposable fixture.' }
$tradeRumorTestSource = Get-Content (Join-Path $harnessRoot 'Test-AgentTradeTransactions.ps1') -Raw -Encoding UTF8
$tradeRumorQuerySource = [regex]::Match($tradeAdapterSource, 'internal static string BuildTradeRumorOptionsJson\([\s\S]*?\n    internal static string SeedHarnessTradeRumorFixture').Value
if ($agentProtocolSource -notmatch 'case "tradeRumors"' -or $agentCliSource -notmatch "'tradeRumors'" -or $agentDecisionLoopSource -notmatch "tradeRumors = @\('ItemViewModelId','InventorySide'\)" -or $tradeAdapterSource -notmatch 'ITradeRumorCampaignBehavior' -or $tradeAdapterSource -notmatch 'InventoryItemType.Goods' -or $tradeAdapterSource -notmatch 'RumorEndTime.RemainingDaysFromNow' -or $tradeAdapterSource -notmatch '0\.9f \* localSellingPrice' -or $tradeAdapterSource -notmatch '1\.1f \* localBuyingPrice' -or $tradeAdapterSource -notmatch 'RequireVisualHarnessTradeRumorFixture' -or $tradeRumorQuerySource -match 'new ItemMenuVM|\.SetItem\(' -or $agentDecisionLoopSource -match 'harnessSeedTradeRumorFixture|harnessTradeRumorTooltipDiagnostics' -or $tradeRumorTestSource -notmatch 'MarketGoodsRumorsMatchNativeItemMenuVM' -or $tradeRumorTestSource -notmatch 'PlayerGoodsRumorsMatchNativeItemMenuVM' -or $tradeRumorTestSource -notmatch 'SeededRumorIds' -or $tradeRumorTestSource -notmatch 'ExpiredRumorFilteredByNativeBehavior' -or $tradeRumorTestSource -notmatch 'CurrentTownRumorsExcluded' -or $tradeRumorTestSource -notmatch 'TradeRumorReadsDoNotMutateWorldOrClock' -or $tradeRumorTestSource -notmatch 'NonGoodsDoNotExposeNativeTradeRumors' -or $tradeRumorTestSource -notmatch 'TradeRumorQueryRequiresActiveTradeState') { throw 'tradeRumors must be limited to the current observed Trade candidate and match Native ItemMenuVM Goods filtering, price thresholds, expiry, text and side parity; deterministic rumor seeding and tooltip diagnostics must remain Harness-only.' }
if ($agentProtocolSource -notmatch 'case "barterOptions"' -or $agentProtocolSource -notmatch 'case "barterEdit"' -or $agentProtocolSource -notmatch 'case "barterAutoBalance"' -or $agentProtocolSource -notmatch 'case "barterOffer"' -or $agentProtocolSource -notmatch 'case "barterCancel"' -or $agentCliSource -notmatch "'barterOptions'" -or $agentCliSource -notmatch "'barterEdit'" -or $agentCliSource -notmatch "'barterAutoBalance'" -or $agentDecisionLoopSource -notmatch "barterEdit = @\('BarterCandidateId','BarterOperation','Amount'\)" -or $agentDecisionLoopSource -notmatch 'barterAutoBalance = @\(\)' -or $barterCaptureSource -notmatch 'typeof\(BarterVM\)' -or $barterCaptureSource -notmatch 'BarterManager.*Close' -or $barterAdapterSource -match 'new BarterVM' -or $barterAdapterSource -notmatch 'ExecuteAutoBalance\(\)' -or $barterAdapterSource -notmatch 'IsOfferDisabled' -or $barterAdapterSource -notmatch 'ExecuteAction\(\)' -or $barterAdapterSource -notmatch 'ExecuteRemoveOffered\(\)' -or $barterAdapterSource -notmatch 'ExecuteReset\(\)' -or $barterAdapterSource -notmatch 'ExecuteOffer\(\)' -or $barterAdapterSource -notmatch 'ExecuteCancel\(\)' -or $barterTransactionsSource -notmatch 'NativeHeroBarterEntryOpenedLiveBarterVM' -or $barterTransactionsSource -notmatch 'NativeItemAndAutoBalanceUsesCashAndOwnedItem' -or $barterTransactionsSource -notmatch 'NativeCancelDiscardsGoldDraft' -or $barterTransactionsSource -notmatch 'NativeOfferAcceptedAndTransfersExactlyOneGold' -or $barterTransactionsSource -notmatch 'DisposableBarterAssetFixtureCleared' -or $barterTransactionsSource -notmatch 'FixtureHashUnchanged' -or $barterTransactionsSource -notmatch 'ProcessStopped') { throw 'Barter must capture the actual Native BarterVM across player contexts, expose its shared observation/edit/autobalance/Offer/Cancel handlers, honor Native transferability and IsOfferDisabled guards, and verify cancel/commit results plus fixture cleanup.' }
if ($agentProtocolSource -notmatch 'case "barterAutoBalance"' -or $agentCliSource -notmatch "'barterAutoBalance'" -or $agentDecisionLoopSource -notmatch 'barterAutoBalance = @\(\)' -or $barterAdapterSource -notmatch 'ExecuteAutoBalance\(\)' -or $barterTransactionsSource -notmatch 'NativeItemAndAutoBalanceUsesCashAndOwnedItem') { throw 'Barter Auto Balance must invoke the active Native VM button, remain callable as a no-argument agent tool, and verify its ordinary Lord money/item behavior.' }
if ($agentProtocolSource -notmatch 'case "harnessPrepareSafePassageFixture"' -or $agentProtocolSource -notmatch 'harnessPrepareSafePassageFixture is restricted to a visual Harness run' -or $agentCliSource -notmatch "'harnessPrepareSafePassageFixture'" -or $agentDecisionLoopSource -notmatch 'HarnessPrepareSafePassageAfterMove' -or $agentDecisionLoopSource -notmatch 'visual Harness run whose decision allowlist includes Native move' -or $safePassageFixtureSource -notmatch 'BanditPartyComponent\.CreateLooterParty' -or $safePassageFixtureSource -notmatch 'SetMoveEngageParty\(mainParty' -or $safePassageFixtureSource -match 'EncounterManager\.StartPartyEncounter' -or $safePassageFixtureSource -notmatch 'GetEncounterJoiningRadius' -or $safePassageFixtureSource -notmatch 'PotentialPlayerJoiners' -or $safePassageFixtureSource -notmatch 'GetCustomStrength' -or $safePassageFixtureSource -notmatch 'FindNearbyNavigablePoint' -or $safePassageFixtureSource -notmatch 'FindNearestSettlementToMobileParty' -or $barterContextsSource -notmatch 'bandit_start_defender_2' -or $barterContextsSource -notmatch 'InitializeSafePassageBarterContext' -or $barterContextsSource -notmatch 'BanditFixtureOutnumbersNativeJoiningSide' -or $barterContextsSource -notmatch 'NativeJoiningPartiesRecorded' -or $barterContextsSource -notmatch "'moveToPoint'" -or $barterContextsSource -notmatch 'StoppablePlay' -or $barterContextsSource -notmatch 'Wait-ForBanditConversation' -or $barterContextsSource -notmatch 'consecutiveTimeouts -ge 3' -or $barterContextsSource -notmatch 'CHRONICLE_CAPTURE_CRASH_EXCEPTION' -or $barterContextsSource -notmatch 'CrashExceptionCaptured' -or $barterContextsSource -notmatch 'System\.IO\.File\]::ReadAllText' -or $barterContextsSource -notmatch 'NativeAutoBalanceStayedInSafePassageContext' -or $barterContextsSource -notmatch 'FixtureHashUnchanged' -or $barterContextsSource -notmatch 'ProcessStopped') { throw 'Safe Passage Barter regression must create a disposable hostile Native Bandit through AI pursuit, preserve ordinary map-clock semantics, use the captured Native BarterVM and retain fixture integrity; any integrated Safe Passage stimulus must remain explicitly Harness-gated.' }
if ($safePassageFixtureSource -notmatch 'playerSideStrength \* 1\.56f' -or $barterContextsSource -notmatch 'requiredBanditStrength -ge 1\.55' -or $barterContextsSource -notmatch 'function Get-AutoBalanceWorldFingerprint' -or $barterContextsSource -notmatch 'worldFingerprintBeforeAutoBalance -ceq \$worldFingerprintAfterAutoBalance' -or $barterContextsSource -notmatch 'Native Safe Passage assertions failed before fixture shutdown' -or $barterContextsSource -match 'NativeAutoBalancePreservedWorldAndClock\s*=\s*\([^\r\n]*otherPartyFingerprintUnchanged') { throw 'Safe Passage fixture strength must include numeric rounding headroom; Auto Balance must compare its own before/after native world observation and perform assertions while a failing screen can still be captured.' }
$safePassageResearchSource = Get-Content (Join-Path $harnessRoot 'Research\E\EconomyAndTrade.md') -Raw -Encoding UTF8
if ($barterContextsSource -notmatch '\[switch\]\$CancelOnly' -or $barterContextsSource -notmatch 'SafePassageBarterCancelResult\.json' -or $barterContextsSource -notmatch 'NativeContinueRestoredEncounterMenu' -or $harnessScript -notmatch '\$barterContextsScript -CancelOnly' -or $safePassageResearchSource -notmatch 'TestResults/20260928-170916/Temp/SafePassageBarterCancelResult.json' -or $safePassageResearchSource -notmatch '而不是重新显示Safe Passage威胁选择') { throw 'Safe Passage Cancel must have its own disposable Harness run and preserve evidence that Native Continue returns to the Encounter menu, not the toll choices.' }
if ($barterContextsSource -notmatch '\[switch\]\$FightOnly' -or $barterContextsSource -notmatch 'bandit_start_defender_1' -or $barterContextsSource -notmatch 'NativePlayerBattleEntryAvailable' -or $barterContextsSource -notmatch 'NativeSendTroopsEntryAvailable' -or $harnessScript -notmatch '\$barterContextsScript -FightOnly' -or $harnessScript -notmatch "'BarterFightRoute'\s*\{\s*@\('Preflight',\s*'Build',\s*'BarterFightRoute'\)\s*\}" -or $harnessScript -notmatch "Invoke-Stage -Name 'BarterFightRoute'" -or $developmentDoc -notmatch 'BarterFightRoute') { throw 'Safe Passage Fight must be runnable as a standalone disposable Harness phase from the active threat dialogue, while the full BarterContexts phase also retains that branch.' }
if ($barterContextsSource -notmatch '\[switch\]\$ObserveExpiry' -or $harnessScript -notmatch "'BarterSafePassage'\s*\{\s*@\('Preflight',\s*'Build',\s*'BarterSafePassage'\)\s*\}" -or $harnessScript -notmatch "Invoke-Stage -Name 'BarterSafePassage'" -or $harnessScript -notmatch '\$barterContextsScript -ObserveExpiry' -or $developmentDoc -notmatch 'BarterSafePassage') { throw 'The 32-hour natural cooldown test must be a separate disposable Harness phase so unrelated random encounters do not make the standard BarterContexts suite flaky.' }
if ($barterContextsSource -notmatch "Invoke-AgentCli 'barterCancel'" -or $barterContextsSource -notmatch "Invoke-AgentCli 'dialogueContinue'" -or $barterContextsSource -notmatch 'NativeCancelChangedNoResourcesOrClock' -or $barterContextsSource -notmatch 'NativeContinueRestoredEncounterMenu' -or $barterContextsSource -notmatch 'NativeFightOptionAvailableAfterCancel' -or $barterContextsSource -notmatch "Invoke-AgentCli 'barterOffer'" -or $barterContextsSource -notmatch 'Wait-ForSafePassageExit' -or $barterContextsSource -notmatch 'NativeSafePassageOfferCommitted144' -or $barterContextsSource -notmatch 'NativeEncounterEndedAfterAcceptedSafePassage' -or $barterContextsSource -notmatch "Invoke-AgentCli 'harnessMapPartyDiagnostics'" -or $barterContextsSource -notmatch 'Native32HourDoNotAttackCooldownSet' -or $barterContextsSource -notmatch 'NativeSafePassageHoldModeObserved' -or $barterContextsSource -notmatch "Invoke-AgentCli 'advance'" -or $barterContextsSource -notmatch 'HarnessExplicitAdvanceCrossed32HourCooldownBoundary' -or $barterContextsSource -notmatch 'EarlyExpiryEncounterWasCausedByFixtureBandit' -or $barterContextsSource -notmatch 'NativeSafePassageCooldownExpiredAfterAdvance' -or $agentProtocolSource -notmatch 'doNotAttackMainPartyRemainingHours' -or $agentProtocolSource -notmatch 'DoNotAttackMainPartyUntil\.RemainingHoursFromNow' -or $agentProtocolSource -notmatch 'party\.PartyMoveMode\.ToString\(\)' -or $barterContextsSource -notmatch 'Native Safe Passage outcome assertions failed before fixture shutdown') { throw 'Safe Passage regression must verify Native Cancel without world/clock mutation, accepted payment/exit/cooldown state, and explicitly advance at least 32 hours through natural cooldown expiry or an encounter from the fixture bandit.' }
if ($safePassageResearchSource -notmatch 'DoNotAttackMainParty' -or $safePassageResearchSource -notmatch '32小时.*中途采样') { throw 'Safe Passage research must distinguish the source-backed 32-hour field, elapsed expiry evidence, and the fact that intermediate behavior was not sampled.' }
if ($safePassageResearchSource -notmatch 'Safe Passage 运行验收（W2-W）' -or $safePassageResearchSource -notmatch 'TestResults/20260928-161518/Temp/SafePassageBarterContextResult.json' -or $safePassageResearchSource -notmatch 'TestResults/20260928-181704/Temp/SafePassageBarterContextResult.json' -or $safePassageResearchSource -notmatch 'CrashException-18860\.txt' -or $safePassageResearchSource -notmatch '尚未证实' -or $safePassageResearchSource -notmatch '金币从1000降到856' -or $safePassageResearchSource -notmatch 'RemainingHoursFromNow=32\.0' -or $safePassageResearchSource -notmatch '32.4小时' -or $safePassageResearchSource -notmatch 'PatrolAroundPoint') { throw 'Economy research must preserve the accepted native Bandit Safe Passage receipt, observed 32-hour timer expiry and PatrolAroundPoint recovery evidence, plus the earlier exception evidence.' }
if ($agentProtocolSource -notmatch 'TryCaptureUnexpectedProtocolFailureFrame' -or $agentProtocolSource -notmatch 'Utilities\.TakeScreenshot\(imagePath\)' -or $agentProtocolSource -notmatch 'exception is InvalidOperationException' -or $testAgentSupportSource -notmatch 'function Capture-HarnessFailureFrame' -or $testAgentSupportSource -notmatch "Invoke-AgentCli.*captureFrame|captureFrame" -or $testAgentSupportSource -notmatch 'processId' -or $testAgentSupportSource -notmatch 'harness-failure-frame\.bmp' -or $testAgentSupportSource -notmatch 'protocol-unexpected-failure-frame\.bmp' -or $barterContextsSource -notmatch 'Capture-HarnessFailureFrame' -or $barterTransactionsSource -notmatch 'Capture-HarnessFailureFrame') { throw 'Harness UI tests must preserve the native game-engine frame on unexpected protocol errors and pre-cleanup test failures, with the failure step and owning process, without desktop-wide screenshots.' }
if ($partyRoleTest -notmatch 'NativeRoleVMMatchesMobilePartyBaseline' -or $partyRoleTest -notmatch 'ThreeRoleNativeReplacementIsObserved' -or $partyRoleTest -notmatch 'InvalidRoleHeroAndRemovalRejectedWithoutMutation' -or $partyRoleTest -notmatch 'ActiveCampaignTimeModeUnaffected' -or $partyRoleTest -notmatch 'FixtureUnchanged' -or $partyRoleTest -notmatch 'ProcessStopped') { throw 'PartyRoles regression must compare native role state, verify two-role replacement semantics, invalid-action safety, time mode and fixture/process cleanup.' }
$mapSettlementTargetsTest = Get-Content (Join-Path $harnessRoot 'Test-AgentMapSettlementTargets.ps1') -Raw -Encoding UTF8
if ($mapSettlementTargetsTest -notmatch 'harnessMapDiagnostics' -or $mapSettlementTargetsTest -notmatch 'mapSettlementTargets' -or $mapSettlementTargetsTest -notmatch 'HiddenIdAbsentFromMapObservation' -or $mapSettlementTargetsTest -notmatch 'MoveRejectedForVisibility' -or $mapSettlementTargetsTest -notmatch 'NoMutation' -or $mapSettlementTargetsTest -notmatch 'FixtureUnchanged' -or $mapSettlementTargetsTest -notmatch 'ProcessStopped') { throw 'MapSettlementTargets must compare the native IsVisible set and prove hidden targets are rejected without state or fixture mutation.' }
$mapNotificationsAdapterSource = Get-Content (Join-Path $harnessRoot 'AgentMapNotifications.cs') -Raw -Encoding UTF8
$mapNotificationsTestSource = Get-Content (Join-Path $harnessRoot 'Test-AgentMapNotifications.ps1') -Raw -Encoding UTF8
if ($agentProtocolSource -notmatch 'case "mapNotifications"' -or $agentProtocolSource -notmatch 'case "harnessSeedMapNotificationFixture"' -or $agentCliSource -notmatch "'mapNotifications'" -or $agentDecisionLoopSource -notmatch 'mapNotifications = @\(\)' -or $agentDecisionLoopSource -match 'harnessSeedMapNotificationFixture' -or $harnessScript -notmatch "'MapNotifications' \{ @\('Preflight', 'Build', 'MapNotifications'\) \}" -or $harnessScript -notmatch "Invoke-Stage -Name 'MapNotifications'" -or $mapNotificationsAdapterSource -notmatch 'CampaignInformationManager' -or $mapNotificationsAdapterSource -notmatch '_mapNotices' -or $mapNotificationsAdapterSource -notmatch 'MapNotificationVM' -or $mapNotificationsAdapterSource -notmatch 'AddMapNotification' -or $mapNotificationsAdapterSource -notmatch 'notice.IsValid\(\)' -or $mapNotificationsAdapterSource -notmatch 'item.OnFinalize\(\)' -or $mapNotificationsAdapterSource -notmatch 'viewModel.OnFinalize\(\)' -or $mapNotificationsAdapterSource -notmatch 'RequireVisualHarnessFixture' -or $mapNotificationsTestSource -notmatch 'NativeMapNotificationVMMappingReturnedItem' -or $mapNotificationsTestSource -notmatch 'UnregisteredNativeNoticeNotExposed' -or $mapNotificationsTestSource -notmatch 'InvalidNoticeNotExposed' -or $mapNotificationsTestSource -notmatch 'ObservationDoesNotMutateCampaignOrClock' -or $mapNotificationsTestSource -notmatch 'RepeatedReadsStableAndOrdered' -or $mapNotificationsTestSource -notmatch 'FixtureUnchanged' -or $mapNotificationsTestSource -notmatch 'ProcessStopped' -or $developmentDoc -notmatch 'MapNotifications') { throw 'Campaign Map notices must be observed through the native MapNotificationVM mapping, valid entries only, and prove deterministic read/no world mutation with Harness-only disposable data.' }
$quickInformationAdapterSource = Get-Content (Join-Path $harnessRoot 'AgentQuickInformation.cs') -Raw -Encoding UTF8
$quickInformationTestSource = Get-Content (Join-Path $harnessRoot 'Test-AgentQuickInformation.ps1') -Raw -Encoding UTF8
if ($agentProtocolSource -notmatch 'case "quickInformation"' -or $agentProtocolSource -notmatch 'case "harnessSeedQuickInformationFixture"' -or $agentCliSource -notmatch "'quickInformation'" -or $agentDecisionLoopSource -notmatch 'quickInformation = @\(\)' -or $agentDecisionLoopSource -match 'harnessSeedQuickInformationFixture' -or $harnessScript -notmatch "'QuickInformation' \{ @\('Preflight', 'Build', 'QuickInformation'\) \}" -or $harnessScript -notmatch "Invoke-Stage -Name 'QuickInformation'" -or $quickInformationAdapterSource -notmatch 'GauntletGameNotificationTypeName' -or $quickInformationAdapterSource -notmatch 'CurrentNotification' -or $quickInformationAdapterSource -notmatch 'GotNotification' -or $quickInformationAdapterSource -notmatch 'IsPaused' -or $quickInformationAdapterSource -notmatch 'IsDialog' -or $quickInformationAdapterSource -match 'FiringQuickInformation\s*\+=' -or $quickInformationAdapterSource -match 'GetField\("_items"' -or $quickInformationAdapterSource -notmatch 'RequireVisualHarnessFixture' -or $quickInformationTestSource -notmatch 'NativeQuickInfoUIAvailable' -or $quickInformationTestSource -notmatch 'HiddenQueuedQuickInfoNotExposed' -or $quickInformationTestSource -notmatch 'QuickInfoReadDoesNotMutateCampaignOrClock' -or $quickInformationTestSource -notmatch 'FixtureUnchanged' -or $quickInformationTestSource -notmatch 'ProcessStopped' -or $developmentDoc -notmatch 'QuickInformation') { throw 'QuickInformation must report only the visible native Current item, never cache/inspect the hidden queue, filter paused/Dialog content, and pass a disposable native event regression.' }
$sceneNotificationAdapterSource = Get-Content (Join-Path $harnessRoot 'AgentSceneNotification.cs') -Raw -Encoding UTF8
$sceneNotificationTestSource = Get-Content (Join-Path $harnessRoot 'Test-AgentSceneNotification.ps1') -Raw -Encoding UTF8
$companionLoopSource = Get-Content (Join-Path $harnessRoot 'AgentHost\AgentHostEstablishClanCompanionLoop.cs') -Raw -Encoding UTF8
$companionPromptSource = Get-Content (Join-Path $harnessRoot 'AgentHost\AgentHostDecisionCycle.cs') -Raw -Encoding UTF8
 $storyModeSetupLoopSource = Get-Content (Join-Path $harnessRoot 'AgentHost\AgentHostStoryModeSetupLoop.cs') -Raw -Encoding UTF8
 $bannerEditorAdapterSource = Get-Content (Join-Path $harnessRoot 'AgentBannerEditor.cs') -Raw -Encoding UTF8
 $nativeInquiryAdapterSource = Get-Content (Join-Path $harnessRoot 'AgentInquiryAdapter.cs') -Raw -Encoding UTF8
if ($agentProtocolSource -notmatch 'case "sceneNotification"' -or $agentProtocolSource -notmatch 'case "continueSceneNotification"' -or $agentProtocolSource -notmatch 'case "submitStoryModeClanName"' -or $agentProtocolSource -notmatch 'case "bannerEditorDone"' -or $agentProtocolSource -notmatch 'case "harnessSeedSceneNotificationFixture"' -or
    $agentCliSource -notmatch "'sceneNotification'" -or $agentCliSource -notmatch "'continueSceneNotification'" -or $agentCliSource -notmatch "'submitStoryModeClanName'" -or $agentCliSource -notmatch "'bannerEditorDone'" -or
    $agentObserverSource -notmatch 'BuildJson\(includeClockAudit: false\)' -or $agentObserverSource -notmatch 'ChronicleAgentBannerEditor.BuildJson' -or $agentDecisionLoopSource -notmatch 'sceneNotification = @\(\)' -or $agentDecisionLoopSource -match 'harnessSeedSceneNotificationFixture' -or
    $harnessScript -notmatch "'SceneNotification' \{ @\('Preflight', 'Build', 'SceneNotification'\) \}" -or $harnessScript -notmatch "Invoke-Stage -Name 'SceneNotification'" -or
    $sceneNotificationAdapterSource -notmatch 'GauntletSceneNotificationTypeName' -or $sceneNotificationAdapterSource -notmatch 'FindingFirstBannerPieceSceneNotificationItem' -or
    $sceneNotificationAdapterSource -notmatch 'CanContinueFirstBannerNotification' -or $sceneNotificationAdapterSource -notmatch '_onCloseAction' -or $sceneNotificationAdapterSource -notmatch 'OnPieceFoundAction' -or $sceneNotificationAdapterSource -notmatch 'ExecuteClose\(\)' -or
    $sceneNotificationAdapterSource -notmatch 'hasActiveNotification' -or $sceneNotificationAdapterSource -notmatch 'IsShown' -or $sceneNotificationAdapterSource -notmatch 'IsReady' -or
    $sceneNotificationAdapterSource -notmatch 'ButtonOkLabel' -or $sceneNotificationAdapterSource -notmatch 'ButtonCancelLabel' -or
    $sceneNotificationAdapterSource -match 'OnAffirmativeAction\(|OnNegativeAction\(|OnCloseAction\(' -or $sceneNotificationAdapterSource -notmatch 'RequireVisualHarnessFixture' -or
    $nativeInquiryAdapterSource -notmatch 'StoryModeClanNameTextInquiry' -or $nativeInquiryAdapterSource -notmatch 'TextQueryPopUpVM.ExecuteAffirmativeAction' -or
    $bannerEditorAdapterSource -notmatch 'BannerEditorVM.ExecuteDone' -or $bannerEditorAdapterSource -notmatch 'ExecuteDone' -or
    $storyModeSetupLoopSource -notmatch 'family-name' -or $storyModeSetupLoopSource -notmatch 'banner-editor-done' -or $storyModeSetupLoopSource -notmatch 'stealth-tutorial-start' -or
    $storyModeSetupLoopSource -notmatch 'if \(!ReadBoolean\(scene, "isReady"\) \|\| !ReadBoolean\(scene, "canContinue"\)\)' -or
    $storyModeSetupLoopSource -notmatch 'storymode-setup-waits-for-scene-notification-native-readiness-without-spending-model-call' -or
    $companionLoopSource -notmatch 'continueSceneNotification' -or $companionLoopSource -notmatch 'native-map-scene-notification-closes-then-movement-resumes' -or
    $companionPromptSource -notmatch 'FindingFirstBannerPieceSceneNotificationItem' -or $companionPromptSource -notmatch 'family-name' -or
    $sceneNotificationTestSource -notmatch 'NativeSceneNotificationVMFieldsMatchData' -or $sceneNotificationTestSource -notmatch 'ActualEngineFrameCaptured' -or
    $sceneNotificationTestSource -notmatch 'RepeatedReadDoesNotDismissAndActiveTimeIsPaused' -or $sceneNotificationTestSource -notmatch 'NativeCloseHandlerDismissesCurrentCard' -or
    $sceneNotificationTestSource -notmatch 'NativeCloseHandlerOpensClanNameTextInquiry' -or $sceneNotificationTestSource -notmatch 'CurrentNativeNameAcceptedThroughTextQueryVM' -or
    $sceneNotificationTestSource -notmatch 'NativeBannerEditorFrameCaptured' -or $sceneNotificationTestSource -notmatch 'NativeBannerEditorDoneHandlerReturnedToMap' -or
    $sceneNotificationTestSource -notmatch 'FollowUpStealthTutorialPromptObserved' -or $sceneNotificationTestSource -notmatch 'FixtureUnchanged' -or
    $sceneNotificationTestSource -notmatch 'ProcessStopped' -or $developmentDoc -notmatch 'SceneNotification') {
    throw 'StoryMode setup support must follow the exact Native SceneNotification callback through validated clan-name entry, BannerEditor Done and the subsequent tutorial inquiry, while preserving modal/time and clean-fixture evidence.'
}

$missionLeaveInputSource = Get-Content (Join-Path $harnessRoot 'AgentMissionLeave.cs') -Raw -Encoding UTF8
$missionLeaveTestSource = Get-Content (Join-Path $harnessRoot 'Test-AgentMissionLeave.ps1') -Raw -Encoding UTF8
if ($agentProtocolSource -notmatch 'case "missionLeave"' -or $agentProtocolSource -notmatch 'leaveMission\.InputManager = _missionLeaveInputContext' -or $agentProtocolSource -match 'Mission\.EndMission\(' -or $agentObserverSource -notmatch 'BuildMissionLeaveObservationJson' -or $agentCliSource -notmatch "'missionLeave'" -or $agentDecisionLoopSource -notmatch 'missionLeave = @\(\)' -or $harnessScript -notmatch "'MissionLeave' \{ @\('Preflight', 'Build', 'MissionLeave'\) \}" -or $harnessScript -notmatch "Invoke-Stage -Name 'MissionLeave'" -or $missionLeaveInputSource -notmatch 'IInputContext' -or $missionLeaveInputSource -notmatch 'IsGameKeyDown\(int gameKey\)' -or $missionLeaveInputSource -match 'SendInput|keybd_event|SetCursorPos' -or $missionLeaveTestSource -notmatch 'mission-leave-before\.bmp' -or $missionLeaveTestSource -notmatch 'mission-leave-after\.bmp' -or $missionLeaveTestSource -notmatch 'missionLeave' -or $missionLeaveTestSource -notmatch 'ReturnedGameState' -or $missionLeaveTestSource -notmatch 'CampaignTimeUnchanged' -or $missionLeaveTestSource -notmatch 'FixtureUnchanged' -or $missionLeaveTestSource -notmatch 'ProcessStopped' -or $developmentDoc -notmatch 'MissionLeave' -or $mainlineDoc -notmatch 'Location Mission长按离开/返回Campaign Map' -or $mainlineDoc -notmatch 'OnEndMissionRequest') { throw 'Mission Leave must hold the current Mission InputContext leave action for a bounded lease, preserve native OnEndMissionRequest/veto logic, and verify MapState return, clock, screenshots and cleanup.' }
if ($harnessScript -notmatch "'All' \{ [^}]*'MissionLeave'[^}]*\}") { throw 'MissionLeave is a validated Native Campaign transition and must remain part of the full harness regression.' }
if ($agentProtocolSource -match 'var (quickTalkData|visitData) = [^\r\n]*(hasIssue|issueType|RequestedItem|numberOfRequested|locationId)' -or $agentProtocolSource -notmatch 'var quickTalkData = .*heroName' -or $agentProtocolSource -notmatch 'var visitData = .*heroName') { throw 'Settlement overlay conversation actions may echo only the currently observed target identity; Quest/Issue implementation fields and internal Location IDs are not player-visible knowledge.' }
$freshCampaignSource = Get-Content (Join-Path $harnessRoot 'FreshCampaignHarness.cs') -Raw -Encoding UTF8
$freshCampaignTelemetry = Get-Content (Join-Path $harnessRoot 'SubModule.cs') -Raw -Encoding UTF8
if ($harnessStartupEvidenceSource -notmatch 'function Disable-ChronicleHarnessAutoSave' -or
    $harnessStartupEvidenceSource -notmatch 'BannerlordConfig\.chronicle-autosave-backup\.json' -or
    $harnessStartupEvidenceSource -notmatch 'function Restore-ChronicleHarnessAutoSaveSetting' -or
    $harnessStartupEvidenceSource -notmatch 'AutoSaveInterval=\(-\?\\d\+\)' -or
    $freshCampaignTest -notmatch 'Disable-ChronicleHarnessAutoSave' -or
    $freshCampaignTest -notmatch 'bannerlordAutoSaveDisabledDuringRun' -or
    $freshCampaignTest -notmatch 'noNativeAutoSaveObserved' -or
    $freshCampaignTest -notmatch 'AutoSaveCurrentGame' -or
    $harnessScript -notmatch 'Restore-ChronicleHarnessAutoSaveSetting') { throw 'FreshCampaign must disable Native AutoSaveInterval through its exact -1 off value, restore the prior setting after game cleanup, and recover stale backups before later Harness runs.' }
foreach ($autosaveHelper in @('Get-ChronicleBannerlordAutoSavePaths', 'Get-ChronicleBannerlordAutoSaveInterval', 'Set-ChronicleBannerlordAutoSaveInterval', 'Restore-ChronicleHarnessAutoSaveSetting', 'Disable-ChronicleHarnessAutoSave')) {
    if ([regex]::Matches($harnessStartupEvidenceSource, "(?m)^function $([regex]::Escape($autosaveHelper))\b").Count -ne 1) { throw "HarnessStartupEvidence.ps1 must define exactly one '$autosaveHelper' autosave helper." }
}
$pursuitTestSource = Get-Content (Join-Path $harnessRoot 'Test-AgentPursuit.ps1') -Raw -Encoding UTF8
$moveToPointTestSource = Get-Content (Join-Path $harnessRoot 'Test-AgentMoveToPoint.ps1') -Raw -Encoding UTF8
$protocolTestSource = Get-Content (Join-Path $harnessRoot 'Test-AgentProtocol.ps1') -Raw -Encoding UTF8
if ($freshCampaignTest -notmatch 'storyModeFocusLossEscapeMenuGuardInstalled' -or $freshCampaignTest -notmatch 'StoryModeFocusLossEscapeMenuGuardInstalled') { throw 'Natural StoryMode live-model tests must record whether the focus-loss Escape guard was installed in their lifecycle harness mode.' }
if ($pursuitTestSource -notmatch 'hold-settled' -or $pursuitTestSource -notmatch 'AgentPursuitResult\.json' -or $pursuitTestSource -notmatch 'PursuitPrecondition' -or $pursuitTestSource -notmatch 'ProbeEscortVisibilityLoss' -or $pursuitTestSource -notmatch 'AgentPursuitVisibilityResult\.json' -or $pursuitTestSource -notmatch 'target-left-nearby-observation' -or $pursuitTestSource -notmatch 'target-remained-in-nearby-observation-for-window' -or $pursuitTestSource -notmatch 'DaysElapsed') { throw 'Pursuit must compare invalid actions against a settled observation and preserve dedicated Escort visibility probe evidence.' }
if ($pursuitTestSource -notmatch 'ProbeConversation' -or $pursuitTestSource -notmatch 'AgentConversationResult\.json' -or $pursuitTestSource -notmatch 'lord_meet_player_response1' -or $pursuitTestSource -notmatch 'dialogueContinue' -or $pursuitTestSource -notmatch 'invalidContinueNoMutation' -or $pursuitTestSource -notmatch 'ContinueWithOpenOptions') { throw 'Campaign conversation coverage must use a real native Lord meeting and preserve option/continue guard evidence.' }
if ($pursuitTestSource -notmatch 'ProbeQuestAcceptance' -or $pursuitTestSource -notmatch 'issue_offer_player_accept_quest' -or $pursuitTestSource -notmatch 'AgentQuestAcceptanceResult\.json' -or $pursuitTestSource -notmatch 'QuestStarted' -or $pursuitTestSource -notmatch 'issueOfferRequested' -or $pursuitTestSource -notmatch 'issue-offer-returned-without-quest-option') { throw 'Quest acceptance coverage must select the live native quest branch, avoid retrying an unavailable Issue offer, and verify a Quest state transition in a disposable fixture.' }
if ($moveToPointTestSource -notmatch 'moveToPoint' -or $moveToPointTestSource -notmatch 'AgentMoveToPointResult\.json' -or $moveToPointTestSource -notmatch 'ArrivedWithinTolerance' -or $moveToPointTestSource -notmatch 'InvalidOutOfRangeDestination' -or $moveToPointTestSource -notmatch 'FixtureUnchanged' -or $moveToPointTestSource -notmatch 'ProcessStopped') { throw 'Free-point movement requires an independent disposable fixture test for native target result, arrival, invalid coordinate safety, and cleanup.' }
if ($freshCampaignTelemetry -notmatch 'Campaign\.Current\?\.CampaignBehaviorManager\?\.GetBehavior<ChronicleCampaignBehavior>\(\)' -or $freshCampaignTelemetry -notmatch 'campaign-agent-behavior-rebound' -or $freshCampaignTelemetry -notmatch 'AgentProtocolReady' -or $freshCampaignTelemetry -match 'fresh-progression-app-tick|fresh-progression-map-tick' -or $protocolSource -notmatch 'fresh-progression-protocol-command-visible' -or $freshCampaignTest -notmatch 'CHRONICLE_FRESH_CAMPAIGN_SKIP_ISSUE_PROBE') { throw 'Progression must skip the native Issue probe without app-tick polling before a campaign exists.' }
if ($subModuleSource -notmatch 'isFreshCampaignHarness && !_freshCampaignMusicReadyLogged && !IsNativeCampaignMusicInitialized\(\)' -or
    $subModuleSource -notmatch 'if \(isFreshCampaignHarness && !_freshCampaignMusicReadyLogged\)' -or
    $subModuleSource -notmatch 'if \(!skipProgressionIssueProbe \|\| storyModeProgressionHarness\) FreshCampaignHarness\.AdvanceCharacterCreation\(\)' -or
    $subModuleSource -notmatch 'fresh-storymode-app-state-transition-probe' -or
    $subModuleSource -notmatch 'private static bool IsPersistentStoryModeSeedHarness\(\)' -or
    $subModuleSource -notmatch 'harnessMode == "agent-host-lifecycle-test"' -or
    $subModuleSource -notmatch 'if \(!IsPersistentStoryModeSeedHarness\(\)' -or
    $subModuleSource -notmatch 'unavailable-.*exception\.GetType\(\)\.Name' -or
    $subModuleSource -match 'Settlement\.CurrentSettlement' -or
    $freshCampaignTest -notmatch 'storyModeTutorialSkipConfirmedAt\.AddSeconds\(180\)' -or
    $freshCampaignTest -notmatch 'storyModeAgentHostStartRequestedAt\.AddSeconds\(90\)' -or
    $freshCampaignTest -notmatch 'if \(\$StoryModeEycLiveModelEvaluation -and \$storyModeMapSettledObserved -and \$storyModeVideoCapture -and \$storyModeVideoCaptureActive\)' -or
    $freshCampaignTest -notmatch 'capture-end-after-map-settled' -or
    $freshCampaignTest -notmatch 'StoryModeStartupFailure') { throw 'Fresh StoryMode startup must preserve post-skip observation, record state-source transitions and fail quickly when the Native takeover/Host handshake never starts.' }
if ($freshCampaignSource -notmatch 'CHRONICLE_HARNESS_MODE' -or $freshCampaignSource -notmatch 'OnNarrativeMenuOptionSelected' -or $freshCampaignSource -notmatch 'adulthood_defeated_enemy_option' -or $freshCampaignSource -notmatch 'manager\.NextStage\(\)' -or $freshCampaignSource -notmatch 'CanUserSkip' -or $freshCampaignSource -notmatch 'OnVideoFinished\(\)' -or $freshCampaignSource -notmatch 'CampaignMapConversation.OpenConversation' -or $freshCampaignSource -notmatch 'hero_give_issue' -or $freshCampaignSource -notmatch 'issueOfferDenied' -or $freshCampaignSource -notmatch 'lord_meet_player_response1' -or $freshCampaignSource -notmatch 'issue_explanation_player_response_pre_quest_solution') { throw 'Fresh campaign test must exercise native creation and classify local Issue offer/precondition outcomes.' }
if ($freshCampaignSource -notmatch 'StoryModeNewGame' -or
    $freshCampaignSource -notmatch 'GetInitialStateOptions\(\)' -or
    $freshCampaignSource -notmatch 'OnExecutedInitialStateOption\(storyModeOption\)' -or
    $freshCampaignSource -notmatch 'storyModeOption\.DoAction\(\)' -or
    $freshCampaignSource -notmatch 'player_answer_skip_tutorial' -or
    $freshCampaignSource -notmatch 'end_tutorial_yes' -or
    $freshCampaignSource -notmatch 'manager\.DoOption\(requiredOptionId\)' -or
    $freshCampaignSource -match 'CompleteTutorialPhase\(' -or
    $freshCampaignSource -notmatch 'fresh-storymode-e2e-ready' -or
    $freshCampaignSource -notmatch 'fresh-storymode-post-skip-map-ready' -or
    $freshCampaignSource -notmatch 'fresh-storymode-post-skip-map-settled' -or
    $freshCampaignSource -notmatch 'eyc-map-render-settled' -or
    $freshCampaignSource -notmatch 'CHRONICLE_FRESH_CAMPAIGN_START_AGENT' -or
    $freshCampaignSource -notmatch 'CHRONICLE_HARNESS_MODE", "agent-host-lifecycle-test"' -or
    $freshCampaignSource -notmatch 'TimeSpan\.FromSeconds\(8\)' -or
    $freshCampaignSource -notmatch '_trainingFieldConversationFrameCaptured' -or
    $freshCampaignSource -notmatch '_tutorialSkipOptionFrameCaptured' -or
    $freshCampaignSource -notmatch '_tutorialSkipConfirmationFrameCaptured' -or
    $freshCampaignTest -notmatch '\[switch\]\$StoryModeEycSetup' -or
    $freshCampaignTest -notmatch '\[switch\]\$StoryModeEycLiveModelEvaluation' -or
    $freshCampaignTest -notmatch 'providerEnvironmentNames' -or
    $freshCampaignTest -notmatch 'GetEnvironmentVariable\(\$name,''User''\)' -or
    $freshCampaignTest -notmatch 'CHRONICLE_LLM_API_KEY' -or
    $freshCampaignTest -notmatch 'https' -or
    $freshCampaignTest -notmatch '/models' -or
    $freshCampaignTest -notmatch 'Configured model ID is absent from the remote provider catalog' -or
    $freshCampaignTest -notmatch 'providerApiKey' -or
    $freshCampaignTest -notmatch 'DeepSeekRunCostLimitCny' -or
    $freshCampaignTest -notmatch 'StoryModeAgentHostStarted' -or
    $freshCampaignTest -notmatch 'StoryModeOriginalEstablishYourClanCompleted' -or
    $freshCampaignTest -notmatch '\$storyModeHostReceipt\.status -eq ''completed'' -and' -or
    $freshCampaignTest -notmatch '\$storyModeHostReceipt\.termination\.goalVerified -eq \$true' -or
    $freshCampaignTest -notmatch 'StoryModeAgentProgressPath' -or
    $freshCampaignTest -notmatch 'Initialize-FreeLLMAPIProfile' -or
    $freshCampaignTest -notmatch 'storyModeLiveProviderPreflightReady' -or
    $freshCampaignTest -notmatch 'StoryModeModelProviderProfile' -or
    $freshCampaignTest -notmatch 'Remote provider read-only /models preflight failed' -or
    $freshCampaignTest -notmatch 'cleanupDeadline = \(Get-Date\)\.AddSeconds\(15\)' -or
    $freshCampaignTest -notmatch 'CHRONICLE_FRESH_CAMPAIGN_STORYMODE' -or
    $freshCampaignTest -notmatch '\$diagnosticStartLineCount = \$allLines\.Count' -or
    $freshCampaignTest -notmatch 'originalEstablishYourClanQuestNaturallyActive' -or
    $freshCampaignTest -notmatch 'StoryModeFirstMapStateObserved' -or
    $freshCampaignTest -notmatch 'storyModeTakeoverMapReady' -or
    $harnessScript -notmatch "'FreshStoryModeSetup' \{ @\('Preflight', 'Build', 'FreshStoryModeSetup'\) \}" -or
    $harnessScript -notmatch "-StoryModeEycSetup -TimeoutSeconds 360" -or
    $harnessScript -notmatch "'FreshStoryModeModelEvaluation' \{ @\('Preflight', 'Build', 'Smoke', 'AgentHostPackage', 'FreshStoryModeModelEvaluation'\) \}" -or
    $harnessScript -notmatch '-StoryModeEycLiveModelEvaluation -TimeoutSeconds 7500' -or
    $harnessScript -notmatch "CHRONICLE_HARNESS_AGENT_AUTO_STOP_AFTER_MS', '7200000'" -or
    $harnessScript -notmatch "CHRONICLE_LLM_TIMEOUT_SECONDS', '300'" -or
    $agentHostRuntimeControllerSource -notmatch 'autoStopMilliseconds <= 7200000' -or
    $harnessScript -notmatch "ValidateSet\('deepseek-flash','gpt-oss-20b','openai-gpt-oss-20b','nvidiallama-3.2-11b-vision','poolside-laguna-s-2.1','free-router','gemini-2.5-flash','mistral-nemo','mistral-small-3.2-24b','qwen3.6-27b','auto:reliable'\)" -or
    $harnessScript -notmatch 'CHRONICLE_HARNESS_AGENT_MODEL.*\$FreshStoryModeModel' -or
    $agentHostRuntimeControllerSource -notmatch 'CHRONICLE_HARNESS_AGENT_MODEL' -or
    $agentHostCampaignLoopSource -notmatch 'HasPostTutorialTrainingFieldMap' -or
    $agentHostCampaignLoopSource -notmatch 'supportedEstablishYourClanGoal' -or
    $agentHostEstablishClanAutonomySource -notmatch 'AgentHostStoryModeBootstrapLoop.RunAsync' -or
    $agentHostStoryModeBootstrapLoopSource -notmatch 'ExecuteTrainingFieldMenuSelectAsync' -or
    $agentHostStoryModeBootstrapLoopSource -notmatch 'storymode-bootstrap-model-selects-native-leave' -or
    $agentHostStoryModeBootstrapLoopSource -notmatch 'storymode-training-field-leave-works-when-eyc-is-already-active' -or
    $agentHostStoryModeBootstrapLoopSource -notmatch 'HasLeftTrainingField' -or
    $agentHostEstablishClanAutonomySource -notmatch 'AgentHostStoryModeBootstrapLoop.IsEligibleTrainingFieldBootstrapState\(initialState.RootElement\)' -or
    $agentHostEstablishClanAutonomySource -notmatch 'companion-model-stopped' -or
    $agentHostEstablishClanAutonomySource -notmatch 'establish-clan-autonomy-safe-no-goods-and-companion-recruitment-stops-mark-route-unavailable-and-allow-replan' -or
    $freshCampaignSource -notmatch '_storyModeAgentAutostartArmed' -or
    $freshCampaignSource -notmatch 'if \(_storyModeAgentAutostartArmed\) return' -or
    $freshCampaignTest -notmatch 'storyModeLiveModelProducedDecision' -or
    $freshCampaignTest -notmatch 'storyModeLiveNativeActionExecuted' -or
    $freshCampaignTest -notmatch 'StoryModeAgentNativeActionsExecuted' -or
    $freshCampaignTest -notmatch 'AgentHostLifecycleHostReceipt\.json' -or
    $freshCampaignTest -notmatch 'AgentHostProgress\.jsonl') { throw 'Fresh StoryMode setup must use the original StoryMode Campaign and exact skip-tutorial/confirmation dialogue choices, verify natural EYC activation, and never call the tutorial completion function directly; its optional live Host slice must use bounded same-session MCM startup with a real decision trace.' }
if ($harnessScript -notmatch "'PersistentEycCampaign' \{ @\('Preflight', 'Build', 'Smoke', 'AgentHostPackage', 'PersistentEycCampaign'\) \}" -or
    [regex]::Matches($harnessScript, "(?m)^        'PersistentEycCampaign' \{").Count -ne 1 -or
    $harnessScript -match "'All' \{[^\r\n]*'PersistentEycCampaign'" -or
    $freshCampaignTest -notmatch '\[switch\]\$StoryModeEycPersistentSeed' -or
    $freshCampaignTest -notmatch 'CHRONICLE_FRESH_CAMPAIGN_SAVE_READY_FILE' -or
    $freshCampaignTest -notmatch 'fresh-campaign-disposable-save-time-check' -or
    $freshCampaignTest -match "Invoke-FreshCampaignAgentCli 'save'" -or
    $freshCampaignTest -notmatch 'PersistentStoryModeSaveRetained' -or
    $subModuleSource -notmatch 'TrySavePersistentStoryModeSeedOnReadyMap' -or
    $subModuleSource -notmatch 'PersistentStoryModeReadyMapTick' -or
    $subModuleSource -notmatch 'Game.Current\?\.GameStateManager\?\.ActiveState is not MapState' -or
    $subModuleSource -notmatch 'ChronicleInquiryAdapter.IsInquiryOpen' -or
    $subModuleSource -notmatch 'campaignDayBefore=' -or
    $subModuleSource -notmatch 'timeControlModeAfter=' -or
    $agentLiveModelLoopSource -notmatch '\[string\]\$CheckpointSaveName' -or
    $agentLiveModelLoopSource -notmatch 'stable Native Campaign Map or a safe non-sieged settlement menu' -or
    $agentLiveModelLoopSource -notmatch 'CheckpointSaveHash' -or
    $persistentEycCampaignSource -notmatch 'campaignInstanceId' -or
    $persistentEycCampaignSource -notmatch 'Get-Sha256' -or
    $persistentEycCampaignSource -notmatch 'Get-VerifiedOrphanSeedReceipt' -or
    $persistentEycCampaignSource -notmatch 'Get-AgentHostProgressUsage' -or
    $persistentEycCampaignSource -notmatch 'Get-VerifiedCampaignProgressUsage' -or
    $persistentEycCampaignSource -notmatch 'usageMetric = ''AgentHostProgress.jsonl provider-decision events''' -or
    $persistentEycCampaignSource -notmatch '\$manifest \| Add-Member -NotePropertyName usageMetric' -or
    $persistentEycCampaignSource -notmatch 'FreshCampaignResult\.json' -or
    $persistentEycCampaignSource -notmatch 'LiveModelLoopResult\.json' -or
    $persistentEycCampaignSource -notmatch 'no unique matching Native SaveAs/hash/process-cleanup receipt' -or
    $persistentEycCampaignSource -notmatch '\$liveRunActualCost = \[double\]\$liveUsage\.CostEstimateCny' -or
    $persistentEycCampaignSource -notmatch 'cumulativeProviderActualCostEstimateCny = \[double\]\$Usage\.CostEstimateCny' -or
    $persistentEycCampaignSource -notmatch 'Remove-ObsoleteOwnedSaves' -or
    $persistentEycCampaignSource -notmatch '-StoryModeEycLiveModelEvaluation' -or
    $persistentEycCampaignSource -notmatch "CHRONICLE_HARNESS_AGENT_AUTO_START','1'" -or
    $persistentEycCampaignSource -notmatch 'FreshStoryModeHostTimeoutSeconds = 7500' -or
    $agentLiveModelLoopSource -notmatch 'checkpointEncounterIsStableSettlementMenu' -or
    $agentLiveModelLoopSource -notmatch 'native-settlement-menu' -or
    $agentLiveModelLoopSource -notmatch 'CheckpointSaveStateDisposition = \$checkpointSaveStateDisposition' -or
    $agentLiveModelLoopSource -notmatch 'underSiege' -or
    $agentHostEstablishClanAutonomySource -notmatch 'safeSettlementRefreshVisitedIds' -or
    $agentHostEstablishClanAutonomySource -notmatch 'excludedSettlementIds' -or
    $agentHostCampaignLoopSource -notmatch 'previously-visited' -or
    $persistentEycCampaignSource -notmatch 'cumulativeProviderActualCostEstimateCny' -or
    $persistentEycCampaignSource -notmatch 'no verified Native checkpoint') {
    throw 'Persistent EYC Harness must seed from natural StoryMode, resume only a hash- and Campaign-ID-matched Native save, checkpoint from a stable map or verified non-sieged settlement menu, bound save retention and retain cumulative run-cost evidence.'
}
if ($harnessScript -notmatch "'FreshStoryModeNativeMenuLeaveEvaluation' \{ @\('Preflight', 'Build', 'FreshStoryModeNativeMenuLeaveEvaluation'\) \}" -or
    $harnessScript -notmatch '-StoryModeNativeMenuLeaveEvaluation -TimeoutSeconds 360' -or
    $freshCampaignTest -notmatch '\[switch\]\$StoryModeNativeMenuLeaveEvaluation' -or
    $freshCampaignTest -notmatch 'StoryModeNativeMenuLeaveVerified' -or
    $freshCampaignTest -notmatch 'StoryModeNativeMenuLeaveInquiryOpenAfter' -or
    $freshCampaignTest -notmatch 'storyModeNativeLeavePostActionSnapshot\.context\.inquiryOpen' -or
    $freshCampaignTest -notmatch 'storyModeNativeLeavePostActionSnapshot\.context\.inquiry' -or
    $freshCampaignTest -notmatch 'Select-Object supported,kind,title,text,affirmative,negative,timerShown,pauseGameActiveState' -or
    $freshCampaignTest -notmatch 'StoryModeNativeMenuLeaveInquiry = \$storyModeNativeLeaveInquiryForSummary' -or
    $freshCampaignTest -match 'storyModeNativeLeavePostActionSnapshot\.state\.context\.inquiry' -or
    $freshCampaignTest -notmatch 'training-field-menu-exited' -or
    $freshCampaignSource -notmatch 'RunMenuOptionConsequence\(menuContext, leaveIndex\)' -or
    $freshCampaignSource -notmatch 'fresh-storymode-native-menu-leave-snapshot\|json=' -or
    $freshCampaignSource -notmatch 'training_field_leave' -or
    $freshCampaignSource -notmatch 'MissionScreen missionScreen && missionScreen\.IsConversationActive' -or
    $freshCampaignSource -notmatch 'conversation-ui-ended-manager-still-active' -or
    $freshCampaignSource -notmatch 'post-confirmation-dialogue-remained-active-after-8-native-continues') { throw 'The opt-in fresh StoryMode Native-menu test must wait for the visible conversation UI to end, use the bounded Native Tab fallback only when that UI is gone, then verify the map/menu/clock/Quest and preserve evidence without saving.' }
if ($agentHostCompanionLoopSource -notmatch 'BuildControlCatalog\(gameState == "MapState"' -or
    $agentHostCompanionLoopSource -notmatch 'private static JsonArray BuildControlCatalog\(bool allowStop' -or
    $agentHostCompanionLoopSource -notmatch 'if \(allowStop\) controls\.Add\("stop"\)' -or
    $agentHostCompanionLoopSource -notmatch 'establish-clan-companion-mission-stop-did-not-recover-to-map' -or
    $agentHostCompanionLoopSource -notmatch 'decisionFeedback = AgentHostProviderDecisionRecovery\.BuildFeedback' -or
    $agentHostCompanionLoopSource -notmatch 'ReadBoolean\(decision\.Decision, "stop"\)' -or
    $agentHostDecisionCycleSource -notmatch 'var prompt = EstablishClanCompanionSystemPrompt' -or
    $agentHostDecisionCycleSource -notmatch 'RECOVERY DIRECTIVE' -or
    $agentHostCompanionLoopSource -notmatch 'establish-clan-companion-listed-safe-stop-is-interrupted-with-zero-native-actions' -or
    $agentHostProviderSource -notmatch 'ContainsString\(request, "allowedControls", "stop"\)' -or
    $agentHostProviderContractSelfTestSource -notmatch 'provider-normalizes-only-workflow-listed-safe-stop-control') { throw 'The Companion may stop only on free Map; Mission stop requests must be corrected against the current Native catalog, and only the original Native missionLeave may return it to Map for parent replanning.' }
if ($agentHostCompanionLoopSource -notmatch 'ReadConversation\(state\)' -or
    $agentHostCompanionLoopSource -notmatch 'state\?\["context"\]\?\["conversation"\]' -or
    $agentHostCompanionLoopSource -notmatch 'establish-clan-companion-native-conversation-shape-failed' -or
    $agentHostCompanionLoopSource -notmatch 'TryReadListedInteger' -or
    $agentHostCompanionLoopSource -notmatch 'establish-clan-companion-current-catalog-integer-normalization-failed' -or
    $agentHostCompanionLoopSource -notmatch 'establish-clan-companion-out-of-catalog-formatted-index-accepted') { throw 'Companion integer arguments may be format-normalized only when the canonical numeric value is present in the fresh Native candidate catalog; formatted out-of-catalog values must remain rejected.' }
if ($agentHostCompanionLoopSource -notmatch 'var journalTargetMet = ReadBoolean\(companionObjective, "met"\)' -or
    $agentHostCompanionLoopSource -notmatch 'journalTargetMet && gameState != "MissionState"' -or
    $agentHostCompanionLoopSource -notmatch 'journalTargetMet && gameState == "MissionState"' -or
    $agentHostCompanionLoopSource -notmatch '"dialogueSelect", "missionLeave"' -or
    $agentHostCompanionLoopSource -notmatch 'case "missionLeave": _stage = 9') { throw 'Companion completion must close its Native Tavern Mission with the original Leave Area action before the parent selects its next campaign objective.' }
if ($agentHostCompanionLoopSource -notmatch 'player_is_leaving_neutral_or_friendly' -or
    $agentHostCompanionLoopSource -notmatch 'currentConversationHeroDeclined' -or
    $agentHostCompanionLoopSource -notmatch 'establish-clan-companion-declined-wanderer-exit-not-gated' -or
    $agentHostDecisionCycleSource -notmatch 'After declining, if the same Wanderer asks' -or
    $agentHostDecisionCycleSource -notmatch 'Do not decline only to preserve Gold for the separate Gold objective') { throw 'A declined Wanderer quote must expose the current Native conversation exit and prevent reopening that same hire offer; an enabled affordable offer should advance the unmet Companion objective instead of preserving Gold without a concrete constraint.' }
if ($agentHostCompanionLoopSource -notmatch 'establish-clan-companion-unlisted-navigation-duration-feedback-failed' -or
    $agentHostCompanionLoopSource -notmatch 'AgentIndex \[\{allowedIndexes\}\]' -or
    $agentHostCompanionLoopSource -notmatch 'DurationSeconds \[\{allowedDurationValues\}\]' -or
    $agentHostDecisionCycleSource -notmatch 'DurationSeconds pair without interpolation') { throw 'An unlisted Tavern navigation lease must be rejected before Native execution with the exact current AgentIndex and DurationSeconds values for a bounded correction.' }
if ($agentHostCampaignLoopEvaluationSource -notmatch 'Initialize-ChronicleCampaignLoopProviderProfile' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'CHRONICLE_LLM_BASE_URL' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'ProviderBaseUrl' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'configured-openai-compatible-provider' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'priorProviderEnvironment' -or
    $agentHostLiveModelLoopSource -notmatch 'configured provider model-list preflight' -or
    $agentHostLiveModelLoopSource -notmatch 'isFreeLlmApi') { throw 'Campaign loop evaluations must use the configured provider-neutral OpenAI-compatible profile, health-check the configured model, and restore inherited process environment values without writing API keys to the model profile.' }
if ($agentHostEstablishClanPlannerSource -notmatch 'objective-selection-rejected-before-native' -or
    $agentHostEstablishClanPlannerSource -notmatch 'allowed ObjectiveId values are exactly' -or
    $agentHostDecisionCycleSource -notmatch 'Treat the current allowedActions list as exact' -or
    $agentHostEstablishClanPlannerSource -notmatch 'establish-clan-objective-invalid-choice-correction-failed' -or
    $agentHostEstablishClanAutonomySource -notmatch 'objective-planner-failed') { throw 'The EYC planner must make at most one correction for an objective omitted from the current allowed catalog, preserve the request/evidence counts, and fail explicitly only after the bounded correction.' }
if ($harnessScript -notmatch "'FreshStoryModeNativeInquiryResponseEvaluation' \{ @\('Preflight', 'Build', 'FreshStoryModeNativeInquiryResponseEvaluation'\) \}" -or
    $harnessScript -notmatch '-StoryModeNativeMenuLeaveEvaluation -StoryModeNativeInquiryResponseEvaluation' -or
    $freshCampaignTest -notmatch '\[switch\]\$StoryModeNativeInquiryResponseEvaluation' -or
    $freshCampaignTest -notmatch 'respondInquiry' -or
    $freshCampaignTest -notmatch '\[IO\.FileMode\]::CreateNew' -or
    $freshCampaignTest -notmatch 'harnessNativeOnly = \$true' -or
    $freshCampaignTest -notmatch 'StoryModeNativeInquiryTestSessionCreated' -or
    $freshCampaignTest -notmatch 'Remove-Item -LiteralPath \$agentSessionPath' -or
    $freshCampaignTest -notmatch 'ExecuteAffirmativeAction' -or
    $freshCampaignTest -notmatch 'inquiry\.affirmative\.visible' -or
    $freshCampaignTest -notmatch 'inquiry\.affirmative\.enabled' -or
    $freshCampaignTest -notmatch 'inquiry\.negative\.visible' -or
    $freshCampaignTest -notmatch 'storyModeNativeInquiryClosedAfterResponse' -or
    $freshCampaignTest -notmatch 'StoryModeNativeInquiryKeptCampaignDayAndStop' -or
    $freshCampaignTest -notmatch '\[redacted-token\]') { throw 'The fresh StoryMode Native Inquiry integration phase must answer only the observed enabled affirmative button, use the production respondInquiry bridge, verify the modal closed with EYC/time unchanged, and keep its one-use token out of summaries.' }
if ($harnessScript -notmatch 'function Remove-RetainedAgentHostPackage' -or
    $harnessScript -notmatch 'CHRONICLE_AGENT_HOST_TEST_PATH' -or
    $harnessScript -notmatch 'Remove-RetainedAgentHostPackage \$script:retainedAgentHostPackageRoot' -or
    $harnessScript -notmatch 'retainPackageForSameSessionRuntime = \$Phase -in @\(''FreshStoryModeModelEvaluation'', ''PersistentEycCampaign'', ''AgentHostLifecycleEvaluation'', ''AgentHostLifecycleCompletionEvaluation''\)' -or
    $harnessScript -notmatch 'finally \{[\s\S]*?Remove-RetainedAgentHostPackage \$script:retainedAgentHostPackageRoot[\s\S]*?AgentHostLifecycleEvaluation' -or
    $harnessScript -notmatch 'Test-AgentHostPackage\.ps1' -or $harnessScript -notmatch '-CleanupPackageRoot' -or
    $agentHostPackageSource -notmatch 'Cleanup-only mode refuses while a Bannerlord or Agent Host process may still use the package') { throw 'Same-session MCM runtime testing must use the verified self-contained D: package artifact and remove only its unique temporary folder after game/Host processes are gone.' }
if ($freshCampaignTest -notmatch 'FreshStoryModeSetup\.mp4' -or
    $freshCampaignTest -notmatch 'FreshStoryModeSetup-contact\.jpg' -or
    $freshCampaignTest -notmatch 'Write-StoryModeCaptureEvent' -or
    $freshCampaignTest -notmatch 'StoryModeNativeFramesPassed' -or
    $freshCampaignTest -notmatch 'Bannerlord\.BLSE\.Standalone\.exe' -or
    $freshCampaignTest -notmatch 'Ensure-ChronicleSteamClientReady' -or
    $freshCampaignTest -notmatch 'StoryModeNativeFrameSha256' -or
    $freshCampaignTest -notmatch 'distinctRequiredFrameHashes\.Count -eq \$requiredNativeFrames\.Count' -or
    $freshCampaignTest -notmatch 'Get-FileHash -LiteralPath \$finalFramePath -Algorithm SHA256' -or
    $freshCampaignTest -notmatch 'tutorial-skip-confirmation-visible' -or
    $freshCampaignTest -notmatch 'eyc-map-render-settled' -or
    $freshCampaignTest -notmatch 'storyModeRenderSettledObserved' -or
    $freshCampaignSource -notmatch 'TaleWorlds\.Engine\.Utilities\.TakeScreenshot' -or
    $freshCampaignTest -notmatch "Get-Process -Name 'Bannerlord\*'") { throw 'Fresh StoryMode UI setup evidence must stay window-scoped, mark tutorial/EYC transitions in its timeline, and handle the installed BLSE process name.' }
if ($freshCampaignTelemetry -notmatch 'ChronicleAgentObserver.BuildSnapshotJson') { throw 'FreshCampaign must capture the post-creation Agent snapshot.' }
if ($freshCampaignTelemetry -notmatch 'Campaign\.Current\.SaveHandler\.SaveAs\(freshSaveName\)' -or $freshCampaignTelemetry -notmatch 'fresh-campaign-disposable-save-scheduled' -or $freshCampaignTelemetry -notmatch 'fresh-campaign-disposable-save-requested' -or $freshCampaignTelemetry -notmatch 'fresh-campaign-disposable-save-complete' -or $freshCampaignTelemetry -notmatch 'via=CampaignTick' -or $freshCampaignTelemetry -notmatch 'fresh-campaign-progression-campaign-tick' -or $freshCampaignTelemetry -notmatch '_agentProtocol\?\.Poll\(this\)') { throw 'FreshCampaign must save the stopped fresh campaign on its first native CampaignTick and observe completion.' }
if ($freshCampaignTelemetry -notmatch 'IsNativeCampaignMusicInitialized' -or $freshCampaignTelemetry -notmatch 'MBMusicManager\.IsCreationCompleted\(\)' -or $freshCampaignTelemetry -notmatch 'fresh-campaign-start-wait' -or $freshCampaignTelemetry -notmatch 'fresh-campaign-start-ready' -or $freshCampaignTelemetry -notmatch 'skipProgressionIssueProbe' -or $freshCampaignTelemetry -notmatch 'GetType\(\)\.Name == "MapState"') { throw 'FreshCampaign must wait for native music initialization and suppress only the progression Issue probe after MapState.' }
if ($protocolTestSource -notmatch 'NewGuid\(\)' -or $protocolTestSource -notmatch 'Disposable protocol save path escaped Game Saves' -or $protocolTestSource -notmatch 'ProtocolSaveCleaned' -or $protocolTestSource -notmatch 'Remove-ProtocolSaveFixture' -or $protocolTestSource -notmatch 'Get-PersistedCampaignFingerprint' -or $protocolTestSource -notmatch 'PersistentCampaignStateMatchesAfterProcessRestart' -or $protocolTestSource -notmatch 'TargetPositionX' -or $protocolTestSource -notmatch 'TargetPositionY' -or $protocolTestSource -notmatch 'reloadedState\.timeControlMode -eq ''Stop''') { throw 'Protocol save/reload tests must compare a structured Campaign fingerprint, including an active point-navigation target when present, across separate processes; assert native Stop restoration and safely clean a unique disposable save.' }
if ($agentProtocolSource -notmatch 'case "pause":\s*WriteResponse\(commandId, action, "completed", behavior, null, SetNativeTimeSpeed\(0\)\)' -or $agentProtocolSource -notmatch 'case "resume":\s*WriteResponse\(commandId, action, "completed", behavior, null, SetNativeTimeSpeed\(1\)\)' -or $agentProtocolSource -notmatch 'case "fastForward":\s*WriteResponse\(commandId, action, "completed", behavior, null, SetNativeTimeSpeed\(2\)\)' -or $agentProtocolSource -notmatch 'campaign\.SetTimeSpeed\(selectedTimeSpeed\)' -or $agentCliSource -notmatch "Invoke-ProtocolCommand 'fastForward'" -or $protocolTestSource -notmatch "Invoke-AgentCli 'fastForward'" -or $protocolTestSource -notmatch 'FastForwardStop') { throw 'Agent pause/play/fast-forward must map to the Native Campaign.SetTimeSpeed modes, remain distinct from Harness advance, and pass CLI/protocol checks.' }
$pursuitTestSource = Get-Content (Join-Path $harnessRoot 'Test-AgentPursuit.ps1') -Raw -Encoding UTF8
$pursuitFixtureSource = Get-Content (Join-Path $harnessRoot 'HarnessPursuitFixture.cs') -Raw -Encoding UTF8
if ($harnessScript -notmatch "'EngageVisibility'" -or $harnessScript -notmatch '\$pursuitScript -ProbeEngageVisibilityLoss' -or $harnessScript -notmatch 'TimeoutSeconds 240' -or $harnessScript -notmatch '\$testOutput' -or $pursuitTestSource -notmatch 'pursuitVisibilitySetupPause' -or $pursuitTestSource -notmatch 'TargetVisibleMapMarker' -or $pursuitTestSource -notmatch 'IsMainPartyWaiting' -or $pursuitTestSource -notmatch 'DaysElapsedAfterTargetLoss' -or $pursuitTestSource -notmatch 'StableHoldScreenshot' -or $pursuitTestSource -notmatch 'CampaignClockStoppedAfterTargetLoss' -or $pursuitTestSource -notmatch 'native-visible-map-marker-lost' -or $pursuitTestSource -notmatch 'engage-encounter-before-target-loss\.bmp' -or $pursuitTestSource -notmatch 'engage-target-initial-map\.bmp' -or $pursuitTestSource -notmatch 'captureFrame' -or $protocolSource -notmatch 'harnessPreparePursuitVisibilityFixture' -or $protocolSource -notmatch 'visual Harness run' -or $agentCliSource -notmatch "Invoke-ProtocolCommand 'harnessPreparePursuitVisibilityFixture'" -or $pursuitFixtureSource -notmatch 'BanditPartyComponent\.CreateLooterParty' -or $pursuitFixtureSource -notmatch 'BasicTroop' -or $pursuitFixtureSource -match '\.IsVisible\s*=') { throw 'Engage visibility research must use an explicit setup clock action, visual-Harness-only Native party fixture reachable through the CLI, IsMainPartyWaiting/stable-hold sampling, pre-action/transition screenshots, and separate raw time mode from effective Campaign pause.' }
if ($freshCampaignSource -match 'SaveAs\(|SaveGame\(') { throw 'Fresh campaign renown test must not create a save.' }
$freshCampaignTestCompact = $freshCampaignTest -replace '\s+', ' '
$decisionLoopSource = Get-Content (Join-Path $harnessRoot 'Agent-DecisionLoop.ps1') -Raw -Encoding UTF8
$agentLoopTest = Get-Content (Join-Path $harnessRoot 'Test-AgentLoop.ps1') -Raw -Encoding UTF8
$agentLoopProviderSource = Get-Content (Join-Path $harnessRoot 'Test-AgentLoopProvider.ps1') -Raw -Encoding UTF8
if ($agentLoopProviderSource -notmatch 'ConfirmPartySizeWarning' -or $agentLoopProviderSource -notmatch 'partyCapacity') { throw 'The deterministic decision Provider must derive the volunteer over-limit confirmation from the current Native recruitment receipt.' }
$movementTestSource = Get-Content (Join-Path $harnessRoot 'Test-AgentMovement.ps1') -Raw -Encoding UTF8
$holdTestSource = Get-Content (Join-Path $harnessRoot 'Test-AgentHold.ps1') -Raw -Encoding UTF8
if ($decisionLoopSource -notmatch "moveToPoint = @\('X','Y','Surface'\)" -or $agentLoopProviderSource -notmatch "CHRONICLE_TEST_PROVIDER_MODE -eq 'point'" -or $agentLoopProviderSource -notmatch "action = 'moveToPoint'") { throw 'The Agent decision loop must permit a provider to request the free-point moveToPoint action; its movement result is covered by the dedicated movement phase.' }
if ($decisionLoopSource -notmatch 'fastForward = @\(\)' -or $agentLoopProviderSource -notmatch "CHRONICLE_TEST_PROVIDER_MODE -eq 'timeModes'" -or $agentLoopProviderSource -notmatch "3 \{ 'pause' \}" -or $agentLoopProviderSource -notmatch "CHRONICLE_TEST_PROVIDER_MODE -eq 'waitingResume'" -or $agentLoopTest -notmatch '\$TimeControlOnly' -or $agentLoopTest -notmatch 'NativeTimeControlActionsRouted' -or $agentLoopTest -notmatch 'PlayModeNaturallyAdvancedBeforeFastForwardSelection' -or $agentLoopTest -notmatch 'FastForwardNaturallyAdvanced' -or $agentLoopTest -notmatch 'PauseHeldCampaignDay' -or $agentLoopTest -notmatch 'WaitingHoldThenResumeAdvancedNaturally' -or $harnessScript -notmatch "'TimeControlLoop'" -or $developmentDoc -notmatch 'TimeControlLoop') { throw 'Native time controls must verify Play/FastForward/Pause and Hold-waiting resume through their own bounded decision-loop phase, separate from the read-only AgentLoop and Harness-only advance.' }
if ($harnessScript -notmatch 'Agent decision loop test failed with exit code \$testExitCode' -or $harnessScript -notmatch '\$testOutput = & powershell .*\$agentLoopScript 2>&1 \| Out-String') { throw 'AgentLoop failures must preserve the child test output in the owning Harness run receipt.' }
if ($harnessScript -notmatch '\$buildOutput = & dotnet build .*2>&1 \| Out-String' -or $harnessScript -notmatch 'Build failed with exit code \$buildExitCode') { throw 'Build failures must retain the compiler diagnostic output in the owning Harness run receipt.' }
if (-not $harnessScript.Contains("agentHostBuildOutput -match 'NU1900'") -or
    -not $harnessScript.Contains("GetAttribute('Include') -ceq 'Microsoft.ML.Tokenizers'") -or
    -not $harnessScript.Contains("GetAttribute('Version') -ceq '[2.0.1]'") -or
    -not $harnessScript.Contains('--locked-mode') -or
    -not $harnessScript.Contains('NuGetAudit=false') -or
    -not $harnessScript.Contains('nugetAuditFallbackUsed')) { throw 'Harness Build may bypass NuGet vulnerability metadata only for the single pinned Host dependency, with locked restore and an explicit receipt.' }
if ($harnessScript -notmatch 'Agent movement test failed with exit code \$testExitCode' -or $harnessScript -notmatch '\$testOutput = & powershell .*\$movementScript 2>&1 \| Out-String') { throw 'Movement failures must preserve the child test output in the owning Harness run receipt.' }
if ($harnessScript -notmatch 'Agent recruitment test failed with exit code \$testExitCode' -or $harnessScript -notmatch '\$testOutput = & powershell .*\$recruitmentScript 2>&1 \| Out-String') { throw 'Recruitment failures must preserve the child test output in the owning Harness run receipt.' }
if ($movementTestSource -notmatch 'mapSettlementTargets' -or $movementTestSource -notmatch 'TargetSource = ''mapSettlementTargets''' -or $movementTestSource -notmatch 'Capture-HarnessFailureFrame' -or $movementTestSource -notmatch 'reuse it instead of issuing a second identical read' -or $movementTestSource -notmatch 'not currently exposed as a visible Campaign map target') { throw 'Movement regression must navigate from Native visible-marker observations, reuse the arrival receipt, capture an in-engine last frame when possible, and match the current hidden/missing target rejection boundary.' }
if ($harnessScript -notmatch "'Hold' \{ @\('Preflight', 'Build', 'Hold'\) \}" -or $harnessScript -notmatch "'Hold' \{\s+Invoke-Stage -Name 'Hold'" -or $developmentDoc -notmatch '\| Hold \|' -or $holdTestSource -notmatch "Invoke-AgentCli 'move'" -or $holdTestSource -notmatch "Invoke-AgentCli 'hold'" -or $holdTestSource -notmatch 'NaturalObservationSeconds' -or $holdTestSource -notmatch 'CampaignDayDeltaWhileWaiting' -or $holdTestSource -notmatch 'MovementStoppedAfterNaturalWindow' -or $holdTestSource -notmatch 'StoppableModeWaitingAtHold' -or $holdTestSource -match "Invoke-AgentCli 'advance'|Invoke-AgentCli 'pause'|Invoke-AgentCli 'resume'") { throw 'Hold must independently test moving→native Hold, stable stop, and a natural clock-command-free observation window.' }
if ($agentLoopProviderSource -notmatch 'OpenStandardInput\(\)' -or $agentLoopProviderSource -notmatch 'System\.Text\.Encoding\]::UTF8' -or $agentLoopProviderSource -notmatch 'StreamReader' -or $agentLoopProviderSource -notmatch '\$requestJson\.IndexOf\(''\{''\)') { throw 'The AgentLoop provider boundary must read raw standard input as UTF-8 with BOM detection and reject non-encoding data before the JSON object.' }
$agentLoopProvider = Get-Content (Join-Path $harnessRoot 'Test-AgentLoopProvider.ps1') -Raw -Encoding UTF8
if ($decisionLoopSource -notmatch 'previousActionReceipt' -or $agentLoopTest -notmatch 'PreviousActionReceiptForwarded' -or $agentLoopProvider -notmatch 'previous Native receipt') { throw 'The next Agent decision must receive and test the preceding native action receipt, while safe pre-Native rejection feedback remains separately observable.' }
if ($decisionLoopSource -notmatch 'decision\.done -eq \$true' -or $decisionLoopSource -notmatch 'completedByProvider = \$true' -or $decisionLoopSource -notmatch 'decision-budget-exhausted' -or $agentLoopProviderSource -notmatch "CHRONICLE_TEST_PROVIDER_MODE -eq 'doneSignal'" -or $agentLoopTest -notmatch 'ExplicitGoalStopHonoredWithoutIssuingAnotherAction') { throw 'The decision loop must support an explicit, reasoned provider stop without executing another game action, and distinguish that request from verified goal success.' }
$recruitmentTest = Get-Content (Join-Path $harnessRoot 'Test-AgentRecruitment.ps1') -Raw -Encoding UTF8
if ($agentLoopProvider -notmatch "CHRONICLE_TEST_PROVIDER_MODE -eq 'recruitment'" -or $agentLoopProvider -notmatch '\$request\.previousActionReceipt' -or $agentLoopProvider -notmatch '\$receipt\.data\.offers' -or $recruitmentTest -notmatch 'OfferDataForwardedToNextDecision' -or $recruitmentTest -notmatch 'OfferSelectionMatchedReceipt' -or $recruitmentTest -notmatch 'RecruitmentDecisionSummary' -or $recruitmentTest -match 'RecruitmentDecisionTrace\s*=\s*\$recruitmentLoop\.trace') { throw 'Recruitment must test receipt-based selection and keep only concise evidence, not duplicate full observations.' }
if ($freshCampaignTest -notmatch 'Set-ChronicleTestWindow' -or $freshCampaignTest -notmatch 'WindowLayoutApplied' -or $freshCampaignTest -notmatch 'display_width' -or $freshCampaignTest -notmatch '840') { throw 'FreshCampaign must enforce the existing non-activating windowed test layout.' }
if ($testWindowLayoutSource -notmatch 'IsIconic' -or $testWindowLayoutSource -notmatch 'IsWindowVisible' -or $testWindowLayoutSource -notmatch '0x0050' -or $testWindowLayoutSource -notmatch 'Minimized = \$iconic' -or $testWindowLayoutSource -match 'SetForegroundWindow|BringWindowToTop') { throw 'Windowed capture must show the 840x472 game window without activating it or stealing the user focus.' }
if ($agentCliSource -notmatch "'recoverTestConfig'" -or $testWindowLayoutSource -notmatch "max_framerate = 30" -or $agentCliSource -notmatch 'engine_config\.chronicle-backup' -or $agentCliSource -notmatch 'Restore-ChronicleTestEngineConfig' -or $agentCliSource -notmatch 'engineConfigRestored' -or $agentCliSource -notmatch 'startup-timeout-' -or $agentCliSource -notmatch 'RglErrorLogTail' -or $agentCliSource -notmatch 'WatchdogLogTail' -or $agentCliSource -notmatch 'Ensure-ChronicleSteamClient' -or $startupEvidenceSource -notmatch 'steamwebhelper' -or $startupEvidenceSource -notmatch 'Get-ChronicleSteamClientReadiness' -or $startupEvidenceSource -notmatch 'Bannerlord was not launched' -or $agentCliSource -notmatch 'ConvertTo-ChronicleStartupDialogEvidence' -or $agentCliSource -notmatch 'StreamReader') { throw 'Harness must wait for stable Steam WebHelper readiness, serialize sanitized startup dialog evidence, and preserve Steam API warnings without global input.' }
if ($freshCampaignTest -notmatch 'FreshCampaign\.initial-state\.json' -or $freshCampaignTest -notmatch 'WriteAllBytes' -or $freshCampaignTest -notmatch 'creationCompleted -and \$initialSnapshotCaptured') { throw 'FreshCampaign must persist the post-creation Agent observation as UTF-8 evidence before passing.' }
if ($freshCampaignTest -notmatch 'IssueConversationProbeApplicable' -or $freshCampaignTest -notmatch 'IssueConversationProbeSkipped' -or $freshCampaignTestCompact -notmatch 'issueConversationProbePassed = if \(\$issueProbeExpected\).*?\$null' -or $freshCampaignTest -notmatch 'issueConversationProbeOutcomeValid' -or $freshCampaignTest -notmatch 'issueConversationOfferDenied' -or $freshCampaignTest -notmatch 'issueOfferOptionAvailable') { throw 'FreshCampaign must distinguish an applicable offer/denial from a no-issue skip.' }
if ($freshCampaignTest -notmatch 'ValidateRecruitmentProgression' -or $freshCampaignTest -notmatch 'CHRONICLE_FRESH_CAMPAIGN_SAVE_NAME' -or $freshCampaignTest -notmatch 'disposableSaveCompleted' -or $freshCampaignTest -notmatch 'disposable save' -or $freshCampaignTest -notmatch 'Agent CLI could not load the fresh-created disposable save' -or $freshCampaignTest -notmatch 'Wait-ForAgentSettlementArrival' -or $freshCampaignTest -notmatch 'Crash Report' -or $freshCampaignTest -notmatch 'Math\]::Min\(15, \$TimeoutSeconds\)' -or $freshCampaignTest -notmatch 'save cleanup path escaped Game Saves' -or $freshCampaignTest -notmatch 'activeGameProcess\.MainWindowTitle' -or $freshCampaignTelemetry -match 'fresh-campaign-progression-clock') { throw 'Fresh progression must keep the clock stopped and save from the first CampaignTick.' }
if ($freshCampaignTest -notmatch "Test-AgentSupport\.ps1" -or $freshCampaignTest -notmatch 'Wait-ForAgentSettlementArrival') { throw 'FreshCampaign progression must import the shared arrival helper it invokes.' }
if ($freshCampaignTest -notmatch 'Get-Content -LiteralPath \$diagnosticLog -Encoding UTF8') { throw 'FreshCampaign must read diagnostic telemetry as UTF-8 to preserve localized JSON strings.' }
if ($freshCampaignTest -notmatch 'Start-ChronicleWindowVideoCapture' -or $freshCampaignTest -notmatch 'Stop-ChronicleWindowVideoCapture' -or $freshCampaignTest -notmatch 'CrashReport-\$bannerlordPid\.mp4' -or $freshCampaignTest -notmatch 'crashCaptureGraceActive' -or $freshCampaignTest -notmatch 'CrashWindowCaptureVideoRetained' -or $freshCampaignTest -notmatch 'action = ''crashReport''' -or $freshCampaignTest -notmatch 'crashObserved' -or $videoCaptureSource -notmatch '''crashObserved''' -or $freshCampaignTest -match 'UIAutomationClient|ExpandCollapsePattern|PostMouseWheel|crashReportScroll') { throw 'FreshCampaign must retain crash-window visual evidence without brittle report-window UI automation.' }
if ($freshCampaignTest -notmatch 'CrashFaultAddress' -or $freshCampaignTest -notmatch 'CrashFaultModule' -or $freshCampaignTest -notmatch 'ModuleMemorySize' -or $freshCampaignTest -notmatch 'CrashModuleInventory' -or $harnessScript -notmatch 'crashModuleInventory = \$testResult\.CrashModuleInventory') { throw 'Crash evidence must map the native fault IP against the live process module address ranges.' }
if ($harnessScript -notmatch "Get-Process -Name 'Bannerlord\*'" -or $harnessScript -notmatch 'Refusing to build or deploy ChronicleFramework while a Bannerlord client is running' -or $harnessScript -notmatch 'Harness will not stop a live client or overwrite its loaded DLL') { throw 'Build must refuse to deploy while a Bannerlord client is already running, without terminating that client or replacing its loaded module.' }
if ($freshCampaignTest -notmatch 'CHRONICLE_CAPTURE_CRASH_EXCEPTION' -or $freshCampaignTest -notmatch 'CrashExceptionCaptured' -or $harnessScript -notmatch 'crashExceptionPath = \[string\]\$testResult\.CrashExceptionPath' -or $freshCampaignTelemetry -notmatch 'ExceptionReporter' -or $freshCampaignTelemetry -notmatch 'CaptureCrashExceptionBeforeReport' -or $freshCampaignTelemetry -notmatch 'exception\.ToString\(\)' -or $freshCampaignTelemetry -notmatch 'DescribeCampaignMusicContext' -or $projectFile -notmatch '0Harmony\.dll') { throw 'Crash reports must capture ButterLib exception and CampaignMusic context in-process, without UI automation.' }
if ($freshCampaignTest -notmatch 'Start-ChronicleWindowVideoCapture' -or $freshCampaignTest -notmatch 'Stop-ChronicleWindowVideoCapture' -or $freshCampaignTest -notmatch 'CrashReport-\$bannerlordPid\.mp4' -or $freshCampaignTest -notmatch 'crashCaptureGraceActive' -or $freshCampaignTest -notmatch 'CrashWindowCaptureError') { throw 'FreshCampaign must capture an actual crash-report window into keyframe evidence before cleanup.' }
if ($harnessVideoCaptureSource -notmatch '\$frameDuration\s*=\s*1\.0\s*/' -or $harnessVideoCaptureSource -notmatch 'format=yuvj420p') { throw 'Video event-frame extraction must clamp timestamps to an actual frame and explicitly encode JPEG-compatible full-range pixels.' }
if ($freshCampaignTelemetry -notmatch 'fresh-campaign-visible-issues' -or $freshCampaignTest -notmatch 'VisibleIssueTypesBySettlement') { throw 'FreshCampaign must record local issue types for route research.' }
if ($freshCampaignTelemetry -notmatch 'FreshCampaignHarness\.ProbeLocalIssueConversation') { throw 'FreshCampaign must probe the local native issue dialogue after character creation.' }
foreach ($requiredHeading in @('## 判断原则', '## 单一工作循环', '## 事实归属与资料读取')) {
    if ($rootAgents -notmatch [regex]::Escape($requiredHeading)) { throw "AGENTS.md is missing the unified method section '$requiredHeading'." }
}
if ($rootAgents -notmatch '最多推进一项' -or $rootAgents -notmatch 'Harness 不调用 GitHub' -or $rootAgents -notmatch '高影响未知未解决前不猜着实现') { throw 'AGENTS.md must preserve single-task execution, source ownership, and consequential-unknown handling.' }
if ($developmentDoc -notmatch '研究就绪门槛' -or $harnessScript -notmatch 'Get-ChronicleResearchReadiness' -or -not (Test-Path -LiteralPath $researchReadinessScript)) { throw 'Research readiness rules must be documented and enforced before building changed game C# sources.' }
$approvedDiagnosticHash = [regex]::Match($researchReadinessSource, "AuditedHarnessDiagnosticSha256 = '([0-9a-f]{64})'")
$actualDiagnosticHash = Get-ChronicleCanonicalFileSha256 -LiteralPath (Join-Path $harnessRoot 'SubModule.cs')
if (-not $approvedDiagnosticHash.Success -or $approvedDiagnosticHash.Groups[1].Value -ne $actualDiagnosticHash) { throw 'The exact-hash reviewed SubModule baseline must match the source.' }
if ($contextFocusSource -notmatch 'Get-ChronicleCanonicalFileSha256' -or $harnessScript -notmatch 'Get-ChronicleCanonicalFileSha256' -or $researchReadinessSource -notmatch 'Canonical source hashing must treat LF and CRLF') { throw 'Source-content hashing must normalize line endings consistently in the readiness gate, context updater, and Docs regression checks.' }
if ($mainlineDoc -notmatch '(?m)^Research Gate: \*\*(BLOCKED|READY)\*\*' -or $mainlineDoc -notmatch '(?m)^Implementation Gate: \*\*(BLOCKED|READY)\*\*' -or $mainlineDoc -notmatch '行为总分母：\*\*(UNKNOWN|[1-9]\d*)\*\*' -or $mainlineDoc -notmatch 'SYSTEM_INVENTORY' -or $mainlineDoc -notmatch '126') { throw 'MAINLINE must expose gate status and distinguish the game-system inventory from the player-behavior denominator.' }
if ([string]::IsNullOrWhiteSpace($taskTrackerUrl) -or $taskTrackerUrl -notmatch '^https://github\.com/users/[^/]+/projects/\d+$' -or @($contextState.taskTracker.PSObject.Properties.Name).Count -ne 1) { throw 'ContextState must store only one GitHub Project locator, without duplicated task metadata.' }
if ($mainlineDoc -match '(?m)^\| Behavior-interface census \|' -or $mainlineDoc -match '\b0/12 domains\b' -or $mainlineDoc -match '\[W1-A.*Issue #\d+') { throw 'MAINLINE must not mirror live GitHub work-item or domain-completion status.' }
if ($mainlineDoc -match '(?m)^Research Gate: \*\*READY\*\*' -and $mainlineDoc -match '行为总分母：\*\*UNKNOWN\*\*') { throw 'Research cannot be marked READY while the behavior denominator is unknown.' }
if ($mainlineDoc -match '(?m)^Implementation Gate: \*\*READY\*\*' -and $mainlineDoc -notmatch '(?m)^Research Gate: \*\*READY\*\*') { throw 'Implementation cannot be READY before the research gate.' }
$inventoryIds = @([regex]::Matches($inventoryDoc, '(?m)^\|\s*([A-L]\d{2})\s*\|') | ForEach-Object { $_.Groups[1].Value })
$inventoryDomainLetters = @($inventoryIds | ForEach-Object { $_.Substring(0, 1) } | Sort-Object -Unique)
$inventoryCountInFocus = [regex]::Match($mainlineDoc, 'SYSTEM_INVENTORY\.md.*?(\d+)项')
if ($inventoryIds.Count -eq 0 -or @($inventoryIds | Sort-Object -Unique).Count -ne $inventoryIds.Count -or ($inventoryDomainLetters -join '') -ne 'ABCDEFGHIJKL' -or -not $inventoryCountInFocus.Success -or [int]$inventoryCountInFocus.Groups[1].Value -ne $inventoryIds.Count) { throw 'SYSTEM_INVENTORY item IDs, A-L coverage, or the derived count in MAINLINE do not agree.' }
$catalogIdDefinitions = @([regex]::Matches($inventoryDoc, '(?m)^\|\s*((?:OBS|ACT|N/A)-[A-L]\d{2}-\d{2})\s*\|') | ForEach-Object { $_.Groups[1].Value })
$duplicateCatalogIds = @($catalogIdDefinitions | Group-Object | Where-Object { $_.Count -gt 1 })
$catalogIdSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($catalogId in $catalogIdDefinitions) { [void]$catalogIdSet.Add($catalogId) }
$catalogIdReferences = @([regex]::Matches($inventoryDoc, '(?:OBS|ACT|N/A)-[A-L]\d{2}-\d{2}') | ForEach-Object { $_.Value } | Sort-Object -Unique)
$undefinedCatalogIds = @($catalogIdReferences | Where-Object { -not $catalogIdSet.Contains($_) })
$catalogDefinitionLines = @([regex]::Matches($inventoryDoc, '(?m)^\|\s*(?:OBS|ACT|N/A)-[A-L]\d{2}-\d{2}\s*\|[^\r\n]*') | ForEach-Object { $_.Value })
$catalogMappedSystemIds = @([regex]::Matches(($catalogDefinitionLines -join "`n"), '\b[A-L]\d{2}\b') | ForEach-Object { $_.Value } | Sort-Object -Unique)
$unmappedSystemIds = @($inventoryIds | Where-Object { $_ -notin $catalogMappedSystemIds })
if ($catalogIdDefinitions.Count -eq 0 -or $duplicateCatalogIds.Count -gt 0 -or $undefinedCatalogIds.Count -gt 0) {
    throw "SYSTEM_INVENTORY observation/action IDs must be unique and every reference defined. Duplicate=[$($duplicateCatalogIds.Name -join ',')], undefined=[$($undefinedCatalogIds -join ',')]."
}
$catalogActionRows = @($catalogIdDefinitions | Where-Object { $_.StartsWith('ACT-', [System.StringComparison]::Ordinal) }).Count
$privilegedActionRows = @($catalogDefinitionLines | Where-Object { $_ -match '特权扩展，不计核心分母' }).Count
$coreActionRows = $catalogActionRows - $privilegedActionRows
$mainlineActionTotal = [regex]::Match($mainlineDoc, '当前目录含(\d+)条ACT')
$mainlineCoreDenominator = [regex]::Match($mainlineDoc, '标准行动族分母为(\d+)')
$mainlineBehaviorDenominator = [regex]::Match($mainlineDoc, '(?m)^行为总分母：\*\*(\d+)\*\*')
if (-not $mainlineActionTotal.Success -or -not $mainlineCoreDenominator.Success -or -not $mainlineBehaviorDenominator.Success -or [int]$mainlineActionTotal.Groups[1].Value -ne $catalogActionRows -or [int]$mainlineCoreDenominator.Groups[1].Value -ne $coreActionRows -or [int]$mainlineBehaviorDenominator.Groups[1].Value -ne $coreActionRows) {
    throw "Player-action denominator in MAINLINE does not match unique catalog IDs/privilege classifications: catalog ACT=$catalogActionRows, privileged ACT=$privilegedActionRows, core ACT=$coreActionRows."
}
if ($unmappedSystemIds.Count -gt 0) {
    throw "SYSTEM_INVENTORY A-L systems must appear in at least one explicit OBS/ACT/N/A directory row. Unmapped=[$($unmappedSystemIds -join ',')]."
}
$catalogSourceSystemIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$catalogSourceErrors = @()
foreach ($line in $catalogDefinitionLines) {
    $columns = $line.Trim('|').Split('|')
    $catalogId = $columns[0].Trim()
    $sourceColumn = $columns[-1]
    $sourceIds = @([regex]::Matches($sourceColumn, '(?<![A-Z])[A-L]\d{2}(?!\d)') | ForEach-Object { $_.Value } | Sort-Object -Unique)
    if ($sourceIds.Count -eq 0) {
        $catalogSourceErrors += "$catalogId has no A-L source-system citation"
        continue
    }
    foreach ($sourceId in $sourceIds) {
        if ($sourceId -notin $inventoryIds) {
            $catalogSourceErrors += "$catalogId cites undefined system $sourceId"
            continue
        }
        [void]$catalogSourceSystemIds.Add($sourceId)
    }
}
$uncitedSourceSystemIds = @($inventoryIds | Where-Object { -not $catalogSourceSystemIds.Contains($_) })
if ($catalogSourceErrors.Count -gt 0 -or $uncitedSourceSystemIds.Count -gt 0) {
    throw "SYSTEM_INVENTORY directory source columns must cite defined A-L systems and collectively cover all 126 systems. Errors=[$($catalogSourceErrors -join '; ')], Uncited=[$($uncitedSourceSystemIds -join ',')]."
}
if (-not (Test-ChronicleResearchReadiness)) { throw 'Research readiness gate regression checks failed.' }
if ($mainlineDoc -notmatch '(?m)^#### .*Mechanic Contract\s*$') { throw 'MAINLINE.md is missing the required original-mechanic contract table.' }
if ($mainlineDoc -notmatch '(?m)^#### .*Coverage and Evidence Contract') { throw 'MAINLINE.md must define durable denominator/acceptance rules without storing current task progress.' }
foreach ($actionId in @('moveToPoint（自由地点移动，陆地）', 'move', 'pursue', 'follow / escort', 'hold', 'rest', 'advance', 'ACT-G01-02 send troops / native BattleSimulation（W2-X）', 'dialogueSelect / dialogueContinue', 'retreat (research)', 'ACT-G10-01 battle loot items / take all and commit（新目录项；W2-X）', 'ACT-H04-03 settlement volunteer recruitment / `recruitOptions` + `recruit`')) {
    if ($mainlineDoc -notmatch "(?m)^\|\s*$([regex]::Escape($actionId))\s*\|") {
        throw "MAINLINE.md mechanic-contract table is missing action '$actionId'."
    }
}
foreach ($requiredText in @('Confirmed optimization list', 'No confirmed features')) {
    if ($designDoc -notmatch [regex]::Escape($requiredText)) {
        throw "DESIGN.md is missing required design element '$requiredText'."
    }
}
foreach ($reference in $contextState.references) {
    $requiredText = ([string]$reference.path).Replace('\', '/')
    if ($inventoryDoc -notmatch [regex]::Escape($requiredText)) {
        throw "SYSTEM_INVENTORY.md does not route to '$requiredText'."
    }
}
$mainlineHash = Get-ChronicleCanonicalFileSha256 -LiteralPath $mainlinePath
if ($contextState.current.mainlineSha256 -ne $mainlineHash) { throw 'Focus/MAINLINE.md hash is stale; run Set-ContextFocus.ps1 -Review.' }
$reviewAfter = [DateTime]::Parse($contextState.current.reviewAfterUtc).ToUniversalTime()
if ($reviewAfter -lt [DateTime]::UtcNow) { throw "Current focus review is overdue: $($contextState.current.reviewAfterUtc)." }
if ([int]$contextState.schemaVersion -ne 2) { throw 'ContextState must use router-only schema version 2.' }
if ([string]::IsNullOrWhiteSpace([string]$contextState.current.path) -or [string]::IsNullOrWhiteSpace([string]$contextState.current.reviewedUtc) -or [string]::IsNullOrWhiteSpace([string]$contextState.current.reviewAfterUtc) -or [string]::IsNullOrWhiteSpace([string]$contextState.current.mainlineSha256)) { throw 'ContextState current may contain only a valid focus pointer and review/hash metadata.' }
if (@($contextState.current.PSObject.Properties.Name | Where-Object { $_ -in @('id', 'objective', 'phase', 'updatedUtc') }).Count -gt 0) { throw 'ContextState must not duplicate project/task objective, phase, or live status.' }
[string[]]$expectedDefaultRead = @('DEVELOPMENT.md', 'Focus/MAINLINE.md')
if (($contextState.defaultRead -join '|') -ne ($expectedDefaultRead -join '|')) { throw 'Default context is limited to the engineering contract and active technical focus; load design/inventory/research on demand.' }
[string]$defaultMainline = $contextState.defaultRead | Where-Object { $_ -eq [string]$contextState.current.path }
if (-not $defaultMainline) { throw 'Current focus is not in defaultRead.' }
if (@($contextState.defaultRead | Where-Object { $_ -like 'Archive/*' }).Count -gt 0) { throw 'Archive content cannot be in defaultRead.' }

[pscustomobject]@{
    Passed = $true
    ContractVersion = $contractVersion
    MarkdownFiles = $activeFiles.Count
    ArchiveFiles = @($actualFiles | Where-Object { $_.FullName -like '*\Archive\*' }).Count
    CatalogSystemRows = $inventoryIds.Count
    CatalogMappedSystemRows = $catalogMappedSystemIds.Count
    CatalogActionRows = @($catalogIdDefinitions | Where-Object { $_.StartsWith('ACT-', [System.StringComparison]::Ordinal) }).Count
    CatalogObservationRows = @($catalogIdDefinitions | Where-Object { $_.StartsWith('OBS-', [System.StringComparison]::Ordinal) }).Count
    CatalogNARows = @($catalogIdDefinitions | Where-Object { $_.StartsWith('N/A-', [System.StringComparison]::Ordinal) }).Count
    MarkdownBytes = $totalBytes
    DefaultReadMarkdownBytes = $defaultReadBytes
    TaskTrackerUrl = $taskTrackerUrl
    CheckedUtc = (Get-Date).ToUniversalTime().ToString('O')
} | ConvertTo-Json
