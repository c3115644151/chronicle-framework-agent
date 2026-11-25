#Requires -Version 7.0

# BattleMissionFormationProbe stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'BattleMissionFormationProbe' -Action {
    $childOutputPath = Join-Path $harnessTempDirectory 'BattleMissionFormationProbeChild.log'
    $childOutput = & $HarnessPowerShell -NoProfile -File $battleMissionFormationProbeScript -SourceSaveName $BattleSimulationSourceSaveName -TimeoutSeconds 300 2>&1 | Out-String
    $childOutput | Set-Content -LiteralPath $childOutputPath -Encoding UTF8
    if ($LASTEXITCODE -ne 0) { throw "Native Battle Mission formation probe failed with exit code $LASTEXITCODE. Child output: $childOutput" }
    $childOutput
}
