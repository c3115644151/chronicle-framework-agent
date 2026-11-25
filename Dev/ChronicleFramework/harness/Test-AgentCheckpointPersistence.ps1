#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$env:CHRONICLE_HARNESS_MODE = 'visual-capture'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$saveRoot = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\Game Saves'
$sourceSavePath = Join-Path $saveRoot ($LoadSaveName + '.sav')
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$prefix = 'checkpoint-persistence-' + [Guid]::NewGuid().ToString('N')
$checkpointSaveName = 'ChronicleCheckpoint-' + [Guid]::NewGuid().ToString('N')
$checkpointSavePath = Join-Path $saveRoot ($checkpointSaveName + '.sav')
$checkpointBakPath = $checkpointSavePath + '.bak'
$fixtureHashBefore = (Get-FileHash -LiteralPath $sourceSavePath -Algorithm SHA256).Hash
$sessionStarted = $false
$cleanup = $null

if (Get-Process -Name Bannerlord* -ErrorAction SilentlyContinue) { throw 'Refusing to start Campaign checkpoint persistence while Bannerlord is already running.' }
if (-not (Test-Path -LiteralPath $sourceSavePath -PathType Leaf)) { throw "Disposable checkpoint source save not found: $sourceSavePath" }
if (Test-Path -LiteralPath $checkpointSavePath -PathType Leaf) { throw 'Checkpoint test save name unexpectedly already exists.' }
if (-not $env:CHRONICLE_HARNESS_TEMP -or -not (Test-Path -LiteralPath $env:CHRONICLE_HARNESS_TEMP -PathType Container)) { throw 'Checkpoint persistence requires an active Harness TestResults temp directory.' }
$runDirectory = Split-Path -Parent $env:CHRONICLE_HARNESS_TEMP

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $output = & $HarnessPowerShell -NoProfile -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

function Capture-CheckpointFrame([string]$Label) {
    $tempFrame = Join-Path $env:CHRONICLE_HARNESS_TEMP ($Label + '.bmp')
    $evidenceFrame = Join-Path $runDirectory ($Label + '.bmp')
    Remove-Item -LiteralPath $tempFrame -Force -ErrorAction SilentlyContinue
    $receipt = Invoke-AgentCli 'captureFrame' @('-OutputPath', $tempFrame, '-CommandId', ($prefix + '-' + $Label)) 20
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path -LiteralPath $tempFrame) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
    if ($receipt.status -ne 'completed' -or -not (Test-Path -LiteralPath $tempFrame) -or (Get-Item -LiteralPath $tempFrame).Length -lt 4096) { throw "Native frame '$Label' was not captured." }
    Move-Item -LiteralPath $tempFrame -Destination $evidenceFrame -Force
    return $evidenceFrame
}

