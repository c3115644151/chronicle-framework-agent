#Requires -Version 7.0

# EquipmentTransactions stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'EquipmentTransactions' -Action {
    & $HarnessPowerShell -NoProfile -File $equipmentTransactionsScript
    if ($LASTEXITCODE -ne 0) { throw "Native MainHero equip/unequip transaction test failed with exit code $LASTEXITCODE." }
}
