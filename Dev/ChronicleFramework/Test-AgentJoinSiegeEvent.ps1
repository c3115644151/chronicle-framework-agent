[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180,
    [int]$SiegeMenuWaitSeconds = 120
)

$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$tempPath = $env:CHRONICLE_HARNESS_TEMP
$runDirectory = if ($tempPath) { Split-Path -Parent $tempPath } else { Join-Path $PSScriptRoot 'TestResults\ManualJoinSiegeEvent' }
$frameRoot = if ($tempPath) { $tempPath } else { $runDirectory }
$resultPath = if ($tempPath) { Join-Path $tempPath 'JoinSiegeEventResult.json' } else { Join-Path $runDirectory 'JoinSiegeEventResult.json' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$prefix = 'join-siege-event-' + (Get-Date -Format 'yyyyMMddHHmmssfff')
$currentStep = 'preflight'
$approach = $null

if (-not (Test-Path -LiteralPath $savePath)) { throw "Join Siege fixture not found: $LoadSaveName" }
if (Get-Process -Name Bannerlord -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
. (Join-Path $PSScriptRoot 'Test-AgentSupport.ps1')

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
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
        { throw "Native Join Siege frame '$Path' was not captured (receipt='$($receipt.status)', exists=$exists, bytes=$length)." }
}

try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $currentStep = 'load-disposable-campaign'
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $initial = Invoke-AgentCli 'state' @('-CommandId', "$prefix-initial")
    if ($initial.state.context.gameState -ne 'MapState' -or $initial.state.context.encounterActive -or $initial.state.context.captivity)
        { throw 'Fixture must start as a free Campaign Map party with no active Encounter.' }

    $currentStep = 'observe-current-visible-fortification-target'
    $settlementTargets = Invoke-AgentCli 'mapSettlementTargets' @('-CommandId', "$prefix-visible-settlement-targets") 30
    if ($settlementTargets.status -ne 'completed') { throw 'Native visible map settlement target query failed.' }
    $target = @($settlementTargets.data.mapSettlementTargets | Where-Object { $_.type -in @('town','castle') -and -not [bool]$_.underSiege } | Select-Object -First 1)
    if ($target.Count -ne 1) { throw 'No visible, unsieged Town/Castle marker was available to prepare the controlled siege fixture.' }
    $settlementId = [string]$target[0].id

    $currentStep = 'prepare-native-siege-event-and-war-context'
    $fixture = Invoke-AgentCli 'harnessPrepareSiegeJoinFixture' @('-SettlementId', $settlementId, '-CommandId', "$prefix-native-siege-fixture") 30
    if ($fixture.status -ne 'completed' -or -not [bool]$fixture.data.nativeSiegeJoinFixtureCreated -or
        -not [bool]$fixture.data.siegeEventActive -or -not [bool]$fixture.data.attackerJoinSideEnabled -or
        [bool]$fixture.data.settlementMapEventActive -or [bool]$fixture.data.besiegerMapEventActive)
        { throw "Native Settlement SiegeEvent fixture did not satisfy attacker Join conditions: $($fixture.data | ConvertTo-Json -Compress)" }
    $besiegerLeaderPartyId = [string]$fixture.data.besiegerLeaderPartyId

    $currentStep = 'confirm-sieged-settlement-remains-a-native-visible-target'
    $siegedTargets = Invoke-AgentCli 'mapSettlementTargets' @('-CommandId', "$prefix-sieged-settlement-targets") 30
    $siegedTarget = @($siegedTargets.data.mapSettlementTargets | Where-Object { $_.id -eq $settlementId -and [bool]$_.underSiege } | Select-Object -First 1)
    if ($siegedTargets.status -ne 'completed' -or $siegedTarget.Count -ne 1)
        { throw "Native visible settlement target '$settlementId' did not present its SiegeEvent after fixture setup." }

    $currentStep = 'approach-visible-sieged-settlement-through-native-map-navigation'
    $approach = Invoke-AgentCli 'move' @('-SettlementId', $settlementId, '-CommandId', "$prefix-native-move-to-sieged-settlement") 30
    if ($approach.status -ne 'completed' -or $approach.state.location.targetSettlementId -ne $settlementId)
        { throw 'Native Map travel did not target the currently visible siege settlement.' }

    $currentStep = 'observe-native-join-siege-event-menu'
    $deadline = [DateTime]::UtcNow.AddSeconds($SiegeMenuWaitSeconds)
    $siegeMenu = $null
    $state = $null
    $timeouts = 0
    while ([DateTime]::UtcNow -lt $deadline) {
        try { $state = Invoke-AgentCli 'state' @('-CommandId', "$prefix-siege-menu-poll-$([Guid]::NewGuid().ToString('N'))") 8; $timeouts = 0 }
        catch {
            if ($_.Exception.Message -notmatch 'timed out after') { throw }
            $timeouts++
            if ($timeouts -ge 3) { throw 'Game stopped answering while waiting for Native Join Siege menu.' }
            if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'Bannerlord exited before the Join Siege menu appeared.' }
            continue
        }
        if ($state.state.context.menuId -eq 'join_siege_event' -and [bool]$state.state.context.encounterActive) { $siegeMenu = $state; break }
        if ($state.state.context.menuId -in @('encounter','army_encounter','menu_siege_strategies') -or
            ([bool]$state.state.context.encounterActive -and $state.state.context.menuId -ne 'join_siege_event'))
            { throw "Native Settlement interaction entered '$($state.state.context.menuId)' rather than join_siege_event. LastContext=$($state.state.context | ConvertTo-Json -Compress)" }
        if ($state.state.context.captivity) { throw 'MainHero entered Captivity before the Native Join Siege options were observed.' }
        if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'Bannerlord exited before the Join Siege menu appeared.' }
        Start-Sleep -Milliseconds 200
    }
    if (-not $siegeMenu) { throw "Native join_siege_event did not open within $SiegeMenuWaitSeconds seconds. LastContext=$($state.state.context | ConvertTo-Json -Depth 6 -Compress)" }

    $currentStep = 'inspect-current-native-siege-options-and-prerequisites'
    $options = @($siegeMenu.state.availableMenuOptions | Where-Object { $_.available -and $_.enabled })
    $joinOption = @($options | Where-Object { $_.id -eq 'join_siege_event' } | Select-Object -First 1)
    $beforeDiag = Invoke-AgentCli 'harnessSiegeJoinDiagnostics' @('-SettlementId', $settlementId, '-PartyId', $besiegerLeaderPartyId, '-CommandId', "$prefix-before-siege-join-diagnostics") 30
    if ($beforeDiag.status -ne 'completed') { throw 'Native SiegeEvent diagnostics unavailable before Join.' }
    $pre = $beforeDiag.data
    if ($joinOption.Count -ne 1 -or -not [bool]$pre.siegeEventActive -or -not [bool]$pre.settlementUnderSiege -or
        [bool]$pre.settlementMapEventActive -or [bool]$pre.besiegerMapEventActive -or [bool]$pre.playerSiegeEventActive -or [bool]$pre.mainPartyInBesiegerCamp -or
        -not [bool]$pre.canJoinAttacker -or [bool]$pre.canJoinDefender)
        { throw "Join continuing siege was not the valid unengaged attacker-side action: options=$(($options | ForEach-Object id) -join ','); diagnostics=$($pre | ConvertTo-Json -Compress)" }
    $beforeFrame = Join-Path $frameRoot 'join-siege-event-before.bmp'
    $afterFrame = Join-Path $frameRoot 'join-siege-event-after.bmp'
    Capture-EngineFrame $beforeFrame 'join-siege-page'

    $currentStep = 'select-native-join-continuing-siege-option'
    $joinReceipt = Invoke-AgentCli 'menuSelect' @('-MenuId', 'join_siege_event', '-OptionId', 'join_siege_event', '-CommandId', "$prefix-join-continuing-siege") 30
    if ($joinReceipt.status -ne 'completed') { throw "Native Join Continuing Siege option was rejected: $($joinReceipt.error)" }

    $currentStep = 'verify-native-player-siege-preparation'
    $after = $null
    $afterDeadline = [DateTime]::UtcNow.AddSeconds(25)
    while ([DateTime]::UtcNow -lt $afterDeadline) {
        $after = Invoke-AgentCli 'state' @('-CommandId', "$prefix-after-siege-join-state-$([Guid]::NewGuid().ToString('N'))") 8
        if ($after.state.context.menuId -eq 'menu_siege_strategies' -or -not [bool]$after.state.context.encounterActive) { break }
        if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'Bannerlord exited while submitting Native Join Siege.' }
        Start-Sleep -Milliseconds 150
    }
    if ($after.state.context.menuId -ne 'menu_siege_strategies')
        { throw "Native Join Siege did not enter siege preparation. LastContext=$($after.state.context | ConvertTo-Json -Depth 6 -Compress)" }
    Capture-EngineFrame $afterFrame 'join-siege-preparation'
    $afterDiag = Invoke-AgentCli 'harnessSiegeJoinDiagnostics' @('-SettlementId', $settlementId, '-PartyId', $besiegerLeaderPartyId, '-CommandId', "$prefix-after-siege-join-diagnostics") 30
    if ($afterDiag.status -ne 'completed') { throw 'Native post-Join-Siege diagnostics unavailable.' }
    $post = $afterDiag.data
    $joinedSiegeAsAttacker = ([bool]$post.siegeEventActive -and [bool]$post.settlementUnderSiege -and [bool]$post.playerSiegeEventActive -and
        [string]$post.playerSiegeSide -eq 'Attacker' -and [bool]$post.mainPartyInBesiegerCamp)
    $noMissionAutoStarted = ($after.state.context.gameState -eq 'MapState' -and $null -eq $after.state.mission)
    $resourcesRecorded = ($null -ne $pre.gold -and $null -ne $post.gold -and $null -ne $pre.playerInfluence -and $null -ne $post.playerInfluence)
    $resourcesUnchanged = ($resourcesRecorded -and [int]$pre.gold -eq [int]$post.gold -and [double]$pre.playerInfluence -eq [double]$post.playerInfluence)
    $nativeSiegeTimeRecorded = ([string]$post.timeControlMode -in @('UnstoppablePlay','UnstoppableFastForward') -and [double]$post.campaignDay -ge [double]$pre.campaignDay)

    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-stop") 30
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $processesStopped = -not [bool](Get-Process -Name Bannerlord -ErrorAction SilentlyContinue)
    $result = [ordered]@{
        ProviderKind = 'Native Settlement join_siege_event menu; join the continuing siege as attacker and enter Native siege preparation'
        ProcessId = $start.session.processId
        SiegeFixture = $fixture.data
        NativeVisibleSettlementTarget = $target[0]
        NativeMapApproach = $approach
        NativeJoinSiegeMenu = [ordered]@{ menuId = $siegeMenu.state.context.menuId; context = $siegeMenu.state.context; enabledOptions = @($options | ForEach-Object { [ordered]@{ id = $_.id; text = $_.text } }) }
        NativeJoinReceipt = $joinReceipt
        Before = $pre
        After = $post
        AfterState = [ordered]@{ context = $after.state.context; location = $after.state.location; campaignDay = $after.campaignDay; timeControlMode = $after.timeControlMode }
        JoinedSiegeAsAttacker = $joinedSiegeAsAttacker
        SiegePreparationMenuReached = ($after.state.context.menuId -eq 'menu_siege_strategies')
        NoMissionAutoStarted = $noMissionAutoStarted
        ResourcesUnchanged = $resourcesUnchanged
        NativeSiegeTimeVerified = $nativeSiegeTimeRecorded
        EngineFrames = @($beforeFrame, $afterFrame)
        SourceFixtureHashBefore = $fixtureHashBefore
        SourceFixtureHashAfter = $fixtureHashAfter
        SourceFixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = [bool]$stop.processStopped
        AllGameProcessesStopped = $processesStopped
        Passed = ($joinedSiegeAsAttacker -and $noMissionAutoStarted -and $resourcesUnchanged -and $nativeSiegeTimeRecorded -and $fixtureHashBefore -eq $fixtureHashAfter -and [bool]$stop.processStopped -and $processesStopped)
    }
    $json = $result | ConvertTo-Json -Depth 16
    if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) { Set-Content -LiteralPath $resultPath -Value $json -Encoding UTF8 }
    $json
    if (-not $result.Passed) { exit 1 }
}
catch {
    $failureFrame = Capture-HarnessFailureFrame -CliPath $cli -CommandPrefix $prefix -FailedStep $currentStep -FailureReason $_.Exception.ToString()
    if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) {
        [ordered]@{ FailedStep = $currentStep; Exception = $_.Exception.ToString(); FailureFrame = $failureFrame; LastState = if ($state) { $state.state.context } else { $null }; LastAction = $approach; Fixture = if ($fixture) { $fixture.data } else { $null }; TimestampUtc = [DateTime]::UtcNow.ToString('O') } |
            ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tempPath 'JoinSiegeEventFailure.json') -Encoding UTF8
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
