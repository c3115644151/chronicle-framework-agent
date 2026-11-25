#Requires -Version 7.0

# CheckpointValidation stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'CheckpointValidation' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $agentCheckpointValidationScript 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Invalid Campaign checkpoint safety test failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
