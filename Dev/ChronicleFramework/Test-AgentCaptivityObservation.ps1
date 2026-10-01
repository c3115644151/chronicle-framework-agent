[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$tempPath = $env:CHRONICLE_HARNESS_TEMP
$runDirectory = if ($tempPath) { Split-Path -Parent $tempPath } else { Join-Path $PSScriptRoot 'TestResults\ManualCaptivityObservation' }
$framePath = if ($tempPath) { Join-Path $tempPath 'captivity-ransom-menu.bmp' } else { Join-Path $runDirectory 'captivity-ransom-menu.bmp' }
$escapeFramePath = if ($tempPath) { Join-Path $tempPath 'captivity-escape-continuation-menu.bmp' } else { Join-Path $runDirectory 'captivity-escape-continuation-menu.bmp' }
$resultPath = if ($tempPath) { Join-Path $tempPath 'CaptivityObservationResult.json' } else { Join-Path $runDirectory 'CaptivityObservationResult.json' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$prefix = 'captivity-observation-' + (Get-Date -Format 'yyyyMMddHHmmssfff')

if (-not (Test-Path -LiteralPath $savePath)) { throw "Disposable Captivity observation fixture not found: $savePath" }
if (Get-Process -Name Bannerlord -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
$start = $null

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

function Capture-EngineFrame([string]$Path, [string]$Suffix) {
    $receipt = Invoke-AgentCli 'captureFrame' @('-OutputPath', $Path, '-CommandId', "$prefix-$Suffix") 30
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path -LiteralPath $Path) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
    if ($receipt.status -ne 'completed' -or -not (Test-Path -LiteralPath $Path) -or (Get-Item -LiteralPath $Path).Length -lt 4096)
        { throw "Native captivity menu frame '$Path' was not captured." }
}

try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $before = Invoke-AgentCli 'state' @('-CommandId', "$prefix-before")
    if ($before.state.context.gameState -ne 'MapState' -or $before.state.context.encounterActive -or $before.state.context.captivity)
        { throw 'Captivity observation fixture must begin on a free Campaign Map without an active encounter.' }

    $captorFixture = Invoke-AgentCli 'harnessPrepareSafePassageFixture' @('-CommandId', "$prefix-captor-fixture") 30
    if ($captorFixture.status -ne 'completed' -or [string]::IsNullOrWhiteSpace([string]$captorFixture.data.partyId))
        { throw 'Native harness captor party fixture was not created.' }
    $captivityFixture = Invoke-AgentCli 'harnessSeedCaptivityObservationFixture' @('-PartyId', [string]$captorFixture.data.partyId, '-CommandId', "$prefix-captivity-fixture") 30
    if ($captivityFixture.status -ne 'completed' -or $captivityFixture.data.menuId -ne 'menu_captivity_end_propose_ransom_wilderness')
        { throw 'Native MainHero captivity fixture did not reach its ransom-offer Campaign menu.' }

    $first = Invoke-AgentCli 'state' @('-CommandId', "$prefix-observe-1")
    Capture-EngineFrame $framePath 'capture-ransom-menu'
    $second = Invoke-AgentCli 'state' @('-CommandId', "$prefix-observe-2")
    $escapeFixture = Invoke-AgentCli 'harnessSwitchCaptivityObservationMenu' @('-CommandId', "$prefix-switch-escape-menu") 30
    if ($escapeFixture.status -ne 'completed' -or $escapeFixture.data.currentMenuId -ne 'menu_captivity_end_wilderness_escape')
        { throw 'Native Captivity fixture did not reach the Wilderness escape continuation menu.' }
    $escapeFirst = Invoke-AgentCli 'state' @('-CommandId', "$prefix-escape-observe-1")
    Capture-EngineFrame $escapeFramePath 'capture-escape-continuation'
    $escapeSecond = Invoke-AgentCli 'state' @('-CommandId', "$prefix-escape-observe-2")
    $context = $first.state.context.captivity
    $secondContext = $second.state.context.captivity
    $options = @($first.state.availableMenuOptions | Where-Object { $_.available -and $_.enabled })
    $acceptOption = @($options | Where-Object { $_.id -eq 'mno_captivity_end_ransom_accept' })
    $declineOption = @($options | Where-Object { $_.id -eq 'captivity_end_ransom_deny' })
    $escapeContext = $escapeFirst.state.context.captivity
    $escapeSecondContext = $escapeSecond.state.context.captivity
    $escapeOptions = @($escapeFirst.state.availableMenuOptions | Where-Object { $_.available -and $_.enabled })
    $continueOption = @($escapeOptions | Where-Object { $_.id -eq 'mno_continue' })

    $result = [ordered]@{
        ProviderKind = 'Native UI observation fixture; no captivity choice submitted'
        ProcessId = $start.session.processId
        CaptorFixture = $captorFixture.data
        CaptivityFixture = $captivityFixture.data
        NativeEscapeMenuFixture = $escapeFixture.data
        CaptivityObservation = $context
        AvailableOptions = @($options | ForEach-Object { [ordered]@{ id = $_.id; text = $_.text } })
        RepeatObservation = $secondContext
        EscapeMenuObservation = $escapeContext
        EscapeMenuOptions = @($escapeOptions | ForEach-Object { [ordered]@{ id = $_.id; text = $_.text } })
        RepeatEscapeObservation = $escapeSecondContext
        EngineFrames = @($framePath, $escapeFramePath)
        MainHeroGoldBeforeCapture = $before.state.economy.gold
        MainHeroGoldAfterCapture = $first.state.economy.gold
        PlayerCaptivityVisible = [bool]$context.isCaptive
        CurrentRansomMenuObserved = ($first.state.context.menuId -eq 'menu_captivity_end_propose_ransom_wilderness')
        RansomOfferOnlyWhenVisible = ([bool]$context.ransomOfferVisible -and [int]$context.currentVisibleRansomAmount -eq [int]$captivityFixture.data.nativeRansomAmount)
        NativeAcceptAndDeclineOptionsObserved = ($acceptOption.Count -eq 1 -and $declineOption.Count -eq 1)
        RepeatedCaptivityObservationStable = ($context.isCaptive -eq $secondContext.isCaptive -and $context.currentMenuId -eq $secondContext.currentMenuId -and $context.currentVisibleRansomAmount -eq $secondContext.currentVisibleRansomAmount)
        EscapeContinuationMenuObserved = ($escapeContext.isCaptive -and $escapeContext.currentMenuId -eq 'menu_captivity_end_wilderness_escape' -and $continueOption.Count -eq 1)
        RansomQuoteHiddenOutsideOfferMenu = (-not $escapeContext.ransomOfferVisible -and $null -eq $escapeContext.currentVisibleRansomAmount)
        RepeatedEscapeObservationStable = ($escapeContext.isCaptive -eq $escapeSecondContext.isCaptive -and $escapeContext.currentMenuId -eq $escapeSecondContext.currentMenuId -and $escapeContext.currentVisibleRansomAmount -eq $escapeSecondContext.currentVisibleRansomAmount)
        ObservationDidNotMutateCampaignOrResources = ([double]$first.campaignDay -eq [double]$second.campaignDay -and [int]$first.state.economy.gold -eq [int]$second.state.economy.gold -and [string]$first.state.context.timeControlMode -eq [string]$second.state.context.timeControlMode)
        MenuStageChangeDidNotMutateCampaignOrResources = ([double]$first.campaignDay -eq [double]$escapeFirst.campaignDay -and [int]$first.state.economy.gold -eq [int]$escapeFirst.state.economy.gold -and [int]$first.state.party.members -eq [int]$escapeFirst.state.party.members -and [string]$first.state.context.timeControlMode -eq [string]$escapeFirst.state.context.timeControlMode)
        RansomWasNotAcceptedOrDeclined = $true
        CaptivityContextOmittedWhenFree = ($null -eq $before.state.context.captivity)
        SourceFixtureUnchanged = $false
        ProcessStopped = $false
    }

    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-stop") 30
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $result.SourceFixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
    $result.ProcessStopped = [bool]$stop.processStopped
    $result.Passed = (
        $result.PlayerCaptivityVisible -and $result.CurrentRansomMenuObserved -and $result.RansomOfferOnlyWhenVisible -and
        $result.NativeAcceptAndDeclineOptionsObserved -and $result.RepeatedCaptivityObservationStable -and
        $result.EscapeContinuationMenuObserved -and $result.RansomQuoteHiddenOutsideOfferMenu -and $result.RepeatedEscapeObservationStable -and
        $result.ObservationDidNotMutateCampaignOrResources -and $result.MenuStageChangeDidNotMutateCampaignOrResources -and $result.RansomWasNotAcceptedOrDeclined -and
        $result.CaptivityContextOmittedWhenFree -and $result.SourceFixtureUnchanged -and $result.ProcessStopped
    )
    $json = $result | ConvertTo-Json -Depth 14
    if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) { Set-Content -LiteralPath $resultPath -Value $json -Encoding UTF8 }
    $json
    if (-not $result.Passed) { exit 1 }
}
finally {
    if (Test-Path $sessionPath) { try { Invoke-AgentCli 'stop' @('-CommandId', "$prefix-cleanup") 30 | Out-Null } catch { } }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
