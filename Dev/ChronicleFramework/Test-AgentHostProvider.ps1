[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$HostDllPath,
    [Parameter(Mandatory = $true)][string]$EvidencePath,
    [ValidateRange(64,2048)][int]$MaxOutputTokens = 128,
    [switch]$AllowDshXdPoolFreeRoute,
    [switch]$ProbeDshFreeRouteWithMinimalChat,
    [switch]$HealthOnly
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Get-FreeLLMAPIProfile.ps1')
$hostDll = [IO.Path]::GetFullPath($HostDllPath)
$evidencePath = [IO.Path]::GetFullPath($EvidencePath)
if (-not (Test-Path -LiteralPath $hostDll -PathType Leaf)) { throw 'Local Agent Host binary is missing.' }
New-Item -ItemType Directory -Path $evidencePath -Force | Out-Null
$credentialContractRoot = Join-Path ([IO.Path]::GetTempPath()) ('ChronicleProviderCredentialContract-' + [Guid]::NewGuid().ToString('N'))
$previousDshHome = [Environment]::GetEnvironmentVariable('DSH_HOME', 'Process')
$previousProviderKey = [Environment]::GetEnvironmentVariable('CHRONICLE_LLM_API_KEY', 'Process')
try {
    New-Item -ItemType Directory -Path (Join-Path $credentialContractRoot 'openai-gateway') -Force | Out-Null
    [Environment]::SetEnvironmentVariable('DSH_HOME', $credentialContractRoot, 'Process')
    [Environment]::SetEnvironmentVariable('CHRONICLE_LLM_API_KEY', 'paid-provider-key-must-not-be-used-for-dsh', 'Process')
    $gatewayKeyPath = Join-Path $credentialContractRoot 'openai-gateway/api-key'
    [IO.File]::WriteAllText($gatewayKeyPath, 'synthetic-dsh-gateway-key')
    $dshCredential = Get-ChronicleProviderCredential -Endpoint ([Uri]'http://127.0.0.1:8326/v1')
    if ($dshCredential.Value -cne 'synthetic-dsh-gateway-key' -or $dshCredential.Source -ne 'DSH gateway key file') {
        throw 'DSH provider credential selection did not prefer its dedicated local gateway key.'
    }
    Remove-Item -LiteralPath $gatewayKeyPath -Force
    $missingDshCredential = Get-ChronicleProviderCredential -Endpoint ([Uri]'http://127.0.0.1:8326/v1')
    $remoteCredential = Get-ChronicleProviderCredential -Endpoint ([Uri]'https://api.example.invalid/v1')
    if (-not [string]::IsNullOrWhiteSpace([string]$missingDshCredential.Value) -or
        $remoteCredential.Value -cne 'paid-provider-key-must-not-be-used-for-dsh') {
        throw 'Missing DSH gateway credentials must fail closed without borrowing the generic remote provider key.'
    }
}
finally {
    [Environment]::SetEnvironmentVariable('DSH_HOME', $previousDshHome, 'Process')
    [Environment]::SetEnvironmentVariable('CHRONICLE_LLM_API_KEY', $previousProviderKey, 'Process')
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $credentialContractRootFull = [IO.Path]::GetFullPath($credentialContractRoot).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if ($credentialContractRootFull.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $credentialContractRoot) -match '^ChronicleProviderCredentialContract-[0-9a-f]{32}$' -and
        (Test-Path -LiteralPath $credentialContractRoot)) {
        Remove-Item -LiteralPath $credentialContractRoot -Recurse -Force
    }
}
$credentialSelectionContract = [ordered]@{
    DshGatewayUsesDedicatedLocalKey = $true
    DshDoesNotBorrowGenericRemoteKey = $true
    RemoteOpenAiCompatibleUsesGenericKey = $true
    CredentialValuesLogged = $false
}
Set-Content -LiteralPath (Join-Path $evidencePath 'ProviderCredentialContract.json') -Value ($credentialSelectionContract | ConvertTo-Json -Depth 3) -Encoding utf8

