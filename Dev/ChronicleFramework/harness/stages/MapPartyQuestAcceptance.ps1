#Requires -Version 7.0

# MapPartyQuestAcceptance stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'MapPartyQuestAcceptance' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $mapPartyQuestAcceptanceScript 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Native map Lord Issue Quest acceptance test failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
