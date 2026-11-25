#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180,
    [switch]$ProbeEscortVisibilityLoss,
    [switch]$ProbeEngageVisibilityLoss,
    [switch]$ProbeConversation,
    [switch]$ProbeQuestAcceptance,
    [int]$VisibilityProbeSeconds = 30
)

$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
. (Join-Path $PSScriptRoot 'Test-AgentSupport.ps1')
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$agentRoot = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent'
$sessionPath = Join-Path $agentRoot 'session.json'
$runPrefix = 'p4p-' + (Get-Date -Format 'yyyyMMddHHmmssfff')
if (-not (Test-Path $savePath)) { throw "Pursuit fixture not found: $savePath" }
$fixtureHashBefore = (Get-FileHash $savePath -Algorithm SHA256).Hash

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @()) {
    $output = & $HarnessPowerShell -NoProfile -File $cli $Action @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

try {
    $specializedProbeCount = @(@($ProbeEscortVisibilityLoss, $ProbeEngageVisibilityLoss, $ProbeConversation, $ProbeQuestAcceptance) | Where-Object { $_ }).Count
    if ($specializedProbeCount -gt 1) {
        throw 'Select exactly one specialized Pursuit probe mode per run.'
    }
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName, '-TimeoutSeconds', $TimeoutSeconds)
    $initial = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-initial", '-TimeoutSeconds', $TimeoutSeconds)
    $settlement = @($initial.state.nearbySettlements | Where-Object { -not $_.hostile -and $_.distance -gt 1.0 } | Sort-Object distance | Select-Object -First 1)
    if ($settlement.Count -ne 1) { throw 'No safe settlement target exists to establish a clean campaign-map pursuit fixture.' }
    $arrival = Invoke-AgentCli 'move' @('-SettlementId', [string]$settlement[0].id, '-CommandId', "$runPrefix-arrival", '-TimeoutSeconds', $TimeoutSeconds)
    if ($arrival.status -ne 'completed' -or $arrival.state.location.targetSettlementId -ne $settlement[0].id) { throw 'Native move order did not target the settlement used to exit into the campaign map.' }
    $arrivalState = Wait-ForAgentSettlementArrival -CliPath $cli -SettlementId ([string]$settlement[0].id) -CommandPrefix "$runPrefix-travel" -TimeoutSeconds $TimeoutSeconds
    if ($arrivalState.state.location.currentSettlementId -ne $settlement[0].id) { throw 'Could not reach the settlement used to exit into the campaign map.' }
    $town = Invoke-AgentCli 'menu' @('-CommandId', "$runPrefix-town", '-TimeoutSeconds', $TimeoutSeconds)
    $leave = @($town.state.availableMenuOptions | Where-Object { $_.isLeave -and $_.available -and $_.enabled } | Select-Object -First 1)
    if ($leave.Count -ne 1) { throw 'The settlement did not expose an enabled native leave option.' }
    $leaveResult = Invoke-AgentCli 'menuSelect' @('-MenuId', [string]$town.state.context.menuId, '-OptionId', [string]$leave[0].id, '-CommandId', "$runPrefix-leave", '-TimeoutSeconds', $TimeoutSeconds)
    if ($leaveResult.status -ne 'completed') { throw 'Could not exit the settlement to test campaign-map pursuit.' }

    $mapState = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-map-state", '-TimeoutSeconds', $TimeoutSeconds)
    $escortTargets = @($mapState.state.nearbyParties | Where-Object { $_.isMoving -and $null -eq $_.currentSettlementId -and $_.distance -gt 1.0 } | Sort-Object distance)
    if ($escortTargets.Count -eq 0) { throw 'No visible moving party outside a settlement is available in the disposable fixture; refusing to invent or teleport an escort target.' }
    $escortTarget = if ($ProbeEscortVisibilityLoss) { $escortTargets[-1] } else { $escortTargets[0] }

    $invalidEscort = Invoke-AgentCli 'follow' @('-PartyId', 'chronicle_missing_party', '-CommandId', "$runPrefix-invalid-escort", '-TimeoutSeconds', '15')
    $afterInvalidEscort = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-after-invalid-escort", '-TimeoutSeconds', $TimeoutSeconds)
    $invalidEscortNoMutation = ($invalidEscort.status -eq 'rejected' -and $afterInvalidEscort.state.location.targetPartyId -eq $mapState.state.location.targetPartyId -and $afterInvalidEscort.state.party.moveMode -eq $mapState.state.party.moveMode -and $afterInvalidEscort.state.context.timeControlMode -eq $mapState.state.context.timeControlMode)

    $escort = Invoke-AgentCli 'follow' @('-PartyId', [string]$escortTarget.id, '-CommandId', "$runPrefix-escort", '-TimeoutSeconds', $TimeoutSeconds)
    $escortState = $escort.state
    $nativeEscortIssued = ($escort.status -eq 'completed' -and $escortState.location.targetPartyId -eq $escortTarget.id -and $escortState.party.defaultBehavior -eq 'EscortParty')
    $nativeEscortTimePolicyApplied = $escortState.context.timeControlMode -in @('StoppablePlay', 'StoppableFastForward')

    if ($ProbeEscortVisibilityLoss) {
        $probeDeadline = [DateTime]::UtcNow.AddSeconds([Math]::Max(5, [Math]::Min(120, $VisibilityProbeSeconds)))
        $probeState = $escort
        $probeOutcome = 'target-remained-in-nearby-observation-for-window'
        $probeStartDay = [double]$escort.campaignDay
        $probeSamples = 0
        while ([DateTime]::UtcNow -lt $probeDeadline) {
            $probeState = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-escort-observe-$([guid]::NewGuid().ToString('N'))", '-TimeoutSeconds', $TimeoutSeconds)
            $probeSamples++
            if ($probeState.state.context.gameState -ne 'MapState') { $probeOutcome = 'left-campaign-map'; break }
            $targetInNearbyObservation = @($probeState.state.nearbyParties | Where-Object { $_.id -eq $escortTarget.id }).Count -gt 0
            if (-not $targetInNearbyObservation) { $probeOutcome = 'target-left-nearby-observation'; break }
            if ($probeState.state.location.targetPartyId -ne $escortTarget.id -or $probeState.state.party.defaultBehavior -ne 'EscortParty') { $probeOutcome = 'escort-order-ended'; break }
            if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'Game process exited during the Escort visibility probe.' }
            Start-Sleep -Milliseconds 250
        }
        $stop = Invoke-AgentCli 'stop' @('-CommandId', "$runPrefix-escort-probe-stop", '-TimeoutSeconds', $TimeoutSeconds)
        $fixtureHashAfter = (Get-FileHash $savePath -Algorithm SHA256).Hash
        $finalTargetRecord = @($probeState.state.nearbyParties | Where-Object { $_.id -eq $escortTarget.id } | Select-Object -First 1)
        $targetStillObserved = $finalTargetRecord.Count -gt 0
        $probeResult = [ordered]@{
            ProcessId = $start.session.processId
            Mode = 'natural-campaign-time; no explicit advance/pause during probe'
            ProbeOutcome = $probeOutcome
            ProbeSamples = $probeSamples
            ProbeSeconds = $VisibilityProbeSeconds
            Target = [ordered]@{ Id = $escortTarget.id; Name = $escortTarget.name; InitialDistance = $escortTarget.distance; FinalObservedParty = if ($finalTargetRecord.Count -gt 0) { $finalTargetRecord[0] } else { $null } }
            InitialEscort = [ordered]@{ Status = $escort.status; TargetPartyId = $escortState.location.targetPartyId; DefaultBehavior = $escortState.party.defaultBehavior; TimeControlMode = $escortState.context.timeControlMode; NativeMapClickTimePolicy = $nativeEscortTimePolicyApplied }
            FinalObservation = [ordered]@{ TargetInNearbyObservation = $targetStillObserved; TargetPartyId = $probeState.state.location.targetPartyId; DefaultBehavior = $probeState.state.party.defaultBehavior; TimeControlMode = $probeState.state.context.timeControlMode; CampaignDay = $probeState.campaignDay; DaysElapsed = [double]$probeState.campaignDay - $probeStartDay; GameState = $probeState.state.context.gameState }
            FixtureUnchanged = $fixtureHashBefore -eq $fixtureHashAfter
            ProcessStopped = $stop.processStopped
        }
        $probeResult.Passed = ($nativeEscortIssued -and $nativeEscortTimePolicyApplied -and $probeResult.FixtureUnchanged -and $probeResult.ProcessStopped)
        $probeJson = $probeResult | ConvertTo-Json -Depth 8
        if ($env:CHRONICLE_HARNESS_TEMP -and (Test-Path -LiteralPath $env:CHRONICLE_HARNESS_TEMP -PathType Container)) {
            Set-Content -LiteralPath (Join-Path $env:CHRONICLE_HARNESS_TEMP 'AgentPursuitVisibilityResult.json') -Value $probeJson -Encoding UTF8
        }
        $probeJson
        if (-not $probeResult.Passed) { exit 1 }
        return
    }

    $holdAfterEscort = Invoke-AgentCli 'hold' @('-CommandId', "$runPrefix-hold-after-escort", '-TimeoutSeconds', $TimeoutSeconds)
    $mapState = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-hold-settled", '-TimeoutSeconds', $TimeoutSeconds)
    $escortStoppedByNativeHold = ($holdAfterEscort.status -eq 'completed' -and $mapState.state.location.targetPartyId -eq $null -and $mapState.state.party.defaultBehavior -eq 'Hold')

    $pursuitVisibilityFixture = $null
    $pursuitVisibilitySetupPause = $null
    if ($ProbeEngageVisibilityLoss) {
        $pursuitVisibilitySetupPause = Invoke-AgentCli 'pause' @('-CommandId', "$runPrefix-pause-for-visibility-fixture", '-TimeoutSeconds', $TimeoutSeconds)
        if ($pursuitVisibilitySetupPause.timeControlMode -ne 'Stop') { throw 'Visibility fixture setup did not reach Native Stop before target creation.' }
        $pursuitVisibilityFixture = Invoke-AgentCli 'harnessPreparePursuitVisibilityFixture' @('-CommandId', "$runPrefix-prepare-visibility-fixture", '-TimeoutSeconds', $TimeoutSeconds)
        $mapState = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-after-visibility-fixture", '-TimeoutSeconds', $TimeoutSeconds)
        $visibleParties = Invoke-AgentCli 'mapPartyTargets' @('-CommandId', "$runPrefix-visibility-fixture-targets", '-TimeoutSeconds', $TimeoutSeconds)
        $fixtureTarget = @($visibleParties.data.mapPartyTargets | Where-Object { $_.id -eq $pursuitVisibilityFixture.data.partyId } | Select-Object -First 1)
        if ($fixtureTarget.Count -ne 1) { throw 'The Native-spawned weak Bandit Party was not naturally present in the IsVisible map-target set; refusing to force visibility or substitute another target.' }
        $targets = @($fixtureTarget[0])
    }
    else {
        $targets = @($mapState.state.nearbyParties | Where-Object { $_.isMoving -and $null -eq $_.currentSettlementId -and $_.distance -gt 1.0 -and (-not ($ProbeConversation -or $ProbeQuestAcceptance) -or $_.type -eq 'lord') } | Sort-Object distance)
    }
    if ($targets.Count -eq 0) {
        if ($ProbeConversation -or $ProbeQuestAcceptance) { throw 'No visible moving Lord party exists in this disposable conversation fixture; refusing to substitute another Party or fake the meeting.' }
        throw 'No visible moving party outside a settlement is available for pursuit in the disposable fixture; refusing to invent or teleport a target.'
    }
    $target = if ($ProbeEngageVisibilityLoss) { $targets[-1] } else { $targets[0] }
    $targetVisibleBeforePursuit = $null
    if ($ProbeEngageVisibilityLoss) {
        $targetVisibleBeforePursuit = @((Invoke-AgentCli 'mapPartyTargets' @('-CommandId', "$runPrefix-pursuit-visible-before", '-TimeoutSeconds', $TimeoutSeconds)).data.mapPartyTargets | Where-Object { $_.id -eq $target.id }).Count -gt 0
        if (-not $targetVisibleBeforePursuit) { throw 'The selected Pursuit target was not present in the native visible-party marker set before the action.' }
    }
    $initialScreenshot = $null
    $initialScreenshotError = $null
    if ($ProbeEngageVisibilityLoss) {
        try {
            $framePath = Join-Path $env:CHRONICLE_HARNESS_TEMP 'engage-target-initial-map.bmp'
            $capture = Invoke-AgentCli 'captureFrame' @('-OutputPath', $framePath, '-CommandId', "$runPrefix-engage-initial-frame", '-TimeoutSeconds', $TimeoutSeconds)
            $initialScreenshot = if ($capture.status -eq 'completed' -and (Test-Path -LiteralPath $framePath -PathType Leaf)) { $framePath } else { $null }
        }
        catch { $initialScreenshotError = $_.Exception.Message }
    }

    $invalid = $null
    $invalidNoMutation = $null
    if (-not $ProbeEngageVisibilityLoss) {
        $invalid = Invoke-AgentCli 'pursue' @('-PartyId', 'chronicle_missing_party', '-CommandId', "$runPrefix-invalid", '-TimeoutSeconds', '15')
        $afterInvalid = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-after-invalid", '-TimeoutSeconds', $TimeoutSeconds)
        $invalidNoMutation = ($invalid.status -eq 'rejected' -and $afterInvalid.state.location.targetPartyId -eq $mapState.state.location.targetPartyId -and $afterInvalid.state.party.moveMode -eq $mapState.state.party.moveMode)
    }

    $pursuit = Invoke-AgentCli 'pursue' @('-PartyId', [string]$target.id, '-CommandId', "$runPrefix-pursue", '-TimeoutSeconds', $TimeoutSeconds)
    $pursuitState = $pursuit.state
    $nativeOrderIssued = ($pursuit.status -eq 'completed' -and $pursuitState.location.targetPartyId -eq $target.id -and $pursuitState.party.defaultBehavior -eq 'EngageParty')
    $nativeMapClickTimePolicyApplied = $pursuitState.context.timeControlMode -in @('StoppablePlay', 'StoppableFastForward')
    $pursuitStartDay = [double]$pursuit.campaignDay
    $outcomeState = $pursuitState
    $pursuitOutcome = $null

    if ($ProbeEngageVisibilityLoss) {
        $probeDeadline = [DateTime]::UtcNow.AddSeconds([Math]::Max(10, [Math]::Min(180, $VisibilityProbeSeconds)))
        $probeSamples = [System.Collections.Generic.List[object]]::new()
        $probeOutcome = 'target-remained-visible-through-window'
        $targetLostAtUtc = $null
        $targetLostCampaignDay = $null
        $holdObservedAtUtc = $null
        $lossScreenshot = $null
        $encounterScreenshot = $null
        $encounterScreenshotError = $null
        $lastVisible = $true
        $lossScreenshotError = $null
        $stableHoldScreenshot = $null
        $stableHoldScreenshotError = $null
        while ([DateTime]::UtcNow -lt $probeDeadline) {
            $outcomeState = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-engage-observe-$([guid]::NewGuid().ToString('N'))", '-TimeoutSeconds', $TimeoutSeconds)
            if ($outcomeState.state.context.gameState -ne 'MapState') {
                $probeOutcome = if ($outcomeState.state.context.encounterActive) { 'encounter-before-visible-target-loss' } else { 'left-campaign-map' }
                if ($outcomeState.state.context.encounterActive) {
                    try {
                        $framePath = Join-Path $env:CHRONICLE_HARNESS_TEMP 'engage-encounter-before-target-loss.bmp'
                        $capture = Invoke-AgentCli 'captureFrame' @('-OutputPath', $framePath, '-CommandId', "$runPrefix-engage-encounter-frame", '-TimeoutSeconds', $TimeoutSeconds)
                        $encounterScreenshot = if ($capture.status -eq 'completed' -and (Test-Path -LiteralPath $framePath -PathType Leaf)) { $framePath } else { $null }
                    }
                    catch { $encounterScreenshotError = $_.Exception.Message }
                }
                break
            }

            $visibleSnapshot = Invoke-AgentCli 'mapPartyTargets' @('-CommandId', "$runPrefix-engage-visible-$([guid]::NewGuid().ToString('N'))", '-TimeoutSeconds', $TimeoutSeconds)
            $targetVisible = @($visibleSnapshot.data.mapPartyTargets | Where-Object { $_.id -eq $target.id }).Count -gt 0
            $targetNearby = @($outcomeState.state.nearbyParties | Where-Object { $_.id -eq $target.id }).Count -gt 0
            $sample = [ordered]@{
                Utc = [DateTime]::UtcNow.ToString('o')
                CampaignDay = [double]$outcomeState.campaignDay
                TargetVisibleMapMarker = $targetVisible
                TargetInNearbyObservation = $targetNearby
                MainPartyTargetId = $outcomeState.state.location.targetPartyId
                MainPartyMoveMode = $outcomeState.state.party.moveMode
                MainPartyDefaultBehavior = $outcomeState.state.party.defaultBehavior
                TimeControlMode = $outcomeState.state.context.timeControlMode
                IsMainPartyWaiting = [bool]$outcomeState.state.context.isWaiting
                EncounterActive = [bool]$outcomeState.state.context.encounterActive
            }
            $probeSamples.Add($sample)

            if ($lastVisible -and -not $targetVisible) {
                $targetLostAtUtc = $sample.Utc
                $targetLostCampaignDay = [double]$sample.CampaignDay
                $probeOutcome = 'native-visible-map-marker-lost'
                $framePath = Join-Path $env:CHRONICLE_HARNESS_TEMP 'engage-target-lost-map.bmp'
                try {
                    $capture = Invoke-AgentCli 'captureFrame' @('-OutputPath', $framePath, '-CommandId', "$runPrefix-engage-loss-frame", '-TimeoutSeconds', $TimeoutSeconds)
                    $lossScreenshot = if ($capture.status -eq 'completed' -and (Test-Path -LiteralPath $framePath -PathType Leaf)) { $framePath } else { $null }
                }
                catch { $lossScreenshotError = $_.Exception.Message }
            }
            $lastVisible = $targetVisible

            if ($outcomeState.state.context.encounterActive -and $outcomeState.state.context.encounteredPartyId -eq $target.id) {
                $probeOutcome = 'encounter-before-visible-target-loss'
                try {
                    $framePath = Join-Path $env:CHRONICLE_HARNESS_TEMP 'engage-encounter-before-target-loss.bmp'
                    $capture = Invoke-AgentCli 'captureFrame' @('-OutputPath', $framePath, '-CommandId', "$runPrefix-engage-encounter-frame", '-TimeoutSeconds', $TimeoutSeconds)
                    $encounterScreenshot = if ($capture.status -eq 'completed' -and (Test-Path -LiteralPath $framePath -PathType Leaf)) { $framePath } else { $null }
                }
                catch { $encounterScreenshotError = $_.Exception.Message }
                break
            }
            if ($probeOutcome -eq 'native-visible-map-marker-lost' -and $outcomeState.state.party.defaultBehavior -eq 'Hold' -and $null -eq $outcomeState.state.location.targetPartyId) {
                $probeOutcome = 'visible-target-lost-and-native-hold'
                if ($null -eq $holdObservedAtUtc) { $holdObservedAtUtc = [DateTime]::UtcNow }
            }
            if ($null -ne $holdObservedAtUtc -and ([DateTime]::UtcNow - $holdObservedAtUtc).TotalSeconds -ge 5) {
                try {
                    $framePath = Join-Path $env:CHRONICLE_HARNESS_TEMP 'engage-target-lost-stable-hold.bmp'
                    $capture = Invoke-AgentCli 'captureFrame' @('-OutputPath', $framePath, '-CommandId', "$runPrefix-engage-stable-hold-frame", '-TimeoutSeconds', $TimeoutSeconds)
                    $stableHoldScreenshot = if ($capture.status -eq 'completed' -and (Test-Path -LiteralPath $framePath -PathType Leaf)) { $framePath } else { $null }
                }
                catch { $stableHoldScreenshotError = $_.Exception.Message }
                break
            }
            if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'Game process exited during the native Engage visibility probe.' }
            Start-Sleep -Milliseconds 750
        }

        $stop = Invoke-AgentCli 'stop' @('-CommandId', "$runPrefix-engage-probe-stop", '-TimeoutSeconds', $TimeoutSeconds)
        $fixtureHashAfter = (Get-FileHash $savePath -Algorithm SHA256).Hash
        $probeResult = [ordered]@{
            ProcessId = $start.session.processId
            Mode = 'Explicit setup pause stabilizes a controlled initial Native Bandit fixture; pursue then applies its ordinary click time policy; all post-action movement, AI, visibility, and Campaign time are Native/natural'
            Target = $target
            FixtureSetup = if ($pursuitVisibilityFixture) { $pursuitVisibilityFixture.data } else { $null }
            SetupPause = $pursuitVisibilitySetupPause
            Initial = [ordered]@{ Status = $pursuit.status; TargetPartyId = $pursuitState.location.targetPartyId; DefaultBehavior = $pursuitState.party.defaultBehavior; TimeControlMode = $pursuitState.context.timeControlMode; CampaignDay = [double]$pursuit.campaignDay; VisibleMapMarker = $targetVisibleBeforePursuit }
            Outcome = $probeOutcome
            InitialMapScreenshot = $initialScreenshot
            InitialMapScreenshotError = $initialScreenshotError
            TargetLostAtUtc = $targetLostAtUtc
            TargetLostCampaignDay = $targetLostCampaignDay
            HoldStableForSeconds = if ($null -ne $holdObservedAtUtc) { ([DateTime]::UtcNow - $holdObservedAtUtc).TotalSeconds } else { 0 }
            TargetLossScreenshot = $lossScreenshot
            TargetLossScreenshotError = $lossScreenshotError
            StableHoldScreenshot = $stableHoldScreenshot
            StableHoldScreenshotError = $stableHoldScreenshotError
            EncounterScreenshot = $encounterScreenshot
            EncounterScreenshotError = $encounterScreenshotError
            Samples = @($probeSamples.ToArray())
            FinalState = [ordered]@{ TargetPartyId = $outcomeState.state.location.targetPartyId; MoveMode = $outcomeState.state.party.moveMode; DefaultBehavior = $outcomeState.state.party.defaultBehavior; TimeControlMode = $outcomeState.state.context.timeControlMode; IsMainPartyWaiting = [bool]$outcomeState.state.context.isWaiting; CampaignDay = [double]$outcomeState.campaignDay; GameState = $outcomeState.state.context.gameState }
            DaysElapsed = [double]$outcomeState.campaignDay - $pursuitStartDay
            DaysElapsedAfterTargetLoss = if ($null -ne $targetLostCampaignDay) { [double]$outcomeState.campaignDay - $targetLostCampaignDay } else { $null }
            FixtureUnchanged = $fixtureHashBefore -eq $fixtureHashAfter
            ProcessStopped = $stop.processStopped
        }
        $probeResult.TargetLossAndHoldReproduced = $probeOutcome -eq 'visible-target-lost-and-native-hold'
        $probeResult.CampaignClockStoppedAfterTargetLoss = ($probeResult.TargetLossAndHoldReproduced -and $outcomeState.state.context.isWaiting -and [math]::Abs([double]$probeResult.DaysElapsedAfterTargetLoss) -lt 0.002)
        $probeResult.Passed = ($nativeOrderIssued -and $nativeMapClickTimePolicyApplied -and $probeResult.FixtureUnchanged -and $probeResult.ProcessStopped)
        $probeJson = $probeResult | ConvertTo-Json -Depth 10
        if ($env:CHRONICLE_HARNESS_TEMP -and (Test-Path -LiteralPath $env:CHRONICLE_HARNESS_TEMP -PathType Container)) {
            Set-Content -LiteralPath (Join-Path $env:CHRONICLE_HARNESS_TEMP 'AgentEngageVisibilityResult.json') -Value $probeJson -Encoding UTF8
        }
        $probeJson
        if (-not $probeResult.Passed) { exit 1 }
        return
    }

    $deadline = [DateTime]::UtcNow.AddSeconds([Math]::Min(90, $TimeoutSeconds))
    while ([DateTime]::UtcNow -lt $deadline) {
        $outcomeState = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-observe-$([guid]::NewGuid().ToString('N'))", '-TimeoutSeconds', $TimeoutSeconds)
        if ($outcomeState.state.context.encounterActive -and $outcomeState.state.context.encounteredPartyId -eq $target.id) {
            $pursuitOutcome = if ($outcomeState.state.context.conversation) { 'conversation' } else { 'encounter' }
            break
        }
        if ($outcomeState.state.party.defaultBehavior -eq 'Hold' -and $null -eq $outcomeState.state.location.targetPartyId) { $pursuitOutcome = 'nativeHoldAfterTargetLoss'; break }
        if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'Game process exited while the native pursuit order was active.' }
        Start-Sleep -Milliseconds 250
    }
    $pursuitTimedOut = -not $pursuitOutcome

    if ($ProbeConversation) {
        $conversationBefore = $outcomeState.state.context.conversation
        if (-not $conversationBefore -or $pursuitOutcome -ne 'conversation') {
            throw "Pursuit reached '$pursuitOutcome' rather than a map conversation with the selected party."
        }
        $introOption = @($conversationBefore.options | Where-Object { $_.id -eq 'lord_meet_player_response1' -and $_.clickable } | Select-Object -First 1)
        if ($introOption.Count -ne 1) { throw 'The native map-meeting conversation did not expose the expected clickable introduction response.' }
        $invalidDialogue = Invoke-AgentCli 'dialogueSelect' @('-OptionId', 'chronicle_missing_dialogue_option', '-CommandId', "$runPrefix-invalid-dialogue", '-TimeoutSeconds', '15')
        $afterInvalidDialogue = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-after-invalid-dialogue", '-TimeoutSeconds', $TimeoutSeconds)
        $conversationBeforeSignature = $conversationBefore | ConvertTo-Json -Depth 8 -Compress
        $conversationOptionsBeforeSignature = @($conversationBefore.options) | ConvertTo-Json -Depth 8 -Compress
        $conversationAfterInvalidSignature = $afterInvalidDialogue.state.context.conversation | ConvertTo-Json -Depth 8 -Compress
        $invalidDialogueNoMutation = (
            $invalidDialogue.status -eq 'rejected' -and
            $conversationBeforeSignature -eq $conversationAfterInvalidSignature -and
            $afterInvalidDialogue.state.context.encounteredPartyId -eq $outcomeState.state.context.encounteredPartyId -and
            $afterInvalidDialogue.state.context.timeControlMode -eq $outcomeState.state.context.timeControlMode
        )
        $invalidContinue = Invoke-AgentCli 'dialogueContinue' @('-CommandId', "$runPrefix-invalid-continue", '-TimeoutSeconds', '15')
        $afterInvalidContinue = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-after-invalid-continue", '-TimeoutSeconds', $TimeoutSeconds)
        $invalidContinueNoMutation = (
            $invalidContinue.status -eq 'rejected' -and
            $conversationBeforeSignature -eq ($afterInvalidContinue.state.context.conversation | ConvertTo-Json -Depth 8 -Compress) -and
            $afterInvalidContinue.state.context.timeControlMode -eq $outcomeState.state.context.timeControlMode
        )
        $selectedDialogue = Invoke-AgentCli 'dialogueSelect' @('-OptionId', [string]$introOption[0].id, '-CommandId', "$runPrefix-intro-dialogue", '-TimeoutSeconds', $TimeoutSeconds)
        $afterSelectedDialogue = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-after-intro-dialogue", '-TimeoutSeconds', $TimeoutSeconds)
        $continueReceipt = $null
        if ($afterSelectedDialogue.state.context.conversation -and @($afterSelectedDialogue.state.context.conversation.options).Count -eq 0) {
            $continueReceipt = Invoke-AgentCli 'dialogueContinue' @('-CommandId', "$runPrefix-dialogue-continue", '-TimeoutSeconds', $TimeoutSeconds)
            $afterSelectedDialogue = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-after-dialogue-continue", '-TimeoutSeconds', $TimeoutSeconds)
        }
        $conversationOptionsAfterSignature = if ($afterSelectedDialogue.state.context.conversation) { @($afterSelectedDialogue.state.context.conversation.options) | ConvertTo-Json -Depth 8 -Compress } else { 'null' }
        $conversationTransitioned = (
            $selectedDialogue.status -eq 'completed' -and
            ($null -eq $afterSelectedDialogue.state.context.conversation -or
                $afterSelectedDialogue.state.context.conversation.sentenceText -ne $conversationBefore.sentenceText -or
                $conversationOptionsAfterSignature -ne $conversationOptionsBeforeSignature)
        )
        $stop = Invoke-AgentCli 'stop' @('-CommandId', "$runPrefix-conversation-stop", '-TimeoutSeconds', $TimeoutSeconds)
        $fixtureHashAfter = (Get-FileHash $savePath -Algorithm SHA256).Hash
        $conversationResult = [ordered]@{
            ProcessId = $start.session.processId
            Target = $target
            Entry = [ordered]@{ PursuitStatus = $pursuit.status; Outcome = $pursuitOutcome; EncounteredPartyId = $outcomeState.state.context.encounteredPartyId; InitialConversation = $conversationBefore }
            InvalidOption = [ordered]@{ Status = $invalidDialogue.status; Error = $invalidDialogue.error; NoMutation = $invalidDialogueNoMutation }
            ContinueWithOpenOptions = [ordered]@{ Status = $invalidContinue.status; Error = $invalidContinue.error; NoMutation = $invalidContinueNoMutation }
            IntroSelection = [ordered]@{ OptionId = $introOption[0].id; Status = $selectedDialogue.status; After = $afterSelectedDialogue.state.context.conversation; Progressed = $conversationTransitioned }
            ContinueReceipt = $continueReceipt
            CampaignTimeMode = $outcomeState.state.context.timeControlMode
            FixtureUnchanged = $fixtureHashBefore -eq $fixtureHashAfter
            ProcessStopped = $stop.processStopped
        }
        $conversationResult.Passed = ($pursuitOutcome -eq 'conversation' -and $invalidDialogueNoMutation -and $invalidContinueNoMutation -and $conversationTransitioned -and $conversationResult.FixtureUnchanged -and $conversationResult.ProcessStopped)
        $conversationJson = $conversationResult | ConvertTo-Json -Depth 12
        if ($env:CHRONICLE_HARNESS_TEMP -and (Test-Path -LiteralPath $env:CHRONICLE_HARNESS_TEMP -PathType Container)) {
            Set-Content -LiteralPath (Join-Path $env:CHRONICLE_HARNESS_TEMP 'AgentConversationResult.json') -Value $conversationJson -Encoding UTF8
        }
        $conversationJson
        if (-not $conversationResult.Passed) { exit 1 }
        return
    }

    if ($ProbeQuestAcceptance) {
        $initialQuests = @($outcomeState.state.quests)
        $steps = @()
        $questOptionSelected = $false
        $issueOfferRequested = $false
        $questStartState = $outcomeState
        $questFlowOutcome = 'quest-accept-option-not-reached'
        for ($flowStep = 1; $flowStep -le 12; $flowStep++) {
            $conversationState = $questStartState.state.context.conversation
            if (-not $conversationState) { $questFlowOutcome = 'conversation-ended-before-quest-accept'; break }
            $options = @($conversationState.options)
            $questAcceptOption = @($options | Where-Object { $_.id -eq 'issue_offer_player_accept_quest' -and $_.clickable } | Select-Object -First 1)
            if ($questAcceptOption.Count -eq 1) {
                $acceptedQuest = Invoke-AgentCli 'dialogueSelect' @('-OptionId', [string]$questAcceptOption[0].id, '-CommandId', "$runPrefix-quest-accept", '-TimeoutSeconds', $TimeoutSeconds)
                $questStartState = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-after-quest-accept", '-TimeoutSeconds', $TimeoutSeconds)
                $questOptionSelected = $acceptedQuest.status -eq 'completed'
                $questFlowOutcome = 'quest-accept-option-selected'
                $steps += [pscustomobject]@{ Step = $flowStep; Action = 'dialogueSelect'; OptionId = $questAcceptOption[0].id; Status = $acceptedQuest.status; Text = $questAcceptOption[0].text }
                break
            }
            $nextOption = @($options | Where-Object { $_.clickable -and $_.id -in @('lord_meet_player_response1','hero_give_issue','issue_explanation_player_response_pre_quest_solution') } | Select-Object -First 1)
            if ($nextOption.Count -eq 1) {
                if ($nextOption[0].id -eq 'hero_give_issue' -and $issueOfferRequested) {
                    $questFlowOutcome = 'issue-offer-returned-without-quest-option'
                    $steps += [pscustomobject]@{ Step = $flowStep; Action = 'stop-after-issue-offer-returned'; SentenceText = $conversationState.sentenceText; Options = $options }
                    break
                }
                if ($nextOption[0].id -eq 'hero_give_issue') { $issueOfferRequested = $true }
                $receipt = Invoke-AgentCli 'dialogueSelect' @('-OptionId', [string]$nextOption[0].id, '-CommandId', "$runPrefix-quest-flow-$flowStep", '-TimeoutSeconds', $TimeoutSeconds)
                $questStartState = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-quest-flow-observe-$flowStep", '-TimeoutSeconds', $TimeoutSeconds)
                $steps += [pscustomobject]@{ Step = $flowStep; Action = 'dialogueSelect'; OptionId = $nextOption[0].id; Status = $receipt.status; Text = $nextOption[0].text }
                continue
            }
            if ($options.Count -eq 0) {
                $receipt = Invoke-AgentCli 'dialogueContinue' @('-CommandId', "$runPrefix-quest-flow-continue-$flowStep", '-TimeoutSeconds', $TimeoutSeconds)
                $questStartState = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-quest-flow-continue-observe-$flowStep", '-TimeoutSeconds', $TimeoutSeconds)
                $steps += [pscustomobject]@{ Step = $flowStep; Action = 'dialogueContinue'; Status = $receipt.status }
                continue
            }
            $questFlowOutcome = 'unhandled-solution-options-present'
            $steps += [pscustomobject]@{ Step = $flowStep; Action = 'stop-without-choosing-unsupported-solution'; Options = $options }
            break
        }
        $newQuests = @($questStartState.state.quests | Where-Object { $_.id -notin @($initialQuests | ForEach-Object { $_.id }) })
        $questStarted = $questOptionSelected -and $newQuests.Count -gt 0
        $stop = Invoke-AgentCli 'stop' @('-CommandId', "$runPrefix-quest-probe-stop", '-TimeoutSeconds', $TimeoutSeconds)
        $fixtureHashAfter = (Get-FileHash $savePath -Algorithm SHA256).Hash
        $questResult = [ordered]@{
            ProcessId = $start.session.processId
            PartyTarget = $target
            ConversationEntry = $outcomeState.state.context.conversation
            InitialQuestCount = $initialQuests.Count
            Steps = $steps
            Outcome = $questFlowOutcome
            QuestAcceptanceReceiptObserved = $questOptionSelected
            NewActiveQuests = $newQuests
            QuestStarted = $questStarted
            FinalConversation = $questStartState.state.context.conversation
            CampaignTimeMode = $questStartState.state.context.timeControlMode
            FixtureUnchanged = $fixtureHashBefore -eq $fixtureHashAfter
            ProcessStopped = $stop.processStopped
        }
        $questResult.Passed = ($pursuitOutcome -eq 'conversation' -and $questStarted -and $questResult.FixtureUnchanged -and $questResult.ProcessStopped)
        $questJson = $questResult | ConvertTo-Json -Depth 12
        if ($env:CHRONICLE_HARNESS_TEMP -and (Test-Path -LiteralPath $env:CHRONICLE_HARNESS_TEMP -PathType Container)) {
            Set-Content -LiteralPath (Join-Path $env:CHRONICLE_HARNESS_TEMP 'AgentQuestAcceptanceResult.json') -Value $questJson -Encoding UTF8
        }
        $questJson
        if (-not $questResult.Passed) { exit 1 }
        return
    }

    if ($pursuitTimedOut) {
        Invoke-AgentCli 'hold' @('-CommandId', "$runPrefix-timeout-hold", '-TimeoutSeconds', $TimeoutSeconds) | Out-Null
        Invoke-AgentCli 'pause' @('-CommandId', "$runPrefix-timeout-pause", '-TimeoutSeconds', $TimeoutSeconds) | Out-Null
    }
    $pursuitElapsedDays = [double]$outcomeState.campaignDay - $pursuitStartDay

    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$runPrefix-stop", '-TimeoutSeconds', $TimeoutSeconds)
    $fixtureHashAfter = (Get-FileHash $savePath -Algorithm SHA256).Hash
    $result = [ordered]@{
        ProcessId = $start.session.processId
        WindowLayout = $start.session.windowLayout
        InvalidEscort = [ordered]@{ Status = $invalidEscort.status; Error = $invalidEscort.error; NoMutation = $invalidEscortNoMutation }
        EscortOrder = [ordered]@{ Status = $escort.status; TargetPartyId = $escortState.location.targetPartyId; MoveMode = $escortState.party.moveMode; DefaultBehavior = $escortState.party.defaultBehavior; TimeControlMode = $escortState.context.timeControlMode; NativeMapClickTimePolicy = $nativeEscortTimePolicyApplied }
        EscortStoppedByNativeHold = $escortStoppedByNativeHold
        Target = $target
        InvalidTarget = [ordered]@{ Status = $invalid.status; Error = $invalid.error; NoMutation = $invalidNoMutation }
        PursuitOrder = [ordered]@{ Status = $pursuit.status; TargetPartyId = $pursuitState.location.targetPartyId; MoveMode = $pursuitState.party.moveMode; DefaultBehavior = $pursuitState.party.defaultBehavior; TimeControlMode = $pursuitState.context.timeControlMode; NativeMapClickTimePolicy = $nativeMapClickTimePolicyApplied }
        PursuitPrecondition = [ordered]@{ TargetPartyId = $mapState.state.location.targetPartyId; MoveMode = $mapState.state.party.moveMode; DefaultBehavior = $mapState.state.party.defaultBehavior; TimeControlMode = $mapState.state.context.timeControlMode }
        NaturalPursuitOutcome = [ordered]@{ Outcome = $pursuitOutcome; DaysElapsed = $pursuitElapsedDays; TargetPartyId = $outcomeState.state.location.targetPartyId; MoveMode = $outcomeState.state.party.moveMode; DefaultBehavior = $outcomeState.state.party.defaultBehavior; TimeControlMode = $outcomeState.state.context.timeControlMode; EncounterActive = $outcomeState.state.context.encounterActive; EncounteredPartyId = $outcomeState.state.context.encounteredPartyId }
        TimedOut = $pursuitTimedOut
        FixtureUnchanged = $fixtureHashBefore -eq $fixtureHashAfter
        ProcessStopped = $stop.processStopped
    }
    $result.Passed = ($invalidEscortNoMutation -and $nativeEscortIssued -and $nativeEscortTimePolicyApplied -and $escortStoppedByNativeHold -and $invalidNoMutation -and $nativeOrderIssued -and $nativeMapClickTimePolicyApplied -and $pursuitOutcome -in @('encounter', 'conversation', 'nativeHoldAfterTargetLoss') -and -not $pursuitTimedOut -and $result.FixtureUnchanged -and $result.ProcessStopped)
    $resultJson = $result | ConvertTo-Json -Depth 8
    if ($env:CHRONICLE_HARNESS_TEMP -and (Test-Path -LiteralPath $env:CHRONICLE_HARNESS_TEMP -PathType Container)) {
        Set-Content -LiteralPath (Join-Path $env:CHRONICLE_HARNESS_TEMP 'AgentPursuitResult.json') -Value $resultJson -Encoding UTF8
    }
    $resultJson
    if (-not $result.Passed) { exit 1 }
}
finally {
    if (Test-Path $sessionPath) {
        try { Invoke-AgentCli 'stop' @('-CommandId', "$runPrefix-cleanup", '-TimeoutSeconds', '15') | Out-Null } catch { }
    }
}
