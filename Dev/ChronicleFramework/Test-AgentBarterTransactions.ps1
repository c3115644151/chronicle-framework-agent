[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$resultPath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP 'BarterTransactionResult.json' } else { Join-Path $PSScriptRoot 'TestResults\ManualBarterTransactions\BarterTransactionResult.json' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$prefix = 'barter-w-' + (Get-Date -Format 'yyyyMMddHHmmssfff')
$currentTestStep = 'preflight'

if (-not (Test-Path -LiteralPath $savePath)) { throw "Barter transaction fixture not found: $LoadSaveName" }
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

function Get-BarterState([string]$Suffix) {
    return Invoke-AgentCli 'state' @('-CommandId', "$prefix-$Suffix")
}

function Wait-ForLordMeeting([string]$PartyId, [int]$GameProcessId, [int]$WaitSeconds = 100) {
    $deadline = [DateTime]::UtcNow.AddSeconds($WaitSeconds)
    $state = $null
    while ([DateTime]::UtcNow -lt $deadline) {
        $state = Get-BarterState "meeting-$([Guid]::NewGuid().ToString('N'))"
        if ($state.state.context.gameState -eq 'MapState' -and $state.state.context.encounterActive -and
            $state.state.context.encounteredPartyId -eq $PartyId -and $state.state.context.conversation) { return $state }
        if (-not (Get-Process -Id $GameProcessId -ErrorAction SilentlyContinue)) { throw "Bannerlord process $GameProcessId exited while approaching the ordinary Lord conversation." }
        Start-Sleep -Milliseconds 350
    }
    throw "Native pursuit did not open a Lord conversation with '$PartyId'. LastState=$($state.state.context.gameState), Encounter=$($state.state.context.encounteredPartyId)."
}

function Enter-OrdinaryLordBarter([string]$PartyId, [int]$Pass) {
    $state = Get-BarterState "barter-route-start-$Pass"
    $trace = @()
    for ($step = 1; $step -le 12; $step++) {
        $conversation = $state.state.context.conversation
        if (-not $conversation -or $state.state.context.encounteredPartyId -ne $PartyId) { throw 'The native Lord conversation ended or changed during the barter route.' }
        $options = @($conversation.options)
        $barterOption = @($options | Where-Object { $_.id -eq 'hero_barter' -and $_.clickable } | Select-Object -First 1)
        if ($barterOption.Count -eq 1) {
            $receipt = Invoke-AgentCli 'dialogueSelect' @('-OptionId', 'hero_barter', '-CommandId', "$prefix-barter-entry-$Pass")
            $trace += [pscustomobject]@{ Step = $step; OptionId = 'hero_barter'; Text = $barterOption[0].text; Status = $receipt.status }
            $entryState = Get-BarterState "barter-entry-state-$Pass"
            $entryOptions = @($entryState.state.context.conversation.options | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.id) })
            if ($entryState.state.context.conversation -and $entryOptions.Count -eq 0) {
                $continue = Invoke-AgentCli 'dialogueContinue' @('-CommandId', "$prefix-barter-entry-continue-$Pass")
                $trace += [pscustomobject]@{ Step = $step; OptionId = 'dialogueContinue'; Text = $entryState.state.context.conversation.sentenceText; Status = $continue.status }
                if ($continue.status -ne 'completed') { throw "Native continuation after the barter choice failed: $($continue.error)" }
            }
            $optionsDeadline = [DateTime]::UtcNow.AddSeconds(5)
            while ([DateTime]::UtcNow -lt $optionsDeadline) {
                try {
                    $barterOptions = Invoke-AgentCli 'barterOptions' @('-CommandId', "$prefix-barter-options-entry-$Pass") 15
                    if ($barterOptions.status -eq 'completed' -and $barterOptions.data.context -eq 'ordinary') {
                        return [pscustomobject]@{ Options = $barterOptions; Trace = $trace; State = $state }
                    }
                }
                catch { }
                Start-Sleep -Milliseconds 150
            }
            throw 'The ordinary Lord barter dialog option did not create a live captured Native BarterVM.'
        }

        $intro = @($options | Where-Object { $_.id -eq 'lord_meet_player_response1' -and $_.clickable } | Select-Object -First 1)
        $discussion = @($options | Where-Object { $_.id -eq 'main_option_discussions_3' -and $_.clickable } | Select-Object -First 1)
        $selected = if ($intro.Count -eq 1) { 'lord_meet_player_response1' } elseif ($discussion.Count -eq 1) { 'main_option_discussions_3' } else { $null }
        if ($selected) {
            $receipt = Invoke-AgentCli 'dialogueSelect' @('-OptionId', $selected, '-CommandId', "$prefix-barter-route-$Pass-$step")
            $trace += [pscustomobject]@{ Step = $step; OptionId = $selected; Text = ($options | Where-Object { $_.id -eq $selected } | Select-Object -First 1).text; Status = $receipt.status }
        }
        elseif ($options.Count -eq 0) {
            $receipt = Invoke-AgentCli 'dialogueContinue' @('-CommandId', "$prefix-barter-continue-$Pass-$step")
            $trace += [pscustomobject]@{ Step = $step; OptionId = $null; Text = $null; Status = $receipt.status }
        }
        else {
            throw "Ordinary Lord barter route has unsupported options at step ${step}: $(($options | ForEach-Object { $_.id }) -join ',')"
        }
        if ($receipt.status -ne 'completed') { throw "Native Lord conversation rejected route step '$selected': $($receipt.error)" }
        Start-Sleep -Milliseconds 200
        $state = Get-BarterState "barter-route-observe-$Pass-$step"
    }
    throw 'The current native Lord conversation did not expose hero_barter within 12 observed steps.'
}

