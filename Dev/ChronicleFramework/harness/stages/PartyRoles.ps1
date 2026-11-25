#Requires -Version 7.0

# PartyRoles stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'PartyRoles' -Action {
    & $HarnessPowerShell -NoProfile -File $partyRolesScript
    if ($LASTEXITCODE -ne 0) { throw "Native PartyRole assignment/removal flow failed with exit code $LASTEXITCODE." }
}
