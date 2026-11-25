#Requires -Version 7.0

# MapIncidentInputGuard stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'MapIncidentInputGuard' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $mapIncidentInputGuardScript 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Native MapIncident movement guard test failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
