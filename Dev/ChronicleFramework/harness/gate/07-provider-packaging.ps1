#Requires -Version 7.0

# Provider packaging: tokenizer payload, pinned package lock and provider profile sources.
# Sources asserted here: AgentProviderConfigurationValidator.cs, ChronicleAgentHost.csproj, packages.lock.json, AgentProviderProfile.cs, ProviderContractSelfTest.cs, OllamaNativeProvider.cs, Program.cs, Test-AgentHostProvider.ps1, AgentHostSupplyLoop.cs

$providerValidatorSource = Get-Content (Join-Path $modRoot 'AgentProviderConfigurationValidator.cs') -Raw -Encoding UTF8
$agentHostProjectSource = Get-Content (Join-Path $agentHostRoot 'ChronicleAgentHost.csproj') -Raw -Encoding UTF8
if ($agentHostProjectSource -notmatch '<PackageReference Include="Microsoft\.ML\.Tokenizers" Version="\[2\.0\.1\]"' -or
    $agentHostProjectSource -notmatch '<RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>' -or
    $agentHostProjectSource -notmatch '<RuntimeIdentifiers>win-x64</RuntimeIdentifiers>' -or
    $agentHostProjectSource -notmatch 'CopyToPublishDirectory="PreserveNewest"' -or
    $agentHostProjectSource -notmatch 'deepseek_v4_tokenizer\.zip' -or
    $agentHostProjectSource -notmatch 'DeepSeekV4Tokenizer-LICENSE\.txt' -or
    $agentHostProjectSource -notmatch 'Resources\\\*\.txt') {
    throw 'The Agent Host must ship the pinned, MIT-noticed DeepSeek tokenizer data and its matching Microsoft tokenizer package.'
}
$tokenizerLockPath = Join-Path $agentHostRoot 'packages.lock.json'
if (-not (Test-Path -LiteralPath $tokenizerLockPath -PathType Leaf)) { throw 'The Agent Host tokenizer package lock file is missing.' }
$tokenizerLock = Get-Content -LiteralPath $tokenizerLockPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$tokenizerLock.dependencies.'net8.0'.'Microsoft.ML.Tokenizers'.resolved -ne '2.0.1' -or
    [string]$tokenizerLock.dependencies.'net8.0'.'Google.Protobuf'.resolved -ne '3.30.2' -or
    $null -eq $tokenizerLock.dependencies.'net8.0/win-x64') {
    throw 'The Agent Host package lock must pin Microsoft.ML.Tokenizers 2.0.1 and its reviewed Google.Protobuf transitive dependency.'
}
$providerProfileSource = Get-Content (Join-Path $agentHostRoot 'AgentProviderProfile.cs') -Raw -Encoding UTF8
$providerProfileTestSource = Get-Content (Join-Path $agentHostRoot 'ProviderContractSelfTest.cs') -Raw -Encoding UTF8
$providerHostSource = Get-Content (Join-Path $agentHostRoot 'OllamaNativeProvider.cs') -Raw -Encoding UTF8
$providerProgramSource = Get-Content (Join-Path $agentHostRoot 'Program.cs') -Raw -Encoding UTF8
$providerSmokeSource = Get-Content (Join-Path $stageRoot 'Test-AgentHostProvider.ps1') -Raw -Encoding UTF8
$supplyHostSource = Get-Content (Join-Path $agentHostRoot 'AgentHostSupplyLoop.cs') -Raw -Encoding UTF8
$sourceModuleManifest = Get-Content $sourceManifestPath -Raw -Encoding UTF8
if ($projectFile -notmatch 'Reference Include="MCMv5"' -or $projectFile -notmatch 'Reference Include="0Harmony"' -or
    $sourceModuleManifest -notmatch 'DependedModule Id="Bannerlord\.Harmony" DependentVersion="[^"]+" Optional="false"' -or
    $sourceModuleManifest -notmatch 'DependedModule Id="Bannerlord\.ButterLib" DependentVersion="[^"]+" Optional="false"' -or
    $sourceModuleManifest -notmatch 'DependedModule Id="Bannerlord\.UIExtenderEx" DependentVersion="[^"]+" Optional="false"' -or
    $sourceModuleManifest -notmatch 'DependedModule Id="Bannerlord\.MBOptionScreen" DependentVersion="[^"]+" Optional="false"' -or
    $sourceModuleManifest -notmatch 'DependedModule Id="Native" DependentVersion="[^"]+" Optional="false"' -or
    $sourceModuleManifest -notmatch 'DependedModule Id="SandBoxCore" DependentVersion="[^"]+" Optional="false"' -or
    $sourceModuleManifest -notmatch 'DependedModule Id="SandBox" DependentVersion="[^"]+" Optional="false"' -or
    $providerSettingsSource -notmatch 'AttributeGlobalSettings<ChronicleAgentProviderSettings>' -or $providerSettingsSource -notmatch 'FormatType => "json"' -or
    $providerSettingsSource -notmatch 'OllamaBaseUrl' -or $providerSettingsSource -notmatch 'ModelId' -or
    $providerSettingsSource -notmatch 'api.deepseek.com/v1' -or $providerSettingsSource -notmatch 'deepseek-flash' -or
    $providerSettingsSource -notmatch 'OpenAI 兼容服务地址' -or $providerSettingsSource -notmatch 'CHRONICLE_LLM_API_KEY' -or
    $providerSettingsSource -notmatch 'EnvironmentVariableTarget.User' -or $providerSettingsSource -notmatch 'OutputMode' -or $providerSettingsSource -notmatch 'DeepSeekRunCostLimitCny' -or
    $providerSettingsSource -notmatch 'SettingPropertyButton' -or $providerSettingsSource -notmatch 'AgentProviderConfigurationValidator\.GetErrorCode' -or
    $providerSettingsSource -notmatch 'AgentProviderConfigurationValidator\.SelectApiKey' -or
    $providerSettingsSource -notmatch 'MBInformationManager\.AddQuickInformation' -or
    $providerSettingsSource -notmatch '(?s)public Action ValidateLocalConfiguration\s*\{\s*get => ShowConfigurationValidation;\s*set \{\s*\}\s*\}' -or
    $providerSettingsSource -notmatch 'CampaignGoal' -or $providerSettingsSource -notmatch 'StartAgent' -or $providerSettingsSource -notmatch 'StopAgent' -or $providerSettingsSource -notmatch 'ViewAgentStatus' -or
    $agentHostRuntimeControllerSource -notmatch 'ChronicleAgentHost\.exe' -or $agentHostRuntimeControllerSource -notmatch 'ResolveModuleRoot' -or
    $agentHostRuntimeControllerSource -notmatch 'RequestStart' -or $agentHostRuntimeControllerSource -notmatch 'RequestStop' -or $agentHostRuntimeControllerSource -notmatch 'host-stop-requested' -or
    $agentHostRuntimeControllerSource -notmatch 'Kill\(\)' -or $agentHostRuntimeControllerSource -notmatch 'IsOwnedLiveProcess' -or
    $agentHostRuntimeControllerSource -notmatch 'CHRONICLE_HARNESS_AGENT_AUTO_STOP_AFTER_MS' -or
    $agentHostRuntimeControllerSource -notmatch 'providerIsRemote' -or $agentHostRuntimeControllerSource -notmatch 'ResolveApiKey\(settings\.OllamaBaseUrl\)' -or $agentHostRuntimeControllerSource -notmatch 'EnvironmentVariableTarget.User' -or
    $agentHostRuntimeControllerSource -notmatch 'settings.OutputMode' -or $agentHostRuntimeControllerSource -notmatch 'settings.DeepSeekRunCostLimitCny' -or
    $agentHostLifecycleEvaluationSource -notmatch 'AgentHostPackage\.log' -or $agentHostLifecycleEvaluationSource -notmatch 'agent-host-process-started' -or
    $agentHostLifecycleEvaluationSource -notmatch 'agent-host-process-exit' -or $agentHostLifecycleEvaluationSource -notmatch 'FixtureUnchanged' -or
    $providerValidatorSource -notmatch 'uri.Scheme == "http" && !uri.IsLoopback' -or $providerValidatorSource -notmatch 'SelectApiKey' -or $agentHostProjectSource -notmatch 'AgentProviderConfigurationValidator\.cs' -or
    $providerProfileSource -notmatch 'AgentProviderConfigurationValidator\.GetErrorCode' -or
    $providerProfileTestSource -notmatch 'mcm-profile-accepts-generic-https-openai-compatible-provider' -or
    $providerProfileTestSource -notmatch 'deepseek-auto-profile-selects-bounded-non-thinking-strict-tool-calls' -or
    $providerProfileTestSource -notmatch 'provider-credential-selection-is-endpoint-scoped' -or
    $providerProfileTestSource -notmatch 'mcm-profile-rejects-insecure-remote-http' -or
    $providerProfileTestSource -notmatch 'mcm-profile-rejects-nonpositive-deepseek-run-budget' -or
    $providerProfileTestSource -notmatch 'deepseek-auto-profile-selects-bounded-non-thinking-strict-tool-calls' -or
    $providerProfileTestSource -notmatch 'mcm-global-profile-tolerates-legacy-and-unknown-fields' -or
    $providerProfileTestSource -notmatch 'provider-profile-reads-without-migrating-user-file' -or
    $providerProfileTestSource -notmatch 'provider-profile-error-path-mutated-file' -or
    $providerProfileTestSource -notmatch 'freellmapi-bearer-auth-available-model-preflight-and-routed-model-evidence' -or
    $providerProfileTestSource -notmatch 'freellmapi-profile-uses-512-token-and-one-http-request-per-decision-default' -or
    $providerProfileTestSource -notmatch 'freellmapi-model-without-json-or-tool-support-fails-before-inference' -or
    $providerProfileTestSource -notmatch 'freellmapi-explicit-json-object-allows-prompt-only-output-with-local-action-validation' -or
    $providerHostSource -notmatch '_usePromptOnlyJsonMode' -or $providerHostSource -notmatch 'json_object_prompt_only' -or
    $providerProfileTestSource -notmatch 'provider-action-rationale-is-optional-and-native-catalog-still-gates' -or
    $providerHostSource -notmatch 'SelectApiKey' -or $providerHostSource -notmatch '\["anyOf"\]' -or $providerHostSource -match '\["oneOf"\]' -or
    $providerProfileTestSource -notmatch 'village-tools-prompt-uses-exact-native-action-id' -or
    $providerProfileTestSource -notmatch 'conversation is already open: never talk to that hero again' -or
    $providerProfileTestSource -notmatch 'only before a conversation is open, and only if talkToSettlementHero is currently listed' -or
    $providerProfileTestSource -notmatch 'Once the Journal confirms the Quest is active and tools are still owed, leave the Village and travel to a Town' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'village-tools-active-quest-dialogue-allows-leave-only-before-tools-obtained' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'village-tools-active-quest-giver-reopens-only-after-tools-and-inventory-baseline' -or
    $providerProfileTestSource -notmatch 'freellmapi-http-error-keeps-safe-route-fallback-headers-without-response-body' -or
    $providerProfileTestSource -notmatch 'freellmapi-json-schema-provider-rejection-falls-back-to-validated-json-object' -or
    $providerProfileTestSource -notmatch 'freellmapi-json-object-fallback-recognizes-schema-rejection-or-format-ignored-502-only' -or
    $providerProfileTestSource -notmatch 'freellmapi-format-ignored-502-falls-back-once-to-locally-normalized-native-action' -or
    $agentHostProviderSource -notmatch 'format_ignored' -or
    $providerProfileTestSource -notmatch 'freellmapi-transient-upstream-502-retried-once-before-native-action' -or
    $providerProfileTestSource -notmatch 'freellmapi-429-honors-bounded-retry-after-before-native-action' -or
    $providerProfileTestSource -notmatch 'freellmapi-exhaustion-body-eta-allows-one-bounded-retry' -or
    $providerProfileTestSource -notmatch 'freellmapi-exhaustion-body-beyond-deadline-fails-fast-with-safe-diagnostic' -or
    $providerProfileTestSource -notmatch 'freellmapi-429-allows-three-explicit-waits-then-fails-closed' -or
    $providerProfileTestSource -notmatch 'freellmapi-changing-retry-after-honors-later-in-deadline-window' -or
    $providerProfileTestSource -notmatch 'freellmapi-reclassifies-429-after-transient-upstream-retry' -or
    $providerProfileTestSource -notmatch 'freellmapi-429-reports-over-bound-retry-as-ineligible' -or
    $providerProfileTestSource -notmatch 'freellmapi-retry-after-delay-respects-overall-provider-timeout' -or
    $providerSmokeSource -notmatch 'function Resolve-ProviderSmokeTimeoutSeconds' -or
    $providerSmokeSource -notmatch 'Resolve-ProviderSmokeTimeoutSeconds \$null\) -ne 360' -or
    $providerSmokeSource -notmatch '\[ValidateRange\(64,2048\)\]\[int\]\$MaxOutputTokens = 128' -or
    $providerSmokeSource -notmatch '\$env:CHRONICLE_LLM_MAX_TOKENS = \[string\]\$MaxOutputTokens' -or
    $harnessScript -notmatch '\[ValidateRange\(64,2048\)\]\[int\]\$ProviderSmokeMaxOutputTokens = 128' -or
    $harnessScript -notmatch '\$providerArguments = @\(' -or
    $harnessScript -notmatch "'-MaxOutputTokens', \[string\]\`$ProviderSmokeMaxOutputTokens" -or
    $providerSmokeSource -notmatch 'EffectiveMaxOutputTokens = \[int\]\$env:CHRONICLE_LLM_MAX_TOKENS' -or
    $providerSmokeSource -match '\[ref\]\$effectiveTimeout' -or
    $providerProfileTestSource -notmatch 'freellmapi-429-accepts-observed-315-second-retry-and-fails-closed-outside-bounds' -or
    $providerProfileTestSource -notmatch 'freellmapi-two-transient-upstream-retries-bounded-before-native-action' -or
    $providerProfileTestSource -notmatch 'freellmapi-schema-fallback-then-transient-upstream-retry-is-bounded' -or
    $providerProfileTestSource -notmatch 'observedTokenParameters' -or
    $providerProfileTestSource -notmatch 'freellmapi-mistral-uses-validated-json-object-compatibility-mode' -or
    $providerProfileTestSource -notmatch 'freellmapi-ovh-model-rate-window-is-route-specific' -or
    $providerProfileTestSource -notmatch 'openrouter-free-model-rate-window-stays-under-published-20-rpm' -or
    $providerHostSource -notmatch 'TimeSpan.FromMilliseconds\(3100\)' -or
    $providerProfileTestSource -notmatch 'max_tokens' -or
    $providerProfileTestSource -notmatch 'mistralRequestShapeValid' -or
    $providerHostSource -notmatch 'IsMistralSmall32' -or $providerHostSource -notmatch 'GetMinimumRequestInterval' -or $providerHostSource -notmatch 'WaitForProviderRateWindowAsync' -or $providerHostSource -notmatch 'ShouldRetryTransientFreeLlmApiFailure' -or $providerHostSource -notmatch 'GetBoundedRateLimitRetryAfter' -or $providerHostSource -notmatch 'transientProviderRetriesUsed' -or $providerHostSource -notmatch 'retryDelaySeconds = transientProviderRetriesUsed == 0 \? 5 : 15' -or $providerHostSource -notmatch 'retryAfter=' -or $providerHostSource -notmatch 'failedRoute.Contains\("ovh/Mistral-Small"' -or $providerHostSource -notmatch 'payload.Remove\("max_completion_tokens"\)' -or $providerHostSource -notmatch 'ReadIntegerEnvironment\("CHRONICLE_LLM_MAX_TOKENS", 256, 64, 4096\)' -or
    $providerProfileTestSource -notmatch 'freellmapi-missing-key-fails-before-network-request' -or
    $providerSmokeSource -notmatch 'goalScopeClassificationRequired = \$true' -or
    $providerSmokeSource -notmatch 'goalScopeContract = ''native-campaign-goal-classification-v1''' -or
    $providerSmokeSource -notmatch 'No goal-specific game action has run yet' -or
    $providerSmokeSource -notmatch 'supportedVillageToolsQuestGoal' -or
    $providerSmokeSource -notmatch 'NativeCommands = 0' -or
    $providerSmokeSource -notmatch 'GatewayStartedByHarness = if \(\$freeLlmApiProfile\)' -or
    $providerSmokeSource -notmatch 'LocalProxyBootstrapApplied = if \(\$freeLlmApiProfile\)' -or
    $providerSmokeSource -notmatch 'DecisionClassification = \[string\]\$result.decision.goalClassification' -or
    $providerProgramSource -notmatch 'AgentHostDecisionCycle.DecideCampaignAsync' -or
    $providerSmokeSource -notmatch 'ResponseFormatMode = \[string\]\$result\.responseFormatMode' -or
    $providerSmokeSource -notmatch 'ProviderErrorParam = if \(\$providerFailure\)' -or
    $providerSmokeSource -notmatch 'ProviderDshUpstreamCode = if \(\$providerFailure\)' -or
    $providerSmokeSource -notmatch 'ProviderResponseContentKind = if \(\$providerFailure\)' -or
    $providerSmokeSource -notmatch 'ProviderResponseCompletionTokens = if \(\$providerFailure\)' -or
    $providerProgramSource -notmatch 'BuildSafeProviderFailureDetails' -or
    $providerProfileTestSource -notmatch 'provider-http-failure-cli-output-preserves-safe-error-fields-without-body' -or
    $providerProfileTestSource -notmatch 'dsh-workbuddy-risk-blocked-preserves-allowlisted-upstream-code-without-body-or-account-label' -or
    $freeLlmApiProfileSource -notmatch 'Get-DshXdPoolFreeModelStatus' -or
    $freeLlmApiProfileSource -notmatch 'current-profile-plus-recent-runtime-receipt' -or
    $providerSmokeSource -notmatch 'xdpool/hy4flash-free' -or
    $harnessScript -notmatch 'xdpool/hy4flash-free' -or
    $providerSmokeSource -notmatch 'ProviderSmokeFailure\.json' -or
    $providerHostSource -notmatch 'FREELLMAPI_API_KEY' -or $providerHostSource -notmatch 'CHRONICLE_LLM_API_KEY' -or
    $providerHostSource -notmatch 'X-Routed-Via' -or
    $providerProfileTestSource -notmatch 'mcm-global-profile-tolerates-legacy-and-unknown-fields' -or
    $providerProfileTestSource -notmatch 'provider-profile-reads-without-migrating-user-file' -or
    $providerProfileTestSource -notmatch 'provider-profile-error-path-mutated-file' -or
    $providerProfileTestSource -notmatch 'host-loads-authorized-harness-mcm-profile' -or
    $providerProfileTestSource -notmatch 'host-rejects-profile-outside-harness-root' -or
    $providerProfileSource -notmatch 'Configs.*ModSettings.*Global.*ChronicleFramework.*ChronicleAgentSettings\.json' -or
    $providerHostSource -notmatch 'FromConfiguredProfile' -or
    $supplyHostSource -notmatch 'OllamaNativeProvider\.FromConfiguredProfile') {
    throw 'Player model settings must expose an OpenAI-compatible endpoint with HTTPS-only remote transport, process/user-scoped secret lookup, and a matching Agent Host profile outside Harness overrides.'
}
if ($providerSmokeSource -notmatch '\$isOpenRouterFreeRouter' -or
    $providerSmokeSource -notmatch 'openrouter/free' -or
    $providerSmokeSource -notmatch 'supported-establish-your-clan') {
    throw 'The OpenRouter free router smoke must exercise the product EYC scope rather than stand in for an unrelated arrival goal.'
}
if ($providerHostSource -notmatch 'defaultTimeoutSeconds = nativeOllama \? 60 : 360' -or
    $providerHostSource -notmatch 'maximumTimeoutSeconds = nativeOllama \? 240 : 360' -or
    $providerHostSource -notmatch 'ReadIntegerEnvironment\("CHRONICLE_LLM_TIMEOUT_SECONDS", defaultTimeoutSeconds, 5, maximumTimeoutSeconds\)' -or
    $providerHostSource -notmatch 'ReadIntegerEnvironment\("CHRONICLE_LLM_TIMEOUT_SECONDS", 360, 5, 360\)' -or
    $providerHostSource -notmatch 'maximumRateLimitRetries = retryHint.Source == "body-exhaustion" \|\| !IsFreeLlmApi\(_settings\.Endpoint\) \? 1 : 3' -or
    $providerHostSource -notmatch 'ReadRateLimitRetryHintAsync' -or
    $providerHostSource -notmatch 'MaxRateLimitErrorBytes = 16 \* 1024' -or
    $providerHostSource -notmatch 'MinimumRateLimitRetryRequestBudget = TimeSpan.FromSeconds\(5\)' -or
    $providerHostSource -notmatch 'TimeSpan.FromSeconds\(360\)' -or
    $providerProfileTestSource -notmatch '315' -or
    $providerProfileTestSource -notmatch '361') {
    throw 'FreeLLMAPI recovery must permit the observed 315-second Retry-After inside a 360-second Host request deadline and reject waits above the bound.'
}
if ($agentHostCampaignLoopSource -notmatch 'ReadIntEnvironment\("CHRONICLE_NATIVE_MAILBOX_TIMEOUT_SECONDS", 180, 5, 240\)' -or
    $agentHostSupplyLoopSource -notmatch 'ReadIntEnvironment\("CHRONICLE_NATIVE_MAILBOX_TIMEOUT_SECONDS", 180, 5, 240\)') {
    throw 'Campaign and Supply Native mailbox waits must stay independently bounded and must not inherit the longer FreeLLMAPI model retry deadline.'
}
