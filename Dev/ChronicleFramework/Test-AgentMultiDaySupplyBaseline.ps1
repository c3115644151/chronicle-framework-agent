[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180,
    [ValidateRange(3,10)][int]$RestDays = 3,
    [ValidateRange(4,20)][int]$TargetPartyMembers = 6,
    [ValidateRange(1,20)][int]$ProvisionAmount = 4,
    [ValidateRange(30,600)][int]$RestWallClockLimitSeconds = 180,
    [ValidateRange(1,5)][int]$Repetitions = 1,
    [switch]$CaptureVisualEvidence,
    [switch]$StartAtCurrentTown,
    [ValidateRange(5,30)][int]$FrameRate = 10
)

$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$runPrefix = 'supply-' + [Guid]::NewGuid().ToString('N')
if (-not (Test-Path -LiteralPath $savePath -PathType Leaf)) { throw "Supply baseline fixture not found: $savePath" }
if (Test-Path -LiteralPath $sessionPath -PathType Leaf) { throw 'Refusing to replace an existing Chronicle Agent session during the supply baseline.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
$scenarioResults = [System.Collections.Generic.List[object]]::new()
$script:ScenarioClockCommands = @()
$videoLibrary = Join-Path $PSScriptRoot 'HarnessVideoCapture.ps1'
$failure = $null

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    if ($Action -in @('advance','pause','resume','fastForward')) { $script:ScenarioClockCommands += [string]$Action }
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

function Wait-NativeSettlementArrival([string]$SettlementId, [int]$ArrivalTimeoutSeconds = 180) {
    $deadline = [DateTime]::UtcNow.AddSeconds($ArrivalTimeoutSeconds)
    $lastObservation = $null
    while ([DateTime]::UtcNow -lt $deadline) {
        $lastObservation = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-arrival-$([Guid]::NewGuid().ToString('N'))")
        $state = $lastObservation.state
        if ([string]$state.location.currentSettlementId -ceq $SettlementId -and [string]$state.context.menuId -in @('town','town_backstreet','village')) { return $lastObservation }
        if ([bool]$state.context.encounterActive) { throw "Unexpected encounter '$($state.context.encounteredPartyId)' interrupted the deterministic supply route." }
        if (-not [bool]$state.party.isMoving) { throw "The Native party stopped before reaching '$SettlementId'; no clock control will be injected." }
        if ([string]$state.context.timeControlMode -notin @('StoppablePlay','UnstoppableFastForward')) { throw "Campaign time stopped during the Native supply route (mode='$($state.context.timeControlMode)')." }
        Start-Sleep -Seconds 1
    }
    throw "Native travel did not reach '$SettlementId' within $ArrivalTimeoutSeconds seconds; no Harness time step was used."
}

function Write-SupplyCaptureEvent($Capture, [string]$EventName, [string]$Action, [string]$CommandId, $Observation, $Receipt) {
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
    Add-Content -LiteralPath $script:CaptureEventTracePath -Value ($event | ConvertTo-Json -Compress -Depth 6) -Encoding UTF8
}

function Wait-NativeRestCompletion([string]$CommandId, [double]$TargetDay, [int]$WallClockLimitSeconds = 180) {
    $responseRoot = Join-Path (Split-Path -Parent $sessionPath) 'responses'
    $completedPath = Join-Path $responseRoot "$CommandId.completed.json"
    $failedPath = Join-Path $responseRoot "$CommandId.failed.json"
    $deadline = [DateTime]::UtcNow.AddSeconds($WallClockLimitSeconds)
    $nextSampleUtc = [DateTime]::MinValue
    $targetReachedUtc = $null
    $samples = [System.Collections.Generic.List[object]]::new()
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-Path -LiteralPath $completedPath -PathType Leaf) {
            return [pscustomobject]@{ Receipt = (Get-Content -LiteralPath $completedPath -Raw -Encoding UTF8 | ConvertFrom-Json); Samples = @($samples); WallClockElapsedSeconds = $WallClockLimitSeconds - ([Math]::Max(0, ($deadline - [DateTime]::UtcNow).TotalSeconds)) }
        }
        if (Test-Path -LiteralPath $failedPath -PathType Leaf) {
            $failed = Get-Content -LiteralPath $failedPath -Raw -Encoding UTF8 | ConvertFrom-Json
            throw "Native rest command was rejected/failed while waiting: $($failed.error)"
        }
        if ([DateTime]::UtcNow -ge $nextSampleUtc) {
            $observation = Invoke-AgentCli 'state' @('-CommandId', "$CommandId-monitor-$($samples.Count)") 20
            $sample = [ordered]@{
                sampledUtc = [DateTime]::UtcNow.ToString('O')
                campaignDay = [double]$observation.campaignDay
                dailyTickCount = [int]$observation.dailyTickCount
                timeControlMode = [string]$observation.state.context.timeControlMode
                menuId = [string]$observation.state.context.menuId
                isWaiting = [bool]$observation.state.context.isWaiting
                food = [double]$observation.state.party.food
                foodInventory = [int]$observation.state.party.foodInventory
                foodChange = [double]$observation.state.party.foodChange
                dailyWage = [int]$observation.state.party.dailyWage
                gold = [int]$observation.state.economy.gold
                morale = [int]$observation.state.party.morale
                members = [int]$observation.state.party.members
            }
            $samples.Add($sample)
            if ([double]$sample.campaignDay -ge $TargetDay) {
                if (-not $targetReachedUtc) { $targetReachedUtc = [DateTime]::UtcNow }
            }
            elseif ([string]$sample.menuId -ne 'town_wait_menus' -or -not [bool]$sample.isWaiting -or [string]$sample.timeControlMode -notin @('UnstoppableFastForward','UnstoppableFastForwardForPartyWaitTime')) {
                throw "Native Town Wait stopped before its target day; latest sample=$(ConvertTo-Json -InputObject $sample -Compress)."
            }
            if ($targetReachedUtc -and ([DateTime]::UtcNow - $targetReachedUtc).TotalSeconds -gt 15) {
                throw "Native time passed the target day $TargetDay but the rest completion receipt was not written; latest sample=$(ConvertTo-Json -InputObject $sample -Compress)."
            }
            $nextSampleUtc = [DateTime]::UtcNow.AddSeconds(5)
        }
        Start-Sleep -Milliseconds 500
    }
    $lastSample = if ($samples.Count -gt 0) { ConvertTo-Json -InputObject $samples[$samples.Count - 1] -Compress } else { 'no Native state sample' }
    $sampleHistory = ConvertTo-Json -InputObject @($samples) -Depth 6 -Compress
    throw "Native rest did not reach target Campaign day $TargetDay within $WallClockLimitSeconds seconds; last sample=$lastSample; sample history=$sampleHistory."
}

