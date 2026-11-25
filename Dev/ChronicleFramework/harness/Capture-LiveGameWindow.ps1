#Requires -Version 7.0
[CmdletBinding()]
param(
    [int]$ProcessId = 0,
    [ValidateRange(2, 60)][int]$DurationSeconds = 8,
    [ValidateRange(100, 2000)][int]$SampleIntervalMilliseconds = 500,
    [ValidateRange(5, 30)][int]$FrameRate = 15,
    [string]$EvidenceDirectory,
    [string]$Name = 'LiveGameWindow',
    [string]$ReadySignalPath
)

$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$videoCaptureLibrary = Join-Path $PSScriptRoot 'HarnessVideoCapture.ps1'
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
if (-not (Test-Path -LiteralPath $cli -PathType Leaf)) { throw "Agent CLI not found: $cli" }
if (-not (Test-Path -LiteralPath $sessionPath -PathType Leaf)) { throw "No active Chronicle game session: $sessionPath" }
$session = Get-Content -LiteralPath $sessionPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($ProcessId -le 0) { $ProcessId = [int]$session.processId }
if ($ProcessId -ne [int]$session.processId) { throw "Requested process $ProcessId does not match active Chronicle session $($session.processId)." }
$gameProcess = Get-Process -Id $ProcessId -ErrorAction Stop
if ($gameProcess.ProcessName -notmatch '^Bannerlord') { throw "Target process is not Bannerlord: $($gameProcess.ProcessName)." }

if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
    $runStamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
    $EvidenceDirectory = Join-Path (Split-Path -Parent $PSScriptRoot) "TestResults\$runStamp-live-window-capture"
}
$EvidenceDirectory = [IO.Path]::GetFullPath($EvidenceDirectory)
New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null
if ($Name -notmatch '^[A-Za-z0-9_-]{1,64}$') { throw 'Name must contain only letters, numbers, underscore or hyphen.' }
$videoPath = Join-Path $EvidenceDirectory ($Name + '.mp4')
$contactPath = Join-Path $EvidenceDirectory ($Name + '-contact.jpg')
$eventPath = Join-Path $EvidenceDirectory ($Name + '-events.jsonl')
$timelinePath = Join-Path $EvidenceDirectory ($Name + '-timeline-index.json')
$receiptPath = Join-Path $EvidenceDirectory ($Name + '-receipt.json')
if ($ReadySignalPath) { $ReadySignalPath = [IO.Path]::GetFullPath($ReadySignalPath) }
Remove-Item -LiteralPath $videoPath,$contactPath,$eventPath,$timelinePath,$receiptPath -Force -ErrorAction SilentlyContinue

. $videoCaptureLibrary
$capture = $null
$samples = 0
$totalSamples = 0
$failures = [Collections.Generic.List[string]]::new()
$lastFingerprint = $null
$stopwatch = [Diagnostics.Stopwatch]::StartNew()

function Add-CaptureObservation([string]$EventName, $Snapshot, $StartedTicks, $Frequency) {
    $nowTicks = [Diagnostics.Stopwatch]::GetTimestamp()
    $state = if ($Snapshot -and $Snapshot.state) { $Snapshot.state } else { $null }
    $context = if ($state) { $state.context } else { $null }
    $mission = if ($state) { $state.mission } else { $null }
    $conversation = if ($context) { $context.conversation } else { $null }
    $party = if ($state) { $state.party } else { $null }
    $fingerprintObject = [ordered]@{
        gameState = [string]$context.gameState
        menuId = [string]$context.menuId
        mode = [string]$context.timeControlMode
        missionMode = [string]$mission.mode
        sceneName = [string]$mission.sceneName
        conversationCharacter = [string]$conversation.characterId
        conversationText = [string]$conversation.sentenceText
        conversationOptions = @($conversation.options | ForEach-Object { [string]$_.id + ':' + [string]$_.textId })
        conversationOptionCount = @($conversation.options).Count
        inquiry = [bool]$context.inquiryOpen
        inquiryTitle = [string]$context.inquiry.title
        inquiryOptionCount = @($context.inquiry.options).Count
        escape = [bool]$context.escapeMenuOpen
        encounter = [bool]$context.encounterActive
        incidentActive = [bool]$context.mapIncident.active
        sceneNotification = [bool]$context.sceneNotification.hasActiveNotification
        visibleMenuOptionIds = @($state.availableMenuOptions | ForEach-Object { [string]$_.id })
        partyMembers = $party.members
        partyPrisoners = $party.prisoners
        activeQuestIds = @($state.quests | ForEach-Object { [string]$_.id })
        hostilePartyCount = $state.danger.hostilePartyCount
        nearbyPartyIds = @($state.nearbyParties | ForEach-Object { [string]$_.id })
    }
    $row = [ordered]@{
        event = $EventName
        utc = (Get-Date).ToUniversalTime().ToString('O')
        stopwatchTicks = $nowTicks
        offsetMilliseconds = if ($StartedTicks -gt 0) { [Math]::Round(($nowTicks - $StartedTicks) * 1000.0 / $Frequency, 2) } else { 0 }
        commandId = if ($Snapshot) { [string]$Snapshot.commandId } else { $null }
        action = if ($Snapshot) { [string]$Snapshot.action } else { 'observe' }
        gameState = [string]$context.gameState
        menuId = [string]$context.menuId
        partyScreenMode = if ($state.partyScreen) { [string]$state.partyScreen.mode } else { $null }
        inventoryMode = if ($state.inventoryScreen) { [string]$state.inventoryScreen.mode } else { $null }
        campaignDay = if ($Snapshot) { $Snapshot.campaignDay } else { $null }
        stateFingerprint = $fingerprintObject | ConvertTo-Json -Compress -Depth 5
    }
    Add-Content -LiteralPath $eventPath -Value ($row | ConvertTo-Json -Compress -Depth 7) -Encoding UTF8
    return [string]$row.stateFingerprint
}

