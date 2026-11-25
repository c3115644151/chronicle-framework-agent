#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$LoadSaveName = 'ChronicleEycDev-20261030-tyal-arena-master',
    [ValidateRange(10, 120)][int]$AgentSpawnTimeoutSeconds = 30,
    [ValidateRange(10, 60)][int]$TransitionTimeoutSeconds = 20,
    [ValidateRange(20, 180)][int]$TimeoutSeconds = 60
)

$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$documentsRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)) 'Mount and Blade II Bannerlord'
$savePath = Join-Path (Join-Path $documentsRoot 'Game Saves') "$LoadSaveName.sav"
$sessionPath = Join-Path $documentsRoot 'AgentRuns\ChronicleAgent\session.json'
$runDirectory = if ($env:CHRONICLE_HARNESS_TEMP) { Split-Path -Parent $env:CHRONICLE_HARNESS_TEMP } else { Join-Path $PSScriptRoot 'TestResults\ManualArenaMasterInteraction' }
$captureTempPath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP 'ArenaMasterConversation.bmp' } else { Join-Path $runDirectory 'ArenaMasterConversation.bmp' }
$capturePath = Join-Path $runDirectory 'ArenaMasterConversation.bmp'
$resultPath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP 'ArenaMasterInteractionResult.json' } else { Join-Path $runDirectory 'ArenaMasterInteractionResult.json' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$commandPrefix = 'arena-master-interaction-' + (Get-Date -Format 'yyyyMMddHHmmssfff')
$diagnosticStep = 'preflight'
$testStartedUtc = [DateTime]::UtcNow
$cliOutputDirectory = Join-Path $runDirectory 'Temp'
New-Item -ItemType Directory -Force -Path $cliOutputDirectory | Out-Null

if ([string]::IsNullOrWhiteSpace($env:CHRONICLE_HARNESS_TEMP)) { throw 'ArenaMaster interaction requires an isolated visual Harness evidence directory.' }
if (-not (Test-Path -LiteralPath $savePath)) { throw "ArenaMaster interaction fixture not found: $LoadSaveName" }
if (Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $attemptId = [Guid]::NewGuid().ToString('N')
    $stdoutPath = Join-Path $cliOutputDirectory "AgentCli-$Action-$attemptId.stdout.log"
    $stderrPath = Join-Path $cliOutputDirectory "AgentCli-$Action-$attemptId.stderr.log"
    $quotedArgs = @('-NoProfile','-File',$cli,$Action) + $Arguments + @('-TimeoutSeconds',[string]$effectiveTimeout,'-AsJson')
    $argumentLine = ($quotedArgs | ForEach-Object {
        $value = [string]$_
        if ($value -match '\s|"') { '"' + $value.Replace('"','\"') + '"' } else { $value }
    }) -join ' '
    $cliProcess = Start-Process -FilePath $HarnessPowerShell -ArgumentList $argumentLine -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
    $wallTimeoutSeconds = [Math]::Max(300, $effectiveTimeout + 45)
    if (-not $cliProcess.WaitForExit($wallTimeoutSeconds * 1000)) {
        Stop-Process -Id $cliProcess.Id -Force -ErrorAction SilentlyContinue
        throw "Agent CLI '$Action' exceeded its $wallTimeoutSeconds-second wall timeout; stdout=$stdoutPath; stderr=$stderrPath."
    }
    $cliProcess.WaitForExit()
    $cliProcess.Refresh()
    $output = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw -Encoding UTF8 } else { '' }
    $errorOutput = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw -Encoding UTF8 } else { '' }
    $cliExitCode = $cliProcess.ExitCode
    if ($null -ne $cliExitCode -and [int]$cliExitCode -ne 0) { throw "Agent CLI '$Action' failed (exit $cliExitCode); stdout=$stdoutPath; stderr=$stderrPath; error=$errorOutput" }
    try { $result = $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON; stdout=$stdoutPath; stderr=$stderrPath; error=$errorOutput" }
    if ([string]$result.action -ne $Action -or [string]$result.status -ne 'completed') {
        throw "Agent CLI '$Action' did not return a completed result (action=$($result.action), status=$($result.status)); stdout=$stdoutPath; stderr=$stderrPath; error=$errorOutput"
    }
    return $result
}

