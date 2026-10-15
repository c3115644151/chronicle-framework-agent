function Test-ChronicleFragmentedCaptureResilience {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$EvidencePath)

    $evidencePath = [IO.Path]::GetFullPath($EvidencePath)
    $evidenceDirectory = Split-Path -Parent $evidencePath
    New-Item -ItemType Directory -Path $evidenceDirectory -Force | Out-Null
    $nonce = [Guid]::NewGuid().ToString('N')
    $videoPath = Join-Path $evidenceDirectory ('CaptureRecoveryProbe-' + $nonce + '.mp4')
    $contactPath = Join-Path $evidenceDirectory ('CaptureRecoveryProbe-' + $nonce + '-contact.jpg')
    $probeErrorPath = Join-Path $evidenceDirectory ('CaptureRecoveryProbe-' + $nonce + '-ffprobe.stderr')
    $extractErrorPath = Join-Path $evidenceDirectory ('CaptureRecoveryProbe-' + $nonce + '-extract.stderr')
    $captureProcess = $null
    $processStarted = $false
    $errorMessage = $null
    $result = [ordered]@{
        Passed = $false
        Probe = 'fragmented-mp4-forced-interruption'
        InterruptedProcess = $false
        PartialVideoDecoded = $false
        ContactSheetExtracted = $false
        PartialBytes = 0
        DecodedFrames = 0
        PartialVideoSha256 = $null
        TemporaryArtifactsRemoved = $false
    }

    try {
        $ffmpeg = (Get-Command ffmpeg.exe -ErrorAction Stop).Source
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $ffmpeg
        $startInfo.Arguments = '-hide_banner -loglevel error -nostats -nostdin -y -f lavfi -i "testsrc2=size=320x180:rate=5" -an -c:v libx264 -preset ultrafast -crf 35 -pix_fmt yuv420p -g 5 -keyint_min 5 -fps_mode cfr -movflags +frag_keyframe+empty_moov+default_base_moof -t 86400 "' + $videoPath.Replace('"','\"') + '"'
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $captureProcess = [Diagnostics.Process]::new()
        $captureProcess.StartInfo = $startInfo
        if (-not $captureProcess.Start()) { throw 'FFmpeg fragmented-capture probe did not start.' }
        $processStarted = $true
        $stdoutTask = $captureProcess.StandardOutput.ReadToEndAsync()
        $stderrTask = $captureProcess.StandardError.ReadToEndAsync()
        Start-Sleep -Seconds 2
        $captureProcess.Refresh()
        if ($captureProcess.HasExited) {
            $exitCode = [int]$captureProcess.ExitCode
            $stderr = [string]$stderrTask.GetAwaiter().GetResult()
            throw "FFmpeg fragmented-capture probe exited before forced interruption (exit=$exitCode): $stderr"
        }
        $captureProcess.Kill()
        $captureProcess.WaitForExit()
        $result.InterruptedProcess = $true
        $result.PartialBytes = if (Test-Path -LiteralPath $videoPath -PathType Leaf) { (Get-Item -LiteralPath $videoPath).Length } else { 0 }
        if ($result.PartialBytes -lt 4096) { throw 'FFmpeg did not write a usable fragmented MP4 prefix before interruption.' }

        $ffprobe = (Get-Command ffprobe.exe -ErrorAction Stop).Source
        $probeText = & $ffprobe -v error -count_frames -select_streams v:0 -show_entries stream=codec_name,width,height,nb_read_frames -of json $videoPath 2> $probeErrorPath | Out-String
        $probeExitCode = $LASTEXITCODE
        if ($probeExitCode -ne 0) { throw 'ffprobe could not parse the interrupted fragmented MP4 prefix.' }
        $probe = $probeText | ConvertFrom-Json
        $streams = @($probe.streams)
        if ($streams.Count -ne 1 -or [int]$streams[0].nb_read_frames -lt 1) { throw 'ffprobe found no decodable frames in the interrupted fragmented MP4 prefix.' }
        $result.DecodedFrames = [int]$streams[0].nb_read_frames
        $result.PartialVideoSha256 = (Get-FileHash -LiteralPath $videoPath -Algorithm SHA256).Hash
        $result.PartialVideoDecoded = $true

        & $ffmpeg -hide_banner -loglevel error -err_detect ignore_err -y -i $videoPath -vf 'fps=0.25,scale=160:-1,tile=4x4' -frames:v 1 -q:v 3 $contactPath 2> $extractErrorPath
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $contactPath -PathType Leaf) -or (Get-Item -LiteralPath $contactPath).Length -lt 512) {
            throw 'The interrupted fragmented MP4 could not produce a reviewable keyframe sheet.'
        }
        $result.ContactSheetExtracted = $true
        $result.Passed = $true
    }
    catch {
        $errorMessage = $_.Exception.Message
    }
    finally {
        if ($processStarted -and $captureProcess -and -not $captureProcess.HasExited) { try { $captureProcess.Kill(); $captureProcess.WaitForExit() } catch { } }
        foreach ($artifact in @($videoPath,$contactPath,$probeErrorPath,$extractErrorPath)) {
            if (Test-Path -LiteralPath $artifact -PathType Leaf) { Remove-Item -LiteralPath $artifact -Force }
        }
        $remainingArtifacts = 0
        foreach ($artifact in @($videoPath,$contactPath,$probeErrorPath,$extractErrorPath)) {
            if (Test-Path -LiteralPath $artifact -PathType Leaf) { $remainingArtifacts++ }
        }
        $result.TemporaryArtifactsRemoved = $remainingArtifacts -eq 0
        if ($errorMessage) { $result.Failure = $errorMessage }
        $result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $evidencePath -Encoding UTF8
        if ($captureProcess) { $captureProcess.Dispose() }
    }

    if (-not $result.Passed) { throw "Fragmented MP4 interruption probe failed: $errorMessage" }
    [pscustomobject]$result
}

