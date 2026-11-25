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
$resultPath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP 'MapNotificationsResult.json' } else { Join-Path (Split-Path -Parent $PSScriptRoot) 'TestResults\ManualMapNotifications\MapNotificationsResult.json' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$env:CHRONICLE_HARNESS_MODE = 'visual-capture'
$prefix = 'map-notifications-' + (Get-Date -Format 'yyyyMMddHHmmssfff')

if (-not (Test-Path -LiteralPath $savePath)) { throw "Map notification fixture not found: $LoadSaveName" }
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
    if ($before.state.context.gameState -ne 'MapState') { throw 'Map notification test did not load into Campaign Map.' }

    $seed = Invoke-AgentCli 'harnessSeedMapNotificationFixture' @('-CommandId', "$prefix-seed")
    $first = Invoke-AgentCli 'mapNotifications' @('-CommandId', "$prefix-observe-1")
    $second = Invoke-AgentCli 'mapNotifications' @('-CommandId', "$prefix-observe-2")
    $after = Invoke-AgentCli 'state' @('-CommandId', "$prefix-state-after")
    $notice = @($first.data.notifications | Where-Object {
        $_.dataType -eq 'TraitChangedMapNotification' -and $_.descriptionText -eq [string]$seed.data.descriptionText
    } | Select-Object -First 1)
    $unregisteredNoticeExposed = @($first.data.notifications | Where-Object { $_.descriptionText -eq [string]$seed.data.unregisteredDescriptionText }).Count -gt 0
    $invalidNoticeExposed = @($first.data.notifications | Where-Object { $_.descriptionText -eq [string]$seed.data.invalidDescriptionText }).Count -gt 0

    $stableRepeatedRead = ($first.status -eq 'completed' -and $second.status -eq 'completed' -and
        ($first.data.notifications | ConvertTo-Json -Depth 8 -Compress) -ceq ($second.data.notifications | ConvertTo-Json -Depth 8 -Compress))
    $nativeMapNotificationVMDataReturned = ($notice.Count -eq 1 -and
        $notice[0].viewModelType -eq 'TraitChangedNotificationItemVM' -and
        -not [string]::IsNullOrWhiteSpace([string]$notice[0].titleText) -and
        -not [string]::IsNullOrWhiteSpace([string]$notice[0].notificationIdentifier))
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
        CampaignMapNoticeSeedCreatedNativeInformationData = ($seed.status -eq 'completed' -and $seed.data.testOnly -and $seed.data.type -eq 'TraitChangedMapNotification')
        NativeMapNotificationVMMappingReturnedItem = [bool]$nativeMapNotificationVMDataReturned
        NativeDescriptionTextPreserved = ($notice.Count -eq 1 -and $notice[0].descriptionText -eq [string]$seed.data.descriptionText)
        UnregisteredNativeNoticeNotExposed = -not $unregisteredNoticeExposed
        InvalidNoticeNotExposed = -not $invalidNoticeExposed
        RepeatedReadsStableAndOrdered = [bool]$stableRepeatedRead
        ObservationDoesNotMutateCampaignOrClock = [bool]$queryDidNotMutateCampaign
        FixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = [bool]$stop.processStopped
    }
    $failedAssertions = @($assertions.Keys | Where-Object { -not [bool]$assertions[$_] })
    $result = [ordered]@{
        Notice = if ($notice.Count -eq 1) { $notice[0] } else { $null }
        NativeNoticeCount = $first.data.notificationCount
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
    if (-not $result.Passed) { throw 'Native Campaign Map notice observation regression failed.' }
}
finally {
    if (Test-Path -LiteralPath $sessionPath) {
        try { Invoke-AgentCli 'stop' @('-CommandId', "$prefix-cleanup") 30 | Out-Null } catch { }
    }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
