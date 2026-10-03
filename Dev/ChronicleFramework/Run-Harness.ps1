[CmdletBinding()]
param(
    [ValidateSet('Docs', 'Preflight', 'Api', 'Build', 'Smoke', 'Campaign', 'FreshCampaign', 'FreshCampaignProgression', 'Protocol', 'AgentLoop', 'TimeControlLoop', 'BattleFixture', 'PostBattle', 'Observation', 'CaptivityObservation', 'CaptivityOutcome', 'PrisonCaptivityOutcome', 'EncounterSurrender', 'EncounterEscape', 'JoinEncounterDefenders', 'JoinEncounterEligibility', 'JoinEncounterAbandonArmy', 'MovingArmyJoin', 'JoinSiegeEvent', 'MapNotifications', 'QuickInformation', 'SceneNotification', 'MissionLeave', 'VillageToolsDelivery', 'MainHeroSkills', 'CharacterDevelopment', 'SpendSkillFocus', 'QuestJournal', 'PartyRoster', 'MapPartyTargets', 'MapPartyQuestMarkers', 'MapPartyQuestAcceptance', 'MapPartyComposition', 'MapArmyComposition', 'MapPartyBehavior', 'PartyUpgrade', 'PartyPrisonerRecruitment', 'PartyRoles', 'InventoryNavigation', 'EquipmentTransactions', 'TradeTransactions', 'BarterTransactions', 'BarterContexts', 'BarterFightRoute', 'BarterSafePassage', 'MissionInteraction', 'CompanionHiring', 'MapSettlementTargets', 'Movement', 'Hold', 'MoveToPoint', 'Recruitment', 'Rest', 'Pursuit', 'EngageVisibility', 'Conversation', 'QuestAcceptance', 'EscortVisibility', 'TavernMission', 'TownCenterMission', 'SettlementOverlayConversation', 'SettlementOverlayQuickTalk', 'SettlementOverlayQuestAcceptance', 'SettlementOverlayQuestGate', 'VisualCapture', 'All')]
    [string]$Phase = 'All',
    [int]$SmokeTimeoutSeconds = 45,
    [int]$SmokeStabilitySeconds = 8,
    [string]$TargetSettlementId = 'town_V1',
    [string]$ApproachSettlementId = 'town_V1',
    [string]$QuickTalkTargetSettlementId = 'village_V1_1',
    [int]$VisibilityProbeSeconds = 120,
    [int]$VillageToolsMaxDecisions = 320
)

$ErrorActionPreference = 'Stop'
$startupEvidenceScript = Join-Path $PSScriptRoot 'HarnessStartupEvidence.ps1'
. $startupEvidenceScript
$researchReadinessScript = Join-Path $PSScriptRoot 'HarnessResearchReadiness.ps1'
. $researchReadinessScript
$HarnessContractVersion = '7.5'
$harnessRoot = $PSScriptRoot
$localSettingsPath = Join-Path $harnessRoot 'harness.local.json'
if (-not (Test-Path -LiteralPath $localSettingsPath)) { throw "Local harness settings not found: $localSettingsPath. Run Initialize-ChronicleWorkspace.ps1 first." }
$localSettings = Get-Content -LiteralPath $localSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
$repositoryRoot = [IO.Path]::GetFullPath([string]$localSettings.repositoryRoot)
$gameRoot = [IO.Path]::GetFullPath([string]$localSettings.gameRoot)
if (-not (Test-Path -LiteralPath $repositoryRoot -PathType Container)) { throw "Repository root not found: $repositoryRoot" }
if (-not (Test-Path -LiteralPath (Join-Path $gameRoot 'bin\Win64_Shipping_Client\Bannerlord.exe'))) { throw "Configured Bannerlord game root is invalid: $gameRoot" }
$env:CHRONICLE_GAME_ROOT = $gameRoot
$env:CHRONICLE_REPOSITORY_ROOT = $repositoryRoot
$evidenceRoot = Join-Path $harnessRoot 'TestResults'
$runId = Get-Date -Format 'yyyyMMdd-HHmmss'
$runDirectory = Join-Path $evidenceRoot $runId
$manifestPath = Join-Path $gameRoot 'Modules\ChronicleFramework\SubModule.xml'
$sourceManifestPath = Join-Path $repositoryRoot 'Modules\ChronicleFramework\SubModule.xml'
$gameExe = Join-Path $gameRoot 'bin\Win64_Shipping_Client\Bannerlord.exe'
$projectPath = Join-Path $harnessRoot 'ChronicleFramework.csproj'
$apiScript = Join-Path (Split-Path -Parent $harnessRoot) 'ApiProbe\Inspect-CampaignApi.ps1'
$smokeScript = Join-Path $harnessRoot 'Test-Module.ps1'
$campaignScript = Join-Path $harnessRoot 'Test-Campaign.ps1'
$freshCampaignScript = Join-Path $harnessRoot 'Test-AgentFreshCampaign.ps1'
$saveModuleMetadataTestScript = Join-Path $harnessRoot 'Test-AgentSaveMetadata.ps1'
$protocolScript = Join-Path $harnessRoot 'Test-AgentProtocol.ps1'
$observationScript = Join-Path $harnessRoot 'Test-AgentObservation.ps1'
$captivityObservationScript = Join-Path $harnessRoot 'Test-AgentCaptivityObservation.ps1'
$captivityOutcomeScript = Join-Path $harnessRoot 'Test-AgentCaptivityOutcome.ps1'
$encounterSurrenderScript = Join-Path $harnessRoot 'Test-AgentEncounterSurrender.ps1'
$encounterEscapeScript = Join-Path $harnessRoot 'Test-AgentEncounterEscape.ps1'
$joinEncounterScript = Join-Path $harnessRoot 'Test-AgentJoinEncounterDefenders.ps1'
$joinEncounterEligibilityScript = Join-Path $harnessRoot 'Test-AgentJoinEncounterEligibility.ps1'
$joinEncounterAbandonArmyScript = Join-Path $harnessRoot 'Test-AgentJoinEncounterAbandonArmy.ps1'
$movingArmyJoinScript = Join-Path $harnessRoot 'Test-AgentMovingArmyJoin.ps1'
$joinSiegeEventScript = Join-Path $harnessRoot 'Test-AgentJoinSiegeEvent.ps1'
$mapNotificationsScript = Join-Path $harnessRoot 'Test-AgentMapNotifications.ps1'
$quickInformationScript = Join-Path $harnessRoot 'Test-AgentQuickInformation.ps1'
$sceneNotificationScript = Join-Path $harnessRoot 'Test-AgentSceneNotification.ps1'
$missionLeaveScript = Join-Path $harnessRoot 'Test-AgentMissionLeave.ps1'
$villageToolsDeliveryScript = Join-Path $harnessRoot 'Test-AgentVillageToolsDelivery.ps1'
$movementScript = Join-Path $harnessRoot 'Test-AgentMovement.ps1'
$holdScript = Join-Path $harnessRoot 'Test-AgentHold.ps1'
$moveToPointScript = Join-Path $harnessRoot 'Test-AgentMoveToPoint.ps1'
$recruitmentScript = Join-Path $harnessRoot 'Test-AgentRecruitment.ps1'
$restScript = Join-Path $harnessRoot 'Test-AgentRest.ps1'
$pursuitScript = Join-Path $harnessRoot 'Test-AgentPursuit.ps1'
$agentLoopScript = Join-Path $harnessRoot 'Test-AgentLoop.ps1'
$battleFixtureScript = Join-Path $harnessRoot 'Test-AgentBattleFixture.ps1'
$visualCaptureScript = Join-Path $harnessRoot 'Test-AgentVisualCapture.ps1'
$tavernMissionScript = Join-Path $harnessRoot 'Test-AgentTavernMission.ps1'
$townCenterMissionScript = Join-Path $harnessRoot 'Test-AgentTownCenterMission.ps1'
$settlementOverlayConversationScript = Join-Path $harnessRoot 'Test-AgentSettlementOverlayConversation.ps1'
$mapSettlementTargetsScript = Join-Path $harnessRoot 'Test-AgentMapSettlementTargets.ps1'
$mainHeroSkillsScript = Join-Path $harnessRoot 'Test-AgentMainHeroSkills.ps1'
$characterDevelopmentScript = Join-Path $harnessRoot 'Test-AgentCharacterDevelopment.ps1'
$spendSkillFocusScript = Join-Path $harnessRoot 'Test-AgentSpendSkillFocus.ps1'
$partyRosterScript = Join-Path $harnessRoot 'Test-AgentPartyRoster.ps1'
$mapPartyTargetsScript = Join-Path $harnessRoot 'Test-AgentMapPartyTargets.ps1'
$mapPartyQuestMarkersScript = Join-Path $harnessRoot 'Test-AgentMapPartyQuestMarkers.ps1'
$mapPartyQuestAcceptanceScript = Join-Path $harnessRoot 'Test-AgentMapPartyQuestAcceptance.ps1'
$mapPartyCompositionScript = Join-Path $harnessRoot 'Test-AgentMapPartyComposition.ps1'
$mapPartyBehaviorScript = Join-Path $harnessRoot 'Test-AgentMapPartyBehavior.ps1'
$partyUpgradeScript = Join-Path $harnessRoot 'Test-AgentPartyUpgrade.ps1'
$partyPrisonerRecruitmentScript = Join-Path $harnessRoot 'Test-AgentPartyPrisonerRecruitment.ps1'
$missionInteractionScript = Join-Path $harnessRoot 'Test-AgentMissionInteraction.ps1'
$companionHiringScript = Join-Path $harnessRoot 'Test-AgentCompanionHiring.ps1'
$partyRolesScript = Join-Path $harnessRoot 'Test-AgentPartyRoles.ps1'
$inventoryNavigationScript = Join-Path $harnessRoot 'Test-AgentInventoryNavigation.ps1'
$equipmentTransactionsScript = Join-Path $harnessRoot 'Test-AgentEquipmentTransactions.ps1'
$tradeTransactionsScript = Join-Path $harnessRoot 'Test-AgentTradeTransactions.ps1'
$barterTransactionsScript = Join-Path $harnessRoot 'Test-AgentBarterTransactions.ps1'
$barterContextsScript = Join-Path $harnessRoot 'Test-AgentSafePassageBarterContext.ps1'
$docsScript = Join-Path $harnessRoot 'Check-Docs.ps1'
$contextPackScript = Join-Path $harnessRoot 'Get-ContextPack.ps1'

