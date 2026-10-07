[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180,
    [ValidateRange(5,30)][int]$FrameRate = 10,
    [switch]$ArrivalLoop,
    [switch]$RecruitmentLoop
)

$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$loop = Join-Path $PSScriptRoot 'Agent-DecisionLoop.ps1'
$provider = Join-Path $PSScriptRoot 'Agent-OpenAICompatibleProvider.ps1'
$videoLibrary = Join-Path $PSScriptRoot 'HarnessVideoCapture.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'

if (Get-Process -Name Bannerlord* -ErrorAction SilentlyContinue) {
    throw 'Refusing to start a live-model Campaign test while any Bannerlord client is already running.'
}
if ($ArrivalLoop -and $RecruitmentLoop) { throw 'Select only one LiveModel test goal per run.' }
foreach ($setting in @('CHRONICLE_LLM_BASE_URL','CHRONICLE_LLM_MODEL','CHRONICLE_LLM_API_KEY','CHRONICLE_LLM_TIMEOUT_SECONDS','CHRONICLE_LLM_MAX_TOKENS','CHRONICLE_LLM_MAX_TOKEN_PARAMETER','CHRONICLE_LLM_REASONING_EFFORT','CHRONICLE_LLM_TEMPERATURE')) {
    $configuredValue = [string][Environment]::GetEnvironmentVariable($setting, 'Process')
    if ([string]::IsNullOrWhiteSpace($configuredValue)) {
        $configuredValue = [string][Environment]::GetEnvironmentVariable($setting, 'User')
        if (-not [string]::IsNullOrWhiteSpace($configuredValue)) { [Environment]::SetEnvironmentVariable($setting, $configuredValue, 'Process') }
    }
    if ($setting -in @('CHRONICLE_LLM_BASE_URL','CHRONICLE_LLM_MODEL') -and [string]::IsNullOrWhiteSpace($configuredValue)) {
        throw "Live-model verification requires local $setting configuration; the value is never printed by this test."
    }
}
if (-not (Test-Path -LiteralPath $savePath -PathType Leaf)) { throw "Disposable AgentLoop fixture not found: $savePath" }
if (Test-Path -LiteralPath $sessionPath -PathType Leaf) { throw 'Refusing to replace an existing Chronicle Agent session; stop or recover it before the live-model test.' }
if (-not $env:CHRONICLE_HARNESS_TEMP -or -not (Test-Path -LiteralPath $env:CHRONICLE_HARNESS_TEMP -PathType Container)) {
    throw 'Live-model visual evidence requires the active Run-Harness TestResults temp directory.'
}

$runDirectory = Split-Path -Parent $env:CHRONICLE_HARNESS_TEMP
$videoPath = Join-Path $runDirectory 'LiveModelWindow.mp4'
$contactSheetPath = Join-Path $runDirectory 'LiveModelWindow-contact.jpg'
$eventTracePath = Join-Path $runDirectory 'LiveModelWindow-events.jsonl'
$timelineIndexPath = Join-Path $runDirectory 'LiveModelWindow-timeline-index.json'
$engineFrameBeforePath = Join-Path $runDirectory 'LiveModelEngine-before.bmp'
$engineFrameAfterPath = Join-Path $runDirectory 'LiveModelEngine-after.bmp'
$engineFrameFailurePath = Join-Path $runDirectory 'LiveModelEngine-failure.bmp'
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
$priorHarnessMode = $env:CHRONICLE_HARNESS_MODE
$priorModelTimeout = $env:CHRONICLE_LLM_TIMEOUT_SECONDS
$priorModelMaxTokens = $env:CHRONICLE_LLM_MAX_TOKENS
$sessionStarted = $false
$capture = $null
$captureResult = $null
$loopTrace = $null
$failure = $null
$start = $null
$stop = $null
$liveModelTrace = $null
$fixtureHashAfter = $null
$fixtureUnchanged = $false
$processStopped = $false
$failureEngineFrameCaptured = $false
$failureEvidenceError = $null

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

