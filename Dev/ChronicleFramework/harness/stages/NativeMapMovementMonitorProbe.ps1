#Requires -Version 7.0

# NativeMapMovementMonitorProbe stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'NativeMapMovementMonitorProbe' -Action {
    $probeOutput = & $HarnessPowerShell -NoProfile -File $agentHostMovementProbeScript -WaitSeconds $NativeMapMovementProbeWaitSeconds 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Live Native map-movement monitor probe failed with exit code $LASTEXITCODE.`n$probeOutput" }
    $probeOutput
}