function Find-PlayerGoldCandidate($Options) {
    $matching = @($Options | Where-Object {
        $_.nativeType -eq 'gold_barterable' -and $_.originalOwnerHeroId -eq 'main_hero' -and
        -not [bool]$_.isOffered -and [int]$_.maxAmount -ge 1 -and [bool]$_.isTransferable
    } | Select-Object -First 1)
    if ($matching.Count -eq 0) { return $null }
    return $matching[0]
}

try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $currentTestStep = 'load-fixture'
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $barterAssetFixtureSeed = Invoke-AgentCli 'harnessSeedEquipmentModifierFixture' @('-CommandId', "$prefix-seed-player-barter-asset")
    if ($barterAssetFixtureSeed.status -ne 'completed' -or [int]$barterAssetFixtureSeed.data.countAfter -ne 1) { throw 'The Harness could not add its exact tradeable MainParty item for Auto Balance validation.' }
    $initial = Get-BarterState 'initial'
    if ($initial.state.context.gameState -ne 'MapState') { throw "Barter fixture must start on Campaign Map; got '$($initial.state.context.gameState)'" }
    $safeSettlement = @($initial.state.nearbySettlements | Where-Object { $_.type -eq 'town' -and -not $_.hostile -and $_.distance -gt 1.0 } | Sort-Object distance | Select-Object -First 1)
    if ($safeSettlement.Count -ne 1) { throw 'No safe visible Town exists for leaving the fixture settlement and preparing a map meeting.' }
    $currentTestStep = 'leave-settlement'
    $move = Invoke-AgentCli 'move' @('-SettlementId', [string]$safeSettlement[0].id, '-CommandId', "$prefix-exit-target-town")
    if ($move.status -ne 'completed') { throw 'Native movement could not target a safe visible Town.' }
    $arrival = Wait-ForAgentSettlementArrival -CliPath $cli -SettlementId ([string]$safeSettlement[0].id) -CommandPrefix "$prefix-town-arrival" -TimeoutSeconds $TimeoutSeconds
    $menu = Invoke-AgentCli 'menu' @('-CommandId', "$prefix-town-menu")
    $leave = @($menu.state.availableMenuOptions | Where-Object { $_.isLeave -and $_.available -and $_.enabled } | Select-Object -First 1)
    if ($leave.Count -ne 1) { throw 'The native Town menu did not expose an enabled Leave option.' }
    $leaveReceipt = Invoke-AgentCli 'menuSelect' @('-MenuId', [string]$menu.state.context.menuId, '-OptionId', [string]$leave[0].id, '-CommandId', "$prefix-town-leave")
    if ($leaveReceipt.status -ne 'completed') { throw 'Native Leave from the Town did not complete.' }

    $currentTestStep = 'select-lord-target'
    $map = Get-BarterState 'map-after-leave'
    $lordTargets = @($map.state.nearbyParties | Where-Object { $_.type -eq 'lord' -and $_.isMoving -and -not $_.hostile -and $null -eq $_.currentSettlementId -and [double]$_.distance -gt 1.0 } | Sort-Object distance)
    if ($lordTargets.Count -eq 0) { throw 'No visible, mobile, non-hostile Lord party is present in the disposable fixture; no Party was invented or teleported.' }
    $target = $lordTargets[0]
    $currentTestStep = 'pursuit-to-lord'
    $pursuit = Invoke-AgentCli 'pursue' @('-PartyId', [string]$target.id, '-CommandId', "$prefix-pursue-lord")
    if ($pursuit.status -ne 'completed' -or $pursuit.state.location.targetPartyId -ne $target.id) { throw 'Native pursuit did not target the observed Lord party.' }
    $meeting = Wait-ForLordMeeting -PartyId ([string]$target.id) -GameProcessId ([int]$start.session.processId)
    $currentTestStep = 'first-native-barter-entry'
    $firstBarter = Enter-OrdinaryLordBarter -PartyId ([string]$target.id) -Pass 1
    $baseline = Get-BarterState 'native-barter-baseline'
    $goldCandidate = Find-PlayerGoldCandidate $firstBarter.Options.data.candidates
    if ($null -eq $goldCandidate) { throw 'The active ordinary Native Lord BarterVM exposed no transferable MainHero GoldBarterable.' }
    $playerItemCandidate = @($firstBarter.Options.data.candidates | Where-Object { $_.nativeType -eq 'item_barterable' -and $_.originalOwnerHeroId -eq 'main_hero' -and $_.itemId -eq 'vlandia_sword_1_t2' -and -not $_.isOffered -and $_.isTransferable } | Select-Object -First 1)
    if ($playerItemCandidate.Count -ne 1) { throw 'The ordinary Native Lord BarterVM did not expose the Harness-seeded player-owned tradeable item.' }
    $lordItemCandidate = @($firstBarter.Options.data.candidates | Where-Object {
        $_.nativeType -eq 'item_barterable' -and $_.originalOwnerHeroId -eq $firstBarter.Options.data.otherHeroId -and
        -not [bool]$_.isOffered -and [int]$_.maxAmount -ge 2 -and [int]$_.valueForOtherFaction -lt (0 - [int]$firstBarter.Options.data.playerGold) -and [bool]$_.isTransferable
    } | Select-Object -First 1)
    if ($lordItemCandidate.Count -ne 1) { throw 'The Native VM fixture exposed no multi-count item whose Native value exceeds available player Gold for Auto Balance testing.' }
    $goldBeforeCancel = [int]$baseline.state.economy.gold
    $partyCountBeforeCancel = [int]$baseline.state.party.itemCount

    $currentTestStep = 'native-auto-balance-assets'
    $itemOffer = Invoke-AgentCli 'barterEdit' @('-BarterCandidateId', [string]$lordItemCandidate[0].candidateId, '-BarterOperation', 'offer', '-Amount', '2', '-CommandId', "$prefix-barter-item-offer-two")
    if ($itemOffer.status -ne 'completed') { throw 'Native BarterItemVM did not add the Lord item candidate to the proposal.' }
    $itemOfferedOptions = Invoke-AgentCli 'barterOptions' @('-CommandId', "$prefix-barter-item-current")
    $offeredItem = @($itemOfferedOptions.data.candidates | Where-Object { $_.nativeType -eq 'item_barterable' -and $_.originalOwnerHeroId -eq $firstBarter.Options.data.otherHeroId -and $_.itemId -eq $lordItemCandidate[0].itemId -and $_.isOffered } | Select-Object -First 1)
    if ($offeredItem.Count -ne 1 -or [int]$offeredItem[0].currentAmount -ne 2) { throw 'Native Barter proposal did not preserve the requested two-item amount.' }
    $autoBalance = Invoke-AgentCli 'barterAutoBalance' @('-CommandId', "$prefix-barter-auto-balance")
    $autoGoldOffer = @($autoBalance.data.updatedOptions.candidates | Where-Object { $_.nativeType -eq 'gold_barterable' -and $_.originalOwnerHeroId -eq 'main_hero' -and $_.isOffered } | Select-Object -First 1)
    $autoOwnedItemOffer = @($autoBalance.data.updatedOptions.candidates | Where-Object { $_.nativeType -eq 'item_barterable' -and $_.originalOwnerHeroId -eq 'main_hero' -and $_.itemId -eq 'vlandia_sword_1_t2' -and $_.isOffered } | Select-Object -First 1)
    $autoBalanceVerified = ($autoBalance.status -eq 'completed' -and $autoGoldOffer.Count -eq 1 -and [int]$autoGoldOffer[0].currentAmount -eq [int]$autoBalance.data.updatedOptions.playerGold -and $autoOwnedItemOffer.Count -eq 1 -and [bool]$autoBalance.data.playerPartyFingerprintUnchanged -and [int]$autoBalance.data.playerGoldBefore -eq [int]$autoBalance.data.playerGoldAfter)
    if (-not $autoBalanceVerified) { throw 'Native Barter Auto Balance did not add both the available MainHero Gold and the tradeable player item to the unaffordable proposal without changing world resources.' }
    $itemAfterBalance = @($autoBalance.data.updatedOptions.candidates | Where-Object { $_.nativeType -eq 'item_barterable' -and $_.originalOwnerHeroId -eq $firstBarter.Options.data.otherHeroId -and $_.itemId -eq $lordItemCandidate[0].itemId -and $_.isOffered } | Select-Object -First 1)
    if ($itemAfterBalance.Count -ne 1 -or [int]$itemAfterBalance[0].currentAmount -ne 2) { throw 'Native Auto Balance unexpectedly changed the offered ItemBarterable amount.' }

    $autoReset = Invoke-AgentCli 'barterReset' @('-CommandId', "$prefix-barter-autobalance-reset")
    if ($autoReset.status -ne 'completed' -or @($autoReset.data.updatedOptions.candidates | Where-Object { $_.isOffered }).Count -ne 0) { throw 'Native Reset did not clear the Auto Balance proposal before the separate edit checks.' }
    $optionsAfterAutoBalanceReset = Invoke-AgentCli 'barterOptions' @('-CommandId', "$prefix-barter-options-after-autobalance-reset")
    $currentTestStep = 'native-gold-proposal-edit'
    $currentGoldCandidate = Find-PlayerGoldCandidate $optionsAfterAutoBalanceReset.data.candidates
    if ($null -eq $currentGoldCandidate) { throw 'Native Reset did not return the current MainHero GoldBarterable candidate.' }
    $edit = Invoke-AgentCli 'barterEdit' @('-BarterCandidateId', [string]$currentGoldCandidate.candidateId, '-BarterOperation', 'offer', '-Amount', '1', '-CommandId', "$prefix-barter-edit-cancel")
    if ($edit.status -ne 'completed' -or -not $edit.data.updatedOptions.candidates) { throw 'Native BarterItemVM could not add a Gold offer to the active proposal.' }
    $staleEdit = Invoke-AgentCli 'barterEdit' @('-BarterCandidateId', [string]$currentGoldCandidate.candidateId, '-BarterOperation', 'offer', '-Amount', '1', '-CommandId', "$prefix-barter-stale-edit") 15
    $currentTestStep = 'native-reset-stale-id'
    $reset = Invoke-AgentCli 'barterReset' @('-CommandId', "$prefix-barter-reset")
    $resetIsEmpty = ($reset.status -eq 'completed' -and [bool]$reset.data.updatedOptions.isOfferDisabled -and @($reset.data.updatedOptions.candidates | Where-Object { $_.isOffered }).Count -eq 0)
    if (-not $resetIsEmpty) { throw 'Native BarterVM Reset did not clear the temporary proposal.' }
    $currentOptionsBeforeCancel = Invoke-AgentCli 'barterOptions' @('-CommandId', "$prefix-barter-options-before-cancel")
    $cancelGoldCandidate = Find-PlayerGoldCandidate $currentOptionsBeforeCancel.data.candidates
    if ($null -eq $cancelGoldCandidate) { throw 'Reset did not return the MainHero GoldBarterable to the current Native candidate list.' }
    $cancelEdit = Invoke-AgentCli 'barterEdit' @('-BarterCandidateId', [string]$cancelGoldCandidate.candidateId, '-BarterOperation', 'offer', '-Amount', '1', '-CommandId', "$prefix-barter-edit-cancel-final")
    if ($cancelEdit.status -ne 'completed') { throw 'Native BarterVM could not recreate the simple Gold proposal before cancellation.' }
    $currentTestStep = 'native-cancel-no-mutation'
    $cancel = Invoke-AgentCli 'barterCancel' @('-CommandId', "$prefix-barter-cancel")
    $afterCancel = Get-BarterState 'after-barter-cancel'
    $cancelNoMutation = ($cancel.status -eq 'completed' -and $cancel.data.cancelled -and [bool]$cancel.data.playerPartyFingerprintUnchanged -and [bool]$cancel.data.otherPartyFingerprintUnchanged -and [int]$afterCancel.state.economy.gold -eq $goldBeforeCancel -and [int]$afterCancel.state.party.itemCount -eq $partyCountBeforeCancel -and [int]$cancel.data.otherHeroBaseRelationAfter -eq [int]$cancel.data.otherHeroBaseRelationBefore)
    if (-not $cancelNoMutation) { throw 'Native Barter Cancel did not discard the draft without changing player resources or relation.' }

    $currentTestStep = 'second-native-barter-entry'
    $secondBarter = Enter-OrdinaryLordBarter -PartyId ([string]$target.id) -Pass 2
    $offerCandidate = Find-PlayerGoldCandidate $secondBarter.Options.data.candidates
    if ($null -eq $offerCandidate) { throw 'The second Native ordinary BarterVM had no current MainHero GoldBarterable candidate.' }
    $offerEdit = Invoke-AgentCli 'barterEdit' @('-BarterCandidateId', [string]$offerCandidate.candidateId, '-BarterOperation', 'offer', '-Amount', '1', '-CommandId', "$prefix-barter-edit-offer")
    if ($offerEdit.status -ne 'completed' -or [bool]$offerEdit.data.updatedOptions.isOfferDisabled) { throw 'Native BarterVM did not expose an enabled Offer for a one-denar gift to the Lord.' }
    $currentTestStep = 'native-offer-one-denar'
    $offer = Invoke-AgentCli 'barterOffer' @('-CommandId', "$prefix-barter-offer")
    $afterOffer = Get-BarterState 'after-barter-offer'
    $offerApplied = ($offer.status -eq 'completed' -and [bool]$offer.data.submitted -and [bool]$offer.data.accepted -and [int]$offer.data.offererGoldAfter -eq ([int]$offer.data.offererGoldBefore - 1) -and [int]$offer.data.otherGoldAfter -eq ([int]$offer.data.otherGoldBefore + 1) -and $afterOffer.state.context.gameState -eq 'MapState')
    if (-not $offerApplied) { throw 'Native Barter Offer did not produce the expected accepted one-denar gold transfer and return to the Campaign Map.' }

    $currentTestStep = 'clear-disposable-barter-asset-fixture'
    $barterAssetFixtureClear = Invoke-AgentCli 'harnessClearEquipmentModifierFixture' @('-CommandId', "$prefix-clear-player-barter-asset")
    if ($barterAssetFixtureClear.status -ne 'completed' -or [int]$barterAssetFixtureClear.data.countAfter -ne 0) { throw 'The disposable player-owned barter asset could not be removed before test shutdown.' }
    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-stop") 30
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $assertions = [ordered]@{
        PursuitReachedOrdinaryLordConversation = ($meeting.state.context.gameState -eq 'MapState' -and $meeting.state.context.encounteredPartyId -eq $target.id -and -not [string]::IsNullOrWhiteSpace([string]$meeting.state.context.conversation.heroId))
        NativeHeroBarterEntryOpenedLiveBarterVM = ($firstBarter.Options.status -eq 'completed' -and $firstBarter.Options.data.context -eq 'ordinary')
        NativeItemAndAutoBalanceUsesCashAndOwnedItem = ($itemOffer.status -eq 'completed' -and [bool]$autoBalanceVerified -and [int]$itemAfterBalance[0].currentAmount -eq 2)
        NativeAddResetAndStaleCandidateValidated = ($edit.status -eq 'completed' -and $staleEdit.status -eq 'rejected' -and $resetIsEmpty)
        NativeCancelDiscardsGoldDraft = [bool]$cancelNoMutation
        NativeOfferAcceptedAndTransfersExactlyOneGold = [bool]$offerApplied
        FixtureHashUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        DisposableBarterAssetFixtureCleared = ($barterAssetFixtureClear.status -eq 'completed' -and [int]$barterAssetFixtureClear.data.countAfter -eq 0)
        ProcessStopped = [bool]$stop.processStopped
    }
    $failedAssertions = @($assertions.Keys | Where-Object { -not [bool]$assertions[$_] })
    $result = [ordered]@{
        Target = $target
        Pursuit = [ordered]@{ Status = $pursuit.status; Outcome = $meeting.state.context.conversation.sentenceText; CampaignDay = $meeting.campaignDay }
        FirstBarter = $firstBarter.Options.data
        InitialGoldCandidate = $goldCandidate[0]
        InitialPlayerItemCandidate = $playerItemCandidate[0]
        PostAutoBalanceGoldCandidate = $currentGoldCandidate
        AutoBalance = $autoBalance.data
        AutoBalanceItem = $itemAfterBalance[0]
        AutoBalancePlayerOwnedItem = $autoOwnedItemOffer[0]
        AutoBalanceReset = $autoReset.data
        BarterAssetFixtureSeed = $barterAssetFixtureSeed.data
        BarterAssetFixtureClear = $barterAssetFixtureClear.data
        Edit = $edit.data
        StaleEditStatus = [string]$staleEdit.status
        Reset = $reset.data
        Cancel = $cancel.data
        AfterCancel = [ordered]@{ Gold = $afterCancel.state.economy.gold; PartyItemCount = $afterCancel.state.party.itemCount }
        SecondBarter = $secondBarter.Options.data
        Offer = $offer.data
        AfterOffer = [ordered]@{ Gold = $afterOffer.state.economy.gold; Context = $afterOffer.state.context }
        Assertions = $assertions
        FailedAssertions = $failedAssertions
        FixtureHashBefore = $fixtureHashBefore
        FixtureHashAfter = $fixtureHashAfter
        ProcessStopped = [bool]$stop.processStopped
        Passed = ($failedAssertions.Count -eq 0)
    }
    $result | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    $result | ConvertTo-Json -Depth 16
    if (-not $result.Passed) { throw 'Native ordinary Lord barter transaction regression failed.' }
}
catch {
    $failureFrame = Capture-HarnessFailureFrame -CliPath $cli -CommandPrefix $prefix -FailedStep $currentTestStep -FailureReason $_.Exception.ToString()
    if ($env:CHRONICLE_HARNESS_TEMP -and (Test-Path -LiteralPath $env:CHRONICLE_HARNESS_TEMP -PathType Container)) {
        [ordered]@{ FailedStep = $currentTestStep; Exception = $_.Exception.ToString(); FailureFrame = $failureFrame; TimestampUtc = [DateTime]::UtcNow.ToString('O') } |
            ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $env:CHRONICLE_HARNESS_TEMP 'BarterTransactionFailure.json') -Encoding UTF8
    }
    throw
}
finally {
    if (Test-Path -LiteralPath $sessionPath) {
        try {
            Invoke-AgentCli 'barterCancel' @('-CommandId', "$prefix-cleanup-barter-cancel") 15 | Out-Null
        }
        catch { }
        try { Invoke-AgentCli 'stop' @('-CommandId', "$prefix-cleanup-stop") 30 | Out-Null } catch { }
    }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:\CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