try {
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $sessionStarted = $true
    $before = Invoke-AgentCli 'state' @('-CommandId', "$prefix-before")
    if ($before.state.context.gameState -ne 'MapState' -or $before.state.context.encounterActive) { throw 'Checkpoint fixture must begin in an unobstructed Campaign Map.' }
    $targetQuery = Invoke-AgentCli 'mapSettlementTargets' @('-CommandId', "$prefix-targets")
    $currentSettlementId = [string]$before.state.location.currentSettlementId
    $candidate = @($targetQuery.data.mapSettlementTargets | Where-Object { [string]$_.id -cne $currentSettlementId -and [double]$_.distance -gt 1.0 -and -not $_.hostile -and -not $_.underSiege -and $_.type -ne 'hideout' } | Sort-Object distance | Select-Object -First 1)
    if ($candidate.Count -ne 1) { throw 'No safe observed Settlement target exists for the Native move checkpoint fixture.' }
    $move = Invoke-AgentCli 'move' @('-SettlementId', [string]$candidate[0].id, '-CommandId', "$prefix-move")
    if ($move.status -ne 'completed' -or [string]$move.state.location.targetSettlementId -cne [string]$candidate[0].id) { throw 'Native movement receipt did not confirm the chosen settlement target.' }
    $checkpointReadBefore = Invoke-AgentCli 'agentCheckpointGet' @('-CommandId', "$prefix-checkpoint-read-before")
    if ($checkpointReadBefore.status -ne 'completed' -or [string]::IsNullOrWhiteSpace([string]$checkpointReadBefore.data.campaignInstanceId) -or -not [string]::IsNullOrWhiteSpace([string]$checkpointReadBefore.data.checkpointBase64)) { throw 'Expected an empty initial Agent checkpoint with a Campaign-scoped identity.' }
    $campaignInstanceId = [string]$checkpointReadBefore.data.campaignInstanceId
    $goal = 'Recruit one affordable volunteer from a current safe settlement using its enabled native recruit_volunteers option.'
    $checkpoint = [ordered]@{
        schemaVersion = 1
        campaignInstanceId = $campaignInstanceId
        taskId = [Guid]::NewGuid().ToString('N')
        goal = $goal
        status = 'active'
        lastActionReceipt = [ordered]@{
            protocolVersion = [int]$move.protocolVersion
            commandId = [string]$move.commandId
            action = [string]$move.action
            status = [string]$move.status
            campaignDay = [double]$move.campaignDay
            state = [ordered]@{
                campaignDay = [double]$move.state.campaignDay
                location = [ordered]@{
                    x = [double]$move.state.location.x
                    y = [double]$move.state.location.y
                    currentSettlementId = $move.state.location.currentSettlementId
                    targetSettlementId = [string]$move.state.location.targetSettlementId
                    targetPartyId = $move.state.location.targetPartyId
                    targetPosition = $move.state.location.targetPosition
                }
                party = [ordered]@{
                    id = $move.state.party.id
                    members = [int]$move.state.party.members
                    healthy = [int]$move.state.party.healthy
                    wounded = [int]$move.state.party.wounded
                    prisoners = [int]$move.state.party.prisoners
                    speed = [double]$move.state.party.speed
                    isMoving = [bool]$move.state.party.isMoving
                    defaultBehavior = [string]$move.state.party.defaultBehavior
                }
                context = [ordered]@{
                    gameState = [string]$move.state.context.gameState
                    menuId = $move.state.context.menuId
                    timeControlMode = [string]$move.state.context.timeControlMode
                    encounterActive = [bool]$move.state.context.encounterActive
                }
            }
        }
        lastObservedSummary = [ordered]@{
            campaignDay = [double]$move.campaignDay
            currentSettlementId = $move.state.location.currentSettlementId
            targetSettlementId = [string]$move.state.location.targetSettlementId
            isMoving = [bool]$move.state.party.isMoving
            members = [int]$move.state.party.members
            gold = [int]$move.state.economy.gold
            menuId = $move.state.context.menuId
        }
        lastStopReason = $null
        updatedUtc = [DateTime]::UtcNow.ToString('O')
    }
    $checkpointJson = $checkpoint | ConvertTo-Json -Depth 16 -Compress
    $checkpointBase64 = [Convert]::ToBase64String([Text.UTF8Encoding]::new($false).GetBytes($checkpointJson))
    $checkpointWrite = Invoke-AgentCli 'agentCheckpointSet' @('-CheckpointBase64', $checkpointBase64, '-CommandId', "$prefix-checkpoint-write")
    if ($checkpointWrite.status -ne 'completed' -or [string]$checkpointWrite.data.campaignInstanceId -cne $campaignInstanceId) { throw 'Native Campaign did not accept a matching Agent checkpoint.' }
    $beforeSaveFrame = Capture-CheckpointFrame 'CheckpointEngine-before-save'
    $save = Invoke-AgentCli 'save' @('-SaveName', $checkpointSaveName, '-CommandId', "$prefix-save") $TimeoutSeconds
    if ($save.status -ne 'completed') { throw 'Native Campaign save did not complete.' }
    $savedCheckpoint = Invoke-AgentCli 'agentCheckpointGet' @('-CommandId', "$prefix-checkpoint-read-after-save")
    $savedCheckpointJson = [Text.UTF8Encoding]::new($false, $true).GetString([Convert]::FromBase64String([string]$savedCheckpoint.data.checkpointBase64))
    if ([string]$savedCheckpoint.data.campaignInstanceId -cne $campaignInstanceId -or [string]($savedCheckpointJson | ConvertFrom-Json).goal -cne $goal) { throw 'Saved Native Campaign checkpoint did not round-trip its identity and goal.' }
    $stopBeforeLoad = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-stop-before-load")
    $sessionStarted = $false
    if (-not $stopBeforeLoad.processStopped -or (Get-Process -Name Bannerlord* -ErrorAction SilentlyContinue)) { throw 'First Bannerlord/Agent runtime was not stopped before save reload.' }

    $restart = Invoke-AgentCli 'load' @('-SaveName', $checkpointSaveName)
    $sessionStarted = $true
    $afterLoad = Invoke-AgentCli 'state' @('-CommandId', "$prefix-after-load")
    $checkpointReadAfterLoad = Invoke-AgentCli 'agentCheckpointGet' @('-CommandId', "$prefix-checkpoint-read-after-load")
    if ($checkpointReadAfterLoad.status -ne 'completed' -or [string]$checkpointReadAfterLoad.data.campaignInstanceId -cne $campaignInstanceId) { throw 'Campaign identity changed across Native save/load.' }
    $restoredCheckpointJson = [Text.UTF8Encoding]::new($false, $true).GetString([Convert]::FromBase64String([string]$checkpointReadAfterLoad.data.checkpointBase64))
    $restoredCheckpoint = $restoredCheckpointJson | ConvertFrom-Json
    $restoredMove = $restoredCheckpoint.lastActionReceipt
    $moveTargetRestored = ([string]$restoredMove.action -ceq 'move' -and [string]$restoredMove.status -ceq 'completed' -and [string]$restoredMove.state.location.targetSettlementId -ceq [string]$candidate[0].id)
    $loadedWorldStillMatchesMove = ([string]$afterLoad.state.location.currentSettlementId -ceq [string]$candidate[0].id -or [string]$afterLoad.state.location.targetSettlementId -ceq [string]$candidate[0].id)
    $afterLoadFrame = Capture-CheckpointFrame 'CheckpointEngine-after-load'
    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-stop-after-load")
    $sessionStarted = $false
    $fixtureHashAfter = (Get-FileHash -LiteralPath $sourceSavePath -Algorithm SHA256).Hash
    $result = [ordered]@{
        ProviderKind = 'deterministic protocol-only checkpoint persistence test; not an LLM autonomy result'
        Passed = $false
        CampaignInstanceStableAcrossNativeSaveLoad = ([string]$checkpointReadAfterLoad.data.campaignInstanceId -ceq $campaignInstanceId)
        GoalRestored = ([string]$restoredCheckpoint.goal -ceq $goal)
        LastMoveReceiptRestored = $moveTargetRestored
        LoadedNativeWorldMatchesMoveTarget = $loadedWorldStillMatchesMove
        CurrentSettlementIdAfterLoad = $afterLoad.state.location.currentSettlementId
        TargetSettlementIdAfterLoad = $afterLoad.state.location.targetSettlementId
        TargetSettlementIdInCheckpoint = $restoredMove.state.location.targetSettlementId
        CheckpointStatusAfterLoad = $restoredCheckpoint.status
        SourceFixtureUnchanged = ($fixtureHashBefore -ceq $fixtureHashAfter)
        ProcessStopped = ([bool]$stop.processStopped -and -not (Get-Process -Name Bannerlord* -ErrorAction SilentlyContinue) -and -not (Test-Path -LiteralPath $sessionPath -PathType Leaf))
        DisposableSaveName = $checkpointSaveName
        BeforeSaveFramePath = $beforeSaveFrame
        AfterLoadFramePath = $afterLoadFrame
        CampaignDayBeforeMove = $before.campaignDay
        CampaignDayAfterLoad = $afterLoad.campaignDay
    }
    $result.Passed = ($result.CampaignInstanceStableAcrossNativeSaveLoad -and $result.GoalRestored -and $result.LastMoveReceiptRestored -and $result.LoadedNativeWorldMatchesMoveTarget -and $result.SourceFixtureUnchanged -and $result.ProcessStopped)
    $result | ConvertTo-Json -Depth 10
    if (-not $result.Passed) { exit 1 }
}
finally {
    if ($sessionStarted -or (Test-Path -LiteralPath $sessionPath -PathType Leaf)) { try { Invoke-AgentCli 'stop' @('-CommandId', "$prefix-final-cleanup", '-TimeoutSeconds', '15') | Out-Null } catch { } }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
    $saveRootFull = [IO.Path]::GetFullPath($saveRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    foreach ($disposablePath in @($checkpointSavePath,$checkpointBakPath)) {
        if (Test-Path -LiteralPath $disposablePath -PathType Leaf) {
            $resolvedDisposablePath = [IO.Path]::GetFullPath($disposablePath)
            if (-not $resolvedDisposablePath.StartsWith($saveRootFull, [StringComparison]::OrdinalIgnoreCase)) { throw 'Checkpoint test cleanup target escaped the Bannerlord Game Saves directory.' }
            Remove-Item -LiteralPath $resolvedDisposablePath -Force
        }
    }
}
