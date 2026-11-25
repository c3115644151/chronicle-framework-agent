#Requires -Version 7.0

# TimeControlLoop stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'TimeControlLoop' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $agentLoopScript -TimeControlOnly 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Native time-control decision loop test failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
