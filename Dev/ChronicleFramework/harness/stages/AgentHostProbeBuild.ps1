#Requires -Version 7.0

# AgentHostProbeBuild stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'AgentHostProbeBuild' -Action {
    $probeBuildOutput = & dotnet build $agentHostProjectPath --configuration Release --no-restore 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent Host-only probe build failed with exit code $LASTEXITCODE.`n$probeBuildOutput" }
    $probeBuildOutput
}
