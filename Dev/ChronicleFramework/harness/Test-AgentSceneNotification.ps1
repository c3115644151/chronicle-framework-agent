#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$LoadSaveName = 'save002',
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$resultPath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP 'SceneNotificationResult.json' } else { Join-Path (Split-Path -Parent $PSScriptRoot) 'TestResults\ManualSceneNotification\SceneNotificationResult.json' }
$framePath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP 'scene-notification-active.bmp' } else { Join-Path (Split-Path -Parent $PSScriptRoot) 'TestResults\ManualSceneNotification\scene-notification-active.bmp' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$env:CHRONICLE_HARNESS_MODE = 'visual-capture'
$prefix = 'scene-notification-' + (Get-Date -Format 'yyyyMMddHHmmssfff')
$bannerFramePath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP 'storymode-banner-editor-active.bmp' } else { Join-Path (Split-Path -Parent $PSScriptRoot) 'TestResults\ManualSceneNotification\storymode-banner-editor-active.bmp' }

if (-not (Test-Path -LiteralPath $savePath)) { throw "Scene notification fixture not found: $LoadSaveName" }
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
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName, '-IncludeChronicleFramework')
    $before = Invoke-AgentCli 'state' @('-CommandId', "$prefix-state-before")
    if ($before.state.context.gameState -ne 'MapState') { throw 'Scene notification test did not load into Campaign Map.' }
    $resume = Invoke-AgentCli 'resume' @('-CommandId', "$prefix-resume")
    if ($resume.status -ne 'completed') { throw "Could not establish active Native Campaign time before showing the scene notification: $($resume | ConvertTo-Json -Depth 8 -Compress)" }

    $seed = Invoke-AgentCli 'harnessSeedSceneNotificationFixture' @('-CommandId', "$prefix-seed")
    $first = $null
    $deadline = [DateTime]::UtcNow.AddSeconds([Math]::Min(90, $TimeoutSeconds))
    while ([DateTime]::UtcNow -lt $deadline) {
        $first = Invoke-AgentCli 'sceneNotification' @('-CommandId', "$prefix-active")
        if ($first.status -eq 'completed' -and [bool]$first.data.hasActiveNotification -and [bool]$first.data.isShown -and [bool]$first.data.isReady -and
            [bool]$first.data.canContinue -and
            [string]$first.data.titleText -eq [string]$seed.data.titleText) { break }
        Start-Sleep -Milliseconds 300
    }
    if ($null -eq $first -or -not [bool]$first.data.hasActiveNotification -or -not [bool]$first.data.isShown -or -not [bool]$first.data.isReady -or
        -not [bool]$first.data.canContinue -or
        [string]$first.data.titleText -ne [string]$seed.data.titleText) { throw 'Native SceneNotification did not become the active, ready notification before timeout.' }

    $beforeRead = Invoke-AgentCli 'state' @('-CommandId', "$prefix-state-before-read")
    $capture = Invoke-AgentCli 'captureFrame' @('-OutputPath', $framePath, '-CommandId', "$prefix-capture") 30
    Start-Sleep -Seconds 2
    $second = Invoke-AgentCli 'sceneNotification' @('-CommandId', "$prefix-repeat")
    $afterRead = Invoke-AgentCli 'state' @('-CommandId', "$prefix-state-after-read")
    $frameExists = (Test-Path -LiteralPath $framePath -PathType Leaf) -and (Get-Item -LiteralPath $framePath).Length -gt 0
    $continue = Invoke-AgentCli 'continueSceneNotification' @('-CommandId', "$prefix-continue")
    $afterClose = Invoke-AgentCli 'state' @('-CommandId', "$prefix-state-after-close")
    $followUp = $continue.data.followUpInquiry
    if ($followUp.kind -ne 'StoryModeClanNameTextInquiry' -or -not $followUp.token) { throw 'Closing the natural StoryMode banner notification did not open the original family-name TextInquiry.' }
    $clanName = [string]$followUp.defaultInputText
    $submitName = Invoke-AgentCli 'submitStoryModeClanName' @('-InquiryToken', [string]$followUp.token, '-Text', $clanName, '-CommandId', "$prefix-submit-clan-name")
    if ($submitName.status -ne 'completed') { throw "Native clan-name TextInquiry submission failed: $($submitName | ConvertTo-Json -Depth 8 -Compress)" }
    $bannerEditorState = $null
    $bannerEditorDeadline = [DateTime]::UtcNow.AddSeconds([Math]::Min(60, $TimeoutSeconds))
    while ([DateTime]::UtcNow -lt $bannerEditorDeadline) {
        $bannerEditorState = Invoke-AgentCli 'state' @('-CommandId', "$prefix-banner-editor-state")
        if ($bannerEditorState.state.context.gameState -eq 'BannerEditorState' -and $bannerEditorState.state.context.bannerEditor.supported) { break }
        Start-Sleep -Milliseconds 250
    }
    if ($null -eq $bannerEditorState -or $bannerEditorState.state.context.gameState -ne 'BannerEditorState' -or -not $bannerEditorState.state.context.bannerEditor.supported) { throw 'The Native family-name callback did not enter the supported player BannerEditorState.' }
    $bannerCapture = Invoke-AgentCli 'captureFrame' @('-OutputPath', $bannerFramePath, '-CommandId', "$prefix-banner-capture") 30
    $bannerFrameExists = (Test-Path -LiteralPath $bannerFramePath -PathType Leaf) -and (Get-Item -LiteralPath $bannerFramePath).Length -gt 0
    $bannerDone = Invoke-AgentCli 'bannerEditorDone' @('-CommandId', "$prefix-banner-done")
    if ($bannerDone.status -ne 'completed') { throw "Native BannerEditor Done handler failed: $($bannerDone | ConvertTo-Json -Depth 8 -Compress)" }
    $afterBannerDone = Invoke-AgentCli 'state' @('-CommandId', "$prefix-state-after-banner-done")

    $nativeVMFieldsMatchData = (
        $first.status -eq 'completed' -and $first.data.dataType -eq 'FindingFirstBannerPieceSceneNotificationItem' -and
        [string]$first.data.titleText -eq [string]$seed.data.titleText -and
        [bool]$first.data.affirmativeButtonShown -eq $false -and
        [bool]$first.data.negativeButtonShown -eq $false -and
        [bool]$first.data.pauseActiveState -eq $true -and
        [string]$first.data.continuationKind -eq 'storymode-clan-name-setup'
    )
    $repeatedReadStable = (
        $second.status -eq 'completed' -and $second.data.hasActiveNotification -and $second.data.isReady -and
        [string]$first.data.titleText -eq [string]$second.data.titleText -and
        [bool]$second.data.canContinue -eq $true
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
        NativeSceneNotificationBecameActiveAndReady = [bool]($first.data.hasActiveNotification -and $first.data.isShown -and $first.data.isReady)
        NativeSceneNotificationVMFieldsMatchData = [bool]$nativeVMFieldsMatchData
        BannerNotificationWithExpectedNativeClanNameCallbackIsPreciselyAllowed = [bool]($first.data.canContinue -and $first.data.continuationKind -eq 'storymode-clan-name-setup' -and -not $first.data.affirmativeButtonShown -and -not $first.data.negativeButtonShown)
        RepeatedReadDoesNotDismissAndActiveTimeIsPaused = [bool]($repeatedReadStable -and $campaignUnchangedDuringReads)
        ActualEngineFrameCaptured = [bool]$frameExists
        NativeCloseHandlerDismissesCurrentCard = [bool]($continue.status -eq 'completed' -and $continue.data.nativeHandler -eq 'SceneNotificationVM.ExecuteClose' -and -not $afterClose.state.context.sceneNotification.hasActiveNotification)
        NativeCloseHandlerOpensClanNameTextInquiry = [bool]([string]$continue.data.followUpInquiry.kind -eq 'StoryModeClanNameTextInquiry' -and [string]$afterClose.state.context.inquiry.kind -eq 'StoryModeClanNameTextInquiry')
        CurrentNativeNameAcceptedThroughTextQueryVM = [bool]($submitName.data.nativeViewModelHandler -eq 'TextQueryPopUpVM.ExecuteAffirmativeAction' -and [string]$submitName.data.clanNameAfter -eq $clanName)
        NativeBannerEditorFrameCaptured = [bool]($bannerCapture.status -eq 'completed' -and $bannerFrameExists)
        NativeBannerEditorDoneHandlerReturnedToMap = [bool]($bannerDone.data.nativeHandler -eq 'BannerEditorVM.ExecuteDone' -and $afterBannerDone.state.context.gameState -eq 'MapState')
        FollowUpStealthTutorialPromptObserved = [bool]([string]$afterBannerDone.state.context.inquiry.storyModeStartupKind -eq 'stealth-tutorial-start')
        TimeModeUnchangedByCloseHandler = [bool]([string]$afterClose.state.context.timeControlMode -eq [string]$continue.data.timeControlModeAfter)
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
        Continue = $continue.data
        AfterClose = [ordered]@{ CampaignDay = $afterClose.state.campaignDay; TimeControlMode = $afterClose.state.context.timeControlMode; SceneNotificationActive = $afterClose.state.context.sceneNotification.hasActiveNotification }
        ClanNameSubmission = $submitName.data
        BannerEditor = $bannerEditorState.state.context.bannerEditor
        BannerEditorFrame = $bannerFramePath
        BannerEditorFrameBytes = if ($bannerFrameExists) { (Get-Item -LiteralPath $bannerFramePath).Length } else { 0 }
        BannerDone = $bannerDone.data
        AfterBannerDone = [ordered]@{ GameState = $afterBannerDone.state.context.gameState; Inquiry = $afterBannerDone.state.context.inquiry }
        Assertions = $assertions
        FailedAssertions = $failedAssertions
        FixtureHashBefore = $fixtureHashBefore
        FixtureHashAfter = $fixtureHashAfter
        ProcessStopped = [bool]$stop.processStopped
        Passed = ($failedAssertions.Count -eq 0)
    }
    $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    $result | ConvertTo-Json -Depth 12
    if (-not $result.Passed) { throw 'Native SceneNotification close-to-clan-name transition regression failed.' }
}
finally {
    if (Test-Path -LiteralPath $sessionPath) {
        try { Invoke-AgentCli 'stop' @('-CommandId', "$prefix-cleanup") 30 | Out-Null } catch { }
    }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
