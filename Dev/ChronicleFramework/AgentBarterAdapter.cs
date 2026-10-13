using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.BarterSystem;
using TaleWorlds.CampaignSystem.BarterSystem.Barterables;
using TaleWorlds.CampaignSystem.Party;
using TaleWorlds.CampaignSystem.Roster;
using TaleWorlds.CampaignSystem.ViewModelCollection.Barter;
using TaleWorlds.CampaignSystem.GameState;
using TaleWorlds.Core;

namespace ChronicleFramework;

internal static class ChronicleAgentBarterAdapter
{
    private sealed class Candidate
    {
        internal int Index;
        internal Barterable Barterable;
        internal BarterItemVM ViewModel;
        internal string ListId;
    }

    private static BarterData _activeData;
    private static BarterVM _activeViewModel;
    private static string _sessionId;
    private static long _generation;
    private static Dictionary<string, Candidate> _lastObservedCandidates = new Dictionary<string, Candidate>(StringComparer.Ordinal);

    internal static void CaptureNativeViewModel(BarterData data, BarterVM viewModel)
    {
        if (viewModel == null) { ChronicleDiagnostics.Write("native-barter-view-not-captured|reason=null-viewmodel"); return; }
        if (!IsSupportedPlayerContext(data)) { ChronicleDiagnostics.Write("native-barter-view-not-captured|reason=not-player-initiated-context"); return; }
        _activeData = data;
        _activeViewModel = viewModel;
        _sessionId = Guid.NewGuid().ToString("N");
        _generation = 0;
        _lastObservedCandidates.Clear();
        ChronicleDiagnostics.Write($"native-barter-view-captured|offerer={data.OffererHero?.StringId}|other={data.OtherHero?.StringId}|session={_sessionId}");
    }

    internal static void ClearNativeViewModel(BarterVM viewModel = null)
    {
        if (viewModel != null && !ReferenceEquals(viewModel, _activeViewModel)) return;
        if (_activeViewModel != null) ChronicleDiagnostics.Write($"native-barter-view-cleared|session={_sessionId}");
        _activeData = null;
        _activeViewModel = null;
        _sessionId = null;
        _generation = 0;
        _lastObservedCandidates.Clear();
    }

    internal static string BuildOptionsJson()
    {
        RequireCurrentPlayerBarter(out var data, out var viewModel);
        _generation++;
        _lastObservedCandidates = new Dictionary<string, Candidate>(StringComparer.Ordinal);
        var rows = CollectCandidates(data, viewModel);
        var proposalFingerprint = BuildProposalFingerprint(data, viewModel, rows);
        var json = new StringBuilder(8192);
        json.Append('{').Append("\"schemaVersion\":1");
        ChroniclePartyUpgradeAdapter.Property(json, "sessionId", _sessionId);
        ChroniclePartyUpgradeAdapter.Property(json, "proposalFingerprint", proposalFingerprint);
        ChroniclePartyUpgradeAdapter.Property(json, "context", DescribeContext(data));
        ChroniclePartyUpgradeAdapter.Property(json, "contextInitializer", data.ContextInitializer?.Method?.Name);
        ChroniclePartyUpgradeAdapter.Property(json, "gameState", Game.Current?.GameStateManager?.ActiveState?.GetType().Name);
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlMode", Campaign.Current.TimeControlMode.ToString());
        json.Append(",\"campaignDay\":").Append(CampaignTime.Now.ToDays.ToString("F6", CultureInfo.InvariantCulture));
        ChroniclePartyUpgradeAdapter.Property(json, "offererHeroId", data.OffererHero?.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "offererHeroName", data.OffererHero?.Name?.ToString());
        ChroniclePartyUpgradeAdapter.Property(json, "otherHeroId", data.OtherHero?.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "otherHeroName", data.OtherHero?.Name?.ToString());
        json.Append(",\"playerGold\":").Append(Hero.MainHero.Gold);
        json.Append(",\"otherHeroGold\":").Append(data.OtherHero?.Gold ?? 0);
        json.Append(",\"otherHeroBaseRelation\":").Append(data.OtherHero == null ? 0 : Hero.MainHero.GetBaseHeroRelation(data.OtherHero));
        json.Append(",\"otherHeroEffectiveRelation\":").Append(data.OtherHero == null ? 0 : Hero.MainHero.GetRelation(data.OtherHero));
        ChroniclePartyUpgradeAdapter.Property(json, "leftName", viewModel.LeftNameLbl);
        ChroniclePartyUpgradeAdapter.Property(json, "rightName", viewModel.RightNameLbl);
        json.Append(",\"leftMaxGold\":").Append(viewModel.LeftMaxGold);
        json.Append(",\"rightMaxGold\":").Append(viewModel.RightMaxGold);
        json.Append(",\"isOfferDisabled\":").Append(ChroniclePartyUpgradeAdapter.Bool(viewModel.IsOfferDisabled));
        json.Append(",\"offererResultPercent\":").Append(viewModel.ResultBarOffererPercentage);
        json.Append(",\"otherResultPercent\":").Append(viewModel.ResultBarOtherPercentage);
        json.Append(",\"nativeCandidateCount\":").Append(rows.Count);
        json.Append(",\"candidates\":[");
        for (var index = 0; index < rows.Count; index++)
        {
            if (index > 0) json.Append(',');
            AppendCandidate(json, data, rows[index]);
        }
        json.Append("]}");
        return json.ToString();
    }

