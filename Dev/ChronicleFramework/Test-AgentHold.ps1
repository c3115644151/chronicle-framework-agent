#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180,
    [int]$NaturalObservationSeconds = 4
)

$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$runPrefix = 'native-hold-' + (Get-Date -Format 'yyyyMMddHHmmssfff')
if (-not (Test-Path -LiteralPath $savePath)) { throw "Hold fixture not found: $savePath" }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$ActionTimeoutSeconds = $TimeoutSeconds) {
    $output = & $HarnessPowerShell -NoProfile -File $cli $Action @Arguments -TimeoutSeconds $ActionTimeoutSeconds -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

try {
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $before = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-before")
    if ($before.state.context.gameState -ne 'MapState' -or $before.state.context.encounterActive) { throw 'Hold validation requires an unblocked Campaign Map.' }
    $targets = Invoke-AgentCli 'mapSettlementTargets' @('-CommandId', "$runPrefix-targets")
    $target = @($targets.data.mapSettlementTargets | Where-Object { -not $_.hostile -and -not $_.underSiege -and $_.type -ne 'hideout' -and $_.distance -gt 1.0 } | Sort-Object distance | Select-Object -First 1)
    if ($targets.status -ne 'completed' -or $target.Count -ne 1) { throw 'No safe, visible Native Settlement target was available to establish active movement.' }

    $move = Invoke-AgentCli 'move' @('-SettlementId', [string]$target[0].id, '-CommandId', "$runPrefix-move")
    if ($move.status -ne 'completed' -or $move.state.location.targetSettlementId -ne $target[0].id) { throw 'Native map movement did not establish the observed Settlement target.' }
    $hold = Invoke-AgentCli 'hold' @('-CommandId', "$runPrefix-hold")
    $afterHold = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-hold-settled")
    Start-Sleep -Seconds $NaturalObservationSeconds
    $afterNaturalWindow = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-hold-stable")

    $targetCleared = (
        $hold.status -eq 'completed' -and
        $afterHold.state.party.defaultBehavior -eq 'Hold' -and
        $null -eq $afterHold.state.location.targetSettlementId -and
        $null -eq $afterHold.state.location.targetPartyId -and
        $null -eq $afterHold.state.location.targetPosition
    )
    $movementStoppedAfterNaturalWindow = (
        $afterNaturalWindow.state.party.defaultBehavior -eq 'Hold' -and
        -not [bool]$afterNaturalWindow.state.party.isMoving -and
        $null -eq $afterNaturalWindow.state.location.targetSettlementId -and
        $null -eq $afterNaturalWindow.state.location.targetPartyId -and
        $null -eq $afterNaturalWindow.state.location.targetPosition
    )
    $stoppableModeWaitingAtHold = ($afterHold.state.context.timeControlMode -eq 'StoppablePlay' -and [bool]$afterHold.state.context.isWaiting)
    $waitingObserved = ([bool]$afterHold.state.context.isWaiting -and [bool]$afterNaturalWindow.state.context.isWaiting)
    $dayDelta = [double]$afterNaturalWindow.campaignDay - [double]$afterHold.campaignDay
    $noHiddenClockAction = $true

    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$runPrefix-stop") 15
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $result = [ordered]@{
        ProcessId = $start.session.processId
        TargetSource = 'mapSettlementTargets'
        Target = $target[0]
        Movement = $move
        Hold = $hold
        RawTimeModeAfterHold = $afterHold.state.context.timeControlMode
        IsMainPartyWaitingAfterHold = [bool]$afterHold.state.context.isWaiting
        CampaignDayAtHold = [double]$afterHold.campaignDay
        CampaignDayAfterNaturalObservation = [double]$afterNaturalWindow.campaignDay
        NaturalObservationSeconds = $NaturalObservationSeconds
        CampaignDayDeltaWhileWaiting = $dayDelta
        HoldClearedNativeTargets = $targetCleared
        MovementStoppedAfterNaturalWindow = $movementStoppedAfterNaturalWindow
        StoppableModeWaitingAtHold = $stoppableModeWaitingAtHold
        WaitingRemainedTrue = $waitingObserved
        NoExplicitClockActionAfterHold = $noHiddenClockAction
        FixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = $stop.processStopped
    }
    $result.Passed = (
        $targetCleared -and $movementStoppedAfterNaturalWindow -and $stoppableModeWaitingAtHold -and $waitingObserved -and $dayDelta -le 0.001 -and
        $noHiddenClockAction -and $result.FixtureUnchanged -and $result.ProcessStopped
    )
    $json = $result | ConvertTo-Json -Depth 12
    if ($env:CHRONICLE_HARNESS_TEMP -and (Test-Path -LiteralPath $env:CHRONICLE_HARNESS_TEMP -PathType Container)) {
        Set-Content -LiteralPath (Join-Path $env:CHRONICLE_HARNESS_TEMP 'AgentHoldResult.json') -Value $json -Encoding UTF8
    }
    $json
    if (-not $result.Passed) { throw 'Native Hold/settled-clock assertions failed; see AgentHoldResult.json and the response trace.' }
}
catch {
    throw
}
finally {
    if (Test-Path -LiteralPath $sessionPath) {
        try { Invoke-AgentCli 'stop' @('-CommandId', "$runPrefix-cleanup") 15 | Out-Null } catch { }
    }
}
