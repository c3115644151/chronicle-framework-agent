[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180,
    [ValidateRange(5,30)][int]$FrameRate = 10,
    [switch]$RuntimeOnlyResume,
    [switch]$CrashAfterRecruit
)

$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$loop = Join-Path $PSScriptRoot 'Agent-DecisionLoop.ps1'
$provider = Join-Path $PSScriptRoot 'Agent-OpenAICompatibleProvider.ps1'
$videoLibrary = Join-Path $PSScriptRoot 'HarnessVideoCapture.ps1'
$saveRoot = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\Game Saves'
$sourceSavePath = Join-Path $saveRoot ($LoadSaveName + '.sav')
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$resumeSaveName = 'ChronicleLiveResume-' + [Guid]::NewGuid().ToString('N')
$resumeSavePath = Join-Path $saveRoot ($resumeSaveName + '.sav')
$resumeBackupPath = $resumeSavePath + '.bak'
$runDirectory = if ($env:CHRONICLE_HARNESS_TEMP) { Split-Path -Parent $env:CHRONICLE_HARNESS_TEMP } else { $null }
if (-not $runDirectory -or -not (Test-Path -LiteralPath $runDirectory -PathType Container)) { throw 'Live checkpoint resume requires the active Harness TestResults directory.' }
$prefix = 'live-resume-' + [Guid]::NewGuid().ToString('N')
    $goal = 'Recruit one affordable volunteer at a safe settlement. First query visible settlement targets and move once to the nearest safe target. If the confirmed Native move is still in progress after the Agent or Campaign restart and Campaign time is stopped, use the separate resume action, then reobserve with observeAgain; do not issue the same move again. After arrival, inspect the current recruit_volunteers option, choose one currently available offer that fits capacity and gold, recruit it once, and stop after the Native receipt and fresh state verify members plus one and gold minus the offer cost.'
$allowedActions = 'mapSettlementTargets,move,resume,recruitOptions,recruit'
$fixtureHashBefore = (Get-FileHash -LiteralPath $sourceSavePath -Algorithm SHA256).Hash
$priorHarnessMode = $env:CHRONICLE_HARNESS_MODE
$priorModelTimeout = $env:CHRONICLE_LLM_TIMEOUT_SECONDS
$priorModelMaxTokens = $env:CHRONICLE_LLM_MAX_TOKENS
$sessionStarted = $false
$firstCapture = $null
$secondCapture = $null
$firstCaptureResult = $null
$secondCaptureResult = $null
$firstLoopTrace = $null
$resumeLoopTrace = $null
$firstStop = $null
$finalStop = $null
$failure = $null
$start = $null
$resumeStart = $null
$checkpointBeforeSave = $null
$checkpointAfterLoad = $null
$recruitmentVerified = $false
$goalRestored = $false
$moveNotRepeated = $false
$crashAfterRecruitVerified = $false
$firstCrashExitCode = $null

foreach ($setting in @('CHRONICLE_LLM_BASE_URL','CHRONICLE_LLM_MODEL','CHRONICLE_LLM_API_KEY','FREELLMAPI_API_KEY','CHRONICLE_LLM_TIMEOUT_SECONDS','CHRONICLE_LLM_MAX_TOKENS','CHRONICLE_LLM_MAX_TOKEN_PARAMETER','CHRONICLE_LLM_REASONING_EFFORT','CHRONICLE_LLM_TEMPERATURE')) {
    $configuredValue = [string][Environment]::GetEnvironmentVariable($setting, 'Process')
    if ([string]::IsNullOrWhiteSpace($configuredValue)) {
        $configuredValue = [string][Environment]::GetEnvironmentVariable($setting, 'User')
        if (-not [string]::IsNullOrWhiteSpace($configuredValue)) { [Environment]::SetEnvironmentVariable($setting, $configuredValue, 'Process') }
    }
    if ($setting -in @('CHRONICLE_LLM_BASE_URL','CHRONICLE_LLM_MODEL') -and [string]::IsNullOrWhiteSpace($configuredValue)) {
        throw "Live-model checkpoint verification requires local $setting configuration; the value is never printed."
    }
}
. (Join-Path $PSScriptRoot 'Get-FreeLLMAPIProfile.ps1')
$null = Initialize-FreeLLMAPIProfile
if (Get-Process -Name Bannerlord* -ErrorAction SilentlyContinue) { throw 'Refusing to run checkpoint resume while any Bannerlord client is already running.' }
if ($RuntimeOnlyResume -and $CrashAfterRecruit) { throw 'Select only one checkpoint recovery scenario per run.' }
if (-not (Test-Path -LiteralPath $sourceSavePath -PathType Leaf)) { throw "Disposable checkpoint source save not found: $sourceSavePath" }
if (Test-Path -LiteralPath $resumeSavePath -PathType Leaf) { throw 'Generated resume save name unexpectedly already exists.' }
if (Test-Path -LiteralPath $sessionPath -PathType Leaf) { throw 'Refusing to replace an existing Chronicle Agent session.' }

