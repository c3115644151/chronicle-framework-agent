[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$env:CHRONICLE_HARNESS_MODE = 'visual-capture'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$decisionLoop = Join-Path $PSScriptRoot 'Agent-DecisionLoop.ps1'
$decisionProvider = Join-Path $PSScriptRoot 'Test-AgentLoopProvider.ps1'
. (Join-Path $PSScriptRoot 'Test-AgentSupport.ps1')
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$runPrefix = 'p4r-' + (Get-Date -Format 'yyyyMMddHHmmssfff')
if (-not (Test-Path $savePath)) { throw "Recruitment fixture not found: $savePath" }
$fixtureHashBefore = (Get-FileHash $savePath -Algorithm SHA256).Hash

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @()) {
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $cli $Action @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    return $output | ConvertFrom-Json
}

function Open-NativeTownTrade([string]$Suffix) {
    $menu = Invoke-AgentCli 'menu' @('-CommandId', "$runPrefix-$Suffix-menu", '-TimeoutSeconds', $TimeoutSeconds)
    if ($menu.state.context.menuId -ne 'town') { throw "Native market test expected the Town menu, got '$($menu.state.context.menuId)'" }
    $tradeOption = @($menu.state.availableMenuOptions | Where-Object { $_.id -eq 'trade' -and $_.available -and $_.enabled } | Select-Object -First 1)
    if ($tradeOption.Count -ne 1) { throw 'The current Town menu did not expose an enabled Native Trade option.' }
    $open = Invoke-AgentCli 'menuSelect' @('-MenuId', 'town', '-OptionId', [string]$tradeOption[0].id, '-CommandId', "$runPrefix-$Suffix-open-trade", '-TimeoutSeconds', $TimeoutSeconds)
    $state = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-$Suffix-trade-state", '-TimeoutSeconds', $TimeoutSeconds)
    if ($open.status -ne 'completed' -or $state.state.context.gameState -ne 'InventoryState' -or $state.state.inventoryScreen.mode -ne 'Trade')
        { throw 'Native Town trade did not open its Trade-mode InventoryState.' }
    return [pscustomobject]@{ Menu = $menu; Open = $open; State = $state }
}

