function Test-UnobstructedCampaignMap {
    param([Parameter(Mandatory = $true)]$State)

    return (
        [string]$State.context.gameState -ceq 'MapState' -and
        -not [bool]$State.context.encounterActive -and
        [string]::IsNullOrWhiteSpace([string]$State.context.menuId) -and
        -not [bool]$State.context.escapeMenuOpen -and -not [bool]$State.context.inquiryOpen
    )
}

function Get-ObserveAgainPolicy {
    param(
        [Parameter(Mandatory = $true)]$Observation,
        [Parameter(Mandatory = $true)]$PreviousActionReceipt
    )

    $state = $Observation.state
    $nativeWaitActive = (
        [string]$state.context.gameState -ceq 'MapState' -and
        [string]$state.context.menuId -ceq 'town_wait_menus' -and
        [bool]$state.context.isWaiting
    )
    if ($nativeWaitActive) {
        $restWasAccepted = ($PreviousActionReceipt -and [string]$PreviousActionReceipt.action -ceq 'rest' -and [string]$PreviousActionReceipt.status -ceq 'accepted')
        $nativeWaitClockRunning = [string]$state.context.timeControlMode -in @('UnstoppableFastForward','UnstoppableFastForwardForPartyWaitTime')
        if ($restWasAccepted -and $nativeWaitClockRunning) {
            return [pscustomobject]@{ Allowed = $true; Recoverable = $false; Reason = 'The accepted Native Town Wait is actively advancing; observeAgain only waits outside the game and re-reads state.' }
        }
        return [pscustomobject]@{ Allowed = $false; Recoverable = $true; Reason = 'Native Town Wait has no accepted active rest request or its Campaign clock is stopped.' }
    }

    $nativeEncounterOrStop = (
        [string]$state.context.gameState -ceq 'MapState' -and
        ([bool]$state.context.encounterActive -or -not [string]::IsNullOrWhiteSpace([string]$state.context.menuId) -or
            [bool]$state.context.escapeMenuOpen -or [bool]$state.context.inquiryOpen -or
            [string]$state.context.timeControlMode -notin @('StoppablePlay','UnstoppableFastForward'))
    )
    if ($nativeEncounterOrStop) {
        return [pscustomobject]@{
            Allowed = $false
            Recoverable = $true
            Reason = "Native map context blocks waiting (menu='$($state.context.menuId)', encounter=$([bool]$state.context.encounterActive), timeMode='$($state.context.timeControlMode)')."
        }
    }

    $targetSettlementId = [string]$PreviousActionReceipt.state.location.targetSettlementId
    if ([string]$state.context.gameState -cne 'MapState' -or
        [string]$PreviousActionReceipt.action -notin @('move','resume') -or
        [string]$PreviousActionReceipt.status -cne 'completed' -or
        [string]::IsNullOrWhiteSpace($targetSettlementId) -or
        [string]$state.location.targetSettlementId -cne $targetSettlementId) {
        return [pscustomobject]@{
            Allowed = $false
            Recoverable = $true
            Reason = 'observeAgain is unavailable without an active Native move or accepted Town Wait; no scheduler wait or game action was started.'
        }
    }

    if ([string]$state.location.currentSettlementId -ceq $targetSettlementId) {
        return [pscustomobject]@{
            Allowed = $false
            Recoverable = $true
            Reason = 'The Native party has already arrived at the move target.'
        }
    }

    if ([bool]$state.context.encounterActive -or
        -not [string]::IsNullOrWhiteSpace([string]$state.context.menuId) -or
        [bool]$state.context.escapeMenuOpen -or [bool]$state.context.inquiryOpen) {
        return [pscustomobject]@{
            Allowed = $false
            Recoverable = $true
            Reason = 'A Native encounter, menu, escape menu, or inquiry is active; waiting cannot resolve it.'
        }
    }

    if ([string]$state.context.timeControlMode -notin @('StoppablePlay','UnstoppableFastForward')) {
        return [pscustomobject]@{
            Allowed = $false
            Recoverable = $true
            Reason = "Native Campaign time is not advancing (mode='$($state.context.timeControlMode)')."
        }
    }

    if (-not [bool]$state.party.isMoving) {
        return [pscustomobject]@{
            Allowed = $false
            Recoverable = $true
            Reason = 'The Native party is no longer moving toward its target.'
        }
    }

    return [pscustomobject]@{ Allowed = $true; Recoverable = $false; Reason = 'Native movement is active and Campaign time is advancing.' }
}

