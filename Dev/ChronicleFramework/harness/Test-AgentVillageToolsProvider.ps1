#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
$reader = New-Object System.IO.StreamReader -ArgumentList @([Console]::OpenStandardInput(), [System.Text.Encoding]::UTF8, $true)
try { $inputJson = $reader.ReadToEnd() }
finally { $reader.Dispose() }
$jsonStart = $inputJson.IndexOf('{')
if ($jsonStart -lt 0) { throw 'Village Tools decision input has no JSON object.' }
if ($jsonStart -gt 0) {
    $prefix = $inputJson.Substring(0, $jsonStart)
    if ($prefix -notmatch '^[\s\p{C}]*$') { throw 'Village Tools decision input has non-whitespace before the JSON object.' }
    $inputJson = $inputJson.Substring($jsonStart)
}
$request = $inputJson | ConvertFrom-Json
if ($request.schemaVersion -ne 1) { throw 'Unsupported Agent loop request schema.' }
$state = $request.observation.state
$previous = $request.previousActionReceipt
$safeRunId = ([string]$request.runId) -replace '[^A-Za-z0-9_-]', ''
$memoryPath = Join-Path $env:CHRONICLE_HARNESS_TEMP "VillageToolsAgentMemory-$safeRunId.json"
$memory = [ordered]@{
    schemaVersion = 1
    visitedVillages = @()
    visitedMarkets = @()
    scenarioTargetId = $null
    currentTargetId = $null
    marketStatus = $null
    homeVillageId = $null
    giverHeroId = $null
    questId = $null
    questTitle = $null
    questStageDescription = $null
    taskName = $null
    targetCount = 0
    currentProgress = 0
    requestedItemSearch = $null
    rewardItemName = $null
    rewardItemCount = 0
    marketTownId = $null
    toolsItemId = $null
    toolsCountBeforeDelivery = $null
    rewardItemId = $null
    rewardCountBeforeDelivery = 0
    preDeliveryGold = $null
    postDeliveryGold = $null
    goldRewardObserved = $false
    questMarkerObserved = $false
    questAcceptanceOptionObserved = $false
    deliveryOptionObserved = $false
    deliverySelected = $false
    verification = $null
    stopReason = $null
}
if (Test-Path -LiteralPath $memoryPath) {
    $saved = Get-Content -LiteralPath $memoryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($property in $saved.PSObject.Properties) { $memory[$property.Name] = $property.Value }
}
if ([string]::IsNullOrWhiteSpace([string]$memory.scenarioTargetId) -and -not [string]::IsNullOrWhiteSpace([string]$env:CHRONICLE_VILLAGE_TOOLS_SCENARIO_TARGET_ID)) {
    $memory.scenarioTargetId = [string]$env:CHRONICLE_VILLAGE_TOOLS_SCENARIO_TARGET_ID
}

function Save-Memory {
    $memory | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $memoryPath -Encoding UTF8
}

function Emit-Action([string]$Action, [hashtable]$Arguments, [string]$Rationale) {
    $overlaySnapshot = @($state.settlementOverlayCharacters | ForEach-Object {
        [ordered]@{
            heroId = [string]$_.heroId
            isNotable = [bool]$_.isNotable
            issueMarkers = @($_.questMarkers | Where-Object { [string]$_.type -eq 'AvailableIssue' } | ForEach-Object { [ordered]@{ type = [string]$_.type; title = [string]$_.title; hint = [string]$_.hint } })
        }
    })
    $memory.lastDecision = [ordered]@{ action = $Action; rationale = $Rationale; gameState = [string]$state.context.gameState; menuId = [string]$state.context.menuId; currentSettlementId = [string]$state.location.currentSettlementId; currentTargetId = [string]$state.location.targetSettlementId; overlay = $overlaySnapshot }
    $memory.recentDecisions = @(@($memory.recentDecisions) + @($memory.lastDecision) | Select-Object -Last 6)
    Save-Memory
    [pscustomobject]@{ action = $Action; arguments = $Arguments; rationale = $Rationale } | ConvertTo-Json -Depth 10 -Compress
    exit 0
}

function Emit-Done([string]$Reason) {
    $memory.stopReason = $Reason
    $memory.lastDecision = [ordered]@{
        action = 'done'
        rationale = $Reason
        gameState = [string]$state.context.gameState
        menuId = [string]$state.context.menuId
        currentSettlementId = [string]$state.location.currentSettlementId
        activeQuest = [bool]$activeQuest
        conversationOptions = @($state.context.conversation.options | ForEach-Object { [ordered]@{ id = [string]$_.id; clickable = [bool]$_.clickable; text = [string]$_.text } })
        issueOverlays = @($state.settlementOverlayCharacters | Where-Object { @($_.questMarkers).Count -gt 0 } | ForEach-Object { [ordered]@{ heroId = [string]$_.heroId; questMarkers = @($_.questMarkers | ForEach-Object { [ordered]@{ type = [string]$_.type; title = [string]$_.title } }) } })
    }
    $memory.recentDecisions = @(@($memory.recentDecisions) + @($memory.lastDecision) | Select-Object -Last 6)
    Save-Memory
    [pscustomobject]@{ done = $true; reason = $Reason } | ConvertTo-Json -Depth 10 -Compress
    exit 0
}

function Get-ClickableOption($Options, [string]$Id) {
    return @($Options | Where-Object { [string]$_.id -eq $Id -and [bool]$_.clickable } | Select-Object -First 1)
}

function Get-SettlementLeaveOption($Options) {
    return @($Options | Where-Object { $_.isLeave -and $_.enabled -and $_.available } | Select-Object -First 1)
}

function Get-MarketData($Receipt) {
    if (-not $Receipt -or $Receipt.action -ne 'tradeOptions' -or $Receipt.status -ne 'completed') { return $null }
    return $Receipt.data
}

function Get-CurrentVillageToolsQuest($Quests) {
    return @($Quests | Where-Object { ([string]$_.title).Contains('工具') -or ([string]$_.title -match 'tools') } | Select-Object -First 1)
}

function Update-QuestMemory($Details) {
    $stageRows = @($Details.journalStages | Where-Object { $_.hasTask } | Select-Object -First 1)
    if ($stageRows.Count -eq 0) { return $false }
    $stage = $stageRows[0]
    $memory.questId = [string]$Details.questId
    $memory.questTitle = [string]$Details.title
    $memory.questStageDescription = [string]$stage.description
    $memory.taskName = [string]$stage.taskName
    $memory.currentProgress = [int]$stage.currentProgress
    $memory.targetCount = [int]$stage.targetProgress
    $visibleText = ([string]$stage.description + ' ' + [string]$stage.taskName)
    if ($visibleText -match '工具') { $memory.requestedItemSearch = '工具' }
    elseif ($visibleText -match '(?i)tools?') { $memory.requestedItemSearch = 'tools?' }
    else { $memory.requestedItemSearch = $null }
    $rewardText = ([string]$stage.description -replace '<[^>]+>', '')
    $rewardMatch = [regex]::Match($rewardText, '给你\s*(\d+)\s*单位\s*([^，。]+?)\s*作为报酬')
    if ($rewardMatch.Success) {
        $memory.rewardItemCount = [int]$rewardMatch.Groups[1].Value
        $memory.rewardItemName = $rewardMatch.Groups[2].Value.Trim()
    }
    return $true
}

