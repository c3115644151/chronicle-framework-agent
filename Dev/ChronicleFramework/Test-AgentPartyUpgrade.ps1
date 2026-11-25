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
$resultPath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP 'PartyUpgradeResult.json' } else { Join-Path $PSScriptRoot 'TestResults\ManualPartyUpgrade\PartyUpgradeResult.json' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$commandPrefix = 'party-upgrade-' + (Get-Date -Format 'yyyyMMddHHmmssfff')

if (-not (Test-Path -LiteralPath $savePath)) { throw "Party upgrade fixture not found: $LoadSaveName" }
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
    $seed = Invoke-AgentCli 'harnessSeedPartyUpgradeFixture' @('-CommandId', "$commandPrefix-seed")
    $beforeOptions = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-before-options")
    $options = Invoke-AgentCli 'partyUpgradeOptions' @('-CommandId', "$commandPrefix-options")
    $afterOptions = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-after-options")
    $rosterBefore = Invoke-AgentCli 'partyRoster' @('-CommandId', "$commandPrefix-roster-before")

    $seededTroopOption = @($options.data.options | Where-Object { [string]$_.troopId -eq [string]$seed.data.characterId } | Select-Object -First 1)
    if ($seededTroopOption.Count -ne 1) { throw "Native PartyVM did not expose seeded troop $($seed.data.characterId)" }
    $targetOption = @($seededTroopOption[0].upgradeTargets | Where-Object { [int]$_.targetIndex -eq [int]$seed.data.upgradeTargetIndex } | Select-Object -First 1)
    if ($targetOption.Count -ne 1 -or -not $targetOption[0].isAvailable -or $targetOption[0].isInsufficient -or [int]$targetOption[0].availableCount -lt 1)
        { throw 'The native PartyVM did not expose the Harness-seeded upgrade target as available.' }

    $upgrade = Invoke-AgentCli 'upgradeTroop' @('-TroopId', [string]$seed.data.characterId, '-UpgradeTargetIndex', [string]$seed.data.upgradeTargetIndex, '-CommandId', "$commandPrefix-upgrade")
    $rosterAfter = Invoke-AgentCli 'partyRoster' @('-CommandId', "$commandPrefix-roster-after")
    $afterUpgrade = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-after-upgrade")

    $sourceAfter = Find-RosterRow @($rosterAfter.data.members) ([string]$seed.data.characterId)
    $targetAfter = Find-RosterRow @($rosterAfter.data.members) ([string]$seed.data.targetId)
    $sourceAfterCount = if ($sourceAfter.Count -eq 1) { [int]$sourceAfter[0].count } else { 0 }
    $targetAfterCount = if ($targetAfter.Count -eq 1) { [int]$targetAfter[0].count } else { 0 }
    $upgradeCommitted = (
        $upgrade.status -eq 'completed' -and [bool]$upgrade.data.committed -and
        [int]$upgrade.data.upgradedCount -eq 1 -and
        [int]$upgrade.data.sourceCountBefore - [int]$upgrade.data.sourceCountAfter -eq 1 -and
        [int]$upgrade.data.sourceXpBefore - [int]$upgrade.data.sourceXpAfter -eq [int]$upgrade.data.xpCost -and
        [int]$upgrade.data.goldBefore - [int]$upgrade.data.goldAfter -eq [int]$upgrade.data.goldCost -and
        $sourceAfterCount -eq 0 -and $targetAfterCount -eq 1
    )
    $queryReadOnly = (
        $beforeOptions.state.party.members -eq $afterOptions.state.party.members -and
        $beforeOptions.state.party.prisoners -eq $afterOptions.state.party.prisoners -and
        $beforeOptions.state.economy.gold -eq $afterOptions.state.economy.gold -and
        $beforeOptions.campaignDay -eq $afterOptions.campaignDay -and
        $afterOptions.state.context.gameState -eq 'MapState' -and
        $options.data.timeControlModeAfter -eq $options.data.timeControlModeBefore
    )

    $invalid = Invoke-AgentCli 'upgradeTroop' @('-TroopId', 'chronicle_invalid_upgrade_troop', '-UpgradeTargetIndex', '0', '-CommandId', "$commandPrefix-invalid")
    $afterInvalid = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-after-invalid")
    $invalidNoMutation = (
        $invalid.status -eq 'rejected' -and
        $afterInvalid.state.party.members -eq $afterUpgrade.state.party.members -and
        $afterInvalid.state.economy.gold -eq $afterUpgrade.state.economy.gold -and
        $afterInvalid.campaignDay -eq $afterUpgrade.campaignDay
    )
    $insufficientXp = Invoke-AgentCli 'upgradeTroop' @('-TroopId', [string]$seed.data.targetId, '-UpgradeTargetIndex', '0', '-CommandId', "$commandPrefix-insufficient-xp")
    $afterInsufficientXp = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-after-insufficient-xp")
    $insufficientXpNoMutation = (
        $insufficientXp.status -eq 'rejected' -and
        $afterInsufficientXp.state.party.members -eq $afterInvalid.state.party.members -and
        $afterInsufficientXp.state.economy.gold -eq $afterInvalid.state.economy.gold -and
        $afterInsufficientXp.campaignDay -eq $afterInvalid.campaignDay
    )

    $resume = Invoke-AgentCli 'resume' @('-CommandId', "$commandPrefix-resume")
    $activeBeforeOptions = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-active-before-options")
    $activeOptions = Invoke-AgentCli 'partyUpgradeOptions' @('-CommandId', "$commandPrefix-active-options")
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
        HarnessSeedMatchesNativePartyVMOptions = ([string]$seed.data.characterId -eq [string]$seededTroopOption[0].troopId -and [int]$targetOption[0].experienceCostPerUnit -eq [int]$seed.data.experienceCost -and [int]$targetOption[0].goldCostPerUnit -eq [int]$seed.data.goldCost)
        OptionQueryIsReadOnlyAndReturnsToMap = [bool]$queryReadOnly
        NativePartyScreenTransactionUpgradesOneUnit = [bool]$upgradeCommitted
        InvalidUpgradeRejectedWithoutMutation = [bool]$invalidNoMutation
        InsufficientExperienceRejectedWithoutMutation = [bool]$insufficientXpNoMutation
        ActiveTimeModeSurvivesPartyScreenOpenClose = [bool]$activeTimePreserved
        FormalFixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = [bool]$stop.processStopped
    }
    $failedAssertions = @($assertions.Keys | Where-Object { -not [bool]$assertions[$_] })
    $result = [ordered]@{
        Seed = $seed.data
        SelectedNativeOption = $targetOption[0]
        UpgradeReceipt = $upgrade.data
        InvalidReceiptStatus = [string]$invalid.status
        InsufficientXpReceiptStatus = [string]$insufficientXp.status
        PausedModeDuringOptions = [ordered]@{ before = [string]$options.data.timeControlModeBefore; during = [string]$options.data.timeControlModeDuring; after = [string]$options.data.timeControlModeAfter }
        ActiveModeDuringOptions = [ordered]@{ before = [string]$activeOptions.data.timeControlModeBefore; during = [string]$activeOptions.data.timeControlModeDuring; after = [string]$activeOptions.data.timeControlModeAfter; modeAfterObservation = [string]$activeAfterOptions.state.context.timeControlMode }
        Assertions = $assertions
        FailedAssertions = $failedAssertions
        Passed = ($failedAssertions.Count -eq 0)
    }
    $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    $result | ConvertTo-Json -Depth 10
    if (-not $result.Passed) { throw 'Native PartyScreen upgrade did not match options/fees/results, restored the map or preserved time mode and fixture.' }
}
finally {
    if (Test-Path $sessionPath) {
        try { Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-cleanup") 20 | Out-Null } catch { }
    }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
