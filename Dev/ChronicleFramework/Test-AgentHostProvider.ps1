[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$HostDllPath,
    [Parameter(Mandatory = $true)][string]$EvidencePath,
    [ValidateRange(64,2048)][int]$MaxOutputTokens = 128,
    [switch]$HealthOnly
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Get-FreeLLMAPIProfile.ps1')
$hostDll = [IO.Path]::GetFullPath($HostDllPath)
$evidencePath = [IO.Path]::GetFullPath($EvidencePath)
if (-not (Test-Path -LiteralPath $hostDll -PathType Leaf)) { throw 'Local Agent Host binary is missing.' }
New-Item -ItemType Directory -Path $evidencePath -Force | Out-Null

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
    if ($providerUri.Scheme -ne 'https') { throw 'Remote provider smoke requires HTTPS; no inference request was sent.' }
    $providerCredential = Get-ChronicleProviderCredential -Endpoint $providerUri
    if ([string]::IsNullOrWhiteSpace([string]$providerCredential.Value)) { throw 'Remote provider API key is missing; no inference request was sent.' }
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
$healthOutput = $healthRequest | & dotnet $hostDll --provider-health-only 2>&1 | Out-String
$healthExitCode = $LASTEXITCODE
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
        ModelCalls = 0
        NativeCommands = 0
        NoModelEndpointOrCredentialLogged = $true
    }
    $summaryJson = $summary | ConvertTo-Json -Depth 6
    Set-Content -LiteralPath (Join-Path $evidencePath 'ProviderHealth.json') -Value $summaryJson -Encoding utf8
    $summaryJson
    return
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
if ($process.ExitCode -ne 0) { throw "Configured provider returned an error (exit=$($process.ExitCode)); response text is omitted. $stderr" }
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
