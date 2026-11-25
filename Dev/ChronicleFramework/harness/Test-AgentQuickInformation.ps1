#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$resultPath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP 'QuickInformationResult.json' } else { Join-Path (Split-Path -Parent $PSScriptRoot) 'TestResults\ManualQuickInformation\QuickInformationResult.json' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$env:CHRONICLE_HARNESS_MODE = 'visual-capture'
$prefix = 'quick-information-' + (Get-Date -Format 'yyyyMMddHHmmssfff')

if (-not (Test-Path -LiteralPath $savePath)) { throw "QuickInformation fixture not found: $LoadSaveName" }
if (Get-Process -Name Bannerlord -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
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
    if ($before.state.context.gameState -ne 'MapState') { throw 'QuickInformation test did not load into Campaign Map.' }

    $seed = Invoke-AgentCli 'harnessSeedQuickInformationFixture' @('-CommandId', "$prefix-seed")
    $first = Invoke-AgentCli 'quickInformation' @('-CommandId', "$prefix-observe-1")
    $second = Invoke-AgentCli 'quickInformation' @('-CommandId', "$prefix-observe-2")
    $after = Invoke-AgentCli 'state' @('-CommandId', "$prefix-state-after")
    $nativeVisibleCurrent = ($first.status -eq 'completed' -and [bool]$first.data.available -and [bool]$first.data.hasVisibleQuickInfo -and
        [string]$first.data.notificationText -eq [string]$seed.data.currentText -and
        [int]$first.data.extraTimeInMs -eq [int]$seed.data.extraTimeInMs -and
        [double]$first.data.nativeDisplayDurationSeconds -ge ([double]$seed.data.extraTimeInMs / 1000.0) -and
        -not [bool]$first.data.isFadingOut)
    $queuedTextNotLeaked = ([string]$first.data.notificationText -ne [string]$seed.data.queuedText -and
        [bool]$second.data.hasVisibleQuickInfo -and [string]$second.data.notificationText -eq [string]$seed.data.currentText)
    $stableCurrentMessage = ([int]$first.data.notificationId -eq [int]$second.data.notificationId -and
        [string]$first.data.notificationText -eq [string]$second.data.notificationText)
    $queryDidNotMutateCampaign = (
        [int]$before.state.economy.gold -eq [int]$after.state.economy.gold -and
        [int]$before.state.party.itemCount -eq [int]$after.state.party.itemCount -and
        [int]@($before.state.quests).Count -eq [int]@($after.state.quests).Count -and
        [string]$before.state.context.timeControlMode -eq [string]$after.state.context.timeControlMode -and
        [double]$before.state.campaignDay -eq [double]$after.state.campaignDay
    )
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-stop") 30

    $assertions = [ordered]@{
        NativeQuickInfoUIAvailable = [bool]$first.data.available
        CurrentNativeQuickInfoExposed = [bool]$nativeVisibleCurrent
        HiddenQueuedQuickInfoNotExposed = [bool]$queuedTextNotLeaked
        CurrentMessageStableAcrossImmediateReads = [bool]$stableCurrentMessage
        QuickInfoReadDoesNotMutateCampaignOrClock = [bool]$queryDidNotMutateCampaign
        FixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = [bool]$stop.processStopped
    }
    $failedAssertions = @($assertions.Keys | Where-Object { -not [bool]$assertions[$_] })
    $result = [ordered]@{
        Current = $first.data
        RepeatedRead = $second.data
        Seed = $seed.data
        Assertions = $assertions
        FailedAssertions = $failedAssertions
        FixtureHashBefore = $fixtureHashBefore
        FixtureHashAfter = $fixtureHashAfter
        ProcessStopped = [bool]$stop.processStopped
        Passed = ($failedAssertions.Count -eq 0)
    }
    $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    $result | ConvertTo-Json -Depth 12
    if (-not $result.Passed) { throw 'Native QuickInformation observation regression failed.' }
}
finally {
    if (Test-Path -LiteralPath $sessionPath) {
        try { Invoke-AgentCli 'stop' @('-CommandId', "$prefix-cleanup") 30 | Out-Null } catch { }
    }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