if (-not $state) { throw 'Village Tools provider received no current Native game state.' }
if ($previous -and $previous.action -eq 'questDetails' -and $previous.status -eq 'completed') {
    if (-not (Update-QuestMemory $previous.data)) { Emit-Done 'The observed active Quest has no readable task row in the Native Journal.' }
    if ($memory.verification -eq 'check-progress-after-buy') {
        if ($memory.currentProgress -ge $memory.targetCount -and $memory.targetCount -gt 0) { $memory.verification = 'snapshot-before-delivery' }
        else { $memory.verification = 'buyTools' }
    }
}
if ($previous -and $previous.action -eq 'tradeConfirm' -and $previous.status -eq 'completed' -and $previous.data.committed) {
    $memory.lastCommittedTrade = $previous.data
    $memory.verification = 'check-progress-after-buy'
    $memory.marketStatus = 'pending'
}
if ($previous -and $previous.action -eq 'dialogueSelect' -and $memory.deliverySelected -and $previous.status -eq 'completed') {
    $memory.postDeliveryGold = [int]$state.economy.gold
    $memory.goldRewardObserved = ([int]$memory.postDeliveryGold -gt [int]$memory.preDeliveryGold)
    $memory.postDeliveryPartyItemCount = [int]$state.party.itemCount
    $memory.questRewardNetItemDelta = [int]$memory.postDeliveryPartyItemCount - [int]$memory.preDeliveryPartyItemCount
    $memory.questRewardRosterDeltaMatches = ($memory.rewardItemCount -gt 0 -and ($memory.questRewardNetItemDelta + [int]$memory.targetCount) -eq [int]$memory.rewardItemCount)
    $questStillActiveAfterTurnIn = @($state.quests | Where-Object { [string]$_.id -eq [string]$memory.questId }).Count -gt 0
    if (-not $questStillActiveAfterTurnIn -and [int]$memory.toolsCountBeforeDelivery -ge [int]$memory.targetCount -and [bool]$memory.questRewardRosterDeltaMatches) {
        $memory.verification = 'inventory-check-needed'
        $memory.verificationEvidence = 'Native turn-in closed the active Quest; the current market had shown the requested Tool quantity before travel back, and the immediate MainParty total-item delta plus consumed tools matched the Quest Journal reward quantity. Verify exact item IDs/counts in the native MainHero inventory.'
    }
}

$gameState = [string]$state.context.gameState
$menuId = [string]$state.context.menuId
$conversation = $state.context.conversation
$currentSettlement = [string]$state.location.currentSettlementId
$currentMoveTarget = [string]$state.location.targetSettlementId
if (-not [string]::IsNullOrWhiteSpace([string]$memory.currentTargetId) -and $currentSettlement -eq [string]$memory.currentTargetId) { $memory.currentTargetId = $null }
$movingTowardCurrentTarget = (-not [string]::IsNullOrWhiteSpace([string]$memory.currentTargetId) -and $currentMoveTarget -eq [string]$memory.currentTargetId -and $currentSettlement -ne [string]$memory.currentTargetId)
$visibleQuest = @(Get-CurrentVillageToolsQuest -Quests $state.quests)
$activeQuest = $false
if ($visibleQuest.Count -gt 0) {
    $memory.questId = [string]$visibleQuest[0].id
    $memory.questTitle = [string]$visibleQuest[0].title
    $activeQuest = $true
}
elseif (-not [string]::IsNullOrWhiteSpace([string]$memory.questId)) {
    $activeQuest = @($state.quests | Where-Object { [string]$_.id -eq [string]$memory.questId }).Count -gt 0
}

if ($memory.verification -eq 'passed' -and -not $conversation) { Emit-Done 'The Quest is no longer active; native turn-in consequences match the Journal reward and the QuickConversation has returned to Campaign.' }
if ($memory.verification -eq 'failed') { Emit-Done ('The Quest route ended but inventory outcome verification failed: ' + [string]$memory.verificationDetails) }
if ($memory.questId -and -not $activeQuest -and -not $memory.deliverySelected) { Emit-Done 'The naturally active Quest ended before its observed Native turn-in option was selected.' }

if ($state.context.battleSimulation -and $gameState -in @('PartyState','InventoryState')) { $memory.nativeBattleResultReached = $true; Save-Memory }
if ($state.context.battleSimulation -and -not [bool]$memory.nativeBattleResultReached -and $gameState -notin @('PartyState','InventoryState')) {
    if ([bool]$state.context.battleSimulation.finished) { Emit-Action 'battleFinish' @{} 'Finish the completed Native Send Troops simulation through the Campaign encounter handler.' }
    if ($previous -and $previous.action -eq 'battleSkip') { Emit-Action 'state' @{} 'Reobserve the Native auto-resolving battle until its simulation result is complete.' }
    Emit-Action 'battleSkip' @{} 'Use Native Send Troops simulation rather than entering a real-time battle Mission.'
}

if ($gameState -eq 'MapState' -and $menuId -eq 'encounter_meeting') {
    if ($conversation -and @($conversation.options).Count -eq 0) { Emit-Action 'dialogueContinue' @{} 'Advance the current hostile-encounter dialogue node after the peaceful response was selected.' }
    $peacefulOption = @(Get-ClickableOption -Options @($conversation.options) -Id 'bandit_start_defender_2')
    if ($peacefulOption.Count -eq 1) { Emit-Action 'dialogueSelect' @{ OptionId = [string]$peacefulOption[0].id } 'A hostile Party interrupted travel; choose the currently visible peaceful solution before resuming the Quest route.' }
    Emit-Done 'A hostile Party interrupted the Quest route, but the current Native encounter exposes no known peaceful choice.'
}

if ($gameState -eq 'PartyState' -and [string]$state.partyScreen.mode -eq 'Loot') {
    $membersToTake = @($state.partyScreen.leftMembers | Where-Object { $_.transferable -and [int]$_.count -gt 0 })
    if ($membersToTake.Count -gt 0) { Emit-Action 'partyTakeAll' @{ LootType = 'members' } 'Transfer surviving Native member-roster loot through the Party aftermath handler.' }
    $prisonersToTake = @($state.partyScreen.leftPrisoners | Where-Object { $_.transferable -and [int]$_.count -gt 0 })
    if ($prisonersToTake.Count -gt 0) { Emit-Action 'partyTakeAll' @{ LootType = 'prisoners' } 'Transfer Native prisoner-roster loot through the Party aftermath handler.' }
    Emit-Action 'partyScreenDone' @{} 'Close Native post-battle Party aftermath after taking currently transferable member/prisoner loot.'
}

