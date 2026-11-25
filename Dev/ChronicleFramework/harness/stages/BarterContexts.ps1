#Requires -Version 7.0

# BarterContexts stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'BarterContexts' -Action {
    & $HarnessPowerShell -NoProfile -File $barterContextsScript
    if ($LASTEXITCODE -ne 0) { throw "Native Safe Passage Barter context test failed with exit code $LASTEXITCODE." }
    & $HarnessPowerShell -NoProfile -File $barterContextsScript -CancelOnly
    if ($LASTEXITCODE -ne 0) { throw "Native Safe Passage Cancel/encounter-menu test failed with exit code $LASTEXITCODE." }
    & $HarnessPowerShell -NoProfile -File $barterContextsScript -FightOnly
    if ($LASTEXITCODE -ne 0) { throw "Native Safe Passage Fight/encounter-menu test failed with exit code $LASTEXITCODE." }
}
