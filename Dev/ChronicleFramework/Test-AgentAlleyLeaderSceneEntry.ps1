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
$frameAfterNavigation = Join-Path $frameRoot 'alley-leader-entry-after-navigation.bmp'
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
    $alleyBaseline = Invoke-AgentCli 'harnessAlleyRosterDiagnostics' @('-SettlementId', $TargetSettlementId, '-AlleyTag', [string]$fixture.data.alleyTag, '-CommandId', "$prefix-alley-baseline") 30
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
    $remoteNavigationRejectedWithoutSceneObservation = $null
    $initialAssignedLeader = if ($missionAssignedHero.Count -eq 1) { $missionAssignedHero[0] } else { $null }
    if ($initialAssignedLeader -and [double]$initialAssignedLeader.distance -gt 12.0) {
        $positionBeforeUnobservedNavigation = $entered.state.mission.mainAgent.position
        $unobservedNavigation = Invoke-AgentCli 'missionNavigateToAgent' @('-AgentIndex', [string]$initialAssignedLeader.agentIndex, '-DurationSeconds', '8', '-CommandId', "$prefix-reject-unobserved-remote") 30
        $positionAfterUnobservedNavigation = $unobservedNavigation.state.mission.mainAgent.position
        $remoteNavigationRejectedWithoutSceneObservation = ($unobservedNavigation.status -eq 'rejected' -and
            [double]$positionBeforeUnobservedNavigation.x -eq [double]$positionAfterUnobservedNavigation.x -and
            [double]$positionBeforeUnobservedNavigation.y -eq [double]$positionAfterUnobservedNavigation.y -and
            [double]$positionBeforeUnobservedNavigation.z -eq [double]$positionAfterUnobservedNavigation.z)
        if (-not $remoteNavigationRejectedWithoutSceneObservation) { throw 'Remote navigation succeeded without an ordinary local or explicit scene-level observation.' }
    }

    $failedStep = 'query-current-Location-Mission-scene-agents'
    $sceneObservation = Invoke-AgentCli 'missionSceneAgents' @('-CommandId', "$prefix-scene-agents") 30
    if ($sceneObservation.status -ne 'completed' -or -not $sceneObservation.data -or $sceneObservation.data.sceneName -ne $entered.state.mission.sceneName)
        { throw "Current Mission scene-agent query failed or reported a different scene: $($sceneObservation | ConvertTo-Json -Depth 5 -Compress)" }
    $assignedSceneAgent = @($sceneObservation.data.agents | Where-Object { $_.heroId -eq $assignedHeroId } | Select-Object -First 1)
    if ($assignedSceneAgent.Count -ne 1) { throw "Assigned Alley leader was in the Harness-only Mission census but missing from the Agent's current-scene observation: $($sceneObservation.data | ConvertTo-Json -Depth 5 -Compress)" }

    $navigationAttempts = [System.Collections.Generic.List[object]]::new()
    $navigationState = $sceneObservation
    $navigationError = $null
    $navigationLimit = 10
    for ($attempt = 0; $attempt -lt $navigationLimit -and [double]$assignedSceneAgent[0].distance -gt 1.8; $attempt++) {
        $failedStep = "native-navmesh-approach-$attempt"
        $navigationStart = $navigationState
        $distanceBefore = [double]$assignedSceneAgent[0].distance
        try {
            $navigationReceipt = Invoke-AgentCli 'missionNavigateToAgent' @('-AgentIndex', [string]$assignedSceneAgent[0].agentIndex, '-DurationSeconds', '20', '-CommandId', "$prefix-navigate-$attempt") 30
        }
        catch { $navigationError = $_.Exception.Message; break }
        if ($navigationReceipt.status -ne 'completed') { $navigationError = [string]$navigationReceipt.error; break }
        $navigationEnd = $navigationReceipt
        $navigationDeadline = [DateTime]::UtcNow.AddSeconds(23)
        while ([DateTime]::UtcNow -lt $navigationDeadline) {
            Start-Sleep -Milliseconds 750
            $navigationEnd = Invoke-AgentCli 'state' @('-CommandId', "$prefix-navigation-state-$attempt-$([Guid]::NewGuid().ToString('N'))") 30
            if (-not $navigationEnd.state.mission.navigation -or -not $navigationEnd.state.mission.navigation.active) { break }
        }
        $positionBefore = $navigationStart.state.mission.mainAgent.position
        $positionAfter = $navigationEnd.state.mission.mainAgent.position
        $movementDistance = [Math]::Sqrt([Math]::Pow(([double]$positionAfter.x - [double]$positionBefore.x), 2) + [Math]::Pow(([double]$positionAfter.y - [double]$positionBefore.y), 2) + [Math]::Pow(([double]$positionAfter.z - [double]$positionBefore.z), 2))
        $failedStep = "refresh-scene-agent-target-$attempt"
        $navigationState = Invoke-AgentCli 'missionSceneAgents' @('-CommandId', "$prefix-refresh-scene-agents-$attempt") 30
        if ($navigationState.status -ne 'completed' -or -not $navigationState.data) { $navigationError = 'Could not refresh the current Mission scene-agent observation after a navigation lease.'; break }
        $assignedSceneAgent = @($navigationState.data.agents | Where-Object { $_.heroId -eq $assignedHeroId } | Select-Object -First 1)
        $distanceAfter = if ($assignedSceneAgent.Count -eq 1) { [Math]::Round([double]$assignedSceneAgent[0].distance, 3) } else { $null }
        $navigationAttempts.Add([ordered]@{ Attempt = $attempt + 1; TargetAgentIndex = [int]$navigationReceipt.data.targetAgentIndex; DistanceBefore = [Math]::Round($distanceBefore, 3); DistanceAfter = $distanceAfter; MainAgentDistanceMoved = [Math]::Round($movementDistance, 3); Navigation = $navigationEnd.state.mission.navigation; ControllerRestored = [bool]$navigationEnd.state.mission.mainAgent.isPlayerControlled })
        if ($assignedSceneAgent.Count -ne 1) { $navigationError = 'Assigned Alley leader left the active Mission during navigation.'; break }
    }
    $afterNavigation = Invoke-AgentCli 'state' @('-CommandId', "$prefix-after-navigation") 30
    Capture-EngineFrame $frameAfterNavigation 'after-navigation'
    $nearbyLeaderAfterNavigation = @($afterNavigation.state.mission.nearbySceneAgents | Where-Object { $_.characterId -eq $assignedHeroId } | Select-Object -First 1)
    $interaction = $null
    $afterInteraction = $afterNavigation
    if ($nearbyLeaderAfterNavigation.Count -eq 1 -and [double]$nearbyLeaderAfterNavigation[0].distance -le 1.8) {
        $failedStep = 'start-native-Alley-leader-conversation'
        $interaction = Invoke-AgentCli 'missionInteract' @('-AgentIndex', [string]$nearbyLeaderAfterNavigation[0].agentIndex, '-CommandId', "$prefix-interact")
        $afterInteraction = Invoke-AgentCli 'state' @('-CommandId', "$prefix-after-interact") 30
        if ($interaction.status -eq 'completed' -and [bool]$interaction.data.conversationStarted) { Capture-EngineFrame $frameConversation 'conversation' }
    }
    $alleyAfter = Invoke-AgentCli 'harnessAlleyRosterDiagnostics' @('-SettlementId', $TargetSettlementId, '-AlleyTag', [string]$fixture.data.alleyTag, '-CommandId', "$prefix-alley-after") 30
    $alleyBusinessStable = ([bool]$alleyBaseline.data.playerAlleyDataPresent -eq [bool]$alleyAfter.data.playerAlleyDataPresent -and
        [string]$alleyBaseline.data.alleyOwnerId -eq [string]$alleyAfter.data.alleyOwnerId -and
        [string]$alleyBaseline.data.assignedHeroId -eq [string]$alleyAfter.data.assignedHeroId -and
        ($alleyBaseline.data.alleyRoster | ConvertTo-Json -Compress) -eq ($alleyAfter.data.alleyRoster | ConvertTo-Json -Compress) -and
        ($alleyBaseline.data.mainPartyRoster | ConvertTo-Json -Compress) -eq ($alleyAfter.data.mainPartyRoster | ConvertTo-Json -Compress) -and
        [int]$alleyBaseline.data.gold -eq [int]$alleyAfter.data.gold -and
        [double]$alleyBaseline.data.influence -eq [double]$alleyAfter.data.influence)
    $conversation = $afterInteraction.state.context.conversation
    $remoteTargetWasObserved = ($null -eq $initialAssignedLeader -or [double]$initialAssignedLeader.distance -le 12.0 -or [bool]$remoteNavigationRejectedWithoutSceneObservation)
    $conversationIdentityMatches = ($interaction -and $conversation -and
        $interaction.status -eq 'completed' -and [bool]$interaction.data.conversationStarted -and
        [string]$interaction.data.conversationHeroId -eq $assignedHeroId -and
        [string]$conversation.heroId -eq $assignedHeroId)
    $volunteerQuestionOption = @($conversation.options | Where-Object { $_.id -eq 'alley_talk_start_player_owned_alley_manager_answer_2' -and $_.clickable } | Select-Object -First 1)
    $campaignClockStable = ([double]$entered.campaignDay -eq [double]$afterInteraction.campaignDay -and
        [string]$entered.state.context.timeControlMode -eq 'Stop' -and
        [string]$afterInteraction.state.context.timeControlMode -eq 'Stop' -and
        [double]$alleyBaseline.data.campaignDay -eq [double]$alleyAfter.data.campaignDay -and
        [string]$alleyBaseline.data.timeControlMode -eq [string]$alleyAfter.data.timeControlMode -and
        [bool]$alleyBaseline.data.isWaiting -eq [bool]$alleyAfter.data.isWaiting)
    $navigationReachedLeader = ($assignedSceneAgent.Count -eq 1 -and [double]$assignedSceneAgent[0].distance -le 1.8 -and
        $nearbyLeaderAfterNavigation.Count -eq 1 -and [double]$nearbyLeaderAfterNavigation[0].distance -le 1.8)
    $conversationPathSucceeded = ([bool]$navigationReachedLeader -and [bool]$conversationIdentityMatches -and $volunteerQuestionOption.Count -eq 1)
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
        RemoteNavigationRejectedWithoutSceneObservation = $remoteNavigationRejectedWithoutSceneObservation
        RemoteTargetGuardVerified = [bool]$remoteTargetWasObserved
        MissionSceneAgentCount = @($sceneObservation.data.agents).Count
        SceneScope = [string]$sceneObservation.data.scope
        AssignedLeaderInSceneObservation = $assignedSceneAgent.Count -eq 1
        InitialAssignedLeaderSceneDistance = if ($missionAssignedHero.Count -eq 1) { [double]$missionAssignedHero[0].distance } else { $null }
        NativeSceneNavigation = [ordered]@{ ProviderKind = 'On-demand active Mission agent observation followed by fresh same-Mission target validation and native SandBox.AgentNavigator/NavMesh leases'; Attempts = @($navigationAttempts); Error = $navigationError; FinalAssignedLeaderDistance = if ($assignedSceneAgent.Count -eq 1) { [double]$assignedSceneAgent[0].distance } else { $null }; AssignedLeaderInNearbyObservation = ($nearbyLeaderAfterNavigation.Count -eq 1); NearbyLeader = $nearbyLeaderAfterNavigation; FinalMainAgent = $afterNavigation.state.mission.mainAgent; Conversation = $afterInteraction.state.context.conversation; InteractionReceipt = if ($interaction) { $interaction.data } else { $null } }
        ConversationPathSucceeded = [bool]$conversationPathSucceeded
        VolunteerQuestionOption = $volunteerQuestionOption
        AlleyBusinessStableBeforeAnyDialogueChoice = [bool]$alleyBusinessStable
        CampaignClockStable = [bool]$campaignClockStable
        AlleyBaseline = $alleyBaseline.data
        AlleyAfter = $alleyAfter.data
        EngineFrames = @($frameTown, $frameMission, $frameAfterNavigation) + $(if (Test-Path -LiteralPath $frameConversation) { @($frameConversation) } else { @() })
        SourceFixtureHashBefore = $fixtureHashBefore
        SourceFixtureHashAfter = $fixtureHashAfter
        SourceFixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = [bool]$stop.processStopped
        AllGameProcessesStopped = $allProcessesStopped
        ProbeSucceeded = ($entered.status -eq 'completed' -and [bool]$remoteTargetWasObserved -and [bool]$conversationPathSucceeded -and [bool]$alleyBusinessStable -and [bool]$campaignClockStable -and $fixtureHashBefore -eq $fixtureHashAfter -and [bool]$stop.processStopped -and $allProcessesStopped)
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