    internal static string EditProposal(string candidateId, string operation, int amount)
    {
        RequireCurrentPlayerBarter(out var data, out var viewModel);
        if (string.IsNullOrWhiteSpace(candidateId) || !_lastObservedCandidates.TryGetValue(candidateId, out var candidate))
            throw new InvalidOperationException("barter candidate is stale or was not returned by the latest barterOptions observation");
        var beforeAmount = candidate.ViewModel.CurrentOfferedAmount;
        var wasOffered = candidate.Barterable.IsOffered;
        switch (operation)
        {
            case "offer":
                if (wasOffered) throw new InvalidOperationException("the current Native Barterable is already offered");
                if (!candidate.ViewModel.IsItemTransferrable) throw new InvalidOperationException("Native BarterVM marks this candidate as not transferable/compatible");
                if (amount < 1 || amount > candidate.ViewModel.TotalItemCount) throw new InvalidOperationException("requested offer amount is outside the current Native BarterItemVM range");
                candidate.ViewModel.ExecuteAction();
                if (!candidate.Barterable.IsOffered) throw new InvalidOperationException("Native BarterItemVM did not add the candidate to the proposal");
                if (candidate.ViewModel.CurrentOfferedAmount != amount) candidate.ViewModel.CurrentOfferedAmount = amount;
                break;
            case "setAmount":
                if (!wasOffered) throw new InvalidOperationException("setAmount requires a candidate already present in the Native proposal");
                if (!candidate.ViewModel.IsItemTransferrable) throw new InvalidOperationException("the Native BarterVM marks this context-dependent offer as fixed");
                if (amount < 1 || amount > candidate.ViewModel.TotalItemCount) throw new InvalidOperationException("requested amount is outside the current Native BarterItemVM range");
                candidate.ViewModel.CurrentOfferedAmount = amount;
                break;
            case "remove":
                if (!wasOffered) throw new InvalidOperationException("remove requires a candidate already present in the Native proposal");
                if (!candidate.ViewModel.IsItemTransferrable) throw new InvalidOperationException("the Native BarterVM marks this context-dependent offer as fixed");
                candidate.ViewModel.CurrentOfferedAmount = 1;
                candidate.ViewModel.ExecuteRemoveOffered();
                if (candidate.Barterable.IsOffered) throw new InvalidOperationException("Native BarterItemVM did not remove the candidate from the proposal");
                break;
            default:
                throw new InvalidOperationException("barter operation must be offer, setAmount or remove");
        }

        var json = new StringBuilder(8192);
        json.Append('{').Append("\"schemaVersion\":1");
        ChroniclePartyUpgradeAdapter.Property(json, "operation", operation);
        ChroniclePartyUpgradeAdapter.Property(json, "candidateId", candidateId);
        ChroniclePartyUpgradeAdapter.Property(json, "nativeCandidateId", candidate.Barterable.StringID);
        json.Append(",\"amountBefore\":").Append(beforeAmount);
        json.Append(",\"amountAfter\":").Append(candidate.ViewModel.CurrentOfferedAmount);
        json.Append(",\"offeredBefore\":").Append(ChroniclePartyUpgradeAdapter.Bool(wasOffered));
        json.Append(",\"offeredAfter\":").Append(ChroniclePartyUpgradeAdapter.Bool(candidate.Barterable.IsOffered));
        json.Append(",\"updatedOptions\":").Append(BuildOptionsJson()).Append('}');
        return json.ToString();
    }

