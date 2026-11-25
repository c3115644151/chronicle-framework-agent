#Requires -Version 7.0

# AgentHostBattleSimulationEvaluation stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'AgentHostBattleSimulationEvaluation' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $agentHostCampaignLoopEvaluationScript -BattleSimulationLoop -BattleSourceSaveName $BattleSimulationSourceSaveName -FrameRate 5 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "FreeLLMAPI-routed real-model Agent Host BattleSimulation evaluation failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
