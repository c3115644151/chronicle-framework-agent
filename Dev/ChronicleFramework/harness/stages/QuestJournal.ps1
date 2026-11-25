#Requires -Version 7.0

# QuestJournal stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'QuestJournal' -Action {
    & $HarnessPowerShell -NoProfile -File $settlementOverlayConversationScript -TargetSettlementId village_V1_1 -ApproachSettlementId town_V1 -ExpectedOutcome QuestAccepted -ValidateQuestDetails
    if ($LASTEXITCODE -ne 0) { throw "Native Quest Journal details comparison failed with exit code $LASTEXITCODE." }
}
