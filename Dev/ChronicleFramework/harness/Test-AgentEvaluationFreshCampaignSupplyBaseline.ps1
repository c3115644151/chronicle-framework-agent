#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateRange(1,5)][int]$Runs = 5,
    [int]$TimeoutSeconds = 240,
    [int]$RestWallClockLimitSeconds = 180,
    [ValidateRange(5,30)][int]$FrameRate = 10
)

$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$freshCampaignScript = Join-Path $PSScriptRoot 'Test-AgentFreshCampaign.ps1'
$supplyBaselineScript = Join-Path $PSScriptRoot 'Test-AgentMultiDaySupplyBaseline.ps1'
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$saveDirectory = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\Game Saves'
$outerTemp = $env:CHRONICLE_HARNESS_TEMP
if (-not $outerTemp -or -not (Test-Path -LiteralPath $outerTemp -PathType Container)) { throw 'Fresh Campaign supply baseline requires an active Run-Harness TestResults temp directory.' }
$evaluationRoot = Split-Path -Parent $outerTemp
$results = [System.Collections.Generic.List[object]]::new()

function Get-SaveManifestHash {
    if (-not (Test-Path -LiteralPath $saveDirectory -PathType Container)) { return 'no-save-directory' }
    $entries = @(Get-ChildItem -LiteralPath $saveDirectory -File -Filter '*.sav' | Sort-Object Name | ForEach-Object {
        $fileHash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        "$($_.Name)|$($_.Length)|$fileHash"
    })
    $bytes = [Text.Encoding]::UTF8.GetBytes($entries -join "`n")
    $sha = [Security.Cryptography.SHA256]::Create()
    try { [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '') }
    finally { $sha.Dispose() }
}