try {
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName, '-TimeoutSeconds', $TimeoutSeconds)
    $beforeMove = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-before-move", '-TimeoutSeconds', $TimeoutSeconds)
    $target = @($beforeMove.state.nearbySettlements | Where-Object { -not $_.hostile -and $_.distance -gt 1.0 } | Sort-Object distance | Select-Object -First 1)
    if ($target.Count -ne 1) { throw 'No safe visible settlement target exists in the disposable fixture.' }
    $move = Invoke-AgentCli 'move' @('-SettlementId', [string]$target[0].id, '-CommandId', "$runPrefix-move", '-TimeoutSeconds', $TimeoutSeconds)
    if ($move.status -ne 'completed' -or $move.state.location.targetSettlementId -ne $target[0].id) { throw 'Native move order did not target the recruitment settlement.' }
    $arrival = Wait-ForAgentSettlementArrival -CliPath $cli -SettlementId ([string]$target[0].id) -CommandPrefix "$runPrefix-travel" -TimeoutSeconds $TimeoutSeconds
    if ($arrival.state.location.currentSettlementId -ne $target[0].id) { throw 'Player party did not reach the recruitment settlement.' }

    $beforeRecruit = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-before-recruit", '-TimeoutSeconds', $TimeoutSeconds)
    $recruitmentMenuOption = @($beforeRecruit.state.availableMenuOptions | Where-Object { $_.id -eq 'recruit_volunteers' -and $_.available -and $_.enabled } | Select-Object -First 1)
    $recruitmentMenuContextValid = ($beforeRecruit.state.context.menuId -in @('town','town_backstreet','village') -and $recruitmentMenuOption.Count -eq 1)
    if (-not $recruitmentMenuContextValid) { throw 'Native recruit_volunteers was not available in the current observed Settlement menu.' }
    $previousProviderMode = $env:CHRONICLE_TEST_PROVIDER_MODE
    $env:CHRONICLE_TEST_PROVIDER_MODE = 'recruitment'
    try {
        $loopOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $decisionLoop -DecisionProviderPath $decisionProvider -MaxDecisions 2 -TimeoutSeconds $TimeoutSeconds -CommandPrefix "$runPrefix-recruit-loop" 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "Recruitment decision loop failed: $loopOutput" }
    $recruitmentLoop = $loopOutput | ConvertFrom-Json
    }
    finally {
        if ($null -eq $previousProviderMode) { Remove-Item Env:CHRONICLE_TEST_PROVIDER_MODE -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_TEST_PROVIDER_MODE = $previousProviderMode }
    }
    $loopTrace = @($recruitmentLoop.trace)
    $offer = @($loopTrace[0].actionReceipt.data.offers | Where-Object { $_.available -and $_.cost -le $beforeRecruit.state.economy.gold } | Sort-Object cost | Select-Object -First 1)
    if ($offer.Count -ne 1) { throw 'The native recruitment view model returned no affordable available volunteer.' }
    $recruit = $loopTrace[1].actionReceipt
    $afterRecruit = $loopTrace[1].observationAfter
    $offerPayloadForwarded = ($loopTrace[1].previousActionReceipt.commandId -eq $loopTrace[0].actionReceipt.commandId -and @($loopTrace[1].previousActionReceipt.data.offers).Count -gt 0)
    $offerDecisionMatched = ($loopTrace[1].decision.action -eq 'recruit' -and $loopTrace[1].decision.arguments.OwnerId -eq $offer[0].ownerId -and $loopTrace[1].decision.arguments.TroopId -eq $offer[0].troopId -and [int]$loopTrace[1].decision.arguments.VolunteerSlot -eq [int]$offer[0].slot -and -not [bool]$loopTrace[1].decision.arguments.ConfirmPartySizeWarning)
    $recruitmentDecisionSummary = @(
        [ordered]@{ iteration = 1; action = $loopTrace[0].decision.action; nativeOfferCount = @($loopTrace[0].actionReceipt.data.offers).Count; receiptStatus = $loopTrace[0].actionReceipt.status },
        [ordered]@{ iteration = 2; previousReceiptAction = $loopTrace[1].previousActionReceipt.action; offerDataForwarded = $offerPayloadForwarded; action = $loopTrace[1].decision.action; selectedOwnerId = $loopTrace[1].decision.arguments.OwnerId; selectedTroopId = $loopTrace[1].decision.arguments.TroopId; selectedSlot = $loopTrace[1].decision.arguments.VolunteerSlot; receiptStatus = $recruit.status; membersAfter = $afterRecruit.state.party.members; goldAfter = $afterRecruit.state.economy.gold }
    )
    $invalidRecruit = Invoke-AgentCli 'recruit' @('-OwnerId', 'chronicle_missing_owner', '-TroopId', 'chronicle_missing_troop', '-VolunteerSlot', '0', '-CommandId', "$runPrefix-invalid-recruit", '-TimeoutSeconds', 15)
    $afterInvalid = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-after-invalid", '-TimeoutSeconds', $TimeoutSeconds)

    $capacitySeed = Invoke-AgentCli 'harnessSeedRecruitmentCapacityFixture' @('-CommandId', "$runPrefix-capacity-seed", '-TimeoutSeconds', $TimeoutSeconds)
    $capacityBefore = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-capacity-before", '-TimeoutSeconds', $TimeoutSeconds)
    if ([int]$capacityBefore.state.party.members -ne [int]$capacityBefore.state.party.sizeLimit) { throw 'Harness did not seed the disposable MainParty exactly to the Native size limit.' }
    $capacityOptions = Invoke-AgentCli 'recruitOptions' @('-CommandId', "$runPrefix-capacity-options", '-TimeoutSeconds', $TimeoutSeconds)
    $capacityOffer = @($capacityOptions.data.offers | Where-Object { $_.available -and [int]$_.cost -le [int]$capacityBefore.state.economy.gold } | Sort-Object cost | Select-Object -First 1)
    if ($capacityOffer.Count -ne 1 -or -not $capacityOptions.data.partySizeWarningForOne) { throw 'RecruitmentVM did not expose an affordable volunteer and a native capacity warning at the seeded limit.' }
    $unconfirmedCapacityRecruit = Invoke-AgentCli 'recruit' @('-OwnerId', [string]$capacityOffer[0].ownerId, '-TroopId', [string]$capacityOffer[0].troopId, '-VolunteerSlot', [string]$capacityOffer[0].slot, '-CommandId', "$runPrefix-capacity-no-consent", '-TimeoutSeconds', $TimeoutSeconds)
    $afterUnconfirmedCapacity = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-capacity-no-consent-state", '-TimeoutSeconds', $TimeoutSeconds)
    $offersAfterUnconfirmedCapacity = Invoke-AgentCli 'recruitOptions' @('-CommandId', "$runPrefix-capacity-no-consent-offers", '-TimeoutSeconds', $TimeoutSeconds)
    $unconfirmedCapacityRejectedWithoutMutation = (
        $unconfirmedCapacityRecruit.status -eq 'rejected' -and
        $unconfirmedCapacityRecruit.error -match 'explicit ConfirmPartySizeWarning=true' -and
        [int]$afterUnconfirmedCapacity.state.party.members -eq [int]$capacityBefore.state.party.members -and
        [int]$afterUnconfirmedCapacity.state.economy.gold -eq [int]$capacityBefore.state.economy.gold -and
        @($offersAfterUnconfirmedCapacity.data.offers | Where-Object { $_.available -and $_.ownerId -eq $capacityOffer[0].ownerId -and $_.troopId -eq $capacityOffer[0].troopId -and [int]$_.slot -eq [int]$capacityOffer[0].slot }).Count -eq 1
    )
    if (-not $unconfirmedCapacityRejectedWithoutMutation) { throw 'Unconfirmed Native over-limit recruitment changed MainParty, Gold, or the Notable volunteer slot.' }
    $previousCapacityProviderMode = $env:CHRONICLE_TEST_PROVIDER_MODE
    $env:CHRONICLE_TEST_PROVIDER_MODE = 'recruitment'
    try {
        $capacityLoopOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $decisionLoop -DecisionProviderPath $decisionProvider -MaxDecisions 2 -TimeoutSeconds $TimeoutSeconds -CommandPrefix "$runPrefix-capacity-loop" 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "Over-limit recruitment decision loop failed: $capacityLoopOutput" }
        $capacityLoop = $capacityLoopOutput | ConvertFrom-Json
    }
    finally {
        if ($null -eq $previousCapacityProviderMode) { Remove-Item Env:CHRONICLE_TEST_PROVIDER_MODE -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_TEST_PROVIDER_MODE = $previousCapacityProviderMode }
    }
    $capacityTrace = @($capacityLoop.trace)
    $capacityDecision = if ($capacityTrace.Count -ge 2) { $capacityTrace[1].decision } else { $null }
    $capacityRecruit = if ($capacityTrace.Count -ge 2) { $capacityTrace[1].actionReceipt } else { $null }
    $afterCapacityRecruit = if ($capacityTrace.Count -ge 2) { $capacityTrace[1].observationAfter } else { $null }
    $capacityWarningConfirmed = (
        $capacityDecision.action -eq 'recruit' -and
        [bool]$capacityDecision.arguments.ConfirmPartySizeWarning -and
        $capacityRecruit.status -eq 'completed' -and
        [bool]$capacityRecruit.data.nativeCapacityWarningRequired -and
        [bool]$capacityRecruit.data.nativeCapacityConfirmationAccepted -and
        $capacityRecruit.data.nativeCapacityConfirmationTitle -eq $capacityOptions.data.nativeCapacityWarningTitle -and
        [int]$afterCapacityRecruit.state.party.members -eq ([int]$capacityBefore.state.party.sizeLimit + 1) -and
        [int]$afterCapacityRecruit.state.economy.gold -eq ([int]$capacityBefore.state.economy.gold - [int]$capacityOffer[0].cost)
    )
    if (-not $capacityWarningConfirmed) { throw 'Native volunteer over-limit warning was not surfaced and explicitly accepted through its affirmative callback.' }

    $provisionTradeState = Open-NativeTownTrade 'provision-food'
    $foodOptions = Invoke-AgentCli 'foodOptions' @('-CommandId', "$runPrefix-food-options", '-TimeoutSeconds', $TimeoutSeconds)
    $foodOffer = @($foodOptions.data.offers | Where-Object { $_.stock -gt 0 -and $_.isTransferable -and $_.inventoryLogicUnitPrice -le $afterCapacityRecruit.state.economy.gold } | Sort-Object inventoryLogicUnitPrice | Select-Object -First 1)
    if ($foodOffer.Count -ne 1) { throw 'Native trade inventory contains no affordable food item.' }
    $provision = Invoke-AgentCli 'provision' @('-ItemViewModelId', [string]$foodOffer[0].viewModelItemId, '-Amount', '1', '-CommandId', "$runPrefix-provision", '-TimeoutSeconds', $TimeoutSeconds)
    $provisionCommit = Invoke-AgentCli 'tradeConfirm' @('-CommandId', "$runPrefix-provision-confirm", '-TimeoutSeconds', $TimeoutSeconds)
    $afterProvision = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-after-provision", '-TimeoutSeconds', $TimeoutSeconds)
    $sellTradeState = Open-NativeTownTrade 'sell-food'
    $tradeOptions = Invoke-AgentCli 'tradeOptions' @('-CommandId', "$runPrefix-trade-options", '-TimeoutSeconds', $TimeoutSeconds)
    $sellOffer = @($tradeOptions.data.sellOffers | Where-Object { $_.itemId -eq $foodOffer[0].itemId -and $_.modifierId -eq $foodOffer[0].modifierId -and $_.stock -gt 0 -and $_.isTransferable } | Select-Object -First 1)
    if ($sellOffer.Count -ne 1) { throw 'The acquired food item was not exposed as a player sell offer.' }
    $sell = Invoke-AgentCli 'trade' @('-Direction', 'sell', '-ItemViewModelId', [string]$sellOffer[0].viewModelItemId, '-InventorySide', [string]$sellOffer[0].inventorySide, '-Amount', '1', '-CommandId', "$runPrefix-sell", '-TimeoutSeconds', $TimeoutSeconds)
    $sellCommit = Invoke-AgentCli 'tradeConfirm' @('-CommandId', "$runPrefix-sell-confirm", '-TimeoutSeconds', $TimeoutSeconds)
    $afterSell = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-after-sell", '-TimeoutSeconds', $TimeoutSeconds)
    $invalidTradeState = Open-NativeTownTrade 'stale-sell'
    $invalidTrade = Invoke-AgentCli 'trade' @('-Direction', 'sell', '-ItemViewModelId', [string]$sellOffer[0].viewModelItemId, '-InventorySide', [string]$sellOffer[0].inventorySide, '-Amount', '1', '-CommandId', "$runPrefix-invalid-trade", '-TimeoutSeconds', '15')
    $afterInvalidTrade = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-after-invalid-trade", '-TimeoutSeconds', $TimeoutSeconds)
    $invalidTradeClose = Invoke-AgentCli 'tradeCancel' @('-CommandId', "$runPrefix-invalid-trade-close", '-TimeoutSeconds', $TimeoutSeconds)

    $menu = Invoke-AgentCli 'menu' @('-CommandId', "$runPrefix-menu", '-TimeoutSeconds', $TimeoutSeconds)
    $leave = Invoke-AgentCli 'menuSelect' @('-MenuId', [string]$menu.state.context.menuId, '-OptionId', 'town_leave', '-CommandId', "$runPrefix-leave", '-TimeoutSeconds', $TimeoutSeconds)
    $offMenuRecruitmentOptions = Invoke-AgentCli 'recruitOptions' @('-CommandId', "$runPrefix-off-menu-recruit", '-TimeoutSeconds', '15')
    $afterOffMenuRecruit = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-after-off-menu-recruit", '-TimeoutSeconds', $TimeoutSeconds)
    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$runPrefix-stop", '-TimeoutSeconds', $TimeoutSeconds)
    $fixtureHashAfter = (Get-FileHash $savePath -Algorithm SHA256).Hash

    $expectedMembers = [int]$beforeRecruit.state.party.members + 1
    $expectedGold = [int]$beforeRecruit.state.economy.gold - [int]$offer[0].cost
    $successVerified = $recruit.data.verified -and [int]$afterRecruit.state.party.members -eq $expectedMembers -and [int]$afterRecruit.state.economy.gold -eq $expectedGold
    $failureNoMutation = $invalidRecruit.status -eq 'rejected' -and [int]$afterInvalid.state.party.members -eq [int]$afterRecruit.state.party.members -and [int]$afterInvalid.state.economy.gold -eq [int]$afterRecruit.state.economy.gold
    $provisionVerified = ($provision.status -eq 'completed' -and $provisionCommit.data.postconditionPassed -and [int]$afterProvision.state.party.foodInventory -gt [int]$afterCapacityRecruit.state.party.foodInventory -and [int]$afterCapacityRecruit.state.economy.gold - [int]$afterProvision.state.economy.gold -eq [int]$provision.data.nativeTransactionAmount)
    $tradeVerified = ($sell.status -eq 'completed' -and $sellCommit.data.postconditionPassed -and [int]$afterSell.state.party.foodInventory -eq [int]$afterProvision.state.party.foodInventory - 1 -and [int]$afterProvision.state.economy.gold - [int]$afterSell.state.economy.gold -eq [int]$sellCommit.data.nativeTransactionAmount)
    $invalidTradeNoMutation = ($invalidTrade.status -eq 'rejected' -and [int]$afterInvalidTrade.state.party.foodInventory -eq [int]$afterSell.state.party.foodInventory -and [int]$afterInvalidTrade.state.economy.gold -eq [int]$afterSell.state.economy.gold -and $invalidTradeClose.data.returnedToMap)
    $offMenuRecruitmentRejectedWithoutMutation = ($leave.status -eq 'completed' -and $offMenuRecruitmentOptions.status -eq 'rejected' -and $offMenuRecruitmentOptions.error -match 'active Settlement GameMenu' -and $afterOffMenuRecruit.state.location.currentSettlementId -eq $null -and [int]$afterOffMenuRecruit.state.party.members -eq [int]$afterSell.state.party.members -and [int]$afterOffMenuRecruit.state.economy.gold -eq [int]$afterSell.state.economy.gold)
    $recruitmentRawClockModePreserved = ($beforeRecruit.state.context.timeControlMode -eq $recruit.timeControlMode -and $beforeRecruit.state.context.timeControlMode -eq $afterRecruit.state.context.timeControlMode)
    $capacityRawClockModePreserved = ($capacityBefore.state.context.timeControlMode -eq $capacityRecruit.timeControlMode -and $capacityBefore.state.context.timeControlMode -eq $afterCapacityRecruit.state.context.timeControlMode)
    $result = [ordered]@{
        ProcessId = $start.session.processId
        WindowLayout = $start.session.windowLayout
        Settlement = $target[0]
        RecruitmentMenuId = $beforeRecruit.state.context.menuId
        RecruitmentMenuOption = $recruitmentMenuOption[0]
        RecruitmentMenuContextValid = $recruitmentMenuContextValid
        Offer = $offer[0]
        RecruitReceipt = $recruit.data
        DecisionProviderKind = 'deterministic-test-only'
        RecruitmentDecisionSummary = $recruitmentDecisionSummary
        OfferDataForwardedToNextDecision = $offerPayloadForwarded
        OfferSelectionMatchedReceipt = $offerDecisionMatched
        CapacityFixture = $capacitySeed.data
        CapacityBefore = [ordered]@{ Members = $capacityBefore.state.party.members; Limit = $capacityBefore.state.party.sizeLimit; Gold = $capacityBefore.state.economy.gold }
        UnconfirmedCapacityRecruit = [ordered]@{ Status = $unconfirmedCapacityRecruit.status; Error = $unconfirmedCapacityRecruit.error }
        UnconfirmedCapacityRejectedWithoutMutation = $unconfirmedCapacityRejectedWithoutMutation
        CapacityRecruitmentDecision = [ordered]@{ Action = $capacityDecision.action; ConfirmPartySizeWarning = [bool]$capacityDecision.arguments.ConfirmPartySizeWarning; Receipt = $capacityRecruit.data }
        CapacityWarningConfirmed = $capacityWarningConfirmed
        AfterCapacityRecruit = [ordered]@{ Members = $afterCapacityRecruit.state.party.members; Gold = $afterCapacityRecruit.state.economy.gold }
        Before = [ordered]@{ Members = $beforeRecruit.state.party.members; Gold = $beforeRecruit.state.economy.gold }
        After = [ordered]@{ Members = $afterRecruit.state.party.members; Gold = $afterRecruit.state.economy.gold }
        RecruitmentClock = [ordered]@{ CampaignDayBefore = $beforeRecruit.campaignDay; CampaignDayAtAction = $recruit.campaignDay; CampaignDayAfterObservation = $afterRecruit.campaignDay; RawModeBefore = $beforeRecruit.state.context.timeControlMode; RawModeAfter = $afterRecruit.state.context.timeControlMode; RawModePreserved = $recruitmentRawClockModePreserved }
        CapacityRecruitmentClock = [ordered]@{ CampaignDayBefore = $capacityBefore.campaignDay; CampaignDayAtAction = $capacityRecruit.campaignDay; CampaignDayAfterObservation = $afterCapacityRecruit.campaignDay; RawModeBefore = $capacityBefore.state.context.timeControlMode; RawModeAfter = $afterCapacityRecruit.state.context.timeControlMode; RawModePreserved = $capacityRawClockModePreserved }
        InvalidRecruit = [ordered]@{ Status = $invalidRecruit.status; Error = $invalidRecruit.error }
        InvalidAttemptNoMutation = $failureNoMutation
        FoodOffer = $foodOffer[0]
        ProvisionReceipt = $provision.data
        ProvisionCommit = $provisionCommit.data
        AfterProvision = [ordered]@{ FoodInventory = $afterProvision.state.party.foodInventory; Gold = $afterProvision.state.economy.gold }
        SellOffer = $sellOffer[0]
        SellReceipt = $sell.data
        SellCommit = $sellCommit.data
        AfterSell = [ordered]@{ FoodInventory = $afterSell.state.party.foodInventory; Gold = $afterSell.state.economy.gold }
        InvalidTrade = [ordered]@{ Status = $invalidTrade.status; Error = $invalidTrade.error; Close = $invalidTradeClose.data }
        InvalidTradeNoMutation = $invalidTradeNoMutation
        OffMenuRecruitmentAttempt = [ordered]@{ Status = $offMenuRecruitmentOptions.status; Error = $offMenuRecruitmentOptions.error }
        OffMenuRecruitmentRejectedWithoutMutation = $offMenuRecruitmentRejectedWithoutMutation
        ProvisionVerified = $provisionVerified
        TradeVerified = $tradeVerified
        LeaveReceipt = [ordered]@{ Status = $leave.status; CurrentSettlementId = $leave.state.location.currentSettlementId; MenuId = $leave.state.context.menuId }
        SuccessfulRecruitVerified = $successVerified
        FixtureUnchanged = $fixtureHashBefore -eq $fixtureHashAfter
        ProcessStopped = $stop.processStopped
    }
    $result.Passed = ($recruitmentMenuContextValid -and $successVerified -and $offerPayloadForwarded -and $offerDecisionMatched -and $failureNoMutation -and $unconfirmedCapacityRejectedWithoutMutation -and $capacityWarningConfirmed -and $recruitmentRawClockModePreserved -and $capacityRawClockModePreserved -and $provisionVerified -and $tradeVerified -and $invalidTradeNoMutation -and $offMenuRecruitmentRejectedWithoutMutation -and $leave.status -eq 'completed' -and $result.FixtureUnchanged -and $result.ProcessStopped)
    $result | ConvertTo-Json -Depth 10
    if (-not $result.Passed) { exit 1 }
}
finally {
    if (Test-Path $sessionPath) {
        try { Invoke-AgentCli 'stop' @('-CommandId', "$runPrefix-cleanup", '-TimeoutSeconds', '15') | Out-Null } catch { }
    }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