function Invoke-SupplyScenario([string]$Branch, [int]$Repetition) {
    if ($Branch -notin @('noProvision','provision')) { throw "Unsupported supply scenario branch '$Branch'." }
    $script:ScenarioClockCommands = @()
    $prefix = "$runPrefix-$Branch-$Repetition"
    $capture = $null
    $captureResult = $null
    $script:CaptureEventTracePath = $null
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName, '-CommandId', "$prefix-load")
    try {
        if ($start.status -ne 'completed' -or [string]$start.session.processId -eq '') { throw "Native supply scenario '$Branch' failed to load its disposable Campaign." }
        if ($CaptureVisualEvidence) {
            . $videoLibrary
            $captureRoot = if ($env:CHRONICLE_HARNESS_TEMP -and (Test-Path -LiteralPath $env:CHRONICLE_HARNESS_TEMP -PathType Container)) { $env:CHRONICLE_HARNESS_TEMP } else { throw 'Visual supply evidence requires the active Harness TestResults temp directory.' }
            $videoPath = Join-Path $captureRoot "$prefix.mp4"
            $contactSheetPath = Join-Path $captureRoot "$prefix-contact.jpg"
            $script:CaptureEventTracePath = Join-Path $captureRoot "$prefix-events.jsonl"
            Set-Content -LiteralPath $script:CaptureEventTracePath -Value '' -Encoding UTF8
            $capture = Start-ChronicleWindowVideoCapture -ProcessId ([int]$start.session.processId) -OutputPath $videoPath -FrameRate $FrameRate
        }
        $campaignIdentity = Invoke-AgentCli 'agentCheckpointGet' @('-CommandId', "$prefix-campaign-identity")
        if ($campaignIdentity.status -ne 'completed' -or [string]::IsNullOrWhiteSpace([string]$campaignIdentity.data.campaignInstanceId)) { throw 'Native supply fixture did not expose its Campaign instance identity.' }
        $campaignInstanceId = [string]$campaignIdentity.data.campaignInstanceId
        $beforeMove = Invoke-AgentCli 'state' @('-CommandId', "$prefix-before-move")
        Write-SupplyCaptureEvent $capture 'capture-start' 'capture' $null $beforeMove $null
        if ($beforeMove.state.context.gameState -ne 'MapState' -or $beforeMove.state.context.encounterActive) { throw 'Supply baseline must begin on an unobstructed Campaign Map.' }
        $move = $null
        $arrival = $null
        $target = @()
        if ($StartAtCurrentTown -and [string]$beforeMove.state.context.menuId -eq 'town' -and -not [string]::IsNullOrWhiteSpace([string]$beforeMove.state.location.currentSettlementId)) {
            $visibleTargets = Invoke-AgentCli 'mapSettlementTargets' @('-CommandId', "$prefix-current-settlement-targets")
            $target = @($visibleTargets.data.mapSettlementTargets | Where-Object { [string]$_.id -ceq [string]$beforeMove.state.location.currentSettlementId -and $_.type -eq 'town' -and -not $_.hostile -and -not $_.underSiege } | Select-Object -First 1)
            if ($target.Count -ne 1) { throw 'Prepared supply fixture is not at a currently visible, safe Native Town.' }
            $arrival = $beforeMove
            Write-SupplyCaptureEvent $capture 'settlement-already-current' 'state' "$prefix-before-move" $arrival $null
        }
        elseif ($StartAtCurrentTown) {
            $visibleTargets = Invoke-AgentCli 'mapSettlementTargets' @('-CommandId', "$prefix-prepared-map-towns")
            $target = @($visibleTargets.data.mapSettlementTargets | Where-Object { $_.type -eq 'town' -and -not $_.hostile -and -not $_.underSiege } | Sort-Object { [double]$_.distance }, { [string]$_.id } | Select-Object -First 1)
            if ($visibleTargets.status -ne 'completed' -or $target.Count -ne 1) { throw 'Prepared Campaign Map has no currently visible, safe Native Town.' }
            $move = Invoke-AgentCli 'move' @('-SettlementId', [string]$target[0].id, '-CommandId', "$prefix-move-prepared-town")
            Write-SupplyCaptureEvent $capture 'native-action' 'move' "$prefix-move-prepared-town" $beforeMove $move
            if ($move.status -ne 'completed' -or [string]$move.state.location.targetSettlementId -cne [string]$target[0].id) { throw 'Native movement did not accept the nearest currently visible safe Town target from the prepared Campaign Map.' }
            $arrival = Wait-NativeSettlementArrival -SettlementId ([string]$target[0].id) -ArrivalTimeoutSeconds $TimeoutSeconds
            Write-SupplyCaptureEvent $capture 'settlement-arrived' 'state' "$prefix-arrival-prepared-town" $arrival $null
        }
        else {
            $target = @($beforeMove.state.nearbySettlements | Where-Object { $_.type -eq 'town' -and -not $_.hostile -and -not $_.underSiege -and [double]$_.distance -gt 1.0 } | Sort-Object { [double]$_.distance } | Select-Object -First 1)
            if ($target.Count -ne 1) { throw 'No safe visible Town exists for the supply baseline.' }
            $move = Invoke-AgentCli 'move' @('-SettlementId', [string]$target[0].id, '-CommandId', "$prefix-move")
            Write-SupplyCaptureEvent $capture 'native-action' 'move' "$prefix-move" $beforeMove $move
            if ($move.status -ne 'completed' -or [string]$move.state.location.targetSettlementId -cne [string]$target[0].id) { throw 'Native map movement did not accept the current visible Town target.' }
            $arrival = Wait-NativeSettlementArrival -SettlementId ([string]$target[0].id) -ArrivalTimeoutSeconds $TimeoutSeconds
            Write-SupplyCaptureEvent $capture 'settlement-arrived' 'state' "$prefix-arrival" $arrival $null
        }
        $recruitMenuOption = @($arrival.state.availableMenuOptions | Where-Object { $_.id -eq 'recruit_volunteers' -and $_.available -and $_.enabled } | Select-Object -First 1)
        if ([string]$arrival.state.context.menuId -ne 'town' -or ([int]$arrival.state.party.members -lt $TargetPartyMembers -and $recruitMenuOption.Count -ne 1)) { throw 'The arrival must be a Native Town; a recruitment option is required only when the roster still needs recruits.' }

        $recruitReceipts = [System.Collections.Generic.List[object]]::new()
        while ([int]$arrival.state.party.members -lt $TargetPartyMembers) {
            $offers = Invoke-AgentCli 'recruitOptions' @('-CommandId', "$prefix-recruit-options-$($recruitReceipts.Count)")
            if ($offers.status -ne 'completed') { throw 'The Native Town recruitment menu was not available while preparing the fixed supply scenario.' }
            $offer = @($offers.data.offers | Where-Object { $_.available -and [int]$_.cost -le [int]$arrival.state.economy.gold } | Sort-Object { [int]$_.cost },{ [int]$_.slot } | Select-Object -First 1)
            if ($offer.Count -ne 1) { throw "Could not recruit the fixed $TargetPartyMembers-member supply party from currently available Town volunteers." }
            $goldBeforeRecruit = [int]$arrival.state.economy.gold
            $recruit = Invoke-AgentCli 'recruit' @('-OwnerId', [string]$offer[0].ownerId, '-TroopId', [string]$offer[0].troopId, '-VolunteerSlot', [string]$offer[0].slot, '-CommandId', "$prefix-recruit-$($recruitReceipts.Count)")
            $arrival = Invoke-AgentCli 'state' @('-CommandId', "$prefix-after-recruit-$($recruitReceipts.Count)")
            if ($recruit.status -ne 'completed' -or -not [bool]$recruit.data.verified -or [int]$arrival.state.party.members -ne [int]$recruitReceipts.Count + [int]$beforeMove.state.party.members + 1 -or [int]$arrival.state.economy.gold -ne ($goldBeforeRecruit - [int]$offer[0].cost)) {
                throw 'Native volunteer recruitment did not match its current offer/party-size postcondition while preparing the supply fixture.'
            }
            $recruitReceipts.Add([ordered]@{ offer = $offer[0]; receipt = $recruit.data; partyMembersAfter = [int]$arrival.state.party.members; goldAfter = [int]$arrival.state.economy.gold })
        }
        $afterRecruit = $arrival
        $provisionDetails = $null
        $beforeRest = $afterRecruit
        if ($Branch -eq 'provision') {
            $townMenu = Invoke-AgentCli 'menu' @('-CommandId', "$prefix-before-trade-menu")
            $tradeMenuOption = @($townMenu.state.availableMenuOptions | Where-Object { $_.id -eq 'trade' -and $_.available -and $_.enabled } | Select-Object -First 1)
            if ($townMenu.state.context.menuId -ne 'town' -or $tradeMenuOption.Count -ne 1) { throw 'Native Town Trade option was unavailable for the provision branch.' }
            $tradeOpen = Invoke-AgentCli 'menuSelect' @('-MenuId', 'town', '-OptionId', 'trade', '-CommandId', "$prefix-open-trade")
            $tradeState = Invoke-AgentCli 'state' @('-CommandId', "$prefix-trade-state")
            Write-SupplyCaptureEvent $capture 'native-action' 'menuSelect' "$prefix-open-trade" $tradeState $tradeOpen
            if ($tradeOpen.status -ne 'completed' -or $tradeState.state.context.gameState -ne 'InventoryState' -or $tradeState.state.inventoryScreen.mode -ne 'Trade') { throw 'Native Trade InventoryState did not open for the provision branch.' }
            $foodOptions = Invoke-AgentCli 'foodOptions' @('-CommandId', "$prefix-food-options")
            $foodOffer = @($foodOptions.data.offers | Where-Object { $_.stock -gt 0 -and $_.isTransferable -and [double]$_.inventoryLogicUnitPrice -le [int]$tradeState.state.economy.gold } | Sort-Object { [double]$_.inventoryLogicUnitPrice } | Select-Object -First 1)
            if ($foodOffer.Count -ne 1) { throw 'Native Town Trade VM exposed no affordable transferable food candidate.' }
            $affordableAmount = if ([double]$foodOffer[0].inventoryLogicUnitPrice -gt 0) { [int][Math]::Floor([int]$tradeState.state.economy.gold / [double]$foodOffer[0].inventoryLogicUnitPrice) } else { $ProvisionAmount }
            $amount = [Math]::Min($ProvisionAmount, [Math]::Min([int]$foodOffer[0].stock, $affordableAmount))
            if ($amount -lt 1) { throw 'The current Native food offer had no affordable positive purchase amount.' }
            $provision = Invoke-AgentCli 'provision' @('-ItemViewModelId', [string]$foodOffer[0].viewModelItemId, '-Amount', [string]$amount, '-CommandId', "$prefix-provision")
            Write-SupplyCaptureEvent $capture 'native-action' 'provision' "$prefix-provision" $tradeState $provision
            $provisionCommit = Invoke-AgentCli 'tradeConfirm' @('-CommandId', "$prefix-provision-confirm")
            $beforeRest = Invoke-AgentCli 'state' @('-CommandId', "$prefix-after-provision")
            Write-SupplyCaptureEvent $capture 'native-action' 'tradeConfirm' "$prefix-provision-confirm" $beforeRest $provisionCommit
            if ($provision.status -ne 'completed' -or -not [bool]$provisionCommit.data.postconditionPassed -or
                [int]$beforeRest.state.party.foodInventory -le [int]$afterRecruit.state.party.foodInventory -or
                [int]$afterRecruit.state.economy.gold - [int]$beforeRest.state.economy.gold -ne [int]$provision.data.nativeTransactionAmount) {
                throw 'The current Native provision transaction did not produce the measured food/Gold postcondition.'
            }
            $provisionDetails = [ordered]@{ foodOffer = $foodOffer[0]; amount = $amount; draft = $provision.data; commit = $provisionCommit.data }
        }

        $townMenuForWait = Invoke-AgentCli 'menu' @('-CommandId', "$prefix-town-menu")
        $waitOption = @($townMenuForWait.state.availableMenuOptions | Where-Object { $_.id -eq 'town_wait' -and $_.available -and $_.enabled } | Select-Object -First 1)
        if ($townMenuForWait.state.context.menuId -ne 'town' -or $waitOption.Count -ne 1) { throw 'Native Town Wait option was unavailable in the supply scenario.' }
        $waitEntry = Invoke-AgentCli 'menuSelect' @('-MenuId', 'town', '-OptionId', 'town_wait', '-CommandId', "$prefix-enter-wait")
        $waitStart = Invoke-AgentCli 'state' @('-CommandId', "$prefix-wait-start")
        Write-SupplyCaptureEvent $capture 'native-action' 'menuSelect' "$prefix-enter-wait" $waitStart $waitEntry
        if ($waitEntry.status -ne 'completed' -or $waitStart.state.context.menuId -ne 'town_wait_menus' -or -not [bool]$waitStart.state.context.isWaiting) { throw 'The Native Town Wait menu did not enter its actual waiting state.' }
        $restCommandId = "$prefix-native-rest"
        $restAccepted = Invoke-AgentCli 'rest' @('-Days', [string]$RestDays, '-CommandId', $restCommandId, '-ReturnWhenAccepted') 20
        Write-SupplyCaptureEvent $capture 'native-action' 'rest' $restCommandId $waitStart $restAccepted
        if ($restAccepted.status -ne 'accepted') { throw "Native rest did not accept the requested $RestDays-day wait: $($restAccepted.error)" }
        $restMonitor = Wait-NativeRestCompletion -CommandId $restCommandId -TargetDay ([double]$restAccepted.campaignDay + $RestDays) -WallClockLimitSeconds $RestWallClockLimitSeconds
        $rest = $restMonitor.Receipt
        $afterRest = Invoke-AgentCli 'state' @('-CommandId', "$prefix-after-rest")
        $waitMenu = Invoke-AgentCli 'menu' @('-CommandId', "$prefix-wait-menu")
        $leaveOption = @($waitMenu.state.availableMenuOptions | Where-Object { $_.id -eq 'wait_leave' -and $_.available -and $_.enabled } | Select-Object -First 1)
        if ($leaveOption.Count -ne 1) { throw 'The Native Wait menu did not expose an enabled leave option after rest elapsed.' }
        $leave = Invoke-AgentCli 'menuSelect' @('-MenuId', 'town_wait_menus', '-OptionId', 'wait_leave', '-CommandId', "$prefix-leave-wait")
        $final = Invoke-AgentCli 'state' @('-CommandId', "$prefix-final-state")
        Write-SupplyCaptureEvent $capture 'native-action' 'menuSelect' "$prefix-leave-wait" $final $leave
        Write-SupplyCaptureEvent $capture 'capture-end' 'capture' $null $final $null
        if ($capture) {
            $captureResult = Stop-ChronicleWindowVideoCapture -Capture $capture -ContactSheetPath $contactSheetPath -EventTracePath $script:CaptureEventTracePath
            $capture = $null
        }
        $stop = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-stop") 30
        $elapsedDays = [double]$afterRest.campaignDay - [double]$waitStart.campaignDay
        $scenarioPassed = (
            $rest.status -eq 'completed' -and
            $elapsedDays -ge ($RestDays - 0.01) -and
            [int]$afterRest.dailyTickCount -ge ([int]$waitStart.dailyTickCount + $RestDays) -and
            [string]$afterRest.state.context.timeControlMode -eq [string]$waitStart.state.context.timeControlMode -and
            $leave.status -eq 'completed' -and [string]$final.state.context.menuId -eq 'town'
        )
        if ($CaptureVisualEvidence) { $scenarioPassed = $scenarioPassed -and $captureResult -and [double]$captureResult.FrameCoverageRatio -ge 0.9 -and [bool]$captureResult.VideoRemovedAfterEvidence }
        $result = [ordered]@{
            Branch = $Branch
            Repetition = $Repetition
            CampaignInstanceId = $campaignInstanceId
            StartAtCurrentTown = $StartAtCurrentTown
            NativeMoveIssued = ($null -ne $move)
            Capture = $captureResult
            TemplateSaveHash = $fixtureHashBefore
            ModuleSet = @($start.session.moduleSet)
            TargetSettlement = $target[0]
            InitialState = [ordered]@{ CampaignDay = $beforeMove.campaignDay; Members = $beforeMove.state.party.members; Gold = $beforeMove.state.economy.gold; Food = $beforeMove.state.party.food; FoodInventory = $beforeMove.state.party.foodInventory; FoodChange = $beforeMove.state.party.foodChange; DailyWage = $beforeMove.state.party.dailyWage }
            PartyAfterNativeRecruitment = [ordered]@{ CampaignDay = $afterRecruit.campaignDay; DailyTickCount = $afterRecruit.dailyTickCount; Members = $afterRecruit.state.party.members; Gold = $afterRecruit.state.economy.gold; Food = $afterRecruit.state.party.food; FoodInventory = $afterRecruit.state.party.foodInventory; FoodChange = $afterRecruit.state.party.foodChange; DailyWage = $afterRecruit.state.party.dailyWage; Receipts = @($recruitReceipts) }
            Provision = $provisionDetails
            BeforeRest = [ordered]@{ CampaignDay = $waitStart.campaignDay; DailyTickCount = $waitStart.dailyTickCount; TimeControlMode = $waitStart.state.context.timeControlMode; IsWaiting = $waitStart.state.context.isWaiting; Members = $waitStart.state.party.members; Gold = $waitStart.state.economy.gold; Food = $waitStart.state.party.food; FoodInventory = $waitStart.state.party.foodInventory; FoodChange = $waitStart.state.party.foodChange; DailyWage = $waitStart.state.party.dailyWage; Morale = $waitStart.state.party.morale }
            RestReceipt = [ordered]@{ Status = $rest.status; CampaignDay = $rest.campaignDay; TimeControlMode = $rest.state.context.timeControlMode; DaysRequested = $RestDays; DaysElapsed = $elapsedDays; WallClockElapsedSeconds = $restMonitor.WallClockElapsedSeconds; PollSamples = @($restMonitor.Samples); RawModePreserved = ([string]$rest.state.context.timeControlMode -ceq [string]$waitStart.state.context.timeControlMode) }
            AfterRest = [ordered]@{ CampaignDay = $afterRest.campaignDay; DailyTickCount = $afterRest.dailyTickCount; TimeControlMode = $afterRest.state.context.timeControlMode; IsWaiting = $afterRest.state.context.isWaiting; Members = $afterRest.state.party.members; Gold = $afterRest.state.economy.gold; Food = $afterRest.state.party.food; FoodInventory = $afterRest.state.party.foodInventory; FoodChange = $afterRest.state.party.foodChange; DailyWage = $afterRest.state.party.dailyWage; Morale = $afterRest.state.party.morale }
            FinalState = [ordered]@{ CampaignDay = $final.campaignDay; TimeControlMode = $final.state.context.timeControlMode; MenuId = $final.state.context.menuId; Members = $final.state.party.members; Gold = $final.state.economy.gold; Food = $final.state.party.food; FoodInventory = $final.state.party.foodInventory; FoodChange = $final.state.party.foodChange; DailyWage = $final.state.party.dailyWage; Morale = $final.state.party.morale }
            ClockControlActions = @($script:ScenarioClockCommands)
            NoHarnessClockActionsUsed = (@($script:ScenarioClockCommands).Count -eq 0)
            ProcessStopped = [bool]$stop.processStopped
            Passed = $scenarioPassed
        }
        return $result
    }
    finally {
        if ($capture) {
            try {
                $fallbackEvent = [ordered]@{ event = 'capture-end'; utc = [DateTimeOffset]::UtcNow.ToString('O'); offsetMilliseconds = 0; commandId = $null; action = 'capture'; decisionAction = ''; gameState = $null; menuId = $null; partyScreenMode = $null; inventoryMode = $null; campaignDay = $null }
                Add-Content -LiteralPath $script:CaptureEventTracePath -Value ($fallbackEvent | ConvertTo-Json -Compress) -Encoding UTF8
                $null = Stop-ChronicleWindowVideoCapture -Capture $capture -ContactSheetPath (Join-Path $env:CHRONICLE_HARNESS_TEMP "$prefix-contact.jpg") -EventTracePath $script:CaptureEventTracePath
            } catch { }
        }
        if (Test-Path -LiteralPath $sessionPath -PathType Leaf) { try { Invoke-AgentCli 'stop' @('-CommandId', "$prefix-cleanup") 15 | Out-Null } catch { } }
    }
}

