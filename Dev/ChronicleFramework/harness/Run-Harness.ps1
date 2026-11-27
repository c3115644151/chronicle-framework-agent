#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('Docs', 'Preflight', 'ConfiguredModelPreflight', 'Api', 'Build', 'Smoke', 'ReleasePackage', 'Campaign', 'CampaignActorThinkTrace', 'FreshCampaign', 'FreshStoryModeSetup', 'FreshStoryModeModelEvaluation', 'PersistentEycCampaign', 'EycObjectiveCheckpointReadback', 'FreshStoryModeNativeMenuLeaveEvaluation', 'FreshStoryModeNativeInquiryResponseEvaluation', 'FreshCampaignProgression', 'FreshCampaignBaselineMatrix', 'FreshCampaignLiveModelEvaluation', 'FreshCampaignSupplyBaseline', 'FreshCampaignRecruitmentFallback', 'Protocol', 'AgentHostProvider', 'AgentHostProviderHealth', 'AgentHostPackage', 'AgentHostSupplyEvaluation', 'AgentHostCampaignLoopEvaluation', 'AgentHostNativeMapMovementMonitorProbe', 'AgentHostVillageToolsQuestEvaluation', 'AgentHostEstablishClanGoalPlannerEvaluation', 'AgentHostEstablishClanAutonomyEvaluation', 'AgentHostCaptivityRecoveryEvaluation', 'AgentHostEstablishClanGoldSaleEvaluation', 'AgentHostBattleSimulationEvaluation', 'AgentHostBattleAndCaptivityEvaluation', 'AgentHostLifecycleEvaluation', 'AgentHostLifecycleCompletionEvaluation', 'AgentLoop', 'LiveModel', 'LiveModelArrival', 'LiveModelRecruitment', 'LiveModelSafePassageRecruitment', 'LiveModelRecruitmentEvaluation', 'LiveModelSupplyEvaluation', 'CheckpointPersistence', 'LiveModelResume', 'LiveModelRuntimeResume', 'LiveModelActionRecovery', 'CheckpointValidation', 'RecruitmentBaseline', 'MultiDaySupplyBaseline', 'TimeControlLoop', 'BattleMissionFormationProbe', 'BattleMissionInputIsolationProbe', 'BattleMissionControllerProbe', 'BattleMissionRtsCameraProbe', 'BattleMissionMovementInputProbe', 'BattleMissionAgentNavigatorProbe', 'BattleMissionNativeAiHandoffProbe', 'BattleMissionHostNativeAiAutopilotProbe', 'BattleFixture', 'PostBattle', 'Observation', 'CaptivityObservation', 'CaptivityOutcome', 'EncounterSurrender', 'EncounterEscape', 'JoinEncounterDefenders', 'JoinEncounterEligibility', 'JoinEncounterAbandonArmy', 'MovingArmyJoin', 'JoinSiegeEvent', 'MapNotifications', 'MapIncidentInputGuard', 'QuickInformation', 'SceneNotification', 'MissionLeave', 'VillageToolsDelivery', 'MainHeroSkills', 'CharacterDevelopment', 'SpendSkillFocus', 'QuestJournal', 'PartyRoster', 'MapPartyTargets', 'MapPartyQuestMarkers', 'MapPartyQuestAcceptance', 'MapEscapeMenu', 'MapInquiry', 'AlleyLeaderInquiry', 'AlleyRosterManagement', 'AlleyAbandonment', 'AlleyEntryMenu', 'MissionSceneNavigation', 'AlleyVolunteerBranches', 'AlleyAttackYield', 'AlleyAttackFightMission', 'PersuasionDetails', 'MapPartyComposition', 'MapArmyComposition', 'MapPartyBehavior', 'PartyUpgrade', 'PartyPrisonerRecruitment', 'PrisonerRansomSale', 'IdlePressure', 'OpeningScenario', 'PartyRoles', 'InventoryNavigation', 'EquipmentTransactions', 'TradeTransactions', 'BarterTransactions', 'BarterContexts', 'BarterFightRoute', 'MissionInteraction', 'ArenaMasterInteraction', 'CompanionHiring', 'MapSettlementTargets', 'Movement', 'Hold', 'MoveToPoint', 'Recruitment', 'Rest', 'Pursuit', 'EngageVisibility', 'Conversation', 'QuestAcceptance', 'EscortVisibility', 'TavernMission', 'TownCenterMission', 'SettlementOverlayConversation', 'SettlementOverlayQuickTalk', 'SettlementOverlayQuestAcceptance', 'SettlementOverlayQuestGate', 'SettlementOverlayQuickTalkIssueGateProbe', 'VisualCapture', 'MarketProbe', 'VillageMarketProbe', 'BattleLootSale', 'DecisionTimeline', 'All')]
    [string]$Phase = 'All',
    [switch]$RecruitmentBulkOnly,
    [string]$FreshStoryModeModel = '',
    [switch]$AllowDshXdPoolFreeRoute,
    [switch]$AllowDshWorkBuddyGateway,
    [switch]$ProbeDshFreeRouteWithMinimalChat,
    [int]$SmokeTimeoutSeconds = 180,
    [ValidateRange(64,2048)][int]$ProviderSmokeMaxOutputTokens = 128,
    [int]$SmokeStabilitySeconds = 8,
    [ValidateSet('Stop','Complete','UnsupportedGoal','MissingModel','ServiceUnavailable','ParentExited','StopTimeout','NonMap','CampaignRoundtrip','InputToggle')][string]$LifecycleScenario = 'Stop',
    [string]$TargetSettlementId = 'town_V1',
    [string]$ApproachSettlementId = 'town_V1',
    [string]$QuickTalkTargetSettlementId = 'village_V1_1',
    [int]$VisibilityProbeSeconds = 120,
    [int]$VillageToolsMaxDecisions = 320,
    [ValidateRange(1,5)][int]$SupplyBaselineRepetitions = 3,
    [ValidateRange(1,3)][int]$SupplyModelRuns = 3,
    [ValidateRange(1,3)][int]$AgentHostSupplyRuns = 3,
    [ValidateRange(1,20)][int]$SupplyBaselineProvisionAmount = 4,
    [ValidateRange(1,5)][int]$FreshCampaignSupplyRuns = 5,
    [ValidateRange(1,10)][int]$RecruitmentFallbackMaxAttempts = 10,
    [string]$BattleSimulationSourceSaveName = 'AgentBridgeLifecycle',
    [switch]$BattleMissionSoloMainHeroProbe,
    [switch]$BattleMissionDesktopInputIsolationOnly,
    [string]$StoryModePlannerSourceSaveName = 'save002',
    [ValidateRange(60,86400)][int]$PersistentEycHostMaxElapsedSeconds = 86400,
    [ValidateRange(1,160)][int]$PersistentEycMaxProviderDecisionsPerContinuation = 1,
    [ValidateRange(1,2)][int]$PersistentEycMaxHttpRequestsPerDecision = 1,
    [ValidatePattern('^([A-Za-z0-9_-]{1,8})?$')][string]$PersistentEycCampaignKey = '',
    [ValidateRange(1,10)][int]$NativeMapMovementProbeWaitSeconds = 8,
    [string]$DecisionTimelineRunDirectory = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'HarnessPaths.ps1')
