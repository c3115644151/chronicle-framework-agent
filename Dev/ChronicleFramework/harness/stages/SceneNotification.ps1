#Requires -Version 7.0

# SceneNotification stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'SceneNotification' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $sceneNotificationScript 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Native SceneNotification observation test failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
