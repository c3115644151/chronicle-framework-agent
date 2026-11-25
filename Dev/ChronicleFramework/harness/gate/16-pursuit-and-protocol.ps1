#Requires -Version 7.0

# Pursuit and protocol: move to point, protocol save/reload fingerprints, natural StoryMode live-model runs.
# Sources asserted here: Test-AgentPursuit.ps1, Test-AgentMoveToPoint.ps1, Test-AgentProtocol.ps1, Test-AgentPersistentStoryModeCampaign.ps1

$pursuitTestSource = Get-Content (Join-Path $stageRoot 'Test-AgentPursuit.ps1') -Raw -Encoding UTF8
$moveToPointTestSource = Get-Content (Join-Path $stageRoot 'Test-AgentMoveToPoint.ps1') -Raw -Encoding UTF8
$protocolTestSource = Get-Content (Join-Path $stageRoot 'Test-AgentProtocol.ps1') -Raw -Encoding UTF8
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
    $harnessScript -notmatch "'FreshStoryModeModelEvaluation' \{ @\('Preflight', 'ConfiguredModelPreflight', 'Build', 'Smoke', 'AgentHostPackage', 'FreshStoryModeModelEvaluation'\) \}" -or
    $harnessScript -notmatch '-StoryModeEycLiveModelEvaluation -TimeoutSeconds 87000' -or
    $harnessScript -notmatch "CHRONICLE_HARNESS_AGENT_AUTO_STOP_AFTER_MS.*, '86400000'" -or
    $harnessScript -notmatch "CHRONICLE_LLM_TIMEOUT_SECONDS', '300'" -or
    $agentHostRuntimeControllerSource -notmatch 'autoStopMilliseconds <= 86400000' -or
    $harnessScript -match '\[ValidateSet\([^\r\n]*\)\]\[string\]\$FreshStoryModeModel' -or
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
    $freshCampaignTest -notmatch 'TestAgentUsageTraceSummary' -or
    $freshCampaignTest -notmatch 'Measure-StoryModeAgentUsageFromTrace' -or
    $freshCampaignTest -notmatch 'AllDecisionCostRowsPresent' -or
    $freshCampaignTest -notmatch 'harness-provider-decision-trace' -or
    $freshCampaignTest -notmatch 'StoryModeAgentHostReceiptCaptured' -or
    $freshCampaignTest -notmatch 'StoryModeAgentProviderDecisionCostsComplete' -or
    $freshCampaignTest -notmatch 'StoryModeAgentNativeActionTraceObserved' -or
    $freshCampaignTest -notmatch 'AgentHostLifecycleHostReceipt\.json' -or
    $freshCampaignTest -notmatch 'AgentHostProgress\.jsonl') { throw 'Fresh StoryMode setup must use the original StoryMode Campaign and exact skip-tutorial/confirmation dialogue choices, verify natural EYC activation, and never call the tutorial completion function directly; its optional live Host slice must use bounded same-session MCM startup with a real decision trace.' }
