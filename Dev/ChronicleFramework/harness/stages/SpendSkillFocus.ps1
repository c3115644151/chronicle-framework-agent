#Requires -Version 7.0

# SpendSkillFocus stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'SpendSkillFocus' -Action {
    & $HarnessPowerShell -NoProfile -File $spendSkillFocusScript
    if ($LASTEXITCODE -ne 0) { throw "Native Character Developer Skill Focus transaction test failed with exit code $LASTEXITCODE." }
}
