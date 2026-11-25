#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180,
    [int]$ArmyEncounterWaitSeconds = 90
)

$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$tempPath = $env:CHRONICLE_HARNESS_TEMP
$runDirectory = if ($tempPath) { Split-Path -Parent $tempPath } else { Join-Path $PSScriptRoot 'TestResults\ManualMovingArmyJoin' }
$frameRoot = if ($tempPath) { $tempPath } else { $runDirectory }
$resultPath = if ($tempPath) { Join-Path $tempPath 'MovingArmyJoinResult.json' } else { Join-Path $runDirectory 'MovingArmyJoinResult.json' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$prefix = 'moving-army-join-' + (Get-Date -Format 'yyyyMMddHHmmssfff')
$currentStep = 'preflight'

if (-not (Test-Path -LiteralPath $savePath)) { throw "Moving Army join fixture not found: $LoadSaveName" }
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
        { throw "Native Army encounter frame '$Path' was not captured (receipt='$($receipt.status)', exists=$exists, bytes=$length)." }
}

try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $currentStep = 'load-disposable-campaign'
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $initial = Invoke-AgentCli 'state' @('-CommandId', "$prefix-initial")
    if ($initial.state.context.gameState -ne 'MapState' -or $initial.state.context.encounterActive -or $initial.state.context.captivity)
        { throw 'Fixture must start as a free Campaign Map party with no active Encounter.' }

    $currentStep = 'observe-visible-inspected-independent-LordParty'
    $targets = Invoke-AgentCli 'mapPartyTargets' @('-CommandId', "$prefix-party-targets") 30
    if ($targets.status -ne 'completed') { throw 'Current Native mapPartyTargets query failed.' }
    $candidate = @($targets.data.mapPartyTargets | Where-Object { $_.type -eq 'lord' -and $_.isInspected -and -not $_.hostile -and -not $_.isArmyLeader } | Select-Object -First 1)
    if ($candidate.Count -ne 1) { throw 'No current inspected, non-hostile, independent LordParty candidate was available for the moving Army fixture.' }
    $armyLeaderPartyId = [string]$candidate[0].id

    $currentStep = 'prepare-native-moving-army-fixture'
    $fixture = Invoke-AgentCli 'harnessPrepareMovingArmyEncounter' @('-PartyId', $armyLeaderPartyId, '-CommandId', "$prefix-native-moving-army") 30
    if ($fixture.status -ne 'completed' -or -not [bool]$fixture.data.nativeMovingArmyFixtureCreated -or
        [bool]$fixture.data.leaderMapEventActive -or [bool]$fixture.data.leaderSiegeEventActive)
        { throw "The visible LordParty did not become a free Native Army Leader outside battle/siege: $($fixture.data | ConvertTo-Json -Compress)" }

    $currentStep = 'observe-current-ArmyLeader-marker'
    $armyTargets = Invoke-AgentCli 'mapPartyTargets' @('-CommandId', "$prefix-army-leader-target") 30
    $leaderTarget = @($armyTargets.data.mapPartyTargets | Where-Object { $_.id -eq $armyLeaderPartyId -and $_.isArmyLeader } | Select-Object -First 1)
    if ($armyTargets.status -ne 'completed' -or $leaderTarget.Count -ne 1)
        { throw "Native visible map targets did not expose the created Army leader '$armyLeaderPartyId'." }

    $currentStep = 'approach-visible-nonengaged-ArmyLeader-through-native-map-party-action'
    $approach = Invoke-AgentCli 'pursue' @('-PartyId', $armyLeaderPartyId, '-CommandId', "$prefix-pursue-moving-army") 30
    if ($approach.status -ne 'completed' -or $approach.state.location.targetPartyId -ne $armyLeaderPartyId -or $approach.timeControlMode -ne 'StoppablePlay')
        { throw 'The Native map approach to the current visible Army leader did not start under StoppablePlay.' }

    $currentStep = 'observe-native-unengaged-Army-interaction'
    $deadline = [DateTime]::UtcNow.AddSeconds($ArmyEncounterWaitSeconds)
    $armyMenu = $null
    $state = $null
    $timeouts = 0
    while ([DateTime]::UtcNow -lt $deadline) {
        try { $state = Invoke-AgentCli 'state' @('-CommandId', "$prefix-army-menu-poll-$([Guid]::NewGuid().ToString('N'))") 8; $timeouts = 0 }
        catch {
            if ($_.Exception.Message -notmatch 'timed out after') { throw }
            $timeouts++
            if ($timeouts -ge 3) { throw 'Game stopped answering while waiting for Native Army encounter.' }
            if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'Bannerlord exited before Native Army encounter was observed.' }
            continue
        }
        if ($state.state.context.menuId -eq 'army_encounter' -and [bool]$state.state.context.encounterActive) { $armyMenu = $state; break }
        if ($state.state.context.menuId -in @('join_encounter','encounter','army_encounter') -and [bool]$state.state.context.encounterActive)
            { throw "Native approach entered '$($state.state.context.menuId)' instead of the expected unengaged-army interaction. This is distinct from battle help/join." }
        if ($state.state.context.captivity) { throw 'MainHero entered Captivity before the Native Army encounter menu.' }
        if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'Bannerlord exited before the Native Army encounter menu.' }
        Start-Sleep -Milliseconds 200
    }
    if (-not $armyMenu) { throw "Native army_encounter menu was not observed within $ArmyEncounterWaitSeconds seconds. LastContext=$($state.state.context | ConvertTo-Json -Depth 6 -Compress)" }

    $currentStep = 'inspect-native-army-encounter-options-and-prerequisites'
    $options = @($armyMenu.state.availableMenuOptions | Where-Object { $_.available -and $_.enabled })
    $joinArmyOption = @($options | Where-Object { $_.id -eq 'army_join_army' } | Select-Object -First 1)
    $beforeDiag = Invoke-AgentCli 'harnessArmyEncounterDiagnostics' @('-PartyId', $armyLeaderPartyId, '-CommandId', "$prefix-before-join-diagnostics") 30
    if ($beforeDiag.status -ne 'completed') { throw 'Native Army membership/encounter diagnostics unavailable before joining.' }
    $pre = $beforeDiag.data
    if ($joinArmyOption.Count -ne 1 -or [bool]$pre.mainPartyArmyMember -or [bool]$pre.mainPartyAttachedToLeader -or
        $pre.playerMapFactionId -ne $pre.armyKingdomId -or [bool]$pre.armyLeaderMapEventActive -or [bool]$pre.armyLeaderSiegeEventActive)
        { throw "army_join was not enabled with a nonmember, same-faction MainParty and an unengaged target Army. Options=$(($options | ForEach-Object id) -join ','); Diagnostics=$($pre | ConvertTo-Json -Compress)" }
    $beforeFrame = Join-Path $frameRoot 'moving-army-join-before.bmp'
    $afterFrame = Join-Path $frameRoot 'moving-army-join-after.bmp'
    Capture-EngineFrame $beforeFrame 'moving-army-join-page'

    $currentStep = 'select-current-native-army_join-option'
    $joinReceipt = Invoke-AgentCli 'menuSelect' @('-MenuId', 'army_encounter', '-OptionId', 'army_join_army', '-CommandId', "$prefix-join-army") 30
    if ($joinReceipt.status -ne 'completed') { throw "Native Join Army option was rejected: $($joinReceipt.error)" }

    $currentStep = 'verify-native-Army-membership-and-encounter-close'
    $after = $null
    $afterDeadline = [DateTime]::UtcNow.AddSeconds(20)
    while ([DateTime]::UtcNow -lt $afterDeadline) {
        $after = Invoke-AgentCli 'state' @('-CommandId', "$prefix-after-join-state-$([Guid]::NewGuid().ToString('N'))") 8
        if (-not [bool]$after.state.context.encounterActive) { break }
        if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'Bannerlord exited while completing Native Army join.' }
        Start-Sleep -Milliseconds 150
    }
    if ([bool]$after.state.context.encounterActive) { throw "Native Join Army did not close PlayerEncounter: $($after.state.context | ConvertTo-Json -Depth 5 -Compress)" }
    Capture-EngineFrame $afterFrame 'moving-army-join-after-menu'
    $afterDiag = Invoke-AgentCli 'harnessArmyEncounterDiagnostics' @('-PartyId', $armyLeaderPartyId, '-CommandId', "$prefix-after-join-diagnostics") 30
    if ($afterDiag.status -ne 'completed') { throw 'Native Army membership diagnostics unavailable after Join Army.' }
    $post = $afterDiag.data
    $joinedExpectedArmy = ([bool]$post.mainPartyArmyMember -and [bool]$post.mainPartyAttachedToLeader -and $post.playerMapFactionId -eq $post.armyKingdomId)
    $mapEncounterFinished = (-not [bool]$post.playerEncounterActive -and $after.state.context.gameState -eq 'MapState')
    $resourceChangesRecorded = ($null -ne $pre.gold -and $null -ne $post.gold -and $null -ne $pre.playerClanInfluence -and $null -ne $post.playerClanInfluence -and
        $null -ne $pre.armyLeaderClanInfluence -and $null -ne $post.armyLeaderClanInfluence)
    $joinActionDidNotSetClock = ([string]$pre.timeControlMode -eq 'Stop' -and [string]$joinReceipt.timeControlMode -eq 'Stop' -and
        [Math]::Abs([double]$joinReceipt.campaignDay - [double]$pre.campaignDay) -lt 0.001)
    $nativeArmyWaitMenuEntered = ($after.state.context.menuId -eq 'army_wait' -and [string]$after.state.context.timeControlMode -eq 'UnstoppableFastForward')
    $armyWaitNaturallyAdvanced = ([double]$post.campaignDay -gt [double]$joinReceipt.campaignDay)

    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-stop") 30
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $processesStopped = -not [bool](Get-Process -Name Bannerlord -ErrorAction SilentlyContinue)
    $result = [ordered]@{
        ProviderKind = 'Native army_encounter on a non-engaged travelling Army; submit army_join_army through the current Native menu'
        ProcessId = $start.session.processId
        ArmyFixture = $fixture.data
        NativeVisibleArmyTarget = $leaderTarget[0]
        NativeApproach = $approach
        NativeArmyEncounterMenu = [ordered]@{ menuId = $armyMenu.state.context.menuId; context = $armyMenu.state.context; enabledOptions = @($options | ForEach-Object { [ordered]@{ id = $_.id; text = $_.text } }) }
        NativeJoinReceipt = $joinReceipt
        Before = $pre
        After = $post
        AfterState = [ordered]@{ context = $after.state.context; location = $after.state.location; party = $after.state.party; campaignDay = $after.campaignDay; timeControlMode = $after.timeControlMode }
        JoinedExpectedArmy = $joinedExpectedArmy
        PlayerEncounterClosed = $mapEncounterFinished
        ResourceAndInfluenceChangesRecorded = $resourceChangesRecorded
        JoinActionDidNotWriteClockControl = $joinActionDidNotSetClock
        NativeArmyWaitMenuEntered = $nativeArmyWaitMenuEntered
        NativeArmyWaitNaturallyAdvancedCampaign = $armyWaitNaturallyAdvanced
        EngineFrames = @($beforeFrame, $afterFrame)
        SourceFixtureHashBefore = $fixtureHashBefore
        SourceFixtureHashAfter = $fixtureHashAfter
        SourceFixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = [bool]$stop.processStopped
        AllGameProcessesStopped = $processesStopped
        Passed = ($joinedExpectedArmy -and $mapEncounterFinished -and $resourceChangesRecorded -and $joinActionDidNotSetClock -and $nativeArmyWaitMenuEntered -and
            $armyWaitNaturallyAdvanced -and $fixtureHashBefore -eq $fixtureHashAfter -and [bool]$stop.processStopped -and $processesStopped)
    }
    $json = $result | ConvertTo-Json -Depth 16
    if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) { Set-Content -LiteralPath $resultPath -Value $json -Encoding UTF8 }
    $json
    if (-not $result.Passed) { exit 1 }
}
catch {
    $failureFrame = Capture-HarnessFailureFrame -CliPath $cli -CommandPrefix $prefix -FailedStep $currentStep -FailureReason $_.Exception.ToString()
    if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) {
        [ordered]@{ FailedStep = $currentStep; Exception = $_.Exception.ToString(); FailureFrame = $failureFrame; LastState = if ($state) { $state.state.context } else { $null }; Fixture = if ($fixture) { $fixture.data } else { $null }; TimestampUtc = [DateTime]::UtcNow.ToString('O') } |
            ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tempPath 'MovingArmyJoinFailure.json') -Encoding UTF8
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
