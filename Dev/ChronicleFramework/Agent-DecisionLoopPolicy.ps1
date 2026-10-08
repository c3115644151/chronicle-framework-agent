function Get-ObserveAgainPolicy {
    param(
        [Parameter(Mandatory = $true)]$Observation,
        [Parameter(Mandatory = $true)]$PreviousActionReceipt
    )

    $state = $Observation.state
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
