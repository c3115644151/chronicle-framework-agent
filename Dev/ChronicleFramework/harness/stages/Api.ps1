#Requires -Version 7.0

# Api stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'Api' -Action {
    & $HarnessPowerShell -NoProfile -File $apiScript -Scope Lifecycle
    if ($LASTEXITCODE -ne 0) { throw "API lifecycle stage failed with exit code $LASTEXITCODE." }
    & $HarnessPowerShell -NoProfile -File $apiScript -Scope Events
    if ($LASTEXITCODE -ne 0) { throw "API events stage failed with exit code $LASTEXITCODE." }
}
