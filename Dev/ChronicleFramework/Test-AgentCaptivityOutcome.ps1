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
$runDirectory = if ($tempPath) { Split-Path -Parent $tempPath } else { Join-Path $PSScriptRoot 'TestResults\ManualCaptivityOutcome' }
$frameRoot = if ($tempPath) { $tempPath } else { $runDirectory }
$resultPath = if ($tempPath) { Join-Path $tempPath 'CaptivityOutcomeResult.json' } else { Join-Path $runDirectory 'CaptivityOutcomeResult.json' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$prefix = 'captivity-outcome-' + (Get-Date -Format 'yyyyMMddHHmmssfff')

if (-not (Test-Path -LiteralPath $savePath)) { throw "Disposable Captivity outcome fixture not found: $savePath" }
if (Get-Process -Name Bannerlord -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash

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
    $frameExists = Test-Path -LiteralPath $Path
    $frameLength = if ($frameExists) { (Get-Item -LiteralPath $Path).Length } else { 0 }
    if ($receipt.status -ne 'completed' -or -not $frameExists -or $frameLength -lt 4096)
        { throw "Native captivity outcome frame '$Path' was not captured (receipt='$($receipt.status)', exists=$frameExists, bytes=$frameLength)." }
}

function Invoke-CaptivityOutcomeTrial([ValidateSet('Accept','Reject')][string]$Choice) {
    $suffix = $Choice.ToLowerInvariant()
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    try {
        $before = Invoke-AgentCli 'state' @('-CommandId', "$prefix-$suffix-before")
        if ($before.state.context.gameState -ne 'MapState' -or $before.state.context.encounterActive -or $before.state.context.captivity)
            { throw "$Choice trial must begin on a free Campaign Map without an active encounter." }

        $captor = Invoke-AgentCli 'harnessPrepareSafePassageFixture' @('-CommandId', "$prefix-$suffix-captor") 30
        if ($captor.status -ne 'completed' -or [string]::IsNullOrWhiteSpace([string]$captor.data.partyId))
            { throw "$Choice trial failed to create its Native captor party." }
        $fixture = Invoke-AgentCli 'harnessSeedCaptivityObservationFixture' @('-PartyId', [string]$captor.data.partyId, '-CommandId', "$prefix-$suffix-captive") 30
        if ($fixture.status -ne 'completed' -or $fixture.data.menuId -ne 'menu_captivity_end_propose_ransom_wilderness')
            { throw "$Choice trial failed to reach the Native wilderness ransom menu." }

        $ransomMenu = Invoke-AgentCli 'state' @('-CommandId', "$prefix-$suffix-ransom-state")
        $frameBefore = Join-Path $frameRoot "captivity-$suffix-before.bmp"
        $frameAfter = Join-Path $frameRoot "captivity-$suffix-after.bmp"
        Capture-EngineFrame $frameBefore "$suffix-before-frame"

        $beforeInvalidSelectionGold = [int]$ransomMenu.state.economy.gold
        $beforeInvalidSelectionDay = [double]$ransomMenu.campaignDay
        $invalidSelection = Invoke-AgentCli 'menuSelect' @('-MenuId', 'menu_captivity_end_propose_ransom_wilderness', '-OptionId', 'chronicle_invalid_captivity_option', '-CommandId', "$prefix-$suffix-invalid-option") 30
        $afterInvalidSelection = Invoke-AgentCli 'state' @('-CommandId', "$prefix-$suffix-after-invalid-option")
        if ($invalidSelection.status -ne 'rejected' -or $afterInvalidSelection.state.context.menuId -ne 'menu_captivity_end_propose_ransom_wilderness' -or
            [int]$afterInvalidSelection.state.economy.gold -ne [int]$ransomMenu.state.economy.gold -or
            [double]$afterInvalidSelection.campaignDay -ne [double]$ransomMenu.campaignDay)
            { throw "$Choice trial invalid-option request was not rejected without changing the menu, Gold or Campaign time." }
        $ransomMenu = $afterInvalidSelection

        $expectedOptionId = if ($Choice -eq 'Accept') { 'mno_captivity_end_ransom_accept' } else { 'captivity_end_ransom_deny' }
        $visibleOptions = @($ransomMenu.state.availableMenuOptions | Where-Object { $_.available -and $_.enabled })
        $selectedOption = @($visibleOptions | Where-Object { $_.id -eq $expectedOptionId })
        if ($selectedOption.Count -ne 1) { throw "$Choice option '$expectedOptionId' was not uniquely visible and enabled in the Native ransom menu." }

        $beforeDiagnostic = Invoke-AgentCli 'harnessCaptivityDiagnostics' @('-PartyId', [string]$captor.data.partyId, '-CommandId', "$prefix-$suffix-diagnostics-before") 30
        if ($beforeDiagnostic.status -ne 'completed') { throw "$Choice trial could not read pre-choice native diagnostics." }

        $selection = Invoke-AgentCli 'menuSelect' @('-MenuId', 'menu_captivity_end_propose_ransom_wilderness', '-OptionId', $expectedOptionId, '-CommandId', "$prefix-$suffix-select") 30
        if ($selection.status -ne 'completed') { throw "$Choice trial Native menu selection did not complete." }
        $after = Invoke-AgentCli 'state' @('-CommandId', "$prefix-$suffix-after")
        Capture-EngineFrame $frameAfter "$suffix-after-frame"
        $afterDiagnostic = Invoke-AgentCli 'harnessCaptivityDiagnostics' @('-PartyId', [string]$captor.data.partyId, '-CommandId', "$prefix-$suffix-diagnostics-after") 30
        if ($afterDiagnostic.status -ne 'completed') { throw "$Choice trial could not read post-choice native diagnostics." }

        $pre = $beforeDiagnostic.data
        $post = $afterDiagnostic.data
        $quote = [int]$fixture.data.nativeRansomAmount
        $optionText = [string]$selectedOption[0].text
        $goldExpected = if ($Choice -eq 'Accept') { [int]$pre.gold - $quote } else { [int]$pre.gold }
        $goldMatchesNativeBranch = ([int]$post.gold -eq $goldExpected)
        $acceptCampaignDayUnchangedAtPostObservation = ([double]$pre.campaignDay -eq [double]$post.campaignDay)
        $captorRosterCleared = ($post.captorPartyFound -and -not $post.captorRosterContainsMainHero -and [int]$post.captorMainHeroPrisonerCount -eq 0)
        $acceptReleasedMainHero = (-not $post.isCaptive -and -not $post.heroIsPrisoner -and $post.mainPartyIsActive -and $post.mainPartyContainsMainHero -and $captorRosterCleared)
        $rejectKeptMainHeroCaptive = ($post.isCaptive -and $post.heroIsPrisoner -and $post.captorRosterContainsMainHero -and [int]$post.captorMainHeroPrisonerCount -gt 0)
        $rejectReturnedToWaitMenu = ($post.menuId -eq 'prisoner_wait')
        $rejectResumedNativeWaitClock = ([double]$post.campaignDay -ge [double]$pre.campaignDay -and $post.timeControlMode -eq 'UnstoppableFastForward')

        $stop = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-$suffix-stop") 30
        [ordered]@{
            Choice = $Choice
            ProcessId = $start.session.processId
            CaptorPartyId = $captor.data.partyId
            NativeRansomFixture = $fixture.data
            SelectedNativeOption = [ordered]@{ id = $expectedOptionId; text = $optionText }
            InvalidOptionRejectedWithoutEffects = ($invalidSelection.status -eq 'rejected' -and $afterInvalidSelection.state.context.menuId -eq 'menu_captivity_end_propose_ransom_wilderness' -and [int]$afterInvalidSelection.state.economy.gold -eq $beforeInvalidSelectionGold -and [double]$afterInvalidSelection.campaignDay -eq $beforeInvalidSelectionDay)
            MenuSelection = $selection
            Before = $pre
            After = $post
            BeforeGameState = $ransomMenu.state.context.gameState
            AfterGameState = $after.state.context.gameState
            AfterMenuId = $after.state.context.menuId
            CampaignDayBefore = $pre.campaignDay
            CampaignDayAfter = $post.campaignDay
            GoldExpectedAfter = $goldExpected
            GoldMatchesNativeBranch = $goldMatchesNativeBranch
            AcceptCampaignDayUnchangedAtPostObservation = if ($Choice -eq 'Accept') { $acceptCampaignDayUnchangedAtPostObservation } else { $null }
            CaptorRosterClearedOnAccept = $captorRosterCleared
            AcceptReleasedMainHeroToMainParty = $acceptReleasedMainHero
            RejectLeftMainHeroCaptive = $rejectKeptMainHeroCaptive
            RejectReturnedToNativeWaitMenu = $rejectReturnedToWaitMenu
            RejectResumedNativeWaitClock = $rejectResumedNativeWaitClock
            EngineFrames = @($frameBefore, $frameAfter)
            ProcessStopped = [bool]$stop.processStopped
            Passed = if ($Choice -eq 'Accept') { $invalidSelection.status -eq 'rejected' -and $goldMatchesNativeBranch -and $acceptCampaignDayUnchangedAtPostObservation -and $acceptReleasedMainHero } else { $invalidSelection.status -eq 'rejected' -and $goldMatchesNativeBranch -and $rejectKeptMainHeroCaptive -and $rejectReturnedToWaitMenu -and $rejectResumedNativeWaitClock }
        }
    }
    finally {
        if (Test-Path $sessionPath) { try { Invoke-AgentCli 'stop' @('-CommandId', "$prefix-$suffix-cleanup") 30 | Out-Null } catch { } }
    }
}

try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $accept = Invoke-CaptivityOutcomeTrial 'Accept'
    $reject = Invoke-CaptivityOutcomeTrial 'Reject'
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $processesStopped = -not [bool](Get-Process -Name Bannerlord -ErrorAction SilentlyContinue)
    $result = [ordered]@{
        ProviderKind = 'Native MainHero captivity outcomes through currently visible GameMenu options; disposable fixture only'
        Accept = $accept
        Reject = $reject
        SourceFixtureHashBefore = $fixtureHashBefore
        SourceFixtureHashAfter = $fixtureHashAfter
        SourceFixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        AllGameProcessesStopped = $processesStopped
        Passed = ([bool]$accept.Passed -and [bool]$reject.Passed -and $fixtureHashBefore -eq $fixtureHashAfter -and $processesStopped)
    }
    $json = $result | ConvertTo-Json -Depth 16
    if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) { Set-Content -LiteralPath $resultPath -Value $json -Encoding UTF8 }
    $json
    if (-not $result.Passed) { exit 1 }
}
finally {
    if (Test-Path $sessionPath) { try { Invoke-AgentCli 'stop' @('-CommandId', "$prefix-final-cleanup") 30 | Out-Null } catch { } }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
