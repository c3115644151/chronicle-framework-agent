[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9_-]{1,8}$')]
    [string]$CampaignKey,
    [ValidateRange(30,600)]
    [int]$TimeoutSeconds = 240
)

$ErrorActionPreference = 'Stop'
$CampaignKey = $CampaignKey.Trim()
$documentsPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
if ([string]::IsNullOrWhiteSpace($documentsPath)) { throw 'Cannot resolve the Bannerlord save root.' }
$saveRoot = [IO.Path]::GetFullPath((Join-Path $documentsPath 'Mount and Blade II Bannerlord\Game Saves'))
$saveRootPrefix = $saveRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
$manifestPath = Join-Path $PSScriptRoot ('TestResults\PersistentEycCampaign-' + $CampaignKey + '.json')
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$sessionPath = Join-Path $documentsPath 'Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$resultPath = Join-Path (Split-Path -Parent $env:CHRONICLE_HARNESS_TEMP) 'PersistentEycObjectiveCheckpointReadback.json'
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$sessionStarted = $false
$result = [ordered]@{
    Passed = $false
    ProviderCalls = 0
    ModelCostCny = 0
    CampaignKey = $CampaignKey
    CampaignInstanceMatched = $false
    ObjectiveAttemptPropertyPresent = $false
    CompanionAttemptStatus = $null
    CheckpointSaveName = $null
    CheckpointSaveSha256 = $null
    SourceSaveUnchanged = $false
    ProcessStopped = $false
    Failure = $null
}

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @()) {
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli $Action @Arguments -TimeoutSeconds $TimeoutSeconds -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

try {
    if ([string]::IsNullOrWhiteSpace($env:CHRONICLE_HARNESS_TEMP) -or -not (Test-Path -LiteralPath $env:CHRONICLE_HARNESS_TEMP -PathType Container)) {
        throw 'Checkpoint readback requires a Run-Harness evidence directory.'
    }
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'The requested persistent Campaign manifest does not exist.' }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$manifest.schemaVersion -ne 1 -or [string]$manifest.project -cne 'ChronicleFramework' -or
        [string]$manifest.campaignKey -cne $CampaignKey -or [string]::IsNullOrWhiteSpace([string]$manifest.campaignInstanceId) -or
        [string]::IsNullOrWhiteSpace([string]$manifest.saveName) -or [string]$manifest.saveName -notmatch '^ChronicleEycDev-[A-Za-z0-9_-]{1,32}$') {
        throw 'The persistent Campaign manifest identity is invalid; no save was loaded.'
    }
    $savePath = [IO.Path]::GetFullPath((Join-Path $saveRoot ([string]$manifest.saveName + '.sav')))
    if (-not $savePath.StartsWith($saveRootPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $savePath -PathType Leaf)) { throw 'The manifest save is missing or escaped the Game Saves root.' }
    $sourceHash = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    if ($sourceHash -cne [string]$manifest.sha256) { throw 'The owned Campaign save hash differs from its manifest; refusing to load it.' }
    if (Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue) { throw 'Refusing to start checkpoint readback while Bannerlord is already running.' }
    if (Test-Path -LiteralPath $sessionPath -PathType Leaf) { throw 'A Chronicle Agent session file exists; refusing to take ownership of another session.' }

    $result.CheckpointSaveName = [string]$manifest.saveName
    $result.CheckpointSaveSha256 = $sourceHash
    $result.CampaignInstanceMatched = $false
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $load = Invoke-AgentCli 'load' @('-SaveName', [string]$manifest.saveName, '-IncludeChronicleFramework')
    if ($load.status -ne 'completed') { throw 'Native Campaign did not load the owned checkpoint.' }
    $sessionStarted = $true
    $checkpointReceipt = Invoke-AgentCli 'agentCheckpointGet' @('-CommandId', ('eyc-attempt-readback-' + [Guid]::NewGuid().ToString('N')))
    if ($checkpointReceipt.status -ne 'completed' -or
        [string]$checkpointReceipt.data.campaignInstanceId -cne [string]$manifest.campaignInstanceId -or
        [string]::IsNullOrWhiteSpace([string]$checkpointReceipt.data.checkpointBase64)) {
        throw 'Native checkpoint readback did not return the expected saved Campaign identity and payload.'
    }
    $checkpointJson = [Text.UTF8Encoding]::new($false, $true).GetString([Convert]::FromBase64String([string]$checkpointReceipt.data.checkpointBase64))
    $checkpoint = $checkpointJson | ConvertFrom-Json
    if ([int]$checkpoint.schemaVersion -notin @(1,2) -or [string]$checkpoint.campaignInstanceId -cne [string]$manifest.campaignInstanceId) {
        throw 'The loaded checkpoint payload is not bound to this Campaign instance.'
    }
    $memory = $checkpoint.eycObjectiveAttemptMemoryV1
    $attempt = $memory.attempts.companions
    if ([int]$memory.schemaVersion -ne 1 -or $null -eq $attempt -or
        [string]$attempt.status -notin @('pending','blocked') -or
        [string]::IsNullOrWhiteSpace([string]$attempt.journalFingerprint) -or
        [string]::IsNullOrWhiteSpace([string]$attempt.nativeRouteFingerprint) -or
        [string]::IsNullOrWhiteSpace([string]$attempt.termination) -or $null -eq $attempt.journalSnapshot) {
        throw 'The saved checkpoint does not contain a well-formed Companion attempt record.'
    }
    $result.CampaignInstanceMatched = $true
    $result.ObjectiveAttemptPropertyPresent = $true
    $result.CompanionAttemptStatus = [string]$attempt.status
    $stop = Invoke-AgentCli 'stop' @('-CommandId', ('eyc-attempt-readback-stop-' + [Guid]::NewGuid().ToString('N')))
    $sessionStarted = $false
    $result.ProcessStopped = [bool]$stop.processStopped -and -not (Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue) -and -not (Test-Path -LiteralPath $sessionPath -PathType Leaf)
    $result.SourceSaveUnchanged = ((Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash -ceq $sourceHash)
    if (-not $result.ProcessStopped) { throw 'The read-only Native session did not cleanly stop.' }
    if (-not $result.SourceSaveUnchanged) { throw 'Read-only checkpoint inspection changed the source save.' }
    $result.Passed = $true
}
catch {
    $result.Failure = $_.Exception.Message
}
finally {
    if ($sessionStarted -or (Test-Path -LiteralPath $sessionPath -PathType Leaf)) {
        try {
            $stop = Invoke-AgentCli 'stop' @('-CommandId', ('eyc-attempt-readback-cleanup-' + [Guid]::NewGuid().ToString('N')))
            $result.ProcessStopped = [bool]$stop.processStopped -and -not (Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue) -and -not (Test-Path -LiteralPath $sessionPath -PathType Leaf)
        }
        catch { if (-not $result.Failure) { $result.Failure = "Cleanup failed: $($_.Exception.Message)" }; $result.Passed = $false }
    }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
}

$result | ConvertTo-Json -Depth 8
if (-not $result.Passed) { exit 1 }
