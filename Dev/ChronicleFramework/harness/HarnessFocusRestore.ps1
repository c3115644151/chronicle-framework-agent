#Requires -Version 7.0
# The Harness never activates itself: it keeps the test-owned game window visible with
# WS_EX_NOACTIVATE and, when the game grabs the foreground during startup, hands the
# foreground back to the window that carried it before the launch. Returning focus to
# the recorded pre-launch owner is the only supported way to satisfy the
# "game window must not be foreground" contract, and it never targets the Harness
# process itself.
if (-not ('ChronicleFramework.FocusApi' -as [type])) {
    $previousTemp = [Environment]::GetEnvironmentVariable('TEMP', 'Process')
    $previousTmp = [Environment]::GetEnvironmentVariable('TMP', 'Process')
    try {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace ChronicleFramework
{
    public static class FocusApi
    {
        public delegate bool FocusEnumWindowsProc(IntPtr hWnd, IntPtr lParam);
        [StructLayout(LayoutKind.Sequential)]
        public struct FocusRect { public int Left; public int Top; public int Right; public int Bottom; }
        [DllImport("user32.dll")] public static extern bool EnumWindows(FocusEnumWindowsProc callback, IntPtr lParam);
        [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
        [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll", SetLastError = true)] public static extern bool SetForegroundWindow(IntPtr hWnd);
        [DllImport("user32.dll", SetLastError = true)] public static extern bool BringWindowToTop(IntPtr hWnd);
        [DllImport("user32.dll", SetLastError = true)] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool attach);
        [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int index);
        [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();

        public static int GetForegroundProcessId()
        {
            var foreground = GetForegroundWindow();
            if (foreground == IntPtr.Zero) return 0;
            uint processId;
            GetWindowThreadProcessId(foreground, out processId);
            return unchecked((int)processId);
        }

        public static uint GetWindowThreadId(IntPtr hWnd)
        {
            uint ignored;
            return GetWindowThreadProcessId(hWnd, out ignored);
        }

        // Pick the largest visible top-level window owned by the process, matching how a
        // foreground owner presents itself to the user rather than its helper windows.
        public static IntPtr FindVisibleProcessWindow(int targetProcessId)
        {
            IntPtr best = IntPtr.Zero;
            long bestArea = 0;
            EnumWindows(delegate(IntPtr handle, IntPtr ignored)
            {
                uint processId;
                GetWindowThreadProcessId(handle, out processId);
                if (unchecked((int)processId) != targetProcessId) return true;
                if (!IsWindowVisible(handle) || IsIconic(handle)) return true;
                FocusRect rect;
                if (!GetWindowRectForFocus(handle, out rect)) return true;
                long area = (long)(rect.Right - rect.Left) * (rect.Bottom - rect.Top);
                if (area > bestArea) { bestArea = area; best = handle; }
                return true;
            }, IntPtr.Zero);
            return best;
        }

        [DllImport("user32.dll")]
        private static extern bool GetWindowRect(IntPtr hWnd, out FocusRect rect);

        private static bool GetWindowRectForFocus(IntPtr hWnd, out FocusRect rect)
        {
            return GetWindowRect(hWnd, out rect);
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

function Restore-ChroniclePreLaunchForeground {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$TargetProcessId,
        [Parameter(Mandatory)][int]$GameProcessId,
        [int]$HarnessProcessId = $PID
    )

    $before = [ChronicleFramework.FocusApi]::GetForegroundProcessId()
    $receipt = [ordered]@{
        Attempted = $false
        Restored = $true
        Reason = 'game-was-not-foreground'
        TargetProcessId = $TargetProcessId
        GameProcessId = $GameProcessId
        ForegroundProcessIdBefore = $before
        ForegroundProcessIdAfter = $before
        TargetWindowHandle = 0
        WindowRaised = $false
        AttachSucceeded = $false
        SetForegroundWindowAccepted = $false
        Attempts = 0
    }
    if ($before -ne $GameProcessId) { return [pscustomobject]$receipt }

    $refusal = if ($TargetProcessId -le 0) { 'no-recorded-pre-launch-foreground-owner' }
        elseif ($TargetProcessId -eq $GameProcessId) { 'pre-launch-foreground-owner-was-the-game' }
        elseif ($HarnessProcessId -gt 0 -and $TargetProcessId -eq $HarnessProcessId) { 'pre-launch-foreground-owner-is-the-harness' }
        elseif (-not (Get-Process -Id $TargetProcessId -ErrorAction SilentlyContinue)) { 'pre-launch-foreground-owner-has-exited' }
        else { $null }
    if ($refusal) {
        $receipt.Reason = $refusal
        return [pscustomobject]$receipt
    }

    $handle = [ChronicleFramework.FocusApi]::FindVisibleProcessWindow($TargetProcessId)
    if ($handle -eq [IntPtr]::Zero) {
        $receipt.Reason = 'pre-launch-foreground-owner-has-no-visible-window'
        return [pscustomobject]$receipt
    }
    $receipt.Attempted = $true
    $receipt.TargetWindowHandle = $handle.ToInt64()

    # Windows only honors SetForegroundWindow for the owning input queue; attaching to the
    # queue that currently holds the foreground makes the hand-back explicit instead of a
    # taskbar flash.
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $receipt.Attempts = $attempt
        $foregroundHandle = [ChronicleFramework.FocusApi]::GetForegroundWindow()
        $foregroundThread = [ChronicleFramework.FocusApi]::GetWindowThreadId($foregroundHandle)
        $currentThread = [ChronicleFramework.FocusApi]::GetCurrentThreadId()
        $attached = $false
        if ($foregroundThread -ne 0 -and $foregroundThread -ne $currentThread) {
            $attached = [ChronicleFramework.FocusApi]::AttachThreadInput($currentThread, $foregroundThread, $true)
        }
        try {
            if ($attempt -eq 1) {
                $receipt.SetForegroundWindowAccepted = [ChronicleFramework.FocusApi]::SetForegroundWindow($handle)
            } else {
                $receipt.WindowRaised = [ChronicleFramework.FocusApi]::BringWindowToTop($handle)
                $receipt.SetForegroundWindowAccepted = [ChronicleFramework.FocusApi]::SetForegroundWindow($handle)
            }
        }
        finally {
            if ($attached) { [ChronicleFramework.FocusApi]::AttachThreadInput($currentThread, $foregroundThread, $false) | Out-Null }
        }
        $receipt.AttachSucceeded = $attached
        Start-Sleep -Milliseconds 120
        $receipt.ForegroundProcessIdAfter = [ChronicleFramework.FocusApi]::GetForegroundProcessId()
        if ($receipt.ForegroundProcessIdAfter -ne $GameProcessId) { break }
    }
    $receipt.Restored = $receipt.ForegroundProcessIdAfter -ne $GameProcessId
    $receipt.Reason = if ($receipt.Restored) { 'pre-launch-foreground-owner-restored' } else { 'foreground-hand-back-was-refused' }
    [pscustomobject]$receipt
}
