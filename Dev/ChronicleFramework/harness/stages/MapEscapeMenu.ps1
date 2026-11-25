#Requires -Version 7.0

# MapEscapeMenu stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'MapEscapeMenu' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $mapEscapeMenuScript 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Native Map Escape-menu observe/close test failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
