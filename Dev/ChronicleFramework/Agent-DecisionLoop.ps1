[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$DecisionProviderPath,
    [int]$MaxDecisions = 1,
    [int]$TimeoutSeconds = 180,
    [ValidateRange(0,3600)][int]$MaxElapsedSeconds = 0,
    [string]$CommandPrefix = 'loop',
    [string]$Goal,
    [string[]]$AllowedActionNames,
    [switch]$PersistCheckpoint,
    [switch]$ResumeCheckpoint,
    [ValidateSet('recruit')][string]$HarnessCrashAfterAction,
    [switch]$HarnessPrepareSafePassageAfterMove
)

$ErrorActionPreference = 'Stop'
$decisionLoopPolicyPath = Join-Path $PSScriptRoot 'Agent-DecisionLoopPolicy.ps1'
. $decisionLoopPolicyPath
$cliPath = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$providerPath = (Resolve-Path -LiteralPath $DecisionProviderPath).Path
if ($MaxDecisions -lt 1 -or $MaxDecisions -gt 400) { throw 'MaxDecisions must be between 1 and 400.' }

$script:ProductAllowedActions = @{
    state = @(); closeEscapeMenu = @(); respondInquiry = @('InquiryToken','InquiryChoice'); respondMultiSelectionInquiry = @('InquiryToken','InquiryChoice','SelectedIds'); mapSettlementTargets = @(); mapNotifications = @(); quickInformation = @(); sceneNotification = @(); mapPartyTargets = @(); mapPartyComposition = @('PartyId'); mapPartyBehavior = @('PartyId'); partyUpgradeOptions = @(); upgradeTroop = @('TroopId','UpgradeTargetIndex'); prisonerRecruitmentOptions = @(); recruitPrisoner = @('TroopId','ConfirmPartySizeWarning'); characterDevelopment = @(); spendSkillFocus = @('SkillId','Count'); questDetails = @('QuestId'); partyRoster = @(); partyRoles = @(); setPartyRole = @('RoleId','HeroId'); unassignPartyRole = @('RoleId'); inventoryOpen = @(); heroEquipmentOptions = @(); equipHeroItem = @('ItemViewModelId','EquipmentIndex'); unequipHeroItem = @('EquipmentIndex'); inventoryConfirm = @(); inventoryCancel = @(); inventoryCancelChanges = @(); pause = @(); resume = @(); fastForward = @(); move = @('SettlementId'); moveToPoint = @('X','Y','Surface'); missionSceneAgents = @(); missionInput = @('X','Y','DurationSeconds'); missionNavigateToAgent = @('AgentIndex','DurationSeconds'); missionLeave = @(); missionInteract = @('AgentIndex'); missionCancelNavigation = @(); missionAimAt = @('AgentIndex');
    pursue = @('PartyId'); follow = @('PartyId'); hold = @(); menu = @(); menuSelect = @('MenuId','OptionId'); talkToSettlementHero = @('HeroId'); visitSettlementHero = @('HeroId'); dialogueSelect = @('OptionId'); dialogueContinue = @();
    battlePause = @(); battleSkip = @(); battleFinish = @(); battleRetreat = @(); missionRetreat = @();
    partyTakeAll = @('LootType'); partyScreenDone = @(); inventoryTakeAll = @(); inventoryDone = @();
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
    param([string]$Action, [hashtable]$Arguments = @{}, [string]$CommandId)
    $cliArguments = @($Action, '-CommandId', $CommandId, '-TimeoutSeconds', [string]$TimeoutSeconds, '-AsJson')
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
        throw "Decision provider timed out after $TimeoutSeconds seconds."
    }
    $stdout = $stdoutTask.Result.Trim()
    $stderr = $stderrTask.Result.Trim()
    if ($process.ExitCode -ne 0) { throw "Decision provider exited $($process.ExitCode): $stderr" }
    try { return $stdout | ConvertFrom-Json }
    catch { throw "Decision provider returned invalid JSON: $stdout $stderr" }
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
        default { $null }
    }
    if (-not $actionProfile -or -not $Observation.state) { return $Observation }
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
    $script:AgentCheckpoint.updatedUtc = [DateTime]::UtcNow.ToString('O')
    $checkpointJson = $script:AgentCheckpoint | ConvertTo-Json -Depth 16 -Compress
    if ($checkpointJson.Length -gt 60000) { throw 'Agent checkpoint exceeded the 60,000-character runtime limit.' }
    $checkpointBase64 = [Convert]::ToBase64String([Text.UTF8Encoding]::new($false).GetBytes($checkpointJson))
    $receipt = Invoke-AgentCli 'agentCheckpointSet' @{ CheckpointBase64 = $checkpointBase64 } $CheckpointCommandId
    if ($receipt.status -ne 'completed' -or [string]$receipt.data.campaignInstanceId -cne [string]$script:AgentCheckpoint.campaignInstanceId)
        { throw 'Native Campaign checkpoint write did not confirm the active Campaign identity.' }
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
    $previousActionReceipt = $null
    $decisionFeedback = $null
    $consecutiveDecisionRejections = 0
    $initialObservationStartedUtc = [DateTime]::UtcNow.ToString('O')
    $observation = Invoke-AgentCli 'state' @{} "$CommandPrefix-observe-0"
    $initialObservationCompletedUtc = [DateTime]::UtcNow.ToString('O')
    $termination = [ordered]@{ reason = 'decision-budget-exhausted'; providerReason = $null; completedByProvider = $false }
    if ($observation.status -ne 'completed' -or -not $observation.state) { throw 'Initial game observation was not completed.' }
    if ($ResumeCheckpoint) {
        $checkpointRead = Invoke-AgentCli 'agentCheckpointGet' @{} "$CommandPrefix-checkpoint-read"
        if ($checkpointRead.status -ne 'completed' -or [string]::IsNullOrWhiteSpace([string]$checkpointRead.data.checkpointBase64))
            { throw 'No Campaign-saved Agent checkpoint is available to resume.' }
        try {
            $checkpointJson = [Text.UTF8Encoding]::new($false, $true).GetString([Convert]::FromBase64String([string]$checkpointRead.data.checkpointBase64))
            $script:AgentCheckpoint = $checkpointJson | ConvertFrom-Json -ErrorAction Stop
        }
        catch { throw 'Campaign Agent checkpoint is corrupt or unreadable; stopping before any provider call or Native action.' }
        if ([int]$script:AgentCheckpoint.schemaVersion -ne 1)
            { throw "Campaign Agent checkpoint schema version '$($script:AgentCheckpoint.schemaVersion)' is unsupported; stopping before provider/actions." }
        if ([string]$script:AgentCheckpoint.campaignInstanceId -cne [string]$checkpointRead.data.campaignInstanceId)
            { throw 'Campaign Agent checkpoint belongs to a different Campaign instance; stopping before provider/actions.' }
        if ([string]$script:AgentCheckpoint.status -notin @('active','provider-stopped'))
            { throw "Checkpoint status '$($script:AgentCheckpoint.status)' is not resumable." }
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
            schemaVersion = 1
            campaignInstanceId = [string]$checkpointRead.data.campaignInstanceId
            taskId = [Guid]::NewGuid().ToString('N')
            goal = $Goal
            status = 'active'
            lastActionReceipt = $null
            pendingAction = $null
            lastRecovery = $null
            lastObservedSummary = $null
            lastStopReason = $null
            updatedUtc = [DateTime]::UtcNow.ToString('O')
        }
        Write-AgentCheckpoint "$CommandPrefix-checkpoint-start"
    }
    for ($index = 1; $index -le $MaxDecisions; $index++) {
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
            schemaVersion = 2
            runId = $loopRunId
            iteration = $index
            goal = $Goal
            allowedActions = @($actionCatalog.GetEnumerator() | Sort-Object -Property Key | ForEach-Object { [ordered]@{ action = [string]$_.Key; arguments = @($_.Value) } })
            allowedControls = $controlCatalog
            nativeMoveArrival = $nativeMoveArrival
            checkpointContext = if ($script:AgentCheckpoint) { [ordered]@{ schemaVersion = $script:AgentCheckpoint.schemaVersion; campaignInstanceId = $script:AgentCheckpoint.campaignInstanceId; taskId = $script:AgentCheckpoint.taskId; status = $script:AgentCheckpoint.status; lastObservedSummary = $script:AgentCheckpoint.lastObservedSummary; pendingAction = $script:AgentCheckpoint.pendingAction; lastRecovery = $script:AgentCheckpoint.lastRecovery } } else { $null }
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
        finally {
            $stepTiming.providerCompletedUtc = [DateTime]::UtcNow.ToString('O')
            $stepTiming.providerElapsedMilliseconds = [Math]::Round(([Diagnostics.Stopwatch]::GetTimestamp() - $providerStartedTicks) * 1000.0 / [Diagnostics.Stopwatch]::Frequency, 2)
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
                if (-not $observeAgainPolicy.Recoverable) { throw $observeAgainPolicy.Reason }
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
                observationAfter = $observation
                actionExecuted = $false
            }
            if ($script:AgentCheckpoint) {
                $script:AgentCheckpoint.status = 'provider-stopped'
                $script:AgentCheckpoint.lastStopReason = $doneReason
                Write-AgentCheckpoint "$CommandPrefix-checkpoint-stop-$index"
            }
            $termination = [ordered]@{ reason = 'provider-stop'; providerReason = $doneReason; completedByProvider = $true }
            break
        }
        try {
            if ($providerRejectedDecision) { throw $providerRejectionMessage }
            $validated = Convert-DecisionToCli $decision $actionCatalog $observation $previousActionReceipt
        }
        catch {
            $recoverableProviderRejection = ($providerRejectedDecision -and [string]$decision.reason -in @('not-in-current-action-catalog','invalid-action-arguments'))
            if (-not $recoverableProviderRejection -and $_.Exception.Message -notmatch 'is not currently available from the latest Native observation') { throw }
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
        $actionResult = Invoke-AgentCli $validated.Action $validated.Arguments $commandId
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
        harnessEvents = @($script:HarnessEvents)
        trace = @($trace)
    } | ConvertTo-Json -Depth 20 -Compress
    exit 1
}