$sourceControl = [ordered]@{
    Available = $false
    Commit = $null
    Branch = $null
    Dirty = $null
    DirtyFileCount = $null
}
try {
    $gitCommit = [string](& git -C $repositoryRoot rev-parse --verify HEAD 2>$null)
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($gitCommit)) {
        $gitBranch = [string](& git -C $repositoryRoot branch --show-current 2>$null)
        $gitStatus = @(& git -C $repositoryRoot status --porcelain=v1 --untracked-files=all 2>$null)
        if ($LASTEXITCODE -eq 0) {
            $sourceControl.Available = $true
            $sourceControl.Commit = $gitCommit.Trim()
            $sourceControl.Branch = $gitBranch.Trim()
            $sourceControl.Dirty = ($gitStatus.Count -gt 0)
            $sourceControl.DirtyFileCount = $gitStatus.Count
        }
    }
} catch { }

New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null
$harnessTempDirectory = Join-Path $runDirectory 'Temp'
New-Item -ItemType Directory -Path $harnessTempDirectory -Force | Out-Null
$env:CHRONICLE_HARNESS_TEMP = $harnessTempDirectory
$env:TEMP = $harnessTempDirectory
$env:TMP = $harnessTempDirectory

function Write-StageResult {
    param(
        [string]$Name,
        [int]$ExitCode,
        [string]$Output
    )

    $result = [ordered]@{
        Stage = $Name
        ExitCode = $ExitCode
        Passed = ($ExitCode -eq 0)
        TimestampUtc = (Get-Date).ToUniversalTime().ToString('O')
    }
    if ($sourceControl.Available) {
        $result['GitCommit'] = $sourceControl.Commit
        $result['GitBranch'] = $sourceControl.Branch
        $result['GitDirty'] = $sourceControl.Dirty
        $result['GitDirtyFileCount'] = $sourceControl.DirtyFileCount
    }
    if ($Name -eq 'Docs') {
        $sizeMatch = [regex]::Match($Output, '"MarkdownBytes"\s*:\s*(\d+)[\s\S]*?"DefaultReadMarkdownBytes"\s*:\s*(\d+)')
        if ($sizeMatch.Success) {
            $result['MarkdownBytes'] = [int]$sizeMatch.Groups[1].Value
            $result['DefaultReadMarkdownBytes'] = [int]$sizeMatch.Groups[2].Value
        }
        foreach ($metric in @('CatalogSystemRows', 'CatalogMappedSystemRows', 'CatalogActionRows', 'CatalogObservationRows', 'CatalogNARows')) {
            $metricMatch = [regex]::Match($Output, ('"' + [regex]::Escape($metric) + '"\s*:\s*(\d+)'))
            if ($metricMatch.Success) { $result[$metric] = [int]$metricMatch.Groups[1].Value }
        }
    }
    $Output | Set-Content -Path (Join-Path $runDirectory "$Name.log") -Encoding UTF8
    $result | ConvertTo-Json | Set-Content -Path (Join-Path $runDirectory "$Name.json") -Encoding UTF8
    return $result
}

