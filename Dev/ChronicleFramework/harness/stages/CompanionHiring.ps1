#Requires -Version 7.0

# CompanionHiring stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'CompanionHiring' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $companionHiringScript 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Native Wanderer companion-hiring flow failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