$layout = Get-HarnessLayout -ProjectRoot (Split-Path -Parent $PSScriptRoot)
$stageRoot = [string]$layout.StageRoot
$agentHostRoot = [string]$layout.AgentHostRoot
$modRoot = [string]$layout.ModRoot
$docsRoot = [string]$layout.DocsRoot
$modulePackageRoot = [string]$layout.ModulePackageRoot
$toolRoot = [string]$layout.ToolRoot
$stagesRoot = [string]$layout.StagesRoot

$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$startupEvidenceScript = Join-Path $PSScriptRoot 'HarnessStartupEvidence.ps1'
. $startupEvidenceScript
$researchReadinessScript = Join-Path $PSScriptRoot 'HarnessResearchReadiness.ps1'
. $researchReadinessScript
$HarnessContractVersion = '7.735'
$providerCredentialScript = Join-Path $PSScriptRoot 'Get-FreeLLMAPIProfile.ps1'
function Get-HarnessConfiguredProviderCredential {
    . $providerCredentialScript
    $baseUrl = [string][Environment]::GetEnvironmentVariable('CHRONICLE_LLM_BASE_URL', 'Process')
    if ([string]::IsNullOrWhiteSpace($baseUrl)) { $baseUrl = [string][Environment]::GetEnvironmentVariable('CHRONICLE_LLM_BASE_URL', 'User') }
    $endpoint = $null
    if (-not [Uri]::TryCreate($baseUrl, [UriKind]::Absolute, [ref]$endpoint) -or
        -not [string]::IsNullOrWhiteSpace($endpoint.Query) -or -not [string]::IsNullOrWhiteSpace($endpoint.UserInfo) -or
        -not [string]::IsNullOrWhiteSpace($endpoint.Fragment)) {
        throw 'The configured model endpoint is invalid; no inference request was sent.'
    }
    $credential = Get-ChronicleProviderCredential -Endpoint $endpoint
    if ([string]::IsNullOrWhiteSpace([string]$credential.Value)) {
        throw 'The endpoint-specific provider credential is unavailable; no inference request was sent.'
    }
    return $credential
}
function Get-OpenRouterZeroPriceReceipt {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$ModelId)

    if ($ModelId -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.:-]+$') {
        throw 'The selected OpenRouter model ID is not a valid author/model slug; no inference request was sent.'
    }
    $modelUri = [Uri]::new('https://openrouter.ai/api/v1/model/' + $ModelId)
    try {
        $modelReceipt = Invoke-RestMethod -Method Get -Uri $modelUri -Proxy 'http://127.0.0.1:7890' -TimeoutSec 15
    }
    catch { throw 'The current OpenRouter public price receipt could not be fetched through the configured local proxy; no inference request was sent.' }
    $data = $modelReceipt.data
    $promptPrice = [decimal]0
    $completionPrice = [decimal]0
    if ([string]$data.id -cne $ModelId -or $null -eq $data.pricing -or
        -not [decimal]::TryParse([string]$data.pricing.prompt, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$promptPrice) -or
        -not [decimal]::TryParse([string]$data.pricing.completion, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$completionPrice)) {
        throw 'OpenRouter did not return a matching model ID with explicit prompt and completion prices; no inference request was sent.'
    }
    if ($promptPrice -ne 0 -or $completionPrice -ne 0) {
        throw 'The selected OpenRouter model is not currently zero-priced for both prompt and completion tokens; no inference request was sent.'
    }
    return [ordered]@{
        Available = $true
        ModelId = $ModelId
        PromptPriceUsdPerToken = $promptPrice.ToString([Globalization.CultureInfo]::InvariantCulture)
        CompletionPriceUsdPerToken = $completionPrice.ToString([Globalization.CultureInfo]::InvariantCulture)
        Source = $modelUri.AbsoluteUri
        VerifiedUtc = [DateTime]::UtcNow.ToString('O', [Globalization.CultureInfo]::InvariantCulture)
    }
}
if ($BattleMissionSoloMainHeroProbe -and $Phase -ne 'BattleMissionHostNativeAiAutopilotProbe') {
    throw 'The solo MainHero option is only valid with -Phase BattleMissionHostNativeAiAutopilotProbe.'
}
if ($BattleMissionDesktopInputIsolationOnly -and $Phase -ne 'BattleMissionInputIsolationProbe') {
    throw 'The desktop input isolation option is only valid with -Phase BattleMissionInputIsolationProbe.'
}
if ($Phase -ceq 'EycObjectiveCheckpointReadback' -and [string]::IsNullOrWhiteSpace($PersistentEycCampaignKey)) {
    throw 'EycObjectiveCheckpointReadback requires -PersistentEycCampaignKey to select one owned Campaign branch.'
}
if ($Phase -in @('ConfiguredModelPreflight','FreshStoryModeModelEvaluation','PersistentEycCampaign') -and [string]::IsNullOrWhiteSpace($FreshStoryModeModel)) {
    throw 'Select an explicit model ID with -FreshStoryModeModel; the configured provider catalog will verify it before any game or model request.'
}
if ($Phase -in @('FreshStoryModeModelEvaluation','PersistentEycCampaign') -and $FreshStoryModeModel -match '^(auto(?::|$)|fusion(?::|$)|free-router$)') {
    throw 'FreeLLMAPI multi-provider router inference is blocked until its active chain is verified free-only with readable quota/cost evidence; no game or model request was sent.'
}
if ($Phase -in @('ConfiguredModelPreflight','AgentHostProvider','AgentHostProviderHealth','PersistentEycCampaign') -and
    $FreshStoryModeModel -match '^buddy:hy4flash(?:-free)?$' -and -not $AllowDshWorkBuddyGateway) {
    throw 'The DSH WorkBuddy gateway requires explicit -AllowDshWorkBuddyGateway opt-in; no game or model request was sent.'
}
if ($Phase -in @('ConfiguredModelPreflight','AgentHostProvider','AgentHostProviderHealth','PersistentEycCampaign') -and
    $FreshStoryModeModel -ceq 'xdpool/hy4flash-free' -and -not $AllowDshXdPoolFreeRoute) {
    throw 'The DSH XD Pool WorkBuddy free route requires explicit -AllowDshXdPoolFreeRoute opt-in; no game or model request was sent.'
}
if ($Phase -ceq 'FreshStoryModeModelEvaluation' -and $FreshStoryModeModel -match '^buddy:hy4flash(?:-free)?$') {
    throw 'The DSH WorkBuddy route is supported only by bounded Provider and PersistentEycCampaign phases; no unbounded fresh-Campaign model run was sent.'
}
if ($Phase -ceq 'FreshStoryModeModelEvaluation' -and $FreshStoryModeModel -ceq 'xdpool/hy4flash-free') {
    throw 'The DSH XD Pool WorkBuddy free route is supported only by bounded Provider and PersistentEycCampaign phases; no unbounded fresh-Campaign model run was sent.'
}
if ($Phase -ceq 'PersistentEycCampaign' -and $FreshStoryModeModel -match '^xdpool-aggregate/open_router/.+:free$' -and
    ($PersistentEycMaxProviderDecisionsPerContinuation -gt 4 -or $PersistentEycMaxHttpRequestsPerDecision -ne 1)) {
    throw 'OpenRouter :free persistent continuations are limited to four provider decisions and one HTTP request per decision; failed requests also consume the published 50/day quota. No game or model request was sent.'
}
if ($Phase -ceq 'PersistentEycCampaign' -and $FreshStoryModeModel -match '^buddy:hy4flash(?:-free)?$' -and
    ($PersistentEycMaxProviderDecisionsPerContinuation -gt 4 -or $PersistentEycMaxHttpRequestsPerDecision -ne 1)) {
    throw 'DSH WorkBuddy persistent continuations are limited to four provider decisions and one HTTP request per decision. No game or model request was sent.'
}
if ($Phase -ceq 'PersistentEycCampaign' -and $FreshStoryModeModel -ceq 'xdpool/hy4flash-free' -and
    ($PersistentEycMaxProviderDecisionsPerContinuation -gt 4 -or $PersistentEycMaxHttpRequestsPerDecision -ne 1)) {
    throw 'DSH XD Pool WorkBuddy free continuations are limited to four provider decisions and one HTTP request per decision. No game or model request was sent.'
}
if (-not [string]::IsNullOrWhiteSpace($FreshStoryModeModel) -and ($FreshStoryModeModel.Length -gt 256 -or $FreshStoryModeModel -match '[\x00-\x1F\x7F]')) {
    throw 'FreshStoryModeModel must be a model ID of at most 256 characters with no control characters.'
}
$effectiveSmokeTimeoutSeconds = if ($Phase -in @('FreshStoryModeModelEvaluation','FreshStoryModeNativeInquiryResponseEvaluation','AgentHostVillageToolsQuestEvaluation','AgentHostEstablishClanGoalPlannerEvaluation','AgentHostEstablishClanAutonomyEvaluation','AgentHostCaptivityRecoveryEvaluation','AgentHostEstablishClanGoldSaleEvaluation','AgentHostBattleSimulationEvaluation','AgentHostBattleAndCaptivityEvaluation')) { [Math]::Max($SmokeTimeoutSeconds, 240) } else { $SmokeTimeoutSeconds }
$harnessRoot = [string]$layout.ProjectRoot
$localSettingsPath = Join-Path $harnessRoot 'harness.local.json'
if (-not (Test-Path -LiteralPath $localSettingsPath)) { throw "Local harness settings not found: $localSettingsPath. Run Initialize-ChronicleWorkspace.ps1 first." }
$localSettings = Get-Content -LiteralPath $localSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
$repositoryRoot = [IO.Path]::GetFullPath([string]$localSettings.repositoryRoot)
$gameRoot = [IO.Path]::GetFullPath([string]$localSettings.gameRoot)
if (-not (Test-Path -LiteralPath $repositoryRoot -PathType Container)) { throw "Repository root not found: $repositoryRoot" }
if (-not (Test-Path -LiteralPath (Join-Path $gameRoot 'bin\Win64_Shipping_Client\Bannerlord.exe'))) { throw "Configured Bannerlord game root is invalid: $gameRoot" }
$script:BannerlordAutoSaveRecoveryOnHarnessStart = Restore-ChronicleHarnessAutoSaveSetting
$script:BannerlordSoundRecoveryOnHarnessStart = Restore-ChronicleHarnessGameSound
$env:CHRONICLE_GAME_ROOT = $gameRoot
$env:CHRONICLE_REPOSITORY_ROOT = $repositoryRoot
$evidenceRoot = Join-Path $harnessRoot 'TestResults'
$runId = Get-Date -Format 'yyyyMMdd-HHmmss'
$runDirectory = Join-Path $evidenceRoot $runId
$script:retainedAgentHostPackageRoot = $null
$script:retainedAgentHostExecutablePath = $null
$previousAgentHostTestPath = [Environment]::GetEnvironmentVariable('CHRONICLE_AGENT_HOST_TEST_PATH', 'Process')
$manifestPath = Join-Path $gameRoot 'Modules\ChronicleFramework\SubModule.xml'
$sourceManifestPath = Join-Path $modulePackageRoot 'SubModule.xml'
$gameExe = Join-Path $gameRoot 'bin\Win64_Shipping_Client\Bannerlord.exe'
$projectPath = Join-Path $modRoot 'ChronicleFramework.csproj'
$agentHostProjectPath = Join-Path $agentHostRoot 'ChronicleAgentHost.csproj'
$agentHostDllPath = Join-Path $agentHostRoot 'bin\Release\net8.0\ChronicleAgentHost.dll'
$agentHostMovementProbeScript = Join-Path $stageRoot 'Test-AgentHostNativeMapMovementMonitorProbe.ps1'
$apiScript = Join-Path $toolRoot 'ApiProbe\Inspect-CampaignApi.ps1'
$smokeScript = Join-Path $stageRoot 'Test-Module.ps1'
$campaignScript = Join-Path $stageRoot 'Test-Campaign.ps1'
$freshCampaignScript = Join-Path $stageRoot 'Test-AgentFreshCampaign.ps1'
$persistentEycCampaignScript = Join-Path $stageRoot 'Test-AgentPersistentStoryModeCampaign.ps1'
$eycObjectiveCheckpointReadbackScript = Join-Path $stageRoot 'Test-AgentEycObjectiveCheckpointReadback.ps1'
$freshCampaignBaselineMatrixScript = Join-Path $stageRoot 'Test-AgentEvaluationFreshCampaignBaseline.ps1'
$freshCampaignLiveModelEvaluationScript = Join-Path $stageRoot 'Test-AgentEvaluationFreshCampaignLiveModel.ps1'
$saveModuleMetadataTestScript = Join-Path $stageRoot 'Test-AgentSaveMetadata.ps1'
$protocolScript = Join-Path $stageRoot 'Test-AgentProtocol.ps1'
$observationScript = Join-Path $stageRoot 'Test-AgentObservation.ps1'
$captivityObservationScript = Join-Path $stageRoot 'Test-AgentCaptivityObservation.ps1'
$captivityOutcomeScript = Join-Path $stageRoot 'Test-AgentCaptivityOutcome.ps1'
$encounterSurrenderScript = Join-Path $stageRoot 'Test-AgentEncounterSurrender.ps1'
$encounterEscapeScript = Join-Path $stageRoot 'Test-AgentEncounterEscape.ps1'
$joinEncounterScript = Join-Path $stageRoot 'Test-AgentJoinEncounterDefenders.ps1'
$joinEncounterEligibilityScript = Join-Path $stageRoot 'Test-AgentJoinEncounterEligibility.ps1'
$joinEncounterAbandonArmyScript = Join-Path $stageRoot 'Test-AgentJoinEncounterAbandonArmy.ps1'
$movingArmyJoinScript = Join-Path $stageRoot 'Test-AgentMovingArmyJoin.ps1'
$joinSiegeEventScript = Join-Path $stageRoot 'Test-AgentJoinSiegeEvent.ps1'
$mapNotificationsScript = Join-Path $stageRoot 'Test-AgentMapNotifications.ps1'
$mapIncidentInputGuardScript = Join-Path $stageRoot 'Test-AgentMapIncidentInputGuard.ps1'
$quickInformationScript = Join-Path $stageRoot 'Test-AgentQuickInformation.ps1'
$sceneNotificationScript = Join-Path $stageRoot 'Test-AgentSceneNotification.ps1'
$missionLeaveScript = Join-Path $stageRoot 'Test-AgentMissionLeave.ps1'
$villageToolsDeliveryScript = Join-Path $stageRoot 'Test-AgentVillageToolsDelivery.ps1'
$movementScript = Join-Path $stageRoot 'Test-AgentMovement.ps1'
$holdScript = Join-Path $stageRoot 'Test-AgentHold.ps1'
$moveToPointScript = Join-Path $stageRoot 'Test-AgentMoveToPoint.ps1'
$recruitmentScript = Join-Path $stageRoot 'Test-AgentRecruitment.ps1'
$restScript = Join-Path $stageRoot 'Test-AgentRest.ps1'
$multiDaySupplyBaselineScript = Join-Path $stageRoot 'Test-AgentMultiDaySupplyBaseline.ps1'
$freshCampaignSupplyBaselineScript = Join-Path $stageRoot 'Test-AgentEvaluationFreshCampaignSupplyBaseline.ps1'
$freshCampaignRecruitmentFallbackScript = Join-Path $stageRoot 'Test-AgentEvaluationFreshCampaignRecruitmentFallback.ps1'
$agentEvaluationLiveModelSupplyScript = Join-Path $stageRoot 'Test-AgentEvaluationLiveModelSupply.ps1'
$pursuitScript = Join-Path $stageRoot 'Test-AgentPursuit.ps1'
$agentLoopScript = Join-Path $stageRoot 'Test-AgentLoop.ps1'
$agentModelProviderScript = Join-Path $stageRoot 'Test-AgentOpenAICompatibleProvider.ps1'
$agentHostPackageScript = Join-Path $stageRoot 'Test-AgentHostPackage.ps1'
$agentHostReleasePackageScript = Join-Path $stageRoot 'Test-AgentHostReleasePackage.ps1'
$agentHostCampaignLoopEvaluationScript = Join-Path $stageRoot 'Test-AgentHostCampaignLoopEvaluation.ps1'
$campaignActorThinkTraceScript = Join-Path $stageRoot 'Test-AgentCampaignActorThinkTrace.ps1'
$agentHostLifecycleEvaluationScript = Join-Path $stageRoot 'Test-AgentHostLifecycleEvaluation.ps1'

