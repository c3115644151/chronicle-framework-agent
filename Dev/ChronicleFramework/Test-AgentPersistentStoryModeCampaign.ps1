[CmdletBinding()]
param(
    [ValidateRange(60,86400)][int]$HostMaxElapsedSeconds = 86400,
    [ValidateRange(1,160)][int]$MaxProviderDecisionsPerContinuation = 1,
    [ValidateRange(1,2)][int]$MaxHttpRequestsPerDecision = 1,
    [ValidateRange(5,30)][int]$FrameRate = 5,
    [int]$StartupTimeoutSeconds = 240,
    [ValidateRange(300,87000)][int]$FreshStoryModeHostTimeoutSeconds = 87000,
    [string]$CampaignKey = '',
    [switch]$UsageSelfTest
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
$CampaignKey = $CampaignKey.Trim()
if ($CampaignKey -notmatch '^(?:[A-Za-z0-9_-]{1,8})?$') { throw 'CampaignKey must be empty for the primary campaign or 1-8 safe filename characters for an isolated persistent branch.' }
$campaignFileSuffix = if ([string]::IsNullOrWhiteSpace($CampaignKey)) { '' } else { '-' + $CampaignKey }
$manifestPath = Join-Path $PSScriptRoot ('TestResults\PersistentEycCampaign' + $campaignFileSuffix + '.json')
$persistentSavePrefix = 'ChronicleEycDev-' + $(if ([string]::IsNullOrWhiteSpace($CampaignKey)) { '' } else { $CampaignKey + '-' })
$freshCampaignScript = Join-Path $harnessRoot 'Test-AgentFreshCampaign.ps1'
$liveModelScript = Join-Path $harnessRoot 'Test-AgentLiveModelLoop.ps1'
$bannerlordConfigPath = Join-Path $documentsPath 'Mount and Blade II Bannerlord\Configs\BannerlordConfig.txt'
$focusPauseLease = $null
$focusPauseContract = $null
$focusPauseRestoreResult = [pscustomobject]@{ changedByHarness = $false; restored = $true; reason = 'not-applied' }

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

function Get-Utf8FileState([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $encoding = [Text.UTF8Encoding]::new($hasBom)
    $offset = if ($hasBom) { 3 } else { 0 }
    [pscustomobject]@{ Bytes = $bytes; Text = $encoding.GetString($bytes, $offset, $bytes.Length - $offset); Encoding = $encoding; HasBom = $hasBom }
}

function Set-HarnessFocusPauseLease([string]$ConfigurationPath = $bannerlordConfigPath) {
    if (-not (Test-Path -LiteralPath $ConfigurationPath -PathType Leaf)) {
        throw 'BannerlordConfig.txt is required to inspect the Native StopGameOnFocusLost preference before a persistent long test.'
    }
    $file = Get-Utf8FileState $ConfigurationPath
    $pattern = '(?m)^(StopGameOnFocusLost=)(True|False)(?=\r?$)'
    $matches = [regex]::Matches($file.Text, $pattern)
    if ($matches.Count -ne 1) { throw 'BannerlordConfig.txt must contain exactly one StopGameOnFocusLost setting; no game was launched.' }
    $originalValue = $matches[0].Groups[2].Value
    if ($originalValue -ceq 'False') {
        return [pscustomobject]@{ path = $ConfigurationPath; changedByHarness = $false; originalValue = $originalValue; expectedHarnessValue = $originalValue; hasBom = $file.HasBom }
    }
    $updated = [regex]::Replace($file.Text, $pattern, '${1}False', 1)
    [IO.File]::WriteAllText($ConfigurationPath, $updated, $file.Encoding)
    return [pscustomobject]@{ path = $ConfigurationPath; changedByHarness = $true; originalValue = $originalValue; expectedHarnessValue = 'False'; hasBom = $file.HasBom }
}

function Restore-HarnessFocusPauseLease([object]$Lease) {
    if ($null -eq $Lease -or -not [bool]$Lease.changedByHarness) {
        return [pscustomobject]@{ changedByHarness = [bool]($Lease -and $Lease.changedByHarness); restored = $true; reason = 'no-override-needed' }
    }
    if (Get-Process -Name Bannerlord* -ErrorAction SilentlyContinue) {
        return [pscustomobject]@{ changedByHarness = $true; restored = $false; reason = 'game-process-still-running'; settingPath = $Lease.path }
    }
    $file = Get-Utf8FileState ([string]$Lease.path)
    $pattern = '(?m)^(StopGameOnFocusLost=)(True|False)(?=\r?$)'
    $matches = [regex]::Matches($file.Text, $pattern)
    if ($matches.Count -ne 1) {
        return [pscustomobject]@{ changedByHarness = $true; restored = $false; reason = 'setting-was-removed-or-duplicated'; settingPath = $Lease.path }
    }
    if ($matches[0].Groups[2].Value -cne [string]$Lease.expectedHarnessValue) {
        return [pscustomobject]@{ changedByHarness = $true; restored = $false; reason = 'setting-was-changed-during-test'; settingPath = $Lease.path }
    }
    $updated = [regex]::Replace($file.Text, $pattern, ('${1}' + [string]$Lease.originalValue), 1)
    [IO.File]::WriteAllText([string]$Lease.path, $updated, $file.Encoding)
    return [pscustomobject]@{ changedByHarness = $true; restored = $true; reason = 'original-user-value-restored'; restoredValue = [string]$Lease.originalValue }
}

function Test-HarnessFocusPauseLeaseContract {
    $path = Join-Path $env:CHRONICLE_HARNESS_TEMP 'FocusPauseLeaseContract-BannerlordConfig.txt'
    try {
        [IO.File]::WriteAllText($path, "MapDoubleClickBehavior=0`r`nStopGameOnFocusLost=True`r`n", [Text.UTF8Encoding]::new($false))
        $lease = Set-HarnessFocusPauseLease $path
        $disabled = Get-Utf8FileState $path
        if (-not $lease.changedByHarness -or $disabled.Text -notmatch '(?m)^StopGameOnFocusLost=False\r?$') {
            throw 'The Harness did not disable only the focus-loss pause setting in the disposable config contract.'
        }
        $restored = Restore-HarnessFocusPauseLease $lease
        $after = Get-Utf8FileState $path
        if (-not $restored.restored -or $after.Text -cne "MapDoubleClickBehavior=0`r`nStopGameOnFocusLost=True`r`n") {
            throw 'The Harness did not restore the original focus-loss setting and preserve neighboring config values.'
        }
        return [pscustomobject]@{ passed = $true; temporaryValue = 'False'; restoredValue = 'True'; unrelatedSettingPreserved = $true }
    }
    finally { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
}

function Get-AgentHostProgressUsage([string]$ProgressPath) {
    $providerDecisions = 0
    $providerRequests = 0
    $providerFailures = 0
    $providerFailuresWithUsage = 0
    $providerFailuresWithoutUsage = 0
    $unpricedProviderFailures = 0
    $unpricedProviderResponses = 0
    $tokenUsageComplete = $true
    $costEstimateComplete = $true
    [long]$promptTokens = 0
    [long]$completionTokens = 0
    [long]$failedPromptTokens = 0
    [long]$failedCompletionTokens = 0
    [double]$costEstimateCny = 0
    if (Test-Path -LiteralPath $ProgressPath -PathType Leaf) {
        foreach ($line in Get-Content -LiteralPath $ProgressPath -Encoding UTF8) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try { $entry = $line | ConvertFrom-Json } catch { continue }
            if ([string]$entry.event -ceq 'provider-decision') {
                $providerDecisions++
                $providerRequests++
                if ($null -ne $entry.promptTokens) { $promptTokens += [long]$entry.promptTokens } else { $tokenUsageComplete = $false }
                if ($null -ne $entry.completionTokens) { $completionTokens += [long]$entry.completionTokens } else { $tokenUsageComplete = $false }
                if ($null -ne $entry.estimatedCostCny) { $costEstimateCny += [double]$entry.estimatedCostCny } else { $costEstimateComplete = $false; $unpricedProviderResponses++ }
                continue
            }
            if ([string]$entry.event -cne 'provider-failure') { continue }
            $providerRequests++
            $providerFailures++
            $failureHasPrompt = $null -ne $entry.providerResponsePromptTokens
            $failureHasCompletion = $null -ne $entry.providerResponseCompletionTokens
            if ($failureHasPrompt) {
                $failedPromptTokens += [long]$entry.providerResponsePromptTokens
                $promptTokens += [long]$entry.providerResponsePromptTokens
            }
            if ($failureHasCompletion) {
                $failedCompletionTokens += [long]$entry.providerResponseCompletionTokens
                $completionTokens += [long]$entry.providerResponseCompletionTokens
            }
            if ($failureHasPrompt -and $failureHasCompletion) { $providerFailuresWithUsage++ }
            else { $providerFailuresWithoutUsage++; $tokenUsageComplete = $false }
            if ($null -ne $entry.providerFailureCostEstimateCny) { $costEstimateCny += [double]$entry.providerFailureCostEstimateCny }
            else { $costEstimateComplete = $false; $unpricedProviderResponses++; $unpricedProviderFailures++ }
        }
    }
    [pscustomobject]@{
        ProviderDecisions = $providerDecisions
        ProviderRequests = $providerRequests
        ProviderFailures = $providerFailures
        ProviderFailuresWithUsage = $providerFailuresWithUsage
        ProviderFailuresWithoutUsage = $providerFailuresWithoutUsage
        UnpricedProviderFailures = $unpricedProviderFailures
        PromptTokens = $promptTokens
        CompletionTokens = $completionTokens
        FailedPromptTokens = $failedPromptTokens
        FailedCompletionTokens = $failedCompletionTokens
        TokenUsageComplete = $tokenUsageComplete
        CostEstimateCny = [Math]::Round($costEstimateCny, 9)
        CostEstimateComplete = $costEstimateComplete
        UnpricedProviderResponses = $unpricedProviderResponses
    }
}

function Set-PersistentManifestProperty([object]$Manifest, [string]$Name, [object]$Value) {
    if ($null -eq $Manifest.PSObject.Properties[$Name]) {
        $Manifest | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
    else { $Manifest.$Name = $Value }
}

function Test-AgentHostProgressUsageAccounting {
    $path = Join-Path $env:CHRONICLE_HARNESS_TEMP ('PersistentEycUsageSelfTest-' + [Guid]::NewGuid().ToString('N') + '.jsonl')
    try {
        $rows = @(
            [ordered]@{ event = 'provider-decision'; promptTokens = 100; completionTokens = 20; estimatedCostCny = 0.01 },
            [ordered]@{ event = 'provider-failure'; providerResponsePromptTokens = 1437; providerResponseCompletionTokens = 256; providerRoute = 'kilo/test-model:free' },
            [ordered]@{ event = 'provider-failure'; providerResponsePromptTokens = $null; providerResponseCompletionTokens = $null; providerRoute = 'https://untrusted.example' }
        )
        [IO.File]::WriteAllLines($path, @($rows | ForEach-Object { $_ | ConvertTo-Json -Compress }), [Text.UTF8Encoding]::new($false))
        $usage = Get-AgentHostProgressUsage $path
        if ($usage.ProviderDecisions -ne 1 -or $usage.ProviderRequests -ne 3 -or $usage.ProviderFailures -ne 2 -or
            $usage.ProviderFailuresWithUsage -ne 1 -or $usage.ProviderFailuresWithoutUsage -ne 1 -or
            $usage.UnpricedProviderFailures -ne 2 -or
            $usage.PromptTokens -ne 1537 -or $usage.CompletionTokens -ne 276 -or
            $usage.FailedPromptTokens -ne 1437 -or $usage.FailedCompletionTokens -ne 256 -or
            $usage.TokenUsageComplete -or $usage.CostEstimateComplete -or $usage.UnpricedProviderResponses -ne 2 -or
            [Math]::Abs([double]$usage.CostEstimateCny - 0.01) -gt 0.0000001) {
            throw "Persistent EYC provider accounting dropped failed-response usage or overstated cost coverage: $($usage | ConvertTo-Json -Compress)."
        }
        $legacyManifest = [pscustomobject]@{ usageMetric = 'AgentHostProgress.jsonl provider-decision events'; cumulativeDecisions = 17 }
        Set-PersistentManifestProperty $legacyManifest 'usageAccountingVersion' 2
        Set-PersistentManifestProperty $legacyManifest 'failureUsageTrackingSinceUtc' 'self-test'
        Set-PersistentManifestProperty $legacyManifest 'lastFailureUsageReconciledRunId' 'synthetic-run'
        if ([int]$legacyManifest.usageAccountingVersion -ne 2 -or
            [string]$legacyManifest.failureUsageTrackingSinceUtc -cne 'self-test' -or
            [string]$legacyManifest.lastFailureUsageReconciledRunId -cne 'synthetic-run' -or
            [int]$legacyManifest.cumulativeDecisions -ne 17) {
            throw 'Persistent EYC manifest migration must add missing tracking fields without overwriting historical decision totals.'
        }
        return [pscustomobject]@{ passed = $true; successfulDecisions = $usage.ProviderDecisions; providerRequests = $usage.ProviderRequests; promptTokens = $usage.PromptTokens; completionTokens = $usage.CompletionTokens; failedResponsePromptTokens = $usage.FailedPromptTokens; failedResponseCompletionTokens = $usage.FailedCompletionTokens; costEstimateComplete = $usage.CostEstimateComplete; legacyManifestMigrationPreservedTotals = $true }
    }
    finally { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
}

function Get-VerifiedCampaignProgressUsage([string]$CampaignInstanceId) {
    $total = [ordered]@{
        ProviderDecisions = 0; ProviderRequests = 0; ProviderFailures = 0; ProviderFailuresWithUsage = 0; ProviderFailuresWithoutUsage = 0
        PromptTokens = [long]0; CompletionTokens = [long]0; FailedPromptTokens = [long]0; FailedCompletionTokens = [long]0
        CostEstimateCny = [double]0; CostEstimateComplete = $true; TokenUsageComplete = $true; UnpricedProviderResponses = 0; UnpricedProviderFailures = 0; ReceiptRunCount = 0
    }
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
        $total.ProviderRequests += [int]$usage.ProviderRequests
        $total.ProviderFailures += [int]$usage.ProviderFailures
        $total.ProviderFailuresWithUsage += [int]$usage.ProviderFailuresWithUsage
        $total.ProviderFailuresWithoutUsage += [int]$usage.ProviderFailuresWithoutUsage
        $total.UnpricedProviderFailures += [int]$usage.UnpricedProviderFailures
        $total.PromptTokens += [long]$usage.PromptTokens
        $total.CompletionTokens += [long]$usage.CompletionTokens
        $total.FailedPromptTokens += [long]$usage.FailedPromptTokens
        $total.FailedCompletionTokens += [long]$usage.FailedCompletionTokens
        $total.CostEstimateCny += [double]$usage.CostEstimateCny
        if (-not $usage.CostEstimateComplete) { $total.CostEstimateComplete = $false }
        if (-not $usage.TokenUsageComplete) { $total.TokenUsageComplete = $false }
        $total.UnpricedProviderResponses += [int]$usage.UnpricedProviderResponses
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

function Get-VerifiedCheckpointProviderFailureUsage([string]$CampaignInstanceId, [string]$SaveName, [string]$SaveHash) {
    $resultsRoot = Join-Path $PSScriptRoot 'TestResults'
    $matches = [Collections.Generic.List[object]]::new()
    foreach ($runDirectory in Get-ChildItem -LiteralPath $resultsRoot -Directory -ErrorAction SilentlyContinue) {
        $tempDirectory = Join-Path $runDirectory.FullName 'Temp'
        $receiptPath = Join-Path $tempDirectory 'PersistentEycCampaignResult.json'
        $progressPath = Join-Path $tempDirectory 'AgentHostProgress.jsonl'
        if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf) -or -not (Test-Path -LiteralPath $progressPath -PathType Leaf)) { continue }
        try { $receipt = Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json }
        catch { continue }
        if (-not [bool]$receipt.CheckpointSaved -or
            [string]$receipt.CampaignInstanceId -cne $CampaignInstanceId -or
            [string]$receipt.CheckpointSaveName -cne $SaveName -or
            [string]$receipt.CheckpointSaveSha256 -cne $SaveHash) { continue }
        $matches.Add([pscustomobject]@{ RunId = $runDirectory.Name; Usage = Get-AgentHostProgressUsage $progressPath })
    }
    if ($matches.Count -gt 1) { throw "Multiple persistent-run receipts claim the current checkpoint '$SaveName'; refusing to reconcile provider usage more than once." }
    if ($matches.Count -eq 1) { return $matches[0] }
    return $null
}

function New-PersistentSeedManifest([object]$Receipt, [string]$SaveName, [string]$SaveHash, [object]$Usage) {
    if ($null -eq $Usage) {
        $Usage = [pscustomobject]@{ ProviderDecisions = 0; ProviderRequests = 0; ProviderFailures = 0; ProviderFailuresWithUsage = 0; ProviderFailuresWithoutUsage = 0; UnpricedProviderFailures = 0; PromptTokens = [long]0; CompletionTokens = [long]0; FailedPromptTokens = [long]0; FailedCompletionTokens = [long]0; CostEstimateCny = [double]0; CostEstimateComplete = $true; TokenUsageComplete = $true; UnpricedProviderResponses = 0; ReceiptRunCount = 0 }
    }
    return [pscustomobject]@{
        schemaVersion = 1
        project = 'ChronicleFramework'
        campaignKey = $CampaignKey
        campaignInstanceId = [string]$Receipt.ChronicleCampaignInstanceId
        saveName = $SaveName
        sha256 = $SaveHash
        previousSaveName = $null
        previousSha256 = $null
        seedRunUtc = [DateTime]::UtcNow.ToString('O')
        lastCheckpointUtc = [DateTime]::UtcNow.ToString('O')
        checkpointCount = 1
        usageMetric = 'AgentHostProgress.jsonl provider decisions plus failed response token usage; price coverage tracked separately'
        usageAccountingVersion = 2
        failureUsageTrackingSinceUtc = [DateTime]::UtcNow.ToString('O')
        lastFailureUsageReconciledSaveName = $SaveName
        usageReceiptRunCount = if ($null -ne $Usage) { [int]$Usage.ReceiptRunCount } else { 0 }
        cumulativeDecisions = [int]$Usage.ProviderDecisions
        cumulativeProviderRequests = [int]$Usage.ProviderRequests
        cumulativeProviderFailures = [int]$Usage.ProviderFailures
        cumulativeProviderFailuresWithUsage = [int]$Usage.ProviderFailuresWithUsage
        cumulativeProviderFailuresWithoutUsage = [int]$Usage.ProviderFailuresWithoutUsage
        cumulativeUnpricedProviderFailures = [int]$Usage.UnpricedProviderFailures
        cumulativePromptTokens = [long]$Usage.PromptTokens
        cumulativeCompletionTokens = [long]$Usage.CompletionTokens
        cumulativeFailedPromptTokens = [long]$Usage.FailedPromptTokens
        cumulativeFailedCompletionTokens = [long]$Usage.FailedCompletionTokens
        cumulativeProviderActualCostEstimateCny = [double]$Usage.CostEstimateCny
        cumulativeUnpricedProviderResponses = [int]$Usage.UnpricedProviderResponses
        cumulativeCostEstimateComplete = [bool]$Usage.CostEstimateComplete
        cumulativeTokenUsageComplete = [bool]$Usage.TokenUsageComplete
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

if ($UsageSelfTest) {
    $usageSelfTestResult = Test-AgentHostProgressUsageAccounting
    $usageSelfTestResult | ConvertTo-Json -Depth 4
    return
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
$liveRunProviderRequests = 0
$liveRunProviderFailures = 0
$liveRunProviderFailuresWithUsage = 0
$liveRunProviderFailuresWithoutUsage = 0
$liveRunFailedPromptTokens = 0L
$liveRunFailedCompletionTokens = 0L
$liveRunUnpricedProviderResponses = 0
$liveRunCostEstimateComplete = $true
$liveRunTokenUsageComplete = $true
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
    $focusPauseContract = Test-HarnessFocusPauseLeaseContract
    $focusPauseLease = Set-HarnessFocusPauseLease

    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([int]$manifest.schemaVersion -ne 1 -or [string]$manifest.project -cne 'ChronicleFramework' -or
            [string]::IsNullOrWhiteSpace([string]$manifest.saveName) -or [string]::IsNullOrWhiteSpace([string]$manifest.sha256) -or
            [string]::IsNullOrWhiteSpace([string]$manifest.campaignInstanceId)) {
            throw 'Persistent EYC manifest is invalid; no save was loaded or overwritten.'
        }
        $manifestCampaignKey = if ($null -ne $manifest.PSObject.Properties['campaignKey']) { [string]$manifest.campaignKey } else { '' }
        if ($manifestCampaignKey -cne $CampaignKey) {
            throw 'Persistent EYC manifest belongs to a different CampaignKey; no save was loaded or overwritten.'
        }
        $sourceSaveName = [string]$manifest.saveName
        $sourcePath = Get-SavePath $sourceSaveName
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf) -or (Get-Sha256 $sourcePath) -cne [string]$manifest.sha256) {
            throw 'Persistent EYC checkpoint hash does not match its manifest; the test will not silently restart from a new campaign.'
        }
        $sourceHash = [string]$manifest.sha256
        $sourceCampaignInstanceId = [string]$manifest.campaignInstanceId
        if ($null -eq $manifest.PSObject.Properties['usageMetric']) {
            $manifest | Add-Member -NotePropertyName usageMetric -NotePropertyValue $null
        }
        if ($null -eq $manifest.PSObject.Properties['usageReceiptRunCount']) {
            $manifest | Add-Member -NotePropertyName usageReceiptRunCount -NotePropertyValue 0
        }
        $usageMetricV2 = 'AgentHostProgress.jsonl provider decisions plus failed response usage; provider cost coverage tracked separately'
        if ([string]$manifest.usageMetric -cne $usageMetricV2) {
            # Older manifests only counted accepted provider decisions. Preserve
            # their cumulative totals as a historical lower bound; do not replace
            # them from whatever subset of TestResults happens to be retained.
            $manifest.usageMetric = $usageMetricV2
            Set-PersistentManifestProperty $manifest 'usageAccountingVersion' 2
            Set-PersistentManifestProperty $manifest 'failureUsageTrackingSinceUtc' ([DateTime]::UtcNow.ToString('O'))
            if ($null -eq $manifest.PSObject.Properties['cumulativeProviderRequests']) { $manifest | Add-Member -NotePropertyName cumulativeProviderRequests -NotePropertyValue ([int]$manifest.cumulativeDecisions) }
            if ($null -eq $manifest.PSObject.Properties['cumulativeProviderFailures']) { $manifest | Add-Member -NotePropertyName cumulativeProviderFailures -NotePropertyValue 0 }
            if ($null -eq $manifest.PSObject.Properties['cumulativeProviderFailuresWithUsage']) { $manifest | Add-Member -NotePropertyName cumulativeProviderFailuresWithUsage -NotePropertyValue 0 }
            if ($null -eq $manifest.PSObject.Properties['cumulativeProviderFailuresWithoutUsage']) { $manifest | Add-Member -NotePropertyName cumulativeProviderFailuresWithoutUsage -NotePropertyValue 0 }
            if ($null -eq $manifest.PSObject.Properties['cumulativeFailedPromptTokens']) { $manifest | Add-Member -NotePropertyName cumulativeFailedPromptTokens -NotePropertyValue ([long]0) }
            if ($null -eq $manifest.PSObject.Properties['cumulativeFailedCompletionTokens']) { $manifest | Add-Member -NotePropertyName cumulativeFailedCompletionTokens -NotePropertyValue ([long]0) }
            if ($null -eq $manifest.PSObject.Properties['cumulativeUnpricedProviderResponses']) { $manifest | Add-Member -NotePropertyName cumulativeUnpricedProviderResponses -NotePropertyValue 0 }
            if ($null -eq $manifest.PSObject.Properties['cumulativeUnpricedProviderFailures']) { $manifest | Add-Member -NotePropertyName cumulativeUnpricedProviderFailures -NotePropertyValue 0 }
            if ($null -eq $manifest.PSObject.Properties['cumulativeCostEstimateComplete']) { $manifest | Add-Member -NotePropertyName cumulativeCostEstimateComplete -NotePropertyValue $false }
            if ($null -eq $manifest.PSObject.Properties['cumulativeTokenUsageComplete']) { $manifest | Add-Member -NotePropertyName cumulativeTokenUsageComplete -NotePropertyValue $false }
            if ($null -eq $manifest.PSObject.Properties['lastFailureUsageReconciledSaveName']) { $manifest | Add-Member -NotePropertyName lastFailureUsageReconciledSaveName -NotePropertyValue $null }
            if ($null -eq $manifest.PSObject.Properties['lastFailureUsageReconciledRunId']) { $manifest | Add-Member -NotePropertyName lastFailureUsageReconciledRunId -NotePropertyValue $null }
            $manifestUpdated = $true
        }

        if ([string]$manifest.lastFailureUsageReconciledSaveName -cne $sourceSaveName) {
            $previousCheckpointUsage = Get-VerifiedCheckpointProviderFailureUsage $sourceCampaignInstanceId $sourceSaveName $sourceHash
            if ($previousCheckpointUsage) {
                $previousFailureUsage = $previousCheckpointUsage.Usage
                $manifest.cumulativeProviderRequests = [int]$manifest.cumulativeProviderRequests + [int]$previousFailureUsage.ProviderFailures
                $manifest.cumulativeProviderFailures = [int]$manifest.cumulativeProviderFailures + [int]$previousFailureUsage.ProviderFailures
                $manifest.cumulativeProviderFailuresWithUsage = [int]$manifest.cumulativeProviderFailuresWithUsage + [int]$previousFailureUsage.ProviderFailuresWithUsage
                $manifest.cumulativeProviderFailuresWithoutUsage = [int]$manifest.cumulativeProviderFailuresWithoutUsage + [int]$previousFailureUsage.ProviderFailuresWithoutUsage
                $manifest.cumulativePromptTokens = [long]$manifest.cumulativePromptTokens + [long]$previousFailureUsage.FailedPromptTokens
                $manifest.cumulativeCompletionTokens = [long]$manifest.cumulativeCompletionTokens + [long]$previousFailureUsage.FailedCompletionTokens
                $manifest.cumulativeFailedPromptTokens = [long]$manifest.cumulativeFailedPromptTokens + [long]$previousFailureUsage.FailedPromptTokens
                $manifest.cumulativeFailedCompletionTokens = [long]$manifest.cumulativeFailedCompletionTokens + [long]$previousFailureUsage.FailedCompletionTokens
                $manifest.cumulativeUnpricedProviderResponses = [int]$manifest.cumulativeUnpricedProviderResponses + [int]$previousFailureUsage.UnpricedProviderFailures
                $manifest.cumulativeUnpricedProviderFailures = [int]$manifest.cumulativeUnpricedProviderFailures + [int]$previousFailureUsage.UnpricedProviderFailures
                if ([int]$previousFailureUsage.UnpricedProviderFailures -gt 0) { $manifest.cumulativeCostEstimateComplete = $false }
                if ([int]$previousFailureUsage.ProviderFailuresWithoutUsage -gt 0) { $manifest.cumulativeTokenUsageComplete = $false }
                $manifest.lastFailureUsageReconciledRunId = [string]$previousCheckpointUsage.RunId
            }
            $manifest.lastFailureUsageReconciledSaveName = $sourceSaveName
            $manifestUpdated = $true
        }
        if ($manifestUpdated) { Write-PersistentManifest $manifest }
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
                [Environment]::SetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_AUTO_START','0','Process')
                [Environment]::SetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_AUTO_STOP_AFTER_MS','86400000','Process')
                [Environment]::SetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_GOAL','自主完成原版主线任务“建立你的家族”。','Process')
                [Environment]::SetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_MODEL',[Environment]::GetEnvironmentVariable('CHRONICLE_LLM_MODEL','Process'),'Process')
                Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue
                $seed = Invoke-JsonChild $freshCampaignScript @('-StoryModeEycSetup','-StoryModeEycPersistentSeed',
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

    if (-not $eycCompleted) {
        $checkpointSaveName = New-PersistentSaveName
        Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue
        $live = Invoke-JsonChild $liveModelScript @('-LoadSaveName',$sourceSaveName,'-CheckpointSaveName',$checkpointSaveName,
            '-EstablishYourClanAutonomyLoop','-AgentHostRuntime','-MaxProviderDecisions',[string]$MaxProviderDecisionsPerContinuation,'-FrameRate',[string]$FrameRate,
            '-MaxHttpRequestsPerDecision',[string]$MaxHttpRequestsPerDecision,
            '-TimeoutSeconds',[string]$StartupTimeoutSeconds,'-HostMaxElapsedSeconds',[string]$HostMaxElapsedSeconds) 'LiveModelLoopResult.json'
        $liveExitCode = $live.ExitCode
        $liveEvidence = $live.Evidence
        $liveTrace = $liveEvidence.Trace
        $liveUsage = Get-AgentHostProgressUsage (Join-Path $env:CHRONICLE_HARNESS_TEMP 'AgentHostProgress.jsonl')
        $liveRunActualCost = [double]$liveUsage.CostEstimateCny
        $liveRunDecisions = [int]$liveUsage.ProviderDecisions
        $liveRunProviderRequests = [int]$liveUsage.ProviderRequests
        $liveRunProviderFailures = [int]$liveUsage.ProviderFailures
        $liveRunProviderFailuresWithUsage = [int]$liveUsage.ProviderFailuresWithUsage
        $liveRunProviderFailuresWithoutUsage = [int]$liveUsage.ProviderFailuresWithoutUsage
        $liveRunFailedPromptTokens = [long]$liveUsage.FailedPromptTokens
        $liveRunFailedCompletionTokens = [long]$liveUsage.FailedCompletionTokens
        $liveRunUnpricedProviderResponses = [int]$liveUsage.UnpricedProviderResponses
        $liveRunCostEstimateComplete = [bool]$liveUsage.CostEstimateComplete
        $liveRunTokenUsageComplete = [bool]$liveUsage.TokenUsageComplete
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

        if ($campaignContinued) {
            if ($checkpointSaved) {
                $oldCurrentName = [string]$manifest.saveName
                $oldCurrentHash = [string]$manifest.sha256
                $manifest.previousSaveName = $oldCurrentName
                $manifest.previousSha256 = $oldCurrentHash
                $manifest.saveName = $checkpointSaveName
                $manifest.sha256 = [string]$liveEvidence.CheckpointSaveHash
                $manifest.lastCheckpointUtc = [DateTime]::UtcNow.ToString('O')
                $manifest.checkpointCount = [int]$manifest.checkpointCount + 1
            }
            $manifest.cumulativeDecisions = [int]$manifest.cumulativeDecisions + $liveRunDecisions
            $manifest.cumulativeProviderRequests = [int]$manifest.cumulativeProviderRequests + $liveRunProviderRequests
            $manifest.cumulativeProviderFailures = [int]$manifest.cumulativeProviderFailures + $liveRunProviderFailures
            $manifest.cumulativeProviderFailuresWithUsage = [int]$manifest.cumulativeProviderFailuresWithUsage + $liveRunProviderFailuresWithUsage
            $manifest.cumulativeProviderFailuresWithoutUsage = [int]$manifest.cumulativeProviderFailuresWithoutUsage + $liveRunProviderFailuresWithoutUsage
            $manifest.cumulativePromptTokens = [long]$manifest.cumulativePromptTokens + $liveRunPromptTokens
            $manifest.cumulativeCompletionTokens = [long]$manifest.cumulativeCompletionTokens + $liveRunCompletionTokens
            $manifest.cumulativeFailedPromptTokens = [long]$manifest.cumulativeFailedPromptTokens + $liveRunFailedPromptTokens
            $manifest.cumulativeFailedCompletionTokens = [long]$manifest.cumulativeFailedCompletionTokens + $liveRunFailedCompletionTokens
            $manifest.cumulativeProviderActualCostEstimateCny = [Math]::Round([double]$manifest.cumulativeProviderActualCostEstimateCny + $liveRunActualCost, 6)
            $manifest.cumulativeUnpricedProviderResponses = [int]$manifest.cumulativeUnpricedProviderResponses + $liveRunUnpricedProviderResponses
            $manifest.cumulativeUnpricedProviderFailures = [int]$manifest.cumulativeUnpricedProviderFailures + $liveUsage.UnpricedProviderFailures
            $manifest.cumulativeCostEstimateComplete = [bool]$manifest.cumulativeCostEstimateComplete -and $liveRunCostEstimateComplete
            $manifest.cumulativeTokenUsageComplete = [bool]$manifest.cumulativeTokenUsageComplete -and $liveRunTokenUsageComplete
            if ($liveRunProviderRequests -gt 0) {
                $manifest.usageReceiptRunCount = [int]$manifest.usageReceiptRunCount + 1
            }
            $manifest.lastFailureUsageReconciledSaveName = if ($checkpointSaved) { $checkpointSaveName } else { $sourceSaveName }
            $manifest.lastFailureUsageReconciledRunId = Split-Path -Leaf (Split-Path -Parent $env:CHRONICLE_HARNESS_TEMP)
            $manifest.lastHostStatus = [string]$liveTrace.status
            $manifest.lastFailureCode = if ($liveTrace.failureCode) { [string]$liveTrace.failureCode } else { $null }
            Write-PersistentManifest $manifest
            $manifestUpdated = $true
            if ($checkpointSaved) { Remove-ObsoleteOwnedSaves @([string]$manifest.saveName,[string]$manifest.previousSaveName) }
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

try { $focusPauseRestoreResult = Restore-HarnessFocusPauseLease $focusPauseLease }
catch {
    $focusPauseRestoreResult = [pscustomobject]@{ changedByHarness = [bool]($focusPauseLease -and $focusPauseLease.changedByHarness); restored = $false; reason = 'restore-exception' }
    if (-not $failure) { $failure = "Harness could not restore Bannerlord StopGameOnFocusLost: $($_.Exception.Message)" }
}
if (-not [bool]$focusPauseRestoreResult.restored -and -not $failure) {
    $failure = "Harness could not safely restore Bannerlord StopGameOnFocusLost ($($focusPauseRestoreResult.reason))."
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
    ProviderRequestsThisRun = $liveRunProviderRequests
    ProviderFailuresThisRun = $liveRunProviderFailures
    ProviderFailuresWithUsageThisRun = $liveRunProviderFailuresWithUsage
    ProviderFailuresWithoutUsageThisRun = $liveRunProviderFailuresWithoutUsage
    FailedPromptTokensThisRun = $liveRunFailedPromptTokens
    FailedCompletionTokensThisRun = $liveRunFailedCompletionTokens
    UnpricedProviderResponsesThisRun = $liveRunUnpricedProviderResponses
    MaxHttpRequestsPerDecision = $MaxHttpRequestsPerDecision
    PromptTokensThisRun = $liveRunPromptTokens
    CompletionTokensThisRun = $liveRunCompletionTokens
    KnownProviderCostEstimateCnyThisRun = $liveRunActualCost
    ActualCostEstimateCnyThisRun = if ($liveRunCostEstimateComplete) { $liveRunActualCost } else { $null }
    CostEstimateCompleteThisRun = $liveRunCostEstimateComplete
    TokenUsageCompleteThisRun = $liveRunTokenUsageComplete
    CostEstimateScope = 'Known response cost estimates only; inspect CostEstimateCompleteThisRun before treating the value as a total.'
    CumulativeDecisions = if ($manifest) { [int]$manifest.cumulativeDecisions } else { $null }
    CumulativeProviderRequests = if ($manifest) { [int]$manifest.cumulativeProviderRequests } else { $null }
    CumulativeProviderFailures = if ($manifest) { [int]$manifest.cumulativeProviderFailures } else { $null }
    CumulativeFailedPromptTokens = if ($manifest) { [long]$manifest.cumulativeFailedPromptTokens } else { $null }
    CumulativeFailedCompletionTokens = if ($manifest) { [long]$manifest.cumulativeFailedCompletionTokens } else { $null }
    CumulativeUnpricedProviderResponses = if ($manifest) { [int]$manifest.cumulativeUnpricedProviderResponses } else { $null }
    CumulativeCostEstimateComplete = if ($manifest) { [bool]$manifest.cumulativeCostEstimateComplete } else { $false }
    CumulativeActualCostEstimateCny = if ($manifest) { [double]$manifest.cumulativeProviderActualCostEstimateCny } else { $null }
    ManifestPath = $manifestPath
    ManifestUpdated = $manifestUpdated
    FocusPauseLeaseContract = $focusPauseContract
    FocusLossPauseIsolation = $focusPauseRestoreResult
    GameProcessesClean = if ($liveEvidence) { [bool]$liveEvidence.ProcessStopped } elseif ($seedEvidence) { [bool]$seedEvidence.BannerlordProcessesCleanAtExit } else { $null }
}
$json = $result | ConvertTo-Json -Depth 6
Set-Content -LiteralPath $resultPath -Value $json -Encoding UTF8
$json
if (-not $result.Passed) { exit 1 }
