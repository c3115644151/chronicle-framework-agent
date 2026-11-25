#Requires -Version 7.0

# EngageVisibility stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'EngageVisibility' -Action {
    $previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    try {
        $testOutput = & $HarnessPowerShell -NoProfile -File $pursuitScript -ProbeEngageVisibilityLoss -VisibilityProbeSeconds $VisibilityProbeSeconds -TimeoutSeconds 240 2>&1 | Out-String
        $testExitCode = $LASTEXITCODE
        if ($testExitCode -ne 0) { throw "Agent Engage visibility probe failed with exit code $testExitCode.`n$testOutput" }
    }
    finally {
        if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
    }
}
