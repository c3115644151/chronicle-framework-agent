#Requires -Version 7.0

# AlleyAttackFightMission stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'AlleyAttackFightMission' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $alleyAttackFightMissionScript 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Native Alley Fight Mission entry/retreat failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
