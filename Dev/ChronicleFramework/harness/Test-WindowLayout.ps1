#Requires -Version 7.0
$script:ChronicleTempDirectory = if ([string]::IsNullOrWhiteSpace($env:CHRONICLE_HARNESS_TEMP)) {
    Join-Path (Split-Path -Parent $PSScriptRoot) 'TestResults\Temp'
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
        [DllImport("user32.dll", SetLastError = true)] public static extern bool ClipCursor(ref Rect rect);
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

        public static bool EnsurePlayerWindowStyles(IntPtr hWnd)
        {
            if (hWnd == IntPtr.Zero) return false;
            const int GWL_STYLE = -16;
            const int GWL_EXSTYLE = -20;
            const long WS_CAPTION = 0x00C00000L, WS_THICKFRAME = 0x00040000L, WS_SYSMENU = 0x00080000L;
            const long WS_MINIMIZEBOX = 0x00020000L, WS_MAXIMIZEBOX = 0x00010000L, WS_POPUP = 0x80000000L;
            const long WS_EX_APPWINDOW = 0x00040000L, WS_EX_TOOLWINDOW = 0x00000080L;
            var style = GetWindowLongPtr(hWnd, GWL_STYLE).ToInt64();
            var exStyle = GetWindowLongPtr(hWnd, GWL_EXSTYLE).ToInt64();
            var requestedStyle = (style & ~WS_POPUP) | WS_CAPTION | WS_THICKFRAME | WS_SYSMENU | WS_MINIMIZEBOX | WS_MAXIMIZEBOX;
            var requestedExStyle = (exStyle | WS_EX_APPWINDOW) & ~WS_EX_TOOLWINDOW;
            if (requestedStyle != style) SetWindowLongPtr(hWnd, GWL_STYLE, new IntPtr(requestedStyle));
            if (requestedExStyle != exStyle) SetWindowLongPtr(hWnd, GWL_EXSTYLE, new IntPtr(requestedExStyle));
            var finalStyle = GetWindowLongPtr(hWnd, GWL_STYLE).ToInt64();
            return (finalStyle & WS_CAPTION) != 0 && (finalStyle & WS_THICKFRAME) != 0;
        }
        public static bool RemoveNoActivate(IntPtr hWnd)
        {
            if (hWnd == IntPtr.Zero) return false;
            const int GWL_EXSTYLE = -20;
            var currentStyle = GetWindowLongPtr(hWnd, GWL_EXSTYLE).ToInt64();
            var requestedStyle = currentStyle & ~0x08000000L;
            if (requestedStyle != currentStyle) SetWindowLongPtr(hWnd, GWL_EXSTYLE, new IntPtr(requestedStyle));
            var actualStyle = GetWindowLongPtr(hWnd, GWL_EXSTYLE).ToInt64();
            return !HasNoActivateExtendedStyle(actualStyle);
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

if (-not (Get-Command Restore-ChroniclePreLaunchForeground -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'HarnessFocusRestore.ps1')
}

function Set-ChronicleTestDisplayConfig([string]$EngineConfigPath) {
    if (-not (Test-Path $EngineConfigPath)) { return }
    $text = Get-Content $EngineConfigPath -Raw
    # Never rewrite the player's display mode, size or frame cap: capture reads the live window, and a
    # forced layout used to survive a killed run as a tiny non-movable window at the top-left corner.
    $text = $text -replace '(?m)^safely_exited\s*=\s*0$', 'safely_exited = 1'
    Set-Content -Path $EngineConfigPath -Value $text -NoNewline
}

function Get-ChronicleCursorClipSnapshot {
    $rect = New-Object ChronicleFramework.WindowApi+Rect
    $read = [ChronicleFramework.WindowApi]::GetClipCursor([ref]$rect)
    $left = [ChronicleFramework.WindowApi]::GetSystemMetrics(76)
    $top = [ChronicleFramework.WindowApi]::GetSystemMetrics(77)
    $right = $left + [ChronicleFramework.WindowApi]::GetSystemMetrics(78)
    $bottom = $top + [ChronicleFramework.WindowApi]::GetSystemMetrics(79)
    return [pscustomobject]@{
        Read = $read
        Left = $rect.Left; Top = $rect.Top; Right = $rect.Right; Bottom = $rect.Bottom
        VirtualLeft = $left; VirtualTop = $top; VirtualRight = $right; VirtualBottom = $bottom
        IsUnrestricted = ($read -and $rect.Left -le $left -and $rect.Top -le $top -and $rect.Right -ge $right -and $rect.Bottom -ge $bottom)
        ForegroundProcessId = [ChronicleFramework.WindowApi]::GetForegroundProcessId()
    }
}

function Test-ChronicleCursorClipRestorePolicy([object]$Baseline, [object]$Current, [int]$TargetProcessId) {
    return ($null -ne $Baseline -and [bool]$Baseline.Read -and [bool]$Baseline.IsUnrestricted -and
        $null -ne $Current -and [bool]$Current.Read -and -not [bool]$Current.IsUnrestricted -and
        [int]$Current.ForegroundProcessId -eq [int]$Baseline.ForegroundProcessId -and
        [int]$Current.ForegroundProcessId -ne $TargetProcessId)
}

function Restore-ChronicleCursorClipBaseline([object]$Baseline, [int]$TargetProcessId) {
    if ($null -eq $Baseline -or -not [bool]$Baseline.Read -or -not [bool]$Baseline.IsUnrestricted) {
        return [pscustomobject]@{ Restored = $false; Attempted = $false; Reason = 'original-desktop-clip-was-not-unrestricted' }
    }
    $current = Get-ChronicleCursorClipSnapshot
    if (-not (Test-ChronicleCursorClipRestorePolicy -Baseline $Baseline -Current $current -TargetProcessId $TargetProcessId)) {
        $reason = if ($current.IsUnrestricted) { 'already-at-original-desktop-bounds' }
            elseif ($current.ForegroundProcessId -ne $Baseline.ForegroundProcessId) { 'foreground-owner-changed; left-clip-untouched' }
            elseif ($current.ForegroundProcessId -eq $TargetProcessId) { 'test-game-is-foreground; refused-global-clip-change' }
            else { 'clip-change-not-attributable-to-test-window; left-untouched' }
        return [pscustomobject]@{ Restored = [bool]$current.IsUnrestricted; Attempted = $false; Reason = $reason; Current = $current }
    }
    $rect = New-Object ChronicleFramework.WindowApi+Rect
    # Desktop geometry can change between the prelaunch sample and the game window. Restore the full current virtual desktop, not stale pixel coordinates.
    $rect.Left = [int]$current.VirtualLeft; $rect.Top = [int]$current.VirtualTop
    $rect.Right = [int]$current.VirtualRight; $rect.Bottom = [int]$current.VirtualBottom
    $set = [ChronicleFramework.WindowApi]::ClipCursor([ref]$rect)
    Start-Sleep -Milliseconds 20
    $after = Get-ChronicleCursorClipSnapshot
    return [pscustomobject]@{
        Restored = ($set -and $after.IsUnrestricted)
        Attempted = $true
        Reason = if ($set -and $after.IsUnrestricted) { 'original-unrestricted-desktop-bounds-restored' } else { 'restore-did-not-stick' }
        Current = $after
    }
}

function Set-ChronicleTestWindow([int]$ProcessId, [object]$CursorClipBaseline = $null) {
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
    $cursorClipRestoreAttempted = $false
    $cursorClipRestoreSucceeded = $false
    $focusRestore = $null
    $focusRestoreBudget = 3
    for ($attempt = 0; $attempt -lt 12; $attempt++) {
        $nonActivating = [ChronicleFramework.WindowApi]::EnsureNoActivate($handle)
        [ChronicleFramework.WindowApi]::ShowWindowAsync($handle, 4) | Out-Null
        # Keep the game visible for capture, but do not activate it or raise it above the user's windows.
        # Bring the window up without activation and without touching its geometry: the player keeps the
        # position and size they chose (SWP_NOSIZE|SWP_NOMOVE|SWP_NOZORDER|SWP_NOACTIVATE|SWP_SHOWWINDOW).
        $rawApplied = [ChronicleFramework.WindowApi]::SetWindowPos($handle, [IntPtr]::Zero, 0, 0, 0, 0, 0x0057)
        Start-Sleep -Milliseconds 100
        $foregroundProcessId = [ChronicleFramework.WindowApi]::GetForegroundProcessId()
        # Window foreground must not belong to the harness client, including during 3D Missions.
        $notForeground = $foregroundProcessId -ne $ProcessId
        if (-not $notForeground -and $focusRestoreBudget -gt 0 -and $null -ne $CursorClipBaseline) {
            # The game window can claim the foreground while it initializes; hand it back to the
            # window that owned the foreground before launch instead of failing the whole run.
            $focusRestore = Restore-ChroniclePreLaunchForeground -TargetProcessId ([int]$CursorClipBaseline.ForegroundProcessId) -GameProcessId $ProcessId
            $focusRestoreBudget--
            $foregroundProcessId = [ChronicleFramework.FocusApi]::GetForegroundProcessId()
            $notForeground = $foregroundProcessId -ne $ProcessId
        }
        $cursorClipRead = [ChronicleFramework.WindowApi]::GetClipCursor([ref]$cursorClip)
        $virtualLeft = [ChronicleFramework.WindowApi]::GetSystemMetrics(76)
        $virtualTop = [ChronicleFramework.WindowApi]::GetSystemMetrics(77)
        $virtualRight = $virtualLeft + [ChronicleFramework.WindowApi]::GetSystemMetrics(78)
        $virtualBottom = $virtualTop + [ChronicleFramework.WindowApi]::GetSystemMetrics(79)
        $cursorUnrestrictedAcrossDesktop = $cursorClipRead -and
            $cursorClip.Left -le $virtualLeft -and $cursorClip.Top -le $virtualTop -and
            $cursorClip.Right -ge $virtualRight -and $cursorClip.Bottom -ge $virtualBottom
        if (-not $cursorUnrestrictedAcrossDesktop) {
            $currentClipSnapshot = [pscustomobject]@{
                Read = $cursorClipRead
                Left = $cursorClip.Left; Top = $cursorClip.Top; Right = $cursorClip.Right; Bottom = $cursorClip.Bottom
                IsUnrestricted = $false
                ForegroundProcessId = $foregroundProcessId
            }
            if (Test-ChronicleCursorClipRestorePolicy -Baseline $CursorClipBaseline -Current $currentClipSnapshot -TargetProcessId $ProcessId) {
                $cursorClipRestoreAttempted = $true
                $restore = Restore-ChronicleCursorClipBaseline -Baseline $CursorClipBaseline -TargetProcessId $ProcessId
                $cursorClipRestoreSucceeded = [bool]$restore.Restored
                $cursorClipRead = [ChronicleFramework.WindowApi]::GetClipCursor([ref]$cursorClip)
                $virtualLeft = [ChronicleFramework.WindowApi]::GetSystemMetrics(76)
                $virtualTop = [ChronicleFramework.WindowApi]::GetSystemMetrics(77)
                $virtualRight = $virtualLeft + [ChronicleFramework.WindowApi]::GetSystemMetrics(78)
                $virtualBottom = $virtualTop + [ChronicleFramework.WindowApi]::GetSystemMetrics(79)
                $cursorUnrestrictedAcrossDesktop = $cursorClipRead -and
                    $cursorClip.Left -le $virtualLeft -and $cursorClip.Top -le $virtualTop -and
                    $cursorClip.Right -ge $virtualRight -and $cursorClip.Bottom -ge $virtualBottom
            }
        }
        $visible = [ChronicleFramework.WindowApi]::IsWindowVisible($handle)
        $iconic = [ChronicleFramework.WindowApi]::IsIconic($handle)
        if ($visible -and -not $iconic -and $nonActivating -and $notForeground -and $cursorUnrestrictedAcrossDesktop) { break }
    }
    $rect = New-Object ChronicleFramework.WindowApi+Rect
    $measured = [ChronicleFramework.WindowApi]::GetWindowRect($handle, [ref]$rect)
    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    # The harness must leave the window usable: any real client area is enough for capture.
    $geometryPreserved = $measured -and $width -ge 320 -and $height -ge 200
    [pscustomobject]@{
        Applied = ($rawApplied -and $nonActivating -and $notForeground -and $cursorUnrestrictedAcrossDesktop -and $measured -and $visible -and -not $iconic -and $geometryPreserved)
        NonActivating = $nonActivating
        NotForeground = $notForeground
        ForegroundProcessId = $foregroundProcessId
        FocusRestore = $focusRestore
        CursorClipRead = $cursorClipRead
        CursorUnrestrictedAcrossDesktop = $cursorUnrestrictedAcrossDesktop
        CursorClipRectangle = [ordered]@{ Left = $cursorClip.Left; Top = $cursorClip.Top; Right = $cursorClip.Right; Bottom = $cursorClip.Bottom }
        CursorClipRestoreAttempted = $cursorClipRestoreAttempted
        CursorClipRestoreSucceeded = $cursorClipRestoreSucceeded
        CursorClipBaselineUnrestricted = [bool]($CursorClipBaseline -and $CursorClipBaseline.IsUnrestricted)
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

function Test-ChronicleCursorClipRestoreContract {
    $baseline = [pscustomobject]@{ Read = $true; IsUnrestricted = $true; Left = 0; Top = 0; Right = 2560; Bottom = 1440; ForegroundProcessId = 100 }
    $captured = [pscustomobject]@{ Read = $true; IsUnrestricted = $false; Left = 1109; Top = 589; Right = 1112; Bottom = 592; ForegroundProcessId = 100 }
    $capturedByForegroundGame = [pscustomobject]@{ Read = $true; IsUnrestricted = $false; Left = 0; Top = 0; Right = 840; Bottom = 472; ForegroundProcessId = 200 }
    $preExistingRestriction = [pscustomobject]@{ Read = $true; IsUnrestricted = $false; Left = 50; Top = 50; Right = 850; Bottom = 522; ForegroundProcessId = 100 }
    return [pscustomobject]@{
        RestoresOnlyTestIntroducedClip = (Test-ChronicleCursorClipRestorePolicy -Baseline $baseline -Current $captured -TargetProcessId 200)
        RefusesWhenGameIsForeground = -not (Test-ChronicleCursorClipRestorePolicy -Baseline $baseline -Current $capturedByForegroundGame -TargetProcessId 200)
        RefusesToOverridePreExistingRestriction = -not (Test-ChronicleCursorClipRestorePolicy -Baseline $preExistingRestriction -Current $captured -TargetProcessId 200)
    }
}
