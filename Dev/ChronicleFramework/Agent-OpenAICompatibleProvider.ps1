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

    $systemPrompt = @'
You are the decision maker for a Bannerlord Campaign Agent. Use only the task goal, current observation, previous native action receipt, and action catalog in the request. Select at most one listed action with only its listed argument names. Use IDs and values only when present in the current observation or receipt. Never invent unseen people, settlements, options, or game state. Never request or output code, tools, shell commands, or direct game API calls. If the goal is already met or no safe legal action is supported by the current evidence, return a done decision with a concise reason. Return exactly one JSON object and no Markdown.

For an action, return: {"action":"listed action name","arguments":{},"rationale":"brief evidence-based reason"}
To stop, return: {"done":true,"reason":"brief evidence-based reason"}
'@
    $userContent = $request | ConvertTo-Json -Depth 24 -Compress
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
    $body = $payload | ConvertTo-Json -Depth 28 -Compress
    $headers = @{}
    if (-not [string]::IsNullOrWhiteSpace($apiKey)) { $headers.Authorization = "Bearer $apiKey" }

    try {
        $response = Invoke-RestMethod -Method Post -Uri $endpointUri -Headers $headers -Body $body -ContentType 'application/json' -TimeoutSec $timeoutSeconds
    }
    catch {
        $status = $null
        try { $status = [int]$_.Exception.Response.StatusCode } catch { }
        if ($status) { throw "Model provider HTTP request failed with status $status." }
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

    if ($decision.done -eq $true) {
        $reason = [string]$decision.reason
        if ([string]::IsNullOrWhiteSpace($reason)) { throw 'Model stop decision is missing a reason.' }
        [Console]::Out.WriteLine(([ordered]@{ done = $true; reason = $reason } | ConvertTo-Json -Compress))
        exit 0
    }

    $actionName = [string]$decision.action
    if ([string]::IsNullOrWhiteSpace($actionName) -or $null -eq $decision.arguments -or $decision.arguments -isnot [System.Management.Automation.PSCustomObject])
        { throw 'Model action decision must contain a non-empty action and an arguments object.' }
    $allowedAction = @($request.allowedActions | Where-Object { [string]$_.action -ceq $actionName } | Select-Object -First 1)
    if ($allowedAction.Count -ne 1) { throw 'Model selected an action not present in the current decision request catalog.' }
    $allowedArguments = @($allowedAction[0].arguments | ForEach-Object { [string]$_ })
    foreach ($property in $decision.arguments.PSObject.Properties) {
        if ($property.Name -notin $allowedArguments) { throw "Model supplied unsupported argument '$($property.Name)' for action '$actionName'." }
    }
    $rationale = [string]$decision.rationale
    if ([string]::IsNullOrWhiteSpace($rationale)) { throw 'Model action decision is missing its evidence-based rationale.' }
    $normalized = [ordered]@{ action = $actionName; arguments = $decision.arguments; rationale = $rationale }
    [Console]::Out.WriteLine(($normalized | ConvertTo-Json -Depth 16 -Compress))
    exit 0
}
catch {
    Write-ProviderError $_.Exception.Message
}
