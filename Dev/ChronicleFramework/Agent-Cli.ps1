[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet('start','load','state','captureFrame','inventoryTakeAll','inventoryDone','seedVisualLoot','advance','pause','resume','move','pursue','follow','hold','menu','menuSelect','dialogueSelect','dialogueContinue','battlePause','battleSkip','battleFinish','battleRetreat','missionRetreat','partyTakeAll','partyScreenDone','rest','recruitOptions','recruit','foodOptions','tradeOptions','trade','provision','save','stop')]
    [string]$Action,
    [string]$SaveName,
    [string]$SettlementId,
    [string]$PartyId,
    [string]$MenuId,
    [string]$OptionId,
    [string]$OwnerId,
    [string]$TroopId,
    [ValidateSet('members','prisoners')][string]$LootType,
    [int]$VolunteerSlot = -1,
    [string]$ItemId,
    [string]$Direction,
    [string]$OutputPath,
    [int]$Amount = 1,
    [double]$Days = 0.01,
    [string]$CommandId,
    [int]$TimeoutSeconds = 180,
    [switch]$ReturnWhenAccepted,
    [Alias('json')]
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
$gameRoot = if ($env:CHRONICLE_GAME_ROOT -and (Test-Path -LiteralPath $env:CHRONICLE_GAME_ROOT)) { [IO.Path]::GetFullPath($env:CHRONICLE_GAME_ROOT) } else { Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$binDirectory = Join-Path $gameRoot 'bin\Win64_Shipping_Client'
$launcher = Join-Path $binDirectory 'Bannerlord.BLSE.Standalone.exe'
$documentsRoot = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord'
$saveDirectory = Join-Path $documentsRoot 'Game Saves'
$diagnosticLog = Join-Path $documentsRoot 'Configs\ModLogs\chronicle-framework.log'
$engineConfig = Join-Path $documentsRoot 'Configs\engine_config.txt'
$protocolRoot = Join-Path $documentsRoot 'AgentRuns\ChronicleAgent'
$responseRoot = Join-Path $protocolRoot 'responses'
$commandPath = Join-Path $protocolRoot 'command.json'
$sessionPath = Join-Path $protocolRoot 'session.json'
New-Item -ItemType Directory -Force -Path $protocolRoot,$responseRoot | Out-Null
. (Join-Path $PSScriptRoot 'Agent-SaveMetadata.ps1')
. (Join-Path $PSScriptRoot 'Test-WindowLayout.ps1')

function Set-SafeExitMarker {
    if (Test-Path $engineConfig) {
        $engineText = Get-Content $engineConfig -Raw
        $engineText = $engineText -replace 'safely_exited\s*=\s*0', 'safely_exited = 1'
        Set-Content -Path $engineConfig -Value $engineText -NoNewline
    }
}

function Write-Result($Value) {
    $Value | ConvertTo-Json -Depth 8
}

function Get-Session {
    if (-not (Test-Path $sessionPath)) { throw 'No active Chronicle Agent session.' }
    $session = Get-Content $sessionPath -Raw | ConvertFrom-Json
    if (-not (Get-Process -Id $session.processId -ErrorAction SilentlyContinue)) {
        throw "Chronicle Agent session process $($session.processId) is not running."
    }
    return $session
}

function Get-DescendantProcessIds([int]$ParentId) {
    $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId = $ParentId" -ErrorAction SilentlyContinue)
    foreach ($child in $children) {
        [int]$child.ProcessId
        Get-DescendantProcessIds -ParentId $child.ProcessId
    }
}

function Stop-AgentProcessTree([int]$RootProcessId) {
    $descendants = @(Get-DescendantProcessIds -ParentId $RootProcessId)
    foreach ($id in @($descendants + $RootProcessId) | Where-Object { $_ } | Select-Object -Unique) {
        Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
    }
    $deadline = (Get-Date).AddSeconds(15)
    do {
        $remaining = @($descendants + $RootProcessId | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue })
        if ($remaining.Count -eq 0) { return $true }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    return $false
}

function Invoke-ProtocolCommand([string]$ProtocolAction, [hashtable]$Arguments = @{}, [switch]$ReturnWhenAccepted) {
    $session = Get-Session
    $id = if ($CommandId) { $CommandId } else { 'cli-' + [Guid]::NewGuid().ToString('N') }
    $payload = [ordered]@{ id = $id; action = $ProtocolAction }
    foreach ($key in $Arguments.Keys) { $payload[$key] = $Arguments[$key] }
    $expectedStatus = if ($ReturnWhenAccepted) { 'accepted' } else { 'completed' }
    $responsePath = Join-Path $responseRoot "$id.$expectedStatus.json"
    $temporaryPath = "$commandPath.$id.tmp"
    $payload | ConvertTo-Json -Compress | Set-Content -Path $temporaryPath -Encoding UTF8
    Move-Item -LiteralPath $temporaryPath -Destination $commandPath -Force
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path $responsePath) {
            return Get-Content $responsePath -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        foreach ($terminalStatus in @('failed','rejected')) {
            $terminalPath = Join-Path $responseRoot "$id.$terminalStatus.json"
            if (Test-Path $terminalPath) {
                return Get-Content $terminalPath -Raw -Encoding UTF8 | ConvertFrom-Json
            }
        }
        if (-not (Get-Process -Id $session.processId -ErrorAction SilentlyContinue)) {
            throw "Game process $($session.processId) exited before command '$id' completed."
        }
        Start-Sleep -Milliseconds 100
    }
    throw "Command '$id' timed out after $TimeoutSeconds seconds."
}

