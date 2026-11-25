#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('Docs', 'Preflight', 'ConfiguredModelPreflight', 'Api', 'Build', 'Smoke', 'ReleasePackage', 'Campaign', 'CampaignActorThinkTrace', 'FreshCampaign', 'FreshStoryModeSetup', 'FreshStoryModeModelEvaluation', 'PersistentEycCampaign', 'EycObjectiveCheckpointReadback', 'FreshStoryModeNativeMenuLeaveEvaluation', 'FreshStoryModeNativeInquiryResponseEvaluation', 'FreshCampaignProgression', 'FreshCampaignBaselineMatrix', 'FreshCampaignLiveModelEvaluation', 'FreshCampaignSupplyBaseline', 'FreshCampaignRecruitmentFallback', 'Protocol', 'AgentHostProvider', 'AgentHostProviderHealth', 'AgentHostPackage', 'AgentHostSupplyEvaluation', 'AgentHostCampaignLoopEvaluation', 'AgentHostNativeMapMovementMonitorProbe', 'AgentHostVillageToolsQuestEvaluation', 'AgentHostEstablishClanGoalPlannerEvaluation', 'AgentHostEstablishClanAutonomyEvaluation', 'AgentHostCaptivityRecoveryEvaluation', 'AgentHostEstablishClanGoldSaleEvaluation', 'AgentHostBattleSimulationEvaluation', 'AgentHostBattleAndCaptivityEvaluation', 'AgentHostLifecycleEvaluation', 'AgentHostLifecycleCompletionEvaluation', 'AgentLoop', 'LiveModel', 'LiveModelArrival', 'LiveModelRecruitment', 'LiveModelSafePassageRecruitment', 'LiveModelRecruitmentEvaluation', 'LiveModelSupplyEvaluation', 'CheckpointPersistence', 'LiveModelResume', 'LiveModelRuntimeResume', 'LiveModelActionRecovery', 'CheckpointValidation', 'RecruitmentBaseline', 'MultiDaySupplyBaseline', 'TimeControlLoop', 'BattleMissionFormationProbe', 'BattleMissionInputIsolationProbe', 'BattleMissionControllerProbe', 'BattleMissionRtsCameraProbe', 'BattleMissionMovementInputProbe', 'BattleMissionAgentNavigatorProbe', 'BattleMissionNativeAiHandoffProbe', 'BattleMissionHostNativeAiAutopilotProbe', 'BattleFixture', 'PostBattle', 'Observation', 'CaptivityObservation', 'CaptivityOutcome', 'EncounterSurrender', 'EncounterEscape', 'JoinEncounterDefenders', 'JoinEncounterEligibility', 'JoinEncounterAbandonArmy', 'MovingArmyJoin', 'JoinSiegeEvent', 'MapNotifications', 'MapIncidentInputGuard', 'QuickInformation', 'SceneNotification', 'MissionLeave', 'VillageToolsDelivery', 'MainHeroSkills', 'CharacterDevelopment', 'SpendSkillFocus', 'QuestJournal', 'PartyRoster', 'MapPartyTargets', 'MapPartyQuestMarkers', 'MapPartyQuestAcceptance', 'MapEscapeMenu', 'MapInquiry', 'AlleyLeaderInquiry', 'AlleyRosterManagement', 'AlleyAbandonment', 'AlleyEntryMenu', 'MissionSceneNavigation', 'AlleyVolunteerBranches', 'AlleyAttackYield', 'AlleyAttackFightMission', 'PersuasionDetails', 'MapPartyComposition', 'MapArmyComposition', 'MapPartyBehavior', 'PartyUpgrade', 'PartyPrisonerRecruitment', 'PartyRoles', 'InventoryNavigation', 'EquipmentTransactions', 'TradeTransactions', 'BarterTransactions', 'BarterContexts', 'BarterFightRoute', 'MissionInteraction', 'ArenaMasterInteraction', 'CompanionHiring', 'MapSettlementTargets', 'Movement', 'Hold', 'MoveToPoint', 'Recruitment', 'Rest', 'Pursuit', 'EngageVisibility', 'Conversation', 'QuestAcceptance', 'EscortVisibility', 'TavernMission', 'TownCenterMission', 'SettlementOverlayConversation', 'SettlementOverlayQuickTalk', 'SettlementOverlayQuestAcceptance', 'SettlementOverlayQuestGate', 'SettlementOverlayQuickTalkIssueGateProbe', 'VisualCapture', 'All')]
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
    [ValidateRange(1,10)][int]$NativeMapMovementProbeWaitSeconds = 8
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'HarnessPaths.ps1')
$layout = Get-HarnessLayout -HarnessRoot $PSScriptRoot
$stageRoot = [string]$layout.StageRoot
$agentHostRoot = [string]$layout.AgentHostRoot
$modRoot = [string]$layout.ModRoot
$docsRoot = [string]$layout.DocsRoot

$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$startupEvidenceScript = Join-Path $PSScriptRoot 'HarnessStartupEvidence.ps1'
. $startupEvidenceScript
$researchReadinessScript = Join-Path $PSScriptRoot 'HarnessResearchReadiness.ps1'
. $researchReadinessScript
$HarnessContractVersion = '7.679'
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
$harnessRoot = $PSScriptRoot
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
$sourceManifestPath = Join-Path $repositoryRoot 'Modules\ChronicleFramework\SubModule.xml'
$gameExe = Join-Path $gameRoot 'bin\Win64_Shipping_Client\Bannerlord.exe'
$projectPath = Join-Path $modRoot 'ChronicleFramework.csproj'
$agentHostProjectPath = Join-Path $agentHostRoot 'ChronicleAgentHost.csproj'
$agentHostDllPath = Join-Path $agentHostRoot 'bin\Release\net8.0\ChronicleAgentHost.dll'
$agentHostMovementProbeScript = Join-Path $stageRoot 'Test-AgentHostNativeMapMovementMonitorProbe.ps1'
$apiScript = Join-Path (Split-Path -Parent $harnessRoot) 'ApiProbe\Inspect-CampaignApi.ps1'
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
    'All' { @('Docs', 'Preflight', 'Api', 'Build', 'Smoke', 'Campaign', 'Protocol', 'AgentLoop', 'TimeControlLoop', 'Observation', 'MapNotifications', 'QuickInformation', 'SceneNotification', 'MissionLeave', 'MainHeroSkills', 'CharacterDevelopment', 'SpendSkillFocus', 'QuestJournal', 'PartyRoster', 'MapPartyTargets', 'MapPartyComposition', 'MapArmyComposition', 'MapPartyBehavior', 'PartyUpgrade', 'PartyPrisonerRecruitment', 'PartyRoles', 'InventoryNavigation', 'EquipmentTransactions', 'TradeTransactions', 'BarterTransactions', 'BarterContexts', 'MissionInteraction', 'CompanionHiring', 'MapSettlementTargets', 'Movement', 'Hold', 'MoveToPoint', 'Recruitment', 'Rest', 'Pursuit', 'Conversation', 'QuestAcceptance', 'BattleFixture', 'PostBattle', 'TavernMission', 'TownCenterMission', 'SettlementOverlayConversation', 'SettlementOverlayQuickTalk', 'SettlementOverlayQuestGate') }
}
if (@($requestedStages).Count -eq 0) { throw "Harness phase '$Phase' has no mapped stages; refusing to report a vacuous pass." }

