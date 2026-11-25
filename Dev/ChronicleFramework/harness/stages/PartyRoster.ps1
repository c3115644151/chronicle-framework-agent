#Requires -Version 7.0

# PartyRoster stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'PartyRoster' -Action {
    & $HarnessPowerShell -NoProfile -File $partyRosterScript
    if ($LASTEXITCODE -ne 0) { throw "Native MainParty roster observation test failed with exit code $LASTEXITCODE." }
}
