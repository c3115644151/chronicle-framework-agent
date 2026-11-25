#Requires -Version 7.0

# ReleasePackage stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'ReleasePackage' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $agentHostReleasePackageScript 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Isolated Chronicle release package verification failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
