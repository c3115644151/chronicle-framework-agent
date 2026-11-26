#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string[]]$RunDirectories,
    [string]$OutputPath
)

# Zero-model divergence criterion for the opening-survival scenario (#142). It does not drive the
# game or call a model. It aligns several finished LiveModel runs on their observable start
# (fixture hash, source commit, goal, model and output budget), extracts each run's Native action
# path from the full Host result, and decides whether comparable runs diverged. A "comparable"
# group must share the same start; runs from different checkpoints/commits/goals are reported but
# never used to claim divergence.
$ErrorActionPreference = 'Stop'

function Read-Json([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch { throw "Invalid JSON receipt: $Path" }
}

function Find-Receipt([string]$RunDirectory, [string]$Name) {
    $direct = Join-Path $RunDirectory $Name
    if (Test-Path -LiteralPath $direct -PathType Leaf) { return $direct }
    $nested = Join-Path (Join-Path $RunDirectory 'Temp') $Name
    if (Test-Path -LiteralPath $nested -PathType Leaf) { return $nested }
    return $null
}

function Get-ActionPath($HostResult) {
    if (-not $HostResult -or -not $HostResult.trace) { return @() }
    return @($HostResult.trace | ForEach-Object { [string]$_.decision.action } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-DecisionFingerprint($HostResult) {
    # Action names alone can converge while argument choices diverge (e.g. which item is bought).
    # Record each Native action together with its decision arguments so both shapes are visible.
    if (-not $HostResult -or -not $HostResult.trace) { return @() }
    return @($HostResult.trace | ForEach-Object {
        $action = [string]$_.decision.action
        if ([string]::IsNullOrWhiteSpace($action)) { return $null }
        $argObject = $_.decision.arguments
        if ($argObject) {
            $argPairs = @($argObject.PSObject.Properties | Where-Object { $_.Name -notin @('done','observeAgain','waitSeconds','control','goalClassification') } | ForEach-Object { '{0}={1}' -f $_.Name, $_.Value } | Sort-Object)
            if ($argPairs.Count -gt 0) { return ($action + '(' + ($argPairs -join ',') + ')') }
        }
        return $action
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

$runs = @()
foreach ($directory in $RunDirectories) {
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { throw "Run directory not found: $directory" }
    $livePath = Find-Receipt $directory 'LiveModelLoopResult.json'
    if (-not $livePath) { throw "Run has no LiveModelLoopResult.json: $directory" }
    $live = Read-Json $livePath
    $hostPath = Find-Receipt $directory 'AgentHostCampaignLoopResult.json'
    $hostResult = Read-Json $hostPath
    $path = @(Get-ActionPath $hostResult)
    $trace = $live.Trace
    $runs += [ordered]@{
        runDirectory = $directory
        passed = [bool]$live.Passed
        failure = [string]$live.Failure
        fixtureHash = if (-not [string]::IsNullOrWhiteSpace([string]$trace.FixtureHashBefore)) { [string]$trace.FixtureHashBefore } else { [string]$live.FixtureHashBefore }
        sourceCommit = [string]$trace.SourceCommit
        modelId = [string]$trace.ModelId
        goal = [string]$trace.Goal
        outputBudgetTokens = [int]$trace.ModelMaxOutputTokens
        actionsExecuted = if ($hostResult) { [int]$hostResult.actionsExecuted } else { [int]$trace.ActionsExecuted }
        actionPath = $path
        decisionFingerprint = ((@(Get-DecisionFingerprint $hostResult)) -join '>')
        actionFingerprint = ($path -join '>')
        hasFullHostReceipt = [bool]$hostResult
    }
}

# Same observable start = same fixture, commit, goal, model and output budget.
$startKey = @($runs | ForEach-Object {
    '{0}|{1}|{2}|{3}|{4}' -f $_.fixtureHash, $_.sourceCommit, $_.modelId, $_.outputBudgetTokens, $_.goal
} | Sort-Object -Unique)
$comparable = @($runs | Where-Object {
    $key = '{0}|{1}|{2}|{3}|{4}' -f $_.fixtureHash, $_.sourceCommit, $_.modelId, $_.outputBudgetTokens, $_.goal
    $key -ceq $startKey[0]
})
$fingerprints = @($comparable | ForEach-Object { $_.actionFingerprint } | Sort-Object -Unique)
$decisionFingerprints = @($comparable | ForEach-Object { $_.decisionFingerprint } | Sort-Object -Unique)
$fullReceiptComparable = @($comparable | Where-Object { $_.hasFullHostReceipt })
$diverged = ($fingerprints.Count -gt 1)
$result = [ordered]@{
    criterion = '#142 same-start path divergence (zero model)'
    evaluatedUtc = [DateTime]::UtcNow.ToString('O')
    runCount = $runs.Count
    startKeys = $startKey
    comparableStartCount = $comparable.Count
    comparableHasFullHostReceipt = ($fullReceiptComparable.Count -eq $comparable.Count)
    distinctActionFingerprints = $fingerprints.Count
    distinctDecisionFingerprints = $decisionFingerprints.Count
    actionShapeDiverged = $diverged
    argumentDiverged = ($decisionFingerprints.Count -gt 1)
    diverged = ($diverged -or $decisionFingerprints.Count -gt 1)
    comparableRunIds = @($comparable | ForEach-Object { Split-Path -Leaf $_.runDirectory })
    runs = $runs
}
if (-not $result.comparableHasFullHostReceipt) {
    $result.diverged = $false
    $result.limitation = 'At least one comparable run lacks the full Host receipt; path divergence cannot be judged from terminal receipts alone.'
}
if ($comparable.Count -lt 2) {
    $result.diverged = $false
    $result.limitation = 'Fewer than two runs share the same observable start; no divergence claim is possible.'
}
$json = $result | ConvertTo-Json -Depth 10
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $json | Set-Content -LiteralPath $OutputPath -Encoding UTF8
}
$json
