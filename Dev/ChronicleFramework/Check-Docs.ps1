[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$harnessRoot = $PSScriptRoot
$localSettingsPath = Join-Path $harnessRoot 'harness.local.json'
$localSettings = if (Test-Path -LiteralPath $localSettingsPath) { Get-Content -LiteralPath $localSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
$projectRoot = if ($localSettings -and $localSettings.repositoryRoot) { [IO.Path]::GetFullPath([string]$localSettings.repositoryRoot) } else { Split-Path -Parent (Split-Path -Parent $harnessRoot) }
$contractVersion = '4.85'
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

$actualFiles = @(Get-ChildItem -Path $harnessRoot -Recurse -File -Filter '*.md' | Where-Object { $_.FullName -notmatch '[\\/](TestResults|obj|bin)[\\/]' })
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
$startupEvidenceScript = Join-Path $harnessRoot 'HarnessStartupEvidence.ps1'
$contextFocusScript = Join-Path $harnessRoot 'Set-ContextFocus.ps1'
$researchReadinessScript = Join-Path $harnessRoot 'HarnessResearchReadiness.ps1'
$researchReadinessSource = Get-Content $researchReadinessScript -Raw -Encoding UTF8
. $researchReadinessScript
$contextFocusSource = Get-Content $contextFocusScript -Raw -Encoding UTF8
. $researchReadinessScript
$projectFile = Get-Content (Join-Path $harnessRoot 'ChronicleFramework.csproj') -Raw -Encoding UTF8
$developmentDoc = Get-Content (Join-Path $harnessRoot 'DEVELOPMENT.md') -Raw -Encoding UTF8
$designDoc = Get-Content (Join-Path $harnessRoot 'DESIGN.md') -Raw -Encoding UTF8
$inventoryDoc = Get-Content (Join-Path $harnessRoot 'SYSTEM_INVENTORY.md') -Raw -Encoding UTF8
$rootAgents = Get-Content (Join-Path $projectRoot 'AGENTS.md') -Raw -Encoding UTF8
$runtimeGameRoot = if ($localSettings -and $localSettings.gameRoot) { [IO.Path]::GetFullPath([string]$localSettings.gameRoot) } else { $null }
$gitIgnore = Get-Content (Join-Path $projectRoot '.gitignore') -Raw -Encoding UTF8
$sourceManifestPath = Join-Path $projectRoot 'Modules\ChronicleFramework\SubModule.xml'
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
if ($harnessScript -notmatch 'GitCommit' -or $harnessScript -notmatch 'SourceControl' -or $harnessScript -notmatch 'status --porcelain' -or $harnessScript -match 'TaskBoard|CensusDomainDoneCount|gh project|gh api|githubProjectNumber') { throw 'Harness receipts must record Git provenance and remain independent of GitHub task tracking.' }
if ($projectFile -notmatch 'ChronicleGameRoot' -or $harnessScript -notmatch 'ChronicleGameRoot=\$gameRoot' -or -not (Test-Path -LiteralPath (Join-Path $harnessRoot 'Initialize-ChronicleWorkspace.ps1'))) { throw 'Cloned repositories must accept a local game path and provide a repeatable workspace initializer.' }
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
if ($harnessScript -notmatch "FreshCampaign'\s*\{\s*@\('Preflight', 'Build', 'FreshCampaign'\)") { throw 'FreshCampaign phase must run Preflight and Build before its test.' }
if ($harnessScript -notmatch "FreshCampaignProgression'\s*\{\s*@\('Preflight', 'Build', 'FreshCampaignProgression'\)") { throw 'FreshCampaignProgression phase must run Preflight and Build before its test.' }
if ($harnessScript -notmatch 'FreshCampaignProgressionAttempt\$attempt' -or $harnessScript -notmatch '\$attempt -le 2' -or $harnessScript -notmatch 'Get-ChronicleStartupAssessment' -or $harnessScript -notmatch 'startupClassification' -or $harnessScript -notmatch 'progressionFailureDetail' -or $harnessScript -notmatch 'characterCreationCompleted' -or $harnessScript -notmatch 'Get-Content -LiteralPath \$testResult\.RglLog -Tail 8' -or $harnessScript -notmatch 'ConvertTo-ChronicleLogTail -Lines \$rglLogLines' -or -not (Test-Path -LiteralPath $startupEvidenceScript)) { throw 'FreshCampaignProgression must retain stage/failure detail and normalize its short RGL tail.' }
if ($harnessScript -notmatch 'recruitmentProgression = \$testResult\.RecruitmentProgression' -or $harnessScript -notmatch 'progressionSaveCycleVerified' -or $harnessScript -notmatch 'freshClanRenown = \$testResult\.ClanRenown') { throw 'FreshCampaignProgression must preserve the measurable baseline, save cycle, and recruit receipt summary.' }
. $startupEvidenceScript
if (-not (Test-ChronicleStartupAssessment)) { throw 'Startup evidence regression checks failed.' }
if (-not (Test-ChronicleLogTailNormalization -Path $startupEvidenceScript)) { throw 'Get-Content log-tail normalization regression checks failed.' }
$protocolSource = Get-Content (Join-Path (Split-Path -Parent $harnessRoot) 'ChronicleFramework\AgentProtocol.cs') -Raw -Encoding UTF8
if ($protocolSource -notmatch 'postbattle-renown-telemetry-failed' -or $protocolSource -notmatch 'visual-battle-fixture' -or $protocolSource -notmatch 'winnerRenownValue' -or $protocolSource -notmatch 'loserStrengthReductionFactorAfterFinish') { throw 'PostBattle renown telemetry must remain fixture-only and report model inputs/results without changing battle rules.' }
if ($protocolSource -notmatch 'captureFrame is restricted to visual Harness modes' -or $protocolSource -notmatch 'Utilities\.TakeScreenshot\(capturePath\)') { throw 'Harness-only engine screenshot contract is missing.' }
if ($protocolSource -notmatch '_pendingClaimedCommandPath' -or $protocolSource -notmatch 'agent-command-read-retry' -or $protocolSource -notmatch 'FileShare\.ReadWrite \| FileShare\.Delete') { throw 'Transiently locked commands must remain claimed and retry instead of being deleted/lost.' }
$videoCaptureSource = Get-Content (Join-Path $harnessRoot 'HarnessVideoCapture.ps1') -Raw -Encoding UTF8
if ($videoCaptureSource -notmatch 'gfxcapture=hwnd=' -or $videoCaptureSource -notmatch 'FrameCoverageRatio' -or $videoCaptureSource -notmatch 'TimelineIndexPath' -or $videoCaptureSource -notmatch 'Remove-Item -LiteralPath \$Capture\.OutputPath' -or $videoCaptureSource -notmatch 'Explicit Bannerlord HWND') { throw 'Continuous capture must target one Bannerlord HWND, validate/index frames, and delete successful source video.' }
$battleFixtureSource = Get-Content (Join-Path $harnessRoot 'Test-AgentBattleFixture.ps1') -Raw -Encoding UTF8
if ($battleFixtureSource -notmatch 'BattleRewardTelemetry = if \(\$simulationFinish -and \$simulationFinish\.data\)') { throw 'PostBattle evidence must preserve the returned renown telemetry object.' }
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
foreach ($requiredScript in @('Agent-DecisionLoop.ps1', 'Test-AgentLoop.ps1', 'Test-AgentLoopProvider.ps1', 'Test-AgentBattleFixture.ps1', 'Test-AgentVisualCapture.ps1', 'Test-AgentFreshCampaign.ps1', 'Test-AgentSupport.ps1', 'HarnessVideoCapture.ps1', 'Set-ContextFocus.ps1')) {
    if (-not (Test-Path (Join-Path $harnessRoot $requiredScript))) { throw "Agent loop harness script is missing: $requiredScript" }
}
$freshCampaignSource = Get-Content (Join-Path $harnessRoot 'FreshCampaignHarness.cs') -Raw -Encoding UTF8
$freshCampaignTelemetry = Get-Content (Join-Path $harnessRoot 'SubModule.cs') -Raw -Encoding UTF8
$freshCampaignTest = Get-Content (Join-Path $harnessRoot 'Test-AgentFreshCampaign.ps1') -Raw -Encoding UTF8
$protocolTestSource = Get-Content (Join-Path $harnessRoot 'Test-AgentProtocol.ps1') -Raw -Encoding UTF8
if ($freshCampaignTelemetry -notmatch 'Campaign\.Current\?\.CampaignBehaviorManager\?\.GetBehavior<ChronicleCampaignBehavior>\(\)' -or $freshCampaignTelemetry -notmatch 'campaign-agent-behavior-rebound' -or $freshCampaignTelemetry -notmatch 'AgentProtocolReady' -or $freshCampaignTelemetry -match 'fresh-progression-app-tick|fresh-progression-map-tick' -or $protocolSource -notmatch 'fresh-progression-protocol-command-visible' -or $freshCampaignTest -notmatch 'CHRONICLE_FRESH_CAMPAIGN_SKIP_ISSUE_PROBE') { throw 'Progression must skip the native Issue probe without app-tick polling before a campaign exists.' }
if ($freshCampaignSource -notmatch 'CHRONICLE_HARNESS_MODE' -or $freshCampaignSource -notmatch 'OnNarrativeMenuOptionSelected' -or $freshCampaignSource -notmatch 'adulthood_defeated_enemy_option' -or $freshCampaignSource -notmatch 'manager\.NextStage\(\)' -or $freshCampaignSource -notmatch 'CanUserSkip' -or $freshCampaignSource -notmatch 'OnVideoFinished\(\)' -or $freshCampaignSource -notmatch 'CampaignMapConversation.OpenConversation' -or $freshCampaignSource -notmatch 'hero_give_issue' -or $freshCampaignSource -notmatch 'issueOfferDenied' -or $freshCampaignSource -notmatch 'lord_meet_player_response1' -or $freshCampaignSource -notmatch 'issue_explanation_player_response_pre_quest_solution') { throw 'Fresh campaign test must exercise native creation and classify local Issue offer/precondition outcomes.' }
if ($freshCampaignTelemetry -notmatch 'ChronicleAgentObserver.BuildSnapshotJson') { throw 'FreshCampaign must capture the post-creation Agent snapshot.' }
if ($freshCampaignTelemetry -notmatch 'Campaign\.Current\.SaveHandler\.SaveAs\(freshSaveName\)' -or $freshCampaignTelemetry -notmatch 'fresh-campaign-disposable-save-scheduled' -or $freshCampaignTelemetry -notmatch 'fresh-campaign-disposable-save-requested' -or $freshCampaignTelemetry -notmatch 'fresh-campaign-disposable-save-complete' -or $freshCampaignTelemetry -notmatch 'via=CampaignTick' -or $freshCampaignTelemetry -notmatch 'fresh-campaign-progression-campaign-tick' -or $freshCampaignTelemetry -notmatch '_agentProtocol\?\.Poll\(this\)') { throw 'FreshCampaign must save the stopped fresh campaign on its first native CampaignTick and observe completion.' }
if ($freshCampaignTelemetry -notmatch 'IsNativeCampaignMusicInitialized' -or $freshCampaignTelemetry -notmatch 'MBMusicManager\.IsCreationCompleted\(\)' -or $freshCampaignTelemetry -notmatch 'fresh-campaign-start-wait' -or $freshCampaignTelemetry -notmatch 'fresh-campaign-start-ready' -or $freshCampaignTelemetry -notmatch 'skipProgressionIssueProbe' -or $freshCampaignTelemetry -notmatch 'GetType\(\)\.Name == "MapState"') { throw 'FreshCampaign must wait for native music initialization and suppress only the progression Issue probe after MapState.' }
if ($protocolTestSource -notmatch 'NewGuid\(\)' -or $protocolTestSource -notmatch 'Disposable protocol save path escaped Game Saves' -or $protocolTestSource -notmatch 'ProtocolSaveCleaned' -or $protocolTestSource -notmatch 'Remove-ProtocolSaveFixture') { throw 'Protocol save/reload tests must use a unique disposable save inside Game Saves and clean it after capturing verification evidence.' }
if ($freshCampaignSource -match 'SaveAs\(|SaveGame\(') { throw 'Fresh campaign renown test must not create a save.' }
$freshCampaignTestCompact = $freshCampaignTest -replace '\s+', ' '
$decisionLoopSource = Get-Content (Join-Path $harnessRoot 'Agent-DecisionLoop.ps1') -Raw -Encoding UTF8
$agentLoopTest = Get-Content (Join-Path $harnessRoot 'Test-AgentLoop.ps1') -Raw -Encoding UTF8
$agentLoopProvider = Get-Content (Join-Path $harnessRoot 'Test-AgentLoopProvider.ps1') -Raw -Encoding UTF8
if ($decisionLoopSource -notmatch 'previousActionReceipt' -or $agentLoopTest -notmatch 'PreviousActionReceiptForwarded' -or $agentLoopProvider -notmatch 'Previous native action receipt was not forwarded') { throw 'The next Agent decision must receive and test the preceding native action receipt.' }
$recruitmentTest = Get-Content (Join-Path $harnessRoot 'Test-AgentRecruitment.ps1') -Raw -Encoding UTF8
if ($agentLoopProvider -notmatch "CHRONICLE_TEST_PROVIDER_MODE -eq 'recruitment'" -or $agentLoopProvider -notmatch '\$request\.previousActionReceipt' -or $agentLoopProvider -notmatch '\$receipt\.data\.offers' -or $recruitmentTest -notmatch 'OfferDataForwardedToNextDecision' -or $recruitmentTest -notmatch 'OfferSelectionMatchedReceipt' -or $recruitmentTest -notmatch 'RecruitmentDecisionSummary' -or $recruitmentTest -match 'RecruitmentDecisionTrace\s*=\s*\$recruitmentLoop\.trace') { throw 'Recruitment must test receipt-based selection and keep only concise evidence, not duplicate full observations.' }
if ($freshCampaignTest -notmatch 'Set-ChronicleTestWindow' -or $freshCampaignTest -notmatch 'WindowLayoutApplied' -or $freshCampaignTest -notmatch 'display_width' -or $freshCampaignTest -notmatch '840') { throw 'FreshCampaign must enforce the existing non-activating windowed test layout.' }
if ($freshCampaignTest -notmatch 'FreshCampaign\.initial-state\.json' -or $freshCampaignTest -notmatch 'WriteAllBytes' -or $freshCampaignTest -notmatch 'creationCompleted -and \$initialSnapshotCaptured') { throw 'FreshCampaign must persist the post-creation Agent observation as UTF-8 evidence before passing.' }
if ($freshCampaignTest -notmatch 'IssueConversationProbeApplicable' -or $freshCampaignTest -notmatch 'IssueConversationProbeSkipped' -or $freshCampaignTestCompact -notmatch 'issueConversationProbePassed = if \(\$issueProbeExpected\).*?\$null' -or $freshCampaignTest -notmatch 'issueConversationProbeOutcomeValid' -or $freshCampaignTest -notmatch 'issueConversationOfferDenied' -or $freshCampaignTest -notmatch 'issueOfferOptionAvailable') { throw 'FreshCampaign must distinguish an applicable offer/denial from a no-issue skip.' }
if ($freshCampaignTest -notmatch 'ValidateRecruitmentProgression' -or $freshCampaignTest -notmatch 'CHRONICLE_FRESH_CAMPAIGN_SAVE_NAME' -or $freshCampaignTest -notmatch 'disposableSaveCompleted' -or $freshCampaignTest -notmatch 'disposable save' -or $freshCampaignTest -notmatch 'Agent CLI could not load the fresh-created disposable save' -or $freshCampaignTest -notmatch 'Wait-ForAgentSettlementArrival' -or $freshCampaignTest -notmatch 'Crash Report' -or $freshCampaignTest -notmatch 'Math\]::Min\(15, \$TimeoutSeconds\)' -or $freshCampaignTest -notmatch 'save cleanup path escaped Game Saves' -or $freshCampaignTest -notmatch 'activeGameProcess\.MainWindowTitle' -or $freshCampaignTelemetry -match 'fresh-campaign-progression-clock') { throw 'Fresh progression must keep the clock stopped and save from the first CampaignTick.' }
if ($freshCampaignTest -notmatch "Test-AgentSupport\.ps1" -or $freshCampaignTest -notmatch 'Wait-ForAgentSettlementArrival') { throw 'FreshCampaign progression must import the shared arrival helper it invokes.' }
if ($freshCampaignTest -notmatch 'Get-Content -LiteralPath \$diagnosticLog -Encoding UTF8') { throw 'FreshCampaign must read diagnostic telemetry as UTF-8 to preserve localized JSON strings.' }
if ($freshCampaignTest -notmatch 'Start-ChronicleWindowVideoCapture' -or $freshCampaignTest -notmatch 'Stop-ChronicleWindowVideoCapture' -or $freshCampaignTest -notmatch 'CrashReport-\$bannerlordPid\.mp4' -or $freshCampaignTest -notmatch 'crashCaptureGraceActive' -or $freshCampaignTest -notmatch 'CrashWindowCaptureVideoRetained' -or $freshCampaignTest -notmatch 'action = ''crashReport''' -or $freshCampaignTest -notmatch 'crashObserved' -or $videoCaptureSource -notmatch '''crashObserved''' -or $freshCampaignTest -match 'UIAutomationClient|ExpandCollapsePattern|PostMouseWheel|crashReportScroll') { throw 'FreshCampaign must retain crash-window visual evidence without brittle report-window UI automation.' }
if ($freshCampaignTest -notmatch 'CrashFaultAddress' -or $freshCampaignTest -notmatch 'CrashFaultModule' -or $freshCampaignTest -notmatch 'ModuleMemorySize' -or $freshCampaignTest -notmatch 'CrashModuleInventory' -or $harnessScript -notmatch 'crashModuleInventory = \$testResult\.CrashModuleInventory') { throw 'Crash evidence must map the native fault IP against the live process module address ranges.' }
if ($freshCampaignTest -notmatch 'CHRONICLE_CAPTURE_CRASH_EXCEPTION' -or $freshCampaignTest -notmatch 'CrashExceptionCaptured' -or $harnessScript -notmatch 'crashExceptionPath = \[string\]\$testResult\.CrashExceptionPath' -or $freshCampaignTelemetry -notmatch 'ExceptionReporter' -or $freshCampaignTelemetry -notmatch 'CaptureCrashExceptionBeforeReport' -or $freshCampaignTelemetry -notmatch 'exception\.ToString\(\)' -or $freshCampaignTelemetry -notmatch 'DescribeCampaignMusicContext' -or $projectFile -notmatch '0Harmony\.dll') { throw 'Crash reports must capture ButterLib exception and CampaignMusic context in-process, without UI automation.' }
if ($freshCampaignTest -notmatch 'Start-ChronicleWindowVideoCapture' -or $freshCampaignTest -notmatch 'Stop-ChronicleWindowVideoCapture' -or $freshCampaignTest -notmatch 'CrashReport-\$bannerlordPid\.mp4' -or $freshCampaignTest -notmatch 'crashCaptureGraceActive' -or $freshCampaignTest -notmatch 'CrashWindowCaptureError') { throw 'FreshCampaign must capture an actual crash-report window into keyframe evidence before cleanup.' }
if ($freshCampaignTelemetry -notmatch 'fresh-campaign-visible-issues' -or $freshCampaignTest -notmatch 'VisibleIssueTypesBySettlement') { throw 'FreshCampaign must record local issue types for route research.' }
if ($freshCampaignTelemetry -notmatch 'FreshCampaignHarness\.ProbeLocalIssueConversation') { throw 'FreshCampaign must probe the local native issue dialogue after character creation.' }
foreach ($requiredHeading in @('## 判断原则', '## 单一工作循环', '## 事实归属与资料读取')) {
    if ($rootAgents -notmatch [regex]::Escape($requiredHeading)) { throw "AGENTS.md is missing the unified method section '$requiredHeading'." }
}
if ($rootAgents -notmatch '最多推进一项' -or $rootAgents -notmatch 'Harness 不调用 GitHub' -or $rootAgents -notmatch '高影响未知未解决前不猜着实现') { throw 'AGENTS.md must preserve single-task execution, source ownership, and consequential-unknown handling.' }
if ($developmentDoc -notmatch '研究就绪门槛' -or $harnessScript -notmatch 'Get-ChronicleResearchReadiness' -or -not (Test-Path -LiteralPath $researchReadinessScript)) { throw 'Research readiness rules must be documented and enforced before building changed game C# sources.' }
$approvedDiagnosticHash = [regex]::Match($researchReadinessSource, "AuditedHarnessDiagnosticSha256 = '([0-9a-f]{64})'")
$actualDiagnosticHash = Get-ChronicleCanonicalFileSha256 -LiteralPath (Join-Path $harnessRoot 'SubModule.cs')
if (-not $approvedDiagnosticHash.Success -or $approvedDiagnosticHash.Groups[1].Value -ne $actualDiagnosticHash) { throw 'The exact-hash SubModule diagnostic exception must match the reviewed source.' }
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
if (-not (Test-ChronicleResearchReadiness)) { throw 'Research readiness gate regression checks failed.' }
if ($mainlineDoc -notmatch '(?m)^#### .*Mechanic Contract\s*$') { throw 'MAINLINE.md is missing the required original-mechanic contract table.' }
if ($mainlineDoc -notmatch '(?m)^#### .*Coverage and Evidence Contract') { throw 'MAINLINE.md must define durable denominator/acceptance rules without storing current task progress.' }
foreach ($actionId in @('move', 'pursue', 'hold', 'rest', 'advance', 'autoresolve (research)', 'dialogueSelect (research)', 'dialogueContinue (research)', 'retreat (research)', 'partyLoot (research)')) {
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
    MarkdownBytes = $totalBytes
    DefaultReadMarkdownBytes = $defaultReadBytes
    TaskTrackerUrl = $taskTrackerUrl
    CheckedUtc = (Get-Date).ToUniversalTime().ToString('O')
} | ConvertTo-Json
