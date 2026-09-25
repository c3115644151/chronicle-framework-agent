[CmdletBinding()]
param(
    [switch]$Review
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
. (Join-Path $root 'HarnessResearchReadiness.ps1')
$statePath = Join-Path $root 'ContextState.json'
$mainlinePath = Join-Path $root 'Focus\MAINLINE.md'
if (-not (Test-Path $statePath)) { throw "Context state is missing: $statePath" }
if (-not (Test-Path $mainlinePath)) { throw "Current mainline document is missing: $mainlinePath" }

$state = Get-Content $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $Review) { throw 'Use -Review after editing Focus/MAINLINE.md. Work-item status is managed in GitHub Project, not ContextState.' }

$now = [DateTime]::UtcNow
$reviewDays = [int]$state.lifecyclePolicy.reviewIntervalDays
$state.current.path = 'Focus/MAINLINE.md'
$state.current.reviewedUtc = $now.ToString('O')
$state.current.reviewAfterUtc = $now.AddDays($reviewDays).ToString('O')
$state.current.mainlineSha256 = Get-ChronicleCanonicalFileSha256 -LiteralPath $mainlinePath

$archiveRoot = Join-Path $root ([string]$state.lifecyclePolicy.archiveDirectory)
$archives = @()
if (Test-Path $archiveRoot) {
    $archives = @(Get-ChildItem $archiveRoot -Recurse -File -Filter '*.md' | ForEach-Object {
        $_.FullName.Substring($root.Length + 1).Replace('\', '/')
    })
}
$state.archives = $archives

$temporaryPath = "$statePath.tmp"
$state | ConvertTo-Json -Depth 8 | Set-Content -Path $temporaryPath -Encoding UTF8
Move-Item -LiteralPath $temporaryPath -Destination $statePath -Force

[pscustomobject]@{
    Updated = $true
    FocusPath = $state.current.path
    ReviewedUtc = $state.current.reviewedUtc
    ReviewAfterUtc = $state.current.reviewAfterUtc
    MainlineSha256 = $state.current.mainlineSha256
    DefaultRead = $state.defaultRead
    References = $state.references
    Archives = $state.archives
} | ConvertTo-Json -Depth 8
