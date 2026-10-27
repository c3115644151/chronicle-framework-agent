[CmdletBinding()]
param(
    [ValidateRange(60,7200)][int]$HostMaxElapsedSeconds = 7200,
    [ValidateRange(5,30)][int]$FrameRate = 5,
    [int]$StartupTimeoutSeconds = 240,
    [ValidateRange(300,7500)][int]$FreshStoryModeHostTimeoutSeconds = 7500
)

$ErrorActionPreference = 'Stop'
$harnessRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($env:CHRONICLE_HARNESS_TEMP) -or -not (Test-Path -LiteralPath $env:CHRONICLE_HARNESS_TEMP -PathType Container)) {
    throw 'Persistent StoryMode evaluation requires an active Run-Harness evidence directory.'
}
$documentsPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
if ([string]::IsNullOrWhiteSpace($documentsPath)) { throw 'Windows Documents directory could not be resolved for the persistent EYC fixture.' }
$saveDirectory = [IO.Path]::GetFullPath((Join-Path $documentsPath 'Mount and Blade II Bannerlord\Game Saves'))
$saveRoot = $saveDirectory.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
$resultPath = Join-Path $env:CHRONICLE_HARNESS_TEMP 'PersistentEycCampaignResult.json'
$manifestPath = Join-Path $PSScriptRoot 'TestResults\PersistentEycCampaign.json'
$persistentSavePrefix = 'ChronicleEycDev-'
$freshCampaignScript = Join-Path $harnessRoot 'Test-AgentFreshCampaign.ps1'
$liveModelScript = Join-Path $harnessRoot 'Test-AgentLiveModelLoop.ps1'

