[CmdletBinding()]
param(
    [ValidateRange(5,5)][int]$Runs = 5,
    [int]$WallClockLimitSeconds = 180,
    [double]$CampaignDayLimit = 0.1,
    [ValidateRange(5,30)][int]$FrameRate = 10
)

$ErrorActionPreference = 'Stop'
$liveTest = Join-Path $PSScriptRoot 'Test-AgentLiveModelLoop.ps1'
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$outerTemp = $env:CHRONICLE_HARNESS_TEMP
if (-not $outerTemp -or -not (Test-Path -LiteralPath $outerTemp -PathType Container)) { throw 'Candidate evaluation requires an active Run-Harness TestResults temp directory.' }
$evaluationRoot = Split-Path -Parent $outerTemp
$modelName = [string][Environment]::GetEnvironmentVariable('CHRONICLE_LLM_MODEL','Process')
if ([string]::IsNullOrWhiteSpace($modelName)) { $modelName = [string][Environment]::GetEnvironmentVariable('CHRONICLE_LLM_MODEL','User') }
if ([string]::IsNullOrWhiteSpace($modelName)) { throw 'Candidate evaluation requires a locally configured model name; credentials are never displayed.' }
$results = [System.Collections.Generic.List[object]]::new()

for ($runIndex = 1; $runIndex -le $Runs; $runIndex++) {
    if (Get-Process -Name Bannerlord* -ErrorAction SilentlyContinue) { throw "Candidate evaluation run $runIndex found a Bannerlord client left by the preceding run." }
    if (Test-Path -LiteralPath $sessionPath -PathType Leaf) { throw "Candidate evaluation run $runIndex found a stale Agent session; no session may be overwritten." }
    $runDirectory = Join-Path $evaluationRoot ('ModelCandidateRun-' + $runIndex.ToString('00'))
    $runTemp = Join-Path $runDirectory 'Temp'
    New-Item -ItemType Directory -Force -Path $runTemp | Out-Null
    $env:CHRONICLE_HARNESS_TEMP = $runTemp
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    $output = $null
    $exitCode = 1
    $liveResult = $null
    $failure = $null
    try {
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $liveTest -RecruitmentLoop -FrameRate $FrameRate 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
        $resultPath = Join-Path $runTemp 'LiveModelLoopResult.json'
        if (Test-Path -LiteralPath $resultPath -PathType Leaf) { $liveResult = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json }
        if ($exitCode -ne 0) { $failure = if ($liveResult -and $liveResult.Failure) { [string]$liveResult.Failure } else { "Live-model child exited $exitCode without a structured failure result." } }
        if (-not $liveResult) { $failure = 'Live-model child produced no structured LiveModelLoopResult.' }
    }
    catch { $failure = $_.Exception.Message }
    finally {
        $stopwatch.Stop()
        $env:CHRONICLE_HARNESS_TEMP = $outerTemp
    }

    if (Get-Process -Name Bannerlord* -ErrorAction SilentlyContinue) { $failure = if ($failure) { $failure + '; Bannerlord process leaked from candidate run.' } else { 'Bannerlord process leaked from candidate run.' } }
    if (Test-Path -LiteralPath $sessionPath -PathType Leaf) { $failure = if ($failure) { $failure + '; Agent session file remained after candidate run.' } else { 'Agent session file remained after candidate run.' } }

    $trace = if ($liveResult -and $liveResult.Trace) { @($liveResult.Trace.Trace) } else { @() }
    $moves = @($trace | Where-Object { $_.decision.action -eq 'move' -and $_.actionExecuted })
    $offerSteps = @($trace | Where-Object { $_.decision.action -eq 'recruitOptions' -and $_.actionExecuted })
    $recruits = @($trace | Where-Object { $_.decision.action -eq 'recruit' -and $_.actionExecuted })
    $elapsedDays = $null
    if ($trace.Count -gt 0) { $elapsedDays = [double]$trace[-1].observationAfter.campaignDay - [double]$trace[0].observationBefore.campaignDay }
    $visualCoverage = if ($liveResult -and $liveResult.Capture) { [double]$liveResult.Capture.FrameCoverageRatio } else { 0.0 }
    $runPassed = (
        -not $failure -and $exitCode -eq 0 -and $liveResult.Passed -and
        $liveResult.Trace.RecruitmentVerified -and $liveResult.FixtureUnchanged -and $liveResult.ProcessStopped -and
        $moves.Count -eq 1 -and $recruits.Count -eq 1 -and
        $stopwatch.Elapsed.TotalSeconds -le $WallClockLimitSeconds -and
        $null -ne $elapsedDays -and $elapsedDays -le $CampaignDayLimit -and
        $visualCoverage -ge 0.9 -and [bool]$liveResult.Capture.VideoRemovedAfterEvidence
    )
    if (-not $runPassed -and -not $failure) { $failure = 'Candidate run failed one or more predeclared repeatability thresholds.' }
    $results.Add([pscustomobject]@{
        Run = $runIndex
        Passed = $runPassed
        Failure = $failure
        HarnessRunDirectory = $runDirectory
        Model = $modelName
        RunWallClockSeconds = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 3)
        CampaignDaysElapsed = $elapsedDays
        MoveCount = $moves.Count
        RecruitCount = $recruits.Count
        RecruitmentVerified = if ($liveResult) { [bool]$liveResult.Trace.RecruitmentVerified } else { $false }
        FixtureUnchanged = if ($liveResult) { [bool]$liveResult.FixtureUnchanged } else { $false }
        ProcessStopped = if ($liveResult) { [bool]$liveResult.ProcessStopped -and -not (Get-Process -Name Bannerlord* -ErrorAction SilentlyContinue) } else { $false }
        VisualCoverageRatio = $visualCoverage
        SourceClipRemovedAfterEvidence = if ($liveResult -and $liveResult.Capture) { [bool]$liveResult.Capture.VideoRemovedAfterEvidence } else { $false }
        TargetSettlementId = if ($liveResult) { [string]$liveResult.Trace.ChosenSettlementId } else { $null }
        RecruitmentOfferCount = if ($offerSteps.Count -eq 1) { @($offerSteps[0].actionReceipt.data.offers | Where-Object { $_.available }).Count } else { $null }
    })
}

$resultsArray = @($results)
$passedRuns = @($resultsArray | Where-Object { $_.Passed }).Count
$result = [ordered]@{
    ProviderKind = 'Configured local real-model candidate; not a deterministic baseline'
    Model = $modelName
    RunCount = $Runs
    DistinctCampaignSeeds = 1
    PredeclaredThreshold = [ordered]@{ successRuns = $Runs; maxSecondsPerRun = $WallClockLimitSeconds; maxCampaignDaysPerRun = $CampaignDayLimit; requiredNativeMoveCount = 1; requiredNativeRecruitCount = 1; minVisualCoverage = 0.9; fixtureUnchanged = $true; processStopped = $true }
    SuccessfulRuns = $passedRuns
    Passed = ($passedRuns -eq $Runs)
    Results = $resultsArray
}
$json = $result | ConvertTo-Json -Depth 12
if ($outerTemp -and (Test-Path -LiteralPath $outerTemp -PathType Container)) { Set-Content -LiteralPath (Join-Path $outerTemp 'LiveModelRecruitmentEvaluation.json') -Value $json -Encoding UTF8 }
$json
if (-not $result.Passed) { exit 1 }
