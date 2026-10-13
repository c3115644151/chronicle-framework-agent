[CmdletBinding()]
param([int]$TimeoutSeconds = 20)

$ErrorActionPreference = 'Stop'
$providerPath = Join-Path $PSScriptRoot 'Agent-OpenAICompatibleProvider.ps1'
$budgetPolicyPath = Join-Path $PSScriptRoot 'Agent-ProviderBudget.ps1'
$decisionLoopPolicyPath = Join-Path $PSScriptRoot 'Agent-DecisionLoopPolicy.ps1'
. $budgetPolicyPath
. $decisionLoopPolicyPath
$priorBaseUrl = $env:CHRONICLE_LLM_BASE_URL
$priorModel = $env:CHRONICLE_LLM_MODEL
$priorApiKey = $env:CHRONICLE_LLM_API_KEY
$priorTimeout = $env:CHRONICLE_LLM_TIMEOUT_SECONDS
$priorTokens = $env:CHRONICLE_LLM_MAX_TOKENS
$priorTokenParameter = $env:CHRONICLE_LLM_MAX_TOKEN_PARAMETER
$priorReasoningEffort = $env:CHRONICLE_LLM_REASONING_EFFORT
$priorThinkingMode = $env:CHRONICLE_LLM_THINKING_MODE
$priorTemperature = $env:CHRONICLE_LLM_TEMPERATURE
$priorProtocol = $env:CHRONICLE_LLM_PROTOCOL
$priorHarnessProviderMode = $env:CHRONICLE_HARNESS_PROVIDER_MODE
$harnessSecret = 'chronicle-local-provider-test-secret'
$listener = $null
$process = $null
$ledgerTestRoot = $null
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
    $env:CHRONICLE_HARNESS_PROVIDER_MODE = 'protocol-stub'
    $tcpListener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $tcpListener.Start()
    $port = ([System.Net.IPEndPoint]$tcpListener.LocalEndpoint).Port
    $tcpListener.Stop()
    $listener = [System.Net.HttpListener]::new()
    $null = $listener.Prefixes.Add("http://127.0.0.1:$port/")
    $listener.Start()
    $env:CHRONICLE_LLM_PROTOCOL = 'openai-compatible'
    $env:CHRONICLE_LLM_BASE_URL = "http://127.0.0.1:$port/v1"
    $env:CHRONICLE_LLM_MODEL = 'harness-contract-model'
    $env:CHRONICLE_LLM_API_KEY = $harnessSecret
    $env:CHRONICLE_LLM_TIMEOUT_SECONDS = [string]$TimeoutSeconds
    $env:CHRONICLE_LLM_MAX_TOKENS = '512'
    $env:CHRONICLE_LLM_MAX_TOKEN_PARAMETER = 'max_completion_tokens'
    $env:CHRONICLE_LLM_THINKING_MODE = 'disabled'

    $goal = 'Inspect currently visible safe settlements and then stop with the Native receipt.'
    $expectedHeroName = -join @([char]0x6CD5,[char]0x5C14,[char]0x585E,[char]0x6C83)
    $request = [ordered]@{
        schemaVersion = 3
        runId = 'provider-contract-test'
        iteration = 1
        goal = $goal
        recentDecisionHistory = @([ordered]@{ iteration = 0; action = 'menuSelect'; arguments = [ordered]@{ OptionId = 'town_wait' }; decisionRejected = $false; rejectionReason = $null; nativeOutcome = [ordered]@{ action = 'menuSelect'; status = 'completed'; actionExecuted = $true; noNativeActionSent = $false } })
        allowedActions = @(
            [ordered]@{ action = 'mapSettlementTargets'; arguments = @() }
            [ordered]@{ action = 'move'; arguments = @('SettlementId') }
        )
        providerBudget = [ordered]@{ budgetId = 'provider-test-budget'; mode = 'token-only-local'; maxRequestBodyBytes = 65536; maxOutputTokensPerRequest = 128 }
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
    $nativeArgumentPromptBindingsPresent = ([string]$apiRequest.messages[0].content -match 'For `menuSelect`, set `arguments\.OptionId` to the exact `id` value' -and [string]$apiRequest.messages[0].content -match 'For `provision`, set `arguments\.ItemViewModelId` to the exact `viewModelItemId`' -and [string]$apiRequest.messages[0].content -match '`provision` only drafts a TradeVM transaction' -and [string]$apiRequest.messages[0].content -match 'bounded recentDecisionHistory')
    $requestGoalForwarded = ([string]$modelInput.goal -ceq $goal)
    $recentDecisionHistoryForwarded = (@($modelInput.recentDecisionHistory).Count -eq 1 -and [string]$modelInput.recentDecisionHistory[0].action -ceq 'menuSelect' -and [string]$modelInput.recentDecisionHistory[0].arguments.OptionId -ceq 'town_wait' -and [string]$modelInput.recentDecisionHistory[0].nativeOutcome.status -ceq 'completed')
    $unicodeObservationForwarded = ([string]$modelInput.observation.state.identity.heroName -ceq $expectedHeroName)
    $allowedNames = @($modelInput.allowedActions | ForEach-Object { [string]$_.action })
    $actionCatalogForwarded = ('mapSettlementTargets' -in $allowedNames -and 'move' -in $allowedNames -and 'advance' -notin $allowedNames)
    $authorizationSent = ($context.Request.Headers['Authorization'] -ceq "Bearer $harnessSecret")
    $payloadModeCorrect = ($apiRequest.model -eq 'harness-contract-model' -and $apiRequest.response_format.type -eq 'json_object' -and
        [int]$apiRequest.max_completion_tokens -eq 128 -and [bool]($apiRequest.store -eq $false) -and $apiRequest.stream -ne $true -and $apiRequest.thinking.type -ceq 'disabled' -and $null -eq $apiRequest.reasoning_effort -and $null -eq $apiRequest.temperature)

    $modelDecision = [ordered]@{
        action = 'mapSettlementTargets'
        arguments = @()
    } | ConvertTo-Json -Compress
    $responseJson = [ordered]@{
        id = 'chatcmpl-harness-provider-test'
        model = 'harness-contract-model'
        usage = [ordered]@{
            prompt_tokens = 1200
            completion_tokens = 42
            total_tokens = 1242
            prompt_tokens_details = [ordered]@{ prompt_cache_hit_tokens = 900; prompt_cache_miss_tokens = 300; cached_tokens = 900 }
            completion_tokens_details = [ordered]@{ reasoning_tokens = 0 }
        }
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
    $usageReceiptAccurate = ($decision.providerUsage.status -ceq 'reported' -and [bool]$decision.providerUsage.totalTokensConsistent -and [string]$decision.providerUsage.responseId -ceq 'chatcmpl-harness-provider-test' -and [int]$decision.providerUsage.promptTokens -eq 1200 -and [int]$decision.providerUsage.completionTokens -eq 42 -and [int]$decision.providerUsage.totalTokens -eq 1242 -and [int]$decision.providerUsage.promptCacheHitTokens -eq 900 -and [int]$decision.providerUsage.promptCacheMissTokens -eq 300 -and [int]$decision.providerUsage.reasoningTokens -eq 0 -and [int]$decision.providerUsage.requestAttempts -eq 1 -and [int]$decision.providerUsage.maxOutputTokens -eq 128 -and [int]$decision.providerUsage.requestBodyBytes -gt 0)

    $failureStep = 'compact-current-native-trade-observation-within-provider-budget'
    $tradeRequest = $request | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    $tradeRequest.runId = 'provider-trade-scope-test'
    $tradeRequest.providerBudget.maxRequestBodyBytes = 10000
    $tradeRequest.allowedActions = @(
        [ordered]@{ action = 'foodOptions'; arguments = @() }
        [ordered]@{ action = 'provision'; arguments = @('ItemViewModelId','Amount') }
        [ordered]@{ action = 'tradeConfirm'; arguments = @() }
        [ordered]@{ action = 'tradeCancelChanges'; arguments = @() }
    )
    $tradeState = [ordered]@{
        schemaVersion = 23
        campaignDay = 91077.401
        identity = [ordered]@{ heroId = 'main_hero'; heroName = $expectedHeroName; clanTier = 0 }
        economy = [ordered]@{ gold = 900; influence = 0; renown = 20 }
        party = [ordered]@{ members = 6; food = 0.95; foodChange = -0.3; dailyWage = 10; sizeLimit = 20 }
        location = [ordered]@{ currentSettlementId = 'town_V1'; targetSettlementId = 'town_V1' }
        context = [ordered]@{ gameState = 'InventoryState'; timeControlMode = 'Stop'; menuId = 'town'; escapeMenuOpen = $false; inquiryOpen = $false; encounterActive = $true; isWaiting = $true }
        inventoryScreen = [ordered]@{ mode = 'Trade'; lootItemCount = 0; playerItemCount = 0; hasHandler = $true }
        availableMenuOptions = @([ordered]@{ id = 'town_leave'; text = 'Leave'; available = $true; enabled = $true; isLeave = $true })
        mainHeroSkills = @([ordered]@{ id = 'Trade'; name = 'Trade'; level = 0 })
        settlementOverlayCharacters = @()
        nearbySettlements = @()
        nearbyParties = @()
        quests = @()
        danger = [ordered]@{ hostilePartyCount = 0; nearestHostileDistance = $null }
        mission = $null
        partyScreen = $null
    }
    $tradeState.settlementOverlayCharacters = @(1..8 | ForEach-Object { [ordered]@{ heroId = "hero_$_"; name = ('Notable ' + $_ + ' ' + ('x' * 80)); questMarkers = @() } })
    $tradeState.nearbyParties = @(1..8 | ForEach-Object { [ordered]@{ id = "party_$_"; name = ('Party ' + $_ + ' ' + ('y' * 80)); members = 100; strength = 100; hostile = $false } })
    $tradeRequest.observation.state = $tradeState
    $tradeRequest.previousActionReceipt = [ordered]@{
        protocolVersion = 1
        commandId = 'provider-trade-scope-options'
        action = 'foodOptions'
        status = 'completed'
        campaignDay = 91077.401
        dailyTickCount = 2
        timeControlMode = 'Stop'
        data = [ordered]@{ settlementId = 'town_V1'; gold = 900; offers = @([ordered]@{ viewModelItemId = 'olives'; itemId = 'olives'; name = 'Olives'; stock = 166; unitPrice = 9; isFood = $true; isTransferable = $true }) }
        state = $tradeState
    }
    $tradeProvider = Start-ProviderProcess ($tradeRequest | ConvertTo-Json -Depth 16 -Compress)
    $process = $tradeProvider.Process
    $tradeAcceptTask = $listener.GetContextAsync()
    if (-not $tradeAcceptTask.Wait(5000)) { throw 'Local HTTP stub did not receive the scoped Native trade request.' }
    $tradeContext = $tradeAcceptTask.GetAwaiter().GetResult()
    $tradeReader = New-Object System.IO.StreamReader($tradeContext.Request.InputStream, $tradeContext.Request.ContentEncoding)
    $tradeRequestBody = $tradeReader.ReadToEnd()
    $tradeReader.Dispose()
    $tradeApiRequest = $tradeRequestBody | ConvertFrom-Json
    $tradeModelInput = [string]$tradeApiRequest.messages[1].content | ConvertFrom-Json
    $tradeBodyWithinBudget = ([int]$tradeRequest.providerBudget.maxRequestBodyBytes -ge [System.Text.Encoding]::UTF8.GetByteCount($tradeRequestBody))
    $tradeObservationScoped = ([string]$tradeModelInput.observation.scope -ceq 'trade-transaction' -and 'settlementOverlayCharacters' -in @($tradeModelInput.observation.omittedStateFields) -and 'nearbyParties' -in @($tradeModelInput.observation.omittedStateFields) -and $null -eq $tradeModelInput.observation.state.settlementOverlayCharacters -and $null -eq $tradeModelInput.observation.state.nearbyParties)
    $tradeRequiredContextPreserved = ([string]$tradeModelInput.observation.state.context.gameState -ceq 'InventoryState' -and [string]$tradeModelInput.observation.state.inventoryScreen.mode -ceq 'Trade' -and [int]$tradeModelInput.observation.state.economy.gold -eq 900 -and [int]$tradeModelInput.observation.state.party.members -eq 6 -and [string]$tradeModelInput.previousActionReceipt.data.offers[0].viewModelItemId -ceq 'olives' -and [int]$tradeModelInput.previousActionReceipt.data.offers[0].unitPrice -eq 9 -and 'provision' -in @($tradeModelInput.allowedActions | ForEach-Object { [string]$_.action }))
    $tradeDecisionJson = [ordered]@{ action = 'provision'; arguments = [ordered]@{ ItemViewModelId = 'olives'; Amount = 1 }; rationale = 'Use the observed lowest-cost food offer.' } | ConvertTo-Json -Compress
    $tradeResponseJson = [ordered]@{ id = 'chatcmpl-harness-trade-scope'; model = 'harness-contract-model'; choices = @([ordered]@{ index = 0; message = [ordered]@{ role = 'assistant'; content = $tradeDecisionJson }; finish_reason = 'stop' }); usage = [ordered]@{ prompt_tokens = 500; completion_tokens = 24; total_tokens = 524 } } | ConvertTo-Json -Depth 8 -Compress
    $tradeResponseBytes = [System.Text.Encoding]::UTF8.GetBytes($tradeResponseJson)
    $tradeContext.Response.StatusCode = 200
    $tradeContext.Response.ContentType = 'application/json; charset=utf-8'
    $tradeContext.Response.ContentLength64 = $tradeResponseBytes.Length
    $tradeContext.Response.OutputStream.Write($tradeResponseBytes, 0, $tradeResponseBytes.Length)
    $tradeContext.Response.OutputStream.Close()
    if (-not $process.WaitForExit(($TimeoutSeconds + 5) * 1000)) { try { $process.Kill() } catch { }; throw 'Trade-scope provider did not exit after its local HTTP response.' }
    $tradeStdout = $tradeProvider.StdoutTask.Result.Trim()
    $tradeStderr = $tradeProvider.StderrTask.Result.Trim()
    if ($process.ExitCode -ne 0) { throw "Scoped Native trade request exceeded or failed the provider budget: $tradeStderr" }
    $tradeDecision = $tradeStdout | ConvertFrom-Json
    $tradeObservationCompactionVerified = ($tradeDecision.action -ceq 'provision' -and [string]$tradeDecision.arguments.ItemViewModelId -ceq 'olives' -and [int]$tradeDecision.arguments.Amount -eq 1 -and [string]$tradeDecision.providerUsage.responseId -ceq 'chatcmpl-harness-trade-scope' -and [string]$tradeDecision.providerUsage.observationScope -ceq 'trade-transaction' -and $tradeBodyWithinBudget -and $tradeObservationScoped -and $tradeRequiredContextPreserved -and $tradeStdout -notmatch [regex]::Escape($harnessSecret) -and $tradeStderr -notmatch [regex]::Escape($harnessSecret))

    $failureStep = 'fit-native-supply-view-and-nine-food-quotes-within-provider-budget'
    $supplyRequest = $tradeRequest | ConvertTo-Json -Depth 16 | ConvertFrom-Json
    $supplyRequest.runId = 'provider-multiday-supply-scope-test'
    $supplyRequest.observation | Add-Member -NotePropertyName modelView -NotePropertyValue 'campaign-multiday-supply' -Force
    $supplyContract = [ordered]@{
        schemaVersion = 1
        contractId = 'sargot-three-day-food-v1'
        conditions = @(
            [ordered]@{ id = 'party-members'; path = 'state.party.members'; operator = 'eq'; expected = 6 }
            [ordered]@{ id = 'daily-ticks'; path = 'dailyTickCount'; operator = 'gte'; expected = 5 }
            [ordered]@{ id = 'party-food'; path = 'state.party.food'; operator = 'gte'; expected = 1 }
            [ordered]@{ id = 'minimum-gold'; path = 'state.economy.gold'; operator = 'gte'; expected = 861 }
            [ordered]@{ id = 'town-menu'; path = 'state.context.menuId'; operator = 'eq'; expected = 'town' }
        )
    }
    $supplyRequest | Add-Member -NotePropertyName completionContract -NotePropertyValue $supplyContract -Force
    $supplyRequest.previousActionReceipt.data.offers = @(
        [ordered]@{ viewModelItemId = 'olives'; itemId = 'olives'; modifierId = ''; name = 'Olives'; stock = 166; nativeItemCost = 9; inventoryLogicUnitPrice = 9; unitWeight = 10; isFood = $true; isTransferable = $true; inventorySide = 'OtherInventory'; nativeTooltipType = 'Goods' }
        [ordered]@{ viewModelItemId = 'grain'; itemId = 'grain'; modifierId = ''; name = 'Grain'; stock = 155; nativeItemCost = 17; inventoryLogicUnitPrice = 17; unitWeight = 10; isFood = $true; isTransferable = $true; inventorySide = 'OtherInventory'; nativeTooltipType = 'Goods' }
        [ordered]@{ viewModelItemId = 'fish'; itemId = 'fish'; modifierId = ''; name = 'Fish'; stock = 38; nativeItemCost = 25; inventoryLogicUnitPrice = 25; unitWeight = 10; isFood = $true; isTransferable = $true; inventorySide = 'OtherInventory'; nativeTooltipType = 'Goods' }
        [ordered]@{ viewModelItemId = 'meat'; itemId = 'meat'; modifierId = ''; name = 'Meat'; stock = 64; nativeItemCost = 31; inventoryLogicUnitPrice = 31; unitWeight = 10; isFood = $true; isTransferable = $true; inventorySide = 'OtherInventory'; nativeTooltipType = 'Goods' }
        [ordered]@{ viewModelItemId = 'grape'; itemId = 'grape'; modifierId = ''; name = 'Grape'; stock = 31; nativeItemCost = 35; inventoryLogicUnitPrice = 35; unitWeight = 10; isFood = $true; isTransferable = $true; inventorySide = 'OtherInventory'; nativeTooltipType = 'Goods' }
        [ordered]@{ viewModelItemId = 'butter'; itemId = 'butter'; modifierId = ''; name = 'Butter'; stock = 6; nativeItemCost = 61; inventoryLogicUnitPrice = 61; unitWeight = 10; isFood = $true; isTransferable = $true; inventorySide = 'OtherInventory'; nativeTooltipType = 'Goods' }
        [ordered]@{ viewModelItemId = 'beer'; itemId = 'beer'; modifierId = ''; name = 'Beer'; stock = 8; nativeItemCost = 137; inventoryLogicUnitPrice = 137; unitWeight = 10; isFood = $true; isTransferable = $true; inventorySide = 'OtherInventory'; nativeTooltipType = 'Goods' }
        [ordered]@{ viewModelItemId = 'date_fruit'; itemId = 'date_fruit'; modifierId = ''; name = 'Date fruit'; stock = 2; nativeItemCost = 142; inventoryLogicUnitPrice = 142; unitWeight = 10; isFood = $true; isTransferable = $true; inventorySide = 'OtherInventory'; nativeTooltipType = 'Goods' }
        [ordered]@{ viewModelItemId = 'cheese'; itemId = 'cheese'; modifierId = ''; name = 'Cheese'; stock = 1; nativeItemCost = 176; inventoryLogicUnitPrice = 176; unitWeight = 10; isFood = $true; isTransferable = $true; inventorySide = 'OtherInventory'; nativeTooltipType = 'Goods' }
    )
    $supplyRequest.observation = Convert-SupplyObservationForDecision -Observation $supplyRequest.observation
    $supplyRequest.previousActionReceipt = Convert-SupplyReceiptForDecision -Receipt $supplyRequest.previousActionReceipt -Observation $supplyRequest.observation
    $supplyProvider = Start-ProviderProcess ($supplyRequest | ConvertTo-Json -Depth 20 -Compress)
    $process = $supplyProvider.Process
    $supplyAcceptTask = $listener.GetContextAsync()
    if (-not $supplyAcceptTask.Wait(5000)) { throw 'Local HTTP stub did not receive the scoped supply request.' }
    $supplyContext = $supplyAcceptTask.GetAwaiter().GetResult()
    $supplyReader = New-Object System.IO.StreamReader($supplyContext.Request.InputStream, $supplyContext.Request.ContentEncoding)
    $supplyRequestBody = $supplyReader.ReadToEnd()
    $supplyReader.Dispose()
    $supplyApiRequest = $supplyRequestBody | ConvertFrom-Json
    $supplyModelInput = [string]$supplyApiRequest.messages[1].content | ConvertFrom-Json
    $supplyBodyWithinBudget = ([int]$supplyRequest.providerBudget.maxRequestBodyBytes -ge [System.Text.Encoding]::UTF8.GetByteCount($supplyRequestBody))
    $supplyDecisionJson = [ordered]@{ action = 'provision'; arguments = [ordered]@{ ItemViewModelId = 'olives'; Amount = 1 }; rationale = 'Use the observed cheapest food quote.' } | ConvertTo-Json -Compress
    $supplyResponseJson = [ordered]@{ id = 'chatcmpl-harness-supply-scope'; model = 'harness-contract-model'; choices = @([ordered]@{ index = 0; message = [ordered]@{ role = 'assistant'; content = $supplyDecisionJson }; finish_reason = 'stop' }); usage = [ordered]@{ prompt_tokens = 800; completion_tokens = 25; total_tokens = 825 } } | ConvertTo-Json -Depth 8 -Compress
    $supplyResponseBytes = [System.Text.Encoding]::UTF8.GetBytes($supplyResponseJson)
    $supplyContext.Response.StatusCode = 200
    $supplyContext.Response.ContentType = 'application/json; charset=utf-8'
    $supplyContext.Response.ContentLength64 = $supplyResponseBytes.Length
    $supplyContext.Response.OutputStream.Write($supplyResponseBytes, 0, $supplyResponseBytes.Length)
    $supplyContext.Response.OutputStream.Close()
    if (-not $process.WaitForExit(($TimeoutSeconds + 5) * 1000)) { try { $process.Kill() } catch { }; throw 'Scoped supply provider did not exit after its local HTTP response.' }
    $supplyStdout = $supplyProvider.StdoutTask.Result.Trim()
    $supplyStderr = $supplyProvider.StderrTask.Result.Trim()
    if ($process.ExitCode -ne 0) { throw "Scoped supply request failed its provider budget: $supplyStderr" }
    $supplyDecision = $supplyStdout | ConvertFrom-Json
    $supplyReceiptRetainsActionFacts = (@($supplyModelInput.previousActionReceipt.data.offers).Count -eq 9 -and [string]$supplyModelInput.previousActionReceipt.data.offers[0].viewModelItemId -ceq 'olives' -and [int]$supplyModelInput.previousActionReceipt.data.offers[0].stock -eq 166 -and [int]$supplyModelInput.previousActionReceipt.data.offers[0].inventoryLogicUnitPrice -eq 9 -and $null -eq $supplyModelInput.previousActionReceipt.data.offers[0].unitWeight -and [string]$supplyModelInput.observation.modelView -ceq 'campaign-multiday-supply' -and [string]$supplyModelInput.completionContract.contractId -ceq 'sargot-three-day-food-v1' -and [int]$supplyModelInput.completionContract.conditions[3].expected -eq 861)
    $supplyProfileFitsBudget = ($supplyDecision.action -ceq 'provision' -and [string]$supplyDecision.providerUsage.observationScope -ceq 'campaign-multiday-supply' -and [int]$supplyDecision.providerUsage.systemPromptBytes -lt 3000 -and $supplyBodyWithinBudget -and $supplyReceiptRetainsActionFacts -and $supplyStdout -notmatch [regex]::Escape($harnessSecret) -and $supplyStderr -notmatch [regex]::Escape($harnessSecret))

    $failureStep = 'normalize-action-done-as-native-verifiable-stop-proposal'
    $doneAliasProvider = Start-ProviderProcess $requestJson
    $process = $doneAliasProvider.Process
    $doneAliasAcceptTask = $listener.GetContextAsync()
    if (-not $doneAliasAcceptTask.Wait(5000)) { throw 'Local HTTP stub did not receive the done-alias provider request.' }
    $doneAliasContext = $doneAliasAcceptTask.GetAwaiter().GetResult()
    $doneAliasReader = New-Object System.IO.StreamReader($doneAliasContext.Request.InputStream, $doneAliasContext.Request.ContentEncoding)
    $doneAliasRequestBody = $doneAliasReader.ReadToEnd()
    $doneAliasReader.Dispose()
    $doneAliasDecisionJson = [ordered]@{ action = 'done'; arguments = @{}; rationale = 'The objective appears satisfied; ask the Native verifier to confirm.' } | ConvertTo-Json -Compress
    $doneAliasResponseJson = [ordered]@{ id = 'chatcmpl-harness-done-alias'; model = 'harness-contract-model'; choices = @([ordered]@{ index = 0; message = [ordered]@{ role = 'assistant'; content = $doneAliasDecisionJson }; finish_reason = 'stop' }); usage = [ordered]@{ prompt_tokens = 310; completion_tokens = 22; total_tokens = 332 } } | ConvertTo-Json -Depth 8 -Compress
    $doneAliasResponseBytes = [System.Text.Encoding]::UTF8.GetBytes($doneAliasResponseJson)
    $doneAliasContext.Response.StatusCode = 200
    $doneAliasContext.Response.ContentType = 'application/json; charset=utf-8'
    $doneAliasContext.Response.ContentLength64 = $doneAliasResponseBytes.Length
    $doneAliasContext.Response.OutputStream.Write($doneAliasResponseBytes, 0, $doneAliasResponseBytes.Length)
    $doneAliasContext.Response.OutputStream.Close()
    if (-not $process.WaitForExit(($TimeoutSeconds + 5) * 1000)) { try { $process.Kill() } catch { }; throw 'Done-alias provider did not exit after its local HTTP response.' }
    $doneAliasStdout = $doneAliasProvider.StdoutTask.Result.Trim()
    $doneAliasStderr = $doneAliasProvider.StderrTask.Result.Trim()
    if ($process.ExitCode -ne 0) { throw "Done-alias provider failed to return a stop proposal: $doneAliasStderr" }
    $doneAliasDecision = $doneAliasStdout | ConvertFrom-Json
    $doneAliasNormalizesToStop = ([bool]$doneAliasDecision.done -and [string]$doneAliasDecision.reason -match 'Native verifier' -and $null -eq $doneAliasDecision.action -and [string]$doneAliasDecision.providerUsage.responseId -ceq 'chatcmpl-harness-done-alias' -and [int]$doneAliasDecision.providerUsage.totalTokens -eq 332 -and $doneAliasStdout -notmatch [regex]::Escape($harnessSecret) -and $doneAliasStderr -notmatch [regex]::Escape($harnessSecret))

    $failureStep = 'normalize-ollama-native-provider-usage'
    $env:CHRONICLE_LLM_PROTOCOL = 'ollama-native'
    $env:CHRONICLE_LLM_BASE_URL = "http://127.0.0.1:$port"
    $env:CHRONICLE_LLM_MODEL = 'harness-ollama-native-model'
    $env:CHRONICLE_LLM_API_KEY = ''
    $nativeProvider = Start-ProviderProcess $requestJson
    $process = $nativeProvider.Process
    $nativeAcceptTask = $listener.GetContextAsync()
    if (-not $nativeAcceptTask.Wait(5000)) { throw 'Local HTTP stub did not receive the Ollama-native provider request.' }
    $nativeContext = $nativeAcceptTask.GetAwaiter().GetResult()
    $nativeReader = New-Object System.IO.StreamReader($nativeContext.Request.InputStream, $nativeContext.Request.ContentEncoding)
    $nativeRequestBody = $nativeReader.ReadToEnd()
    $nativeReader.Dispose()
    $nativeApiRequest = $nativeRequestBody | ConvertFrom-Json
    $nativeRequestShapeCorrect = ($nativeContext.Request.Url.AbsolutePath -ceq '/api/chat' -and $nativeApiRequest.format -ceq 'json' -and -not [bool]$nativeApiRequest.stream -and [int]$nativeApiRequest.options.num_predict -eq 128 -and $nativeApiRequest.messages.Count -eq 2 -and [string]$nativeApiRequest.model -ceq 'harness-ollama-native-model' -and [string]::IsNullOrWhiteSpace([string]$nativeContext.Request.Headers['Authorization']))
    $nativeDecisionJson = [ordered]@{ action = 'mapSettlementTargets'; arguments = @{}; rationale = 'Return the currently observed settlement targets.' } | ConvertTo-Json -Compress
    $nativeResponseJson = [ordered]@{ model = 'harness-ollama-native-model'; message = [ordered]@{ role = 'assistant'; content = $nativeDecisionJson }; done = $true; done_reason = 'stop'; prompt_eval_count = 77; eval_count = 14 } | ConvertTo-Json -Depth 8 -Compress
    $nativeResponseBytes = [System.Text.Encoding]::UTF8.GetBytes($nativeResponseJson)
    $nativeContext.Response.StatusCode = 200
    $nativeContext.Response.ContentType = 'application/json; charset=utf-8'
    $nativeContext.Response.ContentLength64 = $nativeResponseBytes.Length
    $nativeContext.Response.OutputStream.Write($nativeResponseBytes, 0, $nativeResponseBytes.Length)
    $nativeContext.Response.OutputStream.Close()
    if (-not $process.WaitForExit(($TimeoutSeconds + 5) * 1000)) { try { $process.Kill() } catch { }; throw 'Ollama-native provider did not exit after its local HTTP response.' }
    $nativeStdout = $nativeProvider.StdoutTask.Result.Trim()
    $nativeStderr = $nativeProvider.StderrTask.Result.Trim()
    if ($process.ExitCode -ne 0) { throw "Ollama-native provider failed to normalize its local response: $nativeStderr" }
    $nativeDecision = $nativeStdout | ConvertFrom-Json
    $ollamaNativeUsageReceiptChecks = [ordered]@{
        DecisionAction = ($nativeDecision.action -ceq 'mapSettlementTargets')
        Protocol = ($nativeDecision.providerUsage.protocol -ceq 'ollama-native')
        UsageReported = ($nativeDecision.providerUsage.status -ceq 'reported')
        UsageConsistent = [bool]$nativeDecision.providerUsage.totalTokensConsistent
        TokenCounts = ([int]$nativeDecision.providerUsage.promptTokens -eq 77 -and [int]$nativeDecision.providerUsage.completionTokens -eq 14 -and [int]$nativeDecision.providerUsage.totalTokens -eq 91)
        FinishReason = ([string]$nativeDecision.providerUsage.finishReason -ceq 'stop')
        CacheMissOmitted = ($null -eq $nativeDecision.providerUsage.promptCacheMissTokens)
        RequestShape = $nativeRequestShapeCorrect
        NoCredentialLeak = ($nativeStdout -notmatch [regex]::Escape($harnessSecret) -and $nativeStderr -notmatch [regex]::Escape($harnessSecret))
    }
    $ollamaNativeUsageReceiptCorrect = -not [bool]@($ollamaNativeUsageReceiptChecks.Values | Where-Object { -not $_ }).Count
    $env:CHRONICLE_LLM_PROTOCOL = 'openai-compatible'
    $env:CHRONICLE_LLM_BASE_URL = "http://127.0.0.1:$port/v1"
    $env:CHRONICLE_LLM_MODEL = 'harness-contract-model'
    $env:CHRONICLE_LLM_API_KEY = $harnessSecret

    $failureStep = 'enforce-provider-request-body-budget-before-http'
    $oversizeRequest = $request | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    $oversizeRequest.providerBudget.maxRequestBodyBytes = 1024
    $oversizeProvider = Start-ProviderProcess ($oversizeRequest | ConvertTo-Json -Depth 12 -Compress)
    $process = $oversizeProvider.Process
    if (-not $process.WaitForExit(($TimeoutSeconds + 5) * 1000)) { try { $process.Kill() } catch { }; throw 'Provider did not stop when the request-body budget was exceeded.' }
    $oversizeStdout = $oversizeProvider.StdoutTask.Result.Trim()
    $oversizeStderr = $oversizeProvider.StderrTask.Result.Trim()
    $oversizeReceipt = $oversizeStdout | ConvertFrom-Json
    $requestBodyBudgetRejectedBeforeHttp = ($process.ExitCode -eq 0 -and [bool]$oversizeReceipt.providerBudgetRejected -and [bool]$oversizeReceipt.noHttpRequestSent -and [int]$oversizeReceipt.providerUsage.requestBodyBytes -gt 1024 -and $oversizeStderr -notmatch [regex]::Escape($harnessSecret))

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
    $missingUsageNotZero = ([string]$observeDecision.providerUsage.status -ceq 'unavailable' -and $null -eq $observeDecision.providerUsage.promptTokens -and $null -eq $observeDecision.providerUsage.completionTokens)

    $failureStep = 'normalize-exact-positional-action-arguments'
    $tupleRequest = [ordered]@{
        schemaVersion = 3
        runId = 'provider-positional-tuple-test'
        iteration = 2
        goal = 'Submit one current native recruitment offer.'
        recentDecisionHistory = @()
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

    $failureStep = 'normalize-string-encoded-object-action-arguments'
    $encodedArgumentsRequest = [ordered]@{
        schemaVersion = 3
        runId = 'provider-string-encoded-arguments-test'
        iteration = 1
        goal = 'Submit the current observed Native food offer.'
        recentDecisionHistory = @()
        allowedActions = @([ordered]@{ action = 'provision'; arguments = @('ItemViewModelId','Amount') })
        allowedControls = @()
        observation = $request.observation
        previousActionReceipt = $null
    }
    $encodedArgumentsProvider = Start-ProviderProcess ($encodedArgumentsRequest | ConvertTo-Json -Depth 12 -Compress)
    $process = $encodedArgumentsProvider.Process
    $encodedArgumentsAcceptTask = $listener.GetContextAsync()
    if (-not $encodedArgumentsAcceptTask.Wait(5000)) { throw 'Local HTTP stub did not receive the string-encoded action-argument request.' }
    $encodedArgumentsContext = $encodedArgumentsAcceptTask.GetAwaiter().GetResult()
    $encodedArgumentsReader = New-Object System.IO.StreamReader($encodedArgumentsContext.Request.InputStream, $encodedArgumentsContext.Request.ContentEncoding)
    $null = $encodedArgumentsReader.ReadToEnd()
    $encodedArgumentsReader.Dispose()
    $encodedObject = [ordered]@{ ItemViewModelId = 'olives'; Amount = 4 } | ConvertTo-Json -Compress
    $encodedModelDecision = [ordered]@{ action = 'provision'; arguments = $encodedObject; rationale = 'Buy four units from the current Native food offer.' } | ConvertTo-Json -Compress
    $encodedResponseJson = [ordered]@{ choices = @([ordered]@{ index = 0; message = [ordered]@{ role = 'assistant'; content = $encodedModelDecision }; finish_reason = 'stop' }) } | ConvertTo-Json -Depth 8 -Compress
    $encodedResponseBytes = [System.Text.Encoding]::UTF8.GetBytes($encodedResponseJson)
    $encodedArgumentsContext.Response.StatusCode = 200
    $encodedArgumentsContext.Response.ContentType = 'application/json; charset=utf-8'
    $encodedArgumentsContext.Response.ContentLength64 = $encodedResponseBytes.Length
    $encodedArgumentsContext.Response.OutputStream.Write($encodedResponseBytes, 0, $encodedResponseBytes.Length)
    $encodedArgumentsContext.Response.OutputStream.Close()
    if (-not $process.WaitForExit(($TimeoutSeconds + 5) * 1000)) { try { $process.Kill() } catch { }; throw 'Provider did not exit after string-encoded action arguments.' }
    $encodedArgumentsStdout = $encodedArgumentsProvider.StdoutTask.Result.Trim()
    $encodedArgumentsStderr = $encodedArgumentsProvider.StderrTask.Result.Trim()
    if ($process.ExitCode -ne 0) { throw "Provider rejected a valid JSON-object string for action arguments (exit=$($process.ExitCode)): $encodedArgumentsStderr" }
    $encodedArgumentsDecision = $encodedArgumentsStdout | ConvertFrom-Json
    $stringEncodedArgumentsNormalized = ($encodedArgumentsDecision.action -ceq 'provision' -and $encodedArgumentsDecision.arguments -is [System.Management.Automation.PSCustomObject] -and [string]$encodedArgumentsDecision.arguments.ItemViewModelId -ceq 'olives' -and [int]$encodedArgumentsDecision.arguments.Amount -eq 4)

    $failureStep = 'normalize-single-string-array-action-arguments'
    $singleArrayProvider = Start-ProviderProcess ($encodedArgumentsRequest | ConvertTo-Json -Depth 12 -Compress)
    $process = $singleArrayProvider.Process
    $singleArrayAcceptTask = $listener.GetContextAsync()
    if (-not $singleArrayAcceptTask.Wait(5000)) { throw 'Local HTTP stub did not receive the single-string-array argument request.' }
    $singleArrayContext = $singleArrayAcceptTask.GetAwaiter().GetResult()
    $singleArrayReader = New-Object System.IO.StreamReader($singleArrayContext.Request.InputStream, $singleArrayContext.Request.ContentEncoding)
    $null = $singleArrayReader.ReadToEnd()
    $singleArrayReader.Dispose()
    $singleArrayModelDecision = [ordered]@{ action = 'provision'; arguments = @($encodedObject) } | ConvertTo-Json -Compress
    $singleArrayResponseJson = [ordered]@{ choices = @([ordered]@{ index = 0; message = [ordered]@{ role = 'assistant'; content = $singleArrayModelDecision }; finish_reason = 'stop' }) } | ConvertTo-Json -Depth 8 -Compress
    $singleArrayResponseBytes = [System.Text.Encoding]::UTF8.GetBytes($singleArrayResponseJson)
    $singleArrayContext.Response.StatusCode = 200
    $singleArrayContext.Response.ContentType = 'application/json; charset=utf-8'
    $singleArrayContext.Response.ContentLength64 = $singleArrayResponseBytes.Length
    $singleArrayContext.Response.OutputStream.Write($singleArrayResponseBytes, 0, $singleArrayResponseBytes.Length)
    $singleArrayContext.Response.OutputStream.Close()
    if (-not $process.WaitForExit(($TimeoutSeconds + 5) * 1000)) { try { $process.Kill() } catch { }; throw 'Provider did not exit after single-string-array action arguments.' }
    $singleArrayStdout = $singleArrayProvider.StdoutTask.Result.Trim()
    $singleArrayStderr = $singleArrayProvider.StderrTask.Result.Trim()
    if ($process.ExitCode -ne 0) { throw "Provider rejected a single-element JSON-object string array (exit=$($process.ExitCode)): $singleArrayStderr" }
    $singleArrayDecision = $singleArrayStdout | ConvertFrom-Json
    $singleStringArrayArgumentsNormalized = ($singleArrayDecision.action -ceq 'provision' -and $singleArrayDecision.arguments -is [System.Management.Automation.PSCustomObject] -and [string]$singleArrayDecision.arguments.ItemViewModelId -ceq 'olives' -and [int]$singleArrayDecision.arguments.Amount -eq 4)

    $failureStep = 'normalize-nested-single-string-array-action-arguments'
    $nestedArgumentArray = [System.Array]::CreateInstance([object], 1)
    $nestedArgumentArray.SetValue([object[]]@($encodedObject), 0)
    $nestedArrayProvider = Start-ProviderProcess ($encodedArgumentsRequest | ConvertTo-Json -Depth 12 -Compress)
    $process = $nestedArrayProvider.Process
    $nestedArrayAcceptTask = $listener.GetContextAsync()
    if (-not $nestedArrayAcceptTask.Wait(5000)) { throw 'Local HTTP stub did not receive the nested-string-array argument request.' }
    $nestedArrayContext = $nestedArrayAcceptTask.GetAwaiter().GetResult()
    $nestedArrayReader = New-Object System.IO.StreamReader($nestedArrayContext.Request.InputStream, $nestedArrayContext.Request.ContentEncoding)
    $null = $nestedArrayReader.ReadToEnd()
    $nestedArrayReader.Dispose()
    $nestedArrayModelDecision = [ordered]@{ action = 'provision'; arguments = $nestedArgumentArray } | ConvertTo-Json -Compress -Depth 8
    $nestedArrayResponseJson = [ordered]@{ choices = @([ordered]@{ index = 0; message = [ordered]@{ role = 'assistant'; content = $nestedArrayModelDecision }; finish_reason = 'stop' }) } | ConvertTo-Json -Depth 8 -Compress
    $nestedArrayResponseBytes = [System.Text.Encoding]::UTF8.GetBytes($nestedArrayResponseJson)
    $nestedArrayContext.Response.StatusCode = 200
    $nestedArrayContext.Response.ContentType = 'application/json; charset=utf-8'
    $nestedArrayContext.Response.ContentLength64 = $nestedArrayResponseBytes.Length
    $nestedArrayContext.Response.OutputStream.Write($nestedArrayResponseBytes, 0, $nestedArrayResponseBytes.Length)
    $nestedArrayContext.Response.OutputStream.Close()
    if (-not $process.WaitForExit(($TimeoutSeconds + 5) * 1000)) { try { $process.Kill() } catch { }; throw 'Provider did not exit after nested-string-array action arguments.' }
    $nestedArrayStdout = $nestedArrayProvider.StdoutTask.Result.Trim()
    $nestedArrayStderr = $nestedArrayProvider.StderrTask.Result.Trim()
    if ($process.ExitCode -ne 0) { throw "Provider rejected a nested single-string-array action argument (exit=$($process.ExitCode)): $nestedArrayStderr" }
    $nestedArrayDecision = $nestedArrayStdout | ConvertFrom-Json
    $nestedStringArrayArgumentsNormalized = ($nestedArrayDecision.action -ceq 'provision' -and $nestedArrayDecision.arguments -is [System.Management.Automation.PSCustomObject] -and [string]$nestedArrayDecision.arguments.ItemViewModelId -ceq 'olives' -and [int]$nestedArrayDecision.arguments.Amount -eq 4)

    $failureStep = 'normalize-single-parameter-scalar-arguments'
    $scalarRequest = [ordered]@{
        schemaVersion = 3
        runId = 'provider-single-scalar-argument-test'
        iteration = 1
        goal = 'Wait three Campaign days in the active Native Town Wait menu.'
        recentDecisionHistory = @()
        allowedActions = @([ordered]@{ action = 'rest'; arguments = @('Days') })
        allowedControls = @()
        observation = $request.observation
        previousActionReceipt = $null
    }
    $scalarProvider = Start-ProviderProcess ($scalarRequest | ConvertTo-Json -Depth 12 -Compress)
    $process = $scalarProvider.Process
    $scalarAcceptTask = $listener.GetContextAsync()
    if (-not $scalarAcceptTask.Wait(5000)) { throw 'Local HTTP stub did not receive the single-scalar argument request.' }
    $scalarContext = $scalarAcceptTask.GetAwaiter().GetResult()
    $scalarReader = New-Object System.IO.StreamReader($scalarContext.Request.InputStream, $scalarContext.Request.ContentEncoding)
    $null = $scalarReader.ReadToEnd()
    $scalarReader.Dispose()
    $scalarModelDecision = [ordered]@{ action = 'rest'; arguments = 3 } | ConvertTo-Json -Compress
    $scalarResponseJson = [ordered]@{ choices = @([ordered]@{ index = 0; message = [ordered]@{ role = 'assistant'; content = $scalarModelDecision }; finish_reason = 'stop' }) } | ConvertTo-Json -Depth 8 -Compress
    $scalarResponseBytes = [System.Text.Encoding]::UTF8.GetBytes($scalarResponseJson)
    $scalarContext.Response.StatusCode = 200
    $scalarContext.Response.ContentType = 'application/json; charset=utf-8'
    $scalarContext.Response.ContentLength64 = $scalarResponseBytes.Length
    $scalarContext.Response.OutputStream.Write($scalarResponseBytes, 0, $scalarResponseBytes.Length)
    $scalarContext.Response.OutputStream.Close()
    if (-not $process.WaitForExit(($TimeoutSeconds + 5) * 1000)) { try { $process.Kill() } catch { }; throw 'Provider did not exit after single-scalar action arguments.' }
    $scalarStdout = $scalarProvider.StdoutTask.Result.Trim()
    $scalarStderr = $scalarProvider.StderrTask.Result.Trim()
    if ($process.ExitCode -ne 0) { throw "Provider rejected a scalar for an unambiguous one-argument action (exit=$($process.ExitCode)): $scalarStderr" }
    $scalarDecision = $scalarStdout | ConvertFrom-Json
    $singleScalarArgumentsNormalized = ($scalarDecision.action -ceq 'rest' -and [int]$scalarDecision.arguments.Days -eq 3)

    $failureStep = 'verify-local-openai-compatible-service-contract'
    $env:CHRONICLE_LLM_API_KEY = ''
    $env:CHRONICLE_LLM_MAX_TOKEN_PARAMETER = 'max_tokens'
    Remove-Item Env:CHRONICLE_LLM_THINKING_MODE -ErrorAction SilentlyContinue
    $env:CHRONICLE_LLM_REASONING_EFFORT = 'none'
    $env:CHRONICLE_LLM_TEMPERATURE = '0'
    $largeMapTargets = @(1..40 | ForEach-Object {
        [ordered]@{ id = "town_test_$_"; name = "Test settlement $_"; type = 'town'; distance = [double]$_; hostile = ($_ -gt 30); underSiege = $false }
    })
    $localRequest = [ordered]@{
        schemaVersion = 3
        runId = 'provider-large-receipt-test'
        iteration = 2
        goal = $goal
        recentDecisionHistory = @()
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

    $deepSeekBudget = New-AgentProviderBudget -ModelId 'deepseek-flash' -BaseUrl 'https://api.deepseek.com/v1' -MaxProviderCalls 20 -MaxRequestBodyBytes 10000 -MaxOutputTokensPerRequest 256
    $localTokenOnlyBudget = New-AgentProviderBudget -ModelId 'qwen3.5:4b-q4_K_M' -BaseUrl 'http://127.0.0.1:11434/v1'
    $deepSeekBudgetFingerprint = Get-AgentProviderBudgetFingerprint -Budget $deepSeekBudget
    $deepSeekBudgetRoundtrip = $deepSeekBudget | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $budgetFingerprintStableAcrossRoundtrip = (Get-AgentProviderBudgetFingerprint -Budget $deepSeekBudgetRoundtrip) -ceq $deepSeekBudgetFingerprint
    $changedBudgetProfile = $deepSeekBudget | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $changedBudgetProfile.maxEstimatedCost = [double]$changedBudgetProfile.maxEstimatedCost - 0.01
    $changedBudgetProfileDetected = (Get-AgentProviderBudgetFingerprint -Budget $changedBudgetProfile) -cne $deepSeekBudgetFingerprint
    $unknownRemoteBudgetRejected = $false
    try { $null = New-AgentProviderBudget -ModelId 'unpriced-model' -BaseUrl 'https://provider.example/v1' } catch { $unknownRemoteBudgetRejected = $_.Exception.Message -match 'No verified price profile exists' }
    $deepSeekPerRequestUpperCny = Get-AgentProviderRequestCostUpperBound -Budget $deepSeekBudget
    $deepSeekRunUpperCny = [Math]::Round($deepSeekPerRequestUpperCny * [int]$deepSeekBudget.maxProviderCalls, 8)
    $deepSeekThreeRunUpperCny = [Math]::Round($deepSeekRunUpperCny * 3, 8)
    $usageCostCheck = [ordered]@{ status = 'reported'; promptTokens = 1000; promptCacheHitTokens = 600; promptCacheMissTokens = 400; completionTokens = 100 }
    $estimatedUsageCostCny = Get-AgentProviderActualCostEstimate -Budget $deepSeekBudget -Usage $usageCostCheck
    $estimatedUsageBreakdown = Get-AgentProviderActualCostBreakdown -Budget $deepSeekBudget -Usage $usageCostCheck
    $providerBudgetMathVerified = ($deepSeekBudget.priceProfileId -ceq 'deepseek-v4.1-flash-peak-cny-upper-bound-2026-10' -and $localTokenOnlyBudget.mode -ceq 'token-only-local' -and $null -eq $localTokenOnlyBudget.maxEstimatedCost -and $unknownRemoteBudgetRejected -and $budgetFingerprintStableAcrossRoundtrip -and $changedBudgetProfileDetected -and [long]$deepSeekBudget.maxTotalInputTokens -eq 202560 -and [Math]::Abs($deepSeekRunUpperCny - 0.535296) -lt 0.000001 -and $deepSeekRunUpperCny -le [double]$deepSeekBudget.maxEstimatedCost -and $deepSeekThreeRunUpperCny -le 1.95 -and [Math]::Abs($estimatedUsageCostCny - 0.0019488) -lt 0.0000001 -and [Math]::Abs([double]$estimatedUsageBreakdown.inputCacheHitCny - 0.0000288) -lt 0.0000001 -and [Math]::Abs([double]$estimatedUsageBreakdown.inputCacheMissCny - 0.00096) -lt 0.0000001 -and [Math]::Abs([double]$estimatedUsageBreakdown.outputCny - 0.00096) -lt 0.0000001 -and $null -eq (Get-AgentProviderActualCostEstimate -Budget $deepSeekBudget -Usage ([ordered]@{ status = 'unavailable' })))

    $failureStep = 'persist-cumulative-budget-ledger-without-secret-or-prompt'
    $ledgerTestRoot = Join-Path ([IO.Path]::GetTempPath()) ('chronicle-provider-budget-ledger-' + [Guid]::NewGuid().ToString('N'))
    $ledgerTaskId = [Guid]::NewGuid().ToString('N')
    $ledgerPath = Get-AgentProviderBudgetLedgerPath -Root $ledgerTestRoot -TaskId $ledgerTaskId
    $ledgerState = New-AgentProviderBudgetState -Budget $deepSeekBudget
    $ledgerState.taskId = $ledgerTaskId
    $ledgerState.reservedProviderCalls = 1
    $ledgerState.reservedRequestBodyBytes = [long]$deepSeekBudget.maxRequestBodyBytes
    $ledgerState.reservedInputTokenUpperBound = [long]$deepSeekBudget.maxInputTokensPerRequest
    $ledgerState.reservedOutputTokens = [long]$deepSeekBudget.maxOutputTokensPerRequest
    $ledgerState.reservedCostUpperBound = Get-AgentProviderRequestCostUpperBound -Budget $deepSeekBudget
    $ledgerState.pendingProviderCall = [ordered]@{ iteration = 1; reservedUtc = [DateTime]::UtcNow.ToString('O'); costUpperBoundCny = $ledgerState.reservedCostUpperBound }
    Write-AgentProviderBudgetLedger -Path $ledgerPath -TaskId $ledgerTaskId -CampaignInstanceId 'campaign-ledger-test' -Budget $deepSeekBudget -State $ledgerState
    $ledgerRead = Read-AgentProviderBudgetLedger -Path $ledgerPath -TaskId $ledgerTaskId -CampaignInstanceId 'campaign-ledger-test' -Budget $deepSeekBudget
    $staleCheckpointBudgetState = New-AgentProviderBudgetState -Budget $deepSeekBudget
    $staleCheckpointBudgetState.taskId = $ledgerTaskId
    $mergedBudgetState = Merge-AgentProviderBudgetStates -CheckpointState $staleCheckpointBudgetState -LedgerState $ledgerRead.state -Budget $deepSeekBudget
    $ledgerChangedProfileRejected = $false
    try { $null = Read-AgentProviderBudgetLedger -Path $ledgerPath -TaskId $ledgerTaskId -CampaignInstanceId 'campaign-ledger-test' -Budget $changedBudgetProfile } catch { $ledgerChangedProfileRejected = $_.Exception.Message -match 'identity/profile mismatch' }
    $ledgerText = Get-Content -LiteralPath $ledgerPath -Raw -Encoding UTF8
    $budgetLedgerPersistsCumulativeStateAndFailsClosed = ([int]$ledgerRead.state.reservedProviderCalls -eq 1 -and [bool]$ledgerRead.state.pendingProviderCall -and [int]$mergedBudgetState.reservedProviderCalls -eq 1 -and $ledgerChangedProfileRejected -and $ledgerText -notmatch [regex]::Escape($harnessSecret) -and $ledgerText -notmatch [regex]::Escape($goal))
    if (-not $budgetLedgerPersistsCumulativeStateAndFailsClosed) { throw 'Durable budget ledger failed to retain a pending reservation, merge it over a stale checkpoint, reject a changed profile, or keep prompt/credential data out.' }
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
        schemaVersion = 3
        runId = 'provider-invalid-argument-test'
        iteration = 1
        goal = 'Submit the current Native barter offer.'
        recentDecisionHistory = @()
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

    $failureStep = 'bounded-retry-for-pre-response-connection-failure'
    $env:CHRONICLE_LLM_BASE_URL = 'http://127.0.0.1:1/v1'
    $connectionProvider = Start-ProviderProcess $requestJson
    $process = $connectionProvider.Process
    if (-not $process.WaitForExit(10000)) { try { $process.Kill() } catch { }; throw 'Provider did not stop after its bounded connection retry.' }
    $connectionStdout = $connectionProvider.StdoutTask.Result.Trim()
    $connectionStderr = $connectionProvider.StderrTask.Result.Trim()
    $connectionFailureClassified = ($process.ExitCode -ne 0 -and $connectionStdout -notmatch '"action"' -and $connectionStderr -match 'WebException \(status=(ConnectFailure|NameResolutionFailure|ProxyNameResolutionFailure); host=127\.0\.0\.1; attempt=2/2;' -and $connectionStderr -notmatch [regex]::Escape($harnessSecret))

    $failureStep = 'disable-retries-for-priced-provider'
    $paidRetryRequest = $request | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    $paidRetryRequest.providerBudget.mode = 'priced-provider'
    $paidRetryProvider = Start-ProviderProcess ($paidRetryRequest | ConvertTo-Json -Depth 12 -Compress)
    $process = $paidRetryProvider.Process
    if (-not $process.WaitForExit(10000)) { try { $process.Kill() } catch { }; throw 'Priced-provider request retried despite the cost guard.' }
    $paidRetryStdout = $paidRetryProvider.StdoutTask.Result.Trim()
    $paidRetryStderr = $paidRetryProvider.StderrTask.Result.Trim()
    $paidProviderRetryDisabled = ($process.ExitCode -ne 0 -and $paidRetryStdout -notmatch '"action"' -and $paidRetryStderr -match 'attempt=1/1' -and $paidRetryStderr -notmatch 'attempt=2/' -and $paidRetryStderr -notmatch [regex]::Escape($harnessSecret))

    $result = [ordered]@{
        ProviderKind = 'local HTTP stub; not a real model call'
        RequestGoalForwarded = $requestGoalForwarded
        RecentDecisionHistoryForwarded = $recentDecisionHistoryForwarded
        NativeArgumentPromptBindingsPresent = $nativeArgumentPromptBindingsPresent
        UnicodeObservationForwarded = $unicodeObservationForwarded
        AllowedActionCatalogForwarded = $actionCatalogForwarded
        PriorReceiptFieldPresent = ($null -eq $modelInput.previousActionReceipt)
        AuthorizationHeaderSent = $authorizationSent
        LocalCompatibleMaxTokensWithoutAuthorization = $localCompatibilityPassed
        ProviderBudgetMathAndUnknownPriceFailClosed = $providerBudgetMathVerified
        OllamaNativeRequestShapeCorrect = $nativeRequestShapeCorrect
        OllamaNativeUsageStatus = [string]$nativeDecision.providerUsage.status
        OllamaNativeTokenCounts = [ordered]@{ prompt = $nativeDecision.providerUsage.promptTokens; completion = $nativeDecision.providerUsage.completionTokens; total = $nativeDecision.providerUsage.totalTokens; consistent = $nativeDecision.providerUsage.totalTokensConsistent; finishReason = $nativeDecision.providerUsage.finishReason; protocol = $nativeDecision.providerUsage.protocol }
        OllamaNativeProtocolNormalizesUsage = $ollamaNativeUsageReceiptCorrect
        OllamaNativeProtocolChecks = $ollamaNativeUsageReceiptChecks
        OllamaNativeDecisionAction = [string]$nativeDecision.action
        TradeObservationCompactionWithinBudget = $tradeObservationCompactionVerified
        TradeObservationScope = [string]$tradeDecision.providerUsage.observationScope
        MultiDaySupplyProfileFitsRequestBudget = $supplyProfileFitsBudget
        NativeFoodQuoteFieldsRetained = $supplyReceiptRetainsActionFacts
        MultiDaySupplySystemPromptBytes = [int]$supplyDecision.providerUsage.systemPromptBytes
        MultiDaySupplyRequestBodyBytes = [int]$supplyDecision.providerUsage.requestBodyBytes
        ActionDoneAliasNormalizesToStopProposal = $doneAliasNormalizesToStop
        BudgetFingerprintSurvivesRoundtripAndDetectsChanges = ($budgetFingerprintStableAcrossRoundtrip -and $changedBudgetProfileDetected)
        DurableBudgetLedgerPersistsPendingSpend = $budgetLedgerPersistsCumulativeStateAndFailsClosed
        DeepSeekWorstCasePerRunCny = $deepSeekRunUpperCny
        DeepSeekWorstCaseThreeRunsCny = $deepSeekThreeRunUpperCny
        ProviderReportedUsageCostCny = $estimatedUsageCostCny
        ProviderReportedUsageCostBreakdown = $estimatedUsageBreakdown
        LocalReasoningEffortForwarded = $localReasoningEffortForwarded
        LocalTemperatureForwarded = $localTemperatureForwarded
        LargeMapReceiptCompacted = $localReceiptCompacted
        BaseUrlResolvedToChatCompletionsPath = $endpointPathCorrect
        RequestFormatCorrect = $payloadModeCorrect
        ProviderOutputCredentialFree = $providerOutputClean
        StructuredDecisionReturned = $decisionValidated
        UsageReceiptAccurate = $usageReceiptAccurate
        RequestBodyBudgetRejectedBeforeHttp = $requestBodyBudgetRejectedBeforeHttp
        PerRequestOutputBudgetApplied = ([int]$decision.providerUsage.maxOutputTokens -eq 128)
        BoundedObserveAgainControlValidated = $observeAgainValidated
        MissingUsageNotTreatedAsZero = $missingUsageNotZero
        ExactPositionalArgumentsNormalized = $positionalArgumentsNormalized
        StringEncodedObjectArgumentsNormalized = $stringEncodedArgumentsNormalized
        SingleStringArrayArgumentsNormalized = $singleStringArrayArgumentsNormalized
        NestedStringArrayArgumentsNormalized = $nestedStringArrayArgumentsNormalized
        SingleScalarArgumentsNormalized = $singleScalarArgumentsNormalized
        UnsupportedActionArgumentReturnsRecoverableRejection = $unsupportedActionArgumentRecoverable
        ProviderExitCode = $successfulProviderExitCode
        HttpErrorFailsClosedWithoutCredentialLeak = $httpErrorFailedClosed
        DisallowedActionFailsClosed = $invalidActionFailedClosed
        TimeoutFailsClosedWithoutCredentialLeak = $timeoutFailedClosed
        PreResponseConnectionFailureRetriesOnceAndClassifies = $connectionFailureClassified
        PaidProviderBudgetDisablesRetry = $paidProviderRetryDisabled
        Passed = ($requestGoalForwarded -and $recentDecisionHistoryForwarded -and $nativeArgumentPromptBindingsPresent -and $unicodeObservationForwarded -and $actionCatalogForwarded -and $authorizationSent -and $localCompatibilityPassed -and $providerBudgetMathVerified -and $ollamaNativeUsageReceiptCorrect -and $tradeObservationCompactionVerified -and $supplyProfileFitsBudget -and $supplyReceiptRetainsActionFacts -and $doneAliasNormalizesToStop -and $budgetLedgerPersistsCumulativeStateAndFailsClosed -and $endpointPathCorrect -and $payloadModeCorrect -and $providerOutputClean -and $decisionValidated -and $usageReceiptAccurate -and $requestBodyBudgetRejectedBeforeHttp -and $observeAgainValidated -and $missingUsageNotZero -and $positionalArgumentsNormalized -and $stringEncodedArgumentsNormalized -and $singleStringArrayArgumentsNormalized -and $nestedStringArrayArgumentsNormalized -and $singleScalarArgumentsNormalized -and $invalidActionFailedClosed -and $unsupportedActionArgumentRecoverable -and $httpErrorFailedClosed -and $timeoutFailedClosed -and $connectionFailureClassified -and $paidProviderRetryDisabled)
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
    if ($ledgerTestRoot -and (Test-Path -LiteralPath $ledgerTestRoot -PathType Container)) {
        $resolvedLedgerTestRoot = [IO.Path]::GetFullPath($ledgerTestRoot)
        $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        if (-not $resolvedLedgerTestRoot.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or -not (Split-Path -Leaf $resolvedLedgerTestRoot).StartsWith('chronicle-provider-budget-ledger-',[StringComparison]::Ordinal)) { throw 'Provider budget test cleanup target escaped its exact temporary ledger directory.' }
        Remove-Item -LiteralPath $resolvedLedgerTestRoot -Recurse -Force
    }
    if ($null -eq $priorBaseUrl) { Remove-Item Env:CHRONICLE_LLM_BASE_URL -ErrorAction SilentlyContinue } else { $env:CHRONICLE_LLM_BASE_URL = $priorBaseUrl }
    if ($null -eq $priorModel) { Remove-Item Env:CHRONICLE_LLM_MODEL -ErrorAction SilentlyContinue } else { $env:CHRONICLE_LLM_MODEL = $priorModel }
    if ($null -eq $priorApiKey) { Remove-Item Env:CHRONICLE_LLM_API_KEY -ErrorAction SilentlyContinue } else { $env:CHRONICLE_LLM_API_KEY = $priorApiKey }
    if ($null -eq $priorTimeout) { Remove-Item Env:CHRONICLE_LLM_TIMEOUT_SECONDS -ErrorAction SilentlyContinue } else { $env:CHRONICLE_LLM_TIMEOUT_SECONDS = $priorTimeout }
    if ($null -eq $priorTokens) { Remove-Item Env:CHRONICLE_LLM_MAX_TOKENS -ErrorAction SilentlyContinue } else { $env:CHRONICLE_LLM_MAX_TOKENS = $priorTokens }
    if ($null -eq $priorTokenParameter) { Remove-Item Env:CHRONICLE_LLM_MAX_TOKEN_PARAMETER -ErrorAction SilentlyContinue } else { $env:CHRONICLE_LLM_MAX_TOKEN_PARAMETER = $priorTokenParameter }
    if ($null -eq $priorReasoningEffort) { Remove-Item Env:CHRONICLE_LLM_REASONING_EFFORT -ErrorAction SilentlyContinue } else { $env:CHRONICLE_LLM_REASONING_EFFORT = $priorReasoningEffort }
    if ($null -eq $priorThinkingMode) { Remove-Item Env:CHRONICLE_LLM_THINKING_MODE -ErrorAction SilentlyContinue } else { $env:CHRONICLE_LLM_THINKING_MODE = $priorThinkingMode }
    if ($null -eq $priorTemperature) { Remove-Item Env:CHRONICLE_LLM_TEMPERATURE -ErrorAction SilentlyContinue } else { $env:CHRONICLE_LLM_TEMPERATURE = $priorTemperature }
    if ($null -eq $priorProtocol) { Remove-Item Env:CHRONICLE_LLM_PROTOCOL -ErrorAction SilentlyContinue } else { $env:CHRONICLE_LLM_PROTOCOL = $priorProtocol }
    if ($null -eq $priorHarnessProviderMode) { Remove-Item Env:CHRONICLE_HARNESS_PROVIDER_MODE -ErrorAction SilentlyContinue } else { $env:CHRONICLE_HARNESS_PROVIDER_MODE = $priorHarnessProviderMode }
}
