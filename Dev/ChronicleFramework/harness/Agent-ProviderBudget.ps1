#Requires -Version 7.0
function New-AgentProviderBudget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ModelId,
        [Parameter(Mandatory = $true)][string]$BaseUrl,
        [ValidateRange(1,400)][int]$MaxProviderCalls = 20,
        [ValidateRange(1024,65536)][int]$MaxRequestBodyBytes = 10000,
        [ValidateRange(64,512)][int]$MaxOutputTokensPerRequest = 256
    )

    $uri = $null
    if (-not [Uri]::TryCreate($BaseUrl, [UriKind]::Absolute, [ref]$uri)) { throw 'Provider budget could not classify the configured endpoint URI.' }
    $inputTokenFramingReserveTokens = 128
    $maxInputTokensPerRequest = [int]($MaxRequestBodyBytes + $inputTokenFramingReserveTokens)
    $totalInputBytes = [long]$MaxProviderCalls * $MaxRequestBodyBytes
    $totalInputTokens = [long]$MaxProviderCalls * $maxInputTokensPerRequest
    $totalOutputTokens = [long]$MaxProviderCalls * $MaxOutputTokensPerRequest
    if ($uri.Host -ceq 'api.deepseek.com' -and $ModelId -ceq 'deepseek-flash') {
        # Official DeepSeek Flash peak rates (current profile), conservatively
        # converted at 8 CNY/USD; all input is reserved at cache-miss pricing.
        return [ordered]@{
            schemaVersion = 1
            budgetId = 'deepseek-flash-three-run-guard-v1'
            mode = 'priced-provider'
            providerHost = 'api.deepseek.com'
            modelId = $ModelId
            maxProviderCalls = $MaxProviderCalls
            maxRequestBodyBytes = $MaxRequestBodyBytes
            maxTotalRequestBodyBytes = $totalInputBytes
            maxInputTokensPerRequest = $maxInputTokensPerRequest
            maxTotalInputTokens = $totalInputTokens
            maxOutputTokensPerRequest = $MaxOutputTokensPerRequest
            maxTotalOutputTokens = $totalOutputTokens
            currency = 'CNY'
            maxEstimatedCost = 0.65
            priceProfileId = 'deepseek-v4.1-flash-peak-cny-upper-bound-2026-10'
            priceSource = 'https://api-docs.deepseek.com/quick_start/pricing/'
            priceVerifiedOn = '2026-10-10'
            pricePeriod = 'peak-rate upper-bound reservation'
            cnyPerUsdUpperBound = 8.0
            inputCacheMissCnyPerMillion = 2.4
            inputCacheHitCnyPerMillion = 0.048
            inputTokenFramingReserveTokens = $inputTokenFramingReserveTokens
            outputCnyPerMillion = 9.6
        }
    }
    if ($uri.IsLoopback) {
        return [ordered]@{
            schemaVersion = 1
            budgetId = 'local-provider-token-guard-v1'
            mode = 'token-only-local'
            providerHost = $uri.Host
            modelId = $ModelId
            maxProviderCalls = $MaxProviderCalls
            maxRequestBodyBytes = $MaxRequestBodyBytes
            maxTotalRequestBodyBytes = $totalInputBytes
            maxInputTokensPerRequest = $maxInputTokensPerRequest
            maxTotalInputTokens = $totalInputTokens
            maxOutputTokensPerRequest = $MaxOutputTokensPerRequest
            maxTotalOutputTokens = $totalOutputTokens
            currency = $null
            maxEstimatedCost = $null
            priceProfileId = $null
            priceSource = $null
            inputCacheMissCnyPerMillion = $null
            inputCacheHitCnyPerMillion = $null
            inputTokenFramingReserveTokens = $null
            outputCnyPerMillion = $null
        }
    }
    throw "No verified price profile exists for remote endpoint host '$($uri.Host)' and model '$ModelId'; refusing a paid run without an explicit budget profile."
}

