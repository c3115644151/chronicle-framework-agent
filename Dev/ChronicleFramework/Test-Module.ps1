[CmdletBinding()]
param(
    [switch]$WithoutChronicle,
    [switch]$WithoutPrerequisites,
    [int]$TimeoutSeconds = 45,
    [int]$StabilitySeconds = 8
)

$ErrorActionPreference = 'Stop'
$gameRoot = if ($env:CHRONICLE_GAME_ROOT -and (Test-Path -LiteralPath $env:CHRONICLE_GAME_ROOT)) { [IO.Path]::GetFullPath($env:CHRONICLE_GAME_ROOT) } else { Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$gameExe = Join-Path $gameRoot 'bin\Win64_Shipping_Client\Bannerlord.exe'
$project = Join-Path $PSScriptRoot 'ChronicleFramework.csproj'
$modulePath = Join-Path $gameRoot 'Modules\ChronicleFramework'
$engineConfig = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\Configs\engine_config.txt'
$diagnosticLog = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\Configs\ModLogs\chronicle-framework.log'
. (Join-Path $PSScriptRoot 'Test-WindowLayout.ps1')
. (Join-Path $PSScriptRoot 'HarnessStartupEvidence.ps1')
. (Join-Path $PSScriptRoot 'HarnessShaderCacheDialog.ps1')

$existing = Get-Process Bannerlord -ErrorAction SilentlyContinue
if ($existing) {
    throw 'Bannerlord is already running. Close it before running the automated module test.'
}

dotnet build $project --configuration Release --no-restore | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw 'ChronicleFramework build failed.'
}

[xml]$manifest = Get-Content (Join-Path $modulePath 'SubModule.xml')
$manifestId = [string]$manifest.Module.Id.value
if ($manifestId -ne 'ChronicleFramework') {
    throw "Manifest Id '$manifestId' does not match the module directory and test target."
}
$manifestDependencies = @($manifest.Module.DependedModules.DependedModule | ForEach-Object { [string]$_.Id })
foreach ($requiredDependency in @('Native', 'SandBoxCore', 'SandBox')) {
    if ($requiredDependency -notin $manifestDependencies) {
        throw "Manifest is missing required dependency '$requiredDependency'."
    }
}
$dll = Join-Path $modulePath 'bin\Win64_Shipping_Client\ChronicleFramework.dll'
if (-not (Test-Path $dll)) {
    throw "Compiled module DLL was not found: $dll"
}

$modules = @(
    'Bannerlord.Harmony',
    'Bannerlord.ButterLib',
    'Bannerlord.UIExtenderEx',
    'Bannerlord.MBOptionScreen',
    'Native',
    'SandBoxCore',
    'CustomBattle',
    'SandBox',
    'StoryMode',
    'BirthAndDeath'
)
if ($WithoutPrerequisites) {
    $modules = $modules | Where-Object {
        $_ -notin @('Bannerlord.Harmony', 'Bannerlord.ButterLib', 'Bannerlord.UIExtenderEx', 'Bannerlord.MBOptionScreen')
    }
}
if (-not $WithoutChronicle) {
    $modules += 'ChronicleFramework'
}
$moduleArgument = '_MODULES_*' + ($modules -join '*') + '*_MODULES_'
$arguments = "/singleplayer $moduleArgument /anticheat /no_watchdog"

Set-ChronicleTestDisplayConfig -EngineConfigPath $engineConfig
if (Test-Path $engineConfig) {
    $engineText = Get-Content $engineConfig -Raw
    $engineText = $engineText -replace 'safely_exited\s*=\s*0', 'safely_exited = 1'
    Set-Content -Path $engineConfig -Value $engineText -NoNewline
}

