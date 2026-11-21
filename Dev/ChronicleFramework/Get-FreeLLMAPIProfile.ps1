function Get-FreeLLMAPIModelExecutionStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$ModelRows,
        [Parameter(Mandatory = $true)][string]$ModelId
    )

    $routerStrategies = @('auto:smart', 'auto:fast', 'auto:cheap', 'auto:reliable', 'auto:balanced',
        'auto:fastest', 'auto:speed', 'auto:smartest', 'auto:cheapest', 'auto:budget')
    if ($routerStrategies -contains $ModelId) { return 'router' }

    $model = $ModelRows | Where-Object { [string]$_.id -ceq $ModelId } | Select-Object -First 1
    if ($null -eq $model) { return 'not-listed' }
    if ($ModelId -match '^(auto|fusion)(:|$)' -or $ModelId -ceq 'free-router') { return 'router' }

    $status = [string]$model.execution_status
    if ($status -in @('ready', 'needsKey', 'exhausted')) { return $status }
    return 'unknown'
}

function Test-FreeLLMAPIModelExecutionReady {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$ModelRows,
        [Parameter(Mandatory = $true)][string]$ModelId
    )

    return (Get-FreeLLMAPIModelExecutionStatus -ModelRows $ModelRows -ModelId $ModelId) -in @('ready', 'router')
}

function Get-ChronicleProviderCredential {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][Uri]$Endpoint)

    $isFreeLlmApi = $Endpoint.IsLoopback -and $Endpoint.Port -eq 31415 -and $Endpoint.AbsolutePath.TrimEnd('/') -eq '/v1'
    $candidates = if ($isFreeLlmApi) {
        @(
            @{ Name = 'FREELLMAPI_API_KEY'; Target = 'Process' },
            @{ Name = 'FREELLMAPI_API_KEY'; Target = 'User' },
            @{ Name = 'CHRONICLE_LLM_API_KEY'; Target = 'Process' },
            @{ Name = 'CHRONICLE_LLM_API_KEY'; Target = 'User' }
        )
    } else {
        @(
            @{ Name = 'CHRONICLE_LLM_API_KEY'; Target = 'Process' },
            @{ Name = 'CHRONICLE_LLM_API_KEY'; Target = 'User' }
        )
    }
    foreach ($candidate in $candidates) {
        $value = [string][Environment]::GetEnvironmentVariable($candidate.Name, $candidate.Target)
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return [pscustomobject]@{ Value = $value; Source = "$($candidate.Name):$($candidate.Target)"; IsFreeLLMAPI = $isFreeLlmApi }
        }
    }
    return [pscustomobject]@{ Value = $null; Source = $null; IsFreeLLMAPI = $isFreeLlmApi }
}

