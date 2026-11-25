#Requires -Version 7.0

# AgentHostVillageToolsQuestEvaluation stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'AgentHostVillageToolsQuestEvaluation' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $agentHostCampaignLoopEvaluationScript -VillageToolsQuest -FrameRate 5 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "FreeLLMAPI-routed real-model Agent Host VillageNeedsTools Quest evaluation failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
