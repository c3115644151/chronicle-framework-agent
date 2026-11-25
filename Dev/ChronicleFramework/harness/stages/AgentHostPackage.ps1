#Requires -Version 7.0

# AgentHostPackage stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'AgentHostPackage' -Action {
    $packageEvidencePath = Join-Path $harnessTempDirectory 'AgentHostPackage'
    $retainPackageForSameSessionRuntime = $Phase -in @('FreshStoryModeModelEvaluation', 'PersistentEycCampaign', 'AgentHostLifecycleEvaluation', 'AgentHostLifecycleCompletionEvaluation', 'BattleMissionHostNativeAiAutopilotProbe')
    $packageArguments = @('-ProjectPath', $agentHostProjectPath, '-EvidencePath', $packageEvidencePath)
    if ($retainPackageForSameSessionRuntime) { $packageArguments += '-RetainRuntimePackage' }
    try {
        $packageOutput = & $HarnessPowerShell -NoProfile -File $agentHostPackageScript @packageArguments 2>&1 | Out-String
        $packageExitCode = $LASTEXITCODE
        $runtimeReceiptPath = Join-Path $packageEvidencePath 'AgentHostRuntimePackage.json'
        if ($retainPackageForSameSessionRuntime -and (Test-Path -LiteralPath $runtimeReceiptPath -PathType Leaf)) {
            $runtimeReceipt = Get-Content -LiteralPath $runtimeReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $script:retainedAgentHostPackageRoot = [IO.Path]::GetFullPath([string]$runtimeReceipt.PackageRoot)
            $script:retainedAgentHostExecutablePath = [IO.Path]::GetFullPath([string]$runtimeReceipt.RuntimeExecutablePath)
            if (-not (Test-Path -LiteralPath $script:retainedAgentHostExecutablePath -PathType Leaf)) { throw 'Retained Agent Host runtime executable is missing after package verification.' }
            [Environment]::SetEnvironmentVariable('CHRONICLE_AGENT_HOST_TEST_PATH', $script:retainedAgentHostExecutablePath, 'Process')
        }
        if ($packageExitCode -ne 0) { throw "Self-contained Agent Host package validation failed. Evidence: $packageOutput" }
        if ($retainPackageForSameSessionRuntime -and [string]::IsNullOrWhiteSpace($script:retainedAgentHostExecutablePath)) { throw 'Fresh StoryMode runtime requires the self-contained package receipt and executable path.' }
        $packageOutput
    }
    catch {
        if ($script:retainedAgentHostPackageRoot) { Remove-RetainedAgentHostPackage $script:retainedAgentHostPackageRoot; $script:retainedAgentHostPackageRoot = $null; $script:retainedAgentHostExecutablePath = $null }
        [Environment]::SetEnvironmentVariable('CHRONICLE_AGENT_HOST_TEST_PATH', $previousAgentHostTestPath, 'Process')
        throw
    }
}
