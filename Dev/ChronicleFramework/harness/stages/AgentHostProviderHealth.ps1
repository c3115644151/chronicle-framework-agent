#Requires -Version 7.0

# AgentHostProviderHealth stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'AgentHostProviderHealth' -Action {
    $providerHealthEvidencePath = Join-Path $harnessTempDirectory 'AgentHostProviderHealth'
    $providerHealthArguments = @('-NoProfile', '-File', (Join-Path $stageRoot 'Test-AgentHostProvider.ps1'),
        '-HostDllPath', $agentHostDllPath, '-EvidencePath', $providerHealthEvidencePath, '-HealthOnly')
    if ($AllowDshXdPoolFreeRoute) { $providerHealthArguments += '-AllowDshXdPoolFreeRoute' }
    if ($AllowDshWorkBuddyGateway) { $providerHealthArguments += '-AllowDshWorkBuddyGateway' }
    $providerHealthOutput = & $HarnessPowerShell @providerHealthArguments 2>&1 | Out-String
    $providerHealthExitCode = $LASTEXITCODE
    if ($providerHealthExitCode -ne 0) { throw "Read-only Agent Host provider health check failed with exit code $providerHealthExitCode.`n$providerHealthOutput" }
    $providerHealthOutput
}