$firstVideo = Join-Path $runDirectory 'LiveResume-before-reload.mp4'
$firstContactSheet = Join-Path $runDirectory 'LiveResume-before-reload-contact.jpg'
$firstEvents = Join-Path $runDirectory 'LiveResume-before-reload-events.jsonl'
$firstTimeline = Join-Path $runDirectory 'LiveResume-before-reload-timeline-index.json'
$secondVideo = Join-Path $runDirectory 'LiveResume-after-reload.mp4'
$secondContactSheet = Join-Path $runDirectory 'LiveResume-after-reload-contact.jpg'
$secondEvents = Join-Path $runDirectory 'LiveResume-after-reload-events.jsonl'
$secondTimeline = Join-Path $runDirectory 'LiveResume-after-reload-timeline-index.json'
$frameBeforeSave = Join-Path $runDirectory 'LiveResume-before-save.bmp'
$frameAfterLoad = Join-Path $runDirectory 'LiveResume-after-load.bmp'
$frameAfterGoal = Join-Path $runDirectory 'LiveResume-after-goal.bmp'
$frameFailure = Join-Path $runDirectory 'LiveResume-failure.bmp'

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

function Capture-EngineFrame([string]$Label, [string]$Destination) {
    $tempFrame = Join-Path $env:CHRONICLE_HARNESS_TEMP ($Label + '.bmp')
    Remove-Item -LiteralPath $tempFrame -Force -ErrorAction SilentlyContinue
    $receipt = Invoke-AgentCli 'captureFrame' @('-OutputPath', $tempFrame, '-CommandId', ($prefix + '-' + $Label)) 20
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path -LiteralPath $tempFrame) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
    if ($receipt.status -ne 'completed' -or -not (Test-Path -LiteralPath $tempFrame) -or (Get-Item -LiteralPath $tempFrame).Length -lt 4096) { throw "Native engine frame '$Label' was not captured." }
    Move-Item -LiteralPath $tempFrame -Destination $Destination -Force
}

function Write-ResumeEvent([string]$Path, [string]$Name, [string]$Utc, [string]$Action, $State, $Receipt = $null) {
    $event = [ordered]@{ event = $Name; utc = $Utc; action = $Action; commandId = if ($Receipt) { [string]$Receipt.commandId } else { $null }; gameState = if ($State) { [string]$State.context.gameState } else { $null }; menuId = if ($State) { [string]$State.context.menuId } else { $null }; currentSettlementId = if ($State) { [string]$State.location.currentSettlementId } else { $null }; targetSettlementId = if ($State) { [string]$State.location.targetSettlementId } else { $null }; campaignDay = if ($Receipt) { $Receipt.campaignDay } elseif ($State) { $State.campaignDay } else { $null } }
    Add-Content -LiteralPath $Path -Value ($event | ConvertTo-Json -Compress -Depth 6) -Encoding UTF8
}

function Stop-CaptureIfRunning($Capture, $ContactSheet, $Events) {
    if (-not $Capture) { return $null }
    return Stop-ChronicleWindowVideoCapture -Capture $Capture -ContactSheetPath $ContactSheet -EventTracePath $Events
}

