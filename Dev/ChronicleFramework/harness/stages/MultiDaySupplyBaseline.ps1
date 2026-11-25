#Requires -Version 7.0

# MultiDaySupplyBaseline stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'MultiDaySupplyBaseline' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $multiDaySupplyBaselineScript -Repetitions $SupplyBaselineRepetitions -ProvisionAmount $SupplyBaselineProvisionAmount 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Multi-day Native supply baseline failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
