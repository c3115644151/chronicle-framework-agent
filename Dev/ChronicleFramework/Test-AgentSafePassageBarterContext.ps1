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
$previousCrashCaptureFlag = $env:CHRONICLE_CAPTURE_CRASH_EXCEPTION

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

function Get-SafePassageState([string]$Suffix, [int]$CommandTimeout = 8) {
    return Invoke-AgentCli 'state' @('-CommandId', "$prefix-$Suffix") $CommandTimeout
}

function Wait-ForBanditConversation([string]$PartyId, [int]$GameProcessId, [int]$WaitSeconds = 90) {
    $deadline = [DateTime]::UtcNow.AddSeconds($WaitSeconds)
    $state = $null
    $consecutiveTimeouts = 0
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $state = Get-SafePassageState "wait-bandit-$([Guid]::NewGuid().ToString('N'))" 8
            $consecutiveTimeouts = 0
        }
        catch {
            if ($_.Exception.Message -notmatch 'timed out after') { throw }
            $consecutiveTimeouts++
            if ($consecutiveTimeouts -ge 3) { throw "The game stopped answering Harness state requests after Bandit AI pursuit began: $($_.Exception.Message)" }
            if (-not (Get-Process -Id $GameProcessId -ErrorAction SilentlyContinue)) { throw "Bannerlord process $GameProcessId exited while waiting for the native Bandit conversation." }
            continue
        }
        if ($state.state.context.gameState -eq 'MapState' -and
            $state.state.context.encounterActive -and
            $state.state.context.encounteredPartyId -eq $PartyId -and
            $state.state.context.conversation -and
            @($state.state.context.conversation.options | Where-Object { $_.id -eq 'bandit_start_defender_2' -and $_.clickable }).Count -gt 0) { return $state }
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

function Wait-ForSafePassageExit([int]$WaitSeconds = 20) {
    $deadline = [DateTime]::UtcNow.AddSeconds($WaitSeconds)
    $state = $null
    while ([DateTime]::UtcNow -lt $deadline) {
        $state = Get-SafePassageState "wait-safe-passage-exit-$([Guid]::NewGuid().ToString('N'))" 8
        if (-not [bool]$state.state.context.encounterActive -and -not $state.state.context.conversation) { return $state }
        if ($state.state.context.conversation) {
            $options = @($state.state.context.conversation.options | Where-Object { $_.clickable })
            if ($options.Count -eq 0) {
                $continue = Invoke-AgentCli 'dialogueContinue' @('-CommandId', "$prefix-safe-passage-conclusion-continue-$([Guid]::NewGuid().ToString('N'))") 8
                if ($continue.status -ne 'completed') { throw "Native Safe Passage conclusion could not continue: $($continue.error)" }
            }
            elseif ($options.Count -eq 1 -and $options[0].id -eq 'close_window') {
                $close = Invoke-AgentCli 'dialogueSelect' @('-OptionId', 'close_window', '-CommandId', "$prefix-safe-passage-conclusion-close-$([Guid]::NewGuid().ToString('N'))") 8
                if ($close.status -ne 'completed') { throw "Native Safe Passage conclusion could not close: $($close.error)" }
            }
            else { throw "Unexpected player choices appeared after accepted Safe Passage: $(($options | ForEach-Object { $_.id }) -join ',')" }
        }
        Start-Sleep -Milliseconds 150
    }
    throw "The accepted Safe Passage did not end the native Encounter/conversation within $WaitSeconds seconds. LastContext=$($state.state.context | ConvertTo-Json -Depth 7 -Compress)"
}