    internal static string ResetProposal()
    {
        RequireCurrentPlayerBarter(out _, out var viewModel);
        viewModel.ExecuteReset();
        return "{\"schemaVersion\":1,\"reset\":true,\"updatedOptions\":" + BuildOptionsJson() + "}";
    }

    internal static string AutoBalanceProposal()
    {
        RequireCurrentPlayerBarter(out var data, out var viewModel);
        var offerCountBefore = data.GetOfferedBarterables().Count;
        var playerGoldBefore = Hero.MainHero.Gold;
        var playerPartyBefore = ItemRosterFingerprint(PartyBase.MainParty?.ItemRoster);
        var timeModeBefore = Campaign.Current.TimeControlMode.ToString();
        var dayBefore = CampaignTime.Now.ToDays;
        viewModel.ExecuteAutoBalance();
        var updatedOptions = BuildOptionsJson();
        var json = new StringBuilder(10000);
        json.Append('{').Append("\"schemaVersion\":1,\"autoBalanced\":true");
        json.Append(",\"offeredBarterableCountBefore\":").Append(offerCountBefore);
        json.Append(",\"offeredBarterableCountAfter\":").Append(data.GetOfferedBarterables().Count);
        json.Append(",\"playerGoldBefore\":").Append(playerGoldBefore);
        json.Append(",\"playerGoldAfter\":").Append(Hero.MainHero.Gold);
        json.Append(",\"playerPartyFingerprintUnchanged\":").Append(ChroniclePartyUpgradeAdapter.Bool(string.Equals(playerPartyBefore, ItemRosterFingerprint(PartyBase.MainParty?.ItemRoster), StringComparison.Ordinal)));
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeBefore", timeModeBefore);
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeAfter", Campaign.Current.TimeControlMode.ToString());
        json.Append(",\"campaignDayBefore\":").Append(dayBefore.ToString("F6", CultureInfo.InvariantCulture));
        json.Append(",\"campaignDayAfter\":").Append(CampaignTime.Now.ToDays.ToString("F6", CultureInfo.InvariantCulture));
        json.Append(",\"updatedOptions\":").Append(updatedOptions).Append('}');
        return json.ToString();
    }

    internal static string CancelProposal()
    {
        RequireCurrentPlayerBarter(out var data, out var viewModel);
        var otherHero = data.OtherHero;
        var dayBefore = CampaignTime.Now.ToDays;
        var timeModeBefore = Campaign.Current.TimeControlMode.ToString();
        var playerGoldBefore = Hero.MainHero.Gold;
        var otherGoldBefore = data.OtherHero?.Gold ?? 0;
        var otherHeroBaseRelationBefore = otherHero == null ? 0 : Hero.MainHero.GetBaseHeroRelation(otherHero);
        var playerPartyBefore = ItemRosterFingerprint(PartyBase.MainParty?.ItemRoster);
        var otherPartyBefore = ItemRosterFingerprint(data.OtherParty?.ItemRoster);
        viewModel.ExecuteCancel();
        var returnedToConversation = Campaign.Current.ConversationManager?.IsConversationInProgress ?? false;
        var stateName = Game.Current?.GameStateManager?.ActiveState?.GetType().Name;
        var json = new StringBuilder(1024);
        json.Append('{').Append("\"schemaVersion\":1,\"cancelled\":true");
        json.Append(",\"returnedToConversation\":").Append(ChroniclePartyUpgradeAdapter.Bool(returnedToConversation));
        ChroniclePartyUpgradeAdapter.Property(json, "gameStateAfter", stateName);
        json.Append(",\"playerGoldBefore\":").Append(playerGoldBefore);
        json.Append(",\"playerGoldAfter\":").Append(Hero.MainHero.Gold);
        json.Append(",\"otherGoldBefore\":").Append(otherGoldBefore);
        json.Append(",\"otherGoldAfter\":").Append(data.OtherHero?.Gold ?? 0);
        json.Append(",\"otherHeroBaseRelationBefore\":").Append(otherHeroBaseRelationBefore);
        json.Append(",\"otherHeroBaseRelationAfter\":").Append(otherHero == null ? 0 : Hero.MainHero.GetBaseHeroRelation(otherHero));
        json.Append(",\"playerPartyFingerprintUnchanged\":").Append(ChroniclePartyUpgradeAdapter.Bool(string.Equals(playerPartyBefore, ItemRosterFingerprint(PartyBase.MainParty?.ItemRoster), StringComparison.Ordinal)));
        json.Append(",\"otherPartyFingerprintUnchanged\":").Append(ChroniclePartyUpgradeAdapter.Bool(string.Equals(otherPartyBefore, ItemRosterFingerprint(data.OtherParty?.ItemRoster), StringComparison.Ordinal)));
        json.Append(",\"campaignDayBefore\":").Append(dayBefore.ToString("F6", CultureInfo.InvariantCulture));
        json.Append(",\"campaignDayAfter\":").Append(CampaignTime.Now.ToDays.ToString("F6", CultureInfo.InvariantCulture));
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeBefore", timeModeBefore);
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeAfter", Campaign.Current.TimeControlMode.ToString());
        return json.Append('}').ToString();
    }

