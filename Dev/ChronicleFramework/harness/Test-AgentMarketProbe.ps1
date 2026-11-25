#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$LoadSaveName = 'ChronicleW7P-manual-20261101-eyc-complete',
    [ValidateRange(30,900)][int]$ArrivalTimeoutSeconds = 240,
    [ValidateRange(1,20)][int]$BuyAmount = 1,
    [int]$TimeoutSeconds = 180
)

# Market probe receipt: what a town actually pays for goods, and whether carrying a good from one town
# to another pays for the ride. Loads a fixture, buys the cheapest non-food good the first town sells,
# records every offer on both sides, walks to a second town and asks what that town pays for the same
# good before selling one unit. No model requests, no save writes.
#
# Food is deliberately excluded from the arbitrage leg: a 25-member party eats through a grain purchase
# during travel, so the unit that arrives is not the unit that left.
$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$runDirectory = if ($env:CHRONICLE_HARNESS_TEMP) { Split-Path -Parent $env:CHRONICLE_HARNESS_TEMP } else { Join-Path (Split-Path -Parent $PSScriptRoot) 'TestResults\ManualMarketProbe' }
New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null
$resultPath = Join-Path $runDirectory 'MarketProbeResult.json'
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$commandPrefix = 'market-probe-' + (Get-Date -Format 'yyyyMMddHHmmssfff')

