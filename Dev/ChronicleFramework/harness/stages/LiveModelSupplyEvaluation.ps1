#Requires -Version 7.0

# LiveModelSupplyEvaluation stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'LiveModelSupplyEvaluation' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $agentEvaluationLiveModelSupplyScript -Runs $SupplyModelRuns 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Repeated real-model multi-day supply evaluation failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
