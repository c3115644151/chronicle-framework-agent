[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$DecisionProviderPath,
    [int]$MaxDecisions = 1,
    [int]$TimeoutSeconds = 180,
    [ValidateRange(0,3600)][int]$MaxElapsedSeconds = 0,
    [string]$CommandPrefix = 'loop',
    [string]$Goal,
    [string]$CompletionContractJson,
    [string]$CompletionContractBase64,
    [string]$ProviderBudgetBase64,
    [string[]]$AllowedActionNames,
    [switch]$PersistCheckpoint,
    [switch]$ResumeCheckpoint,
    [ValidateSet('recruit')][string]$HarnessCrashAfterAction,
    [switch]$HarnessPrepareSafePassageAfterMove
)

$ErrorActionPreference = 'Stop'
$decisionLoopPolicyPath = Join-Path $PSScriptRoot 'Agent-DecisionLoopPolicy.ps1'
. $decisionLoopPolicyPath
$providerBudgetPolicyPath = Join-Path $PSScriptRoot 'Agent-ProviderBudget.ps1'
. $providerBudgetPolicyPath
$cliPath = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$providerPath = (Resolve-Path -LiteralPath $DecisionProviderPath).Path
if ($MaxDecisions -lt 1 -or $MaxDecisions -gt 400) { throw 'MaxDecisions must be between 1 and 400.' }

