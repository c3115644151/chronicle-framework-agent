#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$EvidenceRoot,
    [string]$CurrentRunId,
    [string[]]$ReferenceDocumentPaths,
    [ValidateRange(1, 1000)][int]$KeepMostRecent = 30,
    [ValidateRange(1, 1000)][int]$KeepMostRecentContactSheets = 5,
    [switch]$Apply,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) { $EvidenceRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'TestResults' }
if (-not $ReferenceDocumentPaths -or $ReferenceDocumentPaths.Count -eq 0) {
    $docsRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'docs'
    $ReferenceDocumentPaths = @((Join-Path $docsRoot 'DEVELOPMENT.md'), (Join-Path $docsRoot 'MAINLINE.md'), (Join-Path $docsRoot 'RUNLOG.md'))
}

function Test-IndexedCapture {
    param([Parameter(Mandatory)][string]$VideoPath)

    $directory = Split-Path -Parent $VideoPath
    $stem = [IO.Path]::GetFileNameWithoutExtension($VideoPath)
    $indexPath = Join-Path $directory ($stem + '-timeline-index.json')
    $contactPath = Join-Path $directory ($stem + '-contact.jpg')
    if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf) -or -not (Test-Path -LiteralPath $contactPath -PathType Leaf)) { return $false }

    try {
        $index = Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $selections = @($index.selections)
        if ($selections.Count -eq 0) { return [bool]$index.sourceClip.removedAfterEvidence }
        foreach ($selection in $selections) {
            foreach ($property in @('beforeFramePath', 'eventFramePath', 'afterFramePath')) {
                $framePath = [string]$selection.$property
                if (-not [string]::IsNullOrWhiteSpace($framePath) -and -not (Test-Path -LiteralPath $framePath -PathType Leaf)) { return $false }
            }
        }
        return $true
    } catch {
        return $false
    }
}

