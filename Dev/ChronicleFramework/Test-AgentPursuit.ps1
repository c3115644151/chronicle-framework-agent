[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
. (Join-Path $PSScriptRoot 'Test-AgentSupport.ps1')
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$agentRoot = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent'
$sessionPath = Join-Path $agentRoot 'session.json'
$runPrefix = 'p4p-' + (Get-Date -Format 'yyyyMMddHHmmssfff')
if (-not (Test-Path $savePath)) { throw "Pursuit fixture not found: $savePath" }
$fixtureHashBefore = (Get-FileHash $savePath -Algorithm SHA256).Hash

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @()) {
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $cli $Action @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

try {
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName, '-TimeoutSeconds', $TimeoutSeconds)
    $initial = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-initial", '-TimeoutSeconds', $TimeoutSeconds)
    $settlement = @($initial.state.nearbySettlements | Where-Object { -not $_.hostile -and $_.distance -gt 1.0 } | Sort-Object distance | Select-Object -First 1)
    if ($settlement.Count -ne 1) { throw 'No safe settlement target exists to establish a clean campaign-map pursuit fixture.' }
    $arrival = Invoke-AgentCli 'move' @('-SettlementId', [string]$settlement[0].id, '-CommandId', "$runPrefix-arrival", '-TimeoutSeconds', $TimeoutSeconds)
    if ($arrival.status -ne 'completed' -or $arrival.state.location.targetSettlementId -ne $settlement[0].id) { throw 'Native move order did not target the settlement used to exit into the campaign map.' }
    $arrivalState = Wait-ForAgentSettlementArrival -CliPath $cli -SettlementId ([string]$settlement[0].id) -CommandPrefix "$runPrefix-travel" -TimeoutSeconds $TimeoutSeconds
    if ($arrivalState.state.location.currentSettlementId -ne $settlement[0].id) { throw 'Could not reach the settlement used to exit into the campaign map.' }
    $town = Invoke-AgentCli 'menu' @('-CommandId', "$runPrefix-town", '-TimeoutSeconds', $TimeoutSeconds)
    $leave = @($town.state.availableMenuOptions | Where-Object { $_.isLeave -and $_.available -and $_.enabled } | Select-Object -First 1)
    if ($leave.Count -ne 1) { throw 'The settlement did not expose an enabled native leave option.' }
    $leaveResult = Invoke-AgentCli 'menuSelect' @('-MenuId', [string]$town.state.context.menuId, '-OptionId', [string]$leave[0].id, '-CommandId', "$runPrefix-leave", '-TimeoutSeconds', $TimeoutSeconds)
    if ($leaveResult.status -ne 'completed') { throw 'Could not exit the settlement to test campaign-map pursuit.' }

    $mapState = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-map-state", '-TimeoutSeconds', $TimeoutSeconds)
    $targets = @($mapState.state.nearbyParties | Where-Object { $_.isMoving -and $null -eq $_.currentSettlementId -and $_.distance -gt 1.0 } | Sort-Object distance)
    if ($targets.Count -eq 0) { throw 'No visible moving party outside a settlement is available in the disposable fixture; refusing to invent or teleport a target.' }
    $target = $targets[0]

    $invalid = Invoke-AgentCli 'pursue' @('-PartyId', 'chronicle_missing_party', '-CommandId', "$runPrefix-invalid", '-TimeoutSeconds', '15')
    $afterInvalid = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-after-invalid", '-TimeoutSeconds', $TimeoutSeconds)
    $invalidNoMutation = ($invalid.status -eq 'rejected' -and $afterInvalid.state.location.targetPartyId -eq $mapState.state.location.targetPartyId -and $afterInvalid.state.party.moveMode -eq $mapState.state.party.moveMode)

    $pursuit = Invoke-AgentCli 'pursue' @('-PartyId', [string]$target.id, '-CommandId', "$runPrefix-pursue", '-TimeoutSeconds', $TimeoutSeconds)
    $pursuitState = $pursuit.state
    $nativeOrderIssued = ($pursuit.status -eq 'completed' -and $pursuitState.location.targetPartyId -eq $target.id -and $pursuitState.party.defaultBehavior -eq 'EngageParty')
    $nativeMapClickTimePolicyApplied = $pursuitState.context.timeControlMode -in @('StoppablePlay', 'StoppableFastForward')
    $pursuitStartDay = [double]$pursuit.campaignDay
    $outcomeState = $pursuitState
    $pursuitOutcome = $null
    $deadline = [DateTime]::UtcNow.AddSeconds([Math]::Min(90, $TimeoutSeconds))
    while ([DateTime]::UtcNow -lt $deadline) {
        $outcomeState = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-observe-$([guid]::NewGuid().ToString('N'))", '-TimeoutSeconds', $TimeoutSeconds)
        if ($outcomeState.state.context.encounterActive -and $outcomeState.state.context.encounteredPartyId -eq $target.id) { $pursuitOutcome = 'encounter'; break }
        if ($outcomeState.state.party.defaultBehavior -eq 'Hold' -and $null -eq $outcomeState.state.location.targetPartyId) { $pursuitOutcome = 'nativeHoldAfterTargetLoss'; break }
        if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'Game process exited while the native pursuit order was active.' }
        Start-Sleep -Milliseconds 250
    }
    $pursuitTimedOut = -not $pursuitOutcome
    if ($pursuitTimedOut) {
        Invoke-AgentCli 'hold' @('-CommandId', "$runPrefix-timeout-hold", '-TimeoutSeconds', $TimeoutSeconds) | Out-Null
        Invoke-AgentCli 'pause' @('-CommandId', "$runPrefix-timeout-pause", '-TimeoutSeconds', $TimeoutSeconds) | Out-Null
    }
    $pursuitElapsedDays = [double]$outcomeState.campaignDay - $pursuitStartDay

    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$runPrefix-stop", '-TimeoutSeconds', $TimeoutSeconds)
    $fixtureHashAfter = (Get-FileHash $savePath -Algorithm SHA256).Hash
    $result = [ordered]@{
        ProcessId = $start.session.processId
        WindowLayout = $start.session.windowLayout
        Target = $target
        InvalidTarget = [ordered]@{ Status = $invalid.status; Error = $invalid.error; NoMutation = $invalidNoMutation }
        PursuitOrder = [ordered]@{ Status = $pursuit.status; TargetPartyId = $pursuitState.location.targetPartyId; MoveMode = $pursuitState.party.moveMode; DefaultBehavior = $pursuitState.party.defaultBehavior; TimeControlMode = $pursuitState.context.timeControlMode; NativeMapClickTimePolicy = $nativeMapClickTimePolicyApplied }
        NaturalPursuitOutcome = [ordered]@{ Outcome = $pursuitOutcome; DaysElapsed = $pursuitElapsedDays; TargetPartyId = $outcomeState.state.location.targetPartyId; MoveMode = $outcomeState.state.party.moveMode; DefaultBehavior = $outcomeState.state.party.defaultBehavior; TimeControlMode = $outcomeState.state.context.timeControlMode; EncounterActive = $outcomeState.state.context.encounterActive; EncounteredPartyId = $outcomeState.state.context.encounteredPartyId }
        TimedOut = $pursuitTimedOut
        FixtureUnchanged = $fixtureHashBefore -eq $fixtureHashAfter
        ProcessStopped = $stop.processStopped
    }
    $result.Passed = ($invalidNoMutation -and $nativeOrderIssued -and $nativeMapClickTimePolicyApplied -and $pursuitOutcome -in @('encounter', 'nativeHoldAfterTargetLoss') -and -not $pursuitTimedOut -and $result.FixtureUnchanged -and $result.ProcessStopped)
    $result | ConvertTo-Json -Depth 8
    if (-not $result.Passed) { exit 1 }
}
finally {
    if (Test-Path $sessionPath) {
        try { Invoke-AgentCli 'stop' @('-CommandId', "$runPrefix-cleanup", '-TimeoutSeconds', '15') | Out-Null } catch { }
    }
}