    internal static string SubmitOffer(string expectedSessionId = null, string expectedProposalFingerprint = null)
    {
        RequireCurrentPlayerBarter(out var data, out var viewModel);
        if (!string.IsNullOrWhiteSpace(expectedSessionId) || !string.IsNullOrWhiteSpace(expectedProposalFingerprint))
        {
            if (string.IsNullOrWhiteSpace(expectedSessionId) || string.IsNullOrWhiteSpace(expectedProposalFingerprint))
                throw new InvalidOperationException("expected Native BarterVM session and proposal fingerprint must be supplied together");
            if (!string.Equals(_sessionId, expectedSessionId, StringComparison.Ordinal))
                throw new InvalidOperationException("the active Native BarterVM session changed after the quoted proposal");
            var currentFingerprint = BuildProposalFingerprint(data, viewModel, CollectCandidates(data, viewModel));
            if (!string.Equals(currentFingerprint, expectedProposalFingerprint, StringComparison.Ordinal))
                throw new InvalidOperationException("the active Native BarterVM proposal changed after the quoted proposal");
        }
        if (viewModel.IsOfferDisabled) throw new InvalidOperationException("Native BarterVM disables Offer for the current proposal; no world transaction was submitted");
        var otherHero = data.OtherHero;
        var offererGoldBefore = data.OffererHero?.Gold ?? 0;
        var otherGoldBefore = otherHero?.Gold ?? 0;
        var offererPartyBefore = ItemRosterFingerprint(data.OffererParty?.ItemRoster);
        var otherPartyBefore = ItemRosterFingerprint(data.OtherParty?.ItemRoster);
        var mainHeroRelationBefore = otherHero == null ? 0 : Hero.MainHero.GetBaseHeroRelation(otherHero);
        var dayBefore = CampaignTime.Now.ToDays;
        var timeModeBefore = Campaign.Current.TimeControlMode.ToString();
        viewModel.ExecuteOffer();
        var accepted = Campaign.Current.BarterManager.LastBarterIsAccepted;
        var json = new StringBuilder(1400);
        json.Append('{').Append("\"schemaVersion\":1");
        json.Append(",\"submitted\":true,\"accepted\":").Append(ChroniclePartyUpgradeAdapter.Bool(accepted));
        json.Append(",\"offererGoldBefore\":").Append(offererGoldBefore);
        json.Append(",\"offererGoldAfter\":").Append(data.OffererHero?.Gold ?? 0);
        json.Append(",\"otherGoldBefore\":").Append(otherGoldBefore);
        json.Append(",\"otherGoldAfter\":").Append(otherHero?.Gold ?? 0);
        ChroniclePartyUpgradeAdapter.Property(json, "offererPartyFingerprintBefore", offererPartyBefore);
        ChroniclePartyUpgradeAdapter.Property(json, "offererPartyFingerprintAfter", ItemRosterFingerprint(data.OffererParty?.ItemRoster));
        ChroniclePartyUpgradeAdapter.Property(json, "otherPartyFingerprintBefore", otherPartyBefore);
        ChroniclePartyUpgradeAdapter.Property(json, "otherPartyFingerprintAfter", ItemRosterFingerprint(data.OtherParty?.ItemRoster));
        json.Append(",\"otherHeroBaseRelationBefore\":").Append(mainHeroRelationBefore);
        json.Append(",\"otherHeroBaseRelationAfter\":").Append(otherHero == null ? 0 : Hero.MainHero.GetBaseHeroRelation(otherHero));
        json.Append(",\"campaignDayBefore\":").Append(dayBefore.ToString("F6", CultureInfo.InvariantCulture));
        json.Append(",\"campaignDayAfter\":").Append(CampaignTime.Now.ToDays.ToString("F6", CultureInfo.InvariantCulture));
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeBefore", timeModeBefore);
        ChroniclePartyUpgradeAdapter.Property(json, "timeControlModeAfter", Campaign.Current.TimeControlMode.ToString());
        ChroniclePartyUpgradeAdapter.Property(json, "gameStateAfter", Game.Current?.GameStateManager?.ActiveState?.GetType().Name);
        return json.Append('}').ToString();
    }

