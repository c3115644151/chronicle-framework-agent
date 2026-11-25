#Requires -Version 7.0

# SettlementOverlayQuickTalkIssueGateProbe stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'SettlementOverlayQuickTalkIssueGateProbe' -Action {
    & $HarnessPowerShell -NoProfile -File $settlementOverlayConversationScript -TargetSettlementId $QuickTalkTargetSettlementId -ApproachSettlementId $QuickTalkTargetSettlementId -InteractionMode QuickTalk -ExpectedOutcome IssueGateProbe
    if ($LASTEXITCODE -ne 0) { throw "Native Settlement QuickTalk Issue gate diagnostic failed with exit code $LASTEXITCODE." }
}
