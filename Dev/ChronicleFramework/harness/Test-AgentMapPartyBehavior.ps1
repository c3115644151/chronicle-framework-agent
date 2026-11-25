#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [switch]$ValidateArmyTooltip,
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$resultFileName = if ($ValidateArmyTooltip) { 'MapArmyBehaviorResult.json' } else { 'MapPartyBehaviorResult.json' }
$resultPath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP $resultFileName } else { Join-Path (Split-Path -Parent $PSScriptRoot) "TestResults\ManualMapPartyBehavior\$resultFileName" }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$commandPrefix = 'map-party-behavior-' + (Get-Date -Format 'yyyyMMddHHmmssfff')

if (-not (Test-Path -LiteralPath $savePath)) { throw "Map party behavior fixture not found: $LoadSaveName" }
if (Get-Process -Name Bannerlord -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $output = & $HarnessPowerShell -NoProfile -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

function Test-BehaviorMatchesNativeTooltip($Observation, $Native) {
    if (-not $Observation.data.available -or [string]::IsNullOrWhiteSpace([string]$Observation.data.behaviorText)) { return $false }
    return @($Native.data.nativeTooltipProperties | Where-Object { [string]$_.value -ceq [string]$Observation.data.behaviorText }).Count -gt 0
}

try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $pause = Invoke-AgentCli 'pause' @('-CommandId', "$commandPrefix-pause")
    $before = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-before")
    $targets = Invoke-AgentCli 'mapPartyTargets' @('-CommandId', "$commandPrefix-targets")
    $nativeCandidates = @(
        foreach ($candidate in @($targets.data.mapPartyTargets | Where-Object isInspected)) {
            $native = Invoke-AgentCli 'harnessMapPartyCompositionDiagnostics' @('-PartyId', [string]$candidate.id, '-CommandId', "$commandPrefix-native-$($candidate.id)")
            if ($native.data.isInfoHidden) { continue }
            $candidateBehavior = Invoke-AgentCli 'mapPartyBehavior' @('-PartyId', [string]$candidate.id, '-CommandId', "$commandPrefix-behavior-$($candidate.id)")
            if ($candidateBehavior.data.available -and (Test-BehaviorMatchesNativeTooltip $candidateBehavior $native)) {
                [pscustomobject]@{ Target = $candidate; Native = $native; Behavior = $candidateBehavior }
            }
        }
    )
    $selectedCandidate = @($nativeCandidates | Where-Object { -not $_.Native.data.isArmyLeader } | Select-Object -First 1)
    if ($selectedCandidate.Count -ne 1) { throw 'The fixture has no currently visible, inspected, non-Army Party for behavior-tooltip verification.' }
    $partyId = [string]$selectedCandidate[0].Target.id
    $observed = $selectedCandidate[0].Behavior
    $repeat = Invoke-AgentCli 'mapPartyBehavior' @('-PartyId', $partyId, '-CommandId', "$commandPrefix-repeat")
    $ordinaryMatches = Test-BehaviorMatchesNativeTooltip $observed $selectedCandidate[0].Native
    $ordinaryStable = [string](ConvertTo-Json -InputObject $observed.data -Depth 8 -Compress) -ceq [string](ConvertTo-Json -InputObject $repeat.data -Depth 8 -Compress)

    $armyAssertion = $true
    $armyEvidence = $null
    if ($ValidateArmyTooltip) {
        $armyFixture = Invoke-AgentCli 'harnessCreateMapArmyFixture' @('-PartyId', $partyId, '-CommandId', "$commandPrefix-create-army")
        $armyNative = Invoke-AgentCli 'harnessMapPartyCompositionDiagnostics' @('-PartyId', [string]$armyFixture.data.leaderPartyId, '-CommandId', "$commandPrefix-native-army")
        $armyObserved = Invoke-AgentCli 'mapPartyBehavior' @('-PartyId', [string]$armyFixture.data.leaderPartyId, '-CommandId', "$commandPrefix-behavior-army")
        $armyAssertion = ([bool]$armyFixture.data.armyRegisteredInKingdom -and [int]$armyFixture.data.attachedPartyCount -eq 0 -and [bool]$armyObserved.data.isArmyLeader -and (Test-BehaviorMatchesNativeTooltip $armyObserved $armyNative))
        $armyEvidence = [ordered]@{ LeaderPartyId = [string]$armyFixture.data.leaderPartyId; BehaviorText = [string]$armyObserved.data.behaviorText; NativeTooltipPropertyCount = @($armyNative.data.nativeTooltipProperties).Count; IsInfoHidden = [bool]$armyNative.data.isInfoHidden }
    }

    $invalid = Invoke-AgentCli 'mapPartyBehavior' @('-PartyId', 'chronicle_non_visible_party_test', '-CommandId', "$commandPrefix-invalid")
    $after = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-after")
    $snapshotUnchanged = (
        $before.state.identity.heroId -eq $after.state.identity.heroId -and
        $before.state.location.x -eq $after.state.location.x -and
        $before.state.location.y -eq $after.state.location.y -and
        $before.state.party.id -eq $after.state.party.id -and
        $before.state.party.members -eq $after.state.party.members -and
        $before.state.party.prisoners -eq $after.state.party.prisoners -and
        $before.state.economy.gold -eq $after.state.economy.gold -and
        $before.state.economy.renown -eq $after.state.economy.renown -and
        $before.campaignDay -eq $after.campaignDay -and
        $after.state.context.timeControlMode -eq 'Stop'
    )
    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-stop") 30
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $assertions = [ordered]@{
        CampaignMapAndExplicitPause = ($before.state.context.gameState -eq 'MapState' -and $pause.status -eq 'completed' -and $after.state.context.timeControlMode -eq 'Stop')
        TargetWasVisibleAndInspected = ([bool]$selectedCandidate[0].Target.isInspected -and [bool]$observed.data.available)
        OrdinaryBehaviorTextMatchesNativeTooltip = [bool]$ordinaryMatches
        OrdinaryBehaviorTextStable = [bool]$ordinaryStable
        ArmyBehaviorTextMatchesNativeTooltipWhenRequested = [bool]$armyAssertion
        InvalidPartyRejected = ($invalid.status -eq 'rejected')
        SnapshotUnchanged = [bool]$snapshotUnchanged
        FixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = [bool]$stop.processStopped
    }
    $failedAssertions = @($assertions.Keys | Where-Object { -not [bool]$assertions[$_] })
    $result = [ordered]@{
        PartyId = $partyId
        IsArmyLeader = [bool]$observed.data.isArmyLeader
        BehaviorText = [string]$observed.data.behaviorText
        NativeTooltipPropertyCount = @($selectedCandidate[0].Native.data.nativeTooltipProperties).Count
        ArmyBehaviorEvidence = $armyEvidence
        InspectedTargetCount = $nativeCandidates.Count
        Assertions = $assertions
        FailedAssertions = $failedAssertions
        Passed = ($failedAssertions.Count -eq 0)
    }
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    $result | ConvertTo-Json -Depth 8
    if (-not $result.Passed) { throw 'Map party behavior observation diverged from the native expanded tooltip or changed Campaign/save state.' }
}
finally {
    if (Test-Path $sessionPath) {
        try { Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-cleanup") 20 | Out-Null } catch { }
    }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
