[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [ValidateRange(2,10)][int]$CaptureSeconds = 6,
    [ValidateRange(10,60)][int]$FrameRate = 30,
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$videoCaptureLibrary = Join-Path $PSScriptRoot 'HarnessVideoCapture.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$runDirectory = if ($env:CHRONICLE_HARNESS_TEMP) { Split-Path -Parent $env:CHRONICLE_HARNESS_TEMP } else { Join-Path $PSScriptRoot 'TestResults\ManualVisualCapture' }
$videoPath = Join-Path $runDirectory 'CampaignWindow.mp4'
$framePath = Join-Path $runDirectory 'CampaignWindow-frame.jpg'
$contactSheetPath = Join-Path $runDirectory 'CampaignWindow-contact.jpg'
$engineFramePath = Join-Path $runDirectory 'CampaignEngine-frame.bmp'
$eventTracePath = Join-Path $runDirectory 'CampaignWindow-events.jsonl'
if (-not (Test-Path $savePath)) { throw "Visual capture fixture not found: $savePath" }
if (Get-Process Bannerlord -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash $savePath -Algorithm SHA256).Hash
$priorHarnessMode = $env:CHRONICLE_HARNESS_MODE
$capture = $null

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

function Write-CaptureEvent([string]$Name, $Receipt, [long]$CaptureStartTicks, [long]$Frequency) {
    $nowTicks = [Diagnostics.Stopwatch]::GetTimestamp()
    $state = if ($Receipt -and $Receipt.state) { $Receipt.state } else { $null }
    $event = [ordered]@{
        event = $Name
        utc = (Get-Date).ToUniversalTime().ToString('O')
        stopwatchTicks = $nowTicks
        offsetMilliseconds = if ($CaptureStartTicks -gt 0) { [Math]::Round(($nowTicks - $CaptureStartTicks) * 1000.0 / $Frequency, 2) } else { 0 }
        commandId = if ($Receipt) { [string]$Receipt.commandId } else { $null }
        action = if ($Receipt) { [string]$Receipt.action } else { $null }
        gameState = if ($state) { [string]$state.context.gameState } else { $null }
        menuId = if ($state) { [string]$state.context.menuId } else { $null }
        partyScreenMode = if ($state -and $state.partyScreen) { [string]$state.partyScreen.mode } else { $null }
        inventoryMode = if ($state -and $state.inventoryScreen) { [string]$state.inventoryScreen.mode } else { $null }
        campaignDay = if ($Receipt) { $Receipt.campaignDay } else { $null }
    }
    Add-Content -LiteralPath $eventTracePath -Value ($event | ConvertTo-Json -Compress -Depth 5) -Encoding UTF8
}

try {
    . $videoCaptureLibrary
    $captureRecoveryProof = Test-ChronicleFragmentedCaptureResilience -EvidencePath (Join-Path $runDirectory 'CampaignWindow-CaptureRecovery.json')
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $before = Invoke-AgentCli 'state' @('-CommandId', ('visual-capture-before-' + [Guid]::NewGuid().ToString('N')))
    if ($before.state.context.gameState -ne 'MapState') { throw "Visual fixture is not on campaign map: $($before.state.context.gameState)." }

    $engineFrameTemp = Join-Path $env:CHRONICLE_HARNESS_TEMP 'engine-reference.bmp'
    $still = Invoke-AgentCli 'captureFrame' @('-OutputPath', $engineFrameTemp, '-CommandId', ('visual-capture-still-' + [Guid]::NewGuid().ToString('N'))) 15
    $stillDeadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path $engineFrameTemp) -and [DateTime]::UtcNow -lt $stillDeadline) { Start-Sleep -Milliseconds 100 }
    if ($still.status -ne 'completed' -or -not (Test-Path $engineFrameTemp) -or (Get-Item $engineFrameTemp).Length -lt 4096) { throw 'Engine-native single-frame screenshot failed.' }
    Move-Item -LiteralPath $engineFrameTemp -Destination $engineFramePath -Force

    $capture = Start-ChronicleWindowVideoCapture -ProcessId ([int]$start.session.processId) -OutputPath $videoPath -FrameRate $FrameRate
    Write-CaptureEvent 'capture-start' $before $capture.StartedTicks $capture.StopwatchFrequency
    Start-Sleep -Seconds $CaptureSeconds
    $after = Invoke-AgentCli 'state' @('-CommandId', ('visual-capture-after-' + [Guid]::NewGuid().ToString('N')))
    Write-CaptureEvent 'capture-end' $after $capture.StartedTicks $capture.StopwatchFrequency
    if ($after.state.context.gameState -ne 'MapState') { throw "Capture fixture left MapState unexpectedly: $($after.state.context.gameState)." }
    $captureResult = Stop-ChronicleWindowVideoCapture -Capture $capture -ContactSheetPath $contactSheetPath -EventTracePath $eventTracePath
    $capture = $null
    $timelineIndex = Get-Content -LiteralPath $captureResult.TimelineIndexPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $reviewFrameSource = [string]$timelineIndex.selections[-1].eventFramePath
    if ([string]::IsNullOrWhiteSpace($reviewFrameSource) -or -not (Test-Path -LiteralPath $reviewFrameSource)) { throw 'Timeline index did not produce a reviewable full-resolution event frame.' }
    Copy-Item -LiteralPath $reviewFrameSource -Destination $framePath -Force

    $stop = Invoke-AgentCli 'stop' @('-CommandId', ('visual-capture-stop-game-' + [Guid]::NewGuid().ToString('N'))) 15
    $fixtureHashAfter = (Get-FileHash $savePath -Algorithm SHA256).Hash
    $result = [ordered]@{
        Capture = $captureResult
        CaptureRecoveryProof = $captureRecoveryProof
        EngineStillPath = $engineFramePath
        ReviewFramePath = $framePath
        EventTracePath = $eventTracePath
        ObservedGameState = $after.state.context.gameState
        FixtureUnchanged = $fixtureHashBefore -eq $fixtureHashAfter
        ProcessStopped = $stop.processStopped
    }
    $result.Passed = ($result.Capture.Passed -and $result.Capture.FrameCoverageRatio -ge 0.9 -and $result.Capture.WindowTitle -match 'Bannerlord' -and $result.ObservedGameState -eq 'MapState' -and $result.FixtureUnchanged -and $result.ProcessStopped)
    $result | ConvertTo-Json -Depth 8
    if (-not $result.Passed) { exit 1 }
}
finally {
    if ($capture -and $capture.Process -and -not $capture.Process.HasExited) {
        try {
            $partialContactPath = Join-Path $runDirectory 'CampaignWindow-partial-contact.jpg'
            $partialResult = Stop-ChronicleWindowVideoCapture -Capture $capture -ContactSheetPath $partialContactPath -EventTracePath $eventTracePath
            $partialResult | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $runDirectory 'CampaignWindow-partial.json') -Encoding UTF8
        }
        catch {
            [ordered]@{ stoppedUtc = (Get-Date).ToUniversalTime().ToString('O'); error = $_.Exception.Message; videoPath = $videoPath; eventTracePath = $eventTracePath } |
                ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $runDirectory 'CampaignWindow-partial.json') -Encoding UTF8
            try { $capture.Process.Kill() } catch { }
        }
    }
    if (Test-Path $sessionPath) { try { Invoke-AgentCli 'stop' @('-CommandId', ('visual-capture-cleanup-' + [Guid]::NewGuid().ToString('N'))) 15 | Out-Null } catch { } }
    if ($null -eq $priorHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $priorHarnessMode }
}
