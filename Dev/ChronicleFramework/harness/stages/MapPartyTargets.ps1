#Requires -Version 7.0

# MapPartyTargets stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'MapPartyTargets' -Action {
    & $HarnessPowerShell -NoProfile -File $mapPartyTargetsScript
    if ($LASTEXITCODE -ne 0) { throw "Native Map party target observation test failed with exit code $LASTEXITCODE." }
}