function Test-Mp4WithoutDecodableStream {
    param([Parameter(Mandatory)][string]$Path)

    # Walks the top-level MP4 box chain. A file whose chain cannot be parsed, or
    # that never declares the movie box carrying the stream table, has no
    # decodable stream on any host, whether or not a media tool happens to be
    # installed where this check runs.
    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    $length = [long]$item.Length
    if ($length -eq 0) { return $true }
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $header = [byte[]]::new(8)
        $offset = [long]0
        $hasMovieBox = $false
        while ($offset -lt $length) {
            if ($length - $offset -lt 8) { return $true }
            $stream.Position = $offset
            if ($stream.Read($header, 0, 8) -ne 8) { return $true }
            $size = (([long]$header[0] -shl 24) -bor ([long]$header[1] -shl 16) -bor ([long]$header[2] -shl 8) -bor [long]$header[3])
            $type = [Text.Encoding]::ASCII.GetString($header, 4, 4)
            if ($type -notmatch '^[A-Za-z][A-Za-z0-9 ]{3}$') { return $true }
            if ($size -eq 0) {
                # Only a trailing media box may run to end of file.
                return -not ($type -eq 'mdat' -and $hasMovieBox)
            }
            if ($size -eq 1) {
                $largeSize = [byte[]]::new(8)
                $stream.Position = $offset + 8
                if ($stream.Read($largeSize, 0, 8) -ne 8) { return $true }
                [Array]::Reverse($largeSize)
                $size = [long][BitConverter]::ToUInt64($largeSize, 0)
            }
            if ($size -lt 8 -or $offset + $size -gt $length) { return $true }
            if ($type -eq 'moov') { $hasMovieBox = $true }
            if ($type -eq 'mdat' -and $hasMovieBox) { return $false }
            $offset += $size
        }
        return -not $hasMovieBox
    }
    finally {
        $stream.Dispose()
    }
}
function Invoke-TestResultsRetention {
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$ActiveRunId,
        [string[]]$ReferencePaths,
        [int]$RecentLimit,
        [int]$RecentContactLimit,
        [bool]$Execute
    )

    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $rootFull -PathType Container)) { throw "Evidence root not found: $rootFull" }
    $rootPrefix = $rootFull + [IO.Path]::DirectorySeparatorChar
    $protectedIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if (-not [string]::IsNullOrWhiteSpace($ActiveRunId)) { $null = $protectedIds.Add($ActiveRunId) }
    $recentIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $referencedFiles = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    $missingReferences = @(@($ReferencePaths) | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
    if ($missingReferences.Count -gt 0) {
        throw ("Retention reference document missing: " + ($missingReferences -join '; ') + ". Protecting documented runs is mandatory; retention stops instead of deleting evidence it cannot account for.")
    }
    foreach ($documentPath in $ReferencePaths) {
        $documentText = Get-Content -LiteralPath $documentPath -Raw -Encoding UTF8
        foreach ($match in [regex]::Matches($documentText, '(?<!\d)\d{8}-\d{6}(?!\d)')) { $null = $protectedIds.Add($match.Value) }
        foreach ($match in [regex]::Matches($documentText, '(?i)TestResults[\\/](\d{8}-\d{6})[\\/]([^\s`"\)\]>]+\.(?:bmp|jpg|jpeg|png))')) {
            $relative = $match.Value -replace '(?i)^TestResults[\\/]', ''
            $relative = $relative.Replace('/', '\\')
            $null = $referencedFiles.Add([IO.Path]::GetFullPath((Join-Path $rootFull $relative)))
        }
    }
    $referencedRunCount = $protectedIds.Count

    $timestampedDirectories = @(Get-ChildItem -LiteralPath $rootFull -Directory | Where-Object { $_.Name -match '^\d{8}-\d{6}$' })
    $recentDirectories = @($timestampedDirectories | Sort-Object Name -Descending | Select-Object -First $RecentLimit)
    foreach ($directory in $recentDirectories) { $null = $protectedIds.Add($directory.Name); $null = $recentIds.Add($directory.Name) }
    $recentContactDirectories = @($timestampedDirectories | Sort-Object Name -Descending | Select-Object -First $RecentContactLimit)
    $recentContactIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($directory in $recentContactDirectories) { $null = $recentContactIds.Add($directory.Name) }

    $keptForIncompleteCapture = [Collections.Generic.List[string]]::new()
    $skippedRuns = [Collections.Generic.List[object]]::new()
    $removedVideoBytes = [long]0
    $removedVideoCount = 0
    $removedUndecodableVideoBytes = [long]0
    $removedUndecodableVideoCount = 0
    $removedLegacyProbeBytes = [long]0
    $removedLegacyProbeCount = 0
    $compactedMedia = [Collections.Generic.List[object]]::new()
    $compactedMediaBytes = [long]0
    $compactedMediaCount = 0

    # A previous standalone capture-resilience probe left this exact synthetic
    # file at the TestResults root. It is not a run receipt or user recording.
    $legacyProbePath = Join-Path $rootFull 'fragment-probe-test.mp4'
    if (Test-Path -LiteralPath $legacyProbePath -PathType Leaf) {
        $legacyProbeItem = Get-Item -LiteralPath $legacyProbePath
        if ($Execute) {
            Remove-Item -LiteralPath $legacyProbePath -Force -ErrorAction Stop
            $removedLegacyProbeBytes = [long]$legacyProbeItem.Length
            $removedLegacyProbeCount = 1
        }
    }
    $legacyProbeStderrPath = Join-Path $rootFull 'fragment-probe-test.stderr'
    if ($Execute -and (Test-Path -LiteralPath $legacyProbeStderrPath -PathType Leaf) -and (Get-Item -LiteralPath $legacyProbeStderrPath).Length -eq 0) {
        Remove-Item -LiteralPath $legacyProbeStderrPath -Force -ErrorAction Stop
    }

    foreach ($directory in $timestampedDirectories) {
        $directoryFull = [IO.Path]::GetFullPath($directory.FullName)
        if (-not $directoryFull.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Refusing path outside evidence root: $directoryFull" }
        if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $null = $protectedIds.Add($directory.Name); continue }

        $hasIncompleteVideo = $false
        foreach ($video in Get-ChildItem -LiteralPath $directoryFull -File -Recurse -Filter '*.mp4' -ErrorAction SilentlyContinue) {
            if (-not (Test-IndexedCapture -VideoPath $video.FullName)) {
                $hasMatchingPartialReceipt = $false
                foreach ($partialReceipt in Get-ChildItem -LiteralPath $directoryFull -File -Recurse -Filter '*partial*.json' -ErrorAction SilentlyContinue) {
                    try {
                        $partialData = Get-Content -LiteralPath $partialReceipt.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                        if ([string]::Equals([string]$partialData.videoPath, $video.FullName, [StringComparison]::OrdinalIgnoreCase)) { $hasMatchingPartialReceipt = $true; break }
                    } catch { }
                }
                if ($hasMatchingPartialReceipt) { $hasIncompleteVideo = $true; continue }
                $ffprobeCommand = Get-Command ffprobe.exe -ErrorAction SilentlyContinue
                $probeOutput = ''
                $probeError = ''
                $probeExitCode = -1
                $hasVideoStream = $false
                if ($ffprobeCommand) {
                    $previousErrorActionPreference = $ErrorActionPreference
                    $probeErrorPath = [IO.Path]::GetTempFileName()
                    try {
                        $ErrorActionPreference = 'Continue'
                        $probeOutput = & $ffprobeCommand.Source -v error -select_streams v:0 -show_entries stream=codec_name -of json $video.FullName 2> $probeErrorPath | Out-String
                        $probeExitCode = $LASTEXITCODE
                        $probeError = if (Test-Path -LiteralPath $probeErrorPath) { Get-Content -LiteralPath $probeErrorPath -Raw -Encoding UTF8 } else { '' }
                        try { $hasVideoStream = @((($probeOutput | ConvertFrom-Json).streams | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.codec_name) })).Count -gt 0 } catch { $hasVideoStream = $false }
                    }
                    finally {
                        $ErrorActionPreference = $previousErrorActionPreference
                        if (Test-Path -LiteralPath $probeErrorPath -PathType Leaf) { Remove-Item -LiteralPath $probeErrorPath -Force -ErrorAction SilentlyContinue }
                    }
                }
                $probeSaysBroken = $probeExitCode -ne 0 -and $probeError -match 'moov atom not found|Invalid data found when processing input'
                $knownUndecodable = -not $hasVideoStream -and ($video.Length -eq 0 -or $probeSaysBroken -or (Test-Mp4WithoutDecodableStream -Path $video.FullName))
                if ($knownUndecodable) {
                    if ($Execute -and $protectedIds.Contains($directory.Name)) {
                        $receiptPath = Join-Path $directoryFull (([IO.Path]::GetFileNameWithoutExtension($video.Name)) + '-capture-cleanup.json')
                        $cleanupReceipt = [ordered]@{
                            sourceFile = $video.Name
                            sourceBytes = [long]$video.Length
                            sourceSha256 = if ($video.Length -gt 0) { (Get-FileHash -LiteralPath $video.FullName -Algorithm SHA256).Hash } else { $null }
                            ffprobeExitCode = $probeExitCode
                            ffprobeError = $probeError.Trim()
                            structuralVerdict = 'no-movie-box'
                            reason = 'Source MP4 has no decodable video stream; retain per-run screenshots, events and Harness receipts instead.'
                            sourceRemoved = $false
                        }
                        $cleanupReceipt | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
                        $bytes = [long]$video.Length
                        Remove-Item -LiteralPath $video.FullName -Force -ErrorAction Stop
                        $cleanupReceipt.sourceRemoved = $true
                        $cleanupReceipt | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
                        $removedUndecodableVideoBytes += $bytes
                        $removedUndecodableVideoCount++
                    }
                    continue
                }
                $hasIncompleteVideo = $true
                continue
            }
            if ($Execute) {
                try {
                    $length = $video.Length
                    Remove-Item -LiteralPath $video.FullName -Force -ErrorAction Stop
                    $removedVideoBytes += $length
                    $removedVideoCount++
                } catch {
                    $hasIncompleteVideo = $true
                }
            }
        }

        $partialCaptureStillExists = $false
        foreach ($partialReceipt in Get-ChildItem -LiteralPath $directoryFull -File -Recurse -Filter '*partial*.json' -ErrorAction SilentlyContinue) {
            try {
                $partialData = Get-Content -LiteralPath $partialReceipt.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                $partialVideoPath = [string]$partialData.videoPath
                if (-not [string]::IsNullOrWhiteSpace($partialVideoPath) -and (Test-Path -LiteralPath $partialVideoPath -PathType Leaf)) { $partialCaptureStillExists = $true; break }
            } catch { }
        }
        if ($hasIncompleteVideo -or $partialCaptureStillExists) {
            $null = $protectedIds.Add($directory.Name)
            $keptForIncompleteCapture.Add($directory.Name)
        }
    }

    # Keep compact receipts for old runs cited by docs, but do not let every
    # historical screenshot/contact sheet/keyframe accumulate forever. For old
    # indexed captures, retain event frames and prune redundant before/after
    # context frames; recent runs and explicitly cited image files stay intact.
    foreach ($directory in $timestampedDirectories) {
        if (-not $protectedIds.Contains($directory.Name) -or $keptForIncompleteCapture.Contains($directory.Name)) { continue }
        $directoryFull = [IO.Path]::GetFullPath($directory.FullName)
        if (-not $directoryFull.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Refusing media compaction outside evidence root: $directoryFull" }
        try { $compactionTree = @(Get-ChildItem -LiteralPath $directoryFull -Force -Recurse -ErrorAction Stop) }
        catch { $skippedRuns.Add([pscustomobject]@{ RunId = $directory.Name; Reason = 'media-tree-enumeration-failed'; Detail = $_.Exception.Message }); continue }
        if (@($compactionTree | Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 }).Count -gt 0 -or @($compactionTree | Where-Object { $_.FullName.Length -gt 240 }).Count -gt 0) {
            $skippedRuns.Add([pscustomobject]@{ RunId = $directory.Name; Reason = 'media-tree-unsafe-or-path-too-long'; Detail = $null })
            continue
        }

        $indexedFrames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $historicalContextFrames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $completeContactSheets = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $timelineIndexFiles = @(Get-ChildItem -LiteralPath $directoryFull -File -Recurse -Filter '*-timeline-index.json' -ErrorAction SilentlyContinue)
        foreach ($indexFile in $timelineIndexFiles) {
            try {
                $index = Get-Content -LiteralPath $indexFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                $framesExist = $true
                foreach ($selection in @($index.selections)) {
                    $eventFrame = [string]$selection.eventFramePath
                    if (-not [string]::IsNullOrWhiteSpace($eventFrame)) {
                        $eventFrameFull = [IO.Path]::GetFullPath($eventFrame)
                        if (-not (Test-Path -LiteralPath $eventFrameFull -PathType Leaf)) { $framesExist = $false; break }
                        $null = $indexedFrames.Add($eventFrameFull)
                    }
                    foreach ($property in @('beforeFramePath', 'afterFramePath')) {
                        $frame = [string]$selection.$property
                        if ([string]::IsNullOrWhiteSpace($frame)) { continue }
                        $frameFull = [IO.Path]::GetFullPath($frame)
                        if (-not (Test-Path -LiteralPath $frameFull -PathType Leaf)) { $framesExist = $false; break }
                        if (-not $recentIds.Contains($directory.Name) -and -not $indexedFrames.Contains($frameFull) -and -not $referencedFiles.Contains($frameFull)) {
                            $null = $historicalContextFrames.Add($frameFull)
                        }
                    }
                    if (-not $framesExist) { break }
                }
                if ($framesExist -and [bool]$index.sourceClip.removedAfterEvidence) {
                    $contactName = ([IO.Path]::GetFileName($indexFile.FullName) -replace '-timeline-index\.json$', '-contact.jpg')
                    $null = $completeContactSheets.Add([IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $indexFile.FullName) $contactName)))
                }
            } catch { }
        }

        foreach ($file in Get-ChildItem -LiteralPath $directoryFull -File -Recurse -Force -ErrorAction SilentlyContinue) {
            $isBitmap = [string]::Equals($file.Extension, '.bmp', [StringComparison]::OrdinalIgnoreCase) -and -not $recentIds.Contains($directory.Name)
            $isContactSheet = $file.Name -match '-contact\.jpg$' -and -not $recentContactIds.Contains($directory.Name) -and $completeContactSheets.Contains([IO.Path]::GetFullPath($file.FullName))
            $fileFull = [IO.Path]::GetFullPath($file.FullName)
            $isHistoricalContextFrame = $historicalContextFrames.Contains($fileFull) -and -not $indexedFrames.Contains($fileFull)
            if (-not ($isBitmap -or $isContactSheet -or $isHistoricalContextFrame)) { continue }
            if ($referencedFiles.Contains($fileFull) -or $indexedFrames.Contains($fileFull)) { continue }
            $entry = [pscustomobject]@{ Path = $fileFull.Substring($rootPrefix.Length); Bytes = [long]$file.Length }
            if ($Execute) {
                Remove-Item -LiteralPath $fileFull -Force -ErrorAction Stop
            }
            $compactedMedia.Add($entry)
            $compactedMediaBytes += [long]$file.Length
            $compactedMediaCount++
        }

        if ($Execute -and $historicalContextFrames.Count -gt 0) {
            foreach ($indexFile in $timelineIndexFiles) {
                try {
                    $index = Get-Content -LiteralPath $indexFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                    $prunedReferences = 0
                    foreach ($selection in @($index.selections)) {
                        foreach ($property in @('beforeFramePath', 'afterFramePath')) {
                            $frame = [string]$selection.$property
                            if ([string]::IsNullOrWhiteSpace($frame)) { continue }
                            $frameFull = [IO.Path]::GetFullPath($frame)
                            if ($historicalContextFrames.Contains($frameFull) -and -not (Test-Path -LiteralPath $frameFull -PathType Leaf)) {
                                $selection.$property = ''
                                $prunedReferences++
                            }
                        }
                    }
                    if ($prunedReferences -gt 0) {
                        $index | Add-Member -NotePropertyName retentionCompaction -NotePropertyValue ([ordered]@{
                            policy = 'historical-event-frames-only'
                            compactedUtc = [DateTime]::UtcNow.ToString('o')
                            contextFrameReferencesCleared = $prunedReferences
                        }) -Force
                        $index | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $indexFile.FullName -Encoding UTF8
                    }
                } catch {
                    $skippedRuns.Add([pscustomobject]@{ RunId = $directory.Name; Reason = 'timeline-index-update-failed'; Detail = $_.Exception.Message })
                }
            }
        }
    }

    $candidates = @($timestampedDirectories | Where-Object { -not $protectedIds.Contains($_.Name) })
    $deletedDirectories = [Collections.Generic.List[object]]::new()
    $deletedBytes = [long]0
    $deletedFiles = 0
    foreach ($directory in $candidates) {
        $directoryFull = [IO.Path]::GetFullPath($directory.FullName)
        if (-not $directoryFull.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase) -or $directory.Name -notmatch '^\d{8}-\d{6}$') { throw "Refusing unsafe evidence directory: $directoryFull" }
        try { $tree = @(Get-ChildItem -LiteralPath $directoryFull -Force -Recurse -ErrorAction Stop) }
        catch {
            $skippedRuns.Add([pscustomobject]@{ RunId = $directory.Name; Reason = 'tree-enumeration-failed'; Detail = $_.Exception.Message })
            continue
        }
        if (@($tree | Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 }).Count -gt 0) {
            $skippedRuns.Add([pscustomobject]@{ RunId = $directory.Name; Reason = 'reparse-point-present'; Detail = $null })
            continue
        }
        if (@($tree | Where-Object { $_.FullName.Length -gt 240 }).Count -gt 0) {
            $skippedRuns.Add([pscustomobject]@{ RunId = $directory.Name; Reason = 'path-too-long-for-powershell'; Detail = $null })
            continue
        }
        $files = @($tree | Where-Object { -not $_.PSIsContainer })
        $bytes = [long](($files | Measure-Object -Property Length -Sum).Sum)
        if ($Execute) {
            try {
                Remove-Item -LiteralPath $directoryFull -Recurse -Force -ErrorAction Stop
                $deletedDirectories.Add([pscustomobject]@{ RunId = $directory.Name; FileCount = $files.Count; Bytes = $bytes })
                $deletedBytes += $bytes
                $deletedFiles += $files.Count
            } catch {
                $skippedRuns.Add([pscustomobject]@{ RunId = $directory.Name; Reason = 'delete-failed'; Detail = $_.Exception.Message })
            }
        } else {
            $deletedDirectories.Add([pscustomobject]@{ RunId = $directory.Name; FileCount = $files.Count; Bytes = $bytes })
            $deletedBytes += $bytes
            $deletedFiles += $files.Count
        }
    }

    $unexpectedSkips = @($skippedRuns | Where-Object { $_.Reason -in @('tree-enumeration-failed', 'delete-failed') })
    [pscustomobject]@{
        Passed = $unexpectedSkips.Count -eq 0
        Complete = $skippedRuns.Count -eq 0
        Applied = $Execute
        EvidenceRoot = $rootFull
        KeepMostRecentRuns = $RecentLimit
        KeepMostRecentContactSheets = $RecentContactLimit
        ProtectedDocumentRunCount = $referencedRunCount
        PreservedIncompleteCaptureRuns = @($keptForIncompleteCapture | Sort-Object -Unique)
        SkippedRuns = @($skippedRuns)
        DeletedRunCount = $deletedDirectories.Count
        DeletedFileCount = $deletedFiles
        DeletedBytes = $deletedBytes
        DeletedIndexedVideoCount = $removedVideoCount
        DeletedIndexedVideoBytes = $removedVideoBytes
        DeletedUndecodableVideoCount = $removedUndecodableVideoCount
        DeletedUndecodableVideoBytes = $removedUndecodableVideoBytes
        DeletedLegacyProbeCount = $removedLegacyProbeCount
        DeletedLegacyProbeBytes = $removedLegacyProbeBytes
        CompactedMediaCount = $compactedMediaCount
        CompactedMediaBytes = $compactedMediaBytes
        CompactedMedia = @($compactedMedia)
        DeletedRuns = @($deletedDirectories)
    }
}

