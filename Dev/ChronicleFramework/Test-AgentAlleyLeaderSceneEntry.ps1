[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [string]$TargetSettlementId = 'town_V1',
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$tempPath = $env:CHRONICLE_HARNESS_TEMP
$frameRoot = if ($tempPath) { $tempPath } else { Join-Path $PSScriptRoot 'TestResults\ManualAlleyLeaderSceneEntry' }
$resultPath = if ($tempPath) { Join-Path $tempPath 'AlleyLeaderSceneEntryResult.json' } else { Join-Path $frameRoot 'AlleyLeaderSceneEntryResult.json' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$prefix = 'alley-leader-entry-' + (Get-Date -Format 'yyyyMMddHHmmssfff')
$failedStep = 'preflight'
$frameTown = Join-Path $frameRoot 'alley-leader-entry-town-menu.bmp'
$frameMission = Join-Path $frameRoot 'alley-leader-entry-town-streets.bmp'
$frameAfterWalk = Join-Path $frameRoot 'alley-leader-entry-after-walk.bmp'
$frameConversation = Join-Path $frameRoot 'alley-leader-entry-conversation.bmp'

if (-not (Test-Path -LiteralPath $savePath)) { throw "Disposable Campaign fixture not found: $LoadSaveName" }
if (Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
. (Join-Path $PSScriptRoot 'Test-AgentSupport.ps1')

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorActionPreference
    if ($exitCode -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

function Capture-EngineFrame([string]$Path, [string]$Suffix) {
    $receipt = Invoke-AgentCli 'captureFrame' @('-OutputPath', $Path, '-CommandId', "$prefix-frame-$Suffix") 30
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path -LiteralPath $Path) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
    if ($receipt.status -ne 'completed' -or -not (Test-Path -LiteralPath $Path) -or (Get-Item -LiteralPath $Path).Length -lt 4096)
        { throw "Alley Scene-entry frame was not captured: $Path" }
}

try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $failedStep = 'load-disposable-campaign'
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $initial = Invoke-AgentCli 'state' @('-CommandId', "$prefix-initial")
    if ($initial.state.context.gameState -ne 'MapState' -or [bool]$initial.state.context.inquiryOpen -or [bool]$initial.state.context.escapeMenuOpen)
        { throw 'Fixture must start on a clear Campaign Map.' }
    $visible = Invoke-AgentCli 'mapSettlementTargets' @('-CommandId', "$prefix-visible-settlements")
    $target = @($visible.data.mapSettlementTargets | Where-Object { $_.id -eq $TargetSettlementId -and -not $_.hostile } | Select-Object -First 1)
    if ($target.Count -ne 1) { throw "Town '$TargetSettlementId' is not currently visible and nonhostile." }
    $move = Invoke-AgentCli 'move' @('-SettlementId', $TargetSettlementId, '-CommandId', "$prefix-move")
    if ($move.status -ne 'completed') { throw "Native map movement failed: $($move.error)" }
    $arrival = Wait-ForAgentSettlementArrival -CliPath $cli -SettlementId $TargetSettlementId -CommandPrefix "$prefix-arrival" -TimeoutSeconds $TimeoutSeconds
    if ($arrival.state.context.gameState -ne 'MapState' -or $arrival.state.location.currentSettlementId -ne $TargetSettlementId)
        { throw 'The Campaign Map Party did not reach the Town menu.' }

    $failedStep = 'prepare-player-Alley-and-Town-entry'
    $fixture = Invoke-AgentCli 'harnessPrepareAlleyRosterFixture' @('-SettlementId', $TargetSettlementId, '-MenuId', 'town', '-CommandId', "$prefix-fixture") 60
    if ($fixture.status -ne 'completed' -or $fixture.state.context.menuId -ne 'town')
        { throw 'Native player-Alley fixture did not leave the Campaign on its Town menu.' }
    $entryMenu = Invoke-AgentCli 'menu' @('-CommandId', "$prefix-town-menu")
    $walkOption = @($entryMenu.state.availableMenuOptions | Where-Object { $_.id -eq 'town_streets' -and $_.available -and $_.enabled } | Select-Object -First 1)
    if ($entryMenu.state.context.menuId -ne 'town' -or $walkOption.Count -ne 1)
        { throw "Native Town did not expose its enabled 'town_streets' option: $($entryMenu.state.availableMenuOptions | ConvertTo-Json -Depth 4 -Compress)" }
    $assignedHeroId = [string]$fixture.data.assignedHeroId
    $overlayCharacters = @($entryMenu.state.settlementOverlayCharacters)
    $assignedHeroOverlayEntry = @($overlayCharacters | Where-Object { $_.heroId -eq $assignedHeroId } | Select-Object -First 1)
    Capture-EngineFrame $frameTown 'town'

    $failedStep = 'enter-Native-Town-streets'
    $entryCommand = Invoke-AgentCli 'menuSelect' @('-MenuId', 'town', '-OptionId', 'town_streets', '-CommandId', "$prefix-town-streets") 60
    if ($entryCommand.status -ne 'completed' -or $entryCommand.state.context.gameState -ne 'MissionState')
        { throw "Native town_streets did not enter MissionState: $($entryCommand.state.context | ConvertTo-Json -Depth 5 -Compress)" }
    $entered = $entryCommand
    $missionReadyDeadline = [DateTime]::UtcNow.AddSeconds(60)
    while ((!$entered.state.mission -or !$entered.state.mission.mainAgent) -and [DateTime]::UtcNow -lt $missionReadyDeadline) {
        if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'The game process exited while the Town Streets Mission was loading.' }
        Start-Sleep -Milliseconds 500
        $entered = Invoke-AgentCli 'state' @('-CommandId', "$prefix-mission-ready-$([Guid]::NewGuid().ToString('N'))") 30
    }
    if (-not $entered.state.mission.mainAgent) { throw 'Town Streets entered MissionState, but the active MainAgent did not appear within 60 seconds.' }
    Start-Sleep -Seconds 3
    $entered = Invoke-AgentCli 'state' @('-CommandId', "$prefix-town-mission-stable") 30
    $nativeMissionDiagnostics = Invoke-AgentCli 'harnessMissionDiagnostics' @('-CommandId', "$prefix-native-mission-diagnostics") 30
    Capture-EngineFrame $frameMission 'town-streets'
    $nearbyAssignedHero = @($entered.state.mission.nearbySceneAgents | Where-Object { $_.characterId -eq $assignedHeroId } | Select-Object -First 1)
    $missionAssignedHero = @($nativeMissionDiagnostics.data.activeHeroAgents | Where-Object { $_.heroId -eq $assignedHeroId } | Select-Object -First 1)
    $walkSamples = [System.Collections.Generic.List[object]]::new()
    $walkStart = $entered.state.mission.mainAgent.position
    for ($step = 0; $step -lt 24; $step++) {
        $walkReceipt = Invoke-AgentCli 'missionInput' @('-X', '0', '-Y', '1', '-DurationSeconds', '0.5', '-CommandId', "$prefix-walk-$step") 30
        if ($walkReceipt.status -ne 'completed') { throw "Native bounded forward input failed at step ${step}: $($walkReceipt.error)" }
        $walkSamples.Add([ordered]@{ Step = $step + 1; ReceiptStatus = $walkReceipt.status })
        Start-Sleep -Milliseconds 150
    }
    Start-Sleep -Milliseconds 500
    $afterWalk = Invoke-AgentCli 'state' @('-CommandId', "$prefix-after-walk") 30
    $afterWalkDiagnostics = Invoke-AgentCli 'harnessMissionDiagnostics' @('-CommandId', "$prefix-after-walk-diagnostics") 30
    Capture-EngineFrame $frameAfterWalk 'after-walk'
    $approachState = $afterWalk
    $nearbyLeaderAfterWalk = @($approachState.state.mission.nearbySceneAgents | Where-Object { $_.characterId -eq $assignedHeroId } | Select-Object -First 1)
    $leaderAfterWalk = @($afterWalkDiagnostics.data.activeHeroAgents | Where-Object { $_.heroId -eq $assignedHeroId } | Select-Object -First 1)
    $approachSteps = 0
    $approachDeadline = [DateTime]::UtcNow.AddSeconds(20)
    while ($nearbyLeaderAfterWalk.Count -eq 1 -and [double]$nearbyLeaderAfterWalk[0].distance -gt 1.8 -and $approachSteps -lt 32 -and [DateTime]::UtcNow -lt $approachDeadline) {
        $mainAgent = $approachState.state.mission.mainAgent
        $forwardX = [double]$mainAgent.lookDirection.x
        $forwardY = [double]$mainAgent.lookDirection.y
        $forwardLength = [Math]::Sqrt($forwardX * $forwardX + $forwardY * $forwardY)
        if ($forwardLength -lt 0.01) { throw 'Town MainAgent look direction became degenerate during observed Alley leader approach.' }
        $forwardX /= $forwardLength
        $forwardY /= $forwardLength
        $deltaX = [double]$nearbyLeaderAfterWalk[0].position.x - [double]$mainAgent.position.x
        $deltaY = [double]$nearbyLeaderAfterWalk[0].position.y - [double]$mainAgent.position.y
        $axisX = ($deltaX * $forwardY) - ($deltaY * $forwardX)
        $axisY = ($deltaX * $forwardX) + ($deltaY * $forwardY)
        $axisLength = [Math]::Sqrt($axisX * $axisX + $axisY * $axisY)
        if ($axisLength -lt 0.01) { throw 'Observed Town Alley leader has no horizontal approach direction.' }
        $moveStep = Invoke-AgentCli 'missionInput' @('-X', [string]($axisX / $axisLength), '-Y', [string]($axisY / $axisLength), '-DurationSeconds', '0.35', '-CommandId', "$prefix-approach-$approachSteps")
        if ($moveStep.status -ne 'completed') { throw 'Native bounded Mission movement input was rejected during observed Alley leader approach.' }
        Start-Sleep -Milliseconds 300
        $approachState = Invoke-AgentCli 'state' @('-CommandId', "$prefix-approach-state-$approachSteps") 30
        $nearbyLeaderAfterWalk = @($approachState.state.mission.nearbySceneAgents | Where-Object { $_.characterId -eq $assignedHeroId } | Select-Object -First 1)
        $approachSteps++
    }
    $interaction = $null
    $afterInteraction = $approachState
    if ($nearbyLeaderAfterWalk.Count -eq 1 -and [double]$nearbyLeaderAfterWalk[0].distance -le 1.8) {
        $interaction = Invoke-AgentCli 'missionInteract' @('-AgentIndex', [string]$nearbyLeaderAfterWalk[0].agentIndex, '-CommandId', "$prefix-interact")
        $afterInteraction = Invoke-AgentCli 'state' @('-CommandId', "$prefix-after-interact") 30
        if ($interaction.status -eq 'completed' -and [bool]$interaction.data.conversationStarted) { Capture-EngineFrame $frameConversation 'conversation' }
    }
    $walkEnd = $afterWalk.state.mission.mainAgent.position
    $walkDistance = [Math]::Sqrt([Math]::Pow(([double]$walkEnd.x - [double]$walkStart.x), 2) + [Math]::Pow(([double]$walkEnd.y - [double]$walkStart.y), 2) + [Math]::Pow(([double]$walkEnd.z - [double]$walkStart.z), 2))
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-stop") 30
    $allProcessesStopped = -not [bool](Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue)
    $result = [ordered]@{
        ProviderKind = 'Native Town town_streets GameMenuOption after in-memory PlayerAlleyData fixture; mission result is observed, not assumed'
        ProcessId = $start.session.processId
        TownOption = $walkOption[0]
        Fixture = $fixture.data
        Transition = $entered.state.context
        SettlementOverlayCharacters = $overlayCharacters
        AssignedLeaderInSettlementOverlay = ($assignedHeroOverlayEntry.Count -eq 1)
        AssignedLeaderOverlayData = $assignedHeroOverlayEntry
        MissionState = $entered.state.mission
        NativeMissionDiagnostics = $nativeMissionDiagnostics.data
        AssignedLeaderId = $assignedHeroId
        AssignedLeaderInNearbyObservation = ($nearbyAssignedHero.Count -eq 1)
        AssignedLeaderNearbyData = $nearbyAssignedHero
        AssignedLeaderInMissionScene = ($missionAssignedHero.Count -eq 1)
        AssignedLeaderMissionData = $missionAssignedHero
        NativeMovementProbe = [ordered]@{ ProviderKind = 'Harness-only bounded Native forward exploration followed only by target-relative movement after the assigned Hero entered ordinary local observation'; Steps = @($walkSamples); DistanceMoved = [Math]::Round($walkDistance, 3); MainAgentAfterExploration = $afterWalk.state.mission.mainAgent; AssignedLeaderInNearbyObservation = ($nearbyLeaderAfterWalk.Count -eq 1); AssignedLeaderDistanceAfterExploration = if ($leaderAfterWalk.Count -eq 1) { $leaderAfterWalk[0].distance } else { $null }; AssignedLeaderNearbyData = $nearbyLeaderAfterWalk; ObservedTargetApproachSteps = $approachSteps; FinalApproachedTarget = if ($nearbyLeaderAfterWalk.Count -eq 1) { $nearbyLeaderAfterWalk[0] } else { $null }; InteractionReceipt = if ($interaction) { $interaction.data } else { $null }; Conversation = $afterInteraction.state.context.conversation }
        EngineFrames = @($frameTown, $frameMission, $frameAfterWalk) + $(if (Test-Path -LiteralPath $frameConversation) { @($frameConversation) } else { @() })
        SourceFixtureHashBefore = $fixtureHashBefore
        SourceFixtureHashAfter = $fixtureHashAfter
        SourceFixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = [bool]$stop.processStopped
        AllGameProcessesStopped = $allProcessesStopped
        ProbeSucceeded = ($entered.status -eq 'completed' -and $fixtureHashBefore -eq $fixtureHashAfter -and [bool]$stop.processStopped -and $allProcessesStopped)
    }
    $json = $result | ConvertTo-Json -Depth 16
    if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) { Set-Content -LiteralPath $resultPath -Value $json -Encoding UTF8 }
    $json
    if (-not $result.ProbeSucceeded) { exit 1 }
}
catch {
    $failureFrame = $null
    if (Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue) {
        try { $failureFrame = Capture-HarnessFailureFrame -CliPath $cli -CommandPrefix $prefix -FailedStep $failedStep -FailureReason $_.Exception.ToString() }
        catch { $failureFrame = [ordered]@{ Captured = $false; Error = $_.Exception.Message } }
    }
    if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) {
        [ordered]@{ FailedStep = $failedStep; Exception = $_.Exception.ToString(); FailureFrame = $failureFrame; TimestampUtc = [DateTime]::UtcNow.ToString('O') } |
            ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $tempPath 'AlleyLeaderSceneEntryFailure.json') -Encoding UTF8
    }
    throw
}
finally {
    if (Test-Path $sessionPath) {
        try { $session = Get-Content $sessionPath -Raw | ConvertFrom-Json; if ($session.status -ne 'stopped') { $null = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-final-stop") 30 } }
        catch { }
    }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
