[CmdletBinding()]
param(
    [ValidateRange(1,3)][int]$Runs = 3,
    [int]$WallClockLimitSeconds = 300,
    [ValidateRange(5,30)][int]$FrameRate = 10
)

$ErrorActionPreference = 'Stop'
$liveTest = Join-Path $PSScriptRoot 'Test-AgentLiveModelLoop.ps1'
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$outerTemp = $env:CHRONICLE_HARNESS_TEMP
if (-not $outerTemp -or -not (Test-Path -LiteralPath $outerTemp -PathType Container)) { throw 'Supply candidate evaluation requires an active Run-Harness TestResults temp directory.' }
$evaluationRoot = Split-Path -Parent $outerTemp
$modelName = [string][Environment]::GetEnvironmentVariable('CHRONICLE_LLM_MODEL','Process')
if ([string]::IsNullOrWhiteSpace($modelName)) { $modelName = [string][Environment]::GetEnvironmentVariable('CHRONICLE_LLM_MODEL','User') }
if ([string]::IsNullOrWhiteSpace($modelName)) { throw 'Supply candidate evaluation requires a locally configured model name; credentials are never displayed.' }
$results = [System.Collections.Generic.List[object]]::new()

for ($runIndex = 1; $runIndex -le $Runs; $runIndex++) {
    if (Get-Process -Name Bannerlord* -ErrorAction SilentlyContinue) { throw "Supply candidate run $runIndex found a Bannerlord client left by the preceding run." }
    if (Test-Path -LiteralPath $sessionPath -PathType Leaf) { throw "Supply candidate run $runIndex found a stale Agent session; no session may be overwritten." }
    $runDirectory = Join-Path $evaluationRoot ('SupplyModelRun-' + $runIndex.ToString('00'))
    $runTemp = Join-Path $runDirectory 'Temp'
    New-Item -ItemType Directory -Force -Path $runTemp | Out-Null
    $env:CHRONICLE_HARNESS_TEMP = $runTemp
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    $liveResult = $null
    $failure = $null
    $exitCode = 1
    try {
        $null = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $liveTest -SupplyManagementLoop -FrameRate $FrameRate 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
        $resultPath = Join-Path $runTemp 'LiveModelLoopResult.json'
        if (Test-Path -LiteralPath $resultPath -PathType Leaf) { $liveResult = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json }
        if ($exitCode -ne 0) { $failure = if ($liveResult -and $liveResult.Failure) { [string]$liveResult.Failure } else { "Supply live-model child exited $exitCode without a structured result." } }
        if (-not $liveResult) { $failure = 'Supply live-model child produced no structured LiveModelLoopResult.' }
    }
    catch { $failure = $_.Exception.Message }
    finally {
        $stopwatch.Stop()
        $env:CHRONICLE_HARNESS_TEMP = $outerTemp
    }

    if (Get-Process -Name Bannerlord* -ErrorAction SilentlyContinue) { $failure = if ($failure) { $failure + '; Bannerlord process leaked from candidate run.' } else { 'Bannerlord process leaked from candidate run.' } }
    if (Test-Path -LiteralPath $sessionPath -PathType Leaf) { $failure = if ($failure) { $failure + '; Agent session file remained after candidate run.' } else { 'Agent session file remained after candidate run.' } }
    $trace = if ($liveResult -and $liveResult.Trace) { $liveResult.Trace } else { $null }
    $supply = if ($trace -and $trace.SupplyVerification) { $trace.SupplyVerification } else { $null }
    $visualCoverage = if ($liveResult -and $liveResult.Capture) { [double]$liveResult.Capture.FrameCoverageRatio } else { 0.0 }
    $sourceClipRemoved = [bool]($liveResult -and $liveResult.Capture -and $liveResult.Capture.VideoRemovedAfterEvidence)
    $runPassed = (
        -not $failure -and $exitCode -eq 0 -and [bool]$liveResult.Passed -and [bool]$trace.SupplyVerified -and
        [bool]$liveResult.FixtureUnchanged -and [bool]$liveResult.ProcessStopped -and
        $stopwatch.Elapsed.TotalSeconds -le $WallClockLimitSeconds -and
        [int]$trace.Decisions -le 24 -and $visualCoverage -ge 0.9 -and $sourceClipRemoved
    )
    if (-not $runPassed -and -not $failure) { $failure = 'Candidate run failed one or more predeclared supply, resource, visual, cleanup, or budget thresholds.' }
    $results.Add([pscustomobject]@{
        Run = $runIndex
        Passed = $runPassed
        Failure = $failure
        Model = if ($trace) { [string]$trace.ModelId } else { $modelName }
        ModelMaxOutputTokens = if ($trace) { [int]$trace.ModelMaxOutputTokens } else { $null }
        SourceCommit = if ($trace) { [string]$trace.SourceCommit } else { $null }
        SourceTrackedTreeClean = if ($trace) { [bool]$trace.SourceTrackedTreeClean } else { $false }
        HarnessRunDirectory = $runDirectory
        RunWallClockSeconds = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 3)
        DecisionCount = if ($trace) { [int]$trace.Decisions } else { 0 }
        CampaignDaysElapsed = if ($supply) { [Math]::Round(([double]$supply.CampaignDayEnd - [double]$supply.CampaignDayStart), 6) } else { $null }
        DailyTicksElapsed = if ($supply) { [int]$supply.DailyTicksElapsed } else { 0 }
        FinalMembers = if ($supply) { [int]$supply.Members } else { $null }
        FinalGold = if ($supply) { [int]$supply.Gold } else { $null }
        FinalFood = if ($supply) { [double]$supply.Food } else { $null }
        FoodItemId = if ($supply) { [string]$supply.FoodItemId } else { $null }
        FoodAmount = if ($supply) { [int]$supply.FoodAmount } else { $null }
        TransactionAmount = if ($supply) { [int]$supply.NativeTransactionAmount } else { $null }
        RejectedDecisions = if ($supply) { [int]$supply.RejectedDecisions } else { $null }
        FixtureUnchanged = if ($liveResult) { [bool]$liveResult.FixtureUnchanged } else { $false }
        ProcessStopped = if ($liveResult) { [bool]$liveResult.ProcessStopped -and -not (Get-Process -Name Bannerlord* -ErrorAction SilentlyContinue) } else { $false }
        VisualCoverageRatio = $visualCoverage
        SourceClipRemovedAfterEvidence = $sourceClipRemoved
    })
}