$launchStart = Get-Date
$startupWatch = [Diagnostics.Stopwatch]::StartNew()
$diagnosticStartLineCount = if (Test-Path $diagnosticLog) { @(Get-Content $diagnosticLog).Count } else { 0 }
$process = Start-Process -FilePath $gameExe -ArgumentList $arguments -WorkingDirectory (Split-Path $gameExe) -WindowStyle Minimized -PassThru
$trackedProcessId = $process.Id
$rglLog = Join-Path $env:ProgramData "Mount and Blade II Bannerlord\logs\rgl_log_$trackedProcessId.txt"
$watchdogLog = Join-Path $env:ProgramData "Mount and Blade II Bannerlord\logs\watchdog_log_$trackedProcessId.txt"
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$finishedAll = $false
$assemblyLoaded = $WithoutChronicle.IsPresent
$crashDetected = $false
$processExitedUnexpectedly = $false
$lifecycleLoadObserved = $WithoutChronicle.IsPresent
$gameStartObserved = $WithoutChronicle.IsPresent
$mcmSettingsRegistered = $WithoutChronicle.IsPresent
$mcmSettingPropertyIds = @()
$mcmButtonPropertyIds = @()
$validationButtonType = if ($WithoutChronicle) { 'not-tested' } else { 'missing' }
$requiredMcmPropertyIds = @('OllamaBaseUrl', 'ModelId', 'ValidateLocalConfiguration', 'CampaignGoal', 'StartAgent', 'StopAgent', 'ViewAgentStatus')
$requiredMcmButtonPropertyIds = @('ValidateLocalConfiguration', 'StartAgent', 'StopAgent', 'ViewAgentStatus')
$mcmDefinitionComplete = $WithoutChronicle.IsPresent
$startupReadySeconds = $null
$stabilityCompleted = $false
$startupFault = $null
$startupDialogReceipts = [System.Collections.Generic.List[object]]::new()
$startupDialogSnapshots = [System.Collections.Generic.List[object]]::new()

