#Requires -Version 7.0

# AgentHostCampaignLoopEvaluation stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'AgentHostCampaignLoopEvaluation' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $agentHostCampaignLoopEvaluationScript 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "FreeLLMAPI-routed real-model Agent Host Campaign loop evaluation failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
