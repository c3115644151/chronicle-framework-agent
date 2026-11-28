#Requires -Version 7.0

# Runtime loops: time-speed handlers, decision loop policy, movement, hold, recruitment and window layout.
# Sources asserted here: Test-AgentPursuit.ps1, HarnessPursuitFixture.cs, Agent-DecisionLoop.ps1, Test-AgentLoop.ps1, Test-AgentLoopProvider.ps1, Test-AgentMovement.ps1, Test-AgentHold.ps1, Test-AgentRecruitment.ps1, Test-WindowLayout.ps1, SubModule.cs

if ($protocolTestSource -notmatch 'NewGuid\(\)' -or $protocolTestSource -notmatch 'Disposable protocol save path escaped Game Saves' -or $protocolTestSource -notmatch 'ProtocolSaveCleaned' -or $protocolTestSource -notmatch 'Remove-ProtocolSaveFixture' -or $protocolTestSource -notmatch 'Get-PersistedCampaignFingerprint' -or $protocolTestSource -notmatch 'PersistentCampaignStateMatchesAfterProcessRestart' -or $protocolTestSource -notmatch 'TargetPositionX' -or $protocolTestSource -notmatch 'TargetPositionY' -or $protocolTestSource -notmatch 'reloadedState\.timeControlMode -eq ''Stop''') { throw 'Protocol save/reload tests must compare a structured Campaign fingerprint, including an active point-navigation target when present, across separate processes; assert native Stop restoration and safely clean a unique disposable save.' }
if ($agentProtocolSource -notmatch 'case "pause":\s*HandlePause\(behavior, commandId, action, command\);' -or $agentProtocolSource -notmatch 'case "resume":\s*HandleResume\(behavior, commandId, action, command\);' -or $agentProtocolSource -notmatch 'case "fastForward":\s*HandleFastForward\(behavior, commandId, action, command\);' -or $agentProtocolSource -notmatch 'private void HandlePause\(ChronicleCampaignBehavior behavior, string commandId, string action, string command\)\s*\{\s*WriteResponse\(commandId, action, "completed", behavior, null, SetNativeTimeSpeed\(0\)\);' -or $agentProtocolSource -notmatch 'private void HandleResume\(ChronicleCampaignBehavior behavior, string commandId, string action, string command\)\s*\{\s*WriteResponse\(commandId, action, "completed", behavior, null, SetNativeTimeSpeed\(1\)\);' -or $agentProtocolSource -notmatch 'private void HandleFastForward\(ChronicleCampaignBehavior behavior, string commandId, string action, string command\)\s*\{\s*WriteResponse\(commandId, action, "completed", behavior, null, SetNativeTimeSpeed\(2\)\);' ) { throw 'Agent pause/play/fast-forward must map to the Native Campaign.SetTimeSpeed modes, remain distinct from Harness advance, and pass CLI/protocol checks.' }
$pursuitTestSource = Get-Content (Join-Path $stageRoot 'Test-AgentPursuit.ps1') -Raw -Encoding UTF8
$pursuitFixtureSource = Get-Content (Join-Path $modRoot 'HarnessPursuitFixture.cs') -Raw -Encoding UTF8
if ($harnessScript -notmatch "'EngageVisibility'" -or $harnessScript -notmatch '\$pursuitScript -ProbeEngageVisibilityLoss' -or $harnessScript -notmatch 'TimeoutSeconds 240' -or $harnessScript -notmatch '\$testOutput' -or $pursuitTestSource -notmatch 'pursuitVisibilitySetupPause' -or $pursuitTestSource -notmatch 'TargetVisibleMapMarker' -or $pursuitTestSource -notmatch 'IsMainPartyWaiting' -or $pursuitTestSource -notmatch 'DaysElapsedAfterTargetLoss' -or $pursuitTestSource -notmatch 'StableHoldScreenshot' -or $pursuitTestSource -notmatch 'CampaignClockStoppedAfterTargetLoss' -or $pursuitTestSource -notmatch 'native-visible-map-marker-lost' -or $pursuitTestSource -notmatch 'engage-encounter-before-target-loss\.bmp' -or $pursuitTestSource -notmatch 'engage-target-initial-map\.bmp' -or $pursuitTestSource -notmatch 'captureFrame' -or $protocolSource -notmatch 'harnessPreparePursuitVisibilityFixture' -or $protocolSource -notmatch 'visual Harness run' -or $agentCliSource -notmatch "Invoke-ProtocolCommand 'harnessPreparePursuitVisibilityFixture'" -or $pursuitFixtureSource -notmatch 'BanditPartyComponent\.CreateLooterParty' -or $pursuitFixtureSource -notmatch 'BasicTroop' -or $pursuitFixtureSource -match '\.IsVisible\s*=') { throw 'Engage visibility research must use an explicit setup clock action, visual-Harness-only Native party fixture reachable through the CLI, IsMainPartyWaiting/stable-hold sampling, pre-action/transition screenshots, and separate raw time mode from effective Campaign pause.' }
if ($freshCampaignSource -match 'SaveAs\(|SaveGame\(') { throw 'Fresh campaign renown test must not create a save.' }
$freshCampaignTestCompact = $freshCampaignTest -replace '\s+', ' '
$decisionLoopSource = Get-Content (Join-Path $stageRoot 'Agent-DecisionLoop.ps1') -Raw -Encoding UTF8
$agentLoopTest = Get-Content (Join-Path $stageRoot 'Test-AgentLoop.ps1') -Raw -Encoding UTF8
$agentLoopProviderSource = Get-Content (Join-Path $stageRoot 'Test-AgentLoopProvider.ps1') -Raw -Encoding UTF8
if ($agentLoopProviderSource -notmatch 'ConfirmPartySizeWarning' -or $agentLoopProviderSource -notmatch 'partyCapacity') { throw 'The deterministic decision Provider must derive the volunteer over-limit confirmation from the current Native recruitment receipt.' }
$movementTestSource = Get-Content (Join-Path $stageRoot 'Test-AgentMovement.ps1') -Raw -Encoding UTF8
$holdTestSource = Get-Content (Join-Path $stageRoot 'Test-AgentHold.ps1') -Raw -Encoding UTF8
if ($decisionLoopSource -notmatch "moveToPoint = @\('X','Y','Surface'\)" -or $agentLoopProviderSource -notmatch "CHRONICLE_TEST_PROVIDER_MODE -eq 'point'" -or $agentLoopProviderSource -notmatch "action = 'moveToPoint'") { throw 'The Agent decision loop must permit a provider to request the free-point moveToPoint action; its movement result is covered by the dedicated movement phase.' }
if ($decisionLoopSource -notmatch 'fastForward = @\(\)' -or $agentLoopProviderSource -notmatch "CHRONICLE_TEST_PROVIDER_MODE -eq 'timeModes'" -or $agentLoopProviderSource -notmatch "3 \{ 'pause' \}" -or $agentLoopProviderSource -notmatch "CHRONICLE_TEST_PROVIDER_MODE -eq 'waitingResume'" -or $agentLoopTest -notmatch '\$TimeControlOnly' -or $agentLoopTest -notmatch 'NativeTimeControlActionsRouted' -or $agentLoopTest -notmatch 'PlayModeNaturallyAdvancedBeforeFastForwardSelection' -or $agentLoopTest -notmatch 'FastForwardNaturallyAdvanced' -or $agentLoopTest -notmatch 'PauseHeldCampaignDay' -or $agentLoopTest -notmatch 'WaitingHoldThenResumeAdvancedNaturally' -or $harnessScript -notmatch "'TimeControlLoop'" -or $developmentDoc -notmatch 'TimeControlLoop') { throw 'Native time controls must verify Play/FastForward/Pause and Hold-waiting resume through their own bounded decision-loop phase, separate from the read-only AgentLoop and Harness-only advance.' }
if ($harnessScript -notmatch 'Agent decision loop test failed with exit code \$testExitCode' -or $harnessScript -notmatch '\$testOutput = & \$HarnessPowerShell .*\$agentLoopScript 2>&1 \| Out-String') { throw 'AgentLoop failures must preserve the child test output in the owning Harness run receipt.' }
if ($harnessScript -notmatch '\$buildOutput = & dotnet build .*2>&1 \| Out-String' -or $harnessScript -notmatch 'Build failed with exit code \$buildExitCode') { throw 'Build failures must retain the compiler diagnostic output in the owning Harness run receipt.' }
if (-not $harnessScript.Contains("agentHostBuildOutput -match 'NU1900'") -or
    -not $harnessScript.Contains("GetAttribute('Include') -ceq 'Microsoft.ML.Tokenizers'") -or
    -not $harnessScript.Contains("GetAttribute('Version') -ceq '[2.0.1]'") -or
    -not $harnessScript.Contains('--locked-mode') -or
    -not $harnessScript.Contains('NuGetAudit=false') -or
    -not $harnessScript.Contains('nugetAuditFallbackUsed')) { throw 'Harness Build may bypass NuGet vulnerability metadata only for the single pinned Host dependency, with locked restore and an explicit receipt.' }