while ((Get-Date) -lt $deadline) {
    $candidateProcesses = @(Get-Process Bannerlord -ErrorAction SilentlyContinue | Where-Object { $_.StartTime -ge $launchStart })
    if ($candidateProcesses.Count -gt 0) {
        $trackedProcessId = ($candidateProcesses | Sort-Object StartTime | Select-Object -Last 1).Id
        $rglLog = Join-Path $env:ProgramData "Mount and Blade II Bannerlord\logs\rgl_log_$trackedProcessId.txt"
        $watchdogLog = Join-Path $env:ProgramData "Mount and Blade II Bannerlord\logs\watchdog_log_$trackedProcessId.txt"
    }
    Set-ChronicleTestWindow -ProcessId $trackedProcessId | Out-Null
    $trackedProcess = Get-Process -Id $trackedProcessId -ErrorAction SilentlyContinue
    if ($trackedProcess -and $trackedProcess.MainWindowTitle -ceq 'Mod change detected') {
        try {
            $dialogReceipt = Invoke-ChronicleShaderCacheDialogAcknowledgement -ProcessId $trackedProcessId -WindowHandle $trackedProcess.MainWindowHandle
            $startupDialogReceipts.Add($dialogReceipt)
            if (-not $dialogReceipt.Handled) {
                $startupFault = "Unverified 'Mod change detected' startup dialog; no button was pressed. Dialog evidence: $($dialogReceipt.DialogText)"
                break
            }
        }
        catch {
            $startupFault = "The known shader-cache dialog could not be inspected safely: $($_.Exception.Message)"
            break
        }
        continue
    }
    if ($trackedProcess -and $trackedProcess.MainWindowTitle -ceq 'Warning') {
        try {
            $warningSnapshot = Get-ChronicleWindowAutomationSnapshot -ProcessId $trackedProcessId -WindowHandle $trackedProcess.MainWindowHandle
            $startupDialogSnapshots.Add((ConvertTo-ChronicleStartupDialogEvidence -Snapshot $warningSnapshot))
            $startupFault = if ($warningSnapshot.DialogText -match '(?i)Unable to initialize Steam API') {
                'Bannerlord reports that the Steam API could not initialize; see startup dialog evidence.'
            } else { 'Bannerlord is blocked by an unclassified Warning dialog; no button was pressed.' }
        }
        catch { $startupFault = "Bannerlord Warning dialog could not be read safely: $($_.Exception.Message)" }
        break
    }
    if (Test-Path $rglLog) {
        $rglText = Get-Content $rglLog -Raw
        $finishedAll = $rglText -match 'Finished All'
        if (-not $WithoutChronicle) {
            $assemblyLoaded = $rglText -match 'ChronicleFramework\.dll'
        }
    }
    if (-not $WithoutChronicle -and (Test-Path $diagnosticLog)) {
        $diagnosticLines = @(Get-Content $diagnosticLog)
        $newDiagnosticLines = if ($diagnosticLines.Count -gt $diagnosticStartLineCount) { $diagnosticLines[$diagnosticStartLineCount..($diagnosticLines.Count - 1)] } else { @() }
        $lifecycleLoadObserved = [bool]($newDiagnosticLines -match '\|submodule-load$')
        $gameStartObserved = [bool]($newDiagnosticLines -match '\|game-start$')
        $mcmSettingsLines = @($newDiagnosticLines | Where-Object { $_ -match '\|harness-mcm-settings\|' })
        if ($mcmSettingsLines.Count -gt 0) {
            $mcmSettingsLine = [string]$mcmSettingsLines[-1]
            if ($mcmSettingsLine -match '\|propertyIds=([^|]*)\|buttonPropertyIds=([^|]*)\|validationButtonType=([^|\r\n]*)') {
                $mcmSettingPropertyIds = @($Matches[1] -split ',' | Where-Object { $_ })
                $mcmButtonPropertyIds = @($Matches[2] -split ',' | Where-Object { $_ })
                $validationButtonType = [string]$Matches[3]
            }
            $mcmSettingsRegistered = [bool]($mcmSettingsLine -match '\|loaded=True\|definition=True\|')
        }
        if ($lifecycleLoadObserved -and -not $assemblyLoaded) { $assemblyLoaded = $true }
    }
    if (Test-Path $watchdogLog) {
        $crashDetected = (Get-Content $watchdogLog -Raw) -match 'Crash occurred|ExceptionCode:'
    }
    $mcmDefinitionComplete = $WithoutChronicle.IsPresent -or ($mcmSettingsRegistered -and $validationButtonType -eq 'Button' -and
        @($requiredMcmPropertyIds | Where-Object { $_ -notin $mcmSettingPropertyIds }).Count -eq 0 -and
        @($requiredMcmButtonPropertyIds | Where-Object { $_ -notin $mcmButtonPropertyIds }).Count -eq 0)
    if ($finishedAll -and -not $crashDetected -and $assemblyLoaded -and $lifecycleLoadObserved -and $mcmDefinitionComplete) {
        $startupReadySeconds = [Math]::Round($startupWatch.Elapsed.TotalSeconds, 2)
        break
    }
    if ($finishedAll -and $crashDetected) {
        break
    }
    if ($candidateProcesses.Count -eq 0 -and -not (Get-Process -Id $process.Id -ErrorAction SilentlyContinue)) {
        $processExitedUnexpectedly = -not $finishedAll
        break
    }
    Start-Sleep -Milliseconds 500
}

if ($null -ne $startupReadySeconds -and -not $crashDetected) {
    $stabilityDeadline = (Get-Date).AddSeconds($StabilitySeconds)
    while ((Get-Date) -lt $stabilityDeadline) {
        if (-not (Get-Process -Id $process.Id -ErrorAction SilentlyContinue)) {
            $processExitedUnexpectedly = $true
            break
        }
        if (Test-Path $watchdogLog) {
            $watchdogText = Get-Content $watchdogLog -Raw
            if ($watchdogText -match 'Crash occurred|ExceptionCode:') {
                $crashDetected = $true
                break
            }
        }
        Start-Sleep -Milliseconds 500
    }
    $stabilityCompleted = (-not $crashDetected -and -not $processExitedUnexpectedly -and (Get-Date) -ge $stabilityDeadline)
}

function Get-DescendantProcessIds([int]$parentId) {
    $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId = $parentId" -ErrorAction SilentlyContinue)
    foreach ($child in $children) {
        $child.ProcessId
        Get-DescendantProcessIds -parentId $child.ProcessId
    }
}

