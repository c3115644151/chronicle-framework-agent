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
