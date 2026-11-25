#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180,
    [int]$CandidateLimit = 20
)

$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$tempPath = $env:CHRONICLE_HARNESS_TEMP
$runDirectory = if ($tempPath) { Split-Path -Parent $tempPath } else { Join-Path $PSScriptRoot 'TestResults\ManualMapPartyQuestMarkers' }
$frameRoot = if ($tempPath) { $tempPath } else { $runDirectory }
$resultPath = if ($tempPath) { Join-Path $tempPath 'MapPartyQuestMarkersResult.json' } else { Join-Path $runDirectory 'MapPartyQuestMarkersResult.json' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$prefix = 'map-party-quest-markers-' + (Get-Date -Format 'yyyyMMddHHmmssfff')
$currentStep = 'preflight'
$fixture = $null
$seededPartyId = $null
$state = $null

if (-not (Test-Path -LiteralPath $savePath)) { throw "Map Party marker fixture not found: $LoadSaveName" }
if (Get-Process -Name Bannerlord -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
. (Join-Path $PSScriptRoot 'Test-AgentSupport.ps1')

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $output = & $HarnessPowerShell -NoProfile -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

function Capture-EngineFrame([string]$Path, [string]$Suffix) {
    $receipt = Invoke-AgentCli 'captureFrame' @('-OutputPath', $Path, '-CommandId', "$prefix-$Suffix") 30
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path -LiteralPath $Path) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
    $exists = Test-Path -LiteralPath $Path
    $length = if ($exists) { (Get-Item -LiteralPath $Path).Length } else { 0 }
    if ($receipt.status -ne 'completed' -or -not $exists -or $length -lt 4096)
        { throw "Native map Party marker frame '$Path' was not captured (receipt='$($receipt.status)', exists=$exists, bytes=$length)." }
}

try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $currentStep = 'load-disposable-campaign'
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $initial = Invoke-AgentCli 'state' @('-CommandId', "$prefix-initial")
    if ($initial.state.context.gameState -ne 'MapState' -or $initial.state.context.encounterActive -or $initial.state.context.captivity)
        { throw 'Fixture must start as a free Campaign Map party with no active Encounter.' }

    $currentStep = 'observe-native-visible-map-party-candidates'
    $beforeTargets = Invoke-AgentCli 'mapPartyTargets' @('-CommandId', "$prefix-party-targets-before") 30
    if ($beforeTargets.status -ne 'completed') { throw 'Native mapPartyTargets query failed before Issue marker fixture creation.' }
    $candidates = @($beforeTargets.data.mapPartyTargets |
        Where-Object { $_.type -eq 'lord' -and -not [bool]$_.isArmyLeader -and $null -ne $_.questMarkers -and @($_.questMarkers).Count -eq 0 -and [double]$_.distance -lt 12 } |
        Select-Object -First $CandidateLimit)
    if ($candidates.Count -eq 0) { throw 'No nearby visible, spotted Lord nameplate candidate without an existing marker was available.' }
    $negativeTarget = $candidates | Select-Object -Last 1
    $beforeFrame = Join-Path $frameRoot 'map-party-quest-marker-before.bmp'
    $afterFrame = Join-Path $frameRoot 'map-party-quest-marker-after.bmp'
    Capture-EngineFrame $beforeFrame 'party-marker-before'

    $currentStep = 'create-native-eligible-issue-for-one-observed-party-leader'
    $seedErrors = [System.Collections.Generic.List[string]]::new()
    foreach ($candidate in $candidates) {
        try {
            $fixture = Invoke-AgentCli 'harnessSeedMapPartyIssueMarker' @('-PartyId', [string]$candidate.id, '-CommandId', "$prefix-seed-issue-$($candidate.id)") 30
            if ($fixture.status -eq 'completed' -and [bool]$fixture.data.nativeIssueFixtureCreated) {
                $seededPartyId = [string]$candidate.id
                break
            }
            $seedErrors.Add("$($candidate.id): seed receipt was not completed")
        }
        catch {
            $message = $_.Exception.Message
            if ($message -match 'no currently eligible Issue candidate|already owns an Issue|no Native Nameplate candidate') {
                $seedErrors.Add("$($candidate.id): $message")
                continue
            }
            throw
        }
    }
    if (-not $seededPartyId) { throw "No current visible Lord candidate exposed an eligible Native Issue fixture. Attempts=$($seedErrors -join ' | ')" }
    if ([string]$negativeTarget.id -eq $seededPartyId) {
        $negativeTarget = $candidates | Where-Object { [string]$_.id -ne $seededPartyId } | Select-Object -First 1
        if (-not $negativeTarget) { throw 'A second Native nameplate candidate without marker was needed to verify the negative branch.' }
    }
    if (-not @($fixture.data.nativeHeroQuestMarkerFlags | Where-Object { $_ -eq 'AvailableIssue' }).Count)
        { throw "Native IssueManager created an Issue but GetQuestStateOfHero did not expose AvailableIssue: $($fixture.data | ConvertTo-Json -Compress)" }

    $currentStep = 'reobserve-marker-through-product-mapPartyTargets'
    $afterTargets = Invoke-AgentCli 'mapPartyTargets' @('-CommandId', "$prefix-party-targets-after") 30
    $afterTarget = @($afterTargets.data.mapPartyTargets | Where-Object { $_.id -eq $seededPartyId } | Select-Object -First 1)
    $negativeAfter = @($afterTargets.data.mapPartyTargets | Where-Object { $_.id -eq $negativeTarget.id } | Select-Object -First 1)
    $hasAvailableMarker = ($afterTarget.Count -eq 1 -and @($afterTarget[0].questMarkers | Where-Object { $_ -eq 'AvailableIssue' }).Count -gt 0 -and [bool]$afterTarget[0].hasAvailableIssueMarker)
    $negativeRemainsEmpty = ($negativeAfter.Count -eq 1 -and $null -ne $negativeAfter[0].questMarkers -and @($negativeAfter[0].questMarkers).Count -eq 0 -and -not [bool]$negativeAfter[0].hasAvailableIssueMarker)
    if ($afterTargets.status -ne 'completed' -or -not $hasAvailableMarker -or -not $negativeRemainsEmpty)
        { throw "Native Party marker observation did not match controlled Issue/no-Issue states. Positive=$($afterTarget | ConvertTo-Json -Compress); Negative=$($negativeAfter | ConvertTo-Json -Compress)" }
    Capture-EngineFrame $afterFrame 'party-marker-after'

    $repeatTargets = Invoke-AgentCli 'mapPartyTargets' @('-CommandId', "$prefix-party-targets-repeat") 30
    $repeatTarget = @($repeatTargets.data.mapPartyTargets | Where-Object { $_.id -eq $seededPartyId } | Select-Object -First 1)
    $observationStable = ($repeatTargets.status -eq 'completed' -and $repeatTarget.Count -eq 1 -and (($repeatTarget[0].questMarkers | ConvertTo-Json -Compress) -eq ($afterTarget[0].questMarkers | ConvertTo-Json -Compress)))
    $noQuestTextLeaked = ($null -eq $afterTarget[0].issueTitle -and $null -eq $afterTarget[0].issueDescription -and $null -eq $afterTarget[0].issueDeadline)
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-stop") 30
    $processesStopped = -not [bool](Get-Process -Name Bannerlord -ErrorAction SilentlyContinue)
    $result = [ordered]@{
        ProviderKind = 'Native observed mapPartyTargets and Native IssueManager eligible candidate; no product gameplay action'
        ProcessId = $start.session.processId
        InitialPartyTargetCount = @($beforeTargets.data.mapPartyTargets).Count
        IssueFixture = $fixture.data
        SeededPartyId = $seededPartyId
        NegativeTargetId = [string]$negativeTarget.id
        PositivePartyBefore = @($beforeTargets.data.mapPartyTargets | Where-Object { $_.id -eq $seededPartyId } | Select-Object -First 1)
        PositivePartyAfter = $afterTarget[0]
        NegativePartyAfter = $negativeAfter[0]
        AvailableIssueMarkerExposed = $hasAvailableMarker
        NoMarkerPartyRemainsEmpty = $negativeRemainsEmpty
        ObservationRepeatStable = $observationStable
        QuestTextNotLeaked = $noQuestTextLeaked
        EngineFrames = @($beforeFrame, $afterFrame)
        SourceFixtureHashBefore = $fixtureHashBefore
        SourceFixtureHashAfter = $fixtureHashAfter
        SourceFixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = [bool]$stop.processStopped
        AllGameProcessesStopped = $processesStopped
        Passed = ($hasAvailableMarker -and $negativeRemainsEmpty -and $observationStable -and $noQuestTextLeaked -and $fixtureHashBefore -eq $fixtureHashAfter -and [bool]$stop.processStopped -and $processesStopped)
    }
    $json = $result | ConvertTo-Json -Depth 16
    if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) { Set-Content -LiteralPath $resultPath -Value $json -Encoding UTF8 }
    $json
    if (-not $result.Passed) { exit 1 }
}
catch {
    $failureFrame = Capture-HarnessFailureFrame -CliPath $cli -CommandPrefix $prefix -FailedStep $currentStep -FailureReason $_.Exception.ToString()
    if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) {
        [ordered]@{ FailedStep = $currentStep; Exception = $_.Exception.ToString(); FailureFrame = $failureFrame; TargetCount = if ($beforeTargets) { @($beforeTargets.data.mapPartyTargets).Count } else { 0 }; CandidateAttempts = @($seedErrors); Fixture = if ($fixture) { $fixture.data } else { $null }; TargetId = $seededPartyId; TimestampUtc = [DateTime]::UtcNow.ToString('O') } |
            ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tempPath 'MapPartyQuestMarkersFailure.json') -Encoding UTF8
    }
    throw
}
finally {
    if (Test-Path $sessionPath) {
        try {
            $session = Get-Content $sessionPath -Raw | ConvertFrom-Json
            if ($session.status -ne 'stopped') { $null = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-final-stop") 30 }
        }
        catch { }
    }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
