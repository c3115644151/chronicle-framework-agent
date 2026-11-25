#Requires -Version 7.0

# Ready diagnostics: battle probe expectations, ready diagnostics and tolerant event trace appends.
# Sources asserted here: Test-AgentBattleMissionFormationProbe.ps1, Test-AgentMapSettlementTargets.ps1, Test-AgentMapPartyTargets.ps1, Test-AgentMapPartyComposition.ps1, HarnessMapPartyIssueMarkerFixture.cs, Test-AgentMapPartyQuestMarkers.ps1, Test-AgentMapPartyQuestAcceptance.ps1, Test-AgentMapEscapeMenu.ps1, Test-AgentMapInquiry.ps1

$battleProbeScript = Get-Content -LiteralPath (Join-Path $stageRoot 'Test-AgentBattleMissionFormationProbe.ps1') -Raw -Encoding UTF8
if ($battleProbeScript -notmatch 'hostMissionResult\.missionModeAtEntry -eq ''Deployment''' -or
    $battleProbeScript -notmatch '\$soloNativeDeploymentTransitionVerified\s*=\s*\$hostMissionResult\.nativeDeploymentCompletedByNative' -or
    $battleProbeScript -notmatch 'missionModeObservedAtHostEntry') {
    throw 'Battle Mission probe expectations must use the Host first-read Native state and preserve observed mode transitions.'
}
if ($battleMissionAdapterSource -notmatch 'viewInitialized' -or
    $battleMissionAdapterSource -notmatch '"_gauntletLayer"' -or
    $battleMissionAdapterSource -notmatch 'nativeCanDeployWithOrderOfBattle' -or
    $battleMissionAdapterSource -notmatch 'CanPlayerSideDeployWithOrderOfBattle\(\)' -or
    $battleMissionAdapterSource -notmatch 'playerRoleControllerAvailable' -or
    $battleMissionAdapterSource -notmatch 'AssignPlayerRoleInTeamMissionController' -or
    $agentHostBattleSimulationLoopSource -notmatch '_deploymentUiStatusReads\+\+\s*>=\s*1') {
    throw 'Native Ready diagnostics must expose the Gauntlet view, original deployment eligibility, player-role controller, and lone-MainHero troop distinction; package simulation must cover delayed view readiness.'
}
if ($battleFixtureSource -notmatch 'IO\.File\]::Open\(\$script:VideoCaptureEventsPath' -or $battleFixtureSource -notmatch 'FileShare\]::ReadWrite' -or $battleFixtureSource -notmatch 'for \(\$attempt = 0; \$attempt -lt 6; \$attempt\+\+\)') { throw 'Battle event trace appends must tolerate transient readers/locks with bounded retry and shared access.' }
if ($developmentDoc -notmatch "Contract version:\s*$([regex]::Escape($contractVersion))") {
    throw "DEVELOPMENT.md is not synchronized with contract version $contractVersion."
}
foreach ($requiredText in @('DEVELOPMENT.md', 'DESIGN.md', 'SYSTEM_INVENTORY.md', 'TestResults/latest.json')) {
    if ($rootAgents -notmatch [regex]::Escape($requiredText)) {
        throw "Root AGENTS.md does not reference '$requiredText'."
    }
}
foreach ($forbiddenText in @('ChronicleFramework/README.md', 'ChronicleFramework/HARNESS.md', 'ChronicleFramework/TOOLCHAIN.md')) {
    if ($rootAgents -match [regex]::Escape($forbiddenText)) {
        throw "Root AGENTS.md still references removed document '$forbiddenText'."
    }
}
foreach ($requiredText in @('TestResults/latest.json', 'Computer Use', 'ContextState.json', 'MAINLINE.md', 'Original Mechanic Assumption Gate')) {
    if ($developmentDoc -notmatch [regex]::Escape($requiredText)) {
        throw "DEVELOPMENT.md is missing contract element '$requiredText'."
    }
}
foreach ($requiredScript in @('Agent-DecisionLoop.ps1', 'Agent-ProviderBudget.ps1', 'Agent-SaveMetadata.ps1', 'Test-AgentSaveMetadata.ps1', 'Test-AgentLoop.ps1', 'Test-AgentLoopProvider.ps1', 'Test-AgentOpenAICompatibleProvider.ps1', 'Get-FreeLLMAPIProfile.ps1', 'Test-AgentLiveModelLoop.ps1', 'Test-AgentCheckpointPersistence.ps1', 'Test-AgentEycObjectiveCheckpointReadback.ps1', 'Test-AgentLiveModelResume.ps1', 'Test-AgentVillageToolsProvider.ps1', 'Test-AgentVillageToolsDelivery.ps1', 'Test-AgentBattleFixture.ps1', 'Test-AgentBattleMissionFormationProbe.ps1', 'Test-AgentVisualCapture.ps1', 'AgentMissionInputPatch.cs', 'Test-AgentTavernMission.ps1', 'Test-AgentTownCenterMission.ps1', 'Test-AgentMissionInteraction.ps1', 'AgentMissionInteraction.cs', 'Test-AgentCompanionHiring.ps1', 'AgentPartyRoleAdapter.cs', 'Test-AgentPartyRoles.ps1', 'AgentInventoryStateAdapter.cs', 'AgentTradeAdapter.cs', 'HarnessEquipmentModifierFixture.cs', 'Test-AgentInventoryNavigation.ps1', 'Test-AgentEquipmentTransactions.ps1', 'Test-AgentTradeTransactions.ps1', 'Test-AgentSettlementOverlayConversation.ps1', 'Test-AgentFreshCampaign.ps1', 'Test-AgentSupport.ps1', 'Test-AgentMoveToPoint.ps1', 'Test-AgentCharacterDevelopment.ps1', 'Test-AgentSpendSkillFocus.ps1', 'Test-AgentPartyRoster.ps1', 'AgentPartyScreenAdapter.cs', 'AgentPartyUpgradeAdapter.cs', 'Test-AgentPartyUpgrade.ps1', 'AgentPartyPrisonerRecruitmentAdapter.cs', 'Test-AgentPartyPrisonerRecruitment.ps1', 'Test-AgentJoinEncounterEligibility.ps1', 'Test-AgentJoinEncounterAbandonArmy.ps1', 'Test-AgentMovingArmyJoin.ps1', 'Test-AgentJoinSiegeEvent.ps1', 'HarnessSiegeJoinFixture.cs', 'HarnessVideoCapture.ps1', 'Prune-TestResults.ps1', 'Set-ContextFocus.ps1')) {
    if (-not (Test-Path ((Resolve-SourceArtifact $requiredScript)))) { throw "Agent loop harness script is missing: $requiredScript" }
}
if ($harnessScript -notmatch "'EycObjectiveCheckpointReadback' \{ @\('Preflight', 'EycObjectiveCheckpointReadback'\) \}" -or
    [regex]::Matches($harnessScript, "(?m)^Invoke-Stage -Name 'EycObjectiveCheckpointReadback' -Action \{").Count -ne 1 -or
    $harnessScript -match "'All' \{[^\r\n]*'EycObjectiveCheckpointReadback'" -or
    $eycObjectiveCheckpointReadbackSource -notmatch "agentCheckpointGet" -or
    $eycObjectiveCheckpointReadbackSource -notmatch "eycObjectiveAttemptMemoryV1" -or
    $eycObjectiveCheckpointReadbackSource -notmatch "CampaignInstanceMatched" -or
    $eycObjectiveCheckpointReadbackSource -notmatch "ObjectiveAttemptCount" -or
    $eycObjectiveCheckpointReadbackSource -notmatch "SourceSaveUnchanged" -or
    $eycObjectiveCheckpointReadbackSource -notmatch "ProviderCalls = 0" -or
    $eycObjectiveCheckpointReadbackSource -notmatch "ModelCostCny = 0" -or
    $eycObjectiveCheckpointReadbackSource -notmatch "questDetails" -or
    $eycObjectiveCheckpointReadbackSource -notmatch "JournalObjectives" -or
    $eycObjectiveCheckpointReadbackSource -notmatch "ObjectiveAttemptEntries" -or
    $eycObjectiveCheckpointReadbackSource -notmatch "CompanionSearchMemoryPropertyPresent" -or
    $eycObjectiveCheckpointReadbackSource -notmatch "UnaffordableHeroCount" -or
    $eycObjectiveCheckpointReadbackSource -notmatch "UnaffordableHeroesSuppressedAtCurrentGold" -or
    $eycObjectiveCheckpointReadbackSource -notmatch "PSObject.Properties\['unaffordableHeroes'\]" -or
    $eycObjectiveCheckpointReadbackSource -notmatch "NativeParty" -or
    $eycObjectiveCheckpointReadbackSource -notmatch "NativeClan" -or
    $eycObjectiveCheckpointReadbackSource -notmatch "NativeLocation" -or
    $eycObjectiveCheckpointReadbackSource -notmatch "NativeTimeControlMode" -or
    $eycObjectiveCheckpointReadbackSource -notmatch "MainPartyIsMoving") {
    throw 'The EYC checkpoint readback must be a dedicated opt-in Native-only phase, verify saved attempt data, original Journal progress, location/movement/time, MainParty capacity, Clan state and identity, preserve the source save, and make no model call.'
}
if (-not (Test-Path (Join-Path $stageRoot 'Test-AgentMapSettlementTargets.ps1'))) { throw 'MapSettlementTargets regression script is missing.' }
foreach ($barterPath in @('AgentBarterAdapter.cs', 'AgentBarterViewCapture.cs', 'Test-AgentBarterTransactions.ps1')) {
    if (-not (Test-Path ((Resolve-SourceArtifact $barterPath)))) { throw "Native Barter implementation/test file is missing: $barterPath" }
}
foreach ($barterContextPath in @('Test-AgentSafePassageBarterContext.ps1', 'HarnessSafePassageFixture.cs')) {
    if (-not (Test-Path ((Resolve-SourceArtifact $barterContextPath)))) { throw "Safe Passage context test/fixture file is missing: $barterContextPath" }
}
if (-not (Test-Path (Join-Path $stageRoot 'Test-AgentMapPartyTargets.ps1'))) { throw 'MapPartyTargets regression script is missing.' }
if (-not (Test-Path (Join-Path $stageRoot 'Test-AgentMapPartyComposition.ps1'))) { throw 'MapPartyComposition regression script is missing.' }
if (-not (Test-Path (Join-Path $modRoot 'HarnessMapPartyIssueMarkerFixture.cs')) -or -not (Test-Path (Join-Path $stageRoot 'Test-AgentMapPartyQuestMarkers.ps1'))) { throw 'MapPartyQuestMarkers requires its Native Issue fixture and visual-capture regression script.' }
if (-not (Test-Path (Join-Path $stageRoot 'Test-AgentMapPartyQuestAcceptance.ps1'))) { throw 'MapPartyQuestAcceptance requires its standalone map-party Issue-to-Quest regression script.' }
if (-not (Test-Path (Join-Path $stageRoot 'Test-AgentMapEscapeMenu.ps1'))) { throw 'MapEscapeMenu requires its standalone Native overlay observe/close regression script.' }
if (-not (Test-Path (Join-Path $stageRoot 'Test-AgentMapInquiry.ps1'))) { throw 'MapInquiry requires its standalone Native active-Inquiry observe/respond regression script.' }
if ($harnessScript -notmatch "'MapPartyQuestMarkers'\s*\{\s*@\('Preflight', 'Build', 'MapPartyQuestMarkers'\)" -or $harnessScript -notmatch "Invoke-Stage -Name 'MapPartyQuestMarkers'" -or $harnessScript -notmatch 'Test-AgentMapPartyQuestMarkers\.ps1') { throw 'MapPartyQuestMarkers must remain a separate opt-in Native observation phase with Preflight and Build.' }
