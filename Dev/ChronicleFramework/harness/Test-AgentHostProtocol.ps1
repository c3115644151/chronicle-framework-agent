#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$HostDllPath,
    [Parameter(Mandatory = $true)][string]$EvidenceDirectory
)

$ErrorActionPreference = 'Stop'
$hostDll = [IO.Path]::GetFullPath($HostDllPath)
$evidenceRoot = [IO.Path]::GetFullPath($EvidenceDirectory)
if (-not (Test-Path -LiteralPath $hostDll -PathType Leaf)) { throw "Agent Host DLL not found: $hostDll" }
New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null

function Start-AgentHost([string]$ProtocolRoot, [int]$TimeoutSeconds = 5) {
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = (Get-Command dotnet -ErrorAction Stop).Source
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.Arguments = '"{0}" --state-once --protocol-root "{1}" --timeout-seconds {2}' -f $hostDll, $ProtocolRoot, $TimeoutSeconds
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    if (-not $process.Start()) { throw 'Could not start local Agent Host test process.' }
    return $process
}

function Wait-HostCommand([Diagnostics.Process]$Process, [string]$CommandPath, [int]$TimeoutSeconds = 5) {
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-Path -LiteralPath $CommandPath -PathType Leaf) {
            return Get-Content -LiteralPath $CommandPath -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        if ($Process.HasExited) { break }
        Start-Sleep -Milliseconds 25
    }
    throw 'Agent Host did not publish a protocol command within the test bound.'
}

function Write-FakeStateResponse([string]$ProtocolRoot, [string]$CommandId, [string]$ResponseCommandId = $CommandId, [string]$Status = 'completed') {
    $responsePath = Join-Path (Join-Path $ProtocolRoot 'responses') "$CommandId.$Status.json"
    $response = [ordered]@{
        protocolVersion = 1
        commandId = $ResponseCommandId
        action = 'state'
        status = $Status
        processId = 4242
        campaignDay = 10.25
        dailyTickCount = 3
        timeControlMode = 'Stop'
        state = [ordered]@{
            identity = [ordered]@{ heroId = 'player_1'; clanId = 'player_clan' }
            party = [ordered]@{ id = 'main_party'; members = 6 }
            context = [ordered]@{ gameState = 'MapState' }
        }
    }
    $temporaryPath = "$responsePath.$([Guid]::NewGuid().ToString('N')).tmp"
    [IO.File]::WriteAllText($temporaryPath, ($response | ConvertTo-Json -Depth 6 -Compress), [Text.UTF8Encoding]::new($false))
    [IO.File]::Move($temporaryPath, $responsePath)
}

function Finish-Host([Diagnostics.Process]$Process, [int]$TimeoutSeconds = 8) {
    if (-not $Process.WaitForExit($TimeoutSeconds * 1000)) {
        try { $Process.Kill($true) } catch { }
        throw "Agent Host process did not exit within $TimeoutSeconds seconds."
    }
    $stdout = $Process.StandardOutput.ReadToEnd()
    $stderr = $Process.StandardError.ReadToEnd()
    return [pscustomobject]@{ ExitCode = $Process.ExitCode; Stdout = $stdout; Stderr = $stderr }
}

$results = [System.Collections.Generic.List[object]]::new()

# A stale response with a different correlation ID must not satisfy a new request.
$successRoot = Join-Path $evidenceRoot 'success'
New-Item -ItemType Directory -Path (Join-Path $successRoot 'responses') -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $successRoot 'responses/stale.completed.json'), '{"protocolVersion":1,"commandId":"stale"}')
$successProcess = Start-AgentHost -ProtocolRoot $successRoot
$successCommand = Wait-HostCommand -Process $successProcess -CommandPath (Join-Path $successRoot 'command.json')
if ($successCommand.action -cne 'state' -or [string]$successCommand.id -notmatch '^host-state-[0-9a-f]{32}$') {
    try { $successProcess.Kill($true) } catch { }
    throw 'Host emitted an unexpected or non-read-only command.'
}
Write-FakeStateResponse -ProtocolRoot $successRoot -CommandId $successCommand.id
$success = Finish-Host -Process $successProcess
if ($success.ExitCode -ne 0) { throw "Host rejected the matching Native response: $($success.Stderr)" }
$successData = $success.Stdout | ConvertFrom-Json
if ($successData.bannerlordProcessId -ne 4242 -or $successData.mainHeroId -ne 'player_1' -or $successData.mainPartyId -ne 'main_party') {
    throw 'Host summary did not preserve the matching Native identity and process evidence.'
}
$results.Add([ordered]@{ case = 'matching-response-and-stale-response-isolation'; passed = $true; commandId = $successCommand.id; action = $successCommand.action })