if ($Action -in @('start','load')) {
    if (-not $SaveName) { throw '-SaveName is required for start/load in the P2 campaign prototype.' }
    $savePath = Join-Path $saveDirectory "$SaveName.sav"
    if (-not (Test-Path $savePath)) { throw "Save not found: $savePath" }
    $processNames = @('Bannerlord','Bannerlord.BLSE.Standalone','TaleWorlds.MountAndBlade.Launcher')
    $shutdownDeadline = (Get-Date).AddSeconds(15)
    do {
        $runningGame = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -in $processNames })
        if ($runningGame.Count -eq 0) { break }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $shutdownDeadline)
    if ($runningGame.Count -gt 0) { throw "Bannerlord is already running: $($runningGame.ProcessName -join ', ')." }
    $modules = @(Get-AgentSaveModuleIds -SavePath $savePath)
    $installedModuleIds = @()
    foreach ($moduleDirectory in Get-ChildItem -LiteralPath (Join-Path $gameRoot 'Modules') -Directory) {
        $moduleManifestPath = Join-Path $moduleDirectory.FullName 'SubModule.xml'
        if (-not (Test-Path -LiteralPath $moduleManifestPath)) { continue }
        try { $installedModuleIds += [string]([xml](Get-Content -LiteralPath $moduleManifestPath -Raw -Encoding UTF8)).Module.Id.value }
        catch { }
    }
    $missingSaveModules = @($modules | Where-Object { $_ -notin $installedModuleIds })
    if ($missingSaveModules.Count -gt 0) { throw "Save requires modules that are not installed in the configured game root: $($missingSaveModules -join ', ')." }
    $moduleArgument = '_MODULES_*' + ($modules -join '*') + '*_MODULES_'
    $diagnosticStartLineCount = if (Test-Path $diagnosticLog) { @(Get-Content $diagnosticLog).Count } else { 0 }
    $expectedHarnessMode = if ([string]::IsNullOrWhiteSpace($env:CHRONICLE_HARNESS_MODE)) { 'normal' } else { $env:CHRONICLE_HARNESS_MODE }
    Set-ChronicleTestDisplayConfig -EngineConfigPath $engineConfig
    Set-SafeExitMarker
    $process = Start-Process -FilePath $launcher -ArgumentList "/continuesave $SaveName $moduleArgument /anticheat" -WorkingDirectory $binDirectory -WindowStyle Minimized -PassThru
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $ready = $false
    $windowLayout = $null
    while ((Get-Date) -lt $deadline) {
        $launchProcess = Get-Process -Id $process.Id -ErrorAction SilentlyContinue
        if (-not $launchProcess) { break }
        if ($launchProcess.MainWindowTitle -match '^Mod change detected$') {
            $blockedWindowTitle = $launchProcess.MainWindowTitle
            Stop-AgentProcessTree -RootProcessId $process.Id | Out-Null
            Set-SafeExitMarker
            throw "Campaign launch stopped at Bannerlord's '$blockedWindowTitle' dialog. In v1.4.8 this is the native shader-cache invalidation notice; it does not prove the save module list is incompatible. The notice requires acknowledging cache regeneration once for this module set. No game-window input was sent."
        }
        $candidateLayout = Set-ChronicleTestWindow -ProcessId $process.Id
        if ($candidateLayout -and $candidateLayout.Applied) { $windowLayout = $candidateLayout }
        if (Test-Path $diagnosticLog) {
            $lines = @(Get-Content $diagnosticLog)
            $newLines = @($lines | Select-Object -Skip $diagnosticStartLineCount)
            $ready = [bool]($newLines | Where-Object { $_ -match "\|pid=$($process.Id)\|campaign-loaded\|mode=$([regex]::Escape($expectedHarnessMode))\|" })
        }
        if ($ready) { break }
        Start-Sleep -Milliseconds 250
    }
    if (-not $ready) {
        Stop-AgentProcessTree -RootProcessId $process.Id | Out-Null
        Set-SafeExitMarker
        throw 'Campaign did not reach protocol-ready state.'
    }
    $windowLayout = Set-ChronicleTestWindow -ProcessId $process.Id
    if (-not $windowLayout -or -not $windowLayout.Applied) { throw 'Windowed test layout was not verified.' }
    $session = [ordered]@{ protocolVersion = 1; processId = $process.Id; saveName = $SaveName; moduleSet = $modules; startedUtc = (Get-Date).ToUniversalTime().ToString('O'); windowLayout = $windowLayout }
    $session | ConvertTo-Json | Set-Content -Path $sessionPath -Encoding UTF8
    $configuredTimeout = $TimeoutSeconds
    $TimeoutSeconds = [Math]::Min(30, $TimeoutSeconds)
    try {
        $protocolProbe = Invoke-ProtocolCommand 'state'
        if ($protocolProbe.status -ne 'completed' -or -not $protocolProbe.state) { throw 'Agent protocol returned no structured initial state.' }
    }
    catch {
        $handshakeError = $_.Exception.Message
        Stop-AgentProcessTree -RootProcessId $process.Id | Out-Null
        Set-SafeExitMarker
        Remove-Item -LiteralPath $sessionPath -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $commandPath) {
            try { if ((Get-Content -LiteralPath $commandPath -Raw -Encoding UTF8 | ConvertFrom-Json).action -eq 'state') { Remove-Item -LiteralPath $commandPath -Force -ErrorAction SilentlyContinue } } catch { }
        }
        throw "Campaign-loaded marker appeared, but Agent Protocol handshake failed: $handshakeError"
    }
    finally { $TimeoutSeconds = $configuredTimeout }
    Write-Result ([ordered]@{ action = $Action; status = 'completed'; session = $session })
    exit 0
}

