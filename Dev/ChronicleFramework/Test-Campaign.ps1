[CmdletBinding()]
param(
    [string]$FixtureSaveName = 'AgentBridgeFixture',
    [string]$LifecycleSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180,
    [int]$StabilitySeconds = 5
)

$ErrorActionPreference = 'Stop'
$gameRoot = if ($env:CHRONICLE_GAME_ROOT -and (Test-Path -LiteralPath $env:CHRONICLE_GAME_ROOT)) { [IO.Path]::GetFullPath($env:CHRONICLE_GAME_ROOT) } else { Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$binDirectory = Join-Path $gameRoot 'bin\Win64_Shipping_Client'
$launcher = Join-Path $binDirectory 'Bannerlord.BLSE.Standalone.exe'
$saveDirectory = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\Game Saves'
$fixtureSave = Join-Path $saveDirectory "$FixtureSaveName.sav"
$lifecycleSave = Join-Path $saveDirectory "$LifecycleSaveName.sav"
$diagnosticLog = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\Configs\ModLogs\chronicle-framework.log'
$engineConfig = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\Configs\engine_config.txt'
. (Join-Path $PSScriptRoot 'Test-WindowLayout.ps1')

if (-not (Test-Path $launcher)) { throw "BLSE Standalone was not found: $launcher" }
if (-not (Test-Path $fixtureSave)) { throw "Clean fixture was not found: $fixtureSave" }
if (Get-Process Bannerlord -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
if (Test-Path $lifecycleSave) { Remove-Item -LiteralPath $lifecycleSave -Force }

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
    'BirthAndDeath',
    'ChronicleFramework'
)
$moduleArgument = '_MODULES_*' + ($modules -join '*') + '*_MODULES_'

function Set-SafeExitMarker {
    if (Test-Path $engineConfig) {
        $engineText = Get-Content $engineConfig -Raw
        $engineText = $engineText -replace 'safely_exited\s*=\s*0', 'safely_exited = 1'
        Set-Content -Path $engineConfig -Value $engineText -NoNewline
    }
}

function Get-DescendantProcessIds([int]$ParentId) {
    $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId = $ParentId" -ErrorAction SilentlyContinue)
    foreach ($child in $children) {
        [int]$child.ProcessId
        Get-DescendantProcessIds -ParentId $child.ProcessId
    }
}

function Stop-CampaignProcessTree([System.Diagnostics.Process]$LauncherProcess, [int]$BannerlordPid) {
    $descendantIds = @(Get-DescendantProcessIds -ParentId $LauncherProcess.Id)
    foreach ($processId in @($descendantIds + $BannerlordPid + $LauncherProcess.Id) | Where-Object { $_ } | Select-Object -Unique) {
        Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
    }
    Set-ChronicleTestDisplayConfig -EngineConfigPath $engineConfig
    Set-SafeExitMarker
}

function Invoke-CampaignLifecycleRun {
    param(
        [string]$Mode,
        [string]$LoadSaveName,
        [int]$ExpectedLoadCount,
        [switch]$ExpectSave
    )

    Set-SafeExitMarker
    $diagnosticStartLineCount = if (Test-Path $diagnosticLog) { @(Get-Content $diagnosticLog).Count } else { 0 }
    $launchStart = Get-Date
    $previousMode = $env:CHRONICLE_HARNESS_MODE
    $previousSaveName = $env:CHRONICLE_HARNESS_SAVE_NAME
    $env:CHRONICLE_HARNESS_MODE = $Mode
    $env:CHRONICLE_HARNESS_SAVE_NAME = $LifecycleSaveName
    try {
        $arguments = "/continuesave $LoadSaveName $moduleArgument /anticheat"
        $launcherProcess = Start-Process -FilePath $launcher -ArgumentList $arguments -WorkingDirectory $binDirectory -WindowStyle Minimized -PassThru
    }
    finally {
        $env:CHRONICLE_HARNESS_MODE = $previousMode
        $env:CHRONICLE_HARNESS_SAVE_NAME = $previousSaveName
    }

    $bannerlordPid = 0
    $gameStartObserved = $false
    $behaviorRegistered = $false
    $loadObserved = $false
    $campaignLoadedObserved = $false
    $dailyTickObserved = $false
    $saveRequestedObserved = $false
    $saveSyncObserved = $false
    $finishedAll = $false
    $crashDetected = $false
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    try {
        while ((Get-Date) -lt $deadline) {
            $candidate = Get-Process Bannerlord -ErrorAction SilentlyContinue |
                Where-Object { $_.StartTime -ge $launchStart } |
                Sort-Object StartTime |
                Select-Object -Last 1
            if ($candidate) { $bannerlordPid = $candidate.Id }
            if ($bannerlordPid) { Set-ChronicleTestWindow -ProcessId $bannerlordPid | Out-Null }

            $newDiagnosticLines = @()
            if (Test-Path $diagnosticLog) {
                $allDiagnosticLines = @(Get-Content $diagnosticLog)
                if ($allDiagnosticLines.Count -gt $diagnosticStartLineCount) {
                    $newDiagnosticLines = @($allDiagnosticLines[$diagnosticStartLineCount..($allDiagnosticLines.Count - 1)])
                }
            }
            $gameStartLine = $newDiagnosticLines | Where-Object { $_ -match '\|pid=(\d+)\|game-start$' } | Select-Object -Last 1
            if ($gameStartLine -and $gameStartLine -match '\|pid=(\d+)\|') {
                $bannerlordPid = [int]$Matches[1]
                $gameStartObserved = $true
            }
            $behaviorRegistered = [bool]($newDiagnosticLines -match "pid=$bannerlordPid\|campaign-behavior-registered$")
            $loadObserved = [bool]($newDiagnosticLines -match "pid=$bannerlordPid\|campaign-sync\|mode=load\|version=1\|count=$ExpectedLoadCount\|")
            $campaignLoadedObserved = [bool]($newDiagnosticLines -match "pid=$bannerlordPid\|campaign-loaded\|mode=$Mode\|version=1\|count=$ExpectedLoadCount\|")
            if ($ExpectSave) {
                $nextCount = $ExpectedLoadCount + 1
                $dailyTickObserved = [bool]($newDiagnosticLines -match "pid=$bannerlordPid\|campaign-daily-tick\|version=1\|count=$nextCount\|")
                $saveRequestedObserved = [bool]($newDiagnosticLines -match "pid=$bannerlordPid\|campaign-save-requested\|name=$LifecycleSaveName\|count=$nextCount\|")
                $saveSyncObserved = [bool]($newDiagnosticLines -match "pid=$bannerlordPid\|campaign-sync\|mode=save\|version=1\|count=$nextCount\|")
            }

            if ($bannerlordPid) {
                $rglLog = Join-Path $env:ProgramData "Mount and Blade II Bannerlord\logs\rgl_log_$bannerlordPid.txt"
                $watchdogLog = Join-Path $env:ProgramData "Mount and Blade II Bannerlord\logs\watchdog_log_$bannerlordPid.txt"
                if (Test-Path $rglLog) {
                    $rglText = [string](Get-Content $rglLog -Raw)
                    $finishedAll = [bool]($rglText -match 'Finished All')
                    $crashDetected = [bool]($rglText -match 'Unhandled Exception|Crash occurred|ExceptionCode:')
                }
                if (Test-Path $watchdogLog) {
                    $watchdogText = [string](Get-Content $watchdogLog -Raw)
                    $crashDetected = [bool]($crashDetected -or ($watchdogText -match 'Crash occurred|ExceptionCode:'))
                }
            }

            $saveReady = -not $ExpectSave -or ($dailyTickObserved -and $saveRequestedObserved -and $saveSyncObserved -and (Test-Path $lifecycleSave) -and (Get-Item $lifecycleSave).Length -gt 0)
            if ($gameStartObserved -and $behaviorRegistered -and $loadObserved -and $campaignLoadedObserved -and $finishedAll -and $saveReady) { break }
            if (-not (Get-Process -Id $launcherProcess.Id -ErrorAction SilentlyContinue) -and -not $candidate) { break }
            Start-Sleep -Milliseconds 500
        }

        if ($gameStartObserved -and $behaviorRegistered -and $loadObserved -and $campaignLoadedObserved -and $finishedAll -and -not $crashDetected) {
            $stabilityDeadline = (Get-Date).AddSeconds($StabilitySeconds)
            while ((Get-Date) -lt $stabilityDeadline) {
                if ($bannerlordPid -and -not (Get-Process -Id $bannerlordPid -ErrorAction SilentlyContinue)) { break }
                Start-Sleep -Milliseconds 500
            }
        }
    }
    finally {
        Stop-CampaignProcessTree -LauncherProcess $launcherProcess -BannerlordPid $bannerlordPid
    }

    $passed = $gameStartObserved -and $behaviorRegistered -and $loadObserved -and $campaignLoadedObserved -and $finishedAll -and -not $crashDetected
    if ($ExpectSave) {
        $passed = $passed -and $dailyTickObserved -and $saveRequestedObserved -and $saveSyncObserved -and (Test-Path $lifecycleSave)
    }
    return [pscustomobject]@{
        Mode = $Mode
        LoadSaveName = $LoadSaveName
        BannerlordPid = $bannerlordPid
        GameStartObserved = $gameStartObserved
        BehaviorRegistered = $behaviorRegistered
        LoadObserved = $loadObserved
        CampaignLoadedObserved = $campaignLoadedObserved
        DailyTickObserved = $dailyTickObserved
        SaveRequestedObserved = $saveRequestedObserved
        SaveSyncObserved = $saveSyncObserved
        FinishedAll = $finishedAll
        CrashDetected = $crashDetected
        Passed = $passed
    }
}

$fixtureHashBefore = (Get-FileHash $fixtureSave -Algorithm SHA256).Hash
$advanceRun = Invoke-CampaignLifecycleRun -Mode 'advance-save' -LoadSaveName $FixtureSaveName -ExpectedLoadCount 0 -ExpectSave
if (-not $advanceRun.Passed) {
    [pscustomobject]@{ Passed = $false; FixtureHash = $fixtureHashBefore; AdvanceRun = $advanceRun } | ConvertTo-Json -Depth 6
    exit 1
}

$lifecycleHash = (Get-FileHash $lifecycleSave -Algorithm SHA256).Hash
$reloadRun = Invoke-CampaignLifecycleRun -Mode 'verify-load' -LoadSaveName $LifecycleSaveName -ExpectedLoadCount 1
$fixtureHashAfter = (Get-FileHash $fixtureSave -Algorithm SHA256).Hash

$result = [ordered]@{
    FixtureSaveName = $FixtureSaveName
    FixtureSavePath = $fixtureSave
    FixtureUnchanged = $fixtureHashBefore -eq $fixtureHashAfter
    FixtureHash = $fixtureHashAfter
    LifecycleSaveName = $LifecycleSaveName
    LifecycleSavePath = $lifecycleSave
    LifecycleSaveHash = $lifecycleHash
    LauncherVersion = (Get-Item $launcher).VersionInfo.ProductVersion
    AdvanceRun = $advanceRun
    ReloadRun = $reloadRun
    Passed = ($advanceRun.Passed -and $reloadRun.Passed -and $fixtureHashBefore -eq $fixtureHashAfter)
}
$result | ConvertTo-Json -Depth 8
if (-not $result.Passed) { exit 1 }
