#Requires -Version 7.0

# JoinEncounterAbandonArmy stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'JoinEncounterAbandonArmy' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $joinEncounterAbandonArmyScript 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Native Join Encounter Abandon Army test failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
