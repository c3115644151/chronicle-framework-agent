[CmdletBinding()]
param(
    [string]$SourceSaveName = 'AgentBridgeLifecycle',
    [ValidateRange(30,900)][int]$TimeoutSeconds = 300,
    [switch]$ProbeMainAgentAiController,
    [switch]$ProbeMainAgentRtsCameraBehavior,
    [switch]$ProbeBattleMovementInput,
    [switch]$ProbeBattleAgentNavigator
)

$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$saveRoot = [IO.Path]::GetFullPath((Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\Game Saves')).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($SourceSaveName -notmatch '^[A-Za-z0-9_-]{1,48}$') { throw 'Battle Mission formation probe requires one source save basename without a path or extension.' }
$sourceSavePath = [IO.Path]::GetFullPath((Join-Path $saveRoot ($SourceSaveName + '.sav')))
if (-not $sourceSavePath.StartsWith($saveRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Battle Mission source save path escaped the Game Saves directory.' }
if (-not (Test-Path -LiteralPath $sourceSavePath -PathType Leaf)) { throw "Battle Mission source save not found: $SourceSaveName" }
if (Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running; the probe will not disturb an existing session.' }

$sourceHashBefore = (Get-FileHash -LiteralPath $sourceSavePath -Algorithm SHA256).Hash
$disposableSaveName = 'ChronicleW7P-FormationProbe-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
$disposableSavePath = [IO.Path]::GetFullPath((Join-Path $saveRoot ($disposableSaveName + '.sav')))
if (-not $disposableSavePath.StartsWith($saveRoot, [StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $disposableSavePath)) { throw 'Unique disposable Battle Mission probe save path is invalid or already exists.' }
$disposableSaveHash = $null
$disposableSaveOwned = $false
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$priorMode = $env:CHRONICLE_HARNESS_MODE
$env:CHRONICLE_HARNESS_MODE = 'battle-fixture'
$prefix = 'battle-mission-formation-' + [Guid]::NewGuid().ToString('N')
$probeName = if ($ProbeBattleAgentNavigator) { 'BattleMissionAgentNavigatorProbe' } elseif ($ProbeBattleMovementInput) { 'BattleMissionMovementInputProbe' } elseif ($ProbeMainAgentRtsCameraBehavior) { 'BattleMissionRtsCameraProbe' } elseif ($ProbeMainAgentAiController) { 'BattleMissionControllerProbe' } else { 'BattleMissionFormationProbe' }
$runDirectory = if ($env:CHRONICLE_HARNESS_TEMP) { [IO.Path]::GetFullPath($env:CHRONICLE_HARNESS_TEMP) } else { Join-Path $PSScriptRoot ('TestResults\' + $probeName) }
New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null
$script:NativeReceipts = [System.Collections.Generic.List[object]]::new()
$script:ProcessId = $null
$nativeReceiptPath = Join-Path $runDirectory 'BattleMissionFormationProbe-NativeReceipts.jsonl'
[IO.File]::WriteAllText($nativeReceiptPath, '', [Text.UTF8Encoding]::new($false))

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @()) {
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli $Action @Arguments -TimeoutSeconds $TimeoutSeconds -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { $receipt = $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
    if ($script:ProcessId -and [int]$receipt.processId -ne $script:ProcessId) { throw "Agent CLI '$Action' switched Bannerlord process ids." }
    $script:NativeReceipts.Add([ordered]@{
        action = $Action
        commandId = [string]$receipt.commandId
        status = [string]$receipt.status
        gameState = [string]$receipt.state.context.gameState
        menuId = [string]$receipt.state.context.menuId
        missionMode = [string]$receipt.state.mission.mode
        missionEnded = [bool]$receipt.state.mission.missionEnded
        campaignDay = $receipt.campaignDay
        timeControlMode = [string]$receipt.timeControlMode
        mainAgentController = [string]$receipt.data.mainAgentControllerAfter
        error = [string]$receipt.error
    })
    $receiptLine = ($receipt | ConvertTo-Json -Depth 10 -Compress) + [Environment]::NewLine
    [IO.File]::AppendAllText($nativeReceiptPath, $receiptLine, [Text.UTF8Encoding]::new($false))
    return $receipt
}

function Invoke-AgentCliExpectedReject([string]$Action, [string[]]$Arguments, [string]$CommandId) {
    $responseRoot = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\responses'
    $rejectedPath = Join-Path $responseRoot ($CommandId + '.rejected.json')
    if (Test-Path -LiteralPath $rejectedPath) { Remove-Item -LiteralPath $rejectedPath }
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli $Action @Arguments -CommandId $CommandId -TimeoutSeconds $TimeoutSeconds -AsJson 2>&1 | Out-String
    $receipt = $null
    if ($LASTEXITCODE -eq 0) {
        try { $receipt = $output | ConvertFrom-Json } catch { throw "Native '$Action' returned invalid JSON for an expected rejection: $output" }
    }
    elseif (Test-Path -LiteralPath $rejectedPath -PathType Leaf) {
        $receipt = Get-Content -LiteralPath $rejectedPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    else { throw "Native '$Action' did not leave its expected rejected receipt: $output" }
    if ($receipt.status -ne 'rejected' -or $receipt.action -ne $Action) { throw "Native '$Action' returned an invalid rejection receipt." }
    $script:NativeReceipts.Add([ordered]@{ action = $Action; commandId = $CommandId; status = [string]$receipt.status; error = [string]$receipt.error })
    [IO.File]::AppendAllText($nativeReceiptPath, (($receipt | ConvertTo-Json -Depth 10 -Compress) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    return $receipt
}

function Get-FormationSnapshot($MissionStatus) {
    $mainAgent = $MissionStatus.data.mainAgent
    if ($null -eq $mainAgent) { throw 'Native Battle Mission status did not expose the current MainAgent.' }
    if ($null -eq $mainAgent.currentWatchState -or $null -eq $mainAgent.formation -or $null -eq $mainAgent.formation.hasPlayerControlledTroop -or
        $null -eq $mainAgent.formation.isPlayerTroopInFormation -or $null -eq $mainAgent.formation.hasActiveAiBehavior -or
        $null -eq $mainAgent.formation.PSObject.Properties['activeAiBehaviorType'] -or
        $null -eq $mainAgent.formation.PSObject.Properties['activeAiOrderType'] -or
        $null -eq $mainAgent.formation.PSObject.Properties['activeAiOrderTarget'] -or
        $null -eq $mainAgent.formation.PSObject.Properties['distanceToActiveAiOrderTarget']) {
        throw 'Native Battle Mission status did not expose the current MainAgent Formation AI behavior context.'
    }
    return [ordered]@{
        agentIndex = [int]$mainAgent.agentIndex
        controller = [string]$mainAgent.controller
        currentWatchState = [string]$mainAgent.currentWatchState
        isPlayerControlled = [bool]$mainAgent.isPlayerControlled
        health = [double]$mainAgent.health
        healthLimit = [double]$mainAgent.healthLimit
        isDetachedFromFormation = $mainAgent.isDetachedFromFormation
        formation = $mainAgent.formation
        formationHasPlayerControlledTroop = [bool]$mainAgent.formation.hasPlayerControlledTroop
        formationIsPlayerTroopInFormation = [bool]$mainAgent.formation.isPlayerTroopInFormation
        formationHasActiveAiBehavior = [bool]$mainAgent.formation.hasActiveAiBehavior
        formationActiveAiBehaviorType = [string]$mainAgent.formation.activeAiBehaviorType
        formationActiveAiOrderType = [string]$mainAgent.formation.activeAiOrderType
        formationActiveAiOrderTarget = $mainAgent.formation.activeAiOrderTarget
        formationDistanceToAiOrderTarget = $mainAgent.formation.distanceToActiveAiOrderTarget
        playerFormations = @($MissionStatus.data.playerTeam.formations | ForEach-Object {
            [ordered]@{ formationIndex = $_.formationIndex; unitCount = $_.unitCount; isAIControlled = $_.isAIControlled; isPlayerOwned = $_.isPlayerOwned; isSelected = $_.isSelected }
        })
        campaignDay = [double]$MissionStatus.campaignDay
        timeControlMode = [string]$MissionStatus.data.campaignTimeControlMode
    }
}

try {
    $loaded = Invoke-AgentCli 'load' @('-SaveName', $SourceSaveName)
    if ($loaded.status -ne 'completed' -or -not $loaded.session.processId) { throw 'Native disposable Campaign load did not complete.' }
    $script:ProcessId = [int]$loaded.session.processId
    $saveAs = Invoke-AgentCli 'save' @('-SaveName', $disposableSaveName)
    if ($saveAs.status -ne 'completed' -or -not (Test-Path -LiteralPath $disposableSavePath -PathType Leaf)) { throw 'Native SaveAs did not create the uniquely named disposable Battle Mission probe copy.' }
    $disposableSaveOwned = $true
    $disposableSaveHash = (Get-FileHash -LiteralPath $disposableSavePath -Algorithm SHA256).Hash
    $state = Invoke-AgentCli 'state' @('-CommandId', "$prefix-initial")
    $invalidDeploymentBefore = $state
    $invalidDeployment = Invoke-AgentCliExpectedReject 'missionFinishDeployment' @() "$prefix-map-deployment-reject"
    $invalidDeploymentAfter = Invoke-AgentCli 'state' @('-CommandId', "$prefix-after-map-deployment-reject")
    $invalidDeploymentNoMutation = $invalidDeploymentBefore.state.context.gameState -eq $invalidDeploymentAfter.state.context.gameState -and
        $invalidDeploymentBefore.campaignDay -eq $invalidDeploymentAfter.campaignDay -and
        $invalidDeploymentBefore.timeControlMode -eq $invalidDeploymentAfter.timeControlMode -and
        $invalidDeploymentBefore.state.party.members -eq $invalidDeploymentAfter.state.party.members -and
        $invalidDeploymentBefore.state.economy.gold -eq $invalidDeploymentAfter.state.economy.gold -and
        $invalidDeploymentBefore.state.economy.renown -eq $invalidDeploymentAfter.state.economy.renown
    if (-not $invalidDeploymentNoMutation) { throw 'The out-of-Mission deployment-finish rejection changed Campaign state, time, party, Gold, or Renown.' }
    $initialMenuId = [string]$state.state.context.menuId
    if ($state.state.context.gameState -eq 'MapState' -and $initialMenuId -and $initialMenuId -notin @('encounter','encounter_meeting','join_encounter')) {
        $leaveOption = @($state.state.availableMenuOptions | Where-Object { $_.available -and $_.enabled -and $_.isLeave } | Select-Object -First 1)
        if ($leaveOption.Count -ne 1) { throw "The disposable source opened map menu '$initialMenuId' without a current Native Leave option; the probe will not use screen coordinates." }
        $leave = Invoke-AgentCli 'menuSelect' @('-MenuId', $initialMenuId, '-OptionId', [string]$leaveOption[0].id, '-CommandId', "$prefix-leave-initial-location")
        if ($leave.status -ne 'completed') { throw "The current Native Leave option for '$initialMenuId' was not accepted." }
        $state = Invoke-AgentCli 'state' @('-CommandId', "$prefix-map-after-location-leave")
    }
    $encounteredPartyId = [string]$state.state.context.encounteredPartyId
    $encounterActive = [bool]$state.state.context.encounterActive
    if (-not $encounterActive) {
        $visibleTarget = @($state.state.nearbyParties | Where-Object { $_.hostile -and $_.type -eq 'bandit' } | Sort-Object distance | Select-Object -First 1)
        if ($visibleTarget.Count -ne 1) { throw 'The source Campaign has no currently visible hostile Bandit party; the disposable copy will be cleaned without pursuing or advancing time.' }
        $targetId = [string]$visibleTarget[0].id
        $pursue = Invoke-AgentCli 'pursue' @('-PartyId', $targetId, '-CommandId', "$prefix-pursue")
        if ($pursue.status -ne 'completed') { throw 'Native pursuit did not accept the exact current visible hostile party.' }
        $deadline = [DateTime]::UtcNow.AddSeconds([Math]::Min(60, $TimeoutSeconds))
        do {
            Start-Sleep -Milliseconds 500
            $state = Invoke-AgentCli 'state' @('-CommandId', "$prefix-map-observe-$([Guid]::NewGuid().ToString('N'))")
            $encounterActive = [bool]$state.state.context.encounterActive
            $encounteredPartyId = [string]$state.state.context.encounteredPartyId
        } while (-not $encounterActive -and [DateTime]::UtcNow -lt $deadline)
    }
    if (-not $encounterActive) { throw "The native pursuit did not reach a currently visible hostile Bandit before its bounded deadline; observed '$encounteredPartyId'." }
    $targetId = $encounteredPartyId

    $dialogueSteps = 0
    while ($dialogueSteps++ -lt 8) {
        $state = Invoke-AgentCli 'menu' @('-CommandId', "$prefix-encounter-menu-$dialogueSteps")
        if ($state.state.context.menuId -eq 'encounter') { break }
        $conversation = $state.state.context.conversation
        if ($null -eq $conversation) { throw "Encounter was interrupted by unsupported game state '$($state.state.context.gameState)' / '$($state.state.context.menuId)'." }
        $clickable = @($conversation.options | Where-Object { $_.clickable })
        if ($clickable.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$conversation.sentenceText)) {
            $state = Invoke-AgentCli 'dialogueContinue' @('-CommandId', "$prefix-continue-$dialogueSteps")
            continue
        }
        $fight = @($clickable | Where-Object { $_.id -in @('bandit_start_defender_1','common_encounter_ultimatum','common_bandit_surrender_declined') } | Select-Object -First 1)
        if ($fight.Count -ne 1) { throw "The current hostile dialogue has no supported direct-fight choice; observed ids: $(($clickable | ForEach-Object id) -join ',')." }
        $state = Invoke-AgentCli 'dialogueSelect' @('-OptionId', [string]$fight[0].id, '-CommandId', "$prefix-fight-dialogue-$dialogueSteps")
    }

    $encounterMenu = Invoke-AgentCli 'menu' @('-CommandId', "$prefix-final-menu")
    if ($encounterMenu.state.context.menuId -ne 'encounter') { throw "Expected Native encounter menu; found '$($encounterMenu.state.context.menuId)'." }
    $sendTroops = @($encounterMenu.state.availableMenuOptions | Where-Object { $_.id -eq 'str_order_attack' -and $_.available -and $_.enabled })
    $attack = @($encounterMenu.state.availableMenuOptions | Where-Object { $_.id -eq 'attack' -and $_.available -and $_.enabled })
    if ($attack.Count -ne 1 -or [int]$encounterMenu.state.party.healthy -lt 1) {
        throw "Native attack Mission probe is unavailable; SendTroops=$($sendTroops.Count), attack=$($attack.Count), healthy=$($encounterMenu.state.party.healthy), morale=$($encounterMenu.state.party.morale)."
    }
    $renownBefore = [double]$encounterMenu.state.economy.renown
    $goldBefore = [long]$encounterMenu.state.economy.gold
    $attackReceipt = Invoke-AgentCli 'menuSelect' @('-MenuId', 'encounter', '-OptionId', 'attack', '-CommandId', "$prefix-attack")
    if ($attackReceipt.status -ne 'completed') { throw 'The original Native attack menu handler did not complete.' }

    $missionDeadline = [DateTime]::UtcNow.AddSeconds([Math]::Min(45, $TimeoutSeconds))
    $missionState = $attackReceipt
    while ([DateTime]::UtcNow -lt $missionDeadline) {
        $missionState = Invoke-AgentCli 'state' @('-CommandId', "$prefix-mission-enter-$([Guid]::NewGuid().ToString('N'))")
        if ($missionState.state.context.gameState -eq 'MissionState' -and $missionState.state.mission.mode -in @('Deployment','Battle')) { break }
        Start-Sleep -Milliseconds 500
    }
    if ($missionState.state.context.gameState -ne 'MissionState' -or $missionState.state.mission.mode -notin @('Deployment','Battle')) {
        throw "The original Attack option did not reach a supported Battle Mission state; state='$($missionState.state.context.gameState)', mode='$($missionState.state.mission.mode)'."
    }

    $deploymentFinish = $null
    $deploymentTransitionPollCount = 0
    if ($missionState.state.mission.mode -eq 'Deployment') {
        $deploymentFinish = Invoke-AgentCli 'missionFinishDeployment' @('-CommandId', "$prefix-native-finish-deployment")
        if ($deploymentFinish.status -ne 'completed' -or $deploymentFinish.data.nativeHandler -ne 'OrderOfBattleVM.ExecuteBeginMission' -or
            $deploymentFinish.data.nativeDeploymentHandler -ne 'DeploymentHandler.FinishDeployment' -or $deploymentFinish.data.canStartMission -ne $true -or
            $deploymentFinish.data.modeBefore -ne 'Deployment' -or $deploymentFinish.data.timeControlModeBefore -ne 'Stop' -or
            $deploymentFinish.data.timeControlModeAfter -ne 'Stop') {
            throw 'Native DeploymentHandler.FinishDeployment did not verify its current Deployment/Stop preconditions and receipt.'
        }
    $duplicateDeploymentBefore = Invoke-AgentCli 'state' @('-CommandId', "$prefix-before-duplicate-deployment-finish")
    $duplicateDeployment = Invoke-AgentCliExpectedReject 'missionFinishDeployment' @() "$prefix-duplicate-deployment-finish"
    $duplicateDeploymentAfter = Invoke-AgentCli 'state' @('-CommandId', "$prefix-after-duplicate-deployment-finish")
    $duplicateDeploymentNoMutation = $duplicateDeploymentBefore.state.context.gameState -eq $duplicateDeploymentAfter.state.context.gameState -and
        $duplicateDeploymentBefore.state.mission.mode -eq $duplicateDeploymentAfter.state.mission.mode -and
        $duplicateDeploymentBefore.campaignDay -eq $duplicateDeploymentAfter.campaignDay -and
        $duplicateDeploymentBefore.timeControlMode -eq $duplicateDeploymentAfter.timeControlMode -and
        $duplicateDeploymentBefore.state.party.members -eq $duplicateDeploymentAfter.state.party.members -and
        $duplicateDeploymentBefore.state.economy.gold -eq $duplicateDeploymentAfter.state.economy.gold -and
        $duplicateDeploymentBefore.state.economy.renown -eq $duplicateDeploymentAfter.state.economy.renown
    if ($duplicateDeployment.status -ne 'rejected' -or -not $duplicateDeploymentNoMutation) { throw 'A duplicate Native deployment-finish request was not safely rejected without a second state change.' }
        $battleReadyDeadline = [DateTime]::UtcNow.AddSeconds([Math]::Min(30, $TimeoutSeconds))
        while ([DateTime]::UtcNow -lt $battleReadyDeadline) {
            $missionState = Invoke-AgentCli 'state' @('-CommandId', "$prefix-battle-ready-$([Guid]::NewGuid().ToString('N'))")
            $deploymentTransitionPollCount++
            if ($missionState.state.context.gameState -eq 'MissionState' -and $missionState.state.mission.mode -eq 'Battle') { break }
            if ($missionState.state.context.gameState -ne 'MissionState' -or $missionState.state.mission.missionEnded -or $missionState.state.context.inquiryOpen) {
                throw "Native FinishDeployment did not advance the same Mission to Battle safely; state='$($missionState.state.context.gameState)', mode='$($missionState.state.mission.mode)', inquiry=$($missionState.state.context.inquiryOpen)."
            }
            Start-Sleep -Milliseconds 500
        }
        if ($missionState.state.mission.mode -ne 'Battle') { throw 'Native FinishDeployment timed out before Battle mode appeared.' }
    }

    $statusBefore = Invoke-AgentCli 'battleMissionStatus' @('-CommandId', "$prefix-status-before")
    if ($statusBefore.data.supported -ne $true -or $statusBefore.data.missionMode -ne 'Battle') { throw "Battle Mission status rejected the expected field battle: $($statusBefore.data.reason)" }
    $mainAgentBefore = Get-FormationSnapshot $statusBefore
    if (-not $mainAgentBefore.isPlayerControlled) { throw 'MainAgent was not Player-controlled before F6-equivalent delegation.' }
    if ($statusBefore.data.playerTeam.formationCount -lt 1) { throw 'Native status exposed no current player Formation to delegate.' }

    $delegation = Invoke-AgentCli 'missionDelegateTroops' @('-CommandId', "$prefix-delegate")
    if ($delegation.status -ne 'completed' -or $delegation.data.allRequestedFormationsDelegated -ne $true -or
        $delegation.data.mainAgentStillPlayerControlled -ne $true -or $delegation.data.timeControlModeBefore -ne 'Stop' -or
        $delegation.data.timeControlModeAfter -ne 'Stop' -or [Math]::Abs([double]$delegation.data.campaignDayAfter - [double]$delegation.data.campaignDayBefore) -gt 0.000001) {
        throw 'Native F6-equivalent delegation failed to preserve current formations, MainAgent controller, and Campaign time.'
    }
    $statusAfter = Invoke-AgentCli 'battleMissionStatus' @('-CommandId', "$prefix-status-after")
    $mainAgentAfter = Get-FormationSnapshot $statusAfter

    $battleAgentNavigatorProbe = $null
    $battleAgentNavigatorSamples = [System.Collections.Generic.List[object]]::new()
    if ($ProbeBattleAgentNavigator) {
        $battleAgentNavigatorProbe = Invoke-AgentCli 'harnessBattleAgentNavigatorProbe' @('-DurationSeconds', '8', '-CommandId', "$prefix-battle-agent-navigator")
        if ($battleAgentNavigatorProbe.status -ne 'completed' -or $battleAgentNavigatorProbe.data.scope -ne 'harness-only' -or
            $battleAgentNavigatorProbe.data.controllerBefore -ne 'Player' -or $battleAgentNavigatorProbe.data.controllerAfter -ne 'AI' -or
            $battleAgentNavigatorProbe.data.timeControlModeBefore -ne 'Stop' -or $battleAgentNavigatorProbe.data.timeControlModeAfter -ne 'Stop' -or
            [Math]::Abs([double]$battleAgentNavigatorProbe.data.campaignDayAfter - [double]$battleAgentNavigatorProbe.data.campaignDayBefore) -gt 0.000001) {
            throw 'The bounded Battle AgentNavigator probe did not preserve the Campaign clock or switch MainAgent control under its guards.'
        }
        $navigatorProbeDeadline = [DateTime]::UtcNow.AddSeconds(6)
        $navigatorStillActive = $false
        $navigatorMissionStillActive = $true
        while ([DateTime]::UtcNow -lt $navigatorProbeDeadline) {
            Start-Sleep -Milliseconds 500
            $navigatorState = Invoke-AgentCli 'state' @('-CommandId', "$prefix-agent-navigator-state-$([Guid]::NewGuid().ToString('N'))")
            if ($navigatorState.state.context.gameState -ne 'MissionState' -or $navigatorState.state.mission.missionEnded) { $navigatorMissionStillActive = $false; break }
            $navigatorStatus = Invoke-AgentCli 'battleMissionStatus' @('-CommandId', "$prefix-agent-navigator-status-$([Guid]::NewGuid().ToString('N'))")
            if ($navigatorStatus.status -ne 'completed' -or $null -eq $navigatorStatus.data.mainAgent) { break }
            $navigatorLease = $navigatorStatus.data.agentNavigator
            $battleAgentNavigatorSamples.Add([ordered]@{
                controller = [string]$navigatorStatus.data.mainAgent.controller
                health = [double]$navigatorStatus.data.mainAgent.health
                position = $navigatorStatus.data.mainAgent.position
                navigator = $navigatorLease
            })
            $navigatorStillActive = $null -ne $navigatorLease -and $navigatorLease.active -eq $true
            if (-not $navigatorStillActive) { break }
        }
        if ($navigatorStillActive -and $navigatorMissionStillActive) {
            $cancelNavigator = Invoke-AgentCli 'missionCancelNavigation' @('-CommandId', "$prefix-agent-navigator-cancel")
            if ($cancelNavigator.status -ne 'completed') { throw 'Native battle AgentNavigator lease did not accept bounded cleanup.' }
        }
        $navigatorRestoredState = Invoke-AgentCli 'state' @('-CommandId', "$prefix-agent-navigator-restored-state")
        if ($navigatorRestoredState.state.context.gameState -eq 'MissionState' -and -not $navigatorRestoredState.state.mission.missionEnded) {
            $navigatorRestoredStatus = Invoke-AgentCli 'battleMissionStatus' @('-CommandId', "$prefix-agent-navigator-restored-status")
            if ($navigatorRestoredStatus.status -ne 'completed' -or $navigatorRestoredStatus.data.mainAgent.controller -ne 'Player') {
                throw 'Battle AgentNavigator did not restore Player control after bounded movement.'
            }
        }
    }

    $controllerProbe = $null
    $rtsCameraProbe = $null
    $battleMovementInputProbe = $null
    $controllerProbeRestore = $null
    $controllerProbeSamples = [System.Collections.Generic.List[object]]::new()
    $surrogateControllerProbe = $null
    $surrogateFormationAiRefresh = $null
    $surrogateMovementOrderRebind = $null
    $surrogateControllerProbeRestore = $null
    $surrogateControllerProbeSamples = [System.Collections.Generic.List[object]]::new()
    if ($ProbeMainAgentAiController) {
        $controllerProbe = Invoke-AgentCli 'harnessMainAgentAiControllerProbe' @('-DurationSeconds', '10', '-CommandId', "$prefix-main-agent-ai-probe")
        if ($controllerProbe.status -ne 'completed' -or $controllerProbe.data.scope -ne 'harness-only' -or
            $controllerProbe.data.controllerBefore -ne 'Player' -or $controllerProbe.data.controllerAfter -ne 'AI' -or
            $controllerProbe.data.timeControlModeBefore -ne 'Stop' -or $controllerProbe.data.timeControlModeAfter -ne 'Stop' -or
            [Math]::Abs([double]$controllerProbe.data.campaignDayAfter - [double]$controllerProbe.data.campaignDayBefore) -gt 0.000001) {
            throw 'The bounded Native MainAgent controller probe did not preserve the Campaign clock or switch Player-to-AI under its guards.'
        }
        if ($ProbeMainAgentRtsCameraBehavior) {
            $rtsCameraProbe = Invoke-AgentCli 'harnessMainAgentAiRtsCameraProbe' @('-CommandId', "$prefix-main-agent-rts-camera-ai")
            if ($rtsCameraProbe.status -ne 'completed' -or $rtsCameraProbe.data.scope -ne 'harness-only' -or
                $rtsCameraProbe.data.ownerController -ne 'AI' -or $rtsCameraProbe.data.nativeWatchStateAfter -ne 'Alarmed' -or
                $rtsCameraProbe.data.isPlayerTroopInFormationAfter -ne $false -or $rtsCameraProbe.data.orderType -ne 'Move' -or
                $rtsCameraProbe.data.campaignDayBefore -ne $rtsCameraProbe.data.campaignDayAfter -or
                $rtsCameraProbe.data.timeControlModeBefore -ne 'Stop' -or $rtsCameraProbe.data.timeControlModeAfter -ne 'Stop') {
                throw 'The Native RTSCamera-pattern MainAgent handoff did not preserve the Campaign clock and its guarded AI/Alarmed state.'
            }
        }

        $controllerProbeDeadline = [DateTime]::UtcNow.AddSeconds(12)
        while ([DateTime]::UtcNow -lt $controllerProbeDeadline) {
            Start-Sleep -Milliseconds 500
            $controllerProbeState = Invoke-AgentCli 'state' @('-CommandId', "$prefix-main-agent-ai-state-$([Guid]::NewGuid().ToString('N'))")
            if ($controllerProbeState.state.context.gameState -ne 'MissionState' -or $controllerProbeState.state.mission.missionEnded) { break }
            $controllerProbeStatus = Invoke-AgentCli 'battleMissionStatus' @('-CommandId', "$prefix-main-agent-ai-status-$([Guid]::NewGuid().ToString('N'))")
            if ($controllerProbeStatus.status -ne 'completed' -or $null -eq $controllerProbeStatus.data.mainAgent) { break }
            $hero = $controllerProbeStatus.data.mainAgent
            $controllerProbeSamples.Add([ordered]@{
                missionMode = [string]$controllerProbeStatus.data.missionMode
                controller = [string]$hero.controller
                currentWatchState = [string]$hero.currentWatchState
                health = [double]$hero.health
                position = $hero.position
                formation = $hero.formation
                isPlayerTroopInFormation = $hero.formation.isPlayerTroopInFormation
                lease = $controllerProbeStatus.data.mainAgentAiControllerProbe
            })
            if ($controllerProbeStatus.data.mainAgentAiControllerProbe.active -ne $true) { break }
        }
        $controllerProbeRestore = Invoke-AgentCli 'harnessRestoreMainAgentAiControllerProbe' @('-CommandId', "$prefix-main-agent-ai-restore")
        if ($controllerProbeRestore.status -ne 'completed' -or $controllerProbeRestore.data.restored -ne $true) {
            throw 'The bounded Native MainAgent controller probe failed to restore Player control.'
        }
        $restoredState = Invoke-AgentCli 'state' @('-CommandId', "$prefix-main-agent-ai-restored-state")
        if ($restoredState.state.context.gameState -eq 'MissionState' -and -not $restoredState.state.mission.missionEnded) {
            $restoredStatus = Invoke-AgentCli 'battleMissionStatus' @('-CommandId', "$prefix-main-agent-ai-restored-status")
            if ($restoredStatus.status -ne 'completed' -or $null -eq $restoredStatus.data.mainAgent -or
                $restoredStatus.data.mainAgent.controller -ne 'Player' -or $restoredStatus.data.mainAgent.isPlayerControlled -ne $true) {
                throw 'The current Battle Mission did not read back MainAgent as Player-controlled after the probe restore.'
            }
            if ($ProbeMainAgentRtsCameraBehavior -and
                ($restoredStatus.data.mainAgent.currentWatchState -ne $mainAgentBefore.currentWatchState -or
                 $restoredStatus.data.mainAgent.formation.isPlayerTroopInFormation -ne $mainAgentBefore.formationIsPlayerTroopInFormation)) {
                throw 'The RTSCamera-pattern probe did not restore the original MainAgent watch state and player-troop formation flag.'
            }
        }

    }
    if ($ProbeMainAgentAiController -and -not $ProbeMainAgentRtsCameraBehavior) {
        $surrogateControllerProbe = Invoke-AgentCli 'harnessMainAgentAiSurrogateControllerProbe' @('-DurationSeconds', '10', '-CommandId', "$prefix-main-agent-ai-surrogate-probe")
        if ($surrogateControllerProbe.status -ne 'completed' -or $surrogateControllerProbe.data.scope -ne 'harness-only' -or
            $surrogateControllerProbe.data.controllerBefore -ne 'Player' -or $surrogateControllerProbe.data.controllerAfter -ne 'AI' -or
            $surrogateControllerProbe.data.surrogateAgentIndex -eq $null -or
            $surrogateControllerProbe.data.missionMainAgentIndexAfter -eq $surrogateControllerProbe.data.originalMainAgentIndex -or
            $surrogateControllerProbe.data.surrogateControllerAfter -ne 'Player' -or
            $surrogateControllerProbe.data.timeControlModeBefore -ne 'Stop' -or $surrogateControllerProbe.data.timeControlModeAfter -ne 'Stop' -or
            [Math]::Abs([double]$surrogateControllerProbe.data.campaignDayAfter - [double]$surrogateControllerProbe.data.campaignDayBefore) -gt 0.000001) {
            throw 'The Native MainAgent surrogate probe did not hand temporary player control to a friendly Agent under the stopped Campaign clock.'
        }

        $surrogateProbeDeadline = [DateTime]::UtcNow.AddSeconds(12)
        while ([DateTime]::UtcNow -lt $surrogateProbeDeadline) {
            Start-Sleep -Milliseconds 500
            $surrogateProbeState = Invoke-AgentCli 'state' @('-CommandId', "$prefix-surrogate-state-$([Guid]::NewGuid().ToString('N'))")
            if ($surrogateProbeState.state.context.gameState -ne 'MissionState' -or $surrogateProbeState.state.mission.missionEnded) { break }
            $surrogateProbeStatus = Invoke-AgentCli 'battleMissionStatus' @('-CommandId', "$prefix-surrogate-status-$([Guid]::NewGuid().ToString('N'))")
            if ($surrogateProbeStatus.status -ne 'completed' -or $null -eq $surrogateProbeStatus.data.mainAgentAiControllerProbe.ownerPosition) { break }
            $probe = $surrogateProbeStatus.data.mainAgentAiControllerProbe
            $surrogateControllerProbeSamples.Add([ordered]@{
                missionMode = [string]$surrogateProbeStatus.data.missionMode
                missionMainAgentIndex = $probe.missionMainAgentIndex
                surrogateAgentIndex = $probe.surrogateAgentIndex
                ownerController = [string]$probe.ownerController
                health = [double]$probe.ownerHealth
                position = $probe.ownerPosition
                formationIndex = $probe.ownerFormationIndex
                hasActiveAiBehavior = $probe.ownerHasActiveAiBehavior
                activeAiBehaviorType = $probe.ownerActiveAiBehaviorType
                activeAiOrderType = $probe.ownerActiveAiOrderType
                activeAiOrderTarget = $probe.ownerActiveAiOrderTarget
                distanceToAiOrderTarget = $probe.ownerDistanceToAiOrderTarget
                phase = if ($null -eq $surrogateFormationAiRefresh) { 'before-formation-refresh' } elseif ($null -eq $surrogateMovementOrderRebind) { 'after-formation-refresh' } else { 'after-movement-order-rebind' }
                lease = $probe
            })
            if ($null -eq $surrogateFormationAiRefresh -and $surrogateControllerProbeSamples.Count -ge 2) {
                $surrogateFormationAiRefresh = Invoke-AgentCli 'harnessRefreshMainAgentFormationAiProbe' @('-CommandId', "$prefix-surrogate-formation-ai-refresh")
                if ($surrogateFormationAiRefresh.status -ne 'completed' -or
                    $surrogateFormationAiRefresh.data.isAIControlledBefore -ne $true -or $surrogateFormationAiRefresh.data.isAIControlledAfter -ne $true -or
                    $surrogateFormationAiRefresh.data.campaignDayBefore -ne $surrogateFormationAiRefresh.data.campaignDayAfter -or
                    $surrogateFormationAiRefresh.data.timeControlModeBefore -ne 'Stop' -or $surrogateFormationAiRefresh.data.timeControlModeAfter -ne 'Stop') {
                    throw 'Native Formation AI refresh did not preserve AI control and the stopped Campaign clock.'
                }
                $surrogateMovementOrderRebind = Invoke-AgentCli 'harnessNotifyMainAgentAiMovementOrderProbe' @('-CommandId', "$prefix-surrogate-movement-order-rebind")
                if ($surrogateMovementOrderRebind.status -ne 'completed' -or
                    $surrogateMovementOrderRebind.data.controller -ne 'AI' -or
                    $surrogateMovementOrderRebind.data.orderTypeBefore -ne 'Move' -or $surrogateMovementOrderRebind.data.orderTypeAfter -ne 'Move' -or
                    $surrogateMovementOrderRebind.data.campaignDayBefore -ne $surrogateMovementOrderRebind.data.campaignDayAfter -or
                    $surrogateMovementOrderRebind.data.timeControlModeBefore -ne 'Stop' -or $surrogateMovementOrderRebind.data.timeControlModeAfter -ne 'Stop') {
                    throw 'Native MovementOrder membership notification did not preserve the current Move order and stopped Campaign clock.'
                }
            }
            if ($probe.active -ne $true) { break }
        }
        $surrogateControllerProbeRestore = Invoke-AgentCli 'harnessRestoreMainAgentAiControllerProbe' @('-CommandId', "$prefix-surrogate-restore")
        if ($surrogateControllerProbeRestore.status -ne 'completed' -or $surrogateControllerProbeRestore.data.restored -ne $true -or
            $surrogateControllerProbeRestore.data.ownerControllerAfter -ne 'Player' -or
            $surrogateControllerProbeRestore.data.surrogateControllerAfter -ne 'AI' -or
            $surrogateControllerProbeRestore.data.missionMainAgentIndexAfter -ne $mainAgentBefore.agentIndex) {
            throw 'The Native MainAgent surrogate probe failed to restore MainHero, the friendly Agent controller, and original Mission.MainAgent.'
        }
        $surrogateRestoredState = Invoke-AgentCli 'state' @('-CommandId', "$prefix-surrogate-restored-state")
        if ($surrogateRestoredState.state.context.gameState -eq 'MissionState' -and -not $surrogateRestoredState.state.mission.missionEnded) {
            $surrogateRestoredStatus = Invoke-AgentCli 'battleMissionStatus' @('-CommandId', "$prefix-surrogate-restored-status")
            if ($surrogateRestoredStatus.status -ne 'completed' -or $surrogateRestoredStatus.data.mainAgent.agentIndex -ne $mainAgentBefore.agentIndex -or
                $surrogateRestoredStatus.data.mainAgent.controller -ne 'Player') {
                throw 'Native battle status did not restore MainHero as Mission.MainAgent after the surrogate probe.'
            }
        }
    }

    if ($ProbeBattleMovementInput) {
        $movementProbeBefore = $statusAfter.data.mainAgent.position
        $movementProbeDayBefore = [double]$statusAfter.campaignDay
        $movementProbeModeBefore = [string]$statusAfter.data.campaignTimeControlMode
        $battleMovementInputProbe = Invoke-AgentCli 'harnessBattleMovementInputProbe' @('-X', '0', '-Y', '-1', '-DurationSeconds', '0.5', '-CommandId', "$prefix-battle-movement-input")
        if ($battleMovementInputProbe.status -ne 'completed' -or $battleMovementInputProbe.data.scope -ne 'harness-only' -or
            $battleMovementInputProbe.data.mainAgentController -ne 'Player' -or $battleMovementInputProbe.data.timeControlModeBefore -ne 'Stop' -or
            $battleMovementInputProbe.data.timeControlModeAfter -ne 'Stop' -or [Math]::Abs([double]$battleMovementInputProbe.data.campaignDayAfter - $movementProbeDayBefore) -gt 0.001) {
            throw 'The battle movement input probe did not preserve Player control and Campaign time under its field-Battle guards.'
        }
        Start-Sleep -Milliseconds 750
        $movementProbeStateAfter = Invoke-AgentCli 'state' @('-CommandId', "$prefix-battle-movement-input-after")
        $movementProbeStatusAfter = $null
        $movementProbePositionAfter = $null
        if ($movementProbeStateAfter.state.context.gameState -eq 'MissionState' -and -not $movementProbeStateAfter.state.mission.missionEnded) {
            $movementProbeStatusAfter = Invoke-AgentCli 'battleMissionStatus' @('-CommandId', "$prefix-battle-movement-input-status-after")
            if ($movementProbeStatusAfter.status -eq 'completed' -and $movementProbeStatusAfter.data.mainAgent) {
                $movementProbePositionAfter = $movementProbeStatusAfter.data.mainAgent.position
            }
        }
        $movementProbeDistance = $null
        if ($null -ne $movementProbePositionAfter) {
            $dx = [double]$movementProbePositionAfter.x - [double]$movementProbeBefore.x
            $dy = [double]$movementProbePositionAfter.y - [double]$movementProbeBefore.y
            $dz = [double]$movementProbePositionAfter.z - [double]$movementProbeBefore.z
            $movementProbeDistance = [Math]::Sqrt($dx * $dx + $dy * $dy + $dz * $dz)
        }
        $battleMovementInputProbe = [ordered]@{
            request = $battleMovementInputProbe.data
            campaignDayBefore = $movementProbeDayBefore
            campaignDayAfter = [double]$movementProbeStateAfter.campaignDay
            timeControlModeBefore = $movementProbeModeBefore
            timeControlModeAfter = [string]$movementProbeStateAfter.timeControlMode
            positionBefore = $movementProbeBefore
            positionAfter = $movementProbePositionAfter
            distanceMoved = $movementProbeDistance
            movementObserved = ($null -ne $movementProbeDistance -and $movementProbeDistance -gt 0.05)
            missionEndedBeforeReadback = [bool]$movementProbeStateAfter.state.mission.missionEnded
        }
        if ($battleMovementInputProbe.campaignDayAfter -ne $movementProbeDayBefore -or $battleMovementInputProbe.timeControlModeAfter -ne 'Stop') {
            throw 'The bounded battle movement input changed Campaign time or mode.'
        }
    }

    $missionEnded = $false
    $healthSamples = [System.Collections.Generic.List[double]]::new()
    $positionSamples = [System.Collections.Generic.List[object]]::new()
    $battleDeadline = [DateTime]::UtcNow.AddSeconds([Math]::Min(900, $TimeoutSeconds))
    while ([DateTime]::UtcNow -lt $battleDeadline) {
        $state = Invoke-AgentCli 'state' @('-CommandId', "$prefix-mission-watch-$([Guid]::NewGuid().ToString('N'))")
        if ($state.state.context.gameState -ne 'MissionState') { break }
        if ($state.state.mission.missionEnded) { $missionEnded = $true; break }
        $currentStatus = Invoke-AgentCli 'battleMissionStatus' @('-CommandId', "$prefix-status-watch-$([Guid]::NewGuid().ToString('N'))")
        if ($currentStatus.status -ne 'completed' -or $currentStatus.data.supported -ne $true) {
            $latestMissionState = Invoke-AgentCli 'state' @('-CommandId', "$prefix-after-status-boundary-$([Guid]::NewGuid().ToString('N'))")
            if ($latestMissionState.state.context.gameState -eq 'MissionState' -and $latestMissionState.state.mission.missionEnded) {
                $missionEnded = $true
                break
            }
            throw 'The supported Battle Mission status stopped being readable before the Native Mission ended.'
        }
        $currentHero = $currentStatus.data.mainAgent
        if ($null -ne $currentHero.health) { $healthSamples.Add([double]$currentHero.health) }
        $positionSamples.Add($currentHero.position)
        if ($currentStatus.data.campaignTimeControlMode -ne 'Stop') { throw 'Campaign time mode changed during the passive delegated Mission probe.' }
        Start-Sleep -Seconds 1
    }
    if (-not $missionEnded) { throw 'The delegated Battle Mission did not report MissionEnded within the bounded probe window.' }
    $missionEndedState = Invoke-AgentCli 'state' @('-CommandId', "$prefix-mission-ended")
    $exit = Invoke-AgentCli 'missionRetreat' @('-CommandId', "$prefix-native-battle-end-exit")
    if ($exit.status -ne 'completed') { throw 'Native BattleEnd Mission exit did not accept the ended Mission.' }
    $campaignReturn = $exit
    $returnDeadline = [DateTime]::UtcNow.AddSeconds([Math]::Min(45, $TimeoutSeconds))
    while ([DateTime]::UtcNow -lt $returnDeadline -and $campaignReturn.state.context.gameState -eq 'MissionState') {
        Start-Sleep -Milliseconds 250
        $campaignReturn = Invoke-AgentCli 'state' @('-CommandId', "$prefix-aftermath-$([Guid]::NewGuid().ToString('N'))")
    }
    if ($campaignReturn.state.context.gameState -eq 'MissionState') { throw 'Native BattleEnd did not return out of MissionState.' }

    $stop = Invoke-AgentCli 'stop'
    $sourceHashAfter = (Get-FileHash -LiteralPath $sourceSavePath -Algorithm SHA256).Hash
    $disposableSaveHashAfter = (Get-FileHash -LiteralPath $disposableSavePath -Algorithm SHA256).Hash
    $disposableSaveRemoved = $false
    if ($disposableSaveOwned -and $disposableSaveHashAfter -eq $disposableSaveHash) {
        Remove-Item -LiteralPath $disposableSavePath
        $disposableSaveRemoved = -not (Test-Path -LiteralPath $disposableSavePath)
    }
    $finalParty = $campaignReturn.state.party
    $result = [ordered]@{
        runId = $probeName
        scenario = 'native-only-no-model-engine-control-probe'
        modelCalls = 0
        nativeCommands = $script:NativeReceipts.Count
        mapStateDeploymentFinishRejected = ($invalidDeployment.status -eq 'rejected')
        mapStateDeploymentFinishPreservedState = $invalidDeploymentNoMutation
        sourceSaveName = $SourceSaveName
        sourceSaveHashBefore = $sourceHashBefore
        sourceSaveHashAfter = $sourceHashAfter
        sourceSaveUnchanged = ($sourceHashBefore -eq $sourceHashAfter)
        disposableSaveName = $disposableSaveName
        disposableSaveHashBeforeTest = $disposableSaveHash
        disposableSaveHashAfterTest = $disposableSaveHashAfter
        disposableSaveRemoved = $disposableSaveRemoved
        processStopped = [bool]$stop.processStopped
        initialParty = [ordered]@{ members = $encounterMenu.state.party.members; healthy = $encounterMenu.state.party.healthy; wounded = $encounterMenu.state.party.wounded; morale = $encounterMenu.state.party.morale }
        opponentPartyId = $targetId
        sendTroopsWasUnavailable = ($sendTroops.Count -eq 0)
        hostFallbackEligible = ($sendTroops.Count -eq 0)
        nativeAttackWasAvailable = ($attack.Count -eq 1)
        mainAgentFormationBeforeDelegate = $mainAgentBefore
        mainAgentFormationAfterDelegate = $mainAgentAfter
        mainAgentFormationAiBehavior = $mainAgentAfter.formation
        delegation = $delegation.data
        mainAgentAiControllerProbe = if ($controllerProbe) { $controllerProbe.data } else { $null }
        mainAgentAiRtsCameraProbe = if ($rtsCameraProbe) { $rtsCameraProbe.data } else { $null }
        battleMovementInputProbe = $battleMovementInputProbe
        battleAgentNavigatorProbe = if ($battleAgentNavigatorProbe) { $battleAgentNavigatorProbe.data } else { $null }
        battleAgentNavigatorSamples = $battleAgentNavigatorSamples.ToArray()
        mainAgentMovedDuringBattleNavigator = if ($battleAgentNavigatorSamples.Count -gt 1) {
            $navigatorStart = $battleAgentNavigatorSamples[0].position
            @($battleAgentNavigatorSamples | Where-Object {
                $dx = [double]$_.position.x - [double]$navigatorStart.x
                $dy = [double]$_.position.y - [double]$navigatorStart.y
                $dz = [double]$_.position.z - [double]$navigatorStart.z
                [Math]::Sqrt($dx * $dx + $dy * $dy + $dz * $dz) -gt 0.1
            }).Count -gt 0
        } else { $null }
        mainAgentAiControllerProbeSamples = $controllerProbeSamples.ToArray()
        mainAgentAiFormationBehaviorPresenceSamples = @($controllerProbeSamples | ForEach-Object { $_.formation.hasActiveAiBehavior } | Sort-Object -Unique)
        mainAgentAiFormationBehaviorTypes = @($controllerProbeSamples | ForEach-Object { $_.formation.activeAiBehaviorType } | Sort-Object -Unique)
        mainAgentAiFormationOrderTypes = @($controllerProbeSamples | ForEach-Object { $_.formation.activeAiOrderType } | Sort-Object -Unique)
        mainAgentAiFormationOrderTargets = @($controllerProbeSamples | ForEach-Object { $_.formation.activeAiOrderTarget } | Sort-Object -Unique)
        mainAgentAiFormationDistancesToOrderTarget = @($controllerProbeSamples | ForEach-Object { $_.formation.distanceToActiveAiOrderTarget } | Sort-Object -Unique)
        mainAgentAiSurrogateControllerProbe = if ($surrogateControllerProbe) { $surrogateControllerProbe.data } else { $null }
        mainAgentAiSurrogateControllerProbeSamples = $surrogateControllerProbeSamples.ToArray()
        mainAgentAiSurrogateFormationRefresh = if ($surrogateFormationAiRefresh) { $surrogateFormationAiRefresh.data } else { $null }
        mainAgentAiSurrogateMovementOrderRebind = if ($surrogateMovementOrderRebind) { $surrogateMovementOrderRebind.data } else { $null }
        mainAgentAiSurrogateControllerProbeRestore = if ($surrogateControllerProbeRestore) { $surrogateControllerProbeRestore.data } else { $null }
        mainHeroMovedAfterMovementOrderRebind = if ($surrogateMovementOrderRebind -and @($surrogateControllerProbeSamples | Where-Object phase -eq 'after-movement-order-rebind').Count -gt 1) {
            $postRebindSamples = @($surrogateControllerProbeSamples | Where-Object phase -eq 'after-movement-order-rebind')
            $initialPostRebindPosition = $postRebindSamples[0].position
            @($postRebindSamples | Where-Object {
                $dx = [double]$_.position.x - [double]$initialPostRebindPosition.x
                $dy = [double]$_.position.y - [double]$initialPostRebindPosition.y
                $dz = [double]$_.position.z - [double]$initialPostRebindPosition.z
                [Math]::Sqrt($dx * $dx + $dy * $dy + $dz * $dz) -gt 0.1
            }).Count -gt 0
        } else { $null }
        mainAgentMovedWhileNonMissionMainAgent = if ($surrogateControllerProbeSamples.Count -gt 1) {
            $initialSurrogateProbePosition = $surrogateControllerProbeSamples[0].position
            @($surrogateControllerProbeSamples | Where-Object {
                $dx = [double]$_.position.x - [double]$initialSurrogateProbePosition.x
                $dy = [double]$_.position.y - [double]$initialSurrogateProbePosition.y
                $dz = [double]$_.position.z - [double]$initialSurrogateProbePosition.z
                [Math]::Sqrt($dx * $dx + $dy * $dy + $dz * $dz) -gt 0.1
            }).Count -gt 0
        } else { $null }
        mainAgentAiControllerProbeRestore = if ($controllerProbeRestore) { $controllerProbeRestore.data } else { $null }
        mainAgentPositionChangedWhileAiControlled = if ($controllerProbeSamples.Count -gt 1) {
            $initialPosition = $controllerProbeSamples[0].position
            @($controllerProbeSamples | Where-Object {
                $dx = [double]$_.position.x - [double]$initialPosition.x
                $dy = [double]$_.position.y - [double]$initialPosition.y
                $dz = [double]$_.position.z - [double]$initialPosition.z
                [Math]::Sqrt($dx * $dx + $dy * $dy + $dz * $dz) -gt 0.1
            }).Count -gt 0
        } else { $null }
        deploymentFinish = if ($deploymentFinish) { $deploymentFinish.data } else { $null }
        deploymentTransitionPollCount = $deploymentTransitionPollCount
        duplicateDeploymentFinishRejected = ($duplicateDeployment.status -eq 'rejected')
        duplicateDeploymentFinishPreservedState = $duplicateDeploymentNoMutation
        mainAgentHealthSamples = $healthSamples.ToArray()
        mainAgentPositionSamples = $positionSamples.ToArray()
        missionEnded = $missionEnded
        missionExit = $exit.data
        postBattleGameState = [string]$campaignReturn.state.context.gameState
        postBattlePartyScreenMode = [string]$campaignReturn.state.partyScreen.mode
        mainPartyAfter = if ($finalParty) { [ordered]@{ members = $finalParty.members; healthy = $finalParty.healthy; wounded = $finalParty.wounded; prisoners = $finalParty.prisoners } } else { $null }
        renownBefore = $renownBefore
        renownAfter = [double]$campaignReturn.state.economy.renown
        goldBefore = $goldBefore
        goldAfter = [long]$campaignReturn.state.economy.gold
        nativeReceipts = $script:NativeReceipts.ToArray()
    }
    $result['passed'] = $result.mapStateDeploymentFinishRejected -and $result.mapStateDeploymentFinishPreservedState -and
        $result.duplicateDeploymentFinishRejected -and $result.duplicateDeploymentFinishPreservedState -and
        $result.sourceSaveUnchanged -and $result.disposableSaveRemoved -and $result.processStopped -and $result.missionEnded -and $result.postBattleGameState -ne 'MissionState'
    $json = ConvertTo-Json -InputObject $result -Depth 10
    [IO.File]::WriteAllText((Join-Path $runDirectory ($probeName + '.json')), $json, [Text.UTF8Encoding]::new($false))
    $json
    if (-not $result.passed) { exit 1 }
}
finally {
    if ($null -eq $priorMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $priorMode }
    if (Test-Path -LiteralPath $sessionPath) { try { Invoke-AgentCli 'stop' | Out-Null } catch { } }
    if ($disposableSaveOwned -and (Test-Path -LiteralPath $disposableSavePath -PathType Leaf) -and $null -ne $disposableSaveHash) {
        $currentDisposableHash = (Get-FileHash -LiteralPath $disposableSavePath -Algorithm SHA256).Hash
        if ($currentDisposableHash -eq $disposableSaveHash) { Remove-Item -LiteralPath $disposableSavePath }
    }
}
