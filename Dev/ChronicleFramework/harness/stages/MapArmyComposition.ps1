#Requires -Version 7.0

# MapArmyComposition stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'MapArmyComposition' -Action {
    & $HarnessPowerShell -NoProfile -File $mapPartyCompositionScript -ValidateArmyTooltip
    if ($LASTEXITCODE -ne 0) { throw "Native Army tooltip composition comparison failed with exit code $LASTEXITCODE." }
}
