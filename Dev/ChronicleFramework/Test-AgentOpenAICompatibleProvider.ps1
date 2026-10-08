[CmdletBinding()]
param([int]$TimeoutSeconds = 20)

$ErrorActionPreference = 'Stop'
$providerPath = Join-Path $PSScriptRoot 'Agent-OpenAICompatibleProvider.ps1'
$priorBaseUrl = $env:CHRONICLE_LLM_BASE_URL
$priorModel = $env:CHRONICLE_LLM_MODEL
$priorApiKey = $env:CHRONICLE_LLM_API_KEY
$priorTimeout = $env:CHRONICLE_LLM_TIMEOUT_SECONDS
$priorTokens = $env:CHRONICLE_LLM_MAX_TOKENS
$priorTokenParameter = $env:CHRONICLE_LLM_MAX_TOKEN_PARAMETER
$priorReasoningEffort = $env:CHRONICLE_LLM_REASONING_EFFORT
$priorTemperature = $env:CHRONICLE_LLM_TEMPERATURE
$harnessSecret = 'chronicle-local-provider-test-secret'
$listener = $null
$process = $null
$failureStep = 'preflight'

if (-not (Test-Path -LiteralPath $providerPath)) { throw "OpenAI-compatible provider not found: $providerPath" }

function Start-ProviderProcess($InputJson) {
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = (Get-Command powershell.exe -ErrorAction Stop).Source
    $startInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$providerPath`""
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $child = New-Object System.Diagnostics.Process
    $child.StartInfo = $startInfo
    if (-not $child.Start()) { throw 'Could not start the provider process.' }
    $stdoutTask = $child.StandardOutput.ReadToEndAsync()
    $stderrTask = $child.StandardError.ReadToEndAsync()
    $child.StandardInput.WriteLine($InputJson)
    $child.StandardInput.Close()
    return [pscustomobject]@{ Process = $child; StdoutTask = $stdoutTask; StderrTask = $stderrTask }
}

try {
    $tcpListener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $tcpListener.Start()
    $port = ([System.Net.IPEndPoint]$tcpListener.LocalEndpoint).Port
    $tcpListener.Stop()
    $listener = [System.Net.HttpListener]::new()
    $null = $listener.Prefixes.Add("http://127.0.0.1:$port/")
    $listener.Start()
    $env:CHRONICLE_LLM_BASE_URL = "http://127.0.0.1:$port/v1"
    $env:CHRONICLE_LLM_MODEL = 'harness-contract-model'
    $env:CHRONICLE_LLM_API_KEY = $harnessSecret
    $env:CHRONICLE_LLM_TIMEOUT_SECONDS = [string]$TimeoutSeconds
    $env:CHRONICLE_LLM_MAX_TOKENS = '512'
    $env:CHRONICLE_LLM_MAX_TOKEN_PARAMETER = 'max_completion_tokens'

    $goal = 'Inspect currently visible safe settlements and then stop with the Native receipt.'
    $expectedHeroName = -join @([char]0x6CD5,[char]0x5C14,[char]0x585E,[char]0x6C83)
    $request = [ordered]@{
        schemaVersion = 2
        runId = 'provider-contract-test'
        iteration = 1
        goal = $goal
        allowedActions = @(
            [ordered]@{ action = 'mapSettlementTargets'; arguments = @() }
            [ordered]@{ action = 'move'; arguments = @('SettlementId') }
        )
        observation = [ordered]@{ state = [ordered]@{ identity = [ordered]@{ heroName = $expectedHeroName }; context = [ordered]@{ gameState = 'MapState' }; location = [ordered]@{ currentSettlementId = 'town_V1' } } }
        previousActionReceipt = $null
    }
    $requestJson = $request | ConvertTo-Json -Depth 12 -Compress
    $failureStep = 'send-structured-model-request'
    $started = Start-ProviderProcess $requestJson
    $process = $started.Process
    $acceptTask = $listener.GetContextAsync()
    if (-not $acceptTask.Wait([Math]::Max(5000, $TimeoutSeconds * 1000))) { throw 'Local HTTP stub did not receive the provider request before timeout.' }
    $context = $acceptTask.GetAwaiter().GetResult()
    $endpointPathCorrect = ($context.Request.Url.AbsolutePath -ceq '/v1/chat/completions')
    $reader = New-Object System.IO.StreamReader($context.Request.InputStream, $context.Request.ContentEncoding)
    $requestBody = $reader.ReadToEnd()
    $reader.Dispose()
    $apiRequest = $requestBody | ConvertFrom-Json
    $modelInput = [string]$apiRequest.messages[1].content | ConvertFrom-Json
    $requestGoalForwarded = ([string]$modelInput.goal -ceq $goal)
    $unicodeObservationForwarded = ([string]$modelInput.observation.state.identity.heroName -ceq $expectedHeroName)
    $allowedNames = @($modelInput.allowedActions | ForEach-Object { [string]$_.action })
    $actionCatalogForwarded = ('mapSettlementTargets' -in $allowedNames -and 'move' -in $allowedNames -and 'advance' -notin $allowedNames)
    $authorizationSent = ($context.Request.Headers['Authorization'] -ceq "Bearer $harnessSecret")
    $payloadModeCorrect = ($apiRequest.model -eq 'harness-contract-model' -and $apiRequest.response_format.type -eq 'json_object' -and
        [int]$apiRequest.max_completion_tokens -eq 512 -and [bool]($apiRequest.store -eq $false) -and $apiRequest.stream -ne $true -and $null -eq $apiRequest.reasoning_effort -and $null -eq $apiRequest.temperature)

    $modelDecision = [ordered]@{
        action = 'mapSettlementTargets'
        arguments = @()
    } | ConvertTo-Json -Compress
    $responseJson = [ordered]@{
        id = 'chatcmpl-harness-provider-test'
        choices = @([ordered]@{ index = 0; message = [ordered]@{ role = 'assistant'; content = $modelDecision }; finish_reason = 'stop' })
    } | ConvertTo-Json -Depth 8 -Compress
    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($responseJson)
    $context.Response.StatusCode = 200
    $context.Response.ContentType = 'application/json; charset=utf-8'
    $context.Response.ContentLength64 = $responseBytes.Length
    $context.Response.OutputStream.Write($responseBytes, 0, $responseBytes.Length)
    $context.Response.OutputStream.Close()
    if (-not $process.WaitForExit(($TimeoutSeconds + 5) * 1000)) { try { $process.Kill() } catch { }; throw 'Provider did not exit after the HTTP response.' }
    $stdout = $started.StdoutTask.Result.Trim()
    $stderr = $started.StderrTask.Result.Trim()
    if ($process.ExitCode -ne 0) { throw "Provider rejected a valid stub response (exit=$($process.ExitCode)): $stderr" }
    $successfulProviderExitCode = $process.ExitCode
    $decision = $stdout | ConvertFrom-Json
    $expectedDecision = $modelDecision | ConvertFrom-Json
    $providerOutputClean = ($stdout -notmatch [regex]::Escape($harnessSecret) -and $stderr -notmatch [regex]::Escape($harnessSecret))
    $decisionValidated = ($decision.action -eq 'mapSettlementTargets' -and $decision.rationaleSource -eq 'provider-fallback' -and $decision.rationale -match 'omitted its rationale' -and $decision.arguments -is [System.Management.Automation.PSCustomObject] -and @($decision.arguments.PSObject.Properties).Count -eq 0)

    $failureStep = 'validate-bounded-observe-again-control-response'
    $observeAgainRequest = $request | ConvertTo-Json -Depth 12 -Compress
    $observeAgainProvider = Start-ProviderProcess $observeAgainRequest
    $process = $observeAgainProvider.Process
    $observeAcceptTask = $listener.GetContextAsync()
    if (-not $observeAcceptTask.Wait(5000)) { throw 'Local HTTP stub did not receive the observeAgain provider request.' }
    $observeContext = $observeAcceptTask.GetAwaiter().GetResult()
    $observeReader = New-Object System.IO.StreamReader($observeContext.Request.InputStream, $observeContext.Request.ContentEncoding)
    $null = $observeReader.ReadToEnd()
    $observeReader.Dispose()
    $observeDecisionJson = [ordered]@{ action = 'observeAgain'; arguments = @{ waitSeconds = 3 }; rationale = 'Native party remains en route; take a fresh bounded observation.' } | ConvertTo-Json -Compress
    $observeResponseJson = [ordered]@{ choices = @([ordered]@{ index = 0; message = [ordered]@{ role = 'assistant'; content = $observeDecisionJson }; finish_reason = 'stop' }) } | ConvertTo-Json -Depth 8 -Compress
    $observeBytes = [System.Text.Encoding]::UTF8.GetBytes($observeResponseJson)
    $observeContext.Response.StatusCode = 200
    $observeContext.Response.ContentType = 'application/json; charset=utf-8'
    $observeContext.Response.ContentLength64 = $observeBytes.Length
    $observeContext.Response.OutputStream.Write($observeBytes, 0, $observeBytes.Length)
    $observeContext.Response.OutputStream.Close()
    if (-not $process.WaitForExit(($TimeoutSeconds + 5) * 1000)) { try { $process.Kill() } catch { }; throw 'Provider did not exit after the observeAgain response.' }
    $observeStdout = $observeAgainProvider.StdoutTask.Result.Trim()
    $observeStderr = $observeAgainProvider.StderrTask.Result.Trim()
    if ($process.ExitCode -ne 0) { throw "Provider rejected a valid observeAgain response (exit=$($process.ExitCode)): $observeStderr" }
    $observeDecision = $observeStdout | ConvertFrom-Json
    $observeAgainValidated = ([bool]$observeDecision.observeAgain -and [int]$observeDecision.waitSeconds -eq 3 -and -not $observeDecision.action -and -not $observeDecision.done -and -not [string]::IsNullOrWhiteSpace([string]$observeDecision.reason))

    $failureStep = 'normalize-exact-positional-action-arguments'
    $tupleRequest = [ordered]@{
        schemaVersion = 2
        runId = 'provider-positional-tuple-test'
        iteration = 2
        goal = 'Submit one current native recruitment offer.'
        allowedActions = @([ordered]@{ action = 'recruit'; arguments = @('OwnerId','TroopId','VolunteerSlot','ConfirmPartySizeWarning') })
        allowedControls = @()
        nativeMoveArrival = $null
        observation = $request.observation
        previousActionReceipt = $null
    }
    $tupleProvider = Start-ProviderProcess ($tupleRequest | ConvertTo-Json -Depth 12 -Compress)
    $process = $tupleProvider.Process
    $tupleAcceptTask = $listener.GetContextAsync()
    if (-not $tupleAcceptTask.Wait(5000)) { throw 'Local HTTP stub did not receive the positional-argument normalization request.' }
    $tupleContext = $tupleAcceptTask.GetAwaiter().GetResult()
    $tupleReader = New-Object System.IO.StreamReader($tupleContext.Request.InputStream, $tupleContext.Request.ContentEncoding)
    $null = $tupleReader.ReadToEnd()
    $tupleReader.Dispose()
    $tupleModelDecision = [ordered]@{ action = 'recruit'; arguments = @('CharacterObject_1642','vlandian_recruit',3,$false) } | ConvertTo-Json -Compress
    $tupleResponseJson = [ordered]@{ choices = @([ordered]@{ index = 0; message = [ordered]@{ role = 'assistant'; content = $tupleModelDecision }; finish_reason = 'stop' }) } | ConvertTo-Json -Depth 8 -Compress
    $tupleResponseBytes = [System.Text.Encoding]::UTF8.GetBytes($tupleResponseJson)
    $tupleContext.Response.StatusCode = 200
    $tupleContext.Response.ContentType = 'application/json; charset=utf-8'
    $tupleContext.Response.ContentLength64 = $tupleResponseBytes.Length
    $tupleContext.Response.OutputStream.Write($tupleResponseBytes, 0, $tupleResponseBytes.Length)
    $tupleContext.Response.OutputStream.Close()
    if (-not $process.WaitForExit(($TimeoutSeconds + 5) * 1000)) { try { $process.Kill() } catch { }; throw 'Provider did not exit after the positional action response.' }
    $tupleStdout = $tupleProvider.StdoutTask.Result.Trim()
    $tupleStderr = $tupleProvider.StderrTask.Result.Trim()
    if ($process.ExitCode -ne 0) { throw "Provider rejected an exact ordered argument tuple (exit=$($process.ExitCode)): $tupleStderr" }
    $tupleDecision = $tupleStdout | ConvertFrom-Json
    $positionalArgumentsNormalized = ($tupleDecision.action -eq 'recruit' -and $tupleDecision.arguments.OwnerId -eq 'CharacterObject_1642' -and $tupleDecision.arguments.TroopId -eq 'vlandian_recruit' -and [int]$tupleDecision.arguments.VolunteerSlot -eq 3 -and -not [bool]$tupleDecision.arguments.ConfirmPartySizeWarning -and $tupleDecision.rationaleSource -eq 'provider-fallback')

    $failureStep = 'verify-local-openai-compatible-service-contract'
    $env:CHRONICLE_LLM_API_KEY = ''
    $env:CHRONICLE_LLM_MAX_TOKEN_PARAMETER = 'max_tokens'
    $env:CHRONICLE_LLM_REASONING_EFFORT = 'none'
    $env:CHRONICLE_LLM_TEMPERATURE = '0'
    $largeMapTargets = @(1..40 | ForEach-Object {
        [ordered]@{ id = "town_test_$_"; name = "Test settlement $_"; type = 'town'; distance = [double]$_; hostile = ($_ -gt 30); underSiege = $false }
    })
    $localRequest = [ordered]@{
        schemaVersion = 2
        runId = 'provider-large-receipt-test'
        iteration = 2
        goal = $goal
        allowedActions = $request.allowedActions
        observation = $request.observation
        previousActionReceipt = [ordered]@{
            protocolVersion = 1
            commandId = 'large-map-query-receipt'
            action = 'mapSettlementTargets'
            status = 'completed'
            campaignDay = 1234.5
            state = [ordered]@{ context = [ordered]@{ gameState = 'MapState' }; location = [ordered]@{ currentSettlementId = 'town_V1' } }
            data = [ordered]@{ mapSettlementTargets = $largeMapTargets }
        }
    }
    $localProvider = Start-ProviderProcess ($localRequest | ConvertTo-Json -Depth 16 -Compress)
    $process = $localProvider.Process
    $localAcceptTask = $listener.GetContextAsync()
    if (-not $localAcceptTask.Wait(5000)) { throw 'Local HTTP stub did not receive the local-model compatibility request.' }
    $localContext = $localAcceptTask.GetAwaiter().GetResult()
    $localReader = New-Object System.IO.StreamReader($localContext.Request.InputStream, $localContext.Request.ContentEncoding)
    $localRequestBody = $localReader.ReadToEnd()
    $localReader.Dispose()
    $localApiRequest = $localRequestBody | ConvertFrom-Json
    $localModelInput = [string]$localApiRequest.messages[1].content | ConvertFrom-Json
    $localTokenParameterCorrect = ([int]$localApiRequest.max_tokens -eq 512 -and $null -eq $localApiRequest.max_completion_tokens)
    $localReasoningEffortForwarded = ($localApiRequest.reasoning_effort -ceq 'none')
    $localTemperatureForwarded = ([double]$localApiRequest.temperature -eq 0)
    $localPromptTargets = @($localModelInput.previousActionReceipt.data.mapSettlementTargets)
    $localReceiptSummary = $localModelInput.previousActionReceipt.data.mapSettlementTargetsSummary
    $localReceiptCompacted = ($localPromptTargets.Count -eq 16 -and [int]$localReceiptSummary.totalCount -eq 40 -and [int]$localReceiptSummary.includedCount -eq 16 -and [int]$localReceiptSummary.omittedCount -eq 24 -and $null -eq $localModelInput.previousActionReceipt.state -and [string]$localModelInput.previousActionReceipt.stateSummary.location.currentSettlementId -ceq 'town_V1' -and [string]$localModelInput.previousActionReceipt.stateSummary.context.gameState -ceq 'MapState')
    $localNoAuthorizationHeader = [string]::IsNullOrWhiteSpace([string]$localContext.Request.Headers['Authorization'])
    $localResponseBytes = [System.Text.Encoding]::UTF8.GetBytes($responseJson)
    $localContext.Response.StatusCode = 200
    $localContext.Response.ContentType = 'application/json; charset=utf-8'
    $localContext.Response.ContentLength64 = $localResponseBytes.Length
    $localContext.Response.OutputStream.Write($localResponseBytes, 0, $localResponseBytes.Length)
    $localContext.Response.OutputStream.Close()
    if (-not $process.WaitForExit(($TimeoutSeconds + 5) * 1000)) { try { $process.Kill() } catch { }; throw 'Local-compatible provider did not exit after the HTTP response.' }
    $localStdout = $localProvider.StdoutTask.Result.Trim()
    $localStderr = $localProvider.StderrTask.Result.Trim()
    if ($process.ExitCode -ne 0) { throw "Provider rejected the local-compatible response (exit=$($process.ExitCode)): $localStderr" }
    $localDecision = $localStdout | ConvertFrom-Json
    $localCompatibilityPassed = ($localTokenParameterCorrect -and $localReasoningEffortForwarded -and $localTemperatureForwarded -and $localReceiptCompacted -and $localNoAuthorizationHeader -and $localDecision.action -eq 'mapSettlementTargets' -and $localStdout -notmatch [regex]::Escape($harnessSecret) -and $localStderr -notmatch [regex]::Escape($harnessSecret))
    $env:CHRONICLE_LLM_API_KEY = $harnessSecret
    $env:CHRONICLE_LLM_MAX_TOKEN_PARAMETER = 'max_completion_tokens'

    $failureStep = 'reject-action-outside-current-catalog'
    $invalidActionProvider = Start-ProviderProcess $requestJson
    $process = $invalidActionProvider.Process
    $invalidActionAcceptTask = $listener.GetContextAsync()
    if (-not $invalidActionAcceptTask.Wait(5000)) { throw 'Local HTTP stub did not receive the invalid-action test request.' }
    $invalidActionContext = $invalidActionAcceptTask.GetAwaiter().GetResult()
    $invalidActionReader = New-Object System.IO.StreamReader($invalidActionContext.Request.InputStream, $invalidActionContext.Request.ContentEncoding)
    $null = $invalidActionReader.ReadToEnd()
    $invalidActionReader.Dispose()
    $invalidActionDecision = [ordered]@{ action = 'advance'; arguments = @{}; rationale = 'The model requested a Harness-only time step.' } | ConvertTo-Json -Compress
    $invalidActionResponse = [ordered]@{ choices = @([ordered]@{ index = 0; message = [ordered]@{ role = 'assistant'; content = $invalidActionDecision }; finish_reason = 'stop' }) } | ConvertTo-Json -Depth 8 -Compress
    $invalidActionBytes = [System.Text.Encoding]::UTF8.GetBytes($invalidActionResponse)
    $invalidActionContext.Response.StatusCode = 200
    $invalidActionContext.Response.ContentType = 'application/json; charset=utf-8'
    $invalidActionContext.Response.ContentLength64 = $invalidActionBytes.Length
    $invalidActionContext.Response.OutputStream.Write($invalidActionBytes, 0, $invalidActionBytes.Length)
    $invalidActionContext.Response.OutputStream.Close()
    if (-not $process.WaitForExit(($TimeoutSeconds + 5) * 1000)) { try { $process.Kill() } catch { }; throw 'Provider did not exit after returning a disallowed action.' }
    $invalidActionStdout = $invalidActionProvider.StdoutTask.Result.Trim()
    $invalidActionStderr = $invalidActionProvider.StderrTask.Result.Trim()
    $invalidActionDecision = $null
    try { $invalidActionDecision = $invalidActionStdout | ConvertFrom-Json } catch { }
    $invalidActionFailedClosed = (
        $process.ExitCode -eq 0 -and
        [bool]$invalidActionDecision.decisionRejected -and
        [string]$invalidActionDecision.requestedAction -ceq 'advance' -and
        [string]$invalidActionDecision.reason -ceq 'not-in-current-action-catalog' -and
        @($invalidActionDecision.availableActions).Count -gt 0 -and
        $invalidActionStdout -notmatch [regex]::Escape($harnessSecret) -and
        $invalidActionStderr -notmatch [regex]::Escape($harnessSecret)
    )

    $failureStep = 'recover-from-unsupported-native-action-argument'
    $barterRequest = [ordered]@{
        schemaVersion = 2
        runId = 'provider-invalid-argument-test'
        iteration = 1
        goal = 'Submit the current Native barter offer.'
        allowedActions = @([ordered]@{ action = 'barterOffer'; arguments = @() })
        allowedControls = @()
        observation = $request.observation
        previousActionReceipt = $null
    }
    $invalidArgumentProvider = Start-ProviderProcess ($barterRequest | ConvertTo-Json -Depth 12 -Compress)
    $process = $invalidArgumentProvider.Process
    $invalidArgumentAcceptTask = $listener.GetContextAsync()
    if (-not $invalidArgumentAcceptTask.Wait(5000)) { throw 'Local HTTP stub did not receive the invalid-argument test request.' }
    $invalidArgumentContext = $invalidArgumentAcceptTask.GetAwaiter().GetResult()
    $invalidArgumentReader = New-Object System.IO.StreamReader($invalidArgumentContext.Request.InputStream, $invalidArgumentContext.Request.ContentEncoding)
    $null = $invalidArgumentReader.ReadToEnd()
    $invalidArgumentReader.Dispose()
    $badBarterDecision = [ordered]@{ action = 'barterOffer'; arguments = @{ candidateId = 'not-a-native-offer-parameter' }; rationale = 'Intentional extra-argument recovery regression.' } | ConvertTo-Json -Compress
    $badBarterResponse = [ordered]@{ choices = @([ordered]@{ index = 0; message = [ordered]@{ role = 'assistant'; content = $badBarterDecision }; finish_reason = 'stop' }) } | ConvertTo-Json -Depth 8 -Compress
    $badBarterBytes = [System.Text.Encoding]::UTF8.GetBytes($badBarterResponse)
    $invalidArgumentContext.Response.StatusCode = 200
    $invalidArgumentContext.Response.ContentType = 'application/json; charset=utf-8'
    $invalidArgumentContext.Response.ContentLength64 = $badBarterBytes.Length
    $invalidArgumentContext.Response.OutputStream.Write($badBarterBytes, 0, $badBarterBytes.Length)
    $invalidArgumentContext.Response.OutputStream.Close()
    if (-not $process.WaitForExit(($TimeoutSeconds + 5) * 1000)) { try { $process.Kill() } catch { }; throw 'Provider did not return after an unsupported action argument.' }
    $invalidArgumentStdout = $invalidArgumentProvider.StdoutTask.Result.Trim()
    $invalidArgumentStderr = $invalidArgumentProvider.StderrTask.Result.Trim()
    $invalidArgumentDecision = $null
    try { $invalidArgumentDecision = $invalidArgumentStdout | ConvertFrom-Json } catch { }
    $unsupportedActionArgumentRecoverable = (
        $process.ExitCode -eq 0 -and [bool]$invalidArgumentDecision.decisionRejected -and
        [string]$invalidArgumentDecision.reason -ceq 'invalid-action-arguments' -and
        [string]$invalidArgumentDecision.requestedAction -ceq 'barterOffer' -and
        @($invalidArgumentDecision.invalidArguments).Count -eq 1 -and [string]$invalidArgumentDecision.invalidArguments[0] -ceq 'candidateId' -and
        @($invalidArgumentDecision.allowedArguments).Count -eq 0 -and [bool]$invalidArgumentDecision.noNativeActionSent -and
        $invalidArgumentStdout -notmatch [regex]::Escape($harnessSecret) -and $invalidArgumentStderr -notmatch [regex]::Escape($harnessSecret)
    )

    $failureStep = 'fail-closed-on-provider-http-error'
    $httpErrorProvider = Start-ProviderProcess $requestJson
    $process = $httpErrorProvider.Process
    $errorAcceptTask = $listener.GetContextAsync()
    if (-not $errorAcceptTask.Wait(5000)) { throw 'Local HTTP stub did not receive the provider error-path request.' }
    $errorContext = $errorAcceptTask.GetAwaiter().GetResult()
    $errorReader = New-Object System.IO.StreamReader($errorContext.Request.InputStream, $errorContext.Request.ContentEncoding)
    $null = $errorReader.ReadToEnd()
    $errorReader.Dispose()
    $httpErrorBytes = [System.Text.Encoding]::UTF8.GetBytes('{"error":{"message":"test unauthorized"}}')
    $errorContext.Response.StatusCode = 401
    $errorContext.Response.ContentType = 'application/json'
    $errorContext.Response.ContentLength64 = $httpErrorBytes.Length
    $errorContext.Response.OutputStream.Write($httpErrorBytes, 0, $httpErrorBytes.Length)
    $errorContext.Response.OutputStream.Close()
    if (-not $process.WaitForExit(7000)) { try { $process.Kill() } catch { }; throw 'Provider did not exit after an HTTP 401 response.' }
    $httpErrorStdout = $httpErrorProvider.StdoutTask.Result.Trim()
    $httpErrorStderr = $httpErrorProvider.StderrTask.Result.Trim()
    $httpErrorFailedClosed = ($process.ExitCode -ne 0 -and $httpErrorStdout -notmatch '"action"' -and $httpErrorStderr -notmatch [regex]::Escape($harnessSecret))

    $failureStep = 'fail-closed-on-provider-timeout'
    $env:CHRONICLE_LLM_TIMEOUT_SECONDS = '5'
    $timeoutProvider = Start-ProviderProcess $requestJson
    $process = $timeoutProvider.Process
    $timeoutAcceptTask = $listener.GetContextAsync()
    if (-not $timeoutAcceptTask.Wait(5000)) { throw 'Local HTTP stub did not receive the provider timeout-path request.' }
    $timeoutContext = $timeoutAcceptTask.GetAwaiter().GetResult()
    $timeoutReader = New-Object System.IO.StreamReader($timeoutContext.Request.InputStream, $timeoutContext.Request.ContentEncoding)
    $null = $timeoutReader.ReadToEnd()
    $timeoutReader.Dispose()
    Start-Sleep -Seconds 7
    if (-not $process.WaitForExit(3000)) { try { $process.Kill() } catch { }; throw 'Provider remained alive past its configured HTTP timeout.' }
    $timeoutStdout = $timeoutProvider.StdoutTask.Result.Trim()
    $timeoutStderr = $timeoutProvider.StderrTask.Result.Trim()
    $timeoutFailedClosed = ($process.ExitCode -ne 0 -and $timeoutStdout -notmatch '"action"' -and $timeoutStderr -notmatch [regex]::Escape($harnessSecret))
    try { $timeoutContext.Response.Close() } catch { }

    $result = [ordered]@{
        ProviderKind = 'local HTTP stub; not a real model call'
        RequestGoalForwarded = $requestGoalForwarded
        UnicodeObservationForwarded = $unicodeObservationForwarded
        AllowedActionCatalogForwarded = $actionCatalogForwarded
        PriorReceiptFieldPresent = ($null -eq $modelInput.previousActionReceipt)
        AuthorizationHeaderSent = $authorizationSent
        LocalCompatibleMaxTokensWithoutAuthorization = $localCompatibilityPassed
        LocalReasoningEffortForwarded = $localReasoningEffortForwarded
        LocalTemperatureForwarded = $localTemperatureForwarded
        LargeMapReceiptCompacted = $localReceiptCompacted
        BaseUrlResolvedToChatCompletionsPath = $endpointPathCorrect
        RequestFormatCorrect = $payloadModeCorrect
        ProviderOutputCredentialFree = $providerOutputClean
        StructuredDecisionReturned = $decisionValidated
        BoundedObserveAgainControlValidated = $observeAgainValidated
        ExactPositionalArgumentsNormalized = $positionalArgumentsNormalized
        UnsupportedActionArgumentReturnsRecoverableRejection = $unsupportedActionArgumentRecoverable
        ProviderExitCode = $successfulProviderExitCode
        HttpErrorFailsClosedWithoutCredentialLeak = $httpErrorFailedClosed
        DisallowedActionFailsClosed = $invalidActionFailedClosed
        TimeoutFailsClosedWithoutCredentialLeak = $timeoutFailedClosed
        Passed = ($requestGoalForwarded -and $unicodeObservationForwarded -and $actionCatalogForwarded -and $authorizationSent -and $localCompatibilityPassed -and $endpointPathCorrect -and $payloadModeCorrect -and $providerOutputClean -and $decisionValidated -and $observeAgainValidated -and $positionalArgumentsNormalized -and $invalidActionFailedClosed -and $unsupportedActionArgumentRecoverable -and $httpErrorFailedClosed -and $timeoutFailedClosed)
    }
    $result | ConvertTo-Json -Depth 8
    if (-not $result.Passed) { exit 1 }
}
catch {
    Write-Error "Provider stub test failed at '$failureStep': $($_.Exception.Message)"
    exit 1
}
finally {
    if ($listener) { try { if ($listener.IsListening) { $listener.Stop() }; $listener.Close() } catch { } }
    if ($process) { try { if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit(3000) } } catch { } }
    if ($null -eq $priorBaseUrl) { Remove-Item Env:CHRONICLE_LLM_BASE_URL -ErrorAction SilentlyContinue } else { $env:CHRONICLE_LLM_BASE_URL = $priorBaseUrl }
    if ($null -eq $priorModel) { Remove-Item Env:CHRONICLE_LLM_MODEL -ErrorAction SilentlyContinue } else { $env:CHRONICLE_LLM_MODEL = $priorModel }
    if ($null -eq $priorApiKey) { Remove-Item Env:CHRONICLE_LLM_API_KEY -ErrorAction SilentlyContinue } else { $env:CHRONICLE_LLM_API_KEY = $priorApiKey }
    if ($null -eq $priorTimeout) { Remove-Item Env:CHRONICLE_LLM_TIMEOUT_SECONDS -ErrorAction SilentlyContinue } else { $env:CHRONICLE_LLM_TIMEOUT_SECONDS = $priorTimeout }
    if ($null -eq $priorTokens) { Remove-Item Env:CHRONICLE_LLM_MAX_TOKENS -ErrorAction SilentlyContinue } else { $env:CHRONICLE_LLM_MAX_TOKENS = $priorTokens }
    if ($null -eq $priorTokenParameter) { Remove-Item Env:CHRONICLE_LLM_MAX_TOKEN_PARAMETER -ErrorAction SilentlyContinue } else { $env:CHRONICLE_LLM_MAX_TOKEN_PARAMETER = $priorTokenParameter }
    if ($null -eq $priorReasoningEffort) { Remove-Item Env:CHRONICLE_LLM_REASONING_EFFORT -ErrorAction SilentlyContinue } else { $env:CHRONICLE_LLM_REASONING_EFFORT = $priorReasoningEffort }
    if ($null -eq $priorTemperature) { Remove-Item Env:CHRONICLE_LLM_TEMPERATURE -ErrorAction SilentlyContinue } else { $env:CHRONICLE_LLM_TEMPERATURE = $priorTemperature }
}