    private static List<Candidate> CollectCandidates(BarterData data, BarterVM viewModel)
    {
        var result = new List<Candidate>();
        var seen = new HashSet<BarterItemVM>();
        AddCandidateList(result, seen, data, viewModel.LeftFiefList, "leftFief");
        AddCandidateList(result, seen, data, viewModel.RightFiefList, "rightFief");
        AddCandidateList(result, seen, data, viewModel.LeftPrisonerList, "leftPrisoner");
        AddCandidateList(result, seen, data, viewModel.RightPrisonerList, "rightPrisoner");
        AddCandidateList(result, seen, data, viewModel.LeftItemList, "leftItem");
        AddCandidateList(result, seen, data, viewModel.RightItemList, "rightItem");
        AddCandidateList(result, seen, data, viewModel.LeftOtherList, "leftOther");
        AddCandidateList(result, seen, data, viewModel.RightOtherList, "rightOther");
        AddCandidateList(result, seen, data, viewModel.LeftDiplomaticList, "leftDiplomatic");
        AddCandidateList(result, seen, data, viewModel.RightDiplomaticList, "rightDiplomatic");
        AddCandidateList(result, seen, data, viewModel.LeftGoldList, "leftGold");
        AddCandidateList(result, seen, data, viewModel.RightGoldList, "rightGold");
        AddCandidateList(result, seen, data, viewModel.LeftOfferList, "leftOffer");
        AddCandidateList(result, seen, data, viewModel.RightOfferList, "rightOffer");
        return result;
    }

    private static void AddCandidateList(List<Candidate> output, HashSet<BarterItemVM> seen, BarterData data, IEnumerable<BarterItemVM> items, string listId)
    {
        foreach (var item in items ?? Enumerable.Empty<BarterItemVM>())
        {
            if (item?.Barterable == null || !seen.Add(item)) continue;
            var index = data.GetBarterables().FindIndex(candidate => ReferenceEquals(candidate, item.Barterable));
            if (index < 0) continue;
            output.Add(new Candidate { Index = index, Barterable = item.Barterable, ViewModel = item, ListId = listId });
        }
    }

    private static void AppendCandidate(StringBuilder json, BarterData data, Candidate candidate)
    {
        var item = candidate.ViewModel;
        var id = BuildCandidateId(candidate.Index);
        _lastObservedCandidates[id] = candidate;
        var barterable = candidate.Barterable;
        var playerFaction = Hero.MainHero.MapFaction;
        var otherFaction = data.OtherHero?.MapFaction;
        json.Append('{');
        ChroniclePartyUpgradeAdapter.Property(json, "candidateId", id, addComma: false);
        ChroniclePartyUpgradeAdapter.Property(json, "nativeType", barterable.StringID);
        ChroniclePartyUpgradeAdapter.Property(json, "list", candidate.ListId);
        ChroniclePartyUpgradeAdapter.Property(json, "name", barterable.Name?.ToString());
        ChroniclePartyUpgradeAdapter.Property(json, "originalOwnerHeroId", barterable.OriginalOwner?.StringId);
        ChroniclePartyUpgradeAdapter.Property(json, "originalPartyId", barterable.OriginalParty?.Id);
        json.Append(",\"isContextDependent\":").Append(ChroniclePartyUpgradeAdapter.Bool(barterable.IsContextDependent));
        json.Append(",\"currentAmount\":").Append(item.CurrentOfferedAmount);
        json.Append(",\"maxAmount\":").Append(item.TotalItemCount);
        json.Append(",\"isOffered\":").Append(ChroniclePartyUpgradeAdapter.Bool(barterable.IsOffered));
        json.Append(",\"isTransferable\":").Append(ChroniclePartyUpgradeAdapter.Bool(item.IsItemTransferrable));
        json.Append(",\"valueForPlayerFaction\":").Append(playerFaction == null ? 0 : barterable.GetValueForFaction(playerFaction));
        json.Append(",\"valueForOtherFaction\":").Append(otherFaction == null ? 0 : barterable.GetValueForFaction(otherFaction));
        if (barterable is ItemBarterable itemBarterable)
        {
            var element = itemBarterable.ItemRosterElement.EquipmentElement;
            ChroniclePartyUpgradeAdapter.Property(json, "itemId", element.Item?.StringId);
            ChroniclePartyUpgradeAdapter.Property(json, "modifierId", element.ItemModifier?.StringId);
            json.Append(",\"isFood\":").Append(ChroniclePartyUpgradeAdapter.Bool(element.Item?.IsFood ?? false));
        }
        json.Append('}');
    }

