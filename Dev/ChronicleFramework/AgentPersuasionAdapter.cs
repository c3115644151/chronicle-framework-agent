using System;
using System.Collections;
using System.Reflection;
using System.Text;
using SandBox.View.Map;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.Conversation;
using TaleWorlds.CampaignSystem.GameState;
using TaleWorlds.CampaignSystem.ViewModelCollection.Conversation;
using TaleWorlds.CampaignSystem.ViewModelCollection.Map.MapConversation;
using TaleWorlds.Core;

namespace ChronicleFramework;

internal static class ChroniclePersuasionAdapter
{
    internal static bool IsVisiblePersuasionOption(string optionId)
    {
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            return false;
        var manager = Campaign.Current?.ConversationManager;
        if (manager == null || string.IsNullOrWhiteSpace(optionId) || !manager.IsConversationInProgress || !ConversationManager.GetPersuasionIsActive())
            return false;

        var mapConversationView = MapScreen.Instance?.GetMapView<MapConversationView>();
        if (mapConversationView == null || !mapConversationView.IsConversationActive)
            return false;
        var dataSourceField = ReadPrivateField(mapConversationView, "_dataSource");
        if (dataSourceField?.GetValue(mapConversationView) is not MapConversationVM dataSource || dataSource.IsBarterActive)
            return false;
        var answerList = dataSource.DialogController?.AnswerList;
        var currentOptions = manager.CurOptions;
        if (answerList == null || currentOptions == null)
            return false;

        var currentIndex = currentOptions.FindIndex(option => string.Equals(option.Id, optionId, StringComparison.Ordinal) && option.IsClickable && option.HasPersuasion);
        if (currentIndex < 0)
            return false;

        foreach (var answer in answerList)
        {
            if (answer.Index == currentIndex && answer.HasPersuasion && answer.IsEnabled && answer.Index < currentOptions.Count &&
                string.Equals(currentOptions[answer.Index].Id, optionId, StringComparison.Ordinal))
                return true;
        }
        return false;
    }

    internal static string ReadCurrentPersuasion()
    {
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("persuasionDetails requires the Campaign Map state");

        var manager = Campaign.Current?.ConversationManager;
        if (manager == null || !manager.IsConversationInProgress)
            return Unavailable("noActiveConversation");
        if (!ConversationManager.GetPersuasionIsActive())
            return Unavailable("noActivePersuasionTask");

        var mapConversationView = MapScreen.Instance?.GetMapView<MapConversationView>();
        if (mapConversationView == null || !mapConversationView.IsConversationActive)
            return Unavailable("nativeMapConversationViewUnavailable");

        var dataSourceField = ReadPrivateField(mapConversationView, "_dataSource");
        if (dataSourceField?.GetValue(mapConversationView) is not MapConversationVM dataSource)
            return Unavailable("nativeMapConversationViewModelUnavailable");
        if (dataSource.IsBarterActive)
            return Unavailable("nativeBarterIsActive");

        var dialogController = dataSource.DialogController;
        var persuasion = dialogController?.Persuasion;
        if (persuasion == null || !persuasion.IsPersuasionActive)
            return Unavailable("nativePersuasionViewModelInactive");

        var currentOptions = manager.CurOptions;
        var answerList = dialogController.AnswerList;
        if (currentOptions == null || answerList == null)
            throw new InvalidOperationException("Native Persuasion or current Conversation options are unavailable");

        var speaker = Hero.OneToOneConversationHero;
        var progress = ConversationManager.GetPersuasionProgress();
        var goal = ConversationManager.GetPersuasionGoalValue();
        var json = new StringBuilder(1024);
        json.Append('{');
        json.Append("\"available\":true");
        json.Append(",\"nativeViewModel\":\"MapConversationVM.DialogController.Persuasion\"");
        AppendProperty(json, "speakerHeroId", speaker?.StringId);
        AppendProperty(json, "speakerName", speaker?.Name?.ToString());
        json.Append(",\"progress\":").Append(progress.ToString("R", System.Globalization.CultureInfo.InvariantCulture));
        json.Append(",\"goal\":").Append(goal.ToString("R", System.Globalization.CultureInfo.InvariantCulture));
        json.Append(",\"progressText\":");
        AppendQuoted(json, persuasion.ProgressText ?? string.Empty);
        json.Append(",\"progressIndicators\":[");
        for (var index = 0; index < persuasion.PersuasionProgress.Count; index++)
        {
            if (index > 0) json.Append(',');
            json.Append(persuasion.PersuasionProgress[index].IsActive ? "true" : "false");
        }
        json.Append("],\"options\":[");
        var outputCount = 0;
        foreach (var answer in answerList)
        {
            if (answer.Index < 0 || answer.Index >= currentOptions.Count)
                throw new InvalidOperationException("Native Persuasion option index is outside the current Conversation options");
            var currentOption = currentOptions[answer.Index];
            if (answer.HasPersuasion != currentOption.HasPersuasion)
                throw new InvalidOperationException("Native Persuasion VM and current Conversation option disagree; refusing to infer a mapping");
            if (!answer.HasPersuasion) continue;

            var persuasionOption = answer.PersuasionItem;
            if (persuasionOption == null)
                throw new InvalidOperationException("Native Persuasion option VM is missing for a visible Persuasion argument");
            if (outputCount++ > 0) json.Append(',');
            json.Append('{');
            json.Append("\"conversationIndex\":").Append(answer.Index);
            AppendProperty(json, "optionId", currentOption.Id);
            AppendProperty(json, "text", answer.ItemText);
            json.Append(",\"clickable\":").Append(answer.IsEnabled && currentOption.IsClickable ? "true" : "false");
            json.Append(",\"successChance\":").Append(persuasionOption.SuccessChance);
            json.Append(",\"failChance\":").Append(persuasionOption.FailChance);
            json.Append(",\"criticalSuccessChance\":").Append(persuasionOption.CritSuccessChance);
            json.Append(",\"criticalFailChance\":").Append(persuasionOption.CritFailChance);
            json.Append(",\"isProgressingOption\":").Append(persuasionOption.IsAProgressingOption ? "true" : "false");
            json.Append(",\"isBlockingOption\":").Append(persuasionOption.IsABlockingOption ? "true" : "false");
            json.Append('}');
        }
        json.Append("]}");
        return json.ToString();
    }

    private static string Unavailable(string reason) => "{\"available\":false,\"reason\":\"" + Escape(reason) + "\"}";

    private static FieldInfo ReadPrivateField(object instance, string fieldName)
    {
        for (var type = instance?.GetType(); type != null; type = type.BaseType)
        {
            var field = type.GetField(fieldName, BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.DeclaredOnly);
            if (field != null) return field;
        }
        return null;
    }

    private static void AppendProperty(StringBuilder json, string name, string value)
    {
        json.Append(',');
        AppendQuoted(json, name);
        json.Append(':');
        AppendQuoted(json, value ?? string.Empty);
    }

    private static void AppendQuoted(StringBuilder json, string value)
    {
        json.Append('"').Append(Escape(value)).Append('"');
    }

    private static string Escape(string value)
    {
        if (string.IsNullOrEmpty(value)) return string.Empty;
        var builder = new StringBuilder(value.Length + 8);
        foreach (var character in value)
        {
            switch (character)
            {
                case '\\': builder.Append("\\\\"); break;
                case '"': builder.Append("\\\""); break;
                case '\r': builder.Append("\\r"); break;
                case '\n': builder.Append("\\n"); break;
                case '\t': builder.Append("\\t"); break;
                default: builder.Append(character); break;
            }
        }
        return builder.ToString();
    }
}