foreach ($setting in @(
    'CHRONICLE_LLM_PROTOCOL', 'CHRONICLE_LLM_BASE_URL', 'CHRONICLE_LLM_MODEL',
    'CHRONICLE_LLM_TIMEOUT_SECONDS', 'CHRONICLE_LLM_MAX_TOKENS', 'CHRONICLE_LLM_MAX_TOKEN_PARAMETER',
    'CHRONICLE_LLM_REASONING_EFFORT', 'CHRONICLE_LLM_THINKING_MODE', 'CHRONICLE_LLM_TEMPERATURE', 'CHRONICLE_LLM_OUTPUT_MODE', 'CHRONICLE_LLM_MAX_RUN_COST_CNY'
)) {
    $current = [string][Environment]::GetEnvironmentVariable($setting, 'Process')
    if ([string]::IsNullOrWhiteSpace($current)) {
        $userValue = [Environment]::GetEnvironmentVariable($setting, 'User')
        if (-not [string]::IsNullOrWhiteSpace($userValue)) { [Environment]::SetEnvironmentVariable($setting, $userValue, 'Process') }
    }
}

# Keep this one-shot smoke bounded even when a larger production setting exists.
# The caller may raise this small cap for a structured model that needs more room
# to finish its schema response; it never changes the product run profile.
$env:CHRONICLE_LLM_MAX_TOKENS = [string]$MaxOutputTokens

$protocolSelfTestOutput = & dotnet $hostDll --provider-self-test 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "Provider transport-contract tests failed: $protocolSelfTestOutput" }
$protocolSelfTest = $protocolSelfTestOutput | ConvertFrom-Json
if (-not $protocolSelfTest.passed -or $protocolSelfTest.modelCalls -ne 0 -or $protocolSelfTest.nativeCommands -ne 0) {
    throw 'Provider contract self-test returned an invalid pass summary.'
}

$providerBaseUrl = [string]$env:CHRONICLE_LLM_BASE_URL
$model = [string]$env:CHRONICLE_LLM_MODEL
$providerUri = $null
if (-not [Uri]::TryCreate($providerBaseUrl, [UriKind]::Absolute, [ref]$providerUri) -or [string]::IsNullOrWhiteSpace($model)) {
    throw 'Provider smoke requires a configured absolute base URL and model ID; no inference request was sent.'
}
$protocol = 'openai-compatible'
$freeLlmApiProfile = $null
if ($providerUri.IsLoopback -and $providerUri.Port -eq 31415 -and $providerUri.AbsolutePath.TrimEnd('/') -eq '/v1') {
    . (Join-Path $PSScriptRoot 'Get-FreeLLMAPIProfile.ps1')
    $readinessFixture = @(
        [pscustomobject]@{ id = 'ready-model'; execution_status = 'ready' },
        [pscustomobject]@{ id = 'blocked-model'; execution_status = 'exhausted' },
        [pscustomobject]@{ id = 'missing-key-model'; execution_status = 'needsKey' },
        [pscustomobject]@{ id = 'unknown-model' }
    )
    if (-not (Test-FreeLLMAPIModelExecutionReady -ModelRows $readinessFixture -ModelId 'ready-model') -or
        (Test-FreeLLMAPIModelExecutionReady -ModelRows $readinessFixture -ModelId 'blocked-model') -or
        (Test-FreeLLMAPIModelExecutionReady -ModelRows $readinessFixture -ModelId 'missing-key-model') -or
        (Test-FreeLLMAPIModelExecutionReady -ModelRows $readinessFixture -ModelId 'unknown-model') -or
        (Get-FreeLLMAPIModelExecutionStatus -ModelRows $readinessFixture -ModelId 'absent-model') -ne 'not-listed' -or
        (Get-FreeLLMAPIModelExecutionStatus -ModelRows $readinessFixture -ModelId 'auto:typo-profile') -ne 'not-listed' -or
        (Get-FreeLLMAPIModelExecutionStatus -ModelRows @([pscustomobject]@{ id='auto:noema-free'; execution_status='ready' }) -ModelId 'auto:noema-free') -ne 'router' -or
        (Get-FreeLLMAPIModelExecutionStatus -ModelRows @([pscustomobject]@{ id='free-router'; execution_status='ready' }) -ModelId 'free-router') -ne 'router' -or
        -not (Test-FreeLLMAPIModelExecutionReady -ModelRows @([pscustomobject]@{ id = 'auto:noema-free' }) -ModelId 'auto:noema-free') -or
        -not (Test-FreeLLMAPIModelExecutionReady -ModelRows $readinessFixture -ModelId 'auto:reliable')) {
        throw 'FreeLLMAPI execution-readiness preflight readiness contract failed.'
    }
    $freeLlmApiProfile = Initialize-FreeLLMAPIProfile
    $model = [string]$freeLlmApiProfile.RequestedModelId
    if ($freeLlmApiProfile.ModelExecutionStatus -notin @('ready','router')) { throw 'Configured FreeLLMAPI route is not currently available; no inference request was sent.' }
}
else {
    $isDshXdPoolFreeRoute = $providerUri.IsLoopback -and $providerUri.Port -eq 8326 -and
        $providerUri.AbsolutePath.TrimEnd('/') -eq '/v1' -and
        $model -match '^xdpool-aggregate/(?!combo:)[^\r\n]+:free$' -and
        $model -notmatch '(?i)(fallback|fusion|auto:)'
    if ($isDshXdPoolFreeRoute -and -not $AllowDshXdPoolFreeRoute) {
        throw 'DSH XD Pool inference requires the explicit -AllowDshXdPoolFreeRoute opt-in; no inference request was sent.'
    }
    if ($providerUri.IsLoopback -and -not $isDshXdPoolFreeRoute) {
        throw 'Only a directly named DSH XD Pool :free model may use this loopback smoke path; no inference request was sent.'
    }
    if (-not $providerUri.IsLoopback -and $providerUri.Scheme -ne 'https') { throw 'Remote provider smoke requires HTTPS; no inference request was sent.' }
    $providerCredential = Get-ChronicleProviderCredential -Endpoint $providerUri
    if ([string]::IsNullOrWhiteSpace([string]$providerCredential.Value)) { throw 'Provider API key is missing; no inference request was sent.' }
}

