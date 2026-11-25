#Requires -Version 7.0

# LiveModelRuntimeResume stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'LiveModelRuntimeResume' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $agentLiveModelResumeScript -RuntimeOnlyResume 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Live-model in-process runtime restart failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
