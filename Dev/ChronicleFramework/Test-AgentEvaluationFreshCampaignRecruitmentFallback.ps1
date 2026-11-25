#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateRange(1,10)][int]$MaxAttempts = 10,
    [int]$TimeoutSeconds = 240,
    [int]$RestWallClockLimitSeconds = 180,
    [ValidateRange(5,30)][int]$FrameRate = 10
)

$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$freshCampaignScript = Join-Path $PSScriptRoot 'Test-AgentFreshCampaign.ps1'
$supplyBaselineScript = Join-Path $PSScriptRoot 'Test-AgentMultiDaySupplyBaseline.ps1'
$videoLibrary = Join-Path $PSScriptRoot 'HarnessVideoCapture.ps1'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$saveDirectory = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\Game Saves'
$outerTemp = $env:CHRONICLE_HARNESS_TEMP
if (-not $outerTemp -or -not (Test-Path -LiteralPath $outerTemp -PathType Container)) { throw 'Fresh-Campaign recruitment fallback requires an active Run-Harness TestResults temp directory.' }
$evaluationRoot = Split-Path -Parent $outerTemp
$results = [System.Collections.Generic.List[object]]::new()
$videoEventTracePath = $null

function Get-SaveManifestHash {
    if (-not (Test-Path -LiteralPath $saveDirectory -PathType Container)) { return 'no-save-directory' }
    $entries = @(Get-ChildItem -LiteralPath $saveDirectory -File -Filter '*.sav' | Sort-Object Name | ForEach-Object {
        "$($_.Name)|$($_.Length)|$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)"
    })
    $bytes = [Text.Encoding]::UTF8.GetBytes($entries -join "`n")
    $sha = [Security.Cryptography.SHA256]::Create()
    try { [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '') } finally { $sha.Dispose() }
}

function Invoke-FallbackCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 15) {
    $output = & $HarnessPowerShell -NoProfile -File $cli $Action @Arguments -TimeoutSeconds $CommandTimeout -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Native fallback CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Native fallback CLI '$Action' returned invalid JSON: $output" }
}

function Write-FallbackCaptureEvent($Capture, [string]$EventName, [string]$Action, [string]$CommandId, $Observation, $Receipt) {
    if (-not $Capture) { return }
    $now = [DateTimeOffset]::UtcNow
    $started = [DateTimeOffset]::Parse([string]$Capture.StartedUtc).ToUniversalTime()
    $state = if ($Observation -and $Observation.state) { $Observation.state } else { $null }
    $context = if ($state -and $state.context) { $state.context } else { $null }
    $event = [ordered]@{
        event = $EventName
        utc = $now.ToString('O')
        offsetMilliseconds = [Math]::Round(($now - $started).TotalMilliseconds,2)
        commandId = $CommandId
        action = $Action
        decisionAction = ''
        gameState = if ($context) { [string]$context.gameState } else { $null }
        menuId = if ($context) { [string]$context.menuId } else { $null }
        partyScreenMode = if ($state -and $state.partyScreen) { [string]$state.partyScreen.mode } else { $null }
        inventoryMode = if ($state -and $state.inventoryScreen) { [string]$state.inventoryScreen.mode } else { $null }
        campaignDay = if ($Receipt) { $Receipt.campaignDay } elseif ($Observation) { $Observation.campaignDay } else { $null }
    }
    Add-Content -LiteralPath $videoEventTracePath -Value ($event | ConvertTo-Json -Compress -Depth 6) -Encoding UTF8
}

function Get-SafeVisibleSettlementTargets($MapTargets, [string[]]$Visited) {
    @($MapTargets.data.mapSettlementTargets |
        Where-Object { $_.type -in @('town','castle','village') -and -not $_.hostile -and -not $_.underSiege -and [string]$_.id -notin $Visited } |
        Sort-Object { [double]$_.distance }, { [string]$_.id })
}

function Wait-FallbackSettlementArrival([string]$SettlementId, [string]$Prefix) {
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $state = Invoke-FallbackCli 'state' @('-CommandId', "$Prefix-arrival-$([Guid]::NewGuid().ToString('N'))") 20
        if ([string]$state.state.location.currentSettlementId -ceq $SettlementId -and [string]$state.state.context.menuId -in @('town','town_backstreet','village')) { return $state }
        if ([bool]$state.state.context.encounterActive) { throw "Native encounter '$($state.state.context.encounteredPartyId)' interrupted movement to '$SettlementId'." }
        if (-not [bool]$state.state.party.isMoving) { throw "Native movement stopped before reaching '$SettlementId'; no Harness clock control was used." }
        if ([string]$state.state.context.timeControlMode -notin @('StoppablePlay','UnstoppableFastForward')) { throw "Campaign time stopped en route to '$SettlementId'." }
        Start-Sleep -Seconds 1
    }
    throw "Native move to '$SettlementId' timed out without Harness clock control."
}

