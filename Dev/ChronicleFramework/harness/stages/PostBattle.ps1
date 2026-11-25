#Requires -Version 7.0

# PostBattle stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'PostBattle' -Action {
    $childOutputPath = Join-Path $harnessTempDirectory 'PostBattleChild.log'
    $childOutput = & $HarnessPowerShell -NoProfile -File $battleFixtureScript -LoadSaveName $BattleSimulationSourceSaveName -Scenario PostBattle -CaptureFrames 2>&1 | Out-String
    $childOutput | Set-Content -LiteralPath $childOutputPath -Encoding UTF8
    if ($LASTEXITCODE -ne 0) { throw "Postbattle test failed with exit code $LASTEXITCODE. Child output: $childOutput" }
    $childOutput
}
