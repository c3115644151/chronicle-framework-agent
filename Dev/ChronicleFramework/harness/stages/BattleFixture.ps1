#Requires -Version 7.0

# BattleFixture stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'BattleFixture' -Action {
    $childOutputPath = Join-Path $harnessTempDirectory 'BattleFixtureChild.log'
    $childOutput = & $HarnessPowerShell -NoProfile -File $battleFixtureScript -LoadSaveName $BattleSimulationSourceSaveName 2>&1 | Out-String
    $childOutput | Set-Content -LiteralPath $childOutputPath -Encoding UTF8
    if ($LASTEXITCODE -ne 0) { throw "Battle fixture test failed with exit code $LASTEXITCODE. Child output: $childOutput" }
    $childOutput
}
