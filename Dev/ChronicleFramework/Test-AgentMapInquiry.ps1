[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$tempPath = $env:CHRONICLE_HARNESS_TEMP
$frameRoot = if ($tempPath) { $tempPath } else { Join-Path $PSScriptRoot 'TestResults\ManualMapInquiry' }
$resultPath = if ($tempPath) { Join-Path $tempPath 'MapInquiryResult.json' } else { Join-Path $frameRoot 'MapInquiryResult.json' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$prefix = 'map-inquiry-' + (Get-Date -Format 'yyyyMMddHHmmssfff')
$step = 'preflight'
$state = $null
$frameBefore = Join-Path $frameRoot 'map-inquiry-before.bmp'
$frameOpen = Join-Path $frameRoot 'map-inquiry-open.bmp'
$frameAccepted = Join-Path $frameRoot 'map-inquiry-accepted.bmp'
$frameOpenNegative = Join-Path $frameRoot 'map-inquiry-negative-open.bmp'
$frameDeclined = Join-Path $frameRoot 'map-inquiry-declined.bmp'
$frameRecruitmentOpen = Join-Path $frameRoot 'map-inquiry-recruitment-native-open.bmp'
$frameRecruitmentAccepted = Join-Path $frameRoot 'map-inquiry-recruitment-native-accepted.bmp'

if (-not (Test-Path -LiteralPath $savePath)) { throw "Disposable Campaign fixture not found: $LoadSaveName" }
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
    $receipt = Invoke-AgentCli 'captureFrame' @('-OutputPath', $Path, '-CommandId', "$prefix-frame-$Suffix") 30
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path -LiteralPath $Path) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
    if ($receipt.status -ne 'completed' -or -not (Test-Path -LiteralPath $Path) -or (Get-Item -LiteralPath $Path).Length -lt 4096)
        { throw "Native Inquiry frame was not captured: $Path; receipt=$($receipt | ConvertTo-Json -Depth 4 -Compress)" }
}

function Open-HarnessInquiry([string]$Suffix) {
    $receipt = Invoke-AgentCli 'harnessOpenNativeInquiry' @('-CommandId', "$prefix-open-$Suffix") 30
    if ($receipt.status -ne 'completed' -or -not [bool]$receipt.data.fixtureCreated) { throw "Native Inquiry fixture failed: $($receipt.error)" }
    $observed = Invoke-AgentCli 'state' @('-CommandId', "$prefix-state-open-$Suffix")
    if ($observed.state.context.gameState -ne 'MapState' -or -not [bool]$observed.state.context.inquiryOpen -or -not [bool]$observed.state.context.inquiry.supported)
        { throw "Native active Inquiry was not exposed: $($observed.state.context | ConvertTo-Json -Compress)" }
    if ($observed.state.context.inquiry.title -ne 'Chronicle Harness Confirmation' -or -not [bool]$observed.state.context.inquiry.affirmative.enabled -or -not [bool]$observed.state.context.inquiry.negative.enabled)
        { throw "Active Native Inquiry title/buttons differ from the VM: $($observed.state.context.inquiry | ConvertTo-Json -Compress)" }
    $repeat = Invoke-AgentCli 'state' @('-CommandId', "$prefix-state-repeat-$Suffix")
    if ($repeat.state.context.inquiry.token -ne $observed.state.context.inquiry.token) { throw 'Repeated state observation changed the current Inquiry token.' }
    return $observed
}