function Write-LiveModelCaptureEvent(
    [string]$EventName,
    [string]$Utc,
    [string]$Action,
    [string]$CommandId,
    $State,
    $Receipt,
    $ActiveCapture,
    [string]$DecisionAction = ''
) {
    $eventUtc = if ([string]::IsNullOrWhiteSpace($Utc)) { (Get-Date).ToUniversalTime().ToString('O') } else { $Utc }
    $startUtc = [DateTimeOffset]::Parse([string]$ActiveCapture.StartedUtc).ToUniversalTime()
    $eventOffset = [DateTimeOffset]::Parse($eventUtc).ToUniversalTime()
    $stateContext = if ($State -and $State.context) { $State.context } else { $null }
    $event = [ordered]@{
        event = $EventName
        utc = $eventUtc
        offsetMilliseconds = [Math]::Round(($eventOffset - $startUtc).TotalMilliseconds, 2)
        commandId = $CommandId
        action = $Action
        decisionAction = $DecisionAction
        gameState = if ($stateContext) { [string]$stateContext.gameState } else { $null }
        menuId = if ($stateContext) { [string]$stateContext.menuId } else { $null }
        partyScreenMode = if ($State -and $State.partyScreen) { [string]$State.partyScreen.mode } else { $null }
        inventoryMode = if ($State -and $State.inventoryScreen) { [string]$State.inventoryScreen.mode } else { $null }
        campaignDay = if ($Receipt) { $Receipt.campaignDay } elseif ($State) { $State.campaignDay } else { $null }
    }
    Add-Content -LiteralPath $eventTracePath -Value ($event | ConvertTo-Json -Compress -Depth 6) -Encoding UTF8
}

function Capture-EngineFrame([string]$Name) {
    $temporaryPath = Join-Path $env:CHRONICLE_HARNESS_TEMP ($Name + '.bmp')
    Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    $still = Invoke-AgentCli 'captureFrame' @('-OutputPath', $temporaryPath, '-CommandId', ($Name + '-' + [Guid]::NewGuid().ToString('N'))) 15
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path -LiteralPath $temporaryPath) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
    if ($still.status -ne 'completed' -or -not (Test-Path -LiteralPath $temporaryPath) -or (Get-Item -LiteralPath $temporaryPath).Length -lt 4096) {
        throw "Native engine frame '$Name' was not captured."
    }
    $destination = switch ($Name) {
        'LiveModelEngine-before' { $engineFrameBeforePath; break }
        'LiveModelEngine-after' { $engineFrameAfterPath; break }
        'LiveModelEngine-failure' { $engineFrameFailurePath; break }
        default { throw "Unknown LiveModel engine-frame label '$Name'." }
    }
    Move-Item -LiteralPath $temporaryPath -Destination $destination -Force
    return $destination
}