try {
    . $videoLibrary
    Set-Content -LiteralPath $firstEvents -Value '' -Encoding UTF8
    Set-Content -LiteralPath $secondEvents -Value '' -Encoding UTF8
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $env:CHRONICLE_LLM_TIMEOUT_SECONDS = '180'
    $env:CHRONICLE_LLM_MAX_TOKENS = '512'

    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $sessionStarted = $true
    $baseline = Invoke-AgentCli 'state'
    if ($baseline.state.context.gameState -ne 'MapState' -or $baseline.state.context.encounterActive) { throw 'Live-resume source must start in an unobstructed Campaign Map.' }
    Capture-EngineFrame 'LiveResume-before-save' $frameBeforeSave
    $firstCapture = Start-ChronicleWindowVideoCapture -ProcessId ([int]$start.session.processId) -OutputPath $firstVideo -FrameRate 10
    Write-ResumeEvent $firstEvents 'capture-start' $firstCapture.StartedUtc 'capture' $baseline.state $baseline

    if ($CrashAfterRecruit) {
        $firstOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -Goal $goal -AllowedActionNames $allowedActions -PersistCheckpoint -HarnessCrashAfterAction recruit -MaxDecisions 24 -MaxElapsedSeconds 600 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ($prefix + '-initial') 2>&1 | Out-String
        $firstCrashExitCode = $LASTEXITCODE
        if ($firstCrashExitCode -ne 93) { try { $firstLoopTrace = $firstOutput | ConvertFrom-Json } catch { }; throw "Harness did not stop the Agent runtime immediately after the Native recruit action; exit=$firstCrashExitCode output=$firstOutput" }
        $crashObservation = Invoke-AgentCli 'state' @('-CommandId', ($prefix + '-after-runtime-crash'))
        $checkpointBeforeSave = Invoke-AgentCli 'agentCheckpointGet' @('-CommandId', ($prefix + '-checkpoint-after-runtime-crash'))
        if ($checkpointBeforeSave.status -ne 'completed' -or [string]::IsNullOrWhiteSpace([string]$checkpointBeforeSave.data.checkpointBase64)) { throw 'Native Campaign lost the pending checkpoint after the simulated Agent runtime failure.' }
        $checkpointBeforeSaveJson = [Text.UTF8Encoding]::new($false, $true).GetString([Convert]::FromBase64String([string]$checkpointBeforeSave.data.checkpointBase64))
        $checkpointBeforeSaveObject = $checkpointBeforeSaveJson | ConvertFrom-Json
        $pending = $checkpointBeforeSaveObject.pendingAction
        if ([string]$checkpointBeforeSaveObject.status -ne 'active' -or [string]$checkpointBeforeSaveObject.goal -cne $goal -or [string]$checkpointBeforeSaveObject.lastActionReceipt.action -cne 'recruitOptions' -or [string]$pending.action -cne 'recruit' -or [int]$pending.expectedCost -le 0) {
            throw 'Native checkpoint did not preserve the prior offer receipt plus pending recruit intent at the injected runtime failure boundary.'
        }
        $crashAfterRecruitVerified = ([int]$crashObservation.state.party.members -eq [int]$pending.expectedMembersAfter -and [int]$crashObservation.state.economy.gold -eq [int]$pending.expectedGoldAfter)
        if (-not $crashAfterRecruitVerified) { throw 'The real Native recruit side effect was not visible after terminating the Agent runtime.' }
        $postCrashOptions = Invoke-AgentCli 'recruitOptions' @('-CommandId', ($prefix + '-after-crash-recruit-options'))
        $sameSlotStillAvailable = @($postCrashOptions.data.offers | Where-Object { $_.available -and [string]$_.ownerId -ceq [string]$pending.arguments.OwnerId -and [string]$_.troopId -ceq [string]$pending.arguments.TroopId -and [int]$_.slot -eq [int]$pending.arguments.VolunteerSlot }).Count -gt 0
        if ($sameSlotStillAvailable) { throw 'The Native volunteer slot remained available after the interrupted recruit transaction.' }
        $initialSteps = @()
        $initialTargetId = [string]$checkpointBeforeSaveObject.lastActionReceipt.state.location.targetSettlementId
        Write-ResumeEvent $firstEvents 'runtime-terminated-after-native-recruit' ([DateTime]::UtcNow.ToString('O')) 'recruit' $crashObservation.state $null
    }
    else {
        $firstOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -Goal $goal -AllowedActionNames $allowedActions -PersistCheckpoint -MaxDecisions 2 -MaxElapsedSeconds 240 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ($prefix + '-initial') 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { try { $firstLoopTrace = $firstOutput | ConvertFrom-Json } catch { }; throw "Initial model segment failed before checkpoint save: $firstOutput" }
        $firstLoopTrace = $firstOutput | ConvertFrom-Json
        $initialSteps = @($firstLoopTrace.trace)
        if ($initialSteps.Count -ne 2 -or $initialSteps[0].decision.action -ne 'mapSettlementTargets' -or $initialSteps[1].decision.action -ne 'move' -or [int]$firstLoopTrace.actionsExecuted -ne 2) {
            throw 'The real model did not complete exactly one Native target query and one move before the planned checkpoint boundary.'
        }
        $initialTargetId = [string]$initialSteps[1].decision.arguments.SettlementId
        foreach ($step in $initialSteps) {
            $state = $step.observationAfter.state
            Write-ResumeEvent $firstEvents 'initial-model-action' $step.timing.actionCompletedUtc ([string]$step.actionReceipt.action) $state $step.actionReceipt
        }
        $checkpointBeforeSave = Invoke-AgentCli 'agentCheckpointGet' @('-CommandId', ($prefix + '-checkpoint-before-save'))
        if ($checkpointBeforeSave.status -ne 'completed' -or [string]::IsNullOrWhiteSpace([string]$checkpointBeforeSave.data.checkpointBase64)) { throw 'Native Campaign checkpoint was not present before saving.' }
        $checkpointBeforeSaveJson = [Text.UTF8Encoding]::new($false, $true).GetString([Convert]::FromBase64String([string]$checkpointBeforeSave.data.checkpointBase64))
        $checkpointBeforeSaveObject = $checkpointBeforeSaveJson | ConvertFrom-Json
        if ([string]$checkpointBeforeSaveObject.status -ne 'active' -or [string]$checkpointBeforeSaveObject.goal -cne $goal -or [string]$checkpointBeforeSaveObject.lastActionReceipt.action -cne 'move' -or [string]$checkpointBeforeSaveObject.lastActionReceipt.state.location.targetSettlementId -cne $initialTargetId) {
            throw 'Persisted checkpoint did not hold the active goal and the confirmed Native move receipt.'
        }
    }
    Capture-EngineFrame 'LiveResume-before-save-checkpoint' $frameBeforeSave
    $firstCaptureResult = Stop-CaptureIfRunning $firstCapture $firstContactSheet $firstEvents
    $firstCapture = $null
    if ($RuntimeOnlyResume -or $CrashAfterRecruit) {
        $boundaryState = if ($CrashAfterRecruit) { $crashObservation.state } else { $initialSteps[-1].observationAfter.state }
        $boundaryEventName = if ($CrashAfterRecruit) { 'runtime-crash-after-recruit' } else { 'agent-runtime-loop-ended' }
        Write-ResumeEvent $firstEvents $boundaryEventName ([DateTime]::UtcNow.ToString('O')) 'decisionLoop' $boundaryState $null
        $resumeBaseline = Invoke-AgentCli 'state' @('-CommandId', ($prefix + '-runtime-restart-baseline'))
        $checkpointAfterLoad = Invoke-AgentCli 'agentCheckpointGet' @('-CommandId', ($prefix + '-runtime-restart-checkpoint'))
        if ([int]$resumeBaseline.processId -ne [int]$start.session.processId) { throw 'Bannerlord PID changed across the Agent-only runtime restart.' }
        if ($checkpointAfterLoad.status -ne 'completed' -or [string]$checkpointAfterLoad.data.campaignInstanceId -cne [string]$checkpointBeforeSave.data.campaignInstanceId) { throw 'In-memory Campaign checkpoint did not survive the Agent-only restart.' }
        if ($CrashAfterRecruit -and ([int]$resumeBaseline.state.party.members -ne [int]$crashObservation.state.party.members -or [int]$resumeBaseline.state.economy.gold -ne [int]$crashObservation.state.economy.gold)) { throw 'The committed Native recruitment changed while only the Agent runtime restarted.' }
        $resumeStart = $start
        Capture-EngineFrame 'LiveResume-after-load' $frameAfterLoad
    }
    else {
        Write-ResumeEvent $firstEvents 'save-begin' ([DateTime]::UtcNow.ToString('O')) 'save' $initialSteps[-1].observationAfter.state $null
        $save = Invoke-AgentCli 'save' @('-SaveName', $resumeSaveName, '-CommandId', ($prefix + '-save')) $TimeoutSeconds
        if ($save.status -ne 'completed' -or -not (Test-Path -LiteralPath $resumeSavePath -PathType Leaf)) { throw 'Campaign checkpoint save did not complete into its disposable save file.' }
        Write-ResumeEvent $firstEvents 'save-complete' ([DateTime]::UtcNow.ToString('O')) 'save' $save.state $save
        $firstStop = Invoke-AgentCli 'stop' @('-CommandId', ($prefix + '-stop-before-reload'))
        $sessionStarted = $false
        if (-not $firstStop.processStopped -or (Get-Process -Name Bannerlord* -ErrorAction SilentlyContinue)) { throw 'Initial Bannerlord/Agent process remained active before checkpoint reload.' }
        $resumeStart = Invoke-AgentCli 'load' @('-SaveName', $resumeSaveName)
        $sessionStarted = $true
        $resumeBaseline = Invoke-AgentCli 'state' @('-CommandId', ($prefix + '-resume-baseline'))
        $checkpointAfterLoad = Invoke-AgentCli 'agentCheckpointGet' @('-CommandId', ($prefix + '-checkpoint-after-load'))
        if ($checkpointAfterLoad.status -ne 'completed' -or [string]$checkpointAfterLoad.data.campaignInstanceId -cne [string]$checkpointBeforeSave.data.campaignInstanceId) { throw 'Campaign instance identity did not survive Native save/load.' }
        Capture-EngineFrame 'LiveResume-after-load' $frameAfterLoad
    }
    $checkpointAfterLoadJson = [Text.UTF8Encoding]::new($false, $true).GetString([Convert]::FromBase64String([string]$checkpointAfterLoad.data.checkpointBase64))
    $checkpointAfterLoadObject = $checkpointAfterLoadJson | ConvertFrom-Json
    $goalRestored = ([string]$checkpointAfterLoadObject.goal -ceq $goal -and [string]$checkpointAfterLoadObject.status -eq 'active' -and [string]$checkpointAfterLoadObject.campaignInstanceId -ceq [string]$checkpointBeforeSave.data.campaignInstanceId)
    $expectedSavedReceiptAction = if ($CrashAfterRecruit) { 'recruitOptions' } else { 'move' }
    if ([string]$checkpointAfterLoadObject.goal -cne $goal -or [string]$checkpointAfterLoadObject.lastActionReceipt.action -cne $expectedSavedReceiptAction) { throw 'Saved goal or last confirmed Native receipt was not restored.' }
    if ($CrashAfterRecruit -and [string]$checkpointAfterLoadObject.pendingAction.action -cne 'recruit') { throw 'The pending non-idempotent Native recruit intent was not retained across Agent runtime failure.' }
    $secondCapture = Start-ChronicleWindowVideoCapture -ProcessId ([int]$resumeStart.session.processId) -OutputPath $secondVideo -FrameRate $FrameRate
    Write-ResumeEvent $secondEvents 'capture-start-after-reload' $secondCapture.StartedUtc 'capture' $resumeBaseline.state $resumeBaseline

    $resumeOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -AllowedActionNames $allowedActions -ResumeCheckpoint -MaxDecisions 24 -MaxElapsedSeconds 600 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ($prefix + '-resume') 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { try { $resumeLoopTrace = $resumeOutput | ConvertFrom-Json } catch { }; throw "Real-model checkpoint resume failed: $resumeOutput" }
    $resumeLoopTrace = $resumeOutput | ConvertFrom-Json
    $resumeSteps = @($resumeLoopTrace.trace)
    foreach ($step in $resumeSteps) {
        $decisionName = if ($step.decision.done -eq $true) { 'providerDone' } elseif ($step.decision.observeAgain -eq $true) { 'observeAgain' } else { [string]$step.decision.action }
        $state = if ($step.observationAfter.state) { $step.observationAfter.state } elseif ($step.observationBefore.state) { $step.observationBefore.state } else { $resumeBaseline.state }
        Write-ResumeEvent $secondEvents ('resumed-decision-' + [int]$step.iteration) ([string]$step.timing.providerCompletedUtc) $decisionName $state $step.actionReceipt
    }
    $resumeRecruitmentSteps = @($resumeSteps | Where-Object { $_.decision.action -eq 'recruit' -and $_.actionReceipt.status -eq 'completed' })
    $resumeOfferSteps = @($resumeSteps | Where-Object { $_.decision.action -eq 'recruitOptions' -and $_.actionReceipt.status -eq 'completed' })
    $resumeMoveSteps = @($resumeSteps | Where-Object { $_.decision.action -eq 'move' -and $_.actionExecuted })
    $resumeRecruitDecisions = @($resumeSteps | Where-Object { $_.decision.action -eq 'recruit' })
    $expectedResumeReceiptAction = if ($CrashAfterRecruit) { 'recruit' } else { 'move' }
    if ($resumeSteps.Count -eq 0 -or [string]$resumeSteps[0].previousActionReceipt.action -cne $expectedResumeReceiptAction) { throw 'Resumed model request did not receive the reconciled/saved Native action receipt.' }
    $moveNotRepeated = ($resumeMoveSteps.Count -eq 0)
    if (-not $moveNotRepeated) { throw 'Resumed model repeated a Native move already confirmed in the saved checkpoint.' }
    if ($CrashAfterRecruit) {
        $recoveredReceipt = $resumeSteps[0].previousActionReceipt
        if ([bool]$recoveredReceipt.data.recoveredAfterRuntimeInterruption -ne $true -or $resumeRecruitDecisions.Count -gt 0 -or $resumeOfferSteps.Count -gt 0) { throw 'The resumed model did not reconcile the committed recruitment before deciding; a second recruit attempt was issued.' }
        $recruitmentVerified = [bool]$crashAfterRecruitVerified
    }
    else {
        if ($resumeOfferSteps.Count -ne 1 -or $resumeRecruitmentSteps.Count -ne 1) { throw 'Resumed model did not inspect and submit exactly one Native recruitment offer.' }
        $offerStep = $resumeOfferSteps[0]
        $recruitStep = $resumeRecruitmentSteps[0]
        $menuOption = @($offerStep.observationBefore.state.availableMenuOptions | Where-Object { $_.id -eq 'recruit_volunteers' -and $_.available -and $_.enabled } | Select-Object -First 1)
        $chosenOffer = @($offerStep.actionReceipt.data.offers | Where-Object { $_.available -and [string]$_.ownerId -ceq [string]$recruitStep.decision.arguments.OwnerId -and [string]$_.troopId -ceq [string]$recruitStep.decision.arguments.TroopId -and [int]$_.slot -eq [int]$recruitStep.decision.arguments.VolunteerSlot -and [int]$_.cost -le [int]$offerStep.observationBefore.state.economy.gold } | Select-Object -First 1)
        $recruitBefore = $recruitStep.observationBefore.state
        $recruitAfter = $recruitStep.observationAfter.state
        $recruitmentVerified = ($menuOption.Count -eq 1 -and $offerStep.observationBefore.state.location.currentSettlementId -ceq $initialTargetId -and $chosenOffer.Count -eq 1 -and [bool]$recruitStep.actionReceipt.data.verified -and [int]$recruitAfter.party.members -eq ([int]$recruitBefore.party.members + 1) -and [int]$recruitBefore.economy.gold - [int]$recruitAfter.economy.gold -eq [int]$chosenOffer[0].cost)
        if (-not $recruitmentVerified) { throw 'Resumed Native recruitment did not match the current menu option, offer, party delta, and Gold cost.' }
    }
    $providerStoppedAfterGoal = ([bool]$resumeLoopTrace.termination.completedByProvider -and [bool]$resumeSteps[-1].decision.done)
    if (-not $providerStoppedAfterGoal) { throw 'Resumed real model did not stop after the goal postconditions were observed.' }
    Capture-EngineFrame 'LiveResume-after-goal' $frameAfterGoal
    Write-ResumeEvent $secondEvents 'goal-complete' ([DateTime]::UtcNow.ToString('O')) 'recruitmentVerified' $recruitAfter $recruitStep.actionReceipt
    $secondCaptureResult = Stop-CaptureIfRunning $secondCapture $secondContactSheet $secondEvents
    $secondCapture = $null
    $finalStop = Invoke-AgentCli 'stop' @('-CommandId', ($prefix + '-final-stop'))
    $sessionStarted = $false
}
catch {
    $failure = $_.Exception.Message
    if ($sessionStarted) { try { Capture-EngineFrame 'LiveResume-failure' $frameFailure } catch { } }
}
finally {
    foreach ($captureEntry in @(
        [pscustomobject]@{ Capture = $firstCapture; Video = $firstVideo; Sheet = $firstContactSheet; Events = $firstEvents },
        [pscustomobject]@{ Capture = $secondCapture; Video = $secondVideo; Sheet = $secondContactSheet; Events = $secondEvents }
    )) {
        if ($captureEntry.Capture) {
            try { $null = Stop-CaptureIfRunning $captureEntry.Capture $captureEntry.Sheet $captureEntry.Events }
            catch { try { if ($captureEntry.Capture.Process -and -not $captureEntry.Capture.Process.HasExited) { $captureEntry.Capture.Process.Kill() } } catch { } }
        }
    }
    if ($sessionStarted -or (Test-Path -LiteralPath $sessionPath -PathType Leaf)) { try { $finalStop = Invoke-AgentCli 'stop' @('-CommandId', ($prefix + '-cleanup-stop'), '-TimeoutSeconds', '15') } catch { } }
    if ($null -eq $priorHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $priorHarnessMode }
    if ($null -eq $priorModelTimeout) { Remove-Item Env:CHRONICLE_LLM_TIMEOUT_SECONDS -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_LLM_TIMEOUT_SECONDS = $priorModelTimeout }
    if ($null -eq $priorModelMaxTokens) { Remove-Item Env:CHRONICLE_LLM_MAX_TOKENS -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_LLM_MAX_TOKENS = $priorModelMaxTokens }
}

