#Requires -Version 7.0

# AlleyAttackYield stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'AlleyAttackYield' -Action {
    $outputs = [System.Collections.Generic.List[string]]::new()
    foreach ($scenario in @('noAttack','peacefulYield')) {
        $testOutput = & $HarnessPowerShell -NoProfile -File $alleyAttackYieldScript -Scenario $scenario 2>&1 | Out-String
        $testExitCode = $LASTEXITCODE
        if ($testExitCode -ne 0) { throw "Alley attack branch '$scenario' failed with exit code $testExitCode.`n$testOutput" }
        $outputs.Add("scenario=$scenario`n$testOutput")
    }
    $outputs -join "`n"
}
