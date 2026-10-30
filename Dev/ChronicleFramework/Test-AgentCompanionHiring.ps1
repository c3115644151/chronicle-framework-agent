[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [ValidateRange(30, 300)][int]$ArrivalTimeoutSeconds = 180,
    [ValidateRange(5, 20)][int]$NavigationLeaseSeconds = 20,
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$runDirectory = if ($env:CHRONICLE_HARNESS_TEMP) { Split-Path -Parent $env:CHRONICLE_HARNESS_TEMP } else { Join-Path $PSScriptRoot 'TestResults\ManualCompanionHiring' }
$captureTempPath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP 'CompanionHiring-frame.bmp' } else { Join-Path $runDirectory 'CompanionHiring-frame.bmp' }
$capturePath = Join-Path $runDirectory 'CompanionHiring-frame.bmp'
$resultPath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP 'CompanionHiringResult.json' } else { Join-Path $runDirectory 'CompanionHiringResult.json' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$commandPrefix = 'companion-hiring-' + (Get-Date -Format 'yyyyMMddHHmmssfff')
$diagnosticStep = 'preflight'

if (-not (Test-Path -LiteralPath $savePath)) { throw "Companion hiring fixture not found: $LoadSaveName" }
if (Get-Process -Name Bannerlord -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

function Get-LocalHeroAgent($State, [string]$HeroId) {
    return @($State.state.mission.nearbySceneAgents | Where-Object { [string]$_.heroId -eq $HeroId } | Select-Object -First 1)
}

function Get-LocalObservedAgent($State, [int]$AgentIndex) {
    return @($State.state.mission.nearbySceneAgents | Where-Object { [int]$_.agentIndex -eq $AgentIndex } | Select-Object -First 1)
}

function Get-StableConversationState($State, [string]$Label) {
    $current = $State
    for ($turn = 0; $turn -lt 6; $turn++) {
        if (-not $current.state.context.conversation) { throw "Conversation ended before the $Label stage could be observed." }
        if (@($current.state.context.conversation.options).Count -gt 0) { return $current }
        $continue = Invoke-AgentCli 'dialogueContinue' @('-CommandId', "$commandPrefix-$Label-continue-$turn")
        if ($continue.status -ne 'completed') { throw "Native dialogueContinue did not complete during $Label." }
        $current = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-$Label-observe-$turn")
    }
    throw "Native conversation did not expose a player option during $Label after six observations."
}

function Invoke-CompanionHiringScenario([int]$GoldOffset, [string]$Scenario) {
    $script:diagnosticStep = "${Scenario}: map arrival and Tavern entry"
    $scenarioPrefix = "$commandPrefix-$Scenario"
    $scenarioFixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $initial = Invoke-AgentCli 'state' @('-CommandId', "$scenarioPrefix-initial")
    if ($initial.state.context.gameState -ne 'MapState') { throw "$Scenario fixture did not start on Campaign Map." }

    $settlement = @($initial.state.nearbySettlements | Where-Object { $_.type -eq 'town' -and -not $_.hostile } | Sort-Object distance | Select-Object -First 1)
    if ($settlement.Count -ne 1) { throw "$Scenario fixture has no visible non-hostile town." }
    $move = Invoke-AgentCli 'move' @('-SettlementId', [string]$settlement[0].id, '-CommandId', "$scenarioPrefix-move")
    if ($move.status -ne 'completed') { throw "$Scenario map movement did not accept the visible town." }
    $arrivalDeadline = [DateTime]::UtcNow.AddSeconds($ArrivalTimeoutSeconds)
    $arrived = $null
    while ([DateTime]::UtcNow -lt $arrivalDeadline) {
        $arrived = Invoke-AgentCli 'state' @('-CommandId', "$scenarioPrefix-arrival-$([Guid]::NewGuid().ToString('N'))") 30
        if ($arrived.state.location.currentSettlementId -eq $settlement[0].id -and $arrived.state.context.menuId -eq 'town') { break }
        if ($arrived.state.context.encounterActive -and $arrived.state.context.encounteredPartyId -ne $settlement[0].id) { throw "$Scenario travel was interrupted by an unrelated encounter." }
        if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw "$Scenario game process exited during travel." }
        Start-Sleep -Milliseconds 500
    }
    if (-not $arrived -or $arrived.state.context.menuId -ne 'town') { throw "$Scenario natural travel did not arrive at town." }

    $district = @($arrived.state.availableMenuOptions | Where-Object { $_.id -eq 'town_backstreet' -and $_.available -and $_.enabled })
    if ($district.Count -ne 1) { throw "$Scenario Town menu lacked an enabled Tavern district." }
    $backstreet = Invoke-AgentCli 'menuSelect' @('-MenuId', 'town', '-OptionId', 'town_backstreet', '-CommandId', "$scenarioPrefix-backstreet")
    $tavern = @($backstreet.state.availableMenuOptions | Where-Object { $_.id -eq 'town_tavern' -and $_.available -and $_.enabled })
    if ($tavern.Count -ne 1) { throw "$Scenario Tavern district lacked an enabled Visit Tavern option." }
    $mission = Invoke-AgentCli 'menuSelect' @('-MenuId', 'town_backstreet', '-OptionId', 'town_tavern', '-CommandId', "$scenarioPrefix-enter-tavern")
    $sceneDeadline = [DateTime]::UtcNow.AddSeconds(60)
    while ((-not $mission.state.mission -or -not $mission.state.mission.mainAgent -or -not $mission.state.mission.nativeConversationReady) -and [DateTime]::UtcNow -lt $sceneDeadline) {
        Start-Sleep -Milliseconds 500
        $mission = Invoke-AgentCli 'state' @('-CommandId', "$scenarioPrefix-scene-$([Guid]::NewGuid().ToString('N'))")
    }
    if (-not $mission.state.mission.mainAgent -or -not $mission.state.mission.nativeConversationReady -or $mission.state.mission.sceneName -notmatch 'tavern' -or $mission.state.context.timeControlMode -ne 'Stop') { throw "$Scenario did not enter a stopped native Tavern Location Mission with its rendering-time conversation manager initialized." }

    $wanderer = @($mission.state.mission.nearbySceneAgents | Where-Object { $_.heroId -and $_.occupation -eq 'Wanderer' -and -not $_.isEnemy } | Sort-Object distance | Select-Object -First 1)
    if ($wanderer.Count -ne 1) { throw "$Scenario current local Tavern observation contains no friendly Wanderer." }
    $heroId = [string]$wanderer[0].heroId
    $sceneAgentCatalog = Invoke-AgentCli 'missionSceneAgents' @('-CommandId', "$scenarioPrefix-local-agent-catalog")
    $catalogWanderer = @($sceneAgentCatalog.data.agents | Where-Object { $_.heroId -eq $heroId -and [int]$_.agentIndex -eq [int]$wanderer[0].agentIndex })
    if ([int]$sceneAgentCatalog.data.schemaVersion -lt 2 -or $catalogWanderer.Count -ne 1 -or $null -eq $catalogWanderer[0].nativeConversationActionAvailable)
        { throw "$Scenario missionSceneAgents response did not include the schema-v2 Native conversation-action eligibility field for the observed Wanderer." }
    $initialNativeConversationActionAvailable = [bool]$catalogWanderer[0].nativeConversationActionAvailable
    $initialCatalogDistance = [double]$catalogWanderer[0].distance
    $fixture = Invoke-AgentCli 'harnessPrepareCompanionHiringFixture' @('-HeroId', $heroId, '-GoldOffset', [string]$GoldOffset, '-CommandId', "$scenarioPrefix-prepare-gold")
    $beforeHiring = Invoke-AgentCli 'harnessCompanionHiringDiagnostics' @('-HeroId', $heroId, '-CommandId', "$scenarioPrefix-before-hire")
    if ($beforeHiring.data.isPlayerCompanion -or [int]$beforeHiring.data.playerGold -ne ([int]$beforeHiring.data.nativeHiringPrice + $GoldOffset) -or [int]$beforeHiring.data.playerCompanionCount -ge [int]$beforeHiring.data.companionLimit)
        { throw "$Scenario Harness fixture failed native Wanderer availability/price/limit preconditions." }

    $currentWanderer = @($wanderer)
    $nearby = $mission
    $navigator = [pscustomobject]@{ status = 'not-required'; data = @{ reason = 'target already inside the native conversation radius'; durationSeconds = 0 } }
    if ([double]$currentWanderer[0].distance -ge 2.0) {
    $script:diagnosticStep = "${Scenario}: approach observed Wanderer agent $($wanderer[0].agentIndex) from $($wanderer[0].distance) meters"
    $navigator = Invoke-AgentCli 'missionNavigateToAgent' @('-AgentIndex', [string]$wanderer[0].agentIndex, '-DurationSeconds', [string]$NavigationLeaseSeconds, '-CommandId', "$scenarioPrefix-navigate")
        if ($navigator.status -ne 'completed') { throw "$Scenario native AgentNavigator rejected the current Wanderer." }
        $navigationDeadline = [DateTime]::UtcNow.AddSeconds($NavigationLeaseSeconds + 2)
        do {
            Start-Sleep -Milliseconds 500
            $nearby = Invoke-AgentCli 'state' @('-CommandId', "$scenarioPrefix-navigation-$([Guid]::NewGuid().ToString('N'))")
            $currentWanderer = $nearby.state.mission.nearbySceneAgents | Where-Object { [int]$_.agentIndex -eq [int]$wanderer[0].agentIndex } | Select-Object -First 1
            if ($null -ne $currentWanderer -and [double]$currentWanderer.distance -lt 2.0) { break }
            if (-not $nearby.state.mission.navigation -or -not $nearby.state.mission.navigation.active) { break }
        } while ([DateTime]::UtcNow -lt $navigationDeadline)
        if ($null -eq $currentWanderer -or [double]$currentWanderer.distance -ge 2.0)
            { $lastDistance = if ($null -eq $currentWanderer) { 'not-local' } else { [string]$currentWanderer.distance }; throw "$Scenario native non-teleporting navigation failed to reach the Wanderer within $NavigationLeaseSeconds seconds; last observed distance: $lastDistance." }
        if ($nearby.state.mission.navigation -and $nearby.state.mission.navigation.active) {
            $cancelNavigation = Invoke-AgentCli 'missionCancelNavigation' @('-CommandId', "$scenarioPrefix-cancel-navigation")
            $nearby = Invoke-AgentCli 'state' @('-CommandId', "$scenarioPrefix-after-cancel-navigation")
            $currentWanderer = $nearby.state.mission.nearbySceneAgents | Where-Object { [int]$_.agentIndex -eq [int]$wanderer[0].agentIndex } | Select-Object -First 1
            if (-not $nearby.state.mission.mainAgent.isPlayerControlled) { throw "$Scenario cancelled navigation did not restore Player control." }
        }
    }

    $sceneAgentCatalog = Invoke-AgentCli 'missionSceneAgents' @('-CommandId', "$scenarioPrefix-nearby-agent-catalog")
    $catalogWanderer = @($sceneAgentCatalog.data.agents | Where-Object { $_.heroId -eq $heroId -and [int]$_.agentIndex -eq [int]$wanderer[0].agentIndex })
    if ($catalogWanderer.Count -ne 1 -or -not $catalogWanderer[0].nativeConversationActionAvailable)
        { throw "$Scenario Native navigation reached the Wanderer, but current MissionConversationLogic still reports no conversation action for this Agent." }
    $nearbyNativeConversationActionAvailable = [bool]$catalogWanderer[0].nativeConversationActionAvailable
    $nearbyCatalogDistance = [double]$catalogWanderer[0].distance

    $script:diagnosticStep = "${Scenario}: start native conversation with agent $($currentWanderer[0].agentIndex) at $($currentWanderer[0].distance) meters"
    $interaction = Invoke-AgentCli 'missionInteract' @('-AgentIndex', [string]$currentWanderer[0].agentIndex, '-CommandId', "$scenarioPrefix-start-dialogue")
    $greeting = Invoke-AgentCli 'state' @('-CommandId', "$scenarioPrefix-greeting")
    if ($interaction.status -ne 'completed' -or [string]$greeting.state.context.conversation.heroId -ne $heroId) { throw "$Scenario Native Use did not start a conversation with the observed Wanderer." }
    $script:diagnosticStep = "${Scenario}: inspect Wanderer greeting options"
    $options = @($greeting.state.context.conversation.options)
    if (-not ($options | Where-Object { $_.id -eq 'wanderer_meet_player_response2' -and $_.clickable }))
        { throw "$Scenario Native Wanderer greeting did not expose the current business-conversation response." }
    $businessResponse = Invoke-AgentCli 'dialogueSelect' @('-OptionId', 'wanderer_meet_player_response2', '-CommandId', "$scenarioPrefix-wanderer-business")
    $businessState = Get-StableConversationState (Invoke-AgentCli 'state' @('-CommandId', "$scenarioPrefix-business-options")) 'companion-main-option'
    $hireOffer = @($businessState.state.context.conversation.options | Where-Object { $_.id -eq 'main_option_faction_hire' -and $_.clickable } | Select-Object -First 1)
    if ($hireOffer.Count -ne 1) { throw "$Scenario current Native Conversation did not expose the dynamic company-hire offer." }
    $hireStart = Invoke-AgentCli 'dialogueSelect' @('-OptionId', [string]$hireOffer[0].id, '-CommandId', "$scenarioPrefix-hire-offer")
    $quoteState = Get-StableConversationState (Invoke-AgentCli 'state' @('-CommandId', "$scenarioPrefix-price-quote")) 'companion-price-quote'
    $quoteText = [string]$quoteState.state.context.conversation.sentenceText
    $quoteOptions = @($quoteState.state.context.conversation.options)
    $acceptOption = @($quoteOptions | Where-Object { $_.id -eq 'player_companion_hire_response_1' -and $_.clickable } | Select-Object -First 1)
    $declineOption = @($quoteOptions | Where-Object { $_.id -eq 'player_companion_hire_response_2' -and $_.clickable } | Select-Object -First 1)
    $quoteDigits = $quoteText -replace '\D', ''
    $nativePrice = [int]$fixture.data.nativeHiringPrice
    $quoteMatchesNativePrice = $quoteDigits.Contains($nativePrice.ToString([Globalization.CultureInfo]::InvariantCulture))
    $goldBeforeChoice = [int]$quoteState.state.economy.gold

    if ($GoldOffset -eq 0) {
        if ($acceptOption.Count -ne 0 -or $declineOption.Count -ne 1) { throw 'At exact asking price, Native dialogue did not block the strict-Gold acceptance option or offer the no-purchase response.' }
        $decline = Invoke-AgentCli 'dialogueSelect' @('-OptionId', [string]$declineOption[0].id, '-CommandId', "$scenarioPrefix-decline")
        $afterRefusal = Invoke-AgentCli 'state' @('-CommandId', "$scenarioPrefix-after-refusal")
        $refusalDiagnostics = Invoke-AgentCli 'harnessCompanionHiringDiagnostics' @('-HeroId', $heroId, '-CommandId', "$scenarioPrefix-after-refusal-diagnostics")
        $scenarioStop = Invoke-AgentCli 'stop' @('-CommandId', "$scenarioPrefix-stop") 30
        $scenarioFixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
        $result = [ordered]@{
            Scenario = $Scenario
            Wanderer = $wanderer[0]
            NativeConversationActionBeforeApproach = $initialNativeConversationActionAvailable
            CatalogDistanceBeforeApproach = $initialCatalogDistance
            NativeConversationActionAfterApproach = $nearbyNativeConversationActionAvailable
            CatalogDistanceAfterApproach = $nearbyCatalogDistance
            NativePrice = $nativePrice
            QuoteText = $quoteText
            GoldAtPrice = $goldBeforeChoice
            AcceptOptionVisible = ($acceptOption.Count -gt 0)
            DeclineOptionStatus = [string]$decline.status
            NoPartialHire = (-not [bool]$refusalDiagnostics.data.isPlayerCompanion -and -not [bool]$refusalDiagnostics.data.isInPlayerClan -and -not [bool]$refusalDiagnostics.data.isInMainParty -and [int]$afterRefusal.state.economy.gold -eq $goldBeforeChoice)
            CompanionDiagnostics = $refusalDiagnostics.data
            SourceFixtureUnchanged = ($scenarioFixtureHashBefore -eq $scenarioFixtureHashAfter)
            ProcessStopped = [bool]$scenarioStop.processStopped
        }
        return $result
    }

    if ($acceptOption.Count -ne 1) { throw "$Scenario Native dialogue did not expose the enabled strict-Gold companion acceptance option." }
    $capture = Invoke-AgentCli 'captureFrame' @('-OutputPath', $captureTempPath, '-CommandId', "$scenarioPrefix-capture-price") 30
    if ($capture.status -eq 'completed' -and (Test-Path -LiteralPath $captureTempPath) -and $env:CHRONICLE_HARNESS_TEMP) { Move-Item -LiteralPath $captureTempPath -Destination $capturePath -Force }
    $partyMembersBefore = [int]$quoteState.state.party.members
    $accepted = Invoke-AgentCli 'dialogueSelect' @('-OptionId', [string]$acceptOption[0].id, '-CommandId', "$scenarioPrefix-accept-price")
    $afterHire = Invoke-AgentCli 'state' @('-CommandId', "$scenarioPrefix-after-hire")
    $afterDiagnostics = Invoke-AgentCli 'harnessCompanionHiringDiagnostics' @('-HeroId', $heroId, '-CommandId', "$scenarioPrefix-after-hire-diagnostics")
    $scenarioStop = Invoke-AgentCli 'stop' @('-CommandId', "$scenarioPrefix-stop") 30
    $scenarioFixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    return [ordered]@{
        Scenario = $Scenario
        Wanderer = $wanderer[0]
        NativeConversationActionBeforeApproach = $initialNativeConversationActionAvailable
        CatalogDistanceBeforeApproach = $initialCatalogDistance
        NativeConversationActionAfterApproach = $nearbyNativeConversationActionAvailable
        CatalogDistanceAfterApproach = $nearbyCatalogDistance
        NavigationReceipt = $navigator.data
        NavigationState = $nearby.state.mission.navigation
        InteractionReceipt = $interaction.data
        HiringOffer = $hireOffer[0]
        QuoteText = $quoteText
        QuoteMatchesNativePrice = [bool]$quoteMatchesNativePrice
        NativePrice = $nativePrice
        GoldBeforeHire = $goldBeforeChoice
        GoldAfterHire = [int]$afterHire.state.economy.gold
        GoldSpent = $goldBeforeChoice - [int]$afterHire.state.economy.gold
        PartyMemberDelta = [int]$afterHire.state.party.members - $partyMembersBefore
        CompanionDiagnostics = $afterDiagnostics.data
        HireCommitted = ($accepted.status -eq 'completed' -and [int]$afterHire.state.economy.gold -eq ($goldBeforeChoice - $nativePrice) -and [int]$afterHire.state.party.members -eq ($partyMembersBefore + 1) -and [bool]$afterDiagnostics.data.isPlayerCompanion -and [bool]$afterDiagnostics.data.isInPlayerClan -and [bool]$afterDiagnostics.data.isInMainParty)
        SourceFixtureUnchanged = ($scenarioFixtureHashBefore -eq $scenarioFixtureHashAfter)
        ProcessStopped = [bool]$scenarioStop.processStopped
    }
}

try {
    $diagnosticStep = 'positive and strict-Gold acceptance scenarios'
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $positive = Invoke-CompanionHiringScenario 1 'positive'
    $strictGold = Invoke-CompanionHiringScenario 0 'strict-gold'
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $assertions = [ordered]@{
        NativeCurrentTavernWandererHired = [bool]$positive.HireCommitted
        NativeConversationActionRefreshesAfterApproach = [bool]$positive.NativeConversationActionAfterApproach -and [double]$positive.CatalogDistanceAfterApproach -lt 2.0
        NativePriceQuoteMatchesModel = [bool]$positive.QuoteMatchesNativePrice
        StrictGoldEqualityRejected = ([int]$strictGold.GoldAtPrice -eq [int]$strictGold.NativePrice -and -not [bool]$strictGold.AcceptOptionVisible -and [bool]$strictGold.NoPartialHire)
        SourceFixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter -and [bool]$positive.SourceFixtureUnchanged -and [bool]$strictGold.SourceFixtureUnchanged)
        AllProcessesStopped = ([bool]$positive.ProcessStopped -and [bool]$strictGold.ProcessStopped)
    }
    $failedAssertions = @($assertions.Keys | Where-Object { -not [bool]$assertions[$_] })
    $result = [ordered]@{
        Positive = $positive
        StrictGold = $strictGold
        Assertions = $assertions
        FailedAssertions = $failedAssertions
        FixtureHashBefore = $fixtureHashBefore
        FixtureHashAfter = $fixtureHashAfter
        ProcessStopped = [bool]$positive.ProcessStopped -and [bool]$strictGold.ProcessStopped
        Passed = ($failedAssertions.Count -eq 0)
    }
    $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    $result | ConvertTo-Json -Depth 12
    if (-not $result.Passed) { throw 'Native Wanderer hiring transaction, strict Gold condition, Clan/Party membership, or fixture safety did not match.' }
}
catch {
    throw "Companion hiring test failed during '$diagnosticStep': $($_.Exception.Message)"
}
finally {
    if (Test-Path $sessionPath) {
        try { Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-cleanup") 20 | Out-Null } catch { }
    }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
