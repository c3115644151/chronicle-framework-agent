[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180,
    [switch]$TimeControlOnly
)

$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$loop = Join-Path $PSScriptRoot 'Agent-DecisionLoop.ps1'
$provider = Join-Path $PSScriptRoot 'Test-AgentLoopProvider.ps1'
$policy = Join-Path $PSScriptRoot 'Agent-DecisionLoopPolicy.ps1'
$providerBudgetPolicy = Join-Path $PSScriptRoot 'Agent-ProviderBudget.ps1'
. $policy
. $providerBudgetPolicy
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$saveDirectory = Split-Path -Parent $savePath
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
if (-not (Test-Path $savePath)) { throw "Agent loop fixture not found: $savePath" }
$fixtureHashBefore = (Get-FileHash $savePath -Algorithm SHA256).Hash

function New-ObserveAgainPolicyFixture {
    param([string]$TimeMode = 'StoppablePlay', [bool]$Moving = $true, [bool]$EncounterActive = $false, [string]$MenuId = '', [string]$CurrentSettlementId = '')
    return [pscustomobject]@{
        status = 'completed'
        state = [pscustomobject]@{
            context = [pscustomobject]@{ gameState = 'MapState'; timeControlMode = $TimeMode; encounterActive = $EncounterActive; menuId = $MenuId; escapeMenuOpen = $false; inquiryOpen = $false }
            party = [pscustomobject]@{ isMoving = $Moving }
            location = [pscustomobject]@{ currentSettlementId = $CurrentSettlementId; targetSettlementId = 'village_test' }
        }
    }
}
$policyReceipt = [pscustomobject]@{ action = 'move'; status = 'completed'; state = [pscustomobject]@{ location = [pscustomobject]@{ targetSettlementId = 'village_test' } } }
$activeTravelPolicy = Get-ObserveAgainPolicy -Observation (New-ObserveAgainPolicyFixture) -PreviousActionReceipt $policyReceipt
$pausedTravelPolicy = Get-ObserveAgainPolicy -Observation (New-ObserveAgainPolicyFixture -TimeMode 'Stop') -PreviousActionReceipt $policyReceipt
$encounterTravelPolicy = Get-ObserveAgainPolicy -Observation (New-ObserveAgainPolicyFixture -TimeMode 'Stop' -Moving $true -EncounterActive $true -MenuId 'encounter_meeting') -PreviousActionReceipt $policyReceipt
$arrivedTravelPolicy = Get-ObserveAgainPolicy -Observation (New-ObserveAgainPolicyFixture -TimeMode 'Stop' -Moving $false -MenuId 'town' -CurrentSettlementId 'village_test') -PreviousActionReceipt $policyReceipt
$invalidTravelPolicy = Get-ObserveAgainPolicy -Observation (New-ObserveAgainPolicyFixture) -PreviousActionReceipt ([pscustomobject]@{ action = 'recruit'; status = 'completed'; state = [pscustomobject]@{ location = [pscustomobject]@{ targetSettlementId = 'village_test' } } })
$activeTravelControls = @(Get-EffectiveControlCatalog -Observation (New-ObserveAgainPolicyFixture) -PreviousActionReceipt $policyReceipt)
$encounterTravelControls = @(Get-EffectiveControlCatalog -Observation (New-ObserveAgainPolicyFixture -TimeMode 'Stop' -Moving $true -EncounterActive $true -MenuId 'encounter_meeting') -PreviousActionReceipt $policyReceipt)
$stoppedTravelControls = @(Get-EffectiveControlCatalog -Observation (New-ObserveAgainPolicyFixture -TimeMode 'Stop') -PreviousActionReceipt $policyReceipt)
$initialStateControls = @(Get-EffectiveControlCatalog -Observation (New-ObserveAgainPolicyFixture) -PreviousActionReceipt $null)
$observeAgainControlCatalogVerified = ($activeTravelControls.Count -eq 1 -and $activeTravelControls[0].control -ceq 'observeAgain' -and $encounterTravelControls.Count -eq 0 -and $stoppedTravelControls.Count -eq 0 -and $initialStateControls.Count -eq 0)
if (-not $observeAgainControlCatalogVerified) { throw 'The scheduler wait control must only be offered during confirmed, naturally advancing Native travel, not at encounters or stopped time.' }
$nativeTownWaitObservation = [pscustomobject]@{
    status = 'completed'
    state = [pscustomobject]@{
        context = [pscustomobject]@{ gameState = 'MapState'; timeControlMode = 'UnstoppableFastForward'; encounterActive = $false; menuId = 'town_wait_menus'; escapeMenuOpen = $false; inquiryOpen = $false; isWaiting = $true }
        party = [pscustomobject]@{ isMoving = $false }
        location = [pscustomobject]@{ currentSettlementId = 'town_test'; targetSettlementId = 'town_test' }
    }
}
$nativeRestAcceptedReceipt = [pscustomobject]@{ action = 'rest'; status = 'accepted'; state = $nativeTownWaitObservation.state }
$nativeRestWaitPolicy = Get-ObserveAgainPolicy -Observation $nativeTownWaitObservation -PreviousActionReceipt $nativeRestAcceptedReceipt
$nativeRestWaitControls = @(Get-EffectiveControlCatalog -Observation $nativeTownWaitObservation -PreviousActionReceipt $nativeRestAcceptedReceipt)
$unownedNativeWaitPolicy = Get-ObserveAgainPolicy -Observation $nativeTownWaitObservation -PreviousActionReceipt ([pscustomobject]@{ action = 'menuSelect'; status = 'completed' })
$nativeWaitEntryReceipt = [pscustomobject]@{ action = 'menuSelect'; status = 'completed' }
$nativeWaitBeforeRestGate = Get-NativeRestActionGate -State $nativeTownWaitObservation.state -PreviousActionReceipt $nativeWaitEntryReceipt
$nativeWaitAfterAcceptedRestGate = Get-NativeRestActionGate -State $nativeTownWaitObservation.state -PreviousActionReceipt $nativeRestAcceptedReceipt
$nativeWaitAfterCompletedRestGate = Get-NativeRestActionGate -State $nativeTownWaitObservation.state -PreviousActionReceipt ([pscustomobject]@{ action = 'rest'; status = 'completed' })
$observeAgainSupportsNativeTownWait = ($nativeRestWaitPolicy.Allowed -and $nativeRestWaitControls.Count -eq 1 -and $nativeRestWaitControls[0].control -ceq 'observeAgain' -and -not $unownedNativeWaitPolicy.Allowed -and $unownedNativeWaitPolicy.Recoverable)
$nativeRestMayBeRequestedOnlyOnce = ($nativeWaitBeforeRestGate.HideActions.Count -eq 0 -and 'rest' -in $nativeWaitAfterAcceptedRestGate.HideActions -and 'rest' -in $nativeWaitAfterCompletedRestGate.HideActions)
if (-not $observeAgainSupportsNativeTownWait -or -not $nativeRestMayBeRequestedOnlyOnce) { throw 'observeAgain may monitor an accepted Native Town Wait while its native clock advances, but must not create/advance the wait or permit a duplicate rest request.' }
$barterOptionsFixture = [pscustomobject]@{ sessionId = 'safe-passage-test-session'; context = 'contextual:safe_passage_barterable'; isOfferDisabled = $false }
$barterReadReceiptFixture = [pscustomobject]@{ action = 'barterOptions'; status = 'completed'; data = $barterOptionsFixture }
$barterAutoBalanceReceiptFixture = [pscustomobject]@{ action = 'barterAutoBalance'; status = 'completed'; data = [pscustomobject]@{ updatedOptions = $barterOptionsFixture } }
$barterNoSessionGate = Get-BarterActionGate -BarterOptions $null -PreviousActionReceipt $null -BalancedBarterSessionId $null
$barterNeedsBalanceGate = Get-BarterActionGate -BarterOptions $barterOptionsFixture -PreviousActionReceipt $barterReadReceiptFixture -BalancedBarterSessionId $null
$barterBalancedGate = Get-BarterActionGate -BarterOptions $barterOptionsFixture -PreviousActionReceipt $barterAutoBalanceReceiptFixture -BalancedBarterSessionId $barterOptionsFixture.sessionId
$barterActionPhaseGateVerified = (
    -not $barterNoSessionGate.SessionAvailable -and
    'barterAutoBalance' -in $barterNoSessionGate.HideActions -and 'barterOffer' -in $barterNoSessionGate.HideActions -and
    $barterNeedsBalanceGate.SessionAvailable -and 'barterOptions' -in $barterNeedsBalanceGate.HideActions -and 'barterOffer' -in $barterNeedsBalanceGate.HideActions -and 'barterAutoBalance' -notin $barterNeedsBalanceGate.HideActions -and
    $barterBalancedGate.SessionAvailable -and 'barterOptions' -in $barterBalancedGate.HideActions -and 'barterAutoBalance' -in $barterBalancedGate.HideActions -and 'barterOffer' -notin $barterBalancedGate.HideActions
)
if (-not $barterActionPhaseGateVerified) { throw 'A current barter session must expose one useful phase at a time: inspect, auto-balance, then submit without repeating reads or balancing.' }
$townMenuState = [pscustomobject]@{
    context = [pscustomobject]@{ gameState = 'MapState'; menuId = 'town' }
    availableMenuOptions = @(
        [pscustomobject]@{ id = 'trade'; available = $true; enabled = $true }
        [pscustomobject]@{ id = 'town_wait'; available = $true; enabled = $true }
    )
}
$townMenuObservation = [pscustomobject]@{ state = $townMenuState }
$currentTownWaitSelection = Get-CurrentMenuSelectionContext -Observation $townMenuObservation -OptionId 'town_wait'
$staleTownMenuSelection = Get-CurrentMenuSelectionContext -Observation $townMenuObservation -OptionId 'town_keep'
$tradeNoSessionGate = Get-TradeActionGate -State $townMenuState -PreviousActionReceipt $null
$tradeInventoryState = [pscustomobject]@{ context = [pscustomobject]@{ gameState = 'InventoryState' }; inventoryScreen = [pscustomobject]@{ mode = 'Trade' } }
$tradeInventoryGate = Get-TradeActionGate -State $tradeInventoryState -PreviousActionReceipt $null
$foodOptionsReceiptFixture = [pscustomobject]@{ action = 'foodOptions'; status = 'completed'; data = [pscustomobject]@{ offers = @([pscustomobject]@{ viewModelItemId = 'olives' }) } }
$foodQuotedTradeGate = Get-TradeActionGate -State $tradeInventoryState -PreviousActionReceipt $foodOptionsReceiptFixture
$provisionReceiptFixture = [pscustomobject]@{ action = 'provision'; status = 'completed'; data = [pscustomobject]@{ nativeTransactionAmount = 9 } }
$pendingNativeTradeGate = Get-TradeActionGate -State $tradeInventoryState -PreviousActionReceipt $provisionReceiptFixture
$tradeInventoryObserveAgain = Get-ObserveAgainPolicy -Observation ([pscustomobject]@{ state = [pscustomobject]@{ context = [pscustomobject]@{ gameState = 'InventoryState'; menuId = 'town'; timeControlMode = 'Stop'; encounterActive = $true; escapeMenuOpen = $false; inquiryOpen = $false; isWaiting = $true }; party = [pscustomobject]@{ isMoving = $false }; location = [pscustomobject]@{ currentSettlementId = 'town_V1'; targetSettlementId = 'town_V1' } } }) -PreviousActionReceipt $provisionReceiptFixture
$tradeInventoryObserveAgainRejectedSafely = (-not $tradeInventoryObserveAgain.Allowed -and $tradeInventoryObserveAgain.Recoverable)
$nativeMenuAndTradeCatalogVerified = (
    $currentTownWaitSelection.Allowed -and $currentTownWaitSelection.MenuId -ceq 'town' -and
    -not $staleTownMenuSelection.Allowed -and
    'foodOptions' -in $tradeNoSessionGate.HideActions -and
    'foodOptions' -notin $tradeInventoryGate.HideActions -and 'provision' -in $tradeInventoryGate.HideActions -and
    'provision' -notin $foodQuotedTradeGate.HideActions -and 'foodOptions' -in $foodQuotedTradeGate.HideActions -and 'tradeConfirm' -in $foodQuotedTradeGate.HideActions -and
    'tradeConfirm' -notin $pendingNativeTradeGate.HideActions -and 'foodOptions' -in $pendingNativeTradeGate.HideActions -and
    $tradeInventoryObserveAgainRejectedSafely
)
$supplyProfileState = [pscustomobject]@{
    schemaVersion = 23
    identity = [pscustomobject]@{ heroId = 'main_hero' }
    party = [pscustomobject]@{ members = 6; sizeLimit = 20; food = 0.95; foodInventory = 0; foodChange = -0.3; dailyWage = 10; morale = 49; isMoving = $false }
    economy = [pscustomobject]@{ gold = 900; influence = 0; renown = 20 }
    location = [pscustomobject]@{ currentSettlementId = 'town_V1'; targetSettlementId = 'town_V1' }
    context = [pscustomobject]@{ gameState = 'MapState'; timeControlMode = 'Stop'; menuId = 'town'; isWaiting = $false; encounterActive = $true }
    inventoryScreen = $null
    availableMenuOptions = @(
        [pscustomobject]@{ id = 'trade'; text = 'Trade'; available = $true; enabled = $true; isLeave = $false }
        [pscustomobject]@{ id = 'town_wait'; text = 'Wait'; available = $true; enabled = $true; isLeave = $false }
        [pscustomobject]@{ id = 'town_keep'; text = 'Keep'; available = $true; enabled = $true; isLeave = $false }
    )
    nearbyParties = @([pscustomobject]@{ id = 'unrelated-party' })
    settlementOverlayCharacters = @([pscustomobject]@{ heroId = 'unrelated-hero' })
}
$supplyFullObservation = [pscustomobject]@{ protocolVersion = 1; commandId = 'supply-profile'; action = 'state'; status = 'completed'; campaignDay = 91077.4; dailyTickCount = 2; timeControlMode = 'Stop'; state = $supplyProfileState }
$supplyModelObservation = Convert-SupplyObservationForDecision $supplyFullObservation
$supplyPreviousReceipt = [pscustomobject]@{ protocolVersion = 1; commandId = 'supply-food-options'; action = 'foodOptions'; status = 'completed'; campaignDay = 91077.4; timeControlMode = 'Stop'; data = [pscustomobject]@{ offers = @([pscustomobject]@{ itemId = 'olives'; inventoryLogicUnitPrice = 9 }) }; state = $supplyFullObservation.state }
$supplyModelReceipt = Convert-SupplyReceiptForDecision -Receipt $supplyPreviousReceipt -Observation $supplyFullObservation
$supplyObservationProfileVerified = (
    $supplyModelObservation.modelView -ceq 'campaign-multiday-supply' -and
    -not ($supplyModelObservation.state.PSObject.Properties.Name -contains 'identity') -and
    -not ($supplyModelObservation.state.PSObject.Properties.Name -contains 'nearbyParties') -and
    -not ($supplyModelObservation.state.PSObject.Properties.Name -contains 'settlementOverlayCharacters') -and
    (@($supplyModelObservation.state.availableMenuOptions.id) -join ',') -ceq 'trade,town_wait' -and
    [int]$supplyModelObservation.state.party.members -eq 6 -and [double]$supplyModelObservation.state.party.foodChange -eq -0.3 -and
    $null -eq $supplyModelReceipt.state -and @($supplyModelReceipt.data.offers).Count -eq 1 -and
    [string]$supplyModelReceipt.stateSummary.menuId -ceq 'town' -and [int]$supplyModelReceipt.stateSummary.gold -eq 900
)
if (-not $supplyObservationProfileVerified) { throw 'The multi-day supply model view must preserve task-relevant Native resources/options and the current receipt while excluding unrelated world data.' }
if (-not $nativeMenuAndTradeCatalogVerified) { throw 'Menu selection must bind to a current enabled OptionId, and Trade actions must appear only in the active native InventoryState at the correct quote/commit phase.' }
$observeAgainPolicyVerified = ($activeTravelPolicy.Allowed -and -not $pausedTravelPolicy.Allowed -and $pausedTravelPolicy.Recoverable -and -not $encounterTravelPolicy.Allowed -and $encounterTravelPolicy.Recoverable -and -not $arrivedTravelPolicy.Allowed -and $arrivedTravelPolicy.Recoverable -and -not $invalidTravelPolicy.Allowed -and $invalidTravelPolicy.Recoverable)
if (-not $observeAgainPolicyVerified) { throw 'observeAgain policy must permit naturally advancing travel only, and return safe recovery feedback when time is stopped, a menu/encounter is active, the party arrived, or no matching Native move/wait receipt exists.' }
$unobstructedMapFixture = (New-ObserveAgainPolicyFixture).state
$encounterMapFixture = (New-ObserveAgainPolicyFixture -TimeMode 'Stop' -Moving $true -EncounterActive $true -MenuId 'encounter_meeting').state
$settlementMenuFixture = (New-ObserveAgainPolicyFixture -TimeMode 'Stop' -Moving $false -MenuId 'town' -CurrentSettlementId 'town_test').state
$missionFixture = (New-ObserveAgainPolicyFixture -TimeMode 'Stop' -Moving $false).state
$missionFixture.context.gameState = 'MissionState'
$freeCampaignMapAllowsMovement = Test-UnobstructedCampaignMap $unobstructedMapFixture
$encounterBlocksMovement = -not (Test-UnobstructedCampaignMap $encounterMapFixture)
$settlementMenuBlocksMovement = -not (Test-UnobstructedCampaignMap $settlementMenuFixture)
$missionBlocksMovement = -not (Test-UnobstructedCampaignMap $missionFixture)
$unobstructedCampaignMapPolicyVerified = ($freeCampaignMapAllowsMovement -and $encounterBlocksMovement -and $settlementMenuBlocksMovement -and $missionBlocksMovement)
if (-not $unobstructedCampaignMapPolicyVerified) { throw 'Map movement actions must only be exposed on an unobstructed Campaign Map without an encounter, menu, Escape menu, or inquiry.' }

