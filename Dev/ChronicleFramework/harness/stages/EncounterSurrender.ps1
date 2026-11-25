#Requires -Version 7.0

# EncounterSurrender stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'EncounterSurrender' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $encounterSurrenderScript 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Native Encounter surrender/captivity test failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
