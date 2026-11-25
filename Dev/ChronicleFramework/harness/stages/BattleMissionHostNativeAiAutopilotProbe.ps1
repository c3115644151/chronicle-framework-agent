#Requires -Version 7.0

# BattleMissionHostNativeAiAutopilotProbe stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'BattleMissionHostNativeAiAutopilotProbe' -Action {
    if ([string]::IsNullOrWhiteSpace($script:retainedAgentHostExecutablePath) -or -not (Test-Path -LiteralPath $script:retainedAgentHostExecutablePath -PathType Leaf)) {
        throw 'The self-contained Agent Host runtime package was not retained for the same-session Native battle loop probe.'
    }
    $childOutputPath = Join-Path $harnessTempDirectory 'BattleMissionHostNativeAiAutopilotProbeChild.log'
    $battleProbeArguments = @('-SourceSaveName', $BattleSimulationSourceSaveName, '-TimeoutSeconds', '900', '-ProbeAgentHostNativeAiAutopilot')
    if ($BattleMissionSoloMainHeroProbe) { $battleProbeArguments += '-SoloMainHero' }
    $childOutput = & $HarnessPowerShell -NoProfile -File $battleMissionFormationProbeScript @battleProbeArguments 2>&1 | Out-String
    $childOutput | Set-Content -LiteralPath $childOutputPath -Encoding UTF8
    if ($LASTEXITCODE -ne 0) { throw "Production AgentHost Native battle autopilot probe failed with exit code $LASTEXITCODE.`nChild output: $childOutput" }
    $childOutput
}
