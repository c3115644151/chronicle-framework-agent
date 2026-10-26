[CmdletBinding()]
param(
    [switch]$WithoutChronicle,
    [switch]$WithoutPrerequisites,
    [switch]$SkipBuild,
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

if (-not $SkipBuild) {
    dotnet build $project --configuration Release --no-restore | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw 'ChronicleFramework build failed.'
    }
}

[xml]$manifest = Get-Content (Join-Path $modulePath 'SubModule.xml')
$moduleGameTextXml = @($manifest.Module.Xmls.XmlNode | ForEach-Object { [string]$_.XmlName.id + ':' + [string]$_.XmlName.path })
if ('GameText:global_strings' -notin $moduleGameTextXml) { throw 'Chronicle SubModule.xml must register its native control-key display strings.' }
$globalStringsPath = Join-Path $modulePath 'ModuleData\global_strings.xml'
if (-not (Test-Path -LiteralPath $globalStringsPath -PathType Leaf)) { throw 'Chronicle native key display strings were not deployed to ModuleData.' }
[xml]$globalStrings = Get-Content -LiteralPath $globalStringsPath -Raw -Encoding UTF8
foreach ($stringId in @('str_key_category_name.ChronicleAgentControl','str_key_name.ChronicleAgentControl_Up','str_key_description.ChronicleAgentControl_Up')) {
    if (@($globalStrings.strings.string | Where-Object { $_.id -eq $stringId -and -not [string]::IsNullOrWhiteSpace([string]$_.text) }).Count -ne 1) {
        throw "Chronicle native control-key display string is missing or duplicated: $stringId"
    }
}
$manifestId = [string]$manifest.Module.Id.value
if ($manifestId -ne 'ChronicleFramework') {
    throw "Manifest Id '$manifestId' does not match the module directory and test target."
}
$manifestDependencies = @($manifest.Module.DependedModules.DependedModule | ForEach-Object { [string]$_.Id })
foreach ($requiredDependency in @('Bannerlord.Harmony','Bannerlord.ButterLib','Bannerlord.UIExtenderEx','Bannerlord.MBOptionScreen','Native','SandBoxCore','SandBox')) {
    if ($requiredDependency -notin $manifestDependencies) {
        throw "Manifest is missing required dependency '$requiredDependency'."
    }
}
foreach ($dependency in @($manifest.Module.DependedModules.DependedModule)) {
    $dependencyId = [string]$dependency.Id
    $minimumVersion = [string]$dependency.DependentVersion
    $dependencyManifestPath = Join-Path $gameRoot ("Modules\{0}\SubModule.xml" -f $dependencyId)
    if (-not (Test-Path -LiteralPath $dependencyManifestPath -PathType Leaf)) { throw "Required module manifest is missing: $dependencyId" }
    [xml]$dependencyManifest = Get-Content -LiteralPath $dependencyManifestPath -Encoding UTF8
    $installedVersion = ([string]$dependencyManifest.Module.Version.value).TrimStart('v')
    if (-not [string]::IsNullOrWhiteSpace($minimumVersion) -and [version]$installedVersion -lt [version]$minimumVersion.TrimStart('v')) {
        throw "Installed prerequisite $dependencyId version $installedVersion is below declared minimum $minimumVersion."
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

$steamRoot = if (-not [string]::IsNullOrWhiteSpace($env:CHRONICLE_STEAM_ROOT)) {
    [IO.Path]::GetFullPath($env:CHRONICLE_STEAM_ROOT)
} else {
    Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $gameRoot))
}
$steamStatus = Ensure-ChronicleSteamClientReady -SteamRoot $steamRoot
Set-ChronicleTestDisplayConfig -EngineConfigPath $engineConfig
if (Test-Path $engineConfig) {
    $engineText = Get-Content $engineConfig -Raw
    $engineText = $engineText -replace 'safely_exited\s*=\s*0', 'safely_exited = 1'
    Set-Content -Path $engineConfig -Value $engineText -NoNewline
}
$soundDisabledBefore = Get-ChronicleBannerlordSoundDisabled -LiteralPath $engineConfig
$soundGuard = Disable-ChronicleHarnessGameSound
$soundDisabledDuring = Get-ChronicleBannerlordSoundDisabled -LiteralPath $engineConfig
if ($soundDisabledDuring -ne 1) { throw 'Bannerlord game sound must be disabled by the temporary Harness guard before startup.' }

