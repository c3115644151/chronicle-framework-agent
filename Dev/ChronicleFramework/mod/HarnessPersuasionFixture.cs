using System;
using System.Collections;
using System.Linq;
using System.Reflection;
using System.Text;
using SandBox.View.Map;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.Conversation;
using TaleWorlds.CampaignSystem.Conversation.Persuasion;
using TaleWorlds.CampaignSystem.GameState;
using TaleWorlds.CampaignSystem.ViewModelCollection.Conversation;
using TaleWorlds.CampaignSystem.ViewModelCollection.Map.MapConversation;
using TaleWorlds.Core;
using TaleWorlds.Localization;

namespace ChronicleFramework;

internal static class HarnessPersuasionFixture
{
    internal static string ReadCurrentNativeAnswerList()
    {
        var mode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var root = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(mode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(root) || !System.IO.Directory.Exists(root))
            throw new InvalidOperationException("harnessCurrentConversationAnswers is restricted to a visual Harness run with a Harness temp directory.");
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("harnessCurrentConversationAnswers requires the Campaign Map state.");

        var manager = Campaign.Current?.ConversationManager;
        var mapView = MapScreen.Instance?.GetMapView<MapConversationView>();
        if (manager == null || !manager.IsConversationInProgress || mapView == null || !mapView.IsConversationActive)
            throw new InvalidOperationException("harnessCurrentConversationAnswers requires an active Native Map Conversation.");
        var dataSourceField = ReadPrivateField(mapView, "_dataSource");
        if (dataSourceField?.GetValue(mapView) is not MapConversationVM dataSource || dataSource.DialogController == null || dataSource.IsBarterActive)
            throw new InvalidOperationException("The active Native MapConversationVM is unavailable or showing Barter.");

        var answerList = dataSource.DialogController.AnswerList;
        var options = manager.CurOptions;
        var visibleOptions = new StringBuilder("[");
        for (var index = 0; index < answerList.Count; index++)
        {
            if (index > 0) visibleOptions.Append(',');
            var answer = answerList[index];
            if (answer.Index < 0 || answer.Index >= options.Count)
                throw new InvalidOperationException("The Native answer list contains an out-of-range option index.");
            visibleOptions.Append("{\"index\":").Append(answer.Index)
                .Append(",\"optionId\":\"").Append(Escape(options[answer.Index].Id))
                .Append("\",\"text\":\"").Append(Escape(answer.ItemText))
                .Append("\",\"persuasion\":").Append(answer.HasPersuasion ? "true" : "false")
                .Append(",\"enabled\":").Append(answer.IsEnabled && options[answer.Index].IsClickable ? "true" : "false").Append('}');
        }
        visibleOptions.Append(']');
        return "{\"nativeViewModel\":\"MapConversationVM.DialogController.AnswerList\",\"persuasionActive\":" + (ConversationManager.GetPersuasionIsActive() ? "true" : "false") +
            ",\"isLoadingOver\":" + (dataSource.DialogController.IsLoadingOver ? "true" : "false") + ",\"answerCount\":" + answerList.Count +
            ",\"currentOptionCount\":" + options.Count + ",\"continueButtonVisible\":" + (answerList.Count == 0 ? "true" : "false") +
            ",\"visibleOptions\":" + visibleOptions + "}";
    }

