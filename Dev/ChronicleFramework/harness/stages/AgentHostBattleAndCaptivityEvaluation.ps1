#Requires -Version 7.0

# AgentHostBattleAndCaptivityEvaluation stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'AgentHostBattleAndCaptivityEvaluation' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $agentHostCampaignLoopEvaluationScript -BattleAndCaptivityLoop -BattleSourceSaveName $BattleSimulationSourceSaveName -FrameRate 5 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "FreeLLMAPI-routed real-model Native BattleSimulation/captivity recovery evaluation failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
