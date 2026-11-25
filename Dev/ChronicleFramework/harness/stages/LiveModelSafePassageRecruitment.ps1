#Requires -Version 7.0

# LiveModelSafePassageRecruitment stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'LiveModelSafePassageRecruitment' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $agentLiveModelLoopScript -RecruitmentLoop -RoadsideBanditNegotiationLoop 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Live-model roadside Safe Passage recruitment loop failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
