#Requires -Version 7.0

# BattleMissionInputIsolationProbe stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'BattleMissionInputIsolationProbe' -Action {
    $childOutputPath = Join-Path $harnessTempDirectory 'BattleMissionInputIsolationProbeChild.log'
    $childOutput = & $HarnessPowerShell -NoProfile -File $battleMissionFormationProbeScript -SourceSaveName $BattleSimulationSourceSaveName -TimeoutSeconds 300 -ProbeDesktopInputIsolationOnly 2>&1 | Out-String
    $childOutput | Set-Content -LiteralPath $childOutputPath -Encoding UTF8
    if ($LASTEXITCODE -ne 0) { throw "Native Battle Mission desktop-input isolation probe failed with exit code $LASTEXITCODE. Child output: $childOutput" }
    $childOutput
}