$supplyCompletionContract = [ordered]@{
    schemaVersion = 1
    contractId = 'sargot-three-day-food-v1'
    conditions = @(
        [ordered]@{ id = 'party-size'; path = 'state.party.members'; operator = 'eq'; expected = 6 }
        [ordered]@{ id = 'daily-ticks'; path = 'dailyTickCount'; operator = 'gte'; expected = 5 }
        [ordered]@{ id = 'gold-minimum'; path = 'state.economy.gold'; operator = 'gte'; expected = 861 }
        [ordered]@{ id = 'food-minimum'; path = 'state.party.food'; operator = 'gte'; expected = 1.0 }
        [ordered]@{ id = 'town-location'; path = 'state.location.currentSettlementId'; operator = 'eq'; expected = 'town_V1' }
        [ordered]@{ id = 'town-menu'; path = 'state.context.menuId'; operator = 'eq'; expected = 'town' }
        [ordered]@{ id = 'campaign-map'; path = 'state.context.gameState'; operator = 'eq'; expected = 'MapState' }
        [ordered]@{ id = 'not-waiting'; path = 'state.context.isWaiting'; operator = 'eq'; expected = $false }
    )
}
$null = Test-AgentGoalCompletion -Contract $supplyCompletionContract -Observation $supplyFullObservation -ValidateOnly
$unmetSupplyVerification = Test-AgentGoalCompletion -Contract $supplyCompletionContract -Observation $supplyFullObservation
$satisfiedSupplyObservation = $supplyFullObservation | ConvertTo-Json -Depth 12 | ConvertFrom-Json
$satisfiedSupplyObservation.dailyTickCount = 5
$satisfiedSupplyObservation.state.party.food = 1.05
$satisfiedSupplyVerification = Test-AgentGoalCompletion -Contract $supplyCompletionContract -Observation $satisfiedSupplyObservation
$unknownSupplyObservation = $supplyFullObservation | ConvertTo-Json -Depth 12 | ConvertFrom-Json
$unknownSupplyObservation.PSObject.Properties.Remove('dailyTickCount')
$unknownSupplyVerification = Test-AgentGoalCompletion -Contract $supplyCompletionContract -Observation $unknownSupplyObservation
$goalVerifierBoundedAndFailClosed = (
    $unmetSupplyVerification.Status -eq 'unmet' -and @($unmetSupplyVerification.MissingConditions.id) -contains 'daily-ticks' -and @($unmetSupplyVerification.MissingConditions.id) -contains 'food-minimum' -and
    $satisfiedSupplyVerification.Status -eq 'satisfied' -and [bool]$satisfiedSupplyVerification.Satisfied -and
    $unknownSupplyVerification.Status -eq 'unknown' -and @($unknownSupplyVerification.UnknownConditions.id) -contains 'daily-ticks'
)
if (-not $goalVerifierBoundedAndFailClosed) { throw 'The finite Native completion contract must detect unmet and unknown conditions and only pass when every predicate is satisfied.' }
$deepSeekProviderBudget = New-AgentProviderBudget -ModelId 'deepseek-flash' -BaseUrl 'https://api.deepseek.com/v1'
$deepSeekBudgetValidated = Test-AgentProviderBudget -Budget $deepSeekProviderBudget
$deepSeekMaxRequestCostCny = Get-AgentProviderRequestCostUpperBound -Budget $deepSeekProviderBudget
$threeRunCostUpperBoundCny = [Math]::Round($deepSeekMaxRequestCostCny * [int]$deepSeekProviderBudget.maxProviderCalls * 3, 6)
$localProviderBudget = New-AgentProviderBudget -ModelId 'qwen3.5:4b-q4_K_M' -BaseUrl 'http://127.0.0.1:11434/v1'
$unknownRemotePricingRejected = $false
try { $null = New-AgentProviderBudget -ModelId 'unknown-paid-model' -BaseUrl 'https://provider.example/v1' } catch { $unknownRemotePricingRejected = $_.Exception.Message -match 'No verified price profile' }
$providerBudgetPricingVerified = ($deepSeekBudgetValidated.Valid -and $deepSeekProviderBudget.mode -ceq 'priced-provider' -and $localProviderBudget.mode -ceq 'token-only-local' -and $threeRunCostUpperBoundCny -le 2.0 -and $threeRunCostUpperBoundCny -gt 0 -and $unknownRemotePricingRejected)
if (-not $providerBudgetPricingVerified) { throw 'Provider budget pricing must use a conservative known DeepSeek profile, never claim local or unknown remote service prices, and keep three maximum W5 runs below CNY 2.' }
$underfundedProviderBudget = $deepSeekProviderBudget | ConvertTo-Json -Depth 8 | ConvertFrom-Json
$underfundedProviderBudget.maxEstimatedCost = 0.001
$underfundedProviderBudgetBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($underfundedProviderBudget | ConvertTo-Json -Depth 8 -Compress)))

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @()) {
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli $Action @Arguments -TimeoutSeconds $TimeoutSeconds -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

try {
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $unicodeBaseline = Invoke-AgentCli 'state'
    $expectedHeroName = [string]$unicodeBaseline.state.identity.heroName
    if ([string]::IsNullOrWhiteSpace($expectedHeroName)) { throw 'Unicode Agent transport regression requires the live Native MainHero name.' }
    $priorProviderMode = $env:CHRONICLE_TEST_PROVIDER_MODE
    $priorExpectedHeroName = $env:CHRONICLE_TEST_EXPECTED_HERO_NAME
    $env:CHRONICLE_TEST_PROVIDER_MODE = 'unicodeRoundTrip'
    $env:CHRONICLE_TEST_EXPECTED_HERO_NAME = $expectedHeroName
    try {
        $unicodeOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -MaxDecisions 1 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('loop-unicode-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
        $unicodeExitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $priorProviderMode) { Remove-Item Env:CHRONICLE_TEST_PROVIDER_MODE -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_TEST_PROVIDER_MODE = $priorProviderMode }
        if ($null -eq $priorExpectedHeroName) { Remove-Item Env:CHRONICLE_TEST_EXPECTED_HERO_NAME -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_TEST_EXPECTED_HERO_NAME = $priorExpectedHeroName }
    }
    if ($unicodeExitCode -ne 0) { throw "Agent loop corrupted the live Unicode hero name across its process boundary: $unicodeOutput" }
    $unicodeTrace = $unicodeOutput | ConvertFrom-Json
    $unicodeRoundTripVerified = (@($unicodeTrace.trace).Count -eq 1 -and $unicodeTrace.trace[0].decision.action -eq 'state' -and $unicodeTrace.trace[0].actionReceipt.status -eq 'completed')
    if (-not $unicodeRoundTripVerified) { throw 'Agent loop did not complete the Unicode round-trip regression action.' }
    if ($TimeControlOnly) {
        $priorProviderMode = $env:CHRONICLE_TEST_PROVIDER_MODE
        $env:CHRONICLE_TEST_PROVIDER_MODE = 'timeModes'
        try {
            $timeModesOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -MaxDecisions 3 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('loop-time-modes-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
            $timeModesExitCode = $LASTEXITCODE
        }
        finally {
            if ($null -eq $priorProviderMode) { Remove-Item Env:CHRONICLE_TEST_PROVIDER_MODE -ErrorAction SilentlyContinue }
            else { $env:CHRONICLE_TEST_PROVIDER_MODE = $priorProviderMode }
        }
        if ($timeModesExitCode -ne 0) { throw "Agent decision loop did not route native time controls: $timeModesOutput" }
        $timeModesTrace = $timeModesOutput | ConvertFrom-Json
        $timeModeSteps = @($timeModesTrace.trace)
        $timeControlsRouted = (
            $timeModeSteps.Count -eq 3 -and
            $timeModeSteps[0].decision.action -eq 'resume' -and
            $timeModeSteps[0].actionReceipt.data.requestedMode -eq 'play' -and
            $timeModeSteps[0].actionReceipt.status -eq 'completed' -and
            $timeModeSteps[1].decision.action -eq 'fastForward' -and
            $timeModeSteps[1].actionReceipt.data.requestedMode -eq 'fastForward' -and
            $timeModeSteps[1].actionReceipt.data.rawModeAfter -in @('StoppableFastForward','UnstoppableFastForward') -and
            $timeModeSteps[1].actionReceipt.status -eq 'completed' -and
            $timeModeSteps[2].decision.action -eq 'pause' -and
            $timeModeSteps[2].actionReceipt.data.requestedMode -eq 'pause' -and
            $timeModeSteps[2].actionReceipt.status -eq 'completed' -and
            $timeModeSteps[2].actionReceipt.data.effectiveModeAfter -in @('Stop','FastForwardStop')
        )
        $playNaturallyAdvancedBeforeNextClockDecision = (
            $timeModeSteps.Count -eq 3 -and
            [double]$timeModeSteps[1].actionReceipt.data.campaignDayBefore -gt [double]$timeModeSteps[0].actionReceipt.data.campaignDayAfter -and
            -not [bool]$timeModeSteps[1].actionReceipt.data.isMainPartyWaitingBefore
        )
        $fastForwardNaturallyAdvancedAfterSelection = (
            $timeModeSteps.Count -eq 3 -and
            [double]$timeModeSteps[1].observationAfter.campaignDay -gt [double]$timeModeSteps[1].actionReceipt.data.campaignDayAfter -and
            $timeModeSteps[1].actionReceipt.data.effectiveModeAfter -in @('StoppableFastForward','UnstoppableFastForward') -and
            -not [bool]$timeModeSteps[1].actionReceipt.data.isMainPartyWaitingAfter
        )
        $pauseHeldCampaignDay = (
            $timeModeSteps.Count -eq 3 -and
            [double]$timeModeSteps[2].observationAfter.campaignDay -eq [double]$timeModeSteps[2].actionReceipt.data.campaignDayAfter
        )
        $timeModesStop = Invoke-AgentCli 'stop'
        $priorProviderMode = $env:CHRONICLE_TEST_PROVIDER_MODE
        $env:CHRONICLE_TEST_PROVIDER_MODE = 'waitingResume'
        try {
            $waitingStart = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
            $waitingResumeOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -MaxDecisions 2 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('loop-waiting-resume-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
            $waitingResumeExitCode = $LASTEXITCODE
        }
        finally {
            if ($null -eq $priorProviderMode) { Remove-Item Env:CHRONICLE_TEST_PROVIDER_MODE -ErrorAction SilentlyContinue }
            else { $env:CHRONICLE_TEST_PROVIDER_MODE = $priorProviderMode }
        }
        if ($waitingResumeExitCode -ne 0) { throw "Agent decision loop did not resume native time from Hold/waiting: $waitingResumeOutput" }
        $waitingResumeTrace = ($waitingResumeOutput | ConvertFrom-Json).trace
        $waitingResumeVerified = (
            @($waitingResumeTrace).Count -eq 2 -and
            $waitingResumeTrace[0].decision.action -eq 'hold' -and
            $waitingResumeTrace[0].actionReceipt.status -eq 'completed' -and
            $waitingResumeTrace[1].decision.action -eq 'resume' -and
            $waitingResumeTrace[1].actionReceipt.status -eq 'completed' -and
            $waitingResumeTrace[1].actionReceipt.data.effectiveModeAfter -eq 'UnstoppablePlay' -and
            [bool]$waitingResumeTrace[1].actionReceipt.data.isMainPartyWaitingBefore -and
            [double]$waitingResumeTrace[1].observationAfter.campaignDay -gt [double]$waitingResumeTrace[1].actionReceipt.data.campaignDayAfter -and
            [bool]$waitingResumeTrace[1].observationAfter.state.context.isWaiting
        )
        $waitingResumeStop = Invoke-AgentCli 'stop'
        $fixtureHashAfter = (Get-FileHash $savePath -Algorithm SHA256).Hash
        $timeControlResult = [ordered]@{
            ProviderKind = 'deterministic-test-only'
            ProcessId = $start.session.processId
            DecisionCount = $timeModeSteps.Count
            NativeTimeControlActionsRouted = $timeControlsRouted
            PlayModeNaturallyAdvancedBeforeFastForwardSelection = $playNaturallyAdvancedBeforeNextClockDecision
            FastForwardNaturallyAdvanced = $fastForwardNaturallyAdvancedAfterSelection
            PauseHeldCampaignDay = $pauseHeldCampaignDay
            WaitingHoldThenResumeAdvancedNaturally = $waitingResumeVerified
            TimeControlTrace = $timeModesTrace.trace
            WaitingResumeTrace = $waitingResumeTrace
            FixtureUnchanged = $fixtureHashBefore -eq $fixtureHashAfter
            ProcessStopped = ($timeModesStop.processStopped -and $waitingResumeStop.processStopped)
        }
        $timeControlResult.Passed = ($timeControlsRouted -and $playNaturallyAdvancedBeforeNextClockDecision -and $fastForwardNaturallyAdvancedAfterSelection -and $pauseHeldCampaignDay -and $waitingResumeVerified -and $timeControlResult.FixtureUnchanged -and $timeControlResult.ProcessStopped)
        $timeControlJson = $timeControlResult | ConvertTo-Json -Depth 12
        if ($env:CHRONICLE_HARNESS_TEMP -and (Test-Path -LiteralPath $env:CHRONICLE_HARNESS_TEMP -PathType Container)) {
            Set-Content -LiteralPath (Join-Path $env:CHRONICLE_HARNESS_TEMP 'AgentTimeControlLoopResult.json') -Value $timeControlJson -Encoding UTF8
        }
        $timeControlJson
        if (-not $timeControlResult.Passed) { exit 1 }
        return
    }

    $contextGoal = 'Harness contract check: inspect the current visible settlement list and stop after receiving its Native receipt.'
    $priorProviderMode = $env:CHRONICLE_TEST_PROVIDER_MODE
    $priorExpectedGoal = $env:CHRONICLE_TEST_EXPECTED_GOAL
    $env:CHRONICLE_TEST_PROVIDER_MODE = 'decisionContext'
    $env:CHRONICLE_TEST_EXPECTED_GOAL = $contextGoal
    try {
        $contextOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -Goal $contextGoal -AllowedActionNames 'mapSettlementTargets,move' -MaxDecisions 3 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('loop-context-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
        $contextExitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $priorProviderMode) { Remove-Item Env:CHRONICLE_TEST_PROVIDER_MODE -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_TEST_PROVIDER_MODE = $priorProviderMode }
        if ($null -eq $priorExpectedGoal) { Remove-Item Env:CHRONICLE_TEST_EXPECTED_GOAL -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_TEST_EXPECTED_GOAL = $priorExpectedGoal }
    }
    if ($contextExitCode -ne 0) { throw "Agent provider request lost its explicit goal or product action catalog: $contextOutput" }
    $contextTrace = $contextOutput | ConvertFrom-Json
    $goalAndCatalogForwarded = (@($contextTrace.trace).Count -eq 2 -and
        $contextTrace.trace[0].decision.action -eq 'mapSettlementTargets' -and
        $contextTrace.trace[0].decision.rationale -match 'Context contract accepted goal' -and $contextTrace.trace[0].decision.rationale -match 'only the two requested map actions' -and
        $contextTrace.trace[1].decision.done -and
        $contextTrace.trace[1].previousActionReceipt.action -eq 'mapSettlementTargets' -and
        $contextTrace.trace[1].decision.reason -match 'prior Native receipt')
    if (-not $goalAndCatalogForwarded) { throw "Goal/action-catalog request regression failed: $($contextTrace | ConvertTo-Json -Depth 8 -Compress)" }

    $impossibleCompletionContractJson = [ordered]@{
        schemaVersion = 1
        contractId = 'harness-impossible-tick-goal-v1'
        conditions = @([ordered]@{ id = 'daily-ticks'; path = 'dailyTickCount'; operator = 'gte'; expected = 999999 })
    } | ConvertTo-Json -Depth 8 -Compress
    $impossibleCompletionContractBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($impossibleCompletionContractJson))
    $checkpointProviderBudget = New-AgentProviderBudget -ModelId 'qwen3.5:4b-q4_K_M' -BaseUrl 'http://127.0.0.1:11434/v1' -MaxProviderCalls 4 -MaxOutputTokensPerRequest 128
    $checkpointProviderBudgetBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($checkpointProviderBudget | ConvertTo-Json -Depth 8 -Compress)))
    $priorProviderMode = $env:CHRONICLE_TEST_PROVIDER_MODE
    $env:CHRONICLE_TEST_PROVIDER_MODE = 'goalVerifierRejectedDone'
    try {
        $goalVerifierOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -Goal 'Harness verifier test: do not stop before the deliberately unreachable Native daily tick condition.' -CompletionContractBase64 $impossibleCompletionContractBase64 -ProviderBudgetBase64 $checkpointProviderBudgetBase64 -AllowedActionNames 'state' -PersistCheckpoint -MaxDecisions 3 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('loop-goal-verifier-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
        $goalVerifierExitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $priorProviderMode) { Remove-Item Env:CHRONICLE_TEST_PROVIDER_MODE -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_TEST_PROVIDER_MODE = $priorProviderMode }
    }
    if ($goalVerifierExitCode -ne 0) { throw "Native completion verifier failed its deterministic early-done recovery path: $goalVerifierOutput" }
    $goalVerifierTrace = $goalVerifierOutput | ConvertFrom-Json
    $firstDoneRejected = @($goalVerifierTrace.trace | Where-Object { $_.decision.done -and $_.actionReceipt.status -eq 'goal-verification-rejected' } | Select-Object -First 1)
    $secondDoneRejected = @($goalVerifierTrace.trace | Where-Object { $_.decision.done -and $_.actionReceipt.status -eq 'goal-verification-rejected' } | Select-Object -Skip 1 -First 1)
    $goalVerifierEarlyDoneRecoveryVerified = (
        $firstDoneRejected.Count -eq 1 -and $secondDoneRejected.Count -eq 1 -and
        -not [bool]$firstDoneRejected[0].actionAttempted -and -not [bool]$firstDoneRejected[0].actionExecuted -and [bool]$firstDoneRejected[0].actionReceipt.noNativeActionSent -and
        $firstDoneRejected[0].decisionFeedback.kind -eq $null -and
        @($goalVerifierTrace.trace | Where-Object { $_.decisionFeedback.kind -eq 'goal-not-satisfied' -and $_.decision.action -eq 'state' -and $_.actionReceipt.status -eq 'completed' }).Count -eq 1 -and
        [string]$secondDoneRejected[0].decisionFeedback.kind -eq '' -and
        $goalVerifierTrace.termination.reason -eq 'decision-budget-exhausted' -and -not [bool]$goalVerifierTrace.termination.goalVerified -and
        [int]$goalVerifierTrace.actionsExecuted -eq 1
    )
    if (-not $goalVerifierEarlyDoneRecoveryVerified) { throw "The loop accepted an unverified done proposal or failed to return exact missing-constraint feedback: $($goalVerifierTrace | ConvertTo-Json -Depth 10 -Compress)" }

    $goalCheckpointSaveName = 'ChronicleGoalVerifier-' + [Guid]::NewGuid().ToString('N')
    $goalCheckpointSavePath = Join-Path $saveDirectory ($goalCheckpointSaveName + '.sav')
    $goalCheckpointSaveRoot = [IO.Path]::GetFullPath($saveDirectory).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    try {
        $checkpointBeforeSaveReceipt = Invoke-AgentCli 'agentCheckpointGet' @('-CommandId', ('goal-checkpoint-before-save-' + [Guid]::NewGuid().ToString('N')))
        if ($checkpointBeforeSaveReceipt.status -ne 'completed' -or [string]::IsNullOrWhiteSpace([string]$checkpointBeforeSaveReceipt.data.checkpointBase64)) { throw 'Premature-done recovery did not leave a resumable Native Campaign checkpoint.' }
        $checkpointBeforeSaveJson = [Text.UTF8Encoding]::new($false, $true).GetString([Convert]::FromBase64String([string]$checkpointBeforeSaveReceipt.data.checkpointBase64))
        $checkpointBeforeSave = $checkpointBeforeSaveJson | ConvertFrom-Json
        if ([string]$checkpointBeforeSave.status -cne 'active' -or [string]$checkpointBeforeSave.completionContract.contractId -cne 'harness-impossible-tick-goal-v1' -or [string]$checkpointBeforeSave.lastGoalVerification.status -cne 'unmet') { throw 'Unverified provider stop was not kept distinct from an active checkpoint with its saved Native contract and unmet result.' }
        if ([int]$checkpointBeforeSave.providerBudgetState.reservedProviderCalls -ne [int]$goalVerifierTrace.providerBudget.reservedProviderCalls -or (Get-AgentProviderBudgetFingerprint -Budget $checkpointBeforeSave.providerBudgetProfile) -cne (Get-AgentProviderBudgetFingerprint -Budget $checkpointProviderBudget)) { throw 'Cumulative budget state/profile was not captured in the active Campaign task checkpoint.' }
        $checkpointSaveReceipt = Invoke-AgentCli 'save' @('-SaveName', $goalCheckpointSaveName, '-CommandId', ('goal-checkpoint-save-' + [Guid]::NewGuid().ToString('N')))
        if ($checkpointSaveReceipt.status -ne 'completed' -or -not (Test-Path -LiteralPath $goalCheckpointSavePath -PathType Leaf)) { throw 'Native save of the disposable goal-verification checkpoint did not complete.' }
        $checkpointStopReceipt = Invoke-AgentCli 'stop' @('-CommandId', ('goal-checkpoint-stop-' + [Guid]::NewGuid().ToString('N')))
        if (-not $checkpointStopReceipt.processStopped -or (Get-Process -Name Bannerlord* -ErrorAction SilentlyContinue)) { throw 'Native/Agent processes were not stopped before goal checkpoint reload.' }
        $checkpointReload = Invoke-AgentCli 'load' @('-SaveName', $goalCheckpointSaveName)
        $checkpointAfterLoadReceipt = Invoke-AgentCli 'agentCheckpointGet' @('-CommandId', ('goal-checkpoint-after-load-' + [Guid]::NewGuid().ToString('N')))
        if ($checkpointReload.status -ne 'completed' -or $checkpointAfterLoadReceipt.status -ne 'completed') { throw 'The saved goal-verification checkpoint could not be reloaded.' }
        $checkpointAfterLoadJson = [Text.UTF8Encoding]::new($false, $true).GetString([Convert]::FromBase64String([string]$checkpointAfterLoadReceipt.data.checkpointBase64))
        $checkpointAfterLoad = $checkpointAfterLoadJson | ConvertFrom-Json
        if ([string]$checkpointAfterLoad.completionContract.contractId -cne 'harness-impossible-tick-goal-v1' -or [string]$checkpointAfterLoad.status -cne 'active') { throw 'Native save/load did not preserve the still-incomplete goal contract.' }
        $checkpointBudgetRoundtripVerified = ([int]$checkpointAfterLoad.providerBudgetState.reservedProviderCalls -eq [int]$checkpointBeforeSave.providerBudgetState.reservedProviderCalls -and [string]$checkpointAfterLoad.providerBudgetFingerprint -ceq [string]$checkpointBeforeSave.providerBudgetFingerprint)
        if (-not $checkpointBudgetRoundtripVerified) { throw 'Native save/load reset or changed the cumulative provider budget.' }

        $priorProviderMode = $env:CHRONICLE_TEST_PROVIDER_MODE
        $env:CHRONICLE_TEST_PROVIDER_MODE = 'goalVerifierResume'
        try {
            $goalResumeOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -ProviderBudgetBase64 $checkpointProviderBudgetBase64 -ResumeCheckpoint -AllowedActionNames 'state' -MaxDecisions 1 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('loop-goal-verifier-resume-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
            $goalResumeExitCode = $LASTEXITCODE
        }
        finally {
            if ($null -eq $priorProviderMode) { Remove-Item Env:CHRONICLE_TEST_PROVIDER_MODE -ErrorAction SilentlyContinue }
            else { $env:CHRONICLE_TEST_PROVIDER_MODE = $priorProviderMode }
        }
        if ($goalResumeExitCode -ne 0) { throw "Checkpoint resume did not reverify the Native completion contract: $goalResumeOutput" }
        $goalResumeTrace = $goalResumeOutput | ConvertFrom-Json
        $resumeFeedbackVerified = (
            $goalResumeTrace.trace.Count -eq 1 -and
            $goalResumeTrace.trace[0].decisionFeedback.kind -eq 'goal-not-satisfied-after-resume' -and
            $goalResumeTrace.trace[0].actionReceipt.status -eq 'completed' -and
            -not [bool]$goalResumeTrace.termination.goalVerified -and
            $goalResumeTrace.termination.reason -eq 'decision-budget-exhausted'
        )
        if (-not $resumeFeedbackVerified) { throw "Goal checkpoint resume did not preserve the unmet result and safely continue: $($goalResumeTrace | ConvertTo-Json -Depth 8 -Compress)" }
        $priorProviderMode = $env:CHRONICLE_TEST_PROVIDER_MODE
        $env:CHRONICLE_TEST_PROVIDER_MODE = 'checkpointMustNotCall'
        try {
            $budgetExhaustedResumeOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -ProviderBudgetBase64 $checkpointProviderBudgetBase64 -ResumeCheckpoint -AllowedActionNames 'state' -MaxDecisions 1 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('loop-goal-verifier-budget-exhausted-resume-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
            $budgetExhaustedResumeExitCode = $LASTEXITCODE
        }
        finally {
            if ($null -eq $priorProviderMode) { Remove-Item Env:CHRONICLE_TEST_PROVIDER_MODE -ErrorAction SilentlyContinue }
            else { $env:CHRONICLE_TEST_PROVIDER_MODE = $priorProviderMode }
        }
        if ($budgetExhaustedResumeExitCode -ne 0) { throw "Cumulative task budget resume check failed: $budgetExhaustedResumeOutput" }
        $budgetExhaustedResumeTrace = $budgetExhaustedResumeOutput | ConvertFrom-Json
        $providerBudgetExhaustedAcrossCheckpointResume = (
            $budgetExhaustedResumeTrace.termination.reason -eq 'provider-budget-exhausted' -and
            @($budgetExhaustedResumeTrace.trace).Count -eq 1 -and
            [string]$budgetExhaustedResumeTrace.trace[0].actionReceipt.status -ceq 'provider-budget-exhausted' -and
            [bool]$budgetExhaustedResumeTrace.trace[0].actionReceipt.noProviderRequestSent -and
            [int]$budgetExhaustedResumeTrace.providerBudget.reservedProviderCalls -eq 4 -and
            -not [bool]$budgetExhaustedResumeTrace.trace[0].actionAttempted -and
            -not [bool]$budgetExhaustedResumeTrace.trace[0].actionExecuted
        )
        if (-not $providerBudgetExhaustedAcrossCheckpointResume) { throw "The cumulative budget was reset or a Provider call crossed its ceiling after checkpoint resume: $($budgetExhaustedResumeTrace | ConvertTo-Json -Depth 8 -Compress)" }
        $goalCheckpointRoundtripResumeVerified = (
            [string]$checkpointBeforeSave.completionContract.contractId -ceq [string]$checkpointAfterLoad.completionContract.contractId -and
            [string]$checkpointAfterLoad.status -ceq 'active' -and $resumeFeedbackVerified -and $checkpointBudgetRoundtripVerified -and
            [int]$goalResumeTrace.providerBudget.reservedProviderCalls -eq ([int]$checkpointBeforeSave.providerBudgetState.reservedProviderCalls + 1) -and $providerBudgetExhaustedAcrossCheckpointResume
        )
    }
    finally {
        if (Test-Path -LiteralPath $sessionPath -PathType Leaf) { try { $null = Invoke-AgentCli 'stop' @('-CommandId', ('goal-checkpoint-cleanup-stop-' + [Guid]::NewGuid().ToString('N'))) } catch { } }
        if (Test-Path -LiteralPath $goalCheckpointSavePath -PathType Leaf) {
            $resolvedGoalCheckpointSavePath = [IO.Path]::GetFullPath($goalCheckpointSavePath)
            if (-not $resolvedGoalCheckpointSavePath.StartsWith($goalCheckpointSaveRoot, [StringComparison]::OrdinalIgnoreCase) -or -not $goalCheckpointSaveName.StartsWith('ChronicleGoalVerifier-', [StringComparison]::Ordinal)) { throw 'Goal verifier cleanup target escaped the exact disposable save scope.' }
            Remove-Item -LiteralPath $resolvedGoalCheckpointSavePath -Force
        }
        if (Test-Path -LiteralPath ($goalCheckpointSavePath + '.bak') -PathType Leaf) { Remove-Item -LiteralPath ($goalCheckpointSavePath + '.bak') -Force }
        if (-not (Get-Process -Name Bannerlord* -ErrorAction SilentlyContinue)) { $null = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName) }
    }

    $priorProviderMode = $env:CHRONICLE_TEST_PROVIDER_MODE
    $env:CHRONICLE_TEST_PROVIDER_MODE = 'checkpointMustNotCall'
    try {
        $budgetOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -Goal 'Cost guard test: stop before making a model call when its maximum reserved cost exceeds the task budget.' -AllowedActionNames 'state' -ProviderBudgetBase64 $underfundedProviderBudgetBase64 -MaxDecisions 2 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('loop-budget-preflight-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
        $budgetExitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $priorProviderMode) { Remove-Item Env:CHRONICLE_TEST_PROVIDER_MODE -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_TEST_PROVIDER_MODE = $priorProviderMode }
    }
    if ($budgetExitCode -ne 0) { throw "Provider cost budget did not stop before the first model call: $budgetOutput" }
    $budgetTrace = $budgetOutput | ConvertFrom-Json
    $providerBudgetStoppedBeforeRequest = (
        $budgetTrace.termination.reason -eq 'provider-budget-exhausted' -and
        @($budgetTrace.trace).Count -eq 1 -and
        $budgetTrace.trace[0].actionReceipt.status -eq 'provider-budget-exhausted' -and
        [bool]$budgetTrace.trace[0].actionReceipt.noProviderRequestSent -and
        [int]$budgetTrace.providerBudget.reservedProviderCalls -eq 0 -and
        [double]$budgetTrace.providerBudget.reservedCostUpperBoundCny -eq 0.0
    )
    if (-not $providerBudgetStoppedBeforeRequest) { throw "Provider budget was not enforced before a model request: $($budgetTrace | ConvertTo-Json -Depth 8 -Compress)" }

    $usageBudget = New-AgentProviderBudget -ModelId 'deepseek-flash' -BaseUrl 'https://api.deepseek.com/v1' -MaxProviderCalls 1
    $usageBudgetBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($usageBudget | ConvertTo-Json -Depth 8 -Compress)))
    $priorProviderMode = $env:CHRONICLE_TEST_PROVIDER_MODE
    $env:CHRONICLE_TEST_PROVIDER_MODE = 'reportedUsageOverBudget'
    try {
        $usageBudgetOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -Goal 'Harness test: the provider receipt exceeds the input token reservation and must be suppressed before any Native action.' -AllowedActionNames 'state' -ProviderBudgetBase64 $usageBudgetBase64 -MaxDecisions 2 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('loop-budget-usage-overrun-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
        $usageBudgetExitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $priorProviderMode) { Remove-Item Env:CHRONICLE_TEST_PROVIDER_MODE -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_TEST_PROVIDER_MODE = $priorProviderMode }
    }
    if ($usageBudgetExitCode -ne 0) { throw "Reported over-budget usage did not stop safely before Native: $usageBudgetOutput" }
    $usageBudgetTrace = $usageBudgetOutput | ConvertFrom-Json
    $providerUsageOverBudgetStoppedBeforeNative = (
        $usageBudgetTrace.termination.reason -eq 'provider-reported-usage-exceeded-budget' -and
        @($usageBudgetTrace.trace).Count -eq 1 -and
        [string]$usageBudgetTrace.trace[0].actionReceipt.status -ceq 'provider-usage-over-budget' -and
        [bool]$usageBudgetTrace.trace[0].actionReceipt.noNativeActionSent -and
        -not [bool]$usageBudgetTrace.trace[0].actionAttempted -and
        -not [bool]$usageBudgetTrace.trace[0].actionExecuted -and
        [int]$usageBudgetTrace.providerBudget.usageReportedCalls -eq 1 -and
        [long]$usageBudgetTrace.providerBudget.promptTokensReported -gt [long]$usageBudgetTrace.providerBudget.maxInputTokensPerCall -and
        [double]$usageBudgetTrace.trace[0].observationBefore.campaignDay -eq [double]$usageBudgetTrace.trace[0].observationAfter.campaignDay
    )
    if (-not $providerUsageOverBudgetStoppedBeforeNative) { throw "Reported usage did not prevent Native dispatch: $($usageBudgetTrace | ConvertTo-Json -Depth 8 -Compress)" }

    $priorInvalidDecision = $env:CHRONICLE_TEST_INVALID_DECISION
    $env:CHRONICLE_TEST_INVALID_DECISION = 'recruit'
    try {
        $scopedInvalidOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -AllowedActionNames 'mapSettlementTargets,move' -MaxDecisions 1 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('loop-scoped-invalid-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
        $scopedInvalidExitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $priorInvalidDecision) { Remove-Item Env:CHRONICLE_TEST_INVALID_DECISION -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_TEST_INVALID_DECISION = $priorInvalidDecision }
    }
    $scopedActionRejected = ($scopedInvalidExitCode -ne 0 -and $scopedInvalidOutput -match 'not in the Agent CLI allowlist')
    if (-not $scopedActionRejected) { throw "Scoped action catalog did not restrict execution (exit=$scopedInvalidExitCode): $scopedInvalidOutput" }

    $priorProviderMode = $env:CHRONICLE_TEST_PROVIDER_MODE
    $env:CHRONICLE_TEST_PROVIDER_MODE = 'dynamicAvailabilityRecovery'
    try {
        $recoveryOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -Goal 'Recover from unavailable volunteer recruitment by selecting a currently available map action.' -AllowedActionNames 'mapSettlementTargets,move,recruitOptions,recruit' -MaxDecisions 2 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('loop-action-recovery-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
        $recoveryExitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $priorProviderMode) { Remove-Item Env:CHRONICLE_TEST_PROVIDER_MODE -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_TEST_PROVIDER_MODE = $priorProviderMode }
    }
    if ($recoveryExitCode -ne 0) { throw "Dynamic action availability did not recover after a safe pre-Native rejection: $recoveryOutput" }
    $recoveryTrace = $recoveryOutput | ConvertFrom-Json
    $dynamicActionRecoveryVerified = (
        @($recoveryTrace.trace).Count -eq 2 -and
        $recoveryTrace.trace[0].control.kind -eq 'decision-rejected-before-native' -and
        $recoveryTrace.trace[0].actionAttempted -eq $false -and
        $recoveryTrace.trace[0].actionReceipt.status -eq 'rejected-before-native' -and
        $recoveryTrace.trace[1].decision.action -eq 'mapSettlementTargets' -and
        $recoveryTrace.trace[1].actionReceipt.status -eq 'completed' -and
        $recoveryTrace.actionsExecuted -eq 1
    )
    if (-not $dynamicActionRecoveryVerified) { throw "Decision loop did not block the unavailable action before Native and recover using the current catalog: $($recoveryTrace | ConvertTo-Json -Depth 8 -Compress)" }

    $priorProviderMode = $env:CHRONICLE_TEST_PROVIDER_MODE
    $env:CHRONICLE_TEST_PROVIDER_MODE = 'invalidArgumentRecovery'
    try {
        $invalidArgumentRecoveryOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -Goal 'Recover from a rejected extra argument without sending a Native action, then read state.' -AllowedActionNames 'state' -MaxDecisions 2 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('loop-invalid-argument-recovery-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
        $invalidArgumentRecoveryExitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $priorProviderMode) { Remove-Item Env:CHRONICLE_TEST_PROVIDER_MODE -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_TEST_PROVIDER_MODE = $priorProviderMode }
    }
    if ($invalidArgumentRecoveryExitCode -ne 0) { throw "Decision loop did not safely recover from unsupported action arguments: $invalidArgumentRecoveryOutput" }
    $invalidArgumentRecoveryTrace = $invalidArgumentRecoveryOutput | ConvertFrom-Json
    $invalidArgumentRecoveryVerified = (
        @($invalidArgumentRecoveryTrace.trace).Count -eq 2 -and
        $invalidArgumentRecoveryTrace.trace[0].control.kind -eq 'decision-rejected-before-native' -and
        $invalidArgumentRecoveryTrace.trace[0].actionReceipt.status -eq 'rejected-before-native' -and
        $invalidArgumentRecoveryTrace.trace[0].actionAttempted -eq $false -and
        $invalidArgumentRecoveryTrace.trace[0].decisionFeedback.kind -eq $null -and
        $invalidArgumentRecoveryTrace.trace[1].decisionFeedback.kind -eq 'invalid-action-arguments' -and
        $invalidArgumentRecoveryTrace.trace[1].decisionFeedback.noNativeActionSent -eq $true -and
        $invalidArgumentRecoveryTrace.trace[1].decision.action -eq 'state' -and
        $invalidArgumentRecoveryTrace.trace[1].actionReceipt.status -eq 'completed' -and
        $invalidArgumentRecoveryTrace.actionsExecuted -eq 1
    )
    if (-not $invalidArgumentRecoveryVerified) { throw "Invalid-argument rejection did not recover with fresh state and no attempted Native action: $($invalidArgumentRecoveryTrace | ConvertTo-Json -Depth 8 -Compress)" }

    $priorProviderMode = $env:CHRONICLE_TEST_PROVIDER_MODE
    $priorDialogueErrorActionPreference = $ErrorActionPreference
    $env:CHRONICLE_TEST_PROVIDER_MODE = 'unavailableDialogueRecovery'
    try {
        $ErrorActionPreference = 'Continue'
        $dialogueRecoveryOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -Goal 'Reject a dialogue selection when no Native conversation options are currently visible, then continue with a current map observation.' -AllowedActionNames 'dialogueSelect,mapSettlementTargets,move' -MaxDecisions 2 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('loop-dialogue-recovery-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
        $dialogueRecoveryExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $priorDialogueErrorActionPreference
        if ($null -eq $priorProviderMode) { Remove-Item Env:CHRONICLE_TEST_PROVIDER_MODE -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_TEST_PROVIDER_MODE = $priorProviderMode }
    }
    if ($dialogueRecoveryExitCode -ne 0) {
        if ($env:CHRONICLE_HARNESS_TEMP -and (Test-Path -LiteralPath $env:CHRONICLE_HARNESS_TEMP -PathType Container)) {
            Set-Content -LiteralPath (Join-Path $env:CHRONICLE_HARNESS_TEMP 'UnavailableDialogueRecoveryFailure.log') -Value $dialogueRecoveryOutput -Encoding UTF8
        }
        throw "Unavailable dialogue action was not blocked before Native and recovered: $dialogueRecoveryOutput"
    }
    $dialogueRecoveryTrace = $dialogueRecoveryOutput | ConvertFrom-Json
    $dialogueRejectedStep = @($dialogueRecoveryTrace.trace | Where-Object { $_.control.kind -eq 'decision-rejected-before-native' -and $_.decision.action -eq 'dialogueSelect' } | Select-Object -First 1)
    $dialogueCatalogRecoveryVerified = (
        $dialogueRejectedStep.Count -eq 1 -and -not [bool]$dialogueRejectedStep[0].actionAttempted -and
        [bool]$dialogueRejectedStep[0].actionReceipt.noNativeActionSent -and
        [string]$dialogueRejectedStep[0].observationBefore.state.context.gameState -ceq 'MapState' -and
        $null -eq $dialogueRejectedStep[0].observationBefore.state.context.conversation -and
        $null -eq $dialogueRejectedStep[0].observationAfter.state.context.conversation -and
        [double]$dialogueRejectedStep[0].observationBefore.campaignDay -eq [double]$dialogueRejectedStep[0].observationAfter.campaignDay -and
        @($dialogueRecoveryTrace.trace | Where-Object { $_.decision.action -eq 'mapSettlementTargets' -and $_.actionExecuted }).Count -eq 1
    )
    if (-not $dialogueCatalogRecoveryVerified) { throw "Dialogue selection was not safely removed from the map action catalog: $($dialogueRecoveryTrace | ConvertTo-Json -Depth 8 -Compress)" }

    $markerRoot = if ($env:CHRONICLE_HARNESS_TEMP -and (Test-Path -LiteralPath $env:CHRONICLE_HARNESS_TEMP -PathType Container)) { $env:CHRONICLE_HARNESS_TEMP } else { [IO.Path]::GetTempPath() }
    $staleOfferMarker = Join-Path $markerRoot ('stale-offer-recovery-' + [Guid]::NewGuid().ToString('N') + '.txt')
    $priorStaleOfferMarker = $env:CHRONICLE_TEST_STALE_OFFER_MARKER
    $env:CHRONICLE_TEST_STALE_OFFER_MARKER = $staleOfferMarker
    $priorProviderMode = $env:CHRONICLE_TEST_PROVIDER_MODE
    $env:CHRONICLE_TEST_PROVIDER_MODE = 'staleOfferRecovery'
    try {
        $staleOfferOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -Goal 'Reach a safe visible settlement, recover from a stale volunteer offer without Native mutation, refresh offers, and recruit one affordable volunteer within capacity.' -AllowedActionNames 'mapSettlementTargets,move,recruitOptions,recruit' -MaxDecisions 24 -MaxElapsedSeconds 600 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('loop-stale-offer-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
        $staleOfferExitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $priorProviderMode) { Remove-Item Env:CHRONICLE_TEST_PROVIDER_MODE -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_TEST_PROVIDER_MODE = $priorProviderMode }
        if ($null -eq $priorStaleOfferMarker) { Remove-Item Env:CHRONICLE_TEST_STALE_OFFER_MARKER -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_TEST_STALE_OFFER_MARKER = $priorStaleOfferMarker }
        Remove-Item -LiteralPath $staleOfferMarker -Force -ErrorAction SilentlyContinue
    }
    if ($staleOfferExitCode -ne 0) { throw "Stale Native offer did not fail closed and recover: $staleOfferOutput" }
    $staleOfferTrace = $staleOfferOutput | ConvertFrom-Json
    $staleRejection = @($staleOfferTrace.trace | Where-Object { $_.control.kind -eq 'decision-rejected-before-native' -and $_.decision.action -eq 'recruit' } | Select-Object -First 1)
    $recoveredRecruitment = @($staleOfferTrace.trace | Where-Object { $_.decision.action -eq 'recruit' -and $_.actionExecuted -and $_.actionReceipt.status -eq 'completed' } | Select-Object -First 1)
    $staleOfferBlockedWithoutMutation = $false
    if ($staleRejection.Count -eq 1 -and $staleRejection[0].observationAfter.state) {
        $rejectedBefore = $staleRejection[0].observationBefore
        $rejectedAfter = $staleRejection[0].observationAfter
        $staleOfferBlockedWithoutMutation = (
            $staleRejection[0].actionAttempted -eq $false -and
            [bool]$staleRejection[0].actionReceipt.noNativeActionSent -and
            [string]$rejectedBefore.state.location.currentSettlementId -ceq [string]$rejectedAfter.state.location.currentSettlementId -and
            [string]$rejectedBefore.state.context.menuId -ceq [string]$rejectedAfter.state.context.menuId -and
            [int]$rejectedBefore.state.party.members -eq [int]$rejectedAfter.state.party.members -and
            [int]$rejectedBefore.state.economy.gold -eq [int]$rejectedAfter.state.economy.gold
        )
    }
    $staleOfferRecoveryVerified = (
        $staleOfferBlockedWithoutMutation -and $recoveredRecruitment.Count -eq 1 -and
        @($staleOfferTrace.trace | Where-Object { $_.decision.action -eq 'recruitOptions' -and $_.actionExecuted }).Count -eq 2 -and
        @($staleOfferTrace.trace | Where-Object { $_.decision.action -eq 'move' -and $_.actionExecuted }).Count -eq 1 -and
        $staleOfferTrace.termination.completedByProvider
    )
    if (-not $staleOfferRecoveryVerified) { throw "Stale offer was not blocked without a world change and followed by fresh Native offers/recruitment: $($staleOfferTrace | ConvertTo-Json -Depth 10 -Compress)" }

    $resetBeforeResumeTest = Invoke-AgentCli 'stop'
    if ($resetBeforeResumeTest.status -ne 'completed' -or -not $resetBeforeResumeTest.processStopped) { throw 'Could not cleanly stop the stale-offer scenario before the isolated Native movement/clock recovery regression.' }
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    if ($start.status -ne 'completed' -or -not $start.session.processId) { throw 'Could not reload the disposable Campaign fixture for the isolated Native movement/clock recovery regression.' }
    $priorProviderMode = $env:CHRONICLE_TEST_PROVIDER_MODE
    $env:CHRONICLE_TEST_PROVIDER_MODE = 'unlistedResumeRecovery'
    try {
        $resumeRecoveryOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -Goal 'Move to one currently visible safe Settlement. Native map movement advances time naturally; never issue resume/pause/fastForward. If the provider proposes an unavailable clock action, recover with a fresh observation and observeAgain.' -AllowedActionNames 'mapSettlementTargets,move' -MaxDecisions 12 -MaxElapsedSeconds 600 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('loop-unlisted-resume-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
        $resumeRecoveryExitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $priorProviderMode) { Remove-Item Env:CHRONICLE_TEST_PROVIDER_MODE -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_TEST_PROVIDER_MODE = $priorProviderMode }
    }
    if ($resumeRecoveryExitCode -ne 0) { throw "Unlisted resume proposal did not recover into Native bounded observation: $resumeRecoveryOutput" }
    $resumeRecoveryTrace = $resumeRecoveryOutput | ConvertFrom-Json
    $resumeRejection = @($resumeRecoveryTrace.trace | Where-Object { $_.control.kind -eq 'decision-rejected-before-native' -and $_.decision.requestedAction -ceq 'resume' } | Select-Object -First 1)
    $resumeRecoveryObserve = @($resumeRecoveryTrace.trace | Where-Object { $_.control.kind -eq 'bounded-observe-again' })
    $resumeFeedbackConsumed = @($resumeRecoveryTrace.trace | Where-Object { $_.decisionFeedback.kind -eq 'action-unavailable' -and $_.decisionFeedback.requestedAction -ceq 'resume' })
    $staleObserveRejection = @($resumeRecoveryTrace.trace | Where-Object { $_.control.kind -eq 'control-rejected-before-native' -and $_.control.requestedControl -ceq 'observeAgain' } | Select-Object -First 1)
    $staleObserveFeedbackConsumed = @($resumeRecoveryTrace.trace | Where-Object { $_.decisionFeedback.kind -eq 'control-unavailable' -and $_.decisionFeedback.requestedControl -ceq 'observeAgain' })
    $staleObserveAgainRejectedWithoutNativeAction = (
        $staleObserveRejection.Count -eq 1 -and -not [bool]$staleObserveRejection[0].actionAttempted -and
        [bool]$staleObserveRejection[0].actionReceipt.noNativeActionSent -and $staleObserveFeedbackConsumed.Count -ge 1
    )
    $nativeTimeActions = @($resumeRecoveryTrace.trace | Where-Object { $_.actionExecuted -and $_.actionReceipt.action -in @('resume','pause','fastForward') })
    $moveActions = @($resumeRecoveryTrace.trace | Where-Object { $_.actionExecuted -and $_.actionReceipt.action -eq 'move' })
    $moveReceiptStep = @($resumeRecoveryTrace.trace | Where-Object { $_.actionExecuted -and $_.actionReceipt.action -eq 'move' } | Select-Object -First 1)
    $finalResumeObservation = if ($resumeRecoveryTrace.trace.Count -gt 0 -and $resumeRecoveryTrace.trace[-1].observationAfter) { $resumeRecoveryTrace.trace[-1].observationAfter } else { $null }
    $arrivalAfterResumeRecovery = ($moveReceiptStep.Count -eq 1 -and $resumeRecoveryTrace.termination.completedByProvider -and $null -ne $finalResumeObservation -and [string]$finalResumeObservation.state.location.currentSettlementId -ceq [string]$moveReceiptStep[0].actionReceipt.state.location.targetSettlementId)
    $stoppedEncounterAfterResumeRecovery = ($resumeRecoveryTrace.termination.completedByProvider -and $null -ne $finalResumeObservation -and [bool]$finalResumeObservation.state.context.encounterActive -and [string]$finalResumeObservation.state.context.timeControlMode -ceq 'Stop')
    $safeTravelInterruptionResolved = ($arrivalAfterResumeRecovery -or $stoppedEncounterAfterResumeRecovery)
    $staleControlWasAppropriate = (
        $staleObserveRejection.Count -eq 1 -and
        (([string]$staleObserveRejection[0].observationBefore.state.location.currentSettlementId -ceq [string]$moveReceiptStep[0].actionReceipt.state.location.targetSettlementId) -or
            ([bool]$staleObserveRejection[0].observationBefore.state.context.encounterActive -and [string]$staleObserveRejection[0].observationBefore.state.context.timeControlMode -ceq 'Stop'))
    )
    $unlistedResumeRecoveryVerified = (
        $resumeRejection.Count -eq 1 -and $resumeRejection[0].actionAttempted -eq $false -and
        [bool]$resumeRejection[0].actionReceipt.noNativeActionSent -and $moveActions.Count -eq 1 -and
        $resumeFeedbackConsumed.Count -ge 1 -and ($resumeRecoveryObserve.Count -ge 1 -or $stoppedEncounterAfterResumeRecovery) -and
        $staleObserveAgainRejectedWithoutNativeAction -and
        $staleControlWasAppropriate -and
        $nativeTimeActions.Count -eq 0 -and
        [string]$resumeRejection[0].observationBefore.state.context.timeControlMode -ceq 'StoppablePlay' -and
        [string]$resumeRejection[0].observationAfter.state.context.timeControlMode -in @('StoppablePlay','Stop') -and
        $null -ne $finalResumeObservation -and $null -ne $moveReceiptStep -and $safeTravelInterruptionResolved -and
        [double]$finalResumeObservation.campaignDay -gt [double]$moveReceiptStep[0].actionReceipt.campaignDay
    )
    if (-not $unlistedResumeRecoveryVerified) { throw "The unsupported resume and stale post-arrival observeAgain proposals were safely rejected, surfaced as feedback, and recovered without clock-control Native actions: $($resumeRecoveryTrace | ConvertTo-Json -Depth 8 -Compress)" }

    $priorInvalidDecision = $env:CHRONICLE_TEST_INVALID_DECISION
    $env:CHRONICLE_TEST_INVALID_DECISION = '1'
    try {
        $invalidOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -MaxDecisions 1 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('loop-invalid-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
        $invalidExitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $priorInvalidDecision) { Remove-Item Env:CHRONICLE_TEST_INVALID_DECISION -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_TEST_INVALID_DECISION = $priorInvalidDecision }
    }
    $unsafeActionRejected = ($invalidExitCode -ne 0 -and $invalidOutput -match 'allowlist')
    if (-not $unsafeActionRejected) { throw "Unsafe provider action rejection check failed (exit=$invalidExitCode, message=$($invalidOutput -match 'allowlist')): $invalidOutput" }
    $priorInvalidDecision = $env:CHRONICLE_TEST_INVALID_DECISION
    $env:CHRONICLE_TEST_INVALID_DECISION = 'advance'
    try {
        $harnessClockOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -MaxDecisions 1 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('loop-clock-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
        $harnessClockExitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $priorInvalidDecision) { Remove-Item Env:CHRONICLE_TEST_INVALID_DECISION -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_TEST_INVALID_DECISION = $priorInvalidDecision }
    }
    $harnessClockRejected = ($harnessClockExitCode -ne 0 -and $harnessClockOutput -match 'Harness-only deterministic time step')
    if (-not $harnessClockRejected) { throw "Harness-only advance boundary check failed: $harnessClockOutput" }
    $priorProviderMode = $env:CHRONICLE_TEST_PROVIDER_MODE
    $env:CHRONICLE_TEST_PROVIDER_MODE = 'observationLoop'
    try {
        $loopOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -MaxDecisions 2 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('loop-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
        $loopExitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $priorProviderMode) { Remove-Item Env:CHRONICLE_TEST_PROVIDER_MODE -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_TEST_PROVIDER_MODE = $priorProviderMode }
    }
    if ($loopExitCode -ne 0) { throw "Agent decision loop failed: $loopOutput" }
    $trace = $loopOutput | ConvertFrom-Json
    $first = $trace.trace[0]
    $second = $trace.trace[1]
    $observationLoopVerified = ($trace.trace.Count -eq 2 -and $first.decision.action -eq 'state' -and $first.actionReceipt.status -eq 'completed' -and $second.decision.action -eq 'mapPartyTargets' -and $second.actionReceipt.status -eq 'completed')
    $decisionTimingCaptured = ($trace.initialObservation.startedUtc -and $trace.initialObservation.completedUtc -and
        $first.timing.providerStartedUtc -and $first.timing.providerCompletedUtc -and
        $first.timing.actionStartedUtc -and $first.timing.actionCompletedUtc -and $first.timing.actionElapsedMilliseconds -ge 0 -and
        $first.timing.observationStartedUtc -and $first.timing.observationCompletedUtc -and $first.timing.observationElapsedMilliseconds -ge 0)
    $receiptForwarded = ($second.previousActionReceipt.commandId -eq $first.actionReceipt.commandId -and $second.previousActionReceipt.action -eq $first.actionReceipt.action -and $second.previousActionReceipt.status -eq $first.actionReceipt.status)
    $priorProviderMode = $env:CHRONICLE_TEST_PROVIDER_MODE
    $env:CHRONICLE_TEST_PROVIDER_MODE = 'doneSignal'
    try {
        $doneOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -MaxDecisions 4 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('loop-done-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
        $doneExitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $priorProviderMode) { Remove-Item Env:CHRONICLE_TEST_PROVIDER_MODE -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_TEST_PROVIDER_MODE = $priorProviderMode }
    }
    if ($doneExitCode -ne 0) { throw "Agent loop did not stop on the provider's explicit goal-complete signal: $doneOutput" }
    $doneTrace = $doneOutput | ConvertFrom-Json
    $doneSignalVerified = ($doneTrace.trace.Count -eq 2 -and $doneTrace.actionsExecuted -eq 1 -and $doneTrace.termination.completedByProvider -and $doneTrace.termination.reason -eq 'provider-stop' -and -not $doneTrace.trace[1].actionExecuted -and $doneTrace.trace[1].decision.done)
    $stop = Invoke-AgentCli 'stop'
    $fixtureHashAfter = (Get-FileHash $savePath -Algorithm SHA256).Hash
    $result = [ordered]@{
        ProviderKind = 'deterministic-test-only'
        ProcessId = $start.session.processId
        DecisionCount = @($trace.trace).Count
        ObservationActionObservationVerified = $observationLoopVerified
        FirstDecision = $first.decision.action
        SecondDecision = $second.decision.action
        PreviousActionReceiptForwarded = $receiptForwarded
        DecisionTimingCaptured = $decisionTimingCaptured
        UnicodeHeroNameRoundTripVerified = $unicodeRoundTripVerified
        ObserveAgainPolicySeparatesNaturalTimeFromStoppedEncounter = $observeAgainPolicyVerified
        ObserveAgainControlIsExposedOnlyWhenSafe = $observeAgainControlCatalogVerified
        ObserveAgainCanMonitorAcceptedNativeTownWait = $observeAgainSupportsNativeTownWait
        ObserveAgainDuringUncommittedTradeIsRecoverable = $tradeInventoryObserveAgainRejectedSafely
        NativeRestRequestIsSingleUsePerWait = $nativeRestMayBeRequestedOnlyOnce
        BarterActionCatalogStagesCurrentNativeQuote = $barterActionPhaseGateVerified
        MenuAndTradeActionCatalogFollowsCurrentNativeContext = $nativeMenuAndTradeCatalogVerified
        SupplyObservationProfileCompactsAndKeepsNativeContext = $supplyObservationProfileVerified
        MapMovementCatalogRequiresUnobstructedCampaignMap = $unobstructedCampaignMapPolicyVerified
        ExplicitGoalStopHonoredWithoutIssuingAnotherAction = $doneSignalVerified
        NativeGoalVerifierRejectsPrematureDone = $goalVerifierEarlyDoneRecoveryVerified
        NativeGoalContractPersistsAndReverifiesAfterLoad = $goalCheckpointRoundtripResumeVerified
        ProviderBudgetCheckpointLedgerRoundtripVerified = $checkpointBudgetRoundtripVerified
        ProviderBudgetCallsReservedBeforeResume = [int]$checkpointBeforeSave.providerBudgetState.reservedProviderCalls
        ProviderBudgetCallsReservedAfterResume = [int]$goalResumeTrace.providerBudget.reservedProviderCalls
        ProviderBudgetExhaustedAcrossCheckpointResume = $providerBudgetExhaustedAcrossCheckpointResume
        ProviderBudgetUsesKnownRatesAndBoundsThreeDeepSeekRuns = $providerBudgetPricingVerified
        ProviderBudgetStopsBeforeUnaffordableRequest = $providerBudgetStoppedBeforeRequest
        ProviderReportedUsageOverrunStopsBeforeNativeAction = $providerUsageOverBudgetStoppedBeforeNative
        DeepSeekThreeRunWorstCaseCostCny = $threeRunCostUpperBoundCny
        GoalStopTrace = $doneTrace.trace
        GoalAndActionCatalogForwarded = $goalAndCatalogForwarded
        ScopedActionRejected = $scopedActionRejected
        DynamicActionCatalogRecoveryVerified = $dynamicActionRecoveryVerified
        InvalidActionArgumentsRecoverWithoutNativeMutation = $invalidArgumentRecoveryVerified
        UnavailableDialogueRejectedWithoutNativeAction = $dialogueCatalogRecoveryVerified
        DynamicActionRecoveryTrace = $recoveryTrace.trace
        StaleOfferRecoveryVerified = $staleOfferRecoveryVerified
        StaleOfferBlockedWithoutNativeMutation = $staleOfferBlockedWithoutMutation
        StaleOfferRecoveryTrace = $staleOfferTrace.trace
        UnlistedResumeRejectedWithoutNativeAction = $unlistedResumeRecoveryVerified
        StaleObserveAgainRejectedWithoutNativeAction = $staleObserveAgainRejectedWithoutNativeAction
        UnlistedResumeRecoveryTrace = $resumeRecoveryTrace.trace
        DecisionContextTrace = $contextTrace.trace
        UnsafeActionRejected = $unsafeActionRejected
        HarnessAdvanceRejected = $harnessClockRejected
        FixtureUnchanged = $fixtureHashBefore -eq $fixtureHashAfter
        ProcessStopped = $stop.processStopped
        Trace = $trace.trace
    }
    $result.Passed = ($result.DecisionCount -eq 2 -and $observationLoopVerified -and $receiptForwarded -and $decisionTimingCaptured -and $unicodeRoundTripVerified -and $observeAgainPolicyVerified -and $observeAgainControlCatalogVerified -and $observeAgainSupportsNativeTownWait -and $tradeInventoryObserveAgainRejectedSafely -and $nativeRestMayBeRequestedOnlyOnce -and $barterActionPhaseGateVerified -and $nativeMenuAndTradeCatalogVerified -and $supplyObservationProfileVerified -and $unobstructedCampaignMapPolicyVerified -and $doneSignalVerified -and $goalVerifierEarlyDoneRecoveryVerified -and $goalCheckpointRoundtripResumeVerified -and $providerBudgetPricingVerified -and $providerBudgetStoppedBeforeRequest -and $providerUsageOverBudgetStoppedBeforeNative -and $goalAndCatalogForwarded -and $scopedActionRejected -and $dynamicActionRecoveryVerified -and $invalidArgumentRecoveryVerified -and $dialogueCatalogRecoveryVerified -and $staleOfferRecoveryVerified -and $unlistedResumeRecoveryVerified -and $unsafeActionRejected -and $harnessClockRejected -and $result.FixtureUnchanged -and $result.ProcessStopped)
    $result | ConvertTo-Json -Depth 12
    if (-not $result.Passed) { exit 1 }
}
finally {
    if (Test-Path $sessionPath) { try { Invoke-AgentCli 'stop' | Out-Null } catch { } }
}
