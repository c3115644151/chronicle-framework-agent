#Requires -Version 7.0

# Hold stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'Hold' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $holdScript 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Native Hold behavior test failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
