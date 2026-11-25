#Requires -Version 7.0

# MapInquiry stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'MapInquiry' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $mapInquiryScript 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Native Map Inquiry observe/respond test failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
