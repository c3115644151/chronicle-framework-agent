#Requires -Version 7.0

# TradeTransactions stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'TradeTransactions' -Action {
    & $HarnessPowerShell -NoProfile -File $tradeTransactionsScript
    if ($LASTEXITCODE -ne 0) { throw "Native Town Trade transaction test failed with exit code $LASTEXITCODE." }
}
