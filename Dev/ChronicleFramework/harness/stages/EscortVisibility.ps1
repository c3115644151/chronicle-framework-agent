#Requires -Version 7.0

# EscortVisibility stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'EscortVisibility' -Action {
    & $HarnessPowerShell -NoProfile -File $pursuitScript -ProbeEscortVisibilityLoss -VisibilityProbeSeconds 45
    if ($LASTEXITCODE -ne 0) { throw "Escort visibility probe failed with exit code $LASTEXITCODE." }
}
