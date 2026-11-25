#Requires -Version 7.0

# MarketProbe stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'MarketProbe' -Action {
    & $HarnessPowerShell -NoProfile -File $marketProbeScript
    if ($LASTEXITCODE -ne 0) { throw "Native market probe observed a buy-and-carry price that did not settle as quoted, with exit code $LASTEXITCODE." }
}
