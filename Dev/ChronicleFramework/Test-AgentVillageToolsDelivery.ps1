#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180,
    [int]$MaxDecisions = 320,
    [string]$ScenarioSettlementId = 'village_V1_1'
)

$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$decisionLoop = Join-Path $PSScriptRoot 'Agent-DecisionLoop.ps1'
$provider = Join-Path $PSScriptRoot 'Test-AgentVillageToolsProvider.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$tempPath = $env:CHRONICLE_HARNESS_TEMP
$runDirectory = if ($tempPath) { Split-Path -Parent $tempPath } else { Join-Path $PSScriptRoot 'TestResults\ManualVillageToolsDelivery' }
$beforeFrame = if ($tempPath) { Join-Path $tempPath 'village-tools-before.bmp' } else { Join-Path $runDirectory 'village-tools-before.bmp' }
$afterFrame = if ($tempPath) { Join-Path $tempPath 'village-tools-after.bmp' } else { Join-Path $runDirectory 'village-tools-after.bmp' }
$resultPath = if ($tempPath) { Join-Path $tempPath 'VillageToolsDeliveryResult.json' } else { Join-Path $runDirectory 'VillageToolsDeliveryResult.json' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$previousScenarioSettlementId = $env:CHRONICLE_VILLAGE_TOOLS_SCENARIO_TARGET_ID
$commandPrefix = 'village-tools-' + (Get-Date -Format 'yyyyMMddHHmmssfff')

if (-not (Test-Path -LiteralPath $savePath)) { throw "Disposable Village Tools Campaign fixture not found: $savePath" }
if (-not (Test-Path -LiteralPath $provider)) { throw 'The deterministic Native-observation decision provider is missing.' }
if (Get-Process -Name Bannerlord -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
$start = $null

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $output = & $HarnessPowerShell -NoProfile -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

function Capture-EngineFrame([string]$Path, [string]$Suffix) {
    $receipt = Invoke-AgentCli 'captureFrame' @('-OutputPath', $Path, '-CommandId', "$commandPrefix-$Suffix") 30
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path -LiteralPath $Path) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
    if ($receipt.status -ne 'completed' -or -not (Test-Path -LiteralPath $Path) -or (Get-Item -LiteralPath $Path).Length -lt 4096) {
        throw "Game-engine frame '$Path' was not captured."
    }
}

try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $initial = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-initial")
    if ($initial.state.context.gameState -ne 'MapState') { throw "Disposable fixture must start on Campaign Map, got $($initial.state.context.gameState)." }
    Start-Sleep -Seconds 2
    $initial = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-initial-stable")
    Capture-EngineFrame $beforeFrame 'capture-before'

    $env:CHRONICLE_VILLAGE_TOOLS_SCENARIO_TARGET_ID = $ScenarioSettlementId
    $providerRun = & $HarnessPowerShell -NoProfile -File $decisionLoop -DecisionProviderPath $provider -MaxDecisions $MaxDecisions -TimeoutSeconds $TimeoutSeconds -CommandPrefix "$commandPrefix-agent" 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) {
            $failureTracePath = Join-Path $tempPath 'VillageToolsDecisionFailure.json'
            try {
                $failedLoop = $providerRun | ConvertFrom-Json
                $failedLoop | ConvertTo-Json -Depth 24 | Set-Content -LiteralPath $failureTracePath -Encoding UTF8
                if ($failedLoop.trace -and @($failedLoop.trace).Count -gt 0) {
                    $lastStep = $failedLoop.trace[-1]
                    [ordered]@{
                        Iteration = $lastStep.iteration
                        GameStateBefore = $lastStep.observationBefore.state.context.gameState
                        SettlementBefore = $lastStep.observationBefore.state.location.currentSettlementId
                        MenuBefore = $lastStep.observationBefore.state.context.menuId
                        EncounterActiveBefore = $lastStep.observationBefore.state.context.encounterActive
                        Action = $lastStep.decision.action
                        Arguments = $lastStep.decision.arguments
                        ActionStatus = $lastStep.actionReceipt.status
                        ActionError = $lastStep.actionReceipt.error
                        GameStateAfter = if ($lastStep.observationAfter) { $lastStep.observationAfter.state.context.gameState } else { $null }
                        SettlementAfter = if ($lastStep.observationAfter) { $lastStep.observationAfter.state.location.currentSettlementId } else { $null }
                    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tempPath 'VillageToolsDecisionFailureSummary.json') -Encoding UTF8
                }
            }
            catch {
                [ordered]@{ RawOutput = $providerRun; ParseError = $_.Exception.Message } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $failureTracePath -Encoding UTF8
            }
            try { Capture-EngineFrame (Join-Path $tempPath 'village-tools-failure.bmp') 'capture-failure' } catch { }
        }
        throw "Native-observation Village Tools agent loop failed: $providerRun"
    }
    try { $loop = $providerRun | ConvertFrom-Json }
    catch { throw "Village Tools agent loop returned invalid JSON: $providerRun" }
    if ($loop.status -eq 'failed') { throw "Village Tools decision loop failed: $($loop.error)" }
    if (-not $loop.trace -or @($loop.trace).Count -eq 0) { throw 'Village Tools agent loop returned no decision trace.' }

    $memoryPath = if ($tempPath) { Join-Path $tempPath "VillageToolsAgentMemory-$($loop.runId).json" } else { $null }
    $memory = if ($memoryPath -and (Test-Path -LiteralPath $memoryPath)) { Get-Content -LiteralPath $memoryPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
    $finalObservation = $loop.trace[-1].observationAfter
    $finalState = $finalObservation.state
    if ($finalState.context.gameState -eq 'MapState') {
        Start-Sleep -Seconds 1
        Capture-EngineFrame $afterFrame 'capture-after'
    }
    $loopSummaryPath = if ($tempPath) { Join-Path $tempPath 'VillageToolsDecisionTrace.json' } else { $null }
    if ($loopSummaryPath) {
        $traceSummary = @($loop.trace | ForEach-Object {
            [ordered]@{
                iteration = $_.iteration
                gameStateBefore = $_.observationBefore.state.context.gameState
                settlementBefore = $_.observationBefore.state.location.currentSettlementId
                action = $_.decision.action
                arguments = $_.decision.arguments
                actionStatus = if ($_.actionReceipt) { $_.actionReceipt.status } else { $null }
                gameStateAfter = $_.observationAfter.state.context.gameState
                settlementAfter = $_.observationAfter.state.location.currentSettlementId
                menuAfter = $_.observationAfter.state.context.menuId
            }
        })
        $traceSummary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $loopSummaryPath -Encoding UTF8
    }

    $actionNames = @($loop.trace | Where-Object { $_.actionExecuted } | ForEach-Object { [string]$_.decision.action })
    $activeQuestAfter = if ($memory) { @($finalState.quests | Where-Object { [string]$_.id -eq [string]$memory.questId }) } else { @() }
    $deliverySuccess = ($null -ne $memory -and [string]$memory.verification -eq 'passed' -and $activeQuestAfter.Count -eq 0)
    $returnedToGiverSettlementMenu = ($finalState.context.gameState -eq 'MapState' -and $finalState.context.menuId -eq 'village' -and $finalState.location.currentSettlementId -eq [string]$memory.homeVillageId -and $null -eq $finalState.context.conversation)
    $result = [ordered]@{
        ProviderKind = 'deterministic-observation-driven-agent'
        ScenarioSettlementId = $ScenarioSettlementId
        ProcessId = $start.session.processId
        DecisionCount = [int]$loop.decisions
        ActionsExecuted = [int]$loop.actionsExecuted
        Termination = $loop.termination
        QuestMarkerObserved = [bool]$memory.questMarkerObserved
        QuestAcceptanceOptionObserved = [bool]$memory.questAcceptanceOptionObserved
        DeliveryOptionObserved = [bool]$memory.deliveryOptionObserved
        QuestId = $memory.questId
        QuestTitle = $memory.questTitle
        IssueGiverHeroId = $memory.giverHeroId
        GiverVillageId = $memory.homeVillageId
        RequestedItemText = $memory.requestedItemSearch
        RequestedItemId = $memory.toolsItemId
        RequestedItemCount = $memory.targetCount
        RewardItemText = $memory.rewardItemName
        RewardItemCount = $memory.rewardItemCount
        ToolsCountBeforeDelivery = $memory.toolsCountBeforeDelivery
        ToolsCountAfterDelivery = $memory.toolsCountAfterDelivery
        RewardCountBeforeDelivery = $memory.rewardCountBeforeDelivery
        RewardCountAfterDelivery = $memory.rewardCountAfterDelivery
        GoldBeforeDelivery = $memory.preDeliveryGold
        GoldAfterDelivery = $memory.postDeliveryGold
        PartyItemCountBeforeDelivery = $memory.preDeliveryPartyItemCount
        PartyItemCountAfterDelivery = $memory.postDeliveryPartyItemCount
        QuestRewardNetItemDelta = $memory.questRewardNetItemDelta
        RewardTradeVmCountMatched = ($memory.rewardCountAfterDelivery -ge $memory.rewardCountBeforeDelivery + $memory.rewardItemCount)
        RewardInventoryCountMatched = [bool]$memory.rewardInventoryCountMatched
        RewardInventoryRowCount = $memory.rewardInventoryRowCount
        NativePlayerInventoryVerified = ((@($actionNames | Where-Object { $_ -eq 'inventoryOpen' }).Count -gt 0) -and (@($actionNames | Where-Object { $_ -eq 'heroEquipmentOptions' }).Count -gt 0) -and (@($actionNames | Where-Object { $_ -eq 'inventoryCancel' }).Count -gt 0))
        RewardPartyRosterDeltaMatched = [bool]$memory.questRewardRosterDeltaMatches
        VerificationEvidence = $memory.verificationEvidence
        TradeTownsObserved = @($memory.visitedMarkets)
        VillagesObserved = @($memory.visitedVillages)
        CurrentGameState = $finalState.context.gameState
        CurrentSettlementId = $finalState.location.currentSettlementId
        CurrentMenuId = $finalState.context.menuId
        ReturnedToGiverSettlementMenu = [bool]$returnedToGiverSettlementMenu
        CurrentVisibleMenuOptions = @($finalState.availableMenuOptions | Where-Object { $_.available -and $_.enabled } | ForEach-Object { [ordered]@{ Id = [string]$_.id; Text = [string]$_.text } })
        CampaignDayAtStart = $initial.campaignDay
        CampaignDayAtEnd = $finalObservation.campaignDay
        TimeControlModeAtEnd = $finalState.context.timeControlMode
        ActionNames = $actionNames
        EngineScreenshots = @($beforeFrame, $afterFrame)
        DecisionTrace = $loopSummaryPath
        SourceFixtureUnchanged = $false
        ProcessStopped = $false
        DeliveredNativeQuestAndVerifiedInventory = [bool]$deliverySuccess
    }

    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-stop") 30
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $result.SourceFixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
    $result.ProcessStopped = [bool]$stop.processStopped
    $rewardPostconditionVerified = ([bool]$result.RewardInventoryCountMatched -or [bool]$result.RewardTradeVmCountMatched)
    $result.Passed = ($deliverySuccess -and $memory.questMarkerObserved -and $memory.questAcceptanceOptionObserved -and $memory.deliveryOptionObserved -and $rewardPostconditionVerified -and $result.NativePlayerInventoryVerified -and $returnedToGiverSettlementMenu -and $loop.termination.completedByProvider -and $finalState.context.gameState -eq 'MapState' -and $result.SourceFixtureUnchanged -and $result.ProcessStopped -and (@($actionNames | Where-Object { $_ -eq 'trade' }).Count -gt 0) -and (@($actionNames | Where-Object { $_ -eq 'tradeConfirm' }).Count -gt 0) -and (@($actionNames | Where-Object { $_ -eq 'talkToSettlementHero' }).Count -ge 2))
    $json = $result | ConvertTo-Json -Depth 12
    if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) { Set-Content -LiteralPath (Join-Path $tempPath 'VillageToolsDeliveryResult.json') -Value $json -Encoding UTF8 }
    $json
    if (-not $result.Passed) { throw 'The autonomous Village Tools Issue delivery slice did not meet its visible-option, Native trade, return, reward or cleanup assertions.' }
}
catch {
    if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) {
        [ordered]@{ Error = $_.Exception.Message; SaveName = $LoadSaveName; FixtureHashBefore = $fixtureHashBefore; HarnessRunId = (Split-Path -Leaf (Split-Path -Parent $tempPath)) } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $tempPath 'VillageToolsDeliveryFailure.json') -Encoding UTF8
    }
    throw
}
finally {
    if (Test-Path $sessionPath) { try { Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-cleanup") 20 | Out-Null } catch { } }
    if ($null -eq $previousScenarioSettlementId) { Remove-Item Env:CHRONICLE_VILLAGE_TOOLS_SCENARIO_TARGET_ID -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_VILLAGE_TOOLS_SCENARIO_TARGET_ID = $previousScenarioSettlementId }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
