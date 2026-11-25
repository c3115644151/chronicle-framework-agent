#Requires -Version 7.0

# EycObjectiveCheckpointReadback stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'EycObjectiveCheckpointReadback' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $eycObjectiveCheckpointReadbackScript `
        -CampaignKey $PersistentEycCampaignKey -TimeoutSeconds 240 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Native EYC objective checkpoint readback failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
