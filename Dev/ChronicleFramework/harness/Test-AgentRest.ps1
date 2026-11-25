#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
. (Join-Path $PSScriptRoot 'Test-AgentSupport.ps1')
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$runPrefix = 'p4w-' + (Get-Date -Format 'yyyyMMddHHmmssfff')
if (-not (Test-Path $savePath)) { throw "Rest fixture not found: $savePath" }
$fixtureHashBefore = (Get-FileHash $savePath -Algorithm SHA256).Hash

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @()) {
    $output = & $HarnessPowerShell -NoProfile -File $cli $Action @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

try {
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName, '-TimeoutSeconds', $TimeoutSeconds)
    $before = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-before", '-TimeoutSeconds', $TimeoutSeconds)
    $target = @($before.state.nearbySettlements | Where-Object { -not $_.hostile -and $_.distance -gt 1.0 } | Sort-Object distance | Select-Object -First 1)
    if ($target.Count -ne 1) { throw 'No safe visible town exists in the disposable rest fixture.' }
    $move = Invoke-AgentCli 'move' @('-SettlementId', [string]$target[0].id, '-CommandId', "$runPrefix-move", '-TimeoutSeconds', $TimeoutSeconds)
    if ($move.status -ne 'completed' -or $move.state.location.targetSettlementId -ne $target[0].id) { throw 'Native move order did not target the rest settlement.' }
    $arrival = Wait-ForAgentSettlementArrival -CliPath $cli -SettlementId ([string]$target[0].id) -CommandPrefix "$runPrefix-travel" -TimeoutSeconds $TimeoutSeconds
    if ($arrival.state.location.currentSettlementId -ne $target[0].id) { throw 'Main party did not reach the rest settlement.' }

    $townMenu = Invoke-AgentCli 'menu' @('-CommandId', "$runPrefix-town-menu", '-TimeoutSeconds', $TimeoutSeconds)
    $waitOption = @($townMenu.state.availableMenuOptions | Where-Object { $_.id -eq 'town_wait' -and $_.available -and $_.enabled })
    if ($waitOption.Count -ne 1) { throw 'Native town menu did not expose an enabled wait option.' }
    $enterWait = Invoke-AgentCli 'menuSelect' @('-MenuId', 'town', '-OptionId', 'town_wait', '-CommandId', "$runPrefix-enter-wait", '-TimeoutSeconds', $TimeoutSeconds)
    $waitState = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-wait-state", '-TimeoutSeconds', $TimeoutSeconds)
    if ($waitState.state.context.menuId -ne 'town_wait_menus' -or -not $waitState.state.context.isWaiting) { throw 'Native settlement wait menu did not enter waiting state.' }
    $nativeWaitStartedClock = $waitState.state.context.timeControlMode -in @('UnstoppableFastForward', 'UnstoppableFastForwardForPartyWaitTime')

    $restStartDay = [double]$waitState.campaignDay
    $rest = Invoke-AgentCli 'rest' @('-Days', '0.05', '-CommandId', "$runPrefix-rest", '-TimeoutSeconds', $TimeoutSeconds)
    $restPreservedNativeClock = $rest.state.context.timeControlMode -eq $waitState.state.context.timeControlMode
    $afterRest = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-after-rest", '-TimeoutSeconds', $TimeoutSeconds)
    $waitMenu = Invoke-AgentCli 'menu' @('-CommandId', "$runPrefix-wait-menu", '-TimeoutSeconds', $TimeoutSeconds)
    $leaveOption = @($waitMenu.state.availableMenuOptions | Where-Object { $_.id -eq 'wait_leave' -and $_.available -and $_.enabled })
    if ($leaveOption.Count -ne 1) { throw 'Native wait menu did not expose an enabled stop-waiting option.' }
    $leave = Invoke-AgentCli 'menuSelect' @('-MenuId', 'town_wait_menus', '-OptionId', 'wait_leave', '-CommandId', "$runPrefix-leave-wait", '-TimeoutSeconds', $TimeoutSeconds)
    $afterLeave = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-after-leave", '-TimeoutSeconds', $TimeoutSeconds)
    $invalidRest = Invoke-AgentCli 'rest' @('-Days', '0.05', '-CommandId', "$runPrefix-invalid-rest", '-TimeoutSeconds', 15)
    $afterInvalid = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-after-invalid", '-TimeoutSeconds', $TimeoutSeconds)

    $reenterWait = Invoke-AgentCli 'menuSelect' @('-MenuId', 'town', '-OptionId', 'town_wait', '-CommandId', "$runPrefix-reenter-wait", '-TimeoutSeconds', $TimeoutSeconds)
    $interruptStart = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-interrupt-start", '-TimeoutSeconds', $TimeoutSeconds)
    $interruptId = "$runPrefix-interrupt-rest"
    $interruptAccepted = Invoke-AgentCli 'rest' @('-Days', '365', '-CommandId', $interruptId, '-ReturnWhenAccepted', '-TimeoutSeconds', '15')
    $acceptedPath = Join-Path (Join-Path (Split-Path -Parent $sessionPath) 'responses') "$interruptId.accepted.json"
    $interruptDeadline = [DateTime]::UtcNow.AddSeconds(30)
    while (-not (Test-Path $acceptedPath) -and [DateTime]::UtcNow -lt $interruptDeadline) { Start-Sleep -Milliseconds 100 }
    if (-not (Test-Path $acceptedPath) -or $interruptAccepted.status -ne 'accepted') { throw 'Long rest command did not reach accepted state before interruption test timeout.' }
    $interruptLeave = Invoke-AgentCli 'menuSelect' @('-MenuId', 'town_wait_menus', '-OptionId', 'wait_leave', '-CommandId', "$runPrefix-interrupt-leave", '-TimeoutSeconds', $TimeoutSeconds)
    $interruptResponsePath = Join-Path (Join-Path (Split-Path -Parent $sessionPath) 'responses') "$interruptId.failed.json"
    $interruptResponse = if (Test-Path $interruptResponsePath) { Get-Content $interruptResponsePath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
    if ($interruptLeave.status -eq 'completed' -and -not $interruptResponse) { $interruptResponse = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-interrupt-state", '-TimeoutSeconds', $TimeoutSeconds) }
    $afterInterrupt = $interruptResponse
    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$runPrefix-stop", '-TimeoutSeconds', $TimeoutSeconds)
    $fixtureHashAfter = (Get-FileHash $savePath -Algorithm SHA256).Hash

    $restElapsed = [double]$rest.campaignDay - $restStartDay
    $restVerified = ($rest.status -eq 'completed' -and $restElapsed -ge 0.05 -and [double]$afterRest.campaignDay -ge [double]$rest.campaignDay -and $afterRest.state.context.isWaiting)
    $invalidNoTimeChange = ($invalidRest.status -eq 'rejected' -and [math]::Abs([double]$afterInvalid.campaignDay - [double]$afterLeave.campaignDay) -lt 0.002)
    $interruptVerified = ($reenterWait.status -eq 'completed' -and $interruptLeave.status -eq 'completed' -and $interruptResponse.status -eq 'failed' -and $interruptResponse.timeControlMode -eq 'Stop' -and $afterInterrupt.state.context.menuId -eq 'town' -and ([double]$afterInterrupt.campaignDay - [double]$interruptStart.campaignDay) -lt 365)
    $leftWaitMenu = ($leave.status -eq 'completed' -and $afterLeave.state.context.menuId -eq 'town')
    $result = [ordered]@{
        ProcessId = $start.session.processId
        WindowLayout = $start.session.windowLayout
        Settlement = $target[0]
        EnteredWaitMenu = $enterWait.status -eq 'completed' -and $waitState.state.context.menuId -eq 'town_wait_menus'
        NativeWaitStartedClock = $nativeWaitStartedClock
        RestReceipt = $rest
        RestPreservedNativeClock = $restPreservedNativeClock
        RestDays = $restElapsed
        AfterRest = [ordered]@{ CampaignDay = $afterRest.campaignDay; Waiting = $afterRest.state.context.isWaiting; MenuId = $afterRest.state.context.menuId }
        LeftWaitMenu = $leftWaitMenu
        WaitingFlagAfterLeave = $afterLeave.state.context.isWaiting
        InvalidRest = [ordered]@{ Status = $invalidRest.status; Error = $invalidRest.error }
        InvalidRestNoTimeChange = $invalidNoTimeChange
        InterruptedRest = [ordered]@{ Status = $interruptResponse.status; TimeControlMode = $interruptResponse.timeControlMode; MenuIdAfterInterrupt = $afterInterrupt.state.context.menuId; DaysElapsed = [double]$afterInterrupt.campaignDay - [double]$interruptStart.campaignDay }
        InterruptVerified = $interruptVerified
        FixtureUnchanged = $fixtureHashBefore -eq $fixtureHashAfter
        ProcessStopped = $stop.processStopped
    }
    $result.Passed = ($result.EnteredWaitMenu -and $nativeWaitStartedClock -and $restVerified -and $restPreservedNativeClock -and $result.LeftWaitMenu -and $invalidNoTimeChange -and $interruptVerified -and $result.FixtureUnchanged -and $result.ProcessStopped)
    $result | ConvertTo-Json -Depth 8
    if (-not $result.Passed) { exit 1 }
}
finally {
    if (Test-Path $sessionPath) {
        try { Invoke-AgentCli 'stop' @('-CommandId', "$runPrefix-cleanup", '-TimeoutSeconds', '15') | Out-Null } catch { }
    }
}
