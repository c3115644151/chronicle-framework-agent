#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$tempPath = $env:CHRONICLE_HARNESS_TEMP
$runDirectory = if ($tempPath) { Split-Path -Parent $tempPath } else { Join-Path (Split-Path -Parent $PSScriptRoot) 'TestResults\ManualMapEscapeMenu' }
$frameRoot = if ($tempPath) { $tempPath } else { $runDirectory }
$resultPath = if ($tempPath) { Join-Path $tempPath 'MapEscapeMenuResult.json' } else { Join-Path $runDirectory 'MapEscapeMenuResult.json' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$prefix = 'map-escape-menu-' + (Get-Date -Format 'yyyyMMddHHmmssfff')
$step = 'preflight'
$loaded = $null
$state = $null
$beforeFrame = Join-Path $frameRoot 'map-escape-menu-before.bmp'
$openFrame = Join-Path $frameRoot 'map-escape-menu-open.bmp'
$closedFrame = Join-Path $frameRoot 'map-escape-menu-closed.bmp'

if (-not (Test-Path -LiteralPath $savePath)) { throw "Disposable Campaign fixture not found: $LoadSaveName" }
if (Get-Process -Name Bannerlord -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
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
    $exists = Test-Path -LiteralPath $Path
    $length = if ($exists) { (Get-Item -LiteralPath $Path).Length } else { 0 }
    if ($receipt.status -ne 'completed' -or -not $exists -or $length -lt 4096) { throw "Native frame was not captured: $Path; receipt=$($receipt | ConvertTo-Json -Depth 5 -Compress); exists=$exists; bytes=$length" }
}

try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $step = 'load-disposable-campaign'
    $loaded = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $state = Invoke-AgentCli 'state' @('-CommandId', "$prefix-start")
    if ($state.state.context.gameState -ne 'MapState' -or [bool]$state.state.context.escapeMenuOpen) { throw 'Fixture did not start on an unobstructed Campaign Map.' }

    $startupDiagnostics = Invoke-AgentCli 'harnessMapDiagnostics' @('-CommandId', "$prefix-map-diagnostics") 30
    if ($startupDiagnostics.status -ne 'completed' -or -not [bool]$startupDiagnostics.data.harnessFocusLossEscapeMenuGuardInstalled) { throw 'Visual Harness focus-loss guard is not installed.' }
    if ([bool]$startupDiagnostics.data.mapStateAtMenu -or [bool]$startupDiagnostics.data.escapeMenuOpen) { throw "Map input is already blocked: $($startupDiagnostics.data | ConvertTo-Json -Compress)" }

    $step = 'pause-and-capture-baseline'
    $pause = Invoke-AgentCli 'pause' @('-CommandId', "$prefix-pause")
    if ($pause.status -ne 'completed') { throw 'Could not explicitly pause the disposable Campaign before the overlay-only comparison.' }
    $before = Invoke-AgentCli 'state' @('-CommandId', "$prefix-before")
    Capture-EngineFrame $beforeFrame 'before'

    $closedReceipt = Invoke-AgentCli 'closeEscapeMenu' @('-CommandId', "$prefix-close-when-closed") 30
    $closedActionRejected = ($closedReceipt.status -eq 'rejected' -and [string]$closedReceipt.error -match 'Native Campaign Map Escape menu to be open')
    if (-not $closedActionRejected) { throw "closeEscapeMenu must reject the closed-menu case without treating it as an implicit time-control action; receipt=$($closedReceipt | ConvertTo-Json -Depth 6 -Compress)" }

    $step = 'open-native-map-escape-menu'
    $openReceipt = Invoke-AgentCli 'harnessOpenMapEscapeMenu' @('-CommandId', "$prefix-open") 30
    if ($openReceipt.status -ne 'completed' -or -not [bool]$openReceipt.data.escapeMenuOpen) { throw "Native MapScreen did not produce an observable Escape menu: $($openReceipt.data | ConvertTo-Json -Compress)" }
    $opened = Invoke-AgentCli 'state' @('-CommandId', "$prefix-observe-open")
    if ($opened.state.context.gameState -ne 'MapState' -or -not [bool]$opened.state.context.escapeMenuOpen) { throw "Observer did not report the open native overlay: $($opened.state.context | ConvertTo-Json -Compress)" }
    Capture-EngineFrame $openFrame 'open'

    $step = 'verify-map-action-blocked-before-side-effects'
    $pursueRejectedReceipt = Invoke-AgentCli 'pursue' @('-PartyId', 'not-a-live-party', '-CommandId', "$prefix-pursue-blocked") 30
    $pursueRejected = ($pursueRejectedReceipt.status -eq 'rejected' -and [string]$pursueRejectedReceipt.error -match 'unobstructed Campaign Map')
    if (-not $pursueRejected) { throw 'pursue did not reject the Native Escape overlay before requesting a target.' }
    $stillOpen = Invoke-AgentCli 'state' @('-CommandId', "$prefix-still-open")
    if (-not [bool]$stillOpen.state.context.escapeMenuOpen) { throw 'Rejected map action changed the Escape overlay state.' }

    $step = 'close-native-overlay-with-product-action'
    $close = Invoke-AgentCli 'closeEscapeMenu' @('-CommandId', "$prefix-close")
    if ($close.status -ne 'completed') { throw "Native MapScreen close callback failed: $($close.error)" }
    $after = Invoke-AgentCli 'state' @('-CommandId', "$prefix-after")
    if ($after.state.context.gameState -ne 'MapState' -or [bool]$after.state.context.escapeMenuOpen) { throw "Native close did not restore map observation: $($after.state.context | ConvertTo-Json -Compress)" }
    Capture-EngineFrame $closedFrame 'closed'

    $stable = [ordered]@{
        gameState = ($before.state.context.gameState -eq $after.state.context.gameState)
        campaignDay = ([math]::Abs([double]$before.campaignDay - [double]$after.campaignDay) -le 0.000001)
        rawTimeMode = ($before.timeControlMode -eq $after.timeControlMode)
        waiting = ($before.state.context.isWaiting -eq $after.state.context.isWaiting)
        gold = ($before.state.economy.gold -eq $after.state.economy.gold)
        influence = ($before.state.economy.influence -eq $after.state.economy.influence)
        partyTarget = ($before.state.location.targetPartyId -eq $after.state.location.targetPartyId)
        questCount = (@($before.state.quests).Count -eq @($after.state.quests).Count)
    }
    $unchanged = @($stable.Values | Where-Object { -not $_ }).Count -eq 0
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-stop") 30
    $allProcessesStopped = -not [bool](Get-Process -Name Bannerlord -ErrorAction SilentlyContinue)
    $result = [ordered]@{
        ProviderKind = 'Native MapScreen OpenEscapeMenu test fixture -> Agent observer -> Native CloseEscapeMenu callback'
        ProcessId = $loaded.session.processId
        Before = [ordered]@{ campaignDay = $before.campaignDay; timeControlMode = $before.timeControlMode; isWaiting = $before.state.context.isWaiting; escapeMenuOpen = $before.state.context.escapeMenuOpen }
        Open = [ordered]@{ gameState = $opened.state.context.gameState; menuState = $openReceipt.data; screenshot = $openFrame }
        ClosedMenuActionRejected = $closedActionRejected
        PursueRejectedWithoutChangingMenu = $pursueRejected
        CloseReceipt = $close
        After = [ordered]@{ campaignDay = $after.campaignDay; timeControlMode = $after.timeControlMode; isWaiting = $after.state.context.isWaiting; escapeMenuOpen = $after.state.context.escapeMenuOpen }
        Unchanged = $stable
        OverlayTransitionOnly = $unchanged
        EngineFrames = @($beforeFrame, $openFrame, $closedFrame)
        SourceFixtureHashBefore = $fixtureHashBefore
        SourceFixtureHashAfter = $fixtureHashAfter
        SourceFixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = [bool]$stop.processStopped
        AllGameProcessesStopped = $allProcessesStopped
        Passed = ($closedActionRejected -and $pursueRejected -and $unchanged -and $fixtureHashBefore -eq $fixtureHashAfter -and [bool]$stop.processStopped -and $allProcessesStopped)
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
            ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $tempPath 'MapEscapeMenuFailure.json') -Encoding UTF8
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
