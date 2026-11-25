#Requires -Version 7.0

# AgentHostLifecycleCompletionEvaluation stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'AgentHostLifecycleCompletionEvaluation' -Action {
    try {
        $testOutput = & $HarnessPowerShell -NoProfile -File $agentHostLifecycleEvaluationScript -Scenario Complete -TimeoutSeconds 300 2>&1 | Out-String
        $testExitCode = $LASTEXITCODE
        if ($testExitCode -ne 0) { throw "Game-owned real-model Host completion test failed with exit code $testExitCode.`n$testOutput" }
        $testOutput
    }
    finally {
        if ($script:retainedAgentHostPackageRoot) { Remove-RetainedAgentHostPackage $script:retainedAgentHostPackageRoot }
        $script:retainedAgentHostPackageRoot = $null
        $script:retainedAgentHostExecutablePath = $null
        [Environment]::SetEnvironmentVariable('CHRONICLE_AGENT_HOST_TEST_PATH', $previousAgentHostTestPath, 'Process')
    }
}
