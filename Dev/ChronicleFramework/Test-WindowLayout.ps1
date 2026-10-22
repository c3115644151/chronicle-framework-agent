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
        [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int command);
        [DllImport("user32.dll", SetLastError = true)] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int width, int height, uint flags);
        [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out Rect rect);
        [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hWnd, out Rect rect);

        public static IntPtr FindProcessWindow(int targetProcessId)
        {
            IntPtr best = IntPtr.Zero;
            long bestScore = -1;
            EnumWindows(delegate(IntPtr handle, IntPtr ignored) {
                uint processId;
                GetWindowThreadProcessId(handle, out processId);
                if (processId != targetProcessId || !IsWindowVisible(handle)) return true;
                Rect rect;
                GetWindowRect(handle, out rect);
                long area = Math.Max(0, rect.Right - rect.Left) * (long)Math.Max(0, rect.Bottom - rect.Top);
                var title = new StringBuilder(512);
                GetWindowText(handle, title, title.Capacity);
                long score = area + (title.ToString().IndexOf("Bannerlord", StringComparison.OrdinalIgnoreCase) >= 0 ? 1000000000L : 0L);
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
    $visible = $false
    $iconic = $true
    for ($attempt = 0; $attempt -lt 12; $attempt++) {
        [ChronicleFramework.WindowApi]::ShowWindowAsync($handle, 4) | Out-Null
        $rawApplied = [ChronicleFramework.WindowApi]::SetWindowPos($handle, [IntPtr]::Zero, $script:ChronicleTestWindowX, $script:ChronicleTestWindowY, $script:ChronicleTestWindowWidth, $script:ChronicleTestWindowHeight, 0x0050)
        Start-Sleep -Milliseconds 100
        $visible = [ChronicleFramework.WindowApi]::IsWindowVisible($handle)
        $iconic = [ChronicleFramework.WindowApi]::IsIconic($handle)
        if ($visible -and -not $iconic) { break }
    }
    $rect = New-Object ChronicleFramework.WindowApi+Rect
    $measured = [ChronicleFramework.WindowApi]::GetWindowRect($handle, [ref]$rect)
    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    [pscustomobject]@{
        Applied = ($rawApplied -and $measured -and $visible -and -not $iconic -and $rect.Left -eq 0 -and $rect.Top -eq 0 -and $width -eq $script:ChronicleTestWindowWidth -and $height -eq $script:ChronicleTestWindowHeight)
        Visible = $visible; Minimized = $iconic
        X = $rect.Left; Y = $rect.Top; Width = $width; Height = $height; DisplayMode = 0
    }
}
