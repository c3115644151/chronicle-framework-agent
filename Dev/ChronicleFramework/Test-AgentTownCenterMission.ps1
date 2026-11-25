#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$decisionLoop = Join-Path $PSScriptRoot 'Agent-DecisionLoop.ps1'
$decisionProvider = Join-Path $PSScriptRoot 'Test-AgentLoopProvider.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$runDirectory = if ($env:CHRONICLE_HARNESS_TEMP) { Split-Path -Parent $env:CHRONICLE_HARNESS_TEMP } else { Join-Path $PSScriptRoot 'TestResults\ManualTownCenterMission' }
$captureTempPath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP 'TownCenterMission-frame.bmp' } else { Join-Path $runDirectory 'TownCenterMission-frame.bmp' }
$capturePath = Join-Path $runDirectory 'TownCenterMission-frame.bmp'
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$commandPrefix = 'town-center-' + (Get-Date -Format 'yyyyMMddHHmmssfff')

if (-not (Test-Path -LiteralPath $savePath)) { throw "Town center Mission fixture not found: $savePath" }
if (Get-Process -Name Bannerlord -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $output = & $HarnessPowerShell -NoProfile -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

function Invoke-DecisionLoop([string]$Mode, [int]$DecisionCount, [string]$Prefix) {
    $previousMode = $env:CHRONICLE_TEST_PROVIDER_MODE
    $env:CHRONICLE_TEST_PROVIDER_MODE = $Mode
    try {
        $output = & $HarnessPowerShell -NoProfile -File $decisionLoop -DecisionProviderPath $decisionProvider -MaxDecisions $DecisionCount -TimeoutSeconds $TimeoutSeconds -CommandPrefix $Prefix 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "Decision loop '$Mode' failed: $output" }
        try { return $output | ConvertFrom-Json }
        catch { throw "Decision loop '$Mode' returned invalid JSON: $output" }
    }
    finally {
        if ($null -eq $previousMode) { Remove-Item Env:CHRONICLE_TEST_PROVIDER_MODE -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_TEST_PROVIDER_MODE = $previousMode }
    }
}

