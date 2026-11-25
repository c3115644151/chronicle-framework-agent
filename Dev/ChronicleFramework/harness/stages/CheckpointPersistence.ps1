#Requires -Version 7.0

# CheckpointPersistence stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'CheckpointPersistence' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $agentCheckpointPersistenceScript 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Native Campaign checkpoint persistence test failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