$script:ProductAllowedActions = @{
    state = @(); closeEscapeMenu = @(); respondInquiry = @('InquiryToken','InquiryChoice'); respondMultiSelectionInquiry = @('InquiryToken','InquiryChoice','SelectedIds'); mapSettlementTargets = @(); mapNotifications = @(); quickInformation = @(); sceneNotification = @(); mapPartyTargets = @(); mapPartyComposition = @('PartyId'); mapPartyBehavior = @('PartyId'); partyUpgradeOptions = @(); upgradeTroop = @('TroopId','UpgradeTargetIndex'); prisonerRecruitmentOptions = @(); recruitPrisoner = @('TroopId','ConfirmPartySizeWarning','ConfirmPrisonerLimitWarning'); characterDevelopment = @(); spendSkillFocus = @('SkillId','Count'); questDetails = @('QuestId'); partyRoster = @(); partyRoles = @(); setPartyRole = @('RoleId','HeroId'); unassignPartyRole = @('RoleId'); inventoryOpen = @(); heroEquipmentOptions = @(); equipHeroItem = @('ItemViewModelId','EquipmentIndex'); unequipHeroItem = @('EquipmentIndex'); inventoryConfirm = @(); inventoryCancel = @(); inventoryCancelChanges = @(); pause = @(); resume = @(); fastForward = @(); move = @('SettlementId'); moveToPoint = @('X','Y','Surface'); missionSceneAgents = @(); missionInput = @('X','Y','DurationSeconds'); missionNavigateToAgent = @('AgentIndex','DurationSeconds'); missionLeave = @(); missionInteract = @('AgentIndex'); missionCancelNavigation = @(); missionAimAt = @('AgentIndex');
    pursue = @('PartyId'); follow = @('PartyId'); hold = @(); menu = @(); menuSelect = @('OptionId'); talkToSettlementHero = @('HeroId'); visitSettlementHero = @('HeroId'); dialogueSelect = @('OptionId'); dialogueContinue = @();
    battlePause = @(); battleSkip = @(); battleFinish = @(); battleRetreat = @(); missionRetreat = @();
    partyTakeAll = @('LootType'); partyLootTransferOne = @('TroopId','LootType'); partyScreenDone = @(); questTroopTransfer = @('TroopId','QuestTroopSourceSide'); questTroopScreenDone = @(); questTroopScreenCancel = @(); inventoryTakeAll = @(); inventoryDone = @();
    rest = @('Days'); recruitOptions = @(); recruit = @('OwnerId','TroopId','VolunteerSlot','ConfirmPartySizeWarning');
    foodOptions = @(); tradeOptions = @(); tradeRumors = @('ItemViewModelId','InventorySide'); trade = @('Direction','ItemViewModelId','InventorySide','Amount'); provision = @('ItemViewModelId','Amount'); tradeConfirm = @(); tradeCancel = @(); tradeCancelChanges = @(); barterOptions = @(); barterEdit = @('BarterCandidateId','BarterOperation','Amount'); barterReset = @(); barterAutoBalance = @(); barterOffer = @(); barterCancel = @()
}
$script:ProductAllowedActions['persuasionDetails'] = @()
$script:ProductAllowedActions['alleyRosterTransfer'] = @('TroopId','RosterSide')
$script:ProductAllowedActions['alleyRosterCancel'] = @()
$script:AllowedActions = $script:ProductAllowedActions
if ($PSBoundParameters.ContainsKey('AllowedActionNames')) {
    $requestedActionNames = @($AllowedActionNames | ForEach-Object { ([string]$_).Split(',') } | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($requestedActionNames.Count -eq 0) { throw 'AllowedActionNames cannot be empty when supplied.' }
    $restrictedActions = @{}
    foreach ($requestedActionName in $requestedActionNames) {
        $canonicalName = @($script:ProductAllowedActions.Keys | Where-Object { $_ -ceq [string]$requestedActionName })
        if ($canonicalName.Count -ne 1) { throw "Requested action '$requestedActionName' is not in the product allowlist." }
        $restrictedActions[$canonicalName[0]] = $script:ProductAllowedActions[$canonicalName[0]]
    }
    $script:AllowedActions = $restrictedActions
}
if ($HarnessPrepareSafePassageAfterMove -and
    ($env:CHRONICLE_HARNESS_MODE -ne 'visual-capture' -or [string]::IsNullOrWhiteSpace($env:CHRONICLE_HARNESS_TEMP) -or -not $script:AllowedActions.ContainsKey('move'))) {
    throw 'HarnessPrepareSafePassageAfterMove is restricted to a visual Harness run whose decision allowlist includes Native move.'
}
if ($HarnessCrashAfterAction -and (-not $PersistCheckpoint -or $env:CHRONICLE_HARNESS_MODE -ne 'visual-capture' -or -not $env:CHRONICLE_HARNESS_TEMP)) {
    throw 'HarnessCrashAfterAction requires PersistCheckpoint plus an active visual-capture Harness run.'
}

function Invoke-AgentCli {
    param([string]$Action, [hashtable]$Arguments = @{}, [string]$CommandId, [switch]$ReturnWhenAccepted)
    $cliArguments = @($Action, '-CommandId', $CommandId, '-TimeoutSeconds', [string]$TimeoutSeconds, '-AsJson')
    if ($ReturnWhenAccepted) { $cliArguments += '-ReturnWhenAccepted' }
    foreach ($key in $Arguments.Keys) {
        if ($key -eq 'ConfirmPartySizeWarning') {
            if ([bool]$Arguments[$key]) { $cliArguments += '-ConfirmPartySizeWarning' }
            continue
        }
        $cliArguments += "-$key"
        $cliArguments += [string]$Arguments[$key]
    }
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cliPath @cliArguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

function Get-SafeProviderErrorSummary([string]$ProviderStderr, [int]$ExitCode) {
    if ($ProviderStderr -match 'Model provider HTTP request failed with status (\d{3})') { return "Provider HTTP status $($Matches[1]); response body omitted." }
    if ($ProviderStderr -match 'Model provider request timed out after (\d+) seconds') { return "Provider timed out after $($Matches[1]) seconds; request delivery is unknown." }
    if ($ProviderStderr -match 'Model provider request failed with WebException \(status=([A-Za-z]+); host=([A-Za-z0-9.:-]+); attempt=([0-9/]+);') { return "Provider connection failure status=$($Matches[1]), host=$($Matches[2]), attempt=$($Matches[3])." }
    return "Provider process exited with code $ExitCode; stderr details omitted."
}

function Invoke-DecisionProvider {
    param([string]$RequestJson)
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = (Get-Command powershell.exe -ErrorAction Stop).Source
    $startInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$providerPath`""
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) { throw 'Could not start the decision provider.' }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.StandardInput.WriteLine($RequestJson)
    $process.StandardInput.Close()
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try { $process.Kill() } catch { }
        if ($script:AgentProviderBudget) {
            return [ordered]@{ providerFailed = $true; failureKind = 'provider-timeout'; providerUsage = [ordered]@{ status = 'unavailable'; requestAttempts = $null; requestAttemptsStatus = 'unknown'; requestBodyBytes = $null; httpRequestSent = 'unknown'; usageReason = 'Provider timed out; the request may have reached the endpoint.' } }
        }
        throw "Decision provider timed out after $TimeoutSeconds seconds."
    }
    $stdout = $stdoutTask.Result.Trim()
    $stderr = $stderrTask.Result.Trim()
    if ($process.ExitCode -ne 0) {
        if ($script:AgentProviderBudget) {
            return [ordered]@{ providerFailed = $true; failureKind = 'provider-process-failed'; providerExitCode = [int]$process.ExitCode; providerErrorSummary = Get-SafeProviderErrorSummary -ProviderStderr $stderr -ExitCode ([int]$process.ExitCode); providerUsage = [ordered]@{ status = 'unavailable'; requestAttempts = $null; requestAttemptsStatus = 'unknown'; requestBodyBytes = $null; httpRequestSent = 'unknown'; usageReason = 'Provider exited without usage metadata; worst-case request reservation remains charged.' } }
        }
        throw "Decision provider exited $($process.ExitCode): $stderr"
    }
    try { return $stdout | ConvertFrom-Json }
    catch { throw "Decision provider returned invalid JSON: $stdout $stderr" }
}

function Get-DecisionHistoryValue($InputObject, [string]$Name) {
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) { return $InputObject[$Name] }
        return $null
    }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function Get-RecentDecisionHistory([object[]]$Trace, [int]$MaxEntries = 8) {
    $history = [System.Collections.Generic.List[object]]::new()
    foreach ($step in @($Trace | Select-Object -Last $MaxEntries)) {
        $decision = $step.decision
        if (-not $decision) { continue }
        $decisionRejected = [bool](Get-DecisionHistoryValue $decision 'decisionRejected')
        $decisionAction = if ($decisionRejected) { [string](Get-DecisionHistoryValue $decision 'requestedAction') } else { [string](Get-DecisionHistoryValue $decision 'action') }
        $arguments = Get-DecisionHistoryValue $decision 'arguments'
        if ($null -eq $arguments) { $arguments = [ordered]@{} }
        $receipt = $step.actionReceipt
        $control = $step.control
        $history.Add([ordered]@{
            iteration = [int]$step.iteration
            action = $decisionAction
            arguments = $arguments
            decisionRejected = $decisionRejected
            rejectionReason = if ($decisionRejected) { [string](Get-DecisionHistoryValue $decision 'reason') } else { $null }
            nativeOutcome = [ordered]@{
                action = if ($receipt) { [string](Get-DecisionHistoryValue $receipt 'action') } else { $null }
                status = if ($receipt) { [string](Get-DecisionHistoryValue $receipt 'status') } elseif ($control) { [string](Get-DecisionHistoryValue $control 'kind') } else { 'not-dispatched' }
                actionExecuted = [bool]$step.actionExecuted
                noNativeActionSent = [bool](Get-DecisionHistoryValue $receipt 'noNativeActionSent')
            }
        })
    }
    return @($history)
}

function ConvertTo-AsciiJson([string]$Json) {
    $builder = New-Object System.Text.StringBuilder
    foreach ($character in $Json.ToCharArray()) {
        if ([int]$character -gt 127) { [void]$builder.AppendFormat('\u{0:X4}', [int]$character) }
        else { [void]$builder.Append($character) }
    }
    return $builder.ToString()
}

function Get-EffectiveActionCatalog($Observation, $PreviousActionReceipt, $DecisionFeedback) {
    $catalog = @{}
    foreach ($entry in $script:AllowedActions.GetEnumerator()) { $catalog[$entry.Key] = @($entry.Value) }
    $state = if ($Observation) { $Observation.state } else { $null }
    $unobstructedCampaignMap = ($state -and (Test-UnobstructedCampaignMap $state))
    if ($catalog.ContainsKey('menuSelect')) {
        $currentMenuActive = (
            $state -and [string]$state.context.gameState -ceq 'MapState' -and
            -not [string]::IsNullOrWhiteSpace([string]$state.context.menuId) -and
            @($state.availableMenuOptions).Count -gt 0
        )
        if (-not $currentMenuActive) { $catalog.Remove('menuSelect') }
        else { $catalog['menuSelect'] = @('OptionId') }
    }
    if ($catalog.ContainsKey('rest')) {
        $nativeRestGate = Get-NativeRestActionGate -State $state -PreviousActionReceipt $PreviousActionReceipt
        foreach ($restActionName in $nativeRestGate.HideActions) { $catalog.Remove([string]$restActionName) }
    }
    $tradeActionsPresent = @($catalog.Keys | Where-Object { $_ -in @('foodOptions','tradeOptions','tradeRumors','trade','provision','tradeConfirm','tradeCancel','tradeCancelChanges') }).Count -gt 0
    if ($tradeActionsPresent) {
        $tradeActionGate = Get-TradeActionGate -State $state -PreviousActionReceipt $PreviousActionReceipt
        foreach ($tradeActionName in $tradeActionGate.HideActions) { $catalog.Remove([string]$tradeActionName) }
    }
    if (-not $unobstructedCampaignMap) {
        foreach ($mapMovementAction in @('move','moveToPoint','pursue','follow','hold')) { $catalog.Remove($mapMovementAction) }
    }
    # During a hostile encounter, expose the active conversation/barter route rather than map target queries.
    if ($state -and [bool]$state.context.encounterActive) { $catalog.Remove('mapSettlementTargets') }
    if ($catalog.ContainsKey('recruitOptions') -or $catalog.ContainsKey('recruit')) {
        $settlementMenuActive = (
            [string]$state.context.gameState -ceq 'MapState' -and
            -not [string]::IsNullOrWhiteSpace([string]$state.location.currentSettlementId) -and
            [string]$state.context.menuId -in @('town','town_backstreet','village') -and
            @($state.availableMenuOptions | Where-Object { $_.id -ceq 'recruit_volunteers' -and $_.available -and $_.enabled }).Count -eq 1
        )
        if (-not $settlementMenuActive) {
            $catalog.Remove('recruitOptions')
            $catalog.Remove('recruit')
        }
        elseif ($catalog.ContainsKey('recruit')) {
            $hasCurrentOfferReceipt = (
                [string]$PreviousActionReceipt.action -ceq 'recruitOptions' -and
                [string]$PreviousActionReceipt.status -ceq 'completed' -and
                [string]$PreviousActionReceipt.data.settlementId -ceq [string]$state.location.currentSettlementId -and
                [int]$state.party.members -lt [int]$state.party.sizeLimit -and
                @($PreviousActionReceipt.data.offers | Where-Object { $_.available -and [int]$_.cost -le [int]$state.economy.gold }).Count -gt 0
            )
            if (-not $hasCurrentOfferReceipt) { $catalog.Remove('recruit') }
        }
    }
    if ($catalog.ContainsKey('dialogueSelect') -or $catalog.ContainsKey('dialogueContinue')) {
        $conversation = if ($state) { $state.context.conversation } else { $null }
        $clickableDialogueOptions = if ($conversation) { @($conversation.options | Where-Object { $_.clickable }) } else { @() }
        if ($catalog.ContainsKey('dialogueSelect') -and $clickableDialogueOptions.Count -eq 0) { $catalog.Remove('dialogueSelect') }
        if ($catalog.ContainsKey('dialogueContinue') -and (-not $conversation -or $clickableDialogueOptions.Count -gt 0)) { $catalog.Remove('dialogueContinue') }
        $encounteredPartyIsObservedBandit = @($state.nearbyParties | Where-Object { [string]$_.id -ceq [string]$state.context.encounteredPartyId -and [string]$_.type -ceq 'bandit' }).Count -eq 1
        $banditWaitingForBarterProbe = (
            [bool]$state.context.encounterActive -and [string]$state.context.menuId -ceq 'encounter_meeting' -and
            $encounteredPartyIsObservedBandit -and $conversation -and $clickableDialogueOptions.Count -eq 0 -and $catalog.ContainsKey('barterOptions')
        )
        $nativeBarterProbeWasRejected = (
            ([string]$DecisionFeedback.kind -ceq 'native-action-rejected' -and [string]$DecisionFeedback.requestedAction -ceq 'barterOptions') -or
            ([string]$DecisionFeedback.priorFeedback.kind -ceq 'native-action-rejected' -and [string]$DecisionFeedback.priorFeedback.requestedAction -ceq 'barterOptions')
        )
        $nativeSafePassageOfferAccepted = (
            $PreviousActionReceipt -and [string]$PreviousActionReceipt.action -ceq 'barterOffer' -and
            [string]$PreviousActionReceipt.status -ceq 'completed' -and [bool]$PreviousActionReceipt.data.accepted
        )
        if ($banditWaitingForBarterProbe) {
            if ($nativeBarterProbeWasRejected -or $nativeSafePassageOfferAccepted) { $catalog.Remove('barterOptions') }
            else { $catalog.Remove('dialogueContinue') }
        }
    }
    $barterMutationRequested = $false
    foreach ($barterActionName in @('barterEdit','barterReset','barterAutoBalance','barterOffer','barterCancel')) {
        if ($catalog.ContainsKey($barterActionName)) { $barterMutationRequested = $true; break }
    }
    if ($barterMutationRequested) {
        $barterOptions = $null
        if ($PreviousActionReceipt -and [string]$PreviousActionReceipt.status -ceq 'completed') {
            if ([string]$PreviousActionReceipt.action -ceq 'barterOptions') { $barterOptions = $PreviousActionReceipt.data }
            elseif ($PreviousActionReceipt.data.updatedOptions) { $barterOptions = $PreviousActionReceipt.data.updatedOptions }
        }
        $barterActionGate = Get-BarterActionGate -BarterOptions $barterOptions -PreviousActionReceipt $PreviousActionReceipt -BalancedBarterSessionId $script:BalancedBarterSessionId
        if (-not $barterActionGate.SessionAvailable) {
            foreach ($name in @('barterEdit','barterReset','barterAutoBalance','barterOffer','barterCancel')) { $catalog.Remove($name) }
        }
        else {
            foreach ($name in $barterActionGate.HideActions) { $catalog.Remove([string]$name) }
        }
    }
    return $catalog
}

function Convert-ReceiptForDecision($Receipt, $Observation) {
    $actionNames = @($script:AllowedActions.Keys | Sort-Object)
    if (($actionNames -join ',') -ceq 'foodOptions,menuSelect,provision,rest,tradeConfirm') {
        if (-not $Receipt) { return $null }
        return Convert-SupplyReceiptForDecision -Receipt $Receipt -Observation $Observation
    }
    if (-not $Receipt -or [string]$Receipt.action -cne 'recruitOptions' -or -not $Receipt.data) { return $Receipt }
    $hasCapacity = [int]$Observation.state.party.members -lt [int]$Observation.state.party.sizeLimit
    $safeOffers = @($Receipt.data.offers | Where-Object { $hasCapacity -and $_.available -and [int]$_.cost -le [int]$Observation.state.economy.gold } | ForEach-Object {
        [ordered]@{ ownerId = $_.ownerId; ownerName = $_.ownerName; troopId = $_.troopId; troopName = $_.troopName; slot = $_.slot; cost = $_.cost; wage = $_.wage; available = $_.available }
    })
    return [ordered]@{
        protocolVersion = $Receipt.protocolVersion
        commandId = $Receipt.commandId
        action = $Receipt.action
        status = $Receipt.status
        campaignDay = $Receipt.campaignDay
        state = $null
        data = [ordered]@{
            settlementId = $Receipt.data.settlementId
            gold = [int]$Observation.state.economy.gold
            partySize = [int]$Observation.state.party.members
            partyCapacity = [int]$Observation.state.party.sizeLimit
            partySizeWarningForOne = -not $hasCapacity
            offers = $safeOffers
            recruitOptionsSummary = [ordered]@{ includedCount = $safeOffers.Count; selectionPolicy = 'current Native offers that are available, affordable, and within current MainParty capacity' }
        }
    }
}

function Convert-ObservationForDecision($Observation) {
    $actionNames = @($script:AllowedActions.Keys | Sort-Object)
    $actionProfile = switch ($actionNames -join ',') {
        'mapSettlementTargets,move' { 'campaign-map-travel'; break }
        'mapSettlementTargets,move,recruit,recruitOptions' { 'campaign-settlement-recruitment'; break }
        'foodOptions,menuSelect,provision,rest,tradeConfirm' { 'campaign-multiday-supply'; break }
        default { $null }
    }
    if (-not $actionProfile -or -not $Observation.state) { return $Observation }
    if ($actionProfile -eq 'campaign-multiday-supply') { return Convert-SupplyObservationForDecision $Observation }
    $state = $Observation.state
    $party = $state.party
    $location = $state.location
    $context = $state.context
    return [ordered]@{
        protocolVersion = $Observation.protocolVersion
        commandId = $Observation.commandId
        action = $Observation.action
        status = $Observation.status
        campaignDay = $Observation.campaignDay
        dailyTickCount = $Observation.dailyTickCount
        timeControlMode = $Observation.timeControlMode
        modelView = $actionProfile
        state = [ordered]@{
            schemaVersion = $state.schemaVersion
            campaignDay = $state.campaignDay
            party = [ordered]@{
                id = $party.id
                members = $party.members
                sizeLimit = $party.sizeLimit
                healthy = $party.healthy
                wounded = $party.wounded
                prisoners = $party.prisoners
                speed = $party.speed
                food = $party.food
                isMoving = $party.isMoving
                defaultBehavior = $party.defaultBehavior
                isAtSea = $party.isAtSea
            }
            economy = if ($actionProfile -eq 'campaign-settlement-recruitment') { [ordered]@{ gold = $state.economy.gold } } else { $null }
            location = [ordered]@{
                x = $location.x
                y = $location.y
                currentSettlementId = $location.currentSettlementId
                targetSettlementId = $location.targetSettlementId
                targetPartyId = $location.targetPartyId
                targetPosition = $location.targetPosition
            }
            context = [ordered]@{
                gameState = $context.gameState
                timeControlMode = $context.timeControlMode
                menuId = $context.menuId
                encounterActive = $context.encounterActive
                isWaiting = $context.isWaiting
            }
            nearbySettlements = $state.nearbySettlements
            nearbyParties = @($state.nearbyParties | Where-Object { $_.hostile })
            danger = $state.danger
            availableMenuOptions = if ($actionProfile -eq 'campaign-settlement-recruitment') { @($state.availableMenuOptions | Where-Object { $_.id -eq 'recruit_volunteers' -or $_.isLeave }) } else { $null }
        }
    }
}

function ConvertTo-CheckpointReceipt($Receipt) {
    if (-not $Receipt -or [string]$Receipt.status -ne 'completed') { return $null }
    $stateSummary = $null
    if ($Receipt.state) {
        $stateSummary = [ordered]@{
            campaignDay = $Receipt.state.campaignDay
            location = $Receipt.state.location
            party = [ordered]@{
                id = $Receipt.state.party.id
                members = $Receipt.state.party.members
                healthy = $Receipt.state.party.healthy
                wounded = $Receipt.state.party.wounded
                prisoners = $Receipt.state.party.prisoners
                speed = $Receipt.state.party.speed
                isMoving = $Receipt.state.party.isMoving
                defaultBehavior = $Receipt.state.party.defaultBehavior
            }
            context = [ordered]@{
                gameState = $Receipt.state.context.gameState
                menuId = $Receipt.state.context.menuId
                timeControlMode = $Receipt.state.context.timeControlMode
                encounterActive = $Receipt.state.context.encounterActive
            }
        }
    }
    $dataSummary = $null
    if ($Receipt.action -eq 'recruitOptions' -and $Receipt.data) {
        $dataSummary = [ordered]@{
            settlementId = $Receipt.data.settlementId
            gold = $Receipt.data.gold
            partySize = $Receipt.data.partySize
            partyCapacity = $Receipt.data.partyCapacity
            offers = @($Receipt.data.offers | Where-Object { $_.available } | ForEach-Object { [ordered]@{ ownerId = $_.ownerId; ownerName = $_.ownerName; troopId = $_.troopId; troopName = $_.troopName; slot = $_.slot; cost = $_.cost; wage = $_.wage; available = $_.available } })
        }
    }
    return [ordered]@{
        protocolVersion = $Receipt.protocolVersion
        commandId = $Receipt.commandId
        action = $Receipt.action
        status = $Receipt.status
        campaignDay = $Receipt.campaignDay
        state = $stateSummary
        data = $dataSummary
    }
}

function Write-AgentCheckpoint([string]$CheckpointCommandId) {
    if (-not $script:AgentCheckpoint) { return }
    $script:AgentCheckpoint.schemaVersion = 2
    $script:AgentCheckpoint.providerName = [IO.Path]::GetFileName($providerPath)
    if ($script:AgentProviderBudget) {
        $script:AgentCheckpoint.providerBudgetProfile = $script:AgentProviderBudget
        $script:AgentCheckpoint.providerBudgetFingerprint = Get-AgentProviderBudgetFingerprint -Budget $script:AgentProviderBudget
        $script:AgentCheckpoint.providerBudgetState = $script:AgentProviderBudgetState
        Sync-AgentProviderBudgetLedger
    }
    else {
        $script:AgentCheckpoint.providerBudgetProfile = $null
        $script:AgentCheckpoint.providerBudgetFingerprint = $null
        $script:AgentCheckpoint.providerBudgetState = $null
    }
    $script:AgentCheckpoint.updatedUtc = [DateTime]::UtcNow.ToString('O')
    $checkpointJson = $script:AgentCheckpoint | ConvertTo-Json -Depth 16 -Compress
    if ($checkpointJson.Length -gt 60000) { throw 'Agent checkpoint exceeded the 60,000-character runtime limit.' }
    $checkpointBase64 = [Convert]::ToBase64String([Text.UTF8Encoding]::new($false).GetBytes($checkpointJson))
    $receipt = Invoke-AgentCli 'agentCheckpointSet' @{ CheckpointBase64 = $checkpointBase64 } $CheckpointCommandId
    if ($receipt.status -ne 'completed' -or [string]$receipt.data.campaignInstanceId -cne [string]$script:AgentCheckpoint.campaignInstanceId)
        { throw 'Native Campaign checkpoint write did not confirm the active Campaign identity.' }
}

function Initialize-AgentProviderBudgetLedger([string]$TaskId, [string]$CampaignInstanceId) {
    if (-not $script:AgentProviderBudget) { return }
    $script:AgentProviderBudgetTaskId = $TaskId
    $script:AgentProviderBudgetCampaignInstanceId = $CampaignInstanceId
    $script:AgentProviderBudgetLedgerPath = Get-AgentProviderBudgetLedgerPath -Root $script:AgentProviderBudgetLedgerRoot -TaskId $TaskId
    $script:AgentProviderBudgetState.taskId = $TaskId
    $existingLedger = Read-AgentProviderBudgetLedger -Path $script:AgentProviderBudgetLedgerPath -TaskId $TaskId -CampaignInstanceId $CampaignInstanceId -Budget $script:AgentProviderBudget
    if ($existingLedger) {
        $script:AgentProviderBudgetState = Merge-AgentProviderBudgetStates -CheckpointState $script:AgentProviderBudgetState -LedgerState $existingLedger.state -Budget $script:AgentProviderBudget
    }
    $script:AgentProviderBudgetState.taskId = $TaskId
    Write-AgentProviderBudgetLedger -Path $script:AgentProviderBudgetLedgerPath -TaskId $TaskId -CampaignInstanceId $CampaignInstanceId -Budget $script:AgentProviderBudget -State $script:AgentProviderBudgetState
}

function Sync-AgentProviderBudgetLedger {
    if (-not $script:AgentProviderBudget -or [string]::IsNullOrWhiteSpace([string]$script:AgentProviderBudgetLedgerPath)) { return }
    Write-AgentProviderBudgetLedger -Path $script:AgentProviderBudgetLedgerPath -TaskId $script:AgentProviderBudgetTaskId -CampaignInstanceId $script:AgentProviderBudgetCampaignInstanceId -Budget $script:AgentProviderBudget -State $script:AgentProviderBudgetState
}

function ConvertTo-CheckpointObservationSummary($Observation) {
    return [ordered]@{
        campaignDay = $Observation.campaignDay
        currentSettlementId = $Observation.state.location.currentSettlementId
        targetSettlementId = $Observation.state.location.targetSettlementId
        isMoving = $Observation.state.party.isMoving
        members = $Observation.state.party.members
        gold = $Observation.state.economy.gold
        menuId = $Observation.state.context.menuId
        gameState = $Observation.state.context.gameState
        encounterActive = $Observation.state.context.encounterActive
    }
}

function Get-AgentProviderBudgetSummary($State, $Budget) {
    if (-not $State -or -not $Budget) { return $null }
    $usageCoverage = if ($State.reservedProviderCalls -gt 0) { [Math]::Round([double]$State.usageReportedCalls / [double]$State.reservedProviderCalls, 4) } else { 0.0 }
    $costStatus = if ([string]$State.mode -eq 'token-only-local') { 'local-provider-no-api-price' } elseif ($State.usageUnavailableCalls -gt 0 -or $State.usagePartialCalls -gt 0) { 'partial; reserved upper bound remains authoritative' } elseif ($State.usageReportedCalls -gt 0) { 'provider usage priced at peak reservation rates; invoice may differ' } else { 'no provider request sent' }
    return [ordered]@{
        taskId = [string]$State.taskId
        budgetId = [string]$State.budgetId
        mode = [string]$State.mode
        currency = $State.currency
        maxEstimatedCost = $State.maxEstimatedCost
        priceProfileId = [string]$Budget.priceProfileId
        reservedProviderCalls = [int]$State.reservedProviderCalls
        maxProviderCalls = [int]$State.maxProviderCalls
        maxRequestBodyBytesPerCall = [int]$Budget.maxRequestBodyBytes
        reservedRequestBodyBytes = [long]$State.reservedRequestBodyBytes
        actualRequestBodyBytes = [long]$State.actualRequestBodyBytes
        maxInputTokensPerCall = [int]$Budget.maxInputTokensPerRequest
        reservedInputTokenUpperBound = [long]$State.reservedInputTokenUpperBound
        maxTotalInputTokens = [long]$Budget.maxTotalInputTokens
        maxOutputTokensPerCall = [int]$Budget.maxOutputTokensPerRequest
        reservedOutputTokens = [long]$State.reservedOutputTokens
        maxTotalOutputTokens = [long]$Budget.maxTotalOutputTokens
        reservedCostUpperBoundCny = if ([string]$State.mode -eq 'priced-provider') { [double]$State.reservedCostUpperBound } else { $null }
        actualEstimatedCostCny = if ([string]$State.mode -eq 'priced-provider' -and $State.usageReportedCalls -gt 0) { [double]$State.actualEstimatedCostCny } else { $null }
        estimatedInputCacheHitCostCny = if ([string]$State.mode -eq 'priced-provider' -and $State.usageReportedCalls -gt 0) { [double]$State.estimatedInputCacheHitCostCny } else { $null }
        estimatedInputCacheMissCostCny = if ([string]$State.mode -eq 'priced-provider' -and $State.usageReportedCalls -gt 0) { [double]$State.estimatedInputCacheMissCostCny } else { $null }
        estimatedOutputCostCny = if ([string]$State.mode -eq 'priced-provider' -and $State.usageReportedCalls -gt 0) { [double]$State.estimatedOutputCostCny } else { $null }
        actualEstimatedCostStatus = $costStatus
        promptTokensReported = [long]$State.promptTokensReported
        completionTokensReported = [long]$State.completionTokensReported
        cacheHitTokensReported = [long]$State.cacheHitTokensReported
        cacheMissTokensReported = [long]$State.cacheMissTokensReported
        usageReportedCalls = [int]$State.usageReportedCalls
        usagePartialCalls = [int]$State.usagePartialCalls
        usageUnavailableCalls = [int]$State.usageUnavailableCalls
        providerRetries = [int]$State.providerRetries
        requestAttemptsUnavailableCalls = [int]$State.requestAttemptsUnavailableCalls
        usageCoverage = $usageCoverage
    }
}

function Convert-DecisionToCli {
    param($Decision, $ActionCatalog, $Observation, $PreviousActionReceipt)
    if ($Decision.action -eq 'advance') { throw 'advance is a Harness-only deterministic time step and is unavailable to Agent decision providers.' }
    $allowed = $ActionCatalog
    if (-not $Decision) { throw 'Provider decision was empty.' }
    if ($Decision.action -notin $script:AllowedActions.Keys) { throw 'Decision action is not in the Agent CLI allowlist.' }
    if ($Decision.action -notin $allowed.Keys) { throw "Decision action '$($Decision.action)' is not currently available from the latest Native observation." }
    $arguments = @{}
    if ($Decision.arguments) {
        if ($Decision.arguments -is [Array]) {
            if ($Decision.arguments.Count -gt 0) { throw 'Decision arguments must be an object; non-empty arrays are not accepted.' }
        }
        else { foreach ($property in $Decision.arguments.PSObject.Properties) {
            if ([string]$Decision.action -ceq 'menuSelect' -and [string]$property.Name -ceq 'MenuId') { continue }
            if ($property.Name -notin $allowed[[string]$Decision.action]) { throw "Unexpected argument '$($property.Name)' for action '$($Decision.action)'." }
            $arguments[$property.Name] = $property.Value
        } }
    }
    foreach ($required in $allowed[[string]$Decision.action]) {
        if (-not $arguments.ContainsKey($required)) { throw "Missing '$required' for action '$($Decision.action)'." }
    }
    if ([string]$Decision.action -ceq 'recruit') {
        $currentMenuOption = @($Observation.state.availableMenuOptions | Where-Object { $_.id -ceq 'recruit_volunteers' -and $_.available -and $_.enabled })
        $currentOffer = @($PreviousActionReceipt.data.offers | Where-Object { $_.available -and [string]$_.ownerId -ceq [string]$arguments.OwnerId -and [string]$_.troopId -ceq [string]$arguments.TroopId -and [int]$_.slot -eq [int]$arguments.VolunteerSlot -and [int]$_.cost -le [int]$Observation.state.economy.gold } | Select-Object -First 1)
        $recruitContextCurrent = (
            [string]$Observation.state.context.gameState -ceq 'MapState' -and
            [string]$Observation.state.context.menuId -in @('town','town_backstreet','village') -and
            -not [string]::IsNullOrWhiteSpace([string]$Observation.state.location.currentSettlementId) -and
            [string]$PreviousActionReceipt.action -ceq 'recruitOptions' -and
            [string]$PreviousActionReceipt.data.settlementId -ceq [string]$Observation.state.location.currentSettlementId -and
            $currentMenuOption.Count -eq 1 -and $currentOffer.Count -eq 1 -and
            [int]$Observation.state.party.members -lt [int]$Observation.state.party.sizeLimit -and
            -not [bool]$arguments.ConfirmPartySizeWarning
        )
        if (-not $recruitContextCurrent) { throw "Decision action 'recruit' is not currently available from the latest Native observation or its current affordable offer receipt." }
    }
    if ([string]$Decision.action -ceq 'menuSelect') {
        $menuSelection = Get-CurrentMenuSelectionContext -Observation $Observation -OptionId ([string]$arguments.OptionId)
        if (-not $menuSelection.Allowed) { throw $menuSelection.Reason }
        $arguments.MenuId = $menuSelection.MenuId
    }
    return [pscustomobject]@{ Action = [string]$Decision.action; Arguments = $arguments }
}

try {
    $trace = @()
    $script:HarnessEvents = @()
    $script:BalancedBarterSessionId = $null
    $safePassageFixtureInjected = $false
    $loopRunId = [Guid]::NewGuid().ToString('N')
    $script:AgentCheckpoint = $null
    $loopStartedUtc = [DateTime]::UtcNow
    $observation = $null
    $script:AgentCompletionContract = $null
    $script:AgentProviderBudget = $null
    $script:AgentProviderBudgetState = $null
    $script:AgentProviderBudgetTaskId = $null
    $script:AgentProviderBudgetCampaignInstanceId = $null
    $script:AgentProviderBudgetLedgerPath = $null
    $script:AgentProviderBudgetLedgerRoot = if (-not [string]::IsNullOrWhiteSpace([string]$env:CHRONICLE_PROVIDER_BUDGET_LEDGER_ROOT)) {
        [IO.Path]::GetFullPath([string]$env:CHRONICLE_PROVIDER_BUDGET_LEDGER_ROOT)
    }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$env:CHRONICLE_HARNESS_TEMP)) {
        Join-Path ([IO.Path]::GetFullPath([string]$env:CHRONICLE_HARNESS_TEMP)) 'ProviderBudgetLedger'
    }
    else {
        Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'ChronicleFramework\ProviderBudgetLedger'
    }
    if (-not [string]::IsNullOrWhiteSpace($CompletionContractJson) -and -not [string]::IsNullOrWhiteSpace($CompletionContractBase64)) { throw 'Provide the Native completion contract as JSON or Base64, not both.' }
    $providedCompletionContractJson = $CompletionContractJson
    if (-not [string]::IsNullOrWhiteSpace($CompletionContractBase64)) {
        try { $providedCompletionContractJson = [Text.UTF8Encoding]::new($false, $true).GetString([Convert]::FromBase64String($CompletionContractBase64)) }
        catch { throw 'Completion contract Base64 is invalid.' }
    }
    if (-not [string]::IsNullOrWhiteSpace($providedCompletionContractJson)) {
        try { $script:AgentCompletionContract = $providedCompletionContractJson | ConvertFrom-Json -ErrorAction Stop }
        catch { throw 'Completion contract JSON is invalid.' }
    }
    if (-not [string]::IsNullOrWhiteSpace($ProviderBudgetBase64)) {
        try {
            $providerBudgetJson = [Text.UTF8Encoding]::new($false, $true).GetString([Convert]::FromBase64String($ProviderBudgetBase64))
            $script:AgentProviderBudget = $providerBudgetJson | ConvertFrom-Json -ErrorAction Stop
        }
        catch { throw 'Provider budget Base64/JSON is invalid.' }
    }
    if (-not $script:AgentProviderBudget -and [IO.Path]::GetFileName($providerPath) -ceq 'Agent-OpenAICompatibleProvider.ps1') {
        $script:AgentProviderBudget = New-AgentProviderBudget -ModelId ([string]$env:CHRONICLE_LLM_MODEL) -BaseUrl ([string]$env:CHRONICLE_LLM_BASE_URL)
    }
    $previousActionReceipt = $null
    $decisionFeedback = $null
    $consecutiveDecisionRejections = 0
    $initialObservationStartedUtc = [DateTime]::UtcNow.ToString('O')
    $observation = Invoke-AgentCli 'state' @{} "$CommandPrefix-observe-0"
    $initialObservationCompletedUtc = [DateTime]::UtcNow.ToString('O')
    $termination = [ordered]@{ reason = 'decision-budget-exhausted'; providerReason = $null; completedByProvider = $false; goalVerified = $false; completionContractId = if ($script:AgentCompletionContract) { [string]$script:AgentCompletionContract.contractId } else { $null } }
    if ($observation.status -ne 'completed' -or -not $observation.state) { throw 'Initial game observation was not completed.' }
    if ($script:AgentCompletionContract) { $null = Test-AgentGoalCompletion -Contract $script:AgentCompletionContract -Observation $observation -ValidateOnly }
    $providerBudgetState = $null
    $providerBudgetCostPerRequestCny = 0.0
    if ($script:AgentProviderBudget) {
        $null = Test-AgentProviderBudget -Budget $script:AgentProviderBudget
        $providerBudgetCostPerRequestCny = Get-AgentProviderRequestCostUpperBound -Budget $script:AgentProviderBudget
        $providerBudgetState = New-AgentProviderBudgetState -Budget $script:AgentProviderBudget
        $script:AgentProviderBudgetState = $providerBudgetState
    }
    if ($ResumeCheckpoint) {
        $checkpointRead = Invoke-AgentCli 'agentCheckpointGet' @{} "$CommandPrefix-checkpoint-read"
        if ($checkpointRead.status -ne 'completed' -or [string]::IsNullOrWhiteSpace([string]$checkpointRead.data.checkpointBase64))
            { throw 'No Campaign-saved Agent checkpoint is available to resume.' }
        try {
            $checkpointJson = [Text.UTF8Encoding]::new($false, $true).GetString([Convert]::FromBase64String([string]$checkpointRead.data.checkpointBase64))
            $script:AgentCheckpoint = $checkpointJson | ConvertFrom-Json -ErrorAction Stop
        }
        catch { throw 'Campaign Agent checkpoint is corrupt or unreadable; stopping before any provider call or Native action.' }
        if ([int]$script:AgentCheckpoint.schemaVersion -notin @(1,2))
            { throw "Campaign Agent checkpoint schema version '$($script:AgentCheckpoint.schemaVersion)' is unsupported; stopping before provider/actions." }
        if ([string]$script:AgentCheckpoint.campaignInstanceId -cne [string]$checkpointRead.data.campaignInstanceId)
            { throw 'Campaign Agent checkpoint belongs to a different Campaign instance; stopping before provider/actions.' }
        if ($script:AgentCheckpoint.providerBudgetProfile) {
            $savedBudget = $script:AgentCheckpoint.providerBudgetProfile
            $savedFingerprint = Get-AgentProviderBudgetFingerprint -Budget $savedBudget
            if ([string]$script:AgentCheckpoint.providerBudgetFingerprint -cne $savedFingerprint) { throw 'Saved provider budget profile fingerprint is invalid; refusing to resume with an unverified cost ceiling.' }
            if ($script:AgentProviderBudget -and (Get-AgentProviderBudgetFingerprint -Budget $script:AgentProviderBudget) -cne $savedFingerprint) { throw 'Resume provider budget differs from the saved task budget; refusing to reset or change its cumulative ceiling.' }
            if (-not $script:AgentProviderBudget) { $script:AgentProviderBudget = $savedBudget }
            if ([string]$script:AgentCheckpoint.providerName -and [string]$script:AgentCheckpoint.providerName -cne [IO.Path]::GetFileName($providerPath)) { throw 'Resume provider differs from the one bound to the saved budget; refusing to apply the wrong usage profile.' }
            if (-not $script:AgentCheckpoint.providerBudgetState) { throw 'Saved priced task checkpoint has no cumulative provider budget state; refusing to resume.' }
            $null = Test-AgentProviderBudgetState -State $script:AgentCheckpoint.providerBudgetState -Budget $script:AgentProviderBudget
            $providerBudgetState = $script:AgentCheckpoint.providerBudgetState
            $script:AgentProviderBudgetState = $providerBudgetState
            Initialize-AgentProviderBudgetLedger -TaskId ([string]$script:AgentCheckpoint.taskId) -CampaignInstanceId ([string]$script:AgentCheckpoint.campaignInstanceId)
            $providerBudgetState = $script:AgentProviderBudgetState
            if ($providerBudgetState.pendingProviderCall) {
                $providerBudgetState.usageUnavailableCalls = [int]$providerBudgetState.usageUnavailableCalls + 1
                $providerBudgetState.pendingProviderCall = $null
                Write-AgentCheckpoint "$CommandPrefix-checkpoint-recovered-uncertain-provider-call"
            }
        }
        elseif ($script:AgentProviderBudget) { throw 'This saved task predates cumulative provider budgeting; refusing to resume it with a fresh budget that could reset prior spend.' }
        if ([string]$script:AgentCheckpoint.status -notin @('active','provider-stopped'))
            { throw "Checkpoint status '$($script:AgentCheckpoint.status)' is not resumable." }
        $checkpointContract = $script:AgentCheckpoint.completionContract
        if ($checkpointContract) {
            if ($script:AgentCompletionContract) {
                $checkpointContractJson = $checkpointContract | ConvertTo-Json -Depth 12 -Compress
                $requestedContractJson = $script:AgentCompletionContract | ConvertTo-Json -Depth 12 -Compress
                if ($checkpointContractJson -cne $requestedContractJson) { throw 'A resume request cannot replace the Native completion contract stored in the Campaign checkpoint.' }
            }
            else { $script:AgentCompletionContract = $checkpointContract }
        }
        elseif ($script:AgentCompletionContract) { throw 'A resume request cannot add a completion contract to a Campaign checkpoint that was created without one.' }
        if ($script:AgentCompletionContract) { $termination.completionContractId = [string]$script:AgentCompletionContract.contractId }
        if ([string]::IsNullOrWhiteSpace([string]$script:AgentCheckpoint.goal)) { throw 'Campaign checkpoint has no resumable goal.' }
        if (-not [string]::IsNullOrWhiteSpace($Goal) -and [string]$Goal -cne [string]$script:AgentCheckpoint.goal)
            { throw 'A resume request cannot replace the goal stored in the Campaign checkpoint.' }
        $Goal = [string]$script:AgentCheckpoint.goal
        $previousActionReceipt = $script:AgentCheckpoint.lastActionReceipt
        if ($previousActionReceipt -and [string]$previousActionReceipt.action -ceq 'mapSettlementTargets') { $previousActionReceipt = $null }
        if ($script:AgentCheckpoint.pendingAction) {
            $pendingAction = $script:AgentCheckpoint.pendingAction
            if ([string]$pendingAction.action -cne 'recruit') { throw "Pending action '$($pendingAction.action)' has no implemented recovery verifier; refusing to replay it." }
            $beforeMembers = [int]$pendingAction.preActionSummary.members
            $beforeGold = [int]$pendingAction.preActionSummary.gold
            $expectedCost = [int]$pendingAction.expectedCost
            $effectConfirmed = ($expectedCost -gt 0 -and [int]$observation.state.party.members -eq [int]$pendingAction.expectedMembersAfter -and [int]$observation.state.economy.gold -eq [int]$pendingAction.expectedGoldAfter)
            if (-not $effectConfirmed) { throw 'Pending Native recruitment outcome is unknown in the fresh Campaign observation; refusing to repeat the non-idempotent action.' }
            $previousActionReceipt = [ordered]@{
                protocolVersion = 1
                commandId = [string]$pendingAction.commandId
                action = 'recruit'
                status = 'completed'
                campaignDay = $observation.campaignDay
                state = $observation.state
                data = [ordered]@{ verified = $true; recoveredAfterRuntimeInterruption = $true; ownerId = [string]$pendingAction.arguments.OwnerId; troopId = [string]$pendingAction.arguments.TroopId; slot = [int]$pendingAction.arguments.VolunteerSlot; cost = $expectedCost; beforeMembers = $beforeMembers; afterMembers = [int]$observation.state.party.members; beforeGold = $beforeGold; afterGold = [int]$observation.state.economy.gold }
            }
            $script:AgentCheckpoint.lastActionReceipt = ConvertTo-CheckpointReceipt $previousActionReceipt
            $script:AgentCheckpoint.pendingAction = $null
            $script:AgentCheckpoint.lastRecovery = [ordered]@{ action = 'recruit'; status = 'verified'; commandId = [string]$pendingAction.commandId; membersAfter = [int]$observation.state.party.members; goldAfter = [int]$observation.state.economy.gold; expectedCost = $expectedCost; verifiedAgainst = 'fresh Native Campaign observation'; recoveredUtc = [DateTime]::UtcNow.ToString('O') }
            $script:AgentCheckpoint.lastObservedSummary = ConvertTo-CheckpointObservationSummary $observation
            Write-AgentCheckpoint "$CommandPrefix-checkpoint-reconciled-recruit"
        }
    }
    elseif ($PersistCheckpoint) {
        if ([string]::IsNullOrWhiteSpace($Goal)) { throw 'PersistCheckpoint requires an explicit non-empty goal.' }
        $checkpointRead = Invoke-AgentCli 'agentCheckpointGet' @{} "$CommandPrefix-checkpoint-read"
        if ($checkpointRead.status -ne 'completed' -or [string]::IsNullOrWhiteSpace([string]$checkpointRead.data.campaignInstanceId))
            { throw 'The Native Campaign did not provide a checkpoint identity.' }
        if (-not [string]::IsNullOrWhiteSpace([string]$checkpointRead.data.checkpointBase64)) {
            $existingCheckpointJson = [Text.UTF8Encoding]::new($false, $true).GetString([Convert]::FromBase64String([string]$checkpointRead.data.checkpointBase64))
            $existingCheckpoint = $existingCheckpointJson | ConvertFrom-Json
            if ([string]$existingCheckpoint.status -in @('active','provider-stopped'))
                { throw 'An unfinished Campaign goal checkpoint already exists; resume it instead of overwriting it.' }
        }
        $script:AgentCheckpoint = [ordered]@{
            schemaVersion = 2
            campaignInstanceId = [string]$checkpointRead.data.campaignInstanceId
            taskId = [Guid]::NewGuid().ToString('N')
            providerName = [IO.Path]::GetFileName($providerPath)
            providerBudgetProfile = $script:AgentProviderBudget
            providerBudgetFingerprint = if ($script:AgentProviderBudget) { Get-AgentProviderBudgetFingerprint -Budget $script:AgentProviderBudget } else { $null }
            providerBudgetState = $script:AgentProviderBudgetState
            goal = $Goal
            status = 'active'
            lastActionReceipt = $null
            pendingAction = $null
            lastRecovery = $null
            lastObservedSummary = $null
            lastStopReason = $null
            completionContract = $script:AgentCompletionContract
            lastGoalVerification = $null
            updatedUtc = [DateTime]::UtcNow.ToString('O')
        }
        Initialize-AgentProviderBudgetLedger -TaskId ([string]$script:AgentCheckpoint.taskId) -CampaignInstanceId ([string]$script:AgentCheckpoint.campaignInstanceId)
        $providerBudgetState = $script:AgentProviderBudgetState
        Write-AgentCheckpoint "$CommandPrefix-checkpoint-start"
    }
    elseif (-not $script:AgentCheckpoint -and $script:AgentProviderBudget) {
        Initialize-AgentProviderBudgetLedger -TaskId $loopRunId -CampaignInstanceId ([string]$observation.campaignInstanceId)
        $providerBudgetState = $script:AgentProviderBudgetState
    }
    for ($index = 1; $index -le $MaxDecisions; $index++) {
        if ($ResumeCheckpoint -and $index -eq 1 -and $script:AgentCompletionContract) {
            $resumeVerification = Test-AgentGoalCompletion -Contract $script:AgentCompletionContract -Observation $observation
            if ($resumeVerification.Satisfied) {
                $verifiedUtc = [DateTime]::UtcNow.ToString('O')
                $trace += [pscustomobject]@{
                    iteration = 0
                    observationBefore = $observation
                    previousActionReceipt = $previousActionReceipt
                    allowedActions = @()
                    allowedControls = @()
                    decisionFeedback = $null
                    decision = $null
                    actionReceipt = [ordered]@{ status = 'goal-verified-on-resume'; noNativeActionSent = $true; goalVerification = $resumeVerification; verifiedUtc = $verifiedUtc }
                    observationAfter = $observation
                    actionAttempted = $false
                    actionExecuted = $false
                    control = [ordered]@{ kind = 'goal-already-satisfied-on-resume'; contractId = $resumeVerification.ContractId }
                }
                $script:AgentCheckpoint.status = 'verified-complete'
                $script:AgentCheckpoint.lastGoalVerification = [ordered]@{ status = 'satisfied'; contractId = $resumeVerification.ContractId; verifiedUtc = $verifiedUtc; source = 'fresh Native Campaign observation on checkpoint resume'; result = $resumeVerification }
                $script:AgentCheckpoint.lastStopReason = 'Native goal contract verified on resume.'
                Write-AgentCheckpoint "$CommandPrefix-checkpoint-verified-resume"
                $termination = [ordered]@{ reason = 'native-goal-verified-on-resume'; providerReason = $null; completedByProvider = $false; goalVerified = $true; completionContractId = $resumeVerification.ContractId }
                break
            }
            $decisionFeedback = [ordered]@{
                kind = if ($resumeVerification.Status -eq 'unknown') { 'goal-verification-unknown-after-resume' } else { 'goal-not-satisfied-after-resume' }
                contractId = $resumeVerification.ContractId
                missingConditions = @($resumeVerification.MissingConditions)
                unknownConditions = @($resumeVerification.UnknownConditions)
                noNativeActionSent = $true
                message = if ($resumeVerification.Status -eq 'unknown') { 'Fresh Native Campaign state does not contain every field required to verify this saved goal; do not claim completion.' } else { 'Fresh Native Campaign state does not yet meet these saved goal conditions; continue only through currently allowed actions.' }
            }
            $script:AgentCheckpoint.status = 'active'
            $script:AgentCheckpoint.lastGoalVerification = [ordered]@{ status = [string]$resumeVerification.Status; contractId = $resumeVerification.ContractId; verifiedUtc = [DateTime]::UtcNow.ToString('O'); source = 'fresh Native Campaign observation on checkpoint resume'; result = $resumeVerification }
            Write-AgentCheckpoint "$CommandPrefix-checkpoint-goal-unmet-on-resume"
        }
        if ($providerBudgetState) {
            $wouldExceed = (
                [int]$providerBudgetState.reservedProviderCalls -ge [int]$script:AgentProviderBudget.maxProviderCalls -or
                ([long]$providerBudgetState.reservedRequestBodyBytes + [long]$script:AgentProviderBudget.maxRequestBodyBytes) -gt [long]$script:AgentProviderBudget.maxTotalRequestBodyBytes -or
                ([long]$providerBudgetState.reservedInputTokenUpperBound + [long]$script:AgentProviderBudget.maxInputTokensPerRequest) -gt [long]$script:AgentProviderBudget.maxTotalInputTokens -or
                ([long]$providerBudgetState.reservedOutputTokens + [long]$script:AgentProviderBudget.maxOutputTokensPerRequest) -gt [long]$script:AgentProviderBudget.maxTotalOutputTokens -or
                ([string]$script:AgentProviderBudget.mode -eq 'priced-provider' -and ([double]$providerBudgetState.reservedCostUpperBound + $providerBudgetCostPerRequestCny) -gt [double]$script:AgentProviderBudget.maxEstimatedCost)
            )
            if ($wouldExceed) {
                $trace += [pscustomobject]@{
                    iteration = $index
                    observationBefore = $observation
                    previousActionReceipt = $previousActionReceipt
                    allowedActions = @()
                    allowedControls = @()
                    decisionFeedback = $decisionFeedback
                    decision = $null
                    timing = $null
                    actionReceipt = [ordered]@{ status = 'provider-budget-exhausted'; noProviderRequestSent = $true; campaignDay = $observation.campaignDay }
                    observationAfter = $observation
                    actionAttempted = $false
                    actionExecuted = $false
                    control = [ordered]@{ kind = 'provider-budget-exhausted-before-request'; budgetId = [string]$providerBudgetState.budgetId; reservedProviderCalls = [int]$providerBudgetState.reservedProviderCalls; reservedCostUpperBound = [double]$providerBudgetState.reservedCostUpperBound }
                }
                $termination = [ordered]@{ reason = 'provider-budget-exhausted'; providerReason = 'No budget remained for another fully reserved model request.'; completedByProvider = $false; goalVerified = $false; completionContractId = if ($script:AgentCompletionContract) { [string]$script:AgentCompletionContract.contractId } else { $null } }
                break
            }
            $providerBudgetState.reservedProviderCalls = [int]$providerBudgetState.reservedProviderCalls + 1
            $providerBudgetState.reservedRequestBodyBytes = [long]$providerBudgetState.reservedRequestBodyBytes + [long]$script:AgentProviderBudget.maxRequestBodyBytes
            $providerBudgetState.reservedInputTokenUpperBound = [long]$providerBudgetState.reservedInputTokenUpperBound + [long]$script:AgentProviderBudget.maxInputTokensPerRequest
            $providerBudgetState.reservedOutputTokens = [long]$providerBudgetState.reservedOutputTokens + [long]$script:AgentProviderBudget.maxOutputTokensPerRequest
            $providerBudgetState.reservedCostUpperBound = [Math]::Round(([double]$providerBudgetState.reservedCostUpperBound + $providerBudgetCostPerRequestCny), 8)
            $providerBudgetState.pendingProviderCall = [ordered]@{ iteration = $index; reservedUtc = [DateTime]::UtcNow.ToString('O'); costUpperBoundCny = $providerBudgetCostPerRequestCny }
            $script:AgentProviderBudgetState = $providerBudgetState
            if ($script:AgentCheckpoint) { Write-AgentCheckpoint "$CommandPrefix-checkpoint-provider-reserved-$index" }
            else { Sync-AgentProviderBudgetLedger }
        }
        if ($MaxElapsedSeconds -gt 0 -and ([DateTime]::UtcNow - $loopStartedUtc).TotalSeconds -ge $MaxElapsedSeconds)
            { throw "Agent decision loop exceeded its $MaxElapsedSeconds-second wall-clock budget." }
        $nativeMoveArrival = $null
        $decisionFeedbackBeforeStep = $decisionFeedback
        $actionCatalog = Get-EffectiveActionCatalog $observation $previousActionReceipt $decisionFeedback
        $controlCatalog = @(Get-EffectiveControlCatalog -Observation $observation -PreviousActionReceipt $previousActionReceipt)
        $arrivalActions = @($script:AllowedActions.Keys | Sort-Object)
        if (($arrivalActions -join ',') -ceq 'mapSettlementTargets,move' -and [string]$previousActionReceipt.action -ceq 'move') {
            $moveTargetId = [string]$previousActionReceipt.state.location.targetSettlementId
            $observedSettlementId = [string]$observation.state.location.currentSettlementId
            if (-not [string]::IsNullOrWhiteSpace($moveTargetId) -and $observedSettlementId -ceq $moveTargetId) {
                $nativeMoveArrival = [ordered]@{ targetSettlementId = $moveTargetId; currentSettlementId = $observedSettlementId; status = 'arrived'; evidence = 'current Native Campaign observation' }
            }
        }
        $request = [ordered]@{
            schemaVersion = 3
            runId = $loopRunId
            iteration = $index
            goal = $Goal
            recentDecisionHistory = @(Get-RecentDecisionHistory -Trace $trace)
            allowedActions = @($actionCatalog.GetEnumerator() | Sort-Object -Property Key | ForEach-Object { [ordered]@{ action = [string]$_.Key; arguments = @($_.Value) } })
            allowedControls = $controlCatalog
            nativeMoveArrival = $nativeMoveArrival
            completionContract = $script:AgentCompletionContract
            checkpointContext = if ($script:AgentCheckpoint) { [ordered]@{ schemaVersion = $script:AgentCheckpoint.schemaVersion; campaignInstanceId = $script:AgentCheckpoint.campaignInstanceId; taskId = $script:AgentCheckpoint.taskId; status = $script:AgentCheckpoint.status; lastObservedSummary = $script:AgentCheckpoint.lastObservedSummary; pendingAction = $script:AgentCheckpoint.pendingAction; lastRecovery = $script:AgentCheckpoint.lastRecovery } } else { $null }
            providerBudget = if ($script:AgentProviderBudget) { [ordered]@{ budgetId = [string]$script:AgentProviderBudget.budgetId; mode = [string]$script:AgentProviderBudget.mode; maxRequestBodyBytes = [int]$script:AgentProviderBudget.maxRequestBodyBytes; maxInputTokensPerRequest = [int]$script:AgentProviderBudget.maxInputTokensPerRequest; maxOutputTokensPerRequest = [int]$script:AgentProviderBudget.maxOutputTokensPerRequest } } else { $null }
            observation = (Convert-ObservationForDecision $observation)
            previousActionReceipt = (Convert-ReceiptForDecision $previousActionReceipt $observation)
            decisionFeedback = $decisionFeedback
        }
        $requestJson = ConvertTo-AsciiJson ($request | ConvertTo-Json -Depth 16 -Compress)
        $providerStartedUtc = [DateTime]::UtcNow.ToString('O')
        $providerStartedTicks = [Diagnostics.Stopwatch]::GetTimestamp()
        $stepTiming = [ordered]@{
            providerStartedUtc = $providerStartedUtc
            providerCompletedUtc = $null
            providerElapsedMilliseconds = $null
            actionStartedUtc = $null
            actionCompletedUtc = $null
            actionElapsedMilliseconds = $null
            observationStartedUtc = $null
            observationCompletedUtc = $null
            observationElapsedMilliseconds = $null
        }
        $script:LastLoopTiming = $stepTiming
        try { $decision = Invoke-DecisionProvider $requestJson }
        catch {
            if (-not $providerBudgetState) { throw }
            $decision = [ordered]@{
                providerFailed = $true
                failureKind = 'provider-process-failed'
                failureType = $_.Exception.GetType().Name
                providerUsage = [ordered]@{ status = 'unavailable'; requestAttempts = $null; requestAttemptsStatus = 'unknown'; requestBodyBytes = $null; httpRequestSent = 'unknown'; usageReason = 'Provider process failed before returning response usage.' }
            }
        }
        finally {
            $stepTiming.providerCompletedUtc = [DateTime]::UtcNow.ToString('O')
            $stepTiming.providerElapsedMilliseconds = [Math]::Round(([Diagnostics.Stopwatch]::GetTimestamp() - $providerStartedTicks) * 1000.0 / [Diagnostics.Stopwatch]::Frequency, 2)
        }
        if ($decision -and [bool]$decision.providerBudgetRejected) {
            if ($providerBudgetState) {
                $providerBudgetState.reservedProviderCalls = [Math]::Max(0, [int]$providerBudgetState.reservedProviderCalls - 1)
                $providerBudgetState.reservedRequestBodyBytes = [Math]::Max(0, [long]$providerBudgetState.reservedRequestBodyBytes - [long]$script:AgentProviderBudget.maxRequestBodyBytes)
                $providerBudgetState.reservedInputTokenUpperBound = [Math]::Max(0, [long]$providerBudgetState.reservedInputTokenUpperBound - [long]$script:AgentProviderBudget.maxInputTokensPerRequest)
                $providerBudgetState.reservedOutputTokens = [Math]::Max(0, [long]$providerBudgetState.reservedOutputTokens - [long]$script:AgentProviderBudget.maxOutputTokensPerRequest)
                $providerBudgetState.reservedCostUpperBound = [Math]::Max(0, [double]$providerBudgetState.reservedCostUpperBound - $providerBudgetCostPerRequestCny)
                $providerBudgetState.pendingProviderCall = $null
                $script:AgentProviderBudgetState = $providerBudgetState
                if ($script:AgentCheckpoint) { Write-AgentCheckpoint "$CommandPrefix-checkpoint-provider-rejected-$index" }
                else { Sync-AgentProviderBudgetLedger }
            }
            $trace += [pscustomobject]@{
                iteration = $index
                observationBefore = $observation
                previousActionReceipt = $previousActionReceipt
                allowedActions = @($actionCatalog.Keys | Sort-Object)
                allowedControls = $controlCatalog
                decisionFeedback = $decisionFeedbackBeforeStep
                decision = $decision
                timing = $stepTiming
                actionReceipt = [ordered]@{ status = 'provider-budget-rejected'; noProviderRequestSent = $true; providerUsage = $decision.providerUsage; reason = [string]$decision.reason; campaignDay = $observation.campaignDay }
                observationAfter = $observation
                actionAttempted = $false
                actionExecuted = $false
                control = [ordered]@{ kind = 'provider-budget-rejected-before-http'; budgetId = if ($script:AgentProviderBudget) { [string]$script:AgentProviderBudget.budgetId } else { $null } }
            }
            $termination = [ordered]@{ reason = 'provider-request-budget-exceeded'; providerReason = [string]$decision.reason; completedByProvider = $false; goalVerified = $false; completionContractId = if ($script:AgentCompletionContract) { [string]$script:AgentCompletionContract.contractId } else { $null } }
            break
        }
        if ($providerBudgetState) {
            $providerUsage = if ($decision) { $decision.providerUsage } else { $null }
            if ($providerUsage) {
                if ($null -eq $providerUsage.requestAttempts) { $providerBudgetState.requestAttemptsUnavailableCalls = [int]$providerBudgetState.requestAttemptsUnavailableCalls + 1 }
                else { $providerBudgetState.providerRetries = [int]$providerBudgetState.providerRetries + [Math]::Max(0, ([int]$providerUsage.requestAttempts - 1)) }
                if ($null -ne $providerUsage.requestBodyBytes) { $providerBudgetState.actualRequestBodyBytes = [long]$providerBudgetState.actualRequestBodyBytes + [long]$providerUsage.requestBodyBytes }
                switch ([string]$providerUsage.status) {
                    'reported' {
                        $providerBudgetState.usageReportedCalls = [int]$providerBudgetState.usageReportedCalls + 1
                        $providerBudgetState.promptTokensReported = [long]$providerBudgetState.promptTokensReported + [long]$providerUsage.promptTokens
                        $providerBudgetState.completionTokensReported = [long]$providerBudgetState.completionTokensReported + [long]$providerUsage.completionTokens
                        if ($null -ne $providerUsage.promptCacheHitTokens) { $providerBudgetState.cacheHitTokensReported = [long]$providerBudgetState.cacheHitTokensReported + [long]$providerUsage.promptCacheHitTokens }
                        if ($null -ne $providerUsage.promptCacheMissTokens) { $providerBudgetState.cacheMissTokensReported = [long]$providerBudgetState.cacheMissTokensReported + [long]$providerUsage.promptCacheMissTokens }
                        $actualRequestCost = Get-AgentProviderActualCostBreakdown -Budget $script:AgentProviderBudget -Usage $providerUsage
                        if ($null -ne $actualRequestCost) {
                            $providerBudgetState.actualEstimatedCostCny = [Math]::Round(([double]$providerBudgetState.actualEstimatedCostCny + [double]$actualRequestCost.totalCny), 8)
                            $providerBudgetState.estimatedInputCacheHitCostCny = [Math]::Round(([double]$providerBudgetState.estimatedInputCacheHitCostCny + [double]$actualRequestCost.inputCacheHitCny), 8)
                            $providerBudgetState.estimatedInputCacheMissCostCny = [Math]::Round(([double]$providerBudgetState.estimatedInputCacheMissCostCny + [double]$actualRequestCost.inputCacheMissCny), 8)
                            $providerBudgetState.estimatedOutputCostCny = [Math]::Round(([double]$providerBudgetState.estimatedOutputCostCny + [double]$actualRequestCost.outputCny), 8)
                        }
                    }
                    'partial' { $providerBudgetState.usagePartialCalls = [int]$providerBudgetState.usagePartialCalls + 1 }
                    default { $providerBudgetState.usageUnavailableCalls = [int]$providerBudgetState.usageUnavailableCalls + 1 }
                }
            }
            else {
                $providerBudgetState.usageUnavailableCalls = [int]$providerBudgetState.usageUnavailableCalls + 1
                $providerBudgetState.requestAttemptsUnavailableCalls = [int]$providerBudgetState.requestAttemptsUnavailableCalls + 1
            }
            $providerBudgetState.pendingProviderCall = $null
            $script:AgentProviderBudgetState = $providerBudgetState
            if ($script:AgentCheckpoint) { Write-AgentCheckpoint "$CommandPrefix-checkpoint-provider-receipt-$index" }
            else { Sync-AgentProviderBudgetLedger }
            $reportedUsageOverBudget = $false
            if ($providerUsage -and [string]$providerUsage.status -eq 'reported') {
                $reportedUsageOverBudget = (
                    [long]$providerUsage.promptTokens -gt [long]$script:AgentProviderBudget.maxInputTokensPerRequest -or
                    [long]$providerUsage.completionTokens -gt [long]$script:AgentProviderBudget.maxOutputTokensPerRequest -or
                    [long]$providerBudgetState.promptTokensReported -gt [long]$script:AgentProviderBudget.maxTotalInputTokens -or
                    [long]$providerBudgetState.completionTokensReported -gt [long]$script:AgentProviderBudget.maxTotalOutputTokens
                )
            }
            if ($reportedUsageOverBudget) {
                $trace += [pscustomobject]@{
                    iteration = $index
                    observationBefore = $observation
                    previousActionReceipt = $previousActionReceipt
                    allowedActions = @($actionCatalog.Keys | Sort-Object)
                    allowedControls = $controlCatalog
                    decisionFeedback = $decisionFeedbackBeforeStep
                    decision = $decision
                    timing = $stepTiming
                    actionReceipt = [ordered]@{ status = 'provider-usage-over-budget'; noNativeActionSent = $true; providerUsage = $providerUsage; campaignDay = $observation.campaignDay }
                    observationAfter = $observation
                    actionAttempted = $false
                    actionExecuted = $false
                    control = [ordered]@{ kind = 'reported-usage-exceeded-budget'; budgetId = [string]$providerBudgetState.budgetId }
                }
                $termination = [ordered]@{ reason = 'provider-reported-usage-exceeded-budget'; providerReason = 'Reported token usage exceeded a request or run ceiling; no Native action or next request was sent.'; completedByProvider = $false; goalVerified = $false; completionContractId = if ($script:AgentCompletionContract) { [string]$script:AgentCompletionContract.contractId } else { $null } }
                break
            }
            if ($decision -and [bool]$decision.providerFailed) {
                $trace += [pscustomobject]@{
                    iteration = $index
                    observationBefore = $observation
                    previousActionReceipt = $previousActionReceipt
                    allowedActions = @($actionCatalog.Keys | Sort-Object)
                    allowedControls = $controlCatalog
                    decisionFeedback = $decisionFeedbackBeforeStep
                    decision = $decision
                    timing = $stepTiming
                    actionReceipt = [ordered]@{ status = 'provider-failed'; noNativeActionSent = $true; providerUsage = $providerUsage; requestCostReservedCny = $providerBudgetCostPerRequestCny; campaignDay = $observation.campaignDay }
                    observationAfter = $observation
                    actionAttempted = $false
                    actionExecuted = $false
                    control = [ordered]@{ kind = 'provider-failed-no-native-action'; budgetId = $providerBudgetState.budgetId }
                }
                $termination = [ordered]@{ reason = 'provider-failed'; providerReason = [string]$decision.failureKind; completedByProvider = $false; goalVerified = $false; completionContractId = if ($script:AgentCompletionContract) { [string]$script:AgentCompletionContract.contractId } else { $null } }
                break
            }
            if ([string]$script:AgentProviderBudget.mode -eq 'priced-provider' -and [double]$providerBudgetState.actualEstimatedCostCny -gt [double]$script:AgentProviderBudget.maxEstimatedCost) {
                $trace += [pscustomobject]@{
                    iteration = $index
                    observationBefore = $observation
                    previousActionReceipt = $previousActionReceipt
                    allowedActions = @($actionCatalog.Keys | Sort-Object)
                    allowedControls = $controlCatalog
                    decisionFeedback = $decisionFeedbackBeforeStep
                    decision = [ordered]@{ providerUsage = $providerUsage; providerDecisionSuppressed = $true }
                    timing = $stepTiming
                    actionReceipt = [ordered]@{ status = 'provider-cost-overrun'; noNativeActionSent = $true; actualEstimatedCostCny = [double]$providerBudgetState.actualEstimatedCostCny; budgetCny = [double]$script:AgentProviderBudget.maxEstimatedCost }
                    observationAfter = $observation
                    actionAttempted = $false
                    actionExecuted = $false
                    control = [ordered]@{ kind = 'provider-cost-overrun-before-native-action'; budgetId = [string]$providerBudgetState.budgetId }
                }
                $termination = [ordered]@{ reason = 'provider-cost-budget-exceeded'; providerReason = 'Reported token usage exceeded the configured cost ceiling; no Native action was dispatched.'; completedByProvider = $false; goalVerified = $false; completionContractId = if ($script:AgentCompletionContract) { [string]$script:AgentCompletionContract.contractId } else { $null } }
                break
            }
        }
        $providerRejectedDecision = ($decision -and $decision.decisionRejected -eq $true)
        $rejectedRequestedAction = if ($providerRejectedDecision) { [string]$decision.requestedAction } else { [string]$decision.action }
        $providerRejectionMessage = $null
        if ($providerRejectedDecision) {
            if ([string]::IsNullOrWhiteSpace($rejectedRequestedAction) -or [string]::IsNullOrWhiteSpace([string]$decision.reason))
                { throw 'Provider decisionRejected response must include requestedAction and reason.' }
            if ($rejectedRequestedAction -ceq 'advance') { throw 'advance is a Harness-only deterministic time step and is unavailable to Agent decision providers.' }
            $reportedCatalog = @($decision.availableActions | ForEach-Object { [string]$_ } | Sort-Object -Unique)
            $actualCatalog = @($actionCatalog.Keys | ForEach-Object { [string]$_ } | Sort-Object -Unique)
            if (($reportedCatalog -join ',') -cne ($actualCatalog -join ',')) { throw 'Provider decisionRejected response did not preserve the current validated action catalog.' }
            if ([string]$decision.reason -ceq 'not-in-current-action-catalog') {
                $providerRejectionMessage = "Decision action '$rejectedRequestedAction' is not currently available from the latest Native observation. Provider reason='$($decision.reason)'."
            }
            elseif ([string]$decision.reason -ceq 'invalid-action-arguments') {
                if (-not $actionCatalog.ContainsKey($rejectedRequestedAction)) { throw 'Provider reported invalid arguments for an action absent from the current catalog.' }
                $actualArguments = @($actionCatalog[$rejectedRequestedAction] | ForEach-Object { [string]$_ })
                $reportedArguments = @($decision.allowedArguments | ForEach-Object { [string]$_ })
                $invalidArguments = @($decision.invalidArguments | ForEach-Object { [string]$_ } | Sort-Object -Unique)
                if (($reportedArguments -join ',') -cne ($actualArguments -join ',') -or $invalidArguments.Count -eq 0 -or @($invalidArguments | Where-Object { $_ -in $actualArguments }).Count -gt 0 -or -not [bool]$decision.noNativeActionSent) {
                    throw 'Provider invalid-argument rejection did not match the current action parameter list or confirm that no Native action was sent.'
                }
                $allowedArgumentText = if ($actualArguments.Count -gt 0) { $actualArguments -join ', ' } else { 'none' }
                $providerRejectionMessage = "Decision action '$rejectedRequestedAction' supplied unsupported argument(s): $($invalidArguments -join ', '). Allowed arguments: $allowedArgumentText. No Native action was sent."
            }
            else { throw 'Provider decisionRejected response used an unrecognized rejection reason.' }
        }
        if ($decision -and $decision.observeAgain -eq $true) {
            $waitSeconds = 0
            if (-not [int]::TryParse([string]$decision.waitSeconds, [ref]$waitSeconds) -or $waitSeconds -lt 1 -or $waitSeconds -gt 10)
                { throw 'An observeAgain decision must request a bounded waitSeconds value between 1 and 10.' }
            $waitReason = [string]$decision.reason
            if ([string]::IsNullOrWhiteSpace($waitReason)) { throw 'An observeAgain decision must include a non-empty reason.' }
            if ($decision.PSObject.Properties.Name -contains 'action' -or $decision.PSObject.Properties.Name -contains 'done')
                { throw 'An observeAgain decision cannot include an action or done signal.' }
            $moveReceipt = $previousActionReceipt
            $observeAgainPolicy = Get-ObserveAgainPolicy -Observation $observation -PreviousActionReceipt $moveReceipt
            if (-not $observeAgainPolicy.Allowed) {
                if (-not $observeAgainPolicy.Recoverable) {
                    $controlError = [string]$observeAgainPolicy.Reason
                    $trace += [pscustomobject]@{
                        iteration = $index
                        observationBefore = $observation
                        previousActionReceipt = $previousActionReceipt
                        allowedActions = @($actionCatalog.Keys | Sort-Object)
                        allowedControls = $controlCatalog
                        decisionFeedback = $decisionFeedbackBeforeStep
                        decision = $decision
                        timing = $stepTiming
                        actionReceipt = [ordered]@{ protocolVersion = 1; status = 'control-validation-failed-before-wait'; error = $controlError; noNativeActionSent = $true; schedulerWaitStarted = $false; campaignDay = $observation.campaignDay }
                        observationAfter = $observation
                        actionAttempted = $false
                        actionExecuted = $false
                        control = [ordered]@{ kind = 'control-validation-failed-before-wait'; requestedControl = 'observeAgain'; reason = $controlError }
                    }
                    throw $controlError
                }
                $consecutiveDecisionRejections++
                if ($consecutiveDecisionRejections -gt 2) { throw 'Provider repeated observeAgain while Native movement was unavailable; stopping after two safe pre-action rejections.' }
                $feedbackReason = [string]$observeAgainPolicy.Reason + ' No wait or game action was sent.'
                $nextObservation = Invoke-AgentCli 'state' @{} "$CommandPrefix-rejected-control-observe-$index"
                if ($nextObservation.status -ne 'completed' -or -not $nextObservation.state) { throw 'Fresh Native observation after stale observeAgain was not completed.' }
                $decisionFeedback = [ordered]@{ kind = 'control-unavailable'; requestedControl = 'observeAgain'; message = $feedbackReason; noNativeActionSent = $true; priorFeedback = $decisionFeedbackBeforeStep }
                $rejectionReceipt = [ordered]@{ protocolVersion = 1; control = 'observeAgain'; status = 'rejected-before-native'; error = $feedbackReason; noNativeActionSent = $true; campaignDay = $nextObservation.campaignDay }
                $trace += [pscustomobject]@{
                    iteration = $index
                    observationBefore = $observation
                    previousActionReceipt = $previousActionReceipt
                    allowedActions = @($actionCatalog.Keys | Sort-Object)
                    allowedControls = $controlCatalog
                    decisionFeedback = $decisionFeedbackBeforeStep
                    decision = $decision
                    timing = $stepTiming
                    actionReceipt = $rejectionReceipt
                    observationAfter = $nextObservation
                    actionAttempted = $false
                    actionExecuted = $false
                    control = [ordered]@{ kind = 'control-rejected-before-native'; requestedControl = 'observeAgain'; reason = $feedbackReason }
                }
                $observation = $nextObservation
                continue
            }
            $targetSettlementId = [string]$moveReceipt.state.location.targetSettlementId
            $waitStartedUtc = [DateTime]::UtcNow.ToString('O')
            $waitStartedTicks = [Diagnostics.Stopwatch]::GetTimestamp()
            Start-Sleep -Seconds $waitSeconds
            $waitCompletedUtc = [DateTime]::UtcNow.ToString('O')
            $stepTiming.schedulerWaitStartedUtc = $waitStartedUtc
            $stepTiming.schedulerWaitCompletedUtc = $waitCompletedUtc
            $stepTiming.schedulerWaitElapsedMilliseconds = [Math]::Round(([Diagnostics.Stopwatch]::GetTimestamp() - $waitStartedTicks) * 1000.0 / [Diagnostics.Stopwatch]::Frequency, 2)
            $stepTiming.observationStartedUtc = [DateTime]::UtcNow.ToString('O')
            if ($MaxElapsedSeconds -gt 0 -and ([DateTime]::UtcNow - $loopStartedUtc).TotalSeconds -ge $MaxElapsedSeconds)
                { throw "Agent decision loop exceeded its $MaxElapsedSeconds-second wall-clock budget during scheduler wait." }
            $observationStartedTicks = [Diagnostics.Stopwatch]::GetTimestamp()
            $nextObservation = Invoke-AgentCli 'state' @{} "$CommandPrefix-observe-$index"
            $stepTiming.observationCompletedUtc = [DateTime]::UtcNow.ToString('O')
            $stepTiming.observationElapsedMilliseconds = [Math]::Round(([Diagnostics.Stopwatch]::GetTimestamp() - $observationStartedTicks) * 1000.0 / [Diagnostics.Stopwatch]::Frequency, 2)
            if ($nextObservation.status -ne 'completed' -or -not $nextObservation.state) { throw 'Post-wait Native observation was not completed.' }
            $trace += [pscustomobject]@{
                iteration = $index
                observationBefore = $observation
                previousActionReceipt = $previousActionReceipt
                allowedActions = @($actionCatalog.Keys | Sort-Object)
                allowedControls = $controlCatalog
                decisionFeedback = $decisionFeedbackBeforeStep
                decision = $decision
                timing = $stepTiming
                actionReceipt = $null
                observationAfter = $nextObservation
                actionAttempted = $false
                actionExecuted = $false
                control = [ordered]@{ kind = 'bounded-observe-again'; waitSeconds = $waitSeconds; reason = $waitReason; targetSettlementId = $targetSettlementId }
            }
            $observation = $nextObservation
            if ($script:AgentCheckpoint) {
                $script:AgentCheckpoint.lastObservedSummary = [ordered]@{
                    campaignDay = $observation.campaignDay
                    currentSettlementId = $observation.state.location.currentSettlementId
                    targetSettlementId = $observation.state.location.targetSettlementId
                    isMoving = $observation.state.party.isMoving
                    members = $observation.state.party.members
                    gold = $observation.state.economy.gold
                    menuId = $observation.state.context.menuId
                }
                Write-AgentCheckpoint "$CommandPrefix-checkpoint-observe-$index"
            }
            continue
        }
        if ($decision -and $decision.done -eq $true) {
            $doneReason = [string]$decision.reason
            if ([string]::IsNullOrWhiteSpace($doneReason)) { throw 'A provider stop decision must include a non-empty reason.' }
            $goalVerification = $null
            if ($script:AgentCompletionContract) {
                $goalVerification = Test-AgentGoalCompletion -Contract $script:AgentCompletionContract -Observation $observation
                if (-not $goalVerification.Satisfied) {
                    $verificationStatus = [string]$goalVerification.Status
                    $verificationFeedback = [ordered]@{
                        kind = if ($verificationStatus -eq 'unknown') { 'goal-verification-unknown' } else { 'goal-not-satisfied' }
                        contractId = $goalVerification.ContractId
                        missingConditions = @($goalVerification.MissingConditions)
                        unknownConditions = @($goalVerification.UnknownConditions)
                        noNativeActionSent = $true
                        message = if ($verificationStatus -eq 'unknown') { 'Current Native observation is missing fields required by the goal contract; completion is unverified.' } else { 'Current Native observation does not meet the goal contract; complete the listed Native conditions before stopping.' }
                    }
                    $trace += [pscustomobject]@{
                        iteration = $index
                        observationBefore = $observation
                        previousActionReceipt = $previousActionReceipt
                        allowedActions = @($actionCatalog.Keys | Sort-Object)
                        allowedControls = $controlCatalog
                        decisionFeedback = $decisionFeedbackBeforeStep
                        decision = $decision
                        timing = $stepTiming
                        actionReceipt = [ordered]@{ status = 'goal-verification-rejected'; noNativeActionSent = $true; goalVerification = $goalVerification; providerReason = $doneReason; campaignDay = $observation.campaignDay }
                        observationAfter = $observation
                        actionAttempted = $false
                        actionExecuted = $false
                        control = [ordered]@{ kind = 'goal-verification-rejected'; contractId = $goalVerification.ContractId; status = $verificationStatus }
                    }
                    $decisionFeedback = $verificationFeedback
                    if ($script:AgentCheckpoint) {
                        $script:AgentCheckpoint.status = 'active'
                        $script:AgentCheckpoint.lastGoalVerification = [ordered]@{ status = $verificationStatus; contractId = $goalVerification.ContractId; verifiedUtc = [DateTime]::UtcNow.ToString('O'); result = $goalVerification }
                        $script:AgentCheckpoint.lastStopReason = $null
                        Write-AgentCheckpoint "$CommandPrefix-checkpoint-goal-unmet-$index"
                    }
                    continue
                }
            }
            $trace += [pscustomobject]@{
                iteration = $index
                observationBefore = $observation
                previousActionReceipt = $previousActionReceipt
                allowedActions = @($actionCatalog.Keys | Sort-Object)
                allowedControls = $controlCatalog
                decisionFeedback = $decisionFeedbackBeforeStep
                decision = $decision
                timing = $stepTiming
                actionReceipt = if ($goalVerification) { [ordered]@{ status = 'goal-verified-complete'; noNativeActionSent = $true; goalVerification = $goalVerification; providerReason = $doneReason; campaignDay = $observation.campaignDay } } else { $null }
                observationAfter = $observation
                actionExecuted = $false
            }
            if ($script:AgentCheckpoint) {
                $script:AgentCheckpoint.status = if ($goalVerification) { 'verified-complete' } else { 'provider-stopped' }
                $script:AgentCheckpoint.lastStopReason = $doneReason
                if ($goalVerification) { $script:AgentCheckpoint.lastGoalVerification = [ordered]@{ status = 'satisfied'; contractId = $goalVerification.ContractId; verifiedUtc = [DateTime]::UtcNow.ToString('O'); result = $goalVerification } }
                Write-AgentCheckpoint "$CommandPrefix-checkpoint-stop-$index"
            }
            $termination = if ($goalVerification) {
                [ordered]@{ reason = 'native-goal-verified'; providerReason = $doneReason; completedByProvider = $true; goalVerified = $true; completionContractId = $goalVerification.ContractId }
            }
            else { [ordered]@{ reason = 'provider-stop'; providerReason = $doneReason; completedByProvider = $true; goalVerified = $false; completionContractId = $null } }
            break
        }
        try {
            if ($providerRejectedDecision) { throw $providerRejectionMessage }
            $validated = Convert-DecisionToCli $decision $actionCatalog $observation $previousActionReceipt
        }
        catch {
            $recoverableProviderRejection = ($providerRejectedDecision -and [string]$decision.reason -in @('not-in-current-action-catalog','invalid-action-arguments'))
            if (-not $recoverableProviderRejection -and $_.Exception.Message -notmatch 'is not currently available from the latest Native observation') {
                $validationError = $_.Exception.Message
                $trace += [pscustomobject]@{
                    iteration = $index
                    observationBefore = $observation
                    previousActionReceipt = $previousActionReceipt
                    allowedActions = @($actionCatalog.Keys | Sort-Object)
                    allowedControls = $controlCatalog
                    decisionFeedback = $decisionFeedbackBeforeStep
                    decision = $decision
                    timing = $stepTiming
                    actionReceipt = [ordered]@{ protocolVersion = 1; status = 'decision-validation-failed-before-native'; error = $validationError; noNativeActionSent = $true; campaignDay = $observation.campaignDay }
                    observationAfter = $observation
                    actionAttempted = $false
                    actionExecuted = $false
                    control = [ordered]@{ kind = 'decision-validation-failed-before-native'; reason = $validationError }
                }
                throw
            }
            $consecutiveDecisionRejections++
            if ($consecutiveDecisionRejections -gt 2) { throw 'Provider repeated actions that are unavailable in the latest Native state; stopping after two safe pre-Native rejections.' }
            $feedbackReason = $_.Exception.Message
            $nextObservation = Invoke-AgentCli 'state' @{} "$CommandPrefix-rejected-decision-observe-$index"
            if ($nextObservation.status -ne 'completed' -or -not $nextObservation.state) { throw 'Fresh Native observation after an unavailable decision was not completed.' }
            if ($providerRejectedDecision -and [string]$decision.reason -ceq 'invalid-action-arguments') {
                $decisionFeedback = [ordered]@{ kind = 'invalid-action-arguments'; requestedAction = $rejectedRequestedAction; invalidArguments = @($decision.invalidArguments); allowedArguments = @($decision.allowedArguments); message = $feedbackReason; noNativeActionSent = $true; availableActions = @($actionCatalog.Keys | Sort-Object) }
            }
            else { $decisionFeedback = [ordered]@{ kind = 'action-unavailable'; requestedAction = $rejectedRequestedAction; message = $feedbackReason; noNativeActionSent = $true; availableActions = @($actionCatalog.Keys | Sort-Object) } }
            $rejectionReceipt = [ordered]@{ protocolVersion = 1; action = $rejectedRequestedAction; status = 'rejected-before-native'; error = $feedbackReason; noNativeActionSent = $true; campaignDay = $nextObservation.campaignDay }
            $trace += [pscustomobject]@{ iteration = $index; observationBefore = $observation; previousActionReceipt = $previousActionReceipt; allowedActions = @($actionCatalog.Keys | Sort-Object); allowedControls = $controlCatalog; decisionFeedback = $decisionFeedbackBeforeStep; decision = $decision; timing = $stepTiming; actionReceipt = $rejectionReceipt; observationAfter = $nextObservation; actionAttempted = $false; actionExecuted = $false; control = [ordered]@{ kind = 'decision-rejected-before-native' } }
            $observation = $nextObservation
            continue
        }
        $consecutiveDecisionRejections = 0
        $commandId = "$CommandPrefix-act-$index"
        if ($script:AgentCheckpoint -and $validated.Action -eq 'recruit') {
            $matchingRecruitOffer = @($previousActionReceipt.data.offers | Where-Object { $_.available -and [string]$_.ownerId -ceq [string]$validated.Arguments.OwnerId -and [string]$_.troopId -ceq [string]$validated.Arguments.TroopId -and [int]$_.slot -eq [int]$validated.Arguments.VolunteerSlot -and [int]$_.cost -le [int]$observation.state.economy.gold } | Select-Object -First 1)
            if ($matchingRecruitOffer.Count -ne 1 -or [bool]$validated.Arguments.ConfirmPartySizeWarning) { throw 'Persistent Native recruit requires one current affordable non-over-capacity offer receipt.' }
            $preActionSummary = ConvertTo-CheckpointObservationSummary $observation
            $script:AgentCheckpoint.pendingAction = [ordered]@{
                commandId = $commandId
                action = 'recruit'
                arguments = [ordered]@{ OwnerId = [string]$validated.Arguments.OwnerId; TroopId = [string]$validated.Arguments.TroopId; VolunteerSlot = [int]$validated.Arguments.VolunteerSlot }
                expectedCost = [int]$matchingRecruitOffer[0].cost
                expectedMembersAfter = [int]$preActionSummary.members + 1
                expectedGoldAfter = [int]$preActionSummary.gold - [int]$matchingRecruitOffer[0].cost
                preActionSummary = $preActionSummary
                status = 'pending'
                createdUtc = [DateTime]::UtcNow.ToString('O')
            }
            Write-AgentCheckpoint "$CommandPrefix-checkpoint-pending-$index"
        }
        $stepTiming.actionStartedUtc = [DateTime]::UtcNow.ToString('O')
        $actionStartedTicks = [Diagnostics.Stopwatch]::GetTimestamp()
        try {
            if ($validated.Action -ceq 'rest') { $actionResult = Invoke-AgentCli $validated.Action $validated.Arguments $commandId -ReturnWhenAccepted }
            else { $actionResult = Invoke-AgentCli $validated.Action $validated.Arguments $commandId }
        }
        catch {
            $stepTiming.actionCompletedUtc = [DateTime]::UtcNow.ToString('O')
            $stepTiming.actionElapsedMilliseconds = [Math]::Round(([Diagnostics.Stopwatch]::GetTimestamp() - $actionStartedTicks) * 1000.0 / [Diagnostics.Stopwatch]::Frequency, 2)
            $cliError = $_.Exception.Message
            $knownNoNativeDispatch = ($cliError -match 'Cannot process argument transformation|Mandatory parameter|parameter.*could not be found')
            $trace += [pscustomobject]@{
                iteration = $index
                observationBefore = $observation
                previousActionReceipt = $previousActionReceipt
                allowedActions = @($actionCatalog.Keys | Sort-Object)
                allowedControls = $controlCatalog
                decisionFeedback = $decisionFeedbackBeforeStep
                decision = $decision
                timing = $stepTiming
                actionReceipt = [ordered]@{ protocolVersion = 1; commandId = $commandId; action = [string]$validated.Action; status = 'agent-cli-failed'; error = $cliError; nativeDispatchConfirmed = $false; noNativeDispatchConfirmed = $knownNoNativeDispatch }
                observationAfter = $null
                actionAttempted = $true
                actionExecuted = $false
                control = [ordered]@{ kind = 'agent-cli-invocation-failed'; nativeOutcome = if ($knownNoNativeDispatch) { 'not-dispatched' } else { 'unknown' } }
            }
            throw
        }
        $stepTiming.actionCompletedUtc = [DateTime]::UtcNow.ToString('O')
        $stepTiming.actionElapsedMilliseconds = [Math]::Round(([Diagnostics.Stopwatch]::GetTimestamp() - $actionStartedTicks) * 1000.0 / [Diagnostics.Stopwatch]::Frequency, 2)
        if ($HarnessCrashAfterAction -and $validated.Action -ceq $HarnessCrashAfterAction -and $actionResult.status -in @('completed','accepted')) {
            [Environment]::Exit(93)
        }
        if ($actionResult.status -notin @('completed','accepted')) {
            $consecutiveDecisionRejections++
            $trace += [pscustomobject]@{
                iteration = $index
                observationBefore = $observation
                previousActionReceipt = $previousActionReceipt
                allowedActions = @($actionCatalog.Keys | Sort-Object)
                allowedControls = $controlCatalog
                decisionFeedback = $decisionFeedbackBeforeStep
                decision = $decision
                timing = $stepTiming
                actionReceipt = $actionResult
                observationAfter = $null
                actionAttempted = $true
                actionExecuted = $false
            }
            $nextObservation = Invoke-AgentCli 'state' @{} "$CommandPrefix-rejected-native-observe-$index"
            if ($nextObservation.status -ne 'completed' -or -not $nextObservation.state) { throw 'Fresh Native observation after a rejected action was not completed.' }
            $decisionFeedback = [ordered]@{ kind = 'native-action-rejected'; requestedAction = $validated.Action; message = [string]$actionResult.error; noWorldChangeConfirmed = $false }
            # Keep the last completed Native receipt available for the next replan.
            # The rejected attempt is already present in this trace entry and decisionFeedback;
            # replacing a valid Move receipt here would make an encounter-paused party look contextless.
            $observation = $nextObservation
            if ($script:AgentCheckpoint) {
                $script:AgentCheckpoint.status = 'active'
                $script:AgentCheckpoint.pendingAction = $null
                Write-AgentCheckpoint "$CommandPrefix-checkpoint-rejected-$index"
            }
            if ($consecutiveDecisionRejections -gt 2) { throw 'Provider repeated actions rejected by Native; stopping after two bounded recovery attempts.' }
            continue
        }
        if ($validated.Action -ceq 'barterAutoBalance' -and [bool]$actionResult.data.autoBalanced) {
            $script:BalancedBarterSessionId = [string]$actionResult.data.updatedOptions.sessionId
        }
        elseif ($validated.Action -in @('barterEdit','barterReset','barterOffer','barterCancel')) {
            $script:BalancedBarterSessionId = $null
        }
        $stepTiming.observationStartedUtc = [DateTime]::UtcNow.ToString('O')
        $observationStartedTicks = [Diagnostics.Stopwatch]::GetTimestamp()
        if ($HarnessPrepareSafePassageAfterMove -and -not $safePassageFixtureInjected -and $validated.Action -ceq 'move') {
            $fixtureCreatedUtc = [DateTime]::UtcNow.ToString('O')
            $banditFixture = Invoke-AgentCli 'harnessPrepareSafePassageFixture' @{} "$CommandPrefix-harness-safe-passage-$index"
            if ($banditFixture.status -ne 'completed' -or -not [bool]$banditFixture.data.hostile -or [string]$banditFixture.data.targetPartyId -cne [string]$observation.state.party.id) {
                throw "The Native Safe Passage Harness fixture failed to create an actively hostile bandit targeting the MainParty: $($banditFixture.error)"
            }
            $script:HarnessEvents += [ordered]@{
                kind = 'native-safe-passage-bandit-prepared'
                createdUtc = $fixtureCreatedUtc
                partyId = [string]$banditFixture.data.partyId
                memberCount = [int]$banditFixture.data.memberCount
                banditStrength = [double]$banditFixture.data.banditStrength
                requiredBanditStrength = [double]$banditFixture.data.requiredBanditStrength
                playerSidePartyCount = [int]$banditFixture.data.playerSidePartyCount
                playerSideMemberCount = [int]$banditFixture.data.playerSideMemberCount
            }
            $safePassageFixtureInjected = $true
            $encounterDeadline = [DateTime]::UtcNow.AddSeconds(30)
            $nextObservation = $null
            while ([DateTime]::UtcNow -lt $encounterDeadline) {
                $encounterProbe = Invoke-AgentCli 'state' @{} "$CommandPrefix-harness-safe-passage-observe-$index-$([Guid]::NewGuid().ToString('N'))"
                $talkOption = @($encounterProbe.state.context.conversation.options | Where-Object { $_.clickable -and $_.id -eq 'bandit_start_defender_2' } | Select-Object -First 1)
                if ($encounterProbe.status -eq 'completed' -and [bool]$encounterProbe.state.context.encounterActive -and $talkOption.Count -eq 1) {
                    $nextObservation = $encounterProbe
                    $script:HarnessEvents += [ordered]@{
                        kind = 'native-safe-passage-conversation-observed'
                        observedUtc = [DateTime]::UtcNow.ToString('O')
                        partyId = [string]$encounterProbe.state.context.encounteredPartyId
                        menuId = [string]$encounterProbe.state.context.menuId
                    }
                    break
                }
                Start-Sleep -Milliseconds 200
            }
            if (-not $nextObservation) { throw 'The Native hostile bandit fixture did not produce its visible Safe Passage conversation within 30 seconds.' }
        }
        else { $nextObservation = Invoke-AgentCli 'state' @{} "$CommandPrefix-observe-$index" }
        $stepTiming.observationCompletedUtc = [DateTime]::UtcNow.ToString('O')
        $stepTiming.observationElapsedMilliseconds = [Math]::Round(([Diagnostics.Stopwatch]::GetTimestamp() - $observationStartedTicks) * 1000.0 / [Diagnostics.Stopwatch]::Frequency, 2)
        if ($nextObservation.status -ne 'completed' -or -not $nextObservation.state) { throw 'Post-action observation was not completed.' }
        $restMonitorTarget = Get-NativeRestMonitorTarget -Action $validated.Action -Arguments $validated.Arguments -Receipt $actionResult
        if ($restMonitorTarget -and (Test-NativeRestMonitorNeeded -Observation $nextObservation -MonitorTarget $restMonitorTarget)) {
            $restMonitorStartedUtc = [DateTime]::UtcNow.ToString('O')
            $restMonitorStartedTicks = [Diagnostics.Stopwatch]::GetTimestamp()
            $restMonitorPollCount = 0
            while (Test-NativeRestMonitorNeeded -Observation $nextObservation -MonitorTarget $restMonitorTarget) {
                if ($MaxElapsedSeconds -gt 0 -and ([DateTime]::UtcNow - $loopStartedUtc).TotalSeconds -ge $MaxElapsedSeconds) {
                    throw 'Agent decision loop exceeded its wall-clock budget while monitoring an accepted Native rest; no game clock control was issued.'
                }
                Start-Sleep -Seconds 5
                $restMonitorObservation = Invoke-AgentCli 'state' @{} "$CommandPrefix-native-rest-monitor-$index-$($restMonitorPollCount + 1)"
                $restMonitorPollCount++
                if ($restMonitorObservation.status -ne 'completed' -or -not $restMonitorObservation.state) { throw 'Native observation during accepted-rest monitoring was not completed.' }
                $nextObservation = $restMonitorObservation
            }
            $stepTiming.schedulerWaitStartedUtc = $restMonitorStartedUtc
            $stepTiming.schedulerWaitCompletedUtc = [DateTime]::UtcNow.ToString('O')
            $stepTiming.schedulerWaitElapsedMilliseconds = [Math]::Round(([Diagnostics.Stopwatch]::GetTimestamp() - $restMonitorStartedTicks) * 1000.0 / [Diagnostics.Stopwatch]::Frequency, 2)
            $restMonitorExitReason = if ([int]$nextObservation.dailyTickCount -ge [int]$restMonitorTarget.TargetDailyTickCount) { 'requested-native-daily-tick-reached' } elseif (-not [bool]$nextObservation.state.context.isWaiting) { 'native-wait-ended-before-target' } else { 'native-wait-clock-stopped-before-target' }
            $actionResult | Add-Member -NotePropertyName nativeRestMonitor -NotePropertyValue ([ordered]@{
                kind = 'host-observation-only';
                startingDailyTickCount = [int]$restMonitorTarget.StartingDailyTickCount;
                requestedDays = [int]$restMonitorTarget.RequestedDays;
                targetDailyTickCount = [int]$restMonitorTarget.TargetDailyTickCount;
                finalDailyTickCount = [int]$nextObservation.dailyTickCount;
                observationPollCount = $restMonitorPollCount;
                elapsedMilliseconds = [Math]::Round(([Diagnostics.Stopwatch]::GetTimestamp() - $restMonitorStartedTicks) * 1000.0 / [Diagnostics.Stopwatch]::Frequency, 2);
                exitReason = $restMonitorExitReason;
                nativeClockControlSent = $false;
                nativeGameActionsSent = 0
            }) -Force
        }
        $trace += [pscustomobject]@{
            iteration = $index
            observationBefore = $observation
            previousActionReceipt = $previousActionReceipt
            allowedActions = @($actionCatalog.Keys | Sort-Object)
            allowedControls = $controlCatalog
            decisionFeedback = $decisionFeedbackBeforeStep
            decision = $decision
            timing = $stepTiming
            actionReceipt = $actionResult
            observationAfter = $nextObservation
            actionAttempted = $true
            actionExecuted = $true
        }
        $previousActionReceipt = $actionResult
        $decisionFeedback = $null
        $observation = $nextObservation
        if ($script:AgentCheckpoint) {
            $script:AgentCheckpoint.status = 'active'
            $script:AgentCheckpoint.pendingAction = $null
            $script:AgentCheckpoint.lastActionReceipt = ConvertTo-CheckpointReceipt $actionResult
            $script:AgentCheckpoint.lastObservedSummary = [ordered]@{
                campaignDay = $observation.campaignDay
                currentSettlementId = $observation.state.location.currentSettlementId
                targetSettlementId = $observation.state.location.targetSettlementId
                isMoving = $observation.state.party.isMoving
                members = $observation.state.party.members
                gold = $observation.state.economy.gold
                menuId = $observation.state.context.menuId
            }
            Write-AgentCheckpoint "$CommandPrefix-checkpoint-action-$index"
        }
    }

    [pscustomobject]@{
        schemaVersion = 1
        runId = $loopRunId
        provider = $providerPath
        initialObservation = [ordered]@{ startedUtc = $initialObservationStartedUtc; completedUtc = $initialObservationCompletedUtc }
        decisions = $trace.Count
        actionsExecuted = @($trace | Where-Object { $_.actionExecuted }).Count
        termination = $termination
        providerBudget = Get-AgentProviderBudgetSummary -State $providerBudgetState -Budget $script:AgentProviderBudget
        harnessEvents = @($script:HarnessEvents)
        trace = $trace
    } | ConvertTo-Json -Depth 20
}
catch {
    [pscustomobject]@{
        status = 'failed'
        runId = $loopRunId
        error = $_.Exception.Message
        timing = $script:LastLoopTiming
        lastObservation = $observation
        providerBudget = Get-AgentProviderBudgetSummary -State $providerBudgetState -Budget $script:AgentProviderBudget
        harnessEvents = @($script:HarnessEvents)
        trace = @($trace)
    } | ConvertTo-Json -Depth 20 -Compress
    exit 1
}
