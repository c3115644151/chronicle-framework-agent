[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$resultPath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP 'SafePassageBarterContextResult.json' } else { Join-Path $PSScriptRoot 'TestResults\ManualSafePassageBarterContext\SafePassageBarterContextResult.json' }
$prefix = 'safe-passage-barter-' + (Get-Date -Format 'yyyyMMddHHmmssfff')
$currentTestStep = 'preflight'

if (-not (Test-Path -LiteralPath $savePath)) { throw "Safe Passage test fixture not found: $LoadSaveName" }
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

function Get-SafePassageState([string]$Suffix) {
    return Invoke-AgentCli 'state' @('-CommandId', "$prefix-$Suffix")
}

function Wait-ForBanditConversation([string]$PartyId, [int]$GameProcessId, [int]$WaitSeconds = 90) {
    $deadline = [DateTime]::UtcNow.AddSeconds($WaitSeconds)
    $state = $null
    while ([DateTime]::UtcNow -lt $deadline) {
        $state = Get-SafePassageState "wait-bandit-$([Guid]::NewGuid().ToString('N'))"
        if ($state.state.context.gameState -eq 'MapState' -and
            $state.state.context.encounterActive -and
            $state.state.context.encounteredPartyId -eq $PartyId -and
            $state.state.context.conversation) { return $state }
        if (-not (Get-Process -Id $GameProcessId -ErrorAction SilentlyContinue)) { throw "Bannerlord process $GameProcessId exited while waiting for the native Bandit conversation." }
        Start-Sleep -Milliseconds 350
    }
    throw "The fixture bandit did not open a native conversation. LastState=$($state.state.context.gameState), Encounter=$($state.state.context.encounteredPartyId), Menu=$($state.state.context.menuId)."
}

function Wait-ForSafePassageBarter([int]$WaitSeconds = 8) {
    $deadline = [DateTime]::UtcNow.AddSeconds($WaitSeconds)
    $lastOptions = $null
    $lastState = $null
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $lastOptions = Invoke-AgentCli 'barterOptions' @('-CommandId', "$prefix-safe-passage-observe-$([Guid]::NewGuid().ToString('N'))") 15
            if ($lastOptions.status -eq 'completed' -and $lastOptions.data.contextInitializer -eq 'InitializeSafePassageBarterContext') { return $lastOptions }
        }
        catch { }

        $lastState = Get-SafePassageState "wait-barter-state-$([Guid]::NewGuid().ToString('N'))"
        if ($lastState.state.context.conversation) {
            $options = @($lastState.state.context.conversation.options | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.id) })
            if ($options.Count -eq 0) {
                $continue = Invoke-AgentCli 'dialogueContinue' @('-CommandId', "$prefix-safe-passage-continue-$([Guid]::NewGuid().ToString('N'))") 15
                if ($continue.status -ne 'completed') { throw "Native Continue after the bandit toll choice failed: $($continue.error)" }
            }
        }
        Start-Sleep -Milliseconds 150
    }
    $context = if ($lastState) { $lastState.state.context | ConvertTo-Json -Depth 8 -Compress } else { '<no state>' }
    throw "The native Bandit toll route did not open Safe Passage BarterVM. LastContext=$context"
}