if ($harnessScript -notmatch "'PersistentEycCampaign' \{ @\('Preflight', 'ConfiguredModelPreflight', 'Build', 'AgentHostPackage', 'PersistentEycCampaign'\) \}" -or
    [regex]::Matches($harnessScript, "(?m)^Invoke-Stage -Name 'PersistentEycCampaign' -Action \{").Count -ne 1 -or
    $harnessScript -match "'All' \{[^\r\n]*'PersistentEycCampaign'" -or
    $harnessScript -notmatch '\[ValidatePattern\(''\^\(\[A-Za-z0-9_\-\]\{1,8\}\)\?\$''\)\]\[string\]\$PersistentEycCampaignKey' -or
    -not $harnessScript.Contains('-CampaignKey $PersistentEycCampaignKey') -or
    $persistentEycCampaignSource -notmatch 'PersistentEycCampaign' -or
    $persistentEycCampaignSource -notmatch 'ChronicleEycDev-' -or
    $persistentEycCampaignSource -notmatch 'manifestCampaignKey' -or
    $persistentEycCampaignSource -notmatch 'campaignKey = \$CampaignKey' -or
    -not $persistentEycCampaignSource.Contains("'-StoryModeEycSetup','-StoryModeEycPersistentSeed'") -or
    $persistentEycCampaignSource -match "'-StoryModeEycSetup','-StoryModeEycLiveModelEvaluation','-StoryModeEycPersistentSeed'" -or
    $persistentEycCampaignSource -notmatch "CHRONICLE_HARNESS_AGENT_AUTO_START','0'" -or
    $persistentEycCampaignSource -notmatch 'if \(-not \$eycCompleted\)' -or
    $freshCampaignTest -notmatch '\[switch\]\$StoryModeEycPersistentSeed' -or
    $freshCampaignTest -notmatch 'CHRONICLE_FRESH_CAMPAIGN_SAVE_READY_FILE' -or
    $freshCampaignTest -notmatch 'persistentStoryModeSaveReadySignaled' -or
    $freshCampaignTest -notmatch '\$creationReady -and \$storyModeEycReadyObserved' -or
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
    $agentLiveModelLoopSource -notmatch 'function Get-NativeCheckpointStateDisposition' -or
    $agentLiveModelLoopSource -notmatch 'town_backstreet_back' -or
    $agentLiveModelLoopSource -notmatch 'Test-NativeCheckpointStateContract' -or
    $persistentEycCampaignSource -notmatch 'campaignInstanceId' -or
    $persistentEycCampaignSource -notmatch 'Get-Sha256' -or
    $persistentEycCampaignSource -notmatch 'Get-VerifiedOrphanSeedReceipt' -or
    $persistentEycCampaignSource -notmatch 'Get-AgentHostProgressUsage' -or
    $persistentEycCampaignSource -notmatch 'Get-VerifiedCampaignProgressUsage' -or
    $persistentEycCampaignSource -notmatch 'usageMetric = ''AgentHostProgress.jsonl provider decisions plus failed response token usage; price coverage tracked separately''' -or
    $persistentEycCampaignSource -notmatch 'providerResponsePromptTokens' -or
    $persistentEycCampaignSource -notmatch 'cumulativeFailedPromptTokens' -or
    $persistentEycCampaignSource -notmatch 'CostEstimateCompleteThisRun' -or
    $persistentEycCampaignSource -notmatch 'Get-VerifiedCheckpointProviderFailureUsage' -or
    $persistentEycCampaignSource -notmatch 'UsageSelfTest' -or
    $persistentEycCampaignSource -notmatch '\$manifest \| Add-Member -NotePropertyName usageMetric' -or
    $persistentEycCampaignSource -notmatch 'FreshCampaignResult\.json' -or
    $persistentEycCampaignSource -notmatch 'LiveModelLoopResult\.json' -or
    $persistentEycCampaignSource -notmatch 'no unique matching Native SaveAs/hash/process-cleanup receipt' -or
    $persistentEycCampaignSource -notmatch '\$liveRunActualCost = \[double\]\$liveUsage\.CostEstimateCny' -or
    $persistentEycCampaignSource -notmatch 'cumulativeProviderActualCostEstimateCny = \[double\]\$Usage\.CostEstimateCny' -or
    $persistentEycCampaignSource -notmatch 'Remove-ObsoleteOwnedSaves' -or
    $persistentEycCampaignSource -notmatch "CHRONICLE_HARNESS_AGENT_AUTO_START','0'" -or
    $persistentEycCampaignSource -notmatch "'-StoryModeEycSetup','-StoryModeEycPersistentSeed'" -or
    $persistentEycCampaignSource -match "'-StoryModeEycSetup','-StoryModeEycLiveModelEvaluation','-StoryModeEycPersistentSeed'" -or
    $persistentEycCampaignSource -notmatch 'if \(-not \$eycCompleted\)' -or
    $persistentEycCampaignSource -notmatch 'FreshStoryModeHostTimeoutSeconds = 87000' -or
    $agentLiveModelLoopSource -notmatch '\[ValidateRange\(60,86400\)\]\[int\]\$HostMaxElapsedSeconds = 86400' -or
    -not $persistentEycCampaignSource.Contains("'-HostMaxElapsedSeconds',[string]`$HostMaxElapsedSeconds") -or
    $agentLiveModelLoopSource -notmatch 'native-settlement-menu' -or
    $agentLiveModelLoopSource -notmatch 'CheckpointSaveStateDisposition = \$checkpointSaveStateDisposition' -or
    $agentLiveModelLoopSource -notmatch 'function Get-NativeCheckpointStateDisposition' -or
    $agentLiveModelLoopSource -notmatch 'function Test-NativeCheckpointStateContract' -or
    $agentLiveModelLoopSource -notmatch 'town_backstreet_back' -or
    $agentLiveModelLoopSource -notmatch 'missionStateRejected' -or
    $agentLiveModelLoopSource -notmatch 'siegeRejected' -or
    $agentLiveModelLoopSource -notmatch 'underSiege' -or
    $agentHostEstablishClanAutonomySource -notmatch 'safeSettlementRefreshVisitedIds' -or
    $agentHostEstablishClanAutonomySource -notmatch 'excludedSettlementIds' -or
    $agentHostCampaignLoopSource -notmatch 'previously-visited' -or
    $persistentEycCampaignSource -notmatch 'cumulativeProviderActualCostEstimateCny' -or
    $persistentEycCampaignSource -notmatch 'no verified Native checkpoint') {
    throw 'Persistent EYC Harness must seed from natural StoryMode, resume only a hash- and Campaign-ID-matched Native save, checkpoint from a stable map or verified non-sieged settlement menu, bound save retention and retain cumulative run-cost evidence.'
}
$persistentUsageSelfTestOutput = & $HarnessPowerShell -NoProfile -File (Join-Path $stageRoot 'Test-AgentPersistentStoryModeCampaign.ps1') -UsageSelfTest 2>&1 | Out-String
$persistentUsageSelfTest = $null
try { $persistentUsageSelfTest = $persistentUsageSelfTestOutput | ConvertFrom-Json } catch { }
if ($LASTEXITCODE -ne 0 -or -not $persistentUsageSelfTest.passed -or
    $persistentUsageSelfTest.failedResponsePromptTokens -ne 1437 -or $persistentUsageSelfTest.failedResponseCompletionTokens -ne 256 -or
    $persistentUsageSelfTest.costEstimateComplete) {
    throw "Persistent EYC usage accounting must include failed provider response tokens and mark unpriced failures incomplete: $persistentUsageSelfTestOutput"
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
    $agentHostDecisionCycleSource -notmatch 'BuildEstablishClanCompanionSystemPrompt\(request\)' -or
    $agentHostDecisionCycleSource -notmatch 'reason <= 8 words' -or
    $agentHostCompanionLoopSource -notmatch 'establish-clan-companion-prompt-stage-projection-failed' -or
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
    $agentHostDecisionCycleSource -notmatch 'If acceptance is absent, do not estimate price or retry the same offer' -or
    $agentHostDecisionCycleSource -notmatch 'use only a safe listed decline/exit') { throw 'A declined Wanderer quote must expose the current Native conversation exit and prevent reopening that same hire offer; an enabled affordable offer should advance the unmet Companion objective instead of preserving Gold without a concrete constraint.' }
