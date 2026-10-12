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

        using (var validProfile = JsonDocument.Parse("{\"OllamaBaseUrl\":\"http://127.0.0.1:11434/v1\",\"ModelId\":\"qwen3.5:4b-q4_K_M\"}"))
        {
            var profile = AgentProviderProfile.Parse(validProfile.RootElement);
            if (profile.BaseUrl != "http://127.0.0.1:11434/v1" || profile.ModelId != "qwen3.5:4b-q4_K_M")
                throw new AgentHostException("provider-profile-self-test-normalization-failed", "The global MCM profile did not load the saved loopback URL and model identifier.");
            if (AgentProviderProfile.GetSettingsValidationError(profile.BaseUrl, profile.ModelId) is not null)
                throw new AgentHostException("provider-profile-self-test-settings-check-failed", "The MCM configuration check rejected valid local model settings.");
            results.Add(new { scenario = "mcm-global-profile-values-normalized", passed = true });
        }

        ExpectInvalidProfile("{\"OllamaBaseUrl\":\"https://example.com/v1\",\"ModelId\":\"test\"}", "provider-profile-endpoint-invalid", "mcm-profile-rejects-remote-endpoint");
        if (AgentProviderProfile.GetSettingsValidationError("https://example.com/v1", "test") != "provider-profile-endpoint-invalid")
            throw new AgentHostException("provider-profile-self-test-settings-check-failed", "The MCM configuration check accepted a remote endpoint.");
        results.Add(new { scenario = "mcm-profile-rejects-remote-endpoint", passed = true });
        ExpectInvalidProfile("{\"OllamaBaseUrl\":\"http://user:pass@127.0.0.1:11434/v1\",\"ModelId\":\"test\"}", "provider-profile-endpoint-invalid", "mcm-profile-rejects-credentials");
        results.Add(new { scenario = "mcm-profile-rejects-credentials", passed = true });
        ExpectInvalidProfile("{\"OllamaBaseUrl\":\"http://127.0.0.1:11434/v1?token=not-used\",\"ModelId\":\"test\"}", "provider-profile-endpoint-invalid", "mcm-profile-rejects-query-string");
        results.Add(new { scenario = "mcm-profile-rejects-query-string", passed = true });
        ExpectInvalidProfile("{\"OllamaBaseUrl\":\"http://127.0.0.1:11434/v1\",\"ModelId\":\" \"}", "provider-profile-model-invalid", "mcm-profile-rejects-empty-model");
        if (AgentProviderProfile.GetSettingsValidationError("http://127.0.0.1:11434/v1", " ") != "provider-profile-model-invalid")
            throw new AgentHostException("provider-profile-self-test-settings-check-failed", "The MCM configuration check accepted an empty model identifier.");
        results.Add(new { scenario = "mcm-profile-rejects-empty-model", passed = true });
        ExpectProfileFileError("{", "provider-profile-invalid-json", "mcm-profile-rejects-corrupt-json");
        results.Add(new { scenario = "mcm-profile-rejects-corrupt-json", passed = true });
        TestConfiguredProfileOverride(results);
        using (var launch = JsonDocument.Parse("{\"providerConfiguration\":{\"OllamaBaseUrl\":\"http://127.0.0.1:11434/v1\",\"ModelId\":\"current-page-model\"}}"))
        using (var currentProvider = OllamaNativeProvider.FromCampaignRequest(launch.RootElement))
        {
            if (currentProvider.ModelId != "current-page-model" || currentProvider.ConfigurationSource != "mcm-start-request")
                throw new AgentHostException("mcm-launch-snapshot-self-test-failed", "Host did not use the model snapshot supplied by the Start button.");
            results.Add(new { scenario = "mcm-start-request-uses-current-page-model-without-saved-profile", passed = true });
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

        var earlyStopHandler = new StubHandler((_, _) => Task.FromResult(JsonResponse(BuildChatResponse(ValidDecision, "stop"))));
        using (var earlyStopClient = new HttpClient(earlyStopHandler) { Timeout = settings.Timeout })
        using (var provider = new OllamaNativeProvider(settings, earlyStopClient))
        using (var request = JsonDocument.Parse(BuildDecisionRequestWithoutDoneControl()))
        {
            var result = await provider.DecideAsync(request.RootElement, CancellationToken.None);
            if (result.Decision["done"]?.GetValue<bool>() != true)
                throw new AgentHostException("provider-self-test-stop-proposal-failed", "A done proposal must reach the Host completion verifier even when not yet allowed to stop.");
            results.Add(new { scenario = "premature-done-is-a-verifiable-proposal-not-a-game-action", passed = true });
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
        await ExpectTimeoutAsync(settings);
        results.Add(new { scenario = "provider-timeout", passed = true });
        await ExpectResponseBodyTimeoutAsync(settings);
        results.Add(new { scenario = "provider-response-body-timeout", passed = true });

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
            try
            {
                _ = AgentProviderProfile.Load(profilePath, "provider-profile-self-test");
                throw new AgentHostException("provider-profile-self-test-expected-error", $"Scenario '{scenario}' unexpectedly accepted a corrupt profile.");
            }
            catch (AgentHostException exception) when (exception.Code == expectedCode)
            {
                // Expected safe parse failure.
            }
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

    private static string? ReadDecisionString(JsonObject decision, string propertyName) =>
        decision.TryGetPropertyValue(propertyName, out var node) && node is JsonValue value && value.TryGetValue<string>(out var result) ? result : null;

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
