#Requires -Version 7.0

# ArenaMasterInteraction stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'ArenaMasterInteraction' -Action {
    & $HarnessPowerShell -NoProfile -File $arenaMasterInteractionScript
    if ($LASTEXITCODE -ne 0) { throw "Native cross-culture ArenaMaster interaction regression failed with exit code $LASTEXITCODE." }
}