function Test-AgentProviderBudget {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Budget)

    if ([int]$Budget.schemaVersion -ne 1 -or [string]::IsNullOrWhiteSpace([string]$Budget.budgetId)) { throw 'Provider budget must have schemaVersion 1 and a non-empty budgetId.' }
    if ([string]$Budget.mode -notin @('priced-provider','token-only-local')) { throw "Provider budget mode '$($Budget.mode)' is unsupported." }
    if ([int]$Budget.maxProviderCalls -lt 1 -or [int]$Budget.maxProviderCalls -gt 400) { throw 'Provider budget maxProviderCalls must be in the range 1-400.' }
    if ([int]$Budget.maxRequestBodyBytes -lt 1024 -or [int]$Budget.maxRequestBodyBytes -gt 65536) { throw 'Provider budget maxRequestBodyBytes must be in the range 1024-65536.' }
    if ([int]$Budget.maxOutputTokensPerRequest -lt 64 -or [int]$Budget.maxOutputTokensPerRequest -gt 4096) { throw 'Provider budget maxOutputTokensPerRequest must be in the range 64-4096.' }
    if ([long]$Budget.maxTotalRequestBodyBytes -lt [long]$Budget.maxRequestBodyBytes -or [long]$Budget.maxTotalOutputTokens -lt [long]$Budget.maxOutputTokensPerRequest) { throw 'Provider budget totals must cover at least one complete request.' }
    if ([int]$Budget.maxInputTokensPerRequest -lt [int]$Budget.maxRequestBodyBytes -or [long]$Budget.maxTotalInputTokens -lt [long]$Budget.maxInputTokensPerRequest) { throw 'Provider budget input-token ceilings must cover at least one complete request.' }
    if ([string]$Budget.mode -eq 'priced-provider') {
        foreach ($field in @('currency','priceProfileId','priceSource','maxEstimatedCost')) {
            if ([string]::IsNullOrWhiteSpace([string]$Budget.$field)) { throw "Priced provider budget is missing '$field'." }
        }
        foreach ($field in @('inputCacheMissCnyPerMillion','inputCacheHitCnyPerMillion','inputTokenFramingReserveTokens','outputCnyPerMillion')) {
            if ($null -eq $Budget.$field -or [double]$Budget.$field -lt 0) { throw "Priced provider budget has an invalid '$field'." }
        }
        if ([string]$Budget.currency -cne 'CNY' -or [double]$Budget.maxEstimatedCost -le 0) { throw 'The initial priced budget implementation supports a positive CNY ceiling only.' }
    }
    return [pscustomobject]@{ Valid = $true; BudgetId = [string]$Budget.budgetId; Mode = [string]$Budget.mode }
}

function Get-AgentProviderBudgetFingerprint {
    param([Parameter(Mandatory = $true)]$Budget)
    $fields = @('schemaVersion','budgetId','mode','providerHost','modelId','maxProviderCalls','maxRequestBodyBytes','maxTotalRequestBodyBytes','maxInputTokensPerRequest','maxTotalInputTokens','maxOutputTokensPerRequest','maxTotalOutputTokens','currency','maxEstimatedCost','priceProfileId','priceSource','priceVerifiedOn','pricePeriod','cnyPerUsdUpperBound','inputCacheMissCnyPerMillion','inputCacheHitCnyPerMillion','inputTokenFramingReserveTokens','outputCnyPerMillion')
    $canonical = [ordered]@{}
    foreach ($field in $fields) { $canonical[$field] = $Budget.$field }
    $json = $canonical | ConvertTo-Json -Depth 8 -Compress
    $hash = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($json)))).Replace('-','').ToLowerInvariant() }
    finally { $hash.Dispose() }
}

function New-AgentProviderBudgetState {
    param([Parameter(Mandatory = $true)]$Budget)
    $null = Test-AgentProviderBudget -Budget $Budget
    return [ordered]@{
        taskId = $null
        budgetId = [string]$Budget.budgetId
        mode = [string]$Budget.mode
        currency = $Budget.currency
        maxEstimatedCost = $Budget.maxEstimatedCost
        maxProviderCalls = [int]$Budget.maxProviderCalls
        reservedProviderCalls = 0
        reservedRequestBodyBytes = 0L
        reservedInputTokenUpperBound = 0L
        reservedOutputTokens = 0L
        reservedCostUpperBound = 0.0
        actualRequestBodyBytes = 0L
        promptTokensReported = 0L
        completionTokensReported = 0L
        cacheHitTokensReported = 0L
        cacheMissTokensReported = 0L
        usageReportedCalls = 0
        usagePartialCalls = 0
        usageUnavailableCalls = 0
        providerRetries = 0
        requestAttemptsUnavailableCalls = 0
        actualEstimatedCostCny = 0.0
        estimatedInputCacheHitCostCny = 0.0
        estimatedInputCacheMissCostCny = 0.0
        estimatedOutputCostCny = 0.0
        pendingProviderCall = $null
    }
}

