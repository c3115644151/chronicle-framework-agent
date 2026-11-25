#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$LoadSaveName = 'ChronicleW7P-manual-20261101-eyc-complete',
    [ValidateRange(1,10)][int]$ChunkDays = 4,
    [ValidateRange(1,24)][int]$MaxChunks = 4,
    [ValidateRange(60,600)][int]$ChunkWallClockSeconds = 240,
    [ValidateRange(120,1800)][int]$TotalWallClockSeconds = 900,
    [ValidateRange(0,400)][int]$TopUpFoodUnits = 0,
    [ValidateRange(30,900)][int]$MarketArrivalTimeoutSeconds = 240,
    [int]$TimeoutSeconds = 180
)

# Idle-pressure receipt: what the world does to a party that only waits. Loads a fixture, holds the
# campaign map still, lets the original clock run in $ChunkDays-day steps, and records gold, food,
# morale and members between steps. No model requests, no save writes.
#
# -TopUpFoodUnits buys that many units of the cheapest native market food before the idle window opens,
# so the same fixture can run with and without a stocked larder; that comparison is what separates
# "starvation wounds the party" from "idling wounds the party".
$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$runDirectory = if ($env:CHRONICLE_HARNESS_TEMP) { Split-Path -Parent $env:CHRONICLE_HARNESS_TEMP } else { Join-Path (Split-Path -Parent $PSScriptRoot) 'TestResults\ManualIdlePressure' }
New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null
$resultPath = Join-Path $runDirectory 'IdlePressureResult.json'
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$commandPrefix = 'idle-pressure-' + (Get-Date -Format 'yyyyMMddHHmmssfff')

if (-not (Test-Path -LiteralPath $savePath)) { throw "Idle pressure fixture not found: $savePath" }
if (Get-Process -Name Bannerlord -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash

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
        timeControlMode = [string]$state.context.timeControlMode
        encounterActive = [bool]$state.context.encounterActive
        gold = [int]$state.economy.gold
        members = [int]$state.party.members
        healthy = [int]$state.party.healthy
        wounded = [int]$state.party.wounded
        prisoners = [int]$state.party.prisoners
        morale = [int]$state.party.morale
        food = [double]$state.party.food
        foodInventory = [int]$state.party.foodInventory
        foodChange = [double]$state.party.foodChange
        dailyWage = [int]$state.party.dailyWage
    }
}

