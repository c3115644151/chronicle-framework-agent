#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [ValidateRange(30,300)][int]$ArrivalTimeoutSeconds = 180,
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$decisionLoop = Join-Path $PSScriptRoot 'Agent-DecisionLoop.ps1'
$decisionProvider = Join-Path $PSScriptRoot 'Test-AgentLoopProvider.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$runDirectory = if ($env:CHRONICLE_HARNESS_TEMP) { Split-Path -Parent $env:CHRONICLE_HARNESS_TEMP } else { Join-Path (Split-Path -Parent $PSScriptRoot) 'TestResults\ManualTavernMission' }
$captureTempPath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP 'TavernMission-frame.bmp' } else { Join-Path $runDirectory 'TavernMission-frame.bmp' }
$capturePath = Join-Path $runDirectory 'TavernMission-frame.bmp'
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$commandPrefix = 'tavern-' + (Get-Date -Format 'yyyyMMddHHmmssfff')

if (-not (Test-Path -LiteralPath $savePath)) { throw "Tavern Mission fixture not found: $savePath" }
if (Get-Process -Name Bannerlord -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $output = & $HarnessPowerShell -NoProfile -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $initial = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-initial")
    if ($initial.state.context.gameState -ne 'MapState') { throw "Tavern fixture must start on campaign map; got $($initial.state.context.gameState)." }

    $settlement = @($initial.state.nearbySettlements | Where-Object { $_.type -eq 'town' -and -not $_.hostile } | Sort-Object distance | Select-Object -First 1)
    if ($settlement.Count -ne 1) { throw 'No visible non-hostile town exists in the disposable fixture.' }
    $move = Invoke-AgentCli 'move' @('-SettlementId', [string]$settlement[0].id, '-CommandId', "$commandPrefix-move")
    if ($move.status -ne 'completed' -or $move.state.location.targetSettlementId -ne $settlement[0].id) { throw 'Native campaign map movement did not accept the visible town target.' }

    $arrivalDeadline = [DateTime]::UtcNow.AddSeconds($ArrivalTimeoutSeconds)
    $arrived = $null
    while ([DateTime]::UtcNow -lt $arrivalDeadline) {
        $arrived = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-arrival-$([Guid]::NewGuid().ToString('N'))") 30
        if ($arrived.state.location.currentSettlementId -eq $settlement[0].id -and $arrived.state.context.menuId -eq 'town') { break }
        if ($arrived.state.context.encounterActive -and $arrived.state.context.encounteredPartyId -ne $settlement[0].id) {
            throw "Unexpected encounter '$($arrived.state.context.encounteredPartyId)' interrupted travel to the town."
        }
        if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'Game process exited during natural travel to the town.' }
        Start-Sleep -Milliseconds 500
    }
    if (-not $arrived -or $arrived.state.location.currentSettlementId -ne $settlement[0].id -or $arrived.state.context.menuId -ne 'town') {
        throw "Natural campaign travel did not enter the town menu within $ArrivalTimeoutSeconds seconds."
    }

    $townOptions = @($arrived.state.availableMenuOptions | Where-Object { $_.id -eq 'town_backstreet' -and $_.available -and $_.enabled })
    if ($townOptions.Count -ne 1) { throw 'Native Town menu did not expose an enabled Tavern district option.' }
    $backstreet = Invoke-AgentCli 'menuSelect' @('-MenuId', 'town', '-OptionId', 'town_backstreet', '-CommandId', "$commandPrefix-backstreet")
    if ($backstreet.status -ne 'completed' -or $backstreet.state.context.menuId -ne 'town_backstreet' -or $backstreet.state.context.gameState -ne 'MapState') {
        throw 'Selecting the enabled Town Tavern district menu option did not enter town_backstreet.'
    }

    $tavernOptions = @($backstreet.state.availableMenuOptions | Where-Object { $_.id -eq 'town_tavern' -and $_.available -and $_.enabled })
    if ($tavernOptions.Count -ne 1) { throw 'Native Tavern district menu did not expose an enabled Visit Tavern option.' }
    $mission = Invoke-AgentCli 'menuSelect' @('-MenuId', 'town_backstreet', '-OptionId', 'town_tavern', '-CommandId', "$commandPrefix-enter-tavern")
    if ($mission.status -ne 'completed' -or $mission.state.context.gameState -ne 'MissionState') {
        throw "Native Visit Tavern option did not create MissionState; got '$($mission.state.context.gameState)'."
    }
    $missionDeadline = [DateTime]::UtcNow.AddSeconds(60)
    while ((-not $mission.state.mission -or -not $mission.state.mission.mainAgent) -and [DateTime]::UtcNow -lt $missionDeadline) {
        if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'Game process exited while the Tavern scene was loading.' }
        Start-Sleep -Milliseconds 500
        $mission = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-mission-ready-$([Guid]::NewGuid().ToString('N'))") 30
    }
    if ($mission.state.context.gameState -ne 'MissionState' -or -not $mission.state.mission -or -not $mission.state.mission.mainAgent) {
        throw 'Tavern menu transition reached MissionState, but the scene did not expose an active MainAgent within 60 seconds.'
    }
    if ($mission.state.context.timeControlMode -ne 'Stop') { throw "Campaign time was not stopped in Tavern MissionState: $($mission.state.context.timeControlMode)." }

    $positionBeforeInput = $mission.state.mission.mainAgent.position
    $targetBefore = @($mission.state.mission.nearbyHeroAgents | Where-Object { -not $_.isEnemy -and $_.distance -gt 1.2 } | Sort-Object distance | Select-Object -First 1)
    if ($targetBefore.Count -ne 1) { throw 'Tavern scene exposed no safe nearby HeroAgent for the bounded approach test.' }
    $previousProviderMode = $env:CHRONICLE_TEST_PROVIDER_MODE
    $env:CHRONICLE_TEST_PROVIDER_MODE = 'tavernApproach'
    try {
        $loopOutput = & $HarnessPowerShell -NoProfile -File $decisionLoop -DecisionProviderPath $decisionProvider -MaxDecisions 1 -TimeoutSeconds $TimeoutSeconds -CommandPrefix "$commandPrefix-approach-loop" 2>&1 | Out-String
        $loopExitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $previousProviderMode) { Remove-Item Env:CHRONICLE_TEST_PROVIDER_MODE -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_TEST_PROVIDER_MODE = $previousProviderMode }
    }
    if ($loopExitCode -ne 0) { throw "Native Mission movement decision loop failed: $loopOutput" }
    $movementLoop = $loopOutput | ConvertFrom-Json
    $movementStep = $movementLoop.trace[0]
    $inputReceipt = $movementStep.actionReceipt
    if ($movementStep.decision.action -ne 'missionInput' -or $inputReceipt.status -ne 'completed' -or $inputReceipt.data.boundedLease -ne $true) { throw 'Bounded native Tavern MainAgent movement input was not accepted by the decision loop.' }
    Start-Sleep -Seconds 1
    $afterInput = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-after-forward-step")
    $positionAfterInput = $afterInput.state.mission.mainAgent.position
    $movementDistance = [Math]::Sqrt([Math]::Pow(([double]$positionAfterInput.x - [double]$positionBeforeInput.x), 2) + [Math]::Pow(([double]$positionAfterInput.y - [double]$positionBeforeInput.y), 2) + [Math]::Pow(([double]$positionAfterInput.z - [double]$positionBeforeInput.z), 2))
    $inputClearedAutomatically = ([Math]::Abs([double]$afterInput.state.mission.mainAgent.movementInput.x) -lt 0.001 -and [Math]::Abs([double]$afterInput.state.mission.mainAgent.movementInput.y) -lt 0.001)
    $targetAfter = @($afterInput.state.mission.nearbyHeroAgents | Where-Object { $_.heroId -eq $targetBefore[0].heroId } | Select-Object -First 1)
    $targetDistanceAfter = if ($targetAfter.Count -eq 1) { [double]$targetAfter[0].distance } else { [double]$targetBefore[0].distance }
    $targetDistanceImproved = $targetDistanceAfter -lt ([double]$targetBefore[0].distance - 0.1)
    Start-Sleep -Milliseconds 500
    $afterSettle = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-after-input-settle")
    $positionAfterSettle = $afterSettle.state.mission.mainAgent.position
    $settledDrift = [Math]::Sqrt([Math]::Pow(([double]$positionAfterSettle.x - [double]$positionAfterInput.x), 2) + [Math]::Pow(([double]$positionAfterSettle.y - [double]$positionAfterInput.y), 2) + [Math]::Pow(([double]$positionAfterSettle.z - [double]$positionAfterInput.z), 2))

    $navigationCandidate = @($afterSettle.state.mission.nearbySceneAgents | Where-Object { -not $_.isEnemy -and $_.distance -gt 2.0 } | Sort-Object distance | Select-Object -First 1)
    $navigationReceipt = $null
    $navigationEnd = $afterSettle
    $navigationError = $null
    if ($navigationCandidate.Count -eq 1) {
        try {
            $navigationReceipt = Invoke-AgentCli 'missionNavigateToAgent' @('-AgentIndex', [string]$navigationCandidate[0].agentIndex, '-CommandId', "$runPrefix-native-navigation") 30
            $navigationDeadline = [DateTime]::UtcNow.AddSeconds(9)
            while ([DateTime]::UtcNow -lt $navigationDeadline) {
                Start-Sleep -Milliseconds 500
                $navigationEnd = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-native-navigation-state-$([Guid]::NewGuid().ToString('N'))") 30
                if (-not $navigationEnd.state.mission.navigation -or -not $navigationEnd.state.mission.navigation.active) { break }
            }
        }
        catch { $navigationError = $_.Exception.Message }
    }
    $navigationStartPosition = $afterSettle.state.mission.mainAgent.position
    $navigationEndPosition = $navigationEnd.state.mission.mainAgent.position
    $navigationMovementDistance = [Math]::Sqrt([Math]::Pow(([double]$navigationEndPosition.x - [double]$navigationStartPosition.x), 2) + [Math]::Pow(([double]$navigationEndPosition.y - [double]$navigationStartPosition.y), 2) + [Math]::Pow(([double]$navigationEndPosition.z - [double]$navigationStartPosition.z), 2))

    $screenshot = Invoke-AgentCli 'captureFrame' @('-OutputPath', $captureTempPath, '-CommandId', "$commandPrefix-capture") 30
    $captureDeadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path -LiteralPath $captureTempPath) -and [DateTime]::UtcNow -lt $captureDeadline) { Start-Sleep -Milliseconds 100 }
    if ($screenshot.status -ne 'completed' -or -not (Test-Path -LiteralPath $captureTempPath) -or (Get-Item -LiteralPath $captureTempPath).Length -lt 4096) {
        throw 'Engine-native screenshot of the Tavern Mission did not produce a valid frame.'
    }
    if ($env:CHRONICLE_HARNESS_TEMP) { Move-Item -LiteralPath $captureTempPath -Destination $capturePath -Force }

    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-stop") 30
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $result = [ordered]@{
        ProcessId = $start.session.processId
        Settlement = $settlement[0]
        Entry = [ordered]@{ TownMenu = $backstreet.state.context.menuId; TavernOption = $tavernOptions[0].id; GameState = $mission.state.context.gameState; TimeControlMode = $mission.state.context.timeControlMode; SceneName = $mission.state.mission.sceneName; Mode = $mission.state.mission.mode; CombatType = $mission.state.mission.combatType; ActiveAgentCount = $mission.state.mission.activeAgentCount; Camera = $mission.state.mission.camera; MainAgent = $mission.state.mission.mainAgent; NativeFocus = $mission.state.mission.nativeFocus; NearbyHeroAgents = $mission.state.mission.nearbyHeroAgents }
        Movement = [ordered]@{ ProviderKind = 'deterministic-test-only'; Decision = $movementStep.decision; TargetHeroId = $targetBefore[0].heroId; TargetDistanceBefore = [Math]::Round([double]$targetBefore[0].distance, 3); TargetDistanceAfter = [Math]::Round($targetDistanceAfter, 3); TargetDistanceImproved = $targetDistanceImproved; ActionReceipt = $inputReceipt; MainAgentDistanceMoved = [Math]::Round($movementDistance, 3); InputClearedAutomatically = $inputClearedAutomatically; SettledDrift = [Math]::Round($settledDrift, 3); CampaignClockUnchanged = ($afterInput.campaignDay -eq $mission.campaignDay) }
        NativeNavigation = [ordered]@{ Candidate = if ($navigationCandidate.Count -eq 1) { $navigationCandidate[0] } else { $null }; Receipt = $navigationReceipt; Error = $navigationError; StartPosition = $navigationStartPosition; EndPosition = $navigationEndPosition; MainAgentDistanceMoved = [Math]::Round($navigationMovementDistance, 3); ControllerDuring = if ($navigationReceipt) { $navigationReceipt.state.mission.mainAgent.controller }; PlayerControllerRestored = $navigationEnd.state.mission.mainAgent.isPlayerControlled; FinalNavigationObservation = $navigationEnd.state.mission.navigation }
        CampaignDayBefore = $initial.campaignDay
        CampaignDayInMission = $mission.campaignDay
        EngineScreenshot = $capturePath
        FixtureUnchanged = $fixtureHashBefore -eq $fixtureHashAfter
        ProcessStopped = $stop.processStopped
    }
    $nativeNavigationVerified = if ($navigationCandidate.Count -eq 0) { $true } else { $null -ne $navigationReceipt -and $navigationReceipt.status -eq 'completed' -and $result.NativeNavigation.ControllerDuring -eq 'AI' -and $navigationMovementDistance -ge 0.1 -and $result.NativeNavigation.PlayerControllerRestored }
    $result.Passed = ($result.Entry.TownMenu -eq 'town_backstreet' -and $result.Entry.GameState -eq 'MissionState' -and $result.Entry.TimeControlMode -eq 'Stop' -and $movementStep.decision.action -eq 'missionInput' -and $inputReceipt.status -eq 'completed' -and $movementDistance -ge 0.1 -and $inputClearedAutomatically -and $settledDrift -le 0.1 -and $targetDistanceImproved -and $result.Movement.CampaignClockUnchanged -and $nativeNavigationVerified -and $result.FixtureUnchanged -and $result.ProcessStopped)
    $resultJson = $result | ConvertTo-Json -Depth 7
    if ($env:CHRONICLE_HARNESS_TEMP -and (Test-Path -LiteralPath $env:CHRONICLE_HARNESS_TEMP -PathType Container)) {
        Set-Content -LiteralPath (Join-Path $env:CHRONICLE_HARNESS_TEMP 'TavernMissionResult.json') -Value $resultJson -Encoding UTF8
    }
    $resultJson
    if (-not $result.Passed) { throw "Tavern Mission validation failed: movementDistance=$movementDistance, cleared=$inputClearedAutomatically, settledDrift=$settledDrift, campaignClockUnchanged=$($result.Movement.CampaignClockUnchanged)." }
}
finally {
    if (Test-Path -LiteralPath $sessionPath) {
        try { Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-cleanup") 20 | Out-Null } catch { }
    }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