function Test-AgentProviderBudgetState {
    param([Parameter(Mandatory = $true)]$State, [Parameter(Mandatory = $true)]$Budget)
    if ([string]$State.taskId -and [string]$State.taskId -notmatch '^[a-fA-F0-9]{32}$') { throw 'Persisted provider budget state has an invalid task id.' }
    if ([string]$State.budgetId -cne [string]$Budget.budgetId -or [string]$State.mode -cne [string]$Budget.mode) { throw 'Persisted provider budget state does not match the active budget profile.' }
    foreach ($counter in @('reservedProviderCalls','reservedRequestBodyBytes','reservedInputTokenUpperBound','reservedOutputTokens','usageReportedCalls','usagePartialCalls','usageUnavailableCalls','providerRetries','requestAttemptsUnavailableCalls')) {
        if ($null -eq $State.$counter -or [long]$State.$counter -lt 0) { throw "Persisted provider budget state has an invalid '$counter' counter." }
    }
    if ([int]$State.reservedProviderCalls -gt [int]$Budget.maxProviderCalls -or
        [long]$State.reservedRequestBodyBytes -gt [long]$Budget.maxTotalRequestBodyBytes -or
        [long]$State.reservedInputTokenUpperBound -gt [long]$Budget.maxTotalInputTokens -or
        [long]$State.reservedOutputTokens -gt [long]$Budget.maxTotalOutputTokens -or
        ([string]$Budget.mode -eq 'priced-provider' -and [double]$State.reservedCostUpperBound -gt [double]$Budget.maxEstimatedCost)) {
        throw 'Persisted provider budget state already exceeds its saved profile; refusing to resume.'
    }
    foreach ($counter in @('actualEstimatedCostCny','estimatedInputCacheHitCostCny','estimatedInputCacheMissCostCny','estimatedOutputCostCny','reservedCostUpperBound')) {
        if ($null -eq $State.$counter -or [double]$State.$counter -lt 0) { throw "Persisted provider budget state has an invalid '$counter' amount." }
    }
    return [pscustomobject]@{ Valid = $true; BudgetId = [string]$Budget.budgetId; ReservedProviderCalls = [int]$State.reservedProviderCalls }
}

function Get-AgentProviderBudgetLedgerPath {
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$TaskId)
    if ($TaskId -notmatch '^[a-fA-F0-9]{32}$') { throw 'Provider budget ledger requires a 32-character task GUID.' }
    $rootPath = [IO.Path]::GetFullPath($Root)
    return Join-Path $rootPath ($TaskId.ToLowerInvariant() + '.json')
}

function Read-AgentProviderBudgetLedger {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$TaskId,
        [string]$CampaignInstanceId,
        [Parameter(Mandatory = $true)]$Budget
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $file = Get-Item -LiteralPath $Path
    if ($file.Length -gt 65536) { throw 'Provider budget ledger exceeds the 65,536-byte safety bound.' }
    try { $ledger = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop }
    catch { throw 'Provider budget ledger is corrupt or unreadable; refusing to reset task spending.' }
    $expectedFingerprint = Get-AgentProviderBudgetFingerprint -Budget $Budget
    if ([int]$ledger.schemaVersion -ne 1 -or [string]$ledger.taskId -cne $TaskId -or [string]$ledger.state.taskId -cne $TaskId -or [string]$ledger.budgetFingerprint -cne $expectedFingerprint) { throw 'Provider budget ledger identity/profile mismatch; refusing to reset task spending.' }
    if ($CampaignInstanceId -and [string]$ledger.campaignInstanceId -cne $CampaignInstanceId) { throw 'Provider budget ledger belongs to a different Campaign instance.' }
    if (-not $ledger.state) { throw 'Provider budget ledger has no cumulative state.' }
    $null = Test-AgentProviderBudgetState -State $ledger.state -Budget $Budget
    return $ledger
}

function Merge-AgentProviderBudgetStates {
    param([Parameter(Mandatory = $true)]$CheckpointState, [Parameter(Mandatory = $true)]$LedgerState, [Parameter(Mandatory = $true)]$Budget)
    $merged = [ordered]@{}
    if ($CheckpointState -is [System.Collections.IDictionary]) {
        foreach ($key in $CheckpointState.Keys) { $merged[[string]$key] = $CheckpointState[$key] }
    }
    else {
        foreach ($property in $CheckpointState.PSObject.Properties) { $merged[$property.Name] = $property.Value }
    }
    foreach ($counter in @('reservedProviderCalls','reservedRequestBodyBytes','reservedInputTokenUpperBound','reservedOutputTokens','reservedCostUpperBound','actualRequestBodyBytes','promptTokensReported','completionTokensReported','cacheHitTokensReported','cacheMissTokensReported','usageReportedCalls','usagePartialCalls','usageUnavailableCalls','providerRetries','requestAttemptsUnavailableCalls','actualEstimatedCostCny','estimatedInputCacheHitCostCny','estimatedInputCacheMissCostCny','estimatedOutputCostCny')) {
        if ($null -ne $LedgerState.$counter -and [double]$LedgerState.$counter -gt [double]$merged[$counter]) { $merged[$counter] = $LedgerState.$counter }
    }
    if ($LedgerState.pendingProviderCall) { $merged.pendingProviderCall = $LedgerState.pendingProviderCall }
    $null = Test-AgentProviderBudgetState -State $merged -Budget $Budget
    return $merged
}

