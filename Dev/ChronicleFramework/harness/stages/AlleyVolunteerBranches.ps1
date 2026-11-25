#Requires -Version 7.0

# AlleyVolunteerBranches stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'AlleyVolunteerBranches' -Action {
    $outputs = [System.Collections.Generic.List[string]]::new()
    foreach ($scenario in @('noVolunteers','availableVolunteers')) {
        $testOutput = & $HarnessPowerShell -NoProfile -File $missionSceneNavigationScript -VolunteerScenario $scenario 2>&1 | Out-String
        $testExitCode = $LASTEXITCODE
        if ($testExitCode -ne 0) { throw "Alley volunteer branch '$scenario' failed with exit code $testExitCode.`n$testOutput" }
        $outputs.Add("scenario=$scenario`n$testOutput")
    }
    $outputs -join "`n"
}
