#Requires -Version 7.0

# LiveModelArrival stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'LiveModelArrival' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $agentLiveModelLoopScript -ArrivalLoop 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Live-model Native arrival loop failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
