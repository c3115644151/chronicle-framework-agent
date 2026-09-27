[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$resultPath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP 'PartyRosterResult.json' } else { Join-Path $PSScriptRoot 'TestResults\ManualPartyRoster\PartyRosterResult.json' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$commandPrefix = 'party-roster-' + (Get-Date -Format 'yyyyMMddHHmmssfff')

if (-not (Test-Path -LiteralPath $savePath)) { throw "Party roster fixture not found: $savePath" }
if (Get-Process -Name Bannerlord -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

function Test-RosterEquality($Observed, $Native) {
    $ids = @($Observed | ForEach-Object { [string]$_.characterId })
    $nativeIds = @($Native | ForEach-Object { [string]$_.characterId })
    if (@(Compare-Object -ReferenceObject @($ids | Sort-Object) -DifferenceObject @($nativeIds | Sort-Object)).Count -ne 0) { return $false }
    foreach ($row in $Observed) {
        $nativeRow = @($Native | Where-Object { $_.characterId -eq $row.characterId } | Select-Object -First 1)
        if ($nativeRow.Count -ne 1) { return $false }
        $n = $nativeRow[0]
        if ([string]$row.name -ne [string]$n.name -or
            [int]$row.tier -ne [int]$n.tier -or
            [int]$row.count -ne [int]$n.count -or
            [int]$row.woundedCount -ne [int]$n.woundedCount -or
            [int]$row.healthyCount -ne [int]$n.healthyCount -or
            [bool]$row.isHero -ne [bool]$n.isHero -or
            [bool]$row.isHeroWounded -ne [bool]$n.isHeroWounded) { return $false }
    }
    return $true
}

try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $pause = Invoke-AgentCli 'pause' @('-CommandId', "$commandPrefix-pause")
    $before = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-before")
    $observed = Invoke-AgentCli 'partyRoster' @('-CommandId', "$commandPrefix-roster")
    $native = Invoke-AgentCli 'harnessPartyRosterDiagnostics' @('-CommandId', "$commandPrefix-native")
    $repeat = Invoke-AgentCli 'partyRoster' @('-CommandId', "$commandPrefix-roster-repeat")
    $after = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-after")
    $data = $observed.data
    $reference = $native.data

    $membersMatch = Test-RosterEquality @($data.members) @($reference.members)
    $prisonersMatch = Test-RosterEquality @($data.prisoners) @($reference.prisoners)
    $totalsMatch = (
        [int]$data.memberTotals.totalCount -eq [int]$before.state.party.members -and
        [int]$data.memberTotals.healthyCount -eq [int]$before.state.party.healthy -and
        [int]$data.memberTotals.woundedCount -eq [int]$before.state.party.wounded -and
        [int]$data.prisonerTotals.totalCount -eq [int]$before.state.party.prisoners -and
        [int]$data.memberTotals.totalCount -eq [int]$reference.memberTotals.totalCount -and
        [int]$data.memberTotals.healthyCount -eq [int]$reference.memberTotals.healthyCount -and
        [int]$data.memberTotals.woundedCount -eq [int]$reference.memberTotals.woundedCount -and
        [int]$data.prisonerTotals.totalCount -eq [int]$reference.prisonerTotals.totalCount -and
        [int]$data.prisonerTotals.healthyCount -eq [int]$reference.prisonerTotals.healthyCount -and
        [int]$data.prisonerTotals.woundedCount -eq [int]$reference.prisonerTotals.woundedCount
    )
    $stableAcrossReads = [string](ConvertTo-Json -InputObject $data -Depth 10 -Compress) -ceq [string](ConvertTo-Json -InputObject $repeat.data -Depth 10 -Compress)
    $snapshotUnchanged = (
        $before.state.identity.heroId -eq $after.state.identity.heroId -and
        $before.state.location.x -eq $after.state.location.x -and
        $before.state.location.y -eq $after.state.location.y -and
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
        PartyIdMatchesMainParty = ($data.partyId -eq $before.state.party.id -and $data.partyId -eq $reference.partyId)
        MemberRowsMatchNativeRoster = [bool]$membersMatch
        PrisonerRowsMatchNativeRoster = [bool]$prisonersMatch
        TotalsMatchStateAndNativeRoster = [bool]$totalsMatch
        StableAcrossRepeatedReads = [bool]$stableAcrossReads
        SnapshotUnchanged = [bool]$snapshotUnchanged
        FixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = [bool]$stop.processStopped
    }
    $failedAssertions = @($assertions.Keys | Where-Object { -not [bool]$assertions[$_] })
    $result = [ordered]@{
        MemberRowCount = @($data.members).Count
        PrisonerRowCount = @($data.prisoners).Count
        MemberTotals = $data.memberTotals
        PrisonerTotals = $data.prisonerTotals
        Assertions = $assertions
        FailedAssertions = $failedAssertions
        Passed = ($failedAssertions.Count -eq 0)
    }
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    $result | ConvertTo-Json -Depth 8
    if (-not $result.Passed) { throw 'Party roster observation diverged from native MainParty roster data or changed Campaign/save state.' }
}
finally {
    if (Test-Path $sessionPath) {
        try { Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-cleanup") 20 | Out-Null } catch { }
    }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
