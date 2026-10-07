$ErrorActionPreference = 'Stop'
# Deterministic same-save baseline Provider; this never calls an LLM.
$reader = New-Object System.IO.StreamReader -ArgumentList @([Console]::OpenStandardInput(), [System.Text.Encoding]::UTF8, $true)
try { $requestJson = $reader.ReadToEnd() }
finally { $reader.Dispose() }
$request = $requestJson | ConvertFrom-Json
if ([int]$request.schemaVersion -ne 2) { throw 'Unsupported evaluation baseline decision request schema.' }
$state = $request.observation.state
$receipt = $request.previousActionReceipt
if ([string]::IsNullOrWhiteSpace([string]$request.goal) -or -not $state) { throw 'Evaluation baseline requires the explicit task goal and current Native observation.' }

$decision = $null
if (-not $receipt) {
    $decision = [ordered]@{ action = 'mapSettlementTargets'; arguments = @{}; rationale = 'Start from the current Native map observation and request its visible settlement targets.' }
}
elseif ([string]$receipt.action -ceq 'mapSettlementTargets') {
    $currentSettlementId = [string]$state.location.currentSettlementId
    $target = @($receipt.data.mapSettlementTargets | Where-Object { [string]$_.id -cne $currentSettlementId -and [double]$_.distance -gt 1.0 -and -not [bool]$_.hostile -and -not [bool]$_.underSiege -and [string]$_.type -cne 'hideout' } | Sort-Object { [double]$_.distance } | Select-Object -First 1)
    if ($target.Count -ne 1) {
        $decision = [ordered]@{ done = $true; reason = 'No currently observed safe settlement is available in the native target receipt.' }
    }
    else {
        $decision = [ordered]@{ action = 'move'; arguments = @{ SettlementId = [string]$target[0].id }; rationale = 'Select the nearest currently observed safe Settlement and use its Native map-move entry.' }
    }
}
elseif ([string]$receipt.action -in @('move','resume','observeAgain')) {
    $targetId = [string]$state.location.targetSettlementId
    $currentId = [string]$state.location.currentSettlementId
    if (-not [string]::IsNullOrWhiteSpace($targetId) -and $currentId -ceq $targetId -and $state.context.menuId -in @('town','town_backstreet','village')) {
        $recruitOption = @($state.availableMenuOptions | Where-Object { $_.id -eq 'recruit_volunteers' -and $_.available -and $_.enabled } | Select-Object -First 1)
        if ($recruitOption.Count -eq 1) {
            $decision = [ordered]@{ action = 'recruitOptions'; arguments = @{}; rationale = 'Native arrival opened the current settlement menu and its volunteer-recruitment option is enabled.' }
        }
        else { $decision = [ordered]@{ done = $true; reason = 'Native arrival completed but the current Settlement does not expose enabled volunteer recruitment.' } }
    }
    elseif ([bool]$state.party.isMoving -and -not [string]::IsNullOrWhiteSpace($targetId)) {
        if ([string]$state.context.timeControlMode -in @('Stop','FastForwardStop')) {
            $decision = [ordered]@{ action = 'resume'; arguments = @{}; rationale = 'Native map movement is still active while the explicit Campaign clock is stopped.' }
        }
        else {
            $decision = [ordered]@{ observeAgain = $true; waitSeconds = 5; reason = 'The Native party is still moving toward its observed target; take another bounded observation.' }
        }
    }
    else { $decision = [ordered]@{ done = $true; reason = 'Native movement stopped before observed settlement arrival; no target is safe to repeat.' } }
}
elseif ([string]$receipt.action -ceq 'recruitOptions') {
    $currentGold = [int]$state.economy.gold
    $withinCapacity = [int]$state.party.members -lt [int]$state.party.sizeLimit
    $offer = @($receipt.data.offers | Where-Object { $_.available -and [int]$_.cost -le $currentGold } | Sort-Object cost,ownerId,troopId,slot | Select-Object -First 1)
    if ($offer.Count -ne 1 -or -not $withinCapacity) {
        $decision = [ordered]@{ done = $true; reason = 'The current Native volunteer offers contain no affordable recruit that fits the current MainParty capacity.' }
    }
    else {
        $decision = [ordered]@{ action = 'recruit'; arguments = @{ OwnerId = [string]$offer[0].ownerId; TroopId = [string]$offer[0].troopId; VolunteerSlot = [int]$offer[0].slot; ConfirmPartySizeWarning = $false }; rationale = 'Choose the cheapest currently available affordable offer that fits the observed party capacity.' }
    }
}
elseif ([string]$receipt.action -ceq 'recruit') {
    $verified = ([bool]$receipt.data.verified -and [int]$state.party.members -eq [int]$receipt.data.afterMembers -and [int]$state.economy.gold -eq [int]$receipt.data.afterGold)
    if ($verified) { $decision = [ordered]@{ done = $true; reason = 'Fresh Native state confirms one volunteer was added and the receipt Native cost was charged.' } }
    else { $decision = [ordered]@{ action = 'recruitOptions'; arguments = @{}; rationale = 'The last recruitment receipt is not yet confirmed in current Native party/gold state; refresh current offers before any further choice.' } }
}
else {
    $decision = [ordered]@{ done = $true; reason = 'The current action receipt is outside this evaluation scenario.' }
}

$decision | ConvertTo-Json -Depth 12 -Compress
