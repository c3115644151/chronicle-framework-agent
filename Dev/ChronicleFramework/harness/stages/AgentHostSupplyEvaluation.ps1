#Requires -Version 7.0

# AgentHostSupplyEvaluation stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'AgentHostSupplyEvaluation' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File (Join-Path $stageRoot 'Test-AgentHostSupplyEvaluation.ps1') -Runs $AgentHostSupplyRuns 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "FreeLLMAPI-routed real-model Agent Host supply evaluation failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
