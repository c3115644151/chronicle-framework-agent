#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('noAttack','peacefulYield')][string]$Scenario = 'noAttack',
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [string]$TargetSettlementId = 'town_V1',
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$tempPath = $env:CHRONICLE_HARNESS_TEMP
$frameRoot = if ($tempPath) { $tempPath } else { Join-Path $PSScriptRoot 'TestResults\ManualAlleyAttackYield' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$prefix = "alley-attack-$Scenario-" + (Get-Date -Format 'yyyyMMddHHmmssfff')
$resultName = "AlleyAttackYield-$Scenario-Result.json"
$resultPath = if ($tempPath) { Join-Path $tempPath $resultName } else { Join-Path $frameRoot $resultName }
$frameTown = Join-Path $frameRoot "alley-attack-$Scenario-town.bmp"
$frameMenu = Join-Path $frameRoot "alley-attack-$Scenario-manage-menu.bmp"
$frameDialogue = Join-Path $frameRoot "alley-attack-$Scenario-dialogue.bmp"
$frameAfter = Join-Path $frameRoot "alley-attack-$Scenario-after-yield.bmp"
$failedStep = 'preflight'

if (-not (Test-Path -LiteralPath $savePath)) { throw "Disposable Campaign fixture not found: $LoadSaveName" }
if (Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$sourceHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
. (Join-Path $PSScriptRoot 'Test-AgentSupport.ps1')

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & $HarnessPowerShell -NoProfile -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorActionPreference
    if ($exitCode -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

function Capture-EngineFrame([string]$Path, [string]$Suffix) {
    $receipt = Invoke-AgentCli 'captureFrame' @('-OutputPath', $Path, '-CommandId', "$prefix-frame-$Suffix") 30
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path -LiteralPath $Path) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
    if ($receipt.status -ne 'completed' -or -not (Test-Path -LiteralPath $Path) -or (Get-Item -LiteralPath $Path).Length -lt 4096)
        { throw "Native Alley attack frame was not captured: $Path" }
}

function Continue-AutomaticConversationNodes($Snapshot, [string]$Suffix) {
    $current = $Snapshot
    for ($index = 0; $index -lt 6 -and $current.state.context.conversation; $index++) {
        $clickableOptions = @($current.state.context.conversation.options | Where-Object { $_.clickable })
        if ($clickableOptions.Count -gt 0) { break }
        $continue = Invoke-AgentCli 'dialogueContinue' @('-CommandId', "$prefix-continue-$Suffix-$index") 30
        if ($continue.status -ne 'completed') { break }
        $current = $continue
    }
    return $current
}

function Test-AlleyBusinessStateUnchanged($Before, $After) {
    return ([bool]$Before.playerAlleyDataPresent -eq [bool]$After.playerAlleyDataPresent -and
        [string]$Before.alleyOwnerId -eq [string]$After.alleyOwnerId -and
        [string]$Before.assignedHeroId -eq [string]$After.assignedHeroId -and
        ($Before.alleyRoster | ConvertTo-Json -Compress) -eq ($After.alleyRoster | ConvertTo-Json -Compress) -and
        ($Before.mainPartyRoster | ConvertTo-Json -Compress) -eq ($After.mainPartyRoster | ConvertTo-Json -Compress) -and
        [int]$Before.gold -eq [int]$After.gold -and
        [double]$Before.influence -eq [double]$After.influence -and
        [double]$Before.lastRecruitDay -eq [double]$After.lastRecruitDay)
}

function Get-MainPartyRosterDelta($Before, $After) {
    $beforeCounts = @{}
    foreach ($item in @($Before.mainPartyRoster)) { $beforeCounts[[string]$item.troopId] = [int]$item.count }
    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($item in @($After.mainPartyRoster)) {
        $troopId = [string]$item.troopId
        $oldCount = if ($beforeCounts.ContainsKey($troopId)) { [int]$beforeCounts[$troopId] } else { 0 }
        $delta = [int]$item.count - $oldCount
        if ($delta -ne 0) { $result.Add([pscustomobject]@{ TroopId = $troopId; Before = $oldCount; After = [int]$item.count; Delta = $delta }) }
        $beforeCounts.Remove($troopId)
    }
    foreach ($troopId in @($beforeCounts.Keys)) { $result.Add([pscustomobject]@{ TroopId = [string]$troopId; Before = [int]$beforeCounts[$troopId]; After = 0; Delta = 0 - [int]$beforeCounts[$troopId] }) }
    return @($result)
}

try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $failedStep = 'load-disposable-campaign'
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $initial = Invoke-AgentCli 'state' @('-CommandId', "$prefix-initial")
    if ($initial.state.context.gameState -ne 'MapState' -or [bool]$initial.state.context.inquiryOpen -or [bool]$initial.state.context.escapeMenuOpen)
        { throw 'Fixture must start on a clear Campaign Map.' }
    $visible = Invoke-AgentCli 'mapSettlementTargets' @('-CommandId', "$prefix-visible-settlements")
    $target = @($visible.data.mapSettlementTargets | Where-Object { $_.id -eq $TargetSettlementId -and -not $_.hostile } | Select-Object -First 1)
    if ($target.Count -ne 1) { throw "Town '$TargetSettlementId' is not currently visible and nonhostile." }
    $move = Invoke-AgentCli 'move' @('-SettlementId', $TargetSettlementId, '-CommandId', "$prefix-move")
    if ($move.status -ne 'completed') { throw "Native map movement failed: $($move.error)" }
    $arrival = Wait-ForAgentSettlementArrival -CliPath $cli -SettlementId $TargetSettlementId -CommandPrefix "$prefix-arrival" -TimeoutSeconds $TimeoutSeconds
    if ($arrival.state.context.gameState -ne 'MapState' -or $arrival.state.location.currentSettlementId -ne $TargetSettlementId)
        { throw 'The Campaign Map Party did not reach the Town menu.' }

    $failedStep = 'prepare-disposable-player-Alley'
    $fixture = Invoke-AgentCli 'harnessPrepareAlleyRosterFixture' @('-SettlementId', $TargetSettlementId, '-MenuId', 'town', '-AlleyVolunteerScenario', 'natural', '-CommandId', "$prefix-player-alley") 60
    if ($fixture.status -ne 'completed' -or $fixture.state.context.menuId -ne 'town') { throw 'Native player-Alley fixture did not leave the Campaign on the Town menu.' }
    $alleyTag = [string]$fixture.data.alleyTag
    $alleyBaseline = Invoke-AgentCli 'harnessAlleyRosterDiagnostics' @('-SettlementId', $TargetSettlementId, '-AlleyTag', $alleyTag, '-CommandId', "$prefix-alley-baseline") 30
    if (-not [bool]$alleyBaseline.data.playerAlleyDataPresent -or [bool]$alleyBaseline.data.underAttack -or $alleyBaseline.data.alleyOwnerId -ne 'main_hero')
        { throw 'Fixture requires a player-owned Alley not already under attack.' }
    $attackFixture = $null
    if ($Scenario -eq 'peacefulYield') {
        $failedStep = 'seed-disposable-Native-Alley-attack'
        $attackFixture = Invoke-AgentCli 'harnessSeedAlleyAttackFixture' @('-SettlementId', $TargetSettlementId, '-AlleyTag', $alleyTag, '-CommandId', "$prefix-seed-attack") 30
        if ($attackFixture.status -ne 'completed' -or -not [bool]$attackFixture.data.playerAlleyUnderAttack)
            { throw "Harness did not establish the temporary Native under-attack state: $($attackFixture | ConvertTo-Json -Depth 6 -Compress)" }
        $alleyBaseline = Invoke-AgentCli 'harnessAlleyRosterDiagnostics' @('-SettlementId', $TargetSettlementId, '-AlleyTag', $alleyTag, '-HeroId', [string]$attackFixture.data.attackingHeroId, '-CommandId', "$prefix-attacked-baseline") 30
    }
    Capture-EngineFrame $frameTown 'town'

    $failedStep = 'enter-Native-Alley-management-menu'
    $townMenu = Invoke-AgentCli 'menu' @('-CommandId', "$prefix-town-menu")
    $enterOption = @($townMenu.state.availableMenuOptions | Where-Object { $_.id -eq 'manage_alley' -and $_.available -and $_.enabled } | Select-Object -First 1)
    if ($townMenu.state.context.menuId -ne 'town' -or $enterOption.Count -ne 1) { throw 'Town did not expose its current enabled Native enter-alley option.' }
    $enter = Invoke-AgentCli 'menuSelect' @('-MenuId', 'town', '-OptionId', 'manage_alley', '-CommandId', "$prefix-enter-alley")
    if ($enter.status -ne 'completed' -or $enter.state.context.menuId -ne 'manage_alley' -or $null -ne $enter.state.mission)
        { throw "Native enter-alley did not open the expected MapState management page: $($enter.state.context | ConvertTo-Json -Depth 5 -Compress)" }
    Capture-EngineFrame $frameMenu 'manage-menu'
    $alleyMenu = Invoke-AgentCli 'menu' @('-CommandId', "$prefix-alley-menu")
    $confrontOption = @($alleyMenu.state.availableMenuOptions | Where-Object { $_.id -eq 'confront_hostile_alley_leader' } | Select-Object -First 1)

    if ($Scenario -eq 'noAttack') {
        $confrontAvailable = ($confrontOption.Count -eq 1 -and [bool]$confrontOption[0].available -and [bool]$confrontOption[0].enabled)
        $after = Invoke-AgentCli 'harnessAlleyRosterDiagnostics' @('-SettlementId', $TargetSettlementId, '-AlleyTag', $alleyTag, '-CommandId', "$prefix-no-attack-after") 30
        $noAttackStateStable = Test-AlleyBusinessStateUnchanged $alleyBaseline.data $after.data
        $result = [ordered]@{
            Scenario = $Scenario
            ProviderKind = 'Native town→manage_alley MenuOptions without PlayerAlleyData UnderAttackBy'
            ProcessId = $start.session.processId
            TownOption = $enterOption[0]
            AlleyMenuOptions = $alleyMenu.state.availableMenuOptions
            ConfrontOptionAbsentOrUnavailable = (-not $confrontAvailable)
            BusinessStateUnchanged = $noAttackStateStable
            ClockStable = ([double]$alleyBaseline.data.campaignDay -eq [double]$after.data.campaignDay -and [string]$alleyBaseline.data.timeControlMode -eq [string]$after.data.timeControlMode -and [bool]$alleyBaseline.data.isWaiting -eq [bool]$after.data.isWaiting)
            EngineFrames = @($frameTown, $frameMenu)
            SourceFixtureHashBefore = $sourceHashBefore
        }
        $result.Passed = ($result.ConfrontOptionAbsentOrUnavailable -and $result.BusinessStateUnchanged -and $result.ClockStable)
    }
    else {
        $failedStep = 'select-Native-confront-hostile-alley-leader'
        if ($confrontOption.Count -ne 1 -or -not [bool]$confrontOption[0].available -or -not [bool]$confrontOption[0].enabled)
            { throw "Under-attack Alley menu did not expose the enabled confront option: $($alleyMenu.state.availableMenuOptions | ConvertTo-Json -Depth 4 -Compress)" }
        $confront = Invoke-AgentCli 'menuSelect' @('-MenuId', 'manage_alley', '-OptionId', 'confront_hostile_alley_leader', '-CommandId', "$prefix-confront")
        $conversationState = Continue-AutomaticConversationNodes $confront 'attack-start'
        $introOptionsChosen = [System.Collections.Generic.List[object]]::new()
        for ($introIndex = 0; $introIndex -lt 4 -and $conversationState.state.context.conversation; $introIndex++) {
            $currentOptions = @($conversationState.state.context.conversation.options | Where-Object { $_.clickable })
            if (@($currentOptions | Where-Object { $_.id -in @('alley_talk_start_normal_3','alley_talk_start_normal_4') }).Count -gt 0) { break }
            $introOption = @($currentOptions | Where-Object { $_.id -in @('lord_meet_player_response1','lord_meet_player_response2','lord_meet_player_response3') } | Select-Object -First 1)
            if ($introOption.Count -ne 1) { break }
            $introOptionsChosen.Add($introOption[0])
            $introReceipt = Invoke-AgentCli 'dialogueSelect' @('-OptionId', [string]$introOption[0].id, '-CommandId', "$prefix-intro-$introIndex")
            if ($introReceipt.status -ne 'completed') { throw "Native dialogue introduction option was not submitted: $($introReceipt.error)" }
            $conversationState = Continue-AutomaticConversationNodes $introReceipt "attack-intro-$introIndex"
        }
        $currentDialogueOptions = @($conversationState.state.context.conversation.options | Where-Object { $_.clickable })
        $attackDialogueVisible = @($currentDialogueOptions | Where-Object { $_.id -in @('alley_talk_start_normal_3','alley_talk_start_normal_4') }).Count -gt 0
        $leaveFirstMeeting = @($currentDialogueOptions | Where-Object { $_.id -eq 'player_is_leaving_neutral_or_friendly' } | Select-Object -First 1)
        if (-not $attackDialogueVisible -and $leaveFirstMeeting.Count -eq 1) {
            $failedStep = 'close-Native-first-meeting-and-reopen-attack-dialogue'
            $introOptionsChosen.Add($leaveFirstMeeting[0])
            $leaveReceipt = Invoke-AgentCli 'dialogueSelect' @('-OptionId', [string]$leaveFirstMeeting[0].id, '-CommandId', "$prefix-leave-first-meeting")
            if ($leaveReceipt.status -ne 'completed') { throw "Native first-meeting exit was not submitted: $($leaveReceipt.error)" }
            $afterFirstMeeting = Continue-AutomaticConversationNodes (Invoke-AgentCli 'state' @('-CommandId', "$prefix-after-first-meeting") 30) 'after-first-meeting'
            if ($afterFirstMeeting.state.context.conversation -or $afterFirstMeeting.state.context.gameState -ne 'MapState' -or $afterFirstMeeting.state.context.menuId -ne 'manage_alley')
                { throw "Native first-meeting exit did not return to the attacked-Alley management menu: $($afterFirstMeeting.state.context | ConvertTo-Json -Depth 5 -Compress)" }
            $reopenedMenu = Invoke-AgentCli 'menu' @('-CommandId', "$prefix-reopen-attack-menu")
            $reopenOption = @($reopenedMenu.state.availableMenuOptions | Where-Object { $_.id -eq 'confront_hostile_alley_leader' -and $_.available -and $_.enabled } | Select-Object -First 1)
            if ($reopenOption.Count -ne 1) { throw 'The attacked-Alley Native confrontation option was not available after closing the standard first-meeting dialogue.' }
            $reconfront = Invoke-AgentCli 'menuSelect' @('-MenuId', 'manage_alley', '-OptionId', 'confront_hostile_alley_leader', '-CommandId', "$prefix-reconfront")
            if ($reconfront.status -ne 'completed') { throw "Native re-entry into the Alley attack dialogue failed: $($reconfront.error)" }
            $conversationState = Continue-AutomaticConversationNodes $reconfront 'attack-reentry'
        }
        $conversation = $conversationState.state.context.conversation
        $fightOption = @($conversation.options | Where-Object { $_.id -eq 'alley_talk_start_normal_3' -and $_.clickable } | Select-Object -First 1)
        $yieldOption = @($conversation.options | Where-Object { $_.id -eq 'alley_talk_start_normal_4' -and $_.clickable } | Select-Object -First 1)
        if ($confront.status -ne 'completed' -or -not $conversation -or [string]$conversation.heroId -ne [string]$attackFixture.data.attackingHeroId -or $fightOption.Count -ne 1 -or $yieldOption.Count -ne 1)
            { throw "Native attack dialogue identity/options did not match the seeded hostile Alley leader: $($conversation | ConvertTo-Json -Depth 6 -Compress)" }
        Capture-EngineFrame $frameDialogue 'attacked-dialogue'
        $relationBeforeYield = [int]$alleyBaseline.data.mainHeroRelationToReferenceHero

        $failedStep = 'select-Native-peaceful-Alley-yield'
        $yieldReceipt = Invoke-AgentCli 'dialogueSelect' @('-OptionId', 'alley_talk_start_normal_4', '-CommandId', "$prefix-yield")
        if ($yieldReceipt.status -ne 'completed') { throw "Native peaceful-yield option was not submitted: $($yieldReceipt.error)" }
        $afterYield = Continue-AutomaticConversationNodes (Invoke-AgentCli 'state' @('-CommandId', "$prefix-after-yield") 30) 'after-yield'
        Capture-EngineFrame $frameAfter 'after-yield'
        $after = Invoke-AgentCli 'harnessAlleyRosterDiagnostics' @('-SettlementId', $TargetSettlementId, '-AlleyTag', $alleyTag, '-HeroId', [string]$attackFixture.data.attackingHeroId, '-CommandId', "$prefix-after-yield-diagnostics") 30
        $partyDelta = Get-MainPartyRosterDelta $alleyBaseline.data $after.data
        $positivePartyDeltas = @($partyDelta | Where-Object { [int]$_.Delta -gt 0 })
        $returnedCount = 0
        if ($positivePartyDeltas.Count -gt 0) { $returnedCount = [int]($positivePartyDeltas | Measure-Object -Property Delta -Sum).Sum }
        $stateTransitions = ([bool]$alleyBaseline.data.playerAlleyDataPresent -and -not [bool]$after.data.playerAlleyDataPresent -and [string]$after.data.alleyOwnerId -eq [string]$attackFixture.data.attackingHeroId)
        $relationStable = [int]$after.data.mainHeroRelationToReferenceHero -eq $relationBeforeYield
        $resourcesStable = ([int]$alleyBaseline.data.gold -eq [int]$after.data.gold -and [double]$alleyBaseline.data.influence -eq [double]$after.data.influence)
        $conversationClosedToMap = (-not $afterYield.state.context.conversation -and $afterYield.state.context.gameState -eq 'MapState')
        $result = [ordered]@{
            Scenario = $Scenario
            ProviderKind = 'Native manage_alley confront_hostile_alley_leader→CampaignMapConversation→observed peaceful response'
            ProcessId = $start.session.processId
            Fixture = $attackFixture.data
            TownOption = $enterOption[0]
            ConfrontOption = $confrontOption[0]
            Conversation = $conversation
            NativeIntroductionOptionsChosen = @($introOptionsChosen)
            FightOptionUnselected = [string]$fightOption[0].id
            PeacefulYieldOption = $yieldOption[0]
            YieldReceipt = $yieldReceipt.data
            ConversationAfterYield = $afterYield.state.context.conversation
            ConversationClosedToMap = $conversationClosedToMap
            PlayerAlleyDataRemovedAndOwnerTransferred = $stateTransitions
            HostileOwnerRelationBefore = $relationBeforeYield
            HostileOwnerRelationAfter = [int]$after.data.mainHeroRelationToReferenceHero
            RelationStableAcrossYield = $relationStable
            MainPartyRosterBefore = $alleyBaseline.data.mainPartyRoster
            MainPartyRosterAfter = $after.data.mainPartyRoster
            MainPartyRosterDelta = @($partyDelta)
            OrdinaryAlleyTroopsReturned = [int]$returnedCount
            GoldAndInfluenceStable = $resourcesStable
            CampaignClockStable = ([double]$alleyBaseline.data.campaignDay -eq [double]$after.data.campaignDay -and [string]$alleyBaseline.data.timeControlMode -eq [string]$after.data.timeControlMode -and [bool]$alleyBaseline.data.isWaiting -eq [bool]$after.data.isWaiting)
            EngineFrames = @($frameTown, $frameMenu, $frameDialogue, $frameAfter)
            SourceFixtureHashBefore = $sourceHashBefore
            SourceFixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
        }
    }

    $result.SourceFixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $result.SourceFixtureUnchanged = ($result.SourceFixtureHashBefore -eq $result.SourceFixtureHashAfter)
    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-stop") 30
    $result.ProcessStopped = [bool]$stop.processStopped
    $result.AllGameProcessesStopped = -not [bool](Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue)
    if ($Scenario -eq 'peacefulYield') {
        $result.Passed = ([bool]$result.PlayerAlleyDataRemovedAndOwnerTransferred -and [bool]$result.RelationStableAcrossYield -and [bool]$result.GoldAndInfluenceStable -and [int]$result.OrdinaryAlleyTroopsReturned -gt 0 -and [bool]$result.CampaignClockStable -and [bool]$result.ConversationClosedToMap -and [bool]$result.SourceFixtureUnchanged -and [bool]$result.ProcessStopped -and [bool]$result.AllGameProcessesStopped)
    }
    else { $result.Passed = ([bool]$result.Passed -and [bool]$result.SourceFixtureUnchanged -and [bool]$result.ProcessStopped -and [bool]$result.AllGameProcessesStopped) }
    if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) {
        $result | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $tempPath $resultName) -Encoding UTF8
    }
    $result | ConvertTo-Json -Depth 16
    if (-not $result.Passed) { exit 1 }
}
catch {
    $failureFrame = $null
    if (Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue) {
        try { $failureFrame = Capture-HarnessFailureFrame -CliPath $cli -CommandPrefix $prefix -FailedStep $failedStep -FailureReason $_.Exception.ToString() }
        catch { $failureFrame = [ordered]@{ Captured = $false; Error = $_.Exception.Message } }
    }
    if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) {
        [ordered]@{ Scenario = $Scenario; FailedStep = $failedStep; Exception = $_.Exception.ToString(); FailureFrame = $failureFrame; TimestampUtc = [DateTime]::UtcNow.ToString('O') } |
            ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $tempPath "AlleyAttackYield-$Scenario-Failure.json") -Encoding UTF8
    }
    throw
}
finally {
    if (Test-Path $sessionPath) {
        try { $session = Get-Content $sessionPath -Raw | ConvertFrom-Json; if ($session.status -ne 'stopped') { $null = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-final-stop") 30 } }
        catch { }
    }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
