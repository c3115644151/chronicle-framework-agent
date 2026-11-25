#Requires -Version 7.0

# IdlePressure stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'IdlePressure' -Action {
    & $HarnessPowerShell -NoProfile -File $idlePressureScript
    if ($LASTEXITCODE -ne 0) { throw "Native idle pressure window failed with exit code $LASTEXITCODE." }
}
