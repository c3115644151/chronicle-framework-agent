#Requires -Version 7.0

# LiveModelResume stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'LiveModelResume' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $agentLiveModelResumeScript 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Live-model Native Campaign checkpoint resume failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
