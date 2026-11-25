#Requires -Version 7.0

# SettlementOverlayQuestAcceptance stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'SettlementOverlayQuestAcceptance' -Action {
    & $HarnessPowerShell -NoProfile -File $settlementOverlayConversationScript -TargetSettlementId $TargetSettlementId -ApproachSettlementId $ApproachSettlementId -ExpectedOutcome QuestAccepted
    if ($LASTEXITCODE -ne 0) { throw "Native Settlement overlay Issue Quest acceptance test failed with exit code $LASTEXITCODE." }
}
