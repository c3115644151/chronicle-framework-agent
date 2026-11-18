using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal sealed class OllamaNativeProvider : IAgentHostDecisionProvider
{
    private const int MaxRequestBytes = 512 * 1024;
    private const int MaxResponseBytes = 1024 * 1024;
    private const int MaxRateLimitErrorBytes = 16 * 1024;
    private static readonly TimeSpan MinimumRateLimitRetryRequestBudget = TimeSpan.FromSeconds(5);
    private static readonly JsonSerializerOptions JsonOptions = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
    private static readonly HashSet<string> FreeLlmApiRouterStrategies = new(StringComparer.OrdinalIgnoreCase)
    {
        "auto:smart", "auto:fast", "auto:cheap", "auto:reliable", "auto:balanced",
        "auto:fastest", "auto:speed", "auto:smartest", "auto:cheapest", "auto:budget"
    };
    private readonly OllamaProviderSettings _settings;
    private readonly HttpClient _client;
    private readonly bool _ownsClient;
    private readonly string _proxySelectionSource;
    private readonly string? _proxyEndpointHostPort;
    private int _availableModelCount;
    private DateTimeOffset _lastProviderRequestUtc;
    private string? _lastProviderRoute;
    private bool _useRequiredToolCallStrategy;
    private bool _supportsParallelToolCalls;
    private bool _supportsReasoningEffort;
    private bool _usePromptOnlyJsonMode;
    private double _reservedDeepSeekCostCny;
    private double _actualDeepSeekCostEstimateCny;
    private long _deepSeekPromptCacheHitTokens;
    private long _deepSeekPromptCacheMissTokens;
    private const double DeepSeekInputPeakCnyPerMillion = 2.4d;
    private const double DeepSeekOutputPeakCnyPerMillion = 9.6d;
    internal string ModelId => _settings.Model;
    internal string ProviderHost => _settings.Endpoint.Host;
    internal string StructuredOutputStrategy => _useRequiredToolCallStrategy ? "required_tool_call" :
        _settings.OutputMode == "json_object" ? "json_object" : "json_schema";
    internal string ProxySelectionSource => _proxySelectionSource;
    internal string? ProxyEndpointHostPort => _proxyEndpointHostPort;
    internal int AvailableModelCount => _availableModelCount;
    internal int MaxOutputTokens => _settings.MaxOutputTokens;
    internal int MaxHttpRequestsPerDecision => _settings.MaxHttpRequestsPerDecision;
    internal string OutputMode => _settings.OutputMode;
    internal bool? ThinkingMode => _settings.Thinking;
    internal double? ReservedCostUpperBoundCny => IsDeepSeekApi(_settings.Endpoint) ? _reservedDeepSeekCostCny : null;
    internal double? ActualCostEstimateCny => IsDeepSeekApi(_settings.Endpoint) ? _actualDeepSeekCostEstimateCny : null;
    internal double? MaxEstimatedRunCostCny => IsDeepSeekApi(_settings.Endpoint) ? _settings.MaxEstimatedRunCostCny : null;
    internal long? PromptCacheHitTokens => IsDeepSeekApi(_settings.Endpoint) ? _deepSeekPromptCacheHitTokens : null;
    internal long? PromptCacheMissTokens => IsDeepSeekApi(_settings.Endpoint) ? _deepSeekPromptCacheMissTokens : null;
    internal string ConfigurationSource { get; }

    string IAgentHostDecisionProvider.ModelId => ModelId;
    string IAgentHostDecisionProvider.ConfigurationSource => ConfigurationSource;

    internal OllamaNativeProvider(OllamaProviderSettings settings, HttpClient? client = null, string configurationSource = "direct")
    {
        _settings = settings with { MaxTokenParameter = ResolveMaxTokenParameter(settings.Model, settings.MaxTokenParameter) };
        if (client is null)
            (_client, _proxySelectionSource, _proxyEndpointHostPort) = CreateDefaultHttpClient(_settings);
        else
        {
            _client = client;
            _proxySelectionSource = "injected-http-client";
            _proxyEndpointHostPort = null;
        }
        _ownsClient = client is null;
        ConfigurationSource = configurationSource;
        _useRequiredToolCallStrategy = string.Equals(settings.OutputMode, "required_tool_call", StringComparison.Ordinal);
    }

    private static (HttpClient Client, string ProxySelectionSource, string? ProxyEndpointHostPort) CreateDefaultHttpClient(OllamaProviderSettings settings)
    {
        var processHttps = ReadProxyEnvironment("HTTPS_PROXY", EnvironmentVariableTarget.Process);
        var userHttps = ReadProxyEnvironment("HTTPS_PROXY", EnvironmentVariableTarget.User);
        var processHttp = ReadProxyEnvironment("HTTP_PROXY", EnvironmentVariableTarget.Process);
        var userHttp = ReadProxyEnvironment("HTTP_PROXY", EnvironmentVariableTarget.User);
        var processAll = ReadProxyEnvironment("ALL_PROXY", EnvironmentVariableTarget.Process);
        var userAll = ReadProxyEnvironment("ALL_PROXY", EnvironmentVariableTarget.User);
        var processNoProxy = ReadProxyEnvironment("NO_PROXY", EnvironmentVariableTarget.Process);
        var userNoProxy = ReadProxyEnvironment("NO_PROXY", EnvironmentVariableTarget.User);
        var noProxy = processNoProxy ?? userNoProxy;
        var hasConfiguredProxy = !string.IsNullOrWhiteSpace(processHttps ?? userHttps) ||
            !string.IsNullOrWhiteSpace(processHttp ?? userHttp) || !string.IsNullOrWhiteSpace(processAll ?? userAll);
        var localProxyAvailable = !settings.Endpoint.IsLoopback && !hasConfiguredProxy &&
            !ProviderProxySelection.IsNoProxyMatch(settings.Endpoint.Host, noProxy) && ProviderProxySelection.IsLocalProxyListenerAvailable();
        var proxyUrl = ProviderProxySelection.SelectProxyUrl(settings.Endpoint,
            processHttps ?? userHttps, processHttp ?? userHttp, processAll ?? userAll,
            localProxyAvailable, noProxy);
        if (string.IsNullOrWhiteSpace(proxyUrl))
        {
            var source = ReadProxySelectionSourceOverride() ?? (settings.Endpoint.IsLoopback ? "loopback-or-system-default" :
                ProviderProxySelection.IsNoProxyMatch(settings.Endpoint.Host, noProxy) ? "no-proxy-bypass" : "system-default");
            return (new HttpClient { Timeout = settings.Timeout }, source, null);
        }
        if (!Uri.TryCreate(proxyUrl, UriKind.Absolute, out var proxyUri) || proxyUri.Scheme is not ("http" or "https"))
            throw new AgentHostException("provider-proxy-invalid", "The configured provider proxy must be an absolute HTTP or HTTPS URL.");
        var handler = new HttpClientHandler
        {
            UseProxy = true,
            Proxy = new WebProxy(proxyUri) { BypassProxyOnLocal = true }
        };
        var selectedByEnvironment = !string.IsNullOrWhiteSpace(processHttps) || !string.IsNullOrWhiteSpace(userHttps) ||
            !string.IsNullOrWhiteSpace(processHttp) || !string.IsNullOrWhiteSpace(userHttp) ||
            !string.IsNullOrWhiteSpace(processAll) || !string.IsNullOrWhiteSpace(userAll);
        var proxySource = ReadProxySelectionSourceOverride() ?? (selectedByEnvironment ? "configured-proxy-environment" : "detected-local-listener-7890");
        return (new HttpClient(handler) { Timeout = settings.Timeout }, proxySource, proxyUri.Host + ":" + proxyUri.Port.ToString(CultureInfo.InvariantCulture));
    }

    private static string? ReadProxySelectionSourceOverride()
    {
        var source = Environment.GetEnvironmentVariable("CHRONICLE_LLM_PROXY_SELECTION_SOURCE");
        return source is "https-proxy-environment" or "http-proxy-environment" or "all-proxy-environment" or
            "local-listener" or "no-proxy-bypass" or "system-default" ? source : null;
    }

    private static string? ReadProxyEnvironment(string name, EnvironmentVariableTarget target)
    {
        var value = Environment.GetEnvironmentVariable(name, target);
        return string.IsNullOrWhiteSpace(value) ? null : value.Trim();
    }

    internal static OllamaNativeProvider FromEnvironment()
    {
        var protocol = Environment.GetEnvironmentVariable("CHRONICLE_LLM_PROTOCOL");
        if (string.IsNullOrWhiteSpace(protocol)) protocol = "openai-compatible";
        var nativeOllama = string.Equals(protocol, "ollama-native", StringComparison.OrdinalIgnoreCase);
        if (!nativeOllama && !string.Equals(protocol, "openai-compatible", StringComparison.OrdinalIgnoreCase))
            throw new AgentHostException("provider-protocol-unsupported", "The configured provider protocol is not supported.");

        var baseUrl = Environment.GetEnvironmentVariable("CHRONICLE_LLM_BASE_URL");
        var model = Environment.GetEnvironmentVariable("CHRONICLE_LLM_MODEL");
        if (string.IsNullOrWhiteSpace(baseUrl) || string.IsNullOrWhiteSpace(model))
            throw new AgentHostException("provider-configuration-missing", "Provider URL and model ID configuration are required.");
        if (model.Length > 160)
            throw new AgentHostException("provider-model-invalid", "Configured model identifier is too long.");

        if (!Uri.TryCreate(baseUrl, UriKind.Absolute, out var baseUri) || baseUri.Scheme is not ("http" or "https") ||
            (baseUri.Scheme == "http" && !baseUri.IsLoopback) || !string.IsNullOrEmpty(baseUri.UserInfo) ||
            !string.IsNullOrEmpty(baseUri.Query) || !string.IsNullOrEmpty(baseUri.Fragment))
            throw new AgentHostException("provider-endpoint-invalid", "The provider URL must use HTTPS (HTTP is allowed only on loopback) and cannot include credentials, query, or fragment.");
        var endpointBuilder = new UriBuilder(baseUri);
        endpointBuilder.Path = nativeOllama ? "/api/chat" : endpointBuilder.Path.TrimEnd('/') + "/chat/completions";
        var endpoint = endpointBuilder.Uri;

        var defaultTimeoutSeconds = nativeOllama ? 60 : 360;
        var maximumTimeoutSeconds = nativeOllama ? 240 : 360;
        var timeoutSeconds = ReadIntegerEnvironment("CHRONICLE_LLM_TIMEOUT_SECONDS", defaultTimeoutSeconds, 5, maximumTimeoutSeconds);
        var maxOutputTokens = ReadIntegerEnvironment("CHRONICLE_LLM_MAX_TOKENS", 256, 64, 4096);
        var maxHttpRequestsDefault = IsFreeLlmApi(endpoint) ? 1 : 8;
        var maxHttpRequestsPerDecision = ReadIntegerEnvironment("CHRONICLE_LLM_MAX_HTTP_REQUESTS_PER_DECISION", maxHttpRequestsDefault, 1, 8);
        var temperature = ReadOptionalDoubleEnvironment("CHRONICLE_LLM_TEMPERATURE", 0d, 2d);
        var thinkingMode = Environment.GetEnvironmentVariable("CHRONICLE_LLM_THINKING_MODE");
        bool? thinking = thinkingMode switch
        {
            null or "" => null,
            "enabled" => true,
            "disabled" => false,
            _ => throw new AgentHostException("provider-thinking-mode-invalid", "Thinking mode must be enabled, disabled, or omitted.")
        };
        var reasoningEffort = Environment.GetEnvironmentVariable("CHRONICLE_LLM_REASONING_EFFORT");
        if (!string.IsNullOrWhiteSpace(reasoningEffort) && reasoningEffort is not ("none" or "low" or "medium" or "high"))
            throw new AgentHostException("provider-reasoning-effort-invalid", "Reasoning effort is outside the supported local-provider values.");
        var maxTokenParameter = Environment.GetEnvironmentVariable("CHRONICLE_LLM_MAX_TOKEN_PARAMETER");
        if (string.IsNullOrWhiteSpace(maxTokenParameter)) maxTokenParameter = "max_completion_tokens";
        if (maxTokenParameter is not ("max_completion_tokens" or "max_tokens"))
            throw new AgentHostException("provider-token-parameter-invalid", "The configured output-token parameter is unsupported.");
        var outputMode = Environment.GetEnvironmentVariable("CHRONICLE_LLM_OUTPUT_MODE");
        if (string.IsNullOrWhiteSpace(outputMode)) outputMode = "auto";
        if (outputMode is not ("auto" or "json_schema" or "json_object" or "required_tool_call"))
            throw new AgentHostException("provider-output-mode-invalid", "Output mode must be auto, json_schema, json_object, or required_tool_call.");
        if (outputMode == "required_tool_call" && thinking != false)
            throw new AgentHostException("provider-output-mode-thinking-conflict", "Required tool calls need CHRONICLE_LLM_THINKING_MODE=disabled for this API protocol.");
        var maxRunCostCny = ReadOptionalDoubleEnvironment("CHRONICLE_LLM_MAX_RUN_COST_CNY", 0.01d, 1000d) ?? 5d;

        return new OllamaNativeProvider(new OllamaProviderSettings(
            endpoint,
            model,
            nativeOllama,
            TimeSpan.FromSeconds(timeoutSeconds),
            maxOutputTokens,
            temperature,
            thinking,
            reasoningEffort,
            maxTokenParameter,
            ReadApiKey(baseUri),
            outputMode,
            maxRunCostCny,
            maxHttpRequestsPerDecision));
    }

    internal static OllamaNativeProvider FromConfiguredProfile()
    {
        if (Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE") is string harnessMode &&
            (string.Equals(harnessMode, "visual-capture", StringComparison.Ordinal) || string.Equals(harnessMode, "agent-host-lifecycle-test", StringComparison.Ordinal) || string.Equals(harnessMode, "visual-battle-fixture", StringComparison.Ordinal)) &&
            !string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("CHRONICLE_AGENT_PROFILE_PATH")))
        {
            var overridePath = Path.GetFullPath(Environment.GetEnvironmentVariable("CHRONICLE_AGENT_PROFILE_PATH")!);
            var tempRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
            if (string.IsNullOrWhiteSpace(tempRoot))
                throw new AgentHostException("provider-profile-override-not-authorized", "A temporary profile override requires a Harness-owned directory.");
            var root = Path.GetFullPath(tempRoot).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
            if (!overridePath.StartsWith(root, StringComparison.OrdinalIgnoreCase))
                throw new AgentHostException("provider-profile-override-not-authorized", "The Harness provider profile must stay inside its disposable evidence directory.");
            return FromProfile(AgentProviderProfile.Load(overridePath, "harness-mcm-profile-fixture"));
        }

        return FromProfile(AgentProviderProfile.LoadDefault());
    }

    internal static OllamaNativeProvider FromCampaignRequest(JsonElement request)
    {
        if (request.TryGetProperty("providerConfiguration", out var configuration))
            return FromProfile(AgentProviderProfile.Parse(configuration, ReadString(request, "providerConfigurationSource") ?? "mcm-start-request"));
        return FromConfiguredProfile();
    }

    private static OllamaNativeProvider FromProfile(AgentProviderProfile profile)
    {
        var baseUri = new Uri(profile.BaseUrl.TrimEnd('/'), UriKind.Absolute);
        var endpoint = new Uri(profile.BaseUrl.TrimEnd('/') + "/chat/completions", UriKind.Absolute);
        var maxTokenParameter = Environment.GetEnvironmentVariable("CHRONICLE_LLM_MAX_TOKEN_PARAMETER");
        if (string.IsNullOrWhiteSpace(maxTokenParameter))
            maxTokenParameter = string.Equals(endpoint.Host, "api.deepseek.com", StringComparison.OrdinalIgnoreCase) ? "max_tokens" : "max_completion_tokens";
        if (maxTokenParameter is not ("max_completion_tokens" or "max_tokens"))
            throw new AgentHostException("provider-token-parameter-invalid", "The configured output-token parameter is unsupported.");
        var outputMode = profile.OutputMode;
        if (outputMode == "auto" && string.Equals(endpoint.Host, "api.deepseek.com", StringComparison.OrdinalIgnoreCase))
            outputMode = "required_tool_call";
        var reasoningEffort = Environment.GetEnvironmentVariable("CHRONICLE_LLM_REASONING_EFFORT");
        if (string.IsNullOrWhiteSpace(reasoningEffort)) reasoningEffort = "none";
        if (reasoningEffort is not ("none" or "low" or "medium" or "high"))
            throw new AgentHostException("provider-reasoning-effort-invalid", "Reasoning effort is outside the supported values.");
        var thinking = ReadOptionalThinkingModeEnvironment();
        if (outputMode == "required_tool_call" && thinking is null && string.Equals(endpoint.Host, "api.deepseek.com", StringComparison.OrdinalIgnoreCase))
            thinking = false;
        if (outputMode == "required_tool_call" && thinking != false)
            throw new AgentHostException("provider-output-mode-thinking-conflict", "Required tool calls need CHRONICLE_LLM_THINKING_MODE=disabled for this API protocol.");
        var maxRunCostCny = profile.DeepSeekRunCostLimitCny;
        return new OllamaNativeProvider(new OllamaProviderSettings(
            endpoint,
            profile.ModelId,
            NativeOllama: false,
            Timeout: TimeSpan.FromSeconds(ReadIntegerEnvironment("CHRONICLE_LLM_TIMEOUT_SECONDS", 360, 5, 360)),
            MaxOutputTokens: ReadIntegerEnvironment("CHRONICLE_LLM_MAX_TOKENS", 256, 64, 4096),
            MaxHttpRequestsPerDecision: ReadIntegerEnvironment("CHRONICLE_LLM_MAX_HTTP_REQUESTS_PER_DECISION", IsFreeLlmApi(endpoint) ? 1 : 8, 1, 8),
            Temperature: 0d,
            Thinking: thinking,
            ReasoningEffort: reasoningEffort,
            MaxTokenParameter: maxTokenParameter,
            ApiKey: ReadApiKey(baseUri),
            OutputMode: outputMode,
            MaxEstimatedRunCostCny: maxRunCostCny),
            configurationSource: profile.Source);
    }

    private static bool? ReadOptionalThinkingModeEnvironment()
    {
        var mode = Environment.GetEnvironmentVariable("CHRONICLE_LLM_THINKING_MODE");
        if (string.IsNullOrWhiteSpace(mode)) mode = Environment.GetEnvironmentVariable("CHRONICLE_LLM_THINKING_MODE", EnvironmentVariableTarget.User);
        return mode switch
        {
            null or "" => null,
            "enabled" => true,
            "disabled" => false,
            _ => throw new AgentHostException("provider-thinking-mode-invalid", "Thinking mode must be enabled, disabled, or omitted.")
        };
    }

    private static string? ReadApiKey(Uri baseUri)
    {
        var credential = AgentProviderConfigurationValidator.SelectApiKey(
            baseUri.AbsoluteUri.TrimEnd('/'),
            Environment.GetEnvironmentVariable("CHRONICLE_LLM_API_KEY"),
            Environment.GetEnvironmentVariable("CHRONICLE_LLM_API_KEY", EnvironmentVariableTarget.User),
            Environment.GetEnvironmentVariable("FREELLMAPI_API_KEY"),
            Environment.GetEnvironmentVariable("FREELLMAPI_API_KEY", EnvironmentVariableTarget.User));
        return string.IsNullOrWhiteSpace(credential.ApiKey) ? null : credential.ApiKey.Trim();
    }

    internal Task<ProviderDecisionResult> DecideAsync(JsonElement request, CancellationToken cancellationToken) =>
        DecideAsync(request, AgentHostDecisionCycle.CampaignSystemPrompt + " " + AgentHostDecisionCycle.QuestTerminalOutcomeRule, cancellationToken);

    Task<ProviderDecisionResult> IAgentHostDecisionProvider.DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken) =>
        DecideAsync(request, systemPrompt, cancellationToken);

    Task IAgentHostDecisionProvider.CheckConfiguredModelAsync(CancellationToken cancellationToken) => CheckConfiguredModelAsync(cancellationToken);

    internal async Task CheckConfiguredModelAsync(CancellationToken cancellationToken)
    {
        var endpointPath = _settings.Endpoint.AbsolutePath;
        const string completionSuffix = "/chat/completions";
        if (!endpointPath.EndsWith(completionSuffix, StringComparison.OrdinalIgnoreCase))
            throw new AgentHostException("provider-health-endpoint-invalid", "The configured provider URL does not have the supported chat-completions path.");

        var modelsUriBuilder = new UriBuilder(_settings.Endpoint)
        {
            Path = endpointPath[..^completionSuffix.Length] + "/models",
            Query = string.Empty,
            Fragment = string.Empty
        };
        if (IsFreeLlmApi(_settings.Endpoint) && !string.IsNullOrWhiteSpace(_settings.ApiKey))
            modelsUriBuilder.Query = "available=true";
        if ((!_settings.Endpoint.IsLoopback || IsFreeLlmApi(_settings.Endpoint)) && string.IsNullOrWhiteSpace(_settings.ApiKey))
            throw new AgentHostException("provider-api-key-missing", "This provider requires an API key; configure CHRONICLE_LLM_API_KEY without placing it in the model profile.");

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(8));
        try
        {
            using var healthRequest = new HttpRequestMessage(HttpMethod.Get, modelsUriBuilder.Uri);
            AddAuthorization(healthRequest);
            using var response = await _client.SendAsync(healthRequest, HttpCompletionOption.ResponseContentRead, timeout.Token);
            if (!response.IsSuccessStatusCode)
                throw new AgentHostException("provider-unavailable", "The configured model service rejected its model-list health check.");

            var bytes = await response.Content.ReadAsByteArrayAsync(timeout.Token);
            if (bytes.Length is <= 0 or > 128 * 1024)
                throw new AgentHostException("provider-health-response-invalid", "The configured model service returned an empty or oversized model-list response.");

            using var document = JsonDocument.Parse(bytes);
            if (!document.RootElement.TryGetProperty("data", out var models) || models.ValueKind != JsonValueKind.Array)
                throw new AgentHostException("provider-health-response-invalid", "The configured model service returned an unsupported model-list response.");

            JsonElement selectedModel = default;
            var modelRows = models.EnumerateArray().ToArray();
            _availableModelCount = modelRows.Length;
            foreach (var model in modelRows)
            {
                if (!string.Equals(ReadString(model, "id"), _settings.Model, StringComparison.Ordinal)) continue;
                selectedModel = model;
                break;
            }
            var modelFound = selectedModel.ValueKind == JsonValueKind.Object;
            var documentedFreeLlmApiRouterStrategy = IsFreeLlmApi(_settings.Endpoint) && FreeLlmApiRouterStrategies.Contains(_settings.Model);
            if (!modelFound && !documentedFreeLlmApiRouterStrategy)
                throw new AgentHostException("provider-model-unavailable", "The configured model is not listed by the provider model service.");

            _useRequiredToolCallStrategy = false;
            _supportsParallelToolCalls = false;
            _supportsReasoningEffort = false;
            if (IsFreeLlmApi(_settings.Endpoint) && modelFound &&
                selectedModel.TryGetProperty("supported_parameters", out var supportedParameters) && supportedParameters.ValueKind == JsonValueKind.Array)
            {
                var capabilities = supportedParameters.EnumerateArray()
                    .Where(value => value.ValueKind == JsonValueKind.String)
                    .Select(value => value.GetString())
                    .Where(value => !string.IsNullOrWhiteSpace(value))
                    .ToHashSet(StringComparer.OrdinalIgnoreCase);
                _supportsParallelToolCalls = capabilities.Contains("parallel_tool_calls");
                _supportsReasoningEffort = capabilities.Contains("reasoning_effort");
                var supportsResponseFormat = capabilities.Contains("response_format");
                var supportsRequiredToolCall = capabilities.Contains("tools") && capabilities.Contains("tool_choice");
                if (supportsResponseFormat)
                {
                    _useRequiredToolCallStrategy = false;
                }
                else if (supportsRequiredToolCall)
                {
                    _useRequiredToolCallStrategy = true;
                }
                else if (_settings.OutputMode == "json_object")
                {
                    _usePromptOnlyJsonMode = true;
                }
                else
                {
                    throw new AgentHostException("provider-structured-output-unsupported", "The configured FreeLLMAPI model advertises neither response_format nor required tool-calling support; no decision request was sent.");
                }
            }
            if (_settings.OutputMode == "required_tool_call") _useRequiredToolCallStrategy = true;
            else if (_settings.OutputMode is "json_schema" or "json_object") _useRequiredToolCallStrategy = false;
        }
        catch (AgentHostException)
        {
            throw;
        }
        catch (OperationCanceledException exception) when (!cancellationToken.IsCancellationRequested)
        {
            throw new AgentHostException("provider-health-timeout", "The local model service did not answer its bounded health check.", exception);
        }
        catch (HttpRequestException exception)
        {
            var socketError = FindSocketException(exception)?.SocketErrorCode.ToString() ?? "none";
            var statusCode = exception.StatusCode.HasValue ? ((int)exception.StatusCode.Value).ToString(CultureInfo.InvariantCulture) : "none";
            var innerType = exception.InnerException?.GetType().Name ?? "none";
            var details = $"httpRequestError={exception.HttpRequestError}; status={statusCode}; innerType={innerType}; socketError={socketError}; hresult=0x{exception.HResult:X8}";
            throw new AgentHostException("provider-unavailable", "The configured model service could not be reached. " + details, exception);
        }
        catch (JsonException exception)
        {
            throw new AgentHostException("provider-health-response-invalid", "The local model service returned malformed model-list data.", exception);
        }
    }

    private static SocketException? FindSocketException(Exception exception)
    {
        for (var current = exception; current is not null; current = current.InnerException)
            if (current is SocketException socket) return socket;
        return null;
    }

    internal async Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken)
    {
        ValidateDecisionRequest(request);
        var userContent = JsonSerializer.Serialize(request, JsonOptions);
        var userPayloadBytes = Encoding.UTF8.GetByteCount(userContent);
        var systemPromptBytes = Encoding.UTF8.GetByteCount(systemPrompt);
        var observationBytes = request.TryGetProperty("observation", out var observationElement)
            ? Encoding.UTF8.GetByteCount(observationElement.GetRawText())
            : 0;
        using var decisionRequestSnapshot = JsonDocument.Parse(userContent);
        var messages = new[]
        {
            new { role = "system", content = systemPrompt },
            new { role = "user", content = userContent }
        };
        var payload = new Dictionary<string, object?>
        {
            ["model"] = _settings.Model,
            ["messages"] = messages
        };
        string? reasoningEffortApplied = null;
        var useJsonObjectCompatibilityMode = !_settings.NativeOllama && UsesJsonObjectCompatibilityMode();
        if (_settings.NativeOllama)
        {
            payload["stream"] = false;
            payload["format"] = BuildDecisionSchema(request);
            var options = new Dictionary<string, object?> { ["num_predict"] = _settings.MaxOutputTokens };
            if (_settings.Temperature.HasValue) options["temperature"] = _settings.Temperature.Value;
            payload["options"] = options;
            if (_settings.Thinking.HasValue) payload["think"] = _settings.Thinking.Value;
        }
        else
        {
            if (_useRequiredToolCallStrategy)
            {
                payload["tools"] = new[]
                {
                    new
                    {
                        type = "function",
                        function = new
                        {
                            name = "submit_chronicle_decision",
                            description = "Submit exactly one proposed Chronicle decision. This function is an output format only; it does not execute any game action.",
                            strict = true,
                            parameters = BuildDecisionSchema(request)
                        }
                    }
                };
                payload["tool_choice"] = "required";
                if (_supportsParallelToolCalls) payload["parallel_tool_calls"] = false;
            }
            else if (!_usePromptOnlyJsonMode)
            {
                payload["response_format"] = useJsonObjectCompatibilityMode
                    ? new { type = "json_object" }
                    : new { type = "json_schema", json_schema = new { name = "chronicle_agent_decision", strict = true, schema = BuildDecisionSchema(request) } };
            }
            payload[_settings.MaxTokenParameter] = _settings.MaxOutputTokens;
            if (_settings.Thinking.HasValue) payload["thinking"] = new { type = _settings.Thinking.Value ? "enabled" : "disabled" };
            var reasoningEffortIsExplicitlySupportedByFreeLlmApi = IsFreeLlmApi(_settings.Endpoint) && _supportsReasoningEffort;
            if (!string.IsNullOrWhiteSpace(_settings.ReasoningEffort) &&
                !string.Equals(_settings.ReasoningEffort, "none", StringComparison.OrdinalIgnoreCase) &&
                (_settings.Thinking != false || reasoningEffortIsExplicitlySupportedByFreeLlmApi))
            {
                payload["reasoning_effort"] = _settings.ReasoningEffort;
                reasoningEffortApplied = _settings.ReasoningEffort;
            }
            if (_settings.Temperature.HasValue) payload["temperature"] = _settings.Temperature.Value;
        }

        var body = JsonSerializer.Serialize(payload, JsonOptions);
        var bodyBytes = Encoding.UTF8.GetByteCount(body);
        if (bodyBytes > MaxRequestBytes)
            throw new AgentHostException("provider-request-too-large", "The structured model request exceeds the Host size limit.");
        var reservedCostForRequest = 0d;
        DeepSeekInputTokenEstimate? deepSeekInputTokenEstimate = null;
        if (IsDeepSeekApi(_settings.Endpoint))
        {
            // Count the pinned DeepSeek tokenizer over the exact serialized API
            // request, add an empirically calibrated wrapper margin, and reserve
            // every output token at the peak rate. Returned usage remains the
            // billing source of truth and is compared with this estimate per request.
            deepSeekInputTokenEstimate = DeepSeekPromptTokenEstimator.EstimateRequest(body, systemPrompt, userContent, payload);
            reservedCostForRequest = (deepSeekInputTokenEstimate.ReservedTokens * DeepSeekInputPeakCnyPerMillion +
                                      _settings.MaxOutputTokens * DeepSeekOutputPeakCnyPerMillion) / 1000000d;
            if (_reservedDeepSeekCostCny + reservedCostForRequest > _settings.MaxEstimatedRunCostCny)
            {
                AgentHostHarnessProgressTrace.RecordBudgetReservationRejected(request, _settings.Model,
                    deepSeekInputTokenEstimate.TokenizerTokens, deepSeekInputTokenEstimate.ReservedTokens, _settings.MaxOutputTokens,
                    _reservedDeepSeekCostCny, reservedCostForRequest, _settings.MaxEstimatedRunCostCny);
                throw new AgentHostException("provider-budget-exhausted", "The DeepSeek estimated cost reservation would exceed the configured per-run threshold; no additional model request was sent.");
            }
            _reservedDeepSeekCostCny = Math.Round(_reservedDeepSeekCostCny + reservedCostForRequest, 8);
        }

        using var requestTimeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        requestTimeout.CancelAfter(_settings.Timeout);
        var requestDeadlineUtc = DateTimeOffset.UtcNow + _settings.Timeout;
        var transientProviderRetriesUsed = 0;
        var rateLimitRetryAttempts = 0;
        var rateLimitRetryWaitMilliseconds = 0L;
        RateLimitRetryHint? lastRateLimitRetryHint = null;
        bool? lastRateLimitRetryFitsDeadline = null;
        var providerHttpRequestAttempts = 0;
        void ThrowIfProviderHttpRequestBudgetExhausted(HttpResponseMessage? precedingResponse = null)
        {
            if (providerHttpRequestAttempts < _settings.MaxHttpRequestsPerDecision) return;
            var retryAfter = precedingResponse?.Headers.RetryAfter?.ToString();
            int? statusCode = precedingResponse is null ? null : (int)precedingResponse.StatusCode;
            var providerRoute = SafeOptionalDiagnosticField(precedingResponse is null
                ? _lastProviderRoute
                : ReadResponseHeader(precedingResponse, "X-Routed-Via") ?? _lastProviderRoute);
            var responseRequestId = precedingResponse is null ? null : SafeOptionalDiagnosticField(ReadResponseHeader(precedingResponse, "X-Request-Id") ??
                ReadResponseHeader(precedingResponse, "X-Correlation-Id") ?? ReadResponseHeader(precedingResponse, "CF-Ray"));
            var fallbackAttempts = precedingResponse is null ? null : ReadFallbackAttemptCount(precedingResponse);
            var fallbackTrail = precedingResponse is null ? null : SafeFallbackTrail(ReadResponseHeader(precedingResponse, "X-Fallback-Trail"));
            precedingResponse?.Dispose();
            throw new AgentHostException("provider-http-request-budget-exhausted",
                $"The per-decision HTTP request limit of {_settings.MaxHttpRequestsPerDecision} was reached after {providerHttpRequestAttempts} request(s); no additional provider request was sent.",
                providerHttpStatus: statusCode,
                providerRoute: providerRoute,
                providerRetryAfter: SafeOptionalDiagnosticField(retryAfter),
                providerResponseRequestId: responseRequestId,
                providerFallbackAttempts: fallbackAttempts,
                providerFallbackTrail: fallbackTrail,
                providerRetryAttempts: rateLimitRetryAttempts, providerFailureStage: "per-decision-http-request-budget",
                providerProxySelectionSource: _proxySelectionSource, providerProxyEndpointHostPort: _proxyEndpointHostPort,
                providerTimeoutSeconds: (int)_settings.Timeout.TotalSeconds);
        }
        async Task<HttpResponseMessage> SendProviderRequestAsync(string requestBody)
        {
            ThrowIfProviderHttpRequestBudgetExhausted();
            try
            {
                await WaitForProviderRateWindowAsync(requestTimeout.Token);
            }
            catch (OperationCanceledException exception) when (!cancellationToken.IsCancellationRequested)
            {
                throw new AgentHostException("provider-timeout", "The model provider exceeded its configured timeout while waiting for the provider rate window.", exception,
                    providerFailureStage: "provider-rate-window-wait", providerProxySelectionSource: _proxySelectionSource,
                    providerProxyEndpointHostPort: _proxyEndpointHostPort,
                    providerTimeoutSeconds: (int)_settings.Timeout.TotalSeconds, providerRequestBodyBytes: Encoding.UTF8.GetByteCount(requestBody),
                    providerRetryAttempts: rateLimitRetryAttempts, providerTransportErrorType: exception.GetType().Name);
            }
            using var message = new HttpRequestMessage(HttpMethod.Post, _settings.Endpoint)
            {
                Content = new StringContent(requestBody, new UTF8Encoding(false), "application/json")
            };
            AddAuthorization(message);
            try
            {
                providerHttpRequestAttempts++;
                return await _client.SendAsync(message, HttpCompletionOption.ResponseHeadersRead, requestTimeout.Token);
            }
            catch (OperationCanceledException exception) when (!cancellationToken.IsCancellationRequested)
            {
                throw new AgentHostException("provider-timeout", "The model provider did not respond within its configured timeout.", exception,
                    providerFailureStage: "http-send-response", providerProxySelectionSource: _proxySelectionSource,
                    providerProxyEndpointHostPort: _proxyEndpointHostPort,
                    providerTimeoutSeconds: (int)_settings.Timeout.TotalSeconds, providerRequestBodyBytes: Encoding.UTF8.GetByteCount(requestBody),
                    providerRetryAttempts: rateLimitRetryAttempts, providerTransportErrorType: exception.GetType().Name);
            }
            catch (HttpRequestException exception)
            {
                throw new AgentHostException("provider-unreachable", "The configured model provider could not be reached.", exception,
                    providerFailureStage: "http-send-response", providerProxySelectionSource: _proxySelectionSource,
                    providerProxyEndpointHostPort: _proxyEndpointHostPort,
                    providerTimeoutSeconds: (int)_settings.Timeout.TotalSeconds, providerRequestBodyBytes: Encoding.UTF8.GetByteCount(requestBody),
                    providerRetryAttempts: rateLimitRetryAttempts, providerTransportErrorType: exception.GetType().Name,
                    providerHttpStatus: exception.StatusCode.HasValue ? (int)exception.StatusCode.Value : null);
            }
        }

        async Task DelayForProviderRetryAsync(TimeSpan delay, string description)
        {
            try
            {
                await Task.Delay(delay, requestTimeout.Token);
            }
            catch (OperationCanceledException exception) when (!cancellationToken.IsCancellationRequested)
            {
                throw new AgentHostException("provider-timeout", $"The model provider exceeded its configured timeout {description}.", exception,
                    providerFailureStage: "rate-limit-retry-delay", providerProxySelectionSource: _proxySelectionSource,
                    providerProxyEndpointHostPort: _proxyEndpointHostPort,
                    providerTimeoutSeconds: (int)_settings.Timeout.TotalSeconds, providerRetryAttempts: rateLimitRetryAttempts,
                    providerTransportErrorType: exception.GetType().Name);
            }
        }

        async Task<HttpResponseMessage> SendProviderRequestWithTransientRetryAsync(string requestBody)
        {
            var response = await SendProviderRequestAsync(requestBody);
            while (true)
            {
                RateLimitRetryHint retryHint;
                try
                {
                    retryHint = await ReadRateLimitRetryHintAsync(_settings.Endpoint, response, requestTimeout.Token);
                }
                catch (OperationCanceledException exception) when (!cancellationToken.IsCancellationRequested)
                {
                    throw new AgentHostException("provider-timeout", "The model provider exceeded its configured timeout while reading rate-limit guidance.", exception,
                        providerFailureStage: "rate-limit-guidance-read", providerProxySelectionSource: _proxySelectionSource,
                        providerProxyEndpointHostPort: _proxyEndpointHostPort,
                        providerTimeoutSeconds: (int)_settings.Timeout.TotalSeconds, providerRetryAttempts: rateLimitRetryAttempts,
                        providerTransportErrorType: exception.GetType().Name,
                        providerHttpStatus: (int)response.StatusCode);
                }
                if (response.StatusCode == HttpStatusCode.TooManyRequests)
                {
                    lastRateLimitRetryHint = retryHint;
                    var remaining = requestDeadlineUtc - DateTimeOffset.UtcNow;
                    lastRateLimitRetryFitsDeadline = retryHint.Delay.HasValue && retryHint.Delay.Value + MinimumRateLimitRetryRequestBudget <= remaining;
                }
                // A FreeLLMAPI request may traverse several provider/model candidates and expose
                // a new Retry-After window on each 429. Permit one more bounded header retry so
                // an early short wait cannot consume the budget before a later, still-in-deadline
                // reset hint. Pool-exhaustion bodies remain limited to one retry.
                var maximumRateLimitRetries = retryHint.Source == "body-exhaustion" ? 1 : 3;
                if (rateLimitRetryAttempts < maximumRateLimitRetries && retryHint.Delay.HasValue && lastRateLimitRetryFitsDeadline == true)
                {
                    ThrowIfProviderHttpRequestBudgetExhausted(response);
                    response.Dispose();
                    var retryWaitStartedUtc = DateTimeOffset.UtcNow;
                    await DelayForProviderRetryAsync(retryHint.Delay.Value, "while waiting for the bounded rate-limit retry");
                    rateLimitRetryAttempts++;
                    rateLimitRetryWaitMilliseconds += (long)(DateTimeOffset.UtcNow - retryWaitStartedUtc).TotalMilliseconds;
                    response = await SendProviderRequestAsync(requestBody);
                    continue;
                }
                if (transientProviderRetriesUsed < 2 && ShouldRetryTransientFreeLlmApiFailure(_settings.Endpoint, response))
                {
                    ThrowIfProviderHttpRequestBudgetExhausted(response);
                    var retryDelaySeconds = transientProviderRetriesUsed == 0 ? 5 : 15;
                    transientProviderRetriesUsed++;
                    var fallbackTrail = ReadResponseHeader(response, "X-Fallback-Trail");
                    if (!string.IsNullOrWhiteSpace(fallbackTrail) && fallbackTrail.Contains("ovh/", StringComparison.OrdinalIgnoreCase))
                        _lastProviderRoute = "ovh";
                    response.Dispose();
                    await DelayForProviderRetryAsync(TimeSpan.FromSeconds(retryDelaySeconds), "while waiting for the transient upstream retry");
                    response = await SendProviderRequestAsync(requestBody);
                    continue;
                }
                return response;
            }
        }

        var responseFormatMode = _settings.NativeOllama
            ? "ollama-native"
            : _usePromptOnlyJsonMode ? "json_object_prompt_only" : _useRequiredToolCallStrategy ? "required_tool_call" : useJsonObjectCompatibilityMode ? "json_object_compatibility" : "json_schema";
        var response = await SendProviderRequestWithTransientRetryAsync(body);
        if (!_settings.NativeOllama && responseFormatMode == "json_schema" && ShouldRetryWithJsonObject(_settings.Endpoint, response))
        {
            ThrowIfProviderHttpRequestBudgetExhausted(response);
            var failedRoute = ReadResponseHeader(response, "X-Fallback-Trail");
            if (!string.IsNullOrWhiteSpace(failedRoute) && failedRoute.Contains("ovh/", StringComparison.OrdinalIgnoreCase))
                _lastProviderRoute = "ovh";
            if (!string.IsNullOrWhiteSpace(failedRoute) && failedRoute.Contains("ovh/Mistral-Small", StringComparison.OrdinalIgnoreCase))
            {
                payload.Remove("max_completion_tokens");
                payload["max_tokens"] = _settings.MaxOutputTokens;
            }
            response.Dispose();
            payload["response_format"] = new { type = "json_object" };
            body = JsonSerializer.Serialize(payload, JsonOptions);
            if (Encoding.UTF8.GetByteCount(body) > MaxRequestBytes)
                throw new AgentHostException("provider-request-too-large", "The JSON-mode model request exceeds the Host size limit.");
            responseFormatMode = "json_object_fallback";
            response = await SendProviderRequestWithTransientRetryAsync(body);
        }

        using (response)
        {
            if (!response.IsSuccessStatusCode)
            {
                var errorMetadata = await ReadSafeProviderErrorMetadataAsync(response, requestTimeout.Token);
                throw new AgentHostException("provider-http-error", BuildHttpFailureMessage(response, rateLimitRetryAttempts, rateLimitRetryWaitMilliseconds, lastRateLimitRetryHint, lastRateLimitRetryFitsDeadline) + " outputFormat=" + responseFormatMode,
                    providerHttpStatus: (int)response.StatusCode,
                    providerRoute: SafeDiagnosticField(ReadResponseHeader(response, "X-Routed-Via") ?? _lastProviderRoute),
                    providerOutputFormat: responseFormatMode,
                    providerRetryAttempts: rateLimitRetryAttempts,
                    providerRetryWaitMilliseconds: rateLimitRetryWaitMilliseconds,
                    providerFailureStage: "http-response-status", providerProxySelectionSource: _proxySelectionSource,
                    providerProxyEndpointHostPort: _proxyEndpointHostPort,
                    providerTimeoutSeconds: (int)_settings.Timeout.TotalSeconds, providerRequestBodyBytes: bodyBytes,
                    providerResponseServer: SafeOptionalDiagnosticField(ReadResponseHeader(response, "Server")),
                    providerResponseVia: SafeOptionalDiagnosticField(ReadResponseHeader(response, "Via")),
                    providerRetryAfter: SafeOptionalDiagnosticField(response.Headers.RetryAfter?.ToString()),
                    providerErrorBodyKind: errorMetadata.BodyKind, providerErrorContentType: errorMetadata.ContentType,
                    providerErrorType: errorMetadata.ErrorType, providerErrorCode: errorMetadata.ErrorCode,
                    providerResponseRequestId: errorMetadata.RequestId ?? SafeOptionalDiagnosticField(ReadResponseHeader(response, "X-Request-Id") ??
                        ReadResponseHeader(response, "X-Correlation-Id") ?? ReadResponseHeader(response, "CF-Ray")));
            }

            if (response.Content.Headers.ContentLength is > MaxResponseBytes)
                throw new AgentHostException("provider-response-too-large", "The local model response exceeds the Host size limit.");

            byte[] responseBytes;
            try
            {
                responseBytes = await response.Content.ReadAsByteArrayAsync(requestTimeout.Token);
            }
            catch (OperationCanceledException exception) when (!cancellationToken.IsCancellationRequested)
            {
                throw new AgentHostException("provider-timeout", "The local model provider response exceeded its configured timeout.", exception,
                    providerFailureStage: "response-body-read", providerProxySelectionSource: _proxySelectionSource,
                    providerProxyEndpointHostPort: _proxyEndpointHostPort,
                    providerTimeoutSeconds: (int)_settings.Timeout.TotalSeconds, providerRequestBodyBytes: bodyBytes,
                    providerRetryAttempts: rateLimitRetryAttempts, providerTransportErrorType: exception.GetType().Name,
                    providerHttpStatus: (int)response.StatusCode);
            }
            if (responseBytes.Length > MaxResponseBytes)
                throw new AgentHostException("provider-response-too-large", "The local model response exceeds the Host size limit.");

            using var responseDocument = ParseJson(responseBytes, "provider-response-invalid-json");
            var root = responseDocument.RootElement;
            string? responseModel;
            string? finishReason;
            string? content;
            int? promptTokens;
            int? completionTokens;
            int? promptCacheHitTokens = null;
            int? promptCacheMissTokens = null;
            if (_settings.NativeOllama)
            {
                if (root.TryGetProperty("done", out var completed) && completed.ValueKind == JsonValueKind.False)
                    throw new AgentHostException("provider-response-truncated", "The local model provider marked its response incomplete.");
                finishReason = ReadString(root, "done_reason");
                responseModel = ReadString(root, "model");
                promptTokens = ReadNonNegativeInt(root, "prompt_eval_count");
                completionTokens = ReadNonNegativeInt(root, "eval_count");
                if (!root.TryGetProperty("message", out var messageElement) || messageElement.ValueKind != JsonValueKind.Object ||
                    !messageElement.TryGetProperty("content", out var contentElement) || contentElement.ValueKind != JsonValueKind.String)
                    throw new AgentHostException("provider-content-missing", "The local model provider did not return message content.");
                content = contentElement.GetString();
            }
            else
            {
                var choices = root.TryGetProperty("choices", out var choiceArray) && choiceArray.ValueKind == JsonValueKind.Array
                    ? choiceArray.EnumerateArray().ToArray()
                    : Array.Empty<JsonElement>();
                if (choices.Length != 1)
                    throw new AgentHostException("provider-content-missing", $"The local OpenAI-compatible provider did not return one structured message (choiceCount={choices.Length}; hasError={root.TryGetProperty("error", out _)}; format={responseFormatMode}; responseModel={SafeDiagnosticField(ReadString(root, "model"))}; routedVia={SafeDiagnosticField(ReadResponseHeader(response, "X-Routed-Via"))}).");
                if (choices[0].ValueKind != JsonValueKind.Object ||
                    !choices[0].TryGetProperty("message", out var messageElement) || messageElement.ValueKind != JsonValueKind.Object)
                {
                    var choiceHasMessage = choices[0].ValueKind == JsonValueKind.Object && choices[0].TryGetProperty("message", out _);
                    throw new AgentHostException("provider-content-missing", $"The local OpenAI-compatible provider returned no message object (choiceKind={choices[0].ValueKind}; hasMessage={choiceHasMessage}; format={responseFormatMode}).");
                }
                if (!string.IsNullOrWhiteSpace(ReadString(messageElement, "refusal")))
                    throw new AgentHostException("provider-refused", "The local model provider refused the decision request.");
                finishReason = ReadString(choices[0], "finish_reason");
                responseModel = ReadString(root, "model");
                if (responseFormatMode == "required_tool_call")
                {
                    var hasToolCalls = messageElement.TryGetProperty("tool_calls", out var toolCalls);
                    var toolCallCount = hasToolCalls && toolCalls.ValueKind == JsonValueKind.Array ? toolCalls.GetArrayLength() : 0;
                    if (toolCallCount != 1)
                    {
                        var hasContent = messageElement.TryGetProperty("content", out var contentElement);
                        var contentKind = hasContent ? contentElement.ValueKind.ToString() : JsonValueKind.Undefined.ToString();
                        var contentCharacters = hasContent && contentElement.ValueKind == JsonValueKind.String
                            ? contentElement.GetString()?.Length ?? 0
                            : 0;
                        var responseUsage = root.TryGetProperty("usage", out var responseUsageElement) ? responseUsageElement : default;
                        var responsePromptTokens = ReadNonNegativeInt(responseUsage, "prompt_tokens");
                        var responseCompletionTokens = ReadNonNegativeInt(responseUsage, "completion_tokens");
                        var responseRoute = SafeDiagnosticField(ReadResponseHeader(response, "X-Routed-Via"));
                        var toolCallFailureCode = toolCallCount > 1
                            ? "provider-multiple-tool-calls"
                            : finishReason is "length" or "max_tokens"
                                ? "provider-response-truncated"
                                : "provider-tool-call-missing";
                        throw new AgentHostException(toolCallFailureCode,
                            $"The model must return exactly one required decision tool call (toolCallsPresent={hasToolCalls}; toolCallCount={toolCallCount}; contentKind={contentKind}; contentCharacters={contentCharacters}; finishReason={SafeDiagnosticField(finishReason)}; format={responseFormatMode}; responseModel={SafeDiagnosticField(responseModel)}; routedVia={responseRoute}; promptTokens={responsePromptTokens?.ToString(CultureInfo.InvariantCulture) ?? "unknown"}; completionTokens={responseCompletionTokens?.ToString(CultureInfo.InvariantCulture) ?? "unknown"}).",
                            providerRoute: responseRoute, providerOutputFormat: responseFormatMode,
                            providerToolCallsPresent: hasToolCalls, providerToolCallCount: toolCallCount,
                            providerResponseContentKind: contentKind, providerResponseContentCharacters: contentCharacters,
                            providerFinishReason: SafeDiagnosticField(finishReason), providerResponseModel: SafeDiagnosticField(responseModel),
                            providerResponsePromptTokens: responsePromptTokens, providerResponseCompletionTokens: responseCompletionTokens);
                    }
                    var toolCall = toolCalls[0];
                    if (ReadString(toolCall, "type") != "function" ||
                        !toolCall.TryGetProperty("function", out var function) || function.ValueKind != JsonValueKind.Object ||
                        ReadString(function, "name") != "submit_chronicle_decision" ||
                        !function.TryGetProperty("arguments", out var arguments) || arguments.ValueKind != JsonValueKind.String)
                        throw new AgentHostException("provider-tool-call-invalid", "The model returned an unsupported decision tool call envelope.");
                    content = arguments.GetString();
                }
                else
                {
                    if (!messageElement.TryGetProperty("content", out var contentElement) || contentElement.ValueKind != JsonValueKind.String)
                    {
                        var hasToolCalls = messageElement.TryGetProperty("tool_calls", out var toolCalls);
                        var toolCallCount = hasToolCalls && toolCalls.ValueKind == JsonValueKind.Array ? toolCalls.GetArrayLength() : 0;
                        var hasContent = messageElement.TryGetProperty("content", out var missingContent);
                        throw new AgentHostException("provider-content-missing", $"The local OpenAI-compatible provider returned an incomplete structured message (hasContent={hasContent}; contentKind={(hasContent ? missingContent.ValueKind : JsonValueKind.Undefined)}; hasToolCalls={hasToolCalls}; toolCallCount={toolCallCount}; finishReason={finishReason}; format={responseFormatMode}).");
                    }
                    content = contentElement.GetString();
                }
                var usage = root.TryGetProperty("usage", out var usageValue) ? usageValue : default;
                promptTokens = ReadNonNegativeInt(usage, "prompt_tokens");
                completionTokens = ReadNonNegativeInt(usage, "completion_tokens");
                promptCacheHitTokens = ReadNonNegativeInt(usage, "prompt_cache_hit_tokens");
                if (promptCacheHitTokens is null && usage.ValueKind == JsonValueKind.Object && usage.TryGetProperty("prompt_tokens_details", out var promptDetails))
                    promptCacheHitTokens = ReadNonNegativeInt(promptDetails, "cached_tokens");
                promptCacheMissTokens = ReadNonNegativeInt(usage, "prompt_cache_miss_tokens");
                if (promptCacheMissTokens is null && promptTokens.HasValue)
                    promptCacheMissTokens = Math.Max(0, promptTokens.Value - (promptCacheHitTokens ?? 0));
            }
            if (finishReason is "length" or "max_tokens")
                throw new AgentHostException("provider-response-truncated", "The local model provider reached its output-token limit.");
            if (string.IsNullOrWhiteSpace(content))
                throw new AgentHostException("provider-content-empty", "The local model provider returned empty decision content.");
            using var decisionDocument = ParseJson(Encoding.UTF8.GetBytes(content), "provider-decision-invalid-json");
            var decision = NormalizeDecision(decisionDocument.RootElement, decisionRequestSnapshot.RootElement);

            var routedVia = ReadResponseHeader(response, "X-Routed-Via");
            if (!string.IsNullOrWhiteSpace(routedVia)) _lastProviderRoute = routedVia;
            var fallbackAttempts = ReadFallbackAttemptCount(response);
            var fallbackTrail = SafeFallbackTrail(ReadResponseHeader(response, "X-Fallback-Trail"));
            double? estimatedCostCny = null;
            if (IsDeepSeekApi(_settings.Endpoint) && promptTokens.HasValue && completionTokens.HasValue)
            {
                var cacheHit = promptCacheHitTokens ?? 0;
                var cacheMiss = promptCacheMissTokens ?? Math.Max(0, promptTokens.Value - cacheHit);
                estimatedCostCny = (cacheHit * 0.048d + cacheMiss * DeepSeekInputPeakCnyPerMillion +
                                    completionTokens.Value * DeepSeekOutputPeakCnyPerMillion) / 1000000d;
                _deepSeekPromptCacheHitTokens += cacheHit;
                _deepSeekPromptCacheMissTokens += cacheMiss;
                _actualDeepSeekCostEstimateCny = Math.Round(_actualDeepSeekCostEstimateCny + estimatedCostCny.Value, 8);
            }
            return new ProviderDecisionResult(
                "completed",
                responseModel ?? _settings.Model,
                promptTokens,
                completionTokens,
                finishReason ?? (ReadBoolean(root, "done") == true ? "stop" : "unknown"),
                decision,
                routedVia,
                responseFormatMode,
                IsDeepSeekApi(_settings.Endpoint) ? _reservedDeepSeekCostCny : null,
                bodyBytes,
                systemPromptBytes,
                userPayloadBytes,
                observationBytes,
                promptCacheHitTokens,
                promptCacheMissTokens,
                estimatedCostCny,
                deepSeekInputTokenEstimate?.TokenizerTokens,
                deepSeekInputTokenEstimate?.RawRequestTokens,
                deepSeekInputTokenEstimate?.ReservedTokens,
                deepSeekInputTokenEstimate?.Method,
                _proxySelectionSource,
                _proxyEndpointHostPort,
                fallbackAttempts,
                fallbackTrail,
                reasoningEffortApplied);
        }
    }

    private static bool IsFreeLlmApi(Uri endpoint) => endpoint.Port == 31415 && (endpoint.Host is "127.0.0.1" or "localhost");

    private static bool IsDeepSeekApi(Uri endpoint) => string.Equals(endpoint.Host, "api.deepseek.com", StringComparison.OrdinalIgnoreCase);

    internal sealed record RateLimitRetryHint(TimeSpan? Delay, TimeSpan? ObservedDelay, string Source, bool IsPoolExhaustion);
    private sealed record ProviderErrorMetadata(string BodyKind, string? ContentType, string? ErrorType, string? ErrorCode, string? RequestId);

    private void AddAuthorization(HttpRequestMessage request)
    {
        if (!string.IsNullOrWhiteSpace(_settings.ApiKey))
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _settings.ApiKey);
    }

    private static string? ReadResponseHeader(HttpResponseMessage response, string headerName)
    {
        if (!response.Headers.TryGetValues(headerName, out var values)) return null;
        var value = values.FirstOrDefault()?.Trim();
        return string.IsNullOrWhiteSpace(value) ? null : value[..Math.Min(value.Length, 160)];
    }

    private static int? ReadFallbackAttemptCount(HttpResponseMessage response)
    {
        var value = ReadResponseHeader(response, "X-Fallback-Attempts");
        return int.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out var count) && count is >= 0 and <= 100
            ? count
            : null;
    }

    private static string? SafeFallbackTrail(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        return new string(value.Take(160).Select(character => char.IsLetterOrDigit(character) || character is '.' or '_' or ':' or '/' or '@' or '+' or '-' or '=' or ';' or ' '
            ? character
            : '_').ToArray());
    }

    private static string SafeDiagnosticField(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return "not-reported";
        return new string(value.Take(96).Select(character => char.IsLetterOrDigit(character) || character is '.' or '_' or ':' or '/' or '@' or '+' or '-'
            ? character
            : '_').ToArray());
    }

    private static string? SafeOptionalDiagnosticField(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : SafeDiagnosticField(value);

    private static async Task<ProviderErrorMetadata> ReadSafeProviderErrorMetadataAsync(HttpResponseMessage response, CancellationToken cancellationToken)
    {
        const int maximumBytes = 8192;
        var contentType = SafeOptionalDiagnosticField(response.Content.Headers.ContentType?.MediaType);
        if (response.Content.Headers.ContentLength is long length && length > maximumBytes)
            return new ProviderErrorMetadata("oversized", contentType, null, null, null);
        if (contentType is not null && !contentType.Contains("json", StringComparison.OrdinalIgnoreCase))
            return new ProviderErrorMetadata("non-json", contentType, null, null, null);

        using var boundedRead = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        boundedRead.CancelAfter(TimeSpan.FromSeconds(2));
        try
        {
            await using var stream = await response.Content.ReadAsStreamAsync(boundedRead.Token);
            var buffer = new byte[maximumBytes + 1];
            var total = 0;
            while (total < buffer.Length)
            {
                var read = await stream.ReadAsync(buffer.AsMemory(total, buffer.Length - total), boundedRead.Token);
                if (read == 0) break;
                total += read;
            }
            if (total > maximumBytes) return new ProviderErrorMetadata("oversized", contentType, null, null, null);
            if (total == 0) return new ProviderErrorMetadata("empty", contentType, null, null, null);
            using var document = JsonDocument.Parse(buffer.AsMemory(0, total));
            var root = document.RootElement;
            var error = root.ValueKind == JsonValueKind.Object && root.TryGetProperty("error", out var errorNode) && errorNode.ValueKind == JsonValueKind.Object
                ? errorNode : root;
            var errorType = SafeOptionalDiagnosticField(ReadString(error, "type"));
            var errorCode = SafeOptionalDiagnosticField(ReadString(error, "code"));
            var requestId = SafeOptionalDiagnosticField(ReadString(error, "request_id") ?? ReadString(root, "request_id"));
            var kind = errorType is null && errorCode is null ? "json-without-error-code" : "json-error";
            return new ProviderErrorMetadata(kind, contentType, errorType, errorCode, requestId);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return new ProviderErrorMetadata("metadata-read-timeout", contentType, null, null, null);
        }
        catch (JsonException)
        {
            return new ProviderErrorMetadata("invalid-json", contentType, null, null, null);
        }
        catch
        {
            return new ProviderErrorMetadata("metadata-unavailable", contentType, null, null, null);
        }
    }

    internal string BuildHttpFailureMessage(HttpResponseMessage response, int rateLimitRetryAttempts, long rateLimitRetryWaitMilliseconds, RateLimitRetryHint? retryHint = null, bool? retryFitsDeadline = null)
    {
        var providerName = IsFreeLlmApi(_settings.Endpoint) ? "FreeLLMAPI" : "model provider";
        var details = new List<string>();
        var routedVia = ReadResponseHeader(response, "X-Routed-Via");
        var fallbackAttempts = ReadResponseHeader(response, "X-Fallback-Attempts");
        var fallbackTrail = ReadResponseHeader(response, "X-Fallback-Trail");
        var retryAfter = response.Headers.RetryAfter?.ToString();
        if (!string.IsNullOrWhiteSpace(routedVia)) details.Add("routedVia=" + routedVia);
        else if (!string.IsNullOrWhiteSpace(_lastProviderRoute)) details.Add("lastSuccessfulRoute=" + _lastProviderRoute);
        if (!string.IsNullOrWhiteSpace(fallbackAttempts)) details.Add("fallbackAttempts=" + fallbackAttempts);
        if (!string.IsNullOrWhiteSpace(fallbackTrail)) details.Add("fallbackTrail=" + fallbackTrail);
        if (!string.IsNullOrWhiteSpace(retryAfter)) details.Add("retryAfter=" + retryAfter[..Math.Min(retryAfter.Length, 40)]);
        if (response.StatusCode == HttpStatusCode.TooManyRequests)
        {
            var boundedRetryAfter = retryHint?.Delay ?? GetBoundedRateLimitRetryAfter(_settings.Endpoint, response);
            details.Add("rateLimitRetryAttempts=" + rateLimitRetryAttempts.ToString(CultureInfo.InvariantCulture));
            details.Add("rateLimitRetryWaitMilliseconds=" + rateLimitRetryWaitMilliseconds.ToString(CultureInfo.InvariantCulture));
            details.Add("rateLimitRetryEligible=" + (boundedRetryAfter.HasValue ? "true" : "false"));
            details.Add("rateLimitRetrySource=" + (retryHint?.Source ?? (boundedRetryAfter.HasValue ? "header" : "none")));
            details.Add("rateLimitRetryAfterSeconds=" + ((retryHint?.ObservedDelay ?? boundedRetryAfter)?.TotalSeconds.ToString("0.###", CultureInfo.InvariantCulture) ?? "unbounded-or-unparseable"));
            if (retryHint?.IsPoolExhaustion == true) details.Add("freeLlmApiPoolExhausted=true");
            if (retryFitsDeadline.HasValue) details.Add("rateLimitRetryFitsDeadline=" + (retryFitsDeadline.Value ? "true" : "false"));
        }
        return $"{providerName} returned HTTP {(int)response.StatusCode}." +
               (details.Count == 0 ? string.Empty : " " + string.Join("; ", details));
    }

    internal static bool ShouldRetryWithJsonObject(Uri endpoint, HttpResponseMessage response)
    {
        if (!IsFreeLlmApi(endpoint) || response.StatusCode is not (HttpStatusCode.BadRequest or HttpStatusCode.UnprocessableEntity or HttpStatusCode.BadGateway)) return false;
        var fallbackTrail = ReadResponseHeader(response, "X-Fallback-Trail");
        if (fallbackTrail?.Contains("provider_bad_request", StringComparison.OrdinalIgnoreCase) == true) return true;
        return response.StatusCode == HttpStatusCode.BadGateway &&
               fallbackTrail?.Contains("=format_ignored", StringComparison.OrdinalIgnoreCase) == true;
    }

    internal static bool ShouldRetryTransientFreeLlmApiFailure(Uri endpoint, HttpResponseMessage response)
    {
        if (!IsFreeLlmApi(endpoint) || response.StatusCode != HttpStatusCode.BadGateway) return false;
        var fallbackTrail = ReadResponseHeader(response, "X-Fallback-Trail");
        return !string.IsNullOrWhiteSpace(fallbackTrail) &&
               fallbackTrail.Contains("key", StringComparison.OrdinalIgnoreCase) &&
               (fallbackTrail.Contains("=error", StringComparison.OrdinalIgnoreCase) ||
                fallbackTrail.Contains("=upstream_error", StringComparison.OrdinalIgnoreCase)) &&
               !fallbackTrail.Contains("provider_bad_request", StringComparison.OrdinalIgnoreCase);
    }

    internal static TimeSpan? GetBoundedRateLimitRetryAfter(Uri endpoint, HttpResponseMessage response)
    {
        if (!IsFreeLlmApi(endpoint) || response.StatusCode != HttpStatusCode.TooManyRequests || response.Headers.RetryAfter is null)
            return null;
        var delay = response.Headers.RetryAfter.Delta ?? response.Headers.RetryAfter.Date - DateTimeOffset.UtcNow;
        if (!delay.HasValue || delay.Value <= TimeSpan.Zero || delay.Value > TimeSpan.FromSeconds(360)) return null;
        return delay.Value;
    }

    private static async Task<RateLimitRetryHint> ReadRateLimitRetryHintAsync(Uri endpoint, HttpResponseMessage response, CancellationToken cancellationToken)
    {
        if (response.StatusCode != HttpStatusCode.TooManyRequests)
            return new RateLimitRetryHint(null, null, "none", false);

        var explicitHeader = response.Headers.RetryAfter;
        if (explicitHeader is not null)
        {
            var boundedHeaderDelay = GetBoundedRateLimitRetryAfter(endpoint, response);
            var observedHeaderDelay = explicitHeader.Delta ?? explicitHeader.Date - DateTimeOffset.UtcNow;
            return new RateLimitRetryHint(boundedHeaderDelay, observedHeaderDelay, boundedHeaderDelay.HasValue ? "header" : "header-ineligible", false);
        }

        if (!IsFreeLlmApi(endpoint))
            return new RateLimitRetryHint(null, null, "none", false);

        try
        {
            if (response.Content.Headers.ContentLength is > MaxRateLimitErrorBytes)
                return new RateLimitRetryHint(null, null, "body-too-large", false);

            await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
            using var body = new MemoryStream();
            var buffer = new byte[4096];
            while (body.Length <= MaxRateLimitErrorBytes)
            {
                var wanted = (int)Math.Min(buffer.Length, MaxRateLimitErrorBytes + 1L - body.Length);
                var read = await stream.ReadAsync(buffer.AsMemory(0, wanted), cancellationToken);
                if (read == 0) break;
                body.Write(buffer, 0, read);
                if (body.Length > MaxRateLimitErrorBytes)
                    return new RateLimitRetryHint(null, null, "body-too-large", false);
            }

            using var document = JsonDocument.Parse(body.ToArray());
            var root = document.RootElement;
            if (!root.TryGetProperty("error", out var error) || error.ValueKind != JsonValueKind.Object ||
                !error.TryGetProperty("message", out var messageElement) || messageElement.ValueKind != JsonValueKind.String)
                return new RateLimitRetryHint(null, null, "body-unrecognized", false);

            var message = messageElement.GetString() ?? string.Empty;
            if (!message.StartsWith("All models exhausted", StringComparison.OrdinalIgnoreCase))
                return new RateLimitRetryHint(null, null, "body-unrecognized", false);

            var marker = "Soonest reset ~";
            var markerIndex = message.IndexOf(marker, StringComparison.OrdinalIgnoreCase);
            if (markerIndex < 0)
                return new RateLimitRetryHint(null, null, "body-exhaustion-no-eta", true);

            var valueStart = markerIndex + marker.Length;
            var valueEnd = valueStart;
            while (valueEnd < message.Length && char.IsAsciiDigit(message[valueEnd])) valueEnd++;
            if (valueEnd == valueStart || valueEnd >= message.Length)
                return new RateLimitRetryHint(null, null, "body-exhaustion-invalid-eta", true);

            if (!int.TryParse(message.AsSpan(valueStart, valueEnd - valueStart), NumberStyles.None, CultureInfo.InvariantCulture, out var amount) || amount <= 0)
                return new RateLimitRetryHint(null, null, "body-exhaustion-invalid-eta", true);

            var unit = char.ToLowerInvariant(message[valueEnd]);
            var observedDelay = unit switch
            {
                's' => TimeSpan.FromSeconds(amount),
                'm' => TimeSpan.FromMinutes(amount),
                'h' => TimeSpan.FromHours(amount),
                _ => (TimeSpan?)null
            };
            if (!observedDelay.HasValue || (valueEnd + 1 < message.Length && message[valueEnd + 1] is not ('.' or ' ')))
                return new RateLimitRetryHint(null, null, "body-exhaustion-invalid-eta", true);

            var boundedDelay = observedDelay.Value <= TimeSpan.FromSeconds(360) ? observedDelay : null;
            return new RateLimitRetryHint(boundedDelay, observedDelay, boundedDelay.HasValue ? "body-exhaustion" : "body-exhaustion-over-bound", true);
        }
        catch (JsonException)
        {
            return new RateLimitRetryHint(null, null, "body-unrecognized", false);
        }
        catch (IOException)
        {
            return new RateLimitRetryHint(null, null, "body-read-failed", false);
        }
    }

    private bool UsesJsonObjectCompatibilityMode() =>
        // Remote OpenAI-compatible APIs do not share a standard JSON-Schema response
        // format. Use the broadly supported JSON-object contract remotely; the Host
        // still validates every returned field against the Native catalog.
        _settings.OutputMode == "json_object" ||
        (_settings.OutputMode == "auto" && (!_settings.Endpoint.IsLoopback || IsMistralSmall32(_settings.Model)));

    private static string ResolveMaxTokenParameter(string model, string configured) =>
        IsMistralSmall32(model) ? "max_tokens" : configured;

    private static bool IsMistralSmall32(string model) =>
        model.StartsWith("mistral-small-3.2-24b", StringComparison.OrdinalIgnoreCase);

    internal static TimeSpan GetMinimumRequestInterval(Uri endpoint, string model, string? previousRoute)
    {
        if (!IsFreeLlmApi(endpoint)) return TimeSpan.Zero;
        return IsMistralSmall32(model) || previousRoute?.StartsWith("ovh/", StringComparison.OrdinalIgnoreCase) == true
            ? TimeSpan.FromSeconds(45)
            : TimeSpan.Zero;
    }

    private async Task WaitForProviderRateWindowAsync(CancellationToken cancellationToken)
    {
        var minimum = GetMinimumRequestInterval(_settings.Endpoint, _settings.Model, _lastProviderRoute);
        if (_lastProviderRequestUtc != default)
        {
            var remaining = minimum - (DateTimeOffset.UtcNow - _lastProviderRequestUtc);
            if (remaining > TimeSpan.Zero) await Task.Delay(remaining, cancellationToken);
        }
        _lastProviderRequestUtc = DateTimeOffset.UtcNow;
    }

    public void Dispose()
    {
        if (_ownsClient) _client.Dispose();
    }

    internal static JsonObject BuildDecisionSchema(JsonElement request)
    {
        var alternatives = new JsonArray();
        if (request.TryGetProperty("allowedActions", out var actions) && actions.ValueKind == JsonValueKind.Array)
        {
            foreach (var action in actions.EnumerateArray())
            {
                var actionName = ReadString(action, "action");
                if (string.IsNullOrWhiteSpace(actionName)) continue;
                var argumentNames = action.TryGetProperty("arguments", out var arguments) && arguments.ValueKind == JsonValueKind.Array
                    ? arguments.EnumerateArray().Where(item => item.ValueKind == JsonValueKind.String).Select(item => item.GetString()!).Distinct(StringComparer.Ordinal).ToArray()
                    : Array.Empty<string>();
                var argumentProperties = new JsonObject();
                foreach (var argumentName in argumentNames)
                {
                    JsonElement values = default;
                    var hasEnumeratedValues = action.TryGetProperty("argumentValues", out var argumentValues) &&
                        argumentValues.ValueKind == JsonValueKind.Object && argumentValues.TryGetProperty(argumentName, out values) &&
                        values.ValueKind == JsonValueKind.Array;
                    var inferredValueType = hasEnumeratedValues ? InferEnumeratedJsonSchemaType(values) : null;
                    var valueType = inferredValueType ?? argumentName switch
                    {
                        "Days" or "Count" or "VolunteerSlot" or "Amount" or "OptionIndex" or "slot" or
                            "confirmPartySizeWarning" or "ConfirmPartySizeWarning" or "ConfirmPrisonerLimitWarning" => "integer",
                        _ => "string"
                    };
                    var argumentSchema = new JsonObject { ["type"] = valueType };
                    if (inferredValueType == valueType)
                    {
                        argumentSchema["enum"] = JsonNode.Parse(values.GetRawText());
                    }
                    argumentProperties[argumentName] = argumentSchema;
                }
                var requiredArgumentNames = new JsonArray();
                foreach (var argumentName in argumentNames) requiredArgumentNames.Add(argumentName);
                    var branch = new JsonObject
                {
                    ["type"] = "object",
                    ["properties"] = new JsonObject
                    {
                            ["action"] = new JsonObject { ["type"] = "string", ["enum"] = new JsonArray(actionName) },
                            ["arguments"] = new JsonObject { ["type"] = "object", ["properties"] = argumentProperties, ["required"] = requiredArgumentNames, ["additionalProperties"] = false }
                    },
                    ["required"] = new JsonArray("action", "arguments"),
                    ["additionalProperties"] = false
                };
                alternatives.Add(branch);
            }
        }

        if (request.TryGetProperty("allowedControls", out var controls) && controls.ValueKind == JsonValueKind.Array)
        {
            foreach (var controlItem in controls.EnumerateArray())
            {
                if (controlItem.ValueKind != JsonValueKind.String || string.IsNullOrWhiteSpace(controlItem.GetString())) continue;
                var controlName = controlItem.GetString()!;
                var properties = new JsonObject
                {
                    ["control"] = new JsonObject { ["type"] = "string", ["enum"] = new JsonArray(controlName) }
                };
                var required = new JsonArray("control");
                if (string.Equals(controlName, "observeAgain", StringComparison.Ordinal))
                {
                    var waitBounds = GetObserveAgainWaitBounds(request);
                    properties["waitSeconds"] = new JsonObject { ["type"] = "integer", ["minimum"] = waitBounds.Minimum, ["maximum"] = waitBounds.Maximum };
                    required.Add("waitSeconds");
                }
                properties["reason"] = new JsonObject { ["type"] = "string" };
                required.Add("reason");
                alternatives.Add(new JsonObject
                {
                    ["type"] = "object",
                    ["properties"] = properties,
                    ["required"] = required,
                    ["additionalProperties"] = false
                });
            }
        }

        if (alternatives.Count == 0)
            throw new AgentHostException("provider-decision-catalog-empty", "The local model was not called because Native listed no action or control.");
        return new JsonObject
        {
            ["type"] = "object",
            ["properties"] = new JsonObject
            {
                ["decision"] = new JsonObject { ["anyOf"] = alternatives }
            },
            ["required"] = new JsonArray("decision"),
            ["additionalProperties"] = false
        };
    }

    private static string? InferEnumeratedJsonSchemaType(JsonElement values)
    {
        if (values.ValueKind != JsonValueKind.Array || values.GetArrayLength() == 0) return null;
        var items = values.EnumerateArray().ToArray();
        if (items.All(item => item.ValueKind == JsonValueKind.String)) return "string";
        if (items.All(item => item.ValueKind == JsonValueKind.Number && item.TryGetInt32(out _))) return "integer";
        if (items.All(item => item.ValueKind is JsonValueKind.True or JsonValueKind.False)) return "boolean";
        return null;
    }

    internal static JsonObject NormalizeDecision(JsonElement decision, JsonElement request)
    {
        if (decision.ValueKind != JsonValueKind.Object)
            throw new AgentHostException("provider-decision-shape-invalid", "The local model decision must be a JSON object.");

        if (decision.TryGetProperty("decision", out var wrappedDecision))
        {
            var wrapperProperties = decision.EnumerateObject().Take(2).ToArray();
            if (wrapperProperties.Length != 1 || wrapperProperties[0].Name != "decision" || wrappedDecision.ValueKind != JsonValueKind.Object)
                throw new AgentHostException("provider-decision-wrapper-invalid", "A wrapped model decision must contain only one object-valued decision property.");
            decision = wrappedDecision;
        }

        var controlName = ReadString(decision, "control");
        var rawActionName = ReadString(decision, "action");
        var controlNamesListedAction = !string.IsNullOrWhiteSpace(controlName) && controlName is not ("done" or "observeAgain") &&
            FindAllowedAction(request, controlName) is not null;
        if (controlNamesListedAction && !string.IsNullOrWhiteSpace(rawActionName))
            throw new AgentHostException("provider-decision-ambiguous", "The local model supplied both an action and an action-name control.");
        var actionName = rawActionName ?? (controlNamesListedAction ? controlName : null);
        var isDone = ReadBoolean(decision, "done") == true || controlName == "done" || actionName == "done";
        var hasControl = !string.IsNullOrWhiteSpace(controlName) && controlName != "done" && !controlNamesListedAction;
        var hasObserveAgain = ReadBoolean(decision, "observeAgain") == true || ReadString(decision, "action") == "observeAgain" || controlName == "observeAgain";
        var hasAction = !string.IsNullOrWhiteSpace(actionName) && actionName is not ("observeAgain" or "done");
        if ((isDone ? 1 : 0) + (hasControl ? 1 : 0) + (hasObserveAgain && !hasControl ? 1 : 0) + (hasAction ? 1 : 0) != 1)
        {
            var shape = string.Join(",", decision.EnumerateObject().Take(12).Select(property => property.Name + ":" + property.Value.ValueKind));
            throw new AgentHostException("provider-decision-ambiguous", $"The local model must choose exactly one action, control, or stop; received fields [{shape}].");
        }

        if (isDone)
        {
            EnsureOnlyProperties(decision, "done", "control", "action", "arguments", "reason", "rationale");
            if (decision.TryGetProperty("arguments", out var stopArguments) &&
                (stopArguments.ValueKind == JsonValueKind.Object && stopArguments.EnumerateObject().Any() ||
                 stopArguments.ValueKind == JsonValueKind.Array && stopArguments.GetArrayLength() > 0 ||
                 stopArguments.ValueKind is not (JsonValueKind.Null or JsonValueKind.Undefined or JsonValueKind.Object or JsonValueKind.Array)))
                throw new AgentHostException("provider-stop-arguments-invalid", "A stop decision cannot include action arguments.");
            return new JsonObject
            {
                ["done"] = true,
                ["reason"] = ValidateReason(ReadString(decision, "reason") ?? ReadString(decision, "rationale"))
            };
        }

        if (controlName == "stop")
        {
            EnsureOnlyProperties(decision, "control", "reason", "rationale");
            if (!ContainsString(request, "allowedControls", "stop"))
                throw new AgentHostException("provider-control-unavailable", "stop is not currently listed; the workflow did not offer a safe stop control.");
            return new JsonObject
            {
                ["stop"] = true,
                ["reason"] = ValidateReason(ReadString(decision, "reason") ?? ReadString(decision, "rationale"))
            };
        }

        if (hasObserveAgain)
        {
            EnsureOnlyProperties(decision, "observeAgain", "control", "action", "arguments", "waitSeconds", "reason", "rationale");
            if (!ContainsString(request, "allowedControls", "observeAgain"))
                throw new AgentHostException("provider-control-unavailable", "observeAgain is not currently listed; do not wait unless the current control catalog allows it.");
            var waitValue = decision.TryGetProperty("waitSeconds", out var topWait)
                ? topWait
                : decision.TryGetProperty("arguments", out var arguments) && arguments.ValueKind == JsonValueKind.Object && arguments.TryGetProperty("waitSeconds", out var nestedWait)
                    ? nestedWait
                    : default;
            var waitBounds = GetObserveAgainWaitBounds(request);
            if (waitValue.ValueKind != JsonValueKind.Number || !waitValue.TryGetInt32(out var waitSeconds) ||
                waitSeconds < waitBounds.Minimum || waitSeconds > waitBounds.Maximum)
                throw new AgentHostException("provider-control-arguments-invalid", $"observeAgain must request an integer wait from {waitBounds.Minimum} to {waitBounds.Maximum} seconds.");
            return new JsonObject
            {
                ["observeAgain"] = true,
                ["waitSeconds"] = waitSeconds,
                ["reason"] = ValidateReason(ReadString(decision, "reason") ?? ReadString(decision, "rationale"))
            };
        }

        if (hasControl && controlName is "supportedMapArrivalGoal" or "supportedVillageToolsQuestGoal" or "supportedBattleSimulationGoal" or "supportedBattleAndCaptivityGoal" or "supportedEstablishYourClanGoal" or "supportedCaptivityRecoveryGoal" or "supportedEstablishClanGoldSaleGoal" or "unsupportedGoal")
        {
            EnsureOnlyProperties(decision, "control", "reason", "rationale");
            var classificationPhase = ReadBoolean(request, "goalScopeClassificationRequired") == true &&
                request.TryGetProperty("allowedActions", out var classificationActions) &&
                classificationActions.ValueKind == JsonValueKind.Array && classificationActions.GetArrayLength() == 0;
            if (!ContainsString(request, "allowedControls", controlName) &&
                (!classificationPhase || controlName is "supportedEstablishYourClanGoal" or "supportedCaptivityRecoveryGoal"))
            {
                var supportedListed = ContainsString(request, "allowedControls", "supportedMapArrivalGoal");
                var supportedQuestListed = ContainsString(request, "allowedControls", "supportedVillageToolsQuestGoal");
                var supportedBattleListed = ContainsString(request, "allowedControls", "supportedBattleSimulationGoal");
                var supportedBattleCaptivityListed = ContainsString(request, "allowedControls", "supportedBattleAndCaptivityGoal");
                var supportedEstablishYourClanListed = ContainsString(request, "allowedControls", "supportedEstablishYourClanGoal");
                var supportedCaptivityRecoveryListed = ContainsString(request, "allowedControls", "supportedCaptivityRecoveryGoal");
                var supportedGoldSaleListed = ContainsString(request, "allowedControls", "supportedEstablishClanGoldSaleGoal");
                var unsupportedListed = ContainsString(request, "allowedControls", "unsupportedGoal");
                var controlsKind = request.TryGetProperty("allowedControls", out var controls) ? controls.ValueKind.ToString() : "missing";
                var controlsItems = controls.ValueKind == JsonValueKind.Array
                    ? string.Join(",", controls.EnumerateArray().Select(item => item.ValueKind.ToString()))
                    : "none";
                var classificationRequired = ReadBoolean(request, "goalScopeClassificationRequired") == true;
                var actionCount = request.TryGetProperty("allowedActions", out var actions) && actions.ValueKind == JsonValueKind.Array
                    ? actions.GetArrayLength()
                    : -1;
                var iteration = request.TryGetProperty("iteration", out var iterationValue) && iterationValue.TryGetInt32(out var requestIteration)
                    ? requestIteration
                    : -1;
                throw new AgentHostException("provider-goal-classification-unavailable",
                    $"Goal classification is not currently listed in the decision catalog (catalog={controlsKind}[{controlsItems}], supported={supportedListed}, supportedQuest={supportedQuestListed}, supportedBattle={supportedBattleListed}, supportedBattleCaptivity={supportedBattleCaptivityListed}, supportedEstablishYourClan={supportedEstablishYourClanListed}, supportedCaptivityRecovery={supportedCaptivityRecoveryListed}, supportedGoldSale={supportedGoldSaleListed}, unsupported={unsupportedListed}, gate={classificationRequired}, actions={actionCount}, iteration={iteration}).");
            }
            return new JsonObject
            {
                ["goalClassification"] = controlName switch
                {
                    "supportedMapArrivalGoal" => "supported-map-arrival",
                    "supportedVillageToolsQuestGoal" => "supported-village-tools-quest",
                    "supportedBattleSimulationGoal" => "supported-battle-simulation",
                    "supportedBattleAndCaptivityGoal" => "supported-battle-and-captivity",
                    "supportedEstablishYourClanGoal" => "supported-establish-your-clan",
                    "supportedCaptivityRecoveryGoal" => "supported-captivity-recovery",
                    "supportedEstablishClanGoldSaleGoal" => "supported-establish-clan-gold-sale",
                    _ => "unsupported"
                },
                ["reason"] = ValidateReason(ReadString(decision, "reason") ?? ReadString(decision, "rationale"))
            };
        }

        var menuOptionCandidate = hasAction ? actionName : hasControl ? controlName : null;
        if (!string.IsNullOrWhiteSpace(menuOptionCandidate) && FindAllowedAction(request, menuOptionCandidate) is null &&
            FindEnabledMenuOption(request, menuOptionCandidate) is string menuOptionAlias && FindAllowedAction(request, "menuSelect") is not null)
        {
            EnsureOnlyProperties(decision, "action", "control", "arguments", "rationale", "reason");
            if (!MenuAliasArgumentsMatch(decision, menuOptionAlias))
                throw new AgentHostException("provider-menu-alias-arguments-invalid", "A menu-option alias cannot change its Native option identifier.");
            return new JsonObject
            {
                ["action"] = "menuSelect",
                ["arguments"] = new JsonObject { ["OptionId"] = menuOptionAlias },
                ["rationale"] = ValidateOptionalRationale(ReadString(decision, "rationale") ?? ReadString(decision, "reason"))
            };
        }

        if (hasControl)
            throw new AgentHostException("provider-control-unavailable", $"The control '{controlName}' is not listed in the current action or control catalog.");
        EnsureOnlyProperties(decision, "action", "control", "arguments", "rationale", "reason");
        var allowed = FindAllowedAction(request, actionName!);
        if (allowed is null)
        {
            var catalogNames = request.TryGetProperty("allowedActions", out var currentActions) && currentActions.ValueKind == JsonValueKind.Array
                ? string.Join(",", currentActions.EnumerateArray().Select(item => ReadString(item, "action")).Where(name => !string.IsNullOrWhiteSpace(name)))
                : string.Empty;
            throw new AgentHostException("provider-action-unavailable", $"Action '{actionName}' is not in the current Native action catalog [{catalogNames}].");
        }
        var normalizedArguments = NormalizeArguments(decision, allowed.Value);
        return new JsonObject
        {
            ["action"] = actionName,
            ["arguments"] = normalizedArguments,
            ["rationale"] = ValidateOptionalRationale(ReadString(decision, "rationale") ?? ReadString(decision, "reason"))
        };
    }

    private static string? FindEnabledMenuOption(JsonElement request, string requestedId)
    {
        if (!request.TryGetProperty("observation", out var observation) || observation.ValueKind != JsonValueKind.Object ||
            !observation.TryGetProperty("state", out var state) || state.ValueKind != JsonValueKind.Object ||
            !state.TryGetProperty("availableMenuOptions", out var options) || options.ValueKind != JsonValueKind.Array)
            return null;
        foreach (var option in options.EnumerateArray())
        {
            if (string.Equals(ReadString(option, "id"), requestedId, StringComparison.Ordinal) &&
                ReadBoolean(option, "available") == true && ReadBoolean(option, "enabled") == true)
                return requestedId;
        }
        return null;
    }

    private static bool MenuAliasArgumentsMatch(JsonElement decision, string menuOptionId)
    {
        if (!decision.TryGetProperty("arguments", out var arguments) || arguments.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined ||
            arguments.ValueKind == JsonValueKind.Array && arguments.GetArrayLength() == 0 ||
            arguments.ValueKind == JsonValueKind.Object && !arguments.EnumerateObject().Any()) return true;
        if (arguments.ValueKind != JsonValueKind.Object) return false;
        var properties = arguments.EnumerateObject().ToArray();
        return properties.Length == 1 && string.Equals(properties[0].Name, "OptionId", StringComparison.OrdinalIgnoreCase) &&
            properties[0].Value.ValueKind == JsonValueKind.String && properties[0].Value.GetString() == menuOptionId;
    }

    private static JsonObject NormalizeArguments(JsonElement decision, JsonElement allowedAction)
    {
        var allowedNames = allowedAction.TryGetProperty("arguments", out var names) && names.ValueKind == JsonValueKind.Array
            ? names.EnumerateArray().Where(item => item.ValueKind == JsonValueKind.String).Select(item => item.GetString()!).ToArray()
            : Array.Empty<string>();
        var argumentValue = decision.TryGetProperty("arguments", out var args) ? args.Clone() : default;
        for (var depth = 0; depth < 4; depth++)
        {
            if (argumentValue.ValueKind == JsonValueKind.String)
            {
                var encodedArguments = argumentValue.GetString()!;
                try
                {
                    using var parsed = ParseJson(Encoding.UTF8.GetBytes(encodedArguments), "provider-arguments-invalid-json");
                    argumentValue = parsed.RootElement.Clone();
                    continue;
                }
                catch (AgentHostException exception) when (exception.Code == "provider-arguments-invalid-json" &&
                    allowedNames.Length == 1 &&
                    (IsListedSingleArgumentValue(allowedAction, allowedNames[0], encodedArguments) ||
                     IsStoryModeClanNameTextArgument(allowedAction, allowedNames[0], encodedArguments)))
                {
                    // Some OpenAI-compatible JSON-object routes emit a one-scalar argument
                    // directly instead of wrapping it in an object. Repair only when the
                    // active Native action catalog proves the exact enum choice, or when the
                    // one text field is the StoryMode clan-name action whose native validator
                    // still decides whether the proposed name may be committed.
                    using var normalizedArguments = JsonDocument.Parse(JsonSerializer.Serialize(new Dictionary<string, string>
                    {
                        [allowedNames[0]] = encodedArguments
                    }));
                    argumentValue = normalizedArguments.RootElement.Clone();
                    break;
                }
            }
            if (argumentValue.ValueKind == JsonValueKind.Array && argumentValue.GetArrayLength() == 1)
            {
                var first = argumentValue[0];
                if (first.ValueKind is JsonValueKind.String or JsonValueKind.Array or JsonValueKind.Object)
                {
                    argumentValue = first.Clone();
                    continue;
                }
            }
            break;
        }

        var normalized = new JsonObject();
        if (argumentValue.ValueKind is JsonValueKind.Undefined or JsonValueKind.Null ||
            argumentValue.ValueKind == JsonValueKind.Array && argumentValue.GetArrayLength() == 0)
        {
            if (allowedNames.Length != 0)
                throw new AgentHostException("provider-arguments-missing", "The selected action requires arguments.");
            return normalized;
        }

        if (argumentValue.ValueKind == JsonValueKind.Object)
        {
            foreach (var property in argumentValue.EnumerateObject())
            {
                var canonicalName = allowedNames.FirstOrDefault(name => string.Equals(name, property.Name, StringComparison.OrdinalIgnoreCase));
                if (canonicalName is null)
                    throw new AgentHostException("provider-argument-unavailable", "The selected action contains an argument outside its current Native catalog.");
                normalized[canonicalName] = JsonNode.Parse(property.Value.GetRawText());
            }
            return normalized;
        }

        if (argumentValue.ValueKind == JsonValueKind.Array && argumentValue.GetArrayLength() == allowedNames.Length)
        {
            for (var index = 0; index < allowedNames.Length; index++)
                normalized[allowedNames[index]] = JsonNode.Parse(argumentValue[index].GetRawText());
            return normalized;
        }

        if (allowedNames.Length == 1)
        {
            normalized[allowedNames[0]] = JsonNode.Parse(argumentValue.GetRawText());
            return normalized;
        }

        throw new AgentHostException("provider-arguments-shape-invalid", "Action arguments do not match the current Native catalog.");
    }

    private static bool IsListedSingleArgumentValue(JsonElement allowedAction, string argumentName, string value)
    {
        if (!allowedAction.TryGetProperty("argumentValues", out var argumentValues) || argumentValues.ValueKind != JsonValueKind.Object)
            return false;
        foreach (var property in argumentValues.EnumerateObject())
        {
            if (!string.Equals(property.Name, argumentName, StringComparison.OrdinalIgnoreCase) || property.Value.ValueKind != JsonValueKind.Array)
                continue;
            return property.Value.EnumerateArray().Any(item => item.ValueKind == JsonValueKind.String && string.Equals(item.GetString(), value, StringComparison.Ordinal));
        }
        return false;
    }

    private static bool IsStoryModeClanNameTextArgument(JsonElement allowedAction, string argumentName, string value) =>
        string.Equals(ReadString(allowedAction, "action"), "submitStoryModeClanName", StringComparison.Ordinal) &&
        string.Equals(argumentName, "text", StringComparison.Ordinal) &&
        !string.IsNullOrWhiteSpace(value) && value.Length <= 64;

    private static JsonElement? FindAllowedAction(JsonElement request, string actionName)
    {
        if (!request.TryGetProperty("allowedActions", out var actions) || actions.ValueKind != JsonValueKind.Array)
            throw new AgentHostException("decision-request-catalog-missing", "The decision request did not contain an action catalog.");
        foreach (var action in actions.EnumerateArray())
            if (string.Equals(ReadString(action, "action"), actionName, StringComparison.Ordinal)) return action.Clone();
        return null;
    }

    private static bool ContainsString(JsonElement parent, string arrayName, string value)
    {
        return parent.TryGetProperty(arrayName, out var array) && array.ValueKind == JsonValueKind.Array &&
            array.EnumerateArray().Any(item => item.ValueKind == JsonValueKind.String && string.Equals(item.GetString(), value, StringComparison.Ordinal));
    }

    private static (int Minimum, int Maximum) GetObserveAgainWaitBounds(JsonElement request)
    {
        var minimum = 1;
        var maximum = 10;
        if (request.TryGetProperty("controlArguments", out var controlArguments) && controlArguments.ValueKind == JsonValueKind.Object &&
            controlArguments.TryGetProperty("observeAgain", out var observeAgain) && observeAgain.ValueKind == JsonValueKind.Object &&
            observeAgain.TryGetProperty("waitSeconds", out var waitSeconds) && waitSeconds.ValueKind == JsonValueKind.Object)
        {
            if (waitSeconds.TryGetProperty("minimum", out var minimumValue) && minimumValue.TryGetInt32(out var parsedMinimum)) minimum = parsedMinimum;
            if (waitSeconds.TryGetProperty("maximum", out var maximumValue) && maximumValue.TryGetInt32(out var parsedMaximum)) maximum = parsedMaximum;
        }
        if (minimum is < 1 or > 10 || maximum is < 1 or > 10 || minimum > maximum)
            throw new AgentHostException("decision-request-control-arguments-invalid", "observeAgain wait bounds must remain within 1-10 seconds and minimum cannot exceed maximum.");
        return (minimum, maximum);
    }

    private static void ValidateDecisionRequest(JsonElement request)
    {
        if (request.ValueKind != JsonValueKind.Object ||
            string.IsNullOrWhiteSpace(ReadString(request, "goal")) ||
            !request.TryGetProperty("observation", out var observation) || observation.ValueKind != JsonValueKind.Object ||
            !request.TryGetProperty("allowedActions", out var actions) || actions.ValueKind != JsonValueKind.Array ||
            !request.TryGetProperty("allowedControls", out var controls) || controls.ValueKind != JsonValueKind.Array)
            throw new AgentHostException("decision-request-invalid", "The decision request requires a goal, observation, and current action/control catalogs.");
    }

    private static void EnsureOnlyProperties(JsonElement value, params string[] allowed)
    {
        var unexpected = value.EnumerateObject()
            .Select(property => property.Name)
            .Where(name => !allowed.Contains(name, StringComparer.Ordinal))
            .Distinct(StringComparer.Ordinal)
            .Take(8)
            .ToArray();
        if (unexpected.Length > 0)
        {
            var safeNames = string.Join(',', unexpected.Select(name => name[..Math.Min(name.Length, 40)]));
            throw new AgentHostException("provider-decision-field-unavailable", "The model returned unsupported field names: " + safeNames + ".");
        }
    }

    private static string ValidateReason(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
            throw new AgentHostException("provider-reason-missing", "The structured decision requires an evidence-based reason.");
        // Reasons/rationales are bounded metadata, not authority for a game action.
        // Providers can exceed the prompt's brevity hint even when the structured action
        // is valid; rejecting that response would discard a separately catalog-validated
        // action. Keep the stored explanation within the same bound without changing the
        // action or its arguments.
        return string.Join(' ', value.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Take(20));
    }

    private static string ValidateOptionalRationale(string? value) =>
        string.IsNullOrWhiteSpace(value) ? string.Empty : ValidateReason(value);

    private static JsonDocument ParseJson(byte[] bytes, string errorCode)
    {
        try { return JsonDocument.Parse(bytes); }
        catch (JsonException exception) { throw new AgentHostException(errorCode, "The local model did not return valid JSON.", exception); }
    }

    private static int ReadIntegerEnvironment(string name, int fallback, int minimum, int maximum)
    {
        var value = Environment.GetEnvironmentVariable(name);
        if (string.IsNullOrWhiteSpace(value)) return fallback;
        if (!int.TryParse(value, NumberStyles.Integer, CultureInfo.InvariantCulture, out var parsed) || parsed < minimum || parsed > maximum)
            throw new AgentHostException("provider-configuration-invalid", $"The configured {name} value is outside its supported range.");
        return parsed;
    }

    private static double? ReadOptionalDoubleEnvironment(string name, double minimum, double maximum)
    {
        var value = Environment.GetEnvironmentVariable(name);
        if (string.IsNullOrWhiteSpace(value)) return null;
        if (!double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out var parsed) || parsed < minimum || parsed > maximum)
            throw new AgentHostException("provider-configuration-invalid", $"The configured {name} value is outside its supported range.");
        return parsed;
    }

    private static string? ReadString(JsonElement element, string name) =>
        element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;

    private static int? ReadNonNegativeInt(JsonElement element, string name) =>
        element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var value) && value.TryGetInt32(out var result) && result >= 0 ? result : null;

    private static bool? ReadBoolean(JsonElement element, string name) =>
        element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var value) && value.ValueKind is JsonValueKind.True or JsonValueKind.False ? value.GetBoolean() : null;
}