function Write-FallbackEvent($Capture, [string]$EventName, [string]$Action, [string]$CommandId, $Observation, $Receipt) {
    if (-not $Capture) { return }
    $now = [DateTimeOffset]::UtcNow
    $started = [DateTimeOffset]::Parse([string]$Capture.StartedUtc).ToUniversalTime()
    $state = if ($Observation -and $Observation.state) { $Observation.state } else { $null }
    $context = if ($state -and $state.context) { $state.context } else { $null }
    $event = [ordered]@{
        event = $EventName
        utc = $now.ToString('O')
        offsetMilliseconds = [Math]::Round(($now - $started).TotalMilliseconds,2)
        commandId = $CommandId
        action = $Action
        decisionAction = ''
        gameState = if ($context) { [string]$context.gameState } else { $null }
        menuId = if ($context) { [string]$context.menuId } else { $null }
        partyScreenMode = if ($state -and $state.partyScreen) { [string]$state.partyScreen.mode } else { $null }
        inventoryMode = if ($state -and $state.inventoryScreen) { [string]$state.inventoryScreen.mode } else { $null }
        campaignDay = if ($Receipt) { $Receipt.campaignDay } elseif ($Observation) { $Observation.campaignDay } else { $null }
    }
    Add-Content -LiteralPath $script:VideoEventTracePath -Value ($event | ConvertTo-Json -Compress -Depth 6) -Encoding UTF8
}

function Get-CurrentNativeLeaveOption($Observation) {
    @($Observation.state.availableMenuOptions | Where-Object { $_.available -and $_.enabled -and $_.isLeave } | Select-Object -First 1)
}

