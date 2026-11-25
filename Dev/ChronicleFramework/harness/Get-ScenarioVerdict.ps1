
#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RunPath,
    [string]$Scenario = $null,
    [string]$OutFile
)

# Read one live-model run back as a scenario receipt. The progress log the Host
# already writes carries an observation per decision, so a run that never
# finished its stated objective still yields the quantities a scenario is
# judged on: how much Campaign time passed, what the party lost or gained, how
# many decisions went to waiting or to a refused stop, and whether every
# decision ended in an action, a control, or a classification.
#
# The log mixes two shapes: the Campaign loop answers with {control|action} and
# the objective sub-loops answer with boolean flags ({stop:true},
# {observeAgain:true}) or a classification ({goalClassification}). A reader that
# only knew the first shape would report zero stops on a run that asked to stop
# four times, so both are normalised here.

$ErrorActionPreference = 'Stop'

$runDirectory = (Resolve-Path -LiteralPath $RunPath -ErrorAction Stop).ProviderPath
if (-not (Test-Path -LiteralPath $runDirectory -PathType Container)) { throw "The scenario run path is not a directory: $runDirectory" }
$progressPath = Join-Path $runDirectory 'Temp\AgentHostProgress.jsonl'
if (-not (Test-Path -LiteralPath $progressPath -PathType Leaf)) { throw "No Agent Host progress log in this run: $progressPath" }
$resultPath = Join-Path $runDirectory 'Temp\LiveModelLoopResult.json'

function Read-Number {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [bool]) { return $null }
    return [double]$Value
}

function Read-Text {
    param($Value)
    if ($null -eq $Value) { return $null }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return $text
}

$records = @(Get-Content -LiteralPath $progressPath -Encoding UTF8 |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    ForEach-Object { $_ | ConvertFrom-Json })
if ($records.Count -eq 0) { throw "The Agent Host progress log is empty: $progressPath" }

$decisionRecords = @($records | Where-Object { [string]$_.event -ceq 'provider-decision' })
$subflowRecords = @($records | Where-Object { [string]$_.event -ceq 'objective-subflow-result' })

# Samples stay in log order: a subflow record is written when the subflow ends,
# but its before-state was captured at its start, so re-grouping all decisions
# first would make Campaign time look as if it moved backwards.
$samples = [System.Collections.Generic.List[object]]::new()
function Add-StateSample {
    param([string]$Source, $Record, $State)
    if ($null -eq $State) { return }
    $samples.Add([pscustomobject][ordered]@{
        source = $Source
        utc = [string]$Record.utc
        objectiveId = Read-Text $Record.objectiveId
        campaignDay = Read-Number $State.campaignDay
        gold = Read-Number $State.gold
        members = Read-Number $State.partyMembers
        healthy = Read-Number $State.partyHealthy
        wounded = Read-Number $State.partyWounded
        prisoners = Read-Number $State.partyPrisoners
        morale = Read-Number $State.partyMorale
        food = Read-Number $State.partyFood
        gameState = Read-Text $State.gameState
        menuId = Read-Text $State.menuId
    })
}
foreach ($record in $records) {
    $event = [string]$record.event
    if ($event -ceq 'provider-decision') {
        Add-StateSample -Source 'decision' -Record $record -State $record.observation
    }
    elseif ($event -ceq 'objective-subflow-result') {
        Add-StateSample -Source 'subflow-before' -Record $record -State $record.nativeStateBefore
        Add-StateSample -Source 'subflow-after' -Record $record -State $record.nativeStateAfter
    }
}

function Get-FirstValue {
    param([string]$Property)
    $hit = $samples | Where-Object { $null -ne $_.$Property } | Select-Object -First 1
    if ($null -eq $hit) { return $null }
    return $hit.$Property
}
function Get-LastValue {
    param([string]$Property)
    $hit = $samples | Where-Object { $null -ne $_.$Property } | Select-Object -Last 1
    if ($null -eq $hit) { return $null }
    return $hit.$Property
}
function Get-MinValue {
    param([string]$Property)
    $values = @($samples | Where-Object { $null -ne $_.$Property } | ForEach-Object { $_.$Property })
    if ($values.Count -eq 0) { return $null }
    return [double]($values | Measure-Object -Minimum).Minimum
}

$dayStart = Get-FirstValue 'campaignDay'
$dayEnd = Get-LastValue 'campaignDay'

