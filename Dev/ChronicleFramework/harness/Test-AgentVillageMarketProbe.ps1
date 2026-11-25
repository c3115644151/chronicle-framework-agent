#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$LoadSaveName = 'ChronicleW7P-manual-20261101-eyc-complete',
    [ValidateRange(30,900)][int]$ArrivalTimeoutSeconds = 240,
    [ValidateRange(1,20)][int]$BuyAmount = 1,
    [ValidateRange(1,50)][int]$SellUnits = 1,
    [int]$TimeoutSeconds = 180
)

# Village market probe receipt: whether the Native village menu's trade option opens a real market,
# what that market offers for purchase, and whether a sale there banks the quoted price. The gold route
# in AgentHostEstablishClanGoldSaleLoop accepts only towns, so this probe answers the question that
# decision depends on: is a village a market, and can the player turn goods into gold there?
#
# The village trade menu is labelled "buy provisions" and its purchase side is expected to be food;
# the income leg is the sell side, where the merchant buys the player's goods. Both are recorded. A
# market that offers nothing to buy is a finding, not a failure; only a menu that refuses to open, a
# sale that banks nothing, or a changed fixture is.
$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$runDirectory = if ($env:CHRONICLE_HARNESS_TEMP) { Split-Path -Parent $env:CHRONICLE_HARNESS_TEMP } else { Join-Path (Split-Path -Parent $PSScriptRoot) 'TestResults\ManualVillageMarketProbe' }
New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null
$resultPath = Join-Path $runDirectory 'VillageMarketProbeResult.json'
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$commandPrefix = 'village-market-' + (Get-Date -Format 'yyyyMMddHHmmssfff')

function Get-BannerlordProcesses {
    # The launcher process is Bannerlord.BLSE.Standalone; -Name Bannerlord only ever matches the
    # plain executable, so a cleanup check that only knows one name can report 'stopped' while the
    # game is still running.
    return @(Get-Process -Name 'Bannerlord','Bannerlord.BLSE.Standalone' -ErrorAction SilentlyContinue)
}

if (-not (Test-Path -LiteralPath $savePath)) { throw "Village market fixture not found: $savePath" }
if ((Get-BannerlordProcesses).Count -gt 0) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
$assertions = [ordered]@{}
$record = [ordered]@{
    fixture = $LoadSaveName
    fixtureSha256 = $fixtureHashBefore
    village = $null
    menu = $null
    market = $null
    snapshots = @()
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
        dailyWage = [int]$state.party.dailyWage
    }
}

function Invoke-Checkpoint([string]$Tag) {
    $state = Get-State $Tag
    $record.snapshots += (Get-Snapshot $state $Tag)
    return $state
}

function Get-MenuOptions($State) {
    # availableMenuOptions is a top-level state key; reading it under context returns nothing and
    # then every option looks absent.
    return @($State.availableMenuOptions)
}

function Format-Offers($Rows) {
    # unitPrice is inventoryLogicUnitPrice: the price this side of the trade actually settles at.
    # nativeItemCost is the item's base cost and is not what a sale banks.
    return @(@($Rows) | ForEach-Object {
        [pscustomobject]@{
            itemId = [string]$_.itemId
            viewModelItemId = [string]$_.viewModelItemId
            name = [string]$_.name
            nativeTooltipType = [string]$_.nativeTooltipType
            unitPrice = [int]$_.inventoryLogicUnitPrice
            baseCost = [int]$_.nativeItemCost
            stock = [int]$_.stock
            isFood = [bool]$_.isFood
            isTransferable = [bool]$_.isTransferable
            inventorySide = [string]$_.inventorySide
        }
    })
}

