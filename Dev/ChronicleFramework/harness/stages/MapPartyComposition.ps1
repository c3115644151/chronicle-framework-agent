#Requires -Version 7.0

# MapPartyComposition stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'MapPartyComposition' -Action {
    & $HarnessPowerShell -NoProfile -File $mapPartyCompositionScript
    if ($LASTEXITCODE -ne 0) { throw "Native Map party composition/expanded tooltip comparison failed with exit code $LASTEXITCODE." }
}
