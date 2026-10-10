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

function Get-NativeRestMonitorTarget {
    param(
        [Parameter(Mandatory = $true)][string]$Action,
        [Parameter(Mandatory = $true)]$Arguments,
        [Parameter(Mandatory = $true)]$Receipt
    )

    $days = 0
    $startingDailyTickCount = 0
    if ($Action -cne 'rest' -or [string]$Receipt.status -cne 'accepted' -or
        -not [int]::TryParse([string]$Arguments.Days, [ref]$days) -or $days -lt 1 -or
        -not [int]::TryParse([string]$Receipt.dailyTickCount, [ref]$startingDailyTickCount) -or $startingDailyTickCount -lt 0) {
        return $null
    }
    return [pscustomobject]@{
        StartingDailyTickCount = $startingDailyTickCount
        RequestedDays = $days
        TargetDailyTickCount = $startingDailyTickCount + $days
    }
}

function Test-NativeRestMonitorNeeded {
    param(
        [Parameter(Mandatory = $true)]$Observation,
        [Parameter(Mandatory = $true)]$MonitorTarget
    )

    $state = $Observation.state
    $dailyTickCount = 0
    $hasDailyTickCount = [int]::TryParse([string]$Observation.dailyTickCount, [ref]$dailyTickCount)
    return (
        $hasDailyTickCount -and $dailyTickCount -lt [int]$MonitorTarget.TargetDailyTickCount -and
        [string]$state.context.gameState -ceq 'MapState' -and
        [string]$state.context.menuId -ceq 'town_wait_menus' -and [bool]$state.context.isWaiting -and
        [string]$state.context.timeControlMode -in @('UnstoppableFastForward','UnstoppableFastForwardForPartyWaitTime')
    )
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

function Get-AgentCompletionObservationValue {
    param(
        [Parameter(Mandatory = $true)]$Observation,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $value = $null
    switch -CaseSensitive ($Path) {
        'campaignDay' { $value = $Observation.campaignDay; break }
        'dailyTickCount' { $value = $Observation.dailyTickCount; break }
        'state.context.gameState' { $value = $Observation.state.context.gameState; break }
        'state.context.menuId' { $value = $Observation.state.context.menuId; break }
        'state.context.isWaiting' { $value = $Observation.state.context.isWaiting; break }
        'state.location.currentSettlementId' { $value = $Observation.state.location.currentSettlementId; break }
        'state.party.members' { $value = $Observation.state.party.members; break }
        'state.party.food' { $value = $Observation.state.party.food; break }
        'state.economy.gold' { $value = $Observation.state.economy.gold; break }
        default { return [pscustomobject]@{ Known = $false; Value = $null } }
    }

    $parts = $Path.Split('.')
    $cursor = $Observation
    foreach ($part in $parts) {
        if ($null -eq $cursor) { return [pscustomobject]@{ Known = $false; Value = $null } }
        $property = @($cursor.PSObject.Properties | Where-Object { $_.Name -ceq $part } | Select-Object -First 1)
        if ($property.Count -ne 1) { return [pscustomobject]@{ Known = $false; Value = $null } }
        $cursor = $property[0].Value
    }
    if ($null -eq $cursor) { return [pscustomobject]@{ Known = $false; Value = $null } }
    return [pscustomobject]@{ Known = $true; Value = $cursor }
}

function Test-AgentGoalCompletion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Contract,
        [Parameter(Mandatory = $true)]$Observation,
        [switch]$ValidateOnly
    )

    if ([int]$Contract.schemaVersion -ne 1 -or [string]::IsNullOrWhiteSpace([string]$Contract.contractId)) {
        throw 'Completion contract must have schemaVersion 1 and a non-empty contractId.'
    }
    $conditions = @($Contract.conditions)
    if ($conditions.Count -lt 1 -or $conditions.Count -gt 24) { throw 'Completion contract must contain between 1 and 24 bounded conditions.' }
    $allowedPaths = @('campaignDay','dailyTickCount','state.context.gameState','state.context.menuId','state.context.isWaiting','state.location.currentSettlementId','state.party.members','state.party.food','state.economy.gold')
    $conditionIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($condition in $conditions) {
        $id = [string]$condition.id
        $path = [string]$condition.path
        $operator = [string]$condition.operator
        if ([string]::IsNullOrWhiteSpace($id) -or -not $conditionIds.Add($id)) { throw 'Completion contract condition IDs must be non-empty and unique.' }
        if ($path -notin $allowedPaths) { throw "Completion contract path '$path' is not in the Native observation allowlist." }
        if ($operator -notin @('eq','gte')) { throw "Completion contract operator '$operator' is not supported." }
        $hasExpectedValue = if ($condition -is [System.Collections.IDictionary]) { $condition.Contains('expected') } else { 'expected' -in @($condition.PSObject.Properties.Name) }
        if (-not $hasExpectedValue) { throw "Completion contract condition '$id' has no expected value." }
        if ($operator -eq 'gte' -and ($condition.expected -is [string] -or $condition.expected -is [bool] -or -not ($condition.expected -is [ValueType]))) {
            throw "Completion contract condition '$id' uses gte with a non-numeric expected value."
        }
    }
    if ($ValidateOnly) { return [pscustomobject]@{ Valid = $true; ContractId = [string]$Contract.contractId; ConditionCount = $conditions.Count } }

    $evaluated = [System.Collections.Generic.List[object]]::new()
    foreach ($condition in $conditions) {
        $read = Get-AgentCompletionObservationValue -Observation $Observation -Path ([string]$condition.path)
        $status = 'unknown'
        if ($read.Known) {
            if ([string]$condition.operator -eq 'gte') {
                $status = if ([double]$read.Value -ge [double]$condition.expected) { 'satisfied' } else { 'unmet' }
            }
            elseif ($condition.expected -is [bool]) {
                $status = if ($read.Value -is [bool] -and [bool]$read.Value -eq [bool]$condition.expected) { 'satisfied' } else { 'unmet' }
            }
            elseif ($condition.expected -is [ValueType] -and $condition.expected -isnot [string]) {
                $status = if ($read.Value -is [ValueType] -and $read.Value -isnot [bool] -and [double]$read.Value -eq [double]$condition.expected) { 'satisfied' } else { 'unmet' }
            }
            else {
                $status = if ([string]$read.Value -ceq [string]$condition.expected) { 'satisfied' } else { 'unmet' }
            }
        }
        $evaluated.Add([ordered]@{
            id = [string]$condition.id
            path = [string]$condition.path
            operator = [string]$condition.operator
            expected = $condition.expected
            actual = if ($read.Known) { $read.Value } else { $null }
            status = $status
        })
    }
    $missing = @($evaluated | Where-Object { $_.status -eq 'unmet' })
    $unknown = @($evaluated | Where-Object { $_.status -eq 'unknown' })
    $resultStatus = if ($missing.Count -eq 0 -and $unknown.Count -eq 0) { 'satisfied' } elseif ($unknown.Count -gt 0) { 'unknown' } else { 'unmet' }
    return [pscustomobject]@{
        ContractId = [string]$Contract.contractId
        Status = $resultStatus
        Satisfied = ($resultStatus -eq 'satisfied')
        Conditions = @($evaluated)
        MissingConditions = @($missing)
        UnknownConditions = @($unknown)
    }
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
    $receiptData = $Receipt.data
    if ([string]$Receipt.action -ceq 'foodOptions' -and $Receipt.data) {
        $receiptData = [ordered]@{
            hasPendingChanges = [bool]$Receipt.data.hasPendingChanges
            offers = @($Receipt.data.offers | ForEach-Object {
                [ordered]@{
                    viewModelItemId = $_.viewModelItemId
                    itemId = $_.itemId
                    modifierId = $_.modifierId
                    name = $_.name
                    stock = $_.stock
                    nativeItemCost = $_.nativeItemCost
                    inventoryLogicUnitPrice = $_.inventoryLogicUnitPrice
                    isFood = $_.isFood
                    isTransferable = $_.isTransferable
                }
            })
        }
    }
    return [ordered]@{
        protocolVersion = $Receipt.protocolVersion
        commandId = $Receipt.commandId
        action = $Receipt.action
        status = $Receipt.status
        campaignDay = $Receipt.campaignDay
        timeControlMode = $Receipt.timeControlMode
        data = $receiptData
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
