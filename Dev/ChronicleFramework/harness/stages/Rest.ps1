#Requires -Version 7.0

# Rest stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'Rest' -Action {
    & $HarnessPowerShell -NoProfile -File $restScript
    if ($LASTEXITCODE -ne 0) { throw "Agent rest test failed with exit code $LASTEXITCODE." }
}
