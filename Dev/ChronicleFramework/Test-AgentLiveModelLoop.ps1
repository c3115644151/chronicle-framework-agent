[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180,
    [ValidateRange(5,30)][int]$FrameRate = 10
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
foreach ($setting in @('CHRONICLE_LLM_BASE_URL','CHRONICLE_LLM_MODEL')) {
    if ([string]::IsNullOrWhiteSpace([string][Environment]::GetEnvironmentVariable($setting))) {
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

    $goal = 'This is a strict three-decision state machine. If previousActionReceipt is null, choose mapSettlementTargets. If previousActionReceipt.action is mapSettlementTargets and previousActionReceipt.status is completed, choose exactly one target from its receipt whose hostile=false and underSiege=false and issue one Native move order to that id. If previousActionReceipt.action is move and previousActionReceipt.status is completed, return done immediately; do not query or move again. Do not skip, repeat, or change Campaign time mode explicitly.'
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -Goal $goal -AllowedActionNames 'mapSettlementTargets,move' -MaxDecisions 3 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('live-model-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        try { $loopTrace = $output | ConvertFrom-Json } catch { }
        throw "Real-model decision loop failed: $output"
    }
    $loopTrace = $output | ConvertFrom-Json
    if ($loopTrace.status -eq 'failed') { throw "Real-model decision loop failed: $($loopTrace.error)" }

    $steps = @($loopTrace.trace)
    foreach ($step in $steps) {
        $stepAction = if ($step.decision.done -eq $true) { 'providerDone' } else { [string]$step.decision.action }
        $beforeState = if ($step.observationBefore.state) { $step.observationBefore.state } else { $baseline.state }
        Write-LiveModelCaptureEvent 'provider-response' $step.timing.providerCompletedUtc 'providerDecision' $null $beforeState $null $capture $stepAction
        if ($step.actionExecuted) {
            $afterState = if ($step.observationAfter.state) { $step.observationAfter.state } else { $beforeState }
            Write-LiveModelCaptureEvent 'native-action' $step.timing.actionCompletedUtc ([string]$step.actionReceipt.action) ([string]$step.actionReceipt.commandId) $afterState $step.actionReceipt $capture $stepAction
            Write-LiveModelCaptureEvent 'post-action-observation' $step.timing.observationCompletedUtc 'state' ([string]$step.actionReceipt.commandId) $afterState $step.actionReceipt $capture $stepAction
        }
    }

    $targetQuery = @($steps | Where-Object { $_.decision.action -eq 'mapSettlementTargets' -and $_.actionReceipt.status -eq 'completed' } | Select-Object -First 1)
    $moveStep = @($steps | Where-Object { $_.decision.action -eq 'move' -and $_.actionReceipt.status -eq 'completed' } | Select-Object -First 1)
    if ($targetQuery.Count -ne 1 -or $moveStep.Count -ne 1 -or [int]$targetQuery[0].iteration -ge [int]$moveStep[0].iteration) {
        throw 'Live model did not query visible targets before completing one Native move action within its three-decision budget.'
    }
    $observedTargets = @($targetQuery[0].actionReceipt.data.mapSettlementTargets)
    $chosenId = [string]$moveStep[0].decision.arguments.SettlementId
    $chosenTarget = @($observedTargets | Where-Object { [string]$_.id -ceq $chosenId } | Select-Object -First 1)
    $chosenObservedSafeTarget = ($chosenTarget.Count -eq 1 -and -not [bool]$chosenTarget[0].hostile -and -not [bool]$chosenTarget[0].underSiege)
    $nativeMovementObserved = ([string]$moveStep[0].observationAfter.state.location.targetSettlementId -ceq $chosenId)
    $providerStoppedAfterGoalAction = ([bool]$loopTrace.termination.completedByProvider -and [bool]$steps[-1].decision.done -and [int]$loopTrace.actionsExecuted -eq 2)
    if (-not $chosenObservedSafeTarget -or -not $nativeMovementObserved) { throw 'Native move did not match a safe settlement id returned by the visible-target query.' }
    if (-not $providerStoppedAfterGoalAction) { throw 'Live model did not stop after the single requested Native move order.' }

    $finalObservation = if ($steps.Count -gt 0 -and $steps[-1].observationAfter) { $steps[-1].observationAfter } else { $baseline }
    $null = Capture-EngineFrame 'LiveModelEngine-after'
    Write-LiveModelCaptureEvent 'capture-end' ([DateTime]::UtcNow.ToString('O')) 'capture' $null $finalObservation.state $null $capture
    $captureResult = Stop-ChronicleWindowVideoCapture -Capture $capture -ContactSheetPath $contactSheetPath -EventTracePath $eventTracePath -KeepVideo
    $capture = $null

    $liveModelTrace = [ordered]@{
        ProviderKind = 'configured OpenAI-compatible live model'
        Goal = $goal
        ChosenSettlementId = $chosenId
        ChosenSettlementName = [string]$chosenTarget[0].name
        ObservedTargetCount = $observedTargets.Count
        QueryThenNativeMoveVerified = $true
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
