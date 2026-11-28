using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace ChronicleFramework;

/// <summary>
/// Gives the player a normal desktop window back. Harness capture runs used to leave the game window
/// pinned, non-activating and un-resizable; a player session must instead show a taskbar button,
/// raise on click, drag by its title bar and resize from its edges.
/// </summary>
internal static class AgentGameWindow
{
    private const long WsCaption = 0x00C00000L;
    private const long WsThickFrame = 0x00040000L;
    private const long WsSysMenu = 0x00080000L;
    private const long WsMinimizeBox = 0x00020000L;
    private const long WsMaximizeBox = 0x00010000L;
    private const long WsPopup = 0x80000000L;
    private const long WsExAppWindow = 0x00040000L;
    private const long WsExToolWindow = 0x00000080L;
    private const long WsExNoActivate = 0x08000000L;
    private const int GwlStyle = -16;
    private const int GwlExStyle = -20;
    private const uint SwpNoSize = 0x0001;
    private const uint SwpNoMove = 0x0002;
    private const uint SwpNoZOrder = 0x0004;
    private const uint SwpNoActivate = 0x0010;
    private const uint SwpFrameChanged = 0x0020;

    private static int _installed;

    public static void EnsurePlayerUsableWindow()
    {
        if (Interlocked.Exchange(ref _installed, 1) == 1) return;
        var thread = new Thread(WatchForWindow) { IsBackground = true, Name = "ChronicleAgentWindow" };
        thread.Start();
    }

    private static void WatchForWindow()
    {
        var interactiveCapture = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        var keepNonActivating = !string.IsNullOrWhiteSpace(interactiveCapture);
        for (var attempt = 0; attempt < 120; attempt++)
        {
            try
            {
                var handle = FindMainWindow(Process.GetCurrentProcess().Id);
                if (handle != IntPtr.Zero)
                {
                    Apply(handle, keepNonActivating);
                    return;
                }
            }
            catch (Exception exception)
            {
                ChronicleDiagnostics.Write($"agent-window-style-failed|type={exception.GetType().Name}|message={exception.Message}");
                return;
            }
            Thread.Sleep(500);
        }
        ChronicleDiagnostics.Write("agent-window-style-skipped|reason=no-main-window");
    }

    private static void Apply(IntPtr handle, bool keepNonActivating)
    {
        var style = GetWindowLongPtr(handle, GwlStyle).ToInt64();
        var exStyle = GetWindowLongPtr(handle, GwlExStyle).ToInt64();
        var requestedStyle = (style & ~WsPopup) | WsCaption | WsThickFrame | WsSysMenu | WsMinimizeBox | WsMaximizeBox;
        var requestedExStyle = (exStyle | WsExAppWindow) & ~WsExToolWindow;
        if (!keepNonActivating) requestedExStyle &= ~WsExNoActivate;
        if (requestedStyle != style) SetWindowLongPtr(handle, GwlStyle, new IntPtr(requestedStyle));
        if (requestedExStyle != exStyle) SetWindowLongPtr(handle, GwlExStyle, new IntPtr(requestedExStyle));
        SetWindowPos(handle, IntPtr.Zero, 0, 0, 0, 0, SwpFrameChanged | SwpNoMove | SwpNoSize | SwpNoZOrder | SwpNoActivate);
        var finalStyle = GetWindowLongPtr(handle, GwlStyle).ToInt64();
        var finalExStyle = GetWindowLongPtr(handle, GwlExStyle).ToInt64();
        ChronicleDiagnostics.Write(
            $"agent-window-style|caption={(finalStyle & WsCaption) != 0}|thickFrame={(finalStyle & WsThickFrame) != 0}|" +
            $"appWindow={(finalExStyle & WsExAppWindow) != 0}|toolWindow={(finalExStyle & WsExToolWindow) != 0}|" +
            $"noActivate={(finalExStyle & WsExNoActivate) != 0}|captureMode={keepNonActivating}");
    }

    private delegate bool EnumWindowsProc(IntPtr handle, IntPtr parameter);

    private static IntPtr FindMainWindow(int processId)
    {
        var best = IntPtr.Zero;
        long bestArea = -1;
        EnumWindows((handle, _) =>
        {
            uint owner;
            GetWindowThreadProcessId(handle, out owner);
            if (owner != processId || !IsWindowVisible(handle)) return true;
            Rect rect;
            if (!GetWindowRect(handle, out rect)) return true;
            var area = Math.Max(0, rect.Right - rect.Left) * (long)Math.Max(0, rect.Bottom - rect.Top);
            if (area <= bestArea) return true;
            var title = new StringBuilder(512);
            GetWindowText(handle, title, title.Capacity);
            if (title.Length == 0) return true;
            best = handle;
            bestArea = area;
            return true;
        }, IntPtr.Zero);
        return best;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect { public int Left; public int Top; public int Right; public int Bottom; }

    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr parameter);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr handle, out uint processId);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr handle);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr handle, out Rect rect);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(IntPtr handle, StringBuilder text, int count);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW", SetLastError = true)] private static extern IntPtr GetWindowLongPtr(IntPtr handle, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW", SetLastError = true)] private static extern IntPtr SetWindowLongPtr(IntPtr handle, int index, IntPtr value);
    [DllImport("user32.dll", SetLastError = true)] private static extern bool SetWindowPos(IntPtr handle, IntPtr insertAfter, int x, int y, int width, int height, uint flags);
}
