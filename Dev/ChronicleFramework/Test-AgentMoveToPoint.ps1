[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180,
    [int]$MaximumTravelSteps = 20
)

$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$agentRoot = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent'
$sessionPath = Join-Path $agentRoot 'session.json'
$runPrefix = 'point-' + (Get-Date -Format 'yyyyMMddHHmmssfff')
if (-not (Test-Path -LiteralPath $savePath)) { throw "Point movement fixture not found: $savePath" }
$fixtureHashBefore = (Get-FileHash $savePath -Algorithm SHA256).Hash

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @()) {
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $cli $Action @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

function Get-LocationDistance($State, [double]$X, [double]$Y) {
    $dx = [double]$State.location.x - $X
    $dy = [double]$State.location.y - $Y
    return [Math]::Sqrt(($dx * $dx) + ($dy * $dy))
}

try {
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName, '-TimeoutSeconds', $TimeoutSeconds)
    $before = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-before", '-TimeoutSeconds', $TimeoutSeconds)
    if ($before.state.context.gameState -ne 'MapState' -or $before.state.context.encounterActive -or $before.state.location.currentSettlementId) {
        throw 'Point movement requires the disposable fixture to load directly into the unobstructed Campaign Map.'
    }
    if ($before.state.party.isAtSea) { throw 'The point-movement fixture must start on land; naval navigation is a separate W2 boundary.' }
    $surface = 'land'
    $startX = [double]$before.state.location.x
    $startY = [double]$before.state.location.y
    $offsets = @(
        @{ X = 1.5; Y = 0.0 }, @{ X = -1.5; Y = 0.0 }, @{ X = 0.0; Y = 1.5 }, @{ X = 0.0; Y = -1.5 },
        @{ X = 3.0; Y = 0.0 }, @{ X = -3.0; Y = 0.0 }, @{ X = 0.0; Y = 3.0 }, @{ X = 0.0; Y = -3.0 },
        @{ X = 2.0; Y = 2.0 }, @{ X = -2.0; Y = 2.0 }, @{ X = 2.0; Y = -2.0 }, @{ X = -2.0; Y = -2.0 }
    )
    $invalidCandidates = @()
    $move = $null
    $selected = $null
    $baseline = $before.state
    foreach ($offset in $offsets) {
        $x = $startX + [double]$offset.X
        $y = $startY + [double]$offset.Y
        $candidate = Invoke-AgentCli 'moveToPoint' @('-X', $x, '-Y', $y, '-Surface', $surface, '-CommandId', "$runPrefix-candidate-$($invalidCandidates.Count + 1)", '-TimeoutSeconds', $TimeoutSeconds)
        if ($candidate.status -eq 'completed') {
            $move = $candidate
            $selected = [ordered]@{ X = $x; Y = $y; Surface = $surface }
            break
        }
        if ($candidate.status -ne 'rejected') { throw "Map point candidate returned unexpected status '$($candidate.status)': $($candidate.error)" }
        $candidateState = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-candidate-state-$($invalidCandidates.Count + 1)", '-TimeoutSeconds', $TimeoutSeconds)
        $noMutation = (
            $candidateState.state.location.x -eq $baseline.location.x -and
            $candidateState.state.location.y -eq $baseline.location.y -and
            $candidateState.state.location.targetSettlementId -eq $baseline.location.targetSettlementId -and
            $candidateState.state.location.targetPartyId -eq $baseline.location.targetPartyId -and
            $candidateState.state.party.defaultBehavior -eq $baseline.party.defaultBehavior -and
            $candidateState.state.context.timeControlMode -eq $baseline.context.timeControlMode
        )
        $invalidCandidates += [pscustomobject]@{ X = $x; Y = $y; Surface = $surface; Status = $candidate.status; Error = $candidate.error; NoMutation = $noMutation }
        if (-not $noMutation) { throw "Rejected map point candidate ($x,$y) changed Campaign movement/time state." }
        $baseline = $candidateState.state
    }
    if (-not $move) { throw 'Could not discover a nearby valid Campaign navigation face without altering the disposable campaign.' }
    $nativeTarget = $move.data.nativeTarget
    if ($move.state.party.defaultBehavior -ne 'GoToPoint' -or $move.state.location.targetPosition.x -ne $nativeTarget.x -or $move.state.location.targetPosition.y -ne $nativeTarget.y) {
        throw 'Native point movement receipt and structured target-position observation did not agree.'
    }
    $nativeMapClickTimePolicyApplied = $move.state.context.timeControlMode -in @('StoppablePlay', 'StoppableFastForward')
    $progress = @()
    $current = $move
    $arrived = $false
    $elapsedHarnessDays = 0.0
    for ($step = 1; $step -le $MaximumTravelSteps; $step++) {
        $distance = Get-LocationDistance -State $current.state -X ([double]$nativeTarget.x) -Y ([double]$nativeTarget.y)
        $progress += [pscustomobject]@{ Step = $step - 1; CampaignDay = $current.campaignDay; X = $current.state.location.x; Y = $current.state.location.y; DistanceToTarget = $distance; IsMoving = $current.state.party.isMoving; DefaultBehavior = $current.state.party.defaultBehavior }
        if ($distance -le 0.35) { $arrived = $true; break }
        if ($current.state.context.encounterActive) { break }
        $current = Invoke-AgentCli 'advance' @('-Days', '0.01', '-CommandId', "$runPrefix-travel-$step", '-TimeoutSeconds', $TimeoutSeconds)
        if ($current.status -ne 'completed') { throw "Harness point travel time step did not complete: $($current.error)" }
        $elapsedHarnessDays += 0.01
    }
    $invalid = Invoke-AgentCli 'moveToPoint' @('-X', '1000000', '-Y', '1000000', '-Surface', $surface, '-CommandId', "$runPrefix-invalid-range", '-TimeoutSeconds', '15')
    $afterInvalid = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-after-invalid", '-TimeoutSeconds', $TimeoutSeconds)
    $invalidNoMutation = (
        $invalid.status -eq 'rejected' -and
        $afterInvalid.state.location.x -eq $current.state.location.x -and
        $afterInvalid.state.location.y -eq $current.state.location.y -and
        $afterInvalid.state.location.targetPosition.x -eq $current.state.location.targetPosition.x -and
        $afterInvalid.state.location.targetPosition.y -eq $current.state.location.targetPosition.y -and
        $afterInvalid.state.party.defaultBehavior -eq $current.state.party.defaultBehavior -and
        $afterInvalid.state.context.timeControlMode -eq $current.state.context.timeControlMode
    )
    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$runPrefix-stop", '-TimeoutSeconds', $TimeoutSeconds)
    $fixtureHashAfter = (Get-FileHash $savePath -Algorithm SHA256).Hash
    $result = [ordered]@{
        ProcessId = $start.session.processId
        WindowLayout = $start.session.windowLayout
        Surface = $surface
        InitialPosition = [ordered]@{ X = $startX; Y = $startY }
        InvalidFaceCandidates = $invalidCandidates
        ChosenCoordinate = $selected
        MoveReceipt = $move
        NativeMapClickTimePolicyApplied = $nativeMapClickTimePolicyApplied
        NativeTarget = $nativeTarget
        StructuredTargetPosition = $move.state.location.targetPosition
        TravelProgress = $progress
        ArrivedWithinTolerance = $arrived
        FinalPosition = [ordered]@{ X = $current.state.location.x; Y = $current.state.location.y }
        HarnessAdvanceDays = $elapsedHarnessDays
        InvalidOutOfRangeDestination = [ordered]@{ Status = $invalid.status; Error = $invalid.error; NoMutation = $invalidNoMutation }
        FixtureUnchanged = $fixtureHashBefore -eq $fixtureHashAfter
        ProcessStopped = $stop.processStopped
    }
    $result.Passed = (
        $move.action -eq 'moveToPoint' -and
        $move.status -eq 'completed' -and
        $nativeMapClickTimePolicyApplied -and
        $move.state.party.defaultBehavior -eq 'GoToPoint' -and
        $move.state.location.targetPosition.x -eq $nativeTarget.x -and
        $move.state.location.targetPosition.y -eq $nativeTarget.y -and
        @($invalidCandidates | Where-Object { -not $_.NoMutation }).Count -eq 0 -and
        $arrived -and
        $invalidNoMutation -and
        $result.FixtureUnchanged -and
        $result.ProcessStopped
    )
    $resultJson = $result | ConvertTo-Json -Depth 12
    if ($env:CHRONICLE_HARNESS_TEMP -and (Test-Path -LiteralPath $env:CHRONICLE_HARNESS_TEMP -PathType Container)) {
        Set-Content -LiteralPath (Join-Path $env:CHRONICLE_HARNESS_TEMP 'AgentMoveToPointResult.json') -Value $resultJson -Encoding UTF8
    }
    $resultJson
    if (-not $result.Passed) { exit 1 }
}
finally {
    if (Test-Path $sessionPath) {
        try { Invoke-AgentCli 'stop' @('-CommandId', "$runPrefix-cleanup", '-TimeoutSeconds', '15') | Out-Null } catch { }
    }
}
