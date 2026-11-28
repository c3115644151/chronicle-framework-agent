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
    private const int GwOwner = -8;
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
        // The engine itself creates its window without activation. A player session must be a normal window, so the
        // mod never keeps WS_EX_NOACTIVATE; capture runs that must not steal the cursor re-apply it from the harness.
        const bool keepNonActivating = false;
        for (var attempt = 0; attempt < 120; attempt++)
        {
            try
            {
                var handle = FindMainWindow(Process.GetCurrentProcess().Id);
                if (handle != IntPtr.Zero)
                {
                    Apply(handle, keepNonActivating);
                    Thread.Sleep(4000);
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
        EnsureResizableHitTest(handle);
        RegisterTaskbarTab(handle);
        var style = GetWindowLongPtr(handle, GwlStyle).ToInt64();
        var exStyle = GetWindowLongPtr(handle, GwlExStyle).ToInt64();
        var owner = GetWindow(handle, GwOwner);
        ChronicleDiagnostics.Write(
            $"agent-window-style-before|style=0x{style:X8}|exStyle=0x{exStyle:X8}|owner={owner != IntPtr.Zero}|" +
            $"noActivate={(exStyle & WsExNoActivate) != 0}|popup={(style & WsPopup) != 0}|thickFrame={(style & WsThickFrame) != 0}");
        // An owned window never gets its own taskbar button, so drop the owner before publishing the styles.
        if (owner != IntPtr.Zero) SetWindowLongPtr(handle, GwOwner, IntPtr.Zero);
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

    private static IntPtr _originalWndProc = IntPtr.Zero;
    private static WndProcDelegate? _wndProcDelegate;
    private static bool _hitTestInstalled;

    private delegate IntPtr WndProcDelegate(IntPtr hWnd, uint message, IntPtr wParam, IntPtr lParam);

    private const uint WmNcHitTest = 0x0084;
    private const uint WmMouseActivate = 0x0021;
    private const int MaActivate = 1;
    private static bool _mouseActivateLogged;
    private const int HtClient = 1;
    private const int HtLeft = 10, HtRight = 11, HtTop = 12, HtTopLeft = 13, HtTopRight = 14, HtBottom = 15, HtBottomLeft = 16, HtBottomRight = 17;
    private const int ResizeBorder = 6;

    private static void EnsureResizableHitTest(IntPtr handle)
    {
        if (_hitTestInstalled || handle == IntPtr.Zero) return;
        _wndProcDelegate = HitTestWndProc;
        _originalWndProc = SetWindowLongPtr(handle, GwWndProc, Marshal.GetFunctionPointerForDelegate(_wndProcDelegate));
        if (_originalWndProc == IntPtr.Zero)
        {
            ChronicleDiagnostics.Write("agent-window-resize-hook-failed|reason=no-original-wndproc");
            return;
        }
        _hitTestInstalled = true;
        ChronicleDiagnostics.Write("agent-window-resize-hook-installed");
    }

    private static IntPtr HitTestWndProc(IntPtr hWnd, uint message, IntPtr wParam, IntPtr lParam)
    {
        if (message == WmMouseActivate)
        {
            // Game engines usually answer MA_NOACTIVATE, which is why a covered window stays behind even
            // after the caption and taskbar styles are restored. A click here is an explicit player action.
            if (!_mouseActivateLogged)
            {
                _mouseActivateLogged = true;
                ChronicleDiagnostics.Write("agent-window-mouse-activate|player-clicks-raise-window=True");
            }
            return new IntPtr(MaActivate);
        }
        if (message == WmNcHitTest)
        {
            var packed = lParam.ToInt64();
            var screenX = (short)(packed & 0xFFFF);
            var screenY = (short)((packed >> 16) & 0xFFFF);
            Rect rect;
            if (GetWindowRect(hWnd, out rect) && !IsZoomed(hWnd))
            {
                var onLeft = screenX >= rect.Left && screenX < rect.Left + ResizeBorder;
                var onRight = screenX <= rect.Right - 1 && screenX > rect.Right - ResizeBorder;
                var onTop = screenY >= rect.Top && screenY < rect.Top + ResizeBorder;
                var onBottom = screenY <= rect.Bottom - 1 && screenY > rect.Bottom - ResizeBorder;
                if (onTop && onLeft) return new IntPtr(HtTopLeft);
                if (onTop && onRight) return new IntPtr(HtTopRight);
                if (onBottom && onLeft) return new IntPtr(HtBottomLeft);
                if (onBottom && onRight) return new IntPtr(HtBottomRight);
                if (onLeft) return new IntPtr(HtLeft);
                if (onRight) return new IntPtr(HtRight);
                if (onTop) return new IntPtr(HtTop);
                if (onBottom) return new IntPtr(HtBottom);
            }
        }
        return CallWindowProc(_originalWndProc, hWnd, message, wParam, lParam);
    }

    private const int GwWndProc = -4;

    private static void RegisterTaskbarTab(IntPtr handle)
    {
        try
        {
            var taskbar = (ITaskbarList)Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("56FDF344-FD6D-11D0-958A-006097C9A090"))!)!;
            taskbar.HrInit();
            taskbar.AddTab(handle);
            Marshal.ReleaseComObject(taskbar);
            ChronicleDiagnostics.Write("agent-window-taskbar-tab|requested=True");
        }
        catch (Exception exception)
        {
            ChronicleDiagnostics.Write($"agent-window-taskbar-tab|requested=False|reason={exception.GetType().Name}");
        }
    }

    [ComImport, Guid("56FDF342-FD6D-11d0-958A-006097C9A090"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface ITaskbarList
    {
        void HrInit();
        void AddTab(IntPtr hwnd);
        void DeleteTab(IntPtr hwnd);
        void ActivateTab(IntPtr hwnd);
        void SetActiveAlt(IntPtr hwnd);
    }

    [DllImport("user32.dll", SetLastError = true)] private static extern bool IsZoomed(IntPtr handle);
    [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr CallWindowProc(IntPtr previous, IntPtr handle, uint message, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect { public int Left; public int Top; public int Right; public int Bottom; }

    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr parameter);
    [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr handle, int command);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr handle, out uint processId);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr handle);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr handle, out Rect rect);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(IntPtr handle, StringBuilder text, int count);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW", SetLastError = true)] private static extern IntPtr GetWindowLongPtr(IntPtr handle, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW", SetLastError = true)] private static extern IntPtr SetWindowLongPtr(IntPtr handle, int index, IntPtr value);
    [DllImport("user32.dll", SetLastError = true)] private static extern bool SetWindowPos(IntPtr handle, IntPtr insertAfter, int x, int y, int width, int height, uint flags);
}
