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
$frameRoot = if ($tempPath) { $tempPath } else { Join-Path $PSScriptRoot 'TestResults\ManualAlleyEntryMenu' }
$resultPath = if ($tempPath) { Join-Path $tempPath 'AlleyEntryMenuResult.json' } else { Join-Path $frameRoot 'AlleyEntryMenuResult.json' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$prefix = 'alley-entry-' + (Get-Date -Format 'yyyyMMddHHmmssfff')
$failedStep = 'preflight'
$frameTown = Join-Path $frameRoot 'alley-entry-town-menu.bmp'
$frameAlley = Join-Path $frameRoot 'alley-entry-manage-menu.bmp'
$frameReturn = Join-Path $frameRoot 'alley-entry-returned-town.bmp'

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
        { throw "Native Alley entry frame was not captured: $Path; receipt=$($receipt | ConvertTo-Json -Depth 4 -Compress)" }
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

    $failedStep = 'prepare-disposable-player-Alley-at-Native-Town'
    $fixture = Invoke-AgentCli 'harnessPrepareAlleyRosterFixture' @('-SettlementId', $TargetSettlementId, '-MenuId', 'town', '-CommandId', "$prefix-fixture") 60
    if ($fixture.status -ne 'completed' -or $fixture.state.context.menuId -ne 'town' -or $fixture.data.destinationMenuId -ne 'town')
        { throw "Harness did not return to the Native Town menu with its PlayerAlleyData fixture: $($fixture | ConvertTo-Json -Depth 5 -Compress)" }
    $alleyTag = [string]$fixture.data.alleyTag
    $baseline = Invoke-AgentCli 'harnessAlleyRosterDiagnostics' @('-SettlementId', $TargetSettlementId, '-AlleyTag', $alleyTag, '-CommandId', "$prefix-baseline") 30
    if (-not [bool]$baseline.data.playerAlleyDataPresent -or [bool]$baseline.data.underAttack -or $baseline.data.alleyOwnerId -ne 'main_hero')
        { throw 'Entry test requires a player-owned, non-attacked Native Alley.' }
    Capture-EngineFrame $frameTown 'town'

    $failedStep = 'select-Native-Town-Alley-entry'
    $townMenu = Invoke-AgentCli 'menu' @('-CommandId', "$prefix-town-options")
    $entryOption = @($townMenu.state.availableMenuOptions | Where-Object { $_.id -eq 'manage_alley' -and $_.available -and $_.enabled } | Select-Object -First 1)
    if ($townMenu.state.context.menuId -ne 'town' -or $entryOption.Count -ne 1)
        { throw "Town did not show the enabled Native manage_alley entry: $($townMenu.state.availableMenuOptions | ConvertTo-Json -Depth 4 -Compress)" }
    $entry = Invoke-AgentCli 'menuSelect' @('-MenuId', 'town', '-OptionId', 'manage_alley', '-CommandId', "$prefix-enter")
    if ($entry.status -ne 'completed' -or $entry.state.context.menuId -ne 'manage_alley')
        { throw "Native manage_alley menu option did not enter the Alley menu: $($entry.state.context | ConvertTo-Json -Depth 5 -Compress)" }
    Capture-EngineFrame $frameAlley 'manage-alley'
    $alleyMenu = Invoke-AgentCli 'menu' @('-CommandId', "$prefix-alley-options")
    $backOption = @($alleyMenu.state.availableMenuOptions | Where-Object { $_.id -eq 'back' -and $_.available -and $_.enabled } | Select-Object -First 1)
    if ($backOption.Count -ne 1) { throw 'Current Native manage_alley did not expose its enabled back option.' }

    $failedStep = 'return-through-Native-Alley-back-option'
    $leave = Invoke-AgentCli 'menuSelect' @('-MenuId', 'manage_alley', '-OptionId', 'back', '-CommandId', "$prefix-back")
    if ($leave.status -ne 'completed' -or $leave.state.context.menuId -ne 'town')
        { throw "Native Alley back option did not return to the visible Town menu: $($leave.state.context | ConvertTo-Json -Depth 5 -Compress)" }
    Capture-EngineFrame $frameReturn 'returned-town'
    $after = Invoke-AgentCli 'harnessAlleyRosterDiagnostics' @('-SettlementId', $TargetSettlementId, '-AlleyTag', $alleyTag, '-CommandId', "$prefix-after") 30
    $sameBusinessState = ($baseline.data.playerAlleyDataPresent -eq $after.data.playerAlleyDataPresent -and
        $baseline.data.alleyOwnerId -eq $after.data.alleyOwnerId -and $baseline.data.assignedHeroId -eq $after.data.assignedHeroId -and
        ($baseline.data.alleyRoster | ConvertTo-Json -Compress) -eq ($after.data.alleyRoster | ConvertTo-Json -Compress) -and
        ($baseline.data.mainPartyRoster | ConvertTo-Json -Compress) -eq ($after.data.mainPartyRoster | ConvertTo-Json -Compress) -and
        [int]$baseline.data.gold -eq [int]$after.data.gold -and [double]$baseline.data.influence -eq [double]$after.data.influence)
    $nativeEntryReturn = ($entry.state.context.gameState -eq 'MapState' -and $entry.state.mission -eq $null -and
        $leave.state.context.gameState -eq 'MapState' -and $leave.state.mission -eq $null)
    $clockStable = ([double]$baseline.data.campaignDay -eq [double]$after.data.campaignDay -and
        [string]$baseline.data.timeControlMode -eq [string]$after.data.timeControlMode -and
        [bool]$baseline.data.isWaiting -eq [bool]$after.data.isWaiting)
    if (-not $sameBusinessState) { throw 'Entering and returning from the Alley menu changed PlayerAlleyData, Owner, Leader, rosters, Gold, or Influence.' }

    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-stop") 30
    $allProcessesStopped = -not [bool](Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue)
    $result = [ordered]@{
        ProviderKind = 'Native Town manage_alley GameMenuOption -> Native manage_alley menu back option'
        ProcessId = $start.session.processId
        Fixture = $fixture.data
        TownEntryOption = $entryOption[0]
        AlleyMenuOptions = $alleyMenu.state.availableMenuOptions
        ResultMenuId = [string]$leave.state.context.menuId
        GameStateStayedMap = $nativeEntryReturn
        ActiveMissionAfterEntry = $entry.state.mission
        BusinessStateUnchanged = $sameBusinessState
        ClockStable = $clockStable
        CampaignDayBefore = [double]$baseline.data.campaignDay
        CampaignDayAfter = [double]$after.data.campaignDay
        RawTimeModeBefore = [string]$baseline.data.timeControlMode
        RawTimeModeAfter = [string]$after.data.timeControlMode
        IsWaitingBefore = [bool]$baseline.data.isWaiting
        IsWaitingAfter = [bool]$after.data.isWaiting
        EngineFrames = @($frameTown, $frameAlley, $frameReturn)
        SourceFixtureHashBefore = $fixtureHashBefore
        SourceFixtureHashAfter = $fixtureHashAfter
        SourceFixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = [bool]$stop.processStopped
        AllGameProcessesStopped = $allProcessesStopped
        Passed = ($sameBusinessState -and $nativeEntryReturn -and $clockStable -and $fixtureHashBefore -eq $fixtureHashAfter -and [bool]$stop.processStopped -and $allProcessesStopped)
    }
    $json = $result | ConvertTo-Json -Depth 14
    if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) { Set-Content -LiteralPath $resultPath -Value $json -Encoding UTF8 }
    $json
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
            ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $tempPath 'AlleyEntryMenuFailure.json') -Encoding UTF8
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
