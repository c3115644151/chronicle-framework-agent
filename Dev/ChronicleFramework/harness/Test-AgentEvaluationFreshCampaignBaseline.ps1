#Requires -Version 7.0
[CmdletBinding()]
param([ValidateRange(5,5)][int]$Runs = 5)

$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$freshCampaignScript = Join-Path $PSScriptRoot 'Test-AgentFreshCampaign.ps1'
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$saveDirectory = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\Game Saves'
$outerTemp = $env:CHRONICLE_HARNESS_TEMP
if (-not $outerTemp -or -not (Test-Path -LiteralPath $outerTemp -PathType Container)) { throw 'Fresh-Campaign baseline matrix requires an active Run-Harness TestResults temp directory.' }
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
    if (Get-Process -Name Bannerlord* -ErrorAction SilentlyContinue) { throw "Fresh-Campaign baseline run $runIndex found a Bannerlord client left by the preceding run." }
    $sessionHashBefore = if (Test-Path -LiteralPath $sessionPath -PathType Leaf) { (Get-FileHash -LiteralPath $sessionPath -Algorithm SHA256).Hash } else { $null }
    $runDirectory = Join-Path $evaluationRoot ('FreshCampaignBaselineRun-' + $runIndex.ToString('00'))
    $runTemp = Join-Path $runDirectory 'Temp'
    New-Item -ItemType Directory -Force -Path $runTemp | Out-Null
    $previousTemp = $env:CHRONICLE_HARNESS_TEMP
    $env:CHRONICLE_HARNESS_TEMP = $runTemp
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    $childResult = $null
    $childExitCode = 1
    $failure = $null
    try {
        $childOutput = & $HarnessPowerShell -NoProfile -File $freshCampaignScript -ValidateRecruitmentProgression 2>&1 | Out-String
        $childExitCode = $LASTEXITCODE
        try { $childResult = $childOutput | ConvertFrom-Json }
        catch { $failure = "FreshCampaign child did not return structured JSON (exit=$childExitCode): $childOutput" }
        if ($childExitCode -ne 0 -and -not $failure) { $failure = "FreshCampaign child exited $childExitCode after returning a structured result." }
    }
    catch { $failure = $_.Exception.Message }
    finally {
        $stopwatch.Stop()
        $env:CHRONICLE_HARNESS_TEMP = $previousTemp
    }

    if ($null -ne $childOutput) { Set-Content -LiteralPath (Join-Path $runDirectory 'FreshCampaignChildOutput.log') -Value $childOutput -Encoding UTF8 }
    if ($childResult) { $childResult | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $runDirectory 'FreshCampaignChildResult.json') -Encoding UTF8 }

    $processStopped = -not [bool](Get-Process -Name Bannerlord* -ErrorAction SilentlyContinue)
    $sessionHashAfter = if (Test-Path -LiteralPath $sessionPath -PathType Leaf) { (Get-FileHash -LiteralPath $sessionPath -Algorithm SHA256).Hash } else { $null }
    $sessionRestored = $sessionHashBefore -ceq $sessionHashAfter
    $saveManifestHashAfter = Get-SaveManifestHash
    $saveFilesUnchanged = $sourceSaveManifestHash -ceq $saveManifestHashAfter
    if (-not $processStopped) { $failure = if ($failure) { "$failure; Bannerlord process leaked." } else { 'Bannerlord process leaked.' } }
    if (-not $sessionRestored) { $failure = if ($failure) { "$failure; pre-existing Agent session was not restored exactly." } else { 'Pre-existing Agent session was not restored exactly.' } }
    if (-not $saveFilesUnchanged) { $failure = if ($failure) { "$failure; Game Saves manifest/hash changed." } else { 'Game Saves manifest/hash changed.' } }

    $initialState = $null
    if ($childResult -and $childResult.InitialAgentObservationPath -and (Test-Path -LiteralPath $childResult.InitialAgentObservationPath -PathType Leaf)) {
        try { $initialState = Get-Content -LiteralPath $childResult.InitialAgentObservationPath -Raw -Encoding UTF8 | ConvertFrom-Json }
        catch { $failure = if ($failure) { "$failure; initial Native observation artifact was unreadable." } else { 'Initial Native observation artifact was unreadable.' } }
    }
    $campaignCreated = [bool]($childResult -and $childResult.GameStarted -and $childResult.NativeNewCampaignRequested -and $childResult.CharacterCreationCompleted -and $childResult.InitialAgentObservationCaptured)
    $campaignInstanceId = if ($childResult) { [string]$childResult.ChronicleCampaignInstanceId } else { '' }
    $initialSafeSettlements = if ($initialState) { @($initialState.nearbySettlements | Where-Object { -not $_.hostile -and -not $_.underSiege }) } else { @() }
    $progression = if ($childResult) { $childResult.RecruitmentProgression } else { $null }
    $classification = if (-not $campaignCreated) { 'new-campaign-creation-failed' } elseif ($progression -and $progression.Passed) { 'native-move-and-recruitment-completed' } else { 'fresh-campaign-created-progression-failed-or-unavailable' }
    $runPassed = ($null -ne $childResult -and $campaignCreated -and -not [string]::IsNullOrWhiteSpace($campaignInstanceId) -and $processStopped -and $sessionRestored -and $saveFilesUnchanged -and -not $failure)
    if (-not $runPassed -and -not $failure) { $failure = 'Campaign identity, creation, or cleanup evidence was incomplete.' }

    $results.Add([pscustomobject]@{
        Run = $runIndex
        Passed = $runPassed
        Classification = $classification
        Failure = $failure
        WallClockSeconds = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 3)
        GameProcessId = if ($childResult) { $childResult.GameProcessId } else { $null }
        CampaignInstanceId = $campaignInstanceId
        CampaignSeed = 'unknown; instance ID is not the Native RNG seed'
        IntroSkipped = if ($childResult) { [bool]$childResult.OptionalIntroSkipped } else { $false }
        StartupDialogReceipts = if ($childResult) { @($childResult.StartupDialogReceipts) } else { @() }
        StartupDialogFailure = if ($childResult) { [string]$childResult.StartupDialogFailure } else { '' }
        InitialRenown = if ($initialState) { [double]$initialState.economy.renown } else { $null }
        InitialGold = if ($initialState) { [int]$initialState.economy.gold } else { $null }
        InitialPartyMembers = if ($initialState) { [int]$initialState.party.members } else { $null }
        InitialLocation = if ($initialState) { [ordered]@{ x = $initialState.location.x; y = $initialState.location.y } } else { $null }
        InitialVisibleSafeSettlements = @($initialSafeSettlements | ForEach-Object { [ordered]@{ id = $_.id; name = $_.name; type = $_.type; distance = $_.distance } })
        RecruitmentProgression = if ($progression) { $progression } else { $null }
        ProcessStopped = $processStopped
        PriorAgentSessionRestored = $sessionRestored
        ExistingSaveFilesUnchanged = $saveFilesUnchanged
        FreshCampaignArtifactDirectory = $runTemp
    })
}

