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

    $apiKey = [string][Environment]::GetEnvironmentVariable('CHRONICLE_LLM_API_KEY', 'Process')
    if ([string]::IsNullOrWhiteSpace($apiKey)) { $apiKey = [string][Environment]::GetEnvironmentVariable('FREELLMAPI_API_KEY', 'Process') }
    if ([string]::IsNullOrWhiteSpace($apiKey)) { $apiKey = [string][Environment]::GetEnvironmentVariable('CHRONICLE_LLM_API_KEY', 'User') }
    if ([string]::IsNullOrWhiteSpace($apiKey)) { $apiKey = [string][Environment]::GetEnvironmentVariable('FREELLMAPI_API_KEY', 'User') }
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

    if (-not (Test-FreeLLMAPIListener $endpoint)) {
        $desktopPath = Join-Path $env:LOCALAPPDATA 'Programs\freellmapi-desktop\FreeLLMAPI.exe'
        if (-not (Get-Process -Name 'FreeLLMAPI' -ErrorAction SilentlyContinue)) {
            if (-not (Test-Path -LiteralPath $desktopPath -PathType Leaf)) {
                throw 'FreeLLMAPI gateway is stopped and its desktop executable was not found; no inference request was sent.'
            }
            Start-Process -FilePath $desktopPath -WindowStyle Hidden
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
    if ($modelId.Trim() -notin $availableModelIds) { throw 'The selected FreeLLMAPI model/route is not in the currently available catalog; no inference request was sent.' }
    $catalogBytes = [Text.Encoding]::UTF8.GetBytes(($availableModelIds | Sort-Object -Unique) -join "`n")
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $catalogHash = [BitConverter]::ToString($sha.ComputeHash($catalogBytes)).Replace('-', '') }
    finally { $sha.Dispose() }

    [pscustomobject]@{
        BaseUrl = $endpoint.GetLeftPart([UriPartial]::Path)
        RequestedModelId = $modelId.Trim()
        AvailableModelCount = $availableModelIds.Count
        AvailableModelCatalogSha256 = $catalogHash
        ApiKeyPresent = $true
    }
}
