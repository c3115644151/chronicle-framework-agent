#Requires -Version 7.0

# The only place that knows where each category of files lives.
# A directory move changes this file and nothing else: gate scripts resolve
# paths through the layout instead of joining their own root with literals.

function Get-HarnessLayout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$HarnessRoot
    )

    $root = [IO.Path]::GetFullPath($HarnessRoot)
    $layout = [ordered]@{
        RepositoryRoot = [IO.Path]::GetFullPath((Join-Path (Join-Path $root '..') '..'))
        HarnessRoot    = $root
        StageRoot      = $root
        GateRoot       = $root
        DocsRoot       = $root
        ModRoot        = $root
        AgentHostRoot  = Join-Path $root 'AgentHost'
        ResearchRoot   = Join-Path $root 'Research'
        OpenSpecRoot   = Join-Path $root 'openspec'
        EvidenceRoot   = Join-Path $root 'TestResults'
        ToolRoot       = [IO.Path]::GetFullPath((Join-Path (Join-Path (Join-Path $root '..') '..') 'ApiProbe'))
    }
    return $layout
}

function Test-HarnessLayout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Layout
    )

    $required = @('HarnessRoot', 'StageRoot', 'GateRoot', 'DocsRoot', 'ModRoot', 'AgentHostRoot')
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
