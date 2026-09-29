[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [string]$ProtocolSaveName = 'AgentBridgeProtocol',
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$saveDirectory = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\Game Saves'
$loadSavePath = Join-Path $saveDirectory "$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$runPrefix = 'p2-' + (Get-Date -Format 'yyyyMMddHHmmssfff')
$protocolSavePrefix = $ProtocolSaveName -replace '[^A-Za-z0-9_-]', ''
if ([string]::IsNullOrWhiteSpace($protocolSavePrefix)) { $protocolSavePrefix = 'ChronicleProtocol' }
$protocolSaveSuffix = [Guid]::NewGuid().ToString('N').Substring(0, 10)
$maximumPrefixLength = 30 - $protocolSaveSuffix.Length - 1
if ($protocolSavePrefix.Length -gt $maximumPrefixLength) { $protocolSavePrefix = $protocolSavePrefix.Substring(0, $maximumPrefixLength) }
$protocolSaveNameForRun = "$protocolSavePrefix-$protocolSaveSuffix"
$saveDirectoryPath = [IO.Path]::GetFullPath($saveDirectory).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
$protocolSavePath = [IO.Path]::GetFullPath((Join-Path $saveDirectoryPath "$protocolSaveNameForRun.sav"))
if (-not [string]::Equals([IO.Path]::GetDirectoryName($protocolSavePath), $saveDirectoryPath, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Disposable protocol save path escaped Game Saves.'
}

if (-not (Test-Path $cli)) { throw "CLI not found: $cli" }
if (-not (Test-Path $loadSavePath)) { throw "Save not found: $loadSavePath" }
$fixtureHashBefore = (Get-FileHash $loadSavePath -Algorithm SHA256).Hash
if (Test-Path -LiteralPath $protocolSavePath) { throw 'Unique disposable protocol save name unexpectedly already exists.' }

function Remove-ProtocolSaveFixture {
    $fullPath = [IO.Path]::GetFullPath($protocolSavePath)
    if (-not [string]::Equals([IO.Path]::GetDirectoryName($fullPath), $saveDirectoryPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Disposable protocol save cleanup path escaped Game Saves.'
    }
    if (Test-Path -LiteralPath $fullPath) { Remove-Item -LiteralPath $fullPath -Force }
    return -not (Test-Path -LiteralPath $fullPath)
}

function Invoke-AgentCli {
    param([string]$Action, [string[]]$Arguments = @())
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $cli $Action @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    return $output | ConvertFrom-Json
}

function Get-PersistedCampaignFingerprint($Response) {
    $snapshot = $Response.state
    if ($null -eq $snapshot) { throw 'Save/load fingerprint requires a structured Campaign snapshot.' }
    $quests = @($snapshot.quests | ForEach-Object { '{0}:{1}:{2}' -f $_.id, $_.name, $_.isActive } | Sort-Object)
    $targetPosition = $snapshot.location.targetPosition
    $targetPositionX = $null
    $targetPositionY = $null
    $targetPositionIsOnLand = $null
    if ($null -ne $targetPosition) {
        $targetPositionX = [double]$targetPosition.x
        $targetPositionY = [double]$targetPosition.y
        $targetPositionIsOnLand = [bool]$targetPosition.isOnLand
    }
    return [ordered]@{
        HeroId = [string]$snapshot.identity.heroId
        ClanId = [string]$snapshot.identity.clanId
        ClanTier = [int]$snapshot.identity.clanTier
        Gold = [int]$snapshot.economy.gold
        Influence = [int]$snapshot.economy.influence
        Renown = [double]$snapshot.economy.renown
        MainPartyId = [string]$snapshot.party.id
        PartyMembers = [int]$snapshot.party.members
        PartyHealthy = [int]$snapshot.party.healthy
        PartyWounded = [int]$snapshot.party.wounded
        PartyPrisoners = [int]$snapshot.party.prisoners
        PartyItems = [int]$snapshot.party.itemCount
        Food = [double]$snapshot.party.food
        FoodInventory = [int]$snapshot.party.foodInventory
        LocationX = [double]$snapshot.location.x
        LocationY = [double]$snapshot.location.y
        CurrentSettlementId = [string]$snapshot.location.currentSettlementId
        TargetSettlementId = [string]$snapshot.location.targetSettlementId
        TargetPartyId = [string]$snapshot.location.targetPartyId
        TargetPositionX = $targetPositionX
        TargetPositionY = $targetPositionY
        TargetPositionIsOnLand = $targetPositionIsOnLand
        Quests = $quests
        TimeControlMode = [string]$snapshot.context.timeControlMode
        GameState = [string]$snapshot.context.gameState
        EncounterActive = [bool]$snapshot.context.encounterActive
    }
}

try {
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName, '-TimeoutSeconds', $TimeoutSeconds)
    $state = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-state", '-TimeoutSeconds', $TimeoutSeconds)
    $startDay = [double]$state.campaignDay
    $pause = Invoke-AgentCli 'pause' @('-CommandId', "$runPrefix-pause", '-TimeoutSeconds', $TimeoutSeconds)
    $resume = Invoke-AgentCli 'resume' @('-CommandId', "$runPrefix-resume", '-TimeoutSeconds', $TimeoutSeconds)
    $fastForward = Invoke-AgentCli 'fastForward' @('-CommandId', "$runPrefix-fast-forward", '-TimeoutSeconds', $TimeoutSeconds)
    $pauseFastForward = Invoke-AgentCli 'pause' @('-CommandId', "$runPrefix-pause-fast-forward", '-TimeoutSeconds', $TimeoutSeconds)
    $advance = Invoke-AgentCli 'advance' @('-Days', '0.01', '-CommandId', "$runPrefix-advance", '-TimeoutSeconds', $TimeoutSeconds)
    $preSaveFingerprint = Get-PersistedCampaignFingerprint $advance
    $save = Invoke-AgentCli 'save' @('-SaveName', $protocolSaveNameForRun, '-CommandId', "$runPrefix-save", '-TimeoutSeconds', $TimeoutSeconds)
    $firstStop = Invoke-AgentCli 'stop' @('-CommandId', "$runPrefix-stop-1", '-TimeoutSeconds', $TimeoutSeconds)

    $reload = Invoke-AgentCli 'load' @('-SaveName', $protocolSaveNameForRun, '-TimeoutSeconds', $TimeoutSeconds)
    $reloadedState = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-reload-state", '-TimeoutSeconds', $TimeoutSeconds)
    $reloadedFingerprint = Get-PersistedCampaignFingerprint $reloadedState
    $secondStop = Invoke-AgentCli 'stop' @('-CommandId', "$runPrefix-stop-2", '-TimeoutSeconds', $TimeoutSeconds)

    $fixtureHashAfter = (Get-FileHash $loadSavePath -Algorithm SHA256).Hash
    $result = [ordered]@{
        ProtocolVersion = $state.protocolVersion
        ProtocolSaveName = $protocolSaveNameForRun
        Start = $start
        State = $state
        Pause = $pause
        Resume = $resume
        FastForward = $fastForward
        PauseFastForward = $pauseFastForward
        TimeControlTransitions = [ordered]@{
            Pause = $pause.data
            Resume = $resume.data
            FastForward = $fastForward.data
            PauseFastForward = $pauseFastForward.data
        }
        Advance = $advance
        Save = $save
        FirstStop = $firstStop
        Reload = $reload
        ReloadedState = $reloadedState
        PreSaveCampaignFingerprint = $preSaveFingerprint
        ReloadedCampaignFingerprint = $reloadedFingerprint
        PersistentCampaignStateMatchesAfterProcessRestart = (($preSaveFingerprint | ConvertTo-Json -Depth 6 -Compress) -ceq ($reloadedFingerprint | ConvertTo-Json -Depth 6 -Compress))
        SecondStop = $secondStop
        AdvanceDeltaDays = [double]$advance.campaignDay - $startDay
        ProtocolSaveExists = Test-Path $protocolSavePath
        ProtocolSaveHash = if (Test-Path $protocolSavePath) { (Get-FileHash $protocolSavePath -Algorithm SHA256).Hash } else { $null }
        FixtureUnchanged = $fixtureHashBefore -eq $fixtureHashAfter
    }
    $result.Passed = (
        $state.status -eq 'completed' -and
        $pause.timeControlMode -eq 'Stop' -and
        $resume.timeControlMode -ne 'Stop' -and
        $fastForward.status -eq 'completed' -and
        $fastForward.data.rawModeAfter -in @('StoppableFastForward','UnstoppableFastForward') -and
        $pauseFastForward.data.rawModeAfter -eq 'FastForwardStop' -and
        $advance.status -eq 'completed' -and
        $result.AdvanceDeltaDays -ge 0.01 -and
        $save.status -eq 'completed' -and
        $result.ProtocolSaveExists -and
        $firstStop.processStopped -and
        [int]$reloadedState.dailyTickCount -eq [int]$save.dailyTickCount -and
        [math]::Abs([double]$reloadedState.campaignDay - [double]$save.campaignDay) -lt 0.002 -and
        $result.PersistentCampaignStateMatchesAfterProcessRestart -and
        $reloadedState.timeControlMode -eq 'Stop' -and
        $secondStop.processStopped -and
        $result.FixtureUnchanged
    )
    $result.ProtocolSaveCleaned = Remove-ProtocolSaveFixture
    $result.Passed = $result.Passed -and $result.ProtocolSaveCleaned
    $result | ConvertTo-Json -Depth 10
    if (-not $result.Passed) { exit 1 }
}
finally {
    if (Test-Path $sessionPath) {
        try { Invoke-AgentCli 'stop' @('-CommandId', "$runPrefix-cleanup", '-TimeoutSeconds', '15') | Out-Null } catch { }
    }
    try { Remove-ProtocolSaveFixture | Out-Null } catch { Write-Warning "Could not clean disposable protocol save '$protocolSavePath': $($_.Exception.Message)" }
}
