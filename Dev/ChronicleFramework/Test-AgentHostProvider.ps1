[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$HostDllPath,
    [Parameter(Mandatory = $true)][string]$EvidencePath
)

$ErrorActionPreference = 'Stop'
$hostDll = [IO.Path]::GetFullPath($HostDllPath)
$evidencePath = [IO.Path]::GetFullPath($EvidencePath)
if (-not (Test-Path -LiteralPath $hostDll -PathType Leaf)) { throw 'Local Agent Host binary is missing.' }
New-Item -ItemType Directory -Path $evidencePath -Force | Out-Null

foreach ($setting in @(
    'CHRONICLE_LLM_PROTOCOL', 'CHRONICLE_LLM_BASE_URL', 'CHRONICLE_LLM_MODEL', 'CHRONICLE_LLM_API_KEY',
    'CHRONICLE_LLM_TIMEOUT_SECONDS', 'CHRONICLE_LLM_MAX_TOKENS', 'CHRONICLE_LLM_MAX_TOKEN_PARAMETER',
    'CHRONICLE_LLM_REASONING_EFFORT', 'CHRONICLE_LLM_THINKING_MODE', 'CHRONICLE_LLM_TEMPERATURE'
)) {
    $current = [string][Environment]::GetEnvironmentVariable($setting, 'Process')
    if ([string]::IsNullOrWhiteSpace($current)) {
        $userValue = [Environment]::GetEnvironmentVariable($setting, 'User')
        if (-not [string]::IsNullOrWhiteSpace($userValue)) { [Environment]::SetEnvironmentVariable($setting, $userValue, 'Process') }
    }
}

$protocolSelfTestOutput = & dotnet $hostDll --provider-self-test 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "Provider transport-contract tests failed: $protocolSelfTestOutput" }
$protocolSelfTest = $protocolSelfTestOutput | ConvertFrom-Json
if (-not $protocolSelfTest.passed -or $protocolSelfTest.modelCalls -ne 0 -or $protocolSelfTest.nativeCommands -ne 0) {
    throw 'Provider contract self-test returned an invalid pass summary.'
}

$baseUrl = [string][Environment]::GetEnvironmentVariable('CHRONICLE_LLM_BASE_URL', 'Process')
$model = [string][Environment]::GetEnvironmentVariable('CHRONICLE_LLM_MODEL', 'Process')
$protocol = [string][Environment]::GetEnvironmentVariable('CHRONICLE_LLM_PROTOCOL', 'Process')
if ([string]::IsNullOrWhiteSpace($protocol)) { $protocol = 'openai-compatible' }
$endpoint = $null
if ([string]::IsNullOrWhiteSpace($baseUrl) -or [string]::IsNullOrWhiteSpace($model) -or
    -not [Uri]::TryCreate($baseUrl, [UriKind]::Absolute, [ref]$endpoint) -or -not $endpoint.IsLoopback) {
    throw 'Local provider smoke requires configured model settings and a loopback endpoint; values are not printed.'
}

$tagsBuilder = [UriBuilder]::new($endpoint)
$tagsBuilder.Path = '/api/tags'
try { $tags = Invoke-RestMethod -Method Get -Uri $tagsBuilder.Uri -TimeoutSec 5 }
catch { throw "Configured local model service could not be reached (failureType=$($_.Exception.GetType().Name)); endpoint details are omitted." }
if ($protocol -in @('openai-compatible','')) {
    if ([string]$endpoint.AbsolutePath -notmatch '/v1/?$') { throw 'OpenAI-compatible local provider base must resolve to its /v1 API root.' }
}
if ($protocol -eq 'ollama-native' -and -not $endpoint.IsLoopback) { throw 'Native Ollama requests are restricted to loopback.' }
$availableModels = @($tags.models | ForEach-Object { [string]$_.name })
if ($model -notin $availableModels) { throw 'Configured local model is not present in the reachable Ollama service; its name is not printed.' }

$decisionRequest = [ordered]@{
    goal = 'This is a provider smoke test only. The exact allowed decision is to stop and report that structured output is working.'
    observation = [ordered]@{ scope = 'provider-smoke'; state = [ordered]@{ gameState = 'MapState'; worldMutationAllowed = $false } }
    allowedActions = @()
    allowedControls = @('done')
}
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
$effectiveTimeout = 180
if ([int]::TryParse([string][Environment]::GetEnvironmentVariable('CHRONICLE_LLM_TIMEOUT_SECONDS','Process'), [ref]$effectiveTimeout)) { $effectiveTimeout = [Math]::Min(240, [Math]::Max(5, $effectiveTimeout)) }
if (-not $process.WaitForExit(($effectiveTimeout + 15) * 1000)) {
    try { $process.Kill($true) } catch { }
    throw 'Local provider smoke exceeded the bounded process timeout.'
}
$stdout = $stdoutTask.GetAwaiter().GetResult()
$stderr = $stderrTask.GetAwaiter().GetResult()
if ($process.ExitCode -ne 0) { throw "Local provider returned an error (exit=$($process.ExitCode)); response text is omitted. $stderr" }
try { $result = $stdout | ConvertFrom-Json }
catch { throw 'Local provider Host returned invalid structured JSON; raw response is omitted.' }
if ($result.status -ne 'completed' -or $result.decision.done -ne $true -or
    [string]::IsNullOrWhiteSpace([string]$result.decision.reason)) {
    throw 'Local model did not return the expected bounded stop decision.'
}

$summary = [ordered]@{
    Passed = $true
    ProviderProtocol = $protocol
    LocalServiceReachable = $true
    ConfiguredModelInstalled = $true
    ResultStatus = [string]$result.status
    DecisionType = 'done'
    ReasonWordCount = ([string]$result.decision.reason -split '\s+' | Where-Object { $_ }).Count
    PromptTokens = $result.promptTokens
    CompletionTokens = $result.completionTokens
    NativeCommands = 0
    LocalCallCost = 0
    NoModelEndpointOrCredentialLogged = $true
    ProviderContract = $protocolSelfTest
}
$summary | ConvertTo-Json -Depth 7
