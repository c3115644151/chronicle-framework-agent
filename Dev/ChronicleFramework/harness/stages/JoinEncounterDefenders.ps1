#Requires -Version 7.0

# JoinEncounterDefenders stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'JoinEncounterDefenders' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $joinEncounterScript 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Native Join Encounter Help Defenders test failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
