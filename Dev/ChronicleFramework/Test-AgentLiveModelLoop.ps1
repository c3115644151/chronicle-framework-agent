[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$loop = Join-Path $PSScriptRoot 'Agent-DecisionLoop.ps1'
$provider = Join-Path $PSScriptRoot 'Agent-OpenAICompatibleProvider.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'

foreach ($setting in @('CHRONICLE_LLM_BASE_URL','CHRONICLE_LLM_MODEL')) {
    if ([string]::IsNullOrWhiteSpace([string][Environment]::GetEnvironmentVariable($setting))) {
        throw "Live-model verification requires local $setting configuration; the value is never printed by this test."
    }
}
if (-not (Test-Path -LiteralPath $savePath -PathType Leaf)) { throw "Disposable AgentLoop fixture not found: $savePath" }
if (Test-Path -LiteralPath $sessionPath -PathType Leaf) { throw 'Refusing to replace an existing Chronicle Agent session; stop or recover it before the live-model test.' }

$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
$sessionStarted = $false
$loopTrace = $null
$failure = $null
$start = $null
$stop = $null
$liveModelTrace = $null

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @()) {
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli $Action @Arguments -TimeoutSeconds $TimeoutSeconds -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

try {
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $sessionStarted = $true
    $baseline = Invoke-AgentCli 'state'
    if ($baseline.status -ne 'completed' -or $baseline.state.context.gameState -ne 'MapState' -or $baseline.state.location.currentSettlementId) {
        throw 'Live-model fixture must load into an unobstructed Campaign Map state.'
    }

    $goal = 'Use only the current Native observation and action receipts. First query visible Campaign settlement targets. Then choose one target in that query whose hostile=false and underSiege=false, issue exactly one Native move order to its observed id, and stop. Do not use any other action or change Campaign time mode explicitly.'
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -Goal $goal -AllowedActionNames 'mapSettlementTargets,move' -MaxDecisions 3 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('live-model-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Real-model decision loop failed: $output" }
    $loopTrace = $output | ConvertFrom-Json
    if ($loopTrace.status -eq 'failed') { throw "Real-model decision loop failed: $($loopTrace.error)" }

    $steps = @($loopTrace.trace)
    $targetQuery = @($steps | Where-Object { $_.decision.action -eq 'mapSettlementTargets' -and $_.actionReceipt.status -eq 'completed' } | Select-Object -First 1)
    $moveStep = @($steps | Where-Object { $_.decision.action -eq 'move' -and $_.actionReceipt.status -eq 'completed' } | Select-Object -First 1)
    if ($targetQuery.Count -ne 1 -or $moveStep.Count -ne 1 -or [int]$targetQuery[0].iteration -ge [int]$moveStep[0].iteration) { throw 'Live model did not query visible targets before completing one native move action within its three-decision budget.' }
    $observedTargets = @($targetQuery[0].actionReceipt.data.mapSettlementTargets)
    $chosenId = [string]$moveStep[0].decision.arguments.SettlementId
    $chosenTarget = @($observedTargets | Where-Object { [string]$_.id -ceq $chosenId } | Select-Object -First 1)
    $chosenObservedSafeTarget = ($chosenTarget.Count -eq 1 -and -not [bool]$chosenTarget[0].hostile -and -not [bool]$chosenTarget[0].underSiege)
    $nativeMovementObserved = ([string]$moveStep[0].observationAfter.state.location.targetSettlementId -ceq $chosenId)
    if (-not $chosenObservedSafeTarget -or -not $nativeMovementObserved) { throw 'Native move did not match a safe settlement id returned by the immediately preceding visible-target query.' }

    $liveModelTrace = [ordered]@{
        ProviderKind = 'configured OpenAI-compatible live model'
        Goal = $goal
        ChosenSettlementId = $chosenId
        ChosenSettlementName = [string]$chosenTarget[0].name
        ObservedTargetCount = $observedTargets.Count
        QueryThenNativeMoveVerified = $true
        ProviderStoppedAfterGoalAction = ([bool]$loopTrace.termination.completedByProvider -and [bool]$steps[-1].decision.done -and [int]$loopTrace.actionsExecuted -eq 2)
        Decisions = $steps.Count
        NativeActionReceipts = @($steps | Where-Object { $_.actionExecuted } | ForEach-Object { [ordered]@{ action = $_.actionReceipt.action; status = $_.actionReceipt.status; campaignDay = $_.actionReceipt.campaignDay } })
        Trace = $loopTrace.trace
        FixtureHashBefore = $fixtureHashBefore
    }
    if (-not $liveModelTrace.ProviderStoppedAfterGoalAction) { throw 'Live model did not stop after the single requested Native move order.' }
}
catch {
    $failure = $_.Exception.Message
}
finally {
    if ($sessionStarted -or (Test-Path -LiteralPath $sessionPath -PathType Leaf)) {
        try { $stop = Invoke-AgentCli 'stop' } catch { if (-not $failure) { $failure = "Agent session cleanup failed: $($_.Exception.Message)" } }
    }
}

$fixtureHashAfter = if (Test-Path -LiteralPath $savePath -PathType Leaf) { (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash } else { $null }
$fixtureUnchanged = ($fixtureHashBefore -ceq $fixtureHashAfter)
$processStopped = ([bool]$stop.processStopped -and -not (Test-Path -LiteralPath $sessionPath -PathType Leaf) -and -not (Get-Process -Name Bannerlord* -ErrorAction SilentlyContinue))
$passed = (-not $failure -and $null -ne $liveModelTrace -and $fixtureUnchanged -and $processStopped)
$result = [ordered]@{
    ProviderKind = 'configured OpenAI-compatible live model; not a stub'
    Passed = $passed
    Failure = $failure
    FixtureUnchanged = $fixtureUnchanged
    ProcessStopped = $processStopped
    ProcessId = if ($start -and $start.session) { $start.session.processId } else { $null }
    Trace = $liveModelTrace
}
$json = $result | ConvertTo-Json -Depth 24
if ($env:CHRONICLE_HARNESS_TEMP -and (Test-Path -LiteralPath $env:CHRONICLE_HARNESS_TEMP -PathType Container)) {
    Set-Content -LiteralPath (Join-Path $env:CHRONICLE_HARNESS_TEMP 'LiveModelLoopResult.json') -Value $json -Encoding UTF8
}
$json
if (-not $passed) { exit 1 }
