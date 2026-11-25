#Requires -Version 7.0

# PrisonerRansomSale stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'PrisonerRansomSale' -Action {
    & $HarnessPowerShell -NoProfile -File $prisonerRansomSaleScript
    if ($LASTEXITCODE -ne 0) { throw "Native ransom prisoner sale transaction failed with exit code $LASTEXITCODE." }
}
