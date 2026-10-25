[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$runPrefix = 'p3-' + (Get-Date -Format 'yyyyMMddHHmmssfff')
if (-not (Test-Path $savePath)) { throw "Observation fixture not found: $savePath" }
$fixtureHashBefore = (Get-FileHash $savePath -Algorithm SHA256).Hash

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @()) {
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $cli $Action @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    return $output | ConvertFrom-Json
}

try {
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName, '-TimeoutSeconds', $TimeoutSeconds)
    $first = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-state-1", '-TimeoutSeconds', $TimeoutSeconds)
    $second = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-state-2", '-TimeoutSeconds', $TimeoutSeconds)
    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$runPrefix-stop", '-TimeoutSeconds', $TimeoutSeconds)
    $fixtureHashAfter = (Get-FileHash $savePath -Algorithm SHA256).Hash
    $snapshot = $first.state
    $stableIdentity = $snapshot.identity.heroId -eq $second.state.identity.heroId -and $snapshot.party.id -eq $second.state.party.id
    $stablePosition = [math]::Abs([double]$snapshot.location.x - [double]$second.state.location.x) -lt 0.001 -and [math]::Abs([double]$snapshot.location.y - [double]$second.state.location.y) -lt 0.001
    $result = [ordered]@{
        ProtocolVersion = $first.protocolVersion
        StateSchemaVersion = $snapshot.schemaVersion
        ProcessId = $first.processId
        WindowLayout = $start.session.windowLayout
        Identity = $snapshot.identity
        ClanTierProgression = [ordered]@{
            Renown = $snapshot.economy.renown
            CurrentTier = $snapshot.identity.clanTier
            NextTierRequiredRenown = $snapshot.identity.nextTierRequiredRenown
            MercenaryRequiredTier = $snapshot.identity.mercenaryRequiredTier
        }
        Economy = $snapshot.economy
        Party = $snapshot.party
        InventoryScreen = $snapshot.inventoryScreen
        Location = $snapshot.location
        Context = $snapshot.context
        CaptivityContextNullWhenNotCaptive = ($null -eq $snapshot.context.captivity)
        BattleSimulation = $snapshot.context.battleSimulation
        NearbySettlementCount = @($snapshot.nearbySettlements).Count
        NearbyPartyCount = @($snapshot.nearbyParties).Count
        QuestCount = @($snapshot.quests).Count
        Danger = $snapshot.danger
        StableIdentity = $stableIdentity
        StablePositionWhilePaused = $stablePosition
        FixtureUnchanged = $fixtureHashBefore -eq $fixtureHashAfter
        ProcessStopped = $stop.processStopped
    }
    $result.Passed = (
        $snapshot.schemaVersion -eq 27 -and
        $null -eq $snapshot.mission -and
        $snapshot.location.PSObject.Properties['targetPosition'] -and
        ($null -eq $snapshot.location.targetPosition -or ($null -ne $snapshot.location.targetPosition.x -and $null -ne $snapshot.location.targetPosition.y -and $null -ne $snapshot.location.targetPosition.isOnLand)) -and
        -not [string]::IsNullOrWhiteSpace([string]$snapshot.identity.heroId) -and
        $null -ne $snapshot.identity.mercenaryRequiredTier -and
        ($snapshot.identity.clanTier -ge $snapshot.identity.mercenaryRequiredTier -or $snapshot.identity.nextTierRequiredRenown -ge $snapshot.economy.renown) -and
        -not [string]::IsNullOrWhiteSpace([string]$snapshot.party.id) -and
        [int]$snapshot.party.members -ge 1 -and
        $null -ne $snapshot.party.itemCount -and
        $null -ne $snapshot.location.x -and
        $null -ne $snapshot.location.y -and
        $null -ne $snapshot.context.encounterActive -and
        $null -eq $snapshot.context.lootItemCount -and
        $null -eq $snapshot.context.battleSimulation -and
        $null -eq $snapshot.context.captivity -and
        $null -eq $snapshot.inventoryScreen -and
        $null -ne $snapshot.danger.hostilePartyCount -and
        $stableIdentity -and $stablePosition -and
        $start.session.windowLayout.Applied -and
        [int]$start.session.windowLayout.DisplayMode -eq 0 -and
        $result.FixtureUnchanged -and $result.ProcessStopped
    )
    $result | ConvertTo-Json -Depth 8
    if (-not $result.Passed) { exit 1 }
}
finally {
    if (Test-Path $sessionPath) {
        try { Invoke-AgentCli 'stop' @('-CommandId', "$runPrefix-cleanup", '-TimeoutSeconds', '15') | Out-Null } catch { }
    }
}