try {
    for ($repetition = 1; $repetition -le $Repetitions; $repetition++) {
        $scenarioResults.Add((Invoke-SupplyScenario 'noProvision' $repetition))
        $scenarioResults.Add((Invoke-SupplyScenario 'provision' $repetition))
    }
}
catch { $failure = $_.Exception.ToString() }
finally {
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $pairedComparisons = @()
    foreach ($repetition in 1..$Repetitions) {
        $noProvisionRun = @($scenarioResults | Where-Object { $_.Branch -eq 'noProvision' -and [int]$_.Repetition -eq $repetition } | Select-Object -First 1)
        $provisionRun = @($scenarioResults | Where-Object { $_.Branch -eq 'provision' -and [int]$_.Repetition -eq $repetition } | Select-Object -First 1)
        if ($noProvisionRun.Count -ne 1 -or $provisionRun.Count -ne 1) { continue }
        $control = $noProvisionRun[0]
        $treated = $provisionRun[0]
        $startingDayDelta = [Math]::Abs([double]$treated.BeforeRest.CampaignDay - [double]$control.BeforeRest.CampaignDay)
        $startingDayMatched = ($startingDayDelta -le 0.05 -and [int]$treated.BeforeRest.DailyTickCount -eq [int]$control.BeforeRest.DailyTickCount)
        $sameCampaignInstance = [string]$treated.CampaignInstanceId -ceq [string]$control.CampaignInstanceId
        $startingSetupMatched = ([int]$treated.PartyAfterNativeRecruitment.Members -eq [int]$control.PartyAfterNativeRecruitment.Members -and
            [int]$treated.PartyAfterNativeRecruitment.Gold -eq [int]$control.PartyAfterNativeRecruitment.Gold -and
            [int]$treated.PartyAfterNativeRecruitment.FoodInventory -eq [int]$control.PartyAfterNativeRecruitment.FoodInventory -and
            [Math]::Abs([double]$treated.PartyAfterNativeRecruitment.Food - [double]$control.PartyAfterNativeRecruitment.Food) -le 0.01)
        $noProvisionStressObserved = (
            [double]$control.AfterRest.Food -lt [double]$control.BeforeRest.Food -or
            [int]$control.AfterRest.FoodInventory -lt [int]$control.BeforeRest.FoodInventory -or
            [int]$control.AfterRest.Morale -lt [int]$control.BeforeRest.Morale -or
            [int]$control.AfterRest.Members -lt [int]$control.BeforeRest.Members
        )
        $provisionMitigationObserved = (
            [double]$treated.AfterRest.Food -gt [double]$control.AfterRest.Food -or
            [int]$treated.AfterRest.FoodInventory -gt [int]$control.AfterRest.FoodInventory -or
            [int]$treated.AfterRest.Morale -gt [int]$control.AfterRest.Morale -or
            [int]$treated.AfterRest.Members -gt [int]$control.AfterRest.Members
        )
        $pairedComparisons += [ordered]@{
            Repetition = $repetition
            CampaignInstanceMatched = $sameCampaignInstance
            StartingSetupMatched = $startingSetupMatched
            StartingCampaignDayDelta = [Math]::Round(([double]$treated.BeforeRest.CampaignDay - [double]$control.BeforeRest.CampaignDay),6)
            StartingCampaignDayMatched = $startingDayMatched
            NoProvisionStressObserved = $noProvisionStressObserved
            ProvisionMitigationObserved = $provisionMitigationObserved
            NoProvisionFoodDelta = [Math]::Round(([double]$control.AfterRest.Food - [double]$control.BeforeRest.Food),6)
            ProvisionFoodDelta = [Math]::Round(([double]$treated.AfterRest.Food - [double]$treated.BeforeRest.Food),6)
            NoProvisionFoodInventoryDelta = [int]$control.AfterRest.FoodInventory - [int]$control.BeforeRest.FoodInventory
            ProvisionFoodInventoryDelta = [int]$treated.AfterRest.FoodInventory - [int]$treated.BeforeRest.FoodInventory
        }
    }
    $scenarioContrastObserved = ($pairedComparisons.Count -eq $Repetitions -and @($pairedComparisons | Where-Object { -not $_.StartingSetupMatched -or -not $_.StartingCampaignDayMatched -or -not $_.NoProvisionStressObserved -or -not $_.ProvisionMitigationObserved }).Count -eq 0)
    $result = [ordered]@{
        ProviderKind = 'deterministic Native-action baseline; not a real-model autonomy run'
        LoadSaveName = $LoadSaveName
        Repetitions = $Repetitions
        RestDays = $RestDays
        TargetPartyMembers = $TargetPartyMembers
        ProvisionAmount = $ProvisionAmount
        FixtureHashBefore = $fixtureHashBefore
        FixtureHashAfter = $fixtureHashAfter
        FixtureUnchanged = ($fixtureHashBefore -ceq $fixtureHashAfter)
        Scenarios = @($scenarioResults)
        PairedComparisons = @($pairedComparisons)
        ScenarioContrastObserved = $scenarioContrastObserved
        Failure = $failure
        Passed = ($null -eq $failure -and $scenarioResults.Count -eq ($Repetitions * 2) -and @($scenarioResults | Where-Object { -not $_.Passed -or -not $_.ProcessStopped -or -not $_.NoHarnessClockActionsUsed }).Count -eq 0 -and $scenarioContrastObserved -and $fixtureHashBefore -ceq $fixtureHashAfter)
    }
    $json = $result | ConvertTo-Json -Depth 16
    if ($env:CHRONICLE_HARNESS_TEMP -and (Test-Path -LiteralPath $env:CHRONICLE_HARNESS_TEMP -PathType Container)) {
        Set-Content -LiteralPath (Join-Path $env:CHRONICLE_HARNESS_TEMP 'MultiDaySupplyBaselineResult.json') -Value $json -Encoding UTF8
    }
    $json
    if (-not $result.Passed) { exit 1 }
}
