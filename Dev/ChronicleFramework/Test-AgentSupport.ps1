function Wait-ForAgentSettlementArrival {
    param(
        [Parameter(Mandatory = $true)][string]$CliPath,
        [Parameter(Mandatory = $true)][string]$SettlementId,
        [Parameter(Mandatory = $true)][string]$CommandPrefix,
        [int]$TimeoutSeconds = 180,
        [double]$StepDays = 0.25,
        [int]$MaximumSteps = 12
    )

    for ($step = 1; $step -le $MaximumSteps; $step++) {
        $commandId = "$CommandPrefix-step-$step"
        $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $CliPath advance -Days $StepDays -CommandId $commandId -TimeoutSeconds $TimeoutSeconds 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "Harness time step '$commandId' failed: $output" }
        try { $receipt = $output | ConvertFrom-Json }
        catch { throw "Harness time step '$commandId' returned invalid JSON: $output" }
        if ($receipt.state.location.currentSettlementId -eq $SettlementId) { return $receipt }
        if ($receipt.state.context.encounterActive) {
            throw "Unexpected encounter '$($receipt.state.context.encounteredPartyId)' interrupted travel to settlement '$SettlementId'."
        }
    }

    throw "Main party did not arrive at '$SettlementId' within $MaximumSteps explicit Harness time steps."
}

function Capture-HarnessFailureFrame {
    param(
        [Parameter(Mandatory = $true)][string]$CliPath,
        [Parameter(Mandatory = $true)][string]$CommandPrefix,
        [Parameter(Mandatory = $true)][string]$FailedStep,
        [Parameter(Mandatory = $true)][string]$FailureReason,
        [int]$TimeoutSeconds = 15
    )

    $captureRoot = $env:CHRONICLE_HARNESS_TEMP
    if ([string]::IsNullOrWhiteSpace($captureRoot) -or -not (Test-Path -LiteralPath $captureRoot -PathType Container)) {
        return [ordered]@{ Captured = $false; Reason = 'Harness temporary directory is unavailable.' }
    }
    $sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
    if (-not (Test-Path -LiteralPath $sessionPath)) {
        return [ordered]@{ Captured = $false; Reason = 'Harness game session receipt is unavailable.' }
    }
    try { $session = Get-Content -LiteralPath $sessionPath -Raw | ConvertFrom-Json }
    catch { return [ordered]@{ Captured = $false; Reason = 'Harness game session receipt could not be read.' } }
    $processId = 0
    if (-not [int]::TryParse([string]$session.processId, [ref]$processId) -or -not (Get-Process -Id $processId -ErrorAction SilentlyContinue)) {
        return [ordered]@{ Captured = $false; Reason = 'Harness-owned game process is no longer running; no other window was targeted.' }
    }

    $frameName = 'harness-failure-frame.bmp'
    $framePath = Join-Path $captureRoot $frameName
    $commandId = "$CommandPrefix-failure-frame"
    $receipt = [ordered]@{
        Captured = $false
        ProcessId = $processId
        FailedStep = $FailedStep
        FailureReason = $FailureReason
        FramePath = $framePath
        CaptureCommandId = $commandId
        CaptureError = $null
        CaptureSource = 'captureFrame'
    }
    try {
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $CliPath captureFrame -OutputPath $framePath -CommandId $commandId -TimeoutSeconds $TimeoutSeconds -AsJson 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { $receipt.CaptureError = $output }
        else {
            try { $capture = $output | ConvertFrom-Json }
            catch { $capture = $null; $receipt.CaptureError = "captureFrame returned invalid JSON: $output" }
            $receipt.Captured = ($capture -and $capture.status -eq 'completed' -and (Test-Path -LiteralPath $framePath -PathType Leaf))
            if (-not $receipt.Captured -and -not $receipt.CaptureError) { $receipt.CaptureError = "captureFrame did not produce an engine screenshot; status=$($capture.status)" }
        }
    }
    catch { $receipt.CaptureError = $_.Exception.ToString() }
    if (-not $receipt.Captured) {
        $protocolFramePath = Join-Path $captureRoot 'protocol-unexpected-failure-frame.bmp'
        if (Test-Path -LiteralPath $protocolFramePath -PathType Leaf) {
            $receipt.Captured = $true
            $receipt.FramePath = $protocolFramePath
            $receipt.CaptureSource = 'AgentProtocol unexpected-exception capture'
        }
    }
    $receiptPath = Join-Path $captureRoot 'harness-failure-frame.json'
    $receipt | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
    return $receipt
}
