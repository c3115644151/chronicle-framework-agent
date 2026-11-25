#Requires -Version 7.0

# Recruitment stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'Recruitment' -Action {
    if ($RecruitmentBulkOnly) {
        $testOutput = & $HarnessPowerShell -NoProfile -File $recruitmentScript -BulkOnly 2>&1 | Out-String
    }
    else {
        $testOutput = & $HarnessPowerShell -NoProfile -File $recruitmentScript 2>&1 | Out-String
    }
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Agent recruitment test failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
