#Requires -Version 7.0

# FreshStoryModeNativeMenuLeaveEvaluation stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'FreshStoryModeNativeMenuLeaveEvaluation' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $freshCampaignScript -StoryModeEycSetup -StoryModeNativeMenuLeaveEvaluation -TimeoutSeconds 360 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Fresh StoryMode Native training-field Leave handler evaluation failed with exit code $LASTEXITCODE. Output: $testOutput" }
    $testOutput
}
