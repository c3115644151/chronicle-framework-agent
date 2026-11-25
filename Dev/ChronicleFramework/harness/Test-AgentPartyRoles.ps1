#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$resultPath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP 'PartyRolesResult.json' } else { Join-Path (Split-Path -Parent $PSScriptRoot) 'TestResults\ManualPartyRoles\PartyRolesResult.json' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$commandPrefix = 'party-roles-' + (Get-Date -Format 'yyyyMMddHHmmssfff')

if (-not (Test-Path -LiteralPath $savePath)) { throw "Party-role fixture not found: $LoadSaveName" }
if (Get-Process -Name Bannerlord -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $output = & $HarnessPowerShell -NoProfile -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

function Invoke-PartyRoleRead([string]$Suffix) {
    return Invoke-AgentCli 'partyRoles' @('-CommandId', "$commandPrefix-$Suffix")
}

function Invoke-RoleDiagnostics([string]$Suffix) {
    return Invoke-AgentCli 'harnessPartyRoleDiagnostics' @('-CommandId', "$commandPrefix-$Suffix")
}

function Assert-RoleVMMatchesNative($RoleRead, $NativeRead, [string]$Label) {
    if ($RoleRead.status -ne 'completed' -or $NativeRead.status -ne 'completed') { throw "$Label role read/diagnostic did not complete." }
    $nativeById = @{}
    foreach ($row in @($NativeRead.data.roles)) { $nativeById[[string]$row.roleId] = $row }
    foreach ($row in @($RoleRead.data.roles)) {
        if (-not $nativeById.ContainsKey([string]$row.roleId)) { throw "$Label native diagnostic omitted role $($row.roleId)." }
        $native = $nativeById[[string]$row.roleId]
        if ([string]$row.assignedHeroId -ne [string]$native.assignedHeroId -or [string]$row.effectiveHeroId -ne [string]$native.effectiveHeroId)
            { throw "$Label VM role-holder read differs from MobileParty native state for $($row.roleId)." }
    }
}

try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $pause = Invoke-AgentCli 'pause' @('-CommandId', "$commandPrefix-pause")
    $beforeSeed = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-before-seed")
    if ($beforeSeed.state.context.gameState -ne 'MapState') { throw 'Party role test must begin on Campaign Map.' }

    $seed = Invoke-AgentCli 'harnessSeedPartyRoleFixture' @('-CommandId', "$commandPrefix-seed")
    $candidateId = [string]$seed.data.heroId
    if ($seed.status -ne 'completed' -or -not $seed.data.isPlayerCompanion -or -not $seed.data.inMainParty)
        { throw 'Harness companion was not established as a local PlayerClan MainParty Hero.' }

    $initial = Invoke-PartyRoleRead 'initial-roles'
    $initialNative = Invoke-RoleDiagnostics 'initial-native'
    Assert-RoleVMMatchesNative $initial $initialNative 'Initial'
    $expectedRoles = @('Quartermaster', 'Scout', 'Surgeon', 'Engineer')
    if (@($initial.data.roles).Count -ne $expectedRoles.Count -or [int]$initial.data.maximumPartyRoleAssignmentCount -ne 2)
        { throw 'Default PartyRole model did not expose its four roles and two-role limit.' }
    foreach ($roleId in $expectedRoles) {
        $row = @($initial.data.roles | Where-Object { $_.roleId -eq $roleId } | Select-Object -First 1)
        if ($row.Count -ne 1 -or @($row[0].candidates | Where-Object { $_.heroId -eq $candidateId }).Count -ne 1)
            { throw "Native role VM did not list seeded Clan Hero $candidateId for $roleId." }
    }

    $goldBefore = [int]$initialNative.data.gold
    $initialMode = [string]$initialNative.data.timeControlMode
    $quartermaster = Invoke-AgentCli 'setPartyRole' @('-RoleId', 'Quartermaster', '-HeroId', $candidateId, '-CommandId', "$commandPrefix-set-quartermaster")
    $afterQuartermaster = Invoke-PartyRoleRead 'after-quartermaster'
    $nativeAfterQuartermaster = Invoke-RoleDiagnostics 'native-after-quartermaster'
    Assert-RoleVMMatchesNative $afterQuartermaster $nativeAfterQuartermaster 'Quartermaster assignment'
    if ($quartermaster.status -ne 'completed' -or [string]$nativeAfterQuartermaster.data.roles.Where({ $_.roleId -eq 'Quartermaster' }).assignedHeroId -ne $candidateId)
        { throw 'Native role VM assignment did not establish the requested Quartermaster.' }

    $scout = Invoke-AgentCli 'setPartyRole' @('-RoleId', 'Scout', '-HeroId', $candidateId, '-CommandId', "$commandPrefix-set-scout")
    $afterScout = Invoke-RoleDiagnostics 'native-after-scout'
    if ($scout.status -ne 'completed' -or @($afterScout.data.roles | Where-Object { $_.assignedHeroId -eq $candidateId }).Count -ne 2)
        { throw 'Native role VM did not assign the same Hero a second role.' }

    $surgeon = Invoke-AgentCli 'setPartyRole' @('-RoleId', 'Surgeon', '-HeroId', $candidateId, '-CommandId', "$commandPrefix-set-third-role")
    $afterThirdRole = Invoke-RoleDiagnostics 'native-after-third-role'
    $thirdHolders = @($afterThirdRole.data.roles | Where-Object { $_.assignedHeroId -eq $candidateId } | ForEach-Object { [string]$_.roleId })
    if ($surgeon.status -ne 'completed' -or $thirdHolders.Count -ne 2 -or $thirdHolders -notcontains 'Scout' -or $thirdHolders -notcontains 'Surgeon' -or $thirdHolders -contains 'Quartermaster')
        { throw "Native third-role assignment did not expose the documented two-role replacement: $($thirdHolders -join ',')." }

    $removeSurgeon = Invoke-AgentCli 'unassignPartyRole' @('-RoleId', 'Surgeon', '-CommandId', "$commandPrefix-remove-surgeon")
    $afterRemoval = Invoke-RoleDiagnostics 'native-after-removal'
    if ($removeSurgeon.status -ne 'completed' -or @($afterRemoval.data.roles | Where-Object { $_.roleId -eq 'Surgeon' -and $_.assignedHeroId }).Count -ne 0 -or @($afterRemoval.data.roles | Where-Object { $_.roleId -eq 'Scout' -and $_.assignedHeroId -eq $candidateId }).Count -ne 1)
        { throw 'Native Remove assignee did not clear only Surgeon and preserve Scout.' }

    $invalidRole = Invoke-AgentCli 'setPartyRole' @('-RoleId', 'FirstMate', '-HeroId', $candidateId, '-CommandId', "$commandPrefix-invalid-role")
    $afterInvalidRole = Invoke-RoleDiagnostics 'native-after-invalid-role'
    $invalidCandidate = Invoke-AgentCli 'setPartyRole' @('-RoleId', 'Engineer', '-HeroId', 'chronicle_invalid_party_role_hero', '-CommandId', "$commandPrefix-invalid-candidate")
    $afterInvalidCandidate = Invoke-RoleDiagnostics 'native-after-invalid-candidate'
    $removeUnassigned = Invoke-AgentCli 'unassignPartyRole' @('-RoleId', 'Surgeon', '-CommandId', "$commandPrefix-remove-unassigned")
    $afterRemoveUnassigned = Invoke-RoleDiagnostics 'native-after-remove-unassigned'
    $invalidBranchesRejected = ($invalidRole.status -eq 'rejected' -and $invalidCandidate.status -eq 'rejected' -and $removeUnassigned.status -eq 'rejected')
    $invalidBranchesNoMutation = (
        ($afterInvalidRole.data | ConvertTo-Json -Compress -Depth 8) -eq ($afterRemoval.data | ConvertTo-Json -Compress -Depth 8) -and
        ($afterInvalidCandidate.data | ConvertTo-Json -Compress -Depth 8) -eq ($afterRemoval.data | ConvertTo-Json -Compress -Depth 8) -and
        ($afterRemoveUnassigned.data | ConvertTo-Json -Compress -Depth 8) -eq ($afterRemoval.data | ConvertTo-Json -Compress -Depth 8)
    )

    $resume = Invoke-AgentCli 'resume' @('-CommandId', "$commandPrefix-resume")
    $activeBefore = Invoke-RoleDiagnostics 'active-mode-before-query'
    $activeRead = Invoke-PartyRoleRead 'active-mode-query'
    $activeAfter = Invoke-RoleDiagnostics 'active-mode-after-query'
    $activeScoutChange = Invoke-AgentCli 'unassignPartyRole' @('-RoleId', 'Scout', '-CommandId', "$commandPrefix-active-mode-change")
    $activeAfterChange = Invoke-RoleDiagnostics 'active-mode-after-change'
    $activeModePreserved = (
        $resume.status -eq 'completed' -and
        $activeRead.data.timeControlModeBefore -eq $activeBefore.data.timeControlMode -and
        $activeRead.data.timeControlModeDuring -eq $activeBefore.data.timeControlMode -and
        $activeRead.data.timeControlModeAfter -eq $activeBefore.data.timeControlMode -and
        $activeAfter.data.timeControlMode -eq $activeBefore.data.timeControlMode -and
        $activeScoutChange.data.timeControlModeBefore -eq $activeBefore.data.timeControlMode -and
        $activeScoutChange.data.timeControlModeAfter -eq $activeBefore.data.timeControlMode -and
        $activeAfterChange.data.timeControlMode -eq $activeBefore.data.timeControlMode
    )
    $activeDayNondecreasing = ([double]$activeAfterChange.data.campaignDay -ge [double]$activeBefore.data.campaignDay)
    $pauseEnd = Invoke-AgentCli 'pause' @('-CommandId', "$commandPrefix-pause-end")
    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-stop") 30
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash

    $assertions = [ordered]@{
        HarnessSeedWasIsolatedPlayerClanHero = ($seed.status -eq 'completed' -and $seed.data.isPlayerCompanion -and $seed.data.inMainParty)
        NativeRoleVMMatchesMobilePartyBaseline = ($initial.status -eq 'completed' -and $initialNative.status -eq 'completed')
        DefaultNativeRoleAndEligibilityLists = (@($initial.data.roles).Count -eq 4 -and [int]$initial.data.maximumPartyRoleAssignmentCount -eq 2 -and @($initial.data.roles | ForEach-Object { @($_.candidates | Where-Object { $_.heroId -eq $candidateId }).Count } | Where-Object { $_ -eq 1 }).Count -eq 4)
        AssignAndRemoveUseNativeRoleVMHandlers = ($quartermaster.status -eq 'completed' -and $scout.status -eq 'completed' -and $surgeon.status -eq 'completed' -and $removeSurgeon.status -eq 'completed' -and $removeSurgeon.data.before.roles.Count -eq 4)
        ThreeRoleNativeReplacementIsObserved = ($thirdHolders.Count -eq 2 -and $thirdHolders -contains 'Scout' -and $thirdHolders -contains 'Surgeon' -and $thirdHolders -notcontains 'Quartermaster')
        InvalidRoleHeroAndRemovalRejectedWithoutMutation = ($invalidBranchesRejected -and $invalidBranchesNoMutation)
        ActiveCampaignTimeModeUnaffected = $activeModePreserved
        CampaignDayOnlyNaturallyNondecreasing = $activeDayNondecreasing
        NoGoldOrRosterCostForPausedRoleTransactions = ([int]$afterRemoval.data.gold -eq $goldBefore -and [int]$afterRemoval.data.memberCount -eq [int]$initialNative.data.memberCount)
        FormalFixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = [bool]$stop.processStopped
    }
    $failedAssertions = @($assertions.Keys | Where-Object { -not [bool]$assertions[$_] })
    $result = [ordered]@{
        Seed = $seed.data
        InitialRoles = $initial.data
        NativeInitialDiagnostics = $initialNative.data
        QuartermasterReceipt = $quartermaster.data
        ScoutReceipt = $scout.data
        ThirdRoleReceipt = $surgeon.data
        HoldersAfterThirdRole = $afterThirdRole.data.roles
        RemoveAssigneeReceipt = $removeSurgeon.data
        InvalidRoleStatus = [string]$invalidRole.status
        InvalidCandidateStatus = [string]$invalidCandidate.status
        RemoveUnassignedStatus = [string]$removeUnassigned.status
        ActiveMode = [ordered]@{ before = $activeBefore.data; query = $activeRead.data; afterQuery = $activeAfter.data; change = $activeScoutChange.data; afterChange = $activeAfterChange.data }
        NaturalActiveModeDeltas = [ordered]@{ campaignDayDelta = ([double]$activeAfterChange.data.campaignDay - [double]$activeBefore.data.campaignDay); goldDelta = ([int]$activeAfterChange.data.gold - [int]$activeBefore.data.gold); memberCountDelta = ([int]$activeAfterChange.data.memberCount - [int]$activeBefore.data.memberCount) }
        Assertions = $assertions
        FailedAssertions = $failedAssertions
        FixtureHashBefore = $fixtureHashBefore
        FixtureHashAfter = $fixtureHashAfter
        ProcessStopped = [bool]$stop.processStopped
        Passed = ($failedAssertions.Count -eq 0)
    }
    $result | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    $result | ConvertTo-Json -Depth 14
    if (-not $result.Passed) { throw 'PartyRole flow did not match the native role VM, replacement rule, rejection, time, or fixture invariants.' }
}
finally {
    if (Test-Path -LiteralPath $sessionPath) {
        try { Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-cleanup") 20 | Out-Null } catch { }
    }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
