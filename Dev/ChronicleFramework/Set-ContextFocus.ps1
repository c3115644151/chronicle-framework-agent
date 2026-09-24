[CmdletBinding()]
param(
    [string]$Id,
    [string]$Objective,
    [string]$Phase,
    [switch]$Review
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$statePath = Join-Path $root 'ContextState.json'
$mainlinePath = Join-Path $root 'Focus\MAINLINE.md'
if (-not (Test-Path $statePath)) { throw "Context state is missing: $statePath" }
if (-not (Test-Path $mainlinePath)) { throw "Current mainline document is missing: $mainlinePath" }

$state = Get-Content $statePath -Raw | ConvertFrom-Json
if ($Review) {
    if (-not $Id) { $Id = [string]$state.current.id }
    if (-not $Objective) { $Objective = [string]$state.current.objective }
    if (-not $Phase) { $Phase = [string]$state.current.phase }
}
foreach ($value in @($Id, $Objective, $Phase)) {
    if ([string]::IsNullOrWhiteSpace($value)) { throw 'Id, Objective and Phase are required when setting context focus.' }
}

$now = [DateTime]::UtcNow
$reviewDays = [int]$state.lifecyclePolicy.reviewIntervalDays
$state.current.id = $Id
$state.current.objective = $Objective
$state.current.phase = $Phase
$state.current.path = 'Focus/MAINLINE.md'
$state.current.updatedUtc = $now.ToString('O')
$state.current.reviewAfterUtc = $now.AddDays($reviewDays).ToString('O')
$state.current.mainlineSha256 = (Get-FileHash $mainlinePath -Algorithm SHA256).Hash.ToLowerInvariant()

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
    Current = $state.current
    DefaultRead = $state.defaultRead
    References = $state.references
    Archives = $state.archives
} | ConvertTo-Json -Depth 8
