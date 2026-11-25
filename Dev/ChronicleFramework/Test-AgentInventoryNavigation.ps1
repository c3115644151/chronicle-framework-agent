#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$resultPath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP 'InventoryNavigationResult.json' } else { Join-Path $PSScriptRoot 'TestResults\ManualInventoryNavigation\InventoryNavigationResult.json' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$commandPrefix = 'inventory-nav-' + (Get-Date -Format 'yyyyMMddHHmmssfff')

if (-not (Test-Path -LiteralPath $savePath)) { throw "Inventory navigation fixture not found: $LoadSaveName" }
if (Get-Process -Name Bannerlord -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $output = & $HarnessPowerShell -NoProfile -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

function Get-InventoryObservation([string]$Suffix) {
    return Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-$Suffix")
}

function Wait-ForGameState([string]$Expected, [int]$WaitSeconds = 10) {
    $deadline = [DateTime]::UtcNow.AddSeconds($WaitSeconds)
    $last = $null
    while ([DateTime]::UtcNow -lt $deadline) {
        $last = Get-InventoryObservation "wait-$Expected-$([Guid]::NewGuid().ToString('N'))"
        if ($last.state.context.gameState -eq $Expected) { return $last }
        Start-Sleep -Milliseconds 200
    }
    throw "GameState did not become $Expected. Last observed: $($last.state.context.gameState)"
}

try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $pause = Invoke-AgentCli 'pause' @('-CommandId', "$commandPrefix-pause-initial")
    $mapBefore = Get-InventoryObservation 'map-before'
    if ($mapBefore.state.context.gameState -ne 'MapState') { throw 'Inventory navigation test did not begin in Campaign Map.' }

    $pausedOpen = Invoke-AgentCli 'harnessOpenInventoryState' @('-CommandId', "$commandPrefix-open-paused")
    $inventoryPaused = Wait-ForGameState 'InventoryState'
    if ($pausedOpen.status -ne 'completed' -or -not $pausedOpen.data.inventoryStateActive -or -not $inventoryPaused.state.inventoryScreen.hasHandler)
        { throw 'Native Inventory NavigationElement did not open its Gauntlet InventoryState screen.' }
    $nativeInventoryPaused = Invoke-AgentCli 'harnessInventoryStateDiagnostics' @('-CommandId', "$commandPrefix-native-paused")
    $framePath = Join-Path $env:CHRONICLE_HARNESS_TEMP 'InventoryNavigation-frame.bmp'
    $frame = Invoke-AgentCli 'captureFrame' @('-OutputPath', $framePath, '-CommandId', "$commandPrefix-frame-paused")
    Start-Sleep -Seconds 2
    $pausedDuring = Get-InventoryObservation 'paused-after-wait'
    $nativePausedAfterWait = Invoke-AgentCli 'harnessInventoryStateDiagnostics' @('-CommandId', "$commandPrefix-native-paused-after-wait")
    $pausedDayUnchanged = ([double]$nativePausedAfterWait.data.campaignDay -eq [double]$nativeInventoryPaused.data.campaignDay)
    $pausedModeStable = ($nativeInventoryPaused.data.timeControlMode -eq 'Stop' -and $nativePausedAfterWait.data.timeControlMode -eq 'Stop')
    $pausedClose = Invoke-AgentCli 'harnessCloseInventoryState' @('-CommandId', "$commandPrefix-close-paused")
    $mapAfterPaused = Wait-ForGameState 'MapState'

    $resume = Invoke-AgentCli 'resume' @('-CommandId', "$commandPrefix-resume")
    $activeMapBefore = Get-InventoryObservation 'active-map-before'
    $activeOpen = Invoke-AgentCli 'harnessOpenInventoryState' @('-CommandId', "$commandPrefix-open-active")
    $inventoryActiveBefore = Wait-ForGameState 'InventoryState'
    $nativeInventoryActiveBefore = Invoke-AgentCli 'harnessInventoryStateDiagnostics' @('-CommandId', "$commandPrefix-native-active-before")
    Start-Sleep -Seconds 3
    $inventoryActiveAfter = Get-InventoryObservation 'active-after-wait'
    $nativeInventoryActiveAfter = Invoke-AgentCli 'harnessInventoryStateDiagnostics' @('-CommandId', "$commandPrefix-native-active-after")
    $activeModeStable = (
        $activeOpen.status -eq 'completed' -and
        $nativeInventoryActiveBefore.data.timeControlMode -eq $activeMapBefore.state.context.timeControlMode -and
        $nativeInventoryActiveAfter.data.timeControlMode -eq $activeMapBefore.state.context.timeControlMode
    )
    $activeDayNondecreasing = ([double]$nativeInventoryActiveAfter.data.campaignDay -ge [double]$nativeInventoryActiveBefore.data.campaignDay)
    $activeClose = Invoke-AgentCli 'harnessCloseInventoryState' @('-CommandId', "$commandPrefix-close-active")
    $mapAfterActive = Wait-ForGameState 'MapState'
    $pauseEnd = Invoke-AgentCli 'pause' @('-CommandId', "$commandPrefix-pause-end")
    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-stop") 30
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash

    $assertions = [ordered]@{
        OpenUsesNativeInventoryNavigationElement = ($pausedOpen.data.entryId -eq 'inventory' -and $pausedOpen.data.inventoryStateActive -and $inventoryPaused.state.context.gameState -eq 'InventoryState')
        GauntletInventoryStateHandlerInitialized = [bool]$inventoryPaused.state.inventoryScreen.hasHandler
        NativeSPInventoryVMTargetsMainHero = ($nativeInventoryPaused.status -eq 'completed' -and $nativeInventoryPaused.data.isMainHeroSelected -and @($nativeInventoryPaused.data.equipmentSlots).Count -gt 0)
        EngineScreenshotCapturedInInventoryState = ($frame.status -eq 'completed' -and (Test-Path -LiteralPath $framePath))
        StopModeRemainsStopInsideInventoryState = ($pausedModeStable -and $pausedDayUnchanged)
        CancelReturnsToMapWithoutChangingTimeMode = ($pausedClose.data.returnedToMap -and $mapAfterPaused.state.context.gameState -eq 'MapState' -and $mapAfterPaused.state.context.timeControlMode -eq 'Stop')
        ActiveModeIsNotHiddenlyPausedOrChanged = [bool]$activeModeStable
        ActiveCampaignDayDoesNotGoBackwards = [bool]$activeDayNondecreasing
        ActiveInventoryCancelReturnsToMap = ($activeClose.data.returnedToMap -and $mapAfterActive.state.context.gameState -eq 'MapState' -and $mapAfterActive.state.context.timeControlMode -eq $activeMapBefore.state.context.timeControlMode)
        FormalFixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = [bool]$stop.processStopped
    }
    $failedAssertions = @($assertions.Keys | Where-Object { -not [bool]$assertions[$_] })
    $result = [ordered]@{
        Paused = [ordered]@{ Open = $pausedOpen.data; InventoryBefore = $nativeInventoryPaused.data; InventoryAfterWait = $nativePausedAfterWait.data; Close = $pausedClose.data; DayBefore = $nativeInventoryPaused.data.campaignDay; DayAfter = $nativePausedAfterWait.data.campaignDay; TimeModeAfterMap = $mapAfterPaused.state.context.timeControlMode }
        Active = [ordered]@{ MapMode = $activeMapBefore.state.context.timeControlMode; Open = $activeOpen.data; InventoryBefore = $nativeInventoryActiveBefore.data; InventoryAfterWait = $nativeInventoryActiveAfter.data; Close = $activeClose.data; DayBefore = $nativeInventoryActiveBefore.data.campaignDay; DayAfter = $nativeInventoryActiveAfter.data.campaignDay; TimeModeAfterMap = $mapAfterActive.state.context.timeControlMode }
        EngineFrame = [ordered]@{ Path = $framePath; Receipt = $frame.data }
        StartupDialogReceipts = @($start.session.startupDialogReceipts)
        Assertions = $assertions
        FailedAssertions = $failedAssertions
        FixtureHashBefore = $fixtureHashBefore
        FixtureHashAfter = $fixtureHashAfter
        ProcessStopped = [bool]$stop.processStopped
        Passed = ($failedAssertions.Count -eq 0)
    }
    $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    $result | ConvertTo-Json -Depth 12
    if (-not $result.Passed) { throw 'Native Inventory navigation/time/cancel regression failed.' }
}
finally {
    if (Test-Path -LiteralPath $sessionPath) {
        try {
            $current = Get-InventoryObservation "cleanup-state-$([Guid]::NewGuid().ToString('N'))"
            if ($current.state.context.gameState -eq 'InventoryState') { Invoke-AgentCli 'harnessCloseInventoryState' @('-CommandId', "$commandPrefix-cleanup-inventory") | Out-Null }
            Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-cleanup") 20 | Out-Null
        } catch { }
    }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
