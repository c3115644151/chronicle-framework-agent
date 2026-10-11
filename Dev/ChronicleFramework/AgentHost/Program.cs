using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal static class Program
{
    private static readonly JsonSerializerOptions OutputJsonOptions = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };

    private static async Task<int> Main(string[] args)
    {
        try
        {
            if (args.Length == 1 && string.Equals(args[0], "--provider-self-test", StringComparison.Ordinal))
            {
                var providerTests = await ProviderContractSelfTest.RunAsync();
                Console.Out.WriteLine(JsonSerializer.Serialize(providerTests, OutputJsonOptions));
                return 0;
            }

            var options = HostOptions.Parse(args);
            if (options.DecisionOnce)
            {
                var requestJson = await Console.In.ReadToEndAsync();
                using var requestDocument = JsonDocument.Parse(requestJson);
                using var provider = OllamaNativeProvider.FromEnvironment();
                var decision = await provider.DecideAsync(requestDocument.RootElement, CancellationToken.None);
                Console.Out.WriteLine(JsonSerializer.Serialize(decision, OutputJsonOptions));
                return 0;
            }

            var protocolRoot = GetProtocolRoot(options.ProtocolRoot);
            Directory.CreateDirectory(protocolRoot);
            Directory.CreateDirectory(Path.Combine(protocolRoot, "responses"));

            using var mutex = new Mutex(initiallyOwned: true, GetMutexName(protocolRoot), out var createdNew);
            if (!createdNew)
                throw new AgentHostException("host-already-running", "A Chronicle Agent Host already owns this protocol root.");

            if (options.ProtocolRejectionTest)
            {
                if (Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE") != "agent-host-protocol-test" ||
                    string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP")))
                    throw new AgentHostException("protocol-test-not-authorized", "The invalid-option protocol probe is restricted to its disposable Harness phase.");
                var rejection = await RunProtocolRejectionTestAsync(protocolRoot, CancellationToken.None);
                Console.Out.WriteLine(JsonSerializer.Serialize(rejection, OutputJsonOptions));
                return rejection["passed"]?.GetValue<bool>() == true ? 0 : 1;
            }

            if (options.SupplyLoop)
            {
                var requestJson = await Console.In.ReadToEndAsync();
                using var requestDocument = JsonDocument.Parse(requestJson);
                var loopResult = await AgentHostSupplyLoop.RunAsync(requestDocument.RootElement, protocolRoot, CancellationToken.None);
                Console.Out.WriteLine(JsonSerializer.Serialize(loopResult, OutputJsonOptions));
                return loopResult["status"]?.GetValue<string>() == "completed" ? 0 : 1;
            }

            var result = await RequestCurrentStateAsync(protocolRoot, options.Timeout, CancellationToken.None);
            Console.Out.WriteLine(JsonSerializer.Serialize(result, OutputJsonOptions));
            return 0;
        }
        catch (AgentHostException exception)
        {
            Console.Error.WriteLine(JsonSerializer.Serialize(new
            {
                status = "failed",
                error = exception.Code,
                message = exception.Message
            }, OutputJsonOptions));
            return 2;
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine(JsonSerializer.Serialize(new
            {
                status = "failed",
                error = "host-unexpected-error",
                exceptionType = exception.GetType().Name
            }, OutputJsonOptions));
            return 3;
        }
    }

    private static async Task<HostStateResult> RequestCurrentStateAsync(
        string protocolRoot,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        var commandId = "host-state-" + Guid.NewGuid().ToString("N");
        var commandPath = Path.Combine(protocolRoot, "command.json");
        var responseRoot = Path.Combine(protocolRoot, "responses");
        var temporaryPath = commandPath + "." + commandId + ".tmp";
        var payload = JsonSerializer.Serialize(new { id = commandId, action = "state" });

        await WriteAtomicallyAsync(temporaryPath, payload, cancellationToken);
        try
        {
            try
            {
                File.Move(temporaryPath, commandPath, overwrite: false);
            }
            catch (IOException exception) when (File.Exists(commandPath))
            {
                throw new AgentHostException("protocol-command-busy", "The Native protocol mailbox already has an owner.", exception);
            }

            var deadline = Stopwatch.GetTimestamp() + (long)(timeout.TotalSeconds * Stopwatch.Frequency);
            while (Stopwatch.GetTimestamp() < deadline)
            {
                cancellationToken.ThrowIfCancellationRequested();
                foreach (var status in new[] { "completed", "rejected", "failed" })
                {
                    var responsePath = Path.Combine(responseRoot, commandId + "." + status + ".json");
                    if (!File.Exists(responsePath))
                        continue;

                    using var response = await ReadJsonAsync(responsePath, cancellationToken);
                    ValidateResponse(response.RootElement, commandId, status);
                    return BuildResult(response.RootElement);
                }

                await Task.Delay(TimeSpan.FromMilliseconds(100), cancellationToken);
            }

            throw new AgentHostException("native-state-timeout", $"The current Bannerlord client did not answer the read-only state request within {timeout.TotalSeconds:0} seconds.");
        }
        catch
        {
            TryRemoveOwnedUnclaimedCommand(commandPath, commandId);
            throw;
        }
        finally
        {
            TryDelete(temporaryPath);
        }
    }

    private static HostStateResult BuildResult(JsonElement response)
    {
        var state = response.GetProperty("state");
        var identity = state.GetProperty("identity");
        var party = state.GetProperty("party");
        var context = state.GetProperty("context");

        return new HostStateResult(
            response.GetProperty("commandId").GetString() ?? string.Empty,
            response.GetProperty("processId").GetInt32(),
            response.GetProperty("campaignDay").GetDouble(),
            response.GetProperty("dailyTickCount").GetInt32(),
            response.GetProperty("timeControlMode").GetString() ?? string.Empty,
            identity.GetProperty("heroId").GetString() ?? string.Empty,
            identity.TryGetProperty("clanId", out var clanId) ? clanId.GetString() ?? string.Empty : string.Empty,
            party.GetProperty("id").GetString() ?? string.Empty,
            party.GetProperty("members").GetInt32(),
            context.GetProperty("gameState").GetString() ?? string.Empty);
    }

    private static void ValidateResponse(JsonElement response, string commandId, string responseStatus)
    {
        if (ReadInt(response, "protocolVersion") != 1)
                throw new AgentHostException("protocol-version-mismatch", "The Native bridge returned an unsupported protocol version.");
        if (!string.Equals(ReadString(response, "commandId"), commandId, StringComparison.Ordinal))
            throw new AgentHostException("protocol-correlation-mismatch", "The Native bridge response did not match this request.");
        if (!string.Equals(ReadString(response, "action"), "state", StringComparison.Ordinal))
            throw new AgentHostException("protocol-action-mismatch", "The Native bridge answered with a different action.");
        if (!string.Equals(ReadString(response, "status"), responseStatus, StringComparison.Ordinal))
            throw new AgentHostException("protocol-status-mismatch", "The Native bridge response status did not match its response file.");
        if (responseStatus != "completed")
        {
            var error = ReadString(response, "error");
            throw new AgentHostException("native-state-rejected", string.IsNullOrWhiteSpace(error) ? "The Native bridge rejected the state request." : "The Native bridge rejected the state request: " + error);
        }
        if (ReadInt(response, "processId") <= 0)
            throw new AgentHostException("native-process-id-invalid", "The Native bridge returned an invalid game process ID.");
        if (!response.TryGetProperty("state", out var state) || state.ValueKind != JsonValueKind.Object)
            throw new AgentHostException("native-state-missing", "The Native bridge response did not contain a state object.");
        if (!state.TryGetProperty("identity", out var identity) || identity.ValueKind != JsonValueKind.Object ||
            string.IsNullOrWhiteSpace(ReadString(identity, "heroId")))
            throw new AgentHostException("native-player-identity-missing", "The Native state did not identify the current MainHero.");
        if (!state.TryGetProperty("party", out var party) || party.ValueKind != JsonValueKind.Object ||
            string.IsNullOrWhiteSpace(ReadString(party, "id")))
            throw new AgentHostException("native-main-party-missing", "The Native state did not identify the current MainParty.");
        if (!state.TryGetProperty("context", out var context) || context.ValueKind != JsonValueKind.Object)
            throw new AgentHostException("native-game-context-missing", "The Native state did not contain the current game context.");
    }

    private static async Task<JsonDocument> ReadJsonAsync(string path, CancellationToken cancellationToken)
    {
        for (var attempt = 0; attempt < 5; attempt++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            try
            {
                var text = await File.ReadAllTextAsync(path, cancellationToken);
                return JsonDocument.Parse(text);
            }
            catch (IOException) when (attempt < 4)
            {
                await Task.Delay(TimeSpan.FromMilliseconds(20), cancellationToken);
            }
            catch (JsonException) when (attempt < 4)
            {
                await Task.Delay(TimeSpan.FromMilliseconds(20), cancellationToken);
            }
        }

        throw new AgentHostException("native-response-unreadable", "The Native bridge response could not be read as complete JSON.");
    }

    private static async Task WriteAtomicallyAsync(string path, string contents, CancellationToken cancellationToken)
    {
        await using var stream = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough);
        var bytes = new UTF8Encoding(encoderShouldEmitUTF8Identifier: false).GetBytes(contents);
        await stream.WriteAsync(bytes, cancellationToken);
        await stream.FlushAsync(cancellationToken);
        stream.Flush(flushToDisk: true);
    }

    private static void TryRemoveOwnedUnclaimedCommand(string commandPath, string commandId)
    {
        try
        {
            if (!File.Exists(commandPath))
                return;
            using var document = JsonDocument.Parse(File.ReadAllText(commandPath));
            if (string.Equals(ReadString(document.RootElement, "id"), commandId, StringComparison.Ordinal))
                File.Delete(commandPath);
        }
        catch (IOException)
        {
            // The game's tick loop may be claiming the file at the same moment.
        }
        catch (JsonException)
        {
            // Never remove a mailbox file that cannot be proven to belong to this request.
        }
    }

    private static string GetProtocolRoot(string? requestedRoot)
    {
        var root = requestedRoot ?? Environment.GetEnvironmentVariable("CHRONICLE_AGENT_PROTOCOL_ROOT");
        if (string.IsNullOrWhiteSpace(root))
        {
            var documents = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
            if (string.IsNullOrWhiteSpace(documents))
                throw new AgentHostException("documents-path-unavailable", "The Windows Documents directory could not be resolved.");
            root = Path.Combine(documents, "Mount and Blade II Bannerlord", "AgentRuns", "ChronicleAgent");
        }

        return Path.GetFullPath(root);
    }

    private static async Task<JsonObject> RunProtocolRejectionTestAsync(string protocolRoot, CancellationToken cancellationToken)
    {
        var client = new NativeMailboxClient(protocolRoot, TimeSpan.FromSeconds(15));
        using var before = await client.ReadStateAsync(cancellationToken);
        var beforeState = CloneObject(before.RootElement);
        var invalidArguments = new JsonObject
        {
            ["menuId"] = "__chronicle_invalid_menu__",
            ["optionId"] = "__chronicle_invalid_option__"
        };
        using var rejected = await client.ExecuteSupplyActionAsync("menuSelect", invalidArguments, cancellationToken);
        var rejection = CloneObject(rejected.RootElement);
        using var after = await client.ReadStateAsync(cancellationToken);
        var afterState = CloneObject(after.RootElement);
        var errorText = rejection["error"]?.GetValue<string>() ?? string.Empty;
        var beforeFingerprint = BuildProtocolTestFingerprint(beforeState);
        var afterFingerprint = BuildProtocolTestFingerprint(afterState);
        return new JsonObject
        {
            ["passed"] = rejection["status"]?.GetValue<string>() == "rejected" &&
                errorText.Contains('\n') &&
                (beforeState["processId"]?.GetValue<int>() ?? -1) == (rejection["processId"]?.GetValue<int>() ?? -2) &&
                (beforeState["processId"]?.GetValue<int>() ?? -1) == (afterState["processId"]?.GetValue<int>() ?? -2) &&
                beforeFingerprint.ToJsonString() == afterFingerprint.ToJsonString(),
            ["action"] = "menuSelect",
            ["status"] = rejection["status"]?.GetValue<string>(),
            ["errorType"] = errorText.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries).FirstOrDefault()?.Split(':')[0],
            ["escapedControlCharactersParse"] = errorText.Contains('\n'),
            ["campaignStateUnchanged"] = beforeFingerprint.ToJsonString() == afterFingerprint.ToJsonString(),
            ["gameProcessId"] = beforeState["processId"]?.GetValue<int>() ?? -1
        };
    }

    private static JsonObject BuildProtocolTestFingerprint(JsonObject response)
    {
        var state = response["state"]!.AsObject();
        var identity = state["identity"]!.AsObject();
        var party = state["party"]!.AsObject();
        var economy = state["economy"]!.AsObject();
        var location = state["location"]!.AsObject();
        var context = state["context"]!.AsObject();
        return new JsonObject
        {
            ["heroId"] = identity["heroId"]?.DeepClone(),
            ["clanId"] = identity["clanId"]?.DeepClone(),
            ["partyId"] = party["id"]?.DeepClone(),
            ["members"] = party["members"]?.DeepClone(),
            ["gold"] = economy["gold"]?.DeepClone(),
            ["food"] = party["food"]?.DeepClone(),
            ["foodInventory"] = party["foodInventory"]?.DeepClone(),
            ["settlementId"] = location["currentSettlementId"]?.DeepClone(),
            ["menuId"] = context["menuId"]?.DeepClone(),
            ["timeControlMode"] = context["timeControlMode"]?.DeepClone()
        };
    }

    private static JsonObject CloneObject(JsonElement value) => JsonNode.Parse(value.GetRawText())!.AsObject();

    private static string GetMutexName(string protocolRoot)
    {
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(protocolRoot.ToUpperInvariant())));
        return "Local\\ChronicleAgentHost_" + hash[..24];
    }

    private static string? ReadString(JsonElement element, string name) =>
        element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;

    private static int ReadInt(JsonElement element, string name) =>
        element.TryGetProperty(name, out var value) && value.TryGetInt32(out var result) ? result : 0;

    private static void TryDelete(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); }
        catch (IOException) { }
    }

    private sealed record HostStateResult(
        string CommandId,
        int BannerlordProcessId,
        double CampaignDay,
        int DailyTickCount,
        string TimeControlMode,
        string MainHeroId,
        string PlayerClanId,
        string MainPartyId,
        int MainPartyMembers,
        string GameState);

    private sealed record HostOptions(string? ProtocolRoot, TimeSpan Timeout, bool DecisionOnce, bool SupplyLoop, bool ProtocolRejectionTest)
    {
        internal static HostOptions Parse(string[] args)
        {
            string? root = null;
            var timeoutSeconds = 15;
            var decisionOnce = false;
            var supplyLoop = false;
            var protocolRejectionTest = false;
            for (var index = 0; index < args.Length; index++)
            {
                switch (args[index])
                {
                    case "--protocol-root" when index + 1 < args.Length:
                        root = args[++index];
                        break;
                    case "--timeout-seconds" when index + 1 < args.Length && int.TryParse(args[index + 1], out var parsedTimeout):
                        timeoutSeconds = parsedTimeout;
                        index++;
                        break;
                    case "--state-once":
                        break;
                    case "--decision-once":
                        decisionOnce = true;
                        break;
                    case "--supply-loop":
                        supplyLoop = true;
                        break;
                    case "--protocol-rejection-test":
                        protocolRejectionTest = true;
                        break;
                    default:
                        throw new AgentHostException("host-arguments-invalid", "Agent Host arguments were not recognized.");
                }
            }

            if (timeoutSeconds is < 1 or > 300)
                throw new AgentHostException("host-timeout-invalid", "Host timeout must be from 1 to 300 seconds.");
            if ((decisionOnce ? 1 : 0) + (supplyLoop ? 1 : 0) + (protocolRejectionTest ? 1 : 0) > 1)
                throw new AgentHostException("host-mode-conflict", "Select one Host execution mode.");
            return new HostOptions(root, TimeSpan.FromSeconds(timeoutSeconds), decisionOnce, supplyLoop, protocolRejectionTest);
        }
    }
}