$resultsArray = @($results)
$successfulRuns = @($resultsArray | Where-Object Passed).Count
$result = [ordered]@{
    ProviderKind = 'Configured local real-model supply candidate; not a deterministic baseline'
    Model = $modelName
    RunCount = $Runs
    DistinctCampaignSeeds = 1
    PredeclaredThreshold = [ordered]@{
        successfulRuns = $Runs
        maxSecondsPerRun = $WallClockLimitSeconds
        maxDecisionsPerRun = 24
        modelMaxOutputTokens = 4096
        maxFoodTransactionsPerRun = 1
        maxFoodUnitsPerRun = 1
        maxNativeRestRequestsPerRun = 1
        requiredDailyTicks = 3
        startingDailyTickCount = 2
        requiredFinalDailyTickCount = 5
        minFinalGold = 861
        minFinalFood = 1.0
        positiveGold = $true
        partyMembers = 6
        minVisualCoverage = 0.9
        fixtureUnchanged = $true
        processStopped = $true
    }
    SuccessfulRuns = $successfulRuns
    Passed = ($successfulRuns -eq $Runs)
    Results = $resultsArray
}
$json = $result | ConvertTo-Json -Depth 12
Set-Content -LiteralPath (Join-Path $outerTemp 'LiveModelSupplyEvaluation.json') -Value $json -Encoding UTF8
$json
if (-not $result.Passed) { exit 1 }
