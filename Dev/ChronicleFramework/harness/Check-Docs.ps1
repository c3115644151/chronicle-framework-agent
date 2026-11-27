#Requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$stageRoot = $PSScriptRoot
. (Join-Path $stageRoot 'HarnessPaths.ps1')
$layout = Get-HarnessLayout -ProjectRoot (Split-Path -Parent $stageRoot)
$harnessRoot = [string]$layout.ProjectRoot
$stageRoot = [string]$layout.StageRoot
$agentHostRoot = [string]$layout.AgentHostRoot
$modRoot = [string]$layout.ModRoot
$modulePackageRoot = [string]$layout.ModulePackageRoot
$docsRoot = [string]$layout.DocsRoot
$gateRoot = [string]$layout.GateRoot

# One source artifact name, resolved through the layout instead of the caller's directory.
function Resolve-SourceArtifact {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)

    if ($Name -like '*.ps1') { return (Join-Path $stageRoot $Name) }
    if ($Name -like '*.cs' -or $Name -like '*.csproj') { return (Join-Path $modRoot $Name) }
    return (Join-Path $harnessRoot $Name)
}

$localSettingsPath = Join-Path $harnessRoot 'harness.local.json'
$localSettings = if (Test-Path -LiteralPath $localSettingsPath) { Get-Content -LiteralPath $localSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
$projectRoot = if ($localSettings -and $localSettings.repositoryRoot) { [IO.Path]::GetFullPath([string]$localSettings.repositoryRoot) } else { [string]$layout.RepositoryRoot }
$contractVersion = '7.734'
$openSpecHarnessPath = Join-Path $stageRoot 'OpenSpecHarness.ps1'
if (-not (Test-Path -LiteralPath $openSpecHarnessPath -PathType Leaf)) { throw 'OpenSpec Harness integration is missing.' }
. $openSpecHarnessPath
$openSpecSummary = Get-OpenSpecWorkspaceSummary -Validate
if ([IO.Path]::GetFullPath([string]$openSpecSummary.Root) -ne [IO.Path]::GetFullPath($harnessRoot)) { throw 'OpenSpec resolved a different workspace root than the Chronicle Harness.' }
if ($openSpecSummary.ActiveChangeCount -gt 1) { throw 'OpenSpec must contain at most one active change; GitHub Project remains the product task board.' }
$contextState = Get-Content (Join-Path $docsRoot 'ContextState.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$taskTrackerUrl = [string]$contextState.taskTracker.projectUrl
$requiredRootPaths = @('DEVELOPMENT.md', 'DESIGN.md', 'SYSTEM_INVENTORY.md', 'RUNLOG.md')
$routedPaths = @(
    $requiredRootPaths
    @($contextState.defaultRead | ForEach-Object { [string]$_ })
    @([string]$contextState.current.path)
    @($contextState.references | ForEach-Object { [string]$_.path })
    @($contextState.archives | ForEach-Object { [string]$_ })
) | ForEach-Object { ([string]$_).Replace('/', '\') } | Sort-Object -Unique

# Gate checks are split by subject under the gate root and run in this script's scope,
# in numeric order, so a later subject can read whatever an earlier one loaded.
$gateDriverPath = $PSCommandPath
$gateScripts = @(Get-ChildItem -Path $gateRoot -File -Filter '*.ps1' | Sort-Object Name)
if ($gateScripts.Count -eq 0) { throw "No gate subject scripts found under $gateRoot." }
foreach ($gateScript in $gateScripts) {
    . $gateScript.FullName
}

[pscustomobject]@{
    Passed = $true
    ContractVersion = $contractVersion
    MarkdownFiles = $activeFiles.Count
    ArchiveFiles = @($actualFiles | Where-Object { $_.FullName -like '*\Archive\*' }).Count
    CatalogSystemRows = $inventoryIds.Count
    CatalogMappedSystemRows = $catalogMappedSystemIds.Count
    CatalogActionRows = @($catalogIdDefinitions | Where-Object { $_.StartsWith('ACT-', [System.StringComparison]::Ordinal) }).Count
    CatalogObservationRows = @($catalogIdDefinitions | Where-Object { $_.StartsWith('OBS-', [System.StringComparison]::Ordinal) }).Count
    CatalogNARows = @($catalogIdDefinitions | Where-Object { $_.StartsWith('N/A-', [System.StringComparison]::Ordinal) }).Count
    MarkdownBytes = $totalBytes
    DefaultReadMarkdownBytes = $defaultReadBytes
    TaskTrackerUrl = $taskTrackerUrl
    OpenSpec = $openSpecSummary
    CheckedUtc = (Get-Date).ToUniversalTime().ToString('O')
} | ConvertTo-Json -Depth 8