if ($gameState -eq 'InventoryState') {
    if ([string]$state.inventoryScreen.mode -eq 'Loot') {
        if ([int]$state.inventoryScreen.lootItemCount -gt 0) { Emit-Action 'inventoryTakeAll' @{} 'Take current Native battle loot before closing its result inventory.' }
        Emit-Action 'inventoryDone' @{} 'Close the Native battle-loot inventory after taking the currently available items.'
    }
    if ($memory.verification -eq 'inventory-check-needed') {
        if ([string]$state.inventoryScreen.mode -ne 'Default') { Emit-Done ('Post-turn-in inventory check encountered Native mode ' + [string]$state.inventoryScreen.mode + '; do not substitute a TradeView stock estimate.') }
        if ($previous -and $previous.action -eq 'heroEquipmentOptions' -and $previous.status -eq 'completed') {
            $inventoryRows = @($previous.data.rightItems)
            $toolsInventoryRows = @($inventoryRows | Where-Object { [string]$_.itemId -eq [string]$memory.toolsItemId })
            if ($memory.rewardItemId) { $rewardInventoryRows = @($inventoryRows | Where-Object { [string]$_.itemId -eq [string]$memory.rewardItemId }) }
            else { $rewardInventoryRows = @($inventoryRows | Where-Object { [string]$_.name -match [regex]::Escape([string]$memory.rewardItemName) }) }
            $memory.toolsCountAfterDelivery = [int](($toolsInventoryRows | Measure-Object -Property itemCount -Sum).Sum)
            $memory.rewardCountAfterDelivery = [int](($rewardInventoryRows | Measure-Object -Property itemCount -Sum).Sum)
            $memory.rewardInventoryRowCount = $rewardInventoryRows.Count
            $memory.rewardInventoryCountMatched = ($memory.rewardItemCount -le 0) -or ($memory.rewardCountAfterDelivery -ge ([int]$memory.rewardCountBeforeDelivery + [int]$memory.rewardItemCount))
            if ($memory.toolsCountAfterDelivery -eq 0 -and $memory.rewardInventoryCountMatched) { $memory.verification = 'passed' }
            else {
                $memory.verification = 'failed'
                $memory.verificationDetails = [ordered]@{ toolsAfterNativeInventory = $memory.toolsCountAfterDelivery; rewardItemId = $memory.rewardItemId; rewardExpected = $memory.rewardItemCount; rewardBeforeNativeTrade = $memory.rewardCountBeforeDelivery; rewardAfterNativeInventory = $memory.rewardCountAfterDelivery; rewardInventoryRowCount = $memory.rewardInventoryRowCount }
            }
            Emit-Action 'inventoryCancel' @{} 'Close the unchanged Native MainHero inventory through its Cancel/back handler after checking exact Tools and reward item IDs/counts.'
        }
        if ($previous -and $previous.action -eq 'inventoryCancel' -and $previous.status -eq 'completed' -and $memory.verification -eq 'passed') { Emit-Done 'The Native Quest ended, exact requested/reward item counts were verified in MainHero inventory, and QuickConversation returned to the giver settlement menu.' }
        if ($previous -and $previous.action -eq 'inventoryCancel' -and $previous.status -eq 'completed' -and $memory.verification -eq 'failed') { Emit-Done ('Native post-turn-in inventory verification failed: ' + [string]$memory.verificationDetails) }
        if ($previous -and $previous.action -eq 'inventoryOpen' -and $previous.status -eq 'completed') { Emit-Action 'heroEquipmentOptions' @{} 'Read exact current MainHero inventory items from the Native Inventory VM.' }
        Emit-Action 'inventoryOpen' @{} 'Open the Native MainHero inventory after returning to Campaign so exact reward item identities/counts can be verified.'
    }
    if ([string]$state.inventoryScreen.mode -ne 'Trade') { Emit-Done 'The deterministic Quest path encountered a non-Trade InventoryState; no unrelated inventory control will be used.' }
    if ($previous -and $previous.action -eq 'trade' -and $previous.status -eq 'completed') { Emit-Action 'tradeConfirm' @{} 'Commit only the currently observed Native Trade draft through its original Done handler.' }
    $market = Get-MarketData $previous
    if (-not $market) { Emit-Action 'tradeOptions' @{} 'Read the current Native market and player inventory sides before choosing a transaction.' }

    if ($memory.verification -eq 'snapshot-before-delivery') {
        $toolsRow = @($market.sellOffers | Where-Object { [string]$_.itemId -eq [string]$memory.toolsItemId -and [string]$_.inventorySide -eq 'PlayerInventory' } | Select-Object -First 1)
        $memory.toolsCountBeforeDelivery = if ($toolsRow.Count -eq 1) { [int]$toolsRow[0].stock } else { 0 }
        if (-not $memory.rewardItemId -and $memory.rewardItemName) {
            $rewardRow = @($market.sellOffers + $market.buyOffers | Where-Object { [string]$_.name -match [regex]::Escape([string]$memory.rewardItemName) } | Select-Object -First 1)
            if ($rewardRow.Count -eq 1) { $memory.rewardItemId = [string]$rewardRow[0].itemId }
        }
        $rewardPlayerRow = @($market.sellOffers | Where-Object { [string]$_.itemId -eq [string]$memory.rewardItemId -and [string]$_.inventorySide -eq 'PlayerInventory' } | Select-Object -First 1)
        $memory.rewardCountBeforeDelivery = if ($rewardPlayerRow.Count -eq 1) { [int]$rewardPlayerRow[0].stock } else { 0 }
        $memory.verification = 'return-to-giver'
        Emit-Action 'tradeCancel' @{} 'Record Native player-side goods before delivery; close the read-only Trade view without changing anything.'
    }

    if ($memory.verification -eq 'verify-after-delivery') {
        $toolsAfterRow = @($market.sellOffers | Where-Object { [string]$_.itemId -eq [string]$memory.toolsItemId -and [string]$_.inventorySide -eq 'PlayerInventory' } | Select-Object -First 1)
        $rewardAfterRow = @($market.sellOffers | Where-Object { [string]$_.itemId -eq [string]$memory.rewardItemId -and [string]$_.inventorySide -eq 'PlayerInventory' } | Select-Object -First 1)
        $memory.toolsCountAfterDelivery = if ($toolsAfterRow.Count -eq 1) { [int]$toolsAfterRow[0].stock } else { 0 }
        $memory.rewardCountAfterDelivery = if ($rewardAfterRow.Count -eq 1) { [int]$rewardAfterRow[0].stock } else { 0 }
        $toolsConsumed = ([int]$memory.toolsCountBeforeDelivery - [int]$memory.toolsCountAfterDelivery) -eq [int]$memory.targetCount
        $tradeVmRewardCountMatches = ($memory.rewardItemCount -le 0) -or (([int]$memory.rewardCountAfterDelivery - [int]$memory.rewardCountBeforeDelivery) -eq [int]$memory.rewardItemCount)
        $rewardReceived = $tradeVmRewardCountMatches -or [bool]$memory.questRewardRosterDeltaMatches
        $cashRewardObserved = (-not $memory.rewardItemName) -and ([int]$memory.postDeliveryGold -gt [int]$memory.preDeliveryGold)
        if ($toolsConsumed -and ($rewardReceived -or $cashRewardObserved)) { $memory.verification = 'passed' }
        else {
            $memory.verification = 'failed'
            $memory.verificationDetails = [ordered]@{ toolsBefore = $memory.toolsCountBeforeDelivery; toolsAfter = $memory.toolsCountAfterDelivery; toolsRequired = $memory.targetCount; rewardName = $memory.rewardItemName; rewardExpected = $memory.rewardItemCount; rewardBeforeTradeVm = $memory.rewardCountBeforeDelivery; rewardAfterTradeVm = $memory.rewardCountAfterDelivery; preDeliveryPartyItemCount = $memory.preDeliveryPartyItemCount; postDeliveryPartyItemCount = $memory.postDeliveryPartyItemCount; rewardNetItemDelta = $memory.questRewardNetItemDelta; tradeVmRewardCountMatches = $tradeVmRewardCountMatches; rewardRosterDeltaMatches = $memory.questRewardRosterDeltaMatches; preDeliveryGold = $memory.preDeliveryGold; postDeliveryGold = $memory.postDeliveryGold }
        }
        Emit-Action 'tradeCancel' @{} 'Finish the read-only post-turn-in inventory check and close the Native Trade view.'
    }

    $needed = [int]$memory.targetCount - [int]$memory.currentProgress
    $matches = @($market.buyOffers | Where-Object { $_.isTransferable -and [int]$_.stock -gt 0 -and (([string]$_.name -match '工具') -or ([string]$_.name -match '(?i)tools?')) } | Sort-Object inventoryLogicUnitPrice)
    $offer = @($matches | Select-Object -First 1)
    if ($offer.Count -eq 1 -and $needed -gt 0) {
        $unitPrice = [Math]::Max(1, [int]$offer[0].inventoryLogicUnitPrice)
        $affordable = [int][Math]::Floor([double]$state.economy.gold / $unitPrice)
        $amount = [Math]::Min($needed, [Math]::Min([int]$offer[0].stock, $affordable))
        if ($amount -gt 0) {
            $memory.toolsItemId = [string]$offer[0].itemId
            $memory.marketTownId = [string]$market.settlementId
            Emit-Action 'trade' @{ Direction = 'buy'; ItemViewModelId = [string]$offer[0].viewModelItemId; InventorySide = 'OtherInventory'; Amount = $amount } 'Buy the currently visible requested Tools item from this Native market only within its displayed stock and player Gold.'
        }
    }
    $memory.marketStatus = 'exhausted'
    if ([string]$market.settlementId -notin @($memory.visitedMarkets)) { $memory.visitedMarkets += [string]$market.settlementId }
    Emit-Action 'tradeCancel' @{} 'No affordable in-stock Tools candidate is currently visible; close the unchanged Native market transaction.'
}

