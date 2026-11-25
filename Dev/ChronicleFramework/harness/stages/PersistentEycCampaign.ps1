#Requires -Version 7.0

# PersistentEycCampaign stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'PersistentEycCampaign' -Action {
    $savedLlmModel = [Environment]::GetEnvironmentVariable('CHRONICLE_LLM_MODEL', 'Process')
    $savedHarnessModel = [Environment]::GetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_MODEL', 'Process')
    $providerKeyVariable = 'CHRONICLE_LLM_API_KEY'
    $savedProviderKey = [Environment]::GetEnvironmentVariable($providerKeyVariable, 'Process')
    try {
        $providerCredential = Get-HarnessConfiguredProviderCredential
        $providerKeyVariable = [string]$providerCredential.EnvironmentVariableName
        $savedProviderKey = [Environment]::GetEnvironmentVariable($providerKeyVariable, 'Process')
        [Environment]::SetEnvironmentVariable($providerKeyVariable, [string]$providerCredential.Value, 'Process')
        [Environment]::SetEnvironmentVariable('CHRONICLE_LLM_MODEL', $FreshStoryModeModel, 'Process')
        [Environment]::SetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_MODEL', $FreshStoryModeModel, 'Process')
        $testOutput = & $HarnessPowerShell -NoProfile -File $persistentEycCampaignScript `
            -HostMaxElapsedSeconds $PersistentEycHostMaxElapsedSeconds `
            -MaxProviderDecisionsPerContinuation $PersistentEycMaxProviderDecisionsPerContinuation `
            -MaxHttpRequestsPerDecision $PersistentEycMaxHttpRequestsPerDecision `
            -CampaignKey $PersistentEycCampaignKey `
            -StartupTimeoutSeconds 240 -FrameRate 5 2>&1 | Out-String
        $testExitCode = $LASTEXITCODE
        if ($testExitCode -ne 0) {
            throw "Persistent natural StoryMode campaign has not verified original EYC completion (exit=$testExitCode). A Native checkpoint, if verified, remains selected for the next continuation."
        }
        $testOutput
    }
    finally {
        [Environment]::SetEnvironmentVariable('CHRONICLE_LLM_MODEL', $savedLlmModel, 'Process')
        [Environment]::SetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_MODEL', $savedHarnessModel, 'Process')
        [Environment]::SetEnvironmentVariable($providerKeyVariable, $savedProviderKey, 'Process')
    }
}
