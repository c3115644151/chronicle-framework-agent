#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateRange(90,300)][int]$TimeoutSeconds = 180,
    [ValidateRange(250,10000)][int]$AutoStopAfterMilliseconds = 250,
    [ValidateSet('Stop','Complete','UnsupportedGoal','MissingModel','ServiceUnavailable','ParentExited','StopTimeout','NonMap','CampaignRoundtrip','InputToggle')][string]$Scenario = 'Stop',
    [string]$SaveName = 'AgentBridgeLifecycle'
)

$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$harnessTemp = $env:CHRONICLE_HARNESS_TEMP
if ([string]::IsNullOrWhiteSpace($harnessTemp) -or -not (Test-Path -LiteralPath $harnessTemp -PathType Container)) {
    throw 'Agent Host lifecycle evaluation requires an active Harness evidence directory.'
}
$runDirectory = Split-Path -Parent $harnessTemp
$stageRoot = $PSScriptRoot
$harnessRoot = Split-Path -Parent $stageRoot
$cli = Join-Path $stageRoot 'Agent-Cli.ps1'
$documents = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
$documentsRoot = Join-Path $documents 'Mount and Blade II Bannerlord'
$savePath = Join-Path $documentsRoot "Game Saves\$SaveName.sav"
$saveDirectory = Join-Path $documentsRoot 'Game Saves'
$protocolRoot = Join-Path $documentsRoot 'AgentRuns\ChronicleAgent'
$sessionPath = Join-Path $protocolRoot 'session.json'
$responseRoot = Join-Path $protocolRoot 'responses'
$diagnosticLog = Join-Path $documentsRoot 'Configs\ModLogs\chronicle-framework.log'
$packageLog = Join-Path $runDirectory 'AgentHostPackage.log'
if (-not (Test-Path -LiteralPath $savePath -PathType Leaf)) { throw "Disposable lifecycle save not found: $SaveName" }
if (-not (Test-Path -LiteralPath $packageLog -PathType Leaf)) { throw 'The preceding AgentHostPackage Harness stage did not leave its package receipt.' }
$package = Get-Content -LiteralPath $packageLog -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not [bool]$package.Passed -or -not [bool]$package.SelfContained) { throw 'Lifecycle test requires a passing self-contained Host package.' }
$hostPath = Join-Path ([string]$package.PublishRoot) 'ChronicleAgentHost.exe'
if (-not (Test-Path -LiteralPath $hostPath -PathType Leaf)) { throw 'The packaged Host executable from the preceding stage is missing.' }
if (Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue) { throw 'Refusing to start the lifecycle fixture while another Bannerlord process is running.' }
if (Test-Path -LiteralPath $sessionPath -PathType Leaf) { throw 'Refusing to replace a stale Agent CLI session.' }

$expectsFailure = $Scenario -in @('MissingModel','ServiceUnavailable','UnsupportedGoal')
$expectsUnsupportedGoal = $Scenario -eq 'UnsupportedGoal'
$expectsProviderPreflightFailure = $Scenario -in @('MissingModel','ServiceUnavailable')
$usesIdleProvider = $Scenario -in @('Stop','ParentExited','StopTimeout','NonMap','CampaignRoundtrip','InputToggle')
$providerBaseUrl = if ($Scenario -eq 'ServiceUnavailable') { 'http://127.0.0.1:11433/v1' } else { 'http://127.0.0.1:11434/v1' }
$providerModelId = if ($usesIdleProvider) { 'harness-lifecycle-no-model' } elseif ($Scenario -eq 'MissingModel') { 'chronicle-harness-model-not-installed' } else { 'qwen3.5:4b-q4_K_M' }
if ($Scenario -eq 'MissingModel') {
    $catalog = Invoke-RestMethod -Uri ($providerBaseUrl + '/models') -TimeoutSec 5
    if ($providerModelId -in $catalog.data.id) { throw 'Missing-model fixture unexpectedly exists; no game was started.' }
}
if ($Scenario -eq 'ServiceUnavailable' -and (Get-NetTCPConnection -LocalPort 11433 -State Listen -ErrorAction SilentlyContinue)) {
    throw 'The unavailable-service fixture port is occupied; no game was started.'
}
if ($Scenario -eq 'Complete') {
    $catalog = Invoke-RestMethod -Uri ($providerBaseUrl + '/models') -TimeoutSec 5
    if ($providerModelId -notin $catalog.data.id) { throw 'The existing local 4b baseline model is unavailable; no game was started.' }
    # A model-list response does not exercise the installed inference runner.
    # Fail before the expensive game startup if the existing local model cannot generate.
    $probeBody = @{
        model = $providerModelId
        messages = @(@{ role = 'user'; content = 'Reply OK.' })
        max_tokens = 1
        stream = $false
        reasoning_effort = 'none'
    } | ConvertTo-Json -Depth 5 -Compress
    try {
        $probe = Invoke-RestMethod -Method Post -Uri ($providerBaseUrl + '/chat/completions') -Body $probeBody -ContentType 'application/json' -TimeoutSec 60
        if (@($probe.choices).Count -eq 0) { throw 'No completion choice was returned.' }
    }
    catch { throw "The local inference runner failed its bounded one-token preflight; no game was started (failureType=$($_.Exception.GetType().Name))." }
}

