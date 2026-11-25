#Requires -Version 7.0

# Campaign stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'Campaign' -Action {
    & $HarnessPowerShell -NoProfile -File $campaignScript
    if ($LASTEXITCODE -ne 0) { throw "Campaign test failed with exit code $LASTEXITCODE." }
}
