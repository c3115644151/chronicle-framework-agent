#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$resultPath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP 'TradeTransactionResult.json' } else { Join-Path (Split-Path -Parent $PSScriptRoot) 'TestResults\ManualTradeTransactions\TradeTransactionResult.json' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$prefix = 'trade-v-' + (Get-Date -Format 'yyyyMMddHHmmssfff')

if (-not (Test-Path -LiteralPath $savePath)) { throw "Trade transaction fixture not found: $LoadSaveName" }
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

function Get-TradeState([string]$Suffix) {
    return Invoke-AgentCli 'state' @('-CommandId', "$prefix-$Suffix")
}

function Open-NativeTrade([string]$Suffix) {
    $menu = Invoke-AgentCli 'menu' @('-CommandId', "$prefix-$Suffix-menu")
    if ($menu.state.context.menuId -ne 'town') { throw "Trade fixture expected the Town menu, got '$($menu.state.context.menuId)'" }
    $option = @($menu.state.availableMenuOptions | Where-Object { $_.id -eq 'trade' -and $_.available -and $_.enabled } | Select-Object -First 1)
    if ($option.Count -ne 1) { throw 'The native Town menu did not expose an enabled Trade entry.' }
    $open = Invoke-AgentCli 'menuSelect' @('-MenuId', 'town', '-OptionId', [string]$option[0].id, '-CommandId', "$prefix-$Suffix-open")
    $state = Get-TradeState "$Suffix-state"
    if ($open.status -ne 'completed' -or $state.state.context.gameState -ne 'InventoryState' -or $state.state.inventoryScreen.mode -ne 'Trade')
        { throw 'Native Town trade did not open the expected Trade-mode InventoryState.' }
    return [pscustomobject]@{ Menu = $menu; Open = $open; State = $state }
}

function Find-Offer($Offers, [string]$ItemId = '', [string]$ModifierId = '', [switch]$FoodOnly) {
    $matchElement = -not [string]::IsNullOrWhiteSpace($ItemId)
    $matching = @($Offers | Where-Object {
        $_.isTransferable -and [int]$_.stock -gt 0 -and
        (-not $FoodOnly -or [bool]$_.isFood) -and
        (-not $matchElement -or ([string]$_.itemId -eq $ItemId -and [string]$_.modifierId -eq $ModifierId))
    })
    if ($matching.Count -eq 0) { return $null }
    return @($matching | Sort-Object inventoryLogicUnitPrice | Select-Object -First 1)[0]
}

