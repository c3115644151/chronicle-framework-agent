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
if ($request.schemaVersion -ne 2) { throw 'Unsupported Agent loop request schema.' }
if ($env:CHRONICLE_TEST_PROVIDER_MODE -eq 'checkpointMustNotCall') { throw 'checkpoint-provider-was-called' }
if ($env:CHRONICLE_TEST_PROVIDER_MODE -eq 'checkpointMustNotCall') { throw 'checkpoint-provider-was-called' }
if ($request.iteration -gt 1 -and -not $request.previousActionReceipt) { throw 'Previous native action receipt was not forwarded to the next decision.' }
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
        [string]$request.previousActionReceipt.status -cne 'rejected-before-native' -or $catalogNames -contains 'recruit' -or
        [int]$request.observation.state.party.members -ne 1 -or [int]$request.observation.state.economy.gold -ne 1000) {
        throw 'Unavailable decision feedback did not include a fresh unchanged Native state and a restricted current action catalog.'
    }
    [pscustomobject]@{ action = 'mapSettlementTargets'; arguments = @{}; rationale = 'Recover from the unavailable recruitment proposal using a currently listed map action.' } | ConvertTo-Json -Compress
    exit 0
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
