using System;
using System.Collections.Generic;

namespace ChronicleFramework;

/// <summary>Maps only authoritative Native StoryMode/quest-history facts to a fail-closed lifecycle status.</summary>
public static class StoryModeEstablishClanLifecycleStatus
{
    public static string Classify(
        bool isStoryMode,
        bool tutorialCompleted,
        bool firstPhaseStarted,
        bool questActive,
        bool historicalResultAvailable,
        bool historicalResultUnsuccessful)
    {
        if (!isStoryMode) return "not-storymode";
        if (questActive) return "active";
        if (historicalResultAvailable) return historicalResultUnsuccessful ? "failed" : "completed";
        if (!tutorialCompleted || !firstPhaseStarted) return "storymode-not-activated";
        return "unknown";
    }

    public static IReadOnlyList<object> RunContractSelfTests()
    {
        var cases = new (bool StoryMode, bool TutorialCompleted, bool FirstPhaseStarted, bool QuestActive, bool History, bool Failed, string Expected)[]
        {
            (false, false, false, false, false, false, "not-storymode"),
            (true, false, false, false, false, false, "storymode-not-activated"),
            (true, true, true, true, false, false, "active"),
            (true, true, true, false, true, false, "completed"),
            (true, true, true, false, true, true, "failed"),
            (true, true, true, false, false, false, "unknown")
        };
        foreach (var item in cases)
        {
            var actual = Classify(item.StoryMode, item.TutorialCompleted, item.FirstPhaseStarted, item.QuestActive, item.History, item.Failed);
            if (!string.Equals(actual, item.Expected, StringComparison.Ordinal))
                throw new InvalidOperationException($"StoryMode Establish Your Clan lifecycle classification mismatch: expected={item.Expected}; actual={actual}.");
        }
        return [new { scenario = "storymode-establish-clan-lifecycle-distinguishes-mode-activation-active-completed-failed-and-unknown", passed = true, caseCount = cases.Length }];
    }
}
