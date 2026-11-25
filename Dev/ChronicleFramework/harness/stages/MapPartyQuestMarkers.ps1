#Requires -Version 7.0

# MapPartyQuestMarkers stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'MapPartyQuestMarkers' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $mapPartyQuestMarkersScript 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Native map Party Issue marker observation test failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
