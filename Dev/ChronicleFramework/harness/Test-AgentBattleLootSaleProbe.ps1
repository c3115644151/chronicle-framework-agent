#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$LoadSaveName = 'ChronicleW7P-manual-20261101-eyc-complete',
    [bool]$SeedLoot = $true,
    [ValidateRange(30,900)][int]$ArrivalTimeoutSeconds = 240,
    [ValidateRange(1,200)][int]$SellUnits = 20,
    [int]$TimeoutSeconds = 240
)

# Battle-loot-sale probe receipt: whether one Native hostile battle can fill the player's inventory
# with loot and whether that loot can then become gold at a town market in the same session.
#
# The income leg in this project has been measured one half at a time: the battle fixture proves
# postbattle transfer into the player inventory, and the market probes prove a quote settles into
# gold. Neither proves the chain, and the live-model runs never reach it because the campaign loop
# and the gold route are separate slices. This probe joins the two halves with no model in the loop
# so a later Host change can be judged against a known-good chain.
#
# The loot itself is seeded after the Native autoresolve when -SeedLoot is set (the harness fixture
# mode spawns 'chronicle_harness_looters'); the receipt records lootOrigin so no reader mistakes a
# seeded stack for a natural drop. The sale is entirely natural: the quote, the price and the gold
# delta all come from the game.
$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$runDirectory = if ($env:CHRONICLE_HARNESS_TEMP) { Split-Path -Parent $env:CHRONICLE_HARNESS_TEMP } else { Join-Path (Split-Path -Parent $PSScriptRoot) 'TestResults\ManualBattleLootSale' }
New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null
$resultPath = Join-Path $runDirectory 'BattleLootSaleProbeResult.json'
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$commandPrefix = 'loot-sale-' + (Get-Date -Format 'yyyyMMddHHmmssfff')

function Get-BannerlordProcesses {
    # Bannerlord.BLSE.Standalone is the launcher that actually runs; -Name Bannerlord alone reports
    # a stopped game while the process is alive.
    return @(Get-Process -Name 'Bannerlord','Bannerlord.BLSE.Standalone' -ErrorAction SilentlyContinue)
}

if (-not (Test-Path -LiteralPath $savePath)) { throw "Battle loot sale fixture not found: $savePath" }
if ((Get-BannerlordProcesses).Count -gt 0) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
$assertions = [ordered]@{}
$record = [ordered]@{
    fixture = $LoadSaveName
    fixtureSha256 = $fixtureHashBefore
    lootOrigin = if ($SeedLoot) { 'seeded-fixture-after-native-autoresolve' } else { 'natural' }
    battle = $null
    loot = $null
    sale = $null
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
    }
}

function Invoke-Checkpoint([string]$Tag) {
    $state = Get-State $Tag
    $record.snapshots += (Get-Snapshot $state $Tag)
    return $state
}

function Get-MenuOptions($State) {
    # availableMenuOptions is a top-level state key; reading it under context finds nothing and
    # every option then looks absent.
    return @($State.availableMenuOptions)
}

