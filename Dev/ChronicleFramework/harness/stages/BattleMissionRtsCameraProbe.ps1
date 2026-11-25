#Requires -Version 7.0

# BattleMissionRtsCameraProbe stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'BattleMissionRtsCameraProbe' -Action {
    $childOutputPath = Join-Path $harnessTempDirectory 'BattleMissionRtsCameraProbeChild.log'
    $childOutput = & $HarnessPowerShell -NoProfile -File $battleMissionFormationProbeScript -SourceSaveName $BattleSimulationSourceSaveName -TimeoutSeconds 300 -ProbeMainAgentAiController -ProbeMainAgentRtsCameraBehavior 2>&1 | Out-String
    $childOutput | Set-Content -LiteralPath $childOutputPath -Encoding UTF8
    if ($LASTEXITCODE -ne 0) { throw "Native RTSCamera-pattern MainAgent AI probe failed with exit code $LASTEXITCODE.`nChild output: $childOutput" }
    $childOutput
}
