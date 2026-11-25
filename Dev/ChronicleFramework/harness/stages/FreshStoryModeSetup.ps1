#Requires -Version 7.0

# FreshStoryModeSetup stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'FreshStoryModeSetup' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $freshCampaignScript -StoryModeEycSetup -TimeoutSeconds 360 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Fresh StoryMode/tutorial-skip setup probe failed with exit code $LASTEXITCODE. Output: $testOutput" }
    $testOutput
}
