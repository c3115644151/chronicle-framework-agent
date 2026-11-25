#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180,
    [string]$TargetSettlementId = 'town_V1',
    [string]$ApproachSettlementId = 'town_V1',
    [ValidateSet('QuickTalk', 'Visit')]
    [string]$InteractionMode = 'Visit',
    [ValidateSet('ConversationOnly', 'QuestAccepted', 'NativePreconditionBlocked', 'IssueGateProbe')]
    [string]$ExpectedOutcome = 'ConversationOnly',
    [switch]$ValidateQuestDetails
)

$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$runDirectory = if ($env:CHRONICLE_HARNESS_TEMP) { Split-Path -Parent $env:CHRONICLE_HARNESS_TEMP } else { Join-Path (Split-Path -Parent $PSScriptRoot) 'TestResults\ManualSettlementOverlayConversation' }
$captureName = if ($InteractionMode -eq 'QuickTalk') { 'SettlementOverlayQuickTalk-frame.bmp' } elseif ($ExpectedOutcome -eq 'ConversationOnly') { 'SettlementOverlayVisit-frame.bmp' } else { "SettlementOverlayQuest-$ExpectedOutcome-frame.bmp" }
$resultName = if ($ValidateQuestDetails) { 'SettlementOverlayQuest-QuestDetails-Result.json' } elseif ($InteractionMode -eq 'QuickTalk') { 'SettlementOverlayQuickTalk-Result.json' } elseif ($ExpectedOutcome -eq 'ConversationOnly') { 'SettlementOverlayVisit-Result.json' } else { "SettlementOverlayQuest-$ExpectedOutcome-Result.json" }
$interactionAction = if ($InteractionMode -eq 'QuickTalk') { 'talkToSettlementHero' } else { 'visitSettlementHero' }
$captureTempPath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP $captureName } else { Join-Path $runDirectory $captureName }
$capturePath = Join-Path $runDirectory $captureName
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$commandPrefix = 'settlement-overlay-' + (Get-Date -Format 'yyyyMMddHHmmssfff')
$routeTrace = @()

if (-not (Test-Path -LiteralPath $savePath)) { throw "Settlement overlay fixture not found: $savePath" }
if (Get-Process -Name Bannerlord -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $output = & $HarnessPowerShell -NoProfile -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

function Wait-ForSettlementMenu([string]$SettlementId) {
    $arrivalDeadline = [DateTime]::UtcNow.AddSeconds(120)
    $observation = $null
    while ([DateTime]::UtcNow -lt $arrivalDeadline) {
        $observation = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-arrival-$([Guid]::NewGuid().ToString('N'))") 30
        if ($observation.state.location.currentSettlementId -eq $SettlementId -and -not [string]::IsNullOrWhiteSpace([string]$observation.state.context.menuId)) { return $observation }
        if ($observation.state.context.encounterActive -and $observation.state.context.encounteredPartyId -ne $SettlementId) { throw "Unexpected encounter '$($observation.state.context.encounteredPartyId)' interrupted travel to '$SettlementId'." }
        if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw "Game process exited during travel to '$SettlementId'." }
        Start-Sleep -Milliseconds 500
    }
    throw "Natural Campaign travel did not reach settlement menu '$SettlementId'. LastSettlement=$($observation.state.location.currentSettlementId), Menu=$($observation.state.context.menuId)."
}