$stillRunning = [bool](Get-Process -Id $process.Id -ErrorAction SilentlyContinue)
$childIds = @(Get-DescendantProcessIds -parentId $process.Id)
if ($stillRunning -or $childIds.Count -gt 0 -or $candidateProcesses.Count -gt 0) {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    foreach ($childId in $childIds) {
        Stop-Process -Id $childId -Force -ErrorAction SilentlyContinue
    }
}
if (Test-Path $engineConfig) {
    $engineText = Get-Content $engineConfig -Raw
    $engineText = $engineText -replace 'safely_exited\s*=\s*0', 'safely_exited = 1'
    Set-Content -Path $engineConfig -Value $engineText -NoNewline
}

$startupWatch.Stop()
$result = [ordered]@{
    ManifestId = $manifestId
    Build = 'passed'
    ChronicleIncluded = (-not $WithoutChronicle.IsPresent)
    AssemblyLoaded = $assemblyLoaded
    LifecycleLoadObserved = $lifecycleLoadObserved
    GameStartObserved = $gameStartObserved
    McmSettingsRegistered = $mcmSettingsRegistered
    McmSettingPropertyIds = $mcmSettingPropertyIds
    McmButtonPropertyIds = $mcmButtonPropertyIds
    McmValidationButtonType = $validationButtonType
    FinishedAll = $finishedAll
    CrashDetected = $crashDetected
    ProcessExitedUnexpectedly = $processExitedUnexpectedly
    StableAfterFinishedAll = [bool]$stabilityCompleted
    StartupReadySeconds = $startupReadySeconds
    StartupTimeoutSeconds = $TimeoutSeconds
    StabilitySeconds = $StabilitySeconds
    ElapsedSeconds = [Math]::Round($startupWatch.Elapsed.TotalSeconds, 2)
    ModuleIds = @($modules)
    StartupFault = $startupFault
    StartupDialogReceipts = @($startupDialogReceipts)
    StartupDialogSnapshots = @($startupDialogSnapshots)
    RglLog = $rglLog
    WatchdogLog = $watchdogLog
    GameProcessId = $trackedProcessId
}
$harnessEvidenceDirectory = if ($env:CHRONICLE_HARNESS_TEMP -and (Test-Path -LiteralPath $env:CHRONICLE_HARNESS_TEMP -PathType Container)) { $env:CHRONICLE_HARNESS_TEMP } else { Join-Path $PSScriptRoot 'TestResults\Smoke' }
New-Item -ItemType Directory -Path $harnessEvidenceDirectory -Force | Out-Null
$result.RglLogCopy = if (Test-Path -LiteralPath $rglLog -PathType Leaf) { $copy = Join-Path $harnessEvidenceDirectory "Smoke-rgl-$trackedProcessId.txt"; Copy-Item -LiteralPath $rglLog -Destination $copy -Force; $copy } else { $null }
$result.RglErrorLogCopy = if (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $rglLog) "rgl_log_errors_$trackedProcessId.txt") -PathType Leaf) { $copy = Join-Path $harnessEvidenceDirectory "Smoke-rgl-errors-$trackedProcessId.txt"; Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $rglLog) "rgl_log_errors_$trackedProcessId.txt") -Destination $copy -Force; $copy } else { $null }
$result.WatchdogLogCopy = if (Test-Path -LiteralPath $watchdogLog -PathType Leaf) { $copy = Join-Path $harnessEvidenceDirectory "Smoke-watchdog-$trackedProcessId.txt"; Copy-Item -LiteralPath $watchdogLog -Destination $copy -Force; $copy } else { $null }
$resultPath = Join-Path $harnessEvidenceDirectory 'SmokeResult.json'
$result.EvidenceResultPath = $resultPath
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
$result | ConvertTo-Json

if (-not $finishedAll -or -not $stabilityCompleted -or $crashDetected -or $processExitedUnexpectedly -or (-not $WithoutChronicle -and (-not $assemblyLoaded -or -not $lifecycleLoadObserved -or -not $mcmDefinitionComplete))) {
    exit 1
}
