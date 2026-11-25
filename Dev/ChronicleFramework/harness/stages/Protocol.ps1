#Requires -Version 7.0

# Protocol stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'Protocol' -Action {
    $fakeBridgeEvidence = Join-Path $harnessTempDirectory 'AgentHostProtocolContract'
    $fakeBridgeOutput = & $HarnessPowerShell -NoProfile -File (Join-Path $stageRoot 'Test-AgentHostProtocol.ps1') -HostDllPath $agentHostDllPath -EvidenceDirectory $fakeBridgeEvidence 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent Host mailbox contract test failed with exit code $LASTEXITCODE.`n$fakeBridgeOutput" }
    $nativeProtocolOutput = & $HarnessPowerShell -NoProfile -File $protocolScript 2>&1 | Out-String
    $nativeProtocolExitCode = $LASTEXITCODE
    if ($nativeProtocolExitCode -ne 0) { throw "Agent protocol test failed with exit code $nativeProtocolExitCode.`n$nativeProtocolOutput" }
    [ordered]@{ hostMailboxContract = $fakeBridgeOutput; nativeProtocol = $nativeProtocolOutput; nativeHostHandshakes = '3 read-only state requests; checked same Native PID, MainHero, Clan, MainParty, time mode and unchanged Campaign fingerprint.' } | ConvertTo-Json -Depth 8
}
