#Requires -Version 7.0

# FreshStoryModeNativeInquiryResponseEvaluation stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'FreshStoryModeNativeInquiryResponseEvaluation' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $freshCampaignScript -StoryModeEycSetup -StoryModeNativeMenuLeaveEvaluation -StoryModeNativeInquiryResponseEvaluation -TimeoutSeconds 360 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Fresh StoryMode original one-button Native Inquiry response evaluation failed with exit code $LASTEXITCODE. Output: $testOutput" }
    $testOutput
}