switch ($Action) {
    'state' { $result = Invoke-ProtocolCommand 'state' }
    'captureFrame' {
        if (-not $OutputPath) { throw '-OutputPath is required for captureFrame.' }
        $result = Invoke-ProtocolCommand 'captureFrame' @{ fileName = [IO.Path]::GetFileName($OutputPath) }
    }
    'inventoryTakeAll' { $result = Invoke-ProtocolCommand 'inventoryTakeAll' }
    'inventoryDone' { $result = Invoke-ProtocolCommand 'inventoryDone' }
    'seedVisualLoot' { $result = Invoke-ProtocolCommand 'seedVisualLoot' }
    'advance' { $result = Invoke-ProtocolCommand 'advance' @{ days = $Days } }
    'pause' { $result = Invoke-ProtocolCommand 'pause' }
    'resume' { $result = Invoke-ProtocolCommand 'resume' }
    'move' {
        if (-not $SettlementId) { throw '-SettlementId is required for move.' }
        $result = Invoke-ProtocolCommand 'move' @{ settlementId = $SettlementId }
    }
    'pursue' {
        if (-not $PartyId) { throw '-PartyId is required for pursue.' }
        $result = Invoke-ProtocolCommand 'pursue' @{ partyId = $PartyId }
    }
    'follow' {
        if (-not $PartyId) { throw '-PartyId is required for follow.' }
        $result = Invoke-ProtocolCommand 'follow' @{ partyId = $PartyId }
    }
    'hold' { $result = Invoke-ProtocolCommand 'hold' }
    'menu' { $result = Invoke-ProtocolCommand 'menu' }
    'menuSelect' {
        if (-not $MenuId -or -not $OptionId) { throw '-MenuId and -OptionId are required for menuSelect.' }
        $result = Invoke-ProtocolCommand 'menuSelect' @{ menuId = $MenuId; optionId = $OptionId }
    }
    'dialogueSelect' {
        if (-not $OptionId) { throw '-OptionId is required for dialogueSelect.' }
        $result = Invoke-ProtocolCommand 'dialogueSelect' @{ optionId = $OptionId }
    }
    'dialogueContinue' { $result = Invoke-ProtocolCommand 'dialogueContinue' }
    'battlePause' { $result = Invoke-ProtocolCommand 'battlePause' }
    'battleSkip' { $result = Invoke-ProtocolCommand 'battleSkip' }
    'battleFinish' { $result = Invoke-ProtocolCommand 'battleFinish' }
    'battleRetreat' { $result = Invoke-ProtocolCommand 'battleRetreat' }
    'missionRetreat' { $result = Invoke-ProtocolCommand 'missionRetreat' }
    'partyTakeAll' {
        if (-not $LootType) { throw '-LootType is required for partyTakeAll.' }
        $result = Invoke-ProtocolCommand 'partyTakeAll' @{ troopType = $LootType }
    }
    'partyScreenDone' { $result = Invoke-ProtocolCommand 'partyScreenDone' }
    'rest' { $result = Invoke-ProtocolCommand 'rest' @{ days = $Days } -ReturnWhenAccepted:$ReturnWhenAccepted }
    'recruitOptions' { $result = Invoke-ProtocolCommand 'recruitOptions' }
    'recruit' {
        if (-not $OwnerId -or -not $TroopId -or $VolunteerSlot -lt 0) { throw '-OwnerId, -TroopId and -VolunteerSlot are required for recruit.' }
        $result = Invoke-ProtocolCommand 'recruit' @{ ownerId = $OwnerId; troopId = $TroopId; slot = $VolunteerSlot }
    }
    'foodOptions' { $result = Invoke-ProtocolCommand 'foodOptions' }
    'tradeOptions' { $result = Invoke-ProtocolCommand 'tradeOptions' }
    'trade' {
        if ($Direction -notin @('buy','sell') -or -not $ItemId -or $Amount -le 0) { throw '-Direction (buy/sell), -ItemId and positive -Amount are required for trade.' }
        $result = Invoke-ProtocolCommand 'trade' @{ direction = $Direction; itemId = $ItemId; amount = $Amount }
    }
    'provision' {
        if (-not $ItemId -or $Amount -le 0) { throw '-ItemId and a positive -Amount are required for provision.' }
        $result = Invoke-ProtocolCommand 'provision' @{ itemId = $ItemId; amount = $Amount }
    }
    'save' {
        if (-not $SaveName) { throw '-SaveName is required for save.' }
        $result = Invoke-ProtocolCommand 'save' @{ name = $SaveName }
    }
    'stop' {
        $session = Get-Session
        $receipt = $null
        $commandError = $null
        try { $receipt = Invoke-ProtocolCommand 'stop' }
        catch { $commandError = $_.Exception.Message }
        $processStopped = Stop-AgentProcessTree -RootProcessId ([int]$session.processId)
        Set-SafeExitMarker
        Remove-Item -LiteralPath $sessionPath -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $commandPath) {
            try { if ((Get-Content -LiteralPath $commandPath -Raw -Encoding UTF8 | ConvertFrom-Json).action -eq 'stop') { Remove-Item -LiteralPath $commandPath -Force -ErrorAction SilentlyContinue } } catch { }
        }
        $result = [ordered]@{ protocolVersion = 1; action = 'stop'; status = if ($processStopped) { 'completed' } else { 'failed' }; processId = $session.processId; processStopped = $processStopped; receipt = $receipt; commandError = $commandError }
    }
}

Write-Result $result
