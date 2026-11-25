using System;

namespace ChronicleFramework;

// The Harness modes that own the screen. Three call sites used to spell out their own copy of this
// list (the input lock, captureFrame, the failure frame), so adding a visual fixture mode meant
// updating each one separately and silently losing frames or the input lock when one was missed.
internal static class HarnessScreenModes
{
    internal static bool IsCurrent() =>
        Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE") is "visual-capture" or "visual-battle-fixture" or "visual-opponent-fixture" or "battle-fixture" or "solo-battle-fixture";
}