if (-not (Test-Path -LiteralPath $savePath)) { throw "Market probe fixture not found: $savePath" }
if (Get-Process -Name Bannerlord -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
$assertions = [ordered]@{}
$record = [ordered]@{
    fixture = $LoadSaveName
    fixtureSha256 = $fixtureHashBefore
    towns = @()
    arbitrage = $null
    assertions = $assertions
    passed = $false
}

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $output = & $HarnessPowerShell -NoProfile -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

function Get-State([string]$Tag, [int]$CommandTimeout = 0) {
    return Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-$Tag-$([Guid]::NewGuid().ToString('N'))") $CommandTimeout
}

function Get-Snapshot($Observation, [string]$Label) {
    $state = $Observation.state
    return [ordered]@{
        label = $Label
        campaignDay = [double]$state.campaignDay
        gameState = [string]$state.context.gameState
        menuId = [string]$state.context.menuId
        currentSettlementId = [string]$state.location.currentSettlementId
        gold = [int]$state.economy.gold
        members = [int]$state.party.members
        itemCount = [int]$state.party.itemCount
        cargoWeight = [int]$state.party.cargoWeight
        dailyWage = [int]$state.party.dailyWage
    }
}

function Invoke-Checkpoint([string]$Tag) {
    $state = Get-State $Tag
    $record.towns += (Get-Snapshot $state $Tag)
    return $state
}

function Find-OfferRow($Rows, [string]$ItemId) {
    # The leading comma keeps a single match an array: an OrderedDictionary indexes by key, so
    # $single[0] would read key 0 and silently return null instead of the first row.
    $matched = @(@($Rows) | Where-Object { [string]$_.itemId -eq $ItemId })
    return , $matched
}

function Format-Offers($Rows) {
    return @(@($Rows) | ForEach-Object {
        [pscustomobject]@{
            itemId = [string]$_.itemId
            viewModelItemId = [string]$_.viewModelItemId
            unitPrice = [int]$_.nativeItemCost
            stock = [int]$_.stock
            isFood = [bool]$_.isFood
            inventorySide = [string]$_.inventorySide
        }
    })
}

function Enter-Town([string]$TownId, [string]$Reason) {
    $state = Get-State "$Reason-arrive"
    if ([string]$state.state.location.currentSettlementId -eq $TownId -and [string]$state.state.context.menuId -eq 'town') { return $state }
    $settlements = Invoke-AgentCli 'mapSettlementTargets' @('-CommandId', "$commandPrefix-$Reason-targets")
    $target = @($settlements.data.mapSettlementTargets | Where-Object { [string]$_.id -eq $TownId })
    if ($target.Count -ne 1) { throw "Native map does not expose town '$TownId'." }
    $move = Invoke-AgentCli 'move' @('-SettlementId', $TownId, '-CommandId', "$commandPrefix-$Reason-move")
    if ($move.status -ne 'completed' -or [string]$move.state.location.targetSettlementId -ne $TownId) { throw "Native map movement did not accept '$TownId'." }
    $deadline = [DateTime]::UtcNow.AddSeconds($ArrivalTimeoutSeconds)
    $arrived = $null
    while ([DateTime]::UtcNow -lt $deadline) {
        $arrived = Get-State "$Reason-arrival" 30
        if ([string]$arrived.state.location.currentSettlementId -eq $TownId -and [string]$arrived.state.context.menuId -eq 'town') { return $arrived }
        if ($arrived.state.context.encounterActive -and [string]$arrived.state.context.encounteredPartyId -ne $TownId) {
            throw "Unexpected encounter '$($arrived.state.context.encounteredPartyId)' interrupted travel to '$TownId'."
        }
        Start-Sleep -Milliseconds 500
    }
    throw "Natural campaign travel did not enter '$TownId' within $ArrivalTimeoutSeconds seconds."
}

function Open-Market([string]$TownId) {
    $menu = Invoke-AgentCli 'menuSelect' @('-MenuId', 'town', '-OptionId', 'trade', '-CommandId', "$commandPrefix-open-$TownId")
    if ([string]$menu.state.context.gameState -ne 'InventoryState' -or [string]$menu.state.inventoryScreen.mode -ne 'Trade') {
        throw "Selecting trade at '$TownId' did not open the market; got $($menu.state.context.gameState)/$($menu.state.inventoryScreen.mode)."
    }
    return Invoke-AgentCli 'tradeOptions' @('-CommandId', "$commandPrefix-options-$TownId")
}

function Close-Market([string]$Tag) {
    $deadline = [DateTime]::UtcNow.AddSeconds(120)
    $state = Get-State "$Tag-close" 30
    while ([DateTime]::UtcNow -lt $deadline -and [string]$state.state.context.gameState -ne 'MapState') {
        Invoke-AgentCli 'inventoryDone' @('-CommandId', "$commandPrefix-$Tag-inventory-done") | Out-Null
        Start-Sleep -Milliseconds 500
        $state = Get-State "$Tag-close" 30
    }
    if ([string]$state.state.context.gameState -ne 'MapState') { throw "The market did not return to the campaign map; got $($state.state.context.gameState)." }
    return $state
}

function Leave-Town([string]$TownId) {
    $state = Get-State 'leave-check' 30
    if ([string]$state.state.context.menuId -ne 'town') { return $state }
    $leave = Invoke-AgentCli 'menuSelect' @('-MenuId', 'town', '-OptionId', 'town_leave', '-CommandId', "$commandPrefix-leave-$TownId")
    if ($leave.status -ne 'completed') { throw "The native town_leave option at '$TownId' did not complete: status=$($leave.status)." }
    $deadline = [DateTime]::UtcNow.AddSeconds(60)
    while ([DateTime]::UtcNow -lt $deadline) {
        $state = Get-State 'leave-wait' 30
        if ([string]::IsNullOrWhiteSpace([string]$state.state.context.menuId) -and [string]$state.state.context.gameState -eq 'MapState') { return $state }
        Start-Sleep -Milliseconds 500
    }
    return $state
}

try {
    $loaded = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName, '-CommandId', "$commandPrefix-load")
    $start = Invoke-Checkpoint 'start'
    $record.goldAtStart = [int]$start.state.economy.gold

    $settlements = Invoke-AgentCli 'mapSettlementTargets' @('-CommandId', "$commandPrefix-first-targets")
    $towns = @($settlements.data.mapSettlementTargets | Where-Object { $_.type -eq 'town' -and -not $_.hostile -and -not $_.underSiege } | Sort-Object { [double]$_.distance })
    if ($towns.Count -lt 2) { throw 'The native map exposes fewer than two non-hostile towns that are not under siege, so no arbitrage leg can be walked.' }
    $townA = [string]$towns[0].id
    $townB = [string]$towns[1].id

    $arrivedA = Enter-Town $townA 'townA'
    $optionsA = Open-Market $townA
    $buyOffersA = Format-Offers $optionsA.data.buyOffers
    $sellOffersA = Format-Offers $optionsA.data.sellOffers
    $record.towns += [ordered]@{
        label = 'townA-market'
        townId = $townA
        campaignDay = [double]$arrivedA.state.campaignDay
        merchantGold = [int]$optionsA.data.merchantGold
        playerGold = [int]$optionsA.data.playerGold
        buyOfferCount = @($buyOffersA).Count
        sellOfferCount = @($sellOffersA).Count
        buyOffers = $buyOffersA
        sellOffers = $sellOffersA
    }

    $candidates = @($buyOffersA | Where-Object { -not $_.isFood -and [int]$_.stock -ge $BuyAmount -and [int]$_.unitPrice -gt 0 } | Sort-Object { [int]$_.unitPrice })
    if ($candidates.Count -lt 1) { throw "The market at '$townA' sells no non-food good with stock." }
    $chosen = $candidates[0]
    $record.chosenItem = [ordered]@{
        itemId = [string]$chosen.itemId
        viewModelItemId = [string]$chosen.viewModelItemId
        unitPrice = [int]$chosen.unitPrice
        stock = [int]$chosen.stock
        candidateCount = $candidates.Count
    }

    $draft = Invoke-AgentCli 'trade' @('-Direction', 'buy', '-ItemViewModelId', [string]$chosen.viewModelItemId, '-InventorySide', 'OtherInventory', '-Amount', [string]$BuyAmount, '-CommandId', "$commandPrefix-buy")
    if ($draft.status -ne 'completed') { throw "Native market buy of '$($chosen.itemId)' did not complete: status=$($draft.status)." }
    $confirmBuy = Invoke-AgentCli 'tradeConfirm' @('-CommandId', "$commandPrefix-buy-confirm")
    if ($confirmBuy.status -notin @('completed', 'accepted')) { throw "Native tradeConfirm did not accept the purchase: status=$($confirmBuy.status)." }
    $afterBuy = Close-Market 'buy'
    $afterBuySnapshot = Invoke-Checkpoint 'after-buy'
    # The spread only pays if the party can carry enough units to cover the leg, so the probe prices the
    # cargo side as well: one unit's weight comes from the difference the purchase itself made.
    $startCargoWeight = [double]$start.state.party.cargoWeight
    $afterBuyCargoWeight = [double]$afterBuySnapshot.state.party.cargoWeight
    $afterBuyCargoCapacity = [double]$afterBuySnapshot.state.party.cargoCapacity
    $unitWeight = if ($BuyAmount -gt 0) { [Math]::Round(($afterBuyCargoWeight - $startCargoWeight) / $BuyAmount, 4) } else { 0 }
    $record.afterBuy = [ordered]@{
        gold = [int]$afterBuySnapshot.state.economy.gold
        goldDelta = [int]$afterBuySnapshot.state.economy.gold - [int]$start.state.economy.gold
        itemCount = [int]$afterBuySnapshot.state.party.itemCount
        campaignDay = [double]$afterBuySnapshot.state.campaignDay
        cargoWeight = $afterBuyCargoWeight
        cargoCapacity = $afterBuyCargoCapacity
        unitWeight = $unitWeight
        confirmReceipt = $confirmBuy.data
    }
    $assertions['PurchaseChargedItsPrice'] = ([int]$afterBuySnapshot.state.economy.gold -le [int]$start.state.economy.gold)
    $assertions['PurchaseAddedOneItem'] = ([int]$afterBuySnapshot.state.party.itemCount -ge [int]$start.state.party.itemCount + $BuyAmount)
    $assertions['ItemWeightIsPositive'] = ($unitWeight -gt 0)
    $assertions['CargoCapacityExposed'] = ($afterBuyCargoCapacity -gt 0)

    $leftA = Leave-Town $townA
    $arrivedB = Enter-Town $townB 'townB'
    $optionsB = Open-Market $townB
    $buyOffersB = Format-Offers $optionsB.data.buyOffers
    $sellOffersB = Format-Offers $optionsB.data.sellOffers
    $record.towns += [ordered]@{
        label = 'townB-market'
        townId = $townB
        campaignDay = [double]$arrivedB.state.campaignDay
        merchantGold = [int]$optionsB.data.merchantGold
        playerGold = [int]$optionsB.data.playerGold
        buyOfferCount = @($buyOffersB).Count
        sellOfferCount = @($sellOffersB).Count
        buyOffers = $buyOffersB
        sellOffers = $sellOffersB
    }

    $goldBeforeSale = [int]$optionsB.data.playerGold
    $carriedInB = Find-OfferRow $sellOffersB ([string]$chosen.itemId)
    $assertions['CarriedGoodSurvivedTravel'] = ($carriedInB.Count -ge 1)
    $sellPrice = if ($carriedInB.Count -ge 1) { [int]$carriedInB[0].unitPrice } else { 0 }
    $assertions['SecondTownQuotesAPrice'] = ($sellPrice -gt 0)

    $soldView = if ($carriedInB.Count -ge 1) { [string]$carriedInB[0].viewModelItemId } else { '' }
    if ($carriedInB.Count -ge 1) {
        $sellDraft = Invoke-AgentCli 'trade' @('-Direction', 'sell', '-ItemViewModelId', $soldView, '-InventorySide', 'PlayerInventory', '-Amount', '1', '-CommandId', "$commandPrefix-sell")
        if ($sellDraft.status -ne 'completed') { throw "Native market sell of '$($chosen.itemId)' did not complete: status=$($sellDraft.status)." }
        $confirmSell = Invoke-AgentCli 'tradeConfirm' @('-CommandId', "$commandPrefix-sell-confirm")
        if ($confirmSell.status -notin @('completed', 'accepted')) { throw "Native tradeConfirm did not accept the sale: status=$($confirmSell.status)." }
        $afterSell = Close-Market 'sell'
        $afterSellSnapshot = Invoke-Checkpoint 'after-sell'
        $record.afterSell = [ordered]@{
            gold = [int]$afterSellSnapshot.state.economy.gold
            goldDeltaVsAfterBuy = [int]$afterSellSnapshot.state.economy.gold - [int]$record.afterBuy.gold
            itemCount = [int]$afterSellSnapshot.state.party.itemCount
            confirmReceipt = $confirmSell.data
        }
        # Wages accrue between the two markets, so the sale is judged against the gold the second market
        # quoted at open time, not against the balance left over from the purchase.
        $saleDelta = [int]$afterSellSnapshot.state.economy.gold - $goldBeforeSale
        $assertions['SaleCollectedItsQuotedPrice'] = ($saleDelta -eq $sellPrice)
        $boughtFor = [int]$chosen.unitPrice
        $travelDays = [double]$afterSellSnapshot.state.campaignDay - [double]$record.afterBuy.campaignDay
        $travelWageCost = $goldBeforeSale - [int]$record.afterBuy.gold
        $grossPerUnit = $sellPrice - $boughtFor
        $breakEvenUnits = if ($grossPerUnit -gt 0 -and $travelDays -gt 0) { [Math]::Ceiling((-$travelWageCost) / ($grossPerUnit * $travelDays)) } else { $null }
        $cargoHeadroom = [Math]::Max(0, $afterBuyCargoCapacity - $afterBuyCargoWeight)
        $maxUnitsByCargo = if ($unitWeight -gt 0) { [Math]::Floor($cargoHeadroom / $unitWeight) } else { $null }
        $record.arbitrage = [ordered]@{
            itemId = [string]$chosen.itemId
            boughtFor = $boughtFor
            soldFor = $sellPrice
            grossPerUnit = $grossPerUnit
            travelCampaignDays = $travelDays
            travelWageCost = $travelWageCost
            dailyWage = [int]$start.state.party.dailyWage
            breakEvenUnitsPerTravelDay = $breakEvenUnits
            unitWeight = $unitWeight
            cargoWeight = $afterBuyCargoWeight
            cargoCapacity = $afterBuyCargoCapacity
            cargoHeadroom = $cargoHeadroom
            maxUnitsByCargo = $maxUnitsByCargo
            breakEvenFitsCargo = if ($null -ne $maxUnitsByCargo -and $null -ne $breakEvenUnits) { ($maxUnitsByCargo -ge $breakEvenUnits) } else { $false }
        }
    } else {
        $record.afterSell = $null
        $assertions['SaleCollectedItsQuotedPrice'] = $false
        $record.arbitrage = [ordered]@{ itemId = [string]$chosen.itemId; boughtFor = [int]$chosen.unitPrice; soldFor = 0; grossPerUnit = 0; travelCampaignDays = 0; travelWageCost = 0; dailyWage = [int]$start.state.party.dailyWage; breakEvenUnitsPerTravelDay = $null }
    }

    if ([string]$afterSell.state.context.menuId -eq 'town' -or ([string]$afterBuy.state.context.menuId -eq 'town')) {
        Leave-Town $townB | Out-Null
    }
    $final = Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-stop")
    if ($final.status -notin @('completed', 'accepted')) { throw "Native stop did not accept the market probe exit: status=$($final.status)." }
} catch {
    $record.error = $_.Exception.Message
} finally {
    try { Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-stop-final") | Out-Null } catch { }
    if ($null -ne $previousHarnessMode) { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode } else { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
}

$fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
$assertions['FixtureUnchanged'] = ($fixtureHashAfter -eq $fixtureHashBefore)
$record.fixtureSha256After = $fixtureHashAfter
$record.bannerlordRunning = [bool](Get-Process -Name Bannerlord -ErrorAction SilentlyContinue)
$assertions['ProcessStopped'] = (-not $record.bannerlordRunning)
$record.passed = (-not $record.Contains('error')) -and (@($assertions.Values | Where-Object { -not $_ }).Count -eq 0)
$record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding utf8
$record | ConvertTo-Json -Depth 8 -Compress
if (-not $record.passed) { Write-Error "Market probe failed: $resultPath"; exit 1 }
exit 0