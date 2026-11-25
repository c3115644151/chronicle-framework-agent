#Requires -Version 7.0

# VillageToolsDelivery stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'VillageToolsDelivery' -Action {
    $testOutput = & $HarnessPowerShell -NoProfile -File $villageToolsDeliveryScript -MaxDecisions $VillageToolsMaxDecisions 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Autonomous Native Village Tools delivery test failed with exit code $testExitCode.`n$testOutput" }
    $testOutput
}
