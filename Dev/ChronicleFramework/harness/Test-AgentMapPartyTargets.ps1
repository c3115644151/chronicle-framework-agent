#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$resultPath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP 'MapPartyTargetsResult.json' } else { Join-Path (Split-Path -Parent $PSScriptRoot) 'TestResults\ManualMapPartyTargets\MapPartyTargetsResult.json' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$commandPrefix = 'map-party-targets-' + (Get-Date -Format 'yyyyMMddHHmmssfff')

if (-not (Test-Path -LiteralPath $savePath)) { throw "Map party target fixture not found: $savePath" }
if (Get-Process -Name Bannerlord -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $output = & $HarnessPowerShell -NoProfile -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $pause = Invoke-AgentCli 'pause' @('-CommandId', "$commandPrefix-pause")
    $before = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-before")
    $observed = Invoke-AgentCli 'mapPartyTargets' @('-CommandId', "$commandPrefix-observe")
    $native = Invoke-AgentCli 'harnessMapPartyDiagnostics' @('-CommandId', "$commandPrefix-native")
    $repeat = Invoke-AgentCli 'mapPartyTargets' @('-CommandId', "$commandPrefix-repeat")
    $after = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-after")

    $targets = @($observed.data.mapPartyTargets)
    $nativeCandidates = @($native.data.mapPartyEntities | Where-Object { $_.isNativeMarkerCandidate })
    $nativeById = @{}
    foreach ($row in $native.data.mapPartyEntities) { $nativeById[[string]$row.id] = $row }
    $ids = @($targets | ForEach-Object { [string]$_.id })
    $sortedIds = @($targets | Sort-Object { [double]$_.distance }, { [string]$_.id } | ForEach-Object { [string]$_.id })
    $candidateIds = @($nativeCandidates | ForEach-Object { [string]$_.id } | Sort-Object)
    $observedIds = @($ids | Sort-Object)
    $setMatches = @(Compare-Object -ReferenceObject $candidateIds -DifferenceObject $observedIds).Count -eq 0
    $fieldsMatch = $true
    foreach ($target in $targets) {
        $reference = $nativeById[[string]$target.id]
        if ($null -eq $reference -or
            [string]$target.name -ne [string]$reference.nameplateName -or
            [string]$target.type -ne [string]$reference.type -or
            [bool]$target.isInspected -ne [bool]$reference.isInspected -or
            [int]$target.healthyMemberCount -ne [int]$reference.nameplateHealthyCount -or
            [int]$target.woundedCount -ne [int]$reference.nameplateWoundedCount -or
            [int]$target.prisonerCount -ne [int]$reference.nameplatePrisonerCount -or
            [Math]::Abs([double]$target.distance - [double]$reference.distance) -gt 0.001) { $fieldsMatch = $false; break }
    }
    $sorted = [string]::Join('|', $ids) -eq [string]::Join('|', $sortedIds)
    $stableAcrossReads = [string](ConvertTo-Json -InputObject $observed.data -Depth 10 -Compress) -ceq [string](ConvertTo-Json -InputObject $repeat.data -Depth 10 -Compress)
    $snapshotUnchanged = (
        $before.state.identity.heroId -eq $after.state.identity.heroId -and
        $before.state.location.x -eq $after.state.location.x -and
        $before.state.location.y -eq $after.state.location.y -and
        $before.state.party.id -eq $after.state.party.id -and
        $before.state.party.members -eq $after.state.party.members -and
        $before.state.party.prisoners -eq $after.state.party.prisoners -and
        $before.state.economy.gold -eq $after.state.economy.gold -and
        $before.state.economy.renown -eq $after.state.economy.renown -and
        $before.campaignDay -eq $after.campaignDay -and
        $after.state.context.timeControlMode -eq 'Stop'
    )
    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-stop") 30
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $assertions = [ordered]@{
        CampaignMapAndExplicitPause = ($before.state.context.gameState -eq 'MapState' -and $pause.status -eq 'completed' -and $after.state.context.timeControlMode -eq 'Stop')
        TargetSetMatchesNativeVisibleMarkerCandidates = [bool]$setMatches
        TargetFieldsMatchNativeNameplateData = [bool]$fieldsMatch
        ResultsSortedByDistanceThenId = [bool]$sorted
        StableAcrossRepeatedReads = [bool]$stableAcrossReads
        SnapshotUnchanged = [bool]$snapshotUnchanged
        FixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = [bool]$stop.processStopped
    }
    $failedAssertions = @($assertions.Keys | Where-Object { -not [bool]$assertions[$_] })
    $result = [ordered]@{
        TargetCount = $targets.Count
        NativeCandidateCount = $nativeCandidates.Count
        RuntimeIsInfoHiddenValues = @($native.data.mapPartyEntities | ForEach-Object { $_.isInfoHidden } | Sort-Object -Unique)
        Assertions = $assertions
        FailedAssertions = $failedAssertions
        Passed = ($failedAssertions.Count -eq 0)
    }
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    $result | ConvertTo-Json -Depth 8
    if (-not $result.Passed) { throw 'Map party target observation diverged from native visible marker/nameplate data or changed Campaign/save state.' }
}
finally {
    if (Test-Path $sessionPath) {
        try { Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-cleanup") 20 | Out-Null } catch { }
    }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
