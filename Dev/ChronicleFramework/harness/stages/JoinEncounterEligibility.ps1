#Requires -Version 7.0

# JoinEncounterEligibility stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'JoinEncounterEligibility' -Action {
    foreach ($relationProfile in @('HelpAttackers', 'Neutral')) {
        $testOutput = & $HarnessPowerShell -NoProfile -File $joinEncounterEligibilityScript -RelationProfile $relationProfile 2>&1 | Out-String
        $testExitCode = $LASTEXITCODE
        if ($testExitCode -ne 0) { throw "Native Join Encounter $relationProfile eligibility test failed with exit code $testExitCode.`n$testOutput" }
        $testOutput
    }
}
