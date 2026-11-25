#Requires -Version 7.0

# QuickInformation stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'QuickInformation' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $quickInformationScript 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Native QuickInformation observation test failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
