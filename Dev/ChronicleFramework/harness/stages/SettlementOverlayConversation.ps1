#Requires -Version 7.0

# SettlementOverlayConversation stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'SettlementOverlayConversation' -Action {
    & $HarnessPowerShell -NoProfile -File $settlementOverlayConversationScript -TargetSettlementId $TargetSettlementId -ApproachSettlementId $ApproachSettlementId
    if ($LASTEXITCODE -ne 0) { throw "Native Settlement overlay Conversation test failed with exit code $LASTEXITCODE." }
}
