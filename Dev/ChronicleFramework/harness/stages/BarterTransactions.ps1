#Requires -Version 7.0

# BarterTransactions stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'BarterTransactions' -Action {
    & $HarnessPowerShell -NoProfile -File $barterTransactionsScript
    if ($LASTEXITCODE -ne 0) { throw "Native ordinary Lord Barter transaction test failed with exit code $LASTEXITCODE." }
}