foreach ($stage in $requestedStages) {
    $stageResult = switch ($stage) {
        'Docs' {
            Invoke-Stage -Name 'Docs' -Action {
                & $HarnessPowerShell -NoProfile -File $docsScript
                if ($LASTEXITCODE -ne 0) { throw "Documentation check failed with exit code $LASTEXITCODE." }
                & $HarnessPowerShell -NoProfile -File $contextPackScript
                if ($LASTEXITCODE -ne 0) { throw "Context pack failed with exit code $LASTEXITCODE." }
            }
        }
        'Preflight' {
            Invoke-Stage -Name 'Preflight' -Action {
                if (-not (Test-Path $gameExe)) { throw "Game executable not found: $gameExe" }
                $targetGameBranch = 'v1.4.8'
                $gameBranch = Assert-ChronicleSteamGameBranch -GameRoot $gameRoot -RequiredBranch $targetGameBranch
                if (-not (Test-Path $projectPath)) { throw "Project not found: $projectPath" }
                if (-not (Test-Path $manifestPath)) { throw "Manifest not found: $manifestPath" }
                if (-not (Test-Path $sourceManifestPath)) { throw "Version-controlled manifest not found: $sourceManifestPath" }
                if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { throw 'dotnet was not found on PATH.' }
                if (-not (Get-Command ilspycmd -ErrorAction SilentlyContinue)) { throw 'ilspycmd was not found on PATH.' }
                $templateList = dotnet new list 2>&1 | Out-String
                if ($templateList -notmatch 'blmodfx') { throw 'Bannerlord.Templates blmodfx template was not found.' }
                & $HarnessPowerShell -NoProfile -File $saveModuleMetadataTestScript
                if ($LASTEXITCODE -ne 0) { throw "Save module metadata test failed with exit code $LASTEXITCODE." }
                [xml]$manifest = Get-Content $sourceManifestPath
                if ([string]$manifest.Module.Id.value -ne 'ChronicleFramework') { throw 'Unexpected module id.' }
                $dependencies = @($manifest.Module.DependedModules.DependedModule | ForEach-Object { [string]$_.Id })
                foreach ($dependency in @('Bannerlord.Harmony','Bannerlord.ButterLib','Bannerlord.UIExtenderEx','Bannerlord.MBOptionScreen','Native','SandBoxCore','SandBox')) {
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
                    TargetGameBranch = $gameBranch.Branch
                    SteamBuildId = $gameBranch.BuildId
                    SteamManifest = $gameBranch.ManifestPath
                    GameFileVersion = $gameFileVersion
                    CompileChangeset = $compileChangeset
                    Manifest = $manifestPath
                    SourceManifest = $sourceManifestPath
                    RuntimeManifestMatchesSource = ((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $sourceManifestPath -Algorithm SHA256).Hash)
                    ModuleVersion = [string]$manifest.Module.Version.value
                    ModuleSet = $moduleVersions
                    Toolchain = @('dotnet', 'ilspycmd', 'Bannerlord.Templates:blmodfx')
                    PackageInfoHint = $packageInfoText
                } | ConvertTo-Json -Depth 8
            }
        }
        'ConfiguredModelPreflight' {
            Invoke-Stage -Name 'ConfiguredModelPreflight' -Action {
                $savedLlmModel = [Environment]::GetEnvironmentVariable('CHRONICLE_LLM_MODEL', 'Process')
                try {
                    [Environment]::SetEnvironmentVariable('CHRONICLE_LLM_MODEL', $FreshStoryModeModel, 'Process')
                    . (Join-Path $stageRoot 'Get-FreeLLMAPIProfile.ps1')
                    $providerBaseUrl = [string][Environment]::GetEnvironmentVariable('CHRONICLE_LLM_BASE_URL', 'Process')
                    if ([string]::IsNullOrWhiteSpace($providerBaseUrl)) { $providerBaseUrl = [string][Environment]::GetEnvironmentVariable('CHRONICLE_LLM_BASE_URL', 'User') }
                    $providerProtocol = [string][Environment]::GetEnvironmentVariable('CHRONICLE_LLM_PROTOCOL', 'Process')
                    if ([string]::IsNullOrWhiteSpace($providerProtocol)) { $providerProtocol = [string][Environment]::GetEnvironmentVariable('CHRONICLE_LLM_PROTOCOL', 'User') }
                    if ([string]::IsNullOrWhiteSpace($providerProtocol)) { $providerProtocol = 'openai-compatible' }
                    $endpoint = $null
                    if ($providerProtocol -cne 'openai-compatible' -or -not [Uri]::TryCreate($providerBaseUrl, [UriKind]::Absolute, [ref]$endpoint) -or
                        -not [string]::IsNullOrWhiteSpace($endpoint.Query) -or -not [string]::IsNullOrWhiteSpace($endpoint.UserInfo) -or
                        -not [string]::IsNullOrWhiteSpace($endpoint.Fragment)) {
                        throw 'The selected model provider endpoint is not a safe absolute OpenAI-compatible URL; no inference request was sent.'
                    }

                    $isFreeLlmApiEndpoint = $endpoint.IsLoopback -and $endpoint.Port -eq 31415 -and $endpoint.AbsolutePath.TrimEnd('/') -eq '/v1'
                    if ($isFreeLlmApiEndpoint) {
                        $profile = Initialize-FreeLLMAPIProfile
                        [ordered]@{
                            ProviderKind = 'FreeLLMAPI'
                            ProviderHost = $endpoint.Host
                            ModelId = $profile.RequestedModelId
                            ExecutionStatus = $profile.ModelExecutionStatus
                            AvailableModelCount = $profile.AvailableModelCount
                            CatalogSha256 = $profile.AvailableModelCatalogSha256
                            InferenceRequests = 0
                            BannerlordStarted = $false
                            GatewayStartedByHarness = [bool]$profile.GatewayStartedByHarness
                        } | ConvertTo-Json -Depth 4
                        return
                    }

                    $isDshWorkBuddyEndpoint = $endpoint.IsLoopback -and $endpoint.Port -eq 8328 -and $endpoint.AbsolutePath.TrimEnd('/') -eq '/v1'
                    if ($isDshWorkBuddyEndpoint) {
                        if (-not $AllowDshWorkBuddyGateway -or $FreshStoryModeModel -notmatch '^buddy:hy4flash(?:-free)?$') {
                            throw 'The DSH WorkBuddy route requires explicit opt-in to the listed buddy:hy4flash or buddy:hy4flash-free model; no inference request was sent.'
                        }
                        $credential = Get-ChronicleProviderCredential -Endpoint $endpoint
                        if ([string]::IsNullOrWhiteSpace([string]$credential.Value)) { throw 'The dedicated DSH WorkBuddy gateway credential is unavailable; no inference request was sent.' }
                        $modelsUri = [UriBuilder]::new($endpoint)
                        $modelsUri.Path = '/v1/models'
                        $modelsUri.Query = ''
                        try { $catalog = Invoke-RestMethod -Uri $modelsUri.Uri -Headers @{ Authorization = "Bearer $($credential.Value)" } -TimeoutSec 12 }
                        catch { throw 'The DSH WorkBuddy model-list preflight failed; no inference request was sent.' }
                        $modelRows = @($catalog.data)
                        if (@($modelRows | Where-Object { [string]$_.id -ceq $FreshStoryModeModel }).Count -ne 1) {
                            throw 'The selected direct DSH WorkBuddy model is absent from the current gateway catalog; no inference request was sent.'
                        }
                        $dshHome = [string][Environment]::GetEnvironmentVariable('DSH_HOME', 'Process')
                        if ([string]::IsNullOrWhiteSpace($dshHome)) { $dshHome = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)) '.dsh' }
                        $dshStatusKeyPath = Join-Path $dshHome 'openai-gateway/api-key'
                        $dshStatusKey = if (Test-Path -LiteralPath $dshStatusKeyPath -PathType Leaf) { [string](Get-Content -LiteralPath $dshStatusKeyPath -Raw).Trim() } else { $null }
                        if ([string]::IsNullOrWhiteSpace($dshStatusKey)) { throw 'The local DSH status credential is unavailable; no inference request was sent.' }
                        try { $dshStatus = Invoke-RestMethod -Uri 'http://127.0.0.1:2733/plugins/dsh-xdpool/status' -Headers @{ Authorization = "Bearer $dshStatusKey" } -TimeoutSec 8 }
                        catch { throw 'The read-only DSH WorkBuddy model-status check failed; no inference request was sent.' }
                        $bareWorkBuddyModelId = $FreshStoryModeModel.Substring('buddy:'.Length)
                        $workBuddyModel = @($dshStatus.models | Where-Object { [string]$_.id -ceq $bareWorkBuddyModelId } | Select-Object -First 1)
                        if ($workBuddyModel.Count -ne 1 -or $null -eq $workBuddyModel[0].multiplier -or [double]$workBuddyModel[0].multiplier -lt 0) {
                            throw 'The selected DSH WorkBuddy model has no current credit-multiplier record; no inference request was sent.'
                        }
                        $usableWorkBuddyAccounts = @($dshStatus.accounts | Where-Object {
                            -not [bool]$_.cooling -and $_.credentialDead -ne $true -and
                            (($null -eq $_.credits) -or [double]$_.credits.total -gt 0)
                        })
                        if ($usableWorkBuddyAccounts.Count -eq 0) { throw 'The DSH WorkBuddy account pool has no currently usable account; no inference request was sent.' }
                        [ordered]@{
                            ProviderKind = 'DSH XD Pool WorkBuddy direct loopback gateway'
                            ProviderHost = $endpoint.Host
                            ModelId = $FreshStoryModeModel
                            CatalogListed = $true
                            AvailableModelCount = $modelRows.Count
                            WorkBuddyCreditMultiplier = [double]$workBuddyModel[0].multiplier
                            WorkBuddyModelTags = @($workBuddyModel[0].tags)
                            WorkBuddyCreditReceiptAvailable = $true
                            CurrencyPriceReceiptAvailable = $false
                            UsableAccountCount = $usableWorkBuddyAccounts.Count
                            InferenceRequests = 0
                            BannerlordStarted = $false
                            AutomaticFallbackEnabled = $false
                        } | ConvertTo-Json -Depth 4
                        return
                    }

                    $isDshXdPoolFreeEndpoint = $endpoint.IsLoopback -and $endpoint.Port -eq 8326 -and $endpoint.AbsolutePath.TrimEnd('/') -eq '/v1'
                    if ($isDshXdPoolFreeEndpoint) {
                        $isDshXdPoolWorkBuddyFreeModel = $FreshStoryModeModel -ceq 'xdpool/hy4flash-free'
                        $isDirectDshFreeModel = ($FreshStoryModeModel -match '^xdpool-aggregate/(?!combo:)[^\r\n]+:free$' -and
                            $FreshStoryModeModel -notmatch '(?i)(combo:|fallback|fusion|auto:)') -or $isDshXdPoolWorkBuddyFreeModel
                        if (-not $AllowDshXdPoolFreeRoute -or -not $isDirectDshFreeModel) {
                            throw 'DSH campaign preflight requires explicit opt-in to one direct free XD Pool model; combinations/fallbacks are blocked and no inference request was sent.'
                        }
                        $credential = Get-ChronicleProviderCredential -Endpoint $endpoint
                        if ([string]::IsNullOrWhiteSpace([string]$credential.Value)) { throw 'The DSH OpenAI-compatible gateway credential is unavailable; no inference request was sent.' }
                        if ($isDshXdPoolWorkBuddyFreeModel) {
                            $dshFreeModelStatus = Get-DshXdPoolFreeModelStatus -ModelId $FreshStoryModeModel -Region 'cn'
                            if (-not $dshFreeModelStatus.ReadyForBoundedInference) {
                                throw 'The DSH XD Pool model is disabled or lacks its verified zero-multiplier free tag; no inference request was sent.'
                            }
                            $modelsUri = [UriBuilder]::new($endpoint)
                            $modelsUri.Path = $endpoint.AbsolutePath.TrimEnd('/') + '/models'
                            $modelsUri.Query = ''
                            try { $catalog = Invoke-RestMethod -Uri $modelsUri.Uri -Headers @{ Authorization = "Bearer $($credential.Value)" } -TimeoutSec 12 }
                            catch { throw 'The DSH loopback model-list preflight failed; no inference request was sent.' }
                            $modelRows = @($catalog.data)
                            $modelListed = @($modelRows | Where-Object { [string]$_.id -ceq $FreshStoryModeModel }).Count -gt 0
                            if (-not $modelListed) { throw 'The selected DSH XD Pool WorkBuddy free model is absent from the current gateway catalog; no inference request was sent.' }
                            [ordered]@{
                                ProviderKind = 'DSH XD Pool WorkBuddy limited-time free model'
                                ProviderHost = $endpoint.Host
                                ModelId = $FreshStoryModeModel
                                CatalogListed = $true
                                AvailableModelCount = $modelRows.Count
                                PoolMultiplier = $dshFreeModelStatus.Multiplier
                                FreePromotionTagVerified = $dshFreeModelStatus.HasFreePromotionTag
                                CurrencyPriceReceiptAvailable = $false
                                InferenceRequests = 0
                                BannerlordStarted = $false
                                AutomaticFallbackEnabled = $false
                            } | ConvertTo-Json -Depth 4
                            return
                        }
                        $modelRouteMatch = [regex]::Match($FreshStoryModeModel, '^xdpool-aggregate/([^/]+)/(.+)$')
                        if (-not $modelRouteMatch.Success) { throw 'The direct DSH model ID did not contain a provider segment; no inference request was sent.' }
                        $dshProviderId = $modelRouteMatch.Groups[1].Value
                        $dshProviderModelId = $modelRouteMatch.Groups[2].Value
                        $aggregateUri = [Uri]::new('http://127.0.0.1:2733/plugins/dsh-xdpool/aggregate')
                        try { $aggregateStatus = Invoke-RestMethod -Uri $aggregateUri -Headers @{ Authorization = "Bearer $($credential.Value)" } -TimeoutSec 8 }
                        catch { throw 'The DSH aggregate status preflight failed; no inference request was sent.' }
                        $aggregateProvider = @($aggregateStatus.providers | Where-Object { [string]$_.id -ceq $dshProviderId } | Select-Object -First 1)
                        if ($aggregateProvider.Count -ne 1 -or -not [bool]$aggregateProvider[0].enabled -or
                            -not [bool]$aggregateProvider[0].configured -or
                            @($aggregateProvider[0].models | Where-Object { [string]$_ -ceq $dshProviderModelId }).Count -ne 1) {
                            throw 'The selected direct DSH free model provider is disabled, unconfigured, or absent from its selected model set; no inference request was sent.'
                        }
                        if ($dshProviderId -cne 'open_router') {
                            throw 'No current authoritative price verifier is configured for this DSH upstream provider; no inference request was sent.'
                        }
                        $openRouterPriceReceipt = Get-OpenRouterZeroPriceReceipt -ModelId $dshProviderModelId
                        $modelsUri = [UriBuilder]::new($endpoint)
                        $modelsUri.Path = $endpoint.AbsolutePath.TrimEnd('/') + '/models'
                        $modelsUri.Query = ''
                        try { $catalog = Invoke-RestMethod -Uri $modelsUri.Uri -Headers @{ Authorization = "Bearer $($credential.Value)" } -TimeoutSec 12 }
                        catch { throw 'The DSH loopback model-list preflight failed; no inference request was sent.' }
                        $modelRows = @($catalog.data)
                        $modelListed = @($modelRows | Where-Object { [string]$_.id -ceq $FreshStoryModeModel }).Count -gt 0
                        if (-not $modelListed) { throw 'The selected direct free DSH model is absent from the current gateway catalog; no inference request was sent.' }
                        [ordered]@{
                            ProviderKind = 'DSH XD Pool direct free-labeled model'
                            ProviderHost = $endpoint.Host
                            ModelId = $FreshStoryModeModel
                            CatalogListed = $true
                            AvailableModelCount = $modelRows.Count
                            ModelPriceReceiptAvailable = $true
                            PriceReceipt = $openRouterPriceReceipt
                            InferenceRequests = 0
                            BannerlordStarted = $false
                            AutomaticFallbackEnabled = $false
                        } | ConvertTo-Json -Depth 4
                        return
                    }

                    if ($endpoint.Scheme -cne 'https') { throw 'Remote model preflight requires HTTPS; no inference request was sent.' }
                    $credential = Get-ChronicleProviderCredential -Endpoint $endpoint
                    if ([string]::IsNullOrWhiteSpace([string]$credential.Value)) { throw 'The configured remote model API key is unavailable; no inference request was sent.' }
                    $modelsUri = [UriBuilder]::new($endpoint)
                    $modelsUri.Path = $endpoint.AbsolutePath.TrimEnd('/') + '/models'
                    $modelsUri.Query = ''
                    try { $catalog = Invoke-RestMethod -Uri $modelsUri.Uri -Headers @{ Authorization = "Bearer $($credential.Value)" } -TimeoutSec 12 }
                    catch { throw 'The configured remote provider read-only model-list preflight failed; no inference request was sent.' }
                    $modelRows = @($catalog.data)
                    $modelListed = @($modelRows | Where-Object { [string]$_.id -ceq $FreshStoryModeModel }).Count -gt 0
                    if (-not $modelListed) { throw 'The selected model is absent from the configured remote provider catalog; no inference request was sent.' }
                    [ordered]@{
                        ProviderKind = 'direct-remote-openai-compatible'
                        ProviderHost = $endpoint.Host
                        ModelId = $FreshStoryModeModel
                        ExecutionStatus = 'ready'
                        AvailableModelCount = $modelRows.Count
                        InferenceRequests = 0
                        BannerlordStarted = $false
                        FreeLLMAPIStartedByHarness = $false
                    } | ConvertTo-Json -Depth 4
                }
                finally {
                    [Environment]::SetEnvironmentVariable('CHRONICLE_LLM_MODEL', $savedLlmModel, 'Process')
                }
            }
        }
        'Api' {
            Invoke-Stage -Name 'Api' -Action {
                & $HarnessPowerShell -NoProfile -File $apiScript -Scope Lifecycle
                if ($LASTEXITCODE -ne 0) { throw "API lifecycle stage failed with exit code $LASTEXITCODE." }
                & $HarnessPowerShell -NoProfile -File $apiScript -Scope Events
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
                $mainlinePath = Join-Path $docsRoot 'Focus\MAINLINE.md'
                $mainlineText = Get-Content -LiteralPath $mainlinePath -Raw -Encoding UTF8
                $researchGateReady = $mainlineText -match '(?m)^Research Gate: \*\*READY\*\*\s*$'
                $implementationGateReady = $mainlineText -match '(?m)^Implementation Gate: \*\*READY\*\*\s*$'
                $moduleDll = Join-Path $gameRoot 'Modules\ChronicleFramework\bin\Win64_Shipping_Client\ChronicleFramework.dll'
                $sourceFiles = @(Get-ChildItem -LiteralPath $modRoot -File -Filter '*.cs')
                $changedFeatureSources = if (Test-Path -LiteralPath $moduleDll) {
                    @($sourceFiles | Where-Object { $_.LastWriteTimeUtc -gt (Get-Item -LiteralPath $moduleDll).LastWriteTimeUtc })
                } else { $sourceFiles }
                $subModuleSource = Join-Path $modRoot 'SubModule.cs'
                $diagnosticSourceHash = if (Test-Path -LiteralPath $subModuleSource) { Get-ChronicleCanonicalFileSha256 -LiteralPath $subModuleSource } else { '' }
                $readiness = Get-ChronicleResearchReadiness -ResearchReady $researchGateReady -ImplementationReady $implementationGateReady -ChangedFeatureSources @($changedFeatureSources | ForEach-Object Name) -AuditedHarnessDiagnosticSha256 $diagnosticSourceHash
                if (-not $readiness.Allowed) { throw $readiness.Reason }
                $sourceManifestHash = (Get-FileHash -LiteralPath $sourceManifestPath -Algorithm SHA256).Hash
                $runtimeManifestHash = if (Test-Path -LiteralPath $manifestPath) { (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash } else { '' }
                if ($sourceManifestHash -ne $runtimeManifestHash) { Copy-Item -LiteralPath $sourceManifestPath -Destination $manifestPath -Force }
                $sourceModuleData = Join-Path $repositoryRoot 'Modules\ChronicleFramework\ModuleData'
                $runtimeModuleData = Join-Path (Split-Path -Parent $manifestPath) 'ModuleData'
                if (-not (Test-Path -LiteralPath $sourceModuleData -PathType Container)) { throw 'Chronicle ModuleData source is missing.' }
                New-Item -ItemType Directory -Path $runtimeModuleData -Force | Out-Null
                foreach ($moduleDataEntry in Get-ChildItem -LiteralPath $sourceModuleData -Force) {
                    Copy-Item -LiteralPath $moduleDataEntry.FullName -Destination $runtimeModuleData -Recurse -Force
                }
                $modAssetsPath = Join-Path (Split-Path -Parent $projectPath) 'obj\project.assets.json'
                if (-not (Test-Path -LiteralPath $modAssetsPath)) {
                    $modRestoreOutput = & dotnet restore $projectPath "-p:ChronicleGameRoot=$gameRoot" 2>&1 | Out-String
                    if ($LASTEXITCODE -ne 0) { throw "Mod project restore failed with exit code $LASTEXITCODE." + [char]10 + $modRestoreOutput }
                }
                $buildOutput = & dotnet build $projectPath --configuration Release --no-restore "-p:ChronicleGameRoot=$gameRoot" 2>&1 | Out-String
                $buildExitCode = $LASTEXITCODE
                if ($buildExitCode -ne 0) { throw "Build failed with exit code $buildExitCode.`n$buildOutput" }
                $agentHostBuildOutput = & dotnet build $agentHostProjectPath --configuration Release 2>&1 | Out-String
                $agentHostBuildExitCode = $LASTEXITCODE
                $agentHostNuGetAuditFallbackUsed = $false
                if ($agentHostBuildExitCode -ne 0 -and $agentHostBuildOutput -match 'NU1900') {
                    $agentHostProjectDirectory = Split-Path -Parent $agentHostProjectPath
                    $agentHostProjectXml = [xml](Get-Content -LiteralPath $agentHostProjectPath -Raw -Encoding UTF8)
                    $agentHostPackageReferences = @($agentHostProjectXml.SelectNodes('//PackageReference'))
                    $agentHostPackageLockPath = Join-Path $agentHostProjectDirectory 'packages.lock.json'
                    $pinnedHostPackage = ($agentHostPackageReferences.Count -eq 1 -and
                        $agentHostPackageReferences[0].GetAttribute('Include') -ceq 'Microsoft.ML.Tokenizers' -and
                        $agentHostPackageReferences[0].GetAttribute('Version') -ceq '[2.0.1]' -and
                        (Test-Path -LiteralPath $agentHostPackageLockPath -PathType Leaf))
                    if (-not $pinnedHostPackage) {
                        throw "NuGet vulnerability feed returned NU1900; the offline audit fallback is allowed only for the single locked Microsoft.ML.Tokenizers 2.0.1 Host dependency. $agentHostBuildOutput"
                    }
                    $fallbackRestoreOutput = & dotnet restore $agentHostProjectPath --locked-mode -p:NuGetAudit=false 2>&1 | Out-String
                    $fallbackRestoreExitCode = $LASTEXITCODE
                    if ($fallbackRestoreExitCode -ne 0) { throw "NuGet audit metadata was unavailable and locked local dependency restore failed (exit=$fallbackRestoreExitCode).`n$fallbackRestoreOutput" }
                    $fallbackHostBuildOutput = & dotnet build $agentHostProjectPath --configuration Release --no-restore 2>&1 | Out-String
                    $agentHostBuildExitCode = $LASTEXITCODE
                    $agentHostBuildOutput = "Initial Host build could not reach the vulnerability feed (NU1900); the project has one pinned lockfile dependency, so restore retried in locked mode without the unavailable audit endpoint.`n$fallbackRestoreOutput`nHost build after locked restore:`n$fallbackHostBuildOutput"
                    $agentHostNuGetAuditFallbackUsed = $true
                }
                if ($agentHostBuildExitCode -ne 0) { throw "Local Agent Host build failed with exit code $agentHostBuildExitCode.`n$agentHostBuildOutput" }
                [ordered]@{ gameModBuild = $buildOutput; localAgentHostBuild = $agentHostBuildOutput; nugetAuditFallbackUsed = $agentHostNuGetAuditFallbackUsed } | ConvertTo-Json -Depth 4
            }
        }
        'AgentHostProbeBuild' {
            Invoke-Stage -Name 'AgentHostProbeBuild' -Action {
                $probeBuildOutput = & dotnet build $agentHostProjectPath --configuration Release --no-restore 2>&1 | Out-String
                if ($LASTEXITCODE -ne 0) { throw "Agent Host-only probe build failed with exit code $LASTEXITCODE.`n$probeBuildOutput" }
                $probeBuildOutput
            }
        }
        'NativeMapMovementMonitorProbe' {
            Invoke-Stage -Name 'NativeMapMovementMonitorProbe' -Action {
                $probeOutput = & $HarnessPowerShell -NoProfile -File $agentHostMovementProbeScript -WaitSeconds $NativeMapMovementProbeWaitSeconds 2>&1 | Out-String
                if ($LASTEXITCODE -ne 0) { throw "Live Native map-movement monitor probe failed with exit code $LASTEXITCODE.`n$probeOutput" }
                $probeOutput
            }
        }
        'Smoke' {
            Invoke-Stage -Name 'Smoke' -Action {
                $priorHarnessMode = $env:CHRONICLE_HARNESS_MODE
                $env:CHRONICLE_HARNESS_MODE = 'smoke'
                try {
                    $smokeStdout = Join-Path $harnessTempDirectory 'SmokeWorker.stdout.log'
                    $smokeStderr = Join-Path $harnessTempDirectory 'SmokeWorker.stderr.log'
                    $smokeWorker = Start-Process -FilePath $HarnessPowerShell -ArgumentList @('-NoProfile','-File',('"' + $smokeScript + '"'),'-TimeoutSeconds',$effectiveSmokeTimeoutSeconds,'-StabilitySeconds',$SmokeStabilitySeconds) -WindowStyle Hidden -RedirectStandardOutput $smokeStdout -RedirectStandardError $smokeStderr -PassThru
                    try {
                        if (-not $smokeWorker.WaitForExit(($effectiveSmokeTimeoutSeconds + $SmokeStabilitySeconds + 30) * 1000)) {
                            $ownedGameExe = [IO.Path]::GetFullPath((Join-Path $gameRoot 'bin\Win64_Shipping_Client\Bannerlord.exe'))
                            $ownedChildren = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$($smokeWorker.Id)")
                            foreach ($ownedChild in $ownedChildren) {
                                if ($ownedChild.ExecutablePath -and [IO.Path]::GetFullPath($ownedChild.ExecutablePath) -eq $ownedGameExe) {
                                    Stop-Process -Id $ownedChild.ProcessId -Force -ErrorAction SilentlyContinue
                                }
                            }
                            $smokeWorker.Kill()
                            $smokeWorker.WaitForExit()
                            throw "Smoke worker exceeded its startup/stability/receipt deadline; worker logs and receipt-stage markers are retained in $harnessTempDirectory."
                        }
                        # A redirected worker that runs for minutes can exit without publishing an exit code on the Process object, so the receipt gate below decides the stage; the exit code is only an additional failure signal.
                        $smokeWorker.WaitForExit()
                        try { $smokeExitCode = $smokeWorker.ExitCode } catch { $smokeExitCode = $null }
                    }
                    finally { $smokeWorker.Dispose() }
                    $smokeOutput = (Get-Content -LiteralPath $smokeStdout -Raw) + (Get-Content -LiteralPath $smokeStderr -Raw)
                    if ($null -ne $smokeExitCode -and $smokeExitCode -ne 0) { throw "Smoke test failed with exit code $smokeExitCode. Evidence: $smokeOutput" }
                    $smokeReceipt = Get-Content -LiteralPath (Join-Path $harnessTempDirectory 'SmokeResult.json') -Raw -Encoding UTF8 | ConvertFrom-Json
                    foreach ($flagName in @('FinishedAll','AssemblyLoaded','CrashDetected','McmSettingsRegistered','StableAfterFinishedAll','ProcessExitedUnexpectedly')) {
                        if ($smokeReceipt.$flagName -isnot [bool]) { throw "Smoke receipt field '$flagName' must be a Boolean; collection/string truthiness is not verification." }
                    }
                    if ($smokeReceipt.Passed -isnot [bool]) { throw "Smoke receipt field 'Passed' must be a Boolean; the worker has to serialize its own gate verdict." }
                    if (-not $smokeReceipt.Passed) { throw "Smoke worker reported its gate failed: $(@($smokeReceipt.GateFailures) -join ', '). Evidence: $smokeOutput" }
                    if ($null -eq $smokeExitCode) { $smokeOutput += "`nSmoke worker exit code was unavailable; the stage verdict came from the worker receipt (Passed=true)." }
                }
                finally {
                    if ($null -eq $priorHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
                    else { $env:CHRONICLE_HARNESS_MODE = $priorHarnessMode }
                }
                $smokeOutput
            }
        }
        'ReleasePackage' {
            Invoke-Stage -Name 'ReleasePackage' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $agentHostReleasePackageScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Isolated Chronicle release package verification failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'Campaign' {
            Invoke-Stage -Name 'Campaign' -Action {
                & $HarnessPowerShell -NoProfile -File $campaignScript
                if ($LASTEXITCODE -ne 0) { throw "Campaign test failed with exit code $LASTEXITCODE." }
            }
        }
        'FreshCampaign' {
            Invoke-Stage -Name 'FreshCampaign' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $freshCampaignScript 2>&1 | Out-String
                if ($LASTEXITCODE -ne 0) { throw "Fresh campaign character-creation test failed with exit code $LASTEXITCODE. Output: $testOutput" }
                $testOutput
            }
        }
        'FreshStoryModeSetup' {
            Invoke-Stage -Name 'FreshStoryModeSetup' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $freshCampaignScript -StoryModeEycSetup -TimeoutSeconds 360 2>&1 | Out-String
                if ($LASTEXITCODE -ne 0) { throw "Fresh StoryMode/tutorial-skip setup probe failed with exit code $LASTEXITCODE. Output: $testOutput" }
                $testOutput
            }
        }
        'FreshStoryModeNativeMenuLeaveEvaluation' {
            Invoke-Stage -Name 'FreshStoryModeNativeMenuLeaveEvaluation' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $freshCampaignScript -StoryModeEycSetup -StoryModeNativeMenuLeaveEvaluation -TimeoutSeconds 360 2>&1 | Out-String
                if ($LASTEXITCODE -ne 0) { throw "Fresh StoryMode Native training-field Leave handler evaluation failed with exit code $LASTEXITCODE. Output: $testOutput" }
                $testOutput
            }
        }
        'FreshStoryModeNativeInquiryResponseEvaluation' {
            Invoke-Stage -Name 'FreshStoryModeNativeInquiryResponseEvaluation' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $freshCampaignScript -StoryModeEycSetup -StoryModeNativeMenuLeaveEvaluation -StoryModeNativeInquiryResponseEvaluation -TimeoutSeconds 360 2>&1 | Out-String
                if ($LASTEXITCODE -ne 0) { throw "Fresh StoryMode original one-button Native Inquiry response evaluation failed with exit code $LASTEXITCODE. Output: $testOutput" }
                $testOutput
            }
        }
        'FreshStoryModeModelEvaluation' {
            Invoke-Stage -Name 'FreshStoryModeModelEvaluation' -Action {
                $savedHarnessAutoStart = [Environment]::GetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_AUTO_START', 'Process')
                $savedHarnessAutoStop = [Environment]::GetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_AUTO_STOP_AFTER_MS', 'Process')
                $savedHarnessGoal = [Environment]::GetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_GOAL', 'Process')
                $savedHarnessModel = [Environment]::GetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_MODEL', 'Process')
                $savedLlmModel = [Environment]::GetEnvironmentVariable('CHRONICLE_LLM_MODEL', 'Process')
                $providerKeyVariable = 'CHRONICLE_LLM_API_KEY'
                $savedProviderKey = [Environment]::GetEnvironmentVariable($providerKeyVariable, 'Process')
                $savedProviderTimeout = [Environment]::GetEnvironmentVariable('CHRONICLE_LLM_TIMEOUT_SECONDS', 'Process')
                try {
                    $providerCredential = Get-HarnessConfiguredProviderCredential
                    $providerKeyVariable = [string]$providerCredential.EnvironmentVariableName
                    $savedProviderKey = [Environment]::GetEnvironmentVariable($providerKeyVariable, 'Process')
                    [Environment]::SetEnvironmentVariable($providerKeyVariable, [string]$providerCredential.Value, 'Process')
                    [Environment]::SetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_AUTO_START', '1', 'Process')
                    [Environment]::SetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_AUTO_STOP_AFTER_MS', '86400000', 'Process')
                    [Environment]::SetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_GOAL', '自主完成原版主线任务“建立你的家族”。', 'Process')
                    # Pin one explicit provider model/route for reproducibility; catalog presence is not proof of a successful provider call. Never use a local custom route or unbounded auto chain.
                    [Environment]::SetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_MODEL', $FreshStoryModeModel, 'Process')
                    [Environment]::SetEnvironmentVariable('CHRONICLE_LLM_MODEL', $FreshStoryModeModel, 'Process')
                    if ([string]::IsNullOrWhiteSpace($savedProviderTimeout)) { [Environment]::SetEnvironmentVariable('CHRONICLE_LLM_TIMEOUT_SECONDS', '300', 'Process') }
                    $testOutput = & $HarnessPowerShell -NoProfile -File $freshCampaignScript -StoryModeEycSetup -StoryModeEycLiveModelEvaluation -TimeoutSeconds 87000 2>&1 | Out-String
                    if ($LASTEXITCODE -ne 0) { throw "Fresh natural StoryMode bounded real-model evaluation failed with exit code $LASTEXITCODE. Output: $testOutput" }
                    $testOutput
                }
                finally {
                    [Environment]::SetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_AUTO_START', $savedHarnessAutoStart, 'Process')
                    [Environment]::SetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_AUTO_STOP_AFTER_MS', $savedHarnessAutoStop, 'Process')
                    [Environment]::SetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_GOAL', $savedHarnessGoal, 'Process')
                    [Environment]::SetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_MODEL', $savedHarnessModel, 'Process')
                    [Environment]::SetEnvironmentVariable('CHRONICLE_LLM_MODEL', $savedLlmModel, 'Process')
                    [Environment]::SetEnvironmentVariable($providerKeyVariable, $savedProviderKey, 'Process')
                    [Environment]::SetEnvironmentVariable('CHRONICLE_LLM_TIMEOUT_SECONDS', $savedProviderTimeout, 'Process')
                    try {
                        if ($script:retainedAgentHostPackageRoot) { Remove-RetainedAgentHostPackage $script:retainedAgentHostPackageRoot }
                    }
                    finally {
                        $script:retainedAgentHostPackageRoot = $null
                        $script:retainedAgentHostExecutablePath = $null
                        [Environment]::SetEnvironmentVariable('CHRONICLE_AGENT_HOST_TEST_PATH', $previousAgentHostTestPath, 'Process')
                    }
                }
            }
        }
        'PersistentEycCampaign' {
            Invoke-Stage -Name 'PersistentEycCampaign' -Action {
                $savedLlmModel = [Environment]::GetEnvironmentVariable('CHRONICLE_LLM_MODEL', 'Process')
                $savedHarnessModel = [Environment]::GetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_MODEL', 'Process')
                $providerKeyVariable = 'CHRONICLE_LLM_API_KEY'
                $savedProviderKey = [Environment]::GetEnvironmentVariable($providerKeyVariable, 'Process')
                try {
                    $providerCredential = Get-HarnessConfiguredProviderCredential
                    $providerKeyVariable = [string]$providerCredential.EnvironmentVariableName
                    $savedProviderKey = [Environment]::GetEnvironmentVariable($providerKeyVariable, 'Process')
                    [Environment]::SetEnvironmentVariable($providerKeyVariable, [string]$providerCredential.Value, 'Process')
                    [Environment]::SetEnvironmentVariable('CHRONICLE_LLM_MODEL', $FreshStoryModeModel, 'Process')
                    [Environment]::SetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_MODEL', $FreshStoryModeModel, 'Process')
                    $testOutput = & $HarnessPowerShell -NoProfile -File $persistentEycCampaignScript `
                        -HostMaxElapsedSeconds $PersistentEycHostMaxElapsedSeconds `
                        -MaxProviderDecisionsPerContinuation $PersistentEycMaxProviderDecisionsPerContinuation `
                        -MaxHttpRequestsPerDecision $PersistentEycMaxHttpRequestsPerDecision `
                        -CampaignKey $PersistentEycCampaignKey `
                        -StartupTimeoutSeconds 240 -FrameRate 5 2>&1 | Out-String
                    $testExitCode = $LASTEXITCODE
                    if ($testExitCode -ne 0) {
                        throw "Persistent natural StoryMode campaign has not verified original EYC completion (exit=$testExitCode). A Native checkpoint, if verified, remains selected for the next continuation."
                    }
                    $testOutput
                }
                finally {
                    [Environment]::SetEnvironmentVariable('CHRONICLE_LLM_MODEL', $savedLlmModel, 'Process')
                    [Environment]::SetEnvironmentVariable('CHRONICLE_HARNESS_AGENT_MODEL', $savedHarnessModel, 'Process')
                    [Environment]::SetEnvironmentVariable($providerKeyVariable, $savedProviderKey, 'Process')
                }
            }
        }
        'EycObjectiveCheckpointReadback' {
            Invoke-Stage -Name 'EycObjectiveCheckpointReadback' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $eycObjectiveCheckpointReadbackScript `
                    -CampaignKey $PersistentEycCampaignKey -TimeoutSeconds 240 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native EYC objective checkpoint readback failed with exit code $testExitCode.`n$testOutput" }
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
                        $testOutput = & $HarnessPowerShell -NoProfile -File $freshCampaignScript -ValidateRecruitmentProgression 2>&1 | Out-String
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
        'FreshCampaignBaselineMatrix' {
            Invoke-Stage -Name 'FreshCampaignBaselineMatrix' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $freshCampaignBaselineMatrixScript 2>&1 | Out-String
                if ($LASTEXITCODE -ne 0) { throw "Five-instance fresh-campaign baseline matrix failed with exit code $LASTEXITCODE.`n$testOutput" }
                $testOutput
            }
        }
        'FreshCampaignSupplyBaseline' {
            Invoke-Stage -Name 'FreshCampaignSupplyBaseline' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $freshCampaignSupplyBaselineScript -Runs $FreshCampaignSupplyRuns 2>&1 | Out-String
                if ($LASTEXITCODE -ne 0) { throw "Fresh-Campaign paired Native supply baseline matrix failed with exit code $LASTEXITCODE.`n$testOutput" }
                $testOutput
            }
        }
        'FreshCampaignRecruitmentFallback' {
            Invoke-Stage -Name 'FreshCampaignRecruitmentFallback' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $freshCampaignRecruitmentFallbackScript -MaxAttempts $RecruitmentFallbackMaxAttempts 2>&1 | Out-String
                if ($LASTEXITCODE -ne 0) { throw "Fresh-Campaign Native recruitment fallback evaluation failed with exit code $LASTEXITCODE.`n$testOutput" }
                $testOutput
            }
        }
        'FreshCampaignLiveModelEvaluation' {
            Invoke-Stage -Name 'FreshCampaignLiveModelEvaluation' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $freshCampaignLiveModelEvaluationScript 2>&1 | Out-String
                if ($LASTEXITCODE -ne 0) { throw "Five-instance fresh-campaign real-model evaluation failed with exit code $LASTEXITCODE.`n$testOutput" }
                $testOutput
            }
        }
        'Protocol' {
            Invoke-Stage -Name 'Protocol' -Action {
                $fakeBridgeEvidence = Join-Path $harnessTempDirectory 'AgentHostProtocolContract'
                $fakeBridgeOutput = & $HarnessPowerShell -NoProfile -File (Join-Path $stageRoot 'Test-AgentHostProtocol.ps1') -HostDllPath $agentHostDllPath -EvidenceDirectory $fakeBridgeEvidence 2>&1 | Out-String
                if ($LASTEXITCODE -ne 0) { throw "Agent Host mailbox contract test failed with exit code $LASTEXITCODE.`n$fakeBridgeOutput" }
                $nativeProtocolOutput = & $HarnessPowerShell -NoProfile -File $protocolScript 2>&1 | Out-String
                $nativeProtocolExitCode = $LASTEXITCODE
                if ($nativeProtocolExitCode -ne 0) { throw "Agent protocol test failed with exit code $nativeProtocolExitCode.`n$nativeProtocolOutput" }
                [ordered]@{ hostMailboxContract = $fakeBridgeOutput; nativeProtocol = $nativeProtocolOutput; nativeHostHandshakes = '3 read-only state requests; checked same Native PID, MainHero, Clan, MainParty, time mode and unchanged Campaign fingerprint.' } | ConvertTo-Json -Depth 8
            }
        }
        'AgentHostProvider' {
            Invoke-Stage -Name 'AgentHostProvider' -Action {
                $originalProviderTimeout = [Environment]::GetEnvironmentVariable('CHRONICLE_LLM_TIMEOUT_SECONDS', 'Process')
                $useBoundedProviderSmoke = [string]::IsNullOrWhiteSpace($originalProviderTimeout)
                if ($useBoundedProviderSmoke) { [Environment]::SetEnvironmentVariable('CHRONICLE_LLM_TIMEOUT_SECONDS', '90', 'Process') }
                try {
                $mailboxEvidencePath = Join-Path $harnessTempDirectory 'AgentHostMailboxContract'
                $mailboxOutput = & $HarnessPowerShell -NoProfile -File (Join-Path $stageRoot 'Test-AgentHostProtocol.ps1') -HostDllPath $agentHostDllPath -EvidenceDirectory $mailboxEvidencePath 2>&1 | Out-String
                $mailboxExitCode = $LASTEXITCODE
                if ($mailboxExitCode -ne 0) { throw "Local Agent Host mailbox regression failed with exit code $mailboxExitCode.`n$mailboxOutput" }
                $providerEvidencePath = Join-Path $harnessTempDirectory 'AgentHostProvider'
                $providerArguments = @('-NoProfile', '-File', (Join-Path $stageRoot 'Test-AgentHostProvider.ps1'),
                    '-HostDllPath', $agentHostDllPath, '-EvidencePath', $providerEvidencePath, '-MaxOutputTokens', [string]$ProviderSmokeMaxOutputTokens)
                if ($AllowDshXdPoolFreeRoute) { $providerArguments += '-AllowDshXdPoolFreeRoute' }
                if ($AllowDshWorkBuddyGateway) { $providerArguments += '-AllowDshWorkBuddyGateway' }
                if ($ProbeDshFreeRouteWithMinimalChat) { $providerArguments += '-ProbeDshFreeRouteWithMinimalChat' }
                $providerOutput = & $HarnessPowerShell @providerArguments 2>&1 | Out-String
                $providerExitCode = $LASTEXITCODE
                if ($providerExitCode -ne 0) { throw "Local Agent Host provider contract/smoke failed with exit code $providerExitCode.`n$providerOutput" }
                [ordered]@{ mailboxRegression = $mailboxOutput; providerContractAndSmoke = $providerOutput } | ConvertTo-Json -Depth 8
                }
                finally {
                    if ($useBoundedProviderSmoke) { [Environment]::SetEnvironmentVariable('CHRONICLE_LLM_TIMEOUT_SECONDS', $originalProviderTimeout, 'Process') }
                }
            }
        }
        'AgentHostProviderHealth' {
            Invoke-Stage -Name 'AgentHostProviderHealth' -Action {
                $providerHealthEvidencePath = Join-Path $harnessTempDirectory 'AgentHostProviderHealth'
                $providerHealthArguments = @('-NoProfile', '-File', (Join-Path $stageRoot 'Test-AgentHostProvider.ps1'),
                    '-HostDllPath', $agentHostDllPath, '-EvidencePath', $providerHealthEvidencePath, '-HealthOnly')
                if ($AllowDshXdPoolFreeRoute) { $providerHealthArguments += '-AllowDshXdPoolFreeRoute' }
                if ($AllowDshWorkBuddyGateway) { $providerHealthArguments += '-AllowDshWorkBuddyGateway' }
                $providerHealthOutput = & $HarnessPowerShell @providerHealthArguments 2>&1 | Out-String
                $providerHealthExitCode = $LASTEXITCODE
                if ($providerHealthExitCode -ne 0) { throw "Read-only Agent Host provider health check failed with exit code $providerHealthExitCode.`n$providerHealthOutput" }
                $providerHealthOutput
            }
        }
        'AgentHostPackage' {
            Invoke-Stage -Name 'AgentHostPackage' -Action {
                $packageEvidencePath = Join-Path $harnessTempDirectory 'AgentHostPackage'
                $retainPackageForSameSessionRuntime = $Phase -in @('FreshStoryModeModelEvaluation', 'PersistentEycCampaign', 'AgentHostLifecycleEvaluation', 'AgentHostLifecycleCompletionEvaluation', 'BattleMissionHostNativeAiAutopilotProbe')
                $packageArguments = @('-ProjectPath', $agentHostProjectPath, '-EvidencePath', $packageEvidencePath)
                if ($retainPackageForSameSessionRuntime) { $packageArguments += '-RetainRuntimePackage' }
                try {
                    $packageOutput = & $HarnessPowerShell -NoProfile -File $agentHostPackageScript @packageArguments 2>&1 | Out-String
                    $packageExitCode = $LASTEXITCODE
                    $runtimeReceiptPath = Join-Path $packageEvidencePath 'AgentHostRuntimePackage.json'
                    if ($retainPackageForSameSessionRuntime -and (Test-Path -LiteralPath $runtimeReceiptPath -PathType Leaf)) {
                        $runtimeReceipt = Get-Content -LiteralPath $runtimeReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
                        $script:retainedAgentHostPackageRoot = [IO.Path]::GetFullPath([string]$runtimeReceipt.PackageRoot)
                        $script:retainedAgentHostExecutablePath = [IO.Path]::GetFullPath([string]$runtimeReceipt.RuntimeExecutablePath)
                        if (-not (Test-Path -LiteralPath $script:retainedAgentHostExecutablePath -PathType Leaf)) { throw 'Retained Agent Host runtime executable is missing after package verification.' }
                        [Environment]::SetEnvironmentVariable('CHRONICLE_AGENT_HOST_TEST_PATH', $script:retainedAgentHostExecutablePath, 'Process')
                    }
                    if ($packageExitCode -ne 0) { throw "Self-contained Agent Host package validation failed. Evidence: $packageOutput" }
                    if ($retainPackageForSameSessionRuntime -and [string]::IsNullOrWhiteSpace($script:retainedAgentHostExecutablePath)) { throw 'Fresh StoryMode runtime requires the self-contained package receipt and executable path.' }
                    $packageOutput
                }
                catch {
                    if ($script:retainedAgentHostPackageRoot) { Remove-RetainedAgentHostPackage $script:retainedAgentHostPackageRoot; $script:retainedAgentHostPackageRoot = $null; $script:retainedAgentHostExecutablePath = $null }
                    [Environment]::SetEnvironmentVariable('CHRONICLE_AGENT_HOST_TEST_PATH', $previousAgentHostTestPath, 'Process')
                    throw
                }
            }
        }
        'AgentHostSupplyEvaluation' {
            Invoke-Stage -Name 'AgentHostSupplyEvaluation' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File (Join-Path $stageRoot 'Test-AgentHostSupplyEvaluation.ps1') -Runs $AgentHostSupplyRuns 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "FreeLLMAPI-routed real-model Agent Host supply evaluation failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'AgentHostCampaignLoopEvaluation' {
            Invoke-Stage -Name 'AgentHostCampaignLoopEvaluation' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $agentHostCampaignLoopEvaluationScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "FreeLLMAPI-routed real-model Agent Host Campaign loop evaluation failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'CampaignActorThinkTrace' {
            Invoke-Stage -Name 'CampaignActorThinkTrace' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $campaignActorThinkTraceScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Read-only Native Campaign Actor Think trace failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'AgentHostVillageToolsQuestEvaluation' {
            Invoke-Stage -Name 'AgentHostVillageToolsQuestEvaluation' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $agentHostCampaignLoopEvaluationScript -VillageToolsQuest -FrameRate 5 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "FreeLLMAPI-routed real-model Agent Host VillageNeedsTools Quest evaluation failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'AgentHostEstablishClanGoalPlannerEvaluation' {
            Invoke-Stage -Name 'AgentHostEstablishClanGoalPlannerEvaluation' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $agentHostCampaignLoopEvaluationScript -EstablishYourClanGoalPlanner -PlannerSourceSaveName $StoryModePlannerSourceSaveName -FrameRate 5 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "FreeLLMAPI-routed read-only StoryMode Establish Your Clan objective planner evaluation failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'AgentHostEstablishClanAutonomyEvaluation' {
            Invoke-Stage -Name 'AgentHostEstablishClanAutonomyEvaluation' -Action {
                $originalProviderTimeout = [Environment]::GetEnvironmentVariable('CHRONICLE_LLM_TIMEOUT_SECONDS', 'Process')
                $useBoundedAutonomyRuntime = [string]::IsNullOrWhiteSpace($originalProviderTimeout)
                if ($useBoundedAutonomyRuntime) { [Environment]::SetEnvironmentVariable('CHRONICLE_LLM_TIMEOUT_SECONDS', '90', 'Process') }
                try {
                $testOutput = & $HarnessPowerShell -NoProfile -File $agentHostCampaignLoopEvaluationScript -EstablishYourClanAutonomyLoop -PlannerSourceSaveName $StoryModePlannerSourceSaveName -FrameRate 5 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "FreeLLMAPI-routed real-model StoryMode autonomy evaluation on a disposable existing-quest clone failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
                }
                finally {
                    if ($useBoundedAutonomyRuntime) { [Environment]::SetEnvironmentVariable('CHRONICLE_LLM_TIMEOUT_SECONDS', $originalProviderTimeout, 'Process') }
                }
            }
        }
        'AgentHostCaptivityRecoveryEvaluation' {
            Invoke-Stage -Name 'AgentHostCaptivityRecoveryEvaluation' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $agentHostCampaignLoopEvaluationScript -CaptivityRecoveryFromExisting -PlannerSourceSaveName $StoryModePlannerSourceSaveName -FrameRate 5 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "FreeLLMAPI-routed real-model recovery from existing StoryMode Captivity failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'AgentHostEstablishClanGoldSaleEvaluation' {
            Invoke-Stage -Name 'AgentHostEstablishClanGoldSaleEvaluation' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $agentHostCampaignLoopEvaluationScript -EstablishClanGoldSaleFromStoryMode -PlannerSourceSaveName $StoryModePlannerSourceSaveName -FrameRate 5 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "FreeLLMAPI-routed real-model StoryMode Gold objective sale evaluation failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'AgentHostBattleSimulationEvaluation' {
            Invoke-Stage -Name 'AgentHostBattleSimulationEvaluation' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $agentHostCampaignLoopEvaluationScript -BattleSimulationLoop -BattleSourceSaveName $BattleSimulationSourceSaveName -FrameRate 5 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "FreeLLMAPI-routed real-model Agent Host BattleSimulation evaluation failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'AgentHostBattleAndCaptivityEvaluation' {
            Invoke-Stage -Name 'AgentHostBattleAndCaptivityEvaluation' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $agentHostCampaignLoopEvaluationScript -BattleAndCaptivityLoop -BattleSourceSaveName $BattleSimulationSourceSaveName -FrameRate 5 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "FreeLLMAPI-routed real-model Native BattleSimulation/captivity recovery evaluation failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'AgentHostLifecycleEvaluation' {
            Invoke-Stage -Name 'AgentHostLifecycleEvaluation' -Action {
                try {
                    $testOutput = & $HarnessPowerShell -NoProfile -File $agentHostLifecycleEvaluationScript -Scenario $LifecycleScenario 2>&1 | Out-String
                    $testExitCode = $LASTEXITCODE
                    if ($testExitCode -ne 0) { throw "Game-owned Agent Host lifecycle test failed with exit code $testExitCode.`n$testOutput" }
                    $testOutput
                }
                finally {
                    if ($script:retainedAgentHostPackageRoot) { Remove-RetainedAgentHostPackage $script:retainedAgentHostPackageRoot }
                    $script:retainedAgentHostPackageRoot = $null
                    $script:retainedAgentHostExecutablePath = $null
                    [Environment]::SetEnvironmentVariable('CHRONICLE_AGENT_HOST_TEST_PATH', $previousAgentHostTestPath, 'Process')
                }
            }
        }
        'AgentHostLifecycleCompletionEvaluation' {
            Invoke-Stage -Name 'AgentHostLifecycleCompletionEvaluation' -Action {
                try {
                    $testOutput = & $HarnessPowerShell -NoProfile -File $agentHostLifecycleEvaluationScript -Scenario Complete -TimeoutSeconds 300 2>&1 | Out-String
                    $testExitCode = $LASTEXITCODE
                    if ($testExitCode -ne 0) { throw "Game-owned real-model Host completion test failed with exit code $testExitCode.`n$testOutput" }
                    $testOutput
                }
                finally {
                    if ($script:retainedAgentHostPackageRoot) { Remove-RetainedAgentHostPackage $script:retainedAgentHostPackageRoot }
                    $script:retainedAgentHostPackageRoot = $null
                    $script:retainedAgentHostExecutablePath = $null
                    [Environment]::SetEnvironmentVariable('CHRONICLE_AGENT_HOST_TEST_PATH', $previousAgentHostTestPath, 'Process')
                }
            }
        }
        'Observation' {
            Invoke-Stage -Name 'Observation' -Action {
                & $HarnessPowerShell -NoProfile -File $observationScript
                if ($LASTEXITCODE -ne 0) { throw "Agent observation test failed with exit code $LASTEXITCODE." }
            }
        }
        'CaptivityObservation' {
            Invoke-Stage -Name 'CaptivityObservation' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $captivityObservationScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native MainHero captivity observation test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'CaptivityOutcome' {
            Invoke-Stage -Name 'CaptivityOutcome' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $captivityOutcomeScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native MainHero captivity outcome test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'PrisonCaptivityOutcome' {
            Invoke-Stage -Name 'PrisonCaptivityOutcome' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $captivityOutcomeScript -CaptorContext Settlement 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native MainHero prison captivity outcome test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'EncounterSurrender' {
            Invoke-Stage -Name 'EncounterSurrender' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $encounterSurrenderScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native Encounter surrender/captivity test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'EncounterEscape' {
            Invoke-Stage -Name 'EncounterEscape' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $encounterEscapeScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native Encounter escape/outcome test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'JoinEncounterDefenders' {
            Invoke-Stage -Name 'JoinEncounterDefenders' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $joinEncounterScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native Join Encounter Help Defenders test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'JoinEncounterEligibility' {
            Invoke-Stage -Name 'JoinEncounterEligibility' -Action {
                foreach ($relationProfile in @('HelpAttackers', 'Neutral')) {
                    $testOutput = & $HarnessPowerShell -NoProfile -File $joinEncounterEligibilityScript -RelationProfile $relationProfile 2>&1 | Out-String
                    $testExitCode = $LASTEXITCODE
                    if ($testExitCode -ne 0) { throw "Native Join Encounter $relationProfile eligibility test failed with exit code $testExitCode.`n$testOutput" }
                    $testOutput
                }
            }
        }
        'JoinEncounterAbandonArmy' {
            Invoke-Stage -Name 'JoinEncounterAbandonArmy' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $joinEncounterAbandonArmyScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native Join Encounter Abandon Army test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'MovingArmyJoin' {
            Invoke-Stage -Name 'MovingArmyJoin' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $movingArmyJoinScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native unengaged Army encounter Join Army test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'JoinSiegeEvent' {
            Invoke-Stage -Name 'JoinSiegeEvent' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $joinSiegeEventScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native Join Siege Event test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'MapNotifications' {
            Invoke-Stage -Name 'MapNotifications' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $mapNotificationsScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native map notification observation test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'MapIncidentInputGuard' {
            Invoke-Stage -Name 'MapIncidentInputGuard' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $mapIncidentInputGuardScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native MapIncident movement guard test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'QuickInformation' {
            Invoke-Stage -Name 'QuickInformation' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $quickInformationScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native QuickInformation observation test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'SceneNotification' {
            Invoke-Stage -Name 'SceneNotification' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $sceneNotificationScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native SceneNotification observation test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'MissionLeave' {
            Invoke-Stage -Name 'MissionLeave' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $missionLeaveScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native Mission Leave runtime test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'VillageToolsDelivery' {
            Invoke-Stage -Name 'VillageToolsDelivery' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $villageToolsDeliveryScript -MaxDecisions $VillageToolsMaxDecisions 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Autonomous Native Village Tools delivery test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'Movement' {
            Invoke-Stage -Name 'Movement' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $movementScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Agent movement test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'Hold' {
            Invoke-Stage -Name 'Hold' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $holdScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native Hold behavior test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'MoveToPoint' {
            Invoke-Stage -Name 'MoveToPoint' -Action {
                & $HarnessPowerShell -NoProfile -File $moveToPointScript
                if ($LASTEXITCODE -ne 0) { throw "Agent point movement test failed with exit code $LASTEXITCODE." }
            }
        }
        'Recruitment' {
            Invoke-Stage -Name 'Recruitment' -Action {
                if ($RecruitmentBulkOnly) {
                    $testOutput = & $HarnessPowerShell -NoProfile -File $recruitmentScript -BulkOnly 2>&1 | Out-String
                }
                else {
                    $testOutput = & $HarnessPowerShell -NoProfile -File $recruitmentScript 2>&1 | Out-String
                }
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Agent recruitment test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'Rest' {
            Invoke-Stage -Name 'Rest' -Action {
                & $HarnessPowerShell -NoProfile -File $restScript
                if ($LASTEXITCODE -ne 0) { throw "Agent rest test failed with exit code $LASTEXITCODE." }
            }
        }
        'Pursuit' {
            Invoke-Stage -Name 'Pursuit' -Action {
                & $HarnessPowerShell -NoProfile -File $pursuitScript
                if ($LASTEXITCODE -ne 0) { throw "Agent pursuit test failed with exit code $LASTEXITCODE." }
            }
        }
        'EngageVisibility' {
            Invoke-Stage -Name 'EngageVisibility' -Action {
                $previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
                $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
                try {
                    $testOutput = & $HarnessPowerShell -NoProfile -File $pursuitScript -ProbeEngageVisibilityLoss -VisibilityProbeSeconds $VisibilityProbeSeconds -TimeoutSeconds 240 2>&1 | Out-String
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
                & $HarnessPowerShell -NoProfile -File $pursuitScript -ProbeConversation
                if ($LASTEXITCODE -ne 0) { throw "Agent conversation lifecycle test failed with exit code $LASTEXITCODE." }
            }
        }
        'QuestAcceptance' {
            Invoke-Stage -Name 'QuestAcceptance' -Action {
                & $HarnessPowerShell -NoProfile -File $pursuitScript -ProbeQuestAcceptance
                if ($LASTEXITCODE -ne 0) { throw "Agent Quest acceptance test failed with exit code $LASTEXITCODE." }
            }
        }
        'EscortVisibility' {
            Invoke-Stage -Name 'EscortVisibility' -Action {
                & $HarnessPowerShell -NoProfile -File $pursuitScript -ProbeEscortVisibilityLoss -VisibilityProbeSeconds 45
                if ($LASTEXITCODE -ne 0) { throw "Escort visibility probe failed with exit code $LASTEXITCODE." }
            }
        }
        'TavernMission' {
            Invoke-Stage -Name 'TavernMission' -Action {
                & $HarnessPowerShell -NoProfile -File $tavernMissionScript
                if ($LASTEXITCODE -ne 0) { throw "Native Tavern Mission entry test failed with exit code $LASTEXITCODE." }
            }
        }
        'TownCenterMission' {
            Invoke-Stage -Name 'TownCenterMission' -Action {
                & $HarnessPowerShell -NoProfile -File $townCenterMissionScript
                if ($LASTEXITCODE -ne 0) { throw "Native Town Center Mission test failed with exit code $LASTEXITCODE." }
            }
        }
        'SettlementOverlayConversation' {
            Invoke-Stage -Name 'SettlementOverlayConversation' -Action {
                & $HarnessPowerShell -NoProfile -File $settlementOverlayConversationScript -TargetSettlementId $TargetSettlementId -ApproachSettlementId $ApproachSettlementId
                if ($LASTEXITCODE -ne 0) { throw "Native Settlement overlay Conversation test failed with exit code $LASTEXITCODE." }
            }
        }
        'SettlementOverlayQuickTalk' {
            Invoke-Stage -Name 'SettlementOverlayQuickTalk' -Action {
                & $HarnessPowerShell -NoProfile -File $settlementOverlayConversationScript -TargetSettlementId $QuickTalkTargetSettlementId -ApproachSettlementId $QuickTalkTargetSettlementId -InteractionMode QuickTalk -ExpectedOutcome ConversationOnly
                if ($LASTEXITCODE -ne 0) { throw "Native Settlement overlay QuickConversation test failed with exit code $LASTEXITCODE." }
            }
        }
        'SettlementOverlayQuestAcceptance' {
            Invoke-Stage -Name 'SettlementOverlayQuestAcceptance' -Action {
                & $HarnessPowerShell -NoProfile -File $settlementOverlayConversationScript -TargetSettlementId $TargetSettlementId -ApproachSettlementId $ApproachSettlementId -ExpectedOutcome QuestAccepted
                if ($LASTEXITCODE -ne 0) { throw "Native Settlement overlay Issue Quest acceptance test failed with exit code $LASTEXITCODE." }
            }
        }
        'SettlementOverlayQuestGate' {
            Invoke-Stage -Name 'SettlementOverlayQuestGate' -Action {
                & $HarnessPowerShell -NoProfile -File $settlementOverlayConversationScript -ExpectedOutcome NativePreconditionBlocked
                if ($LASTEXITCODE -ne 0) { throw "Native Settlement overlay Issue Quest precondition gate test failed with exit code $LASTEXITCODE." }
            }
        }
        'SettlementOverlayQuickTalkIssueGateProbe' {
            Invoke-Stage -Name 'SettlementOverlayQuickTalkIssueGateProbe' -Action {
                & $HarnessPowerShell -NoProfile -File $settlementOverlayConversationScript -TargetSettlementId $QuickTalkTargetSettlementId -ApproachSettlementId $QuickTalkTargetSettlementId -InteractionMode QuickTalk -ExpectedOutcome IssueGateProbe
                if ($LASTEXITCODE -ne 0) { throw "Native Settlement QuickTalk Issue gate diagnostic failed with exit code $LASTEXITCODE." }
            }
        }
        'MapSettlementTargets' {
            Invoke-Stage -Name 'MapSettlementTargets' -Action {
                & $HarnessPowerShell -NoProfile -File $mapSettlementTargetsScript
                if ($LASTEXITCODE -ne 0) { throw "Native map settlement visibility and movement guard test failed with exit code $LASTEXITCODE." }
            }
        }
        'MainHeroSkills' {
            Invoke-Stage -Name 'MainHeroSkills' -Action {
                & $HarnessPowerShell -NoProfile -File $mainHeroSkillsScript
                if ($LASTEXITCODE -ne 0) { throw "Native MainHero skills observation test failed with exit code $LASTEXITCODE." }
            }
        }
        'CharacterDevelopment' {
            Invoke-Stage -Name 'CharacterDevelopment' -Action {
                & $HarnessPowerShell -NoProfile -File $characterDevelopmentScript
                if ($LASTEXITCODE -ne 0) { throw "Native MainHero Character Developer observation test failed with exit code $LASTEXITCODE." }
            }
        }
        'SpendSkillFocus' {
            Invoke-Stage -Name 'SpendSkillFocus' -Action {
                & $HarnessPowerShell -NoProfile -File $spendSkillFocusScript
                if ($LASTEXITCODE -ne 0) { throw "Native Character Developer Skill Focus transaction test failed with exit code $LASTEXITCODE." }
            }
        }
        'QuestJournal' {
            Invoke-Stage -Name 'QuestJournal' -Action {
                & $HarnessPowerShell -NoProfile -File $settlementOverlayConversationScript -TargetSettlementId village_V1_1 -ApproachSettlementId town_V1 -ExpectedOutcome QuestAccepted -ValidateQuestDetails
                if ($LASTEXITCODE -ne 0) { throw "Native Quest Journal details comparison failed with exit code $LASTEXITCODE." }
            }
        }
        'PartyRoster' {
            Invoke-Stage -Name 'PartyRoster' -Action {
                & $HarnessPowerShell -NoProfile -File $partyRosterScript
                if ($LASTEXITCODE -ne 0) { throw "Native MainParty roster observation test failed with exit code $LASTEXITCODE." }
            }
        }
        'MapPartyTargets' {
            Invoke-Stage -Name 'MapPartyTargets' -Action {
                & $HarnessPowerShell -NoProfile -File $mapPartyTargetsScript
                if ($LASTEXITCODE -ne 0) { throw "Native Map party target observation test failed with exit code $LASTEXITCODE." }
            }
        }
        'MapPartyQuestMarkers' {
            Invoke-Stage -Name 'MapPartyQuestMarkers' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $mapPartyQuestMarkersScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native map Party Issue marker observation test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'MapPartyQuestAcceptance' {
            Invoke-Stage -Name 'MapPartyQuestAcceptance' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $mapPartyQuestAcceptanceScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native map Lord Issue Quest acceptance test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'MapEscapeMenu' {
            Invoke-Stage -Name 'MapEscapeMenu' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $mapEscapeMenuScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native Map Escape-menu observe/close test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'MapInquiry' {
            Invoke-Stage -Name 'MapInquiry' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $mapInquiryScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native Map Inquiry observe/respond test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'AlleyLeaderInquiry' {
            Invoke-Stage -Name 'AlleyLeaderInquiry' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $alleyLeaderInquiryScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native Alley leader MultiSelection Inquiry test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'AlleyRosterManagement' {
            Invoke-Stage -Name 'AlleyRosterManagement' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $alleyRosterManagementScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native Alley PartyScreen roster test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'AlleyAbandonment' {
            Invoke-Stage -Name 'AlleyAbandonment' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $alleyAbandonmentScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native Alley abandonment menu test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'AlleyEntryMenu' {
            Invoke-Stage -Name 'AlleyEntryMenu' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $alleyEntryMenuScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native Alley entry/return menu test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'MissionSceneNavigation' {
            Invoke-Stage -Name 'MissionSceneNavigation' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $missionSceneNavigationScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native Mission scene discovery/navigation failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'AlleyVolunteerBranches' {
            Invoke-Stage -Name 'AlleyVolunteerBranches' -Action {
                $outputs = [System.Collections.Generic.List[string]]::new()
                foreach ($scenario in @('noVolunteers','availableVolunteers')) {
                    $testOutput = & $HarnessPowerShell -NoProfile -File $missionSceneNavigationScript -VolunteerScenario $scenario 2>&1 | Out-String
                    $testExitCode = $LASTEXITCODE
                    if ($testExitCode -ne 0) { throw "Alley volunteer branch '$scenario' failed with exit code $testExitCode.`n$testOutput" }
                    $outputs.Add("scenario=$scenario`n$testOutput")
                }
                $outputs -join "`n"
            }
        }
        'AlleyAttackYield' {
            Invoke-Stage -Name 'AlleyAttackYield' -Action {
                $outputs = [System.Collections.Generic.List[string]]::new()
                foreach ($scenario in @('noAttack','peacefulYield')) {
                    $testOutput = & $HarnessPowerShell -NoProfile -File $alleyAttackYieldScript -Scenario $scenario 2>&1 | Out-String
                    $testExitCode = $LASTEXITCODE
                    if ($testExitCode -ne 0) { throw "Alley attack branch '$scenario' failed with exit code $testExitCode.`n$testOutput" }
                    $outputs.Add("scenario=$scenario`n$testOutput")
                }
                $outputs -join "`n"
            }
        }
        'AlleyAttackFightMission' {
            Invoke-Stage -Name 'AlleyAttackFightMission' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $alleyAttackFightMissionScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native Alley Fight Mission entry/retreat failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'PersuasionDetails' {
            Invoke-Stage -Name 'PersuasionDetails' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $persuasionDetailsScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native Persuasion observation/option loop failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'MapPartyComposition' {
            Invoke-Stage -Name 'MapPartyComposition' -Action {
                & $HarnessPowerShell -NoProfile -File $mapPartyCompositionScript
                if ($LASTEXITCODE -ne 0) { throw "Native Map party composition/expanded tooltip comparison failed with exit code $LASTEXITCODE." }
            }
        }
        'MapArmyComposition' {
            Invoke-Stage -Name 'MapArmyComposition' -Action {
                & $HarnessPowerShell -NoProfile -File $mapPartyCompositionScript -ValidateArmyTooltip
                if ($LASTEXITCODE -ne 0) { throw "Native Army tooltip composition comparison failed with exit code $LASTEXITCODE." }
            }
        }
        'MapPartyBehavior' {
            Invoke-Stage -Name 'MapPartyBehavior' -Action {
                & $HarnessPowerShell -NoProfile -File $mapPartyBehaviorScript -ValidateArmyTooltip
                if ($LASTEXITCODE -ne 0) { throw "Native Map party behavior summary comparison failed with exit code $LASTEXITCODE." }
            }
        }
        'PartyUpgrade' {
            Invoke-Stage -Name 'PartyUpgrade' -Action {
                & $HarnessPowerShell -NoProfile -File $partyUpgradeScript
                if ($LASTEXITCODE -ne 0) { throw "Native MainParty PartyScreen upgrade transaction failed with exit code $LASTEXITCODE." }
            }
        }
        'PartyPrisonerRecruitment' {
            Invoke-Stage -Name 'PartyPrisonerRecruitment' -Action {
                & $HarnessPowerShell -NoProfile -File $partyPrisonerRecruitmentScript
                if ($LASTEXITCODE -ne 0) { throw "Native MainParty PartyScreen prisoner recruitment transaction failed with exit code $LASTEXITCODE." }
            }
        }
        'MissionInteraction' {
            Invoke-Stage -Name 'MissionInteraction' -Action {
                & $HarnessPowerShell -NoProfile -File $missionInteractionScript
                if ($LASTEXITCODE -ne 0) { throw "Native Mission Agent interaction regression failed with exit code $LASTEXITCODE." }
            }
        }
        'ArenaMasterInteraction' {
            Invoke-Stage -Name 'ArenaMasterInteraction' -Action {
                & $HarnessPowerShell -NoProfile -File $arenaMasterInteractionScript
                if ($LASTEXITCODE -ne 0) { throw "Native cross-culture ArenaMaster interaction regression failed with exit code $LASTEXITCODE." }
            }
        }
        'CompanionHiring' {
            Invoke-Stage -Name 'CompanionHiring' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $companionHiringScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native Wanderer companion-hiring flow failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'PartyRoles' {
            Invoke-Stage -Name 'PartyRoles' -Action {
                & $HarnessPowerShell -NoProfile -File $partyRolesScript
                if ($LASTEXITCODE -ne 0) { throw "Native PartyRole assignment/removal flow failed with exit code $LASTEXITCODE." }
            }
        }
        'InventoryNavigation' {
            Invoke-Stage -Name 'InventoryNavigation' -Action {
                & $HarnessPowerShell -NoProfile -File $inventoryNavigationScript
                if ($LASTEXITCODE -ne 0) { throw "Native Inventory navigation/clock boundary test failed with exit code $LASTEXITCODE." }
            }
        }
        'EquipmentTransactions' {
            Invoke-Stage -Name 'EquipmentTransactions' -Action {
                & $HarnessPowerShell -NoProfile -File $equipmentTransactionsScript
                if ($LASTEXITCODE -ne 0) { throw "Native MainHero equip/unequip transaction test failed with exit code $LASTEXITCODE." }
            }
        }
        'TradeTransactions' {
            Invoke-Stage -Name 'TradeTransactions' -Action {
                & $HarnessPowerShell -NoProfile -File $tradeTransactionsScript
                if ($LASTEXITCODE -ne 0) { throw "Native Town Trade transaction test failed with exit code $LASTEXITCODE." }
            }
        }
        'BarterTransactions' {
            Invoke-Stage -Name 'BarterTransactions' -Action {
                & $HarnessPowerShell -NoProfile -File $barterTransactionsScript
                if ($LASTEXITCODE -ne 0) { throw "Native ordinary Lord Barter transaction test failed with exit code $LASTEXITCODE." }
            }
        }
        'BarterContexts' {
            Invoke-Stage -Name 'BarterContexts' -Action {
                & $HarnessPowerShell -NoProfile -File $barterContextsScript
                if ($LASTEXITCODE -ne 0) { throw "Native Safe Passage Barter context test failed with exit code $LASTEXITCODE." }
                & $HarnessPowerShell -NoProfile -File $barterContextsScript -CancelOnly
                if ($LASTEXITCODE -ne 0) { throw "Native Safe Passage Cancel/encounter-menu test failed with exit code $LASTEXITCODE." }
                & $HarnessPowerShell -NoProfile -File $barterContextsScript -FightOnly
                if ($LASTEXITCODE -ne 0) { throw "Native Safe Passage Fight/encounter-menu test failed with exit code $LASTEXITCODE." }
            }
        }
        'BarterFightRoute' {
            Invoke-Stage -Name 'BarterFightRoute' -Action {
                & $HarnessPowerShell -NoProfile -File $barterContextsScript -FightOnly
                if ($LASTEXITCODE -ne 0) { throw "Native Safe Passage Fight-route test failed with exit code $LASTEXITCODE." }
            }
        }
        'BarterSafePassage' {
            Invoke-Stage -Name 'BarterSafePassage' -Action {
                & $HarnessPowerShell -NoProfile -File $barterContextsScript -ObserveExpiry
                if ($LASTEXITCODE -ne 0) { throw "Native Safe Passage offer/cooldown test failed with exit code $LASTEXITCODE." }
            }
        }
        'AgentLoop' {
            Invoke-Stage -Name 'AgentLoop' -Action {
                $providerOutput = & $HarnessPowerShell -NoProfile -File $agentModelProviderScript 2>&1 | Out-String
                $providerExitCode = $LASTEXITCODE
                if ($providerExitCode -ne 0) { throw "OpenAI-compatible provider protocol test failed with exit code $providerExitCode.`n$providerOutput" }
                $testOutput = & $HarnessPowerShell -NoProfile -File $agentLoopScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Agent decision loop test failed with exit code $testExitCode.`n$testOutput" }
                "Provider Protocol Stub:`n$providerOutput`nAgent Loop:`n$testOutput"
            }
        }
        'LiveModel' {
            Invoke-Stage -Name 'LiveModel' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $agentLiveModelLoopScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Live model Campaign loop failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'LiveModelArrival' {
            Invoke-Stage -Name 'LiveModelArrival' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $agentLiveModelLoopScript -ArrivalLoop 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Live-model Native arrival loop failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'LiveModelRecruitment' {
            Invoke-Stage -Name 'LiveModelRecruitment' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $agentLiveModelLoopScript -RecruitmentLoop 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Live-model Native volunteer recruitment loop failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'LiveModelSafePassageRecruitment' {
            Invoke-Stage -Name 'LiveModelSafePassageRecruitment' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $agentLiveModelLoopScript -RecruitmentLoop -RoadsideBanditNegotiationLoop 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Live-model roadside Safe Passage recruitment loop failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'CheckpointPersistence' {
            Invoke-Stage -Name 'CheckpointPersistence' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $agentCheckpointPersistenceScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native Campaign checkpoint persistence test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'LiveModelResume' {
            Invoke-Stage -Name 'LiveModelResume' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $agentLiveModelResumeScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Live-model Native Campaign checkpoint resume failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'LiveModelRuntimeResume' {
            Invoke-Stage -Name 'LiveModelRuntimeResume' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $agentLiveModelResumeScript -RuntimeOnlyResume 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Live-model in-process runtime restart failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'LiveModelActionRecovery' {
            Invoke-Stage -Name 'LiveModelActionRecovery' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $agentLiveModelResumeScript -CrashAfterRecruit 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Live-model post-action checkpoint recovery failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'CheckpointValidation' {
            Invoke-Stage -Name 'CheckpointValidation' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $agentCheckpointValidationScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Invalid Campaign checkpoint safety test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'RecruitmentBaseline' {
            Invoke-Stage -Name 'RecruitmentBaseline' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $agentEvaluationRecruitmentBaselineScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native recruitment evaluation baseline failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'MultiDaySupplyBaseline' {
            Invoke-Stage -Name 'MultiDaySupplyBaseline' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $multiDaySupplyBaselineScript -Repetitions $SupplyBaselineRepetitions -ProvisionAmount $SupplyBaselineProvisionAmount 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Multi-day Native supply baseline failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'LiveModelRecruitmentEvaluation' {
            Invoke-Stage -Name 'LiveModelRecruitmentEvaluation' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $agentEvaluationLiveModelRecruitmentScript 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Repeated real-model recruitment evaluation failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'LiveModelSupplyEvaluation' {
            Invoke-Stage -Name 'LiveModelSupplyEvaluation' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $agentEvaluationLiveModelSupplyScript -Runs $SupplyModelRuns 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Repeated real-model multi-day supply evaluation failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'TimeControlLoop' {
            Invoke-Stage -Name 'TimeControlLoop' -Action {
                $testOutput = & $HarnessPowerShell -NoProfile -File $agentLoopScript -TimeControlOnly 2>&1 | Out-String
                $testExitCode = $LASTEXITCODE
                if ($testExitCode -ne 0) { throw "Native time-control decision loop test failed with exit code $testExitCode.`n$testOutput" }
                $testOutput
            }
        }
        'BattleMissionFormationProbe' {
            Invoke-Stage -Name 'BattleMissionFormationProbe' -Action {
                $childOutputPath = Join-Path $harnessTempDirectory 'BattleMissionFormationProbeChild.log'
                $childOutput = & $HarnessPowerShell -NoProfile -File $battleMissionFormationProbeScript -SourceSaveName $BattleSimulationSourceSaveName -TimeoutSeconds 300 2>&1 | Out-String
                $childOutput | Set-Content -LiteralPath $childOutputPath -Encoding UTF8
                if ($LASTEXITCODE -ne 0) { throw "Native Battle Mission formation probe failed with exit code $LASTEXITCODE. Child output: $childOutput" }
                $childOutput
            }
        }
        'BattleMissionInputIsolationProbe' {
            Invoke-Stage -Name 'BattleMissionInputIsolationProbe' -Action {
                $childOutputPath = Join-Path $harnessTempDirectory 'BattleMissionInputIsolationProbeChild.log'
                $childOutput = & $HarnessPowerShell -NoProfile -File $battleMissionFormationProbeScript -SourceSaveName $BattleSimulationSourceSaveName -TimeoutSeconds 300 -ProbeDesktopInputIsolationOnly 2>&1 | Out-String
                $childOutput | Set-Content -LiteralPath $childOutputPath -Encoding UTF8
                if ($LASTEXITCODE -ne 0) { throw "Native Battle Mission desktop-input isolation probe failed with exit code $LASTEXITCODE. Child output: $childOutput" }
                $childOutput
            }
        }
        'BattleMissionControllerProbe' {
            Invoke-Stage -Name 'BattleMissionControllerProbe' -Action {
                $childOutputPath = Join-Path $harnessTempDirectory 'BattleMissionControllerProbeChild.log'
                $childOutput = & $HarnessPowerShell -NoProfile -File $battleMissionFormationProbeScript -SourceSaveName $BattleSimulationSourceSaveName -TimeoutSeconds 300 -ProbeMainAgentAiController 2>&1 | Out-String
                $childOutput | Set-Content -LiteralPath $childOutputPath -Encoding UTF8
                if ($LASTEXITCODE -ne 0) { throw "Native MainAgent AI-controller probe failed with exit code $LASTEXITCODE.`nChild output: $childOutput" }
                $childOutput
            }
        }
        'BattleMissionRtsCameraProbe' {
            Invoke-Stage -Name 'BattleMissionRtsCameraProbe' -Action {
                $childOutputPath = Join-Path $harnessTempDirectory 'BattleMissionRtsCameraProbeChild.log'
                $childOutput = & $HarnessPowerShell -NoProfile -File $battleMissionFormationProbeScript -SourceSaveName $BattleSimulationSourceSaveName -TimeoutSeconds 300 -ProbeMainAgentAiController -ProbeMainAgentRtsCameraBehavior 2>&1 | Out-String
                $childOutput | Set-Content -LiteralPath $childOutputPath -Encoding UTF8
                if ($LASTEXITCODE -ne 0) { throw "Native RTSCamera-pattern MainAgent AI probe failed with exit code $LASTEXITCODE.`nChild output: $childOutput" }
                $childOutput
            }
        }
        'BattleMissionMovementInputProbe' {
            Invoke-Stage -Name 'BattleMissionMovementInputProbe' -Action {
                $childOutputPath = Join-Path $harnessTempDirectory 'BattleMissionMovementInputProbeChild.log'
                $childOutput = & $HarnessPowerShell -NoProfile -File $battleMissionFormationProbeScript -SourceSaveName $BattleSimulationSourceSaveName -TimeoutSeconds 300 -ProbeBattleMovementInput 2>&1 | Out-String
                $childOutput | Set-Content -LiteralPath $childOutputPath -Encoding UTF8
                if ($LASTEXITCODE -ne 0) { throw "Native Battle movement input probe failed with exit code $LASTEXITCODE.`nChild output: $childOutput" }
                $childOutput
            }
        }
        'BattleMissionAgentNavigatorProbe' {
            Invoke-Stage -Name 'BattleMissionAgentNavigatorProbe' -Action {
                $childOutputPath = Join-Path $harnessTempDirectory 'BattleMissionAgentNavigatorProbeChild.log'
                $childOutput = & $HarnessPowerShell -NoProfile -File $battleMissionFormationProbeScript -SourceSaveName $BattleSimulationSourceSaveName -TimeoutSeconds 300 -ProbeBattleAgentNavigator 2>&1 | Out-String
                $childOutput | Set-Content -LiteralPath $childOutputPath -Encoding UTF8
                if ($LASTEXITCODE -ne 0) { throw "Native Battle AgentNavigator probe failed with exit code $LASTEXITCODE.`nChild output: $childOutput" }
                $childOutput
            }
        }
        'BattleMissionNativeAiHandoffProbe' {
            Invoke-Stage -Name 'BattleMissionNativeAiHandoffProbe' -Action {
                $childOutputPath = Join-Path $harnessTempDirectory 'BattleMissionNativeAiHandoffProbeChild.log'
                $childOutput = & $HarnessPowerShell -NoProfile -File $battleMissionFormationProbeScript -SourceSaveName $BattleSimulationSourceSaveName -TimeoutSeconds 300 -ProbeMainAgentNativeAiHandoff 2>&1 | Out-String
                $childOutput | Set-Content -LiteralPath $childOutputPath -Encoding UTF8
                if ($LASTEXITCODE -ne 0) { throw "Native Battle MainAgent AI handoff probe failed with exit code $LASTEXITCODE.`nChild output: $childOutput" }
                $childOutput
            }
        }
        'BattleMissionHostNativeAiAutopilotProbe' {
            Invoke-Stage -Name 'BattleMissionHostNativeAiAutopilotProbe' -Action {
                if ([string]::IsNullOrWhiteSpace($script:retainedAgentHostExecutablePath) -or -not (Test-Path -LiteralPath $script:retainedAgentHostExecutablePath -PathType Leaf)) {
                    throw 'The self-contained Agent Host runtime package was not retained for the same-session Native battle loop probe.'
                }
                $childOutputPath = Join-Path $harnessTempDirectory 'BattleMissionHostNativeAiAutopilotProbeChild.log'
                $battleProbeArguments = @('-SourceSaveName', $BattleSimulationSourceSaveName, '-TimeoutSeconds', '900', '-ProbeAgentHostNativeAiAutopilot')
                if ($BattleMissionSoloMainHeroProbe) { $battleProbeArguments += '-SoloMainHero' }
                $childOutput = & $HarnessPowerShell -NoProfile -File $battleMissionFormationProbeScript @battleProbeArguments 2>&1 | Out-String
                $childOutput | Set-Content -LiteralPath $childOutputPath -Encoding UTF8
                if ($LASTEXITCODE -ne 0) { throw "Production AgentHost Native battle autopilot probe failed with exit code $LASTEXITCODE.`nChild output: $childOutput" }
                $childOutput
            }
        }
        'BattleFixture' {
            Invoke-Stage -Name 'BattleFixture' -Action {
                $childOutputPath = Join-Path $harnessTempDirectory 'BattleFixtureChild.log'
                $childOutput = & $HarnessPowerShell -NoProfile -File $battleFixtureScript -LoadSaveName $BattleSimulationSourceSaveName 2>&1 | Out-String
                $childOutput | Set-Content -LiteralPath $childOutputPath -Encoding UTF8
                if ($LASTEXITCODE -ne 0) { throw "Battle fixture test failed with exit code $LASTEXITCODE. Child output: $childOutput" }
                $childOutput
            }
        }
        'PostBattle' {
            Invoke-Stage -Name 'PostBattle' -Action {
                $childOutputPath = Join-Path $harnessTempDirectory 'PostBattleChild.log'
                $childOutput = & $HarnessPowerShell -NoProfile -File $battleFixtureScript -LoadSaveName $BattleSimulationSourceSaveName -Scenario PostBattle -CaptureFrames 2>&1 | Out-String
                $childOutput | Set-Content -LiteralPath $childOutputPath -Encoding UTF8
                if ($LASTEXITCODE -ne 0) { throw "Postbattle test failed with exit code $LASTEXITCODE. Child output: $childOutput" }
                $childOutput
            }
        }
        'VisualCapture' {
            Invoke-Stage -Name 'VisualCapture' -Action {
                & $HarnessPowerShell -NoProfile -File $visualCaptureScript
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
