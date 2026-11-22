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
        results.AddRange(AgentHostDecisionCycle.RunBattleAndCaptivityPromptContractSelfTests());
        var terminalReceipt = Program.BuildCampaignLoopTerminalReceipt(new JsonObject
        {
            ["status"] = "failed", ["providerModelId"] = "deepseek-flash", ["providerConfigurationSource"] = "mcm-start-request",
            ["decisions"] = 12, ["actionsExecuted"] = 4, ["promptTokens"] = 1200, ["completionTokens"] = 90,
            ["providerPromptCacheHitTokens"] = 600, ["providerPromptCacheMissTokens"] = 600,
            ["providerActualCostEstimateCny"] = 0.03, ["providerReservedCostUpperCny"] = 0.05,
            ["failureCode"] = "provider-budget-exhausted", ["failureExceptionType"] = "NullReferenceException",
            ["failureLocation"] = "AgentHostEstablishYourClanAutonomyLoop.RunAsync", ["failure"] = "PRIVATE_FAILURE_TEXT",
            ["trace"] = new JsonArray("PRIVATE_TRACE"), ["conversationText"] = "PRIVATE_DIALOGUE_TEXT",
            ["termination"] = new JsonObject { ["reason"] = "provider-budget-exhausted", ["goalVerified"] = false }
        });
        if (terminalReceipt["status"]?.GetValue<string>() != "failed" ||
            terminalReceipt["failureCode"]?.GetValue<string>() != "provider-budget-exhausted" ||
            terminalReceipt["decisionCount"]?.GetValue<int>() != 12 ||
            terminalReceipt["providerActualCostEstimateCny"]?.GetValue<double>() != 0.03 ||
            terminalReceipt["failureExceptionType"]?.GetValue<string>() != "NullReferenceException" ||
            terminalReceipt["failureLocation"]?.GetValue<string>() != "AgentHostEstablishYourClanAutonomyLoop.RunAsync" ||
            terminalReceipt.ContainsKey("trace") || terminalReceipt.ContainsKey("failure") || terminalReceipt.ContainsKey("conversationText") ||
            terminalReceipt.ToJsonString().Contains("PRIVATE_", StringComparison.Ordinal))
            throw new AgentHostException("campaign-terminal-receipt-self-test-failed", "The game-facing campaign terminal receipt must keep structured outcome/cost fields and omit the full trace and free text.");
        results.Add(new { scenario = "campaign-loop-emits-compact-cost-and-failure-receipt-without-trace-or-free-text", passed = true });
        results.AddRange(DeepSeekPromptTokenEstimator.RunContractSelfTests());
        if (!AgentHostDecisionCycle.IsObserveAgainDecision(new JsonObject { ["observeAgain"] = true, ["waitSeconds"] = 2 }) ||
            !AgentHostDecisionCycle.IsObserveAgainDecision(new JsonObject { ["control"] = "observeAgain", ["waitSeconds"] = 2 }) ||
            AgentHostDecisionCycle.IsObserveAgainDecision(new JsonObject { ["done"] = true }))
            throw new AgentHostException("observe-again-normalized-shape-self-test-failed", "Movement subloops must recognize the canonical boolean observeAgain decision as well as its pre-normalized control alias.");
        results.Add(new { scenario = "canonical-observe-again-decision-is-recognized-by-native-subloops", passed = true });
        results.AddRange(AgentHostProviderDecisionRecovery.RunContractSelfTests());
        results.AddRange(AgentHostSupplyLoop.RunContractSelfTests());
        results.AddRange(StoryModeEstablishClanLifecycleStatus.RunContractSelfTests());
        results.AddRange(AgentHostHarnessProgressTrace.RunContractSelfTests());
        results.AddRange(AgentHostRuntimeProgressLog.RunContractSelfTests());
        results.AddRange(AgentHostNativeInquiryResolution.RunContractSelfTests());
        var villageQuestPrompt = AgentHostDecisionCycle.VillageToolsQuestSystemPrompt;
        if (!villageQuestPrompt.Contains("talkToSettlementHero", StringComparison.Ordinal) ||
            !villageQuestPrompt.Contains("only before a conversation is open, and only if talkToSettlementHero is currently listed", StringComparison.Ordinal) ||
            !villageQuestPrompt.Contains("conversation is already open: never talk to that hero again", StringComparison.Ordinal) ||
            !villageQuestPrompt.Contains("Once the Journal confirms the Quest is active and tools are still owed, leave the Village and travel to a Town", StringComparison.Ordinal) ||
            !villageQuestPrompt.Contains("obey the Host RECOVERY DIRECTIVE", StringComparison.Ordinal) ||
            !villageQuestPrompt.Contains("sameActionRetryAllowed explicitly permits correcting its arguments", StringComparison.Ordinal) ||
            villageQuestPrompt.Contains("quickConversation", StringComparison.OrdinalIgnoreCase))
            throw new AgentHostException("village-tools-prompt-native-action-id-mismatch", "The quest prompt must name the exact Native contact action and prevent stale contact/decision repetition after conversation opens or feedback rejects an action.");
        results.Add(new { scenario = "village-tools-prompt-uses-exact-native-action-id", passed = true });
        results.AddRange(NativeMailboxClient.RunVillageToolsQuestActionContractSelfTests());
        results.AddRange(NativeMailboxClient.RunNativeInquiryResponseContractSelfTests());
        try { results.AddRange(await NativeMailboxClient.RunBattleDoneAcceptedResponseTransportSelfTestsAsync()); }
        catch (Exception exception) { throw new AgentHostException("battle-done-accepted-response-transport-self-test-failed", exception.GetType().Name + ": " + exception.Message, exception); }
        results.AddRange(NativeMailboxClient.RunStoryModeClanNameContractSelfTests());
        results.AddRange(NativeMailboxClient.RunBattleSimulationActionContractSelfTests());
        results.AddRange(NativeMailboxClient.RunGoldSaleActionContractSelfTests());
        try { results.AddRange(await NativeMailboxClient.RunGoldSaleAcceptedResponseTransportSelfTestsAsync()); }
        catch (Exception exception) { throw new AgentHostException("gold-sale-accepted-response-transport-self-test-failed", exception.GetType().Name + ": " + exception.Message, exception); }
        results.AddRange(NativeMailboxClient.RunRecruitmentActionContractSelfTests());
        results.AddRange(NativeMailboxClient.RunTrainingIssueActionContractSelfTests());
        results.AddRange(NativeMailboxClient.RunCompanionHiringActionContractSelfTests());
        try { results.AddRange(await AgentHostEstablishClanRecruitmentLoop.RunContractSelfTestsAsync()); }
        catch (Exception exception) { throw new AgentHostException("establish-clan-recruitment-loop-self-test-failed", exception.GetType().Name + ": " + exception.Message, exception); }
        results.AddRange(AgentHostEstablishClanCompanionLoop.RunContractSelfTests());
        results.AddRange(AgentHostCampaignStateFacts.RunContractSelfTests());
        try { results.AddRange(await AgentHostEstablishClanCompanionLoop.RunTransportSelfTestsAsync()); }
        catch (Exception exception) { throw new AgentHostException("establish-clan-companion-loop-self-test-failed", exception.GetType().Name + ": " + exception.Message, exception); }
        try { results.AddRange(await AgentHostStoryModeSetupLoop.RunContractSelfTestsAsync()); }
        catch (Exception exception) { throw new AgentHostException("storymode-setup-loop-self-test-failed", exception.GetType().Name + ": " + exception.Message, exception); }
        results.AddRange(AgentHostEstablishClanGoldSaleLoop.RunContractSelfTests());
        results.AddRange(AgentHostEstablishClanTrainingIssueLoop.RunContractSelfTests());
        try { results.AddRange(await AgentHostEstablishClanTrainingIssueLoop.RunMapDialogueTransportSelfTestsAsync()); }
        catch (Exception exception) { throw new AgentHostException("training-issue-map-dialogue-transport-self-test-failed", exception.GetType().Name + ": " + exception.Message, exception); }
        results.AddRange(NativeMailboxClient.RunQuestDetailsReadActionContractSelfTests());
        results.AddRange(NativeMailboxClient.RunQuestTroopScreenActionContractSelfTests());
        results.AddRange(AgentHostQuestTroopScreenLoop.RunContractSelfTests());
        results.AddRange(AgentHostCaptivityRecoveryLoop.RunContractSelfTests());
        results.AddRange(AgentHostEstablishClanGoldSaleLoop.RunContractSelfTests());
        try { results.AddRange(await AgentHostEstablishClanGoldSaleLoop.RunFailureTransportSelfTestsAsync()); }
        catch (Exception exception) { throw new AgentHostException("gold-sale-failure-transport-self-test-failed", exception.GetType().Name + ": " + exception.Message, exception); }
        try { results.AddRange(await AgentHostCaptivityRecoveryLoop.RunTransportSelfTestsAsync()); }
        catch (Exception exception) { throw new AgentHostException("captivity-recovery-loop-self-test-failed", exception.GetType().Name + ": " + exception.Message, exception); }
        try { results.AddRange(AgentHostVillageToolsQuestPolicy.RunContractSelfTests()); }
        catch (Exception exception) { throw new AgentHostException("village-tools-policy-self-test-failed", exception.GetType().Name + ": " + exception.Message, exception); }
        try { results.AddRange(await AgentHostVillageToolsQuestLoop.RunContractSelfTestsAsync()); }
        catch (Exception exception) { throw new AgentHostException("village-tools-loop-self-test-failed", exception.GetType().Name + ": " + exception.Message, exception); }
        try { results.AddRange(await AgentHostEstablishYourClanGoalLoop.RunContractSelfTestsAsync()); }
        catch (Exception exception) { throw new AgentHostException("establish-clan-planner-self-test-failed", exception.GetType().Name + ": " + exception.Message, exception); }
        results.AddRange(AgentHostEstablishYourClanAutonomyLoop.RunContractSelfTests());
        results.AddRange(AgentHostCampaignLoop.RunContractSelfTests());
        results.AddRange(AgentHostBattleSimulationLoop.RunContractSelfTests());
        results.AddRange(AgentHostBattleMissionLoop.RunContractSelfTests());
        try { results.AddRange(await AgentHostBattleSimulationLoop.RunTransportSelfTestsAsync()); }
        catch (Exception exception) { throw new AgentHostException("battle-simulation-loop-self-test-failed", exception.GetType().Name + ": " + exception.Message, exception); }
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

        var localGatewayCredential = AgentProviderConfigurationValidator.SelectApiKey(
            "http://127.0.0.1:31415/v1", "sk-paid-provider", "sk-paid-user", null, "freellmapi-user");
        var remoteProviderCredential = AgentProviderConfigurationValidator.SelectApiKey(
            "https://api.deepseek.com/v1", "sk-process-provider", "sk-user-provider", null, "freellmapi-user");
        var remoteRejectsDedicatedGatewayKey = AgentProviderConfigurationValidator.SelectApiKey(
            "https://api.deepseek.com/v1", null, null, null, "freellmapi-user");
        var dshWorkBuddyCredential = AgentProviderConfigurationValidator.SelectApiKey(
            "http://127.0.0.1:8328/v1", "paid-provider-process", "paid-provider-user", "freellmapi-process", "freellmapi-user",
            "dsh-workbuddy-process", "dsh-workbuddy-user");
        var dshWorkBuddyRejectsGenericCredential = AgentProviderConfigurationValidator.SelectApiKey(
            "http://127.0.0.1:8328/v1", "paid-provider-process", "paid-provider-user", "freellmapi-process", "freellmapi-user");
        if (localGatewayCredential.ApiKey != "freellmapi-user" || localGatewayCredential.Source != "FREELLMAPI_API_KEY:User" ||
            remoteProviderCredential.ApiKey != "sk-process-provider" || remoteProviderCredential.Source != "CHRONICLE_LLM_API_KEY:Process" ||
            remoteRejectsDedicatedGatewayKey.ApiKey is not null ||
            dshWorkBuddyCredential.ApiKey != "dsh-workbuddy-process" || dshWorkBuddyCredential.Source != "CHRONICLE_DSH_XDPOOL_API_KEY:Process" ||
            dshWorkBuddyRejectsGenericCredential.ApiKey is not null)
            throw new AgentHostException("provider-credential-selection-self-test-failed", "Provider credentials must follow the configured endpoint: dedicated FreeLLMAPI key for its local loopback gateway and generic key only for other providers.");
        results.Add(new { scenario = "provider-credential-selection-is-endpoint-scoped", passed = true });

        var workBuddyEndpoint = new Uri("http://127.0.0.1:8328/v1/chat/completions");
        if (OllamaNativeProvider.ResolveOutputModeForEndpoint(workBuddyEndpoint, "auto") != "json_object" ||
            OllamaNativeProvider.ResolveOutputModeForEndpoint(workBuddyEndpoint, "json_object") != "json_object" ||
            OllamaNativeProvider.ResolveOutputModeForEndpoint(workBuddyEndpoint, "json_schema") != "json_object" ||
            OllamaNativeProvider.ResolveOutputModeForEndpoint(workBuddyEndpoint, "required_tool_call") != "json_object" ||
            OllamaNativeProvider.ResolveOutputModeForEndpoint(new Uri("https://api.deepseek.com/v1/chat/completions"), "json_schema") != "json_schema" ||
            !OllamaNativeProvider.ResolveSystemPromptForEndpoint(workBuddyEndpoint, "Return one required decision-tool call only.").Contains("JSON decision object only", StringComparison.Ordinal) ||
            OllamaNativeProvider.ResolveSystemPromptForEndpoint(workBuddyEndpoint, "Return one required decision-tool call only.").Contains("required decision-tool call", StringComparison.Ordinal) ||
            OllamaNativeProvider.ResolveSystemPromptForEndpoint(new Uri("https://api.deepseek.com/v1/chat/completions"), "Return one required decision-tool call only.") != "Return one required decision-tool call only.")
            throw new AgentHostException("provider-workbuddy-output-mode-adapter-self-test-failed", "The DSH WorkBuddy endpoint must pin its verified JSON Object wire format without changing other provider profiles.");
        results.Add(new { scenario = "dsh-workbuddy-provider-pins-json-object-and-aligns-prompt-while-preserving-other-provider-profile", passed = true, modelCalls = 0, nativeCommands = 0 });

        using (var workBuddyEycClassificationRequest = JsonDocument.Parse("""
            {"goal":"完成原版StoryMode建立你的家族主线任务","goalScopeClassificationRequired":true,"observation":{"privateSentinel":"must-not-be-forwarded"},"allowedActions":[],"allowedControls":["supportedEstablishYourClanGoal","unsupportedGoal"]}
            """))
        {
            var compactPrompt = OllamaNativeProvider.ResolveSystemPromptForEndpoint(workBuddyEndpoint,
                "Return one required decision-tool call only.", workBuddyEycClassificationRequest.RootElement);
            var compactUserContent = OllamaNativeProvider.ResolveUserContentForEndpoint(workBuddyEndpoint, workBuddyEycClassificationRequest.RootElement);
            var unchangedRemoteUserContent = OllamaNativeProvider.ResolveUserContentForEndpoint(
                new Uri("https://api.deepseek.com/v1/chat/completions"), workBuddyEycClassificationRequest.RootElement);
            if (!compactPrompt.Contains("four Journal objectives are steps toward that goal", StringComparison.Ordinal) ||
                compactPrompt.Contains("required decision-tool call", StringComparison.Ordinal) ||
                !compactUserContent.Contains("supportedEstablishYourClanGoal", StringComparison.Ordinal) ||
                !compactUserContent.Contains("unsupportedGoal", StringComparison.Ordinal) ||
                compactUserContent.Contains("must-not-be-forwarded", StringComparison.Ordinal) ||
                compactUserContent.Contains("allowedActions", StringComparison.Ordinal) ||
                !unchangedRemoteUserContent.Contains("must-not-be-forwarded", StringComparison.Ordinal))
                throw new AgentHostException("dsh-workbuddy-eyc-classification-projection-self-test-failed", "WorkBuddy EYC classification must send only the complete goal and listed controls with a matching JSON prompt, while leaving other provider requests unchanged.");
            results.Add(new { scenario = "dsh-workbuddy-eyc-classifier-compacts-input-and-aligns-json-output", passed = true, modelCalls = 0, nativeCommands = 0 });
        }

        var remoteProxyEndpoint = new Uri("https://api.deepseek.com/v1");
        if (ProviderProxySelection.SelectProxyUrl(remoteProxyEndpoint, "http://explicit-https-proxy:8080", "http://http-proxy:8080", null, true) != "http://explicit-https-proxy:8080" ||
            ProviderProxySelection.SelectProxyUrl(remoteProxyEndpoint, null, "http://explicit-http-proxy:8080", null, true) != "http://explicit-http-proxy:8080" ||
            ProviderProxySelection.SelectProxyUrl(remoteProxyEndpoint, null, null, null, true) != ProviderProxySelection.LocalFallbackProxyUrl ||
            ProviderProxySelection.SelectProxyUrl(remoteProxyEndpoint, null, null, null, false) is not null ||
            ProviderProxySelection.SelectProxyUrl(remoteProxyEndpoint, null, null, null, true, "127.0.0.1,localhost") != ProviderProxySelection.LocalFallbackProxyUrl ||
            ProviderProxySelection.SelectProxyUrl(remoteProxyEndpoint, "http://explicit-https-proxy:8080", null, null, true, "api.deepseek.com") is not null ||
            ProviderProxySelection.SelectProxyUrl(new Uri("http://127.0.0.1:31415/v1"), null, null, null, true) is not null ||
            !ProviderProxySelection.IsNoProxyMatch("api.deepseek.com", ".deepseek.com"))
            throw new AgentHostException("provider-proxy-selection-self-test-failed", "Remote provider requests must respect an explicit proxy, fall back to the detected local 7890 listener only when needed, and leave loopback providers direct.");
        results.Add(new { scenario = "provider-proxy-selection-respects-configured-route-and-local-listener-with-loopback-bypass", passed = true });

        using (var validProfile = JsonDocument.Parse("{\"OllamaBaseUrl\":\"http://127.0.0.1:31415/v1\",\"ModelId\":\"auto\",\"schemaVersion\":0,\"LegacySetting\":true,\"CampaignGoal\":\"older-MCM-key\"}"))
        {
            var profile = AgentProviderProfile.Parse(validProfile.RootElement);
            if (profile.BaseUrl != "http://127.0.0.1:31415/v1" || profile.ModelId != "auto")
                throw new AgentHostException("provider-profile-self-test-normalization-failed", "The global MCM profile did not preserve its legacy provider URL and model identifier.");
            if (AgentProviderProfile.GetSettingsValidationError(profile.BaseUrl, profile.ModelId) is not null)
                throw new AgentHostException("provider-profile-self-test-settings-check-failed", "The MCM configuration check rejected valid local model settings.");
            results.Add(new { scenario = "mcm-global-profile-values-normalized", passed = true });
            results.Add(new { scenario = "mcm-global-profile-tolerates-legacy-and-unknown-fields", passed = true });
        }

        using (var remoteProfile = JsonDocument.Parse("{\"ProviderBaseUrl\":\"https://api.deepseek.com/v1\",\"ModelId\":\"deepseek-flash\"}"))
        {
            var profile = AgentProviderProfile.Parse(remoteProfile.RootElement);
            if (profile.BaseUrl != "https://api.deepseek.com/v1" || profile.ModelId != "deepseek-flash" || profile.DeepSeekRunCostLimitCny != 5d ||
                AgentProviderProfile.GetSettingsValidationError(profile.BaseUrl, profile.ModelId) is not null)
                throw new AgentHostException("provider-profile-self-test-remote-endpoint-failed", "A generic HTTPS OpenAI-compatible profile was not accepted.");
            results.Add(new { scenario = "mcm-profile-accepts-generic-https-openai-compatible-provider", passed = true });
        }
        var providerEnvironmentNames = new[]
        {
            "CHRONICLE_LLM_THINKING_MODE", "CHRONICLE_LLM_MAX_TOKENS", "CHRONICLE_LLM_MAX_TOKEN_PARAMETER",
            "CHRONICLE_LLM_REASONING_EFFORT", "CHRONICLE_LLM_MAX_RUN_COST_CNY", "CHRONICLE_LLM_TEMPERATURE"
        };
        var previousProviderEnvironment = providerEnvironmentNames.ToDictionary(name => name, name => Environment.GetEnvironmentVariable(name), StringComparer.Ordinal);
        try
        {
            foreach (var name in providerEnvironmentNames) Environment.SetEnvironmentVariable(name, null);
            Environment.SetEnvironmentVariable("CHRONICLE_LLM_THINKING_MODE", "disabled");
            using var deepSeekLaunch = JsonDocument.Parse("{\"providerConfiguration\":{\"ProviderBaseUrl\":\"https://api.deepseek.com/v1\",\"ModelId\":\"deepseek-flash\",\"OutputMode\":\"auto\"}} ");
            using var deepSeekProvider = OllamaNativeProvider.FromCampaignRequest(deepSeekLaunch.RootElement);
            if (deepSeekProvider.OutputMode != "required_tool_call" || deepSeekProvider.ThinkingMode != false ||
                deepSeekProvider.MaxOutputTokens != 256 || deepSeekProvider.ReservedCostUpperBoundCny != 0d)
                throw new AgentHostException("deepseek-provider-profile-self-test-failed", "The DeepSeek MCM profile did not select bounded, non-thinking strict tool-call output from auto mode.");
            results.Add(new { scenario = "deepseek-auto-profile-selects-bounded-non-thinking-strict-tool-calls", passed = true });
        }
        finally
        {
            foreach (var name in providerEnvironmentNames)
                Environment.SetEnvironmentVariable(name, previousProviderEnvironment[name]);
        }
        ExpectInvalidProfile("{\"ProviderBaseUrl\":\"http://example.com/v1\",\"ModelId\":\"test\"}", "provider-profile-endpoint-invalid", "mcm-profile-rejects-insecure-remote-http");
        results.Add(new { scenario = "mcm-profile-rejects-insecure-remote-http", passed = true });
        ExpectInvalidProfile("{\"ProviderBaseUrl\":\"https://api.deepseek.com/v1\",\"ModelId\":\"deepseek-flash\",\"DeepSeekRunCostLimitCny\":\"0\"}", "provider-profile-run-cost-invalid", "mcm-profile-rejects-nonpositive-deepseek-run-budget");
        results.Add(new { scenario = "mcm-profile-rejects-nonpositive-deepseek-run-budget", passed = true });
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
        var priorHttpRequestLimit = Environment.GetEnvironmentVariable("CHRONICLE_LLM_MAX_HTTP_REQUESTS_PER_DECISION");
        try
        {
            Environment.SetEnvironmentVariable("CHRONICLE_LLM_MAX_TOKENS", "512");
            Environment.SetEnvironmentVariable("CHRONICLE_LLM_TIMEOUT_SECONDS", "180");
            Environment.SetEnvironmentVariable("CHRONICLE_LLM_MAX_HTTP_REQUESTS_PER_DECISION", null);
            using var launchWithBudget = JsonDocument.Parse("{\"providerConfiguration\":{\"OllamaBaseUrl\":\"http://127.0.0.1:31415/v1\",\"ModelId\":\"auto\"}}");
            using var budgetProvider = OllamaNativeProvider.FromCampaignRequest(launchWithBudget.RootElement);
            if (budgetProvider.ModelId != "auto" || budgetProvider.MaxOutputTokens != 512 || budgetProvider.MaxHttpRequestsPerDecision != 1)
                throw new AgentHostException("freellmapi-profile-budget-self-test-failed", "Host did not apply the bounded FreeLLMAPI output budget from the current process configuration.");
            results.Add(new { scenario = "freellmapi-profile-uses-512-token-and-one-http-request-per-decision-default", passed = true });
        }
        finally
        {
            Environment.SetEnvironmentVariable("CHRONICLE_LLM_MAX_TOKENS", priorMaxTokens);
            Environment.SetEnvironmentVariable("CHRONICLE_LLM_TIMEOUT_SECONDS", priorTimeoutSeconds);
            Environment.SetEnvironmentVariable("CHRONICLE_LLM_MAX_HTTP_REQUESTS_PER_DECISION", priorHttpRequestLimit);
        }
        using (var invalidLaunch = JsonDocument.Parse("{\"providerConfiguration\":{\"OllamaBaseUrl\":\"http://example.com/v1\",\"ModelId\":\"test\"}}"))
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

        using (var actionRequest = JsonDocument.Parse(BuildActionDecisionRequest()))
        using (var actionWithoutRationale = JsonDocument.Parse("{\"decision\":{\"action\":\"tradeConfirm\",\"arguments\":{}}}"))
        {
            var normalized = OllamaNativeProvider.NormalizeDecision(actionWithoutRationale.RootElement, actionRequest.RootElement);
            var schema = OllamaNativeProvider.BuildDecisionSchema(actionRequest.RootElement);
            var alternatives = schema["properties"]?["decision"]?["anyOf"] as JsonArray;
            var firstBranch = alternatives?[0] as JsonObject;
            var required = firstBranch?["required"] as JsonArray ?? new JsonArray();
            if (normalized["action"]?.GetValue<string>() != "tradeConfirm" ||
                normalized["rationale"]?.GetValue<string>() != string.Empty ||
                schema["type"]?.GetValue<string>() != "object" || schema["oneOf"] is not null ||
                alternatives?.Count != 1 || firstBranch?["properties"]?["rationale"] is not null ||
                firstBranch?["properties"]?["action"]?["enum"]?[0]?.GetValue<string>() != "tradeConfirm" ||
                required.Count != 2 || required[0]?.GetValue<string>() != "action" || required[1]?.GetValue<string>() != "arguments" ||
                firstBranch?["additionalProperties"]?.GetValue<bool>() != false)
                throw new AgentHostException("provider-self-test-decision-schema-strict-subset-failed", "The provider schema must use an object root with a nested anyOf, only supported constraints, and required action arguments; Native normalization still accepts the flattened action.");

            using var toolActionAlias = JsonDocument.Parse("{\"tool\":\"tradeConfirm\",\"arguments\":{}}");
            var normalizedToolActionAlias = OllamaNativeProvider.NormalizeDecision(toolActionAlias.RootElement, actionRequest.RootElement);
            if (normalizedToolActionAlias["action"]?.GetValue<string>() != "tradeConfirm")
                throw new AgentHostException("provider-self-test-listed-tool-alias-action-failed", "A provider tool alias must normalize only when it matches a current Native action.");

            using var invalidWrapper = JsonDocument.Parse("{\"decision\":{\"action\":\"tradeConfirm\",\"arguments\":{}},\"extra\":true}");
            try
            {
                _ = OllamaNativeProvider.NormalizeDecision(invalidWrapper.RootElement, actionRequest.RootElement);
                throw new AgentHostException("provider-self-test-decision-wrapper-overbroad", "The decision wrapper accepted an extra top-level property.");
            }
            catch (AgentHostException exception) when (exception.Code == "provider-decision-wrapper-invalid") { }

            using var ambiguousDecision = JsonDocument.Parse("{\"action\":\"tradeConfirm\",\"control\":\"tradeConfirm\",\"arguments\":{}}");
            try
            {
                _ = OllamaNativeProvider.NormalizeDecision(ambiguousDecision.RootElement, actionRequest.RootElement);
                throw new AgentHostException("provider-self-test-ambiguous-shape-accepted", "The provider accepted simultaneous action and action-name control fields.");
            }
            catch (AgentHostException exception) when (exception.Code == "provider-decision-ambiguous")
            {
                if (exception.ProviderDecisionFieldShape != "action:String_control:String_arguments:Object")
                    throw new AgentHostException("provider-self-test-ambiguous-shape-not-retained",
                        $"An ambiguous decision must retain only its bounded field-name/type shape (actual={exception.ProviderDecisionFieldShape ?? "not-reported"}).");
            }
            results.Add(new { scenario = "provider-decision-ambiguity-retains-safe-field-shape", passed = true });

            var longRationale = string.Join(' ', Enumerable.Range(1, 25).Select(index => "word" + index));
            using var longActionDecision = JsonDocument.Parse(JsonSerializer.Serialize(new
            {
                action = "tradeConfirm",
                arguments = new { },
                rationale = longRationale
            }));
            var longActionNormalized = OllamaNativeProvider.NormalizeDecision(longActionDecision.RootElement, actionRequest.RootElement);
            var expectedBoundedRationale = string.Join(' ', Enumerable.Range(1, 20).Select(index => "word" + index));
            if (longActionNormalized["action"]?.GetValue<string>() != "tradeConfirm" ||
                longActionNormalized["rationale"]?.GetValue<string>() != expectedBoundedRationale)
                throw new AgentHostException("provider-self-test-long-rationale-blocked-valid-action", "An overlong explanatory field must be bounded without discarding a Native-catalog-validated action.");
            results.Add(new { scenario = "provider-bounds-overlong-action-rationale-without-blocking-validated-action", passed = true });

            results.Add(new { scenario = "provider-action-rationale-is-optional-and-native-catalog-still-gates", passed = true });
            results.Add(new { scenario = "provider-decision-schema-uses-strict-compatible-root-wrapper", passed = true });
        }

        using (var mapIncidentRequest = JsonDocument.Parse("""
        {"goal":"Resolve the current Native incident.","observation":{"state":{"context":{"mapIncident":{"active":true}}}},"allowedActions":[{"action":"incidentSelect","arguments":["OptionIndex"],"argumentValues":{"OptionIndex":[0,1,2]}}],"allowedControls":[]}
        """))
        using (var numericIncidentDecision = JsonDocument.Parse("{\"action\":\"incidentSelect\",\"arguments\":{\"OptionIndex\":1}}"))
        {
            var schema = OllamaNativeProvider.BuildDecisionSchema(mapIncidentRequest.RootElement);
            var optionIndexSchema = schema["properties"]?["decision"]?["anyOf"]?[0]?["properties"]?["arguments"]?["properties"]?["OptionIndex"] as JsonObject;
            var normalized = OllamaNativeProvider.NormalizeDecision(numericIncidentDecision.RootElement, mapIncidentRequest.RootElement);
            if (optionIndexSchema?["type"]?.GetValue<string>() != "integer" ||
                optionIndexSchema["enum"] is not JsonArray optionIndexEnum || optionIndexEnum.Count != 3 ||
                optionIndexEnum[0]?.GetValue<int>() != 0 || optionIndexEnum[1]?.GetValue<int>() != 1 || optionIndexEnum[2]?.GetValue<int>() != 2 ||
                normalized["arguments"]?["OptionIndex"]?.GetValue<int>() != 1)
                throw new AgentHostException("provider-map-incident-index-schema-invalid", "The current Native incident option index must be a bounded integer enum in the model's structured-output schema and normalization path.");
            results.Add(new { scenario = "provider-map-incident-option-index-is-integer-enum-not-string", passed = true });
        }

        using (var prisonerRecruitmentRequest = JsonDocument.Parse("""
        {"goal":"Recruit one eligible Native prisoner.","observation":{"state":{"party":{"members":13}}},"allowedActions":[{"action":"recruitPrisoner","arguments":["TroopId","ConfirmPartySizeWarning","ConfirmPrisonerLimitWarning"],"argumentValues":{"TroopId":["looter"],"ConfirmPartySizeWarning":[0,1],"ConfirmPrisonerLimitWarning":[1]}}],"allowedControls":[]}
        """))
        {
            var schema = OllamaNativeProvider.BuildDecisionSchema(prisonerRecruitmentRequest.RootElement);
            var properties = schema["properties"]?["decision"]?["anyOf"]?[0]?["properties"]?["arguments"]?["properties"];
            var troopIdSchema = properties?["TroopId"] as JsonObject;
            var partyWarningSchema = properties?["ConfirmPartySizeWarning"] as JsonObject;
            var prisonerWarningSchema = properties?["ConfirmPrisonerLimitWarning"] as JsonObject;
            if (troopIdSchema?["type"]?.GetValue<string>() != "string" ||
                partyWarningSchema?["type"]?.GetValue<string>() != "integer" ||
                partyWarningSchema["enum"] is not JsonArray partyWarningEnum || partyWarningEnum.Count != 2 ||
                partyWarningEnum[0]?.GetValue<int>() != 0 || partyWarningEnum[1]?.GetValue<int>() != 1 ||
                prisonerWarningSchema?["type"]?.GetValue<string>() != "integer" ||
                prisonerWarningSchema["enum"] is not JsonArray prisonerWarningEnum || prisonerWarningEnum.Count != 1 ||
                prisonerWarningEnum[0]?.GetValue<int>() != 1)
                throw new AgentHostException("provider-prisoner-recruitment-enum-schema-invalid", "The current Native prisoner recruitment catalog supplies integer confirmation enums; the model schema must preserve their JSON number type and exact values.");
            results.Add(new { scenario = "provider-prisoner-recruitment-confirmations-follow-native-integer-enums", passed = true });
        }

        using (var oneChoiceArgumentRequest = JsonDocument.Parse("""
        {"goal":"Answer the current Native inquiry.","observation":{"state":{"context":{"inquiryOpen":true}}},"allowedActions":[{"action":"respondInquiry","arguments":["choice"],"argumentValues":{"choice":["affirmative","negative"]}}],"allowedControls":[]}
        """))
        using (var scalarChoiceDecision = JsonDocument.Parse("{\"action\":\"respondInquiry\",\"arguments\":\"affirmative\"}"))
        {
            var repaired = OllamaNativeProvider.NormalizeDecision(scalarChoiceDecision.RootElement, oneChoiceArgumentRequest.RootElement);
            if (repaired["action"]?.GetValue<string>() != "respondInquiry" ||
                repaired["arguments"]?["choice"]?.GetValue<string>() != "affirmative")
                throw new AgentHostException("provider-single-enum-argument-normalization-failed", "A raw single-argument enum value was not mapped to its exact currently listed Native argument.");

            using var unlistedScalar = JsonDocument.Parse("{\"action\":\"respondInquiry\",\"arguments\":\"teleport\"}");
            try
            {
                _ = OllamaNativeProvider.NormalizeDecision(unlistedScalar.RootElement, oneChoiceArgumentRequest.RootElement);
                throw new AgentHostException("provider-unlisted-scalar-argument-accepted", "A scalar shorthand outside the active Native enum values was accepted.");
            }
            catch (AgentHostException exception) when (exception.Code == "provider-arguments-invalid-json") { }
            results.Add(new { scenario = "provider-repairs-only-exact-listed-single-enum-argument-shorthand", passed = true });

            using var clanNameRequest = JsonDocument.Parse("""
            {"goal":"Choose a valid family name.","observation":{"state":{"context":{"inquiryOpen":true}}},"allowedActions":[{"action":"submitStoryModeClanName","arguments":["text"]}],"allowedControls":[]}
            """);
            using var clanNameScalar = JsonDocument.Parse("{\"action\":\"submitStoryModeClanName\",\"arguments\":\"Chronicle Wolves\"}");
            var clanNameNormalized = OllamaNativeProvider.NormalizeDecision(clanNameScalar.RootElement, clanNameRequest.RootElement);
            if (clanNameNormalized["action"]?.GetValue<string>() != "submitStoryModeClanName" ||
                clanNameNormalized["arguments"]?["text"]?.GetValue<string>() != "Chronicle Wolves")
                throw new AgentHostException("provider-storymode-text-argument-normalization-failed", "A raw scalar clan-name string was not mapped to the single listed Native text field.");
            results.Add(new { scenario = "provider-repairs-single-storymode-clan-name-text-shorthand-for-native-validation", passed = true });
        }

        using (var movementWaitRequest = JsonDocument.Parse("""
        {"goal":"Passively observe active Native map travel.","observation":{"state":{"party":{"isMoving":true}}},"allowedActions":[],"allowedControls":["observeAgain"],"controlArguments":{"observeAgain":{"waitSeconds":{"type":"integer","minimum":5,"maximum":10}}}}
        """))
        {
            var schema = OllamaNativeProvider.BuildDecisionSchema(movementWaitRequest.RootElement);
            var observeBranch = (schema["properties"]?["decision"]?["anyOf"] as JsonArray)?.OfType<JsonObject>()
                .FirstOrDefault(branch => branch["properties"]?["control"]?["enum"]?[0]?.GetValue<string>() == "observeAgain");
            if (observeBranch?["properties"]?["waitSeconds"]?["minimum"]?.GetValue<int>() != 5 ||
                observeBranch["properties"]?["waitSeconds"]?["maximum"]?.GetValue<int>() != 10)
                throw new AgentHostException("provider-self-test-observe-again-schema-ignored-current-bounds", "Structured output must use the current movement wait bounds instead of a generic interval.");

            using var tooShort = JsonDocument.Parse("{\"control\":\"observeAgain\",\"waitSeconds\":1,\"reason\":\"Wait briefly.\"}");
            try
            {
                _ = OllamaNativeProvider.NormalizeDecision(tooShort.RootElement, movementWaitRequest.RootElement);
                throw new AgentHostException("provider-self-test-observe-again-short-wait-accepted", "A 1-second poll must not pass the active-travel decision contract.");
            }
            catch (AgentHostException exception) when (exception.Code == "provider-control-arguments-invalid") { }

            using var validWait = JsonDocument.Parse("{\"control\":\"observeAgain\",\"waitSeconds\":8,\"reason\":\"Continue map travel.\"}");
            var normalizedWait = OllamaNativeProvider.NormalizeDecision(validWait.RootElement, movementWaitRequest.RootElement);
            if (normalizedWait["waitSeconds"]?.GetValue<int>() != 8 || normalizedWait["observeAgain"]?.GetValue<bool>() != true)
                throw new AgentHostException("provider-self-test-observe-again-valid-wait-not-normalized", "An in-range active-travel observation interval must remain a passive wait decision.");
            results.Add(new { scenario = "provider-structured-output-enforces-context-specific-active-travel-observe-interval", passed = true });
        }

        using (var fixedMovementWaitRequest = JsonDocument.Parse("""
        {"goal":"Passively observe an active PartySize settlement move.","observation":{"state":{"party":{"isMoving":true}}},"allowedActions":[],"allowedControls":["observeAgain"],"controlArguments":{"observeAgain":{"waitSeconds":{"type":"integer","minimum":10,"maximum":10}}}}
        """))
        {
            var schema = OllamaNativeProvider.BuildDecisionSchema(fixedMovementWaitRequest.RootElement);
            var observeBranch = (schema["properties"]?["decision"]?["anyOf"] as JsonArray)?.OfType<JsonObject>()
                .FirstOrDefault(branch => branch["properties"]?["control"]?["enum"]?[0]?.GetValue<string>() == "observeAgain");
            if (observeBranch?["properties"]?["waitSeconds"]?["minimum"]?.GetValue<int>() != 10 ||
                observeBranch["properties"]?["waitSeconds"]?["maximum"]?.GetValue<int>() != 10)
                throw new AgentHostException("provider-self-test-fixed-observe-again-schema-invalid", "The PartySize control schema sent to the structured-output provider must require exactly ten seconds.");

            foreach (var invalidSeconds in new[] { 9, 11 })
            {
                using var invalidDecision = JsonDocument.Parse($"{{\"control\":\"observeAgain\",\"waitSeconds\":{invalidSeconds},\"reason\":\"Continue map travel.\"}}");
                try
                {
                    _ = OllamaNativeProvider.NormalizeDecision(invalidDecision.RootElement, fixedMovementWaitRequest.RootElement);
                    throw new AgentHostException("provider-self-test-fixed-observe-again-boundary-accepted", $"The exact-ten-second PartySize contract accepted {invalidSeconds} seconds.");
                }
                catch (AgentHostException exception) when (exception.Code == "provider-control-arguments-invalid") { }
            }

            using var validDecision = JsonDocument.Parse("{\"control\":\"observeAgain\",\"waitSeconds\":10,\"reason\":\"Continue map travel.\"}");
            var normalized = OllamaNativeProvider.NormalizeDecision(validDecision.RootElement, fixedMovementWaitRequest.RootElement);
            if (normalized["waitSeconds"]?.GetValue<int>() != 10 || normalized["observeAgain"]?.GetValue<bool>() != true)
                throw new AgentHostException("provider-self-test-fixed-observe-again-valid-decision-not-normalized", "An exact-ten-second PartySize observation must remain an observeAgain control.");
            results.Add(new { scenario = "provider-structured-output-enforces-exact-party-size-movement-wait", passed = true });
        }

        using (var listedStopRequest = JsonDocument.Parse("{\"goal\":\"Safely stop this subgoal.\",\"observation\":{},\"allowedActions\":[],\"allowedControls\":[\"stop\"]}"))
        using (var stopDecision = JsonDocument.Parse("{\"control\":\"stop\",\"reason\":\"No safe action now.\"}"))
        {
            var normalizedStop = OllamaNativeProvider.NormalizeDecision(stopDecision.RootElement, listedStopRequest.RootElement);
            if (normalizedStop["stop"]?.GetValue<bool>() != true || normalizedStop["reason"]?.GetValue<string>() != "No safe action now.")
                throw new AgentHostException("provider-stop-control-normalization-failed", "A workflow-listed safe stop must normalize without becoming goal completion.");
            using var unlistedStopRequest = JsonDocument.Parse("{\"goal\":\"Choose an action.\",\"observation\":{},\"allowedActions\":[],\"allowedControls\":[]}");
            try
            {
                _ = OllamaNativeProvider.NormalizeDecision(stopDecision.RootElement, unlistedStopRequest.RootElement);
                throw new AgentHostException("provider-unlisted-stop-control-accepted", "The provider accepted a stop control not allowed by the current workflow.");
            }
            catch (AgentHostException exception) when (exception.Code == "provider-control-unavailable") { }
            results.Add(new { scenario = "provider-normalizes-only-workflow-listed-safe-stop-control", passed = true });
        }

        using (var classificationRequest = JsonDocument.Parse("{\"goal\":\"Classify the active goal.\",\"observation\":{},\"allowedActions\":[],\"allowedControls\":[\"supportedEstablishYourClanGoal\"],\"goalScopeClassificationRequired\":true}"))
        using (var uniformControlEnvelope = JsonDocument.Parse("{\"control\":\"supportedEstablishYourClanGoal\",\"arguments\":{}}"))
        {
            var schema = OllamaNativeProvider.BuildDecisionSchema(classificationRequest.RootElement);
            var branch = (schema["properties"]?["decision"]?["anyOf"] as JsonArray)?.OfType<JsonObject>()
                .FirstOrDefault(item => item["properties"]?["control"]?["enum"]?[0]?.GetValue<string>() == "supportedEstablishYourClanGoal");
            var required = branch?["required"] as JsonArray;
            var normalized = OllamaNativeProvider.NormalizeDecision(uniformControlEnvelope.RootElement, classificationRequest.RootElement);
            if (normalized["goalClassification"]?.GetValue<string>() != "supported-establish-your-clan" ||
                required is null || required.Count != 1 || required[0]?.GetValue<string>() != "control" ||
                branch?["properties"]?["arguments"]?["additionalProperties"]?.GetValue<bool>() != false ||
                branch["properties"]?["reason"] is null)
                throw new AgentHostException("provider-goal-control-uniform-envelope-regression", "A catalog-listed goal control must accept the standard empty arguments envelope while keeping arguments and rationale non-authoritative.");

            using var toolControlAlias = JsonDocument.Parse("{\"tool\":\"supportedEstablishYourClanGoal\",\"reason\":\"Active quest scope.\"}");
            var normalizedToolControlAlias = OllamaNativeProvider.NormalizeDecision(toolControlAlias.RootElement, classificationRequest.RootElement);
            if (normalizedToolControlAlias["goalClassification"]?.GetValue<string>() != "supported-establish-your-clan")
                throw new AgentHostException("provider-self-test-listed-tool-alias-control-failed", "A provider tool alias must normalize only when it matches a current Native control.");

            using var nonemptyArguments = JsonDocument.Parse("{\"control\":\"supportedEstablishYourClanGoal\",\"arguments\":{\"ObjectiveId\":\"gold\"}}");
            try
            {
                _ = OllamaNativeProvider.NormalizeDecision(nonemptyArguments.RootElement, classificationRequest.RootElement);
                throw new AgentHostException("provider-goal-control-nonempty-arguments-accepted", "A goal-classification control must not accept unlisted nested arguments.");
            }
            catch (AgentHostException exception) when (exception.Code == "provider-control-arguments-invalid") { }

            using var unknownToolAlias = JsonDocument.Parse("{\"tool\":\"teleport\"}");
            try
            {
                _ = OllamaNativeProvider.NormalizeDecision(unknownToolAlias.RootElement, classificationRequest.RootElement);
                throw new AgentHostException("provider-self-test-unlisted-tool-alias-accepted", "A tool alias absent from current Native catalogs must be rejected.");
            }
            catch (AgentHostException exception) when (exception.Code == "provider-control-unavailable") { }
            results.Add(new { scenario = "provider-goal-control-accepts-only-empty-uniform-arguments-envelope", passed = true });
        }

        var visibleInquiry = new JsonObject
        {
            ["supported"] = true,
            ["kind"] = "YesNoInquiry",
            ["title"] = "通知",
            ["text"] = "玩家可见的原版提示",
            ["affirmative"] = new JsonObject { ["visible"] = true, ["enabled"] = true, ["text"] = "好" },
            ["negative"] = new JsonObject { ["visible"] = false, ["enabled"] = false, ["text"] = "" }
        };
        var inquiryRequestObject = AgentHostNativeInquiryResolution.BuildDecisionRequest("provider-native-inquiry-selftest", visibleInquiry, new JsonArray("affirmative"));
        using (var inquiryRequest = JsonDocument.Parse(inquiryRequestObject.ToJsonString()))
        {
            var inquiryHandler = new StubHandler((_, _) => Task.FromResult(JsonResponse(BuildChatResponse(
                "{\"action\":\"respondInquiry\",\"arguments\":{\"choice\":\"affirmative\"}}", "stop"))));
            using var inquiryClient = new HttpClient(inquiryHandler) { Timeout = settings.Timeout };
            using var inquiryProvider = new OllamaNativeProvider(settings, inquiryClient);
            var inquiryDecision = await inquiryProvider.DecideAsync(inquiryRequest.RootElement,
                AgentHostDecisionCycle.NativeInquiryResponseSystemPrompt, CancellationToken.None);
            var inquiryArguments = inquiryDecision.Decision["arguments"] as JsonObject;
            using var posted = JsonDocument.Parse(inquiryHandler.LastRequestBody ?? throw new AgentHostException("provider-self-test-inquiry-request-missing", "Native Inquiry decision did not reach the provider transport."));
            var schemaAlternatives = posted.RootElement.GetProperty("response_format").GetProperty("json_schema").GetProperty("schema")
                .GetProperty("properties").GetProperty("decision").GetProperty("anyOf");
            if (inquiryDecision.Decision["action"]?.GetValue<string>() != "respondInquiry" ||
                inquiryArguments?["choice"]?.GetValue<string>() != "affirmative" ||
                schemaAlternatives.GetArrayLength() != 2 ||
                !schemaAlternatives.GetRawText().Contains("affirmative", StringComparison.Ordinal) ||
                schemaAlternatives.GetRawText().Contains("inquiry-token", StringComparison.Ordinal) ||
                inquiryRequest.RootElement.GetProperty("allowedActions").GetArrayLength() != 1 ||
                inquiryRequest.RootElement.GetProperty("allowedControls").GetArrayLength() != 1)
                throw new AgentHostException("provider-self-test-native-inquiry-decision-envelope-invalid", "A Native Inquiry must use the production action/control decision envelope, expose only the enabled current choice, omit its anti-stale token, and reach the provider successfully.");
            results.Add(new { scenario = "native-inquiry-uses-standard-action-control-envelope-through-provider", passed = true, nativeCommands = 0 });
        }

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

        var reasoningEffortRequestShapeValid = false;
        var freeLlmApiReasoningHandler = new StubHandler((httpRequest, _) =>
        {
            if (httpRequest.Method == HttpMethod.Get)
                return Task.FromResult(JsonResponse("{\"data\":[{\"id\":\"free-reasoning-route\",\"supported_parameters\":[\"tools\",\"tool_choice\",\"reasoning_effort\"]}]}"));
            using var body = JsonDocument.Parse(httpRequest.Content!.ReadAsStringAsync().GetAwaiter().GetResult());
            reasoningEffortRequestShapeValid =
                body.RootElement.TryGetProperty("reasoning_effort", out var effort) && effort.GetString() == "low" &&
                body.RootElement.TryGetProperty("thinking", out var thinking) &&
                thinking.GetProperty("type").GetString() == "disabled";
            return Task.FromResult(JsonResponse(BuildToolCallChatResponse("{\"action\":\"tradeConfirm\",\"arguments\":{}}", "tool_calls")));
        });
        var freeLlmApiReasoningSettings = freeLlmApiSettings with
        {
            Model = "free-reasoning-route", OutputMode = "required_tool_call", Thinking = false, ReasoningEffort = "low"
        };
        using (var reasoningClient = new HttpClient(freeLlmApiReasoningHandler) { Timeout = freeLlmApiReasoningSettings.Timeout })
        using (var reasoningProvider = new OllamaNativeProvider(freeLlmApiReasoningSettings, reasoningClient))
        using (var request = JsonDocument.Parse(BuildActionDecisionRequest()))
        {
            await reasoningProvider.CheckConfiguredModelAsync(CancellationToken.None);
            var result = await reasoningProvider.DecideAsync(request.RootElement, CancellationToken.None);
            if (!reasoningEffortRequestShapeValid || result.ReasoningEffortApplied != "low" ||
                result.Decision["action"]?.GetValue<string>() != "tradeConfirm")
                throw new AgentHostException("freellmapi-reasoning-effort-support-contract-failed", "When FreeLLMAPI advertises reasoning_effort, the Host must send the configured low reasoning budget even with thinking disabled and report the applied setting.");
            results.Add(new { scenario = "freellmapi-advertised-reasoning-effort-low-is-applied-with-thinking-disabled", passed = true });
        }

        var unsupportedReasoningHandler = new StubHandler((httpRequest, _) => httpRequest.Method == HttpMethod.Get
            ? Task.FromResult(JsonResponse("{\"data\":[{\"id\":\"free-no-reasoning-route\",\"supported_parameters\":[\"tools\",\"tool_choice\"]}]}"))
            : Task.FromResult(JsonResponse(BuildToolCallChatResponse("{\"action\":\"tradeConfirm\",\"arguments\":{}}", "tool_calls"))));
        var unsupportedReasoningSettings = freeLlmApiSettings with
        {
            Model = "free-no-reasoning-route", OutputMode = "required_tool_call", Thinking = false, ReasoningEffort = "low"
        };
        using (var unsupportedReasoningClient = new HttpClient(unsupportedReasoningHandler) { Timeout = unsupportedReasoningSettings.Timeout })
        using (var unsupportedReasoningProvider = new OllamaNativeProvider(unsupportedReasoningSettings, unsupportedReasoningClient))
        using (var request = JsonDocument.Parse(BuildActionDecisionRequest()))
        {
            await unsupportedReasoningProvider.CheckConfiguredModelAsync(CancellationToken.None);
            var result = await unsupportedReasoningProvider.DecideAsync(request.RootElement, CancellationToken.None);
            using var sentBody = JsonDocument.Parse(unsupportedReasoningHandler.LastRequestBody ?? "{}");
            if (sentBody.RootElement.TryGetProperty("reasoning_effort", out _) || result.ReasoningEffortApplied is not null)
                throw new AgentHostException("freellmapi-unadvertised-reasoning-effort-was-sent", "The Host must not send reasoning_effort to a FreeLLMAPI route that did not advertise that request capability.");
            results.Add(new { scenario = "freellmapi-unadvertised-reasoning-effort-is-omitted", passed = true });
        }

        const string privatePlainTextToolFailure = "PRIVATE_FREE_LLM_API_RESPONSE_MUST_NOT_BE_LOGGED";
        var missingRequiredToolCallHandler = new StubHandler((httpRequest, _) =>
        {
            if (httpRequest.Method == HttpMethod.Get)
                return Task.FromResult(JsonResponse("{\"data\":[{\"id\":\"gpt-oss-20b\",\"supported_parameters\":[\"tools\",\"tool_choice\"]}]}"));
            var response = JsonResponse(JsonSerializer.Serialize(new
            {
                model = "gpt-oss-20b",
                choices = new[] { new { index = 0, message = new { role = "assistant", content = privatePlainTextToolFailure }, finish_reason = "stop" } },
                usage = new { prompt_tokens = 602, completion_tokens = 128 }
            }));
            response.Headers.TryAddWithoutValidation("X-Routed-Via", "ovh/gpt-oss-20b");
            return Task.FromResult(response);
        });
        using (var missingRequiredToolCallClient = new HttpClient(missingRequiredToolCallHandler) { Timeout = freeLlmApiSettings.Timeout })
        using (var missingRequiredToolCallProvider = new OllamaNativeProvider(freeLlmApiSettings with { Model = "gpt-oss-20b" }, missingRequiredToolCallClient))
        using (var request = JsonDocument.Parse(BuildDecisionRequest()))
        {
            await missingRequiredToolCallProvider.CheckConfiguredModelAsync(CancellationToken.None);
            try
            {
                _ = await missingRequiredToolCallProvider.DecideAsync(request.RootElement, CancellationToken.None);
                throw new AgentHostException("provider-required-tool-call-missing-self-test-failed", "A plain-text model response must not be accepted as a Native decision when the Host requires one tool call.");
            }
            catch (AgentHostException exception) when (exception.Code == "provider-tool-call-missing")
            {
                if (!exception.Message.Contains("toolCallsPresent=False", StringComparison.Ordinal) ||
                    !exception.Message.Contains("toolCallCount=0", StringComparison.Ordinal) ||
                    !exception.Message.Contains("contentKind=String", StringComparison.Ordinal) ||
                    !exception.Message.Contains("finishReason=stop", StringComparison.Ordinal) ||
                    !exception.Message.Contains("responseModel=gpt-oss-20b", StringComparison.Ordinal) ||
                    !exception.Message.Contains("routedVia=ovh/gpt-oss-20b", StringComparison.Ordinal) ||
                    !exception.Message.Contains("promptTokens=602", StringComparison.Ordinal) ||
                    !exception.Message.Contains("completionTokens=128", StringComparison.Ordinal) ||
                    exception.Message.Contains(privatePlainTextToolFailure, StringComparison.Ordinal))
                    throw new AgentHostException("provider-required-tool-call-missing-safe-diagnostic-self-test-failed", "A missing-tool response should log only route/shape/usage metadata, never the plain-text response itself.");
            }
            results.Add(new { scenario = "provider-required-tool-call-missing-response-logs-safe-route-shape-and-usage", modelCalls = 0, nativeCommands = 0, passed = true });
        }

        var truncatedRequiredToolCallHandler = new StubHandler((httpRequest, _) => httpRequest.Method == HttpMethod.Get
            ? Task.FromResult(JsonResponse("{\"data\":[{\"id\":\"gpt-oss-20b\",\"supported_parameters\":[\"tools\",\"tool_choice\"]}]}"))
            : Task.FromResult(JsonResponse(BuildChatResponse(privatePlainTextToolFailure, "length"))));
        using (var truncatedRequiredToolCallClient = new HttpClient(truncatedRequiredToolCallHandler) { Timeout = freeLlmApiSettings.Timeout })
        using (var truncatedRequiredToolCallProvider = new OllamaNativeProvider(freeLlmApiSettings with { Model = "gpt-oss-20b" }, truncatedRequiredToolCallClient))
        using (var request = JsonDocument.Parse(BuildDecisionRequest()))
        {
            await truncatedRequiredToolCallProvider.CheckConfiguredModelAsync(CancellationToken.None);
            try
            {
                _ = await truncatedRequiredToolCallProvider.DecideAsync(request.RootElement, CancellationToken.None);
                throw new AgentHostException("provider-truncated-required-tool-call-self-test-failed", "A length-limited required-tool response must not be accepted as an empty decision.");
            }
            catch (AgentHostException exception) when (exception.Code == "provider-response-truncated")
            {
                if (!exception.Message.Contains("finishReason=length", StringComparison.Ordinal) ||
                    exception.Message.Contains(privatePlainTextToolFailure, StringComparison.Ordinal))
                    throw new AgentHostException("provider-truncated-required-tool-call-safe-diagnostic-failed", "A truncated required-tool response must use the bounded truncation recovery code without logging its body.");
            }
            results.Add(new { scenario = "required-tool-call-length-response-is-routed-to-one-bounded-truncation-retry", modelCalls = 0, nativeCommands = 0, passed = true });
        }

        var incompatibleSchemaResponseBody = "{\"model\":\"free-schema-mismatch\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":null,\"tool_calls\":[{\"id\":\"private-call-id\",\"type\":\"function\",\"function\":{\"name\":\"submit_chronicle_decision\",\"arguments\":\"PRIVATE_RESPONSE_SHOULD_NOT_LEAK\"}}]},\"finish_reason\":\"tool_calls\"}],\"usage\":{\"prompt_tokens\":449,\"completion_tokens\":113}}";
        var incompatibleSchemaHandler = new StubHandler((httpRequest, _) => httpRequest.Method == HttpMethod.Get
            ? Task.FromResult(JsonResponse("{\"data\":[{\"id\":\"free-schema-mismatch\",\"supported_parameters\":[\"response_format\"]}]}"))
            : Task.FromResult(JsonResponse(incompatibleSchemaResponseBody)));
        using (var incompatibleSchemaClient = new HttpClient(incompatibleSchemaHandler) { Timeout = freeLlmApiSettings.Timeout })
        using (var incompatibleSchemaProvider = new OllamaNativeProvider(freeLlmApiSettings with { Model = "free-schema-mismatch" }, incompatibleSchemaClient))
        using (var request = JsonDocument.Parse(BuildDecisionRequest()))
        {
            await incompatibleSchemaProvider.CheckConfiguredModelAsync(CancellationToken.None);
            try
            {
                _ = await incompatibleSchemaProvider.DecideAsync(request.RootElement, CancellationToken.None);
                throw new AgentHostException("freellmapi-schema-toolcall-mismatch-self-test-failed", "A tool-call-only reply must not be accepted after the Host selected JSON Schema mode.");
            }
            catch (AgentHostException exception) when (exception.Code == "provider-content-missing")
            {
                if (!exception.Message.Contains("hasContent=True", StringComparison.Ordinal) ||
                    !exception.Message.Contains("contentKind=Null", StringComparison.Ordinal) ||
                    !exception.Message.Contains("hasToolCalls=True", StringComparison.Ordinal) ||
                    !exception.Message.Contains("toolCallCount=1", StringComparison.Ordinal) ||
                    !exception.Message.Contains("finishReason=tool_calls", StringComparison.Ordinal) ||
                    !exception.Message.Contains("format=json_schema", StringComparison.Ordinal) ||
                    exception.Message.Contains("PRIVATE_RESPONSE_SHOULD_NOT_LEAK", StringComparison.Ordinal) ||
                    exception.Message.Contains("private-call-id", StringComparison.Ordinal) ||
                    incompatibleSchemaHandler.LastRequestUri?.AbsolutePath != "/v1/chat/completions")
                    throw new AgentHostException("freellmapi-schema-mismatch-diagnostic-self-test-failed", "The structured diagnostic must classify the HTTP-success response shape without copying reply content, tool-call IDs or arguments.");
            }
            results.Add(new { scenario = "freellmapi-schema-mode-missing-content-records-shape-without-response-data", passed = true, modelCalls = 1, nativeCommands = 0 });
        }

        var emptyChoicesHandler = new StubHandler((httpRequest, _) =>
        {
            if (httpRequest.Method == HttpMethod.Get)
                return Task.FromResult(JsonResponse("{\"data\":[{\"id\":\"free-empty-choices\",\"supported_parameters\":[\"response_format\"]}]}"));
            var response = JsonResponse("{\"model\":\"gpt-oss-20b\",\"choices\":[],\"error\":{\"message\":\"PRIVATE_UPSTREAM_BODY_MUST_NOT_LEAK\"},\"usage\":{\"prompt_tokens\":449,\"completion_tokens\":113}}");
            response.Headers.TryAddWithoutValidation("X-Routed-Via", "ovh/gpt-oss-20b");
            return Task.FromResult(response);
        });
        using (var emptyChoicesClient = new HttpClient(emptyChoicesHandler) { Timeout = freeLlmApiSettings.Timeout })
        using (var emptyChoicesProvider = new OllamaNativeProvider(freeLlmApiSettings with { Model = "free-empty-choices" }, emptyChoicesClient))
        using (var request = JsonDocument.Parse(BuildDecisionRequest()))
        {
            await emptyChoicesProvider.CheckConfiguredModelAsync(CancellationToken.None);
            try
            {
                _ = await emptyChoicesProvider.DecideAsync(request.RootElement, CancellationToken.None);
                throw new AgentHostException("freellmapi-empty-choices-self-test-failed", "An HTTP-success response without any choices must not become a model decision.");
            }
            catch (AgentHostException exception) when (exception.Code == "provider-content-missing")
            {
                if (!exception.Message.Contains("choiceCount=0", StringComparison.Ordinal) ||
                    !exception.Message.Contains("hasError=True", StringComparison.Ordinal) ||
                    !exception.Message.Contains("format=json_schema", StringComparison.Ordinal) ||
                    !exception.Message.Contains("responseModel=gpt-oss-20b", StringComparison.Ordinal) ||
                    !exception.Message.Contains("routedVia=ovh/gpt-oss-20b", StringComparison.Ordinal) ||
                    exception.Message.Contains("PRIVATE_UPSTREAM_BODY_MUST_NOT_LEAK", StringComparison.Ordinal) ||
                    emptyChoicesHandler.LastRequestUri?.AbsolutePath != "/v1/chat/completions")
                    throw new AgentHostException("freellmapi-empty-choices-diagnostic-self-test-failed", "The bounded error must identify the selected route and missing-choice shape without copying the upstream response body.");
            }
            results.Add(new { scenario = "freellmapi-empty-choices-reports-route-and-shape-without-upstream-body", passed = true, modelCalls = 1, nativeCommands = 0 });
        }

        var genericRemoteSettings = settings with
        {
            Endpoint = new Uri("https://api.deepseek.com/v1/chat/completions"),
            Model = "deepseek-flash",
            ApiKey = "generic-remote-self-test-secret"
        };
        var genericRemoteHandler = new StubHandler((request, _) =>
        {
            if (request.Method == HttpMethod.Get)
                return Task.FromResult(JsonResponse("{\"data\":[{\"id\":\"deepseek-flash\"}]}"));
            return Task.FromResult(JsonResponse(BuildChatResponse(ValidDecision, "stop")));
        });
        using (var genericRemoteClient = new HttpClient(genericRemoteHandler) { Timeout = genericRemoteSettings.Timeout })
        using (var genericRemoteProvider = new OllamaNativeProvider(genericRemoteSettings, genericRemoteClient))
        using (var request = JsonDocument.Parse(BuildDecisionRequest()))
        {
            await genericRemoteProvider.CheckConfiguredModelAsync(CancellationToken.None);
            if (genericRemoteHandler.LastAuthorization?.Scheme != "Bearer" ||
                genericRemoteHandler.LastAuthorization.Parameter != "generic-remote-self-test-secret" ||
                genericRemoteHandler.LastRequestUri?.Query.Length > 0)
                throw new AgentHostException("generic-remote-provider-health-self-test-failed", "A generic HTTPS provider must use bearer auth and its standard models endpoint without FreeLLMAPI-only query parameters.");
            var result = await genericRemoteProvider.DecideAsync(request.RootElement, CancellationToken.None);
            using var remoteRequestBody = JsonDocument.Parse(genericRemoteHandler.LastRequestBody ?? "{}");
            if (result.Status != "completed" || genericRemoteHandler.LastAuthorization?.Parameter != "generic-remote-self-test-secret" ||
                remoteRequestBody.RootElement.GetProperty("model").GetString() != "deepseek-flash" ||
                remoteRequestBody.RootElement.GetProperty("response_format").GetProperty("type").GetString() != "json_object" ||
                result.ResponseFormatMode != "json_object_compatibility")
                throw new AgentHostException("generic-remote-provider-decision-self-test-failed", "The generic HTTPS provider did not complete a structured Chronicle decision using its configured model and bearer key.");
            results.Add(new { scenario = "generic-https-openai-compatible-provider-health-auth-and-structured-decision", passed = true });
        }

        var loopbackGatewayRequestCount = 0;
        var loopbackGatewayPayloadValid = false;
        var loopbackGatewaySettings = settings with
        {
            Endpoint = new Uri("http://127.0.0.1:8326/v1/chat/completions"),
            Model = "xdpool-aggregate/open_router/inclusionai/ling-3.2-flash:free",
            ApiKey = "loopback-gateway-self-test-secret",
            OutputMode = "required_tool_call",
            Thinking = false,
            ReasoningEffort = "none",
            MaxTokenParameter = "max_tokens",
            MaxOutputTokens = 128
        };
        var loopbackGatewayHandler = new StubHandler((httpRequest, _) =>
        {
            if (httpRequest.Method == HttpMethod.Get)
                return Task.FromResult(JsonResponse("{\"data\":[{\"id\":\"xdpool-aggregate/open_router/inclusionai/ling-3.2-flash:free\"}]}"));
            loopbackGatewayRequestCount++;
            using var payloadDocument = JsonDocument.Parse(httpRequest.Content!.ReadAsStringAsync().GetAwaiter().GetResult());
            var payload = payloadDocument.RootElement;
            loopbackGatewayPayloadValid = payload.GetProperty("tool_choice").GetString() == "required" &&
                payload.GetProperty("model").GetString() == "xdpool-aggregate/open_router/inclusionai/ling-3.2-flash:free" &&
                payload.GetProperty("reasoning").GetProperty("enabled").GetBoolean() == false &&
                !payload.TryGetProperty("thinking", out var ignoredThinkingExtension) &&
                !payload.TryGetProperty("response_format", out var ignoredResponseFormat);
            return Task.FromResult(JsonResponse(BuildToolCallChatResponse(ValidDecision, "tool_calls")));
        });
        using (var loopbackGatewayClient = new HttpClient(loopbackGatewayHandler) { Timeout = loopbackGatewaySettings.Timeout })
        using (var loopbackGatewayProvider = new OllamaNativeProvider(loopbackGatewaySettings, loopbackGatewayClient))
        using (var request = JsonDocument.Parse(BuildDecisionRequest()))
        {
            await loopbackGatewayProvider.CheckConfiguredModelAsync(CancellationToken.None);
            var result = await loopbackGatewayProvider.DecideAsync(request.RootElement, CancellationToken.None);
            if (!loopbackGatewayPayloadValid || loopbackGatewayRequestCount != 1 || result.Status != "completed" ||
                result.Decision["done"]?.GetValue<bool>() != true)
                throw new AgentHostException("loopback-openai-gateway-tool-call-self-test-failed", "A provider-neutral loopback OpenAI gateway must receive the strict tool-call envelope without a provider-specific thinking extension, then pass the action through the normal decision validator.");
            results.Add(new { scenario = "provider-neutral-loopback-gateway-tool-call-omits-nonstandard-thinking-extension", passed = true, modelCalls = 1, nativeCommands = 0 });
        }

        var workBuddyStructuredPayloadValid = false;
        var workBuddyPromptMatchesOutputMode = false;
        var workBuddyRequestCount = 0;
        var workBuddySettings = settings with
        {
            Endpoint = new Uri("http://127.0.0.1:8328/v1/chat/completions"),
            Model = "buddy:hy4flash",
            ApiKey = "workbuddy-gateway-self-test-secret",
            OutputMode = OllamaNativeProvider.ResolveOutputModeForEndpoint(new Uri("http://127.0.0.1:8328/v1/chat/completions"), "auto"),
            Thinking = null,
            ReasoningEffort = "none",
            MaxTokenParameter = "max_tokens",
            MaxOutputTokens = 128
        };
        var workBuddyHandler = new StubHandler((httpRequest, cancellationToken) =>
        {
            if (httpRequest.Method == HttpMethod.Get)
                return Task.FromResult(JsonResponse("{\"data\":[{\"id\":\"buddy:hy4flash\"}]}"));
            workBuddyRequestCount++;
            using var payloadDocument = JsonDocument.Parse(httpRequest.Content!.ReadAsStringAsync().GetAwaiter().GetResult());
            var payload = payloadDocument.RootElement;
            var postedSystemPrompt = payload.GetProperty("messages")[0].GetProperty("content").GetString() ?? string.Empty;
            workBuddyPromptMatchesOutputMode = postedSystemPrompt.Contains("JSON decision object only", StringComparison.Ordinal) &&
                !postedSystemPrompt.Contains("required decision-tool call", StringComparison.Ordinal);
            workBuddyStructuredPayloadValid = httpRequest.Headers.Authorization?.Scheme == "Bearer" &&
                payload.GetProperty("model").GetString() == "buddy:hy4flash" &&
                payload.GetProperty("response_format").GetProperty("type").GetString() == "json_object" &&
                payload.TryGetProperty("max_tokens", out var workBuddyTokens) && workBuddyTokens.GetInt32() == 128 &&
                !payload.TryGetProperty("max_completion_tokens", out var ignoredMaxCompletionTokens) &&
                !payload.TryGetProperty("tools", out var ignoredTools) && !payload.TryGetProperty("tool_choice", out var ignoredToolChoice) &&
                !payload.TryGetProperty("thinking", out var ignoredThinking) && !payload.TryGetProperty("reasoning_effort", out var ignoredReasoningEffort);
            return Task.FromResult(JsonResponse(BuildChatResponse(ValidDecision, "stop")));
        });
        using (var workBuddyClient = new HttpClient(workBuddyHandler) { Timeout = workBuddySettings.Timeout })
        using (var workBuddyProvider = new OllamaNativeProvider(workBuddySettings, workBuddyClient))
        using (var request = JsonDocument.Parse(BuildDecisionRequest()))
        {
            await workBuddyProvider.CheckConfiguredModelAsync(CancellationToken.None);
            var result = await workBuddyProvider.DecideAsync(request.RootElement, "Return one required decision-tool call only.", CancellationToken.None);
            if (!workBuddyStructuredPayloadValid || !workBuddyPromptMatchesOutputMode || workBuddyRequestCount != 1 || result.Status != "completed" ||
                result.Decision["done"]?.GetValue<bool>() != true || result.ResponseFormatMode != "json_object_compatibility")
                throw new AgentHostException("dsh-workbuddy-json-object-provider-self-test-failed", $"The DSH WorkBuddy adapter contract failed (payloadValid={workBuddyStructuredPayloadValid}; requestCount={workBuddyRequestCount}; status={result.Status}; outputMode={result.ResponseFormatMode}).");
            results.Add(new { scenario = "dsh-workbuddy-json-object-adapter-is-single-request-and-host-validated", passed = true, modelCalls = 1, nativeCommands = 0 });
        }

        var openRouterStructuredPayloadValid = false;
        var openRouterReasoningSettings = settings with
        {
            Endpoint = new Uri("http://127.0.0.1:8326/v1/chat/completions"),
            Model = "xdpool-aggregate/open_router/particle-ai/particle-1:free",
            ApiKey = "loopback-openrouter-self-test-secret",
            OutputMode = "json_schema",
            Thinking = false,
            ReasoningEffort = "none",
            MaxTokenParameter = "max_tokens",
            MaxOutputTokens = 256
        };
        var openRouterReasoningHandler = new StubHandler((httpRequest, _) =>
        {
            if (httpRequest.Method == HttpMethod.Get)
                return Task.FromResult(JsonResponse("{\"data\":[{\"id\":\"xdpool-aggregate/open_router/particle-ai/particle-1:free\"}]}"));
            using var payloadDocument = JsonDocument.Parse(httpRequest.Content!.ReadAsStringAsync().GetAwaiter().GetResult());
            var payload = payloadDocument.RootElement;
            openRouterStructuredPayloadValid = payload.GetProperty("model").GetString() == "xdpool-aggregate/open_router/particle-ai/particle-1:free" &&
                payload.GetProperty("reasoning").GetProperty("enabled").GetBoolean() == false &&
                !payload.TryGetProperty("thinking", out var ignoredThinkingExtension) &&
                !payload.TryGetProperty("reasoning_effort", out var ignoredLegacyReasoningEffort) &&
                payload.GetProperty("response_format").GetProperty("type").GetString() == "json_schema";
            return Task.FromResult(JsonResponse(BuildChatResponse(ValidDecision, "stop")));
        });
        using (var openRouterReasoningClient = new HttpClient(openRouterReasoningHandler) { Timeout = openRouterReasoningSettings.Timeout })
        using (var openRouterReasoningProvider = new OllamaNativeProvider(openRouterReasoningSettings, openRouterReasoningClient))
        using (var request = JsonDocument.Parse(BuildDecisionRequest()))
        {
            await openRouterReasoningProvider.CheckConfiguredModelAsync(CancellationToken.None);
            var result = await openRouterReasoningProvider.DecideAsync(request.RootElement, CancellationToken.None);
            if (!openRouterStructuredPayloadValid || result.Status != "completed" || result.Decision["done"]?.GetValue<bool>() != true ||
                result.ReasoningEffortApplied != "disabled")
                throw new AgentHostException("openrouter-reasoning-off-provider-self-test-failed", "OpenRouter reasoning disable must use its documented reasoning.enabled field, preserve JSON Schema mode, and not spend the completion budget on hidden reasoning.");
            results.Add(new { scenario = "openrouter-reasoning-disabled-uses-standard-reasoning-object", passed = true, modelCalls = 1, nativeCommands = 0 });
        }

        var emptyOpenRouterResponse = JsonSerializer.Serialize(new
        {
            model = "particle-ai/particle-1:free",
            choices = Array.Empty<object>(),
            usage = new { prompt_tokens = 455, completion_tokens = 256 }
        });
        var emptyOpenRouterHandler = new StubHandler((httpRequest, _) => httpRequest.Method == HttpMethod.Get
            ? Task.FromResult(JsonResponse("{\"data\":[{\"id\":\"xdpool-aggregate/open_router/particle-ai/particle-1:free\"}]}"))
            : Task.FromResult(JsonResponse(emptyOpenRouterResponse)));
        using (var emptyOpenRouterClient = new HttpClient(emptyOpenRouterHandler) { Timeout = openRouterReasoningSettings.Timeout })
        using (var emptyOpenRouterProvider = new OllamaNativeProvider(openRouterReasoningSettings, emptyOpenRouterClient))
        using (var request = JsonDocument.Parse(BuildDecisionRequest()))
        {
            await emptyOpenRouterProvider.CheckConfiguredModelAsync(CancellationToken.None);
            try
            {
                _ = await emptyOpenRouterProvider.DecideAsync(request.RootElement, CancellationToken.None);
                throw new AgentHostException("openrouter-empty-choices-self-test-failed", "A successful HTTP status without a structured choice must not become a model decision.");
            }
            catch (AgentHostException exception) when (exception.Code == "provider-content-missing")
            {
                if (exception.ProviderHttpStatus != 200 || exception.ProviderResponseContentKind != "choices-empty" ||
                    exception.ProviderResponsePromptTokens != 455 || exception.ProviderResponseCompletionTokens != 256 ||
                    exception.ProviderResponseModel != "particle-ai/particle-1:free" ||
                    exception.Message.Contains(emptyOpenRouterResponse, StringComparison.Ordinal))
                    throw new AgentHostException("openrouter-empty-choices-diagnostic-self-test-failed", "An empty-choice response must preserve only bounded model/usage/shape metadata, not the response body.");
            }
            results.Add(new { scenario = "openrouter-empty-choices-preserves-safe-response-shape-and-usage", passed = true, modelCalls = 1, nativeCommands = 0 });
        }

        var openRouterChoiceWithoutMessageResponse = JsonSerializer.Serialize(new
        {
            model = "particle-ai/particle-1:free",
            choices = new[] { new { finish_reason = "stop" } },
            usage = new { prompt_tokens = 455, completion_tokens = 12 }
        });
        var openRouterChoiceWithoutMessageHandler = new StubHandler((httpRequest, _) => httpRequest.Method == HttpMethod.Get
            ? Task.FromResult(JsonResponse("{\"data\":[{\"id\":\"xdpool-aggregate/open_router/particle-ai/particle-1:free\"}]}"))
            : Task.FromResult(JsonResponse(openRouterChoiceWithoutMessageResponse)));
        using (var malformedOpenRouterClient = new HttpClient(openRouterChoiceWithoutMessageHandler) { Timeout = openRouterReasoningSettings.Timeout })
        using (var malformedOpenRouterProvider = new OllamaNativeProvider(openRouterReasoningSettings, malformedOpenRouterClient))
        using (var request = JsonDocument.Parse(BuildDecisionRequest()))
        {
            await malformedOpenRouterProvider.CheckConfiguredModelAsync(CancellationToken.None);
            try
            {
                _ = await malformedOpenRouterProvider.DecideAsync(request.RootElement, CancellationToken.None);
                throw new AgentHostException("openrouter-missing-message-self-test-failed", "An OpenAI-compatible choice without a message object must not become a model decision.");
            }
            catch (AgentHostException exception) when (exception.Code == "provider-content-missing")
            {
                if (exception.ProviderHttpStatus != 200 || exception.ProviderFailureStage != "http-response-body" ||
                    exception.ProviderOutputFormat != "json_schema" || exception.ProviderResponseContentKind != "choice-object-message-missing" ||
                    exception.ProviderFinishReason != "stop" || exception.ProviderResponseModel != "particle-ai/particle-1:free" ||
                    exception.ProviderResponsePromptTokens != 455 || exception.ProviderResponseCompletionTokens != 12 ||
                    exception.Message.Contains(openRouterChoiceWithoutMessageResponse, StringComparison.Ordinal))
                    throw new AgentHostException("openrouter-missing-message-diagnostic-self-test-failed", "A malformed choice must retain safe HTTP/model/usage/shape metadata without retaining its response body.");
            }
            results.Add(new { scenario = "openrouter-choice-without-message-preserves-safe-response-shape-and-usage", passed = true, modelCalls = 1, nativeCommands = 0 });
        }

        const string privateProviderErrorText = "PRIVATE_PROVIDER_RESPONSE_BODY_MUST_NOT_BE_SERIALIZED";
        var safeProviderFailure = Program.BuildSafeProviderFailureDetails(new AgentHostException(
            "provider-http-error", privateProviderErrorText, providerHttpStatus: 400,
            providerRoute: "xdpool-aggregate/open_router", providerOutputFormat: "required_tool_call",
            providerFailureStage: "http-response-status", providerRequestBodyBytes: 512,
            providerResponseRequestId: "req-safe-diagnostic-id", providerErrorBodyKind: "json-error",
            providerErrorContentType: "application/json", providerErrorType: "invalid_request_error",
            providerErrorCode: "invalid_request", providerErrorParam: "tools_0_.function.parameters"));
        var safeProviderFailureJson = safeProviderFailure?.ToJsonString() ?? "{}";
        using (var safeProviderFailureDocument = JsonDocument.Parse(safeProviderFailureJson))
        {
            var details = safeProviderFailureDocument.RootElement;
            if (details.GetProperty("httpStatus").GetInt32() != 400 ||
                details.GetProperty("errorType").GetString() != "invalid_request_error" ||
                details.GetProperty("errorCode").GetString() != "invalid_request" ||
                details.GetProperty("errorParam").GetString() != "tools_0_.function.parameters" ||
                details.GetProperty("responseRequestId").GetString() != "req-safe-diagnostic-id" ||
                safeProviderFailureJson.Contains(privateProviderErrorText, StringComparison.Ordinal))
                throw new AgentHostException("provider-http-failure-diagnostics-self-test-failed", "Provider CLI failure output must preserve only safe HTTP metadata and must never serialize the response body.");
        }
        if (Program.BuildSafeProviderFailureDetails(new AgentHostException("provider-timeout", "timeout")) is not null)
            throw new AgentHostException("provider-http-failure-diagnostics-overreported-self-test-failed", "Non-HTTP provider failures must not fabricate HTTP diagnostics.");
        results.Add(new { scenario = "provider-http-failure-cli-output-preserves-safe-error-fields-without-body", passed = true, modelCalls = 0, nativeCommands = 0 });

        var budgetGuardHandler = new StubHandler((_, _) => Task.FromResult(JsonResponse(BuildChatResponse(ValidDecision, "stop"))));
        var budgetGuardSettings = genericRemoteSettings with
        {
            OutputMode = "required_tool_call",
            Thinking = false,
            MaxOutputTokens = 64,
            MaxEstimatedRunCostCny = 0.0007d
        };
        using (var budgetGuardClient = new HttpClient(budgetGuardHandler) { Timeout = budgetGuardSettings.Timeout })
        using (var budgetGuardProvider = new OllamaNativeProvider(budgetGuardSettings, budgetGuardClient))
        using (var request = JsonDocument.Parse(BuildDecisionRequest()))
        {
            try
            {
                await budgetGuardProvider.DecideAsync(request.RootElement, CancellationToken.None);
                throw new AgentHostException("deepseek-run-budget-self-test-failed", "The request exceeded the configured DeepSeek ceiling but reached the provider.");
            }
            catch (AgentHostException exception) when (exception.Code == "provider-budget-exhausted")
            {
                if (budgetGuardHandler.LastRequestUri is not null)
                    throw new AgentHostException("deepseek-run-budget-request-sent", "A cost-budget rejection must happen before any model request is sent.");
            }
            results.Add(new { scenario = "deepseek-run-cost-reservation-rejects-over-budget-before-http", passed = true });
        }

        var toolCallRequestCount = 0;
        var toolCallPayloadValid = false;
        var toolCallHandler = new StubHandler((httpRequest, _) =>
        {
            if (httpRequest.Method == HttpMethod.Get)
                return Task.FromResult(JsonResponse("{\"data\":[{\"id\":\"north-mini-code\",\"supported_parameters\":[\"tools\",\"tool_choice\",\"max_tokens\",\"parallel_tool_calls\"]}]}"));

            toolCallRequestCount++;
            using var payloadDocument = JsonDocument.Parse(httpRequest.Content!.ReadAsStringAsync().GetAwaiter().GetResult());
            var payload = payloadDocument.RootElement;
            var tools = payload.TryGetProperty("tools", out var toolRows) && toolRows.ValueKind == JsonValueKind.Array
                ? toolRows.EnumerateArray().ToArray()
                : Array.Empty<JsonElement>();
            var function = tools.Length == 1 && tools[0].TryGetProperty("function", out var functionValue)
                ? functionValue
                : default;
            toolCallPayloadValid =
                payload.GetProperty("model").GetString() == "north-mini-code" &&
                !payload.TryGetProperty("response_format", out var ignoredResponseFormat) &&
                payload.GetProperty("tool_choice").GetString() == "required" &&
                payload.GetProperty("parallel_tool_calls").ValueKind == JsonValueKind.False &&
                tools.Length == 1 &&
                function.ValueKind == JsonValueKind.Object &&
                function.TryGetProperty("name", out var functionName) && functionName.GetString() == "submit_chronicle_decision" &&
                function.GetProperty("parameters").GetProperty("properties").GetProperty("decision").GetProperty("anyOf").GetArrayLength() == 1;
            return Task.FromResult(JsonResponse(BuildToolCallChatResponse(
                "{\"decision\":{\"control\":\"done\",\"reason\":\"provider contract smoke passed\"}}", "tool_calls")));
        });
        using (var toolCallClient = new HttpClient(toolCallHandler) { Timeout = freeLlmApiSettings.Timeout })
        using (var toolCallProvider = new OllamaNativeProvider(freeLlmApiSettings with { Model = "north-mini-code" }, toolCallClient))
        using (var request = JsonDocument.Parse(BuildDecisionRequest()))
        {
            await toolCallProvider.CheckConfiguredModelAsync(CancellationToken.None);
            if (toolCallProvider.StructuredOutputStrategy != "required_tool_call")
                throw new AgentHostException("provider-self-test-tool-call-health-strategy-invalid", "FreeLLMAPI's advertised tools/tool_choice capabilities must select required_tool_call during the read-only health check.");
            var result = await toolCallProvider.DecideAsync(request.RootElement, CancellationToken.None);
            if (!toolCallPayloadValid || toolCallRequestCount != 1 ||
                result.ResponseFormatMode != "required_tool_call" ||
                result.Decision["done"]?.GetValue<bool>() != true ||
                result.PromptTokens != 24 || result.CompletionTokens != 12)
                throw new AgentHostException("provider-self-test-tool-call-compatibility-failed", "A FreeLLMAPI model that advertises tools and tool_choice but not response_format must receive one forced, side-effect-free decision tool call and still pass the normal local decision validator.");
            results.Add(new { scenario = "freellmapi-model-capabilities-select-required-tool-call-with-local-decision-validation", passed = true, model = "north-mini-code", modelCalls = 1, nativeCommands = 0 });
        }

        var exactWaitToolCallPayloadValid = false;
        var exactWaitToolCallHandler = new StubHandler((httpRequest, _) =>
        {
            if (httpRequest.Method == HttpMethod.Get)
                return Task.FromResult(JsonResponse("{\"data\":[{\"id\":\"north-mini-code\",\"supported_parameters\":[\"tools\",\"tool_choice\"]}]}"));

            using var payloadDocument = JsonDocument.Parse(httpRequest.Content!.ReadAsStringAsync().GetAwaiter().GetResult());
            var payload = payloadDocument.RootElement;
            var anyOf = payload.GetProperty("tools")[0].GetProperty("function").GetProperty("parameters")
                .GetProperty("properties").GetProperty("decision").GetProperty("anyOf");
            var observeAgainBranch = anyOf.EnumerateArray().FirstOrDefault(branch =>
                branch.GetProperty("properties").GetProperty("control").GetProperty("enum")[0].GetString() == "observeAgain");
            exactWaitToolCallPayloadValid =
                payload.GetProperty("tool_choice").GetString() == "required" &&
                observeAgainBranch.ValueKind == JsonValueKind.Object &&
                observeAgainBranch.GetProperty("properties").GetProperty("waitSeconds").GetProperty("minimum").GetInt32() == 10 &&
                observeAgainBranch.GetProperty("properties").GetProperty("waitSeconds").GetProperty("maximum").GetInt32() == 10;
            return Task.FromResult(JsonResponse(BuildToolCallChatResponse(
                "{\"decision\":{\"control\":\"observeAgain\",\"waitSeconds\":10,\"reason\":\"Continue the observed move.\"}}", "tool_calls")));
        });
        using (var exactWaitToolCallClient = new HttpClient(exactWaitToolCallHandler) { Timeout = freeLlmApiSettings.Timeout })
        using (var exactWaitToolCallProvider = new OllamaNativeProvider(freeLlmApiSettings with { Model = "north-mini-code" }, exactWaitToolCallClient))
        using (var exactWaitRequest = JsonDocument.Parse("""
        {"goal":"Passively observe an active PartySize settlement move.","observation":{"state":{"party":{"isMoving":true}}},"allowedActions":[],"allowedControls":["observeAgain"],"controlArguments":{"observeAgain":{"waitSeconds":{"type":"integer","minimum":10,"maximum":10}}}}
        """))
        {
            await exactWaitToolCallProvider.CheckConfiguredModelAsync(CancellationToken.None);
            var result = await exactWaitToolCallProvider.DecideAsync(exactWaitRequest.RootElement, CancellationToken.None);
            if (!exactWaitToolCallPayloadValid || result.ResponseFormatMode != "required_tool_call" ||
                result.Decision["observeAgain"]?.GetValue<bool>() != true || result.Decision["waitSeconds"]?.GetValue<int>() != 10)
                throw new AgentHostException("provider-self-test-exact-party-size-tool-schema-not-sent", "The required-tool-call provider payload must carry the exact PartySize wait bound and validate the returned ten-second control.");
            results.Add(new { scenario = "openai-compatible-required-tool-call-sends-exact-party-size-wait-schema", passed = true, modelCalls = 0, nativeCommands = 0 });
        }

        var multipleToolCallRequests = 0;
        var parallelToolCallsDisabled = false;
        var multipleToolCallHandler = new StubHandler((httpRequest, _) =>
        {
            if (httpRequest.Method == HttpMethod.Get)
                return Task.FromResult(JsonResponse("{\"data\":[{\"id\":\"north-mini-code\",\"supported_parameters\":[\"tools\",\"tool_choice\",\"parallel_tool_calls\"]}]}"));

            multipleToolCallRequests++;
            using var payloadDocument = JsonDocument.Parse(httpRequest.Content!.ReadAsStringAsync().GetAwaiter().GetResult());
            parallelToolCallsDisabled = payloadDocument.RootElement.TryGetProperty("parallel_tool_calls", out var parallelCalls) &&
                parallelCalls.ValueKind == JsonValueKind.False;
            var arguments = "{\"decision\":{\"control\":\"done\",\"reason\":\"first ordered decision\"}}";
            var laterArguments = "{\"decision\":{\"control\":\"stop\",\"reason\":\"stale later proposal\"}}";
            var response = JsonSerializer.Serialize(new
            {
                model = "north-mini-code",
                choices = new[]
                {
                    new
                    {
                        index = 0,
                        message = new
                        {
                            role = "assistant",
                            content = (string?)null,
                            tool_calls = new[]
                            {
                                new { id = "call-a", type = "function", function = new { name = "submit_chronicle_decision", arguments } },
                                new { id = "call-b", type = "function", function = new { name = "submit_chronicle_decision", arguments = laterArguments } }
                            }
                        },
                        finish_reason = "tool_calls"
                    }
                },
                usage = new { prompt_tokens = 20, completion_tokens = 12 }
            });
            return Task.FromResult(JsonResponse(response));
        });
        using (var multipleToolCallClient = new HttpClient(multipleToolCallHandler) { Timeout = freeLlmApiSettings.Timeout })
        using (var multipleToolCallProvider = new OllamaNativeProvider(freeLlmApiSettings with { Model = "north-mini-code" }, multipleToolCallClient))
        using (var multipleToolCallRequest = JsonDocument.Parse(BuildDecisionRequest()))
        {
            await multipleToolCallProvider.CheckConfiguredModelAsync(CancellationToken.None);
            var serializedDecision = await multipleToolCallProvider.DecideAsync(multipleToolCallRequest.RootElement, CancellationToken.None);
            if (!parallelToolCallsDisabled || serializedDecision.ProviderToolCallsDiscarded != 1 || multipleToolCallRequests != 1 ||
                serializedDecision.Decision["done"]?.GetValue<bool>() != true)
                throw new AgentHostException("provider-multiple-tool-call-serialization-contract-invalid", "The Host must submit parallel_tool_calls=false, validate the first ordered Native decision, discard later batch entries, and execute only that one decision.");
            results.Add(new { scenario = "required-tool-call-disables-parallel-calls-and-serializes-a-native-decision-batch-to-its-first-current-action", discardedProviderCalls = serializedDecision.ProviderToolCallsDiscarded, passed = true, modelCalls = 0, nativeCommands = 0 });
        }

        var invalidToolCallRequests = 0;
        var invalidToolCallHandler = new StubHandler((httpRequest, _) =>
        {
            if (httpRequest.Method == HttpMethod.Get)
                return Task.FromResult(JsonResponse("{\"data\":[{\"id\":\"north-mini-code\",\"supported_parameters\":[\"tools\",\"tool_choice\"]}]}"));
            invalidToolCallRequests++;
            var invalidFirst = "{\"decision\":{\"action\":\"invented_action\",\"arguments\":{},\"rationale\":\"bad first call\"}}";
            var validLater = "{\"decision\":{\"action\":\"tradeConfirm\",\"arguments\":{},\"rationale\":\"must not skip the first call\"}}";
            return Task.FromResult(JsonResponse(JsonSerializer.Serialize(new
            {
                model = "north-mini-code",
                choices = new[]
                {
                    new
                    {
                        index = 0,
                        message = new
                        {
                            role = "assistant",
                            content = (string?)null,
                            tool_calls = new[]
                            {
                                new { id = "call-invalid-first", type = "function", function = new { name = "submit_chronicle_decision", arguments = invalidFirst } },
                                new { id = "call-valid-later", type = "function", function = new { name = "submit_chronicle_decision", arguments = validLater } }
                            }
                        },
                        finish_reason = "tool_calls"
                    }
                },
                usage = new { prompt_tokens = 10, completion_tokens = 5 }
            })));
        });
        using (var invalidToolCallClient = new HttpClient(invalidToolCallHandler) { Timeout = freeLlmApiSettings.Timeout })
        using (var invalidToolCallProvider = new OllamaNativeProvider(freeLlmApiSettings with { Model = "north-mini-code" }, invalidToolCallClient))
        using (var request = JsonDocument.Parse(BuildActionDecisionRequest()))
        {
            await invalidToolCallProvider.CheckConfiguredModelAsync(CancellationToken.None);
            try
            {
                await invalidToolCallProvider.DecideAsync(request.RootElement, CancellationToken.None);
                throw new AgentHostException("provider-self-test-tool-call-unlisted-action-accepted", "A structured tool call outside the current Native catalog must be rejected before it can become a Host action.");
            }
            catch (AgentHostException exception) when (exception.Code == "provider-action-unavailable")
            {
                if (invalidToolCallRequests != 1)
                    throw new AgentHostException("provider-self-test-tool-call-unlisted-action-request-count-invalid", "The Host must validate one tool call locally and must not repeat or dispatch it as a Native command.");
            }
            results.Add(new { scenario = "provider-serializes-only-the-first-tool-call-and-validates-it-against-the-current-native-catalog", passed = true, modelCalls = 1, nativeCommands = 0 });
        }

        var noStructuredOutputRequests = 0;
        var unsupportedOutputHandler = new StubHandler((httpRequest, _) =>
        {
            if (httpRequest.Method != HttpMethod.Get) noStructuredOutputRequests++;
            return Task.FromResult(JsonResponse("{\"data\":[{\"id\":\"horde-model-without-structured-output\",\"supported_parameters\":[\"max_tokens\",\"stream\"]}]}"));
        });
        using (var unsupportedOutputClient = new HttpClient(unsupportedOutputHandler) { Timeout = freeLlmApiSettings.Timeout })
        using (var unsupportedOutputProvider = new OllamaNativeProvider(freeLlmApiSettings with { Model = "horde-model-without-structured-output" }, unsupportedOutputClient))
        {
            try
            {
                await unsupportedOutputProvider.CheckConfiguredModelAsync(CancellationToken.None);
                throw new AgentHostException("provider-self-test-unsupported-structured-output-accepted", "The Host accepted a FreeLLMAPI model with neither JSON response_format nor tool-calling support.");
            }
            catch (AgentHostException exception) when (exception.Code == "provider-structured-output-unsupported")
            {
                if (noStructuredOutputRequests != 0)
                    throw new AgentHostException("provider-self-test-unsupported-structured-output-request-sent", "The Host sent an inference request to a FreeLLMAPI model that advertises no safe structured-output strategy.");
            }
            results.Add(new { scenario = "freellmapi-model-without-json-or-tool-support-fails-before-inference", passed = true, modelCalls = 0, nativeCommands = 0 });
        }

        var promptOnlyJsonModelCalls = 0;
        var promptOnlyJsonRequestOmittedUnsupportedFields = false;
        var promptOnlyJsonHandler = new StubHandler(async (httpRequest, cancellationToken) =>
        {
            if (httpRequest.Method == HttpMethod.Get)
                return JsonResponse("{\"data\":[{\"id\":\"horde-model-without-structured-output\",\"supported_parameters\":[\"max_tokens\",\"stream\"]}]}");
            promptOnlyJsonModelCalls++;
            using var bodyDocument = JsonDocument.Parse(await httpRequest.Content!.ReadAsStringAsync(cancellationToken));
            var systemMessage = bodyDocument.RootElement.GetProperty("messages")[0].GetProperty("content").GetString() ?? string.Empty;
            promptOnlyJsonRequestOmittedUnsupportedFields = !bodyDocument.RootElement.TryGetProperty("response_format", out _) &&
                !bodyDocument.RootElement.TryGetProperty("tools", out _) &&
                systemMessage.Contains("Return exactly one JSON decision object", StringComparison.Ordinal);
            return JsonResponse(BuildChatResponse("{\"action\":\"tradeConfirm\",\"arguments\":{},\"rationale\":\"Confirm the Native trade draft.\"}", "stop"));
        });
        var promptOnlyJsonSettings = freeLlmApiSettings with
        {
            Model = "horde-model-without-structured-output",
            OutputMode = "json_object",
            MaxHttpRequestsPerDecision = 1
        };
        using (var promptOnlyJsonClient = new HttpClient(promptOnlyJsonHandler) { Timeout = promptOnlyJsonSettings.Timeout })
        using (var promptOnlyJsonProvider = new OllamaNativeProvider(promptOnlyJsonSettings, promptOnlyJsonClient))
        using (var request = JsonDocument.Parse(BuildActionDecisionRequest()))
        {
            await promptOnlyJsonProvider.CheckConfiguredModelAsync(CancellationToken.None);
            var result = await promptOnlyJsonProvider.DecideAsync(request.RootElement, "Return exactly one JSON decision object. Validate all fields locally.", CancellationToken.None);
            if (!promptOnlyJsonRequestOmittedUnsupportedFields || promptOnlyJsonModelCalls != 1 || result.ResponseFormatMode != "json_object_prompt_only" ||
                result.Decision["action"]?.GetValue<string>() != "tradeConfirm")
                throw new AgentHostException("provider-self-test-prompt-only-json-mode-failed", "Explicit JSON-object mode may use prompt-only output for a model without provider-side structured output only when the returned action still passes local catalog validation.");
            results.Add(new { scenario = "freellmapi-explicit-json-object-allows-prompt-only-output-with-local-action-validation", passed = true, providerCalls = promptOnlyJsonModelCalls, nativeCommands = 0 });
        }

        var reliableRouterHandler = new StubHandler((_, _) => Task.FromResult(JsonResponse("{\"data\":[{\"id\":\"auto\"}]}")));
        using (var reliableRouterClient = new HttpClient(reliableRouterHandler) { Timeout = settings.Timeout })
        using (var reliableRouter = new OllamaNativeProvider(freeLlmApiSettings with { Model = "auto:reliable" }, reliableRouterClient))
            await reliableRouter.CheckConfiguredModelAsync(CancellationToken.None);
        results.Add(new { scenario = "freellmapi-health-accepts-documented-auto-reliable-strategy-not-listed-as-model", passed = true });

        using (var unknownRouterClient = new HttpClient(new StubHandler((_, _) => Task.FromResult(JsonResponse("{\"data\":[{\"id\":\"auto\"}]}")))) { Timeout = settings.Timeout })
        using (var unknownRouter = new OllamaNativeProvider(freeLlmApiSettings with { Model = "auto:typo-profile" }, unknownRouterClient))
        {
            try
            {
                await unknownRouter.CheckConfiguredModelAsync(CancellationToken.None);
                throw new AgentHostException("freellmapi-unknown-router-profile-accepted", "The Host accepted an unknown named Auto profile absent from the model catalog.");
            }
            catch (AgentHostException exception) when (exception.Code == "provider-model-unavailable") { }
        }
        results.Add(new { scenario = "freellmapi-health-rejects-unknown-auto-profile-not-listed-as-model", passed = true });

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
        var transportFailureHandler = new StubHandler((_, _) => Task.FromException<HttpResponseMessage>(
            new HttpRequestException(HttpRequestError.SecureConnectionError, "PRIVATE_TRANSPORT_MESSAGE", new System.Security.Authentication.AuthenticationException("PRIVATE_TLS_DETAIL"))));
        using (var transportFailureClient = new HttpClient(transportFailureHandler) { Timeout = settings.Timeout })
        using (var transportFailureProvider = new OllamaNativeProvider(settings, transportFailureClient))
        {
            try
            {
                await transportFailureProvider.CheckConfiguredModelAsync(CancellationToken.None);
                throw new AgentHostException("provider-health-transport-failure-accepted", "A failed provider transport must not be reported as ready.");
            }
            catch (AgentHostException exception) when (exception.Code == "provider-unavailable")
            {
                if (!exception.Message.Contains("httpRequestError=SecureConnectionError", StringComparison.Ordinal) ||
                    !exception.Message.Contains("innerType=AuthenticationException", StringComparison.Ordinal) ||
                    exception.Message.Contains("PRIVATE_TRANSPORT_MESSAGE", StringComparison.Ordinal) ||
                    exception.Message.Contains("PRIVATE_TLS_DETAIL", StringComparison.Ordinal) ||
                    transportFailureHandler.LastRequestMethod != HttpMethod.Get)
                    throw new AgentHostException("provider-health-transport-diagnostic-invalid", "A bounded read-only health failure must identify the transport class without exposing exception text or request secrets.");
            }
            results.Add(new { scenario = "provider-health-classifies-transport-failure-without-raw-exception-text", passed = true, modelCalls = 0, nativeCommands = 0 });
        }

        await VerifySharedDecisionCycleAsync(settings, "mapSettlementTargets", "CampaignSystemPrompt", AgentHostDecisionCycle.DecideCampaignAsync, results);
        await VerifySharedDecisionCycleAsync(settings, "foodOptions", "SupplySystemPrompt", AgentHostDecisionCycle.DecideSupplyAsync, results);

        await VerifyGoalClassificationAsync(settings, "supportedMapArrivalGoal", "supported-map-arrival", ["supportedMapArrivalGoal", "unsupportedGoal"], results);
        await VerifyGoalClassificationAsync(settings, "supportedVillageToolsQuestGoal", "supported-village-tools-quest", ["supportedMapArrivalGoal", "supportedVillageToolsQuestGoal", "unsupportedGoal"], results);
        await VerifyGoalClassificationAsync(settings, "supportedBattleSimulationGoal", "supported-battle-simulation", ["supportedMapArrivalGoal", "supportedVillageToolsQuestGoal", "supportedBattleSimulationGoal", "unsupportedGoal"], results);
        await VerifyGoalClassificationAsync(settings, "supportedBattleAndCaptivityGoal", "supported-battle-and-captivity", ["supportedMapArrivalGoal", "supportedVillageToolsQuestGoal", "supportedBattleSimulationGoal", "supportedBattleAndCaptivityGoal", "unsupportedGoal"], results);
        await VerifyGoalClassificationAsync(settings, "supportedEstablishYourClanGoal", "supported-establish-your-clan", ["supportedEstablishYourClanGoal", "unsupportedGoal"], results);
        await VerifyGoalClassificationAsync(settings, "supportedCaptivityRecoveryGoal", "supported-captivity-recovery", ["supportedCaptivityRecoveryGoal", "unsupportedGoal"], results);
        await VerifyGoalClassificationAsync(settings, "supportedEstablishClanGoldSaleGoal", "supported-establish-clan-gold-sale", ["supportedEstablishYourClanGoal", "supportedEstablishClanGoldSaleGoal", "unsupportedGoal"], results);
        await VerifyGoalClassificationAsync(settings, "unsupportedGoal", "unsupported", ["supportedMapArrivalGoal", "unsupportedGoal"], results);
        await VerifyGoalClassificationAsync(settings, "supportedMapArrivalGoal", "provider-goal-classification-unavailable", ["unsupportedGoal"], results);
        await VerifyGoalClassificationAsync(settings, "supportedVillageToolsQuestGoal", "provider-goal-classification-unavailable", ["supportedMapArrivalGoal", "unsupportedGoal"], results);
        await VerifyGoalClassificationAsync(settings, "supportedBattleSimulationGoal", "provider-goal-classification-unavailable", ["supportedMapArrivalGoal", "unsupportedGoal"], results);
        await VerifyGoalClassificationAsync(settings, "supportedBattleAndCaptivityGoal", "provider-goal-classification-unavailable", ["supportedMapArrivalGoal", "unsupportedGoal"], results);
        await VerifyGoalClassificationAsync(settings, "supportedEstablishYourClanGoal", "provider-goal-classification-unavailable", ["unsupportedGoal"], results);
        await VerifyGoalClassificationAsync(settings, "supportedCaptivityRecoveryGoal", "provider-goal-classification-unavailable", ["unsupportedGoal"], results);
        await VerifyGoalClassificationAsync(settings, "supportedEstablishClanGoldSaleGoal", "provider-goal-classification-unavailable", ["supportedEstablishYourClanGoal", "unsupportedGoal"], results);
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

        var successfulFallbackResponse = JsonResponse(BuildChatResponse(ValidDecision, "stop"));
        successfulFallbackResponse.Headers.TryAddWithoutValidation("X-Routed-Via", "ovh/gpt-oss-20b");
        successfulFallbackResponse.Headers.TryAddWithoutValidation("X-Fallback-Attempts", "2");
        successfulFallbackResponse.Headers.TryAddWithoutValidation("X-Fallback-Trail", "groq/model=rate_limited; nvidia/model=upstream_502");
        using (var successfulFallbackClient = new HttpClient(new StubHandler((_, _) => Task.FromResult(successfulFallbackResponse))) { Timeout = settings.Timeout })
        using (var successfulFallbackProvider = new OllamaNativeProvider(settings with
        {
            Endpoint = new Uri("http://127.0.0.1:31415/v1/chat/completions"),
            Model = "gpt-oss-20b",
            ApiKey = "freellmapi-self-test-secret"
        }, successfulFallbackClient))
        using (var request = JsonDocument.Parse(BuildDecisionRequest()))
        {
            var result = await successfulFallbackProvider.DecideAsync(request.RootElement, CancellationToken.None);
            if (result.FallbackAttempts != 2 || result.FallbackTrail != "groq/model=rate_limited; nvidia/model=upstream_502" || result.RoutedVia != "ovh/gpt-oss-20b")
                throw new AgentHostException("provider-self-test-successful-fallback-diagnostics-missing", "A successful FreeLLMAPI response must retain its final route and upstream fallback count/trail for cost and reliability audits.");
            results.Add(new { scenario = "freellmapi-success-records-routed-via-and-upstream-fallback-trail", passed = true });
        }

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
                    !exception.Message.Contains("outputFormat=json_schema", StringComparison.Ordinal) ||
                    exception.Message.Contains("sensitive-error-body-marker", StringComparison.Ordinal))
                    throw new AgentHostException("provider-self-test-routed-failure-diagnostics-unsafe", "FreeLLMAPI failure diagnostics must retain route headers and selected output protocol while omitting response bodies.");
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

        var upstreamThenRateLimitCalls = 0;
        var upstreamThenRateLimitHandler = new StubHandler((_, _) =>
        {
            upstreamThenRateLimitCalls++;
            if (upstreamThenRateLimitCalls == 1)
            {
                var upstreamFailure = new HttpResponseMessage(HttpStatusCode.BadGateway);
                upstreamFailure.Headers.TryAddWithoutValidation("X-Fallback-Trail", "nvidia/test-model key1=upstream_error");
                return Task.FromResult(upstreamFailure);
            }
            var limited = new HttpResponseMessage(HttpStatusCode.TooManyRequests);
            limited.Headers.RetryAfter = new RetryConditionHeaderValue(TimeSpan.FromSeconds(1));
            return Task.FromResult(limited);
        });
        using (var upstreamThenRateLimitClient = new HttpClient(upstreamThenRateLimitHandler) { Timeout = transientRetrySettings.Timeout })
        using (var upstreamThenRateLimitProvider = new OllamaNativeProvider(transientRetrySettings, upstreamThenRateLimitClient))
        using (var request = JsonDocument.Parse(BuildActionDecisionRequest()))
        {
            try
            {
                await upstreamThenRateLimitProvider.DecideAsync(request.RootElement, CancellationToken.None);
                throw new AgentHostException("provider-self-test-upstream-then-rate-limit-accepted", "Repeated 429 responses after the transient 502 must fail closed after the separate bounded 429 retry budget.");
            }
            catch (AgentHostException exception) when (exception.Code == "provider-http-error")
            {
                if (upstreamThenRateLimitCalls != 5 || !exception.Message.Contains("rateLimitRetryAttempts=3", StringComparison.Ordinal) ||
                    !exception.Message.Contains("rateLimitRetryEligible=true", StringComparison.Ordinal))
                    throw new AgentHostException("provider-self-test-upstream-then-rate-limit-recovery-missed", "A 429 returned after transient 502 retries must receive three bounded Retry-After attempts before final failure.");
                results.Add(new { scenario = "freellmapi-reclassifies-429-after-transient-upstream-retry", passed = true, providerCalls = upstreamThenRateLimitCalls, nativeCommands = 0 });
            }
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

        var changingRetryAfterCalls = 0;
        var changingRetryAfterHandler = new StubHandler((_, _) =>
        {
            changingRetryAfterCalls++;
            if (changingRetryAfterCalls <= 3)
            {
                var limited = new HttpResponseMessage(HttpStatusCode.TooManyRequests);
                limited.Headers.RetryAfter = new RetryConditionHeaderValue(TimeSpan.FromSeconds(changingRetryAfterCalls == 3 ? 3 : 1));
                return Task.FromResult(limited);
            }
            var recovered = JsonResponse(BuildChatResponse("{\"action\":\"tradeConfirm\",\"arguments\":{},\"rationale\":\"Confirm the current Native draft.\"}", "stop"));
            recovered.Headers.TryAddWithoutValidation("X-Routed-Via", "custom/nvidia/test-model");
            return Task.FromResult(recovered);
        });
        var changingRetryAfterSettings = freeLlmApiSettings with { Model = "auto:reliable", Timeout = TimeSpan.FromSeconds(20) };
        using (var changingRetryAfterClient = new HttpClient(changingRetryAfterHandler) { Timeout = changingRetryAfterSettings.Timeout })
        using (var changingRetryAfterProvider = new OllamaNativeProvider(changingRetryAfterSettings, changingRetryAfterClient))
        using (var request = JsonDocument.Parse(BuildActionDecisionRequest()))
        {
            var startedUtc = DateTimeOffset.UtcNow;
            var result = await changingRetryAfterProvider.DecideAsync(request.RootElement, CancellationToken.None);
            var elapsed = DateTimeOffset.UtcNow - startedUtc;
            if (result.Decision["action"]?.GetValue<string>() != "tradeConfirm" || changingRetryAfterCalls != 4 || elapsed < TimeSpan.FromSeconds(4))
                throw new AgentHostException("provider-self-test-changing-retry-after-hint-not-honored", "A later, longer Retry-After that fits the request deadline must still receive a bounded retry after earlier short waits.");
            results.Add(new { scenario = "freellmapi-changing-retry-after-honors-later-in-deadline-window", passed = true, providerCalls = changingRetryAfterCalls, nativeCommands = 0 });
        }

        var perDecisionRequestLimitCalls = 0;
        var perDecisionRequestLimitHandler = new StubHandler((_, _) =>
        {
            perDecisionRequestLimitCalls++;
            var limited = new HttpResponseMessage(HttpStatusCode.TooManyRequests);
            limited.Headers.RetryAfter = new RetryConditionHeaderValue(TimeSpan.FromSeconds(4));
            return Task.FromResult(limited);
        });
        var perDecisionRequestLimitSettings = freeLlmApiSettings with
        {
            Model = "qwen3.8-27b",
            Timeout = TimeSpan.FromSeconds(20),
            MaxHttpRequestsPerDecision = 1
        };
        using (var perDecisionRequestLimitClient = new HttpClient(perDecisionRequestLimitHandler) { Timeout = perDecisionRequestLimitSettings.Timeout })
        using (var perDecisionRequestLimitProvider = new OllamaNativeProvider(perDecisionRequestLimitSettings, perDecisionRequestLimitClient))
        using (var request = JsonDocument.Parse(BuildActionDecisionRequest()))
        {
            var startedUtc = DateTimeOffset.UtcNow;
            try
            {
                await perDecisionRequestLimitProvider.DecideAsync(request.RootElement, CancellationToken.None);
                throw new AgentHostException("provider-self-test-per-decision-http-request-budget-accepted", "A second request must not be sent after a one-request decision budget is consumed.");
            }
            catch (AgentHostException exception) when (exception.Code == "provider-http-request-budget-exhausted")
            {
                if (perDecisionRequestLimitCalls != 1 || DateTimeOffset.UtcNow - startedUtc > TimeSpan.FromSeconds(2) ||
                    exception.ProviderHttpStatus != (int)HttpStatusCode.TooManyRequests || exception.ProviderRetryAfter != "4")
                    throw new AgentHostException("provider-self-test-per-decision-http-request-budget-not-enforced", "A per-decision HTTP request cap must stop before waiting or sending a retry and preserve only safe preceding-response metadata.");
                results.Add(new { scenario = "freellmapi-per-decision-http-request-cap-blocks-rate-limit-retry-before-wait", passed = true, providerCalls = perDecisionRequestLimitCalls, nativeCommands = 0 });
            }
        }

        var perDecisionTransientLimitCalls = 0;
        var perDecisionTransientLimitHandler = new StubHandler((_, _) =>
        {
            perDecisionTransientLimitCalls++;
            var failed = new HttpResponseMessage(HttpStatusCode.BadGateway);
            failed.Headers.TryAddWithoutValidation("X-Request-Id", "freeapi-request-1");
            failed.Headers.TryAddWithoutValidation("X-Fallback-Attempts", "1");
            failed.Headers.TryAddWithoutValidation("X-Fallback-Trail", "ovh/qwen3.8-27b key1=upstream_error");
            return Task.FromResult(failed);
        });
        using (var perDecisionTransientLimitClient = new HttpClient(perDecisionTransientLimitHandler) { Timeout = perDecisionRequestLimitSettings.Timeout })
        using (var perDecisionTransientLimitProvider = new OllamaNativeProvider(perDecisionRequestLimitSettings, perDecisionTransientLimitClient))
        using (var request = JsonDocument.Parse(BuildActionDecisionRequest()))
        {
            var startedUtc = DateTimeOffset.UtcNow;
            try
            {
                await perDecisionTransientLimitProvider.DecideAsync(request.RootElement, CancellationToken.None);
                throw new AgentHostException("provider-self-test-transient-retry-http-request-budget-accepted", "A transient upstream failure must not send another request after the per-decision request budget is consumed.");
            }
            catch (AgentHostException exception) when (exception.Code == "provider-http-request-budget-exhausted")
            {
                if (perDecisionTransientLimitCalls != 1 || DateTimeOffset.UtcNow - startedUtc > TimeSpan.FromSeconds(2) ||
                    exception.ProviderHttpStatus != (int)HttpStatusCode.BadGateway || exception.ProviderResponseRequestId != "freeapi-request-1" ||
                    exception.ProviderFallbackAttempts != 1 || exception.ProviderFallbackTrail != "ovh/qwen3.8-27b key1=upstream_error")
                    throw new AgentHostException("provider-self-test-transient-retry-http-request-budget-not-enforced", "The provider must stop a retryable 502 before its delay or any second HTTP request, preserving safe status, request ID and fallback metadata.");
                results.Add(new { scenario = "freellmapi-per-decision-http-request-cap-blocks-transient-retry-before-delay", passed = true, providerCalls = perDecisionTransientLimitCalls, nativeCommands = 0 });
            }
        }

        var exhaustionBodyRetryCalls = 0;
        var exhaustionBodyRetryHandler = new StubHandler((_, _) =>
        {
            exhaustionBodyRetryCalls++;
            if (exhaustionBodyRetryCalls == 1)
            {
                var exhausted = new HttpResponseMessage(HttpStatusCode.TooManyRequests);
                exhausted.Content = new StringContent("{\"error\":{\"message\":\"All models exhausted. Add more API keys or wait for rate limits to reset. Soonest reset ~1s.\"}}", Encoding.UTF8, "application/json");
                return Task.FromResult(exhausted);
            }
            var recovered = JsonResponse(BuildChatResponse("{\"action\":\"tradeConfirm\",\"arguments\":{},\"rationale\":\"Confirm the current Native draft.\"}", "stop"));
            recovered.Headers.TryAddWithoutValidation("X-Routed-Via", "custom/nvidia/test-model");
            return Task.FromResult(recovered);
        });
        var exhaustionBodyRetrySettings = freeLlmApiSettings with { Model = "auto:reliable", Timeout = TimeSpan.FromSeconds(8) };
        using (var exhaustionBodyRetryClient = new HttpClient(exhaustionBodyRetryHandler) { Timeout = exhaustionBodyRetrySettings.Timeout })
        using (var exhaustionBodyRetryProvider = new OllamaNativeProvider(exhaustionBodyRetrySettings, exhaustionBodyRetryClient))
        using (var request = JsonDocument.Parse(BuildActionDecisionRequest()))
        {
            var result = await exhaustionBodyRetryProvider.DecideAsync(request.RootElement, CancellationToken.None);
            if (result.Decision["action"]?.GetValue<string>() != "tradeConfirm" || exhaustionBodyRetryCalls != 2)
                throw new AgentHostException("provider-self-test-exhaustion-body-retry-failed", "A strict FreeLLMAPI all-models-exhausted body hint should permit at most one retry when its reset ETA fits the current request deadline.");
            results.Add(new { scenario = "freellmapi-exhaustion-body-eta-allows-one-bounded-retry", passed = true, providerCalls = exhaustionBodyRetryCalls, nativeCommands = 0 });
        }

        var overDeadlineBodyCalls = 0;
        var overDeadlineBodyHandler = new StubHandler((_, _) =>
        {
            overDeadlineBodyCalls++;
            var exhausted = new HttpResponseMessage(HttpStatusCode.TooManyRequests);
            exhausted.Content = new StringContent("{\"error\":{\"message\":\"All models exhausted. Soonest reset ~2m.\"}}", Encoding.UTF8, "application/json");
            return Task.FromResult(exhausted);
        });
        var overDeadlineBodySettings = freeLlmApiSettings with { Model = "auto:reliable", Timeout = TimeSpan.FromMilliseconds(250) };
        using (var overDeadlineBodyClient = new HttpClient(overDeadlineBodyHandler) { Timeout = overDeadlineBodySettings.Timeout })
        using (var overDeadlineBodyProvider = new OllamaNativeProvider(overDeadlineBodySettings, overDeadlineBodyClient))
        using (var request = JsonDocument.Parse(BuildActionDecisionRequest()))
        {
            var startedUtc = DateTimeOffset.UtcNow;
            try
            {
                await overDeadlineBodyProvider.DecideAsync(request.RootElement, CancellationToken.None);
                throw new AgentHostException("provider-self-test-over-deadline-body-retry-accepted", "The Host must not wait for a FreeLLMAPI pool reset that cannot fit inside the current request deadline.");
            }
            catch (AgentHostException exception) when (exception.Code == "provider-http-error")
            {
                if (overDeadlineBodyCalls != 1 || DateTimeOffset.UtcNow - startedUtc > TimeSpan.FromSeconds(2) ||
                    !exception.Message.Contains("rateLimitRetrySource=body-exhaustion", StringComparison.Ordinal) ||
                    !exception.Message.Contains("freeLlmApiPoolExhausted=true", StringComparison.Ordinal) ||
                    !exception.Message.Contains("rateLimitRetryFitsDeadline=false", StringComparison.Ordinal) ||
                    !exception.Message.Contains("rateLimitRetryAfterSeconds=120", StringComparison.Ordinal) ||
                    exception.Message.Contains("All models exhausted", StringComparison.Ordinal))
                    throw new AgentHostException("provider-self-test-over-deadline-body-diagnostics-unsafe", "An over-deadline exhaustion hint must fail immediately, preserve only safe parsed diagnostics, and omit provider response text.");
                results.Add(new { scenario = "freellmapi-exhaustion-body-beyond-deadline-fails-fast-with-safe-diagnostic", passed = true, providerCalls = overDeadlineBodyCalls, nativeCommands = 0 });
            }
        }

        var exhaustedRetryAfterCalls = 0;
        var exhaustedRetryAfterHandler = new StubHandler((_, _) =>
        {
            exhaustedRetryAfterCalls++;
            var limited = new HttpResponseMessage(HttpStatusCode.TooManyRequests);
            limited.Headers.RetryAfter = new RetryConditionHeaderValue(TimeSpan.FromSeconds(1));
            return Task.FromResult(limited);
        });
        using (var exhaustedRetryAfterClient = new HttpClient(exhaustedRetryAfterHandler) { Timeout = transientRetrySettings.Timeout })
        using (var exhaustedRetryAfterProvider = new OllamaNativeProvider(transientRetrySettings, exhaustedRetryAfterClient))
        using (var request = JsonDocument.Parse(BuildActionDecisionRequest()))
        {
            try
            {
                await exhaustedRetryAfterProvider.DecideAsync(request.RootElement, CancellationToken.None);
                throw new AgentHostException("provider-self-test-retry-after-exhaustion-accepted", "A fourth 429 must fail closed after exactly three bounded retries.");
            }
            catch (AgentHostException exception) when (exception.Code == "provider-http-error")
            {
                if (exhaustedRetryAfterCalls != 4 || !exception.Message.Contains("rateLimitRetryAttempts=3", StringComparison.Ordinal) ||
                    !exception.Message.Contains("rateLimitRetryWaitMilliseconds=", StringComparison.Ordinal) ||
                    !exception.Message.Contains("rateLimitRetryEligible=true", StringComparison.Ordinal))
                    throw new AgentHostException("provider-self-test-retry-after-attempt-telemetry-missing", "A final 429 error must record the actual retry count and elapsed bounded wait.");
                results.Add(new { scenario = "freellmapi-429-allows-three-explicit-waits-then-fails-closed", passed = true, providerCalls = exhaustedRetryAfterCalls, nativeCommands = 0 });
            }
        }

        using (var overBoundRetryAfter = new HttpResponseMessage(HttpStatusCode.TooManyRequests))
        using (var diagnosticProvider = new OllamaNativeProvider(freeLlmApiSettings))
        {
            overBoundRetryAfter.Headers.RetryAfter = new RetryConditionHeaderValue(TimeSpan.FromSeconds(361));
            var failureMessage = diagnosticProvider.BuildHttpFailureMessage(overBoundRetryAfter, 0, 0);
            if (!failureMessage.Contains("rateLimitRetryEligible=false", StringComparison.Ordinal) ||
                !failureMessage.Contains("rateLimitRetryAfterSeconds=unbounded-or-unparseable", StringComparison.Ordinal))
                throw new AgentHostException("provider-self-test-retry-after-eligibility-diagnostic-missing", "An over-bound Retry-After must be reported as ineligible without logging provider response content.");
            results.Add(new { scenario = "freellmapi-429-reports-over-bound-retry-as-ineligible", passed = true });
        }

        var timeoutDuringRetryCalls = 0;
        var timeoutDuringRetryHandler = new StubHandler((_, _) =>
        {
            timeoutDuringRetryCalls++;
            var limited = new HttpResponseMessage(HttpStatusCode.TooManyRequests);
            limited.Headers.RetryAfter = new RetryConditionHeaderValue(TimeSpan.FromSeconds(5));
            return Task.FromResult(limited);
        });
        var timeoutDuringRetrySettings = freeLlmApiSettings with { Timeout = TimeSpan.FromMilliseconds(250) };
        using (var timeoutDuringRetryClient = new HttpClient(timeoutDuringRetryHandler) { Timeout = timeoutDuringRetrySettings.Timeout })
        using (var timeoutDuringRetryProvider = new OllamaNativeProvider(timeoutDuringRetrySettings, timeoutDuringRetryClient))
        using (var request = JsonDocument.Parse(BuildActionDecisionRequest()))
        {
            var startedUtc = DateTimeOffset.UtcNow;
            try
            {
                await timeoutDuringRetryProvider.DecideAsync(request.RootElement, CancellationToken.None);
                throw new AgentHostException("provider-self-test-retry-delay-outlived-provider-timeout", "A bounded Retry-After wait must remain inside the total provider timeout.");
            }
            catch (AgentHostException exception) when (exception.Code == "provider-http-error")
            {
                if (timeoutDuringRetryCalls != 1 || DateTimeOffset.UtcNow - startedUtc > TimeSpan.FromSeconds(2) ||
                    !exception.Message.Contains("rateLimitRetryFitsDeadline=false", StringComparison.Ordinal))
                    throw new AgentHostException("provider-self-test-retry-delay-sent-after-deadline", "The provider must fail a wait that cannot fit inside its overall request deadline without waiting or sending a second request.");
                results.Add(new { scenario = "freellmapi-retry-after-delay-respects-overall-provider-timeout", passed = true, providerCalls = timeoutDuringRetryCalls, nativeCommands = 0 });
            }
        }

        using (var missingRetryAfter = new HttpResponseMessage(HttpStatusCode.TooManyRequests))
        using (var observedRetryAfter = new HttpResponseMessage(HttpStatusCode.TooManyRequests))
        using (var observedLongRetryAfter = new HttpResponseMessage(HttpStatusCode.TooManyRequests))
        using (var longRetryAfter = new HttpResponseMessage(HttpStatusCode.TooManyRequests))
        using (var nonFreeRetryAfter = new HttpResponseMessage(HttpStatusCode.TooManyRequests))
        {
            observedRetryAfter.Headers.RetryAfter = new RetryConditionHeaderValue(TimeSpan.FromSeconds(85));
            observedLongRetryAfter.Headers.RetryAfter = new RetryConditionHeaderValue(TimeSpan.FromSeconds(315));
            longRetryAfter.Headers.RetryAfter = new RetryConditionHeaderValue(TimeSpan.FromSeconds(361));
            nonFreeRetryAfter.Headers.RetryAfter = new RetryConditionHeaderValue(TimeSpan.FromSeconds(1));
            if (OllamaNativeProvider.GetBoundedRateLimitRetryAfter(freeLlmApiSettings.Endpoint, observedRetryAfter) != TimeSpan.FromSeconds(85) ||
                OllamaNativeProvider.GetBoundedRateLimitRetryAfter(freeLlmApiSettings.Endpoint, observedLongRetryAfter) != TimeSpan.FromSeconds(315) ||
                OllamaNativeProvider.GetBoundedRateLimitRetryAfter(freeLlmApiSettings.Endpoint, missingRetryAfter).HasValue ||
                OllamaNativeProvider.GetBoundedRateLimitRetryAfter(freeLlmApiSettings.Endpoint, longRetryAfter).HasValue ||
                OllamaNativeProvider.GetBoundedRateLimitRetryAfter(settings.Endpoint, nonFreeRetryAfter).HasValue)
                throw new AgentHostException("provider-self-test-unbounded-rate-limit-retry-accepted", "Only explicit FreeLLMAPI Retry-After delays from 1 through 360 seconds may be retried automatically; the observed 315-second delay must remain eligible.");
            results.Add(new { scenario = "freellmapi-429-accepts-observed-315-second-retry-and-fails-closed-outside-bounds", passed = true });
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

        var pacedRouteCalls = 0;
        var pacedRouteHandler = new StubHandler((_, _) =>
        {
            pacedRouteCalls++;
            var response = JsonResponse(BuildChatResponse("{\"action\":\"tradeConfirm\",\"arguments\":{},\"rationale\":\"Confirm the current Native draft.\"}", "stop"));
            response.Headers.TryAddWithoutValidation("X-Routed-Via", "ovh/Mistral-Small-3.2-24B-Instruct-2506");
            return Task.FromResult(response);
        });
        var pacedRouteSettings = freeLlmApiSettings with { Model = "mistral-small-3.2-24b", Timeout = TimeSpan.FromMilliseconds(100) };
        using (var pacedRouteClient = new HttpClient(pacedRouteHandler) { Timeout = pacedRouteSettings.Timeout })
        using (var pacedRouteProvider = new OllamaNativeProvider(pacedRouteSettings, pacedRouteClient))
        using (var request = JsonDocument.Parse(BuildActionDecisionRequest()))
        {
            var firstResult = await pacedRouteProvider.DecideAsync(request.RootElement, CancellationToken.None);
            if (firstResult.RoutedVia != "ovh/Mistral-Small-3.2-24B-Instruct-2506" || pacedRouteCalls != 1)
                throw new AgentHostException("provider-self-test-rate-window-seed-failed", "The first OVH response did not establish the route-specific pacing window.");

            using (var rateLimitedWithoutRouteHeader = new HttpResponseMessage(HttpStatusCode.TooManyRequests))
            {
                rateLimitedWithoutRouteHeader.Headers.RetryAfter = new RetryConditionHeaderValue(TimeSpan.FromSeconds(14));
                var diagnostic = pacedRouteProvider.BuildHttpFailureMessage(rateLimitedWithoutRouteHeader, 0, 0);
                if (!diagnostic.Contains("lastSuccessfulRoute=ovh/Mistral-Small-3.2-24B-Instruct-2506", StringComparison.Ordinal) ||
                    diagnostic.Contains("routedVia=", StringComparison.Ordinal))
                    throw new AgentHostException("provider-self-test-rate-limit-last-route-diagnostic-failed", "A provider failure without X-Routed-Via must label the previous route only as lastSuccessfulRoute, never as the failed request route.");
                results.Add(new { scenario = "freellmapi-rate-limit-without-route-header-retains-last-successful-route-label", passed = true });
            }

            var secondRequestStarted = DateTimeOffset.UtcNow;
            try
            {
                await pacedRouteProvider.DecideAsync(request.RootElement, CancellationToken.None);
                throw new AgentHostException("provider-self-test-rate-window-deadline-ignored", "A route pacing wait beyond the per-request deadline must not reach another model request.");
            }
            catch (AgentHostException exception) when (exception.Code == "provider-timeout")
            {
                if (pacedRouteCalls != 1 || DateTimeOffset.UtcNow - secondRequestStarted > TimeSpan.FromSeconds(2))
                    throw new AgentHostException("provider-self-test-rate-window-exceeded-request-deadline", "The route-specific OVH pacing wait must stop at the model request deadline and must not add a 45-second tail.");
                results.Add(new { scenario = "freellmapi-rate-window-wait-respects-per-request-deadline", passed = true, providerCalls = pacedRouteCalls, nativeCommands = 0 });
            }
        }

        foreach (var status in new[] { HttpStatusCode.BadRequest, HttpStatusCode.UnprocessableEntity, HttpStatusCode.BadGateway })
        {
            using var explicitSchemaRejection = new HttpResponseMessage(status);
            explicitSchemaRejection.Headers.TryAddWithoutValidation("X-Fallback-Trail", "ovh/Mistral-Small key1=provider_bad_request");
            if (!OllamaNativeProvider.ShouldRetryWithJsonObject(rateWindowEndpoint, explicitSchemaRejection))
                throw new AgentHostException("provider-self-test-json-schema-rejection-status-not-recognized", $"FreeLLMAPI explicit provider_bad_request status {(int)status} did not enable one bounded JSON-object compatibility retry.");
        }
        var formatFallbackCalls = 0;
        var formatFallbackModes = new List<string>();
        var formatIgnoredFallbackHandler = new StubHandler((httpRequest, cancellationToken) =>
        {
            formatFallbackCalls++;
            using var payloadDocument = JsonDocument.Parse(httpRequest.Content!.ReadAsStringAsync().GetAwaiter().GetResult());
            formatFallbackModes.Add(payloadDocument.RootElement.GetProperty("response_format").GetProperty("type").GetString() ?? "missing");
            if (formatFallbackCalls == 1)
            {
                var ignoredFormat = new HttpResponseMessage(HttpStatusCode.BadGateway);
                ignoredFormat.Headers.TryAddWithoutValidation("X-Fallback-Trail", "custom/nvidia/llama-3.2-11b-vision key1=format_ignored");
                return Task.FromResult(ignoredFormat);
            }
            return Task.FromResult(JsonResponse(BuildChatResponse("{\"action\":\"tradeConfirm\",\"arguments\":{}}", "stop")));
        });
        using (var formatFallbackClient = new HttpClient(formatIgnoredFallbackHandler) { Timeout = freeLlmApiSettings.Timeout })
        using (var formatFallbackProvider = new OllamaNativeProvider(freeLlmApiSettings with { Model = "nvidiallama-3.2-11b-vision" }, formatFallbackClient))
        using (var request = JsonDocument.Parse(BuildActionDecisionRequest()))
        {
            var result = await formatFallbackProvider.DecideAsync(request.RootElement, CancellationToken.None);
            if (result.Decision["action"]?.GetValue<string>() != "tradeConfirm" ||
                result.Decision["rationale"]?.GetValue<string>() != string.Empty ||
                result.ResponseFormatMode != "json_object_fallback" ||
                formatFallbackCalls != 2 ||
                !formatFallbackModes.SequenceEqual(new[] { "json_schema", "json_object" }, StringComparer.Ordinal))
                throw new AgentHostException("provider-self-test-format-ignored-json-fallback-failed", $"A FreeLLMAPI 502 explicitly classifying format_ignored must permit exactly one JSON-object retry, then normalize the returned Native action through the normal catalog contract. calls={formatFallbackCalls}; modes={string.Join(',', formatFallbackModes)}; action={result.Decision["action"]?.GetValue<string>() ?? "missing"}; format={result.ResponseFormatMode}.");
            results.Add(new { scenario = "freellmapi-format-ignored-502-falls-back-once-to-locally-normalized-native-action", passed = true, providerCalls = formatFallbackCalls, nativeCommands = 0 });
        }
        using (var transientGatewayFailure = new HttpResponseMessage(HttpStatusCode.BadGateway))
        {
            transientGatewayFailure.Headers.TryAddWithoutValidation("X-Fallback-Trail", "ovh/Mistral-Small key1=upstream_error");
            using var formatIgnoredBadRequest = new HttpResponseMessage(HttpStatusCode.BadRequest);
            formatIgnoredBadRequest.Headers.TryAddWithoutValidation("X-Fallback-Trail", "custom/nvidia/model key1=format_ignored");
            using var nonGatewayBadRequest = new HttpResponseMessage(HttpStatusCode.BadRequest);
            nonGatewayBadRequest.Headers.TryAddWithoutValidation("X-Fallback-Trail", "ovh/Mistral-Small key1=provider_bad_request");
            if (OllamaNativeProvider.ShouldRetryWithJsonObject(rateWindowEndpoint, transientGatewayFailure) ||
                OllamaNativeProvider.ShouldRetryWithJsonObject(rateWindowEndpoint, formatIgnoredBadRequest) ||
                !OllamaNativeProvider.ShouldRetryTransientFreeLlmApiFailure(rateWindowEndpoint, transientGatewayFailure) ||
                OllamaNativeProvider.ShouldRetryTransientFreeLlmApiFailure(rateWindowEndpoint, nonGatewayBadRequest) ||
                OllamaNativeProvider.ShouldRetryWithJsonObject(new Uri("http://127.0.0.1:11434/v1/chat/completions"), nonGatewayBadRequest))
                throw new AgentHostException("provider-self-test-retried-non-schema-failure", "JSON-object compatibility retry must be limited to explicit FreeLLMAPI provider_bad_request responses.");
        }
        results.Add(new { scenario = "freellmapi-json-object-fallback-recognizes-schema-rejection-or-format-ignored-502-only", passed = true });

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
            goal = control switch
            {
                "supportedVillageToolsQuestGoal" => "Complete the currently visible village tools quest.",
                "supportedBattleSimulationGoal" => "Resolve one currently visible hostile bandit encounter using Campaign Send Troops and verify actual outcomes.",
                "supportedBattleAndCaptivityGoal" => "Resolve a Native battle and continue the actual MainHero captivity process until free on the map.",
                "supportedEstablishYourClanGoal" => "Autonomously pursue the active original StoryMode Establish Your Clan quest through the Host's currently integrated Native objective routes.",
                "supportedCaptivityRecoveryGoal" => "Recover from the current Native captivity state, then replan one unmet active Establish Your Clan objective.",
                "supportedEstablishClanGoldSaleGoal" => "Sell one currently sellable item through Native Trade to increase the active Establish Your Clan Gold Journal progress.",
                _ => "Move to any visible safe settlement."
            },
            goalScopeClassificationRequired = expectedClassification != "provider-goal-classification-unavailable",
            goalScopeContract = "native-campaign-goal-classification-v1",
            observation = new
            {
                scope = "goal-classification-test",
                state = new
                {
                    gameState = "MapState",
                    quests = allowedControls.Contains("supportedEstablishYourClanGoal") || allowedControls.Contains("supportedEstablishClanGoldSaleGoal")
                        ? new[] { new { id = "rebuild_player_clan_storymode_quest", title = "Establish Your Clan" } }
                        : Array.Empty<object>(),
                    context = new
                    {
                        captivity = allowedControls.Contains("supportedCaptivityRecoveryGoal")
                            ? (object?)new { isCaptive = true }
                            : null
                    }
                }
            },
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
            if (!AgentHostDecisionCycle.CampaignGoalClassificationPrompt.Contains("complete requested final outcome", StringComparison.Ordinal) ||
                !AgentHostDecisionCycle.CampaignGoalClassificationPrompt.Contains("may be written in Chinese", StringComparison.Ordinal) ||
                !AgentHostDecisionCycle.CampaignGoalClassificationPrompt.Contains("live Native preconditions are currently met", StringComparison.Ordinal))
                throw new AgentHostException("provider-goal-classification-prompt-incomplete", "The classifier prompt omitted outcome-first, multilingual or scope-versus-availability guidance.");
            if (control == "supportedEstablishYourClanGoal")
            {
                if (system.Length > 1000 ||
                    !system.Contains("supportedEstablishYourClanGoal", StringComparison.Ordinal) ||
                    !system.Contains("four Journal objectives are substeps of that one goal", StringComparison.Ordinal) ||
                    system.Contains("VillageNeedsToolsIssue", StringComparison.Ordinal) || system.Contains("BattleSimulation", StringComparison.Ordinal))
                    throw new AgentHostException("provider-goal-classification-eyc-prompt-not-compact", $"Explicit EYC prompt violated compactness (chars={system.Length}, listedControl={system.Contains("supportedEstablishYourClanGoal", StringComparison.Ordinal)}, substeps={system.Contains("four Journal objectives are substeps of that one goal", StringComparison.Ordinal)}, unrelatedVillage={system.Contains("VillageNeedsToolsIssue", StringComparison.Ordinal)}, unrelatedBattle={system.Contains("BattleSimulation", StringComparison.Ordinal)}).");
            }
            else if (!system.Contains("complete requested final outcome", StringComparison.Ordinal) ||
                     !system.Contains("may be written in Chinese", StringComparison.Ordinal) ||
                     !system.Contains("live Native preconditions are currently met", StringComparison.Ordinal))
                throw new AgentHostException("provider-goal-classification-prompt-incomplete", "The classifier prompt omitted outcome-first, multilingual or scope-versus-availability guidance.");
            var scopeMarkers = new (string Control, string Marker)[]
            {
                ("supportedMapArrivalGoal", "later-observed safe visible settlement"),
                ("supportedVillageToolsQuestGoal", "VillageNeedsToolsIssue (村庄工具委托)"),
                ("supportedBattleSimulationGoal", "Native Campaign Send Troops/BattleSimulation path"),
                ("supportedBattleAndCaptivityGoal", "continue through enabled Native captivity options until free"),
                ("supportedEstablishYourClanGoal", "exact active StoryMode quest rebuild_player_clan_storymode_quest"),
                ("supportedCaptivityRecoveryGoal", "MainHero already captive and the original Establish Your Clan quest active"),
                ("supportedEstablishClanGoldSaleGoal", "currently sellable Goods item"),
                ("unsupportedGoal", "named destinations, other quests, fixed reward amounts")
            };
            var listedControlSet = new HashSet<string>(allowedControls, StringComparer.Ordinal);
            foreach (var scopeMarker in scopeMarkers)
            {
                if (control != "supportedEstablishYourClanGoal" && system.Contains(scopeMarker.Marker, StringComparison.Ordinal) != listedControlSet.Contains(scopeMarker.Control))
                    throw new AgentHostException("provider-goal-classification-scope-catalog-mismatch", "The classifier prompt did not match its scope explanations to exactly the currently listed controls.");
            }
            if (control == "supportedCaptivityRecoveryGoal" &&
                (!system.Contains("prisoner_wait", StringComparison.Ordinal) || !system.Contains("never hide time changes", StringComparison.Ordinal) || !system.Contains("already captive", StringComparison.Ordinal)))
                throw new AgentHostException("provider-captivity-classification-prompt-incomplete", "The classifier prompt omitted the current-captivity boundary or explicit time-control separation.");
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
        using var unobservedStoryRequest = JsonDocument.Parse("""
            {"goal":"Select an Establish Your Clan objective.","goalScopeClassificationRequired":true,"observation":{"scope":"goal-classification-only","state":{"quests":[{"id":"issue_64_quest"}]}},"allowedActions":[],"allowedControls":["unsupportedGoal"]}
            """);
        using var storyDecision = JsonDocument.Parse("""
            {"control":"supportedEstablishYourClanGoal","reason":"Handle the active StoryMode quest."}
            """);
        try
        {
            _ = OllamaNativeProvider.NormalizeDecision(storyDecision.RootElement, unobservedStoryRequest.RootElement);
            throw new AgentHostException("provider-establish-clan-classification-gate-overbroad", "The planner scope was accepted without its exact active quest being listed by the fresh Native state.");
        }
        catch (AgentHostException exception) when (exception.Code == "provider-goal-classification-unavailable") { }
        using var unobservedCaptivityRequest = JsonDocument.Parse("""
            {"goal":"Recover from current captivity.","goalScopeClassificationRequired":true,"observation":{"scope":"goal-classification-only","state":{"context":{"captivity":null}}},"allowedActions":[],"allowedControls":["unsupportedGoal"]}
            """);
        using var captivityDecision = JsonDocument.Parse("""
            {"control":"supportedCaptivityRecoveryGoal","reason":"Recover the captive player."}
            """);
        try
        {
            _ = OllamaNativeProvider.NormalizeDecision(captivityDecision.RootElement, unobservedCaptivityRequest.RootElement);
            throw new AgentHostException("provider-captivity-classification-gate-overbroad", "The captivity recovery scope was accepted without current Native captivity being observed.");
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
        var alternatives = schema["properties"]!["decision"]!["anyOf"]!.AsArray();
        var enumValues = alternatives[0]!["properties"]!["arguments"]!["properties"]!["OptionId"]!["enum"] as JsonArray;
        var amountValues = alternatives[1]!["properties"]!["arguments"]!["properties"]!["Amount"]!["enum"] as JsonArray;
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
        var expectedPrompt = expectedPromptMember == "SupplySystemPrompt"
            ? AgentHostDecisionCycle.SupplySystemPrompt
            : AgentHostDecisionCycle.CampaignSystemPrompt + " " + AgentHostDecisionCycle.QuestTerminalOutcomeRule;
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

    private static string BuildToolCallChatResponse(string arguments, string finishReason) => JsonSerializer.Serialize(new
    {
        model = "north-mini-code",
        choices = new[]
        {
            new
            {
                index = 0,
                message = new
                {
                    role = "assistant",
                    content = (string?)null,
                    tool_calls = new[]
                    {
                        new
                        {
                            id = "call_chronicle_decision",
                            type = "function",
                            function = new { name = "submit_chronicle_decision", arguments }
                        }
                    }
                },
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
        var decisionSchema = root.GetProperty("response_format").GetProperty("json_schema").GetProperty("schema");
        var decisionAlternatives = decisionSchema.GetProperty("properties").GetProperty("decision").GetProperty("anyOf");
        if (root.GetProperty("model").GetString() != "test-local-model" ||
            root.GetProperty("response_format").GetProperty("type").GetString() != "json_schema" ||
            root.GetProperty("response_format").GetProperty("json_schema").GetProperty("name").GetString() != "chronicle_agent_decision" ||
            !root.GetProperty("response_format").GetProperty("json_schema").GetProperty("strict").GetBoolean() ||
            decisionSchema.GetProperty("type").GetString() != "object" ||
            decisionSchema.GetProperty("required")[0].GetString() != "decision" ||
            decisionSchema.TryGetProperty("oneOf", out _) || decisionAlternatives.GetArrayLength() != 1 ||
            decisionAlternatives[0].GetProperty("properties").GetProperty("control").GetProperty("enum")[0].GetString() != "done" ||
            decisionAlternatives[0].GetProperty("properties").TryGetProperty("reason", out var reasonSchema) && reasonSchema.TryGetProperty("maxLength", out _) ||
            root.GetProperty("max_completion_tokens").GetInt32() != 128 ||
            root.TryGetProperty("store", out _) || root.TryGetProperty("reasoning_effort", out _))
            throw new AgentHostException("provider-self-test-request-failed", "Provider request did not use a strict-compatible wrapper object constrained to the current decision catalog.");
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
            root.GetProperty("stream").GetBoolean() ||
            root.GetProperty("format").GetProperty("properties").GetProperty("decision").GetProperty("anyOf").GetArrayLength() != 1 ||
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