# An existing command belongs to another owner; Host must not replace it.
$busyRoot = Join-Path $evidenceRoot 'busy'
New-Item -ItemType Directory -Path (Join-Path $busyRoot 'responses') -Force | Out-Null
$busyPayload = '{"id":"other-owner","action":"move","settlementId":"town_V1"}'
$busyCommandPath = Join-Path $busyRoot 'command.json'
[IO.File]::WriteAllText($busyCommandPath, $busyPayload)
$busyProcess = Start-AgentHost -ProtocolRoot $busyRoot
$busy = Finish-Host -Process $busyProcess
if ($busy.ExitCode -ne 2 -or -not $busy.Stderr.Contains('protocol-command-busy') -or [IO.File]::ReadAllText($busyCommandPath) -cne $busyPayload) {
    throw 'Host did not preserve a command owned by another protocol client.'
}
$results.Add([ordered]@{ case = 'busy-mailbox-not-overwritten'; passed = $true })

# A response written to the matching file but carrying a different command ID is rejected.
$mismatchRoot = Join-Path $evidenceRoot 'mismatch'
New-Item -ItemType Directory -Path (Join-Path $mismatchRoot 'responses') -Force | Out-Null
$mismatchProcess = Start-AgentHost -ProtocolRoot $mismatchRoot
$mismatchCommand = Wait-HostCommand -Process $mismatchProcess -CommandPath (Join-Path $mismatchRoot 'command.json')
Write-FakeStateResponse -ProtocolRoot $mismatchRoot -CommandId $mismatchCommand.id -ResponseCommandId 'different-request'
$mismatch = Finish-Host -Process $mismatchProcess
if ($mismatch.ExitCode -ne 2 -or -not $mismatch.Stderr.Contains('protocol-correlation-mismatch')) {
    throw 'Host accepted a response that did not belong to its command.'
}
$results.Add([ordered]@{ case = 'correlation-mismatch-rejected'; passed = $true })

# A timed-out read-only request is removed only if it is still the unclaimed command.
$timeoutRoot = Join-Path $evidenceRoot 'timeout'
New-Item -ItemType Directory -Path (Join-Path $timeoutRoot 'responses') -Force | Out-Null
$timeoutProcess = Start-AgentHost -ProtocolRoot $timeoutRoot -TimeoutSeconds 1
$timeoutCommand = Wait-HostCommand -Process $timeoutProcess -CommandPath (Join-Path $timeoutRoot 'command.json')
$timeout = Finish-Host -Process $timeoutProcess -TimeoutSeconds 5
if ($timeout.ExitCode -ne 2 -or -not $timeout.Stderr.Contains('native-state-timeout')) {
    throw 'Host did not report a bounded Native state timeout.'
}
$remainingCommand = Test-Path -LiteralPath (Join-Path $timeoutRoot 'command.json')
if ($remainingCommand) { throw 'Host left its own unclaimed command in the shared mailbox after timeout.' }
$results.Add([ordered]@{ case = 'bounded-timeout-and-owned-command-cleanup'; passed = $true; commandId = $timeoutCommand.id })

$summary = [ordered]@{
    Passed = $true
    HostAssembly = [IO.Path]::GetFileName($hostDll)
    Cases = @($results)
    WorldMutationCommands = 0
    EvidenceDirectory = $evidenceRoot
}
$summary | ConvertTo-Json -Depth 6
