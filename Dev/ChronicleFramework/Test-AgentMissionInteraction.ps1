[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [ValidateRange(30, 300)][int]$ArrivalTimeoutSeconds = 180,
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$runDirectory = if ($env:CHRONICLE_HARNESS_TEMP) { Split-Path -Parent $env:CHRONICLE_HARNESS_TEMP } else { Join-Path $PSScriptRoot 'TestResults\ManualMissionInteraction' }
$captureTempPath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP 'MissionInteraction-frame.bmp' } else { Join-Path $runDirectory 'MissionInteraction-frame.bmp' }
$capturePath = Join-Path $runDirectory 'MissionInteraction-frame.bmp'
$resultPath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP 'MissionInteractionResult.json' } else { Join-Path $runDirectory 'MissionInteractionResult.json' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$commandPrefix = 'mission-interaction-' + (Get-Date -Format 'yyyyMMddHHmmssfff')
$diagnosticStep = 'preflight'

if (-not (Test-Path -LiteralPath $savePath)) { throw "Mission interaction fixture not found: $LoadSaveName" }
if (Get-Process -Name Bannerlord -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

function Get-TargetSceneAgent($State, [int]$AgentIndex) {
    return @($State.state.mission.nearbySceneAgents | Where-Object { [int]$_.agentIndex -eq $AgentIndex } | Select-Object -First 1)
}

try {
    $diagnosticStep = 'load disposable save'
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $initial = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-initial")
    if ($initial.state.context.gameState -ne 'MapState') { throw "Mission interaction fixture must start on Campaign Map; got $($initial.state.context.gameState)." }

    $settlement = @($initial.state.nearbySettlements | Where-Object { $_.type -eq 'town' -and -not $_.hostile } | Sort-Object distance | Select-Object -First 1)
    if ($settlement.Count -ne 1) { throw 'No visible non-hostile town exists in the disposable fixture.' }
    $move = Invoke-AgentCli 'move' @('-SettlementId', [string]$settlement[0].id, '-CommandId', "$commandPrefix-move")
    if ($move.status -ne 'completed' -or $move.state.location.targetSettlementId -ne $settlement[0].id) { throw 'Native Campaign map movement did not accept the visible town target.' }

    $arrivalDeadline = [DateTime]::UtcNow.AddSeconds($ArrivalTimeoutSeconds)
    $arrived = $null
    while ([DateTime]::UtcNow -lt $arrivalDeadline) {
        $arrived = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-arrival-$([Guid]::NewGuid().ToString('N'))") 30
        if ($arrived.state.location.currentSettlementId -eq $settlement[0].id -and $arrived.state.context.menuId -eq 'town') { break }
        if ($arrived.state.context.encounterActive -and $arrived.state.context.encounteredPartyId -ne $settlement[0].id) { throw "Unexpected encounter '$($arrived.state.context.encounteredPartyId)' interrupted travel." }
        if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'Game process exited during natural travel to the town.' }
        Start-Sleep -Milliseconds 500
    }
    if (-not $arrived -or $arrived.state.location.currentSettlementId -ne $settlement[0].id -or $arrived.state.context.menuId -ne 'town') { throw "Natural travel did not enter the town within $ArrivalTimeoutSeconds seconds." }

    $backstreetOption = @($arrived.state.availableMenuOptions | Where-Object { $_.id -eq 'town_backstreet' -and $_.available -and $_.enabled })
    if ($backstreetOption.Count -ne 1) { throw 'Native Town menu did not expose an enabled Tavern district option.' }
    $backstreet = Invoke-AgentCli 'menuSelect' @('-MenuId', 'town', '-OptionId', 'town_backstreet', '-CommandId', "$commandPrefix-backstreet")
    if ($backstreet.state.context.menuId -ne 'town_backstreet' -or $backstreet.state.context.gameState -ne 'MapState') { throw 'Native Town menu option did not enter town_backstreet.' }
    $tavernOption = @($backstreet.state.availableMenuOptions | Where-Object { $_.id -eq 'town_tavern' -and $_.available -and $_.enabled })
    if ($tavernOption.Count -ne 1) { throw 'Native Tavern district menu did not expose an enabled Visit Tavern option.' }
    $mission = Invoke-AgentCli 'menuSelect' @('-MenuId', 'town_backstreet', '-OptionId', 'town_tavern', '-CommandId', "$commandPrefix-enter-tavern")
    if ($mission.state.context.gameState -ne 'MissionState') { throw "Native Visit Tavern option did not create MissionState; got '$($mission.state.context.gameState)'." }

    $missionDeadline = [DateTime]::UtcNow.AddSeconds(60)
    while ((-not $mission.state.mission -or -not $mission.state.mission.mainAgent) -and [DateTime]::UtcNow -lt $missionDeadline) {
        if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'Game process exited while the Tavern scene was loading.' }
        Start-Sleep -Milliseconds 500
        $mission = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-ready-$([Guid]::NewGuid().ToString('N'))") 30
    }
    if (-not $mission.state.mission -or -not $mission.state.mission.mainAgent) { throw 'The Tavern scene failed to expose an active player MainAgent.' }
    if ($mission.state.context.timeControlMode -ne 'Stop') { throw "Campaign clock was not stopped in Tavern MissionState: $($mission.state.context.timeControlMode)." }

    $diagnosticStep = 'select local RansomBroker Agent'
    $mainAgentPosition = $mission.state.mission.mainAgent.position
    $targetBefore = @($mission.state.mission.nearbySceneAgents | Where-Object { $_.characterId -eq 'ransom_broker_vlandia' -and -not $_.isEnemy -and $_.distance -gt 1.8 -and [Math]::Abs([double]$_.position.z - [double]$mainAgentPosition.z) -le 1.5 } | Sort-Object distance | Select-Object -First 1)
    if ($targetBefore.Count -ne 1) { throw 'Tavern Mission exposed no friendly local RansomBroker Agent within bounded interaction range.' }
    $targetAgentIndex = [int]$targetBefore[0].agentIndex
    $targetCharacterId = [string]$targetBefore[0].characterId
    $targetHeroId = [string]$targetBefore[0].heroId
    $approachState = $mission
    $targetNear = $targetBefore
    $approachSteps = 0
    $diagnosticStep = 'approach local RansomBroker using bounded inputs'
    $approachDeadline = [DateTime]::UtcNow.AddSeconds(20)
    while ([DateTime]::UtcNow -lt $approachDeadline -and $approachSteps -lt 32) {
        $targetNear = @($approachState.state.mission.nearbySceneAgents | Where-Object { [int]$_.agentIndex -eq $targetAgentIndex } | Select-Object -First 1)
        if ($targetNear.Count -ne 1 -or $targetNear[0].isEnemy) {
            $currentIndices = @($approachState.state.mission.nearbySceneAgents | ForEach-Object { [string]$_.agentIndex }) -join ','
            throw "Selected RansomBroker AgentIndex $targetAgentIndex is not currently observed; local IDs: $currentIndices"
        }
        if ([double]$targetNear[0].distance -le 1.8) { break }
        $mainAgent = $approachState.state.mission.mainAgent
        $forwardX = [double]$mainAgent.lookDirection.x
        $forwardY = [double]$mainAgent.lookDirection.y
        $forwardLength = [Math]::Sqrt($forwardX * $forwardX + $forwardY * $forwardY)
        if ($forwardLength -lt 0.01) { throw 'MainAgent look direction is degenerate during Tavern approach.' }
        $forwardX /= $forwardLength
        $forwardY /= $forwardLength
        $deltaX = [double]$targetNear[0].position.x - [double]$mainAgent.position.x
        $deltaY = [double]$targetNear[0].position.y - [double]$mainAgent.position.y
        $axisX = ($deltaX * $forwardY) - ($deltaY * $forwardX)
        $axisY = ($deltaX * $forwardX) + ($deltaY * $forwardY)
        $axisLength = [Math]::Sqrt($axisX * $axisX + $axisY * $axisY)
        if ($axisLength -lt 0.01) { throw 'Observed Tavern HeroAgent has no horizontal approach direction.' }
        $moveStep = Invoke-AgentCli 'missionInput' @('-X', [string]($axisX / $axisLength), '-Y', [string]($axisY / $axisLength), '-DurationSeconds', '0.35', '-CommandId', "$commandPrefix-approach-$approachSteps")
        if ($moveStep.status -ne 'completed') { throw 'Native bounded Mission movement input was rejected during NPC approach.' }
        Start-Sleep -Milliseconds 300
        $approachState = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-approach-state-$approachSteps") 30
        $approachSteps++
    }
    $diagnosticStep = 'validate native interaction radius'
    if ($targetNear.Count -ne 1 -or [double]$targetNear[0].distance -gt 1.8) { throw 'Bounded native movement did not approach the selected RansomBroker into the original conversation action radius.' }

    $diagnosticStep = 'reject invalid AgentIndex'
    $invalid = Invoke-AgentCli 'missionInteract' @('-AgentIndex', '2147483647', '-CommandId', "$commandPrefix-invalid")
    $afterInvalid = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-after-invalid")
    $invalidRejectedNoConversation = (
        $invalid.status -eq 'rejected' -and
        $afterInvalid.state.context.gameState -eq 'MissionState' -and
        -not $afterInvalid.state.context.conversation
    )

    $diagnosticStep = 'start conversation through native Agent.OnUse'
    $interact = Invoke-AgentCli 'missionInteract' @('-AgentIndex', [string]$targetNear[0].agentIndex, '-CommandId', "$commandPrefix-interact")
    $afterInteract = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-after-interact")
    $conversation = $afterInteract.state.context.conversation
    $conversationIdentityMatches = if ($targetHeroId) {
        [string]$conversation.heroId -eq $targetHeroId -and [string]$interact.data.targetHeroId -eq $targetHeroId -and [string]$interact.data.conversationHeroId -eq $targetHeroId
    } else {
        $null -eq $conversation.heroId -and $null -eq $interact.data.targetHeroId -and $null -eq $interact.data.conversationHeroId
    }
    $conversationTargetMatches = (
        $interact.status -eq 'completed' -and [bool]$interact.data.conversationStarted -and
        $afterInteract.state.context.gameState -eq 'MissionState' -and
        [string]$interact.data.targetCharacterId -eq $targetCharacterId -and [bool]$conversationIdentityMatches
    )

    $diagnosticStep = 'capture active native conversation frame'
    $screenshot = Invoke-AgentCli 'captureFrame' @('-OutputPath', $captureTempPath, '-CommandId', "$commandPrefix-capture") 30
    $captureDeadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path -LiteralPath $captureTempPath) -and [DateTime]::UtcNow -lt $captureDeadline) { Start-Sleep -Milliseconds 100 }
    if ($screenshot.status -ne 'completed' -or -not (Test-Path -LiteralPath $captureTempPath) -or (Get-Item -LiteralPath $captureTempPath).Length -lt 4096) { throw 'Engine-native screenshot of the active conversation was not produced.' }
    if ($env:CHRONICLE_HARNESS_TEMP) { Move-Item -LiteralPath $captureTempPath -Destination $capturePath -Force }

    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-stop") 30
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $result = [ordered]@{
        ProcessId = $start.session.processId
        Settlement = $settlement[0]
        Entry = [ordered]@{ TavernScene = $mission.state.mission.sceneName; MainAgent = $mission.state.mission.mainAgent; SelectedTarget = $targetBefore[0]; TargetAfterApproach = $targetNear[0]; ApproachSteps = $approachSteps }
        InvalidAgentStatus = [string]$invalid.status
        InvalidRejectedWithoutConversation = [bool]$invalidRejectedNoConversation
        InteractionReceipt = $interact.data
        Conversation = $conversation
        ConversationTargetMatches = [bool]$conversationTargetMatches
        CampaignDayBefore = $mission.campaignDay
        CampaignDayAfterInteraction = $afterInteract.campaignDay
        CampaignClockUnchanged = ($mission.campaignDay -eq $afterInteract.campaignDay -and $mission.state.context.timeControlMode -eq $afterInteract.state.context.timeControlMode)
        EngineScreenshot = $capturePath
        FixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = [bool]$stop.processStopped
    }
    $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    $assertions = [ordered]@{
        InNativeTavernMission = ($mission.state.context.gameState -eq 'MissionState' -and $mission.state.mission.sceneName -like '*tavern*')
        TargetFromCurrentLocalObservation = ($targetBefore[0].agentIndex -ge 0 -and $targetNear[0].agentIndex -eq $targetBefore[0].agentIndex -and $targetNear[0].distance -le 1.8)
        InvalidAgentRejectedWithoutConversation = [bool]$invalidRejectedNoConversation
        NativeOnUseStartsObservedTargetConversation = ([string]$interact.data.nativeEntry -eq 'Agent.OnUse' -and [bool]$conversationTargetMatches)
        CampaignClockUnchanged = [bool]$result.CampaignClockUnchanged
        EngineScreenshotCaptured = (Test-Path -LiteralPath $capturePath)
        FixtureUnchanged = [bool]$result.FixtureUnchanged
        ProcessStopped = [bool]$result.ProcessStopped
    }
    $failedAssertions = @($assertions.Keys | Where-Object { -not [bool]$assertions[$_] })
    $result | Add-Member -NotePropertyName Assertions -NotePropertyValue $assertions
    $result | Add-Member -NotePropertyName FailedAssertions -NotePropertyValue $failedAssertions
    $result | Add-Member -NotePropertyName Passed -NotePropertyValue ($failedAssertions.Count -eq 0)
    $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    $result | ConvertTo-Json -Depth 10
    if ($failedAssertions.Count -gt 0) { throw 'Native local Mission Agent interaction did not start the target dialogue or preserve location/time/fixture boundaries.' }
}
catch {
    throw "MissionInteraction test failed during '$diagnosticStep': $($_.Exception.Message)"
}
finally {
    if (Test-Path $sessionPath) {
        try { Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-cleanup") 20 | Out-Null } catch { }
    }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
