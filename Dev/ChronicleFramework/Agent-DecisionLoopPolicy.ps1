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
            Recoverable = $false
            Reason = 'observeAgain requires a completed Native move/resume receipt and a matching active map target.'
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