function Get-AutoBalanceWorldFingerprint($StateResponse) {
    $state = $StateResponse.state
    $npcParties = @($state.nearbyParties | Sort-Object id | ForEach-Object {
        [ordered]@{ Id = $_.id; Members = $_.members; Hostile = $_.hostile; Strength = $_.strength }
    })
    $fingerprint = [ordered]@{
        GameState = $state.context.gameState
        TimeControlMode = $state.context.timeControlMode
        MenuId = $state.context.menuId
        EncounterActive = $state.context.encounterActive
        EncounteredPartyId = $state.context.encounteredPartyId
        CampaignDay = [double]$state.campaignDay
        Gold = [int]$state.economy.gold
        Party = [ordered]@{
            Id = $state.party.id; Members = $state.party.members; Healthy = $state.party.healthy
            Wounded = $state.party.wounded; Prisoners = $state.party.prisoners; ItemCount = $state.party.itemCount
            Morale = $state.party.morale; Speed = [double]$state.party.speed; IsMoving = $state.party.isMoving
            MoveMode = $state.party.moveMode; DefaultBehavior = $state.party.defaultBehavior
        }
        Location = [ordered]@{
            X = [double]$state.location.x; Y = [double]$state.location.y
            CurrentSettlementId = $state.location.currentSettlementId; TargetSettlementId = $state.location.targetSettlementId
            TargetPartyId = $state.location.targetPartyId; TargetPosition = $state.location.targetPosition
        }
        NearbyParties = $npcParties
    }
    return $fingerprint | ConvertTo-Json -Depth 8 -Compress
}

