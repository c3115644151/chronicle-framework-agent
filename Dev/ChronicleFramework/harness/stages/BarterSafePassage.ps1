#Requires -Version 7.0

# BarterSafePassage stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'BarterSafePassage' -Action {
    & $HarnessPowerShell -NoProfile -File $barterContextsScript -ObserveExpiry
    if ($LASTEXITCODE -ne 0) { throw "Native Safe Passage offer/cooldown test failed with exit code $LASTEXITCODE." }
}