function Start-ChronicleWindowVideoCapture {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][int]$ProcessId,
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [ValidateRange(5,60)][int]$FrameRate = 30
    )

    $ffmpeg = (Get-Command ffmpeg.exe -ErrorAction Stop).Source
    $filters = & $ffmpeg -hide_banner -filters 2>&1 | Out-String
    if ($filters -notmatch '(?m)\bgfxcapture\b') { throw 'FFmpeg build does not provide the Windows Graphics Capture gfxcapture source.' }
    if (-not ('ChronicleFramework.WindowApi' -as [type])) { . (Join-Path $PSScriptRoot 'Test-WindowLayout.ps1') }
    $handle = [ChronicleFramework.WindowApi]::FindProcessWindow($ProcessId)
    if ($handle -eq [IntPtr]::Zero) { throw "No visible Bannerlord window found for process $ProcessId." }
    $titleBuffer = New-Object System.Text.StringBuilder 512
    [void][ChronicleFramework.WindowApi]::GetWindowText($handle, $titleBuffer, $titleBuffer.Capacity)
    $title = $titleBuffer.ToString()
    if ([string]::IsNullOrWhiteSpace($title) -or $title -notmatch 'Bannerlord') { throw "Target HWND did not resolve to a Bannerlord window: '$title'." }
    $hwndValue = [UInt64]$handle.ToInt64()
    $captureFilter = "gfxcapture=hwnd=${hwndValue}:max_framerate=${FrameRate}:capture_cursor=0:capture_border=0:display_border=0"
    $keyframeInterval = [Math]::Max(1, $FrameRate * 2)
    $quotedFilter = '"' + $captureFilter.Replace('"','\"') + '"'
    $quotedOutput = '"' + $OutputPath.Replace('"','\"') + '"'
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $ffmpeg
    $startInfo.Arguments = "-hide_banner -loglevel warning -y -f lavfi -i $quotedFilter -an -vf `"hwdownload,format=bgra,pad=ceil(iw/2)*2:ceil(ih/2)*2`" -c:v libx264 -preset ultrafast -crf 22 -pix_fmt yuv420p -g $keyframeInterval -keyint_min $keyframeInterval -fps_mode cfr -movflags +frag_keyframe+empty_moov+default_base_moof $quotedOutput"
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $captureRequestedUtc = (Get-Date).ToUniversalTime().ToString('O')
    $captureRequestedTicks = [Diagnostics.Stopwatch]::GetTimestamp()
    if (-not $process.Start()) { throw 'Could not start FFmpeg Windows Graphics Capture.' }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    Start-Sleep -Milliseconds 400
    if ($process.HasExited) { throw "FFmpeg gfxcapture exited during startup ($($process.ExitCode)): $($stderrTask.Result)" }
    return [pscustomobject]@{
        Process = $process
        StdoutTask = $stdoutTask
        StderrTask = $stderrTask
        ProcessId = $ProcessId
        WindowHandle = $hwndValue
        WindowTitle = $title
        FrameRate = $FrameRate
        StartedUtc = $captureRequestedUtc
        StartedTicks = $captureRequestedTicks
        StopwatchFrequency = [Diagnostics.Stopwatch]::Frequency
        OutputPath = $OutputPath
    }
}

function Stop-ChronicleWindowVideoCapture {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Capture,
        [Parameter(Mandatory = $true)][string]$ContactSheetPath,
        [Parameter(Mandatory = $true)][string]$EventTracePath,
        [switch]$KeepVideo
    )

    $process = $Capture.Process
    $stopRequestedUtc = (Get-Date).ToUniversalTime().ToString('O')
    $stopRequestedTicks = [Diagnostics.Stopwatch]::GetTimestamp()
    if ($process -and -not $process.HasExited) {
        try { $process.StandardInput.WriteLine('q'); $process.StandardInput.Flush() } catch { }
        if (-not $process.WaitForExit(8000)) {
            try { $process.Kill() } catch { }
            throw 'FFmpeg did not stop cleanly after q; the clip is not accepted.'
        }
    }
    $stoppedUtc = (Get-Date).ToUniversalTime().ToString('O')
    $stoppedTicks = [Diagnostics.Stopwatch]::GetTimestamp()
    if ($process.ExitCode -ne 0) { throw "FFmpeg gfxcapture failed ($($process.ExitCode)): $($Capture.StderrTask.Result)" }
    if (-not (Test-Path -LiteralPath $Capture.OutputPath) -or (Get-Item -LiteralPath $Capture.OutputPath).Length -lt 4096) { throw 'FFmpeg gfxcapture produced no usable clip.' }

    $ffprobe = (Get-Command ffprobe.exe -ErrorAction Stop).Source
    $probeText = & $ffprobe -v error -count_frames -select_streams v:0 -show_entries stream=width,height,avg_frame_rate,duration,nb_read_frames -of json $Capture.OutputPath 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "ffprobe rejected the captured clip: $probeText" }
    $stream = @((($probeText | ConvertFrom-Json).streams) | Select-Object -First 1)
    if ($stream.Count -ne 1) { throw "Captured clip has no decodable video stream: $probeText" }
    $duration = [double]$stream[0].duration
    $frames = [int]$stream[0].nb_read_frames
    $expectedFrames = [Math]::Floor($duration * $Capture.FrameRate)
    $coverage = if ($expectedFrames -gt 0) { $frames / [double]$expectedFrames } else { 0 }
    if ($frames -lt ($expectedFrames * 0.9) -or $duration -lt 1) { throw "Captured clip is incomplete: duration=${duration}s frames=$frames expected~$expectedFrames coverage=$coverage." }
    $contactRate = 0.25
    $contactRows = [Math]::Max(1, [Math]::Ceiling($duration * $contactRate / 4))
    & (Get-Command ffmpeg.exe -ErrorAction Stop).Source -hide_banner -loglevel error -y -i $Capture.OutputPath -vf "fps=$contactRate,scale=480:-1,tile=4x$contactRows" -frames:v 1 -q:v 3 $ContactSheetPath
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $ContactSheetPath)) { throw 'Could not extract contact sheet from captured clip.' }

    $timelineDirectory = Join-Path (Split-Path -Parent $Capture.OutputPath) 'TimelineFrames'
    $timelineIndexPath = Join-Path (Split-Path -Parent $Capture.OutputPath) (([IO.Path]::GetFileNameWithoutExtension($Capture.OutputPath)) + '-timeline-index.json')
    $timelineSelections = @()
    if (Test-Path -LiteralPath $EventTracePath) {
        $eventRows = @(Get-Content -LiteralPath $EventTracePath -Encoding UTF8 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json })
        $importantActions = @('menuSelect','dialogueSelect','dialogueContinue','battlePause','battleSkip','battleFinish','partyTakeAll','partyScreenDone','inventoryTakeAll','inventoryDone','mapSettlementTargets','move','recruitOptions','recruit','provision','tradeConfirm','rest','providerDone','modelLoopFailure','crashReport','crashReportExpanded','crashReportScroll','crashObserved')
        $priorSignature = $null
        foreach ($event in $eventRows) {
            $signature = @([string]$event.gameState,[string]$event.menuId,[string]$event.partyScreenMode,[string]$event.inventoryMode) -join '|'
            $stateChanged = $null -ne $priorSignature -and $signature -ne $priorSignature
            $priorSignature = $signature
            $isBoundary = [string]$event.event -in @('capture-start','capture-end')
            $isImportantAction = [string]$event.action -in $importantActions
            if (-not $stateChanged -and -not $isBoundary -and -not $isImportantAction) { continue }
            $frameDuration = 1.0 / [Math]::Max(1.0, [double]$Capture.FrameRate)
            $lastFrameSeconds = [Math]::Max([double]0.0, [double]$duration - $frameDuration)
            $centerSeconds = [Math]::Max([double]0.0, [Math]::Min([double]$lastFrameSeconds, [double]$event.offsetMilliseconds / 1000.0))
            $stateTag = ([string]$event.gameState + '-' + [string]$event.partyScreenMode + '-' + [string]$event.inventoryMode) -replace '[^A-Za-z0-9_-]','_'
            if ([string]::IsNullOrWhiteSpace($stateTag)) { $stateTag = 'unknown' }
            $safeAction = ([string]$event.action) -replace '[^A-Za-z0-9_-]','_'
            if ([string]::IsNullOrWhiteSpace($safeAction)) { $safeAction = ([string]$event.event -replace '[^A-Za-z0-9_-]','_') }
            $timelineSelections += [ordered]@{
                event = [string]$event.event
                action = [string]$event.action
                commandId = [string]$event.commandId
                stateChanged = $stateChanged
                gameState = [string]$event.gameState
                menuId = [string]$event.menuId
                partyScreenMode = [string]$event.partyScreenMode
                inventoryMode = [string]$event.inventoryMode
                utc = [string]$event.utc
                offsetMilliseconds = [double]$event.offsetMilliseconds
                beforeFrameSeconds = [Math]::Round([Math]::Max([double]0.0,$centerSeconds - 0.2),3)
                eventFrameSeconds = [Math]::Round($centerSeconds,3)
                afterFrameSeconds = [Math]::Round([Math]::Min([double]$lastFrameSeconds,$centerSeconds + 0.2),3)
                stateTag = $stateTag
                actionTag = $safeAction
            }
        }
        if ($timelineSelections.Count -gt 0) {
            New-Item -ItemType Directory -Path $timelineDirectory -Force | Out-Null
            $frameOrdinal = 0
            foreach ($selection in $timelineSelections) {
                foreach ($edge in @('before','event','after')) {
                    $frameOrdinal++
                    $seconds = [double]$selection[($edge + 'FrameSeconds')]
                    $framePath = Join-Path $timelineDirectory ('{0:D3}-{1}-{2}-{3}.jpg' -f $frameOrdinal,$selection.actionTag,$selection.stateTag,$edge)
                    & (Get-Command ffmpeg.exe -ErrorAction Stop).Source -hide_banner -loglevel error -y -i $Capture.OutputPath -ss $seconds -vf 'format=yuvj420p' -frames:v 1 -q:v 2 $framePath
                    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $framePath)) { throw "Could not extract $edge frame at ${seconds}s for event '$($selection.commandId)'." }
                    $selection[($edge + 'FramePath')] = $framePath
                }
            }
        }
    }
    $sourceVideoHash = (Get-FileHash -LiteralPath $Capture.OutputPath -Algorithm SHA256).Hash
    $sourceClipName = [IO.Path]::GetFileName($Capture.OutputPath)
    $timelineIndex = [ordered]@{
        sourceClip = [ordered]@{ fileName = $sourceClipName; sha256 = $sourceVideoHash; retained = [bool]$KeepVideo; removedAfterEvidence = (-not $KeepVideo) }
        contactSheetPath = $ContactSheetPath
        eventTracePath = $EventTracePath
        timelineFramesDirectory = if ($timelineSelections.Count -gt 0) { $timelineDirectory } else { $null }
        eventCount = $timelineSelections.Count
        selections = $timelineSelections
    }
    $timelineIndex | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $timelineIndexPath -Encoding UTF8
    if (-not $KeepVideo) { Remove-Item -LiteralPath $Capture.OutputPath -Force }

    [pscustomobject]@{
        Passed = $true
        Provider = 'FFmpeg gfxcapture, explicit Bannerlord HWND'
        ProcessId = $Capture.ProcessId
        WindowHandle = $Capture.WindowHandle
        WindowTitle = $Capture.WindowTitle
        FrameRateTarget = $Capture.FrameRate
        AverageFrameRate = [string]$stream[0].avg_frame_rate
        FrameCount = $frames
        ExpectedFrameCount = $expectedFrames
        FrameCoverageRatio = [Math]::Round($coverage, 3)
        Width = [int]$stream[0].width
        Height = [int]$stream[0].height
        DurationSeconds = [Math]::Round($duration, 3)
        StartedUtc = $Capture.StartedUtc
        StopRequestedUtc = $stopRequestedUtc
        StoppedUtc = $stoppedUtc
        StartedTicks = $Capture.StartedTicks
        StopRequestedTicks = $stopRequestedTicks
        StoppedTicks = $stoppedTicks
        StopwatchFrequency = $Capture.StopwatchFrequency
        SourceVideoName = $sourceClipName
        SourceVideoSha256 = $sourceVideoHash
        VideoRetained = [bool]$KeepVideo
        VideoRemovedAfterEvidence = (-not $KeepVideo)
        ContactSheetPath = $ContactSheetPath
        TimelineIndexPath = $timelineIndexPath
        TimelineFrameCount = $timelineSelections.Count * 3
        FfmpegStderr = $Capture.StderrTask.Result
    }
}