internal sealed record OllamaProviderSettings(
    Uri Endpoint,
    string Model,
    bool NativeOllama,
    TimeSpan Timeout,
    int MaxOutputTokens,
    double? Temperature,
    bool? Thinking,
    string? ReasoningEffort,
    string MaxTokenParameter,
    string? ApiKey = null,
    string OutputMode = "auto",
    double MaxEstimatedRunCostCny = 5d,
    int MaxHttpRequestsPerDecision = 8);

internal sealed record ProviderDecisionResult(
    string Status,
    string ModelId,
    int? PromptTokens,
    int? CompletionTokens,
    string FinishReason,
    JsonObject Decision,
    string? RoutedVia = null,
    string ResponseFormatMode = "json_schema",
    double? ReservedCostUpperBoundCny = null,
    int RequestBodyBytes = 0,
    int SystemPromptBytes = 0,
    int UserPayloadBytes = 0,
    int ObservationBytes = 0,
    int? PromptCacheHitTokens = null,
    int? PromptCacheMissTokens = null,
    double? EstimatedCostCny = null,
    int? DeepSeekEstimatedInputTokens = null,
    int? DeepSeekRawRequestTokens = null,
    int? DeepSeekReservedInputTokens = null,
    string? DeepSeekInputTokenEstimator = null,
    string? ProxySelectionSource = null,
    string? ProxyEndpointHostPort = null,
    int? FallbackAttempts = null,
    string? FallbackTrail = null,
    string? ReasoningEffortApplied = null);