function Remove-RetainedAgentHostPackage([string]$PackageRoot) {
    if ([string]::IsNullOrWhiteSpace($PackageRoot)) { return }
    $packageParent = [IO.Path]::GetFullPath('D:\ChronicleFramework\BuildCache\Packages').TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $resolvedPackageRoot = [IO.Path]::GetFullPath($PackageRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if ([IO.Path]::GetFullPath((Split-Path -Parent $resolvedPackageRoot)).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) -ne $packageParent -or
        (Split-Path -Leaf $resolvedPackageRoot) -notmatch '^ChronicleAgentHost-win-x64-[0-9a-f]{32}$') {
        throw 'Refusing retained Agent Host package cleanup outside its unique D: BuildCache package directory.'
    }
    $cleanupScript = Join-Path $stageRoot 'Test-AgentHostPackage.ps1'
    $cleanupOutput = & $HarnessPowerShell -NoProfile -File $cleanupScript -CleanupPackageRoot $resolvedPackageRoot 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Retained Agent Host package cleanup failed: $cleanupOutput" }
    $cleanupReceipt = $cleanupOutput | ConvertFrom-Json
    if (-not [bool]$cleanupReceipt.Removed -or (Test-Path -LiteralPath $resolvedPackageRoot)) { throw 'Retained Agent Host package directory remains after cleanup.' }
}
$agentLiveModelLoopScript = Join-Path $stageRoot 'Test-AgentLiveModelLoop.ps1'
$decisionTimelineScript = Join-Path $stageRoot 'Export-AgentDecisionTimeline.ps1'
$agentCheckpointPersistenceScript = Join-Path $stageRoot 'Test-AgentCheckpointPersistence.ps1'
$agentLiveModelResumeScript = Join-Path $stageRoot 'Test-AgentLiveModelResume.ps1'
$agentCheckpointValidationScript = Join-Path $stageRoot 'Test-AgentCheckpointValidation.ps1'
$agentEvaluationRecruitmentBaselineScript = Join-Path $stageRoot 'Test-AgentEvaluationRecruitmentBaseline.ps1'
$agentEvaluationLiveModelRecruitmentScript = Join-Path $stageRoot 'Test-AgentEvaluationLiveModelRecruitment.ps1'
$battleFixtureScript = Join-Path $stageRoot 'Test-AgentBattleFixture.ps1'
$battleMissionFormationProbeScript = Join-Path $stageRoot 'Test-AgentBattleMissionFormationProbe.ps1'
$visualCaptureScript = Join-Path $stageRoot 'Test-AgentVisualCapture.ps1'
$tavernMissionScript = Join-Path $stageRoot 'Test-AgentTavernMission.ps1'
$townCenterMissionScript = Join-Path $stageRoot 'Test-AgentTownCenterMission.ps1'
$settlementOverlayConversationScript = Join-Path $stageRoot 'Test-AgentSettlementOverlayConversation.ps1'
$mapSettlementTargetsScript = Join-Path $stageRoot 'Test-AgentMapSettlementTargets.ps1'
$mainHeroSkillsScript = Join-Path $stageRoot 'Test-AgentMainHeroSkills.ps1'
$characterDevelopmentScript = Join-Path $stageRoot 'Test-AgentCharacterDevelopment.ps1'
$spendSkillFocusScript = Join-Path $stageRoot 'Test-AgentSpendSkillFocus.ps1'
$partyRosterScript = Join-Path $stageRoot 'Test-AgentPartyRoster.ps1'
$mapPartyTargetsScript = Join-Path $stageRoot 'Test-AgentMapPartyTargets.ps1'
$mapPartyQuestMarkersScript = Join-Path $stageRoot 'Test-AgentMapPartyQuestMarkers.ps1'
$mapPartyQuestAcceptanceScript = Join-Path $stageRoot 'Test-AgentMapPartyQuestAcceptance.ps1'
$mapEscapeMenuScript = Join-Path $stageRoot 'Test-AgentMapEscapeMenu.ps1'
$mapInquiryScript = Join-Path $stageRoot 'Test-AgentMapInquiry.ps1'
$alleyLeaderInquiryScript = Join-Path $stageRoot 'Test-AgentAlleyLeaderInquiry.ps1'
$alleyRosterManagementScript = Join-Path $stageRoot 'Test-AgentAlleyRosterManagement.ps1'
$alleyAbandonmentScript = Join-Path $stageRoot 'Test-AgentAlleyAbandonment.ps1'
$alleyEntryMenuScript = Join-Path $stageRoot 'Test-AgentAlleyEntryMenu.ps1'
$missionSceneNavigationScript = Join-Path $stageRoot 'Test-AgentAlleyLeaderSceneEntry.ps1'
$alleyAttackYieldScript = Join-Path $stageRoot 'Test-AgentAlleyAttackYield.ps1'
$alleyAttackFightMissionScript = Join-Path $stageRoot 'Test-AgentAlleyAttackFightMission.ps1'
$persuasionDetailsScript = Join-Path $stageRoot 'Test-AgentPersuasionDetails.ps1'
$mapPartyCompositionScript = Join-Path $stageRoot 'Test-AgentMapPartyComposition.ps1'
$mapPartyBehaviorScript = Join-Path $stageRoot 'Test-AgentMapPartyBehavior.ps1'
$partyUpgradeScript = Join-Path $stageRoot 'Test-AgentPartyUpgrade.ps1'
$partyPrisonerRecruitmentScript = Join-Path $stageRoot 'Test-AgentPartyPrisonerRecruitment.ps1'
$prisonerRansomSaleScript = Join-Path $stageRoot 'Test-AgentPrisonerRansomSale.ps1'
$idlePressureScript = Join-Path $stageRoot 'Test-AgentIdlePressure.ps1'
$openingScenarioScript = Join-Path $stageRoot 'Test-AgentOpeningScenario.ps1'
$marketProbeScript = Join-Path $stageRoot 'Test-AgentMarketProbe.ps1'
$villageMarketProbeScript = Join-Path $stageRoot 'Test-AgentVillageMarketProbe.ps1'
$battleLootSaleScript = Join-Path $stageRoot 'Test-AgentBattleLootSaleProbe.ps1'
$missionInteractionScript = Join-Path $stageRoot 'Test-AgentMissionInteraction.ps1'
$arenaMasterInteractionScript = Join-Path $stageRoot 'Test-AgentArenaMasterInteraction.ps1'
$companionHiringScript = Join-Path $stageRoot 'Test-AgentCompanionHiring.ps1'
$partyRolesScript = Join-Path $stageRoot 'Test-AgentPartyRoles.ps1'
$inventoryNavigationScript = Join-Path $stageRoot 'Test-AgentInventoryNavigation.ps1'
$equipmentTransactionsScript = Join-Path $stageRoot 'Test-AgentEquipmentTransactions.ps1'
$tradeTransactionsScript = Join-Path $stageRoot 'Test-AgentTradeTransactions.ps1'
$barterTransactionsScript = Join-Path $stageRoot 'Test-AgentBarterTransactions.ps1'
$barterContextsScript = Join-Path $stageRoot 'Test-AgentSafePassageBarterContext.ps1'
$docsScript = Join-Path $stageRoot 'Check-Docs.ps1'
$contextPackScript = Join-Path $stageRoot 'Get-ContextPack.ps1'
$testResultsRetentionScript = Join-Path $stageRoot 'Prune-TestResults.ps1'

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
    'ConfiguredModelPreflight' { @('Preflight', 'ConfiguredModelPreflight') }
    'Api' { @('Api') }
    'Build' { @('Build') }
    'Smoke' { @('Smoke') }
    'ReleasePackage' { @('Preflight', 'AgentHostPackage', 'ReleasePackage') }
    'Campaign' { @('Preflight', 'Build', 'Campaign') }
    'CampaignActorThinkTrace' { @('Preflight', 'Build', 'CampaignActorThinkTrace') }
    'FreshCampaign' { @('Preflight', 'Build', 'FreshCampaign') }
    'FreshStoryModeSetup' { @('Preflight', 'Build', 'FreshStoryModeSetup') }
    'FreshStoryModeNativeMenuLeaveEvaluation' { @('Preflight', 'Build', 'FreshStoryModeNativeMenuLeaveEvaluation') }
    'FreshStoryModeNativeInquiryResponseEvaluation' { @('Preflight', 'Build', 'FreshStoryModeNativeInquiryResponseEvaluation') }
    'FreshStoryModeModelEvaluation' { @('Preflight', 'ConfiguredModelPreflight', 'Build', 'Smoke', 'AgentHostPackage', 'FreshStoryModeModelEvaluation') }
    # This phase launches and verifies its own packaged Native Host client; a separate Smoke client is redundant.
    'PersistentEycCampaign' { @('Preflight', 'ConfiguredModelPreflight', 'Build', 'AgentHostPackage', 'PersistentEycCampaign') }
    'EycObjectiveCheckpointReadback' { @('Preflight', 'EycObjectiveCheckpointReadback') }
    'FreshCampaignProgression' { @('Preflight', 'Build', 'FreshCampaignProgression') }
    'FreshCampaignBaselineMatrix' { @('Preflight', 'Build', 'FreshCampaignBaselineMatrix') }
    'FreshCampaignSupplyBaseline' { @('Preflight', 'Build', 'FreshCampaignSupplyBaseline') }
    'FreshCampaignRecruitmentFallback' { @('Preflight', 'Build', 'FreshCampaignRecruitmentFallback') }
    'FreshCampaignLiveModelEvaluation' { @('Preflight', 'Build', 'FreshCampaignLiveModelEvaluation') }
    'Protocol' { @('Preflight', 'Build', 'Protocol') }
    'AgentHostProvider' { @('Preflight', 'Build', 'AgentHostProvider') }
    'AgentHostProviderHealth' { @('Preflight', 'Build', 'AgentHostProviderHealth') }
    'AgentHostPackage' { @('Preflight', 'Build', 'AgentHostPackage') }
    'AgentHostNativeMapMovementMonitorProbe' { @('AgentHostProbeBuild', 'NativeMapMovementMonitorProbe') }
    'AgentHostSupplyEvaluation' { @('Preflight', 'Build', 'AgentHostSupplyEvaluation') }
    'AgentHostCampaignLoopEvaluation' { @('Preflight', 'Build', 'AgentHostCampaignLoopEvaluation') }
    'AgentHostVillageToolsQuestEvaluation' { @('Preflight', 'Build', 'Smoke', 'AgentHostPackage', 'AgentHostVillageToolsQuestEvaluation') }
    'AgentHostEstablishClanGoalPlannerEvaluation' { @('Preflight', 'Build', 'Smoke', 'AgentHostPackage', 'AgentHostEstablishClanGoalPlannerEvaluation') }
    'AgentHostEstablishClanAutonomyEvaluation' { @('Preflight', 'Build', 'AgentHostPackage', 'Smoke', 'AgentHostEstablishClanAutonomyEvaluation') }
    'AgentHostCaptivityRecoveryEvaluation' { @('Preflight', 'Build', 'Smoke', 'AgentHostPackage', 'AgentHostCaptivityRecoveryEvaluation') }
    'AgentHostEstablishClanGoldSaleEvaluation' { @('Preflight', 'Build', 'Smoke', 'AgentHostPackage', 'AgentHostEstablishClanGoldSaleEvaluation') }
    'AgentHostBattleSimulationEvaluation' { @('Preflight', 'Build', 'Smoke', 'AgentHostPackage', 'AgentHostBattleSimulationEvaluation') }
    'AgentHostBattleAndCaptivityEvaluation' { @('Preflight', 'Build', 'Smoke', 'AgentHostPackage', 'AgentHostBattleAndCaptivityEvaluation') }
    'AgentHostLifecycleEvaluation' { @('Preflight', 'Build', 'Smoke', 'AgentHostPackage', 'AgentHostLifecycleEvaluation') }
    'AgentHostLifecycleCompletionEvaluation' { @('Preflight', 'Build', 'Smoke', 'AgentHostPackage', 'AgentHostLifecycleCompletionEvaluation') }
    'AgentLoop' { @('Preflight', 'Build', 'AgentLoop') }
    'LiveModel' { @('Preflight', 'Build', 'LiveModel') }
    'LiveModelArrival' { @('Preflight', 'Build', 'LiveModelArrival') }
    'LiveModelRecruitment' { @('Preflight', 'Build', 'LiveModelRecruitment') }
    'LiveModelSafePassageRecruitment' { @('Preflight', 'Build', 'LiveModelSafePassageRecruitment') }
    'CheckpointPersistence' { @('Preflight', 'Build', 'CheckpointPersistence') }
    'LiveModelResume' { @('Preflight', 'Build', 'LiveModelResume') }
    'LiveModelRuntimeResume' { @('Preflight', 'Build', 'LiveModelRuntimeResume') }
    'LiveModelActionRecovery' { @('Preflight', 'Build', 'LiveModelActionRecovery') }
    'CheckpointValidation' { @('Preflight', 'Build', 'CheckpointValidation') }
    'RecruitmentBaseline' { @('Preflight', 'Build', 'RecruitmentBaseline') }
    'MultiDaySupplyBaseline' { @('Preflight', 'Build', 'MultiDaySupplyBaseline') }
    'LiveModelRecruitmentEvaluation' { @('Preflight', 'Build', 'LiveModelRecruitmentEvaluation') }
    'LiveModelSupplyEvaluation' { @('Preflight', 'Build', 'LiveModelSupplyEvaluation') }
    'TimeControlLoop' { @('Preflight', 'Build', 'TimeControlLoop') }
    'BattleMissionFormationProbe' { @('Preflight', 'Build', 'BattleMissionFormationProbe') }
    'BattleMissionInputIsolationProbe' { @('Preflight', 'Build', 'BattleMissionInputIsolationProbe') }
    'BattleMissionControllerProbe' { @('Preflight', 'Build', 'BattleMissionControllerProbe') }
    'BattleMissionRtsCameraProbe' { @('Preflight', 'Build', 'BattleMissionRtsCameraProbe') }
    'BattleMissionMovementInputProbe' { @('Preflight', 'Build', 'BattleMissionMovementInputProbe') }
    'BattleMissionAgentNavigatorProbe' { @('Preflight', 'Build', 'BattleMissionAgentNavigatorProbe') }
    'BattleMissionNativeAiHandoffProbe' { @('Preflight', 'Build', 'BattleMissionNativeAiHandoffProbe') }
    'BattleMissionHostNativeAiAutopilotProbe' { @('Preflight', 'Build', 'AgentHostPackage', 'BattleMissionHostNativeAiAutopilotProbe') }
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
    'MapIncidentInputGuard' { @('Preflight', 'Build', 'AgentHostPackage', 'MapIncidentInputGuard') }
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
    'MapEscapeMenu' { @('Preflight', 'Build', 'MapEscapeMenu') }
    'MapInquiry' { @('Preflight', 'Build', 'MapInquiry') }
    'AlleyLeaderInquiry' { @('Preflight', 'Build', 'AlleyLeaderInquiry') }
    'AlleyRosterManagement' { @('Preflight', 'Build', 'AlleyRosterManagement') }
    'AlleyAbandonment' { @('Preflight', 'Build', 'AlleyAbandonment') }
    'AlleyEntryMenu' { @('Preflight', 'Build', 'AlleyEntryMenu') }
    'MissionSceneNavigation' { @('Preflight', 'Build', 'MissionSceneNavigation') }
    'AlleyVolunteerBranches' { @('Preflight', 'Build', 'AlleyVolunteerBranches') }
    'AlleyAttackYield' { @('Preflight', 'Build', 'AlleyAttackYield') }
    'AlleyAttackFightMission' { @('Preflight', 'Build', 'AlleyAttackFightMission') }
    'PersuasionDetails' { @('Preflight', 'Build', 'PersuasionDetails') }
    'MapPartyComposition' { @('Preflight', 'Build', 'MapPartyComposition') }
    'MapArmyComposition' { @('Preflight', 'Build', 'MapArmyComposition') }
    'MapPartyBehavior' { @('Preflight', 'Build', 'MapPartyBehavior') }
    'PartyUpgrade' { @('Preflight', 'Build', 'PartyUpgrade') }
    'PartyPrisonerRecruitment' { @('Preflight', 'Build', 'PartyPrisonerRecruitment') }
    'PrisonerRansomSale' { @('Preflight', 'Build', 'PrisonerRansomSale') }
    'IdlePressure' { @('Preflight', 'Build', 'IdlePressure') }
    'OpeningScenario' { @('Preflight', 'Build', 'OpeningScenario') }
    'MarketProbe' { @('Preflight', 'Build', 'MarketProbe') }
    'VillageMarketProbe' { @('Preflight', 'Build', 'VillageMarketProbe') }