function Initialize-FreeLLMAPIProfile {
    [CmdletBinding()]
    param()

    $baseUrl = [string][Environment]::GetEnvironmentVariable('CHRONICLE_LLM_BASE_URL', 'Process')
    if ([string]::IsNullOrWhiteSpace($baseUrl)) { $baseUrl = [string][Environment]::GetEnvironmentVariable('CHRONICLE_LLM_BASE_URL', 'User') }
    $modelId = [string][Environment]::GetEnvironmentVariable('CHRONICLE_LLM_MODEL', 'Process')
    if ([string]::IsNullOrWhiteSpace($modelId)) { $modelId = [string][Environment]::GetEnvironmentVariable('CHRONICLE_LLM_MODEL', 'User') }
    $protocol = [string][Environment]::GetEnvironmentVariable('CHRONICLE_LLM_PROTOCOL', 'Process')
    if ([string]::IsNullOrWhiteSpace($protocol)) { $protocol = [string][Environment]::GetEnvironmentVariable('CHRONICLE_LLM_PROTOCOL', 'User') }
    if ([string]::IsNullOrWhiteSpace($protocol)) { $protocol = 'openai-compatible' }

    $endpoint = $null
    if ($protocol -ne 'openai-compatible' -or
        -not [Uri]::TryCreate($baseUrl, [UriKind]::Absolute, [ref]$endpoint) -or
        -not $endpoint.IsLoopback -or $endpoint.Port -ne 31415 -or $endpoint.AbsolutePath.TrimEnd('/') -ne '/v1' -or
        -not [string]::IsNullOrWhiteSpace($endpoint.Query) -or -not [string]::IsNullOrWhiteSpace($endpoint.UserInfo)) {
        throw 'Chronicle live-model runs require FreeLLMAPI at the configured loopback /v1 endpoint. Local inference and other endpoints are refused before model use.'
    }
    if ([string]::IsNullOrWhiteSpace($modelId)) { throw 'FreeLLMAPI route/model name is not configured; no model request was sent.' }

    $credential = Get-ChronicleProviderCredential -Endpoint $endpoint
    $apiKey = [string]$credential.Value
    $apiKeySource = [string]$credential.Source
    if ([string]::IsNullOrWhiteSpace($apiKey)) { throw 'FreeLLMAPI unified key is missing from the process/user environment; the key is never read from UI or printed.' }

    [Environment]::SetEnvironmentVariable('CHRONICLE_LLM_BASE_URL', $baseUrl.TrimEnd('/'), 'Process')
    [Environment]::SetEnvironmentVariable('CHRONICLE_LLM_MODEL', $modelId.Trim(), 'Process')
    [Environment]::SetEnvironmentVariable('CHRONICLE_LLM_PROTOCOL', 'openai-compatible', 'Process')
    [Environment]::SetEnvironmentVariable('CHRONICLE_LLM_API_KEY', $apiKey, 'Process')
    $apiKey = $null

    function Test-FreeLLMAPIListener([Uri]$BaseEndpoint)
    {
        $pingUri = [UriBuilder]::new($BaseEndpoint)
        $pingUri.Path = '/api/ping'
        $pingUri.Query = ''
        try {
            $ping = Invoke-RestMethod -Uri $pingUri.Uri -Method Get -TimeoutSec 3
            return [string]$ping.status -eq 'ok'
        }
        catch { return $false }
    }

    function Test-ChronicleLocalProxyListener([string]$HostName, [int]$Port)
    {
        $client = [System.Net.Sockets.TcpClient]::new()
        try {
            $async = $client.BeginConnect($HostName, $Port, $null, $null)
            if (-not $async.AsyncWaitHandle.WaitOne(1500)) { return $false }
            $client.EndConnect($async)
            return $client.Connected
        }
        catch { return $false }
        finally { $client.Dispose() }
    }

    function Start-FreeLLMAPIWithInheritedProxy([string]$ExecutablePath)
    {
        # Child processes do not reliably receive environment updates made after
        # the parent (Codex/PowerShell) started. Restore the user's persisted
        # FreeLLMAPI proxy settings into this launch only, without logging values.
        $proxyEnvironmentNames = @('PROXY_URL', 'PROXY_MODE', 'ALL_PROXY', 'HTTPS_PROXY', 'HTTP_PROXY', 'NO_PROXY')
        $originalValues = @{}
        foreach ($name in $proxyEnvironmentNames) {
            $processValue = [Environment]::GetEnvironmentVariable($name, 'Process')
            $userValue = [Environment]::GetEnvironmentVariable($name, 'User')
            $originalValues[$name] = $processValue
            if ([string]::IsNullOrWhiteSpace($processValue) -and -not [string]::IsNullOrWhiteSpace($userValue)) {
                [Environment]::SetEnvironmentVariable($name, $userValue, 'Process')
            }
        }

        $proxyConfigured = $false
        foreach ($name in @('PROXY_URL', 'ALL_PROXY', 'HTTPS_PROXY', 'HTTP_PROXY')) {
            if (-not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name, 'Process'))) {
                $proxyConfigured = $true
                break
            }
        }

        $usedLocalProxyBootstrap = $false
        if (-not $proxyConfigured -and (Test-ChronicleLocalProxyListener -HostName '127.0.0.1' -Port 7890)) {
            [Environment]::SetEnvironmentVariable('HTTPS_PROXY', 'http://127.0.0.1:7890', 'Process')
            $usedLocalProxyBootstrap = $true
        }

        try { Start-Process -FilePath $ExecutablePath -WindowStyle Hidden | Out-Null }
        finally {
            foreach ($name in $proxyEnvironmentNames) {
                [Environment]::SetEnvironmentVariable($name, $originalValues[$name], 'Process')
            }
        }

        return $usedLocalProxyBootstrap
    }

    $gatewayStartedByHarness = $false
    $localProxyBootstrapApplied = $false
    if (-not (Test-FreeLLMAPIListener $endpoint)) {
        $desktopPath = Join-Path $env:LOCALAPPDATA 'Programs\freellmapi-desktop\FreeLLMAPI.exe'
        if (-not (Get-Process -Name 'FreeLLMAPI' -ErrorAction SilentlyContinue)) {
            if (-not (Test-Path -LiteralPath $desktopPath -PathType Leaf)) {
                throw 'FreeLLMAPI gateway is stopped and its desktop executable was not found; no inference request was sent.'
            }
            $localProxyBootstrapApplied = Start-FreeLLMAPIWithInheritedProxy -ExecutablePath $desktopPath
            $gatewayStartedByHarness = $true
        }
        $listenerReady = $false
        $listenerDeadline = (Get-Date).AddSeconds(30)
        do {
            if (Test-FreeLLMAPIListener $endpoint) { $listenerReady = $true; break }
            Start-Sleep -Seconds 1
        } while ((Get-Date) -lt $listenerDeadline)
        if (-not $listenerReady) {
            throw 'FreeLLMAPI desktop was started or already running, but its loopback API did not become ready within 30 seconds; no inference request was sent.'
        }
    }

    $modelsUri = [UriBuilder]::new($endpoint)
    $modelsUri.Path = '/v1/models'
    $modelsUri.Query = 'available=true'
    try {
        $catalog = Invoke-RestMethod -Uri $modelsUri.Uri -Method Get -Headers @{ Authorization = "Bearer $env:CHRONICLE_LLM_API_KEY" } -TimeoutSec 8
    }
    catch { throw 'FreeLLMAPI available-model preflight failed. No inference request was sent and no model call was attempted.' }

    $availableModelIds = @($catalog.data | ForEach-Object { [string]$_.id })
    $modelExecutionStatus = Get-FreeLLMAPIModelExecutionStatus -ModelRows @($catalog.data) -ModelId $modelId.Trim()
    if ($modelExecutionStatus -eq 'not-listed') { throw 'The selected FreeLLMAPI model/route is not in the currently available catalog; no inference request was sent.' }
    if ($modelExecutionStatus -notin @('ready', 'router')) {
        throw "The selected FreeLLMAPI model route is not executable now (execution_status=$modelExecutionStatus); no inference request was sent. Wait for provider recovery or select another ready FreeLLMAPI route."
    }
    $catalogBytes = [Text.Encoding]::UTF8.GetBytes(($availableModelIds | Sort-Object -Unique) -join "`n")
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $catalogHash = [BitConverter]::ToString($sha.ComputeHash($catalogBytes)).Replace('-', '') }
    finally { $sha.Dispose() }

    [pscustomobject]@{
        BaseUrl = $endpoint.GetLeftPart([UriPartial]::Path)
        RequestedModelId = $modelId.Trim()
        ModelExecutionStatus = $modelExecutionStatus
        AvailableModelCount = $availableModelIds.Count
        AvailableModelCatalogSha256 = $catalogHash
        ApiKeyPresent = $true
        ApiKeySource = $apiKeySource
        GatewayStartedByHarness = $gatewayStartedByHarness
        LocalProxyBootstrapApplied = $localProxyBootstrapApplied
    }
}

