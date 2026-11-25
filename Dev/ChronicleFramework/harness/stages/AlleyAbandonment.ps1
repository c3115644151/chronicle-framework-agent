#Requires -Version 7.0

# AlleyAbandonment stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'AlleyAbandonment' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $alleyAbandonmentScript 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Native Alley abandonment menu test failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