$launchStart = Get-Date
$startupWatch = [Diagnostics.Stopwatch]::StartNew()
$diagnosticStartLineCount = if (Test-Path $diagnosticLog) { @(Get-Content $diagnosticLog).Count } else { 0 }
$process = Start-ChronicleSteamGame -FilePath $gameExe -ArgumentList $arguments -WorkingDirectory (Split-Path $gameExe) -WindowStyle Minimized
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
$inputControlKeyDisplayTextLoaded = $WithoutChronicle.IsPresent
$inputControlKeyVisibleInNativeOptions = $WithoutChronicle.IsPresent
$mcmSettingPropertyIds = @()
$mcmButtonPropertyIds = @()
$validationButtonType = if ($WithoutChronicle) { 'not-tested' } else { 'missing' }
$requiredMcmPropertyIds = @('OllamaBaseUrl', 'ModelId', 'OutputMode', 'DeepSeekRunCostLimitCny', 'ValidateLocalConfiguration', 'CampaignGoal', 'StartAgent', 'StopAgent', 'ViewAgentStatus')
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
        [string]$rglText = Get-Content $rglLog -Raw
        $finishedAll = [bool]($rglText -match 'Finished All')
        if (-not $WithoutChronicle) {
            $assemblyLoaded = [bool]($rglText -match 'ChronicleFramework\.dll')
        }
    }
    if (-not $WithoutChronicle -and (Test-Path $diagnosticLog)) {
        $diagnosticLines = @(Get-Content $diagnosticLog)
        $newDiagnosticLines = if ($diagnosticLines.Count -gt $diagnosticStartLineCount) { $diagnosticLines[$diagnosticStartLineCount..($diagnosticLines.Count - 1)] } else { @() }
        $lifecycleLoadObserved = [bool]($newDiagnosticLines -match '\|submodule-load$')
        $gameStartObserved = [bool]($newDiagnosticLines -match '\|game-start$')
        $mcmSettingsLines = @($newDiagnosticLines | Where-Object { $_ -match '\|harness-mcm-settings\|' })
        $inputControlKeyTextLines = @($newDiagnosticLines | Where-Object { $_ -match '\|agent-input-key-display-text\|' })
        if ($inputControlKeyTextLines.Count -gt 0) {
            $inputControlKeyDisplayTextLoaded = [bool]([string]$inputControlKeyTextLines[-1] -match '\|loaded=True\|categoryPresent=True\|namePresent=True\|descriptionPresent=True')
            $inputControlKeyVisibleInNativeOptions = [bool]([string]$inputControlKeyTextLines[-1] -match '\|optionsVisible=True\|optionsKey=.+')
        }
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
        $crashDetected = [bool]([string](Get-Content $watchdogLog -Raw) -match 'Crash occurred|ExceptionCode:')
    }
    $mcmDefinitionComplete = $WithoutChronicle.IsPresent -or ($mcmSettingsRegistered -and $validationButtonType -eq 'Button' -and
        @($requiredMcmPropertyIds | Where-Object { $_ -notin $mcmSettingPropertyIds }).Count -eq 0 -and
        @($requiredMcmButtonPropertyIds | Where-Object { $_ -notin $mcmButtonPropertyIds }).Count -eq 0 -and
        $inputControlKeyDisplayTextLoaded -and $inputControlKeyVisibleInNativeOptions)
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
$soundRestoreDeadline = (Get-Date).AddSeconds(10)
do {
    if (@(Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue).Count -eq 0) { break }
    Start-Sleep -Milliseconds 150
} while ((Get-Date) -lt $soundRestoreDeadline)
$soundRestoration = Restore-ChronicleHarnessGameSound
$soundDisabledAfter = Get-ChronicleBannerlordSoundDisabled -LiteralPath $engineConfig
if (Test-Path $engineConfig) {
    $engineText = Get-Content $engineConfig -Raw
    $engineText = $engineText -replace 'safely_exited\s*=\s*0', 'safely_exited = 1'
    Set-Content -Path $engineConfig -Value $engineText -NoNewline
}

