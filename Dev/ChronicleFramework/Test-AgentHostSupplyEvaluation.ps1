[CmdletBinding()]
param(
    [ValidateRange(1,3)][int]$Runs = 3,
    [ValidateRange(60,600)][int]$WallClockLimitSeconds = 300,
    [ValidateRange(5,30)][int]$FrameRate = 10
)

$ErrorActionPreference = 'Stop'
$liveTest = Join-Path $PSScriptRoot 'Test-AgentLiveModelLoop.ps1'
$outerTemp = $env:CHRONICLE_HARNESS_TEMP
if (-not $outerTemp -or -not (Test-Path -LiteralPath $outerTemp -PathType Container)) { throw 'Agent Host supply evaluation requires the active Run-Harness TestResults temp directory.' }
$evaluationRoot = Split-Path -Parent $outerTemp
$documentsPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
if ([string]::IsNullOrWhiteSpace($documentsPath)) { throw 'Windows Documents directory could not be resolved for Agent Host cleanup checks.' }
$protocolRoot = Join-Path $documentsPath 'Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent'
$sessionPath = Join-Path $protocolRoot 'session.json'
$results = [System.Collections.Generic.List[object]]::new()

for ($runIndex = 1; $runIndex -le $Runs; $runIndex++) {
    if (Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue) { throw "Agent Host supply run $runIndex found a Bannerlord process left by a previous run." }
    if (Test-Path -LiteralPath $sessionPath -PathType Leaf) { throw "Agent Host supply run $runIndex found a stale CLI session; the fixture must be stopped before testing Host." }

    $runDirectory = Join-Path $evaluationRoot ('AgentHostSupplyRun-{0:D2}' -f $runIndex)
    $runTemp = Join-Path $runDirectory 'Temp'
    New-Item -ItemType Directory -Path $runTemp -Force | Out-Null
    $priorHarnessTemp = $env:CHRONICLE_HARNESS_TEMP
    $priorTemp = $env:TEMP
    $priorTmp = $env:TMP
    $priorProviderProfilePath = $env:CHRONICLE_AGENT_PROFILE_PATH
    $env:CHRONICLE_HARNESS_TEMP = $runTemp
    $env:TEMP = $runTemp
    $env:TMP = $runTemp

    $watch = [Diagnostics.Stopwatch]::StartNew()
    $childOutput = ''
    $childExitCode = 1
    $liveResult = $null
    $failure = $null
    try {
        $providerBaseUrl = [Environment]::GetEnvironmentVariable('CHRONICLE_LLM_BASE_URL', 'Process')
        if ([string]::IsNullOrWhiteSpace($providerBaseUrl)) { $providerBaseUrl = [Environment]::GetEnvironmentVariable('CHRONICLE_LLM_BASE_URL', 'User') }
        $providerModelId = [Environment]::GetEnvironmentVariable('CHRONICLE_LLM_MODEL', 'Process')
        if ([string]::IsNullOrWhiteSpace($providerModelId)) { $providerModelId = [Environment]::GetEnvironmentVariable('CHRONICLE_LLM_MODEL', 'User') }
        if ([string]::IsNullOrWhiteSpace($providerBaseUrl) -or [string]::IsNullOrWhiteSpace($providerModelId)) { throw 'Agent Host supply evaluation requires existing local loopback model settings; no user credential is read or written.' }
        $mcmFixtureDirectory = Join-Path $runTemp 'MCM\Global\ChronicleFramework'
        New-Item -ItemType Directory -Path $mcmFixtureDirectory -Force | Out-Null
        $profilePath = Join-Path $mcmFixtureDirectory 'ChronicleAgentSettings.json'
        [ordered]@{ OllamaBaseUrl = $providerBaseUrl; ModelId = $providerModelId } | ConvertTo-Json -Compress | Set-Content -LiteralPath $profilePath -Encoding UTF8
        $env:CHRONICLE_AGENT_PROFILE_PATH = $profilePath
        $childOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $liveTest -SupplyManagementLoop -AgentHostRuntime -FrameRate $FrameRate 2>&1 | Out-String
        $childExitCode = $LASTEXITCODE
        $resultPath = Join-Path $runTemp 'LiveModelLoopResult.json'
        if (Test-Path -LiteralPath $resultPath -PathType Leaf) {
            try { $liveResult = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json }
            catch { $failure = 'Host live-loop receipt was not parseable JSON.' }
        }
        if ($childExitCode -ne 0 -and -not $failure) {
            $failure = if ($liveResult -and $liveResult.Failure) { [string]$liveResult.Failure } else { "Agent Host live-loop child exited $childExitCode without an acceptance result." }
        }
        if (-not $liveResult -and -not $failure) { $failure = 'Host live-loop did not produce LiveModelLoopResult.json.' }
    }
    catch { $failure = $_.Exception.Message }
    finally {
        $watch.Stop()
        $env:CHRONICLE_HARNESS_TEMP = $priorHarnessTemp
        $env:TEMP = $priorTemp
        $env:TMP = $priorTmp
        if ($null -eq $priorProviderProfilePath) { Remove-Item Env:CHRONICLE_AGENT_PROFILE_PATH -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_AGENT_PROFILE_PATH = $priorProviderProfilePath }
    }

    $hostTrace = if ($liveResult) { $liveResult.Trace } else { $null }
    $supply = if ($hostTrace) { $hostTrace.SupplyVerification } else { $null }
    $capture = if ($liveResult) { $liveResult.Capture } else { $null }
    $nativeActionCount = if ($hostTrace -and $hostTrace.Trace) { @($hostTrace.Trace | Where-Object { $_.actionAttempted -and $_.actionExecuted }).Count } else { 0 }
    $noGameProcesses = @(Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue).Count -eq 0
    $noSessionFile = -not (Test-Path -LiteralPath $sessionPath -PathType Leaf)
    $runPassed = (
        $childExitCode -eq 0 -and $liveResult -and [bool]$liveResult.Passed -and
        [bool]$supply.Passed -and [bool]$liveResult.FixtureUnchanged -and [bool]$liveResult.ProcessStopped -and
        [string]$hostTrace.ModelConfigurationSource -eq 'harness-mcm-profile-fixture' -and
        [bool]$supply.NativeGoalVerified -and [int]$supply.DailyTicksElapsed -eq 3 -and
        [int]$supply.HostRestPollCount -gt 0 -and [bool]$supply.HostWaitLeaveActionCompleted -and
        [int]$supply.ModelDecisionCount -le 24 -and [int]$supply.NativeRestRequestCount -eq 1 -and
        [int]$supply.FoodAmount -eq 1 -and [int]$supply.Members -eq 6 -and
        [int]$supply.Gold -ge 861 -and [double]$supply.Food -ge 1.0 -and
        [bool]$hostTrace.SourceTrackedTreeClean -and [string]$hostTrace.SourceCommit -eq (git.exe -C $PSScriptRoot rev-parse HEAD).Trim() -and
        $watch.Elapsed.TotalSeconds -le $WallClockLimitSeconds -and
        [bool]$liveResult.VisualEvidencePassed -and [double]$capture.FrameCoverageRatio -ge 0.9 -and
        [bool]$capture.VideoRemovedAfterEvidence -and $noGameProcesses -and $noSessionFile
    )
    if (-not $runPassed -and -not $failure) { $failure = 'One or more frozen Native/Host/visual/source/cleanup assertions failed.' }
    $results.Add([ordered]@{
        run = $runIndex
        passed = [bool]$runPassed
        sourceCommit = if ($hostTrace) { [string]$hostTrace.SourceCommit } else { $null }
        modelId = if ($hostTrace) { [string]$hostTrace.ModelId } else { $null }
        modelConfigurationSource = if ($hostTrace) { [string]$hostTrace.ModelConfigurationSource } else { $null }
        trackedTreeClean = if ($hostTrace) { [bool]$hostTrace.SourceTrackedTreeClean } else { $false }
        wallClockSeconds = [Math]::Round($watch.Elapsed.TotalSeconds, 2)
        decisions = if ($supply) { [int]$supply.ModelDecisionCount } else { $null }
        nativeActions = $nativeActionCount
        hostFailureStage = if ($hostTrace) { [string]$hostTrace.HostFailureStage } else { $null }
        hostFailureExceptionType = if ($hostTrace) { [string]$hostTrace.HostFailureExceptionType } else { $null }
        hostFailureDetail = if ($hostTrace) { [string]$hostTrace.HostFailureDetail } else { $null }
        hostFailureStack = if ($hostTrace) { [string]$hostTrace.HostFailureStack } else { $null }
        hostLastSelectedAction = if ($hostTrace) { [string]$hostTrace.HostLastSelectedAction } else { $null }
        dailyTicksElapsed = if ($supply) { [int]$supply.DailyTicksElapsed } else { $null }
        endingMembers = if ($supply) { [int]$supply.Members } else { $null }
        endingGold = if ($supply) { [int]$supply.Gold } else { $null }
        endingFood = if ($supply) { [double]$supply.Food } else { $null }
        fixtureUnchanged = if ($liveResult) { [bool]$liveResult.FixtureUnchanged } else { $false }
        visualCoverageRatio = if ($capture) { [double]$capture.FrameCoverageRatio } else { $null }
        sourceVideoRemoved = if ($capture) { [bool]$capture.VideoRemovedAfterEvidence } else { $false }
        bannerlordProcessesStopped = $noGameProcesses
        cliSessionCleaned = $noSessionFile
        failure = $failure
    })
    if (-not $runPassed) { break }
}

$result = [ordered]@{
    Passed = ($results.Count -eq $Runs -and @($results | Where-Object { $_.passed }).Count -eq $Runs)
    ProviderKind = 'Local Agent Host decision loop; no billed provider'
    RunCount = $Runs
    DistinctCampaignSeeds = 1
    Threshold = [ordered]@{
        successfulRuns = $Runs
        maxSecondsPerRun = $WallClockLimitSeconds
        maxDecisionsPerRun = 24
        modelMaxOutputTokensPerCall = 256
        foodTransactions = 1
        foodUnits = 1
        nativeRestRequests = 1
        requiredDailyTicks = 3
        finalMembers = 6
        minGold = 861
        minFood = 1.0
        visualCoverageRatio = 0.9
    }
    Runs = @($results)
    EvidenceDirectory = $evaluationRoot
}
$result | ConvertTo-Json -Depth 8
if (-not $result.Passed) { exit 1 }