'BattleLootSale' { @('Preflight', 'Build', 'BattleLootSale') }
    'DecisionTimeline' { @('DecisionTimeline') }
    'PartyRoles' { @('Preflight', 'Build', 'PartyRoles') }
    'InventoryNavigation' { @('Preflight', 'Build', 'InventoryNavigation') }
    'EquipmentTransactions' { @('Preflight', 'Build', 'EquipmentTransactions') }
    'TradeTransactions' { @('Preflight', 'Build', 'TradeTransactions') }
    'BarterTransactions' { @('Preflight', 'Build', 'BarterTransactions') }
    'BarterContexts' { @('Preflight', 'Build', 'BarterContexts') }
    'BarterFightRoute' { @('Preflight', 'Build', 'BarterFightRoute') }
    'BarterSafePassage' { @('Preflight', 'Build', 'BarterSafePassage') }
    'MissionInteraction' { @('Preflight', 'Build', 'MissionInteraction') }
    'ArenaMasterInteraction' { @('Preflight', 'Build', 'ArenaMasterInteraction') }
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
    'SettlementOverlayQuickTalkIssueGateProbe' { @('Preflight', 'Build', 'SettlementOverlayQuickTalkIssueGateProbe') }
    'MapSettlementTargets' { @('Preflight', 'Build', 'MapSettlementTargets') }
    'VisualCapture' { @('Preflight', 'Build', 'VisualCapture') }
    'All' { @('Docs', 'Preflight', 'Api', 'Build', 'Smoke', 'Campaign', 'Protocol', 'AgentLoop', 'TimeControlLoop', 'Observation', 'MapNotifications', 'QuickInformation', 'SceneNotification', 'MissionLeave', 'MainHeroSkills', 'CharacterDevelopment', 'SpendSkillFocus', 'QuestJournal', 'PartyRoster', 'MapPartyTargets', 'MapPartyComposition', 'MapArmyComposition', 'MapPartyBehavior', 'PartyUpgrade', 'PartyPrisonerRecruitment', 'PrisonerRansomSale', 'PartyRoles', 'InventoryNavigation', 'EquipmentTransactions', 'TradeTransactions', 'BarterTransactions', 'BarterContexts', 'MissionInteraction', 'CompanionHiring', 'MapSettlementTargets', 'Movement', 'Hold', 'MoveToPoint', 'Recruitment', 'Rest', 'Pursuit', 'Conversation', 'QuestAcceptance', 'BattleFixture', 'PostBattle', 'TavernMission', 'TownCenterMission', 'SettlementOverlayConversation', 'SettlementOverlayQuickTalk', 'SettlementOverlayQuestGate', 'MarketProbe', 'VillageMarketProbe', 'BattleLootSale') }
}
if (@($requestedStages).Count -eq 0) { throw "Harness phase '$Phase' has no mapped stages; refusing to report a vacuous pass." }

