[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [string]$TargetSettlementId = 'town_V1',
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$tempPath = $env:CHRONICLE_HARNESS_TEMP
$frameRoot = if ($tempPath) { $tempPath } else { Join-Path $PSScriptRoot 'TestResults\ManualAlleyAbandonment' }
$resultPath = if ($tempPath) { Join-Path $tempPath 'AlleyAbandonmentResult.json' } else { Join-Path $frameRoot 'AlleyAbandonmentResult.json' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$prefix = 'alley-abandon-' + (Get-Date -Format 'yyyyMMddHHmmssfff')
$failedStep = 'preflight'

if (-not (Test-Path -LiteralPath $savePath)) { throw "Disposable Campaign fixture not found: $LoadSaveName" }
if (Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
. (Join-Path $PSScriptRoot 'Test-AgentSupport.ps1')

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
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
        { throw "Native Alley abandonment frame was not captured: $Path; receipt=$($receipt | ConvertTo-Json -Depth 4 -Compress)" }
}

function Invoke-AbandonmentBranch([ValidateSet('cancel','confirm')][string]$Branch) {
    $branchPrefix = "$prefix-$Branch"
    $frames = [System.Collections.Generic.List[string]]::new()
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName) 180
    $initial = Invoke-AgentCli 'state' @('-CommandId', "$branchPrefix-initial")
    if ($initial.state.context.gameState -ne 'MapState' -or [bool]$initial.state.context.inquiryOpen -or [bool]$initial.state.context.escapeMenuOpen)
        { throw "$Branch fixture must start on a clear Campaign Map." }

    $visible = Invoke-AgentCli 'mapSettlementTargets' @('-CommandId', "$branchPrefix-visible-settlements")
    $target = @($visible.data.mapSettlementTargets | Where-Object { $_.id -eq $TargetSettlementId -and -not $_.hostile } | Select-Object -First 1)
    if ($target.Count -ne 1) { throw "Town '$TargetSettlementId' is not currently visible and nonhostile." }
    $move = Invoke-AgentCli 'move' @('-SettlementId', $TargetSettlementId, '-CommandId', "$branchPrefix-move")
    if ($move.status -ne 'completed') { throw "Native move failed: $($move.error)" }
    $arrival = Wait-ForAgentSettlementArrival -CliPath $cli -SettlementId $TargetSettlementId -CommandPrefix "$branchPrefix-arrival" -TimeoutSeconds $TimeoutSeconds
    if ($arrival.state.context.gameState -ne 'MapState' -or $arrival.state.location.currentSettlementId -ne $TargetSettlementId)
        { throw "$Branch fixture did not reach the Town menu." }

    $fixture = Invoke-AgentCli 'harnessPrepareAlleyRosterFixture' @('-SettlementId', $TargetSettlementId, '-CommandId', "$branchPrefix-fixture") 60
    if ($fixture.status -ne 'completed') { throw "Native non-attacked Alley fixture failed: $($fixture.error)" }
    $alleyTag = [string]$fixture.data.alleyTag
    $baseline = Invoke-AgentCli 'harnessAlleyRosterDiagnostics' @('-SettlementId', $TargetSettlementId, '-AlleyTag', $alleyTag, '-CommandId', "$branchPrefix-baseline") 30
    if (-not [bool]$baseline.data.playerAlleyDataPresent -or [bool]$baseline.data.underAttack -or $baseline.data.alleyOwnerId -ne 'main_hero')
        { throw "Abandonment test must start from a player-owned, non-attacked Native Alley: $($baseline.data | ConvertTo-Json -Depth 5 -Compress)" }
    $townFrame = Join-Path $frameRoot "alley-abandon-$Branch-town-menu.bmp"
    Capture-EngineFrame $townFrame "$Branch-town-menu"
    $frames.Add($townFrame)

    $townMenu = Invoke-AgentCli 'menu' @('-CommandId', "$branchPrefix-town-menu")
    $abandonOption = @($townMenu.state.availableMenuOptions | Where-Object { $_.id -eq 'abandon_alley' -and $_.available -and $_.enabled } | Select-Object -First 1)
    if ($abandonOption.Count -ne 1) { throw 'Native abandon_alley was not currently available in manage_alley.' }
    $confirmMenu = Invoke-AgentCli 'menuSelect' @('-MenuId', 'manage_alley', '-OptionId', 'abandon_alley', '-CommandId', "$branchPrefix-open-confirm")
    if ($confirmMenu.status -ne 'completed' -or $confirmMenu.state.context.menuId -ne 'manage_alley_abandon_are_you_sure')
        { throw "Native abandon option did not open its confirmation GameMenu: $($confirmMenu.state.context | ConvertTo-Json -Depth 5 -Compress)" }
    $confirmation = Invoke-AgentCli 'menu' @('-CommandId', "$branchPrefix-confirm-menu")
    $expectedOption = if ($Branch -eq 'cancel') { 'abandon_alley_no' } else { 'abandon_alley_yes' }
    $choiceOption = @($confirmation.state.availableMenuOptions | Where-Object { $_.id -eq $expectedOption -and $_.available -and $_.enabled } | Select-Object -First 1)
    if ($choiceOption.Count -ne 1) { throw "Native confirmation option '$expectedOption' was not available." }
    $confirmFrame = Join-Path $frameRoot "alley-abandon-$Branch-confirmation.bmp"
    Capture-EngineFrame $confirmFrame "$Branch-confirmation"
    $frames.Add($confirmFrame)
    $dayBefore = [double]$confirmation.state.campaignDay
    $timeModeBefore = [string]$confirmation.state.timeControlMode
    $waitingBefore = [bool]$confirmation.state.context.isWaiting

    $result = Invoke-AgentCli 'menuSelect' @('-MenuId', 'manage_alley_abandon_are_you_sure', '-OptionId', $expectedOption, '-CommandId', "$branchPrefix-choice")
    $after = Invoke-AgentCli 'harnessAlleyRosterDiagnostics' @('-SettlementId', $TargetSettlementId, '-AlleyTag', $alleyTag, '-CommandId', "$branchPrefix-after") 30
    $resultFrame = Join-Path $frameRoot "alley-abandon-$Branch-result.bmp"
    Capture-EngineFrame $resultFrame "$Branch-result"
    $frames.Add($resultFrame)

    if ($Branch -eq 'cancel') {
        $expectedRoster = (($baseline.data.alleyRoster | ConvertTo-Json -Compress) -eq ($after.data.alleyRoster | ConvertTo-Json -Compress))
        $expectedMainParty = (($baseline.data.mainPartyRoster | ConvertTo-Json -Compress) -eq ($after.data.mainPartyRoster | ConvertTo-Json -Compress))
        $postcondition = ($result.status -eq 'completed' -and $result.state.context.menuId -eq 'manage_alley' -and
            [bool]$after.data.playerAlleyDataPresent -and $baseline.data.alleyOwnerId -eq $after.data.alleyOwnerId -and
            $baseline.data.assignedHeroId -eq $after.data.assignedHeroId -and $expectedRoster -and $expectedMainParty -and
            [int]$baseline.data.gold -eq [int]$after.data.gold -and [double]$baseline.data.influence -eq [double]$after.data.influence)
    }
    else {
        $expectedTroop = @($baseline.data.alleyRoster | Where-Object { $_.troopId -eq $fixture.data.troopId } | Select-Object -First 1)
        $baselineMainPartyTroop = @($baseline.data.mainPartyRoster | Where-Object { $_.troopId -eq $fixture.data.troopId } | Select-Object -First 1)
        $expectedMainPartyTroop = @($after.data.mainPartyRoster | Where-Object { $_.troopId -eq $fixture.data.troopId } | Select-Object -First 1)
        $expectedReturnedCount = [int]$baselineMainPartyTroop[0].count + [int]$expectedTroop[0].count
        $postcondition = ($result.status -eq 'completed' -and $result.state.context.menuId -eq 'town' -and
            -not [bool]$after.data.playerAlleyDataPresent -and -not [string]$after.data.alleyOwnerId -and
            $expectedMainPartyTroop.Count -eq 1 -and [int]$expectedMainPartyTroop[0].count -eq $expectedReturnedCount -and
            [int]$baseline.data.gold -eq [int]$after.data.gold -and [double]$baseline.data.influence -eq [double]$after.data.influence)
    }
    $clockStable = ([double]$after.data.campaignDay -eq [double]$baseline.data.campaignDay -and
        [string]$after.data.timeControlMode -eq [string]$baseline.data.timeControlMode -and
        [double]$result.state.campaignDay -eq $dayBefore -and [string]$result.state.timeControlMode -eq $timeModeBefore)

    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$branchPrefix-stop") 30
    $processStopped = [bool]$stop.processStopped -and -not [bool](Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue)
    [pscustomobject]@{
        Branch = $Branch
        ProcessId = $start.session.processId
        Fixture = $fixture.data
        NativeConfirmationOptions = $confirmation.state.availableMenuOptions
        Choice = $expectedOption
        ResultMenuId = [string]$result.state.context.menuId
        PostconditionPassed = $postcondition
        ClockStable = $clockStable
        CampaignDayBefore = $dayBefore
        CampaignDayAfter = [double]$after.data.campaignDay
        RawTimeModeBefore = $timeModeBefore
        RawTimeModeAfter = [string]$after.data.timeControlMode
        IsWaitingBefore = $waitingBefore
        IsWaitingAfter = [bool]$after.data.isWaiting
        EngineFrames = @($frames)
        ProcessStopped = $processStopped
        Result = $result
        Before = $baseline.data
        After = $after.data
        Passed = ($postcondition -and $clockStable -and $processStopped)
    }
}

try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $failedStep = 'cancel-disposable-campaign'
    $cancelResult = Invoke-AbandonmentBranch 'cancel'
    if (-not $cancelResult.Passed) { throw "Native Alley abandonment cancel branch failed: $($cancelResult | ConvertTo-Json -Depth 8 -Compress)" }

    $failedStep = 'confirm-independent-disposable-campaign'
    $confirmResult = Invoke-AbandonmentBranch 'confirm'
    if (-not $confirmResult.Passed) { throw "Native Alley abandonment confirm branch failed: $($confirmResult | ConvertTo-Json -Depth 8 -Compress)" }

    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $result = [ordered]@{
        ProviderKind = 'Native Town manage_alley -> abandon_alley -> manage_alley_abandon_are_you_sure -> Native No/Yes menu consequences'
        CancelBranch = $cancelResult
        ConfirmBranch = $confirmResult
        SourceFixtureHashBefore = $fixtureHashBefore
        SourceFixtureHashAfter = $fixtureHashAfter
        SourceFixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        Passed = ($cancelResult.Passed -and $confirmResult.Passed -and $fixtureHashBefore -eq $fixtureHashAfter)
    }
    $json = $result | ConvertTo-Json -Depth 14
    if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) { Set-Content -LiteralPath $resultPath -Value $json -Encoding UTF8 }
    $json
    if (-not $result.Passed) { exit 1 }
}
catch {
    if (Test-Path $sessionPath) {
        try { $session = Get-Content $sessionPath -Raw | ConvertFrom-Json; if ($session.status -ne 'stopped') { $null = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-failure-stop") 30 } }
        catch { }
    }
    $failureFrame = $null
    if (Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue) {
        try { $failureFrame = Capture-HarnessFailureFrame -CliPath $cli -CommandPrefix $prefix -FailedStep $failedStep -FailureReason $_.Exception.ToString() }
        catch { $failureFrame = [ordered]@{ Captured = $false; Error = $_.Exception.Message } }
    }
    if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) {
        [ordered]@{ FailedStep = $failedStep; Exception = $_.Exception.ToString(); FailureFrame = $failureFrame; TimestampUtc = [DateTime]::UtcNow.ToString('O') } |
            ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $tempPath 'AlleyAbandonmentFailure.json') -Encoding UTF8
    }
    throw
}
finally {
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
