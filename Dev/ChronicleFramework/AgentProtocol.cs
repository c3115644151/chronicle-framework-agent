using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.Encounters;
using TaleWorlds.CampaignSystem.GameState;
using TaleWorlds.CampaignSystem.MapEvents;
using TaleWorlds.CampaignSystem.Party;
using TaleWorlds.CampaignSystem.Settlements;
using TaleWorlds.CampaignSystem.ViewModelCollection.GameMenu.Recruitment;
using TaleWorlds.Core;
using TaleWorlds.MountAndBlade;
using EngineTime = TaleWorlds.Engine.Time;

namespace ChronicleFramework;

internal sealed class ChronicleAgentProtocol
{
    private readonly string _root;
    private readonly string _responseRoot;
    private string _lastCommandId;
    private double? _advanceTargetDay;
    private string _advanceCommandId;
    private string _pendingSaveName;
    private string _pendingSaveCommandId;
    private string _pendingClaimedCommandPath;
    private float _nextClaimedCommandReadTime;
    private float _nextClaimedCommandReadLogTime;
    private float _waitForDoubleClickUntilTime;
    private string _restCommandId;
    private double? _restTargetDay;
    private RecruitmentVM _recruitmentViewModel;
    private bool _freshProgressionPollLogged;
    private bool _freshProgressionCommandLogged;

    internal ChronicleAgentProtocol()
    {
        var documentsPath = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
        _root = Path.Combine(documentsPath, "Mount and Blade II Bannerlord", "AgentRuns", "ChronicleAgent");
        _responseRoot = Path.Combine(_root, "responses");
        Directory.CreateDirectory(_root);
        Directory.CreateDirectory(_responseRoot);
        if (Environment.GetEnvironmentVariable("CHRONICLE_FRESH_CAMPAIGN_SKIP_ISSUE_PROBE") == "1")
            ChronicleDiagnostics.Write($"fresh-progression-protocol-created|root={_root}");
    }

