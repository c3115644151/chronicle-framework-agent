[CmdletBinding()]
param(
    [ValidateRange(90,300)][int]$TimeoutSeconds = 180,
    [ValidateRange(250,10000)][int]$AutoStopAfterMilliseconds = 250,
    [ValidateSet('Stop','Complete','MissingModel','ServiceUnavailable','ParentExited')][string]$Scenario = 'Stop',
    [string]$SaveName = 'AgentBridgeLifecycle'
)

$ErrorActionPreference = 'Stop'
$harnessTemp = $env:CHRONICLE_HARNESS_TEMP
if ([string]::IsNullOrWhiteSpace($harnessTemp) -or -not (Test-Path -LiteralPath $harnessTemp -PathType Container)) {
    throw 'Agent Host lifecycle evaluation requires an active Harness evidence directory.'
}
$runDirectory = Split-Path -Parent $harnessTemp
$harnessRoot = $PSScriptRoot
$cli = Join-Path $harnessRoot 'Agent-Cli.ps1'
$documents = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
$documentsRoot = Join-Path $documents 'Mount and Blade II Bannerlord'
$savePath = Join-Path $documentsRoot "Game Saves\$SaveName.sav"
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

$expectsFailure = $Scenario -in @('MissingModel','ServiceUnavailable')
$usesIdleProvider = $Scenario -in @('Stop','ParentExited')
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
foreach ($name in @('CHRONICLE_HARNESS_MODE','CHRONICLE_AGENT_PROFILE_PATH','CHRONICLE_AGENT_HOST_TEST_PATH','CHRONICLE_HARNESS_AGENT_AUTO_START','CHRONICLE_HARNESS_AGENT_AUTO_STOP_AFTER_MS','CHRONICLE_HARNESS_AGENT_GOAL','CHRONICLE_HARNESS_AGENT_NO_MODEL','CHRONICLE_HARNESS_AGENT_FAILURE_CASE')) {
    $priorValues[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
$gameProcessId = 0
$hostProcessId = 0
$loadReceipt = $null
$baseline = $null
$endingState = $null
$stopReceipt = $null
$failure = $null
$states = @()
$hostReadyEvents = @()
$nativeHandshakeVerified = $false
$nativeSessionGuardVerified = $false
$startupRejectionCases = @()
$duplicateStartVerified = $false
$hostReceipt = $null
$completionVerified = $false
$parentExitVerified = $false
$parentExitHostExitCode = $null
$parentExitSeconds = $null
$lastMoveTargetId = $null
$nativeWriteActions = @()
$hostExitEvents = @()
$watch = [Diagnostics.Stopwatch]::StartNew()

function Invoke-LifecycleCli([string]$Action, [string[]]$Arguments = @()) {
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli $Action @Arguments -TimeoutSeconds $TimeoutSeconds -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Lifecycle CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Lifecycle CLI '$Action' returned invalid JSON." }
}

try {
    $env:CHRONICLE_HARNESS_MODE = 'agent-host-lifecycle-test'
    $env:CHRONICLE_AGENT_PROFILE_PATH = $profilePath
    $env:CHRONICLE_AGENT_HOST_TEST_PATH = $hostPath
    $env:CHRONICLE_HARNESS_AGENT_AUTO_START = '1'
    $env:CHRONICLE_HARNESS_AGENT_AUTO_STOP_AFTER_MS = if ($Scenario -eq 'Stop') { [string]$AutoStopAfterMilliseconds } else { '0' }
    $env:CHRONICLE_HARNESS_AGENT_GOAL = if ($Scenario -eq 'Stop') { 'Inspect the current Native Campaign state and wait for the explicit stop request without changing the Campaign.' } else { 'Reach a currently visible safe nearby settlement. Finish only when fresh Native state confirms arrival.' }
    $env:CHRONICLE_HARNESS_AGENT_NO_MODEL = if ($usesIdleProvider) { '1' } else { '0' }
    $env:CHRONICLE_HARNESS_AGENT_FAILURE_CASE = if ($expectsFailure) { $Scenario } else { '' }

    $loadReceipt = Invoke-LifecycleCli 'load' @('-SaveName', $SaveName)
    if ($loadReceipt.status -ne 'completed' -or -not $loadReceipt.session.processId) { throw 'The lifecycle fixture did not reach its Native Campaign handshake.' }
    $gameProcessId = [int]$loadReceipt.session.processId
    $baseline = Invoke-LifecycleCli 'state'
    if ($baseline.status -ne 'completed' -or $baseline.state.context.gameState -ne 'MapState') { throw 'Lifecycle baseline was not a current Campaign Map observation.' }

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        Start-Sleep -Milliseconds 250
        if (-not (Test-Path -LiteralPath $diagnosticLog -PathType Leaf)) { continue }
        $lines = @(Get-Content -LiteralPath $diagnosticLog -Encoding UTF8)
        $gameLines = @($lines | Where-Object { $_ -match "\|pid=$gameProcessId\|agent-host-" })
        $rejectionLines = @($lines | Where-Object { $_ -match "\|pid=$gameProcessId\|harness-agent-start-rejection\|" })
        if (@($lines | Where-Object { $_ -match "\|pid=$gameProcessId\|harness-agent-start-rejection-failed\|" }).Count -gt 0) {
            throw 'A startup rejection fixture failed; no normal Host launch was attempted.'
        }
        $duplicateStartLines = @($lines | Where-Object { $_ -match "\|pid=$gameProcessId\|harness-agent-duplicate-start\|" })
        $states = @($gameLines | Where-Object { $_ -match '\|agent-host-state\|' })
        $hostReadyEvents = @($gameLines | Where-Object { $_ -match '\|agent-host-ready\|' })
        $startedLine = @($gameLines | Where-Object { $_ -match '\|agent-host-process-started\|' } | Select-Object -Last 1)
        $hostExitEvents = @($gameLines | Where-Object { $_ -match '\|agent-host-process-exit\|' })
        if ($startedLine.Count -gt 0 -and $startedLine[0] -match '\|agent-host-process-started\|pid=(\d+)\|') { $hostProcessId = [int]$Matches[1] }
        $sawStopped = @($states | Where-Object { $_ -match '\|state=Stopped\|' }).Count -gt 0
        $sawCompleted = @($states | Where-Object { $_ -match '\|state=Completed\|' }).Count -gt 0
        $sawFailed = @($states | Where-Object { $_ -match '\|state=Failed\|' }).Count -gt 0
        if ($Scenario -eq 'ParentExited' -and $hostProcessId -gt 0 -and $hostReadyEvents.Count -gt 0) { break }
        if ((($sawStopped -or $sawCompleted) -and $hostExitEvents.Count -gt 0) -or ($sawFailed -and $startedLine.Count -gt 0)) { break }
    } while ([DateTime]::UtcNow -lt $deadline)

    if ($hostProcessId -le 0) { throw 'The game did not start a child Agent Host process.' }
    foreach ($case in $(if ($Scenario -eq 'Stop') { @('empty-goal','oversized-goal','remote-endpoint','empty-model','missing-host') } else { @() })) {
        if (@($rejectionLines | Where-Object { $_ -match "\|case=$case\|state=Failed\|hostCreated=False" }).Count -ne 1) {
            throw "Startup rejection fixture was not verified exactly once: $case"
        }
        $startupRejectionCases += $case
    }
    $duplicateStartVerified = (@($duplicateStartLines | Where-Object { $_ -match "\|hostPid=$hostProcessId\|unchanged=True" }).Count -eq 1 -and
        @($gameLines | Where-Object { $_ -match '\|agent-host-process-started\|' }).Count -eq 1)
    if (-not $expectsFailure -and -not $duplicateStartVerified) { throw 'Repeated MCM Start did not preserve exactly one owned Host process.' }
    $nativeHandshakeVerified = @($hostReadyEvents | Where-Object {
        $_ -match "\|agent-host-ready\|hostPid=$hostProcessId\|protocol=1\|version=.+"
    }).Count -eq 1
    if (-not $expectsFailure -and -not $nativeHandshakeVerified) { throw 'The controller did not verify a versioned Host handshake bound to the current Native Bannerlord process.' }
    if ($expectsFailure -and $hostReadyEvents.Count -gt 0) { throw 'Host reported Ready before its failing provider health check.' }
    if ($Scenario -eq 'ParentExited') {
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
    $expectedStates = if ($expectsFailure) { @('Starting','Failed') } elseif ($Scenario -eq 'Stop') { @('Starting','Running','Stopping','Stopped') } else { @('Starting','Running','Completed') }
    foreach ($expectedState in $expectedStates) {
        if (@($states | Where-Object { $_ -match "\|state=$expectedState\|" }).Count -eq 0) {
            throw "The lifecycle controller did not report expected state: $expectedState"
        }
    }
    if (@(Get-Process -Id $hostProcessId -ErrorAction SilentlyContinue).Count -gt 0) { throw 'The Agent Host remained alive after its Stop result.' }
    $expectedTerminalState = if ($expectsFailure) { 'Failed' } elseif ($Scenario -eq 'Stop') { 'Stopped' } else { 'Completed' }
    $expectedExitCode = if ($expectsFailure) { 1 } else { 0 }
    if (@($hostExitEvents | Where-Object { $_ -match "\|pid=$hostProcessId\|exitCode=$expectedExitCode\|state=$expectedTerminalState" }).Count -ne 1) {
        throw 'The owned Host did not exit with its expected successful terminal state.'
    }
    $hostReceiptPath = Join-Path $harnessTemp 'AgentHostLifecycleHostReceipt.json'
    if (-not (Test-Path -LiteralPath $hostReceiptPath -PathType Leaf)) { throw 'Game-owned Host did not leave its sanitized lifecycle receipt.' }
    $hostReceipt = Get-Content -LiteralPath $hostReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json

    $endingState = Invoke-LifecycleCli 'state'
    if ($endingState.status -ne 'completed' -or [string]$endingState.state.context.gameState -cne [string]$baseline.state.context.gameState) {
        throw 'Native Campaign could not be observed after Host exit.'
    }
    if (($Scenario -eq 'Stop' -or $expectsFailure) -and
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
    if ($expectsFailure) {
        $expectedFailureCode = if ($Scenario -eq 'MissingModel') { 'provider-model-unavailable' } else { 'provider-unavailable' }
        if ($hostReceipt.status -ne 'failed' -or $hostReceipt.failureCode -ne $expectedFailureCode -or
            $hostReceipt.decisionCount -ne 0 -or $hostReceipt.actionsExecuted -ne 0 -or $responseFiles.Count -ne 0) {
            throw 'Provider failure did not terminate before decisions and Native commands with its expected failure classification.'
        }
    }
    elseif ($Scenario -eq 'Stop') {
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
catch { $failure = $_.Exception.Message }
finally {
    if (Test-Path -LiteralPath $sessionPath -PathType Leaf) {
        try {
            if ($Scenario -eq 'ParentExited' -and -not (Get-Process -Id $gameProcessId -ErrorAction SilentlyContinue)) {
                $remainingHost = Get-Process -Id $hostProcessId -ErrorAction SilentlyContinue
                if ($remainingHost -and [IO.Path]::GetFullPath($remainingHost.Path) -ceq [IO.Path]::GetFullPath($hostPath)) {
                    Stop-Process -Id $hostProcessId -Force
                }
                $cleanup = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli recoverTestConfig -AsJson 2>&1 | Out-String
                if ($LASTEXITCODE -ne 0) { throw 'Parent-exit fixture session/config cleanup failed.' }
                $stopReceipt = $cleanup | ConvertFrom-Json
                if (-not $stopReceipt.restored) { throw 'Parent-exit fixture did not restore its original engine configuration.' }
                $staleSession = Get-Content -LiteralPath $sessionPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ([int]$staleSession.processId -ne $gameProcessId) { throw 'Refusing to remove a different Campaign session during parent-exit cleanup.' }
                Remove-Item -LiteralPath $sessionPath -Force
            }
            else { $stopReceipt = Invoke-LifecycleCli 'stop' }
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
$passed = ($null -eq $failure -and $gameProcessId -gt 0 -and $hostProcessId -gt 0 -and $processesStopped -and $sessionClean -and $fixtureUnchanged -and ($Scenario -ne 'Stop' -or $nativeWriteActions.Count -eq 0) -and ($Scenario -ne 'ParentExited' -or $parentExitVerified))
$result = [pscustomobject][ordered]@{
    Passed = [bool]$passed
    Scenario = $Scenario
    ProviderKind = if ($expectsFailure) { 'Local provider health rejection; zero generation and Native commands' } elseif ($usesIdleProvider) { 'Harness-only idle provider; no model service or generation' } else { 'Real local 4b model through the game-launched Host' }
    GameProcessId = $gameProcessId
    AgentHostProcessId = $hostProcessId
    ModelId = if ($hostReceipt) { $hostReceipt.providerModelId } else { $providerModelId }
    HostReceipt = $hostReceipt
    NativeArrivalCompleted = [bool]$completionVerified
    HostIndependentlyExitedAfterParentTermination = [bool]$parentExitVerified
    ParentExitHostExitCode = $parentExitHostExitCode
    ParentExitSeconds = $parentExitSeconds
    EngineConfigRestoredAfterParentExit = if ($Scenario -eq 'ParentExited') { [bool]($stopReceipt -and $stopReceipt.restored) } else { $null }
    LastMoveTargetId = $lastMoveTargetId
    AutoStopAfterMilliseconds = $AutoStopAfterMilliseconds
    LifecycleStates = @($states | ForEach-Object { [string]$_ })
    NativeHandshakeVerified = [bool]$nativeHandshakeVerified
    NativeSessionGuardVerified = [bool]$nativeSessionGuardVerified
    StartupRejectionCases = @($startupRejectionCases)
    DuplicateStartVerified = [bool]$duplicateStartVerified
    HostReadyEvents = @($hostReadyEvents | ForEach-Object { [string]$_ })
    HostExitEvents = @($hostExitEvents | ForEach-Object { [string]$_ })
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
