#Requires -Version 7.0

# AlleyLeaderInquiry stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'AlleyLeaderInquiry' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $alleyLeaderInquiryScript 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Native Alley leader MultiSelection Inquiry test failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
