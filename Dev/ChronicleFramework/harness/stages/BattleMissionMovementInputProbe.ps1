#Requires -Version 7.0

# BattleMissionMovementInputProbe stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'BattleMissionMovementInputProbe' -Action {
    $childOutputPath = Join-Path $harnessTempDirectory 'BattleMissionMovementInputProbeChild.log'
    $childOutput = & $HarnessPowerShell -NoProfile -File $battleMissionFormationProbeScript -SourceSaveName $BattleSimulationSourceSaveName -TimeoutSeconds 300 -ProbeBattleMovementInput 2>&1 | Out-String
    $childOutput | Set-Content -LiteralPath $childOutputPath -Encoding UTF8
    if ($LASTEXITCODE -ne 0) { throw "Native Battle movement input probe failed with exit code $LASTEXITCODE.`nChild output: $childOutput" }
    $childOutput
}