internal sealed class AgentHostException : Exception
{
    internal AgentHostException(string code, string message, Exception? innerException = null, int? providerHttpStatus = null,
        string? providerRoute = null, string? providerOutputFormat = null, int? providerRetryAttempts = null, long? providerRetryWaitMilliseconds = null,
        string? providerFailureStage = null, string? providerProxySelectionSource = null, string? providerProxyEndpointHostPort = null, int? providerTimeoutSeconds = null,
        int? providerRequestBodyBytes = null, string? providerTransportErrorType = null, string? providerResponseServer = null,
        string? providerResponseVia = null, string? providerResponseRequestId = null, string? providerRetryAfter = null,
        string? providerErrorBodyKind = null, string? providerErrorContentType = null, string? providerErrorType = null, string? providerErrorCode = null,
        int? providerFallbackAttempts = null, string? providerFallbackTrail = null,
        bool? providerToolCallsPresent = null, int? providerToolCallCount = null, string? providerResponseContentKind = null,
        int? providerResponseContentCharacters = null, string? providerFinishReason = null, string? providerResponseModel = null,
        int? providerResponsePromptTokens = null, int? providerResponseCompletionTokens = null) : base(message, innerException)
    {
        Code = code;
        ProviderHttpStatus = providerHttpStatus;
        ProviderRoute = providerRoute;
        ProviderOutputFormat = providerOutputFormat;
        ProviderRetryAttempts = providerRetryAttempts;
        ProviderRetryWaitMilliseconds = providerRetryWaitMilliseconds;
        ProviderFailureStage = providerFailureStage;
        ProviderProxySelectionSource = providerProxySelectionSource;
        ProviderProxyEndpointHostPort = providerProxyEndpointHostPort;
        ProviderTimeoutSeconds = providerTimeoutSeconds;
        ProviderRequestBodyBytes = providerRequestBodyBytes;
        ProviderTransportErrorType = providerTransportErrorType;
        ProviderResponseServer = providerResponseServer;
        ProviderResponseVia = providerResponseVia;
        ProviderResponseRequestId = providerResponseRequestId;
        ProviderRetryAfter = providerRetryAfter;
        ProviderErrorBodyKind = providerErrorBodyKind;
        ProviderErrorContentType = providerErrorContentType;
        ProviderErrorType = providerErrorType;
        ProviderErrorCode = providerErrorCode;
        ProviderFallbackAttempts = providerFallbackAttempts;
        ProviderFallbackTrail = providerFallbackTrail;
        ProviderToolCallsPresent = providerToolCallsPresent;
        ProviderToolCallCount = providerToolCallCount;
        ProviderResponseContentKind = providerResponseContentKind;
        ProviderResponseContentCharacters = providerResponseContentCharacters;
        ProviderFinishReason = providerFinishReason;
        ProviderResponseModel = providerResponseModel;
        ProviderResponsePromptTokens = providerResponsePromptTokens;
        ProviderResponseCompletionTokens = providerResponseCompletionTokens;
    }