try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $env:CHRONICLE_CAPTURE_CRASH_EXCEPTION = '1'
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
    $fixture = Invoke-AgentCli 'harnessPrepareSafePassageFixture' @('-CommandId', "$prefix-prepare-bandit-fixture") 25
    if ($fixture.status -ne 'completed' -or $fixture.data.partyId -ne 'chronicle_harness_safe_passage_looters' -or -not [bool]$fixture.data.hostile -or [int]$fixture.data.playerSidePartyCount -lt 1 -or [int]$fixture.data.playerSideMemberCount -lt 1 -or [double]$fixture.data.banditStrength -lt [double]$fixture.data.requiredBanditStrength -or [string]::IsNullOrWhiteSpace([string]$fixture.data.targetPartyId) -or $fixture.data.targetPartyId -ne $beforeFixture.state.party.id)
        { throw 'The Harness did not seed one actively-engaging hostile BanditFaction party with measured local joining forces and a native MainParty target.' }

    $currentTestStep = 'native-player-movement-near-engaging-bandits'
    $approach = Invoke-AgentCli 'moveToPoint' @('-X', ([double]$fixture.data.playerApproachPoint.x).ToString([Globalization.CultureInfo]::InvariantCulture), '-Y', ([double]$fixture.data.playerApproachPoint.y).ToString([Globalization.CultureInfo]::InvariantCulture), '-Surface', 'land', '-CommandId', "$prefix-native-map-click-toward-bandits")
    if ($approach.status -ne 'completed' -or $approach.state.party.defaultBehavior -ne 'GoToPoint' -or $approach.timeControlMode -ne 'StoppablePlay')
        { throw "Native map movement toward the approaching Bandit party did not start under the ordinary StoppablePlay clock mode: status=$($approach.status), clock=$($approach.timeControlMode), behavior=$($approach.state.party.defaultBehavior), error=$($approach.error)" }

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
    $worldBeforeAutoBalance = Get-SafePassageState 'world-before-native-safe-passage-auto-balance'
    $worldFingerprintBeforeAutoBalance = Get-AutoBalanceWorldFingerprint $worldBeforeAutoBalance
    $autoBalance = Invoke-AgentCli 'barterAutoBalance' @('-CommandId', "$prefix-native-safe-passage-auto-balance")
    if ($autoBalance.status -ne 'completed' -or -not $autoBalance.data.autoBalanced -or $autoBalance.data.updatedOptions.contextInitializer -ne 'InitializeSafePassageBarterContext')
        { throw 'Safe Passage Auto Balance did not call through the current Native VM while preserving its context.' }
    $updatedClause = @($autoBalance.data.updatedOptions.candidates | Where-Object { $_.nativeType -eq 'safe_passage_barterable' -and $_.isOffered } | Select-Object -First 1)
    if ($updatedClause.Count -ne 1) { throw 'Native Auto Balance removed the offered Safe Passage clause from the contextual proposal.' }
    $worldAfterAutoBalance = Get-SafePassageState 'world-after-native-safe-passage-auto-balance'
    $worldFingerprintAfterAutoBalance = Get-AutoBalanceWorldFingerprint $worldAfterAutoBalance
    $worldUnchangedByAutoBalance = ($worldFingerprintBeforeAutoBalance -ceq $worldFingerprintAfterAutoBalance)
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash

    $assertions = [ordered]@{
        NativeBanditDefenderEncounterReached = ($meeting.state.context.gameState -eq 'MapState' -and $meeting.state.context.encounteredPartyId -eq $fixture.data.partyId -and [bool]$meeting.state.context.encounterActive)
        BanditFixtureOutnumbersNativeJoiningSide = ([double]$fixture.data.banditStrength -ge [double]$fixture.data.requiredBanditStrength -and [double]$fixture.data.requiredBanditStrength -ge 1.55 * [double]$fixture.data.playerSideStrength)
        NativeJoiningPartiesRecorded = ([int]$fixture.data.playerSidePartyCount -ge 1 -and [int]$fixture.data.playerSideMemberCount -ge 1)
        NativeBanditSafePassageDialogueSelected = ($dialogueChoice.status -eq 'completed')
        CapturedActualSafePassageBarterVM = ($context.contextInitializer -eq 'InitializeSafePassageBarterContext' -and $context.context -like 'contextual:*' -and $safePassageClause.Count -eq 1)
        NativeAutoBalanceStayedInSafePassageContext = ($autoBalance.status -eq 'completed' -and $updatedClause.Count -eq 1)
        NativeAutoBalancePreservedWorldAndClock = ([int]$autoBalance.data.playerGoldBefore -eq [int]$autoBalance.data.playerGoldAfter -and [bool]$autoBalance.data.playerPartyFingerprintUnchanged -and $worldUnchangedByAutoBalance -and [string]$autoBalance.data.timeControlModeBefore -eq [string]$autoBalance.data.timeControlModeAfter -and [double]$autoBalance.data.campaignDayBefore -eq [double]$autoBalance.data.campaignDayAfter)
        BanditAIWasAssignedToEngagePlayer = ($fixture.data.targetPartyId -eq $beforeFixture.state.party.id)
        NativeMapClickStartedOrdinaryTimeFlow = ($approach.action -eq 'moveToPoint' -and $approach.state.party.defaultBehavior -eq 'GoToPoint' -and $approach.timeControlMode -eq 'StoppablePlay')
        FixtureHashUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
    }
    $failedAssertions = @($assertions.Keys | Where-Object { -not [bool]$assertions[$_] })
    if ($failedAssertions.Count -gt 0) {
        [ordered]@{ Assertions = $assertions; FailedAssertions = $failedAssertions; WorldFingerprintBeforeAutoBalance = $worldFingerprintBeforeAutoBalance; WorldFingerprintAfterAutoBalance = $worldFingerprintAfterAutoBalance } |
            ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $env:CHRONICLE_HARNESS_TEMP 'SafePassageBarterContextAssertions.json') -Encoding UTF8
        throw "Native Safe Passage assertions failed before fixture shutdown: $($failedAssertions -join ', ')"
    }

    $currentTestStep = 'native-safe-passage-offer-acceptance'
    $offer = Invoke-AgentCli 'barterOffer' @('-CommandId', "$prefix-native-safe-passage-offer") 15
    if ($offer.status -ne 'completed' -or -not [bool]$offer.data.submitted -or -not [bool]$offer.data.accepted)
        { throw "Native Safe Passage offer was not accepted by the current BarterVM: status=$($offer.status), submitted=$($offer.data.submitted), accepted=$($offer.data.accepted), error=$($offer.error)" }
    $safePassageResolution = Wait-ForSafePassageExit
    $postSafePassageDiagnostics = Invoke-AgentCli 'harnessMapPartyDiagnostics' @('-CommandId', "$prefix-safe-passage-native-cooldown-diagnostics") 12
    $banditCooldownParty = @($postSafePassageDiagnostics.data.mapPartyEntities | Where-Object { $_.id -eq $fixture.data.partyId } | Select-Object -First 1)
    $offerOutcomeAssertions = [ordered]@{
        NativeSafePassageOfferCommitted144 = ([int]$offer.data.offererGoldBefore -eq 1000 -and [int]$offer.data.offererGoldAfter -eq 856 -and [int]$safePassageResolution.state.economy.gold -eq 856)
        NativeEncounterEndedAfterAcceptedSafePassage = (-not [bool]$safePassageResolution.state.context.encounterActive -and -not $safePassageResolution.state.context.conversation)
        NativeSafePassageOfferDidNotAdvanceClock = ([string]$offer.data.timeControlModeBefore -eq [string]$offer.data.timeControlModeAfter -and [double]$offer.data.campaignDayBefore -eq [double]$offer.data.campaignDayAfter)
        Native32HourDoNotAttackCooldownSet = ($banditCooldownParty.Count -eq 1 -and [double]$banditCooldownParty[0].doNotAttackMainPartyRemainingHours -ge 31.5 -and [double]$banditCooldownParty[0].doNotAttackMainPartyRemainingHours -le 32.0)
        NativeSafePassageHoldModeObserved = ($banditCooldownParty.Count -eq 1 -and $banditCooldownParty[0].defaultBehavior -eq 'Hold' -and $banditCooldownParty[0].moveMode -eq 'Hold')
    }
    $offerOutcomeFailures = @($offerOutcomeAssertions.Keys | Where-Object { -not [bool]$offerOutcomeAssertions[$_] })
    if ($offerOutcomeFailures.Count -gt 0) {
        [ordered]@{ OutcomeAssertions = $offerOutcomeAssertions; FailedAssertions = $offerOutcomeFailures; Offer = $offer.data; Resolution = $safePassageResolution.state } |
            ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $env:CHRONICLE_HARNESS_TEMP 'SafePassageBarterContextOutcomeAssertions.json') -Encoding UTF8
        throw "Native Safe Passage outcome assertions failed before fixture shutdown: $($offerOutcomeFailures -join ', ')"
    }

    $currentTestStep = 'stop-disposable-safe-passage-fixture'
    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-stop") 30
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $assertions.ProcessStopped = [bool]$stop.processStopped
    $assertions.FixtureHashUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
    foreach ($outcomeName in $offerOutcomeAssertions.Keys) { $assertions[$outcomeName] = [bool]$offerOutcomeAssertions[$outcomeName] }
    $failedAssertions = @($assertions.Keys | Where-Object { -not [bool]$assertions[$_] })
    $result = [ordered]@{
        Fixture = $fixture.data
        Encounter = [ordered]@{ PartyId = $meeting.state.context.encounteredPartyId; MenuId = $meeting.state.context.menuId; Conversation = $meeting.state.context.conversation }
        DialogueChoice = [ordered]@{ OptionId = 'bandit_start_defender_2'; Receipt = $dialogueChoice }
        Barter = $context
        SafePassageClause = $safePassageClause[0]
        AutoBalance = $autoBalance.data
        NativeOffer = $offer.data
        SafePassageResolution = $safePassageResolution.state
        PostSafePassageNativeDiagnostics = $postSafePassageDiagnostics.data
        WorldFingerprintBeforeAutoBalance = $worldFingerprintBeforeAutoBalance
        WorldFingerprintAfterAutoBalance = $worldFingerprintAfterAutoBalance
        UpdatedSafePassageClause = $updatedClause[0]
        TimeControlModeBeforeFixture = $beforeFixture.state.context.timeControlMode
        NativePlayerApproachReceipt = $approach
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
    $failureFrame = Capture-HarnessFailureFrame -CliPath $cli -CommandPrefix $prefix -FailedStep $currentTestStep -FailureReason $_.Exception.ToString()
    if ($env:CHRONICLE_HARNESS_TEMP -and (Test-Path -LiteralPath $env:CHRONICLE_HARNESS_TEMP -PathType Container)) {
        $sessionAtFailure = if (Test-Path -LiteralPath $sessionPath) { Get-Content -LiteralPath $sessionPath -Raw | ConvertFrom-Json } else { $null }
        $crashExceptionPath = if ($sessionAtFailure) { Join-Path $env:CHRONICLE_HARNESS_TEMP "CrashException-$($sessionAtFailure.processId).txt" } else { $null }
        $crashException = if ($crashExceptionPath -and (Test-Path -LiteralPath $crashExceptionPath)) { [System.IO.File]::ReadAllText($crashExceptionPath) } else { $null }
        [ordered]@{ FailedStep = $currentTestStep; Exception = $_.Exception.ToString(); FailureFrame = $failureFrame; CrashExceptionPath = $crashExceptionPath; CrashExceptionCaptured = ($null -ne $crashException); CrashException = $crashException; TimestampUtc = [DateTime]::UtcNow.ToString('O') } |
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
    if ($null -eq $previousCrashCaptureFlag) { Remove-Item Env:CHRONICLE_CAPTURE_CRASH_EXCEPTION -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_CAPTURE_CRASH_EXCEPTION = $previousCrashCaptureFlag }
}