$outputMode = [string]$env:CHRONICLE_LLM_OUTPUT_MODE
if ([string]::IsNullOrWhiteSpace($outputMode)) { $outputMode = 'auto' }
$runCostLimit = [string]$env:CHRONICLE_LLM_MAX_RUN_COST_CNY
if ([string]::IsNullOrWhiteSpace($runCostLimit)) { $runCostLimit = '5' }
$healthRequest = [ordered]@{
    providerConfiguration = [ordered]@{
        ProviderBaseUrl = $providerBaseUrl
        ModelId = $model
        OutputMode = $outputMode
        DeepSeekRunCostLimitCny = $runCostLimit
    }
    providerConfigurationSource = 'agent-host-provider-health'
} | ConvertTo-Json -Depth 5 -Compress
$providerKeyBeforeHealth = [Environment]::GetEnvironmentVariable('CHRONICLE_LLM_API_KEY', 'Process')
try {
    if ($providerCredential) { [Environment]::SetEnvironmentVariable('CHRONICLE_LLM_API_KEY', [string]$providerCredential.Value, 'Process') }
    $healthOutput = $healthRequest | & dotnet $hostDll --provider-health-only 2>&1 | Out-String
    $healthExitCode = $LASTEXITCODE
}
finally { [Environment]::SetEnvironmentVariable('CHRONICLE_LLM_API_KEY', $providerKeyBeforeHealth, 'Process') }
if ($healthExitCode -ne 0) { throw "Read-only Agent Host provider health failed (exit=$healthExitCode). No inference request was sent. $healthOutput" }
try { $hostHealth = $healthOutput | ConvertFrom-Json }
catch { throw 'Agent Host provider health returned invalid JSON; no inference request was sent.' }
if ($hostHealth.status -ne 'ready' -or [int]$hostHealth.modelCalls -ne 0 -or [int]$hostHealth.nativeCommands -ne 0) {
    throw 'Agent Host provider health returned an invalid result; no inference request was sent.'
}

