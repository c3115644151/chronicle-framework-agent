#Requires -Version 7.0

# RecruitmentBaseline stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'RecruitmentBaseline' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $agentEvaluationRecruitmentBaselineScript 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Native recruitment evaluation baseline failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
