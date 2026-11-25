#Requires -Version 7.0

# AgentHostEstablishClanAutonomyEvaluation stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'AgentHostEstablishClanAutonomyEvaluation' -Action {
    $originalProviderTimeout = [Environment]::GetEnvironmentVariable('CHRONICLE_LLM_TIMEOUT_SECONDS', 'Process')
    $useBoundedAutonomyRuntime = [string]::IsNullOrWhiteSpace($originalProviderTimeout)
    if ($useBoundedAutonomyRuntime) { [Environment]::SetEnvironmentVariable('CHRONICLE_LLM_TIMEOUT_SECONDS', '90', 'Process') }
    try {
    $testOutput = & $HarnessPowerShell -NoProfile -File $agentHostCampaignLoopEvaluationScript -EstablishYourClanAutonomyLoop -PlannerSourceSaveName $StoryModePlannerSourceSaveName -FrameRate 5 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "FreeLLMAPI-routed real-model StoryMode autonomy evaluation on a disposable existing-quest clone failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
    }
    finally {
        if ($useBoundedAutonomyRuntime) { [Environment]::SetEnvironmentVariable('CHRONICLE_LLM_TIMEOUT_SECONDS', $originalProviderTimeout, 'Process') }
    }
}
