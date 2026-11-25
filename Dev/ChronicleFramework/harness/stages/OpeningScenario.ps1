#Requires -Version 7.0

# OpeningScenario stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'OpeningScenario' -Action {
    & $HarnessPowerShell -NoProfile -File $openingScenarioScript
    if ($LASTEXITCODE -ne 0) { throw "Opening scenario window failed with exit code $LASTEXITCODE." }
}