function Enter-Settlement([string]$SettlementId, [string]$MenuId, [string]$Reason) {
    $state = Get-State "$Reason-arrive"
    if ([string]$state.state.location.currentSettlementId -eq $SettlementId -and [string]$state.state.context.menuId -eq $MenuId) { return $state }
    $targets = Invoke-AgentCli 'mapSettlementTargets' @('-CommandId', "$commandPrefix-$Reason-targets")
    $target = @($targets.data.mapSettlementTargets | Where-Object { [string]$_.id -eq $SettlementId })
    if ($target.Count -ne 1) { throw "Native map does not expose settlement '$SettlementId'." }
    $move = Invoke-AgentCli 'move' @('-SettlementId', $SettlementId, '-CommandId', "$commandPrefix-$Reason-move")
    if ($move.status -ne 'completed' -or [string]$move.state.location.targetSettlementId -ne $SettlementId) { throw "Native map movement did not accept '$SettlementId'." }
    $deadline = [DateTime]::UtcNow.AddSeconds($ArrivalTimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $arrived = Get-State "$Reason-arrival" 30
        if ([string]$arrived.state.location.currentSettlementId -eq $SettlementId -and [string]$arrived.state.context.menuId -eq $MenuId) { return $arrived }
        if ($arrived.state.context.encounterActive -and [string]$arrived.state.context.encounteredPartyId -ne $SettlementId) {
            throw "Unexpected encounter '$($arrived.state.context.encounteredPartyId)' interrupted travel to '$SettlementId'."
        }
        Start-Sleep -Milliseconds 500
    }
    throw "Natural campaign travel did not enter '$SettlementId' within $ArrivalTimeoutSeconds seconds."
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

function Leave-Village([string]$VillageId) {
    $state = Get-State 'leave-check' 30
    if ([string]$state.state.context.menuId -ne 'village') { return $state }
    $leave = Invoke-AgentCli 'menuSelect' @('-MenuId', 'village', '-OptionId', 'leave', '-CommandId', "$commandPrefix-leave-$VillageId")
    if ($leave.status -ne 'completed') { throw "The native village leave option at '$VillageId' did not complete: status=$($leave.status)." }
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

    $targets = Invoke-AgentCli 'mapSettlementTargets' @('-CommandId', "$commandPrefix-first-targets")
    $all = @($targets.data.mapSettlementTargets)
    $record.settlementTypeCounts = [ordered]@{}
    foreach ($group in ($all | Group-Object { [string]$_.type } | Sort-Object Name)) { $record.settlementTypeCounts[$group.Name] = $group.Count }
    $villages = @($all | Where-Object { [string]$_.type -eq 'village' -and -not $_.hostile -and -not $_.underSiege } | Sort-Object { [double]$_.distance })
    if ($villages.Count -lt 1) { throw ('The native map exposes no non-hostile village that is not under siege; observed types: ' + ($record.settlementTypeCounts.Keys -join ', ')) }
    $villageId = [string]$villages[0].id
    $record.village = [ordered]@{
        villageId = $villageId
        name = [string]$villages[0].name
        distance = [double]$villages[0].distance
        candidateCount = $villages.Count
    }

    $arrived = Enter-Settlement $villageId 'village' 'village'
    $options = Get-MenuOptions $arrived.state
    $record.menu = [ordered]@{
        menuId = [string]$arrived.state.context.menuId
        currentSettlementId = [string]$arrived.state.location.currentSettlementId
        optionCount = $options.Count
        options = @($options | ForEach-Object { [pscustomobject]@{ id = [string]$_.id; text = [string]$_.text; available = [bool]$_.available; enabled = [bool]$_.enabled } })
    }
    $tradeOption = @($options | Where-Object { [string]$_.id -eq 'trade' })
    $assertions['VillageMenuOffersTrade'] = ($tradeOption.Count -eq 1 -and [bool]$tradeOption[0].available -and [bool]$tradeOption[0].enabled)
    if (-not $assertions['VillageMenuOffersTrade']) { throw "The village menu at '$villageId' does not offer an available, enabled trade option." }

    $open = Invoke-AgentCli 'menuSelect' @('-MenuId', 'village', '-OptionId', 'trade', '-CommandId', "$commandPrefix-open")
    $openedMarket = ([string]$open.state.context.gameState -eq 'InventoryState' -and [string]$open.state.inventoryScreen.mode -eq 'Trade')
    $assertions['VillageTradeOpenedMarket'] = $openedMarket
    if (-not $openedMarket) { throw "Selecting trade at village '$villageId' did not open a market; got $($open.state.context.gameState)/$($open.state.inventoryScreen.mode)." }

    $quote = Invoke-AgentCli 'tradeOptions' @('-CommandId', "$commandPrefix-options")
    $beforeSale = Invoke-Checkpoint 'before-village-sale'
    $buyOffers = Format-Offers $quote.data.buyOffers
    $sellOffers = Format-Offers $quote.data.sellOffers
    $provisionsOnly = (@($buyOffers).Count -gt 0) -and (@($buyOffers | Where-Object { -not $_.isFood }).Count -eq 0)
    $record.market = [ordered]@{
        settlementId = [string]$quote.data.settlementId
        settlementType = [string]$quote.data.settlementType
        merchantGold = [int]$quote.data.merchantGold
        playerGold = [int]$quote.data.playerGold
        buyOfferCount = @($buyOffers).Count
        sellOfferCount = @($sellOffers).Count
        purchaseAssortmentIsProvisionsOnly = $provisionsOnly
        buyOffers = @($buyOffers | Sort-Object { [int]$_.unitPrice } | Select-Object -First 25)
        sellOffers = @($sellOffers | Sort-Object { -[int]$_.unitPrice } | Select-Object -First 25)
    }
    $assertions['VillageTradeReceiptNamesVillage'] = ([string]$quote.data.settlementType -eq 'village')
    $assertions['VillageMarketExposesGold'] = ($null -ne $quote.data.merchantGold)

    # The income leg: the merchant's buy side is what turns the player's goods into gold. The Host
    # gold route uses exactly these offer fields, so the probe keeps the same vocabulary.
    $candidates = @($sellOffers | Where-Object {
        [string]$_.nativeTooltipType -eq 'Goods' -and [bool]$_.isTransferable -and
        [int]$_.stock -ge 1 -and [int]$_.unitPrice -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$_.viewModelItemId) -and
        [string]$_.inventorySide -eq 'PlayerInventory'
    } | Sort-Object { -[int]$_.unitPrice }, { [string]$_.viewModelItemId })
    if ($candidates.Count -lt 1) { throw "The village market at '$villageId' buys none of the player's goods, so a village cannot be an income market here." }
    # Single-unit probes keep the highest price first, which is what the Host gold route picks today.
    # A multi-unit probe instead takes the largest stack, because the question it answers is whether
    # one Native trade can settle more than one unit at a single quoted price.
    $chosen = if ($SellUnits -gt 1) { @($candidates | Sort-Object { -[int]$_.stock }, { -[int]$_.unitPrice })[0] } else { @($candidates)[0] }
    $soldUnits = [Math]::Min($SellUnits, [int]$chosen.stock)
    $record.chosenGood = [ordered]@{
        itemId = [string]$chosen.itemId
        viewModelItemId = [string]$chosen.viewModelItemId
        name = [string]$chosen.name
        unitPrice = [int]$chosen.unitPrice
        stock = [int]$chosen.stock
        candidateCount = $candidates.Count
        requestedUnits = $SellUnits
        soldUnits = $soldUnits
    }
    $draft = Invoke-AgentCli 'trade' @('-Direction', 'sell', '-ItemViewModelId', [string]$chosen.viewModelItemId, '-InventorySide', 'PlayerInventory', '-Amount', [string]$soldUnits, '-CommandId', "$commandPrefix-sell")
    if ($draft.status -ne 'completed') { throw "Native village sale of '$($chosen.itemId)' did not complete: status=$($draft.status)." }
    $confirm = Invoke-AgentCli 'tradeConfirm' @('-CommandId', "$commandPrefix-sell-confirm")
    if ($confirm.status -notin @('completed', 'accepted')) { throw "Native tradeConfirm did not accept the village sale: status=$($confirm.status)." }
    Close-Market 'village-sale' | Out-Null
    $afterSale = Invoke-Checkpoint 'after-village-sale'
    $goldDelta = [int]$afterSale.state.economy.gold - [int]$beforeSale.state.economy.gold
    $dayStable = ([double]$afterSale.state.campaignDay -eq [double]$beforeSale.state.campaignDay)
    $quotedTotal = [int]$chosen.unitPrice * $soldUnits
    $itemCountDelta = [int]$afterSale.state.party.itemCount - [int]$beforeSale.state.party.itemCount
    $receiptUnits = [int]$confirm.data.amount
    $priceExact = ($goldDelta -eq $quotedTotal)
    $record.afterSale = [ordered]@{
        gold = [int]$afterSale.state.economy.gold
        goldDelta = $goldDelta
        itemCount = [int]$afterSale.state.party.itemCount
        itemCountDelta = $itemCountDelta
        campaignDay = [double]$afterSale.state.campaignDay
        dayAdvancedDuringSale = (-not $dayStable)
        quotedUnitPrice = [int]$chosen.unitPrice
        soldUnits = $soldUnits
        receiptUnits = $receiptUnits
        quotedTotal = $quotedTotal
        priceMatchedExactly = $priceExact
        confirmReceipt = $confirm.data
    }
    $assertions['VillageSaleBankedItsPrice'] = ($goldDelta -gt 0)
    # Campaign time is frozen inside the market, so the banks-exactly-the-quote check only holds on
    # an unbroken campaigns day; a wage payment would otherwise make a correct sale look wrong.
    $assertions['VillageSalePaidTheQuotedPrice'] = if ($dayStable) { $priceExact } else { $goldDelta -gt 0 }
    # A multi-unit sale is only useful to the Host if one confirm really moves the whole stack; the
    # item count and the receipt's own amount both have to say so.
    $assertions['VillageSaleMovedRequestedUnits'] = ($itemCountDelta -eq -$soldUnits) -and ($receiptUnits -eq $soldUnits)


    Leave-Village $villageId | Out-Null
    $final = Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-stop")
    if ($final.status -notin @('completed', 'accepted')) { throw "Native stop did not accept the village market probe exit: status=$($final.status)." }
} catch {
    $record.error = $_.Exception.Message
} finally {
    try { Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-stop-final") | Out-Null } catch { }
    if ($null -ne $previousHarnessMode) { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode } else { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
}

$fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
$assertions['FixtureUnchanged'] = ($fixtureHashAfter -eq $fixtureHashBefore)
$record.fixtureSha256After = $fixtureHashAfter
$running = Get-BannerlordProcesses
$record.bannerlordProcessNames = @($running | ForEach-Object { $_.ProcessName } | Sort-Object -Unique)
$assertions['ProcessStopped'] = ($record.bannerlordProcessNames.Count -eq 0)
$record.passed = (-not $record.Contains('error')) -and (@($assertions.Values | Where-Object { -not $_ }).Count -eq 0)
$record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding utf8
$record | ConvertTo-Json -Depth 8 -Compress
if (-not $record.passed) { Write-Error "Village market probe failed: $resultPath"; exit 1 }
exit 0