try {
    . $videoLibrary
    Set-Content -LiteralPath $eventTracePath -Value '' -Encoding UTF8
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $sessionStarted = $true
    $baseline = Invoke-AgentCli 'state'
    if ($baseline.status -ne 'completed' -or $baseline.state.context.gameState -ne 'MapState' -or $baseline.state.location.currentSettlementId) {
        throw 'Live-model fixture must load into an unobstructed Campaign Map state.'
    }
    $null = Capture-EngineFrame 'LiveModelEngine-before'
    $capture = Start-ChronicleWindowVideoCapture -ProcessId ([int]$start.session.processId) -OutputPath $videoPath -FrameRate $FrameRate
    Write-LiveModelCaptureEvent 'capture-start' $capture.StartedUtc 'capture' $null $baseline.state $baseline $capture

    if ($RecruitmentLoop) {
        $goal = 'Autonomously recruit one affordable local volunteer. First query mapSettlementTargets. Choose the nearest observed safe target that is not the current settlement and issue one move. While still moving, use observeAgain with waitSeconds 5; never send move again or change clock controls. Once a fresh Native observation shows arrival, inspect the current settlement menu. If recruit_volunteers is currently available, call recruitOptions. Select one currently available offer that is affordable and fits party capacity; call recruit with its observed ownerId, troopId and slot, and ConfirmPartySizeWarning=false. After the Native receipt and fresh state show members increased by one and gold decreased by that offer cost, return done. If the current settlement has no eligible offer, use only newly observed safe settlement targets to replan; never invent inventory or force an over-capacity choice.'
        $maxDecisions = 24
        $maxElapsedSeconds = 600
        $allowedActions = 'mapSettlementTargets,move,recruitOptions,recruit'
        $env:CHRONICLE_LLM_TIMEOUT_SECONDS = '180'
        $env:CHRONICLE_LLM_MAX_TOKENS = '512'
    }
    elseif ($ArrivalLoop) {
        $goal = 'First query mapSettlementTargets. Then choose the nearest observed safe target (not hostile, not under siege, not the current settlement) and issue one move. While party.isMoving toward that target and currentSettlementId differs, use observeAgain with waitSeconds 5; do not send move again or use clock controls. When nativeMoveArrival.status is arrived, return done immediately and issue no further game action.'
        $env:CHRONICLE_LLM_TIMEOUT_SECONDS = '180'
        # The four-step arrival loop emits compact JSON; reserve only 256 completion tokens to keep the 4K context available for observed state.
        $env:CHRONICLE_LLM_MAX_TOKENS = '256'
        $maxDecisions = 30
        $maxElapsedSeconds = 600
        $allowedActions = 'mapSettlementTargets,move'
    }
    else {
        $goal = 'This is a strict three-decision state machine. If previousActionReceipt is null, choose mapSettlementTargets. If previousActionReceipt.action is mapSettlementTargets and previousActionReceipt.status is completed, choose exactly one target from its receipt whose hostile=false and underSiege=false and issue one Native move order to that id. If previousActionReceipt.action is move and previousActionReceipt.status is completed, return done immediately; do not query or move again. Do not skip, repeat, or change Campaign time mode explicitly.'
        $maxDecisions = 3
        $maxElapsedSeconds = 0
        $allowedActions = 'mapSettlementTargets,move'
    }
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -Goal $goal -AllowedActionNames $allowedActions -MaxDecisions $maxDecisions -MaxElapsedSeconds $maxElapsedSeconds -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('live-model-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        try { $loopTrace = $output | ConvertFrom-Json } catch { }
        throw "Real-model decision loop failed: $output"
    }
    $loopTrace = $output | ConvertFrom-Json
    if ($loopTrace.status -eq 'failed') { throw "Real-model decision loop failed: $($loopTrace.error)" }

    $steps = @($loopTrace.trace)
    foreach ($step in $steps) {
        $stepAction = if ($step.decision.done -eq $true) { 'providerDone' } elseif ($step.decision.observeAgain -eq $true) { 'observeAgain' } else { [string]$step.decision.action }
        $beforeState = if ($step.observationBefore.state) { $step.observationBefore.state } else { $baseline.state }
        Write-LiveModelCaptureEvent 'provider-response' $step.timing.providerCompletedUtc 'providerDecision' $null $beforeState $null $capture $stepAction
        if ($step.actionExecuted) {
            $afterState = if ($step.observationAfter.state) { $step.observationAfter.state } else { $beforeState }
            Write-LiveModelCaptureEvent 'native-action' $step.timing.actionCompletedUtc ([string]$step.actionReceipt.action) ([string]$step.actionReceipt.commandId) $afterState $step.actionReceipt $capture $stepAction
            Write-LiveModelCaptureEvent 'post-action-observation' $step.timing.observationCompletedUtc 'state' ([string]$step.actionReceipt.commandId) $afterState $step.actionReceipt $capture $stepAction
        }
        elseif ($step.control -and $step.observationAfter) {
            Write-LiveModelCaptureEvent 'scheduler-wait' $step.timing.schedulerWaitCompletedUtc 'boundedObserveAgain' $null $beforeState $null $capture $stepAction
            Write-LiveModelCaptureEvent 'post-wait-observation' $step.timing.observationCompletedUtc 'state' $null $step.observationAfter.state $null $capture $stepAction
        }
    }

    $targetQuery = @($steps | Where-Object { $_.decision.action -eq 'mapSettlementTargets' -and $_.actionReceipt.status -eq 'completed' } | Select-Object -First 1)
    $moveStep = @($steps | Where-Object { $_.decision.action -eq 'move' -and $_.actionReceipt.status -eq 'completed' } | Select-Object -First 1)
    if ($targetQuery.Count -ne 1 -or $moveStep.Count -ne 1 -or [int]$targetQuery[0].iteration -ge [int]$moveStep[0].iteration) {
        throw 'Live model did not query visible targets before one Native move action.'
    }
    $observedTargets = @($targetQuery[0].actionReceipt.data.mapSettlementTargets)
    $chosenId = [string]$moveStep[0].decision.arguments.SettlementId
    $chosenTarget = @($observedTargets | Where-Object { [string]$_.id -ceq $chosenId } | Select-Object -First 1)
    $currentSettlementBeforeMove = [string]$targetQuery[0].observationBefore.state.location.currentSettlementId
    $chosenObservedSafeTarget = ($chosenTarget.Count -eq 1 -and [string]$chosenTarget[0].id -cne $currentSettlementBeforeMove -and [double]$chosenTarget[0].distance -gt 1.0 -and -not [bool]$chosenTarget[0].hostile -and -not [bool]$chosenTarget[0].underSiege)
    $nativeMovementObserved = ([string]$moveStep[0].observationAfter.state.location.targetSettlementId -ceq $chosenId)
    $observeSteps = @($steps | Where-Object { $_.control.kind -eq 'bounded-observe-again' -and -not $_.actionExecuted -and $_.observationAfter.status -eq 'completed' })
    $finalObservation = if ($steps.Count -gt 0 -and $steps[-1].observationAfter) { $steps[-1].observationAfter } else { $baseline }
    $arrivalConfirmed = ([string]$finalObservation.state.location.currentSettlementId -ceq $chosenId)
    $campaignDayAdvancedDuringTravel = ([double]$finalObservation.campaignDay -gt [double]$moveStep[0].observationAfter.campaignDay)
    $providerStoppedAfterGoalAction = ([bool]$loopTrace.termination.completedByProvider -and [bool]$steps[-1].decision.done -and [int]$loopTrace.actionsExecuted -eq 2)
    if (-not $chosenObservedSafeTarget -or -not $nativeMovementObserved) { throw 'Native move did not match a safe settlement id returned by the visible-target query.' }
    if (($ArrivalLoop -or $RecruitmentLoop) -and (-not $arrivalConfirmed -or $observeSteps.Count -lt 1 -or -not $campaignDayAdvancedDuringTravel)) {
        throw 'Live-model arrival slice lacked a verified target settlement, at least one bounded re-observation, or natural Campaign-time advancement.'
    }
    if ($RecruitmentLoop) {
        $offerStep = @($steps | Where-Object { $_.decision.action -eq 'recruitOptions' -and $_.actionReceipt.status -eq 'completed' } | Select-Object -First 1)
        $recruitStep = @($steps | Where-Object { $_.decision.action -eq 'recruit' -and $_.actionReceipt.status -eq 'completed' } | Select-Object -First 1)
        if ($offerStep.Count -ne 1 -or $recruitStep.Count -ne 1) { throw 'Real model did not inspect one Native recruitment offer and submit one recruitment transaction.' }
        $recruitMenuOption = @($offerStep[0].observationBefore.state.availableMenuOptions | Where-Object { $_.id -eq 'recruit_volunteers' -and $_.available -and $_.enabled } | Select-Object -First 1)
        $offerReceipt = $offerStep[0].actionReceipt
        $chosenOffer = @($offerReceipt.data.offers | Where-Object { $_.available -and [string]$_.ownerId -ceq [string]$recruitStep[0].decision.arguments.OwnerId -and [string]$_.troopId -ceq [string]$recruitStep[0].decision.arguments.TroopId -and [int]$_.slot -eq [int]$recruitStep[0].decision.arguments.VolunteerSlot -and [int]$_.cost -le [int]$offerStep[0].observationBefore.state.economy.gold } | Select-Object -First 1)
        $recruitBefore = $recruitStep[0].observationBefore.state
        $recruitAfter = $recruitStep[0].observationAfter.state
        $nativeRecruitmentVerified = (
            $recruitMenuOption.Count -eq 1 -and
            $offerStep[0].observationBefore.state.location.currentSettlementId -ceq $chosenId -and
            $offerStep[0].observationBefore.state.context.menuId -in @('town','town_backstreet','village') -and
            $chosenOffer.Count -eq 1 -and
            -not [bool]$recruitStep[0].decision.arguments.ConfirmPartySizeWarning -and
            [bool]$recruitStep[0].actionReceipt.data.verified -and
            [int]$recruitAfter.party.members -eq ([int]$recruitBefore.party.members + 1) -and
            [int]$recruitBefore.economy.gold - [int]$recruitAfter.economy.gold -eq [int]$chosenOffer[0].cost
        )
        if (-not $nativeRecruitmentVerified) { throw 'Native volunteer recruitment did not match the current enabled menu option, observed offer, party-size delta, and Gold cost.' }
        $providerStoppedAfterGoalAction = ([bool]$loopTrace.termination.completedByProvider -and [bool]$steps[-1].decision.done -and [int]$loopTrace.actionsExecuted -eq 4)
        if (-not $providerStoppedAfterGoalAction) { throw 'Live model did not stop after Native recruitment postconditions were observed.' }
    }
    elseif (-not $ArrivalLoop -and -not $providerStoppedAfterGoalAction) { throw 'Live model did not stop after the single requested Native move order.' }
    if ($ArrivalLoop -and -not $providerStoppedAfterGoalAction) { throw 'Live model did not stop after Native arrival was observed.' }

    $null = Capture-EngineFrame 'LiveModelEngine-after'
    Write-LiveModelCaptureEvent 'capture-end' ([DateTime]::UtcNow.ToString('O')) 'capture' $null $finalObservation.state $null $capture
    $captureResult = Stop-ChronicleWindowVideoCapture -Capture $capture -ContactSheetPath $contactSheetPath -EventTracePath $eventTracePath -KeepVideo
    $capture = $null

    $liveModelTrace = [ordered]@{
        ProviderKind = 'configured OpenAI-compatible live model'
        Goal = $goal
        AcceptanceSlice = if ($RecruitmentLoop) { 'Native movement plus volunteer recruitment' } elseif ($ArrivalLoop) { 'Native movement arrival' } else { 'Native movement order accepted' }
        ChosenSettlementId = $chosenId
        ChosenSettlementName = [string]$chosenTarget[0].name
        ObservedTargetCount = $observedTargets.Count
        QueryThenNativeMoveVerified = $true
        ArrivalConfirmed = $arrivalConfirmed
        BoundedReobservations = $observeSteps.Count
        CampaignDayAdvancedDuringTravel = $campaignDayAdvancedDuringTravel
        RecruitmentVerified = if ($RecruitmentLoop) { [bool]$nativeRecruitmentVerified } else { $null }
        ProviderStoppedAfterGoalAction = $providerStoppedAfterGoalAction
        Decisions = $steps.Count
        NativeActionReceipts = @($steps | Where-Object { $_.actionExecuted } | ForEach-Object { [ordered]@{ action = $_.actionReceipt.action; status = $_.actionReceipt.status; campaignDay = $_.actionReceipt.campaignDay; timing = $_.timing } })
        Trace = $loopTrace.trace
        VisualEvidence = [ordered]@{
            Provider = $captureResult.Provider
            FrameCoverageRatio = $captureResult.FrameCoverageRatio
            DurationSeconds = $captureResult.DurationSeconds
            ContactSheetPath = $contactSheetPath
            TimelineIndexPath = $captureResult.TimelineIndexPath
            EventTracePath = $eventTracePath
            EngineFrameBeforePath = $engineFrameBeforePath
            EngineFrameAfterPath = $engineFrameAfterPath
            SourceVideoPath = $videoPath
            SourceVideoSha256 = $captureResult.SourceVideoSha256
        }
        FixtureHashBefore = $fixtureHashBefore
    }
}
catch {
    $failure = $_.Exception.Message
    if ($capture) {
        try {
            $failedState = if ($loopTrace -and $loopTrace.lastObservation -and $loopTrace.lastObservation.state) { $loopTrace.lastObservation.state } else { $baseline.state }
            $failedUtc = if ($loopTrace -and $loopTrace.timing -and $loopTrace.timing.providerCompletedUtc) { [string]$loopTrace.timing.providerCompletedUtc } else { [DateTime]::UtcNow.ToString('O') }
            Write-LiveModelCaptureEvent 'model-loop-failed' $failedUtc 'modelLoopFailure' $null $failedState $null $capture
        }
        catch { if (-not $failureEvidenceError) { $failureEvidenceError = "Could not align failure event: $($_.Exception.Message)" } }
    }
    if ($sessionStarted) {
        try { $null = Capture-EngineFrame 'LiveModelEngine-failure'; $failureEngineFrameCaptured = $true }
        catch { $failureEvidenceError = $_.Exception.Message }
    }
}
finally {
    if ($capture) {
        try {
            $captureResult = Stop-ChronicleWindowVideoCapture -Capture $capture -ContactSheetPath $contactSheetPath -EventTracePath $eventTracePath -KeepVideo
        }
        catch {
            [ordered]@{ stoppedUtc = (Get-Date).ToUniversalTime().ToString('O'); error = $_.Exception.Message; videoPath = $videoPath; eventTracePath = $eventTracePath } |
                ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $runDirectory 'LiveModelWindow-partial.json') -Encoding UTF8
            try { if ($capture.Process -and -not $capture.Process.HasExited) { $capture.Process.Kill() } } catch { }
        }
        $capture = $null
    }
    if ($sessionStarted -or (Test-Path -LiteralPath $sessionPath -PathType Leaf)) {
        try { $stop = Invoke-AgentCli 'stop' } catch { if (-not $failure) { $failure = "Agent session cleanup failed: $($_.Exception.Message)" } }
    }
    if ($null -eq $priorHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $priorHarnessMode }
    if ($null -eq $priorModelTimeout) { Remove-Item Env:CHRONICLE_LLM_TIMEOUT_SECONDS -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_LLM_TIMEOUT_SECONDS = $priorModelTimeout }
    if ($null -eq $priorModelMaxTokens) { Remove-Item Env:CHRONICLE_LLM_MAX_TOKENS -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_LLM_MAX_TOKENS = $priorModelMaxTokens }
}