try {
    $capture = Start-ChronicleWindowVideoCapture -ProcessId $ProcessId -OutputPath $videoPath -FrameRate $FrameRate -DurationLimitSeconds ($DurationSeconds + 5)
    [void](Add-CaptureObservation 'capture-start' $null $capture.StartedTicks $capture.StopwatchFrequency)
    $deadline = [Diagnostics.Stopwatch]::GetTimestamp() + [long]($DurationSeconds * [Diagnostics.Stopwatch]::Frequency)
    while ([Diagnostics.Stopwatch]::GetTimestamp() -lt $deadline) {
        if (-not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) { throw "Bannerlord process $ProcessId exited during capture." }
        try {
            $snapshot = & $cli state -CommandId ('capture-state-' + [Guid]::NewGuid().ToString('N')) -TimeoutSeconds 10 -AsJson | ConvertFrom-Json
            $totalSamples++
            $fingerprint = Add-CaptureObservation 'state-sample' $snapshot $capture.StartedTicks $capture.StopwatchFrequency
            if ($fingerprint -ne $lastFingerprint) { $samples++ ; $lastFingerprint = $fingerprint }
            if ($ReadySignalPath -and -not (Test-Path -LiteralPath $ReadySignalPath)) {
                $ready = [ordered]@{ processId = $ProcessId; captureStartedUtc = $capture.StartedUtc; firstStateSampleUtc = (Get-Date).ToUniversalTime().ToString('O'); frameRate = $FrameRate; windowTitle = $capture.WindowTitle }
                New-Item -ItemType Directory -Path (Split-Path -Parent $ReadySignalPath) -Force | Out-Null
                $ready | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $ReadySignalPath -Encoding UTF8
            }
        }
        catch { $failures.Add("state-sample: $($_.Exception.Message)") }
        Start-Sleep -Milliseconds $SampleIntervalMilliseconds
    }
    try {
        $finalSnapshot = & $cli state -CommandId ('capture-final-' + [Guid]::NewGuid().ToString('N')) -TimeoutSeconds 10 -AsJson | ConvertFrom-Json
        $totalSamples++
        [void](Add-CaptureObservation 'capture-end' $finalSnapshot $capture.StartedTicks $capture.StopwatchFrequency)
    }
    catch { $failures.Add("final-state-sample: $($_.Exception.Message)") }
    $result = Stop-ChronicleWindowVideoCapture -Capture $capture -ContactSheetPath $contactPath -EventTracePath $eventPath
    $capture = $null
    $receipt = [ordered]@{
        passed = [bool]$result.Passed
        provider = [string]$result.Provider
        processId = $ProcessId
        windowTitle = [string]$result.WindowTitle
        frameRate = [int]$result.FrameRateTarget
        frameCount = [int]$result.FrameCount
        durationSeconds = [double]$result.DurationSeconds
        frameCoverageRatio = [double]$result.FrameCoverageRatio
        stateSamplesWithDistinctFingerprint = $samples
        totalStateSamples = $totalSamples
        elapsedSeconds = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 3)
        stateSampleFailures = @($failures)
        videoRetained = [bool]$result.VideoRetained
        contactSheetPath = [string]$result.ContactSheetPath
        timelineIndexPath = [string]$result.TimelineIndexPath
        timelineFrameCount = [int]$result.TimelineFrameCount
        temporarySourceVideoRemoved = [bool]$result.VideoRemovedAfterEvidence
    }
    $receipt | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
    [pscustomobject]$receipt
}
catch {
    if ($capture -and $capture.Process -and -not $capture.Process.HasExited) {
        try { $capture.Process.Kill(); $capture.Process.WaitForExit() } catch { }
    }
    $failureReceipt = [ordered]@{
        passed = $false
        processId = $ProcessId
        failure = $_.Exception.Message
        partialVideoRetained = Test-Path -LiteralPath $videoPath -PathType Leaf
        partialVideoPath = if (Test-Path -LiteralPath $videoPath -PathType Leaf) { $videoPath } else { $null }
        eventPath = if (Test-Path -LiteralPath $eventPath -PathType Leaf) { $eventPath } else { $null }
    }
    $failureReceipt | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
    throw
}
finally {
    $stopwatch.Stop()
}
