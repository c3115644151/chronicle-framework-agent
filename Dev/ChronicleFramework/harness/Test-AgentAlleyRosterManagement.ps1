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
$frameRoot = if ($tempPath) { $tempPath } else { Join-Path (Split-Path -Parent $PSScriptRoot) 'TestResults\ManualAlleyRosterManagement' }
$resultPath = if ($tempPath) { Join-Path $tempPath 'AlleyRosterManagementResult.json' } else { Join-Path $frameRoot 'AlleyRosterManagementResult.json' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$prefix = 'alley-roster-' + (Get-Date -Format 'yyyyMMddHHmmssfff')
$step = 'preflight'
$frameTown = Join-Path $frameRoot 'alley-roster-town-menu.bmp'
$frameScreen = Join-Path $frameRoot 'alley-roster-party-screen.bmp'
$frameCancel = Join-Path $frameRoot 'alley-roster-after-cancel.bmp'
$frameDone = Join-Path $frameRoot 'alley-roster-after-done.bmp'

if (-not (Test-Path -LiteralPath $savePath)) { throw "Disposable Campaign fixture not found: $LoadSaveName" }
if (Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
. (Join-Path $PSScriptRoot 'Test-AgentSupport.ps1')

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & $HarnessPowerShell -NoProfile -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorActionPreference
    if ($exitCode -ne 0) {
        if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) {
            Set-Content -LiteralPath (Join-Path $tempPath "AlleyRosterManagementCliFailure-$Action.txt") -Value $output -Encoding UTF8
        }
        throw "Agent CLI '$Action' failed: $output"
    }
    try { return $output | ConvertFrom-Json }
    catch {
        if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) {
            Set-Content -LiteralPath (Join-Path $tempPath "AlleyRosterManagementCliFailure-$Action.txt") -Value $output -Encoding UTF8
        }
        throw "Agent CLI '$Action' returned invalid JSON: $output"
    }
}

function Capture-EngineFrame([string]$Path, [string]$Suffix) {
    $receipt = Invoke-AgentCli 'captureFrame' @('-OutputPath', $Path, '-CommandId', "$prefix-frame-$Suffix") 30
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path -LiteralPath $Path) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
    if ($receipt.status -ne 'completed' -or -not (Test-Path -LiteralPath $Path) -or (Get-Item -LiteralPath $Path).Length -lt 4096)
        { throw "Native Alley roster frame was not captured: $Path; receipt=$($receipt | ConvertTo-Json -Depth 4 -Compress)" }
}

function Open-NativeAlleyRosterScreen([string]$Suffix) {
    $menu = Invoke-AgentCli 'menu' @('-CommandId', "$prefix-menu-$Suffix")
    if ($menu.state.context.menuId -ne 'manage_alley') { throw "Expected Native manage_alley but found '$($menu.state.context.menuId)'" }
    $option = @($menu.state.availableMenuOptions | Where-Object { $_.id -eq 'manage_alley_troops' -and $_.available -and $_.enabled } | Select-Object -First 1)
    if ($option.Count -ne 1) { throw 'Native manage_alley_troops was not currently enabled.' }
    $receipt = Invoke-AgentCli 'menuSelect' @('-MenuId', 'manage_alley', '-OptionId', 'manage_alley_troops', '-CommandId', "$prefix-open-$Suffix") 30
    if ($receipt.status -ne 'completed' -or $receipt.state.context.gameState -ne 'PartyState' -or $receipt.state.partyScreen.mode -ne 'TroopsManage')
        { throw "Native menu option did not open the expected PartyState/TroopsManage screen: $($receipt.state | ConvertTo-Json -Depth 5 -Compress)" }
    if (-not $receipt.state.partyScreen.alleyRoster) { throw 'Observer did not identify the current screen as Alley roster management.' }
    return [pscustomobject]@{ Receipt = $receipt; Option = $option[0] }
}

function Invoke-AlleyRosterTransfer([string]$TroopId, [string]$RosterSide, [string]$Suffix) {
    return Invoke-AgentCli 'alleyRosterTransfer' @('-TroopId', $TroopId, '-RosterSide', $RosterSide, '-CommandId', "$prefix-transfer-$Suffix") 30
}

