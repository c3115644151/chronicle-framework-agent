#Requires -Version 7.0

# AgentHostEstablishClanGoalPlannerEvaluation stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'AgentHostEstablishClanGoalPlannerEvaluation' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $agentHostCampaignLoopEvaluationScript -EstablishYourClanGoalPlanner -PlannerSourceSaveName $StoryModePlannerSourceSaveName -FrameRate 5 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "FreeLLMAPI-routed read-only StoryMode Establish Your Clan objective planner evaluation failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
