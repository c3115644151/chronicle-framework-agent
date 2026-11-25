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
$resultFileName = if ($ValidateArmyTooltip) { 'MapArmyCompositionResult.json' } else { 'MapPartyCompositionResult.json' }
$resultPath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP $resultFileName } else { Join-Path (Split-Path -Parent $PSScriptRoot) "TestResults\ManualMapPartyComposition\$resultFileName" }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$commandPrefix = 'map-party-composition-' + (Get-Date -Format 'yyyyMMddHHmmssfff')

if (-not (Test-Path -LiteralPath $savePath)) { throw "Map party composition fixture not found: $savePath" }
if (Get-Process -Name Bannerlord -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $output = & $HarnessPowerShell -NoProfile -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

function Test-RosterEquality($Observed, $Native) {
    $ids = @($Observed | ForEach-Object { [string]$_.characterId } | Sort-Object)
    $nativeIds = @($Native | ForEach-Object { [string]$_.characterId } | Sort-Object)
    if (@(Compare-Object -ReferenceObject $ids -DifferenceObject $nativeIds).Count -ne 0) { return $false }
    foreach ($row in $Observed) {
        $nativeRow = @($Native | Where-Object characterId -eq $row.characterId | Select-Object -First 1)
        if ($nativeRow.Count -ne 1) { return $false }
        $reference = $nativeRow[0]
        if ([string]$row.name -ne [string]$reference.name -or
            [int]$row.totalCount -ne [int]$reference.totalCount -or
            [int]$row.healthyCount -ne [int]$reference.healthyCount -or
            [int]$row.woundedCount -ne [int]$reference.woundedCount -or
            [bool]$row.isHero -ne [bool]$reference.isHero) { return $false }
    }
    return $true
}

try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $pause = Invoke-AgentCli 'pause' @('-CommandId', "$commandPrefix-pause")
    $before = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-before")
    $targets = Invoke-AgentCli 'mapPartyTargets' @('-CommandId', "$commandPrefix-targets")
    $nativeCandidates = @(
        foreach ($candidate in @($targets.data.mapPartyTargets | Where-Object isInspected)) {
            $candidateNative = Invoke-AgentCli 'harnessMapPartyCompositionDiagnostics' @('-PartyId', [string]$candidate.id, '-CommandId', "$commandPrefix-native-$($candidate.id)")
            if ($candidateNative.data.isInfoHidden) { continue }
            $memberWounded = @($candidateNative.data.memberRoster | Where-Object { [int]$_.woundedCount -gt 0 }).Count
            $prisonerRows = @($candidateNative.data.prisonRoster).Count
            if ($candidateNative.data.isArmyLeader) { continue }
            $score = @($candidateNative.data.memberRoster).Count + ($memberWounded * 10) + ($prisonerRows * 20)
            [pscustomobject]@{ Target = $candidate; Native = $candidateNative; Score = $score; WoundedRowCount = $memberWounded; PrisonerRowCount = $prisonerRows }
        }
    )
    $selectedCandidate = @($nativeCandidates | Sort-Object Score -Descending | Select-Object -First 1)
    if ($selectedCandidate.Count -ne 1) { throw 'The fixture has no currently visible and inspected independent map Party available to the native detailed tooltip.' }
    $target = $selectedCandidate[0].Target
    $native = $selectedCandidate[0].Native
    $partyId = [string]$target.id
    $observed = Invoke-AgentCli 'mapPartyComposition' @('-PartyId', $partyId, '-CommandId', "$commandPrefix-composition")
    $repeat = Invoke-AgentCli 'mapPartyComposition' @('-PartyId', $partyId, '-CommandId', "$commandPrefix-repeat")

    $membersMatch = Test-RosterEquality @($observed.data.members) @($native.data.memberRoster)
    $prisonersMatch = Test-RosterEquality @($observed.data.prisoners) @($native.data.prisonRoster)
    $nativeDefinitions = @($native.data.nativeTooltipProperties | ForEach-Object { [string]$_.definition })
    $memberNamesDisplayed = @($observed.data.members | Where-Object { $nativeDefinitions -ccontains [string]$_.name }).Count -eq @($observed.data.members).Count
    $prisonerNamesDisplayed = @($observed.data.prisoners | Where-Object { $nativeDefinitions -ccontains [string]$_.name }).Count -eq @($observed.data.prisoners).Count
    $stableAcrossReads = [string](ConvertTo-Json -InputObject $observed.data -Depth 10 -Compress) -ceq [string](ConvertTo-Json -InputObject $repeat.data -Depth 10 -Compress)

    $invalidParty = Invoke-AgentCli 'mapPartyComposition' @('-PartyId', 'chronicle_non_visible_party_test', '-CommandId', "$commandPrefix-invalid")
    $invalidPartyRejected = ($invalidParty.status -eq 'rejected')
    $armyAssertion = $true
    $armyEvidence = $null
    if ($ValidateArmyTooltip) {
        $armyPair = $null
        foreach ($leaderCandidate in $nativeCandidates) {
            if ($leaderCandidate.Native.data.isArmyLeader -or [string]::IsNullOrWhiteSpace([string]$leaderCandidate.Native.data.mapFactionId)) { continue }
            $attachedCandidate = @($nativeCandidates | Where-Object {
                -not $_.Native.data.isArmyLeader -and
                $_.Target.id -ne $leaderCandidate.Target.id -and
                $_.Native.data.mapFactionId -eq $leaderCandidate.Native.data.mapFactionId
            } | Select-Object -First 1)
            if ($attachedCandidate.Count -eq 1) { $armyPair = [pscustomobject]@{ Leader = $leaderCandidate; Attached = $attachedCandidate[0] }; break }
        }
        if ($null -eq $armyPair) { throw 'The fixture has no two visible inspected independent Parties of one Kingdom for native Kingdom.CreateArmy verification.' }
        $armyFixture = Invoke-AgentCli 'harnessCreateMapArmyFixture' @('-PartyId', [string]$armyPair.Leader.Target.id, '-AttachedPartyId', [string]$armyPair.Attached.Target.id, '-CommandId', "$commandPrefix-create-army")
        $armyNative = Invoke-AgentCli 'harnessMapPartyCompositionDiagnostics' @('-PartyId', [string]$armyFixture.data.leaderPartyId, '-CommandId', "$commandPrefix-native-army")
        $armyObserved = Invoke-AgentCli 'mapPartyComposition' @('-PartyId', [string]$armyFixture.data.leaderPartyId, '-CommandId', "$commandPrefix-composition-army")
        $armyMembersMatch = Test-RosterEquality @($armyObserved.data.members) @($armyNative.data.memberRoster)
        $armyPrisonersMatch = Test-RosterEquality @($armyObserved.data.prisoners) @($armyNative.data.prisonRoster)
        $armyDefinitions = @($armyNative.data.nativeTooltipProperties | ForEach-Object { [string]$_.definition })
        $armyMemberNamesDisplayed = @($armyObserved.data.members | Where-Object { $armyDefinitions -ccontains [string]$_.name }).Count -eq @($armyObserved.data.members).Count
        $armyPrisonerNamesDisplayed = @($armyObserved.data.prisoners | Where-Object { $armyDefinitions -ccontains [string]$_.name }).Count -eq @($armyObserved.data.prisoners).Count
        $armyAssertion = ([bool]$armyFixture.data.armyRegisteredInKingdom -and [int]$armyFixture.data.attachedPartyCount -eq 1 -and [bool]$armyFixture.data.temporaryAttachedPartyEnlisted -and [bool]$armyNative.data.isArmyLeader -and [bool]$armyObserved.data.isArmyLeader -and [bool]$armyObserved.data.available -and [bool]$armyMembersMatch -and [bool]$armyPrisonersMatch -and [bool]$armyMemberNamesDisplayed -and [bool]$armyPrisonerNamesDisplayed)
        $armyEvidence = [ordered]@{ LeaderPartyId = [string]$armyFixture.data.leaderPartyId; AttachedPartyId = [string]$armyPair.Attached.Target.id; MemberRowCount = @($armyObserved.data.members).Count; PrisonerRowCount = @($armyObserved.data.prisoners).Count; NativeTooltipPropertyCount = @($armyNative.data.nativeTooltipProperties).Count; IsInfoHidden = [bool]$armyNative.data.isInfoHidden }
    }
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
        TargetWasVisibleAndInspected = ([bool]$target[0].isInspected -and [bool]$native.data.isInspected -and [bool]$observed.data.available)
        MemberRowsMatchNativeRoster = [bool]$membersMatch
        PrisonerRowsMatchNativeRoster = [bool]$prisonersMatch
        NativeExtendedTooltipDisplaysMemberNames = [bool]$memberNamesDisplayed
        NativeExtendedTooltipDisplaysPrisonerNames = [bool]$prisonerNamesDisplayed
        StableAcrossRepeatedReads = [bool]$stableAcrossReads
        NativeArmyTooltipMatchesWhenRequested = [bool]$armyAssertion
        NonTargetPartyRejected = [bool]$invalidPartyRejected
        SnapshotUnchanged = [bool]$snapshotUnchanged
        FixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = [bool]$stop.processStopped
    }
    $failedAssertions = @($assertions.Keys | Where-Object { -not [bool]$assertions[$_] })
    $result = [ordered]@{
        PartyId = $partyId
        IsArmyLeader = [bool]$observed.data.isArmyLeader
        MemberRowCount = @($observed.data.members).Count
        MemberWoundedRowCount = [int]$selectedCandidate[0].WoundedRowCount
        PrisonerRowCount = @($observed.data.prisoners).Count
        SelectedCandidatePrisonerRowCount = [int]$selectedCandidate[0].PrisonerRowCount
        NativeTooltipPropertyCount = @($native.data.nativeTooltipProperties).Count
        RuntimeIsInfoHidden = [bool]$native.data.isInfoHidden
        NativeArmyLeaderCandidateCount = @($nativeCandidates | Where-Object { $_.Native.data.isArmyLeader }).Count
        NativeCandidateWoundedRowCount = (@($nativeCandidates | ForEach-Object { $_.WoundedRowCount }) | Measure-Object -Sum).Sum
        NativeCandidatePrisonerRowCount = (@($nativeCandidates | ForEach-Object { $_.PrisonerRowCount }) | Measure-Object -Sum).Sum
        ArmyTooltipEvidence = $armyEvidence
        InspectedCandidateCoverage = @($nativeCandidates | ForEach-Object { [ordered]@{ partyId = [string]$_.Target.id; isArmyLeader = [bool]$_.Native.data.isArmyLeader; memberRows = @($_.Native.data.memberRoster).Count; woundedRows = [int]$_.WoundedRowCount; prisonerRows = [int]$_.PrisonerRowCount } })
        Assertions = $assertions
        FailedAssertions = $failedAssertions
        Passed = ($failedAssertions.Count -eq 0)
    }
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    $result | ConvertTo-Json -Depth 8
    if (-not $result.Passed) { throw 'Map party composition diverged from the native expanded tooltip/roster or changed Campaign/save state.' }
}
finally {
    if (Test-Path $sessionPath) {
        try { Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-cleanup") 20 | Out-Null } catch { }
    }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
