#Requires -Version 7.0

# Observation stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'Observation' -Action {
    & $HarnessPowerShell -NoProfile -File $observationScript
    if ($LASTEXITCODE -ne 0) { throw "Agent observation test failed with exit code $LASTEXITCODE." }
}