function Invoke-FoodTopUp([int]$TargetFoodUnits, $Observation) {
    $record = [ordered]@{
        requestedUnits = $TargetFoodUnits
        travelled = $false
        townId = ''
        closedBy = 'tradeConfirm'
        leftTown = $false
        goldBefore = [int]$Observation.state.economy.gold
        foodUnitsBefore = [int]$Observation.state.party.foodInventory
        foodOffers = @()
        purchases = @()
    }
    $arrived = $Observation
    if ($Observation.state.context.menuId -eq 'town' -and -not [string]::IsNullOrWhiteSpace([string]$Observation.state.location.currentSettlementId)) {
        $townId = [string]$Observation.state.location.currentSettlementId
    } else {
        $settlement = @($Observation.state.nearbySettlements | Where-Object { $_.type -eq 'town' -and -not $_.hostile } | Sort-Object distance | Select-Object -First 1)
        if ($settlement.Count -ne 1) { throw 'No visible non-hostile town exists to buy food from.' }
        $townId = [string]$settlement[0].id
        $move = Invoke-AgentCli 'move' @('-SettlementId', $townId, '-CommandId', "$commandPrefix-topup-move")
        if ($move.status -ne 'completed' -or [string]$move.state.location.targetSettlementId -ne $townId) { throw 'Native campaign map movement did not accept the food-market town target.' }
        $record.travelled = $true
        $arrivalDeadline = [DateTime]::UtcNow.AddSeconds($MarketArrivalTimeoutSeconds)
        $arrived = $null
        while ([DateTime]::UtcNow -lt $arrivalDeadline) {
            $arrived = Get-State 'topup-arrival' 30
            if ([string]$arrived.state.location.currentSettlementId -eq $townId -and $arrived.state.context.menuId -eq 'town') { break }
            if ($arrived.state.context.encounterActive -and [string]$arrived.state.context.encounteredPartyId -ne $townId) {
                throw "Unexpected encounter '$($arrived.state.context.encounteredPartyId)' interrupted travel to the food market."
            }
            Start-Sleep -Milliseconds 500
        }
        if (-not $arrived -or [string]$arrived.state.location.currentSettlementId -ne $townId -or $arrived.state.context.menuId -ne 'town') {
            throw "Natural campaign travel did not enter the food market town within $MarketArrivalTimeoutSeconds seconds."
        }
    }
    $record.townId = $townId

    $tradeOption = @($arrived.state.availableMenuOptions | Where-Object { $_.id -eq 'trade' -and $_.available -and $_.enabled })
    if ($tradeOption.Count -ne 1) { throw "The native town menu at '$townId' did not expose an enabled trade option." }
    $market = Invoke-AgentCli 'menuSelect' @('-MenuId', 'town', '-OptionId', 'trade', '-CommandId', "$commandPrefix-topup-open-market")
    if ([string]$market.state.context.gameState -ne 'InventoryState' -or [string]$market.state.inventoryScreen.mode -ne 'Trade') {
        throw "Selecting the native trade option did not open the market; got $($market.state.context.gameState)/$($market.state.inventoryScreen.mode)."
    }

    $options = Invoke-AgentCli 'tradeOptions' @('-CommandId', "$commandPrefix-topup-options")
    $foodOffers = @($options.data.buyOffers | Where-Object { $_.isFood -and [int]$_.stock -gt 0 -and [string]$_.inventorySide -eq 'OtherInventory' } | Sort-Object { [int]$_.nativeItemCost })
    $record.foodOffers = @($foodOffers | ForEach-Object { [ordered]@{ itemId = [string]$_.itemId; unitPrice = [int]$_.nativeItemCost; stock = [int]$_.stock } })
    if ($foodOffers.Count -lt 1) { throw "The native market at '$townId' sells no food." }

    $deficit = $TargetFoodUnits - [int]$Observation.state.party.foodInventory
    foreach ($offer in $foodOffers) {
        if ($deficit -le 0) { break }
        $amount = [Math]::Min($deficit, [int]$offer.stock)
        if ($amount -le 0) { continue }
        $draft = Invoke-AgentCli 'trade' @('-Direction', 'buy', '-ItemViewModelId', [string]$offer.viewModelItemId, '-InventorySide', 'OtherInventory', '-Amount', [string]$amount, '-CommandId', "$commandPrefix-topup-buy-$($offer.itemId)")
        if ($draft.status -ne 'completed') { throw "Native market buy of '$($offer.itemId)' did not complete: status=$($draft.status)." }
        $record.purchases += [ordered]@{ itemId = [string]$offer.itemId; amount = $amount; unitPrice = [int]$offer.nativeItemCost }
        $deficit -= $amount
    }
    if (@($record.purchases).Count -lt 1) { throw 'The food top-up drafted no purchase.' }

    $confirm = Invoke-AgentCli 'tradeConfirm' @('-CommandId', "$commandPrefix-topup-confirm")
    if ($confirm.status -notin @('completed', 'accepted')) { throw "Native tradeConfirm did not accept the food purchase: status=$($confirm.status)." }
    $closedDeadline = [DateTime]::UtcNow.AddSeconds(120)
    $closed = $null
    while ([DateTime]::UtcNow -lt $closedDeadline) {
        $closed = Get-State 'topup-after-confirm' 30
        if ([string]$closed.state.context.gameState -eq 'MapState') { break }
        Start-Sleep -Milliseconds 500
    }
    if (-not $closed -or [string]$closed.state.context.gameState -ne 'MapState') {
        Invoke-AgentCli 'inventoryDone' @('-CommandId', "$commandPrefix-topup-inventory-done") | Out-Null
        $record.closedBy = 'inventoryDone'
        $closed = Get-State 'topup-after-inventory-done' 30
        if ([string]$closed.state.context.gameState -ne 'MapState') { throw "The market did not return to the campaign map; got $($closed.state.context.gameState)." }
    }
    if ([string]$closed.state.context.menuId -eq 'town') {
        $leave = Invoke-AgentCli 'menuSelect' @('-MenuId', 'town', '-OptionId', 'town_leave', '-CommandId', "$commandPrefix-topup-leave-town")
        if ($leave.status -ne 'completed') { throw "The native town_leave option did not complete: status=$($leave.status)." }
        $record.leftTown = $true
        $leaveDeadline = [DateTime]::UtcNow.AddSeconds(60)
        while ([DateTime]::UtcNow -lt $leaveDeadline) {
            $closed = Get-State 'topup-after-leave' 30
            if ([string]::IsNullOrWhiteSpace([string]$closed.state.context.menuId) -and [string]$closed.state.context.gameState -eq 'MapState') { break }
            Start-Sleep -Milliseconds 500
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$closed.state.context.menuId)) { throw "The campaign map did not regain focus after leaving the town; menuId='$($closed.state.context.menuId)'." }
    }
    $record.goldAfter = [int]$closed.state.economy.gold
    $record.foodUnitsAfter = [int]$closed.state.party.foodInventory
    $record.menuIdAfter = [string]$closed.state.context.menuId
    $record.campaignDayAfter = [double]$closed.state.campaignDay
    $record.confirmReceipt = $confirm.data
    return [pscustomobject]@{ Record = $record; Observation = $closed }
}

