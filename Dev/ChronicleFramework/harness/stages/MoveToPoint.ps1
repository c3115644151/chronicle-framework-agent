#Requires -Version 7.0

# MoveToPoint stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'MoveToPoint' -Action {
    & $HarnessPowerShell -NoProfile -File $moveToPointScript
    if ($LASTEXITCODE -ne 0) { throw "Agent point movement test failed with exit code $LASTEXITCODE." }
}
