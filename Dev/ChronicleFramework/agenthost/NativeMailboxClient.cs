using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ChronicleFramework.AgentHost;

internal sealed class NativeMailboxClient : IAgentHostVillageToolsQuestNativeClient, IAgentHostBattleSimulationNativeClient,
    IAgentHostBattleMissionNativeClient,
    IAgentHostQuestDetailsNativeClient, IAgentHostCaptivityRecoveryNativeClient, IAgentHostGoldSaleNativeClient,
    IAgentHostRecruitmentNativeClient, IAgentHostSupplyNativeClient, IAgentHostCompanionHiringNativeClient, IAgentHostStoryModeBootstrapNativeClient,
    IAgentHostNativeInquiryClient, IAgentHostStoryModeBannerEditorNativeClient, IAgentHostEstablishClanTrainingIssueNativeClient,
    IAgentHostQuestTroopScreenNativeClient, IAgentHostCampaignCheckpointNativeClient
{
    private static readonly HashSet<string> SupplySliceActions = new(StringComparer.Ordinal)
    {
        "state", "menuSelect", "foodOptions", "provision", "tradeConfirm", "tradeCancelChanges", "rest"
    };

    private static readonly HashSet<string> VillageToolsQuestActions = new(StringComparer.Ordinal)
    {
        "mapSettlementTargets", "move", "menuSelect", "talkToSettlementHero", "dialogueSelect",
        "dialogueContinue", "questDetails", "tradeOptions", "trade", "tradeConfirm", "tradeCancel", "tradeCancelChanges",
        "barterOptions", "barterAutoBalance", "barterOffer", "barterCancel",
        "inventoryOpen", "heroEquipmentOptions", "inventoryCancel"
    };
    private static readonly HashSet<string> BattleSimulationActions = new(StringComparer.Ordinal)
    {
        "mapPartyTargets", "pursue", "dialogueSelect", "dialogueContinue", "menuSelect", "battleSkip", "battleFinish", "partyTakeAll", "partyLootTransferOne", "partyScreenDone", "inventoryTakeAll", "inventoryDone"
    };

    private readonly string _root;
    private readonly string _responseRoot;
    private readonly TimeSpan _timeout;
    private readonly int? _expectedProcessId;
    private readonly string? _expectedNativeSessionId;

    internal NativeMailboxClient(string protocolRoot, TimeSpan timeout, int? expectedProcessId = null, string? expectedNativeSessionId = null)
    {
        _root = Path.GetFullPath(protocolRoot);
        _responseRoot = Path.Combine(_root, "responses");
        _timeout = timeout;
        _expectedProcessId = expectedProcessId;
        _expectedNativeSessionId = expectedNativeSessionId;
        Directory.CreateDirectory(_root);
        Directory.CreateDirectory(_responseRoot);
    }

    internal static string GetDefaultProtocolRoot()
    {
        var documents = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
        if (string.IsNullOrWhiteSpace(documents))
            throw new AgentHostException("documents-path-unavailable", "The Windows Documents directory could not be resolved.");
        return Path.Combine(documents, "Mount and Blade II Bannerlord", "AgentRuns", "ChronicleAgent");
    }

    internal Task<JsonDocument> ReadStateAsync(CancellationToken cancellationToken) =>
        SendAsync("state", new JsonObject(), acceptedResponseExpected: false, cancellationToken);

    public Task<JsonDocument> ReadCampaignCheckpointAsync(CancellationToken cancellationToken) =>
        SendAsync("agentCheckpointGet", new JsonObject(), acceptedResponseExpected: false, cancellationToken);

    public Task<JsonDocument> WriteCampaignCheckpointAsync(string checkpointJson, CancellationToken cancellationToken)
    {
        var checkpointBase64 = AgentHostCampaignCheckpointCodec.EncodeForNative(checkpointJson);
        return SendAsync("agentCheckpointSet", new JsonObject { ["checkpointBase64"] = checkpointBase64 }, acceptedResponseExpected: false, cancellationToken);
    }

    public Task<JsonDocument> RespondNativeInquiryAsync(string token, string choice, CancellationToken cancellationToken)
    {
        ValidateNativeInquiryResponse(token, choice);
        return SendAsync("respondInquiry", new JsonObject { ["token"] = token, ["choice"] = choice }, acceptedResponseExpected: false, cancellationToken);
    }

    public Task<JsonDocument> SubmitStoryModeClanNameAsync(string token, string clanName, CancellationToken cancellationToken)
    {
        ValidateStoryModeClanNameSubmission(token, clanName);
        return SendAsync("submitStoryModeClanName", new JsonObject { ["token"] = token, ["text"] = clanName }, acceptedResponseExpected: false, cancellationToken);
    }

    public Task<JsonDocument> CompleteStoryModeBannerEditorAsync(CancellationToken cancellationToken) =>
        SendAsync("bannerEditorDone", new JsonObject(), acceptedResponseExpected: false, cancellationToken);

    internal static void ValidateNativeInquiryResponse(string token, string choice)
    {
        if (string.IsNullOrWhiteSpace(token) || token.Length > 256 || choice is not ("affirmative" or "negative"))
            throw new AgentHostException("native-inquiry-response-arguments-invalid", "The Native Inquiry adapter requires a current token and one explicit affirmative/negative choice.");
    }

    internal static IReadOnlyList<object> RunNativeInquiryResponseContractSelfTests()
    {
        ValidateNativeInquiryResponse("current-token", "affirmative");
        ValidateNativeInquiryResponse("current-token", "negative");
        foreach (var item in new[] { (Token: "", Choice: "affirmative"), (Token: "current-token", Choice: "stop"), (Token: "current-token", Choice: "yes") })
        {
            try
            {
                ValidateNativeInquiryResponse(item.Token, item.Choice);
                throw new AgentHostException("native-inquiry-response-invalid-accepted", "The Native Inquiry adapter accepted a missing token or a non-native choice.");
            }
            catch (AgentHostException exception) when (exception.Code == "native-inquiry-response-arguments-invalid") { }
        }
        return [new { scenario = "native-inquiry-mailbox-accepts-only-token-bound-explicit-yes-no-choices", passed = true }];
    }

    internal static void ValidateStoryModeClanNameSubmission(string token, string clanName)
    {
        if (string.IsNullOrWhiteSpace(token) || token.Length > 256 || string.IsNullOrWhiteSpace(clanName) || clanName.Length > 64)
            throw new AgentHostException("native-storymode-clan-name-arguments-invalid", "The StoryMode clan-name adapter requires a current token and 1-64 non-whitespace characters.");
    }

    internal static IReadOnlyList<object> RunStoryModeClanNameContractSelfTests()
    {
        ValidateStoryModeClanNameSubmission("current-token", "Chronicle Vanguard");
        foreach (var item in new[] { (Token: "", Name: "Chronicle Vanguard"), (Token: "token", Name: " "), (Token: "token", Name: new string('x', 65)) })
        {
            try
            {
                ValidateStoryModeClanNameSubmission(item.Token, item.Name);
                throw new AgentHostException("native-storymode-clan-name-invalid-accepted", "The Native clan-name adapter accepted an empty token, blank name, or overlong value.");
            }
            catch (AgentHostException exception) when (exception.Code == "native-storymode-clan-name-arguments-invalid") { }
        }
        return [new { scenario = "storymode-clan-name-mailbox-requires-current-token-and-bounded-nonblank-text", passed = true }];
    }

    Task<JsonDocument> IAgentHostCampaignNativeClient.ReadStateAsync(CancellationToken cancellationToken) => ReadStateAsync(cancellationToken);

    public Task<JsonDocument> ExecuteTrainingFieldMenuSelectAsync(string menuId, string optionId, CancellationToken cancellationToken)
    {
        if (menuId != AgentHostStoryModeBootstrapLoop.TrainingFieldMenuId ||
            optionId is not ("training_field_enter" or AgentHostStoryModeBootstrapLoop.TrainingFieldLeaveOptionId))
            throw new AgentHostException("native-training-field-menu-option-invalid", "The StoryMode bootstrap can select only a currently observed original training-field menu option.");
        return SendAsync("menuSelect", new JsonObject { ["menuId"] = menuId, ["optionId"] = optionId }, acceptedResponseExpected: false, cancellationToken);
    }

    public Task<JsonDocument> ReadQuestDetailsAsync(string questId, CancellationToken cancellationToken)
    {
        return SendAsync("questDetails", BuildQuestDetailsArguments(questId), acceptedResponseExpected: false, cancellationToken);
    }

    public Task<JsonDocument> ExecuteCaptivityRecoveryActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
    {
        if (action == "resume" && arguments.Count == 0)
            return SendAsync("resume", arguments, acceptedResponseExpected: false, cancellationToken);
        if (action == "menuSelect" && arguments.Count == 2 &&
            arguments["menuId"] is JsonValue menuIdNode && menuIdNode.TryGetValue<string>(out var menuId) && !string.IsNullOrWhiteSpace(menuId) &&
            arguments["optionId"] is JsonValue optionIdNode && optionIdNode.TryGetValue<string>(out var optionId) && !string.IsNullOrWhiteSpace(optionId))
            return SendAsync("menuSelect", arguments, acceptedResponseExpected: false, cancellationToken);
        throw new AgentHostException("native-action-not-in-captivity-recovery-scope", "Only explicit Native resume or a current menuSelect can be sent through the Captivity recovery adapter.");
    }

    public Task<JsonDocument> ExecuteGoldSaleActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
    {
        ValidateGoldSaleAction(action, arguments);
        return SendAsync(action, arguments, acceptedResponseExpected: action == "tradeConfirm", cancellationToken);
    }

    public Task<JsonDocument> ExecuteRecruitmentActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
    {
        ValidateRecruitmentAction(action, arguments);
        return SendAsync(action, arguments, acceptedResponseExpected: false, cancellationToken);
    }

    public Task<JsonDocument> ExecuteCompanionHiringActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
    {
        ValidateCompanionHiringAction(action, arguments);
        return SendAsync(action, arguments, acceptedResponseExpected: false, cancellationToken);
    }

    internal static void ValidateCompanionHiringAction(string action, JsonObject arguments)
    {
        static bool HasText(JsonObject value, string key) => value[key] is JsonValue node && node.TryGetValue<string>(out var text) && !string.IsNullOrWhiteSpace(text);
        static bool IsIndex(JsonObject value, string key) => value[key] is JsonValue node && node.TryGetValue<int>(out var index) && index >= 0;
        static bool HasOnlyKeys(JsonObject value, params string[] keys) => value.Count == keys.Length && keys.All(value.ContainsKey);
        var valid = action switch
        {
            "missionSceneAgents" or "missionLeave" or "dialogueContinue" or "continueSceneNotification" => arguments.Count == 0,
            "menuSelect" => HasOnlyKeys(arguments, "menuId", "optionId") && HasText(arguments, "menuId") && HasText(arguments, "optionId"),
            "missionNavigateToAgent" => (arguments.Count == 1 || arguments.Count == 2) && IsIndex(arguments, "agentIndex") &&
                (!arguments.ContainsKey("durationSeconds") || arguments["durationSeconds"] is JsonValue durationNode && durationNode.TryGetValue<int>(out var duration) && duration is >= 1 and <= 20),
            "missionInteract" => HasOnlyKeys(arguments, "agentIndex") && IsIndex(arguments, "agentIndex"),
            "dialogueSelect" => HasOnlyKeys(arguments, "optionId") && HasText(arguments, "optionId"),
            _ => false
        };
        if (!valid)
            throw new AgentHostException("native-action-not-in-companion-hiring-scope", "The companion adapter accepts only observed Town/Tavern entry, local scene perception/navigation/interact, and current Native dialogue/leave actions.");
    }

    internal static IReadOnlyList<object> RunCompanionHiringActionContractSelfTests()
    {
        var valid = new (string Action, string Json)[]
        {
            ("menuSelect", "{\"menuId\":\"town_backstreet\",\"optionId\":\"town_tavern\"}"),
            ("missionSceneAgents", "{}"),
            ("missionNavigateToAgent", "{\"agentIndex\":4,\"durationSeconds\":8}"),
            ("missionInteract", "{\"agentIndex\":4}"),
            ("dialogueSelect", "{\"optionId\":\"player_companion_hire_response_1\"}"),
            ("dialogueContinue", "{}"),
            ("missionLeave", "{}")
        };
        foreach (var item in valid) ValidateCompanionHiringAction(item.Action, JsonNode.Parse(item.Json)!.AsObject());
        foreach (var item in new (string Action, string Json)[]
        {
            ("missionSceneAgents", "{\"heroId\":\"unobserved\"}"),
            ("missionNavigateToAgent", "{\"agentIndex\":-1}"),
            ("missionNavigateToAgent", "{\"agentIndex\":4,\"durationSeconds\":21}"),
            ("missionInteract", "{\"agentIndex\":4,\"heroId\":\"unobserved\"}"),
            ("dialogueSelect", "{\"optionId\":\"\"}"),
            ("missionLeave", "{\"forceEndMission\":true}")
        })
        {
            try
            {
                ValidateCompanionHiringAction(item.Action, JsonNode.Parse(item.Json)!.AsObject());
                throw new AgentHostException("native-companion-invalid-action-accepted", "The companion adapter accepted a hidden target, invalid navigation duration or extra argument.");
            }
            catch (AgentHostException exception) when (exception.Code == "native-action-not-in-companion-hiring-scope") { }
        }
        return [new { scenario = "native-companion-adapter-is-limited-to-observed-current-settlement-mission-and-dialogue-actions", validCases = valid.Length, invalidCases = 6, passed = true }];
    }

    internal static void ValidateRecruitmentAction(string action, JsonObject arguments)
    {
        // Dialogue is admitted only as a transport shape here; PartySize's current
        // VillagersInNeed catalog binds it to the exact active quest, hero and option.
        static bool HasText(JsonObject value, string key) => value[key] is JsonValue node && node.TryGetValue<string>(out var text) && !string.IsNullOrWhiteSpace(text);
        static bool HasSha256(JsonObject value, string key) => value[key] is JsonValue node && node.TryGetValue<string>(out var hash) &&
            hash.Length == 64 && hash.All(character => character is >= '0' and <= '9' or >= 'a' and <= 'f');
        var valid = action switch
        {
            "recruitOptions" => arguments.Count == 0,
            "prisonerRecruitmentOptions" => arguments.Count == 0,
            "menuSelect" => arguments.Count == 2 && HasText(arguments, "menuId") && HasText(arguments, "optionId"),
            "recruit" => arguments.Count == 4 && HasText(arguments, "ownerId") && HasText(arguments, "troopId") &&
                         arguments["slot"] is JsonValue slotNode && slotNode.TryGetValue<int>(out var slot) && slot >= 0 &&
                         arguments["confirmPartySizeWarning"] is JsonValue confirmNode && confirmNode.TryGetValue<int>(out var confirm) && confirm is 0 or 1,
            "recruitAll" => arguments.Count == 6 &&
                            arguments["expectedCount"] is JsonValue countNode && countNode.TryGetValue<int>(out var count) && count >= 2 &&
                            arguments["expectedTotalCost"] is JsonValue totalCostNode && totalCostNode.TryGetValue<int>(out var totalCost) && totalCost >= 0 &&
                            arguments["expectedPartySize"] is JsonValue partySizeNode && partySizeNode.TryGetValue<int>(out var partySize) && partySize >= 0 &&
                            arguments["expectedPartyCapacity"] is JsonValue partyCapacityNode && partyCapacityNode.TryGetValue<int>(out var partyCapacity) && partyCapacity >= partySize &&
                            arguments["expectedJournalTarget"] is JsonValue journalTargetNode && journalTargetNode.TryGetValue<int>(out var journalTarget) && journalTarget >= partySize + count &&
                            HasSha256(arguments, "expectedOfferSetSha256"),
            "recruitPrisoner" => arguments.Count == 3 && HasText(arguments, "troopId") &&
                                  arguments["confirmPartySizeWarning"] is JsonValue prisonerPartyConfirmNode && prisonerPartyConfirmNode.TryGetValue<int>(out var prisonerPartyConfirm) && prisonerPartyConfirm is 0 or 1 &&
                                  arguments["confirmPrisonerLimitWarning"] is JsonValue prisonerLimitConfirmNode && prisonerLimitConfirmNode.TryGetValue<int>(out var prisonerLimitConfirm) && prisonerLimitConfirm is 0 or 1,
            "dialogueContinue" => arguments.Count == 0,
            "dialogueSelect" => arguments.Count == 1 && HasText(arguments, "optionId"),
            _ => false
        };
        if (!valid)
            throw new AgentHostException("native-action-not-in-recruitment-scope", "The recruitment adapter accepts only fresh volunteer/prisoner option queries, exact current offers, and their separate Native troop-size or prisoner-limit confirmation choices.");
    }

    internal static IReadOnlyList<object> RunRecruitmentActionContractSelfTests()
    {
        ValidateRecruitmentAction("recruitOptions", new JsonObject());
        ValidateRecruitmentAction("prisonerRecruitmentOptions", new JsonObject());
        ValidateRecruitmentAction("menuSelect", JsonNode.Parse("{\"menuId\":\"village\",\"optionId\":\"leave\"}")!.AsObject());
        ValidateRecruitmentAction("recruit", JsonNode.Parse("{\"ownerId\":\"notable-a\",\"troopId\":\"vlandian_recruit\",\"slot\":0,\"confirmPartySizeWarning\":0}")!.AsObject());
        ValidateRecruitmentAction("recruitAll", JsonNode.Parse("{\"expectedCount\":2,\"expectedTotalCost\":40,\"expectedPartySize\":1,\"expectedPartyCapacity\":20,\"expectedJournalTarget\":5,\"expectedOfferSetSha256\":\"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\"}")!.AsObject());
        ValidateRecruitmentAction("recruitPrisoner", JsonNode.Parse("{\"troopId\":\"looter\",\"confirmPartySizeWarning\":0,\"confirmPrisonerLimitWarning\":0}")!.AsObject());
        ValidateRecruitmentAction("dialogueContinue", new JsonObject());
        ValidateRecruitmentAction("dialogueSelect", JsonNode.Parse("{\"optionId\":\"villagers_defer\"}")!.AsObject());
        foreach (var item in new (string Action, string Json)[]
        {
            ("recruitOptions", "{\"slot\":0}"),
            ("recruit", "{\"ownerId\":\"notable-a\",\"troopId\":\"vlandian_recruit\",\"slot\":-1,\"confirmPartySizeWarning\":0}"),
            ("recruit", "{\"ownerId\":\"notable-a\",\"troopId\":\"vlandian_recruit\",\"slot\":0,\"confirmPartySizeWarning\":2}"),
            ("recruit", "{\"ownerId\":\"notable-a\",\"troopId\":\"vlandian_recruit\",\"slot\":0,\"confirmPartySizeWarning\":0,\"extra\":true}"),
            ("recruitAll", "{\"expectedCount\":1,\"expectedTotalCost\":20,\"expectedPartySize\":1,\"expectedPartyCapacity\":20,\"expectedJournalTarget\":5,\"expectedOfferSetSha256\":\"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\"}"),
            ("recruitAll", "{\"expectedCount\":2,\"expectedTotalCost\":40,\"expectedPartySize\":1,\"expectedPartyCapacity\":20,\"expectedJournalTarget\":2,\"expectedOfferSetSha256\":\"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\"}"),
            ("recruitAll", "{\"expectedCount\":2,\"expectedTotalCost\":40,\"expectedPartySize\":1,\"expectedPartyCapacity\":20,\"expectedJournalTarget\":5,\"expectedOfferSetSha256\":\"stale\"}"),
            ("recruitPrisoner", "{\"troopId\":\"looter\",\"confirmPartySizeWarning\":0,\"confirmPrisonerLimitWarning\":2}"),
            ("recruitPrisoner", "{\"troopId\":\"looter\",\"confirmPartySizeWarning\":0}"),
            ("dialogueContinue", "{\"optionId\":\"villagers_defer\"}"),
            ("dialogueSelect", "{\"optionId\":\"villagers_defer\",\"extra\":true}")
        })
        {
            try
            {
                ValidateRecruitmentAction(item.Action, JsonNode.Parse(item.Json)!.AsObject());
                throw new AgentHostException("native-recruitment-invalid-action-accepted", "The recruitment transport accepted a malformed slot, extra argument, or invalid capacity-warning confirmation.");
            }
            catch (AgentHostException exception) when (exception.Code == "native-action-not-in-recruitment-scope") { }
        }
        return [new { scenario = "native-recruitment-mailbox-allows-quest-dialogue-current-offers-and-bounded-recruit-all", validCases = 8, invalidCases = 11, passed = true }];
    }

    internal static void ValidateGoldSaleAction(string action, JsonObject arguments)
    {
        static bool HasOnlyKeys(JsonObject value, params string[] keys) => value.Count == keys.Length && keys.All(value.ContainsKey);
        static bool HasText(JsonObject value, string key) => value[key] is JsonValue node && node.TryGetValue<string>(out var text) && !string.IsNullOrWhiteSpace(text);

        var valid = action switch
        {
            "mapSettlementTargets" or "tradeOptions" or "tradeConfirm" or "tradeCancel" or "tradeCancelChanges" => arguments.Count == 0,
            "move" => HasOnlyKeys(arguments, "settlementId") && HasText(arguments, "settlementId"),
            "dialogueContinue" => arguments.Count == 0,
            "dialogueSelect" => HasOnlyKeys(arguments, "optionId") && HasText(arguments, "optionId"),
            "menuSelect" => HasOnlyKeys(arguments, "menuId", "optionId") && HasText(arguments, "menuId") && HasText(arguments, "optionId"),
            "trade" => HasOnlyKeys(arguments, "direction", "itemViewModelId", "inventorySide", "amount") &&
                arguments["direction"] is JsonValue directionNode && directionNode.TryGetValue<string>(out var direction) && direction == "sell" &&
                arguments["inventorySide"] is JsonValue sideNode && sideNode.TryGetValue<string>(out var side) && side == "PlayerInventory" &&
                HasText(arguments, "itemViewModelId") && arguments["amount"] is JsonValue amountNode && amountNode.TryGetValue<int>(out var amount) && amount == 1,
            "sellPrisonerOne" => HasOnlyKeys(arguments, "troopId") && HasText(arguments, "troopId"),
            "partyScreenCancel" => arguments.Count == 0,
            "partyScreenDone" => arguments.Count == 0,
            _ => false
        };
        if (!valid) throw new AgentHostException("native-action-not-in-gold-sale-scope", "The W7-P Native adapter allows safe movement, current Town trade, one exact Goods or Ransom-prisoner sale, Native PartyScreen Done, transaction confirmation, or explicit cancellation.");
    }

    internal static IReadOnlyList<object> RunGoldSaleActionContractSelfTests()
    {
        var validCases = new (string Action, string Json)[]
        {
            ("mapSettlementTargets", "{}"),
            ("move", "{\"settlementId\":\"visible-safe-town\"}"),
            ("dialogueContinue", "{}"),
            ("dialogueSelect", "{\"optionId\":\"current-visible-option\"}"),
            ("menuSelect", "{\"menuId\":\"town\",\"optionId\":\"trade\"}"),
            ("tradeOptions", "{}"),
            ("trade", "{\"direction\":\"sell\",\"itemViewModelId\":\"current-goods-id\",\"inventorySide\":\"PlayerInventory\",\"amount\":1}"),
            ("sellPrisonerOne", "{\"troopId\":\"mounted_ransacker\"}"),
            ("partyScreenCancel", "{}"),
            ("partyScreenDone", "{}"),
            ("tradeConfirm", "{}"),
            ("tradeCancel", "{}"),
            ("tradeCancelChanges", "{}")
        };
        foreach (var item in validCases) ValidateGoldSaleAction(item.Action, JsonNode.Parse(item.Json)!.AsObject());

        var invalidCases = new (string Action, string Json)[]
        {
            ("pause", "{}"),
            ("dialogueSelect", "{\"optionId\":\"unobserved\",\"force\":true}"),
            ("trade", "{\"direction\":\"buy\",\"itemViewModelId\":\"market-goods\",\"inventorySide\":\"OtherInventory\",\"amount\":1}"),
            ("trade", "{\"direction\":\"sell\",\"itemViewModelId\":\"current-goods-id\",\"inventorySide\":\"PlayerInventory\",\"amount\":2}"),
            ("trade", "{\"direction\":\"sell\",\"itemViewModelId\":\"current-goods-id\",\"inventorySide\":\"OtherInventory\",\"amount\":1}"),
            ("sellPrisonerOne", "{\"troopId\":\"mounted_ransacker\",\"count\":7}"),
            ("partyScreenCancel", "{\"confirm\":true}"),
            ("move", "{\"settlementId\":\"visible-safe-town\",\"resume\":true}")
        };
        foreach (var item in invalidCases)
        {
            try
            {
                ValidateGoldSaleAction(item.Action, JsonNode.Parse(item.Json)!.AsObject());
                throw new AgentHostException("native-gold-sale-invalid-action-accepted", "The Gold sale mailbox accepted a buy, bulk quantity, wrong inventory side, or clock action.");
            }
            catch (AgentHostException exception) when (exception.Code == "native-action-not-in-gold-sale-scope") { }
        }
        return [new { scenario = "gold-sale-native-mailbox-allows-only-one-current-player-inventory-sale-and-no-clock-controls", validCases = validCases.Length, invalidCases = invalidCases.Length, passed = true }];
    }

    internal static async Task<IReadOnlyList<object>> RunGoldSaleAcceptedResponseTransportSelfTestsAsync()
    {
        var root = Path.Combine(Path.GetTempPath(), "ChronicleGoldSaleAcceptedMailbox-" + Guid.NewGuid().ToString("N"));
        using var cancellation = new CancellationTokenSource(TimeSpan.FromSeconds(3));
        Task<JsonDocument>? pendingCommand = null;
        try
        {
            var responses = Path.Combine(root, "responses");
            Directory.CreateDirectory(responses);
            var client = new NativeMailboxClient(root, TimeSpan.FromSeconds(2));
            pendingCommand = client.ExecuteGoldSaleActionAsync("tradeConfirm", new JsonObject(), cancellation.Token);
            var commandPath = Path.Combine(root, "command.json");
            JsonObject? command = null;
            for (var attempt = 0; attempt < 100 && command is null; attempt++)
            {
                if (File.Exists(commandPath))
                {
                    try { command = JsonNode.Parse(await File.ReadAllTextAsync(commandPath)) as JsonObject; }
                    catch (IOException) { }
                    catch (JsonException) { }
                }
                if (command is null) await Task.Delay(10);
            }
            var commandId = command?["id"]?.GetValue<string>();
            if (string.IsNullOrWhiteSpace(commandId) || command?["action"]?.GetValue<string>() != "tradeConfirm")
                throw new AgentHostException("gold-sale-accepted-mailbox-command-missing", "The Native Trade confirm transport did not publish its correlated command.");
            var accepted = new JsonObject
            {
                ["protocolVersion"] = 1,
                ["commandId"] = commandId,
                ["action"] = "tradeConfirm",
                ["status"] = "accepted"
            };
            await File.WriteAllTextAsync(Path.Combine(responses, commandId + ".accepted.json"), accepted.ToJsonString());
            using var response = await pendingCommand;
            if (response.RootElement.GetProperty("status").GetString() != "accepted")
                throw new AgentHostException("gold-sale-accepted-mailbox-response-lost", "The Native Trade confirm transport did not return the correlated accepted Inquiry response.");
            return [new { scenario = "gold-sale-trade-confirm-returns-native-accepted-inquiry-before-commit", passed = true }];
        }
        finally
        {
            cancellation.Cancel();
            if (pendingCommand is { IsCompleted: false })
            {
                try { using var ignored = await pendingCommand; }
                catch (OperationCanceledException) { }
                catch (AgentHostException) { }
            }
            if (Directory.Exists(root)) Directory.Delete(root, recursive: true);
        }
    }

    internal static async Task<IReadOnlyList<object>> RunBattleDoneAcceptedResponseTransportSelfTestsAsync()
    {
        var root = Path.Combine(Path.GetTempPath(), "ChronicleBattleDoneAcceptedMailbox-" + Guid.NewGuid().ToString("N"));
        using var cancellation = new CancellationTokenSource(TimeSpan.FromSeconds(3));
        Task<JsonDocument>? pendingCommand = null;
        try
        {
            var responses = Path.Combine(root, "responses");
            Directory.CreateDirectory(responses);
            var client = new NativeMailboxClient(root, TimeSpan.FromSeconds(2));
            pendingCommand = client.ExecuteBattleSimulationActionAsync("partyScreenDone", new JsonObject(), cancellation.Token);
            var commandPath = Path.Combine(root, "command.json");
            JsonObject? command = null;
            for (var attempt = 0; attempt < 100 && command is null; attempt++)
            {
                if (File.Exists(commandPath))
                {
                    try { command = JsonNode.Parse(await File.ReadAllTextAsync(commandPath)) as JsonObject; }
                    catch (IOException) { }
                    catch (JsonException) { }
                }
                if (command is null) await Task.Delay(10);
            }
            var commandId = command?["id"]?.GetValue<string>();
            if (string.IsNullOrWhiteSpace(commandId) || command?["action"]?.GetValue<string>() != "partyScreenDone")
                throw new AgentHostException("battle-done-accepted-mailbox-command-missing", "The Native PartyScreen Done transport did not publish its correlated command.");
            var accepted = new JsonObject
            {
                ["protocolVersion"] = 1,
                ["commandId"] = commandId,
                ["action"] = "partyScreenDone",
                ["status"] = "accepted"
            };
            await File.WriteAllTextAsync(Path.Combine(responses, commandId + ".accepted.json"), accepted.ToJsonString());
            using var response = await pendingCommand;
            if (response.RootElement.GetProperty("status").GetString() != "accepted")
                throw new AgentHostException("battle-done-accepted-mailbox-response-lost", "Native PartyScreen Done must return its current accepted Inquiry without waiting for completion.");
            return [new { scenario = "battle-party-done-returns-native-leftover-inquiry-before-final-choice", passed = true }];
        }
        finally
        {
            cancellation.Cancel();
            if (pendingCommand is { IsCompleted: false })
            {
                try { using var ignored = await pendingCommand; }
                catch (OperationCanceledException) { }
                catch (AgentHostException) { }
            }
            if (Directory.Exists(root)) Directory.Delete(root, recursive: true);
        }
    }

    internal static JsonObject BuildQuestDetailsArguments(string questId)
    {
        if (string.IsNullOrWhiteSpace(questId) || questId.Length > 160)
            throw new AgentHostException("native-quest-details-id-invalid", "The read-only Quest Journal query requires one bounded observed quest id.");
        return new JsonObject { ["questId"] = questId };
    }

    internal static IReadOnlyList<object> RunQuestDetailsReadActionContractSelfTests()
    {
        var arguments = BuildQuestDetailsArguments("rebuild_player_clan_storymode_quest");
        if (arguments.Count != 1 || arguments["questId"]?.GetValue<string>() != "rebuild_player_clan_storymode_quest")
            throw new AgentHostException("native-quest-details-read-contract-failed", "The read-only Quest Journal adapter must serialize only its single observed quest id.");
        foreach (var invalid in new[] { "", " ", new string('x', 161) })
        {
            try
            {
                _ = BuildQuestDetailsArguments(invalid);
                throw new AgentHostException("native-quest-details-invalid-id-accepted", "The read-only Quest Journal adapter accepted a blank or oversized id.");
            }
            catch (AgentHostException exception) when (exception.Code == "native-quest-details-id-invalid") { }
        }
        return [new { scenario = "native-quest-details-is-an-explicit-read-only-adapter-with-one-bounded-id", passed = true }];
    }

    public Task<JsonDocument> ExecuteSupplyActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
    {
        if (!SupplySliceActions.Contains(action) || action == "state")
            throw new AgentHostException("native-action-not-in-supply-scope", "The Agent Host action is outside the approved Native supply slice.");
        return SendAsync(action, arguments, acceptedResponseExpected: action == "rest", cancellationToken);
    }

    internal Task<JsonDocument> ExecuteCampaignActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
    {
        switch (action)
        {
            case "mapSettlementTargets" when arguments.Count == 0:
            case "continueSceneNotification" when arguments.Count == 0:
                break;
            case "incidentSelect" when arguments.Count == 1 &&
                                          arguments.TryGetPropertyValue("optionIndex", out var incidentOptionNode) &&
                                          incidentOptionNode is JsonValue incidentOptionValue &&
                                          incidentOptionValue.TryGetValue<int>(out var incidentOptionIndex) && incidentOptionIndex >= 0:
                break;
            case "move" when arguments.Count == 1 &&
                              arguments.TryGetPropertyValue("settlementId", out var settlementIdNode) &&
                              settlementIdNode is JsonValue settlementIdValue &&
                              settlementIdValue.TryGetValue<string>(out var settlementId) &&
                              !string.IsNullOrWhiteSpace(settlementId):
                break;
            case "mapSettlementTargets":
                throw new AgentHostException("native-map-target-arguments-invalid", "mapSettlementTargets does not accept arguments.");
            case "incidentSelect":
                throw new AgentHostException("native-map-incident-arguments-invalid", "incidentSelect requires only a non-negative optionIndex from the current Native mapIncident observation.");
            case "move":
                throw new AgentHostException("native-move-arguments-invalid", "move requires only a non-empty observed settlementId.");
            default:
                throw new AgentHostException("native-action-not-in-campaign-loop-scope", "The Agent Host action is outside the current Campaign loop scope.");
        }

        return SendAsync(action, arguments, acceptedResponseExpected: false, cancellationToken);
    }

    Task<JsonDocument> IAgentHostCampaignNativeClient.ExecuteCampaignActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken) =>
        ExecuteCampaignActionAsync(action, arguments, cancellationToken);

    public Task<JsonDocument> ExecuteQuestTroopScreenActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
    {
        ValidateQuestTroopScreenAction(action, arguments);
        return SendAsync(action, arguments, acceptedResponseExpected: false, cancellationToken);
    }

    internal static void ValidateQuestTroopScreenAction(string action, JsonObject arguments)
    {
        static bool HasOnlyKeys(JsonObject value, params string[] keys) => value.Count == keys.Length && keys.All(value.ContainsKey);
        static bool HasText(JsonObject value, string key) => value[key] is JsonValue node && node.TryGetValue<string>(out var text) && !string.IsNullOrWhiteSpace(text);
        var valid = action switch
        {
            "questTroopTransfer" => HasOnlyKeys(arguments, "troopId", "sourceSide") && HasText(arguments, "troopId") &&
                arguments["sourceSide"] is JsonValue sideNode && sideNode.TryGetValue<string>(out var side) && side is "mainParty" or "quest",
            "questTroopScreenDone" or "questTroopScreenCancel" => arguments.Count == 0,
            _ => false
        };
        if (!valid)
            throw new AgentHostException("native-action-not-in-quest-troop-screen-scope", "QuestTroopManage accepts only one exact troop/side transfer, Native Done when enabled, or Native Cancel when enabled.");
    }

    internal static IReadOnlyList<object> RunQuestTroopScreenActionContractSelfTests()
    {
        ValidateQuestTroopScreenAction("questTroopTransfer", JsonNode.Parse("{\"troopId\":\"imperial_recruit\",\"sourceSide\":\"mainParty\"}")!.AsObject());
        ValidateQuestTroopScreenAction("questTroopTransfer", JsonNode.Parse("{\"troopId\":\"imperial_recruit\",\"sourceSide\":\"quest\"}")!.AsObject());
        ValidateQuestTroopScreenAction("questTroopScreenDone", new JsonObject());
        ValidateQuestTroopScreenAction("questTroopScreenCancel", new JsonObject());
        foreach (var item in new[]
        {
            (Action: "questTroopTransfer", Json: "{\"troopId\":\"\",\"sourceSide\":\"mainParty\"}"),
            (Action: "questTroopTransfer", Json: "{\"troopId\":\"hero\",\"sourceSide\":\"left\"}"),
            (Action: "questTroopTransfer", Json: "{\"troopId\":\"troop\",\"sourceSide\":\"hidden\"}"),
            (Action: "questTroopScreenDone", Json: "{\"choice\":\"yes\"}"),
            (Action: "questTroopScreenCancel", Json: "{\"force\":true}")
        })
        {
            try
            {
                ValidateQuestTroopScreenAction(item.Action, JsonNode.Parse(item.Json)!.AsObject());
                throw new AgentHostException("native-quest-troop-screen-invalid-action-accepted", "The QuestTroopManage mailbox accepted an unknown side, hidden target or extra argument.");
            }
            catch (AgentHostException exception) when (exception.Code == "native-action-not-in-quest-troop-screen-scope") { }
        }
        return [new { scenario = "quest-troop-screen-mailbox-is-limited-to-observed-side-and-current-native-controls", passed = true }];
    }

    public Task<JsonDocument> ExecuteTrainingIssueActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
    {
        ValidateTrainingIssueAction(action, arguments);
        return SendAsync(action, arguments, acceptedResponseExpected: false, cancellationToken);
    }

    internal static void ValidateTrainingIssueAction(string action, JsonObject arguments)
    {
        static bool HasOnlyKeys(JsonObject value, params string[] keys) =>
            value.Count == keys.Length && keys.All(value.ContainsKey);
        static bool HasText(JsonObject value, string key) =>
            value[key] is JsonValue node && node.TryGetValue<string>(out var text) && !string.IsNullOrWhiteSpace(text);

        var valid = action switch
        {
            "mapSettlementTargets" or "dialogueContinue" => arguments.Count == 0,
            "move" => HasOnlyKeys(arguments, "settlementId") && HasText(arguments, "settlementId"),
            "menuSelect" => HasOnlyKeys(arguments, "menuId", "optionId") && HasText(arguments, "menuId") && HasText(arguments, "optionId"),
            "talkToSettlementHero" => HasOnlyKeys(arguments, "heroId") && HasText(arguments, "heroId"),
            "dialogueSelect" => HasOnlyKeys(arguments, "optionId") && HasText(arguments, "optionId"),
            "partyUpgradeOptions" => arguments.Count == 0,
            "upgradeTroop" => HasOnlyKeys(arguments, "troopId", "upgradeTargetIndex") && HasText(arguments, "troopId") &&
                arguments["upgradeTargetIndex"] is JsonValue targetNode && targetNode.TryGetValue<int>(out var targetIndex) && targetIndex >= 0,
            _ => false
        };
        if (!valid)
            throw new AgentHostException("native-training-issue-arguments-invalid", "The training-issue adapter accepts only a fresh Native PartyVM upgrade-options read or one current troop/upgrade-target selection.");
    }

    internal static IReadOnlyList<object> RunTrainingIssueActionContractSelfTests()
    {
        ValidateTrainingIssueAction("mapSettlementTargets", new JsonObject());
        ValidateTrainingIssueAction("move", JsonNode.Parse("{\"settlementId\":\"village-a\"}")!.AsObject());
        ValidateTrainingIssueAction("menuSelect", JsonNode.Parse("{\"menuId\":\"village\",\"optionId\":\"leave\"}")!.AsObject());
        ValidateTrainingIssueAction("talkToSettlementHero", JsonNode.Parse("{\"heroId\":\"hero-training\"}")!.AsObject());
        ValidateTrainingIssueAction("dialogueSelect", JsonNode.Parse("{\"optionId\":\"issue_offer_player_accept_quest\"}")!.AsObject());
        ValidateTrainingIssueAction("dialogueContinue", new JsonObject());
        ValidateTrainingIssueAction("partyUpgradeOptions", new JsonObject());
        ValidateTrainingIssueAction("upgradeTroop", JsonNode.Parse("{\"troopId\":\"borrowed_troop\",\"upgradeTargetIndex\":0}")!.AsObject());
        foreach (var item in new (string Action, string Json)[]
        {
            ("partyUpgradeOptions", "{\"troopId\":\"borrowed_troop\"}"),
            ("upgradeTroop", "{\"troopId\":\"\",\"upgradeTargetIndex\":0}"),
            ("upgradeTroop", "{\"troopId\":\"borrowed_troop\",\"upgradeTargetIndex\":-1}"),
            ("upgradeTroop", "{\"troopId\":\"borrowed_troop\",\"upgradeTargetIndex\":0,\"amount\":20}"),
            ("recruit", "{}")
        })
        {
            try
            {
                ValidateTrainingIssueAction(item.Action, JsonNode.Parse(item.Json)!.AsObject());
                throw new AgentHostException("native-training-issue-contract-self-test-invalid-accepted", "A malformed or unrelated action passed the bounded training-issue upgrade transport.");
            }
            catch (AgentHostException exception) when (exception.Code == "native-training-issue-arguments-invalid") { }
        }
        return [new { scenario = "training-issue-mailbox-allows-current-overlay-dialogue-party-upgrade-and-single-upgrade-shapes", validCases = 8, invalidCases = 5, passed = true }];
    }

    public Task<JsonDocument> ExecuteVillageToolsQuestActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
    {
        // This is only the transport's closed action/argument boundary. The quest loop must still
        // construct its per-decision catalog from fresh Native observations and bind every ID to it.
        ValidateVillageToolsQuestAction(action, arguments);
        return SendAsync(action, arguments, acceptedResponseExpected: false, cancellationToken);
    }

    public Task<JsonDocument> ExecuteBattleSimulationActionAsync(string action, JsonObject arguments, CancellationToken cancellationToken)
    {
        ValidateBattleSimulationAction(action, arguments);
        return SendAsync(action, arguments, acceptedResponseExpected: action == "partyScreenDone", cancellationToken);
    }

    public Task<JsonDocument> ReadBattleMissionStatusAsync(CancellationToken cancellationToken) =>
        SendAsync("battleMissionStatus", new JsonObject(), acceptedResponseExpected: false, cancellationToken);

    public Task<JsonDocument> AutoDeployBattleMissionAsync(CancellationToken cancellationToken) =>
        SendAsync("missionAutoDeploy", new JsonObject(), acceptedResponseExpected: false, cancellationToken);

    public Task<JsonDocument> FinishBattleMissionDeploymentAsync(CancellationToken cancellationToken) =>
        SendAsync("missionFinishDeployment", new JsonObject(), acceptedResponseExpected: false, cancellationToken);

    public Task<JsonDocument> DelegateBattleMissionTroopsAsync(CancellationToken cancellationToken) =>
        SendAsync("missionDelegateTroops", new JsonObject(), acceptedResponseExpected: false, cancellationToken);

    public Task<JsonDocument> AutopilotMainAgentBattleMissionAsync(CancellationToken cancellationToken) =>
        SendAsync("missionAutopilotMainAgent", new JsonObject(), acceptedResponseExpected: false, cancellationToken);

    public Task<JsonDocument> ExitEndedBattleMissionAsync(CancellationToken cancellationToken) =>
        SendAsync("missionRetreat", new JsonObject(), acceptedResponseExpected: false, cancellationToken);

    public Task<JsonDocument> PauseForVisibleHostileDecisionAsync(CancellationToken cancellationToken) =>
        SendAsync("pause", new JsonObject(), acceptedResponseExpected: false, cancellationToken);

    internal static void ValidateBattleSimulationAction(string action, JsonObject arguments)
    {
        if (!BattleSimulationActions.Contains(action))
            throw new AgentHostException("native-action-not-in-battle-simulation-scope", "The action is outside the bounded Native Campaign BattleSimulation scope.");

        static bool HasOnlyKeys(JsonObject value, params string[] keys) =>
            value.Count == keys.Length && keys.All(value.ContainsKey);
        static bool HasText(JsonObject value, string key) =>
            value[key] is JsonValue node && node.TryGetValue<string>(out var text) && !string.IsNullOrWhiteSpace(text);

        var valid = action switch
        {
            "mapPartyTargets" or "dialogueContinue" or "battleSkip" or "battleFinish" or "partyScreenDone" or "inventoryTakeAll" or "inventoryDone" => arguments.Count == 0,
            "pursue" => HasOnlyKeys(arguments, "partyId") && HasText(arguments, "partyId"),
            "dialogueSelect" => HasOnlyKeys(arguments, "optionId") && HasText(arguments, "optionId"),
            "menuSelect" => HasOnlyKeys(arguments, "menuId", "optionId") && HasText(arguments, "menuId") && HasText(arguments, "optionId"),
            "partyTakeAll" => HasOnlyKeys(arguments, "troopType") && arguments["troopType"] is JsonValue troopTypeNode && troopTypeNode.TryGetValue<string>(out var troopType) && troopType is "members" or "prisoners",
            "partyLootTransferOne" => HasOnlyKeys(arguments, "troopId", "troopType") && HasText(arguments, "troopId") && arguments["troopType"] is JsonValue lootTroopTypeNode && lootTroopTypeNode.TryGetValue<string>(out var lootTroopType) && lootTroopType is "members" or "prisoners",
            _ => false
        };
        if (!valid)
            throw new AgentHostException("native-battle-simulation-arguments-invalid", $"The Native '{action}' arguments do not match the bounded BattleSimulation protocol contract.");
    }

    internal static void ValidateVillageToolsQuestAction(string action, JsonObject arguments)
    {
        if (!VillageToolsQuestActions.Contains(action))
            throw new AgentHostException("native-action-not-in-village-tools-scope", "The action is outside the bounded village-tools quest transport scope.");

        static bool HasOnlyKeys(JsonObject value, params string[] keys) =>
            value.Count == keys.Length && keys.All(value.ContainsKey);
        static bool HasText(JsonObject value, string key) =>
            value[key] is JsonValue node && node.TryGetValue<string>(out var text) && !string.IsNullOrWhiteSpace(text);

        var valid = action switch
        {
            "mapSettlementTargets" or "dialogueContinue" or "tradeOptions" or "tradeConfirm" or "tradeCancel" or "tradeCancelChanges" or
            "barterOptions" or "barterAutoBalance" or "barterCancel" or
                "inventoryOpen" or "heroEquipmentOptions" or "inventoryCancel" => arguments.Count == 0,
            "move" => HasOnlyKeys(arguments, "settlementId") && HasText(arguments, "settlementId"),
            "menuSelect" => HasOnlyKeys(arguments, "menuId", "optionId") && HasText(arguments, "menuId") && HasText(arguments, "optionId"),
            "talkToSettlementHero" => HasOnlyKeys(arguments, "heroId") && HasText(arguments, "heroId"),
            "dialogueSelect" => HasOnlyKeys(arguments, "optionId") && HasText(arguments, "optionId"),
            "questDetails" => HasOnlyKeys(arguments, "questId") && HasText(arguments, "questId"),
            "trade" => HasOnlyKeys(arguments, "direction", "itemViewModelId", "inventorySide", "amount") &&
                HasText(arguments, "direction") && HasText(arguments, "itemViewModelId") && HasText(arguments, "inventorySide") &&
                arguments["amount"] is JsonValue amountNode && amountNode.TryGetValue<int>(out var amount) && amount > 0 &&
                arguments["direction"]!.GetValue<string>() is "buy" or "sell",
            "barterOffer" => arguments.Count == 0 ||
                HasOnlyKeys(arguments, "expectedSessionId", "expectedProposalFingerprint") &&
                HasText(arguments, "expectedSessionId") && HasText(arguments, "expectedProposalFingerprint"),
            _ => false
        };

        if (!valid)
            throw new AgentHostException("native-village-tools-arguments-invalid", $"The Native '{action}' arguments do not match the bounded village-tools protocol contract.");
    }

    internal static IReadOnlyList<object> RunVillageToolsQuestActionContractSelfTests()
    {
        var validCases = new (string Action, string Json)[]
        {
            ("mapSettlementTargets", "{}"),
            ("move", "{\"settlementId\":\"village-1\"}"),
            ("menuSelect", "{\"menuId\":\"village\",\"optionId\":\"town_visit\"}"),
            ("talkToSettlementHero", "{\"heroId\":\"hero-1\"}"),
            ("dialogueSelect", "{\"optionId\":\"quest_accept\"}"),
            ("dialogueContinue", "{}"),
            ("questDetails", "{\"questId\":\"quest-1\"}"),
            ("tradeOptions", "{}"),
            ("trade", "{\"direction\":\"buy\",\"itemViewModelId\":\"tools\",\"inventorySide\":\"OtherInventory\",\"amount\":1}"),
            ("tradeConfirm", "{}"),
            ("tradeCancel", "{}"),
            ("tradeCancelChanges", "{}"),
            ("barterOptions", "{}"),
            ("barterAutoBalance", "{}"),
            ("barterOffer", "{}"),
            ("barterOffer", "{\"expectedSessionId\":\"session-1\",\"expectedProposalFingerprint\":\"fingerprint-1\"}"),
            ("barterCancel", "{}"),
            ("inventoryOpen", "{}"),
            ("heroEquipmentOptions", "{}"),
            ("inventoryCancel", "{}")
        };
        foreach (var item in validCases)
        {
            ValidateVillageToolsQuestAction(item.Action, JsonNode.Parse(item.Json)!.AsObject());
        }

        var invalidCases = new (string Action, string Json)[]
        {
            ("pause", "{}"),
            ("move", "{\"settlementId\":\"village-1\",\"pause\":true}"),
            ("talkToSettlementHero", "{\"heroId\":\"\"}"),
            ("trade", "{\"direction\":\"buy\",\"itemViewModelId\":\"tools\",\"inventorySide\":\"OtherInventory\",\"amount\":0}"),
            ("trade", "{\"direction\":\"delete\",\"itemViewModelId\":\"tools\",\"inventorySide\":\"OtherInventory\",\"amount\":1}"),
            ("tradeConfirm", "{\"questId\":\"quest-1\"}"),
            ("barterOffer", "{\"expectedSessionId\":\"session-1\"}"),
            ("inventoryCancelChanges", "{}")
        };
        foreach (var item in invalidCases)
        {
            var arguments = JsonNode.Parse(item.Json)!.AsObject();
            try
            {
                ValidateVillageToolsQuestAction(item.Action, arguments);
                throw new AgentHostException("native-village-tools-contract-self-test-invalid-accepted", "An invalid action, argument, transaction, or clock request passed validation.");
            }
            catch (AgentHostException exception) when (exception.Code is "native-action-not-in-village-tools-scope" or "native-village-tools-arguments-invalid") { }
        }

        return [new { scenario = "village-tools-mailbox-action-contract-allows-only-observed-native-action-shapes-and-no-clock-control", validCases = validCases.Length, invalidCases = invalidCases.Length, passed = true }];
    }

    internal static IReadOnlyList<object> RunBattleSimulationActionContractSelfTests()
    {
        var validCases = new (string Action, string Json)[]
        {
            ("mapPartyTargets", "{}"),
            ("pursue", "{\"partyId\":\"observed-bandit\"}"),
            ("menuSelect", "{\"menuId\":\"encounter\",\"optionId\":\"str_order_attack\"}"),
            ("menuSelect", "{\"menuId\":\"encounter\",\"optionId\":\"surrender\"}"),
            ("battleSkip", "{}"),
            ("battleFinish", "{}"),
            ("partyTakeAll", "{\"troopType\":\"members\"}"),
            ("partyTakeAll", "{\"troopType\":\"prisoners\"}"),
            ("partyLootTransferOne", "{\"troopId\":\"mounted_ransacker\",\"troopType\":\"prisoners\"}"),
            ("partyLootTransferOne", "{\"troopId\":\"caravan_guard_empire\",\"troopType\":\"members\"}"),
            ("partyScreenDone", "{}"),
            ("inventoryTakeAll", "{}"),
            ("inventoryDone", "{}")
        };
        foreach (var item in validCases)
            ValidateBattleSimulationAction(item.Action, JsonNode.Parse(item.Json)!.AsObject());

        var invalidCases = new (string Action, string Json)[]
        {
            ("pause", "{}"),
            ("battleRetreat", "{}"),
            ("menuSelect", "{\"menuId\":\"encounter\"}"),
            ("pursue", "{\"partyId\":\"\"}"),
            ("partyTakeAll", "{\"troopType\":\"companions\"}"),
            ("partyLootTransferOne", "{\"troopId\":\"mounted_ransacker\",\"troopType\":\"looter\"}"),
            ("partyLootTransferOne", "{\"troopType\":\"prisoners\"}"),
            ("inventoryDone", "{\"skipLoot\":true}")
        };
        foreach (var item in invalidCases)
        {
            try
            {
                ValidateBattleSimulationAction(item.Action, JsonNode.Parse(item.Json)!.AsObject());
                throw new AgentHostException("native-battle-simulation-contract-self-test-invalid-accepted", "An invalid action, argument, outcome, or clock request passed validation.");
            }
            catch (AgentHostException exception) when (exception.Code is "native-action-not-in-battle-simulation-scope" or "native-battle-simulation-arguments-invalid") { }
        }
        return [new { scenario = "battle-simulation-mailbox-allows-only-bounded-native-actions-and-no-clock-controls", validCases = validCases.Length, invalidCases = invalidCases.Length, passed = true }];
    }

    private async Task<JsonDocument> SendAsync(
        string action,
        JsonObject arguments,
        bool acceptedResponseExpected,
        CancellationToken cancellationToken)
    {
        var commandId = "host-" + Guid.NewGuid().ToString("N");
        var commandPath = Path.Combine(_root, "command.json");
        var temporaryPath = commandPath + "." + commandId + ".tmp";
        var command = new JsonObject { ["id"] = commandId, ["action"] = action };
        foreach (var property in arguments) command[property.Key] = property.Value?.DeepClone();
        if (_expectedNativeSessionId != null) command["expectedNativeSessionId"] = _expectedNativeSessionId;
        var json = command.ToJsonString();

        await using (var stream = new FileStream(temporaryPath, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
        {
            var bytes = new UTF8Encoding(false).GetBytes(json);
            await stream.WriteAsync(bytes, cancellationToken);
            await stream.FlushAsync(cancellationToken);
            stream.Flush(flushToDisk: true);
        }

        try
        {
            try { File.Move(temporaryPath, commandPath, overwrite: false); }
            catch (IOException exception) when (File.Exists(commandPath))
            {
                throw new AgentHostException("native-mailbox-busy", "Another protocol owner has an unclaimed Native command.", exception);
            }

            var deadline = Stopwatch.GetTimestamp() + (long)(_timeout.TotalSeconds * Stopwatch.Frequency);
            var candidateStatuses = acceptedResponseExpected
                ? new[] { "accepted", "completed", "rejected", "failed" }
                : new[] { "completed", "rejected", "failed" };
            while (Stopwatch.GetTimestamp() < deadline)
            {
                cancellationToken.ThrowIfCancellationRequested();
                foreach (var status in candidateStatuses)
                {
                    var responsePath = Path.Combine(_responseRoot, commandId + "." + status + ".json");
                    if (!File.Exists(responsePath)) continue;
                    var response = await ReadJsonAsync(responsePath, cancellationToken);
                    try { ValidateResponse(response.RootElement, commandId, action, status); }
                    catch { response.Dispose(); throw; }
                    return response;
                }
                await Task.Delay(TimeSpan.FromMilliseconds(100), cancellationToken);
            }

            throw new AgentHostException("native-command-timeout", $"The Native '{action}' command timed out.");
        }
        catch
        {
            RemoveOwnedUnclaimedCommand(commandPath, commandId);
            throw;
        }
        finally
        {
            try { if (File.Exists(temporaryPath)) File.Delete(temporaryPath); }
            catch (IOException) { }
        }
    }

    private static async Task<JsonDocument> ReadJsonAsync(string path, CancellationToken cancellationToken)
    {
        for (var attempt = 0; attempt < 5; attempt++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            try { return JsonDocument.Parse(await File.ReadAllTextAsync(path, cancellationToken)); }
            catch (IOException) when (attempt < 4) { await Task.Delay(TimeSpan.FromMilliseconds(20), cancellationToken); }
            catch (JsonException) when (attempt < 4) { await Task.Delay(TimeSpan.FromMilliseconds(20), cancellationToken); }
        }
        throw new AgentHostException("native-response-unreadable", "A Native mailbox response was not readable as complete JSON.");
    }

    internal void ValidateResponse(JsonElement response, string commandId, string action, string fileStatus)
    {
        if (!response.TryGetProperty("protocolVersion", out var version) || !version.TryGetInt32(out var protocolVersion) || protocolVersion != 1 ||
            !string.Equals(ReadString(response, "commandId"), commandId, StringComparison.Ordinal) ||
            !string.Equals(ReadString(response, "action"), action, StringComparison.Ordinal) ||
            !string.Equals(ReadString(response, "status"), fileStatus, StringComparison.Ordinal))
            throw new AgentHostException("native-response-correlation-invalid", "Native response did not match the Host command and protocol version.");
        if (_expectedProcessId.HasValue && (!response.TryGetProperty("processId", out var processId) ||
            !processId.TryGetInt32(out var receivedProcessId) || receivedProcessId != _expectedProcessId.Value))
            throw new AgentHostException("native-response-process-mismatch", "Native response came from a different Bannerlord process.");
        if (_expectedNativeSessionId != null && !string.Equals(ReadString(response, "nativeSessionId"), _expectedNativeSessionId, StringComparison.Ordinal))
            throw new AgentHostException("native-response-session-mismatch", "Native response came from a different loaded Campaign session.");
    }

    private static string? ReadString(JsonElement element, string name) =>
        element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;

    private static void RemoveOwnedUnclaimedCommand(string commandPath, string commandId)
    {
        try
        {
            if (!File.Exists(commandPath)) return;
            using var command = JsonDocument.Parse(File.ReadAllText(commandPath));
            if (string.Equals(ReadString(command.RootElement, "id"), commandId, StringComparison.Ordinal)) File.Delete(commandPath);
        }
        catch (IOException) { }
        catch (JsonException) { }
    }
}
