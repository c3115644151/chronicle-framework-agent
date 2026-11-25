#Requires -Version 7.0

# InventoryNavigation stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'InventoryNavigation' -Action {
    & $HarnessPowerShell -NoProfile -File $inventoryNavigationScript
    if ($LASTEXITCODE -ne 0) { throw "Native Inventory navigation/clock boundary test failed with exit code $LASTEXITCODE." }
}
