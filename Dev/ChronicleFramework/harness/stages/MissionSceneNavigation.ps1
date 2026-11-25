#Requires -Version 7.0

# MissionSceneNavigation stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'MissionSceneNavigation' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $missionSceneNavigationScript 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Native Mission scene discovery/navigation failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
