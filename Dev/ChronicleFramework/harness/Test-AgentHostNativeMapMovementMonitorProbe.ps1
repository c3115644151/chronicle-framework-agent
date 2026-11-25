#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateRange(1,10)][int]$WaitSeconds = 8
)

$ErrorActionPreference = 'Stop'
$stageRoot = $PSScriptRoot
$harnessRoot = Split-Path -Parent $stageRoot
$documents = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
if ([string]::IsNullOrWhiteSpace($documents)) { throw 'Windows Documents directory could not be resolved for the live Native map-movement probe.' }
$protocolRoot = Join-Path $documents 'Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent'
$sessionPath = Join-Path $protocolRoot 'session.json'
if (-not (Test-Path -LiteralPath $sessionPath -PathType Leaf)) { throw 'The Native map-movement probe requires an active Agent-Cli session; no game command was sent.' }
$session = Get-Content -LiteralPath $sessionPath -Raw -Encoding UTF8 | ConvertFrom-Json
$fixtureName = [string]$session.saveName
if (-not $fixtureName.StartsWith('ChronicleW7P-manual-', [StringComparison]::Ordinal) -or
    -not (Get-Process -Id ([int]$session.processId) -ErrorAction SilentlyContinue)) {
    throw 'The live Native movement probe is restricted to a running Harness-owned disposable W7-P manual campaign session.'
}
if (@(Get-Process -Name 'ChronicleAgentHost*' -ErrorAction SilentlyContinue).Count -gt 0) {
    throw 'An Agent Host already owns the Native mailbox; the diagnostic probe will not compete with it.'
}
$hostDll = Join-Path $agentHostRoot 'bin\Release\net8.0\ChronicleAgentHost.dll'
if (-not (Test-Path -LiteralPath $hostDll -PathType Leaf)) { throw 'The Release Agent Host DLL is missing; run the dedicated Build stage first.' }
$testTemp = $env:CHRONICLE_HARNESS_TEMP
if ([string]::IsNullOrWhiteSpace($testTemp) -or -not (Test-Path -LiteralPath $testTemp -PathType Container)) {
    throw 'The live Native movement probe requires the active Harness TestResults temp directory.'
}

$priorHarnessMode = [Environment]::GetEnvironmentVariable('CHRONICLE_HARNESS_MODE', 'Process')
$priorHarnessTemp = [Environment]::GetEnvironmentVariable('CHRONICLE_HARNESS_TEMP', 'Process')
$stdout = ''
$stderr = ''
$exitCode = 1
try {
    [Environment]::SetEnvironmentVariable('CHRONICLE_HARNESS_MODE', 'agent-host-native-map-movement-monitor-probe', 'Process')
    $output = & dotnet $hostDll --native-map-movement-monitor-probe $WaitSeconds 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    $stdout = $output.Trim()
}
finally {
    [Environment]::SetEnvironmentVariable('CHRONICLE_HARNESS_MODE', $priorHarnessMode, 'Process')
    [Environment]::SetEnvironmentVariable('CHRONICLE_HARNESS_TEMP', $priorHarnessTemp, 'Process')
}

$logPath = Join-Path $testTemp 'NativeMapMovementMonitorProbe.log'
Set-Content -LiteralPath $logPath -Value $stdout -Encoding UTF8
if ($exitCode -ne 0) { throw "The live Native movement probe failed with exit code $exitCode; receipt: $logPath" }
try { $probe = $stdout | ConvertFrom-Json }
catch { throw "The live Native movement probe did not return valid JSON; receipt: $logPath" }
if ($probe.status -ne 'completed' -or $probe.probe -ne 'native-map-movement-monitor' -or
    [int]$probe.mapPartyTargetPollCount -lt 1 -or [int]$probe.modelCalls -ne 0) {
    throw "The live Native movement probe did not verify at least one passive poll without model calls; receipt: $logPath"
}
$probe | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $testTemp 'NativeMapMovementMonitorProbe.json') -Encoding UTF8
[ordered]@{
    Passed = $true
    SaveName = $fixtureName
    GameProcessId = [int]$session.processId
    WaitSeconds = [int]$probe.waitSeconds
    CampaignDayBefore = $probe.campaignDayBefore
    CampaignDayAfter = $probe.campaignDayAfter
    MapPartyTargetPollCount = [int]$probe.mapPartyTargetPollCount
    InterruptedByVisibleHostileBandit = [bool]$probe.interruptedByVisibleHostileBandit
    VisibleHostileBanditTargetCount = @($probe.visibleHostileBanditTargets).Count
    NativePauseAccepted = $null -ne $probe.nativePauseReceipt
    FreshPausedMapStillShowsBandit = $probe.freshPausedMapStillShowsBandit
    ModelCalls = [int]$probe.modelCalls
} | ConvertTo-Json -Depth 5 -Compress