try {
    $diagnosticStep = 'load disposable Tyal Campaign fixture'
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName, '-IncludeChronicleFramework')
    $initial = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-initial")
    if ($initial.state.context.gameState -ne 'MapState' -or $initial.state.location.currentSettlementId -ne 'town_S5' -or $initial.state.context.menuId -ne 'town') {
        throw "ArenaMaster fixture must start at the original Tyal Town map; got $($initial.state.context.gameState)/$($initial.state.location.currentSettlementId)/$($initial.state.context.menuId)."
    }
    if ([string]$initial.timeControlMode -ne 'Stop') { throw 'Arena entry fixture must start with the original Campaign clock stopped.' }

    $diagnosticStep = 'enter the original Tyal arena through Town menus'
    $arenaMenu = Invoke-AgentCli 'menuSelect' @('-MenuId', 'town', '-OptionId', 'town_arena', '-CommandId', "$commandPrefix-arena-menu")
    if ($arenaMenu.state.context.menuId -ne 'town_arena') { throw 'Native Town option did not open the original Arena menu.' }
    $enter = Invoke-AgentCli 'menuSelect' @('-MenuId', 'town_arena', '-OptionId', 'town_enter_arena', '-CommandId', "$commandPrefix-enter-arena")
    if ($enter.state.context.gameState -ne 'MissionState' -or $enter.state.mission.sceneName -ne 'arena_sturgia_a') {
        throw "Native Tyal Arena did not start its friendly Arena Mission; got $($enter.state.context.gameState)/$($enter.state.mission.sceneName)."
    }

    $diagnosticStep = 'observe the current Native ArenaMaster through standard state'
    $deadline = [DateTime]::UtcNow.AddSeconds($AgentSpawnTimeoutSeconds)
    $observed = $null
    $arenaMaster = @()
    $nativeConversationReadyAtFirstObservation = $null
    while ([DateTime]::UtcNow -lt $deadline) {
        $observed = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-observe-$([Guid]::NewGuid().ToString('N'))") 20
        if ($null -eq $nativeConversationReadyAtFirstObservation) { $nativeConversationReadyAtFirstObservation = [bool]$observed.state.mission.nativeConversationReady }
        $arenaMaster = @($observed.state.mission.nearbySceneAgents | Where-Object {
            $_.occupation -eq 'ArenaMaster' -and $_.characterId -eq 'tournament_master_sturgia' -and $_.isInteractable
        })
        if ($arenaMaster.Count -gt 0 -and [bool]$observed.state.mission.nativeConversationReady) { break }
        if ($observed.state.context.gameState -ne 'MissionState' -or $observed.state.mission.sceneName -ne 'arena_sturgia_a') {
            throw 'The Native Arena Mission changed before its Tyal ArenaMaster became observable.'
        }
        Start-Sleep -Milliseconds 500
    }
    if (-not $observed -or $arenaMaster.Count -ne 1) {
        throw "Expected one current interactable Sturgian ArenaMaster in state.mission.nearbySceneAgents; found $($arenaMaster.Count), nativeConversationReady=$($observed.state.mission.nativeConversationReady)."
    }
    if (-not [bool]$observed.state.mission.nativeConversationReady) {
        throw 'The original MissionConversationLogic has not completed its Native rendering initialization.'
    }
    $target = $arenaMaster[0]
    if ([int]$target.agentIndex -lt 0) { throw 'Current ArenaMaster observation did not include a valid Native AgentIndex.' }

    $diagnosticStep = 'interact through the original Agent.OnUse path'
    $interaction = Invoke-AgentCli 'missionInteract' @('-AgentIndex', [string]$target.agentIndex, '-CommandId', "$commandPrefix-interact")
    $afterInteraction = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-after-interaction")
    $conversation = $afterInteraction.state.context.conversation
    $conversationVerified = (
        $interaction.status -eq 'completed' -and [bool]$interaction.data.conversationStarted -and
        [string]$interaction.data.nativeEntry -eq 'Agent.OnUse' -and
        [string]$interaction.data.targetCharacterId -eq 'tournament_master_sturgia' -and
        [string]$conversation.characterId -eq 'tournament_master_sturgia'
    )
    $clockUnchanged = (
        [double]$observed.campaignDay -eq [double]$afterInteraction.campaignDay -and
        [string]$observed.timeControlMode -eq [string]$afterInteraction.timeControlMode -and
        [string]$afterInteraction.timeControlMode -eq 'Stop'
    )
    if (-not $conversationVerified) { throw 'Native ArenaMaster interaction did not start the currently observed Sturgian ArenaMaster conversation.' }
    if (-not $clockUnchanged) { throw 'Talking to the ArenaMaster changed Campaign time or time mode.' }

    $diagnosticStep = 'capture the Native ArenaMaster conversation screen'
    $capture = Invoke-AgentCli 'captureFrame' @('-OutputPath', $captureTempPath, '-CommandId', "$commandPrefix-frame") 30
    $captureDeadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path -LiteralPath $captureTempPath) -and [DateTime]::UtcNow -lt $captureDeadline) { Start-Sleep -Milliseconds 100 }
    if ($capture.status -ne 'completed' -or -not (Test-Path -LiteralPath $captureTempPath) -or (Get-Item -LiteralPath $captureTempPath).Length -lt 4096) {
        throw 'Engine-native screenshot of the ArenaMaster conversation was not produced.'
    }
    Move-Item -LiteralPath $captureTempPath -Destination $capturePath -Force

    $diagnosticStep = 'close conversation and return by the original Arena Leave Area route'
    $leaveDialogue = @($conversation.options | Where-Object { $_.id -eq 'arena_master_leave' -and $_.clickable })
    if ($leaveDialogue.Count -ne 1) { throw 'The currently visible Native ArenaMaster dialogue did not expose its original leave option.' }
    $dialogueLeave = Invoke-AgentCli 'dialogueSelect' @('-OptionId', 'arena_master_leave', '-CommandId', "$commandPrefix-dialogue-leave")
    if ($dialogueLeave.status -ne 'completed') { throw 'Native ArenaMaster dialogue leave option was not accepted.' }
    $missionLeave = Invoke-AgentCli 'missionLeave' @('-CommandId', "$commandPrefix-mission-leave") 30
    $mapDeadline = [DateTime]::UtcNow.AddSeconds($TransitionTimeoutSeconds)
    $afterLeave = $null
    while ([DateTime]::UtcNow -lt $mapDeadline) {
        $afterLeave = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-map-$([Guid]::NewGuid().ToString('N'))") 20
        if ($afterLeave.state.context.gameState -eq 'MapState' -and $afterLeave.state.context.menuId -eq 'town_arena') { break }
        if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'Game process exited before Native Arena leave returned to Map.' }
        Start-Sleep -Milliseconds 500
    }
    if (-not $afterLeave -or $afterLeave.state.context.gameState -ne 'MapState' -or $afterLeave.state.context.menuId -ne 'town_arena') {
        throw 'Native Tyal Arena Leave Area did not return to the original town_arena menu within the transition window.'
    }

    $diagnosticStep = 'stop and verify the disposable source fixture'
    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-stop") 30
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $result = [ordered]@{
        SourceSaveName = $LoadSaveName
        SourceSaveHashBefore = $fixtureHashBefore
        SourceSaveHashAfter = $fixtureHashAfter
        InitialState = [ordered]@{ Location = $initial.state.location.currentSettlementId; CampaignDay = $initial.campaignDay; Gold = $initial.state.economy.gold; Renown = $initial.state.economy.renown; PartyMembers = $initial.state.party.members }
        ArenaMission = [ordered]@{ Scene = $enter.state.mission.sceneName; Mode = $enter.state.mission.mode; CurrentNativeArenaMaster = $target }
        NativeConversationReadyAtFirstMissionObservation = [bool]$nativeConversationReadyAtFirstObservation
        InteractionReceipt = $interaction.data
        Conversation = $conversation
        CampaignDayAfterInteraction = $afterInteraction.campaignDay
        TimeControlAfterInteraction = $afterInteraction.timeControlMode
        CampaignClockUnchanged = [bool]$clockUnchanged
        NativeDialogueLeave = $dialogueLeave.status
        NativeMissionLeave = $missionLeave.status
        ReturnedToMapArenaMenu = ($afterLeave.state.context.gameState -eq 'MapState' -and $afterLeave.state.context.menuId -eq 'town_arena')
        EngineScreenshot = $capturePath
        FixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = [bool]$stop.processStopped
    }
    $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    $assertions = [ordered]@{
        NativeTyalArenaMission = ($enter.state.context.gameState -eq 'MissionState' -and $enter.state.mission.sceneName -eq 'arena_sturgia_a')
        CurrentNativeArenaMasterFromStandardState = ([string]$target.characterId -eq 'tournament_master_sturgia' -and [string]$target.occupation -eq 'ArenaMaster' -and [bool]$target.isInteractable)
        NativeConversationReadyBeforeInteraction = ([bool]$observed.state.mission.nativeConversationReady)
        NativeAgentOnUseConversation = [bool]$conversationVerified
        CampaignClockUnchanged = [bool]$clockUnchanged
        EngineScreenshotCaptured = (Test-Path -LiteralPath $capturePath)
        OriginalLeaveReturnedToMap = [bool]$result.ReturnedToMapArenaMenu
        FixtureUnchanged = [bool]$result.FixtureUnchanged
        ProcessStopped = [bool]$result.ProcessStopped
    }
    $failedAssertions = @($assertions.Keys | Where-Object { -not [bool]$assertions[$_] })
    $result | Add-Member -NotePropertyName Assertions -NotePropertyValue $assertions
    $result | Add-Member -NotePropertyName FailedAssertions -NotePropertyValue $failedAssertions
    $result | Add-Member -NotePropertyName Passed -NotePropertyValue ($failedAssertions.Count -eq 0)
    $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    $result | ConvertTo-Json -Depth 10
    if ($failedAssertions.Count -gt 0) { throw 'Native Sturgian ArenaMaster interaction regression failed.' }
}
catch {
    $failurePath = Join-Path (Split-Path -Parent $resultPath) 'ArenaMasterInteractionFailure.json'
    $failureReceipt = [ordered]@{
        TimestampUtc = [DateTime]::UtcNow.ToString('O')
        DiagnosticStep = $diagnosticStep
        ExceptionType = $_.Exception.GetType().FullName
        ErrorMessage = $_.Exception.Message
        LastNativeConversationReady = if ($observed -and $observed.state.mission) { [bool]$observed.state.mission.nativeConversationReady } else { $null }
        LastObservedArenaMasterCount = @($arenaMaster).Count
        SessionPresentBeforeCleanup = (Test-Path -LiteralPath $sessionPath)
        BannerlordProcessesBeforeCleanup = @(Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue | ForEach-Object { [ordered]@{ Id = $_.Id; ProcessName = $_.ProcessName; Responding = $_.Responding } })
        EngineConfigBackupPresentBeforeCleanup = Test-Path -LiteralPath (Join-Path $documentsRoot 'AgentRuns\ChronicleAgent\engine_config.chronicle-backup')
        FixtureUnchanged = ((Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash -eq $fixtureHashBefore)
    }
    $failureReceipt | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $failurePath -Encoding UTF8
    throw "ArenaMaster interaction test failed during '$diagnosticStep': $($_.Exception.Message)"
}
finally {
    if (Test-Path $sessionPath) {
        try { Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-cleanup") 20 | Out-Null } catch { }
    }
    $testOwnedGameProcesses = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -like 'Bannerlord*' -and $_.CommandLine -like "*/continuesave $LoadSaveName *" -and
        (([DateTime]$_.CreationDate).ToUniversalTime() -ge $testStartedUtc)
    })
    foreach ($ownedProcess in $testOwnedGameProcesses) { Stop-Process -Id ([int]$ownedProcess.ProcessId) -Force -ErrorAction SilentlyContinue }
    $cleanupDeadline = [DateTime]::UtcNow.AddSeconds(15)
    while ((Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue) -and [DateTime]::UtcNow -lt $cleanupDeadline) { Start-Sleep -Milliseconds 250 }
    if (-not (Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue)) {
        try { Invoke-AgentCli 'recoverTestConfig' @() 20 | Out-Null } catch { }
    }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
