#Requires -Version 7.0

# AgentHostProvider stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'AgentHostProvider' -Action {
    $originalProviderTimeout = [Environment]::GetEnvironmentVariable('CHRONICLE_LLM_TIMEOUT_SECONDS', 'Process')
    $useBoundedProviderSmoke = [string]::IsNullOrWhiteSpace($originalProviderTimeout)
    if ($useBoundedProviderSmoke) { [Environment]::SetEnvironmentVariable('CHRONICLE_LLM_TIMEOUT_SECONDS', '90', 'Process') }
    try {
    $mailboxEvidencePath = Join-Path $harnessTempDirectory 'AgentHostMailboxContract'
    $mailboxOutput = & $HarnessPowerShell -NoProfile -File (Join-Path $stageRoot 'Test-AgentHostProtocol.ps1') -HostDllPath $agentHostDllPath -EvidenceDirectory $mailboxEvidencePath 2>&1 | Out-String
    $mailboxExitCode = $LASTEXITCODE
    if ($mailboxExitCode -ne 0) { throw "Local Agent Host mailbox regression failed with exit code $mailboxExitCode.`n$mailboxOutput" }
    $providerEvidencePath = Join-Path $harnessTempDirectory 'AgentHostProvider'
    $providerArguments = @('-NoProfile', '-File', (Join-Path $stageRoot 'Test-AgentHostProvider.ps1'),
        '-HostDllPath', $agentHostDllPath, '-EvidencePath', $providerEvidencePath, '-MaxOutputTokens', [string]$ProviderSmokeMaxOutputTokens)
    if ($AllowDshXdPoolFreeRoute) { $providerArguments += '-AllowDshXdPoolFreeRoute' }
    if ($AllowDshWorkBuddyGateway) { $providerArguments += '-AllowDshWorkBuddyGateway' }
    if ($ProbeDshFreeRouteWithMinimalChat) { $providerArguments += '-ProbeDshFreeRouteWithMinimalChat' }
    $providerOutput = & $HarnessPowerShell @providerArguments 2>&1 | Out-String
    $providerExitCode = $LASTEXITCODE
    if ($providerExitCode -ne 0) { throw "Local Agent Host provider contract/smoke failed with exit code $providerExitCode.`n$providerOutput" }
    [ordered]@{ mailboxRegression = $mailboxOutput; providerContractAndSmoke = $providerOutput } | ConvertTo-Json -Depth 8
    }
    finally {
        if ($useBoundedProviderSmoke) { [Environment]::SetEnvironmentVariable('CHRONICLE_LLM_TIMEOUT_SECONDS', $originalProviderTimeout, 'Process') }
    }
}
