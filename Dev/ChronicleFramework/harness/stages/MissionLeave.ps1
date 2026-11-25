#Requires -Version 7.0

# MissionLeave stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'MissionLeave' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $missionLeaveScript 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Native Mission Leave runtime test failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