$sourceSaveManifestHash = Get-SaveManifestHash
for ($runIndex = 1; $runIndex -le $Runs; $runIndex++) {
    if (Get-Process -Name Bannerlord* -ErrorAction SilentlyContinue) { throw "Supply baseline run $runIndex found an unclean Bannerlord process before starting." }
    if (Test-Path -LiteralPath $sessionPath -PathType Leaf) { throw "Supply baseline run $runIndex found a pre-existing Chronicle Agent session; it will not overwrite it." }

    $runDirectory = Join-Path $evaluationRoot ('FreshCampaignSupplyRun-' + $runIndex.ToString('00'))
    $runTemp = Join-Path $runDirectory 'Temp'
    New-Item -ItemType Directory -Force -Path $runTemp | Out-Null
    $previousTemp = $env:CHRONICLE_HARNESS_TEMP
    $env:CHRONICLE_HARNESS_TEMP = $runTemp
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    $freshResult = $null
    $baselineResult = $null
    $failure = $null
    $phase = 'fresh-campaign'
    $disposableSaveName = $null
    $disposableSavePath = $null
    $disposableSaveHashBefore = $null
    $disposableSaveHashAfter = $null
    $cleanupSucceeded = $false
    $processStopped = $false
    $sessionAbsent = $false
    $runStartedUtc = [DateTime]::UtcNow.ToString('O')

    try {
        $freshOutput = & $HarnessPowerShell -NoProfile -File $freshCampaignScript -ValidateRecruitmentProgression -RetainDisposableSave -TimeoutSeconds $TimeoutSeconds 2>&1 | Out-String
        try { $freshResult = $freshOutput | ConvertFrom-Json }
        catch { throw "Fresh Campaign fixture preparation returned no structured result (exit=$LASTEXITCODE): $freshOutput" }
        $disposableSaveName = [string]$freshResult.DisposableSaveName
        if (-not [string]::IsNullOrWhiteSpace([string]$freshResult.DisposableSavePath)) { $disposableSavePath = [IO.Path]::GetFullPath([string]$freshResult.DisposableSavePath) }
        if ($LASTEXITCODE -ne 0 -or -not [bool]$freshResult.Passed -or -not [bool]$freshResult.DisposableSaveRetained) { throw "Native New Campaign did not produce a verified retained disposable fixture: $($freshResult.RecruitmentProgressionError)" }
        $saveRoot = [IO.Path]::GetFullPath($saveDirectory).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        if ([string]::IsNullOrWhiteSpace($disposableSaveName) -or -not $disposableSavePath.StartsWith($saveRoot,[StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $disposableSavePath -PathType Leaf)) { throw 'Fresh Campaign returned a disposable save outside Game Saves or no valid save.' }
        $disposableSaveHashBefore = (Get-FileHash -LiteralPath $disposableSavePath -Algorithm SHA256).Hash
        if ($freshResult.SaveDirectoryMetadataUnchanged -ne $true) { throw 'Fresh Campaign fixture creation changed a pre-existing save outside its owned disposable save.' }
        if (Get-Process -Name Bannerlord* -ErrorAction SilentlyContinue) { throw 'Fresh Campaign fixture creation left Bannerlord running before Native branch tests.' }
        if (Test-Path -LiteralPath $sessionPath -PathType Leaf) { throw 'Fresh Campaign fixture creation left an Agent session before Native branch tests.' }

        $phase = 'paired-native-supply-baseline'
        $baselineOutput = & $HarnessPowerShell -NoProfile -File $supplyBaselineScript -LoadSaveName $disposableSaveName -TimeoutSeconds $TimeoutSeconds -RestDays 3 -TargetPartyMembers 6 -ProvisionAmount 1 -RestWallClockLimitSeconds $RestWallClockLimitSeconds -Repetitions 1 -CaptureVisualEvidence -FrameRate $FrameRate 2>&1 | Out-String
        try { $baselineResult = $baselineOutput | ConvertFrom-Json }
        catch { throw "Paired Native supply baseline returned no structured result (exit=$LASTEXITCODE): $baselineOutput" }
        if ($LASTEXITCODE -ne 0 -or -not [bool]$baselineResult.Passed) { throw "Paired Native supply branches did not meet their source-backed baseline checks: $($baselineResult.Failure)" }
        $scenarioInstances = @($baselineResult.Scenarios | ForEach-Object { [string]$_.CampaignInstanceId } | Select-Object -Unique)
        $branchFixtureHashes = @($baselineResult.Scenarios | ForEach-Object { [string]$_.TemplateSaveHash } | Select-Object -Unique)
        if (@($baselineResult.Scenarios).Count -ne 2 -or @($baselineResult.Scenarios | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.CampaignInstanceId) }).Count -gt 0 -or $branchFixtureHashes.Count -ne 1 -or $branchFixtureHashes[0] -cne $disposableSaveHashBefore -or [string]$baselineResult.FixtureHashAfter -cne $disposableSaveHashBefore) { throw 'Paired Native branches did not reload the exact same hash-verified disposable Campaign fixture.' }
        if (@($baselineResult.Scenarios).Count -ne 2 -or @($baselineResult.Scenarios | Where-Object { -not $_.Capture -or [double]$_.Capture.FrameCoverageRatio -lt 0.9 -or -not $_.Capture.VideoRemovedAfterEvidence }).Count -ne 0) { throw 'Each Native branch must have at least 90% UI video coverage and successful keyframe extraction/source-video cleanup.' }
        $disposableSaveHashAfter = (Get-FileHash -LiteralPath $disposableSavePath -Algorithm SHA256).Hash
        if ($disposableSaveHashBefore -cne $disposableSaveHashAfter -or -not [bool]$baselineResult.FixtureUnchanged) { throw 'Native branch execution modified the retained fresh-Campaign disposable save.' }
    }
    catch { $failure = "phase=$phase; $($_.Exception.Message)" }
    finally {
        $stopwatch.Stop()
        if ($disposableSavePath -and (Test-Path -LiteralPath $disposableSavePath -PathType Leaf)) {
            try {
                $saveRoot = [IO.Path]::GetFullPath($saveDirectory).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
                $fullPath = [IO.Path]::GetFullPath($disposableSavePath)
                if (-not $fullPath.StartsWith($saveRoot,[StringComparison]::OrdinalIgnoreCase) -or -not $disposableSaveName.StartsWith('ChronicleP5Fresh-',[StringComparison]::Ordinal)) { throw 'Refusing disposable save cleanup because its exact generated name/path was outside the approved scope.' }
                Get-ChildItem -LiteralPath $saveDirectory -File -Filter "$disposableSaveName*" | Remove-Item -Force
                $cleanupSucceeded = -not (Test-Path -LiteralPath $disposableSavePath -PathType Leaf)
            }
            catch { $failure = if ($failure) { "$failure; disposable-save cleanup failed: $($_.Exception.Message)" } else { "disposable-save cleanup failed: $($_.Exception.Message)" } }
        }
        $processStopped = -not [bool](Get-Process -Name Bannerlord* -ErrorAction SilentlyContinue)
        $sessionAbsent = -not (Test-Path -LiteralPath $sessionPath -PathType Leaf)
        if (-not $processStopped) { $failure = if ($failure) { "$failure; Bannerlord process leaked." } else { 'Bannerlord process leaked.' } }
        if (-not $sessionAbsent) { $failure = if ($failure) { "$failure; Agent session file remained." } else { 'Agent session file remained.' } }
        $env:CHRONICLE_HARNESS_TEMP = $previousTemp
        if ($freshResult) { $freshResult | ConvertTo-Json -Depth 18 | Set-Content -LiteralPath (Join-Path $runDirectory 'FreshCampaignFixture.json') -Encoding UTF8 }
        if ($baselineResult) { $baselineResult | ConvertTo-Json -Depth 18 | Set-Content -LiteralPath (Join-Path $runDirectory 'PairedSupplyBaseline.json') -Encoding UTF8 }
    }

    $saveManifestUnchanged = (Get-SaveManifestHash) -ceq $sourceSaveManifestHash
    if (-not $saveManifestUnchanged) { $failure = if ($failure) { "$failure; pre-existing Game Saves manifest/hash was not restored." } else { 'Pre-existing Game Saves manifest/hash was not restored.' } }
    $passed = (-not $failure -and $freshResult.Passed -and $baselineResult.Passed -and $cleanupSucceeded -and $processStopped -and $sessionAbsent -and $saveManifestUnchanged)
    $results.Add([pscustomobject]@{
        Run = $runIndex
        Passed = $passed
        Failure = $failure
        CampaignInstanceId = if ($freshResult) { [string]$freshResult.ChronicleCampaignInstanceId } else { '' }
        CampaignSeed = 'unknown; Chronicle Campaign instance identity is not represented as the Native RNG seed'
        BranchRuntimeCampaignInstanceIds = if ($baselineResult) { @($baselineResult.Scenarios | ForEach-Object { [string]$_.CampaignInstanceId }) } else { @() }
        BranchInstanceIdsMatched = if ($baselineResult -and $baselineResult.Scenarios.Count -eq 2) { [string]$baselineResult.Scenarios[0].CampaignInstanceId -ceq [string]$baselineResult.Scenarios[1].CampaignInstanceId } else { $false }
        FreshCampaignPassed = if ($freshResult) { [bool]$freshResult.Passed } else { $false }
        NativeRecruitmentProgressionPassed = if ($freshResult) { [bool]$freshResult.RecruitmentProgression.Passed } else { $false }
        FreshInitialRenown = if ($freshResult) { $freshResult.ClanRenown } else { $null }
        FreshInitialGold = if ($freshResult) { $freshResult.RecruitmentProgression.InitialGold } else { $null }
        PairedNativeBaselinePassed = if ($baselineResult) { [bool]$baselineResult.Passed } else { $false }
        Branches = if ($baselineResult) { @($baselineResult.Scenarios) } else { @() }
        PairedComparisons = if ($baselineResult) { @($baselineResult.PairedComparisons) } else { @() }
        RunWallClockSeconds = [Math]::Round($stopwatch.Elapsed.TotalSeconds,3)
        DisposableSaveHashBefore = $disposableSaveHashBefore
        DisposableSaveHashAfter = $disposableSaveHashAfter
        DisposableSaveRemoved = $cleanupSucceeded
        PreExistingSaveManifestUnchanged = $saveManifestUnchanged
        ProcessStopped = $processStopped
        AgentSessionAbsent = $sessionAbsent
        StartedUtc = $runStartedUtc
        FinishedUtc = [DateTime]::UtcNow.ToString('O')
    })
}

