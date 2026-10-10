using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal static class ProviderContractSelfTest
{
    private static readonly Uri FakeEndpoint = new("http://127.0.0.1:11434/v1/chat/completions");
    private const string ValidDecision = "{\"control\":\"done\",\"reason\":\"provider contract smoke passed\"}";

    internal static async Task<object> RunAsync()
    {
        var results = new List<object>();
        var settings = new OllamaProviderSettings(
            FakeEndpoint,
            "test-local-model",
            NativeOllama: false,
            Timeout: TimeSpan.FromSeconds(2),
            MaxOutputTokens: 128,
            Temperature: 0,
            Thinking: false,
            ReasoningEffort: "none",
            MaxTokenParameter: "max_completion_tokens");

        var successHandler = new StubHandler((_, _) => Task.FromResult(JsonResponse(BuildChatResponse(ValidDecision, "stop"))));
        using (var successClient = new HttpClient(successHandler) { Timeout = settings.Timeout })
        using (var provider = new OllamaNativeProvider(settings, successClient))
        using (var request = JsonDocument.Parse(BuildDecisionRequest()))
        {
            var result = await provider.DecideAsync(request.RootElement, CancellationToken.None);
            if (result.Status != "completed" || result.Decision["done"]?.GetValue<bool>() != true)
                throw new AgentHostException("provider-self-test-success-failed", "Provider contract did not normalize the valid stop decision.");
            ValidateRequestShape(successHandler.LastRequestBody, successHandler.LastRequestUri, successHandler.LastAuthorization);
            results.Add(new { scenario = "request-shape-and-valid-decision", passed = true, result.ModelId });
        }

        var nativeSettings = settings with { NativeOllama = true, Endpoint = new Uri("http://127.0.0.1:11434/api/chat") };
        var nativeHandler = new StubHandler((_, _) => Task.FromResult(JsonResponse(JsonSerializer.Serialize(new
        {
            model = "test-local-model",
            message = new { role = "assistant", content = ValidDecision },
            done = true,
            done_reason = "stop",
            prompt_eval_count = 24,
            eval_count = 12
        }))));
        using (var nativeClient = new HttpClient(nativeHandler) { Timeout = nativeSettings.Timeout })
        using (var provider = new OllamaNativeProvider(nativeSettings, nativeClient))
        using (var request = JsonDocument.Parse(BuildDecisionRequest()))
        {
            var result = await provider.DecideAsync(request.RootElement, CancellationToken.None);
            if (result.Status != "completed" || result.Decision["done"]?.GetValue<bool>() != true)
                throw new AgentHostException("provider-self-test-native-failed", "Native Ollama response was not normalized.");
            ValidateNativeRequestShape(nativeHandler.LastRequestBody, nativeHandler.LastRequestUri, nativeHandler.LastAuthorization);
            results.Add(new { scenario = "native-ollama-request-and-response", passed = true });
        }

        await ExpectProviderErrorAsync(settings, "not-json", "provider-response-invalid-json", "malformed-http-json");
        results.Add(new { scenario = "malformed-http-json", passed = true });
        await ExpectProviderErrorAsync(settings, BuildChatResponse("not-json", "stop"), "provider-decision-invalid-json", "malformed-decision-json");
        results.Add(new { scenario = "malformed-decision-json", passed = true });
        await ExpectProviderErrorAsync(settings, BuildChatResponse(ValidDecision, "length"), "provider-response-truncated", "truncated-model-response");
        results.Add(new { scenario = "truncated-model-response", passed = true });
        await ExpectProviderErrorAsync(settings, BuildChatResponse("{\"action\":\"invented_action\",\"arguments\":{},\"rationale\":\"bad\"}", "stop"), "provider-action-unavailable", "action-outside-catalog");
        results.Add(new { scenario = "action-outside-catalog", passed = true });
        await ExpectProviderErrorAsync(settings, statusCode: HttpStatusCode.ServiceUnavailable, expectedCode: "provider-http-error", scenario: "http-unavailable");
        results.Add(new { scenario = "http-unavailable", passed = true });
        await ExpectTimeoutAsync(settings);
        results.Add(new { scenario = "provider-timeout", passed = true });

        return new
        {
            passed = true,
            modelCalls = 0,
            nativeCommands = 0,
            scenarios = results
        };
    }

    private static async Task ExpectProviderErrorAsync(
        OllamaProviderSettings settings,
        string responseBody,
        string expectedCode,
        string scenario)
    {
        await ExpectProviderErrorAsync(settings, JsonResponse(responseBody), expectedCode, scenario);
    }

    private static async Task ExpectProviderErrorAsync(
        OllamaProviderSettings settings,
        HttpResponseMessage response,
        string expectedCode,
        string scenario)
    {
        var handler = new StubHandler((_, _) => Task.FromResult(response));
        using var client = new HttpClient(handler) { Timeout = settings.Timeout };
        using var provider = new OllamaNativeProvider(settings, client);
        using var request = JsonDocument.Parse(BuildDecisionRequest());
        try
        {
            await provider.DecideAsync(request.RootElement, CancellationToken.None);
        }
        catch (AgentHostException exception) when (exception.Code == expectedCode)
        {
            ValidateLocalEndpoint(handler.LastRequestUri);
            return;
        }
        throw new AgentHostException("provider-self-test-negative-failed", $"Provider negative case '{scenario}' did not return {expectedCode}.");
    }

    private static async Task ExpectProviderErrorAsync(
        OllamaProviderSettings settings,
        HttpStatusCode statusCode,
        string expectedCode,
        string scenario)
    {
        var handler = new StubHandler((_, _) => Task.FromResult(new HttpResponseMessage(statusCode)));
        using var client = new HttpClient(handler) { Timeout = settings.Timeout };
        using var provider = new OllamaNativeProvider(settings, client);
        using var request = JsonDocument.Parse(BuildDecisionRequest());
        try
        {
            await provider.DecideAsync(request.RootElement, CancellationToken.None);
        }
        catch (AgentHostException exception) when (exception.Code == expectedCode)
        {
            ValidateLocalEndpoint(handler.LastRequestUri);
            return;
        }
        throw new AgentHostException("provider-self-test-negative-failed", $"Provider negative case '{scenario}' did not return {expectedCode}.");
    }

    private static async Task ExpectTimeoutAsync(OllamaProviderSettings settings)
    {
        var timeoutSettings = settings with { Timeout = TimeSpan.FromMilliseconds(30) };
        var handler = new StubHandler(async (_, cancellationToken) =>
        {
            await Task.Delay(TimeSpan.FromSeconds(2), cancellationToken);
            return JsonResponse(BuildChatResponse(ValidDecision, "stop"));
        });
        using var client = new HttpClient(handler) { Timeout = timeoutSettings.Timeout };
        using var provider = new OllamaNativeProvider(timeoutSettings, client);
        using var request = JsonDocument.Parse(BuildDecisionRequest());
        try
        {
            await provider.DecideAsync(request.RootElement, CancellationToken.None);
        }
        catch (AgentHostException exception) when (exception.Code == "provider-timeout")
        {
            ValidateLocalEndpoint(handler.LastRequestUri);
            return;
        }
        throw new AgentHostException("provider-self-test-timeout-failed", "Provider timeout was not bounded.");
    }

    private static string BuildDecisionRequest() => """
        {
          "goal": "This is a local provider protocol test; stop after validating the schema.",
          "observation": { "scope": "provider-contract-test", "state": { "gameState": "MapState" } },
          "allowedActions": [],
          "allowedControls": ["done"]
        }
        """;

    private static string BuildChatResponse(string content, string finishReason) => JsonSerializer.Serialize(new
    {
        model = "test-local-model",
        choices = new[]
        {
            new
            {
                index = 0,
                message = new { role = "assistant", content, refusal = (string?)null },
                finish_reason = finishReason
            }
        },
        usage = new { prompt_tokens = 24, completion_tokens = 12, total_tokens = 36 }
    });

    private static HttpResponseMessage JsonResponse(string body) => new(HttpStatusCode.OK)
    {
        Content = new StringContent(body, new UTF8Encoding(false), "application/json")
    };

    private static void ValidateRequestShape(string? body, Uri? uri, AuthenticationHeaderValue? authorization)
    {
        if (string.IsNullOrWhiteSpace(body) || uri != FakeEndpoint || authorization is not null)
            throw new AgentHostException("provider-self-test-request-failed", "Provider request was missing, not loopback, or unexpectedly carried authorization.");
        using var document = JsonDocument.Parse(body);
        var root = document.RootElement;
        if (root.GetProperty("model").GetString() != "test-local-model" ||
            root.GetProperty("response_format").GetProperty("type").GetString() != "json_object" ||
            root.GetProperty("max_completion_tokens").GetInt32() != 128 ||
            root.GetProperty("store").GetBoolean())
            throw new AgentHostException("provider-self-test-request-failed", "Provider request did not retain the bounded local structured-output contract.");
    }

    private static void ValidateLocalEndpoint(Uri? uri)
    {
        if (uri is null || !uri.IsLoopback || uri.Scheme != "http")
            throw new AgentHostException("provider-self-test-endpoint-failed", "Provider attempted to use a non-local HTTP endpoint.");
    }

    private static void ValidateNativeRequestShape(string? body, Uri? uri, AuthenticationHeaderValue? authorization)
    {
        if (string.IsNullOrWhiteSpace(body) || uri?.AbsolutePath != "/api/chat" || authorization is not null)
            throw new AgentHostException("provider-self-test-native-request-failed", "Native Ollama request shape or local endpoint is invalid.");
        using var document = JsonDocument.Parse(body);
        var root = document.RootElement;
        if (root.GetProperty("model").GetString() != "test-local-model" ||
            root.GetProperty("stream").GetBoolean() || root.GetProperty("format").GetString() != "json" ||
            root.GetProperty("options").GetProperty("num_predict").GetInt32() != 128)
            throw new AgentHostException("provider-self-test-native-request-failed", "Native Ollama request did not preserve the bounded structured-output contract.");
    }

    private sealed class StubHandler : HttpMessageHandler
    {
        private readonly Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> _responseFactory;
        internal string? LastRequestBody { get; private set; }
        internal Uri? LastRequestUri { get; private set; }
        internal AuthenticationHeaderValue? LastAuthorization { get; private set; }

        internal StubHandler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> responseFactory) => _responseFactory = responseFactory;

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            LastRequestUri = request.RequestUri;
            LastAuthorization = request.Headers.Authorization;
            LastRequestBody = request.Content is null ? null : await request.Content.ReadAsStringAsync(cancellationToken);
            return await _responseFactory(request, cancellationToken);
        }
    }
}
