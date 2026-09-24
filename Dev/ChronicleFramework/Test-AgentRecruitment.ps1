[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
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
    $offerDecisionMatched = ($loopTrace[1].decision.action -eq 'recruit' -and $loopTrace[1].decision.arguments.OwnerId -eq $offer[0].ownerId -and $loopTrace[1].decision.arguments.TroopId -eq $offer[0].troopId -and [int]$loopTrace[1].decision.arguments.VolunteerSlot -eq [int]$offer[0].slot)
    $recruitmentDecisionSummary = @(
        [ordered]@{ iteration = 1; action = $loopTrace[0].decision.action; nativeOfferCount = @($loopTrace[0].actionReceipt.data.offers).Count; receiptStatus = $loopTrace[0].actionReceipt.status },
        [ordered]@{ iteration = 2; previousReceiptAction = $loopTrace[1].previousActionReceipt.action; offerDataForwarded = $offerPayloadForwarded; action = $loopTrace[1].decision.action; selectedOwnerId = $loopTrace[1].decision.arguments.OwnerId; selectedTroopId = $loopTrace[1].decision.arguments.TroopId; selectedSlot = $loopTrace[1].decision.arguments.VolunteerSlot; receiptStatus = $recruit.status; membersAfter = $afterRecruit.state.party.members; goldAfter = $afterRecruit.state.economy.gold }
    )
    $invalidRecruit = Invoke-AgentCli 'recruit' @('-OwnerId', 'chronicle_missing_owner', '-TroopId', 'chronicle_missing_troop', '-VolunteerSlot', '0', '-CommandId', "$runPrefix-invalid-recruit", '-TimeoutSeconds', 15)
    $afterInvalid = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-after-invalid", '-TimeoutSeconds', $TimeoutSeconds)

    $foodOptions = Invoke-AgentCli 'foodOptions' @('-CommandId', "$runPrefix-food-options", '-TimeoutSeconds', $TimeoutSeconds)
    $foodOffer = @($foodOptions.data.offers | Where-Object { $_.stock -gt 0 -and $_.unitPrice -le $afterInvalid.state.economy.gold } | Sort-Object unitPrice | Select-Object -First 1)
    if ($foodOffer.Count -ne 1) { throw 'Native trade inventory contains no affordable food item.' }
    $provision = Invoke-AgentCli 'provision' @('-ItemId', [string]$foodOffer[0].itemId, '-Amount', '1', '-CommandId', "$runPrefix-provision", '-TimeoutSeconds', $TimeoutSeconds)
    $afterProvision = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-after-provision", '-TimeoutSeconds', $TimeoutSeconds)
    $tradeOptions = Invoke-AgentCli 'tradeOptions' @('-CommandId', "$runPrefix-trade-options", '-TimeoutSeconds', $TimeoutSeconds)
    $sellOffer = @($tradeOptions.data.sellOffers | Where-Object { $_.itemId -eq $foodOffer[0].itemId -and $_.stock -gt 0 } | Select-Object -First 1)
    if ($sellOffer.Count -ne 1) { throw 'The acquired food item was not exposed as a player sell offer.' }
    $sell = Invoke-AgentCli 'trade' @('-Direction', 'sell', '-ItemId', [string]$sellOffer[0].itemId, '-Amount', '1', '-CommandId', "$runPrefix-sell", '-TimeoutSeconds', $TimeoutSeconds)
    $afterSell = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-after-sell", '-TimeoutSeconds', $TimeoutSeconds)
    $invalidTrade = Invoke-AgentCli 'trade' @('-Direction', 'sell', '-ItemId', 'chronicle_missing_item', '-Amount', '1', '-CommandId', "$runPrefix-invalid-trade", '-TimeoutSeconds', '15')
    $afterInvalidTrade = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-after-invalid-trade", '-TimeoutSeconds', $TimeoutSeconds)

    $menu = Invoke-AgentCli 'menu' @('-CommandId', "$runPrefix-menu", '-TimeoutSeconds', $TimeoutSeconds)
    $leave = Invoke-AgentCli 'menuSelect' @('-MenuId', [string]$menu.state.context.menuId, '-OptionId', 'town_leave', '-CommandId', "$runPrefix-leave", '-TimeoutSeconds', $TimeoutSeconds)
    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$runPrefix-stop", '-TimeoutSeconds', $TimeoutSeconds)
    $fixtureHashAfter = (Get-FileHash $savePath -Algorithm SHA256).Hash

    $expectedMembers = [int]$beforeRecruit.state.party.members + 1
    $expectedGold = [int]$beforeRecruit.state.economy.gold - [int]$offer[0].cost
    $successVerified = $recruit.data.verified -and [int]$afterRecruit.state.party.members -eq $expectedMembers -and [int]$afterRecruit.state.economy.gold -eq $expectedGold
    $failureNoMutation = $invalidRecruit.status -eq 'rejected' -and [int]$afterInvalid.state.party.members -eq [int]$afterRecruit.state.party.members -and [int]$afterInvalid.state.economy.gold -eq [int]$afterRecruit.state.economy.gold
    $provisionVerified = $provision.data.verified -and [int]$afterProvision.state.party.foodInventory -gt [int]$afterInvalid.state.party.foodInventory -and [int]$afterInvalid.state.economy.gold - [int]$afterProvision.state.economy.gold -eq [int]$provision.data.transactionAmount
    $tradeVerified = $sell.data.verified -and [int]$afterSell.state.party.foodInventory -eq [int]$afterProvision.state.party.foodInventory - 1 -and [int]$afterSell.state.economy.gold -gt [int]$afterProvision.state.economy.gold
    $invalidTradeNoMutation = $invalidTrade.status -eq 'rejected' -and [int]$afterInvalidTrade.state.party.foodInventory -eq [int]$afterSell.state.party.foodInventory -and [int]$afterInvalidTrade.state.economy.gold -eq [int]$afterSell.state.economy.gold
    $result = [ordered]@{
        ProcessId = $start.session.processId
        WindowLayout = $start.session.windowLayout
        Settlement = $target[0]
        Offer = $offer[0]
        RecruitReceipt = $recruit.data
        DecisionProviderKind = 'deterministic-test-only'
        RecruitmentDecisionSummary = $recruitmentDecisionSummary
        OfferDataForwardedToNextDecision = $offerPayloadForwarded
        OfferSelectionMatchedReceipt = $offerDecisionMatched
        Before = [ordered]@{ Members = $beforeRecruit.state.party.members; Gold = $beforeRecruit.state.economy.gold }
        After = [ordered]@{ Members = $afterRecruit.state.party.members; Gold = $afterRecruit.state.economy.gold }
        InvalidRecruit = [ordered]@{ Status = $invalidRecruit.status; Error = $invalidRecruit.error }
        InvalidAttemptNoMutation = $failureNoMutation
        FoodOffer = $foodOffer[0]
        ProvisionReceipt = $provision.data
        AfterProvision = [ordered]@{ FoodInventory = $afterProvision.state.party.foodInventory; Gold = $afterProvision.state.economy.gold }
        SellOffer = $sellOffer[0]
        SellReceipt = $sell.data
        AfterSell = [ordered]@{ FoodInventory = $afterSell.state.party.foodInventory; Gold = $afterSell.state.economy.gold }
        InvalidTrade = [ordered]@{ Status = $invalidTrade.status; Error = $invalidTrade.error }
        InvalidTradeNoMutation = $invalidTradeNoMutation
        ProvisionVerified = $provisionVerified
        TradeVerified = $tradeVerified
        LeaveReceipt = [ordered]@{ Status = $leave.status; CurrentSettlementId = $leave.state.location.currentSettlementId; MenuId = $leave.state.context.menuId }
        SuccessfulRecruitVerified = $successVerified
        FixtureUnchanged = $fixtureHashBefore -eq $fixtureHashAfter
        ProcessStopped = $stop.processStopped
    }
    $result.Passed = ($successVerified -and $offerPayloadForwarded -and $offerDecisionMatched -and $failureNoMutation -and $provisionVerified -and $tradeVerified -and $invalidTradeNoMutation -and $leave.status -eq 'completed' -and $result.FixtureUnchanged -and $result.ProcessStopped)
    $result | ConvertTo-Json -Depth 10
    if (-not $result.Passed) { exit 1 }
}
finally {
    if (Test-Path $sessionPath) {
        try { Invoke-AgentCli 'stop' @('-CommandId', "$runPrefix-cleanup", '-TimeoutSeconds', '15') | Out-Null } catch { }
    }
}
