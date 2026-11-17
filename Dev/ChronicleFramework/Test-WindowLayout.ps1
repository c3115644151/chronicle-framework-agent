$script:ChronicleTestWindowWidth = 840
$script:ChronicleTestWindowHeight = 472
$script:ChronicleTestWindowX = 0
$script:ChronicleTestWindowY = 0
$script:ChronicleTempDirectory = if ([string]::IsNullOrWhiteSpace($env:CHRONICLE_HARNESS_TEMP)) {
    Join-Path $PSScriptRoot 'TestResults\Temp'
} else {
    [IO.Path]::GetFullPath($env:CHRONICLE_HARNESS_TEMP)
}
New-Item -ItemType Directory -Path $script:ChronicleTempDirectory -Force | Out-Null

if (-not ('ChronicleFramework.WindowApi' -as [type])) {
    $previousTemp = [Environment]::GetEnvironmentVariable('TEMP', 'Process')
    $previousTmp = [Environment]::GetEnvironmentVariable('TMP', 'Process')
    [Environment]::SetEnvironmentVariable('TEMP', $script:ChronicleTempDirectory, 'Process')
    [Environment]::SetEnvironmentVariable('TMP', $script:ChronicleTempDirectory, 'Process')
    try {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace ChronicleFramework
{
    public static class WindowApi
    {
        public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
        [StructLayout(LayoutKind.Sequential)]
        public struct Rect { public int Left; public int Top; public int Right; public int Bottom; }
        [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
        [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
        [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder className, int maxCount);
        [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW", SetLastError = true)] public static extern IntPtr GetWindowLongPtr(IntPtr hWnd, int index);
        [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW", SetLastError = true)] public static extern IntPtr SetWindowLongPtr(IntPtr hWnd, int index, IntPtr value);
        [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll", SetLastError = true)] public static extern bool GetClipCursor(out Rect rect);
        [DllImport("user32.dll")] public static extern int GetSystemMetrics(int index);
        [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int command);
        [DllImport("user32.dll", SetLastError = true)] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int width, int height, uint flags);
        [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out Rect rect);
        [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hWnd, out Rect rect);

        public static long AddNoActivateExtendedStyle(long currentStyle)
        {
            return currentStyle | 0x08000000L;
        }
        public static bool HasNoActivateExtendedStyle(long currentStyle)
        {
            return (currentStyle & 0x08000000L) != 0;
        }
        public static bool EnsureNoActivate(IntPtr hWnd)
        {
            if (hWnd == IntPtr.Zero) return false;
            const int GWL_EXSTYLE = -20;
            var currentStyle = GetWindowLongPtr(hWnd, GWL_EXSTYLE).ToInt64();
            var requestedStyle = AddNoActivateExtendedStyle(currentStyle);
            if (requestedStyle != currentStyle) SetWindowLongPtr(hWnd, GWL_EXSTYLE, new IntPtr(requestedStyle));
            var actualStyle = GetWindowLongPtr(hWnd, GWL_EXSTYLE).ToInt64();
            return HasNoActivateExtendedStyle(actualStyle);
        }

        public static int GetForegroundProcessId()
        {
            var foreground = GetForegroundWindow();
            if (foreground == IntPtr.Zero) return 0;
            uint processId;
            GetWindowThreadProcessId(foreground, out processId);
            return unchecked((int)processId);
        }

        public static IntPtr FindProcessWindow(int targetProcessId)
        {
            IntPtr best = IntPtr.Zero;
            long bestScore = -1;
            EnumWindows(delegate(IntPtr handle, IntPtr ignored) {
                uint processId;
                GetWindowThreadProcessId(handle, out processId);
                if (processId != targetProcessId) return true;
                Rect rect;
                GetWindowRect(handle, out rect);
                long area = Math.Max(0, rect.Right - rect.Left) * (long)Math.Max(0, rect.Bottom - rect.Top);
                var title = new StringBuilder(512);
                GetWindowText(handle, title, title.Capacity);
                long score = area + (title.ToString().IndexOf("Bannerlord", StringComparison.OrdinalIgnoreCase) >= 0 ? 1000000000L : 0L) + (IsWindowVisible(handle) ? 10000000L : 0L);
                if (score > bestScore) { best = handle; bestScore = score; }
                return true;
            }, IntPtr.Zero);
            return best;
        }
    }
}
'@
    }
    finally {
        [Environment]::SetEnvironmentVariable('TEMP', $previousTemp, 'Process')
        [Environment]::SetEnvironmentVariable('TMP', $previousTmp, 'Process')
    }
}

function Set-ChronicleTestDisplayConfig([string]$EngineConfigPath) {
    if (-not (Test-Path $EngineConfigPath)) { return }
    $text = Get-Content $EngineConfigPath -Raw
    $text = $text -replace '(?m)^display_mode\s*=.*$', 'display_mode = 0'
    $text = $text -replace '(?m)^display_width\s*=.*$', "display_width = $script:ChronicleTestWindowWidth"
    $text = $text -replace '(?m)^display_height\s*=.*$', "display_height = $script:ChronicleTestWindowHeight"
    $text = $text -replace '(?m)^max_framerate\s*=.*$', 'max_framerate = 30'
    $text = $text -replace '(?m)^safely_exited\s*=\s*0$', 'safely_exited = 1'
    Set-Content -Path $EngineConfigPath -Value $text -NoNewline
}

function Set-ChronicleTestWindow([int]$ProcessId) {
    if (-not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) { return $null }
    $handle = [ChronicleFramework.WindowApi]::FindProcessWindow($ProcessId)
    if ($handle -eq [IntPtr]::Zero) { return $null }
    $rawApplied = $false
    $nonActivating = [ChronicleFramework.WindowApi]::EnsureNoActivate($handle)
    $foregroundProcessId = 0
    $notForeground = $false
    $cursorClip = New-Object ChronicleFramework.WindowApi+Rect
    $cursorClipRead = $false
    $cursorUnrestrictedAcrossDesktop = $false
    $visible = $false
    $iconic = $true
    for ($attempt = 0; $attempt -lt 12; $attempt++) {
        $nonActivating = [ChronicleFramework.WindowApi]::EnsureNoActivate($handle)
        [ChronicleFramework.WindowApi]::ShowWindowAsync($handle, 4) | Out-Null
        # Keep the game visible for capture, but do not activate it or raise it above the user's windows.
        $rawApplied = [ChronicleFramework.WindowApi]::SetWindowPos($handle, [IntPtr]::Zero, $script:ChronicleTestWindowX, $script:ChronicleTestWindowY, $script:ChronicleTestWindowWidth, $script:ChronicleTestWindowHeight, 0x0074)
        Start-Sleep -Milliseconds 100
        $foregroundProcessId = [ChronicleFramework.WindowApi]::GetForegroundProcessId()
        # Window foreground must not belong to the harness client, including during 3D Missions.
        $notForeground = $foregroundProcessId -ne $ProcessId
        $cursorClipRead = [ChronicleFramework.WindowApi]::GetClipCursor([ref]$cursorClip)
        $virtualLeft = [ChronicleFramework.WindowApi]::GetSystemMetrics(76)
        $virtualTop = [ChronicleFramework.WindowApi]::GetSystemMetrics(77)
        $virtualRight = $virtualLeft + [ChronicleFramework.WindowApi]::GetSystemMetrics(78)
        $virtualBottom = $virtualTop + [ChronicleFramework.WindowApi]::GetSystemMetrics(79)
        $cursorUnrestrictedAcrossDesktop = $cursorClipRead -and
            $cursorClip.Left -le $virtualLeft -and $cursorClip.Top -le $virtualTop -and
            $cursorClip.Right -ge $virtualRight -and $cursorClip.Bottom -ge $virtualBottom
        $visible = [ChronicleFramework.WindowApi]::IsWindowVisible($handle)
        $iconic = [ChronicleFramework.WindowApi]::IsIconic($handle)
        if ($visible -and -not $iconic -and $nonActivating -and $notForeground -and $cursorUnrestrictedAcrossDesktop) { break }
    }
    $rect = New-Object ChronicleFramework.WindowApi+Rect
    $measured = [ChronicleFramework.WindowApi]::GetWindowRect($handle, [ref]$rect)
    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    $withinExpectedBounds = [Math]::Abs($rect.Left - $script:ChronicleTestWindowX) -le 1 -and
        [Math]::Abs($rect.Top - $script:ChronicleTestWindowY) -le 1 -and
        [Math]::Abs($width - $script:ChronicleTestWindowWidth) -le 1 -and
        [Math]::Abs($height - $script:ChronicleTestWindowHeight) -le 1
    [pscustomobject]@{
        Applied = ($rawApplied -and $nonActivating -and $notForeground -and $cursorUnrestrictedAcrossDesktop -and $measured -and $visible -and -not $iconic -and $withinExpectedBounds)
        NonActivating = $nonActivating
        NotForeground = $notForeground
        ForegroundProcessId = $foregroundProcessId
        CursorClipRead = $cursorClipRead
        CursorUnrestrictedAcrossDesktop = $cursorUnrestrictedAcrossDesktop
        CursorClipRectangle = [ordered]@{ Left = $cursorClip.Left; Top = $cursorClip.Top; Right = $cursorClip.Right; Bottom = $cursorClip.Bottom }
        Visible = $visible; Minimized = $iconic
        X = $rect.Left; Y = $rect.Top; Width = $width; Height = $height; DisplayMode = 0
    }
}

function Test-ChronicleNoActivateStyleContract {
    $original = [long]0x00040000
    $updated = [ChronicleFramework.WindowApi]::AddNoActivateExtendedStyle($original)
    return ([ChronicleFramework.WindowApi]::HasNoActivateExtendedStyle($updated) -and
        ($updated -band $original) -eq $original -and
        -not [ChronicleFramework.WindowApi]::HasNoActivateExtendedStyle($original))
}
