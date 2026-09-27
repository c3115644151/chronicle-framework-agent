[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180,
    [string]$TargetSettlementId = 'town_V1',
    [string]$ApproachSettlementId = 'town_V1',
    [ValidateSet('ConversationOnly', 'QuestAccepted', 'NativePreconditionBlocked')]
    [string]$ExpectedOutcome = 'ConversationOnly'
)

$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$runDirectory = if ($env:CHRONICLE_HARNESS_TEMP) { Split-Path -Parent $env:CHRONICLE_HARNESS_TEMP } else { Join-Path $PSScriptRoot 'TestResults\ManualSettlementOverlayConversation' }
$captureName = if ($ExpectedOutcome -eq 'ConversationOnly') { 'SettlementOverlayConversation-frame.bmp' } else { "SettlementOverlayQuest-$ExpectedOutcome-frame.bmp" }
$resultName = if ($ExpectedOutcome -eq 'ConversationOnly') { 'SettlementOverlayConversationResult.json' } else { "SettlementOverlayQuest-$ExpectedOutcome-Result.json" }
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
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
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
    if ($arrived.state.schemaVersion -ne 20) { throw "Settlement overlay observation schema changed unexpectedly: $($arrived.state.schemaVersion)." }

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
    $talk = Invoke-AgentCli 'talkToSettlementHero' @('-HeroId', $targetHeroId, '-CommandId', "$commandPrefix-talk") 30
    $postTalk = $talk
    $conversationDeadline = [DateTime]::UtcNow.AddSeconds(30)
    while ($talk.status -eq 'completed' -and [DateTime]::UtcNow -lt $conversationDeadline) {
        $conversation = $postTalk.state.context.conversation
        if ($postTalk.state.context.gameState -eq 'MissionState' -and $postTalk.state.mission.mainAgent -and $conversation -and $conversation.heroId -eq $targetHeroId) { break }
        if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { break }
        Start-Sleep -Milliseconds 300
        $postTalk = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-conversation-$([Guid]::NewGuid().ToString('N'))") 30
    }

    $conversation = $postTalk.state.context.conversation
    $conversationStartedForTarget = ($postTalk.state.context.gameState -eq 'MissionState' -and $postTalk.state.mission.mainAgent -and $conversation -and $conversation.heroId -eq $targetHeroId)
    $initialConversationHeroMatchesTarget = [bool]$conversationStartedForTarget
    $questCountBefore = @($arrived.state.quests).Count
    $issueTopicRequested = $false
    $alternativeExplanationRequested = $false
    $questOfferObserved = $false
    $questAccepted = $false
    $questBlockedReason = $null
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
        TargetSettlement = [ordered]@{ Id = $TargetSettlementId; Name = $settlement[0].name; Type = $settlement[0].type; MenuId = $arrived.state.context.menuId }
        MapSettlementTargetCount = $mapSettlementTargets.Count
        RouteTrace = $routeTrace
        NativeOverlayCharacterCount = $overlayCharacters.Count
        Target = $targetCharacter
        TargetIssueMarkers = $candidate[0].IssueMarkers
        TalkPermissionWasReported = $talk.data.talkPermissionWasReported
        TalkStatus = $talk.status
        TalkError = $talk.error
        TalkData = $talk.data
        PostTalkContext = $postTalk.state.context
        Mission = $postTalk.state.mission
        Conversation = $conversation
        ConversationStartedForTarget = $initialConversationHeroMatchesTarget
        ExpectedOutcome = $ExpectedOutcome
        IssueQuestAcceptanceRequested = [bool]($ExpectedOutcome -ne 'ConversationOnly')
        IssueTopicRequested = $issueTopicRequested
        AlternativeExplanationRequested = $alternativeExplanationRequested
        QuestOfferObserved = $questOfferObserved
        QuestAccepted = $questAccepted
        QuestBlockedReason = $questBlockedReason
        NativePreconditionBlocked = [bool]($ExpectedOutcome -eq 'NativePreconditionBlocked' -and $issueTopicRequested -and -not $questOfferObserved -and -not $questAccepted -and @($postTalk.state.quests).Count -eq $questCountBefore -and $questBlockedReason -like '*returned to its main options after the Issue topic*')
        NativeRefusalSentence = if ($ExpectedOutcome -ne 'ConversationOnly' -and -not $questAccepted) { $conversation.sentenceText } else { $null }
        DialogueTrace = $dialogueTrace
        QuestCountBefore = $questCountBefore
        QuestCountAfter = $questCountAfter
        QuestUnchanged = ($questCountBefore -eq $questCountAfter)
        CampaignDayBeforeTalk = $arrived.campaignDay
        CampaignDayAfterTalk = $postTalk.campaignDay
        CampaignClockUnchangedDuringSceneEntry = ($arrived.campaignDay -eq $postTalk.campaignDay)
        EngineScreenshot = if ($screenshotValid) { $capturePath } else { $null }
        ScreenshotValid = $screenshotValid
        FixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = $stop.processStopped
    }
    $result.ExpectedOutcomeMet = switch ($ExpectedOutcome) {
        'ConversationOnly' { $true }
        'QuestAccepted' { [bool]$questAccepted }
        'NativePreconditionBlocked' { [bool]$result.NativePreconditionBlocked }
    }
    $result.Passed = ($talk.status -eq 'completed' -and $initialConversationHeroMatchesTarget -and $result.ExpectedOutcomeMet -and $result.QuestUnchanged -eq (-not $questAccepted) -and $result.CampaignClockUnchangedDuringSceneEntry -and $screenshotValid -and $result.FixtureUnchanged -and $result.ProcessStopped)
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