function Resolve-FreeLLMAPIProxyTrace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$ProgressEntries,
        [Parameter(Mandatory = $true)][string[]]$LogLines,
        [ValidateRange(1, 60)][int]$CorrelationWindowMinutes = 15
    )

    $failureEvents = @($ProgressEntries | Where-Object {
        [string]$_.event -ceq 'provider-failure' -and
        [string]$_.providerResponseRequestId -match '^[a-fA-F0-9]{8}-'
    })
    $correlatedAttempts = [System.Collections.Generic.List[object]]::new()
    foreach ($failure in $failureEvents) {
        $requestId = [string]$failure.providerResponseRequestId
        $requestPrefix = $requestId.Substring(0, 6).ToLowerInvariant()
        try { $failureUtc = [DateTimeOffset]::Parse([string]$failure.utc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal).UtcDateTime }
        catch { continue }
        $requestPrefixPattern = '\[Proxy\].*\b' + [regex]::Escape($requestPrefix) + '\b'

        foreach ($line in $LogLines) {
            if ($line -notmatch $requestPrefixPattern) { continue }
            if ($line -notmatch '^(?<utc>\d{4}-\d{2}-\d{2}T[^ ]+)\s+\[[^\]]+\]\s+\[Proxy\]\s+\d{2}:\d{2}:\d{2}\s+(?<event>start|fail|ok)\s+(?<prefix>[a-fA-F0-9]{6})\s+\S+\s+(?<provider>[a-zA-Z0-9_-]+)\s+\S+\s+(?<model>[^\s]+)(?<tail>.*)$') { continue }
            if ($Matches.prefix -ine $requestPrefix) { continue }
            try { $logUtc = [DateTimeOffset]::Parse([string]$Matches.utc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal).UtcDateTime }
            catch { continue }
            if ([Math]::Abs(($logUtc - $failureUtc).TotalMinutes) -gt $CorrelationWindowMinutes) { continue }

            $eventName = [string]$Matches.event
            $providerName = [string]$Matches.provider
            $modelName = [string]$Matches.model
            $errorKind = $null
            $latencyMilliseconds = $null
            $tail = [string]$Matches.tail
            if ($tail -match '\blat=(\d+)ms') { $latencyMilliseconds = [int]$Matches[1] }
            if ($eventName -ceq 'fail') {
                if ($tail -match '(?i)socket hang up|ECONNRESET') { $errorKind = 'connection-reset' }
                elseif ($tail -match '(?i)truncated JSON|finish_reason=length') { $errorKind = 'truncated-response' }
                elseif ($tail -match '(?i)429|rate.?limit|exhausted') { $errorKind = 'rate-limited' }
                elseif ($tail -match '(?i)401|403|invalid.{0,12}key|unauthorized') { $errorKind = 'authorization' }
                else { $errorKind = 'upstream-error' }
            }

            $correlatedAttempts.Add([pscustomobject]@{
                RequestIdPrefix = $requestPrefix
                Utc = $logUtc.ToString('O')
                Event = $eventName
                Provider = $providerName
                Model = $modelName
                LatencyMilliseconds = $latencyMilliseconds
                FailureKind = $errorKind
            })
        }
    }
    return @($correlatedAttempts | Sort-Object RequestIdPrefix, Utc, Event -Unique)
}

