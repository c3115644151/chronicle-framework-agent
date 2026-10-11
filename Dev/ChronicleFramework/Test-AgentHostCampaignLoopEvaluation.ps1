[CmdletBinding()]
param(
    [ValidateRange(1,3)][int]$Runs = 1,
    [ValidateRange(5,30)][int]$FrameRate = 10
)

$ErrorActionPreference = 'Stop'
$liveTest = Join-Path $PSScriptRoot 'Test-AgentLiveModelLoop.ps1'
$outerTemp = $env:CHRONICLE_HARNESS_TEMP
if (-not $outerTemp -or -not (Test-Path -LiteralPath $outerTemp -PathType Container)) { throw 'Agent Host Campaign loop evaluation requires an active Run-Harness TestResults temp directory.' }
$evaluationRoot = Split-Path -Parent $outerTemp
$documentsPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
if ([string]::IsNullOrWhiteSpace($documentsPath)) { throw 'Windows Documents directory could not be resolved for Agent Host cleanup checks.' }
$protocolRoot = Join-Path $documentsPath 'Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent'
$sessionPath = Join-Path $protocolRoot 'session.json'
$results = [System.Collections.Generic.List[object]]::new()

for ($runIndex = 1; $runIndex -le $Runs; $runIndex++) {
    if (Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue) { throw "Agent Host Campaign run $runIndex found a Bannerlord process left by a previous run." }
    if (Test-Path -LiteralPath $sessionPath -PathType Leaf) { throw "Agent Host Campaign run $runIndex found a stale CLI session; the fixture must be stopped before testing Host." }

    $runDirectory = Join-Path $evaluationRoot ('AgentHostCampaignRun-{0:D2}' -f $runIndex)
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
        if ([string]::IsNullOrWhiteSpace($providerBaseUrl) -or [string]::IsNullOrWhiteSpace($providerModelId)) { throw 'Agent Host Campaign evaluation requires existing local loopback model settings; no user credential is read or written.' }

        $mcmFixtureDirectory = Join-Path $runTemp 'MCM\Global\ChronicleFramework'
        New-Item -ItemType Directory -Path $mcmFixtureDirectory -Force | Out-Null
        $profilePath = Join-Path $mcmFixtureDirectory 'ChronicleAgentSettings.json'
        [ordered]@{ OllamaBaseUrl = $providerBaseUrl; ModelId = $providerModelId } | ConvertTo-Json -Compress | Set-Content -LiteralPath $profilePath -Encoding UTF8
        $env:CHRONICLE_AGENT_PROFILE_PATH = $profilePath
        $childOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $liveTest -ArrivalLoop -AgentHostRuntime -FrameRate $FrameRate 2>&1 | Out-String
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

    $trace = if ($liveResult) { $liveResult.Trace } else { $null }
    $modelSteps = if ($trace -and $trace.Trace) { @($trace.Trace) } else { @() }
    $nativeActions = @($modelSteps | Where-Object { $_.actionExecuted -and $_.actionReceipt.status -eq 'completed' })
    $observeAgainSteps = @($modelSteps | Where-Object { $_.control.kind -eq 'bounded-observe-again' -and -not $_.actionExecuted })
    $noGameProcesses = @(Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue).Count -eq 0
    $noSessionFile = -not (Test-Path -LiteralPath $sessionPath -PathType Leaf)
    $passed = (
        $childExitCode -eq 0 -and $liveResult -and [bool]$liveResult.Passed -and
        [bool]$liveResult.FixtureUnchanged -and [bool]$liveResult.ProcessStopped -and
        [string]$trace.ModelConfigurationSource -eq 'harness-mcm-profile-fixture' -and
        [string]$trace.AcceptanceSlice -eq 'Native movement arrival' -and
        [bool]$trace.ArrivalConfirmed -and [bool]$trace.CampaignDayAdvancedDuringTravel -and
        [bool]$trace.ProviderStoppedAfterGoalAction -and [int]$trace.Decisions -le 30 -and
        $nativeActions.Count -eq 2 -and @($nativeActions | Where-Object { $_.actionReceipt.action -eq 'mapSettlementTargets' }).Count -eq 1 -and
        @($nativeActions | Where-Object { $_.actionReceipt.action -eq 'move' }).Count -eq 1 -and $observeAgainSteps.Count -gt 0 -and
        [bool]$trace.SourceTrackedTreeClean -and [string]$trace.SourceCommit -eq (git.exe -C $PSScriptRoot rev-parse HEAD).Trim() -and
        [bool]$liveResult.VisualEvidencePassed -and [double]$liveResult.Capture.FrameCoverageRatio -ge 0.9 -and
        [bool]$liveResult.Capture.VideoRemovedAfterEvidence -and $noGameProcesses -and $noSessionFile
    )
    if (-not $passed -and -not $failure) { $failure = 'One or more Native arrival, Host, natural-time, visual, source, or cleanup assertions failed.' }
    $results.Add([ordered]@{
        run = $runIndex
        passed = [bool]$passed
        sourceCommit = if ($trace) { [string]$trace.SourceCommit } else { $null }
        modelId = if ($trace) { [string]$trace.ModelId } else { $null }
        modelConfigurationSource = if ($trace) { [string]$trace.ModelConfigurationSource } else { $null }
        trackedTreeClean = if ($trace) { [bool]$trace.SourceTrackedTreeClean } else { $false }
        decisions = if ($trace) { [int]$trace.Decisions } else { $null }
        nativeActions = $nativeActions.Count
        nativeArrivalVerified = if ($trace) { [bool]$trace.ArrivalConfirmed } else { $false }
        campaignTimeAdvancedNaturally = if ($trace) { [bool]$trace.CampaignDayAdvancedDuringTravel } else { $false }
        observeAgainCount = $observeAgainSteps.Count
        visualCoverageRatio = if ($liveResult) { [double]$liveResult.Capture.FrameCoverageRatio } else { $null }
        sourceVideoRemoved = if ($liveResult) { [bool]$liveResult.Capture.VideoRemovedAfterEvidence } else { $false }
        bannerlordProcessesStopped = $noGameProcesses
        cliSessionCleaned = $noSessionFile
        failure = $failure
        childOutput = if ($childExitCode -ne 0) { $childOutput } else { $null }
    })
    if (-not $passed) { break }
}

$result = [ordered]@{
    Passed = ($results.Count -eq $Runs -and @($results | Where-Object { $_.passed }).Count -eq $Runs)
    ProviderKind = 'Local Agent Host decision loop; no billed provider'
    RunCount = $Runs
    DistinctCampaignSeeds = 1
    Threshold = [ordered]@{
        successfulRuns = $Runs
        maxDecisionsPerRun = 30
        nativeActions = 2
        requiredNativeActions = @('mapSettlementTargets', 'move')
        naturalCampaignTimeAdvance = $true
        requiredPassiveObservationsDuringMovement = $true
        explicitClockActions = 0
        visualCoverageRatio = 0.9
    }
    Runs = @($results)
    EvidenceDirectory = $evaluationRoot
}
$result | ConvertTo-Json -Depth 14
if (-not $result.Passed) { exit 1 }
