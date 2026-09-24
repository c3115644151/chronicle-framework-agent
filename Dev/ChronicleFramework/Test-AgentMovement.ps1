[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
. (Join-Path $PSScriptRoot 'Test-AgentSupport.ps1')
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$runPrefix = 'p4-' + (Get-Date -Format 'yyyyMMddHHmmssfff')
if (-not (Test-Path $savePath)) { throw "Movement fixture not found: $savePath" }
$fixtureHashBefore = (Get-FileHash $savePath -Algorithm SHA256).Hash

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @()) {
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $cli $Action @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    return $output | ConvertFrom-Json
}

try {
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName, '-TimeoutSeconds', $TimeoutSeconds)
    $before = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-before", '-TimeoutSeconds', $TimeoutSeconds)
    $target = @($before.state.nearbySettlements | Where-Object { -not $_.hostile -and $_.distance -gt 1.0 } | Sort-Object distance | Select-Object -First 1)
    if ($target.Count -ne 1) { throw 'No safe visible settlement target exists in the disposable fixture.' }
    $moved = Invoke-AgentCli 'move' @('-SettlementId', [string]$target[0].id, '-CommandId', "$runPrefix-move", '-TimeoutSeconds', $TimeoutSeconds)
    if ($moved.status -ne 'completed' -or $moved.state.location.targetSettlementId -ne $target[0].id) { throw 'Native move order did not target the selected settlement.' }
    $nativeMapClickTimePolicyApplied = $moved.state.context.timeControlMode -in @('StoppablePlay', 'StoppableFastForward')
    $arrivalState = Wait-ForAgentSettlementArrival -CliPath $cli -SettlementId ([string]$target[0].id) -CommandPrefix "$runPrefix-travel" -TimeoutSeconds $TimeoutSeconds
    $menu = Invoke-AgentCli 'menu' @('-CommandId', "$runPrefix-menu", '-TimeoutSeconds', $TimeoutSeconds)
    $leaveOption = @($menu.state.availableMenuOptions | Where-Object { $_.isLeave -and $_.available -and $_.enabled } | Select-Object -First 1)
    if ($leaveOption.Count -ne 1) { throw 'No currently enabled leave option was reported for the active settlement menu.' }
    $leave = Invoke-AgentCli 'menuSelect' @('-MenuId', [string]$menu.state.context.menuId, '-OptionId', [string]$leaveOption[0].id, '-CommandId', "$runPrefix-leave", '-TimeoutSeconds', $TimeoutSeconds)
    $afterLeave = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-after-leave", '-TimeoutSeconds', $TimeoutSeconds)
    $invalidMove = Invoke-AgentCli 'move' @('-SettlementId', 'chronicle_missing_settlement', '-CommandId', "$runPrefix-invalid-move", '-TimeoutSeconds', 15)
    $afterRejectedMove = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-after-reject", '-TimeoutSeconds', $TimeoutSeconds)
    $hold = Invoke-AgentCli 'hold' @('-CommandId', "$runPrefix-hold", '-TimeoutSeconds', $TimeoutSeconds)
    $afterHold = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-after-hold", '-TimeoutSeconds', $TimeoutSeconds)
    $nativeHoldObserved = ($hold.status -eq 'completed' -and $afterHold.state.party.defaultBehavior -eq 'Hold' -and $null -eq $afterHold.state.location.targetPartyId)
    $holdClickTimeModeObserved = $afterHold.state.context.timeControlMode -in @('StoppablePlay', 'StoppableFastForward')
    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$runPrefix-stop", '-TimeoutSeconds', $TimeoutSeconds)
    $fixtureHashAfter = (Get-FileHash $savePath -Algorithm SHA256).Hash
    $arrivalObserved = $arrivalState.state.location.currentSettlementId -eq $target[0].id -and $menu.state.location.currentSettlementId -eq $target[0].id -and $menu.state.context.menuId -eq 'town'
    $result = [ordered]@{
        ProcessId = $start.session.processId
        WindowLayout = $start.session.windowLayout
        Target = $target[0]
        Before = $before.state.location
        MoveReceipt = $moved
        TimeModeAfterMapClick = $moved.state.context.timeControlMode
        ArrivalAfterExplicitTimeSteps = $arrivalState.state.location
        SettlementMenu = $menu.state.availableMenuOptions
        SelectedLeaveOption = $leaveOption[0]
        LeaveReceipt = $leave
        AfterLeave = $afterLeave.state.location
        InvalidMove = $invalidMove
        AfterRejectedMove = $afterRejectedMove.state.location
        NativeHold = [ordered]@{ Status = $hold.status; DefaultBehavior = $afterHold.state.party.defaultBehavior; TargetPartyId = $afterHold.state.location.targetPartyId; TimeControlMode = $afterHold.state.context.timeControlMode; ClickTimeModeApplied = $holdClickTimeModeObserved }
        ArrivalObserved = $arrivalObserved
        CampaignDayElapsed = [double]$arrivalState.campaignDay - [double]$moved.campaignDay
        TimeModeAfterNativeClick = $moved.state.context.timeControlMode
        FixtureUnchanged = $fixtureHashBefore -eq $fixtureHashAfter
        ProcessStopped = $stop.processStopped
    }
    $result.Passed = (
        $moved.action -eq 'move' -and
        $moved.status -eq 'completed' -and
        $moved.state.location.targetSettlementId -eq $target[0].id -and
        $nativeMapClickTimePolicyApplied -and
        $arrivalObserved -and
        $leave.status -eq 'completed' -and
        $afterLeave.state.location.currentSettlementId -eq $null -and
        $afterLeave.state.context.menuId -ne 'town' -and
        $invalidMove.status -eq 'rejected' -and
        $invalidMove.error -match 'settlement not found' -and
        $afterRejectedMove.state.location.currentSettlementId -eq $null -and
        $nativeHoldObserved -and $holdClickTimeModeObserved -and
        $result.CampaignDayElapsed -ge 0 -and
        $result.FixtureUnchanged -and
        $result.ProcessStopped
    )
    $result | ConvertTo-Json -Depth 10
    if (-not $result.Passed) { exit 1 }
}
finally {
    if (Test-Path $sessionPath) {
        try { Invoke-AgentCli 'stop' @('-CommandId', "$runPrefix-cleanup", '-TimeoutSeconds', '15') | Out-Null } catch { }
    }
}
