[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180,
    [int]$MeetingWaitSeconds = 120,
    [int]$ConversationLimit = 16
)

$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$tempPath = $env:CHRONICLE_HARNESS_TEMP
$runDirectory = if ($tempPath) { Split-Path -Parent $tempPath } else { Join-Path $PSScriptRoot 'TestResults\ManualMapPartyQuestAcceptance' }
$frameRoot = if ($tempPath) { $tempPath } else { $runDirectory }
$resultPath = if ($tempPath) { Join-Path $tempPath 'MapPartyQuestAcceptanceResult.json' } else { Join-Path $runDirectory 'MapPartyQuestAcceptanceResult.json' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$prefix = 'map-party-quest-acceptance-' + (Get-Date -Format 'yyyyMMddHHmmssfff')
$currentStep = 'preflight'
$issueFixture = $null
$seededPartyId = $null
$initial = $null
$mapState = $null
$state = $null
$routeTrace = [System.Collections.Generic.List[object]]::new()
$dialogueTrace = [System.Collections.Generic.List[object]]::new()

if (-not (Test-Path -LiteralPath $savePath)) { throw "Map party Quest acceptance fixture not found: $LoadSaveName" }
if (Get-Process -Name Bannerlord -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
. (Join-Path $PSScriptRoot 'Test-AgentSupport.ps1')

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

function Capture-EngineFrame([string]$Path, [string]$Suffix) {
    $receipt = Invoke-AgentCli 'captureFrame' @('-OutputPath', $Path, '-CommandId', "$prefix-$Suffix") 30
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path -LiteralPath $Path) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
    $exists = Test-Path -LiteralPath $Path
    $length = if ($exists) { (Get-Item -LiteralPath $Path).Length } else { 0 }
    if ($receipt.status -ne 'completed' -or -not $exists -or $length -lt 4096)
        { throw "Native map-party conversation frame '$Path' was not captured (receipt='$($receipt.status)', exists=$exists, bytes=$length)." }
}

function Get-ClickableConversationOptions($Snapshot) {
    if ($null -eq $Snapshot.state.context.conversation) { return @() }
    return @($Snapshot.state.context.conversation.options | Where-Object { $_.clickable })
}

function Select-ObservedOption([string]$OptionId, [string]$Reason) {
    $options = Get-ClickableConversationOptions $state
    $match = @($options | Where-Object { $_.id -eq $OptionId } | Select-Object -First 1)
    if ($match.Count -ne 1) {
        throw "Required Native Conversation option '$OptionId' was not clickable. Current=$($options | ConvertTo-Json -Compress)"
    }
    $receipt = Invoke-AgentCli 'dialogueSelect' @('-OptionId', $OptionId, '-CommandId', "$prefix-dialogue-$([Guid]::NewGuid().ToString('N'))") 30
    if ($receipt.status -ne 'completed') { throw "Native option '$OptionId' was rejected: $($receipt.error)" }
    $dialogueTrace.Add([ordered]@{ reason = $Reason; optionId = $OptionId; text = $match[0].text; campaignDay = $receipt.campaignDay; timeControlMode = $receipt.timeControlMode })
    return $receipt
}

try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $currentStep = 'load-disposable-campaign'
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $initial = Invoke-AgentCli 'state' @('-CommandId', "$prefix-initial")
    if ($initial.state.context.gameState -ne 'MapState' -or $initial.state.context.encounterActive -or $initial.state.context.captivity)
        { throw 'Fixture must start as a free Campaign Map party with no active Encounter.' }
    $mapStartupDiagnostics = Invoke-AgentCli 'harnessMapDiagnostics' @('-CommandId', "$prefix-map-startup-diagnostics") 30
    if ($mapStartupDiagnostics.status -ne 'completed' -or -not [bool]$mapStartupDiagnostics.data.harnessFocusLossEscapeMenuGuardInstalled)
        { throw "visual Harness did not install its focus-loss Escape-menu guard before gameplay input: $($mapStartupDiagnostics.data | ConvertTo-Json -Compress)" }
    if ([bool]$mapStartupDiagnostics.data.escapeMenuOpen -or [bool]$mapStartupDiagnostics.data.mapStateAtMenu)
        { throw "Native Escape/Map menu blocks Campaign map input before test actions: $($mapStartupDiagnostics.data | ConvertTo-Json -Compress)" }
    $questCountBefore = @($initial.state.quests).Count
    $goldBefore = [int]$initial.state.economy.gold
    $relationSummary = [ordered]@{}

    $currentStep = 'find-current-visible-map-lord'
    $targetQuery = Invoke-AgentCli 'mapPartyTargets' @('-CommandId', "$prefix-map-targets-before") 30
    if ($targetQuery.status -ne 'completed') { throw 'Native mapPartyTargets query failed before the map Lord route.' }
    $lords = @($targetQuery.data.mapPartyTargets | Where-Object { $_.type -eq 'lord' -and -not [bool]$_.isArmyLeader -and $null -ne $_.questMarkers -and @($_.questMarkers).Count -eq 0 -and [double]$_.distance -lt 12 } | Select-Object -First 12)
    if ($lords.Count -eq 0) { throw 'No current Native nameplate-eligible Lord without an existing marker was visible within the test approach range.' }

    $currentStep = 'prepare-one-native-valid-issue-owner-for-the-disposable-map-party-route'
    $seedErrors = [System.Collections.Generic.List[string]]::new()
    foreach ($lord in $lords) {
        try {
            $issueFixture = Invoke-AgentCli 'harnessSeedMapPartyIssueMarker' @('-PartyId', [string]$lord.id, '-CommandId', "$prefix-native-map-issue-$($lord.id)") 30
            if ($issueFixture.status -eq 'completed' -and [bool]$issueFixture.data.nativeIssueFixtureCreated -and
                @($issueFixture.data.nativeHeroQuestMarkerFlags | Where-Object { $_ -eq 'AvailableIssue' }).Count -gt 0) {
                $seededPartyId = [string]$lord.id
                break
            }
            $seedErrors.Add("$($lord.id): fixture did not create an AvailableIssue marker")
        }
        catch {
            if ($_.Exception.Message -match 'Native IssueManager found no currently eligible Issue candidate|already owns an Issue|no Native Nameplate candidate') {
                $seedErrors.Add("$($lord.id): $($_.Exception.Message)")
                continue
            }
            throw
        }
    }
    if (-not $seededPartyId) { throw "No current map-visible Lord could host a Native AvailableIssue fixture. $($seedErrors -join ' | ')" }
    $sourceParty = @($lords | Where-Object { $_.id -eq $seededPartyId } | Select-Object -First 1)[0]

    $currentStep = 'capture-native-available-issue-marker-before-map-contact'
    $afterIssueTargets = Invoke-AgentCli 'mapPartyTargets' @('-CommandId', "$prefix-map-targets-after-issue") 30
    $targetAfterIssue = @($afterIssueTargets.data.mapPartyTargets | Where-Object { $_.id -eq $seededPartyId } | Select-Object -First 1)
    if ($afterIssueTargets.status -ne 'completed' -or $targetAfterIssue.Count -ne 1 -or -not [bool]$targetAfterIssue[0].hasAvailableIssueMarker)
        { throw "Native available Issue marker disappeared before pursuing its owner. Target=$($targetAfterIssue | ConvertTo-Json -Compress)" }
    $beforeFrame = Join-Path $frameRoot 'map-lord-issue-before-approach.bmp'
    $meetingFrame = Join-Path $frameRoot 'map-lord-issue-meeting.bmp'
    $afterFrame = Join-Path $frameRoot 'map-lord-issue-accepted.bmp'
    Capture-EngineFrame $beforeFrame 'native-lord-issue-before-approach'

    $currentStep = 'approach-current-native-map-party-through-engage'
    $approach = Invoke-AgentCli 'pursue' @('-PartyId', $seededPartyId, '-CommandId', "$prefix-native-pursue-lord") 30
    if ($approach.status -ne 'completed' -or $approach.state.location.targetPartyId -ne $seededPartyId)
        { throw "Native map approach did not retain selected Lord target: $($approach | ConvertTo-Json -Depth 6 -Compress)" }
    $routeTrace.Add([ordered]@{ step = 'pursueObservedLordParty'; partyId = $seededPartyId; receipt = $approach })

    $currentStep = 'wait-for-native-map-lord-meeting'
    $meetingDeadline = [DateTime]::UtcNow.AddSeconds($MeetingWaitSeconds)
    $timeouts = 0
    while ([DateTime]::UtcNow -lt $meetingDeadline) {
        try { $state = Invoke-AgentCli 'state' @('-CommandId', "$prefix-meeting-poll-$([Guid]::NewGuid().ToString('N'))") 8; $timeouts = 0 }
        catch {
            if ($_.Exception.Message -notmatch 'timed out after') { throw }
            $timeouts++
            if ($timeouts -ge 3) { throw 'Game stopped answering while waiting for the Native map Lord meeting.' }
            if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'Bannerlord exited before the map Lord meeting appeared.' }
            continue
        }
        if ($state.state.context.menuId -eq 'encounter_meeting' -and $state.state.context.encounterActive -and $state.state.context.conversation) { break }
        if ($state.state.context.menuId -in @('join_encounter','army_encounter','join_siege_event','encounter') -or $state.state.context.captivity)
            { throw "Map approach entered '$($state.state.context.menuId)' instead of the peaceful Lord meeting. Context=$($state.state.context | ConvertTo-Json -Compress)" }
        if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'Bannerlord exited before the map Lord meeting appeared.' }
        Start-Sleep -Milliseconds 250
    }
    if ($state.state.context.menuId -ne 'encounter_meeting' -or -not $state.state.context.conversation)
        { throw "Native peaceful Lord meeting did not appear within $MeetingWaitSeconds seconds. Context=$($state.state.context | ConvertTo-Json -Depth 6 -Compress)" }
    Capture-EngineFrame $meetingFrame 'native-map-lord-meeting'

    $currentStep = 'advance-native-map-lord-conversation-only-through-current-options'
    $accepted = $false
    $acceptReceipt = $null
    for ($turn = 1; $turn -le $ConversationLimit; $turn++) {
        $options = Get-ClickableConversationOptions $state
        $acceptOption = @($options | Where-Object { $_.id -eq 'issue_offer_player_accept_quest' } | Select-Object -First 1)
        if ($acceptOption.Count -eq 1) {
            $acceptReceipt = Select-ObservedOption 'issue_offer_player_accept_quest' 'Native enabled Quest acceptance option'
            $accepted = $true
            break
        }
        $nextOption = $null
        if (@($options | Where-Object { $_.id -eq 'hero_give_issue' }).Count -gt 0) { $nextOption = 'hero_give_issue' }
        elseif (@($options | Where-Object { $_.id -eq 'issue_explanation_player_response_pre_quest_solution' }).Count -gt 0) { $nextOption = 'issue_explanation_player_response_pre_quest_solution' }
        elseif (@($options | Where-Object { $_.id -eq 'issue_alternative_solution_player_response' }).Count -gt 0) { $nextOption = 'issue_alternative_solution_player_response' }
        elseif ($options.Count -gt 0) {
            $greeting = @($options | Where-Object { $_.id -like 'lord_meet_player_response*' } | Select-Object -First 1)
            if ($greeting.Count -eq 1) { $nextOption = [string]$greeting[0].id }
        }
        if ($nextOption) {
            $null = Select-ObservedOption $nextOption 'Observed Native current Conversation option'
        }
        elseif ($options.Count -eq 0 -and $state.state.context.conversation) {
            $continue = Invoke-AgentCli 'dialogueContinue' @('-CommandId', "$prefix-native-dialogue-continue-$turn") 30
            if ($continue.status -ne 'completed') { throw "Native Continue with no current options was rejected: $($continue.error)" }
            $dialogueTrace.Add([ordered]@{ reason = 'Native conversation had no current option'; action = 'dialogueContinue'; campaignDay = $continue.campaignDay; timeControlMode = $continue.timeControlMode })
        }
        else { break }

        $state = Invoke-AgentCli 'state' @('-CommandId', "$prefix-conversation-state-$turn") 15
        if (@($state.state.quests).Count -gt $questCountBefore) { break }
        if ($state.state.context.menuId -ne 'encounter_meeting' -and @($state.state.quests).Count -le $questCountBefore)
            { throw "Map Lord conversation left encounter_meeting before the Quest result was observed: $($state.state.context | ConvertTo-Json -Compress)" }
    }
    if (-not $accepted) { throw "No current Enabled issue_offer_player_accept_quest option appeared in this map Lord conversation. Trace=$($dialogueTrace | ConvertTo-Json -Compress); LastState=$($state.state.context | ConvertTo-Json -Compress)" }

    $currentStep = 'verify-native-quest-started-from-map-lord'
    $afterDeadline = [DateTime]::UtcNow.AddSeconds(20)
    while (@($state.state.quests).Count -le $questCountBefore -and [DateTime]::UtcNow -lt $afterDeadline) {
        $state = Invoke-AgentCli 'state' @('-CommandId', "$prefix-after-accept-$([Guid]::NewGuid().ToString('N'))") 15
        Start-Sleep -Milliseconds 150
    }
    $questCountAfter = @($state.state.quests).Count
    if ($questCountAfter -ne ($questCountBefore + 1)) { throw "Native acceptance did not add exactly one active Quest. before=$questCountBefore after=$questCountAfter" }
    $newQuest = @($state.state.quests | Where-Object { $_.id -notin @($initial.state.quests | ForEach-Object id) } | Select-Object -First 1)
    if ($newQuest.Count -ne 1) { throw 'The newly started Quest could not be distinguished from the initially observed Quest IDs.' }
    $afterQuestPartyTargets = Invoke-AgentCli 'mapPartyTargets' @('-CommandId', "$prefix-party-markers-after-quest") 30
    $partyAfterQuest = @($afterQuestPartyTargets.data.mapPartyTargets | Where-Object { $_.id -eq $seededPartyId } | Select-Object -First 1)
    $questMarkerAdvancedToActive = ($afterQuestPartyTargets.status -eq 'completed' -and $partyAfterQuest.Count -eq 1 -and
        @($partyAfterQuest[0].questMarkers | Where-Object { $_ -eq 'ActiveIssue' }).Count -gt 0 -and -not [bool]$partyAfterQuest[0].hasAvailableIssueMarker)
    if (-not $questMarkerAdvancedToActive)
        { throw "Accepted Quest did not update the current map Party marker from AvailableIssue to ActiveIssue: $($partyAfterQuest | ConvertTo-Json -Compress)" }
    Capture-EngineFrame $afterFrame 'native-map-lord-quest-started'

    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-stop") 30
    $allProcessesStopped = -not [bool](Get-Process -Name Bannerlord -ErrorAction SilentlyContinue)
    $result = [ordered]@{
        ProviderKind = 'Native current mapPartyTargets marker -> pursue -> map Lord Conversation -> enabled Issue Quest option'
        ProcessId = $start.session.processId
        SeededPartyId = $seededPartyId
        HarnessWindowDiagnostics = [ordered]@{
            mapStateAtMenu = [bool]$mapStartupDiagnostics.data.mapStateAtMenu
            escapeMenuOpen = [bool]$mapStartupDiagnostics.data.escapeMenuOpen
            focusLossEscapeMenuGuardInstalled = [bool]$mapStartupDiagnostics.data.harnessFocusLossEscapeMenuGuardInstalled
        }
        IssueFixture = $issueFixture.data
        Target = $sourceParty
        MapApproach = $approach
        RouteTrace = $routeTrace
        DialogueTrace = $dialogueTrace
        NativeAcceptanceReceipt = $acceptReceipt
        Before = [ordered]@{ questCount = $questCountBefore; gold = $goldBefore; campaignDay = $initial.campaignDay; timeControlMode = $initial.timeControlMode }
        After = [ordered]@{ questCount = $questCountAfter; quest = $newQuest[0]; gold = $state.state.economy.gold; campaignDay = $state.campaignDay; timeControlMode = $state.timeControlMode; context = $state.state.context }
        NativeMapPartyMarkerObserved = [bool]$targetAfterIssue[0].hasAvailableIssueMarker
        QuestAcceptedFromMapParty = $accepted
        ActiveQuestAdded = ($questCountAfter -eq ($questCountBefore + 1))
        QuestMarkerAdvancedToActive = $questMarkerAdvancedToActive
        PartyMarkerAfterQuest = $partyAfterQuest[0]
        QuestTextNotInjectedIntoObservation = $state.state.quests.Count -eq $questCountAfter
        EngineFrames = @($beforeFrame, $meetingFrame, $afterFrame)
        SourceFixtureHashBefore = $fixtureHashBefore
        SourceFixtureHashAfter = $fixtureHashAfter
        SourceFixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = [bool]$stop.processStopped
        AllGameProcessesStopped = $allProcessesStopped
        Passed = ($accepted -and $questCountAfter -eq ($questCountBefore + 1) -and $questMarkerAdvancedToActive -and $fixtureHashBefore -eq $fixtureHashAfter -and [bool]$stop.processStopped -and $allProcessesStopped)
    }
    $json = $result | ConvertTo-Json -Depth 18
    if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) { Set-Content -LiteralPath $resultPath -Value $json -Encoding UTF8 }
    $json
    if (-not $result.Passed) { exit 1 }
}
catch {
    $failureFrame = Capture-HarnessFailureFrame -CliPath $cli -CommandPrefix $prefix -FailedStep $currentStep -FailureReason $_.Exception.ToString()
    if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) {
        [ordered]@{ FailedStep = $currentStep; Exception = $_.Exception.ToString(); FailureFrame = $failureFrame; LastContext = if ($state) { $state.state.context } else { $null }; PartyId = $seededPartyId; IssueFixture = if ($issueFixture) { $issueFixture.data } else { $null }; RouteTrace = $routeTrace; DialogueTrace = $dialogueTrace; TimestampUtc = [DateTime]::UtcNow.ToString('O') } |
            ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $tempPath 'MapPartyQuestAcceptanceFailure.json') -Encoding UTF8
    }
    throw
}
finally {
    if (Test-Path $sessionPath) {
        try {
            $session = Get-Content $sessionPath -Raw | ConvertFrom-Json
            if ($session.status -ne 'stopped') { $null = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-final-stop") 30 }
        }
        catch { }
    }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