if ($SelfTest) {
    $fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('Chronicle-TestResultsRetention-' + [guid]::NewGuid().ToString('N'))
    try {
        $null = New-Item -ItemType Directory -Path $fixtureRoot
        $keep = Join-Path $fixtureRoot '20260101-000003'
        $cited = Join-Path $fixtureRoot '20260101-000002'
        $old = Join-Path $fixtureRoot '20260101-000001'
        $partial = Join-Path $fixtureRoot '20260101-000000'
        $contactOnly = Join-Path $fixtureRoot '20251231-235959'
        $misc = Join-Path $fixtureRoot 'UserNamedEvidence'
        foreach ($path in @($keep, $cited, $old, $partial, $contactOnly, $misc)) { $null = New-Item -ItemType Directory -Path $path }
        'keep' | Set-Content -LiteralPath (Join-Path $keep 'summary.json')
        $brokenCapture = Join-Path $keep 'broken-capture.mp4'
        [IO.File]::WriteAllBytes($brokenCapture, [byte[]]::new(8192))
        'cited' | Set-Content -LiteralPath (Join-Path $cited 'summary.json')
        $citedImage = Join-Path $cited 'Temp\explicit.bmp'
        $unusedImage = Join-Path $cited 'Temp\unused.bmp'
        $citedContact = Join-Path $cited 'Temp\LiveModelWindow-contact.jpg'
        $citedBeforeFrame = Join-Path $cited 'Temp\before.jpg'
        $citedFrames = Join-Path $cited 'Temp\event.jpg'
        $citedAfterFrame = Join-Path $cited 'Temp\after.jpg'
        $null = New-Item -ItemType Directory -Path (Join-Path $cited 'Temp')
        [IO.File]::WriteAllBytes($citedImage, [byte[]]::new(1024))
        [IO.File]::WriteAllBytes($unusedImage, [byte[]]::new(2048))
        [IO.File]::WriteAllBytes($citedContact, [byte[]]::new(3072))
        [IO.File]::WriteAllBytes($citedBeforeFrame, [byte[]]::new(2048))
        [IO.File]::WriteAllBytes($citedFrames, [byte[]]::new(4096))
        [IO.File]::WriteAllBytes($citedAfterFrame, [byte[]]::new(2048))
        $citedIndexPath = Join-Path $cited 'Temp\LiveModelWindow-timeline-index.json'
        [ordered]@{ sourceClip = @{ removedAfterEvidence = $true }; selections = @(@{ beforeFramePath = $citedBeforeFrame; eventFramePath = $citedFrames; afterFramePath = $citedAfterFrame }) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $citedIndexPath -Encoding UTF8
        'old' | Set-Content -LiteralPath (Join-Path $old 'summary.json')
        'partial' | Set-Content -LiteralPath (Join-Path $partial 'LiveModelWindow.mp4')
        [ordered]@{ videoPath = (Join-Path $partial 'LiveModelWindow.mp4') } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $partial 'LiveModelWindow-partial.json') -Encoding UTF8
        $contactVideo = Join-Path $contactOnly 'LiveModelWindow.mp4'
        $contactSheet = Join-Path $contactOnly 'LiveModelWindow-contact.jpg'
        [IO.File]::WriteAllBytes($contactVideo, [byte[]]::new(4096))
        [IO.File]::WriteAllBytes($contactSheet, [byte[]]::new(1024))
        [ordered]@{ sourceClip = @{ removedAfterEvidence = $true }; contactSheetPath = $contactSheet; selections = @() } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $contactOnly 'LiveModelWindow-timeline-index.json') -Encoding UTF8
        'misc' | Set-Content -LiteralPath (Join-Path $misc 'preserve.txt')
        $reference = Join-Path $fixtureRoot 'reference.md'
        "Evidence: 20260101-000002; TestResults\20260101-000002\Temp\explicit.bmp; TestResults\20260101-000002\Temp\event.jpg" | Set-Content -LiteralPath $reference
        $preview = Invoke-TestResultsRetention -Root $fixtureRoot -ActiveRunId '20260101-000003' -ReferencePaths @($reference) -RecentLimit 1 -RecentContactLimit 1 -Execute $false
        if ($preview.DeletedRunCount -ne 2 -or @($preview.DeletedRuns.RunId) -notcontains '20260101-000001' -or @($preview.DeletedRuns.RunId) -notcontains '20251231-235959' -or $preview.PreservedIncompleteCaptureRuns -notcontains '20260101-000000') { throw "Retention dry-run selection mismatch: deleted=$($preview.DeletedRunCount); ids=$(@($preview.DeletedRuns.RunId) -join ','); incomplete=$(@($preview.PreservedIncompleteCaptureRuns) -join ',')" }
        $applied = Invoke-TestResultsRetention -Root $fixtureRoot -ActiveRunId '20260101-000003' -ReferencePaths @($reference) -RecentLimit 1 -RecentContactLimit 1 -Execute $true
        foreach ($path in @($keep, $cited, $partial, $misc)) { if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw "Retention deleted protected fixture $path" } }
        if (Test-Path -LiteralPath $old) { throw 'Retention failed to remove the eligible old fixture run.' }
        if (Test-Path -LiteralPath $contactOnly) { throw 'Retention failed to remove an MP4 whose contact sheet and post-processing index already preserve review evidence.' }
        $citedIndex = Get-Content -LiteralPath $citedIndexPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ((Test-Path -LiteralPath $citedImage) -eq $false -or (Test-Path -LiteralPath $unusedImage) -or (Test-Path -LiteralPath $citedContact) -or (Test-Path -LiteralPath $citedFrames) -eq $false -or (Test-Path -LiteralPath $citedBeforeFrame) -or (Test-Path -LiteralPath $citedAfterFrame) -or -not [string]::IsNullOrWhiteSpace([string]$citedIndex.selections[0].beforeFramePath) -or -not [string]::IsNullOrWhiteSpace([string]$citedIndex.selections[0].afterFramePath) -or $citedIndex.retentionCompaction.policy -ne 'historical-event-frames-only') { throw "Retention media compaction failed: cited=$(Test-Path -LiteralPath $citedImage), unused=$(Test-Path -LiteralPath $unusedImage), contact=$(Test-Path -LiteralPath $citedContact), event=$(Test-Path -LiteralPath $citedFrames), context=$(Test-Path -LiteralPath $citedBeforeFrame)/$(Test-Path -LiteralPath $citedAfterFrame); compacted=$($applied.CompactedMediaCount); paths=$(@($applied.CompactedMedia.Path) -join ',')" }
        $brokenReceiptPath = Join-Path $keep 'broken-capture-capture-cleanup.json'
        $brokenReceipt = if (Test-Path -LiteralPath $brokenReceiptPath) { Get-Content -LiteralPath $brokenReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
        if ((Test-Path -LiteralPath $brokenCapture) -or $null -eq $brokenReceipt -or -not $brokenReceipt.sourceRemoved -or $applied.DeletedUndecodableVideoCount -ne 1) { throw "Retention failed undecodable capture cleanup: rawExists=$(Test-Path -LiteralPath $brokenCapture); receiptExists=$($null -ne $brokenReceipt); sourceRemoved=$($brokenReceipt.sourceRemoved); count=$($applied.DeletedUndecodableVideoCount); skipped=$($applied.SkippedRuns.Count)" }
        [pscustomobject]@{ Passed = $true; PreviewDeletedRuns = $preview.DeletedRunCount; AppliedDeletedRuns = $applied.DeletedRunCount; IncompleteCapturePreserved = $true; ContactSheetOnlyCapturePruned = $true; UndecodableCapturePrunedWithReceipt = $true; ReferencedRunPreserved = $true; CitedAndIndexedMediaPreserved = $true; HistoricalContextFramesCompacted = $true; RedundantHistoricalMediaCompacted = $true; NonRunFolderPreserved = $true } | ConvertTo-Json -Compress
    } finally {
        if (Test-Path -LiteralPath $fixtureRoot -PathType Container) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
    }
    exit 0
}

$result = Invoke-TestResultsRetention -Root $EvidenceRoot -ActiveRunId $CurrentRunId -ReferencePaths $ReferenceDocumentPaths -RecentLimit $KeepMostRecent -RecentContactLimit $KeepMostRecentContactSheets -Execute ([bool]$Apply)
$result | ConvertTo-Json -Depth 6
