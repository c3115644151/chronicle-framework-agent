#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [string]$ProtocolSaveName = 'AgentBridgeProtocol',
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$documentsPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
if ([string]::IsNullOrWhiteSpace($documentsPath)) { throw 'Windows Documents directory could not be resolved for the protocol fixture.' }
$documentsRoot = Join-Path $documentsPath 'Mount and Blade II Bannerlord'
$saveDirectory = Join-Path $documentsRoot 'Game Saves'
$loadSavePath = Join-Path $saveDirectory "$LoadSaveName.sav"
$sessionPath = Join-Path $documentsRoot 'AgentRuns\ChronicleAgent\session.json'
$agentHostDllPath = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'agenthost') 'bin\Release\net8.0\ChronicleAgentHost.dll'
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
    $output = & $HarnessPowerShell -NoProfile -File $cli $Action @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    return $output | ConvertFrom-Json
}

function Invoke-AgentHostProtocolRejectionProbe {
    if (-not (Test-Path -LiteralPath $agentHostDllPath -PathType Leaf)) { throw "Agent Host DLL not found: $agentHostDllPath" }
    if ([string]::IsNullOrWhiteSpace($env:CHRONICLE_HARNESS_TEMP) -or -not (Test-Path -LiteralPath $env:CHRONICLE_HARNESS_TEMP -PathType Container)) {
        throw 'Agent Host error-escaping probe requires the active Harness temp directory.'
    }
    $previousMode = $env:CHRONICLE_HARNESS_MODE
    $env:CHRONICLE_HARNESS_MODE = 'agent-host-protocol-test'
    try {
        $output = & dotnet $agentHostDllPath --protocol-rejection-test 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "Agent Host Native rejection/JSON escaping probe failed: $output" }
        $probe = $output | ConvertFrom-Json
        if (-not [bool]$probe.passed -or $probe.status -ne 'rejected' -or -not [bool]$probe.escapedControlCharactersParse -or -not [bool]$probe.campaignStateUnchanged) {
            throw 'Agent Host rejection response did not pass strict JSON parsing and no-mutation checks.'
        }
        return $probe
    }
    finally { $env:CHRONICLE_HARNESS_MODE = $previousMode }
}

function Invoke-AgentHostState {
    if (-not (Test-Path -LiteralPath $agentHostDllPath -PathType Leaf)) { throw "Agent Host DLL not found: $agentHostDllPath" }
    $output = & dotnet $agentHostDllPath --state-once --timeout-seconds $TimeoutSeconds 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Local Agent Host state request failed with exit code ${LASTEXITCODE}: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Local Agent Host returned invalid JSON: $output" }
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
    $agentHostRejectionProbe = Invoke-AgentHostProtocolRejectionProbe
    $campaignBeforeHost = Get-PersistedCampaignFingerprint $state
    $hostStateCalls = @()
    for ($hostCall = 1; $hostCall -le 3; $hostCall++) {
        $hostState = Invoke-AgentHostState
        $hostStateCalls += [ordered]@{
            commandId = [string]$hostState.commandId
            bannerlordProcessId = [int]$hostState.bannerlordProcessId
            mainHeroId = [string]$hostState.mainHeroId
            playerClanId = [string]$hostState.playerClanId
            mainPartyId = [string]$hostState.mainPartyId
            gameState = [string]$hostState.gameState
            timeControlMode = [string]$hostState.timeControlMode
        }
        if ([int]$hostState.bannerlordProcessId -ne [int]$state.processId -or
            [string]$hostState.mainHeroId -cne [string]$state.state.identity.heroId -or
            [string]$hostState.playerClanId -cne [string]$state.state.identity.clanId -or
            [string]$hostState.mainPartyId -cne [string]$state.state.party.id -or
            [string]$hostState.timeControlMode -cne [string]$state.timeControlMode) {
            throw "Agent Host read did not match the active Native Campaign state on repetition $hostCall."
        }
    }
    $stateAfterHost = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-state-after-host", '-TimeoutSeconds', $TimeoutSeconds)
    $campaignAfterHost = Get-PersistedCampaignFingerprint $stateAfterHost
    $hostObservationsDidNotMutateCampaign = (
        ($campaignBeforeHost | ConvertTo-Json -Depth 6 -Compress) -ceq
        ($campaignAfterHost | ConvertTo-Json -Depth 6 -Compress)
    )
    if (-not $hostObservationsDidNotMutateCampaign) { throw 'Read-only Agent Host handshakes changed the Native Campaign fingerprint.' }
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
        AgentHostNativeRejectionEscapeProbe = [ordered]@{
            Passed = [bool]$agentHostRejectionProbe.passed
            Status = [string]$agentHostRejectionProbe.status
            ErrorType = [string]$agentHostRejectionProbe.errorType
            ControlCharactersEscaped = [bool]$agentHostRejectionProbe.escapedControlCharactersParse
            CampaignStateUnchanged = [bool]$agentHostRejectionProbe.campaignStateUnchanged
        }
        AgentHostStateCalls = $hostStateCalls
        AgentHostObservationsDidNotMutateCampaign = $hostObservationsDidNotMutateCampaign
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
        [bool]$agentHostRejectionProbe.passed -and
        $hostStateCalls.Count -eq 3 -and
        $hostObservationsDidNotMutateCampaign -and
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
