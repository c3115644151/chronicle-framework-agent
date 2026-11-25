using System;
using HarmonyLib;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.BarterSystem;
using TaleWorlds.CampaignSystem.ViewModelCollection.Barter;

namespace ChronicleFramework;

internal static class ChronicleAgentBarterViewCapture
{
    private const string HarmonyId = "ChronicleFramework.NativeBarterViewCapture";
    private static bool _installed;

    internal static void Install()
    {
        if (_installed) return;
        try
        {
            var constructor = AccessTools.Constructor(typeof(BarterVM), new[] { typeof(BarterData) });
            var managerClose = AccessTools.Method(typeof(BarterManager), nameof(BarterManager.Close));
            var viewFinalize = AccessTools.Method(typeof(BarterVM), nameof(BarterVM.OnFinalize));
            var constructorPostfix = AccessTools.Method(typeof(ChronicleAgentBarterViewCapture), nameof(OnNativeViewConstructed));
            var closePostfix = AccessTools.Method(typeof(ChronicleAgentBarterViewCapture), nameof(OnNativeBarterClosed));
            var finalizePostfix = AccessTools.Method(typeof(ChronicleAgentBarterViewCapture), nameof(OnNativeViewFinalized));
            if (constructor == null || managerClose == null || viewFinalize == null || constructorPostfix == null || closePostfix == null || finalizePostfix == null)
            {
                ChronicleDiagnostics.Write("native-barter-view-capture-unavailable|reason=target-not-found");
                return;
            }

            var harmony = new Harmony(HarmonyId);
            harmony.Patch(constructor, postfix: new HarmonyMethod(constructorPostfix));
            harmony.Patch(managerClose, postfix: new HarmonyMethod(closePostfix));
            harmony.Patch(viewFinalize, postfix: new HarmonyMethod(finalizePostfix));
            _installed = true;
            ChronicleDiagnostics.Write("native-barter-view-capture-installed");
        }
        catch (Exception exception)
        {
            ChronicleDiagnostics.Write($"native-barter-view-capture-install-failed|type={exception.GetType().FullName}|message={exception.Message}");
        }
    }

    private static void OnNativeViewConstructed(BarterVM __instance, BarterData __0)
    {
        ChronicleDiagnostics.Write($"native-barter-vm-constructed|hasInstance={(__instance != null)}|offerer={__0?.OffererHero?.StringId}|other={__0?.OtherHero?.StringId}|context={(__0?.ContextInitializer != null)}|ai={(__0?.IsAiBarter ?? false)}");
        try { ChronicleAgentBarterAdapter.CaptureNativeViewModel(__0, __instance); }
        catch (Exception exception) { ChronicleDiagnostics.Write($"native-barter-vm-capture-failed|type={exception.GetType().FullName}|message={exception.Message}"); }
    }

    private static void OnNativeBarterClosed()
    {
        ChronicleAgentBarterAdapter.ClearNativeViewModel();
    }

    private static void OnNativeViewFinalized(BarterVM __instance)
    {
        ChronicleAgentBarterAdapter.ClearNativeViewModel(__instance);
    }
}