function Get-FreeLLMAPIProxyTrace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$ProgressEntries,
        [string]$LogPath = (Join-Path $env:APPDATA 'FreeLLMAPI\logs\freeapi.log')
    )

    $hasProviderFailure = @($ProgressEntries | Where-Object { [string]$_.event -ceq 'provider-failure' }).Count -gt 0
    if (-not $hasProviderFailure) { return [pscustomobject]@{ Status = 'no-provider-failure'; Attempts = @() } }
    if (-not (Test-Path -LiteralPath $LogPath -PathType Leaf)) { return [pscustomobject]@{ Status = 'log-not-found'; Attempts = @() } }

    try { $lines = @(Get-Content -LiteralPath $LogPath -Encoding UTF8) }
    catch { return [pscustomobject]@{ Status = 'log-unreadable'; Attempts = @() } }
    $attempts = @(Resolve-FreeLLMAPIProxyTrace -ProgressEntries $ProgressEntries -LogLines $lines)
    return [pscustomobject]@{
        Status = if ($attempts.Count -gt 0) { 'correlated' } else { 'request-not-correlated' }
        Attempts = $attempts
    }
}

function Test-FreeLLMAPIProxyTraceContract {
    [CmdletBinding()]
    param()

    $entries = @([pscustomobject]@{
        event = 'provider-failure'
        utc = '2026-01-01T00:00:02.000Z'
        providerResponseRequestId = 'abcdef12-3456-7890-abcd-ef1234567890'
    })
    $logs = @(
        '2026-01-01T00:00:01.000Z [log] [Proxy] 00:00:01 start abcdef a0 ovh - gpt-oss-20b req=gpt-oss-20b',
        '2026-01-01T00:00:02.000Z [log] [Proxy] 00:00:02 fail abcdef a0 ovh - gpt-oss-20b lat=1000ms err="socket hang up"',
        '2026-01-01T00:00:02.000Z [log] [Proxy] 00:00:02 fail fedcba a0 kilo - unrelated lat=1000ms err="socket hang up"'
    )
    $result = @(Resolve-FreeLLMAPIProxyTrace -ProgressEntries $entries -LogLines $logs)
    $failure = $result | Where-Object { $_.Event -ceq 'fail' } | Select-Object -First 1
    $fields = @($failure.PSObject.Properties.Name)
    if ($result.Count -ne 2 -or $null -eq $failure -or
        $failure.Provider -cne 'ovh' -or $failure.Model -cne 'gpt-oss-20b' -or
        $failure.FailureKind -cne 'connection-reset' -or $failure.LatencyMilliseconds -ne 1000 -or
        $fields -contains 'RawError' -or $fields -contains 'ApiKey' -or $fields -contains 'Prompt') {
        throw 'FreeLLMAPI proxy-log correlation failed request matching, safe-field projection, or error classification.'
    }
    return [pscustomobject]@{ Passed = $true; ModelCalls = 0; CorrelatedAttempts = $result.Count; RawProviderTextLogged = $false }
}
