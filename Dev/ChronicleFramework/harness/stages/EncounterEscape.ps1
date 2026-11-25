#Requires -Version 7.0

# EncounterEscape stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'EncounterEscape' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $encounterEscapeScript 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Native Encounter escape/outcome test failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
