#Requires -Version 7.0

# FreshCampaignRecruitmentFallback stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'FreshCampaignRecruitmentFallback' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $freshCampaignRecruitmentFallbackScript -MaxAttempts $RecruitmentFallbackMaxAttempts 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Fresh-Campaign Native recruitment fallback evaluation failed with exit code $LASTEXITCODE.`n$testOutput" }
    $testOutput
}