$decisionTimeline = @($decisionRecords | ForEach-Object {
    $control = Read-Text $_.decision.control
    if (-not $control) {
        foreach ($flag in @('stop', 'observeAgain', 'done')) {
            if ($_.decision.$flag -eq $true) { $control = $flag; break }
        }
    }
    $action = Read-Text $_.decision.action
    $goalClassification = Read-Text $_.decision.goalClassification
    $argumentText = $null
    if ($null -ne $_.decision.arguments) {
        $argumentText = ($_.decision.arguments | ConvertTo-Json -Compress -Depth 4)
        if ($argumentText.Length -gt 120) { $argumentText = $argumentText.Substring(0, 117) + '...' }
    }
    [pscustomobject][ordered]@{
        utc = [string]$_.utc
        objectiveId = Read-Text $_.objectiveId
        scope = Read-Text $_.scope
        campaignDay = Read-Number $_.observation.campaignDay
        gold = Read-Number $_.observation.gold
        control = $control
        action = $action
        goalClassification = $goalClassification
        arguments = $argumentText
        feedbackKind = Read-Text $_.decisionFeedbackKind
        promptTokens = Read-Number $_.promptTokens
        completionTokens = Read-Number $_.completionTokens
    }
})

$unusableDecisions = @($decisionTimeline | Where-Object { -not $_.control -and -not $_.action -and -not $_.goalClassification })
$stopRequests = @($decisionTimeline | Where-Object { $_.control -ceq 'stop' })
$refusedStops = @($decisionTimeline | Where-Object { $_.control -ceq 'stop' -and $_.feedbackKind -ceq 'safe-stop-rejected-with-observe-again-control' })
$waits = @($decisionTimeline | Where-Object { $_.control -ceq 'observeAgain' })
$doneControls = @($decisionTimeline | Where-Object { $_.control -ceq 'done' })
$actionDecisions = @($decisionTimeline | Where-Object { $null -ne $_.action })
$actionCounts = [ordered]@{}
foreach ($group in ($actionDecisions | Group-Object -Property action | Sort-Object -Property Count -Descending)) {
    $actionCounts[$group.Name] = $group.Count
}

# Campaign day is judged per series, not across the merged sample list. A
# decision's observation is the state the model actually saw, so that series
# must never go backwards; a subflow window is judged on its own ends because
# its before-state is captured when the subflow starts and written down when it
# ends. Comparing the two against each other reports a regression on every run
# whose subflow began before the decisions that follow it.
$decisionDaySteps = 0
$previousDecisionDay = $null
foreach ($sample in @($samples | Where-Object { $_.source -ceq 'decision' })) {
    if ($null -eq $sample.campaignDay) { continue }
    if ($null -ne $previousDecisionDay -and $sample.campaignDay -lt $previousDecisionDay) { $decisionDaySteps++ }
    $previousDecisionDay = $sample.campaignDay
}
$subflowWindows = 0
$subflowWindowRegressions = 0
foreach ($record in $subflowRecords) {
    $beforeDay = Read-Number $record.nativeStateBefore.campaignDay
    $afterDay = Read-Number $record.nativeStateAfter.campaignDay
    if ($null -eq $beforeDay -or $null -eq $afterDay) { continue }
    $subflowWindows++
    if ($afterDay -lt $beforeDay) { $subflowWindowRegressions++ }
}
$nonMonotonicDays = $decisionDaySteps + $subflowWindowRegressions

$objectiveRuns = @($subflowRecords | ForEach-Object {
    [pscustomobject][ordered]@{
        objectiveId = Read-Text $_.objectiveId
        status = Read-Text $_.status
        termination = Read-Text $_.termination
        failureCode = Read-Text $_.failureCode
        actionsExecuted = Read-Number $_.actionsExecuted
        decisions = Read-Number $_.decisions
        completionVerified = if ($null -eq $_.verification) { $null } else { [bool]$_.verification.verified }
    }
})

$loopResult = $null
if (Test-Path -LiteralPath $resultPath -PathType Leaf) {
    $loopResult = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
}
$loopTrace = $loopResult.Trace
$actionsExecuted = Read-Number $loopTrace.ActionsExecuted
$hostTermination = Read-Text $loopTrace.Termination.reason
$hostFailureCode = Read-Text $loopTrace.HostFailureCode
$goalVerified = if ($null -eq $loopTrace.Termination) { $null } else { [bool]$loopTrace.Termination.goalVerified }

$checks = [System.Collections.Generic.List[object]]::new()
function Add-Check {
    param([string]$Name, [bool]$Passed, [string]$Detail)
    $checks.Add([pscustomobject][ordered]@{ name = $Name; passed = $Passed; detail = $Detail })
}