$fixtureHashAfter = if (Test-Path -LiteralPath $sourceSavePath -PathType Leaf) { (Get-FileHash -LiteralPath $sourceSavePath -Algorithm SHA256).Hash } else { $null }
$sourceFixtureUnchanged = ($fixtureHashBefore -ceq $fixtureHashAfter)
$processStopped = ([bool]$finalStop.processStopped -and -not (Test-Path -LiteralPath $sessionPath -PathType Leaf) -and -not (Get-Process -Name Bannerlord* -ErrorAction SilentlyContinue))
$firstCapturePassed = ($firstCaptureResult -and $firstCaptureResult.Passed -and [double]$firstCaptureResult.FrameCoverageRatio -ge 0.9)
$secondCapturePassed = ($secondCaptureResult -and $secondCaptureResult.Passed -and [double]$secondCaptureResult.FrameCoverageRatio -ge 0.9)
$runtimeRunIdChanged = if ($CrashAfterRecruit) { ($firstCrashExitCode -eq 93 -and $null -ne $resumeLoopTrace.runId) } else { ($firstLoopTrace -and $resumeLoopTrace -and [string]$firstLoopTrace.runId -cne [string]$resumeLoopTrace.runId) }
$runtimeBoundaryVerified = if ($RuntimeOnlyResume -or $CrashAfterRecruit) { ([int]$start.session.processId -eq [int]$resumeStart.session.processId -and $runtimeRunIdChanged) } else { $true }
$firstSegmentVerified = if ($CrashAfterRecruit) { ($firstCrashExitCode -eq 93 -and $crashAfterRecruitVerified) } else { $null -ne $firstLoopTrace }
$passed = (-not $failure -and $firstSegmentVerified -and $resumeLoopTrace -and $sourceFixtureUnchanged -and $processStopped -and $firstCapturePassed -and $secondCapturePassed -and $goalRestored -and $moveNotRepeated -and $recruitmentVerified -and $runtimeBoundaryVerified)

