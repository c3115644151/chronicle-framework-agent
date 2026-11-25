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
$runDirectory = if ($tempPath) { Split-Path -Parent $tempPath } else { Join-Path (Split-Path -Parent $PSScriptRoot) 'TestResults\ManualJoinEncounterDefenders' }
$frameRoot = if ($tempPath) { $tempPath } else { $runDirectory }
$resultPath = if ($tempPath) { Join-Path $tempPath 'JoinEncounterDefendersResult.json' } else { Join-Path $runDirectory 'JoinEncounterDefendersResult.json' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$prefix = 'join-encounter-defenders-' + (Get-Date -Format 'yyyyMMddHHmmssfff')
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

    $currentStep = 'seed-native-npc-vs-npc-battle'
    $fixture = Invoke-AgentCli 'harnessSeedNpcBattleForPlayerJoin' @('-CommandId', "$prefix-native-npc-battle") 30
    if ($fixture.status -ne 'completed' -or -not [bool]$fixture.data.nativeNpcMapEventCreated -or [bool]$fixture.data.mainPartyJoined -or [bool]$fixture.data.battleHasWinner)
        { throw "Harness did not create the expected continuing Native NPC MapEvent: $($fixture.data | ConvertTo-Json -Compress)" }

    $currentStep = 'observe-native-visible-parties-and-approach-map-event-party'
    $targets = Invoke-AgentCli 'mapPartyTargets' @('-CommandId', "$prefix-native-party-targets") 30
    if ($targets.status -ne 'completed') { throw 'The current native visible Map Party target query failed.' }
    $defenderTarget = @($targets.data.mapPartyTargets | Where-Object { $_.id -eq $fixture.data.defenderPartyId } | Select-Object -First 1)
    if ($defenderTarget.Count -ne 1) { throw "Native MapPartyTargets did not list the active NPC battle's visible defender party '$($fixture.data.defenderPartyId)'." }
    $approach = Invoke-AgentCli 'pursue' @('-PartyId', [string]$defenderTarget[0].id, '-CommandId', "$prefix-native-pursue-visible-defender") 30
    if ($approach.status -ne 'completed' -or $approach.state.location.targetPartyId -ne $fixture.data.defenderPartyId -or $approach.timeControlMode -ne 'StoppablePlay')
        { throw 'Native pursuit of the currently visible battle defender did not start under ordinary StoppablePlay mode.' }

    $currentStep = 'wait-for-native-join-encounter-menu'
    $deadline = [DateTime]::UtcNow.AddSeconds($JoinWaitSeconds)
    $joinMenu = $null
    $timeouts = 0
    while ([DateTime]::UtcNow -lt $deadline) {
        try { $state = Invoke-AgentCli 'state' @('-CommandId', "$prefix-join-poll-$([Guid]::NewGuid().ToString('N'))") 8; $timeouts = 0 }
        catch {
            if ($_.Exception.Message -notmatch 'timed out after') { throw }
            $timeouts++
            if ($timeouts -ge 3) { throw 'Game stopped answering while waiting for the Native Join Encounter menu.' }
            if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'Bannerlord exited before the Native Join Encounter menu appeared.' }
            continue
        }
        if ($state.state.context.menuId -eq 'join_encounter' -and [bool]$state.state.context.encounterActive) { $joinMenu = $state; break }
        if ($state.state.context.captivity) { throw 'MainHero was captured before the Join Encounter choice was observed.' }
        if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'Bannerlord exited before the Join Encounter menu appeared.' }
        Start-Sleep -Milliseconds 200
    }
    if (-not $joinMenu) { throw "The Player did not reach the Native join_encounter menu in time. LastContext=$($state.state.context | ConvertTo-Json -Depth 6 -Compress)" }

    $helpDefendersOption = @($joinMenu.state.availableMenuOptions | Where-Object { $_.id -eq 'join_encounter_help_defenders' -and $_.available -and $_.enabled } | Select-Object -First 1)
    if ($helpDefendersOption.Count -ne 1)
        { throw "Native join_encounter menu did not expose enabled Help Defenders. Options=$(($joinMenu.state.availableMenuOptions | ForEach-Object { "$($_.id):$($_.available):$($_.enabled)" }) -join ',')" }
    $beforeDiagnostics = Invoke-AgentCli 'harnessJoinEncounterDiagnostics' @('-CommandId', "$prefix-before-join-diagnostics") 30
    if ($beforeDiagnostics.status -ne 'completed' -or [bool]$beforeDiagnostics.data.mainPartyOnAttackerSide -or [bool]$beforeDiagnostics.data.mainPartyOnDefenderSide)
        { throw 'MainParty was already present on an event side before the observed Join Encounter option.' }

    $beforeFrame = Join-Path $frameRoot 'join-encounter-defenders-before.bmp'
    $afterFrame = Join-Path $frameRoot 'join-encounter-defenders-after.bmp'
    Capture-EngineFrame $beforeFrame 'join-menu-frame'

    $currentStep = 'select-current-native-help-defenders-option'
    $joinReceipt = Invoke-AgentCli 'menuSelect' @('-MenuId', 'join_encounter', '-OptionId', 'join_encounter_help_defenders', '-CommandId', "$prefix-help-defenders") 30
    if ($joinReceipt.status -ne 'completed') { throw "Native Help Defenders option was rejected: $($joinReceipt.error)" }

    $currentStep = 'observe-native-map-event-side-after-join'
    $after = $null
    $afterDeadline = [DateTime]::UtcNow.AddSeconds(20)
    while ([DateTime]::UtcNow -lt $afterDeadline) {
        $after = Invoke-AgentCli 'state' @('-CommandId', "$prefix-joined-state-$([Guid]::NewGuid().ToString('N'))") 8
        if ($after.state.context.encounterActive -and $after.state.context.menuId -eq 'encounter') { break }
        if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'Bannerlord exited while completing Native join.' }
        Start-Sleep -Milliseconds 150
    }
    if (-not $after.state.context.encounterActive -or $after.state.context.menuId -ne 'encounter')
        { throw "Native Help Defenders did not return to the active Encounter menu. LastContext=$($after.state.context | ConvertTo-Json -Depth 6 -Compress)" }
    Capture-EngineFrame $afterFrame 'joined-encounter-frame'
    $afterDiagnostics = Invoke-AgentCli 'harnessJoinEncounterDiagnostics' @('-CommandId', "$prefix-after-join-diagnostics") 30
    if ($afterDiagnostics.status -ne 'completed') { throw 'Native post-join MapEvent diagnostics were unavailable.' }
    $pre = $beforeDiagnostics.data
    $post = $afterDiagnostics.data
    $sameMapEvent = ($pre.eventId -eq $post.eventId -and $post.isJoinedBattle)
    $joinedDefenderSide = ($post.mainPartyOnDefenderSide -and -not $post.mainPartyOnAttackerSide -and $post.playerSide -eq 'Defender')
    $worldAndClockStable = ([int]$pre.gold -eq [int]$post.gold -and [int]$pre.mainPartyMemberCount -eq [int]$post.mainPartyMemberCount -and
        [Math]::Abs([double]$pre.campaignDay - [double]$post.campaignDay) -lt 0.00001 -and [string]$pre.timeControlMode -eq [string]$post.timeControlMode)
    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-stop") 30
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $processesStopped = -not [bool](Get-Process -Name Bannerlord -ErrorAction SilentlyContinue)
    $result = [ordered]@{
        ProviderKind = 'Native NPC MapEvent and Native Join Encounter Help Defenders option; no battle mode started'
        ProcessId = $start.session.processId
        NpcBattleFixture = $fixture.data
        NativePlayerApproach = $approach
        JoinMenu = [ordered]@{ menuId = $joinMenu.state.context.menuId; context = $joinMenu.state.context; visibleOptions = @($joinMenu.state.availableMenuOptions | Where-Object { $_.available -and $_.enabled } | ForEach-Object { [ordered]@{ id = $_.id; text = $_.text } }) }
        JoinReceipt = $joinReceipt
        Before = $pre
        After = $post
        SameNpcMapEventAfterJoin = $sameMapEvent
        MainPartyJoinedDefenderSide = $joinedDefenderSide
        WorldAndClockUnchangedByJoin = $worldAndClockStable
        NoBattleSimulationStarted = (-not [bool]$post.battleSimulationExists)
        EngineFrames = @($beforeFrame, $afterFrame)
        SourceFixtureHashBefore = $fixtureHashBefore
        SourceFixtureHashAfter = $fixtureHashAfter
        SourceFixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = [bool]$stop.processStopped
        AllGameProcessesStopped = $processesStopped
        Passed = ($sameMapEvent -and $joinedDefenderSide -and $worldAndClockStable -and -not [bool]$post.battleSimulationExists -and $fixtureHashBefore -eq $fixtureHashAfter -and [bool]$stop.processStopped -and $processesStopped)
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
            ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $tempPath 'JoinEncounterDefendersFailure.json') -Encoding UTF8
    }
    throw
}
finally {
    if (Test-Path $sessionPath) {
        try {
            $session = Get-Content -LiteralPath $sessionPath -Raw | ConvertFrom-Json
            if ($session.status -ne 'stopped') { $null = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-final-stop") 30 }
        }
        catch { }
    }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
