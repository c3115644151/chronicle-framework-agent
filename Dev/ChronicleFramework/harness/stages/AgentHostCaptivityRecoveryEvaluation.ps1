#Requires -Version 7.0

# AgentHostCaptivityRecoveryEvaluation stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'AgentHostCaptivityRecoveryEvaluation' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $agentHostCampaignLoopEvaluationScript -CaptivityRecoveryFromExisting -PlannerSourceSaveName $StoryModePlannerSourceSaveName -FrameRate 5 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "FreeLLMAPI-routed real-model recovery from existing StoryMode Captivity failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
