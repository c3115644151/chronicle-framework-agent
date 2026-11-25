#Requires -Version 7.0

# CharacterDevelopment stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'CharacterDevelopment' -Action {
    & $HarnessPowerShell -NoProfile -File $characterDevelopmentScript
    if ($LASTEXITCODE -ne 0) { throw "Native MainHero Character Developer observation test failed with exit code $LASTEXITCODE." }
}