if (Test-Path -LiteralPath $resumeSavePath -PathType Leaf) {
    $saveRootFull = [IO.Path]::GetFullPath($saveRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $resolvedResumeSave = [IO.Path]::GetFullPath($resumeSavePath)
    if (-not $resolvedResumeSave.StartsWith($saveRootFull, [StringComparison]::OrdinalIgnoreCase)) { throw 'Disposable resume save escaped the expected Game Saves root.' }
    Remove-Item -LiteralPath $resolvedResumeSave -Force
}
if (Test-Path -LiteralPath $resumeBackupPath -PathType Leaf) { Remove-Item -LiteralPath $resumeBackupPath -Force }

$result = [ordered]@{
    ProviderKind = 'configured OpenAI-compatible live model; not a stub'
    Passed = $passed
    Failure = $failure
    InitialDecisions = if ($firstLoopTrace) { $firstLoopTrace.decisions } else { $null }
    ResumeDecisions = if ($resumeLoopTrace) { $resumeLoopTrace.decisions } else { $null }
    FaultInjectionExitCode = $firstCrashExitCode
    CrashAfterNativeRecruitVerified = $crashAfterRecruitVerified
    GoalRestored = $goalRestored
    MoveNotRepeated = $moveNotRepeated
    RecruitmentVerified = $recruitmentVerified
    RuntimeOnlyResume = [bool]$RuntimeOnlyResume
    CrashAfterRecruit = [bool]$CrashAfterRecruit
    BannerlordProcessUnchangedAcrossResume = if ($RuntimeOnlyResume -or $CrashAfterRecruit) { [int]$resumeStart.session.processId -eq [int]$start.session.processId } else { $null }
    RuntimeRunIdChanged = $runtimeRunIdChanged
    SaveReloadPerformed = (-not [bool]$RuntimeOnlyResume)
    SourceFixtureUnchanged = $sourceFixtureUnchanged
    ProcessStopped = $processStopped
    FirstCapture = $firstCaptureResult
    ResumeCapture = $secondCaptureResult
    BeforeSaveFramePath = if (Test-Path -LiteralPath $frameBeforeSave) { $frameBeforeSave } else { $null }
    AfterLoadFramePath = if (Test-Path -LiteralPath $frameAfterLoad) { $frameAfterLoad } else { $null }
    AfterGoalFramePath = if (Test-Path -LiteralPath $frameAfterGoal) { $frameAfterGoal } else { $null }
    FixtureHashBefore = $fixtureHashBefore
    FixtureHashAfter = $fixtureHashAfter
}
$json = $result | ConvertTo-Json -Depth 16
if ($env:CHRONICLE_HARNESS_TEMP -and (Test-Path -LiteralPath $env:CHRONICLE_HARNESS_TEMP -PathType Container)) { Set-Content -LiteralPath (Join-Path $env:CHRONICLE_HARNESS_TEMP 'LiveModelResumeResult.json') -Value $json -Encoding UTF8 }
$json
if (-not $passed) { exit 1 }