$samples = [System.Collections.Generic.List[object]]::new()
$chunks = [System.Collections.Generic.List[object]]::new()
$assertions = [ordered]@{}
$stopReason = ''
$failure = $null
try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $initial = Get-State 'initial'
    if ([string]$initial.state.context.gameState -ne 'MapState') { throw "Idle pressure fixture must start on the campaign map; got $($initial.state.context.gameState)." }
    if (-not [string]::IsNullOrWhiteSpace([string]$initial.state.context.menuId)) { throw "Idle pressure fixture must start with no menu open; got $($initial.state.context.menuId)." }
    $baseline = Get-Snapshot $initial 'start'
    $samples.Add($baseline)
    $topUp = $null
    if ($TopUpFoodUnits -gt 0) {
        $topUpResult = Invoke-FoodTopUp $TopUpFoodUnits $initial
        $topUp = $topUpResult.Record
        $assertions['TopUpBoughtFood'] = ([int]$topUp.foodUnitsAfter -gt [int]$topUp.foodUnitsBefore) -and ([int]$topUp.goldAfter -lt [int]$topUp.goldBefore)
        $samples.Clear()
        $baseline = Get-Snapshot $topUpResult.Observation 'start-after-top-up'
        $samples.Add($baseline)
    }

    $globalDeadline = [DateTime]::UtcNow.AddSeconds($TotalWallClockSeconds)
    for ($chunk = 1; $chunk -le $MaxChunks; $chunk++) {
        if ([DateTime]::UtcNow -gt $globalDeadline) { $stopReason = 'total-wall-clock'; break }
        $before = $samples[$samples.Count - 1]
        $advanceTimeout = [Math]::Max(60, $ChunkDays * 70)
        $chunkStop = 'target-day'
        try {
            $advance = Invoke-AgentCli 'advance' @('-Days', [string]$ChunkDays, '-CommandId', "$commandPrefix-advance-$chunk") $advanceTimeout
            if ($advance.status -ne 'completed') { throw "Native map advance did not complete for chunk ${chunk}: status=$($advance.status) error=$($advance.error)" }
        } catch {
            $chunkStop = 'advance-failed'
            $advanceError = $_.Exception.Message
        }
        if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'Game process exited during the idle pressure window.' }
        $observed = Get-State "chunk-$chunk" 60
        $after = Get-Snapshot $observed "chunk-$chunk"
        $samples.Add($after)
        if ($after.gameState -ne 'MapState') { $chunkStop = 'left-map-state' }
        $chunkRecord = [ordered]@{
            chunk = $chunk
            requestedDays = $ChunkDays
            stop = $chunkStop
            daysElapsed = [Math]::Round([double]$after.campaignDay - [double]$before.campaignDay, 4)
            goldDelta = [int]$after.gold - [int]$before.gold
            foodDelta = [Math]::Round([double]$after.food - [double]$before.food, 4)
            moraleDelta = [int]$after.morale - [int]$before.morale
            membersDelta = [int]$after.members - [int]$before.members
            woundedDelta = [int]$after.wounded - [int]$before.wounded
            foodInventory = [int]$after.foodInventory
        }
        if ($advanceError) { $chunkRecord['advanceError'] = $advanceError; $advanceError = $null }
        $chunks.Add($chunkRecord)
        if ($chunkStop -ne 'target-day') { $stopReason = $chunkStop; break }
        if ([double]$after.campaignDay -le [double]$before.campaignDay) { $stopReason = 'clock-did-not-advance'; break }
        if ([int]$after.members -lt [int]$baseline.members) { $stopReason = 'party-shrunk'; break }
        if (-not [string]::IsNullOrWhiteSpace([string]$after.menuId)) { $stopReason = 'menu-opened'; break }
    }
    if ([string]::IsNullOrWhiteSpace($stopReason)) { $stopReason = 'chunk-budget-exhausted' }
} catch {
    $failure = $_
}