foreach ($stage in $requestedStages) {
    $stageScriptPath = Join-Path $stagesRoot "$stage.ps1"
    if (-not (Test-Path -LiteralPath $stageScriptPath -PathType Leaf)) { throw "Harness stage '$stage' has no dispatch script: $stageScriptPath" }
    $stageResult = . $stageScriptPath
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

try {
    $retentionOutput = & $HarnessPowerShell -NoProfile -File $testResultsRetentionScript -EvidenceRoot $evidenceRoot -CurrentRunId $runId -Apply 2>&1 | Out-String
    $retentionExitCode = $LASTEXITCODE
    if ($retentionExitCode -ne 0) { throw "Prune-TestResults exited ${retentionExitCode}: $retentionOutput" }
    $retention = $retentionOutput | ConvertFrom-Json
    $retentionReceiptPath = Join-Path $runDirectory 'TestResultsRetention.json'
    $retention | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $retentionReceiptPath -Encoding UTF8
    $summary['TestResultsRetention'] = [ordered]@{
        Passed = [bool]$retention.Passed
        Complete = [bool]$retention.Complete
        KeepMostRecentRuns = [int]$retention.KeepMostRecentRuns
        KeepMostRecentContactSheets = [int]$retention.KeepMostRecentContactSheets
        ProtectedDocumentRunCount = [int]$retention.ProtectedDocumentRunCount
        PreservedIncompleteCaptureRunCount = @($retention.PreservedIncompleteCaptureRuns).Count
        DeletedRunCount = [int]$retention.DeletedRunCount
        DeletedFileCount = [int]$retention.DeletedFileCount
        DeletedBytes = [long]$retention.DeletedBytes
        DeletedIndexedVideoCount = [int]$retention.DeletedIndexedVideoCount
        DeletedIndexedVideoBytes = [long]$retention.DeletedIndexedVideoBytes
        DeletedUndecodableVideoCount = [int]$retention.DeletedUndecodableVideoCount
        DeletedUndecodableVideoBytes = [long]$retention.DeletedUndecodableVideoBytes
        DeletedLegacyProbeCount = [int]$retention.DeletedLegacyProbeCount
        DeletedLegacyProbeBytes = [long]$retention.DeletedLegacyProbeBytes
        CompactedMediaCount = [int]$retention.CompactedMediaCount
        CompactedMediaBytes = [long]$retention.CompactedMediaBytes
        SkippedRunCount = @($retention.SkippedRuns).Count
        Receipt = $retentionReceiptPath
    }
} catch {
    $summary['TestResultsRetention'] = [ordered]@{ Passed = $false; Error = $_.Exception.Message }
}

$summary | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $runDirectory 'summary.json') -Encoding UTF8
$summary | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $evidenceRoot 'latest.json') -Encoding UTF8
$summary | ConvertTo-Json -Depth 5

if (-not $summary.Passed) {
    exit 1
}
