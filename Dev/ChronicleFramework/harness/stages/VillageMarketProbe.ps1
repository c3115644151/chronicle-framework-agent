#Requires -Version 7.0

# VillageMarketProbe stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'VillageMarketProbe' -Action {
    & $HarnessPowerShell -NoProfile -File $villageMarketProbeScript
    if ($LASTEXITCODE -ne 0) { throw "A Native village market did not settle its quoted sale, with exit code $LASTEXITCODE." }
}
