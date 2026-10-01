[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180,
    [switch]$TimeControlOnly
)

$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$loop = Join-Path $PSScriptRoot 'Agent-DecisionLoop.ps1'
$provider = Join-Path $PSScriptRoot 'Test-AgentLoopProvider.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
if (-not (Test-Path $savePath)) { throw "Agent loop fixture not found: $savePath" }
$fixtureHashBefore = (Get-FileHash $savePath -Algorithm SHA256).Hash

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @()) {
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli $Action @Arguments -TimeoutSeconds $TimeoutSeconds -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

try {
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    if ($TimeControlOnly) {
        $priorProviderMode = $env:CHRONICLE_TEST_PROVIDER_MODE
        $env:CHRONICLE_TEST_PROVIDER_MODE = 'timeModes'
        try {
            $timeModesOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -MaxDecisions 3 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('loop-time-modes-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
            $timeModesExitCode = $LASTEXITCODE
        }
        finally {
            if ($null -eq $priorProviderMode) { Remove-Item Env:CHRONICLE_TEST_PROVIDER_MODE -ErrorAction SilentlyContinue }
            else { $env:CHRONICLE_TEST_PROVIDER_MODE = $priorProviderMode }
        }
        if ($timeModesExitCode -ne 0) { throw "Agent decision loop did not route native time controls: $timeModesOutput" }
        $timeModesTrace = $timeModesOutput | ConvertFrom-Json
        $timeModeSteps = @($timeModesTrace.trace)
        $timeControlsRouted = (
            $timeModeSteps.Count -eq 3 -and
            $timeModeSteps[0].decision.action -eq 'resume' -and
            $timeModeSteps[0].actionReceipt.data.requestedMode -eq 'play' -and
            $timeModeSteps[0].actionReceipt.status -eq 'completed' -and
            $timeModeSteps[1].decision.action -eq 'fastForward' -and
            $timeModeSteps[1].actionReceipt.data.requestedMode -eq 'fastForward' -and
            $timeModeSteps[1].actionReceipt.data.rawModeAfter -in @('StoppableFastForward','UnstoppableFastForward') -and
            $timeModeSteps[1].actionReceipt.status -eq 'completed' -and
            $timeModeSteps[2].decision.action -eq 'pause' -and
            $timeModeSteps[2].actionReceipt.data.requestedMode -eq 'pause' -and
            $timeModeSteps[2].actionReceipt.status -eq 'completed' -and
            $timeModeSteps[2].actionReceipt.data.effectiveModeAfter -in @('Stop','FastForwardStop')
        )
        $playNaturallyAdvancedBeforeNextClockDecision = (
            $timeModeSteps.Count -eq 3 -and
            [double]$timeModeSteps[1].actionReceipt.data.campaignDayBefore -gt [double]$timeModeSteps[0].actionReceipt.data.campaignDayAfter -and
            -not [bool]$timeModeSteps[1].actionReceipt.data.isMainPartyWaitingBefore
        )
        $fastForwardNaturallyAdvancedAfterSelection = (
            $timeModeSteps.Count -eq 3 -and
            [double]$timeModeSteps[1].observationAfter.campaignDay -gt [double]$timeModeSteps[1].actionReceipt.data.campaignDayAfter -and
            $timeModeSteps[1].actionReceipt.data.effectiveModeAfter -in @('StoppableFastForward','UnstoppableFastForward') -and
            -not [bool]$timeModeSteps[1].actionReceipt.data.isMainPartyWaitingAfter
        )
        $pauseHeldCampaignDay = (
            $timeModeSteps.Count -eq 3 -and
            [double]$timeModeSteps[2].observationAfter.campaignDay -eq [double]$timeModeSteps[2].actionReceipt.data.campaignDayAfter
        )
        $timeModesStop = Invoke-AgentCli 'stop'
        $priorProviderMode = $env:CHRONICLE_TEST_PROVIDER_MODE
        $env:CHRONICLE_TEST_PROVIDER_MODE = 'waitingResume'
        try {
            $waitingStart = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
            $waitingResumeOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -MaxDecisions 2 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('loop-waiting-resume-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
            $waitingResumeExitCode = $LASTEXITCODE
        }
        finally {
            if ($null -eq $priorProviderMode) { Remove-Item Env:CHRONICLE_TEST_PROVIDER_MODE -ErrorAction SilentlyContinue }
            else { $env:CHRONICLE_TEST_PROVIDER_MODE = $priorProviderMode }
        }
        if ($waitingResumeExitCode -ne 0) { throw "Agent decision loop did not resume native time from Hold/waiting: $waitingResumeOutput" }
        $waitingResumeTrace = ($waitingResumeOutput | ConvertFrom-Json).trace
        $waitingResumeVerified = (
            @($waitingResumeTrace).Count -eq 2 -and
            $waitingResumeTrace[0].decision.action -eq 'hold' -and
            $waitingResumeTrace[0].actionReceipt.status -eq 'completed' -and
            $waitingResumeTrace[1].decision.action -eq 'resume' -and
            $waitingResumeTrace[1].actionReceipt.status -eq 'completed' -and
            $waitingResumeTrace[1].actionReceipt.data.effectiveModeAfter -eq 'UnstoppablePlay' -and
            [bool]$waitingResumeTrace[1].actionReceipt.data.isMainPartyWaitingBefore -and
            [double]$waitingResumeTrace[1].observationAfter.campaignDay -gt [double]$waitingResumeTrace[1].actionReceipt.data.campaignDayAfter -and
            [bool]$waitingResumeTrace[1].observationAfter.state.context.isWaiting
        )
        $waitingResumeStop = Invoke-AgentCli 'stop'
        $fixtureHashAfter = (Get-FileHash $savePath -Algorithm SHA256).Hash
        $timeControlResult = [ordered]@{
            ProviderKind = 'deterministic-test-only'
            ProcessId = $start.session.processId
            DecisionCount = $timeModeSteps.Count
            NativeTimeControlActionsRouted = $timeControlsRouted
            PlayModeNaturallyAdvancedBeforeFastForwardSelection = $playNaturallyAdvancedBeforeNextClockDecision
            FastForwardNaturallyAdvanced = $fastForwardNaturallyAdvancedAfterSelection
            PauseHeldCampaignDay = $pauseHeldCampaignDay
            WaitingHoldThenResumeAdvancedNaturally = $waitingResumeVerified
            TimeControlTrace = $timeModesTrace.trace
            WaitingResumeTrace = $waitingResumeTrace
            FixtureUnchanged = $fixtureHashBefore -eq $fixtureHashAfter
            ProcessStopped = ($timeModesStop.processStopped -and $waitingResumeStop.processStopped)
        }
        $timeControlResult.Passed = ($timeControlsRouted -and $playNaturallyAdvancedBeforeNextClockDecision -and $fastForwardNaturallyAdvancedAfterSelection -and $pauseHeldCampaignDay -and $waitingResumeVerified -and $timeControlResult.FixtureUnchanged -and $timeControlResult.ProcessStopped)
        $timeControlJson = $timeControlResult | ConvertTo-Json -Depth 12
        if ($env:CHRONICLE_HARNESS_TEMP -and (Test-Path -LiteralPath $env:CHRONICLE_HARNESS_TEMP -PathType Container)) {
            Set-Content -LiteralPath (Join-Path $env:CHRONICLE_HARNESS_TEMP 'AgentTimeControlLoopResult.json') -Value $timeControlJson -Encoding UTF8
        }
        $timeControlJson
        if (-not $timeControlResult.Passed) { exit 1 }
        return
    }

    $priorInvalidDecision = $env:CHRONICLE_TEST_INVALID_DECISION
    $env:CHRONICLE_TEST_INVALID_DECISION = '1'
    try {
        $invalidOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -MaxDecisions 1 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('loop-invalid-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
        $invalidExitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $priorInvalidDecision) { Remove-Item Env:CHRONICLE_TEST_INVALID_DECISION -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_TEST_INVALID_DECISION = $priorInvalidDecision }
    }
    $unsafeActionRejected = ($invalidExitCode -ne 0 -and $invalidOutput -match 'allowlist')
    if (-not $unsafeActionRejected) { throw "Unsafe provider action rejection check failed (exit=$invalidExitCode, message=$($invalidOutput -match 'allowlist')): $invalidOutput" }
    $priorInvalidDecision = $env:CHRONICLE_TEST_INVALID_DECISION
    $env:CHRONICLE_TEST_INVALID_DECISION = 'advance'
    try {
        $harnessClockOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -MaxDecisions 1 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('loop-clock-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
        $harnessClockExitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $priorInvalidDecision) { Remove-Item Env:CHRONICLE_TEST_INVALID_DECISION -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_TEST_INVALID_DECISION = $priorInvalidDecision }
    }
    $harnessClockRejected = ($harnessClockExitCode -ne 0 -and $harnessClockOutput -match 'Harness-only deterministic time step')
    if (-not $harnessClockRejected) { throw "Harness-only advance boundary check failed: $harnessClockOutput" }
    $priorProviderMode = $env:CHRONICLE_TEST_PROVIDER_MODE
    $env:CHRONICLE_TEST_PROVIDER_MODE = 'observationLoop'
    try {
        $loopOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -MaxDecisions 2 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('loop-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
        $loopExitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $priorProviderMode) { Remove-Item Env:CHRONICLE_TEST_PROVIDER_MODE -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_TEST_PROVIDER_MODE = $priorProviderMode }
    }
    if ($loopExitCode -ne 0) { throw "Agent decision loop failed: $loopOutput" }
    $trace = $loopOutput | ConvertFrom-Json
    $first = $trace.trace[0]
    $second = $trace.trace[1]
    $observationLoopVerified = ($trace.trace.Count -eq 2 -and $first.decision.action -eq 'state' -and $first.actionReceipt.status -eq 'completed' -and $second.decision.action -eq 'mapPartyTargets' -and $second.actionReceipt.status -eq 'completed')
    $receiptForwarded = ($second.previousActionReceipt.commandId -eq $first.actionReceipt.commandId -and $second.previousActionReceipt.action -eq $first.actionReceipt.action -and $second.previousActionReceipt.status -eq $first.actionReceipt.status)
    $priorProviderMode = $env:CHRONICLE_TEST_PROVIDER_MODE
    $env:CHRONICLE_TEST_PROVIDER_MODE = 'doneSignal'
    try {
        $doneOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -MaxDecisions 4 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('loop-done-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
        $doneExitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $priorProviderMode) { Remove-Item Env:CHRONICLE_TEST_PROVIDER_MODE -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_TEST_PROVIDER_MODE = $priorProviderMode }
    }
    if ($doneExitCode -ne 0) { throw "Agent loop did not stop on the provider's explicit goal-complete signal: $doneOutput" }
    $doneTrace = $doneOutput | ConvertFrom-Json
    $doneSignalVerified = ($doneTrace.trace.Count -eq 2 -and $doneTrace.actionsExecuted -eq 1 -and $doneTrace.termination.completedByProvider -and $doneTrace.termination.reason -eq 'provider-stop' -and -not $doneTrace.trace[1].actionExecuted -and $doneTrace.trace[1].decision.done)
    $stop = Invoke-AgentCli 'stop'
    $fixtureHashAfter = (Get-FileHash $savePath -Algorithm SHA256).Hash
    $result = [ordered]@{
        ProviderKind = 'deterministic-test-only'
        ProcessId = $start.session.processId
        DecisionCount = @($trace.trace).Count
        ObservationActionObservationVerified = $observationLoopVerified
        FirstDecision = $first.decision.action
        SecondDecision = $second.decision.action
        PreviousActionReceiptForwarded = $receiptForwarded
        ExplicitGoalStopHonoredWithoutIssuingAnotherAction = $doneSignalVerified
        GoalStopTrace = $doneTrace.trace
        UnsafeActionRejected = $unsafeActionRejected
        HarnessAdvanceRejected = $harnessClockRejected
        FixtureUnchanged = $fixtureHashBefore -eq $fixtureHashAfter
        ProcessStopped = $stop.processStopped
        Trace = $trace.trace
    }
    $result.Passed = ($result.DecisionCount -eq 2 -and $observationLoopVerified -and $receiptForwarded -and $doneSignalVerified -and $unsafeActionRejected -and $harnessClockRejected -and $result.FixtureUnchanged -and $result.ProcessStopped)
    $result | ConvertTo-Json -Depth 12
    if (-not $result.Passed) { exit 1 }
}
finally {
    if (Test-Path $sessionPath) { try { Invoke-AgentCli 'stop' | Out-Null } catch { } }
}
