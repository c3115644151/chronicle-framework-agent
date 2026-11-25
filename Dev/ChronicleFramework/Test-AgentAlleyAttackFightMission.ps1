#Requires -Version 7.0
[CmdletBinding()]
param(
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
$frameRoot = if ($tempPath) { $tempPath } else { Join-Path $PSScriptRoot 'TestResults\ManualAlleyAttackFight' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$prefix = 'alley-attack-fight-' + (Get-Date -Format 'yyyyMMddHHmmssfff')
$resultName = 'AlleyAttackFightMission-Result.json'
$frameTown = Join-Path $frameRoot 'alley-fight-town.bmp'
$frameMenu = Join-Path $frameRoot 'alley-fight-manage-menu.bmp'
$frameDialogue = Join-Path $frameRoot 'alley-fight-confront-dialogue.bmp'
$frameMission = Join-Path $frameRoot 'alley-fight-mission.bmp'
$frameExitInquiry = Join-Path $frameRoot 'alley-fight-exit-inquiry.bmp'
$frameAfterCancel = Join-Path $frameRoot 'alley-fight-after-exit-cancel.bmp'
$frameAfterRetreat = Join-Path $frameRoot 'alley-fight-after-retreat.bmp'
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
        { throw "Native Alley fight frame was not captured: $Path" }
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

function Wait-ForMissionState([int]$MaxAttempts = 120) {
    for ($attempt = 0; $attempt -lt $MaxAttempts; $attempt++) {
        $snapshot = Invoke-AgentCli 'state' @('-CommandId', "$prefix-mission-poll-$attempt") 30
        $mission = $snapshot.state.mission
        if ($mission -and [bool]$mission.active -and $mission.mainAgent -and [bool]$mission.mainAgent.isPlayerControlled -and
            [int]$mission.activeAgentCount -gt 0 -and [string]$mission.mode -ne 'StartUp') { return $snapshot }
        Start-Sleep -Seconds 1
    }
    return (Invoke-AgentCli 'state' @('-CommandId', "$prefix-mission-timeout") 30)
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
    $seed = Invoke-AgentCli 'harnessSeedAlleyAttackFixture' @('-SettlementId', $TargetSettlementId, '-AlleyTag', $alleyTag, '-CommandId', "$prefix-seed-attack") 30
    if ($seed.status -ne 'completed' -or -not [bool]$seed.data.playerAlleyUnderAttack) { throw 'Harness did not establish the temporary Native under-attack state.' }
    $alleyBefore = Invoke-AgentCli 'harnessAlleyRosterDiagnostics' @('-SettlementId', $TargetSettlementId, '-AlleyTag', $alleyTag, '-HeroId', [string]$seed.data.attackingHeroId, '-CommandId', "$prefix-before-attack") 30
    Capture-EngineFrame $frameTown 'town'

    $failedStep = 'enter-Native-Alley-management-menu'
    $townMenu = Invoke-AgentCli 'menu' @('-CommandId', "$prefix-town-menu")
    $enterOption = @($townMenu.state.availableMenuOptions | Where-Object { $_.id -eq 'manage_alley' -and $_.available -and $_.enabled } | Select-Object -First 1)
    if ($townMenu.state.context.menuId -ne 'town' -or $enterOption.Count -ne 1) { throw 'Town did not expose its current enabled Native enter-alley option.' }
    $enter = Invoke-AgentCli 'menuSelect' @('-MenuId', 'town', '-OptionId', 'manage_alley', '-CommandId', "$prefix-enter-alley")
    if ($enter.status -ne 'completed' -or $enter.state.context.menuId -ne 'manage_alley' -or $null -ne $enter.state.mission)
        { throw 'Native enter-alley did not open the expected MapState management page.' }
    Capture-EngineFrame $frameMenu 'manage-menu'

    $alleyMenu = Invoke-AgentCli 'menu' @('-CommandId', "$prefix-alley-menu")
    $confrontOption = @($alleyMenu.state.availableMenuOptions | Where-Object { $_.id -eq 'confront_hostile_alley_leader' -and $_.available -and $_.enabled } | Select-Object -First 1)
    if ($confrontOption.Count -ne 1) { throw 'The Native attacked-Alley management menu did not expose the current confrontation option.' }
    $confront = Invoke-AgentCli 'menuSelect' @('-MenuId', 'manage_alley', '-OptionId', 'confront_hostile_alley_leader', '-CommandId', "$prefix-confront")
    $conversationState = Continue-AutomaticConversationNodes $confront 'attack-start'
    $initiallyVisibleOptions = [System.Collections.Generic.List[object]]::new()
    for ($introIndex = 0; $introIndex -lt 4 -and $conversationState.state.context.conversation; $introIndex++) {
        $currentOptions = @($conversationState.state.context.conversation.options | Where-Object { $_.clickable })
        if (@($currentOptions | Where-Object { $_.id -in @('alley_talk_start_normal_3','alley_talk_start_normal_4') }).Count -gt 0) { break }
        $introOption = @($currentOptions | Where-Object { $_.id -in @('lord_meet_player_response1','lord_meet_player_response2','lord_meet_player_response3') } | Select-Object -First 1)
        if ($introOption.Count -ne 1) { break }
        $initiallyVisibleOptions.Add($introOption[0])
        $introReceipt = Invoke-AgentCli 'dialogueSelect' @('-OptionId', [string]$introOption[0].id, '-CommandId', "$prefix-intro-$introIndex")
        if ($introReceipt.status -ne 'completed') { throw "Native dialogue introduction option was not submitted: $($introReceipt.error)" }
        $conversationState = Continue-AutomaticConversationNodes $introReceipt "attack-intro-$introIndex"
    }
    $currentOptions = @($conversationState.state.context.conversation.options | Where-Object { $_.clickable })
    $fightOption = @($currentOptions | Where-Object { $_.id -eq 'alley_talk_start_normal_3' } | Select-Object -First 1)
    $yieldOption = @($currentOptions | Where-Object { $_.id -eq 'alley_talk_start_normal_4' } | Select-Object -First 1)
    if (($fightOption.Count -ne 1 -or $yieldOption.Count -ne 1) -and @($currentOptions | Where-Object { $_.id -eq 'player_is_leaving_neutral_or_friendly' }).Count -eq 1) {
        $leave = Invoke-AgentCli 'dialogueSelect' @('-OptionId', 'player_is_leaving_neutral_or_friendly', '-CommandId', "$prefix-leave-first-meeting")
        $afterIntro = Continue-AutomaticConversationNodes (Invoke-AgentCli 'state' @('-CommandId', "$prefix-after-intro") 30) 'after-intro'
        if ($afterIntro.state.context.conversation -or $afterIntro.state.context.gameState -ne 'MapState' -or $afterIntro.state.context.menuId -ne 'manage_alley')
            { throw "Native first-meeting exit did not return to the attacked-Alley management menu: $($afterIntro.state.context | ConvertTo-Json -Depth 5 -Compress)" }
        $reopenMenu = Invoke-AgentCli 'menu' @('-CommandId', "$prefix-reopen-menu")
        $reconfrontOption = @($reopenMenu.state.availableMenuOptions | Where-Object { $_.id -eq 'confront_hostile_alley_leader' -and $_.available -and $_.enabled } | Select-Object -First 1)
        if ($reconfrontOption.Count -ne 1) { throw 'Native Alley confrontation was not available after ending the first-meeting dialogue.' }
        $reconfront = Invoke-AgentCli 'menuSelect' @('-MenuId', 'manage_alley', '-OptionId', 'confront_hostile_alley_leader', '-CommandId', "$prefix-reconfront")
        $conversationState = Continue-AutomaticConversationNodes $reconfront 'attack-reentry'
        $currentOptions = @($conversationState.state.context.conversation.options | Where-Object { $_.clickable })
        $fightOption = @($currentOptions | Where-Object { $_.id -eq 'alley_talk_start_normal_3' } | Select-Object -First 1)
        $yieldOption = @($currentOptions | Where-Object { $_.id -eq 'alley_talk_start_normal_4' } | Select-Object -First 1)
    }
    if ($fightOption.Count -ne 1 -or $yieldOption.Count -ne 1 -or [string]$conversationState.state.context.conversation.heroId -ne [string]$seed.data.attackingHeroId)
        { throw "Native Fight option/attacker identity did not match: $($conversationState.state.context.conversation | ConvertTo-Json -Depth 6 -Compress)" }
    Capture-EngineFrame $frameDialogue 'fight-dialogue'

    $failedStep = 'select-Native-Alley-Fight-option'
    $fightReceipt = Invoke-AgentCli 'dialogueSelect' @('-OptionId', 'alley_talk_start_normal_3', '-CommandId', "$prefix-fight")
    if ($fightReceipt.status -ne 'completed') { throw "Native Fight dialogue option was not submitted: $($fightReceipt.error)" }
    $missionState = Wait-ForMissionState 45
    if (-not $missionState.state.mission -or -not [bool]$missionState.state.mission.active)
        { throw "Native Fight line did not enter a Mission: $($missionState.state.context | ConvertTo-Json -Depth 5 -Compress)" }
    Capture-EngineFrame $frameMission 'fight-mission'
    $missionObservation = $missionState.state.mission
    $missionEntryVerified = ($missionState.state.context.gameState -eq 'MissionState' -and
        [string]$missionObservation.mainAgent.heroId -eq 'main_hero' -and [int]$missionObservation.activeAgentCount -gt 0 -and
        -not [string]::IsNullOrWhiteSpace([string]$missionObservation.sceneName))
    if (-not $missionEntryVerified) { throw "Alley Fight Mission did not show the expected live player combat state: $($missionState.state | ConvertTo-Json -Depth 6 -Compress)" }

    $failedStep = 'read-combat-Mission-exit-baseline'
    $alleyDuringMissionBeforeExit = Invoke-AgentCli 'harnessAlleyRosterDiagnostics' @('-SettlementId', $TargetSettlementId, '-AlleyTag', $alleyTag, '-HeroId', [string]$seed.data.attackingHeroId, '-CommandId', "$prefix-before-native-exit") 30
    $failedStep = 'request-Native-Mission-exit'
    $retreatRequest = Invoke-AgentCli 'missionRetreat' @('-CommandId', "$prefix-retreat-request") 30
    if ($retreatRequest.status -ne 'completed' -or -not [bool]$retreatRequest.state.context.inquiryOpen -or
        -not [bool]$retreatRequest.state.context.inquiry.supported -or $retreatRequest.state.context.gameState -ne 'MissionState')
        { throw "Native Mission exit did not expose its active confirmation Inquiry to the Agent: $($retreatRequest.state.context | ConvertTo-Json -Depth 6 -Compress)" }
    $exitInquiry = $retreatRequest.state.context.inquiry
    if (-not [bool]$exitInquiry.affirmative.visible -or -not [bool]$exitInquiry.affirmative.enabled -or
        -not [bool]$exitInquiry.negative.visible -or -not [bool]$exitInquiry.negative.enabled)
        { throw "Native exit Inquiry did not expose both current enabled choices: $($exitInquiry | ConvertTo-Json -Depth 5 -Compress)" }
    Capture-EngineFrame $frameExitInquiry 'exit-inquiry'
    $alleyWithExitInquiry = Invoke-AgentCli 'harnessAlleyRosterDiagnostics' @('-SettlementId', $TargetSettlementId, '-AlleyTag', $alleyTag, '-HeroId', [string]$seed.data.attackingHeroId, '-CommandId', "$prefix-inquiry-alley") 30

    $failedStep = 'cancel-Native-Mission-exit-confirmation'
    $cancelExit = Invoke-AgentCli 'respondInquiry' @('-InquiryToken', [string]$exitInquiry.token, '-InquiryChoice', 'negative', '-CommandId', "$prefix-cancel-exit") 30
    if ($cancelExit.status -ne 'completed') { throw "Native exit confirmation cancel callback failed: $($cancelExit.error)" }
    $afterCancel = Invoke-AgentCli 'state' @('-CommandId', "$prefix-after-exit-cancel") 30
    $alleyAfterCancel = Invoke-AgentCli 'harnessAlleyRosterDiagnostics' @('-SettlementId', $TargetSettlementId, '-AlleyTag', $alleyTag, '-HeroId', [string]$seed.data.attackingHeroId, '-CommandId', "$prefix-cancel-alley") 30
    $cancelPreservedMission = ($afterCancel.state.context.gameState -eq 'MissionState' -and -not [bool]$afterCancel.state.context.inquiryOpen -and
        [bool]$afterCancel.state.mission.active -and [bool]$afterCancel.state.mission.mainAgent.isPlayerControlled)
    $alleyUnchangedUntilNativeConfirmation = ([bool]$alleyDuringMissionBeforeExit.data.playerAlleyDataPresent -eq [bool]$alleyAfterCancel.data.playerAlleyDataPresent -and
        [string]$alleyDuringMissionBeforeExit.data.alleyOwnerId -eq [string]$alleyAfterCancel.data.alleyOwnerId -and
        ($alleyDuringMissionBeforeExit.data.alleyRoster | ConvertTo-Json -Compress) -eq ($alleyAfterCancel.data.alleyRoster | ConvertTo-Json -Compress) -and
        ($alleyDuringMissionBeforeExit.data.mainPartyRoster | ConvertTo-Json -Compress) -eq ($alleyAfterCancel.data.mainPartyRoster | ConvertTo-Json -Compress) -and
        [int]$alleyDuringMissionBeforeExit.data.mainHeroHitPoints -eq [int]$alleyAfterCancel.data.mainHeroHitPoints)
    if (-not $cancelPreservedMission -or -not $alleyUnchangedUntilNativeConfirmation)
        { throw 'Native exit cancel did not preserve the active Mission, player control, Alley state, roster, and Hero health.' }
    Capture-EngineFrame $frameAfterCancel 'after-exit-cancel'

    $failedStep = 'reopen-and-confirm-Native-Mission-exit'
    $confirmedRequest = Invoke-AgentCli 'missionRetreat' @('-CommandId', "$prefix-retreat-confirm-request") 30
    if ($confirmedRequest.status -ne 'completed' -or -not [bool]$confirmedRequest.state.context.inquiryOpen -or
        -not [bool]$confirmedRequest.state.context.inquiry.supported -or $confirmedRequest.state.context.gameState -ne 'MissionState')
        { throw "Native exit Inquiry did not reopen for the explicit affirmative choice: $($confirmedRequest.state.context | ConvertTo-Json -Depth 6 -Compress)" }
    $confirmExit = Invoke-AgentCli 'respondInquiry' @('-InquiryToken', [string]$confirmedRequest.state.context.inquiry.token, '-InquiryChoice', 'affirmative', '-CommandId', "$prefix-confirm-exit") 30
    if ($confirmExit.status -ne 'completed') { throw "Native exit confirmation affirmative callback failed: $($confirmExit.error)" }
    $afterRetreat = $null
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        $afterRetreat = Invoke-AgentCli 'state' @('-CommandId', "$prefix-after-retreat-$attempt") 30
        if ($afterRetreat.state.context.gameState -eq 'MapState' -and -not $afterRetreat.state.mission) { break }
        Start-Sleep -Milliseconds 500
    }
    if (-not $afterRetreat -or $afterRetreat.state.context.gameState -ne 'MapState' -or $afterRetreat.state.mission)
        { throw "Native retreat did not return to the Campaign Map within 30 seconds: $($afterRetreat.state.context | ConvertTo-Json -Depth 5 -Compress)" }
    Capture-EngineFrame $frameAfterRetreat 'after-retreat'
    $afterAlley = Invoke-AgentCli 'harnessAlleyRosterDiagnostics' @('-SettlementId', $TargetSettlementId, '-AlleyTag', $alleyTag, '-HeroId', [string]$seed.data.attackingHeroId, '-CommandId', "$prefix-after-retreat-alley") 30
    $sourceHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $clockStable = ([double]$alleyBefore.data.campaignDay -eq [double]$afterAlley.data.campaignDay -and
        [string]$alleyBefore.data.timeControlMode -eq [string]$afterAlley.data.timeControlMode -and [bool]$alleyBefore.data.isWaiting -eq [bool]$afterAlley.data.isWaiting)
    $result = [ordered]@{
        Scenario = 'fightMissionNativeExitInquiry'
        ProviderKind = 'Native attacked-Alley conversation→Fight line→AlleyFight Mission→Mission.OnEndMissionRequest→Native Inquiry cancel/affirmative callbacks'
        ProcessId = $start.session.processId
        AttackFixture = $seed.data
        NativeFightOption = $fightOption[0]
        NativeYieldOptionAlsoVisible = $yieldOption[0]
        NativeFirstMeetingOptions = @($initiallyVisibleOptions)
        MissionEntry = [ordered]@{ GameState = $missionState.state.context.gameState; SceneName = $missionObservation.sceneName; CombatType = $missionObservation.combatType; Mode = $missionObservation.mode; ActiveAgentCount = $missionObservation.activeAgentCount; MainAgent = $missionObservation.mainAgent; Leave = $missionObservation.leave }
        MissionEntryVerified = $missionEntryVerified
        NativeExitRequest = $retreatRequest.data
        NativeExitInquiry = $exitInquiry
        NativeCancelReceipt = $cancelExit.data
        NativeCancelPreservedMission = $cancelPreservedMission
        AlleyUnchangedUntilNativeConfirmation = $alleyUnchangedUntilNativeConfirmation
        NativeAffirmativeReceipt = $confirmExit.data
        ReturnedToMap = ($afterRetreat.state.context.gameState -eq 'MapState' -and -not $afterRetreat.state.mission)
        MenuAfterRetreat = $afterRetreat.state.context.menuId
        AlleyBefore = $alleyBefore.data
        AlleyAfter = $afterAlley.data
        AlleyLostAfterRetreat = (-not [bool]$afterAlley.data.playerAlleyDataPresent -and [string]$afterAlley.data.alleyOwnerId -eq [string]$seed.data.attackingHeroId)
        MainHeroHitPointsAfterRetreat = [int]$afterAlley.data.mainHeroHitPoints
        GoldAndInfluenceStable = ([int]$alleyBefore.data.gold -eq [int]$afterAlley.data.gold -and [double]$alleyBefore.data.influence -eq [double]$afterAlley.data.influence)
        CampaignClockStable = $clockStable
        SourceFixtureHashBefore = $sourceHashBefore
        SourceFixtureHashAfter = $sourceHashAfter
        SourceFixtureUnchanged = ($sourceHashBefore -eq $sourceHashAfter)
        EngineFrames = @($frameTown, $frameMenu, $frameDialogue, $frameMission, $frameExitInquiry, $frameAfterCancel, $frameAfterRetreat)
    }
    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-stop") 30
    $result.ProcessStopped = [bool]$stop.processStopped
    $result.AllGameProcessesStopped = -not [bool](Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue)
    $result.MissionExitInquiryVisible = ([bool]$exitInquiry.supported -and $exitInquiry.kind -eq 'YesNoInquiry' -and
        [bool]$exitInquiry.affirmative.visible -and [bool]$exitInquiry.negative.visible)
    $result.Passed = ([bool]$result.MissionEntryVerified -and [bool]$result.MissionExitInquiryVisible -and [bool]$result.NativeCancelPreservedMission -and
        [bool]$result.AlleyUnchangedUntilNativeConfirmation -and [bool]$result.ReturnedToMap -and [bool]$result.AlleyLostAfterRetreat -and
        [int]$result.MainHeroHitPointsAfterRetreat -eq 1 -and [bool]$result.GoldAndInfluenceStable -and [bool]$result.CampaignClockStable -and
        [bool]$result.SourceFixtureUnchanged -and [bool]$result.ProcessStopped -and [bool]$result.AllGameProcessesStopped)
    if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) {
        $result | ConvertTo-Json -Depth 18 | Set-Content -LiteralPath (Join-Path $tempPath $resultName) -Encoding UTF8
    }
    $result | ConvertTo-Json -Depth 18
    if (-not $result.Passed) { exit 1 }
}
catch {
    $failureFrame = $null
    if (Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue) {
        try { $failureFrame = Capture-HarnessFailureFrame -CliPath $cli -CommandPrefix $prefix -FailedStep $failedStep -FailureReason $_.Exception.ToString() }
        catch { $failureFrame = [ordered]@{ Captured = $false; Error = $_.Exception.Message } }
    }
    if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) {
        [ordered]@{ FailedStep = $failedStep; Exception = $_.Exception.ToString(); FailureFrame = $failureFrame; TimestampUtc = [DateTime]::UtcNow.ToString('O') } |
            ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $tempPath 'AlleyAttackFightMission-Failure.json') -Encoding UTF8
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