try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $currentTestStep = 'load-fixture'
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $initial = Get-SafePassageState 'initial'
    if ($initial.state.context.gameState -ne 'MapState') { throw "Safe Passage fixture must start on Campaign Map; got '$($initial.state.context.gameState)'" }

    $currentTestStep = 'leave-settlement'
    $safeSettlement = @($initial.state.nearbySettlements | Where-Object { $_.type -eq 'town' -and -not $_.hostile -and [double]$_.distance -gt 1.0 } | Sort-Object distance | Select-Object -First 1)
    if ($safeSettlement.Count -ne 1) { throw 'No safe Town exists for leaving the fixture settlement before the Bandit encounter.' }
    $move = Invoke-AgentCli 'move' @('-SettlementId', [string]$safeSettlement[0].id, '-CommandId', "$prefix-exit-target-town")
    if ($move.status -ne 'completed') { throw 'Native movement could not target a safe visible Town.' }
    $arrival = Wait-ForAgentSettlementArrival -CliPath $cli -SettlementId ([string]$safeSettlement[0].id) -CommandPrefix "$prefix-town-arrival" -TimeoutSeconds $TimeoutSeconds
    $menu = Invoke-AgentCli 'menu' @('-CommandId', "$prefix-town-menu")
    $leave = @($menu.state.availableMenuOptions | Where-Object { $_.isLeave -and $_.available -and $_.enabled } | Select-Object -First 1)
    if ($leave.Count -ne 1) { throw 'The native Town menu did not expose an enabled Leave option.' }
    $leaveReceipt = Invoke-AgentCli 'menuSelect' @('-MenuId', [string]$menu.state.context.menuId, '-OptionId', [string]$leave[0].id, '-CommandId', "$prefix-town-leave")
    if ($leaveReceipt.status -ne 'completed') { throw 'Native Leave from Town did not complete.' }

    $currentTestStep = 'prepare-bandit-fixture'
    $beforeFixture = Get-SafePassageState 'map-before-bandit-fixture'
    if ($beforeFixture.state.context.encounterActive) { throw 'Campaign already has an active encounter before Safe Passage fixture setup.' }
    $fixture = Invoke-AgentCli 'harnessPrepareSafePassageFixture' @('-CommandId', "$prefix-prepare-bandit-fixture")
    if ($fixture.status -ne 'completed' -or $fixture.data.partyId -ne 'chronicle_harness_safe_passage_looters' -or -not [bool]$fixture.data.hostile -or $fixture.data.playerSide -ne 'Defender' -or -not [bool]$fixture.data.encounterActive)
        { throw 'The Harness did not start a native encounter with the hostile Bandit as attacker and MainParty as defender.' }

    $currentTestStep = 'native-bandit-meeting'
    $meeting = Wait-ForBanditConversation -PartyId ([string]$fixture.data.partyId) -GameProcessId ([int]$start.session.processId)
    $tollOption = @($meeting.state.context.conversation.options | Where-Object { $_.id -eq 'bandit_start_defender_2' -and $_.clickable } | Select-Object -First 1)
    if ($tollOption.Count -ne 1) {
        throw "Native Bandit encounter did not expose its Safe Passage dialogue option. Options=$(($meeting.state.context.conversation.options | ForEach-Object { $_.id }) -join ',')"
    }

    $currentTestStep = 'native-bandit-toll-dialogue'
    $dialogueChoice = Invoke-AgentCli 'dialogueSelect' @('-OptionId', 'bandit_start_defender_2', '-CommandId', "$prefix-select-native-bandit-toll")
    if ($dialogueChoice.status -ne 'completed') { throw "Native Bandit toll dialogue option was rejected: $($dialogueChoice.error)" }
    $barter = Wait-ForSafePassageBarter
    $context = $barter.data
    $safePassageClause = @($context.candidates | Where-Object { $_.nativeType -eq 'safe_passage_barterable' -and $_.isOffered } | Select-Object -First 1)
    if ($context.context -notlike 'contextual:*' -or $context.contextInitializer -ne 'InitializeSafePassageBarterContext' -or $safePassageClause.Count -ne 1)
        { throw 'The live Bandit BarterVM was not identified as a contextual Safe Passage proposal.' }

    $currentTestStep = 'native-safe-passage-auto-balance'
    $autoBalance = Invoke-AgentCli 'barterAutoBalance' @('-CommandId', "$prefix-native-safe-passage-auto-balance")
    if ($autoBalance.status -ne 'completed' -or -not $autoBalance.data.autoBalanced -or $autoBalance.data.updatedOptions.contextInitializer -ne 'InitializeSafePassageBarterContext')
        { throw 'Safe Passage Auto Balance did not call through the current Native VM while preserving its context.' }
    $updatedClause = @($autoBalance.data.updatedOptions.candidates | Where-Object { $_.nativeType -eq 'safe_passage_barterable' -and $_.isOffered } | Select-Object -First 1)
    if ($updatedClause.Count -ne 1) { throw 'Native Auto Balance removed the offered Safe Passage clause from the contextual proposal.' }

    $currentTestStep = 'stop-disposable-safe-passage-fixture'
    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-stop") 30
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $assertions = [ordered]@{
        NativeBanditDefenderEncounterReached = ($meeting.state.context.gameState -eq 'MapState' -and $meeting.state.context.encounteredPartyId -eq $fixture.data.partyId -and [bool]$meeting.state.context.encounterActive)
        NativeBanditSafePassageDialogueSelected = ($dialogueChoice.status -eq 'completed')
        CapturedActualSafePassageBarterVM = ($context.contextInitializer -eq 'InitializeSafePassageBarterContext' -and $context.context -like 'contextual:*' -and $safePassageClause.Count -eq 1)
        NativeAutoBalanceStayedInSafePassageContext = ($autoBalance.status -eq 'completed' -and $updatedClause.Count -eq 1)
        NativeAutoBalancePreservedWorldAndClock = ([int]$autoBalance.data.playerGoldBefore -eq [int]$autoBalance.data.playerGoldAfter -and [bool]$autoBalance.data.playerPartyFingerprintUnchanged -and [bool]$autoBalance.data.otherPartyFingerprintUnchanged -and [string]$autoBalance.data.timeControlModeBefore -eq [string]$autoBalance.data.timeControlModeAfter -and [double]$autoBalance.data.campaignDayBefore -eq [double]$autoBalance.data.campaignDayAfter)
        NativeEncounterSideWasDefender = ($fixture.data.playerSide -eq 'Defender' -and [bool]$fixture.data.encounterActive)
        FixtureHashUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = [bool]$stop.processStopped
    }
    $failedAssertions = @($assertions.Keys | Where-Object { -not [bool]$assertions[$_] })
    $result = [ordered]@{
        Fixture = $fixture.data
        Encounter = [ordered]@{ PartyId = $meeting.state.context.encounteredPartyId; MenuId = $meeting.state.context.menuId; Conversation = $meeting.state.context.conversation }
        DialogueChoice = [ordered]@{ OptionId = 'bandit_start_defender_2'; Receipt = $dialogueChoice }
        Barter = $context
        SafePassageClause = $safePassageClause[0]
        AutoBalance = $autoBalance.data
        UpdatedSafePassageClause = $updatedClause[0]
        TimeControlModeBeforeFixture = $beforeFixture.state.context.timeControlMode
        FixtureEncounter = $fixture.data
        Assertions = $assertions
        FailedAssertions = $failedAssertions
        FixtureHashBefore = $fixtureHashBefore
        FixtureHashAfter = $fixtureHashAfter
        ProcessStopped = [bool]$stop.processStopped
        Passed = ($failedAssertions.Count -eq 0)
    }
    $result | ConvertTo-Json -Depth 18 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    $result | ConvertTo-Json -Depth 18
    if (-not $result.Passed) { throw 'Native Safe Passage Barter context regression failed.' }
}
catch {
    if ($env:CHRONICLE_HARNESS_TEMP -and (Test-Path -LiteralPath $env:CHRONICLE_HARNESS_TEMP -PathType Container)) {
        [ordered]@{ FailedStep = $currentTestStep; Exception = $_.Exception.ToString(); TimestampUtc = [DateTime]::UtcNow.ToString('O') } |
            ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $env:CHRONICLE_HARNESS_TEMP 'SafePassageBarterContextFailure.json') -Encoding UTF8
    }
    throw
}
finally {
    if (Test-Path -LiteralPath $sessionPath) {
        try {
            $session = Get-Content -LiteralPath $sessionPath -Raw | ConvertFrom-Json
            if ($session.status -ne 'stopped') { $null = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-finally-stop") 30 }
        }
        catch { }
    }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
