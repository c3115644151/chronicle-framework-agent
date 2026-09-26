$ErrorActionPreference = 'Stop'
$requestJson = [Console]::In.ReadToEnd()
$request = $requestJson | ConvertFrom-Json
if ($request.schemaVersion -ne 1) { throw 'Unsupported Agent loop request schema.' }
if ($request.iteration -gt 1 -and -not $request.previousActionReceipt) { throw 'Previous native action receipt was not forwarded to the next decision.' }
if ($env:CHRONICLE_TEST_INVALID_DECISION) {
    $invalidAction = [string]$env:CHRONICLE_TEST_INVALID_DECISION
    $arguments = if ($invalidAction -eq 'start') { @{ SaveName = 'must_not_execute' } } else { @{} }
    [pscustomobject]@{ action = $invalidAction; arguments = $arguments; rationale = 'Intentional Agent decision boundary regression test.' } | ConvertTo-Json -Compress
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
    [pscustomobject]@{ action = 'recruit'; arguments = @{ OwnerId = [string]$offer[0].ownerId; TroopId = [string]$offer[0].troopId; VolunteerSlot = [int]$offer[0].slot }; rationale = 'Deterministic harness test: select the cheapest affordable native offer.' } | ConvertTo-Json -Compress
    exit 0
}
if ($env:CHRONICLE_TEST_PROVIDER_MODE -eq 'escort') {
    $parties = @($request.observation.state.nearbyParties | Where-Object { $_.isMoving -and $null -eq $_.currentSettlementId -and $_.distance -gt 1.0 } | Sort-Object distance)
    if ($parties.Count -eq 0) { throw 'Escort provider received no visible moving party in the native observation.' }
    [pscustomobject]@{ action = 'follow'; arguments = @{ PartyId = [string]$parties[0].id }; rationale = 'Deterministic harness test: choose a visible map Party and use its native Escort action.' } | ConvertTo-Json -Compress
    exit 0
}
$mode = [string]$request.observation.timeControlMode
if (-not $mode) { $mode = [string]$request.observation.state.timeControlMode }
$action = if ($mode -eq 'Stop' -or $mode -eq 'FastForwardStop') { 'resume' } else { 'pause' }
[pscustomobject]@{ action = $action; arguments = @{}; rationale = 'Deterministic harness adapter: toggle campaign clock to exercise the observation/action boundary.' } | ConvertTo-Json -Compress