try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $step = 'load-disposable-campaign'
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $state = Invoke-AgentCli 'state' @('-CommandId', "$prefix-initial")
    if ($state.state.context.gameState -ne 'MapState' -or [bool]$state.state.context.inquiryOpen -or [bool]$state.state.context.escapeMenuOpen)
        { throw 'Fixture must start on a clear Campaign Map.' }
    $pause = Invoke-AgentCli 'pause' @('-CommandId', "$prefix-pause")
    if ($pause.status -ne 'completed') { throw 'Could not pause disposable Campaign before Inquiry-only comparison.' }
    $before = Invoke-AgentCli 'state' @('-CommandId', "$prefix-before")
    Capture-EngineFrame $frameBefore 'before'

    $step = 'affirmative-inquiry-path'
    $affirmativeOpen = Open-HarnessInquiry 'affirmative'
    Capture-EngineFrame $frameOpen 'open'
    $affirmativeToken = [string]$affirmativeOpen.state.context.inquiry.token
    $stale = Invoke-AgentCli 'respondInquiry' @('-InquiryToken', 'stale-token', '-InquiryChoice', 'affirmative', '-CommandId', "$prefix-stale-before") 30
    if ($stale.status -ne 'rejected' -or -not [bool]$stale.state.context.inquiryOpen) { throw 'Stale Inquiry token did not safely preserve the active Native prompt.' }
    $blockedMove = Invoke-AgentCli 'pursue' @('-PartyId', 'not-a-live-party', '-CommandId', "$prefix-map-action-blocked") 30
    if ($blockedMove.status -ne 'rejected' -or $blockedMove.error -notmatch 'Inquiry is open') { throw 'Campaign map movement did not reject while a modal Inquiry is active.' }
    $affirmative = Invoke-AgentCli 'respondInquiry' @('-InquiryToken', $affirmativeToken, '-InquiryChoice', 'affirmative', '-CommandId', "$prefix-answer-affirmative") 30
    if ($affirmative.status -ne 'completed') { throw "Native affirmative VM handler did not complete: $($affirmative.error)" }
    $afterAffirmative = Invoke-AgentCli 'state' @('-CommandId', "$prefix-after-affirmative")
    if ([bool]$afterAffirmative.state.context.inquiryOpen -or [bool]$afterAffirmative.state.context.escapeMenuOpen -or $afterAffirmative.state.context.gameState -ne 'MapState')
        { throw "Affirmative Native handler failed to close its prompt cleanly: $($afterAffirmative.state.context | ConvertTo-Json -Compress)" }
    $affirmativeDiagnostics = Invoke-AgentCli 'harnessNativeInquiryDiagnostics' @('-CommandId', "$prefix-diagnostics-affirmative") 30
    if ($affirmativeDiagnostics.data.lastChoice -ne 'affirmative') { throw 'Native Inquiry affirmative callback did not run exactly as selected.' }
    Capture-EngineFrame $frameAccepted 'accepted'
    $reusedTokenRejected = Invoke-AgentCli 'respondInquiry' @('-InquiryToken', $affirmativeToken, '-InquiryChoice', 'affirmative', '-CommandId', "$prefix-stale-after") 30
    if ($reusedTokenRejected.status -ne 'rejected') { throw 'Closed Inquiry token remained usable after its callback completed.' }

    $step = 'negative-inquiry-path'
    $negativeOpen = Open-HarnessInquiry 'negative'
    if ($negativeOpen.state.context.inquiry.token -eq $affirmativeToken) { throw 'New Native Inquiry reused an old one-time token.' }
    Capture-EngineFrame $frameOpenNegative 'negative-open'
    $negative = Invoke-AgentCli 'respondInquiry' @('-InquiryToken', [string]$negativeOpen.state.context.inquiry.token, '-InquiryChoice', 'negative', '-CommandId', "$prefix-answer-negative") 30
    if ($negative.status -ne 'completed') { throw "Native negative VM handler did not complete: $($negative.error)" }
    $afterNegative = Invoke-AgentCli 'state' @('-CommandId', "$prefix-after-negative")
    $negativeDiagnostics = Invoke-AgentCli 'harnessNativeInquiryDiagnostics' @('-CommandId', "$prefix-diagnostics-negative") 30
    if ([bool]$afterNegative.state.context.inquiryOpen -or $negativeDiagnostics.data.lastChoice -ne 'negative') { throw 'Native negative callback or close did not match the selected button.' }
    Capture-EngineFrame $frameDeclined 'declined'

    $step = 'open-native-recruitment-capacity-inquiry'
    $mapAfterSyntheticInquiry = Invoke-AgentCli 'state' @('-CommandId', "$prefix-map-for-recruitment")
    $settlement = @($mapAfterSyntheticInquiry.state.nearbySettlements | Where-Object { -not $_.hostile -and [double]$_.distance -gt 0.5 } | Sort-Object { [double]$_.distance } | Select-Object -First 1)
    if ($settlement.Count -ne 1) { throw 'No safe visible settlement target is available to trigger the Native capacity warning.' }
    $move = Invoke-AgentCli 'move' @('-SettlementId', [string]$settlement[0].id, '-CommandId', "$prefix-move-to-recruitment")
    if ($move.status -ne 'completed') { throw "Native settlement approach was not accepted: $($move.error)" }
    $arrival = Wait-ForAgentSettlementArrival -CliPath $cli -SettlementId ([string]$settlement[0].id) -CommandPrefix "$prefix-recruitment-arrival" -TimeoutSeconds $TimeoutSeconds
    $recruitmentMenu = Invoke-AgentCli 'menu' @('-CommandId', "$prefix-recruitment-menu")
    $nativeRecruitmentEntry = @($recruitmentMenu.state.availableMenuOptions | Where-Object { $_.id -eq 'recruit_volunteers' -and $_.available -and $_.enabled } | Select-Object -First 1)
    if ($recruitmentMenu.state.context.menuId -notin @('town','town_backstreet','village') -or $nativeRecruitmentEntry.Count -ne 1)
        { throw 'Native recruitment capacity example did not arrive at a supported Settlement recruit_volunteers menu.' }
    $capacityFixture = Invoke-AgentCli 'harnessSeedRecruitmentCapacityFixture' @('-CommandId', "$prefix-recruitment-capacity-fixture") 30
    $nativeOffers = Invoke-AgentCli 'recruitOptions' @('-CommandId', "$prefix-recruitment-offers") 30
    $offer = @($nativeOffers.data.offers | Where-Object { $_.available -and [int]$_.cost -le [int]$nativeOffers.state.economy.gold } | Sort-Object cost | Select-Object -First 1)
    if ($nativeOffers.status -ne 'completed' -or $offer.Count -ne 1) { throw 'Native RecruitmentVM did not expose an affordable current volunteer offer.' }

    $nativeInquiryFixture = Invoke-AgentCli 'harnessOpenRecruitmentInquiry' @('-OwnerId', [string]$offer[0].ownerId, '-TroopId', [string]$offer[0].troopId, '-VolunteerSlot', [string]$offer[0].slot, '-CommandId', "$prefix-native-capacity-inquiry") 30
    if ($nativeInquiryFixture.status -ne 'completed') { throw "Native RecruitmentVM did not open its own capacity Inquiry: $($nativeInquiryFixture.error)" }
    $nativeInquiryOpen = Invoke-AgentCli 'state' @('-CommandId', "$prefix-native-capacity-inquiry-observed")
    if (-not [bool]$nativeInquiryOpen.state.context.inquiryOpen -or -not [bool]$nativeInquiryOpen.state.context.inquiry.supported -or $nativeInquiryOpen.state.context.inquiry.title -ne $nativeInquiryFixture.data.warningTitle)
        { throw "Native RecruitmentVM's own Over Limit Inquiry was not exposed as the active Native popup: $($nativeInquiryOpen.state.context.inquiry | ConvertTo-Json -Compress)" }
    $nativeInquiryToken = [string]$nativeInquiryOpen.state.context.inquiry.token
    $nativeMembersBeforeAnswer = [int]$nativeInquiryOpen.state.party.members
    $nativeGoldBeforeAnswer = [int]$nativeInquiryOpen.state.economy.gold
    $nativeRawModeBefore = [string]$nativeInquiryOpen.state.context.timeControlMode
    $nativeWaitingBefore = [bool]$nativeInquiryOpen.state.context.isWaiting
    $nativeDayBeforeAnswer = [double]$nativeInquiryOpen.campaignDay
    Capture-EngineFrame $frameRecruitmentOpen 'recruitment-open'

    $declinedCapacity = Invoke-AgentCli 'respondInquiry' @('-InquiryToken', $nativeInquiryToken, '-InquiryChoice', 'negative', '-CommandId', "$prefix-recruitment-decline") 30
    if ($declinedCapacity.status -ne 'completed') { throw "Native RecruitmentVM negative choice failed: $($declinedCapacity.error)" }
    $afterCapacityDecline = Invoke-AgentCli 'state' @('-CommandId', "$prefix-after-recruitment-decline")
    $declineNoMutation = (-not [bool]$afterCapacityDecline.state.context.inquiryOpen -and [int]$afterCapacityDecline.state.party.members -eq $nativeMembersBeforeAnswer -and [int]$afterCapacityDecline.state.economy.gold -eq $nativeGoldBeforeAnswer)
    if (-not $declineNoMutation) { throw 'Native recruitment Inquiry negative choice changed Roster/Gold or left a stale modal open.' }

    $secondOffers = Invoke-AgentCli 'recruitOptions' @('-CommandId', "$prefix-recruitment-offers-second") 30
    $secondOffer = @($secondOffers.data.offers | Where-Object { $_.available -and [int]$_.cost -le [int]$secondOffers.state.economy.gold } | Sort-Object cost | Select-Object -First 1)
    if ($secondOffers.status -ne 'completed' -or $secondOffer.Count -ne 1) { throw 'Native RecruitmentVM did not remain recoverable after the Inquiry was declined.' }
    $secondInquiryFixture = Invoke-AgentCli 'harnessOpenRecruitmentInquiry' @('-OwnerId', [string]$secondOffer[0].ownerId, '-TroopId', [string]$secondOffer[0].troopId, '-VolunteerSlot', [string]$secondOffer[0].slot, '-CommandId', "$prefix-native-capacity-inquiry-second") 30
    if ($secondInquiryFixture.status -ne 'completed') { throw "Native RecruitmentVM could not repeat its Inquiry after a negative choice: $($secondInquiryFixture.error)" }
    $secondInquiryOpen = Invoke-AgentCli 'state' @('-CommandId', "$prefix-native-capacity-inquiry-second-observed")
    if (-not [bool]$secondInquiryOpen.state.context.inquiryOpen -or -not [bool]$secondInquiryOpen.state.context.inquiry.supported) { throw 'Repeated Native Inquiry was not visible.' }
    $acceptedCapacity = Invoke-AgentCli 'respondInquiry' @('-InquiryToken', [string]$secondInquiryOpen.state.context.inquiry.token, '-InquiryChoice', 'affirmative', '-CommandId', "$prefix-recruitment-affirmative") 30
    if ($acceptedCapacity.status -ne 'completed') { throw "Native RecruitmentVM affirmative choice failed: $($acceptedCapacity.error)" }
    $afterCapacityAccept = Invoke-AgentCli 'state' @('-CommandId', "$prefix-after-recruitment-accept")
    $nativeCapacityCommit = (-not [bool]$afterCapacityAccept.state.context.inquiryOpen -and [int]$afterCapacityAccept.state.party.members -eq ($nativeMembersBeforeAnswer + 1) -and [int]$afterCapacityAccept.state.economy.gold -eq ($nativeGoldBeforeAnswer - [int]$secondOffer[0].cost))
    if (-not $nativeCapacityCommit) { throw 'Native affirmative choice did not commit the over-capacity RecruitmentVM transaction.' }
    $nativeInquiryTimeStable = ([math]::Abs($nativeDayBeforeAnswer - [double]$afterCapacityAccept.campaignDay) -le 0.000001 -and
        $nativeRawModeBefore -eq [string]$afterCapacityAccept.state.context.timeControlMode -and
        $nativeWaitingBefore -eq [bool]$afterCapacityAccept.state.context.isWaiting)
    if (-not $nativeInquiryTimeStable) { throw 'Native Inquiry response unexpectedly changed Campaign day, raw time mode, or waiting state.' }
    Capture-EngineFrame $frameRecruitmentAccepted 'recruitment-accepted'

    $unchanged = [ordered]@{
        gameState = ($before.state.context.gameState -eq $afterNegative.state.context.gameState)
        campaignDay = ([math]::Abs([double]$before.campaignDay - [double]$afterNegative.campaignDay) -le 0.000001)
        rawTimeMode = ($before.timeControlMode -eq $afterNegative.timeControlMode)
        waiting = ($before.state.context.isWaiting -eq $afterNegative.state.context.isWaiting)
        gold = ($before.state.economy.gold -eq $afterNegative.state.economy.gold)
        influence = ($before.state.economy.influence -eq $afterNegative.state.economy.influence)
        partyTarget = ($before.state.location.targetPartyId -eq $afterNegative.state.location.targetPartyId)
        questCount = (@($before.state.quests).Count -eq @($afterNegative.state.quests).Count)
    }
    $stateUnchanged = @($unchanged.Values | Where-Object { -not $_ }).Count -eq 0
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-stop") 30
    $allProcessesStopped = -not [bool](Get-Process -Name Bannerlord -ErrorAction SilentlyContinue)
    $result = [ordered]@{
        ProviderKind = 'Native GauntletQueryManager current Inquiry -> structured observation/token -> SingleQueryPopUpVM response handler'
        ProcessId = $start.session.processId
        Initial = [ordered]@{ campaignDay = $before.campaignDay; timeControlMode = $before.timeControlMode; isWaiting = $before.state.context.isWaiting }
        Affirmative = [ordered]@{ inquiry = $affirmativeOpen.state.context.inquiry; receipt = $affirmative; callback = $affirmativeDiagnostics.data.lastChoice }
        Negative = [ordered]@{ inquiry = $negativeOpen.state.context.inquiry; receipt = $negative; callback = $negativeDiagnostics.data.lastChoice }
        NativeRecruitmentInquiry = [ordered]@{ trigger = $nativeInquiryFixture.data; settlement = $settlement[0]; entry = $nativeRecruitmentEntry[0]; capacityFixture = $capacityFixture.data; offer = $offer[0]; prompt = $nativeInquiryOpen.state.context.inquiry; declineNoMutation = $declineNoMutation; affirmativeCommitted = $nativeCapacityCommit; pauseGameActiveState = [bool]$nativeInquiryOpen.state.context.inquiry.pauseGameActiveState; campaignDayAtPrompt = $nativeDayBeforeAnswer; campaignDayAfterAnswer = $afterCapacityAccept.campaignDay; rawTimeModeAtPrompt = $nativeRawModeBefore; rawTimeModeAfterAnswer = $afterCapacityAccept.state.context.timeControlMode; nativeInquiryTimeStable = $nativeInquiryTimeStable }
        StaleTokenRejectedBeforeAndAfter = ($stale.status -eq 'rejected' -and $reusedTokenRejected.status -eq 'rejected')
        MapActionRejectedWithoutClosingInquiry = ($blockedMove.status -eq 'rejected' -and [bool]$stale.state.context.inquiryOpen)
        InquiryResponsesDidNotChangeUnrelatedState = $unchanged
        SourceFixtureHashBefore = $fixtureHashBefore
        SourceFixtureHashAfter = $fixtureHashAfter
        SourceFixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        EngineFrames = @($frameBefore, $frameOpen, $frameAccepted, $frameOpenNegative, $frameDeclined, $frameRecruitmentOpen, $frameRecruitmentAccepted)
        ProcessStopped = [bool]$stop.processStopped
        AllGameProcessesStopped = $allProcessesStopped
        Passed = ($affirmative.status -eq 'completed' -and $negative.status -eq 'completed' -and $affirmativeDiagnostics.data.lastChoice -eq 'affirmative' -and $negativeDiagnostics.data.lastChoice -eq 'negative' -and $stale.status -eq 'rejected' -and $reusedTokenRejected.status -eq 'rejected' -and $blockedMove.status -eq 'rejected' -and $stateUnchanged -and $declineNoMutation -and $nativeCapacityCommit -and $nativeInquiryTimeStable -and $fixtureHashBefore -eq $fixtureHashAfter -and [bool]$stop.processStopped -and $allProcessesStopped)
    }
    $json = $result | ConvertTo-Json -Depth 12
    if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) { Set-Content -LiteralPath $resultPath -Value $json -Encoding UTF8 }
    $json
    if (-not $result.Passed) { exit 1 }
}
catch {
    $failureFrame = Capture-HarnessFailureFrame -CliPath $cli -CommandPrefix $prefix -FailedStep $step -FailureReason $_.Exception.ToString()
    if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) {
        [ordered]@{ FailedStep = $step; Exception = $_.Exception.ToString(); FailureFrame = $failureFrame; LastContext = if ($state) { $state.state.context } else { $null }; TimestampUtc = [DateTime]::UtcNow.ToString('O') } |
            ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $tempPath 'MapInquiryFailure.json') -Encoding UTF8
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
