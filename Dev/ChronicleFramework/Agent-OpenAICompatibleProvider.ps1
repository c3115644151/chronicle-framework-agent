[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$script:LastProviderUsage = $null

function Write-ProviderError([string]$Message) {
    [Console]::Error.WriteLine($Message)
    exit 1
}

function Get-OptionalNonNegativeInt($Source, [string]$Name) {
    if (-not $Source) { return $null }
    $value = $null
    if ($Source -is [System.Collections.IDictionary]) {
        if (-not $Source.Contains($Name)) { return $null }
        $value = $Source[$Name]
    }
    else {
        $property = @($Source.PSObject.Properties | Where-Object { $_.Name -ceq $Name } | Select-Object -First 1)
        if ($property.Count -ne 1) { return $null }
        $value = $property[0].Value
    }
    $parsed = 0
    if (-not [int]::TryParse([string]$value, [ref]$parsed) -or $parsed -lt 0) { return $null }
    return $parsed
}

try {
    $requestJson = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($requestJson)) { throw 'Provider request stdin was empty.' }
    $request = $requestJson | ConvertFrom-Json
    if ([int]$request.schemaVersion -ne 3) { throw 'Unsupported decision request schema.' }
    if ([string]::IsNullOrWhiteSpace([string]$request.goal)) { throw 'A non-empty task goal is required for a model decision.' }
    if ($null -eq $request.recentDecisionHistory -or @($request.recentDecisionHistory).Count -gt 8) { throw 'The bounded recent decision history is missing or exceeds eight entries.' }
    if (@($request.allowedActions).Count -eq 0) { throw 'The validated product action catalog is missing.' }
    if ($null -eq $request.observation -or $null -eq $request.observation.state) { throw 'The current structured game observation is missing.' }

    $endpoint = [string]$env:CHRONICLE_LLM_BASE_URL
    $model = [string]$env:CHRONICLE_LLM_MODEL
    $apiKey = [string]$env:CHRONICLE_LLM_API_KEY
    if ([string]::IsNullOrWhiteSpace($endpoint)) { throw 'CHRONICLE_LLM_BASE_URL is required.' }
    if ([string]::IsNullOrWhiteSpace($model)) { throw 'CHRONICLE_LLM_MODEL is required.' }
    $protocol = if ([string]::IsNullOrWhiteSpace([string]$env:CHRONICLE_LLM_PROTOCOL)) { 'openai-compatible' } else { [string]$env:CHRONICLE_LLM_PROTOCOL }
    if ($protocol -notin @('openai-compatible','ollama-native')) { throw 'CHRONICLE_LLM_PROTOCOL must be openai-compatible or ollama-native.' }
    $endpointUri = [Uri]::new($endpoint)
    if (-not $endpointUri.IsAbsoluteUri -or $endpointUri.Scheme -notin @('https','http')) { throw 'CHRONICLE_LLM_BASE_URL must be an absolute HTTP(S) endpoint.' }
    if ($endpointUri.Scheme -eq 'http' -and -not $endpointUri.IsLoopback) { throw 'Plain HTTP is permitted only for a loopback test provider.' }
    if ($protocol -eq 'ollama-native' -and -not $endpointUri.IsLoopback) { throw 'ollama-native protocol is restricted to a loopback Ollama service.' }
    $endpointBuilder = [UriBuilder]::new($endpointUri)
    if ($protocol -eq 'ollama-native') { $endpointBuilder.Path = '/api/chat' }
    else { $endpointBuilder.Path = $endpointBuilder.Path.TrimEnd('/') + '/chat/completions' }
    $requestUri = $endpointBuilder.Uri

    $timeoutSeconds = 60
    if ($env:CHRONICLE_LLM_TIMEOUT_SECONDS) {
        if (-not [int]::TryParse([string]$env:CHRONICLE_LLM_TIMEOUT_SECONDS, [ref]$timeoutSeconds) -or $timeoutSeconds -lt 5 -or $timeoutSeconds -gt 240)
            { throw 'CHRONICLE_LLM_TIMEOUT_SECONDS must be between 5 and 240.' }
    }
    $maxTokens = 800
    if ($env:CHRONICLE_LLM_MAX_TOKENS) {
        if (-not [int]::TryParse([string]$env:CHRONICLE_LLM_MAX_TOKENS, [ref]$maxTokens) -or $maxTokens -lt 64 -or $maxTokens -gt 4096)
            { throw 'CHRONICLE_LLM_MAX_TOKENS must be between 64 and 4096.' }
    }
    $maxTokenParameter = if ([string]::IsNullOrWhiteSpace([string]$env:CHRONICLE_LLM_MAX_TOKEN_PARAMETER)) { 'max_completion_tokens' } else { [string]$env:CHRONICLE_LLM_MAX_TOKEN_PARAMETER }
    if ($maxTokenParameter -notin @('max_completion_tokens','max_tokens'))
        { throw 'CHRONICLE_LLM_MAX_TOKEN_PARAMETER must be max_completion_tokens or max_tokens.' }
    $reasoningEffort = [string]$env:CHRONICLE_LLM_REASONING_EFFORT
    if (-not [string]::IsNullOrWhiteSpace($reasoningEffort) -and $reasoningEffort -notin @('none','low','medium','high'))
        { throw 'CHRONICLE_LLM_REASONING_EFFORT must be omitted or one of: none, low, medium, high.' }
    $thinkingMode = [string]$env:CHRONICLE_LLM_THINKING_MODE
    if (-not [string]::IsNullOrWhiteSpace($thinkingMode) -and $thinkingMode -notin @('enabled','disabled'))
        { throw 'CHRONICLE_LLM_THINKING_MODE must be omitted or one of: enabled, disabled.' }
    $temperature = 0.0
    $hasTemperature = -not [string]::IsNullOrWhiteSpace([string]$env:CHRONICLE_LLM_TEMPERATURE)
    if ($hasTemperature -and (-not [double]::TryParse([string]$env:CHRONICLE_LLM_TEMPERATURE, [ref]$temperature) -or $temperature -lt 0 -or $temperature -gt 2))
        { throw 'CHRONICLE_LLM_TEMPERATURE must be a number between 0 and 2.' }

    $systemPrompt = @'
You are the decision maker for a Bannerlord Campaign Agent. Use only the task goal, current observation, previous Native receipt, bounded recentDecisionHistory, checkpoint context, decision feedback, and current action/control catalogs. Recent history contains only your previous selected actions and execution outcomes, not game-state truth; the current Native observation and previous receipt remain authoritative. Use history to track completed goal steps and avoid repeating a non-idempotent action when its effect is already present. Select at most one listed action with only listed arguments. The action catalog is recalculated from the latest Native game state; a missing action is not currently available and must not be guessed or requested. Controls are separate from game actions and are also recalculated from the current state; use only controls in `allowedControls`, and do not request an omitted control. If decisionFeedback says an action or control was unavailable or rejected, treat it as authoritative, use the fresh observation and current catalogs, and choose a different legal next step or stop safely; do not repeat the rejected action/control without new evidence. If a Native completion contract is present, its predicates are checked by the execution layer, not by you. A `goal-not-satisfied` or `goal-verification-unknown` feedback means your `done` proposal was not accepted; use its exact Native condition IDs/values, the fresh observation, and current catalogs to continue safely. Never claim completion while the contract is unmet or unknown. Use only observed IDs/values; never invent game state. Never echo input data. Keep rationale/reason short (at most 20 words); do not output analysis. Ordered goal steps are hard preconditions. A mapSettlementTargetsSummary or recruitOptionsSummary is a bounded receipt subset; choose only included IDs/offers. `campaign-map-travel`, `campaign-settlement-recruitment`, and `trade-transaction` are deliberately scoped observations; any field listed in `omittedStateFields` is unknown, not evidence that the value or event is absent. If checkpointContext has a pending Native action, compare it with the fresh observation and do not blindly repeat a non-idempotent action. If checkpointContext.lastRecovery.status is `verified`, its action effect is confirmed by fresh Native state; do not repeat that action, and return done when the one-action goal is thereby met. Action arguments must use only the listed names; for an action with an empty argument list, omit `arguments` or return `{}`. If the provider reports `invalid-action-arguments`, do not repeat the rejected argument names; rebuild the arguments from the current catalog and retry only if a safe, complete action is possible. A positional array is accepted only when its length exactly matches the listed argument-name sequence; the executor still revalidates every value. Return done only when the goal is met or no safe legal action is supported. Return exactly one JSON object and no Markdown.

For `menuSelect`, set `arguments.OptionId` to the exact `id` value of one currently enabled entry in `observation.state.availableMenuOptions`. Do not use the field name `OptionId`, the displayed text, or an option that is absent/disabled. For `provision`, set `arguments.ItemViewModelId` to the exact `viewModelItemId` from the latest successful `foodOptions` receipt and set `arguments.Amount` to an integer amount permitted by that offer; never copy a field name as an ID. `provision` only drafts a TradeVM transaction; while still in Trade InventoryState, use the currently listed `tradeConfirm` to commit it or `tradeCancelChanges` to cancel. Do not wait/observeAgain until a committed receipt and a Native context that permits waiting are observed.

For a finite stay in a settlement, selecting the Native `town_wait` menu option enters the active waiting screen; it does not by itself set the requested number of days. Use the listed `rest` action with the requested `Days` while that wait is active to schedule the bounded Native wait. An accepted `rest` receipt means the wait is still running, not complete. While it runs, use only the listed `observeAgain` control until a fresh Native observation verifies the requested daily-tick/time condition. The Native `wait_leave` menu option means "stop waiting" and exits immediately; do not use it to schedule or continue a finite wait. Select it only after the goal's wait condition is verified or when the goal explicitly requires aborting the wait.

For an action, return: {"action":"listed action name","arguments":{},"rationale":"brief evidence-based reason"}
To stop, return: {"done":true,"reason":"brief evidence-based reason"}
When `nativeMoveArrival.status` is `arrived`, the current Native observation confirms the previous move's target; return done immediately and issue no more game actions. While the previous native move is visibly still in progress and its target has not been reached, you may request bounded re-observation without a game action. Preferred: {"observeAgain":true,"waitSeconds":5,"reason":"brief evidence-based reason"}. Also accepted: {"action":"observeAgain","arguments":{"waitSeconds":5},"rationale":"brief evidence-based reason"}. Use 1-10 seconds only; this is scheduler polling, not a game-time command. Do not request it outside an active visible move. The execution layer revalidates this control independently of the game-action catalog.
'@
    $modelRequest = $request
    $previousReceipt = $request.previousActionReceipt
    if ($previousReceipt) {
        $compactReceipt = [ordered]@{}
        foreach ($property in $previousReceipt.PSObject.Properties) {
            if ($property.Name -cnotin @('state','data')) { $compactReceipt[$property.Name] = $property.Value }
        }
        if ($previousReceipt.data) {
            $compactReceiptData = $previousReceipt.data
            if ([string]$previousReceipt.action -ceq 'mapSettlementTargets') {
                $mapTargets = @($previousReceipt.data.mapSettlementTargets)
                if ($mapTargets.Count -gt 16) {
                    $safeTargets = @($mapTargets | Where-Object { -not [bool]$_.hostile -and -not [bool]$_.underSiege } | Sort-Object { [double]$_.distance } | Select-Object -First 12)
                    $atRiskTargets = @($mapTargets | Where-Object { [bool]$_.hostile -or [bool]$_.underSiege } | Sort-Object { [double]$_.distance } | Select-Object -First 4)
                    $candidateTargets = @($safeTargets + $atRiskTargets)
                    $compactReceiptData = [ordered]@{}
                    foreach ($property in $previousReceipt.data.PSObject.Properties) {
                        if ($property.Name -cne 'mapSettlementTargets') { $compactReceiptData[$property.Name] = $property.Value }
                    }
                    $compactReceiptData.mapSettlementTargets = $candidateTargets
                    $compactReceiptData.mapSettlementTargetsSummary = [ordered]@{
                        totalCount = $mapTargets.Count
                        includedCount = $candidateTargets.Count
                        omittedCount = ($mapTargets.Count - $candidateTargets.Count)
                        selectionPolicy = 'nearest safe candidates plus nearest at-risk candidates'
                    }
                }
            }
            elseif ([string]$previousReceipt.action -ceq 'recruitOptions' -and $previousReceipt.data.offers) {
                $allOffers = @($previousReceipt.data.offers)
                $availableOffers = @($allOffers | Where-Object { [bool]$_.available })
                $compactOffers = @($availableOffers | Select-Object -First 12 | ForEach-Object {
                    [ordered]@{ ownerId = $_.ownerId; ownerName = $_.ownerName; troopId = $_.troopId; troopName = $_.troopName; slot = $_.slot; cost = $_.cost; wage = $_.wage; available = $_.available }
                })
                $compactReceiptData = [ordered]@{
                    settlementId = $previousReceipt.data.settlementId
                    gold = $previousReceipt.data.gold
                    partySize = $previousReceipt.data.partySize
                    partyCapacity = $previousReceipt.data.partyCapacity
                    partySizeWarningForOne = $previousReceipt.data.partySizeWarningForOne
                    offers = $compactOffers
                    recruitOptionsSummary = [ordered]@{ totalCount = $allOffers.Count; availableCount = $availableOffers.Count; includedCount = $compactOffers.Count; omittedCount = [Math]::Max(0, $availableOffers.Count - $compactOffers.Count); selectionPolicy = 'currently available native volunteer offers only' }
                }
            }
            $compactReceipt.data = $compactReceiptData
        }
        if ($previousReceipt.state) {
            $receiptState = $previousReceipt.state
            $compactReceipt.stateSummary = [ordered]@{
                campaignDay = $receiptState.campaignDay
                location = $receiptState.location
                party = $receiptState.party
                context = [ordered]@{
                    gameState = $receiptState.context.gameState
                    menuId = $receiptState.context.menuId
                    timeControlMode = $receiptState.context.timeControlMode
                    encounterActive = $receiptState.context.encounterActive
                }
            }
        }
        $modelRequest = [ordered]@{
            schemaVersion = $request.schemaVersion
            runId = $request.runId
            iteration = $request.iteration
            goal = $request.goal
            recentDecisionHistory = $request.recentDecisionHistory
            allowedActions = $request.allowedActions
            allowedControls = $request.allowedControls
            nativeMoveArrival = $request.nativeMoveArrival
            checkpointContext = $request.checkpointContext
            observation = $request.observation
            previousActionReceipt = $compactReceipt
            decisionFeedback = $request.decisionFeedback
        }
    }
    $state = $request.observation.state
    $tradeOfferCount = @($previousReceipt.data.offers).Count
    if ([string]$state.context.gameState -ceq 'InventoryState' -and [string]$state.inventoryScreen.mode -ceq 'Trade' -and [string]$previousReceipt.action -ceq 'foodOptions' -and [string]$previousReceipt.status -ceq 'completed' -and $tradeOfferCount -gt 0) {
        $retainedStateFields = @('schemaVersion','campaignDay','identity','economy','party','location','context','partyScreen','inventoryScreen','availableMenuOptions')
        $scopedState = [ordered]@{}
        foreach ($field in $retainedStateFields) {
            $property = @($state.PSObject.Properties | Where-Object { $_.Name -ceq $field } | Select-Object -First 1)
            if ($property.Count -eq 1) { $scopedState[$field] = $property[0].Value }
        }
        $omittedStateFields = @($state.PSObject.Properties | Where-Object { $_.Name -cnotin $retainedStateFields } | ForEach-Object { [string]$_.Name } | Sort-Object -Unique)
        $modelRequest.observation = [ordered]@{
            scope = 'trade-transaction'
            omittedStateFields = $omittedStateFields
            state = $scopedState
        }
    }
    $userContent = $modelRequest | ConvertTo-Json -Depth 24 -Compress
    $effectiveMaxTokens = $maxTokens
    $requestBudget = $request.providerBudget
    if ($requestBudget) {
        $budgetOutputLimit = 0
        $budgetBodyLimit = 0
        if (-not [int]::TryParse([string]$requestBudget.maxOutputTokensPerRequest, [ref]$budgetOutputLimit) -or $budgetOutputLimit -lt 1 -or
            -not [int]::TryParse([string]$requestBudget.maxRequestBodyBytes, [ref]$budgetBodyLimit) -or $budgetBodyLimit -lt 1024) {
            throw 'Provider budget request limits are invalid.'
        }
        $effectiveMaxTokens = [Math]::Min($maxTokens, $budgetOutputLimit)
    }
    $messages = @(
        [ordered]@{ role = 'system'; content = $systemPrompt }
        [ordered]@{ role = 'user'; content = [string]$userContent }
    )
    if ($protocol -eq 'ollama-native') {
        $ollamaOptions = [ordered]@{ num_predict = $effectiveMaxTokens }
        if ($hasTemperature) { $ollamaOptions.temperature = $temperature }
        $payload = [ordered]@{ model = $model; messages = $messages; stream = $false; format = 'json'; options = $ollamaOptions }
        if (-not [string]::IsNullOrWhiteSpace($thinkingMode)) { $payload.think = ($thinkingMode -ceq 'enabled') }
    }
    else {
        $payload = [ordered]@{ model = $model; messages = $messages; response_format = [ordered]@{ type = 'json_object' }; store = $false }
        $payload[$maxTokenParameter] = $effectiveMaxTokens
        if (-not [string]::IsNullOrWhiteSpace($thinkingMode)) { $payload.thinking = [ordered]@{ type = $thinkingMode } }
        if (-not [string]::IsNullOrWhiteSpace($reasoningEffort) -and $thinkingMode -cne 'disabled') { $payload.reasoning_effort = $reasoningEffort }
        if ($hasTemperature) { $payload.temperature = $temperature }
    }
    $body = $payload | ConvertTo-Json -Depth 28 -Compress
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    if ($requestBudget -and $bodyBytes.Length -gt $budgetBodyLimit) {
        $preflightUsage = [ordered]@{
            status = 'unavailable'
            modelId = $model
            responseId = $null
            finishReason = $null
            requestAttempts = 0
            requestBodyBytes = [int]$bodyBytes.Length
            systemPromptBytes = [int][System.Text.Encoding]::UTF8.GetByteCount($systemPrompt)
            userPayloadBytes = [int][System.Text.Encoding]::UTF8.GetByteCount($userContent)
            promptTokens = $null
            completionTokens = $null
            totalTokens = $null
            promptCacheHitTokens = $null
            promptCacheMissTokens = $null
            reasoningTokens = $null
            httpRequestSent = $false
            maxOutputTokens = $effectiveMaxTokens
        }
        [Console]::Out.WriteLine(([ordered]@{ providerBudgetRejected = $true; reason = 'request-body-bytes'; noHttpRequestSent = $true; providerUsage = $preflightUsage } | ConvertTo-Json -Compress))
        exit 0
    }
    $headers = @{}
    if (-not [string]::IsNullOrWhiteSpace($apiKey)) { $headers.Authorization = "Bearer $apiKey" }

    $response = $null
    $maxAttempts = if ($requestBudget -and $requestBudget.mode -eq 'priced-provider') { 1 } else { 2 }
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        try {
            $response = Invoke-RestMethod -Method Post -Uri $requestUri -Headers $headers -Body $bodyBytes -ContentType 'application/json; charset=utf-8' -TimeoutSec $timeoutSeconds
            break
        }
        catch {
        $webStatus = if ($_.Exception -is [System.Net.WebException]) { $_.Exception.Status } else { $null }
        $preResponseConnectionFailure = ($webStatus -in @([System.Net.WebExceptionStatus]::ConnectFailure,[System.Net.WebExceptionStatus]::NameResolutionFailure,[System.Net.WebExceptionStatus]::ProxyNameResolutionFailure))
        if ($attempt -lt $maxAttempts -and $preResponseConnectionFailure) {
            Start-Sleep -Milliseconds 400
            continue
        }
        $status = $null
        try { $status = [int]$_.Exception.Response.StatusCode } catch { }
        if ($status) {
            $safeDetail = $null
            if ($endpointUri.IsLoopback) {
                try {
                    $safeDetail = [string]$_.ErrorDetails.Message
                    $errorStream = $_.Exception.Response.GetResponseStream()
                    if ([string]::IsNullOrWhiteSpace($safeDetail) -and $errorStream) {
                        $errorReader = New-Object System.IO.StreamReader($errorStream)
                        $safeDetail = $errorReader.ReadToEnd().Trim()
                        $errorReader.Dispose()
                    }
                    if (-not [string]::IsNullOrWhiteSpace($apiKey)) { $safeDetail = $safeDetail.Replace($apiKey, '[redacted]') }
                    if ($safeDetail.Length -gt 240) { $safeDetail = $safeDetail.Substring(0,240) }
                }
                catch { $safeDetail = $null }
            }
            if ($safeDetail) { throw "Model provider HTTP request failed with status $status on loopback endpoint: $safeDetail" }
            throw "Model provider HTTP request failed with status $status."
        }
        if ($_.Exception -is [System.Net.WebException] -and $_.Exception.Status -eq [System.Net.WebExceptionStatus]::Timeout)
            { throw "Model provider request timed out after $timeoutSeconds seconds." }
        if ($_.Exception -is [System.Net.WebException]) {
            $innerType = if ($_.Exception.InnerException) { $_.Exception.InnerException.GetType().Name } else { 'none' }
            throw "Model provider request failed with WebException (status=$($_.Exception.Status); host=$($endpointUri.Host); attempt=$attempt/$maxAttempts; inner=$innerType)."
        }
        throw "Model provider request failed with $($_.Exception.GetType().Name) (attempt=$attempt/$maxAttempts; host=$($endpointUri.Host))."
        }
    }

    if ($protocol -eq 'ollama-native') {
        $ollamaResponse = $response
        $ollamaPromptTokens = Get-OptionalNonNegativeInt $ollamaResponse 'prompt_eval_count'
        $ollamaCompletionTokens = Get-OptionalNonNegativeInt $ollamaResponse 'eval_count'
        $ollamaTotalTokens = if ($null -ne $ollamaPromptTokens -and $null -ne $ollamaCompletionTokens) { [int]$ollamaPromptTokens + [int]$ollamaCompletionTokens } else { $null }
        $ollamaFinishReason = if ([string]$ollamaResponse.done_reason -in @('length','max_tokens') -or $ollamaResponse.done -eq $false) { 'length' } else { 'stop' }
        $response = [ordered]@{
            id = $null
            model = [string]$ollamaResponse.model
            choices = @([ordered]@{ index = 0; message = [ordered]@{ role = [string]$ollamaResponse.message.role; content = [string]$ollamaResponse.message.content; refusal = $null }; finish_reason = $ollamaFinishReason })
            usage = [ordered]@{ prompt_tokens = $ollamaPromptTokens; completion_tokens = $ollamaCompletionTokens; total_tokens = $ollamaTotalTokens }
        }
    }
    $script:LastProviderUsage = $null
    $choices = @($response.choices)
    $usage = $response.usage
    $promptTokens = Get-OptionalNonNegativeInt $usage 'prompt_tokens'
    $completionTokens = Get-OptionalNonNegativeInt $usage 'completion_tokens'
    $totalTokens = Get-OptionalNonNegativeInt $usage 'total_tokens'
    $promptDetails = if ($usage -and $usage.prompt_tokens_details) { $usage.prompt_tokens_details } else { $null }
    $completionDetails = if ($usage -and $usage.completion_tokens_details) { $usage.completion_tokens_details } else { $null }
    $cacheHitTokens = Get-OptionalNonNegativeInt $promptDetails 'prompt_cache_hit_tokens'
    if ($null -eq $cacheHitTokens) { $cacheHitTokens = Get-OptionalNonNegativeInt $promptDetails 'cached_tokens' }
    $cacheMissTokens = Get-OptionalNonNegativeInt $promptDetails 'prompt_cache_miss_tokens'
    $reasoningTokens = Get-OptionalNonNegativeInt $completionDetails 'reasoning_tokens'
    $usageFieldsComplete = ($null -ne $promptTokens -and $null -ne $completionTokens -and $null -ne $totalTokens)
    $usageTotalsConsistent = if ($usageFieldsComplete) { [long]$totalTokens -eq ([long]$promptTokens + [long]$completionTokens) } else { $null }
    $usageStatus = if ($usageFieldsComplete -and $usageTotalsConsistent) { 'reported' } elseif ($null -ne $promptTokens -or $null -ne $completionTokens -or $null -ne $totalTokens) { 'partial' } else { 'unavailable' }
    $providerUsage = [ordered]@{
        status = $usageStatus
        modelId = if (-not [string]::IsNullOrWhiteSpace([string]$response.model)) { [string]$response.model } else { $model }
        protocol = $protocol
        responseId = [string]$response.id
        finishReason = if ($choices.Count -eq 1) { [string]$choices[0].finish_reason } else { $null }
        requestAttempts = [int]$attempt
        requestBodyBytes = [int]$bodyBytes.Length
        systemPromptBytes = [int][System.Text.Encoding]::UTF8.GetByteCount($systemPrompt)
        userPayloadBytes = [int][System.Text.Encoding]::UTF8.GetByteCount($userContent)
        promptTokens = $promptTokens
        completionTokens = $completionTokens
        totalTokens = $totalTokens
        totalTokensConsistent = $usageTotalsConsistent
        promptCacheHitTokens = $cacheHitTokens
        promptCacheMissTokens = $cacheMissTokens
        reasoningTokens = $reasoningTokens
        httpRequestSent = $true
        maxOutputTokens = $effectiveMaxTokens
    }
    $script:LastProviderUsage = $providerUsage
    if ($choices.Count -ne 1 -or $null -eq $choices[0].message) { throw 'Model provider returned no single Chat Completion choice.' }
    if (-not [string]::IsNullOrWhiteSpace([string]$choices[0].message.refusal)) { throw 'Model provider refused the decision request.' }
    if ($choices[0].finish_reason -eq 'length') { throw 'Model provider response was truncated by its output-token limit.' }
    $content = [string]$choices[0].message.content
    if ([string]::IsNullOrWhiteSpace($content)) { throw 'Model provider returned empty decision content.' }
    $decision = $content | ConvertFrom-Json

    if ($decision.observeAgain -eq $true -or [string]$decision.action -ceq 'observeAgain') {
        $waitSeconds = 0
        $waitValue = if ($decision.observeAgain -eq $true) { [string]$decision.waitSeconds } else { [string]$decision.arguments.waitSeconds }
        if (($decision.observeAgain -eq $true -and $decision.PSObject.Properties.Name -contains 'action') -or
            ($decision.observeAgain -ne $true -and $decision.PSObject.Properties.Name -contains 'done') -or
            -not [int]::TryParse($waitValue, [ref]$waitSeconds) -or $waitSeconds -lt 1 -or $waitSeconds -gt 10)
            { throw 'Model observeAgain decision must request only a waitSeconds value between 1 and 10.' }
        $reason = if ($decision.observeAgain -eq $true) { [string]$decision.reason } else { [string]$decision.rationale }
        if ([string]::IsNullOrWhiteSpace($reason)) { throw 'Model observeAgain decision is missing a reason.' }
        [Console]::Out.WriteLine(([ordered]@{ observeAgain = $true; waitSeconds = $waitSeconds; reason = $reason; providerUsage = $providerUsage } | ConvertTo-Json -Compress))
        exit 0
    }

    if ($decision.done -eq $true) {
        $reason = [string]$decision.reason
        if ([string]::IsNullOrWhiteSpace($reason)) { throw 'Model stop decision is missing a reason.' }
        [Console]::Out.WriteLine(([ordered]@{ done = $true; reason = $reason; providerUsage = $providerUsage } | ConvertTo-Json -Compress))
        exit 0
    }

    $actionName = [string]$decision.action
    if ([string]::IsNullOrWhiteSpace($actionName)) { throw 'Model action decision must contain a non-empty action.' }
    $allowedAction = @($request.allowedActions | Where-Object { [string]$_.action -ceq $actionName } | Select-Object -First 1)
    if ($allowedAction.Count -ne 1) {
        $currentCatalog = @($request.allowedActions | ForEach-Object { [string]$_.action } | Sort-Object -Unique)
        [Console]::Out.WriteLine(([ordered]@{ decisionRejected = $true; requestedAction = $actionName; reason = 'not-in-current-action-catalog'; availableActions = $currentCatalog; providerUsage = $providerUsage } | ConvertTo-Json -Compress))
        exit 0
    }
    $allowedArguments = @($allowedAction[0].arguments | ForEach-Object { [string]$_ })
    $normalizedArguments = [ordered]@{}
    $unsupportedArguments = @()
    $argumentObject = $decision.arguments
    for ($argumentShapeDepth = 0; $argumentShapeDepth -lt 4; $argumentShapeDepth++) {
        if ($argumentObject -is [string]) {
            try { $argumentObject = [string]$argumentObject | ConvertFrom-Json -ErrorAction Stop }
            catch {
                if ($allowedArguments.Count -eq 1) { break }
                throw "Model returned string-encoded arguments for '$actionName' that are not valid JSON."
            }
            continue
        }
        if ($argumentObject -is [Array] -and $argumentObject.Count -eq 1 -and ($argumentObject[0] -is [string] -or $argumentObject[0] -is [Array] -or $argumentObject[0] -is [System.Management.Automation.PSCustomObject] -or $argumentObject[0] -is [System.Collections.IDictionary])) {
            $argumentObject = $argumentObject[0]
            continue
        }
        break
    }
    if ($argumentObject -is [System.Management.Automation.PSCustomObject]) {
        foreach ($property in $argumentObject.PSObject.Properties) {
            if ($property.Name -notin $allowedArguments) { $unsupportedArguments += [string]$property.Name; continue }
            $normalizedArguments[$property.Name] = $property.Value
        }
    }
    elseif ($argumentObject -is [System.Collections.IDictionary]) {
        foreach ($key in $argumentObject.Keys) {
            if ([string]$key -notin $allowedArguments) { $unsupportedArguments += [string]$key; continue }
            $normalizedArguments[[string]$key] = $argumentObject[$key]
        }
    }
    elseif ($null -eq $argumentObject -or ($argumentObject -is [Array] -and $argumentObject.Count -eq 0)) {
        # Some local models copy the empty argument-list shape or omit it. Normalize only for zero-argument actions.
        if ($allowedArguments.Count -gt 0) { throw "Model returned an empty argument list for '$actionName', which requires: $($allowedArguments -join ', ')." }
    }
    elseif ($argumentObject -is [Array] -and $argumentObject.Count -gt 0 -and $argumentObject.Count -eq $allowedArguments.Count) {
        # Some local models return a positional tuple; map it only against the exact ordered parameter list in this request.
        for ($argumentIndex = 0; $argumentIndex -lt $allowedArguments.Count; $argumentIndex++) {
            $normalizedArguments[$allowedArguments[$argumentIndex]] = $argumentObject[$argumentIndex]
        }
    }
    elseif ($allowedArguments.Count -eq 1 -and $null -ne $argumentObject -and $argumentObject -isnot [System.Management.Automation.PSCustomObject] -and $argumentObject -isnot [System.Collections.IDictionary] -and $argumentObject -isnot [Array]) {
        # Some local models collapse a one-field object to its scalar value. Bind it only when the current action schema has exactly one field.
        $normalizedArguments[$allowedArguments[0]] = $argumentObject
    }
    else {
        $argumentShape = if ($null -eq $argumentObject) { 'null' } else { $argumentObject.GetType().FullName }
        if ($argumentObject -is [Array]) { $argumentShape += "[count=$($argumentObject.Count)]" }
        throw "Model action decision arguments for '$actionName' must be an object (or an empty list only for a zero-argument action); received $argumentShape."
    }
    if ($unsupportedArguments.Count -gt 0) {
        $currentCatalog = @($request.allowedActions | ForEach-Object { [string]$_.action } | Sort-Object -Unique)
        [Console]::Out.WriteLine(([ordered]@{
            decisionRejected = $true
            requestedAction = $actionName
            reason = 'invalid-action-arguments'
            invalidArguments = @($unsupportedArguments | Sort-Object -Unique)
            allowedArguments = $allowedArguments
            availableActions = $currentCatalog
            noNativeActionSent = $true
            providerUsage = $providerUsage
        } | ConvertTo-Json -Compress))
        exit 0
    }
    $rationale = [string]$decision.rationale
    $rationaleSource = 'model'
    if ([string]::IsNullOrWhiteSpace($rationale)) {
        $rationale = "The model omitted its rationale; '$actionName' is still subject to the Native action's live preconditions."
        $rationaleSource = 'provider-fallback'
    }
    $normalized = [ordered]@{ action = $actionName; arguments = $normalizedArguments; rationale = $rationale; rationaleSource = $rationaleSource; providerUsage = $providerUsage }
    [Console]::Out.WriteLine(($normalized | ConvertTo-Json -Depth 16 -Compress))
    exit 0
}
catch {
    if ($script:LastProviderUsage) {
        [Console]::Error.WriteLine('Model response could not be normalized; token-usage metadata was retained without storing response content.')
        [Console]::Out.WriteLine(([ordered]@{ providerFailed = $true; failureKind = 'response-unusable'; providerUsage = $script:LastProviderUsage } | ConvertTo-Json -Compress))
        exit 0
    }
    Write-ProviderError $_.Exception.Message
}