$resultsArray = @($results)
$campaignIds = @($resultsArray | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.CampaignInstanceId) } | ForEach-Object { [string]$_.CampaignInstanceId } | Select-Object -Unique)
$createdCampaigns = @($resultsArray | Where-Object { $_.Classification -ne 'new-campaign-creation-failed' }).Count
$result = [ordered]@{
    ProviderKind = 'deterministic Native fresh-campaign baseline; not a real-model result'
    Scenario = 'five independently created 1.4.8 Campaign instances followed by the same Native visible-settlement recruitment slice'
    RunCount = $Runs
    DistinctCampaignInstances = $campaignIds.Count
    CampaignRngSeedExposure = 'unknown; Chronicle Campaign instance IDs are not represented as RNG seeds'
    FreshCampaignsCreated = $createdCampaigns
    NativeRecruitmentCompletions = @($resultsArray | Where-Object { $_.Classification -eq 'native-move-and-recruitment-completed' }).Count
    SourceSaveFilesUnchanged = (@($resultsArray | Where-Object { -not $_.ExistingSaveFilesUnchanged }).Count -eq 0)
    AllGameProcessesStopped = (@($resultsArray | Where-Object { -not $_.ProcessStopped }).Count -eq 0)
    AllPriorSessionsRestored = (@($resultsArray | Where-Object { -not $_.PriorAgentSessionRestored }).Count -eq 0)
    Passed = ($resultsArray.Count -eq $Runs -and $createdCampaigns -eq $Runs -and $campaignIds.Count -eq $Runs -and @($resultsArray | Where-Object { -not $_.Passed }).Count -eq 0)
    Results = $resultsArray
}
$json = $result | ConvertTo-Json -Depth 16
if ($outerTemp -and (Test-Path -LiteralPath $outerTemp -PathType Container)) { Set-Content -LiteralPath (Join-Path $outerTemp 'FreshCampaignBaselineMatrix.json') -Value $json -Encoding UTF8 }
$json
if (-not $result.Passed) { exit 1 }