if ($agentHostCompanionLoopSource -notmatch 'establish-clan-companion-unlisted-navigation-duration-feedback-failed' -or
    $agentHostCompanionLoopSource -notmatch 'AgentIndex \[\{allowedIndexes\}\]' -or
    $agentHostCompanionLoopSource -notmatch 'DurationSeconds \[\{allowedDurationValues\}\]' -or
    $agentHostDecisionCycleSource -notmatch 'exact listed AgentIndex and DurationSeconds') { throw 'An unlisted Tavern navigation lease must be rejected before Native execution with the exact current AgentIndex and DurationSeconds values for a bounded correction.' }
if ($agentHostCampaignLoopEvaluationSource -notmatch 'Initialize-ChronicleCampaignLoopProviderProfile' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'CHRONICLE_LLM_BASE_URL' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'ProviderBaseUrl' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'configured-openai-compatible-provider' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'priorProviderEnvironment' -or
    $agentHostLiveModelLoopSource -notmatch 'configured provider model-list preflight' -or
    $agentHostLiveModelLoopSource -notmatch 'isFreeLlmApi') { throw 'Campaign loop evaluations must use the configured provider-neutral OpenAI-compatible profile, health-check the configured model, and restore inherited process environment values without writing API keys to the model profile.' }
if ($agentHostEstablishClanPlannerSource -notmatch 'objective-selection-rejected-before-native' -or
    $agentHostEstablishClanPlannerSource -notmatch 'allowed ObjectiveId values are exactly' -or
    $agentHostEstablishClanPlannerSource -notmatch 'EYC-planner-sends-one-compact-journal-snapshot-with-current-native-feasibility' -or
    $agentHostEstablishClanPlannerSource -notmatch 'journalObjectiveSnapshot.*is not null' -or
    $agentHostEstablishClanPlannerSource -notmatch 'Encoding\.UTF8\.GetByteCount\(provider\.FirstRequest\?\.ToJsonString\(\) \?\? string\.Empty\) > 1800' -or
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
    $harnessScript -notmatch 'retainPackageForSameSessionRuntime = \$Phase -in @\(''FreshStoryModeModelEvaluation'', ''PersistentEycCampaign'', ''AgentHostLifecycleEvaluation'', ''AgentHostLifecycleCompletionEvaluation'', ''BattleMissionHostNativeAiAutopilotProbe''\)' -or
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
