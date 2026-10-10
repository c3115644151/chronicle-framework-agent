$ErrorActionPreference = 'Stop'
$requestReader = New-Object System.IO.StreamReader -ArgumentList @([Console]::OpenStandardInput(), [System.Text.Encoding]::UTF8, $true)
try { $requestJson = $requestReader.ReadToEnd() }
finally { $requestReader.Dispose() }
$jsonStart = $requestJson.IndexOf('{')
if ($jsonStart -lt 0) { throw 'Provider input does not contain a JSON object.' }
if ($jsonStart -gt 0) {
    $prefix = $requestJson.Substring(0, $jsonStart)
    if ($prefix -notmatch '^[\s\p{C}]*$') { throw 'Provider input has non-whitespace data before its JSON object.' }
    $requestJson = $requestJson.Substring($jsonStart)
}
$request = $requestJson | ConvertFrom-Json
if ($request.schemaVersion -ne 3) { throw 'Unsupported Agent loop request schema.' }
if ($null -eq $request.recentDecisionHistory -or @($request.recentDecisionHistory).Count -gt 8) { throw 'Recent decision history is missing or exceeds its bound.' }
if ($env:CHRONICLE_TEST_PROVIDER_MODE -eq 'checkpointMustNotCall') { throw 'checkpoint-provider-was-called' }
if ($env:CHRONICLE_TEST_PROVIDER_MODE -eq 'checkpointMustNotCall') { throw 'checkpoint-provider-was-called' }
if ($env:CHRONICLE_TEST_PROVIDER_MODE -eq 'reportedUsageOverBudget') {
    if (-not $request.providerBudget -or [string]$request.providerBudget.mode -cne 'priced-provider') { throw 'Usage-over-budget regression requires a priced-provider reservation in the request.' }
    $promptTokens = [int]$request.providerBudget.maxInputTokensPerRequest + 1
    [pscustomobject]@{
        action = 'state'
        arguments = @{}
        rationale = 'Return a deliberately over-budget usage receipt; the loop must suppress this decision before Native.'
        providerUsage = [ordered]@{
            status = 'reported'
            promptTokens = $promptTokens
            completionTokens = 1
            totalTokens = ($promptTokens + 1)
            promptCacheHitTokens = 0
            promptCacheMissTokens = $promptTokens
            requestAttempts = 1
            requestBodyBytes = 512
        }
    } | ConvertTo-Json -Depth 6 -Compress
    exit 0
}
if ($request.iteration -gt 1 -and -not $request.previousActionReceipt -and -not $request.decisionFeedback) { throw 'Neither the previous Native receipt nor safe pre-Native rejection feedback was forwarded to the next decision.' }
if ($env:CHRONICLE_TEST_INVALID_DECISION) {
    $invalidAction = [string]$env:CHRONICLE_TEST_INVALID_DECISION
    $arguments = if ($invalidAction -eq 'start') { @{ SaveName = 'must_not_execute' } } else { @{} }
    [pscustomobject]@{ action = $invalidAction; arguments = $arguments; rationale = 'Intentional Agent decision boundary regression test.' } | ConvertTo-Json -Compress
    exit 0
}
if ($env:CHRONICLE_TEST_PROVIDER_MODE -eq 'dynamicAvailabilityRecovery') {
    $catalogNames = @($request.allowedActions | ForEach-Object { [string]$_.action })
    if ($request.iteration -eq 1) {
        if ($catalogNames -contains 'recruit') { throw 'Recruit leaked into the current map action catalog.' }
        [pscustomobject]@{ action = 'recruit'; arguments = @{ OwnerId = 'town_V1'; TroopId = 'volunteers'; VolunteerSlot = 1; ConfirmPartySizeWarning = $false }; rationale = 'Intentional unavailable-action recovery regression.' } | ConvertTo-Json -Compress
        exit 0
    }
    if ([string]$request.decisionFeedback.kind -cne 'action-unavailable' -or -not [bool]$request.decisionFeedback.noNativeActionSent -or
        [string]$request.decisionFeedback.requestedAction -cne 'recruit' -or $request.previousActionReceipt -or $catalogNames -contains 'recruit' -or
        [int]$request.observation.state.party.members -ne 1 -or [int]$request.observation.state.economy.gold -ne 1000 -or
        @($request.recentDecisionHistory).Count -ne 1 -or [string]$request.recentDecisionHistory[0].action -cne 'recruit' -or
        [bool]$request.recentDecisionHistory[0].decisionRejected -or [string]$request.recentDecisionHistory[0].nativeOutcome.status -cne 'rejected-before-native' -or
        -not [bool]$request.recentDecisionHistory[0].nativeOutcome.noNativeActionSent) {
        throw 'Unavailable decision feedback did not include a fresh unchanged Native state and a restricted current action catalog.'
    }
    [pscustomobject]@{ action = 'mapSettlementTargets'; arguments = @{}; rationale = 'Recover from the unavailable recruitment proposal using a currently listed map action.' } | ConvertTo-Json -Compress
    exit 0
}
if ($env:CHRONICLE_TEST_PROVIDER_MODE -eq 'invalidArgumentRecovery') {
    $catalogNames = @($request.allowedActions | ForEach-Object { [string]$_.action } | Sort-Object -Unique)
    if ($request.iteration -eq 1) {
        if ($catalogNames.Count -ne 1 -or $catalogNames[0] -cne 'state') { throw 'Invalid-argument recovery regression must be scoped to the read-only state action.' }
        [pscustomobject]@{ decisionRejected = $true; requestedAction = 'state'; reason = 'invalid-action-arguments'; invalidArguments = @('candidateId'); allowedArguments = @(); availableActions = $catalogNames; noNativeActionSent = $true } | ConvertTo-Json -Compress
        exit 0
    }
    if ([string]$request.decisionFeedback.kind -cne 'invalid-action-arguments' -or
        [string]$request.decisionFeedback.requestedAction -cne 'state' -or
        @($request.decisionFeedback.invalidArguments).Count -ne 1 -or [string]$request.decisionFeedback.invalidArguments[0] -cne 'candidateId' -or
        @($request.decisionFeedback.allowedArguments).Count -ne 0 -or -not [bool]$request.decisionFeedback.noNativeActionSent -or
        $request.previousActionReceipt -or [string]$request.observation.state.identity.heroId -cne 'main_hero') {
        throw 'Invalid-argument feedback did not provide a fresh unchanged Native observation, the exact allowed parameters, and confirmation that no action was sent.'
    }
    [pscustomobject]@{ action = 'state'; arguments = @{}; rationale = 'Retry the listed zero-argument observation without the rejected candidateId.' } | ConvertTo-Json -Compress
    exit 0
}
if ($env:CHRONICLE_TEST_PROVIDER_MODE -eq 'unavailableDialogueRecovery') {
    $catalogNames = @($request.allowedActions | ForEach-Object { [string]$_.action } | Sort-Object -Unique)
    if ($catalogNames -notcontains 'mapSettlementTargets' -or $catalogNames -notcontains 'move') { throw 'Current Native map observation/movement actions must remain available on an unobstructed map.' }
    if ($request.iteration -eq 1) {
        if ($catalogNames -contains 'dialogueSelect' -or $request.observation.state.context.conversation) { throw 'Dialogue selection leaked into a state with no current Native conversation option.' }
        [pscustomobject]@{ action = 'dialogueSelect'; arguments = @{ OptionId = 'bandit_start_defender_2' }; rationale = 'Intentional unavailable-dialogue recovery regression.' } | ConvertTo-Json -Compress
        exit 0
    }
    if ([string]$request.decisionFeedback.kind -cne 'action-unavailable' -or
        [string]$request.decisionFeedback.requestedAction -cne 'dialogueSelect' -or
        -not [bool]$request.decisionFeedback.noNativeActionSent -or
        $catalogNames -contains 'dialogueSelect' -or $request.previousActionReceipt) {
        throw 'Unavailable dialogue feedback did not report a Native pre-call rejection and the restricted fresh action catalog.'
    }
    [pscustomobject]@{ action = 'mapSettlementTargets'; arguments = @{}; rationale = 'Recover from the unavailable dialogue action using a currently visible read tool.' } | ConvertTo-Json -Compress
    exit 0
}
if ($env:CHRONICLE_TEST_PROVIDER_MODE -eq 'unlistedResumeRecovery') {
    $state = $request.observation.state
    $receipt = $request.previousActionReceipt
    $catalogNames = @($request.allowedActions | ForEach-Object { [string]$_.action } | Sort-Object -Unique)
    if ($catalogNames -contains 'resume') { throw 'The narrowly scoped travel goal must not expose explicit clock control.' }
    if ([string]$request.decisionFeedback.kind -ceq 'control-unavailable') {
        $arrived = ([string]$state.location.currentSettlementId -ceq [string]$receipt.state.location.targetSettlementId -and -not [bool]$state.party.isMoving)
        $encounterStoppedTime = ([bool]$state.context.encounterActive -and [string]$state.context.timeControlMode -ceq 'Stop')
        if ([string]$request.decisionFeedback.requestedControl -cne 'observeAgain' -or -not [bool]$request.decisionFeedback.noNativeActionSent -or
            [string]$receipt.action -cne 'move' -or (-not $arrived -and -not $encounterStoppedTime) -or @($request.allowedControls).Count -ne 0) { throw 'Stale observeAgain rejection did not return a reached target or paused encounter, preserve the prior Move receipt, and hide the unavailable scheduler control.' }
        [pscustomobject]@{ done = $true; reason = if ($arrived) { 'The stale wait was rejected without an action; fresh Native state confirms arrival.' } else { 'The stale wait was rejected without an action; a Native encounter stopped Campaign time and requires a separate strategy.' } } | ConvertTo-Json -Compress
        exit 0
    }
    if ([string]$request.decisionFeedback.kind -ceq 'action-unavailable') {
        $arrivalAfterRejection = [string]$request.nativeMoveArrival.status -ceq 'arrived'
        $encounterAfterRejection = ([bool]$state.context.encounterActive -and [string]$state.context.timeControlMode -ceq 'Stop')
        if ([string]$request.decisionFeedback.requestedAction -cne 'resume' -or -not [bool]$request.decisionFeedback.noNativeActionSent -or
            [string]$receipt.action -cne 'move' -or [string]$receipt.status -cne 'completed' -or
            [string]$receipt.state.context.timeControlMode -cne 'StoppablePlay' -or
            (-not $arrivalAfterRejection -and -not $encounterAfterRejection -and ([string]$state.context.timeControlMode -cne 'StoppablePlay' -or -not [bool]$state.party.isMoving))) {
            throw 'Resume rejection did not preserve the Native move receipt and either ongoing natural movement or arrival after consuming feedback.'
        }
        if ($arrivalAfterRejection -or $encounterAfterRejection) {
            [pscustomobject]@{ observeAgain = $true; waitSeconds = 5; reason = 'Intentional stale-control regression: request one wait after arrival or a stopped encounter so the loop must reject it safely.' } | ConvertTo-Json -Compress
            exit 0
        }
        [pscustomobject]@{ observeAgain = $true; waitSeconds = 5; reason = 'The Native move continues in StoppablePlay; naturally advancing time needs no resume action.' } | ConvertTo-Json -Compress
        exit 0
    }
    if (-not $receipt) {
        [pscustomobject]@{ action = 'mapSettlementTargets'; arguments = @{}; rationale = 'Read current visible Native settlement targets.' } | ConvertTo-Json -Compress
        exit 0
    }
    if ([string]$receipt.action -ceq 'mapSettlementTargets') {
        $target = @($receipt.data.mapSettlementTargets | Where-Object { -not $_.hostile -and -not $_.underSiege -and [string]$_.type -eq 'village' -and [double]$_.distance -ge 15 } | Sort-Object { [double]$_.distance } | Select-Object -First 1)
        if ($target.Count -ne 1) { throw 'No currently visible safe settlement exists for the clock-boundary regression.' }
        [pscustomobject]@{ action = 'move'; arguments = @{ SettlementId = [string]$target[0].id }; rationale = 'Use one Native move toward the selected safe visible Settlement.' } | ConvertTo-Json -Compress
        exit 0
    }
    if ([string]$request.nativeMoveArrival.status -ceq 'arrived' -and [string]$receipt.action -ceq 'move') {
        [pscustomobject]@{ observeAgain = $true; waitSeconds = 5; reason = 'Intentional stale-control regression: ask to wait after Native arrival.' } | ConvertTo-Json -Compress
        exit 0
    }
    if ([string]$receipt.action -ceq 'move' -and [bool]$state.context.encounterActive -and [string]$state.context.timeControlMode -ceq 'Stop') {
        [pscustomobject]@{ observeAgain = $true; waitSeconds = 5; reason = 'Intentional paused-encounter regression: the party movement flag may remain true while Native Campaign time is stopped.' } | ConvertTo-Json -Compress
        exit 0
    }
    if ([string]$receipt.action -ceq 'move' -and [bool]$state.party.isMoving -and [string]$state.context.timeControlMode -ceq 'StoppablePlay') {
        [pscustomobject]@{ decisionRejected = $true; requestedAction = 'resume'; reason = 'not-in-current-action-catalog'; availableActions = $catalogNames } | ConvertTo-Json -Compress
        exit 0
    }
    if ([string]$receipt.action -ceq 'move' -and [bool]$state.party.isMoving) {
        [pscustomobject]@{ observeAgain = $true; waitSeconds = 5; reason = 'Observe the existing Native movement without changing the Campaign clock.' } | ConvertTo-Json -Compress
        exit 0
    }
    [pscustomobject]@{ done = $true; reason = 'No further safe Native travel action is supported.' } | ConvertTo-Json -Compress
    exit 0
}
if ($env:CHRONICLE_TEST_PROVIDER_MODE -eq 'staleOfferRecovery') {
    $state = $request.observation.state
    $receipt = $request.previousActionReceipt
    $offerMarker = [string]$env:CHRONICLE_TEST_STALE_OFFER_MARKER
    if (-not $receipt) {
        [pscustomobject]@{ action = 'mapSettlementTargets'; arguments = @{}; rationale = 'Start from current native map targets.' } | ConvertTo-Json -Compress
        exit 0
    }
    if ([string]$request.decisionFeedback.kind -ceq 'action-unavailable' -and [string]$request.decisionFeedback.requestedAction -ceq 'recruit') {
        [pscustomobject]@{ action = 'recruitOptions'; arguments = @{}; rationale = 'The previous offer selection was rejected before Native; refresh the current settlement offers.' } | ConvertTo-Json -Compress
        exit 0
    }
    if ([string]$receipt.action -ceq 'mapSettlementTargets') {
        $target = @($receipt.data.mapSettlementTargets | Where-Object { -not $_.hostile -and -not $_.underSiege -and [string]$_.type -in @('town','village') } | Sort-Object { [double]$_.distance } | Select-Object -First 1)
        if ($target.Count -ne 1) { throw 'Stale-offer recovery test received no safe visible Settlement target.' }
        [pscustomobject]@{ action = 'move'; arguments = @{ SettlementId = [string]$target[0].id }; rationale = 'Move to the nearest safe visible settlement.' } | ConvertTo-Json -Compress
        exit 0
    }
    if ([string]$receipt.action -in @('move','resume')) {
        if ([string]$state.location.currentSettlementId -ceq [string]$state.location.targetSettlementId -and [string]$state.context.menuId -in @('town','town_backstreet','village')) {
            [pscustomobject]@{ action = 'recruitOptions'; arguments = @{}; rationale = 'Read volunteers only from the active Native settlement menu.' } | ConvertTo-Json -Compress
        }
        elseif ([bool]$state.party.isMoving -and -not [string]::IsNullOrWhiteSpace([string]$state.location.targetSettlementId)) {
            [pscustomobject]@{ observeAgain = $true; waitSeconds = 5; reason = 'The Native party is still travelling; wait briefly and observe again.' } | ConvertTo-Json -Compress
        }
        else { [pscustomobject]@{ done = $true; reason = 'The party did not arrive at the observed settlement.' } | ConvertTo-Json -Compress }
        exit 0
    }
    if ([string]$receipt.action -ceq 'recruitOptions') {
        if (Test-Path -LiteralPath $offerMarker -PathType Leaf) {
            $offer = @($receipt.data.offers | Where-Object { $_.available -and [int]$_.cost -le [int]$state.economy.gold -and [int]$state.party.members -lt [int]$state.party.sizeLimit } | Select-Object -First 1)
            if ($offer.Count -ne 1) { throw 'Refreshed Native receipt contained no safe recruit offer.' }
            [pscustomobject]@{ action = 'recruit'; arguments = @{ OwnerId = [string]$offer[0].ownerId; TroopId = [string]$offer[0].troopId; VolunteerSlot = [int]$offer[0].slot; ConfirmPartySizeWarning = $false }; rationale = 'Select an affordable current Native offer that fits party capacity.' } | ConvertTo-Json -Compress
        }
        else {
            Set-Content -LiteralPath $offerMarker -Value 'stale-offer-sent' -Encoding UTF8
            [pscustomobject]@{ action = 'recruit'; arguments = @{ OwnerId = 'stale-owner'; TroopId = 'stale-troop'; VolunteerSlot = 999; ConfirmPartySizeWarning = $false }; rationale = 'Intentional stale-offer test: request a nonexistent offer to verify pre-Native rejection.' } | ConvertTo-Json -Compress
        }
        exit 0
    }
    if ([string]$receipt.action -ceq 'recruit') {
        if (-not [bool]$receipt.data.verified -or [int]$state.party.members -ne [int]$receipt.data.afterMembers -or [int]$state.economy.gold -ne [int]$receipt.data.afterGold) { throw 'Recovered Native recruitment did not match the fresh state.' }
        [pscustomobject]@{ done = $true; reason = 'One refreshed Native offer completed and the fresh state confirms its result.' } | ConvertTo-Json -Compress
        exit 0
    }
    throw "Unexpected receipt '$($receipt.action)' in stale offer recovery test."
}
if ($env:CHRONICLE_TEST_PROVIDER_MODE -eq 'decisionContext') {
    $expectedGoal = [string]$env:CHRONICLE_TEST_EXPECTED_GOAL
    if ([string]::IsNullOrWhiteSpace($expectedGoal) -or [string]$request.goal -cne $expectedGoal)
        { throw 'Decision request did not preserve the explicit task goal.' }
    $catalog = @($request.allowedActions)
    $move = @($catalog | Where-Object { $_.action -eq 'move' } | Select-Object -First 1)
    $settlementTargets = @($catalog | Where-Object { $_.action -eq 'mapSettlementTargets' } | Select-Object -First 1)
    $catalogNames = @($catalog | ForEach-Object { [string]$_.action } | Sort-Object)
    if ($catalog.Count -ne 2 -or $move.Count -ne 1 -or 'SettlementId' -notin @($move[0].arguments) -or $settlementTargets.Count -ne 1 -or
        ($catalogNames -join ',') -cne 'mapSettlementTargets,move')
        { throw 'Decision request did not enforce the exact requested map-action scope.' }
    if ($request.iteration -eq 1) {
        [pscustomobject]@{ action = 'mapSettlementTargets'; arguments = @{}; rationale = "Context contract accepted goal '$expectedGoal' with only the two requested map actions." } | ConvertTo-Json -Compress
        exit 0
    }
    if ($request.iteration -eq 2 -and $request.previousActionReceipt.action -eq 'mapSettlementTargets') {
        [pscustomobject]@{ done = $true; reason = 'Context and prior Native receipt remained present on the next model turn.' } | ConvertTo-Json -Compress
        exit 0
    }
    throw 'Decision-context provider received an unexpected iteration or missing Native action receipt.'
}
if ($env:CHRONICLE_TEST_PROVIDER_MODE -eq 'goalVerifierRejectedDone') {
    if ([string]$request.completionContract.contractId -cne 'harness-impossible-tick-goal-v1') { throw 'The Native completion contract was not forwarded intact to the deterministic Provider.' }
    $catalogNames = @($request.allowedActions | ForEach-Object { [string]$_.action } | Sort-Object -Unique)
    if (($catalogNames -join ',') -cne 'state') { throw 'Goal verification feedback test must expose only the requested read-only Native state action.' }
    if ($request.iteration -eq 1) {
        [pscustomobject]@{ done = $true; reason = 'Intentional early completion proposal for the Native goal verifier regression.' } | ConvertTo-Json -Compress
        exit 0
    }
    if ($request.iteration -eq 2) {
        $tickFailure = @($request.decisionFeedback.missingConditions | Where-Object { $_.id -ceq 'daily-ticks' })
        if ([string]$request.decisionFeedback.kind -cne 'goal-not-satisfied' -or -not [bool]$request.decisionFeedback.noNativeActionSent -or $tickFailure.Count -ne 1 -or [int]$tickFailure[0].actual -ge [int]$tickFailure[0].expected -or $request.previousActionReceipt) {
            throw 'Rejected done feedback did not name the current unmet Native tick requirement without sending an action.'
        }
        [pscustomobject]@{ action = 'state'; arguments = @{}; rationale = 'Re-read current Native state after the verifier rejected a premature stop.' } | ConvertTo-Json -Compress
        exit 0
    }
    if ($request.iteration -eq 3) {
        if ([string]$request.previousActionReceipt.action -cne 'state' -or [string]$request.decisionFeedback.kind -cne '' -or [int]$request.observation.dailyTickCount -ge 999999) {
            throw 'The loop did not continue with a fresh Native state after an incomplete done proposal.'
        }
        [pscustomobject]@{ done = $true; reason = 'Intentional second early completion proposal; the contract must continue to reject it.' } | ConvertTo-Json -Compress
        exit 0
    }
    throw "Unexpected goal verifier test iteration '$($request.iteration)'."
}
if ($env:CHRONICLE_TEST_PROVIDER_MODE -eq 'goalVerifierResume') {
    $tickFailure = @($request.decisionFeedback.missingConditions | Where-Object { $_.id -ceq 'daily-ticks' })
    if ([string]$request.completionContract.contractId -cne 'harness-impossible-tick-goal-v1' -or
        [string]$request.checkpointContext.status -cne 'active' -or
        [string]$request.decisionFeedback.kind -cne 'goal-not-satisfied-after-resume' -or
        -not [bool]$request.decisionFeedback.noNativeActionSent -or $tickFailure.Count -ne 1 -or
        [int]$request.observation.dailyTickCount -ge 999999) {
        throw 'Checkpoint resume did not re-read Native state and return the persisted goal contract with exact unmet conditions.'
    }
    [pscustomobject]@{ action = 'state'; arguments = @{}; rationale = 'Re-observe the saved Native Campaign after goal verification feedback on resume.' } | ConvertTo-Json -Compress
    exit 0
}
if ($env:CHRONICLE_TEST_PROVIDER_MODE -eq 'recruitment') {
    if ($request.iteration -eq 1) {
        [pscustomobject]@{ action = 'recruitOptions'; arguments = @{}; rationale = 'Deterministic harness test: request native volunteer offers.' } | ConvertTo-Json -Compress
        exit 0
    }
    $receipt = $request.previousActionReceipt
    if ($receipt.action -ne 'recruitOptions' -or -not $receipt.data.offers) { throw 'Recruitment provider did not receive native recruitOptions data.' }
    $gold = [int]$request.observation.state.economy.gold
    $offer = @($receipt.data.offers | Where-Object { $_.available -and [int]$_.cost -le $gold } | Sort-Object cost | Select-Object -First 1)
    if ($offer.Count -ne 1) { throw 'Recruitment provider received no affordable volunteer offer.' }
    $confirmCapacity = ([int]$receipt.data.partySize + 1 -gt [int]$receipt.data.partyCapacity)
    [pscustomobject]@{ action = 'recruit'; arguments = @{ OwnerId = [string]$offer[0].ownerId; TroopId = [string]$offer[0].troopId; VolunteerSlot = [int]$offer[0].slot; ConfirmPartySizeWarning = $confirmCapacity }; rationale = 'Deterministic harness test: select the cheapest affordable native offer and make the native over-limit choice explicit.' } | ConvertTo-Json -Compress
    exit 0
}
if ($env:CHRONICLE_TEST_PROVIDER_MODE -eq 'escort') {
    $parties = @($request.observation.state.nearbyParties | Where-Object { $_.isMoving -and $null -eq $_.currentSettlementId -and $_.distance -gt 1.0 } | Sort-Object distance)
    if ($parties.Count -eq 0) { throw 'Escort provider received no visible moving party in the native observation.' }
    [pscustomobject]@{ action = 'follow'; arguments = @{ PartyId = [string]$parties[0].id }; rationale = 'Deterministic harness test: choose a visible map Party and use its native Escort action.' } | ConvertTo-Json -Compress
    exit 0
}
if ($env:CHRONICLE_TEST_PROVIDER_MODE -eq 'timeModes') {
    $action = switch ([int]$request.iteration) {
        1 { 'resume' }
        2 { 'fastForward' }
        3 { 'pause' }
        default { throw "Unexpected timeModes provider iteration $($request.iteration)." }
    }
    [pscustomobject]@{ action = $action; arguments = @{}; rationale = "Deterministic harness test: select Native Campaign time control '$action' as a separate world-time action." } | ConvertTo-Json -Compress
    exit 0
}
if ($env:CHRONICLE_TEST_PROVIDER_MODE -eq 'waitingResume') {
    $action = switch ([int]$request.iteration) {
        1 { 'hold' }
        2 { 'resume' }
        default { throw "Unexpected waitingResume provider iteration $($request.iteration)." }
    }
    [pscustomobject]@{ action = $action; arguments = @{}; rationale = "Deterministic harness test: verify native '$action' while the MainParty is waiting." } | ConvertTo-Json -Compress
    exit 0
}
if ($env:CHRONICLE_TEST_PROVIDER_MODE -eq 'observationLoop') {
    if ($request.iteration -eq 1) {
        [pscustomobject]@{ action = 'state'; arguments = @{}; rationale = 'Deterministic Harness loop check: request a read-only Campaign state.' } | ConvertTo-Json -Compress
        exit 0
    }
    if ($request.iteration -eq 2 -and $request.previousActionReceipt.action -eq 'state') {
        [pscustomobject]@{ action = 'mapPartyTargets'; arguments = @{}; rationale = 'Deterministic Harness loop check: continue from the prior receipt with a read-only Native map target query.' } | ConvertTo-Json -Compress
        exit 0
    }
    throw 'Observation loop provider received an unexpected iteration or prior receipt.'
}
if ($env:CHRONICLE_TEST_PROVIDER_MODE -eq 'unicodeRoundTrip') {
    $observedHeroName = [string]$request.observation.state.identity.heroName
    $expectedHeroName = [string]$env:CHRONICLE_TEST_EXPECTED_HERO_NAME
    if ([string]::IsNullOrEmpty($expectedHeroName) -or $observedHeroName -cne $expectedHeroName) {
        throw "Unicode observation did not round-trip through the Agent transport. Expected '$expectedHeroName'; received '$observedHeroName'."
    }
    [pscustomobject]@{ action = 'state'; arguments = @{}; rationale = 'Unicode Agent transport round-trip matched the live Native hero name.' } | ConvertTo-Json -Compress
    exit 0
}
if ($env:CHRONICLE_TEST_PROVIDER_MODE -eq 'doneSignal') {
    if ($request.iteration -eq 1) {
        [pscustomobject]@{ action = 'state'; arguments = @{}; rationale = 'Deterministic Harness termination check: acquire one fresh observation before stopping.' } | ConvertTo-Json -Compress
        exit 0
    }
    if ($request.iteration -eq 2 -and $request.previousActionReceipt.action -eq 'state') {
        [pscustomobject]@{ done = $true; reason = 'Harness termination check observed its required state.' } | ConvertTo-Json -Compress
        exit 0
    }
    throw 'Done-signal provider received an unexpected iteration or missing state receipt.'
}
if ($env:CHRONICLE_TEST_PROVIDER_MODE -eq 'point') {
    $state = $request.observation.state
    if ($state.party.isAtSea) { throw 'Point provider fixture must begin on land.' }
    [pscustomobject]@{ action = 'moveToPoint'; arguments = @{ X = [double]$state.location.x + 1.5; Y = [double]$state.location.y; Surface = 'land' }; rationale = 'Deterministic harness test: request one nearby land coordinate from current observed map position.' } | ConvertTo-Json -Compress
    exit 0
}
if ($env:CHRONICLE_TEST_PROVIDER_MODE -eq 'tavernApproach') {
    $state = $request.observation.state
    if ($state.context.gameState -ne 'MissionState' -or $state.mission.sceneName -notmatch 'tavern') { throw 'Tavern movement provider requires a live Tavern Location Mission.' }
    $mainAgent = $state.mission.mainAgent
    $candidate = @($state.mission.nearbyHeroAgents | Where-Object { -not $_.isEnemy -and $_.distance -gt 1.2 } | Sort-Object distance | Select-Object -First 1)
    if ($candidate.Count -ne 1) { throw 'Tavern movement provider received no safe, nearby HeroAgent candidate.' }
    $forwardX = [double]$mainAgent.lookDirection.x
    $forwardY = [double]$mainAgent.lookDirection.y
    $forwardLength = [Math]::Sqrt($forwardX * $forwardX + $forwardY * $forwardY)
    if ($forwardLength -lt 0.01) { throw 'MainAgent look direction is degenerate.' }
    $forwardX /= $forwardLength
    $forwardY /= $forwardLength
    $deltaX = [double]$candidate[0].position.x - [double]$mainAgent.position.x
    $deltaY = [double]$candidate[0].position.y - [double]$mainAgent.position.y
    $axisX = ($deltaX * $forwardY) - ($deltaY * $forwardX)
    $axisY = ($deltaX * $forwardX) + ($deltaY * $forwardY)
    $axisLength = [Math]::Sqrt($axisX * $axisX + $axisY * $axisY)
    if ($axisLength -lt 0.01) { throw 'Observed HeroAgent target has no horizontal direction from MainAgent.' }
    [pscustomobject]@{
        action = 'missionInput'
        arguments = @{ X = ($axisX / $axisLength); Y = ($axisY / $axisLength); DurationSeconds = 0.35 }
        rationale = "Deterministic test provider: one bounded movement step toward currently observed HeroAgent $($candidate[0].heroId)."
    } | ConvertTo-Json -Compress
    exit 0
}
if ($env:CHRONICLE_TEST_PROVIDER_MODE -eq 'townExplore') {
    if ($request.iteration -gt 1) { Start-Sleep -Milliseconds 450 }
    $state = $request.observation.state
    if ($state.context.gameState -ne 'MissionState' -or $state.mission.sceneName -notmatch '_town_') { throw 'Town exploration provider requires a live Town Center Location Mission.' }
    $mainAgent = $state.mission.mainAgent
    $candidate = @($state.mission.nearbySceneAgents | Where-Object { -not $_.isEnemy -and $_.occupation -ne 'Soldier' -and $_.distance -gt 1.2 -and [Math]::Abs([double]$_.position.z - [double]$mainAgent.position.z) -le 1.5 } | Sort-Object distance | Select-Object -First 1)
    if ($candidate.Count -eq 1) {
        $forwardX = [double]$mainAgent.lookDirection.x
        $forwardY = [double]$mainAgent.lookDirection.y
        $forwardLength = [Math]::Sqrt($forwardX * $forwardX + $forwardY * $forwardY)
        if ($forwardLength -lt 0.01) { throw 'MainAgent look direction is degenerate.' }
        $forwardX /= $forwardLength
        $forwardY /= $forwardLength
        $deltaX = [double]$candidate[0].position.x - [double]$mainAgent.position.x
        $deltaY = [double]$candidate[0].position.y - [double]$mainAgent.position.y
        $axisX = ($deltaX * $forwardY) - ($deltaY * $forwardX)
        $axisY = ($deltaX * $forwardX) + ($deltaY * $forwardY)
        $axisLength = [Math]::Sqrt($axisX * $axisX + $axisY * $axisY)
        if ($axisLength -lt 0.01) { throw 'Nearby Town Agent has no horizontal direction from MainAgent.' }
        $axisX /= $axisLength
        $axisY /= $axisLength
        $rationale = "Deterministic test provider: steer one bounded step toward observed Agent $($candidate[0].agentIndex)."
    }
    else {
        if ($request.iteration -ge 33 -and $request.iteration -le 40) {
            $axisX = -1.0
            $axisY = 0.0
            $rationale = 'Deterministic route probe: the prior bounded forward/rightward sample ended at a visible wall corner, so test the opposite lateral direction with short steps and reobserve.'
        }
        elseif ($request.iteration -ge 41 -and $request.iteration -le 44) {
            $axisX = 0.0
            $axisY = 1.0
            $rationale = 'Deterministic route probe: advance briefly after moving around the wall corner, then observe nearby agents again.'
        }
        elseif ($request.iteration -ge 18 -and $request.iteration -le 24) {
            $axisX = 1.0
            $axisY = 0.0
            $rationale = 'Deterministic test provider: after the gate-facing forward probes, take brief rightward steps toward the open gate lane and reobserve.'
        }
        else {
            $axisX = 0.0
            $axisY = 1.0
            $rationale = 'Deterministic test provider: local town scene has no safe nearby target yet, so take one short native forward-input step and reobserve.'
        }
    }
    [pscustomobject]@{ action = 'missionInput'; arguments = @{ X = $axisX; Y = $axisY; DurationSeconds = 0.35 }; rationale = $rationale } | ConvertTo-Json -Compress
    exit 0
}
if ($env:CHRONICLE_TEST_PROVIDER_MODE -eq 'locationAim') {
    $state = $request.observation.state
    if ($state.context.gameState -ne 'MissionState' -or $state.mission.mode -ne 'StartUp') { throw 'Location aim provider requires a live non-battle Location Mission.' }
    $candidate = @($state.mission.nearbySceneAgents | Where-Object { -not $_.isEnemy -and $_.occupation -ne 'Soldier' -and $_.distance -gt 1.0 } | Sort-Object distance | Select-Object -First 1)
    if ($candidate.Count -ne 1) { throw 'Location aim provider received no safe Agent in the bounded local observation.' }
    [pscustomobject]@{ action = 'missionAimAt'; arguments = @{ AgentIndex = [int]$candidate[0].agentIndex }; rationale = "Deterministic test provider: aim the native Mission camera at currently observed local Agent $($candidate[0].agentIndex) and verify Focus." } | ConvertTo-Json -Compress
    exit 0
}
$mode = [string]$request.observation.timeControlMode
if (-not $mode) { $mode = [string]$request.observation.state.timeControlMode }
$action = if ($mode -eq 'Stop' -or $mode -eq 'FastForwardStop') { 'resume' } else { 'pause' }
[pscustomobject]@{ action = $action; arguments = @{}; rationale = 'Deterministic harness adapter: toggle campaign clock to exercise the observation/action boundary.' } | ConvertTo-Json -Compress
