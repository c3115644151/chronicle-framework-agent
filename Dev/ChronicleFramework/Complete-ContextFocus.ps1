[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$NextTitle,
    [Parameter(Mandatory)] [string]$NextObjective,
    [ValidateSet('Delete', 'Archive')] [string]$Disposition = 'Delete'
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$statePath = Join-Path $root 'ContextState.json'
$mainlinePath = Join-Path $root 'Focus\MAINLINE.md'
$state = Get-Content $statePath -Raw | ConvertFrom-Json
$oldPath = [string]$state.current.path
$oldAbsolutePath = Join-Path $root $oldPath
if (-not (Test-Path $oldAbsolutePath)) { throw "Current mainline is missing: $oldAbsolutePath" }

if ($Disposition -eq 'Archive') {
    $archiveRoot = Join-Path $root ([string]$state.lifecyclePolicy.archiveDirectory)
    New-Item -ItemType Directory -Force -Path $archiveRoot | Out-Null
    $archiveName = "{0}-{1}.md" -f ([IO.Path]::GetFileNameWithoutExtension($oldPath)), (Get-Date -Format 'yyyyMMdd-HHmmss')
    Move-Item -LiteralPath $oldAbsolutePath -Destination (Join-Path $archiveRoot $archiveName)
} else {
    Remove-Item -LiteralPath $oldAbsolutePath -Force
}

New-Item -ItemType Directory -Force -Path (Split-Path $mainlinePath) | Out-Null
@"
# $NextTitle

Objective: $NextObjective

Task status and sequence are tracked in the GitHub Project.
"@ | Set-Content -Path $mainlinePath -Encoding UTF8

$now = [DateTime]::UtcNow
$state.current.path = 'Focus/MAINLINE.md'
$state.current.reviewedUtc = $now.ToString('O')
$state.current.reviewAfterUtc = $now.AddDays([int]$state.lifecyclePolicy.reviewIntervalDays).ToString('O')
$state.current.mainlineSha256 = (Get-FileHash $mainlinePath -Algorithm SHA256).Hash.ToLowerInvariant()
$archives = @()
$archiveRoot = Join-Path $root ([string]$state.lifecyclePolicy.archiveDirectory)
if (Test-Path $archiveRoot) { $archives = @(Get-ChildItem $archiveRoot -Recurse -File -Filter '*.md' | ForEach-Object { $_.FullName.Substring($root.Length + 1).Replace('\', '/') }) }
$state.archives = $archives
$temporaryPath = "$statePath.tmp"
$state | ConvertTo-Json -Depth 8 | Set-Content -Path $temporaryPath -Encoding UTF8
Move-Item -LiteralPath $temporaryPath -Destination $statePath -Force

[pscustomobject]@{ Disposition = $Disposition; FocusPath = $state.current.path; ReviewAfterUtc = $state.current.reviewAfterUtc; Archives = $state.archives } | ConvertTo-Json -Depth 8
