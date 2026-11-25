#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180,
    [int]$JoinWaitSeconds = 60
)

$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$tempPath = $env:CHRONICLE_HARNESS_TEMP
$runDirectory = if ($tempPath) { Split-Path -Parent $tempPath } else { Join-Path $PSScriptRoot 'TestResults\ManualJoinEncounterAbandonArmy' }
$frameRoot = if ($tempPath) { $tempPath } else { $runDirectory }
$resultPath = if ($tempPath) { Join-Path $tempPath 'JoinEncounterAbandonArmyResult.json' } else { Join-Path $runDirectory 'JoinEncounterAbandonArmyResult.json' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$prefix = 'join-encounter-abandon-army-' + (Get-Date -Format 'yyyyMMddHHmmssfff')
$currentStep = 'preflight'

if (-not (Test-Path -LiteralPath $savePath)) { throw "Join Encounter fixture not found: $LoadSaveName" }
if (Get-Process -Name Bannerlord -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
. (Join-Path $PSScriptRoot 'Test-AgentSupport.ps1')

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $output = & $HarnessPowerShell -NoProfile -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

function Capture-EngineFrame([string]$Path, [string]$Suffix) {
    $receipt = Invoke-AgentCli 'captureFrame' @('-OutputPath', $Path, '-CommandId', "$prefix-$Suffix") 30
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path -LiteralPath $Path) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
    $exists = Test-Path -LiteralPath $Path
    $length = if ($exists) { (Get-Item -LiteralPath $Path).Length } else { 0 }
    if ($receipt.status -ne 'completed' -or -not $exists -or $length -lt 4096)
        { throw "Native Join Encounter frame '$Path' was not captured (receipt='$($receipt.status)', exists=$exists, bytes=$length)." }
}

try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $currentStep = 'load-disposable-campaign'
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $initial = Invoke-AgentCli 'state' @('-CommandId', "$prefix-initial")
    if ($initial.state.context.gameState -ne 'MapState' -or $initial.state.context.encounterActive -or $initial.state.context.captivity)
        { throw 'Fixture must start as a free Campaign Map party with no active Encounter.' }

    $currentStep = 'seed-native-npc-battle'
    $fixture = Invoke-AgentCli 'harnessSeedNpcBattleForPlayerJoin' @('-RelationProfile', 'HelpDefenders', '-CommandId', "$prefix-native-npc-battle") 30
    if ($fixture.status -ne 'completed' -or -not [bool]$fixture.data.nativeNpcMapEventCreated -or [bool]$fixture.data.mainPartyJoined -or [bool]$fixture.data.battleHasWinner)
        { throw "Native NPC MapEvent fixture was not established: $($fixture.data | ConvertTo-Json -Compress)" }

    $currentStep = 'observe-visible-battle-party-and-native-approach'
    $targets = Invoke-AgentCli 'mapPartyTargets' @('-CommandId', "$prefix-native-party-targets") 30
    if ($targets.status -ne 'completed') { throw 'Current Native Map Party target observation failed.' }
    $targetPartyId = [string]$fixture.data.defenderPartyId
    $defenderTarget = @($targets.data.mapPartyTargets | Where-Object { $_.id -eq $targetPartyId } | Select-Object -First 1)
    if ($defenderTarget.Count -ne 1) { throw "Native visible Party target list did not include the NPC battle defender '$targetPartyId'." }
    $approach = Invoke-AgentCli 'pursue' @('-PartyId', $targetPartyId, '-CommandId', "$prefix-native-pursue-visible-defender") 30
    if ($approach.status -ne 'completed' -or $approach.state.location.targetPartyId -ne $targetPartyId -or $approach.timeControlMode -ne 'StoppablePlay')
        { throw 'Native pursuit of the currently visible battle defender did not start under ordinary StoppablePlay mode.' }

    $currentStep = 'observe-native-join-encounter-page'
    $deadline = [DateTime]::UtcNow.AddSeconds($JoinWaitSeconds)
    $joinMenu = $null
    $timeouts = 0
    while ([DateTime]::UtcNow -lt $deadline) {
        try { $state = Invoke-AgentCli 'state' @('-CommandId', "$prefix-join-poll-$([Guid]::NewGuid().ToString('N'))") 8; $timeouts = 0 }
        catch {
            if ($_.Exception.Message -notmatch 'timed out after') { throw }
            $timeouts++
            if ($timeouts -ge 3) { throw 'Game stopped answering while waiting for Native Join Encounter.' }
            if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'Bannerlord exited before the Join Encounter page appeared.' }
            continue
        }
        if ($state.state.context.menuId -eq 'join_encounter' -and [bool]$state.state.context.encounterActive) { $joinMenu = $state; break }
        if ($state.state.context.captivity) { throw 'MainHero was captured before the Join Encounter options were observed.' }
        if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'Bannerlord exited before the Join Encounter page appeared.' }
        Start-Sleep -Milliseconds 200
    }
    if (-not $joinMenu) { throw "Native join_encounter was not observed in time. LastContext=$($state.state.context | ConvertTo-Json -Depth 6 -Compress)" }

    $currentStep = 'prepare-native-army-member-and-refresh-current-native-menu'
    $armyFixture = Invoke-AgentCli 'harnessPrepareArmyMemberForCurrentJoinEncounter' @('-CommandId', "$prefix-native-army-member-on-join-page") 30
    if ($armyFixture.status -ne 'completed' -or -not [bool]$armyFixture.data.nativeArmyMembershipPrepared -or $armyFixture.data.eventId -ne $fixture.data.eventId)
        { throw "Native Army membership could not be safely prepared while staying in the current Join Encounter: $($armyFixture.data | ConvertTo-Json -Compress)" }
    $joinMenu = Invoke-AgentCli 'state' @('-CommandId', "$prefix-refreshed-join-menu")
    if ($joinMenu.state.context.menuId -ne 'join_encounter' -or -not [bool]$joinMenu.state.context.encounterActive)
        { throw "Native Join Encounter did not remain active after Native Army membership preparation: $($joinMenu.state.context | ConvertTo-Json -Depth 5 -Compress)" }

    $enabledOptions = @($joinMenu.state.availableMenuOptions | Where-Object { $_.available -and $_.enabled })
    $abandonOption = @($enabledOptions | Where-Object { $_.id -eq 'join_encounter_abandon' } | Select-Object -First 1)
    $helpDefendersOption = @($enabledOptions | Where-Object { $_.id -eq 'join_encounter_help_defenders' } | Select-Object -First 1)
    $ordinaryLeaveOption = @($enabledOptions | Where-Object { $_.id -eq 'join_encounter_leave' } | Select-Object -First 1)
    if ($abandonOption.Count -ne 1 -or $helpDefendersOption.Count -ne 1 -or $ordinaryLeaveOption.Count -ne 0 -or $enabledOptions.Count -ne 2) {
        throw "Native non-leader Army member should see only Help Defenders and Abandon Army (the ordinary Don't get involved option is gated off). Enabled=$(($enabledOptions | ForEach-Object id) -join ',')"
    }

    $armyLeaderPartyId = [string]$armyFixture.data.armyLeaderPartyId
    $currentStep = 'cross-check-native-map-event-army-and-resources-before-abandon'
    $before = Invoke-AgentCli 'harnessJoinEncounterDiagnostics' @('-PartyId', $targetPartyId, '-AttachedPartyId', $armyLeaderPartyId, '-CommandId', "$prefix-before-abandon-diagnostics") 30
    if ($before.status -ne 'completed') { throw 'Native MapEvent/Army diagnostics were not available before abandonment.' }
    $pre = $before.data
    if ($pre.eventId -ne $fixture.data.eventId -or [bool]$pre.battleHasWinner -or [bool]$pre.mainPartyOnAttackerSide -or [bool]$pre.mainPartyOnDefenderSide -or
        -not [bool]$pre.mainPartyArmyMember -or -not [bool]$pre.mainPartyArmyContainsPlayer)
        { throw "Before-state failed to prove same NPC event and MainParty as a non-leader Army member: $($pre | ConvertTo-Json -Compress)" }

    $beforeFrame = Join-Path $frameRoot 'join-encounter-abandon-army-before.bmp'
    $afterFrame = Join-Path $frameRoot 'join-encounter-abandon-army-after.bmp'
    Capture-EngineFrame $beforeFrame 'abandon-army-join-page'

    $currentStep = 'select-native-abandon-army-menu-option'
    $leaveReceipt = Invoke-AgentCli 'menuSelect' @('-MenuId', 'join_encounter', '-OptionId', 'join_encounter_abandon', '-CommandId', "$prefix-abandon-army") 30
    if ($leaveReceipt.status -ne 'completed') { throw "Native Abandon Army option was rejected: $($leaveReceipt.error)" }

    $currentStep = 'observe-native-encounter-finish-and-party-army-state'
    $after = $null
    $afterDeadline = [DateTime]::UtcNow.AddSeconds(20)
    while ([DateTime]::UtcNow -lt $afterDeadline) {
        $after = Invoke-AgentCli 'state' @('-CommandId', "$prefix-after-abandon-state-$([Guid]::NewGuid().ToString('N'))") 8
        if (-not [bool]$after.state.context.encounterActive) { break }
        if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'Bannerlord exited while processing Native Abandon Army.' }
        Start-Sleep -Milliseconds 150
    }
    if ($after.state.context.encounterActive) { throw "Native Abandon Army did not finish PlayerEncounter: $($after.state.context | ConvertTo-Json -Depth 6 -Compress)" }
    Capture-EngineFrame $afterFrame 'abandon-army-after-finish'
    $afterDiagnostics = Invoke-AgentCli 'harnessJoinEncounterDiagnostics' @('-PartyId', $targetPartyId, '-AttachedPartyId', $armyLeaderPartyId, '-CommandId', "$prefix-after-abandon-diagnostics") 30
    if ($afterDiagnostics.status -ne 'completed') { throw 'Native post-abandon Event/Army diagnostics were unavailable.' }
    $post = $afterDiagnostics.data
    $sameEvent = $pre.eventId -eq $post.eventId
    $detachedFromArmy = (-not [bool]$post.mainPartyArmyMember -and -not [bool]$post.mainPartyArmyContainsPlayer -and [string]::IsNullOrWhiteSpace([string]$post.mainPartyAttachedToPartyId))
    $holdRestored = ($after.state.party.defaultBehavior -eq 'Hold' -or $after.state.party.moveMode -eq 'Hold')
    $resourcesAndRelationsUnchanged = ([int]$pre.gold -eq [int]$post.gold -and [Math]::Abs([double]$pre.playerClanInfluence - [double]$post.playerClanInfluence) -lt 0.001 -and
        [Math]::Abs([double]$pre.armyLeaderClanInfluence - [double]$post.armyLeaderClanInfluence) -lt 0.001 -and
        [bool]$pre.playerAtWarWithAttacker -eq [bool]$post.playerAtWarWithAttacker -and [bool]$pre.playerAtWarWithDefender -eq [bool]$post.playerAtWarWithDefender)
    $clockAndLocationRecorded = ([string]::IsNullOrWhiteSpace([string]$post.timeControlMode) -eq $false -and $null -ne $post.campaignDay -and $null -ne $after.state.location)

    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-stop") 30
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $processesStopped = -not [bool](Get-Process -Name Bannerlord -ErrorAction SilentlyContinue)
    $result = [ordered]@{
        ProviderKind = 'Native JoinEncounter Abandon Army option and consequence from a disposable Native Kingdom Army membership'
        ProcessId = $start.session.processId
        NpcBattleFixture = $fixture.data
        ArmyFixture = $armyFixture.data
        NativePlayerApproach = $approach
        NativeJoinMenu = [ordered]@{ menuId = $joinMenu.state.context.menuId; context = $joinMenu.state.context; enabledOptions = @($enabledOptions | ForEach-Object { [ordered]@{ id = $_.id; text = $_.text } }) }
        OrdinaryLeaveOptionHiddenForArmyMember = ($ordinaryLeaveOption.Count -eq 0)
        NativeAbandonReceipt = $leaveReceipt
        Before = $pre
        After = $post
        AfterState = [ordered]@{ context = $after.state.context; location = $after.state.location; party = $after.state.party; campaignDay = $after.campaignDay; timeControlMode = $after.timeControlMode }
        SameMapEventAfterAbandon = $sameEvent
        MainPartyDetachedFromArmy = $detachedFromArmy
        NativeHoldAfterAbandon = $holdRestored
        ResourcesAndFactionRelationsUnchanged = $resourcesAndRelationsUnchanged
        CampaignClockAndLocationRecorded = $clockAndLocationRecorded
        EngineFrames = @($beforeFrame, $afterFrame)
        SourceFixtureHashBefore = $fixtureHashBefore
        SourceFixtureHashAfter = $fixtureHashAfter
        SourceFixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = [bool]$stop.processStopped
        AllGameProcessesStopped = $processesStopped
        Passed = ($sameEvent -and $detachedFromArmy -and $holdRestored -and $resourcesAndRelationsUnchanged -and $clockAndLocationRecorded -and
            $fixtureHashBefore -eq $fixtureHashAfter -and [bool]$stop.processStopped -and $processesStopped)
    }
    $json = $result | ConvertTo-Json -Depth 16
    if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) { Set-Content -LiteralPath $resultPath -Value $json -Encoding UTF8 }
    $json
    if (-not $result.Passed) { exit 1 }
}
catch {
    $failureFrame = Capture-HarnessFailureFrame -CliPath $cli -CommandPrefix $prefix -FailedStep $currentStep -FailureReason $_.Exception.ToString()
    if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) {
        [ordered]@{ FailedStep = $currentStep; Exception = $_.Exception.ToString(); FailureFrame = $failureFrame; TimestampUtc = [DateTime]::UtcNow.ToString('O') } |
            ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $tempPath 'JoinEncounterAbandonArmyFailure.json') -Encoding UTF8
    }
    throw
}
finally {
    if (Test-Path $sessionPath) {
        try {
            $session = Get-Content $sessionPath -Raw | ConvertFrom-Json
            if ($session.status -ne 'stopped') { $null = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-final-stop") 30 }
        }
        catch { }
    }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
