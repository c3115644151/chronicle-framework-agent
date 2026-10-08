[CmdletBinding()]
param(
    [int]$TimeoutSeconds = 240,
    [switch]$ValidateRecruitmentProgression
)

$ErrorActionPreference = 'Stop'
$harnessRoot = $PSScriptRoot
. (Join-Path $harnessRoot 'Test-AgentSupport.ps1')
. (Join-Path $harnessRoot 'HarnessShaderCacheDialog.ps1')
$gameRoot = if ($env:CHRONICLE_GAME_ROOT -and (Test-Path -LiteralPath $env:CHRONICLE_GAME_ROOT)) { [IO.Path]::GetFullPath($env:CHRONICLE_GAME_ROOT) } else { Split-Path -Parent (Split-Path -Parent $harnessRoot) }
$gameExe = Join-Path $gameRoot 'bin\Win64_Shipping_Client\Bannerlord.exe'
$engineConfig = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\Configs\engine_config.txt'
$diagnosticLog = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\Configs\ModLogs\chronicle-framework.log'
$saveDirectory = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\Game Saves'
$agentCli = Join-Path $harnessRoot 'Agent-Cli.ps1'
$agentDecisionLoop = Join-Path $harnessRoot 'Agent-DecisionLoop.ps1'
$agentLoopProvider = Join-Path $harnessRoot 'Test-AgentLoopProvider.ps1'
$agentProtocolRoot = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent'
$agentSessionPath = Join-Path $agentProtocolRoot 'session.json'
$agentCommandPath = Join-Path $agentProtocolRoot 'command.json'
$agentResponseRoot = Join-Path $agentProtocolRoot 'responses'
$progressionCommandPrefix = 'freshp5-' + [Guid]::NewGuid().ToString('N')
$progressionSaveName = if ($ValidateRecruitmentProgression) { 'ChronicleP5Fresh-' + (Get-Date -Format 'yyyyMMddHHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8) } else { $null }
$progressionSavePath = if ($progressionSaveName) { Join-Path $saveDirectory "$progressionSaveName.sav" } else { $null }
$disposableSaveOwned = $false
$previousSessionExisted = Test-Path -LiteralPath $agentSessionPath
$previousSessionBytes = if ($previousSessionExisted) { [IO.File]::ReadAllBytes($agentSessionPath) } else { $null }
if ($ValidateRecruitmentProgression -and (Test-Path -LiteralPath $agentCommandPath)) { throw 'A pending Agent command exists; refusing to overwrite it for FreshCampaign progression.' }
if ($progressionSavePath -and (Test-Path -LiteralPath $progressionSavePath)) { throw 'Generated disposable-save name already exists; refusing to overwrite.' }
. (Join-Path $harnessRoot 'Test-WindowLayout.ps1')

function Invoke-FreshCampaignAgentCli([string]$Action, [string[]]$Arguments = @{}, [int]$CommandTimeout = 15) {
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $agentCli $Action @Arguments -TimeoutSeconds $CommandTimeout -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "FreshCampaign Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "FreshCampaign Agent CLI '$Action' returned invalid JSON: $output" }
}

if (-not (Test-Path -LiteralPath $gameExe)) { throw "Bannerlord executable was not found: $gameExe" }
if (Get-Process Bannerlord -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
if (-not (Test-Path -LiteralPath $engineConfig)) { throw "Windowed display config was not found: $engineConfig" }
$currentEngineConfig = Get-Content -LiteralPath $engineConfig -Raw
if ($currentEngineConfig -notmatch '(?m)^display_mode\s*=\s*0\s*$' -or
    $currentEngineConfig -notmatch '(?m)^display_width\s*=\s*840\s*$' -or
    $currentEngineConfig -notmatch '(?m)^display_height\s*=\s*472\s*$') {
    throw 'FreshCampaign requires the existing 840x472 windowed test profile; it will not change display layout.'
}

function Get-DescendantProcessIds([int]$ParentId) {
    $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId = $ParentId" -ErrorAction SilentlyContinue)
    foreach ($child in $children) {
        [int]$child.ProcessId
        Get-DescendantProcessIds -ParentId $child.ProcessId
    }
}

function Set-SafeExitMarker {
    if (-not (Test-Path -LiteralPath $engineConfig)) { return }
    $text = Get-Content -LiteralPath $engineConfig -Raw
    $text = $text -replace 'safely_exited\s*=\s*0', 'safely_exited = 1'
    Set-Content -LiteralPath $engineConfig -Value $text -NoNewline
}

function Get-SaveManifestDigest {
    if (-not (Test-Path -LiteralPath $saveDirectory)) { return 'no-save-directory' }
    $manifest = @(Get-ChildItem -LiteralPath $saveDirectory -File -Filter '*.sav' | Sort-Object Name | ForEach-Object {
        "$($_.Name)|$($_.Length)|$($_.LastWriteTimeUtc.Ticks)"
    }) -join "`n"
    $bytes = [Text.Encoding]::UTF8.GetBytes($manifest)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '') } finally { $sha.Dispose() }
}

$modules = @(
    'Bannerlord.Harmony', 'Bannerlord.ButterLib', 'Bannerlord.UIExtenderEx', 'Bannerlord.MBOptionScreen',
    'Native', 'SandBoxCore', 'CustomBattle', 'SandBox', 'StoryMode', 'BirthAndDeath', 'ChronicleFramework'
)
$moduleArgument = '_MODULES_*' + ($modules -join '*') + '*_MODULES_'
$arguments = "/singleplayer $moduleArgument /anticheat /no_watchdog"
$saveDigestBefore = Get-SaveManifestDigest
$diagnosticStartLineCount = if (Test-Path -LiteralPath $diagnosticLog) { @(Get-Content -LiteralPath $diagnosticLog -Encoding UTF8).Count } else { 0 }
$launchStart = Get-Date
$previousMode = $env:CHRONICLE_HARNESS_MODE
$previousIssueProbeFlag = $env:CHRONICLE_FRESH_CAMPAIGN_SKIP_ISSUE_PROBE
$previousFreshSaveName = $env:CHRONICLE_FRESH_CAMPAIGN_SAVE_NAME
$previousCrashCaptureFlag = $env:CHRONICLE_CAPTURE_CRASH_EXCEPTION
$env:CHRONICLE_HARNESS_MODE = 'fresh-campaign-renown'
$env:CHRONICLE_CAPTURE_CRASH_EXCEPTION = '1'
if ($ValidateRecruitmentProgression) {
    $env:CHRONICLE_FRESH_CAMPAIGN_SKIP_ISSUE_PROBE = '1'
    $env:CHRONICLE_FRESH_CAMPAIGN_SAVE_NAME = $progressionSaveName
}
try {
    Set-SafeExitMarker
    $launcherProcess = Start-Process -FilePath $gameExe -ArgumentList $arguments -WorkingDirectory (Split-Path $gameExe) -WindowStyle Minimized -PassThru
}
finally {
    $env:CHRONICLE_HARNESS_MODE = $previousMode
    if ($null -eq $previousCrashCaptureFlag) { Remove-Item Env:CHRONICLE_CAPTURE_CRASH_EXCEPTION -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_CAPTURE_CRASH_EXCEPTION = $previousCrashCaptureFlag }
    if ($null -eq $previousIssueProbeFlag) { Remove-Item Env:CHRONICLE_FRESH_CAMPAIGN_SKIP_ISSUE_PROBE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_FRESH_CAMPAIGN_SKIP_ISSUE_PROBE = $previousIssueProbeFlag }
    if ($null -eq $previousFreshSaveName) { Remove-Item Env:CHRONICLE_FRESH_CAMPAIGN_SAVE_NAME -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_FRESH_CAMPAIGN_SAVE_NAME = $previousFreshSaveName }
}

$bannerlordPid = 0
$gameStarted = $false
$startRequested = $false
$introSkippedObserved = $false
$startupDialogReceipts = [System.Collections.Generic.List[object]]::new()
$startupDialogFailure = $null
$creationCompleted = $false
$initialSnapshotCaptured = $false
$snapshotArtifactPath = if ([string]::IsNullOrWhiteSpace($env:CHRONICLE_HARNESS_TEMP)) { $null } else { Join-Path $env:CHRONICLE_HARNESS_TEMP 'FreshCampaign.initial-state.json' }
$renown = $null
$campaignInstanceId = $null
$mapState = $null
$clock = $null
$stageIndices = [System.Collections.Generic.HashSet[int]]::new()
$backgroundChoiceObserved = $false
$visibleIssuePoolObserved = $false
$visibleIssueTypes = $null
$issueConversationProbeStatus = 'not-observed'
$issueConversationOfferOption = $false
$issueConversationBriefReached = $false
$issueConversationOfferDenied = $false
$issueQuestAcceptanceAvailable = $false
$issueConversationClockBefore = $null
$issueConversationClockAfter = $null
$issueConversationOptions = @()
$harnessFailureObserved = $false
$campaignSaveRequested = $false
$crashDetected = $false
$windowLayoutApplied = $false
$windowLayout = $null
$crashWindowTitle = $null
$crashWindowCapture = $null
$crashWindowCaptureResult = $null
$crashWindowCaptureError = $null
$crashWindowCaptureAttempted = $false
$crashWindowCaptureUntil = $null
$crashWindowCapturePath = $null
$crashWindowEventTracePath = $null
$crashWindowCaptureRetained = $false
$crashModulesCaptured = $false
$crashFaultAddress = $null
$crashFaultModule = $null
$crashModuleInventory = @()
$crashModuleCaptureError = $null
$rglLog = $null
$watchdogLog = $null
$recruitmentProgression = $null
$recruitmentProgressionError = $null
$recruitmentProgressionPassed = -not $ValidateRecruitmentProgression
$disposableSaveRequested = $false
$disposableSaveCompleted = $false
$disposableSaveSuccessful = $false
$deadline = (Get-Date).AddSeconds($(if ($ValidateRecruitmentProgression) { [Math]::Min(90, $TimeoutSeconds) } else { $TimeoutSeconds }))

try {
    while ((Get-Date) -lt $deadline) {
        $candidate = Get-Process Bannerlord -ErrorAction SilentlyContinue |
            Where-Object { $_.StartTime -ge $launchStart } |
            Sort-Object StartTime |
            Select-Object -Last 1
        if ($candidate) {
            $bannerlordPid = $candidate.Id
            $crashWindowTitle = [string]$candidate.MainWindowTitle
            if ($crashWindowTitle -match '(?i)Crash Report|CrashReporter') { $crashDetected = $true }
            if ($candidate.MainWindowTitle -ceq 'Mod change detected') {
                try {
                    $dialogResult = Invoke-ChronicleShaderCacheDialogAcknowledgement -ProcessId $bannerlordPid -WindowHandle $candidate.MainWindowHandle
                }
                catch {
                    $dialogEvidencePath = if (-not [string]::IsNullOrWhiteSpace($env:CHRONICLE_HARNESS_TEMP)) { Join-Path $env:CHRONICLE_HARNESS_TEMP "startup-dialog-$bannerlordPid.json" } else { $null }
                    if ($dialogEvidencePath) { [pscustomobject]@{ Handled = $false; ProcessId = $bannerlordPid; WindowTitle = $candidate.MainWindowTitle; Error = $_.Exception.Message } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $dialogEvidencePath -Encoding UTF8 }
                    $startupDialogFailure = "Safe handling of the known shader-cache prompt failed before confirmation. No global keyboard or mouse input was sent. Cause: $($_.Exception.Message)"
                    $harnessFailureObserved = $true
                    break
                }
                $startupDialogReceipts.Add($dialogResult)
                if (-not [string]::IsNullOrWhiteSpace($env:CHRONICLE_HARNESS_TEMP)) {
                    $dialogEvidencePath = Join-Path $env:CHRONICLE_HARNESS_TEMP "startup-dialog-$bannerlordPid.json"
                    $dialogResult | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $dialogEvidencePath -Encoding UTF8
                }
                if (-not $dialogResult.Handled) {
                    $startupDialogFailure = "Known shader-cache prompt did not satisfy its exact UIA/Button process-ownership checks. No button was pressed; evidence: $dialogEvidencePath"
                    $harnessFailureObserved = $true
                    break
                }
                Start-Sleep -Milliseconds 200
                continue
            }
            $windowLayout = Set-ChronicleTestWindow -ProcessId $bannerlordPid
            if ($windowLayout) { $windowLayoutApplied = [bool]$windowLayout.Applied }
            if ($crashWindowTitle -match '(?i)Crash Report|CrashReporter' -and -not $crashWindowCaptureAttempted) {
                $crashWindowCaptureAttempted = $true
                if (-not [string]::IsNullOrWhiteSpace($env:CHRONICLE_HARNESS_TEMP)) {
                    try {
                        . (Join-Path $PSScriptRoot 'HarnessVideoCapture.ps1')
                        $crashWindowCapturePath = Join-Path $env:CHRONICLE_HARNESS_TEMP "CrashReport-$bannerlordPid.mp4"
                        $crashWindowCapture = Start-ChronicleWindowVideoCapture -ProcessId $bannerlordPid -OutputPath $crashWindowCapturePath -FrameRate 10
                        $crashWindowEventTracePath = Join-Path $env:CHRONICLE_HARNESS_TEMP "CrashReport-$bannerlordPid-events.jsonl"
                        $crashEvent = [ordered]@{ event = 'crash-report-visible'; action = 'crashReport'; commandId = "crash-$bannerlordPid"; gameState = 'CrashReport'; menuId = ''; partyScreenMode = ''; inventoryMode = ''; utc = (Get-Date).ToUniversalTime().ToString('O'); offsetMilliseconds = 1000 }
                        [IO.File]::WriteAllText($crashWindowEventTracePath, (ConvertTo-Json -InputObject $crashEvent -Compress) + [Environment]::NewLine, [Text.Encoding]::UTF8)
                        $crashWindowCaptureUntil = (Get-Date).AddSeconds(2.2)
                    }
                    catch { $crashWindowCaptureError = $_.Exception.Message }
                }
                else { $crashWindowCaptureError = 'Harness temp directory is unavailable.' }
            }
            $rglLog = Join-Path $env:ProgramData "Mount and Blade II Bannerlord\logs\rgl_log_$bannerlordPid.txt"
            $watchdogLog = Join-Path $env:ProgramData "Mount and Blade II Bannerlord\logs\watchdog_log_$bannerlordPid.txt"
        }

        $newLines = @()
        if (Test-Path -LiteralPath $diagnosticLog) {
            $allLines = @(Get-Content -LiteralPath $diagnosticLog -Encoding UTF8)
            if ($allLines.Count -gt $diagnosticStartLineCount) {
                $newLines = @($allLines[$diagnosticStartLineCount..($allLines.Count - 1)])
            }
        }
        $gameStarted = $gameStarted -or [bool]($newLines -match "pid=$bannerlordPid\|game-start$")
        $startRequested = $startRequested -or [bool]($newLines -match "pid=$bannerlordPid\|fresh-campaign-start-requested\|save=none\|gameMode=sandbox$")
        $introSkippedObserved = $introSkippedObserved -or [bool]($newLines -match 'fresh-campaign-intro-skipped\|via=native-video-completion\|mode=harness$')
        $harnessFailureObserved = $harnessFailureObserved -or [bool]($newLines -match 'fresh-campaign-failed\|')
        $campaignSaveRequested = $campaignSaveRequested -or [bool]($newLines -match 'campaign-save-requested\|')
        $disposableSaveRequested = $disposableSaveRequested -or [bool]($newLines -match "fresh-campaign-disposable-save-requested\|name=$([regex]::Escape($progressionSaveName))\|via=CampaignTick$")
        $disposableSaveCompleted = $disposableSaveCompleted -or [bool]($newLines -match "fresh-campaign-disposable-save-complete\|name=$([regex]::Escape($progressionSaveName))\|successful=True$")
        $disposableSaveSuccessful = $disposableSaveSuccessful -or $disposableSaveCompleted
        $disposableSaveOwned = $disposableSaveOwned -or $disposableSaveRequested
        $disposableSaveSuccessful = $disposableSaveSuccessful -or $disposableSaveCompleted
        if ($disposableSaveRequested) { $disposableSaveOwned = $true }
        foreach ($line in $newLines) {
            if ($line -match 'fresh-campaign-stage\|index=(\d+)') { [void]$stageIndices.Add([int]$Matches[1]) }
            if ($line -match 'fresh-campaign-background-selected\|menu=narrative_adulthood_menu\|option=adulthood_defeated_enemy_option$') { $backgroundChoiceObserved = $true }
            if ($line -match 'fresh-campaign-character-creation-complete\|renown=([0-9.]+)\|tier=([^|]+)\|clock=([^|]+)\|mapState=([^|]+)$') {
                $creationCompleted = $true
                $renown = [double]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture)
                $clock = $Matches[3]
                $mapState = $Matches[4]
            }
            if ($line -match '\|fresh-campaign-snapshot\|json=(\{.*\})$') {
                try {
                    if (-not $snapshotArtifactPath) { throw 'Harness temp directory is not set.' }
                    [IO.File]::WriteAllBytes($snapshotArtifactPath, [Text.Encoding]::UTF8.GetBytes($Matches[1]))
                    $initialSnapshotCaptured = $true
                }
                catch { $harnessFailureObserved = $true }
            }
            if ($line -match 'fresh-campaign-visible-issues\|settlements=(.*)$') {
                $visibleIssuePoolObserved = $true
                $visibleIssueTypes = $Matches[1]
            }
            if ($line -match 'fresh-campaign-issue-probe\|status=skipped\|reason=([^|]+)$') {
                $issueConversationProbeStatus = "skipped:$($Matches[1])"
            }
            if ($line -match 'fresh-campaign-issue-probe\|status=(opened|failed)\|settlement=([^|]+)\|heroId=([^|]+)\|issueType=([^|]+)\|issueOfferOption=(True|False)\|issueBriefReached=(True|False)\|issueOfferDenied=(True|False)\|questAcceptanceAvailable=(True|False)\|clockBefore=([^|]+)\|clockAfter=([^|]+)\|options=(.*)$') {
                $issueConversationProbeStatus = $Matches[1]
                $issueConversationOfferOption = $Matches[5] -eq 'True'
                $issueConversationBriefReached = $Matches[6] -eq 'True'
                $issueConversationOfferDenied = $Matches[7] -eq 'True'
                $issueQuestAcceptanceAvailable = $Matches[8] -eq 'True'
                $issueConversationClockBefore = $Matches[9]
                $issueConversationClockAfter = $Matches[10]
                $issueConversationOptions = if ($Matches[11]) { @($Matches[11] -split ',') } else { @() }
            }
        }

        $rglText = ''
        if ($bannerlordPid -and (Test-Path -LiteralPath $rglLog)) {
            $rglText = [string](Get-Content -LiteralPath $rglLog -Raw)
            $crashDetected = $crashDetected -or ($rglText -match 'Unhandled Exception|Crash occurred|ExceptionCode:')
        }
        if ($bannerlordPid -and (Test-Path -LiteralPath $watchdogLog)) {
            $watchdogText = [string](Get-Content -LiteralPath $watchdogLog -Raw)
            $crashDetected = $crashDetected -or ($watchdogText -match 'Crash occurred|ExceptionCode:')
        }
        if ($crashDetected -and $bannerlordPid -and -not $crashModulesCaptured) {
            $crashModulesCaptured = $true
            try {
                $targetProcess = Get-Process -Id $bannerlordPid -ErrorAction Stop
                $loadedModules = @($targetProcess.Modules)
                $faultMatch = [regex]::Match($rglText, '(?i)Unhandled Exception Code 0x[0-9a-f]+ at (?:adress|address) 0x([0-9a-f]+)')
                [UInt64]$faultValue = 0
                if ($faultMatch.Success) {
                    $faultValue = [Convert]::ToUInt64($faultMatch.Groups[1].Value, 16)
                    $crashFaultAddress = '0x' + $faultMatch.Groups[1].Value.ToUpperInvariant()
                }
                foreach ($module in $loadedModules) {
                    $baseValue = [UInt64]$module.BaseAddress.ToInt64()
                    $sizeValue = [UInt64]$module.ModuleMemorySize
                    $version = ''
                    try { $version = [string]$module.FileVersionInfo.FileVersion } catch { }
                    $crashModuleInventory += [ordered]@{ name = [string]$module.ModuleName; baseAddress = ('0x{0:X}' -f $baseValue); size = $sizeValue; fileVersion = $version }
                    if ($faultMatch.Success -and $faultValue -ge $baseValue -and $faultValue -lt ($baseValue + $sizeValue)) {
                        $crashFaultModule = [string]$module.ModuleName
                    }
                }
            }
            catch { $crashModuleCaptureError = $_.Exception.Message }
        }
        if ($crashDetected -and -not $crashWindowCaptureAttempted -and $bannerlordPid -and $candidate) {
            $crashWindowCaptureAttempted = $true
            if (-not [string]::IsNullOrWhiteSpace($env:CHRONICLE_HARNESS_TEMP)) {
                try {
                    . (Join-Path $PSScriptRoot 'HarnessVideoCapture.ps1')
                    $crashWindowCapturePath = Join-Path $env:CHRONICLE_HARNESS_TEMP "CrashObserved-$bannerlordPid.mp4"
                    $crashWindowCapture = Start-ChronicleWindowVideoCapture -ProcessId $bannerlordPid -OutputPath $crashWindowCapturePath -FrameRate 10
                    $crashWindowEventTracePath = Join-Path $env:CHRONICLE_HARNESS_TEMP "CrashObserved-$bannerlordPid-events.jsonl"
                    $crashObservedEvent = [ordered]@{ event = 'native-crash-signature'; action = 'crashObserved'; commandId = "crash-$bannerlordPid-observed"; gameState = 'StartupCrash'; menuId = ''; partyScreenMode = ''; inventoryMode = ''; utc = (Get-Date).ToUniversalTime().ToString('O'); offsetMilliseconds = 1000 }
                    [IO.File]::WriteAllText($crashWindowEventTracePath, (ConvertTo-Json -InputObject $crashObservedEvent -Compress) + [Environment]::NewLine, [Text.Encoding]::UTF8)
                    $crashWindowCaptureUntil = (Get-Date).AddSeconds(2.2)
                }
                catch { $crashWindowCaptureError = $_.Exception.Message }
            }
            else { $crashWindowCaptureError = 'Harness temp directory is unavailable for crash capture.' }
        }

        $creationReady = $creationCompleted -and $initialSnapshotCaptured -and $issueConversationProbeStatus -ne 'not-observed'
        $saveReady = -not $ValidateRecruitmentProgression -or $disposableSaveCompleted
        $crashCaptureGraceActive = $crashWindowCapture -and $crashWindowCaptureUntil -and (Get-Date) -lt $crashWindowCaptureUntil
        if (($creationReady -and $saveReady) -or (($crashDetected -or $harnessFailureObserved) -and -not $crashCaptureGraceActive)) { break }
        if (-not (Get-Process -Id $launcherProcess.Id -ErrorAction SilentlyContinue) -and -not $candidate) { break }
        Start-Sleep -Milliseconds 300
    }

}
finally {
    if ($crashWindowCapture) {
        $crashContactSheetPath = Join-Path $env:CHRONICLE_HARNESS_TEMP "CrashReport-$bannerlordPid-contact.jpg"
        try {
            $crashWindowCaptureResult = Stop-ChronicleWindowVideoCapture -Capture $crashWindowCapture -ContactSheetPath $crashContactSheetPath -EventTracePath $crashWindowEventTracePath
        }
        catch {
            $crashWindowCaptureError = $_.Exception.Message
            $crashWindowCaptureRetained = Test-Path -LiteralPath $crashWindowCapture.OutputPath
        }
    }
    $descendants = @(Get-DescendantProcessIds -ParentId $launcherProcess.Id)
    foreach ($processId in @($descendants + $bannerlordPid + $launcherProcess.Id) | Where-Object { $_ } | Select-Object -Unique) {
        Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
    }
    Set-SafeExitMarker
    if ($ValidateRecruitmentProgression) {
        if (Test-Path -LiteralPath $agentSessionPath) {
            try {
                $sessionNow = Get-Content -LiteralPath $agentSessionPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($sessionNow.processId -eq $bannerlordPid) { Remove-Item -LiteralPath $agentSessionPath -Force -ErrorAction SilentlyContinue }
            } catch { }
        }
        if ($previousSessionExisted) { [IO.File]::WriteAllBytes($agentSessionPath, $previousSessionBytes) }
        if (Test-Path -LiteralPath $agentCommandPath) {
            try { if ((Get-Content -LiteralPath $agentCommandPath -Raw -Encoding UTF8 | ConvertFrom-Json).id -like "$progressionCommandPrefix*") { Remove-Item -LiteralPath $agentCommandPath -Force } } catch { }
        }
        if (Test-Path -LiteralPath $agentResponseRoot) {
            Get-ChildItem -LiteralPath $agentResponseRoot -File -Filter "$progressionCommandPrefix*.json" | Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }
}

if ($ValidateRecruitmentProgression) {
    try {
        if (-not $gameStarted) { throw "FreshCampaign process did not reach game-start; crashDetected=$crashDetected window='$crashWindowTitle' startupDialog='$startupDialogFailure'." }
        if (-not $creationCompleted -or -not $initialSnapshotCaptured) { throw "FreshCampaign did not reach an observed character-created MapState; crashDetected=$crashDetected window='$crashWindowTitle'." }
        if (-not $disposableSaveRequested) { throw 'FreshCampaign character creation completed but did not request the uniquely named disposable save.' }
        if (-not $disposableSaveCompleted -or -not $disposableSaveSuccessful) { throw 'Fresh campaign did not confirm completion of its isolated disposable save.' }
        if (-not (Test-Path -LiteralPath $progressionSavePath) -or (Get-Item -LiteralPath $progressionSavePath).Length -lt 4096) { throw 'Fresh campaign disposable save is missing or incomplete.' }
        $disposableSaveOwned = $true

        $load = Invoke-FreshCampaignAgentCli 'load' @('-SaveName', $progressionSaveName) -CommandTimeout $TimeoutSeconds
        if ($load.status -ne 'completed' -or -not $load.session.processId) { throw 'Standard Agent CLI could not load the fresh-created disposable save.' }
        $loadedState = Invoke-FreshCampaignAgentCli 'state' @('-CommandId', "$progressionCommandPrefix-observe-start")
        $checkpointIdentity = Invoke-FreshCampaignAgentCli 'agentCheckpointGet' @('-CommandId', "$progressionCommandPrefix-campaign-identity")
        if ($checkpointIdentity.status -ne 'completed' -or [string]::IsNullOrWhiteSpace([string]$checkpointIdentity.data.campaignInstanceId)) { throw 'Native Campaign did not expose its Chronicle campaign-instance identifier for the fresh-start baseline.' }
        $campaignInstanceId = [string]$checkpointIdentity.data.campaignInstanceId
        if ($loadedState.state.economy.renown -ne 20 -or $loadedState.state.party.members -ne 1 -or $loadedState.state.economy.gold -ne 1000) { throw 'Reloaded fresh save did not preserve the expected 20-Renown/solo/1000-gold baseline.' }
        $target = @($loadedState.state.nearbySettlements | Where-Object { -not $_.hostile -and $_.distance -gt 1.0 } | Sort-Object distance | Select-Object -First 1)
        if ($target.Count -ne 1) { throw 'No safe visible settlement exists for the recruitment progression step.' }
        $move = Invoke-FreshCampaignAgentCli 'move' @('-SettlementId', [string]$target[0].id, '-CommandId', "$progressionCommandPrefix-move")
        if ($move.status -ne 'completed' -or $move.state.location.targetSettlementId -ne $target[0].id) { throw 'Reloaded fresh campaign move did not target the selected settlement.' }
        $arrival = Wait-ForAgentSettlementArrival -CliPath $agentCli -SettlementId ([string]$target[0].id) -CommandPrefix "$progressionCommandPrefix-travel" -TimeoutSeconds $TimeoutSeconds
        if ($arrival.state.location.currentSettlementId -ne $target[0].id) { throw 'Reloaded fresh campaign failed to arrive at the recruitment settlement.' }

        $beforeRecruit = Invoke-FreshCampaignAgentCli 'state' @('-CommandId', "$progressionCommandPrefix-before-recruit")
        $previousProviderMode = $env:CHRONICLE_TEST_PROVIDER_MODE
        $env:CHRONICLE_TEST_PROVIDER_MODE = 'recruitment'
        try {
            $loopOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $agentDecisionLoop -DecisionProviderPath $agentLoopProvider -MaxDecisions 2 -TimeoutSeconds ([Math]::Min(15, $TimeoutSeconds)) -CommandPrefix "$progressionCommandPrefix-loop" 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) { throw "FreshCampaign recruitment decision loop failed: $loopOutput" }
            $loop = $loopOutput | ConvertFrom-Json
        }
        finally {
            if ($null -eq $previousProviderMode) { Remove-Item Env:CHRONICLE_TEST_PROVIDER_MODE -ErrorAction SilentlyContinue }
            else { $env:CHRONICLE_TEST_PROVIDER_MODE = $previousProviderMode }
        }
        $offer = @($loop.trace[0].actionReceipt.data.offers | Where-Object { $_.available -and $_.cost -le $beforeRecruit.state.economy.gold } | Sort-Object cost | Select-Object -First 1)
        if ($offer.Count -ne 1) { throw 'FreshCampaign RecruitmentVM exposed no affordable volunteer offer.' }
        $recruit = $loop.trace[1].actionReceipt
        $afterRecruit = $loop.trace[1].observationAfter
        $receiptForwarded = ($loop.trace[1].previousActionReceipt.commandId -eq $loop.trace[0].actionReceipt.commandId -and @($loop.trace[1].previousActionReceipt.data.offers).Count -gt 0)
        $stop = Invoke-FreshCampaignAgentCli 'stop' @('-CommandId', "$progressionCommandPrefix-stop") -CommandTimeout 30
        $recruitmentProgressionPassed = ($receiptForwarded -and $loop.trace[1].decision.action -eq 'recruit' -and $recruit.data.verified -and $afterRecruit.state.party.members -eq $beforeRecruit.state.party.members + 1 -and $afterRecruit.state.economy.gold -eq $beforeRecruit.state.economy.gold - $offer[0].cost -and $afterRecruit.state.economy.renown -eq 20 -and $stop.status -eq 'completed' -and $stop.processStopped)
        $recruitmentProgression = [ordered]@{
            ProviderKind = 'deterministic-test-only'
            DisposableSaveName = $progressionSaveName
            InitialRenown = $loadedState.state.economy.renown
            InitialMembers = $loadedState.state.party.members
            InitialGold = $loadedState.state.economy.gold
            Target = $target[0]
            MoveTimeBefore = $loadedState.timeControlMode
            MoveTimeAfter = $move.timeControlMode
            ArrivalTimeMode = $arrival.timeControlMode
            RecruitmentMenu = $beforeRecruit.state.context.menuId
            OfferCount = @($loop.trace[0].actionReceipt.data.offers).Count
            SelectedOffer = $offer[0]
            ReceiptForwarded = $receiptForwarded
            RecruitReceipt = $recruit.data
            MembersAfter = $afterRecruit.state.party.members
            GoldAfter = $afterRecruit.state.economy.gold
            RenownAfter = $afterRecruit.state.economy.renown
            ProcessStopped = $stop.processStopped
            Passed = $recruitmentProgressionPassed
        }
    }
    catch {
        $activeGameProcess = Get-Process -Id $bannerlordPid -ErrorAction SilentlyContinue
        if ($activeGameProcess) {
            $crashWindowTitle = [string]$activeGameProcess.MainWindowTitle
            if ($crashWindowTitle -match '(?i)Crash Report|CrashReporter') { $crashDetected = $true }
        }
        if ([string]::IsNullOrWhiteSpace($recruitmentProgressionError)) { $recruitmentProgressionError = $_.Exception.ToString() }
        else { $recruitmentProgressionError = "$recruitmentProgressionError; validation: $($_.Exception.Message)" }
        $recruitmentProgressionPassed = $false
        $recruitmentProgression = [ordered]@{ ProviderKind = 'deterministic-test-only'; DisposableSaveName = $progressionSaveName; Passed = $false; Error = $recruitmentProgressionError }
        if (Test-Path -LiteralPath $agentSessionPath) {
            try {
                $sessionNow = Get-Content -LiteralPath $agentSessionPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if (Get-Process -Id $sessionNow.processId -ErrorAction SilentlyContinue) { Invoke-FreshCampaignAgentCli 'stop' @('-CommandId', "$progressionCommandPrefix-failure-stop") -CommandTimeout 30 | Out-Null }
            } catch { }
        }
    }
    finally {
        if ($previousSessionExisted) { [IO.File]::WriteAllBytes($agentSessionPath, $previousSessionBytes) }
        else { Remove-Item -LiteralPath $agentSessionPath -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $agentCommandPath) {
            try { if ((Get-Content -LiteralPath $agentCommandPath -Raw -Encoding UTF8 | ConvertFrom-Json).id -like "$progressionCommandPrefix*") { Remove-Item -LiteralPath $agentCommandPath -Force } } catch { }
        }
        if (Test-Path -LiteralPath $agentResponseRoot) {
            Get-ChildItem -LiteralPath $agentResponseRoot -File -Filter "$progressionCommandPrefix*.json" | Remove-Item -Force -ErrorAction SilentlyContinue
        }
        if ($disposableSaveOwned -and (Test-Path -LiteralPath $progressionSavePath)) {
            $saveRoot = [IO.Path]::GetFullPath($saveDirectory).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
            $fullDisposableSavePath = [IO.Path]::GetFullPath($progressionSavePath)
            if (-not $fullDisposableSavePath.StartsWith($saveRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Disposable save cleanup path escaped Game Saves.' }
            Get-ChildItem -LiteralPath $saveDirectory -File -Filter "$progressionSaveName*" | Remove-Item -Force
        }
    }
}

$saveDigestAfter = Get-SaveManifestDigest
$saveStateUnchanged = $saveDigestBefore -eq $saveDigestAfter
$issueProbeExpected = -not $ValidateRecruitmentProgression -and [bool]($visibleIssueTypes -match ':[^,]+')
$issueConversationProbeApplicable = $issueProbeExpected
$issueConversationProbePassed = if ($issueProbeExpected) {
    $issueConversationProbeStatus -eq 'opened' -and $issueConversationOfferOption -and ($issueConversationBriefReached -or $issueConversationOfferDenied) -and $issueConversationClockBefore -eq $issueConversationClockAfter
} else {
    $null
}
$issueConversationProbeSkipped = -not $issueProbeExpected -and $issueConversationProbeStatus -like 'skipped*'
$issueConversationProbeOutcomeValid = ($issueConversationProbeApplicable -and $issueConversationProbePassed) -or $issueConversationProbeSkipped
$result = [ordered]@{
    Scenario = 'FreshCampaignCharacterCreationRenown'
    Launcher = $gameExe
    GameProcessId = $bannerlordPid
    GameStarted = $gameStarted
    NativeNewCampaignRequested = $startRequested
    OptionalIntroSkipped = $introSkippedObserved
    StartupDialogReceipts = @($startupDialogReceipts)
    StartupDialogFailure = $startupDialogFailure
    AutoSelectedHighRenownBackground = $backgroundChoiceObserved
    VisibleIssueTypesBySettlement = $visibleIssueTypes
    IssueConversationProbeStatus = $issueConversationProbeStatus
    IssueConversationProbeApplicable = $issueConversationProbeApplicable
    IssueOfferOptionAvailable = $issueConversationOfferOption
    IssueBriefReached = $issueConversationBriefReached
    IssueOfferDeniedByNativeDialogue = $issueConversationOfferDenied
    QuestAcceptanceAvailable = $issueQuestAcceptanceAvailable
    IssueConversationProbePassed = $issueConversationProbePassed
    IssueConversationProbeSkipped = $issueConversationProbeSkipped
    IssueConversationClockBefore = $issueConversationClockBefore
    IssueConversationClockAfter = $issueConversationClockAfter
    IssueConversationOptionIds = $issueConversationOptions
    RecruitmentProgression = $recruitmentProgression
    RecruitmentProgressionError = $recruitmentProgressionError
    CharacterCreationCompleted = $creationCompleted
    InitialAgentObservationCaptured = $initialSnapshotCaptured
    InitialAgentObservationPath = if ($initialSnapshotCaptured) { $snapshotArtifactPath } else { $null }
    ChronicleCampaignInstanceId = $campaignInstanceId
    ClanRenown = $renown
    ExpectedClanRenown = 20
    MapState = $mapState
    CampaignClockMode = $clock
    CharacterCreationStagesObserved = @($stageIndices | Sort-Object)
    CrashDetected = $crashDetected
    WindowLayoutApplied = $windowLayoutApplied
    WindowX = if ($windowLayout) { $windowLayout.X } else { $null }
    WindowY = if ($windowLayout) { $windowLayout.Y } else { $null }
    WindowWidth = if ($windowLayout) { $windowLayout.Width } else { $null }
    WindowHeight = if ($windowLayout) { $windowLayout.Height } else { $null }
    NoSaveRequested = -not $campaignSaveRequested
    SaveDirectoryMetadataUnchanged = $saveStateUnchanged
    RglLog = $rglLog
    WatchdogLog = $watchdogLog
    CrashWindowTitle = $crashWindowTitle
    CrashWindowCapture = $crashWindowCaptureResult
    CrashWindowCaptureError = $crashWindowCaptureError
    CrashWindowCaptureVideoRetained = $crashWindowCaptureRetained
    CrashExceptionPath = if ($bannerlordPid -and $env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP "CrashException-$bannerlordPid.txt" } else { $null }
    CrashExceptionCaptured = [bool]($bannerlordPid -and $env:CHRONICLE_HARNESS_TEMP -and (Test-Path -LiteralPath (Join-Path $env:CHRONICLE_HARNESS_TEMP "CrashException-$bannerlordPid.txt")))
    CrashFaultAddress = $crashFaultAddress
    CrashFaultModule = $crashFaultModule
    CrashModuleInventory = $crashModuleInventory
    CrashModuleCaptureError = $crashModuleCaptureError
    Passed = ($gameStarted -and $startRequested -and $introSkippedObserved -and $backgroundChoiceObserved -and $creationCompleted -and $initialSnapshotCaptured -and $visibleIssuePoolObserved -and $issueConversationProbeOutcomeValid -and $recruitmentProgressionPassed -and $renown -eq 20 -and $mapState -eq 'MapState' -and -not $crashDetected -and -not $harnessFailureObserved -and -not $campaignSaveRequested -and $saveStateUnchanged -and $windowLayoutApplied -and $windowLayout.Width -eq 840 -and $windowLayout.Height -eq 472)
}
$result | ConvertTo-Json -Depth 6
if (-not $result.Passed) { exit 1 }