function Invoke-FreshCampaignFallbackAttempt([int]$AttemptNumber) {
    $attemptDirectory = Join-Path $evaluationRoot ('RecruitmentFallbackAttempt-' + $AttemptNumber.ToString('00'))
    $attemptTemp = Join-Path $attemptDirectory 'Temp'
    New-Item -ItemType Directory -Path $attemptTemp -Force | Out-Null
    $previousTemp = $env:CHRONICLE_HARNESS_TEMP
    $env:CHRONICLE_HARNESS_TEMP = $attemptTemp
    $freshResult = $null
    $baselineResult = $null
    $saveName = $null
    $savePath = $null
    $saveHashBefore = $null
    $preparedSaveHash = $null
    $saveHashAfter = $null
    $loadedCampaignInstanceId = ''
    $capture = $null
    $captureResult = $null
    $script:VideoEventTracePath = $null
    $campaignInstanceId = ''
    $fallbackTriggered = $false
    $fallbackResolved = $false
    $partyPrepared = $false
    $marketTownReached = $false
    $preparedMarketTownId = ''
    $visitedSettlements = [System.Collections.Generic.List[string]]::new()
    $settlementVisits = [System.Collections.Generic.List[object]]::new()
    $failure = $null
    $classification = 'harness-failure'
    $routeCampaignDaysElapsed = $null
    $routeGoldStart = $null
    $routeFoodStart = $null
    $routePartyStart = $null
    $videoName = 'recruitment-fallback-' + [Guid]::NewGuid().ToString('N')
    $testStartedUtc = [DateTime]::UtcNow.ToString('O')
    $processStopped = $false
    $sessionAbsent = $false
    $ownedSaveRemoved = $false
    $fixtureHashUnchanged = $false
    try {
        if (Get-Process -Name Bannerlord* -ErrorAction SilentlyContinue) { throw 'A Bannerlord client was present before this fallback attempt.' }
        if (Test-Path -LiteralPath $sessionPath -PathType Leaf) { throw 'A pre-existing Agent session must not be overwritten.' }
        $freshOutput = & $HarnessPowerShell -NoProfile -File $freshCampaignScript -ValidateRecruitmentProgression -RetainDisposableSave -TimeoutSeconds $TimeoutSeconds 2>&1 | Out-String
        try { $freshResult = $freshOutput | ConvertFrom-Json } catch { throw "Fresh Campaign child returned no structured receipt: $freshOutput" }
        $saveName = [string]$freshResult.DisposableSaveName
        if ($freshResult.DisposableSavePath) { $savePath = [IO.Path]::GetFullPath([string]$freshResult.DisposableSavePath) }
        $gameSaveRoot = [IO.Path]::GetFullPath($saveDirectory).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        if ($LASTEXITCODE -ne 0 -or -not [bool]$freshResult.Passed -or -not [bool]$freshResult.DisposableSaveRetained) { throw "Fresh New Campaign did not provide a verified disposable save: $($freshResult.RecruitmentProgressionError)" }
        if ([string]::IsNullOrWhiteSpace($saveName) -or -not $savePath.StartsWith($gameSaveRoot,[StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $savePath -PathType Leaf)) { throw 'Fresh Campaign disposable save escaped Game Saves or is missing.' }
        $saveHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
        $campaignInstanceId = [string]$freshResult.ChronicleCampaignInstanceId

        $prefix = 'fallback-' + $AttemptNumber.ToString('00') + '-' + [Guid]::NewGuid().ToString('N')
        $load = Invoke-FallbackCli 'load' @('-SaveName', $saveName, '-CommandId', "$prefix-load") $TimeoutSeconds
        if ($load.status -ne 'completed' -or -not [int]$load.session.processId) { throw 'Native fallback fixture failed to load.' }
        $loadedIdentity = Invoke-FallbackCli 'agentCheckpointGet' @('-CommandId', "$prefix-loaded-campaign-identity")
        if ($loadedIdentity.status -ne 'completed' -or [string]::IsNullOrWhiteSpace([string]$loadedIdentity.data.campaignInstanceId)) { throw 'Native fallback fixture did not expose a Campaign runtime identity.' }
        $loadedCampaignInstanceId = [string]$loadedIdentity.data.campaignInstanceId
        . $videoLibrary
        $videoPath = Join-Path $attemptTemp "$videoName.mp4"
        $contactPath = Join-Path $attemptTemp "$videoName-contact.jpg"
        $script:VideoEventTracePath = Join-Path $attemptTemp "$videoName-events.jsonl"
        Set-Content -LiteralPath $script:VideoEventTracePath -Value '' -Encoding UTF8
        $capture = Start-ChronicleWindowVideoCapture -ProcessId ([int]$load.session.processId) -OutputPath $videoPath -FrameRate $FrameRate

        $startObservation = Invoke-FallbackCli 'state' @('-CommandId', "$prefix-initial-state")
        if ($startObservation.state.context.gameState -ne 'MapState' -or $startObservation.state.context.encounterActive) { throw 'Recruitment fallback must begin on an unobstructed Campaign Map.' }
        $routeCampaignDayStart = [double]$startObservation.campaignDay
        $routeGoldStart = [int]$startObservation.state.economy.gold
        $routeFoodStart = [double]$startObservation.state.party.food
        $routePartyStart = [int]$startObservation.state.party.members
        Write-FallbackEvent $capture 'capture-start' 'capture' $null $startObservation $null

        $initialMapTargets = Invoke-FallbackCli 'mapSettlementTargets' @('-CommandId', "$prefix-map-targets-initial")
        $initialCandidates = @(Get-SafeVisibleSettlementTargets $initialMapTargets @())
        if ($initialMapTargets.status -ne 'completed' -or $initialCandidates.Count -eq 0) { throw 'No currently visible safe town/castle/village target exists for native recruitment fallback.' }
        $initialTown = @($startObservation.state.nearbySettlements | Where-Object { $_.type -eq 'town' -and -not $_.hostile -and -not $_.underSiege } | Sort-Object { [double]$_.distance } | Select-Object -First 1)
        $firstTownTargetId = if ($initialTown.Count -eq 1 -and $initialCandidates.id -contains [string]$initialTown[0].id) { [string]$initialTown[0].id } else { [string]$initialCandidates[0].id }
        $partyState = $startObservation
        $currentSettlement = $null
        $firstCandidateId = $null
        $firstCandidateName = $null
        $nativeSlotShortageCount = 0
        $routeStep = 0

        while ([int]$partyState.state.party.members -lt 6) {
            $isAtRecruitmentMenu = [string]$partyState.state.context.gameState -eq 'MapState' -and
                [string]$partyState.state.context.menuId -in @('town','town_backstreet','village') -and
                -not [string]::IsNullOrWhiteSpace([string]$partyState.state.location.currentSettlementId)
            if (-not $isAtRecruitmentMenu) {
                $freshTargets = Invoke-FallbackCli 'mapSettlementTargets' @('-CommandId', "$prefix-map-targets-$routeStep")
                $candidates = @(Get-SafeVisibleSettlementTargets $freshTargets $visitedSettlements.ToArray())
                if ($candidates.Count -eq 0) {
                    $classification = if ($fallbackTriggered) { 'fallback-route-exhausted-no-safe-visible-candidates' } else { 'native-recruitment-sufficient-at-no-town-yet-unavailable' }
                    break
                }
                $target = $candidates[0]
                if ($routeStep -eq 0) {
                    $preferredTown = @($candidates | Where-Object { [string]$_.id -ceq $firstTownTargetId } | Select-Object -First 1)
                    if ($preferredTown.Count -eq 1) { $target = $preferredTown[0] }
                }
                $visitedSettlements.Add([string]$target.id) | Out-Null
                if (-not $firstCandidateId) { $firstCandidateId = [string]$target.id; $firstCandidateName = [string]$target.name }
                $moveId = "$prefix-move-$routeStep"
                $move = Invoke-FallbackCli 'move' @('-SettlementId', [string]$target.id, '-CommandId', $moveId) $TimeoutSeconds
                Write-FallbackEvent $capture 'native-action' 'move' $moveId $partyState $move
                if ($move.status -ne 'completed' -or [string]$move.state.location.targetSettlementId -cne [string]$target.id) { throw "Native move did not accept currently visible settlement '$($target.id)'." }
                $arrival = Wait-FallbackSettlementArrival -SettlementId ([string]$target.id) -Prefix "$prefix-$routeStep"
                Write-FallbackEvent $capture 'settlement-arrived' 'state' "$prefix-arrival-$routeStep" $arrival $null
                $partyState = $arrival
                $currentSettlement = $target
            }
            else {
                $settlementId = [string]$partyState.state.location.currentSettlementId
                $lookup = Invoke-FallbackCli 'mapSettlementTargets' @('-CommandId', "$prefix-current-target-$routeStep")
                $currentSettlement = @($lookup.data.mapSettlementTargets | Where-Object { [string]$_.id -ceq $settlementId } | Select-Object -First 1)
                if ($currentSettlement.Count -eq 0) { throw 'Current native recruitment settlement did not match the current visible map target list.' }
                $currentSettlement = $currentSettlement[0]
                if (-not $firstCandidateId) { $firstCandidateId = [string]$currentSettlement.id; $firstCandidateName = [string]$currentSettlement.name }
            }

            $recruitMenuOption = @($partyState.state.availableMenuOptions | Where-Object { $_.id -eq 'recruit_volunteers' -and $_.available -and $_.enabled } | Select-Object -First 1)
            if ($recruitMenuOption.Count -eq 0) {
                $nativeSlotShortageCount++
                Write-FallbackEvent $capture 'native-precondition' 'menu' "$prefix-no-recruit-menu-$routeStep" $partyState $null
                $settlementVisits.Add([ordered]@{ Settlement = $currentSettlement; PartyBefore = [int]$partyState.state.party.members; AvailableOfferCount = 0; NativeOffers = @(); ActiveRecruitmentMenu = $false })
            }
            else {
                $offerQueryCount = 0
                $lastNativeOffers = @()
                while ([int]$partyState.state.party.members -lt 6) {
                    $offerReceipt = Invoke-FallbackCli 'recruitOptions' @('-CommandId', "$prefix-offers-$routeStep-$offerQueryCount")
                    if ($offerReceipt.status -ne 'completed') { throw "Native RecruitmentVM options failed in '$($currentSettlement.id)'." }
                    $offerQueryCount++
                    $lastNativeOffers = @($offerReceipt.data.offers | ForEach-Object { [ordered]@{ ownerId=$_.ownerId; ownerName=$_.ownerName; troopId=$_.troopId; slot=$_.slot; cost=$_.cost; wage=$_.wage; available=$_.available } })
                    Write-FallbackEvent $capture 'native-observation' 'recruitOptions' "$prefix-offers-$routeStep-$($offerQueryCount - 1)" $partyState $offerReceipt
                    $affordableOffers = @($offerReceipt.data.offers | Where-Object { $_.available -and [int]$_.cost -le [int]$partyState.state.economy.gold } | Sort-Object { [int]$_.cost },{ [int]$_.slot })
                    if ($affordableOffers.Count -eq 0) {
                        $nativeSlotShortageCount++
                        Write-FallbackEvent $capture 'native-precondition' 'recruitOptions' "$prefix-offers-$routeStep-$($offerQueryCount - 1)" $partyState $offerReceipt
                        break
                    }
                    $offer = $affordableOffers[0]
                    $beforePartySize = [int]$partyState.state.party.members
                    $beforeGold = [int]$partyState.state.economy.gold
                    $recruitId = "$prefix-recruit-$routeStep-$beforePartySize"
                    $recruit = Invoke-FallbackCli 'recruit' @('-OwnerId', [string]$offer.ownerId, '-TroopId', [string]$offer.troopId, '-VolunteerSlot', [string]$offer.slot, '-CommandId', $recruitId) $TimeoutSeconds
                    $partyState = Invoke-FallbackCli 'state' @('-CommandId', "$recruitId-postcondition")
                    if ($recruit.status -ne 'completed' -or -not [bool]$recruit.data.verified -or [int]$partyState.state.party.members -ne ($beforePartySize + 1) -or [int]$partyState.state.economy.gold -ne ($beforeGold - [int]$offer.cost)) { throw 'Native recruit receipt did not match Party/Gold postconditions.' }
                    Write-FallbackEvent $capture 'native-action' 'recruit' $recruitId $partyState $recruit
                }
                $settlementVisits.Add([ordered]@{ Settlement = $currentSettlement; PartyAfter = [int]$partyState.state.party.members; OfferQueries = $offerQueryCount; LastNativeOffers = $lastNativeOffers; ActiveRecruitmentMenu = $true })
            }

            if ([int]$partyState.state.party.members -ge 6) {
                $partyPrepared = $true
                $fallbackResolved = $fallbackTriggered
                break
            }

            if ([string]$partyState.state.context.menuId -in @('town','town_backstreet','village')) {
                if ([string]$currentSettlement.id -ceq $firstCandidateId) { $fallbackTriggered = $nativeSlotShortageCount -gt 0 }
                $leaveOption = @(Get-CurrentNativeLeaveOption $partyState)
                if ($leaveOption.Count -ne 1) { throw "Could not safely leave Native settlement '$($currentSettlement.id)' to inspect the next visible fallback." }
                $leaveId = "$prefix-leave-$routeStep"
                $leave = Invoke-FallbackCli 'menuSelect' @('-MenuId', [string]$partyState.state.context.menuId, '-OptionId', [string]$leaveOption[0].id, '-CommandId', $leaveId)
                $partyState = Invoke-FallbackCli 'state' @('-CommandId', "$leaveId-postcondition")
                Write-FallbackEvent $capture 'native-action' 'menuSelect' $leaveId $partyState $leave
                if ($leave.status -ne 'completed' -or $partyState.state.context.menuId) { throw 'Native settlement leave did not return to Campaign Map for fallback search.' }
            }
            $routeStep++
            if ($routeStep -gt 64) { throw 'Native settlement fallback exceeded the 64-observation transition cap.' }
        }

        if (-not $fallbackTriggered) { $classification = if ($partyPrepared) { 'initial-settlement-sufficient-no-fallback-needed' } else { 'initial-settlement-sufficient-slots-not-exhausted' } }
        elseif (-not $partyPrepared) { $classification = 'native-visible-safe-route-exhausted-before-six-members' }
        if ($partyPrepared -and [string]$partyState.state.context.menuId -eq 'town') {
            $marketTownReached = $true
            $preparedMarketTownId = [string]$partyState.state.location.currentSettlementId
        }
        elseif ($partyPrepared) {
            $leaveOption = @(Get-CurrentNativeLeaveOption $partyState)
            if ($leaveOption.Count -eq 1) {
                $leaveId = "$prefix-leave-for-market"
                $leave = Invoke-FallbackCli 'menuSelect' @('-MenuId', [string]$partyState.state.context.menuId, '-OptionId', [string]$leaveOption[0].id, '-CommandId', $leaveId)
                $partyState = Invoke-FallbackCli 'state' @('-CommandId', "$leaveId-map")
                Write-FallbackEvent $capture 'native-action' 'menuSelect' $leaveId $partyState $leave
                if ($leave.status -ne 'completed' -or $partyState.state.context.menuId -or $partyState.state.context.encounterActive) { throw 'Native settlement leave did not return to an unobstructed Campaign Map before town routing.' }
            }
            $marketTargets = Invoke-FallbackCli 'mapSettlementTargets' @('-CommandId', "$prefix-market-towns")
            $marketTown = @($marketTargets.data.mapSettlementTargets | Where-Object { $_.type -eq 'town' -and -not $_.hostile -and -not $_.underSiege } | Sort-Object { [double]$_.distance } | Select-Object -First 1)
            if ($marketTargets.status -ne 'completed' -or $marketTown.Count -ne 1) { throw 'No currently visible safe Native Town market target was available after recruiting six members.' }
            $moveId = "$prefix-move-market-town"
            $move = Invoke-FallbackCli 'move' @('-SettlementId', [string]$marketTown[0].id, '-CommandId', $moveId) $TimeoutSeconds
            Write-FallbackEvent $capture 'native-action' 'move' $moveId $partyState $move
            if ($move.status -eq 'completed' -and [string]$move.state.location.targetSettlementId -ceq [string]$marketTown[0].id) {
                $partyState = Wait-FallbackSettlementArrival -SettlementId ([string]$marketTown[0].id) -Prefix "$prefix-market-town"
                $marketTownReached = ([string]$partyState.state.context.menuId -eq 'town' -and [string]$partyState.state.location.currentSettlementId -ceq [string]$marketTown[0].id)
                if ($marketTownReached) { $preparedMarketTownId = [string]$marketTown[0].id }
            }
            if (-not $marketTownReached) { $classification = 'six-members-reached-without-current-market-town' }
        }

        if ($fallbackTriggered -and $partyPrepared -and $marketTownReached) {
            if ([string]$partyState.state.context.menuId -ne 'town' -or [string]$partyState.state.location.currentSettlementId -ne [string]$marketTown[0].id) { throw 'Prepared supply fixture must be at the exact Native Town market menu before the Campaign Map checkpoint.' }
            $leaveOption = @(Get-CurrentNativeLeaveOption $partyState)
            if ($leaveOption.Count -ne 1) { throw 'Native Town did not expose a unique enabled leave option before the paired-test checkpoint save.' }
            $leaveId = "$prefix-leave-prepared-town"
            $leave = Invoke-FallbackCli 'menuSelect' @('-MenuId', [string]$partyState.state.context.menuId, '-OptionId', [string]$leaveOption[0].id, '-CommandId', $leaveId)
            $partyState = Invoke-FallbackCli 'state' @('-CommandId', "$leaveId-prepared-map")
            Write-FallbackEvent $capture 'native-action' 'menuSelect' $leaveId $partyState $leave
            if ($leave.status -ne 'completed' -or [string]$partyState.state.context.gameState -ne 'MapState' -or $partyState.state.context.menuId -or $partyState.state.context.encounterActive) { throw 'Prepared Town exit did not return to an unobstructed Campaign Map before the Native checkpoint save.' }
            $saveReceipt = Invoke-FallbackCli 'save' @('-SaveName', $saveName, '-CommandId', "$prefix-save-prepared-campaign") $TimeoutSeconds
            if ($saveReceipt.status -ne 'completed') { throw 'Native save did not persist the prepared disposable recruitment route.' }
            $saveHashBeforeBaseline = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
            $preparedSaveHash = $saveHashBeforeBaseline
            Write-FallbackEvent $capture 'native-action' 'save' "$prefix-save-prepared-campaign" $partyState $saveReceipt
            $classification = 'fallback-reached-six-and-market-town'
        }
        Write-FallbackEvent $capture 'capture-end' 'capture' $null $partyState $null
        if ($capture) {
            $captureResult = Stop-ChronicleWindowVideoCapture -Capture $capture -ContactSheetPath $contactPath -EventTracePath $script:VideoEventTracePath
            $capture = $null
        }
        if (-not $captureResult -or [double]$captureResult.FrameCoverageRatio -lt 0.9 -or -not [bool]$captureResult.VideoRemovedAfterEvidence) { throw 'Fallback-route video did not produce indexed evidence with at least 90% coverage and successful MP4 cleanup.' }
        if (Get-Process -Id ([int]$load.session.processId) -ErrorAction SilentlyContinue) {
            $stop = Invoke-FallbackCli 'stop' @('-CommandId', "$prefix-stop") 30
            if ($stop.status -ne 'completed' -or -not $stop.processStopped) { throw 'Native fallback preparation process did not stop cleanly.' }
        }
        $processStopped = -not [bool](Get-Process -Name Bannerlord* -ErrorAction SilentlyContinue)
        if (-not $processStopped) { throw 'Bannerlord process remained after fallback preparation.' }

        if ($fallbackTriggered -and $partyPrepared -and $marketTownReached) {
            $baselineOutput = & $HarnessPowerShell -NoProfile -File $supplyBaselineScript -LoadSaveName $saveName -TimeoutSeconds $TimeoutSeconds -RestDays 3 -TargetPartyMembers 6 -ProvisionAmount 1 -RestWallClockLimitSeconds $RestWallClockLimitSeconds -Repetitions 1 -CaptureVisualEvidence -StartAtCurrentTown -FrameRate $FrameRate 2>&1 | Out-String
            try { $baselineResult = $baselineOutput | ConvertFrom-Json } catch { throw "Prepared fallback Campaign returned no paired Native supply result: $baselineOutput" }
            $baselineExitCode = $LASTEXITCODE
            if ($baselineExitCode -ne 0 -or -not [bool]$baselineResult.Passed) { throw "Prepared fallback Campaign could not complete its paired Native supply comparison: $($baselineResult.Failure)" }
            $saveHashAfterBaseline = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
            $saveHashAfter = $saveHashAfterBaseline
            if ($saveHashBeforeBaseline -cne $saveHashAfterBaseline -or -not [bool]$baselineResult.FixtureUnchanged) { throw 'Prepared fallback Campaign source save hash changed during its paired supply branches.' }
        }
    }
    catch {
        $failure = $_.Exception.ToString()
        if ($classification -eq 'harness-failure' -and $fallbackTriggered) { $classification = 'fallback-route-interrupted-or-unusable' }
        elseif ($classification -eq 'harness-failure' -and $freshResult -and $freshResult.Passed) { $classification = 'native-fallback-test-failed' }
    }
    finally {
        if ($capture) {
            try {
                $fallbackEnd = [ordered]@{ event='capture-end'; utc=[DateTimeOffset]::UtcNow.ToString('O'); offsetMilliseconds=0; commandId=$null; action='capture'; decisionAction=''; gameState=$null; menuId=$null; partyScreenMode=$null; inventoryMode=$null; campaignDay=$null }
                if ($videoEventTracePath) { Add-Content -LiteralPath $videoEventTracePath -Value ($fallbackEnd|ConvertTo-Json -Compress) -Encoding UTF8 }
                $null=Stop-ChronicleWindowVideoCapture -Capture $capture -ContactSheetPath $contactPath -EventTracePath $videoEventTracePath
            } catch { }
        }
        if (Test-Path -LiteralPath $sessionPath -PathType Leaf) { try { Invoke-FallbackCli 'stop' @('-CommandId', ('fallback-cleanup-' + [Guid]::NewGuid().ToString('N'))) 20|Out-Null } catch { } }
        $processStopped = -not [bool](Get-Process -Name Bannerlord* -ErrorAction SilentlyContinue)
        $sessionAbsent = -not (Test-Path -LiteralPath $sessionPath -PathType Leaf)
        if ($savePath -and (Test-Path -LiteralPath $savePath -PathType Leaf)) {
            try {
                $saveRoot = [IO.Path]::GetFullPath($saveDirectory).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
                if (-not [IO.Path]::GetFullPath($savePath).StartsWith($saveRoot,[StringComparison]::OrdinalIgnoreCase) -or -not $saveName.StartsWith('ChronicleP5Fresh-',[StringComparison]::Ordinal)) { throw 'Refusing to remove a prepared save outside the exact owned temporary scope.' }
                Get-ChildItem -LiteralPath $saveDirectory -File -Filter "$saveName*"|Remove-Item -Force
                $ownedSaveRemoved = -not (Test-Path -LiteralPath $savePath -PathType Leaf)
            } catch { $failure = if ($failure) { "$failure; temporary save cleanup failed: $($_.Exception.Message)" } else { "temporary save cleanup failed: $($_.Exception.Message)" } }
        }
        $env:CHRONICLE_HARNESS_TEMP = $previousTemp
        if ($freshResult) { $freshResult|ConvertTo-Json -Depth 18|Set-Content -LiteralPath (Join-Path $attemptDirectory 'FreshCampaignFixture.json') -Encoding UTF8 }
        if ($baselineResult) { $baselineResult|ConvertTo-Json -Depth 18|Set-Content -LiteralPath (Join-Path $attemptDirectory 'PairedSupplyBaseline.json') -Encoding UTF8 }
        if (-not $processStopped -or -not $sessionAbsent -or -not $ownedSaveRemoved) { if (-not $failure) { $failure='A game/Agent process, session, or owned disposable save was not cleanly removed.' } }
    }

    $completed = $null -eq $failure -and $processStopped -and $sessionAbsent -and $ownedSaveRemoved
    [pscustomobject]@{
        Attempt = $AttemptNumber
        Completed = $completed
        Failure = $failure
        Classification = $classification
        CampaignInstanceId = $campaignInstanceId
        LoadedRuntimeCampaignInstanceId = $loadedCampaignInstanceId
        CampaignSeed = 'unknown; Chronicle Campaign instance identity is not the Native RNG seed'
        InitialParty = $routePartyStart
        InitialGold = $routeGoldStart
        InitialFood = $routeFoodStart
        FirstSettlementId = $firstCandidateId
        FirstSettlementName = $firstCandidateName
        PartyPreparedToSix = $partyPrepared
        FirstSettlementRecruitmentShortageObserved = $fallbackTriggered
        NativeRecruitmentOfferExhaustions = $nativeSlotShortageCount
        RouteVisits = @($settlementVisits)
        VisitedSettlementIds = $visitedSettlements.ToArray()
        RouteCampaignDaysElapsed = if ($null -ne $routeCampaignDayStart -and $partyState) { [Math]::Round([double]$partyState.campaignDay - [double]$routeCampaignDayStart,6) } else { $null }
        PreparedMarketTownId = $preparedMarketTownId
        RouteCapture = $captureResult
        SupplyBaseline = if ($baselineResult) { [ordered]@{ Passed=$baselineResult.Passed; FixtureUnchanged=$baselineResult.FixtureUnchanged; Scenarios=$baselineResult.Scenarios; PairedComparisons=$baselineResult.PairedComparisons } } else { $null }
        DisposableSaveName = $saveName
        FreshCampaignSaveHash = $saveHashBefore
        PreparedCampaignSaveHash = $preparedSaveHash
        DisposableSaveHashBeforeBaseline = $saveHashBeforeBaseline
        DisposableSaveHashAfterBaseline = $saveHashAfterBaseline
        FinalDisposableSaveHash = $saveHashAfter
        DisposableSaveRemoved = $ownedSaveRemoved
        ProcessStopped = $processStopped
        AgentSessionAbsent = $sessionAbsent
    }
}

$sourceSaveManifestHash = Get-SaveManifestHash
for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    if (Get-Process -Name Bannerlord* -ErrorAction SilentlyContinue) { throw "Fallback attempt $attempt found a game process left by the preceding run." }
    if (Test-Path -LiteralPath $sessionPath -PathType Leaf) { throw "Fallback attempt $attempt found a pre-existing Agent session." }
    $attemptResult = Invoke-FreshCampaignFallbackAttempt -AttemptNumber $attempt
    $attemptResult | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $evaluationRoot ('RecruitmentFallbackAttempt-' + $attempt.ToString('00') + '\RecruitmentFallbackAttempt.json')) -Encoding UTF8
    $results.Add($attemptResult)
    if (-not $attemptResult.Completed) { break }
    if ([bool]$attemptResult.FirstSettlementRecruitmentShortageObserved) { break }
}

