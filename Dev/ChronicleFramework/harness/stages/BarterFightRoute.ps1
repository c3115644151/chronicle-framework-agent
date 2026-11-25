#Requires -Version 7.0

# BarterFightRoute stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'BarterFightRoute' -Action {
    & $HarnessPowerShell -NoProfile -File $barterContextsScript -FightOnly
    if ($LASTEXITCODE -ne 0) { throw "Native Safe Passage Fight-route test failed with exit code $LASTEXITCODE." }
}
