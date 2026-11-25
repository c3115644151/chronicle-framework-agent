#Requires -Version 7.0

# LiveModelActionRecovery stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'LiveModelActionRecovery' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $agentLiveModelResumeScript -CrashAfterRecruit 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Live-model post-action checkpoint recovery failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