if ($harnessScript -notmatch 'Agent movement test failed with exit code \$testExitCode' -or $harnessScript -notmatch '\$testOutput = & \$HarnessPowerShell .*\$movementScript 2>&1 \| Out-String') { throw 'Movement failures must preserve the child test output in the owning Harness run receipt.' }
if ($harnessScript -notmatch 'Agent recruitment test failed with exit code \$testExitCode' -or $harnessScript -notmatch '\$testOutput = & \$HarnessPowerShell .*\$recruitmentScript 2>&1 \| Out-String') { throw 'Recruitment failures must preserve the child test output in the owning Harness run receipt.' }
if ($movementTestSource -notmatch 'mapSettlementTargets' -or $movementTestSource -notmatch 'TargetSource = ''mapSettlementTargets''' -or $movementTestSource -notmatch 'Capture-HarnessFailureFrame' -or $movementTestSource -notmatch 'reuse it instead of issuing a second identical read' -or $movementTestSource -notmatch 'not currently exposed as a visible Campaign map target') { throw 'Movement regression must navigate from Native visible-marker observations, reuse the arrival receipt, capture an in-engine last frame when possible, and match the current hidden/missing target rejection boundary.' }
if ($harnessScript -notmatch "'Hold' \{ @\('Preflight', 'Build', 'Hold'\) \}" -or $harnessScript -notmatch "(?m)^Invoke-Stage -Name 'Hold' -Action \{" -or $developmentDoc -notmatch '\| Hold \|' -or $holdTestSource -notmatch "Invoke-AgentCli 'move'" -or $holdTestSource -notmatch "Invoke-AgentCli 'hold'" -or $holdTestSource -notmatch 'NaturalObservationSeconds' -or $holdTestSource -notmatch 'CampaignDayDeltaWhileWaiting' -or $holdTestSource -notmatch 'MovementStoppedAfterNaturalWindow' -or $holdTestSource -notmatch 'StoppableModeWaitingAtHold' -or $holdTestSource -match "Invoke-AgentCli 'advance'|Invoke-AgentCli 'pause'|Invoke-AgentCli 'resume'") { throw 'Hold must independently test moving→native Hold, stable stop, and a natural clock-command-free observation window.' }
if ($agentLoopProviderSource -notmatch 'OpenStandardInput\(\)' -or $agentLoopProviderSource -notmatch 'System\.Text\.Encoding\]::UTF8' -or $agentLoopProviderSource -notmatch 'StreamReader' -or $agentLoopProviderSource -notmatch '\$requestJson\.IndexOf\(''\{''\)') { throw 'The AgentLoop provider boundary must read raw standard input as UTF-8 with BOM detection and reject non-encoding data before the JSON object.' }
$agentLoopProvider = Get-Content (Join-Path $stageRoot 'Test-AgentLoopProvider.ps1') -Raw -Encoding UTF8
if ($decisionLoopSource -notmatch 'previousActionReceipt' -or $agentLoopTest -notmatch 'PreviousActionReceiptForwarded' -or $agentLoopProvider -notmatch 'previous Native receipt') { throw 'The next Agent decision must receive and test the preceding native action receipt, while safe pre-Native rejection feedback remains separately observable.' }
if ($decisionLoopSource -notmatch 'decision\.done -eq \$true' -or $decisionLoopSource -notmatch 'completedByProvider = \$true' -or $decisionLoopSource -notmatch 'decision-budget-exhausted' -or $agentLoopProviderSource -notmatch "CHRONICLE_TEST_PROVIDER_MODE -eq 'doneSignal'" -or $agentLoopTest -notmatch 'ExplicitGoalStopHonoredWithoutIssuingAnotherAction') { throw 'The decision loop must support an explicit, reasoned provider stop without executing another game action, and distinguish that request from verified goal success.' }
$recruitmentTest = Get-Content (Join-Path $stageRoot 'Test-AgentRecruitment.ps1') -Raw -Encoding UTF8
if ($agentLoopProvider -notmatch "CHRONICLE_TEST_PROVIDER_MODE -eq 'recruitment'" -or $agentLoopProvider -notmatch '\$request\.previousActionReceipt' -or $agentLoopProvider -notmatch '\$receipt\.data\.offers' -or $recruitmentTest -notmatch 'OfferDataForwardedToNextDecision' -or $recruitmentTest -notmatch 'OfferSelectionMatchedReceipt' -or $recruitmentTest -notmatch 'RecruitmentDecisionSummary' -or $recruitmentTest -match 'RecruitmentDecisionTrace\s*=\s*\$recruitmentLoop\.trace') { throw 'Recruitment must test receipt-based selection and keep only concise evidence, not duplicate full observations.' }
if ($freshCampaignTest -notmatch 'Set-ChronicleTestWindow' -or $freshCampaignTest -notmatch 'WindowLayoutApplied' -or $freshCampaignTest -notmatch 'Math\]::Abs\(\$windowLayout\.Width - 840\) -le 1' -or $freshCampaignTest -notmatch 'display_width' -or $freshCampaignTest -notmatch '840') { throw 'FreshCampaign must enforce the existing non-activating windowed test layout within one-pixel window-manager rounding.' }
. (Join-Path $stageRoot 'Test-WindowLayout.ps1')
$cursorClipRestoreContract = Test-ChronicleCursorClipRestoreContract
if (-not (Test-ChronicleNoActivateStyleContract) -or
    -not [bool]$cursorClipRestoreContract.RestoresOnlyTestIntroducedClip -or
    -not [bool]$cursorClipRestoreContract.RefusesWhenGameIsForeground -or
    -not [bool]$cursorClipRestoreContract.RefusesToOverridePreExistingRestriction -or
    $testWindowLayoutSource -notmatch 'EnsureNoActivate' -or
    $testWindowLayoutSource -notmatch '0x08000000L' -or
    $testWindowLayoutSource -notmatch 'GetForegroundProcessId' -or
    $testWindowLayoutSource -notmatch 'NotForeground = \$notForeground' -or
    $testWindowLayoutSource -notmatch 'GetClipCursor' -or
    $testWindowLayoutSource -notmatch 'ClipCursor\(ref Rect rect\)' -or
    $testWindowLayoutSource -notmatch 'CursorClipRestorePolicy' -or
    $testWindowLayoutSource -match 'ClipCursor\(IntPtr.Zero\)' -or
    $testWindowLayoutSource -notmatch 'CursorUnrestrictedAcrossDesktop = \$cursorUnrestrictedAcrossDesktop' -or
    $testWindowLayoutSource -notmatch 'GetSystemMetrics\(76\)' -or
    $testWindowLayoutSource -notmatch 'geometryPreserved' -or
    $testWindowLayoutSource -notmatch '0x0057' -or
    $testWindowLayoutSource -match 'display_width = \$script:ChronicleTestWindow' -or
    $testWindowLayoutSource -notmatch 'RemoveNoActivate' -or
    -not (Test-Path -LiteralPath (Join-Path $stageRoot 'Reset-GameWindow.ps1') -PathType Leaf) -or
    $testWindowLayoutSource -notmatch 'if \(processId != targetProcessId\) return true;' -or
    $testWindowLayoutSource -notmatch 'IsWindowVisible\(handle\) \? 10000000L' -or
    $testWindowLayoutSource -notmatch 'Window foreground must not belong to the harness client' -or
    $testWindowLayoutSource -notmatch 'IsIconic' -or $testWindowLayoutSource -notmatch 'IsWindowVisible' -or
    $testWindowLayoutSource -notmatch 'Minimized = \$iconic' -or
    $testWindowLayoutSource -match 'SetForegroundWindow|BringWindowToTop') {
    throw 'Harness game windows must remain visible for capture but carry WS_EX_NOACTIVATE, verify the style, and restore only a test-introduced cursor clip to the previously unrestricted desktop bounds without foregrounding or injecting input.'
}
$focusRestoreSource = Get-Content (Join-Path $stageRoot 'HarnessFocusRestore.ps1') -Raw -Encoding UTF8
if ($testWindowLayoutSource -notmatch 'Restore-ChroniclePreLaunchForeground -TargetProcessId' -or
    $focusRestoreSource -notmatch 'AttachThreadInput' -or
    $focusRestoreSource -notmatch 'pre-launch-foreground-owner-is-the-harness' -or
    $focusRestoreSource -notmatch 'pre-launch-foreground-owner-was-the-game' -or
    $focusRestoreSource -notmatch 'pre-launch-foreground-owner-has-exited' -or
    $focusRestoreSource -notmatch 'FindVisibleProcessWindow' -or
    $focusRestoreSource -notmatch 'Restored = \$receipt\.ForegroundProcessIdAfter -ne \$GameProcessId' -or
    $focusRestoreSource -notmatch 'pre-launch-foreground-owner-restored' -or
    $smokeModuleSource -notmatch '\$windowLayoutGraceDeadline = \$launchStart\.AddSeconds\(20\)' -or
    $smokeModuleSource -notmatch '\$windowLayoutFailures\+\+' -or
    $smokeModuleSource -notmatch 'FocusRestoreReason = if \(\$testWindowLayout -and \$testWindowLayout\.FocusRestore\)') {
    throw 'A game window that grabs the foreground on startup must be handed back to the recorded pre-launch owner within a bounded startup grace window, never to the Harness process, and the smoke receipt must name the reason when the hand-back is refused.'
}
if ($agentCliSource -notmatch "'recoverTestConfig'" -or $testWindowLayoutSource -match "max_framerate" -or $agentCliSource -notmatch 'engine_config\.chronicle-backup' -or $agentCliSource -notmatch 'Restore-ChronicleTestEngineConfig' -or $agentCliSource -notmatch 'engineConfigRestored' -or $agentCliSource -notmatch 'startup-timeout-' -or $agentCliSource -notmatch 'RglErrorLogTail' -or $agentCliSource -notmatch 'WatchdogLogTail' -or $agentCliSource -notmatch 'Ensure-ChronicleSteamClient' -or $startupEvidenceSource -notmatch 'steamwebhelper' -or $startupEvidenceSource -notmatch 'Get-ChronicleSteamClientReadiness' -or $startupEvidenceSource -notmatch 'Bannerlord was not launched' -or $agentCliSource -notmatch 'ConvertTo-ChronicleStartupDialogEvidence' -or $agentCliSource -notmatch 'StreamReader') { throw 'Harness must wait for stable Steam WebHelper readiness, serialize sanitized startup dialog evidence, and preserve Steam API warnings without global input.' }
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
$actualDiagnosticHash = Get-ChronicleCanonicalFileSha256 -LiteralPath (Join-Path $modRoot 'SubModule.cs')
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
if ($contextState.current.mainlineSha256 -ne $mainlineHash) { throw 'MAINLINE.md hash is stale; run Set-ContextFocus.ps1 -Review.' }
$reviewAfter = [DateTime]::Parse($contextState.current.reviewAfterUtc).ToUniversalTime()
if ($reviewAfter -lt [DateTime]::UtcNow) { throw "Current focus review is overdue: $($contextState.current.reviewAfterUtc)." }
if ([int]$contextState.schemaVersion -ne 2) { throw 'ContextState must use router-only schema version 2.' }
if ([string]::IsNullOrWhiteSpace([string]$contextState.current.path) -or [string]::IsNullOrWhiteSpace([string]$contextState.current.reviewedUtc) -or [string]::IsNullOrWhiteSpace([string]$contextState.current.reviewAfterUtc) -or [string]::IsNullOrWhiteSpace([string]$contextState.current.mainlineSha256)) { throw 'ContextState current may contain only a valid focus pointer and review/hash metadata.' }
if (@($contextState.current.PSObject.Properties.Name | Where-Object { $_ -in @('id', 'objective', 'phase', 'updatedUtc') }).Count -gt 0) { throw 'ContextState must not duplicate project/task objective, phase, or live status.' }
[string[]]$expectedDefaultRead = @('DEVELOPMENT.md', 'MAINLINE.md')
if (($contextState.defaultRead -join '|') -ne ($expectedDefaultRead -join '|')) { throw 'Default context is limited to the engineering contract and active technical focus; load design/inventory/research on demand.' }
[string]$defaultMainline = $contextState.defaultRead | Where-Object { $_ -eq [string]$contextState.current.path }
if (-not $defaultMainline) { throw 'Current focus is not in defaultRead.' }
if (@($contextState.defaultRead | Where-Object { $_ -like 'Archive/*' }).Count -gt 0) { throw 'Archive content cannot be in defaultRead.' }
