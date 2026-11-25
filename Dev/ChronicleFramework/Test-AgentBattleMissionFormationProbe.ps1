#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$SourceSaveName = 'AgentBridgeLifecycle',
    [ValidateRange(30,900)][int]$TimeoutSeconds = 300,
    [switch]$ProbeMainAgentAiController,
    [switch]$ProbeMainAgentRtsCameraBehavior,
    [switch]$ProbeBattleMovementInput,
    [switch]$ProbeBattleAgentNavigator,
    [switch]$ProbeMainAgentNativeAiHandoff,
    [switch]$ProbeAgentHostNativeAiAutopilot,
    [switch]$ProbeDesktopInputIsolationOnly,
    [switch]$SoloMainHero
)

$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
. (Join-Path $PSScriptRoot 'Test-WindowLayout.ps1')
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
$diagnosticLog = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\Configs\ModLogs\chronicle-framework.log'
$priorMode = $env:CHRONICLE_HARNESS_MODE
$priorInputLock = $env:CHRONICLE_HARNESS_AGENT_INPUT_LOCK
$env:CHRONICLE_HARNESS_MODE = if ($SoloMainHero) { 'solo-battle-fixture' } else { 'battle-fixture' }
$env:CHRONICLE_HARNESS_AGENT_INPUT_LOCK = '1'
$prefix = 'battle-mission-formation-' + [Guid]::NewGuid().ToString('N')
$probeName = if ($ProbeDesktopInputIsolationOnly) { 'BattleMissionInputIsolationProbe' } elseif ($ProbeAgentHostNativeAiAutopilot) { 'BattleMissionHostNativeAiAutopilotProbe' } elseif ($ProbeMainAgentNativeAiHandoff) { 'BattleMissionNativeAiHandoffProbe' } elseif ($ProbeBattleAgentNavigator) { 'BattleMissionAgentNavigatorProbe' } elseif ($ProbeBattleMovementInput) { 'BattleMissionMovementInputProbe' } elseif ($ProbeMainAgentRtsCameraBehavior) { 'BattleMissionRtsCameraProbe' } elseif ($ProbeMainAgentAiController) { 'BattleMissionControllerProbe' } else { 'BattleMissionFormationProbe' }
$runDirectory = if ($env:CHRONICLE_HARNESS_TEMP) { [IO.Path]::GetFullPath($env:CHRONICLE_HARNESS_TEMP) } else { Join-Path $PSScriptRoot ('TestResults\' + $probeName) }
New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null
$script:NativeReceipts = [System.Collections.Generic.List[object]]::new()
$script:ProcessId = $null
$nativeReceiptPath = Join-Path $runDirectory 'BattleMissionFormationProbe-NativeReceipts.jsonl'
[IO.File]::WriteAllText($nativeReceiptPath, '', [Text.UTF8Encoding]::new($false))
$hostBattleCameraCapture = $null
$hostBattleCameraCaptureResult = $null
$cameraMotionCapture = $null
$cameraMotionCaptureResult = $null
$cameraMotionEventPath = $null
$playerControlledMainHeroCameraMotionSamples = [System.Collections.Generic.List[object]]::new()
$nativeAiCameraMotionSamples = [System.Collections.Generic.List[object]]::new()
$cameraMotionComparison = $null

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @()) {
    $output = & $HarnessPowerShell -NoProfile -File $cli $Action @Arguments -TimeoutSeconds $TimeoutSeconds -AsJson 2>&1 | Out-String
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

function Capture-NativeFrame([string]$Name) {
    if (-not $env:CHRONICLE_HARNESS_TEMP -or -not (Test-Path -LiteralPath $env:CHRONICLE_HARNESS_TEMP -PathType Container)) {
        throw 'Native map-frame evidence requires the current Harness temporary directory.'
    }
    $frameDirectory = Join-Path $runDirectory 'TimelineFrames'
    New-Item -ItemType Directory -Path $frameDirectory -Force | Out-Null
    $temporaryFrame = Join-Path $env:CHRONICLE_HARNESS_TEMP ("$prefix-$Name.bmp")
    $evidenceFrame = Join-Path $frameDirectory ("$Name.bmp")
    if (Test-Path -LiteralPath $temporaryFrame) { Remove-Item -LiteralPath $temporaryFrame -Force }
    $frameReceipt = Invoke-AgentCli 'captureFrame' @('-OutputPath', $temporaryFrame, '-CommandId', "$prefix-frame-$Name")
    if ($frameReceipt.status -ne 'completed') { throw "Native map-frame capture '$Name' was rejected: $($frameReceipt.error)" }
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path -LiteralPath $temporaryFrame -PathType Leaf) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
    if (-not (Test-Path -LiteralPath $temporaryFrame -PathType Leaf) -or (Get-Item -LiteralPath $temporaryFrame).Length -lt 4096) {
        throw "Native engine-frame capture '$Name' did not produce a readable frame."
    }
    Move-Item -LiteralPath $temporaryFrame -Destination $evidenceFrame -Force
    return $evidenceFrame
}

function Invoke-AgentCliExpectedReject([string]$Action, [string[]]$Arguments, [string]$CommandId) {
    $responseRoot = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\responses'
    $rejectedPath = Join-Path $responseRoot ($CommandId + '.rejected.json')
    if (Test-Path -LiteralPath $rejectedPath) { Remove-Item -LiteralPath $rejectedPath }
    $output = & $HarnessPowerShell -NoProfile -File $cli $Action @Arguments -CommandId $CommandId -TimeoutSeconds $TimeoutSeconds -AsJson 2>&1 | Out-String
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

function Add-CameraMotionSample($Status, [string]$Phase, [int]$Sequence, $Capture, [string]$EventPath) {
    if ($Status.status -ne 'completed' -or $null -eq $Status.data.camera -or $null -eq $Status.data.mainAgent) {
        throw "Camera-motion comparison '$Phase' did not receive a complete Native camera/MainAgent sample."
    }
    $sampleTicks = [Diagnostics.Stopwatch]::GetTimestamp()
    $offsetMilliseconds = ($sampleTicks - [long]$Capture.StartedTicks) * 1000.0 / [double]$Capture.StopwatchFrequency
    $camera = $Status.data.camera
    $mainAgent = $Status.data.mainAgent
    $sample = [ordered]@{
        phase = $Phase
        sequence = $Sequence
        offsetMilliseconds = [Math]::Round($offsetMilliseconds, 2)
        controller = [string]$mainAgent.controller
        camera = $camera
        position = $mainAgent.position
        isPlayerControlled = [bool]$mainAgent.isPlayerControlled
    }
    $event = [ordered]@{
        event = 'camera-sample'
        utc = ([DateTimeOffset]::Parse([string]$Capture.StartedUtc).ToUniversalTime().AddMilliseconds($offsetMilliseconds).ToString('O'))
        offsetMilliseconds = [Math]::Round($offsetMilliseconds, 2)
        commandId = [string]$Status.commandId
        action = 'camera-sample'
        gameState = [string]$Status.state.context.gameState
        menuId = [string]$Status.state.context.menuId
        partyScreenMode = ''
        inventoryMode = ''
        campaignDay = $Status.campaignDay
        stateFingerprint = "$Phase-$Sequence"
    }
    [IO.File]::AppendAllText($EventPath, ((ConvertTo-Json -InputObject $event -Compress -Depth 5) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    return [pscustomobject]$sample
}

function Get-CameraMotionSummary([object[]]$Samples) {
    if ($Samples.Count -lt 2) { return [ordered]@{ sampleCount = $Samples.Count; available = $false } }
    $bearingSpeeds = [System.Collections.Generic.List[double]]::new()
    $elevationSpeeds = [System.Collections.Generic.List[double]]::new()
    for ($index = 1; $index -lt $Samples.Count; $index++) {
        $previous = $Samples[$index - 1]
        $current = $Samples[$index]
        $deltaSeconds = ([double]$current.offsetMilliseconds - [double]$previous.offsetMilliseconds) / 1000.0
        if ($deltaSeconds -le 0.001) { continue }
        $bearingDelta = [double]$current.camera.bearing - [double]$previous.camera.bearing
        $bearingDelta = [Math]::Atan2([Math]::Sin($bearingDelta), [Math]::Cos($bearingDelta))
        $elevationDelta = [double]$current.camera.elevation - [double]$previous.camera.elevation
        $bearingSpeeds.Add([Math]::Abs($bearingDelta) / $deltaSeconds)
        $elevationSpeeds.Add([Math]::Abs($elevationDelta) / $deltaSeconds)
    }
    $verticalOffsets = @($Samples | ForEach-Object { [double]$_.camera.cameraPositionZ - [double]$_.camera.mainAgentPositionZ })
    $relativeFacingErrors = @($Samples | ForEach-Object {
        $difference = [double]$_.camera.bearing - [double]$_.camera.mainAgentLookDirectionAsAngle
        [Math]::Atan2([Math]::Sin($difference), [Math]::Cos($difference))
    })
    $verticalStats = $verticalOffsets | Measure-Object -Minimum -Maximum
    $facingStats = $relativeFacingErrors | ForEach-Object { [Math]::Abs([double]$_) } | Measure-Object -Maximum
    $bearingSpeedStats = $bearingSpeeds | Measure-Object -Maximum
    $elevationSpeedStats = $elevationSpeeds | Measure-Object -Maximum
    $shakeSamples = @($Samples | Where-Object { $_.camera.nativeCameraShake.active -eq $true })
    $shakeIntensities = @($Samples | ForEach-Object { [double]$_.camera.nativeCameraShake.triggerIntensity })
    $maximumShakeIntensity = ($shakeIntensities | Measure-Object -Maximum).Maximum
    return [ordered]@{
        sampleCount = $Samples.Count
        available = $true
        maximumBearingSpeedRadiansPerSecond = [Math]::Round([double]$bearingSpeedStats.Maximum, 3)
        maximumElevationSpeedRadiansPerSecond = [Math]::Round([double]$elevationSpeedStats.Maximum, 3)
        cameraAgentVerticalOffsetRangeMeters = [Math]::Round([double]$verticalStats.Maximum - [double]$verticalStats.Minimum, 4)
        maximumBearingFacingErrorRadians = [Math]::Round([double]$facingStats.Maximum, 4)
        nativeCameraShakeActiveSamples = $shakeSamples.Count
        maximumNativeCameraShakeTriggerIntensity = [Math]::Round([double]$maximumShakeIntensity, 4)
    }
}

function Add-CameraMotionSample($Status, [string]$Phase, [int]$Sequence, $Capture, [string]$EventPath) {
    if ($Status.status -ne 'completed' -or $null -eq $Status.data.camera -or $null -eq $Status.data.mainAgent) {
        throw "Camera-motion comparison '$Phase' did not receive a complete Native camera/MainAgent sample."
    }
    $sampleTicks = [Diagnostics.Stopwatch]::GetTimestamp()
    $offsetMilliseconds = ($sampleTicks - [long]$Capture.StartedTicks) * 1000.0 / [double]$Capture.StopwatchFrequency
    $camera = $Status.data.camera
    $mainAgent = $Status.data.mainAgent
    $sample = [ordered]@{
        phase = $Phase
        sequence = $Sequence
        offsetMilliseconds = [Math]::Round($offsetMilliseconds, 2)
        controller = [string]$mainAgent.controller
        camera = $camera
        position = $mainAgent.position
        isPlayerControlled = [bool]$mainAgent.isPlayerControlled
    }
    $event = [ordered]@{
        event = 'camera-sample'
        utc = ([DateTimeOffset]::Parse([string]$Capture.StartedUtc).ToUniversalTime().AddMilliseconds($offsetMilliseconds).ToString('O'))
        offsetMilliseconds = [Math]::Round($offsetMilliseconds, 2)
        commandId = [string]$Status.commandId
        action = 'camera-sample'
        gameState = [string]$Status.state.context.gameState
        menuId = [string]$Status.state.context.menuId
        partyScreenMode = ''
        inventoryMode = ''
        campaignDay = $Status.campaignDay
        stateFingerprint = "$Phase-$Sequence"
    }
    [IO.File]::AppendAllText($EventPath, ((ConvertTo-Json -InputObject $event -Compress -Depth 5) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    return [pscustomobject]$sample
}

function Get-CameraMotionSummary([object[]]$Samples) {
    if ($Samples.Count -lt 2) { return [ordered]@{ sampleCount = $Samples.Count; available = $false } }
    $bearingSpeeds = [System.Collections.Generic.List[double]]::new()
    $elevationSpeeds = [System.Collections.Generic.List[double]]::new()
    for ($index = 1; $index -lt $Samples.Count; $index++) {
        $previous = $Samples[$index - 1]
        $current = $Samples[$index]
        $deltaSeconds = ([double]$current.offsetMilliseconds - [double]$previous.offsetMilliseconds) / 1000.0
        if ($deltaSeconds -le 0.001) { continue }
        $bearingDelta = [double]$current.camera.bearing - [double]$previous.camera.bearing
        $bearingDelta = [Math]::Atan2([Math]::Sin($bearingDelta), [Math]::Cos($bearingDelta))
        $elevationDelta = [double]$current.camera.elevation - [double]$previous.camera.elevation
        $bearingSpeeds.Add([Math]::Abs($bearingDelta) / $deltaSeconds)
        $elevationSpeeds.Add([Math]::Abs($elevationDelta) / $deltaSeconds)
    }
    $verticalOffsets = @($Samples | ForEach-Object { [double]$_.camera.cameraPositionZ - [double]$_.camera.mainAgentPositionZ })
    $relativeFacingErrors = @($Samples | ForEach-Object {
        $difference = [double]$_.camera.bearing - [double]$_.camera.mainAgentLookDirectionAsAngle
        [Math]::Atan2([Math]::Sin($difference), [Math]::Cos($difference))
    })
    $verticalStats = $verticalOffsets | Measure-Object -Minimum -Maximum
    $facingStats = $relativeFacingErrors | ForEach-Object { [Math]::Abs([double]$_) } | Measure-Object -Maximum
    $bearingSpeedStats = $bearingSpeeds | Measure-Object -Maximum
    $elevationSpeedStats = $elevationSpeeds | Measure-Object -Maximum
    return [ordered]@{
        sampleCount = $Samples.Count
        available = $true
        maximumBearingSpeedRadiansPerSecond = [Math]::Round([double]$bearingSpeedStats.Maximum, 3)
        maximumElevationSpeedRadiansPerSecond = [Math]::Round([double]$elevationSpeedStats.Maximum, 3)
        cameraAgentVerticalOffsetRangeMeters = [Math]::Round([double]$verticalStats.Maximum - [double]$verticalStats.Minimum, 4)
        maximumBearingFacingErrorRadians = [Math]::Round([double]$facingStats.Maximum, 4)
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
    if ($SoloMainHero -and [int]$state.state.party.members -ne 1) {
        throw "The solo MainHero probe requires a one-member Native MainParty; observed $($state.state.party.members)."
    }
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
        $visibleTarget = @($state.state.nearbyParties | Where-Object { $_.id -eq 'chronicle_harness_looters' -and $_.hostile })
        if ($visibleTarget.Count -ne 1) {
            $visibleTarget = @($state.state.nearbyParties | Where-Object { $_.hostile -and $_.type -eq 'bandit' } | Sort-Object distance | Select-Object -First 1)
        }
        if ($visibleTarget.Count -ne 1) { throw 'The source Campaign has no currently visible hostile Bandit party; the disposable copy will be cleaned without pursuing or advancing time.' }
        $targetId = [string]$visibleTarget[0].id
        $pursue = Invoke-AgentCli 'pursue' @('-PartyId', $targetId, '-CommandId', "$prefix-pursue")
        if ($pursue.status -ne 'completed') { throw 'Native pursuit did not accept the exact current visible hostile party.' }
        if ($pursue.state.context.gameState -eq 'MapState' -and $pursue.timeControlMode -eq 'Stop') {
            # Keep native pursuit and explicit clock control as separate, auditable fixture actions.
            $clockResume = Invoke-AgentCli 'resume' @('-CommandId', "$prefix-resume-for-pursuit")
            if ($clockResume.status -ne 'completed' -or $clockResume.state.context.gameState -ne 'MapState') {
                throw "The explicit Native clock resume after pursuit was rejected; status='$($clockResume.status)', state='$($clockResume.state.context.gameState)', time='$($clockResume.timeControlMode)'."
            }
        }
        $pursuitFrame = Capture-NativeFrame 'pursuit-target-selected'
        $deadline = [DateTime]::UtcNow.AddSeconds([Math]::Min(60, $TimeoutSeconds))
        $lastWaitingCampaignDay = $null
        $stableWaitingSince = $null
        do {
            Start-Sleep -Milliseconds 500
            $state = Invoke-AgentCli 'state' @('-CommandId', "$prefix-map-observe-$([Guid]::NewGuid().ToString('N'))")
            $encounterActive = [bool]$state.state.context.encounterActive
            $encounteredPartyId = [string]$state.state.context.encounteredPartyId
            $samePartyStillTargeted = [string]$state.state.location.targetPartyId -eq $targetId
            $isNativeWaitingOnTarget = $samePartyStillTargeted -and [bool]$state.state.context.isWaiting -and -not $state.state.party.isMoving
            if ($isNativeWaitingOnTarget -and $null -ne $lastWaitingCampaignDay -and
                [Math]::Abs([double]$state.campaignDay - [double]$lastWaitingCampaignDay) -lt 0.000001) {
                if ($null -eq $stableWaitingSince) { $stableWaitingSince = [DateTime]::UtcNow }
                if (([DateTime]::UtcNow - $stableWaitingSince).TotalSeconds -ge 3) {
                    $waitingFrame = Capture-NativeFrame 'native-target-selected-but-waiting'
                    throw "Native pursuit left MainParty waiting at its exact current target without a Campaign Encounter. TargetId='$targetId'; CampaignDay=$($state.campaignDay); TimeControlMode=$($state.timeControlMode); TargetFrame='$pursuitFrame'; WaitingFrame='$waitingFrame'."
                }
            }
            elseif (-not $isNativeWaitingOnTarget -or $null -eq $lastWaitingCampaignDay -or
                [Math]::Abs([double]$state.campaignDay - [double]$lastWaitingCampaignDay) -ge 0.000001) {
                $stableWaitingSince = $null
            }
            $lastWaitingCampaignDay = [double]$state.campaignDay
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

    $missionWindowSafety = Set-ChronicleTestWindow -ProcessId $script:ProcessId
    $inputLockPattern = 'pid=' + [regex]::Escape([string]$script:ProcessId) + '\|harness-agent-input-lock\|locked=True\|scope=' + [regex]::Escape([string]$env:CHRONICLE_HARNESS_MODE)
    $missionInputBlockedPattern = 'pid=' + [regex]::Escape([string]$script:ProcessId) + '\|agent-mission-input-blocked\|mission='
    $inputLockDeadline = [DateTime]::UtcNow.AddSeconds(10)
    $inputOwnershipConfirmed = $false
    while ([DateTime]::UtcNow -lt $inputLockDeadline) {
        if (Test-Path -LiteralPath $diagnosticLog -PathType Leaf) {
            $missionDiagnostics = @(Get-Content -LiteralPath $diagnosticLog -Tail 512 -Encoding UTF8)
            $inputLockObserved = @($missionDiagnostics | Where-Object { $_ -match $inputLockPattern }).Count -gt 0
            $missionInputBlockedObserved = @($missionDiagnostics | Where-Object { $_ -match $missionInputBlockedPattern }).Count -gt 0
            if ($inputLockObserved -and $missionInputBlockedObserved) { $inputOwnershipConfirmed = $true; break }
        }
        Start-Sleep -Milliseconds 200
    }
    $desktopInputIsolationPassed = [bool]($missionWindowSafety -and $missionWindowSafety.Applied -and $missionWindowSafety.NonActivating -and $missionWindowSafety.NotForeground -and $missionWindowSafety.CursorUnrestrictedAcrossDesktop)
    if (-not $desktopInputIsolationPassed -or -not $inputOwnershipConfirmed) {
        throw 'Mission safety gate failed: the battle window must remain non-activating/non-foreground, the desktop cursor clip must cover the full virtual desktop, and Chronicle must confirm its Agent lock plus empty Mission input before probe actions continue.'
    }
    $desktopInputIsolationReceipt = [ordered]@{
        runId = $probeName
        scenario = 'native-battle-mission-desktop-input-isolation-no-model'
        capturedUtc = [DateTime]::UtcNow.ToString('O')
        processId = $script:ProcessId
        gameState = [string]$missionState.state.context.gameState
        missionMode = [string]$missionState.state.mission.mode
        missionName = [string]$missionState.state.mission.sceneName
        windowSafety = $missionWindowSafety
        desktopCursorUnrestricted = [bool]$missionWindowSafety.CursorUnrestrictedAcrossDesktop
        harnessInputOwnershipConfirmed = $inputOwnershipConfirmed
        emptyMissionInputObserved = $missionInputBlockedObserved
        modelCalls = 0
    }
    [IO.File]::WriteAllText((Join-Path $runDirectory 'BattleMissionDesktopInputIsolation.json'), (ConvertTo-Json -InputObject $desktopInputIsolationReceipt -Depth 8), [Text.UTF8Encoding]::new($false))

    if ($ProbeDesktopInputIsolationOnly) {
        $stop = Invoke-AgentCli 'stop'
        $sourceHashAfter = (Get-FileHash -LiteralPath $sourceSavePath -Algorithm SHA256).Hash
        $disposableSaveHashAfter = if (Test-Path -LiteralPath $disposableSavePath -PathType Leaf) { (Get-FileHash -LiteralPath $disposableSavePath -Algorithm SHA256).Hash } else { $null }
        $disposableSaveRemoved = $false
        if ($disposableSaveOwned -and $null -ne $disposableSaveHashAfter -and $disposableSaveHashAfter -ceq $disposableSaveHash) {
            Remove-Item -LiteralPath $disposableSavePath
            $disposableSaveRemoved = -not (Test-Path -LiteralPath $disposableSavePath -PathType Leaf)
        }
        $result = [ordered]@{
            runId = $probeName
            scenario = [string]$desktopInputIsolationReceipt.scenario
            passed = [bool]($desktopInputIsolationPassed -and $inputOwnershipConfirmed -and $stop.processStopped -and $sourceHashBefore -ceq $sourceHashAfter -and $disposableSaveRemoved)
            modelCalls = 0
            desktopInputIsolation = $desktopInputIsolationReceipt
            sourceSaveName = $SourceSaveName
            sourceSaveHashBefore = $sourceHashBefore
            sourceSaveHashAfter = $sourceHashAfter
            sourceSaveUnchanged = ($sourceHashBefore -ceq $sourceHashAfter)
            disposableSaveName = $disposableSaveName
            disposableSaveHashBefore = $disposableSaveHash
            disposableSaveHashAfter = $disposableSaveHashAfter
            disposableSaveRemoved = $disposableSaveRemoved
            processStopped = [bool]$stop.processStopped
        }
        [IO.File]::WriteAllText((Join-Path $runDirectory ($probeName + '.json')), (ConvertTo-Json -InputObject $result -Depth 10), [Text.UTF8Encoding]::new($false))
        $result | ConvertTo-Json -Depth 10
        if (-not $result.passed) { throw '3D Mission desktop input isolation probe failed its cursor, focus, input-lock, or cleanup checks.' }
        return
    }

    if ($ProbeAgentHostNativeAiAutopilot) {
        $hostExecutablePath = $env:CHRONICLE_AGENT_HOST_TEST_PATH
        if ([string]::IsNullOrWhiteSpace($hostExecutablePath) -or -not (Test-Path -LiteralPath $hostExecutablePath -PathType Leaf)) {
            throw 'The same-session self-contained Agent Host runtime package is unavailable for the Native loop integration probe.'
        }
        . (Join-Path $PSScriptRoot 'HarnessVideoCapture.ps1')
        $hostBattleCameraVideoPath = Join-Path $runDirectory 'HostNativeBattleCamera.mp4'
        $hostBattleCameraContactPath = Join-Path $runDirectory 'HostNativeBattleCamera-contact.jpg'
        $hostBattleCameraEventsPath = Join-Path $runDirectory 'HostNativeBattleCamera-events.jsonl'
        $hostBattleCameraCapture = Start-ChronicleWindowVideoCapture -ProcessId $script:ProcessId -OutputPath $hostBattleCameraVideoPath -FrameRate 10 -DurationLimitSeconds 30
        $deploymentStatusBeforeHost = Invoke-AgentCli 'battleMissionStatus' @('-CommandId', "$prefix-host-deployment-status")
        $hostStartInfo = [Diagnostics.ProcessStartInfo]::new()
        $hostStartInfo.FileName = $hostExecutablePath
        $hostStartInfo.Arguments = '--native-battle-mission-loop-harness ' + [string]$script:ProcessId
        $hostStartInfo.WorkingDirectory = Split-Path -Parent $hostExecutablePath
        $hostStartInfo.UseShellExecute = $false
        $hostStartInfo.CreateNoWindow = $true
        $hostStartInfo.RedirectStandardOutput = $true
        $hostStartInfo.RedirectStandardError = $true
        $hostProcess = [Diagnostics.Process]::new()
        $hostProcess.StartInfo = $hostStartInfo
        if (-not $hostProcess.Start()) { throw 'The packaged Agent Host Native battle loop did not start.' }
        $hostStdoutTask = $hostProcess.StandardOutput.ReadToEndAsync()
        $hostStderrTask = $hostProcess.StandardError.ReadToEndAsync()
        $hostWaitMilliseconds = [int]([Math]::Min(900, $TimeoutSeconds) * 1000)
        if (-not $hostProcess.WaitForExit($hostWaitMilliseconds)) {
            try { $hostProcess.Kill($true) } catch { }
            throw 'The production AgentHostBattleMissionLoop exceeded its bounded Native integration probe.'
        }
        $captureStarted = [DateTimeOffset]::Parse([string]$hostBattleCameraCapture.StartedUtc).ToUniversalTime()
        $captureDuration = ([Diagnostics.Stopwatch]::GetTimestamp() - [long]$hostBattleCameraCapture.StartedTicks) * 1000.0 / [double]$hostBattleCameraCapture.StopwatchFrequency
        $sampleIntervalMilliseconds = 250.0
        $cameraSampleIndex = 0
        for ($offsetMilliseconds = $sampleIntervalMilliseconds; $offsetMilliseconds -lt ($captureDuration - 100.0) -and $cameraSampleIndex -lt 24; $offsetMilliseconds += $sampleIntervalMilliseconds) {
            $cameraSampleIndex++
            $sampleEvent = [ordered]@{
                event = 'camera-sample'
                utc = $captureStarted.AddMilliseconds($offsetMilliseconds).ToString('O')
                offsetMilliseconds = [Math]::Round($offsetMilliseconds, 2)
                commandId = $null
                action = 'camera-sample'
                gameState = 'MissionState'
                menuId = ''
                partyScreenMode = ''
                inventoryMode = ''
                campaignDay = $null
                stateFingerprint = ('camera-frame-' + $cameraSampleIndex.ToString('D2'))
            }
            [IO.File]::AppendAllText($hostBattleCameraEventsPath, ((ConvertTo-Json -InputObject $sampleEvent -Compress -Depth 4) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
        }
        $hostBattleCameraCaptureResult = Stop-ChronicleWindowVideoCapture -Capture $hostBattleCameraCapture -ContactSheetPath $hostBattleCameraContactPath -EventTracePath $hostBattleCameraEventsPath
        $hostBattleCameraCapture = $null
        $hostStdout = $hostStdoutTask.GetAwaiter().GetResult()
        $hostStderr = $hostStderrTask.GetAwaiter().GetResult()
        $hostPayload = if (-not [string]::IsNullOrWhiteSpace($hostStdout)) { $hostStdout } else { $hostStderr }
        try { $hostResult = $hostPayload | ConvertFrom-Json }
        catch { throw "The production AgentHostBattleMissionLoop did not return a JSON receipt (exit=$($hostProcess.ExitCode)): $hostStderr $hostStdout" }
        $hostMissionResult = $hostResult.nativeResult
        $hostNativeActions = [System.Collections.Generic.List[string]]::new()
        if ($hostMissionResult.nativeDeploymentAutoDeployIssued) { $hostNativeActions.Add('missionAutoDeploy') }
        if ($hostMissionResult.nativeDeploymentFinishIssued) { $hostNativeActions.Add('missionFinishDeployment') }
        if ($hostMissionResult.delegationIssued) { $hostNativeActions.Add('missionDelegateTroops') }
        if ($hostMissionResult.mainHeroAutopilotIssued) { $hostNativeActions.Add('missionAutopilotMainAgent') }
        if ($hostMissionResult.nativeMissionExitIssued) { $hostNativeActions.Add('missionRetreat') }
        $stateAfterHost = Invoke-AgentCli 'state' @('-CommandId', "$prefix-host-autopilot-afterstate")
        $nativeBattleStatusAfterHost = if ($stateAfterHost.state.context.gameState -eq 'MissionState' -and $stateAfterHost.state.mission.mode -in @('Deployment','Battle')) {
            Invoke-AgentCli 'battleMissionStatus' @('-CommandId', "$prefix-host-deployment-afterstatus")
        } else { $null }
        $hostFailureFrame = $null
        if (($hostMissionResult.termination -in @('battle-mission-native-deployment-precondition-failed','battle-mission-deployment-transition-timeout','battle-mission-deployment-ui-not-ready','battle-mission-native-ready-callback-not-bound','battle-mission-native-ready-did-not-finish-deployment') -or
             $hostMissionResult.termination -like 'battle-mission-native-deployment-action-campaign-day-changed:*' -or
             $hostMissionResult.termination -like 'battle-mission-native-auto-deploy-command-rejected:*') -and
            $stateAfterHost.state.context.gameState -eq 'MissionState' -and $stateAfterHost.state.mission.mode -in @('Deployment','Battle')) {
            $hostFailureFramePath = Join-Path $runDirectory 'HostNativeBattlePreconditionFailure.bmp'
            $hostFailureFrame = Invoke-AgentCli 'captureFrame' @('-OutputPath', $hostFailureFramePath, '-CommandId', "$prefix-host-deployment-timeout-frame")
            if ($hostFailureFrame.status -ne 'completed') { throw 'Native engine frame capture failed while the Host remained in the observed Battle Mission.' }
            $frameDeadline = [DateTime]::UtcNow.AddSeconds(10)
            while (-not (Test-Path -LiteralPath $hostFailureFramePath) -and [DateTime]::UtcNow -lt $frameDeadline) { Start-Sleep -Milliseconds 100 }
            if (-not (Test-Path -LiteralPath $hostFailureFramePath) -or (Get-Item -LiteralPath $hostFailureFramePath).Length -lt 4096) {
                throw 'Native engine did not write a usable Battle Mission precondition frame.'
            }
        }
        $stop = Invoke-AgentCli 'stop'
        $sourceHashAfter = (Get-FileHash -LiteralPath $sourceSavePath -Algorithm SHA256).Hash
        $disposableSaveHashAfter = (Get-FileHash -LiteralPath $disposableSavePath -Algorithm SHA256).Hash
        $disposableSaveRemoved = $false
        if ($disposableSaveOwned -and $disposableSaveHashAfter -eq $disposableSaveHash) {
            Remove-Item -LiteralPath $disposableSavePath
            $disposableSaveRemoved = -not (Test-Path -LiteralPath $disposableSavePath)
        }
        $expectedHostNativeActionsList = [System.Collections.Generic.List[string]]::new()
        # Native can advance from Deployment to Battle while the Host is starting.
        # Base the expected Host commands on the Host's own first observation,
        # not the earlier polling snapshot captured before Host startup.
        if ($hostMissionResult.missionModeAtEntry -eq 'Deployment') {
            if ($hostMissionResult.nativeDeploymentAutoDeployIssued) { $expectedHostNativeActionsList.Add('missionAutoDeploy') }
            if (-not $hostMissionResult.nativeDeploymentCompletedByNative) { $expectedHostNativeActionsList.Add('missionFinishDeployment') }
        }
        $hostDelegatedFormationCount = [int]$hostMissionResult.delegatedFormationCount
        if ([bool]$hostMissionResult.delegationIssued -ne ($hostDelegatedFormationCount -gt 0)) {
            throw "Production Host battle result is inconsistent: delegationIssued=$($hostMissionResult.delegationIssued), delegatedFormationCount=$hostDelegatedFormationCount."
        }
        if ($hostMissionResult.delegationIssued) { $expectedHostNativeActionsList.Add('missionDelegateTroops') }
        $expectedHostNativeActionsList.Add('missionAutopilotMainAgent')
        $expectedHostNativeActionsList.Add('missionRetreat')
        $expectedHostNativeActions = $expectedHostNativeActionsList.ToArray()
        $result = [ordered]@{
            runId = $probeName
            scenario = 'production-host-loop-native-battle-autopilot-no-model'
            modelCalls = 0
            nativeCommands = $script:NativeReceipts.Count
            sourceSaveName = $SourceSaveName
            sourceSaveHashBefore = $sourceHashBefore
            sourceSaveHashAfter = $sourceHashAfter
            sourceSaveUnchanged = ($sourceHashBefore -eq $sourceHashAfter)
            disposableSaveName = $disposableSaveName
            disposableSaveHashBeforeTest = $disposableSaveHash
            disposableSaveHashAfterTest = $disposableSaveHashAfter
            disposableSaveRemoved = $disposableSaveRemoved
            processStopped = [bool]$stop.processStopped
            desktopInputIsolationPassed = $desktopInputIsolationPassed
            hostBattleCameraCapture = [ordered]@{
                provider = 'FFmpeg gfxcapture, explicit Bannerlord HWND'
                frameRate = [int]$hostBattleCameraCaptureResult.FrameRateTarget
                frameCount = [int]$hostBattleCameraCaptureResult.FrameCount
                durationSeconds = [double]$hostBattleCameraCaptureResult.DurationSeconds
                periodicFrameSamples = $cameraSampleIndex
                timelineFrameCount = [int]$hostBattleCameraCaptureResult.TimelineFrameCount
                videoRemovedAfterEvidence = [bool]$hostBattleCameraCaptureResult.VideoRemovedAfterEvidence
                contactSheetPath = $hostBattleCameraCaptureResult.ContactSheetPath
                timelineIndexPath = $hostBattleCameraCaptureResult.TimelineIndexPath
            }
            missionWindowSafety = $missionWindowSafety
            harnessInputOwnershipConfirmed = $inputOwnershipConfirmed
            hostRuntimePath = $hostExecutablePath
            hostExitCode = $hostProcess.ExitCode
            hostStatus = [string]$hostResult.status
            hostErrorCode = [string]$hostResult.error
            hostErrorMessage = [string]$hostResult.message
            hostMissionResult = [ordered]@{
                completed = [bool]$hostMissionResult.completed
                termination = [string]$hostMissionResult.termination
                nativeDeploymentPreconditionDiagnostic = $hostMissionResult.nativeDeploymentPreconditionDiagnostic
                missionModeAtEntry = [string]$hostMissionResult.missionModeAtEntry
                nativeDeploymentCompletedByNative = [bool]$hostMissionResult.nativeDeploymentCompletedByNative
                delegationIssued = [bool]$hostMissionResult.delegationIssued
                nativeDeploymentAutoDeployIssued = [bool]$hostMissionResult.nativeDeploymentAutoDeployIssued
                nativeDeploymentFinishIssued = [bool]$hostMissionResult.nativeDeploymentFinishIssued
                nativeReadyCallbackDispatchedByBridge = [bool]$hostMissionResult.nativeReadyCallbackDispatchedByBridge
                nativeReadyHandlerExceptionType = [string]$hostMissionResult.nativeReadyHandlerExceptionType
                delegatedFormationCount = [int]$hostMissionResult.delegatedFormationCount
                mainHeroHealthAtStart = $hostMissionResult.mainHeroHealthAtStart
                mainHeroHealthAtEnd = $hostMissionResult.mainHeroHealthAtEnd
                mainHeroNativeAiControlMaintained = [bool]$hostMissionResult.mainHeroNativeAiControlMaintained
                campaignDayAtStart = $hostMissionResult.campaignDayAtStart
                campaignDayAtEnd = $hostMissionResult.campaignDayAtEnd
                timeControlModeAtStart = [string]$hostMissionResult.timeControlModeAtStart
                timeControlModeAtEnd = [string]$hostMissionResult.timeControlModeAtEnd
                passivePollCount = [int]$hostMissionResult.passivePollCount
                mainAgentRemovedDuringMission = [bool]$hostMissionResult.mainAgentRemovedDuringMission
                mainHeroAutopilotIssued = [bool]$hostMissionResult.mainHeroAutopilotIssued
                nativeMissionExitIssued = [bool]$hostMissionResult.nativeMissionExitIssued
            }
            hostFailureFrame = if ($hostFailureFrame) { [ordered]@{ status = [string]$hostFailureFrame.status; path = $hostFailureFramePath; sha256 = (Get-FileHash -LiteralPath $hostFailureFramePath -Algorithm SHA256).Hash } } else { $null }
            deploymentStatusBeforeHost = [ordered]@{
                supported = [bool]$deploymentStatusBeforeHost.data.supported
                reason = [string]$deploymentStatusBeforeHost.data.reason
                missionMode = [string]$deploymentStatusBeforeHost.data.missionMode
                campaignDay = $deploymentStatusBeforeHost.data.campaignDay
                campaignTimeControlMode = [string]$deploymentStatusBeforeHost.data.campaignTimeControlMode
                mainAgentController = if ($null -eq $deploymentStatusBeforeHost.data.mainAgent) { $null } else { [string]$deploymentStatusBeforeHost.data.mainAgent.controller }
                mainAgentPlayerControlled = if ($null -eq $deploymentStatusBeforeHost.data.mainAgent) { $null } else { [bool]$deploymentStatusBeforeHost.data.mainAgent.isPlayerControlled }
                playerTeamFormationCount = [int]$deploymentStatusBeforeHost.data.playerTeam.formationCount
                deploymentUi = $deploymentStatusBeforeHost.data.deploymentUi
            }
            nativeBattleStatusAfterHost = if ($nativeBattleStatusAfterHost) { [ordered]@{
                supported = [bool]$nativeBattleStatusAfterHost.data.supported
                reason = [string]$nativeBattleStatusAfterHost.data.reason
                missionMode = [string]$nativeBattleStatusAfterHost.data.missionMode
                campaignDay = $nativeBattleStatusAfterHost.data.campaignDay
                campaignTimeControlMode = [string]$nativeBattleStatusAfterHost.data.campaignTimeControlMode
                mainAgentController = if ($null -eq $nativeBattleStatusAfterHost.data.mainAgent) { $null } else { [string]$nativeBattleStatusAfterHost.data.mainAgent.controller }
                mainAgentPlayerControlled = if ($null -eq $nativeBattleStatusAfterHost.data.mainAgent) { $null } else { [bool]$nativeBattleStatusAfterHost.data.mainAgent.isPlayerControlled }
                deploymentUi = $nativeBattleStatusAfterHost.data.deploymentUi
            }} else { $null }
            nativeActionSequence = $hostNativeActions.ToArray()
            fixtureActionSequence = @($script:NativeReceipts | ForEach-Object { [string]$_.action })
            expectedNativeActionSequence = $expectedHostNativeActions
            postHostGameState = [string]$stateAfterHost.state.context.gameState
            postHostMenuId = [string]$stateAfterHost.state.context.menuId
            mainPartyAfter = [ordered]@{ members = $stateAfterHost.state.party.members; healthy = $stateAfterHost.state.party.healthy; wounded = $stateAfterHost.state.party.wounded; prisoners = $stateAfterHost.state.party.prisoners }
            renownBefore = $renownBefore
            renownAfter = [double]$stateAfterHost.state.economy.renown
            nativeReceipts = $script:NativeReceipts.ToArray()
        }
        $hostNativeAftermathValid = $desktopInputIsolationPassed -and $inputOwnershipConfirmed -and $hostProcess.ExitCode -eq 0 -and $hostResult.status -eq 'completed' -and $hostMissionResult.completed -eq $true -and
            $hostMissionResult.mainHeroAutopilotIssued -eq $true -and $hostMissionResult.nativeMissionExitIssued -eq $true -and
            $hostMissionResult.timeControlModeAtStart -eq 'Stop' -and $hostMissionResult.timeControlModeAtEnd -eq 'Stop' -and
            $result.postHostGameState -ne 'MissionState' -and $hostNativeActions.Count -eq $expectedHostNativeActions.Count -and
            -not (Compare-Object $expectedHostNativeActions $hostNativeActions.ToArray()) -and $result.sourceSaveUnchanged -and
            $result.disposableSaveRemoved -and $result.processStopped
        if ($SoloMainHero) {
            $soloNativeDeploymentTransitionVerified = $hostMissionResult.nativeDeploymentCompletedByNative -eq $true -or
                ($missionState.state.mission.mode -eq 'Deployment' -and
                    $hostMissionResult.missionModeAtEntry -eq 'Battle' -and
                    $deploymentStatusBeforeHost.data.missionMode -eq 'Battle')
            $soloControlDispositionValid = $hostMissionResult.mainHeroNativeAiControlMaintained -eq $true -or
                ($hostMissionResult.mainAgentRemovedDuringMission -eq $true -and [bool]$stateAfterHost.state.context.captivity.isCaptive)
            $result['soloNativeDeploymentTransitionVerified'] = [bool]$soloNativeDeploymentTransitionVerified
            $result['missionModeObservedBeforeHost'] = [string]$missionState.state.mission.mode
            $result['missionModeObservedAtHostEntry'] = [string]$hostMissionResult.missionModeAtEntry
            $result['missionModeObservedBeforeHostStartup'] = [string]$deploymentStatusBeforeHost.data.missionMode
            $result['passed'] = $hostNativeAftermathValid -and $soloNativeDeploymentTransitionVerified -and
                $deploymentStatusBeforeHost.data.playerTeam.formationCount -eq 0 -and
                $hostMissionResult.delegationIssued -eq $false -and $hostMissionResult.delegatedFormationCount -eq 0 -and
                $hostMissionResult.nativeDeploymentFinishIssued -eq $false -and
                $soloControlDispositionValid
        }
        else {
            $result['passed'] = $hostNativeAftermathValid -and $hostMissionResult.mainHeroNativeAiControlMaintained -eq $true -and
                $hostMissionResult.delegatedFormationCount -gt 0
        }
        [IO.File]::WriteAllText((Join-Path $runDirectory ($probeName + '.json')), (ConvertTo-Json -InputObject $result -Depth 8), [Text.UTF8Encoding]::new($false))
        $result | ConvertTo-Json -Depth 8
        if (-not $result.passed) { throw 'The production Host Native battle autopilot path failed its end-to-end disposable-clone acceptance checks.' }
        return
    }

    $deploymentAutoDeploy = $null
    $deploymentFinish = $null
    $deploymentTransitionPollCount = 0
    if ($missionState.state.mission.mode -eq 'Deployment') {
        $deploymentStatus = Invoke-AgentCli 'battleMissionStatus' @('-CommandId', "$prefix-native-deployment-status")
        if ($deploymentStatus.status -ne 'completed' -or $deploymentStatus.data.deploymentUi.viewAvailable -ne $true -or
            $deploymentStatus.data.deploymentUi.canStartMission -ne $true -or $deploymentStatus.data.deploymentUi.deploymentFinished -eq $true) {
            throw 'The Native battle deployment screen did not expose an enabled original Auto Deploy/Ready flow.'
        }
        $deploymentAutoDeploy = Invoke-AgentCli 'missionAutoDeploy' @('-CommandId', "$prefix-native-auto-deploy")
        if ($deploymentAutoDeploy.status -ne 'completed' -or $deploymentAutoDeploy.data.nativeHandler -ne 'MissionGauntletSingleplayerOrderUIHandler.OnAutoDeploy' -or
            $deploymentAutoDeploy.data.nativeAutoDeployHandler -ne 'MissionOrderDeploymentControllerVM.ExecuteAutoDeploy' -or
            $deploymentAutoDeploy.data.nativeDeploymentHandler -ne 'MissionOrderDeploymentControllerVM.ExecuteDeployPlayerSide' -or
            $deploymentAutoDeploy.data.canStartMission -ne $true -or $deploymentAutoDeploy.data.timeControlModeBefore -ne 'Stop' -or
            $deploymentAutoDeploy.data.timeControlModeAfter -ne 'Stop' -or
            [Math]::Abs([double]$deploymentAutoDeploy.data.campaignDayAfter - [double]$deploymentAutoDeploy.data.campaignDayBefore) -gt 0.000001) {
            throw 'The Native Auto Deploy screen action did not preserve the stopped Campaign clock and original UI handler receipt.'
        }
        $missionState = Invoke-AgentCli 'state' @('-CommandId', "$prefix-after-native-auto-deploy")
    }
    if ($missionState.state.context.gameState -eq 'MissionState' -and $missionState.state.mission.mode -eq 'Deployment') {
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

    if ($missionState.state.context.gameState -ne 'MissionState' -or $missionState.state.mission.mode -ne 'Battle') {
        $battleReadyDeadline = [DateTime]::UtcNow.AddSeconds([Math]::Min(30, $TimeoutSeconds))
        while ([DateTime]::UtcNow -lt $battleReadyDeadline) {
            $missionState = Invoke-AgentCli 'state' @('-CommandId', "$prefix-battle-ready-$([Guid]::NewGuid().ToString('N'))")
            $deploymentTransitionPollCount++
            if ($missionState.state.context.gameState -eq 'MissionState' -and $missionState.state.mission.mode -eq 'Battle') { break }
            if ($missionState.state.context.gameState -ne 'MissionState' -or $missionState.state.mission.missionEnded -or $missionState.state.context.inquiryOpen) {
                throw "Native deployment did not advance the same Mission to Battle safely; state='$($missionState.state.context.gameState)', mode='$($missionState.state.mission.mode)', inquiry=$($missionState.state.context.inquiryOpen)."
            }
            Start-Sleep -Milliseconds 500
        }
    }
    if ($missionState.state.mission.mode -ne 'Battle') { throw 'Native deployment timed out before Battle mode appeared.' }

    $statusBefore = Invoke-AgentCli 'battleMissionStatus' @('-CommandId', "$prefix-status-before")
    if ($statusBefore.data.supported -ne $true -or $statusBefore.data.missionMode -ne 'Battle') { throw "Battle Mission status rejected the expected field battle: $($statusBefore.data.reason)" }
    $mainAgentBefore = Get-FormationSnapshot $statusBefore
    if (-not $mainAgentBefore.isPlayerControlled) { throw 'MainAgent was not Player-controlled before F6-equivalent delegation.' }
    if ($statusBefore.data.playerTeam.formationCount -lt 1) { throw 'Native status exposed no current player Formation to delegate.' }

    $delegation = Invoke-AgentCli 'missionDelegateTroops' @('-CommandId', "$prefix-delegate")
    if ($delegation.status -ne 'completed' -or $delegation.data.allRequestedFormationsDelegated -ne $true -or
        $delegation.data.mainAgentStillPlayerControlled -ne $true -or $delegation.data.timeControlModeBefore -ne 'Stop' -or
        $delegation.data.timeControlModeAfter -ne 'Stop' -or [Math]::Abs([double]$delegation.data.campaignDayAfter - [double]$delegation.data.campaignDayBefore) -gt 0.000001) {
        throw 'Player-controlled MainHero-equivalent delegation failed to preserve current formations, MainAgent controller, and Campaign time.'
    }
    $statusAfter = Invoke-AgentCli 'battleMissionStatus' @('-CommandId', "$prefix-status-after")
    $mainAgentAfter = Get-FormationSnapshot $statusAfter

    $nativeAiHandoffProbe = $null
    $nativeAiHandoffCameraFrame = $null
    $nativeAiHandoffSustainedCameraFrame = $null
    $nativeAiHandoffExpectedCameraElevation = $null
    $nativeAiHandoffSamples = [System.Collections.Generic.List[object]]::new()
    $mainAgentMovedDuringNativeAiHandoff = $null
    $playerControlledMainHeroOrderViewClose = $null
    if ($ProbeMainAgentNativeAiHandoff) {
        $playerControlledMainHeroOrderViewClose = Invoke-AgentCli 'harnessCloseMissionOrderMenu' @('-CommandId', "$prefix-player-controlled-mainhero-close-order-view")
        if ($playerControlledMainHeroOrderViewClose.status -ne 'completed' -or $playerControlledMainHeroOrderViewClose.data.scope -ne 'harness-only' -or
            ($playerControlledMainHeroOrderViewClose.data.orderViewOpenBefore -eq $true -and $playerControlledMainHeroOrderViewClose.data.status -ne 'closed') -or
            $playerControlledMainHeroOrderViewClose.data.timeControlModeBefore -ne 'Stop' -or $playerControlledMainHeroOrderViewClose.data.timeControlModeAfter -ne 'Stop' -or
            [Math]::Abs([double]$playerControlledMainHeroOrderViewClose.data.campaignDayAfter - [double]$playerControlledMainHeroOrderViewClose.data.campaignDayBefore) -gt 0.000001 -or
            $playerControlledMainHeroOrderViewClose.data.mainAgentControllerBefore -ne 'Player' -or $playerControlledMainHeroOrderViewClose.data.mainAgentControllerAfter -ne 'Player') {
            throw 'The Native order-view close probe did not use the original MissionScreen.OnEscape path without changing MainHero or Campaign time.'
        }
        $cameraBaselinePreparation = Invoke-AgentCli 'harnessPrepareCameraMotionBaseline' @('-CommandId', "$prefix-camera-motion-baseline-setup")
        if ($cameraBaselinePreparation.status -ne 'completed' -or $cameraBaselinePreparation.data.scope -ne 'harness-only' -or
            [Math]::Abs([double]$cameraBaselinePreparation.data.nativeDefaultThirdPersonElevation - (-0.2)) -gt 0.001 -or
            $cameraBaselinePreparation.data.mainAgentController -ne 'Player' -or
            $cameraBaselinePreparation.data.timeControlModeBefore -ne 'Stop' -or $cameraBaselinePreparation.data.timeControlModeAfter -ne 'Stop' -or
            [Math]::Abs([double]$cameraBaselinePreparation.data.campaignDayAfter - [double]$cameraBaselinePreparation.data.campaignDayBefore) -gt 0.000001) {
            throw 'Harness did not establish a normal Native third-person camera baseline without changing MainHero control or Campaign time.'
        }
        $statusAfterF6OrderClose = Invoke-AgentCli 'battleMissionStatus' @('-CommandId', "$prefix-player-controlled-mainhero-camera-baseline-after-close")
        if ($statusAfterF6OrderClose.data.mainAgent.controller -ne 'Player' -or $statusAfterF6OrderClose.data.mainAgent.isPlayerControlled -ne $true -or
            $statusAfterF6OrderClose.data.camera.firstPerson -ne $false) {
            throw 'Preparing the Player-controlled MainHero camera baseline changed MainHero control or first/third-person mode.'
        }
        . (Join-Path $PSScriptRoot 'HarnessVideoCapture.ps1')
        $cameraMotionVideoPath = Join-Path $runDirectory 'NativeAiHandoffCameraMotion.mp4'
        $cameraMotionContactPath = Join-Path $runDirectory 'NativeAiHandoffCameraMotion-contact.jpg'
        $cameraMotionEventPath = Join-Path $runDirectory 'NativeAiHandoffCameraMotion-events.jsonl'
        [IO.File]::WriteAllText($cameraMotionEventPath, '', [Text.UTF8Encoding]::new($false))
        $cameraMotionCapture = Start-ChronicleWindowVideoCapture -ProcessId $script:ProcessId -OutputPath $cameraMotionVideoPath -FrameRate 10 -DurationLimitSeconds 30

        $playerControlledMainHeroBaseline = $statusAfterF6OrderClose
        $playerControlledMainHeroDelegatedFormations = @($playerControlledMainHeroBaseline.data.playerTeam.formations | Where-Object { $_.isAIControlled -eq $true })
        if ($playerControlledMainHeroBaseline.data.mainAgent.controller -ne 'Player' -or
            $playerControlledMainHeroBaseline.data.mainAgent.isPlayerControlled -ne $true -or
            $playerControlledMainHeroDelegatedFormations.Count -eq 0) {
            throw 'The camera comparison baseline is not the Player-controlled MainHero state: at least one player formation must be AI-controlled while MainHero stays Player-controlled.'
        }
        $playerControlledMainHeroCameraMotionSamples.Add((Add-CameraMotionSample $playerControlledMainHeroBaseline 'player-controlled-mainhero-player-camera' 0 $cameraMotionCapture $cameraMotionEventPath))
        for ($baselineIndex = 1; $baselineIndex -le 8; $baselineIndex++) {
            Start-Sleep -Milliseconds 500
            $playerControlledMainHeroSample = Invoke-AgentCli 'battleMissionStatus' @('-CommandId', "$prefix-player-controlled-mainhero-camera-baseline-$baselineIndex")
            if ($playerControlledMainHeroSample.data.mainAgent.controller -ne 'Player' -or $playerControlledMainHeroSample.data.mainAgent.isPlayerControlled -ne $true) {
                throw 'MainHero stopped being Player-controlled during the Player-controlled MainHero camera-motion baseline.'
            }
            $playerControlledMainHeroCameraMotionSamples.Add((Add-CameraMotionSample $playerControlledMainHeroSample 'player-controlled-mainhero-player-camera' $baselineIndex $cameraMotionCapture $cameraMotionEventPath))
        }

        $nativeAiHandoffProbe = Invoke-AgentCli 'harnessMainAgentNativeAiHandoffProbe' @('-DurationSeconds', '180', '-CommandId', "$prefix-main-agent-native-ai-handoff")
        if ($nativeAiHandoffProbe.status -ne 'completed' -or $nativeAiHandoffProbe.data.scope -ne 'harness-only' -or
            $nativeAiHandoffProbe.data.handoffMode -ne 'rts-camera-native-ai-initialization' -or
            $nativeAiHandoffProbe.data.nativeBattleCameraCorrectionPatchInstalled -ne $true -or
            $nativeAiHandoffProbe.data.controllerBefore -ne 'Player' -or $nativeAiHandoffProbe.data.controllerAfter -ne 'AI' -or
            $nativeAiHandoffProbe.data.timeControlModeBefore -ne 'Stop' -or $nativeAiHandoffProbe.data.timeControlModeAfter -ne 'Stop' -or
            [Math]::Abs([double]$nativeAiHandoffProbe.data.campaignDayAfter - [double]$nativeAiHandoffProbe.data.campaignDayBefore) -gt 0.000001) {
            throw 'The Native MainAgent AI handoff did not enter its bounded AI lease while preserving the Campaign clock.'
        }
        $cameraBeforeHandoff = $nativeAiHandoffProbe.data.cameraBefore
        $handoffCamera = $nativeAiHandoffProbe.data.cameraAfter
        if ($null -eq $cameraBeforeHandoff -or $null -eq $handoffCamera) { throw 'Native battle camera telemetry was unavailable around the AI handoff.' }
        $cameraInitialFacingErrorRadians = [Math]::Atan2(
            [Math]::Sin([double]$handoffCamera.bearing - [double]$handoffCamera.mainAgentLookDirectionAsAngle),
            [Math]::Cos([double]$handoffCamera.bearing - [double]$handoffCamera.mainAgentLookDirectionAsAngle))
        $expectedHandoffCameraElevation = [double]$cameraBeforeHandoff.elevation
        if ($cameraBeforeHandoff.firstPerson -eq $false -and $expectedHandoffCameraElevation -lt -0.7) { $expectedHandoffCameraElevation = 0.0 }
        if ($handoffCamera.firstPerson -ne $cameraBeforeHandoff.firstPerson -or
            [Math]::Abs($cameraInitialFacingErrorRadians) -gt 0.02 -or
            [Math]::Abs([double]$handoffCamera.elevation - $expectedHandoffCameraElevation) -gt 0.01) {
            throw "Native battle camera did not align once with MainHero while preserving first-person mode and correcting only a near-vertical pitch; expected elevation=$expectedHandoffCameraElevation firstPerson=$($cameraBeforeHandoff.firstPerson), initialFacingError=$cameraInitialFacingErrorRadians, actual=$($handoffCamera | ConvertTo-Json -Compress)."
        }
        $nativeAiHandoffExpectedCameraElevation = $expectedHandoffCameraElevation
        $nativeAiHandoffCameraFrame = Capture-NativeFrame 'native-ai-battle-camera-after-handoff'
        $nativeAiCameraMotionBaseline = Invoke-AgentCli 'battleMissionStatus' @('-CommandId', "$prefix-mainhero-ai-camera-baseline-00")
        if ($nativeAiCameraMotionBaseline.data.mainAgent.controller -ne 'AI' -or $nativeAiCameraMotionBaseline.data.mainAgent.isPlayerControlled -ne $false) {
            throw 'MainHero did not enter Native AI control for the camera-motion comparison.'
        }
        $nativeAiCameraMotionSamples.Add((Add-CameraMotionSample $nativeAiCameraMotionBaseline 'mainhero-native-ai-camera' 0 $cameraMotionCapture $cameraMotionEventPath))
        $nativeAiHandoffSamples.Add([ordered]@{
            controller = [string]$nativeAiCameraMotionBaseline.data.mainAgent.controller
            health = [double]$nativeAiCameraMotionBaseline.data.mainAgent.health
            position = $nativeAiCameraMotionBaseline.data.mainAgent.position
            isPlayerTroopInFormation = $nativeAiCameraMotionBaseline.data.mainAgent.formation.isPlayerTroopInFormation
            formationAIControlled = $nativeAiCameraMotionBaseline.data.mainAgent.formation.isAIControlled
            watchState = [string]$nativeAiCameraMotionBaseline.data.mainAgent.currentWatchState
            missionMainAgentControllerActive = $nativeAiCameraMotionBaseline.data.mainAgent.missionMainAgentControllerActive
            camera = $nativeAiCameraMotionBaseline.data.camera
            nativeHandoff = $nativeAiCameraMotionBaseline.data.mainAgentAiControlLease
        })
        if ($nativeAiHandoffSamples.Count -eq 3) { $nativeAiHandoffSustainedCameraFrame = Capture-NativeFrame 'native-ai-battle-camera-sustained' }
        for ($cameraIndex = 1; $cameraIndex -le 12; $cameraIndex++) {
            Start-Sleep -Milliseconds 500
            $nativeAiCameraStatus = Invoke-AgentCli 'battleMissionStatus' @('-CommandId', "$prefix-mainhero-ai-camera-$cameraIndex")
            if ($nativeAiCameraStatus.state.context.gameState -ne 'MissionState' -or $nativeAiCameraStatus.state.mission.missionEnded -or
                $nativeAiCameraStatus.data.mainAgent.controller -ne 'AI') { break }
            $cameraSample = Add-CameraMotionSample $nativeAiCameraStatus 'mainhero-native-ai-camera' $cameraIndex $cameraMotionCapture $cameraMotionEventPath
            $nativeAiCameraMotionSamples.Add($cameraSample)
            $nativeAiHandoffSamples.Add([ordered]@{
                controller = [string]$nativeAiCameraStatus.data.mainAgent.controller
                health = [double]$nativeAiCameraStatus.data.mainAgent.health
                position = $nativeAiCameraStatus.data.mainAgent.position
                isPlayerTroopInFormation = $nativeAiCameraStatus.data.mainAgent.formation.isPlayerTroopInFormation
                formationAIControlled = $nativeAiCameraStatus.data.mainAgent.formation.isAIControlled
                watchState = [string]$nativeAiCameraStatus.data.mainAgent.currentWatchState
                missionMainAgentControllerActive = $nativeAiCameraStatus.data.mainAgent.missionMainAgentControllerActive
                camera = $nativeAiCameraStatus.data.camera
                nativeHandoff = $nativeAiCameraStatus.data.mainAgentAiControlLease
            })
            if ($nativeAiHandoffSamples.Count -eq 3) { $nativeAiHandoffSustainedCameraFrame = Capture-NativeFrame 'native-ai-battle-camera-sustained' }
        }
        $cameraMotionCaptureResult = Stop-ChronicleWindowVideoCapture -Capture $cameraMotionCapture -ContactSheetPath $cameraMotionContactPath -EventTracePath $cameraMotionEventPath
        $cameraMotionCapture = $null
        $playerControlledMainHeroSummary = Get-CameraMotionSummary $playerControlledMainHeroCameraMotionSamples.ToArray()
        $nativeAiSummary = Get-CameraMotionSummary $nativeAiCameraMotionSamples.ToArray()
        $playerControlledMainHeroNormalViewSampleCount = @($playerControlledMainHeroCameraMotionSamples | Where-Object {
            $_.camera.firstPerson -eq $true -or [double]$_.camera.elevation -ge -0.7
        }).Count
        $playerControlledMainHeroBaselineViewNormal = $playerControlledMainHeroCameraMotionSamples.Count -gt 0 -and
            $playerControlledMainHeroNormalViewSampleCount -eq $playerControlledMainHeroCameraMotionSamples.Count
        $cameraMotionComparison = [ordered]@{
            cameraBaselinePreparation = $cameraBaselinePreparation.data
            playerControlledMainHeroPlayerControlled = $playerControlledMainHeroSummary
            mainHeroNativeAi = $nativeAiSummary
            playerControlledMainHeroBaselineViewNormal = [bool]$playerControlledMainHeroBaselineViewNormal
            playerControlledMainHeroNormalViewSampleCount = $playerControlledMainHeroNormalViewSampleCount
            cameraFacingAlignmentIssueDetected = [bool]($cameraFacingYawErrorMaxRadians -gt 0.2)
            comparisonValid = [bool]($playerControlledMainHeroBaselineViewNormal -and $playerControlledMainHeroSummary.available -and $nativeAiSummary.available)
            comparisonNote = if ($playerControlledMainHeroBaselineViewNormal) { 'Player-controlled MainHero and MainHero AI samples share a non-overhead third-person baseline.' } else { 'Player-controlled MainHero samples were collected, but the source battle camera remained near-vertical, so they are not a valid normal-view comparator.' }
            playerControlledMainHeroOrderViewOpenBeforeClose = [bool]$playerControlledMainHeroOrderViewClose.data.orderViewOpenBefore
            playerControlledMainHeroOrderViewCloseStatus = [string]$playerControlledMainHeroOrderViewClose.data.status
            playerControlledMainHeroSamples = $playerControlledMainHeroCameraMotionSamples.ToArray()
            mainHeroNativeAiSamples = $nativeAiCameraMotionSamples.ToArray()
            video = [ordered]@{
                frameRate = [int]$cameraMotionCaptureResult.FrameRateTarget
                frameCount = [int]$cameraMotionCaptureResult.FrameCount
                durationSeconds = [double]$cameraMotionCaptureResult.DurationSeconds
                periodicFrameSamples = [int]($playerControlledMainHeroCameraMotionSamples.Count + $nativeAiCameraMotionSamples.Count)
                timelineFrameCount = [int]$cameraMotionCaptureResult.TimelineFrameCount
                videoRemovedAfterEvidence = [bool]$cameraMotionCaptureResult.VideoRemovedAfterEvidence
                contactSheetPath = $cameraMotionCaptureResult.ContactSheetPath
                timelineIndexPath = $cameraMotionCaptureResult.TimelineIndexPath
            }
        }
        $nativeHandoffDeadline = [DateTime]::UtcNow.AddSeconds(185)
        $nativeHandoffLeaseActive = $true
        while ([DateTime]::UtcNow -lt $nativeHandoffDeadline -and $nativeHandoffLeaseActive) {
            Start-Sleep -Milliseconds 2000
            $nativeHandoffState = Invoke-AgentCli 'state' @('-CommandId', "$prefix-native-ai-handoff-state-$([Guid]::NewGuid().ToString('N'))")
            if ($nativeHandoffState.state.context.gameState -ne 'MissionState' -or $nativeHandoffState.state.mission.missionEnded) { break }
            $nativeHandoffStatus = Invoke-AgentCli 'battleMissionStatus' @('-CommandId', "$prefix-native-ai-handoff-status-$([Guid]::NewGuid().ToString('N'))")
            if ($nativeHandoffStatus.status -ne 'completed' -or $null -eq $nativeHandoffStatus.data.mainAgent) { break }
            $nativeHandoffAgent = $nativeHandoffStatus.data.mainAgent
            $nativeAiHandoffSamples.Add([ordered]@{
                controller = [string]$nativeHandoffAgent.controller
                health = [double]$nativeHandoffAgent.health
                position = $nativeHandoffAgent.position
                isPlayerTroopInFormation = $nativeHandoffAgent.formation.isPlayerTroopInFormation
                formationAIControlled = $nativeHandoffAgent.formation.isAIControlled
                watchState = [string]$nativeHandoffAgent.currentWatchState
                missionMainAgentControllerActive = $nativeHandoffStatus.data.mainAgent.missionMainAgentControllerActive
                camera = $nativeHandoffStatus.data.camera
                nativeHandoff = $nativeHandoffStatus.data.mainAgentAiControlLease
            })
            if ($nativeAiHandoffSamples.Count -eq 3) {
                $nativeAiHandoffSustainedCameraFrame = Capture-NativeFrame 'native-ai-battle-camera-sustained'
            }
            $nativeHandoffLeaseActive = $nativeHandoffAgent.controller -eq 'AI'
        }
        if ($nativeAiHandoffSamples.Count -gt 1) {
            $handoffStart = $nativeAiHandoffSamples[0].position
            $mainAgentMovedDuringNativeAiHandoff = @($nativeAiHandoffSamples | Where-Object {
                $dx = [double]$_.position.x - [double]$handoffStart.x
                $dy = [double]$_.position.y - [double]$handoffStart.y
                $dz = [double]$_.position.z - [double]$handoffStart.z
                [Math]::Sqrt($dx * $dx + $dy * $dy + $dz * $dz) -gt 0.1
            }).Count -gt 0
        }
        $activeAiCameraSamples = @($nativeAiHandoffSamples | Where-Object controller -eq 'AI')
        $invalidCameraSamples = @($activeAiCameraSamples | Where-Object {
            $null -eq $_.camera -or $_.camera.firstPerson -ne $cameraBeforeHandoff.firstPerson -or
                ($_.camera.firstPerson -eq $false -and [double]$_.camera.elevation -lt -0.7)
        })
        $cameraFollowSamples = @($activeAiCameraSamples | Where-Object {
            $null -ne $_.camera -and $null -ne $_.camera.mainAgentLookDirectionAsAngle -and
                $null -ne $_.camera.cameraPositionZ -and $null -ne $_.camera.mainAgentPositionZ
        })
        $cameraFacingYawErrors = @($cameraFollowSamples | ForEach-Object {
            $difference = [double]$_.camera.bearing - [double]$_.camera.mainAgentLookDirectionAsAngle
            [Math]::Atan2([Math]::Sin($difference), [Math]::Cos($difference))
        })
        $cameraFacingYawErrorMaxRadians = if ($cameraFacingYawErrors.Count -gt 0) {
            ($cameraFacingYawErrors | ForEach-Object { [Math]::Abs([double]$_) } | Measure-Object -Maximum).Maximum
        } else { $null }
        $cameraVerticalOffsets = @($cameraFollowSamples | ForEach-Object {
            [double]$_.camera.cameraPositionZ - [double]$_.camera.mainAgentPositionZ
        })
        $cameraVerticalOffsetRange = if ($cameraVerticalOffsets.Count -gt 1) {
            $verticalStats = $cameraVerticalOffsets | Measure-Object -Minimum -Maximum
            [double]$verticalStats.Maximum - [double]$verticalStats.Minimum
        } else { $null }
        if ($activeAiCameraSamples.Count -lt 3 -or $invalidCameraSamples.Count -gt 0 -or $null -eq $nativeAiHandoffSustainedCameraFrame) {
            throw "Native battle camera switched view mode or returned to a near-vertical angle during AI control; targetElevation=$nativeAiHandoffExpectedCameraElevation, activeSamples=$($activeAiCameraSamples.Count), invalidSamples=$($invalidCameraSamples.Count), elevations=$(($activeAiCameraSamples | ForEach-Object { $_.camera.elevation }) -join ',')."
        }
        if ($cameraFollowSamples.Count -lt 3 -or [Math]::Abs($cameraInitialFacingErrorRadians) -gt 0.02) {
            throw "Native battle camera handoff did not establish initial MainHero-facing alignment; telemetrySamples=$($cameraFollowSamples.Count), initialFacingErrorRadians=$cameraInitialFacingErrorRadians, maximumFacingYawErrorRadians=$cameraFacingYawErrorMaxRadians, verticalOffsetRangeMeters=$cameraVerticalOffsetRange."
        }
        if ($cameraFacingYawErrorMaxRadians -gt 0.2) {
            throw "The Native camera drifted away from MainHero's facing direction during the AI lease; maximumFacingYawErrorRadians=$cameraFacingYawErrorMaxRadians."
        }
        $nativeHandoffRestoredState = Invoke-AgentCli 'battleMissionStatus' @('-CommandId', "$prefix-native-ai-handoff-restored-status")
        if ($nativeHandoffRestoredState.status -eq 'completed' -and (
            $nativeHandoffRestoredState.data.mainAgent.controller -ne 'Player' -or
            $nativeHandoffRestoredState.data.mainAgent.missionMainAgentControllerActive -ne $statusAfter.data.mainAgent.missionMainAgentControllerActive)) {
            throw 'Native MainAgent AI handoff did not restore Player control and the original MissionMainAgentController state before battle aftermath.'
        }
        if ($nativeHandoffRestoredState.status -eq 'completed' -and
            $nativeHandoffRestoredState.state.context.gameState -eq 'MissionState' -and
            $nativeHandoffRestoredState.state.mission.missionEnded -eq $false -and (
            $nativeHandoffRestoredState.data.camera.firstPerson -ne $statusAfter.data.camera.firstPerson -or
            [Math]::Abs([double]$nativeHandoffRestoredState.data.camera.elevation - [double]$statusAfter.data.camera.elevation) -gt 0.01 -or
            [Math]::Abs([Math]::Atan2(
                [Math]::Sin([double]$nativeHandoffRestoredState.data.camera.bearing - [double]$statusAfter.data.camera.bearing),
                [Math]::Cos([double]$nativeHandoffRestoredState.data.camera.bearing - [double]$statusAfter.data.camera.bearing))) -gt 0.01)) {
            throw 'Native MainAgent AI handoff changed the original third-person camera view after returning control while the Mission remained active.'
        }
    }

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
                lease = $controllerProbeStatus.data.mainAgentAiControlLease
            })
            if ($controllerProbeStatus.data.mainAgentAiControlLease.active -ne $true) { break }
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
            if ($surrogateProbeStatus.status -ne 'completed' -or $null -eq $surrogateProbeStatus.data.mainAgentAiControlLease.ownerPosition) { break }
            $probe = $surrogateProbeStatus.data.mainAgentAiControlLease
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
        desktopInputIsolationPassed = $desktopInputIsolationPassed
        missionWindowSafety = $missionWindowSafety
        harnessInputOwnershipConfirmed = $inputOwnershipConfirmed
        initialParty = [ordered]@{ members = $encounterMenu.state.party.members; healthy = $encounterMenu.state.party.healthy; wounded = $encounterMenu.state.party.wounded; morale = $encounterMenu.state.party.morale }
        opponentPartyId = $targetId
        sendTroopsWasUnavailable = ($sendTroops.Count -eq 0)
        hostFallbackEligible = ($sendTroops.Count -eq 0)
        nativeAttackWasAvailable = ($attack.Count -eq 1)
        mainAgentFormationBeforeDelegate = $mainAgentBefore
        mainAgentFormationAfterDelegate = $mainAgentAfter
        mainAgentFormationAiBehavior = $mainAgentAfter.formation
        delegation = $delegation.data
        nativeAutoDeploy = if ($deploymentAutoDeploy) { $deploymentAutoDeploy.data } else { $null }
        nativeDeploymentFinish = if ($deploymentFinish) { $deploymentFinish.data } else { $null }
        cameraBeforeHandoff = $statusBefore.data.camera
        cameraAfterTroopDelegation = $statusAfter.data.camera
        nativeAiHandoffCameraFrame = if ($nativeAiHandoffCameraFrame) { [ordered]@{ path = $nativeAiHandoffCameraFrame; sha256 = (Get-FileHash -LiteralPath $nativeAiHandoffCameraFrame -Algorithm SHA256).Hash } } else { $null }
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
        nativeAiHandoffProbe = if ($nativeAiHandoffProbe) { $nativeAiHandoffProbe.data } else { $null }
        playerControlledMainHeroOrderViewClose = if ($playerControlledMainHeroOrderViewClose) { $playerControlledMainHeroOrderViewClose.data } else { $null }
        cameraMotionComparison = $cameraMotionComparison
        nativeAiHandoffExpectedCameraElevation = $nativeAiHandoffExpectedCameraElevation
        cameraInitialFacingErrorRadians = $cameraInitialFacingErrorRadians
        cameraFacingYawErrorMaxRadians = $cameraFacingYawErrorMaxRadians
        cameraVerticalOffsetRangeMeters = $cameraVerticalOffsetRange
        nativeAiHandoffSustainedCameraFrame = if ($nativeAiHandoffSustainedCameraFrame) { [ordered]@{ path = $nativeAiHandoffSustainedCameraFrame; sha256 = (Get-FileHash -LiteralPath $nativeAiHandoffSustainedCameraFrame -Algorithm SHA256).Hash } } else { $null }
        nativeAiHandoffSamples = $nativeAiHandoffSamples.ToArray()
        mainAgentMovedDuringNativeAiHandoff = $mainAgentMovedDuringNativeAiHandoff
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
    $result['passed'] = $desktopInputIsolationPassed -and $inputOwnershipConfirmed -and $result.mapStateDeploymentFinishRejected -and $result.mapStateDeploymentFinishPreservedState -and
        $result.duplicateDeploymentFinishRejected -and $result.duplicateDeploymentFinishPreservedState -and
        $result.sourceSaveUnchanged -and $result.disposableSaveRemoved -and $result.processStopped -and $result.missionEnded -and $result.postBattleGameState -ne 'MissionState'
    $json = ConvertTo-Json -InputObject $result -Depth 10
    [IO.File]::WriteAllText((Join-Path $runDirectory ($probeName + '.json')), $json, [Text.UTF8Encoding]::new($false))
    $json
    if (-not $result.passed) { exit 1 }
}
finally {
    if ($cameraMotionCapture) {
        try {
            $cameraMotionCaptureResult = Stop-ChronicleWindowVideoCapture -Capture $cameraMotionCapture -ContactSheetPath (Join-Path $runDirectory 'NativeAiHandoffCameraMotion-contact.jpg') -EventTracePath (Join-Path $runDirectory 'NativeAiHandoffCameraMotion-events.jsonl')
        }
        catch { }
        $cameraMotionCapture = $null
    }
    if ($hostBattleCameraCapture) {
        try {
            $hostBattleCameraCaptureResult = Stop-ChronicleWindowVideoCapture -Capture $hostBattleCameraCapture -ContactSheetPath (Join-Path $runDirectory 'HostNativeBattleCamera-contact.jpg') -EventTracePath (Join-Path $runDirectory 'HostNativeBattleCamera-events.jsonl')
        }
        catch { }
        $hostBattleCameraCapture = $null
    }
    if ($null -eq $priorMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $priorMode }
    if ($null -eq $priorInputLock) { Remove-Item Env:CHRONICLE_HARNESS_AGENT_INPUT_LOCK -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_AGENT_INPUT_LOCK = $priorInputLock }
    if (Test-Path -LiteralPath $sessionPath) { try { Invoke-AgentCli 'stop' | Out-Null } catch { } }
    if ($disposableSaveOwned -and (Test-Path -LiteralPath $disposableSavePath -PathType Leaf) -and $null -ne $disposableSaveHash) {
        $currentDisposableHash = (Get-FileHash -LiteralPath $disposableSavePath -Algorithm SHA256).Hash
        if ($currentDisposableHash -eq $disposableSaveHash) { Remove-Item -LiteralPath $disposableSavePath }
    }
}
