[CmdletBinding()]
param(
    [ValidateRange(5,5)][int]$Runs = 5,
    [int]$WallClockLimitSeconds = 180,
    [double]$CampaignDayLimit = 0.1
)

$ErrorActionPreference = 'Stop'
$harnessRoot = $PSScriptRoot
$freshCampaignScript = Join-Path $PSScriptRoot 'Test-AgentFreshCampaign.ps1'
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$saveDirectory = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\Game Saves'
$outerTemp = $env:CHRONICLE_HARNESS_TEMP
if (-not $outerTemp -or -not (Test-Path -LiteralPath $outerTemp -PathType Container)) { throw 'Fresh-Campaign live-model evaluation requires an active Run-Harness TestResults temp directory.' }
$evaluationRoot = Split-Path -Parent $outerTemp
$modelName = [string][Environment]::GetEnvironmentVariable('CHRONICLE_LLM_MODEL','Process')
if ([string]::IsNullOrWhiteSpace($modelName)) { $modelName = [string][Environment]::GetEnvironmentVariable('CHRONICLE_LLM_MODEL','User') }
if ([string]::IsNullOrWhiteSpace($modelName)) { throw 'Fresh-Campaign candidate evaluation requires a locally configured model name; credentials are never displayed.' }
$harnessCommit = ([string](& git -C $PSScriptRoot rev-parse HEAD)).Trim()
$harnessDirtyFileCount = @(& git -C $PSScriptRoot status --short).Count
$ollamaVersion = $null
try { $ollamaVersion = [string](Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/version' -TimeoutSec 3).version } catch { throw 'The local Ollama loopback service could not be queried before the candidate run.' }
$modelDigest = $null
try { $modelEntry = (Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 3).models | Where-Object { [string]$_.name -ceq $modelName } | Select-Object -First 1; if (-not $modelEntry) { throw 'The configured candidate model is not present in Ollama tags.' }; $modelDigest = [string]$modelEntry.digest } catch { throw "Could not verify configured model metadata without reading or printing credentials: $($_.Exception.Message)" }
$modules = @('Bannerlord.Harmony','Bannerlord.ButterLib','Bannerlord.UIExtenderEx','Bannerlord.MBOptionScreen','Native','SandBoxCore','CustomBattle','SandBox','StoryMode','BirthAndDeath','ChronicleFramework')
$results = [System.Collections.Generic.List[object]]::new()
$gitRoot = ([string](& git -C $harnessRoot rev-parse --show-toplevel)).Trim()
if ([string]::IsNullOrWhiteSpace($gitRoot)) { throw 'Could not resolve the repository root for the candidate-evaluation source manifest.' }

function Get-HarnessSourceManifestHash {
    $relativeFiles = @(& git -C $harnessRoot ls-files --cached --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) { throw 'Could not list tracked and non-ignored Harness source files for the evaluation manifest.' }
    $gitRootPrefix = $gitRoot.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    $localSettingsPath = Join-Path $harnessRoot 'harness.local.json'
    $localSettingsRelative = $localSettingsPath.Substring($gitRootPrefix.Length).Replace('\','/')
    if (Test-Path -LiteralPath $localSettingsPath -PathType Leaf) { $relativeFiles += $localSettingsRelative }
    $entries = foreach ($relativePath in @($relativeFiles | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object -Unique)) {
        $normalized = ([string]$relativePath).Replace('\','/')
        if ($normalized -match '(^|/)AGENTS\.md$') { continue }
        $absolutePath = Join-Path $gitRoot $normalized.Replace('/', [IO.Path]::DirectorySeparatorChar)
        if (Test-Path -LiteralPath $absolutePath -PathType Leaf) {
            $hash = (Get-FileHash -LiteralPath $absolutePath -Algorithm SHA256).Hash
            "$normalized|$hash"
        }
    }
    $payload = [Text.Encoding]::UTF8.GetBytes(($entries -join "`n"))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { [BitConverter]::ToString($sha.ComputeHash($payload)).Replace('-', '') }
    finally { $sha.Dispose() }
}

function Get-SaveManifestHash {
    if (-not (Test-Path -LiteralPath $saveDirectory -PathType Container)) { return 'no-save-directory' }
    $entries = @(Get-ChildItem -LiteralPath $saveDirectory -File -Filter '*.sav' | Sort-Object Name | ForEach-Object {
        "$($_.Name)|$($_.Length)|$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)"
    })
    $bytes = [Text.Encoding]::UTF8.GetBytes($entries -join "`n")
    $sha = [Security.Cryptography.SHA256]::Create()
    try { [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '') }
    finally { $sha.Dispose() }
}

$sourceSaveManifestHash = Get-SaveManifestHash
$sourceManifestAtEvaluationStart = Get-HarnessSourceManifestHash
$sourceChangedDuringEvaluation = $false
for ($runIndex = 1; $runIndex -le $Runs; $runIndex++) {
    $sourceManifestBeforeRun = Get-HarnessSourceManifestHash
    if ($sourceManifestBeforeRun -cne $sourceManifestAtEvaluationStart) {
        $sourceChangedDuringEvaluation = $true
        break
    }
    if (Get-Process -Name Bannerlord* -ErrorAction SilentlyContinue) { throw "Fresh-Campaign live-model run $runIndex found a Bannerlord client left by the preceding run." }
    $sessionHashBefore = if (Test-Path -LiteralPath $sessionPath -PathType Leaf) { (Get-FileHash -LiteralPath $sessionPath -Algorithm SHA256).Hash } else { $null }
    $runDirectory = Join-Path $evaluationRoot ('FreshCampaignLiveModelRun-' + $runIndex.ToString('00'))
    $runTemp = Join-Path $runDirectory 'Temp'
    New-Item -ItemType Directory -Force -Path $runTemp | Out-Null
    $previousTemp = $env:CHRONICLE_HARNESS_TEMP
    $env:CHRONICLE_HARNESS_TEMP = $runTemp
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    $childResult = $null
    $childExitCode = 1
    $failure = $null
    $childOutput = ''
    try {
        $childOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $freshCampaignScript -ValidateRecruitmentProgression -RealModelRecruitment 2>&1 | Out-String
        $childExitCode = $LASTEXITCODE
        try { $childResult = $childOutput | ConvertFrom-Json }
        catch { $failure = "FreshCampaign candidate did not return structured JSON (exit=$childExitCode): $childOutput" }
        if ($childExitCode -ne 0 -and -not $failure) { $failure = "FreshCampaign candidate child exited $childExitCode after returning a structured result." }
    }
    catch { $failure = $_.Exception.Message }
    finally {
        $stopwatch.Stop()
        $env:CHRONICLE_HARNESS_TEMP = $previousTemp
    }

    Set-Content -LiteralPath (Join-Path $runDirectory 'FreshCampaignChildOutput.log') -Value $childOutput -Encoding UTF8
    if ($childResult) { $childResult | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $runDirectory 'FreshCampaignChildResult.json') -Encoding UTF8 }
    $processStopped = -not [bool](Get-Process -Name Bannerlord* -ErrorAction SilentlyContinue)
    $sessionHashAfter = if (Test-Path -LiteralPath $sessionPath -PathType Leaf) { (Get-FileHash -LiteralPath $sessionPath -Algorithm SHA256).Hash } else { $null }
    $sessionRestored = $sessionHashBefore -ceq $sessionHashAfter
    $saveManifestHashAfter = Get-SaveManifestHash
    $saveFilesUnchanged = $sourceSaveManifestHash -ceq $saveManifestHashAfter
    $sourceManifestAfterRun = Get-HarnessSourceManifestHash
    $sourceManifestUnchanged = ($sourceManifestBeforeRun -ceq $sourceManifestAfterRun -and $sourceManifestAfterRun -ceq $sourceManifestAtEvaluationStart)
    if (-not $sourceManifestUnchanged) {
        $sourceChangedDuringEvaluation = $true
        $failure = if ($failure) { "$failure; Harness source changed during the candidate matrix, so this result cannot be treated as one code revision." } else { 'Harness source changed during the candidate matrix; refusing to combine runs from different revisions.' }
    }
    if (-not $processStopped) { $failure = if ($failure) { "$failure; Bannerlord process leaked." } else { 'Bannerlord process leaked.' } }
    if (-not $sessionRestored) { $failure = if ($failure) { "$failure; pre-existing Agent session was not restored exactly." } else { 'Pre-existing Agent session was not restored exactly.' } }
    if (-not $saveFilesUnchanged) { $failure = if ($failure) { "$failure; existing Game Saves changed." } else { 'Existing Game Saves changed.' } }

    $progression = if ($childResult) { $childResult.RecruitmentProgression } else { $null }
    $campaignInstanceId = if ($childResult) { [string]$childResult.ChronicleCampaignInstanceId } else { '' }
    $campaignCreated = [bool]($childResult -and $childResult.GameStarted -and $childResult.NativeNewCampaignRequested -and $childResult.CharacterCreationCompleted -and $childResult.InitialAgentObservationCaptured)
    $classification = if (-not $sourceManifestUnchanged) { 'harness-source-changed-during-evaluation' } elseif (-not $campaignCreated) { 'new-campaign-or-startup-tool-failure' } elseif ($progression -and $progression.Passed) { 'live-model-native-recruitment-completed' } else { 'campaign-created-live-model-progression-failed' }
    $loopWallClock = if ($progression -and $progression.WallClockSeconds -ne $null) { [double]$progression.WallClockSeconds } else { $null }
    $campaignDays = if ($progression -and $progression.CampaignDaysElapsed -ne $null) { [double]$progression.CampaignDaysElapsed } else { $null }
    $nativeActionExact = ($progression -and [int]$progression.MoveCount -eq 1 -and [int]$progression.RecruitmentCount -eq 1 -and [int]$progression.RejectedNativeActions -eq 0)
    $wallClockPassed = ($stopwatch.Elapsed.TotalSeconds -le $WallClockLimitSeconds)
    $campaignDaysPassed = ($null -ne $campaignDays -and $campaignDays -le $CampaignDayLimit)
    $visualPassed = ($progression -and [double]$progression.VisualCoverageRatio -ge 0.9 -and [bool]$progression.VideoRemovedAfterEvidence)
    $runPassed = (
        -not $failure -and $sourceManifestUnchanged -and $childResult -and $childResult.CharacterCreationCompleted -and
        -not [string]::IsNullOrWhiteSpace($campaignInstanceId) -and [bool]$progression.Passed -and
        $nativeActionExact -and $wallClockPassed -and $campaignDaysPassed -and $visualPassed -and
        $processStopped -and $sessionRestored -and $saveFilesUnchanged
    )
    if (-not $runPassed -and -not $failure) { $failure = 'Candidate run failed one or more predeclared native/action/time/visual/cleanup thresholds.' }

    $initialState = $null
    if ($childResult -and $childResult.InitialAgentObservationPath -and (Test-Path -LiteralPath $childResult.InitialAgentObservationPath -PathType Leaf)) {
        try { $initialState = Get-Content -LiteralPath $childResult.InitialAgentObservationPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    }
    $results.Add([pscustomobject]@{
        Run = $runIndex
        Passed = $runPassed
        Classification = $classification
        Failure = $failure
        HarnessSourceManifestBefore = $sourceManifestBeforeRun
        HarnessSourceManifestAfter = $sourceManifestAfterRun
        HarnessSourceIntegrityPassed = $sourceManifestUnchanged
        Model = $modelName
        ModelDigest = $modelDigest
        OllamaVersion = $ollamaVersion
        WallClockSeconds = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 3)
        CampaignDaysElapsed = $campaignDays
        MoveCount = if ($progression) { [int]$progression.MoveCount } else { 0 }
        RecruitCount = if ($progression) { [int]$progression.RecruitmentCount } else { 0 }
        RejectedNativeActions = if ($progression) { [int]$progression.RejectedNativeActions } else { $null }
        PreNativeRejectedDecisions = if ($progression) { [int]$progression.PreNativeRejectedDecisions } else { $null }
        NativeRecruitmentVerified = if ($progression) { [bool]$progression.RecruitmentVerified } else { $false }
        CampaignInstanceId = $campaignInstanceId
        CampaignSeed = 'unknown; instance ID is not the Native RNG seed'
        InitialRenown = if ($initialState) { [double]$initialState.economy.renown } else { $null }
        InitialGold = if ($initialState) { [int]$initialState.economy.gold } else { $null }
        InitialPartyMembers = if ($initialState) { [int]$initialState.party.members } else { $null }
        InitialPosition = if ($initialState) { [ordered]@{ x = $initialState.location.x; y = $initialState.location.y } } else { $null }
        TargetSettlementId = if ($progression) { [string]$progression.TargetSettlementId } else { '' }
        TargetSource = if ($progression) { [string]$progression.TargetSource } else { '' }
        RecruitmentOfferCount = if ($progression) { [int]$progression.RecruitmentOfferCount } else { $null }
        SelectedOffer = if ($progression) { $progression.SelectedOffer } else { $null }
        PartyAfter = if ($progression) { [int]$progression.MembersAfter } else { $null }
        GoldAfter = if ($progression) { [int]$progression.GoldAfter } else { $null }
        VisualCoverageRatio = if ($progression) { [double]$progression.VisualCoverageRatio } else { 0.0 }
        VideoRemovedAfterEvidence = if ($progression) { [bool]$progression.VideoRemovedAfterEvidence } else { $false }
        StartupDialogReceipts = if ($childResult) { @($childResult.StartupDialogReceipts) + @($progression.StartupDialogReceipts) } else { @() }
        ProcessStopped = $processStopped
        PriorAgentSessionRestored = $sessionRestored
        ExistingSaveFilesUnchanged = $saveFilesUnchanged
        HarnessRunDirectory = $runDirectory
    })
    if ($sourceChangedDuringEvaluation) { break }
}

$resultsArray = @($results)
$campaignIds = @($resultsArray | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.CampaignInstanceId) } | ForEach-Object { [string]$_.CampaignInstanceId } | Select-Object -Unique)
$passedRuns = @($resultsArray | Where-Object { $_.Passed }).Count
$result = [ordered]@{
    ProviderKind = 'configured local real-model candidate; not a deterministic baseline'
    Model = $modelName
    ModelDigest = $modelDigest
    OllamaVersion = $ollamaVersion
    HarnessCommit = $harnessCommit
    HarnessDirtyFileCountAtStart = $harnessDirtyFileCount
    HarnessSourceManifestAtStart = $sourceManifestAtEvaluationStart
    HarnessSourceManifestAtEnd = Get-HarnessSourceManifestHash
    SourceChangedDuringEvaluation = $sourceChangedDuringEvaluation
    CompletedRuns = $results.Count
    Modules = $modules
    RunCount = $Runs
    DistinctCampaignInstances = $campaignIds.Count
    CampaignRngSeedExposure = 'unknown; instance IDs are not represented as Native RNG seeds'
    PredeclaredThreshold = [ordered]@{ successRuns = $Runs; maxEndToEndSeconds = $WallClockLimitSeconds; maxCampaignDays = $CampaignDayLimit; requiredMoveCount = 1; requiredRecruitCount = 1; minVisualCoverage = 0.9; existingSavesUnchanged = $true; processStopped = $true }
    SuccessfulRuns = $passedRuns
    Passed = (-not $sourceChangedDuringEvaluation -and $results.Count -eq $Runs -and $passedRuns -eq $Runs -and $campaignIds.Count -eq $Runs)
    Results = $resultsArray
}
$json = $result | ConvertTo-Json -Depth 20
if ($outerTemp -and (Test-Path -LiteralPath $outerTemp -PathType Container)) { Set-Content -LiteralPath (Join-Path $outerTemp 'FreshCampaignLiveModelEvaluation.json') -Value $json -Encoding UTF8 }
$json
if (-not $result.Passed) { exit 1 }
