#Requires -Version 7.0

# The only place that knows where each category of files lives.
# A directory move changes this file and nothing else: gate scripts resolve
# paths through the layout instead of joining their own root with literals.

function Get-HarnessLayout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot
    )

    $root = [IO.Path]::GetFullPath($ProjectRoot)
    $harnessRoot = Join-Path $root 'harness'
    $docsRoot = Join-Path $root 'docs'
    $modRoot = Join-Path $root 'mod'
    $layout = [ordered]@{
        RepositoryRoot     = [IO.Path]::GetFullPath((Join-Path (Join-Path $root '..') '..'))
        ProjectRoot        = $root
        HarnessRoot        = $harnessRoot
        StageRoot          = $harnessRoot
        GateRoot           = $harnessRoot
        DocsRoot           = $docsRoot
        ModRoot            = $modRoot
        ModulePackageRoot  = Join-Path $modRoot 'module'
        AgentHostRoot      = Join-Path $root 'agenthost'
        ResearchRoot       = Join-Path $docsRoot 'Research'
        OpenSpecRoot       = Join-Path $root 'openspec'
        EvidenceRoot       = Join-Path $root 'TestResults'
        ToolRoot           = Join-Path $root 'tools'
    }
    return $layout
}

function Test-HarnessLayout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Layout
    )

    $required = @('ProjectRoot', 'HarnessRoot', 'DocsRoot', 'ModRoot', 'ModulePackageRoot', 'AgentHostRoot', 'ToolRoot')
    $failures = New-Object System.Collections.Generic.List[string]
    foreach ($key in $required) {
        $path = [string]$Layout[$key]
        if ([string]::IsNullOrWhiteSpace($path)) {
            $failures.Add("Harness layout entry is empty: $key")
            continue
        }
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            $failures.Add("Harness layout directory is missing: $key -> $path")
        }
    }
    return $failures.ToArray()
}
