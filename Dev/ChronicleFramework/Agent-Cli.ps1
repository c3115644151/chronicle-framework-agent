[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet('start','load','recoverTestConfig','state','agentCheckpointGet','agentCheckpointSet','harnessSeedAgentCheckpointFailure','closeEscapeMenu','respondInquiry','respondMultiSelectionInquiry','mapSettlementTargets','mapNotifications','quickInformation','sceneNotification','continueSceneNotification','incidentSelect','submitStoryModeClanName','bannerEditorDone','mapPartyTargets','mapPartyComposition','mapPartyBehavior','partyUpgradeOptions','upgradeTroop','prisonerRecruitmentOptions','recruitPrisoner','characterDevelopment','spendSkillFocus','questDetails','partyRoster','partyRoles','inventoryOpen','heroEquipmentOptions','equipHeroItem','unequipHeroItem','inventoryConfirm','inventoryCancel','inventoryCancelChanges','tradeConfirm','tradeCancel','tradeCancelChanges','barterOptions','barterEdit','barterReset','barterAutoBalance','barterOffer','barterCancel','setPartyRole','unassignPartyRole','captureFrame','harnessMissionDiagnostics','harnessMapDiagnostics','harnessOpenMapEscapeMenu','harnessOpenNativeInquiry','harnessOpenRecruitmentInquiry','harnessNativeInquiryDiagnostics','harnessPrepareAlleyLeaderFixture','harnessAlleyLeaderDiagnostics','harnessPrepareAlleyRosterFixture','harnessSeedAlleyAttackFixture','harnessSeedPersuasionFixture','harnessCurrentConversationAnswers','harnessAlleyRosterDiagnostics','harnessPlayerSkillsDiagnostics','harnessCharacterDevelopmentDiagnostics','harnessQuestDetailsDiagnostics','harnessQuestDeadlinePrivacyDiagnostics','harnessPartyRosterDiagnostics','harnessMapPartyDiagnostics','harnessMapPartyCompositionDiagnostics','harnessCreateMapArmyFixture','harnessPrepareMovingArmyEncounter','harnessArmyEncounterDiagnostics','harnessPrepareSiegeJoinFixture','harnessSiegeJoinDiagnostics','harnessSeedMapPartyIssueMarker','harnessPrepareSafePassageFixture','harnessSeedCaptivityObservationFixture','harnessSeedPrisonCaptivityFixture','harnessSwitchCaptivityObservationMenu','harnessCaptivityDiagnostics','harnessPrepareSurrenderCondition','harnessSeedTryGetAwayFixture','harnessTryGetAwayDiagnostics','harnessSeedNpcBattleForPlayerJoin','harnessPrepareArmyMemberForCurrentJoinEncounter','harnessJoinEncounterDiagnostics','harnessPreparePursuitVisibilityFixture','harnessSeedPartyUpgradeFixture','harnessSeedPrisonerRecruitmentFixture','harnessSeedRecruitmentCapacityFixture','harnessPrepareCompanionHiringFixture','harnessCompanionHiringDiagnostics','harnessSeedPartyRoleFixture','harnessPartyRoleDiagnostics','harnessSeedEquipmentModifierFixture','harnessClearEquipmentModifierFixture','harnessSeedTradeRumorFixture','harnessTradeRumorTooltipDiagnostics','harnessSeedMapNotificationFixture','harnessSeedMapIncidentFixture','harnessSeedQuickInformationFixture','harnessSeedSceneNotificationFixture','harnessOpenInventoryState','harnessCloseInventoryState','harnessInventoryStateDiagnostics','talkToSettlementHero','visitSettlementHero','inventoryTakeAll','inventoryDone','seedVisualLoot','advance','pause','resume','fastForward','move','moveToPoint','missionSceneAgents','missionInput','missionNavigateToAgent','missionLeave','tournamentJoin','tournamentSkipRound','tournamentSkipAllRounds','tournamentWatchRound','tournamentLeave','missionInteract','missionCancelNavigation','missionAimAt','pursue','follow','hold','menu','menuSelect','persuasionDetails','dialogueSelect','dialogueContinue','battlePause','battleSkip','battleFinish','battleRetreat','missionRetreat','partyTakeAll','partyLootTransferOne','sellPrisonerOne','partyScreenCancel','partyScreenDone','questTroopTransfer','questTroopScreenDone','questTroopScreenCancel','alleyRosterTransfer','alleyRosterCancel','rest','recruitOptions','recruit','foodOptions','tradeOptions','tradeRumors','trade','provision','save','stop')]
    [string]$Action,
    [string]$SaveName,
    [switch]$IncludeChronicleFramework,
    [string]$CheckpointBase64,
    [ValidateSet('corrupt-json','unsupported-schema','wrong-campaign')][string]$CheckpointFailureMode,
    [string]$SettlementId,
    [string]$AlleyTag,
    [ValidateSet('natural','noVolunteers','availableVolunteers')][string]$AlleyVolunteerScenario = 'natural',
    [double]$X,
    [double]$Y,
    [ValidateSet('land')][string]$Surface,
    [string]$PartyId,
    [ValidateSet('HelpDefenders','HelpAttackers','Neutral')][string]$RelationProfile,
    [int]$UpgradeTargetIndex = -1,
    [string]$AttachedPartyId,
    [int]$AgentIndex = -1,
    [string]$MenuId,
    [string]$OptionId,
    [int]$OptionIndex = -1,
    [string]$InquiryToken,
    [ValidateSet('affirmative','negative')][string]$InquiryChoice,
    [string]$Text,
    [string[]]$SelectedIds,
    [string]$OwnerId,
    [string]$TroopId,
    [switch]$ConfirmPartySizeWarning,
    [switch]$ConfirmPrisonerLimitWarning,
    [ValidateSet('members','prisoners')][string]$LootType,
    [ValidateSet('alley','mainParty')][string]$RosterSide,
    [ValidateSet('quest','mainParty')][string]$QuestTroopSourceSide,
    [int]$VolunteerSlot = -1,
    [string]$ItemId,
    [string]$Direction,
    [string]$OutputPath,
    [string]$HeroId,
    [string]$RoleId,
    [string]$ItemViewModelId,
    [ValidateSet('PlayerInventory','OtherInventory')][string]$InventorySide,
    [string]$BarterCandidateId,
    [string]$ExpectedSessionId,
    [string]$ExpectedProposalFingerprint,
    [ValidateSet('offer','setAmount','remove')][string]$BarterOperation,
    [int]$EquipmentIndex = -1,
    [int]$GoldOffset = 1,
    [string]$SkillId,
    [string]$QuestId,
    [int]$Count = 1,
    [int]$Amount = 1,
    [double]$Days = 0.01,
    [double]$DurationSeconds = 0,
    [string]$CommandId,
    [string]$ExpectedNativeSessionId,
    [int]$TimeoutSeconds = 180,
    [switch]$ReturnWhenAccepted,
    [Alias('json')]
    [switch]$AsJson
)

. (Join-Path $PSScriptRoot 'HarnessShaderCacheDialog.ps1')
. (Join-Path $PSScriptRoot 'HarnessStartupEvidence.ps1')

$ErrorActionPreference = 'Stop'
$localSettingsPath = Join-Path $PSScriptRoot 'harness.local.json'
$localSettings = if (Test-Path -LiteralPath $localSettingsPath -PathType Leaf) {
    Get-Content -LiteralPath $localSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
} else { $null }
$configuredGameRoot = if ($env:CHRONICLE_GAME_ROOT -and (Test-Path -LiteralPath $env:CHRONICLE_GAME_ROOT)) {
    [IO.Path]::GetFullPath($env:CHRONICLE_GAME_ROOT)
} elseif ($localSettings -and $localSettings.gameRoot -and (Test-Path -LiteralPath ([string]$localSettings.gameRoot))) {
    [IO.Path]::GetFullPath([string]$localSettings.gameRoot)
} else {
    Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}
$gameRoot = [IO.Path]::GetFullPath($configuredGameRoot)
$binDirectory = Join-Path $gameRoot 'bin\Win64_Shipping_Client'
$launcher = Join-Path $binDirectory 'Bannerlord.BLSE.Standalone.exe'
$steamRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $gameRoot))
$documentsPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
if ([string]::IsNullOrWhiteSpace($documentsPath)) { throw 'Windows Documents directory could not be resolved for the Native protocol.' }
$documentsRoot = Join-Path $documentsPath 'Mount and Blade II Bannerlord'
$saveDirectory = Join-Path $documentsRoot 'Game Saves'
$diagnosticLog = Join-Path $documentsRoot 'Configs\ModLogs\chronicle-framework.log'
$engineConfig = Join-Path $documentsRoot 'Configs\engine_config.txt'
$protocolRoot = Join-Path $documentsRoot 'AgentRuns\ChronicleAgent'
$engineConfigBackupPath = Join-Path $protocolRoot 'engine_config.chronicle-backup'
$responseRoot = Join-Path $protocolRoot 'responses'
$commandPath = Join-Path $protocolRoot 'command.json'
$sessionPath = Join-Path $protocolRoot 'session.json'
New-Item -ItemType Directory -Force -Path $protocolRoot,$responseRoot | Out-Null
. (Join-Path $PSScriptRoot 'Agent-SaveMetadata.ps1')
. (Join-Path $PSScriptRoot 'Test-WindowLayout.ps1')