    private static string BuildCandidateId(int index) => _sessionId + ":" + _generation.ToString(CultureInfo.InvariantCulture) + ":" + index.ToString(CultureInfo.InvariantCulture);

    private static string BuildProposalFingerprint(BarterData data, BarterVM viewModel, IReadOnlyList<Candidate> candidates)
    {
        var canonical = new StringBuilder(1024);
        void Add(string value) => canonical.Append(value.Length).Append(':').Append(value).Append('|');
        Add(_sessionId ?? string.Empty);
        Add(data.ContextInitializer?.Method?.Name ?? string.Empty);
        Add((Hero.MainHero?.Gold ?? 0).ToString(CultureInfo.InvariantCulture));
        Add(viewModel.IsOfferDisabled ? "1" : "0");
        Add(viewModel.ResultBarOffererPercentage.ToString(CultureInfo.InvariantCulture));
        Add(viewModel.ResultBarOtherPercentage.ToString(CultureInfo.InvariantCulture));
        foreach (var candidate in candidates.OrderBy(item => item.Index))
        {
            Add(candidate.Index.ToString(CultureInfo.InvariantCulture));
            Add(candidate.Barterable.StringID ?? string.Empty);
            Add(candidate.ListId ?? string.Empty);
            Add(candidate.Barterable.OriginalOwner?.StringId ?? string.Empty);
            Add(candidate.Barterable.OriginalParty?.Id ?? string.Empty);
            Add(candidate.ViewModel.CurrentOfferedAmount.ToString(CultureInfo.InvariantCulture));
            Add(candidate.Barterable.IsOffered ? "1" : "0");
        }
        using (var sha256 = SHA256.Create())
            return BitConverter.ToString(sha256.ComputeHash(Encoding.UTF8.GetBytes(canonical.ToString()))).Replace("-", string.Empty);
    }

    private static void RequireCurrentPlayerBarter(out BarterData data, out BarterVM viewModel)
    {
        data = _activeData;
        viewModel = _activeViewModel;
        if (data == null || viewModel == null || string.IsNullOrEmpty(_sessionId)) throw new InvalidOperationException("there is no active Native BarterVM captured from the game's current BarterBegin event");
        if (!IsSupportedPlayerContext(data)) throw new InvalidOperationException("the active Native BarterVM is not a player-initiated Barter context");
        if (Game.Current?.GameStateManager?.ActiveState == null) throw new InvalidOperationException("the current Native BarterVM has no active GameState host");
    }

    private static bool IsSupportedPlayerContext(BarterData data)
    {
        return data != null && !data.IsAiBarter && Hero.MainHero != null && data.OffererHero == Hero.MainHero;
    }

    private static string DescribeContext(BarterData data)
    {
        if (data.ContextInitializer == null && data.GetBarterables().All(item => !item.IsContextDependent)) return "ordinary";
        var fixedTypes = data.GetBarterables().Where(item => item.IsContextDependent).Select(item => item.StringID).Distinct().OrderBy(id => id, StringComparer.Ordinal);
        return "contextual:" + string.Join(",", fixedTypes);
    }

    private static string ItemRosterFingerprint(ItemRoster roster)
    {
        if (roster == null) return "null";
        var values = new List<string>();
        for (var index = 0; index < roster.Count; index++)
        {
            var element = roster.GetElementCopyAtIndex(index).EquipmentElement;
            values.Add((element.Item?.StringId ?? "<none>") + ":" + (element.ItemModifier?.StringId ?? "") + ":" + roster.GetElementNumber(index).ToString(CultureInfo.InvariantCulture));
        }
        return string.Join("|", values.OrderBy(value => value, StringComparer.Ordinal));
    }
}