function New-PersistentSaveName {
    return $persistentSavePrefix + (Get-Date -Format 'yyyyMMddHHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8)
}

function Get-SavePath([string]$SaveName) {
    if ($SaveName -notmatch '^ChronicleEycDev-[A-Za-z0-9_-]{1,32}$') { throw 'Persistent EYC manifest contains an unowned save name.' }
    $path = [IO.Path]::GetFullPath((Join-Path $saveDirectory ($SaveName + '.sav')))
    if (-not $path.StartsWith($saveRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Persistent EYC save path escaped Game Saves.' }
    return $path
}

function Get-Sha256([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }

function Get-AgentHostProgressUsage([string]$ProgressPath) {
    $providerDecisions = 0
    [long]$promptTokens = 0
    [long]$completionTokens = 0
    [double]$costEstimateCny = 0
    if (Test-Path -LiteralPath $ProgressPath -PathType Leaf) {
        foreach ($line in Get-Content -LiteralPath $ProgressPath -Encoding UTF8) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try { $entry = $line | ConvertFrom-Json } catch { continue }
            if ([string]$entry.event -cne 'provider-decision') { continue }
            $providerDecisions++
            $promptTokens += [long]$entry.promptTokens
            $completionTokens += [long]$entry.completionTokens
            $costEstimateCny += [double]$entry.estimatedCostCny
        }
    }
    [pscustomobject]@{
        ProviderDecisions = $providerDecisions
        PromptTokens = $promptTokens
        CompletionTokens = $completionTokens
        CostEstimateCny = [Math]::Round($costEstimateCny, 9)
    }
}

function Get-VerifiedCampaignProgressUsage([string]$CampaignInstanceId) {
    $total = [ordered]@{ ProviderDecisions = 0; PromptTokens = [long]0; CompletionTokens = [long]0; CostEstimateCny = [double]0; ReceiptRunCount = 0 }
    $resultsRoot = Join-Path $PSScriptRoot 'TestResults'
    foreach ($runDirectory in Get-ChildItem -LiteralPath $resultsRoot -Directory -ErrorAction SilentlyContinue) {
        $tempDirectory = Join-Path $runDirectory.FullName 'Temp'
        $freshReceiptPath = Join-Path $tempDirectory 'FreshCampaignResult.json'
        $liveReceiptPath = Join-Path $tempDirectory 'LiveModelLoopResult.json'
        $runBelongsToCampaign = $false
        if (Test-Path -LiteralPath $freshReceiptPath -PathType Leaf) {
            try {
                $receipt = Get-Content -LiteralPath $freshReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $runBelongsToCampaign = [bool]$receipt.PersistentStoryModeSeed -and
                    [string]$receipt.ChronicleCampaignInstanceId -ceq $CampaignInstanceId -and
                    [string]$receipt.PersistentStoryModeSaveName -match '^ChronicleEycDev-'
            }
            catch { $runBelongsToCampaign = $false }
        }
        if (-not $runBelongsToCampaign -and (Test-Path -LiteralPath $liveReceiptPath -PathType Leaf)) {
            try {
                $receipt = Get-Content -LiteralPath $liveReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $runBelongsToCampaign = [string]$receipt.CampaignInstanceId -ceq $CampaignInstanceId -and
                    [string]$receipt.CheckpointSaveName -match '^ChronicleEycDev-'
            }
            catch { $runBelongsToCampaign = $false }
        }
        if (-not $runBelongsToCampaign) { continue }
        $usage = Get-AgentHostProgressUsage (Join-Path $tempDirectory 'AgentHostProgress.jsonl')
        $total.ProviderDecisions += [int]$usage.ProviderDecisions
        $total.PromptTokens += [long]$usage.PromptTokens
        $total.CompletionTokens += [long]$usage.CompletionTokens
        $total.CostEstimateCny += [double]$usage.CostEstimateCny
        $total.ReceiptRunCount++
    }
    $total.CostEstimateCny = [Math]::Round([double]$total.CostEstimateCny, 9)
    [pscustomobject]$total
}

function Get-VerifiedOrphanSeedReceipt([string]$SaveName) {
    $savePath = Get-SavePath $SaveName
    if (-not (Test-Path -LiteralPath $savePath -PathType Leaf)) { return @() }
    $saveHash = Get-Sha256 $savePath
    $receiptRoot = Join-Path $PSScriptRoot 'TestResults'
    $matches = [Collections.Generic.List[object]]::new()
    foreach ($runDirectory in Get-ChildItem -LiteralPath $receiptRoot -Directory -ErrorAction SilentlyContinue) {
        $receiptPath = Join-Path $runDirectory.FullName 'Temp\FreshCampaignResult.json'
        if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) { continue }
        try { $receipt = Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json }
        catch { continue }
        $receiptSavePath = [string]$receipt.PersistentStoryModeSavePath
        if ([string]$receipt.PersistentStoryModeSaveName -cne $SaveName -or
            -not [bool]$receipt.PersistentStoryModeSaveRetained -or [bool]$receipt.CrashDetected -or
            -not [bool]$receipt.BannerlordProcessesCleanAtExit -or
            [string]::IsNullOrWhiteSpace([string]$receipt.ChronicleCampaignInstanceId) -or
            [string]$receipt.PersistentStoryModeSaveHash -cne $saveHash) { continue }
        if ([string]::IsNullOrWhiteSpace($receiptSavePath) -or
            [IO.Path]::GetFullPath($receiptSavePath) -cne $savePath) { continue }
        $matches.Add([pscustomobject]@{ Receipt = $receipt; ReceiptPath = $receiptPath; SavePath = $savePath; Sha256 = $saveHash })
    }
    return @($matches)
}

function Write-PersistentManifest([object]$Manifest) {
    $temporaryPath = $manifestPath + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    $json = $Manifest | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText($temporaryPath, $json, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporaryPath -Destination $manifestPath -Force
}

function New-PersistentSeedManifest([object]$Receipt, [string]$SaveName, [string]$SaveHash, [object]$Usage) {
    if ($null -eq $Usage) {
        $Usage = [pscustomobject]@{ ProviderDecisions = 0; PromptTokens = [long]0; CompletionTokens = [long]0; CostEstimateCny = [double]0; ReceiptRunCount = 0 }
    }
    if ($null -eq $Usage) {
        $Usage = [pscustomobject]@{ ProviderDecisions = 0; PromptTokens = [long]0; CompletionTokens = [long]0; CostEstimateCny = [double]0; ReceiptRunCount = 0 }
    }
    return [pscustomobject]@{
        schemaVersion = 1
        project = 'ChronicleFramework'
        campaignInstanceId = [string]$Receipt.ChronicleCampaignInstanceId
        saveName = $SaveName
        sha256 = $SaveHash
        previousSaveName = $null
        previousSha256 = $null
        seedRunUtc = [DateTime]::UtcNow.ToString('O')
        lastCheckpointUtc = [DateTime]::UtcNow.ToString('O')
        checkpointCount = 1
        usageMetric = 'AgentHostProgress.jsonl provider-decision events'
        usageReceiptRunCount = if ($null -ne $Usage) { [int]$Usage.ReceiptRunCount } else { 0 }
        cumulativeDecisions = [int]$Usage.ProviderDecisions
        cumulativePromptTokens = [long]$Usage.PromptTokens
        cumulativeCompletionTokens = [long]$Usage.CompletionTokens
        cumulativeProviderActualCostEstimateCny = [double]$Usage.CostEstimateCny
        lastHostStatus = [string]$Receipt.StoryModeAgentHostTerminalState
        lastFailureCode = [string]$Receipt.StoryModeAgentFailureCode
    }
}

function Invoke-JsonChild([string]$ScriptPath, [string[]]$Arguments, [string]$ChildResultFileName) {
    if ([string]::IsNullOrWhiteSpace($ChildResultFileName) -or [IO.Path]::GetFileName($ChildResultFileName) -cne $ChildResultFileName) {
        throw 'Persistent EYC child result file must be one safe file name inside the current Harness temp directory.'
    }
    $childResultPath = Join-Path $env:CHRONICLE_HARNESS_TEMP $ChildResultFileName
    Remove-Item -LiteralPath $childResultPath -Force -ErrorAction SilentlyContinue
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Arguments 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    try { $evidence = Get-Content -LiteralPath $childResultPath -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw "Persistent EYC child script returned no structured evidence (exit=$exitCode)." }
    return [pscustomobject]@{ ExitCode = $exitCode; Evidence = $evidence; Output = $output }
}

function Remove-ObsoleteOwnedSaves([string[]]$KeepNames) {
    $keep = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($name in $KeepNames | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) { [void]$keep.Add([string]$name) }
    foreach ($file in Get-ChildItem -LiteralPath $saveDirectory -File -Filter ($persistentSavePrefix + '*.sav') -ErrorAction SilentlyContinue) {
        $name = [IO.Path]::GetFileNameWithoutExtension($file.Name)
        if ($keep.Contains($name)) { continue }
        $fullPath = [IO.Path]::GetFullPath($file.FullName)
        if (-not $fullPath.StartsWith($saveRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Persistent EYC retention cleanup escaped Game Saves.' }
        Remove-Item -LiteralPath $fullPath -Force
    }
}

$manifest = $null
$seedEvidence = $null
$sourceSaveName = $null
$sourceHash = $null
$sourceCampaignInstanceId = $null
$seedCreated = $false
$seedRecoveredFromReceipt = $false
$liveExitCode = $null
$liveEvidence = $null
$liveTrace = $null
$checkpointSaveName = $null
$checkpointSaveHash = $null
$checkpointSaved = $false
$campaignContinued = $false
$eycCompleted = $false
$manifestUpdated = $false
$failure = $null
$liveRunActualCost = 0d
$liveRunDecisions = 0
$liveRunPromptTokens = 0L
$liveRunCompletionTokens = 0L
$seedHostStatus = $null
$seedHostFailureCode = $null

try {
    if (-not (Test-Path -LiteralPath $saveDirectory -PathType Container) -or
        -not (Test-Path -LiteralPath $freshCampaignScript -PathType Leaf) -or
        -not (Test-Path -LiteralPath $liveModelScript -PathType Leaf)) {
        throw 'Persistent EYC save directory or supporting Harness script is unavailable.'
    }

    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([int]$manifest.schemaVersion -ne 1 -or [string]$manifest.project -cne 'ChronicleFramework' -or
            [string]::IsNullOrWhiteSpace([string]$manifest.saveName) -or [string]::IsNullOrWhiteSpace([string]$manifest.sha256) -or
            [string]::IsNullOrWhiteSpace([string]$manifest.campaignInstanceId)) {
            throw 'Persistent EYC manifest is invalid; no save was loaded or overwritten.'
        }
        $sourceSaveName = [string]$manifest.saveName
        $sourcePath = Get-SavePath $sourceSaveName
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf) -or (Get-Sha256 $sourcePath) -cne [string]$manifest.sha256) {
            throw 'Persistent EYC checkpoint hash does not match its manifest; the test will not silently restart from a new campaign.'
        }
        $sourceHash = [string]$manifest.sha256
        $sourceCampaignInstanceId = [string]$manifest.campaignInstanceId
        if ([string]$manifest.usageMetric -cne 'AgentHostProgress.jsonl provider-decision events') {
            $historicalUsage = Get-VerifiedCampaignProgressUsage $sourceCampaignInstanceId
            if ($historicalUsage.ProviderDecisions -gt 0) {
                $manifest.usageMetric = 'AgentHostProgress.jsonl provider-decision events'
                $manifest.usageReceiptRunCount = [int]$historicalUsage.ReceiptRunCount
                $manifest.cumulativeDecisions = [int]$historicalUsage.ProviderDecisions
                $manifest.cumulativePromptTokens = [long]$historicalUsage.PromptTokens
                $manifest.cumulativeCompletionTokens = [long]$historicalUsage.CompletionTokens
                $manifest.cumulativeProviderActualCostEstimateCny = [double]$historicalUsage.CostEstimateCny
                Write-PersistentManifest $manifest
                $manifestUpdated = $true
            }
        }
    }
    else {
        $orphanSaves = @(Get-ChildItem -LiteralPath $saveDirectory -File -Filter ($persistentSavePrefix + '*.sav') -ErrorAction SilentlyContinue)
        if ($orphanSaves.Count -gt 1) {
            throw 'Multiple Harness-owned EYC saves exist without a manifest; refusing to choose among them automatically.'
        }
        if ($orphanSaves.Count -eq 1) {
            $sourceSaveName = [IO.Path]::GetFileNameWithoutExtension($orphanSaves[0].Name)
            $verifiedReceipts = @(Get-VerifiedOrphanSeedReceipt $sourceSaveName)
            if ($verifiedReceipts.Count -ne 1) {
                throw 'One Harness-owned EYC save exists without a manifest, but it has no unique matching Native SaveAs/hash/process-cleanup receipt; refusing to load it.'
            }
            $seedEvidence = $verifiedReceipts[0].Receipt
            $sourcePath = [string]$verifiedReceipts[0].SavePath
            $sourceHash = [string]$verifiedReceipts[0].Sha256
            if (-not [bool]$seedEvidence.StoryModeOfficialTutorialSkipConfirmed -or
                -not [bool]$seedEvidence.StoryModeFirstMapStateObserved -or
                -not [bool]$seedEvidence.OriginalEstablishYourClanQuestNaturallyActive) {
                throw 'The orphan Native checkpoint does not prove the required natural StoryMode tutorial/Quest start state.'
            }
            $sourceCampaignInstanceId = [string]$seedEvidence.ChronicleCampaignInstanceId
            $historicalUsage = Get-VerifiedCampaignProgressUsage $sourceCampaignInstanceId
            $manifest = New-PersistentSeedManifest -Receipt $seedEvidence -SaveName $sourceSaveName -SaveHash $sourceHash -Usage $historicalUsage
            Write-PersistentManifest $manifest
            $manifestUpdated = $true
            $seedRecoveredFromReceipt = $true
            $liveRunActualCost = [double]$manifest.cumulativeProviderActualCostEstimateCny
            $liveRunDecisions = [int]$manifest.cumulativeDecisions
            $liveRunPromptTokens = [long]$manifest.cumulativePromptTokens
            $liveRunCompletionTokens = [long]$manifest.cumulativeCompletionTokens
            $seedHostStatus = [string]$manifest.lastHostStatus
            $seedHostFailureCode = [string]$manifest.lastFailureCode
        }
        else {
            $sourceSaveName = New-PersistentSaveName
            $sourcePath = Get-SavePath $sourceSaveName
            if (Test-Path -LiteralPath $sourcePath) { throw 'Generated EYC seed save name already exists; refusing to overwrite it.' }
            Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue
            $savedAutoStart = [Environment]::GetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_AUTO_START','Process')
            $savedAutoStop = [Environment]::GetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_AUTO_STOP_AFTER_MS','Process')
            $savedGoal = [Environment]::GetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_GOAL','Process')
            $savedHarnessModel = [Environment]::GetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_MODEL','Process')
            try {
                [Environment]::SetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_AUTO_START','1','Process')
                [Environment]::SetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_AUTO_STOP_AFTER_MS','7200000','Process')
                [Environment]::SetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_GOAL','自主完成原版主线任务“建立你的家族”。','Process')
                [Environment]::SetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_MODEL',[Environment]::GetEnvironmentVariable('CHRONICLE_LLM_MODEL','Process'),'Process')
                Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue
                $seed = Invoke-JsonChild $freshCampaignScript @('-StoryModeEycSetup','-StoryModeEycLiveModelEvaluation','-StoryModeEycPersistentSeed',
                    '-PersistentStoryModeSaveName',$sourceSaveName,'-TimeoutSeconds',[string]$FreshStoryModeHostTimeoutSeconds) 'FreshCampaignResult.json'
            }
            finally {
                [Environment]::SetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_AUTO_START',$savedAutoStart,'Process')
                [Environment]::SetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_AUTO_STOP_AFTER_MS',$savedAutoStop,'Process')
                [Environment]::SetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_GOAL',$savedGoal,'Process')
                [Environment]::SetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_MODEL',$savedHarnessModel,'Process')
            }
            $seedEvidence = $seed.Evidence
            if (-not [bool]$seedEvidence.PersistentStoryModeSaveRetained -or [bool]$seedEvidence.CrashDetected -or
                -not [bool]$seedEvidence.BannerlordProcessesCleanAtExit -or
                [string]$seedEvidence.PersistentStoryModeSaveName -cne $sourceSaveName -or
                [string]::IsNullOrWhiteSpace([string]$seedEvidence.ChronicleCampaignInstanceId)) {
                throw 'Natural StoryMode seed/save did not verify Native setup, Tutorial skip, Campaign identity, save receipt and process cleanup.'
            }
            if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw 'Seed receipt passed but the Native StoryMode save file is missing.' }
            $sourceHash = Get-Sha256 $sourcePath
            if ($sourceHash -cne [string]$seedEvidence.PersistentStoryModeSaveHash) { throw 'StoryMode seed save hash changed after Native SaveAs receipt.' }
            $sourceCampaignInstanceId = [string]$seedEvidence.ChronicleCampaignInstanceId
            $seedCreated = $true
            $liveExitCode = $seed.ExitCode
            $liveTrace = $null
            $seedUsage = Get-AgentHostProgressUsage (Join-Path $env:CHRONICLE_HARNESS_TEMP 'AgentHostProgress.jsonl')
            $liveRunActualCost = [double]$seedUsage.CostEstimateCny
            $liveRunDecisions = [int]$seedUsage.ProviderDecisions
            $liveRunPromptTokens = [long]$seedUsage.PromptTokens
            $liveRunCompletionTokens = [long]$seedUsage.CompletionTokens
            $seedHostStatus = [string]$seedEvidence.StoryModeAgentHostTerminalState
            $seedHostFailureCode = [string]$seedEvidence.StoryModeAgentFailureCode
            $checkpointSaveName = $sourceSaveName
            $checkpointSaved = $true
            $campaignContinued = $true
            $eycCompleted = [bool]$seedEvidence.StoryModeOriginalEstablishYourClanCompleted
            if ($seed.ExitCode -ne 0 -or -not [bool]$seedEvidence.Passed) {
                $failure = 'The natural StoryMode seed Host did not pass the bounded Host/visual/cleanup checks; its verified Native checkpoint is retained for diagnosis or continuation.'
            }
            $manifest = New-PersistentSeedManifest -Receipt $seedEvidence -SaveName $sourceSaveName -SaveHash $sourceHash -Usage $seedUsage
            Write-PersistentManifest $manifest
            $manifestUpdated = $true
        }
    }

    if (-not $seedCreated) {
        $checkpointSaveName = New-PersistentSaveName
        Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue
        $live = Invoke-JsonChild $liveModelScript @('-LoadSaveName',$sourceSaveName,'-CheckpointSaveName',$checkpointSaveName,
            '-EstablishYourClanAutonomyLoop','-AgentHostRuntime','-FrameRate',[string]$FrameRate,
            '-TimeoutSeconds',[string]$StartupTimeoutSeconds,'-HostMaxElapsedSeconds',[string]$HostMaxElapsedSeconds) 'LiveModelLoopResult.json'
        $liveExitCode = $live.ExitCode
        $liveEvidence = $live.Evidence
        $liveTrace = $liveEvidence.Trace
        $liveUsage = Get-AgentHostProgressUsage (Join-Path $env:CHRONICLE_HARNESS_TEMP 'AgentHostProgress.jsonl')
        $liveRunActualCost = [double]$liveUsage.CostEstimateCny
        $liveRunDecisions = [int]$liveUsage.ProviderDecisions
        $liveRunPromptTokens = [long]$liveUsage.PromptTokens
        $liveRunCompletionTokens = [long]$liveUsage.CompletionTokens
        $campaignContinued = [string]$liveEvidence.CampaignInstanceId -ceq $sourceCampaignInstanceId
        $checkpointPath = Get-SavePath $checkpointSaveName
        $checkpointSaved = ([bool]$liveEvidence.CheckpointSaveRetained -and
            [string]$liveEvidence.CheckpointSaveName -ceq $checkpointSaveName -and
            [string]$liveEvidence.CheckpointSaveHash -and
            (Test-Path -LiteralPath $checkpointPath -PathType Leaf) -and
            (Get-Sha256 $checkpointPath) -ceq [string]$liveEvidence.CheckpointSaveHash)
        if ($checkpointSaved) { $checkpointSaveHash = [string]$liveEvidence.CheckpointSaveHash }
        $eycCompleted = ($liveTrace.status -ceq 'completed' -and [bool]$liveTrace.termination.goalVerified -and
            [string]$liveTrace.termination.reason -ceq 'native-establish-your-clan-quest-success-verified')

        if ($checkpointSaved -and $campaignContinued) {
            $oldCurrentName = [string]$manifest.saveName
            $oldCurrentHash = [string]$manifest.sha256
            $manifest.previousSaveName = $oldCurrentName
            $manifest.previousSha256 = $oldCurrentHash
            $manifest.saveName = $checkpointSaveName
            $manifest.sha256 = [string]$liveEvidence.CheckpointSaveHash
            $manifest.lastCheckpointUtc = [DateTime]::UtcNow.ToString('O')
            $manifest.checkpointCount = [int]$manifest.checkpointCount + 1
            $manifest.cumulativeDecisions = [int]$manifest.cumulativeDecisions + $liveRunDecisions
            $manifest.cumulativePromptTokens = [long]$manifest.cumulativePromptTokens + $liveRunPromptTokens
            $manifest.cumulativeCompletionTokens = [long]$manifest.cumulativeCompletionTokens + $liveRunCompletionTokens
            $manifest.cumulativeProviderActualCostEstimateCny = [Math]::Round([double]$manifest.cumulativeProviderActualCostEstimateCny + $liveRunActualCost, 6)
            if ($liveRunDecisions -gt 0) {
                $manifest.usageMetric = 'AgentHostProgress.jsonl provider-decision events'
                $manifest.usageReceiptRunCount = [int]$manifest.usageReceiptRunCount + 1
            }
            $manifest.lastHostStatus = [string]$liveTrace.status
            $manifest.lastFailureCode = if ($liveTrace.failureCode) { [string]$liveTrace.failureCode } else { $null }
            Write-PersistentManifest $manifest
            $manifestUpdated = $true
            Remove-ObsoleteOwnedSaves @([string]$manifest.saveName,[string]$manifest.previousSaveName)
        }
    }

    if ($seedCreated) {
        $checkpointSaved = [bool]$seedEvidence.PersistentStoryModeSaveRetained
        $campaignContinued = $checkpointSaved -and -not [string]::IsNullOrWhiteSpace($sourceCampaignInstanceId)
        $checkpointSaveName = $sourceSaveName
        if ($checkpointSaved) { $checkpointSaveHash = $sourceHash }
        $eycCompleted = [bool]$seedEvidence.StoryModeOriginalEstablishYourClanCompleted
        if (-not $checkpointSaved) { $failure = 'The natural StoryMode run produced no verified persistent Native checkpoint; the campaign will not be reset automatically.' }
        elseif (-not $eycCompleted) { $failure = 'The natural StoryMode Host run ended before EYC completion; its Native checkpoint is retained for the next continuation.' }
        else { $failure = 'The Native EYC completion signal lacks a fully passing fresh-run cleanup or visual receipt.' }
    }
    elseif (-not $checkpointSaved) { $failure = 'The current run produced no verified Native checkpoint; the previous persistent campaign remains selected.' }
    elseif (-not $campaignContinued) { $failure = 'The loaded save did not preserve the recorded Native Campaign instance identity; the previous checkpoint remains selected.' }
    elseif (-not $eycCompleted) { $failure = 'The persistent natural StoryMode campaign checkpointed successfully but the original Establish Your Clan Quest remains incomplete.' }
    elseif ($liveExitCode -ne 0 -or -not [bool]$liveEvidence.Passed) { $failure = 'The Native EYC completion signal was not accompanied by a fully passing Host, visual, and cleanup receipt.' }
}
catch {
    if (-not $failure) { $failure = $_.Exception.Message }
}

$result = [ordered]@{
    Passed = [string]::IsNullOrWhiteSpace($failure) -and $checkpointSaved -and $campaignContinued -and $eycCompleted -and $manifestUpdated
    Failure = $failure
    SeedCreated = $seedCreated
    SeedRecoveredFromReceipt = $seedRecoveredFromReceipt
    SourceSaveName = $sourceSaveName
    SourceSaveSha256 = $sourceHash
    CampaignInstanceId = $sourceCampaignInstanceId
    CampaignContinued = $campaignContinued
    CheckpointSaveName = $checkpointSaveName
    CheckpointSaveSha256 = if ($checkpointSaved) { $checkpointSaveHash } else { $null }
    CheckpointSaved = $checkpointSaved
    EycCompleted = $eycCompleted
    HostStatus = if ($liveTrace) { [string]$liveTrace.status } elseif ($seedEvidence) { [string]$seedEvidence.StoryModeAgentHostTerminalState } else { $null }
    HostFailureCode = if ($liveTrace) { [string]$liveTrace.failureCode } elseif ($seedEvidence) { [string]$seedEvidence.StoryModeAgentFailureCode } else { $null }
    DecisionsThisRun = $liveRunDecisions
    PromptTokensThisRun = $liveRunPromptTokens
    CompletionTokensThisRun = $liveRunCompletionTokens
    ActualCostEstimateCnyThisRun = $liveRunActualCost
    CumulativeDecisions = if ($manifest) { [int]$manifest.cumulativeDecisions } else { $null }
    CumulativeActualCostEstimateCny = if ($manifest) { [double]$manifest.cumulativeProviderActualCostEstimateCny } else { $null }
    ManifestPath = $manifestPath
    ManifestUpdated = $manifestUpdated
    GameProcessesClean = if ($liveEvidence) { [bool]$liveEvidence.ProcessStopped } elseif ($seedEvidence) { [bool]$seedEvidence.BannerlordProcessesCleanAtExit } else { $null }
}
$json = $result | ConvertTo-Json -Depth 6
Set-Content -LiteralPath $resultPath -Value $json -Encoding UTF8
$json
if (-not $result.Passed) { exit 1 }
