#Requires -Version 7.0

# AgentLoop stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'AgentLoop' -Action {
    $providerOutput = & $HarnessPowerShell -NoProfile -File $agentModelProviderScript 2>&1 | Out-String
    $providerExitCode = $LASTEXITCODE
    if ($providerExitCode -ne 0) { throw "OpenAI-compatible provider protocol test failed with exit code $providerExitCode.`n$providerOutput" }
    $testOutput = & $HarnessPowerShell -NoProfile -File $agentLoopScript 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) { throw "Agent decision loop test failed with exit code $testExitCode.`n$testOutput" }
    "Provider Protocol Stub:`n$providerOutput`nAgent Loop:`n$testOutput"
}