if ($activeQuest -and ($memory.targetCount -le 0 -or $null -eq $memory.currentProgress)) {
    Emit-Action 'questDetails' @{ QuestId = [string]$memory.questId } 'Read this observed active Quest task from the Native Journal.'
}
if ($activeQuest -and $memory.verification -eq 'check-progress-after-buy') {
    Emit-Action 'questDetails' @{ QuestId = [string]$memory.questId } 'Refresh the player-visible Quest task progress after the Native Trade commit.'
}

if ($conversation) {
    if ($memory.deliverySelected -and -not $activeQuest) {
        if ($gameState -eq 'MissionState') { Emit-Action 'missionLeave' @{} 'Close the completed Quest-giver Location Mission through the Native Leave Area hold.' }
        if (@($conversation.options | Where-Object { $_.clickable -and ([string]$_.id -eq 'player_is_leaving_neutral_or_friendly') }).Count -eq 1) {
            Emit-Action 'dialogueSelect' @{ OptionId = 'player_is_leaving_neutral_or_friendly' } 'Close the completed Native QuickConversation using its currently visible leave option.'
        }
        if (@($conversation.options).Count -eq 0) { Emit-Action 'dialogueContinue' @{} 'Advance the completed Native Conversation back to the settlement menu.' }
        Emit-Done 'The Quest has ended after delivery, but its current conversation exposes no observed way to return to the settlement menu.'
    }
    if (@($conversation.options).Count -eq 0) { Emit-Action 'dialogueContinue' @{} 'Advance the currently observed Native conversation node with no selectable responses.' }
    if ($conversation -and $activeQuest -and $memory.currentProgress -ge $memory.targetCount -and $memory.targetCount -gt 0) {
        $turnIn = $null
        foreach ($option in $conversation.options) {
            $optionText = [string]$option.text
            $chineseTurnIn = ($optionText -match '带') -and ($optionText -match '工具')
            $englishTurnIn = ($optionText -match '(?i)brought') -and ($optionText -match '(?i)tools')
            if ($option.clickable -and ($chineseTurnIn -or $englishTurnIn)) { $turnIn = $option; break }
        }
        if ($null -ne $turnIn) {
            $memory.deliveryOptionObserved = $true
            $memory.deliverySelected = $true
            $memory.preDeliveryGold = [int]$state.economy.gold
            $memory.preDeliveryPartyItemCount = [int]$state.party.itemCount
            Emit-Action 'dialogueSelect' @{ OptionId = [string]$turnIn[0].id } 'Select the currently visible Native Quest turn-in option after its Journal task reached the requested count.'
        }
        $taskTopic = @(Get-ClickableOption -Options @($conversation.options) -Id 'hero_task_given')
        if ($taskTopic.Count -eq 1) { Emit-Action 'dialogueSelect' @{ OptionId = [string]$taskTopic[0].id } 'Open the currently visible Native Quest topic with the giver to reveal the delivery response.' }
        if (@($conversation.options).Count -eq 0) { Emit-Action 'dialogueContinue' @{} 'Advance the current Quest-giver Conversation because its displayed option list is empty.' }
        Emit-Done 'The Native Journal shows all requested goods, but no current delivery option is displayed to select.'
    }
    if ($conversation -and -not $activeQuest) {
        $memory.conversationBranchEntered = $true
        $options = @($conversation.options)
        $acceptQuest = @(Get-ClickableOption -Options $options -Id 'issue_offer_player_accept_quest')
        if ($acceptQuest.Count -eq 1) {
            $memory.questAcceptanceOptionObserved = $true
            Emit-Action 'dialogueSelect' @{ OptionId = [string]$acceptQuest[0].id } 'Choose the current Native Quest solution, not a separate Alternative or Lord solution.'
        }
        foreach ($optionId in @('hero_give_issue','issue_explanation_player_response_pre_quest_solution','issue_alternative_solution_player_response','lord_meet_player_response1')) {
            $option = @(Get-ClickableOption -Options $options -Id $optionId)
            if ($option.Count -eq 1) { Emit-Action 'dialogueSelect' @{ OptionId = [string]$option[0].id } 'Advance only an observed clickable Native issue/topic explanation option.' }
        }
        $memory.matchedIssueOptionIds = @($options | Where-Object { $_.clickable -and [string]$_.id -in @('hero_give_issue','issue_explanation_player_response_pre_quest_solution','issue_alternative_solution_player_response','lord_meet_player_response1') } | ForEach-Object { [string]$_.id })
        if ($options.Count -eq 0) { Emit-Action -Action 'dialogueContinue' -Arguments @{} -Rationale "Advance the current Native Conversation because its observed option list is empty." }
    }
    Emit-Done 'The current Native QuickConversation has no visible, eligible Quest path option; stop without selecting an inferred branch.'
}

