#Requires -Version 7.0
[CmdletBinding()]
param(
    [string[]]$Tag = @(),
    [switch]$IncludeArchive
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$state = Get-Content (Join-Path $root 'ContextState.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$openSpecHarnessPath = Join-Path $root 'OpenSpecHarness.ps1'
if (-not (Test-Path -LiteralPath $openSpecHarnessPath -PathType Leaf)) { throw 'OpenSpec Harness integration is missing.' }
. $openSpecHarnessPath
$openSpecSummary = Get-OpenSpecWorkspaceSummary
$paths = [Collections.Generic.List[string]]::new()
foreach ($path in $state.defaultRead) { if (-not $paths.Contains([string]$path)) { $paths.Add([string]$path) } }

if ($Tag.Count -gt 0) {
    foreach ($reference in $state.references) {
        if (@($reference.tags | Where-Object { $_ -in $Tag }).Count -gt 0 -and -not $paths.Contains([string]$reference.path)) {
            $paths.Add([string]$reference.path)
        }
    }
}
if ($IncludeArchive) {
    foreach ($path in $state.archives) { if (-not $paths.Contains([string]$path)) { $paths.Add([string]$path) } }
}

$documents = @($paths | ForEach-Object {
    $absolutePath = Join-Path $root $_
    [pscustomobject]@{
        Path = $_
        AbsolutePath = $absolutePath
        Exists = Test-Path $absolutePath
        Tier = if ($_ -eq $state.current.path) { 'active' } elseif ($_ -like 'Archive/*') { 'archive' } elseif ($_ -like 'Research/*') { 'reference' } else { 'core' }
    }
})

[pscustomobject]@{
    Current = $state.current
    Documents = $documents
    OpenSpec = $openSpecSummary
} | ConvertTo-Json -Depth 8