$stateSampleCount = @($samples | Where-Object { $null -ne $_.campaignDay }).Count
Add-Check -Name 'observations-carry-campaign-state' -Passed ($stateSampleCount -gt 0) -Detail ("{0} of {1} samples carried a Campaign day; a decision that observed nothing cannot be judged." -f $stateSampleCount, $samples.Count)
Add-Check -Name 'campaign-time-monotonic' -Passed ($nonMonotonicDays -eq 0) -Detail ("{0} decisions observed Campaign day going backwards and {1} of {2} objective windows ended before they started." -f $decisionDaySteps, $subflowWindowRegressions, $subflowWindows)
Add-Check -Name 'party-survived' -Passed ($null -eq (Get-LastValue 'members') -or (Get-LastValue 'members') -ge 1) -Detail ("Party members started at {0} and ended at {1}." -f (Get-FirstValue 'members'), (Get-LastValue 'members'))
Add-Check -Name 'every-decision-ended-in-action-control-or-classification' -Passed ($unusableDecisions.Count -eq 0) -Detail ("{0} of {1} decisions named neither an action, a control, nor a classification." -f $unusableDecisions.Count, $decisionRecords.Count)
$terminal = @($subflowRecords | Where-Object { (Read-Text $_.status) -in @('completed', 'failed') })
$receiptText = if ($null -eq $loopResult) { 'no' } else { 'one' }
Add-Check -Name 'run-reached-a-terminal-outcome' -Passed ($null -ne $loopResult -or $terminal.Count -gt 0 -or $null -ne $hostTermination) -Detail ("{0} terminal objective records, {1} loop receipt, Host termination '{2}'." -f $terminal.Count, $receiptText, $hostTermination)

$verdict = [ordered]@{
    run = Split-Path -Leaf $runDirectory
    scenario = $Scenario
    modelId = Read-Text ($decisionRecords | Select-Object -First 1).modelId
    decisions = $decisionRecords.Count
    decisionsWithAction = $actionDecisions.Count
    actionsExecuted = $actionsExecuted
    actionCounts = $actionCounts
    stopRequests = $stopRequests.Count
    refusedStops = $refusedStops.Count
    waits = $waits.Count
    doneControls = $doneControls.Count
    campaignDayStart = $dayStart
    campaignDayEnd = $dayEnd
    campaignDaysElapsed = if ($null -ne $dayStart -and $null -ne $dayEnd) { [Math]::Round($dayEnd - $dayStart, 3) } else { $null }
    goldStart = Get-FirstValue 'gold'
    goldEnd = Get-LastValue 'gold'
    membersStart = Get-FirstValue 'members'
    membersEnd = Get-LastValue 'members'
    foodStart = Get-FirstValue 'food'
    foodEnd = Get-LastValue 'food'
    minFood = Get-MinValue 'food'
    minMorale = Get-MinValue 'morale'
    prisonersStart = Get-FirstValue 'prisoners'
    prisonersEnd = Get-LastValue 'prisoners'
    hostTermination = $hostTermination
    hostFailureCode = $hostFailureCode
    goalVerified = $goalVerified
    promptTokens = [long](@($decisionRecords | ForEach-Object { Read-Number $_.promptTokens }) | Measure-Object -Sum).Sum
    completionTokens = [long](@($decisionRecords | ForEach-Object { Read-Number $_.completionTokens }) | Measure-Object -Sum).Sum
    objectiveRuns = $objectiveRuns
    checks = $checks
    passed = (@($checks | Where-Object { -not $_.passed }).Count -eq 0)
    timeline = $decisionTimeline
}

$outPath = if ([string]::IsNullOrWhiteSpace($OutFile)) { Join-Path (Split-Path -Parent $progressPath) 'ScenarioVerdict.json' } else { $OutFile }
$verdict | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $outPath -Encoding UTF8

$failed = @($checks | Where-Object { -not $_.passed })
foreach ($check in $checks) { "{0}  {1}  {2}" -f $(if ($check.passed) { 'pass' } else { 'FAIL' }), $check.name, $check.detail }
"decisions={0} actions={1}/{2} waits={3} stops={4}(refused {5}) days={6} gold={7}->{8} members={9}->{10} termination={11} verdict={12}" -f $verdict.decisions, $verdict.decisionsWithAction, $verdict.actionsExecuted, $verdict.waits, $verdict.stopRequests, $verdict.refusedStops, $verdict.campaignDaysElapsed, $verdict.goldStart, $verdict.goldEnd, $verdict.membersStart, $verdict.membersEnd, $hostTermination, $(if ($failed.Count -eq 0) { 'passed' } else { 'failed' })
"receipt: {0}" -f $outPath
if ($failed.Count -gt 0) { exit 1 }