function Invoke-Stage {
    param(
        [string]$Name,
        [scriptblock]$Action
    )

    try {
        $output = (& $Action 2>&1 | Out-String)
        $exitCode = if ($LASTEXITCODE -is [int]) { $LASTEXITCODE } else { 0 }
        return Write-StageResult -Name $Name -ExitCode $exitCode -Output $output
    }
    catch {
        $output = ($_ | Out-String)
        return Write-StageResult -Name $Name -ExitCode 1 -Output $output
    }
}

$stages = @()
$requestedStages = switch ($Phase) {
    'Docs' { @('Docs') }
    'Preflight' { @('Preflight') }
    'Api' { @('Api') }
    'Build' { @('Build') }
    'Smoke' { @('Smoke') }
    'Campaign' { @('Preflight', 'Build', 'Campaign') }
    'FreshCampaign' { @('Preflight', 'Build', 'FreshCampaign') }
    'FreshCampaignProgression' { @('Preflight', 'Build', 'FreshCampaignProgression') }
    'Protocol' { @('Preflight', 'Build', 'Protocol') }
    'AgentLoop' { @('Preflight', 'Build', 'AgentLoop') }
    'TimeControlLoop' { @('Preflight', 'Build', 'TimeControlLoop') }
    'BattleFixture' { @('Preflight', 'Build', 'BattleFixture') }
    'PostBattle' { @('Preflight', 'Build', 'PostBattle') }
    'Observation' { @('Preflight', 'Build', 'Observation') }
    'CaptivityObservation' { @('Preflight', 'Build', 'CaptivityObservation') }
    'CaptivityOutcome' { @('Preflight', 'Build', 'CaptivityOutcome') }
    'PrisonCaptivityOutcome' { @('Preflight', 'Build', 'PrisonCaptivityOutcome') }
    'EncounterSurrender' { @('Preflight', 'Build', 'EncounterSurrender') }
    'EncounterEscape' { @('Preflight', 'Build', 'EncounterEscape') }
    'JoinEncounterDefenders' { @('Preflight', 'Build', 'JoinEncounterDefenders') }
    'JoinEncounterEligibility' { @('Preflight', 'Build', 'JoinEncounterEligibility') }
    'JoinEncounterAbandonArmy' { @('Preflight', 'Build', 'JoinEncounterAbandonArmy') }
    'MovingArmyJoin' { @('Preflight', 'Build', 'MovingArmyJoin') }
    'JoinSiegeEvent' { @('Preflight', 'Build', 'JoinSiegeEvent') }
    'MapNotifications' { @('Preflight', 'Build', 'MapNotifications') }
    'QuickInformation' { @('Preflight', 'Build', 'QuickInformation') }
    'SceneNotification' { @('Preflight', 'Build', 'SceneNotification') }
    'MissionLeave' { @('Preflight', 'Build', 'MissionLeave') }
    'VillageToolsDelivery' { @('Preflight', 'Build', 'VillageToolsDelivery') }
    'MainHeroSkills' { @('Preflight', 'Build', 'MainHeroSkills') }
    'CharacterDevelopment' { @('Preflight', 'Build', 'CharacterDevelopment') }
    'SpendSkillFocus' { @('Preflight', 'Build', 'SpendSkillFocus') }
    'QuestJournal' { @('Preflight', 'Build', 'QuestJournal') }
    'PartyRoster' { @('Preflight', 'Build', 'PartyRoster') }
    'MapPartyTargets' { @('Preflight', 'Build', 'MapPartyTargets') }
    'MapPartyQuestMarkers' { @('Preflight', 'Build', 'MapPartyQuestMarkers') }
    'MapPartyQuestAcceptance' { @('Preflight', 'Build', 'MapPartyQuestAcceptance') }
    'MapPartyComposition' { @('Preflight', 'Build', 'MapPartyComposition') }
    'MapArmyComposition' { @('Preflight', 'Build', 'MapArmyComposition') }
    'MapPartyBehavior' { @('Preflight', 'Build', 'MapPartyBehavior') }
    'PartyUpgrade' { @('Preflight', 'Build', 'PartyUpgrade') }
    'PartyPrisonerRecruitment' { @('Preflight', 'Build', 'PartyPrisonerRecruitment') }
    'PartyRoles' { @('Preflight', 'Build', 'PartyRoles') }
    'InventoryNavigation' { @('Preflight', 'Build', 'InventoryNavigation') }
    'EquipmentTransactions' { @('Preflight', 'Build', 'EquipmentTransactions') }
    'TradeTransactions' { @('Preflight', 'Build', 'TradeTransactions') }
    'BarterTransactions' { @('Preflight', 'Build', 'BarterTransactions') }
    'BarterContexts' { @('Preflight', 'Build', 'BarterContexts') }
    'BarterFightRoute' { @('Preflight', 'Build', 'BarterFightRoute') }
    'BarterSafePassage' { @('Preflight', 'Build', 'BarterSafePassage') }
    'MissionInteraction' { @('Preflight', 'Build', 'MissionInteraction') }
    'CompanionHiring' { @('Preflight', 'Build', 'CompanionHiring') }
    'Movement' { @('Preflight', 'Build', 'Movement') }
    'Hold' { @('Preflight', 'Build', 'Hold') }
    'MoveToPoint' { @('Preflight', 'Build', 'MoveToPoint') }
    'Recruitment' { @('Preflight', 'Build', 'Recruitment') }
    'Rest' { @('Preflight', 'Build', 'Rest') }
    'Pursuit' { @('Preflight', 'Build', 'Pursuit') }
    'EngageVisibility' { @('Preflight', 'Build', 'EngageVisibility') }
    'Conversation' { @('Preflight', 'Build', 'Conversation') }
    'QuestAcceptance' { @('Preflight', 'Build', 'QuestAcceptance') }
    'EscortVisibility' { @('Preflight', 'Build', 'EscortVisibility') }
    'TavernMission' { @('Preflight', 'Build', 'TavernMission') }
    'TownCenterMission' { @('Preflight', 'Build', 'TownCenterMission') }
    'SettlementOverlayConversation' { @('Preflight', 'Build', 'SettlementOverlayConversation') }
    'SettlementOverlayQuickTalk' { @('Preflight', 'Build', 'SettlementOverlayQuickTalk') }
    'SettlementOverlayQuestAcceptance' { @('Preflight', 'Build', 'SettlementOverlayQuestAcceptance') }
    'SettlementOverlayQuestGate' { @('Preflight', 'Build', 'SettlementOverlayQuestGate') }
    'MapSettlementTargets' { @('Preflight', 'Build', 'MapSettlementTargets') }
    'VisualCapture' { @('Preflight', 'Build', 'VisualCapture') }
    'All' { @('Docs', 'Preflight', 'Api', 'Build', 'Smoke', 'Campaign', 'Protocol', 'AgentLoop', 'TimeControlLoop', 'Observation', 'MapNotifications', 'QuickInformation', 'SceneNotification', 'MissionLeave', 'MainHeroSkills', 'CharacterDevelopment', 'SpendSkillFocus', 'QuestJournal', 'PartyRoster', 'MapPartyTargets', 'MapPartyComposition', 'MapArmyComposition', 'MapPartyBehavior', 'PartyUpgrade', 'PartyPrisonerRecruitment', 'PartyRoles', 'InventoryNavigation', 'EquipmentTransactions', 'TradeTransactions', 'BarterTransactions', 'BarterContexts', 'MissionInteraction', 'CompanionHiring', 'MapSettlementTargets', 'Movement', 'Hold', 'MoveToPoint', 'Recruitment', 'Rest', 'Pursuit', 'Conversation', 'QuestAcceptance', 'BattleFixture', 'PostBattle', 'TavernMission', 'TownCenterMission', 'SettlementOverlayConversation', 'SettlementOverlayQuickTalk', 'SettlementOverlayQuestGate') }
}

