#Requires -Version 7.0

# LiveModelRecruitmentEvaluation stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'LiveModelRecruitmentEvaluation' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $agentEvaluationLiveModelRecruitmentScript 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Repeated real-model recruitment evaluation failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