$resultsArray = @($results)
$campaignIds = @($resultsArray | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.CampaignInstanceId) } | ForEach-Object { [string]$_.CampaignInstanceId } | Select-Object -Unique)
$result = [ordered]@{
    ProviderKind = 'deterministic Native fresh-Campaign supply baseline; not a real-model evaluation'
    Scenario = 'five independently created Campaign instances, each with paired no-provision and one-unit Native food-provision branches over three natural Town Wait daily ticks'
    RunCount = $Runs
    DistinctCampaignInstances = $campaignIds.Count
    CampaignRngSeedExposure = 'unknown; Chronicle Campaign instance IDs are not represented as Native RNG seeds'
    SourceSaveManifestUnchanged = (@($resultsArray | Where-Object { -not $_.PreExistingSaveManifestUnchanged }).Count -eq 0)
    AllDisposableSavesRemoved = (@($resultsArray | Where-Object { -not $_.DisposableSaveRemoved }).Count -eq 0)
    AllGameProcessesStopped = (@($resultsArray | Where-Object { -not $_.ProcessStopped }).Count -eq 0)
    AllAgentSessionsAbsent = (@($resultsArray | Where-Object { -not $_.AgentSessionAbsent }).Count -eq 0)
    SuccessfulCampaigns = @($resultsArray | Where-Object Passed).Count
    Passed = ($resultsArray.Count -eq $Runs -and $campaignIds.Count -eq $Runs -and @($resultsArray | Where-Object { -not $_.Passed }).Count -eq 0)
    Results = $resultsArray
}
$json = $result | ConvertTo-Json -Depth 20
Set-Content -LiteralPath (Join-Path $outerTemp 'FreshCampaignSupplyBaselineMatrix.json') -Value $json -Encoding UTF8
$json
if (-not $result.Passed) { exit 1 }