$startupWatch.Stop()
$result = [ordered]@{
    ManifestId = $manifestId
    GameRoot = $gameRoot
    ModuleDirectory = $modulePath
    GameExecutable = $gameExe
    SteamClient = [ordered]@{
        available = [bool]$steamStatus.available
        startedByHarness = [bool]$steamStatus.startedByHarness
        readyUtc = [string]$steamStatus.readyUtc
        readiness = [ordered]@{
            Ready = [bool]$steamStatus.readiness.Ready
            Reason = [string]$steamStatus.readiness.Reason
            SteamProcessCount = [int]$steamStatus.readiness.SteamProcessCount
            WebHelperProcessCount = [int]$steamStatus.readiness.WebHelperProcessCount
            WebHelperStableSeconds = [double]$steamStatus.readiness.WebHelperStableSeconds
            RequiredStableSeconds = [double]$steamStatus.readiness.RequiredStableSeconds
        }
    }
    Build = 'passed'
    ChronicleIncluded = (-not $WithoutChronicle.IsPresent)
    AssemblyLoaded = $assemblyLoaded
    LifecycleLoadObserved = $lifecycleLoadObserved
    GameStartObserved = $gameStartObserved
    McmSettingsRegistered = $mcmSettingsRegistered
    InputControlKeyDisplayTextLoaded = $inputControlKeyDisplayTextLoaded
    InputControlKeyVisibleInNativeOptions = $inputControlKeyVisibleInNativeOptions
    McmSettingPropertyIds = $mcmSettingPropertyIds
    McmButtonPropertyIds = $mcmButtonPropertyIds
    McmValidationButtonType = $validationButtonType
    BannerlordSoundDisabledBefore = $soundDisabledBefore
    BannerlordSoundDisabledDuring = $soundDisabledDuring
    BannerlordSoundDisabledAfter = $soundDisabledAfter
    BannerlordSoundMutedForHarness = [bool]($soundGuard -and $soundDisabledDuring -eq 1)
    BannerlordSoundRestorationStatus = $soundRestoration.Status
    BannerlordSoundRestored = [bool]$soundRestoration.Restored
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
$receiptStagePath = Join-Path $harnessEvidenceDirectory 'SmokeReceiptStages.log'
Add-Content -LiteralPath $receiptStagePath -Value 'serialize-start'
try {
    $receiptJson = ConvertTo-ChronicleReceiptJson -Value $result
}
catch {
    $failedFields = [System.Collections.Generic.List[string]]::new()
    foreach ($fieldName in $result.Keys) {
        try {
            $singleField = [ordered]@{ $fieldName = $result[$fieldName] }
            $null = ConvertTo-ChronicleReceiptJson -Value $singleField
        }
        catch {
            $fieldValue = $result[$fieldName]
            $fieldType = if ($null -eq $fieldValue) { 'null' } else { $fieldValue.GetType().FullName }
            $failedFields.Add("${fieldName}:$fieldType")
        }
    }
    $diagnostic = if ($failedFields.Count -gt 0) { 'serialize-field-failed:' + ($failedFields -join ',') } else { 'serialize-field-failed:none;combined-object-only' }
    Add-Content -LiteralPath $receiptStagePath -Value $diagnostic
    throw
}
Add-Content -LiteralPath $receiptStagePath -Value 'serialize-complete'
$receiptJson | Set-Content -LiteralPath $resultPath -Encoding UTF8
Add-Content -LiteralPath $receiptStagePath -Value 'write-complete'
Write-Output $receiptJson

if (-not $soundRestoration.Restored -or -not $finishedAll -or -not $stabilityCompleted -or $crashDetected -or $processExitedUnexpectedly -or (-not $WithoutChronicle -and (-not $assemblyLoaded -or -not $lifecycleLoadObserved -or -not $mcmDefinitionComplete -or -not $inputControlKeyDisplayTextLoaded -or -not $inputControlKeyVisibleInNativeOptions))) {
    exit 1
}
