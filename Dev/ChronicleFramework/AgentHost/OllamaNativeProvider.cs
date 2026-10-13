using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal sealed class OllamaNativeProvider : IAgentHostDecisionProvider
{
    private const int MaxRequestBytes = 512 * 1024;
    private const int MaxResponseBytes = 1024 * 1024;
    private static readonly JsonSerializerOptions JsonOptions = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
    private readonly OllamaProviderSettings _settings;
    private readonly HttpClient _client;
    private readonly bool _ownsClient;
    private DateTimeOffset _lastProviderRequestUtc;
    private string? _lastProviderRoute;
    internal string ModelId => _settings.Model;
    internal int MaxOutputTokens => _settings.MaxOutputTokens;
    internal string ConfigurationSource { get; }

    string IAgentHostDecisionProvider.ModelId => ModelId;
    string IAgentHostDecisionProvider.ConfigurationSource => ConfigurationSource;

    internal OllamaNativeProvider(OllamaProviderSettings settings, HttpClient? client = null, string configurationSource = "direct")
    {
        _settings = settings with { MaxTokenParameter = ResolveMaxTokenParameter(settings.Model, settings.MaxTokenParameter) };
        _client = client ?? new HttpClient { Timeout = settings.Timeout };
        _ownsClient = client is null;
        ConfigurationSource = configurationSource;
    }

    internal static OllamaNativeProvider FromEnvironment()
    {
        var protocol = Environment.GetEnvironmentVariable("CHRONICLE_LLM_PROTOCOL");
        if (string.IsNullOrWhiteSpace(protocol)) protocol = "openai-compatible";
        var nativeOllama = string.Equals(protocol, "ollama-native", StringComparison.OrdinalIgnoreCase);
        if (!nativeOllama && !string.Equals(protocol, "openai-compatible", StringComparison.OrdinalIgnoreCase))
            throw new AgentHostException("provider-protocol-unsupported", "This Host stage only permits the configured local Ollama-compatible provider.");

        var baseUrl = Environment.GetEnvironmentVariable("CHRONICLE_LLM_BASE_URL");
        var model = Environment.GetEnvironmentVariable("CHRONICLE_LLM_MODEL");
        if (string.IsNullOrWhiteSpace(baseUrl) || string.IsNullOrWhiteSpace(model))
            throw new AgentHostException("provider-configuration-missing", "Local Ollama URL and model configuration are required.");
        if (model.Length > 160)
            throw new AgentHostException("provider-model-invalid", "Configured model identifier is too long.");

        if (!Uri.TryCreate(baseUrl, UriKind.Absolute, out var baseUri) || baseUri.Scheme is not ("http" or "https") || !baseUri.IsLoopback)
            throw new AgentHostException("provider-endpoint-invalid", "The Ollama endpoint must be a local loopback HTTP(S) URL.");
        var endpointBuilder = new UriBuilder(baseUri);
        endpointBuilder.Path = nativeOllama ? "/api/chat" : endpointBuilder.Path.TrimEnd('/') + "/chat/completions";
        var endpoint = endpointBuilder.Uri;

        var timeoutSeconds = ReadIntegerEnvironment("CHRONICLE_LLM_TIMEOUT_SECONDS", 60, 5, 240);
        var maxOutputTokens = ReadIntegerEnvironment("CHRONICLE_LLM_MAX_TOKENS", 256, 64, 4096);
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
            ReadApiKey()));
    }

    internal static OllamaNativeProvider FromConfiguredProfile()
    {
        if (Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE") is string harnessMode &&
            (string.Equals(harnessMode, "visual-capture", StringComparison.Ordinal) || string.Equals(harnessMode, "agent-host-lifecycle-test", StringComparison.Ordinal)) &&
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
            return FromProfile(AgentProviderProfile.Parse(configuration, "mcm-start-request"));
        return FromConfiguredProfile();
    }

    private static OllamaNativeProvider FromProfile(AgentProviderProfile profile)
    {
        var endpoint = new Uri(profile.BaseUrl.TrimEnd('/') + "/chat/completions", UriKind.Absolute);
        return new OllamaNativeProvider(new OllamaProviderSettings(
            endpoint,
            profile.ModelId,
            NativeOllama: false,
            Timeout: TimeSpan.FromSeconds(ReadIntegerEnvironment("CHRONICLE_LLM_TIMEOUT_SECONDS", 180, 5, 240)),
            MaxOutputTokens: ReadIntegerEnvironment("CHRONICLE_LLM_MAX_TOKENS", 512, 64, 4096),
            Temperature: 0d,
            Thinking: null,
            ReasoningEffort: "none",
            MaxTokenParameter: "max_completion_tokens",
            ApiKey: ReadApiKey()),
            configurationSource: profile.Source);
    }

    private static string? ReadApiKey()
    {
        var key = Environment.GetEnvironmentVariable("CHRONICLE_LLM_API_KEY");
        if (string.IsNullOrWhiteSpace(key)) key = Environment.GetEnvironmentVariable("FREELLMAPI_API_KEY");
        return string.IsNullOrWhiteSpace(key) ? null : key.Trim();
    }

    internal Task<ProviderDecisionResult> DecideAsync(JsonElement request, CancellationToken cancellationToken) =>
        DecideAsync(request, AgentHostDecisionCycle.CampaignSystemPrompt, cancellationToken);

    Task<ProviderDecisionResult> IAgentHostDecisionProvider.DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken) =>
        DecideAsync(request, systemPrompt, cancellationToken);

    Task IAgentHostDecisionProvider.CheckConfiguredModelAsync(CancellationToken cancellationToken) => CheckConfiguredModelAsync(cancellationToken);

    internal async Task CheckConfiguredModelAsync(CancellationToken cancellationToken)
    {
        var endpointPath = _settings.Endpoint.AbsolutePath;
        const string completionSuffix = "/chat/completions";
        if (!endpointPath.EndsWith(completionSuffix, StringComparison.OrdinalIgnoreCase))
            throw new AgentHostException("provider-health-endpoint-invalid", "The configured local provider URL does not have the supported chat-completions path.");

        var modelsUriBuilder = new UriBuilder(_settings.Endpoint)
        {
            Path = endpointPath[..^completionSuffix.Length] + "/models",
            Query = string.Empty,
            Fragment = string.Empty
        };
        if (!string.IsNullOrWhiteSpace(_settings.ApiKey))
            modelsUriBuilder.Query = "available=true";
        if (IsFreeLlmApi(_settings.Endpoint) && string.IsNullOrWhiteSpace(_settings.ApiKey))
            throw new AgentHostException("provider-api-key-missing", "FreeLLMAPI requires its unified API key in FREELLMAPI_API_KEY or CHRONICLE_LLM_API_KEY.");

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(8));
        try
        {
            using var healthRequest = new HttpRequestMessage(HttpMethod.Get, modelsUriBuilder.Uri);
            AddAuthorization(healthRequest);
            using var response = await _client.SendAsync(healthRequest, HttpCompletionOption.ResponseContentRead, timeout.Token);
            if (!response.IsSuccessStatusCode)
                throw new AgentHostException("provider-unavailable", "The local model service rejected its model-list health check.");

            var bytes = await response.Content.ReadAsByteArrayAsync(timeout.Token);
            if (bytes.Length is <= 0 or > 128 * 1024)
                throw new AgentHostException("provider-health-response-invalid", "The local model service returned an empty or oversized model-list response.");

            using var document = JsonDocument.Parse(bytes);
            if (!document.RootElement.TryGetProperty("data", out var models) || models.ValueKind != JsonValueKind.Array)
                throw new AgentHostException("provider-health-response-invalid", "The local model service returned an unsupported model-list response.");

            var modelFound = models.EnumerateArray().Any(model => string.Equals(ReadString(model, "id"), _settings.Model, StringComparison.Ordinal));
            if (!modelFound)
                throw new AgentHostException("provider-model-unavailable", "The configured model is not listed by the local model service.");
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
            throw new AgentHostException("provider-unavailable", "The configured local model service could not be reached.", exception);
        }
        catch (JsonException exception)
        {
            throw new AgentHostException("provider-health-response-invalid", "The local model service returned malformed model-list data.", exception);
        }
    }

    internal async Task<ProviderDecisionResult> DecideAsync(JsonElement request, string systemPrompt, CancellationToken cancellationToken)
    {
        ValidateDecisionRequest(request);
        var userContent = JsonSerializer.Serialize(request, JsonOptions);
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
            payload["response_format"] = useJsonObjectCompatibilityMode
                ? new { type = "json_object" }
                : new { type = "json_schema", json_schema = new { schema = BuildDecisionSchema(request) } };
            payload[_settings.MaxTokenParameter] = _settings.MaxOutputTokens;
            if (_settings.Thinking.HasValue) payload["thinking"] = new { type = _settings.Thinking.Value ? "enabled" : "disabled" };
            if (!string.IsNullOrWhiteSpace(_settings.ReasoningEffort) &&
                !string.Equals(_settings.ReasoningEffort, "none", StringComparison.OrdinalIgnoreCase) && _settings.Thinking != false)
                payload["reasoning_effort"] = _settings.ReasoningEffort;
            if (_settings.Temperature.HasValue) payload["temperature"] = _settings.Temperature.Value;
        }

        var body = JsonSerializer.Serialize(payload, JsonOptions);
        if (Encoding.UTF8.GetByteCount(body) > MaxRequestBytes)
            throw new AgentHostException("provider-request-too-large", "The structured model request exceeds the Host size limit.");

        using var requestTimeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        requestTimeout.CancelAfter(_settings.Timeout);
        var transientProviderRetriesUsed = 0;
        async Task<HttpResponseMessage> SendProviderRequestAsync(string requestBody)
        {
            await WaitForProviderRateWindowAsync(cancellationToken);
            using var message = new HttpRequestMessage(HttpMethod.Post, _settings.Endpoint)
            {
                Content = new StringContent(requestBody, new UTF8Encoding(false), "application/json")
            };
            AddAuthorization(message);
            try
            {
                return await _client.SendAsync(message, HttpCompletionOption.ResponseHeadersRead, requestTimeout.Token);
            }
            catch (OperationCanceledException exception) when (!cancellationToken.IsCancellationRequested)
            {
                throw new AgentHostException("provider-timeout", "The model provider did not respond within its configured timeout.", exception);
            }
            catch (HttpRequestException exception)
            {
                throw new AgentHostException("provider-unreachable", "The configured model provider could not be reached.", exception);
            }
        }

        async Task<HttpResponseMessage> SendProviderRequestWithTransientRetryAsync(string requestBody)
        {
            var response = await SendProviderRequestAsync(requestBody);
            while (transientProviderRetriesUsed < 2 && ShouldRetryTransientFreeLlmApiFailure(_settings.Endpoint, response))
            {
                var retryDelaySeconds = transientProviderRetriesUsed == 0 ? 5 : 15;
                transientProviderRetriesUsed++;
                var fallbackTrail = ReadResponseHeader(response, "X-Fallback-Trail");
                if (!string.IsNullOrWhiteSpace(fallbackTrail) && fallbackTrail.Contains("ovh/", StringComparison.OrdinalIgnoreCase))
                    _lastProviderRoute = "ovh";
                response.Dispose();
                await Task.Delay(TimeSpan.FromSeconds(retryDelaySeconds), cancellationToken);
                response = await SendProviderRequestAsync(requestBody);
            }
            return response;
        }

        var responseFormatMode = _settings.NativeOllama
            ? "ollama-native"
            : useJsonObjectCompatibilityMode ? "json_object_compatibility" : "json_schema";
        var response = await SendProviderRequestWithTransientRetryAsync(body);
        if (!_settings.NativeOllama && responseFormatMode == "json_schema" && ShouldRetryWithJsonObject(_settings.Endpoint, response))
        {
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
                throw new AgentHostException("provider-http-error", BuildHttpFailureMessage(response));

            if (response.Content.Headers.ContentLength is > MaxResponseBytes)
                throw new AgentHostException("provider-response-too-large", "The local model response exceeds the Host size limit.");

            byte[] responseBytes;
            try
            {
                responseBytes = await response.Content.ReadAsByteArrayAsync(requestTimeout.Token);
            }
            catch (OperationCanceledException exception) when (!cancellationToken.IsCancellationRequested)
            {
                throw new AgentHostException("provider-timeout", "The local model provider response exceeded its configured timeout.", exception);
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
                if (choices.Length != 1 || choices[0].ValueKind != JsonValueKind.Object ||
                    !choices[0].TryGetProperty("message", out var messageElement) || messageElement.ValueKind != JsonValueKind.Object ||
                    !messageElement.TryGetProperty("content", out var contentElement) || contentElement.ValueKind != JsonValueKind.String)
                    throw new AgentHostException("provider-content-missing", "The local OpenAI-compatible provider did not return one structured message.");
                if (!string.IsNullOrWhiteSpace(ReadString(messageElement, "refusal")))
                    throw new AgentHostException("provider-refused", "The local model provider refused the decision request.");
                finishReason = ReadString(choices[0], "finish_reason");
                responseModel = ReadString(root, "model");
                content = contentElement.GetString();
                var usage = root.TryGetProperty("usage", out var usageValue) ? usageValue : default;
                promptTokens = ReadNonNegativeInt(usage, "prompt_tokens");
                completionTokens = ReadNonNegativeInt(usage, "completion_tokens");
            }
            if (finishReason is "length" or "max_tokens")
                throw new AgentHostException("provider-response-truncated", "The local model provider reached its output-token limit.");
            if (string.IsNullOrWhiteSpace(content))
                throw new AgentHostException("provider-content-empty", "The local model provider returned empty decision content.");
            using var decisionDocument = ParseJson(Encoding.UTF8.GetBytes(content), "provider-decision-invalid-json");
            var decision = NormalizeDecision(decisionDocument.RootElement, decisionRequestSnapshot.RootElement);

            var routedVia = ReadResponseHeader(response, "X-Routed-Via");
            if (!string.IsNullOrWhiteSpace(routedVia)) _lastProviderRoute = routedVia;
            return new ProviderDecisionResult(
                "completed",
                responseModel ?? _settings.Model,
                promptTokens,
                completionTokens,
                finishReason ?? (ReadBoolean(root, "done") == true ? "stop" : "unknown"),
                decision,
                routedVia,
                responseFormatMode);
        }
    }

    private static bool IsFreeLlmApi(Uri endpoint) => endpoint.Port == 31415 && (endpoint.Host is "127.0.0.1" or "localhost");

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

    private string BuildHttpFailureMessage(HttpResponseMessage response)
    {
        var providerName = IsFreeLlmApi(_settings.Endpoint) ? "FreeLLMAPI" : "model provider";
        var details = new List<string>();
        var routedVia = ReadResponseHeader(response, "X-Routed-Via");
        var fallbackAttempts = ReadResponseHeader(response, "X-Fallback-Attempts");
        var fallbackTrail = ReadResponseHeader(response, "X-Fallback-Trail");
        if (!string.IsNullOrWhiteSpace(routedVia)) details.Add("routedVia=" + routedVia);
        if (!string.IsNullOrWhiteSpace(fallbackAttempts)) details.Add("fallbackAttempts=" + fallbackAttempts);
        if (!string.IsNullOrWhiteSpace(fallbackTrail)) details.Add("fallbackTrail=" + fallbackTrail);
        return $"{providerName} returned HTTP {(int)response.StatusCode}." +
               (details.Count == 0 ? string.Empty : " " + string.Join("; ", details));
    }

    internal static bool ShouldRetryWithJsonObject(Uri endpoint, HttpResponseMessage response)
    {
        if (!IsFreeLlmApi(endpoint) || response.StatusCode is not (HttpStatusCode.BadRequest or HttpStatusCode.UnprocessableEntity or HttpStatusCode.BadGateway)) return false;
        return ReadResponseHeader(response, "X-Fallback-Trail")?.Contains("provider_bad_request", StringComparison.OrdinalIgnoreCase) == true;
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

    private bool UsesJsonObjectCompatibilityMode() =>
        IsFreeLlmApi(_settings.Endpoint) &&
        IsMistralSmall32(_settings.Model);

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
                    var valueType = argumentName switch
                    {
                        "ConfirmPartySizeWarning" => "boolean",
                        "Days" or "Count" or "VolunteerSlot" or "Amount" => "integer",
                        _ => "string"
                    };
                    var argumentSchema = new JsonObject { ["type"] = valueType };
                    if (action.TryGetProperty("argumentValues", out var argumentValues) &&
                        argumentValues.ValueKind == JsonValueKind.Object && argumentValues.TryGetProperty(argumentName, out var values) &&
                        values.ValueKind == JsonValueKind.Array &&
                        ((valueType == "string" && values.EnumerateArray().All(item => item.ValueKind == JsonValueKind.String)) ||
                         (valueType == "integer" && values.EnumerateArray().All(item => item.ValueKind == JsonValueKind.Number && item.TryGetInt32(out _))) ||
                         (valueType == "boolean" && values.EnumerateArray().All(item => item.ValueKind is JsonValueKind.True or JsonValueKind.False))))
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
                        ["action"] = new JsonObject { ["type"] = "string", ["const"] = actionName },
                        ["arguments"] = new JsonObject { ["type"] = "object", ["properties"] = argumentProperties, ["required"] = requiredArgumentNames, ["additionalProperties"] = false },
                        ["rationale"] = new JsonObject { ["type"] = "string", ["maxLength"] = 64 }
                    },
                    ["required"] = new JsonArray("action", "arguments", "rationale"),
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
                    ["control"] = new JsonObject { ["type"] = "string", ["const"] = controlName }
                };
                var required = new JsonArray("control");
                if (string.Equals(controlName, "observeAgain", StringComparison.Ordinal))
                {
                    properties["waitSeconds"] = new JsonObject { ["type"] = "integer", ["minimum"] = 1, ["maximum"] = 10 };
                    required.Add("waitSeconds");
                }
                properties["reason"] = new JsonObject { ["type"] = "string", ["maxLength"] = 64 };
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
        return new JsonObject { ["oneOf"] = alternatives };
    }

    internal static JsonObject NormalizeDecision(JsonElement decision, JsonElement request)
    {
        if (decision.ValueKind != JsonValueKind.Object)
            throw new AgentHostException("provider-decision-shape-invalid", "The local model decision must be a JSON object.");

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
            if (waitValue.ValueKind != JsonValueKind.Number || !waitValue.TryGetInt32(out var waitSeconds) || waitSeconds is < 1 or > 10)
                throw new AgentHostException("provider-control-arguments-invalid", "observeAgain must request an integer wait from 1 to 10 seconds.");
            return new JsonObject
            {
                ["observeAgain"] = true,
                ["waitSeconds"] = waitSeconds,
                ["reason"] = ValidateReason(ReadString(decision, "reason") ?? ReadString(decision, "rationale"))
            };
        }

        if (hasControl && controlName is "supportedMapArrivalGoal" or "supportedVillageToolsQuestGoal" or "unsupportedGoal")
        {
            EnsureOnlyProperties(decision, "control", "reason", "rationale");
            var classificationPhase = ReadBoolean(request, "goalScopeClassificationRequired") == true &&
                request.TryGetProperty("allowedActions", out var classificationActions) &&
                classificationActions.ValueKind == JsonValueKind.Array && classificationActions.GetArrayLength() == 0;
            if (!ContainsString(request, "allowedControls", controlName) && !classificationPhase)
            {
                var supportedListed = ContainsString(request, "allowedControls", "supportedMapArrivalGoal");
                var supportedQuestListed = ContainsString(request, "allowedControls", "supportedVillageToolsQuestGoal");
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
                    $"Goal classification is not currently listed in the decision catalog (catalog={controlsKind}[{controlsItems}], supported={supportedListed}, supportedQuest={supportedQuestListed}, unsupported={unsupportedListed}, gate={classificationRequired}, actions={actionCount}, iteration={iteration}).");
            }
            return new JsonObject
            {
                ["goalClassification"] = controlName switch
                {
                    "supportedMapArrivalGoal" => "supported-map-arrival",
                    "supportedVillageToolsQuestGoal" => "supported-village-tools-quest",
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
                ["rationale"] = ValidateReason(ReadString(decision, "rationale") ?? ReadString(decision, "reason"))
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
            ["rationale"] = ValidateReason(ReadString(decision, "rationale") ?? ReadString(decision, "reason"))
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
                using var parsed = ParseJson(Encoding.UTF8.GetBytes(argumentValue.GetString()!), "provider-arguments-invalid-json");
                argumentValue = parsed.RootElement.Clone();
                continue;
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
        if (value.EnumerateObject().Any(property => !allowed.Contains(property.Name, StringComparer.Ordinal)))
            throw new AgentHostException("provider-decision-field-unavailable", "The local model returned a field outside the decision contract.");
    }

    private static string ValidateReason(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
            throw new AgentHostException("provider-reason-missing", "The structured decision requires an evidence-based reason.");
        if (value.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Length > 20)
            throw new AgentHostException("provider-reason-too-long", "The decision reason exceeds the 20-word contract.");
        return value.Trim();
    }

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
    string? ApiKey = null);

internal sealed record ProviderDecisionResult(
    string Status,
    string ModelId,
    int? PromptTokens,
    int? CompletionTokens,
    string FinishReason,
    JsonObject Decision,
    string? RoutedVia = null,
    string ResponseFormatMode = "json_schema");

internal sealed class AgentHostException : Exception
{
    internal AgentHostException(string code, string message, Exception? innerException = null) : base(message, innerException) => Code = code;
    internal string Code { get; }
}
