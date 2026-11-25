#Requires -Version 7.0

# AlleyRosterManagement stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'AlleyRosterManagement' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $alleyRosterManagementScript 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Native Alley PartyScreen roster test failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
