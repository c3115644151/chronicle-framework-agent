#Requires -Version 7.0

# JoinSiegeEvent stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'JoinSiegeEvent' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $joinSiegeEventScript 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Native Join Siege Event test failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
