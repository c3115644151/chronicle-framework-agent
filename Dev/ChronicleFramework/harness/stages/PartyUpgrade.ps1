#Requires -Version 7.0

# PartyUpgrade stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'PartyUpgrade' -Action {
    & $HarnessPowerShell -NoProfile -File $partyUpgradeScript
    if ($LASTEXITCODE -ne 0) { throw "Native MainParty PartyScreen upgrade transaction failed with exit code $LASTEXITCODE." }
}
