[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$tempPath = $env:CHRONICLE_HARNESS_TEMP
$runDirectory = if ($tempPath) { Split-Path -Parent $tempPath } else { Join-Path $PSScriptRoot 'TestResults\ManualMissionLeave' }
$beforeFrame = if ($tempPath) { Join-Path $tempPath 'mission-leave-before.bmp' } else { Join-Path $runDirectory 'mission-leave-before.bmp' }
$afterFrame = if ($tempPath) { Join-Path $tempPath 'mission-leave-after.bmp' } else { Join-Path $runDirectory 'mission-leave-after.bmp' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$prefix = 'mission-leave-' + (Get-Date -Format 'yyyyMMddHHmmssfff')

if (-not (Test-Path -LiteralPath $savePath)) { throw "Disposable Mission Leave fixture not found: $savePath" }
if (Get-Process -Name Bannerlord -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

function Capture-EngineFrame([string]$Path, [string]$Suffix) {
    $receipt = Invoke-AgentCli 'captureFrame' @('-OutputPath', $Path, '-CommandId', "$prefix-$Suffix") 30
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path -LiteralPath $Path) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
    if ($receipt.status -ne 'completed' -or -not (Test-Path -LiteralPath $Path) -or (Get-Item -LiteralPath $Path).Length -lt 4096) {
        throw "Game-engine screenshot '$Path' was not produced."
    }
}

try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $initial = Invoke-AgentCli 'state' @('-CommandId', "$prefix-initial")
    if ($initial.state.context.gameState -ne 'MapState') { throw "Fixture must begin on Campaign Map, got $($initial.state.context.gameState)." }

    $town = @($initial.state.nearbySettlements | Where-Object { $_.id -eq 'town_V1' -and $_.type -eq 'town' -and -not $_.hostile } | Select-Object -First 1)
    if ($town.Count -ne 1) { throw 'Sargot (town_V1) is not a safe visible settlement in the disposable fixture.' }
    $move = Invoke-AgentCli 'move' @('-SettlementId', 'town_V1', '-CommandId', "$prefix-move")
    if ($move.status -ne 'completed' -or $move.state.location.targetSettlementId -ne 'town_V1') { throw 'Native Campaign movement did not accept Sargot.' }

    $arrivalDeadline = [DateTime]::UtcNow.AddSeconds(120)
    $arrived = $null
    while ([DateTime]::UtcNow -lt $arrivalDeadline) {
        Start-Sleep -Milliseconds 400
        $arrived = Invoke-AgentCli 'state' @('-CommandId', "$prefix-arrival-$([Guid]::NewGuid().ToString('N'))") 30
        if ($arrived.state.location.currentSettlementId -eq 'town_V1' -and $arrived.state.context.menuId -eq 'town') { break }
        if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'Game process exited during natural Campaign movement.' }
    }
    if (-not $arrived -or $arrived.state.location.currentSettlementId -ne 'town_V1' -or $arrived.state.context.menuId -ne 'town') { throw 'Natural Campaign movement did not reach the Sargot menu.' }

    $centerOption = @($arrived.state.availableMenuOptions | Where-Object { $_.id -eq 'town_streets' -and $_.available -and $_.enabled } | Select-Object -First 1)
    if ($centerOption.Count -ne 1) { throw 'Sargot native menu has no enabled town_streets entry.' }
    $enter = Invoke-AgentCli 'menuSelect' @('-MenuId', 'town', '-OptionId', 'town_streets', '-CommandId', "$prefix-enter")
    if ($enter.status -ne 'completed' -or $enter.state.context.gameState -ne 'MissionState') { throw 'Native town_streets entry did not start a Location Mission.' }

    $sceneDeadline = [DateTime]::UtcNow.AddSeconds(60)
    $scene = $enter
    while ((!$scene.state.mission -or !$scene.state.mission.mainAgent) -and [DateTime]::UtcNow -lt $sceneDeadline) {
        Start-Sleep -Milliseconds 400
        if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'Game process exited while loading the Town center Mission.' }
        $scene = Invoke-AgentCli 'state' @('-CommandId', "$prefix-scene-$([Guid]::NewGuid().ToString('N'))") 30
    }
    if (-not $scene.state.mission.mainAgent -or $scene.state.mission.sceneName -notmatch '_town_') { throw 'A native Town center scene/MainAgent was not available.' }
    if ($scene.state.context.timeControlMode -ne 'Stop') { throw "Campaign clock was not stopped in the Town Mission: $($scene.state.context.timeControlMode)." }
    Start-Sleep -Seconds 2
    $scene = Invoke-AgentCli 'state' @('-CommandId', "$prefix-scene-settled")
    if ($scene.state.context.gameState -ne 'MissionState' -or -not $scene.state.mission.mainAgent) { throw 'Town center Mission changed before its stable-frame observation.' }
    Capture-EngineFrame $beforeFrame 'capture-before-leave'

    $missionDayBefore = [double]$scene.campaignDay
    $leave = Invoke-AgentCli 'missionLeave' @('-CommandId', "$prefix-leave") 30
    if ($leave.status -ne 'completed' -or $leave.state.context.gameState -ne 'MissionState' -or -not $leave.state.mission.leave.active) {
        throw 'missionLeave did not start a bounded Native Leave Area input lease in the current Location Mission.'
    }

    $returnDeadline = [DateTime]::UtcNow.AddSeconds(15)
    $returned = $null
    $maxNativeLeaveProgress = 0.0
    $missionSamples = 0
    while ([DateTime]::UtcNow -lt $returnDeadline) {
        Start-Sleep -Milliseconds 100
        if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'Game process exited during the native Leave Area hold.' }
        $returned = Invoke-AgentCli 'state' @('-CommandId', "$prefix-return-$([Guid]::NewGuid().ToString('N'))") 30
        if ($returned.state.context.gameState -eq 'MapState') { break }
        if ($returned.state.mission.leave) {
            $missionSamples++
            $maxNativeLeaveProgress = [Math]::Max($maxNativeLeaveProgress, [double]$returned.state.mission.leave.nativeLeaveProgressSeconds)
        }
    }
    if (-not $returned -or $returned.state.context.gameState -ne 'MapState') { throw 'The Native Leave Area hold did not return the Campaign to MapState before its bounded lease ended.' }
    if ($returned.state.location.currentSettlementId -ne 'town_V1' -or $returned.state.context.menuId -ne 'town') { throw 'The Native Leave Area hold did not return to the Sargot Campaign menu.' }
    Capture-EngineFrame $afterFrame 'capture-after-leave'

    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-stop") 30
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $result = [ordered]@{
        ProcessId = $start.session.processId
        SceneName = $scene.state.mission.sceneName
        NativeInputRoute = $leave.data.nativeInputContext
        HoldLeaseSeconds = $leave.data.holdSeconds
        NativeLeaveThresholdSeconds = $leave.data.missionEndTimeInSeconds
        MissionSamplesDuringHold = $missionSamples
        MaxObservedNativeLeaveProgressSeconds = [Math]::Round($maxNativeLeaveProgress, 3)
        ReturnedGameState = $returned.state.context.gameState
        ReturnedSettlementId = $returned.state.location.currentSettlementId
        ReturnedMenuId = $returned.state.context.menuId
        CampaignDayAtMission = $missionDayBefore
        CampaignDayAtReturn = [double]$returned.campaignDay
        CampaignTimeUnchanged = ([Math]::Abs([double]$returned.campaignDay - $missionDayBefore) -lt 0.0001)
        TimeControlModeAtMission = $scene.state.context.timeControlMode
        TimeControlModeAtReturn = $returned.state.context.timeControlMode
        EngineScreenshots = @($beforeFrame, $afterFrame)
        FixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = [bool]$stop.processStopped
    }
    $result.Passed = ($result.NativeInputRoute -match 'Mission.InputManager.IsGameKeyDown\(LeaveArea\)' -and $result.ReturnedGameState -eq 'MapState' -and $result.ReturnedSettlementId -eq 'town_V1' -and $result.ReturnedMenuId -eq 'town' -and $result.CampaignTimeUnchanged -and $result.TimeControlModeAtMission -eq 'Stop' -and $result.TimeControlModeAtReturn -eq 'Stop' -and $result.FixtureUnchanged -and $result.ProcessStopped)
    $json = $result | ConvertTo-Json -Depth 12
    if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) { Set-Content -LiteralPath (Join-Path $tempPath 'MissionLeaveResult.json') -Value $json -Encoding UTF8 }
    $json
    if (-not $result.Passed) { throw 'Native Mission Leave failed its return, clock, cleanup or fixture-preservation assertion.' }
}
finally {
    if (Test-Path -LiteralPath $sessionPath) { try { Invoke-AgentCli 'stop' @('-CommandId', "$prefix-cleanup") 20 | Out-Null } catch { } }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
