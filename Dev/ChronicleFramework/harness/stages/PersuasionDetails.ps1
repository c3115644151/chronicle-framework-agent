#Requires -Version 7.0

# PersuasionDetails stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'PersuasionDetails' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $persuasionDetailsScript 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Native Persuasion observation/option loop failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
