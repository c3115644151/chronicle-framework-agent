#Requires -Version 7.0

# FreshCampaignLiveModelEvaluation stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'FreshCampaignLiveModelEvaluation' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $freshCampaignLiveModelEvaluationScript 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Five-instance fresh-campaign real-model evaluation failed with exit code $LASTEXITCODE.`n$testOutput" }
    $testOutput
}
