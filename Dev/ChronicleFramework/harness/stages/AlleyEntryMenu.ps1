#Requires -Version 7.0

# AlleyEntryMenu stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'AlleyEntryMenu' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $alleyEntryMenuScript 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Native Alley entry/return menu test failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