if ($HealthOnly) {
    $summary = [ordered]@{
        Passed = $true
        Check = 'read-only-provider-health'
        ProviderHost = [string]$hostHealth.providerHost
        ConfiguredModelId = [string]$hostHealth.modelId
        StructuredOutputStrategy = [string]$hostHealth.structuredOutputStrategy
        FreeLLMAPIReachable = [bool]$freeLlmApiProfile
        ProviderProxySelectionSource = [string]$hostHealth.proxySelectionSource
        ConfiguredRouteExecutionStatus = if ($freeLlmApiProfile) { $freeLlmApiProfile.ModelExecutionStatus } else { 'catalog-listed' }
        AvailableModelCount = [int]$hostHealth.availableModelCount
        ProviderCredentialContract = $credentialSelectionContract
        ModelCalls = 0
        NativeCommands = 0
        NoModelEndpointOrCredentialLogged = $true
    }
    $summaryJson = $summary | ConvertTo-Json -Depth 6
    Set-Content -LiteralPath (Join-Path $evidencePath 'ProviderHealth.json') -Value $summaryJson -Encoding utf8
    $summaryJson
    return
}

if ($ProbeDshFreeRouteWithMinimalChat) {
    if (-not $AllowDshXdPoolFreeRoute -or -not $isDshXdPoolFreeRoute -or $null -eq $providerCredential) {
        throw 'The minimal DSH chat probe requires an explicitly allowed direct XD Pool :free model and its local gateway credential; no inference request was sent.'
    }
    Add-Type -AssemblyName System.Net.Http
    function Protect-ProviderDiagnosticField([AllowNull()][string]$Value) {
        if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
        $bounded = $Value.Substring(0, [Math]::Min($Value.Length, 96))
        return [regex]::Replace($bounded, '[^A-Za-z0-9_.:/@+\-]', '_')
    }
    function Get-SafeMinimalChatProbeSummary([int]$StatusCode, [AllowNull()][object]$ResponseJson, [AllowNull()][string]$Route) {
        $errorNode = if ($null -ne $ResponseJson -and $null -ne $ResponseJson.PSObject.Properties['error']) { $ResponseJson.error } else { $null }
        $choice = $null
        $choicesProperty = if ($null -ne $ResponseJson) { $ResponseJson.PSObject.Properties['choices'] } else { $null }
        if ($null -ne $choicesProperty -and $null -ne $choicesProperty.Value) {
            $choiceRows = @($choicesProperty.Value)
            if ($choiceRows.Count -gt 0) { $choice = $choiceRows[0] }
        }
        $content = ''
        if ($null -ne $choice -and $null -ne $choice.PSObject.Properties['message']) {
            $messageNode = $choice.message
            if ($null -ne $messageNode -and $null -ne $messageNode.PSObject.Properties['content']) { $content = [string]$messageNode.content }
        }
        $usage = if ($null -ne $ResponseJson -and $null -ne $ResponseJson.PSObject.Properties['usage']) { $ResponseJson.usage } else { $null }
        [ordered]@{
            Passed = ($StatusCode -eq 200 -and $content.Trim() -ceq 'OK')
            ProviderHost = $providerUri.Host
            ModelId = $model
            HttpStatus = $StatusCode
            Route = $Route
            ErrorType = if ($errorNode) { Protect-ProviderDiagnosticField([string]$errorNode.type) } else { $null }
            ErrorCode = if ($errorNode) { Protect-ProviderDiagnosticField([string]$errorNode.code) } else { $null }
            ErrorParam = if ($errorNode) { Protect-ProviderDiagnosticField([string]$errorNode.param) } else { $null }
            RequestId = if ($errorNode) { Protect-ProviderDiagnosticField([string]$errorNode.request_id) } else { $null }
            FinishReason = if ($choice) { Protect-ProviderDiagnosticField([string]$choice.finish_reason) } else { $null }
            PromptTokens = if ($usage) { $usage.prompt_tokens } else { $null }
            CompletionTokens = if ($usage) { $usage.completion_tokens } else { $null }
            ContentMatchedExpected = ($content.Trim() -ceq 'OK')
            ResponseBodyPersisted = $false
            CredentialPersisted = $false
            NativeCommands = 0
        }
    }
    $syntheticError = '{"error":{"type":"invalid_request_error","code":"invalid_request","param":"tools[0].function.parameters","message":"private response text"}}' | ConvertFrom-Json
    $syntheticFailureSummary = Get-SafeMinimalChatProbeSummary -StatusCode 400 -ResponseJson $syntheticError -Route $null
    $syntheticSuccess = '{"choices":[{"message":{"content":"OK"},"finish_reason":"stop"}],"usage":{"prompt_tokens":3,"completion_tokens":1}}' | ConvertFrom-Json
    $syntheticSuccessSummary = Get-SafeMinimalChatProbeSummary -StatusCode 200 -ResponseJson $syntheticSuccess -Route 'direct-free-route'
    if ($syntheticFailureSummary.ErrorCode -ne 'invalid_request' -or $syntheticFailureSummary.ErrorParam -ne 'tools_0_.function.parameters' -or
        $syntheticFailureSummary.ResponseBodyPersisted -or $syntheticSuccessSummary.Passed -ne $true -or
        $syntheticSuccessSummary.PromptTokens -ne 3 -or $syntheticSuccessSummary.CompletionTokens -ne 1) {
        throw 'Minimal free-route diagnostic parsing must handle both error-only and choices responses without storing bodies.'
    }
    $client = [System.Net.Http.HttpClient]::new()
    $requestMessage = [System.Net.Http.HttpRequestMessage]::new(
        [System.Net.Http.HttpMethod]::Post,
        [Uri]::new($providerBaseUrl.TrimEnd('/') + '/chat/completions'))
    try {
        $requestMessage.Headers.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', [string]$providerCredential.Value)
        $minimalRequestJson = [ordered]@{
            model = $model
            messages = @([ordered]@{ role = 'user'; content = 'Reply with exactly OK.' })
            max_tokens = 8
            temperature = 0
            stream = $false
        } | ConvertTo-Json -Depth 4 -Compress
        $requestMessage.Content = [System.Net.Http.StringContent]::new($minimalRequestJson, [Text.Encoding]::UTF8, 'application/json')
        $response = $client.SendAsync($requestMessage).GetAwaiter().GetResult()
        try {
            $responseText = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $responseJson = $null
            try { $responseJson = $responseText | ConvertFrom-Json -ErrorAction Stop } catch { }
            $route = $null
            try { $route = Protect-ProviderDiagnosticField([string]::Join(',', $response.Headers.GetValues('X-Routed-Via'))) } catch { }
            $safeSummary = Get-SafeMinimalChatProbeSummary -StatusCode ([int]$response.StatusCode) -ResponseJson $responseJson -Route $route
            $safeSummaryJson = $safeSummary | ConvertTo-Json -Depth 4
            Set-Content -LiteralPath (Join-Path $evidencePath 'ProviderSimpleChatProbe.json') -Value $safeSummaryJson -Encoding UTF8
            $safeSummaryJson
            if (-not $safeSummary.Passed) {
                $errorType = if ($safeSummary.ErrorType) { $safeSummary.ErrorType } else { 'unknown' }
                $errorCode = if ($safeSummary.ErrorCode) { $safeSummary.ErrorCode } else { 'unknown' }
                $errorParam = if ($safeSummary.ErrorParam) { $safeSummary.ErrorParam } else { 'unknown' }
                throw "Minimal DSH free-route request failed (http=$($safeSummary.HttpStatus); type=$errorType; code=$errorCode; param=$errorParam). Response body omitted; sanitized receipt saved to ProviderSimpleChatProbe.json."
            }
            return
        }
        finally { $response.Dispose() }
    }
    finally {
        $requestMessage.Dispose()
        $client.Dispose()
    }
}

