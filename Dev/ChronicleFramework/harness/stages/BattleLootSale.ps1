#Requires -Version 7.0

# BattleLootSale stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'BattleLootSale' -Action {
    & $HarnessPowerShell -NoProfile -File $battleLootSaleScript
    if ($LASTEXITCODE -ne 0) { throw "A Native battle's loot did not settle into Gold at a town market, with exit code $LASTEXITCODE." }
}
