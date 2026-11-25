#Requires -Version 7.0

# FreshCampaign stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'FreshCampaign' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $freshCampaignScript 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Fresh campaign character-creation test failed with exit code $LASTEXITCODE. Output: $testOutput" }
    $testOutput
}
