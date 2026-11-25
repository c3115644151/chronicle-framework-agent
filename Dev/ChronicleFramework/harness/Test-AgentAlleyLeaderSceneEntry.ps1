#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [string]$TargetSettlementId = 'town_V1',
    [ValidateSet('natural','noVolunteers','availableVolunteers')][string]$VolunteerScenario = 'natural',
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$tempPath = $env:CHRONICLE_HARNESS_TEMP
$frameRoot = if ($tempPath) { $tempPath } else { Join-Path (Split-Path -Parent $PSScriptRoot) 'TestResults\ManualAlleyLeaderSceneEntry' }
$resultPath = if ($tempPath) { Join-Path $tempPath 'AlleyLeaderSceneEntryResult.json' } else { Join-Path $frameRoot 'AlleyLeaderSceneEntryResult.json' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$prefix = 'alley-leader-entry-' + (Get-Date -Format 'yyyyMMddHHmmssfff')
$failedStep = 'preflight'
$scenarioSuffix = if ($VolunteerScenario -eq 'natural') { '' } else { "-$VolunteerScenario" }
$resultFileName = if ($VolunteerScenario -eq 'natural') { 'AlleyLeaderSceneEntryResult.json' } else { "AlleyLeaderVolunteer-$VolunteerScenario-Result.json" }
$resultPath = if ($tempPath) { Join-Path $tempPath $resultFileName } else { Join-Path $frameRoot $resultFileName }
$frameTown = Join-Path $frameRoot "alley-leader-entry-town-menu$scenarioSuffix.bmp"
$frameMission = Join-Path $frameRoot "alley-leader-entry-town-streets$scenarioSuffix.bmp"
$frameAfterNavigation = Join-Path $frameRoot "alley-leader-entry-after-navigation$scenarioSuffix.bmp"
$frameConversation = Join-Path $frameRoot "alley-leader-entry-conversation$scenarioSuffix.bmp"
$frameVolunteerReply = Join-Path $frameRoot "alley-leader-volunteer-reply$scenarioSuffix.bmp"
$frameVolunteerDecline = Join-Path $frameRoot "alley-leader-volunteer-decline$scenarioSuffix.bmp"
$frameVolunteerAccepted = Join-Path $frameRoot "alley-leader-volunteer-accepted$scenarioSuffix.bmp"

if (-not (Test-Path -LiteralPath $savePath)) { throw "Disposable Campaign fixture not found: $LoadSaveName" }
if (Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
. (Join-Path $PSScriptRoot 'Test-AgentSupport.ps1')

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & $HarnessPowerShell -NoProfile -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
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

function Continue-AutomaticConversationNodes($Snapshot, [string]$Suffix) {
    $current = $Snapshot
    for ($index = 0; $index -lt 6 -and $current.state.context.conversation; $index++) {
        $clickableOptions = @($current.state.context.conversation.options | Where-Object { $_.clickable })
        if ($clickableOptions.Count -gt 0) { break }
        $continue = Invoke-AgentCli 'dialogueContinue' @('-CommandId', "$prefix-continue-$Suffix-$index") 30
        if ($continue.status -ne 'completed') { break }
        $current = $continue
    }
    return $current
}

function Test-AlleyBusinessStateUnchanged($Before, $After) {
    return ([bool]$Before.playerAlleyDataPresent -eq [bool]$After.playerAlleyDataPresent -and
        [string]$Before.alleyOwnerId -eq [string]$After.alleyOwnerId -and
        [string]$Before.assignedHeroId -eq [string]$After.assignedHeroId -and
        ($Before.alleyRoster | ConvertTo-Json -Compress) -eq ($After.alleyRoster | ConvertTo-Json -Compress) -and
        ($Before.mainPartyRoster | ConvertTo-Json -Compress) -eq ($After.mainPartyRoster | ConvertTo-Json -Compress) -and
        [int]$Before.gold -eq [int]$After.gold -and
        [double]$Before.influence -eq [double]$After.influence -and
        [double]$Before.lastRecruitDay -eq [double]$After.lastRecruitDay)
}

function Get-MainPartyRosterDelta($Before, $After) {
    $beforeCounts = @{}
    foreach ($item in @($Before.mainPartyRoster)) { $beforeCounts[[string]$item.troopId] = [int]$item.count }
    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($item in @($After.mainPartyRoster)) {
        $troopId = [string]$item.troopId
        $oldCount = if ($beforeCounts.ContainsKey($troopId)) { [int]$beforeCounts[$troopId] } else { 0 }
        $delta = [int]$item.count - $oldCount
        if ($delta -ne 0) { $result.Add([pscustomobject]@{ TroopId = $troopId; Before = $oldCount; After = [int]$item.count; Delta = $delta }) }
        $beforeCounts.Remove($troopId)
    }
    foreach ($troopId in @($beforeCounts.Keys)) { $result.Add([pscustomobject]@{ TroopId = [string]$troopId; Before = [int]$beforeCounts[$troopId]; After = 0; Delta = 0 - [int]$beforeCounts[$troopId] }) }
    return @($result)
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
    $fixture = Invoke-AgentCli 'harnessPrepareAlleyRosterFixture' @('-SettlementId', $TargetSettlementId, '-MenuId', 'town', '-AlleyVolunteerScenario', $VolunteerScenario, '-CommandId', "$prefix-fixture") 60
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
    $alleyAfterConversation = Invoke-AgentCli 'harnessAlleyRosterDiagnostics' @('-SettlementId', $TargetSettlementId, '-AlleyTag', [string]$fixture.data.alleyTag, '-CommandId', "$prefix-alley-after-conversation") 30
    $alleyBusinessStableBeforeAnyDialogueChoice = Test-AlleyBusinessStateUnchanged $alleyBaseline.data $alleyAfterConversation.data
    $conversation = $afterInteraction.state.context.conversation
    $remoteTargetWasObserved = ($null -eq $initialAssignedLeader -or [double]$initialAssignedLeader.distance -le 12.0 -or [bool]$remoteNavigationRejectedWithoutSceneObservation)
    $conversationIdentityMatches = ($interaction -and $conversation -and
        $interaction.status -eq 'completed' -and [bool]$interaction.data.conversationStarted -and
        [string]$interaction.data.conversationHeroId -eq $assignedHeroId -and
        [string]$conversation.heroId -eq $assignedHeroId)
    $volunteerQuestionOption = @($conversation.options | Where-Object { $_.id -eq 'alley_talk_start_player_owned_alley_manager_answer_2' -and $_.clickable } | Select-Object -First 1)
    $navigationReachedLeader = ($assignedSceneAgent.Count -eq 1 -and [double]$assignedSceneAgent[0].distance -le 1.8 -and
        $nearbyLeaderAfterNavigation.Count -eq 1 -and [double]$nearbyLeaderAfterNavigation[0].distance -le 1.8)
    $conversationPathSucceeded = ([bool]$navigationReachedLeader -and [bool]$conversationIdentityMatches -and $volunteerQuestionOption.Count -eq 1)

    $branchPassed = ($VolunteerScenario -eq 'natural')
    $branchEvidence = $null
    $rosterDelta = @()
    $alleyAfter = $alleyAfterConversation
    if ($VolunteerScenario -ne 'natural') {
        if (-not $conversationPathSucceeded) { throw 'A seeded volunteer branch cannot run until the Native Alley leader Conversation path is active and identity-matched.' }
        if ($VolunteerScenario -eq 'noVolunteers' -and [double]$fixture.data.weeklyRandomForFixture -ne 2.0) { throw 'The Native no-volunteer fixture did not use its within-week sentinel.' }
        if ($VolunteerScenario -eq 'availableVolunteers' -and [double]$fixture.data.weeklyRandomForFixture -ge 0.5) { throw 'The Native available-volunteer fixture did not seed a non-empty roster result.' }

        $failedStep = "select-volunteer-question-$VolunteerScenario"
        $askReceipt = Invoke-AgentCli 'dialogueSelect' @('-OptionId', 'alley_talk_start_player_owned_alley_manager_answer_2', '-CommandId', "$prefix-ask-volunteers")
        if ($askReceipt.status -ne 'completed') { throw "Native volunteer question option was not selected: $($askReceipt.error)" }
        $afterQuestion = Continue-AutomaticConversationNodes (Invoke-AgentCli 'state' @('-CommandId', "$prefix-after-volunteer-question") 30) 'volunteer-question'
        $questionConversation = $afterQuestion.state.context.conversation
        $questionText = [string]$questionConversation.sentenceText
        $questionOptions = @($questionConversation.options | Where-Object { $_.clickable })
        Capture-EngineFrame $frameVolunteerReply 'volunteer-reply'
        $alleyAfterQuestion = Invoke-AgentCli 'harnessAlleyRosterDiagnostics' @('-SettlementId', $TargetSettlementId, '-AlleyTag', [string]$fixture.data.alleyTag, '-CommandId', "$prefix-after-question-diagnostics") 30

        if ($VolunteerScenario -eq 'noVolunteers') {
            $noVolunteerReplyShown = -not [string]::IsNullOrWhiteSpace($questionText)
            $noRecruitmentConfirmationVisible = @($questionOptions | Where-Object { $_.id -in @('alley_talk_start_player_owned_alley_manager_volunteers_3','alley_talk_start_player_owned_alley_manager_volunteers_5') }).Count -gt 0
            $noVolunteerStateUnchanged = Test-AlleyBusinessStateUnchanged $alleyBaseline.data $alleyAfterQuestion.data
            $branchPassed = ([double]$fixture.data.weeklyRandomForFixture -eq 2.0 -and $noVolunteerReplyShown -and -not $noRecruitmentConfirmationVisible -and $noVolunteerStateUnchanged)
            $branchEvidence = [ordered]@{ Scenario = $VolunteerScenario; HarnessSeed = [double]$fixture.data.weeklyRandomForFixture; NativeReply = $questionText; CurrentClickableOptions = $questionOptions; NoRecruitmentConfirmationVisible = (-not $noRecruitmentConfirmationVisible); BusinessStateUnchanged = $noVolunteerStateUnchanged }
            $afterInteraction = $afterQuestion
            $alleyAfter = $alleyAfterQuestion
        }
        else {
            $yesOption = @($questionOptions | Where-Object { $_.id -eq 'alley_talk_start_player_owned_alley_manager_volunteers_3' } | Select-Object -First 1)
            $noNeedOption = @($questionOptions | Where-Object { $_.id -eq 'alley_talk_start_player_owned_alley_manager_volunteers_5' } | Select-Object -First 1)
            if ($yesOption.Count -ne 1 -or $noNeedOption.Count -ne 1) { throw "The Native available-volunteer branch did not expose both current Yes/No options: $($questionConversation | ConvertTo-Json -Depth 8 -Compress)" }

            $failedStep = 'decline-current-volunteers-without-mutating-roster'
            $declineReceipt = Invoke-AgentCli 'dialogueSelect' @('-OptionId', 'alley_talk_start_player_owned_alley_manager_volunteers_5', '-CommandId', "$prefix-decline-volunteers")
            if ($declineReceipt.status -ne 'completed') { throw "Native no-need option was not selected: $($declineReceipt.error)" }
            $afterDecline = Continue-AutomaticConversationNodes (Invoke-AgentCli 'state' @('-CommandId', "$prefix-after-decline") 30) 'after-decline'
            $alleyAfterDecline = Invoke-AgentCli 'harnessAlleyRosterDiagnostics' @('-SettlementId', $TargetSettlementId, '-AlleyTag', [string]$fixture.data.alleyTag, '-CommandId', "$prefix-after-decline-diagnostics") 30
            $declineStateUnchanged = Test-AlleyBusinessStateUnchanged $alleyBaseline.data $alleyAfterDecline.data
            Capture-EngineFrame $frameVolunteerDecline 'volunteer-decline'
            $askAgainOption = @($afterDecline.state.context.conversation.options | Where-Object { $_.id -eq 'alley_talk_start_player_owned_alley_manager_answer_2' -and $_.clickable } | Select-Object -First 1)
            if ($askAgainOption.Count -ne 1) { throw 'Native no-need branch did not return to the manager options with the volunteer question available.' }

            $failedStep = 'reobserve-volunteer-offer-after-decline'
            $askAgain = Invoke-AgentCli 'dialogueSelect' @('-OptionId', 'alley_talk_start_player_owned_alley_manager_answer_2', '-CommandId', "$prefix-reask-volunteers")
            $afterReask = Continue-AutomaticConversationNodes (Invoke-AgentCli 'state' @('-CommandId', "$prefix-after-reask") 30) 'after-reask'
            $reaskOptions = @($afterReask.state.context.conversation.options | Where-Object { $_.clickable })
            $reaskYesOption = @($reaskOptions | Where-Object { $_.id -eq 'alley_talk_start_player_owned_alley_manager_volunteers_3' } | Select-Object -First 1)
            if ($askAgain.status -ne 'completed' -or $reaskYesOption.Count -ne 1) { throw 'The same current Native volunteer offer was not visible after declining without mutation.' }
            $alleyBeforeAccept = Invoke-AgentCli 'harnessAlleyRosterDiagnostics' @('-SettlementId', $TargetSettlementId, '-AlleyTag', [string]$fixture.data.alleyTag, '-CommandId', "$prefix-before-accept-diagnostics") 30
            Capture-EngineFrame $frameVolunteerReply 'volunteer-reply-again'

            $failedStep = 'accept-current-Native-volunteer-offer'
            $acceptReceipt = Invoke-AgentCli 'dialogueSelect' @('-OptionId', 'alley_talk_start_player_owned_alley_manager_volunteers_3', '-CommandId', "$prefix-accept-volunteers")
            if ($acceptReceipt.status -ne 'completed') { throw "Native volunteer acceptance line was not selected: $($acceptReceipt.error)" }
            $afterAccept = Continue-AutomaticConversationNodes (Invoke-AgentCli 'state' @('-CommandId', "$prefix-after-accept") 30) 'after-accept'
            $alleyAfter = Invoke-AgentCli 'harnessAlleyRosterDiagnostics' @('-SettlementId', $TargetSettlementId, '-AlleyTag', [string]$fixture.data.alleyTag, '-CommandId', "$prefix-after-accept-diagnostics") 30
            $rosterDelta = Get-MainPartyRosterDelta $alleyBeforeAccept.data $alleyAfter.data
            $positiveRosterDeltas = @($rosterDelta | Where-Object { [int]$_.Delta -gt 0 })
            $addedCount = 0
            if ($positiveRosterDeltas.Count -gt 0) { $addedCount = [int]($positiveRosterDeltas | Measure-Object -Property Delta -Sum).Sum }
            $lastRecruitTimeUpdated = [Math]::Abs([double]$alleyAfter.data.lastRecruitDay - [double]$alleyAfter.data.campaignDay) -lt 0.001
            $goldInfluenceStable = ([int]$alleyBeforeAccept.data.gold -eq [int]$alleyAfter.data.gold -and [double]$alleyBeforeAccept.data.influence -eq [double]$alleyAfter.data.influence)
            $partySizeLimit = [int]$afterAccept.state.party.sizeLimit
            $partyMembersBeforeAccept = [int]$afterReask.state.party.members
            $partyMembersAfterAccept = [int]$afterAccept.state.party.members
            $overCapacityObserved = ($partyMembersBeforeAccept -eq ($partySizeLimit - 1) -and $partyMembersAfterAccept -gt $partySizeLimit -and -not [bool]$afterAccept.state.context.inquiryOpen)
            $branchPassed = ([double]$fixture.data.weeklyRandomForFixture -lt 0.5 -and $declineStateUnchanged -and $addedCount -gt 0 -and $lastRecruitTimeUpdated -and $goldInfluenceStable -and $overCapacityObserved)
            $branchEvidence = [ordered]@{ Scenario = $VolunteerScenario; HarnessSeed = [double]$fixture.data.weeklyRandomForFixture; NativeVolunteerOfferText = [string]$questionConversation.sentenceText; NoNeedOption = $noNeedOption[0]; DeclineStateUnchanged = $declineStateUnchanged; ReaskedAfterDecline = $askAgain.status -eq 'completed'; AcceptanceOption = $reaskYesOption[0]; AcceptReceipt = $acceptReceipt.data; MainPartyRosterDelta = @($rosterDelta); AddedTroopCount = [int]$addedCount; LastRecruitDayBefore = [double]$alleyBeforeAccept.data.lastRecruitDay; LastRecruitTimeUpdatedToCurrentCampaignDay = $lastRecruitTimeUpdated; GoldBefore = [int]$alleyBeforeAccept.data.gold; GoldAfter = [int]$alleyAfter.data.gold; InfluenceBefore = [double]$alleyBeforeAccept.data.influence; InfluenceAfter = [double]$alleyAfter.data.influence; GoldAndInfluenceUnchanged = $goldInfluenceStable; PartyMembersBeforeAccept = $partyMembersBeforeAccept; PartyMembersAfterAccept = $partyMembersAfterAccept; PartySizeLimit = $partySizeLimit; OverCapacityWithoutInquiry = $overCapacityObserved }
            $afterInteraction = $afterAccept
            Capture-EngineFrame $frameVolunteerAccepted 'volunteer-accepted'
        }
    }
    $conversationReturnSucceeded = $true
    if ($VolunteerScenario -ne 'natural') {
        $closeOption = @($afterInteraction.state.context.conversation.options | Where-Object { $_.id -eq 'alley_talk_start_player_owned_alley_manager_answer_5' -and $_.clickable } | Select-Object -First 1)
        if ($closeOption.Count -ne 1) { throw "The Native manager conversation had no current 'Never mind' return option: $($afterInteraction.state.context.conversation | ConvertTo-Json -Depth 6 -Compress)" }
        $closeConversationReceipt = Invoke-AgentCli 'dialogueSelect' @('-OptionId', 'alley_talk_start_player_owned_alley_manager_answer_5', '-CommandId', "$prefix-close-conversation")
        $afterInteraction = Invoke-AgentCli 'state' @('-CommandId', "$prefix-after-close-conversation") 30
        $conversationReturnSucceeded = ($closeConversationReceipt.status -eq 'completed' -and $afterInteraction.state.context.gameState -eq 'MissionState' -and $null -eq $afterInteraction.state.context.conversation)
    }
    $alleyAfter = Invoke-AgentCli 'harnessAlleyRosterDiagnostics' @('-SettlementId', $TargetSettlementId, '-AlleyTag', [string]$fixture.data.alleyTag, '-CommandId', "$prefix-alley-final") 30
    $alleyBusinessStable = Test-AlleyBusinessStateUnchanged $alleyBaseline.data $alleyAfter.data
    $campaignClockStable = ([double]$entered.campaignDay -eq [double]$afterInteraction.campaignDay -and
        [string]$entered.state.context.timeControlMode -eq 'Stop' -and
        [string]$afterInteraction.state.context.timeControlMode -eq 'Stop' -and
        [double]$alleyBaseline.data.campaignDay -eq [double]$alleyAfter.data.campaignDay -and
        [string]$alleyBaseline.data.timeControlMode -eq [string]$alleyAfter.data.timeControlMode -and
        [bool]$alleyBaseline.data.isWaiting -eq [bool]$alleyAfter.data.isWaiting)
    if ($VolunteerScenario -eq 'natural') { $branchPassed = $true }
    elseif ($VolunteerScenario -eq 'availableVolunteers') { $branchPassed = ([bool]$branchPassed -and [bool]$conversationReturnSucceeded) }
    else { $branchPassed = ([bool]$branchPassed -and [bool]$conversationReturnSucceeded) }
    $allNavigationControllersRestored = (@($navigationAttempts | Where-Object { -not [bool]$_.ControllerRestored }).Count -eq 0)
    $expectedAlleyOutcomePassed = if ($VolunteerScenario -eq 'availableVolunteers') { [bool]$branchPassed } else { ([bool]$branchPassed -and [bool]$alleyBusinessStable) }
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
        VolunteerScenario = $VolunteerScenario
        VolunteerBranchPassed = [bool]$branchPassed
        VolunteerBranchEvidence = $branchEvidence
        ConversationReturnedToMission = [bool]$conversationReturnSucceeded
        AlleyBusinessStableBeforeAnyDialogueChoice = [bool]$alleyBusinessStableBeforeAnyDialogueChoice
        FinalAlleyBusinessMatchesBaseline = [bool]$alleyBusinessStable
        MainPartyRosterDelta = @($rosterDelta)
        CampaignClockStable = [bool]$campaignClockStable
        AllNavigationControllersRestored = [bool]$allNavigationControllersRestored
        AlleyBaseline = $alleyBaseline.data
        AlleyAfter = $alleyAfter.data
        EngineFrames = @($frameTown, $frameMission, $frameAfterNavigation, $frameConversation, $frameVolunteerReply, $frameVolunteerDecline, $frameVolunteerAccepted) | Where-Object { Test-Path -LiteralPath $_ }
        SourceFixtureHashBefore = $fixtureHashBefore
        SourceFixtureHashAfter = $fixtureHashAfter
        SourceFixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = [bool]$stop.processStopped
        AllGameProcessesStopped = $allProcessesStopped
        ProbeSucceeded = ($entered.status -eq 'completed' -and [bool]$remoteTargetWasObserved -and [bool]$conversationPathSucceeded -and [bool]$alleyBusinessStableBeforeAnyDialogueChoice -and [bool]$expectedAlleyOutcomePassed -and [bool]$campaignClockStable -and [bool]$allNavigationControllersRestored -and $fixtureHashBefore -eq $fixtureHashAfter -and [bool]$stop.processStopped -and $allProcessesStopped)
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
