#Requires -Version 7.0

# MovingArmyJoin stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'MovingArmyJoin' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $movingArmyJoinScript 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Native unengaged Army encounter Join Army test failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
