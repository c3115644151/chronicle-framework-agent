#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateRange(1, 600)][int]$DurationSeconds = 30,
    [ValidateRange(100, 2000)][int]$SampleIntervalMilliseconds = 400,
    [string]$QuestId,
    [switch]$PauseOnHostile,
    [string]$EvidenceDirectory
)

$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
if (-not (Test-Path -LiteralPath $cli -PathType Leaf)) { throw "Agent CLI not found: $cli" }
if (-not (Test-Path -LiteralPath $sessionPath -PathType Leaf)) { throw "No active Chronicle game session: $sessionPath" }
$session = Get-Content -LiteralPath $sessionPath -Raw -Encoding UTF8 | ConvertFrom-Json
$gameProcessId = [int]$session.processId
if (-not (Get-Process -Id $gameProcessId -ErrorAction SilentlyContinue)) { throw "Active Chronicle game process $gameProcessId is not running." }
if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
    $runStamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
    $EvidenceDirectory = Join-Path (Split-Path -Parent $PSScriptRoot) "TestResults\$runStamp-live-campaign-observation"
}
$EvidenceDirectory = [IO.Path]::GetFullPath($EvidenceDirectory)
New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null
$tracePath = Join-Path $EvidenceDirectory 'LiveCampaignObservations.jsonl'
$receiptPath = Join-Path $EvidenceDirectory 'LiveCampaignObservationReceipt.json'
Remove-Item -LiteralPath $tracePath,$receiptPath -Force -ErrorAction SilentlyContinue

function Invoke-LiveState {
    $result = & $cli state -CommandId ('observe-' + [Guid]::NewGuid().ToString('N')) -TimeoutSeconds 10 -AsJson | ConvertFrom-Json
    if ($result.status -ne 'completed' -or [int]$result.processId -ne $gameProcessId) {
        throw "Native observation did not complete for the active game process $gameProcessId."
    }
    return $result
}

function Write-LiveSample($Snapshot, [string]$QuestStatus, $QuestProgress) {
    $state = $Snapshot.state
    $context = $state.context
    $conversation = $context.conversation
    $row = [ordered]@{
        utc = (Get-Date).ToUniversalTime().ToString('O')
        campaignDay = $Snapshot.campaignDay
        timeControlMode = [string]$Snapshot.timeControlMode
        gameState = [string]$context.gameState
        menuId = [string]$context.menuId
        isWaiting = [bool]$context.isWaiting
        encounterActive = [bool]$context.encounterActive
        conversation = if ($conversation) { [ordered]@{ characterId = [string]$conversation.characterId; text = [string]$conversation.sentenceText; optionIds = @($conversation.options | ForEach-Object { [string]$_.id }) } } else { $null }
        inquiryOpen = [bool]$context.inquiryOpen
        party = $state.party
        location = $state.location
        danger = $state.danger
        nearbyParties = $state.nearbyParties
        activeQuestIds = @($state.quests | ForEach-Object { [string]$_.id })
        targetQuestStatus = $QuestStatus
        targetQuestProgress = $QuestProgress
    }
    Add-Content -LiteralPath $tracePath -Value ($row | ConvertTo-Json -Compress -Depth 8) -Encoding UTF8
}

function Pause-ForNativeDecision($Snapshot) {
    if ([string]$Snapshot.timeControlMode -in @('Stop','FastForwardStop')) { return $null }
    return (& $cli pause -CommandId ('observe-pause-' + [Guid]::NewGuid().ToString('N')) -TimeoutSeconds 10 -AsJson | ConvertFrom-Json)
}

$startedUtc = (Get-Date).ToUniversalTime()
$deadline = $startedUtc.AddSeconds($DurationSeconds)
$sampleCount = 0
$sampleErrors = [Collections.Generic.List[string]]::new()
$stopReason = 'duration-elapsed'
$lastProgress = $null
$pauseReceipt = $null