foreach ($stage in $requestedStages) {
    $stageResult = switch ($stage) {
        'Docs' {
            Invoke-Stage -Name 'Docs' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $docsScript
                if ($LASTEXITCODE -ne 0) { throw "Documentation check failed with exit code $LASTEXITCODE." }
                & powershell -NoProfile -ExecutionPolicy Bypass -File $contextPackScript
                if ($LASTEXITCODE -ne 0) { throw "Context pack failed with exit code $LASTEXITCODE." }
            }
        }
        'Preflight' {
            Invoke-Stage -Name 'Preflight' -Action {
                if (-not (Test-Path $gameExe)) { throw "Game executable not found: $gameExe" }
                if (-not (Test-Path $projectPath)) { throw "Project not found: $projectPath" }
                if (-not (Test-Path $manifestPath)) { throw "Manifest not found: $manifestPath" }
                if (-not (Test-Path $sourceManifestPath)) { throw "Version-controlled manifest not found: $sourceManifestPath" }
                if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { throw 'dotnet was not found on PATH.' }
                if (-not (Get-Command ilspycmd -ErrorAction SilentlyContinue)) { throw 'ilspycmd was not found on PATH.' }
                $templateList = dotnet new list 2>&1 | Out-String
                if ($templateList -notmatch 'blmodfx') { throw 'Bannerlord.Templates blmodfx template was not found.' }
                & powershell -NoProfile -ExecutionPolicy Bypass -File $saveModuleMetadataTestScript
                if ($LASTEXITCODE -ne 0) { throw "Save module metadata test failed with exit code $LASTEXITCODE." }
                [xml]$manifest = Get-Content $sourceManifestPath
                if ([string]$manifest.Module.Id.value -ne 'ChronicleFramework') { throw 'Unexpected module id.' }
                $dependencies = @($manifest.Module.DependedModules.DependedModule | ForEach-Object { [string]$_.Id })
                foreach ($dependency in @('Native', 'SandBoxCore', 'SandBox')) {
                    if ($dependency -notin $dependencies) {
                        throw "Missing dependency: $dependency"
                    }
                }
                $moduleIds = @(
                    'Bannerlord.Harmony',
                    'Bannerlord.ButterLib',
                    'Bannerlord.UIExtenderEx',
                    'Bannerlord.MBOptionScreen',
                    'Native',
                    'SandBoxCore',
                    'CustomBattle',
                    'SandBox',
                    'StoryMode',
                    'BirthAndDeath',
                    'ChronicleFramework'
                )
                $moduleVersions = @($moduleIds | ForEach-Object {
                    $moduleId = $_
                    $moduleDirectory = Get-ChildItem (Join-Path $gameRoot 'Modules') -Directory |
                        Where-Object { Test-Path (Join-Path $_.FullName 'SubModule.xml') } |
                        Where-Object {
                            try { ([xml](Get-Content (Join-Path $_.FullName 'SubModule.xml'))).Module.Id.value -eq $moduleId } catch { $false }
                        } |
                        Select-Object -First 1
                    if (-not $moduleDirectory) { throw "Module manifest not found for id: $moduleId" }
                    [xml]$moduleManifest = Get-Content (Join-Path $moduleDirectory.FullName 'SubModule.xml')
                    [pscustomobject]@{
                        Id = $moduleId
                        Directory = $moduleDirectory.Name
                        Version = [string]$moduleManifest.Module.Version.value
                    }
                })
                $gameFileVersion = (Get-Item $gameExe).VersionInfo.FileVersion
                $packageInfoText = [string](Get-Content (Join-Path $gameRoot 'package_info.txt') -Raw)
                $compileChangeset = if ($packageInfoText -match 'Compile Changeset:\s*(\d+)') { $Matches[1] } else { $null }
                [pscustomobject]@{
                    GameExecutable = $gameExe
                    GameFileVersion = $gameFileVersion
                    CompileChangeset = $compileChangeset
                    Manifest = $manifestPath
                    SourceManifest = $sourceManifestPath
                    RuntimeManifestMatchesSource = ((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $sourceManifestPath -Algorithm SHA256).Hash)
                    ModuleVersion = [string]$manifest.Module.Version.value
                    ModuleSet = $moduleVersions
                    Toolchain = @('dotnet', 'ilspycmd', 'Bannerlord.Templates:blmodfx')
                    PackageInfoHint = $packageInfoText
                } | ConvertTo-Json
            }
        }
        'Api' {
            Invoke-Stage -Name 'Api' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $apiScript -Scope Lifecycle
                if ($LASTEXITCODE -ne 0) { throw "API lifecycle stage failed with exit code $LASTEXITCODE." }
                & powershell -NoProfile -ExecutionPolicy Bypass -File $apiScript -Scope Events
                if ($LASTEXITCODE -ne 0) { throw "API events stage failed with exit code $LASTEXITCODE." }
            }
        }
        'Build' {
            Invoke-Stage -Name 'Build' -Action {
                $runningBannerlordClients = @(Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue)
                if ($runningBannerlordClients.Count -gt 0) {
                    $runningClientSummary = ($runningBannerlordClients | ForEach-Object { "$($_.ProcessName)#$($_.Id)" }) -join ', '
                    throw "Refusing to build or deploy ChronicleFramework while a Bannerlord client is running ($runningClientSummary). Close the game normally and retry; Harness will not stop a live client or overwrite its loaded DLL."
                }
                $mainlinePath = Join-Path $harnessRoot 'Focus\MAINLINE.md'
                $mainlineText = Get-Content -LiteralPath $mainlinePath -Raw -Encoding UTF8
                $researchGateReady = $mainlineText -match '(?m)^Research Gate: \*\*READY\*\*\s*$'
                $implementationGateReady = $mainlineText -match '(?m)^Implementation Gate: \*\*READY\*\*\s*$'
                $moduleDll = Join-Path $gameRoot 'Modules\ChronicleFramework\bin\Win64_Shipping_Client\ChronicleFramework.dll'
                $sourceFiles = @(Get-ChildItem -LiteralPath $harnessRoot -File -Filter '*.cs')
                $changedFeatureSources = if (Test-Path -LiteralPath $moduleDll) {
                    @($sourceFiles | Where-Object { $_.LastWriteTimeUtc -gt (Get-Item -LiteralPath $moduleDll).LastWriteTimeUtc })
                } else { $sourceFiles }
                $subModuleSource = Join-Path $harnessRoot 'SubModule.cs'
                $diagnosticSourceHash = if (Test-Path -LiteralPath $subModuleSource) { Get-ChronicleCanonicalFileSha256 -LiteralPath $subModuleSource } else { '' }
                $readiness = Get-ChronicleResearchReadiness -ResearchReady $researchGateReady -ImplementationReady $implementationGateReady -ChangedFeatureSources @($changedFeatureSources | ForEach-Object Name) -AuditedHarnessDiagnosticSha256 $diagnosticSourceHash
                if (-not $readiness.Allowed) { throw $readiness.Reason }
                $sourceManifestHash = (Get-FileHash -LiteralPath $sourceManifestPath -Algorithm SHA256).Hash
                $runtimeManifestHash = if (Test-Path -LiteralPath $manifestPath) { (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash } else { '' }
                if ($sourceManifestHash -ne $runtimeManifestHash) { Copy-Item -LiteralPath $sourceManifestPath -Destination $manifestPath -Force }
                $buildOutput = & dotnet build $projectPath --configuration Release --no-restore "-p:ChronicleGameRoot=$gameRoot" 2>&1 | Out-String
                $buildExitCode = $LASTEXITCODE
                if ($buildExitCode -ne 0) { throw "Build failed with exit code $buildExitCode.`n$buildOutput" }
                $buildOutput
            }
        }
        'Smoke' {
            Invoke-Stage -Name 'Smoke' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $smokeScript -TimeoutSeconds $SmokeTimeoutSeconds -StabilitySeconds $SmokeStabilitySeconds
                if ($LASTEXITCODE -ne 0) { throw "Smoke test failed with exit code $LASTEXITCODE." }
            }
        }
        'Campaign' {
            Invoke-Stage -Name 'Campaign' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $campaignScript
                if ($LASTEXITCODE -ne 0) { throw "Campaign test failed with exit code $LASTEXITCODE." }
            }
        }
        'FreshCampaign' {
            Invoke-Stage -Name 'FreshCampaign' -Action {
                $testOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $freshCampaignScript 2>&1 | Out-String
                if ($LASTEXITCODE -ne 0) { throw "Fresh campaign character-creation test failed with exit code $LASTEXITCODE. Output: $testOutput" }
                $testOutput
            }
        }
        'FreshCampaignProgression' {
            Invoke-Stage -Name 'FreshCampaignProgression' -Action {
                $attempts = @()
                $finalResult = $null
                for ($attempt = 1; $attempt -le 2; $attempt++) {
                    $attemptTemp = Join-Path $harnessTempDirectory "FreshCampaignProgressionAttempt$attempt"
                    New-Item -ItemType Directory -Path $attemptTemp -Force | Out-Null
                    $previousTemp = $env:CHRONICLE_HARNESS_TEMP
                    $env:CHRONICLE_HARNESS_TEMP = $attemptTemp
                    try {
                        $testOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $freshCampaignScript -ValidateRecruitmentProgression 2>&1 | Out-String
                        $testExitCode = $LASTEXITCODE
                    }
                    finally { $env:CHRONICLE_HARNESS_TEMP = $previousTemp }
                    try { $testResult = $testOutput | ConvertFrom-Json }
                    catch { throw "Fresh campaign attempt $attempt returned invalid JSON (exit=$testExitCode): $testOutput" }
                    $rglTail = @()
                    if ($testResult.RglLog -and (Test-Path -LiteralPath $testResult.RglLog)) {
                        try {
                            $rglLogLines = @(Get-Content -LiteralPath $testResult.RglLog -Tail 8 -ErrorAction Stop)
                            $rglTail = @(ConvertTo-ChronicleLogTail -Lines $rglLogLines)
                        }
                        catch { $rglTail = @([pscustomobject]@{ text = "RGL tail unavailable: $($_.Exception.Message)" }) }
                    }
                    $startupAssessment = Get-ChronicleStartupAssessment -Attempt $attempt -GameStarted ([bool]$testResult.GameStarted) -NativeNewCampaignRequested ([bool]$testResult.NativeNewCampaignRequested) -CrashDetected ([bool]$testResult.CrashDetected) -CrashWindowTitle ([string]$testResult.CrashWindowTitle) -SaveDirectoryMetadataUnchanged ([bool]$testResult.SaveDirectoryMetadataUnchanged) -RglLogExists ([bool]($testResult.RglLog -and (Test-Path -LiteralPath $testResult.RglLog)))
                    $attemptSummary = [ordered]@{
                        attempt = $attempt
                        exitCode = $testExitCode
                        passed = [bool]$testResult.Passed
                        gameStarted = [bool]$testResult.GameStarted
                        characterCreationCompleted = [bool]$testResult.CharacterCreationCompleted
                        nativeNewCampaignRequested = [bool]$testResult.NativeNewCampaignRequested
                        gameProcessId = $testResult.GameProcessId
                        crashWindowTitle = [string]$testResult.CrashWindowTitle
                        crashDetected = [bool]$testResult.CrashDetected
                        crashWindowCapture = $testResult.CrashWindowCapture
                        crashWindowCaptureError = [string]$testResult.CrashWindowCaptureError
                        crashWindowCaptureVideoRetained = [bool]$testResult.CrashWindowCaptureVideoRetained
                        crashExceptionPath = [string]$testResult.CrashExceptionPath
                        crashExceptionCaptured = [bool]$testResult.CrashExceptionCaptured
                        crashFaultAddress = [string]$testResult.CrashFaultAddress
                        crashFaultModule = [string]$testResult.CrashFaultModule
                        crashModuleInventory = $testResult.CrashModuleInventory
                        crashModuleCaptureError = [string]$testResult.CrashModuleCaptureError
                        startupClassification = $startupAssessment.Classification
                        rglLogPath = [string]$testResult.RglLog
                        rglLogExists = [bool]($testResult.RglLog -and (Test-Path -LiteralPath $testResult.RglLog))
                        rglTail = $rglTail
                        progressionFailureDetail = [string]$testResult.RecruitmentProgressionError
                        freshClanRenown = $testResult.ClanRenown
                        recruitmentProgression = $testResult.RecruitmentProgression
                        progressionSaveCycleVerified = [bool]($testResult.RecruitmentProgression -and $testResult.RecruitmentProgression.DisposableSaveName -and $testResult.RecruitmentProgression.Passed)
                        saveDirectoryUnchanged = [bool]$testResult.SaveDirectoryMetadataUnchanged
                        evidenceDirectory = $attemptTemp
                    }
                    $attempts += $attemptSummary
                    $attemptSummary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $attemptTemp 'attempt-summary.json') -Encoding UTF8
                    $finalResult = $testResult
                    if ($testExitCode -eq 0 -and $testResult.Passed) { break }
                    # A per-process RGL log proves only that the launcher emitted a log; it is not crash evidence.
                    # Retry once only when the test itself observed an explicit crash signature or crash-report window.
                    if (-not $startupAssessment.ShouldRetry) { break }
                }
                $stageOutput = [ordered]@{ scenario = 'FreshCampaignProgressionWithExplicitCrashOnlyRetry'; attempts = $attempts; finalResult = $finalResult; passed = [bool]($finalResult.Passed -and $attempts[-1].exitCode -eq 0) }
                $stageOutput | ConvertTo-Json -Depth 8
                if (-not $stageOutput.passed) { throw 'Fresh campaign recruitment progression failed after bounded startup recovery.' }
            }
        }
        'Protocol' {
            Invoke-Stage -Name 'Protocol' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $protocolScript
                if ($LASTEXITCODE -ne 0) { throw "Agent protocol test failed with exit code $LASTEXITCODE." }
            }
        }
        'Observation' {
            Invoke-Stage -Name 'Observation' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $observationScript
                if ($LASTEXITCODE -ne 0) { throw "Agent observation test failed with exit code $LASTEXITCODE." }
            }
        }
        'CaptivityObservation' {
            Invoke-Stage -Name 'CaptivityObservation' -Action {
                $testOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $captivityObservationScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native MainHero captivity observation test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'CaptivityOutcome' {
            Invoke-Stage -Name 'CaptivityOutcome' -Action {
                $testOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $captivityOutcomeScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native MainHero captivity outcome test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'PrisonCaptivityOutcome' {
            Invoke-Stage -Name 'PrisonCaptivityOutcome' -Action {
                $testOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $captivityOutcomeScript -CaptorContext Settlement 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native MainHero prison captivity outcome test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'EncounterSurrender' {
            Invoke-Stage -Name 'EncounterSurrender' -Action {
                $testOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $encounterSurrenderScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native Encounter surrender/captivity test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'EncounterEscape' {
            Invoke-Stage -Name 'EncounterEscape' -Action {
                $testOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $encounterEscapeScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native Encounter escape/outcome test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'JoinEncounterDefenders' {
            Invoke-Stage -Name 'JoinEncounterDefenders' -Action {
                $testOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $joinEncounterScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native Join Encounter Help Defenders test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'JoinEncounterEligibility' {
            Invoke-Stage -Name 'JoinEncounterEligibility' -Action {
                foreach ($relationProfile in @('HelpAttackers', 'Neutral')) {
                    $testOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $joinEncounterEligibilityScript -RelationProfile $relationProfile 2>&1 | Out-String
                    $testExitCode = $LASTEXITCODE
                    if ($testExitCode -ne 0) { throw "Native Join Encounter $relationProfile eligibility test failed with exit code $testExitCode.`n$testOutput" }
                    $testOutput
                }
            }
        }
        'JoinEncounterAbandonArmy' {
            Invoke-Stage -Name 'JoinEncounterAbandonArmy' -Action {
                $testOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $joinEncounterAbandonArmyScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native Join Encounter Abandon Army test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'MovingArmyJoin' {
            Invoke-Stage -Name 'MovingArmyJoin' -Action {
                $testOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $movingArmyJoinScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native unengaged Army encounter Join Army test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'JoinSiegeEvent' {
            Invoke-Stage -Name 'JoinSiegeEvent' -Action {
                $testOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $joinSiegeEventScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native Join Siege Event test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'MapNotifications' {
            Invoke-Stage -Name 'MapNotifications' -Action {
                $testOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $mapNotificationsScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native map notification observation test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'QuickInformation' {
            Invoke-Stage -Name 'QuickInformation' -Action {
                $testOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $quickInformationScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native QuickInformation observation test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'SceneNotification' {
            Invoke-Stage -Name 'SceneNotification' -Action {
                $testOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $sceneNotificationScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native SceneNotification observation test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'MissionLeave' {
            Invoke-Stage -Name 'MissionLeave' -Action {
                $testOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $missionLeaveScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native Mission Leave runtime test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'VillageToolsDelivery' {
            Invoke-Stage -Name 'VillageToolsDelivery' -Action {
                $testOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $villageToolsDeliveryScript -MaxDecisions $VillageToolsMaxDecisions 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Autonomous Native Village Tools delivery test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'Movement' {
            Invoke-Stage -Name 'Movement' -Action {
                $testOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $movementScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Agent movement test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'Hold' {
            Invoke-Stage -Name 'Hold' -Action {
                $testOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $holdScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native Hold behavior test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'MoveToPoint' {
            Invoke-Stage -Name 'MoveToPoint' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $moveToPointScript
                if ($LASTEXITCODE -ne 0) { throw "Agent point movement test failed with exit code $LASTEXITCODE." }
            }
        }
        'Recruitment' {
            Invoke-Stage -Name 'Recruitment' -Action {
                $testOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $recruitmentScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Agent recruitment test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'Rest' {
            Invoke-Stage -Name 'Rest' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $restScript
                if ($LASTEXITCODE -ne 0) { throw "Agent rest test failed with exit code $LASTEXITCODE." }
            }
        }
        'Pursuit' {
            Invoke-Stage -Name 'Pursuit' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $pursuitScript
                if ($LASTEXITCODE -ne 0) { throw "Agent pursuit test failed with exit code $LASTEXITCODE." }
            }
        }
        'EngageVisibility' {
            Invoke-Stage -Name 'EngageVisibility' -Action {
                $previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
                $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
                try {
                    $testOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $pursuitScript -ProbeEngageVisibilityLoss -VisibilityProbeSeconds $VisibilityProbeSeconds -TimeoutSeconds 240 2>&1 | Out-String
                    $testExitCode = $LASTEXITCODE
                    if ($testExitCode -ne 0) { throw "Agent Engage visibility probe failed with exit code $testExitCode.`n$testOutput" }
                }
                finally {
                    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
                    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
                }
            }
        }
        'Conversation' {
            Invoke-Stage -Name 'Conversation' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $pursuitScript -ProbeConversation
                if ($LASTEXITCODE -ne 0) { throw "Agent conversation lifecycle test failed with exit code $LASTEXITCODE." }
            }
        }
        'QuestAcceptance' {
            Invoke-Stage -Name 'QuestAcceptance' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $pursuitScript -ProbeQuestAcceptance
                if ($LASTEXITCODE -ne 0) { throw "Agent Quest acceptance test failed with exit code $LASTEXITCODE." }
            }
        }
        'EscortVisibility' {
            Invoke-Stage -Name 'EscortVisibility' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $pursuitScript -ProbeEscortVisibilityLoss -VisibilityProbeSeconds 45
                if ($LASTEXITCODE -ne 0) { throw "Escort visibility probe failed with exit code $LASTEXITCODE." }
            }
        }
        'TavernMission' {
            Invoke-Stage -Name 'TavernMission' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $tavernMissionScript
                if ($LASTEXITCODE -ne 0) { throw "Native Tavern Mission entry test failed with exit code $LASTEXITCODE." }
            }
        }
        'TownCenterMission' {
            Invoke-Stage -Name 'TownCenterMission' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $townCenterMissionScript
                if ($LASTEXITCODE -ne 0) { throw "Native Town Center Mission test failed with exit code $LASTEXITCODE." }
            }
        }
        'SettlementOverlayConversation' {
            Invoke-Stage -Name 'SettlementOverlayConversation' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $settlementOverlayConversationScript -TargetSettlementId $TargetSettlementId -ApproachSettlementId $ApproachSettlementId
                if ($LASTEXITCODE -ne 0) { throw "Native Settlement overlay Conversation test failed with exit code $LASTEXITCODE." }
            }
        }
        'SettlementOverlayQuickTalk' {
            Invoke-Stage -Name 'SettlementOverlayQuickTalk' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $settlementOverlayConversationScript -TargetSettlementId $QuickTalkTargetSettlementId -ApproachSettlementId $QuickTalkTargetSettlementId -InteractionMode QuickTalk -ExpectedOutcome ConversationOnly
                if ($LASTEXITCODE -ne 0) { throw "Native Settlement overlay QuickConversation test failed with exit code $LASTEXITCODE." }
            }
        }
        'SettlementOverlayQuestAcceptance' {
            Invoke-Stage -Name 'SettlementOverlayQuestAcceptance' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $settlementOverlayConversationScript -TargetSettlementId $TargetSettlementId -ApproachSettlementId $ApproachSettlementId -ExpectedOutcome QuestAccepted
                if ($LASTEXITCODE -ne 0) { throw "Native Settlement overlay Issue Quest acceptance test failed with exit code $LASTEXITCODE." }
            }
        }
        'SettlementOverlayQuestGate' {
            Invoke-Stage -Name 'SettlementOverlayQuestGate' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $settlementOverlayConversationScript -ExpectedOutcome NativePreconditionBlocked
                if ($LASTEXITCODE -ne 0) { throw "Native Settlement overlay Issue Quest precondition gate test failed with exit code $LASTEXITCODE." }
            }
        }
        'MapSettlementTargets' {
            Invoke-Stage -Name 'MapSettlementTargets' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $mapSettlementTargetsScript
                if ($LASTEXITCODE -ne 0) { throw "Native map settlement visibility and movement guard test failed with exit code $LASTEXITCODE." }
            }
        }
        'MainHeroSkills' {
            Invoke-Stage -Name 'MainHeroSkills' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $mainHeroSkillsScript
                if ($LASTEXITCODE -ne 0) { throw "Native MainHero skills observation test failed with exit code $LASTEXITCODE." }
            }
        }
        'CharacterDevelopment' {
            Invoke-Stage -Name 'CharacterDevelopment' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $characterDevelopmentScript
                if ($LASTEXITCODE -ne 0) { throw "Native MainHero Character Developer observation test failed with exit code $LASTEXITCODE." }
            }
        }
        'SpendSkillFocus' {
            Invoke-Stage -Name 'SpendSkillFocus' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $spendSkillFocusScript
                if ($LASTEXITCODE -ne 0) { throw "Native Character Developer Skill Focus transaction test failed with exit code $LASTEXITCODE." }
            }
        }
        'QuestJournal' {
            Invoke-Stage -Name 'QuestJournal' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $settlementOverlayConversationScript -TargetSettlementId village_V1_1 -ApproachSettlementId town_V1 -ExpectedOutcome QuestAccepted -ValidateQuestDetails
                if ($LASTEXITCODE -ne 0) { throw "Native Quest Journal details comparison failed with exit code $LASTEXITCODE." }
            }
        }
        'PartyRoster' {
            Invoke-Stage -Name 'PartyRoster' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $partyRosterScript
                if ($LASTEXITCODE -ne 0) { throw "Native MainParty roster observation test failed with exit code $LASTEXITCODE." }
            }
        }
        'MapPartyTargets' {
            Invoke-Stage -Name 'MapPartyTargets' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $mapPartyTargetsScript
                if ($LASTEXITCODE -ne 0) { throw "Native Map party target observation test failed with exit code $LASTEXITCODE." }
            }
        }
        'MapPartyQuestMarkers' {
            Invoke-Stage -Name 'MapPartyQuestMarkers' -Action {
                $testOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $mapPartyQuestMarkersScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native map Party Issue marker observation test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'MapPartyQuestAcceptance' {
            Invoke-Stage -Name 'MapPartyQuestAcceptance' -Action {
                $testOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $mapPartyQuestAcceptanceScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native map Lord Issue Quest acceptance test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'MapPartyComposition' {
            Invoke-Stage -Name 'MapPartyComposition' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $mapPartyCompositionScript
                if ($LASTEXITCODE -ne 0) { throw "Native Map party composition/expanded tooltip comparison failed with exit code $LASTEXITCODE." }
            }
        }
        'MapArmyComposition' {
            Invoke-Stage -Name 'MapArmyComposition' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $mapPartyCompositionScript -ValidateArmyTooltip
                if ($LASTEXITCODE -ne 0) { throw "Native Army tooltip composition comparison failed with exit code $LASTEXITCODE." }
            }
        }
        'MapPartyBehavior' {
            Invoke-Stage -Name 'MapPartyBehavior' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $mapPartyBehaviorScript -ValidateArmyTooltip
                if ($LASTEXITCODE -ne 0) { throw "Native Map party behavior summary comparison failed with exit code $LASTEXITCODE." }
            }
        }
        'PartyUpgrade' {
            Invoke-Stage -Name 'PartyUpgrade' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $partyUpgradeScript
                if ($LASTEXITCODE -ne 0) { throw "Native MainParty PartyScreen upgrade transaction failed with exit code $LASTEXITCODE." }
            }
        }
        'PartyPrisonerRecruitment' {
            Invoke-Stage -Name 'PartyPrisonerRecruitment' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $partyPrisonerRecruitmentScript
                if ($LASTEXITCODE -ne 0) { throw "Native MainParty PartyScreen prisoner recruitment transaction failed with exit code $LASTEXITCODE." }
            }
        }
        'MissionInteraction' {
            Invoke-Stage -Name 'MissionInteraction' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $missionInteractionScript
                if ($LASTEXITCODE -ne 0) { throw "Native Mission Agent interaction regression failed with exit code $LASTEXITCODE." }
            }
        }
        'CompanionHiring' {
            Invoke-Stage -Name 'CompanionHiring' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $companionHiringScript
                if ($LASTEXITCODE -ne 0) { throw "Native Wanderer companion-hiring flow failed with exit code $LASTEXITCODE." }
            }
        }
        'PartyRoles' {
            Invoke-Stage -Name 'PartyRoles' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $partyRolesScript
                if ($LASTEXITCODE -ne 0) { throw "Native PartyRole assignment/removal flow failed with exit code $LASTEXITCODE." }
            }
        }
        'InventoryNavigation' {
            Invoke-Stage -Name 'InventoryNavigation' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $inventoryNavigationScript
                if ($LASTEXITCODE -ne 0) { throw "Native Inventory navigation/clock boundary test failed with exit code $LASTEXITCODE." }
            }
        }
        'EquipmentTransactions' {
            Invoke-Stage -Name 'EquipmentTransactions' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $equipmentTransactionsScript
                if ($LASTEXITCODE -ne 0) { throw "Native MainHero equip/unequip transaction test failed with exit code $LASTEXITCODE." }
            }
        }
        'TradeTransactions' {
            Invoke-Stage -Name 'TradeTransactions' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $tradeTransactionsScript
                if ($LASTEXITCODE -ne 0) { throw "Native Town Trade transaction test failed with exit code $LASTEXITCODE." }
            }
        }
        'BarterTransactions' {
            Invoke-Stage -Name 'BarterTransactions' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $barterTransactionsScript
                if ($LASTEXITCODE -ne 0) { throw "Native ordinary Lord Barter transaction test failed with exit code $LASTEXITCODE." }
            }
        }
        'BarterContexts' {
            Invoke-Stage -Name 'BarterContexts' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $barterContextsScript
                if ($LASTEXITCODE -ne 0) { throw "Native Safe Passage Barter context test failed with exit code $LASTEXITCODE." }
                & powershell -NoProfile -ExecutionPolicy Bypass -File $barterContextsScript -CancelOnly
                if ($LASTEXITCODE -ne 0) { throw "Native Safe Passage Cancel/encounter-menu test failed with exit code $LASTEXITCODE." }
                & powershell -NoProfile -ExecutionPolicy Bypass -File $barterContextsScript -FightOnly
                if ($LASTEXITCODE -ne 0) { throw "Native Safe Passage Fight/encounter-menu test failed with exit code $LASTEXITCODE." }
            }
        }
        'BarterFightRoute' {
            Invoke-Stage -Name 'BarterFightRoute' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $barterContextsScript -FightOnly
                if ($LASTEXITCODE -ne 0) { throw "Native Safe Passage Fight-route test failed with exit code $LASTEXITCODE." }
            }
        }
        'BarterSafePassage' {
            Invoke-Stage -Name 'BarterSafePassage' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $barterContextsScript -ObserveExpiry
                if ($LASTEXITCODE -ne 0) { throw "Native Safe Passage offer/cooldown test failed with exit code $LASTEXITCODE." }
            }
        }
        'AgentLoop' {
            Invoke-Stage -Name 'AgentLoop' -Action {
                $testOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $agentLoopScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Agent decision loop test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'TimeControlLoop' {
            Invoke-Stage -Name 'TimeControlLoop' -Action {
                $testOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $agentLoopScript -TimeControlOnly 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native time-control decision loop test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'BattleFixture' {
            Invoke-Stage -Name 'BattleFixture' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $battleFixtureScript
                if ($LASTEXITCODE -ne 0) { throw "Battle fixture test failed with exit code $LASTEXITCODE." }
            }
        }
        'PostBattle' {
            Invoke-Stage -Name 'PostBattle' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $battleFixtureScript -Scenario PostBattle -CaptureFrames
                if ($LASTEXITCODE -ne 0) { throw "Postbattle test failed with exit code $LASTEXITCODE." }
            }
        }
        'VisualCapture' {
            Invoke-Stage -Name 'VisualCapture' -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $visualCaptureScript
                if ($LASTEXITCODE -ne 0) { throw "Window-only visual capture failed with exit code $LASTEXITCODE." }
            }
        }
    }
    $stages += $stageResult
    if (-not $stageResult.Passed) {
        break
    }
}

$summary = [ordered]@{
    RunId = $runId
    Phase = $Phase
    Passed = @($stages | Where-Object { -not $_.Passed }).Count -eq 0 -and $stages.Count -eq $requestedStages.Count
    Stages = $stages
    SourceControl = $sourceControl
    EvidenceDirectory = $runDirectory
}
$summary | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $runDirectory 'summary.json') -Encoding UTF8
$summary | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $evidenceRoot 'latest.json') -Encoding UTF8
$summary | ConvertTo-Json -Depth 5

if (-not $summary.Passed) {
    exit 1
}
