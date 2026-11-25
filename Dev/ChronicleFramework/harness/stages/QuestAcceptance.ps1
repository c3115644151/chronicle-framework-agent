#Requires -Version 7.0

# QuestAcceptance stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'QuestAcceptance' -Action {
    & $HarnessPowerShell -NoProfile -File $pursuitScript -ProbeQuestAcceptance
    if ($LASTEXITCODE -ne 0) { throw "Agent Quest acceptance test failed with exit code $LASTEXITCODE." }
}
