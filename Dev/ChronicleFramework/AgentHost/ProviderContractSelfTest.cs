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
        var villageQuestPrompt = AgentHostDecisionCycle.VillageToolsQuestSystemPrompt;
        if (!villageQuestPrompt.Contains("talkToSettlementHero", StringComparison.Ordinal) ||
            !villageQuestPrompt.Contains("only before a conversation is open, and only if talkToSettlementHero is currently listed", StringComparison.Ordinal) ||
            !villageQuestPrompt.Contains("conversation is already open: never talk to that hero again", StringComparison.Ordinal) ||
            !villageQuestPrompt.Contains("Once the Journal confirms the Quest is active and tools are still owed, leave the Village and travel to a Town", StringComparison.Ordinal) ||
            !villageQuestPrompt.Contains("never repeat the rejected action/control", StringComparison.Ordinal) ||
            villageQuestPrompt.Contains("quickConversation", StringComparison.OrdinalIgnoreCase))
            throw new AgentHostException("village-tools-prompt-native-action-id-mismatch", "The quest prompt must name the exact Native contact action and prevent stale contact/decision repetition after conversation opens or feedback rejects an action.");
        results.Add(new { scenario = "village-tools-prompt-uses-exact-native-action-id", passed = true });
        results.AddRange(NativeMailboxClient.RunVillageToolsQuestActionContractSelfTests());
        try { results.AddRange(AgentHostVillageToolsQuestPolicy.RunContractSelfTests()); }
        catch (Exception exception) { throw new AgentHostException("village-tools-policy-self-test-failed", exception.GetType().Name + ": " + exception.Message, exception); }
        try { results.AddRange(await AgentHostVillageToolsQuestLoop.RunContractSelfTestsAsync()); }
        catch (Exception exception) { throw new AgentHostException("village-tools-loop-self-test-failed", exception.GetType().Name + ": " + exception.Message, exception); }
        results.AddRange(AgentHostCampaignLoop.RunContractSelfTests());
        results.AddRange(await AgentHostCampaignLoop.RunTransportSelfTestsAsync());
        results.AddRange(await Program.RunParentProcessContractSelfTestsAsync());
        var readyLine = AgentHostReadyProtocol.Format(321, "mcm-test", "0.1.0+test");
        if (!AgentHostReadyProtocol.TryParse(readyLine, out var readyPid, out var readyRunId, out var readyVersion) ||
            readyPid != 321 || readyRunId != "mcm-test" || readyVersion != "0.1.0+test" ||
            AgentHostReadyProtocol.TryParse(readyLine.Replace("|1|", "|2|"), out _, out _, out _) ||
            AgentHostReadyProtocol.TryParse(readyLine + "|extra", out _, out _, out _))
            throw new AgentHostException("host-ready-protocol-self-test-failed", "Shared Mod/Host readiness framing failed identity round-trip or accepted an invalid frame.");
        results.Add(new { scenario = "shared-mod-host-ready-identity-roundtrip-and-invalid-frame-rejection", passed = true });
        var sessionMailboxRoot = Path.Combine(Path.GetTempPath(), "ChronicleNativeSessionTest-" + Guid.NewGuid().ToString("N"));
        try
        {
            var sessionClient = new NativeMailboxClient(sessionMailboxRoot, TimeSpan.FromSeconds(1), 321, "session-a");
            using var matching = JsonDocument.Parse("{\"protocolVersion\":1,\"commandId\":\"test\",\"action\":\"state\",\"status\":\"completed\",\"processId\":321,\"nativeSessionId\":\"session-a\"}");
            sessionClient.ValidateResponse(matching.RootElement, "test", "state", "completed");
            foreach (var mismatch in new[] { (ProcessId: 322, SessionId: "session-a", Code: "native-response-process-mismatch"), (ProcessId: 321, SessionId: "session-b", Code: "native-response-session-mismatch") })
            {
                using var response = JsonDocument.Parse(JsonSerializer.Serialize(new { protocolVersion = 1, commandId = "test", action = "state", status = "completed", processId = mismatch.ProcessId, nativeSessionId = mismatch.SessionId }));
                try
                {
                    sessionClient.ValidateResponse(response.RootElement, "test", "state", "completed");
                    throw new AgentHostException("native-session-self-test-mismatch-accepted", "The Host accepted a response from a different loaded Native session.");
                }
                catch (AgentHostException exception) when (exception.Code == mismatch.Code) { }
            }
            results.Add(new { scenario = "native-mailbox-binds-every-response-to-game-process-and-loaded-session", passed = true });
        }
        finally
        {
            Directory.Delete(Path.Combine(sessionMailboxRoot, "responses"));
            Directory.Delete(sessionMailboxRoot);
        }
        if (!await Program.WaitForStopSignalAsync(new StringReader("not-json\n{\"control\":\"stop\"}\n"), CancellationToken.None) ||
            await Program.WaitForStopSignalAsync(new StringReader("{\"control\":\"pause\"}\n"), CancellationToken.None))
            throw new AgentHostException("agent-host-stop-control-self-test-failed", "Only an explicit stop control line may cancel the persistent Campaign Host.");
        results.Add(new { scenario = "agent-host-stdin-accepts-only-explicit-stop-control", passed = true });
        var documents = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
        var expectedGlobalProfilePath = Path.Combine(documents, "Mount and Blade II Bannerlord", "Configs", "ModSettings", "Global", "ChronicleFramework", "ChronicleAgentSettings.json");
        if (!string.Equals(AgentProviderProfile.GetDefaultPath(), expectedGlobalProfilePath, StringComparison.OrdinalIgnoreCase))
            throw new AgentHostException("provider-profile-path-self-test-failed", "The Host global profile path does not match the MCM Global folder/id convention.");
        results.Add(new { scenario = "host-default-path-matches-mcm-global-folder-and-id", passed = true });

        using (var validProfile = JsonDocument.Parse("{\"OllamaBaseUrl\":\"http://127.0.0.1:31415/v1\",\"ModelId\":\"auto\",\"schemaVersion\":0,\"LegacySetting\":true,\"CampaignGoal\":\"older-MCM-key\"}"))
        {
            var profile = AgentProviderProfile.Parse(validProfile.RootElement);
            if (profile.BaseUrl != "http://127.0.0.1:31415/v1" || profile.ModelId != "auto")
                throw new AgentHostException("provider-profile-self-test-normalization-failed", "The global MCM profile did not load the FreeLLMAPI gateway and default route identifier.");
            if (AgentProviderProfile.GetSettingsValidationError(profile.BaseUrl, profile.ModelId) is not null)
                throw new AgentHostException("provider-profile-self-test-settings-check-failed", "The MCM configuration check rejected valid local model settings.");
            results.Add(new { scenario = "mcm-global-profile-values-normalized", passed = true });
            results.Add(new { scenario = "mcm-global-profile-tolerates-legacy-and-unknown-fields", passed = true });
        }

        ExpectInvalidProfile("{\"OllamaBaseUrl\":\"https://example.com/v1\",\"ModelId\":\"test\"}", "provider-profile-endpoint-invalid", "mcm-profile-rejects-remote-endpoint");
        if (AgentProviderProfile.GetSettingsValidationError("https://example.com/v1", "test") != "provider-profile-endpoint-invalid")
            throw new AgentHostException("provider-profile-self-test-settings-check-failed", "The MCM configuration check accepted a remote endpoint.");
        results.Add(new { scenario = "mcm-profile-rejects-remote-endpoint", passed = true });
        ExpectInvalidProfile("{\"OllamaBaseUrl\":\"http://user:pass@127.0.0.1:31415/v1\",\"ModelId\":\"test\"}", "provider-profile-endpoint-invalid", "mcm-profile-rejects-credentials");
        results.Add(new { scenario = "mcm-profile-rejects-credentials", passed = true });
        ExpectInvalidProfile("{\"OllamaBaseUrl\":\"http://127.0.0.1:31415/v1?token=not-used\",\"ModelId\":\"test\"}", "provider-profile-endpoint-invalid", "mcm-profile-rejects-query-string");
        results.Add(new { scenario = "mcm-profile-rejects-query-string", passed = true });
        ExpectInvalidProfile("{\"OllamaBaseUrl\":\"http://127.0.0.1:31415/v1\",\"ModelId\":\" \"}", "provider-profile-model-invalid", "mcm-profile-rejects-empty-model");
        if (AgentProviderProfile.GetSettingsValidationError("http://127.0.0.1:31415/v1", " ") != "provider-profile-model-invalid")
            throw new AgentHostException("provider-profile-self-test-settings-check-failed", "The MCM configuration check accepted an empty model identifier.");
        results.Add(new { scenario = "mcm-profile-rejects-empty-model", passed = true });
        ExpectProfileFileError("{", "provider-profile-invalid-json", "mcm-profile-rejects-corrupt-json");
        results.Add(new { scenario = "mcm-profile-rejects-corrupt-json", passed = true });
        TestConfiguredProfileOverride(results);
        using (var launch = JsonDocument.Parse("{\"providerConfiguration\":{\"OllamaBaseUrl\":\"http://127.0.0.1:31415/v1\",\"ModelId\":\"current-page-model\"}}"))
        using (var currentProvider = OllamaNativeProvider.FromCampaignRequest(launch.RootElement))
        {
            if (currentProvider.ModelId != "current-page-model" || currentProvider.ConfigurationSource != "mcm-start-request")
                throw new AgentHostException("mcm-launch-snapshot-self-test-failed", "Host did not use the model snapshot supplied by the Start button.");
            results.Add(new { scenario = "mcm-start-request-uses-current-page-model-without-saved-profile", passed = true });
        }
        var priorMaxTokens = Environment.GetEnvironmentVariable("CHRONICLE_LLM_MAX_TOKENS");
        var priorTimeoutSeconds = Environment.GetEnvironmentVariable("CHRONICLE_LLM_TIMEOUT_SECONDS");
        try
        {
            Environment.SetEnvironmentVariable("CHRONICLE_LLM_MAX_TOKENS", "512");
            Environment.SetEnvironmentVariable("CHRONICLE_LLM_TIMEOUT_SECONDS", "180");
            using var launchWithBudget = JsonDocument.Parse("{\"providerConfiguration\":{\"OllamaBaseUrl\":\"http://127.0.0.1:31415/v1\",\"ModelId\":\"auto\"}}");
            using var budgetProvider = OllamaNativeProvider.FromCampaignRequest(launchWithBudget.RootElement);
            if (budgetProvider.ModelId != "auto" || budgetProvider.MaxOutputTokens != 512)
                throw new AgentHostException("freellmapi-profile-budget-self-test-failed", "Host did not apply the bounded FreeLLMAPI output budget from the current process configuration.");
            results.Add(new { scenario = "freellmapi-profile-uses-bounded-512-token-live-model-budget", passed = true });
        }
        finally
        {
            Environment.SetEnvironmentVariable("CHRONICLE_LLM_MAX_TOKENS", priorMaxTokens);
            Environment.SetEnvironmentVariable("CHRONICLE_LLM_TIMEOUT_SECONDS", priorTimeoutSeconds);
        }
        using (var invalidLaunch = JsonDocument.Parse("{\"providerConfiguration\":{\"OllamaBaseUrl\":\"https://example.com/v1\",\"ModelId\":\"test\"}}"))
        {
            try
            {
                using var unexpectedProvider = OllamaNativeProvider.FromCampaignRequest(invalidLaunch.RootElement);
                throw new AgentHostException("mcm-launch-snapshot-invalid-accepted", "Host accepted an invalid inline provider configuration.");
            }
            catch (AgentHostException exception) when (exception.Code == "provider-profile-endpoint-invalid") { }
            results.Add(new { scenario = "mcm-start-request-rejects-invalid-snapshot-without-profile-fallback", passed = true });
        }

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

        var healthHandler = new StubHandler((_, _) => Task.FromResult(JsonResponse("{\"data\":[{\"id\":\"test-local-model\"}]}")));
        using (var healthClient = new HttpClient(healthHandler) { Timeout = settings.Timeout })
        using (var provider = new OllamaNativeProvider(settings, healthClient))
        {
            await provider.CheckConfiguredModelAsync(CancellationToken.None);
            if (healthHandler.LastRequestMethod != HttpMethod.Get || healthHandler.LastRequestUri?.AbsolutePath != "/v1/models")
                throw new AgentHostException("provider-health-self-test-request-failed", "Startup health check must make a read-only GET to the local model catalog, not generate model output.");
            results.Add(new { scenario = "local-provider-health-check-is-read-only-model-list", passed = true });
        }

        var unauthenticatedFreeLlmApiHandler = new StubHandler((_, _) => Task.FromResult(JsonResponse("{\"data\":[{\"id\":\"auto\"}]}")));
        using (var unauthenticatedFreeLlmApiClient = new HttpClient(unauthenticatedFreeLlmApiHandler) { Timeout = settings.Timeout })
        using (var unauthenticatedFreeLlmApi = new OllamaNativeProvider(settings with
        {
            Endpoint = new Uri("http://127.0.0.1:31415/v1/chat/completions"),
            Model = "auto",
            ApiKey = null
        }, unauthenticatedFreeLlmApiClient))
        {
            try
            {
                await unauthenticatedFreeLlmApi.CheckConfiguredModelAsync(CancellationToken.None);
                throw new AgentHostException("freellmapi-missing-key-self-test-failed", "The Host attempted unauthenticated FreeLLMAPI access.");
            }
            catch (AgentHostException exception) when (exception.Code == "provider-api-key-missing")
            {
                if (unauthenticatedFreeLlmApiHandler.LastRequestUri is not null)
                    throw new AgentHostException("freellmapi-missing-key-request-sent", "A missing FreeLLMAPI key must fail before any HTTP request.");
            }
            results.Add(new { scenario = "freellmapi-missing-key-fails-before-network-request", passed = true });
        }

        var freeLlmApiEndpoint = new Uri("http://127.0.0.1:31415/v1/chat/completions");
        var freeLlmApiSettings = settings with { Endpoint = freeLlmApiEndpoint, Model = "auto", ApiKey = "freellmapi-self-test-secret" };
        var freeLlmApiHandler = new StubHandler((request, _) =>
        {
            if (request.Method == HttpMethod.Get)
                return Task.FromResult(JsonResponse("{\"data\":[{\"id\":\"auto\"}]}"));
            var response = JsonResponse(BuildChatResponse(ValidDecision, "stop"));
            response.Headers.TryAddWithoutValidation("X-Routed-Via", "google/gemini-test-model");
            return Task.FromResult(response);
        });
        using (var freeLlmApiClient = new HttpClient(freeLlmApiHandler) { Timeout = freeLlmApiSettings.Timeout })
        using (var provider = new OllamaNativeProvider(freeLlmApiSettings, freeLlmApiClient))
        using (var request = JsonDocument.Parse(BuildDecisionRequest()))
        {
            await provider.CheckConfiguredModelAsync(CancellationToken.None);
            if (freeLlmApiHandler.LastAuthorization?.Scheme != "Bearer" ||
                freeLlmApiHandler.LastAuthorization.Parameter != "freellmapi-self-test-secret" ||
                freeLlmApiHandler.LastRequestUri?.Query != "?available=true")
                throw new AgentHostException("freellmapi-auth-self-test-failed", "FreeLLMAPI model discovery must use the bearer credential and only request presently available models.");
            var result = await provider.DecideAsync(request.RootElement, CancellationToken.None);
            if (freeLlmApiHandler.LastAuthorization?.Scheme != "Bearer" || result.RoutedVia != "google/gemini-test-model")
                throw new AgentHostException("freellmapi-routing-evidence-self-test-failed", "FreeLLMAPI inference must carry bearer auth and preserve the actual routed provider/model header.");
            results.Add(new { scenario = "freellmapi-bearer-auth-available-model-preflight-and-routed-model-evidence", passed = true });
        }

        await ExpectProviderHealthErrorAsync(settings, JsonResponse("{\"data\":[{\"id\":\"different-model\"}]}"), "provider-model-unavailable", "local-provider-health-rejects-missing-model");
        using (var unavailableClient = new HttpClient(new StubHandler((_, _) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable)))) { Timeout = settings.Timeout })
        using (var provider = new OllamaNativeProvider(settings, unavailableClient))
        {
            try
            {
                await provider.CheckConfiguredModelAsync(CancellationToken.None);
                throw new AgentHostException("provider-health-self-test-http-accepted", "The local health check accepted an HTTP error.");
            }
            catch (AgentHostException exception) when (exception.Code == "provider-unavailable") { }
            results.Add(new { scenario = "local-provider-health-distinguishes-http-rejection", passed = true });
        }

        await VerifySharedDecisionCycleAsync(settings, "mapSettlementTargets", "CampaignSystemPrompt", AgentHostDecisionCycle.DecideCampaignAsync, results);
        await VerifySharedDecisionCycleAsync(settings, "foodOptions", "SupplySystemPrompt", AgentHostDecisionCycle.DecideSupplyAsync, results);

        await VerifyGoalClassificationAsync(settings, "supportedMapArrivalGoal", "supported-map-arrival", ["supportedMapArrivalGoal", "unsupportedGoal"], results);
        await VerifyGoalClassificationAsync(settings, "supportedVillageToolsQuestGoal", "supported-village-tools-quest", ["supportedMapArrivalGoal", "supportedVillageToolsQuestGoal", "unsupportedGoal"], results);
        await VerifyGoalClassificationAsync(settings, "unsupportedGoal", "unsupported", ["supportedMapArrivalGoal", "unsupportedGoal"], results);
        await VerifyGoalClassificationAsync(settings, "supportedMapArrivalGoal", "provider-goal-classification-unavailable", ["unsupportedGoal"], results);
        await VerifyGoalClassificationAsync(settings, "supportedVillageToolsQuestGoal", "provider-goal-classification-unavailable", ["supportedMapArrivalGoal", "unsupportedGoal"], results);
        VerifyProductionGoalClassificationCatalogNormalization(results);
        VerifyDecisionSchemaBindsCurrentArgumentValues(results);

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

        var controlAliasHandler = new StubHandler((_, _) => Task.FromResult(JsonResponse(BuildChatResponse("{\"control\":\"tradeConfirm\",\"rationale\":\"confirm the current Native draft\"}", "stop"))));
        using (var aliasClient = new HttpClient(controlAliasHandler) { Timeout = settings.Timeout })
        using (var provider = new OllamaNativeProvider(settings, aliasClient))
        using (var request = JsonDocument.Parse(BuildActionDecisionRequest()))
        {
            var result = await provider.DecideAsync(request.RootElement, CancellationToken.None);
            if (ReadDecisionString(result.Decision, "action") != "tradeConfirm")
                throw new AgentHostException("provider-self-test-action-alias-failed", "An action named in the current action catalog was not normalized safely.");
            results.Add(new { scenario = "listed-action-returned-through-control-field", passed = true });
        }

        var emptyCatalogHandler = new StubHandler((_, _) => Task.FromResult(JsonResponse(BuildChatResponse(ValidDecision, "stop"))));
        using (var emptyCatalogClient = new HttpClient(emptyCatalogHandler) { Timeout = settings.Timeout })
        using (var provider = new OllamaNativeProvider(settings, emptyCatalogClient))
        using (var request = JsonDocument.Parse(BuildDecisionRequestWithoutDoneControl()))
        {
            try
            {
                _ = await provider.DecideAsync(request.RootElement, CancellationToken.None);
                throw new AgentHostException("provider-self-test-empty-catalog-accepted", "The Provider attempted a model call without a Native action or control.");
            }
            catch (AgentHostException exception) when (exception.Code == "provider-decision-catalog-empty")
            {
                if (emptyCatalogHandler.LastRequestBody is not null)
                    throw new AgentHostException("provider-self-test-empty-catalog-requested", "An empty Native catalog must not produce a model request.");
            }
            results.Add(new { scenario = "empty-native-catalog-stops-before-model-call", passed = true });
        }

        var menuAliasHandler = new StubHandler((_, _) => Task.FromResult(JsonResponse(BuildChatResponse("{\"action\":\"trade\",\"arguments\":{},\"rationale\":\"Select the visible trade menu.\"}", "stop"))));
        using (var menuAliasClient = new HttpClient(menuAliasHandler) { Timeout = settings.Timeout })
        using (var provider = new OllamaNativeProvider(settings, menuAliasClient))
        using (var request = JsonDocument.Parse(BuildMenuAliasDecisionRequest()))
        {
            var result = await provider.DecideAsync(request.RootElement, CancellationToken.None);
            if (ReadDecisionString(result.Decision, "action") != "menuSelect" ||
                result.Decision["arguments"]?["OptionId"]?.GetValue<string>() != "trade")
                throw new AgentHostException("provider-self-test-menu-alias-failed", "An exact enabled Native menu-option alias was not safely bound to menuSelect.OptionId.");
            results.Add(new { scenario = "enabled-menu-option-alias-binds-observed-id", passed = true });
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

        var routedFailureResponse = new HttpResponseMessage(HttpStatusCode.BadGateway);
        routedFailureResponse.Headers.TryAddWithoutValidation("X-Routed-Via", "custom/nvidia/test-model");
        routedFailureResponse.Headers.TryAddWithoutValidation("X-Fallback-Attempts", "2");
        routedFailureResponse.Headers.TryAddWithoutValidation("X-Fallback-Trail", "nvidia/test-model=upstream_502; kilo/model=rate_limited");
        routedFailureResponse.Content = new StringContent("sensitive-error-body-marker");
        using (var routedFailureClient = new HttpClient(new StubHandler((_, _) => Task.FromResult(routedFailureResponse))) { Timeout = settings.Timeout })
        using (var routedFailureProvider = new OllamaNativeProvider(settings with
        {
            Endpoint = new Uri("http://127.0.0.1:31415/v1/chat/completions"),
            Model = "auto:noema-free",
            ApiKey = "freellmapi-self-test-secret"
        }, routedFailureClient))
        using (var request = JsonDocument.Parse(BuildDecisionRequest()))
        {
            try
            {
                await routedFailureProvider.DecideAsync(request.RootElement, CancellationToken.None);
                throw new AgentHostException("provider-self-test-routed-failure-accepted", "The FreeLLMAPI error response unexpectedly succeeded.");
            }
            catch (AgentHostException exception) when (exception.Code == "provider-http-error")
            {
                if (!exception.Message.Contains("FreeLLMAPI returned HTTP 502", StringComparison.Ordinal) ||
                    !exception.Message.Contains("routedVia=custom/nvidia/test-model", StringComparison.Ordinal) ||
                    !exception.Message.Contains("fallbackAttempts=2", StringComparison.Ordinal) ||
                    !exception.Message.Contains("fallbackTrail=nvidia/test-model=upstream_502", StringComparison.Ordinal) ||
                    exception.Message.Contains("sensitive-error-body-marker", StringComparison.Ordinal))
                    throw new AgentHostException("provider-self-test-routed-failure-diagnostics-unsafe", "FreeLLMAPI failure diagnostics must retain route headers while omitting response bodies.");
            }
            results.Add(new { scenario = "freellmapi-http-error-keeps-safe-route-fallback-headers-without-response-body", passed = true });
        }

        await ExpectTimeoutAsync(settings);
        results.Add(new { scenario = "provider-timeout", passed = true });
        await ExpectResponseBodyTimeoutAsync(settings);
        results.Add(new { scenario = "provider-response-body-timeout", passed = true });

        try
        {
        var observedResponseFormats = new List<string>();
        var observedTokenParameters = new List<(bool MaxTokens, bool MaxCompletionTokens)>();
        var jsonModeFallbackHandler = new StubHandler((httpRequest, cancellationToken) =>
        {
            using var payloadDocument = JsonDocument.Parse(httpRequest.Content!.ReadAsStringAsync().GetAwaiter().GetResult());
            var payload = payloadDocument.RootElement;
            observedTokenParameters.Add((payload.TryGetProperty("max_tokens", out _), payload.TryGetProperty("max_completion_tokens", out _)));
            if (payload.TryGetProperty("response_format", out var responseFormat) && responseFormat.TryGetProperty("type", out var responseType))
                observedResponseFormats.Add(responseType.GetString() ?? "missing");
            else
                observedResponseFormats.Add("missing");
            if (observedResponseFormats.Count == 1)
            {
                var rejectedSchema = new HttpResponseMessage(HttpStatusCode.BadGateway);
                rejectedSchema.Headers.TryAddWithoutValidation("X-Fallback-Trail", "custom/nvidia/model key1=upstream_error; ovh/Mistral-Small key2=provider_bad_request");
                rejectedSchema.Content = new StringContent("schema unsupported");
                return Task.FromResult(rejectedSchema);
            }
            var jsonModeResponse = JsonResponse(BuildChatResponse(ValidDecision, "stop"));
            jsonModeResponse.Headers.TryAddWithoutValidation("X-Routed-Via", "ovh/Mistral-Small");
            return Task.FromResult(jsonModeResponse);
        });
        using (var jsonModeFallbackClient = new HttpClient(jsonModeFallbackHandler) { Timeout = freeLlmApiSettings.Timeout })
        using (var jsonModeFallbackProvider = new OllamaNativeProvider(freeLlmApiSettings with { Model = "auto:noema-free" }, jsonModeFallbackClient))
        using (var request = JsonDocument.Parse(BuildDecisionRequest()))
        {
            var result = await jsonModeFallbackProvider.DecideAsync(request.RootElement, CancellationToken.None);
            if (result.Decision["done"]?.GetValue<bool>() != true ||
                result.ResponseFormatMode != "json_object_fallback" ||
                result.RoutedVia != "ovh/Mistral-Small" ||
                !observedResponseFormats.SequenceEqual(new[] { "json_schema", "json_object" }, StringComparer.Ordinal) ||
                !observedTokenParameters.SequenceEqual(new[] { (false, true), (true, false) }))
                throw new AgentHostException("provider-self-test-json-mode-fallback-failed", "A FreeLLMAPI route that explicitly rejected JSON Schema was not retried once in JSON mode and then normalized against the decision contract.");
            results.Add(new { scenario = "freellmapi-json-schema-provider-rejection-falls-back-to-validated-json-object", passed = true });
        }

        var transientRetryCalls = 0;
        var transientRetryHandler = new StubHandler((httpRequest, cancellationToken) =>
        {
            transientRetryCalls++;
            if (transientRetryCalls == 1)
            {
                var unavailable = new HttpResponseMessage(HttpStatusCode.BadGateway);
                unavailable.Headers.TryAddWithoutValidation("X-Fallback-Trail", "custom/nvidia/model key1=error");
                return Task.FromResult(unavailable);
            }
            var recovered = JsonResponse(BuildChatResponse("{\"action\":\"tradeConfirm\",\"arguments\":{},\"rationale\":\"Confirm the current Native draft.\"}", "stop"));
            recovered.Headers.TryAddWithoutValidation("X-Routed-Via", "custom/nvidia/test-model");
            return Task.FromResult(recovered);
        });
        var transientRetrySettings = freeLlmApiSettings with { Model = "auto:noema-free", Timeout = TimeSpan.FromSeconds(20) };
        using (var transientRetryClient = new HttpClient(transientRetryHandler) { Timeout = transientRetrySettings.Timeout })
        using (var transientRetryProvider = new OllamaNativeProvider(transientRetrySettings, transientRetryClient))
        using (var request = JsonDocument.Parse(BuildActionDecisionRequest()))
        {
            var result = await transientRetryProvider.DecideAsync(request.RootElement, CancellationToken.None);
            if (result.Decision["action"]?.GetValue<string>() != "tradeConfirm" ||
                result.RoutedVia != "custom/nvidia/test-model" || transientRetryCalls != 2)
                throw new AgentHostException("provider-self-test-transient-free-gateway-retry-failed", "A FreeLLMAPI upstream transport failure must retry the model decision exactly once before any Native action can be issued.");
            results.Add(new { scenario = "freellmapi-transient-upstream-502-retried-once-before-native-action", passed = true, providerCalls = transientRetryCalls, nativeCommands = 0 });
        }

        var retryAfterCalls = 0;
        var retryAfterHandler = new StubHandler((httpRequest, cancellationToken) =>
        {
            retryAfterCalls++;
            if (retryAfterCalls == 1)
            {
                var limited = new HttpResponseMessage(HttpStatusCode.TooManyRequests);
                limited.Headers.RetryAfter = new RetryConditionHeaderValue(TimeSpan.FromSeconds(1));
                return Task.FromResult(limited);
            }
            var recovered = JsonResponse(BuildChatResponse("{\"action\":\"tradeConfirm\",\"arguments\":{},\"rationale\":\"Confirm the current Native draft.\"}", "stop"));
            recovered.Headers.TryAddWithoutValidation("X-Routed-Via", "custom/nvidia/test-model");
            return Task.FromResult(recovered);
        });
        using (var retryAfterClient = new HttpClient(retryAfterHandler) { Timeout = transientRetrySettings.Timeout })
        using (var retryAfterProvider = new OllamaNativeProvider(transientRetrySettings, retryAfterClient))
        using (var request = JsonDocument.Parse(BuildActionDecisionRequest()))
        {
            var result = await retryAfterProvider.DecideAsync(request.RootElement, CancellationToken.None);
            if (result.Decision["action"]?.GetValue<string>() != "tradeConfirm" || retryAfterCalls != 2)
                throw new AgentHostException("provider-self-test-retry-after-recovery-failed", "The Host should wait for an explicit short FreeLLMAPI Retry-After once before any Native action can be issued.");
            results.Add(new { scenario = "freellmapi-429-honors-bounded-retry-after-before-native-action", passed = true, providerCalls = retryAfterCalls, nativeCommands = 0 });
        }

        using (var missingRetryAfter = new HttpResponseMessage(HttpStatusCode.TooManyRequests))
        using (var longRetryAfter = new HttpResponseMessage(HttpStatusCode.TooManyRequests))
        using (var nonFreeRetryAfter = new HttpResponseMessage(HttpStatusCode.TooManyRequests))
        {
            longRetryAfter.Headers.RetryAfter = new RetryConditionHeaderValue(TimeSpan.FromSeconds(61));
            nonFreeRetryAfter.Headers.RetryAfter = new RetryConditionHeaderValue(TimeSpan.FromSeconds(1));
            if (OllamaNativeProvider.GetBoundedRateLimitRetryAfter(freeLlmApiSettings.Endpoint, missingRetryAfter).HasValue ||
                OllamaNativeProvider.GetBoundedRateLimitRetryAfter(freeLlmApiSettings.Endpoint, longRetryAfter).HasValue ||
                OllamaNativeProvider.GetBoundedRateLimitRetryAfter(settings.Endpoint, nonFreeRetryAfter).HasValue)
                throw new AgentHostException("provider-self-test-unbounded-rate-limit-retry-accepted", "Rate limits without a safe short retry window must not be retried automatically.");
            results.Add(new { scenario = "freellmapi-429-without-short-retry-after-fails-closed", passed = true });
        }

        var boundedTransientRetryCalls = 0;
        var boundedTransientRetryHandler = new StubHandler((httpRequest, cancellationToken) =>
        {
            boundedTransientRetryCalls++;
            if (boundedTransientRetryCalls < 3)
            {
                var unavailable = new HttpResponseMessage(HttpStatusCode.BadGateway);
                unavailable.Headers.TryAddWithoutValidation("X-Fallback-Trail", "custom/nvidia/model key1=upstream_error");
                return Task.FromResult(unavailable);
            }
            var recovered = JsonResponse(BuildChatResponse("{\"action\":\"tradeConfirm\",\"arguments\":{},\"rationale\":\"Confirm the current Native draft.\"}", "stop"));
            recovered.Headers.TryAddWithoutValidation("X-Routed-Via", "custom/nvidia/test-model");
            return Task.FromResult(recovered);
        });
        var boundedTransientRetrySettings = transientRetrySettings with { Timeout = TimeSpan.FromSeconds(60) };
        using (var boundedTransientRetryClient = new HttpClient(boundedTransientRetryHandler) { Timeout = boundedTransientRetrySettings.Timeout })
        using (var boundedTransientRetryProvider = new OllamaNativeProvider(boundedTransientRetrySettings, boundedTransientRetryClient))
        using (var request = JsonDocument.Parse(BuildActionDecisionRequest()))
        {
            var result = await boundedTransientRetryProvider.DecideAsync(request.RootElement, CancellationToken.None);
            if (result.Decision["action"]?.GetValue<string>() != "tradeConfirm" ||
                result.RoutedVia != "custom/nvidia/test-model" || boundedTransientRetryCalls != 3)
                throw new AgentHostException("provider-self-test-bounded-transient-free-gateway-retry-failed", "The Host must make at most two bounded retries for explicitly marked FreeLLMAPI upstream failures before issuing any Native action.");
            results.Add(new { scenario = "freellmapi-two-transient-upstream-retries-bounded-before-native-action", passed = true, providerCalls = boundedTransientRetryCalls, nativeCommands = 0 });
        }

        var schemaTransientCalls = 0;
        var schemaTransientFormats = new List<string>();
        var schemaThenTransientHandler = new StubHandler((httpRequest, cancellationToken) =>
        {
            schemaTransientCalls++;
            using var requestBody = JsonDocument.Parse(httpRequest.Content!.ReadAsStringAsync().GetAwaiter().GetResult());
            schemaTransientFormats.Add(requestBody.RootElement.GetProperty("response_format").GetProperty("type").GetString() ?? "missing");
            if (schemaTransientCalls == 1)
            {
                var schemaRejected = new HttpResponseMessage(HttpStatusCode.BadGateway);
                schemaRejected.Headers.TryAddWithoutValidation("X-Fallback-Trail", "custom/provider/model key1=provider_bad_request");
                return Task.FromResult(schemaRejected);
            }
            if (schemaTransientCalls == 2)
            {
                var upstreamFailed = new HttpResponseMessage(HttpStatusCode.BadGateway);
                upstreamFailed.Headers.TryAddWithoutValidation("X-Fallback-Trail", "custom/provider/model key1=error");
                return Task.FromResult(upstreamFailed);
            }
            return Task.FromResult(JsonResponse(BuildChatResponse("{\"action\":\"tradeConfirm\",\"arguments\":{},\"rationale\":\"Confirm the current Native draft.\"}", "stop")));
        });
        using (var schemaTransientClient = new HttpClient(schemaThenTransientHandler) { Timeout = transientRetrySettings.Timeout })
        using (var schemaTransientProvider = new OllamaNativeProvider(transientRetrySettings, schemaTransientClient))
        using (var request = JsonDocument.Parse(BuildActionDecisionRequest()))
        {
            var result = await schemaTransientProvider.DecideAsync(request.RootElement, CancellationToken.None);
            if (result.Decision["action"]?.GetValue<string>() != "tradeConfirm" || schemaTransientCalls != 3 ||
                !schemaTransientFormats.SequenceEqual(new[] { "json_schema", "json_object", "json_object" }, StringComparer.Ordinal))
                throw new AgentHostException("provider-self-test-schema-fallback-transient-retry-failed", "The bounded transport retry must remain available after the single structured-schema compatibility fallback.");
            results.Add(new { scenario = "freellmapi-schema-fallback-then-transient-upstream-retry-is-bounded", passed = true, providerCalls = schemaTransientCalls, nativeCommands = 0 });
        }

        var compatibilityFormats = new List<string>();
        var mistralRequestShapeValid = true;
        var mistralCompatibilityHandler = new StubHandler((httpRequest, cancellationToken) =>
        {
            using var payloadDocument = JsonDocument.Parse(httpRequest.Content!.ReadAsStringAsync().GetAwaiter().GetResult());
            var payload = payloadDocument.RootElement;
            if (payload.TryGetProperty("response_format", out var responseFormat) && responseFormat.TryGetProperty("type", out var responseFormatType))
                compatibilityFormats.Add(responseFormatType.GetString() ?? "missing");
            else
                compatibilityFormats.Add("missing");
            mistralRequestShapeValid &= payload.TryGetProperty("max_tokens", out var maxTokens) && maxTokens.GetInt32() == 128 &&
                !payload.TryGetProperty("max_completion_tokens", out _) && !payload.TryGetProperty("store", out _) &&
                !payload.TryGetProperty("reasoning_effort", out _);
            var compatibleResponse = JsonResponse(BuildChatResponse("{\"action\":\"tradeConfirm\",\"arguments\":{},\"rationale\":\"Confirm the current Native draft.\"}", "stop"));
            compatibleResponse.Headers.TryAddWithoutValidation("X-Routed-Via", "ovh/Mistral-Small-3.2-24B-Instruct-2506");
            return Task.FromResult(compatibleResponse);
        });
        using (var mistralCompatibilityClient = new HttpClient(mistralCompatibilityHandler) { Timeout = freeLlmApiSettings.Timeout })
        using (var mistralCompatibilityProvider = new OllamaNativeProvider(freeLlmApiSettings with { Model = "mistral-small-3.2-24b" }, mistralCompatibilityClient))
        using (var request = JsonDocument.Parse(BuildActionDecisionRequest()))
        {
            var result = await mistralCompatibilityProvider.DecideAsync(request.RootElement, CancellationToken.None);
            if (result.Decision["action"]?.GetValue<string>() != "tradeConfirm" ||
                result.ResponseFormatMode != "json_object_compatibility" ||
                result.RoutedVia != "ovh/Mistral-Small-3.2-24B-Instruct-2506" ||
                !mistralRequestShapeValid ||
                !compatibilityFormats.SequenceEqual(new[] { "json_object" }, StringComparer.Ordinal))
                throw new AgentHostException("provider-self-test-mistral-json-mode-failed", "The FreeLLMAPI Mistral compatibility route did not use only its empirically accepted JSON/token parameter shape.");
            results.Add(new { scenario = "freellmapi-mistral-uses-validated-json-object-compatibility-mode", passed = true });
        }

        var rateWindowEndpoint = new Uri("http://127.0.0.1:31415/v1/chat/completions");
        if (OllamaNativeProvider.GetMinimumRequestInterval(rateWindowEndpoint, "mistral-small-3.2-24b", null) != TimeSpan.FromSeconds(45) ||
            OllamaNativeProvider.GetMinimumRequestInterval(rateWindowEndpoint, "auto:noema-free", "ovh/Mistral-Small-3.2-24B-Instruct-2506") != TimeSpan.FromSeconds(45) ||
            OllamaNativeProvider.GetMinimumRequestInterval(rateWindowEndpoint, "auto:noema-free", "kilo/openrouter/free") != TimeSpan.Zero ||
            OllamaNativeProvider.GetMinimumRequestInterval(new Uri("http://127.0.0.1:11434/v1/chat/completions"), "mistral-small-3.2-24b", null) != TimeSpan.Zero)
            throw new AgentHostException("provider-self-test-rate-window-policy-failed", "Only the known FreeLLMAPI-to-OVH Mistral route should receive the conservative 31-second request spacing.");
        results.Add(new { scenario = "freellmapi-ovh-model-rate-window-is-route-specific", passed = true });

        foreach (var status in new[] { HttpStatusCode.BadRequest, HttpStatusCode.UnprocessableEntity, HttpStatusCode.BadGateway })
        {
            using var explicitSchemaRejection = new HttpResponseMessage(status);
            explicitSchemaRejection.Headers.TryAddWithoutValidation("X-Fallback-Trail", "ovh/Mistral-Small key1=provider_bad_request");
            if (!OllamaNativeProvider.ShouldRetryWithJsonObject(rateWindowEndpoint, explicitSchemaRejection))
                throw new AgentHostException("provider-self-test-json-schema-rejection-status-not-recognized", $"FreeLLMAPI explicit provider_bad_request status {(int)status} did not enable one bounded JSON-object compatibility retry.");
        }
        using (var transientGatewayFailure = new HttpResponseMessage(HttpStatusCode.BadGateway))
        {
            transientGatewayFailure.Headers.TryAddWithoutValidation("X-Fallback-Trail", "ovh/Mistral-Small key1=upstream_error");
            using var nonGatewayBadRequest = new HttpResponseMessage(HttpStatusCode.BadRequest);
            nonGatewayBadRequest.Headers.TryAddWithoutValidation("X-Fallback-Trail", "ovh/Mistral-Small key1=provider_bad_request");
            if (OllamaNativeProvider.ShouldRetryWithJsonObject(rateWindowEndpoint, transientGatewayFailure) ||
                !OllamaNativeProvider.ShouldRetryTransientFreeLlmApiFailure(rateWindowEndpoint, transientGatewayFailure) ||
                OllamaNativeProvider.ShouldRetryTransientFreeLlmApiFailure(rateWindowEndpoint, nonGatewayBadRequest) ||
                OllamaNativeProvider.ShouldRetryWithJsonObject(new Uri("http://127.0.0.1:11434/v1/chat/completions"), nonGatewayBadRequest))
                throw new AgentHostException("provider-self-test-retried-non-schema-failure", "JSON-object compatibility retry must be limited to explicit FreeLLMAPI provider_bad_request responses.");
        }
        results.Add(new { scenario = "freellmapi-json-object-fallback-recognizes-explicit-400-422-and-fallback-502-schema-rejection-only", passed = true });

        }
        catch (KeyNotFoundException exception)
        {
            throw new AgentHostException("provider-json-mode-compatibility-self-test-missing-property", exception.Message, exception);
        }

        return new
        {
            passed = true,
            modelCalls = 0,
            nativeCommands = 0,
            scenarios = results
        };
    }

    private static void ExpectInvalidProfile(string json, string expectedCode, string scenario)
    {
        using var document = JsonDocument.Parse(json);
        try
        {
            _ = AgentProviderProfile.Parse(document.RootElement);
        }
        catch (AgentHostException exception) when (exception.Code == expectedCode)
        {
            return;
        }
        throw new AgentHostException("provider-profile-self-test-failed", $"Global profile validation did not reject {scenario}.");
    }

    private static void ExpectProfileFileError(string json, string expectedCode, string scenario)
    {
        var testDirectory = Path.Combine(Path.GetTempPath(), "ChronicleProviderProfileTest-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(testDirectory);
        var profilePath = Path.Combine(testDirectory, "ChronicleAgentSettings.json");
        try
        {
            File.WriteAllText(profilePath, json);
            var profileHashBefore = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(profilePath)));
            try
            {
                _ = AgentProviderProfile.Load(profilePath, "provider-profile-self-test");
                throw new AgentHostException("provider-profile-self-test-expected-error", $"Scenario '{scenario}' unexpectedly accepted a corrupt profile.");
            }
            catch (AgentHostException exception) when (exception.Code == expectedCode)
            {
                // Expected safe parse failure.
            }
            var profileHashAfter = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(profilePath)));
            if (!string.Equals(profileHashBefore, profileHashAfter, StringComparison.Ordinal))
                throw new AgentHostException("provider-profile-error-path-mutated-file", $"Scenario '{scenario}' changed the saved profile while rejecting it.");
        }
        finally
        {
            File.Delete(profilePath);
            Directory.Delete(testDirectory);
        }
    }

    private static void TestConfiguredProfileOverride(List<object> results)
    {
        var harnessRoot = Path.Combine(Path.GetTempPath(), "ChronicleMcmProfileHarness-" + Guid.NewGuid().ToString("N"));
        var profileDirectory = Path.Combine(harnessRoot, "MCM", "Global", "ChronicleFramework");
        Directory.CreateDirectory(profileDirectory);
        var profilePath = Path.Combine(profileDirectory, "ChronicleAgentSettings.json");
        var outsideProfilePath = Path.Combine(Path.GetTempPath(), "ChronicleMcmProfileOutside-" + Guid.NewGuid().ToString("N") + ".json");
        var previousMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var previousHarnessRoot = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        var previousProfilePath = Environment.GetEnvironmentVariable("CHRONICLE_AGENT_PROFILE_PATH");
        try
        {
            File.WriteAllText(profilePath, "{\"OllamaBaseUrl\":\"http://127.0.0.1:11434/v1\",\"ModelId\":\"test-local-model\"}");
            var profileHashBefore = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(profilePath)));
            Environment.SetEnvironmentVariable("CHRONICLE_HARNESS_MODE", "visual-capture");
            Environment.SetEnvironmentVariable("CHRONICLE_HARNESS_TEMP", harnessRoot);
            Environment.SetEnvironmentVariable("CHRONICLE_AGENT_PROFILE_PATH", profilePath);
            using (var provider = OllamaNativeProvider.FromConfiguredProfile())
            {
                if (provider.ModelId != "test-local-model" || provider.ConfigurationSource != "harness-mcm-profile-fixture")
                    throw new AgentHostException("provider-profile-override-self-test-failed", "The Host did not load the authorized MCM profile fixture.");
                results.Add(new { scenario = "host-loads-authorized-harness-mcm-profile", passed = true });
            }

            Environment.SetEnvironmentVariable("CHRONICLE_HARNESS_MODE", "agent-host-lifecycle-test");
            using (var lifecycleProvider = OllamaNativeProvider.FromConfiguredProfile())
            {
                if (lifecycleProvider.ModelId != "test-local-model" || lifecycleProvider.ConfigurationSource != "harness-mcm-profile-fixture")
                    throw new AgentHostException("provider-profile-override-self-test-failed", "The Host lifecycle test did not load its authorized temporary MCM profile.");
                results.Add(new { scenario = "lifecycle-test-loads-only-its-authorized-temporary-profile", passed = true });
            }
            var profileHashAfter = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(profilePath)));
            if (!string.Equals(profileHashBefore, profileHashAfter, StringComparison.Ordinal))
                throw new AgentHostException("provider-profile-read-mutated-file", "Loading the existing MCM profile must never rewrite or migrate user-owned configuration.");
            results.Add(new { scenario = "provider-profile-reads-without-migrating-user-file", passed = true });

            Environment.SetEnvironmentVariable("CHRONICLE_AGENT_PROFILE_PATH", outsideProfilePath);
            try
            {
                using var unauthorizedProvider = OllamaNativeProvider.FromConfiguredProfile();
                throw new AgentHostException("provider-profile-override-self-test-failed", "The Host accepted a profile outside its disposable Harness directory.");
            }
            catch (AgentHostException exception) when (exception.Code == "provider-profile-override-not-authorized")
            {
                results.Add(new { scenario = "host-rejects-profile-outside-harness-root", passed = true });
            }
        }
        finally
        {
            Environment.SetEnvironmentVariable("CHRONICLE_HARNESS_MODE", previousMode);
            Environment.SetEnvironmentVariable("CHRONICLE_HARNESS_TEMP", previousHarnessRoot);
            Environment.SetEnvironmentVariable("CHRONICLE_AGENT_PROFILE_PATH", previousProfilePath);
            File.Delete(profilePath);
            Directory.Delete(harnessRoot, recursive: true);
        }
    }

    private static async Task VerifyGoalClassificationAsync(
        OllamaProviderSettings settings,
        string control,
        string expectedClassification,
        string[] allowedControls,
        List<object> results)
    {
        const string reason = "The full goal matches the available scope.";
        var response = JsonResponse(BuildChatResponse(JsonSerializer.Serialize(new { control, reason }), "stop"));
        var handler = new StubHandler((_, _) => Task.FromResult(response));
        using var client = new HttpClient(handler) { Timeout = settings.Timeout };
        using var provider = new OllamaNativeProvider(settings, client);
        using var request = JsonDocument.Parse(JsonSerializer.Serialize(new
        {
            goal = control == "supportedVillageToolsQuestGoal" ? "Complete the currently visible village tools quest." : "Move to any visible safe settlement.",
            goalScopeClassificationRequired = expectedClassification != "provider-goal-classification-unavailable",
            goalScopeContract = "native-map-arrival-v1",
            observation = new { scope = "goal-classification-test", state = new { gameState = "MapState" } },
            allowedActions = Array.Empty<object>(),
            allowedControls
        }));
        try
        {
            var result = await AgentHostDecisionCycle.DecideCampaignAsync(provider, JsonNode.Parse(request.RootElement.GetRawText())!.AsObject(), CancellationToken.None);
            if (expectedClassification == "provider-goal-classification-unavailable" ||
                ReadDecisionString(result.Decision, "goalClassification") != expectedClassification ||
                result.Decision.ContainsKey("action"))
                throw new AgentHostException("provider-goal-classification-self-test-failed", "Goal classification did not stay within its listed control catalog.");
            using var body = JsonDocument.Parse(handler.LastRequestBody ?? throw new AgentHostException("provider-goal-classification-prompt-missing", "The classification request was not sent."));
            var system = body.RootElement.GetProperty("messages")[0].GetProperty("content").GetString() ?? string.Empty;
            if (!system.Contains("required final outcome", StringComparison.Ordinal) || !system.Contains("VillageNeedsToolsIssue", StringComparison.Ordinal) || !system.Contains("named destination", StringComparison.Ordinal) || !system.Contains("not extra goals", StringComparison.Ordinal))
                throw new AgentHostException("provider-goal-classification-prompt-incomplete", "The classifier prompt omitted the exact limits of the supported goal.");
            results.Add(new { scenario = "provider-goal-classification-before-action", control, passed = true });
        }
        catch (AgentHostException exception) when (exception.Code == expectedClassification)
        {
            ValidateLocalEndpoint(handler.LastRequestUri);
            results.Add(new { scenario = "provider-rejects-unlisted-goal-classification", control, passed = true });
        }
        ValidateLocalEndpoint(handler.LastRequestUri);
    }

    private static void VerifyProductionGoalClassificationCatalogNormalization(List<object> results)
    {
        using var request = JsonDocument.Parse("""
            {"goal":"Move the current party to any one currently visible safe settlement.","goalScopeClassificationRequired":true,"goalScopeContract":"native-map-arrival-v1","observation":{"scope":"goal-classification-only"},"allowedActions":[],"allowedControls":["supportedMapArrivalGoal","unsupportedGoal"]}
            """);
        using var acceptedDecision = JsonDocument.Parse("""
            {"control":"supportedMapArrivalGoal","reason":"This request exactly matches the supported map-arrival scope."}
            """);
        var normalized = OllamaNativeProvider.NormalizeDecision(acceptedDecision.RootElement, request.RootElement);
        if (ReadDecisionString(normalized, "goalClassification") != "supported-map-arrival")
            throw new AgentHostException("provider-production-goal-catalog-normalization-failed", "The production JSON catalog did not authorize its listed supported-goal control.");
        using var gateOnlyRequest = JsonDocument.Parse("""
            {"goal":"Move to any safe settlement.","goalScopeClassificationRequired":true,"observation":{"scope":"goal-classification-only"},"allowedActions":[],"allowedControls":[]}
            """);
        var gateOnlyNormalized = OllamaNativeProvider.NormalizeDecision(acceptedDecision.RootElement, gateOnlyRequest.RootElement);
        if (ReadDecisionString(gateOnlyNormalized, "goalClassification") != "supported-map-arrival")
            throw new AgentHostException("provider-goal-classification-phase-gate-failed", "The exact no-action classification phase must authorize only the two fixed classification controls.");
        using var unlistedRequest = JsonDocument.Parse("""
            {"goal":"Move to any safe settlement.","observation":{"scope":"ordinary-decision"},"allowedActions":[],"allowedControls":[]}
            """);
        try
        {
            _ = OllamaNativeProvider.NormalizeDecision(acceptedDecision.RootElement, unlistedRequest.RootElement);
            throw new AgentHostException("provider-goal-classification-phase-gate-overbroad", "A supported-goal declaration escaped its explicitly marked no-action classification phase.");
        }
        catch (AgentHostException exception) when (exception.Code == "provider-goal-classification-unavailable") { }
        results.Add(new { scenario = "production-json-goal-classification-catalog-normalization", passed = true });
    }

    private static void VerifyDecisionSchemaBindsCurrentArgumentValues(List<object> results)
    {
        using var request = JsonDocument.Parse("""
            {"allowedActions":[{"action":"menuSelect","arguments":["OptionId"],"argumentValues":{"OptionId":["trade","leave"]}},{"action":"trade","arguments":["Direction","Amount"],"argumentValues":{"Direction":["buy"],"Amount":[1,2]}}],"allowedControls":[]}
            """);
        var schema = OllamaNativeProvider.BuildDecisionSchema(request.RootElement);
        var enumValues = schema["oneOf"]![0]!["properties"]!["arguments"]!["properties"]!["OptionId"]!["enum"] as JsonArray;
        var amountValues = schema["oneOf"]![1]!["properties"]!["arguments"]!["properties"]!["Amount"]!["enum"] as JsonArray;
        if (enumValues is null || enumValues.Count != 2 || enumValues.Select(item => item?.GetValue<string>()).Any(value => value == "village_center") ||
            !enumValues.Any(item => item?.GetValue<string>() == "trade") || !enumValues.Any(item => item?.GetValue<string>() == "leave") ||
            amountValues is null || amountValues.Count != 2 || !amountValues.Any(item => item?.GetValue<int>() == 1) || !amountValues.Any(item => item?.GetValue<int>() == 2))
            throw new AgentHostException("provider-decision-schema-value-gate-failed", "Structured output must constrain string and integer action arguments to values permitted by the current Native policy.");
        results.Add(new { scenario = "decision-schema-constrains-current-native-string-and-integer-values", passed = true });
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

    private static async Task ExpectResponseBodyTimeoutAsync(OllamaProviderSettings settings)
    {
        var timeoutSettings = settings with { Timeout = TimeSpan.FromMilliseconds(50) };
        using var handler = new StubHandler((_, _) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new DelayedBodyContent()
        }));
        using var client = new HttpClient(handler) { Timeout = Timeout.InfiniteTimeSpan };
        using var provider = new OllamaNativeProvider(timeoutSettings, client);
        using var request = JsonDocument.Parse(BuildDecisionRequest());
        try
        {
            await provider.DecideAsync(request.RootElement, CancellationToken.None);
        }
        catch (AgentHostException exception) when (exception.Code == "provider-timeout")
        {
            return;
        }
        throw new AgentHostException("provider-self-test-body-timeout-failed", "Response headers bypassed the configured body deadline.");
    }

    private sealed class DelayedBodyContent : HttpContent
    {
        protected override Task SerializeToStreamAsync(Stream stream, TransportContext? context) =>
            SerializeToStreamAsync(stream, context, CancellationToken.None);

        protected override async Task SerializeToStreamAsync(Stream stream, TransportContext? context, CancellationToken cancellationToken)
        {
            await Task.Delay(TimeSpan.FromSeconds(2), cancellationToken);
            await stream.WriteAsync(Encoding.UTF8.GetBytes("{}"), cancellationToken);
        }

        protected override bool TryComputeLength(out long length)
        {
            length = 0;
            return false;
        }
    }

    private static string BuildDecisionRequest() => """
        {
          "goal": "This is a local provider protocol test; stop after validating the schema.",
          "observation": { "scope": "provider-contract-test", "state": { "gameState": "MapState" } },
          "allowedActions": [],
          "allowedControls": ["done"]
        }
        """;

    private static string BuildActionDecisionRequest() => """
        {
          "goal": "Use only the currently listed Native action.",
          "observation": { "scope": "provider-action-alias-test", "state": { "gameState": "InventoryState" } },
          "allowedActions": [{ "action": "tradeConfirm", "arguments": [] }],
          "allowedControls": []
        }
        """;

    private static string BuildDecisionRequestWithoutDoneControl() => """
        {
          "goal": "The Host will verify this stop proposal against an unmet Native completion contract.",
          "observation": { "scope": "provider-stop-proposal-test", "state": { "gameState": "InventoryState" } },
          "allowedActions": [],
          "allowedControls": []
        }
        """;

    private static string BuildMenuAliasDecisionRequest() => """
        {
          "goal": "Choose the currently enabled trade menu option.",
          "observation": {
            "scope": "provider-menu-alias-test",
            "state": {
              "context": { "gameState": "MapState", "menuId": "town" },
              "availableMenuOptions": [{ "id": "trade", "available": true, "enabled": true }]
            }
          },
          "allowedActions": [{ "action": "menuSelect", "arguments": ["OptionId"] }],
          "allowedControls": []
        }
        """;

    private static async Task VerifySharedDecisionCycleAsync(
        OllamaProviderSettings settings,
        string actionName,
        string expectedPromptMember,
        Func<IAgentHostDecisionProvider, JsonObject, CancellationToken, Task<ProviderDecisionResult>> decide,
        List<object> results)
    {
        var handler = new StubHandler((_, _) => Task.FromResult(JsonResponse(BuildChatResponse(
            JsonSerializer.Serialize(new { action = actionName, arguments = new { }, rationale = "Use the currently listed action." }),
            "stop"))));
        using var client = new HttpClient(handler) { Timeout = settings.Timeout };
        using var provider = new OllamaNativeProvider(settings, client);
        using var promptRequest = JsonDocument.Parse("{\"goal\":\"Use a single Native action within a fixed scope.\",\"observation\":{\"status\":\"completed\",\"state\":{\"gameState\":\"MapState\"}},\"previousActionReceipt\":null,\"decisionFeedback\":null,\"allowedActions\":[{\"action\":\"" + actionName + "\",\"arguments\":[]}],\"allowedControls\":[]}");
        var request = JsonNode.Parse(promptRequest.RootElement.GetRawText())!.AsObject();
        var decision = await decide(provider, request, CancellationToken.None);
        if (decision.Status != "completed" || ReadDecisionString(decision.Decision, "action") != actionName || string.IsNullOrWhiteSpace(handler.LastRequestBody))
            throw new AgentHostException("agent-host-shared-decision-cycle-failed", $"The shared Host decision cycle failed for {actionName}.");

        using var sentRequest = JsonDocument.Parse(handler.LastRequestBody);
        var systemContent = sentRequest.RootElement.GetProperty("messages")[0].GetProperty("content").GetString();
        var expectedPrompt = expectedPromptMember == "SupplySystemPrompt" ? AgentHostDecisionCycle.SupplySystemPrompt : AgentHostDecisionCycle.CampaignSystemPrompt;
        if (!string.Equals(systemContent, expectedPrompt, StringComparison.Ordinal))
            throw new AgentHostException("agent-host-shared-decision-prompt-failed", $"The shared Host decision cycle did not apply the {expectedPromptMember} policy.");
        results.Add(new { scenario = "shared-agent-host-decision-cycle-" + (expectedPromptMember == "SupplySystemPrompt" ? "supply" : "campaign"), passed = true, action = actionName });
    }

    private static async Task ExpectProviderHealthErrorAsync(OllamaProviderSettings settings, HttpResponseMessage response, string expectedCode, string scenario)
    {
        using var handler = new StubHandler((_, _) => Task.FromResult(response));
        using var client = new HttpClient(handler) { Timeout = settings.Timeout };
        using var provider = new OllamaNativeProvider(settings, client);
        try
        {
            await provider.CheckConfiguredModelAsync(CancellationToken.None);
            throw new AgentHostException("provider-health-self-test-error-missing", $"The provider health check did not reject {scenario}.");
        }
        catch (AgentHostException exception) when (exception.Code == expectedCode) { }
    }

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
            root.GetProperty("response_format").GetProperty("type").GetString() != "json_schema" ||
            root.GetProperty("response_format").GetProperty("json_schema").GetProperty("schema").GetProperty("oneOf").GetArrayLength() != 1 ||
            root.GetProperty("response_format").GetProperty("json_schema").GetProperty("schema").GetProperty("oneOf")[0].GetProperty("properties").GetProperty("control").GetProperty("const").GetString() != "done" ||
            root.GetProperty("response_format").GetProperty("json_schema").GetProperty("schema").GetProperty("oneOf")[0].GetProperty("properties").GetProperty("reason").GetProperty("maxLength").GetInt32() != 64 ||
            root.GetProperty("max_completion_tokens").GetInt32() != 128 ||
            root.TryGetProperty("store", out _) || root.TryGetProperty("reasoning_effort", out _))
            throw new AgentHostException("provider-self-test-request-failed", "Provider request did not constrain its local response to the current decision catalog.");
    }

    private static void ValidateLocalEndpoint(Uri? uri)
    {
        if (uri is null || !uri.IsLoopback || uri.Scheme != "http")
            throw new AgentHostException("provider-self-test-endpoint-failed", "Provider attempted to use a non-local HTTP endpoint.");
    }

    private static string? ReadDecisionString(JsonObject decision, string propertyName) =>
        decision.TryGetPropertyValue(propertyName, out var node) && node is JsonValue value && value.TryGetValue<string>(out var result) ? result : null;

    private static void ValidateNativeRequestShape(string? body, Uri? uri, AuthenticationHeaderValue? authorization)
    {
        if (string.IsNullOrWhiteSpace(body) || uri?.AbsolutePath != "/api/chat" || authorization is not null)
            throw new AgentHostException("provider-self-test-native-request-failed", "Native Ollama request shape or local endpoint is invalid.");
        using var document = JsonDocument.Parse(body);
        var root = document.RootElement;
        if (root.GetProperty("model").GetString() != "test-local-model" ||
            root.GetProperty("stream").GetBoolean() || root.GetProperty("format").GetProperty("oneOf").GetArrayLength() != 1 ||
            root.GetProperty("options").GetProperty("num_predict").GetInt32() != 128)
            throw new AgentHostException("provider-self-test-native-request-failed", "Native Ollama request did not constrain output to the current decision catalog.");
    }

    private sealed class StubHandler : HttpMessageHandler
    {
        private readonly Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> _responseFactory;
        internal string? LastRequestBody { get; private set; }
        internal HttpMethod? LastRequestMethod { get; private set; }
        internal Uri? LastRequestUri { get; private set; }
        internal AuthenticationHeaderValue? LastAuthorization { get; private set; }

        internal StubHandler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> responseFactory) => _responseFactory = responseFactory;

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            LastRequestMethod = request.Method;
            LastRequestUri = request.RequestUri;
            LastAuthorization = request.Headers.Authorization;
            LastRequestBody = request.Content is null ? null : await request.Content.ReadAsStringAsync(cancellationToken);
            return await _responseFactory(request, cancellationToken);
        }
    }
}