$fixtureHashAfter = if (Test-Path -LiteralPath $savePath -PathType Leaf) { (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash } else { $null }
$fixtureUnchanged = ($fixtureHashBefore -ceq $fixtureHashAfter)
$processStopped = ([bool]$stop.processStopped -and -not (Test-Path -LiteralPath $sessionPath -PathType Leaf) -and -not (Get-Process -Name Bannerlord* -ErrorAction SilentlyContinue))
$capturePassed = ($captureResult -and $captureResult.Passed -and [double]$captureResult.FrameCoverageRatio -ge 0.9 -and $captureResult.WindowTitle -match 'Bannerlord')
$passed = (-not $failure -and $null -ne $liveModelTrace -and $fixtureUnchanged -and $processStopped -and $capturePassed)

if ($passed -and (Test-Path -LiteralPath $videoPath -PathType Leaf)) {
    Remove-Item -LiteralPath $videoPath -Force
    if (Test-Path -LiteralPath $timelineIndexPath -PathType Leaf) {
        $timelineIndex = Get-Content -LiteralPath $timelineIndexPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $timelineIndex.sourceClip.retained = $false
        $timelineIndex.sourceClip.removedAfterEvidence = $true
        $timelineIndex | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $timelineIndexPath -Encoding UTF8
    }
    if ($liveModelTrace.VisualEvidence) { $liveModelTrace.VisualEvidence.SourceVideoPath = $null; $liveModelTrace.VisualEvidence.SourceVideoRemovedAfterKeyframes = $true }
    if ($captureResult) { $captureResult.VideoRetained = $false; $captureResult.VideoRemovedAfterEvidence = $true }
}

$result = [ordered]@{
    ProviderKind = 'configured OpenAI-compatible live model; not a stub'
    Passed = $passed
    Failure = $failure
    FixtureUnchanged = $fixtureUnchanged
    ProcessStopped = $processStopped
    VisualEvidencePassed = [bool]$capturePassed
    FailureEngineFrameCaptured = $failureEngineFrameCaptured
    FailureEvidenceError = $failureEvidenceError
    FailureEngineFramePath = if ($failureEngineFrameCaptured) { $engineFrameFailurePath } else { $null }
    ProcessId = if ($start -and $start.session) { $start.session.processId } else { $null }
    Capture = $captureResult
    Trace = $liveModelTrace
}
$json = $result | ConvertTo-Json -Depth 28
if ($env:CHRONICLE_HARNESS_TEMP -and (Test-Path -LiteralPath $env:CHRONICLE_HARNESS_TEMP -PathType Container)) {
    Set-Content -LiteralPath (Join-Path $env:CHRONICLE_HARNESS_TEMP 'LiveModelLoopResult.json') -Value $json -Encoding UTF8
}
$json
if (-not $passed) { exit 1 }
