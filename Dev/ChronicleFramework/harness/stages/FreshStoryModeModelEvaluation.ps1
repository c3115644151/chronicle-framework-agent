#Requires -Version 7.0

# FreshStoryModeModelEvaluation stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'FreshStoryModeModelEvaluation' -Action {
    $savedHarnessAutoStart = [Environment]::GetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_AUTO_START', 'Process')
    $savedHarnessAutoStop = [Environment]::GetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_AUTO_STOP_AFTER_MS', 'Process')
    $savedHarnessGoal = [Environment]::GetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_GOAL', 'Process')
    $savedHarnessModel = [Environment]::GetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_MODEL', 'Process')
    $savedLlmModel = [Environment]::GetEnvironmentVariable('CHRONICLE_LLM_MODEL', 'Process')
    $providerKeyVariable = 'CHRONICLE_LLM_API_KEY'
    $savedProviderKey = [Environment]::GetEnvironmentVariable($providerKeyVariable, 'Process')
    $savedProviderTimeout = [Environment]::GetEnvironmentVariable('CHRONICLE_LLM_TIMEOUT_SECONDS', 'Process')
    try {
        $providerCredential = Get-HarnessConfiguredProviderCredential
        $providerKeyVariable = [string]$providerCredential.EnvironmentVariableName
        $savedProviderKey = [Environment]::GetEnvironmentVariable($providerKeyVariable, 'Process')
        [Environment]::SetEnvironmentVariable($providerKeyVariable, [string]$providerCredential.Value, 'Process')
        [Environment]::SetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_AUTO_START', '1', 'Process')
        [Environment]::SetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_AUTO_STOP_AFTER_MS', '86400000', 'Process')
        [Environment]::SetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_GOAL', '自主完成原版主线任务“建立你的家族”。', 'Process')
        # Pin one explicit provider model/route for reproducibility; catalog presence is not proof of a successful provider call. Never use a local custom route or unbounded auto chain.
        [Environment]::SetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_MODEL', $FreshStoryModeModel, 'Process')
        [Environment]::SetEnvironmentVariable('CHRONICLE_LLM_MODEL', $FreshStoryModeModel, 'Process')
        if ([string]::IsNullOrWhiteSpace($savedProviderTimeout)) { [Environment]::SetEnvironmentVariable('CHRONICLE_LLM_TIMEOUT_SECONDS', '300', 'Process') }
        $testOutput = & $HarnessPowerShell -NoProfile -File $freshCampaignScript -StoryModeEycSetup -StoryModeEycLiveModelEvaluation -TimeoutSeconds 87000 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "Fresh natural StoryMode bounded real-model evaluation failed with exit code $LASTEXITCODE. Output: $testOutput" }
        $testOutput
    }
    finally {
        [Environment]::SetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_AUTO_START', $savedHarnessAutoStart, 'Process')
        [Environment]::SetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_AUTO_STOP_AFTER_MS', $savedHarnessAutoStop, 'Process')
        [Environment]::SetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_GOAL', $savedHarnessGoal, 'Process')
        [Environment]::SetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_MODEL', $savedHarnessModel, 'Process')
        [Environment]::SetEnvironmentVariable('CHRONICLE_LLM_MODEL', $savedLlmModel, 'Process')
        [Environment]::SetEnvironmentVariable($providerKeyVariable, $savedProviderKey, 'Process')
        [Environment]::SetEnvironmentVariable('CHRONICLE_LLM_TIMEOUT_SECONDS', $savedProviderTimeout, 'Process')
        try {
            if ($script:retainedAgentHostPackageRoot) { Remove-RetainedAgentHostPackage $script:retainedAgentHostPackageRoot }
        }
        finally {
            $script:retainedAgentHostPackageRoot = $null
            $script:retainedAgentHostExecutablePath = $null
            [Environment]::SetEnvironmentVariable('CHRONICLE_AGENT_HOST_TEST_PATH', $previousAgentHostTestPath, 'Process')
        }
    }
}
