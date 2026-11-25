#Requires -Version 7.0

# AgentHostLifecycleEvaluation stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'AgentHostLifecycleEvaluation' -Action {
    try {
        $testOutput = & $HarnessPowerShell -NoProfile -File $agentHostLifecycleEvaluationScript -Scenario $LifecycleScenario 2>&1 | Out-String
        $testExitCode = $LASTEXITCODE
        if ($testExitCode -ne 0) { throw "Game-owned Agent Host lifecycle test failed with exit code $testExitCode.`n$testOutput" }
        $testOutput
    }
    finally {
        if ($script:retainedAgentHostPackageRoot) { Remove-RetainedAgentHostPackage $script:retainedAgentHostPackageRoot }
        $script:retainedAgentHostPackageRoot = $null
        $script:retainedAgentHostExecutablePath = $null
        [Environment]::SetEnvironmentVariable('CHRONICLE_AGENT_HOST_TEST_PATH', $previousAgentHostTestPath, 'Process')
    }
}
