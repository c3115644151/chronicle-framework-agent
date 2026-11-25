#Requires -Version 7.0

# Conversation stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'Conversation' -Action {
    & $HarnessPowerShell -NoProfile -File $pursuitScript -ProbeConversation
    if ($LASTEXITCODE -ne 0) { throw "Agent conversation lifecycle test failed with exit code $LASTEXITCODE." }
}
