#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$resultPath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP 'PartyPrisonerRecruitmentResult.json' } else { Join-Path $PSScriptRoot 'TestResults\ManualPartyPrisonerRecruitment\PartyPrisonerRecruitmentResult.json' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$commandPrefix = 'party-prisoner-recruitment-' + (Get-Date -Format 'yyyyMMddHHmmssfff')

if (-not (Test-Path -LiteralPath $savePath)) { throw "Prisoner recruitment fixture not found: $LoadSaveName" }
if (Get-Process -Name Bannerlord -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $output = & $HarnessPowerShell -NoProfile -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

function Find-RosterRow($Roster, [string]$CharacterId) {
    return @($Roster | Where-Object { [string]$_.characterId -eq $CharacterId } | Select-Object -First 1)
}

try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $pause = Invoke-AgentCli 'pause' @('-CommandId', "$commandPrefix-pause")
    $beforeSeed = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-before-seed")
    $seed = Invoke-AgentCli 'harnessSeedPrisonerRecruitmentFixture' @('-CommandId', "$commandPrefix-seed")
    $beforeOptions = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-before-options")
    $options = Invoke-AgentCli 'prisonerRecruitmentOptions' @('-CommandId', "$commandPrefix-options")
    $afterOptions = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-after-options")

    $selectedOption = @($options.data.options | Where-Object { [string]$_.troopId -eq [string]$seed.data.characterId } | Select-Object -First 1)
    if ($selectedOption.Count -ne 1) { throw "Native PartyVM did not expose seeded prisoner $($seed.data.characterId)" }
    $queryReadOnly = (
        $beforeOptions.state.party.members -eq $afterOptions.state.party.members -and
        $beforeOptions.state.party.prisoners -eq $afterOptions.state.party.prisoners -and
        $beforeOptions.state.economy.gold -eq $afterOptions.state.economy.gold -and
        $beforeOptions.campaignDay -eq $afterOptions.campaignDay -and
        $afterOptions.state.context.gameState -eq 'MapState' -and
        $options.data.timeControlModeBefore -eq $options.data.timeControlModeAfter
    )
    if (-not $selectedOption[0].isAvailable -or [int]$selectedOption[0].availableCount -ne [int]$seed.data.availableCountExpected)
        { throw 'The native PartyVM did not expose the fixture prisoner with the expected one-unit recruitable count.' }
    if (-not $options.data.nativeDoneConfirmationRequiredForOne -or [string]::IsNullOrWhiteSpace([string]$options.data.nativeDoneConfirmationText))
        { throw 'The native PartyVM did not expose the Done confirmation required by recruiting one prisoner above the MainParty size limit.' }

    $rosterBefore = Invoke-AgentCli 'partyRoster' @('-CommandId', "$commandPrefix-roster-before")
    $unconfirmedRecruit = Invoke-AgentCli 'recruitPrisoner' @('-TroopId', [string]$seed.data.characterId, '-CommandId', "$commandPrefix-unconfirmed")
    $afterUnconfirmed = Invoke-AgentCli 'partyRoster' @('-CommandId', "$commandPrefix-after-unconfirmed")
    $unconfirmedRejectedWithoutMutation = (
        $unconfirmedRecruit.status -eq 'rejected' -and
        $afterUnconfirmed.data.memberTotals.totalCount -eq $rosterBefore.data.memberTotals.totalCount -and
        $afterUnconfirmed.data.prisonerTotals.totalCount -eq $rosterBefore.data.prisonerTotals.totalCount
    )
    $recruit = Invoke-AgentCli 'recruitPrisoner' @('-TroopId', [string]$seed.data.characterId, '-ConfirmPartySizeWarning', '-CommandId', "$commandPrefix-recruit")
    $rosterAfter = Invoke-AgentCli 'partyRoster' @('-CommandId', "$commandPrefix-roster-after")
    $afterRecruit = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-after-recruit")
    $prisonerAfter = Find-RosterRow @($rosterAfter.data.prisoners) ([string]$seed.data.characterId)
    $memberAfter = Find-RosterRow @($rosterAfter.data.members) ([string]$seed.data.characterId)
    $prisonerAfterCount = if ($prisonerAfter.Count -eq 1) { [int]$prisonerAfter[0].count } else { 0 }
    $memberAfterCount = if ($memberAfter.Count -eq 1) { [int]$memberAfter[0].count } else { 0 }
    $recruitCommitted = (
        $recruit.status -eq 'completed' -and [bool]$recruit.data.committed -and
        [int]$recruit.data.recruitedCount -eq 1 -and
        [int]$recruit.data.prisonerCountBefore - [int]$recruit.data.prisonerCountAfter -eq 1 -and
        [int]$recruit.data.prisonerConformityXpBefore - [int]$recruit.data.prisonerConformityXpAfter -eq [int]$recruit.data.conformityXpCost -and
        [int]$recruit.data.memberTotalAfter - [int]$recruit.data.memberTotalBefore -eq 1 -and
        [int]$recruit.data.memberCountAfter - [int]$recruit.data.memberCountBefore -eq 1 -and
        $prisonerAfterCount -eq ([int]$seed.data.prisonerCount - 1) -and $memberAfterCount -eq 1
    )
    $costAndMoraleMatched = (
        [int]$recruit.data.goldAfter -eq [int]$recruit.data.goldBefore -and
        [Math]::Abs(([double]$recruit.data.recentEventsMoraleAfter - [double]$recruit.data.recentEventsMoraleBefore) - [double]$recruit.data.expectedRecentEventsMoraleDelta) -lt 0.001 -and
        [int]$recruit.data.nativeMoralePreviewDelta -eq [int]$recruit.data.expectedRecentEventsMoraleDelta
    )
    $capacityBoundaryMatchesNative = (
        [int]$recruit.data.memberTotalBefore -eq [int]$recruit.data.partySizeLimit -and
        [bool]$recruit.data.partySizeWarningBefore -and
        [bool]$recruit.data.nativeLimitConfirmationAccepted -and
        [int]$recruit.data.memberTotalAfter -eq ([int]$recruit.data.partySizeLimit + 1)
    )

    $afterRecruitOptions = Invoke-AgentCli 'prisonerRecruitmentOptions' @('-CommandId', "$commandPrefix-after-recruit-options")
    $remainingOption = @($afterRecruitOptions.data.options | Where-Object { [string]$_.troopId -eq [string]$seed.data.characterId } | Select-Object -First 1)
    $remainingRecruitCount = if ($remainingOption.Count -eq 1) { [int]$remainingOption[0].availableCount } else { 0 }
    $belowThresholdRejected = $false
    $belowThresholdStatus = 'not-tested'
    if ($remainingOption.Count -eq 1 -and $remainingRecruitCount -eq 0) {
        $unavailable = Invoke-AgentCli 'recruitPrisoner' @('-TroopId', [string]$seed.data.characterId, '-CommandId', "$commandPrefix-insufficient-conformity")
        $afterUnavailable = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-after-insufficient-conformity")
        $belowThresholdStatus = [string]$unavailable.status
        $belowThresholdRejected = (
            $unavailable.status -eq 'rejected' -and
            $afterUnavailable.state.party.members -eq $afterRecruit.state.party.members -and
            $afterUnavailable.state.party.prisoners -eq $afterRecruit.state.party.prisoners -and
            $afterUnavailable.state.economy.gold -eq $afterRecruit.state.economy.gold -and
            $afterUnavailable.campaignDay -eq $afterRecruit.campaignDay
        )
    }

    $resume = Invoke-AgentCli 'resume' @('-CommandId', "$commandPrefix-resume")
    $activeBeforeOptions = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-active-before-options")
    $activeOptions = Invoke-AgentCli 'prisonerRecruitmentOptions' @('-CommandId', "$commandPrefix-active-options")
    $activeAfterOptions = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-active-after-options")
    $activeTimePreserved = (
        $activeBeforeOptions.state.context.timeControlMode -ne 'Stop' -and
        $activeOptions.data.timeControlModeBefore -eq $activeBeforeOptions.state.context.timeControlMode -and
        $activeOptions.data.timeControlModeAfter -eq $activeBeforeOptions.state.context.timeControlMode -and
        $activeAfterOptions.state.context.timeControlMode -eq $activeBeforeOptions.state.context.timeControlMode
    )
    $pauseEnd = Invoke-AgentCli 'pause' @('-CommandId', "$commandPrefix-pause-end")
    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-stop") 30
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash

    $assertions = [ordered]@{
        CampaignMapAndExplicitPause = ($beforeSeed.state.context.gameState -eq 'MapState' -and $pause.status -eq 'completed')
        HarnessSeedMatchesNativeEligibility = ([string]$seed.data.characterId -eq [string]$selectedOption[0].troopId -and [bool]$selectedOption[0].isAvailable -and [int]$selectedOption[0].conformityXpPerRecruit -eq [int]$seed.data.conformityCostPerRecruit)
        OptionsReadOnlyAndReturnToMap = [bool]$queryReadOnly
        NativePartyVMRecruitsExactlyOneAtCapacity = [bool]$recruitCommitted
        RecruitableCountAndMoraleMatchNativeModel = [bool]$costAndMoraleMatched
        FullPartyBoundaryMatchesNativeVMAndDone = [bool]$capacityBoundaryMatchesNative
        NativeOverLimitWarningRequiresExplicitConfirmation = [bool]$unconfirmedRejectedWithoutMutation
        InsufficientConformityRejectedWithoutMutation = [bool]$belowThresholdRejected
        ActiveTimeModeSurvivesPartyScreenOpenClose = [bool]$activeTimePreserved
        FormalFixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = [bool]$stop.processStopped
    }
    $failedAssertions = @($assertions.Keys | Where-Object { -not [bool]$assertions[$_] })
    $result = [ordered]@{
        Seed = $seed.data
        SelectedNativeOption = $selectedOption[0]
        NativeDoneConfirmation = [ordered]@{ required = [bool]$options.data.nativeDoneConfirmationRequiredForOne; title = [string]$options.data.nativeDoneConfirmationTitle; text = [string]$options.data.nativeDoneConfirmationText }
        RecruitmentReceipt = $recruit.data
        UnconfirmedReceiptStatus = [string]$unconfirmedRecruit.status
        RemainingRecruitableCount = $remainingRecruitCount
        InsufficientConformityStatus = $belowThresholdStatus
        PausedModeDuringOptions = [ordered]@{ before = [string]$options.data.timeControlModeBefore; during = [string]$options.data.timeControlModeDuring; after = [string]$options.data.timeControlModeAfter }
        ActiveModeDuringOptions = [ordered]@{ before = [string]$activeOptions.data.timeControlModeBefore; during = [string]$activeOptions.data.timeControlModeDuring; after = [string]$activeOptions.data.timeControlModeAfter; modeAfterObservation = [string]$activeAfterOptions.state.context.timeControlMode }
        Assertions = $assertions
        FailedAssertions = $failedAssertions
        Passed = ($failedAssertions.Count -eq 0)
    }
    $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    $result | ConvertTo-Json -Depth 10
    if (-not $result.Passed) { throw 'Native PartyVM prisoner recruitment did not match eligibility/conformity/morale, preserve capacity behavior/time mode, or clean the disposable fixture.' }
}
finally {
    if (Test-Path $sessionPath) {
        try { Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-cleanup") 20 | Out-Null } catch { }
    }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
