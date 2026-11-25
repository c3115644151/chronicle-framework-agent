#Requires -Version 7.0

# SettlementOverlayQuickTalk stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'SettlementOverlayQuickTalk' -Action {
    & $HarnessPowerShell -NoProfile -File $settlementOverlayConversationScript -TargetSettlementId $QuickTalkTargetSettlementId -ApproachSettlementId $QuickTalkTargetSettlementId -InteractionMode QuickTalk -ExpectedOutcome ConversationOnly
    if ($LASTEXITCODE -ne 0) { throw "Native Settlement overlay QuickConversation test failed with exit code $LASTEXITCODE." }
}