    internal static string SeedPersuasionForCurrentNativeOption(string optionId)
    {
        var mode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var root = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (!string.Equals(mode, "visual-capture", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(root) || !System.IO.Directory.Exists(root))
            throw new InvalidOperationException("Harness Persuasion fixture is restricted to a visual Harness run with a Harness temp directory.");
        if (Game.Current?.GameStateManager?.ActiveState is not MapState)
            throw new InvalidOperationException("Harness Persuasion fixture requires the Campaign Map state.");

        var manager = Campaign.Current?.ConversationManager;
        if (manager == null || !manager.IsConversationInProgress || ConversationManager.GetPersuasionIsActive())
            throw new InvalidOperationException("Harness Persuasion fixture requires a current Native Conversation without another active Persuasion.");
        if (string.IsNullOrWhiteSpace(optionId)) throw new InvalidOperationException("optionId must come from current Native Conversation options.");

        var optionIndex = manager.CurOptions.FindIndex(option => string.Equals(option.Id, optionId, StringComparison.Ordinal) && option.IsClickable);
        if (optionIndex < 0) throw new InvalidOperationException("Harness Persuasion fixture requires a currently clickable Native Conversation option.");
        var mapView = MapScreen.Instance?.GetMapView<MapConversationView>();
        var dataSourceField = ReadPrivateField(mapView, "_dataSource");
        if (mapView == null || !mapView.IsConversationActive || dataSourceField?.GetValue(mapView) is not MapConversationVM dataSource ||
            dataSource.IsBarterActive || !dataSource.DialogController.AnswerList.Any(answer => answer.Index == optionIndex && answer.IsEnabled))
            throw new InvalidOperationException("Harness Persuasion fixture requires the option to exist in the currently rendered, enabled Native AnswerList.");
        var selectedOption = manager.CurOptions[optionIndex];
        var visibleAnswer = dataSource.DialogController.AnswerList.First(answer => answer.Index == optionIndex && answer.IsEnabled);
        var sentencesField = typeof(ConversationManager).GetField("_sentences", BindingFlags.Instance | BindingFlags.NonPublic);
        if (sentencesField?.GetValue(manager) is not IList sentences || selectedOption.SentenceNo < 0 || selectedOption.SentenceNo >= sentences.Count)
            throw new InvalidOperationException("Native Conversation sentence storage does not match its currently observed option.");
        var sentence = sentences[selectedOption.SentenceNo];
        if (sentence == null) throw new InvalidOperationException("Native Conversation sentence is unavailable.");
        var sentenceType = sentence.GetType();
        var persuasionDelegateField = sentenceType.GetField("_onPersuasionOption", BindingFlags.Instance | BindingFlags.NonPublic);
        var delegateType = sentenceType.GetNestedType("OnPersuasionOptionDelegate", BindingFlags.Public | BindingFlags.NonPublic);
        var argumentFactory = typeof(HarnessPersuasionFixture).GetMethod(nameof(CreateHarnessPersuasionArgument), BindingFlags.Static | BindingFlags.NonPublic);
        if (persuasionDelegateField == null || delegateType == null || argumentFactory == null)
            throw new MissingMemberException(sentenceType.FullName, "_onPersuasionOption/OnPersuasionOptionDelegate");
        if (persuasionDelegateField.GetValue(sentence) != null)
            throw new InvalidOperationException("Selected Native Conversation sentence already has a Persuasion option; refusing to overwrite it.");

        ConversationManager.StartPersuasion(2f, 1f, 0f, 2f, 2f, 0f, PersuasionDifficulty.Medium);
        try
        {
            persuasionDelegateField.SetValue(sentence, Delegate.CreateDelegate(delegateType, argumentFactory));
            var persuasionArgument = CreateHarnessPersuasionArgument();
            var persuasionArgsProperty = sentenceType.GetProperty("PersuationOptionArgs", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
            var setPersuasionArgs = persuasionArgsProperty?.GetSetMethod(nonPublic: true);
            if (setPersuasionArgs == null) throw new MissingMethodException(sentenceType.FullName, "PersuationOptionArgs.set");
            setPersuasionArgs.Invoke(sentence, new object[] { persuasionArgument });

            var currentOption = manager.CurOptions[optionIndex];
            currentOption.HasPersuasion = true;
            currentOption.PersuationOptionArgs = persuasionArgument;
            manager.CurOptions[optionIndex] = currentOption;
            visibleAnswer.HasPersuasion = true;
            var readyMethodField = typeof(ConversationItemVM).GetField("_onReadyToContinue", BindingFlags.Instance | BindingFlags.NonPublic);
            if (readyMethodField?.GetValue(visibleAnswer) is not Action onReadyToContinue)
                throw new MissingFieldException(typeof(ConversationItemVM).FullName, "_onReadyToContinue");
            visibleAnswer.PersuasionItem = new PersuasionOptionVM(manager, optionIndex, onReadyToContinue);
            visibleAnswer.RefreshValues();
            dataSource.DialogController.Persuasion.RefreshPersusasion();

            if (!manager.CurOptions[optionIndex].HasPersuasion || !visibleAnswer.HasPersuasion || visibleAnswer.PersuasionItem == null)
                throw new InvalidOperationException("Native Persuasion option/view model was not installed on the current visible answer row.");
            var answerList = dataSource.DialogController.AnswerList;
            var answers = new StringBuilder();
            answers.Append('[');
            for (var index = 0; index < answerList.Count; index++)
            {
                if (index > 0) answers.Append(',');
                var answer = answerList[index];
                answers.Append("{\"index\":").Append(answer.Index)
                    .Append(",\"hasPersuasion\":").Append(answer.HasPersuasion ? "true" : "false")
                    .Append(",\"enabled\":").Append(answer.IsEnabled ? "true" : "false");
                if (answer.Index >= 0 && answer.Index < manager.CurOptions.Count)
                {
                    answers.Append(",\"optionId\":\"").Append(Escape(manager.CurOptions[answer.Index].Id)).Append('"');
                }
                answers.Append('}');
            }
            answers.Append(']');
            return "{\"fixture\":\"Harness-only Native PersuasionTask and PersuasionOptionVM bound to the current visible Native answer row\",\"optionId\":\"" + Escape(optionId) + "\",\"conversationIndex\":" + optionIndex + ",\"nativeOptionCount\":" + manager.CurOptions.Count + ",\"nativeAnswerCount\":" + answerList.Count + ",\"nativeAnswers\":" + answers + ",\"persuasionActive\":true}";
        }
        catch
        {
            ConversationManager.EndPersuasion();
            throw;
        }
    }

    private static PersuasionOptionArgs CreateHarnessPersuasionArgument()
    {
        return new PersuasionOptionArgs(DefaultSkills.Charm, null, TraitEffect.Positive, PersuasionArgumentStrength.Normal,
            givesCriticalSuccess: false, new TextObject("{=!}I can make a reasonable case."));
    }

    private static FieldInfo ReadPrivateField(object instance, string fieldName)
    {
        for (var type = instance?.GetType(); type != null; type = type.BaseType)
        {
            var field = type.GetField(fieldName, BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.DeclaredOnly);
            if (field != null) return field;
        }
        return null;
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
