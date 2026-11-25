#Requires -Version 7.0

# PrisonCaptivityOutcome stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'PrisonCaptivityOutcome' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $captivityOutcomeScript -CaptorContext Settlement 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Native MainHero prison captivity outcome test failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
