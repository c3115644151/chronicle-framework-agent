function Test-ChronicleShaderCacheDialogCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$WindowTitle,
        [Parameter(Mandatory)][string]$DialogText,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ActionNames
    )

    if ($WindowTitle -cne 'Mod change detected') { return $false }
    if ($DialogText -notmatch '(?i)shader|cache') { return $false }
    if ($ActionNames.Count -lt 1) { return $false }
    $affirmativeNames = @('OK', 'Yes', 'Continue', 'Proceed', 'Confirm', 'Regenerate', 'Rebuild', ([string][char]0x786E + [char]0x5B9A))
    $affirmativeButtons = @($ActionNames | Where-Object { $_.Trim() -cin $affirmativeNames })
    if ($affirmativeButtons.Count -ne 1) { return $false }
    $negativeNames = @('Cancel', 'No', 'Close', ([string][char]0x53D6 + [char]0x6D88), ([string][char]0x5426))
    if (@($ActionNames | Where-Object { $_.Trim() -cin $negativeNames }).Count -gt 0) { return $false }
    return $true
}

function Invoke-ChronicleNativeButtonClick {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][IntPtr]$WindowHandle,
        [Parameter(Mandatory)][int]$ExpectedProcessId
    )

    if (-not ('Chronicle.Framework.NativeButtonMessage' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace Chronicle.Framework {
    public static class NativeButtonMessage {
        [DllImport("user32.dll", SetLastError = true)] public static extern bool IsWindow(IntPtr hWnd);
        [DllImport("user32.dll", SetLastError = true)] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] public static extern IntPtr SendMessage(IntPtr hWnd, uint message, IntPtr wParam, IntPtr lParam);
    }
}
'@
    }
    if (-not [Chronicle.Framework.NativeButtonMessage]::IsWindow($WindowHandle)) { throw 'The verified native button handle is no longer a window.' }
    [uint32]$ownerProcessId = 0
    $null = [Chronicle.Framework.NativeButtonMessage]::GetWindowThreadProcessId($WindowHandle, [ref]$ownerProcessId)
    if ($ownerProcessId -ne $ExpectedProcessId) { throw 'The native confirm button does not belong to the launched game process.' }
    $null = [Chronicle.Framework.NativeButtonMessage]::SendMessage($WindowHandle, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)
}

function Get-ChronicleWindowAutomationSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$ProcessId,
        [Parameter(Mandatory)][IntPtr]$WindowHandle
    )

    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    $root = [System.Windows.Automation.AutomationElement]::FromHandle($WindowHandle)
    if (-not $root) { throw 'UI Automation could not read the target process window.' }
    if ($root.Current.ProcessId -ne $ProcessId) { throw 'The UI Automation root belongs to a different process.' }

    $all = $root.FindAll(
        [System.Windows.Automation.TreeScope]::Descendants,
        [System.Windows.Automation.Condition]::TrueCondition
    )
    $names = [System.Collections.Generic.List[string]]::new()
    $actionElements = [System.Collections.Generic.List[object]]::new()
    $controls = [System.Collections.Generic.List[object]]::new()
    foreach ($element in $all) {
        try {
            $name = [string]$element.Current.Name
            if (-not [string]::IsNullOrWhiteSpace($name)) { $names.Add($name.Trim()) }
            $patterns = [System.Collections.Generic.List[string]]::new()
            $nativeWindowHandle = [int]$element.Current.NativeWindowHandle
            $className = [string]$element.Current.ClassName
            try {
                $null = $element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
                $patterns.Add('InvokePattern')
            }
            catch { }
            try {
                $null = $element.GetCurrentPattern([System.Windows.Automation.LegacyIAccessiblePattern]::Pattern)
                $patterns.Add('LegacyIAccessiblePattern')
            }
            catch { }
            if ($patterns.Count -gt 0 -or ($className -ceq 'Button' -and $nativeWindowHandle -gt 0)) { $actionElements.Add($element) }
            $controls.Add([pscustomobject]@{
                Name = $name
                ControlType = [string]$element.Current.ControlType.ProgrammaticName
                ClassName = $className
                AutomationId = [string]$element.Current.AutomationId
                NativeWindowHandle = $nativeWindowHandle
                Patterns = @($patterns)
            })
        }
        catch { }
    }
    $actionNames = @($actionElements | ForEach-Object { [string]$_.Current.Name })
    [pscustomobject]@{
        ProcessId = $ProcessId
        WindowTitle = [string]$root.Current.Name
        DialogText = ($names -join ' | ')
        ActionNames = $actionNames
        ActionElements = @($actionElements)
        Controls = @($controls)
    }
}