    internal string Code { get; }
    internal int? ProviderHttpStatus { get; }
    internal string? ProviderRoute { get; }
    internal string? ProviderOutputFormat { get; }
    internal int? ProviderRetryAttempts { get; }
    internal long? ProviderRetryWaitMilliseconds { get; }
    internal string? ProviderFailureStage { get; }
    internal string? ProviderProxySelectionSource { get; }
    internal string? ProviderProxyEndpointHostPort { get; }
    internal int? ProviderTimeoutSeconds { get; }
    internal int? ProviderRequestBodyBytes { get; }
    internal string? ProviderTransportErrorType { get; }
    internal string? ProviderResponseServer { get; }
    internal string? ProviderResponseVia { get; }
    internal string? ProviderResponseRequestId { get; }
    internal string? ProviderRetryAfter { get; }
    internal string? ProviderErrorBodyKind { get; }
    internal string? ProviderErrorContentType { get; }
    internal string? ProviderErrorType { get; }
    internal string? ProviderErrorCode { get; }
    internal int? ProviderFallbackAttempts { get; }
    internal string? ProviderFallbackTrail { get; }
    internal bool? ProviderToolCallsPresent { get; }
    internal int? ProviderToolCallCount { get; }
    internal string? ProviderResponseContentKind { get; }
    internal int? ProviderResponseContentCharacters { get; }
    internal string? ProviderFinishReason { get; }
    internal string? ProviderResponseModel { get; }
    internal int? ProviderResponsePromptTokens { get; }
    internal int? ProviderResponseCompletionTokens { get; }
}
