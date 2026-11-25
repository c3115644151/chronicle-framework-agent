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
$frameRoot = if ($tempPath) { $tempPath } else { Join-Path $PSScriptRoot 'TestResults\ManualAlleyLeaderInquiry' }
$resultPath = if ($tempPath) { Join-Path $tempPath 'AlleyLeaderInquiryResult.json' } else { Join-Path $frameRoot 'AlleyLeaderInquiryResult.json' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$prefix = 'alley-leader-inquiry-' + (Get-Date -Format 'yyyyMMddHHmmssfff')
$step = 'preflight'
$frameTown = Join-Path $frameRoot 'alley-leader-town-menu.bmp'
$framePrompt = Join-Path $frameRoot 'alley-leader-multiselection.bmp'
$frameCancel = Join-Path $frameRoot 'alley-leader-after-cancel.bmp'
$frameAccepted = Join-Path $frameRoot 'alley-leader-after-accept.bmp'

if (-not (Test-Path -LiteralPath $savePath)) { throw "Disposable Campaign fixture not found: $LoadSaveName" }
if (Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
. (Join-Path $PSScriptRoot 'Test-AgentSupport.ps1')

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $output = & $HarnessPowerShell -NoProfile -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

function Capture-EngineFrame([string]$Path, [string]$Suffix) {
    $receipt = Invoke-AgentCli 'captureFrame' @('-OutputPath', $Path, '-CommandId', "$prefix-frame-$Suffix") 30
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path -LiteralPath $Path) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
    if ($receipt.status -ne 'completed' -or -not (Test-Path -LiteralPath $Path) -or (Get-Item -LiteralPath $Path).Length -lt 4096)
        { throw "Native Alley frame was not captured: $Path; receipt=$($receipt | ConvertTo-Json -Depth 4 -Compress)" }
}

function Get-EnabledLeaderOption($Snapshot) {
    return @($Snapshot.state.availableMenuOptions | Where-Object { $_.id -eq 'change_leader_of_alley' -and $_.available -and $_.enabled } | Select-Object -First 1)
}

function Open-NativeLeaderInquiry([string]$Suffix) {
    $menu = Invoke-AgentCli 'menu' @('-CommandId', "$prefix-menu-$Suffix")
    if ($menu.state.context.menuId -ne 'manage_alley') { throw "Expected the Native manage_alley menu but found '$($menu.state.context.menuId)'" }
    $option = @(Get-EnabledLeaderOption $menu)
    if ($option.Count -ne 1) { throw 'Native manage_alley did not expose an enabled change_leader_of_alley option.' }
    $receipt = Invoke-AgentCli 'menuSelect' @('-MenuId', 'manage_alley', '-OptionId', 'change_leader_of_alley', '-CommandId', "$prefix-menu-select-$Suffix") 30
    if ($receipt.status -ne 'completed' -or -not [bool]$receipt.state.context.inquiryOpen -or -not [bool]$receipt.state.context.inquiry.supported -or $receipt.state.context.inquiry.kind -ne 'AlleyLeaderSelection')
        { throw "Native change_leader_of_alley did not present a supported active MultiSelection: $($receipt.state.context | ConvertTo-Json -Depth 6 -Compress)" }
    $repeat = Invoke-AgentCli 'state' @('-CommandId', "$prefix-repeat-$Suffix")
    if ($repeat.state.context.inquiry.token -ne $receipt.state.context.inquiry.token) { throw 'Repeated observation changed the current Alley inquiry token.' }
    return [pscustomobject]@{ Receipt = $receipt; Menu = $menu; Option = $option[0] }
}

function Respond-AlleyInquiry([string]$Token, [string]$Choice, [string[]]$Ids, [string]$Suffix) {
    $arguments = @('-InquiryToken', $Token, '-InquiryChoice', $Choice, '-CommandId', "$prefix-respond-$Suffix")
    if ($Ids.Count -gt 0) { $arguments += @('-SelectedIds', $Ids) }
    return Invoke-AgentCli 'respondMultiSelectionInquiry' $arguments 30
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

    $step = 'arrive-at-the-Town-native-menu'
    $move = Invoke-AgentCli 'move' @('-SettlementId', $TargetSettlementId, '-CommandId', "$prefix-move")
    if ($move.status -ne 'completed') { throw "Native map movement to the target Town failed: $($move.error)" }
    $arrival = Wait-ForAgentSettlementArrival -CliPath $cli -SettlementId $TargetSettlementId -CommandPrefix "$prefix-arrival" -TimeoutSeconds $TimeoutSeconds
    if ($arrival.state.context.gameState -ne 'MapState' -or $arrival.state.location.currentSettlementId -ne $TargetSettlementId)
        { throw 'The Campaign Map Party did not reach the Town GameMenu.' }
    $town = Invoke-AgentCli 'menu' @('-CommandId', "$prefix-town-menu")
    Capture-EngineFrame $frameTown 'town-menu'

    $step = 'prepare-disposable-native-PlayerAlleyData'
    $fixture = Invoke-AgentCli 'harnessPrepareAlleyLeaderFixture' @('-SettlementId', $TargetSettlementId, '-CommandId', "$prefix-alley-fixture") 60
    if ($fixture.status -ne 'completed' -or $fixture.data.nativeAvailability -notin @('Available','AvailableWithDelay'))
        { throw "Harness could not prepare an Alley candidate accepted by the Native model: status=$($fixture.status); error=$($fixture.error); data=$($fixture.data | ConvertTo-Json -Compress)" }
    $manageAlley = Invoke-AgentCli 'menu' @('-CommandId', "$prefix-manage-alley")
    if ($manageAlley.state.context.menuId -ne 'manage_alley') { throw "Harness did not reach manage_alley: $($manageAlley.state.context | ConvertTo-Json -Compress)" }

    $step = 'Native-MultiSelection-cancel-and-reopen'
    $cancelInquiry = Open-NativeLeaderInquiry 'cancel'
    $cancelData = $cancelInquiry.Receipt.state.context.inquiry
    if ([int]$cancelData.minimum -ne 1 -or [int]$cancelData.maximum -ne 1 -or -not [bool]$cancelData.pauseGameActiveState)
        { throw "Native Alley MultiSelection contract differs from 1-of-1/GameState-pause: $($cancelData | ConvertTo-Json -Compress)" }
    $enabledCandidates = @($cancelData.options | Where-Object { $_.enabled -and -not $_.filteredOut })
    if ($enabledCandidates.Count -lt 1 -or -not (@($enabledCandidates.heroId) -contains [string]$fixture.data.candidateHeroId))
        { throw "Observer did not return the candidate set from the Native VM: $($cancelData.options | ConvertTo-Json -Compress)" }
    Capture-EngineFrame $framePrompt 'multi-selection'
    $beforeCancel = Invoke-AgentCli 'harnessAlleyLeaderDiagnostics' @('-SettlementId', $TargetSettlementId, '-CommandId', "$prefix-alley-before-cancel") 30
    $invalid = Respond-AlleyInquiry ([string]$cancelData.token) 'affirmative' @('not-a-current-hero') 'invalid-hidden-candidate'
    if ($invalid.status -ne 'rejected' -or -not [bool]$invalid.state.context.inquiryOpen)
        { throw 'Hidden/out-of-list Hero ID was not rejected while keeping the current Native multi-select open.' }
    $cancel = Respond-AlleyInquiry ([string]$cancelData.token) 'negative' @() 'negative'
    if ($cancel.status -ne 'completed' -or [bool]$cancel.state.context.inquiryOpen) { throw 'Native MultiSelection negative/cancel handler did not close the current prompt.' }
    $afterCancel = Invoke-AgentCli 'harnessAlleyLeaderDiagnostics' @('-SettlementId', $TargetSettlementId, '-CommandId', "$prefix-alley-after-cancel") 30
    $cancelNoMutation = ($beforeCancel.data.assignedHeroId -eq $afterCancel.data.assignedHeroId -and
        ($beforeCancel.data.roster | ConvertTo-Json -Compress) -eq ($afterCancel.data.roster | ConvertTo-Json -Compress) -and
        $beforeCancel.data.alleyOwnerId -eq $afterCancel.data.alleyOwnerId -and
        [int]$cancel.state.economy.gold -eq [int]$cancelInquiry.Receipt.state.economy.gold -and
        [double]$cancel.state.influence -eq [double]$cancelInquiry.Receipt.state.influence)
    if (-not $cancelNoMutation) { throw 'Native Alley cancel changed the Assigned Hero, TroopRoster, Alley owner, Gold, or Influence.' }
    Capture-EngineFrame $frameCancel 'cancel'

    $step = 'Native-MultiSelection-confirm'
    $confirmInquiry = Open-NativeLeaderInquiry 'confirm'
    $confirmData = $confirmInquiry.Receipt.state.context.inquiry
    $candidate = @($confirmData.options | Where-Object { $_.heroId -eq $fixture.data.candidateHeroId -and $_.enabled -and -not $_.filteredOut } | Select-Object -First 1)
    if ($candidate.Count -ne 1) { throw 'The Native candidate was no longer available for the second prompt.' }
    $confirm = Respond-AlleyInquiry ([string]$confirmData.token) 'affirmative' @([string]$candidate[0].heroId) 'positive'
    if ($confirm.status -ne 'completed') { throw "Native MultiSelection affirmative handler failed: $($confirm.error)" }
    $afterConfirm = Invoke-AgentCli 'harnessAlleyLeaderDiagnostics' @('-SettlementId', $TargetSettlementId, '-CommandId', "$prefix-alley-after-confirm") 30
    $leaderAndRosterChanged = ($afterConfirm.data.assignedHeroId -eq $candidate[0].heroId -and
        @($afterConfirm.data.roster | Where-Object { $_.heroId -eq $candidate[0].heroId -and [int]$_.count -eq 1 }).Count -eq 1 -and
        @($afterConfirm.data.roster | Where-Object { $_.heroId -eq $fixture.data.initialAssignedHeroId }).Count -eq 0)
    $nativeWorldStable = ($afterConfirm.data.alleyOwnerId -eq $beforeCancel.data.alleyOwnerId -and
        [int]$confirm.state.economy.gold -eq [int]$confirmInquiry.Receipt.state.economy.gold -and
        [double]$confirm.state.influence -eq [double]$confirmInquiry.Receipt.state.influence -and
        [double]$confirm.state.campaignDay -eq [double]$confirmInquiry.Receipt.state.campaignDay -and
        [string]$confirm.state.timeControlMode -eq [string]$confirmInquiry.Receipt.state.timeControlMode)
    $positiveCommitted = ($leaderAndRosterChanged -and $nativeWorldStable)
    if (-not $positiveCommitted) { throw "Native Alley leader callback did not update assigned Hero and roster: $($afterConfirm.data | ConvertTo-Json -Compress)" }
    Capture-EngineFrame $frameAccepted 'accepted'
    $stale = Respond-AlleyInquiry ([string]$confirmData.token) 'affirmative' @([string]$candidate[0].heroId) 'stale-after-confirm'
    if ($stale.status -ne 'rejected') { throw 'The completed MultiSelection token remained usable.' }

    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-stop") 30
    $allProcessesStopped = -not [bool](Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue)
    $result = [ordered]@{
        ProviderKind = 'Native Town change_leader_of_alley -> current MultiSelectionInquiryData -> MultiSelectionQueryPopUpVM callbacks'
        ProcessId = $start.session.processId
        TownMenu = [ordered]@{ settlementId = $TargetSettlementId; beforeFixtureMenuId = $town.state.context.menuId; NativeOption = $cancelInquiry.Option }
        Fixture = $fixture.data
        Inquiry = $cancelData
        InvalidCandidateRejected = ($invalid.status -eq 'rejected')
        CancelNoMutation = $cancelNoMutation
        NativeWorldStableAcrossConfirmation = $nativeWorldStable
        NativeLeaderAndRosterChanged = $leaderAndRosterChanged
        NegativeReceipt = $cancel
        SelectedHeroId = [string]$candidate[0].heroId
        PositiveCommitted = $positiveCommitted
        PositiveReceipt = $confirm
        NativeGameStatePause = [bool]$confirmData.pauseGameActiveState
        StaleTokenRejected = ($stale.status -eq 'rejected')
        EngineFrames = @($frameTown, $framePrompt, $frameCancel, $frameAccepted)
        SourceFixtureHashBefore = $fixtureHashBefore
        SourceFixtureHashAfter = $fixtureHashAfter
        SourceFixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = [bool]$stop.processStopped
        AllGameProcessesStopped = $allProcessesStopped
        Passed = ($cancelNoMutation -and $positiveCommitted -and $invalid.status -eq 'rejected' -and $stale.status -eq 'rejected' -and $fixtureHashBefore -eq $fixtureHashAfter -and [bool]$stop.processStopped -and $allProcessesStopped)
    }
    $json = $result | ConvertTo-Json -Depth 14
    if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) { Set-Content -LiteralPath $resultPath -Value $json -Encoding UTF8 }
    $json
    if (-not $result.Passed) { exit 1 }
}
catch {
    $failureFrame = Capture-HarnessFailureFrame -CliPath $cli -CommandPrefix $prefix -FailedStep $step -FailureReason $_.Exception.ToString()
    if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) {
        [ordered]@{ FailedStep = $step; Exception = $_.Exception.ToString(); FailureFrame = $failureFrame; LastContext = $state.state.context; TimestampUtc = [DateTime]::UtcNow.ToString('O') } |
            ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $tempPath 'AlleyLeaderInquiryFailure.json') -Encoding UTF8
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