if ($freeLlmApiProfile -and $freeLlmApiProfile.ModelExecutionStatus -eq 'router') {
    throw 'FreeLLMAPI multi-provider router inference is blocked: this Harness has no verified free-only fallback chain and readable quota/cost receipt. Health-only checks remain available; select a directly verifiable model route before inference.'
}

$expectedClassification = if ($freeLlmApiProfile) { 'supported-village-tools-quest' } else { 'supported-map-arrival' }
$decisionGoal = if ($freeLlmApiProfile) { '完成当前可见的村庄工具委托' } else { '前往一个目前可见且安全的定居点' }
$scopeControls = if ($freeLlmApiProfile) { @('supportedMapArrivalGoal','supportedVillageToolsQuestGoal','unsupportedGoal') } else { @('supportedMapArrivalGoal','unsupportedGoal') }
$decisionRequest = [ordered]@{ goal = $decisionGoal; goalScopeClassificationRequired = $true; goalScopeContract = 'native-campaign-goal-classification-v1'; observation = [ordered]@{ scope = 'goal-classification-only'; message = 'No goal-specific game action has run yet. Classify the complete requested outcome against the listed supported goals; only the selected goal executor will become available after this gate.' }; allowedActions = @(); allowedControls = $scopeControls }
$startInfo = [Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = (Get-Command dotnet -ErrorAction Stop).Source
$startInfo.Arguments = '"{0}" --decision-once' -f $hostDll
$startInfo.UseShellExecute = $false
$startInfo.EnvironmentVariables['CHRONICLE_LLM_API_KEY'] = [string]$providerCredential.Value
$startInfo.CreateNoWindow = $true
$startInfo.RedirectStandardInput = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$process = [Diagnostics.Process]::new()
$process.StartInfo = $startInfo
if (-not $process.Start()) { throw 'Could not start the local provider smoke process.' }
$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()
$process.StandardInput.WriteLine(($decisionRequest | ConvertTo-Json -Depth 6 -Compress))
$process.StandardInput.Close()
function Resolve-ProviderSmokeTimeoutSeconds([AllowNull()][string]$ConfiguredValue)
{
    $parsedTimeout = 0
    if ([int]::TryParse($ConfiguredValue, [ref]$parsedTimeout)) { return [Math]::Min(360, [Math]::Max(5, $parsedTimeout)) }
    return 360
}

if ((Resolve-ProviderSmokeTimeoutSeconds $null) -ne 360 -or
    (Resolve-ProviderSmokeTimeoutSeconds '75') -ne 75 -or
    (Resolve-ProviderSmokeTimeoutSeconds '2') -ne 5 -or
    (Resolve-ProviderSmokeTimeoutSeconds '360') -ne 360 -or
    (Resolve-ProviderSmokeTimeoutSeconds '361') -ne 360 -or
    (Resolve-ProviderSmokeTimeoutSeconds 'invalid') -ne 360) {
    throw 'Provider smoke timeout configuration did not preserve its default and bounded values.'
}
$effectiveTimeout = Resolve-ProviderSmokeTimeoutSeconds ([string][Environment]::GetEnvironmentVariable('CHRONICLE_LLM_TIMEOUT_SECONDS','Process'))
if (-not $process.WaitForExit(($effectiveTimeout + 15) * 1000)) {
    try { $process.Kill($true) } catch { }
    throw 'Local provider smoke exceeded the bounded process timeout.'
}
$stdout = $stdoutTask.GetAwaiter().GetResult()
$stderr = $stderrTask.GetAwaiter().GetResult()
if ($process.ExitCode -ne 0) {
    $failurePayload = $null
    try { $failurePayload = $stderr | ConvertFrom-Json -ErrorAction Stop } catch { }
    $providerFailure = if ($failurePayload) { $failurePayload.provider } else { $null }
    $failureSummary = [ordered]@{
        Passed = $false
        ProviderProtocol = $protocol
        ProviderHost = $providerUri.Host
        ConfiguredModelId = $model
        ExitCode = [int]$process.ExitCode
        ErrorCode = if ($failurePayload) { [string]$failurePayload.error } else { $null }
        ProviderHttpStatus = if ($providerFailure) { $providerFailure.httpStatus } else { $null }
        ProviderRoute = if ($providerFailure) { [string]$providerFailure.route } else { $null }
        ProviderOutputFormat = if ($providerFailure) { [string]$providerFailure.outputFormat } else { $null }
        ProviderFailureStage = if ($providerFailure) { [string]$providerFailure.failureStage } else { $null }
        ProviderErrorBodyKind = if ($providerFailure) { [string]$providerFailure.errorBodyKind } else { $null }
        ProviderErrorContentType = if ($providerFailure) { [string]$providerFailure.errorContentType } else { $null }
        ProviderErrorType = if ($providerFailure) { [string]$providerFailure.errorType } else { $null }
        ProviderErrorCode = if ($providerFailure) { [string]$providerFailure.errorCode } else { $null }
        ProviderErrorParam = if ($providerFailure) { [string]$providerFailure.errorParam } else { $null }
        ProviderResponseContentKind = if ($providerFailure) { [string]$providerFailure.responseContentKind } else { $null }
        ProviderResponseContentCharacters = if ($providerFailure) { $providerFailure.responseContentCharacters } else { $null }
        ProviderResponseFinishReason = if ($providerFailure) { [string]$providerFailure.finishReason } else { $null }
        ProviderResponseModel = if ($providerFailure) { [string]$providerFailure.responseModel } else { $null }
        ProviderResponsePromptTokens = if ($providerFailure) { $providerFailure.promptTokens } else { $null }
        ProviderResponseCompletionTokens = if ($providerFailure) { $providerFailure.completionTokens } else { $null }
        ProviderRequestId = if ($providerFailure) { [string]$providerFailure.responseRequestId } else { $null }
        ProviderRetryAfter = if ($providerFailure) { [string]$providerFailure.retryAfter } else { $null }
        ProviderFallbackAttempts = if ($providerFailure) { $providerFailure.fallbackAttempts } else { $null }
        ProviderFallbackTrail = if ($providerFailure) { [string]$providerFailure.fallbackTrail } else { $null }
        ProviderRequestBodyBytes = if ($providerFailure) { $providerFailure.requestBodyBytes } else { $null }
        NativeCommands = 0
        ResponseBodyPersisted = $false
        CredentialPersisted = $false
    }
    $failureSummary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $evidencePath 'ProviderSmokeFailure.json') -Encoding UTF8
    $httpStatus = if ($providerFailure) { $providerFailure.httpStatus } else { 'unknown' }
    $errorType = if ($providerFailure -and $providerFailure.errorType) { $providerFailure.errorType } else { 'unknown' }
    $errorCode = if ($providerFailure -and $providerFailure.errorCode) { $providerFailure.errorCode } else { 'unknown' }
    $errorParam = if ($providerFailure -and $providerFailure.errorParam) { $providerFailure.errorParam } else { 'unknown' }
    $requestId = if ($providerFailure -and $providerFailure.responseRequestId) { $providerFailure.responseRequestId } else { 'unknown' }
    $responseShape = if ($providerFailure -and $providerFailure.responseContentKind) { [string]$providerFailure.responseContentKind } else { 'unknown' }
    $responseFinish = if ($providerFailure -and $providerFailure.finishReason) { [string]$providerFailure.finishReason } else { 'unknown' }
    $responseTokens = if ($providerFailure -and $null -ne $providerFailure.completionTokens) { [string]$providerFailure.completionTokens } else { 'unknown' }
    throw "Configured provider returned an error (exit=$($process.ExitCode); http=$httpStatus; type=$errorType; code=$errorCode; param=$errorParam; shape=$responseShape; finish=$responseFinish; completionTokens=$responseTokens; requestId=$requestId). Response body and credentials are omitted; sanitized receipt saved to ProviderSmokeFailure.json."
}
try { $result = $stdout | ConvertFrom-Json }
catch { throw 'Local provider Host returned invalid structured JSON; raw response is omitted.' }
if ($result.status -ne 'completed' -or $result.decision.goalClassification -cne $expectedClassification -or
    [string]::IsNullOrWhiteSpace([string]$result.decision.reason)) {
    $classificationReason = [string]$result.decision.reason
    if ($classificationReason.Length -gt 160) { $classificationReason = $classificationReason.Substring(0, 160) }
    throw "Configured provider missed the bounded goal-classification smoke (status=$($result.status); goalClassification=$($result.decision.goalClassification); reason=$classificationReason)."
}

