[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$resultPath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP 'SceneNotificationResult.json' } else { Join-Path $PSScriptRoot 'TestResults\ManualSceneNotification\SceneNotificationResult.json' }
$framePath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP 'scene-notification-active.bmp' } else { Join-Path $PSScriptRoot 'TestResults\ManualSceneNotification\scene-notification-active.bmp' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$env:CHRONICLE_HARNESS_MODE = 'visual-capture'
$prefix = 'scene-notification-' + (Get-Date -Format 'yyyyMMddHHmmssfff')

if (-not (Test-Path -LiteralPath $savePath)) { throw "Scene notification fixture not found: $LoadSaveName" }
if (Get-Process -Name Bannerlord -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

try {
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $before = Invoke-AgentCli 'state' @('-CommandId', "$prefix-state-before")
    if ($before.state.context.gameState -ne 'MapState') { throw 'Scene notification test did not load into Campaign Map.' }

    $seed = Invoke-AgentCli 'harnessSeedSceneNotificationFixture' @('-CommandId', "$prefix-seed")
    $first = $null
    $deadline = [DateTime]::UtcNow.AddSeconds([Math]::Min(90, $TimeoutSeconds))
    while ([DateTime]::UtcNow -lt $deadline) {
        $first = Invoke-AgentCli 'sceneNotification' @('-CommandId', "$prefix-active")
        if ($first.status -eq 'completed' -and [bool]$first.data.hasActiveNotification -and [bool]$first.data.isReady -and
            [string]$first.data.titleText -eq [string]$seed.data.titleText) { break }
        Start-Sleep -Milliseconds 300
    }
    if ($null -eq $first -or -not [bool]$first.data.hasActiveNotification -or -not [bool]$first.data.isReady -or
        [string]$first.data.titleText -ne [string]$seed.data.titleText) { throw 'Native SceneNotification did not become the active, ready notification before timeout.' }

    $beforeRead = Invoke-AgentCli 'state' @('-CommandId', "$prefix-state-before-read")
    $capture = Invoke-AgentCli 'captureFrame' @('-OutputPath', $framePath, '-CommandId', "$prefix-capture") 30
    $second = Invoke-AgentCli 'sceneNotification' @('-CommandId', "$prefix-repeat")
    $afterRead = Invoke-AgentCli 'state' @('-CommandId', "$prefix-state-after-read")
    $frameExists = (Test-Path -LiteralPath $framePath -PathType Leaf) -and (Get-Item -LiteralPath $framePath).Length -gt 0

    $nativeVMFieldsMatchData = (
        $first.status -eq 'completed' -and $first.data.dataType -eq 'HeroExecutionSceneNotificationData' -and
        [string]$first.data.titleText -eq [string]$seed.data.titleText -and
        [string]$first.data.affirmativeTitleText -eq [string]$seed.data.affirmativeTitleText -and
        [string]$first.data.affirmativeDescription -eq [string]$seed.data.affirmativeDescription -and
        [string]$first.data.affirmativeButtonLabel -eq [string]$seed.data.affirmativeButtonLabel -and
        [bool]$first.data.affirmativeButtonShown -eq [bool]$seed.data.affirmativeButtonShown -and
        [string]$first.data.negativeButtonLabel -eq [string]$seed.data.negativeButtonLabel -and
        [bool]$first.data.negativeButtonShown -eq [bool]$seed.data.negativeButtonShown
    )
    $repeatedReadStable = (
        $second.status -eq 'completed' -and $second.data.hasActiveNotification -and $second.data.isReady -and
        [string]$first.data.titleText -eq [string]$second.data.titleText -and
        [string]$first.data.affirmativeButtonLabel -eq [string]$second.data.affirmativeButtonLabel -and
        [bool]$first.data.affirmativeButtonShown -eq [bool]$second.data.affirmativeButtonShown
    )
    $campaignUnchangedDuringReads = (
        [int]$beforeRead.state.economy.gold -eq [int]$afterRead.state.economy.gold -and
        [int]$beforeRead.state.party.itemCount -eq [int]$afterRead.state.party.itemCount -and
        [int]@($beforeRead.state.quests).Count -eq [int]@($afterRead.state.quests).Count -and
        [string]$beforeRead.state.context.timeControlMode -eq [string]$afterRead.state.context.timeControlMode -and
        [double]$beforeRead.state.campaignDay -eq [double]$afterRead.state.campaignDay
    )
    if ($capture.status -ne 'completed') { throw "Scene notification engine frame capture was rejected: $($capture.message)" }

    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-stop") 30
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $assertions = [ordered]@{
        NativeSceneNotificationBecameActiveAndReady = [bool]($first.data.hasActiveNotification -and $first.data.isReady)
        NativeSceneNotificationVMFieldsMatchData = [bool]$nativeVMFieldsMatchData
        VisibleButtonAffordancesAreReported = [bool]($first.data.affirmativeButtonShown -and -not $first.data.negativeButtonShown)
        RepeatedReadDoesNotDismissOrCommitNotice = [bool]$repeatedReadStable
        ActualEngineFrameCaptured = [bool]$frameExists
        CampaignUnchangedDuringReads = [bool]$campaignUnchangedDuringReads
        FixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = [bool]$stop.processStopped
    }
    $failedAssertions = @($assertions.Keys | Where-Object { -not [bool]$assertions[$_] })
    $result = [ordered]@{
        Data = $first.data
        Seed = $seed.data
        NativeFrame = $framePath
        NativeFrameBytes = if ($frameExists) { (Get-Item -LiteralPath $framePath).Length } else { 0 }
        BeforeRead = [ordered]@{ Gold = $beforeRead.state.economy.gold; PartyItemCount = $beforeRead.state.party.itemCount; CampaignDay = $beforeRead.state.campaignDay; TimeControlMode = $beforeRead.state.context.timeControlMode }
        AfterRead = [ordered]@{ Gold = $afterRead.state.economy.gold; PartyItemCount = $afterRead.state.party.itemCount; CampaignDay = $afterRead.state.campaignDay; TimeControlMode = $afterRead.state.context.timeControlMode }
        Assertions = $assertions
        FailedAssertions = $failedAssertions
        FixtureHashBefore = $fixtureHashBefore
        FixtureHashAfter = $fixtureHashAfter
        ProcessStopped = [bool]$stop.processStopped
        Passed = ($failedAssertions.Count -eq 0)
    }
    $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    $result | ConvertTo-Json -Depth 12
    if (-not $result.Passed) { throw 'Native SceneNotification observation regression failed.' }
}
finally {
    if (Test-Path -LiteralPath $sessionPath) {
        try { Invoke-AgentCli 'stop' @('-CommandId', "$prefix-cleanup") 30 | Out-Null } catch { }
    }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