try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $initial = Get-TradeState 'initial'
    $target = @($initial.state.nearbySettlements | Where-Object { $_.type -eq 'town' -and -not $_.hostile -and $_.distance -gt 1.0 } | Sort-Object distance | Select-Object -First 1)
    if ($target.Count -ne 1) { throw 'No safe visible Town exists in the disposable trade fixture.' }
    $move = Invoke-AgentCli 'move' @('-SettlementId', [string]$target[0].id, '-CommandId', "$prefix-move")
    if ($move.status -ne 'completed' -or $move.state.location.targetSettlementId -ne $target[0].id) { throw 'Native Town movement did not accept the current visible target.' }
    $arrival = Wait-ForAgentSettlementArrival -CliPath $cli -SettlementId ([string]$target[0].id) -CommandPrefix "$prefix-arrival" -TimeoutSeconds $TimeoutSeconds
    if ($arrival.state.location.currentSettlementId -ne $target[0].id) { throw 'MainParty did not reach the selected Town.' }

    $timeModeAtTownMenu = [string]$arrival.state.context.timeControlMode
    $activeTrade = Open-NativeTrade 'active'
    $activeOptions = Invoke-AgentCli 'tradeOptions' @('-CommandId', "$prefix-active-options")
    $activeBuyOffer = Find-Offer $activeOptions.data.buyOffers
    if ($null -eq $activeBuyOffer) { throw 'The Active-mode Native Trade VM exposed no buy candidate for the clock-boundary transaction.' }
    $activeBuyDraft = Invoke-AgentCli 'trade' @('-Direction', 'buy', '-ItemViewModelId', [string]$activeBuyOffer.viewModelItemId, '-InventorySide', [string]$activeBuyOffer.inventorySide, '-Amount', '1', '-CommandId', "$prefix-active-buy")
    if ($activeBuyDraft.status -ne 'completed' -or -not $activeBuyDraft.data.nativeCanCompleteTransaction) { throw 'Active-mode Native Trade buy did not produce a completable draft.' }
    $activeBuyCommit = Invoke-AgentCli 'tradeConfirm' @('-CommandId', "$prefix-active-buy-done")
    $activeBuyAfter = Get-TradeState 'active-buy-after'
    if (-not $activeBuyCommit.data.postconditionPassed) { throw 'Active-mode Native Trade buy did not commit through the Native Done path.' }
    $activeSellTrade = Open-NativeTrade 'active-sell'
    $activeSellOptions = Invoke-AgentCli 'tradeOptions' @('-CommandId', "$prefix-active-sell-options")
    $activeSellOffer = Find-Offer $activeSellOptions.data.sellOffers $activeBuyOffer.itemId $activeBuyOffer.modifierId
    if ($null -eq $activeSellOffer) { throw 'Active-mode Native Trade did not expose the purchased EquipmentElement for sell-back.' }
    $activeSellDraft = Invoke-AgentCli 'trade' @('-Direction', 'sell', '-ItemViewModelId', [string]$activeSellOffer.viewModelItemId, '-InventorySide', [string]$activeSellOffer.inventorySide, '-Amount', '1', '-CommandId', "$prefix-active-sell")
    if ($activeSellDraft.status -ne 'completed' -or -not $activeSellDraft.data.nativeCanCompleteTransaction) { throw 'Active-mode Native Trade sell did not produce a completable draft.' }
    $activeSellCommit = Invoke-AgentCli 'tradeConfirm' @('-CommandId', "$prefix-active-sell-done")
    $activeSellAfter = Get-TradeState 'active-sell-after'
    if (-not $activeSellCommit.data.postconditionPassed) { throw 'Active-mode Native Trade sell did not commit through the Native Done path.' }
    $activeTransactionsStable = (
        $activeBuyDraft.data.timeControlModeBefore -eq $activeBuyDraft.data.timeControlModeAfter -and
        $activeBuyCommit.data.timeControlModeBefore -eq $activeBuyCommit.data.timeControlModeAfter -and
        $activeSellDraft.data.timeControlModeBefore -eq $activeSellDraft.data.timeControlModeAfter -and
        $activeSellCommit.data.timeControlModeBefore -eq $activeSellCommit.data.timeControlModeAfter -and
        $activeBuyDraft.data.timeControlModeBefore -eq $timeModeAtTownMenu -and
        $activeBuyAfter.state.context.timeControlMode -eq $timeModeAtTownMenu -and
        [double]$activeBuyAfter.state.campaignDay -ge [double]$activeTrade.State.state.campaignDay -and
        [double]$activeSellAfter.state.campaignDay -ge [double]$activeBuyAfter.state.campaignDay
    )
    $activeBeforeWait = Get-TradeState 'active-before-wait'
    Start-Sleep -Seconds 2
    $activeAfterWait = Get-TradeState 'active-after-wait'
    $activeQueryStable = (
        $activeOptions.status -eq 'completed' -and
        $activeBeforeWait.state.context.timeControlMode -eq $activeTrade.State.state.context.timeControlMode -and
        $activeAfterWait.state.context.timeControlMode -eq $activeTrade.State.state.context.timeControlMode -and
        [double]$activeAfterWait.state.campaignDay -ge [double]$activeBeforeWait.state.campaignDay
    )
    $activeCloseTrade = Open-NativeTrade 'active-close'
    $activeClose = Invoke-AgentCli 'tradeCancel' @('-CommandId', "$prefix-active-close")
    $mapAfterActiveClose = Get-TradeState 'active-map-after-close'
    $activeCloseStable = ($activeClose.data.returnedToMap -and $mapAfterActiveClose.state.context.gameState -eq 'MapState' -and $mapAfterActiveClose.state.context.timeControlMode -eq $activeTrade.State.state.context.timeControlMode)
    $baseline = Get-TradeState 'native-town-baseline'

    $buyTrade = Open-NativeTrade 'buy'
    $buyOptions = Invoke-AgentCli 'tradeOptions' @('-CommandId', "$prefix-buy-options")
    if ($buyOptions.status -ne 'completed' -or $buyOptions.data.inventoryMode -ne 'Trade') { throw 'tradeOptions did not read the active native Trade VM.' }
    $modifiedMarketOffers = @($buyOptions.data.buyOffers | Where-Object {
        $_.isTransferable -and [int]$_.stock -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$_.modifierId) -and [int]$_.inventoryLogicUnitPrice -le [int]$buyOptions.data.playerGold
    } | Sort-Object inventoryLogicUnitPrice)
    $buyOffer = if ($modifiedMarketOffers.Count -gt 0) { $modifiedMarketOffers[0] } else { $null }
    if ($null -eq $buyOffer -or [int]$buyOffer.inventoryLogicUnitPrice -gt [int]$buyOptions.data.playerGold)
        { throw 'The Native Trade VM exposed no transferable affordable non-empty modifier market item in the disposable Town.' }
    if ([string]::IsNullOrWhiteSpace([string]$buyOffer.modifierId)) { throw 'The trade variant fixture must use an exact non-empty item modifier.' }
    $nativeQuoteMatchesLogic = [int]$buyOffer.nativeItemCost -eq [int]$buyOffer.inventoryLogicUnitPrice

    $rumorGood = @($buyOptions.data.buyOffers | Where-Object {
        $_.nativeTooltipType -eq 'Goods' -and $_.isFood -and $_.isTransferable -and [int]$_.stock -gt 0 -and [int]$_.inventoryLogicUnitPrice -le [int]$buyOptions.data.playerGold
    } | Sort-Object inventoryLogicUnitPrice | Select-Object -First 1)
    if ($rumorGood.Count -ne 1) { throw 'The disposable Town exposed no affordable Native Goods candidate for the trade rumor observation.' }
    $rumorFixture = Invoke-AgentCli 'harnessSeedTradeRumorFixture' @('-ItemViewModelId', [string]$rumorGood[0].viewModelItemId, '-InventorySide', 'OtherInventory', '-CommandId', "$prefix-rumor-fixture")
    $rumorBefore = Get-TradeState 'rumor-before-read'
    $marketRumors = Invoke-AgentCli 'tradeRumors' @('-ItemViewModelId', [string]$rumorGood[0].viewModelItemId, '-InventorySide', 'OtherInventory', '-CommandId', "$prefix-market-rumors")
    $marketNativeTooltip = Invoke-AgentCli 'harnessTradeRumorTooltipDiagnostics' @('-ItemViewModelId', [string]$rumorGood[0].viewModelItemId, '-InventorySide', 'OtherInventory', '-CommandId', "$prefix-market-tooltip")
    $rumorAfter = Get-TradeState 'rumor-after-read'
    $marketHintTexts = @($marketRumors.data.hints | ForEach-Object { [string]$_.nativeText })
    $marketTooltipTexts = @($marketNativeTooltip.data.hintTexts | ForEach-Object { [string]$_ })
    $marketTooltipParity = ($marketRumors.status -eq 'completed' -and [bool]$marketRumors.data.applicable -and $marketHintTexts.Count -ge 2 -and (($marketHintTexts -join "`n") -ceq ($marketTooltipTexts -join "`n")))
    $seededRumorIds = @([string]$rumorFixture.data.buyRumorTownId, [string]$rumorFixture.data.sellRumorTownId)
    $seededHintsVisible = @($marketRumors.data.hints | Where-Object { $_.settlementId -in $seededRumorIds }).Count -eq 2
    $expiredRumorFiltered = @($marketRumors.data.hints | Where-Object { $_.settlementId -eq [string]$rumorFixture.data.expiredRumorTownId }).Count -eq 0
    $currentTownRumorsExcluded = @($marketRumors.data.hints | Where-Object { $_.settlementId -eq [string]$marketRumors.data.settlementId }).Count -eq 0
    $marketRumorReadNoMutation = (
        [int]$rumorBefore.state.economy.gold -eq [int]$rumorAfter.state.economy.gold -and
        [int]$rumorBefore.state.party.itemCount -eq [int]$rumorAfter.state.party.itemCount -and
        [string]$rumorBefore.state.context.timeControlMode -eq [string]$rumorAfter.state.context.timeControlMode -and
        [double]$rumorBefore.state.campaignDay -eq [double]$rumorAfter.state.campaignDay -and
        [string]$rumorBefore.state.location.currentSettlementId -eq [string]$rumorAfter.state.location.currentSettlementId
    )
    $staleRumors = Invoke-AgentCli 'tradeRumors' @('-ItemViewModelId', 'harness_unknown_item', '-InventorySide', 'OtherInventory', '-CommandId', "$prefix-stale-rumors") 15
    $allTradeCandidates = @($buyOptions.data.buyOffers) + @($buyOptions.data.sellOffers)
    $nonGoodsCandidate = @($allTradeCandidates | Where-Object { $_.nativeTooltipType -ne 'Goods' -and $_.stock -gt 0 } | Select-Object -First 1)
    $nonGoodsRumors = if ($nonGoodsCandidate.Count -eq 1) {
        Invoke-AgentCli 'tradeRumors' @('-ItemViewModelId', [string]$nonGoodsCandidate[0].viewModelItemId, '-InventorySide', [string]$nonGoodsCandidate[0].inventorySide, '-CommandId', "$prefix-non-goods-rumors")
    } else { $null }
    $nonGoodsRejectedAsRumorSource = ($null -ne $nonGoodsRumors -and $nonGoodsRumors.status -eq 'completed' -and -not [bool]$nonGoodsRumors.data.applicable -and @($nonGoodsRumors.data.hints).Count -eq 0)

    $overstock = Invoke-AgentCli 'trade' @('-Direction', 'buy', '-ItemViewModelId', [string]$buyOffer.viewModelItemId, '-InventorySide', [string]$buyOffer.inventorySide, '-Amount', [string]([int]$buyOffer.stock + 1), '-CommandId', "$prefix-overstock") 15
    $afterOverstock = Invoke-AgentCli 'tradeOptions' @('-CommandId', "$prefix-overstock-after")
    $sameOverstockOffer = @($afterOverstock.data.buyOffers | Where-Object { $_.viewModelItemId -eq $buyOffer.viewModelItemId } | Select-Object -First 1)
    $overstockRejected = ($overstock.status -eq 'rejected' -and [int]$afterOverstock.data.playerGold -eq [int]$buyOptions.data.playerGold -and $sameOverstockOffer.Count -eq 1 -and [int]$sameOverstockOffer[0].stock -eq [int]$buyOffer.stock)
    if (-not $overstockRejected) { throw 'An amount greater than current native market stock was not rejected without mutation.' }

    $wrongSide = Invoke-AgentCli 'trade' @('-Direction', 'buy', '-ItemViewModelId', [string]$buyOffer.viewModelItemId, '-InventorySide', 'PlayerInventory', '-Amount', '1', '-CommandId', "$prefix-wrong-side") 15
    $afterWrongSide = Invoke-AgentCli 'tradeOptions' @('-CommandId', "$prefix-wrong-side-after")
    $wrongSideRejected = ($wrongSide.status -eq 'rejected' -and -not [bool]$afterWrongSide.data.hasPendingChanges -and [int]$afterWrongSide.data.playerGold -eq [int]$buyOptions.data.playerGold)
    if (-not $wrongSideRejected) { throw 'A market offer addressed as PlayerInventory was not rejected without leaving a Trade draft.' }

    $unaffordableOffer = @($buyOptions.data.buyOffers | Where-Object {
        $_.isTransferable -and [int]$_.stock -gt 0 -and [int]$_.nativeItemCost -gt [int]$buyOptions.data.playerGold
    } | Sort-Object nativeItemCost | Select-Object -First 1)
    $unaffordableResult = $null
    $unaffordableRollback = $null
    $unaffordableRejected = $false
    if ($unaffordableOffer.Count -gt 0) {
        $unaffordableResult = Invoke-AgentCli 'trade' @('-Direction', 'buy', '-ItemViewModelId', [string]$unaffordableOffer[0].viewModelItemId, '-InventorySide', [string]$unaffordableOffer[0].inventorySide, '-Amount', '1', '-CommandId', "$prefix-insufficient-gold") 15
        $afterUnaffordable = Get-TradeState 'insufficient-gold-after'
        $unaffordableGoldAfter = [int]$afterUnaffordable.state.economy.gold
        $unaffordableItemCountAfter = [int]$afterUnaffordable.state.party.itemCount
        $unaffordableRejected = ($unaffordableResult.status -eq 'rejected' -and $afterUnaffordable.state.context.gameState -eq 'MapState' -and $unaffordableGoldAfter -eq [int]$buyOptions.data.playerGold -and $unaffordableItemCountAfter -eq [int]$buyOptions.data.playerItemCount)
        [ordered]@{ Candidate = $unaffordableOffer[0]; Result = $unaffordableResult; Rollback = $unaffordableResult.message; GoldAfter = $unaffordableGoldAfter; ItemCountAfter = $unaffordableItemCountAfter; ReturnedToMap = ($afterUnaffordable.state.context.gameState -eq 'MapState') } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding UTF8
        if (-not $unaffordableRejected) { throw 'An unaffordable Native market offer changed Gold or left an uncommitted draft after cleanup.' }
    }
    else { throw 'The Town Native Trade VM exposed no over-budget candidate for the insufficient-gold test.' }

    $capacityBaseline = Get-TradeState 'capacity-baseline'
    $capacityTrade = Open-NativeTrade 'capacity'
    $capacityOptions = Invoke-AgentCli 'tradeOptions' @('-CommandId', "$prefix-capacity-options")
    $overCapacityOffers = @($capacityOptions.data.buyOffers | Where-Object {
        $_.isTransferable -and [int]$_.stock -gt 0 -and
        [double]$_.unitWeight -gt [double]$capacityBaseline.state.party.cargoCapacity -and
        [int]$_.nativeItemCost -le [int]$capacityOptions.data.playerGold
    } | Sort-Object nativeItemCost | Select-Object -First 1)
    if ($overCapacityOffers.Count -eq 0) { throw 'The fixture had no affordable item heavier than the MainParty capacity for the native capacity rule check.' }
    $capacityAttempt = Invoke-AgentCli 'trade' @('-Direction', 'buy', '-ItemViewModelId', [string]$overCapacityOffers[0].viewModelItemId, '-InventorySide', [string]$overCapacityOffers[0].inventorySide, '-Amount', '1', '-CommandId', "$prefix-over-capacity") 15
    $capacityRollback = $null
    if ($capacityAttempt.status -eq 'completed') {
        $capacityDraftState = Invoke-AgentCli 'tradeOptions' @('-CommandId', "$prefix-over-capacity-state")
        if ($capacityDraftState.data.hasPendingChanges) { $capacityRollback = Invoke-AgentCli 'tradeCancelChanges' @('-CommandId', "$prefix-over-capacity-cancel") }
        else { throw 'An over-capacity purchase was accepted without a visible native draft to cancel.' }
    }
    $afterCapacity = Get-TradeState 'capacity-after'
    $capacityRuleObserved = (
        ($capacityAttempt.status -eq 'rejected' -or [bool]$capacityAttempt.data.nativeCanCompleteTransaction) -and
        $afterCapacity.state.context.gameState -eq 'MapState' -and
        [int]$afterCapacity.state.economy.gold -eq [int]$capacityBaseline.state.economy.gold -and
        [int]$afterCapacity.state.party.itemCount -eq [int]$capacityBaseline.state.party.itemCount
    )
    if (-not $capacityRuleObserved) { throw 'The overweight purchase path neither matched a Native completion decision nor returned the fixture to an unchanged state.' }

    $cancelDraftTrade = Open-NativeTrade 'cancel-draft'
    $cancelDraft = Invoke-AgentCli 'trade' @('-Direction', 'buy', '-ItemViewModelId', [string]$buyOffer.viewModelItemId, '-InventorySide', [string]$buyOffer.inventorySide, '-Amount', '1', '-CommandId', "$prefix-cancel-draft")
    if ($cancelDraft.status -ne 'completed' -or -not $cancelDraft.data.nativeCanCompleteTransaction) { throw 'Native market buy did not create a completable VM draft for the cancel test.' }
    $cancel = Invoke-AgentCli 'tradeCancelChanges' @('-CommandId', "$prefix-cancel-confirm")
    $afterCancel = Get-TradeState 'after-cancel'
    $cancelNoMutation = ($cancel.status -eq 'completed' -and $cancel.data.discardConfirmed -and $cancel.data.returnedToMap -and [int]$afterCancel.state.economy.gold -eq [int]$baseline.state.economy.gold -and [int]$afterCancel.state.party.itemCount -eq [int]$baseline.state.party.itemCount)
    if (-not $cancelNoMutation) { throw 'Native Trade Cancel inquiry did not roll back the draft without a persistent inventory/gold change.' }

    $buyTrade = Open-NativeTrade 'buy-commit'
    $buyOptions = Invoke-AgentCli 'tradeOptions' @('-CommandId', "$prefix-buy-options-current")
    $buyOffer = Find-Offer $buyOptions.data.buyOffers $buyOffer.itemId $buyOffer.modifierId
    if ($null -eq $buyOffer) { throw 'The same EquipmentElement was not present as a fresh Native market candidate after the canceled draft.' }
    $buyDraft = Invoke-AgentCli 'trade' @('-Direction', 'buy', '-ItemViewModelId', [string]$buyOffer.viewModelItemId, '-InventorySide', [string]$buyOffer.inventorySide, '-Amount', '1', '-CommandId', "$prefix-buy-draft")
    if ($buyDraft.status -ne 'completed' -or -not $buyDraft.data.nativeCanCompleteTransaction) { throw 'Native trade buy draft was rejected or disabled.' }
    $buyPreview = Invoke-AgentCli 'tradeOptions' @('-CommandId', "$prefix-buy-preview")
    $buyCommit = Invoke-AgentCli 'tradeConfirm' @('-CommandId', "$prefix-buy-confirm")
    $afterBuy = Get-TradeState 'after-buy'
    if (-not $buyCommit.data.postconditionPassed -or [int]$buyCommit.data.amount -ne 1) { throw 'Native Trade Done did not commit the buy and matching Town/Party changes.' }

    $sellTrade = Open-NativeTrade 'sell'
    $sellOptions = Invoke-AgentCli 'tradeOptions' @('-CommandId', "$prefix-sell-options")
    $sellOffer = Find-Offer $sellOptions.data.sellOffers $buyOffer.itemId $buyOffer.modifierId
    if ($null -eq $sellOffer) { throw 'The exact purchased EquipmentElement was not shown as a Native PlayerInventory sell candidate.' }
    $sellDraft = Invoke-AgentCli 'trade' @('-Direction', 'sell', '-ItemViewModelId', [string]$sellOffer.viewModelItemId, '-InventorySide', [string]$sellOffer.inventorySide, '-Amount', '1', '-CommandId', "$prefix-sell-draft")
    if ($sellDraft.status -ne 'completed' -or -not $sellDraft.data.nativeCanCompleteTransaction) { throw 'Native trade sell draft was rejected or disabled.' }
    $sellPreview = Invoke-AgentCli 'tradeOptions' @('-CommandId', "$prefix-sell-preview")
    $sellCommit = Invoke-AgentCli 'tradeConfirm' @('-CommandId', "$prefix-sell-confirm")
    $afterSell = Get-TradeState 'after-sell'
    if (-not $sellCommit.data.postconditionPassed -or [int]$sellCommit.data.amount -ne 1) { throw 'Native Trade Done did not commit the sell and matching Town/Party changes.' }

    $rumorGoodsBuyTrade = Open-NativeTrade 'rumor-goods-buy'
    $rumorGoodsBuyOptions = Invoke-AgentCli 'tradeOptions' @('-CommandId', "$prefix-rumor-goods-buy-options")
    $rumorGoodsBuyOffer = Find-Offer $rumorGoodsBuyOptions.data.buyOffers ([string]$rumorGood[0].itemId) ([string]$rumorGood[0].modifierId)
    if ($null -eq $rumorGoodsBuyOffer) { throw 'The Native Goods item used for rumor observation was not available for the side parity transaction.' }
    $rumorGoodsBuyDraft = Invoke-AgentCli 'trade' @('-Direction', 'buy', '-ItemViewModelId', [string]$rumorGoodsBuyOffer.viewModelItemId, '-InventorySide', 'OtherInventory', '-Amount', '1', '-CommandId', "$prefix-rumor-goods-buy-draft")
    $rumorGoodsBuyCommit = Invoke-AgentCli 'tradeConfirm' @('-CommandId', "$prefix-rumor-goods-buy-confirm")
    if (-not $rumorGoodsBuyCommit.data.postconditionPassed) { throw 'The Native Trade VM could not buy the Goods item needed to validate its PlayerInventory tooltip.' }
    $rumorGoodsSellTrade = Open-NativeTrade 'rumor-goods-sell'
    $rumorGoodsSellOptions = Invoke-AgentCli 'tradeOptions' @('-CommandId', "$prefix-rumor-goods-sell-options")
    $rumorGoodsSellOffer = Find-Offer $rumorGoodsSellOptions.data.sellOffers ([string]$rumorGood[0].itemId) ([string]$rumorGood[0].modifierId)
    if ($null -eq $rumorGoodsSellOffer) { throw 'Bought Goods item was not present in the current PlayerInventory side.' }
    $playerRumors = Invoke-AgentCli 'tradeRumors' @('-ItemViewModelId', [string]$rumorGoodsSellOffer.viewModelItemId, '-InventorySide', 'PlayerInventory', '-CommandId', "$prefix-player-rumors")
    $playerNativeTooltip = Invoke-AgentCli 'harnessTradeRumorTooltipDiagnostics' @('-ItemViewModelId', [string]$rumorGoodsSellOffer.viewModelItemId, '-InventorySide', 'PlayerInventory', '-CommandId', "$prefix-player-tooltip")
    $playerHintTexts = @($playerRumors.data.hints | ForEach-Object { [string]$_.nativeText })
    $playerTooltipTexts = @($playerNativeTooltip.data.hintTexts | ForEach-Object { [string]$_ })
    $playerTooltipParity = ($playerRumors.status -eq 'completed' -and [bool]$playerRumors.data.applicable -and $playerHintTexts.Count -ge 2 -and (($playerHintTexts -join "`n") -ceq ($playerTooltipTexts -join "`n")))
    $rumorGoodsSellDraft = Invoke-AgentCli 'trade' @('-Direction', 'sell', '-ItemViewModelId', [string]$rumorGoodsSellOffer.viewModelItemId, '-InventorySide', 'PlayerInventory', '-Amount', '1', '-CommandId', "$prefix-rumor-goods-sell-draft")
    $rumorGoodsSellCommit = Invoke-AgentCli 'tradeConfirm' @('-CommandId', "$prefix-rumor-goods-sell-confirm")
    if (-not $rumorGoodsSellCommit.data.postconditionPassed) { throw 'The Native Trade VM could not complete the PlayerInventory side rollback transaction.' }
    $afterSell = Get-TradeState 'after-rumor-round-trip'
    $rumorEmptyTrade = Open-NativeTrade 'rumor-empty'
    $rumorQueryOutsideTrade = Invoke-AgentCli 'tradeCancel' @('-CommandId', "$prefix-rumor-close")
    $rumorOutsideState = Invoke-AgentCli 'tradeRumors' @('-ItemViewModelId', [string]$rumorGoodsSellOffer.viewModelItemId, '-InventorySide', 'PlayerInventory', '-CommandId', "$prefix-rumor-outside-state") 15
    $rumorOutsideTradeRejected = ($rumorOutsideState.status -eq 'rejected' -and $rumorQueryOutsideTrade.data.returnedToMap)

    $staleTrade = Open-NativeTrade 'stale'
    $staleItem = Invoke-AgentCli 'trade' @('-Direction', 'sell', '-ItemViewModelId', [string]$sellOffer.viewModelItemId, '-InventorySide', [string]$sellOffer.inventorySide, '-Amount', '1', '-CommandId', "$prefix-stale-item") 15
    $staleOptions = Invoke-AgentCli 'tradeOptions' @('-CommandId', "$prefix-stale-options")
    $staleRejected = ($staleItem.status -eq 'rejected' -and [int]$staleOptions.data.playerGold -eq [int]$afterSell.state.economy.gold)
    $staleClose = Invoke-AgentCli 'tradeCancel' @('-CommandId', "$prefix-stale-close")
    $partyDataAfterTransactions = Get-TradeState 'party-after-transactions'
    $tradeOutsideNativeState = Invoke-AgentCli 'trade' @('-Direction', 'buy', '-ItemViewModelId', [string]$buyOffer.viewModelItemId, '-InventorySide', 'OtherInventory', '-Amount', '1', '-CommandId', "$prefix-outside-trade-state") 15
    $afterOutsideNativeState = Get-TradeState 'outside-trade-state-after'
    $tradeRequiresNativeState = ($tradeOutsideNativeState.status -eq 'rejected' -and $afterOutsideNativeState.state.context.gameState -eq 'MapState' -and [int]$afterOutsideNativeState.state.economy.gold -eq [int]$afterSell.state.economy.gold -and [int]$afterOutsideNativeState.state.party.itemCount -eq [int]$afterSell.state.party.itemCount)
    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-stop") 30
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash

    $assertions = [ordered]@{
        TownMenuOpenedNativeTradeInventoryState = ($buyTrade.Open.status -eq 'completed' -and $buyTrade.State.state.context.gameState -eq 'InventoryState' -and $buyTrade.State.state.inventoryScreen.mode -eq 'Trade')
        NativeTownTradeBuySellPreserveArrivalClockMode = [bool]$activeTransactionsStable
        NativeTradeQueryPreservesClockAndNaturalDate = [bool]$activeQueryStable
        NativeTradeCloseReturnsToTownWithoutClockWrite = [bool]$activeCloseStable
        NativeTradeQuoteMatchesInventoryLogic = [bool]$nativeQuoteMatchesLogic
        MarketGoodsRumorsMatchNativeItemMenuVM = [bool]$marketTooltipParity
        PlayerGoodsRumorsMatchNativeItemMenuVM = [bool]$playerTooltipParity
        SeededBuyAndSellRumorsVisibleFromObservedCandidate = [bool]$seededHintsVisible
        ExpiredRumorFilteredByNativeBehavior = [bool]$expiredRumorFiltered
        CurrentTownRumorExcluded = [bool]$currentTownRumorsExcluded
        TradeRumorReadsDoNotMutateWorldOrClock = [bool]$marketRumorReadNoMutation
        StaleTradeRumorCandidateRejected = ($staleRumors.status -eq 'rejected')
        NonGoodsDoNotExposeNativeTradeRumors = [bool]$nonGoodsRejectedAsRumorSource
        TradeRumorQueryRequiresActiveTradeState = [bool]$rumorOutsideTradeRejected
        NativeTradeOfferPreservesNonEmptyModifier = -not [string]::IsNullOrWhiteSpace([string]$buyOffer.modifierId)
        OverMarketStockRejectedWithoutGoldOrMarketMutation = [bool]$overstockRejected
        WrongInventorySideRejectedWithoutDraft = [bool]$wrongSideRejected
        InsufficientGoldRejectedAndNativeDraftRolledBack = [bool]$unaffordableRejected
        NativeCapacityRuleObservedWithoutPersistentMutation = [bool]$capacityRuleObserved
        NativeCancelInquiryDiscardsUncommittedBuy = [bool]$cancelNoMutation
        NativeBuyTransferAndDoneVerified = [bool]$buyCommit.data.postconditionPassed
        NativeSellTransferAndDoneVerified = [bool]$sellCommit.data.postconditionPassed
        StaleSellCandidateRejected = [bool]$staleRejected
        TradeRequiresActiveNativeTradeState = [bool]$tradeRequiresNativeState
        MapStateRestoredAtTown = ($staleClose.data.returnedToMap -and $partyDataAfterTransactions.state.context.gameState -eq 'MapState' -and $partyDataAfterTransactions.state.location.currentSettlementId -eq $target[0].id)
        FixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = [bool]$stop.processStopped
    }
    $failedAssertions = @($assertions.Keys | Where-Object { -not [bool]$assertions[$_] })
    $result = [ordered]@{
        Settlement = $target[0]
        TownClock = [ordered]@{ TimeModeAtTownMenu = $timeModeAtTownMenu; Open = $activeTrade.Open.data; TradeStateTimeMode = $activeTrade.State.state.context.timeControlMode; Options = $activeOptions.data; BuyDraft = $activeBuyDraft.data; Buy = $activeBuyCommit.data; SellDraft = $activeSellDraft.data; Sell = $activeSellCommit.data; ModeAfterWait = $activeAfterWait.state.context.timeControlMode; DayBefore = $activeBeforeWait.state.campaignDay; DayAfter = $activeAfterWait.state.campaignDay; Close = $activeClose.data }
        Buy = [ordered]@{ Offer = $buyOffer; Draft = $buyDraft.data; Preview = $buyPreview.data; Commit = $buyCommit.data; After = [ordered]@{ Gold = $afterBuy.state.economy.gold; ItemCount = $afterBuy.state.party.itemCount } }
        Sell = [ordered]@{ Offer = $sellOffer; Draft = $sellDraft.data; Preview = $sellPreview.data; Commit = $sellCommit.data }
        TradeRumors = [ordered]@{ Seed = $rumorFixture.data; Market = $marketRumors.data; MarketNativeTooltip = $marketNativeTooltip.data; NonGoods = if ($null -ne $nonGoodsRumors) { $nonGoodsRumors.data } else { $null }; Player = $playerRumors.data; PlayerNativeTooltip = $playerNativeTooltip.data; GoodsBuy = $rumorGoodsBuyCommit.data; GoodsSell = $rumorGoodsSellCommit.data; NoMutationReceipt = [bool]$marketRumorReadNoMutation; ExpiredRumorFiltered = [bool]$expiredRumorFiltered; CurrentTownExcluded = [bool]$currentTownRumorsExcluded; InvalidCandidateStatus = [string]$staleRumors.status; OutsideTradeStatus = [string]$rumorOutsideState.status }
        AfterTransactions = [ordered]@{ Gold = $afterSell.state.economy.gold; ItemCount = $afterSell.state.party.itemCount }
        CancelDraft = $cancelDraft.data
        CancelReceipt = $cancel.data
        UnaffordableOffer = [ordered]@{ Candidate = if ($unaffordableOffer.Count -gt 0) { $unaffordableOffer[0] } else { $null }; Result = $unaffordableResult; Rollback = $unaffordableRollback }
        CapacityOffer = [ordered]@{ Candidate = $overCapacityOffers[0]; Attempt = $capacityAttempt; Rollback = $capacityRollback; WeightLimit = $capacityBaseline.state.party.cargoCapacity }
        OverstockStatus = [string]$overstock.status
        StaleStatus = [string]$staleItem.status
        OutsideNativeTradeStateStatus = [string]$tradeOutsideNativeState.status
        Assertions = $assertions
        FailedAssertions = $failedAssertions
        FixtureHashBefore = $fixtureHashBefore
        FixtureHashAfter = $fixtureHashAfter
        ProcessStopped = [bool]$stop.processStopped
        Passed = ($failedAssertions.Count -eq 0)
    }
    $result | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    $result | ConvertTo-Json -Depth 16
    if (-not $result.Passed) { throw 'Native Town Trade Inventory buy/sell/cancel regression failed.' }
}
finally {
    if (Test-Path -LiteralPath $sessionPath) {
        try {
            $current = Get-TradeState "cleanup-$([Guid]::NewGuid().ToString('N'))"
            if ($current.state.context.gameState -eq 'InventoryState' -and $current.state.inventoryScreen.mode -eq 'Trade') {
                $options = Invoke-AgentCli 'tradeOptions' @('-CommandId', "$prefix-cleanup-options")
                if ($options.data.hasPendingChanges) { Invoke-AgentCli 'tradeCancelChanges' @('-CommandId', "$prefix-cleanup-cancel-changes") | Out-Null }
                else { Invoke-AgentCli 'tradeCancel' @('-CommandId', "$prefix-cleanup-cancel") | Out-Null }
            }
            Invoke-AgentCli 'stop' @('-CommandId', "$prefix-cleanup-stop") 30 | Out-Null
        }
        catch { try { Invoke-AgentCli 'stop' @('-CommandId', "$prefix-cleanup-stop-again") 30 | Out-Null } catch { } }
    }
}
