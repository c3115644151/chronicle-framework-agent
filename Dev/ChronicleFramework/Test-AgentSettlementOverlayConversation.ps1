[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180,
    [switch]$AcceptIssueQuest
)

$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$runDirectory = if ($env:CHRONICLE_HARNESS_TEMP) { Split-Path -Parent $env:CHRONICLE_HARNESS_TEMP } else { Join-Path $PSScriptRoot 'TestResults\ManualSettlementOverlayConversation' }
$captureName = if ($AcceptIssueQuest) { 'SettlementOverlayQuestAcceptance-frame.bmp' } else { 'SettlementOverlayConversation-frame.bmp' }
$resultName = if ($AcceptIssueQuest) { 'SettlementOverlayQuestAcceptanceResult.json' } else { 'SettlementOverlayConversationResult.json' }
$captureTempPath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP $captureName } else { Join-Path $runDirectory $captureName }
$capturePath = Join-Path $runDirectory $captureName
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$commandPrefix = 'settlement-overlay-' + (Get-Date -Format 'yyyyMMddHHmmssfff')

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

try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $initial = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-initial")
    if ($initial.state.context.gameState -ne 'MapState') { throw "Settlement overlay fixture must start on Campaign map; got $($initial.state.context.gameState)." }

    $town = @($initial.state.nearbySettlements | Where-Object { $_.id -eq 'town_V1' -and $_.type -eq 'town' -and -not $_.hostile } | Select-Object -First 1)
    if ($town.Count -ne 1) { throw 'Sargot is not currently a safe visible town target in the disposable fixture.' }
    $move = Invoke-AgentCli 'move' @('-SettlementId', 'town_V1', '-CommandId', "$commandPrefix-move")
    if ($move.status -ne 'completed' -or $move.state.location.targetSettlementId -ne 'town_V1') { throw 'Native campaign movement did not accept the Sargot test target.' }

    $arrivalDeadline = [DateTime]::UtcNow.AddSeconds(120)
    $arrived = $null
    while ([DateTime]::UtcNow -lt $arrivalDeadline) {
        $arrived = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-arrival-$([Guid]::NewGuid().ToString('N'))") 30
        if ($arrived.state.location.currentSettlementId -eq 'town_V1' -and $arrived.state.context.menuId -eq 'town') { break }
        if ($arrived.state.context.encounterActive -and $arrived.state.context.encounteredPartyId -ne 'town_V1') { throw "Unexpected encounter '$($arrived.state.context.encounteredPartyId)' interrupted Sargot travel." }
        if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'Game process exited during natural Sargot travel.' }
        Start-Sleep -Milliseconds 500
    }
    if (-not $arrived -or $arrived.state.location.currentSettlementId -ne 'town_V1' -or $arrived.state.context.menuId -ne 'town') { throw 'Natural Campaign travel did not reach Sargot town menu.' }
    if ($arrived.state.schemaVersion -ne 19) { throw "Settlement overlay observation schema changed unexpectedly: $($arrived.state.schemaVersion)." }

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
    $questOfferObserved = $false
    $questAccepted = $false
    $questBlockedReason = $null
    $dialogueTrace = @()
    if ($AcceptIssueQuest -and $conversationStartedForTarget) {
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
                $introResponse = @($currentOptions | Where-Object { $_.id -eq 'lord_meet_player_response1' -and $_.clickable } | Select-Object -First 1)
                $alternativeOrLordSolution = @($currentOptions | Where-Object { $_.id -in @('issue_offer_player_accept_alternative','issue_offer_player_accept_lord') -and $_.clickable })
                if ($questSolutionPath.Count -eq 1) { $selectedOption = 'issue_explanation_player_response_pre_quest_solution' }
                elseif ($issueTopic.Count -eq 1 -and -not $issueTopicRequested) { $selectedOption = 'hero_give_issue' }
                elseif ($issueTopic.Count -eq 1 -and $issueTopicRequested) { $questBlockedReason = 'The native conversation returned to its main options after the Issue topic; no legal Quest solution was opened.'; break }
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
        IssueQuestAcceptanceRequested = [bool]$AcceptIssueQuest
        IssueTopicRequested = $issueTopicRequested
        QuestOfferObserved = $questOfferObserved
        QuestAccepted = $questAccepted
        QuestBlockedReason = $questBlockedReason
        NativePreconditionBlocked = [bool]($AcceptIssueQuest -and $issueTopicRequested -and -not $questOfferObserved -and -not $questAccepted -and @($postTalk.state.quests).Count -eq $questCountBefore -and $questBlockedReason -like '*returned to its main options after the Issue topic*')
        NativeRefusalSentence = if ($AcceptIssueQuest -and -not $questAccepted) { $conversation.sentenceText } else { $null }
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
    $questAcceptanceSatisfied = (-not $AcceptIssueQuest -or $questAccepted -or $result.NativePreconditionBlocked)
    $result.Passed = ($talk.status -eq 'completed' -and $initialConversationHeroMatchesTarget -and $questAcceptanceSatisfied -and $result.QuestUnchanged -eq (-not $questAccepted) -and $result.CampaignClockUnchangedDuringSceneEntry -and $screenshotValid -and $result.FixtureUnchanged -and $result.ProcessStopped)
    $resultJson = $result | ConvertTo-Json -Depth 18
    if ($env:CHRONICLE_HARNESS_TEMP -and (Test-Path -LiteralPath $env:CHRONICLE_HARNESS_TEMP -PathType Container)) {
        Set-Content -LiteralPath (Join-Path $env:CHRONICLE_HARNESS_TEMP $resultName) -Value $resultJson -Encoding UTF8
    }
    $resultJson
    if (-not $result.Passed) { throw "Native settlement overlay validation failed: talk=$($talk.status), partner=$($conversation.heroId), expected=$targetHeroId, questAccepted=$questAccepted, nativePreconditionBlocked=$($result.NativePreconditionBlocked), issueOfferObserved=$questOfferObserved, blockedReason=$questBlockedReason." }
}
finally {
    if (Test-Path $sessionPath) {
        try { Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-cleanup") 20 | Out-Null } catch { }
    }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
