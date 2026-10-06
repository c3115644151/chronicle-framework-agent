[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet('start','load','recoverTestConfig','state','closeEscapeMenu','respondInquiry','respondMultiSelectionInquiry','mapSettlementTargets','mapNotifications','quickInformation','sceneNotification','mapPartyTargets','mapPartyComposition','mapPartyBehavior','partyUpgradeOptions','upgradeTroop','prisonerRecruitmentOptions','recruitPrisoner','characterDevelopment','spendSkillFocus','questDetails','partyRoster','partyRoles','inventoryOpen','heroEquipmentOptions','equipHeroItem','unequipHeroItem','inventoryConfirm','inventoryCancel','inventoryCancelChanges','tradeConfirm','tradeCancel','tradeCancelChanges','barterOptions','barterEdit','barterReset','barterAutoBalance','barterOffer','barterCancel','setPartyRole','unassignPartyRole','captureFrame','harnessMissionDiagnostics','harnessMapDiagnostics','harnessOpenMapEscapeMenu','harnessOpenNativeInquiry','harnessOpenRecruitmentInquiry','harnessNativeInquiryDiagnostics','harnessPrepareAlleyLeaderFixture','harnessAlleyLeaderDiagnostics','harnessPrepareAlleyRosterFixture','harnessSeedAlleyAttackFixture','harnessSeedPersuasionFixture','harnessCurrentConversationAnswers','harnessAlleyRosterDiagnostics','harnessPlayerSkillsDiagnostics','harnessCharacterDevelopmentDiagnostics','harnessQuestDetailsDiagnostics','harnessQuestDeadlinePrivacyDiagnostics','harnessPartyRosterDiagnostics','harnessMapPartyDiagnostics','harnessMapPartyCompositionDiagnostics','harnessCreateMapArmyFixture','harnessPrepareMovingArmyEncounter','harnessArmyEncounterDiagnostics','harnessPrepareSiegeJoinFixture','harnessSiegeJoinDiagnostics','harnessSeedMapPartyIssueMarker','harnessPrepareSafePassageFixture','harnessSeedCaptivityObservationFixture','harnessSeedPrisonCaptivityFixture','harnessSwitchCaptivityObservationMenu','harnessCaptivityDiagnostics','harnessPrepareSurrenderCondition','harnessSeedTryGetAwayFixture','harnessTryGetAwayDiagnostics','harnessSeedNpcBattleForPlayerJoin','harnessPrepareArmyMemberForCurrentJoinEncounter','harnessJoinEncounterDiagnostics','harnessPreparePursuitVisibilityFixture','harnessSeedPartyUpgradeFixture','harnessSeedPrisonerRecruitmentFixture','harnessSeedRecruitmentCapacityFixture','harnessPrepareCompanionHiringFixture','harnessCompanionHiringDiagnostics','harnessSeedPartyRoleFixture','harnessPartyRoleDiagnostics','harnessSeedEquipmentModifierFixture','harnessClearEquipmentModifierFixture','harnessSeedTradeRumorFixture','harnessTradeRumorTooltipDiagnostics','harnessSeedMapNotificationFixture','harnessSeedQuickInformationFixture','harnessSeedSceneNotificationFixture','harnessOpenInventoryState','harnessCloseInventoryState','harnessInventoryStateDiagnostics','talkToSettlementHero','visitSettlementHero','inventoryTakeAll','inventoryDone','seedVisualLoot','advance','pause','resume','fastForward','move','moveToPoint','missionSceneAgents','missionInput','missionNavigateToAgent','missionLeave','missionInteract','missionCancelNavigation','missionAimAt','pursue','follow','hold','menu','menuSelect','persuasionDetails','dialogueSelect','dialogueContinue','battlePause','battleSkip','battleFinish','battleRetreat','missionRetreat','partyTakeAll','partyScreenDone','alleyRosterTransfer','alleyRosterCancel','rest','recruitOptions','recruit','foodOptions','tradeOptions','tradeRumors','trade','provision','save','stop')]
    [string]$Action,
    [string]$SaveName,
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
    [string]$InquiryToken,
    [ValidateSet('affirmative','negative')][string]$InquiryChoice,
    [string[]]$SelectedIds,
    [string]$OwnerId,
    [string]$TroopId,
    [switch]$ConfirmPartySizeWarning,
    [ValidateSet('members','prisoners')][string]$LootType,
    [ValidateSet('alley','mainParty')][string]$RosterSide,
    [int]$VolunteerSlot = -1,
    [string]$ItemId,
    [string]$Direction,
    [string]$OutputPath,
    [string]$HeroId,
    [string]$RoleId,
    [string]$ItemViewModelId,
    [ValidateSet('PlayerInventory','OtherInventory')][string]$InventorySide,
    [string]$BarterCandidateId,
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
    [int]$TimeoutSeconds = 180,
    [switch]$ReturnWhenAccepted,
    [Alias('json')]
    [switch]$AsJson
)

