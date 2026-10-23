using System;
using System.Reflection;
using System.Text;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.GameState;
using TaleWorlds.Core;
using TaleWorlds.Library;
using TaleWorlds.ScreenSystem;

namespace ChronicleFramework;

internal static class ChronicleAgentBannerEditor
{
    private const string NativeScreenTypeName = "SandBox.GauntletUI.BannerEditor.GauntletBannerEditorScreen";
    private const string NativeViewModelTypeName = "TaleWorlds.CampaignSystem.ViewModelCollection.BannerEditorVM";

    internal static string BuildJson()
    {
        var state = Game.Current?.GameStateManager?.ActiveState as BannerEditorState;
        if (state == null) return "{\"schemaVersion\":1,\"active\":false}";
        if (!TryGetCurrentEditor(state, out var view, out var viewModel, out var failure))
            return "{\"schemaVersion\":1,\"active\":true,\"supported\":false,\"reason\":\"" + Escape(failure) + "\"}";

        var bannerViewModel = ReadProperty(viewModel, "BannerVM");
        var banner = ReadProperty(bannerViewModel, "Banner");
        var bannerCode = banner?.GetType().GetMethod("Serialize", BindingFlags.Instance | BindingFlags.Public, null, Type.EmptyTypes, null)?.Invoke(banner, null) as string;
        var json = new StringBuilder(768);
        json.Append("{\"schemaVersion\":1,\"active\":true,\"supported\":true");
        ChroniclePartyUpgradeAdapter.Property(json, "clanName", state.GetClan()?.Name?.ToString());
        ChroniclePartyUpgradeAdapter.Property(json, "title", ReadString(viewModel, "Title"));
        ChroniclePartyUpgradeAdapter.Property(json, "description", ReadString(viewModel, "Description"));
        ChroniclePartyUpgradeAdapter.Property(json, "doneText", ReadString(viewModel, "DoneText"));
        ChroniclePartyUpgradeAdapter.Property(json, "cancelText", ReadString(viewModel, "CancelText"));
        ChroniclePartyUpgradeAdapter.Property(json, "bannerCode", bannerCode);
        ChroniclePartyUpgradeAdapter.Property(json, "iconCodes", ReadString(viewModel, "IconCodes"));
        ChroniclePartyUpgradeAdapter.Property(json, "colorCodes", ReadString(viewModel, "ColorCodes"));
        ChroniclePartyUpgradeAdapter.Property(json, "currentIconSize", ReadProperty(viewModel, "CurrentIconSize")?.ToString());
        json.Append(",\"canChangeBackgroundColor\":").Append(ChroniclePartyUpgradeAdapter.Bool(ReadBoolean(viewModel, "CanChangeBackgroundColor")));
        json.Append('}');
        return json.ToString();
    }

    internal static string CompleteCurrentEditor()
    {
        var state = Game.Current?.GameStateManager?.ActiveState as BannerEditorState;
        if (state == null) throw new InvalidOperationException("bannerEditorDone requires the current Native BannerEditorState");
        if (!TryGetCurrentEditor(state, out _, out var viewModel, out var failure))
            throw new InvalidOperationException("bannerEditorDone requires the current supported Native BannerEditorState: " + failure);
        if (string.IsNullOrWhiteSpace(ReadString(viewModel, "DoneText")))
            throw new InvalidOperationException("The current Native banner editor does not expose its Done choice");

        var bannerViewModel = ReadProperty(viewModel, "BannerVM");
        var banner = ReadProperty(bannerViewModel, "Banner");
        var bannerCodeBefore = banner?.GetType().GetMethod("Serialize", BindingFlags.Instance | BindingFlags.Public, null, Type.EmptyTypes, null)?.Invoke(banner, null) as string;
        var done = viewModel.GetType().GetMethod("ExecuteDone", BindingFlags.Instance | BindingFlags.Public, null, Type.EmptyTypes, null);
        if (done == null) throw new MissingMethodException(viewModel.GetType().FullName, "ExecuteDone()");
        done.Invoke(viewModel, null);
        var editorStillActive = Game.Current?.GameStateManager?.ActiveState is BannerEditorState;
        if (editorStillActive) throw new InvalidOperationException("Native BannerEditorVM.ExecuteDone did not leave BannerEditorState");

        var json = new StringBuilder(512);
        json.Append("{\"schemaVersion\":1,\"status\":\"completed\"");
        ChroniclePartyUpgradeAdapter.Property(json, "nativeHandler", "BannerEditorVM.ExecuteDone");
        ChroniclePartyUpgradeAdapter.Property(json, "clanNameAfter", Clan.PlayerClan?.Name?.ToString());
        ChroniclePartyUpgradeAdapter.Property(json, "bannerCodeBefore", bannerCodeBefore);
        json.Append(",\"editorStillActive\":false");
        if (InformationManager.IsAnyInquiryActive())
            json.Append(",\"followUpInquiry\":").Append(ChronicleInquiryAdapter.BuildMapInquiryJson());
        return json.Append('}').ToString();
    }

    private static bool TryGetCurrentEditor(BannerEditorState state, out object view, out object viewModel, out string failure)
    {
        view = null;
        viewModel = null;
        failure = null;
        var screen = ScreenManager.TopScreen;
        if (screen?.GetType().FullName != NativeScreenTypeName)
        {
            failure = "The active Native screen is not the original BannerEditor screen";
            return false;
        }
        var layer = screen.GetType().GetField("_bannerEditorLayer", BindingFlags.Instance | BindingFlags.NonPublic)?.GetValue(screen);
        if (layer == null)
        {
            failure = "The original BannerEditor screen has no current Native view";
            return false;
        }
        view = layer;
        var dataSource = layer.GetType().GetProperty("DataSource", BindingFlags.Instance | BindingFlags.Public)?.GetValue(layer);
        if (dataSource?.GetType().FullName != NativeViewModelTypeName)
        {
            failure = "The current BannerEditor view model is not the verified 1.4.8 Native VM";
            return false;
        }
        if (!ReferenceEquals(state.GetClan(), Clan.PlayerClan) || !ReferenceEquals(state.GetCharacter(), CharacterObject.PlayerCharacter))
        {
            failure = "The BannerEditor is not bound to the MainHero's player clan";
            return false;
        }
        viewModel = dataSource;
        return true;
    }

    private static object ReadProperty(object source, string name) => source?.GetType().GetProperty(name, BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)?.GetValue(source);
    private static string ReadString(object source, string name) => ReadProperty(source, name)?.ToString();
    private static bool ReadBoolean(object source, string name) => ReadProperty(source, name) is bool value && value;
    private static string Escape(string value) => (value ?? string.Empty).Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\r", "\\r").Replace("\n", "\\n");
}
