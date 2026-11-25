#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateRange(0.1,1.0)][double]$AdvanceDays = 0.25,
    [ValidateRange(60,900)][int]$AdvanceTimeoutSeconds = 600,
    [string]$SaveName = 'AgentBridgeLifecycle'
)

$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$harnessTemp = $env:CHRONICLE_HARNESS_TEMP
if ([string]::IsNullOrWhiteSpace($harnessTemp) -or -not (Test-Path -LiteralPath $harnessTemp -PathType Container)) {
    throw 'Campaign Actor Think trace requires an active Harness evidence directory.'
}

$documentsRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)) 'Mount and Blade II Bannerlord'
$savePath = Join-Path $documentsRoot "Game Saves\$SaveName.sav"
$sessionPath = Join-Path $documentsRoot 'AgentRuns\ChronicleAgent\session.json'
$diagnosticLog = Join-Path $documentsRoot 'Configs\ModLogs\chronicle-framework.log'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$resultPath = Join-Path $harnessTemp 'CampaignActorThinkTraceResult.json'
$traceId = [Guid]::NewGuid().ToString('N')
$marker = "campaign-actor-think-trace|trace=$traceId|"

if (-not (Test-Path -LiteralPath $savePath -PathType Leaf)) { throw "Disposable Campaign trace save not found: $SaveName" }
if (Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue) { throw 'Refusing to start the Actor trace while a Bannerlord process is already running.' }
if (Test-Path -LiteralPath $sessionPath -PathType Leaf) { throw 'Refusing to replace a stale Agent CLI session.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
$diagnosticLogOffset = if (Test-Path -LiteralPath $diagnosticLog -PathType Leaf) { [long](Get-Item -LiteralPath $diagnosticLog).Length } else { 0L }

$priorValues = @{}
foreach ($name in @('CHRONICLE_HARNESS_MODE','CHRONICLE_HARNESS_ACTOR_TRACE_ID','CHRONICLE_HARNESS_ACTOR_HERO_ID')) {
    $priorValues[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

function Invoke-ActorTraceCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 30) {
    $output = & $HarnessPowerShell -NoProfile -File $cli $Action @Arguments -TimeoutSeconds $CommandTimeout -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Actor trace CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Actor trace CLI '$Action' returned invalid JSON." }
}

function Read-NewTraceLines([long]$Offset, [string]$ExpectedMarker) {
    if (-not (Test-Path -LiteralPath $diagnosticLog -PathType Leaf)) { return @() }
    $traceRecords = [System.Collections.Generic.List[string]]::new()
    $stream = [IO.File]::Open($diagnosticLog, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        if ($stream.Length -lt $Offset) { throw 'Chronicle diagnostic log shrank during the trace; preserving the run as inconclusive.' }
        $stream.Position = $Offset
        $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8, $true, 4096, $true)
        try {
            while ($null -ne ($line = $reader.ReadLine())) {
                if ($line.Contains($ExpectedMarker)) { $traceRecords.Add($line) }
            }
        }
        finally { $reader.Dispose() }
    }
    finally { $stream.Dispose() }
    return @($traceRecords)
}

$gameStarted = $false
$load = $null
$before = $null
$after = $null
$advance = $null
$pause = $null
$stop = $null
$traceLine = $null

try {
    $env:CHRONICLE_HARNESS_MODE = 'campaign-actor-think-trace'
    $env:CHRONICLE_HARNESS_ACTOR_TRACE_ID = $traceId
    Remove-Item Env:CHRONICLE_HARNESS_ACTOR_HERO_ID -ErrorAction SilentlyContinue

    $load = Invoke-ActorTraceCli 'load' @('-SaveName', $SaveName) 180
    if ($load.status -ne 'completed' -or -not $load.session.processId) { throw 'The disposable Campaign did not complete the Native handshake.' }
    $gameStarted = $true
    $before = Invoke-ActorTraceCli 'state'
    if ($before.state.context.gameState -ne 'MapState') { throw "Actor trace expected MapState, got $($before.state.context.gameState)." }

    $advance = Invoke-ActorTraceCli 'advance' @('-Days', $AdvanceDays.ToString('F3', [System.Globalization.CultureInfo]::InvariantCulture)) $AdvanceTimeoutSeconds
    if ($advance.status -ne 'completed') { throw "The explicit Harness Campaign advance did not complete ($AdvanceDays days)." }

    $after = Invoke-ActorTraceCli 'state'
    if ($after.state.context.timeControlMode -ne 'Stop') {
        $pause = Invoke-ActorTraceCli 'pause'
        $after = Invoke-ActorTraceCli 'state'
    }
    $stop = Invoke-ActorTraceCli 'stop' @() 45
    $gameStarted = $false

    $traceSamples = @(Read-NewTraceLines $diagnosticLogOffset $marker)
    $traceLine = @($traceSamples | Where-Object { [int]([regex]::Match($_, '\|candidateCount=(\d+)').Groups[1].Value) -gt 0 } | Select-Object -First 1)
    if ($traceLine.Count -eq 0) { $traceLine = @($traceSamples | Select-Object -First 1) }
    $traceLine = if ($traceLine.Count -gt 0) { [string]$traceLine[0] } else { $null }
    $actorHeroId = [regex]::Match($traceLine, '\|actorHeroId=([^|]+)').Groups[1].Value
    $partyId = [regex]::Match($traceLine, '\|partyId=([^|]+)').Groups[1].Value
    $candidateCountText = [regex]::Match($traceLine, '\|candidateCount=(\d+)').Groups[1].Value
    $candidateCount = if ($candidateCountText) { [int]$candidateCountText } else { -1 }
    $sameMainHero = (
        $before.state.identity.heroId -eq $after.state.identity.heroId -and
        $before.state.party.id -eq $after.state.party.id -and
        $before.state.economy.gold -eq $after.state.economy.gold -and
        $before.state.economy.renown -eq $after.state.economy.renown
    )
    $mainHeroLocationChangedDuringHarnessAdvance = (
        $before.state.location.x -ne $after.state.location.x -or
        $before.state.location.y -ne $after.state.location.y -or
        $before.state.location.currentSettlementId -ne $after.state.location.currentSettlementId
    )
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $assertions = [ordered]@{
        CapturedNonMainHeroLord = (-not [string]::IsNullOrWhiteSpace($actorHeroId) -and $actorHeroId -ne [string]$before.state.identity.heroId)
        CapturedPartyThinkCandidateList = ($candidateCount -gt 0)
        ExplicitClockCommandWasAccepted = ($advance.status -eq 'completed' -and $after.state.context.timeControlMode -eq 'Stop' -and [double]$after.campaignDay -gt [double]$before.campaignDay)
        MainHeroIdentityPartyAndEconomyUnchanged = [bool]$sameMainHero
        SourceFixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        GameProcessStopped = [bool]$stop.processStopped
    }
    $failed = @($assertions.Keys | Where-Object { -not [bool]$assertions[$_] })
    $result = [ordered]@{
        TraceId = $traceId
        SaveName = $SaveName
        ActorHeroId = $actorHeroId
        PartyId = $partyId
        CandidateCount = $candidateCount
        Trace = $traceLine
        TraceSamples = $traceSamples
        CampaignDayBefore = $before.campaignDay
        CampaignDayAfter = $after.campaignDay
        MainHeroLocationBefore = $before.state.location
        MainHeroLocationAfter = $after.state.location
        MainHeroLocationChangedDuringHarnessAdvance = [bool]$mainHeroLocationChangedDuringHarnessAdvance
        MainHeroMoveCommandIssued = $false
        HarnessAdvanceDaysRequested = $AdvanceDays
        HarnessAdvanceCompletedBy = [string]$advance.data.completedBy
        ConditionalPauseReceipt = $pause
        Assertions = $assertions
        FailedAssertions = $failed
        Passed = ($failed.Count -eq 0)
        Scope = 'Read-only Native Think cache sample; no Actor action was submitted; the Harness explicitly advanced Campaign time by a bounded amount and records any Native encounter interruption.'
    }
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    $result | ConvertTo-Json -Depth 8
    if (-not $result.Passed) { throw 'Campaign Actor Think trace failed one or more assertions.' }
}
finally {
    if ($gameStarted -or (Test-Path -LiteralPath $sessionPath -PathType Leaf)) {
        try { Invoke-ActorTraceCli 'stop' @() 45 | Out-Null } catch { }
    }
    foreach ($name in $priorValues.Keys) {
        if ($null -eq $priorValues[$name]) { [Environment]::SetEnvironmentVariable($name, $null, 'Process') }
        else { [Environment]::SetEnvironmentVariable($name, [string]$priorValues[$name], 'Process') }
    }
}