. (Join-Path $PSScriptRoot 'HarnessShaderCacheDialog.ps1')

$ErrorActionPreference = 'Stop'
$gameRoot = if ($env:CHRONICLE_GAME_ROOT -and (Test-Path -LiteralPath $env:CHRONICLE_GAME_ROOT)) { [IO.Path]::GetFullPath($env:CHRONICLE_GAME_ROOT) } else { Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$binDirectory = Join-Path $gameRoot 'bin\Win64_Shipping_Client'
$launcher = Join-Path $binDirectory 'Bannerlord.BLSE.Standalone.exe'
$steamRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $gameRoot))
$steamExe = Join-Path $steamRoot 'steam.exe'
$documentsRoot = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord'
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
    return $true
}

function Ensure-ChronicleSteamClient([int]$TimeoutSeconds = 45) {
    $existingSteam = @(Get-Process -Name 'steam' -ErrorAction SilentlyContinue)
    if ($existingSteam.Count -gt 0) {
        return [ordered]@{ available = $true; startedByHarness = $false; processIds = @($existingSteam | ForEach-Object { [int]$_.Id }) }
    }
    if (-not (Test-Path -LiteralPath $steamExe -PathType Leaf)) {
        throw "Steam client is not running and the expected Steam executable is not present at '$steamExe'."
    }
    Start-Process -FilePath $steamExe -ArgumentList '-silent' -WorkingDirectory $steamRoot -WindowStyle Hidden | Out-Null
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $steamProcesses = @()
    while ([DateTime]::UtcNow -lt $deadline) {
        $steamProcesses = @(Get-Process -Name 'steam' -ErrorAction SilentlyContinue)
        if ($steamProcesses.Count -gt 0) {
            Start-Sleep -Seconds 5
            $steamProcesses = @(Get-Process -Name 'steam' -ErrorAction SilentlyContinue)
            if ($steamProcesses.Count -gt 0) {
                return [ordered]@{ available = $true; startedByHarness = $true; processIds = @($steamProcesses | ForEach-Object { [int]$_.Id }) }
            }
        }
        Start-Sleep -Milliseconds 500
    }
    throw "Steam was launched silently but its client process did not become available within $TimeoutSeconds seconds."
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

function Invoke-ProtocolCommand([string]$ProtocolAction, [hashtable]$Arguments = @{}, [switch]$ReturnWhenAccepted) {
    $session = Get-Session
    $id = if ($CommandId) { $CommandId } else { 'cli-' + [Guid]::NewGuid().ToString('N') }
    $payload = [ordered]@{ id = $id; action = $ProtocolAction }
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
        Set-SafeExitMarker
        $process = Start-Process -FilePath $launcher -ArgumentList "/continuesave $SaveName $moduleArgument /anticheat" -WorkingDirectory $binDirectory -WindowStyle Minimized -PassThru
    }
    catch {
        if ($engineConfigBackupCreated) { Restore-ChronicleTestEngineConfig -BackupPath $engineConfigBackupPath | Out-Null }
        throw
    }
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $ready = $false
    $windowLayout = $null
    $startupDialogReceipts = [System.Collections.Generic.List[object]]::new()
    while ((Get-Date) -lt $deadline) {
        $launchProcess = Get-Process -Id $process.Id -ErrorAction SilentlyContinue
        if (-not $launchProcess) { break }
        if ($launchProcess.MainWindowTitle -match '^Mod change detected$') {
            try {
                $dialogResult = Invoke-ChronicleShaderCacheDialogAcknowledgement -ProcessId $process.Id -WindowHandle $launchProcess.MainWindowHandle
            }
            catch {
                $dialogEvidenceDirectory = if (-not [string]::IsNullOrWhiteSpace($env:CHRONICLE_HARNESS_TEMP)) { $env:CHRONICLE_HARNESS_TEMP } else { $protocolRoot }
                New-Item -ItemType Directory -Force -Path $dialogEvidenceDirectory | Out-Null
                $dialogEvidencePath = Join-Path $dialogEvidenceDirectory "startup-dialog-$($process.Id).json"
                [pscustomobject]@{ Handled = $false; ProcessId = $process.Id; WindowTitle = $launchProcess.MainWindowTitle; Error = $_.Exception.Message } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $dialogEvidencePath -Encoding UTF8
                $launchStopped = Stop-AgentProcessTree -RootProcessId $process.Id
                Set-SafeExitMarker
                if ($launchStopped -and $engineConfigBackupCreated) { Restore-ChronicleTestEngineConfig -BackupPath $engineConfigBackupPath | Out-Null }
                throw "Safe handling of the known shader-cache prompt failed before confirmation. The test-owned game process was stopped; evidence: $dialogEvidencePath. Cause: $($_.Exception.Message)"
            }
            $startupDialogReceipts.Add($dialogResult)
            $dialogEvidenceDirectory = if (-not [string]::IsNullOrWhiteSpace($env:CHRONICLE_HARNESS_TEMP)) { $env:CHRONICLE_HARNESS_TEMP } else { $protocolRoot }
            New-Item -ItemType Directory -Force -Path $dialogEvidenceDirectory | Out-Null
            $dialogEvidencePath = Join-Path $dialogEvidenceDirectory "startup-dialog-$($process.Id).json"
            $dialogResult | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $dialogEvidencePath -Encoding UTF8
            if (-not $dialogResult.Handled) {
                $launchStopped = Stop-AgentProcessTree -RootProcessId $process.Id
                Set-SafeExitMarker
                if ($launchStopped -and $engineConfigBackupCreated) { Restore-ChronicleTestEngineConfig -BackupPath $engineConfigBackupPath | Out-Null }
                $actionSummary = @($dialogResult.ActionNames) -join ', '
                throw "Campaign launch stopped at 'Mod change detected'; this is not evidence of incompatible save modules. Safely captured UIA actions='$actionSummary', reason='$($dialogResult.Reason)'. Full dialog evidence: $dialogEvidencePath. No global keyboard or mouse input was sent."
            }
            continue
        }
        if ($launchProcess.MainWindowTitle -ceq 'Warning') {
            try {
                $warningSnapshot = Get-ChronicleWindowAutomationSnapshot -ProcessId $process.Id -WindowHandle $launchProcess.MainWindowHandle
                $startupDialogSnapshots.Add($warningSnapshot)
                $startupFault = if ($warningSnapshot.DialogText -match '(?i)Unable to initialize Steam API') { 'Bannerlord reports that the Steam API could not initialize; see startup dialog evidence.' } else { 'Bannerlord is blocked by an unclassified Warning dialog; no button was pressed.' }
            }
            catch { $startupFault = "Bannerlord Warning dialog could not be read safely: $($_.Exception.Message)" }
            break
        }
        $candidateLayout = Set-ChronicleTestWindow -ProcessId $process.Id
        if ($candidateLayout -and $candidateLayout.Applied) { $windowLayout = $candidateLayout }
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
                    if (@($newLines | Where-Object { $_ -match "\|pid=$($process.Id)\|campaign-loaded\|mode=$([regex]::Escape($expectedHarnessMode))\|" }).Count -gt 0) { $ready = $true }
                }
            }
            catch { }
            finally {
                if ($diagnosticReader) { $diagnosticReader.Dispose() }
                if ($diagnosticStream) { $diagnosticStream.Dispose() }
            }
        }
        if ($ready) { break }
        Start-Sleep -Milliseconds 250
    }
    if (-not $ready) {
        $startupProcess = Get-Process -Id $process.Id -ErrorAction SilentlyContinue
        $programDataLogs = Join-Path $env:ProgramData 'Mount and Blade II Bannerlord\logs'
        $rglPath = Join-Path $programDataLogs "rgl_log_$($process.Id).txt"
        $rglErrorPath = Join-Path $programDataLogs "rgl_log_errors_$($process.Id).txt"
        $watchdogPath = Join-Path $programDataLogs "watchdog_log_$($process.Id).txt"
        $telemetryLines = @()
        if (Test-Path -LiteralPath $diagnosticLog) {
            $allTelemetry = @(Get-Content -LiteralPath $diagnosticLog -Encoding UTF8)
            $telemetryLines = @($allTelemetry | Select-Object -Skip $diagnosticStartLineCount)
        }
        $startupEvidence = [ordered]@{
            ProcessId = $process.Id
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
        $startupEvidencePath = Join-Path $startupEvidenceDirectory "startup-timeout-$($process.Id).json"
        $startupEvidence | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $startupEvidencePath -Encoding UTF8
        $launchStopped = Stop-AgentProcessTree -RootProcessId $process.Id
        Set-SafeExitMarker
        if ($launchStopped -and $engineConfigBackupCreated) { Restore-ChronicleTestEngineConfig -BackupPath $engineConfigBackupPath | Out-Null }
        $startupFailureMessage = if ($startupFault) { [string]$startupFault } else { 'Campaign did not reach protocol-ready state.' }
        throw "$startupFailureMessage Startup evidence: $startupEvidencePath"
    }
    $windowLayout = Set-ChronicleTestWindow -ProcessId $process.Id
    if (-not $windowLayout -or -not $windowLayout.Applied) {
        $launchStopped = Stop-AgentProcessTree -RootProcessId $process.Id
        Set-SafeExitMarker
        if ($launchStopped -and $engineConfigBackupCreated) { Restore-ChronicleTestEngineConfig -BackupPath $engineConfigBackupPath | Out-Null }
        throw 'Windowed test layout was not verified.'
    }
    $performanceProfile = [ordered]@{ maxFramerate = 30; width = [int]$windowLayout.Width; height = [int]$windowLayout.Height; configRestoredAfterStop = [bool]$engineConfigBackupCreated }
    $session = [ordered]@{ protocolVersion = 1; processId = $process.Id; saveName = $SaveName; moduleSet = $modules; startedUtc = (Get-Date).ToUniversalTime().ToString('O'); windowLayout = $windowLayout; performanceProfile = $performanceProfile; steamClient = $steamStatus; engineConfigBackupPath = if ($engineConfigBackupCreated) { $engineConfigBackupPath } else { $null }; startupDialogReceipts = @($startupDialogReceipts) }
    $session | ConvertTo-Json | Set-Content -Path $sessionPath -Encoding UTF8
    $configuredTimeout = $TimeoutSeconds
    $TimeoutSeconds = [Math]::Min(30, $TimeoutSeconds)
    try {
        $protocolProbe = Invoke-ProtocolCommand 'state'
        if ($protocolProbe.status -ne 'completed' -or -not $protocolProbe.state) { throw 'Agent protocol returned no structured initial state.' }
    }
    catch {
        $handshakeError = $_.Exception.Message
        $launchStopped = Stop-AgentProcessTree -RootProcessId $process.Id
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
        $result = Invoke-ProtocolCommand 'recruitPrisoner' @{ troopId = $TroopId; confirmPartySizeWarning = [int]$ConfirmPartySizeWarning.IsPresent }
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
    'harnessMapDiagnostics' { $result = Invoke-ProtocolCommand 'harnessMapDiagnostics' }
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
    'partyScreenDone' { $result = Invoke-ProtocolCommand 'partyScreenDone' }
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
    'barterOffer' { $result = Invoke-ProtocolCommand 'barterOffer' }
    'barterCancel' { $result = Invoke-ProtocolCommand 'barterCancel' }
    'save' {
        if (-not $SaveName) { throw '-SaveName is required for save.' }
        $result = Invoke-ProtocolCommand 'save' @{ name = $SaveName }
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
