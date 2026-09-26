[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180
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
    $loopOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -MaxDecisions 2 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('loop-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent decision loop failed: $loopOutput" }
    $trace = $loopOutput | ConvertFrom-Json
    $first = $trace.trace[0]
    $second = $trace.trace[1]
    $firstState = [string]$first.observationBefore.timeControlMode
    if (-not $firstState) { $firstState = [string]$first.observationBefore.state.timeControlMode }
    $firstAfter = [string]$first.observationAfter.timeControlMode
    if (-not $firstAfter) { $firstAfter = [string]$first.observationAfter.state.timeControlMode }
    $secondAfter = [string]$second.observationAfter.timeControlMode
    if (-not $secondAfter) { $secondAfter = [string]$second.observationAfter.state.timeControlMode }
    $orderedDecisions = ($first.decision.action -in @('resume','pause') -and $second.decision.action -in @('resume','pause') -and $first.decision.action -ne $second.decision.action)
    $observedTransition = ($firstAfter -ne $firstState -and $secondAfter -in @('Stop','FastForwardStop'))
    $receiptForwarded = ($second.previousActionReceipt.commandId -eq $first.actionReceipt.commandId -and $second.previousActionReceipt.action -eq $first.actionReceipt.action -and $second.previousActionReceipt.status -eq $first.actionReceipt.status)
    $priorProviderMode = $env:CHRONICLE_TEST_PROVIDER_MODE
    $env:CHRONICLE_TEST_PROVIDER_MODE = 'point'
    try {
        $pointLoopOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -MaxDecisions 1 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('loop-point-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
        $pointLoopExitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $priorProviderMode) { Remove-Item Env:CHRONICLE_TEST_PROVIDER_MODE -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_TEST_PROVIDER_MODE = $priorProviderMode }
    }
    if ($pointLoopExitCode -ne 0) { throw "Agent decision loop did not route the native free-point movement action: $pointLoopOutput" }
    $pointTrace = $pointLoopOutput | ConvertFrom-Json
    $pointStep = $pointTrace.trace[0]
    $pointTarget = $pointStep.actionReceipt.data.nativeTarget
    $pointDecisionAccepted = (
        $pointStep.decision.action -eq 'moveToPoint' -and
        $pointStep.actionReceipt.status -eq 'completed' -and
        $pointStep.observationAfter.state.party.defaultBehavior -eq 'GoToPoint' -and
        $pointStep.observationAfter.state.location.targetPosition.x -eq $pointTarget.x -and
        $pointStep.observationAfter.state.location.targetPosition.y -eq $pointTarget.y
    )
    $priorProviderMode = $env:CHRONICLE_TEST_PROVIDER_MODE
    $env:CHRONICLE_TEST_PROVIDER_MODE = 'escort'
    try {
        $followLoopOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -MaxDecisions 1 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('loop-escort-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
        $followLoopExitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $priorProviderMode) { Remove-Item Env:CHRONICLE_TEST_PROVIDER_MODE -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_TEST_PROVIDER_MODE = $priorProviderMode }
    }
    if ($followLoopExitCode -ne 0) { throw "Agent decision loop did not route the native Escort action: $followLoopOutput" }
    $followTrace = $followLoopOutput | ConvertFrom-Json
    $followStep = $followTrace.trace[0]
    $followTargetId = [string]$followStep.decision.arguments.PartyId
    $escortDecisionAccepted = ($followStep.decision.action -eq 'follow' -and $followStep.actionReceipt.status -eq 'completed' -and $followStep.observationAfter.state.location.targetPartyId -eq $followTargetId -and $followStep.observationAfter.state.party.defaultBehavior -eq 'EscortParty')
    $stop = Invoke-AgentCli 'stop'
    $fixtureHashAfter = (Get-FileHash $savePath -Algorithm SHA256).Hash
    $result = [ordered]@{
        ProviderKind = 'deterministic-test-only'
        ProcessId = $start.session.processId
        DecisionCount = @($trace.trace).Count
        StateBeforeFirstDecision = $firstState
        FirstDecision = $first.decision.action
        StateAfterFirstAction = $firstAfter
        SecondDecision = $second.decision.action
        StateAfterSecondAction = $secondAfter
        OrderedDecisions = $orderedDecisions
        ObservationActionObservationVerified = $observedTransition
        PreviousActionReceiptForwarded = $receiptForwarded
        PointDecisionRoutedAndObserved = $pointDecisionAccepted
        EscortDecisionRoutedAndObserved = $escortDecisionAccepted
        UnsafeActionRejected = $unsafeActionRejected
        HarnessAdvanceRejected = $harnessClockRejected
        FixtureUnchanged = $fixtureHashBefore -eq $fixtureHashAfter
        ProcessStopped = $stop.processStopped
        Trace = $trace.trace
    }
    $result.Passed = ($result.DecisionCount -eq 2 -and $orderedDecisions -and $observedTransition -and $receiptForwarded -and $pointDecisionAccepted -and $escortDecisionAccepted -and $unsafeActionRejected -and $harnessClockRejected -and $result.FixtureUnchanged -and $result.ProcessStopped)
    $result | ConvertTo-Json -Depth 12
    if (-not $result.Passed) { exit 1 }
}
finally {
    if (Test-Path $sessionPath) { try { Invoke-AgentCli 'stop' | Out-Null } catch { } }
}
