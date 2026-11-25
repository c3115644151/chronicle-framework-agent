#Requires -Version 7.0

# PartyPrisonerRecruitment stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'PartyPrisonerRecruitment' -Action {
    & $HarnessPowerShell -NoProfile -File $partyPrisonerRecruitmentScript
    if ($LASTEXITCODE -ne 0) { throw "Native MainParty PartyScreen prisoner recruitment transaction failed with exit code $LASTEXITCODE." }
}
