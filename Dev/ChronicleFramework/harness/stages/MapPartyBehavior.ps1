#Requires -Version 7.0

# MapPartyBehavior stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'MapPartyBehavior' -Action {
    & $HarnessPowerShell -NoProfile -File $mapPartyBehaviorScript -ValidateArmyTooltip
    if ($LASTEXITCODE -ne 0) { throw "Native Map party behavior summary comparison failed with exit code $LASTEXITCODE." }
}
