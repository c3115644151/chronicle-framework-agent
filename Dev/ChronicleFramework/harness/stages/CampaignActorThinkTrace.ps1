#Requires -Version 7.0

# CampaignActorThinkTrace stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'CampaignActorThinkTrace' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $campaignActorThinkTraceScript 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Read-only Native Campaign Actor Think trace failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