try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $step = 'load-disposable-campaign'
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $initial = Invoke-AgentCli 'state' @('-CommandId', "$prefix-initial")
    if ($initial.state.context.gameState -ne 'MapState' -or [bool]$initial.state.context.inquiryOpen -or [bool]$initial.state.context.escapeMenuOpen)
        { throw 'Fixture must start on a clear Campaign Map.' }
    $visibleSettlements = Invoke-AgentCli 'mapSettlementTargets' @('-CommandId', "$prefix-visible-settlements")
    $target = @($visibleSettlements.data.mapSettlementTargets | Where-Object { $_.id -eq $TargetSettlementId -and -not $_.hostile } | Select-Object -First 1)
    if ($target.Count -ne 1) { throw "Town '$TargetSettlementId' is not a currently visible nonhostile Settlement target." }

    $step = 'arrive-at-Town-native-menu'
    $move = Invoke-AgentCli 'move' @('-SettlementId', $TargetSettlementId, '-CommandId', "$prefix-move")
    if ($move.status -ne 'completed') { throw "Native map movement failed: $($move.error)" }
    $arrival = Wait-ForAgentSettlementArrival -CliPath $cli -SettlementId $TargetSettlementId -CommandPrefix "$prefix-arrival" -TimeoutSeconds $TimeoutSeconds
    if ($arrival.state.context.gameState -ne 'MapState' -or $arrival.state.location.currentSettlementId -ne $TargetSettlementId)
        { throw 'Campaign Map Party did not reach the Town GameMenu.' }

    $step = 'prepare-disposable-native-Alley-roster'
    $fixture = Invoke-AgentCli 'harnessPrepareAlleyRosterFixture' @('-SettlementId', $TargetSettlementId, '-CommandId', "$prefix-fixture") 60
    if ($fixture.status -ne 'completed') { throw "Native Alley roster fixture failed: $($fixture.error)" }
    $baseline = Invoke-AgentCli 'harnessAlleyRosterDiagnostics' @('-SettlementId', $TargetSettlementId, '-CommandId', "$prefix-baseline") 30
    $troopId = [string]$fixture.data.troopId
    $minimum = [int]$fixture.data.minimumTroops
    $maximum = [int]$fixture.data.maximumTroops
    $initialAlleyCount = [int]$fixture.data.initialAlleyCount
    $initialMainPartyCount = [int]$fixture.data.initialMainPartyCount
    $baselineAlleyTroop = @($baseline.data.alleyRoster | Where-Object { $_.troopId -eq $troopId } | Select-Object -First 1)
    if ($initialAlleyCount -ne $minimum + 1 -or $maximum -le $minimum -or $baselineAlleyTroop.Count -ne 1 -or [int]$baselineAlleyTroop[0].count -ne $initialAlleyCount)
        { throw "Disposable Native Alley roster does not match configured limits: $($fixture.data | ConvertTo-Json -Compress)" }
    Capture-EngineFrame $frameTown 'town-menu'

    $step = 'open-native-Alley-PartyScreen-and-cancel'
    $openedForCancel = Open-NativeAlleyRosterScreen 'cancel'
    $screen = $openedForCancel.Receipt.state.partyScreen
    $alleyRow = @($screen.leftMembers | Where-Object { $_.troopId -eq $troopId -and $_.transferable } | Select-Object -First 1)
    if ($alleyRow.Count -ne 1 -or -not ($screen.leftMembers | Where-Object { $_.troopId -eq $fixture.data.assignedHeroId -and -not $_.transferable }))
        { throw "Native PartyScreen does not show the expected ordinary transfer row and nontransferable assigned Hero: $($screen | ConvertTo-Json -Depth 6 -Compress)" }
    Capture-EngineFrame $frameScreen 'party-screen'
    $stagedCancel = Invoke-AlleyRosterTransfer $troopId 'alley' 'cancel'
    if ($stagedCancel.status -ne 'completed' -or $stagedCancel.data.sourceAfter -ne $initialAlleyCount - 1 -or $stagedCancel.data.targetAfter -ne $initialMainPartyCount + 1)
        { throw "Native PartyCharacterVM transfer did not stage one troop: $($stagedCancel | ConvertTo-Json -Depth 4 -Compress)" }
    $cancel = Invoke-AgentCli 'alleyRosterCancel' @('-CommandId', "$prefix-cancel") 30
    if ($cancel.status -ne 'completed' -or $cancel.state.context.gameState -ne 'MapState') { throw 'Native PartyScreen cancel did not return to the Campaign Map.' }
    $afterCancel = Invoke-AgentCli 'harnessAlleyRosterDiagnostics' @('-SettlementId', $TargetSettlementId, '-CommandId', "$prefix-after-cancel") 30
    $alleyRosterEqual = (($baseline.data.alleyRoster | ConvertTo-Json -Compress) -eq ($afterCancel.data.alleyRoster | ConvertTo-Json -Compress))
    $mainRosterEqual = (($baseline.data.mainPartyRoster | ConvertTo-Json -Compress) -eq ($afterCancel.data.mainPartyRoster | ConvertTo-Json -Compress))
    $cancelNoMutation = ($baseline.data.alleyOwnerId -eq $afterCancel.data.alleyOwnerId -and $baseline.data.assignedHeroId -eq $afterCancel.data.assignedHeroId -and
        $alleyRosterEqual -and $mainRosterEqual -and [int]$baseline.data.gold -eq [int]$afterCancel.data.gold -and
        [double]$baseline.data.influence -eq [double]$afterCancel.data.influence -and [double]$baseline.data.campaignDay -eq [double]$afterCancel.data.campaignDay -and
        [string]$baseline.data.timeControlMode -eq [string]$afterCancel.data.timeControlMode -and [bool]$baseline.data.isWaiting -eq [bool]$afterCancel.data.isWaiting)
    if (-not $cancelNoMutation) { throw "Native Alley PartyScreen cancel committed a draft: before=$($baseline.data | ConvertTo-Json -Depth 5 -Compress); after=$($afterCancel.data | ConvertTo-Json -Depth 5 -Compress)" }
    Capture-EngineFrame $frameCancel 'cancel'

    $step = 'native-transfer-and-Alley-minimum-boundary'
    $openedForDone = Open-NativeAlleyRosterScreen 'done'
    $dayBeforeDone = [double]$openedForDone.Receipt.state.campaignDay
    $timeModeBeforeDone = [string]$openedForDone.Receipt.state.timeControlMode
    $firstTransfer = Invoke-AlleyRosterTransfer $troopId 'alley' 'first'
    $atMinimum = Invoke-AgentCli 'state' @('-CommandId', "$prefix-at-minimum")
    $atMinimumCount = [int]$atMinimum.state.partyScreen.alleyRoster.currentTroops
    $atMinimumDone = [bool]$atMinimum.state.partyScreen.canDone
    $secondTransfer = Invoke-AlleyRosterTransfer $troopId 'alley' 'below-minimum'
    $belowMinimum = Invoke-AgentCli 'state' @('-CommandId', "$prefix-below-minimum")
    $belowMinimumCount = [int]$belowMinimum.state.partyScreen.alleyRoster.currentTroops
    $belowMinimumDone = [bool]$belowMinimum.state.partyScreen.canDone
    if ($firstTransfer.status -ne 'completed' -or $atMinimumCount -ne $minimum -or -not $atMinimumDone -or
        $secondTransfer.status -ne 'completed' -or $belowMinimumCount -ne $minimum - 1 -or $belowMinimumDone)
        { throw "Native Alley minimum troop limit was not represented by the active PartyScreen: min=$minimum at=$atMinimumCount/$atMinimumDone below=$belowMinimumCount/$belowMinimumDone" }
    $blockedDone = Invoke-AgentCli 'partyScreenDone' @('-CommandId', "$prefix-blocked-done") 30
    if ($blockedDone.status -ne 'rejected' -or $blockedDone.state.context.gameState -ne 'PartyState')
        { throw 'Native Done was not rejected while the Alley roster was below its minimum.' }
    $restoreTransfer = Invoke-AlleyRosterTransfer $troopId 'mainParty' 'restore-minimum'
    $restored = Invoke-AgentCli 'state' @('-CommandId', "$prefix-restored-minimum")
    if ($restoreTransfer.status -ne 'completed' -or [int]$restored.state.partyScreen.alleyRoster.currentTroops -ne $minimum -or -not [bool]$restored.state.partyScreen.canDone)
        { throw 'Native PartyScreen could not restore the Alley roster to a Done-valid minimum.' }

    $step = 'native-Alley-maximum-boundary'
    $transfersToAboveMaximum = $maximum - $minimum + 1
    for ($index = 0; $index -lt $transfersToAboveMaximum; $index++) {
        $upperTransfer = Invoke-AlleyRosterTransfer $troopId 'mainParty' "above-maximum-$index"
        if ($upperTransfer.status -ne 'completed') { throw "Native MainParty->Alley transfer failed while probing the upper boundary at step $index." }
    }
    $aboveMaximum = Invoke-AgentCli 'state' @('-CommandId', "$prefix-above-maximum")
    $aboveMaximumCount = [int]$aboveMaximum.state.partyScreen.alleyRoster.currentTroops
    $aboveMaximumDone = [bool]$aboveMaximum.state.partyScreen.canDone
    $blockedUpperDone = Invoke-AgentCli 'partyScreenDone' @('-CommandId', "$prefix-blocked-upper-done") 30
    if ($aboveMaximumCount -ne $maximum + 1 -or $aboveMaximumDone -or $blockedUpperDone.status -ne 'rejected' -or $blockedUpperDone.state.context.gameState -ne 'PartyState')
        { throw "Native Alley maximum troop limit did not disable Done at the upper boundary: maximum=$maximum observed=$aboveMaximumCount/$aboveMaximumDone receipt=$($blockedUpperDone.status)" }
    $restoreUpperBoundary = Invoke-AlleyRosterTransfer $troopId 'alley' 'restore-maximum'
    $atMaximum = Invoke-AgentCli 'state' @('-CommandId', "$prefix-at-maximum")
    $atMaximumCount = [int]$atMaximum.state.partyScreen.alleyRoster.currentTroops
    $atMaximumDone = [bool]$atMaximum.state.partyScreen.canDone
    if ($restoreUpperBoundary.status -ne 'completed' -or $atMaximumCount -ne $maximum -or -not $atMaximumDone)
        { throw "Native Alley PartyScreen did not restore Done availability at its maximum: maximum=$maximum observed=$atMaximumCount/$atMaximumDone" }

    $done = Invoke-AgentCli 'partyScreenDone' @('-CommandId', "$prefix-done") 30
    if ($done.status -ne 'completed' -or $done.state.context.gameState -ne 'MapState') { throw "Native PartyScreen Done did not return to MapState: $($done | ConvertTo-Json -Depth 5 -Compress)" }
    $afterDone = Invoke-AgentCli 'harnessAlleyRosterDiagnostics' @('-SettlementId', $TargetSettlementId, '-CommandId', "$prefix-after-done") 30
    $finalAlleyTroop = @($afterDone.data.alleyRoster | Where-Object { $_.troopId -eq $troopId } | Select-Object -First 1)
    $finalMainPartyTroop = @($afterDone.data.mainPartyRoster | Where-Object { $_.troopId -eq $troopId } | Select-Object -First 1)
    $finalAlleyCount = if ($finalAlleyTroop.Count -eq 1) { [int]$finalAlleyTroop[0].count } else { 0 }
    $finalMainPartyCount = if ($finalMainPartyTroop.Count -eq 1) { [int]$finalMainPartyTroop[0].count } else { 0 }
    $expectedMainPartyCount = $initialMainPartyCount - ($maximum - $initialAlleyCount)
    $nativeCommitCorrect = ([int]$finalAlleyCount -eq $maximum -and [int]$finalMainPartyCount -eq $expectedMainPartyCount -and
        $afterDone.data.alleyOwnerId -eq $baseline.data.alleyOwnerId -and $afterDone.data.assignedHeroId -eq $baseline.data.assignedHeroId -and
        [int]$afterDone.data.gold -eq [int]$baseline.data.gold -and [double]$afterDone.data.influence -eq [double]$baseline.data.influence)
    $nativeClockStable = ([double]$afterDone.data.campaignDay -eq [double]$baseline.data.campaignDay -and
        [string]$afterDone.data.timeControlMode -eq [string]$baseline.data.timeControlMode -and
        [bool]$afterDone.data.isWaiting -eq [bool]$baseline.data.isWaiting -and
        [double]$done.state.campaignDay -eq $dayBeforeDone -and [string]$done.state.timeControlMode -eq $timeModeBeforeDone -and
        [bool]$done.state.context.isWaiting -eq [bool]$openedForDone.Receipt.state.context.isWaiting)
    if (-not $nativeCommitCorrect) { throw "Native PartyScreen Done did not commit the expected single-troop transfer: $($afterDone.data | ConvertTo-Json -Depth 5 -Compress)" }
    if (-not $nativeClockStable) { throw 'Alley PartyState opening, editing, cancel or Done changed Campaign day or raw time mode.' }
    Capture-EngineFrame $frameDone 'done'

    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-stop") 30
    $allProcessesStopped = -not [bool](Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue)
    $frames = @($frameTown, $frameScreen, $frameCancel, $frameDone)
    $result = [ordered]@{
        ProviderKind = 'Native town manage_alley_troops -> PartyScreenHelper/PartyState/TroopsManage -> PartyCharacterVM transfer + PartyVM Done/Cancel'
        ProcessId = $start.session.processId
        TownMenu = [ordered]@{ settlementId = $TargetSettlementId; NativeOption = $openedForDone.Option }
        Fixture = $fixture.data
        NativePartyScreen = $screen
        StagedTransferReceipt = $stagedCancel
        CancelNoMutation = $cancelNoMutation
        MinimumBoundary = [ordered]@{ minimum = $minimum; atMinimumCount = $atMinimumCount; atMinimumDone = $atMinimumDone; belowMinimumCount = $belowMinimumCount; belowMinimumDone = $belowMinimumDone; blockedDoneRejected = ($blockedDone.status -eq 'rejected') }
        MaximumBoundary = [ordered]@{ maximum = $maximum; aboveMaximumCount = $aboveMaximumCount; aboveMaximumDone = $aboveMaximumDone; blockedDoneRejected = ($blockedUpperDone.status -eq 'rejected'); atMaximumCount = $atMaximumCount; atMaximumDone = $atMaximumDone }
        NativeCommitCorrect = $nativeCommitCorrect
        NativeClockStable = $nativeClockStable
        NativeHandlerTransferCount = [int]$firstTransfer.data.transferredCount + [int]$secondTransfer.data.transferredCount + [int]$restoreTransfer.data.transferredCount + $transfersToAboveMaximum + [int]$restoreUpperBoundary.data.transferredCount
        EngineFrames = $frames
        SourceFixtureHashBefore = $fixtureHashBefore
        SourceFixtureHashAfter = $fixtureHashAfter
        SourceFixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = [bool]$stop.processStopped
        AllGameProcessesStopped = $allProcessesStopped
        Passed = ($cancelNoMutation -and $atMinimumDone -and -not $belowMinimumDone -and $blockedDone.status -eq 'rejected' -and
            $aboveMaximumCount -eq $maximum + 1 -and -not $aboveMaximumDone -and $blockedUpperDone.status -eq 'rejected' -and $atMaximumDone -and
            $nativeCommitCorrect -and $nativeClockStable -and $fixtureHashBefore -eq $fixtureHashAfter -and [bool]$stop.processStopped -and $allProcessesStopped)
    }
    $json = $result | ConvertTo-Json -Depth 14
    if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) { Set-Content -LiteralPath $resultPath -Value $json -Encoding UTF8 }
    $json
    if (-not $result.Passed) { exit 1 }
}
catch {
    $failureFrame = Capture-HarnessFailureFrame -CliPath $cli -CommandPrefix $prefix -FailedStep $step -FailureReason $_.Exception.ToString()
    if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) {
        [ordered]@{ FailedStep = $step; Exception = $_.Exception.ToString(); FailureFrame = $failureFrame; TimestampUtc = [DateTime]::UtcNow.ToString('O') } |
            ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $tempPath 'AlleyRosterManagementFailure.json') -Encoding UTF8
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
