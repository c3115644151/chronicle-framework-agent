[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [ValidateSet('Retreat','PostBattle')][string]$Scenario = 'Retreat',
    [switch]$CaptureFrames,
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
if (-not (Test-Path $savePath)) { throw "Disposable battle fixture save not found: $savePath" }
if (Get-Process Bannerlord -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash $savePath -Algorithm SHA256).Hash
$priorMode = $env:CHRONICLE_HARNESS_MODE
$env:CHRONICLE_HARNESS_MODE = if ($Scenario -eq 'PostBattle') { 'visual-battle-fixture' } else { 'battle-fixture' }
$prefix = 'battlefixture-' + [Guid]::NewGuid().ToString('N')
$runDirectory = if ($env:CHRONICLE_HARNESS_TEMP) { Split-Path -Parent $env:CHRONICLE_HARNESS_TEMP } else { Join-Path $PSScriptRoot 'TestResults\ManualBattleFixture' }
$script:VisualFrames = @()
$script:VideoCapture = $null
$script:VideoCaptureActive = $false
$script:VideoCaptureEventsPath = Join-Path $runDirectory 'BattleToLoot-events.jsonl'
$script:VideoCaptureStartedTicks = 0
$script:VideoCaptureFrequency = [Diagnostics.Stopwatch]::Frequency
$videoPath = Join-Path $runDirectory 'BattleToLoot.mp4'
$videoContactSheetPath = Join-Path $runDirectory 'BattleToLoot-contact.jpg'

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @()) {
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli $Action @Arguments -TimeoutSeconds $TimeoutSeconds -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { $receipt = $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
    if ($script:VideoCaptureActive) { Write-BattleCaptureEvent 'agent-command' $receipt }
    return $receipt
}

function Write-BattleCaptureEvent([string]$EventName, $Receipt) {
    $nowTicks = [Diagnostics.Stopwatch]::GetTimestamp()
    $state = if ($Receipt -and $Receipt.state) { $Receipt.state } else { $null }
    $event = [ordered]@{
        event = $EventName
        utc = (Get-Date).ToUniversalTime().ToString('O')
        stopwatchTicks = $nowTicks
        offsetMilliseconds = [Math]::Round(($nowTicks - $script:VideoCaptureStartedTicks) * 1000.0 / $script:VideoCaptureFrequency, 2)
        commandId = if ($Receipt) { [string]$Receipt.commandId } else { $null }
        action = if ($Receipt) { [string]$Receipt.action } else { $null }
        status = if ($Receipt) { [string]$Receipt.status } else { $null }
        gameState = if ($state) { [string]$state.context.gameState } else { $null }
        menuId = if ($state) { [string]$state.context.menuId } else { $null }
        partyScreenMode = if ($state -and $state.partyScreen) { [string]$state.partyScreen.mode } else { $null }
        inventoryMode = if ($state -and $state.inventoryScreen) { [string]$state.inventoryScreen.mode } else { $null }
        campaignDay = if ($Receipt) { $Receipt.campaignDay } else { $null }
    }
    $line = [Text.UTF8Encoding]::new($false).GetBytes(($event | ConvertTo-Json -Compress -Depth 5) + [Environment]::NewLine)
    for ($attempt = 0; $attempt -lt 6; $attempt++) {
        $stream = $null
        try {
            $stream = [IO.File]::Open($script:VideoCaptureEventsPath, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
            $stream.Write($line, 0, $line.Length)
            return
        }
        catch [IO.IOException] {
            if ($attempt -eq 5) { throw }
            Start-Sleep -Milliseconds (25 * ($attempt + 1))
        }
        finally {
            if ($null -ne $stream) { $stream.Dispose() }
        }
    }
}

function Capture-BattleFrame([string]$FrameName, $Observation) {
    if (-not $CaptureFrames) { return }
    $tempPath = Join-Path $env:CHRONICLE_HARNESS_TEMP ($FrameName + '.bmp')
    $outputPath = Join-Path $runDirectory ($FrameName + '.bmp')
    if (Test-Path $tempPath) { Remove-Item -LiteralPath $tempPath -Force }
    $receipt = Invoke-AgentCli 'captureFrame' @('-OutputPath', $tempPath, '-CommandId', "$prefix-frame-$FrameName")
    if ($receipt.status -ne 'completed') { throw "Native frame capture '$FrameName' was rejected: $($receipt.error)" }
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path $tempPath) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
    if (-not (Test-Path $tempPath) -or (Get-Item $tempPath).Length -lt 4096) { throw "Native frame '$FrameName' was not written by the game engine." }
    Move-Item -LiteralPath $tempPath -Destination $outputPath -Force
    $script:VisualFrames += [ordered]@{
        frame = $FrameName
        capturedUtc = (Get-Date).ToUniversalTime().ToString('O')
        gameState = [string]$Observation.state.context.gameState
        menuId = if ([string]$Observation.state.context.gameState -eq 'MapState') { [string]$Observation.state.context.menuId } else { $null }
        partyScreenMode = if ($Observation.state.partyScreen) { [string]$Observation.state.partyScreen.mode } else { $null }
        inventoryMode = if ($Observation.state.inventoryScreen) { [string]$Observation.state.inventoryScreen.mode } else { $null }
        path = $outputPath
    }
}

try {
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $initial = Invoke-AgentCli 'state' @('-CommandId', "$prefix-initial")
    $enemy = @($initial.state.nearbyParties | Where-Object { $_.id -eq 'chronicle_harness_looters' -and $_.hostile })
    if ($enemy.Count -ne 1) { throw 'Harness did not create one visible, hostile native looter party at the disposable encounter position.' }

    $pursuit = Invoke-AgentCli 'pursue' @('-PartyId', 'chronicle_harness_looters', '-CommandId', "$prefix-pursue")
    if ($pursuit.status -ne 'completed' -or $pursuit.state.location.targetPartyId -ne 'chronicle_harness_looters') {
        throw 'Native pursue command did not target the disposable hostile party.'
    }
    $pursuitStartDay = [double]$pursuit.campaignDay
    $last = $pursuit
    $encounter = $false
    $deadline = [DateTime]::UtcNow.AddSeconds([Math]::Min(60, $TimeoutSeconds))
    while ([DateTime]::UtcNow -lt $deadline) {
        $last = Invoke-AgentCli 'state' @('-CommandId', "$prefix-observe-$([Guid]::NewGuid().ToString('N'))")
        if ($last.state.context.encounterActive -and $last.state.context.encounteredPartyId -eq 'chronicle_harness_looters') { $encounter = $true; break }
        if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'Campaign process exited before the native hostile encounter.' }
        Start-Sleep -Milliseconds 500
    }
    if (-not $encounter) { throw 'Native pursuit did not reach the disposable hostile encounter in time.' }

    $dialogueChoices = @()
    for ($step = 1; $step -le 8; $step++) {
        if ($last.state.context.menuId -eq 'encounter') { break }
        $conversation = $last.state.context.conversation
        if ($null -eq $conversation) {
            $last = Invoke-AgentCli 'state' @('-CommandId', "$prefix-dialogue-observe-$step")
            if ($last.state.context.menuId -eq 'encounter') { break }
            $conversation = $last.state.context.conversation
        }
        if ($null -eq $conversation) {
            if ($last.state.context.gameState -match 'Mission') { throw 'Encounter dialogue transitioned to a 3D Mission; Campaign encounter options are not active.' }
            Start-Sleep -Milliseconds 750
            $last = Invoke-AgentCli 'state' @('-CommandId', "$prefix-dialogue-empty-$step")
            continue
        }
        if (@($conversation.options).Count -eq 0) {
            if ($last.state.context.gameState -match 'Mission') { throw 'Native encounter dialogue transitioned to a 3D Mission instead of the campaign encounter menu.' }
            if (-not [string]::IsNullOrWhiteSpace([string]$conversation.sentenceText)) {
                $last = Invoke-AgentCli 'dialogueContinue' @('-CommandId', "$prefix-dialogue-continue-$step")
            }
            else {
                Start-Sleep -Milliseconds 500
                $last = Invoke-AgentCli 'state' @('-CommandId', "$prefix-dialogue-wait-$step")
            }
            continue
        }
        $choice = @($conversation.options | Where-Object { $_.clickable -and $_.id -in @('common_encounter_ultimatum','common_bandit_surrender_declined') } | Select-Object -First 1)
        if ($choice.Count -ne 1) { throw "Expected a sourced hostile/ultimatum choice; available IDs: $(($conversation.options | ForEach-Object id) -join ',')." }
        $dialogueChoices += [string]$choice[0].id
        $last = Invoke-AgentCli 'dialogueSelect' @('-OptionId', [string]$choice[0].id, '-CommandId', "$prefix-dialogue-$step")
    }

    $encounterMenu = Invoke-AgentCli 'menu' @('-CommandId', "$prefix-menu")
    if ($encounterMenu.state.context.menuId -ne 'encounter') { throw "Expected native encounter menu; found '$($encounterMenu.state.context.menuId)'." }
    $sendTroops = @($encounterMenu.state.availableMenuOptions | Where-Object { $_.id -eq 'str_order_attack' -and $_.available -and $_.enabled })
    if ($sendTroops.Count -ne 1) { throw 'The native encounter menu did not expose enabled Send troops.' }
    if ($Scenario -eq 'PostBattle' -and $CaptureFrames) {
        . (Join-Path $PSScriptRoot 'HarnessVideoCapture.ps1')
        Set-Content -LiteralPath $script:VideoCaptureEventsPath -Value '' -Encoding UTF8
        $script:VideoCapture = Start-ChronicleWindowVideoCapture -ProcessId ([int]$start.session.processId) -OutputPath $videoPath -FrameRate 30
        $script:VideoCaptureStartedTicks = $script:VideoCapture.StartedTicks
        $script:VideoCaptureFrequency = $script:VideoCapture.StopwatchFrequency
        $script:VideoCaptureActive = $true
        Write-BattleCaptureEvent 'capture-start' $encounterMenu
    }
    $simulationStart = Invoke-AgentCli 'menuSelect' @('-MenuId', 'encounter', '-OptionId', 'str_order_attack', '-CommandId', "$prefix-send-troops")
    if ($null -eq $simulationStart.state.context.battleSimulation) { throw 'Native Send troops did not expose an active BattleSimulation.' }
    $simulationPause = Invoke-AgentCli 'battlePause' @('-CommandId', "$prefix-simulation-pause")
    if ($simulationPause.status -ne 'completed' -or $null -eq $simulationPause.state.context.battleSimulation) { throw 'Native BattleSimulation pause did not return an active simulation state.' }
    $retreatedState = $null
    $simulationRetreat = $null
    $missionEntered = $false
    $missionRetreat = $null
    $missionReturnedToCampaign = $false
    $simulationFinished = $false
    $simulationFinish = $null
    $postBattleMenu = $null
    $postBattleTransition = $false
    $partyDone = $null
    $inventoryScreenObserved = $false
    $inventoryLootItemCountBefore = 0
    $inventoryLootItemCountAfter = 0
    $inventoryPlayerItemCountBefore = 0
    $inventoryPlayerItemCountAfter = 0
    $inventoryItemsTransferred = 0
    $inventoryDoneStatus = $null
    $inventoryReturnedToMap = $false
    $partyLootBefore = $null
    $partyLootAfterTransfer = $null
    $partyLootTransfersVerified = $false
    $partyLootTransferCounts = $null
    if ($Scenario -eq 'Retreat') {
        $simulationRetreat = Invoke-AgentCli 'battleRetreat' @('-CommandId', "$prefix-simulation-retreat")
        $retreatedState = $simulationRetreat.state.context.battleSimulation
        if ($simulationRetreat.status -ne 'completed' -or $null -eq $retreatedState -or -not $retreatedState.playerRetreated) { throw 'Native BattleSimulation retreat callback did not set its retreat state.' }
        if (-not $simulationRetreat.state.context.encounterActive) { throw 'Simulation retreat did not return the campaign encounter.' }

        $afterSimulationMenu = Invoke-AgentCli 'menu' @('-CommandId', "$prefix-after-simulation-menu")
        $attackOption = @($afterSimulationMenu.state.availableMenuOptions | Where-Object { $_.id -eq 'attack' -and $_.available -and $_.enabled })
        if ($attackOption.Count -ne 1) { throw 'Native encounter menu did not expose enabled manual attack after simulated retreat.' }
        $manualAttack = Invoke-AgentCli 'menuSelect' @('-MenuId', 'encounter', '-OptionId', 'attack', '-CommandId', "$prefix-manual-attack")
        $missionState = $manualAttack.state
        $missionDeadline = [DateTime]::UtcNow.AddSeconds([Math]::Min(45, $TimeoutSeconds))
        while ([DateTime]::UtcNow -lt $missionDeadline) {
            $missionState = Invoke-AgentCli 'state' @('-CommandId', "$prefix-mission-observe-$([Guid]::NewGuid().ToString('N'))")
            if ([string]$missionState.state.context.gameState -match 'Mission') { $missionEntered = $true; break }
            if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'Campaign process exited before the native battle mission became active.' }
            Start-Sleep -Milliseconds 500
        }
        if (-not $missionEntered) { throw "Manual attack did not enter a battle mission; gameState='$($missionState.state.context.gameState)', menu='$($missionState.state.context.menuId)'." }
        $missionRetreat = Invoke-AgentCli 'missionRetreat' @('-CommandId', "$prefix-mission-retreat")
        if ($missionRetreat.status -ne 'completed' -or -not $missionRetreat.data.missionEnded) { throw 'Native BattleEndLogic retreat did not end the battle mission.' }
        $campaignReturn = $missionRetreat
        $returnDeadline = [DateTime]::UtcNow.AddSeconds([Math]::Min(45, $TimeoutSeconds))
        while ([DateTime]::UtcNow -lt $returnDeadline -and ([string]$campaignReturn.state.context.gameState) -match 'Mission') {
            Start-Sleep -Milliseconds 250
            $campaignReturn = Invoke-AgentCli 'state' @('-CommandId', "$prefix-return-observe-$([Guid]::NewGuid().ToString('N'))")
        }
        $missionReturnedToCampaign = [string]$campaignReturn.state.context.gameState -notmatch 'Mission'
        if (-not $missionReturnedToCampaign) { throw "Native retreat ended the Mission but did not return to the campaign state; gameState='$($campaignReturn.state.context.gameState)'." }
    }
    else {
        $skipResult = Invoke-AgentCli 'battleSkip' @('-CommandId', "$prefix-simulation-skip")
        if ($skipResult.status -ne 'completed') { throw 'Native BattleSimulation skip action was not accepted.' }
        $simulationState = $skipResult
        $finishDeadline = [DateTime]::UtcNow.AddSeconds([Math]::Min(45, $TimeoutSeconds))
        while ([DateTime]::UtcNow -lt $finishDeadline) {
            $simulationState = Invoke-AgentCli 'state' @('-CommandId', "$prefix-simulation-observe-$([Guid]::NewGuid().ToString('N'))")
            if ($simulationState.state.context.battleSimulation.finished) { $simulationFinished = $true; break }
            Start-Sleep -Milliseconds 250
        }
        if (-not $simulationFinished) { throw 'Native BattleSimulation skip did not produce a completed result.' }
        Capture-BattleFrame 'loot-01-simulation-result' $simulationState
        $lootFixtureSeed = Invoke-AgentCli 'seedVisualLoot' @('-CommandId', "$prefix-seed-visual-loot")
        if ($lootFixtureSeed.status -ne 'completed' -or $lootFixtureSeed.data.naturalDrop -ne $false -or [int]$lootFixtureSeed.data.count -le 0) {
            throw 'Deterministic visual loot seed was not accepted after native autoresolve; this is fixture-only and does not claim a natural item drop.'
        }
        $simulationFinish = Invoke-AgentCli 'battleFinish' @('-CommandId', "$prefix-simulation-finish")
        if ($simulationFinish.status -ne 'completed' -or -not $simulationFinish.state.context.encounterActive) { throw 'Finished BattleSimulation did not return to the native encounter menu.' }
        $postBattleState = Invoke-AgentCli 'state' @('-CommandId', "$prefix-post-battle-state")
        $partyScreenObserved = ($postBattleState.state.context.gameState -eq 'PartyState' -and $postBattleState.state.partyScreen.mode -eq 'Loot')
        if (-not $partyScreenObserved) {
            throw "Native BattleSimulation Done did not directly enter PartyState aftermath; gameState='$($postBattleState.state.context.gameState)', menu='$($postBattleState.state.context.menuId)' lootItems=$($postBattleState.state.context.lootItemCount). Do not force Leave here."
        }
        Capture-BattleFrame 'loot-02-party-aftermath' $postBattleState
        if ($partyScreenObserved) {
            $partyLootBefore = $postBattleState.state.partyScreen
            $leftMemberCount = @($partyLootBefore.leftMembers | Where-Object { $_.count -gt 0 -and $_.transferable }).Count
            $leftPrisonerCount = @($partyLootBefore.leftPrisoners | Where-Object { $_.count -gt 0 -and $_.transferable }).Count
            if ($leftMemberCount -gt 0) {
                $postBattleState = Invoke-AgentCli 'partyTakeAll' @('-LootType', 'members', '-CommandId', "$prefix-loot-members")
            }
            if ($leftPrisonerCount -gt 0) {
                $postBattleState = Invoke-AgentCli 'partyTakeAll' @('-LootType', 'prisoners', '-CommandId', "$prefix-loot-prisoners")
            }
            $partyLootAfterTransfer = $postBattleState.state.partyScreen
            $countRoster = {
                param($Roster)
                $total = 0
                foreach ($entry in @($Roster)) { $total += [int]$entry.count }
                return $total
            }
            $memberTransferred = (& $countRoster $partyLootBefore.leftMembers) - (& $countRoster $partyLootAfterTransfer.leftMembers)
            $prisonerTransferred = (& $countRoster $partyLootBefore.leftPrisoners) - (& $countRoster $partyLootAfterTransfer.leftPrisoners)
            $memberReceived = (& $countRoster $partyLootAfterTransfer.rightMembers) - (& $countRoster $partyLootBefore.rightMembers)
            $prisonerReceived = (& $countRoster $partyLootAfterTransfer.rightPrisoners) - (& $countRoster $partyLootBefore.rightPrisoners)
            $partyLootTransferCounts = [ordered]@{
                transferableMemberEntries = $leftMemberCount
                transferablePrisonerEntries = $leftPrisonerCount
                membersRemovedFromLoot = $memberTransferred
                membersAddedToParty = $memberReceived
                prisonersRemovedFromLoot = $prisonerTransferred
                prisonersAddedToParty = $prisonerReceived
            }
            $partyLootTransfersVerified = (($leftMemberCount -eq 0 -or ($memberTransferred -gt 0 -and $memberTransferred -eq $memberReceived)) -and ($leftPrisonerCount -eq 0 -or ($prisonerTransferred -gt 0 -and $prisonerTransferred -eq $prisonerReceived)) -and ($leftMemberCount + $leftPrisonerCount -gt 0))
            if (-not $partyLootTransfersVerified) { throw 'Native PartyScreen transfer did not move the full transferable count from loot side to player party.' }
            $partyDone = Invoke-AgentCli 'partyScreenDone' @('-CommandId', "$prefix-party-done")
            if ($partyDone.status -ne 'completed') { throw 'Native PartyScreen Done handler did not accept the postbattle screen.' }
            $postBattleState = Invoke-AgentCli 'state' @('-CommandId', "$prefix-after-party-done")
            if ($postBattleState.state.context.gameState -eq 'PartyState' -and $postBattleState.state.partyScreen.mode -eq 'Loot') {
                throw 'Native PartyScreen Done did not advance beyond the Aftermath state.'
            }
            $inventoryScreenObserved = ($postBattleState.state.context.gameState -eq 'InventoryState' -and $postBattleState.state.inventoryScreen.mode -eq 'Loot')
            if (-not $inventoryScreenObserved) { throw "Native loot item screen was not entered; gameState='$($postBattleState.state.context.gameState)', inventory=$($postBattleState.state.inventoryScreen | ConvertTo-Json -Compress)." }
            $inventoryLootItemCountBefore = [int]$postBattleState.state.inventoryScreen.lootItemCount
            $inventoryPlayerItemCountBefore = [int]$postBattleState.state.inventoryScreen.playerItemCount
            if ($inventoryLootItemCountBefore -le 0) { throw 'Loot InventoryState opened without any item loot to observe.' }
            Capture-BattleFrame 'loot-03-inventory-screen' $postBattleState
            $inventoryTakeAll = Invoke-AgentCli 'inventoryTakeAll' @('-CommandId', "$prefix-inventory-take-all")
            if ($inventoryTakeAll.status -ne 'completed') { throw 'Native InventoryState Loot All handler did not complete.' }
            $afterInventoryTakeAll = Invoke-AgentCli 'state' @('-CommandId', "$prefix-after-inventory-take-all")
            if ($afterInventoryTakeAll.state.context.gameState -ne 'InventoryState' -or $afterInventoryTakeAll.state.inventoryScreen.mode -ne 'Loot') { throw 'Taking loot unexpectedly left the InventoryState before Done.' }
            $inventoryLootItemCountAfter = [int]$afterInventoryTakeAll.state.inventoryScreen.lootItemCount
            $inventoryPlayerItemCountAfter = [int]$afterInventoryTakeAll.state.inventoryScreen.playerItemCount
            $inventoryItemsTransferred = $inventoryPlayerItemCountAfter - $inventoryPlayerItemCountBefore
            if ($inventoryLootItemCountAfter -ne 0 -or $inventoryItemsTransferred -lt $inventoryLootItemCountBefore) { throw "Native Loot All did not move all items: left=$inventoryLootItemCountAfter, playerDelta=$inventoryItemsTransferred, initial=$inventoryLootItemCountBefore." }
            Capture-BattleFrame 'loot-04-inventory-after-take-all' $afterInventoryTakeAll
            $inventoryDone = Invoke-AgentCli 'inventoryDone' @('-CommandId', "$prefix-inventory-done")
            $inventoryDoneStatus = [string]$inventoryDone.status
            if ($inventoryDoneStatus -ne 'completed') { throw 'Native InventoryLogic Done path did not accept the Loot screen.' }
            $postBattleState = Invoke-AgentCli 'state' @('-CommandId', "$prefix-after-inventory-done")
            $inventoryReturnedToMap = ($postBattleState.state.context.gameState -eq 'MapState' -and -not $postBattleState.state.context.encounterActive)
            if (-not $inventoryReturnedToMap) { throw "Closing InventoryState did not return to campaign MapState; gameState='$($postBattleState.state.context.gameState)' encounter=$($postBattleState.state.context.encounterActive)." }
            Capture-BattleFrame 'loot-05-map-return' $postBattleState
            if ($script:VideoCapture) {
                $script:VideoCaptureActive = $false
                Write-BattleCaptureEvent 'capture-end' $postBattleState
                $videoCaptureResult = Stop-ChronicleWindowVideoCapture -Capture $script:VideoCapture -ContactSheetPath $videoContactSheetPath -EventTracePath $script:VideoCaptureEventsPath
                $script:VideoCapture = $null
                $videoCaptureResult | Add-Member -NotePropertyName EventTracePath -NotePropertyValue $script:VideoCaptureEventsPath
            }
        }
        $postBattleTransition = ($simulationFinish.status -eq 'completed' -and $partyScreenObserved -and $inventoryScreenObserved -and $inventoryReturnedToMap)
        if (-not $postBattleTransition) { throw "Native postbattle aftermath did not advance through InventoryState to MapState; gameState='$($postBattleState.state.context.gameState)', menu='$($postBattleState.state.context.menuId)' lootItems=$($postBattleState.state.context.lootItemCount)." }
    }

    $stop = Invoke-AgentCli 'stop'
    $fixtureHashAfter = (Get-FileHash $savePath -Algorithm SHA256).Hash
    $battleRewardTelemetry = if ($simulationFinish -and $simulationFinish.data) { $simulationFinish.data.rewardTelemetry } else { $null }
    $battleRewardTelemetryPassed = $Scenario -ne 'PostBattle' -or (
        $battleRewardTelemetry -and
        [double]$battleRewardTelemetry.winnerRenownValue -gt 0 -and
        [int]$battleRewardTelemetry.winnerContributionTotal -gt 0 -and
        [int]$battleRewardTelemetry.playerContribution -gt 0 -and
        @($battleRewardTelemetry.winnerPartyAwards | Where-Object { $_.partyId -eq 'player_party' -and [double]$_.renown -gt 0 }).Count -eq 1 -and
        [Math]::Abs(([double]$battleRewardTelemetry.playerRenownAfter - [double]$battleRewardTelemetry.playerRenownBefore) - ([double]$postBattleState.state.economy.renown - [double]$pursuit.state.economy.renown)) -lt 0.002
    )
    $result = [ordered]@{
        ProviderKind = 'test-fixture-only'
        ProcessId = $start.session.processId
        Scenario = $Scenario
        ClanTierBeforeBattle = if ($Scenario -eq 'PostBattle') { $pursuit.state.identity.clanTier } else { $null }
        ClanRenownBeforeBattle = if ($Scenario -eq 'PostBattle') { $pursuit.state.economy.renown } else { $null }
        ClanTierAfterBattle = if ($Scenario -eq 'PostBattle' -and $postBattleState) { $postBattleState.state.identity.clanTier } else { $null }
        ClanRenownAfterBattle = if ($Scenario -eq 'PostBattle' -and $postBattleState) { $postBattleState.state.economy.renown } else { $null }
        ClanRenownDelta = if ($Scenario -eq 'PostBattle' -and $postBattleState) { [Math]::Round(([double]$postBattleState.state.economy.renown - [double]$pursuit.state.economy.renown), 3) } else { $null }
        FixtureParty = $enemy[0]
        PursuitTimeControlMode = $pursuit.state.context.timeControlMode
        DaysElapsed = [Math]::Round(([double]$last.campaignDay - $pursuitStartDay), 4)
        EncounterActive = [bool]$last.state.context.encounterActive
        EncounteredPartyId = $last.state.context.encounteredPartyId
        NativeEncounterReached = $encounter
        DialogueChoices = $dialogueChoices
        NativeSendTroopsStartedSimulation = ($null -ne $simulationStart.state.context.battleSimulation)
        NativeSimulationPaused = ($simulationPause.status -eq 'completed' -and $null -ne $simulationPause.state.context.battleSimulation)
        NativeSimulationRetreat = if ($Scenario -eq 'Retreat') { [bool]$retreatedState.playerRetreated } else { $false }
        EncounterReturnedAfterRetreat = if ($Scenario -eq 'Retreat') { [bool]$simulationRetreat.state.context.encounterActive } else { $false }
        ManualMissionEntered = $missionEntered
        MissionRetreatResult = if ($missionRetreat) { $missionRetreat.data.tryExit } else { $null }
        NativeMissionEnded = if ($missionRetreat) { [bool]$missionRetreat.data.missionEnded } else { $false }
        MissionReturnedToCampaign = $missionReturnedToCampaign
        NativeSimulationFinished = $simulationFinished
        NativeSimulationFinishReceipt = if ($simulationFinish) { $simulationFinish.status } else { $null }
        BattleRewardTelemetry = $battleRewardTelemetry
        BattleRewardTelemetryPassed = $battleRewardTelemetryPassed
        PostBattleTransitionObserved = $postBattleTransition
        PartyScreenLootObserved = if ($Scenario -eq 'PostBattle') { $partyScreenObserved } else { $false }
        PartyScreenLootMembersBefore = if ($partyLootBefore) { @($partyLootBefore.leftMembers | ForEach-Object { [ordered]@{ troopId = $_.troopId; count = $_.count; transferable = $_.transferable } }) } else { @() }
        PartyScreenLootPrisonersBefore = if ($partyLootBefore) { @($partyLootBefore.leftPrisoners | ForEach-Object { [ordered]@{ troopId = $_.troopId; count = $_.count; transferable = $_.transferable } }) } else { @() }
        PartyScreenLootMembersAfterTransfer = if ($partyLootAfterTransfer) { @($partyLootAfterTransfer.leftMembers | ForEach-Object { [ordered]@{ troopId = $_.troopId; count = $_.count; transferable = $_.transferable } }) } else { @() }
        PartyScreenLootPrisonersAfterTransfer = if ($partyLootAfterTransfer) { @($partyLootAfterTransfer.leftPrisoners | ForEach-Object { [ordered]@{ troopId = $_.troopId; count = $_.count; transferable = $_.transferable } }) } else { @() }
        PartyScreenLootTransferCounts = $partyLootTransferCounts
        PartyScreenLootTransfersVerified = $partyLootTransfersVerified
        InventoryLootObserved = $inventoryScreenObserved
        InventoryLootItemCountBefore = $inventoryLootItemCountBefore
        InventoryLootItemCountAfter = $inventoryLootItemCountAfter
        InventoryPlayerItemCountBefore = $inventoryPlayerItemCountBefore
        InventoryPlayerItemCountAfter = $inventoryPlayerItemCountAfter
        InventoryItemsTransferred = $inventoryItemsTransferred
        InventoryDoneStatus = $inventoryDoneStatus
        InventoryReturnedToMap = $inventoryReturnedToMap
        VisualFrames = $script:VisualFrames
        ContinuousVideoCapture = $videoCaptureResult
        PostBattleGameState = if ($postBattleState) { $postBattleState.state.context.gameState } else { $null }
        FixtureUnchanged = $fixtureHashBefore -eq $fixtureHashAfter
        ProcessStopped = $stop.processStopped
    }
    $scenarioPassed = if ($Scenario -eq 'Retreat') {
        $result.NativeSimulationRetreat -and $result.EncounterReturnedAfterRetreat -and $missionEntered -and $result.NativeMissionEnded -and $missionReturnedToCampaign
    } else {
        $simulationFinished -and $null -ne $simulationFinish -and $partyLootTransfersVerified -and $inventoryScreenObserved -and $inventoryItemsTransferred -gt 0 -and $inventoryDoneStatus -eq 'completed' -and $postBattleTransition
    }
    $videoCapturePassed = ($Scenario -ne 'PostBattle' -or -not $CaptureFrames -or ($videoCaptureResult -and $videoCaptureResult.Passed -and $videoCaptureResult.FrameCoverageRatio -ge 0.9))
    $renownProgressionPassed = $Scenario -ne 'PostBattle' -or ($null -ne $result.ClanRenownDelta -and [double]$result.ClanRenownDelta -gt 0)
    $result.RenownProgressionPassed = $renownProgressionPassed
    $result.Passed = ($encounter -and $result.NativeSendTroopsStartedSimulation -and $result.NativeSimulationPaused -and $scenarioPassed -and $result.FixtureUnchanged -and $result.ProcessStopped -and $videoCapturePassed -and $renownProgressionPassed -and $battleRewardTelemetryPassed)
    $result | ConvertTo-Json -Depth 8
    if (-not $result.Passed) { exit 1 }
}
finally {
    if ($null -eq $priorMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $priorMode }
    if ($script:VideoCapture -and $script:VideoCapture.Process -and -not $script:VideoCapture.Process.HasExited) {
        try {
            . (Join-Path $PSScriptRoot 'HarnessVideoCapture.ps1')
            $partialContactPath = Join-Path $runDirectory 'BattleToLoot-partial-contact.jpg'
            $partialVideoResult = Stop-ChronicleWindowVideoCapture -Capture $script:VideoCapture -ContactSheetPath $partialContactPath -EventTracePath $script:VideoCaptureEventsPath -KeepVideo
            $partialVideoResult | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $runDirectory 'BattleToLoot-partial.json') -Encoding UTF8
        }
        catch {
            [ordered]@{ stoppedUtc = (Get-Date).ToUniversalTime().ToString('O'); error = $_.Exception.Message; videoPath = $videoPath; eventTracePath = $script:VideoCaptureEventsPath } |
                ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $runDirectory 'BattleToLoot-partial.json') -Encoding UTF8
            try { $script:VideoCapture.Process.Kill() } catch { }
        }
    }
    if (Test-Path $sessionPath) { try { Invoke-AgentCli 'stop' | Out-Null } catch { } }
}