try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $initial = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-initial")
    if ($initial.state.context.gameState -ne 'MapState') { throw "Settlement overlay fixture must start on Campaign map; got $($initial.state.context.gameState)." }
    $mapTargetsReceipt = Invoke-AgentCli 'mapSettlementTargets' @('-CommandId', "$commandPrefix-map-targets-initial")
    if ($mapTargetsReceipt.status -ne 'completed' -or -not $mapTargetsReceipt.data) { throw 'Native map settlement target observation was not available on Campaign Map.' }
    $mapSettlementTargets = @($mapTargetsReceipt.data.mapSettlementTargets)

    $settlement = @($mapSettlementTargets | Where-Object { $_.id -eq $TargetSettlementId -and -not $_.hostile } | Select-Object -First 1)
    if ($settlement.Count -ne 1) {
        $approach = @($mapSettlementTargets | Where-Object { $_.id -eq $ApproachSettlementId -and -not $_.hostile } | Select-Object -First 1)
        if ($approach.Count -ne 1) { throw "Neither target '$TargetSettlementId' nor safe approach settlement '$ApproachSettlementId' is currently a visible map target. Observed=$((@($mapSettlementTargets | ForEach-Object { $_.id }) -join ','))" }
        $approachMove = Invoke-AgentCli 'move' @('-SettlementId', $ApproachSettlementId, '-CommandId', "$commandPrefix-approach-move")
        if ($approachMove.status -ne 'completed' -or $approachMove.state.location.targetSettlementId -ne $ApproachSettlementId) { throw "Native Campaign movement did not accept observed approach target '$ApproachSettlementId'." }
        $approachArrival = Wait-ForSettlementMenu $ApproachSettlementId
        $routeTrace += [ordered]@{ Step = 'moveToObservedApproach'; SettlementId = $ApproachSettlementId; MenuId = $approachArrival.state.context.menuId; CampaignDay = $approachArrival.campaignDay }
        $leaveOption = @($approachArrival.state.availableMenuOptions | Where-Object { $_.isLeave -and $_.available } | Select-Object -First 1)
        if ($leaveOption.Count -ne 1) { throw "Approach settlement '$ApproachSettlementId' has no unique available native Leave option." }
        $leaveReceipt = Invoke-AgentCli 'menuSelect' @('-MenuId', $approachArrival.state.context.menuId, '-OptionId', $leaveOption[0].id, '-CommandId', "$commandPrefix-approach-leave")
        if ($leaveReceipt.status -ne 'completed') { throw "Native Leave option '$($leaveOption[0].id)' failed: $($leaveReceipt.error)" }
        $mapDeadline = [DateTime]::UtcNow.AddSeconds(20)
        $mapObservation = $null
        while ([DateTime]::UtcNow -lt $mapDeadline) {
            $mapObservation = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-map-after-leave-$([Guid]::NewGuid().ToString('N'))") 30
            if ($mapObservation.state.context.gameState -eq 'MapState' -and -not $mapObservation.state.location.currentSettlementId) { break }
            Start-Sleep -Milliseconds 250
        }
        if (-not $mapObservation -or $mapObservation.state.context.gameState -ne 'MapState' -or $mapObservation.state.location.currentSettlementId) { throw "Native Leave from '$ApproachSettlementId' did not return to Campaign Map." }
        $routeTrace += [ordered]@{ Step = 'leaveApproachAndReobserve'; OptionId = $leaveOption[0].id; GameState = $mapObservation.state.context.gameState; CampaignDay = $mapObservation.campaignDay }
        $initial = $mapObservation
        $mapTargetsReceipt = Invoke-AgentCli 'mapSettlementTargets' @('-CommandId', "$commandPrefix-map-targets-after-approach")
        if ($mapTargetsReceipt.status -ne 'completed' -or -not $mapTargetsReceipt.data) { throw 'Map settlement targets could not be re-observed after native Leave.' }
        $mapSettlementTargets = @($mapTargetsReceipt.data.mapSettlementTargets)
        $settlement = @($mapSettlementTargets | Where-Object { $_.id -eq $TargetSettlementId -and -not $_.hostile } | Select-Object -First 1)
    }
    if ($settlement.Count -ne 1) { throw "Target settlement '$TargetSettlementId' is not a safe target in the current map target observation after the approach. Observed=$((@($mapSettlementTargets | ForEach-Object { $_.id }) -join ','))" }

    $move = Invoke-AgentCli 'move' @('-SettlementId', $TargetSettlementId, '-CommandId', "$commandPrefix-move")
    if ($move.status -ne 'completed' -or $move.state.location.targetSettlementId -ne $TargetSettlementId) { throw "Native Campaign movement did not accept observed settlement target '$TargetSettlementId'." }
    $routeTrace += [ordered]@{ Step = 'moveToObservedTarget'; SettlementId = $TargetSettlementId; CampaignDay = $initial.campaignDay }
    $arrived = Wait-ForSettlementMenu $TargetSettlementId
    $arrivedStateProperties = @($arrived.state.PSObject.Properties.Name)
    if ('settlementOverlayCharacters' -notin $arrivedStateProperties -or 'availableMenuOptions' -notin $arrivedStateProperties) { throw "Settlement overlay observation is missing the fields this test consumes (schema $($arrived.state.schemaVersion))." }

    $overlayCharacters = @($arrived.state.settlementOverlayCharacters)
    $issueCandidates = @()
    foreach ($character in $overlayCharacters) {
        $issueMarkers = @($character.questMarkers | Where-Object { [string]$_.type -match 'Issue' })
        if ($character.isNotable -and $issueMarkers.Count -gt 0) {
            $issueCandidates += [pscustomobject]@{ Character = $character; IssueMarkers = $issueMarkers }
        }
    }
    $candidate = @($issueCandidates | Select-Object -First 1)
    if ($candidate.Count -ne 1) { throw "Native Settlement overlay did not expose an Issue-marked Notable. OverlayCount=$($overlayCharacters.Count), overlayIds=$((@($overlayCharacters | ForEach-Object { $_.heroId }) -join ',')), menuMarker=$($arrived.state.availableMenuOptions | Where-Object id -eq 'town_streets' | Select-Object -ExpandProperty questMarkerNames -First 1)." }

    $targetCharacter = $candidate[0].Character
    $targetHeroId = [string]$targetCharacter.heroId
    $talk = Invoke-AgentCli $interactionAction @('-HeroId', $targetHeroId, '-CommandId', "$commandPrefix-$($InteractionMode.ToLowerInvariant())") 30
    $postTalk = $talk
    $conversationDeadline = [DateTime]::UtcNow.AddSeconds(30)
    while ($talk.status -eq 'completed' -and [DateTime]::UtcNow -lt $conversationDeadline) {
        $conversation = $postTalk.state.context.conversation
        $interactionContextReady = if ($InteractionMode -eq 'QuickTalk') { $postTalk.state.context.gameState -eq 'MapState' } else { $postTalk.state.context.gameState -eq 'MissionState' -and $postTalk.state.mission.mainAgent }
        if ($interactionContextReady -and $conversation -and $conversation.heroId -eq $targetHeroId) { break }
        if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { break }
        Start-Sleep -Milliseconds 300
        $postTalk = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-conversation-$([Guid]::NewGuid().ToString('N'))") 30
    }

    $conversation = $postTalk.state.context.conversation
    $interactionContextReady = if ($InteractionMode -eq 'QuickTalk') { $postTalk.state.context.gameState -eq 'MapState' } else { $postTalk.state.context.gameState -eq 'MissionState' -and $postTalk.state.mission.mainAgent }
    $conversationStartedForTarget = ($interactionContextReady -and $conversation -and $conversation.heroId -eq $targetHeroId)
    $initialConversationHeroMatchesTarget = [bool]$conversationStartedForTarget
    $questCountBefore = @($arrived.state.quests).Count
    $issueTopicRequested = $false
    $alternativeExplanationRequested = $false
    $questOfferObserved = $false
    $questAccepted = $false
    $questBlockedReason = $null
    $nativeIssueGateDiagnostics = $null
    $dialogueTrace = @()
    if ($ExpectedOutcome -ne 'ConversationOnly' -and $conversationStartedForTarget) {
        for ($step = 1; $step -le 10; $step++) {
            $currentConversation = $postTalk.state.context.conversation
            if (-not $currentConversation) { $questBlockedReason = 'Native Conversation ended before an Issue Quest option was submitted.'; break }
            $currentOptions = @($currentConversation.options)
            $selectedOption = $null
            $selectedAction = 'dialogueSelect'
            $questAcceptOption = @($currentOptions | Where-Object { $_.id -eq 'issue_offer_player_accept_quest' } | Select-Object -First 1)
            if ($questAcceptOption.Count -eq 1) {
                $questOfferObserved = $true
                if ($ExpectedOutcome -eq 'IssueGateProbe') { $questBlockedReason = 'Native direct Issue Quest acceptance is available; diagnostic probe stopped before accepting it.'; break }
                if (-not $questAcceptOption[0].clickable) { $questBlockedReason = 'The native Issue Quest acceptance option is present but not clickable.'; break }
                $selectedOption = 'issue_offer_player_accept_quest'
            }
            else {
                $questSolutionPath = @($currentOptions | Where-Object { $_.id -eq 'issue_explanation_player_response_pre_quest_solution' -and $_.clickable } | Select-Object -First 1)
                $issueTopic = @($currentOptions | Where-Object { $_.id -eq 'hero_give_issue' -and $_.clickable } | Select-Object -First 1)
                $alternativeExplanationPath = @($currentOptions | Where-Object { $_.id -eq 'issue_alternative_solution_player_response' -and $_.clickable } | Select-Object -First 1)
                $introResponse = @($currentOptions | Where-Object { $_.id -eq 'lord_meet_player_response1' -and $_.clickable } | Select-Object -First 1)
                $alternativeOrLordSolution = @($currentOptions | Where-Object { $_.id -in @('issue_offer_player_accept_alternative','issue_offer_player_accept_lord') -and $_.clickable })
                if ($questSolutionPath.Count -eq 1) { $selectedOption = 'issue_explanation_player_response_pre_quest_solution' }
                elseif ($issueTopic.Count -eq 1 -and -not $issueTopicRequested) { $selectedOption = 'hero_give_issue' }
                elseif ($issueTopic.Count -eq 1 -and $issueTopicRequested) { $questBlockedReason = 'The native conversation returned to its main options after the Issue topic; no legal Quest solution was opened.'; break }
                elseif ($alternativeExplanationPath.Count -eq 1 -and -not $alternativeExplanationRequested) { $selectedOption = 'issue_alternative_solution_player_response' }
                elseif ($introResponse.Count -eq 1) { $selectedOption = 'lord_meet_player_response1' }
                elseif ($alternativeOrLordSolution.Count -gt 0) { $questBlockedReason = 'Only Alternative or Lord Solution options are available; this W2-E test will not select those paths.'; break }
                elseif ($currentOptions.Count -eq 0) { $selectedAction = 'dialogueContinue' }
                else { $questBlockedReason = "No whitelisted Quest path option is currently clickable: $((@($currentOptions | ForEach-Object id) -join ','))"; break }
            }

            $optionListBefore = @($currentOptions | ForEach-Object { [ordered]@{ Id = $_.id; Clickable = $_.clickable; Text = $_.text } })
            $selection = if ($selectedAction -eq 'dialogueContinue') {
                Invoke-AgentCli 'dialogueContinue' @('-CommandId', "$commandPrefix-quest-continue-$step") 30
            }
            else {
                Invoke-AgentCli 'dialogueSelect' @('-OptionId', $selectedOption, '-CommandId', "$commandPrefix-quest-select-$step") 30
            }
            $dialogueTrace += [ordered]@{ Step = $step; SentenceBefore = $currentConversation.sentenceText; OptionsBefore = $optionListBefore; Action = $selectedAction; OptionId = $selectedOption; ReceiptStatus = $selection.status; ReceiptError = $selection.error }
            if ($selection.status -ne 'completed') { $questBlockedReason = "Native conversation action rejected: $($selection.error)"; break }
            if ($selectedOption -eq 'hero_give_issue') { $issueTopicRequested = $true }
            if ($selectedOption -eq 'issue_alternative_solution_player_response') { $alternativeExplanationRequested = $true }
            Start-Sleep -Milliseconds 250
            $postTalk = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-quest-state-$step") 30
            $questCountAfterStep = @($postTalk.state.quests).Count
            if ($questCountAfterStep -gt $questCountBefore) { $questAccepted = $true; break }
            if ($selectedOption -eq 'issue_offer_player_accept_quest') { $questOfferObserved = $true; $questBlockedReason = 'Native Quest acceptance option executed, but no new Ongoing Quest appeared in the latest observation.'; break }
        }
        if (-not $questAccepted -and -not $questBlockedReason) { $questBlockedReason = 'The safe native Issue Quest dialogue path reached its 10-step Harness limit.' }
    }
    if ($ExpectedOutcome -eq 'IssueGateProbe' -and $InteractionMode -eq 'QuickTalk' -and $conversationStartedForTarget -and $postTalk.state.context.gameState -eq 'MapState') {
        $nativeIssueGateDiagnostics = Invoke-AgentCli 'harnessMapDiagnostics' @('-HeroId', $targetHeroId, '-CommandId', "$commandPrefix-issue-gate-probe") 30
    }
    $quickTalkReturnedToSettlementMenu = $false
    if ($InteractionMode -eq 'QuickTalk' -and $ExpectedOutcome -ne 'IssueGateProbe' -and $conversationStartedForTarget) {
        for ($quickStep = 1; $quickStep -le 10; $quickStep++) {
            $activeQuickConversation = $postTalk.state.context.conversation
            if (-not $activeQuickConversation) { break }
            $quickOptions = @($activeQuickConversation.options)
            $quickLeaveOption = @($quickOptions | Where-Object { $_.clickable -and [string]$_.id -eq 'player_is_leaving_neutral_or_friendly' } | Select-Object -First 1)
            if ($quickLeaveOption.Count -eq 1) {
                $quickAction = Invoke-AgentCli 'dialogueSelect' @('-OptionId', [string]$quickLeaveOption[0].id, '-CommandId', "$commandPrefix-quick-leave-$quickStep") 30
                if ($quickAction.status -ne 'completed') { throw "Native QuickConversation leave option failed: $($quickAction.error)" }
            }
            elseif ($quickOptions.Count -eq 0) {
                $quickAction = Invoke-AgentCli 'dialogueContinue' @('-CommandId', "$commandPrefix-quick-continue-$quickStep") 30
                if ($quickAction.status -ne 'completed') { throw "Native QuickConversation continue failed: $($quickAction.error)" }
            }
            else {
                $introduction = @($quickOptions | Where-Object { $_.clickable -and [string]$_.id -eq 'lord_meet_player_response1' } | Select-Object -First 1)
                if ($introduction.Count -ne 1) { throw "QuickConversation exposes no leave or introductory option the test is scoped to: $((@($quickOptions | ForEach-Object id) -join ','))" }
                $quickAction = Invoke-AgentCli 'dialogueSelect' @('-OptionId', [string]$introduction[0].id, '-CommandId', "$commandPrefix-quick-intro-$quickStep") 30
                if ($quickAction.status -ne 'completed') { throw "Native QuickConversation introduction failed: $($quickAction.error)" }
            }
            Start-Sleep -Milliseconds 200
            $postTalk = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-quick-state-$quickStep") 30
            if ($postTalk.state.context.gameState -eq 'MapState' -and
                $postTalk.state.location.currentSettlementId -eq $TargetSettlementId -and
                -not $postTalk.state.context.conversation -and
                -not [string]::IsNullOrWhiteSpace([string]$postTalk.state.context.menuId)) { break }
        }
        $quickTalkReturnedToSettlementMenu = ($postTalk.state.context.gameState -eq 'MapState' -and
            $postTalk.state.location.currentSettlementId -eq $TargetSettlementId -and
            -not $postTalk.state.context.conversation -and
            -not [string]::IsNullOrWhiteSpace([string]$postTalk.state.context.menuId))
        if (-not $quickTalkReturnedToSettlementMenu) { throw 'Native QuickConversation did not end back at the original Campaign Map settlement menu.' }
    }
    $questDetailsReceipt = $null
    $questDetailsNative = $null
    $questDetailsRepeat = $null
    $questDetailsValidated = $false
    if ($ValidateQuestDetails)
    {
        if ($ExpectedOutcome -ne 'QuestAccepted' -or -not $questAccepted) { throw 'Quest Journal details validation requires a successfully accepted native Issue Quest.' }
        $questIdsBeforeTalk = @($arrived.state.quests | ForEach-Object { [string]$_.id })
        $newlyAcceptedQuests = @($postTalk.state.quests | Where-Object { [string]$_.id -notin $questIdsBeforeTalk })
        if ($newlyAcceptedQuests.Count -ne 1) { throw "Expected one newly observed active Quest after acceptance; found $($newlyAcceptedQuests.Count)." }
        $questId = [string]$newlyAcceptedQuests[0].id
        $questDetailsReceipt = Invoke-AgentCli 'questDetails' @('-QuestId', $questId, '-CommandId', "$commandPrefix-quest-details") 30
        $questDetailsNative = Invoke-AgentCli 'harnessQuestDetailsDiagnostics' @('-QuestId', $questId, '-CommandId', "$commandPrefix-quest-details-native") 30
        $questDetailsRepeat = Invoke-AgentCli 'questDetails' @('-QuestId', $questId, '-CommandId', "$commandPrefix-quest-details-repeat") 30
        $questDetailsUnknown = Invoke-AgentCli 'questDetails' @('-QuestId', '__not_observed_quest__', '-CommandId', "$commandPrefix-quest-details-unknown") 30
        $questDeadlinePrivacy = Invoke-AgentCli 'harnessQuestDeadlinePrivacyDiagnostics' @('-CommandId', "$commandPrefix-quest-deadline-privacy") 30
        $detail = $questDetailsReceipt.data
        $nativeDetail = $questDetailsNative.data
        $detailStages = @($detail.journalStages)
        $nativeStages = @($nativeDetail.journalStages)
        $stagesMatch = ($detailStages.Count -eq $nativeStages.Count)
        if ($stagesMatch) {
            for ($stageIndex = 0; $stageIndex -lt $detailStages.Count; $stageIndex++) {
                $observedStage = $detailStages[$stageIndex]
                $nativeStage = $nativeStages[$stageIndex]
                if ([string]$observedStage.logType -ne [string]$nativeStage.logType -or
                    [string]$observedStage.dateText -ne [string]$nativeStage.dateText -or
                    [string]$observedStage.description -ne [string]$nativeStage.description -or
                    [bool]$observedStage.isLastStage -ne [bool]$nativeStage.isLastStage -or
                    [bool]$observedStage.hasTask -ne [bool]$nativeStage.hasTask) { $stagesMatch = $false; break }
                if ($observedStage.hasTask -and (
                    [string]$observedStage.taskName -ne [string]$nativeStage.rawTaskName -or
                    [int]$observedStage.currentProgress -ne [int]$nativeStage.currentProgress -or
                    [int]$observedStage.targetProgress -ne [int]$nativeStage.targetProgress -or
                    [string]$observedStage.progressType -ne [string]$nativeStage.progressType -or
                    [bool]$observedStage.isTaskCompleted -ne [bool]$nativeStage.isTaskCompleted)) { $stagesMatch = $false; break }
            }
        }
        $visibleQuestSummary = @($postTalk.state.quests | Where-Object { $_.id -eq $questId } | Select-Object -First 1)
        $dueVisibilityMatches = $false
        if ($visibleQuestSummary.Count -eq 1 -and [bool]$detail.isRemainingTimeHidden -eq [bool]$nativeDetail.isRemainingTimeHidden)
        {
            if ([bool]$detail.isRemainingTimeHidden) { $dueVisibilityMatches = ($null -eq $detail.daysRemaining -and $null -eq $visibleQuestSummary[0].daysRemaining) }
            else { $dueVisibilityMatches = ([int]$detail.daysRemaining -eq [int]$nativeDetail.daysRemaining -and [int]$visibleQuestSummary[0].daysRemaining -eq [int]$detail.daysRemaining) }
        }
        $giverMatches = ([string]$detail.title -eq [string]$nativeDetail.title -and
            [bool]$detail.questGiverHidden -eq [bool]$nativeDetail.questGiverHidden -and
            [string]$detail.questGiver.id -eq [string]$nativeDetail.questGiverId -and
            [string]$detail.questGiver.name -eq [string]$nativeDetail.questGiverName -and
            [bool]$detail.isTracked -eq [bool]$nativeDetail.isTracked)
        $repeatStable = ([string](ConvertTo-Json -InputObject $detail -Depth 12 -Compress) -ceq [string](ConvertTo-Json -InputObject $questDetailsRepeat.data -Depth 12 -Compress))
        $unobservedQuestRejected = ($questDetailsUnknown.status -eq 'rejected')
        $deadlinePrivacyGateCorrect = ($questDeadlinePrivacy.status -eq 'completed' -and
            [bool]$questDeadlinePrivacy.data.hidden.isRemainingTimeHidden -and
            $null -eq $questDeadlinePrivacy.data.hidden.daysRemaining -and
            -not [bool]$questDeadlinePrivacy.data.visible.isRemainingTimeHidden -and
            [int]$questDeadlinePrivacy.data.visible.daysRemaining -eq 14)
        $postDetailsState = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-quest-details-state-after") 30
        $journalReadOnly = ([string](ConvertTo-Json -InputObject @($postTalk.state.quests) -Depth 8 -Compress) -ceq [string](ConvertTo-Json -InputObject @($postDetailsState.state.quests) -Depth 8 -Compress) -and $postTalk.campaignDay -eq $postDetailsState.campaignDay)
        $questDetailsValidated = ($questDetailsReceipt.status -eq 'completed' -and $questDetailsNative.status -eq 'completed' -and $questDetailsRepeat.status -eq 'completed' -and $stagesMatch -and $dueVisibilityMatches -and $giverMatches -and $repeatStable -and $unobservedQuestRejected -and $deadlinePrivacyGateCorrect -and $journalReadOnly)
    }
    $screenshot = $null
    $screenshotValid = $false
    if ($conversationStartedForTarget) {
        $screenshot = Invoke-AgentCli 'captureFrame' @('-OutputPath', $captureTempPath, '-CommandId', "$commandPrefix-capture") 30
    $captureDeadline = [DateTime]::UtcNow.AddSeconds(10)
        while (-not (Test-Path -LiteralPath $captureTempPath) -and [DateTime]::UtcNow -lt $captureDeadline) { Start-Sleep -Milliseconds 100 }
        $screenshotValid = ($screenshot.status -eq 'completed' -and (Test-Path -LiteralPath $captureTempPath) -and (Get-Item -LiteralPath $captureTempPath).Length -ge 4096)
        if ($screenshotValid -and $env:CHRONICLE_HARNESS_TEMP) { Move-Item -LiteralPath $captureTempPath -Destination $capturePath -Force }
    }

    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-stop") 30
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $conversation = $postTalk.state.context.conversation
    $questCountAfter = @($postTalk.state.quests).Count
    $result = [ordered]@{
        ProcessId = $start.session.processId
        InteractionMode = $InteractionMode
        TargetSettlement = [ordered]@{ Id = $TargetSettlementId; Name = $settlement[0].name; Type = $settlement[0].type; MenuId = $arrived.state.context.menuId }
        MapSettlementTargetCount = $mapSettlementTargets.Count
        RouteTrace = $routeTrace
        NativeOverlayCharacterCount = $overlayCharacters.Count
        Target = $targetCharacter
        TargetIssueMarkers = $candidate[0].IssueMarkers
        TalkStatus = $talk.status
        TalkError = $talk.error
        TalkActionReceipt = $talk.data
        PostTalkContext = $postTalk.state.context
        Mission = $postTalk.state.mission
        Conversation = $conversation
        ConversationStartedForTarget = $initialConversationHeroMatchesTarget
        QuickTalkReturnedToSettlementMenu = $quickTalkReturnedToSettlementMenu
        ExpectedOutcome = $ExpectedOutcome
        IssueQuestAcceptanceRequested = [bool]($ExpectedOutcome -ne 'ConversationOnly')
        IssueTopicRequested = $issueTopicRequested
        AlternativeExplanationRequested = $alternativeExplanationRequested
        QuestOfferObserved = $questOfferObserved
        QuestAccepted = $questAccepted
        QuestBlockedReason = $questBlockedReason
        NativeIssueGateDiagnostics = if ($nativeIssueGateDiagnostics) { $nativeIssueGateDiagnostics.data.issueGateProbe } else { $null }
        QuestDetails = if ($questDetailsReceipt) { $questDetailsReceipt.data } else { $null }
        QuestDetailsNativeDiagnostics = if ($questDetailsNative) { $questDetailsNative.data } else { $null }
        UnobservedQuestDetailsStatus = if ($questDetailsUnknown) { $questDetailsUnknown.status } else { $null }
        QuestDeadlinePrivacyGate = if ($questDeadlinePrivacy) { $questDeadlinePrivacy.data } else { $null }
        QuestDetailsValidated = [bool]$questDetailsValidated
        NativePreconditionBlocked = [bool]($ExpectedOutcome -eq 'NativePreconditionBlocked' -and $issueTopicRequested -and -not $questOfferObserved -and -not $questAccepted -and @($postTalk.state.quests).Count -eq $questCountBefore -and $questBlockedReason -like '*returned to its main options after the Issue topic*')
        NativeRefusalSentence = if ($ExpectedOutcome -ne 'ConversationOnly' -and -not $questAccepted) { $conversation.sentenceText } else { $null }
        DialogueTrace = $dialogueTrace
        QuestCountBefore = $questCountBefore
        QuestCountAfter = $questCountAfter
        QuestUnchanged = ($questCountBefore -eq $questCountAfter)
        CampaignDayBeforeTalk = $arrived.campaignDay
        CampaignDayAfterTalk = $postTalk.campaignDay
        CampaignClockUnchangedDuringSceneEntry = ($arrived.campaignDay -eq $postTalk.campaignDay)
        CampaignDayDeltaDuringInteraction = [Math]::Round(([double]$postTalk.campaignDay - [double]$arrived.campaignDay), 6)
        TimeControlModeBeforeInteraction = $arrived.state.context.timeControlMode
        TimeControlModeAfterInteraction = $postTalk.state.context.timeControlMode
        EngineScreenshot = if ($screenshotValid) { $capturePath } else { $null }
        ScreenshotValid = $screenshotValid
        FixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = $stop.processStopped
        TestMaximumFramerate = $start.session.performanceProfile.maxFramerate
        EngineConfigRestored = [bool]$stop.engineConfigRestored
    }
    $result.ExpectedOutcomeMet = switch ($ExpectedOutcome) {
        'ConversationOnly' { $true }
        'QuestAccepted' { [bool]$questAccepted }
        'NativePreconditionBlocked' { [bool]$result.NativePreconditionBlocked }
        'IssueGateProbe' { [bool]($null -ne $nativeIssueGateDiagnostics -and $result.NativeIssueGateDiagnostics.targetHeroFound -and $result.NativeIssueGateDiagnostics.targetHasIssue -and -not [string]::IsNullOrWhiteSpace([string]$result.NativeIssueGateDiagnostics.targetIssueType) -and [int]$result.NativeIssueGateDiagnostics.sameTypeIssueCount -ge 1 -and $questOfferObserved -and @($conversation.options | Where-Object { $_.id -eq 'issue_offer_player_accept_quest' -and $_.clickable }).Count -eq 1 -and -not $questAccepted) }
    }
    $interactionReturnValidated = ($ExpectedOutcome -eq 'IssueGateProbe' -or $InteractionMode -ne 'QuickTalk' -or $quickTalkReturnedToSettlementMenu)
    $clockAssertionValid = ($InteractionMode -eq 'QuickTalk' -or $result.CampaignClockUnchangedDuringSceneEntry)
    $result.Passed = ($talk.status -eq 'completed' -and $initialConversationHeroMatchesTarget -and $interactionReturnValidated -and $result.ExpectedOutcomeMet -and $result.QuestUnchanged -eq (-not $questAccepted) -and $clockAssertionValid -and (-not $ValidateQuestDetails -or $questDetailsValidated) -and $screenshotValid -and $result.FixtureUnchanged -and $result.ProcessStopped -and [int]$result.TestMaximumFramerate -eq 30 -and $result.EngineConfigRestored)
    $resultJson = $result | ConvertTo-Json -Depth 18
    if ($env:CHRONICLE_HARNESS_TEMP -and (Test-Path -LiteralPath $env:CHRONICLE_HARNESS_TEMP -PathType Container)) {
        Set-Content -LiteralPath (Join-Path $env:CHRONICLE_HARNESS_TEMP $resultName) -Value $resultJson -Encoding UTF8
    }
    $resultJson
    if (-not $result.Passed) { throw "Native settlement overlay validation failed: expectedOutcome=$ExpectedOutcome, expectedOutcomeMet=$($result.ExpectedOutcomeMet), talk=$($talk.status), partner=$($conversation.heroId), expected=$targetHeroId, questAccepted=$questAccepted, nativePreconditionBlocked=$($result.NativePreconditionBlocked), issueOfferObserved=$questOfferObserved, blockedReason=$questBlockedReason." }
}
catch {
    $lastObservedState = if ($postTalk -and $postTalk.state) { $postTalk.state } elseif ($arrived -and $arrived.state) { $arrived.state } elseif ($initial -and $initial.state) { $initial.state } else { $null }
    $observedOverlay = if ($overlayCharacters) { @($overlayCharacters) } elseif ($lastObservedState -and $lastObservedState.settlementOverlayCharacters) { @($lastObservedState.settlementOverlayCharacters) } else { @() }
    $mapFramePath = $null
    $mapFrameStatus = $null
    if ($lastObservedState -and $lastObservedState.context.gameState -eq 'MapState' -and $env:CHRONICLE_HARNESS_TEMP -and (Test-Path -LiteralPath $env:CHRONICLE_HARNESS_TEMP -PathType Container)) {
        $mapFrameName = 'SettlementOverlayFailure-map.bmp'
        $mapFramePath = Join-Path $env:CHRONICLE_HARNESS_TEMP $mapFrameName
        try {
            $mapFrameReceipt = Invoke-AgentCli 'captureFrame' @('-OutputPath', $mapFramePath, '-CommandId', "$commandPrefix-failure-map-frame") 15
            $captureDeadline = [DateTime]::UtcNow.AddSeconds(8)
            while (-not (Test-Path -LiteralPath $mapFramePath) -and [DateTime]::UtcNow -lt $captureDeadline) { Start-Sleep -Milliseconds 100 }
            if ($mapFrameReceipt.status -eq 'completed' -and (Test-Path -LiteralPath $mapFramePath) -and (Get-Item -LiteralPath $mapFramePath).Length -ge 4096) { $mapFrameStatus = 'captured' }
            else { $mapFrameStatus = "failed:$($mapFrameReceipt.error)"; $mapFramePath = $null }
        }
        catch { $mapFrameStatus = "failed:$($_.Exception.Message)"; $mapFramePath = $null }
    }
    $failureStop = $null
    if (Test-Path $sessionPath) {
        try { $failureStop = Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-failure-cleanup") 20 } catch { }
    }
    $failure = [ordered]@{
        ExpectedOutcome = $ExpectedOutcome
        TargetSettlementId = $TargetSettlementId
        ApproachSettlementId = $ApproachSettlementId
        RouteTrace = $routeTrace
        TargetSettlement = $settlement
        Error = $_.Exception.Message
        EngineMapFrame = if ($mapFramePath) { Split-Path -Leaf $mapFramePath } else { $null }
        EngineMapFrameStatus = $mapFrameStatus
        GameState = $lastObservedState.context.gameState
        CurrentSettlementId = $lastObservedState.location.currentSettlementId
        MenuId = $lastObservedState.context.menuId
        ObservedOverlayCharacters = $observedOverlay
        IssueMarkedNotables = @($observedOverlay | Where-Object { $_.isNotable -and @($_.questMarkers | Where-Object { [string]$_.type -match 'Issue' }).Count -gt 0 })
        AvailableMenuOptions = @($lastObservedState.availableMenuOptions)
        CleanupReceipt = $failureStop
    }
    if ($env:CHRONICLE_HARNESS_TEMP -and (Test-Path -LiteralPath $env:CHRONICLE_HARNESS_TEMP -PathType Container)) {
        $failurePath = [IO.Path]::ChangeExtension($resultName, 'Failure.json')
        Set-Content -LiteralPath (Join-Path $env:CHRONICLE_HARNESS_TEMP $failurePath) -Value ($failure | ConvertTo-Json -Depth 16) -Encoding UTF8
    }
    throw
}
finally {
    if (Test-Path $sessionPath) {
        try { Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-cleanup") 20 | Out-Null } catch { }
    }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