while ([DateTime]::UtcNow -lt $deadline) {
    $snapshot = Invoke-LiveState
    $targetQuestStatus = if ($QuestId) { 'active-unverified' } else { 'not-requested' }
    $targetQuestProgress = $null
    if ($QuestId) {
        try {
            $questResult = & $cli questDetails -QuestId $QuestId -CommandId ('observe-quest-' + [Guid]::NewGuid().ToString('N')) -TimeoutSeconds 10 -AsJson | ConvertFrom-Json
            if ($questResult.status -eq 'completed' -and $questResult.data.questId -eq $QuestId) {
                $targetQuestStatus = 'active'
                $targetStage = @($questResult.data.journalStages | Where-Object { $_.hasTask -and -not $_.isLastStage }) | Select-Object -First 1
                if ($targetStage) { $targetQuestProgress = [ordered]@{ stage = [string]$targetStage.taskName; current = $targetStage.currentProgress; target = $targetStage.targetProgress; completed = [bool]$targetStage.isTaskCompleted } }
            }
            else { $targetQuestStatus = 'not-active' }
        }
        catch {
            $targetQuestStatus = 'observation-error'
            $sampleErrors.Add("questDetails: $($_.Exception.Message)")
        }
    }
    Write-LiveSample $snapshot $targetQuestStatus $targetQuestProgress
    $sampleCount++

    if ([bool]$snapshot.state.context.encounterActive) { $stopReason = 'native-encounter-active'; $pauseReceipt = Pause-ForNativeDecision $snapshot; break }
    if ([int]$snapshot.state.danger.hostilePartyCount -gt 0 -and $PauseOnHostile) {
        $stopReason = 'hostile-party-visible'
        if ($snapshot.timeControlMode -notin @('Stop','FastForwardStop')) {
            $pauseReceipt = & $cli pause -CommandId ('observe-pause-' + [Guid]::NewGuid().ToString('N')) -TimeoutSeconds 10 -AsJson | ConvertFrom-Json
        }
        break
    }
    if ($QuestId -and $targetQuestStatus -ne 'active') { $stopReason = if ($targetQuestStatus -eq 'observation-error') { 'target-quest-observation-error' } else { 'target-quest-not-active' }; $pauseReceipt = Pause-ForNativeDecision $snapshot; break }
    if ($contextConversation = $snapshot.state.context.conversation) {
        if (@($contextConversation.options).Count -gt 0) { $stopReason = 'native-conversation-choice'; $pauseReceipt = Pause-ForNativeDecision $snapshot; break }
    }
    if ([bool]$snapshot.state.context.inquiryOpen) { $stopReason = 'native-inquiry-open'; $pauseReceipt = Pause-ForNativeDecision $snapshot; break }
    if ($targetQuestProgress) {
        $progressSignature = @([string]$targetQuestProgress.stage,[string]$targetQuestProgress.current,[string]$targetQuestProgress.target) -join '|'
        if ($null -ne $lastProgress -and $progressSignature -ne $lastProgress) { $stopReason = 'quest-progress-changed'; $pauseReceipt = Pause-ForNativeDecision $snapshot; break }
        $lastProgress = $progressSignature
    }
    Start-Sleep -Milliseconds $SampleIntervalMilliseconds
}

$finalSnapshot = Invoke-LiveState
$receipt = [ordered]@{
    passed = $true
    processId = $gameProcessId
    startedUtc = $startedUtc.ToString('O')
    endedUtc = (Get-Date).ToUniversalTime().ToString('O')
    requestedDurationSeconds = $DurationSeconds
    sampleIntervalMilliseconds = $SampleIntervalMilliseconds
    sampleCount = $sampleCount
    stopReason = $stopReason
    pauseOnHostile = [bool]$PauseOnHostile
    pauseReceipt = $pauseReceipt
    targetQuestId = $QuestId
    sampleErrors = @($sampleErrors)
    finalCampaignDay = $finalSnapshot.campaignDay
    finalTimeControlMode = [string]$finalSnapshot.timeControlMode
    finalGameState = [string]$finalSnapshot.state.context.gameState
    finalActiveQuestIds = @($finalSnapshot.state.quests | ForEach-Object { [string]$_.id })
    observationPath = $tracePath
}
$receipt | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
[pscustomobject]$receipt
