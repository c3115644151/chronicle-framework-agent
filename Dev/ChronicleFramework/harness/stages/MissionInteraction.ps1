#Requires -Version 7.0

# MissionInteraction stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'MissionInteraction' -Action {
    & $HarnessPowerShell -NoProfile -File $missionInteractionScript
    if ($LASTEXITCODE -ne 0) { throw "Native Mission Agent interaction regression failed with exit code $LASTEXITCODE." }
}
