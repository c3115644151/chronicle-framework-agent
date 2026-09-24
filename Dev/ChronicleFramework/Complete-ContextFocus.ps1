[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$NextId,
    [Parameter(Mandatory)] [string]$NextObjective,
    [Parameter(Mandatory)] [string]$NextPhase,
    [ValidateSet('Delete', 'Archive')] [string]$Disposition = 'Delete'
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$statePath = Join-Path $root 'ContextState.json'
$mainlinePath = Join-Path $root 'Focus\MAINLINE.md'
$state = Get-Content $statePath -Raw | ConvertFrom-Json
$oldId = [string]$state.current.id
$oldPath = [string]$state.current.path
$oldAbsolutePath = Join-Path $root $oldPath
if (-not (Test-Path $oldAbsolutePath)) { throw "Current mainline is missing: $oldAbsolutePath" }

if ($Disposition -eq 'Archive') {
    $archiveRoot = Join-Path $root ([string]$state.lifecyclePolicy.archiveDirectory)
    New-Item -ItemType Directory -Force -Path $archiveRoot | Out-Null
    $archiveName = "{0}-{1}.md" -f $oldId, (Get-Date -Format 'yyyyMMdd-HHmmss')
    Move-Item -LiteralPath $oldAbsolutePath -Destination (Join-Path $archiveRoot $archiveName)
} else {
    Remove-Item -LiteralPath $oldAbsolutePath -Force
}

New-Item -ItemType Directory -Force -Path (Split-Path $mainlinePath) | Out-Null
@"
# Current focus: $NextId

Status: atomically moved by `Complete-ContextFocus.ps1`.

Objective: $NextObjective

Phase: $NextPhase
"@ | Set-Content -Path $mainlinePath -Encoding UTF8

$now = [DateTime]::UtcNow
$state.current.id = $NextId
$state.current.objective = $NextObjective
$state.current.phase = $NextPhase
$state.current.path = 'Focus/MAINLINE.md'
$state.current.updatedUtc = $now.ToString('O')
$state.current.reviewAfterUtc = $now.AddDays([int]$state.lifecyclePolicy.reviewIntervalDays).ToString('O')
$state.current.mainlineSha256 = (Get-FileHash $mainlinePath -Algorithm SHA256).Hash.ToLowerInvariant()
$archives = @()
$archiveRoot = Join-Path $root ([string]$state.lifecyclePolicy.archiveDirectory)
if (Test-Path $archiveRoot) { $archives = @(Get-ChildItem $archiveRoot -Recurse -File -Filter '*.md' | ForEach-Object { $_.FullName.Substring($root.Length + 1).Replace('\', '/') }) }
$state.archives = $archives
$temporaryPath = "$statePath.tmp"
$state | ConvertTo-Json -Depth 8 | Set-Content -Path $temporaryPath -Encoding UTF8
Move-Item -LiteralPath $temporaryPath -Destination $statePath -Force

[pscustomobject]@{ CompletedId = $oldId; Disposition = $Disposition; Current = $state.current; Archives = $state.archives } | ConvertTo-Json -Depth 8
