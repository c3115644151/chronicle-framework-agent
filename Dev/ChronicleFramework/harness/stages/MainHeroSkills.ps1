#Requires -Version 7.0

# MainHeroSkills stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'MainHeroSkills' -Action {
    & $HarnessPowerShell -NoProfile -File $mainHeroSkillsScript
    if ($LASTEXITCODE -ne 0) { throw "Native MainHero skills observation test failed with exit code $LASTEXITCODE." }
}