function Get-EffectiveControlCatalog {
    param(
        [Parameter(Mandatory = $true)]$Observation,
        $PreviousActionReceipt
    )

    if (-not $PreviousActionReceipt) { return @() }
    $policy = Get-ObserveAgainPolicy -Observation $Observation -PreviousActionReceipt $PreviousActionReceipt
    if (-not $policy.Allowed) { return @() }

    return @([ordered]@{
        control = 'observeAgain'
        waitSecondsMinimum = 1
        waitSecondsMaximum = 10
        description = 'Wait briefly outside the game, then read fresh Native state without issuing a game action.'
    })
}

function Get-TradeActionGate {
    param($State, $PreviousActionReceipt)

    $tradeInventoryActive = (
        $State -and [string]$State.context.gameState -ceq 'InventoryState' -and
        [string]$State.inventoryScreen.mode -ceq 'Trade'
    )
    $allTradeActions = @('foodOptions','tradeOptions','tradeRumors','trade','provision','tradeConfirm','tradeCancel','tradeCancelChanges')
    if (-not $tradeInventoryActive) { return [pscustomobject]@{ TradeInventoryActive = $false; HideActions = $allTradeActions } }

    $hideActions = @()
    $hasCurrentFoodQuote = ($PreviousActionReceipt -and [string]$PreviousActionReceipt.action -ceq 'foodOptions' -and [string]$PreviousActionReceipt.status -ceq 'completed' -and @($PreviousActionReceipt.data.offers).Count -gt 0)
    $hasCurrentTradeQuote = ($PreviousActionReceipt -and [string]$PreviousActionReceipt.action -ceq 'tradeOptions' -and [string]$PreviousActionReceipt.status -ceq 'completed' -and ((@($PreviousActionReceipt.data.buyOffers).Count + @($PreviousActionReceipt.data.sellOffers).Count) -gt 0))
    $hasPendingTransaction = ($PreviousActionReceipt -and [string]$PreviousActionReceipt.status -ceq 'completed' -and [string]$PreviousActionReceipt.action -in @('trade','provision'))
    if (-not $hasCurrentFoodQuote -or $hasPendingTransaction) { $hideActions += 'provision' }
    if ($hasCurrentFoodQuote -or $hasPendingTransaction) { $hideActions += 'foodOptions' }
    if (-not $hasCurrentTradeQuote -or $hasPendingTransaction) { $hideActions += 'trade' }
    if ($hasPendingTransaction) { $hideActions += @('foodOptions','tradeOptions','tradeRumors') }
    else { $hideActions += @('tradeConfirm','tradeCancelChanges') }
    return [pscustomobject]@{ TradeInventoryActive = $true; HideActions = @($hideActions | Sort-Object -Unique) }
}

function Get-CurrentMenuSelectionContext {
    param(
        [Parameter(Mandatory = $true)]$Observation,
        [Parameter(Mandatory = $true)][string]$OptionId
    )

    $state = $Observation.state
    if (-not $state -or [string]$state.context.gameState -cne 'MapState' -or [string]::IsNullOrWhiteSpace([string]$state.context.menuId)) {
        return [pscustomobject]@{ Allowed = $false; MenuId = ''; OptionId = $OptionId; Reason = 'menuSelect requires a current Native Campaign menu.' }
    }
    $option = @($state.availableMenuOptions | Where-Object { [string]$_.id -ceq $OptionId -and [bool]$_.available -and [bool]$_.enabled })
    if ($option.Count -ne 1) {
        return [pscustomobject]@{ Allowed = $false; MenuId = [string]$state.context.menuId; OptionId = $OptionId; Reason = "OptionId '$OptionId' is not a unique enabled option in the current Native menu '$($state.context.menuId)'." }
    }
    return [pscustomobject]@{ Allowed = $true; MenuId = [string]$state.context.menuId; OptionId = $OptionId; Reason = 'OptionId is current and enabled; bind selection to the observed Native menu.' }
}

function Convert-SupplyObservationForDecision {
    param([Parameter(Mandatory = $true)]$Observation)

    if (-not $Observation.state) { return $Observation }
    $state = $Observation.state
    $menuId = [string]$state.context.menuId
    $relevantOptionIds = switch ($menuId) {
        'town' { @('trade','town_wait'); break }
        'town_wait_menus' { @('wait_leave'); break }
        default { @() }
    }
    $menuOptions = @($state.availableMenuOptions | Where-Object { [string]$_.id -in $relevantOptionIds })
    return [ordered]@{
        protocolVersion = $Observation.protocolVersion
        commandId = $Observation.commandId
        action = $Observation.action
        status = $Observation.status
        campaignDay = $Observation.campaignDay
        dailyTickCount = $Observation.dailyTickCount
        timeControlMode = $Observation.timeControlMode
        modelView = 'campaign-multiday-supply'
        state = [ordered]@{
            schemaVersion = $state.schemaVersion
            campaignDay = $state.campaignDay
            party = [ordered]@{
                members = $state.party.members
                sizeLimit = $state.party.sizeLimit
                food = $state.party.food
                foodInventory = $state.party.foodInventory
                foodChange = $state.party.foodChange
                dailyWage = $state.party.dailyWage
                morale = $state.party.morale
            }
            economy = [ordered]@{ gold = $state.economy.gold }
            location = [ordered]@{ currentSettlementId = $state.location.currentSettlementId }
            context = [ordered]@{
                gameState = $state.context.gameState
                timeControlMode = $state.context.timeControlMode
                menuId = $menuId
                isWaiting = $state.context.isWaiting
            }
            inventoryScreen = if ($state.inventoryScreen) { [ordered]@{ mode = $state.inventoryScreen.mode } } else { $null }
            availableMenuOptions = @($menuOptions | ForEach-Object {
                [ordered]@{ id = $_.id; text = $_.text; available = $_.available; enabled = $_.enabled }
            })
        }
    }
}

