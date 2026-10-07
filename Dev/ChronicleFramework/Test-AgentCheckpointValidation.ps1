[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$loop = Join-Path $PSScriptRoot 'Agent-DecisionLoop.ps1'
$provider = Join-Path $PSScriptRoot 'Test-AgentLoopProvider.ps1'
$saveRoot = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\Game Saves'
$sourceSavePath = Join-Path $saveRoot ($LoadSaveName + '.sav')
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$priorHarnessMode = $env:CHRONICLE_HARNESS_MODE
$priorProviderMode = $env:CHRONICLE_TEST_PROVIDER_MODE
$fixtureHashBefore = (Get-FileHash -LiteralPath $sourceSavePath -Algorithm SHA256).Hash
$scenarios = @(
    [pscustomobject]@{ Mode = 'corrupt-json'; ExpectedError = 'checkpoint is corrupt or unreadable' }
    [pscustomobject]@{ Mode = 'unsupported-schema'; ExpectedError = 'schema version.*unsupported' }
    [pscustomobject]@{ Mode = 'wrong-campaign'; ExpectedError = 'different Campaign instance' }
)
$results = [System.Collections.Generic.List[object]]::new()

if (Get-Process -Name Bannerlord* -ErrorAction SilentlyContinue) { throw 'Refusing to start checkpoint validation while a Bannerlord client is already running.' }
if (-not (Test-Path -LiteralPath $sourceSavePath -PathType Leaf)) { throw "Disposable checkpoint source save not found: $sourceSavePath" }
if (-not $env:CHRONICLE_HARNESS_TEMP -or -not (Test-Path -LiteralPath $env:CHRONICLE_HARNESS_TEMP -PathType Container)) { throw 'Checkpoint validation requires an active Harness TestResults temp directory.' }

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $env:CHRONICLE_TEST_PROVIDER_MODE = 'checkpointMustNotCall'
    foreach ($scenario in $scenarios) {
        $saveName = 'ChronicleBadCheckpoint-' + [string]$scenario.Mode + '-' + [Guid]::NewGuid().ToString('N')
        $savePath = Join-Path $saveRoot ($saveName + '.sav')
        $saveBackup = $savePath + '.bak'
        $started = $false
        try {
            if (Test-Path -LiteralPath $savePath -PathType Leaf) { throw 'Generated invalid-checkpoint save name unexpectedly exists.' }
            $null = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
            $started = $true
            $seed = Invoke-AgentCli 'harnessSeedAgentCheckpointFailure' @('-CheckpointFailureMode', [string]$scenario.Mode, '-CommandId', ('checkpoint-seed-' + [Guid]::NewGuid().ToString('N')))
            if ($seed.status -ne 'completed' -or [string]$seed.data.mode -cne [string]$scenario.Mode) { throw "Native Harness did not seed the requested '$($scenario.Mode)' checkpoint variant." }
            $save = Invoke-AgentCli 'save' @('-SaveName', $saveName, '-CommandId', ('checkpoint-save-' + [Guid]::NewGuid().ToString('N')))
            if ($save.status -ne 'completed' -or -not (Test-Path -LiteralPath $savePath -PathType Leaf)) { throw 'Native save of the disposable invalid-checkpoint fixture did not complete.' }
            $stop = Invoke-AgentCli 'stop' @('-CommandId', ('checkpoint-stop-' + [Guid]::NewGuid().ToString('N')))
            $started = $false
            if (-not $stop.processStopped -or (Get-Process -Name Bannerlord* -ErrorAction SilentlyContinue)) { throw 'Game/Agent process did not stop before invalid-checkpoint reload.' }
            $null = Invoke-AgentCli 'load' @('-SaveName', $saveName)
            $started = $true
            $before = Invoke-AgentCli 'state' @('-CommandId', ('checkpoint-before-resume-' + [Guid]::NewGuid().ToString('N')))
            $resumeOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -AllowedActionNames 'mapSettlementTargets,move' -ResumeCheckpoint -MaxDecisions 1 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('checkpoint-invalid-' + $scenario.Mode) 2>&1 | Out-String
            $resumeExitCode = $LASTEXITCODE
            $resumeResult = $null
            try { $resumeResult = $resumeOutput | ConvertFrom-Json } catch { }
            $after = Invoke-AgentCli 'state' @('-CommandId', ('checkpoint-after-resume-' + [Guid]::NewGuid().ToString('N')))
            $noWorldMutation = (
                [string]$before.state.location.currentSettlementId -ceq [string]$after.state.location.currentSettlementId -and
                [string]$before.state.location.targetSettlementId -ceq [string]$after.state.location.targetSettlementId -and
                [int]$before.state.party.members -eq [int]$after.state.party.members -and
                [int]$before.state.party.prisoners -eq [int]$after.state.party.prisoners -and
                [int]$before.state.economy.gold -eq [int]$after.state.economy.gold -and
                [double]$before.campaignDay -eq [double]$after.campaignDay -and
                [string]$before.state.context.timeControlMode -ceq [string]$after.state.context.timeControlMode
            )
            $safeStop = ($resumeExitCode -ne 0 -and $null -ne $resumeResult -and $resumeResult.status -eq 'failed' -and [string]$resumeResult.error -match $scenario.ExpectedError -and [string]$resumeResult.error -notmatch 'checkpoint-provider-was-called' -and @($resumeResult.trace).Count -eq 0 -and $noWorldMutation)
            $results.Add([pscustomobject]@{
                Scenario = [string]$scenario.Mode
                ExpectedClassification = [string]$scenario.ExpectedError
                DecisionLoopExitCode = $resumeExitCode
                FailureReason = if ($resumeResult) { [string]$resumeResult.error } else { 'DecisionLoop returned no structured failure.' }
                ProviderWasNotCalled = ([string]$resumeResult.error -notmatch 'checkpoint-provider-was-called')
                NoNativeActionTrace = if ($resumeResult) { @($resumeResult.trace).Count -eq 0 } else { $false }
                WorldStateUnchanged = $noWorldMutation
                SafeStop = $safeStop
            })
        }
        finally {
            if ($started -or (Test-Path -LiteralPath $sessionPath -PathType Leaf)) { try { $null = Invoke-AgentCli 'stop' @('-CommandId', ('checkpoint-final-stop-' + [Guid]::NewGuid().ToString('N'))) 15 } catch { } }
            if (Test-Path -LiteralPath $savePath -PathType Leaf) {
                $saveRootFull = [IO.Path]::GetFullPath($saveRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
                $resolvedSavePath = [IO.Path]::GetFullPath($savePath)
                if (-not $resolvedSavePath.StartsWith($saveRootFull, [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid-checkpoint cleanup target escaped Game Saves.' }
                Remove-Item -LiteralPath $resolvedSavePath -Force
            }
            if (Test-Path -LiteralPath $saveBackup -PathType Leaf) { Remove-Item -LiteralPath $saveBackup -Force }
        }
    }
}
finally {
    if ($null -eq $priorHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue } else { $env:CHRONICLE_HARNESS_MODE = $priorHarnessMode }
    if ($null -eq $priorProviderMode) { Remove-Item Env:CHRONICLE_TEST_PROVIDER_MODE -ErrorAction SilentlyContinue } else { $env:CHRONICLE_TEST_PROVIDER_MODE = $priorProviderMode }
}

$fixtureHashAfter = if (Test-Path -LiteralPath $sourceSavePath -PathType Leaf) { (Get-FileHash -LiteralPath $sourceSavePath -Algorithm SHA256).Hash } else { $null }
$result = [ordered]@{
    ProviderKind = 'deterministic sentinel Provider; expected never to run'
    Passed = ($results.Count -eq $scenarios.Count -and @($results | Where-Object { -not $_.SafeStop }).Count -eq 0 -and $fixtureHashBefore -ceq $fixtureHashAfter -and -not (Get-Process -Name Bannerlord* -ErrorAction SilentlyContinue) -and -not (Test-Path -LiteralPath $sessionPath -PathType Leaf))
    Scenarios = @($results)
    SourceFixtureUnchanged = ($fixtureHashBefore -ceq $fixtureHashAfter)
    ProcessStopped = (-not (Get-Process -Name Bannerlord* -ErrorAction SilentlyContinue) -and -not (Test-Path -LiteralPath $sessionPath -PathType Leaf))
}
$result | ConvertTo-Json -Depth 10
if (-not $result.Passed) { exit 1 }