if ($gameState -eq 'MissionState') {
    Emit-Action -Action 'missionLeave' -Arguments @{} -Rationale "Return from the current player-controlled Settlement Location Mission using the Native Leave Area hold."
}

if ($gameState -eq 'InventoryState') {
    if ([string]$state.inventoryScreen.mode -ne 'Trade') { Emit-Done 'The task reached a non-Trade inventory screen; no unrelated inventory action is permitted.' }
    if ($previous -and $previous.action -eq 'trade' -and $previous.status -eq 'completed') {
        $memory.verification = 'check-progress-after-buy'
        Emit-Action 'tradeConfirm' @{} 'Commit the current Native Trade purchase using its original Done handler.'
    }
    $market = Get-MarketData $previous
    if (-not $market) { Emit-Action 'tradeOptions' @{} 'Read current Native Trade market/player candidates before selecting a transaction.' }
    if ($memory.verification -eq 'snapshot-before-delivery') {
        $toolsRow = @($market.sellOffers | Where-Object { [string]$_.itemId -eq [string]$memory.toolsItemId -and [string]$_.inventorySide -eq 'PlayerInventory' } | Select-Object -First 1)
        $memory.toolsCountBeforeDelivery = if ($toolsRow.Count -eq 1) { [int]$toolsRow[0].stock } else { 0 }
        if (-not $memory.rewardItemId -and $memory.rewardItemName) {
            $rewardRow = @($market.sellOffers + $market.buyOffers | Where-Object { [string]$_.name -match [regex]::Escape([string]$memory.rewardItemName) } | Select-Object -First 1)
            if ($rewardRow.Count -eq 1) { $memory.rewardItemId = [string]$rewardRow[0].itemId }
        }
        $rewardPlayerRow = @($market.sellOffers | Where-Object { [string]$_.itemId -eq [string]$memory.rewardItemId -and [string]$_.inventorySide -eq 'PlayerInventory' } | Select-Object -First 1)
        $memory.rewardCountBeforeDelivery = if ($rewardPlayerRow.Count -eq 1) { [int]$rewardPlayerRow[0].stock } else { 0 }
        $memory.verification = 'return-to-giver'
        Emit-Action 'tradeCancel' @{} 'Capture player-side Tools/reward baseline from the Native market, then close the unchanged Trade view.'
    }
    if ($memory.verification -eq 'verify-after-delivery') {
        $toolsRow = @($market.sellOffers | Where-Object { [string]$_.itemId -eq [string]$memory.toolsItemId -and [string]$_.inventorySide -eq 'PlayerInventory' } | Select-Object -First 1)
        $rewardRow = @($market.sellOffers | Where-Object { [string]$_.itemId -eq [string]$memory.rewardItemId -and [string]$_.inventorySide -eq 'PlayerInventory' } | Select-Object -First 1)
        $memory.toolsCountAfterDelivery = if ($toolsRow.Count -eq 1) { [int]$toolsRow[0].stock } else { 0 }
        $memory.rewardCountAfterDelivery = if ($rewardRow.Count -eq 1) { [int]$rewardRow[0].stock } else { 0 }
        $toolsConsumed = ([int]$memory.toolsCountBeforeDelivery - [int]$memory.toolsCountAfterDelivery) -eq [int]$memory.targetCount
        $rewardReceived = ($memory.rewardItemCount -le 0) -or (([int]$memory.rewardCountAfterDelivery - [int]$memory.rewardCountBeforeDelivery) -eq [int]$memory.rewardItemCount)
        $cashRewardObserved = (-not $memory.rewardItemName) -and ([int]$memory.postDeliveryGold -gt [int]$memory.preDeliveryGold)
        if ($toolsConsumed -and ($rewardReceived -or $cashRewardObserved)) { $memory.verification = 'passed' }
        else {
            $memory.verification = 'failed'
            $memory.verificationDetails = [ordered]@{ toolsBefore = $memory.toolsCountBeforeDelivery; toolsAfter = $memory.toolsCountAfterDelivery; toolsRequired = $memory.targetCount; rewardName = $memory.rewardItemName; rewardExpected = $memory.rewardItemCount; rewardBefore = $memory.rewardCountBeforeDelivery; rewardAfter = $memory.rewardCountAfterDelivery; preDeliveryGold = $memory.preDeliveryGold; postDeliveryGold = $memory.postDeliveryGold }
        }
        Emit-Action 'tradeCancel' @{} 'Finish the read-only player-side inventory verification and close the Native Trade view.'
    }
    if ($memory.verification -eq 'failed') { Emit-Done ('Inventory verification failed: ' + [string]$memory.verificationDetails) }
    if ($memory.verification -eq 'passed') { Emit-Done 'The native Quest is no longer active; Trade VM confirms requested Tools were consumed and the displayed reward was received.' }

    if ($memory.verification -eq 'check-progress-after-buy') { Emit-Action 'tradeCancel' @{} 'The committed purchase has left the Trade draft; return to Campaign to read the resulting Quest Journal progress.' }
    if ($memory.currentProgress -ge $memory.targetCount -and $memory.targetCount -gt 0) {
        $rewardCandidate = @($market.buyOffers | Where-Object { [string]$_.name -match [regex]::Escape([string]$memory.rewardItemName) } | Select-Object -First 1)
        if ($rewardCandidate.Count -eq 1) { $memory.rewardItemId = [string]$rewardCandidate[0].itemId }
        $memory.verification = 'snapshot-before-delivery'
        Emit-Action 'tradeOptions' @{} 'Refresh current Native Trade candidates before recording the player-side delivery baseline.'
    }
    $needed = [int]$memory.targetCount - [int]$memory.currentProgress
    $toolOffer = @($market.buyOffers | Where-Object { $_.isTransferable -and [int]$_.stock -gt 0 -and (([string]$_.name -match '工具') -or ([string]$_.name -match '(?i)tools?')) } | Sort-Object inventoryLogicUnitPrice | Select-Object -First 1)
    if ($toolOffer.Count -eq 1 -and $needed -gt 0) {
        $unitPrice = [Math]::Max(1, [int]$toolOffer[0].inventoryLogicUnitPrice)
        $affordable = [int][Math]::Floor([double]$state.economy.gold / $unitPrice)
        $amount = [Math]::Min($needed, [Math]::Min([int]$toolOffer[0].stock, $affordable))
        if ($amount -gt 0) {
            $memory.toolsItemId = [string]$toolOffer[0].itemId
            $memory.marketTownId = [string]$market.settlementId
            Emit-Action 'trade' @{ Direction = 'buy'; ItemViewModelId = [string]$toolOffer[0].viewModelItemId; InventorySide = 'OtherInventory'; Amount = $amount } 'Buy only the currently visible requested Tools from this Native Town market within stock and Gold.'
        }
    }
    $memory.marketStatus = 'exhausted'
    if ([string]$market.settlementId -notin @($memory.visitedMarkets)) { $memory.visitedMarkets += [string]$market.settlementId }
    Emit-Action 'tradeCancel' @{} 'No affordable Tools candidate is in current market stock; discard no trade draft.'
}

