[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Write-ProviderError([string]$Message) {
    [Console]::Error.WriteLine($Message)
    exit 1
}

try {
    $requestJson = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($requestJson)) { throw 'Provider request stdin was empty.' }
    $request = $requestJson | ConvertFrom-Json
    if ([int]$request.schemaVersion -ne 2) { throw 'Unsupported decision request schema.' }
    if ([string]::IsNullOrWhiteSpace([string]$request.goal)) { throw 'A non-empty task goal is required for a model decision.' }
    if (@($request.allowedActions).Count -eq 0) { throw 'The validated product action catalog is missing.' }
    if ($null -eq $request.observation -or $null -eq $request.observation.state) { throw 'The current structured game observation is missing.' }

    $endpoint = [string]$env:CHRONICLE_LLM_BASE_URL
    $model = [string]$env:CHRONICLE_LLM_MODEL
    $apiKey = [string]$env:CHRONICLE_LLM_API_KEY
    if ([string]::IsNullOrWhiteSpace($endpoint)) { throw 'CHRONICLE_LLM_BASE_URL is required.' }
    if ([string]::IsNullOrWhiteSpace($model)) { throw 'CHRONICLE_LLM_MODEL is required.' }
    $endpointUri = [Uri]::new($endpoint)
    if (-not $endpointUri.IsAbsoluteUri -or $endpointUri.Scheme -notin @('https','http')) { throw 'CHRONICLE_LLM_BASE_URL must be an absolute HTTP(S) endpoint.' }
    if ($endpointUri.Scheme -eq 'http' -and -not $endpointUri.IsLoopback) { throw 'Plain HTTP is permitted only for a loopback test provider.' }
    $endpointBuilder = [UriBuilder]::new($endpointUri)
    $endpointBuilder.Path = $endpointBuilder.Path.TrimEnd('/') + '/chat/completions'
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
    $temperature = 0.0
    $hasTemperature = -not [string]::IsNullOrWhiteSpace([string]$env:CHRONICLE_LLM_TEMPERATURE)
    if ($hasTemperature -and (-not [double]::TryParse([string]$env:CHRONICLE_LLM_TEMPERATURE, [ref]$temperature) -or $temperature -lt 0 -or $temperature -gt 2))
        { throw 'CHRONICLE_LLM_TEMPERATURE must be a number between 0 and 2.' }

    $systemPrompt = @'
You are the decision maker for a Bannerlord Campaign Agent. Use only the task goal, current observation, previous Native receipt, checkpoint context, and action catalog. Select at most one listed action with only listed arguments. Use only observed IDs/values; never invent game state. Never echo input data. Keep rationale/reason short (at most 20 words); do not output analysis. Ordered goal steps are hard preconditions. A mapSettlementTargetsSummary or recruitOptionsSummary is a bounded receipt subset; choose only included IDs/offers. `campaign-map-travel` and `campaign-settlement-recruitment` are deliberately scoped observations; omitted state is unknown, not evidence. If checkpointContext has a pending Native action, compare it with the fresh observation and do not blindly repeat a non-idempotent action. If checkpointContext.lastRecovery.status is `verified`, its action effect is confirmed by fresh Native state; do not repeat that action, and return done when the one-action goal is thereby met. Action arguments should be an object keyed by listed argument names. A positional array is accepted only when its length exactly matches the listed argument-name sequence; the executor still revalidates every value. Return done only when the goal is met or no safe legal action is supported. Return exactly one JSON object and no Markdown.

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
            allowedActions = $request.allowedActions
            allowedControls = $request.allowedControls
            nativeMoveArrival = $request.nativeMoveArrival
            checkpointContext = $request.checkpointContext
            observation = $request.observation
            previousActionReceipt = $compactReceipt
        }
    }
    $userContent = $modelRequest | ConvertTo-Json -Depth 24 -Compress
    $payload = [ordered]@{
        model = $model
        messages = @(
            [ordered]@{ role = 'system'; content = $systemPrompt }
            [ordered]@{ role = 'user'; content = [string]$userContent }
        )
        response_format = [ordered]@{ type = 'json_object' }
        store = $false
    }
    $payload[$maxTokenParameter] = $maxTokens
    if (-not [string]::IsNullOrWhiteSpace($reasoningEffort)) { $payload.reasoning_effort = $reasoningEffort }
    if ($hasTemperature) { $payload.temperature = $temperature }
    $body = $payload | ConvertTo-Json -Depth 28 -Compress
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $headers = @{}
    if (-not [string]::IsNullOrWhiteSpace($apiKey)) { $headers.Authorization = "Bearer $apiKey" }

    try {
        $response = Invoke-RestMethod -Method Post -Uri $requestUri -Headers $headers -Body $bodyBytes -ContentType 'application/json; charset=utf-8' -TimeoutSec $timeoutSeconds
    }
    catch {
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
        throw "Model provider request failed with $($_.Exception.GetType().Name)."
    }

    $choices = @($response.choices)
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
        [Console]::Out.WriteLine(([ordered]@{ observeAgain = $true; waitSeconds = $waitSeconds; reason = $reason } | ConvertTo-Json -Compress))
        exit 0
    }

    if ($decision.done -eq $true) {
        $reason = [string]$decision.reason
        if ([string]::IsNullOrWhiteSpace($reason)) { throw 'Model stop decision is missing a reason.' }
        [Console]::Out.WriteLine(([ordered]@{ done = $true; reason = $reason } | ConvertTo-Json -Compress))
        exit 0
    }

    $actionName = [string]$decision.action
    if ([string]::IsNullOrWhiteSpace($actionName)) { throw 'Model action decision must contain a non-empty action.' }
    $allowedAction = @($request.allowedActions | Where-Object { [string]$_.action -ceq $actionName } | Select-Object -First 1)
    if ($allowedAction.Count -ne 1) { throw 'Model selected an action not present in the current decision request catalog.' }
    $allowedArguments = @($allowedAction[0].arguments | ForEach-Object { [string]$_ })
    $normalizedArguments = [ordered]@{}
    if ($decision.arguments -is [System.Management.Automation.PSCustomObject]) {
        foreach ($property in $decision.arguments.PSObject.Properties) {
            if ($property.Name -notin $allowedArguments) { throw "Model supplied unsupported argument '$($property.Name)' for action '$actionName'." }
            $normalizedArguments[$property.Name] = $property.Value
        }
    }
    elseif ($null -eq $decision.arguments -or ($decision.arguments -is [Array] -and $decision.arguments.Count -eq 0)) {
        # Some local models copy the empty argument-list shape or omit it. Normalize only for zero-argument actions.
        if ($allowedArguments.Count -gt 0) { throw "Model returned an empty argument list for '$actionName', which requires: $($allowedArguments -join ', ')." }
    }
    elseif ($decision.arguments -is [Array] -and $decision.arguments.Count -gt 0 -and $decision.arguments.Count -eq $allowedArguments.Count) {
        # Some local models return a positional tuple; map it only against the exact ordered parameter list in this request.
        for ($argumentIndex = 0; $argumentIndex -lt $allowedArguments.Count; $argumentIndex++) {
            $normalizedArguments[$allowedArguments[$argumentIndex]] = $decision.arguments[$argumentIndex]
        }
    }
    else {
        throw "Model action decision arguments for '$actionName' must be an object (or an empty list only for a zero-argument action)."
    }
    $rationale = [string]$decision.rationale
    $rationaleSource = 'model'
    if ([string]::IsNullOrWhiteSpace($rationale)) {
        $rationale = "The model omitted its rationale; '$actionName' is still subject to the Native action's live preconditions."
        $rationaleSource = 'provider-fallback'
    }
    $normalized = [ordered]@{ action = $actionName; arguments = $normalizedArguments; rationale = $rationale; rationaleSource = $rationaleSource }
    [Console]::Out.WriteLine(($normalized | ConvertTo-Json -Depth 16 -Compress))
    exit 0
}
catch {
    Write-ProviderError $_.Exception.Message
}