function Set-SafeExitMarker {
    if (Test-Path $engineConfig) {
        $engineText = Get-Content $engineConfig -Raw
        $engineText = $engineText -replace 'safely_exited\s*=\s*0', 'safely_exited = 1'
        Set-Content -Path $engineConfig -Value $engineText -NoNewline
    }
}

function Restore-ChronicleTestEngineConfig([string]$BackupPath) {
    if ([string]::IsNullOrWhiteSpace($BackupPath) -or -not (Test-Path -LiteralPath $BackupPath -PathType Leaf)) { return $false }
    $allowedRoot = [IO.Path]::GetFullPath($protocolRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $backupFullPath = [IO.Path]::GetFullPath($BackupPath)
    if (-not $backupFullPath.StartsWith($allowedRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Engine-config recovery snapshot must remain inside the Chronicle Agent protocol directory.' }
    Copy-Item -LiteralPath $backupFullPath -Destination $engineConfig -Force
    Set-SafeExitMarker
    Remove-Item -LiteralPath $backupFullPath -Force
    [void](Restore-ChronicleHarnessGameSound)
    return $true
}

function Ensure-ChronicleSteamClient([int]$TimeoutSeconds = 45) {
    Ensure-ChronicleSteamClientReady -SteamRoot $steamRoot -TimeoutSeconds $TimeoutSeconds
}

function Write-Result($Value) {
    $json = $Value | ConvertTo-Json -Depth 8
    $builder = New-Object System.Text.StringBuilder
    foreach ($character in $json.ToCharArray()) {
        if ([int]$character -gt 127) { [void]$builder.AppendFormat('\u{0:X4}', [int]$character) }
        else { [void]$builder.Append($character) }
    }
    $builder.ToString()
}

function Write-ChronicleStartupTrace {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Stage,
        [int]$RootProcessId = 0,
        [int]$ProcessId = 0,
        [hashtable]$Details = @{}
    )
    try {
        $record = [ordered]@{
            utc = [DateTime]::UtcNow.ToString('O')
            stage = $Stage
            rootProcessId = $RootProcessId
            processId = $ProcessId
        }
        foreach ($key in $Details.Keys) { $record[[string]$key] = $Details[$key] }
        Add-Content -LiteralPath $Path -Value ($record | ConvertTo-Json -Compress -Depth 5) -Encoding UTF8
    }
    catch { }
}

if ($Action -eq 'recoverTestConfig') {
    if (Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue) { throw 'Refusing to restore test engine settings while a Bannerlord client is running.' }
    $restored = Restore-ChronicleTestEngineConfig -BackupPath $engineConfigBackupPath
    $engineText = if (Test-Path -LiteralPath $engineConfig) { Get-Content -LiteralPath $engineConfig -Raw } else { '' }
    $maxFrameMatch = [regex]::Match($engineText, '(?m)^max_framerate\s*=\s*(\d+)')
    Write-Result ([ordered]@{ action = 'recoverTestConfig'; status = 'completed'; restored = [bool]$restored; maxFramerate = if ($maxFrameMatch.Success) { [int]$maxFrameMatch.Groups[1].Value } else { $null } })
    exit 0
}

function Get-Session {
    if (-not (Test-Path $sessionPath)) { throw 'No active Chronicle Agent session.' }
    $session = Get-Content $sessionPath -Raw | ConvertFrom-Json
    if (-not (Get-Process -Id $session.processId -ErrorAction SilentlyContinue)) {
        if ($session.engineConfigBackupPath) { Restore-ChronicleTestEngineConfig -BackupPath ([string]$session.engineConfigBackupPath) | Out-Null }
        Remove-Item -LiteralPath $sessionPath -Force -ErrorAction SilentlyContinue
        throw "Chronicle Agent session process $($session.processId) is not running."
    }
    return $session
}

function Get-DescendantProcessIds([int]$ParentId) {
    $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId = $ParentId" -ErrorAction SilentlyContinue)
    foreach ($child in $children) {
        [int]$child.ProcessId
        Get-DescendantProcessIds -ParentId $child.ProcessId
    }
}

function Stop-AgentProcessTree([int]$RootProcessId) {
    $descendants = @(Get-DescendantProcessIds -ParentId $RootProcessId)
    foreach ($id in @($descendants + $RootProcessId) | Where-Object { $_ } | Select-Object -Unique) {
        Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
    }
    $deadline = (Get-Date).AddSeconds(15)
    do {
        $remaining = @($descendants + $RootProcessId | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue })
        if ($remaining.Count -eq 0) { return $true }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    return $false
}

function Stop-ChronicleStartupProcessTree([int]$RootProcessId, [int[]]$KnownProcessIds = @()) {
    $descendants = @(Get-DescendantProcessIds -ParentId $RootProcessId)
    $targets = @($descendants + $KnownProcessIds + $RootProcessId | Where-Object { $_ } | Select-Object -Unique)
    foreach ($id in $targets) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue }
    $deadline = (Get-Date).AddSeconds(15)
    do {
        $remaining = @($targets | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue })
        if ($remaining.Count -eq 0) { return $true }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    return $false
}

function Invoke-ProtocolCommand([string]$ProtocolAction, [hashtable]$Arguments = @{}, [switch]$ReturnWhenAccepted) {
    $session = Get-Session
    $id = if ($CommandId) { $CommandId } else { 'cli-' + [Guid]::NewGuid().ToString('N') }
    $payload = [ordered]@{ id = $id; action = $ProtocolAction }
    if (-not [string]::IsNullOrEmpty($ExpectedNativeSessionId)) { $payload.expectedNativeSessionId = $ExpectedNativeSessionId }
    foreach ($key in $Arguments.Keys) { $payload[$key] = $Arguments[$key] }
    $expectedStatus = if ($ReturnWhenAccepted) { 'accepted' } else { 'completed' }
    $responsePath = Join-Path $responseRoot "$id.$expectedStatus.json"
    $temporaryPath = "$commandPath.$id.tmp"
    $payload | ConvertTo-Json -Compress | Set-Content -Path $temporaryPath -Encoding UTF8
    Move-Item -LiteralPath $temporaryPath -Destination $commandPath -Force
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path $responsePath) {
            return Get-Content $responsePath -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        foreach ($terminalStatus in @('failed','rejected')) {
            $terminalPath = Join-Path $responseRoot "$id.$terminalStatus.json"
            if (Test-Path $terminalPath) {
                return Get-Content $terminalPath -Raw -Encoding UTF8 | ConvertFrom-Json
            }
        }
        if (-not (Get-Process -Id $session.processId -ErrorAction SilentlyContinue)) {
            throw "Game process $($session.processId) exited before command '$id' completed."
        }
        Start-Sleep -Milliseconds 100
    }
    throw "Command '$id' timed out after $TimeoutSeconds seconds."
}

