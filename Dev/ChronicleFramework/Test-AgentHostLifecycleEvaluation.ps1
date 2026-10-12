[CmdletBinding()]
param(
    [ValidateRange(90,300)][int]$TimeoutSeconds = 180,
    [ValidateRange(250,10000)][int]$AutoStopAfterMilliseconds = 250,
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

$providerBaseUrl = 'http://127.0.0.1:11434/v1'
$providerModelId = 'harness-lifecycle-no-model'

$profileDirectory = Join-Path $harnessTemp 'MCM\Global\ChronicleFramework'
New-Item -ItemType Directory -Path $profileDirectory -Force | Out-Null
$profilePath = Join-Path $profileDirectory 'ChronicleAgentSettings.json'
[ordered]@{ OllamaBaseUrl = $providerBaseUrl; ModelId = $providerModelId } | ConvertTo-Json -Compress | Set-Content -LiteralPath $profilePath -Encoding UTF8
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
$hostResponseFilesBefore = @(Get-ChildItem -LiteralPath $responseRoot -File -Filter 'host-*.json' -ErrorAction SilentlyContinue | ForEach-Object Name)
$priorValues = @{}
foreach ($name in @('CHRONICLE_HARNESS_MODE','CHRONICLE_AGENT_PROFILE_PATH','CHRONICLE_AGENT_HOST_TEST_PATH','CHRONICLE_HARNESS_AGENT_AUTO_START','CHRONICLE_HARNESS_AGENT_AUTO_STOP_AFTER_MS','CHRONICLE_HARNESS_AGENT_GOAL','CHRONICLE_HARNESS_AGENT_NO_MODEL')) {
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
    $env:CHRONICLE_HARNESS_AGENT_AUTO_STOP_AFTER_MS = [string]$AutoStopAfterMilliseconds
    $env:CHRONICLE_HARNESS_AGENT_GOAL = 'Inspect the current Native Campaign state and wait for the explicit stop request without changing the Campaign.'
    $env:CHRONICLE_HARNESS_AGENT_NO_MODEL = '1'

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
        $states = @($gameLines | Where-Object { $_ -match '\|agent-host-state\|' })
        $hostReadyEvents = @($gameLines | Where-Object { $_ -match '\|agent-host-ready\|' })
        $startedLine = @($gameLines | Where-Object { $_ -match '\|agent-host-process-started\|' } | Select-Object -Last 1)
        $hostExitEvents = @($gameLines | Where-Object { $_ -match '\|agent-host-process-exit\|' })
        if ($startedLine.Count -gt 0 -and $startedLine[0] -match '\|agent-host-process-started\|pid=(\d+)\|') { $hostProcessId = [int]$Matches[1] }
        $sawStopped = @($states | Where-Object { $_ -match '\|state=Stopped\|' }).Count -gt 0
        $sawFailed = @($states | Where-Object { $_ -match '\|state=Failed\|' }).Count -gt 0
        if ($sawStopped -or $sawFailed) { break }
    } while ([DateTime]::UtcNow -lt $deadline)

    if ($hostProcessId -le 0) { throw 'The game did not start a child Agent Host process.' }
    $nativeHandshakeVerified = @($hostReadyEvents | Where-Object {
        $_ -match "\|agent-host-ready\|hostPid=$hostProcessId\|protocol=1\|version=.+"
    }).Count -eq 1
    if (-not $nativeHandshakeVerified) { throw 'The controller did not verify a versioned Host handshake bound to the current Native Bannerlord process.' }
    if (-not (@($states | Where-Object { $_ -match '\|state=Starting\|' }).Count -gt 0 -and
              @($states | Where-Object { $_ -match '\|state=Running\|' }).Count -gt 0 -and
              @($states | Where-Object { $_ -match '\|state=Stopping\|' }).Count -gt 0 -and
              @($states | Where-Object { $_ -match '\|state=Stopped\|' }).Count -gt 0)) {
        throw 'The lifecycle controller did not report the expected Starting -> Running -> Stopping -> Stopped states.'
    }
    if (@(Get-Process -Id $hostProcessId -ErrorAction SilentlyContinue).Count -gt 0) { throw 'The Agent Host remained alive after its Stop result.' }
    if (@($hostExitEvents | Where-Object { $_ -match "\|pid=$hostProcessId\|exitCode=0\|state=Stopped" }).Count -ne 1) {
        throw 'The owned Host did not exit cleanly through the explicit stop protocol.'
    }

    $endingState = Invoke-LifecycleCli 'state'
    if ($endingState.status -ne 'completed' -or
        [string]$endingState.state.context.gameState -cne [string]$baseline.state.context.gameState -or
        [string]$endingState.state.location.currentSettlementId -cne [string]$baseline.state.location.currentSettlementId -or
        [string]$endingState.state.location.targetSettlementId -cne [string]$baseline.state.location.targetSettlementId) {
        throw 'Stopping the Host changed the active Native location/movement state in this cancellation-window test.'
    }

    $responseFiles = @(Get-ChildItem -LiteralPath $responseRoot -File -Filter 'host-*.json' -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin $hostResponseFilesBefore })
    foreach ($responseFile in $responseFiles) {
        try {
            $response = Get-Content -LiteralPath $responseFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($response.action -in @('mapSettlementTargets','move')) { $nativeWriteActions += [string]$response.action }
        }
        catch { }
    }
    if ($nativeWriteActions.Count -gt 0) { throw 'Host issued a goal action before the post-handshake cancellation window; this lifecycle fixture expects no model decision/action.' }
}
catch { $failure = $_.Exception.Message }
finally {
    if (Test-Path -LiteralPath $sessionPath -PathType Leaf) {
        try { $stopReceipt = Invoke-LifecycleCli 'stop' } catch { if (-not $failure) { $failure = $_.Exception.Message } }
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
$passed = ($null -eq $failure -and $gameProcessId -gt 0 -and $hostProcessId -gt 0 -and $processesStopped -and $sessionClean -and $fixtureUnchanged -and $nativeWriteActions.Count -eq 0)
$result = [pscustomobject][ordered]@{
    Passed = [bool]$passed
    ProviderKind = 'Harness-only idle provider; no model service, generation, or payment required'
    GameProcessId = $gameProcessId
    AgentHostProcessId = $hostProcessId
    ModelId = $providerModelId
    AutoStopAfterMilliseconds = $AutoStopAfterMilliseconds
    LifecycleStates = @($states | ForEach-Object { [string]$_ })
    NativeHandshakeVerified = [bool]$nativeHandshakeVerified
    HostReadyEvents = @($hostReadyEvents | ForEach-Object { [string]$_ })
    HostExitEvents = @($hostExitEvents | ForEach-Object { [string]$_ })
    NativeGoalActionsBeforeStop = @($nativeWriteActions | ForEach-Object { [string]$_ })
    GameStillUsableAfterHostStop = [bool]($endingState -and $endingState.status -eq 'completed')
    NativeLocationUnchanged = [bool]($endingState -and $baseline -and $endingState.state.location.currentSettlementId -ceq $baseline.state.location.currentSettlementId)
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
