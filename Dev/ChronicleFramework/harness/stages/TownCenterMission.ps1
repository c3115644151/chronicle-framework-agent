#Requires -Version 7.0

# TownCenterMission stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'TownCenterMission' -Action {
    & $HarnessPowerShell -NoProfile -File $townCenterMissionScript
    if ($LASTEXITCODE -ne 0) { throw "Native Town Center Mission test failed with exit code $LASTEXITCODE." }
}