function Enter-Settlement([string]$SettlementId, [string]$MenuId, [string]$Reason) {
    $move = Invoke-AgentCli 'move' @('-SettlementId', $SettlementId, '-CommandId', "$commandPrefix-move-$Reason")
    if ($move.status -notin @('completed', 'accepted')) { throw "Native move toward '$SettlementId' was not accepted: status=$($move.status)." }
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

try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-battle-fixture'
    $null = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName, '-CommandId', "$commandPrefix-load")
    $start = Invoke-Checkpoint 'start'

    $looters = @($start.state.nearbyParties | Where-Object { [string]$_.id -eq 'chronicle_harness_looters' -and [bool]$_.hostile })
    $encounterActive = ([bool]$start.state.context.encounterActive -and [string]$start.state.context.encounteredPartyId -eq 'chronicle_harness_looters')
    $assertions['HarnessLooterPartyVisible'] = ($looters.Count -eq 1 -or $encounterActive)
    if (-not $assertions['HarnessLooterPartyVisible']) { throw 'The harness fixture mode did not expose one visible hostile looter party to fight.' }

    $last = $start
    if (-not $encounterActive) {
        $pursuit = Invoke-AgentCli 'pursue' @('-PartyId', 'chronicle_harness_looters', '-CommandId', "$commandPrefix-pursue")
        if ($pursuit.status -ne 'completed') { throw "Native pursue was not accepted: status=$($pursuit.status)." }
        $last = $pursuit
        $deadline = [DateTime]::UtcNow.AddSeconds(90)
        while ([DateTime]::UtcNow -lt $deadline) {
            $last = Get-State 'pursuit' 30
            if ([bool]$last.state.context.encounterActive -and [string]$last.state.context.encounteredPartyId -eq 'chronicle_harness_looters') { $encounterActive = $true; break }
            Start-Sleep -Milliseconds 500
        }
    }
    $assertions['LooterEncounterReached'] = $encounterActive
    if (-not $encounterActive) { throw 'Native pursuit did not reach the harness looter encounter in time.' }

    for ($step = 1; $step -le 8; $step++) {
        if ([string]$last.state.context.menuId -eq 'encounter') { break }
        $conversation = $last.state.context.conversation
        if ($null -eq $conversation) { Start-Sleep -Milliseconds 500; $last = Get-State "dialogue-wait-$step" 30; continue }
        if (@($conversation.options).Count -eq 0) {
            if (-not [string]::IsNullOrWhiteSpace([string]$conversation.sentenceText)) { $last = Invoke-AgentCli 'dialogueContinue' @('-CommandId', "$commandPrefix-dialogue-continue-$step") }
            else { Start-Sleep -Milliseconds 500; $last = Get-State "dialogue-silent-$step" 30 }
            continue
        }
        $choice = @($conversation.options | Where-Object { [bool]$_.clickable -and [string]$_.id -in @('common_encounter_ultimatum','common_bandit_surrender_declined') } | Select-Object -First 1)
        if ($choice.Count -ne 1) { throw "Expected a sourced hostile choice; available IDs: $(($conversation.options | ForEach-Object { [string]$_.id }) -join ',')." }
        $last = Invoke-AgentCli 'dialogueSelect' @('-OptionId', [string]$choice[0].id, '-CommandId', "$commandPrefix-dialogue-$step")
    }

    $encounterMenu = Invoke-AgentCli 'menu' @('-CommandId', "$commandPrefix-encounter-menu")
    $attack = @((Get-MenuOptions $encounterMenu.state) | Where-Object { [string]$_.id -eq 'str_order_attack' -and [bool]$_.available -and [bool]$_.enabled })
    $assertions['EncounterMenuOffersSendTroops'] = ($attack.Count -eq 1)
    if (-not $assertions['EncounterMenuOffersSendTroops']) { throw 'The native encounter menu did not expose an enabled Send troops option.' }

    $simulationStart = Invoke-AgentCli 'menuSelect' @('-MenuId', 'encounter', '-OptionId', 'str_order_attack', '-CommandId', "$commandPrefix-send-troops")
    $assertions['BattleSimulationStarted'] = ($null -ne $simulationStart.state.context.battleSimulation)
    if (-not $assertions['BattleSimulationStarted']) { throw 'Native Send troops did not expose an active BattleSimulation.' }
    $skip = Invoke-AgentCli 'battleSkip' @('-CommandId', "$commandPrefix-battle-skip")
    if ($skip.status -ne 'completed') { throw "Native battleSkip was not accepted: status=$($skip.status)." }
    $simulation = $skip
    $deadline = [DateTime]::UtcNow.AddSeconds(90)
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($null -ne $simulation.state.context.battleSimulation -and [bool]$simulation.state.context.battleSimulation.finished) { break }
        Start-Sleep -Milliseconds 250
        $simulation = Get-State 'battle-finish-wait' 30
    }
    $assertions['BattleSimulationFinished'] = ($null -ne $simulation.state.context.battleSimulation -and [bool]$simulation.state.context.battleSimulation.finished)
    if (-not $assertions['BattleSimulationFinished']) { throw 'Native BattleSimulation skip did not produce a completed result.' }
    $record.battle = [ordered]@{
        playerWon = if ($null -ne $simulation.state.context.battleSimulation.playerWon) { [bool]$simulation.state.context.battleSimulation.playerWon } else { $null }
        campaignDay = [double]$simulation.state.campaignDay
    }
    if ($SeedLoot) {
        $seed = Invoke-AgentCli 'seedVisualLoot' @('-CommandId', "$commandPrefix-seed-loot")
        if ($seed.status -ne 'completed' -or [int]$seed.data.count -le 0) { throw 'The deterministic visual loot seed was not accepted after the Native autoresolve.' }
        $record.lootOrigin = "seeded-fixture-after-native-autoresolve(count=$([int]$seed.data.count),naturalDrop=$([bool]$seed.data.naturalDrop))"
    }

    $finish = Invoke-AgentCli 'battleFinish' @('-CommandId', "$commandPrefix-battle-finish")
    if ($finish.status -ne 'completed') { throw "Native battleFinish was not accepted: status=$($finish.status)." }
    $afterBattle = Get-State 'after-battle' 60
    $partyScreen = $afterBattle.state.partyScreen
    $assertions['PostBattlePartyScreenReached'] = ([string]$afterBattle.state.context.gameState -eq 'PartyState' -and [string]$partyScreen.mode -eq 'Loot')
    if (-not $assertions['PostBattlePartyScreenReached']) { throw "Native aftermath did not enter the loot PartyState; got $($afterBattle.state.context.gameState)/$($partyScreen.mode)." }

    $takeMembers = @($partyScreen.leftMembers | Where-Object { [bool]$_.transferable -and [int]$_.count -gt 0 })
    $takePrisoners = @($partyScreen.leftPrisoners | Where-Object { [bool]$_.transferable -and [int]$_.count -gt 0 })
    if ($takeMembers.Count -gt 0) { $afterBattle = Invoke-AgentCli 'partyTakeAll' @('-LootType', 'members', '-CommandId', "$commandPrefix-loot-members") }
    if ($takePrisoners.Count -gt 0) { $afterBattle = Invoke-AgentCli 'partyTakeAll' @('-LootType', 'prisoners', '-CommandId', "$commandPrefix-loot-prisoners") }
    $done = Invoke-AgentCli 'partyScreenDone' @('-CommandId', "$commandPrefix-party-done")
    if ($done.status -ne 'completed') { throw "Native partyScreenDone was not accepted: status=$($done.status)." }
    $afterDone = Get-State 'after-party-done' 60
    if ([bool]$afterDone.state.context.inquiryOpen -and [string]$afterDone.state.context.inquiry.kind -eq 'YesNoInquiry') {
        $null = Invoke-AgentCli 'respondInquiry' @('-InquiryToken', [string]$afterDone.state.context.inquiry.token, '-InquiryChoice', 'affirmative', '-CommandId', "$commandPrefix-party-done-inquiry")
        $afterDone = Get-State 'after-party-done-inquiry' 60
    }
    $assertions['LootInventoryScreenReached'] = ([string]$afterDone.state.context.gameState -eq 'InventoryState' -and [string]$afterDone.state.inventoryScreen.mode -eq 'Loot')
    if (-not $assertions['LootInventoryScreenReached']) { throw "The loot item screen was not entered; got $($afterDone.state.context.gameState)/$($afterDone.state.inventoryScreen.mode)." }
    $lootItemsBefore = [int]$afterDone.state.inventoryScreen.lootItemCount
    $playerItemsBefore = [int]$afterDone.state.inventoryScreen.playerItemCount
    $take = Invoke-AgentCli 'inventoryTakeAll' @('-CommandId', "$commandPrefix-inventory-take-all")
    if ($take.status -ne 'completed') { throw 'Native inventoryTakeAll did not complete.' }
    $afterTake = Get-State 'after-inventory-take-all' 30
    $lootItemsAfter = [int]$afterTake.state.inventoryScreen.lootItemCount
    $playerItemsAfter = [int]$afterTake.state.inventoryScreen.playerItemCount
    $record.loot = [ordered]@{
        lootItemCountBefore = $lootItemsBefore
        lootItemCountAfter = $lootItemsAfter
        playerItemCountBefore = $playerItemsBefore
        playerItemCountAfter = $playerItemsAfter
        itemsMovedIntoPlayerInventory = $playerItemsAfter - $playerItemsBefore
    }
    $assertions['LootMovedIntoPlayerInventory'] = ($lootItemsAfter -eq 0 -and ($playerItemsAfter - $playerItemsBefore) -gt 0)
    if (-not $assertions['LootMovedIntoPlayerInventory']) { throw "Taking the battle loot left $lootItemsAfter items in the loot side and moved $($playerItemsAfter - $playerItemsBefore) into the player inventory." }
    $null = Invoke-AgentCli 'inventoryDone' @('-CommandId', "$commandPrefix-inventory-done")
    $onMap = Get-State 'after-inventory-done' 60
    if ([string]$onMap.state.context.gameState -ne 'MapState') { throw "Closing the loot screen did not return to the map; got $($onMap.state.context.gameState)." }

    $targets = Invoke-AgentCli 'mapSettlementTargets' @('-CommandId', "$commandPrefix-targets")
    $towns = @($targets.data.mapSettlementTargets | Where-Object { [string]$_.type -eq 'town' -and -not [bool]$_.hostile -and -not [bool]$_.underSiege } | Sort-Object { [double]$_.distance })
    if ($towns.Count -lt 1) { throw 'The native map exposes no non-hostile town that is not under siege, so the loot has nowhere to be sold.' }
    $townId = [string]$towns[0].id
    $record.sale = [ordered]@{ townId = $townId; townName = [string]$towns[0].name; distance = [double]$towns[0].distance; townCandidateCount = $towns.Count }

    $arrived = Enter-Settlement $townId 'town' 'town'
    $tradeOption = @((Get-MenuOptions $arrived.state) | Where-Object { [string]$_.id -eq 'trade' -and [bool]$_.available -and [bool]$_.enabled })
    $assertions['TownMenuOffersTrade'] = ($tradeOption.Count -eq 1)
    if (-not $assertions['TownMenuOffersTrade']) { throw "The town menu at '$townId' does not offer an available, enabled trade option." }
    $open = Invoke-AgentCli 'menuSelect' @('-MenuId', 'town', '-OptionId', 'trade', '-CommandId', "$commandPrefix-open-market")
    $assertions['TownMarketOpened'] = ([string]$open.state.context.gameState -eq 'InventoryState' -and [string]$open.state.inventoryScreen.mode -eq 'Trade')
    if (-not $assertions['TownMarketOpened']) { throw "Selecting trade at '$townId' did not open a market." }
    $quote = Invoke-AgentCli 'tradeOptions' @('-CommandId', "$commandPrefix-quote")
    $beforeSale = Invoke-Checkpoint 'before-sale'
    $offers = @($quote.data.sellOffers | Where-Object {
        [string]$_.nativeTooltipType -eq 'Goods' -and [bool]$_.isTransferable -and [string]$_.inventorySide -eq 'PlayerInventory' -and
        [int]$_.stock -ge 1 -and [int]$_.inventoryLogicUnitPrice -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$_.viewModelItemId)
    } | Sort-Object { -[int]$_.inventoryLogicUnitPrice }, { -[int]$_.stock })
    $rawSellOffers = @($quote.data.sellOffers)
    $record.sale['quote'] = [ordered]@{
        rawSellOfferCount = $rawSellOffers.Count
        tooltipTypes = @($rawSellOffers | Group-Object { [string]$_.nativeTooltipType } | ForEach-Object { "$($_.Name):$($_.Count)" })
        inventorySides = @($rawSellOffers | Group-Object { [string]$_.inventorySide } | ForEach-Object { "$($_.Name):$($_.Count)" })
        buyOfferCount = @($quote.data.buyOffers).Count
        offers = @($rawSellOffers | Select-Object -First 40 | ForEach-Object { [pscustomobject]@{ itemId = [string]$_.itemId; viewModelItemId = [string]$_.viewModelItemId; modifierId = [string]$_.modifierId; tooltipType = [string]$_.nativeTooltipType; stock = [int]$_.stock; nativeItemCost = [int]$_.nativeItemCost; quoteUnitPrice = [int]$_.inventoryLogicUnitPrice; isTransferable = [bool]$_.isTransferable } })
    }
    $assertions['TownMarketBuysLootedGoods'] = ($offers.Count -ge 1)
    if (-not $assertions['TownMarketBuysLootedGoods']) { throw "The town market at '$townId' buys none of the loot the battle just produced." }
    $chosen = @($offers)[0]
    $units = [Math]::Min($SellUnits, [int]$chosen.stock)
    $record.sale['market'] = [ordered]@{
        settlementId = [string]$quote.data.settlementId
        settlementType = [string]$quote.data.settlementType
        merchantGold = [int]$quote.data.merchantGold
        playerGold = [int]$quote.data.playerGold
        sellOfferCount = @($offers).Count
    }
    $record.sale['good'] = [ordered]@{ itemId = [string]$chosen.itemId; viewModelItemId = [string]$chosen.viewModelItemId; name = [string]$chosen.name; unitPrice = [int]$chosen.inventoryLogicUnitPrice; stock = [int]$chosen.stock; soldUnits = $units }
    $draft = Invoke-AgentCli 'trade' @('-Direction', 'sell', '-ItemViewModelId', [string]$chosen.viewModelItemId, '-InventorySide', 'PlayerInventory', '-Amount', [string]$units, '-CommandId', "$commandPrefix-sell-draft")
    if ($draft.status -ne 'completed') { throw "The native sale draft of '$($chosen.itemId)' did not complete: status=$($draft.status)." }
    $confirm = Invoke-AgentCli 'tradeConfirm' @('-CommandId', "$commandPrefix-sell-confirm")
    if ($confirm.status -notin @('completed', 'accepted')) { throw "Native tradeConfirm did not accept the loot sale: status=$($confirm.status)." }
    $null = Close-Market 'loot-sale'
    $afterSale = Invoke-Checkpoint 'after-sale'
    $goldDelta = [int]$afterSale.state.economy.gold - [int]$beforeSale.state.economy.gold
    $quotedTotal = [int]$chosen.inventoryLogicUnitPrice * $units
    $record.sale['result'] = [ordered]@{
        goldBefore = [int]$beforeSale.state.economy.gold
        goldAfter = [int]$afterSale.state.economy.gold
        goldDelta = $goldDelta
        quotedTotal = $quotedTotal
        itemCountBefore = [int]$beforeSale.state.party.itemCount
        itemCountAfter = [int]$afterSale.state.party.itemCount
        campaignDayBefore = [double]$beforeSale.state.campaignDay
        campaignDayAfter = [double]$afterSale.state.campaignDay
        confirmReceipt = $confirm.data
    }
    $assertions['LootSaleBankedGold'] = ($goldDelta -gt 0)
    $settledAmount = [Math]::Abs([int]$confirm.data.nativeTransactionAmount)
    $record.sale['result']['settledUnitPrice'] = if ($units -gt 0) { [double]$settledAmount / $units } else { $null }
    $assertions['LootSalePaidTheSettlement'] = ($goldDelta -eq $settledAmount -and $settledAmount -gt 0)
    $assertions['QuoteMatchedTheSettlement'] = ($quotedTotal -eq $settledAmount)
    $assertions['LootSaleKeptCampaignTime'] = ([double]$afterSale.state.campaignDay -eq [double]$beforeSale.state.campaignDay)
}
finally {
    try {
        if ($null -ne $start) { $null = Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-stop") }
    } catch { $record['stopError'] = $_.Exception.Message }
    $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $record['fixtureSha256After'] = $fixtureHashAfter
    $assertions['FixtureUnchanged'] = ($fixtureHashAfter -eq $fixtureHashBefore)
    Start-Sleep -Seconds 3
    $assertions['ProcessStopped'] = ((Get-BannerlordProcesses).Count -eq 0)
    $record['passed'] = (@($assertions.Values | Where-Object { -not $_ }).Count -eq 0)
    $record | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding utf8
    Write-Output ('Receipt: ' + $resultPath)
    if (-not $record.passed) {
        $failed = @($assertions.Keys | Where-Object { -not $assertions[$_] })
        throw ('Battle loot sale probe failed these assertions: ' + ($failed -join ', '))
    }
}
