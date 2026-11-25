#Requires -Version 7.0

# ConfiguredModelPreflight stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'ConfiguredModelPreflight' -Action {
    $savedLlmModel = [Environment]::GetEnvironmentVariable('CHRONICLE_LLM_MODEL', 'Process')
    try {
        [Environment]::SetEnvironmentVariable('CHRONICLE_LLM_MODEL', $FreshStoryModeModel, 'Process')
        . (Join-Path $stageRoot 'Get-FreeLLMAPIProfile.ps1')
        $providerBaseUrl = [string][Environment]::GetEnvironmentVariable('CHRONICLE_LLM_BASE_URL', 'Process')
        if ([string]::IsNullOrWhiteSpace($providerBaseUrl)) { $providerBaseUrl = [string][Environment]::GetEnvironmentVariable('CHRONICLE_LLM_BASE_URL', 'User') }
        $providerProtocol = [string][Environment]::GetEnvironmentVariable('CHRONICLE_LLM_PROTOCOL', 'Process')
        if ([string]::IsNullOrWhiteSpace($providerProtocol)) { $providerProtocol = [string][Environment]::GetEnvironmentVariable('CHRONICLE_LLM_PROTOCOL', 'User') }
        if ([string]::IsNullOrWhiteSpace($providerProtocol)) { $providerProtocol = 'openai-compatible' }
        $endpoint = $null
        if ($providerProtocol -cne 'openai-compatible' -or -not [Uri]::TryCreate($providerBaseUrl, [UriKind]::Absolute, [ref]$endpoint) -or
            -not [string]::IsNullOrWhiteSpace($endpoint.Query) -or -not [string]::IsNullOrWhiteSpace($endpoint.UserInfo) -or
            -not [string]::IsNullOrWhiteSpace($endpoint.Fragment)) {
            throw 'The selected model provider endpoint is not a safe absolute OpenAI-compatible URL; no inference request was sent.'
        }

        $isFreeLlmApiEndpoint = $endpoint.IsLoopback -and $endpoint.Port -eq 31415 -and $endpoint.AbsolutePath.TrimEnd('/') -eq '/v1'
        if ($isFreeLlmApiEndpoint) {
            $profile = Initialize-FreeLLMAPIProfile
            [ordered]@{
                ProviderKind = 'FreeLLMAPI'
                ProviderHost = $endpoint.Host
                ModelId = $profile.RequestedModelId
                ExecutionStatus = $profile.ModelExecutionStatus
                AvailableModelCount = $profile.AvailableModelCount
                CatalogSha256 = $profile.AvailableModelCatalogSha256
                InferenceRequests = 0
                BannerlordStarted = $false
                GatewayStartedByHarness = [bool]$profile.GatewayStartedByHarness
            } | ConvertTo-Json -Depth 4
            return
        }

        $isDshWorkBuddyEndpoint = $endpoint.IsLoopback -and $endpoint.Port -eq 8328 -and $endpoint.AbsolutePath.TrimEnd('/') -eq '/v1'
        if ($isDshWorkBuddyEndpoint) {
            if (-not $AllowDshWorkBuddyGateway -or $FreshStoryModeModel -notmatch '^buddy:hy4flash(?:-free)?$') {
                throw 'The DSH WorkBuddy route requires explicit opt-in to the listed buddy:hy4flash or buddy:hy4flash-free model; no inference request was sent.'
            }
            $credential = Get-ChronicleProviderCredential -Endpoint $endpoint
            if ([string]::IsNullOrWhiteSpace([string]$credential.Value)) { throw 'The dedicated DSH WorkBuddy gateway credential is unavailable; no inference request was sent.' }
            $modelsUri = [UriBuilder]::new($endpoint)
            $modelsUri.Path = '/v1/models'
            $modelsUri.Query = ''
            try { $catalog = Invoke-RestMethod -Uri $modelsUri.Uri -Headers @{ Authorization = "Bearer $($credential.Value)" } -TimeoutSec 12 }
            catch { throw 'The DSH WorkBuddy model-list preflight failed; no inference request was sent.' }
            $modelRows = @($catalog.data)
            if (@($modelRows | Where-Object { [string]$_.id -ceq $FreshStoryModeModel }).Count -ne 1) {
                throw 'The selected direct DSH WorkBuddy model is absent from the current gateway catalog; no inference request was sent.'
            }
            $dshHome = [string][Environment]::GetEnvironmentVariable('DSH_HOME', 'Process')
            if ([string]::IsNullOrWhiteSpace($dshHome)) { $dshHome = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)) '.dsh' }
            $dshStatusKeyPath = Join-Path $dshHome 'openai-gateway/api-key'
            $dshStatusKey = if (Test-Path -LiteralPath $dshStatusKeyPath -PathType Leaf) { [string](Get-Content -LiteralPath $dshStatusKeyPath -Raw).Trim() } else { $null }
            if ([string]::IsNullOrWhiteSpace($dshStatusKey)) { throw 'The local DSH status credential is unavailable; no inference request was sent.' }
            try { $dshStatus = Invoke-RestMethod -Uri 'http://127.0.0.1:2733/plugins/dsh-xdpool/status' -Headers @{ Authorization = "Bearer $dshStatusKey" } -TimeoutSec 8 }
            catch { throw 'The read-only DSH WorkBuddy model-status check failed; no inference request was sent.' }
            $bareWorkBuddyModelId = $FreshStoryModeModel.Substring('buddy:'.Length)
            $workBuddyModel = @($dshStatus.models | Where-Object { [string]$_.id -ceq $bareWorkBuddyModelId } | Select-Object -First 1)
            if ($workBuddyModel.Count -ne 1 -or $null -eq $workBuddyModel[0].multiplier -or [double]$workBuddyModel[0].multiplier -lt 0) {
                throw 'The selected DSH WorkBuddy model has no current credit-multiplier record; no inference request was sent.'
            }
            $usableWorkBuddyAccounts = @($dshStatus.accounts | Where-Object {
                -not [bool]$_.cooling -and $_.credentialDead -ne $true -and
                (($null -eq $_.credits) -or [double]$_.credits.total -gt 0)
            })
            if ($usableWorkBuddyAccounts.Count -eq 0) { throw 'The DSH WorkBuddy account pool has no currently usable account; no inference request was sent.' }
            [ordered]@{
                ProviderKind = 'DSH XD Pool WorkBuddy direct loopback gateway'
                ProviderHost = $endpoint.Host
                ModelId = $FreshStoryModeModel
                CatalogListed = $true
                AvailableModelCount = $modelRows.Count
                WorkBuddyCreditMultiplier = [double]$workBuddyModel[0].multiplier
                WorkBuddyModelTags = @($workBuddyModel[0].tags)
                WorkBuddyCreditReceiptAvailable = $true
                CurrencyPriceReceiptAvailable = $false
                UsableAccountCount = $usableWorkBuddyAccounts.Count
                InferenceRequests = 0
                BannerlordStarted = $false
                AutomaticFallbackEnabled = $false
            } | ConvertTo-Json -Depth 4
            return
        }

        $isDshXdPoolFreeEndpoint = $endpoint.IsLoopback -and $endpoint.Port -eq 8326 -and $endpoint.AbsolutePath.TrimEnd('/') -eq '/v1'
        if ($isDshXdPoolFreeEndpoint) {
            $isDshXdPoolWorkBuddyFreeModel = $FreshStoryModeModel -ceq 'xdpool/hy4flash-free'
            $isDirectDshFreeModel = ($FreshStoryModeModel -match '^xdpool-aggregate/(?!combo:)[^\r\n]+:free$' -and
                $FreshStoryModeModel -notmatch '(?i)(combo:|fallback|fusion|auto:)') -or $isDshXdPoolWorkBuddyFreeModel
            if (-not $AllowDshXdPoolFreeRoute -or -not $isDirectDshFreeModel) {
                throw 'DSH campaign preflight requires explicit opt-in to one direct free XD Pool model; combinations/fallbacks are blocked and no inference request was sent.'
            }
            $credential = Get-ChronicleProviderCredential -Endpoint $endpoint
            if ([string]::IsNullOrWhiteSpace([string]$credential.Value)) { throw 'The DSH OpenAI-compatible gateway credential is unavailable; no inference request was sent.' }
            if ($isDshXdPoolWorkBuddyFreeModel) {
                $dshFreeModelStatus = Get-DshXdPoolFreeModelStatus -ModelId $FreshStoryModeModel -Region 'cn'
                if (-not $dshFreeModelStatus.ReadyForBoundedInference) {
                    throw 'The DSH XD Pool model is disabled or lacks its verified zero-multiplier free tag; no inference request was sent.'
                }
                $modelsUri = [UriBuilder]::new($endpoint)
                $modelsUri.Path = $endpoint.AbsolutePath.TrimEnd('/') + '/models'
                $modelsUri.Query = ''
                try { $catalog = Invoke-RestMethod -Uri $modelsUri.Uri -Headers @{ Authorization = "Bearer $($credential.Value)" } -TimeoutSec 12 }
                catch { throw 'The DSH loopback model-list preflight failed; no inference request was sent.' }
                $modelRows = @($catalog.data)
                $modelListed = @($modelRows | Where-Object { [string]$_.id -ceq $FreshStoryModeModel }).Count -gt 0
                if (-not $modelListed) { throw 'The selected DSH XD Pool WorkBuddy free model is absent from the current gateway catalog; no inference request was sent.' }
                [ordered]@{
                    ProviderKind = 'DSH XD Pool WorkBuddy limited-time free model'
                    ProviderHost = $endpoint.Host
                    ModelId = $FreshStoryModeModel
                    CatalogListed = $true
                    AvailableModelCount = $modelRows.Count
                    PoolMultiplier = $dshFreeModelStatus.Multiplier
                    FreePromotionTagVerified = $dshFreeModelStatus.HasFreePromotionTag
                    CurrencyPriceReceiptAvailable = $false
                    InferenceRequests = 0
                    BannerlordStarted = $false
                    AutomaticFallbackEnabled = $false
                } | ConvertTo-Json -Depth 4
                return
            }
            $modelRouteMatch = [regex]::Match($FreshStoryModeModel, '^xdpool-aggregate/([^/]+)/(.+)$')
            if (-not $modelRouteMatch.Success) { throw 'The direct DSH model ID did not contain a provider segment; no inference request was sent.' }
            $dshProviderId = $modelRouteMatch.Groups[1].Value
            $dshProviderModelId = $modelRouteMatch.Groups[2].Value
            $aggregateUri = [Uri]::new('http://127.0.0.1:2733/plugins/dsh-xdpool/aggregate')
            try { $aggregateStatus = Invoke-RestMethod -Uri $aggregateUri -Headers @{ Authorization = "Bearer $($credential.Value)" } -TimeoutSec 8 }
            catch { throw 'The DSH aggregate status preflight failed; no inference request was sent.' }
            $aggregateProvider = @($aggregateStatus.providers | Where-Object { [string]$_.id -ceq $dshProviderId } | Select-Object -First 1)
            if ($aggregateProvider.Count -ne 1 -or -not [bool]$aggregateProvider[0].enabled -or
                -not [bool]$aggregateProvider[0].configured -or
                @($aggregateProvider[0].models | Where-Object { [string]$_ -ceq $dshProviderModelId }).Count -ne 1) {
                throw 'The selected direct DSH free model provider is disabled, unconfigured, or absent from its selected model set; no inference request was sent.'
            }
            if ($dshProviderId -cne 'open_router') {
                throw 'No current authoritative price verifier is configured for this DSH upstream provider; no inference request was sent.'
            }
            $openRouterPriceReceipt = Get-OpenRouterZeroPriceReceipt -ModelId $dshProviderModelId
            $modelsUri = [UriBuilder]::new($endpoint)
            $modelsUri.Path = $endpoint.AbsolutePath.TrimEnd('/') + '/models'
            $modelsUri.Query = ''
            try { $catalog = Invoke-RestMethod -Uri $modelsUri.Uri -Headers @{ Authorization = "Bearer $($credential.Value)" } -TimeoutSec 12 }
            catch { throw 'The DSH loopback model-list preflight failed; no inference request was sent.' }
            $modelRows = @($catalog.data)
            $modelListed = @($modelRows | Where-Object { [string]$_.id -ceq $FreshStoryModeModel }).Count -gt 0
            if (-not $modelListed) { throw 'The selected direct free DSH model is absent from the current gateway catalog; no inference request was sent.' }
            [ordered]@{
                ProviderKind = 'DSH XD Pool direct free-labeled model'
                ProviderHost = $endpoint.Host
                ModelId = $FreshStoryModeModel
                CatalogListed = $true
                AvailableModelCount = $modelRows.Count
                ModelPriceReceiptAvailable = $true
                PriceReceipt = $openRouterPriceReceipt
                InferenceRequests = 0
                BannerlordStarted = $false
                AutomaticFallbackEnabled = $false
            } | ConvertTo-Json -Depth 4
            return
        }

        if ($endpoint.Scheme -cne 'https') { throw 'Remote model preflight requires HTTPS; no inference request was sent.' }
        $credential = Get-ChronicleProviderCredential -Endpoint $endpoint
        if ([string]::IsNullOrWhiteSpace([string]$credential.Value)) { throw 'The configured remote model API key is unavailable; no inference request was sent.' }
        $modelsUri = [UriBuilder]::new($endpoint)
        $modelsUri.Path = $endpoint.AbsolutePath.TrimEnd('/') + '/models'
        $modelsUri.Query = ''
        try { $catalog = Invoke-RestMethod -Uri $modelsUri.Uri -Headers @{ Authorization = "Bearer $($credential.Value)" } -TimeoutSec 12 }
        catch { throw 'The configured remote provider read-only model-list preflight failed; no inference request was sent.' }
        $modelRows = @($catalog.data)
        $modelListed = @($modelRows | Where-Object { [string]$_.id -ceq $FreshStoryModeModel }).Count -gt 0
        if (-not $modelListed) { throw 'The selected model is absent from the configured remote provider catalog; no inference request was sent.' }
        [ordered]@{
            ProviderKind = 'direct-remote-openai-compatible'
            ProviderHost = $endpoint.Host
            ModelId = $FreshStoryModeModel
            ExecutionStatus = 'ready'
            AvailableModelCount = $modelRows.Count
            InferenceRequests = 0
            BannerlordStarted = $false
            FreeLLMAPIStartedByHarness = $false
        } | ConvertTo-Json -Depth 4
    }
    finally {
        [Environment]::SetEnvironmentVariable('CHRONICLE_LLM_MODEL', $savedLlmModel, 'Process')
    }
}