$stop = $null
try { if ($start) { $stop = Invoke-AgentCli 'stop' } } catch { if (-not $failure) { $failure = $_ } }
if ($previousHarnessMode) { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode } else { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }

$last = if ($samples.Count -gt 0) { $samples[$samples.Count - 1] } else { $null }
$first = if ($samples.Count -gt 0) { $samples[0] } else { $null }
if ($first -and $last) {
    $assertions['CampaignDaysAdvanced'] = ([double]$last.campaignDay - [double]$first.campaignDay) -gt 0.5
    $assertions['GoldNeverRose'] = [int]$last.gold -le [int]$first.gold
    $assertions['TimeModeReturnedToStop'] = ([string]$last.timeControlMode -eq 'Stop') -or ([string]$last.gameState -ne 'MapState')
}
$assertions['FixtureUnchanged'] = ((Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash -eq $fixtureHashBefore)
$assertions['ProcessStopped'] = if ($start) { -not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue) } else { $true }
$assertions['ReceiptHasSample'] = ($samples.Count -ge 2)
$failedAssertions = @($assertions.Keys | Where-Object { -not $assertions[$_] })

$receipt = [ordered]@{
    TimestampUtc = [DateTime]::UtcNow.ToString('o')
    Fixture = $LoadSaveName
    FixtureSha256 = $fixtureHashBefore
    Parameters = [ordered]@{ ChunkDays = $ChunkDays; MaxChunks = $MaxChunks; ChunkWallClockSeconds = $ChunkWallClockSeconds; TopUpFoodUnits = $TopUpFoodUnits }
    StopReason = $stopReason
    Samples = $samples
    Chunks = $chunks
    Assertions = $assertions
    FailedAssertions = $failedAssertions
    Passed = ($failedAssertions.Count -eq 0 -and -not $failure)
    ModelRequests = 0
}
if ($topUp) { $receipt['TopUp'] = $topUp }
if ($failure) { $receipt['Error'] = $failure.Exception.Message }
if ($stop) { $receipt['Stop'] = [ordered]@{ status = $stop.status; processStopped = $stop.processStopped; engineConfigRestored = $stop.engineConfigRestored } }
Set-Content -LiteralPath $resultPath -Value (ConvertTo-Json -InputObject $receipt -Depth 8) -Encoding UTF8

$receipt.Chunks | ForEach-Object { "chunk {0}: {1} days, gold {2}, food {3}, morale {4}, members {5} ({6})" -f $_.chunk, $_.daysElapsed, $_.goldDelta, $_.foodDelta, $_.moraleDelta, $_.membersDelta, $_.stop }
"stop=$stopReason passed=$($receipt.Passed) failed=$($failedAssertions -join ',')"
if ($failure) { throw $failure }
if ($failedAssertions.Count -gt 0) { throw "Idle pressure assertions failed: $($failedAssertions -join ',')" }
