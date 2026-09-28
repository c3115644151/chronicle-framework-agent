[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$resultPath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP 'TradeTransactionResult.json' } else { Join-Path $PSScriptRoot 'TestResults\ManualTradeTransactions\TradeTransactionResult.json' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$prefix = 'trade-v-' + (Get-Date -Format 'yyyyMMddHHmmssfff')

if (-not (Test-Path -LiteralPath $savePath)) { throw "Trade transaction fixture not found: $LoadSaveName" }
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

    $activeTrade = Open-NativeTrade 'active'
    $activeOptions = Invoke-AgentCli 'tradeOptions' @('-CommandId', "$prefix-active-options")
    $activeBeforeWait = Get-TradeState 'active-before-wait'
    Start-Sleep -Seconds 2
    $activeAfterWait = Get-TradeState 'active-after-wait'
    $activeQueryStable = (
        $activeOptions.status -eq 'completed' -and
        $activeBeforeWait.state.context.timeControlMode -eq $activeTrade.State.state.context.timeControlMode -and
        $activeAfterWait.state.context.timeControlMode -eq $activeTrade.State.state.context.timeControlMode -and
        [double]$activeAfterWait.state.campaignDay -ge [double]$activeBeforeWait.state.campaignDay
    )
    $activeClose = Invoke-AgentCli 'tradeCancel' @('-CommandId', "$prefix-active-close")
    $mapAfterActiveClose = Get-TradeState 'active-map-after-close'
    $activeCloseStable = ($activeClose.data.returnedToMap -and $mapAfterActiveClose.state.context.gameState -eq 'MapState' -and $mapAfterActiveClose.state.context.timeControlMode -eq $activeTrade.State.state.context.timeControlMode)

    $pause = Invoke-AgentCli 'pause' @('-CommandId', "$prefix-stop-clock")
    $baseline = Get-TradeState 'stopped-baseline'
    if ($pause.status -ne 'completed' -or $baseline.state.context.timeControlMode -ne 'Stop') { throw 'Stop-mode trade transaction baseline could not be established.' }

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

    $overstock = Invoke-AgentCli 'trade' @('-Direction', 'buy', '-ItemViewModelId', [string]$buyOffer.viewModelItemId, '-InventorySide', [string]$buyOffer.inventorySide, '-Amount', [string]([int]$buyOffer.stock + 1), '-CommandId', "$prefix-overstock") 15
    $afterOverstock = Invoke-AgentCli 'tradeOptions' @('-CommandId', "$prefix-overstock-after")
    $sameOverstockOffer = @($afterOverstock.data.buyOffers | Where-Object { $_.viewModelItemId -eq $buyOffer.viewModelItemId } | Select-Object -First 1)
    $overstockRejected = ($overstock.status -eq 'rejected' -and [int]$afterOverstock.data.playerGold -eq [int]$buyOptions.data.playerGold -and $sameOverstockOffer.Count -eq 1 -and [int]$sameOverstockOffer[0].stock -eq [int]$buyOffer.stock)
    if (-not $overstockRejected) { throw 'An amount greater than current native market stock was not rejected without mutation.' }

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

    $staleTrade = Open-NativeTrade 'stale'
    $staleItem = Invoke-AgentCli 'trade' @('-Direction', 'sell', '-ItemViewModelId', [string]$sellOffer.viewModelItemId, '-InventorySide', [string]$sellOffer.inventorySide, '-Amount', '1', '-CommandId', "$prefix-stale-item") 15
    $staleOptions = Invoke-AgentCli 'tradeOptions' @('-CommandId', "$prefix-stale-options")
    $staleRejected = ($staleItem.status -eq 'rejected' -and [int]$staleOptions.data.playerGold -eq [int]$afterSell.state.economy.gold)
    $staleClose = Invoke-AgentCli 'tradeCancel' @('-CommandId', "$prefix-stale-close")
    $partyDataAfterTransactions = Get-TradeState 'party-after-transactions'
    $pauseEnd = Invoke-AgentCli 'pause' @('-CommandId', "$prefix-pause-end")
    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-stop") 30
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash

    $assertions = [ordered]@{
        TownMenuOpenedNativeTradeInventoryState = ($buyTrade.Open.status -eq 'completed' -and $buyTrade.State.state.context.gameState -eq 'InventoryState' -and $buyTrade.State.state.inventoryScreen.mode -eq 'Trade')
        ActiveTradeQueryKeepsModeAndNaturalTimeNondecreasing = [bool]$activeQueryStable
        ActiveTradeCloseReturnsToTownWithoutClockWrite = [bool]$activeCloseStable
        NativeTradeQuoteMatchesInventoryLogic = [bool]$nativeQuoteMatchesLogic
        NativeTradeOfferPreservesNonEmptyModifier = -not [string]::IsNullOrWhiteSpace([string]$buyOffer.modifierId)
        OverMarketStockRejectedWithoutGoldOrMarketMutation = [bool]$overstockRejected
        NativeCancelInquiryDiscardsUncommittedBuy = [bool]$cancelNoMutation
        NativeBuyTransferAndDoneVerified = [bool]$buyCommit.data.postconditionPassed
        NativeSellTransferAndDoneVerified = [bool]$sellCommit.data.postconditionPassed
        StaleSellCandidateRejected = [bool]$staleRejected
        MapStateRestoredAtTown = ($staleClose.data.returnedToMap -and $partyDataAfterTransactions.state.context.gameState -eq 'MapState' -and $partyDataAfterTransactions.state.location.currentSettlementId -eq $target[0].id)
        FixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = [bool]$stop.processStopped
    }
    $failedAssertions = @($assertions.Keys | Where-Object { -not [bool]$assertions[$_] })
    $result = [ordered]@{
        Settlement = $target[0]
        ActiveState = [ordered]@{ Open = $activeTrade.Open.data; Options = $activeOptions.data; ModeAfterWait = $activeAfterWait.state.context.timeControlMode; DayBefore = $activeBeforeWait.state.campaignDay; DayAfter = $activeAfterWait.state.campaignDay; Close = $activeClose.data }
        Buy = [ordered]@{ Offer = $buyOffer; Draft = $buyDraft.data; Preview = $buyPreview.data; Commit = $buyCommit.data; After = [ordered]@{ Gold = $afterBuy.state.economy.gold; ItemCount = $afterBuy.state.party.itemCount } }
        Sell = [ordered]@{ Offer = $sellOffer; Draft = $sellDraft.data; Preview = $sellPreview.data; Commit = $sellCommit.data; After = [ordered]@{ Gold = $afterSell.state.economy.gold; ItemCount = $afterSell.state.party.itemCount } }
        CancelDraft = $cancelDraft.data
        CancelReceipt = $cancel.data
        OverstockStatus = [string]$overstock.status
        StaleStatus = [string]$staleItem.status
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