if ($Action -in @('start','load')) {
    if (-not $SaveName) { throw '-SaveName is required for start/load in the P2 campaign prototype.' }
    $savePath = Join-Path $saveDirectory "$SaveName.sav"
    if (-not (Test-Path $savePath)) { throw "Save not found: $savePath" }
    $processNames = @('Bannerlord','Bannerlord.BLSE.Standalone','TaleWorlds.MountAndBlade.Launcher')
    $shutdownDeadline = (Get-Date).AddSeconds(15)
    do {
        $runningGame = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -in $processNames })
        if ($runningGame.Count -eq 0) { break }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $shutdownDeadline)
    if ($runningGame.Count -gt 0) { throw "Bannerlord is already running: $($runningGame.ProcessName -join ', ')." }
    if (Test-Path -LiteralPath $engineConfigBackupPath -PathType Leaf) { Restore-ChronicleTestEngineConfig -BackupPath $engineConfigBackupPath | Out-Null }
    $engineConfigBackupCreated = $false
    $modules = @(Get-AgentSaveModuleIds -SavePath $savePath)
    $installedModuleIds = @()
    foreach ($moduleDirectory in Get-ChildItem -LiteralPath (Join-Path $gameRoot 'Modules') -Directory) {
        $moduleManifestPath = Join-Path $moduleDirectory.FullName 'SubModule.xml'
        if (-not (Test-Path -LiteralPath $moduleManifestPath)) { continue }
        try { $installedModuleIds += [string]([xml](Get-Content -LiteralPath $moduleManifestPath -Raw -Encoding UTF8)).Module.Id.value }
        catch { }
    }
    if ($IncludeChronicleFramework -and 'ChronicleFramework' -notin $modules) {
        if ('ChronicleFramework' -notin $installedModuleIds) { throw 'ChronicleFramework was requested for this disposable save load but is not installed in the configured game root.' }
        $modules += 'ChronicleFramework'
    }
    $missingSaveModules = @($modules | Where-Object { $_ -notin $installedModuleIds })
    if ($missingSaveModules.Count -gt 0) { throw "Save requires modules that are not installed in the configured game root: $($missingSaveModules -join ', ')." }
    $steamStatus = Ensure-ChronicleSteamClient
    $moduleArgument = '_MODULES_*' + ($modules -join '*') + '*_MODULES_'
    $diagnosticStartLineCount = if (Test-Path $diagnosticLog) { @(Get-Content $diagnosticLog).Count } else { 0 }
    $diagnosticReadOffset = if (Test-Path -LiteralPath $diagnosticLog -PathType Leaf) { [long](Get-Item -LiteralPath $diagnosticLog).Length } else { 0L }
    $diagnosticPendingText = ''
    $startupTelemetry = [System.Collections.Generic.List[string]]::new()
    $startupDialogSnapshots = [System.Collections.Generic.List[object]]::new()
    $startupFault = $null
    $expectedHarnessMode = if ([string]::IsNullOrWhiteSpace($env:CHRONICLE_HARNESS_MODE)) { 'normal' } else { $env:CHRONICLE_HARNESS_MODE }
    if (Test-Path -LiteralPath $engineConfig -PathType Leaf) {
        Copy-Item -LiteralPath $engineConfig -Destination $engineConfigBackupPath -Force
        $engineConfigBackupCreated = $true
    }
    try {
        Set-ChronicleTestDisplayConfig -EngineConfigPath $engineConfig
        $gameSoundGuard = Disable-ChronicleHarnessGameSound
        Set-SafeExitMarker
        $process = Start-ChronicleSteamGame -FilePath $launcher -ArgumentList "/continuesave $SaveName $moduleArgument /anticheat" -WorkingDirectory $binDirectory -WindowStyle Minimized
        $startupTraceDirectory = if (-not [string]::IsNullOrWhiteSpace($env:CHRONICLE_HARNESS_TEMP)) { $env:CHRONICLE_HARNESS_TEMP } else { $protocolRoot }
        New-Item -ItemType Directory -Force -Path $startupTraceDirectory | Out-Null
        $startupProgressPath = Join-Path $startupTraceDirectory "agent-cli-startup-$($process.Id).jsonl"
        Write-ChronicleStartupTrace -Path $startupProgressPath -Stage 'process-launched' -RootProcessId $process.Id -ProcessId $process.Id -Details @{ saveName = $SaveName; harnessMode = $expectedHarnessMode }
    }
    catch {
        if ($engineConfigBackupCreated) { Restore-ChronicleTestEngineConfig -BackupPath $engineConfigBackupPath | Out-Null }
        throw
    }
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $ready = $false
    $readyProcessId = 0
    $windowLayout = $null
    $lastWindowLayoutAttemptUtc = [DateTime]::MinValue
    $lastProgressTraceUtc = [DateTime]::UtcNow
    $startupDialogReceipts = [System.Collections.Generic.List[object]]::new()
    $observedStartupProcessIds = [System.Collections.Generic.HashSet[int]]::new()
    [void]$observedStartupProcessIds.Add([int]$process.Id)
    $launchStartedUtc = $process.StartTime.ToUniversalTime()
    $programDataLogs = Join-Path $env:ProgramData 'Mount and Blade II Bannerlord\logs'
    while ((Get-Date) -lt $deadline) {
        $traceThisStartupCycle = ([DateTime]::UtcNow - $lastProgressTraceUtc).TotalSeconds -ge 5
        if ($traceThisStartupCycle) {
            $lastProgressTraceUtc = [DateTime]::UtcNow
            Write-ChronicleStartupTrace -Path $startupProgressPath -Stage 'startup-loop-enter' -RootProcessId $process.Id -ProcessId $process.Id
        }
        $launchProcess = Get-Process -Id $process.Id -ErrorAction SilentlyContinue
        $currentDescendants = @(Get-DescendantProcessIds -ParentId $process.Id)
        foreach ($descendantId in $currentDescendants) { [void]$observedStartupProcessIds.Add([int]$descendantId) }
        $startedBannerlordProcesses = @(Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue | Where-Object {
            try { $_.StartTime.ToUniversalTime() -ge $launchStartedUtc.AddSeconds(-1) } catch { $false }
        })
        foreach ($bannerlordProcess in $startedBannerlordProcesses) { [void]$observedStartupProcessIds.Add([int]$bannerlordProcess.Id) }
        if (-not $launchProcess) { $launchProcess = $startedBannerlordProcesses | Select-Object -First 1 }
        if (-not $launchProcess) { break }
        if ($traceThisStartupCycle) { Write-ChronicleStartupTrace -Path $startupProgressPath -Stage 'startup-loop-process-discovery-complete' -RootProcessId $process.Id -ProcessId $launchProcess.Id -Details @{ elapsedSeconds = [Math]::Round(([DateTime]::UtcNow - $launchStartedUtc).TotalSeconds, 1); observedProcessIds = @($observedStartupProcessIds) } }
        $crashCandidate = $null
        $crashTail = @()
        $unhandledException = @()
        foreach ($candidateId in @($observedStartupProcessIds)) {
            $candidateProcess = Get-Process -Id $candidateId -ErrorAction SilentlyContinue
            if (-not $candidateProcess -or $candidateProcess.ProcessName -notlike 'Bannerlord*') { continue }
            $candidateCrashLog = Join-Path $programDataLogs "rgl_log_errors_$candidateId.txt"
            if (-not (Test-Path -LiteralPath $candidateCrashLog -PathType Leaf)) { continue }
            $candidateTail = @()
            try { $candidateTail = @(Get-Content -LiteralPath $candidateCrashLog -Tail 100 -Encoding UTF8) } catch { }
            $candidateException = @($candidateTail | Where-Object { $_ -match 'Unhandled Exception Code 0x[0-9A-Fa-f]+' } | Select-Object -Last 1)
            if ($candidateException.Count -gt 0) {
                $crashCandidate = $candidateProcess
                $crashTail = $candidateTail
                $unhandledException = $candidateException
                break
            }
        }
        if ($traceThisStartupCycle) { Write-ChronicleStartupTrace -Path $startupProgressPath -Stage 'startup-loop-crash-scan-complete' -RootProcessId $process.Id -ProcessId $launchProcess.Id }
        if ($crashCandidate) {
                $crashEvidenceRoot = if (-not [string]::IsNullOrWhiteSpace($env:CHRONICLE_HARNESS_TEMP)) { $env:CHRONICLE_HARNESS_TEMP } else { $protocolRoot }
                New-Item -ItemType Directory -Force -Path $crashEvidenceRoot | Out-Null
                $crashEvidencePath = Join-Path $crashEvidenceRoot "startup-crash-$($crashCandidate.Id).json"
                $rglPath = Join-Path $programDataLogs "rgl_log_$($crashCandidate.Id).txt"
                $crashEvidence = [ordered]@{
                    Detected = $true
                    RootProcessId = $process.Id
                    ExceptionProcessId = $crashCandidate.Id
                    SaveName = $SaveName
                    ActiveModules = $modules
                    ExceptionLine = [string]$unhandledException[0]
                    ErrorLogTail = $crashTail
                    RglLogTail = if (Test-Path -LiteralPath $rglPath -PathType Leaf) { @(Get-Content -LiteralPath $rglPath -Tail 80 -Encoding UTF8) } else { @() }
                    DetectedUtc = [DateTime]::UtcNow.ToString('O')
                }
                $crashEvidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $crashEvidencePath -Encoding UTF8
                $crashStopped = Stop-ChronicleStartupProcessTree -RootProcessId $process.Id -KnownProcessIds @($observedStartupProcessIds)
                if ($crashStopped) {
                    Set-SafeExitMarker
                    if ($engineConfigBackupCreated) { Restore-ChronicleTestEngineConfig -BackupPath $engineConfigBackupPath | Out-Null }
                }
                throw "Bannerlord reported an unhandled startup exception. Test-owned processStopped=$crashStopped; crash evidence: $crashEvidencePath. No model request was sent."
        }
        if ($launchProcess.MainWindowTitle -match '^Mod change detected$') {
            try {
                $dialogResult = Invoke-ChronicleShaderCacheDialogAcknowledgement -ProcessId $launchProcess.Id -WindowHandle $launchProcess.MainWindowHandle
            }
            catch {
                $dialogEvidenceDirectory = if (-not [string]::IsNullOrWhiteSpace($env:CHRONICLE_HARNESS_TEMP)) { $env:CHRONICLE_HARNESS_TEMP } else { $protocolRoot }
                New-Item -ItemType Directory -Force -Path $dialogEvidenceDirectory | Out-Null
                $dialogEvidencePath = Join-Path $dialogEvidenceDirectory "startup-dialog-$($launchProcess.Id).json"
                [pscustomobject]@{ Handled = $false; ProcessId = $launchProcess.Id; WindowTitle = $launchProcess.MainWindowTitle; Error = $_.Exception.Message } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $dialogEvidencePath -Encoding UTF8
                $launchStopped = Stop-ChronicleStartupProcessTree -RootProcessId $process.Id -KnownProcessIds @($observedStartupProcessIds)
                Set-SafeExitMarker
                if ($launchStopped -and $engineConfigBackupCreated) { Restore-ChronicleTestEngineConfig -BackupPath $engineConfigBackupPath | Out-Null }
                throw "Safe handling of the known shader-cache prompt failed before confirmation. The test-owned game process was stopped; evidence: $dialogEvidencePath. Cause: $($_.Exception.Message)"
            }
            $startupDialogReceipts.Add($dialogResult)
            $dialogEvidenceDirectory = if (-not [string]::IsNullOrWhiteSpace($env:CHRONICLE_HARNESS_TEMP)) { $env:CHRONICLE_HARNESS_TEMP } else { $protocolRoot }
            New-Item -ItemType Directory -Force -Path $dialogEvidenceDirectory | Out-Null
            $dialogEvidencePath = Join-Path $dialogEvidenceDirectory "startup-dialog-$($launchProcess.Id).json"
            $dialogResult | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $dialogEvidencePath -Encoding UTF8
            if (-not $dialogResult.Handled) {
                $launchStopped = Stop-ChronicleStartupProcessTree -RootProcessId $process.Id -KnownProcessIds @($observedStartupProcessIds)
                Set-SafeExitMarker
                if ($launchStopped -and $engineConfigBackupCreated) { Restore-ChronicleTestEngineConfig -BackupPath $engineConfigBackupPath | Out-Null }
                $actionSummary = @($dialogResult.ActionNames) -join ', '
                throw "Campaign launch stopped at 'Mod change detected'; this is not evidence of incompatible save modules. Safely captured UIA actions='$actionSummary', reason='$($dialogResult.Reason)'. Full dialog evidence: $dialogEvidencePath. No global keyboard or mouse input was sent."
            }
            continue
        }
        if ($launchProcess.MainWindowTitle -ceq 'Warning') {
            try {
                $warningSnapshot = Get-ChronicleWindowAutomationSnapshot -ProcessId $launchProcess.Id -WindowHandle $launchProcess.MainWindowHandle
                $startupDialogSnapshots.Add((ConvertTo-ChronicleStartupDialogEvidence -Snapshot $warningSnapshot))
                $startupFault = if ($warningSnapshot.DialogText -match '(?i)Unable to initialize Steam API') { 'Bannerlord reports that the Steam API could not initialize; see startup dialog evidence.' } else { 'Bannerlord is blocked by an unclassified Warning dialog; no button was pressed.' }
            }
            catch { $startupFault = "Bannerlord Warning dialog could not be read safely: $($_.Exception.Message)" }
            break
        }
        if ($traceThisStartupCycle) { Write-ChronicleStartupTrace -Path $startupProgressPath -Stage 'startup-loop-dialog-check-complete' -RootProcessId $process.Id -ProcessId $launchProcess.Id }
        $windowAttemptDue = ([DateTime]::UtcNow - $lastWindowLayoutAttemptUtc).TotalSeconds -ge 2
        if ((-not $windowLayout -or -not $windowLayout.Applied) -and $windowAttemptDue) {
            $lastWindowLayoutAttemptUtc = [DateTime]::UtcNow
            Write-ChronicleStartupTrace -Path $startupProgressPath -Stage 'window-layout-attempt-start' -RootProcessId $process.Id -ProcessId $launchProcess.Id -Details @{ windowTitle = [string]$launchProcess.MainWindowTitle }
            $candidateLayout = Set-ChronicleTestWindow -ProcessId $launchProcess.Id
            Write-ChronicleStartupTrace -Path $startupProgressPath -Stage 'window-layout-attempt-finished' -RootProcessId $process.Id -ProcessId $launchProcess.Id -Details @{ layout = $candidateLayout }
            if ($candidateLayout -and $candidateLayout.Applied) { $windowLayout = $candidateLayout }
        }
        if ($traceThisStartupCycle) { Write-ChronicleStartupTrace -Path $startupProgressPath -Stage 'startup-loop-before-telemetry-read' -RootProcessId $process.Id -ProcessId $launchProcess.Id }
        if (Test-Path $diagnosticLog) {
            $diagnosticStream = $null
            $diagnosticReader = $null
            try {
                $diagnosticStream = [IO.File]::Open($diagnosticLog, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
                if ($diagnosticStream.Length -lt $diagnosticReadOffset) { $diagnosticReadOffset = 0; $diagnosticPendingText = '' }
                if ($diagnosticStream.Length -gt $diagnosticReadOffset) {
                    $diagnosticStream.Position = $diagnosticReadOffset
                    $diagnosticReader = [IO.StreamReader]::new($diagnosticStream, [Text.Encoding]::UTF8, $true, 1024, $true)
                    $appendedText = $diagnosticReader.ReadToEnd()
                    $diagnosticReadOffset = $diagnosticStream.Length
                    $combinedTelemetry = [string]$diagnosticPendingText + [string]$appendedText
                    $telemetryParts = @($combinedTelemetry -split "`r?`n")
                    if ($combinedTelemetry.EndsWith("`n") -or $combinedTelemetry.EndsWith("`r")) {
                        $newLines = $telemetryParts
                        $diagnosticPendingText = ''
                    }
                    elseif ($telemetryParts.Count -gt 1) {
                        $newLines = @($telemetryParts | Select-Object -First ($telemetryParts.Count - 1))
                        $diagnosticPendingText = [string]$telemetryParts[-1]
                    }
                    else {
                        $newLines = @()
                        $diagnosticPendingText = $combinedTelemetry
                    }
                    foreach ($line in $newLines) { if (-not [string]::IsNullOrWhiteSpace([string]$line)) { $startupTelemetry.Add([string]$line) } }
                    $readyLine = @($newLines | Where-Object { $_ -match "\|pid=\d+\|campaign-loaded\|mode=$([regex]::Escape($expectedHarnessMode))\|" } | Select-Object -Last 1)
                    if ($readyLine.Count -gt 0) {
                        $readyPidMatch = [regex]::Match([string]$readyLine[0], '\|pid=(\d+)\|campaign-loaded\|')
                        if ($readyPidMatch.Success) {
                            $candidateReadyPid = [int]$readyPidMatch.Groups[1].Value
                            $candidateReadyProcess = Get-Process -Id $candidateReadyPid -ErrorAction SilentlyContinue
                            if ($candidateReadyProcess -and $candidateReadyProcess.ProcessName -like 'Bannerlord*' -and $candidateReadyPid -in @($observedStartupProcessIds)) {
                                $ready = $true
                                $readyProcessId = $candidateReadyPid
                                Write-ChronicleStartupTrace -Path $startupProgressPath -Stage 'campaign-loaded-marker-observed' -RootProcessId $process.Id -ProcessId $candidateReadyPid -Details @{ marker = [string]$readyLine[0] }
                            }
                        }
                    }
                }
            }
            catch { }
            finally {
                if ($diagnosticReader) { $diagnosticReader.Dispose() }
                if ($diagnosticStream) { $diagnosticStream.Dispose() }
            }
        }
        if ($traceThisStartupCycle) { Write-ChronicleStartupTrace -Path $startupProgressPath -Stage 'startup-loop-telemetry-read-complete' -RootProcessId $process.Id -ProcessId $launchProcess.Id -Details @{ ready = $ready; readyProcessId = $readyProcessId } }
        if ($ready) { break }
        Start-Sleep -Milliseconds 250
    }
    if (-not $ready) {
        $startupProcess = Get-Process -Id $process.Id -ErrorAction SilentlyContinue
        if (-not $startupProcess) { $startupProcess = @($observedStartupProcessIds | ForEach-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue } | Where-Object { $_ } | Select-Object -First 1) }
        $startupEvidenceProcessId = [int]$process.Id
        foreach ($candidateId in @($observedStartupProcessIds)) {
            if (Test-Path -LiteralPath (Join-Path $programDataLogs "rgl_log_errors_$candidateId.txt") -PathType Leaf) { $startupEvidenceProcessId = [int]$candidateId }
        }
        $programDataLogs = Join-Path $env:ProgramData 'Mount and Blade II Bannerlord\logs'
        $rglPath = Join-Path $programDataLogs "rgl_log_$startupEvidenceProcessId.txt"
        $rglErrorPath = Join-Path $programDataLogs "rgl_log_errors_$startupEvidenceProcessId.txt"
        $watchdogPath = Join-Path $programDataLogs "watchdog_log_$startupEvidenceProcessId.txt"
        $telemetryLines = @()
        if (Test-Path -LiteralPath $diagnosticLog) {
            $allTelemetry = @(Get-Content -LiteralPath $diagnosticLog -Encoding UTF8)
            $telemetryLines = @($allTelemetry | Select-Object -Skip $diagnosticStartLineCount)
        }
        $startupEvidence = [ordered]@{
            RootProcessId = $process.Id
            ProcessId = $startupEvidenceProcessId
            SaveName = $SaveName
            MainWindowTitle = if ($startupProcess) { [string]$startupProcess.MainWindowTitle } else { $null }
            MainWindowHandle = if ($startupProcess) { [string]$startupProcess.MainWindowHandle } else { $null }
            ProcessRunningAtTimeout = [bool]$startupProcess
            ProcessCpuSeconds = if ($startupProcess) { [double]$startupProcess.CPU } else { $null }
            ExpectedHarnessMode = $expectedHarnessMode
            SteamClient = $steamStatus
            StartupFault = $startupFault
            StartupDialogReceipts = @($startupDialogReceipts)
            StartupDialogSnapshots = @($startupDialogSnapshots)
            ChronicleTelemetryAfterLaunch = $telemetryLines
            RglLogTail = if (Test-Path -LiteralPath $rglPath) { @(Get-Content -LiteralPath $rglPath -Tail 60 -Encoding UTF8) } else { @() }
            RglErrorLogTail = if (Test-Path -LiteralPath $rglErrorPath) { @(Get-Content -LiteralPath $rglErrorPath -Tail 60 -Encoding UTF8) } else { @() }
            WatchdogLogTail = if (Test-Path -LiteralPath $watchdogPath) { @(Get-Content -LiteralPath $watchdogPath -Tail 60 -Encoding UTF8) } else { @() }
            EngineConfigBackupPending = [bool]$engineConfigBackupCreated
        }
        $startupEvidenceDirectory = if (-not [string]::IsNullOrWhiteSpace($env:CHRONICLE_HARNESS_TEMP)) { $env:CHRONICLE_HARNESS_TEMP } else { $protocolRoot }
        New-Item -ItemType Directory -Force -Path $startupEvidenceDirectory | Out-Null
        $startupEvidencePath = Join-Path $startupEvidenceDirectory "startup-timeout-$startupEvidenceProcessId.json"
        $startupEvidence | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $startupEvidencePath -Encoding UTF8
        $launchStopped = Stop-ChronicleStartupProcessTree -RootProcessId $process.Id -KnownProcessIds @($observedStartupProcessIds)
        Set-SafeExitMarker
        if ($launchStopped -and $engineConfigBackupCreated) { Restore-ChronicleTestEngineConfig -BackupPath $engineConfigBackupPath | Out-Null }
        $startupFailureMessage = if ($startupFault) { [string]$startupFault } else { 'Campaign did not reach protocol-ready state.' }
        throw "$startupFailureMessage Startup evidence: $startupEvidencePath"
    }
    if ($readyProcessId -le 0) { throw 'Campaign reached a ready marker without recording its process identity.' }
    Write-ChronicleStartupTrace -Path $startupProgressPath -Stage 'window-layout-final-start' -RootProcessId $process.Id -ProcessId $readyProcessId
    $windowLayout = Set-ChronicleTestWindow -ProcessId $readyProcessId
    Write-ChronicleStartupTrace -Path $startupProgressPath -Stage 'window-layout-final-finished' -RootProcessId $process.Id -ProcessId $readyProcessId -Details @{ layout = $windowLayout }
    if (-not $windowLayout -or -not $windowLayout.Applied) {
        $launchStopped = Stop-ChronicleStartupProcessTree -RootProcessId $process.Id -KnownProcessIds @($observedStartupProcessIds)
        Set-SafeExitMarker
        if ($launchStopped -and $engineConfigBackupCreated) { Restore-ChronicleTestEngineConfig -BackupPath $engineConfigBackupPath | Out-Null }
        throw 'Windowed test layout was not verified.'
    }
    $performanceProfile = [ordered]@{ maxFramerate = 30; width = [int]$windowLayout.Width; height = [int]$windowLayout.Height; configRestoredAfterStop = [bool]$engineConfigBackupCreated }
    $session = [ordered]@{ protocolVersion = 1; processId = $readyProcessId; rootProcessId = $process.Id; observedProcessIds = @($observedStartupProcessIds); saveName = $SaveName; moduleSet = $modules; startedUtc = (Get-Date).ToUniversalTime().ToString('O'); windowLayout = $windowLayout; performanceProfile = $performanceProfile; steamClient = $steamStatus; engineConfigBackupPath = if ($engineConfigBackupCreated) { $engineConfigBackupPath } else { $null }; startupDialogReceipts = @($startupDialogReceipts) }
    $session | ConvertTo-Json | Set-Content -Path $sessionPath -Encoding UTF8
    Write-ChronicleStartupTrace -Path $startupProgressPath -Stage 'session-written' -RootProcessId $process.Id -ProcessId $readyProcessId -Details @{ sessionPath = $sessionPath }
    $configuredTimeout = $TimeoutSeconds
    $TimeoutSeconds = [Math]::Min(30, $TimeoutSeconds)
    try {
        Write-ChronicleStartupTrace -Path $startupProgressPath -Stage 'protocol-probe-start' -RootProcessId $process.Id -ProcessId $readyProcessId
        $protocolProbe = Invoke-ProtocolCommand 'state'
        if ($protocolProbe.status -ne 'completed' -or -not $protocolProbe.state) { throw 'Agent protocol returned no structured initial state.' }
        Write-ChronicleStartupTrace -Path $startupProgressPath -Stage 'protocol-probe-finished' -RootProcessId $process.Id -ProcessId $readyProcessId -Details @{ status = $protocolProbe.status }
    }
    catch {
        $handshakeError = $_.Exception.Message
        $launchStopped = Stop-ChronicleStartupProcessTree -RootProcessId $process.Id -KnownProcessIds @($observedStartupProcessIds)
        Set-SafeExitMarker
        if ($launchStopped -and $engineConfigBackupCreated) { Restore-ChronicleTestEngineConfig -BackupPath $engineConfigBackupPath | Out-Null }
        Remove-Item -LiteralPath $sessionPath -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $commandPath) {
            try { if ((Get-Content -LiteralPath $commandPath -Raw -Encoding UTF8 | ConvertFrom-Json).action -eq 'state') { Remove-Item -LiteralPath $commandPath -Force -ErrorAction SilentlyContinue } } catch { }
        }
        throw "Campaign-loaded marker appeared, but Agent Protocol handshake failed: $handshakeError"
    }
    finally { $TimeoutSeconds = $configuredTimeout }
    Write-Result ([ordered]@{ action = $Action; status = 'completed'; session = $session })
    exit 0
}

