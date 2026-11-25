#Requires -Version 7.0

# MapSettlementTargets stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'MapSettlementTargets' -Action {
    & $HarnessPowerShell -NoProfile -File $mapSettlementTargetsScript
    if ($LASTEXITCODE -ne 0) { throw "Native map settlement visibility and movement guard test failed with exit code $LASTEXITCODE." }
}
