#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$runDirectory = if ($env:CHRONICLE_HARNESS_TEMP) { Split-Path -Parent $env:CHRONICLE_HARNESS_TEMP } else { Join-Path (Split-Path -Parent $PSScriptRoot) 'TestResults\ManualMapSettlementTargets' }
$resultName = 'MapSettlementTargetsResult.json'
$resultPath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP $resultName } else { Join-Path $runDirectory $resultName }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$commandPrefix = 'map-settlement-targets-' + (Get-Date -Format 'yyyyMMddHHmmssfff')
$fixtureHashBefore = $null
$result = $null

if (-not (Test-Path -LiteralPath $savePath)) { throw "Map settlement target fixture not found: $savePath" }
if (Get-Process -Name Bannerlord -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0, [switch]$AllowProtocolRejection) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $output = & $HarnessPowerShell -NoProfile -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    try { $receipt = $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON (exit=$exitCode): $output" }
    if ($exitCode -ne 0 -and -not $AllowProtocolRejection) { throw "Agent CLI '$Action' failed (exit=$exitCode): $output" }
    return $receipt
}

try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $before = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-before")
    if ($before.state.context.gameState -ne 'MapState') { throw "Visible Settlement validation requires Campaign Map; got '$($before.state.context.gameState)'." }

    $diagnostics = Invoke-AgentCli 'harnessMapDiagnostics' @('-CommandId', "$commandPrefix-diagnostics")
    $mapTargetsReceipt = Invoke-AgentCli 'mapSettlementTargets' @('-CommandId', "$commandPrefix-map-targets")
    if ($mapTargetsReceipt.status -ne 'completed' -or -not $mapTargetsReceipt.data) { throw 'On-demand mapSettlementTargets observation was not completed.' }
    $allSettlements = @($diagnostics.data.settlements)
    $visibleSettlementIds = @($allSettlements | Where-Object { $_.isVisible } | ForEach-Object { [string]$_.id } | Sort-Object)
    $observedSettlementIds = @($mapTargetsReceipt.data.mapSettlementTargets | ForEach-Object { [string]$_.id } | Sort-Object)
    $visibleTargetSetMatches = (@(Compare-Object -ReferenceObject $visibleSettlementIds -DifferenceObject $observedSettlementIds).Count -eq 0)

    $hiddenCandidate = @($allSettlements | Where-Object { -not $_.isVisible } | Select-Object -First 1)
    if ($hiddenCandidate.Count -ne 1) { throw 'The disposable Campaign fixture has no active Settlement with IsVisible=false, so the hidden-target rejection branch cannot be tested in this fixture.' }
    $hiddenId = [string]$hiddenCandidate[0].id
    $hiddenIdAbsentFromMapObservation = $hiddenId -notin $observedSettlementIds
    $move = Invoke-AgentCli 'move' @('-SettlementId', $hiddenId, '-CommandId', "$commandPrefix-hidden-move") 30 -AllowProtocolRejection
    $after = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-after")

    $moveRejectedForVisibility = ($move.status -eq 'rejected' -and [string]$move.error -like '*visible Campaign map target*')
    $noMutation = (
        [Math]::Abs([double]$after.state.location.x - [double]$before.state.location.x) -le 0.001 -and
        [Math]::Abs([double]$after.state.location.y - [double]$before.state.location.y) -le 0.001 -and
        $after.state.location.currentSettlementId -eq $before.state.location.currentSettlementId -and
        $after.state.location.targetSettlementId -eq $before.state.location.targetSettlementId -and
        $after.state.location.targetPartyId -eq $before.state.location.targetPartyId -and
        $after.state.party.moveMode -eq $before.state.party.moveMode -and
        $after.state.party.isMoving -eq $before.state.party.isMoving -and
        $after.state.context.timeControlMode -eq $before.state.context.timeControlMode -and
        [Math]::Abs([double]$after.campaignDay - [double]$before.campaignDay) -le 0.001
    )

    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-stop") 30
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $result = [ordered]@{
        ActiveSettlementCount = $diagnostics.data.activeSettlementCount
        VisibleSettlementCount = $diagnostics.data.visibleSettlementCount
        HiddenSettlementCount = $diagnostics.data.hiddenSettlementCount
        MapSettlementTargetCount = $observedSettlementIds.Count
        VisibleTargetSetMatches = $visibleTargetSetMatches
        MapSettlementObservationSchemaVersion = $mapTargetsReceipt.data.schemaVersion
        HiddenCandidate = $hiddenCandidate[0]
        HiddenIdAbsentFromMapObservation = $hiddenIdAbsentFromMapObservation
        MoveReceipt = $move
        MoveRejectedForVisibility = $moveRejectedForVisibility
        NoMutation = $noMutation
        CampaignDayBefore = $before.campaignDay
        CampaignDayAfter = $after.campaignDay
        FixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = $stop.processStopped
    }
    $result.Passed = ($visibleTargetSetMatches -and $hiddenIdAbsentFromMapObservation -and $moveRejectedForVisibility -and $noMutation -and $result.FixtureUnchanged -and $result.ProcessStopped)
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    $result | ConvertTo-Json -Depth 8
    if (-not $result.Passed) { throw 'Map visible Settlement targets diverged from native IsVisible targets, or a hidden target changed Campaign state.' }
}
finally {
    if (Test-Path $sessionPath) {
        try { Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-cleanup") 20 | Out-Null } catch { }
    }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