$profileDirectory = Join-Path $harnessTemp 'MCM\Global\ChronicleFramework'
New-Item -ItemType Directory -Path $profileDirectory -Force | Out-Null
$profilePath = Join-Path $profileDirectory 'ChronicleAgentSettings.json'
[ordered]@{ OllamaBaseUrl = $providerBaseUrl; ModelId = $providerModelId } | ConvertTo-Json -Compress | Set-Content -LiteralPath $profilePath -Encoding UTF8
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
$hostResponseFilesBefore = @(Get-ChildItem -LiteralPath $responseRoot -File -Filter 'host-*.json' -ErrorAction SilentlyContinue | ForEach-Object Name)
$priorValues = @{}
foreach ($name in @('CHRONICLE_HARNESS_MODE','CHRONICLE_AGENT_PROFILE_PATH','CHRONICLE_AGENT_HOST_TEST_PATH','CHRONICLE_HARNESS_AGENT_AUTO_START','CHRONICLE_HARNESS_AGENT_AUTO_STOP_AFTER_MS','CHRONICLE_HARNESS_AGENT_GOAL','CHRONICLE_HARNESS_AGENT_NO_MODEL','CHRONICLE_HARNESS_AGENT_FAILURE_CASE','CHRONICLE_HARNESS_AGENT_IGNORE_STOP','CHRONICLE_HARNESS_AGENT_START_STATE','CHRONICLE_HARNESS_AGENT_ROUNDTRIP','CHRONICLE_HARNESS_AGENT_ROUNDTRIP_SAVE_ID','CHRONICLE_HARNESS_AGENT_INPUT_FOCUS_TEST','CHRONICLE_HARNESS_AGENT_INPUT_TOGGLE_TEST')) {
    $priorValues[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
$gameProcessId = 0
$hostProcessId = 0
$loadReceipt = $null
$baseline = $null
$trainingFieldMenuExitApplied = $false
$endingState = $null
$stopReceipt = $null
$failure = $null
$states = @()
$hostReadyEvents = @()
$inputOwnershipEvents = @()
$nativeHandshakeVerified = $false
$nativeSessionGuardVerified = $false
$startupRejectionCases = @()
$duplicateStartVerified = $false
$hostReceipt = $null
$completionVerified = $false
$parentExitVerified = $false
$parentExitHostExitCode = $null
$parentExitSeconds = $null
$stopTimeoutVerified = $false
$nonMapRejected = $false
$campaignRoundtripVerified = $false
$oldNativeSession = $null
$newNativeSession = $null
$roundtripSaveName = if ($Scenario -eq 'CampaignRoundtrip') { 'ChronicleRT-' + [Guid]::NewGuid().ToString('N') } else { $null }
$roundtripSavePath = if ($roundtripSaveName) { Join-Path $saveDirectory ($roundtripSaveName + '.sav') } else { $null }
$roundtripSaveCreationRequested = $false
$roundtripSaveCreated = $false
$roundtripSaveHash = $null
$lastMoveTargetId = $null
$nativeWriteActions = @()
$hostExitEvents = @()
$hostExitObservedEvents = @()
$watch = [Diagnostics.Stopwatch]::StartNew()

function Invoke-LifecycleCli([string]$Action, [string[]]$Arguments = @()) {
    $output = & $HarnessPowerShell -NoProfile -File $cli $Action @Arguments -TimeoutSeconds $TimeoutSeconds -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Lifecycle CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Lifecycle CLI '$Action' returned invalid JSON." }
}

try {
    $env:CHRONICLE_HARNESS_MODE = 'agent-host-lifecycle-test'
    $env:CHRONICLE_AGENT_PROFILE_PATH = $profilePath
    $env:CHRONICLE_AGENT_HOST_TEST_PATH = $hostPath
    $env:CHRONICLE_HARNESS_AGENT_AUTO_START = '1'
    $effectiveAutoStopAfterMilliseconds = if ($Scenario -eq 'InputToggle') { 10000 } else { $AutoStopAfterMilliseconds }
    $env:CHRONICLE_HARNESS_AGENT_AUTO_STOP_AFTER_MS = if ($Scenario -in @('Stop','StopTimeout','InputToggle')) { [string]$effectiveAutoStopAfterMilliseconds } else { '0' }
    $env:CHRONICLE_HARNESS_AGENT_GOAL = if ($Scenario -eq 'Stop') { 'Inspect the current Native Campaign state and wait for the explicit stop request without changing the Campaign.' } elseif ($expectsUnsupportedGoal) { 'Become clan tier 1 (50 renown).' } else { 'Move the current party to any one currently visible safe settlement.' }
    $env:CHRONICLE_HARNESS_AGENT_NO_MODEL = if ($usesIdleProvider) { '1' } else { '0' }
    $env:CHRONICLE_HARNESS_AGENT_FAILURE_CASE = if ($expectsFailure) { $Scenario } else { '' }
    $env:CHRONICLE_HARNESS_AGENT_IGNORE_STOP = if ($Scenario -eq 'StopTimeout') { '1' } else { '' }
    $env:CHRONICLE_HARNESS_AGENT_START_STATE = if ($Scenario -eq 'NonMap') { 'InventoryState' } else { 'MapState' }
    $env:CHRONICLE_HARNESS_AGENT_INPUT_FOCUS_TEST = if ($Scenario -eq 'Stop') { '1' } else { '0' }
    $env:CHRONICLE_HARNESS_AGENT_INPUT_TOGGLE_TEST = if ($Scenario -eq 'InputToggle') { '1' } else { '0' }
    $env:CHRONICLE_HARNESS_AGENT_ROUNDTRIP = if ($Scenario -eq 'CampaignRoundtrip') { '1' } else { '' }
    $env:CHRONICLE_HARNESS_AGENT_ROUNDTRIP_SAVE_ID = if ($Scenario -eq 'CampaignRoundtrip') { $roundtripSaveName.Substring('ChronicleRT-'.Length) } else { '' }

    $diagnosticRunStartedUtc = [DateTime]::UtcNow
    $loadReceipt = Invoke-LifecycleCli 'load' @('-SaveName', $SaveName)
    if ($loadReceipt.status -ne 'completed' -or -not $loadReceipt.session.processId) { throw 'The lifecycle fixture did not reach its Native Campaign handshake.' }
    $gameProcessId = [int]$loadReceipt.session.processId
    $baseline = Invoke-LifecycleCli 'state'
    if ($baseline.status -ne 'completed' -or $baseline.state.context.gameState -ne 'MapState') { throw 'Lifecycle baseline was not a current Campaign Map observation.' }
    if ($baseline.state.context.menuId -eq 'training_field_menu') {
        $nativeLeave = @($baseline.state.availableMenuOptions | Where-Object { $_.id -eq 'training_field_leave' -and $_.enabled -eq $true })
        if ($nativeLeave.Count -ne 1) { throw 'Training-field lifecycle fixture has no current enabled Native Leave option.' }
        $leaveTrainingField = Invoke-LifecycleCli 'menuSelect' @('-MenuId','training_field_menu','-OptionId','training_field_leave')
        if ($leaveTrainingField.status -ne 'completed') { throw 'Disposable lifecycle fixture could not leave the training field through the current Native menu option.' }
        $trainingFieldMenuExitApplied = $true
        $baseline = Invoke-LifecycleCli 'state'
        if ($baseline.status -ne 'completed' -or $baseline.state.context.gameState -ne 'MapState' -or
            $baseline.state.context.menuId -eq 'training_field_menu' -or $baseline.state.context.inquiryOpen -eq $true -or
            $baseline.state.context.escapeMenuOpen -eq $true) {
            throw 'Lifecycle focus-loss baseline did not settle on the free Campaign Map after the Native training-field Leave.'
        }
    }
    if ($Scenario -eq 'NonMap') {
        $inventoryReceipt = Invoke-LifecycleCli 'inventoryOpen'
        if ($inventoryReceipt.status -ne 'completed') { throw 'The non-map fixture could not open the existing Native inventory entry.' }
    }
    if ($Scenario -eq 'CampaignRoundtrip') {
        if (Test-Path -LiteralPath $roundtripSavePath) { throw 'The one-time Campaign roundtrip save name already exists; no save was attempted.' }
        $spaceRequired = (Get-Item -LiteralPath $savePath).Length + 1073741824
        $saveDrive = [IO.Path]::GetPathRoot($saveDirectory).TrimEnd('\').TrimEnd(':')
        if ((Get-PSDrive -Name $saveDrive).Free -lt $spaceRequired) { throw 'Insufficient free space for one temporary native roundtrip save; no save was attempted.' }
        $saveRequest = Invoke-LifecycleCli 'save' @('-SaveName', $roundtripSaveName)
        if ($saveRequest.status -ne 'accepted' -or [string]::IsNullOrWhiteSpace([string]$saveRequest.commandId)) {
            throw 'Native did not accept creation of the isolated roundtrip test save.'
        }
        $roundtripSaveCreationRequested = $true
        $saveResponsePath = Join-Path $responseRoot ($saveRequest.commandId + '.completed.json')
        $saveRejectedPath = Join-Path $responseRoot ($saveRequest.commandId + '.rejected.json')
        $saveDeadline = [DateTime]::UtcNow.AddSeconds(120)
        while (-not (Test-Path -LiteralPath $saveResponsePath -PathType Leaf) -and -not (Test-Path -LiteralPath $saveRejectedPath -PathType Leaf) -and [DateTime]::UtcNow -lt $saveDeadline) {
            Start-Sleep -Milliseconds 250
        }
        if (Test-Path -LiteralPath $saveRejectedPath -PathType Leaf) { throw 'Native rejected creation of the isolated roundtrip test save.' }
        if (-not (Test-Path -LiteralPath $saveResponsePath -PathType Leaf) -or -not (Test-Path -LiteralPath $roundtripSavePath -PathType Leaf)) {
            throw 'Native did not finish the isolated roundtrip test save within two minutes.'
        }
        $roundtripSaveCreated = $true
        $completedSave = Get-Content -LiteralPath $saveResponsePath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($completedSave.action -ne 'save' -or $completedSave.status -ne 'completed' -or
            $completedSave.processId -ne $gameProcessId -or $completedSave.nativeSessionId -ne $baseline.nativeSessionId) {
            throw 'Temporary SaveAs completion did not match the current disposable Campaign PID/session.'
        }
        $roundtripSaveHash = (Get-FileHash -LiteralPath $roundtripSavePath -Algorithm SHA256).Hash
        [IO.File]::WriteAllText((Join-Path $harnessTemp 'CampaignRoundtrip.proceed'), 'Baseline Native handshake verified.')
    }

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        Start-Sleep -Milliseconds 250
        if (-not (Test-Path -LiteralPath $diagnosticLog -PathType Leaf)) { continue }
        $lines = @(Get-Content -LiteralPath $diagnosticLog -Encoding UTF8)
        $runLines = @($lines | Where-Object {
            $timestampMatch = [regex]::Match($_, '^(?<utc>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z)\|')
            if (-not $timestampMatch.Success) { return $false }
            [DateTimeOffset]::Parse($timestampMatch.Groups['utc'].Value).UtcDateTime -ge $diagnosticRunStartedUtc
        })
        $gameLines = @($runLines | Where-Object { $_ -match "\|pid=$gameProcessId\|agent-host-" })
        $rejectionLines = @($runLines | Where-Object { $_ -match "\|pid=$gameProcessId\|harness-agent-start-rejection\|" })
        if (@($runLines | Where-Object { $_ -match "\|pid=$gameProcessId\|harness-agent-start-rejection-failed\|" }).Count -gt 0) {
            throw 'A startup rejection fixture failed; no normal Host launch was attempted.'
        }
        $duplicateStartLines = @($runLines | Where-Object { $_ -match "\|pid=$gameProcessId\|harness-agent-duplicate-start\|" })
        $states = @($gameLines | Where-Object { $_ -match '\|agent-host-state\|' })
        $hostReadyEvents = @($gameLines | Where-Object { $_ -match '\|agent-host-ready\|' })
        $startedLine = @($gameLines | Where-Object { $_ -match '\|agent-host-process-started\|' } | Select-Object -Last 1)
        $hostExitEvents = @($gameLines | Where-Object { $_ -match '\|agent-host-process-exit\|' })
        $hostExitObservedEvents = @($gameLines | Where-Object { $_ -match '\|agent-host-process-exit-observed\|' })
        $inputOwnershipEvents = @($runLines | Where-Object {
            $_ -match "\|pid=$gameProcessId\|agent-input-(layer-installed|focus-guard-installed|mission-input-blocked|mission-input-restored|focus-baseline|layer-probe|routing-probe(-injected)?|toggle-harness-probe)\|" -or
            $_ -match "\|pid=$gameProcessId\|agent-input-toggle\|" -or
            $_ -match "\|pid=$gameProcessId\|agent-input-routing-probe\|" -or
            $_ -match "\|pid=$gameProcessId\|agent-input-focus-(probe|restored-probe)\|" -or
            $_ -match "\|pid=$gameProcessId\|agent-player-input-owner\|"
        })
        $toggleCycleCompleteLines = @($inputOwnershipEvents | Where-Object { $_ -match '\|agent-input-toggle-harness-probe\|passed=True\|cycle=agent-player-agent-player$' })
        $toggleCycleFailedLines = @($inputOwnershipEvents | Where-Object { $_ -match '\|agent-input-toggle-harness-probe\|passed=False\|' })
        $roundtripLines = @($runLines | Where-Object { $_ -match "\|pid=$gameProcessId\|harness-agent-campaign-roundtrip-complete\|" })
        if (@($runLines | Where-Object { $_ -match "\|pid=$gameProcessId\|harness-agent-campaign-roundtrip-failed\|" }).Count -gt 0) { throw 'Native Campaign roundtrip fixture failed; see the game diagnostics.' }
        if ($Scenario -eq 'CampaignRoundtrip' -and $roundtripLines.Count -eq 1) { break }
        if ($Scenario -eq 'InputToggle' -and $toggleCycleCompleteLines.Count -eq 1 -and $hostExitEvents.Count -ge 2) { break }
        if ($Scenario -eq 'InputToggle' -and $toggleCycleFailedLines.Count -gt 0) { break }
        if ($startedLine.Count -gt 0 -and $startedLine[0] -match '\|agent-host-process-started\|pid=(\d+)\|') { $hostProcessId = [int]$Matches[1] }
        $sawStopped = @($states | Where-Object { $_ -match '\|state=Stopped\|' }).Count -gt 0
        $sawCompleted = @($states | Where-Object { $_ -match '\|state=Completed\|' }).Count -gt 0
        $sawFailed = @($states | Where-Object { $_ -match '\|state=Failed\|' }).Count -gt 0
        if ($Scenario -eq 'NonMap' -and $sawFailed) { break }
        if ($Scenario -eq 'Stop' -and $sawFailed -and $startedLine.Count -eq 0) { break }
        if ($Scenario -eq 'ParentExited' -and $hostProcessId -gt 0 -and $hostReadyEvents.Count -gt 0) { break }
        if ($Scenario -notin @('CampaignRoundtrip','InputToggle') -and ((($sawStopped -or $sawCompleted) -and $hostExitEvents.Count -gt 0) -or ($sawFailed -and $startedLine.Count -gt 0))) { break }
    } while ([DateTime]::UtcNow -lt $deadline)

    $hostReceiptPath = Join-Path $harnessTemp 'AgentHostLifecycleHostReceipt.json'
    if (Test-Path -LiteralPath $hostReceiptPath -PathType Leaf) {
        $hostReceipt = Get-Content -LiteralPath $hostReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }

    if ($Scenario -eq 'NonMap') {
        $nonMapState = Invoke-LifecycleCli 'state'
        $nonMapRejected = ($hostProcessId -eq 0 -and $startedLine.Count -eq 0 -and $hostReadyEvents.Count -eq 0 -and
            $nonMapState.state.context.gameState -eq 'InventoryState' -and
            @($states | Where-Object { $_ -match '\|state=Starting\|' }).Count -eq 1 -and
            @($states | Where-Object { $_ -match '\|state=Failed\|' }).Count -eq 1)
        if (-not $nonMapRejected) { throw 'Non-map Start was not rejected before creating a Host while Native inventory remained open.' }
        $inventoryCancel = Invoke-LifecycleCli 'inventoryCancel'
        $endingState = Invoke-LifecycleCli 'state'
        if ($inventoryCancel.status -ne 'completed' -or $endingState.state.context.gameState -ne 'MapState' -or
            $endingState.state.economy.gold -ne $baseline.state.economy.gold -or
            $endingState.state.location.currentSettlementId -cne $baseline.state.location.currentSettlementId) {
            throw 'Non-map fixture did not return through Native inventory cancel without changing location/gold.'
        }
    }
    else {
    if ($hostProcessId -le 0) { throw 'The game did not start a child Agent Host process.' }
    foreach ($case in $(if ($Scenario -eq 'Stop') { @('empty-goal','oversized-goal','remote-endpoint','empty-model','missing-host') } else { @() })) {
        if (@($rejectionLines | Where-Object { $_ -match "\|case=$case\|state=Failed\|hostCreated=False" }).Count -ne 1) {
            throw "Startup rejection fixture was not verified exactly once: $case"
        }
        $startupRejectionCases += $case
    }
    $hostStartLines = @($gameLines | Where-Object { $_ -match '\|agent-host-process-started\|' })
    if ($Scenario -eq 'InputToggle') {
        $startPids = @($hostStartLines | ForEach-Object { if ($_ -match '\|agent-host-process-started\|pid=(\d+)\|') { $Matches[1] } })
        $duplicateStartVerified = $startPids.Count -eq 2 -and $startPids[0] -ne $startPids[1] -and $hostExitEvents.Count -ge 2
    }
    else {
        $duplicateStartVerified = (@($duplicateStartLines | Where-Object { $_ -match "\|hostPid=$hostProcessId\|unchanged=True" }).Count -eq 1 -and $hostStartLines.Count -eq 1)
    }
    if (-not $expectsProviderPreflightFailure -and -not $duplicateStartVerified) { throw 'Repeated MCM Start did not preserve exactly one owned Host process.' }
    $nativeHandshakeVerified = @($hostReadyEvents | Where-Object {
        $_ -match "\|agent-host-ready\|hostPid=$hostProcessId\|protocol=1\|version=.+"
    }).Count -eq 1
    if (-not $expectsProviderPreflightFailure -and -not $nativeHandshakeVerified) { throw 'The controller did not verify a versioned Host handshake bound to the current Native Bannerlord process.' }
    if ($expectsProviderPreflightFailure -and $hostReadyEvents.Count -gt 0) { throw 'Host reported Ready before its failing provider health check.' }
    if ($Scenario -eq 'CampaignRoundtrip') {
        if ($roundtripLines.Count -ne 1 -or $roundtripLines[0] -notmatch '\|oldSession=([^|]+)\|newSession=([^|\r\n]+)') { throw 'Native same-process Campaign reload did not complete.' }
        $oldNativeSession = $Matches[1]
        $newNativeSession = $Matches[2]
        $endingState = Invoke-LifecycleCli 'state'
        $target = @($endingState.state.nearbySettlements | Where-Object { -not $_.hostile -and -not $_.underSiege } | Select-Object -First 1)
        if ($target.Count -ne 1) { throw 'Reloaded fixture has no observed safe settlement for the stale-command rejection probe.' }
        $staleMove = Invoke-LifecycleCli 'move' @('-SettlementId',[string]$target[0].id,'-ExpectedNativeSessionId',$oldNativeSession)
        $nativeSessionGuardVerified = ($staleMove.status -eq 'rejected' -and $staleMove.error -eq 'native-session-mismatch' -and
            $staleMove.nativeSessionId -eq $newNativeSession -and $staleMove.state.economy.gold -eq $endingState.state.economy.gold -and
            $staleMove.state.location.targetSettlementId -ceq $endingState.state.location.targetSettlementId -and $staleMove.timeControlMode -eq $endingState.timeControlMode)
        $campaignRoundtripVerified = ($oldNativeSession -eq $baseline.nativeSessionId -and $oldNativeSession -ne $newNativeSession -and
            $endingState.processId -eq $gameProcessId -and $endingState.nativeSessionId -eq $newNativeSession -and
            $endingState.state.context.gameState -eq 'MapState' -and $nativeSessionGuardVerified -and
            @(Get-Process -Id $hostProcessId -ErrorAction SilentlyContinue).Count -eq 0 -and
            @($gameLines | Where-Object { $_ -match '\|agent-host-process-started\|' }).Count -eq 1 -and $hostExitEvents.Count -eq 1)
        if (-not $campaignRoundtripVerified) { throw 'Same-process reload did not preserve game PID, end the old Host, or reject its stale-session move without side effects.' }
        $roundtripSaveHash = (Get-FileHash -LiteralPath $roundtripSavePath -Algorithm SHA256).Hash
    }
    elseif ($Scenario -eq 'ParentExited') {
        $ownedGame = Get-Process -Id $gameProcessId -ErrorAction Stop
        $ownedHost = Get-Process -Id $hostProcessId -ErrorAction Stop
        $installedGameRoot = [IO.Path]::GetFullPath([string](Get-Content (Join-Path $harnessRoot 'harness.local.json') -Raw | ConvertFrom-Json).gameRoot).TrimEnd('\') + '\'
        if (-not $ownedGame.Path.StartsWith($installedGameRoot, [StringComparison]::OrdinalIgnoreCase) -or
            [IO.Path]::GetFullPath($ownedHost.Path) -cne [IO.Path]::GetFullPath($hostPath)) {
            throw 'Disposable game/Host process identity differs from the loaded fixture; refusing forced exit.'
        }
        $null = $ownedHost.Handle
        $exitClock = [Diagnostics.Stopwatch]::StartNew()
        Stop-Process -Id $gameProcessId -Force -ErrorAction Stop
        $parentExitVerified = $ownedHost.WaitForExit(10000)
        $parentExitSeconds = [Math]::Round($exitClock.Elapsed.TotalSeconds, 3)
        if (-not $parentExitVerified) { throw 'Host did not independently exit after its disposable Bannerlord parent was terminated.' }
        $parentExitHostExitCode = $ownedHost.ExitCode
        $ownedHost.Dispose()
        $ownedGame.Dispose()
        $newResponses = @(Get-ChildItem -LiteralPath $responseRoot -File -Filter 'host-*.json' | Where-Object { $_.Name -notin $hostResponseFilesBefore })
        foreach ($responseFile in $newResponses) {
            try { $response = Get-Content -LiteralPath $responseFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json }
            catch { throw 'The parent-exit Native response file could not be read as UTF-8 JSON.' }
            if ($response.action -ne 'state') { throw 'Parent-exit idle fixture issued a Native world action.' }
        }
    }
    else {
    $expectedStates = if ($expectsFailure -and -not $expectsUnsupportedGoal) { @('Starting','Failed') } elseif ($expectsUnsupportedGoal) { @('Starting','Running','Failed') } elseif ($Scenario -eq 'StopTimeout') { @('Starting','Running','Stopping','Failed') } elseif ($Scenario -in @('Stop','InputToggle')) { @('Starting','Running','Stopping','Stopped') } else { @('Starting','Running','Completed') }
    foreach ($expectedState in $expectedStates) {
        if (@($states | Where-Object { $_ -match "\|state=$expectedState\|" }).Count -eq 0) {
            throw "The lifecycle controller did not report expected state: $expectedState"
        }
    }
    if (@(Get-Process -Id $hostProcessId -ErrorAction SilentlyContinue).Count -gt 0) { throw 'The Agent Host remained alive after its Stop result.' }
    if ($Scenario -eq 'StopTimeout') {
        $timeoutStates = @($states | Where-Object { $_ -match '\|state=Failed\|detail=Host' })
        $stoppingStates = @($states | Where-Object { $_ -match '\|state=Stopping\|' })
        $stopTimeoutVerified = ($timeoutStates.Count -eq 1 -and $stoppingStates.Count -eq 1 -and $hostExitEvents.Count -eq 0 -and
            ([DateTime]::Parse($timeoutStates[0].Split('|')[0]) - [DateTime]::Parse($stoppingStates[0].Split('|')[0])).TotalSeconds -ge 5)
        if (-not $stopTimeoutVerified) { throw 'Stop timeout did not end the owned Host and report its explicit timeout failure.' }
    }
    else {
    $expectedTerminalState = if ($expectsFailure) { 'Failed' } elseif ($Scenario -in @('Stop','InputToggle')) { 'Stopped' } else { 'Completed' }
    $expectedExitCode = if ($expectsFailure) { 1 } else { 0 }
    if (@($hostExitEvents | Where-Object { $_ -match "\|pid=$hostProcessId\|exitCode=$expectedExitCode\|state=$expectedTerminalState" }).Count -ne 1) {
        throw 'The owned Host did not exit with its expected successful terminal state.'
    }
    if (-not $hostReceipt) { throw 'Game-owned Host did not leave its sanitized lifecycle receipt.' }
    }

    $endingState = Invoke-LifecycleCli 'state'
    if ($endingState.status -ne 'completed' -or [string]$endingState.state.context.gameState -cne [string]$baseline.state.context.gameState) {
        throw 'Native Campaign could not be observed after Host exit.'
    }
    if (($usesIdleProvider -or $expectsFailure) -and
        ([string]$endingState.state.location.currentSettlementId -cne [string]$baseline.state.location.currentSettlementId -or
        [string]$endingState.state.location.targetSettlementId -cne [string]$baseline.state.location.targetSettlementId)) {
        throw 'Stopping the Host changed the active Native location/movement state in this cancellation-window test.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$endingState.nativeSessionId)) { throw 'Native observation did not identify its loaded Campaign bridge session.' }
    $staleSessionReceipt = Invoke-LifecycleCli 'state' @('-ExpectedNativeSessionId','harness-stale-native-session')
    $nativeSessionGuardVerified = ($staleSessionReceipt.status -eq 'rejected' -and $staleSessionReceipt.error -eq 'native-session-mismatch' -and
        $staleSessionReceipt.nativeSessionId -ceq $endingState.nativeSessionId -and
        $staleSessionReceipt.state.economy.gold -eq $endingState.state.economy.gold -and
        $staleSessionReceipt.state.location.currentSettlementId -ceq $endingState.state.location.currentSettlementId)
    if (-not $nativeSessionGuardVerified) { throw 'The Native bridge did not safely reject a command bound to a stale loaded Campaign session.' }

    $responseFiles = @(Get-ChildItem -LiteralPath $responseRoot -File -Filter 'host-*.json' -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin $hostResponseFilesBefore } | Sort-Object LastWriteTimeUtc)
    foreach ($responseFile in $responseFiles) {
        $response = Get-Content -LiteralPath $responseFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($response.action -notin @('state','mapSettlementTargets','move')) { throw 'Unexpected Host action outside the approved map slice.' }
        if ($response.action -in @('mapSettlementTargets','move')) { $nativeWriteActions += [string]$response.action }
        if ($response.action -eq 'move' -and $response.status -eq 'completed') { $lastMoveTargetId = [string]$response.state.location.targetSettlementId }
    }
    if ($Scenario -eq 'StopTimeout') {
        if ($nativeWriteActions.Count -gt 0) { throw 'Stop-timeout idle fixture issued a world action.' }
    }
    elseif ($expectsFailure) {
        $expectedFailureCode = if ($Scenario -eq 'MissingModel') { 'provider-model-unavailable' } elseif ($Scenario -eq 'ServiceUnavailable') { 'provider-unavailable' } else { 'campaign-goal-unsupported' }
        $expectedDecisionCount = if ($expectsUnsupportedGoal) { 1 } else { 0 }
        $unapprovedNativeActions = @($responseFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } | Where-Object { $_.action -notin @('state') })
        if ($hostReceipt.status -ne 'failed' -or $hostReceipt.failureCode -ne $expectedFailureCode -or
            $hostReceipt.decisionCount -ne $expectedDecisionCount -or $hostReceipt.actionsExecuted -ne 0 -or $unapprovedNativeActions.Count -gt 0) {
            throw 'Provider or goal-scope failure did not stop before a Native action with its expected classification.'
        }
    }
    elseif ($Scenario -in @('Stop','InputToggle')) {
        if ($nativeWriteActions.Count -gt 0 -or $hostReceipt.decisionCount -ne 0 -or $hostReceipt.actionsExecuted -ne 0 -or
            $hostReceipt.providerConfigurationSource -ne 'harness-only-no-model-lifecycle-test') {
            throw 'Stop fixture must remain an idle-provider lifecycle test with zero decisions and goal actions.'
        }
    }
    else {
        $completionVerified = ($hostReceipt.status -eq 'completed' -and $hostReceipt.termination.goalVerified -eq $true -and
            $hostReceipt.termination.completedByProvider -eq $true -and $hostReceipt.providerConfigurationSource -eq 'mcm-start-request' -and
            $hostReceipt.providerModelId -eq $providerModelId -and $hostReceipt.decisionCount -gt 0 -and
            $nativeWriteActions -contains 'mapSettlementTargets' -and $nativeWriteActions -contains 'move' -and
            -not [string]::IsNullOrWhiteSpace($lastMoveTargetId) -and $endingState.state.location.currentSettlementId -ceq $lastMoveTargetId)
        if (-not $completionVerified) { throw 'Real game-launched Host did not verify Native arrival and report Completed using the current MCM model snapshot.' }
    }
    }
    }
}
catch { $failure = $_.Exception.Message }
finally {
    if (Test-Path -LiteralPath $sessionPath -PathType Leaf) {
        try {
            if ($Scenario -eq 'ParentExited' -and -not (Get-Process -Id $gameProcessId -ErrorAction SilentlyContinue)) {
                $remainingHost = Get-Process -Id $hostProcessId -ErrorAction SilentlyContinue
                if ($remainingHost -and [IO.Path]::GetFullPath($remainingHost.Path) -ceq [IO.Path]::GetFullPath($hostPath)) {
                    Stop-Process -Id $hostProcessId -Force
                }
                $cleanup = & $HarnessPowerShell -NoProfile -File $cli recoverTestConfig -AsJson 2>&1 | Out-String
                if ($LASTEXITCODE -ne 0) { throw 'Parent-exit fixture session/config cleanup failed.' }
                $stopReceipt = $cleanup | ConvertFrom-Json
                if (-not $stopReceipt.restored) { throw 'Parent-exit fixture did not restore its original engine configuration.' }
                $staleSession = Get-Content -LiteralPath $sessionPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ([int]$staleSession.processId -ne $gameProcessId) { throw 'Refusing to remove a different Campaign session during parent-exit cleanup.' }
                Remove-Item -LiteralPath $sessionPath -Force
            }
            else {
                $cleanup = & $HarnessPowerShell -NoProfile -File $cli stop -TimeoutSeconds 5 -AsJson 2>&1 | Out-String
                if ($LASTEXITCODE -ne 0) { throw 'Lifecycle fixture cleanup failed.' }
                $stopReceipt = $cleanup | ConvertFrom-Json
            }
        } catch { if (-not $failure) { $failure = $_.Exception.Message } }
    }
    $watch.Stop()
    foreach ($name in $priorValues.Keys) {
        if ($null -eq $priorValues[$name]) { Remove-Item "Env:$name" -ErrorAction SilentlyContinue }
        else { [Environment]::SetEnvironmentVariable($name, $priorValues[$name], 'Process') }
    }
}

$processesStopped = @(Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue).Count -eq 0
$sessionClean = -not (Test-Path -LiteralPath $sessionPath -PathType Leaf)
$fixtureHashAfter = if (Test-Path -LiteralPath $savePath -PathType Leaf) { (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash } else { $null }
$fixtureUnchanged = $fixtureHashBefore -eq $fixtureHashAfter
$roundtripSaveRemoved = ($Scenario -ne 'CampaignRoundtrip')
$inputLayerInstalled = @($inputOwnershipEvents | Where-Object { $_ -match '\|agent-input-layer-installed\|' }).Count -eq 1
$focusGuardInstalled = @($inputOwnershipEvents | Where-Object { $_ -match '\|agent-input-focus-guard-installed\|' }).Count -eq 1
$agentOwnerEvent = @($inputOwnershipEvents | Where-Object { $_ -match '\|agent-player-input-owner\|owner=agent$' } | Select-Object -First 1)
$playerOwnerEvent = @($inputOwnershipEvents | Where-Object { $_ -match '\|agent-player-input-owner\|owner=player$' } | Select-Object -Last 1)
$focusProbeEvents = @($inputOwnershipEvents | Where-Object { $_ -match '\|agent-input-focus-probe\|' })
$focusSuppressionEvent = @($focusProbeEvents | Where-Object { $_ -match '\|passed=True\|.*\|nativeBaselinePermission=True\|' })
$focusGuardOwnerPrefixEvent = @($focusProbeEvents | Where-Object { $_ -match '\|guardPrefixOverride=True\|' })
$focusCallbackEscapeClosedEvent = @($focusProbeEvents | Where-Object { $_ -match '\|callbackEscapeStayedClosed=True\|' })
$focusRestorationEvent = @($inputOwnershipEvents | Where-Object { $_ -match '\|agent-input-focus-restored-probe\|passed=True\|' })
$focusGuardPlayerPrefixEvent = @($focusRestorationEvent | Where-Object { $_ -match '\|guardPrefixPassthrough=True(?:\||$)' })
$screenLayerProbeEvent = @($inputOwnershipEvents | Where-Object { $_ -match '\|agent-input-layer-probe\|passed=True\|present=True\|topmost=True\|mask=All\|focus=True\|hitTest=True$' })
$screenInputRoutingEvent = @($inputOwnershipEvents | Where-Object { $_ -match '\|agent-input-routing-probe\|' })
$screenInputRoutingPassed = @($screenInputRoutingEvent | Where-Object { $_ -match '\|mousePassed=True\|escapePassed=True\|' }).Count -eq 1
$inputToggleRequestEvent = @($inputOwnershipEvents | Where-Object { $_ -match '\|agent-input-toggle\|direction=agent-to-player$' })
$inputToggleResumeEvent = @($inputOwnershipEvents | Where-Object { $_ -match '\|agent-input-toggle\|direction=player-to-agent$' })
$inputToggleHarnessPassEvent = @($inputOwnershipEvents | Where-Object { $_ -match '\|agent-input-toggle-harness-probe\|passed=True\|cycle=agent-player-agent-player$' })
$inputToggleAgentOwnerEvents = @($inputOwnershipEvents | Where-Object { $_ -match '\|agent-player-input-owner\|owner=agent$' })
$inputTogglePlayerOwnerEvents = @($inputOwnershipEvents | Where-Object { $_ -match '\|agent-player-input-owner\|owner=player$' })
$hostExitEvent = @($hostExitObservedEvents | Select-Object -Last 1)
$inputOwnershipAutoReleasedAfterHostExit = $agentOwnerEvent.Count -eq 1 -and $playerOwnerEvent.Count -eq 1 -and $hostExitEvent.Count -eq 1 -and
    [string]$playerOwnerEvent[0] -match '^([^|]+)\|' -and [string]$hostExitEvent[0] -match '^([^|]+)\|' -and
    [DateTime]::Parse([string]$hostExitEvent[0].Split('|')[0]).ToUniversalTime() -le [DateTime]::Parse([string]$playerOwnerEvent[0].Split('|')[0]).ToUniversalTime()
$inputTogglePlayerReturnVerified = $Scenario -eq 'InputToggle' -and $inputToggleRequestEvent.Count -eq 2 -and $inputToggleResumeEvent.Count -eq 1 -and
    $inputToggleHarnessPassEvent.Count -eq 1 -and $inputToggleAgentOwnerEvents.Count -eq 2 -and
    $inputTogglePlayerOwnerEvents.Count -eq 2 -and $hostReadyEvents.Count -eq 2 -and $hostExitEvents.Count -ge 2 -and
    $duplicateStartVerified -and $nativeWriteActions.Count -eq 0
$inputOwnershipSafeHandoffVerified = $inputLayerInstalled -and $focusGuardInstalled -and $agentOwnerEvent.Count -eq 1 -and
    $playerOwnerEvent.Count -eq 1 -and $hostExitEvent.Count -eq 1 -and $focusGuardOwnerPrefixEvent.Count -eq 1 -and $focusGuardPlayerPrefixEvent.Count -eq 1 -and $focusRestorationEvent.Count -eq 1 -and $screenLayerProbeEvent.Count -eq 1 -and
    [string]$agentOwnerEvent[0] -match '^([^|]+)\|' -and [string]$playerOwnerEvent[0] -match '^([^|]+)\|' -and
    [string]$hostExitEvent[0] -match '^([^|]+)\|' -and
    [DateTime]::Parse([string]$agentOwnerEvent[0].Split('|')[0]).ToUniversalTime() -le [DateTime]::Parse([string]$hostExitEvent[0].Split('|')[0]).ToUniversalTime() -and
    [DateTime]::Parse([string]$hostExitEvent[0].Split('|')[0]).ToUniversalTime() -le [DateTime]::Parse([string]$playerOwnerEvent[0].Split('|')[0]).ToUniversalTime()
if ($Scenario -eq 'CampaignRoundtrip' -and $roundtripSaveCreationRequested -and $processesStopped -and (Test-Path -LiteralPath $roundtripSavePath -PathType Leaf)) {
    $allowedSaveRoot = [IO.Path]::GetFullPath($saveDirectory).TrimEnd('\') + '\'
    $actualRoundtripPath = [IO.Path]::GetFullPath($roundtripSavePath)
    if ($roundtripSaveName -and $actualRoundtripPath.StartsWith($allowedSaveRoot, [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($actualRoundtripPath) -ceq ($roundtripSaveName + '.sav')) {
        Remove-Item -LiteralPath $actualRoundtripPath -Force
    }
    $roundtripSaveRemoved = -not (Test-Path -LiteralPath $roundtripSavePath -PathType Leaf)
}
$passed = ($null -eq $failure -and $gameProcessId -gt 0 -and ($hostProcessId -gt 0 -or $nonMapRejected) -and $processesStopped -and $sessionClean -and $fixtureUnchanged -and ($Scenario -ne 'Stop' -or ($nativeWriteActions.Count -eq 0 -and $inputOwnershipSafeHandoffVerified)) -and ($Scenario -ne 'StopTimeout' -or $inputOwnershipAutoReleasedAfterHostExit) -and ($Scenario -ne 'InputToggle' -or $inputTogglePlayerReturnVerified) -and ($Scenario -ne 'ParentExited' -or $parentExitVerified) -and ($Scenario -ne 'CampaignRoundtrip' -or ($campaignRoundtripVerified -and $roundtripSaveCreated -and $roundtripSaveRemoved)))
$result = [pscustomobject][ordered]@{
    Passed = [bool]$passed
    Scenario = $Scenario
    ProviderKind = if ($expectsProviderPreflightFailure) { 'Local provider health rejection; zero generation and Native commands' } elseif ($expectsUnsupportedGoal) { 'Real local 4b goal classification through the game-launched Host' } elseif ($usesIdleProvider) { 'Harness-only idle provider; no model service or generation' } else { 'Real local 4b model through the game-launched Host' }
    GameProcessId = $gameProcessId
    DiagnosticsRunStartedUtc = $diagnosticRunStartedUtc.ToString('O')
    AgentHostProcessId = $hostProcessId
    ModelId = if ($hostReceipt) { $hostReceipt.providerModelId } else { $providerModelId }
    HostReceipt = $hostReceipt
    HostFailure = if ($hostReceipt) { [string]$hostReceipt.failure } else { $null }
    NativeArrivalCompleted = [bool]$completionVerified
    HostIndependentlyExitedAfterParentTermination = [bool]$parentExitVerified
    OwnedHostStopTimeoutVerified = [bool]$stopTimeoutVerified
    NonMapStartRejectedBeforeHostCreation = [bool]$nonMapRejected
    SameProcessCampaignRoundtripVerified = [bool]$campaignRoundtripVerified
    OldNativeSessionId = $oldNativeSession
    NewNativeSessionId = $newNativeSession
    RoundtripSaveName = $roundtripSaveName
    RoundtripSaveHash = $roundtripSaveHash
    RoundtripSaveCreated = [bool]$roundtripSaveCreated
    RoundtripSaveRemoved = [bool]$roundtripSaveRemoved
    ParentExitHostExitCode = $parentExitHostExitCode
    ParentExitSeconds = $parentExitSeconds
    EngineConfigRestoredAfterParentExit = if ($Scenario -eq 'ParentExited') { [bool]($stopReceipt -and $stopReceipt.restored) } else { $null }
    LastMoveTargetId = $lastMoveTargetId
    AutoStopAfterMilliseconds = $effectiveAutoStopAfterMilliseconds
    LifecycleStates = @($states | ForEach-Object { [string]$_ })
    NativeHandshakeVerified = [bool]$nativeHandshakeVerified
    TrainingFieldMenuExitApplied = [bool]$trainingFieldMenuExitApplied
    InputOwnershipSafeHandoffVerified = [bool]$inputOwnershipSafeHandoffVerified
    InputOwnershipAutoReleasedAfterHostExit = [bool]$inputOwnershipAutoReleasedAfterHostExit
    InputTogglePlayerReturnVerified = [bool]$inputTogglePlayerReturnVerified
    FocusLossEscapeSuppressionVerified = [bool]($focusSuppressionEvent.Count -eq 1)
    FocusGuardOwnerPrefixVerified = [bool]($focusGuardOwnerPrefixEvent.Count -eq 1)
    FocusGuardPlayerPrefixPassthroughVerified = [bool]($focusGuardPlayerPrefixEvent.Count -eq 1)
    FocusCallbackEscapeStayedClosed = [bool]($focusCallbackEscapeClosedEvent.Count -eq 1)
    NativeFocusEscapePermissionAllowedAtBaseline = [bool](@($focusProbeEvents | Where-Object { $_ -match '\|nativeBaselinePermission=True\|' }).Count -gt 0)
    ScreenLayerCaptureConfigurationVerified = [bool]($screenLayerProbeEvent.Count -eq 1)
    SyntheticScreenInputRoutingVerified = [bool]$screenInputRoutingPassed
    InputOwnershipEvents = @($inputOwnershipEvents | ForEach-Object { [string]$_ })
    NativeSessionGuardVerified = [bool]$nativeSessionGuardVerified
    StartupRejectionCases = @($startupRejectionCases)
    DuplicateStartVerified = [bool]$duplicateStartVerified
    HostReadyEvents = @($hostReadyEvents | ForEach-Object { [string]$_ })
    HostExitEvents = @($hostExitEvents | ForEach-Object { [string]$_ })
    HostExitObservedEvents = @($hostExitObservedEvents | ForEach-Object { [string]$_ })
    NativeGoalActions = @($nativeWriteActions | ForEach-Object { [string]$_ })
    GameStillUsableAfterHostStop = [bool]($endingState -and $endingState.status -eq 'completed')
    NativeLocationUnchanged = if ($Scenario -eq 'Stop') { [bool]($endingState -and $baseline -and $endingState.state.location.currentSettlementId -ceq $baseline.state.location.currentSettlementId) } else { $null }
    CampaignDayBefore = if ($baseline) { $baseline.campaignDay } else { $null }
    CampaignDayAfter = if ($endingState) { $endingState.campaignDay } else { $null }
    FixtureHashBefore = $fixtureHashBefore
    FixtureHashAfter = $fixtureHashAfter
    FixtureUnchanged = [bool]$fixtureUnchanged
    BannerlordProcessesStopped = [bool]$processesStopped
    CliSessionCleaned = [bool]$sessionClean
    WallClockSeconds = [Math]::Round($watch.Elapsed.TotalSeconds, 2)
    Failure = if ($null -eq $failure) { $null } else { [string]$failure }
}
$resultJson = ConvertTo-Json -InputObject $result -Depth 8
$resultJson | Set-Content -LiteralPath (Join-Path $runDirectory 'AgentHostLifecycleEvaluationResult.json') -Encoding UTF8
Write-Output $resultJson
if (-not $passed) { exit 1 }
