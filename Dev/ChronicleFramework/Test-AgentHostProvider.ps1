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
    'CHRONICLE_LLM_PROTOCOL', 'CHRONICLE_LLM_BASE_URL', 'CHRONICLE_LLM_MODEL', 'CHRONICLE_LLM_API_KEY', 'FREELLMAPI_API_KEY',
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

. (Join-Path $PSScriptRoot 'Get-FreeLLMAPIProfile.ps1')
$freeLlmApiProfile = Initialize-FreeLLMAPIProfile
$model = [string]$freeLlmApiProfile.RequestedModelId
$protocol = 'openai-compatible'

$decisionRequest = [ordered]@{
    goal = 'Synthetic provider-contract probe only: choose the single listed Native action and return its exact allowed argument. No game command will be executed.'
    observation = [ordered]@{
        scope = 'provider-smoke-synthetic-visible-village-contact'
        state = [ordered]@{
            gameState = 'MapState'
            context = [ordered]@{ menuId = 'village' }
            worldMutationAllowed = $false
            settlementOverlayCharacters = @([ordered]@{
                heroId = 'CharacterObject_ProviderSmoke'
                name = 'Synthetic Notable'
                questMarkers = @([ordered]@{ type = 'AvailableIssue'; title = 'Needs tools'; hint = 'Synthetic provider probe only.' })
            })
        }
    }
    allowedActions = @([ordered]@{
        action = 'talkToSettlementHero'
        arguments = @('HeroId')
        argumentValues = [ordered]@{ HeroId = @('CharacterObject_ProviderSmoke') }
    })
    allowedControls = @()
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
if ($result.status -ne 'completed' -or $result.decision.action -cne 'talkToSettlementHero' -or
    $result.decision.arguments.HeroId -cne 'CharacterObject_ProviderSmoke' -or
    [string]::IsNullOrWhiteSpace([string]$result.decision.rationale)) {
    throw 'FreeLLMAPI-routed model did not select the single synthetic Native action and exact allowed target.'
}

$summary = [ordered]@{
    Passed = $true
    ProviderProtocol = $protocol
    FreeLLMAPIReachable = $true
    ConfiguredRouteAvailable = $freeLlmApiProfile.RequestedModelId
    AvailableModelCount = $freeLlmApiProfile.AvailableModelCount
    AvailableModelCatalogSha256 = $freeLlmApiProfile.AvailableModelCatalogSha256
    RoutedVia = [string]$result.routedVia
    ResultStatus = [string]$result.status
    ResponseFormatMode = [string]$result.responseFormatMode
    DecisionType = 'single-listed-native-action'
    DecisionAction = [string]$result.decision.action
    ExactListedArgument = ($result.decision.arguments.HeroId -ceq 'CharacterObject_ProviderSmoke')
    ReasonWordCount = ([string]$result.decision.rationale -split '\s+' | Where-Object { $_ }).Count
    PromptTokens = $result.promptTokens
    CompletionTokens = $result.completionTokens
    NativeCommands = 0
    RouterCatalog = 'FreeLLMAPI currently available catalog; actual provider captured in RoutedVia'
    NoModelEndpointOrCredentialLogged = $true
    ProviderContract = $protocolSelfTest
}
$summary | ConvertTo-Json -Depth 7
