#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('HelpAttackers','Neutral')][string]$RelationProfile,
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
$runDirectory = if ($tempPath) { Split-Path -Parent $tempPath } else { Join-Path $PSScriptRoot 'TestResults\ManualJoinEncounterEligibility' }
$frameRoot = if ($tempPath) { $tempPath } else { $runDirectory }
$resultPath = if ($tempPath) { Join-Path $tempPath "JoinEncounterEligibility-$RelationProfile.json" } else { Join-Path $runDirectory "JoinEncounterEligibility-$RelationProfile.json" }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$prefix = "join-encounter-$($RelationProfile.ToLowerInvariant())-" + (Get-Date -Format 'yyyyMMddHHmmssfff')
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

    $currentStep = 'seed-native-npc-vs-npc-battle-with-relation-profile'
    $fixture = Invoke-AgentCli 'harnessSeedNpcBattleForPlayerJoin' @('-RelationProfile', $RelationProfile, '-CommandId', "$prefix-native-npc-battle") 30
    if ($fixture.status -ne 'completed' -or -not [bool]$fixture.data.nativeNpcMapEventCreated -or [bool]$fixture.data.mainPartyJoined -or [bool]$fixture.data.battleHasWinner)
        { throw "Harness did not create the expected continuing Native NPC MapEvent: $($fixture.data | ConvertTo-Json -Compress)" }

    $expectedCanJoinAttackers = $RelationProfile -eq 'HelpAttackers'
    if ([bool]$fixture.data.mainPartyCanJoinAttacker -ne $expectedCanJoinAttackers -or [bool]$fixture.data.mainPartyCanJoinDefender)
        { throw "Native MapEvent.CanPartyJoinBattle did not match the $RelationProfile relationship fixture: $($fixture.data | ConvertTo-Json -Compress)" }

    $currentStep = 'observe-native-visible-parties-and-approach-neutral-side-party'
    $targets = Invoke-AgentCli 'mapPartyTargets' @('-CommandId', "$prefix-native-party-targets") 30
    if ($targets.status -ne 'completed') { throw 'The current native visible Map Party target query failed.' }
    $targetPartyId = if ($RelationProfile -eq 'HelpAttackers') { [string]$fixture.data.attackerPartyId } else { [string]$fixture.data.defenderPartyId }
    $target = @($targets.data.mapPartyTargets | Where-Object { $_.id -eq $targetPartyId } | Select-Object -First 1)
    if ($target.Count -ne 1) { throw "Native MapPartyTargets did not list the relation-neutral battle party '$targetPartyId'." }
    $approach = Invoke-AgentCli 'pursue' @('-PartyId', $targetPartyId, '-CommandId', "$prefix-native-pursue-neutral-side") 30
    if ($approach.status -ne 'completed' -or $approach.state.location.targetPartyId -ne $targetPartyId -or $approach.timeControlMode -ne 'StoppablePlay')
        { throw 'Native pursuit of the currently visible neutral battle party did not start under ordinary StoppablePlay mode.' }

    $currentStep = 'observe-native-player-encounter-routing'
    $deadline = [DateTime]::UtcNow.AddSeconds($JoinWaitSeconds)
    $observed = $null
    $timeouts = 0
    while ([DateTime]::UtcNow -lt $deadline) {
        try { $observed = Invoke-AgentCli 'state' @('-CommandId', "$prefix-route-poll-$([Guid]::NewGuid().ToString('N'))") 8; $timeouts = 0 }
        catch {
            if ($_.Exception.Message -notmatch 'timed out after') { throw }
            $timeouts++
            if ($timeouts -ge 3) { throw 'Game stopped answering while waiting for Native Join Encounter routing.' }
            if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'Bannerlord exited before a Native Join Encounter result was observed.' }
            continue
        }
        if ($observed.state.context.encounterActive -or $observed.state.context.menuId -eq 'join_encounter') { break }
        if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'Bannerlord exited before a Native Join Encounter result was observed.' }
        Start-Sleep -Milliseconds 200
    }

    if (-not $observed) { throw 'No Native state was observed after approaching the ongoing battle.' }
    $currentStep = 'cross-check-current-native-map-event-and-side-eligibility'
    $beforeDiagnostics = Invoke-AgentCli 'harnessJoinEncounterDiagnostics' @('-PartyId', $targetPartyId, '-CommandId', "$prefix-current-join-diagnostics") 30
    if ($beforeDiagnostics.status -ne 'completed') { throw "Native MapEvent diagnostics unavailable after approach: $($observed.state.context | ConvertTo-Json -Compress)" }
    $pre = $beforeDiagnostics.data
    if ($pre.eventId -ne $fixture.data.eventId -or [bool]$pre.battleHasWinner -or [bool]$pre.mainPartyOnAttackerSide -or [bool]$pre.mainPartyOnDefenderSide)
        { throw "The NPC battle ended/changed or MainParty joined before the eligibility observation: $($pre | ConvertTo-Json -Compress)" }

    $enabledHelpOptions = @($observed.state.availableMenuOptions | Where-Object { $_.id -in @('join_encounter_help_attackers','join_encounter_help_defenders') -and $_.available -and $_.enabled })
    $framePath = Join-Path $frameRoot "join-encounter-eligibility-$($RelationProfile.ToLowerInvariant()).bmp"
    Capture-EngineFrame $framePath 'eligibility-route-frame'

    $joined = $false
    $joinReceipt = $null
    $post = $pre
    $menuOptions = @($observed.state.availableMenuOptions | Where-Object { $_.available -and $_.enabled } | ForEach-Object { [ordered]@{ id = $_.id; text = $_.text } })
    $joinMenuOptions = @($menuOptions)
    $postEncounterOptions = @()
    if ($RelationProfile -eq 'HelpAttackers') {
        if ($observed.state.context.menuId -ne 'join_encounter' -or $enabledHelpOptions.Count -ne 1 -or $enabledHelpOptions[0].id -ne 'join_encounter_help_attackers' -or
            $menuOptions.Count -ne 2 -or @($menuOptions.id | Where-Object { $_ -eq 'join_encounter_leave' }).Count -ne 1)
            { throw "Expected only Native Help Attackers plus decline; got menu=$($observed.state.context.menuId), enabled=$(($enabledHelpOptions.id) -join ','). Options=$(($menuOptions.id) -join ',')" }
        $currentStep = 'select-native-help-attackers-option'
        $joinReceipt = Invoke-AgentCli 'menuSelect' @('-MenuId', 'join_encounter', '-OptionId', 'join_encounter_help_attackers', '-CommandId', "$prefix-help-attackers") 30
        if ($joinReceipt.status -ne 'completed') { throw "Native Help Attackers option was rejected: $($joinReceipt.error)" }
        $currentStep = 'verify-native-attacker-side-after-join'
        $joinedState = $null
        $afterDeadline = [DateTime]::UtcNow.AddSeconds(20)
        while ([DateTime]::UtcNow -lt $afterDeadline) {
            $joinedState = Invoke-AgentCli 'state' @('-CommandId', "$prefix-joined-state-$([Guid]::NewGuid().ToString('N'))") 8
            if ($joinedState.state.context.encounterActive -and $joinedState.state.context.menuId -eq 'encounter') { break }
            if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'Bannerlord exited while completing Native Help Attackers.' }
            Start-Sleep -Milliseconds 150
        }
        if (-not $joinedState.state.context.encounterActive -or $joinedState.state.context.menuId -ne 'encounter')
            { throw "Native Help Attackers did not return to the active Encounter menu. LastContext=$($joinedState.state.context | ConvertTo-Json -Depth 6 -Compress)" }
        $afterFramePath = Join-Path $frameRoot 'join-encounter-eligibility-helpattackers-after.bmp'
        Capture-EngineFrame $afterFramePath 'help-attackers-after-join-frame'
        $afterDiagnostics = Invoke-AgentCli 'harnessJoinEncounterDiagnostics' @('-CommandId', "$prefix-after-join-diagnostics") 30
        if ($afterDiagnostics.status -ne 'completed') { throw 'Native post-join MapEvent diagnostics were unavailable.' }
        $post = $afterDiagnostics.data
        $joined = ($pre.eventId -eq $post.eventId -and [bool]$post.isJoinedBattle -and [bool]$post.mainPartyOnAttackerSide -and -not [bool]$post.mainPartyOnDefenderSide -and $post.playerSide -eq 'Attacker')
        if (-not $joined) { throw "Native Help Attackers did not add MainParty to this MapEvent's AttackerSide: $($post | ConvertTo-Json -Compress)" }
        $postEncounterOptions = @($joinedState.state.availableMenuOptions | Where-Object { $_.available -and $_.enabled } | ForEach-Object { [ordered]@{ id = $_.id; text = $_.text } })
    }
    else {
        if ($enabledHelpOptions.Count -gt 0 -or $menuOptions.Count -ne 1 -or $menuOptions[0].id -ne 'join_encounter_leave')
            { throw "Both-neutral MainParty should only see Don't join; got $(($menuOptions.id) -join ',')" }
    }

    $worldAndClockStable = ([int]$pre.gold -eq [int]$post.gold -and [int]$pre.mainPartyMemberCount -eq [int]$post.mainPartyMemberCount -and
        [Math]::Abs([double]$pre.campaignDay - [double]$post.campaignDay) -lt 0.00001 -and [string]$pre.timeControlMode -eq [string]$post.timeControlMode)
    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-stop") 30
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $processesStopped = -not [bool](Get-Process -Name Bannerlord -ErrorAction SilentlyContinue)
    $hasNativeVisualBoundary = if ($RelationProfile -eq 'Neutral') { $enabledHelpOptions.Count -eq 0 } else { $enabledHelpOptions.Count -eq 1 }
    $result = [ordered]@{
        ProviderKind = 'Native NPC MapEvent relationship filtering; Help Attackers joined through the visible Native option, both-neutral never submits a join action'
        RelationProfile = $RelationProfile
        ProcessId = $start.session.processId
        NpcBattleFixture = $fixture.data
        NativePlayerApproach = $approach
        ObservedRoutingState = [ordered]@{ menuId = $observed.state.context.menuId; context = $observed.state.context; enabledOptions = $joinMenuOptions }
        PostJoinEncounterOptions = $postEncounterOptions
        JoinReceipt = $joinReceipt
        Before = $pre
        After = $post
        MainPartyJoinedExpectedSide = $joined
        BothNeutralHasNoEnabledHelp = ($RelationProfile -ne 'Neutral' -or $enabledHelpOptions.Count -eq 0)
        WorldAndClockStableAcrossJoinDecision = $worldAndClockStable
        NoBattleSimulationStarted = (-not [bool]$post.battleSimulationExists)
        EngineFrames = if ($RelationProfile -eq 'HelpAttackers') { @($framePath, $afterFramePath) } else { @($framePath) }
        SourceFixtureHashBefore = $fixtureHashBefore
        SourceFixtureHashAfter = $fixtureHashAfter
        SourceFixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = [bool]$stop.processStopped
        AllGameProcessesStopped = $processesStopped
        Passed = ($hasNativeVisualBoundary -and $joined -eq ($RelationProfile -eq 'HelpAttackers') -and $worldAndClockStable -and -not [bool]$post.battleSimulationExists -and $fixtureHashBefore -eq $fixtureHashAfter -and [bool]$stop.processStopped -and $processesStopped)
    }
    $json = $result | ConvertTo-Json -Depth 16
    if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) { Set-Content -LiteralPath $resultPath -Value $json -Encoding UTF8 }
    $json
    if (-not $result.Passed) { exit 1 }
}
catch {
    $failureFrame = Capture-HarnessFailureFrame -CliPath $cli -CommandPrefix $prefix -FailedStep $currentStep -FailureReason $_.Exception.ToString()
    if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) {
        [ordered]@{ RelationProfile = $RelationProfile; FailedStep = $currentStep; Exception = $_.Exception.ToString(); FailureFrame = $failureFrame; TimestampUtc = [DateTime]::UtcNow.ToString('O') } |
            ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $tempPath "JoinEncounterEligibility-$RelationProfile-Failure.json") -Encoding UTF8
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