$summary = [ordered]@{
    Passed = $true
    ProviderProtocol = $protocol
    ProviderHost = $providerUri.Host
    FreeLLMAPIReachable = [bool]$freeLlmApiProfile
    GatewayStartedByHarness = if ($freeLlmApiProfile) { [bool]$freeLlmApiProfile.GatewayStartedByHarness } else { $false }
    LocalProxyBootstrapApplied = if ($freeLlmApiProfile) { [bool]$freeLlmApiProfile.LocalProxyBootstrapApplied } else { $false }
    ProviderProxySelectionSource = [string]$hostHealth.proxySelectionSource
    ConfiguredModelId = $model
    ConfiguredRouteExecutionStatus = if ($freeLlmApiProfile) { $freeLlmApiProfile.ModelExecutionStatus } else { 'catalog-listed' }
    EffectiveMaxOutputTokens = [int]$env:CHRONICLE_LLM_MAX_TOKENS
    MaxTokenParameter = if ([string]::IsNullOrWhiteSpace([string]$env:CHRONICLE_LLM_MAX_TOKEN_PARAMETER)) { 'max_completion_tokens' } else { [string]$env:CHRONICLE_LLM_MAX_TOKEN_PARAMETER }
    AvailableModelCount = [int]$hostHealth.availableModelCount
    AvailableModelCatalogSha256 = if ($freeLlmApiProfile) { $freeLlmApiProfile.AvailableModelCatalogSha256 } else { $null }
    RoutedVia = [string]$result.routedVia
    ResultStatus = [string]$result.status
    ResponseFormatMode = [string]$result.responseFormatMode
    DecisionType = 'production-goal-scope-classification'
    DecisionClassification = [string]$result.decision.goalClassification
    ReasonWordCount = ([string]$result.decision.reason -split '\s+' | Where-Object { $_ }).Count
    PromptTokens = $result.promptTokens
    CompletionTokens = $result.completionTokens
    PromptCacheHitTokens = $result.promptCacheHitTokens
    PromptCacheMissTokens = $result.promptCacheMissTokens
    EstimatedUsageCostCny = $result.estimatedCostCny
    EstimatedPeakCostCny = if ($providerUri.Host -eq 'api.deepseek.com' -and $null -ne $result.promptTokens -and $null -ne $result.completionTokens) {
        [Math]::Round(([double]$result.promptTokens * 2.4 + [double]$result.completionTokens * 9.6) / 1000000, 8)
    } else { $null }
    ReservedCostUpperBoundCny = $result.reservedCostUpperBoundCny
    DeepSeekRunCostCeilingCny = if ($providerUri.Host -eq 'api.deepseek.com') { [double]$env:CHRONICLE_LLM_MAX_RUN_COST_CNY } else { $null }
    NativeCommands = 0
    RouterCatalog = if ($freeLlmApiProfile) { 'FreeLLMAPI currently available catalog; actual provider captured in RoutedVia' } else { 'Configured OpenAI-compatible provider model catalog' }
    NoModelEndpointOrCredentialLogged = $true
    ProviderContract = [ordered]@{
        Passed = [bool]$protocolSelfTest.passed
        ScenarioCount = @($protocolSelfTest.scenarios).Count
        ModelCalls = [int]$protocolSelfTest.modelCalls
        NativeCommands = [int]$protocolSelfTest.nativeCommands
    }
}
$summaryJson = $summary | ConvertTo-Json -Depth 7
Set-Content -LiteralPath (Join-Path $evidencePath 'ProviderSmoke.json') -Value $summaryJson -Encoding utf8
$summaryJson
