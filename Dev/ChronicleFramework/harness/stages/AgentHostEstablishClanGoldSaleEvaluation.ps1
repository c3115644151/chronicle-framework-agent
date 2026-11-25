#Requires -Version 7.0

# AgentHostEstablishClanGoldSaleEvaluation stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'AgentHostEstablishClanGoldSaleEvaluation' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $agentHostCampaignLoopEvaluationScript -EstablishClanGoldSaleFromStoryMode -PlannerSourceSaveName $StoryModePlannerSourceSaveName -FrameRate 5 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "FreeLLMAPI-routed real-model StoryMode Gold objective sale evaluation failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
