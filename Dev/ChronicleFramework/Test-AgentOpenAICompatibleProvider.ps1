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
    $env:CHRONICLE_LLM_BASE_URL = "http://127.0.0.1:$port/v1/chat/completions"
    $env:CHRONICLE_LLM_MODEL = 'harness-contract-model'
    $env:CHRONICLE_LLM_API_KEY = $harnessSecret
    $env:CHRONICLE_LLM_TIMEOUT_SECONDS = [string]$TimeoutSeconds
    $env:CHRONICLE_LLM_MAX_TOKENS = '512'
    $env:CHRONICLE_LLM_MAX_TOKEN_PARAMETER = 'max_completion_tokens'

    $goal = 'Inspect currently visible safe settlements and then stop with the Native receipt.'
    $request = [ordered]@{
        schemaVersion = 2
        runId = 'provider-contract-test'
        iteration = 1
        goal = $goal
        allowedActions = @(
            [ordered]@{ action = 'mapSettlementTargets'; arguments = @() }
            [ordered]@{ action = 'move'; arguments = @('SettlementId') }
        )
        observation = [ordered]@{ state = [ordered]@{ context = [ordered]@{ gameState = 'MapState' }; location = [ordered]@{ currentSettlementId = 'town_V1' } } }
        previousActionReceipt = $null
    }
    $requestJson = $request | ConvertTo-Json -Depth 12 -Compress
    $failureStep = 'send-structured-model-request'
    $started = Start-ProviderProcess $requestJson
    $process = $started.Process
    $acceptTask = $listener.GetContextAsync()
    if (-not $acceptTask.Wait([Math]::Max(5000, $TimeoutSeconds * 1000))) { throw 'Local HTTP stub did not receive the provider request before timeout.' }
    $context = $acceptTask.GetAwaiter().GetResult()
    $reader = New-Object System.IO.StreamReader($context.Request.InputStream, $context.Request.ContentEncoding)
    $requestBody = $reader.ReadToEnd()
    $reader.Dispose()
    $apiRequest = $requestBody | ConvertFrom-Json
    $modelInput = [string]$apiRequest.messages[1].content | ConvertFrom-Json
    $requestGoalForwarded = ([string]$modelInput.goal -ceq $goal)
    $allowedNames = @($modelInput.allowedActions | ForEach-Object { [string]$_.action })
    $actionCatalogForwarded = ('mapSettlementTargets' -in $allowedNames -and 'move' -in $allowedNames -and 'advance' -notin $allowedNames)
    $authorizationSent = ($context.Request.Headers['Authorization'] -ceq "Bearer $harnessSecret")
    $payloadModeCorrect = ($apiRequest.model -eq 'harness-contract-model' -and $apiRequest.response_format.type -eq 'json_object' -and
        [int]$apiRequest.max_completion_tokens -eq 512 -and [bool]($apiRequest.store -eq $false) -and $apiRequest.stream -ne $true)

    $modelDecision = [ordered]@{
        action = 'mapSettlementTargets'
        arguments = @{}
        rationale = 'The current Campaign Map permits a read-only query of visible settlement targets.'
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
    $decisionValidated = ($decision.action -eq 'mapSettlementTargets' -and $decision.rationale -eq $expectedDecision.rationale)

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
        AllowedActionCatalogForwarded = $actionCatalogForwarded
        PriorReceiptFieldPresent = ($null -eq $modelInput.previousActionReceipt)
        AuthorizationHeaderSent = $authorizationSent
        RequestFormatCorrect = $payloadModeCorrect
        ProviderOutputCredentialFree = $providerOutputClean
        StructuredDecisionReturned = $decisionValidated
        ProviderExitCode = $successfulProviderExitCode
        HttpErrorFailsClosedWithoutCredentialLeak = $httpErrorFailedClosed
        TimeoutFailsClosedWithoutCredentialLeak = $timeoutFailedClosed
        Passed = ($requestGoalForwarded -and $actionCatalogForwarded -and $authorizationSent -and $payloadModeCorrect -and $providerOutputClean -and $decisionValidated -and $httpErrorFailedClosed -and $timeoutFailedClosed)
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
}