function Invoke-ChronicleShaderCacheDialogAcknowledgement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$ProcessId,
        [Parameter(Mandatory)][IntPtr]$WindowHandle
    )

    $maxAcknowledgements = 3
    $acknowledgementMethods = [System.Collections.Generic.List[string]]::new()
    $lastButtonName = $null
    $snapshot = Get-ChronicleWindowAutomationSnapshot -ProcessId $ProcessId -WindowHandle $WindowHandle
    $affirmativeNames = @('OK', 'Yes', 'Continue', 'Proceed', 'Confirm', 'Regenerate', 'Rebuild', ([string][char]0x786E + [char]0x5B9A))
    $closed = $false
    for ($attempt = 1; $attempt -le $maxAcknowledgements; $attempt++) {
        $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        if (-not $process) { $closed = $true; break }
        $process.Refresh()
        if ($process.MainWindowTitle -cne 'Mod change detected') { $closed = $true; break }
        $currentHandle = [IntPtr]$process.MainWindowHandle
        if ($currentHandle -eq [IntPtr]::Zero) { break }
        $snapshot = Get-ChronicleWindowAutomationSnapshot -ProcessId $ProcessId -WindowHandle $currentHandle
        if (-not (Test-ChronicleShaderCacheDialogCandidate -WindowTitle $snapshot.WindowTitle -DialogText $snapshot.DialogText -ActionNames $snapshot.ActionNames)) { break }

        $targetButton = @($snapshot.ActionElements | Where-Object { ([string]$_.Current.Name).Trim() -cin $affirmativeNames })[0]
        if (-not $targetButton) { throw 'The verified affirmative UI Automation control disappeared before invocation.' }
        if ($targetButton.Current.ProcessId -ne $ProcessId) { throw 'Refusing to invoke a control owned by a different process.' }
        $lastButtonName = ([string]$targetButton.Current.Name).Trim()
        $targetPatterns = @($snapshot.Controls | Where-Object { $_.Name -ceq [string]$targetButton.Current.Name } | ForEach-Object { $_.Patterns } | Select-Object -First 1)
        if ('InvokePattern' -in $targetPatterns) {
            $invoke = $targetButton.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
            $invoke.Invoke()
            $acknowledgementMethods.Add('InvokePattern')
        }
        elseif ('LegacyIAccessiblePattern' -in $targetPatterns) {
            $legacy = $targetButton.GetCurrentPattern([System.Windows.Automation.LegacyIAccessiblePattern]::Pattern)
            $legacy.DoDefaultAction()
            $acknowledgementMethods.Add('LegacyIAccessiblePattern')
        }
        elseif ($targetButton.Current.ClassName -ceq 'Button' -and $targetButton.Current.NativeWindowHandle -gt 0) {
            Invoke-ChronicleNativeButtonClick -WindowHandle ([IntPtr]$targetButton.Current.NativeWindowHandle) -ExpectedProcessId $ProcessId
            $acknowledgementMethods.Add('Process-owned BM_CLICK')
        }
        else { throw 'The verified affirmative element exposed no safe process-scoped invocation mechanism.' }

        $deadline = (Get-Date).AddSeconds(4)
        while ((Get-Date) -lt $deadline) {
            $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
            if (-not $process) { $closed = $true; break }
            $process.Refresh()
            if ($process.MainWindowTitle -cne 'Mod change detected') { $closed = $true; break }
            Start-Sleep -Milliseconds 200
        }
        if ($closed) { break }

        $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        if (-not $process) { $closed = $true; break }
        $process.Refresh()
        $currentHandle = [IntPtr]$process.MainWindowHandle
        if ($process.MainWindowTitle -cne 'Mod change detected' -or $currentHandle -eq [IntPtr]::Zero) { $closed = $true; break }
        $snapshot = Get-ChronicleWindowAutomationSnapshot -ProcessId $ProcessId -WindowHandle $currentHandle
        if (-not (Test-ChronicleShaderCacheDialogCandidate -WindowTitle $snapshot.WindowTitle -DialogText $snapshot.DialogText -ActionNames $snapshot.ActionNames)) { break }
    }

    if (-not $closed) {
        $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        if (-not $process) { $closed = $true }
        else {
            $process.Refresh()
            if ($process.MainWindowTitle -cne 'Mod change detected') { $closed = $true }
            elseif ($process.MainWindowHandle -ne [IntPtr]::Zero) {
                $snapshot = Get-ChronicleWindowAutomationSnapshot -ProcessId $ProcessId -WindowHandle ([IntPtr]$process.MainWindowHandle)
            }
        }
    }

    [pscustomobject]@{
        Handled = $closed
        ProcessId = $ProcessId
        WindowTitle = $snapshot.WindowTitle
        DialogText = $snapshot.DialogText
        ActionNames = $snapshot.ActionNames
        AcknowledgementAttempts = $acknowledgementMethods.Count
        InvokedMethods = @($acknowledgementMethods)
        InvokedMethod = if ($acknowledgementMethods.Count -gt 0) { $acknowledgementMethods[$acknowledgementMethods.Count - 1] } else { $null }
        Controls = $snapshot.Controls
        InvokedButton = $lastButtonName
        Reason = if ($closed) { "Verified shader-cache prompt cleared after $($acknowledgementMethods.Count) process-owned acknowledgement(s)." } else { "The verified shader-cache prompt remained open after the bounded $maxAcknowledgements acknowledgement attempts; no global input was sent." }
    }
}