if ($gameState -eq 'MapState') {
    if ($memory.verification -eq 'inventory-check-needed' -and -not $conversation) { Emit-Action 'inventoryOpen' @{} 'Open the Native MainHero inventory after the QuickConversation returns to Campaign so exact reward items can be verified without another market trip.' }
    if ($menuId -eq 'menu_escape_captivity_during_battle') {
        $memory.captivityMenuObserved = $menuId
        $memory.captivityDetailsObserved = $state.context.captivity
        $continueCaptivity = @($state.availableMenuOptions | Where-Object { $_.id -eq 'mno_continue' -and $_.available -and $_.enabled } | Select-Object -First 1)
        if ($continueCaptivity.Count -eq 1) { Emit-Action 'menuSelect' @{ MenuId = $menuId; OptionId = 'mno_continue' } 'Advance the single currently visible Native captivity-result Continue choice to observe the next campaign state.' }
        Emit-Done 'The Native battle-captivity continuation has no currently visible enabled choice; preserve its state.'
    }
    if ($menuId -like 'menu_captivity_end_*') {
        $memory.captivityMenuObserved = $menuId
        $memory.captivityDetailsObserved = $state.context.captivity
        $memory.captivityOptionsObserved = @($state.availableMenuOptions | Where-Object { $_.available -and $_.enabled } | ForEach-Object { [ordered]@{ id = [string]$_.id; text = [string]$_.text } })
        $continueCaptivity = @($state.availableMenuOptions | Where-Object { $_.id -eq 'mno_continue' -and $_.available -and $_.enabled } | Select-Object -First 1)
        if ($continueCaptivity.Count -eq 1 -and @($state.availableMenuOptions | Where-Object { $_.available -and $_.enabled }).Count -eq 1) { Emit-Action 'menuSelect' @{ MenuId = $menuId; OptionId = 'mno_continue' } 'Advance the single currently visible Native captivity continuation, without choosing its later ransom/escape outcome.' }
        Emit-Done 'A Native captivity decision interrupted travel; preserve its visible options and do not fast-forward or choose a ransom/escape outcome without the policy decision.'
    }
    if ($menuId -eq 'encounter_meeting') {
        $memory.stopReason = 'An unplanned Native hostile-party conversation interrupted Village travel; preserve the visible dialogue and await a policy decision instead of repeating observations.'
        $memory.interruptedMenuId = $menuId
        $memory.interruptedMenuOptions = @($state.availableMenuOptions | Where-Object { $_.available -and $_.enabled } | ForEach-Object { [ordered]@{ id = [string]$_.id; text = [string]$_.text } })
        Emit-Done $memory.stopReason
    }
    if ($menuId -eq 'encounter') {
        $sendTroops = @($state.availableMenuOptions | Where-Object { $_.id -eq 'str_order_attack' -and $_.available -and $_.enabled } | Select-Object -First 1)
        if ($sendTroops.Count -eq 1) { Emit-Action 'menuSelect' @{ MenuId = 'encounter'; OptionId = 'str_order_attack' } 'Resolve this Native encounter with enabled Send Troops instead of entering a real-time battle Mission.' }
        $memory.encounterBlocker = [ordered]@{
            partySize = [int]$state.party.members
            sendTroopsEnabled = $false
            directAttackEnabled = @($state.availableMenuOptions | Where-Object { $_.id -eq 'attack' -and $_.available -and $_.enabled }).Count -eq 1
            surrenderEnabled = @($state.availableMenuOptions | Where-Object { $_.id -eq 'surrender' -and $_.available -and $_.enabled }).Count -eq 1
            hostileParties = @($state.nearbyParties | Where-Object hostile | Select-Object id,name,members,strength)
        }
        Emit-Done 'The Native encounter has no enabled Send Troops option; do not enter a real-time battle or surrender implicitly.'
    }
    if ($movingTowardCurrentTarget -and [bool]$state.party.isMoving -and [string]$state.context.timeControlMode -notin @('StoppableFastForward','UnstoppableFastForward')) {
        Emit-Action 'fastForward' @{} 'Explicitly choose Native fast-forward while the MainParty is already moving; movement itself remains the separate native travel order.'
    }
    if ($movingTowardCurrentTarget) { Emit-Action 'state' @{} 'Re-observe the Native Campaign travel already requested for the currently observed settlement target.' }
    if ($activeQuest -and $memory.verification -eq 'check-progress-after-buy') { Emit-Action 'questDetails' @{ QuestId = [string]$memory.questId } 'Refresh the public Quest Journal progress after the committed Native Trade.' }
    $toolsMarker = $false
    $toolsCandidate = @()
    foreach ($character in @($state.settlementOverlayCharacters)) {
        if (-not $character.isNotable) { continue }
        $marker = @($character.questMarkers | Where-Object { $markerText = [string]$_.title + ' ' + [string]$_.hint; [string]$_.type -eq 'AvailableIssue' -and ($markerText.Contains('工具') -or $markerText -match 'tools') } | Select-Object -First 1)
        if ($marker.Count -gt 0) { $toolsCandidate += [pscustomobject]@{ Character = $character; Marker = $marker[0] } }
    }
    $memory.lastObservedIssueCandidates = @($toolsCandidate | ForEach-Object { [ordered]@{ heroId = [string]$_.Character.heroId; name = [string]$_.Character.name; markerTitle = [string]$_.Marker.title; markerHint = [string]$_.Marker.hint } })
    if ($toolsCandidate.Count -gt 0 -and -not $activeQuest -and -not $memory.questId) {
        $memory.homeVillageId = $currentSettlement
        $memory.giverHeroId = [string]$toolsCandidate[0].Character.heroId
        $memory.questMarkerTitle = [string]$toolsCandidate[0].Marker.title
        $memory.questMarkerObserved = $true
        Emit-Action 'talkToSettlementHero' @{ HeroId = [string]$memory.giverHeroId } 'Use the currently visible Native QuickConversation (交谈) action on the Issue-marked Village Notable.'
    }

    if (-not $activeQuest -and $memory.questId -and -not $memory.deliverySelected) { Emit-Done 'The naturally active Village Tools Quest ended before its observed turn-in option was selected.' }

    if (-not [string]::IsNullOrWhiteSpace($menuId)) {
        if ($menuId -eq 'village' -and $currentSettlement -eq [string]$memory.homeVillageId -and -not [bool]$memory.recruitmentPrepared) {
            if ([int]$state.party.members -ge 5) { $memory.recruitmentPrepared = $true; Save-Memory }
            else {
                if ($previous -and $previous.action -eq 'recruit' -and $previous.status -eq 'completed' -and [int]$state.party.members -lt 5) { Emit-Action 'recruitOptions' @{} 'Refresh currently visible volunteer offers to continue preparing a small escort.' }
                if ($previous -and $previous.action -eq 'recruitOptions' -and $previous.status -eq 'completed') {
                    $reserveGold = 450
                    $affordableVolunteers = @($previous.data.offers | Where-Object { $_.available -and [int]$_.cost -le ([int]$state.economy.gold - $reserveGold) } | Sort-Object cost | Select-Object -First 1)
                    if ($affordableVolunteers.Count -eq 1) { Emit-Action 'recruit' @{ OwnerId = [string]$affordableVolunteers[0].ownerId; TroopId = [string]$affordableVolunteers[0].troopId; VolunteerSlot = [int]$affordableVolunteers[0].slot; ConfirmPartySizeWarning = $false } 'Recruit one currently offered village volunteer to form a small escort while preserving 450 Gold for requested goods and incidental costs.' }
                    else { $memory.recruitmentPrepared = $true; Save-Memory }
                }
                if (-not $memory.recruitmentPrepared) { Emit-Action 'recruitOptions' @{} 'Check currently available Native village volunteers before leaving alone on the Quest delivery route.' }
            }
        }
        if ($activeQuest -and $memory.verification -eq 'return-to-giver' -and $currentSettlement -eq [string]$memory.homeVillageId) {
            $giver = @($state.settlementOverlayCharacters | Where-Object { [string]$_.heroId -eq [string]$memory.giverHeroId } | Select-Object -First 1)
            if ($giver.Count -eq 1) { Emit-Action 'talkToSettlementHero' @{ HeroId = [string]$giver[0].heroId } 'Reopen the original Quest giver with Native QuickConversation after the Journal reached the requested quantity.' }
        }
        if ($activeQuest -and $memory.verification -eq 'buyTools' -and $memory.marketStatus -eq 'pending' -and [string]$state.context.menuId -eq 'town') {
            $tradeOption = @($state.availableMenuOptions | Where-Object { $_.available -and $_.enabled -and [string]$_.id -eq 'trade' } | Select-Object -First 1)
            if ($tradeOption.Count -eq 1) { Emit-Action 'menuSelect' @{ MenuId = $menuId; OptionId = [string]$tradeOption[0].id } 'Open the current visible Native Town Trade menu for Tools purchase or inventory inspection.' }
        }
        if ($activeQuest -and $memory.verification -eq 'snapshot-before-delivery' -and [string]$state.context.menuId -eq 'town') {
            $tradeOption = @($state.availableMenuOptions | Where-Object { $_.available -and $_.enabled -and [string]$_.id -eq 'trade' } | Select-Object -First 1)
            if ($tradeOption.Count -eq 1) { Emit-Action 'menuSelect' @{ MenuId = $menuId; OptionId = [string]$tradeOption[0].id } 'Open Trade to record player-side items before delivering the collected goods.' }
        }
        if ($memory.deliverySelected -and -not $activeQuest -and $memory.verification -eq 'verify-after-delivery' -and $currentSettlement -eq [string]$memory.marketTownId) {
            $tradeOption = @($state.availableMenuOptions | Where-Object { $_.available -and $_.enabled -and [string]$_.id -eq 'trade' } | Select-Object -First 1)
            if ($tradeOption.Count -eq 1) { Emit-Action 'menuSelect' @{ MenuId = $menuId; OptionId = [string]$tradeOption[0].id } 'Open the previously observed market before taking the settlement leave option so Native Trade can verify post-delivery inventory.' }
        }
        $leaveOption = Get-SettlementLeaveOption -Options $state.availableMenuOptions
        if (@($leaveOption).Count -eq 1) { Emit-Action 'menuSelect' @{ MenuId = $menuId; OptionId = [string]$leaveOption[0].id } 'Leave this Settlement through the currently observed Native menu option.' }
    }

    if ($memory.deliverySelected -and -not $activeQuest) {
        $memory.postDeliveryGold = [int]$state.economy.gold
        $memory.verification = 'verify-after-delivery'
        if ($currentSettlement -ne [string]$memory.marketTownId) {
            if ($previous -and $previous.action -eq 'mapSettlementTargets' -and $previous.data) {
                $marketTarget = @($previous.data.mapSettlementTargets | Where-Object { [string]$_.id -eq [string]$memory.marketTownId -and -not $_.hostile } | Select-Object -First 1)
                if ($marketTarget.Count -eq 1) { $memory.currentTargetId = [string]$marketTarget[0].id; Emit-Action 'move' @{ SettlementId = [string]$marketTarget[0].id } 'Return to the previously observed market Town for player-visible inventory verification.' }
            }
            Emit-Action 'mapSettlementTargets' @{} 'Refresh current visible map settlements to return to the earlier Trade market.'
        }
        if ($menuId -and $currentSettlement -eq [string]$memory.marketTownId) {
            $tradeOption = @($state.availableMenuOptions | Where-Object { $_.available -and $_.enabled -and [string]$_.id -eq 'trade' } | Select-Object -First 1)
            if ($tradeOption.Count -eq 1) { Emit-Action 'menuSelect' @{ MenuId = $menuId; OptionId = [string]$tradeOption[0].id } 'Open the previously observed market to verify player-side Tools consumption and reward.' }
        }
    }

    if ($activeQuest -and $memory.currentProgress -ge $memory.targetCount -and $memory.targetCount -gt 0 -and $memory.verification -eq 'return-to-giver') {
        if ($currentSettlement -ne [string]$memory.homeVillageId) {
            if ($previous -and $previous.action -eq 'mapSettlementTargets' -and $previous.data) {
                $homeSettlement = @($previous.data.mapSettlementTargets | Where-Object { [string]$_.id -eq [string]$memory.homeVillageId -and -not $_.hostile } | Select-Object -First 1)
                if ($homeSettlement.Count -eq 1) { $memory.currentTargetId = [string]$homeSettlement[0].id; Emit-Action 'move' @{ SettlementId = [string]$homeSettlement[0].id } 'Return to the original observed Quest-giver Village once the Native Journal says all Tools are collected.' }
            }
            Emit-Action 'mapSettlementTargets' @{} 'Refresh currently visible Settlement markers before returning to the Quest giver.'
        }
    }

    if ($activeQuest -and ($memory.targetCount -le 0 -or $null -eq $memory.currentProgress)) {
        Emit-Action 'questDetails' @{ QuestId = [string]$memory.questId } 'Read the visible Native Quest Journal task row before deciding which goods are still needed.'
    }
    if ($activeQuest -and $memory.currentProgress -lt $memory.targetCount) {
        if ($previous -and $previous.action -eq 'mapSettlementTargets' -and $previous.data) {
            $marketTarget = @($previous.data.mapSettlementTargets | Where-Object { $_.type -eq 'town' -and -not $_.hostile -and -not $_.underSiege -and $_.id -notin @($memory.visitedMarkets) } | Sort-Object distance | Select-Object -First 1)
            if ($marketTarget.Count -eq 1) {
                $memory.marketTownId = [string]$marketTarget[0].id
                $memory.currentTargetId = $memory.marketTownId
                $memory.visitedMarkets += $memory.marketTownId
                $memory.marketStatus = 'pending'
                $memory.verification = 'buyTools'
                Emit-Action 'move' @{ SettlementId = $memory.marketTownId } 'Travel to the nearest currently visible safe Town and inspect its Native market for the Journal-requested Tools.'
            }
        }
        Emit-Action 'mapSettlementTargets' @{} 'Read currently visible Settlement markers to find a safe market for the displayed Quest task.'
    }

    if ($activeQuest -and $memory.currentProgress -ge $memory.targetCount -and $memory.targetCount -gt 0 -and $memory.verification -eq 'snapshot-before-delivery' -and $currentSettlement -eq [string]$memory.marketTownId -and $menuId) {
        $tradeOption = @($state.availableMenuOptions | Where-Object { $_.available -and $_.enabled -and [string]$_.id -eq 'trade' } | Select-Object -First 1)
        if ($tradeOption.Count -eq 1) { Emit-Action 'menuSelect' @{ MenuId = $menuId; OptionId = [string]$tradeOption[0].id } 'Open Native Trade to record the player-side Tools/reward baseline before delivery.' }
    }

    if ($activeQuest -and $memory.verification -eq 'verify-after-delivery' -and $currentSettlement -eq [string]$memory.marketTownId -and $menuId) {
        $tradeOption = @($state.availableMenuOptions | Where-Object { $_.available -and $_.enabled -and [string]$_.id -eq 'trade' } | Select-Object -First 1)
        if ($tradeOption.Count -eq 1) { Emit-Action 'menuSelect' @{ MenuId = $menuId; OptionId = [string]$tradeOption[0].id } 'Open the same Native Town Trade view to verify post-delivery inventory.' }
    }

    if (-not $memory.questId) {
        if (-not [string]::IsNullOrWhiteSpace([string]$memory.scenarioTargetId)) {
            if ($currentSettlement -eq [string]$memory.scenarioTargetId) {
                Emit-Done 'The explicitly selected scenario Village has no current player-visible Tools Issue marker; no hidden Quest fields were checked.'
            }
            if ($previous -and $previous.action -eq 'mapSettlementTargets' -and $previous.data) {
                $scenarioVillage = @($previous.data.mapSettlementTargets | Where-Object { [string]$_.id -eq [string]$memory.scenarioTargetId -and $_.type -eq 'village' -and -not $_.hostile -and -not $_.underSiege } | Select-Object -First 1)
                if ($scenarioVillage.Count -eq 1) {
                    if ([string]$scenarioVillage[0].id -notin @($memory.visitedVillages)) { $memory.visitedVillages += [string]$scenarioVillage[0].id }
                    $memory.currentVillageId = [string]$scenarioVillage[0].id
                    $memory.currentTargetId = [string]$scenarioVillage[0].id
                    Emit-Action 'move' @{ SettlementId = [string]$scenarioVillage[0].id } 'Travel to the explicit scenario destination selected from the currently observed Native-visible map list; inspect its local overlay only after arrival.'
                }
                Emit-Done 'The explicit scenario Village is not among the currently visible, safe Native map targets.'
            }
            Emit-Action 'mapSettlementTargets' @{} 'Observe current Native-visible map targets before pursuing the explicit scenario destination.'
        }
        if ($previous -and $previous.action -eq 'mapSettlementTargets' -and $previous.data) {
            $village = @($previous.data.mapSettlementTargets | Where-Object { $_.type -eq 'village' -and -not $_.hostile -and -not $_.underSiege -and $_.id -notin @($memory.visitedVillages) } | Sort-Object distance | Select-Object -First 1)
            if ($village.Count -eq 1) {
                $memory.visitedVillages += [string]$village[0].id
                $memory.currentVillageId = [string]$village[0].id
                $memory.currentTargetId = [string]$village[0].id
                Emit-Action 'move' @{ SettlementId = [string]$village[0].id } 'Visit the nearest safe Village from the current Native-visible Settlement list; no issue, quest, or location is created.'
            }
        }
        if (@($memory.visitedVillages).Count -ge 5) { Emit-Done 'The bounded observation-driven search visited five visible Villages but saw no player-visible Tools Issue marker.' }
        Emit-Action 'mapSettlementTargets' @{} 'Request the current Native-visible map markers to select a safe Village by observed distance.'
    }
}

Emit-Done 'The current observation provides no supported action for the active quest goal; preserve the live trace rather than guessing.'
