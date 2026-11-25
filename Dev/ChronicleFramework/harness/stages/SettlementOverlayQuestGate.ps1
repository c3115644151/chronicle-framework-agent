#Requires -Version 7.0

# SettlementOverlayQuestGate stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'SettlementOverlayQuestGate' -Action {
    & $HarnessPowerShell -NoProfile -File $settlementOverlayConversationScript -ExpectedOutcome NativePreconditionBlocked
    if ($LASTEXITCODE -ne 0) { throw "Native Settlement overlay Issue Quest precondition gate test failed with exit code $LASTEXITCODE." }
}
