#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateRange(640, 7680)][int]$Width = 1600,
    [ValidateRange(360, 4320)][int]$Height = 900,
    [ValidateRange(30, 240)][int]$FrameRate = 60,
    [string]$ProcessName = "Bannerlord.BLSE.Standalone"
)

# Hands the game window back to the player after harness capture runs:
#   - clears WS_EX_NOACTIVATE, so clicking the window raises and activates it like any other window
#   - restores a normal windowed size and caps the frame rate in engine_config for the next launch
# Harness capture no longer forces window position or size, so nothing else has to be undone.
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "Test-WindowLayout.ps1")
if (-not ("ChronicleWindowRelease" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
namespace ChronicleFramework {
    public static class ChronicleWindowReleaseApi {
        [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    }
    public static class ChronicleWindowRelease {
        public static bool Raise(IntPtr hWnd) { return hWnd == IntPtr.Zero ? false : ChronicleWindowReleaseApi.SetForegroundWindow(hWnd); }
    }
}
"@
}

$configPath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Configs\engine_config.txt"
if (Test-Path -LiteralPath $configPath -PathType Leaf) {
    $text = Get-Content -LiteralPath $configPath -Raw
    $text = $text -replace "(?m)^display_mode\s*=.*$", "display_mode = 0"
    $text = $text -replace "(?m)^display_width\s*=.*$", ("display_width = " + $Width)
    $text = $text -replace "(?m)^display_height\s*=.*$", ("display_height = " + $Height)
    $text = $text -replace "(?m)^max_framerate\s*=.*$", ("max_framerate = " + $FrameRate)
    Set-Content -LiteralPath $configPath -Value $text -NoNewline
}

$targets = @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue)
if ($targets.Count -eq 0) {
    [ordered]@{ ProcessCount = 0; WindowReleased = $false; EngineConfigRepaired = (Test-Path -LiteralPath $configPath); Message = "No running game window; engine_config restored for the next launch." } | ConvertTo-Json
    return
}
$released = @()
foreach ($target in $targets) {
    $handle = [ChronicleFramework.WindowApi]::FindProcessWindow($target.Id)
    if ($handle -eq [IntPtr]::Zero) { continue }
    $cleared = [ChronicleFramework.WindowApi]::RemoveNoActivate($handle)
    $styled = [ChronicleFramework.WindowApi]::EnsurePlayerWindowStyles($handle)
    # SWP_FRAMECHANGED|SWP_NOZORDER applies the style change without touching the player's layout.
    [ChronicleFramework.WindowApi]::SetWindowPos($handle, [IntPtr]::Zero, 0, 0, 0, 0, 0x0024) | Out-Null
    [ChronicleFramework.WindowApi]::ShowWindowAsync($handle, 9) | Out-Null
    [void]([ChronicleWindowRelease]::Raise($handle))
    $style = [ChronicleFramework.WindowApi]::GetWindowLongPtr($handle, -20).ToInt64()
    $released += [ordered]@{
        ProcessId = $target.Id
        NoActivateCleared = $cleared
        NoActivateStillPresent = [ChronicleFramework.WindowApi]::HasNoActivateExtendedStyle($style)
        PlayerStylesApplied = $styled
    }
}
[ordered]@{
    ProcessCount = $targets.Count
    WindowReleased = @($released | Where-Object { -not $_.NoActivateStillPresent }).Count -gt 0
    EngineConfigRepaired = (Test-Path -LiteralPath $configPath)
    Windows = $released
} | ConvertTo-Json -Depth 4