function Convert-SupplyReceiptForDecision {
    param(
        [Parameter(Mandatory = $true)]$Receipt,
        [Parameter(Mandatory = $true)]$Observation
    )

    $state = if ($Observation) { $Observation.state } else { $null }
    return [ordered]@{
        protocolVersion = $Receipt.protocolVersion
        commandId = $Receipt.commandId
        action = $Receipt.action
        status = $Receipt.status
        campaignDay = $Receipt.campaignDay
        timeControlMode = $Receipt.timeControlMode
        data = $Receipt.data
        error = $Receipt.error
        state = $null
        stateSummary = if ($state) {
            [ordered]@{
                campaignDay = $Observation.campaignDay
                dailyTickCount = $Observation.dailyTickCount
                gold = $state.economy.gold
                members = $state.party.members
                food = $state.party.food
                foodInventory = $state.party.foodInventory
                currentSettlementId = $state.location.currentSettlementId
                gameState = $state.context.gameState
                menuId = $state.context.menuId
                timeControlMode = $state.context.timeControlMode
                isWaiting = $state.context.isWaiting
            }
        } else { $null }
    }
}

function Get-NativeRestActionGate {
    param($State, $PreviousActionReceipt)

    $nativeWaitMenuActive = (
        $State -and [string]$State.context.gameState -ceq 'MapState' -and
        [string]$State.context.menuId -ceq 'town_wait_menus' -and [bool]$State.context.isWaiting
    )
    if (-not $nativeWaitMenuActive) { return [pscustomobject]@{ NativeWaitMenuActive = $false; HideActions = @('rest') } }
    $restAlreadyRequested = (
        $PreviousActionReceipt -and [string]$PreviousActionReceipt.action -ceq 'rest' -and
        [string]$PreviousActionReceipt.status -in @('accepted','completed')
    )
    if ($restAlreadyRequested) { return [pscustomobject]@{ NativeWaitMenuActive = $true; HideActions = @('rest') } }
    return [pscustomobject]@{ NativeWaitMenuActive = $true; HideActions = @() }
}

function Get-BarterActionGate {
    param(
        $BarterOptions,
        $PreviousActionReceipt,
        [string]$BalancedBarterSessionId
    )

    $sessionAvailable = ($BarterOptions -and -not [string]::IsNullOrWhiteSpace([string]$BarterOptions.sessionId) -and [string]$BarterOptions.context -like 'contextual:*')
    if (-not $sessionAvailable) { return [pscustomobject]@{ SessionAvailable = $false; HideActions = @('barterEdit','barterReset','barterAutoBalance','barterOffer','barterCancel') } }

    $previousReceiptOptions = $null
    if ($PreviousActionReceipt -and [string]$PreviousActionReceipt.status -ceq 'completed') {
        if ([string]$PreviousActionReceipt.action -ceq 'barterOptions') { $previousReceiptOptions = $PreviousActionReceipt.data }
        elseif ($PreviousActionReceipt.data.updatedOptions) { $previousReceiptOptions = $PreviousActionReceipt.data.updatedOptions }
    }
    $sameSessionReceipt = ($previousReceiptOptions -and [string]$previousReceiptOptions.sessionId -ceq [string]$BarterOptions.sessionId)
    $balancedCurrentQuote = (-not [string]::IsNullOrWhiteSpace($BalancedBarterSessionId) -and [string]$BalancedBarterSessionId -ceq [string]$BarterOptions.sessionId)
    $hideActions = @()
    if ($sameSessionReceipt) { $hideActions += 'barterOptions' }
    if ($balancedCurrentQuote) { $hideActions += 'barterAutoBalance' }
    else { $hideActions += 'barterOffer' }
    if ([bool]$BarterOptions.isOfferDisabled) { $hideActions += 'barterOffer' }
    return [pscustomobject]@{ SessionAvailable = $true; HideActions = @($hideActions | Sort-Object -Unique) }
}
