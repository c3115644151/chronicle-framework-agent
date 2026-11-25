#Requires -Version 7.0

# Pursuit stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'Pursuit' -Action {
    & $HarnessPowerShell -NoProfile -File $pursuitScript
    if ($LASTEXITCODE -ne 0) { throw "Agent pursuit test failed with exit code $LASTEXITCODE." }
}
