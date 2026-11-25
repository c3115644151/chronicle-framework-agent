#Requires -Version 7.0

# TavernMission stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'TavernMission' -Action {
    & $HarnessPowerShell -NoProfile -File $tavernMissionScript
    if ($LASTEXITCODE -ne 0) { throw "Native Tavern Mission entry test failed with exit code $LASTEXITCODE." }
}