    internal void Poll(ChronicleCampaignBehavior behavior)
    {
        string currentCommandId = null;
        string currentAction = null;
        try
        {
            CompleteRestIfReady(behavior);
            CompleteAdvanceIfReady(behavior);
            CompleteDeferredMapClickTimeChange();
            var commandPath = Path.Combine(_root, "command.json");
            if (!_freshProgressionPollLogged && Environment.GetEnvironmentVariable("CHRONICLE_FRESH_CAMPAIGN_SKIP_ISSUE_PROBE") == "1")
            {
                _freshProgressionPollLogged = true;
                ChronicleDiagnostics.Write($"fresh-progression-protocol-polled|root={_root}|commandExists={File.Exists(commandPath)}");
            }
            if (!_freshProgressionCommandLogged && Environment.GetEnvironmentVariable("CHRONICLE_FRESH_CAMPAIGN_SKIP_ISSUE_PROBE") == "1" && File.Exists(commandPath))
            {
                _freshProgressionCommandLogged = true;
                ChronicleDiagnostics.Write("fresh-progression-protocol-command-visible");
            }
            if (_pendingClaimedCommandPath == null)
            {
                if (!File.Exists(commandPath)) return;
                _pendingClaimedCommandPath = Path.Combine(_root, "command-" + Guid.NewGuid().ToString("N") + ".processing");
                try { File.Move(commandPath, _pendingClaimedCommandPath); }
                catch (IOException) { _pendingClaimedCommandPath = null; return; }
            }
            if (EngineTime.ApplicationTime < _nextClaimedCommandReadTime) return;
            string command;
            try
            {
                using (var commandStream = new FileStream(_pendingClaimedCommandPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                using (var commandReader = new StreamReader(commandStream, new System.Text.UTF8Encoding(false), true))
                    command = commandReader.ReadToEnd();
            }
            catch (IOException exception)
            {
                var applicationTime = EngineTime.ApplicationTime;
                _nextClaimedCommandReadTime = applicationTime + 0.1f;
                if (applicationTime >= _nextClaimedCommandReadLogTime)
                {
                    ChronicleDiagnostics.Write($"agent-command-read-retry|message={exception.Message}");
                    _nextClaimedCommandReadLogTime = applicationTime + 2f;
                }
                return;
            }
            var completedClaimedPath = _pendingClaimedCommandPath;
            _pendingClaimedCommandPath = null;
            _nextClaimedCommandReadTime = 0f;
            try { File.Delete(completedClaimedPath); }
            catch (IOException exception) { ChronicleDiagnostics.Write($"agent-command-file-cleanup|message={exception.Message}"); }
            var commandId = ReadString(command, "id") ?? Guid.NewGuid().ToString("N");
            currentCommandId = commandId;
            if (commandId == _lastCommandId) return;
            _lastCommandId = commandId;

            var action = ReadString(command, "action") ?? "unknown";
            currentAction = action;
            switch (action)
            {
                case "state":
                    WriteResponse(commandId, action, "completed", behavior);
                    break;
                case "captureFrame":
                    var screenshotHarnessMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
                    if (!string.Equals(screenshotHarnessMode, "visual-capture", StringComparison.Ordinal) &&
                        !string.Equals(screenshotHarnessMode, "visual-battle-fixture", StringComparison.Ordinal))
                        throw new InvalidOperationException("captureFrame is restricted to visual Harness modes");
                    var captureRootValue = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
                    if (string.IsNullOrWhiteSpace(captureRootValue)) throw new InvalidOperationException("Harness capture directory is unavailable");
                    var captureRoot = Path.GetFullPath(captureRootValue).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
                    var captureFileName = ReadString(command, "fileName") ?? string.Empty;
                    if (!string.Equals(captureFileName, Path.GetFileName(captureFileName), StringComparison.Ordinal) || !string.Equals(Path.GetExtension(captureFileName), ".bmp", StringComparison.OrdinalIgnoreCase))
                        throw new InvalidOperationException("captureFrame requires a BMP file name without path components");
                    var capturePath = Path.GetFullPath(Path.Combine(captureRoot, captureFileName));
                    if (!capturePath.StartsWith(captureRoot, StringComparison.OrdinalIgnoreCase))
                        throw new InvalidOperationException("captureFrame output escaped the Harness temp directory");
                    Directory.CreateDirectory(Path.GetDirectoryName(capturePath));
                    TaleWorlds.Engine.Utilities.TakeScreenshot(capturePath);
                    WriteResponse(commandId, action, "completed", behavior);
                    break;
                case "inventoryTakeAll":
                    var lootInventoryState = Game.Current.GameStateManager.ActiveState as InventoryState;
                    if (lootInventoryState?.InventoryLogic == null || lootInventoryState.InventoryMode != Helpers.InventoryScreenHelper.InventoryMode.Loot)
                        throw new InvalidOperationException("inventoryTakeAll requires the native postbattle Loot InventoryState");
                    var inventoryHandler = lootInventoryState.Handler;
                    if (inventoryHandler == null || lootInventoryState.InventoryLogic.GetElementCountOnSide(TaleWorlds.CampaignSystem.Inventory.InventoryLogic.InventorySide.OtherInventory) <= 0)
                        throw new InvalidOperationException("native InventoryState has no loot items or UI handler");
                    inventoryHandler.ExecuteLootingScript();
                    WriteResponse(commandId, action, "completed", behavior);
                    break;
                case "inventoryDone":
                    var lootInventoryStateToClose = Game.Current.GameStateManager.ActiveState as InventoryState;
                    if (lootInventoryStateToClose?.InventoryLogic == null || lootInventoryStateToClose.InventoryMode != Helpers.InventoryScreenHelper.InventoryMode.Loot)
                        throw new InvalidOperationException("inventoryDone requires the native postbattle Loot InventoryState");
                    Helpers.InventoryScreenHelper.CloseScreen(fromCancel: false);
                    WriteResponse(commandId, action, "completed", behavior);
                    break;
                case "advance":
                    var days = ReadDouble(command, "days");
                    _advanceTargetDay = CampaignTime.Now.ToDays + Math.Max(0.01, days);
                    _advanceCommandId = commandId;
                    TaleWorlds.CampaignSystem.Campaign.Current.TimeControlMode = TaleWorlds.CampaignSystem.CampaignTimeControlMode.UnstoppableFastForward;
                    WriteResponse(commandId, action, "accepted", behavior);
                    break;
                case "rest":
                    var currentMenu = TaleWorlds.CampaignSystem.Campaign.Current.CurrentMenuContext?.GameMenu;
                    if (currentMenu == null || currentMenu.StringId != "town_wait_menus" || !currentMenu.IsWaitMenu || !Campaign.Current.IsMainPartyWaiting)
                        throw new InvalidOperationException("rest requires the native town settlement wait menu");
                    if (_restCommandId != null) throw new InvalidOperationException("another rest command is active");
                    var restDays = Math.Max(0.01, ReadDouble(command, "days"));
                    _restCommandId = commandId;
                    _restTargetDay = CampaignTime.Now.ToDays + restDays;
                    WriteResponse(commandId, action, "accepted", behavior);
                    break;
                case "pursue":
                    if (PlayerEncounter.IsActive || MobileParty.MainParty.CurrentSettlement != null || MobileParty.MainParty.MapEvent != null)
                        throw new InvalidOperationException("pursuit requires the campaign map with no active encounter");
                    var targetPartyId = ReadString(command, "partyId");
                    var targetParty = MobileParty.All.FirstOrDefault(party => party != null && string.Equals(party.StringId, targetPartyId, StringComparison.Ordinal));
                    if (targetParty == null || targetParty == MobileParty.MainParty || !targetParty.IsActive || !targetParty.IsVisible)
                        throw new InvalidOperationException("active visible target party not found");
                    if (targetParty.IsCurrentlyAtSea != MobileParty.MainParty.IsCurrentlyAtSea ||
                        !Helpers.NavigationHelper.CanPlayerNavigateToPosition(targetParty.Position, out var pursuitNavigationType))
                        throw new InvalidOperationException("target party is not currently navigable by the main party");
                    MobileParty.MainParty.SetMoveEngageParty(targetParty, pursuitNavigationType);
                    ApplyMapClickTimeChange(isDoubleClick: false);
                    WriteResponse(commandId, action, "completed", behavior);
                    break;
                case "follow":
                    if (PlayerEncounter.IsActive || MobileParty.MainParty.CurrentSettlement != null || MobileParty.MainParty.MapEvent != null)
                        throw new InvalidOperationException("escort requires the campaign map with no active encounter");
                    var escortPartyId = ReadString(command, "partyId");
                    var escortParty = MobileParty.All.FirstOrDefault(party => party != null && string.Equals(party.StringId, escortPartyId, StringComparison.Ordinal));
                    if (escortParty == null || escortParty == MobileParty.MainParty || !escortParty.IsActive || !escortParty.IsVisible)
                        throw new InvalidOperationException("active visible target party not found");
                    if (escortParty.IsCurrentlyAtSea != MobileParty.MainParty.IsCurrentlyAtSea ||
                        !Helpers.NavigationHelper.CanPlayerNavigateToPosition(escortParty.Position, out var escortNavigationType))
                        throw new InvalidOperationException("target party is not currently navigable by the main party");
                    MobileParty.MainParty.SetMoveEscortParty(escortParty, escortNavigationType, isTargetingPort: false);
                    ApplyMapClickTimeChange(isDoubleClick: false);
                    WriteResponse(commandId, action, "completed", behavior);
                    break;
                case "hold":
                    MobileParty.MainParty.SetMoveModeHold();
                    ApplyMapClickTimeChange(isDoubleClick: false);
                    WriteResponse(commandId, action, "completed", behavior);
                    break;
                case "pause":
                    TaleWorlds.CampaignSystem.Campaign.Current.TimeControlMode = TaleWorlds.CampaignSystem.CampaignTimeControlMode.Stop;
                    WriteResponse(commandId, action, "completed", behavior);
                    break;
                case "resume":
                    TaleWorlds.CampaignSystem.Campaign.Current.TimeControlMode = TaleWorlds.CampaignSystem.CampaignTimeControlMode.UnstoppablePlay;
                    WriteResponse(commandId, action, "completed", behavior);
                    break;
                case "move":
                    if (PlayerEncounter.IsActive || MobileParty.MainParty.CurrentSettlement != null || MobileParty.MainParty.MapEvent != null)
                        throw new InvalidOperationException("settlement movement requires the campaign map with no active encounter");
                    var settlementId = ReadString(command, "settlementId");
                    var settlement = string.IsNullOrWhiteSpace(settlementId) ? null : Settlement.Find(settlementId);
                    if (settlement == null || !settlement.IsActive) throw new InvalidOperationException("active settlement not found");
                    if (settlement.MapFaction != null && FactionManager.IsAtWarAgainstFaction(MobileParty.MainParty.MapFaction, settlement.MapFaction))
                        throw new InvalidOperationException("hostile settlement rejected by safe movement policy");
                    Helpers.NavigationHelper.GetInteractionDataForMainParty(settlement, out var canNavigateToSettlement, out var navigationType, out var targetingPort);
                    if (!canNavigateToSettlement) throw new InvalidOperationException("settlement is not currently navigable by the main party");
                    MobileParty.MainParty.SetMoveGoToSettlement(settlement, navigationType, targetingPort);
                    ApplyMapClickTimeChange(isDoubleClick: false);
                    WriteResponse(commandId, action, "completed", behavior);
                    break;
                case "menu":
                    if (TaleWorlds.CampaignSystem.Campaign.Current.CurrentMenuContext?.GameMenu == null)
                        throw new InvalidOperationException("no campaign menu is active");
                    WriteResponse(commandId, action, "completed", behavior);
                    break;
                case "recruitOptions":
                    _recruitmentViewModel = ChronicleAgentRecruitment.CreateOrRefresh(_recruitmentViewModel);
                    WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentRecruitment.BuildOptionsJson(_recruitmentViewModel));
                    break;
                case "recruit":
                    _recruitmentViewModel = ChronicleAgentRecruitment.CreateOrRefresh(_recruitmentViewModel);
                    var recruitOwnerId = ReadString(command, "ownerId");
                    var recruitTroopId = ReadString(command, "troopId");
                    var recruitSlot = (int)ReadDouble(command, "slot");
                    var recruitmentResult = ChronicleAgentRecruitment.Recruit(_recruitmentViewModel, recruitOwnerId, recruitTroopId, recruitSlot);
                    WriteResponse(commandId, action, "completed", behavior, null, recruitmentResult);
                    break;
                case "foodOptions":
                    WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentProvisioning.GetFoodOptionsJson());
                    break;
                case "tradeOptions":
                    WriteResponse(commandId, action, "completed", behavior, null, ChronicleAgentProvisioning.GetTradeOptionsJson());
                    break;
                case "trade":
                    var tradeDirection = ReadString(command, "direction");
                    var tradeItemId = ReadString(command, "itemId");
                    var tradeAmount = (int)ReadDouble(command, "amount");
                    var tradeResult = ChronicleAgentProvisioning.TradeItem(tradeDirection, tradeItemId, tradeAmount);
                    WriteResponse(commandId, action, "completed", behavior, null, tradeResult);
                    break;
                case "provision":
                    var foodItemId = ReadString(command, "itemId");
                    var foodAmount = (int)ReadDouble(command, "amount");
                    var provisionResult = ChronicleAgentProvisioning.BuyFood(foodItemId, foodAmount);
                    WriteResponse(commandId, action, "completed", behavior, null, provisionResult);
                    break;
                case "menuSelect":
                    var menuContext = TaleWorlds.CampaignSystem.Campaign.Current.CurrentMenuContext;
                    var expectedMenuId = ReadString(command, "menuId");
                    var optionId = ReadString(command, "optionId");
                    if (menuContext?.GameMenu == null || !string.Equals(menuContext.GameMenu.StringId, expectedMenuId, StringComparison.Ordinal))
                        throw new InvalidOperationException("campaign menu changed before option selection");
                    var menuOptions = menuContext.GameMenu.MenuOptions.ToList();
                    if (menuContext.GameMenu.MenuRepeatObjects.Count > 0)
                        throw new InvalidOperationException("repeatable menu options are not supported by protocol v1");
                    var optionIndex = menuOptions.FindIndex(candidate => string.Equals(candidate.IdString, optionId, StringComparison.Ordinal));
                    if (optionIndex < 0) throw new InvalidOperationException("menu option not found");
                    var option = menuOptions[optionIndex];
                    if (!option.GetConditionsHold(TaleWorlds.Core.Game.Current, menuContext) || !option.IsEnabled)
                        throw new InvalidOperationException("menu option is unavailable or disabled");
                    menuContext.GameMenu.RunMenuOptionConsequence(menuContext, optionIndex);
                    WriteResponse(commandId, action, "completed", behavior);
                    break;
                case "dialogueSelect":
                    var conversationManager = Campaign.Current.ConversationManager;
                    var dialogueOptionId = ReadString(command, "optionId");
                    if (conversationManager == null || !conversationManager.IsConversationInProgress)
                        throw new InvalidOperationException("dialogueSelect requires an active native conversation");
                    var dialogueOption = conversationManager.CurOptions.FirstOrDefault(option => string.Equals(option.Id, dialogueOptionId, StringComparison.Ordinal));
                    if (string.IsNullOrWhiteSpace(dialogueOption.Id) || !dialogueOption.IsClickable)
                        throw new InvalidOperationException("conversation option is missing or not clickable");
                    conversationManager.DoOption(dialogueOptionId);
                    WriteResponse(commandId, action, "completed", behavior);
                    break;
                case "dialogueContinue":
                    var conversationToContinue = Campaign.Current.ConversationManager;
                    if (conversationToContinue == null || !conversationToContinue.IsConversationInProgress || conversationToContinue.CurOptions.Count != 0)
                        throw new InvalidOperationException("dialogueContinue requires an active conversation with no selectable options");
                    conversationToContinue.ContinueConversation();
                    WriteResponse(commandId, action, "completed", behavior);
                    break;
                case "battlePause":
                    var battleSimulationToPause = PlayerEncounter.CurrentBattleSimulation;
                    if (battleSimulationToPause == null) throw new InvalidOperationException("battlePause requires an active native battle simulation");
                    battleSimulationToPause.Pause();
                    WriteResponse(commandId, action, "completed", behavior);
                    break;
                case "battleSkip":
                    var battleSimulationToSkip = PlayerEncounter.CurrentBattleSimulation;
                    if (battleSimulationToSkip == null || battleSimulationToSkip.IsSimulationFinished)
                        throw new InvalidOperationException("battleSkip requires an unfinished native battle simulation");
                    battleSimulationToSkip.Skip();
                    WriteResponse(commandId, action, "completed", behavior);
                    break;
                case "seedVisualLoot":
                    if (!string.Equals(Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE"), "visual-battle-fixture", StringComparison.Ordinal))
                        throw new InvalidOperationException("seedVisualLoot is restricted to the visual battle Harness fixture");
                    var finishedLootSimulation = PlayerEncounter.CurrentBattleSimulation;
                    var activeLootEncounter = PlayerEncounter.Current;
                    if (finishedLootSimulation == null || !finishedLootSimulation.IsSimulationFinished || activeLootEncounter == null)
                        throw new InvalidOperationException("seedVisualLoot requires a finished native simulation before encounter aftermath");
                    var visualLootItem = Game.Current.ObjectManager.GetObject<ItemObject>("wool");
                    if (visualLootItem == null) throw new InvalidOperationException("visual loot fixture item 'wool' is unavailable");
                    activeLootEncounter.RosterToReceiveLootItems.AddToCounts(visualLootItem, 10);
                    ChronicleDiagnostics.Write("visual-loot-fixture-seeded|item=wool|count=10|naturalDrop=false");
                    WriteResponse(commandId, action, "completed", behavior, null, "{\"itemId\":\"wool\",\"count\":10,\"naturalDrop\":false}");
                    break;
                case "battleFinish":
                    var completedBattleSimulation = PlayerEncounter.CurrentBattleSimulation;
                    if (completedBattleSimulation == null || !completedBattleSimulation.IsSimulationFinished)
                        throw new InvalidOperationException("battleFinish requires a completed native battle simulation");
                    var activeMapState = Game.Current.GameStateManager.LastOrDefault<MapState>();
                    if (activeMapState != null && activeMapState.IsSimulationActive) activeMapState.EndBattleSimulation();
                    var captureRewardTelemetry = string.Equals(Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE"), "visual-battle-fixture", StringComparison.Ordinal);
                    var rewardMapEvent = captureRewardTelemetry ? completedBattleSimulation.MapEvent : null;
                    var rewardWinnerSide = rewardMapEvent?.Winner;
                    var rewardWinnerParties = rewardWinnerSide?.Parties.ToList() ?? new System.Collections.Generic.List<MapEventParty>();
                    var rewardLoserSide = rewardMapEvent == null || rewardMapEvent.DefeatedSide == BattleSideEnum.None ? null : rewardMapEvent.GetMapEventSide(rewardMapEvent.DefeatedSide);
                    var rewardLoserParties = rewardLoserSide?.Parties.ToList() ?? new System.Collections.Generic.List<MapEventParty>();
                    var rewardPlayerRenownBefore = Clan.PlayerClan?.Renown ?? 0f;
                    var rewardAttackerStrength = rewardMapEvent != null && rewardMapEvent.StrengthOfSide.Length > 1 ? rewardMapEvent.StrengthOfSide[1] : 0f;
                    var rewardDefenderStrength = rewardMapEvent != null && rewardMapEvent.StrengthOfSide.Length > 0 ? rewardMapEvent.StrengthOfSide[0] : 0f;
                    var rewardWinnerContributionTotal = rewardWinnerParties.Sum(entry => entry.ContributionToBattle);
                    var rewardPlayerEntry = rewardWinnerParties.FirstOrDefault(entry => entry.Party == PartyBase.MainParty);
                    completedBattleSimulation.OnFinished();
                    string rewardTelemetryJson = null;
                    if (captureRewardTelemetry && rewardMapEvent != null && rewardWinnerSide != null)
                    {
                        try
                        {
                            var rewardPlayerRenownAfter = Clan.PlayerClan?.Renown ?? 0f;
                            var loserStartingStrength = rewardMapEvent.StrengthOfSide[(int)rewardMapEvent.DefeatedSide];
                            var loserCurrentStrength = rewardLoserParties.Sum(entry => entry.Party.GetCustomStrength(entry.Party.Side, rewardMapEvent.SimulationContext));
                            var loserStrengthReductionFactor = loserStartingStrength > 0f ? (loserStartingStrength - loserCurrentStrength) / loserStartingStrength : 0f;
                            var partyAwards = string.Join(",", rewardWinnerParties.Select(entry => "{\"partyId\":\"" + Escape(entry.Party.MobileParty?.StringId ?? entry.Party.LeaderHero?.StringId ?? "party") + "\",\"contribution\":" + entry.ContributionToBattle + ",\"renown\":" + entry.GainedRenown.ToString("F3", CultureInfo.InvariantCulture) + "}"));
                            rewardTelemetryJson = "{\"eventType\":\"" + Escape(rewardMapEvent.EventType.ToString()) + "\",\"winnerSide\":\"" + Escape(rewardMapEvent.WinningSide.ToString()) + "\",\"attackerStartingStrength\":" + rewardAttackerStrength.ToString("F3", CultureInfo.InvariantCulture) + ",\"defenderStartingStrength\":" + rewardDefenderStrength.ToString("F3", CultureInfo.InvariantCulture) + ",\"winnerRenownValue\":" + rewardWinnerSide.RenownValue.ToString("F3", CultureInfo.InvariantCulture) + ",\"winnerStrengthRatio\":" + rewardWinnerSide.StrengthRatio.ToString("F3", CultureInfo.InvariantCulture) + ",\"winnerContributionTotal\":" + rewardWinnerContributionTotal + ",\"playerContribution\":" + (rewardPlayerEntry?.ContributionToBattle ?? 0) + ",\"loserStartingStrength\":" + loserStartingStrength.ToString("F3", CultureInfo.InvariantCulture) + ",\"loserCurrentStrengthAfterFinish\":" + loserCurrentStrength.ToString("F3", CultureInfo.InvariantCulture) + ",\"loserStrengthReductionFactorAfterFinish\":" + loserStrengthReductionFactor.ToString("F3", CultureInfo.InvariantCulture) + ",\"playerRenownBefore\":" + rewardPlayerRenownBefore.ToString("F3", CultureInfo.InvariantCulture) + ",\"playerRenownAfter\":" + rewardPlayerRenownAfter.ToString("F3", CultureInfo.InvariantCulture) + ",\"winnerPartyAwards\":[" + partyAwards + "]}";
                        }
                        catch (Exception telemetryException)
                        {
                            ChronicleDiagnostics.Write("postbattle-renown-telemetry-failed|detail=" + telemetryException.GetType().Name + ":" + telemetryException.Message);
                        }
                    }
                    WriteResponse(commandId, action, "completed", behavior, null, rewardTelemetryJson == null ? null : "{\"rewardTelemetry\":" + rewardTelemetryJson + "}");
                    break;
                case "battleRetreat":
                    var battleSimulationToRetreat = PlayerEncounter.CurrentBattleSimulation;
                    if (battleSimulationToRetreat == null) throw new InvalidOperationException("battleRetreat requires an active native battle simulation");
                    if (battleSimulationToRetreat.IsSimulationFinished) throw new InvalidOperationException("battleRetreat requires an unfinished battle simulation");
                    battleSimulationToRetreat.OnPlayerRetreat();
                    WriteResponse(commandId, action, "completed", behavior);
                    break;
                case "missionRetreat":
                    var missionToRetreat = Mission.Current;
                    if (missionToRetreat == null || missionToRetreat.MissionEnded) throw new InvalidOperationException("missionRetreat requires an active battle mission");
                    var battleEndLogic = missionToRetreat.GetMissionBehavior<BattleEndLogic>();
                    if (battleEndLogic == null) throw new InvalidOperationException("active mission does not expose native BattleEndLogic");
                    var exitResult = battleEndLogic.TryExit();
                    if (exitResult == BattleEndLogic.ExitResult.SurrenderSiege)
                        throw new InvalidOperationException("native TAB exit is surrender for a siege defender, not retreat");
                    if (exitResult == BattleEndLogic.ExitResult.True)
                        throw new InvalidOperationException("battle mission already ended; retreat is not applicable");
                    missionToRetreat.RetreatMission();
                    var retreatData = "{\"tryExit\":\"" + Escape(exitResult.ToString()) + "\",\"missionEnded\":" + (missionToRetreat.MissionEnded ? "true" : "false") + "}";
                    WriteResponse(commandId, action, "completed", behavior, null, retreatData);
                    break;
                case "partyTakeAll":
                    var activeLootPartyState = Game.Current.GameStateManager.ActiveState as PartyState;
                    var lootTypeName = ReadString(command, "troopType");
                    if (activeLootPartyState?.PartyScreenLogic == null || activeLootPartyState.PartyScreenMode.ToString() != "Loot")
                        throw new InvalidOperationException("partyTakeAll requires the native postbattle loot PartyState");
                    var lootTroopType = lootTypeName == "members"
                        ? PartyScreenLogic.TroopType.Member
                        : lootTypeName == "prisoners" ? PartyScreenLogic.TroopType.Prisoner : (PartyScreenLogic.TroopType?)null;
                    if (!lootTroopType.HasValue) throw new InvalidOperationException("troopType must be members or prisoners");
                    var lootRoster = activeLootPartyState.PartyScreenLogic.GetRoster(PartyScreenLogic.PartyRosterSide.Left, lootTroopType.Value);
                    if (lootRoster.Count == 0 || !lootRoster.GetTroopRoster().Any(element => element.Character != null && element.Number > 0 && activeLootPartyState.PartyScreenLogic.IsTroopTransferable(lootTroopType.Value, element.Character, (int)PartyScreenLogic.PartyRosterSide.Left)))
                        throw new InvalidOperationException("no transferable loot of the requested type is available");
                    var takeAllCommand = new PartyScreenLogic.PartyCommand();
                    takeAllCommand.FillForTransferAllTroops(PartyScreenLogic.PartyRosterSide.Left, lootTroopType.Value);
                    activeLootPartyState.PartyScreenLogic.AddCommand(takeAllCommand);
                    activeLootPartyState.PartyScreenLogic.RemoveZeroCounts();
                    WriteResponse(commandId, action, "completed", behavior);
                    break;
                case "partyScreenDone":
                    var lootPartyStateToClose = Game.Current.GameStateManager.ActiveState as PartyState;
                    if (lootPartyStateToClose?.PartyScreenLogic == null || lootPartyStateToClose.PartyScreenMode.ToString() != "Loot")
                        throw new InvalidOperationException("partyScreenDone requires the native postbattle loot PartyState");
                    if (!lootPartyStateToClose.PartyScreenLogic.IsDoneActive()) throw new InvalidOperationException("native loot PartyScreen Done is unavailable");
                    var partyScreenHandler = lootPartyStateToClose.Handler as IPartyScreenPrisonHandler;
                    if (partyScreenHandler == null) throw new InvalidOperationException("native PartyScreen Done handler is unavailable");
                    partyScreenHandler.ExecuteDoneScript();
                    WriteResponse(commandId, action, "completed", behavior);
                    break;
                case "save":
                    var saveName = ReadString(command, "name");
                    if (string.IsNullOrWhiteSpace(saveName)) throw new InvalidOperationException("save name is required");
                    _pendingSaveName = saveName;
                    _pendingSaveCommandId = commandId;
                    TaleWorlds.CampaignSystem.Campaign.Current.SaveHandler.SaveAs(saveName);
                    WriteResponse(commandId, action, "accepted", behavior);
                    break;
                case "stop":
                    TaleWorlds.CampaignSystem.Campaign.Current.TimeControlMode = TaleWorlds.CampaignSystem.CampaignTimeControlMode.Stop;
                    WriteResponse(commandId, action, "completed", behavior);
                    break;
                default:
                    WriteResponse(commandId, action, "rejected", behavior, "unknown action");
                    break;
            }
        }
        catch (Exception exception)
        {
            ChronicleDiagnostics.Write($"agent-protocol-error|type={exception.GetType().Name}|message={exception.Message}");
            if (!string.IsNullOrWhiteSpace(currentCommandId))
            {
                try { WriteResponse(currentCommandId, currentAction ?? "unknown", "rejected", behavior, exception.ToString()); }
                catch { }
            }
        }
    }

    private void CompleteRestIfReady(ChronicleCampaignBehavior behavior)
    {
        if (_restCommandId == null || !_restTargetDay.HasValue) return;
        var menu = TaleWorlds.CampaignSystem.Campaign.Current.CurrentMenuContext?.GameMenu;
        var commandId = _restCommandId;
        if (menu == null || menu.StringId != "town_wait_menus" || !menu.IsWaitMenu || !Campaign.Current.IsMainPartyWaiting)
        {
            WriteResponse(commandId, "rest", "failed", behavior, "settlement wait was interrupted before the requested time elapsed");
            _restCommandId = null;
            _restTargetDay = null;
            return;
        }
        if (CampaignTime.Now.ToDays >= _restTargetDay.Value)
        {
            WriteResponse(commandId, "rest", "completed", behavior);
            _restCommandId = null;
            _restTargetDay = null;
        }
    }

    private void ApplyMapClickTimeChange(bool isDoubleClick)
    {
        var mode = BannerlordConfig.MapDoubleClickBehavior;
        var campaign = Campaign.Current;
        switch (mode)
        {
            case 0:
                if (!isDoubleClick && campaign.TimeControlMode == CampaignTimeControlMode.StoppableFastForward)
                {
                    _waitForDoubleClickUntilTime = EngineTime.ApplicationTime + 0.3f;
                    campaign.TimeControlMode = CampaignTimeControlMode.StoppableFastForward;
                }
                else
                {
                    campaign.TimeControlMode = isDoubleClick ? CampaignTimeControlMode.StoppableFastForward : CampaignTimeControlMode.StoppablePlay;
                }
                break;
            case 1:
                if (isDoubleClick)
                    campaign.TimeControlMode = campaign.TimeControlMode == CampaignTimeControlMode.StoppableFastForward ? CampaignTimeControlMode.StoppablePlay : CampaignTimeControlMode.StoppableFastForward;
                else
                    campaign.TimeControlMode = campaign.TimeControlMode == CampaignTimeControlMode.StoppableFastForward ? CampaignTimeControlMode.StoppableFastForward : CampaignTimeControlMode.StoppablePlay;
                break;
            case 2:
                campaign.TimeControlMode = campaign.TimeControlMode == CampaignTimeControlMode.StoppableFastForward ? CampaignTimeControlMode.StoppableFastForward : CampaignTimeControlMode.StoppablePlay;
                break;
        }
    }

    private void CompleteDeferredMapClickTimeChange()
    {
        if (_waitForDoubleClickUntilTime <= 0f || _waitForDoubleClickUntilTime >= EngineTime.ApplicationTime) return;
        if (BannerlordConfig.MapDoubleClickBehavior == 0 && Campaign.Current.TimeControlMode == CampaignTimeControlMode.StoppableFastForward)
            Campaign.Current.TimeControlMode = CampaignTimeControlMode.StoppablePlay;
        _waitForDoubleClickUntilTime = 0f;
    }

    private void CompleteAdvanceIfReady(ChronicleCampaignBehavior behavior)
    {
        if (!_advanceTargetDay.HasValue) return;
        var interruptedByEncounter = PlayerEncounter.IsActive;
        if (!interruptedByEncounter && CampaignTime.Now.ToDays < _advanceTargetDay.Value) return;
        var commandId = _advanceCommandId;
        var completionReason = interruptedByEncounter ? "encounter" : "requestedDuration";
        _advanceTargetDay = null;
        _advanceCommandId = null;
        Campaign.Current.TimeControlMode = CampaignTimeControlMode.Stop;
        var dataJson = "{\"completedBy\":\"" + completionReason + "\"}";
        WriteResponse(commandId, "advance", "completed", behavior, null, dataJson);
    }

    internal void OnSaveOver(bool successful, string saveName, ChronicleCampaignBehavior behavior)
    {
        if (_pendingSaveName == null || !string.Equals(_pendingSaveName, saveName, StringComparison.Ordinal)) return;
        _pendingSaveName = null;
        WriteResponse(_pendingSaveCommandId, "save", successful ? "completed" : "rejected", behavior, successful ? null : "save failed");
        _pendingSaveCommandId = null;
    }

    private void WriteResponse(string commandId, string action, string status, ChronicleCampaignBehavior behavior, string error = null, string dataJson = null)
    {
        var response = "{\"protocolVersion\":1,\"commandId\":\"" + Escape(commandId) + "\",\"action\":\"" + Escape(action) + "\",\"status\":\"" + Escape(status) + "\",\"processId\":" + Process.GetCurrentProcess().Id + ",\"campaignDay\":" + CampaignTime.Now.ToDays.ToString("F3", CultureInfo.InvariantCulture) + ",\"dailyTickCount\":" + behavior.DailyTickCount + ",\"timeControlMode\":\"" + Escape(TaleWorlds.CampaignSystem.Campaign.Current.TimeControlMode.ToString()) + "\",\"state\":" + ChronicleAgentObserver.BuildSnapshotJson() + (dataJson == null ? "" : ",\"data\":" + dataJson) + (error == null ? "" : ",\"error\":\"" + Escape(error) + "\"") + "}";
        var safeCommandId = SanitizeFileName(commandId);
        var safeStatus = SanitizeFileName(status);
        var responsePath = Path.Combine(_responseRoot, safeCommandId + "." + safeStatus + ".json");
        var temporaryPath = Path.Combine(_responseRoot, safeCommandId + "." + safeStatus + "." + Guid.NewGuid().ToString("N") + ".tmp");
        File.WriteAllText(temporaryPath, response);
        for (var attempt = 0; attempt < 5; attempt++)
        {
            try
            {
                if (File.Exists(responsePath)) File.Delete(responsePath);
                File.Move(temporaryPath, responsePath);
                File.AppendAllText(Path.Combine(_root, "events.jsonl"), response + Environment.NewLine);
                return;
            }
            catch (IOException) when (attempt < 4)
            {
                System.Threading.Thread.Sleep(20);
            }
        }
    }

    private static string SanitizeFileName(string value)
    {
        var result = value ?? string.Empty;
        foreach (var invalidCharacter in Path.GetInvalidFileNameChars()) result = result.Replace(invalidCharacter, '_');
        return string.IsNullOrWhiteSpace(result) ? "unknown" : result;
    }

    private static string ReadString(string json, string key)
    {
        var marker = "\"" + key + "\":\"";
        var start = json.IndexOf(marker, StringComparison.Ordinal);
        if (start < 0) return null;
        start += marker.Length;
        var end = json.IndexOf('"', start);
        return end < 0 ? null : json.Substring(start, end - start);
    }

    private static double ReadDouble(string json, string key)
    {
        var marker = "\"" + key + "\":";
        var start = json.IndexOf(marker, StringComparison.Ordinal);
        if (start < 0) return 0;
        start += marker.Length;
        var end = json.IndexOfAny(new[] { ',', '}' }, start);
        var value = json.Substring(start, end < 0 ? json.Length - start : end - start);
        return double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out var parsed) ? parsed : 0;
    }

    private static string Escape(string value) => (value ?? string.Empty).Replace("\\", "\\\\").Replace("\"", "\\\"");
}
