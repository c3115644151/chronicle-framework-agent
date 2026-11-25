#Requires -Version 7.0

# CLI startup: Preflight Steam branch parsing, crash report windows and Steam readiness regressions.
# Sources asserted here: Agent-Cli.ps1

$startupEvidenceSource = Get-Content -LiteralPath $startupEvidenceScript -Raw -Encoding UTF8
if (-not (Test-ChronicleSteamBranchSelectionContract) -or
    $startupEvidenceSource -notmatch 'function Get-ChronicleSteamBranchSelectionFromManifestText' -or
    $startupEvidenceSource -notmatch 'function Assert-ChronicleSteamGameBranch' -or
    $harnessScript -notmatch '(?m)\$targetGameBranch\s*=\s*''v1\.4\.8''' -or
    $harnessScript -notmatch 'Assert-ChronicleSteamGameBranch -GameRoot \$gameRoot -RequiredBranch \$targetGameBranch' -or
    $harnessScript -notmatch 'SteamBuildId\s*=\s*\$gameBranch\.BuildId') {
    throw 'Harness Preflight must parse separate Steam selected/installed branches and stop before build or game launch unless both match the contracted v1.4.8 target.'
}
$agentCliSource = Get-Content -LiteralPath (Join-Path $stageRoot 'Agent-Cli.ps1') -Raw -Encoding UTF8
if (-not (Test-ChronicleCrashReportWindowTitleContract) -or
    $agentCliSource -notmatch 'Test-ChronicleCrashReportWindowTitle' -or
    $agentCliSource -notmatch 'startup-crash-report-' -or
    $agentCliSource -notmatch 'DialogReadError' -or
    $agentCliSource -notmatch 'Get-WinEvent -FilterHashtable' -or
    $agentCliSource -notmatch 'WindowsErrorEvents = \$windowsErrorEvents' -or
    $startupEvidenceSource -notmatch 'function ConvertTo-ChronicleStartupCrashEventEvidence' -or
    -not (Test-ChronicleStartupCrashEventEvidenceContract) -or
    $agentCliSource -notmatch 'No model request was sent and no crash-dialog button was pressed') {
    throw 'Agent-Cli must recognize a process-owned Crash Report window, retain correlated Windows/RGL evidence, stop only the test-owned process tree, and never click the crash dialog.'
}
$startupEvidenceSource = Get-Content -LiteralPath $startupEvidenceScript -Raw -Encoding UTF8
if (-not (Test-ChronicleSteamClientReadiness)) { throw 'Steam API readiness regression checks failed.' }
if ($startupEvidenceSource -notmatch 'function Ensure-ChronicleSteamClientReady' -or
    $startupEvidenceSource -notmatch 'function Get-ChronicleSteamLoginState' -or
    $startupEvidenceSource -notmatch 'function Test-ChronicleSteamReconnectDelayExceedsHarnessWindow' -or
    $startupEvidenceSource -notmatch 'steam-user-logged-on' -or
    $startupEvidenceSource -notmatch 'SteamServerConnectFailure_t' -or
    $startupEvidenceSource -notmatch 'ReconnectDelaySeconds' -or
    $startupEvidenceSource -notmatch 'ReconnectDelaySeconds -gt \$TimeoutSeconds' -or
    $startupEvidenceSource -notmatch "ArgumentList '-silent'.*-WindowStyle Hidden" -or
    $startupEvidenceSource -notmatch 'function Start-ChronicleSteamGame' -or
    $startupEvidenceSource -notmatch 'function Disable-ChronicleHarnessGameSound' -or
    $startupEvidenceSource -notmatch 'function Restore-ChronicleHarnessGameSound' -or
    $startupEvidenceSource -notmatch 'disable_sound\\s\*=\\s\*' -or
    $harnessScript -notmatch 'BannerlordSoundRecoveryOnHarnessStart' -or
    $startupEvidenceSource -notmatch "steam_appid\.txt" -or
    $startupEvidenceSource -notmatch "SetEnvironmentVariable\('SteamAppId'" -or
    $startupEvidenceSource -notmatch "SetEnvironmentVariable\('SteamGameId'" -or
    $startupEvidenceSource -notmatch 'WindowStyle\s*=\s*''Hidden''' -or
    $agentCliSource -notmatch 'Ensure-ChronicleSteamClientReady' -or
    $agentCliSource -notmatch 'Start-ChronicleSteamGame -FilePath \$launcher.*-WindowStyle Hidden' -or
    $agentCliSource -notmatch 'Disable-ChronicleHarnessGameSound' -or
    $agentCliSource -notmatch 'Restore-ChronicleHarnessGameSound' -or
    $freshCampaignSource -notmatch 'Start-ChronicleSteamGame -FilePath \$launcher.*-WindowStyle Hidden' -or
    $freshCampaignSource -notmatch 'Disable-ChronicleHarnessGameSound' -or
    $freshCampaignSource -notmatch 'Restore-ChronicleHarnessGameSound' -or
    $freshCampaignSource -notmatch 'BannerlordSoundMutedForHarness' -or
    $campaignTestSource -notmatch 'Start-ChronicleSteamGame -FilePath \$launcher.*-WindowStyle Hidden' -or
    $campaignTestSource -notmatch 'Disable-ChronicleHarnessGameSound' -or
    $campaignTestSource -notmatch 'Restore-ChronicleHarnessGameSound' -or
    $campaignTestSource -notmatch 'Ensure-ChronicleSteamClientReady' -or
    $smokeModuleSource -notmatch 'Ensure-ChronicleSteamClientReady' -or
    $smokeModuleSource -notmatch 'Start-ChronicleSteamGame -FilePath \$gameExe.*-WindowStyle Hidden' -or
    $smokeModuleSource -notmatch 'Disable-ChronicleHarnessGameSound' -or
    $smokeModuleSource -notmatch 'Restore-ChronicleHarnessGameSound' -or
    $smokeModuleSource -notmatch 'BannerlordSoundMutedForHarness' -or
    $smokeModuleSource -notmatch 'BannerlordSoundRestored' -or
    $smokeModuleSource -notmatch 'SteamClient = \[ordered\]@\{' -or
    $smokeModuleSource -notmatch 'startedByHarness = \[bool\]\$steamStatus\.startedByHarness' -or
    $smokeModuleSource -notmatch 'loginState = \[ordered\]@\{' -or
    $smokeModuleSource -notmatch 'eventUtc = \[string\]\$steamStatus\.loginState\.EventUtc' -or
    $smokeModuleSource -notmatch 'SteamProcessCount = \[int\]\$steamStatus\.readiness\.SteamProcessCount' -or
    $smokeModuleSource -notmatch 'WebHelperStableSeconds = \[double\]\$steamStatus\.readiness\.WebHelperStableSeconds' -or
    $smokeModuleSource.IndexOf('Ensure-ChronicleSteamClientReady', [StringComparison]::Ordinal) -gt $smokeModuleSource.IndexOf('Start-ChronicleSteamGame -FilePath $gameExe', [StringComparison]::Ordinal)) {
    throw 'Every Harness-owned Bannerlord launch must use the shared Steam readiness gate and reversible game-only sound guard; Smoke must record readiness and sound restoration.'
}
if (-not (Test-ChronicleStartupDialogEvidenceSerialization)) { throw 'Startup dialog evidence retained a live UI Automation object instead of a serializable snapshot.' }
if (-not (Test-ChronicleReceiptSerialization)) { throw 'Receipt normalization changed primitive/list data or retained PowerShell object metadata.' }
$retentionSelfTestOutput = & $HarnessPowerShell -NoProfile -File $testResultsRetentionScript -SelfTest 2>&1 | Out-String
if ($LASTEXITCODE -ne 0 -or -not ($retentionSelfTestOutput | ConvertFrom-Json).Passed) { throw "TestResults retention safety regression failed: $retentionSelfTestOutput" }
$retentionSource = Get-Content -LiteralPath $testResultsRetentionScript -Raw -Encoding UTF8
$expectedTimestampFolderPattern = '$_.Name -match ''^\d{8}-\d{6}$'''
$retentionSelfTest = $retentionSelfTestOutput | ConvertFrom-Json
if ($harnessScript -notmatch 'Prune-TestResults\.ps1' -or $harnessScript -notmatch '-CurrentRunId \$runId -Apply' -or -not $retentionSource.Contains($expectedTimestampFolderPattern) -or $retentionSource -notmatch 'ProtectedDocumentRunCount' -or $retentionSource -notmatch 'PreservedIncompleteCaptureRuns' -or $retentionSource -notmatch 'KeepMostRecentRuns' -or $retentionSource -notmatch 'knownUndecodable' -or $retentionSource -notmatch 'removedAfterEvidence' -or -not $retentionSelfTest.ContactSheetOnlyCapturePruned -or -not $retentionSelfTest.CitedAndIndexedMediaPreserved -or -not $retentionSelfTest.HistoricalContextFramesCompacted -or -not $retentionSelfTest.RedundantHistoricalMediaCompacted -or $harnessScript -notmatch 'DeletedUndecodableVideoBytes' -or $harnessScript -notmatch 'CompactedMediaBytes' -or $retentionSource -notmatch 'historical-event-frames-only' -or $retentionSource -notmatch 'Complete = \$skippedRuns\.Count -eq 0') { throw 'TestResults retention must protect active, documented and recent receipts plus incomplete captures, retain historical event frames, compact redundant adjacent frames only after index updates, and preserve explicitly cited images.' }
if (-not (Test-ChronicleLogTailNormalization -Path $startupEvidenceScript)) { throw 'Get-Content log-tail normalization regression checks failed.' }
$protocolSource = $agentProtocolSource
if ($protocolSource -notmatch 'postbattle-renown-telemetry-failed' -or $protocolSource -notmatch 'visual-battle-fixture' -or $protocolSource -notmatch 'winnerRenownValue' -or $protocolSource -notmatch 'loserStrengthReductionFactorAfterFinish') { throw 'PostBattle renown telemetry must remain fixture-only and report model inputs/results without changing battle rules.' }
if ($protocolSource -notmatch 'captureFrame is restricted to visual Harness modes' -or $protocolSource -notmatch 'solo-battle-fixture' -or $protocolSource -notmatch 'Utilities\.TakeScreenshot\(capturePath\)') { throw 'Harness-only engine screenshot contract is missing.' }
if ($protocolSource -notmatch '_pendingClaimedCommandPath' -or $protocolSource -notmatch 'agent-command-read-retry' -or $protocolSource -notmatch 'FileShare\.ReadWrite \| FileShare\.Delete') { throw 'Transiently locked commands must remain claimed and retry instead of being deleted/lost.' }
