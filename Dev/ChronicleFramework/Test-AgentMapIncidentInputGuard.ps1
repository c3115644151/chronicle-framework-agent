#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$LoadSaveName = 'ChronicleEycDev-20261030-gold2017-party20',
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$resultPath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP 'MapIncidentInputGuardResult.json' } else { Join-Path $PSScriptRoot 'TestResults\ManualMapIncident\MapIncidentInputGuardResult.json' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$env:CHRONICLE_HARNESS_MODE = 'visual-capture'
$prefix = 'map-incident-input-guard-' + (Get-Date -Format 'yyyyMMddHHmmssfff')

if ([string]::IsNullOrWhiteSpace($env:CHRONICLE_HARNESS_TEMP)) { throw 'MapIncident input guard needs an isolated Harness evidence directory.' }
if (-not (Test-Path -LiteralPath $savePath)) { throw "MapIncident input guard fixture not found: $LoadSaveName" }
if (Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $output = & $HarnessPowerShell -NoProfile -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

try {
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $before = Invoke-AgentCli 'state' @('-CommandId', "$prefix-state-before")
    if ($before.state.context.gameState -ne 'MapState' -or $before.state.context.menuId -ne 'town') {
        throw "MapIncident input guard fixture must load at the saved Town menu; got $($before.state.context.gameState)/$($before.state.context.menuId)."
    }

    $leave = Invoke-AgentCli 'menuSelect' @('-MenuId', 'town', '-OptionId', 'town_leave', '-CommandId', "$prefix-town-leave")
    $mapBefore = Invoke-AgentCli 'state' @('-CommandId', "$prefix-map-before")
    if ($leave.status -ne 'completed' -or $mapBefore.state.context.gameState -ne 'MapState' -or
        $mapBefore.state.context.menuId -ne $null -or $mapBefore.state.location.currentSettlementId -ne $null) {
        throw 'The MapIncident input guard fixture could not leave the original Town menu and reach a free Campaign Map.'
    }

    $frameBeforePath = Join-Path $env:CHRONICLE_HARNESS_TEMP 'MapIncidentInputGuard-before.bmp'
    if ($mapBefore.state.context.mapIncident.active) {
        $active = $mapBefore
        $fixtureKind = 'native-town-leave-incident'
        $seed = [pscustomobject]@{ status = 'completed'; data = [pscustomobject]@{ testOnly = $false; type = $active.state.context.mapIncident.incidentType; source = 'native-town-leave' } }
    }
    else {
        $seed = Invoke-AgentCli 'harnessSeedMapIncidentFixture' @('-CommandId', "$prefix-seed")
        $active = Invoke-AgentCli 'state' @('-CommandId', "$prefix-active")
        $fixtureKind = 'harness-seeded-native-map-view'
    }
    $frameBefore = Invoke-AgentCli 'captureFrame' @('-OutputPath', $frameBeforePath, '-CommandId', "$prefix-frame-before")
    $activeIncident = $active.state.context.mapIncident
    $visibleModal = $active.state.context.gameState -eq 'MapState' -and
        $active.state.context.menuId -eq $null -and
        $active.state.context.timeControlMode -eq 'Stop' -and
        $active.state.context.timeControlModeLocked -and
        $activeIncident.active -and $activeIncident.options.Count -gt 0 -and $activeIncident.canConfirm -eq $false
    if ($seed.status -ne 'completed' -or -not $visibleModal -or
        -not (Test-Path -LiteralPath $frameBeforePath)) {
        throw 'The original MapState did not expose and visibly render a Native MapIncident with its time lock.'
    }

    $movementCases = @(
        [ordered]@{ name = 'pursue'; arguments = @('-PartyId', 'harness-nonexistent-party') },
        [ordered]@{ name = 'follow'; arguments = @('-PartyId', 'harness-nonexistent-party') },
        [ordered]@{ name = 'hold'; arguments = @() },
        [ordered]@{ name = 'move'; arguments = @('-SettlementId', 'town_ES3') },
        [ordered]@{ name = 'moveToPoint'; arguments = @('-X', '472.46', '-Y', '267.852', '-Surface', 'land') }
    )
    $actionAssertions = [ordered]@{}
    $actionReceipts = @()
    foreach ($testCase in $movementCases) {
        $response = Invoke-AgentCli $testCase.name $testCase.arguments
        $afterAction = Invoke-AgentCli 'state' @('-CommandId', "$prefix-state-$($testCase.name)")
        $reason = [string]$response.error
        $blockedBeforeMutation = $response.status -eq 'rejected' -and
            $reason.IndexOf('Native Map Incident is open', [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
            $afterAction.state.context.mapIncident.active -and
            $afterAction.state.context.timeControlModeLocked -and
            $afterAction.state.context.timeControlMode -eq 'Stop' -and
            $afterAction.state.location.targetPartyId -eq $mapBefore.state.location.targetPartyId -and
            $afterAction.state.location.targetSettlementId -eq $mapBefore.state.location.targetSettlementId -and
            [double]$afterAction.state.campaignDay -eq [double]$mapBefore.state.campaignDay -and
            [int]$afterAction.state.economy.gold -eq [int]$mapBefore.state.economy.gold -and
            [int]$afterAction.state.party.members -eq [int]$mapBefore.state.party.members
        $actionAssertions[$testCase.name] = [bool]$blockedBeforeMutation
        $actionReceipts += [ordered]@{
            action = $testCase.name
            commandId = $response.commandId
            status = $response.status
            error = $response.error
            contextAfter = $afterAction.state.context
            targetAfter = $afterAction.state.location
            campaignDayAfter = $afterAction.state.campaignDay
            goldAfter = $afterAction.state.economy.gold
            partyMembersAfter = $afterAction.state.party.members
            blockedBeforeMutation = [bool]$blockedBeforeMutation
        }
    }

    $frameAfterBlockPath = Join-Path $env:CHRONICLE_HARNESS_TEMP 'MapIncidentInputGuard-blocked.bmp'
    $frameAfterBlock = Invoke-AgentCli 'captureFrame' @('-OutputPath', $frameAfterBlockPath, '-CommandId', "$prefix-frame-blocked")
    $submitOptionIndex = [int]$activeIncident.options[-1].index
    $submit = Invoke-AgentCli 'incidentSelect' @('-OptionIndex', [string]$submitOptionIndex, '-CommandId', "$prefix-submit")
    $afterSubmit = Invoke-AgentCli 'state' @('-CommandId', "$prefix-state-after-submit")
    $frameAfterSubmitPath = Join-Path $env:CHRONICLE_HARNESS_TEMP 'MapIncidentInputGuard-resolved.bmp'
    $frameAfterSubmit = Invoke-AgentCli 'captureFrame' @('-OutputPath', $frameAfterSubmitPath, '-CommandId', "$prefix-frame-resolved")
    $closeReceiptPassed = $submit.status -eq 'completed' -and $submit.data.submitted -and
        -not $submit.data.sameIncidentViewRemains -and
        $submit.data.timeControlModeLockBefore -and -not $submit.data.timeControlModeLockAfter -and
        [double]$submit.data.campaignDayBefore -eq [double]$submit.data.campaignDayAfter -and
        -not $afterSubmit.state.context.mapIncident.active -and
        -not $afterSubmit.state.context.timeControlModeLocked -and
        [double]$afterSubmit.state.campaignDay -eq [double]$mapBefore.state.campaignDay
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-stop") 30
    $assertions = [ordered]@{
        NativeIncidentFixtureDisplayedInMapState = [bool]$visibleModal
        PursueBlockedBeforeNativeMutation = [bool]$actionAssertions['pursue']
        FollowBlockedBeforeNativeMutation = [bool]$actionAssertions['follow']
        HoldBlockedBeforeNativeMutation = [bool]$actionAssertions['hold']
        SettlementMoveBlockedBeforeNativeMutation = [bool]$actionAssertions['move']
        PointMoveBlockedBeforeNativeMutation = [bool]$actionAssertions['moveToPoint']
        OriginalIncidentDoneClosedTheModalAndReleasedClockLock = [bool]$closeReceiptPassed
        CampaignDayUnchangedByIncidentResolution = ([double]$afterSubmit.state.campaignDay -eq [double]$mapBefore.state.campaignDay)
        FixtureHashUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = [bool]$stop.processStopped
        NativeFramesCaptured = ((Test-Path -LiteralPath $frameBeforePath) -and (Test-Path -LiteralPath $frameAfterBlockPath) -and (Test-Path -LiteralPath $frameAfterSubmitPath))
    }
    $failedAssertions = @($assertions.Keys | Where-Object { -not [bool]$assertions[$_] })
    $result = [ordered]@{
        FixtureSave = $LoadSaveName
        FixtureKind = $fixtureKind
        FixtureHashBefore = $fixtureHashBefore
        FixtureHashAfter = $fixtureHashAfter
        Seed = $seed.data
        StateBefore = $before.state
        MapStateBeforeIncident = $mapBefore.state
        ActiveIncidentObservation = $active.state.context.mapIncident
        MovementActionReceipts = $actionReceipts
        ModalClosedReceipt = $submit.data
        StateAfterSubmit = $afterSubmit.state
        FrameBefore = 'MapIncidentInputGuard-before.bmp'
        FrameWhileBlocked = 'MapIncidentInputGuard-blocked.bmp'
        FrameAfterNativeDone = 'MapIncidentInputGuard-resolved.bmp'
        Assertions = $assertions
        FailedAssertions = $failedAssertions
        ProcessStopped = [bool]$stop.processStopped
        Passed = ($failedAssertions.Count -eq 0)
    }
    $result | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    $result | ConvertTo-Json -Depth 14
    if (-not $result.Passed) { throw 'Native MapIncident modal input guard regression failed.' }
}
finally {
    if (Test-Path -LiteralPath $sessionPath) {
        try { Invoke-AgentCli 'stop' @('-CommandId', "$prefix-cleanup") 30 | Out-Null } catch { }
    }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