$saveManifestUnchanged = (Get-SaveManifestHash) -ceq $sourceSaveManifestHash
$campaignIds = @($results | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.CampaignInstanceId) } | ForEach-Object { [string]$_.CampaignInstanceId } | Select-Object -Unique)
$shortageAttempt = @($results | Where-Object { $_.FirstSettlementRecruitmentShortageObserved } | Select-Object -First 1)
$routeValidated = [bool]($shortageAttempt.Count -eq 1 -and $shortageAttempt[0].Classification -eq 'fallback-reached-six-and-market-town' -and $shortageAttempt[0].SupplyBaseline -and $shortageAttempt[0].SupplyBaseline.Passed)
$routeExhausted = [bool]($shortageAttempt.Count -eq 1 -and $shortageAttempt[0].Classification -eq 'native-visible-safe-route-exhausted-before-six-members')
$notReproduced = ($shortageAttempt.Count -eq 0 -and $results.Count -eq $MaxAttempts -and @($results | Where-Object { $_.Classification -ne 'initial-settlement-sufficient-no-fallback-needed' }).Count -eq 0)
$outcome = if ($routeValidated) { 'fallback-verified-with-native-paired-supply-baseline' } elseif ($routeExhausted) { 'shortage-reproduced-no-safe-visible-native-recruitment-route-found' } elseif ($notReproduced) { 'recruitment-shortage-not-reproduced-within-attempt-cap' } elseif ($shortageAttempt.Count -eq 1) { 'shortage-reproduced-but-fallback-test-incomplete' } else { 'harness-or-campaign-creation-failure' }
$allAttemptsCompleted = (@($results | Where-Object { -not $_.Completed }).Count -eq 0)
$result = [ordered]@{
    ProviderKind = 'deterministic Native fresh-Campaign recruitment fallback evaluation; not a real-model result'
    Scenario = 'up to ten independent Bannerlord 1.4.8 New Campaign instances; stop after the first nearest safe Town volunteer-slot shortage is either repaired through current visible safe settlement targets or classified unrecoverable within the observed set'
    MaxAttempts = $MaxAttempts
    AttemptsRun = $results.Count
    DistinctCampaignInstances = $campaignIds.Count
    CampaignRngSeedExposure = 'unknown; Chronicle Campaign instance IDs are not represented as Native RNG seeds'
    RecruitmentShortagesObserved = @($results | Where-Object { $_.FirstSettlementRecruitmentShortageObserved }).Count
    FallbackRouteValidated = $routeValidated
    Outcome = $outcome
    AllAttemptCleanupPassed = $allAttemptsCompleted
    SourceSaveManifestUnchanged = $saveManifestUnchanged
    ProcessesStopped = (@($results | Where-Object { -not $_.ProcessStopped }).Count -eq 0)
    AgentSessionsAbsent = (@($results | Where-Object { -not $_.AgentSessionAbsent }).Count -eq 0)
    Passed = ($allAttemptsCompleted -and $campaignIds.Count -eq $results.Count -and $saveManifestUnchanged -and $outcome -in @('fallback-verified-with-native-paired-supply-baseline','shortage-reproduced-no-safe-visible-native-recruitment-route-found','recruitment-shortage-not-reproduced-within-attempt-cap'))
    Results = @($results)
}
$json = $result | ConvertTo-Json -Depth 24
Set-Content -LiteralPath (Join-Path $outerTemp 'FreshCampaignRecruitmentFallback.json') -Value $json -Encoding UTF8
$json
if (-not $result.Passed) { exit 1 }