function Write-AgentProviderBudgetLedger {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$TaskId,
        [string]$CampaignInstanceId,
        [Parameter(Mandatory = $true)]$Budget,
        [Parameter(Mandatory = $true)]$State
    )
    $null = Test-AgentProviderBudgetState -State $State -Budget $Budget
    if ([string]$State.taskId -cne $TaskId) { throw 'Provider budget ledger state does not match its task id.' }
    $directory = Split-Path -Parent ([IO.Path]::GetFullPath($Path))
    $null = [IO.Directory]::CreateDirectory($directory)
    $ledger = [ordered]@{
        schemaVersion = 1
        taskId = $TaskId
        campaignInstanceId = $CampaignInstanceId
        budgetFingerprint = Get-AgentProviderBudgetFingerprint -Budget $Budget
        state = $State
        updatedUtc = [DateTime]::UtcNow.ToString('O')
    }
    $json = $ledger | ConvertTo-Json -Depth 10 -Compress
    if ($json.Length -gt 60000) { throw 'Provider budget ledger exceeded its 60,000-character limit.' }
    $tempPath = Join-Path $directory (([Guid]::NewGuid().ToString('N')) + '.tmp')
    $backupPath = Join-Path $directory (([Guid]::NewGuid().ToString('N')) + '.bak')
    try {
        [IO.File]::WriteAllText($tempPath, $json, [Text.UTF8Encoding]::new($false))
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            [IO.File]::Replace($tempPath, $Path, $backupPath)
            if (Test-Path -LiteralPath $backupPath -PathType Leaf) { Remove-Item -LiteralPath $backupPath -Force }
        }
        else { [IO.File]::Move($tempPath, $Path) }
    }
    finally {
        if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue }
        if ((Test-Path -LiteralPath $backupPath -PathType Leaf) -and (Test-Path -LiteralPath $Path -PathType Leaf)) { Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue }
    }
}

function Get-AgentProviderRequestCostUpperBound {
    param([Parameter(Mandatory = $true)]$Budget)
    if ([string]$Budget.mode -ne 'priced-provider') { return 0.0 }
    $inputTokenUpper = [double]$Budget.maxRequestBodyBytes + [double]$Budget.inputTokenFramingReserveTokens
    $inputUpper = $inputTokenUpper * [double]$Budget.inputCacheMissCnyPerMillion / 1000000.0
    $outputUpper = [double]$Budget.maxOutputTokensPerRequest * [double]$Budget.outputCnyPerMillion / 1000000.0
    return [Math]::Round(($inputUpper + $outputUpper), 8)
}

function Get-AgentProviderActualCostEstimate {
    param([Parameter(Mandatory = $true)]$Budget, [Parameter(Mandatory = $true)]$Usage)
    $breakdown = Get-AgentProviderActualCostBreakdown -Budget $Budget -Usage $Usage
    if ($null -eq $breakdown) { return $null }
    return [double]$breakdown.totalCny
}

function Get-AgentProviderActualCostBreakdown {
    param([Parameter(Mandatory = $true)]$Budget, [Parameter(Mandatory = $true)]$Usage)
    if ([string]$Budget.mode -ne 'priced-provider' -or [string]$Usage.status -ne 'reported') { return $null }
    $prompt = [double]$Usage.promptTokens
    $hit = if ($null -ne $Usage.promptCacheHitTokens) { [Math]::Min($prompt, [double]$Usage.promptCacheHitTokens) } else { 0.0 }
    $miss = if ($null -ne $Usage.promptCacheMissTokens) { [Math]::Min(($prompt - $hit), [double]$Usage.promptCacheMissTokens) } else { $prompt - $hit }
    if (($hit + $miss) -lt $prompt) { $miss += ($prompt - $hit - $miss) }
    $hitCost = $hit * [double]$Budget.inputCacheHitCnyPerMillion / 1000000.0
    $missCost = $miss * [double]$Budget.inputCacheMissCnyPerMillion / 1000000.0
    $outputCost = [double]$Usage.completionTokens * [double]$Budget.outputCnyPerMillion / 1000000.0
    return [ordered]@{
        inputCacheHitCny = [Math]::Round($hitCost, 8)
        inputCacheMissCny = [Math]::Round($missCost, 8)
        outputCny = [Math]::Round($outputCost, 8)
        totalCny = [Math]::Round(($hitCost + $missCost + $outputCost), 8)
        ratePeriod = [string]$Budget.pricePeriod
    }
}
