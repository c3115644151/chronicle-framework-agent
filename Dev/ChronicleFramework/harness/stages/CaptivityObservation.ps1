#Requires -Version 7.0

# CaptivityObservation stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'CaptivityObservation' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $captivityObservationScript 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Native MainHero captivity observation test failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
