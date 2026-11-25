using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using SandBox;
using SandBox.View.Map;
using SandBox.View.Map.Managers;
using SandBox.View.Map.Visuals;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.Encounters;
using TaleWorlds.CampaignSystem.GameState;
using TaleWorlds.CampaignSystem.GameMenus;
using TaleWorlds.CampaignSystem.Issues;
using TaleWorlds.CampaignSystem.MapEvents;
using TaleWorlds.CampaignSystem.Party;
using TaleWorlds.CampaignSystem.Settlements;
using TaleWorlds.CampaignSystem.Settlements.Locations;
using TaleWorlds.CampaignSystem.ViewModelCollection.GameMenu.Recruitment;
using TaleWorlds.CampaignSystem.ViewModelCollection.GameMenu.Events;
using TaleWorlds.Core;
using TaleWorlds.InputSystem;
using TaleWorlds.MountAndBlade;
using TaleWorlds.MountAndBlade.View.MissionViews;
using EngineTime = TaleWorlds.Engine.Time;

namespace ChronicleFramework;

internal sealed partial class ChronicleAgentProtocol
{
    private void WriteResponse(string commandId, string action, string status, ChronicleCampaignBehavior behavior, string error = null, string dataJson = null)
    {
        var response = "{\"nativeSessionId\":\"" + Escape(behavior.AgentRuntimeSessionId) + "\",\"protocolVersion\":1,\"commandId\":\"" + Escape(commandId) + "\",\"action\":\"" + Escape(action) + "\",\"status\":\"" + Escape(status) + "\",\"processId\":" + Process.GetCurrentProcess().Id + ",\"campaignDay\":" + CampaignTime.Now.ToDays.ToString("F3", CultureInfo.InvariantCulture) + ",\"dailyTickCount\":" + behavior.DailyTickCount + ",\"timeControlMode\":\"" + Escape(TaleWorlds.CampaignSystem.Campaign.Current.TimeControlMode.ToString()) + "\",\"state\":" + ChronicleAgentObserver.BuildSnapshotJson() + (dataJson == null ? "" : ",\"data\":" + dataJson) + (error == null ? "" : ",\"error\":\"" + Escape(error) + "\"") + "}";
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
                AppendBoundedProtocolEventLog(response);
                return;
            }
            catch (IOException) when (attempt < 4)
            {
                System.Threading.Thread.Sleep(20);
            }
        }
    }

    private void AppendBoundedProtocolEventLog(string response)
    {
        var path = Path.Combine(_root, "events.jsonl");
        var incomingBytes = Encoding.UTF8.GetByteCount(response) + Encoding.UTF8.GetByteCount(Environment.NewLine);
        var currentBytes = File.Exists(path) ? new FileInfo(path).Length : 0L;
        if (currentBytes + incomingBytes > MaxProtocolEventLogBytes)
            File.WriteAllText(path, string.Empty, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
        File.AppendAllText(path, response + Environment.NewLine, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
    }

    private static string SanitizeFileName(string value)
    {
        var result = value ?? string.Empty;
        foreach (var invalidCharacter in Path.GetInvalidFileNameChars()) result = result.Replace(invalidCharacter, '_');
        return string.IsNullOrWhiteSpace(result) ? "unknown" : result;
    }

    private static void TryCaptureUnexpectedProtocolFailureFrame(string commandId, string action, Exception exception)
    {
        if (_unexpectedProtocolFailureFrameCaptured || exception is InvalidOperationException) return;
        var mode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var rootValue = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if ((mode != "visual-capture" && mode != "visual-battle-fixture") || string.IsNullOrWhiteSpace(rootValue) || !Directory.Exists(rootValue)) return;

        _unexpectedProtocolFailureFrameCaptured = true;
        try
        {
            var root = Path.GetFullPath(rootValue).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
            var imagePath = Path.GetFullPath(Path.Combine(root, "protocol-unexpected-failure-frame.bmp"));
            if (!imagePath.StartsWith(root, StringComparison.OrdinalIgnoreCase)) return;
            TaleWorlds.Engine.Utilities.TakeScreenshot(imagePath);

            var gameState = Game.Current?.GameStateManager?.ActiveState?.GetType().Name ?? string.Empty;
            var menuId = Campaign.Current?.CurrentMenuContext?.GameMenu?.StringId ?? string.Empty;
            var timeMode = Campaign.Current?.TimeControlMode.ToString() ?? string.Empty;
            var campaignDayJson = Campaign.Current != null ? CampaignTime.Now.ToDays.ToString("R", CultureInfo.InvariantCulture) : "null";
            var stack = (exception.StackTrace ?? string.Empty).Replace("\r", " ").Replace("\n", " | ");
            var message = (exception.Message ?? string.Empty).Replace("\r", " ").Replace("\n", " | ");
            var metadata = "{\"commandId\":\"" + Escape(commandId) + "\",\"action\":\"" + Escape(action) + "\",\"exceptionType\":\"" + Escape(exception.GetType().FullName) + "\",\"message\":\"" + Escape(message) + "\",\"stackTrace\":\"" + Escape(stack) + "\",\"gameState\":\"" + Escape(gameState) + "\",\"menuId\":\"" + Escape(menuId) + "\",\"timeControlMode\":\"" + Escape(timeMode) + "\",\"campaignDay\":" + campaignDayJson + "}";
            File.WriteAllText(Path.Combine(root, "protocol-unexpected-failure-frame.json"), metadata, Encoding.UTF8);
            ChronicleDiagnostics.Write("protocol-unexpected-failure-frame-captured|action=" + Escape(action) + "|path=" + imagePath);
        }
        catch (Exception captureException)
        {
            ChronicleDiagnostics.Write("protocol-unexpected-failure-frame-capture-failed|type=" + captureException.GetType().Name + "|message=" + captureException.Message);
        }
    }
}
