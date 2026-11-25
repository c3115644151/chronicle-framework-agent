#Requires -Version 7.0

# FreshCampaignSupplyBaseline stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'FreshCampaignSupplyBaseline' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $freshCampaignSupplyBaselineScript -Runs $FreshCampaignSupplyRuns 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Fresh-Campaign paired Native supply baseline matrix failed with exit code $LASTEXITCODE.`n$testOutput" }
    $testOutput
}
