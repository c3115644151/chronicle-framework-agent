#Requires -Version 7.0

# Movement stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'Movement' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $movementScript 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Agent movement test failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
