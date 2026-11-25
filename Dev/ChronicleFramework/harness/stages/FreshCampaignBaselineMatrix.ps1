#Requires -Version 7.0

# FreshCampaignBaselineMatrix stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'FreshCampaignBaselineMatrix' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $freshCampaignBaselineMatrixScript 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Five-instance fresh-campaign baseline matrix failed with exit code $LASTEXITCODE.`n$testOutput" }
    $testOutput
}