try {
    if ($env:CHRONICLE_HARNESS_MODE -ne 'visual-capture') { $env:CHRONICLE_HARNESS_MODE = 'visual-capture' }
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $initial = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-initial")
    if ($initial.state.context.gameState -ne 'MapState') { throw "Town center fixture must start on campaign map; got $($initial.state.context.gameState)." }

    $town = @($initial.state.nearbySettlements | Where-Object { $_.id -eq 'town_V1' -and $_.type -eq 'town' -and -not $_.hostile } | Select-Object -First 1)
    if ($town.Count -ne 1) { throw 'Sargot is not currently a safe visible town target in the disposable fixture.' }
    $move = Invoke-AgentCli 'move' @('-SettlementId', 'town_V1', '-CommandId', "$commandPrefix-move")
    if ($move.status -ne 'completed' -or $move.state.location.targetSettlementId -ne 'town_V1') { throw 'Native campaign movement did not accept the Town center test target.' }

    $arrivalDeadline = [DateTime]::UtcNow.AddSeconds(120)
    $arrived = $null
    while ([DateTime]::UtcNow -lt $arrivalDeadline) {
        $arrived = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-arrival-$([Guid]::NewGuid().ToString('N'))") 30
        if ($arrived.state.location.currentSettlementId -eq 'town_V1' -and $arrived.state.context.menuId -eq 'town') { break }
        if ($arrived.state.context.encounterActive -and $arrived.state.context.encounteredPartyId -ne 'town_V1') {
            throw "Unexpected encounter '$($arrived.state.context.encounteredPartyId)' interrupted Town center travel."
        }
        if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'Game process exited during natural Town center travel.' }
        Start-Sleep -Milliseconds 500
    }
    if (-not $arrived -or $arrived.state.location.currentSettlementId -ne 'town_V1' -or $arrived.state.context.menuId -ne 'town') { throw 'Natural campaign travel did not reach the Town menu.' }
    if ($arrived.state.schemaVersion -ne 20) { throw "Town menu observation schema changed unexpectedly: $($arrived.state.schemaVersion)." }

    $centerOption = @($arrived.state.availableMenuOptions | Where-Object { $_.id -eq 'town_streets' -and $_.available -and $_.enabled })
    if ($centerOption.Count -ne 1) { throw 'Native Town menu does not expose an enabled town_streets option.' }
    if ($null -eq $centerOption[0].PSObject.Properties['questMarkerFlags'] -or $null -eq $centerOption[0].PSObject.Properties['questMarkerNames']) { throw 'Native Town menu observation omitted the original issue/quest marker flags.' }
    $enter = Invoke-AgentCli 'menuSelect' @('-MenuId', 'town', '-OptionId', 'town_streets', '-CommandId', "$commandPrefix-enter-center")
    if ($enter.status -ne 'completed' -or $enter.state.context.gameState -ne 'MissionState') { throw 'Native town_streets option did not enter MissionState.' }

    $sceneDeadline = [DateTime]::UtcNow.AddSeconds(60)
    $center = $enter
    while ((!$center.state.mission -or !$center.state.mission.mainAgent) -and [DateTime]::UtcNow -lt $sceneDeadline) {
        if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'Game process exited while the Town center Scene was loading.' }
        Start-Sleep -Milliseconds 500
        $center = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-scene-ready-$([Guid]::NewGuid().ToString('N'))") 30
    }
    if (-not $center.state.mission.mainAgent -or $center.state.mission.sceneName -notmatch '_town_') { throw 'Native Town center Mission/MainAgent was not available after menu transition.' }
    Start-Sleep -Seconds 3
    $center = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-center-stable")
    if ($center.state.context.timeControlMode -ne 'Stop') { throw "Campaign time was not stopped in Town center Mission: $($center.state.context.timeControlMode)." }
    $initialMissionDiagnostics = Invoke-AgentCli 'harnessMissionDiagnostics' @('-CommandId', "$commandPrefix-initial-harness-mission-diagnostics") 30
    if ($initialMissionDiagnostics.status -ne 'completed' -or -not $initialMissionDiagnostics.data) { throw 'Initial Harness-only Mission Notable diagnostics did not complete.' }
    $activeIssueNotables = @($initialMissionDiagnostics.data.notableAgents | Where-Object { $_.hasIssue })
    $nearestActiveIssueNotableDistance = if ($activeIssueNotables.Count -gt 0) { ($activeIssueNotables | Measure-Object -Property distance -Minimum).Minimum } else { $null }
    $diagnosticOnlyReason = if ($initialMissionDiagnostics.data.campaignLocationId -ne 'center') {
        'The active Mission is not the native center Location.'
    }
    elseif ([int]$initialMissionDiagnostics.data.locationIssueOwnerCount -eq 0) {
        'The active center Location has no registered Issue owner, despite the menu marker; investigate the source/runtime mismatch instead of walking.'
    }
    elseif ($activeIssueNotables.Count -eq 0) {
        'The center Location has an Issue owner in its roster, but no active Issue Notable Agent is instantiated in this Mission.'
    }
    elseif ([double]$nearestActiveIssueNotableDistance -gt 12.0) {
        'An active Issue Notable is instantiated in the Mission but outside the Agent local observation radius; use the native encounter/visit affordance rather than extending a blind walk.'
    }
    if ($diagnosticOnlyReason) {
        $diagnosticStop = Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-diagnostic-only-stop") 30
        $diagnosticFixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
        $diagnosticResult = [ordered]@{
            ProcessId = $start.session.processId
            Status = 'diagnostics-only-classified-entry'
            Reason = $diagnosticOnlyReason
            MenuOption = $centerOption[0]
            QuestMarkerObservation = [ordered]@{ NativeFlags = $centerOption[0].questMarkerFlags; Names = $centerOption[0].questMarkerNames }
            Scene = [ordered]@{ SceneName = $center.state.mission.sceneName; LocationId = $initialMissionDiagnostics.data.campaignLocationId; CampaignTimeMode = $center.state.context.timeControlMode }
            InitialHarnessOnlyMissionDiagnostics = $initialMissionDiagnostics.data
            NearestActiveIssueNotableDistance = $nearestActiveIssueNotableDistance
            IssueNotableWithinLocalObservation = ($null -ne $nearestActiveIssueNotableDistance -and [double]$nearestActiveIssueNotableDistance -le 12.0)
            ProductPathVerified = $false
            FixtureUnchanged = ($fixtureHashBefore -eq $diagnosticFixtureHashAfter)
            ProcessStopped = $diagnosticStop.processStopped
            Passed = ($center.state.mission.sceneName -match '_town_' -and $center.state.context.timeControlMode -eq 'Stop' -and $diagnosticStop.processStopped -and $fixtureHashBefore -eq $diagnosticFixtureHashAfter)
        }
        $diagnosticJson = $diagnosticResult | ConvertTo-Json -Depth 14
        if ($env:CHRONICLE_HARNESS_TEMP -and (Test-Path -LiteralPath $env:CHRONICLE_HARNESS_TEMP -PathType Container)) {
            Set-Content -LiteralPath (Join-Path $env:CHRONICLE_HARNESS_TEMP 'TownCenterMissionResult.json') -Value $diagnosticJson -Encoding UTF8
        }
        $diagnosticJson
        if (-not $diagnosticResult.Passed) { throw 'Harness-only initial location diagnostic did not preserve the fixture and cleanly stop the game.' }
        return
    }

    $loop = Invoke-DecisionLoop 'townExplore' 60 "$commandPrefix-explore-loop"
    $stepSummary = @($loop.trace | ForEach-Object {
        [ordered]@{
            Iteration = $_.iteration
            Action = $_.decision.action
            Arguments = $_.decision.arguments
            ReceiptStatus = $_.actionReceipt.status
            PositionBefore = $_.observationBefore.state.mission.mainAgent.position
            NearbySceneAgentCountBefore = @($_.observationBefore.state.mission.nearbySceneAgents).Count
            PositionAfter = $_.observationAfter.state.mission.mainAgent.position
            NearbySceneAgentCountAfter = @($_.observationAfter.state.mission.nearbySceneAgents).Count
        }
    })
    Start-Sleep -Seconds 1
    $afterExplore = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-after-exploration")
    $positionBefore = $center.state.mission.mainAgent.position
    $positionAfter = $afterExplore.state.mission.mainAgent.position
    $explorationDistance = [Math]::Sqrt([Math]::Pow(([double]$positionAfter.x - [double]$positionBefore.x), 2) + [Math]::Pow(([double]$positionAfter.y - [double]$positionBefore.y), 2) + [Math]::Pow(([double]$positionAfter.z - [double]$positionBefore.z), 2))
    $inputCleared = ([Math]::Abs([double]$afterExplore.state.mission.mainAgent.movementInput.x) -lt 0.001 -and [Math]::Abs([double]$afterExplore.state.mission.mainAgent.movementInput.y) -lt 0.001)
    $localAgentCount = @($afterExplore.state.mission.nearbySceneAgents).Count
    $navigationCandidate = @($afterExplore.state.mission.nearbySceneAgents | Where-Object { -not $_.isEnemy -and $_.distance -gt 2.0 } | Sort-Object distance | Select-Object -First 1)
    $navigationReceipt = $null
    $navigationStart = $afterExplore
    $navigationEnd = $afterExplore
    $navigationError = $null
    if ($navigationCandidate.Count -eq 1) {
        try {
            $navigationReceipt = Invoke-AgentCli 'missionNavigateToAgent' @('-AgentIndex', [string]$navigationCandidate[0].agentIndex, '-CommandId', "$commandPrefix-native-path") 30
            $navigationDeadline = [DateTime]::UtcNow.AddSeconds(9)
            while ([DateTime]::UtcNow -lt $navigationDeadline) {
                Start-Sleep -Milliseconds 500
                $navigationEnd = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-native-path-state-$([Guid]::NewGuid().ToString('N'))") 30
                if (-not $navigationEnd.state.mission.navigation -or -not $navigationEnd.state.mission.navigation.active) { break }
            }
        }
        catch { $navigationError = $_.Exception.Message }
    }
    $navigationStartPosition = $navigationStart.state.mission.mainAgent.position
    $navigationEndPosition = $navigationEnd.state.mission.mainAgent.position
    $navigationMovementDistance = [Math]::Sqrt([Math]::Pow(([double]$navigationEndPosition.x - [double]$navigationStartPosition.x), 2) + [Math]::Pow(([double]$navigationEndPosition.y - [double]$navigationStartPosition.y), 2) + [Math]::Pow(([double]$navigationEndPosition.z - [double]$navigationStartPosition.z), 2))
    $navigationFollowUpCandidate = @()
    $navigationFollowUpReceipt = $null
    $navigationFollowUpStart = $navigationEnd
    $navigationFollowUpEnd = $navigationEnd
    $navigationFollowUpError = $null
    if ($navigationCandidate.Count -eq 1) {
        $navigationFollowUpCandidate = @($navigationEnd.state.mission.nearbySceneAgents | Where-Object { [int]$_.agentIndex -eq [int]$navigationCandidate[0].agentIndex -and -not $_.isEnemy -and $_.distance -gt 2.0 } | Select-Object -First 1)
        if ($navigationFollowUpCandidate.Count -eq 1) {
            try {
                $navigationFollowUpReceipt = Invoke-AgentCli 'missionNavigateToAgent' @('-AgentIndex', [string]$navigationFollowUpCandidate[0].agentIndex, '-CommandId', "$commandPrefix-native-path-follow-up") 30
                $navigationFollowUpDeadline = [DateTime]::UtcNow.AddSeconds(9)
                while ([DateTime]::UtcNow -lt $navigationFollowUpDeadline) {
                    Start-Sleep -Milliseconds 500
                    $navigationFollowUpEnd = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-native-path-follow-up-state-$([Guid]::NewGuid().ToString('N'))") 30
                    if (-not $navigationFollowUpEnd.state.mission.navigation -or -not $navigationFollowUpEnd.state.mission.navigation.active) { break }
                }
            }
            catch { $navigationFollowUpError = $_.Exception.Message }
        }
    }
    $navigationFollowUpStartPosition = $navigationFollowUpStart.state.mission.mainAgent.position
    $navigationFollowUpEndPosition = $navigationFollowUpEnd.state.mission.mainAgent.position
    $navigationFollowUpMovementDistance = [Math]::Sqrt([Math]::Pow(([double]$navigationFollowUpEndPosition.x - [double]$navigationFollowUpStartPosition.x), 2) + [Math]::Pow(([double]$navigationFollowUpEndPosition.y - [double]$navigationFollowUpStartPosition.y), 2) + [Math]::Pow(([double]$navigationFollowUpEndPosition.z - [double]$navigationFollowUpStartPosition.z), 2))
    $afterNavigation = $navigationFollowUpEnd
    $nativeFocusAfterApproach = $afterNavigation.state.mission.nativeFocus
    $expectedFocusAgentIndex = if ($navigationFollowUpCandidate.Count -eq 1) { [int]$navigationFollowUpCandidate[0].agentIndex } elseif ($navigationCandidate.Count -eq 1) { [int]$navigationCandidate[0].agentIndex } else { $null }
    $focusMatchesApproachTarget = ($null -ne $expectedFocusAgentIndex -and $nativeFocusAfterApproach.agent -and [int]$nativeFocusAfterApproach.agent.agentIndex -eq $expectedFocusAgentIndex)
    $aimCandidate = @($afterNavigation.state.mission.nearbySceneAgents | Where-Object { -not $_.isEnemy -and $_.occupation -ne 'Soldier' } | Sort-Object distance | Select-Object -First 1)
    $aimReceipt = $null
    $aimTargetAgentIndex = $null
    $afterAim = $afterNavigation
    $focusMatchesTarget = $false
    $aimError = $null
    if ($aimCandidate.Count -eq 1) {
        $aimTargetAgentIndex = [int]$aimCandidate[0].agentIndex
        try {
            $aimReceipt = Invoke-AgentCli 'missionAimAt' @('-AgentIndex', [string]$aimTargetAgentIndex, '-CommandId', "$commandPrefix-location-aim") 30
            Start-Sleep -Milliseconds 500
            $afterAim = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-after-location-aim")
            $focusMatchesTarget = ($afterAim.state.mission.nativeFocus.agent -and [int]$afterAim.state.mission.nativeFocus.agent.agentIndex -eq $aimTargetAgentIndex)
        }
        catch { $aimError = $_.Exception.Message }
    }

    $missionDiagnostics = Invoke-AgentCli 'harnessMissionDiagnostics' @('-CommandId', "$commandPrefix-harness-mission-diagnostics") 30
    if ($missionDiagnostics.status -ne 'completed' -or -not $missionDiagnostics.data) { throw 'Harness-only Mission Notable diagnostics did not complete.' }

    $screenshot = Invoke-AgentCli 'captureFrame' @('-OutputPath', $captureTempPath, '-CommandId', "$commandPrefix-capture") 30
    $captureDeadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path -LiteralPath $captureTempPath) -and [DateTime]::UtcNow -lt $captureDeadline) { Start-Sleep -Milliseconds 100 }
    if ($screenshot.status -ne 'completed' -or -not (Test-Path -LiteralPath $captureTempPath) -or (Get-Item -LiteralPath $captureTempPath).Length -lt 4096) { throw 'Engine-native Town center screenshot did not produce a valid frame.' }
    if ($env:CHRONICLE_HARNESS_TEMP) { Move-Item -LiteralPath $captureTempPath -Destination $capturePath -Force }

    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-stop") 30
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $result = [ordered]@{
        ProcessId = $start.session.processId
        MenuOption = $centerOption[0]
        QuestMarkerObservation = [ordered]@{ NativeFlags = $centerOption[0].questMarkerFlags; Names = $centerOption[0].questMarkerNames }
        Scene = [ordered]@{ SceneName = $center.state.mission.sceneName; Mode = $center.state.mission.mode; CombatType = $center.state.mission.combatType; ActiveAgentCount = $center.state.mission.activeAgentCount; InitialMainAgent = $center.state.mission.mainAgent; InitialLocalAgents = $center.state.mission.nearbySceneAgents; InitialFocus = $center.state.mission.nativeFocus; CampaignTimeMode = $center.state.context.timeControlMode }
        InitialHarnessOnlyMissionDiagnostics = $initialMissionDiagnostics.data
        Exploration = [ordered]@{ ProviderKind = 'deterministic-test-only'; DecisionCount = @($loop.trace).Count; Steps = $stepSummary; DistanceMoved = [Math]::Round($explorationDistance, 3); LocalAgentCountAfter = $localAgentCount; LocalAgentsAfter = $afterExplore.state.mission.nearbySceneAgents; InputClearedAutomatically = $inputCleared; CampaignClockUnchanged = ($afterExplore.campaignDay -eq $center.campaignDay) }
        NativeNavigation = [ordered]@{ Candidate = if ($navigationCandidate.Count -eq 1) { $navigationCandidate[0] } else { $null }; Receipt = $navigationReceipt; Error = $navigationError; StartPosition = $navigationStartPosition; EndPosition = $navigationEndPosition; MainAgentDistanceMoved = [Math]::Round($navigationMovementDistance, 3); ControllerDuring = if ($navigationReceipt) { $navigationReceipt.state.mission.mainAgent.controller } else { $null }; PlayerControllerRestored = $navigationEnd.state.mission.mainAgent.isPlayerControlled; FinalNavigationObservation = $navigationEnd.state.mission.navigation; FollowUpCandidate = if ($navigationFollowUpCandidate.Count -eq 1) { $navigationFollowUpCandidate[0] } else { $null }; FollowUpReceipt = $navigationFollowUpReceipt; FollowUpError = $navigationFollowUpError; FollowUpStartPosition = $navigationFollowUpStartPosition; FollowUpEndPosition = $navigationFollowUpEndPosition; FollowUpDistanceMoved = [Math]::Round($navigationFollowUpMovementDistance, 3); FollowUpControllerDuring = if ($navigationFollowUpReceipt) { $navigationFollowUpReceipt.state.mission.mainAgent.controller } else { $null }; FollowUpPlayerControllerRestored = $navigationFollowUpEnd.state.mission.mainAgent.isPlayerControlled; FollowUpNavigationObservation = $navigationFollowUpEnd.state.mission.navigation }
        NativeFocusAfterApproach = [ordered]@{ Focus = $nativeFocusAfterApproach; ExpectedAgentIndex = $expectedFocusAgentIndex; MatchesApproachTarget = [bool]$focusMatchesApproachTarget }
        HarnessOnlyMissionDiagnostics = $missionDiagnostics.data
        CameraAim = if ($aimReceipt) { [ordered]@{ TargetAgentIndex = $aimTargetAgentIndex; Receipt = $aimReceipt; FocusAfter = $afterAim.state.mission.nativeFocus; MatchesSelectedAgent = [bool]$focusMatchesTarget; Error = $aimError } } else { [ordered]@{ Skipped = $true; Reason = if ($aimCandidate.Count -eq 0) { 'No non-hostile non-soldier candidate in the current local observation' } else { $aimError }; Error = $aimError } }
        FinalMainAgent = $afterAim.state.mission.mainAgent
        EngineScreenshot = $capturePath
        FixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = $stop.processStopped
    }
    $nativeNavigationVerified = ($navigationCandidate.Count -eq 0 -or ($null -ne $navigationReceipt -and $navigationReceipt.status -eq 'completed' -and $result.NativeNavigation.ControllerDuring -eq 'AI' -and $navigationMovementDistance -ge 0.1 -and $result.NativeNavigation.PlayerControllerRestored)) -and ($navigationFollowUpCandidate.Count -eq 0 -or ($null -ne $navigationFollowUpReceipt -and $navigationFollowUpReceipt.status -eq 'completed' -and $result.NativeNavigation.FollowUpControllerDuring -eq 'AI' -and $navigationFollowUpMovementDistance -ge 0.1 -and $result.NativeNavigation.FollowUpPlayerControllerRestored))
    $result.Passed = ($result.Scene.SceneName -match '_town_' -and $result.Scene.CampaignTimeMode -eq 'Stop' -and $explorationDistance -ge 1.0 -and $inputCleared -and $result.Exploration.CampaignClockUnchanged -and $nativeNavigationVerified -and $result.QuestMarkerObservation -and $result.HarnessOnlyMissionDiagnostics -and $result.FixtureUnchanged -and $result.ProcessStopped)
    $resultJson = $result | ConvertTo-Json -Depth 14
    if ($env:CHRONICLE_HARNESS_TEMP -and (Test-Path -LiteralPath $env:CHRONICLE_HARNESS_TEMP -PathType Container)) {
        Set-Content -LiteralPath (Join-Path $env:CHRONICLE_HARNESS_TEMP 'TownCenterMissionResult.json') -Value $resultJson -Encoding UTF8
    }
    $resultJson
    if (-not $result.Passed) { throw "Town center Mission validation failed: distance=$explorationDistance, localAgents=$localAgentCount, aimed=$($null -ne $aimReceipt), focusMatched=$focusMatchesTarget, campaignClockUnchanged=$($result.Exploration.CampaignClockUnchanged)." }
}
finally {
    if (Test-Path -LiteralPath $sessionPath) {
        try { Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-cleanup") 20 | Out-Null } catch { }
    }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
