[CmdletBinding()]
param(
    [string]$EvidenceRoot,
    [string]$CurrentRunId,
    [string[]]$ReferenceDocumentPaths,
    [ValidateRange(1, 1000)][int]$KeepMostRecent = 30,
    [switch]$Apply,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) { $EvidenceRoot = Join-Path $PSScriptRoot 'TestResults' }
if (-not $ReferenceDocumentPaths -or $ReferenceDocumentPaths.Count -eq 0) {
    $ReferenceDocumentPaths = @((Join-Path $PSScriptRoot 'DEVELOPMENT.md'), (Join-Path $PSScriptRoot 'Focus\MAINLINE.md'))
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
        if ($selections.Count -eq 0) { return $false }
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

function Invoke-TestResultsRetention {
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$ActiveRunId,
        [string[]]$ReferencePaths,
        [int]$RecentLimit,
        [bool]$Execute
    )

    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $rootFull -PathType Container)) { throw "Evidence root not found: $rootFull" }
    $rootPrefix = $rootFull + [IO.Path]::DirectorySeparatorChar
    $protectedIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if (-not [string]::IsNullOrWhiteSpace($ActiveRunId)) { $null = $protectedIds.Add($ActiveRunId) }

    foreach ($documentPath in $ReferencePaths) {
        if (-not (Test-Path -LiteralPath $documentPath -PathType Leaf)) { continue }
        $documentText = Get-Content -LiteralPath $documentPath -Raw -Encoding UTF8
        foreach ($match in [regex]::Matches($documentText, '(?<!\d)\d{8}-\d{6}(?!\d)')) { $null = $protectedIds.Add($match.Value) }
    }
    $referencedRunCount = $protectedIds.Count

    $timestampedDirectories = @(Get-ChildItem -LiteralPath $rootFull -Directory | Where-Object { $_.Name -match '^\d{8}-\d{6}$' })
    $recentDirectories = @($timestampedDirectories | Sort-Object Name -Descending | Select-Object -First $RecentLimit)
    foreach ($directory in $recentDirectories) { $null = $protectedIds.Add($directory.Name) }

    $keptForIncompleteCapture = [Collections.Generic.List[string]]::new()
    $skippedRuns = [Collections.Generic.List[object]]::new()
    $removedVideoBytes = [long]0
    $removedVideoCount = 0
    foreach ($directory in $timestampedDirectories) {
        $directoryFull = [IO.Path]::GetFullPath($directory.FullName)
        if (-not $directoryFull.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Refusing path outside evidence root: $directoryFull" }
        if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $null = $protectedIds.Add($directory.Name); continue }

        $hasIncompleteVideo = $false
        foreach ($video in Get-ChildItem -LiteralPath $directoryFull -File -Recurse -Filter '*.mp4' -ErrorAction SilentlyContinue) {
            if (-not (Test-IndexedCapture -VideoPath $video.FullName)) {
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

        if ($hasIncompleteVideo -or (Get-ChildItem -LiteralPath $directoryFull -File -Recurse -Filter '*partial*.json' -ErrorAction SilentlyContinue | Select-Object -First 1)) {
            $null = $protectedIds.Add($directory.Name)
            $keptForIncompleteCapture.Add($directory.Name)
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
        ProtectedDocumentRunCount = $referencedRunCount
        PreservedIncompleteCaptureRuns = @($keptForIncompleteCapture | Sort-Object -Unique)
        SkippedRuns = @($skippedRuns)
        DeletedRunCount = $deletedDirectories.Count
        DeletedFileCount = $deletedFiles
        DeletedBytes = $deletedBytes
        DeletedIndexedVideoCount = $removedVideoCount
        DeletedIndexedVideoBytes = $removedVideoBytes
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
        $misc = Join-Path $fixtureRoot 'UserNamedEvidence'
        foreach ($path in @($keep, $cited, $old, $partial, $misc)) { $null = New-Item -ItemType Directory -Path $path }
        'keep' | Set-Content -LiteralPath (Join-Path $keep 'summary.json')
        'cited' | Set-Content -LiteralPath (Join-Path $cited 'summary.json')
        'old' | Set-Content -LiteralPath (Join-Path $old 'summary.json')
        'partial' | Set-Content -LiteralPath (Join-Path $partial 'LiveModelWindow.mp4')
        'partial' | Set-Content -LiteralPath (Join-Path $partial 'LiveModelWindow-partial.json')
        'misc' | Set-Content -LiteralPath (Join-Path $misc 'preserve.txt')
        $reference = Join-Path $fixtureRoot 'reference.md'
        "Evidence: 20260101-000002" | Set-Content -LiteralPath $reference
        $preview = Invoke-TestResultsRetention -Root $fixtureRoot -ActiveRunId '20260101-000003' -ReferencePaths @($reference) -RecentLimit 1 -Execute $false
        if ($preview.DeletedRunCount -ne 1 -or $preview.DeletedRuns[0].RunId -ne '20260101-000001' -or $preview.PreservedIncompleteCaptureRuns -notcontains '20260101-000000') { throw 'Retention dry-run did not keep the cited/recent/incomplete records and select only the old run.' }
        $applied = Invoke-TestResultsRetention -Root $fixtureRoot -ActiveRunId '20260101-000003' -ReferencePaths @($reference) -RecentLimit 1 -Execute $true
        foreach ($path in @($keep, $cited, $partial, $misc)) { if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw "Retention deleted protected fixture $path" } }
        if (Test-Path -LiteralPath $old) { throw 'Retention failed to remove the eligible old fixture run.' }
        [pscustomobject]@{ Passed = $true; PreviewDeletedRuns = $preview.DeletedRunCount; AppliedDeletedRuns = $applied.DeletedRunCount; IncompleteCapturePreserved = $true; ReferencedRunPreserved = $true; NonRunFolderPreserved = $true } | ConvertTo-Json -Compress
    } finally {
        if (Test-Path -LiteralPath $fixtureRoot -PathType Container) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
    }
    exit 0
}

$result = Invoke-TestResultsRetention -Root $EvidenceRoot -ActiveRunId $CurrentRunId -ReferencePaths $ReferenceDocumentPaths -RecentLimit $KeepMostRecent -Execute ([bool]$Apply)
$result | ConvertTo-Json -Depth 6