switch ($Action) {
    'state' { $result = Invoke-ProtocolCommand 'state' }
    'mapSettlementTargets' { $result = Invoke-ProtocolCommand 'mapSettlementTargets' }
    'mapNotifications' { $result = Invoke-ProtocolCommand 'mapNotifications' }
    'quickInformation' { $result = Invoke-ProtocolCommand 'quickInformation' }
    'sceneNotification' { $result = Invoke-ProtocolCommand 'sceneNotification' }
    'continueSceneNotification' { $result = Invoke-ProtocolCommand 'continueSceneNotification' }
    'incidentSelect' {
        if ($OptionIndex -lt 0) { throw '-OptionIndex must come from the current Native mapIncident.options observation.' }
        $result = Invoke-ProtocolCommand 'incidentSelect' @{ optionIndex = $OptionIndex }
    }
    'submitStoryModeClanName' { $result = Invoke-ProtocolCommand 'submitStoryModeClanName' @{ token = $InquiryToken; text = $Text } }
    'bannerEditorDone' { $result = Invoke-ProtocolCommand 'bannerEditorDone' }
    'mapPartyTargets' { $result = Invoke-ProtocolCommand 'mapPartyTargets' }
    'mapPartyComposition' {
        if (-not $PartyId) { throw '-PartyId is required and must be selected from a current mapPartyTargets observation.' }
        $result = Invoke-ProtocolCommand 'mapPartyComposition' @{ partyId = $PartyId }
    }
    'mapPartyBehavior' {
        if (-not $PartyId) { throw '-PartyId is required and must be selected from a current mapPartyTargets observation.' }
        $result = Invoke-ProtocolCommand 'mapPartyBehavior' @{ partyId = $PartyId }
    }
    'partyUpgradeOptions' { $result = Invoke-ProtocolCommand 'partyUpgradeOptions' }
    'upgradeTroop' {
        if (-not $TroopId) { throw '-TroopId is required and must be selected from the latest partyUpgradeOptions observation.' }
        if ($UpgradeTargetIndex -lt 0) { throw '-UpgradeTargetIndex must be selected from the latest partyUpgradeOptions observation.' }
        $result = Invoke-ProtocolCommand 'upgradeTroop' @{ troopId = $TroopId; upgradeTargetIndex = $UpgradeTargetIndex }
    }
    'prisonerRecruitmentOptions' { $result = Invoke-ProtocolCommand 'prisonerRecruitmentOptions' }
    'recruitPrisoner' {
        if (-not $TroopId) { throw '-TroopId is required and must be selected from the latest prisonerRecruitmentOptions observation.' }
        $result = Invoke-ProtocolCommand 'recruitPrisoner' @{ troopId = $TroopId; confirmPartySizeWarning = [int]$ConfirmPartySizeWarning.IsPresent; confirmPrisonerLimitWarning = [int]$ConfirmPrisonerLimitWarning.IsPresent }
    }
    'characterDevelopment' { $result = Invoke-ProtocolCommand 'characterDevelopment' }
    'questDetails' {
        if (-not $QuestId) { throw '-QuestId is required and must come from the current state.quests observation.' }
        $result = Invoke-ProtocolCommand 'questDetails' @{ questId = $QuestId }
    }
    'partyRoster' { $result = Invoke-ProtocolCommand 'partyRoster' }
    'partyRoles' { $result = Invoke-ProtocolCommand 'partyRoles' }
    'inventoryOpen' { $result = Invoke-ProtocolCommand 'inventoryOpen' }
    'heroEquipmentOptions' { $result = Invoke-ProtocolCommand 'heroEquipmentOptions' }
    'equipHeroItem' {
        if (-not $ItemViewModelId) { throw '-ItemViewModelId is required from the latest heroEquipmentOptions query.' }
        if ($EquipmentIndex -lt 0) { throw '-EquipmentIndex must come from the latest heroEquipmentOptions query.' }
        $result = Invoke-ProtocolCommand 'equipHeroItem' @{ itemViewModelId = $ItemViewModelId; equipmentIndex = $EquipmentIndex }
    }
    'unequipHeroItem' {
        if ($EquipmentIndex -lt 0) { throw '-EquipmentIndex must come from the latest heroEquipmentOptions query.' }
        $result = Invoke-ProtocolCommand 'unequipHeroItem' @{ equipmentIndex = $EquipmentIndex }
    }
    'inventoryConfirm' { $result = Invoke-ProtocolCommand 'inventoryConfirm' }
    'inventoryCancel' { $result = Invoke-ProtocolCommand 'inventoryCancel' }
    'inventoryCancelChanges' { $result = Invoke-ProtocolCommand 'inventoryCancelChanges' }
    'setPartyRole' {
        if (-not $RoleId) { throw '-RoleId is required for setPartyRole.' }
        if (-not $HeroId) { throw '-HeroId is required for setPartyRole and must come from the latest partyRoles observation.' }
        $result = Invoke-ProtocolCommand 'setPartyRole' @{ roleId = $RoleId; heroId = $HeroId }
    }
    'unassignPartyRole' {
        if (-not $RoleId) { throw '-RoleId is required for unassignPartyRole and must come from the latest partyRoles observation.' }
        $result = Invoke-ProtocolCommand 'unassignPartyRole' @{ roleId = $RoleId }
    }
    'harnessSeedPartyRoleFixture' { $result = Invoke-ProtocolCommand 'harnessSeedPartyRoleFixture' }
    'harnessPartyRoleDiagnostics' { $result = Invoke-ProtocolCommand 'harnessPartyRoleDiagnostics' }
    'harnessSeedEquipmentModifierFixture' { $result = Invoke-ProtocolCommand 'harnessSeedEquipmentModifierFixture' }
    'harnessClearEquipmentModifierFixture' { $result = Invoke-ProtocolCommand 'harnessClearEquipmentModifierFixture' }
    'harnessOpenInventoryState' { $result = Invoke-ProtocolCommand 'harnessOpenInventoryState' }
    'harnessCloseInventoryState' { $result = Invoke-ProtocolCommand 'harnessCloseInventoryState' }
    'harnessInventoryStateDiagnostics' { $result = Invoke-ProtocolCommand 'harnessInventoryStateDiagnostics' }
    'spendSkillFocus' {
        if (-not $SkillId) { throw '-SkillId is required and must come from the current characterDevelopment observation.' }
        $result = Invoke-ProtocolCommand 'spendSkillFocus' @{ skillId = $SkillId; count = $Count }
    }
    'harnessMissionDiagnostics' { $result = Invoke-ProtocolCommand 'harnessMissionDiagnostics' }
    'harnessMapDiagnostics' { $result = Invoke-ProtocolCommand 'harnessMapDiagnostics' @{ heroId = $HeroId } }
    'harnessOpenMapEscapeMenu' { $result = Invoke-ProtocolCommand 'harnessOpenMapEscapeMenu' }
    'harnessOpenNativeInquiry' { $result = Invoke-ProtocolCommand 'harnessOpenNativeInquiry' }
    'harnessOpenRecruitmentInquiry' {
        if (-not $OwnerId -or -not $TroopId -or $VolunteerSlot -lt 0) { throw '-OwnerId, -TroopId and -VolunteerSlot are required from current Native recruitOptions.' }
        $result = Invoke-ProtocolCommand 'harnessOpenRecruitmentInquiry' @{ ownerId = $OwnerId; troopId = $TroopId; slot = $VolunteerSlot }
    }
    'harnessNativeInquiryDiagnostics' { $result = Invoke-ProtocolCommand 'harnessNativeInquiryDiagnostics' }
    'harnessPrepareAlleyLeaderFixture' {
        if (-not $SettlementId) { throw '-SettlementId must come from the current visible settlement observation.' }
        $result = Invoke-ProtocolCommand 'harnessPrepareAlleyLeaderFixture' @{ settlementId = $SettlementId }
    }
    'harnessAlleyLeaderDiagnostics' {
        if (-not $SettlementId) { throw '-SettlementId is required for Alley fixture diagnostics.' }
        $result = Invoke-ProtocolCommand 'harnessAlleyLeaderDiagnostics' @{ settlementId = $SettlementId }
    }
    'harnessPrepareAlleyRosterFixture' {
        if (-not $SettlementId) { throw '-SettlementId must come from the current visible settlement observation.' }
        $arguments = @{ settlementId = $SettlementId; volunteerScenario = $AlleyVolunteerScenario }
        if ($MenuId) { $arguments.menuId = $MenuId }
        $result = Invoke-ProtocolCommand 'harnessPrepareAlleyRosterFixture' $arguments
    }
    'harnessSeedAlleyAttackFixture' {
        if (-not $SettlementId -or -not $AlleyTag) { throw '-SettlementId and -AlleyTag are required for the visual-only Alley attack fixture.' }
        $result = Invoke-ProtocolCommand 'harnessSeedAlleyAttackFixture' @{ settlementId = $SettlementId; alleyTag = $AlleyTag }
    }
    'harnessSeedPersuasionFixture' {
        if (-not $OptionId) { throw '-OptionId must come from the current visible Native Conversation.' }
        $result = Invoke-ProtocolCommand 'harnessSeedPersuasionFixture' @{ optionId = $OptionId }
    }
    'harnessCurrentConversationAnswers' {
        $result = Invoke-ProtocolCommand 'harnessCurrentConversationAnswers' @{}
    }
    'harnessAlleyRosterDiagnostics' {
        if (-not $SettlementId) { throw '-SettlementId is required for Alley roster fixture diagnostics.' }
        $result = Invoke-ProtocolCommand 'harnessAlleyRosterDiagnostics' @{ settlementId = $SettlementId; alleyTag = $AlleyTag; referenceHeroId = $HeroId }
    }
    'harnessPlayerSkillsDiagnostics' { $result = Invoke-ProtocolCommand 'harnessPlayerSkillsDiagnostics' }
    'harnessCharacterDevelopmentDiagnostics' { $result = Invoke-ProtocolCommand 'harnessCharacterDevelopmentDiagnostics' }
    'harnessQuestDetailsDiagnostics' {
        if (-not $QuestId) { throw '-QuestId is required for the Harness-only Quest Journal diagnostic.' }
        $result = Invoke-ProtocolCommand 'harnessQuestDetailsDiagnostics' @{ questId = $QuestId }
    }
    'harnessQuestDeadlinePrivacyDiagnostics' { $result = Invoke-ProtocolCommand 'harnessQuestDeadlinePrivacyDiagnostics' }
    'harnessPartyRosterDiagnostics' { $result = Invoke-ProtocolCommand 'harnessPartyRosterDiagnostics' }
    'harnessMapPartyDiagnostics' { $result = Invoke-ProtocolCommand 'harnessMapPartyDiagnostics' }
    'harnessMapPartyCompositionDiagnostics' {
        if (-not $PartyId) { throw '-PartyId is required for Harness-only map party composition diagnostics.' }
        $result = Invoke-ProtocolCommand 'harnessMapPartyCompositionDiagnostics' @{ partyId = $PartyId }
    }
    'harnessCreateMapArmyFixture' {
        if (-not $PartyId) { throw '-PartyId is required for the Harness-only native Army fixture.' }
        $armyCommand = @{ partyId = $PartyId }
        if ($AttachedPartyId) { $armyCommand.attachedPartyId = $AttachedPartyId }
        $result = Invoke-ProtocolCommand 'harnessCreateMapArmyFixture' $armyCommand
    }
    'harnessPrepareMovingArmyEncounter' {
        if (-not $PartyId) { throw '-PartyId is required from the current visible/inspected mapPartyTargets observation.' }
        $result = Invoke-ProtocolCommand 'harnessPrepareMovingArmyEncounter' @{ partyId = $PartyId }
    }
    'harnessArmyEncounterDiagnostics' {
        if (-not $PartyId) { throw '-PartyId is required for the current visual Harness Army Leader diagnostics.' }
        $result = Invoke-ProtocolCommand 'harnessArmyEncounterDiagnostics' @{ partyId = $PartyId }
    }
    'harnessPrepareSiegeJoinFixture' {
        if (-not $SettlementId) { throw '-SettlementId is required from the current visible mapSettlementTargets observation.' }
        $result = Invoke-ProtocolCommand 'harnessPrepareSiegeJoinFixture' @{ settlementId = $SettlementId }
    }
    'harnessSiegeJoinDiagnostics' {
        if (-not $SettlementId -or -not $PartyId) { throw '-SettlementId and -PartyId are required for Harness-only Native Siege diagnostics.' }
        $result = Invoke-ProtocolCommand 'harnessSiegeJoinDiagnostics' @{ settlementId = $SettlementId; armyLeaderPartyId = $PartyId }
    }
    'harnessSeedMapPartyIssueMarker' {
        if (-not $PartyId) { throw '-PartyId is required from the current mapPartyTargets observation.' }
        $result = Invoke-ProtocolCommand 'harnessSeedMapPartyIssueMarker' @{ partyId = $PartyId }
    }
    'harnessPrepareSafePassageFixture' { $result = Invoke-ProtocolCommand 'harnessPrepareSafePassageFixture' }
    'harnessSeedCaptivityObservationFixture' {
        if (-not $PartyId) { throw '-PartyId is required from the current Harness-created captor party.' }
        $result = Invoke-ProtocolCommand 'harnessSeedCaptivityObservationFixture' @{ partyId = $PartyId }
    }
    'harnessSeedPrisonCaptivityFixture' {
        if (-not $SettlementId) { throw '-SettlementId is required from the current Campaign settlement list.' }
        $result = Invoke-ProtocolCommand 'harnessSeedPrisonCaptivityFixture' @{ settlementId = $SettlementId }
    }
    'harnessPrepareSurrenderCondition' { $result = Invoke-ProtocolCommand 'harnessPrepareSurrenderCondition' }
    'harnessSeedTryGetAwayFixture' { $result = Invoke-ProtocolCommand 'harnessSeedTryGetAwayFixture' }
    'harnessTryGetAwayDiagnostics' { $result = Invoke-ProtocolCommand 'harnessTryGetAwayDiagnostics' }
    'harnessSeedNpcBattleForPlayerJoin' { $result = Invoke-ProtocolCommand 'harnessSeedNpcBattleForPlayerJoin' @{ relationProfile = if ($RelationProfile) { $RelationProfile } else { 'HelpDefenders' } } }
    'harnessPrepareArmyMemberForCurrentJoinEncounter' { $result = Invoke-ProtocolCommand 'harnessPrepareArmyMemberForCurrentJoinEncounter' }
    'harnessJoinEncounterDiagnostics' { $result = Invoke-ProtocolCommand 'harnessJoinEncounterDiagnostics' @{ partyId = $PartyId; armyLeaderPartyId = $AttachedPartyId } }
    'harnessSwitchCaptivityObservationMenu' { $result = Invoke-ProtocolCommand 'harnessSwitchCaptivityObservationMenu' }
    'harnessCaptivityDiagnostics' { $result = Invoke-ProtocolCommand 'harnessCaptivityDiagnostics' @{ partyId = $PartyId } }
    'harnessPreparePursuitVisibilityFixture' { $result = Invoke-ProtocolCommand 'harnessPreparePursuitVisibilityFixture' }
    'harnessSeedPartyUpgradeFixture' { $result = Invoke-ProtocolCommand 'harnessSeedPartyUpgradeFixture' }
    'harnessSeedPrisonerRecruitmentFixture' { $result = Invoke-ProtocolCommand 'harnessSeedPrisonerRecruitmentFixture' }
    'harnessSeedRecruitmentCapacityFixture' { $result = Invoke-ProtocolCommand 'harnessSeedRecruitmentCapacityFixture' }
    'harnessPrepareCompanionHiringFixture' {
        if (-not $HeroId) { throw '-HeroId is required from the current local Mission observation for this Harness fixture.' }
        if ($GoldOffset -lt 0 -or $GoldOffset -gt 1) { throw '-GoldOffset must be 0 (at quote price) or 1 (one gold above price) in Harness.' }
        $result = Invoke-ProtocolCommand 'harnessPrepareCompanionHiringFixture' @{ heroId = $HeroId; goldOffset = $GoldOffset }
    }
    'harnessCompanionHiringDiagnostics' {
        if (-not $HeroId) { throw '-HeroId is required for Harness-only companion hiring diagnostics.' }
        $result = Invoke-ProtocolCommand 'harnessCompanionHiringDiagnostics' @{ heroId = $HeroId }
    }
    'talkToSettlementHero' {
        if (-not $HeroId) { throw '-HeroId is required and must come from settlementOverlayCharacters in the current observation.' }
        $result = Invoke-ProtocolCommand 'talkToSettlementHero' @{ heroId = $HeroId }
    }
    'visitSettlementHero' {
        if (-not $HeroId) { throw '-HeroId is required and must come from settlementOverlayCharacters in the current observation.' }
        $result = Invoke-ProtocolCommand 'visitSettlementHero' @{ heroId = $HeroId }
    }
    'captureFrame' {
        if (-not $OutputPath) { throw '-OutputPath is required for captureFrame.' }
        $result = Invoke-ProtocolCommand 'captureFrame' @{ fileName = [IO.Path]::GetFileName($OutputPath) }
    }
    'inventoryTakeAll' { $result = Invoke-ProtocolCommand 'inventoryTakeAll' }
    'inventoryDone' { $result = Invoke-ProtocolCommand 'inventoryDone' }
    'seedVisualLoot' { $result = Invoke-ProtocolCommand 'seedVisualLoot' }
    'advance' { $result = Invoke-ProtocolCommand 'advance' @{ days = $Days } }
    'pause' { $result = Invoke-ProtocolCommand 'pause' }
    'resume' { $result = Invoke-ProtocolCommand 'resume' }
    'fastForward' { $result = Invoke-ProtocolCommand 'fastForward' }
    'move' {
        if (-not $SettlementId) { throw '-SettlementId is required for move.' }
        $result = Invoke-ProtocolCommand 'move' @{ settlementId = $SettlementId }
    }
    'moveToPoint' {
        if (-not $PSBoundParameters.ContainsKey('X') -or -not $PSBoundParameters.ContainsKey('Y') -or -not $Surface) { throw '-X, -Y and -Surface (land|sea) are required for moveToPoint.' }
        $result = Invoke-ProtocolCommand 'moveToPoint' @{ x = $X; y = $Y; surface = $Surface }
    }
    'missionInput' {
        if (-not $PSBoundParameters.ContainsKey('X') -or -not $PSBoundParameters.ContainsKey('Y')) { throw '-X and -Y are required for missionInput.' }
        $result = Invoke-ProtocolCommand 'missionInput' @{ x = $X; y = $Y; durationSeconds = $DurationSeconds }
    }
    'missionSceneAgents' { $result = Invoke-ProtocolCommand 'missionSceneAgents' @{} }
    'missionNavigateToAgent' {
        if ($AgentIndex -lt 0) { throw '-AgentIndex is required for missionNavigateToAgent.' }
        $result = Invoke-ProtocolCommand 'missionNavigateToAgent' @{ agentIndex = $AgentIndex; durationSeconds = $DurationSeconds }
    }
    'missionLeave' { $result = Invoke-ProtocolCommand 'missionLeave' @{} }
    'tournamentJoin' { $result = Invoke-ProtocolCommand 'tournamentJoin' }
    'tournamentSkipRound' { $result = Invoke-ProtocolCommand 'tournamentSkipRound' }
    'tournamentSkipAllRounds' { $result = Invoke-ProtocolCommand 'tournamentSkipAllRounds' }
    'tournamentWatchRound' { $result = Invoke-ProtocolCommand 'tournamentWatchRound' }
    'tournamentLeave' { $result = Invoke-ProtocolCommand 'tournamentLeave' }
    'missionInteract' {
        if ($AgentIndex -lt 0) { throw '-AgentIndex is required and must come from nearbySceneAgents in the current Mission observation.' }
        $result = Invoke-ProtocolCommand 'missionInteract' @{ agentIndex = $AgentIndex }
    }
    'missionCancelNavigation' { $result = Invoke-ProtocolCommand 'missionCancelNavigation' }
    'missionAimAt' {
        if ($AgentIndex -lt 0) { throw '-AgentIndex is required for missionAimAt.' }
        $result = Invoke-ProtocolCommand 'missionAimAt' @{ agentIndex = $AgentIndex }
    }
    'closeEscapeMenu' { $result = Invoke-ProtocolCommand 'closeEscapeMenu' }
    'respondInquiry' {
        if (-not $InquiryToken -or -not $InquiryChoice) { throw '-InquiryToken and -InquiryChoice are required from the current Native Inquiry observation.' }
        $result = Invoke-ProtocolCommand 'respondInquiry' @{ token = $InquiryToken; choice = $InquiryChoice }
    }
    'respondMultiSelectionInquiry' {
        if (-not $InquiryToken -or -not $InquiryChoice) { throw '-InquiryToken and -InquiryChoice are required from the current Native MultiSelection observation.' }
        $selectionIds = @()
        if ($SelectedIds) { $selectionIds = @($SelectedIds) }
        $result = Invoke-ProtocolCommand 'respondMultiSelectionInquiry' @{ token = $InquiryToken; choice = $InquiryChoice; selectedIds = $selectionIds }
    }
    'pursue' {
        if (-not $PartyId) { throw '-PartyId is required for pursue.' }
        $result = Invoke-ProtocolCommand 'pursue' @{ partyId = $PartyId }
    }
    'follow' {
        if (-not $PartyId) { throw '-PartyId is required for follow.' }
        $result = Invoke-ProtocolCommand 'follow' @{ partyId = $PartyId }
    }
    'hold' { $result = Invoke-ProtocolCommand 'hold' }
    'menu' { $result = Invoke-ProtocolCommand 'menu' }
    'menuSelect' {
        if (-not $MenuId -or -not $OptionId) { throw '-MenuId and -OptionId are required for menuSelect.' }
        $result = Invoke-ProtocolCommand 'menuSelect' @{ menuId = $MenuId; optionId = $OptionId }
    }
    'dialogueSelect' {
        if (-not $OptionId) { throw '-OptionId is required for dialogueSelect.' }
        $result = Invoke-ProtocolCommand 'dialogueSelect' @{ optionId = $OptionId }
    }
    'persuasionDetails' { $result = Invoke-ProtocolCommand 'persuasionDetails' }
    'dialogueContinue' { $result = Invoke-ProtocolCommand 'dialogueContinue' }
    'battlePause' { $result = Invoke-ProtocolCommand 'battlePause' }
    'battleSkip' { $result = Invoke-ProtocolCommand 'battleSkip' }
    'battleFinish' { $result = Invoke-ProtocolCommand 'battleFinish' }
    'battleRetreat' { $result = Invoke-ProtocolCommand 'battleRetreat' }
    'missionRetreat' { $result = Invoke-ProtocolCommand 'missionRetreat' }
    'partyTakeAll' {
        if (-not $LootType) { throw '-LootType is required for partyTakeAll.' }
        $result = Invoke-ProtocolCommand 'partyTakeAll' @{ troopType = $LootType }
    }
    'partyLootTransferOne' {
        if (-not $TroopId -or -not $LootType) { throw '-TroopId and -LootType (members|prisoners) from the current Native Loot PartyScreen are required for partyLootTransferOne.' }
        $result = Invoke-ProtocolCommand 'partyLootTransferOne' @{ troopId = $TroopId; troopType = $LootType }
    }
    'sellPrisonerOne' {
        if (-not $TroopId) { throw '-TroopId from the current Native Ransom PartyScreen is required for sellPrisonerOne.' }
        $result = Invoke-ProtocolCommand 'sellPrisonerOne' @{ troopId = $TroopId }
    }
    'partyScreenCancel' { $result = Invoke-ProtocolCommand 'partyScreenCancel' }
    'partyScreenDone' { $result = Invoke-ProtocolCommand 'partyScreenDone' }
    'questTroopTransfer' {
        if (-not $TroopId -or -not $QuestTroopSourceSide) { throw '-TroopId and -QuestTroopSourceSide from the current Native QuestTroopManage PartyScreen are required for questTroopTransfer.' }
        $result = Invoke-ProtocolCommand 'questTroopTransfer' @{ troopId = $TroopId; sourceSide = $QuestTroopSourceSide }
    }
    'questTroopScreenDone' { $result = Invoke-ProtocolCommand 'questTroopScreenDone' }
    'questTroopScreenCancel' { $result = Invoke-ProtocolCommand 'questTroopScreenCancel' }
    'alleyRosterTransfer' {
        if (-not $TroopId -or -not $RosterSide) { throw '-TroopId and -RosterSide from the current Native Alley PartyScreen are required for alleyRosterTransfer.' }
        $result = Invoke-ProtocolCommand 'alleyRosterTransfer' @{ troopId = $TroopId; sourceSide = $RosterSide }
    }
    'alleyRosterCancel' { $result = Invoke-ProtocolCommand 'alleyRosterCancel' }
    'rest' { $result = Invoke-ProtocolCommand 'rest' @{ days = $Days } -ReturnWhenAccepted:$ReturnWhenAccepted }
    'recruitOptions' { $result = Invoke-ProtocolCommand 'recruitOptions' }
    'recruit' {
        if (-not $OwnerId -or -not $TroopId -or $VolunteerSlot -lt 0) { throw '-OwnerId, -TroopId and -VolunteerSlot are required for recruit.' }
        $result = Invoke-ProtocolCommand 'recruit' @{ ownerId = $OwnerId; troopId = $TroopId; slot = $VolunteerSlot; confirmPartySizeWarning = [int]$ConfirmPartySizeWarning.IsPresent }
    }
    'foodOptions' { $result = Invoke-ProtocolCommand 'foodOptions' }
    'tradeOptions' { $result = Invoke-ProtocolCommand 'tradeOptions' }
    'tradeRumors' {
        if (-not $ItemViewModelId -or -not $InventorySide) { throw '-ItemViewModelId and -InventorySide from the current native tradeOptions result are required for tradeRumors.' }
        $result = Invoke-ProtocolCommand 'tradeRumors' @{ itemViewModelId = $ItemViewModelId; inventorySide = $InventorySide }
    }
    'harnessSeedTradeRumorFixture' { $result = Invoke-ProtocolCommand 'harnessSeedTradeRumorFixture' @{ itemViewModelId = $ItemViewModelId; inventorySide = $InventorySide } }
    'harnessSeedMapNotificationFixture' { $result = Invoke-ProtocolCommand 'harnessSeedMapNotificationFixture' }
    'harnessSeedMapIncidentFixture' { $result = Invoke-ProtocolCommand 'harnessSeedMapIncidentFixture' }
    'harnessSeedQuickInformationFixture' { $result = Invoke-ProtocolCommand 'harnessSeedQuickInformationFixture' }
    'harnessSeedSceneNotificationFixture' { $result = Invoke-ProtocolCommand 'harnessSeedSceneNotificationFixture' }
    'harnessTradeRumorTooltipDiagnostics' { $result = Invoke-ProtocolCommand 'harnessTradeRumorTooltipDiagnostics' @{ itemViewModelId = $ItemViewModelId; inventorySide = $InventorySide } }
    'trade' {
        if ($Direction -notin @('buy','sell') -or -not $ItemViewModelId -or -not $InventorySide -or $Amount -le 0) { throw '-Direction, -ItemViewModelId, -InventorySide and positive -Amount from the current native tradeOptions result are required for trade.' }
        $result = Invoke-ProtocolCommand 'trade' @{ direction = $Direction; itemViewModelId = $ItemViewModelId; inventorySide = $InventorySide; amount = $Amount }
    }
    'provision' {
        if (-not $ItemViewModelId -or $Amount -le 0) { throw '-ItemViewModelId and a positive -Amount from the current native foodOptions result are required for provision.' }
        $result = Invoke-ProtocolCommand 'provision' @{ itemViewModelId = $ItemViewModelId; amount = $Amount }
    }
    'tradeConfirm' { $result = Invoke-ProtocolCommand 'tradeConfirm' }
    'tradeCancel' { $result = Invoke-ProtocolCommand 'tradeCancel' }
    'tradeCancelChanges' { $result = Invoke-ProtocolCommand 'tradeCancelChanges' }
    'barterOptions' { $result = Invoke-ProtocolCommand 'barterOptions' }
    'barterEdit' {
        if (-not $BarterCandidateId -or -not $BarterOperation) { throw '-BarterCandidateId and -BarterOperation are required for barterEdit.' }
        $result = Invoke-ProtocolCommand 'barterEdit' @{ barterCandidateId = $BarterCandidateId; barterOperation = $BarterOperation; amount = $Amount }
    }
    'barterReset' { $result = Invoke-ProtocolCommand 'barterReset' }
    'barterAutoBalance' { $result = Invoke-ProtocolCommand 'barterAutoBalance' }
    'barterOffer' {
        if ($ExpectedSessionId -or $ExpectedProposalFingerprint) {
            if (-not $ExpectedSessionId -or -not $ExpectedProposalFingerprint) { throw 'Both -ExpectedSessionId and -ExpectedProposalFingerprint are required together.' }
            $result = Invoke-ProtocolCommand 'barterOffer' @{ expectedSessionId = $ExpectedSessionId; expectedProposalFingerprint = $ExpectedProposalFingerprint }
        } else { $result = Invoke-ProtocolCommand 'barterOffer' }
    }
    'barterCancel' { $result = Invoke-ProtocolCommand 'barterCancel' }
    'save' {
        if (-not $SaveName) { throw '-SaveName is required for save.' }
        $result = Invoke-ProtocolCommand 'save' @{ name = $SaveName } -ReturnWhenAccepted:$ReturnWhenAccepted
    }
    'agentCheckpointGet' { $result = Invoke-ProtocolCommand 'agentCheckpointGet' }
    'agentCheckpointSet' {
        if ([string]::IsNullOrWhiteSpace($CheckpointBase64) -or $CheckpointBase64.Length -gt 100000) { throw '-CheckpointBase64 is required and must be at most 100,000 characters.' }
        try {
            $checkpointJson = [Text.UTF8Encoding]::new($false, $true).GetString([Convert]::FromBase64String($CheckpointBase64))
            if ($checkpointJson.Length -gt 65536) { throw 'Checkpoint payload exceeds the 65,536-character limit.' }
            $checkpointObject = $checkpointJson | ConvertFrom-Json
            if ([int]$checkpointObject.schemaVersion -notin @(1,2) -or [string]::IsNullOrWhiteSpace([string]$checkpointObject.campaignInstanceId)) { throw 'Checkpoint schemaVersion 1 or 2 and campaignInstanceId are required.' }
        }
        catch { throw "Checkpoint payload is invalid: $($_.Exception.Message)" }
        $result = Invoke-ProtocolCommand 'agentCheckpointSet' @{ checkpointBase64 = $CheckpointBase64 }
    }
    'harnessSeedAgentCheckpointFailure' {
        if (-not $CheckpointFailureMode) { throw '-CheckpointFailureMode is required for the Harness-only checkpoint failure fixture.' }
        $result = Invoke-ProtocolCommand 'harnessSeedAgentCheckpointFailure' @{ mode = $CheckpointFailureMode }
    }
    'stop' {
        $session = Get-Session
        $receipt = $null
        $commandError = $null
        try { $receipt = Invoke-ProtocolCommand 'stop' }
        catch { $commandError = $_.Exception.Message }
        $processStopped = Stop-AgentProcessTree -RootProcessId ([int]$session.processId)
        Set-SafeExitMarker
        $engineConfigRestored = $false
        if ($processStopped -and $session.engineConfigBackupPath) { $engineConfigRestored = Restore-ChronicleTestEngineConfig -BackupPath ([string]$session.engineConfigBackupPath) }
        elseif ($processStopped -and (Test-Path -LiteralPath $engineConfigBackupPath -PathType Leaf)) { $engineConfigRestored = Restore-ChronicleTestEngineConfig -BackupPath $engineConfigBackupPath }
        Remove-Item -LiteralPath $sessionPath -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $commandPath) {
            try { if ((Get-Content -LiteralPath $commandPath -Raw -Encoding UTF8 | ConvertFrom-Json).action -eq 'stop') { Remove-Item -LiteralPath $commandPath -Force -ErrorAction SilentlyContinue } } catch { }
        }
        $result = [ordered]@{ protocolVersion = 1; action = 'stop'; status = if ($processStopped) { 'completed' } else { 'failed' }; processId = $session.processId; processStopped = $processStopped; engineConfigRestored = $engineConfigRestored; receipt = $receipt; commandError = $commandError }
    }
}

Write-Result $result
