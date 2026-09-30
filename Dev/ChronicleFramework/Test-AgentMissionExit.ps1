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
$runDirectory = if ($tempPath) { Split-Path -Parent $tempPath } else { Join-Path $PSScriptRoot 'TestResults\ManualMissionExit' }
$beforeFrame = if ($tempPath) { Join-Path $tempPath 'mission-exit-before.bmp' } else { Join-Path $runDirectory 'mission-exit-before.bmp' }
$afterFrame = if ($tempPath) { Join-Path $tempPath 'mission-exit-after.bmp' } else { Join-Path $runDirectory 'mission-exit-after.bmp' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$prefix = 'mission-exit-' + (Get-Date -Format 'yyyyMMddHHmmssfff')

if (-not (Test-Path -LiteralPath $savePath)) { throw "Disposable Mission Exit fixture not found: $savePath" }
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
        Start-Sleep -Milliseconds 500
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
    Start-Sleep -Seconds 3
    $scene = Invoke-AgentCli 'state' @('-CommandId', "$prefix-scene-settled")
    if ($scene.state.context.gameState -ne 'MissionState' -or -not $scene.state.mission.mainAgent) { throw 'Town center Mission changed before its settled-frame observation.' }
    Capture-EngineFrame $beforeFrame 'capture-before-candidate-check'

    $candidate = @($scene.state.mission.exitTargets | Where-Object { $_.isNativeExit -and $_.isUsableNow -and $_.hasPath } | Sort-Object distance | Select-Object -First 1)
    if ($candidate.Count -ne 1) {
        $diagnostics = Invoke-AgentCli 'harnessMissionDiagnostics' @('-CommandId', "$prefix-exit-diagnostics") 30
        $noExitStop = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-stop-no-exit") 30
        $noExitFixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
        $noExitResult = [ordered]@{ Status = 'NoNativeExitCandidate'; Scene = $scene.state.mission.sceneName; ExitTargets = $scene.state.mission.exitTargets; ExitLikeNativeObjects = $diagnostics.data.exitLikeObjects; EngineScreenshot = $beforeFrame; FixtureUnchanged = ($fixtureHashBefore -eq $noExitFixtureHashAfter); ProcessStopped = [bool]$noExitStop.processStopped; ProductPathVerified = $false }
        if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) { $noExitResult | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $tempPath 'MissionExitResult.json') -Encoding UTF8 }
        $noExitResult | ConvertTo-Json -Depth 8
        if (-not $noExitResult.FixtureUnchanged -or -not $noExitResult.ProcessStopped) { throw 'No-exit diagnostic failed to preserve its fixture or stop the game process cleanly.' }
        throw 'Current official Town center Mission exposed no usable, reachable Native exit; refusing to synthesize Mission.EndMission.'
    }

    Capture-EngineFrame $beforeFrame 'capture-before'
    $before = Invoke-AgentCli 'state' @('-CommandId', "$prefix-before-exit")
    $invalidRejected = $false
    try {
        Invoke-AgentCli 'missionUseExit' @('-MissionObjectId', '2147483647:1', '-CommandId', "$prefix-invalid-id") 30 | Out-Null
    }
    catch { $invalidRejected = $true }
    if (-not $invalidRejected) { throw 'A stale/nonexistent Mission exit id was not rejected.' }
    $afterInvalid = Invoke-AgentCli 'state' @('-CommandId', "$prefix-after-invalid")
    if ($afterInvalid.state.context.gameState -ne 'MissionState' -or $afterInvalid.state.mission.sceneName -ne $before.state.mission.sceneName) { throw 'Invalid exit id changed the active Mission.' }

    $startPosition = $scene.state.mission.mainAgent.position
    $navigation = Invoke-AgentCli 'missionNavigateToExit' @('-MissionObjectId', [string]$candidate[0].missionObjectId, '-DurationSeconds', '16', '-CommandId', "$prefix-navigate") 30
    if ($navigation.status -ne 'completed' -or $navigation.data.missionObjectId -ne $candidate[0].missionObjectId) { throw 'Native Mission exit navigation was not accepted for the current observation candidate.' }
    $navigationDeadline = [DateTime]::UtcNow.AddSeconds(18)
    $atExit = $null
    do {
        Start-Sleep -Milliseconds 300
        $atExit = Invoke-AgentCli 'state' @('-CommandId', "$prefix-nav-state-$([Guid]::NewGuid().ToString('N'))") 30
    } while ($atExit.state.context.gameState -eq 'MissionState' -and $atExit.state.mission.navigation.active -and [DateTime]::UtcNow -lt $navigationDeadline)
    if ($atExit.state.context.gameState -ne 'MissionState' -or $atExit.state.mission.navigation.active) { throw 'Bounded native navigation did not finish in the same Mission.' }
    if (-not $atExit.state.mission.mainAgent.isPlayerControlled) { throw 'Native navigation did not restore Player control after the bounded lease.' }
    $distanceMoved = [Math]::Sqrt([Math]::Pow(([double]$atExit.state.mission.mainAgent.position.x - [double]$startPosition.x), 2) + [Math]::Pow(([double]$atExit.state.mission.mainAgent.position.y - [double]$startPosition.y), 2) + [Math]::Pow(([double]$atExit.state.mission.mainAgent.position.z - [double]$startPosition.z), 2))
    $nearby = @($atExit.state.mission.exitTargets | Where-Object { $_.missionObjectId -eq $candidate[0].missionObjectId } | Select-Object -First 1)
    if ($nearby.Count -ne 1 -or [double]$nearby[0].distance -gt 2.5) { throw 'Native AgentNavigator ended outside the exit interaction range.' }

    $use = Invoke-AgentCli 'missionUseExit' @('-MissionObjectId', [string]$candidate[0].missionObjectId, '-CommandId', "$prefix-use") 30
    if ($use.status -ne 'completed' -or -not $use.data.nativeUseRequested) { throw 'Native Agent.HandleStartUsingAction did not begin the exit action.' }
    $returnDeadline = [DateTime]::UtcNow.AddSeconds(20)
    $returned = $null
    while ([DateTime]::UtcNow -lt $returnDeadline) {
        Start-Sleep -Milliseconds 400
        if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'Game process exited while native exit animation/transition was running.' }
        $returned = Invoke-AgentCli 'state' @('-CommandId', "$prefix-return-$([Guid]::NewGuid().ToString('N'))") 30
        if ($returned.state.context.gameState -eq 'MapState') { break }
    }
    if (-not $returned -or $returned.state.context.gameState -ne 'MapState') { throw 'Native exit interaction did not return the Campaign to MapState.' }
    if ($returned.state.location.currentSettlementId -ne 'town_V1' -or $returned.state.context.menuId -ne 'town') { throw 'Native exit returned to a different Campaign location/menu than the active Town center.' }
    Capture-EngineFrame $afterFrame 'capture-after'

    $finalStop = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-stop") 30
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $result = [ordered]@{
        ProcessId = $start.session.processId
        SceneName = $scene.state.mission.sceneName
        NativeExitCandidate = $candidate[0]
        InvalidIdRejectedWithoutLeavingMission = $invalidRejected
        NavigationDistanceMoved = [Math]::Round($distanceMoved, 3)
        PlayerControlRestored = [bool]$atExit.state.mission.mainAgent.isPlayerControlled
        NativeUseReceipt = $use.data
        ReturnedGameState = $returned.state.context.gameState
        ReturnedSettlementId = $returned.state.location.currentSettlementId
        ReturnedMenuId = $returned.state.context.menuId
        CampaignDayAtMission = $scene.campaignDay
        CampaignDayBeforeUse = $before.campaignDay
        CampaignDayAfterReturn = $returned.campaignDay
        TimeControlModeAtMission = $scene.state.context.timeControlMode
        TimeControlModeAfterReturn = $returned.state.context.timeControlMode
        EngineScreenshots = @($beforeFrame, $afterFrame)
        FixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = [bool]$finalStop.processStopped
    }
    $result.Passed = ($result.InvalidIdRejectedWithoutLeavingMission -and $distanceMoved -ge 0.1 -and $result.PlayerControlRestored -and $result.ReturnedGameState -eq 'MapState' -and $result.ReturnedSettlementId -eq 'town_V1' -and $result.ReturnedMenuId -eq 'town' -and $result.FixtureUnchanged -and $result.ProcessStopped)
    $json = $result | ConvertTo-Json -Depth 14
    if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) { Set-Content -LiteralPath (Join-Path $tempPath 'MissionExitResult.json') -Value $json -Encoding UTF8 }
    $json
    if (-not $result.Passed) { throw 'Native Mission Exit path failed its runtime return, cleanup or fixture-preservation assertion.' }
}
finally {
    if (Test-Path -LiteralPath $sessionPath) { try { Invoke-AgentCli 'stop' @('-CommandId', "$prefix-cleanup") 20 | Out-Null } catch { } }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
